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
\  Text follows the shared text rules (APT-1-TEXT.md): a character is a
\  grapheme cluster, a wide one takes a lead and a continuation cell, and
\  each DRW-TEXT string is laid out as one bidi paragraph in visual order
\  (../text/text-row.f).  Printable ASCII takes a byte path.
\
\  Prefix: DRW- (public), _DRW- (internal)
\  Provider: akashic-tui-draw
\  Dependencies: screen.f, ../text/utf8.f, ../text/cell-width.f,
\                ../text/text-row.f

PROVIDED akashic-tui-draw

REQUIRE screen.f
REQUIRE ../text/utf8.f
REQUIRE ../text/cell-width.f
REQUIRE ../text/text-row.f

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
\   Build a cell from codepoint cp using current style.  WIDE and CONT are
\   not styles; the drawing words set them.
: _DRW-MAKE-CELL  ( cp -- cell )
    _DRW-FG @ _DRW-BG @
    _DRW-ATTRS @ CELL-A-WIDE CELL-A-CONT OR INVERT AND CELL-MAKE ;

CELL-A-WIDE 48 LSHIFT CONSTANT _DRW-C-WIDE

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
VARIABLE _DRW-PLANE-RESIDUE-A 0 _DRW-PLANE-RESIDUE-A !
VARIABLE _DRW-PLANE-RESIDUE-DIRTY-A 0 _DRW-PLANE-RESIDUE-DIRTY-A !
VARIABLE _DRW-PLANE-RESIDUE-DAMAGE-A 0 _DRW-PLANE-RESIDUE-DAMAGE-A !
VARIABLE _DRW-PLANE-REPLACEMENT 0 _DRW-PLANE-REPLACEMENT !
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
    0 _DRW-PLANE-RESIDUE-A !
    0 _DRW-PLANE-RESIDUE-DIRTY-A !
    0 _DRW-PLANE-RESIDUE-DAMAGE-A !
    0 _DRW-PLANE-REPLACEMENT !
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
  ( cells-a residue-a residue-dirty-a residue-damage-a occlusion-a cols rows overlay? replacement? -- row-low row-high wrote? )
    _DRW-PLANE-REPLACEMENT !
    _DRW-PLANE-OVERLAY !
    _DRW-PLANE-ROWS !
    _DRW-PLANE-COLS !
    _DRW-PLANE-OCCLUSION-A !
    _DRW-PLANE-RESIDUE-DAMAGE-A !
    _DRW-PLANE-RESIDUE-DIRTY-A !
    _DRW-PLANE-RESIDUE-A !
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

VARIABLE _DRW-PS-CELL
VARIABLE _DRW-PS-ROW
VARIABLE _DRW-PS-COL

: _DRW-PS-ROW-A  ( plane-a -- row-a )
    _DRW-PS-ROW @ _DRW-PLANE-COLS @ * 8 * + ;

: _DRW-PS-RESIDUE-CHANGED  ( -- )
    -1 _DRW-PLANE-RESIDUE-DIRTY-A @ !
    _DRW-PLANE-RESIDUE-DAMAGE-A @ _DRW-PS-ROW @ + -1 SWAP C! ;

\ A write that is or replaces half of a wide pair keeps every pair whole
\ (screen.f section 8b), in the residue and in the back plane.
: _DRW-PLANE-PAIR-SET  ( -- )
    _DRW-PLANE-REPLACEMENT @ 0= IF
        _DRW-PLANE-RESIDUE-A @ _DRW-PS-ROW-A
        DUP _DRW-PS-COL @ 8 * + @ >R
        _DRW-PS-CELL @ _DRW-PS-COL @ ROT _DRW-PLANE-COLS @ SCR-ROW-PUT
        SWAP - 1 <>
        R> _DRW-PLANE-RESIDUE-A @ _DRW-PLANE-IDX @ 8 * + @ <> OR IF
            _DRW-PS-RESIDUE-CHANGED
        THEN
    THEN
    _DRW-PS-CELL @ _DRW-PS-COL @
    _DRW-PLANE-A @ _DRW-PS-ROW-A _DRW-PLANE-COLS @ SCR-ROW-PUT
    OVER - SWAP
    _DRW-PLANE-OCCLUSION-A @ _DRW-PS-ROW @ _DRW-PLANE-COLS @ * + + SWAP
    _DRW-PLANE-OVERLAY @ FILL ;

