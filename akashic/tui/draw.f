\ =====================================================================
\  akashic/tui/draw.f — Cell-Level Drawing Primitives
\ =====================================================================
\
\  Convenience words for common drawing operations on the current
\  screen's back buffer: horizontal / vertical lines, filled rectangles,
\  text strings placed at a position.  DRW-OVERLAY brackets ordinary
\  foreground paint so retained projections can respect final painter order.
\  Operates on the screen set by SCR-USE.
\
\  A "current style" (fg, bg, attrs) is maintained so callers don't
\  need to pass three extra values on every draw call.
\
\  All coordinates are 0-based (row, col).  Drawing is clipped to the
\  screen dimensions — writes outside the screen are silently discarded.
\
\  Prefix: DRW- (public), _DRW- (internal)
\  Provider: akashic-tui-draw
\  Dependencies: screen.f, ../text/utf8.f, ../text/cell-width.f

PROVIDED akashic-tui-draw

REQUIRE screen.f
REQUIRE ../text/utf8.f
REQUIRE ../text/cell-width.f

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

\ Save / Restore — widgets call DRW-STYLE-RESTORE to return to
\ the "normal" style after drawing a highlight (selected/cursor).
\ The UIDL paint path calls DRW-STYLE-SAVE after applying the
\ sidecar style so widgets inherit theme colours.
VARIABLE _DRW-SAVED-FG  VARIABLE _DRW-SAVED-BG  VARIABLE _DRW-SAVED-A

: DRW-STYLE-SAVE  ( -- )
    _DRW-FG @ _DRW-SAVED-FG !
    _DRW-BG @ _DRW-SAVED-BG !
    _DRW-ATTRS @ _DRW-SAVED-A ! ;

: DRW-STYLE-RESTORE  ( -- )
    _DRW-SAVED-FG @ _DRW-FG !
    _DRW-SAVED-BG @ _DRW-BG !
    _DRW-SAVED-A @ _DRW-ATTRS ! ;

\ _DRW-MAKE-CELL ( cp -- cell )
\   Build a cell from codepoint cp using current style.
: _DRW-MAKE-CELL  ( cp -- cell )
    _DRW-FG @ _DRW-BG @ _DRW-ATTRS @ CELL-MAKE ;

\ =====================================================================
\ 2. Clipping helpers (region-aware)
\ =====================================================================
\
\  The origin variables translate caller coordinates.  The clip variables
\  describe an independent screen-absolute rectangle.  Keeping the two
\  separate lets a child retain its local (0,0) while a parent clips any
\  edge of the child's drawing.  region.f sets both when RGN-USE is called.

VARIABLE _DRW-ORIGIN-ROW  0 _DRW-ORIGIN-ROW ! \ coordinate origin row
VARIABLE _DRW-ORIGIN-COL  0 _DRW-ORIGIN-COL ! \ coordinate origin column
VARIABLE _DRW-CLIP-ROW    0 _DRW-CLIP-ROW !   \ absolute clip top
VARIABLE _DRW-CLIP-COL    0 _DRW-CLIP-COL !   \ absolute clip left
VARIABLE _DRW-CLIP-H      0 _DRW-CLIP-H !     \ clip height (0 = SCR-H)
VARIABLE _DRW-CLIP-W      0 _DRW-CLIP-W !     \ clip width  (0 = SCR-W)
VARIABLE _DRW-CLIP-ON     0 _DRW-CLIP-ON !    \ 0 = no clip, non-0 = clip active

\ Bulk primitives borrow the current screen plane only for one synchronous
\ primitive body.  The cached address is never exposed to app callbacks and
\ is scrubbed on both normal and exceptional return.
VARIABLE _DRW-PLANE-A       0 _DRW-PLANE-A !
VARIABLE _DRW-PLANE-OCCLUSION-A 0 _DRW-PLANE-OCCLUSION-A !
VARIABLE _DRW-PLANE-COLS    0 _DRW-PLANE-COLS !
VARIABLE _DRW-PLANE-ROWS    0 _DRW-PLANE-ROWS !
VARIABLE _DRW-PLANE-OVERLAY 0 _DRW-PLANE-OVERLAY !
VARIABLE _DRW-PLANE-TOUCH-LOW  0 _DRW-PLANE-TOUCH-LOW !
VARIABLE _DRW-PLANE-TOUCH-HIGH 0 _DRW-PLANE-TOUCH-HIGH !
VARIABLE _DRW-PLANE-ACTIVE  0 _DRW-PLANE-ACTIVE !
VARIABLE _DRW-PLANE-WROTE   0 _DRW-PLANE-WROTE !
VARIABLE _DRW-PLANE-BODY    0 _DRW-PLANE-BODY !
VARIABLE _DRW-PLANE-IDX     0 _DRW-PLANE-IDX !

