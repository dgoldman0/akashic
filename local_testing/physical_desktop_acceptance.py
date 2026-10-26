#!/usr/bin/env python3
"""Run the canonical physical Desktop journey under resource and source guards.

The supervisor starts one fresh process group running
`akashic_tui.py accept --backend simulator` with the native semantic executor;
--backend hybrid runs the same journey in MegaPad's hybrid mode instead.
It stops the group at the 900-second watchdog or at 3.5 GiB aggregate RSS. It
binds the run to clean Akashic and MegaPad trees, the viewer font, and the
native extension, and rejects source changes made during the run. The journey
itself is the unmodified canonical one in `rich_terminal_desktop_acceptance.py`.
This creates its own server and window; it never attaches to an existing viewer.

With --applet NAME it instead runs Desk holding only that applet, with the
applet's journey from `rich_terminal_applet_journeys.py`, to check work on
one applet before the canonical journey runs across all of them.  That is a
development check, so the trees need not be clean; their state, including a
digest of uncommitted changes, is recorded and must not change during the run.

With --terminal-link-pace BYTES_PER_SECOND:FRAME_US the hosted terminal takes
the guest's bytes no faster than that rate, as a real serial link would, so a
run can see frames keep going while a picture uploads.

With --screen-profile the simulator also records what each PRESENT carries
and the guest words each step runs under, in the evidence's screen-profile
directory, which local_testing/screen_change_profile.py reads.  With --shadow-check
the image turns on the shadow check of the rich frame's shortcuts at boot
(tui/rich-terminal/frame-shadow.f): each shortcut also runs its full path
and compares, and the run fails on any difference, or when the check was
not on after all.  With --every-frame-checks the image turns every check
on at boot, once Desk has loaded (tui/check-mode.f), and the run fails when
they were not on after all.  With --safe-mode it boots in safe mode, and
fails when the guest did not report it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import tempfile
import time

WATCHDOG_SECONDS = 900
RSS_STOP_BYTES = 3584 * 1024**2  # Aggregate processes; below the 4 GiB gate.
KIND = "canonical-physical-desktop-acceptance"
APPLET_KIND = "physical-desk-single-applet-check"
# A single applet's journey is short.  Its own timeout ends a stalled run
# well inside the outer watchdog, so the runner still writes its diagnostics.
APPLET_TIMEOUT_SECONDS = 300
APPLETS = ("pad", "fexp", "daybook", "streams", "agent", "soundlab", "observatory",
           "small-terminal", "photo", "damaged")


def write_json(path: Path, value) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024**2), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_binding(root: Path, *, clean: bool = True) -> dict:
    """ROOT's revision, and for a development check its uncommitted state."""

    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(root), *arguments], text=True)
    status = git("status", "--porcelain")
    if status and clean:
        raise RuntimeError(f"commit measured sources before acceptance: {root}\n{status}")
    binding = {"root": str(root), "head": git("rev-parse", "HEAD").strip(),
               "tree": git("rev-parse", "HEAD^{tree}").strip(), "status": status}
    if status:
        changes = hashlib.sha256(git("diff", "HEAD", "--binary").encode())
        for line in status.splitlines():
            if line.startswith("?? "):
                path = root / line[3:]
                changes.update(line.encode())
                if path.is_file():
                    changes.update(path.read_bytes())
        binding["uncommitted_sha256"] = changes.hexdigest()
    return binding


def owned_rss(group: int) -> int:
    """Bound the whole new process group, conservatively counting shared pages."""
    total = 0
    page_size = os.sysconf("SC_PAGE_SIZE")
    for directory in Path("/proc").iterdir():
        if not directory.name.isdecimal():
            continue
        try:
            fields = (directory / "stat").read_text().rsplit(")", 1)[1].split()
            if int(fields[2]) == group or int(directory.name) == os.getpid():
                total += int((directory / "statm").read_text().split()[1]) * page_size
        except (OSError, ValueError, IndexError):
            continue
    return total


def stop_group(process) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        process.poll()
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=10)