CELL-A-WIDE CELL-A-CONT OR 48 LSHIFT CONSTANT _DRW-C-PAIR

\ _DRW-PLANE-SET ( cell row col -- )
\   Write one normalized cell into the borrowed plane, clipped to it.  A
\   cell that neither is nor replaces half of a pair takes the direct path.
: _DRW-PLANE-SET  ( cell row col -- )
    2DUP SWAP 0 _DRW-PLANE-ROWS @ WITHIN
    SWAP 0 _DRW-PLANE-COLS @ WITHIN AND IF
        OVER _DRW-PLANE-TOUCH
        OVER >R SWAP _DRW-PLANE-COLS @ * + DUP _DRW-PLANE-IDX !
        2DUP 8 * _DRW-PLANE-A @ + @ OR
        _DRW-PLANE-REPLACEMENT @ 0= IF
            OVER 8 * _DRW-PLANE-RESIDUE-A @ + @ OR
        THEN
        _DRW-C-PAIR AND IF
            DROP _DRW-PS-CELL ! R> DUP _DRW-PS-ROW !
            _DRW-PLANE-COLS @ * _DRW-PLANE-IDX @ SWAP - _DRW-PS-COL !
            _DRW-PLANE-PAIR-SET EXIT
        THEN
        R> DROP
        _DRW-PLANE-REPLACEMENT @ 0= IF
            2DUP 8 * _DRW-PLANE-RESIDUE-A @ +
            DUP @ 2 PICK <> IF
                -1 _DRW-PLANE-RESIDUE-DIRTY-A @ !
                _DRW-PLANE-IDX @ _DRW-PLANE-COLS @ /
                _DRW-PLANE-RESIDUE-DAMAGE-A @ + -1 SWAP C!
            THEN !
        THEN
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

\ DRW-REPLACEMENT ( ... body-xt -- ... )
\   Paint one independently replaceable semantic layer normally while
\   preserving the ordinary content beneath it.  Optional neutral draw
\   observers select these scopes; applications use the ordinary draw words.
\   Nested scopes and THROW restore the previous depth.  BODY may neither
\   yield nor switch screens.  Foreground DRW-OVERLAY remains independent.
: DRW-REPLACEMENT  ( ... body-xt -- ... )
    DUP 0= IF DROP -1 ABORT" DRW-REPLACEMENT: null body" THEN
    _SCR-WITH-REPLACEMENT ;

\ DRW-CHAR ( cp row col -- )
\   Place the one-scalar character cp at (row, col) using current style.
\   A wide character also takes the cell to its right; when the clip cuts
\   that cell, a space in the style takes its place (APT-1-TEXT Section 6).
\   Coordinates are relative to the current clip region.
\   Silently clipped if out of bounds.
VARIABLE _DRW-CH-CELL

: DRW-CHAR  ( cp row col -- )
    2DUP _DRW-IN-BOUNDS? 0= IF DROP 2DROP EXIT THEN
    ROT _DRW-MAKE-CELL SCR-CELL-NORMALIZE _DRW-CH-CELL !
    _DRW-CH-CELL @ _DRW-C-WIDE AND IF
        2DUP 1+ _DRW-IN-BOUNDS? 0= IF
            _DRW-CH-CELL @ SCR-CELL-SPACE _DRW-CH-CELL !
        THEN
    THEN
    _DRW-CLIP-ON @ IF
        SWAP _DRW-ORIGIN-ROW @ + SWAP _DRW-ORIGIN-COL @ +
    THEN
    _DRW-CH-CELL @ -ROT
    _DRW-PLANE-ACTIVE @ IF _DRW-PLANE-SET ELSE SCR-SET THEN ;

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
VARIABLE _DRW-HLINE-HIGH
VARIABLE _DRW-HLINE-STEP
VARIABLE _DRW-HLINE-CELL
VARIABLE _DRW-HLINE-ABS-ROW
VARIABLE _DRW-HLINE-DX

