\ =====================================================================
\  akashic/tui/widgets/dialog.f — Dialogs
\ =====================================================================
\
\  A dialog asks the application that opens it a question: a title, a
\  message and a row of buttons.  It never blocks.  DLG-ASK opens it over
\  the asking application, and that application's host — the app shell,
\  or Desk's applet host — gives the dialog the application's input and
\  paints it over the application until a button is chosen.  Then the
\  dialog closes, the host repaints what it covered, and the asker is
\  called back with the button.  Everything else, the rest of Desk
\  included, runs on meanwhile.
\
\  Left and Right move between the buttons and Tab cycles them; Enter
\  chooses the selected button and Escape the cancel button; a press on a
\  button chooses it.  The application's other events are swallowed while
\  the dialog is open.
\
\  Each button has roles: DLG-B-DEFAULT is selected when the dialog
\  opens, DLG-B-CANCEL answers Escape, and DLG-B-DESTRUCTIVE marks an
\  action that cannot be undone, which is never the default.
\
\  Dialog descriptor (128 bytes, then its button records and its text):
\    +0..+39  widget header  (type = WDG-T-DIALOG; the region is its own)
\    +40  title-a       +48  title-u
\    +56  msg-a         +64  msg-u
\    +72  buttons       COUNT records of three cells: label-a label-u roles
\    +80  btn-count
\    +88  selected      the button Enter chooses
\    +96  result        -1 while open, then the chosen button
\    +104 answer-xt     ( index context -- ), or 0
\    +112 context
\    +120 confirm?      the answer is a flag, true for the first button
\
\  The title, message and labels are the dialog's own copies, so an asker
\  may pass text it reuses.  Titles, messages and labels are measured in
\  cells, and a message wraps between whole characters (APT-1-TEXT
\  Sections 3 and 4).
\
\  Prefix: DLG- (public), _DLG- (internal)
\  Provider: akashic-tui-dialog

PROVIDED akashic-tui-dialog

REQUIRE ../keys.f
REQUIRE ../screen.f
REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../box.f
REQUIRE ../region.f
REQUIRE ../../text/grapheme.f
REQUIRE ../../text/cell-width.f

\ =====================================================================
\ 1. Host hooks
\ =====================================================================

\ The cell that holds the dialog the current application shows, or 0.
\ A host that runs several applications gives each its own cell; with no
\ such host one cell serves the one application.
VARIABLE _DLG-ONLY-CELL
0 _DLG-ONLY-CELL !
DEFER _DLG-CELL-HOOK  ( -- a )
' _DLG-ONLY-CELL IS _DLG-CELL-HOOK

\ The host repaints the rectangle a closing dialog leaves.
DEFER _DLG-DISMISS-HOOK  ( row col h w -- )
: _DLG-DISMISS-NOOP  ( row col h w -- )  2DROP 2DROP ;
' _DLG-DISMISS-NOOP IS _DLG-DISMISS-HOOK

\ The area a dialog is centred in.  Standalone dialogs use the whole
\ screen; UIDL hosts narrow this to the application's document region, so
\ a dialog never covers another application.
DEFER _DLG-BOUNDS-HOOK  ( -- row col h w )
: _DLG-BOUNDS-SCREEN  ( -- row col h w )  0 0 SCR-H SCR-W ;
' _DLG-BOUNDS-SCREEN IS _DLG-BOUNDS-HOOK

\ =====================================================================
\ 2. Descriptor layout and button roles
\ =====================================================================

40  CONSTANT _DLG-O-TITLE-A
48  CONSTANT _DLG-O-TITLE-U
56  CONSTANT _DLG-O-MSG-A
64  CONSTANT _DLG-O-MSG-U
72  CONSTANT _DLG-O-BTNS
80  CONSTANT _DLG-O-BCNT
88  CONSTANT _DLG-O-SEL
96  CONSTANT _DLG-O-RESULT
104 CONSTANT _DLG-O-XT
112 CONSTANT _DLG-O-CTX
120 CONSTANT _DLG-O-CONFIRM