def child(args) -> int:
    resource.setrlimit(resource.RLIMIT_AS, (RSS_STOP_BYTES, RSS_STOP_BYTES))
    sys.path[:0] = [str(args.megapad_root), str(args.akashic_root / "local_testing")]
    import akashic_tui as tui
    import _megaforth_native as extension
    from rich_terminal.font_set import discover_fallback_fonts, discover_style_fonts

    if tui.DESKTOP_ACCEPTANCE_TIMEOUT != WATCHDOG_SECONDS:
        raise RuntimeError("review the changed canonical watchdog before using this launcher")
    clean = args.applet is None
    profile = "desktop-apt1" if clean else f"desktop-apt1-{args.applet}"
    bindings = {"akashic": git_binding(args.akashic_root, clean=clean),
                "megapad": git_binding(args.megapad_root, clean=clean)}
    extension_path = Path(extension.__file__).resolve()
    write_json(args.artifact / "bindings.json", {
        "kind": KIND if clean else APPLET_KIND, **bindings, "profile": profile,
        "backend": args.backend,
        "executor": "native", "launcher_sha256": sha256(Path(__file__)),
        "font": str(args.font), "font_sha256": sha256(args.font),
        "fallback_fonts": [{"path": str(path), "sha256": sha256(path)}
                           for path in discover_fallback_fonts()],
        "style_fonts": {name: {"path": str(path), "sha256": sha256(path)}
                        for name, path in discover_style_fonts(args.font).items()},
        "native_extension": str(extension_path), "native_sha256": sha256(extension_path),
        "socket": str(args.socket), "font_size": 18, "action_delay_seconds": 0.75,
        "hold_seconds": 10, "watchdog_seconds": WATCHDOG_SECONDS,
        "terminal_link_pace": args.terminal_link_pace,
        "screen_profile": args.screen_profile,
        "shadow_check": args.shadow_check,
        "every_frame_checks": args.every_frame_checks,
        "safe_mode": args.safe_mode,
    })
    sys.argv = [str(args.akashic_root / "local_testing/akashic_tui.py"),
                "accept", "--profile", profile, "--backend", args.backend,
                "--output", str(args.artifact / "desktop.img"),
                "--artifact-root", str(args.artifact / "evidence"),
                "--socket", str(args.socket),
                "--timeout", str(WATCHDOG_SECONDS if clean else APPLET_TIMEOUT_SECONDS),
                "--font", str(args.font), "--font-size", "18", "--action-delay", "0.75",
                "--hold-seconds", "10"]
    if args.terminal_link_pace is not None:
        sys.argv += ["--terminal-link-pace", args.terminal_link_pace]
    if args.screen_profile:
        sys.argv.append("--screen-profile")
    if args.shadow_check:
        sys.argv.append("--shadow-check")
    if args.every_frame_checks:
        sys.argv.append("--every-frame-checks")
    if args.safe_mode:
        sys.argv.append("--safe-mode")
    result = tui.main()
    after = {"akashic": git_binding(args.akashic_root, clean=clean),
             "megapad": git_binding(args.megapad_root, clean=clean)}
    if after != bindings:
        raise RuntimeError("paired source revisions changed during physical acceptance")
    return result