: _DRW-HLINE-BODY  ( -- )
    _DRW-HLINE-ROW @ DUP _DRW-LOCAL-ROW-LOW <
    SWAP _DRW-LOCAL-ROW-HIGH < 0= OR IF EXIT THEN
    0 _DRW-HLINE-I !
    _DRW-HLINE-COL @ _DRW-HLINE-CUR !
    _DRW-LOCAL-COL-LOW DUP _DRW-HLINE-LOW !
    _DRW-HLINE-CUR @ > IF
        _DRW-HLINE-LOW @ _DRW-HLINE-CUR @ -
        DUP _DRW-HLINE-LEN @ U< 0= IF DROP EXIT THEN
        DUP _DRW-HLINE-I !
        _DRW-HLINE-CUR +!
    THEN
    _DRW-LOCAL-COL-HIGH _DRW-HLINE-HIGH !
    _DRW-HLINE-CP @ _DRW-MAKE-CELL SCR-CELL-NORMALIZE _DRW-HLINE-CELL !
    _DRW-CLIP-ON @ IF
        _DRW-HLINE-ROW @ _DRW-ORIGIN-ROW @ + _DRW-HLINE-ABS-ROW !
        _DRW-ORIGIN-COL @ _DRW-HLINE-DX !
    ELSE
        _DRW-HLINE-ROW @ _DRW-HLINE-ABS-ROW !
        0 _DRW-HLINE-DX !
    THEN
    BEGIN
        _DRW-HLINE-I @ _DRW-HLINE-LEN @ <
        _DRW-HLINE-CUR @ _DRW-HLINE-HIGH @ < AND
    WHILE
        _DRW-HLINE-CELL @
        _DRW-HLINE-STEP @ 2 = IF
            \ A wide character the clip cuts shows a space.
            _DRW-HLINE-CUR @ 1+ _DRW-HLINE-HIGH @ < 0= IF SCR-CELL-SPACE THEN
        THEN
        _DRW-HLINE-ABS-ROW @ _DRW-HLINE-CUR @ _DRW-HLINE-DX @ +
        _DRW-PLANE-SET
        _DRW-HLINE-STEP @ _DRW-HLINE-I +!
        _DRW-HLINE-STEP @ _DRW-HLINE-CUR +!
    REPEAT ;

\ LEN counts cells: a wide character repeats every two.
: DRW-HLINE  ( cp row col len -- )
    _DRW-HLINE-LEN !
    _DRW-HLINE-COL !
    _DRW-HLINE-ROW !
    DUP _DRW-HLINE-CP !
    DUP 0x7F U< IF DROP 1 ELSE CW-CHAR-WIDTH 2 = IF 2 ELSE 1 THEN THEN
    _DRW-HLINE-STEP !
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
\   Lay out a UTF-8 string as one row of text (APT-1-TEXT, text-row.f)
\   and place it from (row, col) in visual order: each character takes
\   its width in cells, and one the clip cuts shows spaces in its style
\   in the cells the clip keeps.  Printable ASCII takes a byte path.
VARIABLE _DRW-TEXT-A
VARIABLE _DRW-TEXT-U
VARIABLE _DRW-TEXT-ROW
VARIABLE _DRW-TEXT-COL
VARIABLE _DRW-TEXT-FLAGS
VARIABLE _DRW-TEXT-LOW
VARIABLE _DRW-TEXT-HIGH
VARIABLE _DRW-TEXT-SKIP
VARIABLE _DRW-TEXT-BUDGET
VARIABLE _DRW-TEXT-ABS-ROW
VARIABLE _DRW-TEXT-ABS-COL
VARIABLE _DRW-TEXT-DX
VARIABLE _DRW-TEXT-KEEP      \ one-cell scalars drawn as they are
VARIABLE _DRW-TEXT-SC-A
VARIABLE _DRW-TEXT-SC-U
VARIABLE _DRW-TEXT-REC
VARIABLE _DRW-TEXT-C
VARIABLE _DRW-TEXT-W

CREATE _DRW-TEXT-UTF8-STATE UTF8-DECODE-STATE-SIZE ALLOT
CREATE _DRW-TROW TROW-SIZE ALLOT  _DRW-TROW TROW-INIT

\ Scratch grown as needed before the plane borrow: the display scalars of
\ one character, and the cells of a laid-out row's visible characters.
VARIABLE _DRW-DS-A    0 _DRW-DS-A !
VARIABLE _DRW-DS-CAP  0 _DRW-DS-CAP !
VARIABLE _DRW-TC-A    0 _DRW-TC-A !
VARIABLE _DRW-TC-CAP  0 _DRW-TC-CAP !

