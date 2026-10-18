"""The app shell's notice: its own copy of the text, its meaning, the layout
a paint decides once, its CELL bar, the UDLG model a renderer takes, and
the press it takes, run in the native source runtime."""

from test_shell_snapshot import PRELUDE, _run


NOTICE = PRELUDE + r'''
CREATE _NT-CD COMP-DESC ALLOT CREATE _NT-AD APP-DESC ALLOT
CREATE _NT-EVS 31 ALLOT : _NT-EV _NT-EVS 7 + -8 AND ;
CREATE _NT-TS 71 ALLOT : _NT-T _NT-TS 7 + -8 AND ;
VARIABLE _NT-I VARIABLE _NT-S VARIABLE _NT-EVENTS VARIABLE _NT-U
: _NT-EVENT ( ev instance -- consumed? ) 2DROP 1 _NT-EVENTS +! -1 ;
: _NT-SAVED S" Saved" ;
: _NT-LONG S" abcdefghijklmnop" ;
\ Text written byte by byte: an ellipsis, five wide characters, a
\ right-to-left override inside "abcd", and a bell inside "ab".
CREATE _NT-ELL 0xE2 C, 0x80 C, 0xA6 C,
CREATE _NT-WIDES 0xE6 C, 0x97 C, 0xA5 C, 0xE6 C, 0x9C C, 0xAC C, 0xE8 C, 0xAA C,
    0x9E C, 0xE3 C, 0x83 C, 0x86 C, 0xE3 C, 0x82 C, 0xAD C,
CREATE _NT-RLOS 0x61 C, 0x62 C, 0xE2 C, 0x80 C, 0xAE C, 0x63 C, 0x64 C,
CREATE _NT-BELLS 0x61 C, 0x07 C, 0x62 C,
: _NT-WIDE _NT-WIDES 15 ; : _NT-RLO _NT-RLOS 7 ; : _NT-BELL _NT-BELLS 3 ;
: _NT-SHOWN ( -- a u ) _ASHELL-SHOWN-BUF @ _ASHELL-SHOWN-U @ ;
: _NT-CELL ( row col -- cell ) SCR-GET ;
\ A mouse event of CODE at ROW COL, dispatched as the shell does.
: _NT-MOUSE ( code row col -- )
    KEY-T-MOUSE _NT-EV ! ROT _NT-EV 8 + ! SWAP 16 LSHIFT OR _NT-EV 16 + !
    _NT-EV _ASHELL-DISPATCH-MOUSE-IMPL ;
: _NT-SCREEN ( cols rows -- ) SCR-NEW DUP _NT-S ! SCR-USE ;
_NT-CD COMP-DESC-INIT _NT-CD CINST-NEW _SS-OK DUP _NT-I ! _ASHELL-INST !
_NT-AD APP-DESC-INIT _NT-CD _NT-AD APP.COMP-DESC !
' _NT-EVENT _NT-AD APP.EVENT-XT ! _NT-AD _ASHELL-DESC !
'''

CLEANUP = r'''
_ASHELL-TOAST-FREE
0 _ASHELL-DESC ! 0 _ASHELL-INST ! _NT-I @ CINST-FREE _NT-S @ SCR-FREE
_SS-DONE
'''


