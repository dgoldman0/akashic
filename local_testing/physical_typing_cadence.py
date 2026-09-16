#!/usr/bin/env python3
"""Measure individual typing through the ordinary Desktop and physical viewer.

The first character is isolated; the rest arrive at five characters/second.
Each run owns one fresh source-mode image, socket, session, and X11 window.
Trace records distinguish intended event times, actual dispatch, RPC acceptance,
composition, physical flip/ACK, and exact visible text. This typing benchmark
is separate from full Desktop functional acceptance.
"""
from __future__ import annotations

import argparse
from types import SimpleNamespace
import hashlib
import json
import os
from pathlib import Path
import resource
import runpy
import signal
import subprocess
import sys
import tempfile
import time
import traceback

WATCHDOG_SECONDS = 900
RSS_STOP_BYTES = 3584 * 1024**2  # Aggregate processes; below the 4 GiB gate.
KIND = "physical-desktop-typing-cadence"


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024**2), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_binding(root):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(root), *args], text=True)
    status = git("status", "--porcelain")
    if status:
        raise RuntimeError(f"commit the measured sources before profiling: {root}\n{status}")
    return {"root": str(root), "head": git("rev-parse", "HEAD").strip(),
            "tree": git("rev-parse", "HEAD^{tree}").strip(), "status": status}


def owned_rss(group):
    """Linux aggregate RSS; conservatively counts shared pages in each process."""
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


def stop_group(process):
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


def supervise(args):
    for root in (args.akashic_root, args.megapad_root):
        git_binding(root)
    if not args.font.is_file():
        raise ValueError("--font must name the same existing font file for both runs")
    args.output_parent.mkdir(parents=True, exist_ok=True)
    artifact = Path(tempfile.mkdtemp(prefix=f"{args.label}-", dir=args.output_parent))
    command = [sys.executable, str(Path(__file__).resolve()), "worker",
               "--akashic-root", str(args.akashic_root),
               "--megapad-root", str(args.megapad_root), "--font", str(args.font),
               "--artifact", str(artifact)]
    environment = dict(os.environ, SDL_VIDEODRIVER="x11", SDL_AUDIODRIVER="dummy",
                       MEGAFORTH_EXECUTOR="native", MEGAFORTH_NATIVE_PROFILE="0",
                       MEGAPAD_ROOT=str(args.megapad_root))
    environment.pop("WAYLAND_DISPLAY", None)
    started = time.monotonic()
    peak = 0
    stop_reason = None
    print(f"{KIND}\nArtifacts: {artifact}", flush=True)
    with (artifact / "run.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   env=environment, start_new_session=True)
        try:
            while process.poll() is None:
                peak = max(peak, owned_rss(process.pid))
                elapsed = time.monotonic() - started
                if peak >= RSS_STOP_BYTES:
                    stop_reason = "aggregate_rss_limit"
                    break
                if elapsed >= WATCHDOG_SECONDS:
                    stop_reason = "900_second_outer_watchdog"
                    break
                time.sleep(0.25)
        finally:
            stop_group(process)
    write_json(artifact / "supervisor.json", {
        "kind": KIND, "returncode": process.returncode, "stop_reason": stop_reason,
        "elapsed_seconds": time.monotonic() - started, "peak_aggregate_rss_bytes": peak,
        "rss_stop_bytes": RSS_STOP_BYTES, "watchdog_seconds": WATCHDOG_SECONDS,
        "note": "Outer watchdog includes image packaging and is no larger than the canonical budget.",
    })
    return 0 if process.returncode == 0 and stop_reason is None else 1



def server_main(args):
    sys.path.insert(0, str(args.megapad_root))
    # Permit diagnostic output on termination during source preparation, too.
    def terminate(_signum, _frame):
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, terminate)
    sys.argv = [str(args.megapad_root / "simulator_server.py"), *args.server_args]
    runpy.run_path(sys.argv[0], run_name="__main__")


