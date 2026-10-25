#!/usr/bin/env python3
"""Widget words that changed what a widget shows without saying so now move
its revision (WDG-REVISION), and setting what a widget already has moves
nothing."""

from test_field_model import PRELUDE, run_field

MODULES = (
    "tui/widgets/textarea.f",
    "tui/widgets/tabs.f",
    "tui/widgets/menu.f",
    "tui/widgets/tree.f",
    "tui/widgets/list.f",
    "tui/widgets/canvas.f",
)

# _WC-MOVES? runs XT, a word of no inputs, and says whether W's revision
# moved.
COMMON = r'''
VARIABLE _WC-R
: _WC-MOVES?  ( xt w -- flag )
    DUP >R WDG-REVISION _WC-R ! EXECUTE R> WDG-REVISION _WC-R @ <> ;
CREATE _WC-EV 24 ALLOT
'''


def run(program, minimum):
    run_field(PRELUDE + COMMON + program, minimum=minimum, extra_sources=MODULES)


TEXTAREA = r'''
CREATE _WC-BUF 256 ALLOT
0 0 3 20 RGN-NEW _WC-BUF 256 TXTA-NEW CONSTANT _WC-T
: _WC-KEY  ( code mods -- )
    _WC-EV 16 + ! _WC-EV 8 + ! KEY-T-SPECIAL _WC-EV ! _WC-EV _WC-T WDG-HANDLE DROP ;
: _WC-RELEASE  ( -- )
    KEY-T-MOUSE _WC-EV ! KEY-MOUSE-RELEASE _WC-EV 8 + ! 0 _WC-EV 16 + !
    _WC-EV _WC-T WDG-HANDLE DROP ;
: _WC-ABC  S" abc" _WC-T TXTA-SET-TEXT ;
'''


def test_text_area_selection_changes_move_the_revision():
    run(TEXTAREA + r'''
_WC-ABC
: _WC-ALL  _WC-T TXTA-SELECT-ALL ;
' _WC-ALL _WC-T _WC-MOVES? _FM-A
\ Shift+Home selects back to the start; a plain Left then drops the
\ selection, though the caret stays at the start.
_WC-ABC KEY-HOME KEY-MOD-SHIFT _WC-KEY
: _WC-LEFT  KEY-LEFT 0 _WC-KEY ;
' _WC-LEFT _WC-T _WC-MOVES? _FM-A
_WC-T TXTA-GET-SEL NIP 0= _FM-A
\ Shift+Left then Shift+Right leaves a selection of nothing; the mouse
\ release that drops it is a change too.
_WC-ABC KEY-LEFT KEY-MOD-SHIFT _WC-KEY KEY-RIGHT KEY-MOD-SHIFT _WC-KEY
' _WC-RELEASE _WC-T _WC-MOVES? _FM-A
' _WC-RELEASE _WC-T _WC-MOVES? 0= _FM-A
_FM-DONE
''', minimum=5)


def test_text_area_scroll_gutter_and_buffer_changes_move_the_revision():
    run(TEXTAREA + r'''
\ Six lines in three rows, the caret on the last: keeping it in view
\ scrolls, and then there is nothing to do.
CREATE _WC-LINES 11 ALLOT
: _WC-SIX  S" a b c d e f" _WC-LINES SWAP CMOVE
    11 0 DO _WC-LINES I + C@ 32 = IF 10 _WC-LINES I + C! THEN LOOP
    _WC-LINES 11 _WC-T TXTA-SET-TEXT ;
_WC-SIX
: _WC-ADJ  _WC-T TXTA-ADJUST-SCROLL ;
' _WC-ADJ _WC-T _WC-MOVES? _FM-A
' _WC-ADJ _WC-T _WC-MOVES? 0= _FM-A
: _WC-GUT  ( line# row width widget -- ) 2DROP 2DROP ;
: _WC-GUTTER  ['] _WC-GUT 3 _WC-T TXTA-GUTTER! ;
' _WC-GUTTER _WC-T _WC-MOVES? _FM-A
' _WC-GUTTER _WC-T _WC-MOVES? 0= _FM-A
\ Binding a gap buffer changes the text's source; the handle is only
\ stored, so a stand-in will do, and nothing reads it after.
: _WC-BIND  _WC-BUF _WC-T TXTA-BIND-GB ;
: _WC-UNBIND  _WC-T TXTA-UNBIND-GB ;
' _WC-BIND _WC-T _WC-MOVES? _FM-A
' _WC-BIND _WC-T _WC-MOVES? 0= _FM-A
' _WC-UNBIND _WC-T _WC-MOVES? _FM-A
' _WC-UNBIND _WC-T _WC-MOVES? 0= _FM-A
_FM-DONE
''', minimum=8)


