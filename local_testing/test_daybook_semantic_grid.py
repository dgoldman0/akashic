#!/usr/bin/env python3
"""Focused target-byte oracle for Daybook's production semantic grid block."""

from __future__ import annotations

from pathlib import Path
import re
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
DAYBOOK = ROOT / "akashic/tui/applets/daybook/daybook.f"
COLLECTIONS = ROOT / "akashic/tui/uidl-semantic-collections.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "daybook-semantic-grid-byte-oracle"
ORACLE_PATH = "local_testing/db-sem-grid-oracle.f"
SMOKE_MAX_STEPS = 120_000_000
SMOKE_TIMEOUT_SECONDS = 15.0


_DAYBOOK_TEXT = DAYBOOK.read_text(encoding="utf-8")
_COLLECTION_TEXT = COLLECTIONS.read_text(encoding="utf-8")
_COLLECTION_BODY = "\n".join(
    line
    for line in _COLLECTION_TEXT.splitlines()
    if not line.startswith("PROVIDED ") and not line.startswith("REQUIRE ")
)


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


_PROVIDER_START = "\\  Renderer-neutral calendar grid provider\n"
_PROVIDER_END = "\\ End renderer-neutral calendar grid provider."
_provider_start = _DAYBOOK_TEXT.index(_PROVIDER_START)
_provider_start = _DAYBOOK_TEXT.rfind(
    "\\ =====================================================================", 0, _provider_start
)
_provider_end = _DAYBOOK_TEXT.index(_PROVIDER_END, _provider_start)
_provider_end = _DAYBOOK_TEXT.index("\n", _provider_end)
_PROVIDER_BODY = _DAYBOOK_TEXT[_provider_start:_provider_end]
_MONTH_NAME = _word(_DAYBOOK_TEXT, "_DB-MONTH-NAME")


ORACLE_STUBS = r'''\ Minimal production-boundary vocabulary.
PROVIDED daybook-semantic-grid-oracle

0 CONSTANT UTUI-SEMANTIC-S-OK
1 CONSTANT UTUI-SEMANTIC-S-UNSUPPORTED
2 CONSTANT UTUI-SEMANTIC-S-CAPACITY
4 CONSTANT UTUI-SEMANTIC-S-INVALID

32 CONSTANT UTUI-SEMANTIC-ENTRY-HEADER-SIZE
: UTUI-SEMANTIC-ENTRY-BYTES@       ( entry -- value )       @ ;
: UTUI-SEMANTIC-ENTRY-FAMILY@      ( entry -- value )   8 + @ ;
: UTUI-SEMANTIC-ENTRY-FAMILY-ABI@  ( entry -- value )  16 + @ ;
: UTUI-SEMANTIC-ENTRY-KEY@         ( entry -- value )  24 + @ ;

86400 CONSTANT _DB-SECONDS-DAY
VARIABLE _DB-SELECTED-DATE
VARIABLE _DB-TODAY-CACHE
VARIABLE _DB-E-BODY
VARIABLE _dsg-rgn-width
VARIABLE _dsg-rgn-height

: _DB-ACTIVATE  ( context -- ) DROP ;
: UTUI-ELEM-RGN  ( elem -- row column height width )
    DROP 0 0 _dsg-rgn-height @ _dsg-rgn-width @ ;
'''


