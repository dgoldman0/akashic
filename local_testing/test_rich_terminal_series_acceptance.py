"""Bounded ordinary-source evidence and acknowledged full-history Desk probes."""
from dataclasses import replace
from pathlib import Path
import struct
from types import SimpleNamespace

import pytest

import akashic_tui  # noqa: F401
import rich_terminal_desktop_acceptance as acceptance
from rich_terminal.retained_scene import ControlState, ObjectBounds, RGBA, Sample
from rich_terminal.retained_view import (
    RetainedDrawPlane, RetainedRegionDraw, SeriesHistoryDraw, WaveformDraw,
    ReadoutDraw, MeterDraw, StatusDraw, MenuBarDraw, MenuDraw,
    TextAreaDraw, TextGridDraw, TabSetDraw, TabDraw, _draw_order_key,
)
from rich_terminal.semantic_content import SemanticTextContent, SemanticContentFlag
from rich_terminal.semantic_fields import FieldContent, FieldFlag, FieldKind, FieldRect
from test_rich_terminal_desktop_acceptance import (
    _offer, _glyph_draws_outside, _peek_record_fixture, _soundlab_desktop_projection,
)

MASK = (1 << 64) - 1
VALUES = tuple(index - 8000 for index in range(16000))


class SourceClient:
    def __init__(self, values=VALUES, amplitude=75, paused=False):
        self.calls = []
        self.paused = paused
        series = [72 + len(values) * 8, 4, 40, len(values), 1, 125, len(values), 0, 0]
        series += [value & MASK for value in values]
        waveform = [144, 5, 41, 0, 11, 2, 12, 86, 0, 1, 40,
                    -32768 & MASK, 32767, 0x5FD7FFFF, 0x4E4E4EFF, 0, 1, 0]
        graph = [112 + len(series) * 8 + 144, 1, 1, 0, 0, 35, 90, 3, 2, 1, 1,
                 len(values), 0, 0] + series + waveform
        self.records = {0x100: [0x100000], 0x100000: [0x200000, graph[0], 0x300000,
                        MASK, 2000, amplitude, 40, 4], 0x200000: graph,
                        0x300000: [44, 188, 35, 90]}
        names = ('_SL-DGRAPH-ACTIVE-A', '_SL-DGRAPH-ACTIVE-U', '_SL-PANEL-RGN',
                 '_SL-RENDER-VALID', '_SL-DURATION', '_SL-AMPLITUDE',
                 '_SL-FREQUENCY', '_SL-SHAPE')
        self.words = {'_SL-CURRENT-STATE': {'data_address': 0x100, 'value': 0x100000}}
        for index, name in enumerate(names):
            address = 0x200 + index * 16
            self.words[name] = {'data_address': address, 'value': 0x100}
            self.records[address] = [0x100, index * 8]

    def request(self, method, **params):
        self.calls.append((method, params))
        if method == 'status':
            return {'paused': self.paused, 'error': None}
        if method in ('pause', 'resume'):
            self.paused = method == 'pause'
            return {'paused': self.paused, 'error': None}
        if method == 'forth':
            return {'words': {name: self.words[name] for name in params['names']}}
        assert method == 'peek'
        assert self.paused
        assert 1 <= params['count'] <= 256
        return _peek_record_fixture(self.records, **params)


def wave_offer(values=VALUES, *, identity=1, offer_id=1):
    offer = _offer('\n'.join('.' * 280 for _ in range(84)), offer_id=offer_id)
    gaps = {(col, row) for row in range(55, 67) for col in range(190, 276)}
    base = replace(offer.retained.regions[0], draws=_glyph_draws_outside(280, 84, gaps))
    wave = WaveformDraw(1000 + identity, 0, ObjectBounds(2, 11, 86, 12), identity,
                        -32768, 32767, RGBA(95, 215, 255, 255), RGBA(78, 78, 78, 255), 0, True)
    region = RetainedRegionDraw(1, 1, 2, 188, 44, 90, 35, 188, 44, 90, 35, 1, True, (wave,))
    history = SeriesHistoryDraw(1, 1, identity, tuple(Sample(index * 125, value)
                                                   for index, value in enumerate(values)))
    return replace(offer, retained=RetainedDrawPlane(True, True, (base, region), (history,)))


