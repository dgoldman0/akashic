"""Headless Desk acceptance through the real unified application entry point.

The only transport substitutions are SessionServer._bind (no Unix listener)
and serve_forever (the synchronous acceptance client). megapad.main still
selects the simulator, parses its real options, prepares the image, starts the
production owner, and performs production shutdown. Dispatch, display leases,
offer acknowledgments, native execution, and composition remain production
code. This does not qualify socket transport, a physical display, or audio.
"""

import os

os.environ['MEGAFORTH_EXECUTOR'] = 'native'
os.environ['SDL_VIDEODRIVER'] = 'dummy'
os.environ['SDL_AUDIODRIVER'] = 'dummy'
os.environ['PYGAME_HIDE_SUPPORT_PROMPT'] = '1'

import argparse
import json
import hashlib
import resource
import signal
import subprocess
import sys
import time
import traceback
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--megapad-root", type=Path, required=True)
parser.add_argument("--output", type=Path)
parser.add_argument("--deadline", type=int, default=240)
args = parser.parse_args()
AK = Path(__file__).resolve().parents[1]
MP = args.megapad_root.resolve()
OUT = (args.output or AK / "build/grid-producer-qualification").resolve()
DEADLINE_SECONDS = args.deadline
if DEADLINE_SECONDS <= 0:
    parser.error("--deadline must be positive")
os.environ['MEGAPAD_ROOT'] = str(MP)
os.environ.setdefault('MP64_RUNTIME_NAMESPACE', 'grid-producer-qualification')
sys.path[:0] = [str(MP), str(AK / 'local_testing')]
resource.setrlimit(resource.RLIMIT_AS, (3584 * 1024**2, 3584 * 1024**2))

import pygame
import akashic_tui as tui
import megapad
# Unified startup moved into its backend package. Select the same module
# megapad.main uses while remaining runnable at the pinned pre-move checkpoint.
import importlib.util
if importlib.util.find_spec("simulator.server") is None:
    import simulator_server
else:
    from simulator import server as simulator_server