: _DRW-DS-FIT?  ( n -- ok? )
    DUP _DRW-DS-CAP @ > 0= IF DROP -1 EXIT THEN
    DUP 16 MAX DUP 4 * ALLOCATE IF 2DROP DROP 0 EXIT THEN
    _DRW-DS-A @ ?DUP IF FREE THEN
    _DRW-DS-A ! _DRW-DS-CAP ! DROP -1 ;

: _DRW-TC-FIT?  ( n -- ok? )
    DUP _DRW-TC-CAP @ > 0= IF DROP -1 EXIT THEN
    DUP 64 MAX DUP 8 * ALLOCATE IF 2DROP DROP 0 EXIT THEN
    _DRW-TC-A @ ?DUP IF FREE THEN
    _DRW-TC-A ! _DRW-TC-CAP ! DROP -1 ;

: _DRW-TEXT-CLEAR  ( -- )
    0 _DRW-TEXT-A !
    0 _DRW-TEXT-U !
    0 _DRW-TEXT-ROW !
    0 _DRW-TEXT-COL !
    0 _DRW-TEXT-FLAGS !
    0 _DRW-TEXT-LOW !
    0 _DRW-TEXT-HIGH !
    0 _DRW-TEXT-SKIP !
    0 _DRW-TEXT-BUDGET !
    0 _DRW-TEXT-ABS-ROW !
    0 _DRW-TEXT-ABS-COL !
    0 _DRW-TEXT-DX !
    0 _DRW-TEXT-KEEP !
    0 _DRW-TEXT-SC-A !
    0 _DRW-TEXT-SC-U !
    0 _DRW-TEXT-REC !
    0 _DRW-TEXT-C !
    0 _DRW-TEXT-W !
    _DRW-TEXT-UTF8-STATE UTF8-DECODE-STATE-SIZE 0 FILL ;

: _DRW-TEXT-ASCII?  ( -- flag )
    _DRW-TEXT-A @ _DRW-TEXT-U @ OVER + SWAP ?DO
        I C@ 0x20 0x7F WITHIN 0= IF UNLOOP 0 EXIT THEN
    LOOP -1 ;

\ A scalar that is a whole one-cell character at level 0 in any AUTO or
\ LTR paragraph: grapheme break Other with no emoji or conjunct role, width
\ 1, not Default_Ignorable, and not a right-to-left or Arabic-number bidi
\ class (APT-1-TEXT Sections 3, 4, and 11).  Text made only of such
\ scalars, like labels with arrows, ellipses, or box lines, needs no layout.
: _DRW-SIMPLE-PROPS?  ( props -- flag )
    DUP 0x7F AND IF DROP 0 EXIT THEN
    DUP UP-WIDTH 1 <> IF DROP 0 EXIT THEN
    DUP UP-IGNORABLE? IF DROP 0 EXIT THEN
    UP-BIDI DUP UP-BC-R = OVER UP-BC-AL = OR SWAP UP-BC-AN = OR 0= ;

: _DRW-TEXT-SIMPLE?  ( -- flag )
    _DRW-TEXT-A @ _DRW-TEXT-SC-A ! _DRW-TEXT-U @ _DRW-TEXT-SC-U !
    BEGIN _DRW-TEXT-SC-U @ 0> WHILE
        _DRW-TEXT-SC-A @ C@ DUP 0x80 < IF
            \ An ASCII byte needs no decoding.
            0x20 0x7F WITHIN 0= IF 0 EXIT THEN
            1 _DRW-TEXT-SC-A +! -1 _DRW-TEXT-SC-U +!
        ELSE
            DROP
            _DRW-TEXT-SC-A @ _DRW-TEXT-SC-U @ _DRW-TEXT-UTF8-STATE
            UTF8-DECODE-WITH _DRW-TEXT-SC-U ! _DRW-TEXT-SC-A !
            UP-PROPS _DRW-SIMPLE-PROPS? 0= IF 0 EXIT THEN
        THEN
    REPEAT
    _DRW-TEXT-UTF8-STATE UTF8-DECODE-STATE-SIZE 0 FILL -1 ;

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

