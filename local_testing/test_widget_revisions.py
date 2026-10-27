#!/usr/bin/env python3
"""Every canonical widget something uses counts each change to what it
shows, and nothing else.

For each kind, a scenario drives one widget through every public word that
changes what it shows, drawing it after each, and checks that each word
moved its revision (WDG-REVISION).  A second widget, made the same way,
takes the same words without a draw between them; then both draw in the
same place, and their cells must be the same, so nothing an earlier draw
left behind changes what the first one shows.  Then every word that only
reads the widget, captures it, checks it or sets what it calls is called on
the first widget, and moves nothing.

The kinds are the fifteen something uses: list, tree, tabs, text area,
input, prompt, dialog, picture, text grid, field, data graphics, explorer,
canvas, media and the document view.  A widget that shows others counts
their changes in its own revision, so the scenarios of the prompt, the
explorer and the media widget also pass keys through them to the widgets
they hold.

test_every_public_word_is_placed holds each module's public words against
these lists, so a word added later is placed here: among the changes when it
changes what the widget shows, among the words that move nothing when it
takes a widget and shows nothing new, and otherwise among the rest, which
make or free a widget or do not take one.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import pytest

import qoi_codec
from test_field_model import PRELUDE, run_field

ROOT = Path(__file__).resolve().parents[1]

# Steps are words of no inputs that act on the widget in _WR-W.
# _WR-STEP keeps one, and _WR-PREP one that only sets up the next, with no
# check and no draw after it.  _WR-RUN runs the kept steps on the first
# widget, checking and drawing after each, then on the second without
# either, and compares what the two draw.  _WR-STILL runs one word and
# checks that the revision stayed.  _WR-REV is the revision checked: a
# widget's own, or for a widget made of others, its own and theirs added.
COMMON = r'''
40 16 SCR-NEW SCR-USE
DEFER _WR-REV  ( widget -- n )  ' WDG-REVISION IS _WR-REV
VARIABLE _WR-W  VARIABLE _WR-R
: _WR-MOVES  ( xt -- )
    _WR-W @ _WR-REV _WR-R !  EXECUTE
    _WR-W @ _WR-REV _WR-R @ <> _FM-A  _WR-W @ WDG-DRAW ;
: _WR-STILL  ( xt -- )
    _WR-W @ _WR-REV _WR-R !  EXECUTE
    _WR-W @ _WR-REV _WR-R @ = _FM-A ;
CREATE _WR-STEPS 64 CELLS ALLOT  CREATE _WR-PREPS 64 CELLS ALLOT
VARIABLE _WR-N  0 _WR-N !
: _WR-KEEP  ( xt prep? -- )
    _WR-PREPS _WR-N @ CELLS + !  _WR-STEPS _WR-N @ CELLS + !  1 _WR-N +! ;
: _WR-STEP  ( xt -- )  0 _WR-KEEP ;
: _WR-PREP  ( xt -- )  -1 _WR-KEEP ;
: _WR-CHANGES  ( -- )
    _WR-W @ WDG-DRAW
    _WR-N @ 0 ?DO
        _WR-STEPS I CELLS + @
        _WR-PREPS I CELLS + @ IF EXECUTE ELSE _WR-MOVES THEN
    LOOP ;
: _WR-REPLAY  ( -- )  _WR-N @ 0 ?DO _WR-STEPS I CELLS + @ EXECUTE LOOP ;
CREATE _WR-CELLS-1 640 CELLS ALLOT  CREATE _WR-CELLS-2 640 CELLS ALLOT
: _WR-SNAP  ( cells widget -- )
    SCR-CLEAR WDG-DRAW
    16 0 ?DO 40 0 ?DO J I SCR-GET OVER J 40 * I + CELLS + ! LOOP LOOP DROP ;
: _WR-RUN  ( first second -- )
    OVER _WR-W ! _WR-CHANGES  DUP _WR-W ! _WR-REPLAY
    >R _WR-CELLS-1 SWAP _WR-SNAP  _WR-CELLS-2 R> _WR-SNAP
    _WR-CELLS-1 640 CELLS _WR-CELLS-2 640 CELLS COMPARE 0= _FM-A ;
: _WR-NOP1  ( x -- )  DROP ;
: _WR-NOP2  ( x y -- )  2DROP ;
CREATE _WR-BLD-S USCOL-BUILDER-SIZE 7 + ALLOT
: _WR-BLD  _WR-BLD-S 7 + -8 AND ;
CREATE _WR-OUT-S 4096 7 + ALLOT
: _WR-OUT  _WR-OUT-S 7 + -8 AND ;
''' + "CREATE _WR-TEXT " + " ".join(
    f"{byte} C," for byte in
    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
) + "\n"


@dataclass(frozen=True)
class Kind:
    modules: tuple[str, ...]
    change: tuple[str, ...]
    same: tuple[str, ...]
    other: tuple[str, ...]
    scenario: str
    minimum: int


KINDS: dict[str, Kind] = {}


KINDS["list"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/list.f"),
    change=(
        "LST-ROWS!", "LST-SELECT", "LST-SCROLL-TO", "LST-SCROLL-END",
        "LST-SCROLL-SET", "LST-CONTEXT!", "LST-ROW-FLAGS!", "LST-COLUMNS!",
        "LST-STYLE!", "LST-RECOUNT", "LST-REFRESH", "LST-MODE!",
    ),
    same=(
        "LST-COUNT", "LST-SELECTED", "LST-CONTEXT@", "LST-SCROLL-INFO",
        "LST-ITEM-VIEW-MEASURE", "LST-ITEM-VIEW-CAPTURE", "LST-INSTANCE@",
        "LST-GENUINE?", "LST-ITEM-VIEW-STORAGE-DISJOINT?", "LST-ON-SELECT",
        "LST-ON-OPEN", "LST-ON-CHECK",
    ),
    other=("LST-NEW", "LST-FREE", "LST-STORAGE-DISJOINT?"),
    minimum=25,
    scenario=r'''
\ Row I shows three letters from the I-th, and the second column from the
\ I+1-th; row 3 becomes a heading.
: _LS-KEY  ( index widget -- key )  DROP 1+ ;
: _LS-FIELD  ( index column widget -- a u )  DROP + _WR-TEXT + 3 ;
: _LS-FLAGS  ( index widget -- flags )  DROP 3 = IF LST-ROW-SECTION ELSE 0 THEN ;
: _LS-STYLE  ( a u map index column widget -- styled? )  2DROP 2DROP 2DROP 0 ;
CREATE _LS-COLS LST-COLUMN-SIZE 2 * ALLOT  _LS-COLS LST-COLUMN-SIZE 2 * 0 FILL
LST-TEXT-COLUMN _LS-COLS LST-COLUMN-KIND + !
: _LS-NAME  S" Name" ;
_LS-NAME _LS-COLS LST-COLUMN-LABEL-U + ! _LS-COLS LST-COLUMN-LABEL-A + !
LST-NUMBER-COLUMN _LS-COLS LST-COLUMN-SIZE + LST-COLUMN-KIND + !
6 _LS-COLS LST-COLUMN-SIZE + LST-COLUMN-WIDTH + !
: _LS-MAKE  ( -- widget )  0 0 6 30 RGN-NEW ['] _LS-KEY ['] _LS-FIELD LST-NEW ;
: _LS1  20 _WR-W @ LST-ROWS! ;         ' _LS1 _WR-STEP
: _LS2  7 _WR-W @ LST-SELECT ;         ' _LS2 _WR-STEP
: _LS3  15 _WR-W @ LST-SCROLL-TO ;     ' _LS3 _WR-STEP
: _LS4  _WR-W @ LST-SCROLL-END ;       ' _LS4 _WR-STEP
: _LS5  2 _WR-W @ LST-SCROLL-SET ;     ' _LS5 _WR-STEP
: _LS6  9 _WR-W @ LST-CONTEXT! ;       ' _LS6 _WR-STEP
: _LS7  ['] _LS-FLAGS _WR-W @ LST-ROW-FLAGS! ;  ' _LS7 _WR-STEP
: _LS8  _LS-COLS 2 _WR-W @ LST-COLUMNS! ;       ' _LS8 _WR-STEP
: _LS9  ['] _LS-STYLE _WR-W @ LST-STYLE! ;      ' _LS9 _WR-STEP
: _LS10  25 _WR-W @ LST-RECOUNT ;      ' _LS10 _WR-STEP
: _LS11  _WR-W @ LST-REFRESH ;         ' _LS11 _WR-STEP
: _LS12  LST-UNTRUSTED _WR-W @ LST-MODE! ;      ' _LS12 _WR-STEP
_LS-MAKE CONSTANT _LS-A  _LS-MAKE CONSTANT _LS-B
_LS-A _LS-B _WR-RUN
_LS-A _WR-W !
: _LQ1  _WR-W @ LST-COUNT DROP ;       ' _LQ1 _WR-STILL
: _LQ2  _WR-W @ LST-SELECTED DROP ;    ' _LQ2 _WR-STILL
: _LQ3  _WR-W @ LST-CONTEXT@ DROP ;    ' _LQ3 _WR-STILL
: _LQ4  _WR-W @ LST-SCROLL-INFO 2DROP DROP ;    ' _LQ4 _WR-STILL
: _LQ5  5 _WR-BLD _WR-W @ LST-ITEM-VIEW-MEASURE 2DROP ;   ' _LQ5 _WR-STILL
: _LQ6  5 _WR-OUT 4096 _WR-BLD _WR-W @ LST-ITEM-VIEW-CAPTURE 2DROP ;
' _LQ6 _WR-STILL
: _LQ7  _WR-W @ LST-INSTANCE@ DROP ;   ' _LQ7 _WR-STILL
: _LQ8  _WR-W @ LST-GENUINE? DROP ;    ' _LQ8 _WR-STILL
: _LQ9  _WR-OUT 4096 _WR-W @ LST-ITEM-VIEW-STORAGE-DISJOINT? DROP ;
' _LQ9 _WR-STILL
: _LQ10  ['] _WR-NOP2 _WR-W @ LST-ON-SELECT ;   ' _LQ10 _WR-STILL
: _LQ11  ['] _WR-NOP2 _WR-W @ LST-ON-OPEN ;     ' _LQ11 _WR-STILL
: _LQ12  ['] _WR-NOP2 _WR-W @ LST-ON-CHECK ;    ' _LQ12 _WR-STILL
''',
)


KINDS["tree"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/tree.f"),
    change=(
        "TREE-EXPAND", "TREE-SELECT", "TREE-COLLAPSE", "TREE-TOGGLE",
        "TREE-EXPAND-KEY", "TREE-COLLAPSE-ALL", "TREE-EXPAND-ALL",
        "TREE-SCROLL-SET", "TREE-CONTEXT!", "TREE-UNTRUSTED!", "TREE-REFRESH",
    ),
    same=(
        "TREE-SELECTED", "TREE-SELECTED-KEY", "TREE-CONTEXT@",
        "TREE-EXPANDED?", "TREE-SCROLL-INFO", "TREE-ITEM-VIEW-MEASURE",
        "TREE-ITEM-VIEW-CAPTURE", "TREE-INSTANCE@", "TREE-GENUINE?",
        "TREE-ITEM-VIEW-STORAGE-DISJOINT?", "TREE-ON-SELECT", "TREE-ON-OPEN",
    ),
    other=(
        "TREE-NEW", "TREE-FREE", "TREE-STORAGE-DISJOINT?",
        "TREE-WALK-CONTEXT",
    ),
    minimum=24,
    scenario=r'''
\ Node 1 is the root, with children 2, 3 and 4; node 2 has 5 and 6.  A
\ node's key is the node, and its label two letters from the node-th.
: _TR-CHILDREN  ( node -- first|0 )
    DUP 1 = IF DROP 2 EXIT THEN  2 = IF 5 ELSE 0 THEN ;
: _TR-NEXT  ( node -- sibling|0 )
    DUP 2 = IF DROP 3 EXIT THEN  DUP 3 = IF DROP 4 EXIT THEN
    5 = IF 6 ELSE 0 THEN ;
: _TR-LABEL  ( node -- a u )  _WR-TEXT + 2 ;
: _TR-LEAF?  ( node -- flag )  DUP 1 = SWAP 2 = OR 0= ;
: _TR-KEY  ( parent-key node -- key )  NIP ;
: _TR-MAKE  ( -- widget )
    0 0 4 30 RGN-NEW 1 ['] _TR-CHILDREN ['] _TR-NEXT ['] _TR-LABEL
    ['] _TR-LEAF? ['] _TR-KEY TREE-NEW ;
: _TS1  _WR-W @ 1 TREE-EXPAND ;        ' _TS1 _WR-STEP
: _TS2  _WR-W @ 2 TREE-SELECT ;        ' _TS2 _WR-STEP
: _TS3  _WR-W @ 2 TREE-EXPAND ;        ' _TS3 _WR-STEP
: _TS4  _WR-W @ 2 TREE-COLLAPSE ;      ' _TS4 _WR-STEP
: _TS5  _WR-W @ 2 TREE-TOGGLE ;        ' _TS5 _WR-STEP
: _TS6  _WR-W @ 6 TREE-SELECT ;        ' _TS6 _WR-STEP
: _TS7  _WR-W @ TREE-COLLAPSE-ALL ;    ' _TS7 _WR-STEP
: _TS8  _WR-W @ 2 TREE-EXPAND-KEY ;    ' _TS8 _WR-STEP
: _TS9  _WR-W @ TREE-EXPAND-ALL ;      ' _TS9 _WR-STEP
: _TS10  2 _WR-W @ TREE-SCROLL-SET ;   ' _TS10 _WR-STEP
: _TS11  4 _WR-W @ TREE-CONTEXT! ;     ' _TS11 _WR-STEP
: _TS12  -1 _WR-W @ TREE-UNTRUSTED! ;  ' _TS12 _WR-STEP
: _TS13  _WR-W @ TREE-REFRESH ;        ' _TS13 _WR-STEP
_TR-MAKE CONSTANT _TR-A  _TR-MAKE CONSTANT _TR-B
_TR-A _TR-B _WR-RUN
_TR-A _WR-W !
: _TQ1  _WR-W @ TREE-SELECTED DROP ;   ' _TQ1 _WR-STILL
: _TQ2  _WR-W @ TREE-SELECTED-KEY DROP ;        ' _TQ2 _WR-STILL
: _TQ3  _WR-W @ TREE-CONTEXT@ DROP ;   ' _TQ3 _WR-STILL
: _TQ4  _WR-W @ 2 TREE-EXPANDED? DROP ;         ' _TQ4 _WR-STILL
: _TQ5  _WR-W @ TREE-SCROLL-INFO 2DROP DROP ;   ' _TQ5 _WR-STILL
: _TQ6  5 _WR-BLD _WR-W @ TREE-ITEM-VIEW-MEASURE 2DROP ;  ' _TQ6 _WR-STILL
: _TQ7  5 _WR-OUT 4096 _WR-BLD _WR-W @ TREE-ITEM-VIEW-CAPTURE 2DROP ;
' _TQ7 _WR-STILL
: _TQ8  _WR-W @ TREE-INSTANCE@ DROP ;  ' _TQ8 _WR-STILL
: _TQ9  _WR-W @ TREE-GENUINE? DROP ;   ' _TQ9 _WR-STILL
: _TQ10  _WR-OUT 4096 _WR-W @ TREE-ITEM-VIEW-STORAGE-DISJOINT? DROP ;
' _TQ10 _WR-STILL
: _TQ11  ['] _WR-NOP1 _WR-W @ TREE-ON-SELECT ;  ' _TQ11 _WR-STILL
: _TQ12  ['] _WR-NOP1 _WR-W @ TREE-ON-OPEN ;    ' _TQ12 _WR-STILL
''',
)


KINDS["tabs"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/tabs.f"),
    change=("TAB-ADD", "TAB-SELECT", "TAB-LABEL!", "TAB-REMOVE"),
    same=(
        "TAB-ACTIVE", "TAB-CONTENT", "TAB-COUNT", "TAB-CAPACITY", "TAB-KEY@",
        "TAB-INSTANCE@", "TAB-LABEL@", "TAB-HIT-INDEX", "TAB-GENUINE?",
        "TAB-TABSET-STORAGE-DISJOINT?", "TAB-TABSET-MEASURE",
        "TAB-TABSET-CAPTURE", "TAB-ON-SWITCH",
    ),
    other=("TAB-NEW", "TAB-NEW-CAP", "TAB-FREE", "TAB-STORAGE-DISJOINT?"),
    minimum=19,
    scenario=r'''
: _TB-MAKE  ( -- widget )  0 0 6 30 RGN-NEW TAB-NEW ;
: _TB1  S" One" _WR-W @ TAB-ADD DROP ;      ' _TB1 _WR-STEP
: _TB2  S" Two" _WR-W @ TAB-ADD DROP ;      ' _TB2 _WR-STEP
: _TB3  S" Three" _WR-W @ TAB-ADD DROP ;    ' _TB3 _WR-STEP
: _TB4  2 _WR-W @ TAB-SELECT ;              ' _TB4 _WR-STEP
: _TB5  S" Uno" 0 _WR-W @ TAB-LABEL! ;      ' _TB5 _WR-STEP
: _TB6  1 _WR-W @ TAB-REMOVE ;              ' _TB6 _WR-STEP
_TB-MAKE CONSTANT _TB-A  _TB-MAKE CONSTANT _TB-B
_TB-A _TB-B _WR-RUN
_TB-A _WR-W !
: _BQ1  _WR-W @ TAB-ACTIVE DROP ;           ' _BQ1 _WR-STILL
: _BQ2  0 _WR-W @ TAB-CONTENT DROP ;        ' _BQ2 _WR-STILL
: _BQ3  _WR-W @ TAB-COUNT DROP ;            ' _BQ3 _WR-STILL
: _BQ4  _WR-W @ TAB-CAPACITY DROP ;         ' _BQ4 _WR-STILL
: _BQ5  0 _WR-W @ TAB-KEY@ DROP ;           ' _BQ5 _WR-STILL
: _BQ6  _WR-W @ TAB-INSTANCE@ DROP ;        ' _BQ6 _WR-STILL
: _BQ7  0 _WR-W @ TAB-LABEL@ 2DROP ;        ' _BQ7 _WR-STILL
: _BQ8  0 2 _WR-W @ TAB-HIT-INDEX 2DROP ;   ' _BQ8 _WR-STILL
: _BQ9  _WR-W @ TAB-GENUINE? DROP ;         ' _BQ9 _WR-STILL
: _BQ10  _WR-OUT 4096 _WR-W @ TAB-TABSET-STORAGE-DISJOINT? DROP ;
' _BQ10 _WR-STILL
: _BQ11  5 _WR-BLD _WR-W @ TAB-TABSET-MEASURE 2DROP ;    ' _BQ11 _WR-STILL
: _BQ12  5 _WR-OUT 4096 _WR-BLD _WR-W @ TAB-TABSET-CAPTURE 2DROP ;
' _BQ12 _WR-STILL
: _BQ13  ['] _WR-NOP2 _WR-W @ TAB-ON-SWITCH ;    ' _BQ13 _WR-STILL
''',
)


def _string(name: str, text: str) -> str:
    """A Forth word NAME$ that gives TEXT's bytes."""
    data = text.encode("utf-8")
    return (
        f"CREATE {name} " + " ".join(f"{byte} C," for byte in data)
        + f"\n: {name}$  {name} {len(data)} ;\n"
    )