128 CONSTANT _DLG-DESC-SIZE
24  CONSTANT _DLG-BTN-SIZE

1 CONSTANT DLG-B-DEFAULT
2 CONSTANT DLG-B-CANCEL
4 CONSTANT DLG-B-DESTRUCTIVE

\ =====================================================================
\ 3. Internal helpers
\ =====================================================================

: _DLG-BTN-ADDR  ( btns index -- addr )  _DLG-BTN-SIZE * + ;
: _DLG-BTN-LABEL  ( btns index -- a u )  _DLG-BTN-ADDR DUP @ SWAP 8 + @ ;
: _DLG-BTN-ROLES  ( btns index -- roles )  _DLG-BTN-ADDR 16 + @ ;

\ The first button having ROLE, or -1.
: _DLG-ROLE-INDEX  ( widget role -- index|-1 )
    OVER _DLG-O-BCNT + @ 0 ?DO
        OVER _DLG-O-BTNS + @ I _DLG-BTN-ROLES OVER AND IF
            2DROP I UNLOOP EXIT
        THEN
    LOOP 2DROP -1 ;

\ _DLG-FIT ( a u w -- bytes )
\   The bytes of A U's longest prefix of whole characters at most W cells
\   wide, so a wrapped row never ends inside a character; at least its
\   first character, even when that alone is wider.
CREATE _DLG-GC GR-CURSOR-SIZE ALLOT
VARIABLE _DLG-FIT-W
VARIABLE _DLG-FIT-B
VARIABLE _DLG-FIT-C

: _DLG-FIT  ( a u w -- bytes )
    _DLG-FIT-W ! 0 _DLG-FIT-B ! 0 _DLG-FIT-C !
    0 _DLG-GC GR-CURSOR-INIT
    BEGIN _DLG-GC GR-NEXT WHILE
        _DLG-FIT-C @ _DLG-GC GR-C-WIDTH +
        DUP _DLG-FIT-W @ > _DLG-FIT-B @ 0<> AND IF
            DROP _DLG-FIT-B @ EXIT
        THEN
        _DLG-FIT-C !
        _DLG-GC GR-C-BYTES _DLG-FIT-B +!
    REPEAT
    _DLG-FIT-B @ ;

\ _DLG-MSG-LINES ( a u w -- n )
\   The rows A U takes when wrapped to W cells, at least one.
VARIABLE _DLG-ML-A
VARIABLE _DLG-ML-U
VARIABLE _DLG-ML-W

: _DLG-MSG-LINES  ( a u w -- n )
    _DLG-ML-W ! _DLG-ML-U ! _DLG-ML-A !
    0 BEGIN _DLG-ML-U @ 0> WHILE
        1+
        _DLG-ML-A @ _DLG-ML-U @ _DLG-ML-W @ _DLG-FIT
        DUP _DLG-ML-A +! NEGATE _DLG-ML-U +!
    REPEAT
    1 MAX ;

\ The button row: each button is "[ label ]", one cell apart, the row
\ centred inside the box.  The cells all the buttons take, and where one
\ begins and how wide it is, from the dialog's left edge.
: _DLG-BTN-WIDTH  ( widget index -- cells )
    SWAP _DLG-O-BTNS + @ SWAP _DLG-BTN-LABEL CW-SWIDTH 4 + ;

VARIABLE _DLG-BS-W
: _DLG-BTN-SPAN  ( widget -- cells )
    DUP _DLG-BS-W ! _DLG-O-BCNT + @ DUP 1- 0 MAX
    SWAP 0 ?DO _DLG-BS-W @ I _DLG-BTN-WIDTH + LOOP ;

VARIABLE _DLG-BC-W
: _DLG-BTN-COL  ( widget index -- col )
    SWAP DUP _DLG-BC-W !
    DUP WDG-REGION RGN-W 2 - SWAP _DLG-BTN-SPAN - 0 MAX 2 / 1+
    SWAP 0 ?DO _DLG-BC-W @ I _DLG-BTN-WIDTH 1+ + LOOP ;

