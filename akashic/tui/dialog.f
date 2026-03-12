\ =====================================================================
\  akashic/tui/dialog.f — Modal Dialog Boxes
\ =====================================================================
\
\  Modal popup dialog with a title, message, and horizontal button
\  row.  DLG-SHOW runs a real KEY-POLL modal loop — it blocks the
\  caller until the user picks a button (Enter, Escape, or Tab
\  to cycle + Enter).  Returns the 0-based button index.
\
\  Dialog Descriptor (header + 8 cells = 104 bytes):
\    +0..+39  widget header  (type = WDG-T-DIALOG)
\    +40  title-a       Title string address
\    +48  title-u       Title string length
\    +56  msg-a         Message string address
\    +64  msg-u         Message string length
\    +72  buttons       Address of button label array (addr+len pairs)
\    +80  btn-count     Number of buttons
\    +88  selected-btn  Currently focused button index
\    +96  result        -1 while open; >=0 = chosen button index
\
\  Button label array: contiguous (addr, len) pairs — 2 cells
\  (16 bytes) per button.
\
\  Prefix: DLG- (public), _DLG- (internal)
\  Provider: akashic-tui-dialog
\  Dependencies: keys.f, screen.f, widget.f, draw.f, box.f, region.f

PROVIDED akashic-tui-dialog

REQUIRE keys.f
REQUIRE screen.f
REQUIRE widget.f
REQUIRE draw.f
REQUIRE box.f
REQUIRE region.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _DLG-O-TITLE-A
48 CONSTANT _DLG-O-TITLE-U
56 CONSTANT _DLG-O-MSG-A
64 CONSTANT _DLG-O-MSG-U
72 CONSTANT _DLG-O-BTNS
80 CONSTANT _DLG-O-BCNT
88 CONSTANT _DLG-O-SEL
96 CONSTANT _DLG-O-RESULT

104 CONSTANT _DLG-DESC-SIZE

\ =====================================================================
\ 2. Constants
\ =====================================================================

16 CONSTANT _DLG-BTN-SIZE   \ 2 cells per button label entry

\ =====================================================================
\ 3. Internal helpers
\ =====================================================================

\ _DLG-BTN-ADDR ( btns index -- addr )
\   Address of button entry at index.
: _DLG-BTN-ADDR  ( btns index -- addr )
    _DLG-BTN-SIZE * + ;

\ _DLG-BTN-LABEL ( btns index -- a u )
\   Get label string for button at index.
: _DLG-BTN-LABEL  ( btns index -- a u )
    _DLG-BTN-ADDR DUP @ SWAP 8 + @ ;

\ =====================================================================
\ 4. Internal — Draw
\ =====================================================================

VARIABLE _DLG-DRW-W       \ widget
VARIABLE _DLG-DRW-RW      \ region width
VARIABLE _DLG-DRW-RH      \ region height
VARIABLE _DLG-DRW-TA      \ title-a
VARIABLE _DLG-DRW-TU      \ title-u
VARIABLE _DLG-DRW-MA      \ msg-a
VARIABLE _DLG-DRW-MU      \ msg-u
VARIABLE _DLG-DRW-BTNS    \ buttons array
VARIABLE _DLG-DRW-BCNT    \ button count
VARIABLE _DLG-DRW-SEL     \ selected button
VARIABLE _DLG-DRW-I       \ loop counter
VARIABLE _DLG-DRW-COL     \ current column for buttons
VARIABLE _DLG-DRW-BROW    \ button row

\ _DLG-MSG-ROWS ( -- n )
\   Number of rows available for message text.
\   Layout: row 0 = box top, row 1 = blank, row 2..h-4 = message,
\   row h-3 = blank, row h-2 = buttons, row h-1 = box bottom.
: _DLG-MSG-ROWS  ( -- n )
    _DLG-DRW-RH @ 5 - 1 MAX ;

\ --- Draw message text (line-wrap at column width) ---

VARIABLE _DLG-MSG-ROW     \ current draw row
VARIABLE _DLG-MSG-ADDR    \ remaining text addr
VARIABLE _DLG-MSG-LEN     \ remaining text len
VARIABLE _DLG-MSG-MAXR    \ max rows for message
VARIABLE _DLG-MSG-MW      \ message width (region width - 4)