KINDS["text area"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/textarea.f"),
    change=(
        "TXTA-SET-TEXT", "TXTA-CURSOR!", "TXTA-SCROLL-SET",
        "TXTA-ADJUST-SCROLL", "TXTA-SCROLL-X!", "TXTA-SELECT",
        "TXTA-DEL-SEL", "TXTA-INS-STR", "TXTA-SELECT-ALL", "TXTA-GUTTER!",
        "TXTA-STYLE!", "TXTA-PALETTE!", "TXTA-VIEW!", "TXTA-CLEAR",
        "TXTA-BIND-GB", "TXTA-UNDO", "TXTA-REDO", "TXTA-UNBIND-GB",
    ),
    same=(
        "TXTA-GET-TEXT", "TXTA-LENGTH", "TXTA-BUFFER@", "TXTA-BUFFER!",
        "TXTA-ON-CHANGE", "TXTA-SCROLL-INFO", "TXTA-CURSOR-LINE",
        "TXTA-CURSOR-COL", "TXTA-CURSOR-CELL", "TXTA-CURSOR-X",
        "TXTA-GET-SEL", "TXTA-CURSOR@", "TXTA-SELECTION?", "TXTA-SCROLL-Y@",
        "TXTA-VIEW@", "TXTA-GB@", "TXTA-BIND-UNDO", "TXTA-UNBIND-UNDO",
        "TXTA-ON-FOLLOW!", "TXTA-ON-CARET!", "TXTA-CHANGED-ROWS",
        "TXTA-DRAW-ROWS",
        "TXTA-SCROLL-X@", "TXTA-INSTANCE@", "TXTA-GENUINE?",
        "TXTA-TEXT-AREA-STORAGE-DISJOINT?", "TXTA-TEXT-AREA-MEASURE",
        "TXTA-TEXT-AREA-CAPTURE",
    ),
    other=("TXTA-NEW", "TXTA-FREE", "TXTA-STORAGE-DISJOINT?"),
    minimum=47,
    scenario=_string("_TA-SIX", "one\ntwo\nthree\nfour\nfive\nsix") + r'''
262144 A-XMEM ARENA-NEW DROP CONSTANT _TA-AR
64 _TA-AR GB-NEW CONSTANT _TA-GB-A  64 _TA-AR GB-NEW CONSTANT _TA-GB-B
UNDO-NEW CONSTANT _TA-UD-A  UNDO-NEW CONSTANT _TA-UD-B
CREATE _TA-BUF-A 256 ALLOT  CREATE _TA-BUF-B 256 ALLOT
CREATE _TA-MOVED 256 ALLOT
0 0 4 30 RGN-NEW _TA-BUF-A 256 TXTA-NEW CONSTANT _TA-A
0 0 4 30 RGN-NEW _TA-BUF-B 256 TXTA-NEW CONSTANT _TA-B
: _TA-GB  ( -- gb )  _WR-W @ _TA-A = IF _TA-GB-A ELSE _TA-GB-B THEN ;
: _TA-UD  ( -- ud )  _WR-W @ _TA-A = IF _TA-UD-A ELSE _TA-UD-B THEN ;
CREATE _TA-PAL SPAL-SIZE ALLOT  _TA-PAL SPAL-INIT
: _TA-GUT  ( line# row width widget -- )  2DROP 2DROP ;
: _TA-STYLE  ( line-a line-u map -- )  DROP 2DROP ;
: _TA-FOLLOW  ( line-a line-u pos widget -- )  2DROP 2DROP ;
: _TS1  _TA-SIX$ _WR-W @ TXTA-SET-TEXT ;        ' _TS1 _WR-STEP
: _TS2  0 _WR-W @ TXTA-CURSOR! ;                ' _TS2 _WR-STEP
: _TS3  2 _WR-W @ TXTA-SCROLL-SET ;             ' _TS3 _WR-STEP
\ Off the caret again, with no draw to keep it in view.
' _TS3 _WR-PREP
: _TS4  _WR-W @ TXTA-ADJUST-SCROLL ;            ' _TS4 _WR-STEP
: _TS5  3 _WR-W @ TXTA-SCROLL-X! ;              ' _TS5 _WR-STEP
: _TS6  4 8 _WR-W @ TXTA-SELECT ;               ' _TS6 _WR-STEP
: _TS7  _WR-W @ TXTA-DEL-SEL DROP ;             ' _TS7 _WR-STEP
: _TS8  S" new " _WR-W @ TXTA-INS-STR ;         ' _TS8 _WR-STEP
: _TS9  _WR-W @ TXTA-SELECT-ALL ;               ' _TS9 _WR-STEP
: _TS10  ['] _TA-GUT 3 _WR-W @ TXTA-GUTTER! ;   ' _TS10 _WR-STEP
: _TS11  ['] _TA-STYLE _WR-W @ TXTA-STYLE! ;    ' _TS11 _WR-STEP
: _TS12  _TA-PAL _WR-W @ TXTA-PALETTE! ;        ' _TS12 _WR-STEP
: _TS13  5 1 -1 _WR-W @ TXTA-VIEW! ;            ' _TS13 _WR-STEP
: _TS14  _WR-W @ TXTA-CLEAR ;                   ' _TS14 _WR-STEP
: _TS15  _TA-GB _WR-W @ TXTA-BIND-GB ;          ' _TS15 _WR-STEP
: _TS16  _TA-UD _WR-W @ TXTA-BIND-UNDO ;        ' _TS16 _WR-PREP
: _TS17  S" xyz" _WR-W @ TXTA-INS-STR ;         ' _TS17 _WR-STEP
: _TS18  _WR-W @ TXTA-UNDO ;                    ' _TS18 _WR-STEP
: _TS19  _WR-W @ TXTA-REDO ;                    ' _TS19 _WR-STEP
: _TS20  _WR-W @ TXTA-UNBIND-GB ;               ' _TS20 _WR-STEP
_TA-A _TA-B _WR-RUN
\ The words that move nothing, over a text with a selection.
_TA-A _WR-W !  _TA-SIX$ _TA-A TXTA-SET-TEXT  4 8 _TA-A TXTA-SELECT
_TA-A WDG-DRAW
: _TQ1  _WR-W @ TXTA-GET-TEXT DROP FREE ;       ' _TQ1 _WR-STILL
: _TQ2  _WR-W @ TXTA-LENGTH DROP ;              ' _TQ2 _WR-STILL
: _TQ3  _WR-W @ TXTA-BUFFER@ 2DROP ;            ' _TQ3 _WR-STILL
\ Moved to another buffer that holds the same text, it shows the same.
: _TQ4  _WR-W @ TXTA-BUFFER@ DROP _TA-MOVED _WR-W @ TXTA-LENGTH CMOVE
    _TA-MOVED 256 _WR-W @ TXTA-BUFFER! DROP ;   ' _TQ4 _WR-STILL
: _TQ5  ['] _WR-NOP1 _WR-W @ TXTA-ON-CHANGE ;   ' _TQ5 _WR-STILL
: _TQ6  _WR-W @ TXTA-SCROLL-INFO 2DROP DROP ;   ' _TQ6 _WR-STILL
: _TQ7  _WR-W @ TXTA-CURSOR-LINE DROP ;         ' _TQ7 _WR-STILL
: _TQ8  _WR-W @ TXTA-CURSOR-COL DROP ;          ' _TQ8 _WR-STILL
: _TQ9  _WR-W @ TXTA-CURSOR-CELL DROP ;         ' _TQ9 _WR-STILL
: _TQ10  _WR-W @ TXTA-CURSOR-X DROP ;           ' _TQ10 _WR-STILL
: _TQ11  _WR-W @ TXTA-GET-SEL 2DROP ;           ' _TQ11 _WR-STILL
: _TQ12  _WR-W @ TXTA-CURSOR@ DROP ;            ' _TQ12 _WR-STILL
: _TQ13  _WR-W @ TXTA-SELECTION? DROP ;         ' _TQ13 _WR-STILL
: _TQ14  _WR-W @ TXTA-SCROLL-Y@ DROP ;          ' _TQ14 _WR-STILL
: _TQ15  _WR-W @ TXTA-VIEW@ 2DROP DROP ;        ' _TQ15 _WR-STILL
: _TQ16  _WR-W @ TXTA-GB@ DROP ;                ' _TQ16 _WR-STILL
: _TQ17  _TA-UD-A _WR-W @ TXTA-BIND-UNDO ;      ' _TQ17 _WR-STILL
: _TQ18  _WR-W @ TXTA-UNBIND-UNDO ;             ' _TQ18 _WR-STILL
: _TQ19  ['] _TA-FOLLOW _WR-W @ TXTA-ON-FOLLOW! ;   ' _TQ19 _WR-STILL
: _TQ20  _WR-W @ TXTA-CHANGED-ROWS 2DROP ;      ' _TQ20 _WR-STILL
: _TQ21  0 2 _WR-W @ TXTA-DRAW-ROWS ;           ' _TQ21 _WR-STILL
: _TQ22  _WR-W @ TXTA-SCROLL-X@ DROP ;          ' _TQ22 _WR-STILL
: _TQ23  _WR-W @ TXTA-INSTANCE@ DROP ;          ' _TQ23 _WR-STILL
: _TQ24  _WR-W @ TXTA-GENUINE? DROP ;           ' _TQ24 _WR-STILL
: _TQ25  _WR-OUT 4096 _WR-W @ TXTA-TEXT-AREA-STORAGE-DISJOINT? DROP ;
' _TQ25 _WR-STILL
: _TQ26  5 _WR-BLD _WR-W @ TXTA-TEXT-AREA-MEASURE 2DROP ;   ' _TQ26 _WR-STILL
: _TQ27  5 _WR-OUT 4096 _WR-BLD _WR-W @ TXTA-TEXT-AREA-CAPTURE 2DROP ;
' _TQ27 _WR-STILL
: _TQ28  ['] _WR-NOP1 _WR-W @ TXTA-ON-CARET! ;   ' _TQ28 _WR-STILL
''',
)