: _DRW-SCREEN-ROWS  ( -- rows )
    _DRW-PLANE-ACTIVE @ IF _DRW-PLANE-ROWS @ ELSE SCR-H THEN ;

: _DRW-SCREEN-COLS  ( -- cols )
    _DRW-PLANE-ACTIVE @ IF _DRW-PLANE-COLS @ ELSE SCR-W THEN ;

\ Effective clip dimensions — when clip is off, use screen size.
: _DRW-CLIP-ROWS  ( -- n )
    _DRW-CLIP-ON @ IF _DRW-CLIP-H @ ELSE _DRW-SCREEN-ROWS THEN ;

: _DRW-CLIP-COLS  ( -- n )
    _DRW-CLIP-ON @ IF _DRW-CLIP-W @ ELSE _DRW-SCREEN-COLS THEN ;

: _DRW-LOCAL-ROW-LOW  ( -- row-inclusive )
    _DRW-CLIP-ON @ IF
        _DRW-CLIP-ROW @ _DRW-ORIGIN-ROW @ -
        _DRW-PLANE-ACTIVE @ IF
            0 _DRW-ORIGIN-ROW @ - MAX
        THEN
    ELSE
        0
    THEN ;

: _DRW-LOCAL-ROW-HIGH  ( -- row-exclusive )
    _DRW-CLIP-ON @ IF
        _DRW-CLIP-ROW @ _DRW-CLIP-H @ + _DRW-ORIGIN-ROW @ -
        _DRW-PLANE-ACTIVE @ IF
            _DRW-PLANE-ROWS @ _DRW-ORIGIN-ROW @ - MIN
        THEN
    ELSE
        _DRW-SCREEN-ROWS
    THEN ;

: _DRW-LOCAL-COL-LOW  ( -- col-inclusive )
    _DRW-CLIP-ON @ IF
        _DRW-CLIP-COL @ _DRW-ORIGIN-COL @ -
        _DRW-PLANE-ACTIVE @ IF
            0 _DRW-ORIGIN-COL @ - MAX
        THEN
    ELSE
        0
    THEN ;

: _DRW-LOCAL-COL-HIGH  ( -- col-exclusive )
    _DRW-CLIP-ON @ IF
        _DRW-CLIP-COL @ _DRW-CLIP-W @ + _DRW-ORIGIN-COL @ -
        _DRW-PLANE-ACTIVE @ IF
            _DRW-PLANE-COLS @ _DRW-ORIGIN-COL @ - MIN
        THEN
    ELSE
        _DRW-SCREEN-COLS
    THEN ;

\ _DRW-IN-BOUNDS? ( row col -- flag )
\   Translate (row, col) through the current origin, then test the resulting
\   screen position against the independent effective clip rectangle.
: _DRW-IN-BOUNDS?  ( row col -- flag )
    _DRW-CLIP-ON @ IF
        SWAP _DRW-ORIGIN-ROW @ +
        SWAP _DRW-ORIGIN-COL @ +       ( abs-row abs-col )
        SWAP _DRW-CLIP-ROW @
             _DRW-CLIP-ROW @ _DRW-CLIP-H @ + WITHIN
        SWAP _DRW-CLIP-COL @
             _DRW-CLIP-COL @ _DRW-CLIP-W @ + WITHIN
        AND
    ELSE
        SWAP 0 _DRW-SCREEN-ROWS WITHIN
        SWAP 0 _DRW-SCREEN-COLS WITHIN
        AND
    THEN ;

\ WITHIN ( n lo hi -- flag ) is standard: true if lo <= n < hi.
\ If not available, fall back to manual check.  Megapad-64 KDOS has it.

\ =====================================================================
\ 3. Drawing words
\ =====================================================================

