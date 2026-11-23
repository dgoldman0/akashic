#!/usr/bin/env python3
"""A game board as a canonical text grid (akashic/tui/game/board.f).

The checks build boards over small maps on native machines with a token
that draws walls, floor, an archivist and tiles out of sight, and read the
CELL screen the text grid draws: each tile two cells wide in the middle of
its region, the current tile underlined, the cursor's tile reversed and a
tile out of sight dim.  A press on a tile reaches the game as the tile's
map position, and one out of sight is refused.  A map larger than its
region shows the window the game asks for, kept on the map; a region that
changes size calls for a rebuild; banks grow when the tiles' text grows;
and repeated rebuilds keep the heap flat.
"""
from native_forth import NativeForth

HELPERS = (
    "VARIABLE B  VARIABLE SEL-X  VARIABLE SEL-Y  VARIABLE WIDE  VARIABLE X0",
    "-1 SEL-X ! -1 SEL-Y ! 0 WIDE !",
    # A room of w by h: walls on its edges, the archivist at (1,1), tiles
    # from x = 4 out of sight.  WIDE makes every tile's text eight bytes.
    "VARIABLE RW  VARIABLE RH",
    ": EDGE?  ( x y -- f )  DUP 0= SWAP RH @ 1- = OR"
    "  SWAP DUP 0= SWAP RW @ 1- = OR OR ;",
    ": TOK  ( x y ctx -- a u state )",
    "    DROP WIDE @ IF 2DROP S\" ########\" 0 EXIT THEN",
    "    2DUP 1 = SWAP 1 = AND IF 2DROP S\" @ \" BOARD-CURRENT EXIT THEN",
    "    OVER 4 >= IF EDGE? IF S\" # \" ELSE S\" . \" THEN"
    "        BOARD-UNAVAILABLE EXIT THEN",
    "    EDGE? IF S\" # \" ELSE S\" . \" THEN 0 ;",
    ": ONSEL  ( x y ctx -- )  DROP SEL-Y ! SEL-X ! ;",
    ": ROW.  ( r -- )  .\" |\" 20 0 DO DUP I SCR-GET CELL-CP@"
    "  DUP 33 < IF DROP 95 THEN EMIT LOOP DROP ;",
    "CREATE EV 24 ALLOT",
    ": CLICK  ( row col -- consumed? )",
    "    KEY-T-MOUSE EV !  KEY-MOUSE-LEFT EV 8 + !",
    "    SWAP 16 LSHIFT OR EV 16 + !  EV B @ BOARD-WIDGET WDG-HANDLE ;",
    ": BOARD  ( h w map-w map-h -- )",
    "    2DUP RH ! RW !  >R >R 0 0 2SWAP R> R> BOARD-NEW B !",
    "    ['] TOK 0 B @ BOARD-TOKEN!  ['] ONSEL B @ BOARD-ON-SELECT ;",
    "40 12 SCR-NEW SCR-USE",
)

SUITE = NativeForth(("tui/game/board.f",), prelude=HELPERS)