KINDS["input"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/input.f"),
    change=(
        "INP-SET-TEXT", "INP-SET-PLACEHOLDER", "INP-MASK!", "INP-CLEAR",
        "INP-WIPE",
    ),
    same=(
        "INP-GET-TEXT", "INP-ON-SUBMIT", "INP-CURSOR-POS", "INP-MASK@",
        "INP-PLACEHOLDER@", "INP-SHOWN-STATE", "INP-BUFFER@",
        "INP-DESCRIPTOR-DISJOINT?",
    ),
    other=("INP-NEW", "INP-FREE"),
    minimum=14,
    scenario=r'''
CREATE _IN-BUF-A 64 ALLOT  CREATE _IN-BUF-B 64 ALLOT
: _IN1  S" hello" _WR-W @ INP-SET-TEXT ;          ' _IN1 _WR-STEP
: _IN2  S" name" _WR-W @ INP-SET-PLACEHOLDER ;    ' _IN2 _WR-STEP
: _IN3  42 _WR-W @ INP-MASK! ;                    ' _IN3 _WR-STEP
: _IN4  _WR-W @ INP-CLEAR ;                       ' _IN4 _WR-STEP
: _IN5  S" again" _WR-W @ INP-SET-TEXT ;          ' _IN5 _WR-STEP
: _IN6  _WR-W @ INP-WIPE ;                        ' _IN6 _WR-STEP
0 0 1 30 RGN-NEW _IN-BUF-A 64 INP-NEW CONSTANT _IN-A
0 0 1 30 RGN-NEW _IN-BUF-B 64 INP-NEW CONSTANT _IN-B
_IN-A _IN-B _WR-RUN
_IN-A _WR-W !  S" shown" _IN-A INP-SET-TEXT  _IN-A WDG-DRAW
: _IQ1  _WR-W @ INP-GET-TEXT 2DROP ;              ' _IQ1 _WR-STILL
: _IQ2  ['] _WR-NOP1 _WR-W @ INP-ON-SUBMIT ;      ' _IQ2 _WR-STILL
: _IQ3  _WR-W @ INP-CURSOR-POS DROP ;             ' _IQ3 _WR-STILL
: _IQ4  _WR-W @ INP-MASK@ DROP ;                  ' _IQ4 _WR-STILL
: _IQ5  _WR-W @ INP-PLACEHOLDER@ 2DROP ;          ' _IQ5 _WR-STILL
: _IQ6  _WR-W @ INP-SHOWN-STATE 2DROP 2DROP ;     ' _IQ6 _WR-STILL
: _IQ7  _WR-W @ INP-BUFFER@ 2DROP ;               ' _IQ7 _WR-STILL
: _IQ8  _WR-OUT 4096 _WR-W @ INP-DESCRIPTOR-DISJOINT? DROP ;
' _IQ8 _WR-STILL
''',
)