\ =====================================================================
\ 4. Layout
\ =====================================================================
\
\   Sized to its title, message and buttons, in cells, between 20 and 60
\   wide, and centred in the host's bounds.  Laid out again at each paint,
\   so it follows the application's region.

VARIABLE _DLG-L-W
VARIABLE _DLG-L-BR
VARIABLE _DLG-L-BC
VARIABLE _DLG-L-BH
VARIABLE _DLG-L-BW
VARIABLE _DLG-L-WD
VARIABLE _DLG-L-HT

: _DLG-LAYOUT  ( widget -- )
    _DLG-L-W !
    _DLG-BOUNDS-HOOK _DLG-L-BW ! _DLG-L-BH ! _DLG-L-BC ! _DLG-L-BR !
    _DLG-L-W @ DUP _DLG-O-TITLE-A + @ SWAP _DLG-O-TITLE-U + @ CW-SWIDTH 4 +
    _DLG-L-W @ DUP _DLG-O-MSG-A + @ SWAP _DLG-O-MSG-U + @ CW-SWIDTH 4 + MAX
    _DLG-L-W @ _DLG-BTN-SPAN 4 + MAX
    20 MAX 60 MIN _DLG-L-BW @ 2 - 1 MAX MIN _DLG-L-WD !
    _DLG-L-W @ DUP _DLG-O-MSG-A + @ SWAP _DLG-O-MSG-U + @
        _DLG-L-WD @ 4 - 1 MAX _DLG-MSG-LINES
    5 + _DLG-L-BH @ 2 - 1 MAX MIN _DLG-L-HT !
    _DLG-L-BH @ _DLG-L-HT @ - 2 / 0 MAX _DLG-L-BR @ +
    _DLG-L-BW @ _DLG-L-WD @ - 2 / 0 MAX _DLG-L-BC @ +
    _DLG-L-HT @ _DLG-L-WD @ _DLG-L-W @ WDG-REGION RGN-BOUNDS! ;

\ =====================================================================
\ 5. Draw
\ =====================================================================

VARIABLE _DLG-DRW-W       \ widget
VARIABLE _DLG-DRW-RW      \ region width
VARIABLE _DLG-DRW-RH      \ region height
VARIABLE _DLG-DRW-COL     \ current column for buttons
VARIABLE _DLG-DRW-BROW    \ button row

\ Layout: row 0 = box top, row 1 = blank, row 2..h-4 = message,
\ row h-3 = blank, row h-2 = buttons, row h-1 = box bottom.
: _DLG-MSG-ROWS  ( -- n )
    _DLG-DRW-RH @ 5 - DUP 1 < IF DROP 1 THEN ;

\ --- Message, wrapped between characters at the width ---

VARIABLE _DLG-MSG-ROW     \ current draw row
VARIABLE _DLG-MSG-ADDR    \ remaining text addr
VARIABLE _DLG-MSG-LEN     \ remaining text len
VARIABLE _DLG-MSG-MAXR    \ max rows for message
VARIABLE _DLG-MSG-MW      \ message width in cells (region width - 4)

: _DLG-DRAW-MESSAGE  ( -- )
    _DLG-DRW-W @ _DLG-O-MSG-A + @ _DLG-MSG-ADDR !
    _DLG-DRW-W @ _DLG-O-MSG-U + @ _DLG-MSG-LEN !
    2 _DLG-MSG-ROW !
    _DLG-MSG-ROWS _DLG-MSG-MAXR !
    _DLG-DRW-RW @ 4 - DUP 1 < IF DROP 1 THEN _DLG-MSG-MW !
    BEGIN
        _DLG-MSG-LEN @ 0>
        _DLG-MSG-MAXR @ 0>
        AND
    WHILE
        32 _DLG-MSG-ROW @ 2 _DLG-MSG-MW @ DRW-HLINE
        _DLG-MSG-ADDR @ _DLG-MSG-LEN @ _DLG-MSG-MW @ _DLG-FIT   ( bytes )
        _DLG-MSG-ADDR @ OVER _DLG-MSG-ROW @ 2 DRW-TEXT
        DUP _DLG-MSG-ADDR +!
        NEGATE _DLG-MSG-LEN +!
        1 _DLG-MSG-ROW +!
        -1 _DLG-MSG-MAXR +!
    REPEAT ;