def run(lines) -> str:
    raw = SUITE.run(['." RESULT: "', *lines, 'CR'], 400_000_000)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (10, 13, 9) else ""
                   for b in raw)
    assert "RESULT:" in text, text[-600:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail, tail[-600:]
    return " ".join(tail.split())


def test_a_room_draws_in_the_middle_of_its_region():
    """A room of 6 by 3 tiles in a region of 5 rows and 20 columns draws
    two cells a tile, one row and four columns in from the region's edge.
    The archivist's tile is current and underlined, the cursor's tile is
    the primary item and reversed, and a tile out of sight draws dim."""
    got = run([
        "5 20 6 3 BOARD  2 1 B @ BOARD-CURSOR!",
        "B @ BOARD-REBUILD . B @ BOARD-VIEW . . B @ BOARD-FITS? .",
        "SCR-CLEAR B @ BOARD-WIDGET WDG-DRAW",
        "0 ROW. 1 ROW. 2 ROW. 3 ROW. 4 ROW.",
        "CELL-A-UNDERLINE 2 6 SCR-GET CELL-HAS-ATTR? .",
        "CELL-A-REVERSE 2 8 SCR-GET CELL-HAS-ATTR? .",
        "CELL-A-DIM 1 12 SCR-GET CELL-HAS-ATTR? .",
        "CELL-A-DIM 1 10 SCR-GET CELL-HAS-ATTR? .",
    ])
    blank, wall = "_" * 20, "____" + "#_" * 6 + "____"
    rows = (blank, wall, "____#_@_._._._#_____", wall, blank)
    assert got == "0 3 6 -1 " + "".join("|" + row for row in rows) + "-1 -1 -1 0", got


def test_a_press_selects_a_tile_by_its_map_position():
    """A press on a tile in sight reaches the game as the tile's map
    position; one on a tile out of sight is refused and reaches nothing."""
    got = run([
        "5 20 6 3 BOARD  B @ BOARD-REBUILD .",
        "3 10 CLICK . SEL-X @ . SEL-Y @ .",
        "3 14 CLICK . SEL-X @ . SEL-Y @ .",
        "2 6 CLICK . SEL-X @ . SEL-Y @ .",
    ])
    assert got == "0 -1 3 2 0 3 2 -1 1 1", got


def test_a_map_larger_than_its_region_shows_the_window_asked_for():
    """A map of 30 by 10 in a region of 4 rows and 20 columns shows a
    window of 10 by 4 tiles.  The window the game asks for is kept on the
    map, and a tile keeps its key, its map position, as the window moves."""
    got = run([
        "4 20 30 10 BOARD",
        "5 3 B @ BOARD-WINDOW! B @ BOARD-REBUILD . B @ BOARD-VIEW . .",
        "B @ BOARD-ORIGIN . .",
        "99 99 B @ BOARD-WINDOW! B @ BOARD-REBUILD . B @ BOARD-ORIGIN . .",
        "-4 -4 B @ BOARD-WINDOW! B @ BOARD-REBUILD . B @ BOARD-ORIGIN . .",
        "SCR-CLEAR B @ BOARD-WIDGET WDG-DRAW",
        "2 2 CLICK . SEL-X @ . SEL-Y @ .",
        "2 3 B @ BOARD-WINDOW! B @ BOARD-REBUILD .",
        "SCR-CLEAR B @ BOARD-WIDGET WDG-DRAW",
        "0 2 CLICK . SEL-X @ . SEL-Y @ .",
    ])
    assert got == "0 4 10 3 5 0 6 20 0 0 0 -1 1 2 0 -1 3 3", got


def test_a_region_that_changes_size_calls_for_a_rebuild():
    """Once the region changes size, as UIDL gives the widget its
    element's geometry, the board no longer fits until it is rebuilt."""
    got = run([
        "5 20 6 3 BOARD  B @ BOARD-REBUILD . B @ BOARD-FITS? .",
        "0 0 7 30 B @ BOARD-WIDGET WDG-REGION RGN-BOUNDS! B @ BOARD-FITS? .",
        "B @ BOARD-REBUILD . B @ BOARD-FITS? . B @ BOARD-VIEW . .",
        "0 0 2 6 B @ BOARD-WIDGET WDG-REGION RGN-BOUNDS!",
        "B @ BOARD-REBUILD . B @ BOARD-VIEW . .",
    ])
    assert got == "0 -1 0 0 -1 3 6 0 2 3", got


def test_banks_grow_with_the_tiles_text_and_the_heap_stays_flat():
    """Tiles whose text grows past the banks' room make the board measure
    the model and grow its banks, keeping the bound model until the new one
    binds.  Twenty more rebuilds leave the extended heap where the first
    left it."""
    got = run([
        "10 40 20 10 BOARD  B @ BOARD-REBUILD .",
        "-1 WIDE ! B @ BOARD-REBUILD .",
        "0 WIDE ! B @ BOARD-REBUILD .  XMEM-HERE @ X0 !",
        ": TWENTY  20 0 DO B @ BOARD-REBUILD DROP LOOP ;  TWENTY",
        "XMEM-HERE @ X0 @ - .",
        "B @ BOARD-FREE",
    ])
    assert got == "0 0 0 0", got