from shared_session import SessionServer, display_offer_to_wire
from rich_terminal.appearance import FLOWING_APPEARANCE
from display import VirtualTerminal
from rich_terminal.font_set import FontSet, discover_fallback_fonts
from session_viewer import (
    _GuestKeyboardForwarder, _RetainedDisplayState,
    _accept_status_update, _accept_screen_update,
    compose_terminal_frame_changes, draw_flip_and_present,
)
from rich_terminal_desktop_acceptance import (
    DesktopAcceptanceJourney, reconstruct_retained_screen,
    _request_acceptance_input, _require_healthy_backend,
    _require_cell_fallback_evidence,
)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    deadline = started + DEADLINE_SECONDS
    report = {
        'backend': 'simulator', 'executor': 'native', 'appearance': 'flowing',
        'launcher': 'megapad.main --mode simulator --executor native',
        'transport': 'direct in-process dispatch; no Unix listener',
        'display': 'SDL dummy software sink; no physical display qualification',
        'deadline_seconds': DEADLINE_SECONDS,
        'milestones': [], 'inputs': [], 'journey_complete': False,
        'complete': False,
    }
    server_instance = None
    original_server_class = simulator_server.SessionServer
    original_handlers = {
        sig: signal.getsignal(sig)
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGALRM)
    }

    def timeout(_signum, _frame):
        raise TimeoutError(f'Unified Desk acceptance exceeded {DEADLINE_SECONDS}s')

    def run_journey(server):
        client_started = time.monotonic()
        report['launcher_startup_seconds'] = client_started - started

        class LocalClient:
            def request(self, method, **params):
                return server.dispatch(method, params, connection_id=1)

        client = LocalClient()
        assert client.request('claim_display')['claimed']
        status = client.request('status', detailed=False)
        assert status['runtime']['mode'] == 'simulator', status['runtime']
        assert status['runtime']['executor'] == 'native', status['runtime']
        assert status['runtime']['capabilities']['machine_code'] is False
        assert status['semantic_execution']['backend'] == 'native'
        report['runtime'] = status['runtime']
        pygame.display.init()
        pygame.font.init()
        cols, rows = status['terminal']
        assert (cols, rows) == (
            tui.DESKTOP_ACCEPTANCE_COLS, tui.DESKTOP_ACCEPTANCE_ROWS)
        terminal = VirtualTerminal(cols=cols, rows=rows)
        font_path = AK / 'assets/fonts/DejaVuSansMono.ttf'
        font = FontSet(pygame, font_path, 18, discover_fallback_fonts())
        control_font = FontSet(pygame, font_path, 16, discover_fallback_fonts(), cells=False)
        cw, ch = font.cell_width, font.cell_height
        window = pygame.display.set_mode((cols*cw, rows*ch))
        display = _RetainedDisplayState()
        keyboard = _GuestKeyboardForwarder(
            pygame, client, generation=status['generation'], input_enabled=True,
            display_required=status['rich_terminal']['display_required'])
        ready = tui.PROFILES['desktop-apt1'].ready_markers
        journey = DesktopAcceptanceJourney(ready)
        report['final_stage'] = journey.final_stage
        print(f'Desktop journey: {journey.final_stage} stages; {cols}x{rows} cells', flush=True)
        revision = -1
        previous = None
        glyph_cache = {}
        last_offer = None
        last_generation = None
        last_progress = time.monotonic()
        first_ready = False
        offers = 0
        grid_key = None
        grid_probe_deadline = None

        def send_input(method, value, offer, generation):
            time.sleep(0.75)
            outcome, evidence = _request_acceptance_input(
                client, method, value, offer, generation,
                display_state=display, display_ack=keyboard.display_ack,
                cell_width=cw, cell_height=ch)
            if evidence is not None:
                report['inputs'].append({'stage': journey.stage, 'method': method,
                                         'value': value, 'outcome': outcome,
                                         'offer_id': offer.offer_id})
            return outcome

        while time.monotonic() < deadline:
            if grid_probe_deadline is not None and time.monotonic() > grid_probe_deadline:
                raise TimeoutError('Typed Grid PLACE did not return an acknowledged selection within 20s')
            pygame.event.pump()
            status = client.request('status', detailed=False)
            _require_healthy_backend(status, OUT)
            revision, _ = _accept_status_update(
                status, keyboard=keyboard, display_state=display, revision=revision)
            update = client.request('screen', since=revision,
                                    since_offer=display.since_offer,
                                    base_offer=display.base_offer_id)
            revision, resized = _accept_screen_update(
                update, display_holder=True, terminal=terminal, keyboard=keyboard,
                display_state=display, revision=revision)
            if resized:
                raise RuntimeError('Unexpected geometry change')
            offer = display.pending_offer
            generation = keyboard.generation if display.pending_generation is None else display.pending_generation
            if offer is None:
                if journey.has_pending_input and last_offer is not None:
                    journey.retry_pending_current(last_offer, last_generation, send_input)
                if time.monotonic()-last_progress > 20:
                    print(f'Waiting: stage={journey.stage}, steps={status.get("steps")}, '
                          f'state={status.get("state")}, reason={journey.waiting}', flush=True)
                    (OUT/'waiting-status.json').write_text(json.dumps(status, indent=2))
                    last_progress = time.monotonic()
                time.sleep(0.01)
                continue

            projection = reconstruct_retained_screen(
                offer, require_menu_bar=journey.requires_menu_bar,
                allow_empty=journey.allows_empty_retained_frames)

            def draw():
                nonlocal previous
                previous = compose_terminal_frame_changes(
                    pygame, terminal, font, cw, ch, retained_plane=display.frame_plane,
                    show_cursor=True, glyph_cache=glyph_cache, control_font=control_font,
                    previous=previous, appearance=FLOWING_APPEARANCE)
                window.blit(previous.surface, (0, 0))
                display.stage_frame_hit_map(offer, previous.hit_entries)

            presentation = draw_flip_and_present(
                pygame, client, draw, offer=offer, generation=generation, active=True)
            accepted = display.finish_presentation(presentation)
            if accepted is None:
                revision = -1
                keyboard.clear_display_context(waiting=True)
                continue
            revision = accepted
            keyboard.acknowledge_display_offer(offer.offer_id, offer.scope)
            last_offer, last_generation = offer, generation
            offers += 1
            if not first_ready and all(marker in projection.text for marker in ready):
                _require_cell_fallback_evidence('initial', offer, generation, ready)
                report['desktop_ready_seconds'] = time.monotonic()-started
                pygame.image.save(previous.surface, str(OUT/'Desk-Simulator-Initial.png'))
                (OUT/'initial-offer.json').write_text(json.dumps(display_offer_to_wire(offer)))
                (OUT/'initial-retained.txt').write_text(projection.text)
                first_ready = True
                print(f'Desk ready at {report["desktop_ready_seconds"]:.2f}s', flush=True)
            if report['journey_complete']:
                grids = [claim for claim in projection.semantic_collection_claims
                         if claim.content_state and any(
                             item[5] in (4, 5, 6) for item in claim.content_state[-1])]
                assert len(grids) == 1, ('typed Grid root count', len(grids))
                claim = grids[0]
                if claim.primary_key != grid_key:
                    continue
                report['grid_probe']['acknowledged_primary_key'] = claim.primary_key
                report['grid_probe']['content_revision'] = claim.content_revision
                pygame.image.save(previous.surface, str(OUT/'Desk-Grid-Selected.png'))
                (OUT/'grid-offer.json').write_text(json.dumps(display_offer_to_wire(offer)))
                report['final_status'] = client.request('status', detailed=False)
                report['final_runtime'] = report['final_status']['runtime']
                print('Typed Grid PLACE returned through ordinary application selection', flush=True)
                return
            old_stage = journey.stage
            progress = journey.after_present(offer, generation, projection, send_input)
            if progress.milestone or old_stage != journey.stage:
                print(f'Stage {journey.stage}/{journey.final_stage}: {progress.milestone}', flush=True)
                report['milestones'].append({'stage': journey.stage,
                    'name': progress.milestone, 'elapsed_seconds': time.monotonic()-started})
                pygame.image.save(previous.surface, str(OUT/'Desk-Simulator-Latest.png'))
                (OUT/'latest-retained.txt').write_text(projection.text)
                last_progress = time.monotonic()
            report['stage'] = journey.stage
            report['offers'] = offers
            (OUT/'progress.json').write_text(json.dumps(report, indent=2))
            if progress.complete:
                _require_cell_fallback_evidence('final', offer, generation, ready + journey.final_cell_markers)
                assert first_ready
                report['journey_complete'] = True
                pygame.image.save(previous.surface, str(OUT/'Desk-Simulator-Final.png'))
                (OUT/'final-offer.json').write_text(json.dumps(display_offer_to_wire(offer)))
                (OUT/'final-retained.txt').write_text(projection.text)
                # The completed journey already supplied an acknowledged frame;
                # issue the typed click against that exact live hit map and revision.
                grids = [claim for claim in projection.semantic_collection_claims
                         if claim.content_state and any(
                             item[5] in (4, 5, 6) for item in claim.content_state[-1])]
                assert len(grids) == 1, ('typed Grid root count', len(grids))
                claim = grids[0]
                items = claim.content_state[-1]
                target = next(item for item in items
                              if item[5] == 4 and item[0] != claim.primary_key)
                grid_key = target[0]
                value = journey._text_value(claim, grid_key, 0)
                assert send_input('text_place', value, offer, generation) == 'progress'
                report['grid_probe'] = {
                    'item_key': grid_key, 'display_text': target[7],
                    'roles': sorted({item[5] for item in items}),
                    'root_bounds': [claim.left, claim.top, claim.right, claim.bottom],
                    'prior_primary_key': claim.primary_key,
                }
                grid_probe_deadline = time.monotonic() + 20
                (OUT/'progress.json').write_text(json.dumps(report, indent=2))
                print(f'Typed Grid PLACE sent for item {grid_key}', flush=True)
        raise TimeoutError(f'Desktop journey stalled at {journey.stage}: {journey.waiting}')

    class InProcessAcceptanceServer(SessionServer):
        def __init__(self, *args, **kwargs):
            nonlocal server_instance
            super().__init__(*args, **kwargs)
            server_instance = self

        def _bind(self):
            # This harness intentionally supplies no listener or socket lease.
            pass

        def serve_forever(self):
            assert self.machine._thread is not None
            assert self.machine._thread.is_alive()
            run_journey(self)

    try:
        signal.signal(signal.SIGALRM, timeout)
        signal.setitimer(signal.ITIMER_REAL, DEADLINE_SECONDS)
        for name, path in (('megapad_commit', MP), ('akashic_commit', AK)):
            report[name] = subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=path, text=True, timeout=5).strip()
        report['akashic_tracked_diff_sha256'] = hashlib.sha256(
            subprocess.check_output(
                ['git', 'diff', '--binary', 'HEAD'], cwd=AK, timeout=5)
        ).hexdigest()
        report['megapad_tracked_diff_sha256'] = hashlib.sha256(
            subprocess.check_output(
                ['git', 'diff', '--binary', 'HEAD'], cwd=MP, timeout=5)
        ).hexdigest()
        image = tui.build_image('desktop-apt1', OUT / 'desktop-fresh-simulator.img', backend='simulator')
        with image.open('rb') as image_file:
            report['image_sha256'] = hashlib.file_digest(image_file, 'sha256').hexdigest()
        command = tui._session_server_command(
            'desktop-apt1', image, socket_path=str(OUT / 'unused.sock'),
            cols=tui.DESKTOP_ACCEPTANCE_COLS, rows=tui.DESKTOP_ACCEPTANCE_ROWS,
            backend='simulator')
        unified_args = ['--mode', 'simulator', '--executor', 'native', *command[2:]]
        report['launcher_arguments'] = unified_args
        simulator_server.SessionServer = InProcessAcceptanceServer
        print('Launching full Desk through megapad.main --mode simulator --executor native', flush=True)
        exit_code = megapad.main(unified_args)
        report['launcher_exit_code'] = exit_code
        assert exit_code == 0, exit_code
        assert report['journey_complete']
        assert server_instance is not None
        assert server_instance._stopping.is_set()
        machine = server_instance.machine
        assert machine._thread is not None and not machine._thread.is_alive()
        assert machine.semantic_session.backend.closed
        assert machine.semantic_session.runtime._session_owner_token is None
        assert machine.semantic_session.rich_terminal_driver is None
        assert server_instance._display_holder is None
        assert server_instance._socket is None and server_instance._socket_owner is None
        report['cleanup'] = {
            'server_stopped': True, 'owner_thread_stopped': True,
            'backend_closed': True, 'display_lease_released': True,
            'runtime_owner_released': True, 'terminal_driver_closed': True,
            'socket_transport_used': False,
        }
        report['complete'] = True
        print('HEADLESS DESK AND TYPED GRID SELECTION PASS', flush=True)
    except BaseException as exc:
        report['error'] = repr(exc)
        traceback.print_exc()
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        simulator_server.SessionServer = original_server_class
        for sig, handler in original_handlers.items():
            signal.signal(sig, handler)
        if server_instance is not None and not server_instance._stopping.is_set():
            try:
                server_instance.stop()
            except BaseException as exc:
                report['cleanup_error'] = repr(exc)
                report['complete'] = False
                traceback.print_exc()
        pygame.quit()
        report['elapsed_seconds'] = time.monotonic()-started
        report['peak_rss_bytes'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024
        (OUT/'result.json').write_text(json.dumps(report, indent=2))
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    sys.exit(main())
