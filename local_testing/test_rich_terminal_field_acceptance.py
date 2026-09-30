"""FIELD acceptance uses committed state and real compositor value-slot hits."""
from dataclasses import replace

import pytest
import akashic_tui  # noqa: F401
import rich_terminal_desktop_acceptance as acceptance
from rich_terminal.pygame_view import FieldHitTarget, PixelRect, RegionOcclusion, composite_draw_plane_result
from rich_terminal.retained_scene import ControlKind, ControlState, ObjectBounds, RGBA, StatusSeverity
from rich_terminal.retained_view import FieldDraw, MeterDraw, StatusFieldDraw, _draw_order_key
from rich_terminal.semantic_fields import FieldChoice, FieldContent, FieldFlag, FieldKind, FieldRect
from test_rich_terminal_desktop_acceptance import _offer, _glyph_draws_outside, _acknowledged_hit_state


ENABLED = ControlState.VISIBLE | ControlState.ENABLED


def _field_offer(*fields):
    cols, rows = 12, 4
    offer = _offer("\n".join((" " * cols,) * rows))
    region = offer.retained.regions[0]
    gaps = set()
    for field in fields:
        gaps.update(acceptance._rectangle_cells(acceptance._draw_logical_rectangle(region, field)))
    draws = (*_glyph_draws_outside(cols, rows, gaps), *fields, region.draws[-1])
    return replace(offer, retained=replace(offer.retained, regions=(replace(
        region, draws=tuple(sorted(draws, key=_draw_order_key)),
    ),)))


def _field(kind=FieldKind.INTEGER, *, flags=FieldFlag(0), state=ENABLED):
    values = dict(value=440, minimum=20, maximum=20000, step=10)
    if kind is FieldKind.CHOICE:
        values = dict(value=2, choices=(FieldChoice(1, 'sine'), FieldChoice(2, 'square')))
    elif kind is FieldKind.TEXT:
        values = dict(text='an intentionally long authored text')
    content = FieldContent(7, kind, flags, FieldRect(0, 0, 3, 1), FieldRect(4, 0, 4, 1), **values)
    return FieldDraw(90_000, state, 0, 0, ObjectBounds(2, 1, 8, 1), 'Parameter', content)


@pytest.mark.parametrize('kind', tuple(FieldKind))
def test_field_claim_preserves_state_and_slots_without_promoting_source_text(kind):
    field = _field(kind)
    projection = acceptance.reconstruct_retained_screen(_field_offer(field))
    assert projection.field_count == 1
    claim, = projection.semantic_field_claims
    assert claim.identity.control_id == 90_000
    assert claim.content == field.content and claim.content_revision == 7
    assert claim.label_bounds == (2, 1, 5, 2)
    assert claim.value_bounds == (6, 1, 10, 2)
    assert 'Parameter' not in projection.text
    assert field.content.display_text not in projection.text
    assert acceptance._field_claims_in(projection, (2, 1, 10, 2)) == (claim,)
    assert acceptance._field_claims_in(projection, (3, 1, 10, 2)) == ()
    assert projection.glyph_cell_count == 40  # entire root incl the slot gap is opaque


def test_empty_field_label_keeps_only_its_explicit_value_slot():
    field = _field()
    field = replace(field, label='', content=replace(field.content, label_bounds=FieldRect(0, 0, 0, 0)))
    # FIELD cannot have object parents, so its root origin is directly region-relative.
    claim, = acceptance.reconstruct_retained_screen(_field_offer(field)).semantic_field_claims
    assert claim.label_bounds is None and claim.value_bounds == (6, 1, 10, 2)


@pytest.mark.parametrize('bounds', [ObjectBounds(-1, 1, 8, 1), ObjectBounds(7, 1, 8, 1), ObjectBounds(2, 4, 8, 1)])
def test_field_root_must_fit_selected_surface(bounds):
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError, match='physical screen'):
        acceptance.reconstruct_retained_screen(_field_offer(replace(_field(), bounds=bounds)))


def test_field_root_cannot_overlap_status_or_residual_glyphs():
    field = _field()
    status = StatusFieldDraw(90_001, 0, ObjectBounds(9, 1, 2, 1), '', 'x', 0, StatusSeverity.NEUTRAL, False)
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError, match='semantic root claims overlap'):
        acceptance.reconstruct_retained_screen(_field_offer(field, status))
    offer = _field_offer(field)
    region = offer.retained.regions[0]
    glyph = next(draw for draw in region.draws if type(draw).__name__ == 'GlyphRunDraw')
    glyph = replace(glyph, object_id=99_000, text='X', bounds=ObjectBounds(2, 1, 1, 1))
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError, match='overlap semantic root'):
        acceptance.reconstruct_retained_screen(replace(offer, retained=replace(offer.retained, regions=(replace(region, draws=tuple(sorted((*region.draws, glyph), key=_draw_order_key))),))))