: _DRW-PLANE-CLEAR  ( -- )
    0 _DRW-PLANE-A !
    0 _DRW-PLANE-OCCLUSION-A !
    0 _DRW-PLANE-COLS !
    0 _DRW-PLANE-ROWS !
    0 _DRW-PLANE-OVERLAY !
    0 _DRW-PLANE-TOUCH-LOW !
    0 _DRW-PLANE-TOUCH-HIGH !
    0 _DRW-PLANE-ACTIVE !
    0 _DRW-PLANE-WROTE !
    0 _DRW-PLANE-BODY !
    0 _DRW-PLANE-IDX ! ;

: _DRW-PLANE-CALL
  ( cells-a occlusion-a cols rows overlay? -- row-low row-high wrote? )
    _DRW-PLANE-OVERLAY !
    _DRW-PLANE-ROWS !
    _DRW-PLANE-COLS !
    _DRW-PLANE-OCCLUSION-A !
    _DRW-PLANE-A !
    0 _DRW-PLANE-TOUCH-LOW !
    0 _DRW-PLANE-TOUCH-HIGH !
    0 _DRW-PLANE-WROTE !
    -1 _DRW-PLANE-ACTIVE !
    _DRW-PLANE-BODY @ CATCH DUP IF
        _DRW-PLANE-CLEAR
        THROW
    THEN
    DROP
    _DRW-PLANE-TOUCH-LOW @
    _DRW-PLANE-TOUCH-HIGH @
    _DRW-PLANE-WROTE @
    _DRW-PLANE-CLEAR ;