\ Printable ASCII: one byte per cell.  The body is bounded by the visible
\ column interval; the unseen right suffix is never read.
: _DRW-TEXT-ASCII-BODY  ( -- )
    _DRW-TEXT-ROW-VISIBLE? 0= IF EXIT THEN
    _DRW-TEXT-COL @ _DRW-LOCAL-COL-LOW < IF EXIT THEN
    _DRW-LOCAL-COL-HIGH _DRW-TEXT-COL @ - _DRW-TEXT-U @ MIN
    DUP 0> 0= IF DROP EXIT THEN
    _DRW-CLIP-ON @ IF
        _DRW-TEXT-ROW @ _DRW-ORIGIN-ROW @ + _DRW-TEXT-ABS-ROW !
        _DRW-TEXT-COL @ _DRW-ORIGIN-COL @ + _DRW-TEXT-ABS-COL !
    ELSE
        _DRW-TEXT-ROW @ _DRW-TEXT-ABS-ROW !
        _DRW-TEXT-COL @ _DRW-TEXT-ABS-COL !
    THEN
    _DRW-TEXT-A @ SWAP OVER + SWAP ?DO
        I C@ _DRW-MAKE-CELL
        _DRW-TEXT-ABS-ROW @ _DRW-TEXT-ABS-COL @ _DRW-PLANE-SET
        1 _DRW-TEXT-ABS-COL +!
    LOOP ;

\ One scalar per cell: text of one-cell scalars, and the fallback when a
\ row cannot be laid out, where any scalar but printable ASCII shows as
\ U+FFFD.
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
        _DRW-TEXT-KEEP @ 0= IF
            DUP 0x20 0x7F WITHIN 0= IF DROP 0xFFFD THEN
        THEN
        _DRW-MAKE-CELL
        _DRW-TEXT-ABS-ROW @ _DRW-TEXT-ABS-COL @
        _DRW-PLANE-SET
        1 _DRW-TEXT-COL +!
        1 _DRW-TEXT-ABS-COL +!
        -1 _DRW-TEXT-BUDGET +!
    REPEAT ;

\ The cell of the laid-out character REC: its display scalars, one in the
\ codepoint field or several in the screen's cluster pool.
: _DRW-TEXT-CHAR-CELL  ( rec -- cell )
    DUP TROW.WIDTH >R
    DUP TROW.SCALARS 1 = IF
        TROW.CP0
    ELSE
        DUP TROW.SCALARS _DRW-DS-FIT? IF
            _DRW-DS-A @ _DRW-TROW TROW-DISPLAY
            _DRW-DS-A @ SWAP SCR-CLUSTER
        ELSE
            DROP 0xFFFD
        THEN
    THEN
    _DRW-MAKE-CELL
    R> 2 = IF _DRW-C-WIDE OR THEN ;

\ Before the plane borrow, the cell of every visible character: the borrow
\ itself neither allocates nor calls the screen.
: _DRW-TEXT-PREPARE?  ( -- ok? )
    _DRW-TROW TROW-VISIBLE DUP _DRW-TC-FIT? 0= IF DROP 0 EXIT THEN
    0 ?DO
        I _DRW-TROW TROW-VCHAR _DRW-TEXT-CHAR-CELL
        _DRW-TC-A @ I 8 * + !
    LOOP -1 ;

\ A character the clip cuts shows a space in each cell the clip keeps.
: _DRW-TEXT-CUT  ( -- )
    _DRW-TEXT-W @ 0 ?DO
        _DRW-TEXT-C @ I +
        DUP _DRW-TEXT-LOW @ _DRW-TEXT-HIGH @ WITHIN IF
            32 _DRW-MAKE-CELL _DRW-TEXT-ABS-ROW @ ROT _DRW-TEXT-DX @ +
            _DRW-PLANE-SET
        ELSE DROP THEN
    LOOP ;

