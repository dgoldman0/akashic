"""Grid's real model builder: typed display values, geometry, reuse and input."""
from pathlib import Path
import re

from test_textarea import _run_forth

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "akashic/tui/applets/grid/grid.f").read_text()


def _word(name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", SOURCE)
    assert match, name
    return match.group()


def _program() -> list[str]:
    constants = SOURCE[SOURCE.index("64 CONSTANT _GRID-ROWS"):SOURCE.index("VARIABLE _GRID-CURRENT-STATE")]
    fields = re.findall(r"^_GRID-CURRENT-STATE\s+(.+?)\s+CMP-FIELD:\s+(_GRID-\S+)", SOURCE, re.M)
    cells = re.findall(r"^_GRID-CURRENT-STATE CMP-CELL: (_GRID-\S+)", SOURCE, re.M)
    # Use the production declarations' exact capacities with ordinary variables;
    # the test exercises actual applet words without booting Desk or a VFS.
    storage = "\n".join([*(f"VARIABLE {name}" for name in cells),
                         *(f"CREATE {name}-S {size} 7 + ALLOT\n: {name} {name}-S 7 + -8 AND ;" for size, name in fields
                           if name.startswith("_GRID-TGRID-") or name == "_GRID-PANEL")])
    variables = SOURCE[SOURCE.index("VARIABLE _GRID-TG-DEST"):SOURCE.index(": _GRID-TGRID-CELL-KEY")]
    words = "\n".join(_word(name) for name in (
        "_GRID-CELL", "_GRID-METRICS", "_GRID-ENSURE-VISIBLE",
        "_GRID-MOVE", "_GRID-TGRID-CELL-KEY", "_GRID-TGRID-INACTIVE",
        "_GRID-TGRID-LAYOUT", "_GRID-TGRID-COLUMNS", "_GRID-TGRID-ROW-HEADER",
        "_GRID-TGRID-CELL-TEXT", "_GRID-TGRID-DISPLAY-TEXT", "_GRID-TGRID-CELLS", "_GRID-TGRID-REBUILD",
        "_GRID-TGRID-ENSURE", "_GRID-TGRID-SELECTED", "_GRID-TGRID-SCROLLED",
        "_GRID-TGRID-POINTER?",
    ))
    prelude = r'''
VARIABLE _G-FAILS VARIABLE _G-CHECKS VARIABLE _G-FIRST VARIABLE _G-CURSOR
VARIABLE _G-FIND-KEY VARIABLE _G-DEPTH VARIABLE _G-INVALIDATIONS
VARIABLE _GM-DC VARIABLE _GM-DR
CREATE _G-MOUSE 24 ALLOT
CREATE _G-MULTILINE 3 ALLOT
: _G-ASSERT 1 _G-CHECKS +! 0= IF 1 _G-FAILS +! ." SHEET ASSERT " _G-CHECKS @ . CR THEN ;
: _G-OK USCOL-S-OK = _G-ASSERT ;
: _GRID-INVALIDATE -1 _GRID-TGRID-DIRTY ! 1 _G-INVALIDATIONS +! ;
: _G-FIND ( key -- item|0 )
    _G-FIND-KEY ! _GRID-TGRID-ACTIVE-A @ DUP USCOL-TEXT-FIRST _G-CURSOR !
    USCOL-TEXT-ITEM-COUNT@ 0 ?DO
        _G-CURSOR @ DUP USCOL-ITEM-KEY@ _G-FIND-KEY @ = IF UNLOOP EXIT THEN
        USCOL-ITEM-NEXT _G-CURSOR !
    LOOP 0 ;
: _G-CELL! ( a u value status col row -- )
    _GRID-COLS * + _GRID-CELL-SZ * _GRID-CELLS @ + >R
    R@ _GC-STATUS + ! R@ _GC-VALUE + !
    DUP R@ _GC-LEN + ! R> _GC-SOURCE + SWAP MOVE ;
'''
    # _G-CELL! takes column,row because the flat helper deliberately uses the
    # same row-major index expression as cell keys; fixtures below name row0.
    checks = r'''
0 _G-FAILS ! 0 _G-CHECKS ! 0 _G-INVALIDATIONS !
240 80 SCR-NEW SCR-USE
_GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * ALLOCATE DROP _GRID-CELLS !
_GRID-CELLS @ _GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * 0 FILL
2 3 8 54 RGN-NEW DUP _GRID-PANEL-RGN !
_GRID-PANEL 31 ROT 0 0 WDG-INIT
_GRID-PANEL-RGN @ 1 0 1 1 RGN-SUB DUP _GRID-TGRID-RGN !
TGRID-NEW DUP _GRID-TGRID-WIDGET !
' _GRID-TGRID-SELECTED OVER TGRID-ON-SELECT
' _GRID-TGRID-SCROLLED OVER TGRID-ON-SCROLL
1 OVER TGRID-CELL-INSET! -1 SWAP TGRID-FILL-SELECTION!
S" Text" 0 _GRID-ST-TEXT 0 0 _G-CELL!
S" 17" 17 _GRID-ST-NUMBER 1 0 _G-CELL!
S" =B1*2" 34 _GRID-ST-FORMULA 2 0 _G-CELL!
S" =Z99" 0 _GRID-ST-ERROR 3 0 _G-CELL!
97 _G-MULTILINE C! 10 _G-MULTILINE 1+ C! 98 _G-MULTILINE 2 + C!
_G-MULTILINE 3 0 _GRID-ST-TEXT 4 0 _G-CELL!
0 _GRID-SEL-ROW ! 0 _GRID-SEL-COL !
0 _GRID-SCROLL-ROW ! 0 _GRID-SCROLL-COL !
0 _GRID-TGRID-ACTIVE-A ! 0 _GRID-TGRID-ACTIVE-U !
0 _GRID-TGRID-BOUND-W ! 0 _GRID-TGRID-BOUND-H !
0 _GRID-TGRID-BOUND-CELL-W ! -1 _GRID-TGRID-DIRTY !
DEPTH _G-DEPTH !
_GRID-TGRID-ENSURE
DEPTH _G-DEPTH @ = _G-ASSERT
_GRID-CELL-W @ 10 = _G-ASSERT
_GRID-VIS-COLS @ 5 = _G-ASSERT
_GRID-VIS-ROWS @ 6 = _G-ASSERT
_GRID-TGRID-RGN @ RGN-ROW 3 = _G-ASSERT
_GRID-TGRID-RGN @ RGN-COL 3 = _G-ASSERT
_GRID-TGRID-RGN @ RGN-H 7 = _G-ASSERT
_GRID-TGRID-RGN @ RGN-W 54 = _G-ASSERT
_GRID-TGRID-ACTIVE-A @ DUP _G-FIRST !
DUP USCOL-TEXT-ITEM-COUNT@ 42 = _G-ASSERT
DUP USCOL-TEXT-PRIMARY-KEY@ 1 = _G-ASSERT
DUP USCOL-TEXT-ROWS@ 65 = _G-ASSERT
DUP USCOL-TEXT-COLUMNS@ 164 = _G-ASSERT
USCOL-TEXT-GRID-TYPED? _G-ASSERT
1 _G-FIND DUP USCOL-ITEM-ROLE@ USCOL-ROLE-CONTENT = _G-ASSERT
DUP USCOL-ITEM-COLUMN@ 4 = _G-ASSERT
USCOL-ITEM-TEXT@ S" Text" STR-STR= _G-ASSERT
2 _G-FIND DUP USCOL-ITEM-ROLE@ USCOL-ROLE-NUMBER = _G-ASSERT
USCOL-ITEM-TEXT@ S" 17" STR-STR= _G-ASSERT
3 _G-FIND DUP USCOL-ITEM-ROLE@ USCOL-ROLE-FORMULA = _G-ASSERT
USCOL-ITEM-TEXT@ S" 34" STR-STR= _G-ASSERT
4 _G-FIND DUP USCOL-ITEM-ROLE@ USCOL-ROLE-ERROR = _G-ASSERT
USCOL-ITEM-TEXT@ S" #ERR" STR-STR= _G-ASSERT
5 _G-FIND USCOL-ITEM-TEXT@ 5 = _G-ASSERT
DUP C@ 97 = _G-ASSERT DUP 1+ C@ 0xEF = _G-ASSERT
4 + C@ 98 = _G-ASSERT
0 4 _GRID-CELL _GC-SOURCE + 1+ C@ 10 = _G-ASSERT
_GRID-TGRID-COLUMN-KEY _G-FIND DUP USCOL-ITEM-COLUMN-SPAN@ 10 = _G-ASSERT
USCOL-ITEM-TEXT@ S"      A" STR-STR= _G-ASSERT
_GRID-TGRID-ROW-KEY _G-FIND DUP USCOL-ITEM-COLUMN-SPAN@ 4 = _G-ASSERT
USCOL-ITEM-TEXT@ S"   1" STR-STR= _G-ASSERT
253 233 0 DRW-STYLE! _GRID-TGRID-WIDGET @ WDG-DRAW
3 12 SCR-GET CELL-CP@ 65 = _G-ASSERT
4 5 SCR-GET CELL-CP@ 49 = _G-ASSERT
4 7 SCR-GET CELL-CP@ 84 = _G-ASSERT
4 24 SCR-GET CELL-CP@ 49 = _G-ASSERT
4 25 SCR-GET CELL-CP@ 55 = _G-ASSERT
4 34 SCR-GET CELL-CP@ 51 = _G-ASSERT
4 35 SCR-GET CELL-CP@ 52 = _G-ASSERT
4 37 SCR-GET CELL-CP@ 35 = _G-ASSERT
CELL-A-REVERSE 4 16 SCR-GET CELL-HAS-ATTR? _G-ASSERT
_GRID-TGRID-ENSURE
_GRID-TGRID-ACTIVE-A @ _G-FIRST @ = _G-ASSERT
0 _GRID-TGRID-DIRTY @ = _G-ASSERT
3 _GRID-TGRID-WIDGET @ TGRID-SELECT! _G-OK
_GRID-SEL-COL @ 2 = _G-ASSERT
_GRID-SEL-ROW @ 0= _G-ASSERT
_GRID-TGRID-ENSURE
_GRID-TGRID-ACTIVE-A @ _G-FIRST @ <> _G-ASSERT
_GRID-TGRID-ACTIVE-A @ USCOL-TEXT-PRIMARY-KEY@ 3 = _G-ASSERT
_KEY-TEXT-POSITION-KEY DROP
'''
    # Follow whole-cell rich PLACE and ordinary absolute CELL pointer paths.
    checks = checks.replace("_KEY-TEXT-POSITION-KEY DROP", r'''
KEY-T-MOUSE _G-MOUSE ! KEY-MOUSE-TEXT-PLACE _G-MOUSE 8 + !
4 KEY-MOUSE-TEXT-KEY ! 4 16 LSHIFT 38 OR _G-MOUSE 16 + !
_G-MOUSE _GRID-TGRID-WIDGET @ WDG-HANDLE _G-ASSERT
_GRID-SEL-COL @ 3 = _G-ASSERT
_GRID-TGRID-COLUMN-KEY KEY-MOUSE-TEXT-KEY !
_G-MOUSE _GRID-TGRID-WIDGET @ WDG-HANDLE 0= _G-ASSERT
KEY-MOUSE-LEFT _G-MOUSE 8 + ! 4 16 LSHIFT 18 OR _G-MOUSE 16 + !
_G-MOUSE _GRID-TGRID-WIDGET @ WDG-HANDLE _G-ASSERT
_GRID-SEL-COL @ 1 = _G-ASSERT
63 _GRID-SEL-ROW ! 15 _GRID-SEL-COL ! _GRID-INVALIDATE
_GRID-TGRID-ENSURE
_GRID-SCROLL-ROW @ 58 = _G-ASSERT
_GRID-SCROLL-COL @ 11 = _G-ASSERT
_GRID-TGRID-ACTIVE-A @ DUP USCOL-TEXT-VIEWPORT-ROW@ 58 = _G-ASSERT
USCOL-TEXT-VIEWPORT-COLUMN@ 110 = _G-ASSERT
1024 _G-FIND DUP USCOL-ITEM-ROW@ 64 = _G-ASSERT
DUP USCOL-ITEM-COLUMN@ 154 = _G-ASSERT
USCOL-ITEM-COLUMN-SPAN@ 10 = _G-ASSERT
_GRID-TGRID-ROW-KEY 58 + _G-FIND USCOL-ITEM-COLUMN@ 110 = _G-ASSERT
2 3 66 196 _GRID-PANEL-RGN @ RGN-BOUNDS!
_GRID-TGRID-ENSURE
_GRID-CELL-W @ 12 = _G-ASSERT
_GRID-VIS-COLS @ 16 = _G-ASSERT
_GRID-VIS-ROWS @ 64 = _G-ASSERT
_GRID-SCROLL-ROW @ 0= _G-ASSERT
_GRID-SCROLL-COL @ 0= _G-ASSERT
_GRID-TGRID-ACTIVE-A @ USCOL-TEXT-ITEM-COUNT@ _GRID-TGRID-MAX-ITEMS = _G-ASSERT
_GRID-TGRID-ACTIVE-U @ _GRID-TGRID-BANK-CAP <= _G-ASSERT
1024 _G-FIND USCOL-ITEM-COLUMN@ 184 = _G-ASSERT
DEPTH _G-DEPTH @ = _G-ASSERT
_GRID-TGRID-WIDGET @ TGRID-FREE
_GRID-TGRID-RGN @ RGN-FREE _GRID-PANEL-RGN @ RGN-FREE
_GRID-CELLS @ FREE
_G-FAILS @ 0= IF ." GRID WORKSHEET PASS " ELSE ." GRID WORKSHEET FAIL " THEN _G-CHECKS @ . _G-FAILS @ . CR
''')
    source = "\n".join((constants, storage, variables, prelude, words, checks))
    return [line for line in source.splitlines() if not line.lstrip().startswith("\\")]


def test_grid_canonical_model_preserves_geometry_values_and_selection() -> None:
    output = _run_forth(_program(), max_steps=800_000_000)
    summary = re.search(r"GRID WORKSHEET PASS\s+(\d+)\s+0", output)
    assert summary, output[-14000:]
    assert int(summary.group(1)) >= 60


def test_grid_draw_lifecycle_uses_canonical_model_and_keeps_existing_editor() -> None:
    assert "_GRID-DRAW-CELL" not in SOURCE
    assert "_GRID-TGRID-WIDGET @ ?DUP" in _word("_GRID-PANEL-DRAW")
    assert "WDG-DRAW-IN" in _word("_GRID-PANEL-DRAW")
    assert "TGRID-BIND" in _word("_GRID-TGRID-REBUILD")
    assert "_GRID-TGRID-DIRTY @" in _word("_GRID-TGRID-ENSURE")
    handle = _word("_GRID-PANEL-HANDLE")
    for operation in ("_GRID-BEGIN-EDIT", "_GRID-BEGIN-REPLACE", "_GRID-CLEAR-SELECTED", "_GRID-MOVE"):
        assert operation in handle
    assert "_GRID-TGRID-WIDGET @ WDG-HANDLE" in handle
    shutdown = _word("GRID-SHUTDOWN-CB")
    assert shutdown.index("TGRID-FREE") < shutdown.index("_GRID-TGRID-RGN @") < shutdown.index("_GRID-PANEL-RGN @")
    for forbidden in ("RTAPT-", "PT-CONTROL", "UTUI-SEMANTIC-SET", "rich-terminal.f"):
        assert forbidden not in SOURCE


def _grid_runtime():
    """Load the complete applet, including its real state-layout words."""
    from forth_dependencies import dependency_order
    from test_textarea import MEGAPAD_ROOT
    from simulator.platform import create_one_core_address_space
    from simulator.runtime import MegaForthRuntime

    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20),
        execution_backend="native",
    )
    runtime.evaluate((MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="grid-source-load-init")
    modules = dependency_order(ROOT / "akashic", ("tui/applets/grid/grid.f",))
    for module in modules:
        source = (ROOT / "akashic" / module).read_text()
        source = "\n".join(line for line in source.splitlines()
                           if not line.strip().startswith(("REQUIRE ", "PROVIDED ")))
        runtime.evaluate(source.encode(), source_name=module)
    return runtime


def test_full_grid_dependency_closure_loads_in_source_runtime() -> None:
    runtime = _grid_runtime()
    for name in ("GRID-ENTRY", "GRID-INIT-CB", "_GRID-TGRID-REBUILD",
                 "_GRID-TGRID-ENSURE", "TGRID-CELL-INSET!", "TGRID-FILL-SELECTION!"):
        assert runtime.find(name) is not None, name
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
    runtime.execute("_GRID-TGRID-BANK-CAP")
    assert runtime.main_context.data.pop() == 203256


def test_grid_panel_routes_typed_place_at_asymmetric_screen_coordinates() -> None:
    """Exercise the real panel guard before TGRID, at Desk's lower-left tile."""
    runtime = _grid_runtime()
    runtime.drain_uart_output()
    runtime.evaluate(r'''
VARIABLE _GP-FAILS VARIABLE _GP-CHECKS
CREATE _GP-EVENT 24 ALLOT
: _GP-ASSERT
    1 _GP-CHECKS +! 0= IF
        1 _GP-FAILS +! ." GRID POINTER ASSERT " _GP-CHECKS @ . CR
    THEN ;
: _GP-AT ( row column -- ) SWAP 16 LSHIFT OR _GP-EVENT 16 + ! ;
: _GP-HANDLE _GP-EVENT _GRID-PANEL WDG-HANDLE ;
_GRID-STATE-SIZE ALLOCATE DROP DUP _GRID-CURRENT-STATE !
_GRID-STATE-SIZE 0 FILL
240 84 SCR-NEW SCR-USE
_GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * ALLOCATE DROP
DUP _GRID-CELLS ! _GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * 0 FILL
43 0 38 88 RGN-NEW _GRID-PANEL-INIT
_GRID-PANEL-RGN @ 1 0 1 1 RGN-SUB DUP _GRID-TGRID-RGN !
TGRID-NEW DUP _GRID-TGRID-WIDGET !
' _GRID-TGRID-SELECTED OVER TGRID-ON-SELECT
1 OVER TGRID-CELL-INSET! -1 SWAP TGRID-FILL-SELECTION!
1 1 _GRID-CELL
_GRID-ST-NUMBER OVER _GC-STATUS + ! 3 OVER _GC-VALUE + !
1 OVER _GC-LEN + ! 51 SWAP _GC-SOURCE + C!
-1 _GRID-TGRID-DIRTY ! _GRID-TGRID-ENSURE
_GRID-TGRID-RGN @ RGN-ROW 44 = _GP-ASSERT
_GRID-TGRID-RGN @ RGN-COL 0= _GP-ASSERT
_GRID-TGRID-RGN @ RGN-H 37 = _GP-ASSERT
_GRID-TGRID-RGN @ RGN-W 88 = _GP-ASSERT
KEY-T-MOUSE _GP-EVENT ! KEY-MOUSE-TEXT-PLACE _GP-EVENT 8 + !
18 KEY-MOUSE-TEXT-KEY ! 44 0 _GP-AT
_GP-EVENT _GRID-TGRID-POINTER? _GP-ASSERT
_GP-HANDLE _GP-ASSERT
_GRID-SEL-ROW @ 1 = _GP-ASSERT _GRID-SEL-COL @ 1 = _GP-ASSERT
_GRID-TGRID-DIRTY @ _GP-ASSERT
_GRID-TGRID-ENSURE
_GRID-TGRID-ACTIVE-A @ USCOL-TEXT-PRIMARY-KEY@ 18 = _GP-ASSERT
1 KEY-MOUSE-TEXT-KEY !
43 0 _GP-AT _GP-HANDLE 0= _GP-ASSERT
81 0 _GP-AT _GP-HANDLE 0= _GP-ASSERT
44 88 _GP-AT _GP-HANDLE 0= _GP-ASSERT
44 65535 _GP-AT _GP-HANDLE 0= _GP-ASSERT
44 0 _GP-AT _GRID-TGRID-COLUMN-KEY KEY-MOUSE-TEXT-KEY !
_GP-HANDLE 0= _GP-ASSERT
_GRID-TGRID-WIDGET @ TGRID-SELECTED@ 18 = _GP-ASSERT
KEY-MOUSE-LEFT _GP-EVENT 8 + !
44 4 _GP-AT _GP-HANDLE 0= _GP-ASSERT
45 0 _GP-AT _GP-HANDLE 0= _GP-ASSERT
45 4 _GP-AT _GP-HANDLE _GP-ASSERT
_GRID-TGRID-WIDGET @ TGRID-SELECTED@ 1 = _GP-ASSERT
46 16 _GP-AT _GP-HANDLE _GP-ASSERT
_GRID-TGRID-WIDGET @ TGRID-SELECTED@ 18 = _GP-ASSERT
DEPTH 0= _GP-ASSERT
_GP-FAILS @ 0= IF ." GRID POINTER PASS " ELSE ." GRID POINTER FAIL " THEN
_GP-CHECKS @ . _GP-FAILS @ . CR
'''.encode(), source_name="grid-panel-pointer-checks", step_budget=20_000_000)
    output = runtime.drain_uart_output().decode(errors="replace")
    assert re.search(r"GRID POINTER PASS\s+23\s+0", output), (
        output, runtime.main_context.data.snapshot())
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
