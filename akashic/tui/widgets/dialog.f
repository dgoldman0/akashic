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
\  The message is untrusted text: paragraphs, each with a look, broken
\  into lines by the shared line rule (APT-1-TEXT Section 12) with their
\  direction controls ignored.  A message taller than the dialog scrolls,
\  and while more of it lies below, the last row in view says so.
\  DLG-ASK-DETAIL asks with several paragraphs in a dialog that takes the
\  host's whole area, for a request to read before answering it.
\
\  Left and Right move between the buttons and Tab cycles them; Enter
\  chooses the selected button and Escape the cancel button; a button's
\  function key chooses it, as a press on it does.  Up, Down, PgUp, PgDn,
\  Home, End and the wheel scroll the message.  The application's other
\  events are swallowed while the dialog is open.
\
\  Each button has roles: DLG-B-DEFAULT is selected when the dialog
\  opens, DLG-B-CANCEL answers Escape, DLG-B-DESTRUCTIVE marks an action
\  that cannot be undone, which is never the default, and
\  DLG-B-READ-FIRST keeps the button unavailable until a paint has shown
\  the message's last line.
\
\  Dialog descriptor (200 bytes, then its button records, its paragraph
\  records and its text):
\    +0..+39  widget header  (type = WDG-T-DIALOG; the region is its own)
\    +40  title-a       +48  title-u
\    +56  paras         PARA-COUNT records of three cells: text-a text-u
\                       look
\    +64  para-count
\    +72  buttons       BTN-COUNT records of four cells: label-a label-u
\                       roles key
\    +80  btn-count
\    +88  selected      the button Enter chooses
\    +96  result        -1 while open, then the chosen button
\    +104 answer-xt     ( index context -- ), or 0
\    +112 context
\    +120 confirm?      the answer is a flag, true for the first button
\    +128 instance      its identity for as long as it lives
\    +136 revision      0 until laid out, then new whenever what it shows
\                       changes: its size, or the message rows in view
\    +144 severity      a status field's: neutral, info, success, warning,
\                       error
\    +152 detail?       it takes the host's whole area
\    +160 top           the first message row in view
\    +168 rows          the message's rows at its width; 0 when a paragraph
\                       cannot be laid out
\    +176 view          the message rows in view; while the message runs
\                       past them, the row after them says so
\    +184 read?         a paint has shown the message's last row
\    +192 measure       the width the message is broken at
\
\  The title, paragraphs and labels are the dialog's own copies, so an
\  asker may pass text it reuses.  Titles and labels are measured in
\  cells, and the title is clipped by cells when too wide.
\
\  DLG-MODEL-CAPTURE writes the dialog its last paint laid out as a
\  canonical UDLG model, so a renderer can show it as a dialog.
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
REQUIRE ../../text/cell-width.f
REQUIRE ../../text/text-lines.f
REQUIRE ../../text/bidi.f
REQUIRE ../dialog-model.f
REQUIRE ../../utils/memory-span.f

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
\ 2. Descriptor layout, button roles and looks
\ =====================================================================

40  CONSTANT _DLG-O-TITLE-A
48  CONSTANT _DLG-O-TITLE-U
56  CONSTANT _DLG-O-PARAS
64  CONSTANT _DLG-O-PCNT
72  CONSTANT _DLG-O-BTNS
80  CONSTANT _DLG-O-BCNT
88  CONSTANT _DLG-O-SEL
96  CONSTANT _DLG-O-RESULT
104 CONSTANT _DLG-O-XT
112 CONSTANT _DLG-O-CTX
120 CONSTANT _DLG-O-CONFIRM
128 CONSTANT _DLG-O-INSTANCE
136 CONSTANT _DLG-O-REVISION
144 CONSTANT _DLG-O-SEVERITY
152 CONSTANT _DLG-O-DETAIL
160 CONSTANT _DLG-O-TOP
168 CONSTANT _DLG-O-ROWS
176 CONSTANT _DLG-O-VIEW
184 CONSTANT _DLG-O-READ
192 CONSTANT _DLG-O-MW

200 CONSTANT _DLG-DESC-SIZE
32  CONSTANT _DLG-BTN-SIZE
24  CONSTANT _DLG-PARA-SIZE

1 CONSTANT DLG-B-DEFAULT
2 CONSTANT DLG-B-CANCEL
4 CONSTANT DLG-B-DESTRUCTIVE
8 CONSTANT DLG-B-READ-FIRST

\ How a paragraph looks: ordinary text, a label naming what follows, an
\ exact value, what is wrong, or a heading.
0 CONSTANT DLG-LOOK-TEXT
1 CONSTANT DLG-LOOK-LABEL
2 CONSTANT DLG-LOOK-VALUE
3 CONSTANT DLG-LOOK-FAULT
4 CONSTANT DLG-LOOK-HEADING

\ Instances and revisions only ever grow, so neither repeats across
\ dialogs.
VARIABLE _DLG-INSTANCES
0 _DLG-INSTANCES !
VARIABLE _DLG-REVISIONS
0 _DLG-REVISIONS !

\ =====================================================================
\ 3. Internal helpers
\ =====================================================================

: _DLG-BTN-ADDR  ( btns index -- addr )  _DLG-BTN-SIZE * + ;
: _DLG-BTN-LABEL  ( btns index -- a u )  _DLG-BTN-ADDR DUP @ SWAP 8 + @ ;
: _DLG-BTN-ROLES  ( btns index -- roles )  _DLG-BTN-ADDR 16 + @ ;
: _DLG-BTN-KEY  ( btns index -- key )  _DLG-BTN-ADDR 24 + @ ;
: _DLG-PARA  ( widget index -- a u look )
    _DLG-PARA-SIZE * SWAP _DLG-O-PARAS + @ +
    DUP @ OVER 8 + @ ROT 16 + @ ;
