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
from dataclasses import asdict
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
parser.add_argument("--require-status-fields", action="store_true")
parser.add_argument("--require-fields", action="store_true")
parser.add_argument("--require-series", action="store_true",
                    help="After FIELD probes, render and compare the full Sound Lab history")
args = parser.parse_args()
args.require_fields = args.require_fields or args.require_series
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
from rich_terminal.server import RichTerminalCore
from rich_terminal.driver import RichTerminalDriver
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
    _require_cell_fallback_evidence, _status_field_claims_in_tile, _field_claims_in_tile,
    _write_guest_failure_diagnostics,
    SoundLabSeriesProbe, _read_soundlab_waveform_source,
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
        'complete': False, 'require_status_fields': args.require_status_fields,
        'require_fields': args.require_fields,
        'require_series': args.require_series,
    }
    server_instance = None
    original_server_class = simulator_server.SessionServer
    terminal_events = []
    diagnostic_methods = []
    for cls, method in ((RichTerminalCore, '_fatal'),
                        (RichTerminalCore, '_accept_close'),
                        (RichTerminalDriver, '_fail')):
        original = getattr(cls, method)
        def observed(self, *values, _original=original, _method=method, **kwargs):
            terminal_events.append({
                'seconds': time.monotonic() - started, 'method': _method,
                'arguments': [v.hex() if isinstance(v, bytes) else str(v) for v in values],
                'cause': repr(kwargs.get('cause')),
            })
            del terminal_events[:-32]
            return _original(self, *values, **kwargs)
        diagnostic_methods.append((cls, method, original))
        setattr(cls, method, observed)
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
        initial_status_values = None
        offers = 0
        grid_key = None
        grid_probe_deadline = None
        grid_acknowledged = False
        field_deadline = None
        field_pending = None
        field_stage = 0
        field_geometry = None
        field_acknowledged = False
        series_probe = SoundLabSeriesProbe() if args.require_series else None
        series_deadline = None
        field_actions = [('Frequency (Hz)', 3), ('Frequency (Hz)', (1 << 63) - 1),
                         ('Frequency (Hz)', -(1 << 63)), ('Waveform', -1)]

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

        def field_snapshot(claim):
            return {'label': claim.label, 'kind': int(claim.content.kind),
                    'value': claim.content.value, 'revision': claim.content_revision,
                    'root': [claim.left, claim.top, claim.right, claim.bottom],
                    'label_bounds': claim.label_bounds, 'value_bounds': claim.value_bounds}

        def field_probe(projection, offer, generation):
            nonlocal field_stage, field_pending, field_deadline, field_geometry
            fields = tuple(_field_claims_in_tile(projection, 5))
            if field_stage == len(field_actions) + 1:
                prompt = 'Frequency (40-2000 Hz): 40'
                if prompt not in projection.text:
                    return False
                assert not fields, 'modal prompt retained covered FIELD targets'
                _require_cell_fallback_evidence('field-prompt', offer, generation, (prompt,))
                report['field_probe']['activation_prompt'] = prompt
                assert send_input('send_key', 'escape', offer, generation) == 'progress'
                field_stage += 1
                field_deadline = time.monotonic() + 20
                return False
            if not fields:
                return False
            assert len(fields) == 4, ('Sound Lab FIELD count', len(fields))
            by_label = {claim.label: claim for claim in fields}
            assert set(by_label) == {'Waveform', 'Frequency (Hz)', 'Amplitude (%)', 'Duration (ms)'}
            geometry = {claim.label: (claim.left, claim.top, claim.right, claim.bottom,
                                      claim.label_bounds, claim.value_bounds) for claim in fields}
            if field_geometry is None:
                field_geometry = geometry
                report['field_probe'] = {'initial': [field_snapshot(c) for c in fields], 'adjustments': []}
            assert geometry == field_geometry, 'FIELD input changed authored geometry'
            if field_pending is not None:
                label, expected, old_revision = field_pending
                claim = by_label[label]
                if claim.content_revision == old_revision:
                    return False
                assert claim.content.value == expected, (label, claim.content.value, expected)
                report['field_probe']['adjustments'][-1]['acknowledged'] = field_snapshot(claim)
                field_pending = None
                field_stage += 1
                print(f'FIELD adjustment {field_stage}/{len(field_actions)} acknowledged', flush=True)
            if field_stage < len(field_actions):
                label, count = field_actions[field_stage]
                claim = by_label[label]
                content = claim.content
                if content.choices:
                    values = [choice.value for choice in content.choices]
                    expected = values[(values.index(content.value) + count) % len(values)]
                else:
                    expected = max(content.minimum, min(content.maximum, content.value + count * content.step))
                identity = claim.identity
                target = f'{identity.owner_id},{identity.owner_generation},{identity.control_id},{count}'
                assert send_input('field_adjust', target, offer, generation) == 'progress'
                report['field_probe']['adjustments'].append({
                    'label': label, 'count': count, 'expected': expected, 'before': field_snapshot(claim)})
                field_pending = (label, expected, claim.content_revision)
                field_deadline = time.monotonic() + 20
                return False
            if field_stage == len(field_actions):
                identity = by_label['Frequency (Hz)'].identity
                target = f'{identity.owner_id},{identity.owner_generation},{identity.control_id}'
                assert send_input('field_activate', target, offer, generation) == 'progress'
                field_stage += 1
                field_deadline = time.monotonic() + 20
                return False
            assert field_stage == len(field_actions) + 2
            assert by_label['Frequency (Hz)'].content.value == 40
            report['field_probe']['final'] = [field_snapshot(c) for c in fields]
            report['field_probe']['prompt_cancelled'] = True
            field_deadline = None
            pygame.image.save(previous.surface, str(OUT/'Desk-Fields-Adjusted.png'))
            (OUT/'field-offer.json').write_text(json.dumps(display_offer_to_wire(offer)))
            print('FIELD ADJUST, clamp, choice wrap, ACTIVATE and prompt cancellation PASS', flush=True)
            return True

        while time.monotonic() < deadline:
            if series_deadline is not None and time.monotonic() > series_deadline:
                raise TimeoutError(f"SERIES probe stalled at stage {series_probe.stage} for40s")
            if field_deadline is not None and time.monotonic() > field_deadline:
                raise TimeoutError(f"FIELD probe stalled at stage {field_stage} for20s")
            if grid_probe_deadline is not None and time.monotonic() > grid_probe_deadline:
                raise TimeoutError('Typed Grid PLACE did not return an acknowledged selection within 20s')
            pygame.event.pump()
            status = client.request('status', detailed=False)
            _require_healthy_backend(status, OUT)
            if status.get('halted'):
                (OUT/'halted-status.json').write_text(json.dumps(status, indent=2))
                (OUT/'halted-raw.json').write_text(json.dumps(client.request('raw', since=0), indent=2))
                try:
                    _write_guest_failure_diagnostics(client, OUT, 'Desk guest halted before acceptance completed')
                except Exception as diagnostic_error:
                    report['guest_diagnostic_error'] = repr(diagnostic_error)
                raise RuntimeError(f'Desk guest halted at journey stage {journey.stage}; captured raw and guest state')
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
                if series_probe is not None and series_probe.pending is not None and last_offer is not None:
                    if series_probe.retry_pending(last_offer, last_generation, send_input):
                        series_deadline = time.monotonic() + 40
                if journey.has_pending_input and last_offer is not None:
                    journey.retry_pending_current(last_offer, last_generation, send_input)
                if time.monotonic()-last_progress > 20:
                    print(f'Waiting: stage={journey.stage}, steps={status.get("steps")}, '
                          f'state={status.get("state")}, reason={journey.waiting}', flush=True)
                    (OUT/'waiting-status.json').write_text(json.dumps(status, indent=2))
                    if last_offer is not None:
                        (OUT/'waiting-offer.json').write_text(
                            json.dumps(display_offer_to_wire(last_offer)))
                    if previous is not None:
                        pygame.image.save(previous.surface, str(OUT/'Desk-Simulator-Waiting.png'))
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
            report['offers'] = offers
            if not first_ready and all(marker in projection.text for marker in ready):
                _require_cell_fallback_evidence('initial', offer, generation, ready)
                report['desktop_ready_seconds'] = time.monotonic()-started
                pygame.image.save(previous.surface, str(OUT/'Desk-Simulator-Initial.png'))
                (OUT/'initial-offer.json').write_text(json.dumps(display_offer_to_wire(offer)))
                (OUT/'initial-retained.txt').write_text(projection.text)
                if args.require_status_fields:
                    by_tile = [tuple(_status_field_claims_in_tile(projection, tile))
                               for tile in range(6)]
                    # Sound Lab is launched later by the acceptance journey.
                    assert all(by_tile[:5]), ('missing initial status fields by tile',
                                              [len(claims) for claims in by_tile])
                    initial_status_values = tuple(
                        (claim.left, claim.top, claim.label, claim.value)
                        for claim in projection.semantic_status_field_claims)
                    report['initial_status_fields'] = [
                        [asdict(claim) for claim in claims] for claims in by_tile]
                first_ready = True
                print(f'Desk ready at {report["desktop_ready_seconds"]:.2f}s', flush=True)
            if report['journey_complete']:
                if not grid_acknowledged:
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
                    grid_acknowledged = True
                    grid_probe_deadline = None
                if args.require_fields and not field_acknowledged:
                    if not field_probe(projection, offer, generation):
                        continue
                    field_acknowledged = True
                if series_probe is not None and not series_probe.complete:
                    if series_deadline is None:
                        series_deadline = time.monotonic() + 40
                    prior_series_stage = series_probe.stage
                    complete = series_probe.after_present(
                        projection, offer, generation, send_input,
                        lambda: _read_soundlab_waveform_source(client))
                    report['series_probe'] = series_probe.evidence
                    if series_probe.stage != prior_series_stage:
                        series_deadline = time.monotonic() + 40
                        print(f'SERIES probe stage {series_probe.stage}/13', flush=True)
                    (OUT/'progress.json').write_text(json.dumps(report, indent=2))
                    if not complete:
                        continue
                    series_deadline = None
                    pygame.image.save(previous.surface, str(OUT/'Desk-Series-Verified.png'))
                    (OUT/'series-offer.json').write_text(json.dumps(display_offer_to_wire(offer)))
                    print('Full16000-sample SERIES/WAVEFORM, changed render and stable reuse PASS', flush=True)
                if args.require_status_fields:
                    by_tile = [tuple(_status_field_claims_in_tile(projection, tile))
                               for tile in range(6)]
                    assert all(by_tile), ('missing final status fields by tile',
                                          [len(claims) for claims in by_tile])
                    final_status_values = tuple(
                        (claim.left, claim.top, claim.label, claim.value)
                        for claim in projection.semantic_status_field_claims)
                    assert final_status_values != initial_status_values
                    report['final_status_fields'] = [
                        [asdict(claim) for claim in claims] for claims in by_tile]
                    report['status_state_changed'] = True
                report['final_status'] = client.request('status', detailed=False)
                report['final_runtime'] = report['final_status']['runtime']
                print('Typed Grid PLACE returned through ordinary application selection', flush=True)
                return
            old_stage = journey.stage
            try:
                progress = journey.after_present(offer, generation, projection, send_input)
            except BaseException:
                (OUT/'failure-offer.json').write_text(json.dumps(display_offer_to_wire(offer)))
                (OUT/'failure-retained.txt').write_text(projection.text)
                pygame.image.save(previous.surface, str(OUT/'Desk-Simulator-Failure.png'))
                raise
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
        for cls, method, original in diagnostic_methods:
            setattr(cls, method, original)
        report['terminal_events'] = terminal_events
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