ORACLE_CASES = r'''\ Exact wide/narrow Daybook grid cases.
VARIABLE _dsg-fails
VARIABLE _dsg-checks
VARIABLE _dsg-depth
VARIABLE _dsg-selected
VARIABLE _dsg-today
VARIABLE _dsg-first
VARIABLE _dsg-find-entry
VARIABLE _dsg-find-key
VARIABLE _dsg-find-cursor
VARIABLE _dsg-count-entry
VARIABLE _dsg-count-cursor
VARIABLE _dsg-current-count

CREATE _dsg-output-storage 4103 ALLOT
CREATE _dsg-work-storage 519 ALLOT
CREATE _dsg-summary-storage USCOL-SUMMARY-SIZE 7 + ALLOT
: _dsg-output  _dsg-output-storage 7 + -8 AND ;
: _dsg-work    _dsg-work-storage 7 + -8 AND ;
: _dsg-summary _dsg-summary-storage 7 + -8 AND ;

: _dsg-assert  ( flag -- )
    1 _dsg-checks +!
    0= IF
        1 _dsg-fails +!
        ." DAYBOOK GRID ASSERT " _dsg-checks @ . CR
    THEN ;

: _dsg-stack  ( -- )
    DEPTH DUP _dsg-depth @ <> IF
        ." DAYBOOK GRID STACK " _dsg-depth @ . ." -> " DUP . CR .S CR
    THEN
    _dsg-depth @ = _dsg-assert ;

: _dsg-ok  ( status -- )
    DUP UTUI-SEMANTIC-S-OK <> IF ." DAYBOOK GRID STATUS " DUP . CR THEN
    UTUI-SEMANTIC-S-OK = _dsg-assert ;

: _dsg-date  ( year month day -- epoch )
    DT-YMD>EPOCH-S DUP 0= _dsg-assert DROP ;

: _dsg-find  ( entry key -- item | 0 )
    _dsg-find-key ! _dsg-find-entry !
    _dsg-find-entry @ USCOL-TEXT-FIRST _dsg-find-cursor !
    _dsg-find-entry @ USCOL-TEXT-ITEM-COUNT@ 0 DO
        _dsg-find-cursor @ USCOL-ITEM-KEY@ _dsg-find-key @ = IF
            _dsg-find-cursor @ UNLOOP EXIT
        THEN
        _dsg-find-cursor @ USCOL-ITEM-NEXT _dsg-find-cursor !
    LOOP
    0 ;

: _dsg-current-items  ( entry -- count )
    _dsg-count-entry ! 0 _dsg-current-count !
    _dsg-count-entry @ USCOL-TEXT-FIRST _dsg-count-cursor !
    _dsg-count-entry @ USCOL-TEXT-ITEM-COUNT@ 0 DO
        _dsg-count-cursor @ USCOL-ITEM-STATE@ USCOL-ITEM-CURRENT AND IF
            1 _dsg-current-count +!
        THEN
        _dsg-count-cursor @ USCOL-ITEM-NEXT _dsg-count-cursor !
    LOOP
    _dsg-current-count @ ;

: _dsg-narrow  ( -- )
    _dsg-output 4096 0xA5 FILL
    71 _dsg-rgn-width ! 14 _dsg-rgn-height !
    99 1 _dsg-output 4096 _DB-SEMANTIC-SNAPSHOT _dsg-ok
    0= _dsg-assert
    _dsg-output C@ 0xA5 = _dsg-assert
    72 _dsg-rgn-width ! 13 _dsg-rgn-height !
    99 1 _dsg-output 4096 _DB-SEMANTIC-SNAPSHOT _dsg-ok
    0= _dsg-assert
    _dsg-output C@ 0xA5 = _dsg-assert ;

: _dsg-guards  ( -- )
    99 0 _dsg-output 4096 _DB-SEMANTIC-SNAPSHOT
        UTUI-SEMANTIC-S-INVALID = _dsg-assert 0= _dsg-assert
    98 1 _dsg-output 4096 _DB-SEMANTIC-SNAPSHOT
        UTUI-SEMANTIC-S-INVALID = _dsg-assert 0= _dsg-assert ;

: _dsg-wide  ( -- )
    2026 8 15 _dsg-date DUP _dsg-selected ! _DB-SELECTED-DATE !
    2026 8 20 _dsg-date DUP _dsg-today ! _DB-TODAY-CACHE !
    2026 8 1 _dsg-date _dsg-first !
    99 _DB-E-BODY !
    72 _dsg-rgn-width ! 14 _dsg-rgn-height !

    99 1 0 0 _DB-SEMANTIC-SNAPSHOT _dsg-ok 2984 = _dsg-assert
    99 1 _dsg-output 4096 _DB-SEMANTIC-SNAPSHOT
        _dsg-ok 2984 = _dsg-assert
    _dsg-output @ 2984 = _dsg-assert
    _dsg-output UTUI-SEMANTIC-ENTRY-FAMILY@
        USCOL-F-TEXT-GRID = _dsg-assert
    _dsg-output UTUI-SEMANTIC-ENTRY-FAMILY-ABI@
        USCOL-FAMILY-ABI = _dsg-assert
    _dsg-output UTUI-SEMANTIC-ENTRY-KEY@ _DB-SEM-ROOT-KEY = _dsg-assert
    _dsg-output USCOL-ROOT-HEIGHT@ _DB-CALENDAR-HEIGHT = _dsg-assert
    _dsg-output USCOL-ROOT-WIDTH@ _DB-CALENDAR-WIDTH = _dsg-assert
    _dsg-output USCOL-TEXT-ROWS@ 8 = _dsg-assert
    _dsg-output USCOL-TEXT-COLUMNS@ 7 = _dsg-assert
    _dsg-output USCOL-TEXT-ITEM-COUNT@ 39 = _dsg-assert
    _dsg-output USCOL-TEXT-PRIMARY-KEY@
        _dsg-selected @ _DB-SEM-DATE-KEY = _dsg-assert

    _dsg-output 2984 USCOL-VALIDATION-WORK-BYTES
        _dsg-ok 312 = _dsg-assert
    _dsg-output 2984 _dsg-work 312 _dsg-summary
        USCOL-ENTRY-VALIDATE _dsg-ok
    _dsg-summary USCOL-SUMMARY-FAMILY@
        USCOL-F-TEXT-GRID = _dsg-assert
    _dsg-summary USCOL-SUMMARY-ITEM-COUNT@ 39 = _dsg-assert
    _dsg-summary USCOL-SUMMARY-UTF8-BYTES@ 78 = _dsg-assert
    _dsg-summary USCOL-SUMMARY-STX1-BYTES _dsg-ok 1398 = _dsg-assert

    _dsg-output _DB-SEM-TITLE-KEY _dsg-find
    DUP 0<> _dsg-assert
    DUP USCOL-ITEM-ROW@ 0= _dsg-assert
    DUP USCOL-ITEM-COLUMN-SPAN@ 7 = _dsg-assert
    DUP USCOL-ITEM-ROLE@ USCOL-ROLE-ROW-HEADER = _dsg-assert
    USCOL-ITEM-TEXT@ S" August 2026" STR-STR= _dsg-assert

    _dsg-output _DB-SEM-WEEKDAY-KEY-BASE _dsg-find
    DUP 0<> _dsg-assert
    DUP USCOL-ITEM-ROW@ 1 = _dsg-assert
    DUP USCOL-ITEM-ROLE@ USCOL-ROLE-COLUMN-HEADER = _dsg-assert
    USCOL-ITEM-TEXT@ S" Mo" STR-STR= _dsg-assert

    _dsg-output _dsg-first @ _DB-SEM-DATE-KEY _dsg-find
    DUP 0<> _dsg-assert
    DUP USCOL-ITEM-ROW@ 2 = _dsg-assert
    DUP USCOL-ITEM-COLUMN@ 5 = _dsg-assert
    DUP USCOL-ITEM-ROLE@ USCOL-ROLE-CONTENT = _dsg-assert
    USCOL-ITEM-TEXT@ S" 1" STR-STR= _dsg-assert

    _dsg-output _dsg-today @ _DB-SEM-DATE-KEY _dsg-find
    DUP 0<> _dsg-assert
    USCOL-ITEM-STATE@ USCOL-ITEM-CURRENT = _dsg-assert
    _dsg-output _dsg-current-items 1 = _dsg-assert ;

: _dsg-run  ( -- )
    0 _dsg-fails ! 0 _dsg-checks ! DEPTH _dsg-depth !
    99 _DB-E-BODY !
    _dsg-guards _dsg-stack
    _dsg-narrow _dsg-stack
    _dsg-wide _dsg-stack
    _dsg-fails @ 0= IF
        ." DAYBOOK SEMANTIC GRID PASS " _dsg-checks @ .
    ELSE
        ." DAYBOOK SEMANTIC GRID FAIL " _dsg-fails @ .
        ." / " _dsg-checks @ .
    THEN CR ;

_dsg-run
'''


