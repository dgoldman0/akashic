#!/usr/bin/env python3
"""Focused structural and target-byte oracle for Pad's ordinary provider.

The target case executes the production Pad provider section verbatim around a
tiny ordinary panel/buffer host and the production neutral collection builder.
It deliberately does not load Desk, the aggregate adapter, or a rich-terminal
module, so it stays inside the vertical gate's seconds-scale selector class.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
PAD_SOURCE = AKASHIC_ROOT / "akashic" / "tui" / "applets" / "pad" / "pad.f"
COLLECTION_SOURCE = AKASHIC_ROOT / "akashic" / "tui" / "uidl-semantic-collections.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "pad-semantic-provider-byte-oracle"
ORACLE_PATH = "local_testing/pad-sem-oracle.f"
SMOKE_MAX_STEPS = 120_000_000
SMOKE_TIMEOUT_SECONDS = 12.0

PROVIDER_START = "VARIABLE _PSS-ELEM\n"
PROVIDER_END = (
    "\\ =====================================================================\n"
    "\\  S11 -- File I/O Helpers\n"
)


def _extract_unique(source: str, start: str, end: str) -> str:
    assert source.count(start) == 1, f"start marker drift: {start!r}"
    assert source.count(end) == 1, f"end marker drift: {end!r}"
    start_at = source.index(start)
    end_at = source.index(end, start_at)
    assert start_at < end_at
    return source[start_at:end_at].rstrip()


def _definition(source: str, word: str) -> str:
    start = re.search(rf"(?m)^: {re.escape(word)}(?=\s)", source)
    assert start is not None, f"missing definition {word}"
    end = re.search(r"(?m);\s*(?:\\.*)?$", source[start.start() :])
    assert end is not None, f"unterminated definition {word}"
    return source[start.start() : start.start() + end.end()]


PAD_TEXT = PAD_SOURCE.read_text(encoding="utf-8")
PROVIDER_BODY = _extract_unique(PAD_TEXT, PROVIDER_START, PROVIDER_END)
COLLECTION_TEXT = COLLECTION_SOURCE.read_text(encoding="utf-8")
COLLECTION_BODY = "\n".join(
    line
    for line in COLLECTION_TEXT.splitlines()
    if not line.startswith("PROVIDED ") and not line.startswith("REQUIRE ")
)


ORACLE_STUBS = r'''\ Minimal ordinary Pad host plus public UIDL semantic ABI.
PROVIDED pad-semantic-provider-oracle

0 CONSTANT UTUI-SEMANTIC-S-OK
1 CONSTANT UTUI-SEMANTIC-S-UNSUPPORTED
2 CONSTANT UTUI-SEMANTIC-S-CAPACITY
3 CONSTANT UTUI-SEMANTIC-S-UNAVAILABLE
4 CONSTANT UTUI-SEMANTIC-S-INVALID
1 CONSTANT UTUI-SEMANTIC-EVENT-ACTIVATE

32 CONSTANT UTUI-SEMANTIC-ENTRY-HEADER-SIZE
: UTUI-SEMANTIC-ENTRY-BYTES@       ( entry -- value )       @ ;
: UTUI-SEMANTIC-ENTRY-FAMILY@      ( entry -- value )   8 + @ ;
: UTUI-SEMANTIC-ENTRY-FAMILY-ABI@  ( entry -- value )  16 + @ ;
: UTUI-SEMANTIC-ENTRY-KEY@         ( entry -- value )  24 + @ ;

: UTUI-SEMANTIC-INTENT-FAMILY@      ( intent -- value )       @ ;
: UTUI-SEMANTIC-INTENT-ROOT-KEY@    ( intent -- value )   8 + @ ;
: UTUI-SEMANTIC-INTENT-CHILD-KEY@   ( intent -- value )  16 + @ ;
: UTUI-SEMANTIC-INTENT-KIND@        ( intent -- value )  24 + @ ;

VARIABLE _pps-focus
VARIABLE _pps-switches
: UTUI-FOCUS!  ( elem -- )  _pps-focus ! ;
: UTUI-SEMANTIC-SET  ( revision snapshot event context elem -- status )
    2DROP 2DROP DROP UTUI-SEMANTIC-S-OK ;

16 CONSTANT _PAD-MAX-BUFS
256 CONSTANT _PAD-FNAME-CAP
4 CONSTANT _PAD-GUTTER-W
0 CONSTANT _PBE-FLAGS
8 CONSTANT _PBE-GB
24 CONSTANT _PBE-FNAME-A
32 CONSTANT _PBE-FNAME-L
40 CONSTANT _PBE-DIRTY
88 CONSTANT _PAD-BUF-ENTRY-SIZE
64 CONSTANT _PTO-CURSOR
72 CONSTANT _PTO-SCROLL-Y
88 CONSTANT _PTO-SEL-ANC
136 CONSTANT _PTO-SCROLL-X

CREATE _pps-bufs _PAD-MAX-BUFS _PAD-BUF-ENTRY-SIZE * ALLOT
CREATE _pps-tab-keys _PAD-MAX-BUFS CELLS ALLOT
CREATE _pps-label _PAD-FNAME-CAP ALLOT
CREATE _pps-builder-store 79 ALLOT
CREATE _pps-name-zero 3 ALLOT
CREATE _pps-name-one 3 ALLOT
CREATE _pps-txta 144 ALLOT
CREATE _pps-rgn 32 ALLOT

: _PAD-BUF-ENTRY  ( index -- entry )
    _PAD-BUF-ENTRY-SIZE * _pps-bufs + ;
: _PAD-TAB-KEY  ( index -- a )  CELLS _pps-tab-keys + ;
: _PAD-SEM-TAB-LABEL  ( -- a )  _pps-label ;
: _PAD-SEM-BUILDER  ( -- a )  _pps-builder-store 7 + -8 AND ;

: _PAD-BUF-LABEL  ( index -- a u )
    _PAD-BUF-ENTRY DUP _PBE-FNAME-L + @
    DUP 0= IF 2DROP S" Untitled" ELSE SWAP _PBE-FNAME-A + @ SWAP THEN ;

VARIABLE _PAD-ACTIVE
VARIABLE _PAD-TXTA
VARIABLE _PAD-E-EDITOR-AREA
VARIABLE _PAD-CURRENT-INSTANCE
VARIABLE _PAD-SEM-LIVE
VARIABLE _PAD-PANEL-DUMMY
: _PAD-PANEL  ( -- widget )  _PAD-PANEL-DUMMY ;
: WDG-REGION  ( widget -- rgn )  DROP _pps-rgn ;
: RGN-H  ( rgn -- h )  16 + @ ;
: RGN-W  ( rgn -- w )  24 + @ ;
: _PAD-ACTIVATE  ( instance -- )  DROP ;
: _PAD-BUF-SWITCH  ( index -- )
    DUP _PAD-ACTIVE ! DROP 1 _pps-switches +! ;

CREATE _pps-text 10 ALLOT
VARIABLE _pps-copy-count
VARIABLE _ppc-off
VARIABLE _ppc-dst
VARIABLE _ppc-u

: GB-LINES  ( gb -- lines )  DROP 3 ;
: GB-LINE-OFF  ( line gb -- off )
    DROP CASE 0 OF 0 ENDOF 1 OF 2 ENDOF 2 OF 6 ENDOF 0 SWAP ENDCASE ;
: GB-LINE-LEN  ( line gb -- bytes )
    DROP CASE 0 OF 1 ENDOF 1 OF 3 ENDOF 2 OF 4 ENDOF 0 SWAP ENDCASE ;
: GB-POS-LINE-COL  ( byte-offset gb -- line scalar-column )
    DROP
    DUP 0= IF DROP 0 0 EXIT THEN
    DUP 1 = IF DROP 0 1 EXIT THEN
    DUP 5 = IF DROP 1 2 EXIT THEN
    DUP 10 = IF DROP 2 4 EXIT THEN
    DROP 0 0 ;
: GB-COPY  ( off destination bytes gb -- copied )
    DROP _ppc-u ! _ppc-dst ! _ppc-off !
    _pps-text _ppc-off @ + _ppc-dst @ _ppc-u @ MOVE
    1 _pps-copy-count +!
    _ppc-u @ ;
'''


ORACLE_CASES = r'''\ Production-provider target byte cases.
VARIABLE _pps-fails
VARIABLE _pps-checks
VARIABLE _pps-depth
VARIABLE _pps-bytes
VARIABLE _pps-entry
VARIABLE _pps-status

CREATE _pps-output-store 2055 ALLOT
CREATE _pps-work-store 71 ALLOT
CREATE _pps-summary-store USCOL-SUMMARY-SIZE 7 + ALLOT
CREATE _pps-intent-store 71 ALLOT
: _pps-output  _pps-output-store 7 + -8 AND ;
: _pps-work  _pps-work-store 7 + -8 AND ;
: _pps-summary  _pps-summary-store 7 + -8 AND ;
: _pps-intent  _pps-intent-store 7 + -8 AND ;

: _pps-assert  ( flag -- )
    1 _pps-checks +!
    0= IF 1 _pps-fails +! ." PAD SEM ASSERT " _pps-checks @ . CR THEN ;
: _pps-stack  ( -- )  DEPTH _pps-depth @ = _pps-assert ;
: _pps-ok  ( status -- )
    DUP UTUI-SEMANTIC-S-OK <> IF ." PAD SEM STATUS " DUP . CR THEN
    UTUI-SEMANTIC-S-OK = _pps-assert ;

: _pps-init  ( -- )
    _pps-bufs _PAD-MAX-BUFS _PAD-BUF-ENTRY-SIZE * 0 FILL
    _pps-tab-keys _PAD-MAX-BUFS CELLS 0 FILL
    _pps-txta 144 0 FILL
    _pps-rgn 32 0 FILL
    S" one" _pps-name-zero SWAP MOVE
    S" two" _pps-name-one SWAP MOVE
    -1 0 _PAD-BUF-ENTRY _PBE-FLAGS + !
    101 0 _PAD-BUF-ENTRY _PBE-GB + !
    _pps-name-zero 0 _PAD-BUF-ENTRY _PBE-FNAME-A + !
    3 0 _PAD-BUF-ENTRY _PBE-FNAME-L + !
    9 0 _PAD-TAB-KEY !
    -1 1 _PAD-BUF-ENTRY _PBE-FLAGS + !
    202 1 _PAD-BUF-ENTRY _PBE-GB + !
    _pps-name-one 1 _PAD-BUF-ENTRY _PBE-FNAME-A + !
    3 1 _PAD-BUF-ENTRY _PBE-FNAME-L + !
    -1 1 _PAD-BUF-ENTRY _PBE-DIRTY + !
    10 1 _PAD-TAB-KEY !
    0 _PAD-ACTIVE !
    _pps-txta _PAD-TXTA !
    5 _pps-txta _PTO-CURSOR + !
    1 _pps-txta _PTO-SCROLL-Y + !
    0 _pps-txta _PTO-SEL-ANC + !
    2 _pps-txta _PTO-SCROLL-X + !
    7 _pps-rgn 16 + !
    12 _pps-rgn 24 + !
    42 _PAD-E-EDITOR-AREA !
    99 _PAD-CURRENT-INSTANCE !
    0 _pps-copy-count ! 0 _pps-switches ! 0 _pps-focus !
    [CHAR] a _pps-text C!
    10 _pps-text 1+ C!
    0xC3 _pps-text 2 + C!
    0xA9 _pps-text 3 + C!
    [CHAR] x _pps-text 4 + C!
    10 _pps-text 5 + C!
    [CHAR] t _pps-text 6 + C!
    [CHAR] a _pps-text 7 + C!
    [CHAR] i _pps-text 8 + C!
    [CHAR] l _pps-text 9 + C! ;

: _pps-snapshot-case  ( -- )
    42 99 0 0 _PAD-SEMANTIC-SNAPSHOT
    _pps-ok 560 = _pps-assert
    _pps-copy-count @ 0= _pps-assert

    42 99 _pps-output 2048 _PAD-SEMANTIC-SNAPSHOT
    _pps-ok DUP _pps-bytes ! 560 = _pps-assert
    _pps-copy-count @ 3 = _pps-assert
    _pps-output @ 176 = _pps-assert
    _pps-output UTUI-SEMANTIC-ENTRY-FAMILY@ USCOL-F-TABSET = _pps-assert
    _pps-output UTUI-SEMANTIC-ENTRY-KEY@ 1 = _pps-assert
    _pps-output USCOL-TABSET-COUNT@ 2 = _pps-assert
    _pps-output USCOL-TABSET-FIRST USCOL-TAB-KEY@ 9 = _pps-assert
    _pps-output USCOL-TABSET-FIRST USCOL-TAB-STATE@
        USCOL-STATE-VISIBLE USCOL-STATE-ENABLED OR
        USCOL-STATE-SELECTED OR = _pps-assert
    _pps-output USCOL-TABSET-FIRST USCOL-TAB-NEXT
        DUP USCOL-TAB-KEY@ 10 = _pps-assert
        DUP USCOL-TAB-LABEL-BYTES@ 4 = _pps-assert
        USCOL-TAB-LABEL@ DROP 3 + C@ [CHAR] * = _pps-assert

    _pps-output 176 + DUP _pps-entry !
    DUP @ 384 = _pps-assert
    DUP UTUI-SEMANTIC-ENTRY-FAMILY@ USCOL-F-TEXT-AREA = _pps-assert
    DUP UTUI-SEMANTIC-ENTRY-KEY@ 2 = _pps-assert
    DUP USCOL-ROOT-ROW@ 2 = _pps-assert
    DUP USCOL-ROOT-COLUMN@ 4 = _pps-assert
    DUP USCOL-ROOT-HEIGHT@ 5 = _pps-assert
    DUP USCOL-ROOT-WIDTH@ 8 = _pps-assert
    DUP USCOL-TEXT-ROWS@ 6 = _pps-assert
    DUP USCOL-TEXT-COLUMNS@ 10 = _pps-assert
    DUP USCOL-TEXT-VIEWPORT-ROW@ 1 = _pps-assert
    DUP USCOL-TEXT-VIEWPORT-COLUMN@ 2 = _pps-assert
    DUP USCOL-TEXT-PRIMARY-KEY@ 2 = _pps-assert
    DUP USCOL-TEXT-ANCHOR-KEY@ 1 = _pps-assert
    DUP USCOL-TEXT-PRIMARY-OFFSET@ 2 = _pps-assert
    DUP USCOL-TEXT-ANCHOR-OFFSET@ 0= _pps-assert
    DUP USCOL-TEXT-ITEM-COUNT@ 3 = _pps-assert
    DUP USCOL-TEXT-FIRST
        DUP USCOL-ITEM-ROW@ 0= _pps-assert
        USCOL-ITEM-NEXT
        DUP USCOL-ITEM-ROW@ 1 = _pps-assert
        DUP USCOL-ITEM-TEXT-BYTES@ 3 = _pps-assert
        DUP USCOL-ITEM-TEXT-OFFSET + C@ 0xC3 = _pps-assert
        DUP USCOL-ITEM-TEXT-OFFSET + 1+ C@ 0xA9 = _pps-assert
        USCOL-ITEM-NEXT USCOL-ITEM-ROW@ 2 = _pps-assert
    DROP

    _pps-output 176 _pps-work 16 _pps-summary
        USCOL-ENTRY-VALIDATE _pps-ok
    _pps-entry @ 384 _pps-work 24 _pps-summary
        USCOL-ENTRY-VALIDATE _pps-ok ;

: _pps-event-case  ( -- )
    _pps-intent 64 0 FILL
    USCOL-F-TABSET _pps-intent !
    1 _pps-intent 8 + !
    10 _pps-intent 16 + !
    UTUI-SEMANTIC-EVENT-ACTIVATE _pps-intent 24 + !
    42 99 _pps-intent _PAD-SEMANTIC-EVENT _pps-ok
    _PAD-ACTIVE @ 1 = _pps-assert
    _pps-focus @ 42 = _pps-assert
    _pps-switches @ 1 = _pps-assert

    0 1 _PAD-BUF-ENTRY _PBE-FLAGS + !
    0 1 _PAD-TAB-KEY !
    42 99 _pps-intent _PAD-SEMANTIC-EVENT
        UTUI-SEMANTIC-S-UNAVAILABLE = _pps-assert
    _pps-switches @ 1 = _pps-assert ;

: _pps-run  ( -- )
    0 _pps-fails ! 0 _pps-checks ! DEPTH _pps-depth !
    _pps-init
    _pps-snapshot-case _pps-stack
    _pps-event-case _pps-stack
    _pps-fails @ 0= IF
        ." PAD SEM PASS " _pps-checks @ .
    ELSE
        ." PAD SEM FAIL " _pps-fails @ . ." / " _pps-checks @ .
    THEN CR ;

_pps-run
'''


ORACLE_SOURCE = "\n\n".join(
    (
        ORACLE_STUBS.strip(),
        COLLECTION_BODY.strip(),
        PROVIDER_BODY.strip(),
        ORACLE_CASES.strip(),
    )
) + "\n"

AUTOEXEC = rf'''\ autoexec.f - Pad ordinary semantic-provider byte oracle
ENTER-USERLAND
." [akashic] loading Pad semantic-provider byte oracle" CR
REQUIRE utils/memory-span.f
REQUIRE text/utf8.f
REQUIRE {ORACLE_PATH}
'''


def test_pad_semantic_provider_structure() -> None:
    assert "REQUIRE ../../uidl-semantic-collections.f" in PAD_TEXT
    assert "rich-terminal" not in "\n".join(
        line for line in PAD_TEXT.splitlines() if line.startswith("REQUIRE ")
    )
    assert "_PAD-MAX-BUFS CELLS CMP-FIELD: _PAD-TAB-KEYS" in PAD_TEXT
    assert "1 _PAD-NEXT-TAB-KEY !" in PAD_TEXT
    assert "_PAD-NEXT-TAB-KEY @    R@ _PAD-TAB-KEY !" in PAD_TEXT
    assert "0 OVER _PAD-TAB-KEY !" in PAD_TEXT
    assert "_PBE-RESERVED" not in _definition(PAD_TEXT, "_PAD-TAB-KEY")

    assert "USCOL-TABSET-BEGIN" in PROVIDER_BODY
    assert "USCOL-F-TEXT-AREA 2" in PROVIDER_BODY
    assert "GB-POS-LINE-COL" in PROVIDER_BODY
    assert "USCOL-TEXT-ITEM-BEGIN" in PROVIDER_BODY
    assert "GB-COPY" in PROVIDER_BODY
    assert "GB-FLATTEN" not in PROVIDER_BODY
    assert "TXTA-GET-TEXT" not in PROVIDER_BODY
    assert "ALLOCATE" not in PROVIDER_BODY
    assert "_PSS-DOC-ROWS @ 0 DO" in PROVIDER_BODY
    assert "_PSS-ANCHOR-KEY @" in _definition(PAD_TEXT, "_PAD-SEM-CARRY-LINE?")

    event = _definition(PAD_TEXT, "_PAD-SEMANTIC-EVENT")
    assert "UTUI-SEMANTIC-INTENT-CHILD-KEY@" in event
    assert "_PAD-E-EDITOR-AREA @ UTUI-FOCUS!" in event
    assert "I _PAD-BUF-SWITCH" in event
    assert "UTUI-SEMANTIC-S-UNAVAILABLE" in event

    init = _definition(PAD_TEXT, "PAD-INIT-CB")
    assert init.index("_PAD-PANEL _PAD-E-EDITOR-AREA @ UTUI-WIDGET-SET") < init.index(
        "_PAD-BUF-OPEN DROP"
    ) < init.index("_PAD-SEMANTIC-REGISTER")
    advance = _definition(PAD_TEXT, "_PAD-SEMANTIC-ADVANCE")
    assert "UTUI-SEMANTIC-ADVANCE" in advance
    assert "UTUI-SEMANTIC-TOUCH" not in advance
    assert "_PAD-SEM-EDITOR-END" in _definition(PAD_TEXT, "_PAD-HANDLE-EDITOR")
    on_change = _definition(PAD_TEXT, "_PAD-ON-CHANGE")
    assert on_change.count("_PAD-SEMANTIC-ADVANCE") == 1
    editor_end = _definition(PAD_TEXT, "_PAD-SEM-EDITOR-END")
    assert editor_end.index("_PAD-SEM-EVENT-CHANGED @ IF EXIT THEN") < editor_end.index(
        "_PAD-SEMANTIC-ADVANCE"
    )
    delete_line = _definition(PAD_TEXT, "_PAD-DO-DELETE-LINE")
    assert "_PAD-SELECT-RANGE-RAW" in delete_line
    assert "_PAD-SELECT-RANGE\n" not in delete_line


def test_pad_semantic_provider_target_byte_oracle(tmp_path: Path) -> None:
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255
    assert "GB-FLATTEN" not in PROVIDER_BODY
    assert "PAD SEM PASS" in ORACLE_SOURCE

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("utils/memory-span.f", "text/utf8.f"),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("PAD SEM PASS",),
        stable_markers=("PAD SEM PASS",),
        failure_markers=(
            "PAD SEM FAIL",
            "PAD SEM ASSERT",
            "PAD SEM STATUS",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(PROFILE_NAME, tmp_path / "pad-semantic-provider.img")
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

    test_pad_semantic_provider_structure()
    with tempfile.TemporaryDirectory() as directory:
        test_pad_semantic_provider_target_byte_oracle(Path(directory))