def test_tabs_and_menu_items_move_the_revision():
    run(r'''
0 0 5 20 RGN-NEW TAB-NEW CONSTANT _WC-TB
: _WC-ADD  S" One" _WC-TB TAB-ADD DROP ;
' _WC-ADD _WC-TB _WC-MOVES? _FM-A
: _WC-NOOP ;
: _WC-OPEN  S" Open" ;
: _WC-SAVE  S" Save" ;
: _WC-FILE  S" File" ;
CREATE _WC-ITEMS 64 ALLOT _WC-ITEMS 64 0 FILL
_WC-OPEN _WC-ITEMS 8 + ! _WC-ITEMS !  ' _WC-NOOP _WC-ITEMS 16 + !
_WC-SAVE _WC-ITEMS 40 + ! _WC-ITEMS 32 + !  ' _WC-NOOP _WC-ITEMS 48 + !
CREATE _WC-MENUS 32 ALLOT
_WC-FILE _WC-MENUS 8 + ! _WC-MENUS !  _WC-ITEMS _WC-MENUS 16 + !  2 _WC-MENUS 24 + !
0 0 1 20 RGN-NEW _WC-MENUS 1 MNU-NEW CONSTANT _WC-M
: _WC-DIS  _WC-M 0 1 MNU-ITEM-DISABLE ;
: _WC-EN  _WC-M 0 1 MNU-ITEM-ENABLE ;
: _WC-CHK  _WC-M 0 0 -1 MNU-ITEM-CHECK ;
: _WC-UNCHK  _WC-M 0 0 0 MNU-ITEM-CHECK ;
' _WC-DIS _WC-M _WC-MOVES? _FM-A  ' _WC-DIS _WC-M _WC-MOVES? 0= _FM-A
' _WC-EN _WC-M _WC-MOVES? _FM-A  ' _WC-EN _WC-M _WC-MOVES? 0= _FM-A
' _WC-CHK _WC-M _WC-MOVES? _FM-A  ' _WC-CHK _WC-M _WC-MOVES? 0= _FM-A
' _WC-UNCHK _WC-M _WC-MOVES? _FM-A  ' _WC-UNCHK _WC-M _WC-MOVES? 0= _FM-A
_FM-DONE
''', minimum=9)


def test_tree_settings_move_the_revision():
    run(r'''
: _WC-NONE  ( node -- 0 ) DROP 0 ;
: _WC-LABEL  ( node -- a u ) DROP S" root" ;
: _WC-LEAF?  ( node -- flag ) DROP -1 ;
: _WC-KEY  ( parent-key node -- key ) 2DROP 1 ;
0 0 5 20 RGN-NEW 1 ' _WC-NONE ' _WC-NONE ' _WC-LABEL ' _WC-LEAF? ' _WC-KEY
    TREE-NEW CONSTANT _WC-TR
: _WC-CTX  5 _WC-TR TREE-CONTEXT! ;
: _WC-UNTRUSTED  -1 _WC-TR TREE-UNTRUSTED! ;
' _WC-CTX _WC-TR _WC-MOVES? _FM-A  ' _WC-CTX _WC-TR _WC-MOVES? 0= _FM-A
' _WC-UNTRUSTED _WC-TR _WC-MOVES? _FM-A  ' _WC-UNTRUSTED _WC-TR _WC-MOVES? 0= _FM-A
_FM-DONE
''', minimum=4)


