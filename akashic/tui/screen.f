\ =====================================================================
\  akashic/tui/screen.f — Virtual Screen Buffer (double-buffered)
\ =====================================================================
\
\  Double-buffered character-cell screen.  Widgets write to the back
\  buffer.  SCR-FLUSH diffs front vs. back and projects changed cells
\  through a transactional backend.  ANSI is the constructed default;
\  outer composition may bind another transactional backend explicitly.
\
\  Screen Descriptor (15 cells = 120 bytes):
\    +0   width         Columns
\    +8   height        Rows
\    +16  front         Address of front buffer (w×h cells)
\    +24  back          Address of back buffer  (w×h cells)
\    +32  cursor-row    Current cursor row (0-based)
\    +40  cursor-col    Current cursor column (0-based)
\    +48  cursor-vis    Cursor visible flag (0 = hidden)
\    +56  dirty         Global dirty flag (0 = clean)
\    +64  force         Next accepted flush is a replace-all snapshot
\    +72  backend       Borrowed transactional backend descriptor
\    +80  flush-request Retained-only work needs a neutral transaction
\    +88  draw-generation Last completed ordinary top-level draw
\    +96  front-generation Draw whose CELL plane is committed in front
\    +104 damage       Address of the exact one-byte-per-row flush plan
\    +112 touched      Conservative rows written since accepted COMMIT
\
\  Each cell is 8 bytes (one CELL-MAKE value), so a buffer for
\  80×24 is 15,360 bytes × 2 = 30,720 bytes (~30 KiB).
\
\  Prefix: SCR- (public), _SCR- (internal)
\  Provider: akashic-tui-screen
\  Dependencies: cell.f, ansi.f, ../text/utf8.f,
\                ../text/cell-width.f

PROVIDED akashic-tui-screen

REQUIRE cell.f
REQUIRE ansi.f
REQUIRE ../text/utf8.f
REQUIRE ../text/cell-width.f
REQUIRE ../utils/term.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\ 1. Descriptor field offsets
\ =====================================================================

 0 CONSTANT _SCR-O-W
 8 CONSTANT _SCR-O-H
16 CONSTANT _SCR-O-FRONT
24 CONSTANT _SCR-O-BACK
32 CONSTANT _SCR-O-CROW
40 CONSTANT _SCR-O-CCOL
48 CONSTANT _SCR-O-CVIS
56 CONSTANT _SCR-O-DIRTY
64 CONSTANT _SCR-O-FORCE
72 CONSTANT _SCR-O-BACKEND
80 CONSTANT _SCR-O-FLUSH-REQUEST
88 CONSTANT _SCR-O-DRAW-GENERATION
96 CONSTANT _SCR-O-FRONT-GENERATION
104 CONSTANT _SCR-O-DAMAGE
112 CONSTANT _SCR-O-TOUCHED

120 CONSTANT _SCR-DESC-SIZE

\ =====================================================================
\ 2. Transactional backend ABI
\ =====================================================================

0 CONSTANT SCB-S-OK
1 CONSTANT SCB-S-WOULD-BLOCK
2 CONSTANT SCB-S-SESSION-LOST
3 CONSTANT SCB-S-INVALID

0 CONSTANT SCB-M-DELTA
1 CONSTANT SCB-M-SNAPSHOT
\ NONE carries zero CELL spans and deliberately omits the cursor callback;
\ BEGIN/COMMIT still delimit one backend transaction.
2 CONSTANT SCB-M-NONE

 0 CONSTANT _SCB-O-CONTEXT
 8 CONSTANT _SCB-O-BEGIN-XT
16 CONSTANT _SCB-O-SPAN-XT
24 CONSTANT _SCB-O-CURSOR-XT
32 CONSTANT _SCB-O-COMMIT-XT
40 CONSTANT _SCB-O-ABORT-XT
48 CONSTANT SCB-DESC-SIZE

: SCB.CONTEXT    ( backend -- field ) _SCB-O-CONTEXT + ;
: SCB.BEGIN-XT   ( backend -- field ) _SCB-O-BEGIN-XT + ;
: SCB.SPAN-XT    ( backend -- field ) _SCB-O-SPAN-XT + ;
: SCB.CURSOR-XT  ( backend -- field ) _SCB-O-CURSOR-XT + ;
: SCB.COMMIT-XT  ( backend -- field ) _SCB-O-COMMIT-XT + ;
: SCB.ABORT-XT   ( backend -- field ) _SCB-O-ABORT-XT + ;

\ Bracket every mutable/static byte owned by this module.  The limit is
\ installed only after the optional guard wrappers have also been compiled.
CREATE _SCR-OWNED-START
VARIABLE _SCR-OWNED-LIMIT

VARIABLE _SCBI-BACKEND
VARIABLE _SCBI-CONTEXT
VARIABLE _SCBI-BEGIN
VARIABLE _SCBI-SPAN
VARIABLE _SCBI-CURSOR
VARIABLE _SCBI-COMMIT
VARIABLE _SCBI-ABORT

\ SCB-INIT ( context begin-xt span-xt cursor-xt commit-xt abort-xt backend
\            -- status )
\   Initialise a caller-owned backend descriptor.  The screen borrows the
\   descriptor and context; both must outlive the binding.
: SCB-INIT
    _SCBI-BACKEND !
    _SCBI-ABORT ! _SCBI-COMMIT ! _SCBI-CURSOR !
    _SCBI-SPAN ! _SCBI-BEGIN ! _SCBI-CONTEXT !
    _SCBI-BACKEND @ 0=
    _SCBI-BEGIN @ 0= OR _SCBI-SPAN @ 0= OR
    _SCBI-CURSOR @ 0= OR _SCBI-COMMIT @ 0= OR
    _SCBI-ABORT @ 0= OR IF SCB-S-INVALID EXIT THEN
    _SCBI-CONTEXT @ _SCBI-BACKEND @ SCB.CONTEXT !
    _SCBI-BEGIN @   _SCBI-BACKEND @ SCB.BEGIN-XT !
    _SCBI-SPAN @    _SCBI-BACKEND @ SCB.SPAN-XT !
    _SCBI-CURSOR @  _SCBI-BACKEND @ SCB.CURSOR-XT !
    _SCBI-COMMIT @  _SCBI-BACKEND @ SCB.COMMIT-XT !
    _SCBI-ABORT @   _SCBI-BACKEND @ SCB.ABORT-XT !
    SCB-S-OK ;

