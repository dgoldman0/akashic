\ =====================================================================
\  akashic/tui/draw.f — Cell-Level Drawing Primitives
\ =====================================================================
\
\  Convenience words for common drawing operations on the current
\  screen's back buffer: horizontal / vertical lines, filled rectangles,
\  text strings placed at a position.  Operates on the screen set by
\  SCR-USE.
\
\  A "current style" (fg, bg, attrs) is maintained so callers don't
\  need to pass three extra values on every draw call.
\
\  All coordinates are 0-based (row, col).  Drawing is clipped to the
\  screen dimensions — writes outside the screen are silently discarded.
\
\  Prefix: DRW- (public), _DRW- (internal)
\  Provider: akashic-tui-draw
\  Dependencies: screen.f, ../text/utf8.f

PROVIDED akashic-tui-draw

REQUIRE screen.f
REQUIRE ../text/utf8.f

\ =====================================================================
\ 1. Style state — current drawing style
\ =====================================================================

VARIABLE _DRW-FG     7 _DRW-FG !      \ default foreground (white)
VARIABLE _DRW-BG     0 _DRW-BG !      \ default background (black)
VARIABLE _DRW-ATTRS  0 _DRW-ATTRS !   \ default no attributes

\ DRW-FG! ( fg -- )   Set drawing foreground color.
: DRW-FG!  ( fg -- )
    _DRW-FG ! ;

\ DRW-BG! ( bg -- )   Set drawing background color.
: DRW-BG!  ( bg -- )
    _DRW-BG ! ;

\ DRW-ATTR! ( attrs -- )   Set drawing attributes.
: DRW-ATTR!  ( attrs -- )
    _DRW-ATTRS ! ;

\ DRW-STYLE! ( fg bg attrs -- )  Set all three at once.
: DRW-STYLE!  ( fg bg attrs -- )
    _DRW-ATTRS !
    _DRW-BG !
    _DRW-FG ! ;

\ DRW-STYLE-RESET ( -- )  Reset to defaults (fg=7, bg=0, attrs=0).
: DRW-STYLE-RESET  ( -- )
    7 _DRW-FG !
    0 _DRW-BG !
    0 _DRW-ATTRS ! ;

\ _DRW-MAKE-CELL ( cp -- cell )
\   Build a cell from codepoint cp using current style.
: _DRW-MAKE-CELL  ( cp -- cell )
    _DRW-FG @ _DRW-BG @ _DRW-ATTRS @ CELL-MAKE ;

\ =====================================================================
\ 2. Clipping helpers
\ =====================================================================

\ _DRW-IN-BOUNDS? ( row col -- flag )
\   True if (row, col) is within the current screen.
: _DRW-IN-BOUNDS?  ( row col -- flag )
    SWAP 0 SCR-H WITHIN                \ 0 <= row < h ?
    SWAP 0 SCR-W WITHIN                \ 0 <= col < w ?
    AND ;

\ WITHIN ( n lo hi -- flag ) is standard: true if lo <= n < hi.
\ If not available, fall back to manual check.  Megapad-64 KDOS has it.

\ =====================================================================
\ 3. Drawing words
\ =====================================================================

\ DRW-CHAR ( cp row col -- )
\   Place one character at (row, col) using current style.
\   Silently clipped if out of bounds.
: DRW-CHAR  ( cp row col -- )
    2DUP _DRW-IN-BOUNDS? IF
        ROT _DRW-MAKE-CELL -ROT SCR-SET
    ELSE
        DROP DROP DROP
    THEN ;

\ DRW-HLINE ( cp row col len -- )
\   Draw a horizontal line of character cp starting at (row, col).
\   Clipped to screen width.
VARIABLE _DRW-HLINE-ROW
VARIABLE _DRW-HLINE-CP

: DRW-HLINE  ( cp row col len -- )
    >R                                 \ len on R
    SWAP _DRW-HLINE-ROW !             \ save row
    SWAP _DRW-HLINE-CP !              \ save cp
    \ ( col ) with len on R
    R> OVER + SWAP                     \ ( col+len col )
    ?DO
        _DRW-HLINE-CP @
        _DRW-HLINE-ROW @
        I
        DRW-CHAR
    LOOP ;