def test_complete_canonical_source_read_is_bounded_owned_and_signed():
    client = SourceClient()
    source = acceptance._read_soundlab_waveform_source(client)
    assert source.values == VALUES
    assert source.bounds == (190, 55, 276, 67)
    assert source.duration == 2000 and source.amplitude == 75
    assert client.calls[0][0] == 'status' and client.calls[-1][0] == 'resume'
    reads = [params for method, params in client.calls if method == 'peek']
    graph_reads = [params for params in reads if 0x200000 <= params['address'] < 0x300000]
    assert sum(params['count'] for params in graph_reads) * 8 == source.byte_count
    assert all(params['count'] <= 256 for params in reads)
    client.records[0x200000][23:] = [0] * (len(client.records[0x200000]) - 23)
    assert source.values == VALUES
    evidence = acceptance._require_soundlab_waveform_evidence(wave_offer(), 7, source)
    assert evidence['every_sample_compared'] is True
    assert evidence['sample_count'] == 16000 and evidence['last_timestamp_us'] == 1999875
    assert evidence['source'] == 'paused ordinary Sound Lab canonical UDG'


def test_source_reads_byte_packed_dictionary_bodies_but_requires_aligned_model_storage():
    client = SourceClient()
    # CREATE/VARIABLE bodies follow variable-length dictionary names. Real
    # native Desk's current-state cell was at 4773659, not an aligned address.
    old_cell = client.words['_SL-CURRENT-STATE']['data_address']
    new_cell = 4773659
    client.words['_SL-CURRENT-STATE']['data_address'] = new_cell
    client.records[new_cell] = client.records.pop(old_cell)
    for word in client.words.values():
        if word is client.words['_SL-CURRENT-STATE']:
            continue
        old_body = word['data_address']
        new_body = old_body + 3
        word['data_address'] = new_body
        client.records[new_body] = [new_cell, client.records.pop(old_body)[1]]
    source = acceptance._read_soundlab_waveform_source(client)
    assert source.values == VALUES and source.duration == 2000
    assert not client.paused
    for address, count, body in ((new_cell, 1, False), (new_cell, 3, True),
                                 (0, 1, True), ((1 << 64) - 1, 1, True)):
        with pytest.raises(acceptance.PhysicalDesktopAcceptanceError, match='source span'):
            acceptance._soundlab_source_cells(client, address, count, dictionary_body=body)


@pytest.mark.parametrize('mutation', ['capacity', 'interval', 'reserved', 'extent', 'key',
                                      'signed_range', 'bank_size', 'foreign_field', 'field_bound'])
def test_source_refuses_invalid_extents_references_and_metadata_then_resumes(mutation):
    client = SourceClient()
    graph = client.records[0x200000]
    if mutation == 'capacity': graph[17] = 15999
    elif mutation == 'interval': graph[19] = 126
    elif mutation == 'reserved': graph[22] = 1
    elif mutation == 'extent': graph[14] += 144
    elif mutation == 'key': graph[-16] = 40
    elif mutation == 'signed_range': graph[23] = 70000
    elif mutation == 'bank_size': client.records[0x100000][1] = 130184
    elif mutation == 'foreign_field': client.records[0x200][0] = 0x108
    else: client.records[0x200][1] = 512 * 1024
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError):
        acceptance._read_soundlab_waveform_source(client)
    assert client.paused is False
    assert client.calls[-1][0] == 'resume'
    if mutation in ('bank_size', 'foreign_field', 'field_bound'):
        assert not any(method == 'peek' and params['address'] == 0x200000
                       for method, params in client.calls)


def test_existing_pause_is_preserved_and_transport_failure_does_not_resume():
    paused = SourceClient(paused=True)
    acceptance._read_soundlab_waveform_source(paused)
    assert paused.paused and not any(method == 'resume' for method, _ in paused.calls)
    broken = SourceClient()
    original = broken.request
    def request(method, **params):
        if method == 'peek':
            raise ConnectionError('framing lost')
        return original(method, **params)
    broken.request = request
    with pytest.raises(ConnectionError):
        acceptance._read_soundlab_waveform_source(broken)
    assert not any(method == 'resume' for method, _ in broken.calls)


@pytest.mark.parametrize('mutation', ['value', 'timestamp', 'short', 'geometry', 'owner', 'color'])
def test_retained_evidence_checks_every_sample_geometry_and_owner(mutation):
    source = acceptance._read_soundlab_waveform_source(SourceClient())
    offer = wave_offer()
    history = offer.retained.series[0]
    wave_region = offer.retained.regions[1]
    if mutation in ('value', 'timestamp', 'short'):
        samples = list(history.samples)
        if mutation == 'short': samples.pop()
        elif mutation == 'value': samples[12345] = Sample(12345 * 125, samples[12345].value + 1)
        else: samples[12345] = Sample(12345 * 125 + 1, samples[12345].value)
        history = replace(history, samples=tuple(samples))
    elif mutation == 'geometry':
        wave_region = replace(wave_region, logical_x=189)
    elif mutation == 'color':
        wave_region = replace(wave_region, draws=(replace(wave_region.draws[0], trace=RGBA(1, 2, 3, 255)),))
    else:
        history = replace(history, owner_id=2)
    # A malformed owner relation is rejected by real RetainedDrawPlane too;
    # the independent acceptance check must not assume construction alone.
    bad_plane = SimpleNamespace(regions=(offer.retained.regions[0], wave_region), series=(history,))
    bad_offer = SimpleNamespace(retained=bad_plane, cell=offer.cell, scope=offer.scope, offer_id=offer.offer_id)
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError):
        acceptance._require_soundlab_waveform_evidence(bad_offer, 7, source)