KINDS["prompt"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/prompt.f"),
    change=(
        "PRM-SHOW", "PRM-COLORS!", "PRM-MASK!", "PRM-WIPE", "PRM-SET-BOUNDS",
        "PRM-HIDE",
    ),
    same=(
        "PRM-ACTIVE?", "PRM-GET-TEXT", "PRM-ON-SUBMIT", "PRM-ON-CANCEL",
        "PRM-GENUINE?", "PRM-INSTANCE@", "PRM-FIELD-ROOT",
        "PRM-FIELD-CAPTURE",
    ),
    other=("PRM-NEW", "PRM-FREE"),
    minimum=18,
    scenario=r'''
CREATE _PR-BUF-A 64 ALLOT  CREATE _PR-BUF-B 64 ALLOT
CREATE _PR-EV 24 ALLOT
\ A character typed reaches the prompt's input through the prompt.
: _PR-CHAR  ( cp -- )
    _PR-EV 8 + ! 0 _PR-EV 16 + ! KEY-T-CHAR _PR-EV !
    _PR-EV _WR-W @ WDG-HANDLE DROP ;
: _PS1  S" Name:" S" abc" _WR-W @ PRM-SHOW ;     ' _PS1 _WR-STEP
: _PS2  200 17 _WR-W @ PRM-COLORS! ;             ' _PS2 _WR-STEP
: _PS3  42 _WR-W @ PRM-MASK! ;                   ' _PS3 _WR-STEP
: _PS4  _WR-W @ PRM-WIPE ;                       ' _PS4 _WR-STEP
: _PS5  0 0 1 25 _WR-W @ PRM-SET-BOUNDS ;        ' _PS5 _WR-STEP
: _PS6  _WR-W @ PRM-HIDE ;                       ' _PS6 _WR-STEP
: _PS7  S" Again:" S" xy" _WR-W @ PRM-SHOW ;     ' _PS7 _WR-STEP
: _PS8  122 _PR-CHAR ;                           ' _PS8 _WR-STEP
0 0 1 30 RGN-NEW _PR-BUF-A 64 PRM-NEW CONSTANT _PR-A
0 0 1 30 RGN-NEW _PR-BUF-B 64 PRM-NEW CONSTANT _PR-B
_PR-A _PR-B _WR-RUN
_PR-A _WR-W !
\ Bounds it already has change nothing.
' _PS5 _WR-STILL
: _PQ1  _WR-W @ PRM-ACTIVE? DROP ;               ' _PQ1 _WR-STILL
: _PQ2  _WR-W @ PRM-GET-TEXT 2DROP ;             ' _PQ2 _WR-STILL
: _PQ3  ['] _WR-NOP1 _WR-W @ PRM-ON-SUBMIT ;     ' _PQ3 _WR-STILL
: _PQ4  ['] _WR-NOP1 _WR-W @ PRM-ON-CANCEL ;     ' _PQ4 _WR-STILL
: _PQ5  _WR-W @ PRM-GENUINE? DROP ;              ' _PQ5 _WR-STILL
: _PQ6  _WR-W @ PRM-INSTANCE@ DROP ;             ' _PQ6 _WR-STILL
: _PQ7  _WR-W @ PRM-FIELD-ROOT 2DROP 2DROP ;     ' _PQ7 _WR-STILL
: _PQ8  _WR-OUT 4096 _WR-W @ PRM-FIELD-CAPTURE 2DROP ;   ' _PQ8 _WR-STILL
''',
)


KINDS["dialog"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/dialog.f"),
    change=("DLG-HOST-PAINT", "DLG-HOST-EVENT"),
    same=(
        "DLG-SELECTED", "DLG-BTN-COUNT", "DLG-RESULT", "DLG-PARAGRAPH",
        "DLG-INSTANCE@", "DLG-ROOT", "DLG-MODEL-CAPTURE",
    ),
    other=(
        "DLG-FREE", "DLG-ASK", "DLG-ASK-DETAIL", "DLG-CONFIRM", "DLG-INFO",
        "DLG-SHOWN", "DLG-DISCARD", "DLG-WITHDRAW",
    ),
    minimum=13,
    scenario=_string(
        "_DL-MSG",
        "This message is long enough that the dialog cannot show all of it "
        "at once, so that its rows can scroll.  " * 6,
    ) + r'''
\ Each dialog has its own host cell, chosen for the widget in _WR-W, and
\ the host's bounds are the screen's width and _DL-H rows.
VARIABLE _DL-CELL-A  0 _DL-CELL-A !  VARIABLE _DL-CELL-B  0 _DL-CELL-B !
VARIABLE _DL-WHICH
: _DL-CELL  ( -- a )  _DL-WHICH @ ;
' _DL-CELL IS DLG-CELL-HOOK
VARIABLE _DL-H
: _DL-BOUNDS  ( -- row col h w )  0 0 _DL-H @ 40 ;
' _DL-BOUNDS IS DLG-BOUNDS-HOOK
: _DL-YES  S" Yes" ;  : _DL-NO  S" No" ;  : _DL-TITLE  S" Question" ;
CREATE _DL-BTNS 64 ALLOT  _DL-BTNS 64 0 FILL
_DL-YES _DL-BTNS 8 + ! _DL-BTNS !  DLG-B-DEFAULT _DL-BTNS 16 + !
_DL-NO _DL-BTNS 40 + ! _DL-BTNS 32 + !  DLG-B-CANCEL _DL-BTNS 48 + !
: _DL-ASK  ( -- widget )
    16 _DL-H !
    _DL-TITLE _DL-MSG$ _DL-BTNS 2 0 0 DLG-ASK 0= ABORT" no dialog"
    DLG-SHOWN ;
_DL-CELL-A _DL-WHICH !  _DL-ASK CONSTANT _DL-A
_DL-CELL-B _DL-WHICH !  _DL-ASK CONSTANT _DL-B
: _DL-USE  ( -- )
    _WR-W @ _DL-A = IF _DL-CELL-A ELSE _DL-CELL-B THEN _DL-WHICH ! ;
CREATE _DL-EV 24 ALLOT
: _DL-KEY  ( code -- )
    _DL-EV 8 + ! 0 _DL-EV 16 + ! KEY-T-SPECIAL _DL-EV !
    _DL-EV DLG-HOST-EVENT DROP ;
: _DS0  16 _DL-H ! ;                       ' _DS0 _WR-PREP
: _DS1  _DL-USE DLG-HOST-PAINT ;           ' _DS1 _WR-STEP
: _DS2  _DL-USE KEY-RIGHT _DL-KEY ;        ' _DS2 _WR-STEP
: _DS3  _DL-USE KEY-DOWN _DL-KEY ;         ' _DS3 _WR-STEP
: _DS4  10 _DL-H ! ;                       ' _DS4 _WR-PREP
' _DS1 _WR-STEP
_DL-A _DL-B _WR-RUN
_DL-A _WR-W !  _DL-USE
\ Painting again lays nothing out anew.
' _DS1 _WR-STILL
: _DQ1  _WR-W @ DLG-SELECTED DROP ;        ' _DQ1 _WR-STILL
: _DQ2  _WR-W @ DLG-BTN-COUNT DROP ;       ' _DQ2 _WR-STILL
: _DQ3  _WR-W @ DLG-RESULT DROP ;          ' _DQ3 _WR-STILL
: _DQ4  _WR-W @ 0 DLG-PARAGRAPH 2DROP ;    ' _DQ4 _WR-STILL
: _DQ5  _WR-W @ DLG-INSTANCE@ DROP ;       ' _DQ5 _WR-STILL
: _DQ6  _WR-W @ DLG-ROOT 2DROP 2DROP ;     ' _DQ6 _WR-STILL
: _DQ7  _WR-OUT 4096 _WR-W @ DLG-MODEL-CAPTURE 2DROP ;   ' _DQ7 _WR-STILL
''',
)


def _bytes(name: str, data: bytes) -> str:
    """A Forth word NAME$ that gives DATA."""
    return (
        f"CREATE {name} " + " ".join(f"{byte} C," for byte in data)
        + f"\n: {name}$  {name} {len(data)} ;\n"
    )


