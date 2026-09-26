#!/usr/bin/env python3
"""Run the canonical physical Desktop journey under resource and source guards.

The supervisor starts one fresh process group running
`akashic_tui.py accept --backend simulator` with the native semantic executor.
It stops the group at the 900-second watchdog or at 3.5 GiB aggregate RSS. It
binds the run to clean Akashic and MegaPad trees, the viewer font, and the
native extension, and rejects source changes made during the run. The journey
itself is the unmodified canonical one in `rich_terminal_desktop_acceptance.py`.
This creates its own server and window; it never attaches to an existing viewer.
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


def git_binding(root: Path) -> dict:
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(root), *arguments], text=True)
    status = git("status", "--porcelain")
    if status:
        raise RuntimeError(f"commit measured sources before acceptance: {root}\n{status}")
    return {"root": str(root), "head": git("rev-parse", "HEAD").strip(),
            "tree": git("rev-parse", "HEAD^{tree}").strip(), "status": status}


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

    if tui.DESKTOP_ACCEPTANCE_TIMEOUT != WATCHDOG_SECONDS:
        raise RuntimeError("review the changed canonical watchdog before using this launcher")
    bindings = {"akashic": git_binding(args.akashic_root),
                "megapad": git_binding(args.megapad_root)}
    extension_path = Path(extension.__file__).resolve()
    write_json(args.artifact / "bindings.json", {
        "kind": KIND, **bindings, "profile": "desktop-apt1", "backend": "simulator",
        "executor": "native", "launcher_sha256": sha256(Path(__file__)),
        "font": str(args.font), "font_sha256": sha256(args.font),
        "native_extension": str(extension_path), "native_sha256": sha256(extension_path),
        "socket": str(args.socket), "font_size": 18, "action_delay_seconds": 0.75,
        "hold_seconds": 10, "watchdog_seconds": WATCHDOG_SECONDS,
    })
    sys.argv = [str(args.akashic_root / "local_testing/akashic_tui.py"),
                "accept", "--profile", "desktop-apt1", "--backend", "simulator",
                "--output", str(args.artifact / "desktop.img"),
                "--artifact-root", str(args.artifact / "evidence"),
                "--socket", str(args.socket), "--timeout", str(WATCHDOG_SECONDS),
                "--font", str(args.font), "--font-size", "18", "--action-delay", "0.75",
                "--hold-seconds", "10"]
    result = tui.main()
    after = {"akashic": git_binding(args.akashic_root),
             "megapad": git_binding(args.megapad_root)}
    if after != bindings:
        raise RuntimeError("paired source revisions changed during physical acceptance")
    return result


def supervise(args) -> int:
    for root in (args.akashic_root, args.megapad_root):
        git_binding(root)
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
               "--socket", str(socket_root / "session.sock")]
    environment = dict(os.environ, MEGAPAD_ROOT=str(args.megapad_root),
                       MEGAFORTH_EXECUTOR="native")
    environment.pop("MEGAFORTH_NATIVE_PROFILE", None)
    started = time.monotonic()
    peak = 0
    stop_reason = None
    print(f"{KIND}\nArtifacts: {artifact}\nSocket: {socket_root / 'session.sock'}", flush=True)
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
        "kind": KIND, "returncode": process.returncode, "stop_reason": stop_reason,
        "elapsed_seconds": time.monotonic() - started, "peak_aggregate_rss_bytes": peak,
        "rss_stop_bytes": RSS_STOP_BYTES, "watchdog_seconds": WATCHDOG_SECONDS,
        "socket_directory": str(socket_root),
        "note": "One canonical client/server process group, no test workers; outer budget includes image build.",
    })
    return 0 if process.returncode == 0 and stop_reason is None else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--akashic-root", required=True, type=Path)
    parser.add_argument("--megapad-root", required=True, type=Path)
    parser.add_argument("--font", required=True, type=Path)
    parser.add_argument("--output-parent", type=Path)
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