\ DRW-VLINE ( cp row col len -- )
\   Draw a vertical line of character cp starting at (row, col).
\   Clipped to screen height.
VARIABLE _DRW-VLINE-COL
VARIABLE _DRW-VLINE-CP

: DRW-VLINE  ( cp row col len -- )
    >R                                 \ len on R
    _DRW-VLINE-COL !                   \ save col
    SWAP _DRW-VLINE-CP !              \ save cp — now ( row ) with R=len
    R> OVER + SWAP                     \ ( row+len row )
    ?DO
        _DRW-VLINE-CP @
        I
        _DRW-VLINE-COL @
        DRW-CHAR
    LOOP ;

\ DRW-FILL-RECT ( cp row col h w -- )
\   Fill a rectangle with character cp.
VARIABLE _DRW-FR-COL
VARIABLE _DRW-FR-W
VARIABLE _DRW-FR-CP

: DRW-FILL-RECT  ( cp row col h w -- )
    _DRW-FR-W !                        \ save width
    >R                                 \ h on R
    _DRW-FR-COL !                      \ save starting col
    SWAP _DRW-FR-CP !                  \ save cp — now ( row ) R=h
    R> OVER + SWAP                     \ ( row+h row )
    ?DO
        _DRW-FR-CP @
        I
        _DRW-FR-COL @
        _DRW-FR-W @
        DRW-HLINE
    LOOP ;

\ DRW-CLEAR-RECT ( row col h w -- )
\   Clear a rectangle to CELL-BLANK (space, default colors, no attrs).
\   Temporarily sets style to defaults, draws spaces, then restores.
VARIABLE _DRW-CR-SAVE-FG
VARIABLE _DRW-CR-SAVE-BG
VARIABLE _DRW-CR-SAVE-A
VARIABLE _DRW-CR-ROW
VARIABLE _DRW-CR-COL
VARIABLE _DRW-CR-H
VARIABLE _DRW-CR-W

: DRW-CLEAR-RECT  ( row col h w -- )
    _DRW-CR-W !
    _DRW-CR-H !
    _DRW-CR-COL !
    _DRW-CR-ROW !
    _DRW-FG @ _DRW-CR-SAVE-FG !
    _DRW-BG @ _DRW-CR-SAVE-BG !
    _DRW-ATTRS @ _DRW-CR-SAVE-A !
    DRW-STYLE-RESET
    32 _DRW-CR-ROW @ _DRW-CR-COL @ _DRW-CR-H @ _DRW-CR-W @
    DRW-FILL-RECT
    _DRW-CR-SAVE-FG @ _DRW-FG !
    _DRW-CR-SAVE-BG @ _DRW-BG !
    _DRW-CR-SAVE-A  @ _DRW-ATTRS ! ;

\ =====================================================================
\ 4. Text drawing
\ =====================================================================

\ DRW-TEXT ( addr len row col -- )
\   Place a UTF-8 string at (row, col), advancing column per codepoint.
\   Clipped to screen width.
VARIABLE _DRW-TEXT-ROW
VARIABLE _DRW-TEXT-COL

: DRW-TEXT  ( addr len row col -- )
    _DRW-TEXT-COL !
    _DRW-TEXT-ROW !
    \ ( addr len )
    BEGIN
        DUP 0>
    WHILE
        UTF8-DECODE                    \ ( cp addr' len' )
        ROT                            \ ( addr' len' cp )
        _DRW-TEXT-ROW @
        _DRW-TEXT-COL @
        DRW-CHAR
        1 _DRW-TEXT-COL +!
    REPEAT
    2DROP ;

\ _DRW-UTF8-CPLEN ( addr len -- n )
\   Count codepoints in a UTF-8 string.
: _DRW-UTF8-CPLEN  ( addr len -- n )
    UTF8-LEN ;

\ DRW-TEXT-CENTER ( addr len row col w -- )
\   Center text within a field of width w starting at (row, col).
\   Remaining space is filled with blanks using current style.
VARIABLE _DRW-TC-ROW
VARIABLE _DRW-TC-COL
VARIABLE _DRW-TC-W