: _DLG-DRAW-MESSAGE  ( -- )
    _DLG-DRW-MA @ _DLG-MSG-ADDR !
    _DLG-DRW-MU @ _DLG-MSG-LEN !
    2 _DLG-MSG-ROW !                     \ start at row 2 (after top + blank)
    _DLG-MSG-ROWS _DLG-MSG-MAXR !
    _DLG-DRW-RW @ 4 - 1 MAX _DLG-MSG-MW !
    BEGIN
        _DLG-MSG-LEN @ 0>
        _DLG-MSG-MAXR @ 0>
        AND
    WHILE
        32 _DLG-MSG-ROW @ 2 _DLG-MSG-MW @ DRW-HLINE   \ clear row
        _DLG-MSG-ADDR @
        _DLG-MSG-LEN @ _DLG-MSG-MW @ MIN
        _DLG-MSG-ROW @ 2 DRW-TEXT                       \ draw text
        _DLG-MSG-LEN @ _DLG-MSG-MW @ MIN
        DUP _DLG-MSG-ADDR +!
        NEGATE _DLG-MSG-LEN +!
        1 _DLG-MSG-ROW +!
        -1 _DLG-MSG-MAXR +!
    REPEAT ;

\ --- Draw buttons centered on the button row ---

VARIABLE _DLG-BT-TOTW     \ total width of all buttons

: _DLG-BTN-TOTAL-W  ( -- )
    0 _DLG-BT-TOTW !
    0 _DLG-DRW-I !
    BEGIN
        _DLG-DRW-I @ _DLG-DRW-BCNT @ <
    WHILE
        _DLG-DRW-BTNS @ _DLG-DRW-I @ _DLG-BTN-LABEL
        NIP 4 +                           \ "[ label ]"
        _DLG-BT-TOTW +!
        1 _DLG-DRW-I +!
    REPEAT
    _DLG-DRW-BCNT @ 1 > IF               \ spaces between
        _DLG-DRW-BCNT @ 1- _DLG-BT-TOTW +!
    THEN ;

: _DLG-DRAW-BUTTONS  ( -- )
    _DLG-DRW-BCNT @ 0= IF EXIT THEN
    _DLG-DRW-RH @ 2 - _DLG-DRW-BROW !

    32 _DLG-DRW-BROW @ 1 _DLG-DRW-RW @ 2 - DRW-HLINE  \ clear row

    _DLG-BTN-TOTAL-W
    _DLG-DRW-RW @ 2 - _DLG-BT-TOTW @ -
    DUP 0< IF DROP 0 THEN
    2 / 1+
    _DLG-DRW-COL !

    0 _DLG-DRW-I !
    BEGIN
        _DLG-DRW-I @ _DLG-DRW-BCNT @ <
    WHILE
        _DLG-DRW-I @ _DLG-DRW-SEL @ = IF
            CELL-A-REVERSE DRW-ATTR!
        THEN
        91 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR      \ [
        1 _DLG-DRW-COL +!
        32 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR      \ space
        1 _DLG-DRW-COL +!
        _DLG-DRW-BTNS @ _DLG-DRW-I @ _DLG-BTN-LABEL
        _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-TEXT
        _DLG-DRW-BTNS @ _DLG-DRW-I @ _DLG-BTN-LABEL NIP
        _DLG-DRW-COL +!
        32 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR      \ space
        1 _DLG-DRW-COL +!
        93 _DLG-DRW-BROW @ _DLG-DRW-COL @ DRW-CHAR      \ ]
        1 _DLG-DRW-COL +!
        _DLG-DRW-I @ _DLG-DRW-SEL @ = IF
            0 DRW-ATTR!
        THEN
        _DLG-DRW-I @ 1+ _DLG-DRW-BCNT @ < IF
            1 _DLG-DRW-COL +!
        THEN
        1 _DLG-DRW-I +!
    REPEAT ;

\ --- Main draw callback ---