def test_projection_accepts_initial_waveform_as_an_instrument_without_status_alias():
    projection = acceptance.reconstruct_retained_screen(wave_offer(), require_menu_bar=False)
    assert projection.waveform_count == 1
    assert projection.status_count == 0
    assert projection.instrument_region_count == 1
    assert projection.instrument_cell_count == 86 * 12


def test_full_initial_soundlab_projection_accepts_existing_instruments_and_auto_waveform():
    # Initial 500ms auto-render: the ordinary thirteen instruments and the new
    # waveform share one Sound Lab graph/region and one owned 4000-sample history.
    offer = wave_offer(VALUES[:4000])
    base, region = offer.retained.regions
    white, clear = RGBA(238, 238, 238, 255), RGBA(0, 0, 0, 0)
    instrument_draws = [region.draws[0]]
    for index, (col, row, width, text) in enumerate((
            (7, 24, 5, '75%'), (21, 24, 7, '9'), (35, 24, 5, '50%'), (46, 24, 11, '0 ppt'),
            (8, 25, 10, '440 Hz'), (30, 25, 11, '441 Hz'), (53, 25, 9, '439'), (70, 25, 8, '0'))):
        instrument_draws.append(ReadoutDraw(2000 + index, 1, ObjectBounds(col, row, width, 1),
                                             white, clear, text))
    for index in range(2):
        instrument_draws.append(MeterDraw(2010 + index, 0, ObjectBounds(14, 26 + index, 52, 1),
                                           RGBA(95, 175, 95, 255), RGBA(58, 58, 58, 255),
                                           False, False, 0, 100, 75))
    for index, (col, row) in enumerate(((2, 8), (4, 9), (2, 9))):
        instrument_draws.append(StatusDraw(2020 + index, 2, ObjectBounds(col, row, 1, 1),
                                            RGBA(102, 102, 102, 255), RGBA(0, 175, 175, 255), 1, index))
    region = replace(region, draws=tuple(sorted(instrument_draws, key=_draw_order_key)))
    enabled = ControlState.VISIBLE | ControlState.ENABLED
    signatures = (*acceptance.DESKTOP_MENU_SIGNATURES, acceptance.SOUNDLAB_MENU_SIGNATURE)
    menus = []
    for tile, signature in enumerate(signatures):
        left, top = (tile % 3) * 280 // 3, (tile // 3) * 83 // 2
        identity = 30000 + tile * 100
        menus.append(MenuBarDraw(identity, enabled, 0, 0, ObjectBounds(left, top + 1, 90, 1),
                                 tuple(MenuDraw(identity + index + 1, enabled, index, label, ())
                                       for index, label in enumerate(signature))))
    content = SemanticTextContent(1, 1, 80, 0, 0, 1, 80, SemanticContentFlag(0), 0, 0, 0, 0, ())
    controls = (
        TextAreaDraw(40000, enabled, 0, 0, ObjectBounds(1, 4, 80, 1), content),
        TextGridDraw(40001, enabled, 0, 0, ObjectBounds(190, 4, 80, 1), content),
        TabSetDraw(40002, enabled, 0, 0, ObjectBounds(1, 3, 80, 1),
                   (TabDraw(40003, enabled | ControlState.SELECTED, 0, 'Untitled', ''),)),
    )
    gaps = set()
    for draw in instrument_draws:
        gaps.update(acceptance._rectangle_cells(acceptance._draw_logical_rectangle(region, draw)))
    for draw in controls:
        gaps.update(acceptance._rectangle_cells(acceptance._draw_logical_rectangle(base, draw)))
    base = replace(base, draws=tuple(sorted((*_glyph_draws_outside(280, 84, gaps), *menus, *controls),
                                            key=_draw_order_key)))
    offer = replace(offer, retained=replace(offer.retained, regions=(base, region)))
    projection = acceptance.reconstruct_retained_screen(offer)
    assert len(region.draws) == 14
    assert (projection.readout_count, projection.meter_count, projection.status_count,
            projection.waveform_count, projection.instrument_region_count) == (8, 2, 3, 1, 1)
    assert len(offer.retained.series) == 1 and len(offer.retained.series[0].samples) == 4000
    assert offer.retained.series[0].key == (region.owner_id, region.owner_generation, 1)
    acceptance._require_soundlab_desktop_semantics(projection)
    assert acceptance.DesktopAcceptanceJourney(('SOUND LAB',)).final_stage == 52
    # The extra waveform does not excuse a missing preexisting metric.
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError, match='8 READOUT, 2 METER, and 3 STATUS'):
        acceptance._require_soundlab_desktop_semantics(replace(
            projection, instrument_claims=tuple(claim for claim in projection.instrument_claims
                                                if claim.object_id != 2000)))