_PICTURE = qoi_codec.encode(
    [[((x * 40) & 0xFF, (y * 60) & 0xFF, 128, 255) for x in range(6)]
     for y in range(4)]
)


KINDS["picture"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/picture.f"),
    change=(
        "PICT-SOURCE!", "PICT-SERVICE", "PICT-ALT!", "PICT-CLAIM!",
        "PICT-RICH-FAILED!",
    ),
    same=(
        "PICT-CLAIMED?", "PICT-RICH-FAILED@", "PICT-PENDING?",
        "PICT-RICH-ASK", "PICT-RICH@", "PICT-REVISION@", "PICT-FILE@",
        "PICT-FILE-BYTES@", "PICT-FILE-READ", "PICT-CELL-COPY@",
    ),
    other=(
        "PICT-NEW", "PICT-FREE", "PICT-RICH-FORMATS!", "PICT-WORK?",
        "PICT-RELEASE-ALL",
    ),
    minimum=16,
    scenario=_bytes("_PC-FILE", _PICTURE) + r'''
CREATE _PC-SRC-A-M MEDSRC-SIZE 7 + ALLOT  : _PC-SRC-A  _PC-SRC-A-M 7 + -8 AND ;
CREATE _PC-SRC-B-M MEDSRC-SIZE 7 + ALLOT  : _PC-SRC-B  _PC-SRC-B-M 7 + -8 AND ;
CREATE _PC-MS-M MSRC-SIZE 7 + ALLOT  : _PC-MS  _PC-MS-M 7 + -8 AND ;
: _PC-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: _PC-FREE  ( addr bytes ctx -- )  2DROP FREE ;
' _PC-ALLOC ' _PC-FREE 0 0 _PC-MS MSRC-INIT
_PC-FILE$ _PC-SRC-A MEDSRC-MEMORY  _PC-FILE$ _PC-SRC-B MEDSRC-MEMORY
0 0 4 10 RGN-NEW _PC-MS PICT-NEW CONSTANT _PC-A
0 0 4 10 RGN-NEW _PC-MS PICT-NEW CONSTANT _PC-B
: _PC-SRC  ( -- source )  _WR-W @ _PC-A = IF _PC-SRC-A ELSE _PC-SRC-B THEN ;
: _PS1  _PC-SRC S" sunset" _WR-W @ PICT-SOURCE! ;          ' _PS1 _WR-STEP
\ A draw asks for the copy CELL shows, which a service pass then decodes.
: _PS-DRAW  _WR-W @ WDG-DRAW ;                             ' _PS-DRAW _WR-PREP
: _PS2  PICT-STEP-PIXELS _WR-W @ PICT-SERVICE DROP ;       ' _PS2 _WR-STEP
: _PS3  S" dusk" _WR-W @ PICT-ALT! ;                       ' _PS3 _WR-STEP
: _PS4  -1 _WR-W @ PICT-CLAIM! ;                           ' _PS4 _WR-STEP
: _PS5  PIC-R-DAMAGED _WR-W @ PICT-RICH-FAILED! ;          ' _PS5 _WR-STEP
_PC-A _PC-B _WR-RUN
_PC-A _WR-W !
CREATE _PC-READ 8 ALLOT
: _PQ1  _WR-W @ PICT-CLAIMED? DROP ;               ' _PQ1 _WR-STILL
: _PQ2  _WR-W @ PICT-RICH-FAILED@ DROP ;           ' _PQ2 _WR-STILL
: _PQ3  _WR-W @ PICT-PENDING? DROP ;               ' _PQ3 _WR-STILL
\ Asking for a rich copy starts one; the widget shows nothing new until a
\ service pass has decoded it.
: _PQ4  6 4 _WR-W @ PICT-RICH-ASK DROP ;           ' _PQ4 _WR-STILL
: _PQ5  _WR-W @ PICT-RICH@ DROP ;                  ' _PQ5 _WR-STILL
: _PQ6  _WR-W @ PICT-REVISION@ DROP ;              ' _PQ6 _WR-STILL
: _PQ7  _WR-W @ PICT-FILE@ 2DROP DROP ;            ' _PQ7 _WR-STILL
: _PQ8  _WR-W @ PICT-FILE-BYTES@ DROP ;            ' _PQ8 _WR-STILL
: _PQ9  _PC-READ 8 0 _WR-W @ PICT-FILE-READ DROP ;     ' _PQ9 _WR-STILL
: _PQ10  _WR-W @ PICT-CELL-COPY@ DROP ;            ' _PQ10 _WR-STILL
''',
)


KINDS["text grid"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/text-grid.f"),
    change=(
        "TGRID-BIND", "TGRID-SELECT!", "TGRID-CELL-INSET!",
        "TGRID-FILL-SELECTION!",
    ),
    same=(
        "TGRID-SELECTED@", "TGRID-ON-SELECT", "TGRID-ON-SCROLL",
        "TGRID-INSTANCE@", "TGRID-GENUINE?",
        "TGRID-TEXT-GRID-STORAGE-DISJOINT?", "TGRID-TEXT-GRID-MEASURE",
        "TGRID-TEXT-GRID-CAPTURE",
    ),
    other=("TGRID-NEW", "TGRID-FREE", "TGRID-STORAGE-DISJOINT?"),
    minimum=13,
    scenario=r'''
\ A title over two rows of two items, as test_text_grid builds it, for each
\ widget its own copy, work space and summary.
CREATE _TG-MODEL-S 1024 7 + ALLOT  : _TG-MODEL  _TG-MODEL-S 7 + -8 AND ;
VARIABLE _TG-U
: _TG-BUILD  ( -- )
    _TG-MODEL 1024 _WR-BLD USCOL-BUILDER-INIT DROP
    USCOL-F-TEXT-GRID 1 0 0 10 25 3 _WR-BLD USCOL-TEXT-BEGIN DROP
    USCOL-CONTENT-READ-ONLY 3 2 0 0 3 2 _WR-BLD USCOL-TEXT-SHAPE DROP
    11 0 0 0 _WR-BLD USCOL-TEXT-POSITIONS DROP
    1 0 0 1 2 USCOL-ROLE-ROW-HEADER 0 S" Title" _WR-BLD USCOL-TEXT-ITEM DROP
    10 1 0 1 1 USCOL-ROLE-CONTENT USCOL-ITEM-CURRENT S" A" _WR-BLD USCOL-TEXT-ITEM DROP
    11 1 1 1 1 USCOL-ROLE-CONTENT 0 S" B" _WR-BLD USCOL-TEXT-ITEM DROP
    12 2 0 1 1 USCOL-ROLE-CONTENT USCOL-ITEM-UNAVAILABLE S" C" _WR-BLD USCOL-TEXT-ITEM DROP
    13 2 1 1 1 USCOL-ROLE-CONTENT 0 S" D" _WR-BLD USCOL-TEXT-ITEM DROP
    _WR-BLD USCOL-TEXT-END DROP
    _WR-BLD USCOL-BUILDER-FINISH DROP _TG-U ! ;
_TG-BUILD
CREATE _TG-COPY-S 1024 7 + ALLOT  : _TG-COPY  _TG-COPY-S 7 + -8 AND ;
_TG-MODEL _TG-COPY _TG-U @ CMOVE
CREATE _TG-WORK-A-S 64 7 + ALLOT  : _TG-WORK-A  _TG-WORK-A-S 7 + -8 AND ;
CREATE _TG-WORK-B-S 64 7 + ALLOT  : _TG-WORK-B  _TG-WORK-B-S 7 + -8 AND ;
CREATE _TG-SUM-A-S USCOL-SUMMARY-SIZE 7 + ALLOT  : _TG-SUM-A  _TG-SUM-A-S 7 + -8 AND ;
CREATE _TG-SUM-B-S USCOL-SUMMARY-SIZE 7 + ALLOT  : _TG-SUM-B  _TG-SUM-B-S 7 + -8 AND ;
0 0 10 25 RGN-NEW TGRID-NEW CONSTANT _TG-A
0 0 10 25 RGN-NEW TGRID-NEW CONSTANT _TG-B
: _TG-OWN  ( -- entry bytes work-a work-u summary )
    _WR-W @ _TG-A = IF
        _TG-MODEL _TG-U @ _TG-WORK-A 64 _TG-SUM-A
    ELSE
        _TG-COPY _TG-U @ _TG-WORK-B 64 _TG-SUM-B
    THEN ;
: _GS1  _TG-OWN _WR-W @ TGRID-BIND DROP ;          ' _GS1 _WR-STEP
: _GS2  13 _WR-W @ TGRID-SELECT! DROP ;            ' _GS2 _WR-STEP
: _GS3  2 _WR-W @ TGRID-CELL-INSET! ;              ' _GS3 _WR-STEP
: _GS4  -1 _WR-W @ TGRID-FILL-SELECTION! ;         ' _GS4 _WR-STEP
_TG-A _TG-B _WR-RUN
_TG-A _WR-W !
: _GQ1  _WR-W @ TGRID-SELECTED@ DROP ;             ' _GQ1 _WR-STILL
: _GQ2  ['] _WR-NOP2 _WR-W @ TGRID-ON-SELECT ;     ' _GQ2 _WR-STILL
: _GQ3  ['] _WR-NOP2 _WR-W @ TGRID-ON-SCROLL ;     ' _GQ3 _WR-STILL
: _GQ4  _WR-W @ TGRID-INSTANCE@ DROP ;             ' _GQ4 _WR-STILL
: _GQ5  _WR-W @ TGRID-GENUINE? DROP ;              ' _GQ5 _WR-STILL
: _GQ6  _WR-OUT 4096 _WR-W @ TGRID-TEXT-GRID-STORAGE-DISJOINT? DROP ;
' _GQ6 _WR-STILL
: _GQ7  5 _WR-BLD _WR-W @ TGRID-TEXT-GRID-MEASURE 2DROP ;    ' _GQ7 _WR-STILL
: _GQ8  5 _WR-OUT 4096 _WR-BLD _WR-W @ TGRID-TEXT-GRID-CAPTURE 2DROP ;
' _GQ8 _WR-STILL
''',
)


