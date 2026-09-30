"""Sparse noninteractive regions must not shadow independent FIELD value hits."""
from dataclasses import replace

import pytest
import akashic_tui  # noqa: F401
from rich_terminal.appearance import FLOWING_APPEARANCE, REFERENCE_APPEARANCE
from rich_terminal.pygame_view import (
    FieldHitTarget, ResidualPoint, composite_draw_plane_result, resolve_pointer,
)
from rich_terminal.retained_scene import ObjectBounds, RGBA
from rich_terminal.retained_view import MeterDraw, _draw_order_key
from test_rich_terminal_desktop_acceptance import _offer, _glyph_draws_outside, _acknowledged_hit_state
from test_rich_terminal_field_acceptance import _field, _Client, _request
from rich_terminal_desktop_acceptance import reconstruct_retained_screen


@pytest.mark.parametrize('appearance', [REFERENCE_APPEARANCE, FLOWING_APPEARANCE])
def test_sparse_instruments_below_base_preserve_raster_and_all_field_hits(appearance):
    pygame = pytest.importorskip('pygame')
    pygame.font.init()
    font = pygame.font.Font(None, 16)
    cols, rows, cw, ch = 12, 8, 8, 20
    offer = _offer('\n'.join(' ' * cols for _ in range(rows)))
    base = offer.retained.regions[0]
    fields = tuple(replace(_field(), control_id=90000 + index,
                           bounds=ObjectBounds(2, index, 8, 1)) for index in range(4))
    meters = tuple(MeterDraw(91000 + index, 0, ObjectBounds(2, 5 + index, 8, 1),
                            RGBA(95, 215, 255, 255), RGBA(40, 50, 60, 255),
                            False, False, 0, 100, 65) for index in range(2))
    claimed = {(col, row) for row in (*range(4), 5, 6) for col in range(2, 10)}
    base = replace(base, draws=tuple(sorted(
        (*_glyph_draws_outside(cols, rows, claimed), *fields), key=_draw_order_key)))
    # Both sparse widget regions span the controls, but their actual draws and
    # admitted claims are disjoint. Preserve their different authored Z order.
    instruments = tuple(replace(base, region_id=2 + index, z_order=z,
                                draws=(meters[index],)) for index, z in enumerate((2, 5)))
    old_plane = replace(offer.retained, regions=(base, *instruments))
    promoted = replace(base, z_order=6)
    new_plane = replace(old_plane, regions=(*instruments, promoted))
    old_surface = pygame.Surface((cols * cw, rows * ch))
    new_surface = pygame.Surface(old_surface.get_size())
    old = composite_draw_plane_result(pygame, old_surface, old_plane, font, cw, ch,
                                      appearance=appearance)
    new = composite_draw_plane_result(pygame, new_surface, new_plane, font, cw, ch,
                                      appearance=appearance)
    assert pygame.image.tobytes(old_surface, 'RGB') == pygame.image.tobytes(new_surface, 'RGB')
    assert tuple((r.region_id, r.z_order) for r in new_plane.regions[:-1]) == ((2, 2), (3, 5))
    targets = tuple(t for t in new.hit_entries if isinstance(t, FieldHitTarget))
    assert len(targets) == 4
    new_offer = replace(offer, retained=new_plane)
    projection = reconstruct_retained_screen(new_offer, require_menu_bar=False)
    assert len(projection.semantic_field_claims) == 4
    assert len(projection.instrument_claims) == 2
    state, ack = _acknowledged_hit_state(new_offer, *new.hit_entries)
    for target in targets:
        x = (target.rect.left + target.rect.right) // 2
        y = (target.rect.top + target.rect.bottom) // 2
        assert isinstance(resolve_pointer(old.hit_entries, x, y, cell_width=cw,
                                          cell_height=ch), ResidualPoint)
        assert resolve_pointer(new.hit_entries, x, y, cell_width=cw, cell_height=ch) == target
        client = _Client()
        outcome, evidence = _request(client, new_offer, state, ack,
            value=f'1,1,{target.identity.control_id},3')
        assert outcome == 'progress'
        assert evidence.semantic_target['content_revision'] == target.content_revision
        assert client.requests[0][0] == 'send_text_event'