def test_canvas_drawing_moves_the_revision_and_reading_does_not():
    run(r'''
0 0 4 10 RGN-NEW CVS-NEW CONSTANT _WC-C
CREATE _WC-DATA 3 CELLS ALLOT  1 _WC-DATA !  4 _WC-DATA CELL+ !  2 _WC-DATA 2 CELLS + !
: _WC-SET  _WC-C 1 1 CVS-SET ;
: _WC-CLR  _WC-C 1 1 CVS-CLR ;
: _WC-COLOR  _WC-C 0 0 2 0 CVS-COLOR! ;
: _WC-LINE  _WC-C 0 0 5 5 CVS-LINE ;
: _WC-RECT  _WC-C 0 0 6 6 CVS-RECT ;
: _WC-FILL  _WC-C 1 1 3 3 CVS-FILL-RECT ;
: _WC-CIRCLE  _WC-C 8 8 3 CVS-CIRCLE ;
: _WC-PLOT  _WC-C _WC-DATA 3 2 1 CVS-PLOT ;
: _WC-GET  _WC-C 1 1 CVS-GET DROP ;
: _WC-PEN  _WC-C 3 0 CVS-PEN! ;
' _WC-SET _WC-C _WC-MOVES? _FM-A  ' _WC-CLR _WC-C _WC-MOVES? _FM-A
' _WC-COLOR _WC-C _WC-MOVES? _FM-A  ' _WC-LINE _WC-C _WC-MOVES? _FM-A
' _WC-RECT _WC-C _WC-MOVES? _FM-A  ' _WC-FILL _WC-C _WC-MOVES? _FM-A
' _WC-CIRCLE _WC-C _WC-MOVES? _FM-A  ' _WC-PLOT _WC-C _WC-MOVES? _FM-A
\ Reading a dot and choosing the pen show nothing new.
' _WC-GET _WC-C _WC-MOVES? 0= _FM-A  ' _WC-PEN _WC-C _WC-MOVES? 0= _FM-A
_FM-DONE
''', minimum=10)


def test_a_list_context_change_moves_the_revision():
    run(r'''
: _WC-ROWKEY  ( index widget -- key ) DROP 1+ ;
: _WC-FIELD  ( index column widget -- a u ) 2DROP DROP S" row" ;
0 0 5 20 RGN-NEW ' _WC-ROWKEY ' _WC-FIELD LST-NEW CONSTANT _WC-L
3 _WC-L LST-ROWS!
: _WC-LCTX  7 _WC-L LST-CONTEXT! ;
' _WC-LCTX _WC-L _WC-MOVES? _FM-A  ' _WC-LCTX _WC-L _WC-MOVES? 0= _FM-A
_WC-L LST-CONTEXT@ 7 = _FM-A
_FM-DONE
''', minimum=3)


def test_a_list_refresh_settles_on_the_rows_as_they_are_and_moves_the_revision():
    run(r'''
: _LR-KEY  ( index widget -- key ) DROP 1+ ;
: _LR-FIELD  ( index column widget -- addr len ) 2DROP DROP S" row" ;
VARIABLE _LR-HEADING  -1 _LR-HEADING !
: _LR-FLAGS  ( index widget -- flags ) DROP _LR-HEADING @ = IF LST-ROW-SECTION ELSE 0 THEN ;
0 0 5 20 RGN-NEW ' _LR-KEY ' _LR-FIELD LST-NEW CONSTANT _LR
' _LR-FLAGS _LR LST-ROW-FLAGS!  6 _LR LST-RECOUNT  3 _LR LST-SELECT
_LR LST-SELECTED 3 = _FM-A
\ Row 3 becomes a heading in the application's data.  The refresh moves
\ the selection off it, and it is a change.
3 _LR-HEADING !
: _LR-REFRESH  _LR LST-REFRESH ;
' _LR-REFRESH _LR _WC-MOVES? _FM-A
_LR _LST-O-SEL + @ 3 <> _FM-A
_FM-DONE
''', minimum=3)