ORACLE_SOURCE = "\n\n".join(
    (
        ORACLE_STUBS.strip(),
        _COLLECTION_BODY.strip(),
        _MONTH_NAME.strip(),
        _PROVIDER_BODY.strip(),
        ORACLE_CASES.strip(),
    )
) + "\n"


AUTOEXEC = rf'''\ autoexec.f - Daybook semantic grid byte oracle
ENTER-USERLAND
." [akashic] loading Daybook semantic grid byte oracle" CR
REQUIRE utils/memory-span.f
REQUIRE text/utf8.f
REQUIRE utils/string.f
REQUIRE utils/datetime.f
REQUIRE {ORACLE_PATH}
'''


def test_daybook_semantic_grid_byte_oracle(tmp_path: Path) -> None:
    assert "_DB-SEMANTIC-SNAPSHOT" in _PROVIDER_BODY
    assert "_DB-SEMANTIC-EMIT" in _PROVIDER_BODY
    assert "REQUIRE ../../uidl-semantic-collections.f" not in _PROVIDER_BODY
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=(
            "utils/memory-span.f",
            "text/utf8.f",
            "utils/string.f",
            "utils/datetime.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DAYBOOK SEMANTIC GRID PASS",),
        stable_markers=("DAYBOOK SEMANTIC GRID PASS",),
        failure_markers=(
            "DAYBOOK SEMANTIC GRID FAIL",
            "DAYBOOK GRID ASSERT",
            "DAYBOOK GRID STACK",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(
            PROFILE_NAME,
            tmp_path / "daybook-semantic-grid.img",
        )
        assert smoke(
            PROFILE_NAME,
            image,
            cols=80,
            rows=24,
            max_steps=SMOKE_MAX_STEPS,
            timeout=SMOKE_TIMEOUT_SECONDS,
        )
    finally:
        if previous is None:
            PROFILES.pop(PROFILE_NAME, None)
        else:
            PROFILES[PROFILE_NAME] = previous


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_daybook_semantic_grid_byte_oracle(Path(directory))