def worker(args):
    # This is a diagnostic client plus the ordinary server, with no test workers.
    resource.setrlimit(resource.RLIMIT_AS, (RSS_STOP_BYTES, RSS_STOP_BYTES))
    sys.path[:0] = [str(args.megapad_root), str(args.akashic_root / "local_testing")]
    os.environ["MEGAPAD_ROOT"] = str(args.megapad_root)
    import akashic_tui as tui
    import rich_terminal_desktop_acceptance as journey_api
    import _megaforth_native as native_extension
    import pygame
    from session_viewer import (_GuestKeyboardForwarder, _RetainedDisplayState,
                                _accept_screen_update, _accept_status_update,
                                compose_terminal_frame_result)
    from shared_session import display_scope_to_wire, display_offer_to_wire

    artifact = args.artifact
    bindings = {"akashic": git_binding(args.akashic_root),
                "megapad": git_binding(args.megapad_root)}
    if tui.DESKTOP_ACCEPTANCE_TIMEOUT != WATCHDOG_SECONDS:
        raise RuntimeError("review the changed canonical acceptance watchdog before using this harness")
    extension = Path(native_extension.__file__).resolve()
    write_json(artifact / "bindings.json", {
        "kind": KIND, **bindings, "extension": str(extension),
        "extension_sha256": sha256(extension), "font": str(args.font),
        "font_sha256": sha256(args.font), "harness_sha256": sha256(Path(__file__)),
        "profile": "desktop-apt1", "source_mode": "canonical checked stored source",
        "phase_names": journey_api.GUEST_PHASE_NAMES,
        "font_size": 18, "action_delay_seconds": 0.75, "typing_hz": 5, "hold_seconds": 0,
    })
    start = time.monotonic_ns()
    trace_file = (artifact / "typing-trace.jsonl").open("w")
    def mark(event, **values):
        row = {"event": event, "time_ns": time.monotonic_ns() - start, **values}
        trace_file.write(json.dumps(row, sort_keys=True) + "\n")
        trace_file.flush()
        return row["time_ns"]

    # No checkpoint profile, source patch, compiled cache, or budget override.
    mark("source_build_started")
    image = tui.build_image("desktop-apt1", artifact / "desktop.img", None,
                            backend="simulator")
    mark("source_build_complete", image_sha256=sha256(image))
    socket_path = str(Path(tempfile.mkdtemp(prefix="rich-diag-")) / "session.sock")
    ordinary = tui._session_server_command(
        "desktop-apt1", image, socket_path=socket_path,
        cols=tui.DESKTOP_ACCEPTANCE_COLS, rows=tui.DESKTOP_ACCEPTANCE_ROWS,
        backend="simulator")
    command = [sys.executable, str(Path(__file__).resolve()), "server",
               "--megapad-root", str(args.megapad_root), "--artifact", str(artifact),
               "--", *ordinary[2:]]
    write_json(artifact / "launch.json", {"ordinary_command": ordinary,
                                         "instrumented_command": command, "kind": KIND})
    server_log = (artifact / "server.log").open("w")
    server = subprocess.Popen(command, stdout=server_log, stderr=subprocess.STDOUT)
    client = None
    journey = None
    outcome = "incomplete"
    last_status = None
    last_offer = None
    last_generation = None
    try:
        deadline = time.monotonic() + WATCHDOG_SECONDS
        client = journey_api._connect(socket_path, deadline, server.pid)
        mark("session_connected", server_pid=server.pid)
        if not journey_api._display_claimed(client.request("claim_display")):
            raise RuntimeError("the new diagnostic server did not grant its display lease")
        status = client.request("status", detailed=False)
        if status["semantic_execution"]["backend"] != "native":
            raise RuntimeError("diagnostic session did not select native execution")
        pygame.display.init()
        pygame.font.init()
        if pygame.display.get_driver() in {"dummy", "offscreen"}:
            raise RuntimeError("physical display required")
        font, cell_w, cell_h, fitted = journey_api._fit_viewer_font(
            pygame, args.font, 18, tui.DESKTOP_ACCEPTANCE_COLS, tui.DESKTOP_ACCEPTANCE_ROWS)
        window = pygame.display.set_mode((tui.DESKTOP_ACCEPTANCE_COLS * cell_w,
                                          tui.DESKTOP_ACCEPTANCE_ROWS * cell_h))
        pygame.display.set_caption("Akashic typing cadence — 5 characters/second")
        mark("physical_display", driver=pygame.display.get_driver(), font_size=fitted)
        control_font = pygame.font.Font(str(args.font), 16)
        control_font.set_bold(True)
        cell_w, cell_h = max(1, font.size("M")[0]), font.get_linesize()
        terminal = journey_api.VirtualTerminal(cols=tui.DESKTOP_ACCEPTANCE_COLS,
                                                rows=tui.DESKTOP_ACCEPTANCE_ROWS)
        state = _RetainedDisplayState()
        keyboard = _GuestKeyboardForwarder(
            pygame, client, generation=status["generation"], input_enabled=True,
            display_required=status["rich_terminal"]["display_required"])
        class TypingJourney:
            stage = 0
            sent = 0
            visible = 0
            target = "~fluid typing 12345"
            period_ns = 200_000_000
            first_due = None
            burst_due = None
            def tick(self):
                pygame.event.pump()
                now = time.monotonic_ns()
                if self.first_due is None:
                    return
                while self.sent < len(self.target):
                    due = self.first_due if self.sent == 0 else (
                        None if self.burst_due is None else self.burst_due + (self.sent - 1) * self.period_ns)
                    if due is None or now < due:
                        break
                    mark("character_due", index=self.sent, character=self.target[self.sent],
                         due_ns=due - start, actual_ns=now - start)
                    keyboard.text_input(SimpleNamespace(text=self.target[self.sent]))
                    mark("character_dispatched", index=self.sent, error=keyboard.last_error,
                         pending=keyboard.pending_events)
                    self.sent += 1
                keyboard.flush_pending()
                if self.burst_due is not None and now > self.burst_due + 60_000_000_000:
                    raise RuntimeError(f"typing drain exceeded 60s: visible {self.visible}/{len(self.target)}")
            def after_present(self, offer, projection):
                if self.stage == 0:
                    if not all(m in projection.text for m in tui.PROFILES['desktop-apt1'].ready_markers):
                        return journey_api.JourneyProgress()
                    journey_api._require_canonical_desktop_semantics(projection)
                    if journey_api.PAD_FOCUS_MARKER not in projection.text:
                        raise RuntimeError("canonical initial Pad focus missing")
                    self.stage = 1
                    self.first_due = time.monotonic_ns() + 750_000_000
                    return journey_api.JourneyProgress('typing-ready')
                count = max((n for n in range(1, len(self.target) + 1)
                             if journey_api._desktop_tile_contains(projection, self.target[:n],
                                                                  journey_api.PAD_DESKTOP_TILE)), default=0)
                mark('typing_visible', count=count, offer_id=offer.offer_id,
                     lines=[c.visible_text for c in projection.semantic_collection_claims])
                if count < self.visible:
                    raise RuntimeError("visible typing regressed")
                self.visible = count
                if count >= 1 and self.burst_due is None:
                    self.stage = 2
                    self.burst_due = time.monotonic_ns() + 750_000_000
                    return journey_api.JourneyProgress('single-character')
                if count == len(self.target):
                    self.stage = 3
                    return journey_api.JourneyProgress('typing-complete', complete=True)
                return journey_api.JourneyProgress()
        journey = TypingJourney()
        original_request = client.request
        def traced_request(method, **params):
            began = time.monotonic_ns() - start
            response = original_request(method, **params)
            if method in {'send_text', 'send_key'}:
                mark('input_rpc', started_ns=began, method=method, params=params, result=response)
            return response
        client.request = traced_request
        revision = -1
        glyph_cache = {}

        while time.monotonic() < deadline:
            journey.tick()
            last_status = client.request("status", detailed=False)
            journey_api._require_healthy_backend(last_status, artifact)
            revision, _ = _accept_status_update(
                last_status, keyboard=keyboard, display_state=state, revision=revision)
            update = client.request("screen", since=revision, since_offer=state.since_offer)
            revision, resized = _accept_screen_update(
                update, display_holder=True, terminal=terminal, keyboard=keyboard,
                display_state=state, revision=revision)
            if resized:
                glyph_cache.clear()
            offer = state.pending_offer
            if offer is None:
                time.sleep(0.01)
                continue
            generation = state.pending_generation
            mark("offer_observed", offer_id=offer.offer_id, stage=journey.stage,
                 scope=display_scope_to_wire(offer.scope), native_status=last_status["semantic_execution"])
            write_json(artifact / f"offer-{offer.offer_id}.json", display_offer_to_wire(offer))
            projection = journey_api.reconstruct_retained_screen(offer)
            journey_api._require_canonical_desktop_geometry(projection)
            mark("projection_complete", offer_id=offer.offer_id)
            if not state.pending_resources_ready:
                raise RuntimeError("canonical diagnostic journey unexpectedly requires image resources")
            began = mark("physical_compose_started", offer_id=offer.offer_id)
            frame = compose_terminal_frame_result(
                pygame, terminal, font, cell_w, cell_h, retained_plane=state.frame_plane,
                show_cursor=True, glyph_cache=glyph_cache, control_font=control_font)
            composed = mark("physical_compose_complete", offer_id=offer.offer_id,
                            started_ns=began, pixel_size=frame.surface.get_size())
            window.blit(frame.surface, (0, 0))
            pygame.display.flip()
            mark("physical_flip_complete", offer_id=offer.offer_id)
            state.stage_frame_hit_map(offer, frame.hit_entries)
            response = client.request("present", generation=generation,
                                      display_offer_id=offer.offer_id,
                                      display_scope=display_scope_to_wire(offer.scope))
            accepted = state.finish_presentation(response)
            if accepted is None:
                raise RuntimeError(f"physical completion ACK rejected: {response}")
            revision = accepted
            keyboard.acknowledge_display_offer(offer.offer_id, offer.scope)
            ack = mark("physical_offer_acknowledged", offer_id=offer.offer_id,
                       composed_ns=composed, physical_presentation=True)
            before_stage = journey.stage
            progress = journey.after_present(offer, projection)
            if progress.milestone or journey.stage != before_stage or progress.complete:
                mark("visible_response", milestone=progress.milestone, stage_before=before_stage,
                     stage_after=journey.stage, offer_id=offer.offer_id)
            if progress.milestone:
                pygame.image.save(frame.surface, str(artifact / f"{progress.milestone}-physical.png"))
            if progress.complete:
                outcome = "complete_physical_typing"
                mark(outcome)
                break
        else:
            raise TimeoutError("canonical 900-second diagnostic journey watchdog expired")
    except BaseException as exc:
        mark("diagnostic_error", error=f"{type(exc).__name__}: {exc}")
        raise
    finally:
        if client is not None:
            client.close()
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=10)
        server_log.close()
        pygame.quit()
        write_json(artifact / "result.json", {"kind": KIND, "outcome": outcome,
                                              "last_status": last_status,
                                              "sent": getattr(journey, "sent", 0),
                                              "visible": getattr(journey, "visible", 0)})
        trace_file.close()
        try:
            Path(socket_path).unlink(missing_ok=True)
            Path(socket_path).parent.rmdir()
        except OSError:
            pass
    if bindings != {"akashic": git_binding(args.akashic_root),
                    "megapad": git_binding(args.megapad_root)}:
        raise RuntimeError("measured source bindings changed during this diagnostic")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    run = modes.add_parser("run")
    driver = modes.add_parser("worker")
    server = modes.add_parser("server")
    for item in (run, driver, server):
        item.add_argument("--megapad-root", type=lambda p: Path(p).resolve(), required=True)
    for item in (run, driver):
        item.add_argument("--akashic-root", type=lambda p: Path(p).resolve(), required=True)
        item.add_argument("--font", type=lambda p: Path(p).resolve(), required=True)
    run.add_argument("--output-parent", type=lambda p: Path(p).resolve(), required=True)
    run.add_argument("--label", choices=("baseline", "fixed"), required=True)
    for item in (driver, server):
        item.add_argument("--artifact", type=lambda p: Path(p).resolve(), required=True)
    server.add_argument("server_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.mode == "server":
        if args.server_args[:1] == ["--"]:
            args.server_args.pop(0)
        return server_main(args)
    return supervise(args) if args.mode == "run" else worker(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)
