#!/usr/bin/env python3
"""tui/applets/desk/install-surface.f: Desk's question before an install.

The suite drives the screen's state over the applet builder's real
question, without a screen: the project line and the rows, Cancel then
Install, the answer each row and Escape give the builder, and the screen
closing once it has answered or once its asker withdrew the question.  The
overlay's drawing runs in Desk's smokes.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


PRELUDE = r"""
CREATE KS-RAW _KIS-SIZE 7 + ALLOT  KS-RAW 7 + -8 AND CONSTANT KS
CREATE KI COMP-INST ALLOT  KI COMP-INST 0 FILL  KS KI CINST.STATE !
VARIABLE KRGN  VARIABLE KLIST
\ The screen's state for the question asked, with its list, as Desk binds it.
: SCREEN-ON  ( -- )
    KS _KIS-SIZE 0 FILL  KS _KIS-PROJECT!
    0 0 4 60 RGN-NEW DUP KRGN !
    ['] _KIS-KEY ['] _KIS-FIELD LST-NEW DUP KLIST !
    ['] _KIS-OPENED OVER LST-ON-OPEN
    _KIS-COLUMNS 1 2 PICK LST-COLUMNS!
    KS OVER LST-CONTEXT!  2 OVER LST-ROWS!  KS _KIS.LIST ! ;
: SCREEN-OFF  ( -- )
    KLIST @ ?DUP IF LST-FREE THEN 0 KLIST !  0 KS _KIS.LIST !
    KRGN @ ?DUP IF RGN-FREE THEN 0 KRGN ! ;
: PROJECT.  ( -- ) KS _KIS.PROJECT KS _KIS.PROJECT-U @ TYPE CR ;
: ROWS.  ( -- ) 2 0 DO I 0 KLIST @ _KIS-FIELD TYPE ." |" LOOP CR ;
: OPEN-ROW  ( index -- ) KLIST @ _KIS-OPENED ;
: SERVICE.  ( -- ) KI KIS-SERVICE . ABUILD-QUESTION@ . CR ;
CREATE EV 24 ALLOT
: ESCAPE  ( -- ) KEY-T-SPECIAL EV ! KEY-ESC EV 8 + ! 0 EV 16 + ! EV KI _KIS-EVENT . ;
: ASK  ( -- ) ABUILD-WITHDRAW S" /hello.toml" 4096 ABUILD-ASK . ;
"""

SUITE = NativeForth(("tui/applets/desk/install-surface.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str]) -> list[str]:
    output = forth.run(lines, 400_000_000).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.rstrip() for line in output.replace("\r", "").split("\n")
            if line.strip()]


# The builder's question states: NONE 0, ASKING 1, ALLOWED 2, REFUSED 3.


def test_the_screen_names_the_project_and_offers_cancel_first(forth):
    rows = run(forth, ["ASK CR SCREEN-ON PROJECT. ROWS. SERVICE. SCREEN-OFF"])
    assert rows == ["0", "Project: /hello.toml", "Cancel|Install|", "0 1"]


def test_each_answer_reaches_the_builder(forth):
    rows = run(forth, [
        # Install allows, and the screen closes.
        "ASK CR SCREEN-ON 1 OPEN-ROW SERVICE. SERVICE. SCREEN-OFF",
        # Cancel refuses.
        "ASK CR SCREEN-ON 0 OPEN-ROW SERVICE. SCREEN-OFF",
        # Escape refuses too.
        "ASK CR SCREEN-ON ESCAPE CR SERVICE. SCREEN-OFF",
    ])
    assert rows == [
        "0", "-1 2", "-1 2",
        "0", "-1 3",
        "0", "-1", "-1 3",
    ]


def test_a_question_withdrawn_closes_the_screen_unanswered(forth):
    rows = run(forth, [
        "ASK CR SCREEN-ON SERVICE. ABUILD-WITHDRAW SERVICE.",
        # A choice made after the question went changes nothing.
        "1 OPEN-ROW SERVICE. SCREEN-OFF",
    ])
    assert rows == ["0", "0 1", "-1 0", "-1 0"]