KINDS["field"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/field.f"),
    change=("FLD-BIND", "FLD-STYLE!", "FLD-SELECTED-STYLE!", "FLD-UNBIND"),
    same=(
        "FLD-INSTANCE@", "FLD-MODEL@", "FLD-ON-ACTIVATE", "FLD-ON-ADJUST",
        "FLD-ACTIVATE", "FLD-ADJUST", "FLD-VALUE-CONTAINS?",
        "FLD-FIELD-MEASURE", "FLD-FIELD-CAPTURE", "FLD-GENUINE?",
        "FLD-FIELD-STORAGE-DISJOINT?",
    ),
    other=("FLD-NEW", "FLD-FREE", "FLD-STORAGE-DISJOINT?"),
    minimum=16,
    scenario=r'''
\ Both widgets show the field model _FM-M holds, an integer and then a
\ choice, which _FM-INT and _FM-CHOICES build there.
: _FD-BIND  _FM-M _FM-U @ _WR-W @ FLD-BIND DROP ;
: _FD0  _FM-INT ;                                   ' _FD0 _WR-PREP
' _FD-BIND _WR-STEP
: _FD2  253 234 0 _WR-W @ FLD-STYLE! ;              ' _FD2 _WR-STEP
: _FD3  15 24 CELL-A-BOLD _WR-W @ FLD-SELECTED-STYLE! ;   ' _FD3 _WR-STEP
: _FD4  _FM-CHOICES ;                               ' _FD4 _WR-PREP
' _FD-BIND _WR-STEP
: _FD6  _WR-W @ FLD-UNBIND ;                        ' _FD6 _WR-STEP
\ Its region is the 20 cells by 2 rows that the field models take.
0 0 2 20 RGN-NEW FLD-NEW CONSTANT _FD-A
0 0 2 20 RGN-NEW FLD-NEW CONSTANT _FD-B
_FD-A _FD-B _WR-RUN
_FD-A _WR-W !  _FD-BIND  _FD-A WDG-DRAW
: _FQ1  _WR-W @ FLD-INSTANCE@ DROP ;               ' _FQ1 _WR-STILL
: _FQ2  _WR-W @ FLD-MODEL@ 2DROP ;                 ' _FQ2 _WR-STILL
: _FQ3  ['] _WR-NOP1 _WR-W @ FLD-ON-ACTIVATE ;     ' _FQ3 _WR-STILL
: _FQ4  ['] _WR-NOP2 _WR-W @ FLD-ON-ADJUST ;       ' _FQ4 _WR-STILL
\ Activating and adjusting call the application, which changes its model
\ and binds it again; the widget itself shows nothing new.
: _FQ5  _WR-W @ FLD-ACTIVATE DROP ;                ' _FQ5 _WR-STILL
: _FQ6  1 _WR-W @ FLD-ADJUST DROP ;                ' _FQ6 _WR-STILL
: _FQ7  0 5 _WR-W @ FLD-VALUE-CONTAINS? DROP ;     ' _FQ7 _WR-STILL
: _FQ8  _WR-W @ FLD-FIELD-MEASURE 2DROP ;          ' _FQ8 _WR-STILL
: _FQ9  _WR-OUT 4096 _WR-W @ FLD-FIELD-CAPTURE 2DROP ;     ' _FQ9 _WR-STILL
: _FQ10  _WR-W @ FLD-GENUINE? DROP ;               ' _FQ10 _WR-STILL
: _FQ11  _WR-OUT 4096 _WR-W @ FLD-FIELD-STORAGE-DISJOINT? DROP ;
' _FQ11 _WR-STILL
''',
)


KINDS["canvas"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/canvas.f"),
    change=(
        "CVS-SET", "CVS-CLR", "CVS-COLOR!", "CVS-LINE", "CVS-RECT",
        "CVS-FILL-RECT", "CVS-CIRCLE", "CVS-PLOT", "CVS-CLEAR",
    ),
    same=("CVS-GET", "CVS-PEN!", "CVS-TEXT"),
    other=("CVS-NEW", "CVS-FREE"),
    minimum=14,
    scenario=r'''
CREATE _CV-DATA 3 CELLS ALLOT  1 _CV-DATA !  4 _CV-DATA CELL+ !  2 _CV-DATA 2 CELLS + !
: _CS1  _WR-W @ 1 1 CVS-SET ;                 ' _CS1 _WR-STEP
: _CS2  _WR-W @ 1 1 CVS-CLR ;                 ' _CS2 _WR-STEP
: _CS3  _WR-W @ 0 0 2 0 CVS-COLOR! ;          ' _CS3 _WR-STEP
: _CS4  _WR-W @ 0 0 5 5 CVS-LINE ;            ' _CS4 _WR-STEP
: _CS5  _WR-W @ 0 0 6 6 CVS-RECT ;            ' _CS5 _WR-STEP
: _CS6  _WR-W @ 1 1 3 3 CVS-FILL-RECT ;       ' _CS6 _WR-STEP
: _CS7  _WR-W @ 8 8 3 CVS-CIRCLE ;            ' _CS7 _WR-STEP
: _CS9  _WR-W @ _CV-DATA 3 2 1 CVS-PLOT ;     ' _CS9 _WR-STEP
: _CS10  _WR-W @ CVS-CLEAR ;                  ' _CS10 _WR-STEP
\ The same dots again after the clear, so the comparison has some.
' _CS4 _WR-STEP  ' _CS7 _WR-STEP
0 0 4 10 RGN-NEW CVS-NEW CONSTANT _CV-A
0 0 4 10 RGN-NEW CVS-NEW CONSTANT _CV-B
_CV-A _CV-B _WR-RUN
_CV-A _WR-W !
: _CQ1  _WR-W @ 1 1 CVS-GET DROP ;            ' _CQ1 _WR-STILL
: _CQ2  _WR-W @ 3 0 CVS-PEN! ;                ' _CQ2 _WR-STILL
\ Text is drawn over the canvas, in the cell that holds the dot: the dot
\ 8 4 is in the fifth column of the second row.
: _CQ3  _WR-W @ 8 4 S" hi" CVS-TEXT ;         ' _CQ3 _WR-STILL
1 4 SCR-GET CELL-CP@ 104 = _FM-A
''',
)


KINDS["data graphics"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/data-graphics.f"),
    change=("DGRAPH-BIND",),
    same=(
        "DGRAPH-INSTANCE@", "DGRAPH-GENUINE?",
        "DGRAPH-DATA-GRAPHICS-STORAGE-DISJOINT?",
        "DGRAPH-DATA-GRAPHICS-MEASURE", "DGRAPH-DATA-GRAPHICS-CAPTURE",
    ),
    other=("DGRAPH-NEW", "DGRAPH-FREE", "DGRAPH-STORAGE-DISJOINT?"),
    minimum=8,
    scenario=r'''
\ Two graphs of one integer readout, 42 and then 43, each widget with its
\ own summary.
CREATE _DG-G1-S 4096 7 + ALLOT  : _DG-G1  _DG-G1-S 7 + -8 AND ;
CREATE _DG-G2-S 4096 7 + ALLOT  : _DG-G2  _DG-G2-S 7 + -8 AND ;
CREATE _DG-B-S UDG-BUILDER-SIZE 7 + ALLOT  : _DG-B  _DG-B-S 7 + -8 AND ;
CREATE _DG-SUM-A-S UDG-SUMMARY-SIZE 7 + ALLOT  : _DG-SUM-A  _DG-SUM-A-S 7 + -8 AND ;
CREATE _DG-SUM-B-S UDG-SUMMARY-SIZE 7 + ALLOT  : _DG-SUM-B  _DG-SUM-B-S 7 + -8 AND ;
VARIABLE _DG-U1  VARIABLE _DG-U2
: _DG-BUILD  ( graph value -- bytes )
    >R 4096 _DG-B UDG-BUILDER-INIT DROP
    100 0 0 12 30 UDG-STATE-VISIBLE UDG-STATE-ENABLED OR _DG-B UDG-BEGIN DROP
    101 0 0 1 4 0 UDG-OBJECT-VISIBLE 0xFFFFFFFF 0x00000000
        UDG-READOUT-INTEGER 0 R> 1 0 0 _DG-B UDG-READOUT DROP
    _DG-B UDG-END DROP  _DG-B UDG-BUILDER-FINISH DROP ;
_DG-G1 42 _DG-BUILD _DG-U1 !  _DG-G2 43 _DG-BUILD _DG-U2 !
0 0 12 30 RGN-NEW DGRAPH-NEW CONSTANT _DG-A
0 0 12 30 RGN-NEW DGRAPH-NEW CONSTANT _DG-B-W
: _DG-SUM  ( -- summary )  _WR-W @ _DG-A = IF _DG-SUM-A ELSE _DG-SUM-B THEN ;
: _DS1  _DG-G1 _DG-U1 @ _DG-SUM _WR-W @ DGRAPH-BIND DROP ;    ' _DS1 _WR-STEP
: _DS2  _DG-G2 _DG-U2 @ _DG-SUM _WR-W @ DGRAPH-BIND DROP ;    ' _DS2 _WR-STEP
_DG-A _DG-B-W _WR-RUN
_DG-A _WR-W !
: _DQ1  _WR-W @ DGRAPH-INSTANCE@ DROP ;       ' _DQ1 _WR-STILL
: _DQ2  _WR-W @ DGRAPH-GENUINE? DROP ;        ' _DQ2 _WR-STILL
: _DQ3  _WR-OUT 4096 _WR-W @ DGRAPH-DATA-GRAPHICS-STORAGE-DISJOINT? DROP ;
' _DQ3 _WR-STILL
: _DQ4  _DG-B _WR-W @ DGRAPH-DATA-GRAPHICS-MEASURE 2DROP ;    ' _DQ4 _WR-STILL
: _DQ5  _WR-OUT 4096 _DG-B _WR-W @ DGRAPH-DATA-GRAPHICS-CAPTURE 2DROP ;
' _DQ5 _WR-STILL
''',
)