def supervise(args) -> int:
    for root in (args.akashic_root, args.megapad_root):
        git_binding(root, clean=args.applet is None)
    if not args.font.is_file():
        raise ValueError("--font must name an existing physical viewer font")
    if os.environ.get("SDL_VIDEODRIVER", "").lower() in ("dummy", "offscreen"):
        raise ValueError("physical capture cannot use dummy/offscreen SDL; select the real display")
    args.output_parent.mkdir(parents=True, exist_ok=True)
    artifact = Path(tempfile.mkdtemp(prefix="physical-desktop-", dir=args.output_parent))
    socket_root = Path(tempfile.mkdtemp(prefix="rich-physical-desktop-"))
    command = [sys.executable, str(Path(__file__).resolve()), "--child",
               "--akashic-root", str(args.akashic_root), "--megapad-root", str(args.megapad_root),
               "--font", str(args.font), "--artifact", str(artifact),
               "--socket", str(socket_root / "session.sock"), "--backend", args.backend]
    if args.applet is not None:
        command += ["--applet", args.applet]
    if args.terminal_link_pace is not None:
        command += ["--terminal-link-pace", args.terminal_link_pace]
    if args.screen_profile:
        command.append("--screen-profile")
    if args.shadow_check:
        command.append("--shadow-check")
    if args.every_frame_checks:
        command.append("--every-frame-checks")
    if args.safe_mode:
        command.append("--safe-mode")
    kind = KIND if args.applet is None else f"{APPLET_KIND}: {args.applet}"
    if args.backend != "simulator":
        kind += f" ({args.backend})"
    if args.terminal_link_pace is not None:
        kind += f", paced link {args.terminal_link_pace}"
    if args.screen_profile:
        kind += ", screen profile"
    if args.shadow_check:
        kind += ", shadow check"
    if args.every_frame_checks:
        kind += ", every-frame checks"
    if args.safe_mode:
        kind += ", safe mode"
    environment = dict(os.environ, MEGAPAD_ROOT=str(args.megapad_root),
                       MEGAFORTH_EXECUTOR="native")
    environment.pop("MEGAFORTH_NATIVE_PROFILE", None)
    started = time.monotonic()
    peak = 0
    stop_reason = None
    print(f"{kind}\nArtifacts: {artifact}\nSocket: {socket_root / 'session.sock'}", flush=True)
    with (artifact / "run.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   env=environment, start_new_session=True)
        try:
            while process.poll() is None:
                peak = max(peak, owned_rss(process.pid))
                if peak >= RSS_STOP_BYTES:
                    stop_reason = "aggregate_rss_limit"
                    break
                if time.monotonic() - started >= WATCHDOG_SECONDS:
                    stop_reason = "900_second_outer_watchdog"
                    break
                time.sleep(0.25)
        finally:
            stop_group(process)
    write_json(artifact / "supervisor.json", {
        "kind": kind, "returncode": process.returncode, "stop_reason": stop_reason,
        "elapsed_seconds": time.monotonic() - started, "peak_aggregate_rss_bytes": peak,
        "rss_stop_bytes": RSS_STOP_BYTES, "watchdog_seconds": WATCHDOG_SECONDS,
        "socket_directory": str(socket_root),
        "note": "One canonical client/server process group, no test workers; outer budget includes image build.",
    })
    passed = process.returncode == 0 and stop_reason is None
    if passed and args.shadow_check and not shadow_check_was_on(artifact):
        print("Shadow check: asked for, but the guest did not report it on", flush=True)
        passed = False
    if passed and args.every_frame_checks and not every_frame_checks_were_on(artifact):
        print("Every-frame checks: asked for, but the guest did not report them on",
              flush=True)
        passed = False
    if passed and args.safe_mode and safe_mode_reason(artifact) != "boot":
        print("Safe mode: asked for at boot, but the guest did not report it",
              flush=True)
        passed = False
    return 0 if passed else 1


def shadow_check_was_on(artifact: Path) -> bool:
    """Whether the run's final guest diagnostics show the shadow check on."""

    try:
        diagnostics = json.loads(
            (artifact / "evidence" / "final-guest-diagnostics.json").read_text()
        )
    except (OSError, ValueError):
        return False
    record = diagnostics.get("shadow_check") or {}
    return bool(record.get("on")) and not record.get("unavailable")


def every_frame_checks_were_on(artifact: Path) -> bool:
    """Whether the run's final guest diagnostics show every-frame checks on."""

    try:
        diagnostics = json.loads(
            (artifact / "evidence" / "final-guest-diagnostics.json").read_text()
        )
    except (OSError, ValueError):
        return False
    record = diagnostics.get("check_mode") or {}
    return bool(record.get("every_frame")) and not record.get("unavailable")


def safe_mode_reason(artifact: Path) -> str | None:
    """Why the run's final guest diagnostics show safe mode on, or None."""

    try:
        diagnostics = json.loads(
            (artifact / "evidence" / "final-guest-diagnostics.json").read_text()
        )
    except (OSError, ValueError):
        return None
    return (diagnostics.get("check_mode") or {}).get("safe_mode")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--akashic-root", required=True, type=Path)
    parser.add_argument("--megapad-root", required=True, type=Path)
    parser.add_argument("--font", required=True, type=Path)
    parser.add_argument("--output-parent", type=Path)
    parser.add_argument("--applet", choices=APPLETS,
                        help="run Desk with only this applet, the small-terminal "
                             "check of Desk with Pad, or the photo or damaged-picture "
                             "check of Desk with File Explorer, as a development check")
    parser.add_argument("--backend", choices=("simulator", "hybrid"), default="simulator",
                        help="semantic backend: the simulator, or MegaPad's hybrid mode")
    parser.add_argument("--terminal-link-pace", metavar="BYTES_PER_SECOND:FRAME_US",
                        help="pace the link to the hosted terminal, for testing")
    parser.add_argument("--shadow-check", action="store_true",
                        help="turn on the shadow check of the rich frame's "
                             "shortcuts at boot, and fail on any difference")
    parser.add_argument("--every-frame-checks", action="store_true",
                        help="run every check on every frame instead of "
                             "normal mode")
    parser.add_argument("--safe-mode", action="store_true",
                        help="boot in safe mode: every frame takes the full "
                             "path, with every check")
    parser.add_argument("--screen-profile", action="store_true",
                        help="record what each PRESENT carries and the guest words each "
                             "step runs under, in the evidence's screen-profile "
                             "directory (local_testing/screen_change_profile.py)")
    parser.add_argument("--child", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--artifact", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--socket", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    for name in ("akashic_root", "megapad_root", "font", "output_parent", "artifact", "socket"):
        value = getattr(args, name)
        if value is not None:
            setattr(args, name, value.expanduser().resolve())
    if args.child:
        if args.artifact is None or args.socket is None:
            parser.error("internal child requires --artifact and --socket")
        return child(args)
    if args.output_parent is None:
        parser.error("--output-parent is required")
    return supervise(args)


if __name__ == "__main__":
    raise SystemExit(main())