\ --- Buttons, the selected one reversed ---

: _DLG-DRAW-BUTTONS  ( -- )
    _DLG-DRW-RH @ 2 - _DLG-DRW-BROW !
    32 _DLG-DRW-BROW @ 1 _DLG-DRW-RW @ 2 - DRW-HLINE
    _DLG-DRW-W @ _DLG-O-BCNT + @ 0 ?DO
        I _DLG-DRW-W @ _DLG-O-SEL + @ = IF CELL-A-REVERSE DRW-ATTR! THEN
        _DLG-DRW-W @ I _DLG-BTN-COL _DLG-DRW-COL !
        91 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR
        32 _DLG-DRW-BROW @ _DLG-DRW-COL @ 1+ DRW-CHAR
        _DLG-DRW-W @ _DLG-O-BTNS + @ I _DLG-BTN-LABEL
            _DLG-DRW-BROW @ _DLG-DRW-COL @ 2 + DRW-TEXT
        _DLG-DRW-W @ I _DLG-BTN-WIDTH 2 - _DLG-DRW-COL +!
        32 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR
        93 _DLG-DRW-BROW @ _DLG-DRW-COL @ 1+ DRW-CHAR
        I _DLG-DRW-W @ _DLG-O-SEL + @ = IF 0 DRW-ATTR! THEN
    LOOP ;

: _DLG-DRAW-BODY  ( widget -- )
    \ Its chrome must stay legible whatever style the application left.
    \ Preserve that style for the application.
    _DRW-FG @ _DRW-BG @ _DRW-ATTRS @ >R >R >R
    15 24 0 DRW-STYLE!
    _DLG-DRW-W !
    _DLG-DRW-W @ WDG-REGION RGN-W _DLG-DRW-RW !
    _DLG-DRW-W @ WDG-REGION RGN-H _DLG-DRW-RH !
    BOX-SINGLE _DLG-DRW-W @ DUP _DLG-O-TITLE-A + @ SWAP _DLG-O-TITLE-U + @
        0 0 _DLG-DRW-RH @ _DLG-DRW-RW @ BOX-DRAW-TITLED
    0 0 _DLG-DRW-RH @ _DLG-DRW-RW @ BOX-SHADOW
    32 1 1 _DLG-DRW-RH @ 2 - _DLG-DRW-RW @ 2 - DRW-FILL-RECT
    _DLG-DRAW-MESSAGE
    _DLG-DRAW-BUTTONS
    R> DRW-FG! R> DRW-BG! R> DRW-ATTR! ;

