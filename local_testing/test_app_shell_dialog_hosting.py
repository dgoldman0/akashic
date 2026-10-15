"""The app shell hosts only its own application's dialog.

A child context stays current after the child paints or is captured, so a
child's open dialog is then in the UIDL globals.  The shell's own key,
pointer and paint steps must leave that dialog to the child's host, as
Desk's applet host runs it; a standalone application's own dialog, with no
child context current, still takes them.
"""

from test_shell_snapshot import PRELUDE, _run


HOSTING = PRELUDE + r'''
CREATE _AD-CD COMP-DESC ALLOT CREATE _AD-AD APP-DESC ALLOT
CREATE _AD-EVS 31 ALLOT : _AD-EV _AD-EVS 7 + -8 AND ;
CREATE _AD-BT 48 ALLOT
VARIABLE _AD-I VARIABLE _AD-S VARIABLE _AD-EVENTS VARIABLE _AD-CHILD
VARIABLE _AD-ANS VARIABLE _AD-ROW VARIABLE _AD-COL
: _AD-EVENT ( ev instance -- consumed? ) 2DROP 1 _AD-EVENTS +! -1 ;
: _AD-ANSWER ( index context -- ) DROP _AD-ANS ! ;
S" OK" _AD-BT 8 + ! _AD-BT ! DLG-B-DEFAULT _AD-BT 16 + !
S" No" _AD-BT 32 + ! _AD-BT 24 + ! DLG-B-CANCEL _AD-BT 40 + !
: _AD-ASK ( -- ok? ) S" Title" S" Proceed?" _AD-BT 2 ['] _AD-ANSWER 0 DLG-ASK ;
\ The dialog's top-left cell, and a left press on its first button.
: _AD-CORNER ( -- row col ) DLG-SHOWN WDG-REGION DUP RGN-ROW SWAP RGN-COL ;
: _AD-CLICK ( -- )
    KEY-T-MOUSE _AD-EV ! KEY-MOUSE-LEFT _AD-EV 8 + !
    DLG-SHOWN WDG-REGION DUP RGN-ROW OVER RGN-H + 2 - 16 LSHIFT
    SWAP RGN-COL DLG-SHOWN 0 _DLG-BTN-COL + OR _AD-EV 16 + ! ;
: _AD-ESCAPE ( -- )
    KEY-T-SPECIAL _AD-EV ! KEY-ESC _AD-EV 8 + ! 0 _AD-EV 16 + ! ;
40 12 SCR-NEW DUP _AD-S ! SCR-USE
_AD-CD COMP-DESC-INIT _AD-CD CINST-NEW _SS-OK DUP _AD-I ! _ASHELL-INST !
_AD-AD APP-DESC-INIT _AD-CD _AD-AD APP.COMP-DESC !
' _AD-EVENT _AD-AD APP.EVENT-XT ! _AD-AD _ASHELL-DESC !
'''

CLEANUP = r'''
0 ASHELL-CTX-SWITCH _AD-CHILD @ ?DUP IF UCTX-FREE THEN
0 _ASHELL-DESC ! 0 _ASHELL-INST ! _AD-I @ CINST-FREE _AD-S @ SCR-FREE
_SS-DONE
'''


def test_a_childs_dialog_left_current_is_its_hosts_not_the_shells():
    _run(HOSTING + r'''
UCTX-ALLOC DUP _AD-CHILD ! UCTX-CLEAR _AD-CHILD @ ASHELL-CTX-SWITCH
-1 _AD-ANS ! _AD-ASK _SS-A DLG-HOST-PAINT DLG-SHOWN 0<> _SS-A
_AD-CORNER _AD-COL ! _AD-ROW !
\ A press on its button and Escape reach the application, unanswered.
_AD-CLICK _AD-EV _ASHELL-DISPATCH-MOUSE-IMPL
_AD-EVENTS @ 1 = _SS-A DLG-SHOWN 0<> _SS-A _AD-ANS @ -1 = _SS-A
_AD-ESCAPE _AD-EV _ASHELL-DISPATCH-KEY
_AD-EVENTS @ 2 = _SS-A DLG-SHOWN 0<> _SS-A _AD-ANS @ -1 = _SS-A
\ The shell's paint leaves it to the child's paint.
RGN-ROOT 88 _AD-ROW @ _AD-COL @ DRW-CHAR
-1 _ASHELL-DIRTY ! _ASHELL-PAINT
_AD-ROW @ _AD-COL @ SCR-GET CELL-CP@ 88 = _SS-A
\ Its own host answers it, with the child's context current.
_AD-CLICK _AD-EV DLG-HOST-EVENT _SS-A
_AD-ANS @ 0= _SS-A DLG-SHOWN 0= _SS-A
''' + CLEANUP, minimum=12)


def test_a_standalone_applications_own_dialog_takes_its_events():
    _run(HOSTING + r'''
0 _AD-CHILD !
-1 _AD-ANS ! _AD-ASK _SS-A DLG-HOST-PAINT DLG-SHOWN 0<> _SS-A
_AD-ESCAPE _AD-EV _ASHELL-DISPATCH-KEY
_AD-EVENTS @ 0= _SS-A DLG-SHOWN 0= _SS-A _AD-ANS @ 1 = _SS-A
-1 _AD-ANS ! _AD-ASK _SS-A DLG-HOST-PAINT
_AD-CLICK _AD-EV _ASHELL-DISPATCH-MOUSE-IMPL
_AD-EVENTS @ 0= _SS-A DLG-SHOWN 0= _SS-A _AD-ANS @ 0= _SS-A
\ The shell paints its own application's dialog.
-1 _AD-ANS ! _AD-ASK _SS-A DLG-HOST-PAINT _AD-CORNER _AD-COL ! _AD-ROW !
RGN-ROOT 88 _AD-ROW @ _AD-COL @ DRW-CHAR
-1 _ASHELL-DIRTY ! _ASHELL-PAINT
_AD-ROW @ _AD-COL @ SCR-GET CELL-CP@ 88 <> _SS-A
DLG-DISCARD
''' + CLEANUP, minimum=12)