def test_foreground_instrument_withholds_entire_field_semantic_evidence():
    offer = _field_offer(_field())
    region = offer.retained.regions[0]
    instrument = MeterDraw(91_000, 0, ObjectBounds(0, 0, 1, 1), RGBA(255,255,255,255), RGBA(0,0,0,255), False, False, 0, 100, 50)
    foreground = replace(region, region_id=2, logical_x=6, logical_y=1, logical_cols=1, logical_rows=1, z_order=1, draws=(instrument,))
    projection = acceptance.reconstruct_retained_screen(replace(offer, retained=replace(offer.retained, regions=(region, foreground))))
    assert projection.field_count == 0


@pytest.fixture(scope='module')
def pygame_font():
    pygame = pytest.importorskip('pygame')
    pygame.font.init()
    return pygame, pygame.font.Font(None, 16)


def _input_environment(pygame_font, field=None):
    pygame, font = pygame_font
    offer = _field_offer(_field() if field is None else field)
    result = composite_draw_plane_result(pygame, pygame.Surface((96, 80)), offer.retained, font, 8, 20)
    state, ack = _acknowledged_hit_state(offer, *result.hit_entries)
    return offer, state, ack


class _Client:
    def __init__(self, response=None):
        self.requests = []
        self.response = response or {'status': 'progress', 'accepted_events': 1}
    def request(self, method, **params):
        self.requests.append((method, params))
        return self.response


def _request(client, offer, state, ack, method='field_adjust', value='1,1,90000,-3'):
    return acceptance._request_acceptance_input(client, method, value, offer, 9, display_state=state, display_ack=ack, cell_width=8, cell_height=20)


@pytest.mark.parametrize('kind', [FieldKind.INTEGER, FieldKind.CHOICE])
@pytest.mark.parametrize('count', [-(1 << 63), -3, 2, (1 << 63)-1])
def test_field_adjust_uses_exact_real_value_hit_and_revision(pygame_font, kind, count):
    offer, state, ack = _input_environment(pygame_font, _field(kind))
    client = _Client()
    status, evidence = _request(client, offer, state, ack, value=f'1,1,90000,{count}')
    assert status == 'progress'
    method, params = client.requests[0]
    assert method == 'send_text_event'
    assert params['event_kind'] == 11 and params['adjustment'] == count
    assert params['content_revision'] == 7
    assert evidence.semantic_target['content_revision'] == 7
    assert evidence.semantic_target['pixel_rect'] == {'left':48,'top':20,'right':80,'bottom':40}
    assert len(client.requests) == 1


@pytest.mark.parametrize('kind', tuple(FieldKind))
def test_field_activate_uses_existing_revisionless_activate_wire(pygame_font, kind):
    offer, state, ack = _input_environment(pygame_font, _field(kind))
    client = _Client()
    status, evidence = _request(client, offer, state, ack, 'field_activate', '1,1,90000')
    assert status == 'progress' and evidence.semantic_target['event_kind'] == 'ACTIVATE'
    method, params = client.requests[0]
    assert method == 'send_control_event'
    assert 'content_revision' not in params and 'adjustment' not in params


@pytest.mark.parametrize('mutation', ['stale', 'wrong_slot', 'occluded', 'no_ack', 'unknown_identity', 'readonly', 'disabled', 'text_adjust'])
def test_field_input_refuses_inexact_or_noninteractive_targets(pygame_font, mutation):
    field = _field()
    if mutation == 'readonly': field = _field(flags=FieldFlag.READ_ONLY)
    if mutation == 'disabled': field = _field(state=ControlState.VISIBLE)
    if mutation == 'text_adjust': field = _field(FieldKind.TEXT)
    offer, state, ack = _input_environment(pygame_font, field)
    entries = state.hit_entries
    if mutation in ('stale', 'wrong_slot'):
        entries = tuple(replace(entry, **({'content_revision': 8} if mutation == 'stale' else {'rect':PixelRect(16,20,40,40)})) if isinstance(entry, FieldHitTarget) else entry for entry in entries)
        state, ack = _acknowledged_hit_state(offer, *entries)
    if mutation == 'occluded':
        state, ack = _acknowledged_hit_state(offer, *entries, RegionOcclusion(1,1,2,PixelRect(48,20,80,40)))
    if mutation == 'no_ack': ack = None
    client = _Client()
    value = '1,1,99999,2' if mutation == 'unknown_identity' else '1,1,90000,2'
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError):
        _request(client, offer, state, ack, value=value)
    assert client.requests == []


@pytest.mark.parametrize('value', ['1,1,90000,0','1,1,90000,9223372036854775808','1,1,90000,-9223372036854775809','1,1,90000,+1'])
def test_field_adjust_rejects_noncanonical_or_out_of_range_counts(pygame_font, value):
    offer, state, ack = _input_environment(pygame_font)
    client = _Client()
    with pytest.raises(acceptance.PhysicalDesktopAcceptanceError):
        _request(client, offer, state, ack, value=value)
    assert client.requests == []


def test_field_backpressure_records_no_accepted_input(pygame_font):
    offer, state, ack = _input_environment(pygame_font)
    client = _Client({'status':'backpressured','accepted_events':0})
    assert _request(client, offer, state, ack) == ('backpressured', None)