KINDS["explorer"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/explorer.f"),
    change=(
        "EXPL-EXPAND-ALL", "EXPL-COLLAPSE-ALL", "EXPL-SHOW-HIDDEN!",
        "EXPL-REFRESH", "EXPL-NEW-FILE", "EXPL-NEW-DIR", "EXPL-ROOT!",
        "EXPL-RENAME",
    ),
    same=(
        "EXPL-SELECTED", "EXPL-ON-OPEN", "EXPL-ON-SELECT",
        "EXPL-SHOW-HIDDEN?", "EXPL-VFS", "EXPL-TREE", "EXPL-DELETE",
    ),
    other=("EXPL-NEW", "EXPL-FREE", "EXPL-ENTRY-KEY"),
    minimum=20,
    scenario=r'''
\ Keys reach the explorer's tree, and its rename input while it renames,
\ through the explorer.
CREATE _EX-EV 24 ALLOT
: _EX-EVENT  ( code type -- )
    _EX-EV ! _EX-EV 8 + ! 0 _EX-EV 16 + !  _EX-EV _WR-W @ WDG-HANDLE DROP ;
: _EX-KEY  ( code -- )  KEY-T-SPECIAL _EX-EVENT ;
: _EX-CHAR  ( cp -- )  KEY-T-CHAR _EX-EVENT ;
\ Each explorer has its own file system, made the same: a directory with
\ a file in it, a file and a hidden file.
: _EX-VFS  ( -- vfs )
    524288 A-XMEM ARENA-NEW IF -1 THROW THEN
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
    DUP VFS-USE
    S" docs" VFS-CUR VFS-MKDIR DROP
    S" hello.f" VFS-CUR VFS-MKFILE DROP
    S" .hidden" VFS-CUR VFS-MKFILE DROP
    S" docs" VFS-CUR VFS-CD DROP  S" readme" VFS-CUR VFS-MKFILE DROP
    S" .." VFS-CUR VFS-CD DROP ;
: _EX-MAKE  ( -- widget )  0 0 10 30 RGN-NEW _EX-VFS DUP V.ROOT @ EXPL-NEW ;
: _ES1  _WR-W @ EXPL-EXPAND-ALL ;             ' _ES1 _WR-STEP
: _ES2  _WR-W @ EXPL-COLLAPSE-ALL ;           ' _ES2 _WR-STEP
: _ES3  -1 _WR-W @ EXPL-SHOW-HIDDEN! ;        ' _ES3 _WR-STEP
: _ES4  _WR-W @ EXPL-REFRESH ;                ' _ES4 _WR-STEP
: _ES5  _WR-W @ EXPL-NEW-FILE ;               ' _ES5 _WR-STEP
: _ES6  _WR-W @ EXPL-NEW-DIR ;                ' _ES6 _WR-STEP
' _ES1 _WR-STEP
: _ES8  _WR-W @ EXPL-VFS V.ROOT @ _WR-W @ EXPL-ROOT! ;    ' _ES8 _WR-STEP
: _ES10  KEY-RIGHT _EX-KEY ;                  ' _ES10 _WR-STEP
: _ES11  KEY-DOWN _EX-KEY ;                   ' _ES11 _WR-STEP
: _ES9  _WR-W @ EXPL-RENAME ;                 ' _ES9 _WR-STEP
: _ES12  120 _EX-CHAR ;                       ' _ES12 _WR-STEP
: _ES13  KEY-ESC _EX-KEY ;                    ' _ES13 _WR-STEP
_EX-MAKE CONSTANT _EX-A  _EX-MAKE CONSTANT _EX-B
_EX-A _EX-B _WR-RUN
_EX-A _WR-W !
: _EQ1  _WR-W @ EXPL-SELECTED DROP ;          ' _EQ1 _WR-STILL
: _EQ2  ['] _WR-NOP2 _WR-W @ EXPL-ON-OPEN ;   ' _EQ2 _WR-STILL
: _EQ3  ['] _WR-NOP2 _WR-W @ EXPL-ON-SELECT ;     ' _EQ3 _WR-STILL
: _EQ4  _WR-W @ EXPL-SHOW-HIDDEN? DROP ;      ' _EQ4 _WR-STILL
: _EQ5  _WR-W @ EXPL-VFS DROP ;               ' _EQ5 _WR-STILL
: _EQ6  _WR-W @ EXPL-TREE DROP ;              ' _EQ6 _WR-STILL
\ Deleting asks first, in a dialog of its own; the explorer is as it was.
: _EQ7  _WR-W @ EXPL-DELETE ;                 ' _EQ7 _WR-STILL
''',
)


_MARKDOWN = (
    "# One\n\nThe first paragraph, with a few words in it.\n\n"
    "## Two\n\nThe second paragraph, long enough that it takes more than "
    "one row of the view to show it all.\n\n"
    "## Three\n\nThe third paragraph.\n\nThe last words.\n"
)

# A memory source that allocates from the heap.
MEMORY_SOURCE = r'''
CREATE _FS-MS-M MSRC-SIZE 7 + ALLOT  : _FS-MS  _FS-MS-M 7 + -8 AND ;
: _FS-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: _FS-FREE  ( addr bytes ctx -- )  2DROP FREE ;
' _FS-ALLOC ' _FS-FREE 0 0 _FS-MS MSRC-INIT
'''

# A file system per widget, which _FS-PUT writes files into.
FILES = MEMORY_SOURCE + r'''
VARIABLE _FS-V
: _FS-NEW  ( -- vfs )
    524288 A-XMEM ARENA-NEW IF -1 THROW THEN
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;
: _FS-PUT  ( src u path-a path-u -- )
    2DUP _FS-V @ VFS-CREATE 0= IF -101 THROW THEN
    VFS-FF-WRITE _FS-V @ VFS-OPEN? ?DUP IF THROW THEN
    DUP >R VFS-WRITE-EXACT IF -102 THROW THEN  R> VFS-CLOSE ;
'''


KINDS["media"] = Kind(
    modules=("tui/semantic-collections.f", "tui/widgets/media.f"),
    change=(
        "MEDIA-OPEN-VFS", "MEDIA-ALT!", "MEDIA-CLEAR", "MEDIA-SERVICE",
    ),
    same=(
        "MEDIA-PATH@", "MEDIA-NAME@", "MEDIA-KIND@", "MEDIA-SIZE@",
        "MEDIA-VIEW@", "MEDIA-NOTE@", "MEDIA-PICTURE@", "MEDIA-TEXT@",
        "MEDIA-DOCUMENT@", "MEDIA-CONTENTS@", "MEDIA-VIEW-WIDGET@",
        "MEDIA-CONTENTS-STORAGE-DISJOINT?", "MEDIA-GENUINE?",
        "MEDIA-DESCRIPTOR-DISJOINT?", "MEDIA-PENDING?", "MEDIA-READER!",
        "MEDIA-FOLLOW!",
    ),
    other=("MEDIA-NEW", "MEDIA-FREE"),
    minimum=28,
    scenario=FILES + _bytes("_MD-TEXT", b"first\nsecond\nthird\nfourth\n")
    + _bytes("_MD-PICTURE", _PICTURE) + _string("_MD-DOC", _MARKDOWN) + r'''
\ Each widget has its own file system holding a text file, a picture and a
\ Markdown document, and what it shows is its view's.  Keys reach the view
\ through the widget.
VARIABLE _MD-V-A  VARIABLE _MD-V-B
: _MD-FILES  ( vfs -- )
    _FS-V !
    _MD-TEXT$ S" /a.txt" _FS-PUT  _MD-PICTURE$ S" /p.qoi" _FS-PUT
    _MD-DOC$ S" /d.md" _FS-PUT ;
_FS-NEW DUP _MD-V-A ! _MD-FILES  _FS-NEW DUP _MD-V-B ! _MD-FILES
0 0 6 36 RGN-NEW _FS-MS MEDIA-NEW CONSTANT _MD-A
0 0 6 36 RGN-NEW _FS-MS MEDIA-NEW CONSTANT _MD-B
: _MD-VFS  ( -- vfs )  _WR-W @ _MD-A = IF _MD-V-A ELSE _MD-V-B THEN @ ;
: _MD-OPEN  ( path-a path-u -- )  _MD-VFS _WR-W @ MEDIA-OPEN-VFS DROP ;
CREATE _MD-EV 24 ALLOT
: _MD-EVENT  ( code type -- )
    _MD-EV ! _MD-EV 8 + ! 0 _MD-EV 16 + !  _MD-EV _WR-W @ WDG-HANDLE DROP ;
: _MS1  S" /a.txt" _MD-OPEN ;                    ' _MS1 _WR-STEP
: _MS2  KEY-UP KEY-T-SPECIAL _MD-EVENT ;         ' _MS2 _WR-STEP
: _MS3  S" dusk" _WR-W @ MEDIA-ALT! ;            ' _MS3 _WR-STEP
: _MS4  _WR-W @ MEDIA-CLEAR ;                    ' _MS4 _WR-STEP
: _MS5  S" /p.qoi" _MD-OPEN ;                    ' _MS5 _WR-STEP
\ A draw asks for the picture's copy, which a service pass decodes.
: _MS-DRAW  _WR-W @ WDG-DRAW ;                   ' _MS-DRAW _WR-PREP
: _MS6  _WR-W @ MEDIA-SERVICE DROP ;             ' _MS6 _WR-STEP
: _MS7  S" /d.md" _MD-OPEN ;                     ' _MS7 _WR-STEP
: _MS8  99 KEY-T-CHAR _MD-EVENT ;                ' _MS8 _WR-STEP
: _MS9  KEY-ESC KEY-T-SPECIAL _MD-EVENT ;        ' _MS9 _WR-STEP
: _MS10  KEY-DOWN KEY-T-SPECIAL _MD-EVENT ;     ' _MS10 _WR-STEP
_MD-A _MD-B _WR-RUN
_MD-A _WR-W !
: _MQ1  _WR-W @ MEDIA-PATH@ 2DROP ;              ' _MQ1 _WR-STILL
: _MQ2  _WR-W @ MEDIA-NAME@ 2DROP ;              ' _MQ2 _WR-STILL
: _MQ3  _WR-W @ MEDIA-KIND@ DROP ;               ' _MQ3 _WR-STILL
: _MQ4  _WR-W @ MEDIA-SIZE@ DROP ;               ' _MQ4 _WR-STILL
: _MQ5  _WR-W @ MEDIA-VIEW@ DROP ;               ' _MQ5 _WR-STILL
: _MQ6  _WR-W @ MEDIA-NOTE@ DROP ;               ' _MQ6 _WR-STILL
: _MQ7  _WR-W @ MEDIA-PICTURE@ DROP ;            ' _MQ7 _WR-STILL
: _MQ8  _WR-W @ MEDIA-TEXT@ DROP ;               ' _MQ8 _WR-STILL
: _MQ9  _WR-W @ MEDIA-DOCUMENT@ DROP ;           ' _MQ9 _WR-STILL
: _MQ10  _WR-W @ MEDIA-CONTENTS@ DROP ;          ' _MQ10 _WR-STILL
: _MQ11  _WR-W @ MEDIA-VIEW-WIDGET@ DROP ;       ' _MQ11 _WR-STILL
: _MQ12  _WR-OUT 4096 _WR-W @ MEDIA-CONTENTS-STORAGE-DISJOINT? DROP ;
' _MQ12 _WR-STILL
: _MQ13  _WR-W @ MEDIA-GENUINE? DROP ;           ' _MQ13 _WR-STILL
: _MQ14  _WR-OUT 4096 _WR-W @ MEDIA-DESCRIPTOR-DISJOINT? DROP ;
' _MQ14 _WR-STILL
: _MQ15  _WR-W @ MEDIA-PENDING? DROP ;           ' _MQ15 _WR-STILL
\ The reader it has already for Markdown, and no link follower.
: _MQ16  MD-READER MEDIA-K-MARKDOWN _WR-W @ MEDIA-READER! ;   ' _MQ16 _WR-STILL
: _MQ17  0 0 _WR-W @ MEDIA-FOLLOW! ;             ' _MQ17 _WR-STILL
''',
)


