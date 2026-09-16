"""Exact acknowledged projection coverage, independent of content revisions."""
import struct

import pytest

from test_rich_instrument_reuse import InstrumentHarness
from test_rich_glyph_growth import MASK64


@pytest.fixture(params=['python', 'native'])
def projection(request):
    h = InstrumentHarness(request.param, (
        '_RTHP-RD-MARK-CURRENT-CLAIMS?', '_RTHP-PACK-PROJECTION-RECTS-A',
        '_RTHP-U-CLONE?', '_RTHP-RD-SCAN-ACTIVE-ROW?',
    ))
    h.setup(units=b'', kinds=(), controls=4)
    h.claims = h.cursor
    h.damage = h.cursor + 320 + 8
    h.runtime.memory.write_bytes(h.damage - 8, b'LEFTGUAR' + bytes(2) + b'RIGHTGUA')
    h.field(h.producer, '_RTHP.CLAIMS-A', h.claims)
    h.field(h.producer, '_RTHP.CLAIMS-U', 320)
    h.field(h.producer, '_RTHP.ROW-DAMAGE-A', h.damage)
    h.field(h.producer, '_RTHP.ROW-DAMAGE-U', 2)
    for name, value in (('_RTHP-RD-P', h.producer), ('_RTHP-RD-BANK', h.bank),
                        ('_RTHP-RD-ROWS', 2), ('_RTHP-RD-COLS', 8)):
        h.variable(name, value)
    return h


def claims(h, rects, *, menus=0, generation=1):
    assert len(rects) <= 4
    payload = b''.join(struct.pack('<10Q', 1, generation, 1, i, 0, 0,
                                    *(x & MASK64 for x in rect))
                       for i, rect in enumerate(rects))
    h.runtime.memory.write_bytes(h.claims, payload)
    h.field(h.producer, '_RTHP.CLAIMS-USED', len(payload))
    h.field(h.producer, '_RTHP.MENU-CLAIMS', menus)


def capture(h, rects, *, menus=0):
    claims(h, rects, menus=menus)
    assert h.call('_RTHP-PACK-ADMITTED-CANDIDATE', h.bank, h.producer)
    assert h.call('_RTHP-PACKED-BANK?', h.bank, h.producer)
    return h.runtime.memory.read_bytes(h.bank, h.bank_size)


def damage(h, before):
    assert h.call('_RTHP-RD-MARK-CURRENT-CLAIMS?')
    assert h.runtime.memory.read_bytes(h.bank, h.bank_size) == before
    assert h.runtime.memory.read_bytes(h.damage - 8, 8) == b'LEFTGUAR'
    assert h.runtime.memory.read_bytes(h.damage + 2, 8) == b'RIGHTGUA'
    return h.runtime.memory.read_bytes(h.damage, 2)


def test_content_revision_does_not_rebuild_unchanged_coverage(projection):
    h = projection
    rects = [(0, 0, 2, 8)]
    before = capture(h, rects)
    claims(h, rects, generation=999)
    # CELL and residue differences remain authoritative even when coverage
    # is unchanged. The optimization may not clear a previously dirty row.
    h.runtime.memory.write_bytes(h.damage, bytes((255, 0)))
    assert damage(h, before) == bytes((255, 0))
    assert h.runtime.memory.read_bytes(h.packed('PROJECTION-RECTS'), 32) == struct.pack('<4Q', *rects[0])


def test_acknowledged_empty_residual_rows_keep_the_coverage_proof(projection):
    h = projection
    rects = [(0, 0, 2, 8)]
    before = capture(h, rects)
    claims(h, rects, generation=999)
    assert damage(h, before) == bytes(2)
    h.variable('_RTHP-RD-ACTIVE-I', 0)
    h.variable('_RTHP-RD-ACTIVE-ITEMS', h.packed('ITEMS'))
    for row in range(2):
        h.variable('_RTHP-RD-ROW', row)
        assert h.call('_RTHP-RD-SCAN-ACTIVE-ROW?')
    assert h.runtime.memory.read_bytes(h.damage, 2) == bytes(2)
    assert h.runtime.memory.read_bytes(h.bank, h.bank_size) == before


@pytest.mark.parametrize('old,new,expected', [
    ([(0, 0, 1, 8)], [(1, 0, 2, 8)], (255, 255)),  # move
    ([(0, 0, 1, 8)], [], (255, 0)),                 # hide/remove
    ([], [(1, 0, 2, 8)], (0, 255)),                 # new root
    ([(0, 0, 1, 8)], [(0, 0, 1, 4)], (255, 0)),   # shrink horizontally
    ([(0, 0, 1, 8)], [(0, 0, 2, 8)], (255, 255)), # grow vertically
    ([(0, 0, 2, 8)], [(0, 0, 2, 8)], (0, 0)),     # no damage
])
def test_geometry_changes_cover_both_old_and_new_rows(projection, old, new, expected):
    before = capture(projection, old)
    claims(projection, new)
    assert damage(projection, before) == bytes(expected)


def test_menu_and_nonmenu_coverage_have_distinct_authority(projection):
    h = projection
    before = capture(h, [(0, 0, 1, 8), (1, 0, 2, 8)], menus=1)
    assert damage(h, before) == bytes((255, 0))
    # Removing a semantic root in favor of a menu may leave identical bounds
    # but must still rebuild the formerly suppressed residual pixels.
    h.runtime.memory.write_bytes(h.damage, bytes(2))
    claims(h, [(0, 0, 1, 8), (1, 0, 2, 8)], menus=2)
    assert damage(h, before) == bytes((255, 255))


@pytest.mark.parametrize('rect', [(-1, 0, 1, 8), (0, -1, 1, 8), (1, 0, 1, 8),
                                 (0, 2, 1, 2), (0, 0, 3, 8), (0, 0, 1, 9)])
def test_bad_projection_rectangles_cannot_be_captured(projection, rect):
    h = projection
    claims(h, [rect])
    assert not h.call('_RTHP-PACK-ADMITTED-CANDIDATE', h.bank, h.producer)
    assert h.runtime.memory.read64(h.bank + h.offset('_RTHP-TB.VALID')) == 0
    h.guards()


def test_invalid_old_rectangle_falls_back_without_overrunning_damage(projection):
    h = projection
    capture(h, [(0, 0, 1, 8)])
    h.runtime.memory.write64(h.packed('PROJECTION-RECTS') + 16, 3)
    assert not h.call('_RTHP-RD-MARK-CURRENT-CLAIMS?')
    assert h.runtime.memory.read_bytes(h.damage + 2, 8) == b'RIGHTGUA'


def test_clone_owns_projection_coverage_after_source_reuse(projection):
    h = projection
    before = capture(h, [(0, 0, 2, 8)])
    h.field(h.producer, '_RTHP.TARGET-ACTIVE', h.bank)
    for name, value in (('_RTHP-U-P', h.producer), ('_RTHP-U-ACTIVE', h.bank),
                        ('_RTHP-U-DRAW', 2), ('_RTHP-U-SOURCE-GEN', 2),
                        ('_RTHP-U-CONTENT-EPOCH', 2)):
        h.variable(name, value)
    assert h.call('_RTHP-U-CLONE?')
    offset = h.packed('PROJECTION-RECTS') - h.bank
    h.runtime.memory.write_bytes(h.claims, bytes(320))
    assert h.runtime.memory.read_bytes(h.other + offset, 32) == struct.pack('<4Q', 0, 0, 2, 8)
    assert h.runtime.memory.read_bytes(h.bank, h.bank_size) == before