def field_projection(*, duration=2000, amplitude=75, selected='Amplitude (%)'):
    claims = []
    labels = ('Waveform', 'Frequency (Hz)', 'Amplitude (%)', 'Duration (ms)')
    for index, (label, value) in enumerate(zip(labels, (4, 40, amplitude, duration))):
        content = FieldContent(3, FieldKind.INTEGER, FieldFlag(0), FieldRect(2, 0, 70, 1),
                               FieldRect(74, 0, 14, 1), value, 0, 2000, 1)
        state = ControlState.VISIBLE | ControlState.ENABLED
        if label == selected: state |= ControlState.SELECTED
        claims.append(acceptance._SemanticFieldClaim(acceptance.ControlIdentity(1, 1, index + 1),
                                                     188, 47 + index, 278, 48 + index,
                                                     label, state, content))
    return replace(_soundlab_desktop_projection(), semantic_field_claims=tuple(claims))


def test_probe_uses_ordinary_inputs_compares_two_renders_and_proves_stable_reuse():
    probe = acceptance.SoundLabSeriesProbe()
    sent = []
    sender = lambda method, value, offer, generation: sent.append((method, value)) or 'progress'
    first = acceptance._read_soundlab_waveform_source(SourceClient())
    changed = tuple(value // 2 for value in VALUES)
    second = acceptance._read_soundlab_waveform_source(SourceClient(changed, amplitude=40))
    offer = wave_offer()
    def step(projection, current=offer, source=first):
        return probe.after_present(projection, current, 7, sender, lambda: source)
    normal = field_projection()
    assert step(normal) is False and probe.stage == 1
    assert step(normal) is False and probe.stage == 2
    for prefix, value, start in (('Duration (100-2000 ms):', '2000', 2),
                                ('Amplitude (0-100 percent):', '40', 7)):
        prompt = replace(normal, lines=(acceptance.SOUNDLAB_FOCUS_MARKER, f'{prefix} {value}'),
                         cells=(), semantic_field_claims=())
        # Exercise the real fallback evidence boundary against the exact
        # immutable CELL prompt; a mocked recorder hid a full-run failure.
        prompt_cell = _offer('\n'.join(
            line.ljust(280) for line in (*prompt.lines, *('',) * (84 - len(prompt.lines)))
        )).cell
        prompt_offer = replace(offer, cell=prompt_cell)
        assert probe.stage == start
        for expected in (start + 1, start + 2, start + 3):
            assert step(prompt, prompt_offer) is False and probe.stage == expected
        current = normal if start == 2 else field_projection(amplitude=40)
        assert step(current) is False and probe.stage == start + 4
        rendered = offer if start == 2 else wave_offer(changed, identity=2, offer_id=2)
        assert step(current, rendered, first if start == 2 else second) is False
    assert probe.stage == 12
    assert step(field_projection(amplitude=40), wave_offer(changed, identity=2, offer_id=3), second) is False
    assert step(field_projection(amplitude=40, selected='Duration (ms)'),
                wave_offer(changed, identity=2, offer_id=4), second) is True
    assert probe.complete
    assert sent == [('send_key', 'alt+6'), ('field_activate', '1,1,4'),
                    ('send_key', 'ctrl+a'), ('send_text', '2000'), ('send_key', 'enter'), ('send_key', 'f5'),
                    ('field_activate', '1,1,3'), ('send_key', 'ctrl+a'), ('send_text', '40'),
                    ('send_key', 'enter'), ('send_key', 'f5'), ('send_key', 'down')]
    assert len(probe.evidence['renders']) == 2
    assert probe.evidence['stable_reuse']['history_key'] == [1, 1, 2]


def test_probe_retries_only_unaccepted_input_and_runner_latches_completed_fields():
    probe = acceptance.SoundLabSeriesProbe()
    offer = wave_offer()
    assert not probe.after_present(field_projection(), offer, 7, lambda *args: 'backpressured', None)
    assert probe.stage == 0 and probe.pending == ('send_key', 'alt+6', 1)
    assert probe.retry_pending(offer, 7, lambda *args: 'progress')
    assert probe.stage == 1 and probe.pending is None
    runner = (Path(__file__).with_name('run_headless_grid_acceptance.py')).read_text()
    assert 'args.require_fields = args.require_fields or args.require_series' in runner
    assert 'if args.require_fields and not field_acknowledged:' in runner
    assert runner.index('field_acknowledged = True') < runner.index('series_probe.after_present(')