def _pages_pdf() -> bytes:
    from test_pdf_document import pages_pdf
    return pages_pdf()


_FIGURED = _MARKDOWN.replace(
    "## Two\n", "![A sunset](p.qoi)\n\n## Two\n"
)


KINDS["document view"] = Kind(
    modules=(
        "tui/semantic-collections.f", "markup/markdown.f", "pdf/document.f",
        "tui/widgets/document.f",
    ),
    change=(
        "DOCV-OWNER!", "DOCV-DOCUMENT!", "DOCV-SERVICE", "DOCV-SCROLL",
        "DOCV-GO", "DOCV-GO-ENTRY", "DOCV-FOLLOW", "DOCV-GO-PART",
    ),
    same=(
        "DOCV-DOCUMENT@", "DOCV-REVISION@", "DOCV-TOP@", "DOCV-SHOWN",
        "DOCV-ROWS", "DOCV-PENDING?", "DOCV-GENUINE?", "DOCV-FIGURE-COUNT",
        "DOCV-FIGURE@", "DOCV-FIGURE-PICTURE",
        "DOCV-DOCUMENT-STORAGE-DISJOINT?", "DOCV-DOCUMENT-MEASURE",
        "DOCV-DOCUMENT-CAPTURE",
    ),
    other=("DOCV-NEW", "DOCV-FREE", "DOCV-WORK?", "DOCV-STORAGE-DISJOINT?"),
    minimum=24,
    scenario=MEMORY_SOURCE + _string("_DV-TEXT", _FIGURED)
    + _bytes("_DV-PICTURE", _PICTURE) + _bytes("_DV-PDF", _pages_pdf()) + r'''
\ Each view shows its own copies of a Markdown document with a figure,
\ whose picture its owner gives from memory, and of a PDF in pages.
: _DV-RESOLVE  ( name-a name-u ctx -- source|0 )
    DROP 2DROP  MEDSRC-SIZE _FS-MS MSRC-ALLOC DUP 0= IF EXIT THEN
    >R _DV-PICTURE$ R@ MEDSRC-MEMORY R> ;
: _DV-RELEASE  ( source ctx -- )
    DROP DUP MEDSRC-RELEASE MEDSRC-SIZE _FS-MS MSRC-FREE ;
: _DV-OPEN  ( a u reader -- doc )
    >R MEDSRC-SIZE _FS-MS MSRC-ALLOC DUP 0= ABORT" no source"
    DUP >R MEDSRC-MEMORY R> R>
    DOC-SIZE _FS-MS MSRC-ALLOC DUP 0= ABORT" no document"
    >R _FS-MS R@ DOC-OPEN ABORT" not read" R> ;
_DV-TEXT$ MD-READER _DV-OPEN CONSTANT _DV-MD-A
_DV-TEXT$ MD-READER _DV-OPEN CONSTANT _DV-MD-B
_DV-PDF$ PDF-DOC-READER _DV-OPEN CONSTANT _DV-PDF-A
_DV-PDF$ PDF-DOC-READER _DV-OPEN CONSTANT _DV-PDF-B
0 0 6 30 RGN-NEW _FS-MS DOCV-NEW CONSTANT _DV-A
0 0 6 30 RGN-NEW _FS-MS DOCV-NEW CONSTANT _DV-B
: _DV-MD  ( -- doc )  _WR-W @ _DV-A = IF _DV-MD-A ELSE _DV-MD-B THEN ;
: _DV-PAGES  ( -- doc )  _WR-W @ _DV-A = IF _DV-PDF-A ELSE _DV-PDF-B THEN ;
: _VS1  ['] _DV-RESOLVE ['] _DV-RELEASE 0 0 _WR-W @ DOCV-OWNER! ;
' _VS1 _WR-STEP
: _VS2  _DV-MD _WR-W @ DOCV-DOCUMENT! ;           ' _VS2 _WR-STEP
\ A draw gives the figure in view its picture, which asks for its copy;
\ the service pass decodes it.
: _VS-DRAW  _WR-W @ WDG-DRAW ;                    ' _VS-DRAW _WR-PREP
' _VS-DRAW _WR-PREP
: _VS3  _WR-W @ DOCV-SERVICE DROP ;               ' _VS3 _WR-STEP
: _VS4  3 _WR-W @ DOCV-SCROLL ;                   ' _VS4 _WR-STEP
: _VS5  0 _WR-W @ DOCV-GO ;                       ' _VS5 _WR-STEP
\ An entry is one of the contents, which are made when first asked for.
: _VS-CONTENTS  _DV-MD DOC-CONTENTS 2DROP ;       ' _VS-CONTENTS _WR-PREP
: _VS6  1 _WR-W @ DOCV-GO-ENTRY ;                 ' _VS6 _WR-STEP
: _VS7  S" #three" _WR-W @ DOCV-FOLLOW ;          ' _VS7 _WR-STEP
: _VS8  _DV-PAGES _WR-W @ DOCV-DOCUMENT! ;        ' _VS8 _WR-STEP
' _VS-DRAW _WR-PREP
' _VS3 _WR-STEP
: _VS9  1 _WR-W @ DOCV-GO-PART ;                  ' _VS9 _WR-STEP
_DV-A _DV-B _WR-RUN
_DV-A _WR-W !
: _VQ1  _WR-W @ DOCV-DOCUMENT@ DROP ;             ' _VQ1 _WR-STILL
: _VQ2  _WR-W @ DOCV-REVISION@ DROP ;             ' _VQ2 _WR-STILL
: _VQ3  _WR-W @ DOCV-TOP@ 2DROP ;                 ' _VQ3 _WR-STILL
: _VQ4  _WR-W @ DOCV-SHOWN 2DROP ;                ' _VQ4 _WR-STILL
: _VQ5  0 _WR-W @ DOCV-ROWS DROP ;                ' _VQ5 _WR-STILL
: _VQ6  _WR-W @ DOCV-PENDING? DROP ;              ' _VQ6 _WR-STILL
: _VQ7  _WR-W @ DOCV-GENUINE? DROP ;              ' _VQ7 _WR-STILL
: _VQ8  _WR-W @ DOCV-FIGURE-COUNT DROP ;          ' _VQ8 _WR-STILL
: _VQ9  0 _WR-W @ DOCV-FIGURE@ 2DROP ;            ' _VQ9 _WR-STILL
: _VQ10  5 _WR-W @ DOCV-FIGURE-PICTURE DROP ;     ' _VQ10 _WR-STILL
: _VQ11  _WR-OUT 4096 _WR-W @ DOCV-DOCUMENT-STORAGE-DISJOINT? DROP ;
' _VQ11 _WR-STILL
: _VQ12  5 _WR-BLD _WR-W @ DOCV-DOCUMENT-MEASURE 2DROP ;   ' _VQ12 _WR-STILL
: _VQ13  5 _WR-OUT 4096 _WR-BLD _WR-W @ DOCV-DOCUMENT-CAPTURE 2DROP ;
' _VQ13 _WR-STILL
''',
)


def _public_words(path: Path) -> set[str]:
    """The public words a module defines, before any guard wrappers."""
    text = path.read_text(encoding="utf-8")
    text = text.split("[DEFINED] GUARDED [IF]", 1)[0]
    text = re.sub(r"(?m)(?:^|\s)\\(?:\s.*)?$", "", text)
    return set(re.findall(r"(?m)^:\s+([A-Z][^\s]*)", text))


def _module(kind: Kind) -> Path:
    return ROOT / "akashic" / kind.modules[-1]


@pytest.mark.parametrize("name", sorted(KINDS))
def test_every_public_word_is_placed(name: str) -> None:
    kind = KINDS[name]
    placed = set(kind.change) | set(kind.same) | set(kind.other)
    assert len(placed) == len(kind.change) + len(kind.same) + len(kind.other)
    assert placed == _public_words(_module(kind))
    for word in kind.change + kind.same:
        assert re.search(rf"(?<!\S){re.escape(word)}(?!\S)", kind.scenario), word


@pytest.mark.parametrize("name", sorted(KINDS))
def test_each_change_moves_the_revision_and_draws_as_a_fresh_widget(
    name: str,
) -> None:
    kind = KINDS[name]
    run_field(
        PRELUDE + COMMON + kind.scenario + "\n_FM-DONE\n",
        minimum=kind.minimum,
        extra_sources=kind.modules,
    )