def test_a_notice_keeps_its_own_copy_of_its_text_and_its_meaning():
    _run(NOTICE + r'''
\ The caller's buffer may change once the notice is raised.
S" Copied" _NT-T SWAP MOVE
_NT-T 6 1000 ASHELL-TOAST-ERROR
S" XXXXXX" _NT-T SWAP MOVE
_ASHELL-TOAST-MSG 2@ S" Copied" COMPARE 0= _SS-A
_ASHELL-TOAST-MSG 2@ DROP _NT-T <> _SS-A
_ASHELL-TOAST-SEVERITY @ ASHELL-SEVERITY-ERROR = _SS-A
_ASHELL-TOAST-SERIAL @ _NT-U !
_NT-SAVED 1000 ASHELL-TOAST-WARNING
_ASHELL-TOAST-SEVERITY @ ASHELL-SEVERITY-WARNING = _SS-A
_ASHELL-TOAST-SERIAL @ _NT-U @ 1+ = _SS-A
_NT-SAVED 1000 ASHELL-TOAST _ASHELL-TOAST-SEVERITY @ 0= _SS-A
\ A severity the shell does not know is neutral.
_NT-SAVED 1000 9 ASHELL-NOTICE _ASHELL-TOAST-SEVERITY @ 0= _SS-A
_NT-SAVED 1000 ASHELL-SEVERITY-SUCCESS ASHELL-NOTICE
_ASHELL-TOAST-SEVERITY @ 2 = _SS-A
\ A longer text grows the buffer; a notice of its own text keeps it.
_NT-LONG 1000 ASHELL-TOAST _ASHELL-TOAST-MSG 2@ _NT-LONG COMPARE 0= _SS-A
_ASHELL-TOAST-CAP @ 16 < 0= _SS-A
_ASHELL-TOAST-MSG 2@ 4 - SWAP 2 + SWAP 1000 ASHELL-TOAST
_ASHELL-TOAST-MSG 2@ S" cdefghijklmn" COMPARE 0= _SS-A
_ASHELL-TOAST-WAS-VIS @ _SS-A ASHELL-TOAST-VISIBLE? _SS-A
_ASHELL-TOAST-FREE _ASHELL-TOAST-BUF @ 0= _SS-A _ASHELL-TOAST-MSG 2@ NIP 0= _SS-A
_SS-DONE
''', minimum=16)


def test_a_paint_lays_out_and_draws_the_notice_it_shows():
    _run(NOTICE + r'''
40 12 _NT-SCREEN
ASHELL-NOTICE-SHOWN? 0= _SS-A
_NT-SAVED 60000 ASHELL-TOAST-ERROR _ASHELL-TOAST-LATCH
ASHELL-NOTICE-SHOWN? _SS-A
_NT-SHOWN _NT-SAVED COMPARE 0= _SS-A _ASHELL-SHOWN-CELLS @ 5 = _SS-A
\ A bar four cells wider than the text, centred on the bottom row.
ASHELL-NOTICE-ROOT 9 = _SS-A 1 = _SS-A 15 = _SS-A 11 = _SS-A
_ASHELL-DRAW-TOAST
11 15 _NT-CELL DUP CELL-CP@ 32 = _SS-A DUP CELL-BG@ 124 = _SS-A
    CELL-ATTRS@ 1 AND _SS-A
11 17 _NT-CELL DUP CELL-CP@ 83 = _SS-A CELL-FG@ 255 = _SS-A
11 21 _NT-CELL CELL-CP@ 100 = _SS-A
11 23 _NT-CELL CELL-BG@ 124 = _SS-A
11 24 _NT-CELL CELL-BG@ 124 <> _SS-A
\ Neutral and warning colours.
_NT-SAVED 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH _ASHELL-DRAW-TOAST
11 15 _NT-CELL DUP CELL-BG@ 236 = _SS-A CELL-FG@ 253 = _SS-A
_NT-SAVED 60000 ASHELL-TOAST-WARNING _ASHELL-TOAST-LATCH _ASHELL-DRAW-TOAST
11 15 _NT-CELL CELL-BG@ 214 = _SS-A
\ The layout is kept while the notice and the width stay the same.
_ASHELL-SHOWN-REVISION @ _NT-U ! _ASHELL-TOAST-LATCH
_ASHELL-SHOWN-REVISION @ _NT-U @ = _SS-A
\ Its output goes out, which starts its time.  A notice that has ended
\ shows no more, and holds no memory.
_ASHELL-TOAST-ARM
MS@ 1- _ASHELL-TOAST-EXPIRY ! _ASHELL-TOAST-LATCH ASHELL-NOTICE-SHOWN? 0= _SS-A
ASHELL-NOTICE-ROOT OR OR OR 0= _SS-A
_ASHELL-TOAST-BUF @ 0= _SS-A _ASHELL-SHOWN-BUF @ 0= _SS-A
''' + CLEANUP, minimum=25)