\ Internal primitive bodies have no stack inputs: each public primitive
\ saves its bounded arguments before entering this scope.  Nested primitive
\ calls reuse the same borrow, while a top-level call obtains the guarded
\ mutable plane exactly once.
: _DRW-BACK-MUTATION-CALL  ( -- )
    ['] _DRW-PLANE-CALL SCR-WITH-BACK-MUTATION ;

: _DRW-WITH-BACK-MUTATION  ( body-xt -- )
    _DRW-PLANE-ACTIVE @ IF EXECUTE EXIT THEN
    _DRW-PLANE-BODY !
    ['] _DRW-BACK-MUTATION-CALL CATCH DUP IF
        _DRW-PLANE-CLEAR
        THROW
    THEN DROP ;

: _DRW-PLANE-TOUCH  ( row -- )
    _DRW-PLANE-WROTE @ IF
        \ Horizontal spans and text normally remain on the first row.
        DUP _DRW-PLANE-TOUCH-LOW @ = IF DROP EXIT THEN
        \ Vertical spans normally append the next row to the interval.
        DUP _DRW-PLANE-TOUCH-HIGH @ = IF
            DROP 1 _DRW-PLANE-TOUCH-HIGH +! EXIT
        THEN
        DUP _DRW-PLANE-TOUCH-LOW @ MIN _DRW-PLANE-TOUCH-LOW !
        1+ _DRW-PLANE-TOUCH-HIGH @ MAX _DRW-PLANE-TOUCH-HIGH !
        EXIT
    THEN
    DUP _DRW-PLANE-TOUCH-LOW !
    1+ _DRW-PLANE-TOUCH-HIGH !
    -1 _DRW-PLANE-WROTE ! ;

: _DRW-PLANE-SET  ( cell row col -- )
    2DUP SWAP 0 _DRW-PLANE-ROWS @ WITHIN
    SWAP 0 _DRW-PLANE-COLS @ WITHIN AND IF
        OVER _DRW-PLANE-TOUCH
        SWAP _DRW-PLANE-COLS @ * + DUP _DRW-PLANE-IDX !
        8 * _DRW-PLANE-A @ + !
        _DRW-PLANE-OVERLAY @
        _DRW-PLANE-OCCLUSION-A @ _DRW-PLANE-IDX @ + C!
    ELSE
        2DROP DROP
    THEN ;

\ DRW-OVERLAY ( body-xt -- )
\   Run one synchronous post-semantic foreground layer.  Every DRW primitive
\   and direct SCR-SET/SCR-FILL write in BODY assigns foreground provenance
\   beside the persistent BACK plane.  Nested scopes and THROW both restore
\   the prior depth; later ordinary writes clear provenance cell by cell.
\   BODY must not yield or switch the selected screen.
: DRW-OVERLAY  ( body-xt -- )
    DUP 0= IF DROP -1 ABORT" DRW-OVERLAY: null body" THEN
    _SCR-WITH-OCCLUSION ;

\ DRW-CHAR ( cp row col -- )
\   Place one character at (row, col) using current style.
\   Coordinates are relative to the current clip region.
\   Silently clipped if out of bounds.
: DRW-CHAR  ( cp row col -- )
    2DUP _DRW-IN-BOUNDS? IF
        _DRW-CLIP-ON @ IF
            SWAP _DRW-ORIGIN-ROW @ + SWAP _DRW-ORIGIN-COL @ +
        THEN
        ROT _DRW-MAKE-CELL -ROT
        _DRW-PLANE-ACTIVE @ IF _DRW-PLANE-SET ELSE SCR-SET THEN
    ELSE
        DROP DROP DROP
    THEN ;

\ DRW-HLINE ( cp row col len -- )
\   Draw a horizontal line of character cp starting at (row, col).
\   Clipped to screen width.  Nonpositive lengths are no-ops.
VARIABLE _DRW-HLINE-ROW
VARIABLE _DRW-HLINE-CP
VARIABLE _DRW-HLINE-COL
VARIABLE _DRW-HLINE-LEN
VARIABLE _DRW-HLINE-I
VARIABLE _DRW-HLINE-CUR
VARIABLE _DRW-HLINE-LOW

: _DRW-HLINE-BODY  ( -- )
    0 _DRW-HLINE-I !
    _DRW-HLINE-COL @ _DRW-HLINE-CUR !
    _DRW-LOCAL-COL-LOW DUP _DRW-HLINE-LOW !
    _DRW-HLINE-CUR @ > IF
        _DRW-HLINE-LOW @ _DRW-HLINE-CUR @ -
        DUP _DRW-HLINE-LEN @ U< 0= IF DROP EXIT THEN
        DUP _DRW-HLINE-I !
        _DRW-HLINE-CUR +!
    THEN
    BEGIN
        _DRW-HLINE-I @ _DRW-HLINE-LEN @ <
        _DRW-HLINE-CUR @ _DRW-LOCAL-COL-HIGH < AND
    WHILE
        _DRW-HLINE-CP @
        _DRW-HLINE-ROW @
        _DRW-HLINE-CUR @
        DRW-CHAR
        1 _DRW-HLINE-I +!
        1 _DRW-HLINE-CUR +!
    REPEAT ;

: DRW-HLINE  ( cp row col len -- )
    _DRW-HLINE-LEN !
    _DRW-HLINE-COL !
    _DRW-HLINE-ROW !
    _DRW-HLINE-CP !
    _DRW-HLINE-LEN @ 0> IF
        ['] _DRW-HLINE-BODY _DRW-WITH-BACK-MUTATION
    THEN ;

\ DRW-VLINE ( cp row col len -- )
\   Draw a vertical line of character cp starting at (row, col).
\   Clipped to screen height.  Nonpositive lengths are no-ops.
VARIABLE _DRW-VLINE-COL
VARIABLE _DRW-VLINE-CP
VARIABLE _DRW-VLINE-ROW
VARIABLE _DRW-VLINE-LEN
VARIABLE _DRW-VLINE-I
VARIABLE _DRW-VLINE-CUR
VARIABLE _DRW-VLINE-LOW

: _DRW-VLINE-BODY  ( -- )
    0 _DRW-VLINE-I !
    _DRW-VLINE-ROW @ _DRW-VLINE-CUR !
    _DRW-LOCAL-ROW-LOW DUP _DRW-VLINE-LOW !
    _DRW-VLINE-CUR @ > IF
        _DRW-VLINE-LOW @ _DRW-VLINE-CUR @ -
        DUP _DRW-VLINE-LEN @ U< 0= IF DROP EXIT THEN
        DUP _DRW-VLINE-I !
        _DRW-VLINE-CUR +!
    THEN
    BEGIN
        _DRW-VLINE-I @ _DRW-VLINE-LEN @ <
        _DRW-VLINE-CUR @ _DRW-LOCAL-ROW-HIGH < AND
    WHILE
        _DRW-VLINE-CP @
        _DRW-VLINE-CUR @
        _DRW-VLINE-COL @
        DRW-CHAR
        1 _DRW-VLINE-I +!
        1 _DRW-VLINE-CUR +!
    REPEAT ;

: DRW-VLINE  ( cp row col len -- )
    _DRW-VLINE-LEN !
    _DRW-VLINE-COL !
    _DRW-VLINE-ROW !
    _DRW-VLINE-CP !
    _DRW-VLINE-LEN @ 0> IF
        ['] _DRW-VLINE-BODY _DRW-WITH-BACK-MUTATION
    THEN ;

\ DRW-FILL-RECT ( cp row col h w -- )
\   Fill a rectangle with character cp.
VARIABLE _DRW-FR-COL
VARIABLE _DRW-FR-W
VARIABLE _DRW-FR-CP
VARIABLE _DRW-FR-ROW
VARIABLE _DRW-FR-H
VARIABLE _DRW-FR-I
VARIABLE _DRW-CA-START
VARIABLE _DRW-CA-LEN
VARIABLE _DRW-CA-LOW
VARIABLE _DRW-CA-HIGH

: _DRW-CLIP-AXIS  ( start length low high -- start' length' flag )
    _DRW-CA-HIGH ! _DRW-CA-LOW ! _DRW-CA-LEN ! _DRW-CA-START !
    _DRW-CA-LEN @ 0> 0= IF 0 0 0 EXIT THEN
    _DRW-CA-START @ _DRW-CA-HIGH @ >= IF 0 0 0 EXIT THEN
    _DRW-CA-START @ _DRW-CA-LOW @ < IF
        _DRW-CA-LOW @ _DRW-CA-START @ -
        DUP _DRW-CA-LEN @ U< 0= IF DROP 0 0 0 EXIT THEN
        _DRW-CA-LEN @ SWAP - _DRW-CA-LEN !
        _DRW-CA-LOW @ _DRW-CA-START !
    THEN
    _DRW-CA-HIGH @ _DRW-CA-START @ -
        _DRW-CA-LEN @ MIN _DRW-CA-LEN !
    _DRW-CA-START @ _DRW-CA-LEN @ DUP 0> ;

: _DRW-PHYSICAL-ROW-LOW  ( -- row-inclusive )
    _DRW-LOCAL-ROW-LOW
    0 _DRW-ORIGIN-ROW @ - MAX ;

: _DRW-PHYSICAL-ROW-HIGH  ( -- row-exclusive )
    _DRW-LOCAL-ROW-HIGH
    _DRW-SCREEN-ROWS _DRW-ORIGIN-ROW @ - MIN ;

: _DRW-PHYSICAL-COL-LOW  ( -- column-inclusive )
    _DRW-LOCAL-COL-LOW
    0 _DRW-ORIGIN-COL @ - MAX ;

: _DRW-PHYSICAL-COL-HIGH  ( -- column-exclusive )
    _DRW-LOCAL-COL-HIGH
    _DRW-SCREEN-COLS _DRW-ORIGIN-COL @ - MIN ;

: DRW-FILL-RECT  ( cp row col h w -- )
    _DRW-FR-W ! _DRW-FR-H ! _DRW-FR-COL !
    _DRW-FR-ROW ! _DRW-FR-CP !
    _DRW-FR-H @ 0> _DRW-FR-W @ 0> AND 0= IF EXIT THEN
    _DRW-FR-ROW @ _DRW-FR-H @
        _DRW-PHYSICAL-ROW-LOW _DRW-PHYSICAL-ROW-HIGH _DRW-CLIP-AXIS
    0= IF 2DROP EXIT THEN
    _DRW-FR-H ! _DRW-FR-ROW !
    _DRW-FR-COL @ _DRW-FR-W @
        _DRW-PHYSICAL-COL-LOW _DRW-PHYSICAL-COL-HIGH _DRW-CLIP-AXIS
    0= IF 2DROP EXIT THEN
    _DRW-FR-W ! _DRW-FR-COL !
    0 _DRW-FR-I !
    BEGIN _DRW-FR-I @ _DRW-FR-H @ < WHILE
        _DRW-FR-CP @
        _DRW-FR-ROW @ _DRW-FR-I @ +
        _DRW-FR-COL @
        _DRW-FR-W @
        DRW-HLINE
        1 _DRW-FR-I +!
    REPEAT ;

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
VARIABLE _DRW-TEXT-A
VARIABLE _DRW-TEXT-U
VARIABLE _DRW-TEXT-ROW
VARIABLE _DRW-TEXT-COL
VARIABLE _DRW-TEXT-UNTRUSTED
VARIABLE _DRW-TEXT-LOW
VARIABLE _DRW-TEXT-HIGH
VARIABLE _DRW-TEXT-SKIP
VARIABLE _DRW-TEXT-BUDGET
VARIABLE _DRW-TEXT-ABS-ROW
VARIABLE _DRW-TEXT-ABS-COL

CREATE _DRW-TEXT-UTF8-STATE UTF8-DECODE-STATE-SIZE ALLOT
CREATE _DRW-TEXT-CW-STATE CW-STATE-SIZE ALLOT

: _DRW-TEXT-CLEAR  ( -- )
    0 _DRW-TEXT-A !
    0 _DRW-TEXT-U !
    0 _DRW-TEXT-ROW !
    0 _DRW-TEXT-COL !
    0 _DRW-TEXT-UNTRUSTED !
    0 _DRW-TEXT-LOW !
    0 _DRW-TEXT-HIGH !
    0 _DRW-TEXT-SKIP !
    0 _DRW-TEXT-BUDGET !
    0 _DRW-TEXT-ABS-ROW !
    0 _DRW-TEXT-ABS-COL !
    _DRW-TEXT-UTF8-STATE UTF8-DECODE-STATE-SIZE 0 FILL
    _DRW-TEXT-CW-STATE CW-STATE-SIZE 0 FILL ;

: _DRW-TEXT-NEXT  ( -- cp )
    _DRW-TEXT-A @ _DRW-TEXT-U @ _DRW-TEXT-UTF8-STATE
    UTF8-DECODE-WITH
    _DRW-TEXT-U !
    _DRW-TEXT-A ! ;

\ Decode any off-left prefix before borrowing the screen.  The unsigned
\ distance proof bounds the maximum codepoint count by the remaining source
\ bytes, so even an extreme negative column is rejected or skipped without
\ wrapping a signed loop count.
: _DRW-TEXT-SKIP-LEFT  ( -- drawable? )
    _DRW-CLIP-ON @ IF
        _DRW-CLIP-COL @ _DRW-ORIGIN-COL @ -
        0 _DRW-ORIGIN-COL @ - MAX
    ELSE
        0
    THEN
    DUP _DRW-TEXT-LOW !
    _DRW-TEXT-COL @ > IF
        _DRW-TEXT-LOW @ _DRW-TEXT-COL @ -
        DUP _DRW-TEXT-U @ U< 0= IF DROP 0 EXIT THEN
        _DRW-TEXT-SKIP !
        BEGIN
            _DRW-TEXT-SKIP @ 0>
            _DRW-TEXT-U @ 0> AND
        WHILE
            _DRW-TEXT-NEXT DROP
            -1 _DRW-TEXT-SKIP +!
        REPEAT
        _DRW-TEXT-SKIP @ IF 0 EXIT THEN
        _DRW-TEXT-LOW @ _DRW-TEXT-COL !
    THEN
    _DRW-TEXT-U @ 0> ;

: _DRW-TEXT-ROW-VISIBLE?  ( -- flag )
    _DRW-TEXT-ROW @ DUP _DRW-LOCAL-ROW-LOW >=
    SWAP _DRW-LOCAL-ROW-HIGH < AND ;

\ The mutable-plane body is bounded by the actual row and visible column
\ interval presented by this borrow.  Caller-state codecs and direct plane
\ stores are non-yielding; the unseen right suffix is never decoded.
: _DRW-TEXT-BODY  ( -- )
    _DRW-TEXT-ROW-VISIBLE? 0= IF EXIT THEN
    _DRW-TEXT-COL @ _DRW-LOCAL-COL-LOW < IF EXIT THEN
    _DRW-LOCAL-COL-HIGH _DRW-TEXT-HIGH !
    _DRW-TEXT-COL @ _DRW-TEXT-HIGH @ >= IF EXIT THEN
    _DRW-PLANE-COLS @ _DRW-TEXT-BUDGET !
    _DRW-CLIP-ON @ IF
        _DRW-TEXT-ROW @ _DRW-ORIGIN-ROW @ + _DRW-TEXT-ABS-ROW !
        _DRW-TEXT-COL @ _DRW-ORIGIN-COL @ + _DRW-TEXT-ABS-COL !
    ELSE
        _DRW-TEXT-ROW @ _DRW-TEXT-ABS-ROW !
        _DRW-TEXT-COL @ _DRW-TEXT-ABS-COL !
    THEN
    BEGIN
        _DRW-TEXT-U @ 0>
        _DRW-TEXT-COL @ _DRW-TEXT-HIGH @ < AND
        _DRW-TEXT-BUDGET @ 0> AND
    WHILE
        _DRW-TEXT-NEXT
        _DRW-TEXT-UNTRUSTED @ IF
            _DRW-TEXT-CW-STATE CW-CELL-CP-WITH
        THEN
        _DRW-MAKE-CELL
        _DRW-TEXT-ABS-ROW @ _DRW-TEXT-ABS-COL @
        _DRW-PLANE-SET
        1 _DRW-TEXT-COL +!
        1 _DRW-TEXT-ABS-COL +!
        -1 _DRW-TEXT-BUDGET +!
    REPEAT ;

: _DRW-TEXT-RUN  ( -- )
    _DRW-TEXT-U @ 0> IF
        _DRW-TEXT-SKIP-LEFT IF
            ['] _DRW-TEXT-BODY _DRW-WITH-BACK-MUTATION
        THEN
    THEN ;

: _DRW-TEXT-TRANSACTION  ( -- )
    ['] _DRW-TEXT-RUN CATCH
    _DRW-TEXT-CLEAR
    ?DUP IF THROW THEN ;

: _DRW-TEXT-START  ( addr len row col untrusted? -- )
    _DRW-TEXT-UNTRUSTED !
    _DRW-TEXT-COL !
    _DRW-TEXT-ROW !
    _DRW-TEXT-U !
    _DRW-TEXT-A !
    _DRW-TEXT-TRANSACTION ;

: DRW-TEXT  ( addr len row col -- )
    0 _DRW-TEXT-START ;

\ Network, document, and Agent text must not be allowed to place terminal
\ controls or invisible direction overrides into the screen buffer.  Keep the
\ source bytes unchanged in their owning model and project only at this final
\ presentation boundary.  The screen has no continuation-cell or grapheme
\ model, so every decoded codepoint must occupy exactly one isolated cell:
\ controls, nonspacing/joining codepoints, and wide codepoints become U+FFFD.
: DRW-TEXT-UNTRUSTED  ( addr len row col -- )
    -1 _DRW-TEXT-START ;

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
REQUIRE ../concurrency/guard.f
GUARD _draw-guard

' DRW-FG!             CONSTANT _drw-fgset-xt
' DRW-BG!             CONSTANT _drw-bgset-xt
' DRW-ATTR!           CONSTANT _drw-attrset-xt
' DRW-STYLE!          CONSTANT _drw-styleset-xt
' DRW-STYLE-RESET     CONSTANT _drw-stylerst-xt
' DRW-OVERLAY         CONSTANT _drw-overlay-xt
' DRW-CHAR            CONSTANT _drw-char-xt
' DRW-TEXT            CONSTANT _drw-text-xt
' DRW-TEXT-UNTRUSTED  CONSTANT _drw-text-untrusted-xt
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
: DRW-OVERLAY         _drw-overlay-xt   _draw-guard WITH-GUARD ;
: DRW-CHAR            _drw-char-xt     _draw-guard WITH-GUARD ;
: DRW-TEXT            _drw-text-xt     _draw-guard WITH-GUARD ;
: DRW-TEXT-UNTRUSTED  _drw-text-untrusted-xt
    _draw-guard WITH-GUARD ;
: DRW-HLINE           _drw-hline-xt    _draw-guard WITH-GUARD ;
: DRW-VLINE           _drw-vline-xt    _draw-guard WITH-GUARD ;
: DRW-FILL-RECT       _drw-fillrect-xt _draw-guard WITH-GUARD ;
: DRW-CLEAR-RECT      _drw-clrrect-xt  _draw-guard WITH-GUARD ;
: DRW-TEXT-CENTER      _drw-txtcenter-xt _draw-guard WITH-GUARD ;
: DRW-TEXT-RIGHT       _drw-txtright-xt _draw-guard WITH-GUARD ;
: DRW-REPEAT          _drw-repeat-xt   _draw-guard WITH-GUARD ;
[THEN] [THEN]