: DRW-TEXT-CENTER  ( addr len row col w -- )
    _DRW-TC-W !
    _DRW-TC-COL !
    _DRW-TC-ROW !
    \ ( addr len )
    2DUP _DRW-UTF8-CPLEN              \ ( addr len cplen )
    _DRW-TC-W @ OVER -                \ ( addr len cplen pad-total )
    DUP 0< IF DROP 0 THEN             \ clamp to 0
    2 /                                \ ( addr len cplen left-pad )
    NIP                                \ ( addr len left-pad )
    \ clear field first
    32 _DRW-TC-ROW @ _DRW-TC-COL @ _DRW-TC-W @ DRW-HLINE
    \ draw text at offset
    _DRW-TC-ROW @
    _DRW-TC-COL @ ROT +               \ ( addr len row col+left-pad )
    DRW-TEXT ;

\ DRW-TEXT-RIGHT ( addr len row col w -- )
\   Right-align text within a field of width w starting at (row, col).
\   Remaining space is filled with blanks using current style.
VARIABLE _DRW-TR-ROW
VARIABLE _DRW-TR-COL
VARIABLE _DRW-TR-W

: DRW-TEXT-RIGHT  ( addr len row col w -- )
    _DRW-TR-W !
    _DRW-TR-COL !
    _DRW-TR-ROW !
    \ ( addr len )
    2DUP _DRW-UTF8-CPLEN              \ ( addr len cplen )
    _DRW-TR-W @ SWAP -                \ ( addr len right-pad )
    DUP 0< IF DROP 0 THEN             \ clamp to 0
    \ clear field first
    32 _DRW-TR-ROW @ _DRW-TR-COL @ _DRW-TR-W @ DRW-HLINE
    \ draw text at offset
    _DRW-TR-ROW @
    _DRW-TR-COL @ ROT +               \ ( addr len row col+right-pad )
    DRW-TEXT ;

\ DRW-REPEAT ( cp row col n -- )
\   Synonym for DRW-HLINE (convenience naming).
: DRW-REPEAT  ( cp row col n -- )
    DRW-HLINE ;

\ =====================================================================
\ 5. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
GUARD _draw-guard

' DRW-FG!             CONSTANT _drw-fgset-xt
' DRW-BG!             CONSTANT _drw-bgset-xt
' DRW-ATTR!           CONSTANT _drw-attrset-xt
' DRW-STYLE!          CONSTANT _drw-styleset-xt
' DRW-STYLE-RESET     CONSTANT _drw-stylerst-xt
' DRW-CHAR            CONSTANT _drw-char-xt
' DRW-TEXT            CONSTANT _drw-text-xt
' DRW-HLINE           CONSTANT _drw-hline-xt
' DRW-VLINE           CONSTANT _drw-vline-xt
' DRW-FILL-RECT       CONSTANT _drw-fillrect-xt
' DRW-CLEAR-RECT      CONSTANT _drw-clrrect-xt
' DRW-TEXT-CENTER      CONSTANT _drw-txtcenter-xt
' DRW-TEXT-RIGHT       CONSTANT _drw-txtright-xt
' DRW-REPEAT          CONSTANT _drw-repeat-xt

: DRW-FG!             _drw-fgset-xt    _draw-guard WITH-GUARD ;
: DRW-BG!             _drw-bgset-xt    _draw-guard WITH-GUARD ;
: DRW-ATTR!           _drw-attrset-xt  _draw-guard WITH-GUARD ;
: DRW-STYLE!          _drw-styleset-xt _draw-guard WITH-GUARD ;
: DRW-STYLE-RESET     _drw-stylerst-xt _draw-guard WITH-GUARD ;
: DRW-CHAR            _drw-char-xt     _draw-guard WITH-GUARD ;
: DRW-TEXT            _drw-text-xt     _draw-guard WITH-GUARD ;
: DRW-HLINE           _drw-hline-xt    _draw-guard WITH-GUARD ;
: DRW-VLINE           _drw-vline-xt    _draw-guard WITH-GUARD ;
: DRW-FILL-RECT       _drw-fillrect-xt _draw-guard WITH-GUARD ;
: DRW-CLEAR-RECT      _drw-clrrect-xt  _draw-guard WITH-GUARD ;
: DRW-TEXT-CENTER      _drw-txtcenter-xt _draw-guard WITH-GUARD ;
: DRW-TEXT-RIGHT       _drw-txtright-xt _draw-guard WITH-GUARD ;
: DRW-REPEAT          _drw-repeat-xt   _draw-guard WITH-GUARD ;
[THEN] [THEN]