: _DLG-DRAW  ( widget -- )
    \ A dialog is foreground paint over its application.  Mark every
    \ write with final-writer provenance so an optional retained
    \ projection cannot paint stale semantics above it.
    ['] _DLG-DRAW-BODY DRW-OVERLAY ;

\ =====================================================================
\ 6. Handle
\ =====================================================================

VARIABLE _DLG-HND-W

: _DLG-SEL@  ( -- index )  _DLG-HND-W @ _DLG-O-SEL + @ ;
: _DLG-BCNT@  ( -- n )  _DLG-HND-W @ _DLG-O-BCNT + @ ;
: _DLG-SELECT  ( index -- )
    _DLG-HND-W @ _DLG-O-SEL + ! _DLG-HND-W @ WDG-DIRTY ;
: _DLG-CHOOSE  ( index -- )  _DLG-HND-W @ _DLG-O-RESULT + ! ;

: _DLG-KEY  ( code -- )
    DUP KEY-LEFT = IF
        DROP _DLG-SEL@ DUP 0> IF 1- _DLG-SELECT ELSE DROP THEN EXIT
    THEN
    DUP KEY-RIGHT = IF
        DROP _DLG-SEL@ 1+ DUP _DLG-BCNT@ < IF _DLG-SELECT ELSE DROP THEN EXIT
    THEN
    DUP KEY-TAB = IF DROP _DLG-SEL@ 1+ _DLG-BCNT@ MOD _DLG-SELECT EXIT THEN
    DUP KEY-ENTER = IF DROP _DLG-SEL@ _DLG-CHOOSE EXIT THEN
    KEY-ESC = IF
        _DLG-HND-W @ DLG-B-CANCEL _DLG-ROLE-INDEX
        DUP 0< IF DROP ELSE _DLG-CHOOSE THEN
    THEN ;

\ The button at a screen cell, or -1.
VARIABLE _DLG-HIT-W
VARIABLE _DLG-HIT-C
: _DLG-BUTTON-AT  ( row col widget -- index|-1 )
    DUP _DLG-HIT-W ! WDG-REGION >R
    R@ RGN-COL - _DLG-HIT-C !
    R@ RGN-ROW - R> RGN-H 2 - <> IF -1 EXIT THEN
    _DLG-HIT-W @ _DLG-O-BCNT + @ 0 ?DO
        _DLG-HIT-C @ _DLG-HIT-W @ I _DLG-BTN-COL -
        DUP 0< 0= SWAP _DLG-HIT-W @ I _DLG-BTN-WIDTH < AND IF
            I UNLOOP EXIT
        THEN
    LOOP -1 ;

: _DLG-MOUSE  ( event -- )
    DUP 8 + @ KEY-MOUSE-BUTTON KEY-MOUSE-LEFT <> IF DROP EXIT THEN
    16 + @ DUP 16 RSHIFT SWAP 0xFFFF AND _DLG-HND-W @ _DLG-BUTTON-AT
    DUP 0< IF DROP EXIT THEN
    DUP _DLG-SELECT _DLG-CHOOSE ;

\ While open, every event of the application is the dialog's.
: _DLG-HANDLE  ( event widget -- consumed? )
    _DLG-HND-W !
    DUP @ KEY-T-SPECIAL = IF 8 + @ _DLG-KEY -1 EXIT THEN
    DUP @ KEY-T-MOUSE = IF _DLG-MOUSE -1 EXIT THEN
    DROP -1 ;

\ =====================================================================
\ 7. Constructor
\ =====================================================================

VARIABLE _DLG-N-TA
VARIABLE _DLG-N-TU
VARIABLE _DLG-N-MA
VARIABLE _DLG-N-MU
VARIABLE _DLG-N-BT
VARIABLE _DLG-N-BC
VARIABLE _DLG-N-W
VARIABLE _DLG-N-P
VARIABLE _DLG-N-E
VARIABLE _DLG-N-D
VARIABLE _DLG-N-C

\ Buttons are valid when there is at least one, each has a label and
\ known roles, at most one is the default and at most one the cancel, and
\ no destructive button is the default.
: _DLG-BUTTONS?  ( -- flag )
    _DLG-N-BC @ 1 < IF FALSE EXIT THEN
    0 _DLG-N-D ! 0 _DLG-N-C !
    _DLG-N-BC @ 0 ?DO
        _DLG-N-BT @ I _DLG-BTN-LABEL NIP 0= IF FALSE UNLOOP EXIT THEN
        _DLG-N-BT @ I _DLG-BTN-ROLES
        DUP DLG-B-DEFAULT DLG-B-CANCEL OR DLG-B-DESTRUCTIVE OR INVERT AND IF
            DROP FALSE UNLOOP EXIT
        THEN
        DUP DLG-B-DEFAULT DLG-B-DESTRUCTIVE OR AND
            DLG-B-DEFAULT DLG-B-DESTRUCTIVE OR = IF
            DROP FALSE UNLOOP EXIT
        THEN
        DUP DLG-B-DEFAULT AND IF 1 _DLG-N-D +! THEN
        DLG-B-CANCEL AND IF 1 _DLG-N-C +! THEN
    LOOP
    _DLG-N-D @ 2 < _DLG-N-C @ 2 < AND ;

\ Copy A U to the dialog's text.
: _DLG-COPY  ( a u -- a' u )
    _DLG-N-P @ SWAP 2DUP 2>R MOVE 2R> DUP _DLG-N-P +! ;

\ DLG-NEW ( title-a title-u msg-a msg-u buttons count -- widget|0 )
\   A dialog holding its own copies of the title, the message and COUNT
\   buttons, each three cells: label-a label-u roles.  The default button
\   starts selected, else the first.  0 when the buttons are not valid or
\   memory is short.  It has no region until DLG-ASK opens it.
: DLG-NEW  ( title-a title-u msg-a msg-u buttons count -- widget|0 )
    _DLG-N-BC ! _DLG-N-BT ! _DLG-N-MU ! _DLG-N-MA ! _DLG-N-TU ! _DLG-N-TA !
    _DLG-BUTTONS? 0= IF 0 EXIT THEN
    _DLG-DESC-SIZE _DLG-N-BC @ _DLG-BTN-SIZE * + _DLG-N-TU @ + _DLG-N-MU @ +
    _DLG-N-BC @ 0 ?DO _DLG-N-BT @ I _DLG-BTN-LABEL NIP + LOOP
    ALLOCATE IF DROP 0 EXIT THEN _DLG-N-W !
    _DLG-N-W @ _DLG-DESC-SIZE 0 FILL
    _DLG-N-W @ WDG-T-DIALOG 0 ['] _DLG-DRAW ['] _DLG-HANDLE WDG-INIT
    _DLG-N-W @ _DLG-DESC-SIZE + DUP _DLG-N-W @ _DLG-O-BTNS + !
        _DLG-N-BC @ _DLG-BTN-SIZE * + _DLG-N-P !
    _DLG-N-BC @ _DLG-N-W @ _DLG-O-BCNT + !
    _DLG-N-TA @ _DLG-N-TU @ _DLG-COPY
        _DLG-N-W @ _DLG-O-TITLE-U + ! _DLG-N-W @ _DLG-O-TITLE-A + !
    _DLG-N-MA @ _DLG-N-MU @ _DLG-COPY
        _DLG-N-W @ _DLG-O-MSG-U + ! _DLG-N-W @ _DLG-O-MSG-A + !
    _DLG-N-BC @ 0 ?DO
        _DLG-N-W @ _DLG-O-BTNS + @ I _DLG-BTN-ADDR _DLG-N-E !
        _DLG-N-BT @ I _DLG-BTN-LABEL _DLG-COPY
            _DLG-N-E @ 8 + ! _DLG-N-E @ !
        _DLG-N-BT @ I _DLG-BTN-ROLES _DLG-N-E @ 16 + !
    LOOP
    -1 _DLG-N-W @ _DLG-O-RESULT + !
    _DLG-N-W @ DLG-B-DEFAULT _DLG-ROLE-INDEX 0 MAX
        _DLG-N-W @ _DLG-O-SEL + !
    _DLG-N-W @ ;

\ DLG-FREE ( widget -- )
\   Free a dialog and its region.  A dialog freed unanswered never calls
\   its asker back: its application is going away.
: DLG-FREE  ( widget -- )
    DUP WDG-REGION ?DUP IF RGN-FREE THEN FREE ;

\ =====================================================================
\ 8. Accessors
\ =====================================================================

\ DLG-SELECTED ( widget -- index )
: DLG-SELECTED  ( widget -- index )  _DLG-O-SEL + @ ;

\ DLG-BTN-COUNT ( widget -- n )
: DLG-BTN-COUNT  ( widget -- n )  _DLG-O-BCNT + @ ;

\ DLG-RESULT ( widget -- n )
\   -1 while open, then the chosen button.
: DLG-RESULT  ( widget -- n )  _DLG-O-RESULT + @ ;

\ =====================================================================
\ 9. Asking
\ =====================================================================

VARIABLE _DLG-A-XT
VARIABLE _DLG-A-CTX

\ DLG-ASK ( title-a title-u msg-a msg-u buttons count xt context -- ok? )
\   Open a dialog over the application that asks.  BUTTONS holds COUNT
\   records of three cells: label-a label-u roles.  Once a button is
\   chosen the dialog closes and XT, unless 0, runs ( index context -- )
\   in that application.  False when the application already shows a
\   dialog, the buttons are not valid, or memory is short.
: DLG-ASK  ( title-a title-u msg-a msg-u buttons count xt context -- ok? )
    _DLG-A-CTX ! _DLG-A-XT !
    _DLG-CELL-HOOK @ IF 2DROP 2DROP 2DROP FALSE EXIT THEN
    DLG-NEW ?DUP 0= IF FALSE EXIT THEN
    0 0 0 0 ['] RGN-NEW CATCH IF 2DROP 2DROP DLG-FREE FALSE EXIT THEN
    OVER _WDG-O-REGION + !
    _DLG-A-XT @ OVER _DLG-O-XT + !
    _DLG-A-CTX @ OVER _DLG-O-CTX + !
    _DLG-CELL-HOOK ! TRUE ;

CREATE _DLG-CONFIRM-BTNS 2 _DLG-BTN-SIZE * ALLOT

\ DLG-CONFIRM ( msg-a msg-u verb-a verb-u xt context -- ok? )
\   Ask before an action that cannot be undone, under the title Confirm:
\   VERB, destructive, and Cancel, the default.  XT, unless 0, runs
\   ( confirmed? context -- ) with true only for VERB.
: DLG-CONFIRM  ( msg-a msg-u verb-a verb-u xt context -- ok? )
    _DLG-A-CTX ! _DLG-A-XT !
    _DLG-CONFIRM-BTNS 8 + ! _DLG-CONFIRM-BTNS !
    DLG-B-DESTRUCTIVE _DLG-CONFIRM-BTNS 16 + !
    S" Cancel" _DLG-CONFIRM-BTNS _DLG-BTN-SIZE + 8 + !
        _DLG-CONFIRM-BTNS _DLG-BTN-SIZE + !
    DLG-B-DEFAULT DLG-B-CANCEL OR _DLG-CONFIRM-BTNS _DLG-BTN-SIZE + 16 + !
    S" Confirm" 2SWAP _DLG-CONFIRM-BTNS 2 _DLG-A-XT @ _DLG-A-CTX @ DLG-ASK
    DUP IF -1 _DLG-CELL-HOOK @ _DLG-O-CONFIRM + ! THEN ;

CREATE _DLG-OK-BTN _DLG-BTN-SIZE ALLOT

\ DLG-INFO ( msg-a msg-u -- ok? )
\   Tell the user something: an Info dialog with OK.
: DLG-INFO  ( msg-a msg-u -- ok? )
    S" OK" _DLG-OK-BTN 8 + ! _DLG-OK-BTN !
    DLG-B-DEFAULT DLG-B-CANCEL OR _DLG-OK-BTN 16 + !
    S" Info" 2SWAP _DLG-OK-BTN 1 0 0 DLG-ASK ;

\ =====================================================================
\ 10. Hosting
\ =====================================================================
\
\   A host calls these with an application's state current: DLG-HOST-EVENT
\   before the application sees an event, and DLG-HOST-PAINT after the
\   application has painted.

\ DLG-SHOWN ( -- widget|0 )
\   The dialog the current application shows.
: DLG-SHOWN  ( -- widget|0 )  _DLG-CELL-HOOK @ ;

\ Close an answered dialog: the host repaints what it covered, and the
\ asker is called back.  The dialog is freed first, so a callback that
\ throws leaks nothing and one that asks again finds no dialog shown.
VARIABLE _DLG-ANS-W
: _DLG-ANSWER  ( widget -- )
    _DLG-ANS-W !
    _DLG-ANS-W @ WDG-REGION >R
    R@ RGN-ROW R@ RGN-COL R@ RGN-H R> RGN-W
    2DUP * IF _DLG-DISMISS-HOOK ELSE 2DROP 2DROP THEN
    _DLG-ANS-W @ _DLG-O-RESULT + @
    _DLG-ANS-W @ _DLG-O-CONFIRM + @ IF 0= THEN
    _DLG-ANS-W @ _DLG-O-CTX + @
    _DLG-ANS-W @ _DLG-O-XT + @
    _DLG-ANS-W @ DLG-FREE
    ?DUP IF EXECUTE ELSE 2DROP THEN ;

\ DLG-HOST-EVENT ( event -- handled? )
\   Give EVENT to the dialog the current application shows, and once a
\   button is chosen close it and call its asker back.  False when the
\   application shows no dialog.
: DLG-HOST-EVENT  ( event -- handled? )
    _DLG-CELL-HOOK @ ?DUP 0= IF DROP FALSE EXIT THEN
    TUCK WDG-HANDLE DROP
    DUP DLG-RESULT 0< IF DROP TRUE EXIT THEN
    0 _DLG-CELL-HOOK ! _DLG-ANSWER TRUE ;

\ DLG-HOST-PAINT ( -- )
\   Paint the dialog the current application shows over it, centred in
\   the host's bounds, keeping the drawing region the caller had.
: DLG-HOST-PAINT  ( -- )
    _DLG-CELL-HOOK @ ?DUP 0= IF EXIT THEN
    DUP _DLG-LAYOUT DUP WDG-DIRTY
    RGN-CURRENT >R ['] WDG-DRAW CATCH R> RGN-RESTORE
    ?DUP IF NIP THROW THEN ;

\ DLG-DISCARD ( -- )
\   Free the dialog the current application shows, unanswered: the
\   application is going away.
: DLG-DISCARD  ( -- )
    _DLG-CELL-HOOK @ ?DUP IF DLG-FREE 0 _DLG-CELL-HOOK ! THEN ;

\ =====================================================================
\ 11. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _dlg-guard

' DLG-NEW         CONSTANT _dlg-new-xt
' DLG-SELECTED    CONSTANT _dlg-selected-xt
' DLG-BTN-COUNT   CONSTANT _dlg-btncnt-xt
' DLG-RESULT      CONSTANT _dlg-result-xt
' DLG-FREE        CONSTANT _dlg-free-xt
' DLG-ASK         CONSTANT _dlg-ask-xt
' DLG-CONFIRM     CONSTANT _dlg-confirm-xt
' DLG-INFO        CONSTANT _dlg-info-xt
' DLG-SHOWN       CONSTANT _dlg-shown-xt
' DLG-HOST-EVENT  CONSTANT _dlg-host-event-xt
' DLG-HOST-PAINT  CONSTANT _dlg-host-paint-xt
' DLG-DISCARD     CONSTANT _dlg-discard-xt

: DLG-NEW         _dlg-new-xt       _dlg-guard WITH-GUARD ;
: DLG-SELECTED    _dlg-selected-xt  _dlg-guard WITH-GUARD ;
: DLG-BTN-COUNT   _dlg-btncnt-xt    _dlg-guard WITH-GUARD ;
: DLG-RESULT      _dlg-result-xt    _dlg-guard WITH-GUARD ;
: DLG-FREE        _dlg-free-xt      _dlg-guard WITH-GUARD ;
: DLG-ASK         _dlg-ask-xt       _dlg-guard WITH-GUARD ;
: DLG-CONFIRM     _dlg-confirm-xt   _dlg-guard WITH-GUARD ;
: DLG-INFO        _dlg-info-xt      _dlg-guard WITH-GUARD ;
: DLG-SHOWN       _dlg-shown-xt     _dlg-guard WITH-GUARD ;
\ Hosting calls back into the application and paints through host hooks,
\ so it never holds the dialog guard.  Call it only on the UI owner core.
: DLG-HOST-EVENT  _dlg-host-event-xt EXECUTE ;
: DLG-HOST-PAINT  _dlg-host-paint-xt EXECUTE ;
: DLG-DISCARD     _dlg-discard-xt   _dlg-guard WITH-GUARD ;
[THEN] [THEN]