: _DLG-FLOOR1  ( n -- n' )  DUP 1 < IF DROP 1 THEN ;
: _DLG-FLOOR0  ( n -- n' )  DUP 0< IF DROP 0 THEN ;

\ The first button having ROLE, or -1.
: _DLG-ROLE-INDEX  ( widget role -- index|-1 )
    OVER _DLG-O-BCNT + @ 0 ?DO
        OVER _DLG-O-BTNS + @ I _DLG-BTN-ROLES OVER AND IF
            2DROP I UNLOOP EXIT
        THEN
    LOOP 2DROP -1 ;

\ A button's key is none, 0, or a function key; it shows that key's name.
: _DLG-KEY?  ( key -- flag )  DUP 0= SWAP KEY-F1 KEY-F12 1+ WITHIN OR ;
: _DLG-KEY-NAME  ( key -- a u )
    CASE
        KEY-F1 OF S" F1" ENDOF    KEY-F2 OF S" F2" ENDOF
        KEY-F3 OF S" F3" ENDOF    KEY-F4 OF S" F4" ENDOF
        KEY-F5 OF S" F5" ENDOF    KEY-F6 OF S" F6" ENDOF
        KEY-F7 OF S" F7" ENDOF    KEY-F8 OF S" F8" ENDOF
        KEY-F9 OF S" F9" ENDOF    KEY-F10 OF S" F10" ENDOF
        KEY-F11 OF S" F11" ENDOF  KEY-F12 OF S" F12" ENDOF
        >R 0 0 R>
    ENDCASE ;

\ A button is available unless it waits for the message to be read.
: _DLG-AVAILABLE?  ( widget index -- flag )
    OVER _DLG-O-BTNS + @ SWAP _DLG-BTN-ROLES DLG-B-READ-FIRST AND 0=
    SWAP _DLG-O-READ + @ OR ;

\ The button row: each button is "[ ", its key's name and a space when it
\ has a key, its label and " ]", one cell apart, the row centred inside
\ the box.  The cells all the buttons take, and where one begins and how
\ wide it is, from the dialog's left edge.
: _DLG-BTN-WIDTH  ( widget index -- cells )
    SWAP _DLG-O-BTNS + @ SWAP 2DUP _DLG-BTN-LABEL CW-SWIDTH 4 + >R
    _DLG-BTN-KEY _DLG-KEY-NAME NIP DUP IF 1+ THEN R> + ;

VARIABLE _DLG-BS-W
: _DLG-BTN-SPAN  ( widget -- cells )
    DUP _DLG-BS-W ! _DLG-O-BCNT + @ DUP 1- 0 MAX
    SWAP 0 ?DO _DLG-BS-W @ I _DLG-BTN-WIDTH + LOOP ;

VARIABLE _DLG-BC-W
: _DLG-BTN-COL  ( widget index -- col )
    SWAP DUP _DLG-BC-W !
    DUP WDG-REGION RGN-W 2 - SWAP _DLG-BTN-SPAN - _DLG-FLOOR0 2 / 1+
    SWAP 0 ?DO _DLG-BC-W @ I _DLG-BTN-WIDTH 1+ + LOOP ;

\ =====================================================================
\ 4. The message's lines
\ =====================================================================
\
\   One cursor breaks every paragraph, as untrusted text in its own
\   direction, at the width the dialog gives its message.

CREATE _DLG-TLN TLINES-SIZE ALLOT  _DLG-TLN TLINES-INIT

: _DLG-TLN-START  ( a u width -- line? )
    >R TROW-F-UNTRUSTED BIDI-AUTO R> _DLG-TLN TLINES-START ;

\ The rows the message takes broken at WIDTH, or 0 when a paragraph
\ cannot be laid out.
VARIABLE _DLG-R-W
VARIABLE _DLG-R-WD
VARIABLE _DLG-R-N

: _DLG-ROWS  ( widget width -- rows )
    _DLG-R-WD ! _DLG-R-W ! 0 _DLG-R-N !
    _DLG-R-W @ _DLG-O-PCNT + @ 0 ?DO
        _DLG-R-W @ I _DLG-PARA DROP
        TROW-F-UNTRUSTED BIDI-AUTO _DLG-R-WD @ _DLG-TLN TLINES-COUNT
        0= IF DROP 0 UNLOOP EXIT THEN _DLG-R-N +!
    LOOP _DLG-R-N @ ;

\ The widest line, in cells, the message has broken at WIDTH.
: _DLG-WIDEST  ( widget width -- cells )
    _DLG-R-WD ! _DLG-R-W ! 0 _DLG-R-N !
    _DLG-R-W @ _DLG-O-PCNT + @ 0 ?DO
        _DLG-R-W @ I _DLG-PARA DROP _DLG-R-WD @ _DLG-TLN-START
        BEGIN WHILE
            _DLG-TLN TLINES-WIDTH _DLG-R-N @ MAX _DLG-R-N !
            _DLG-TLN TLINES-NEXT
        REPEAT
    LOOP _DLG-R-N @ ;

\ Run XT ( index -- ) on each message line in view, INDEX counting from
\ the view's first row, with the cursor reading the line and LOOK the
\ look of its paragraph.  False when a paragraph cannot be laid out.
VARIABLE _DLG-V-W
VARIABLE _DLG-V-XT
VARIABLE _DLG-V-N
VARIABLE _DLG-V-END
VARIABLE _DLG-V-LOOK

: _DLG-VISIBLE  ( widget xt -- ok? )
    _DLG-V-XT ! _DLG-V-W ! 0 _DLG-V-N !
    _DLG-V-W @ DUP _DLG-O-TOP + @ SWAP _DLG-O-VIEW + @ + _DLG-V-END !
    _DLG-V-W @ _DLG-O-PCNT + @ 0 ?DO
        _DLG-V-N @ _DLG-V-END @ < 0= IF -1 UNLOOP EXIT THEN
        _DLG-V-W @ I _DLG-PARA _DLG-V-LOOK !
        _DLG-V-W @ _DLG-O-MW + @ _DLG-TLN-START
        BEGIN WHILE
            _DLG-V-N @ _DLG-V-W @ _DLG-O-TOP + @ -
            DUP 0< IF DROP ELSE _DLG-V-XT @ EXECUTE THEN
            1 _DLG-V-N +!
            _DLG-V-N @ _DLG-V-END @ < 0= IF -1 UNLOOP EXIT THEN
            _DLG-TLN TLINES-NEXT
        REPEAT
        _DLG-TLN TLINES-FAILED? IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

\ The message runs past the rows in view.
: _DLG-MORE?  ( widget -- flag )
    DUP _DLG-O-TOP + @ OVER _DLG-O-VIEW + @ + SWAP _DLG-O-ROWS + @ < ;

\ What the row after the view says while the message runs past it.
: _DLG-MORE$  ( -- a u )  S" PgDn: more below" ;

\ =====================================================================
\ 5. Layout
\ =====================================================================
\
\   A plain dialog is sized to its title, its widest message line and
\   its buttons, between 20 and 60 cells wide, and to its message's rows;
\   a detail dialog takes the host's area.  Either is at most two less
\   than the bounds each way, and centred in them.  A message taller than
\   its rows keeps the last of them to say more lies below.  Laid out
\   again at each paint, so it follows the application's region; a paint
\   that shows the message's last row lets its read-first buttons be
\   chosen.

VARIABLE _DLG-L-W
VARIABLE _DLG-L-BR
VARIABLE _DLG-L-BC
VARIABLE _DLG-L-BH
VARIABLE _DLG-L-BW
VARIABLE _DLG-L-WD
VARIABLE _DLG-L-HT

: _DLG-SIZE-PLAIN  ( -- )
    _DLG-L-W @ DUP _DLG-O-TITLE-A + @ SWAP _DLG-O-TITLE-U + @ CW-SWIDTH 4 +
    _DLG-L-W @ _DLG-L-BW @ 6 - _DLG-FLOOR1 56 MIN _DLG-WIDEST 4 + MAX
    _DLG-L-W @ _DLG-BTN-SPAN 4 + MAX
    20 MAX 60 MIN _DLG-L-BW @ 2 - _DLG-FLOOR1 MIN _DLG-L-WD !
    _DLG-L-W @ _DLG-L-WD @ 4 - _DLG-FLOOR1 _DLG-ROWS _DLG-FLOOR1
    5 + _DLG-L-BH @ 2 - _DLG-FLOOR1 MIN _DLG-L-HT ! ;

: _DLG-SIZE-DETAIL  ( -- )
    _DLG-L-BW @ 2 - _DLG-FLOOR1 _DLG-L-WD !
    _DLG-L-BH @ 2 - _DLG-FLOOR1 _DLG-L-HT ! ;

\ The message broken inside the box, the rows in view, the first of them
\ kept inside the message, and whether the last row has been shown.  The
\ message has the rows between the blank rows under the top and over the
\ buttons, or the lower blank row when that is all there is.  A box of
\ fewer than five rows has no row for it, so its message is never read.
VARIABLE _DLG-L-ROWS
VARIABLE _DLG-L-VIEW
: _DLG-MESSAGE-LAYOUT  ( -- )
    _DLG-L-WD @ 4 - _DLG-FLOOR1 DUP _DLG-L-W @ _DLG-O-MW + !
    _DLG-L-W @ SWAP _DLG-ROWS DUP _DLG-L-ROWS ! _DLG-L-W @ _DLG-O-ROWS + !
    _DLG-L-HT @ 5 < IF 0 ELSE _DLG-L-HT @ 5 - _DLG-FLOOR1 THEN _DLG-L-VIEW !
    _DLG-L-ROWS @ _DLG-L-VIEW @ > _DLG-L-VIEW @ 1 > AND IF -1 _DLG-L-VIEW +! THEN
    _DLG-L-VIEW @ _DLG-L-W @ _DLG-O-VIEW + !
    _DLG-L-ROWS @ _DLG-L-VIEW @ - _DLG-FLOOR0
        _DLG-L-W @ _DLG-O-TOP + @ MIN _DLG-L-W @ _DLG-O-TOP + !
    _DLG-L-ROWS @ 0<> _DLG-L-VIEW @ 0<> AND IF
        _DLG-L-W @ _DLG-O-TOP + @ _DLG-L-VIEW @ + _DLG-L-ROWS @ < 0= IF
            -1 _DLG-L-W @ _DLG-O-READ + !
        THEN
    THEN ;

: _DLG-LAYOUT  ( widget -- )
    _DLG-L-W !
    _DLG-BOUNDS-HOOK _DLG-L-BW ! _DLG-L-BH ! _DLG-L-BC ! _DLG-L-BR !
    _DLG-L-W @ _DLG-O-DETAIL + @ IF _DLG-SIZE-DETAIL ELSE _DLG-SIZE-PLAIN THEN
    _DLG-MESSAGE-LAYOUT
    _DLG-L-BH @ _DLG-L-HT @ - 2 / _DLG-FLOOR0 _DLG-L-BR @ +
    _DLG-L-BW @ _DLG-L-WD @ - 2 / _DLG-FLOOR0 _DLG-L-BC @ +
    _DLG-L-HT @ _DLG-L-WD @ _DLG-L-W @ WDG-REGION RGN-BOUNDS! ;

\ =====================================================================
\ 6. Draw
\ =====================================================================

VARIABLE _DLG-DRW-W       \ widget
VARIABLE _DLG-DRW-RW      \ region width
VARIABLE _DLG-DRW-RH      \ region height
VARIABLE _DLG-DRW-COL     \ current column for buttons
VARIABLE _DLG-DRW-BROW    \ button row

\ Layout: row 0 = box top, row 1 = blank, rows 2 onward = the message,
\ row h-3 = blank, row h-2 = buttons, row h-1 = box bottom.

\ The dialog's palette, white on blue, and its looks.
: _DLG-PLAIN  ( -- )  15 24 0 DRW-STYLE! ;
: _DLG-LOOK!  ( look -- )
    CASE
        DLG-LOOK-LABEL OF 229 24 1 DRW-STYLE! ENDOF
        DLG-LOOK-VALUE OF 159 24 0 DRW-STYLE! ENDOF
        DLG-LOOK-FAULT OF 217 24 1 DRW-STYLE! ENDOF
        DLG-LOOK-HEADING OF 15 24 1 DRW-STYLE! ENDOF
        _DLG-PLAIN
    ENDCASE ;

\ A message line in view, on row 2 + INDEX from column 2: a laid-out row
\ starting at the right edge when it reads right to left, else its bytes.
: _DLG-DRAW-LINE  ( index -- )
    2 + _DLG-V-LOOK @ _DLG-LOOK!
    _DLG-TLN TLINES-ROW ?DUP IF
        SWAP 2
        _DLG-TLN TLINES-RTL? IF
            _DLG-DRW-W @ _DLG-O-MW + @ _DLG-TLN TLINES-WIDTH - +
        THEN
        DRW-TROW EXIT
    THEN
    _DLG-TLN TLINES-BYTES ROT 2 DRW-TEXT ;

: _DLG-DRAW-MORE  ( -- )
    _DLG-DRW-W @ _DLG-MORE? 0= IF EXIT THEN
    _DLG-DRW-W @ _DLG-O-VIEW + @ 0= IF EXIT THEN
    244 24 0 DRW-STYLE!
    _DLG-MORE$ _DLG-DRW-W @ _DLG-O-VIEW + @ 2 + 2 DRW-TEXT ;

\ --- Buttons: the selected one reversed, one not yet available dim ---

: _DLG-DRAW-BUTTONS  ( -- )
    _DLG-DRW-RH @ 2 - _DLG-DRW-BROW !
    _DLG-DRW-W @ _DLG-O-BCNT + @ 0 ?DO
        _DLG-DRW-W @ I _DLG-AVAILABLE? IF _DLG-PLAIN ELSE 248 24 0 DRW-STYLE! THEN
        I _DLG-DRW-W @ _DLG-O-SEL + @ = IF CELL-A-REVERSE DRW-ATTR! THEN
        _DLG-DRW-W @ I _DLG-BTN-COL _DLG-DRW-COL !
        91 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR
        32 _DLG-DRW-BROW @ _DLG-DRW-COL @ 1+ DRW-CHAR
        2 _DLG-DRW-COL +!
        _DLG-DRW-W @ _DLG-O-BTNS + @ I _DLG-BTN-KEY _DLG-KEY-NAME DUP IF
            2DUP _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-TEXT
            NIP _DLG-DRW-COL +!
            32 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR 1 _DLG-DRW-COL +!
        ELSE 2DROP THEN
        _DLG-DRW-W @ _DLG-O-BTNS + @ I _DLG-BTN-LABEL
            2DUP _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-TEXT
            CW-SWIDTH _DLG-DRW-COL +!
        32 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR
        93 _DLG-DRW-BROW @ _DLG-DRW-COL @ 1+ DRW-CHAR
    LOOP _DLG-PLAIN ;

: _DLG-DRAW-BODY  ( widget -- )
    \ Its chrome must stay legible whatever style the application left.
    \ Preserve that style for the application.
    _DRW-FG @ _DRW-BG @ _DRW-ATTRS @ >R >R >R
    _DLG-PLAIN
    _DLG-DRW-W !
    _DLG-DRW-W @ WDG-REGION RGN-W _DLG-DRW-RW !
    _DLG-DRW-W @ WDG-REGION RGN-H _DLG-DRW-RH !
    BOX-SINGLE _DLG-DRW-W @ DUP _DLG-O-TITLE-A + @ SWAP _DLG-O-TITLE-U + @
        0 0 _DLG-DRW-RH @ _DLG-DRW-RW @ BOX-DRAW-TITLED
    0 0 _DLG-DRW-RH @ _DLG-DRW-RW @ BOX-SHADOW
    32 1 1 _DLG-DRW-RH @ 2 - _DLG-DRW-RW @ 2 - DRW-FILL-RECT
    _DLG-DRW-W @ ['] _DLG-DRAW-LINE _DLG-VISIBLE DROP
    _DLG-DRAW-MORE
    _DLG-DRAW-BUTTONS
    R> DRW-FG! R> DRW-BG! R> DRW-ATTR! ;

: _DLG-DRAW  ( widget -- )
    \ A dialog is foreground paint over its application.  Mark every
    \ write with final-writer provenance so an optional retained
    \ projection cannot paint stale semantics above it.
    ['] _DLG-DRAW-BODY DRW-OVERLAY ;

\ =====================================================================
\ 7. Handle
\ =====================================================================

VARIABLE _DLG-HND-W

: _DLG-SEL@  ( -- index )  _DLG-HND-W @ _DLG-O-SEL + @ ;
: _DLG-BCNT@  ( -- n )  _DLG-HND-W @ _DLG-O-BCNT + @ ;
: _DLG-SELECT  ( index -- )
    _DLG-HND-W @ _DLG-O-SEL + ! _DLG-HND-W @ WDG-DIRTY ;
\ Only an available button can be chosen.
: _DLG-CHOOSE  ( index -- )
    _DLG-HND-W @ OVER _DLG-AVAILABLE? IF
        _DLG-HND-W @ _DLG-O-RESULT + !
    ELSE DROP THEN ;

\ Move the message by ROWS, within what it has.  The rows in view are
\ new content.
: _DLG-SCROLL  ( rows -- )
    _DLG-HND-W @ _DLG-O-TOP + @ +
    _DLG-HND-W @ DUP _DLG-O-ROWS + @ SWAP _DLG-O-VIEW + @ -
    2DUP > IF NIP ELSE DROP THEN _DLG-FLOOR0
    DUP _DLG-HND-W @ _DLG-O-TOP + @ = IF DROP EXIT THEN
    _DLG-HND-W @ _DLG-O-TOP + !
    1 _DLG-REVISIONS +! _DLG-REVISIONS @ _DLG-HND-W @ _DLG-O-REVISION + !
    _DLG-HND-W @ WDG-DIRTY ;

: _DLG-PAGE  ( -- rows )  _DLG-HND-W @ _DLG-O-VIEW + @ 1- _DLG-FLOOR1 ;

\ The button a function key chooses, or -1.
: _DLG-KEY-INDEX  ( code -- index|-1 )
    DUP 0= IF DROP -1 EXIT THEN
    _DLG-BCNT@ 0 ?DO
        _DLG-HND-W @ _DLG-O-BTNS + @ I _DLG-BTN-KEY OVER = IF
            DROP I UNLOOP EXIT
        THEN
    LOOP DROP -1 ;

: _DLG-KEY  ( code -- )
    DUP KEY-LEFT = IF
        DROP _DLG-SEL@ DUP 0> IF 1- _DLG-SELECT ELSE DROP THEN EXIT
    THEN
    DUP KEY-RIGHT = IF
        DROP _DLG-SEL@ 1+ DUP _DLG-BCNT@ < IF _DLG-SELECT ELSE DROP THEN EXIT
    THEN
    DUP KEY-TAB = IF DROP _DLG-SEL@ 1+ _DLG-BCNT@ MOD _DLG-SELECT EXIT THEN
    DUP KEY-ENTER = IF DROP _DLG-SEL@ _DLG-CHOOSE EXIT THEN
    DUP KEY-UP = IF DROP -1 _DLG-SCROLL EXIT THEN
    DUP KEY-DOWN = IF DROP 1 _DLG-SCROLL EXIT THEN
    DUP KEY-PGUP = IF DROP _DLG-PAGE NEGATE _DLG-SCROLL EXIT THEN
    DUP KEY-PGDN = IF DROP _DLG-PAGE _DLG-SCROLL EXIT THEN
    DUP KEY-HOME = IF
        DROP _DLG-HND-W @ _DLG-O-TOP + @ NEGATE _DLG-SCROLL EXIT
    THEN
    DUP KEY-END = IF DROP _DLG-HND-W @ _DLG-O-ROWS + @ _DLG-SCROLL EXIT THEN
    DUP KEY-ESC = IF
        DROP _DLG-HND-W @ DLG-B-CANCEL _DLG-ROLE-INDEX
        DUP 0< IF DROP ELSE _DLG-CHOOSE THEN EXIT
    THEN
    _DLG-KEY-INDEX DUP 0< IF DROP ELSE _DLG-CHOOSE THEN ;

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
    DUP 8 + @ KEY-MOUSE-BUTTON
    DUP KEY-MOUSE-SCROLL-UP = IF 2DROP -3 _DLG-SCROLL EXIT THEN
    DUP KEY-MOUSE-SCROLL-DN = IF 2DROP 3 _DLG-SCROLL EXIT THEN
    KEY-MOUSE-LEFT <> IF DROP EXIT THEN
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
\ 8. Constructor
\ =====================================================================

VARIABLE _DLG-N-TA
VARIABLE _DLG-N-TU
VARIABLE _DLG-N-PR
VARIABLE _DLG-N-PC
VARIABLE _DLG-N-BT
VARIABLE _DLG-N-BC
VARIABLE _DLG-N-W
VARIABLE _DLG-N-P
VARIABLE _DLG-N-E
VARIABLE _DLG-N-D
VARIABLE _DLG-N-C

\ Buttons are valid when there is at least one, each has a label, known
\ roles and no key or a function key no other has, at most one is the
\ default and at most one the cancel, and no destructive button is the
\ default.
: _DLG-BUTTONS?  ( -- flag )
    _DLG-N-BC @ 1 < IF FALSE EXIT THEN
    0 _DLG-N-D ! 0 _DLG-N-C !
    _DLG-N-BC @ 0 ?DO
        _DLG-N-BT @ I _DLG-BTN-LABEL NIP 0= IF FALSE UNLOOP EXIT THEN
        _DLG-N-BT @ I _DLG-BTN-KEY DUP _DLG-KEY? 0= IF DROP FALSE UNLOOP EXIT THEN
        ?DUP IF
            I 0 ?DO
                DUP _DLG-N-BT @ I _DLG-BTN-KEY = IF
                    DROP FALSE UNLOOP UNLOOP EXIT
                THEN
            LOOP DROP
        THEN
        _DLG-N-BT @ I _DLG-BTN-ROLES
        DUP DLG-B-DEFAULT DLG-B-CANCEL OR DLG-B-DESTRUCTIVE OR
            DLG-B-READ-FIRST OR INVERT AND IF
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

\ Paragraphs are valid when there is at least one, each with a known look.
: _DLG-PARAS?  ( -- flag )
    _DLG-N-PC @ 1 < IF FALSE EXIT THEN
    _DLG-N-PC @ 0 ?DO
        _DLG-N-PR @ I _DLG-PARA-SIZE * + 16 + @ DLG-LOOK-HEADING U> IF
            FALSE UNLOOP EXIT
        THEN
    LOOP TRUE ;

\ Copy A U to the dialog's text.
: _DLG-COPY  ( a u -- a' u )
    _DLG-N-P @ SWAP 2DUP 2>R MOVE 2R> DUP _DLG-N-P +! ;

\ A dialog holding its own copies of the title, PCOUNT paragraphs, each
\ three cells: text-a text-u look, and BCOUNT buttons, each four cells:
\ label-a label-u roles key.  The default button starts selected, else
\ the first.  0 when the paragraphs or buttons are not valid or memory is
\ short.  It has no region until it is opened.
: _DLG-NEW  ( title-a title-u paras pcount buttons bcount -- widget|0 )
    _DLG-N-BC ! _DLG-N-BT ! _DLG-N-PC ! _DLG-N-PR ! _DLG-N-TU ! _DLG-N-TA !
    _DLG-BUTTONS? 0= IF 0 EXIT THEN
    _DLG-PARAS? 0= IF 0 EXIT THEN
    _DLG-DESC-SIZE _DLG-N-BC @ _DLG-BTN-SIZE * +
    _DLG-N-PC @ _DLG-PARA-SIZE * + _DLG-N-TU @ +
    _DLG-N-PC @ 0 ?DO _DLG-N-PR @ I _DLG-PARA-SIZE * + 8 + @ + LOOP
    _DLG-N-BC @ 0 ?DO _DLG-N-BT @ I _DLG-BTN-LABEL NIP + LOOP
    ALLOCATE IF DROP 0 EXIT THEN _DLG-N-W !
    _DLG-N-W @ _DLG-DESC-SIZE 0 FILL
    _DLG-N-W @ WDG-T-DIALOG 0 ['] _DLG-DRAW ['] _DLG-HANDLE WDG-INIT
    _DLG-N-W @ _DLG-DESC-SIZE + DUP _DLG-N-W @ _DLG-O-BTNS + !
        _DLG-N-BC @ _DLG-BTN-SIZE * + DUP _DLG-N-W @ _DLG-O-PARAS + !
        _DLG-N-PC @ _DLG-PARA-SIZE * + _DLG-N-P !
    _DLG-N-BC @ _DLG-N-W @ _DLG-O-BCNT + !
    _DLG-N-PC @ _DLG-N-W @ _DLG-O-PCNT + !
    _DLG-N-TA @ _DLG-N-TU @ _DLG-COPY
        _DLG-N-W @ _DLG-O-TITLE-U + ! _DLG-N-W @ _DLG-O-TITLE-A + !
    _DLG-N-PC @ 0 ?DO
        _DLG-N-W @ _DLG-O-PARAS + @ I _DLG-PARA-SIZE * + _DLG-N-E !
        _DLG-N-PR @ I _DLG-PARA-SIZE * + DUP @ SWAP 8 + @ _DLG-COPY
            _DLG-N-E @ 8 + ! _DLG-N-E @ !
        _DLG-N-PR @ I _DLG-PARA-SIZE * + 16 + @ _DLG-N-E @ 16 + !
    LOOP
    _DLG-N-BC @ 0 ?DO
        _DLG-N-W @ _DLG-O-BTNS + @ I _DLG-BTN-ADDR _DLG-N-E !
        _DLG-N-BT @ I _DLG-BTN-LABEL _DLG-COPY
            _DLG-N-E @ 8 + ! _DLG-N-E @ !
        _DLG-N-BT @ I _DLG-BTN-ROLES _DLG-N-E @ 16 + !
        _DLG-N-BT @ I _DLG-BTN-KEY _DLG-N-E @ 24 + !
    LOOP
    -1 _DLG-N-W @ _DLG-O-RESULT + !
    _DLG-N-W @ DLG-B-DEFAULT _DLG-ROLE-INDEX _DLG-FLOOR0
        _DLG-N-W @ _DLG-O-SEL + !
    1 _DLG-INSTANCES +! _DLG-INSTANCES @ _DLG-N-W @ _DLG-O-INSTANCE + !
    _DLG-N-W @ ;

\ DLG-FREE ( widget -- )
\   Free a dialog and its region.  A dialog freed unanswered never calls
\   its asker back: its application is going away.
: DLG-FREE  ( widget -- )
    DUP WDG-REGION ?DUP IF RGN-FREE THEN FREE ;

\ =====================================================================
\ 9. Accessors
\ =====================================================================

\ DLG-SELECTED ( widget -- index )
: DLG-SELECTED  ( widget -- index )  _DLG-O-SEL + @ ;

\ DLG-BTN-COUNT ( widget -- n )
: DLG-BTN-COUNT  ( widget -- n )  _DLG-O-BCNT + @ ;

\ DLG-RESULT ( widget -- n )
\   -1 while open, then the chosen button.
: DLG-RESULT  ( widget -- n )  _DLG-O-RESULT + @ ;

\ DLG-PARAGRAPH ( widget index -- a u )
\   The dialog's copy of a paragraph's text; DLG-ASK's message is
\   paragraph 0.
: DLG-PARAGRAPH  ( widget index -- a u )  _DLG-PARA DROP ;

\ =====================================================================
\ 10. Asking
\ =====================================================================

VARIABLE _DLG-A-XT
VARIABLE _DLG-A-CTX
VARIABLE _DLG-A-DETAIL

\ Open the dialog over the application that asks.
: _DLG-OPEN  ( title-a title-u paras pcount buttons bcount detail? -- ok? )
    _DLG-A-DETAIL !
    _DLG-CELL-HOOK @ IF 2DROP 2DROP 2DROP FALSE EXIT THEN
    _DLG-NEW ?DUP 0= IF FALSE EXIT THEN
    0 0 0 0 ['] RGN-NEW CATCH IF 2DROP 2DROP DLG-FREE FALSE EXIT THEN
    OVER _WDG-O-REGION + !
    _DLG-A-XT @ OVER _DLG-O-XT + !
    _DLG-A-CTX @ OVER _DLG-O-CTX + !
    _DLG-A-DETAIL @ OVER _DLG-O-DETAIL + !
    _DLG-CELL-HOOK ! TRUE ;

CREATE _DLG-ONE-PARA _DLG-PARA-SIZE ALLOT

\ DLG-ASK ( title-a title-u msg-a msg-u buttons count xt context -- ok? )
\   Open a dialog over the application that asks.  BUTTONS holds COUNT
\   records of four cells: label-a label-u roles key.  Once a button is
\   chosen the dialog closes and XT, unless 0, runs ( index context -- )
\   in that application.  False when the application already shows a
\   dialog, the buttons are not valid, or memory is short.
: DLG-ASK  ( title-a title-u msg-a msg-u buttons count xt context -- ok? )
    _DLG-A-CTX ! _DLG-A-XT !
    2SWAP _DLG-ONE-PARA 8 + ! _DLG-ONE-PARA !
    DLG-LOOK-TEXT _DLG-ONE-PARA 16 + !
    _DLG-ONE-PARA 1 2SWAP 0 _DLG-OPEN ;

\ DLG-ASK-DETAIL ( title-a title-u paras pcount buttons bcount xt context -- ok? )
\   As DLG-ASK, with a message of PCOUNT paragraphs, each three cells:
\   text-a text-u look, in a dialog that takes the host's whole area.
: DLG-ASK-DETAIL  ( title-a title-u paras pcount buttons bcount xt context -- ok? )
    _DLG-A-CTX ! _DLG-A-XT ! -1 _DLG-OPEN ;

CREATE _DLG-CONFIRM-BTNS 2 _DLG-BTN-SIZE * ALLOT

\ DLG-CONFIRM ( msg-a msg-u verb-a verb-u xt context -- ok? )
\   Ask before an action that cannot be undone, under the title Confirm:
\   VERB, destructive, and Cancel, the default.  XT, unless 0, runs
\   ( confirmed? context -- ) with true only for VERB.
: DLG-CONFIRM  ( msg-a msg-u verb-a verb-u xt context -- ok? )
    _DLG-A-CTX ! _DLG-A-XT !
    _DLG-CONFIRM-BTNS 2 _DLG-BTN-SIZE * 0 FILL
    _DLG-CONFIRM-BTNS 8 + ! _DLG-CONFIRM-BTNS !
    DLG-B-DESTRUCTIVE _DLG-CONFIRM-BTNS 16 + !
    S" Cancel" _DLG-CONFIRM-BTNS _DLG-BTN-SIZE + 8 + !
        _DLG-CONFIRM-BTNS _DLG-BTN-SIZE + !
    DLG-B-DEFAULT DLG-B-CANCEL OR _DLG-CONFIRM-BTNS _DLG-BTN-SIZE + 16 + !
    S" Confirm" 2SWAP _DLG-CONFIRM-BTNS 2 _DLG-A-XT @ _DLG-A-CTX @ DLG-ASK
    DUP IF
        -1 _DLG-CELL-HOOK @ _DLG-O-CONFIRM + !
        3 _DLG-CELL-HOOK @ _DLG-O-SEVERITY + !
    THEN ;

CREATE _DLG-OK-BTN _DLG-BTN-SIZE ALLOT

\ DLG-INFO ( msg-a msg-u -- ok? )
\   Tell the user something: an Info dialog with OK.
: DLG-INFO  ( msg-a msg-u -- ok? )
    _DLG-OK-BTN _DLG-BTN-SIZE 0 FILL
    S" OK" _DLG-OK-BTN 8 + ! _DLG-OK-BTN !
    DLG-B-DEFAULT DLG-B-CANCEL OR _DLG-OK-BTN 16 + !
    S" Info" 2SWAP _DLG-OK-BTN 1 0 0 DLG-ASK
    DUP IF 1 _DLG-CELL-HOOK @ _DLG-O-SEVERITY + ! THEN ;

\ =====================================================================
\ 11. Hosting
\ =====================================================================
\
\   A host calls these with an application's state current: DLG-HOST-EVENT
\   before the application sees an event, and DLG-HOST-PAINT after the
\   application has painted.

\ DLG-SHOWN ( -- widget|0 )
\   The dialog the current application shows.
: DLG-SHOWN  ( -- widget|0 )  _DLG-CELL-HOOK @ ;

\ The host repaints what a closing dialog covered.
: _DLG-DISMISS  ( widget -- )
    WDG-REGION >R R@ RGN-ROW R@ RGN-COL R@ RGN-H R> RGN-W
    2DUP * IF _DLG-DISMISS-HOOK ELSE 2DROP 2DROP THEN ;

\ Close an answered dialog: the host repaints what it covered, and the
\ asker is called back.  The dialog is freed first, so a callback that
\ throws leaks nothing and one that asks again finds no dialog shown.
VARIABLE _DLG-ANS-W
: _DLG-ANSWER  ( widget -- )
    DUP _DLG-ANS-W ! _DLG-DISMISS
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

\ A dialog laid out at another size, or showing other rows of its
\ message, shows new content.
VARIABLE _DLG-P-H
VARIABLE _DLG-P-W
VARIABLE _DLG-P-T
: _DLG-RELAYOUT  ( widget -- )
    DUP WDG-REGION DUP RGN-H _DLG-P-H ! RGN-W _DLG-P-W !
    DUP _DLG-O-TOP + @ _DLG-P-T !
    DUP _DLG-LAYOUT
    DUP WDG-REGION DUP RGN-H _DLG-P-H @ <> SWAP RGN-W _DLG-P-W @ <> OR
    OVER _DLG-O-TOP + @ _DLG-P-T @ <> OR
    OVER _DLG-O-REVISION + @ 0= OR IF
        1 _DLG-REVISIONS +! _DLG-REVISIONS @ OVER _DLG-O-REVISION + !
    THEN DROP ;

\ DLG-HOST-PAINT ( -- )
\   Paint the dialog the current application shows over it, centred in
\   the host's bounds, keeping the drawing region the caller had.
: DLG-HOST-PAINT  ( -- )
    _DLG-CELL-HOOK @ ?DUP 0= IF EXIT THEN
    DUP _DLG-RELAYOUT DUP WDG-DIRTY
    RGN-CURRENT >R ['] WDG-DRAW CATCH R> RGN-RESTORE
    ?DUP IF NIP THROW THEN ;

\ DLG-DISCARD ( -- )
\   Free the dialog the current application shows, unanswered: the
\   application is going away.
: DLG-DISCARD  ( -- )
    _DLG-CELL-HOOK @ ?DUP IF DLG-FREE 0 _DLG-CELL-HOOK ! THEN ;

\ DLG-WITHDRAW ( -- )
\   Close the dialog the current application shows, unanswered, and have
\   the host repaint what it covered: the application no longer asks.
: DLG-WITHDRAW  ( -- )
    _DLG-CELL-HOOK @ ?DUP 0= IF EXIT THEN
    0 _DLG-CELL-HOOK ! DUP _DLG-DISMISS DLG-FREE ;

\ =====================================================================
\ 12. Capture
\ =====================================================================
\
\   A dialog its host has painted goes out as a UDLG model: its title on
\   the top edge, the message rows in view as the paint broke them, with
\   the row saying more lies below while it does, and a button record
\   where the paint put each button, with its key's name.  A button that
\   can be chosen is ENABLED, and the selected one SELECTED when it can
\   be.  The message's direction controls go out as inert stand-ins, as
\   the paint ignored them.  A dialog laid out too small to show its parts
\   apart, or whose text is not clean single-line text, is left as
\   painted text.

VARIABLE _DLG-C-W
VARIABLE _DLG-C-DST
VARIABLE _DLG-C-CAP
VARIABLE _DLG-C-H
VARIABLE _DLG-C-WD
VARIABLE _DLG-C-MW
VARIABLE _DLG-C-TU
VARIABLE _DLG-C-TW
VARIABLE _DLG-C-MU
VARIABLE _DLG-C-LINES
VARIABLE _DLG-C-CLEAN
VARIABLE _DLG-C-NEED

\ A live dialog this module made, with its own region.
: _DLG-GENUINE?  ( widget -- flag )
    DUP 0= OVER 7 AND OR IF DROP 0 EXIT THEN
    DUP _WDG-O-HANDLE-XT + @ ['] _DLG-HANDLE <> IF DROP 0 EXIT THEN
    DUP _DLG-O-INSTANCE + @ 0= IF DROP 0 EXIT THEN
    WDG-REGION DUP 0= SWAP 7 AND OR 0= ;

\ DLG-INSTANCE@ ( widget -- instance|0 )
\   The dialog's identity for as long as it lives; 0 for anything else.
: DLG-INSTANCE@  ( widget -- instance|0 )
    DUP _DLG-GENUINE? 0= IF DROP 0 EXIT THEN _DLG-O-INSTANCE + @ ;

\ DLG-ROOT ( widget -- row col height width )
\   The screen cells its last paint laid it out in; all zero before that.
: DLG-ROOT  ( widget -- row col height width )
    DUP _DLG-O-REVISION + @ 0= IF DROP 0 0 0 0 EXIT THEN
    WDG-REGION >R R@ RGN-ROW R@ RGN-COL R@ RGN-H R> RGN-W ;

\ The dialog's allocation: descriptor, button and paragraph records, and
\ text.
VARIABLE _DLG-SZ-W
: _DLG-C-SIZE  ( widget -- bytes )
    DUP _DLG-SZ-W !
    DUP _DLG-O-BCNT + @ _DLG-BTN-SIZE * _DLG-DESC-SIZE +
    OVER _DLG-O-PCNT + @ _DLG-PARA-SIZE * +
    SWAP _DLG-O-TITLE-U + @ +
    _DLG-SZ-W @ _DLG-O-PCNT + @ 0 ?DO _DLG-SZ-W @ I _DLG-PARA DROP NIP + LOOP
    _DLG-SZ-W @ _DLG-O-BCNT + @ 0 ?DO
        _DLG-SZ-W @ _DLG-O-BTNS + @ I _DLG-BTN-LABEL NIP +
    LOOP ;

: _DLG-C-COUNT-BYTES  ( a u -- )
    DUP IF 2DUP USF-TEXT? 0= IF 0 _DLG-C-CLEAN ! THEN THEN
    NIP _DLG-C-LINES @ IF 1+ THEN _DLG-C-MU +!
    1 _DLG-C-LINES +! ;
: _DLG-C-COUNT-LINE  ( index -- )  DROP _DLG-TLN TLINES-BYTES _DLG-C-COUNT-BYTES ;
: _DLG-C-WRITE-LINE  ( index -- )
    DROP _DLG-TLN TLINES-BYTES _DLG-C-DST @ UDLG-LINE+ ;

\ Whether every button lies inside the box and has a clean label.
: _DLG-C-BUTTONS?  ( -- flag )
    _DLG-C-W @ _DLG-O-BCNT + @ 0 ?DO
        _DLG-C-W @ I _DLG-BTN-COL DUP 0< IF DROP 0 UNLOOP EXIT THEN
        _DLG-C-W @ I _DLG-BTN-WIDTH + _DLG-C-WD @ > IF 0 UNLOOP EXIT THEN
        _DLG-C-W @ _DLG-O-BTNS + @ I _DLG-BTN-LABEL USF-TEXT? 0= IF
            0 UNLOOP EXIT
        THEN
    LOOP -1 ;

: _DLG-C-KEY-NAME  ( index -- a u )
    _DLG-C-W @ _DLG-O-BTNS + @ SWAP _DLG-BTN-KEY _DLG-KEY-NAME ;

\ Lay the model out as the paint does, and measure it; false when it
\ cannot be shown as a dialog.
: _DLG-C-PREPARE  ( -- representable? )
    _DLG-C-W @ WDG-REGION DUP RGN-H _DLG-C-H ! RGN-W _DLG-C-WD !
    _DLG-C-H @ 5 < _DLG-C-WD @ 5 < OR IF 0 EXIT THEN
    _DLG-C-W @ _DLG-O-ROWS + @ 0= IF 0 EXIT THEN
    _DLG-C-W @ _DLG-O-MW + @ _DLG-C-MW !
    _DLG-C-W @ _DLG-O-TITLE-A + @ _DLG-C-W @ _DLG-O-TITLE-U + @
    2DUP CW-SWIDTH DUP _DLG-C-TW ! IF
        USF-TEXT? 0= IF 0 EXIT THEN
        _DLG-C-W @ _DLG-O-TITLE-U + @ _DLG-C-TU !
        _DLG-C-TW @ _DLG-C-WD @ 4 - MIN _DLG-C-TW !
    ELSE
        2DROP 0 _DLG-C-TU !
    THEN
    _DLG-C-BUTTONS? 0= IF 0 EXIT THEN
    0 _DLG-C-MU ! 0 _DLG-C-LINES ! -1 _DLG-C-CLEAN !
    _DLG-C-W @ ['] _DLG-C-COUNT-LINE _DLG-VISIBLE 0= IF 0 EXIT THEN
    _DLG-C-W @ _DLG-MORE? IF _DLG-MORE$ _DLG-C-COUNT-BYTES THEN
    _DLG-C-CLEAN @ 0= IF 0 EXIT THEN
    _DLG-C-TU @ _DLG-C-MU @ UDLG-TEXT-BYTES
    _DLG-C-W @ _DLG-O-BCNT + @ 0 ?DO
        _DLG-C-W @ _DLG-O-BTNS + @ I _DLG-BTN-LABEL NIP
        I _DLG-C-KEY-NAME NIP UDLG-BUTTON-BYTES +
    LOOP _DLG-C-NEED ! -1 ;

\ The destination lies apart from the dialog and its region.
: _DLG-C-APART?  ( -- flag )
    _DLG-C-DST @ _DLG-C-CAP @
    2DUP _DLG-C-W @ DUP _DLG-C-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    _DLG-C-W @ WDG-REGION RGN-SIZE MSPAN-OVERLAP? 0= ;

: _DLG-C-STATE  ( index -- state )
    UDLG-STATE-VISIBLE
    _DLG-C-W @ 2 PICK _DLG-AVAILABLE? IF
        UDLG-STATE-ENABLED OR
        SWAP _DLG-C-W @ _DLG-O-SEL + @ = IF UDLG-STATE-SELECTED OR THEN
    ELSE NIP THEN ;

: _DLG-C-WRITE  ( -- )
    _DLG-C-W @ _DLG-O-INSTANCE + @ _DLG-C-W @ _DLG-O-REVISION + @
    _DLG-C-WD @ _DLG-C-H @ 0 _DLG-C-W @ _DLG-O-SEVERITY + @
    _DLG-C-DST @ UDLG-START
    _DLG-C-TU @ IF
        0 2 1 _DLG-C-TW @
        _DLG-C-W @ _DLG-O-TITLE-A + @ _DLG-C-TU @ _DLG-C-DST @ UDLG-TITLE!
    THEN
    _DLG-C-LINES @ IF
        2 2 _DLG-C-LINES @ _DLG-C-MW @ _DLG-C-DST @ UDLG-MESSAGE-SLOT!
        _DLG-C-W @ ['] _DLG-C-WRITE-LINE _DLG-VISIBLE DROP
        _DLG-C-W @ _DLG-MORE? IF _DLG-MORE$ _DLG-C-DST @ UDLG-LINE+ THEN
        _DLG-C-DST @ UDLG-MESSAGE@ BIDI-INERT
    THEN
    _DLG-C-W @ _DLG-O-BCNT + @ 0 ?DO
        _DLG-C-H @ 2 - _DLG-C-W @ I _DLG-BTN-COL 1 _DLG-C-W @ I _DLG-BTN-WIDTH
        _DLG-C-W @ _DLG-O-BTNS + @ I _DLG-BTN-ROLES
            DLG-B-DEFAULT DLG-B-CANCEL OR DLG-B-DESTRUCTIVE OR AND
        I _DLG-C-STATE
        _DLG-C-W @ _DLG-O-BTNS + @ I _DLG-BTN-LABEL I _DLG-C-KEY-NAME
        _DLG-C-DST @ UDLG-BUTTON+
    LOOP ;

\ DLG-MODEL-CAPTURE ( dst cap widget -- bytes status )
\   Write the dialog its last paint laid out as a UDLG model at DST, an
\   aligned span of CAP bytes apart from the dialog, or with DST 0 and
\   CAP 0 only measure it.  The status is a UDLG-S- value: UNSUPPORTED
\   for a dialog not yet laid out, or one that cannot be shown as a
\   dialog.
: DLG-MODEL-CAPTURE  ( dst cap widget -- bytes status )
    DUP _DLG-GENUINE? 0= IF 2DROP DROP 0 UDLG-S-INVALID EXIT THEN
    DUP _DLG-O-REVISION + @ 0= IF 2DROP DROP 0 UDLG-S-UNSUPPORTED EXIT THEN
    _DLG-C-W ! _DLG-C-CAP ! _DLG-C-DST !
    _DLG-C-PREPARE 0= IF 0 UDLG-S-UNSUPPORTED EXIT THEN
    _DLG-C-DST @ 0= IF
        _DLG-C-CAP @ IF 0 UDLG-S-INVALID EXIT THEN
        _DLG-C-NEED @ UDLG-S-OK EXIT
    THEN
    _DLG-C-DST @ 7 AND IF 0 UDLG-S-INVALID EXIT THEN
    _DLG-C-DST @ _DLG-C-CAP @ UDLG-STORAGE-DISJOINT? 0= IF
        0 UDLG-S-INVALID EXIT
    THEN
    _DLG-C-APART? 0= IF 0 UDLG-S-INVALID EXIT THEN
    _DLG-C-CAP @ _DLG-C-NEED @ U< IF 0 UDLG-S-CAPACITY EXIT THEN
    _DLG-C-WRITE
    _DLG-C-DST @ _DLG-C-NEED @ UDLG-VALIDATE
    DUP IF 0 SWAP EXIT THEN
    _DLG-C-NEED @ SWAP ;

\ =====================================================================
\ 13. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _dlg-guard

' DLG-SELECTED    CONSTANT _dlg-selected-xt
' DLG-BTN-COUNT   CONSTANT _dlg-btncnt-xt
' DLG-RESULT      CONSTANT _dlg-result-xt
' DLG-PARAGRAPH   CONSTANT _dlg-paragraph-xt
' DLG-FREE        CONSTANT _dlg-free-xt
' DLG-ASK         CONSTANT _dlg-ask-xt
' DLG-ASK-DETAIL  CONSTANT _dlg-ask-detail-xt
' DLG-CONFIRM     CONSTANT _dlg-confirm-xt
' DLG-INFO        CONSTANT _dlg-info-xt
' DLG-SHOWN       CONSTANT _dlg-shown-xt
' DLG-HOST-EVENT  CONSTANT _dlg-host-event-xt
' DLG-HOST-PAINT  CONSTANT _dlg-host-paint-xt
' DLG-DISCARD     CONSTANT _dlg-discard-xt
' DLG-WITHDRAW    CONSTANT _dlg-withdraw-xt
' DLG-INSTANCE@   CONSTANT _dlg-instance-xt
' DLG-ROOT        CONSTANT _dlg-root-xt
' DLG-MODEL-CAPTURE CONSTANT _dlg-capture-xt

: DLG-SELECTED    _dlg-selected-xt  _dlg-guard WITH-GUARD ;
: DLG-BTN-COUNT   _dlg-btncnt-xt    _dlg-guard WITH-GUARD ;
: DLG-RESULT      _dlg-result-xt    _dlg-guard WITH-GUARD ;
: DLG-PARAGRAPH   _dlg-paragraph-xt _dlg-guard WITH-GUARD ;
: DLG-FREE        _dlg-free-xt      _dlg-guard WITH-GUARD ;
: DLG-ASK         _dlg-ask-xt       _dlg-guard WITH-GUARD ;
: DLG-ASK-DETAIL  _dlg-ask-detail-xt _dlg-guard WITH-GUARD ;
: DLG-CONFIRM     _dlg-confirm-xt   _dlg-guard WITH-GUARD ;
: DLG-INFO        _dlg-info-xt      _dlg-guard WITH-GUARD ;
: DLG-SHOWN       _dlg-shown-xt     _dlg-guard WITH-GUARD ;
\ Hosting calls back into the application and paints through host hooks,
\ so it never holds the dialog guard.  Call it only on the UI owner core.
: DLG-HOST-EVENT  _dlg-host-event-xt EXECUTE ;
: DLG-HOST-PAINT  _dlg-host-paint-xt EXECUTE ;
: DLG-DISCARD     _dlg-discard-xt   _dlg-guard WITH-GUARD ;
\ Withdrawing repaints through the host's hook, as answering does.
: DLG-WITHDRAW    _dlg-withdraw-xt EXECUTE ;
: DLG-INSTANCE@   _dlg-instance-xt  _dlg-guard WITH-GUARD ;
: DLG-ROOT        _dlg-root-xt      _dlg-guard WITH-GUARD ;
: DLG-MODEL-CAPTURE _dlg-capture-xt _dlg-guard WITH-GUARD ;
[THEN] [THEN]