: _DRW-TEXT-ROW-BODY  ( -- )
    _DRW-TEXT-ROW-VISIBLE? 0= IF EXIT THEN
    _DRW-LOCAL-COL-LOW _DRW-TEXT-LOW !
    _DRW-LOCAL-COL-HIGH _DRW-TEXT-HIGH !
    _DRW-CLIP-ON @ IF
        _DRW-TEXT-ROW @ _DRW-ORIGIN-ROW @ + _DRW-TEXT-ABS-ROW !
        _DRW-ORIGIN-COL @ _DRW-TEXT-DX !
    ELSE
        _DRW-TEXT-ROW @ _DRW-TEXT-ABS-ROW !
        0 _DRW-TEXT-DX !
    THEN
    _DRW-TROW TROW-VISIBLE 0 ?DO
        I _DRW-TROW TROW-VCHAR _DRW-TEXT-REC !
        _DRW-TEXT-COL @ _DRW-TEXT-REC @ TROW.COLUMN + _DRW-TEXT-C !
        _DRW-TEXT-REC @ TROW.WIDTH _DRW-TEXT-W !
        _DRW-TEXT-C @ _DRW-TEXT-HIGH @ < 0= IF LEAVE THEN
        _DRW-TEXT-C @ _DRW-TEXT-W @ + _DRW-TEXT-LOW @ > IF
            _DRW-TEXT-C @ _DRW-TEXT-LOW @ < 0=
            _DRW-TEXT-C @ _DRW-TEXT-W @ + _DRW-TEXT-HIGH @ > 0= AND IF
                _DRW-TC-A @ I 8 * + @
                _DRW-TEXT-ABS-ROW @ _DRW-TEXT-C @ _DRW-TEXT-DX @ +
                _DRW-PLANE-SET
            ELSE
                _DRW-TEXT-CUT
            THEN
        THEN
    LOOP ;

: _DRW-TEXT-RUN  ( -- )
    _DRW-TEXT-U @ 0> 0= IF EXIT THEN
    _DRW-TEXT-ASCII? IF
        _DRW-TEXT-SKIP-LEFT IF
            ['] _DRW-TEXT-ASCII-BODY _DRW-WITH-BACK-MUTATION
        THEN EXIT
    THEN
    _DRW-TEXT-SIMPLE? IF
        -1 _DRW-TEXT-KEEP !
        _DRW-TEXT-SKIP-LEFT IF
            ['] _DRW-TEXT-BODY _DRW-WITH-BACK-MUTATION
        THEN EXIT
    THEN
    _DRW-TEXT-A @ _DRW-TEXT-U @ _DRW-TEXT-FLAGS @ BIDI-AUTO
    _DRW-TROW TROW-LAYOUT IF
        _DRW-TEXT-PREPARE? IF
            ['] _DRW-TEXT-ROW-BODY _DRW-WITH-BACK-MUTATION EXIT
        THEN
    THEN
    _DRW-TEXT-SKIP-LEFT IF
        ['] _DRW-TEXT-BODY _DRW-WITH-BACK-MUTATION
    THEN ;

: _DRW-TEXT-TRANSACTION  ( -- )
    ['] _DRW-TEXT-RUN CATCH
    _DRW-TEXT-CLEAR
    ?DUP IF THROW THEN ;

: _DRW-TEXT-START  ( addr len row col flags -- )
    _DRW-TEXT-FLAGS !
    _DRW-TEXT-COL !
    _DRW-TEXT-ROW !
    _DRW-TEXT-U !
    _DRW-TEXT-A !
    _DRW-TEXT-TRANSACTION ;

: DRW-TEXT  ( addr len row col -- )
    0 _DRW-TEXT-START ;

\ Network, document, and Agent text must not place terminal controls or
\ invisible direction overrides into the screen buffer.  Keep the source
\ bytes unchanged in their owning model and project only at this final
\ presentation boundary: controls show as U+FFFD, as for all text, and
\ explicit embeddings, overrides, and isolates are ignored.
: DRW-TEXT-UNTRUSTED  ( addr len row col -- )
    TROW-F-UNTRUSTED _DRW-TEXT-START ;

\ _DRW-TEXT-WIDTH ( addr len -- n )
\   The string's width in cells.
: _DRW-TEXT-WIDTH  ( addr len -- n )
    CW-SWIDTH ;

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
    2DUP _DRW-TEXT-WIDTH              \ ( addr len width )
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
    2DUP _DRW-TEXT-WIDTH              \ ( addr len width )
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
' DRW-REPLACEMENT     CONSTANT _drw-replacement-xt
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
: DRW-REPLACEMENT     _drw-replacement-xt _draw-guard WITH-GUARD ;
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