def test_a_notice_lasts_its_time_from_when_its_output_goes_out():
    _run(NOTICE + r'''
40 12 _NT-SCREEN
_NT-SAVED 60000 ASHELL-TOAST
\ Raised, but no output has shown it yet: it has not begun to end, however
\ late that output comes.
_ASHELL-TOAST-ARMED @ 0= _SS-A ASHELL-TOAST-VISIBLE? _SS-A
MS@ 1000 - _ASHELL-TOAST-EXPIRY ! ASHELL-TOAST-VISIBLE? _SS-A
\ A paint that shows it does not start its time: the output carrying it,
\ a slow rich frame say, may still be on its way.
_ASHELL-TOAST-LATCH ASHELL-NOTICE-SHOWN? _SS-A _ASHELL-TOAST-ARMED @ 0= _SS-A
\ Once that output has gone out its time starts, as the paint's flush does.
_ASHELL-TOAST-ARM _ASHELL-TOAST-ARMED @ _SS-A
_ASHELL-TOAST-EXPIRY @ MS@ - DUP 0> _SS-A 60000 > 0= _SS-A
\ A later paint and output keep its time; once it ends no paint shows it.
_ASHELL-TOAST-EXPIRY @ _NT-U ! _ASHELL-TOAST-LATCH _ASHELL-TOAST-ARM
_ASHELL-TOAST-EXPIRY @ _NT-U @ = _SS-A
MS@ 1- _ASHELL-TOAST-EXPIRY ! _ASHELL-TOAST-LATCH ASHELL-NOTICE-SHOWN? 0= _SS-A
\ A new notice starts afresh.
_NT-SAVED 60000 ASHELL-TOAST _ASHELL-TOAST-ARMED @ 0= _SS-A ASHELL-TOAST-VISIBLE? _SS-A
''' + CLEANUP, minimum=12)


def test_a_notice_raised_during_a_paint_shows_from_the_next():
    _run(NOTICE + r'''
40 12 _NT-SCREEN
_NT-SAVED 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH
_NT-LONG 60000 ASHELL-TOAST-ERROR
_NT-SHOWN _NT-SAVED COMPARE 0= _SS-A _ASHELL-SHOWN-SEVERITY @ 0= _SS-A
_ASHELL-DRAW-TOAST 11 17 _NT-CELL CELL-CP@ 83 = _SS-A
_ASHELL-TOAST-LATCH _NT-SHOWN _NT-LONG COMPARE 0= _SS-A
_ASHELL-SHOWN-SEVERITY @ 4 = _SS-A
''' + CLEANUP, minimum=6)


def test_a_notice_too_wide_for_the_screen_ends_in_an_ellipsis():
    _run(NOTICE + r'''
12 4 _NT-SCREEN
_NT-LONG 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH
_NT-SHOWN 3 - S" abcdefg" COMPARE 0= _SS-A
_NT-SHOWN DROP 7 + 3 _NT-ELL 3 COMPARE 0= _SS-A
_ASHELL-SHOWN-CELLS @ 8 = _SS-A
ASHELL-NOTICE-ROOT 12 = _SS-A 1 = _SS-A 0= _SS-A 3 = _SS-A
\ Wide characters are cut whole: three of them and the ellipsis.
_NT-WIDE 60000 ASHELL-TOAST
_ASHELL-TOAST-LATCH _ASHELL-SHOWN-CELLS @ 7 = _SS-A _ASHELL-SHOWN-U @ 12 = _SS-A
\ A width that fits keeps the whole text.
S" abcdefgh" 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH
_NT-SHOWN S" abcdefgh" COMPARE 0= _SS-A
\ A screen without room for a cell of text shows none, but keeps the
\ notice while it lasts.
_NT-S @ SCR-FREE 4 4 _NT-SCREEN _ASHELL-TOAST-LATCH ASHELL-NOTICE-SHOWN? 0= _SS-A
_ASHELL-SHOWN-BUF @ 0= _SS-A _ASHELL-TOAST-MSG 2@ S" abcdefgh" COMPARE 0= _SS-A
''' + CLEANUP, minimum=14)