: _DLG-DRAW  ( widget -- )
    _DLG-DRW-W !
    _DLG-DRW-W @ WDG-REGION RGN-W _DLG-DRW-RW !
    _DLG-DRW-W @ WDG-REGION RGN-H _DLG-DRW-RH !
    _DLG-DRW-W @ _DLG-O-TITLE-A + @ _DLG-DRW-TA !
    _DLG-DRW-W @ _DLG-O-TITLE-U + @ _DLG-DRW-TU !
    _DLG-DRW-W @ _DLG-O-MSG-A + @ _DLG-DRW-MA !
    _DLG-DRW-W @ _DLG-O-MSG-U + @ _DLG-DRW-MU !
    _DLG-DRW-W @ _DLG-O-BTNS + @ _DLG-DRW-BTNS !
    _DLG-DRW-W @ _DLG-O-BCNT + @ _DLG-DRW-BCNT !
    _DLG-DRW-W @ _DLG-O-SEL + @ _DLG-DRW-SEL !
    BOX-SINGLE _DLG-DRW-TA @ _DLG-DRW-TU @
        0 0 _DLG-DRW-RH @ _DLG-DRW-RW @ BOX-DRAW-TITLED
    0 0 _DLG-DRW-RH @ _DLG-DRW-RW @ BOX-SHADOW
    32 1 1 _DLG-DRW-RH @ 2 - _DLG-DRW-RW @ 2 - DRW-FILL-RECT
    _DLG-DRAW-MESSAGE
    _DLG-DRAW-BUTTONS ;

\ =====================================================================
\ 5. Internal — Handle
\ =====================================================================
\   _DLG-HANDLE stores its "result" in the per-widget field +96
\   so multiple dialogs stay independent.

VARIABLE _DLG-HND-W
VARIABLE _DLG-HND-TYPE
VARIABLE _DLG-HND-CODE
VARIABLE _DLG-HND-SEL
VARIABLE _DLG-HND-BCNT

: _DLG-HANDLE  ( event widget -- consumed? )
    _DLG-HND-W !
    DUP @ _DLG-HND-TYPE !
    8 + @ _DLG-HND-CODE !
    _DLG-HND-W @ _DLG-O-SEL + @ _DLG-HND-SEL !
    _DLG-HND-W @ _DLG-O-BCNT + @ _DLG-HND-BCNT !

    _DLG-HND-TYPE @ KEY-T-SPECIAL = IF
        _DLG-HND-CODE @ CASE
            KEY-LEFT OF
                _DLG-HND-SEL @ 0> IF
                    _DLG-HND-SEL @ 1-
                    _DLG-HND-W @ _DLG-O-SEL + !
                    _DLG-HND-W @ WDG-DIRTY
                THEN
                -1 EXIT
            ENDOF
            KEY-RIGHT OF
                _DLG-HND-SEL @ 1+
                DUP _DLG-HND-BCNT @ < IF
                    _DLG-HND-W @ _DLG-O-SEL + !
                    _DLG-HND-W @ WDG-DIRTY
                ELSE DROP THEN
                -1 EXIT
            ENDOF
            KEY-TAB OF
                _DLG-HND-SEL @ 1+
                _DLG-HND-BCNT @ MOD
                _DLG-HND-W @ _DLG-O-SEL + !
                _DLG-HND-W @ WDG-DIRTY
                -1 EXIT
            ENDOF
            KEY-ENTER OF
                _DLG-HND-SEL @
                _DLG-HND-W @ _DLG-O-RESULT + !
                -1 EXIT
            ENDOF
            KEY-ESC OF
                _DLG-HND-BCNT @ 1-
                DUP 0< IF DROP 0 THEN
                _DLG-HND-W @ _DLG-O-RESULT + !
                -1 EXIT
            ENDOF
        ENDCASE
    THEN
    0 ;

\ =====================================================================
\ 6. Constructor
\ =====================================================================

VARIABLE _DLG-N-TA
VARIABLE _DLG-N-TU
VARIABLE _DLG-N-MA
VARIABLE _DLG-N-MU
VARIABLE _DLG-N-BT
VARIABLE _DLG-N-BC