: SCB-VALID?  ( backend -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP SCB.BEGIN-XT @ 0<>
    OVER SCB.SPAN-XT @ 0<> AND
    OVER SCB.CURSOR-XT @ 0<> AND
    OVER SCB.COMMIT-XT @ 0<> AND
    SWAP SCB.ABORT-XT @ 0<> AND ;

CREATE _SCR-ANSI-BACKEND SCB-DESC-SIZE ALLOT

\ =====================================================================
\ 3. Current screen pointer
\ =====================================================================

VARIABLE _SCR-CUR   0 _SCR-CUR !

\ Scratch variables (avoid deep stack gymnastics)
VARIABLE _SCR-TMP
VARIABLE _SCR-TMP2
VARIABLE _SCR-TMP3
VARIABLE _SCR-BUF-BYTES
VARIABLE _SCR-LAST-ROW    \ last physical cursor row during flush
VARIABLE _SCR-LAST-COL    \ last physical cursor col during flush
VARIABLE _SCR-LAST-FG     \ last emitted fg color
VARIABLE _SCR-LAST-BG     \ last emitted bg color
VARIABLE _SCR-LAST-ATTRS  \ last emitted attribute set
VARIABLE _SCR-SD-A
VARIABLE _SCR-SD-U
VARIABLE _SCR-SD-SCREEN
VARIABLE _SCR-SD-BUF-U
VARIABLE _SCR-SD-FRONT
VARIABLE _SCR-SD-BACK
VARIABLE _SCR-SD-DAMAGE
VARIABLE _SCR-SD-TOUCHED
VARIABLE _SCR-SD-BACKEND
VARIABLE _SCR-BACK-PLANE-XT
VARIABLE _SCR-BACK-MUTATION-XT
VARIABLE _SCR-BACK-MUTATION-SCREEN
VARIABLE _SCR-BACK-MUTATION-LOW
VARIABLE _SCR-BACK-MUTATION-HIGH
VARIABLE _SCR-FRAME-PLANES-XT
VARIABLE _SCR-PLAN-VALID
VARIABLE _SCR-PLAN-SCREEN
VARIABLE _SCR-PLAN-MODE
VARIABLE _SCR-PLAN-SPANS
VARIABLE _SCR-PLAN-CELLS

\ =====================================================================
\ 4. Internal helpers
\ =====================================================================

\ _SCR-CELLS ( scr -- n )   Total number of cells in one buffer.
: _SCR-CELLS  ( scr -- n )
    DUP _SCR-O-W + @ SWAP _SCR-O-H + @ * ;

\ _SCR-BUF-SIZE ( scr -- bytes )  Buffer size in bytes.
: _SCR-BUF-SIZE  ( scr -- bytes )
    _SCR-CELLS 8 * ;

\ _SCR-IDX ( row col -- offset )  Convert (row,col) to byte offset.
\   offset = (row * width + col) * 8
: _SCR-IDX  ( row col -- offset )
    SWAP _SCR-CUR @ _SCR-O-W + @ * + 8 * ;

\ A refused backend BEGIN leaves FRONT and BACK untouched.  Retain the exact
\ row-damage map and bounded admission totals across that retry; every
\ possible plane, cursor, request, backend, or geometry mutation invalidates
\ them synchronously.
: _SCR-PLAN-INVALIDATE  ( -- )
    0 _SCR-PLAN-VALID ! ;

\ The map remains allocated with its screen, but it is borrowable only while
\ the global retry plan still names that exact selected screen.
: _SCR-PLAN-DAMAGE@  ( screen -- damage-a damage-u )
    _SCR-PLAN-VALID @ 0= IF DROP 0 0 EXIT THEN
    DUP _SCR-PLAN-SCREEN @ <> IF DROP 0 0 EXIT THEN
    DUP _SCR-O-DAMAGE + @
    SWAP _SCR-O-H + @ ;

\ TOUCHED is a conservative candidate union, not an admitted plan.  It is
\ screen-owned so switching the selected screen cannot lose outstanding
\ FRONT/BACK differences.  Only accepted front advancement clears it.
: _SCR-SCREEN-TOUCHED-CLEAR  ( screen -- )
    DUP _SCR-O-TOUCHED + @ SWAP _SCR-O-H + @ 0 FILL ;

: _SCR-SCREEN-TOUCHED-ALL  ( screen -- )
    DUP _SCR-O-TOUCHED + @ SWAP _SCR-O-H + @ -1 FILL ;

: _SCR-TOUCHED-CLEAR  ( -- )
    _SCR-CUR @ _SCR-SCREEN-TOUCHED-CLEAR ;

: _SCR-TOUCHED-ALL  ( -- )
    _SCR-CUR @ _SCR-SCREEN-TOUCHED-ALL ;

: _SCR-TOUCHED!  ( row -- )
    _SCR-CUR @ _SCR-O-TOUCHED + @ + -1 SWAP C! ;

: _SCR-TOUCHED?  ( row -- flag )
    _SCR-CUR @ _SCR-O-TOUCHED + @ + C@ 0<> ;

VARIABLE _SCR-FILL-VAL
VARIABLE _SCR-SIZE-W
VARIABLE _SCR-SIZE-H

-1 1 RSHIFT CONSTANT _SCR-SIZE-MAX

\ _SCR-DIMS-BYTES? ( w h -- bytes flag )
\   Validate positive signed dimensions and both multiplications needed by
\   the native cell buffers.  Capacity comes from the allocator, not a
\   hard-coded screen bound.
: _SCR-DIMS-BYTES?  ( w h -- bytes flag )
    _SCR-SIZE-H ! _SCR-SIZE-W !
    _SCR-SIZE-W @ 0> _SCR-SIZE-H @ 0> AND 0= IF 0 0 EXIT THEN
    _SCR-SIZE-W @ _SCR-SIZE-MAX _SCR-SIZE-H @ / U> IF 0 0 EXIT THEN
    _SCR-SIZE-W @ _SCR-SIZE-H @ *
    DUP _SCR-SIZE-MAX 8 / U> IF DROP 0 0 EXIT THEN
    8 * -1 ;

\ _SCR-CELL-FILL ( addr n cell -- )
\   Fill n consecutive cell slots (each 8 bytes) at addr with cell.
\   Note: cannot use >R / R@ across DO..LOOP — loop uses return stack.
: _SCR-CELL-FILL  ( addr n cell -- )
    _SCR-FILL-VAL !
    0 ?DO
        _SCR-FILL-VAL @ OVER !
        8 +
    LOOP
    DROP ;

\ =====================================================================
\ 5. Constructor / destructor
\ =====================================================================

\ SCR-NEW ( w h -- scr )
\   Allocate the descriptor, two cell buffers, and two row-byte maps.
\   Front buffer is filled with CELL-BLANK, back buffer matches.
: SCR-NEW  ( w h -- scr )
    2DUP _SCR-DIMS-BYTES? 0= IF
        DROP 2DROP -1 ABORT" SCR-NEW: invalid dimensions"
    THEN
    _SCR-BUF-BYTES !
    OVER _SCR-TMP !                    \ save w
    DUP  _SCR-TMP2 !                   \ save h
    2DROP                              \ consume w h from caller

    \ Allocate descriptor
    _SCR-DESC-SIZE ALLOCATE
    0<> ABORT" SCR-NEW: descriptor alloc failed"
    _SCR-TMP3 !                        \ scr → TMP3

    \ Allocate front buffer
    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: front buf alloc failed"
    THEN
    DROP
    _SCR-TMP3 @ _SCR-O-FRONT + !

    \ Allocate back buffer
    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP
        _SCR-TMP3 @ _SCR-O-FRONT + @ FREE
        _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: back buf alloc failed"
    THEN
    DROP
    _SCR-TMP3 @ _SCR-O-BACK + !

    \ Allocate the exact row-damage plan.  It is screen-owned so an admitted
    \ plan can survive backend refusal without a fixed global row capacity.
    _SCR-TMP2 @ ALLOCATE DUP IF
        2DROP
        _SCR-TMP3 @ _SCR-O-BACK + @ FREE
        _SCR-TMP3 @ _SCR-O-FRONT + @ FREE
        _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: damage buf alloc failed"
    THEN
    DROP
    _SCR-TMP3 @ _SCR-O-DAMAGE + !

    \ Allocate a distinct conservative candidate map.  Unlike DAMAGE, this
    \ survives planning and backend refusal until an accepted COMMIT makes
    \ FRONT equal BACK again.
    _SCR-TMP2 @ ALLOCATE DUP IF
        2DROP
        _SCR-TMP3 @ _SCR-O-DAMAGE + @ FREE
        _SCR-TMP3 @ _SCR-O-BACK + @ FREE
        _SCR-TMP3 @ _SCR-O-FRONT + @ FREE
        _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: touched buf alloc failed"
    THEN
    DROP
    _SCR-TMP3 @ _SCR-O-TOUCHED + !

    \ Fill both buffers with CELL-BLANK
    _SCR-TMP3 @ _SCR-O-FRONT + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-TMP3 @ _SCR-O-BACK + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-TMP3 @ _SCR-O-DAMAGE + @ _SCR-TMP2 @ 0 FILL
    _SCR-TMP3 @ _SCR-O-TOUCHED + @ _SCR-TMP2 @ 0 FILL

    \ Fill descriptor fields
    _SCR-TMP @  _SCR-TMP3 @ _SCR-O-W     + !
    _SCR-TMP2 @ _SCR-TMP3 @ _SCR-O-H     + !
    0           _SCR-TMP3 @ _SCR-O-CROW   + !
    0           _SCR-TMP3 @ _SCR-O-CCOL   + !
    0           _SCR-TMP3 @ _SCR-O-CVIS   + !
    0           _SCR-TMP3 @ _SCR-O-DIRTY  + !
    0           _SCR-TMP3 @ _SCR-O-FORCE  + !
    0           _SCR-TMP3 @ _SCR-O-FLUSH-REQUEST + !
    0           _SCR-TMP3 @ _SCR-O-DRAW-GENERATION + !
    0           _SCR-TMP3 @ _SCR-O-FRONT-GENERATION + !
    _SCR-ANSI-BACKEND
                _SCR-TMP3 @ _SCR-O-BACKEND + !

    _SCR-TMP3 @ ;

\ SCR-FREE ( scr -- )
\   Deallocate both cell buffers, both row maps, and the screen descriptor
\   through the platform allocator that created them.
: SCR-FREE  ( scr -- )
    DUP 0= IF DROP EXIT THEN
    _SCR-PLAN-INVALIDATE
    DUP _SCR-CUR @ = IF 0 _SCR-CUR ! THEN
    DUP _SCR-O-FRONT + @ FREE
    DUP _SCR-O-BACK + @ FREE
    DUP _SCR-O-DAMAGE + @ FREE
    DUP _SCR-O-TOUCHED + @ FREE
    FREE ;

\ =====================================================================
\ 6. Current screen selection
\ =====================================================================

\ SCR-USE ( scr -- )   Set as current screen for drawing words.
: SCR-USE  ( scr -- )
    _SCR-PLAN-INVALIDATE
    _SCR-CUR ! ;

\ =====================================================================
\ 7. Accessors (operate on current screen)
\ =====================================================================

: SCR-W   ( -- w )    _SCR-CUR @ _SCR-O-W + @ ;
: SCR-H   ( -- h )    _SCR-CUR @ _SCR-O-H + @ ;

\ SCR-DRAW-COMPLETE ( -- )
\   Publish one completed ordinary top-level draw.  Retained consumers use
\   this generation to distinguish a retry of the same back buffer from a
\   newer frame while an earlier rich replacement is still hidden.
: SCR-DRAW-COMPLETE  ( -- )
    _SCR-CUR @ ?DUP IF
        _SCR-O-DRAW-GENERATION + DUP @ 1+
        DUP 0= IF DROP 1 THEN SWAP !
        _SCR-PLAN-INVALIDATE
    THEN ;

: SCR-DRAW-GENERATION@  ( -- generation )
    _SCR-CUR @ ?DUP IF _SCR-O-DRAW-GENERATION + @ ELSE 0 THEN ;

\ SCR-WITH-BACK-PLANE ( xt -- ... )
\   Execute XT with one read-only borrow of the current back plane:
\     xt: ( cells-a cols rows -- ... )
\   The address is valid only for the dynamic extent of XT and must not be
\   retained or mutated.  Guarded builds hold the screen guard across the
\   complete callback, allowing bulk readers to avoid one acquisition per
\   cell while preventing concurrent drawing, resize, or screen replacement.
: SCR-WITH-BACK-PLANE  ( xt -- ... )
    _SCR-BACK-PLANE-XT !
    _SCR-CUR @ DUP _SCR-O-BACK + @
    OVER _SCR-O-W + @
    ROT _SCR-O-H + @
    _SCR-BACK-PLANE-XT @ EXECUTE ;

\ SCR-WITH-BACK-MUTATION ( xt -- )
\   Execute one synchronous mutable borrow of the selected back plane:
\     xt: ( cells-a cols rows -- row-low row-high wrote? )
\   A true result marks the half-open physical row interval, invalidates the
\   retry plan, and dirties the captured screen exactly once.  Discontiguous
\   writes may conservatively return their bounding interval.  A malformed
\   true interval or THROW marks every row before callback state is scrubbed.
\
\   The address is valid only for the dynamic extent of XT.  XT must not
\   retain it, yield, or re-enter any SCR- word.
\   Guarded builds hold the screen guard across the complete callback.
: _SCR-BACK-MUTATION-CALL  ( -- row-low row-high wrote? )
    _SCR-BACK-MUTATION-SCREEN @ DUP _SCR-O-BACK + @
    OVER _SCR-O-W + @
    ROT _SCR-O-H + @
    _SCR-BACK-MUTATION-XT @ EXECUTE ;

: _SCR-BACK-MUTATION-DIRTY  ( -- )
    _SCR-PLAN-INVALIDATE
    -1 _SCR-BACK-MUTATION-SCREEN @ _SCR-O-DIRTY + ! ;

: _SCR-BACK-MUTATION-TOUCH-ALL  ( -- )
    _SCR-BACK-MUTATION-SCREEN @ _SCR-SCREEN-TOUCHED-ALL ;

: _SCR-BACK-MUTATION-TOUCH-RANGE  ( row-low row-high -- )
    _SCR-BACK-MUTATION-HIGH !
    _SCR-BACK-MUTATION-LOW !
    _SCR-BACK-MUTATION-LOW @ 0<
    _SCR-BACK-MUTATION-HIGH @ _SCR-BACK-MUTATION-LOW @ <= OR
    _SCR-BACK-MUTATION-HIGH @
        _SCR-BACK-MUTATION-SCREEN @ _SCR-O-H + @ > OR IF
        _SCR-BACK-MUTATION-TOUCH-ALL
        EXIT
    THEN
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-TOUCHED + @
        _SCR-BACK-MUTATION-LOW @ +
    _SCR-BACK-MUTATION-HIGH @ _SCR-BACK-MUTATION-LOW @ -
    -1 FILL ;

: _SCR-BACK-MUTATION-RANGE-DIRTY  ( row-low row-high -- )
    _SCR-BACK-MUTATION-TOUCH-RANGE
    _SCR-BACK-MUTATION-DIRTY ;

: _SCR-BACK-MUTATION-ALL-DIRTY  ( -- )
    _SCR-BACK-MUTATION-TOUCH-ALL
    _SCR-BACK-MUTATION-DIRTY ;

: _SCR-BACK-MUTATION-CLEAR  ( -- )
    0 _SCR-BACK-MUTATION-XT !
    0 _SCR-BACK-MUTATION-SCREEN !
    0 _SCR-BACK-MUTATION-LOW !
    0 _SCR-BACK-MUTATION-HIGH ! ;

: SCR-WITH-BACK-MUTATION  ( xt -- )
    _SCR-BACK-MUTATION-SCREEN @ IF
        DROP -1 ABORT" SCR-WITH-BACK-MUTATION: nested borrow"
    THEN
    _SCR-BACK-MUTATION-XT !
    _SCR-CUR @ DUP 0= IF
        DROP _SCR-BACK-MUTATION-CLEAR
        -1 ABORT" SCR-WITH-BACK-MUTATION: no current screen"
    THEN _SCR-BACK-MUTATION-SCREEN !
    ['] _SCR-BACK-MUTATION-CALL CATCH DUP IF
        _SCR-BACK-MUTATION-ALL-DIRTY
        _SCR-BACK-MUTATION-CLEAR
        THROW
    THEN
    DROP IF
        _SCR-BACK-MUTATION-RANGE-DIRTY
    ELSE
        2DROP
    THEN
    _SCR-BACK-MUTATION-CLEAR ;

\ SCR-WITH-FRAME-PLANES ( xt -- ... )
\   Execute XT with one read-only view of the complete current frame state:
\     xt: ( front-a back-a cols rows front-draw draw force?
\           damage-a damage-u -- ... )
\   FRONT-DRAW identifies the last draw accepted into FRONT.  DRAW identifies
\   the latest completed ordinary top-level draw represented by BACK.  FORCE?
\   says the next accepted flush must replace the complete CELL plane.
\   DAMAGE-A/DAMAGE-U is the exact one-byte-per-row admitted plan only while
\   the current immutable retry plan is valid; otherwise it is canonical
\   0 0.  A nonzero byte marks a row whose CELL plane differs, or every row
\   for a forced snapshot.
\
\   All borrowed addresses are valid only for the dynamic extent of XT and
\   must not be retained or mutated.  Guarded builds hold the screen guard
\   across the callback, so a selected renderer can consume the admitted
\   damage without racing drawing, resize, or screen replacement.
: SCR-WITH-FRAME-PLANES  ( xt -- ... )
    _SCR-FRAME-PLANES-XT !
    _SCR-CUR @ >R
    R@ _SCR-O-FRONT + @
    R@ _SCR-O-BACK + @
    R@ _SCR-O-W + @
    R@ _SCR-O-H + @
    R@ _SCR-O-FRONT-GENERATION + @
    R@ _SCR-O-DRAW-GENERATION + @
    R@ _SCR-O-FORCE + @ IF -1 ELSE 0 THEN
    R@ _SCR-PLAN-DAMAGE@
    R> DROP
    _SCR-FRAME-PLANES-XT @ EXECUTE ;

\ =====================================================================
\ 8. Cell read/write
\ =====================================================================

\ SCR-SET ( cell row col -- )   Write cell to back buffer.
: SCR-SET  ( cell row col -- )
    _SCR-PLAN-INVALIDATE
    OVER _SCR-TOUCHED!
    -1 _SCR-CUR @ _SCR-O-DIRTY + !
    _SCR-IDX _SCR-CUR @ _SCR-O-BACK + @ + ! ;

\ SCR-GET ( row col -- cell )   Read cell from back buffer.
: SCR-GET  ( row col -- cell )
    _SCR-IDX _SCR-CUR @ _SCR-O-BACK + @ + @ ;

\ SCR-FRONT@ ( row col -- cell )  Read cell from front buffer.
: SCR-FRONT@  ( row col -- cell )
    _SCR-IDX _SCR-CUR @ _SCR-O-FRONT + @ + @ ;

\ SCR-FILL ( cell -- )   Fill entire back buffer with given cell.
: SCR-FILL  ( cell -- )
    _SCR-PLAN-INVALIDATE
    _SCR-TOUCHED-ALL
    -1 _SCR-CUR @ _SCR-O-DIRTY + !
    _SCR-CUR @ _SCR-O-BACK + @
    _SCR-CUR @ _SCR-CELLS
    ROT _SCR-CELL-FILL ;

\ SCR-CLEAR ( -- )   Fill back buffer with CELL-BLANK.
: SCR-CLEAR  ( -- )
    CELL-BLANK SCR-FILL ;

\ =====================================================================
\ 9. Cursor management
\ =====================================================================

\ SCR-CURSOR-AT ( row col -- )   Set logical cursor position.
: SCR-CURSOR-AT  ( row col -- )
    0 MAX SCR-W 1- MIN
    _SCR-CUR @ _SCR-O-CCOL + !
    0 MAX SCR-H 1- MIN
    _SCR-CUR @ _SCR-O-CROW + !
    _SCR-PLAN-INVALIDATE
    -1 _SCR-CUR @ _SCR-O-DIRTY + ! ;

\ SCR-CURSOR-ON ( -- )   Show cursor on next flush.
: SCR-CURSOR-ON  ( -- )
    -1 _SCR-CUR @ _SCR-O-CVIS + !
    _SCR-PLAN-INVALIDATE
    -1 _SCR-CUR @ _SCR-O-DIRTY + ! ;

\ SCR-CURSOR-OFF ( -- )  Hide cursor on next flush.
: SCR-CURSOR-OFF  ( -- )
    0 _SCR-CUR @ _SCR-O-CVIS + !
    _SCR-PLAN-INVALIDATE
    -1 _SCR-CUR @ _SCR-O-DIRTY + ! ;

\ =====================================================================
\ 10. Dirty / force / neutral flush request
\ =====================================================================

\ SCR-FORCE ( -- )
\   Force a replace-all snapshot without poisoning the front buffer.  Every
\   packed native value is legal, so no sentinel can be collision-free.
: SCR-FORCE  ( -- )
    _SCR-CUR @ DUP _SCR-O-FORCE + @ IF DROP EXIT THEN
    -1 OVER _SCR-O-FORCE + !
    _SCR-PLAN-INVALIDATE
    -1 SWAP _SCR-O-DIRTY + ! ;

\ SCR-REQUEST-FLUSH ( -- )
\   Schedule a transaction without claiming that CELL or cursor state has
\   changed.  The request remains set through every refusal and is cleared
\   only after the backend accepts COMMIT.
: SCR-REQUEST-FLUSH  ( -- )
    _SCR-CUR @ ?DUP IF
        DUP _SCR-O-FLUSH-REQUEST + @ IF DROP EXIT THEN
        -1 SWAP _SCR-O-FLUSH-REQUEST + !
        _SCR-PLAN-INVALIDATE
    THEN ;

: SCR-DIRTY?  ( -- flag )
    _SCR-CUR @ ?DUP IF
        DUP _SCR-O-DIRTY + @
        SWAP _SCR-O-FLUSH-REQUEST + @ OR 0<>
    ELSE 0 THEN ;

: SCR-BACKEND@  ( -- backend | 0 )
    _SCR-CUR @ ?DUP IF _SCR-O-BACKEND + @ ELSE 0 THEN ;

\ _SCR-OPTIONAL-BYTE-SPAN? ( a u -- flag )
\   Admit only the canonical empty span or one nonempty, nonwrapping span.
: _SCR-OPTIONAL-BYTE-SPAN?  ( a u -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SCR-SD-OVERLAP?  ( other-a other-u -- flag )
    _SCR-SD-A @ _SCR-SD-U @ 2SWAP MSPAN-OVERLAP? ;

: _SCR-ALIGNED-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SCR-MODULE-DISJOINT?  ( a u -- flag )
    _SCR-OWNED-LIMIT @ DUP _SCR-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _SCR-OWNED-START - _SCR-OWNED-START SWAP MSPAN-OVERLAP? 0= ;

: _SCR-ACTIVE-STORAGE-VALID?  ( -- flag )
    _SCR-CUR @ DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SCR-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    _SCR-SD-SCREEN !
    _SCR-SD-SCREEN @ _SCR-O-W + @
    _SCR-SD-SCREEN @ _SCR-O-H + @ _SCR-DIMS-BYTES? 0= IF
        DROP 0 EXIT
    THEN
    _SCR-SD-BUF-U !
    _SCR-SD-SCREEN @ _SCR-O-FRONT + @ _SCR-SD-FRONT !
    _SCR-SD-SCREEN @ _SCR-O-BACK + @ _SCR-SD-BACK !
    _SCR-SD-SCREEN @ _SCR-O-DAMAGE + @ _SCR-SD-DAMAGE !
    _SCR-SD-SCREEN @ _SCR-O-TOUCHED + @ _SCR-SD-TOUCHED !
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @ _SCR-ALIGNED-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @ _SCR-ALIGNED-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-OPTIONAL-BYTE-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-OPTIONAL-BYTE-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE _SCR-MODULE-DISJOINT? 0= IF
        0 EXIT
    THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @ _SCR-MODULE-DISJOINT? 0= IF
        0 EXIT
    THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @ _SCR-MODULE-DISJOINT? 0= IF
        0 EXIT
    THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-MODULE-DISJOINT? 0= IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-MODULE-DISJOINT? 0= IF 0 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE
        _SCR-SD-FRONT @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE
        _SCR-SD-BACK @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-BACK @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-O-BACKEND + @ DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SCB-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP SCB-VALID? 0= IF DROP 0 EXIT THEN _SCR-SD-BACKEND !
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? 0= ;

\ SCR-STORAGE-DISJOINT? ( a u -- flag )
\   Prove that caller storage cannot mutate the active screen while a
\   projection reads it.  The protected graph is the complete screen module,
\   current descriptor, both CELL planes, both row maps, and the borrowed
\   backend descriptor.  Backend context remains opaque and must be checked
\   by its owning API.
: SCR-STORAGE-DISJOINT?  ( a u -- flag )
    _SCR-SD-U ! _SCR-SD-A !
    _SCR-SD-A @ _SCR-SD-U @ _SCR-OPTIONAL-BYTE-SPAN? 0= IF 0 EXIT THEN
    _SCR-ACTIVE-STORAGE-VALID? 0= IF 0 EXIT THEN
    _SCR-SD-A @ _SCR-SD-U @ _SCR-MODULE-DISJOINT? 0= IF 0 EXIT THEN
    _SCR-SD-U @ 0= IF -1 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACKEND @ SCB-DESC-SIZE _SCR-SD-OVERLAP? IF 0 EXIT THEN
    -1 ;

\ SCR-BACKEND! ( backend -- status )
\   Bind a validated caller-owned descriptor and force its first accepted
\   transaction to be a complete snapshot.
: SCR-BACKEND!  ( backend -- status )
    _SCR-CUR @ 0= IF DROP SCB-S-INVALID EXIT THEN
    DUP SCB-VALID? 0= IF DROP SCB-S-INVALID EXIT THEN
    _SCR-PLAN-INVALIDATE
    _SCR-CUR @ _SCR-O-BACKEND + !
    SCR-FORCE
    SCB-S-OK ;

: SCR-ANSI  ( -- )
    _SCR-CUR @ 0= IF EXIT THEN
    _SCR-PLAN-INVALIDATE
    _SCR-ANSI-BACKEND _SCR-CUR @ _SCR-O-BACKEND + !
    SCR-FORCE ;

\ =====================================================================
\ 11. Internal: emit a single cell via ANSI
\ =====================================================================

\ _SCR-MOVE-TO ( row col -- )
\   Emit ANSI-AT if necessary, update tracking state.
\   ANSI-AT uses 1-based row/col.
: _SCR-MOVE-TO  ( row col -- )
    2DUP _SCR-LAST-COL @ = SWAP _SCR-LAST-ROW @ = AND IF
        2DROP EXIT                     \ already there
    THEN
    OVER _SCR-LAST-ROW !
    DUP  _SCR-LAST-COL !
    SWAP 1+ SWAP 1+ ANSI-AT ;         \ row+1, col+1 (1-based)

\ _SCR-EMIT-ATTRS ( cell -- )
\   Emit ANSI attribute/color changes needed for this cell.
\   Compares against last emitted state, emits only diffs.
\   CELL-ATTRS@ returns low-bit attrs (0–15) matching CELL-A-* constants.
: _SCR-EMIT-ATTRS  ( cell -- )
    DUP CELL-ATTRS@ DUP _SCR-LAST-ATTRS @ <> IF
        \ Attributes changed — reset and re-apply
        ANSI-RESET
        DUP CELL-A-BOLD       AND IF ANSI-BOLD      THEN
        DUP CELL-A-DIM        AND IF ANSI-DIM       THEN
        DUP CELL-A-ITALIC     AND IF ANSI-ITALIC    THEN
        DUP CELL-A-UNDERLINE  AND IF ANSI-UNDERLINE THEN
        DUP CELL-A-BLINK      AND IF ANSI-BLINK     THEN
        DUP CELL-A-REVERSE    AND IF ANSI-REVERSE   THEN
        DUP CELL-A-STRIKE     AND IF ANSI-STRIKE    THEN
        _SCR-LAST-ATTRS !
        \ After RESET, fg/bg are default — force re-emit below
        -1 _SCR-LAST-FG !
        -1 _SCR-LAST-BG !
    ELSE
        DROP
    THEN
    DUP CELL-FG@ DUP _SCR-LAST-FG @ <> IF
        DUP ANSI-FG256
        _SCR-LAST-FG !
    ELSE
        DROP
    THEN
    CELL-BG@ DUP _SCR-LAST-BG @ <> IF
        DUP ANSI-BG256
        _SCR-LAST-BG !
    ELSE
        DROP
    THEN ;

\ Scratch buffer for UTF-8 encoding (4 bytes is enough)
CREATE _SCR-UTF8-BUF 4 ALLOT

\ _SCR-EMIT-CP ( cell -- cp )
\   Resolve an empty cell to space and apply the final one-physical-cell
\   projection.  This guard applies even to raw cells written without DRW.
: _SCR-EMIT-CP  ( cell -- cp )
    CELL-CP@
    DUP 0= IF DROP 32 THEN            \ empty → space
    CW-CELL-CP ;

\ _SCR-EMIT-CHAR ( cell -- )
\   Emit exactly one isolated physical terminal cell as UTF-8.
: _SCR-EMIT-CHAR  ( cell -- )
    _SCR-EMIT-CP
    DUP 128 < IF
        EMIT                           \ ASCII fast path
    ELSE
        _SCR-UTF8-BUF UTF8-ENCODE _SCR-UTF8-BUF -
        _SCR-UTF8-BUF SWAP TYPE        \ emit multi-byte sequence
    THEN ;

\ =====================================================================
\ 12. ANSI transactional backend
\ =====================================================================

VARIABLE _SCBA-A
VARIABLE _SCBA-N
VARIABLE _SCBA-ROW
VARIABLE _SCBA-COL
VARIABLE _SCBA-CROW
VARIABLE _SCBA-CCOL
VARIABLE _SCBA-CVIS
VARIABLE _SCBA-MODE

: _SCBA-BEGIN  ( mode cols rows span-count cell-count context -- status )
    DROP 2DROP 2DROP _SCBA-MODE !
    _SCBA-MODE @ SCB-M-NONE = IF SCB-S-OK EXIT THEN
    ANSI-CURSOR-OFF
    -1 _SCR-LAST-ROW !
    -1 _SCR-LAST-COL !
    -1 _SCR-LAST-FG !
    -1 _SCR-LAST-BG !
     0 _SCR-LAST-ATTRS !
    SCB-S-OK ;

: _SCBA-SPAN  ( cells count row col context -- status )
    DROP _SCBA-COL ! _SCBA-ROW ! _SCBA-N ! _SCBA-A !
    _SCBA-N @ 0 ?DO
        _SCBA-ROW @ _SCBA-COL @ I + _SCR-MOVE-TO
        _SCBA-A @ I 8 * + @
        DUP _SCR-EMIT-ATTRS
        _SCR-EMIT-CHAR
        1 _SCR-LAST-COL +!
    LOOP
    SCB-S-OK ;

: _SCBA-CURSOR  ( row col visible context -- status )
    DROP _SCBA-CVIS ! _SCBA-CCOL ! _SCBA-CROW !
    SCB-S-OK ;

: _SCBA-COMMIT  ( context -- status )
    DROP
    _SCBA-MODE @ SCB-M-NONE = IF
        TERM-FLUSH
        SCB-S-OK EXIT
    THEN
    _SCBA-CVIS @ IF
        _SCBA-CROW @ 1+ _SCBA-CCOL @ 1+ ANSI-AT
        ANSI-CURSOR-ON
    THEN
    ANSI-RESET
    TERM-FLUSH
    SCB-S-OK ;

: _SCBA-ABORT  ( context -- )
    DROP
    _SCBA-MODE @ SCB-M-NONE = IF EXIT THEN
    ANSI-RESET
    ANSI-CURSOR-ON
    TERM-FLUSH ;

0
' _SCBA-BEGIN ' _SCBA-SPAN ' _SCBA-CURSOR
' _SCBA-COMMIT ' _SCBA-ABORT
_SCR-ANSI-BACKEND SCB-INIT
SCB-S-OK <> ABORT" screen: ANSI backend init failed"

\ =====================================================================
\ 13. Transactional differential flush
\ =====================================================================
\
\  One bounded discovery pass avoids a fixed change-list capacity while
\  recording an exact byte per row.  Emission re-derives maximal spans only
\  inside marked rows; accepted retirement copies those same complete rows.

VARIABLE _SCR-ROW-BYTES
VARIABLE _SCR-SCAN-FRONT
VARIABLE _SCR-SCAN-BACK
VARIABLE _SCR-SCAN-W
VARIABLE _SCR-SCAN-H
VARIABLE _SCR-SCAN-ROW
VARIABLE _SCR-SCAN-COL
VARIABLE _SCR-SCAN-START
VARIABLE _SCR-SCAN-MORE
VARIABLE _SCR-SPAN-COUNT
VARIABLE _SCR-CELL-COUNT
VARIABLE _SCR-FLUSH-MODE
VARIABLE _SCR-FLUSH-BACKEND
VARIABLE _SCR-FLUSH-STATUS

: _SCR-DAMAGE-CLEAR  ( -- )
    _SCR-CUR @ DUP _SCR-O-DAMAGE + @
    SWAP _SCR-O-H + @ 0 FILL ;

: _SCR-DAMAGE!  ( row -- )
    _SCR-CUR @ _SCR-O-DAMAGE + @ + -1 SWAP C! ;

: _SCR-DAMAGE?  ( row -- flag )
    _SCR-CUR @ _SCR-O-DAMAGE + @ + C@ 0<> ;

: _SCR-PLAN-SAVE  ( -- )
    _SCR-CUR @ _SCR-PLAN-SCREEN !
    _SCR-FLUSH-MODE @ _SCR-PLAN-MODE !
    _SCR-SPAN-COUNT @ _SCR-PLAN-SPANS !
    _SCR-CELL-COUNT @ _SCR-PLAN-CELLS !
    -1 _SCR-PLAN-VALID ! ;

: _SCR-PLAN-LOAD?  ( -- flag )
    _SCR-PLAN-VALID @ 0= IF 0 EXIT THEN
    _SCR-PLAN-SCREEN @ _SCR-CUR @ <> IF
        _SCR-PLAN-INVALIDATE 0 EXIT
    THEN
    _SCR-PLAN-MODE @ _SCR-FLUSH-MODE !
    _SCR-PLAN-SPANS @ _SCR-SPAN-COUNT !
    _SCR-PLAN-CELLS @ _SCR-CELL-COUNT !
    -1 ;

: _SCR-SCAN-RESET  ( -- )
    _SCR-CUR @ _SCR-O-FRONT + @ _SCR-SCAN-FRONT !
    _SCR-CUR @ _SCR-O-BACK  + @ _SCR-SCAN-BACK !
    SCR-W DUP _SCR-SCAN-W ! 8 * _SCR-ROW-BYTES !
    SCR-H _SCR-SCAN-H ! ;

: _SCR-SCAN-NEXT-ROW  ( -- )
    _SCR-ROW-BYTES @ _SCR-SCAN-FRONT +!
    _SCR-ROW-BYTES @ _SCR-SCAN-BACK +! ;

: _SCR-SCAN-CELL-DIFF?  ( -- flag )
    _SCR-SCAN-FRONT @ _SCR-SCAN-COL @ 8 * + @
    _SCR-SCAN-BACK  @ _SCR-SCAN-COL @ 8 * + @ <> ;

: _SCR-COUNT-DELTA-ROW  ( -- )
    0 _SCR-SCAN-COL !
    BEGIN _SCR-SCAN-COL @ _SCR-SCAN-W @ < WHILE
        _SCR-SCAN-CELL-DIFF? IF
            1 _SCR-SPAN-COUNT +!
            -1 _SCR-SCAN-MORE !
            BEGIN
                _SCR-SCAN-COL @ _SCR-SCAN-W @ <
                _SCR-SCAN-MORE @ AND
            WHILE
                _SCR-SCAN-CELL-DIFF? IF
                    1 _SCR-CELL-COUNT +!
                    1 _SCR-SCAN-COL +!
                ELSE
                    0 _SCR-SCAN-MORE !
                THEN
            REPEAT
        ELSE
            1 _SCR-SCAN-COL +!
        THEN
    REPEAT ;

: _SCR-COUNT-CHANGES  ( -- )
    0 _SCR-SPAN-COUNT !
    0 _SCR-CELL-COUNT !
    _SCR-DAMAGE-CLEAR
    \ A real CELL or cursor mutation subsumes a retained-only request.  This
    \ priority prevents NONE from hiding cursor state that still needs commit.
    _SCR-CUR @ _SCR-O-FORCE + @ IF
        SCB-M-SNAPSHOT
    ELSE _SCR-CUR @ _SCR-O-DIRTY + @ IF
        SCB-M-DELTA
    ELSE _SCR-CUR @ _SCR-O-FLUSH-REQUEST + @ IF
        SCB-M-NONE
    ELSE
        SCB-M-DELTA
    THEN THEN THEN _SCR-FLUSH-MODE !
    _SCR-FLUSH-MODE @ SCB-M-NONE = IF _SCR-PLAN-SAVE EXIT THEN
    _SCR-SCAN-RESET
    _SCR-SCAN-H @ 0 ?DO
        _SCR-FLUSH-MODE @ SCB-M-SNAPSHOT = IF
            I _SCR-DAMAGE!
            1 _SCR-SPAN-COUNT +!
            _SCR-SCAN-W @ _SCR-CELL-COUNT +!
        ELSE
            I _SCR-TOUCHED? IF
                _SCR-SCAN-FRONT @ _SCR-ROW-BYTES @
                _SCR-SCAN-BACK @ _SCR-ROW-BYTES @ COMPARE 0<> IF
                    I _SCR-DAMAGE!
                    _SCR-COUNT-DELTA-ROW
                THEN
            THEN
        THEN
        _SCR-SCAN-NEXT-ROW
    LOOP
    _SCR-PLAN-SAVE ;

: _SCR-CALL-BEGIN  ( -- status )
    _SCR-FLUSH-MODE @
    SCR-W SCR-H
    _SCR-SPAN-COUNT @ _SCR-CELL-COUNT @
    _SCR-FLUSH-BACKEND @ SCB.CONTEXT @
    _SCR-FLUSH-BACKEND @ SCB.BEGIN-XT @ EXECUTE ;

: _SCR-CALL-SPAN  ( cells count row col -- status )
    _SCR-FLUSH-BACKEND @ SCB.CONTEXT @
    _SCR-FLUSH-BACKEND @ SCB.SPAN-XT @ EXECUTE ;

: _SCR-EMIT-DELTA-ROW  ( -- )
    0 _SCR-SCAN-COL !
    BEGIN
        _SCR-SCAN-COL @ _SCR-SCAN-W @ <
        _SCR-FLUSH-STATUS @ SCB-S-OK = AND
    WHILE
        _SCR-SCAN-CELL-DIFF? IF
            _SCR-SCAN-COL @ _SCR-SCAN-START !
            -1 _SCR-SCAN-MORE !
            BEGIN
                _SCR-SCAN-COL @ _SCR-SCAN-W @ <
                _SCR-SCAN-MORE @ AND
            WHILE
                _SCR-SCAN-CELL-DIFF? IF
                    1 _SCR-SCAN-COL +!
                ELSE
                    0 _SCR-SCAN-MORE !
                THEN
            REPEAT
            _SCR-SCAN-BACK @ _SCR-SCAN-START @ 8 * +
            _SCR-SCAN-COL @ _SCR-SCAN-START @ -
            _SCR-SCAN-ROW @ _SCR-SCAN-START @
            _SCR-CALL-SPAN _SCR-FLUSH-STATUS !
        ELSE
            1 _SCR-SCAN-COL +!
        THEN
    REPEAT ;

: _SCR-EMIT-SPANS  ( -- status )
    _SCR-FLUSH-MODE @ SCB-M-NONE = IF SCB-S-OK EXIT THEN
    _SCR-SCAN-RESET
    0 _SCR-SCAN-ROW !
    SCB-S-OK _SCR-FLUSH-STATUS !
    _SCR-SCAN-H @ 0 ?DO
        _SCR-FLUSH-STATUS @ SCB-S-OK = IF
            I _SCR-DAMAGE? IF
                _SCR-FLUSH-MODE @ SCB-M-SNAPSHOT = IF
                    _SCR-SCAN-BACK @ _SCR-SCAN-W @ I 0
                    _SCR-CALL-SPAN _SCR-FLUSH-STATUS !
                ELSE
                    I _SCR-SCAN-ROW !
                    _SCR-EMIT-DELTA-ROW
                THEN
            THEN
        THEN
        _SCR-SCAN-NEXT-ROW
    LOOP
    _SCR-FLUSH-STATUS @ ;

: _SCR-CALL-CURSOR  ( -- status )
    _SCR-CUR @ _SCR-O-CROW + @
    _SCR-CUR @ _SCR-O-CCOL + @
    _SCR-CUR @ _SCR-O-CVIS + @ IF 1 ELSE 0 THEN
    _SCR-FLUSH-BACKEND @ SCB.CONTEXT @
    _SCR-FLUSH-BACKEND @ SCB.CURSOR-XT @ EXECUTE ;

: _SCR-CALL-COMMIT  ( -- status )
    _SCR-FLUSH-BACKEND @ SCB.CONTEXT @
    _SCR-FLUSH-BACKEND @ SCB.COMMIT-XT @ EXECUTE ;

: _SCR-CALL-ABORT  ( -- )
    _SCR-FLUSH-BACKEND @ SCB.CONTEXT @
    _SCR-FLUSH-BACKEND @ SCB.ABORT-XT @ EXECUTE ;

: _SCR-FAIL  ( status -- status )
    \ Backend failures do not prove that raw ANSI is safe.  The terminal
    \ owner performs an explicit synchronized close or hard-reset handoff
    \ before calling SCR-ANSI.
    ;

: _SCR-ADVANCE-FRONT  ( -- )
    _SCR-FLUSH-MODE @ SCB-M-NONE <> IF
        _SCR-SCAN-RESET
        _SCR-SCAN-H @ 0 ?DO
            I _SCR-DAMAGE? IF
                _SCR-SCAN-BACK @ _SCR-SCAN-FRONT @ _SCR-ROW-BYTES @ CMOVE
            THEN
            _SCR-SCAN-NEXT-ROW
        LOOP
    THEN
    \ Touched-but-equal rows were proved equal; every unequal candidate was
    \ copied through exact DAMAGE.  Refusals never reach this retirement.
    _SCR-TOUCHED-CLEAR
    0 _SCR-CUR @ _SCR-O-DIRTY + !
    0 _SCR-CUR @ _SCR-O-FORCE + !
    \ An accepted NONE is legal only when FRONT already equals BACK.  It can
    \ therefore watermark that identical plane with the newer completed draw
    \ just as truthfully as DELTA or SNAPSHOT.  Refusals never reach here.
    _SCR-CUR @ _SCR-O-DRAW-GENERATION + @
        _SCR-CUR @ _SCR-O-FRONT-GENERATION + !
    \ This is the sole runtime retirement point for a neutral request.
    0 _SCR-CUR @ _SCR-O-FLUSH-REQUEST + !
    _SCR-PLAN-INVALIDATE ;

\ SCR-FLUSH? ( -- status )
\   Attempt one transaction.  A refusal never advances front.  In particular,
\   SESSION-LOST leaves the current backend bound: only the stream owner knows
\   whether a synchronized close has made ANSI emission safe again.
: SCR-FLUSH?  ( -- status )
    _SCR-CUR @ 0= IF SCB-S-INVALID EXIT THEN
    SCR-BACKEND@ DUP SCB-VALID? 0= IF DROP SCB-S-INVALID EXIT THEN
    _SCR-FLUSH-BACKEND !
    _SCR-PLAN-LOAD? 0= IF _SCR-COUNT-CHANGES THEN
    _SCR-CALL-BEGIN DUP SCB-S-OK <> IF _SCR-FAIL EXIT THEN DROP
    _SCR-EMIT-SPANS DUP SCB-S-OK <> IF
        _SCR-CALL-ABORT _SCR-FAIL EXIT
    THEN DROP
    _SCR-FLUSH-MODE @ SCB-M-NONE <> IF
        _SCR-CALL-CURSOR DUP SCB-S-OK <> IF
            _SCR-CALL-ABORT _SCR-FAIL EXIT
        THEN DROP
    THEN
    _SCR-CALL-COMMIT DUP SCB-S-OK <> IF _SCR-FAIL EXIT THEN DROP
    _SCR-ADVANCE-FRONT
    SCB-S-OK ;

\ Preserve the established no-result convenience API.  Status-aware owners
\ such as app-shell use SCR-FLUSH? so backpressure remains observable.
: SCR-FLUSH  ( -- )
    SCR-FLUSH? DROP ;

\ =====================================================================
\ 14. SCR-RESIZE
\ =====================================================================
\
\   Resize the screen.  This creates new buffers, copies the
\   overlapping region from old back buffer, then replaces the
\   descriptor fields, returning the old buffers to their allocator.

VARIABLE _SCR-OLD-W
VARIABLE _SCR-OLD-H
VARIABLE _SCR-OLD-FRONT
VARIABLE _SCR-OLD-BACK
VARIABLE _SCR-OLD-DAMAGE
VARIABLE _SCR-OLD-TOUCHED
VARIABLE _SCR-NEW-FRONT
VARIABLE _SCR-NEW-BACK
VARIABLE _SCR-NEW-DAMAGE
VARIABLE _SCR-NEW-TOUCHED
VARIABLE _SCR-COPY-W
VARIABLE _SCR-COPY-H

: SCR-RESIZE  ( w h -- )
    2DUP _SCR-DIMS-BYTES? 0= IF
        DROP 2DROP -1 ABORT" SCR-RESIZE: invalid dimensions"
    THEN
    _SCR-PLAN-INVALIDATE
    _SCR-BUF-BYTES !
    _SCR-CUR @ _SCR-O-W + @ _SCR-OLD-W !
    _SCR-CUR @ _SCR-O-H + @ _SCR-OLD-H !
    _SCR-CUR @ _SCR-O-FRONT + @ _SCR-OLD-FRONT !
    _SCR-CUR @ _SCR-O-BACK + @ _SCR-OLD-BACK !
    _SCR-CUR @ _SCR-O-DAMAGE + @ _SCR-OLD-DAMAGE !
    _SCR-CUR @ _SCR-O-TOUCHED + @ _SCR-OLD-TOUCHED !

    OVER _SCR-TMP  !                   \ new w
    DUP  _SCR-TMP2 !                   \ new h
    2DROP                              \ consume w h from caller

    \ Allocate new buffers
    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP -1 ABORT" SCR-RESIZE: front alloc failed"
    THEN
    DROP _SCR-NEW-FRONT !

    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP _SCR-NEW-FRONT @ FREE
        -1 ABORT" SCR-RESIZE: back alloc failed"
    THEN
    DROP _SCR-NEW-BACK !

    _SCR-TMP2 @ ALLOCATE DUP IF
        2DROP
        _SCR-NEW-BACK @ FREE
        _SCR-NEW-FRONT @ FREE
        -1 ABORT" SCR-RESIZE: damage buf alloc failed"
    THEN
    DROP _SCR-NEW-DAMAGE !

    _SCR-TMP2 @ ALLOCATE DUP IF
        2DROP
        _SCR-NEW-DAMAGE @ FREE
        _SCR-NEW-BACK @ FREE
        _SCR-NEW-FRONT @ FREE
        -1 ABORT" SCR-RESIZE: touched buf alloc failed"
    THEN
    DROP _SCR-NEW-TOUCHED !

    \ Fill new buffers with CELL-BLANK
    _SCR-NEW-FRONT @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-NEW-BACK @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-NEW-DAMAGE @ _SCR-TMP2 @ 0 FILL
    _SCR-NEW-TOUCHED @ _SCR-TMP2 @ -1 FILL

    \ Copy overlapping region from old back → new back
    _SCR-TMP @  _SCR-OLD-W @ MIN _SCR-COPY-W !
    _SCR-TMP2 @ _SCR-OLD-H @ MIN _SCR-COPY-H !

    _SCR-COPY-H @ 0 ?DO
        \ Source row start: old-back + row * old-w * 8
        _SCR-OLD-BACK @ I _SCR-OLD-W @ * 8 * +
        \ Dest row start:  new-back + row * new-w * 8
        _SCR-NEW-BACK @ I _SCR-TMP  @ * 8 * +
        \ Byte count: copy-w * 8
        _SCR-COPY-W @ 8 *
        CMOVE
    LOOP

    \ Publish the complete replacement before releasing old ownership.  If
    \ an allocator guard ever rejects an old pointer, the current descriptor
    \ still names a coherent new screen rather than already-freed storage.
    _SCR-TMP @       _SCR-CUR @ _SCR-O-W     + !
    _SCR-TMP2 @      _SCR-CUR @ _SCR-O-H     + !
    _SCR-NEW-FRONT @ _SCR-CUR @ _SCR-O-FRONT + !
    _SCR-NEW-BACK  @ _SCR-CUR @ _SCR-O-BACK  + !
    _SCR-NEW-DAMAGE @ _SCR-CUR @ _SCR-O-DAMAGE + !
    _SCR-NEW-TOUCHED @ _SCR-CUR @ _SCR-O-TOUCHED + !
    \ The replacement FRONT is blank while BACK contains the copied logical
    \ screen.  No completed draw is a legal incremental baseline until the
    \ forced snapshot below is accepted.
    0 _SCR-CUR @ _SCR-O-FRONT-GENERATION + !

    \ Keep the logical cursor valid for the replacement geometry.
    _SCR-CUR @ _SCR-O-CROW + DUP @ 0 MAX SCR-H 1- MIN SWAP !
    _SCR-CUR @ _SCR-O-CCOL + DUP @ 0 MAX SCR-W 1- MIN SWAP !

    \ Force full redraw
    SCR-FORCE

    _SCR-OLD-FRONT @ FREE
    _SCR-OLD-BACK @ FREE
    _SCR-OLD-DAMAGE @ FREE
    _SCR-OLD-TOUCHED @ FREE ;

\ =====================================================================
\ 15. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _scr-guard

' SCR-NEW             CONSTANT _scr-new-xt
' SCR-FREE            CONSTANT _scr-free-xt
' SCR-USE             CONSTANT _scr-use-xt
' SCR-W               CONSTANT _scr-w-xt
' SCR-H               CONSTANT _scr-h-xt
' SCR-DRAW-COMPLETE   CONSTANT _scr-draw-complete-xt
' SCR-DRAW-GENERATION@ CONSTANT _scr-draw-generation-get-xt
' SCR-WITH-BACK-PLANE CONSTANT _scr-with-back-plane-xt
' SCR-WITH-BACK-MUTATION CONSTANT _scr-with-back-mutation-xt
' SCR-WITH-FRAME-PLANES CONSTANT _scr-with-frame-planes-xt
' SCR-SET             CONSTANT _scr-set-xt
' SCR-GET             CONSTANT _scr-get-xt
' SCR-FILL            CONSTANT _scr-fill-xt
' SCR-CLEAR           CONSTANT _scr-clear-xt
' SCR-FLUSH?          CONSTANT _scr-flush-status-xt
' SCR-FLUSH           CONSTANT _scr-flush-xt
' SCR-FORCE           CONSTANT _scr-force-xt
' SCR-REQUEST-FLUSH   CONSTANT _scr-request-flush-xt
' SCR-DIRTY?          CONSTANT _scr-dirty-xt
' SCR-BACKEND@        CONSTANT _scr-backend-get-xt
' SCR-STORAGE-DISJOINT? CONSTANT _scr-storage-disjoint-xt
' SCR-BACKEND!        CONSTANT _scr-backend-set-xt
' SCR-ANSI            CONSTANT _scr-ansi-xt
' SCR-RESIZE          CONSTANT _scr-resize-xt
' SCR-CURSOR-AT       CONSTANT _scr-curat-xt
' SCR-CURSOR-ON       CONSTANT _scr-curon-xt
' SCR-CURSOR-OFF      CONSTANT _scr-curoff-xt

: SCR-NEW             _scr-new-xt    _scr-guard WITH-GUARD ;
: SCR-FREE            _scr-free-xt   _scr-guard WITH-GUARD ;
: SCR-USE             _scr-use-xt    _scr-guard WITH-GUARD ;
: SCR-W               _scr-w-xt      _scr-guard WITH-GUARD ;
: SCR-H               _scr-h-xt      _scr-guard WITH-GUARD ;
: SCR-DRAW-COMPLETE   _scr-draw-complete-xt _scr-guard WITH-GUARD ;
: SCR-DRAW-GENERATION@
    _scr-draw-generation-get-xt _scr-guard WITH-GUARD ;
: SCR-WITH-BACK-PLANE
    _scr-with-back-plane-xt _scr-guard WITH-GUARD ;
: SCR-WITH-BACK-MUTATION
    _scr-with-back-mutation-xt _scr-guard WITH-GUARD ;
: SCR-WITH-FRAME-PLANES
    _scr-with-frame-planes-xt _scr-guard WITH-GUARD ;
: SCR-SET             _scr-set-xt    _scr-guard WITH-GUARD ;
: SCR-GET             _scr-get-xt    _scr-guard WITH-GUARD ;
: SCR-FILL            _scr-fill-xt   _scr-guard WITH-GUARD ;
: SCR-CLEAR           _scr-clear-xt  _scr-guard WITH-GUARD ;
: SCR-FLUSH?          _scr-flush-status-xt _scr-guard WITH-GUARD ;
: SCR-FLUSH           _scr-flush-xt  _scr-guard WITH-GUARD ;
: SCR-FORCE           _scr-force-xt  _scr-guard WITH-GUARD ;
: SCR-REQUEST-FLUSH   _scr-request-flush-xt _scr-guard WITH-GUARD ;
: SCR-DIRTY?          _scr-dirty-xt _scr-guard WITH-GUARD ;
: SCR-BACKEND@        _scr-backend-get-xt _scr-guard WITH-GUARD ;
: SCR-STORAGE-DISJOINT?
    _scr-storage-disjoint-xt _scr-guard WITH-GUARD ;
: SCR-BACKEND!        _scr-backend-set-xt _scr-guard WITH-GUARD ;
: SCR-ANSI            _scr-ansi-xt _scr-guard WITH-GUARD ;
: SCR-RESIZE          _scr-resize-xt _scr-guard WITH-GUARD ;
: SCR-CURSOR-AT       _scr-curat-xt  _scr-guard WITH-GUARD ;
: SCR-CURSOR-ON       _scr-curon-xt  _scr-guard WITH-GUARD ;
: SCR-CURSOR-OFF      _scr-curoff-xt _scr-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _SCR-OWNED-END
_SCR-OWNED-END _SCR-OWNED-LIMIT !