def test_the_notice_capture_is_a_canonical_udlg_notice():
    _run(NOTICE + r'''
40 12 _NT-SCREEN
0 0 ASHELL-NOTICE-CAPTURE UDLG-S-UNSUPPORTED = _SS-A DROP
_NT-SAVED 60000 ASHELL-TOAST-WARNING _ASHELL-TOAST-LATCH
0 0 ASHELL-NOTICE-CAPTURE _SS-OK DUP _NT-U ! 0 5 UDLG-TEXT-BYTES = _SS-A
_SS-O 8 ASHELL-NOTICE-CAPTURE UDLG-S-CAPACITY = _SS-A _NT-U @ = _SS-A
_SS-O 1+ 4096 ASHELL-NOTICE-CAPTURE UDLG-S-INVALID = _SS-A DROP
_ASHELL-SHOWN-BUF @ -8 AND 4096 ASHELL-NOTICE-CAPTURE UDLG-S-INVALID = _SS-A DROP
_SS-O 4096 ASHELL-NOTICE-CAPTURE _SS-OK _NT-U @ = _SS-A
_SS-O _NT-U @ UDLG-VALIDATE _SS-OK
_SS-O UDLG-FLAGS@ UDLG-F-NOTICE = _SS-A _SS-O UDLG-SEVERITY@ 3 = _SS-A
_SS-O UDLG-WIDTH@ 9 = _SS-A _SS-O UDLG-HEIGHT@ 1 = _SS-A
_SS-O UDLG-KEY@ _ASHELL-TOAST-SERIAL @ = _SS-A
_SS-O UDLG-REVISION@ _ASHELL-SHOWN-REVISION @ = _SS-A
_SS-O UDLG-BUTTON-COUNT@ 0= _SS-A _SS-O UDLG-TITLE@ NIP 0= _SS-A
_SS-O UDLG-MESSAGE@ _NT-SAVED COMPARE 0= _SS-A
_SS-O UDLG-MESSAGE-SLOT@ 5 = _SS-A 1 = _SS-A 2 = _SS-A 0= _SS-A
\ Direction controls go out inert; the shown text keeps them.
_NT-RLO 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH
_SS-O 4096 ASHELL-NOTICE-CAPTURE _SS-OK DROP
_SS-O UDLG-MESSAGE@ DROP 2 + 3 _NT-RLOS 2 + 3 COMPARE 0<> _SS-A
_NT-SHOWN DROP 2 + 3 _NT-RLOS 2 + 3 COMPARE 0= _SS-A
_SS-O DUP UDLG-BYTES@ UDLG-VALIDATE _SS-OK
\ Text that is not clean single-line text stays painted.
_NT-BELL 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH
_SS-O 4096 ASHELL-NOTICE-CAPTURE UDLG-S-UNSUPPORTED = _SS-A DROP
\ An empty notice has no message.
0 0 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH
_SS-O 4096 ASHELL-NOTICE-CAPTURE _SS-OK UDLG-HEADER-SIZE = _SS-A
_SS-O UDLG-WIDTH@ 4 = _SS-A _SS-O UDLG-MESSAGE-BYTES@ 0= _SS-A
_SS-O DUP UDLG-BYTES@ UDLG-VALIDATE _SS-OK
''' + CLEANUP, minimum=34)


def test_a_press_on_the_notice_lands_on_it():
    _run(NOTICE + r'''
40 12 _NT-SCREEN
_NT-SAVED 60000 ASHELL-TOAST _ASHELL-TOAST-LATCH
0 _NT-EVENTS !
KEY-MOUSE-LEFT 11 15 _NT-MOUSE _NT-EVENTS @ 0= _SS-A
KEY-MOUSE-RIGHT 11 23 _NT-MOUSE _NT-EVENTS @ 0= _SS-A
KEY-MOUSE-LEFT KEY-MOUSE-MOD-CTRL OR 11 20 _NT-MOUSE _NT-EVENTS @ 0= _SS-A
KEY-MOUSE-SCROLL-UP 11 18 _NT-MOUSE _NT-EVENTS @ 0= _SS-A
\ Beside it, above it, a release, a drag and a named position go on.
KEY-MOUSE-LEFT 11 14 _NT-MOUSE _NT-EVENTS @ 1 = _SS-A
KEY-MOUSE-LEFT 11 24 _NT-MOUSE _NT-EVENTS @ 2 = _SS-A
KEY-MOUSE-LEFT 10 18 _NT-MOUSE _NT-EVENTS @ 3 = _SS-A
KEY-MOUSE-RELEASE 11 18 _NT-MOUSE _NT-EVENTS @ 4 = _SS-A
KEY-MOUSE-DRAG 11 18 _NT-MOUSE _NT-EVENTS @ 5 = _SS-A
KEY-MOUSE-TEXT-PLACE 11 18 _NT-MOUSE _NT-EVENTS @ 6 = _SS-A
\ Once no paint shows it, a press there reaches the application.
_ASHELL-TOAST-ARM MS@ 1- _ASHELL-TOAST-EXPIRY ! _ASHELL-TOAST-LATCH
KEY-MOUSE-LEFT 11 18 _NT-MOUSE _NT-EVENTS @ 7 = _SS-A
''' + CLEANUP, minimum=12)