\ DLG-NEW ( title-a title-u msg-a msg-u btns count -- widget )
\   Allocate and initialise a dialog widget.
\   Does NOT create a region — use DLG-SET-REGION or DLG-SHOW.
: DLG-NEW  ( title-a title-u msg-a msg-u btns count -- widget )
    _DLG-N-BC !
    _DLG-N-BT !
    _DLG-N-MU !
    _DLG-N-MA !
    _DLG-N-TU !
    _DLG-N-TA !
    _DLG-DESC-SIZE ALLOCATE
    0<> ABORT" DLG-NEW: alloc failed"
    WDG-T-DIALOG  OVER _WDG-O-TYPE       + !
    0             OVER _WDG-O-REGION     + !
    ['] _DLG-DRAW  OVER _WDG-O-DRAW-XT  + !
    ['] _DLG-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                  OVER _WDG-O-FLAGS      + !
    _DLG-N-TA @  OVER _DLG-O-TITLE-A  + !
    _DLG-N-TU @  OVER _DLG-O-TITLE-U  + !
    _DLG-N-MA @  OVER _DLG-O-MSG-A    + !
    _DLG-N-MU @  OVER _DLG-O-MSG-U    + !
    _DLG-N-BT @  OVER _DLG-O-BTNS     + !
    _DLG-N-BC @  OVER _DLG-O-BCNT     + !
    0             OVER _DLG-O-SEL      + !
    -1            OVER _DLG-O-RESULT   + ! ;

\ =====================================================================
\ 7. Public API
\ =====================================================================

\ DLG-SET-REGION ( rgn widget -- )
: DLG-SET-REGION  ( rgn widget -- )
    _WDG-O-REGION + ! ;

\ DLG-SELECTED ( widget -- index )
: DLG-SELECTED  ( widget -- index )
    _DLG-O-SEL + @ ;

\ DLG-BTN-COUNT ( widget -- n )
: DLG-BTN-COUNT  ( widget -- n )
    _DLG-O-BCNT + @ ;

\ DLG-RESULT ( widget -- n )
\   Read per-widget result field.
\   -1 while open, >=0 once a button was chosen.
: DLG-RESULT  ( widget -- n )
    _DLG-O-RESULT + @ ;

\ =====================================================================
\ 8. Modal loop — DLG-SHOW
\ =====================================================================
\
\   Auto-sizes the dialog, centres it on an 80×24 screen, draws it,
\   then enters a KEY-POLL busy-loop.  Each key event is dispatched
\   through WDG-HANDLE (→ _DLG-HANDLE).  The loop exits once the
\   per-widget result field becomes >=0 (set by Enter or Escape).
\
\   After exit the auto-created region is freed and the result index
\   is returned.  The widget itself is NOT freed — caller does that.

VARIABLE _DLG-SH-W
VARIABLE _DLG-SH-WD
VARIABLE _DLG-SH-HT
VARIABLE _DLG-SH-MR
VARIABLE _DLG-SH-RGN

CREATE _DLG-EV 24 ALLOT    \ modal-loop event buffer (type+code+mods)

: _DLG-CALC-BTN-W  ( widget -- w )
    DUP _DLG-O-BTNS + @ SWAP _DLG-O-BCNT + @
    0 SWAP                             \ ( btns 0 count )
    0 ?DO
        OVER I _DLG-BTN-LABEL NIP
        4 + +
    LOOP
    NIP
    _DLG-SH-W @ _DLG-O-BCNT + @ 1 > IF
        _DLG-SH-W @ _DLG-O-BCNT + @ 1- +
    THEN ;

: DLG-SHOW  ( widget -- index )
    _DLG-SH-W !
    \ Reset per-widget result
    -1 _DLG-SH-W @ _DLG-O-RESULT + !
    0  _DLG-SH-W @ _DLG-O-SEL    + !

    \ ---- Auto-size ----
    _DLG-SH-W @ _DLG-O-TITLE-U + @ 4 +
    _DLG-SH-W @ _DLG-O-MSG-U   + @ 4 + MAX
    _DLG-SH-W @ _DLG-CALC-BTN-W 4 + MAX
    20 MAX  60 MIN
    _DLG-SH-WD !

    _DLG-SH-W @ _DLG-O-MSG-U + @
    _DLG-SH-WD @ 4 - 1 MAX /         \ msg-u / inner-width
    1 MAX
    _DLG-SH-MR !

    _DLG-SH-MR @ 5 + _DLG-SH-HT !

    \ ---- Centre on 24×80 screen ----
    24 _DLG-SH-HT @ - 2 / 0 MAX
    80 _DLG-SH-WD @ - 2 / 0 MAX
    _DLG-SH-HT @
    _DLG-SH-WD @
    RGN-NEW _DLG-SH-RGN !
    _DLG-SH-RGN @ _DLG-SH-W @ DLG-SET-REGION

    \ ---- Initial draw + flush ----
    _DLG-SH-W @ WDG-DIRTY
    _DLG-SH-W @ WDG-DRAW
    SCR-FLUSH

    \ ---- Modal event loop ----
    BEGIN
        _DLG-EV KEY-POLL IF
            _DLG-EV _DLG-SH-W @ WDG-HANDLE DROP
            _DLG-SH-W @ WDG-DRAW          \ redraws only when dirty
            SCR-FLUSH
        THEN
        _DLG-SH-W @ _DLG-O-RESULT + @ -1 <>
    UNTIL

    \ ---- Collect result, clean up region ----
    _DLG-SH-W @ _DLG-O-RESULT + @
    _DLG-SH-RGN @ RGN-FREE ;

\ =====================================================================
\ 9. Convenience wrappers — DLG-INFO, DLG-CONFIRM
\ =====================================================================

CREATE _DLG-OK-BTN 16 ALLOT

\ DLG-INFO ( msg-a msg-u -- )
\   One-shot "Info" dialog with a single [ OK ] button.
: DLG-INFO  ( msg-a msg-u -- )
    S" OK" _DLG-OK-BTN 8 + ! _DLG-OK-BTN !
    S" Info" 2SWAP _DLG-OK-BTN 1 DLG-NEW
    DUP DLG-SHOW DROP
    DLG-FREE ;

CREATE _DLG-YN-BTNS 32 ALLOT

\ DLG-CONFIRM ( msg-a msg-u -- flag )
\   Yes / No dialog.  Returns TRUE (-1) when "Yes" (button 0) chosen.
: DLG-CONFIRM  ( msg-a msg-u -- flag )
    S" Yes" _DLG-YN-BTNS 8 + ! _DLG-YN-BTNS !
    S" No"  _DLG-YN-BTNS 24 + ! _DLG-YN-BTNS 16 + !
    S" Confirm" 2SWAP _DLG-YN-BTNS 2 DLG-NEW
    DUP DLG-SHOW
    0= SWAP DLG-FREE ;

\ DLG-FREE ( widget -- )
: DLG-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\ 10. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
GUARD _dlg-guard

' DLG-NEW         CONSTANT _dlg-new-xt
' DLG-SET-REGION  CONSTANT _dlg-setrgn-xt
' DLG-SELECTED    CONSTANT _dlg-selected-xt
' DLG-BTN-COUNT   CONSTANT _dlg-btncnt-xt
' DLG-RESULT      CONSTANT _dlg-result-xt
' DLG-SHOW        CONSTANT _dlg-show-xt
' DLG-INFO        CONSTANT _dlg-info-xt
' DLG-CONFIRM     CONSTANT _dlg-confirm-xt
' DLG-FREE        CONSTANT _dlg-free-xt

: DLG-NEW         _dlg-new-xt       _dlg-guard WITH-GUARD ;
: DLG-SET-REGION  _dlg-setrgn-xt    _dlg-guard WITH-GUARD ;
: DLG-SELECTED    _dlg-selected-xt  _dlg-guard WITH-GUARD ;
: DLG-BTN-COUNT   _dlg-btncnt-xt    _dlg-guard WITH-GUARD ;
: DLG-RESULT      _dlg-result-xt    _dlg-guard WITH-GUARD ;
: DLG-SHOW        _dlg-show-xt      _dlg-guard WITH-GUARD ;
: DLG-INFO        _dlg-info-xt      _dlg-guard WITH-GUARD ;
: DLG-CONFIRM     _dlg-confirm-xt   _dlg-guard WITH-GUARD ;
: DLG-FREE        _dlg-free-xt      _dlg-guard WITH-GUARD ;
[THEN] [THEN]