def test_text_area_owner_words_move_the_revision_on_a_change():
    run(TEXTAREA + r'''
_WC-ABC
\ The caret: elsewhere moves the revision, where it is does not, and it
\ is kept within the text.
: _WC-C0  0 _WC-T TXTA-CURSOR! ;
' _WC-C0 _WC-T _WC-MOVES? _FM-A  ' _WC-C0 _WC-T _WC-MOVES? 0= _FM-A
_WC-T TXTA-CURSOR@ 0= _FM-A
99 _WC-T TXTA-CURSOR!  _WC-T TXTA-CURSOR@ 3 = _FM-A
\ A range is selected with the caret at its end; placing the caret drops
\ it.
: _WC-SEL  1 2 _WC-T TXTA-SELECT ;
' _WC-SEL _WC-T _WC-MOVES? _FM-A
_WC-T TXTA-SELECTION? _FM-A  _WC-T TXTA-CURSOR@ 2 = _FM-A
\ A view kept, left, and shown again.
VARIABLE _WC-VC  VARIABLE _WC-VS  VARIABLE _WC-VA
_WC-T TXTA-VIEW@ _WC-VA ! _WC-VS ! _WC-VC !
_WC-VC @ 2 = _FM-A  _WC-VA @ 1 = _FM-A  _WC-T TXTA-SCROLL-Y@ _WC-VS @ = _FM-A
0 _WC-T TXTA-CURSOR!  _WC-T TXTA-SELECTION? 0= _FM-A
: _WC-RESTORE  _WC-VC @ _WC-VS @ _WC-VA @ _WC-T TXTA-VIEW! ;
' _WC-RESTORE _WC-T _WC-MOVES? _FM-A
_WC-T TXTA-CURSOR@ 2 = _FM-A  _WC-T TXTA-SELECTION? _FM-A
\ Undo and redo, with a gap buffer and an undo state bound.
262144 A-XMEM ARENA-NEW DROP CONSTANT _WC-AR
32 _WC-AR GB-NEW CONSTANT _WC-GB
UNDO-NEW CONSTANT _WC-UD
_WC-GB _WC-T TXTA-BIND-GB  _WC-UD _WC-T TXTA-BIND-UNDO  0 _WC-T TXTA-CURSOR!
_WC-T TXTA-GB@ _WC-GB = _FM-A
S" x" _WC-T TXTA-INS-STR  _WC-T TXTA-LENGTH 1 = _FM-A
: _WC-UNDO  _WC-T TXTA-UNDO ;
: _WC-REDO  _WC-T TXTA-REDO ;
' _WC-UNDO _WC-T _WC-MOVES? _FM-A  _WC-T TXTA-LENGTH 0= _FM-A
' _WC-REDO _WC-T _WC-MOVES? _FM-A  _WC-T TXTA-LENGTH 1 = _FM-A
_FM-DONE
''', minimum=20)


def test_typing_names_the_rows_it_changed_until_anything_else_changes():
    run(TEXTAREA + r'''
40 10 SCR-NEW SCR-USE
: _WC-CHAR  ( cp -- )
    _WC-EV 8 + ! 0 _WC-EV 16 + ! KEY-T-CHAR _WC-EV ! _WC-EV _WC-T WDG-HANDLE DROP ;
: _WC-ROWS  ( -- first count ) _WC-T TXTA-CHANGED-ROWS ;
\ Before the first draw nothing is named.
_WC-ABC  CHAR d _WC-CHAR  _WC-ROWS NIP 0= _FM-A
\ After a draw, a typed character names its row, and so does a second.
_WC-T WDG-DRAW  _WC-ROWS NIP 0= _FM-A
CHAR e _WC-CHAR  _WC-ROWS 1 = _FM-A 0= _FM-A
CHAR f _WC-CHAR  _WC-ROWS 1 = _FM-A 0= _FM-A
\ Drawing those rows leaves nothing to name.
_WC-ROWS _WC-T TXTA-DRAW-ROWS  _WC-ROWS NIP 0= _FM-A
\ A line break at the end names its row and the next.
13 _WC-CHAR  _WC-ROWS 2 = _FM-A 0= _FM-A
\ Anything else since the typing asks for a whole draw: a scroll, a moved
\ region, a line break before the end, or typing over a selection.
_WC-T WDG-DRAW  CHAR g _WC-CHAR  1 _WC-T TXTA-SCROLL-X!  _WC-ROWS NIP 0= _FM-A
_WC-T WDG-DRAW  CHAR h _WC-CHAR  1 0 3 20 _WC-T WDG-REGION RGN-BOUNDS!
_WC-ROWS NIP 0= _FM-A
0 _WC-T TXTA-CURSOR!  _WC-T WDG-DRAW  13 _WC-CHAR  _WC-ROWS NIP 0= _FM-A
_WC-T TXTA-SELECT-ALL  _WC-T WDG-DRAW  CHAR i _WC-CHAR  _WC-ROWS NIP 0= _FM-A
_FM-DONE
''', minimum=13)
