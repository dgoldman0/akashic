\ =====================================================================
\  akashic/tui/screen.f — Virtual Screen Buffer (double-buffered)
\ =====================================================================
\
\  Double-buffered character-cell screen.  Widgets write to the back
\  buffer.  SCR-FLUSH diffs front vs. back and projects changed cells
\  through a transactional backend.  ANSI is the constructed default;
\  outer composition may bind another transactional backend explicitly.
\
\  Screen Descriptor (29 cells = 232 bytes):
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
\    +120 occlusion    Final-writer overlay provenance, one byte per cell
\    +128 residue      Ordinary paint beneath independently replaced layers
\    +136 residue-dirty Residue changed since the accepted screen transaction
\    +144 residue-damage Rows whose residue changed since accepted COMMIT
\    +152 residue-front Residue baseline of the last accepted transaction
\    +160 .. +224  cluster pool: tables, slots, arena, capacity, bytes
\         used, live count, next ID, pass number, and pass trigger
\         (section 8a)
\
\  Each cell is 8 bytes (one CELL-MAKE value), so a buffer for
\  80×24 is 15,360 bytes × 4 = 61,440 bytes (60 KiB), plus provenance.
\
\  Prefix: SCR- (public), _SCR- (internal)
\  Provider: akashic-tui-screen
\  Dependencies: cell.f, ansi.f, ../text/utf8.f,
\                ../text/cell-width.f, ../text/grapheme.f

PROVIDED akashic-tui-screen

REQUIRE cell.f
REQUIRE ansi.f
REQUIRE ../text/utf8.f
REQUIRE ../text/cell-width.f
REQUIRE ../text/grapheme.f
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
120 CONSTANT _SCR-O-OCCLUSION
128 CONSTANT _SCR-O-RESIDUE
136 CONSTANT _SCR-O-RESIDUE-DIRTY
144 CONSTANT _SCR-O-RESIDUE-DAMAGE
152 CONSTANT _SCR-O-RESIDUE-FRONT
160 CONSTANT _SCR-O-CL-TABLES   \ ID table, then content table, or 0
168 CONSTANT _SCR-O-CL-SLOTS    \ slots per table, a power of two
176 CONSTANT _SCR-O-CL-ARENA    \ cluster entries, or 0
184 CONSTANT _SCR-O-CL-CAP      \ arena bytes
192 CONSTANT _SCR-O-CL-USED     \ arena bytes in use
200 CONSTANT _SCR-O-CL-COUNT    \ clusters in the arena
208 CONSTANT _SCR-O-CL-NEXT     \ next cluster ID
216 CONSTANT _SCR-O-CL-EPOCH    \ mark passes made
224 CONSTANT _SCR-O-CL-TRIGGER  \ count that starts the next pass

232 CONSTANT _SCR-DESC-SIZE

\ Cluster pool entry fields, then its scalars as u32 values.
 0 CONSTANT _SCR-CE-ID
 8 CONSTANT _SCR-CE-HASH
16 CONSTANT _SCR-CE-SEEN      \ the last mark pass that found it
24 CONSTANT _SCR-CE-N         \ scalars
32 CONSTANT _SCR-CE-SCALARS
64 CONSTANT _SCR-CL-MIN-SLOTS
64 CONSTANT _SCR-CL-MIN-TRIGGER
HEX 7FFFFFFF CONSTANT _SCR-CL-ID-MASK DECIMAL

\ =====================================================================
\ 2. Transactional backend ABI
\ =====================================================================

0 CONSTANT SCB-S-OK
1 CONSTANT SCB-S-WOULD-BLOCK
2 CONSTANT SCB-S-SESSION-LOST
3 CONSTANT SCB-S-INVALID
\ BEGIN only: the transaction fits the backend's limits without its cluster
\ tails but not with them.  The screen retries it degraded, every cluster
\ cell sent as U+FFFD (APT-1-WIRE Section 11.1).  SCR-FLUSH? never returns
\ it.
4 CONSTANT SCB-S-TOO-LARGE

0 CONSTANT SCB-M-DELTA
1 CONSTANT SCB-M-SNAPSHOT
\ NONE carries zero CELL spans and deliberately omits the cursor callback;
\ BEGIN/COMMIT still delimit one backend transaction.
2 CONSTANT SCB-M-NONE

\ Callbacks, each taking the descriptor's context last:
\   BEGIN   ( mode cols rows span-count cell-count cluster-words span-peak
\             context -- status )
\   SPAN    ( cells count row col cluster-words context -- status )
\   CURSOR  ( row col visible context -- status )
\   COMMIT  ( context -- status )
\   ABORT   ( context -- )
\ CLUSTER-WORDS counts the CELL-1 cluster-tail words (APT-1-WIRE Section 9)
\ of the transaction, or of one span.  SPAN-PEAK is the largest span body
\ in 32-bit words: two per cell plus its cluster words.  CELLS are native
\ cells of the current screen; SCR-CLUSTER@ reads a cluster cell.  A span
\ declared with zero cluster words carries its cluster cells as U+FFFD.

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

\ CREATE bodies are packed, so reserve alignment explicitly for the
\ descriptor admitted by the same storage checks as caller-owned backends.
CREATE _SCR-ANSI-BACKEND-MEM SCB-DESC-SIZE 7 + ALLOT
_SCR-ANSI-BACKEND-MEM 7 + -8 AND CONSTANT _SCR-ANSI-BACKEND

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
VARIABLE _SCR-SD-CELL-U
VARIABLE _SCR-SD-FRONT
VARIABLE _SCR-SD-BACK
VARIABLE _SCR-SD-DAMAGE
VARIABLE _SCR-SD-TOUCHED
VARIABLE _SCR-SD-OCCLUSION
VARIABLE _SCR-SD-RESIDUE
VARIABLE _SCR-SD-RESIDUE-DAMAGE
VARIABLE _SCR-SD-RESIDUE-FRONT
VARIABLE _SCR-SD-BACKEND
VARIABLE _SCR-BACK-PLANE-XT
VARIABLE _SCR-BACK-MUTATION-XT
VARIABLE _SCR-BACK-MUTATION-SCREEN
VARIABLE _SCR-BACK-MUTATION-LOW
VARIABLE _SCR-BACK-MUTATION-HIGH
VARIABLE _SCR-FRAME-PLANES-XT
VARIABLE _SCR-PROJECTION-PLANES-XT
VARIABLE _SCR-PROJECTION-FRAME-PLANES-XT
VARIABLE _SCR-PLAN-VALID
VARIABLE _SCR-PLAN-SCREEN
VARIABLE _SCR-PLAN-MODE
VARIABLE _SCR-PLAN-SPANS
VARIABLE _SCR-PLAN-CELLS
VARIABLE _SCR-PLAN-WORDS
VARIABLE _SCR-PLAN-PEAK
VARIABLE _SCR-PLAN-DEGRADE
VARIABLE _SCR-OCCLUSION-DEPTH  0 _SCR-OCCLUSION-DEPTH !
VARIABLE _SCR-REPLACEMENT-DEPTH  0 _SCR-REPLACEMENT-DEPTH !

VARIABLE _SCR-OR-ROW
VARIABLE _SCR-OR-COL
VARIABLE _SCR-OR-HEIGHT
VARIABLE _SCR-OR-WIDTH
VARIABLE _SCR-OR-ROW-COUNT
VARIABLE _SCR-OR-COL-COUNT

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
\   Allocate the descriptor, four cell buffers, three row-byte maps, and the
\   dimension-derived overlay-occlusion plane.
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

    \ Allocate one exact byte per physical cell.  This is not a fixed overlay
    \ count: ordinary overlay paint marks the cells it actually covers.
    _SCR-BUF-BYTES @ 8 / ALLOCATE DUP IF
        2DROP
        _SCR-TMP3 @ _SCR-O-TOUCHED + @ FREE
        _SCR-TMP3 @ _SCR-O-DAMAGE + @ FREE
        _SCR-TMP3 @ _SCR-O-BACK + @ FREE
        _SCR-TMP3 @ _SCR-O-FRONT + @ FREE
        _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: occlusion buf alloc failed"
    THEN
    DROP
    _SCR-TMP3 @ _SCR-O-OCCLUSION + !

    \ Keep ordinary paint from the first blank screen onward.  The bound is
    \ exactly the caller's screen dimensions, not an overlay-count limit.
    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP
        _SCR-TMP3 @ _SCR-O-OCCLUSION + @ FREE
        _SCR-TMP3 @ _SCR-O-TOUCHED + @ FREE
        _SCR-TMP3 @ _SCR-O-DAMAGE + @ FREE
        _SCR-TMP3 @ _SCR-O-BACK + @ FREE
        _SCR-TMP3 @ _SCR-O-FRONT + @ FREE
        _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: residue buf alloc failed"
    THEN
    DROP _SCR-TMP3 @ _SCR-O-RESIDUE + !

    _SCR-TMP2 @ ALLOCATE DUP IF
        2DROP
        _SCR-TMP3 @ _SCR-O-RESIDUE + @ FREE
        _SCR-TMP3 @ _SCR-O-OCCLUSION + @ FREE
        _SCR-TMP3 @ _SCR-O-TOUCHED + @ FREE
        _SCR-TMP3 @ _SCR-O-DAMAGE + @ FREE
        _SCR-TMP3 @ _SCR-O-BACK + @ FREE
        _SCR-TMP3 @ _SCR-O-FRONT + @ FREE
        _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: residue damage alloc failed"
    THEN
    DROP _SCR-TMP3 @ _SCR-O-RESIDUE-DAMAGE + !

    \ Exact final residue damage needs the accepted plane, not intermediate
    \ clear/repaint writes.  This baseline advances only after COMMIT accepts.
    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP
        _SCR-TMP3 @ _SCR-O-RESIDUE-DAMAGE + @ FREE
        _SCR-TMP3 @ _SCR-O-RESIDUE + @ FREE
        _SCR-TMP3 @ _SCR-O-OCCLUSION + @ FREE
        _SCR-TMP3 @ _SCR-O-TOUCHED + @ FREE
        _SCR-TMP3 @ _SCR-O-DAMAGE + @ FREE
        _SCR-TMP3 @ _SCR-O-BACK + @ FREE
        _SCR-TMP3 @ _SCR-O-FRONT + @ FREE
        _SCR-TMP3 @ FREE
        -1 ABORT" SCR-NEW: residue front alloc failed"
    THEN
    DROP _SCR-TMP3 @ _SCR-O-RESIDUE-FRONT + !

    \ Fill all CELL planes with the same initial blank.
    _SCR-TMP3 @ _SCR-O-FRONT + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-TMP3 @ _SCR-O-BACK + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-TMP3 @ _SCR-O-RESIDUE + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-TMP3 @ _SCR-O-RESIDUE-FRONT + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-TMP3 @ _SCR-O-DAMAGE + @ _SCR-TMP2 @ 0 FILL
    _SCR-TMP3 @ _SCR-O-TOUCHED + @ _SCR-TMP2 @ 0 FILL
    _SCR-TMP3 @ _SCR-O-RESIDUE-DAMAGE + @ _SCR-TMP2 @ 0 FILL
    _SCR-TMP3 @ _SCR-O-OCCLUSION + @
        _SCR-TMP @ _SCR-TMP2 @ * 0 FILL

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
    0           _SCR-TMP3 @ _SCR-O-RESIDUE-DIRTY + !
    _SCR-ANSI-BACKEND
                _SCR-TMP3 @ _SCR-O-BACKEND + !
    _SCR-TMP3 @ _SCR-O-CL-TABLES + _SCR-DESC-SIZE _SCR-O-CL-TABLES - 0 FILL
    1           _SCR-TMP3 @ _SCR-O-CL-NEXT + !
    _SCR-CL-MIN-TRIGGER _SCR-TMP3 @ _SCR-O-CL-TRIGGER + !

    _SCR-TMP3 @ ;

\ SCR-FREE ( scr -- )
\   Deallocate all four cell buffers, all row maps, and the screen descriptor
\   through the platform allocator that created them.
: SCR-FREE  ( scr -- )
    DUP 0= IF DROP EXIT THEN
    _SCR-PLAN-INVALIDATE
    DUP _SCR-CUR @ = IF 0 _SCR-CUR ! THEN
    DUP _SCR-O-FRONT + @ FREE
    DUP _SCR-O-BACK + @ FREE
    DUP _SCR-O-DAMAGE + @ FREE
    DUP _SCR-O-TOUCHED + @ FREE
    DUP _SCR-O-OCCLUSION + @ FREE
    DUP _SCR-O-RESIDUE + @ FREE
    DUP _SCR-O-RESIDUE-DAMAGE + @ FREE
    DUP _SCR-O-RESIDUE-FRONT + @ FREE
    DUP _SCR-O-CL-TABLES + @ ?DUP IF FREE THEN
    DUP _SCR-O-CL-ARENA + @ ?DUP IF FREE THEN
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

\ These internal words delimit renderer-neutral foreground overlay paint.
\ _SCR-WITH-OCCLUSION balances them through CATCH, including nested scopes.
\ The depth selects which provenance value every subsequent screen write
\ assigns, including equal-value overwrites.
: _SCR-OCCLUSION-BEGIN  ( -- )
    1 _SCR-OCCLUSION-DEPTH +! ;

: _SCR-OCCLUSION-END  ( -- )
    _SCR-OCCLUSION-DEPTH @ 0> IF -1 _SCR-OCCLUSION-DEPTH +! THEN ;

\ _SCR-WITH-OCCLUSION ( body-xt -- )
\   Private cross-module hook for guarded DRW-OVERLAY.  Its caller already
\   owns the draw guard, establishing draw -> screen lock order.  BODY may use
\   ordinary recursive DRW/SCR operations, but must not retain pointers,
\   yield, switch the selected screen, or invoke this hook directly.
: _SCR-WITH-OCCLUSION  ( body-xt -- )
    DUP 0= IF DROP -1 ABORT" _SCR-WITH-OCCLUSION: null body" THEN
    _SCR-OCCLUSION-BEGIN
    CATCH
    _SCR-OCCLUSION-END
    ?DUP IF THROW THEN ;

\ A replacement layer still paints the complete ordinary screen.  Only its
\ alternate residue is protected, so refused semantic admission can always
\ use BACK unchanged.  Foreground occlusion is an independent authority:
\ post-semantic foreground writes must remain visible in both planes.
: _SCR-REPLACEMENT?  ( -- flag )
    _SCR-REPLACEMENT-DEPTH @ 0<> _SCR-OCCLUSION-DEPTH @ 0= AND ;

: _SCR-WITH-REPLACEMENT  ( ... body-xt -- ... )
    DUP 0= IF DROP -1 ABORT" replacement layer: null body" THEN
    1 _SCR-REPLACEMENT-DEPTH +!
    CATCH
    -1 _SCR-REPLACEMENT-DEPTH +!
    ?DUP IF THROW THEN ;

\ _SCR-WITH-DRAW-AUTHORITY ( ... body-xt -- ... )
\   Append the selected screen's completed draw generation to BODY's caller
\   arguments and execute it while screen selection, geometry, and provenance
\   are stable.  This is a private retained-capture hook: BODY must be
\   synchronous and must not enter DRW, mutate the screen, yield, or switch
\   screens.
: _SCR-WITH-DRAW-AUTHORITY  ( ... body-xt -- ... )
    >R
    _SCR-CUR @ ?DUP IF _SCR-O-DRAW-GENERATION + @ ELSE 0 THEN
    R> EXECUTE ;

\ _SCR-OR-SPAN-CLEAR? ( a u -- clear? )
\   True when all U provenance bytes at A are zero, for U >= 1: the first
\   byte is zero and every byte equals its successor.  COMPARE of the span
\   against itself shifted by one byte proves the second part, so a row
\   costs one block compare instead of a per-cell loop, with no zero buffer.
: _SCR-OR-SPAN-CLEAR?  ( a u -- clear? )
    OVER C@ IF 2DROP 0 EXIT THEN
    1- ?DUP 0= IF DROP -1 EXIT THEN
    OVER 1+ OVER COMPARE 0= ;

\ SCR-OCCLUSION-RECT? ( row col height width -- intersects? valid? )
\   Query whether a visible rectangle intersects final-writer foreground
\   provenance paired with the current BACK plane.  The result says nothing
\   about CELL contents; it is painter-order metadata used by renderer-neutral
\   projections and survives partial draws and refused transactions.  The
\   clipped rectangle is tested one row span at a time.
: SCR-OCCLUSION-RECT?
  ( row col height width -- intersects? valid? )
    _SCR-OR-WIDTH ! _SCR-OR-HEIGHT ! _SCR-OR-COL ! _SCR-OR-ROW !
    _SCR-CUR @ 0= IF 0 0 EXIT THEN
    _SCR-OR-ROW @ 0< _SCR-OR-COL @ 0< OR IF 0 0 EXIT THEN
    _SCR-OR-HEIGHT @ 0> _SCR-OR-WIDTH @ 0> AND 0= IF 0 0 EXIT THEN
    _SCR-OR-ROW @ SCR-H U< _SCR-OR-COL @ SCR-W U< AND 0= IF
        0 -1 EXIT
    THEN
    _SCR-OR-HEIGHT @ SCR-H _SCR-OR-ROW @ - MIN _SCR-OR-ROW-COUNT !
    _SCR-OR-WIDTH @ SCR-W _SCR-OR-COL @ - MIN _SCR-OR-COL-COUNT !
    _SCR-OR-ROW-COUNT @ 0 ?DO
        _SCR-CUR @ _SCR-O-OCCLUSION + @
            _SCR-OR-ROW @ I + SCR-W * + _SCR-OR-COL @ +
        _SCR-OR-COL-COUNT @ _SCR-OR-SPAN-CLEAR? 0= IF
            -1 -1 UNLOOP EXIT
        THEN
    LOOP
    0 -1 ;

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

VARIABLE _SCR-RD-BACK
VARIABLE _SCR-RD-FRONT
VARIABLE _SCR-RD-MAP
VARIABLE _SCR-RD-ROW-BYTES

: _SCR-RESIDUE-SCAN-RESET  ( -- )
    _SCR-CUR @ DUP _SCR-O-RESIDUE + @ _SCR-RD-BACK !
    DUP _SCR-O-RESIDUE-FRONT + @ _SCR-RD-FRONT !
    DUP _SCR-O-RESIDUE-DAMAGE + @ _SCR-RD-MAP !
    _SCR-O-W + @ 8 * _SCR-RD-ROW-BYTES ! ;

: _SCR-RESIDUE-NEXT-ROW  ( -- )
    _SCR-RD-ROW-BYTES @ DUP _SCR-RD-BACK +! _SCR-RD-FRONT +! ;

\ Writers mark a changed row 255.  Resolve it against the accepted residue:
\ zero means equal, one means an exact difference already proved.  Another
\ write restores 255, so repeated getters need not rescan confirmed rows.
\ This refinement changes no pixels and runs under the same screen guard as
\ the projection borrow.  Refusal preserves the accepted comparison plane.
: _SCR-RESIDUE-RESOLVE  ( -- )
    _SCR-CUR @ DUP 0= IF DROP EXIT THEN
    _SCR-O-RESIDUE-DIRTY + @ 0= IF EXIT THEN
    _SCR-RESIDUE-SCAN-RESET
    0 _SCR-CUR @ _SCR-O-RESIDUE-DIRTY + !
    _SCR-CUR @ _SCR-O-H + @ 0 ?DO
        _SCR-RD-MAP @ I + DUP C@ 255 = IF
            _SCR-RD-FRONT @ _SCR-RD-ROW-BYTES @
            _SCR-RD-BACK @ _SCR-RD-ROW-BYTES @ COMPARE 0<> 1 AND
            OVER C!
        THEN
        C@ IF -1 _SCR-CUR @ _SCR-O-RESIDUE-DIRTY + ! THEN
        _SCR-RESIDUE-NEXT-ROW
    LOOP ;

: _SCR-RESIDUE-ADVANCE-FRONT  ( -- )
    _SCR-RESIDUE-RESOLVE
    _SCR-CUR @ _SCR-O-RESIDUE-DIRTY + @ 0= IF EXIT THEN
    _SCR-RESIDUE-SCAN-RESET
    _SCR-CUR @ _SCR-O-H + @ 0 ?DO
        _SCR-RD-MAP @ I + C@ IF
            _SCR-RD-BACK @ _SCR-RD-FRONT @ _SCR-RD-ROW-BYTES @ CMOVE
        THEN
        _SCR-RESIDUE-NEXT-ROW
    LOOP ;

\ Both planes name the same completed ordinary draw.  Borrowing is read-only
\ and synchronous, including under a surrounding frame-plane borrow.  DIRTY?
\ survives refused transactions even when FRONT and BACK happen to agree.
: SCR-WITH-PROJECTION-PLANES  ( xt -- ... )
    _SCR-PROJECTION-PLANES-XT !
    _SCR-RESIDUE-RESOLVE
    _SCR-CUR @ >R
    R@ _SCR-O-BACK + @ R@ _SCR-O-RESIDUE + @
    R@ _SCR-O-W + @ R@ _SCR-O-H + @
    R@ _SCR-O-DRAW-GENERATION + @
    R> _SCR-O-RESIDUE-DIRTY + @ 0<>
    _SCR-PROJECTION-PLANES-XT @ EXECUTE ;

: SCR-PROJECTION-DIRTY?  ( -- flag )
    _SCR-RESIDUE-RESOLVE
    _SCR-CUR @ ?DUP IF _SCR-O-RESIDUE-DIRTY + @ 0<> ELSE 0 THEN ;

\ SCR-WITH-BACK-MUTATION ( xt -- )
\   Execute one synchronous mutable borrow of the selected back plane and its
\   exact final-writer provenance plane:
\     xt: ( cells-a residue-a residue-dirty-a residue-damage-a occlusion-a cols rows overlay? replacement?
\           -- row-low row-high wrote? )
\   A true result marks the half-open physical row interval, invalidates the
\   retry plan, and dirties the captured screen exactly once.  Discontiguous
\   writes may conservatively return their bounding interval.  A malformed
\   true interval or THROW marks every row before callback state is scrubbed.
\
\   The address is valid only for the dynamic extent of XT.  XT must not
\   retain it, yield, or re-enter any SCR- word other than the plane-writer
\   words of section 8b, which touch only the borrowed row and the screen's
\   scratch.  Every written CELL must
\   assign its matching occlusion byte to OVERLAY? (zero or -1), including
\   equal-value overwrites; otherwise final painter order is undefined.
\   Outside a replacement layer every written CELL must also update RESIDUE.
\   A changed residue value sets RESIDUE-DIRTY to true, even if BACK is equal.
\   It also marks the exact physical row in RESIDUE-DAMAGE.
\   Guarded builds hold the screen guard across the complete callback.
: _SCR-BACK-MUTATION-CALL  ( -- row-low row-high wrote? )
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-BACK + @
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-RESIDUE + @
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-RESIDUE-DIRTY +
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-RESIDUE-DAMAGE + @
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-OCCLUSION + @
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-W + @
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-H + @
    _SCR-OCCLUSION-DEPTH @ 0<> IF -1 ELSE 0 THEN
    _SCR-REPLACEMENT?
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
    -1 _SCR-BACK-MUTATION-SCREEN @ _SCR-O-RESIDUE-DIRTY + !
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-RESIDUE-DAMAGE + @
    _SCR-BACK-MUTATION-SCREEN @ _SCR-O-H + @ -1 FILL
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

\ The projection peer keeps the original frame callback ABI unchanged and
\ adds residue authority under the same guard, without a nested screen call.
\   xt: ( front-a back-a cols rows front-draw draw force?
\         damage-a damage-u residue-a residue-damage-a residue-damage-u -- ... )
: SCR-WITH-PROJECTION-FRAME-PLANES  ( xt -- ... )
    _SCR-PROJECTION-FRAME-PLANES-XT !
    _SCR-RESIDUE-RESOLVE
    _SCR-CUR @ >R
    R@ _SCR-O-FRONT + @ R@ _SCR-O-BACK + @
    R@ _SCR-O-W + @ R@ _SCR-O-H + @
    R@ _SCR-O-FRONT-GENERATION + @ R@ _SCR-O-DRAW-GENERATION + @
    R@ _SCR-O-FORCE + @ IF -1 ELSE 0 THEN
    R@ _SCR-PLAN-DAMAGE@
    R@ _SCR-O-RESIDUE + @ R@ _SCR-O-RESIDUE-DAMAGE + @
    R> _SCR-O-H + @
    _SCR-PROJECTION-FRAME-PLANES-XT @ EXECUTE ;

\ =====================================================================
\ 8a. Cluster pool
\ =====================================================================
\
\  A character of several scalars (APT-1-TEXT Section 3) occupies its
\  lead cell as a reference into its screen's pool: CELL-CP-CLUSTER is
\  set in the codepoint field and the low 31 bits are the cluster's ID.
\  Clusters are interned, so equal characters make equal cells and the
\  flush diff compares them exactly.  IDs only grow and are never reused;
\  when they run out, SCR-CLUSTER returns U+FFFD.
\
\  An accepted flush that finds enough new clusters makes one
\  mark-and-sweep pass over the four CELL planes.  A cluster is freed only
\  when neither that pass nor the one before found it, so a cell value
\  kept outside the planes across one flush, such as a saved cursor cell,
\  stays valid.  The pool is two allocations: the ID and content hash
\  tables, and an arena of entries that each pass compacts.

: _SCR-CE-BYTES  ( n -- bytes )  4 * _SCR-CE-SCALARS + 7 + -8 AND ;

: _SCR-CL-HASH  ( a n -- hash )
    0xCBF29CE484222325 SWAP 0 ?DO
        OVER I 4 * + L@ XOR 0x100000001B3 *
    LOOP NIP ;

: _SCR-CL-IDS    ( -- a )  _SCR-CUR @ _SCR-O-CL-TABLES + @ ;
: _SCR-CL-TEXTS  ( -- a )
    _SCR-CL-IDS _SCR-CUR @ _SCR-O-CL-SLOTS + @ 8 * + ;
: _SCR-CL-MASK   ( -- m )  _SCR-CUR @ _SCR-O-CL-SLOTS + @ 1- ;
: _SCR-CL-ARENA  ( -- a )  _SCR-CUR @ _SCR-O-CL-ARENA + @ ;

\ Table slots hold an entry's arena offset plus one; zero is empty.
: _SCR-CL-FIND  ( id -- entry | 0 )
    _SCR-CUR @ _SCR-O-CL-TABLES + @ 0= IF DROP 0 EXIT THEN
    DUP _SCR-CL-MASK AND
    BEGIN
        DUP 8 * _SCR-CL-IDS + @ ?DUP
    WHILE
        1- _SCR-CL-ARENA + DUP @ 3 PICK = IF NIP NIP EXIT THEN DROP
        1+ _SCR-CL-MASK AND
    REPEAT
    2DROP 0 ;

VARIABLE _SCR-CI-A
VARIABLE _SCR-CI-N
VARIABLE _SCR-CI-H
VARIABLE _SCR-CI-E

: _SCR-CL-MATCH?  ( entry -- flag )
    DUP _SCR-CE-HASH + @ _SCR-CI-H @ <> IF DROP 0 EXIT THEN
    DUP _SCR-CE-N + @ _SCR-CI-N @ <> IF DROP 0 EXIT THEN
    _SCR-CE-SCALARS + _SCR-CI-N @ 4 *
    _SCR-CI-A @ _SCR-CI-N @ 4 * COMPARE 0= ;

: _SCR-CL-LOOKUP  ( -- entry | 0 )
    _SCR-CUR @ _SCR-O-CL-TABLES + @ 0= IF 0 EXIT THEN
    _SCR-CI-H @ _SCR-CL-MASK AND
    BEGIN
        DUP 8 * _SCR-CL-TEXTS + @ ?DUP
    WHILE
        1- _SCR-CL-ARENA + DUP _SCR-CL-MATCH? IF NIP EXIT THEN DROP
        1+ _SCR-CL-MASK AND
    REPEAT
    DROP 0 ;

: _SCR-CL-PUT  ( offset -- )
    DUP _SCR-CL-ARENA + DUP @ _SCR-CL-MASK AND
    BEGIN DUP 8 * _SCR-CL-IDS + @ WHILE 1+ _SCR-CL-MASK AND REPEAT
    8 * _SCR-CL-IDS + 2 PICK 1+ SWAP !
    _SCR-CE-HASH + @ _SCR-CL-MASK AND
    BEGIN DUP 8 * _SCR-CL-TEXTS + @ WHILE 1+ _SCR-CL-MASK AND REPEAT
    8 * _SCR-CL-TEXTS + SWAP 1+ SWAP ! ;

: _SCR-CL-REINDEX  ( -- )
    _SCR-CL-IDS _SCR-CUR @ _SCR-O-CL-SLOTS + @ 16 * 0 FILL
    0 BEGIN DUP _SCR-CUR @ _SCR-O-CL-USED + @ < WHILE
        DUP _SCR-CL-PUT
        DUP _SCR-CL-ARENA + _SCR-CE-N + @ _SCR-CE-BYTES +
    REPEAT DROP ;

\ Keep both tables at most half full.
: _SCR-CL-TABLES-FIT?  ( -- ok? )
    _SCR-CUR @ _SCR-O-CL-COUNT + @ 1+ 2*
    _SCR-CUR @ _SCR-O-CL-SLOTS + @ > 0= IF -1 EXIT THEN
    _SCR-CUR @ _SCR-O-CL-SLOTS + @ 2* _SCR-CL-MIN-SLOTS MAX
    DUP 16 * ALLOCATE IF 2DROP 0 EXIT THEN
    _SCR-CUR @ _SCR-O-CL-TABLES + @ ?DUP IF FREE THEN
    _SCR-CUR @ _SCR-O-CL-TABLES + !
    _SCR-CUR @ _SCR-O-CL-SLOTS + !
    _SCR-CL-REINDEX -1 ;

: _SCR-CL-ARENA-FIT?  ( bytes -- ok? )
    _SCR-CUR @ _SCR-O-CL-USED + @ +
    DUP _SCR-CUR @ _SCR-O-CL-CAP + @ > 0= IF DROP -1 EXIT THEN
    _SCR-CUR @ _SCR-O-CL-CAP + @ 2* MAX 1024 MAX
    DUP ALLOCATE IF 2DROP 0 EXIT THEN
    _SCR-CL-ARENA ?DUP IF
        DUP 2 PICK _SCR-CUR @ _SCR-O-CL-USED + @ CMOVE FREE
    THEN
    _SCR-CUR @ _SCR-O-CL-ARENA + !
    _SCR-CUR @ _SCR-O-CL-CAP + ! -1 ;

\ SCR-CLUSTER ( a n -- cp )
\   The codepoint field for the character whose N display scalars, N at
\   least 2, are u32 values at A, in the current screen's pool.  U+FFFD
\   when the pool can hold no more.  The drawing words call this before
\   they borrow the plane they write.
: SCR-CLUSTER  ( a n -- cp )
    _SCR-CI-N ! _SCR-CI-A !
    _SCR-CI-A @ _SCR-CI-N @ _SCR-CL-HASH _SCR-CI-H !
    _SCR-CL-LOOKUP ?DUP IF @ CELL-CP-CLUSTER OR EXIT THEN
    _SCR-CUR @ _SCR-O-CL-NEXT + @ _SCR-CL-ID-MASK U> IF 0xFFFD EXIT THEN
    _SCR-CL-TABLES-FIT? 0= IF 0xFFFD EXIT THEN
    _SCR-CI-N @ _SCR-CE-BYTES _SCR-CL-ARENA-FIT? 0= IF 0xFFFD EXIT THEN
    _SCR-CUR @ _SCR-O-CL-USED + @
    DUP _SCR-CL-ARENA + _SCR-CI-E !
    _SCR-CUR @ _SCR-O-CL-NEXT + @ _SCR-CI-E @ _SCR-CE-ID + !
    _SCR-CI-H @ _SCR-CI-E @ _SCR-CE-HASH + !
    _SCR-CUR @ _SCR-O-CL-EPOCH + @ _SCR-CI-E @ _SCR-CE-SEEN + !
    _SCR-CI-N @ _SCR-CI-E @ _SCR-CE-N + !
    _SCR-CI-A @ _SCR-CI-E @ _SCR-CE-SCALARS + _SCR-CI-N @ 4 * CMOVE
    _SCR-CI-N @ _SCR-CE-BYTES _SCR-CUR @ _SCR-O-CL-USED + +!
    _SCR-CL-PUT
    1 _SCR-CUR @ _SCR-O-CL-COUNT + +!
    _SCR-CUR @ _SCR-O-CL-NEXT + @ DUP 1+ _SCR-CUR @ _SCR-O-CL-NEXT + !
    CELL-CP-CLUSTER OR ;

\ SCR-CLUSTER@ ( cell -- a n )
\   The display scalars of a cluster cell of the current screen, as N
\   u32 values at A, or 0 0 for an unknown reference.  They stay valid
\   until the screen is next drawn or flushed.
: SCR-CLUSTER@  ( cell -- a n )
    _SCR-CL-ID-MASK AND _SCR-CL-FIND ?DUP IF
        DUP _SCR-CE-SCALARS + SWAP _SCR-CE-N + @ EXIT
    THEN
    0 0 ;

\ SCR-CLUSTER-WORDS ( cell -- n )
\   The CELL-1 cluster-tail words of one cell (APT-1-WIRE Section 9):
\   its extra count plus its extras, or 0 for a cell of one scalar.
: SCR-CLUSTER-WORDS  ( cell -- n )
    DUP CELL-CP-CLUSTER AND 0= IF DROP 0 EXIT THEN
    SCR-CLUSTER@ NIP ;

VARIABLE _SCR-CM-LIVE

: _SCR-CL-MARK-PLANE  ( plane-a -- )
    _SCR-CUR @ _SCR-CELLS 8 * OVER + SWAP ?DO
        I @ DUP CELL-CP-CLUSTER AND IF
            _SCR-CL-ID-MASK AND _SCR-CL-FIND ?DUP IF
                _SCR-CE-SEEN + DUP @ _SCR-CUR @ _SCR-O-CL-EPOCH + @ <> IF
                    _SCR-CUR @ _SCR-O-CL-EPOCH + @ SWAP !
                    1 _SCR-CM-LIVE +!
                ELSE DROP THEN
            THEN
        ELSE DROP THEN
    8 +LOOP ;

VARIABLE _SCR-CS-SRC
VARIABLE _SCR-CS-DST
VARIABLE _SCR-CS-BYTES

\ Free every entry that neither this pass nor the last one found and
\ compact the survivors toward the start of the arena.
: _SCR-CL-SWEEP  ( -- )
    0 _SCR-CS-SRC ! 0 _SCR-CS-DST !
    BEGIN _SCR-CS-SRC @ _SCR-CUR @ _SCR-O-CL-USED + @ < WHILE
        _SCR-CL-ARENA _SCR-CS-SRC @ +
        DUP _SCR-CE-N + @ _SCR-CE-BYTES _SCR-CS-BYTES !
        _SCR-CE-SEEN + @ 1+ _SCR-CUR @ _SCR-O-CL-EPOCH + @ < IF
            -1 _SCR-CUR @ _SCR-O-CL-COUNT + +!
        ELSE
            _SCR-CS-SRC @ _SCR-CS-DST @ <> IF
                _SCR-CL-ARENA DUP _SCR-CS-SRC @ + SWAP _SCR-CS-DST @ +
                _SCR-CS-BYTES @ CMOVE
            THEN
            _SCR-CS-BYTES @ _SCR-CS-DST +!
        THEN
        _SCR-CS-BYTES @ _SCR-CS-SRC +!
    REPEAT
    _SCR-CS-DST @ _SCR-CUR @ _SCR-O-CL-USED + !
    _SCR-CL-REINDEX ;

\ After an accepted flush: one pass once the clusters added since the last
\ pass reach the larger of the minimum and the live count it found.
: _SCR-CL-COLLECT  ( -- )
    _SCR-CUR @ _SCR-O-CL-COUNT + @
    _SCR-CUR @ _SCR-O-CL-TRIGGER + @ < IF EXIT THEN
    1 _SCR-CUR @ _SCR-O-CL-EPOCH + +!
    0 _SCR-CM-LIVE !
    _SCR-CUR @ _SCR-O-FRONT + @ _SCR-CL-MARK-PLANE
    _SCR-CUR @ _SCR-O-BACK + @ _SCR-CL-MARK-PLANE
    _SCR-CUR @ _SCR-O-RESIDUE + @ _SCR-CL-MARK-PLANE
    _SCR-CUR @ _SCR-O-RESIDUE-FRONT + @ _SCR-CL-MARK-PLANE
    _SCR-CL-SWEEP
    _SCR-CUR @ _SCR-O-CL-COUNT + @
    _SCR-CM-LIVE @ _SCR-CL-MIN-TRIGGER MAX +
    _SCR-CUR @ _SCR-O-CL-TRIGGER + ! ;

\ =====================================================================
\ 8b. Wide pairs
\ =====================================================================
\
\  A wide character's lead cell is WIDE and its right neighbour is its
\  CONT cell, with codepoint 0 and the lead's style (APT-1-TEXT Section
\  6).  Every write keeps each plane row whole: a wide lead writes its
\  continuation, a continuation restyles its lead, and a write that
\  breaks a pair turns the other half into a space in its own style.
\  _SCR-NORMALIZE first makes a one-scalar cell's WIDE bit match its
\  width and replaces a scalar that cannot be shown.

HEX
0080000000000000 CONSTANT _SCR-C-WIDE
0100000000000000 CONSTANT _SCR-C-CONT
0180000000000000 CONSTANT _SCR-C-PAIR
DECIMAL

: _SCR-HALF-BLANK  ( cell -- cell' )
    _SCR-C-PAIR INVERT AND _CELL-CP-CLR AND 32 OR ;

: _SCR-NORMALIZE  ( cell -- cell' )
    DUP _CELL-CP-MASK AND
    DUP 0x20 0x7F WITHIN IF DROP _SCR-C-WIDE INVERT AND EXIT THEN
    DUP 0= IF DROP EXIT THEN
    OVER _SCR-C-CONT CELL-CP-CLUSTER OR AND IF DROP EXIT THEN
    DUP 0x10FFFF U> OVER 0xD800 0xE000 WITHIN OR IF DROP 0xFFFD THEN
    DUP CW-CHAR-WIDTH                      ( cell cp w )
    DUP 0= IF 2DROP 32 1 THEN
    OVER UP-PROPS UP-INVALID? IF 2DROP 0xFFFD 1 THEN
    >R SWAP _CELL-CP-CLR AND OR _SCR-C-WIDE INVERT AND
    R> 2 = IF _SCR-C-WIDE OR THEN ;

VARIABLE _SCR-PP-ROW    \ plane row base address
VARIABLE _SCR-PP-W
VARIABLE _SCR-PP-COL
VARIABLE _SCR-PP-CELL
VARIABLE _SCR-PP-LO     \ first column written
VARIABLE _SCR-PP-HI     \ one past the last column written

: _SCR-PP@  ( col -- cell )  8 * _SCR-PP-ROW @ + @ ;

: _SCR-PP!  ( cell col -- )
    DUP _SCR-PP-LO @ MIN _SCR-PP-LO !
    DUP 1+ _SCR-PP-HI @ MAX _SCR-PP-HI !
    8 * _SCR-PP-ROW @ + ! ;

\ A lead left of COL loses its continuation.
: _SCR-PP-REPAIR-LEFT  ( col -- )
    DUP 0= IF DROP EXIT THEN
    1- DUP _SCR-PP@ DUP _SCR-C-WIDE AND IF
        _SCR-HALF-BLANK SWAP _SCR-PP!
    ELSE 2DROP THEN ;

\ A continuation at COL loses its lead.
: _SCR-PP-REPAIR-RIGHT  ( col -- )
    DUP _SCR-PP-W @ < 0= IF DROP EXIT THEN
    DUP _SCR-PP@ DUP _SCR-C-CONT AND IF
        _SCR-HALF-BLANK SWAP _SCR-PP!
    ELSE 2DROP THEN ;

\ _SCR-PAIR-PUT ( cell col row-a w -- )
\   Write CELL at column COL of one plane row, keeping every pair whole.
\   Sets _SCR-PP-LO and _SCR-PP-HI to the columns written; the caller
\   has normalized CELL.
: _SCR-PAIR-PUT  ( cell col row-a w -- )
    _SCR-PP-W ! _SCR-PP-ROW !
    DUP _SCR-PP-COL ! DUP _SCR-PP-LO ! _SCR-PP-HI !
    _SCR-PP-CELL !
    _SCR-PP-CELL @ _SCR-C-CONT AND IF
        _SCR-PP-COL @ IF
            _SCR-PP-COL @ 1- _SCR-PP@ DUP _SCR-C-WIDE AND IF
                \ One style for the pair: the lead keeps its codepoint.
                _CELL-CP-MASK AND
                _SCR-PP-CELL @ _CELL-CP-CLR AND _SCR-C-PAIR INVERT AND
                _SCR-C-WIDE OR OR _SCR-PP-COL @ 1- _SCR-PP!
                _SCR-PP-CELL @ _CELL-CP-CLR AND _SCR-C-WIDE INVERT AND
                _SCR-PP-COL @ _SCR-PP! EXIT
            THEN DROP
        THEN
        _SCR-PP-CELL @ _SCR-HALF-BLANK _SCR-PP-CELL !
    THEN
    _SCR-PP-CELL @ _SCR-C-WIDE AND IF
        _SCR-PP-COL @ 1+ _SCR-PP-W @ < IF
            _SCR-PP-COL @ _SCR-PP-REPAIR-LEFT
            _SCR-PP-CELL @ _SCR-PP-COL @ _SCR-PP!
            _SCR-PP-CELL @ _CELL-CP-CLR AND _SCR-C-PAIR INVERT AND
            _SCR-C-CONT OR _SCR-PP-COL @ 1+ _SCR-PP!
            _SCR-PP-COL @ 2 + _SCR-PP-REPAIR-RIGHT EXIT
        THEN
        \ No room for the right half at the edge of the screen.
        _SCR-PP-CELL @ _SCR-HALF-BLANK _SCR-PP-CELL !
    THEN
    _SCR-PP-COL @ _SCR-PP-REPAIR-LEFT
    _SCR-PP-CELL @ _SCR-PP-COL @ _SCR-PP!
    _SCR-PP-COL @ 1+ _SCR-PP-REPAIR-RIGHT ;

\ The drawing layer writes a borrowed plane (SCR-WITH-BACK-MUTATION)
\ through these words, inside that borrow.
\   SCR-CELL-NORMALIZE ( cell -- cell' )  as SCR-SET normalizes
\   SCR-CELL-PAIR?     ( cell -- flag )   WIDE or CONT
\   SCR-CELL-SPACE     ( cell -- cell' )  a narrow space in its style
\   SCR-ROW-PUT        ( cell col row-a cols -- lo hi )
\       write a normalized CELL into one plane row as SCR-SET does and
\       return the half-open range of columns written.
: SCR-CELL-NORMALIZE  ( cell -- cell' )  _SCR-NORMALIZE ;
: SCR-CELL-PAIR?      ( cell -- flag )   _SCR-C-PAIR AND 0<> ;
: SCR-CELL-SPACE      ( cell -- cell' )  _SCR-HALF-BLANK ;
: SCR-ROW-PUT  ( cell col row-a cols -- lo hi )
    _SCR-PAIR-PUT _SCR-PP-LO @ _SCR-PP-HI @ ;

\ =====================================================================
\ 8. Cell read/write
\ =====================================================================

\ SCR-SET ( cell row col -- )   Write cell to back buffer.
: _SCR-RESIDUE-CHANGED!  ( byte-offset -- )
    -1 _SCR-CUR @ _SCR-O-RESIDUE-DIRTY + !
    8 / _SCR-CUR @ _SCR-O-W + @ /
    _SCR-CUR @ _SCR-O-RESIDUE-DAMAGE + @ + -1 SWAP C! ;

VARIABLE _SCR-SET-CELL
VARIABLE _SCR-SET-ROW
VARIABLE _SCR-SET-COL

: _SCR-ROW-A  ( plane-a row -- row-a )  _SCR-CUR @ _SCR-O-W + @ * 8 * + ;

\ Every column a pair write touched takes the writer's provenance.
: _SCR-SET-OCCLUSION  ( -- )
    _SCR-OCCLUSION-DEPTH @ 0<> IF -1 ELSE 0 THEN
    _SCR-CUR @ _SCR-O-OCCLUSION + @
    _SCR-SET-ROW @ _SCR-CUR @ _SCR-O-W + @ * + _SCR-PP-LO @ +
    _SCR-PP-HI @ _SCR-PP-LO @ - ROT FILL ;

: SCR-SET  ( cell row col -- )
    _SCR-SET-COL ! _SCR-SET-ROW ! _SCR-NORMALIZE _SCR-SET-CELL !
    _SCR-PLAN-INVALIDATE
    _SCR-SET-ROW @ _SCR-TOUCHED!
    -1 _SCR-CUR @ _SCR-O-DIRTY + !
    _SCR-REPLACEMENT? 0= IF
        _SCR-CUR @ _SCR-O-RESIDUE + @ _SCR-SET-ROW @ _SCR-ROW-A
        DUP _SCR-SET-COL @ 8 * + @ >R
        _SCR-SET-CELL @ _SCR-SET-COL @ ROT _SCR-CUR @ _SCR-O-W + @
        _SCR-PAIR-PUT
        R> _SCR-CUR @ _SCR-O-RESIDUE + @ _SCR-SET-ROW @ _SCR-ROW-A
        _SCR-SET-COL @ 8 * + @ <>
        _SCR-PP-HI @ _SCR-PP-LO @ - 1 <> OR IF
            _SCR-SET-ROW @ _SCR-CUR @ _SCR-O-W + @ * 8 *
            _SCR-RESIDUE-CHANGED!
        THEN
    THEN
    _SCR-SET-CELL @ _SCR-SET-COL @
    _SCR-CUR @ _SCR-O-BACK + @ _SCR-SET-ROW @ _SCR-ROW-A
    _SCR-CUR @ _SCR-O-W + @ _SCR-PAIR-PUT
    _SCR-SET-OCCLUSION ;

\ SCR-GET ( row col -- cell )   Read cell from back buffer.
: SCR-GET  ( row col -- cell )
    _SCR-IDX _SCR-CUR @ _SCR-O-BACK + @ + @ ;

\ SCR-FRONT@ ( row col -- cell )  Read cell from front buffer.
: SCR-FRONT@  ( row col -- cell )
    _SCR-IDX _SCR-CUR @ _SCR-O-FRONT + @ + @ ;

\ SCR-FILL ( cell -- )   Fill entire back buffer with given cell.
\   A wide cell fills as a space in its style.
: SCR-FILL  ( cell -- )
    _SCR-NORMALIZE DUP _SCR-C-PAIR AND IF _SCR-HALF-BLANK THEN
    _SCR-PLAN-INVALIDATE
    _SCR-TOUCHED-ALL
    -1 _SCR-CUR @ _SCR-O-DIRTY + !
    _SCR-REPLACEMENT? 0= IF
        DUP _SCR-FILL-VAL !
        _SCR-CUR @ _SCR-O-RESIDUE + @
        _SCR-CUR @ _SCR-CELLS 0 ?DO
            DUP @ _SCR-FILL-VAL @ <> IF
                I 8 * _SCR-RESIDUE-CHANGED!
            THEN
            _SCR-FILL-VAL @ OVER ! 8 +
        LOOP DROP
    THEN
    _SCR-CUR @ _SCR-O-OCCLUSION + @
    _SCR-CUR @ _SCR-CELLS
    _SCR-OCCLUSION-DEPTH @ 0<> IF -1 ELSE 0 THEN FILL
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
    _SCR-SD-BUF-U @ 8 / _SCR-SD-CELL-U !
    _SCR-SD-SCREEN @ _SCR-O-FRONT + @ _SCR-SD-FRONT !
    _SCR-SD-SCREEN @ _SCR-O-BACK + @ _SCR-SD-BACK !
    _SCR-SD-SCREEN @ _SCR-O-DAMAGE + @ _SCR-SD-DAMAGE !
    _SCR-SD-SCREEN @ _SCR-O-TOUCHED + @ _SCR-SD-TOUCHED !
    _SCR-SD-SCREEN @ _SCR-O-OCCLUSION + @ _SCR-SD-OCCLUSION !
    _SCR-SD-SCREEN @ _SCR-O-RESIDUE + @ _SCR-SD-RESIDUE !
    _SCR-SD-SCREEN @ _SCR-O-RESIDUE-DAMAGE + @ _SCR-SD-RESIDUE-DAMAGE !
    _SCR-SD-SCREEN @ _SCR-O-RESIDUE-FRONT + @ _SCR-SD-RESIDUE-FRONT !
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @ _SCR-ALIGNED-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @ _SCR-ALIGNED-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @ _SCR-ALIGNED-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @ _SCR-ALIGNED-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-OPTIONAL-BYTE-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-OPTIONAL-BYTE-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-OPTIONAL-BYTE-SPAN? 0= IF 0 EXIT THEN
    _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
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
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @ _SCR-MODULE-DISJOINT? 0= IF
        0 EXIT
    THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @ _SCR-MODULE-DISJOINT? 0= IF
        0 EXIT
    THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-MODULE-DISJOINT? 0= IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-MODULE-DISJOINT? 0= IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-MODULE-DISJOINT? 0= IF 0 EXIT THEN
    _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
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
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-BACK @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
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
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @
        _SCR-SD-SCREEN @ _SCR-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @
        _SCR-SD-FRONT @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @
        _SCR-SD-BACK @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-SCREEN @ _SCR-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-FRONT @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-BACK @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-SCREEN @ _SCR-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-FRONT @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-BACK @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @
        _SCR-SD-BACKEND @ SCB-DESC-SIZE MSPAN-OVERLAP? 0= ;

\ SCR-STORAGE-DISJOINT? ( a u -- flag )
\   Prove that caller storage cannot mutate the active screen while a
\   projection reads it.  The protected graph is the complete screen module,
\   current descriptor, all four CELL planes, all row maps, the overlay
\   occlusion plane, the cluster pool, and the borrowed backend descriptor.
\   Backend context remains opaque and must be checked by its owning API.
: SCR-STORAGE-DISJOINT?  ( a u -- flag )
    _SCR-SD-U ! _SCR-SD-A !
    _SCR-SD-A @ _SCR-SD-U @ _SCR-OPTIONAL-BYTE-SPAN? 0= IF 0 EXIT THEN
    _SCR-ACTIVE-STORAGE-VALID? 0= IF 0 EXIT THEN
    _SCR-SD-A @ _SCR-SD-U @ _SCR-MODULE-DISJOINT? 0= IF 0 EXIT THEN
    _SCR-SD-U @ 0= IF -1 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-DESC-SIZE _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-FRONT @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACK @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-FRONT @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-TOUCHED @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-RESIDUE-DAMAGE @ _SCR-SD-SCREEN @ _SCR-O-H + @
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-OCCLUSION @ _SCR-SD-CELL-U @
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-BACKEND @ SCB-DESC-SIZE _SCR-SD-OVERLAP? IF 0 EXIT THEN
    _SCR-SD-SCREEN @ _SCR-O-CL-TABLES + @ ?DUP IF
        _SCR-SD-SCREEN @ _SCR-O-CL-SLOTS + @ 16 *
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    THEN
    _SCR-SD-SCREEN @ _SCR-O-CL-ARENA + @ ?DUP IF
        _SCR-SD-SCREEN @ _SCR-O-CL-CAP + @
        _SCR-SD-OVERLAP? IF 0 EXIT THEN
    THEN
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
\   Compares against last emitted state, emits only diffs.  Only the
\   style bits 0-6 are compared; WIDE and CONT are not styles.
: _SCR-EMIT-ATTRS  ( cell -- )
    DUP CELL-ATTRS@ 127 AND DUP _SCR-LAST-ATTRS @ <> IF
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

: _SCR-EMIT-SCALAR  ( cp -- )
    DUP 32 < IF DROP 0xFFFD THEN
    DUP 128 < IF
        EMIT                           \ ASCII fast path
    ELSE
        _SCR-UTF8-BUF UTF8-ENCODE _SCR-UTF8-BUF -
        _SCR-UTF8-BUF SWAP TYPE        \ emit multi-byte sequence
    THEN ;

\ The terminal joins scalars into characters as it reads them.  The
\ backend follows the same segmentation across the characters it emits
\ and, where two cells' characters would join, repositions the cursor
\ first: any escape sequence ends the terminal's open character.
CREATE _SCBA-SEG GR-STATE-SIZE ALLOT
VARIABLE _SCBA-EMIT-ROW
VARIABLE _SCBA-EMIT-COL

: _SCBA-FIRST  ( cell -- cp )
    DUP CELL-CP-CLUSTER AND IF
        SCR-CLUSTER@ IF L@ ELSE DROP 0xFFFD THEN EXIT
    THEN
    CELL-CP@ DUP 0= IF DROP 32 THEN ;

: _SCBA-EMIT-TEXT  ( cell -- )
    DUP _SCBA-FIRST UP-PROPS _SCBA-SEG GR-BREAK? 0= IF
        _SCBA-EMIT-ROW @ 1+ _SCBA-EMIT-COL @ 1+ ANSI-AT
        _SCBA-SEG GR-RESET
        DUP _SCBA-FIRST UP-PROPS _SCBA-SEG GR-BREAK? DROP
    THEN
    DUP CELL-CP-CLUSTER AND IF
        SCR-CLUSTER@ DUP 0= IF 2DROP 0xFFFD _SCR-EMIT-SCALAR EXIT THEN
        OVER L@ _SCR-EMIT-SCALAR
        1 ?DO
            DUP I 4 * + L@ DUP UP-PROPS _SCBA-SEG GR-BREAK? DROP
            _SCR-EMIT-SCALAR
        LOOP DROP EXIT
    THEN
    _SCBA-FIRST _SCR-EMIT-SCALAR ;

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

: _SCBA-BEGIN
  ( mode cols rows span-count cell-count words peak context -- status )
    DROP 2DROP 2DROP 2DROP _SCBA-MODE !
    _SCBA-MODE @ SCB-M-NONE = IF SCB-S-OK EXIT THEN
    ANSI-CURSOR-OFF
    _SCBA-SEG GR-RESET
    -1 _SCR-LAST-ROW !
    -1 _SCR-LAST-COL !
    -1 _SCR-LAST-FG !
    -1 _SCR-LAST-BG !
     0 _SCR-LAST-ATTRS !
    SCB-S-OK ;

\ A continuation cell emits nothing: the terminal draws its lead's wide
\ character across both cells.  Any cursor move or style change emits an
\ escape sequence and so ends the terminal's open character.
: _SCBA-SPAN  ( cells count row col words context -- status )
    2DROP _SCBA-COL ! _SCBA-ROW ! _SCBA-N ! _SCBA-A !
    _SCBA-N @ 0 ?DO
        _SCBA-A @ I 8 * + @
        DUP CELL-ATTRS@ CELL-A-CONT AND IF
            DROP
        ELSE
            _SCBA-ROW @ DUP _SCBA-EMIT-ROW !
            _SCBA-COL @ I + DUP _SCBA-EMIT-COL !
            2DUP _SCR-LAST-COL @ = SWAP _SCR-LAST-ROW @ = AND 0= IF
                _SCBA-SEG GR-RESET
            THEN
            _SCR-MOVE-TO
            DUP CELL-ATTRS@ 127 AND _SCR-LAST-ATTRS @ <>
            OVER CELL-FG@ _SCR-LAST-FG @ <> OR
            OVER CELL-BG@ _SCR-LAST-BG @ <> OR IF
                _SCBA-SEG GR-RESET
            THEN
            DUP _SCR-EMIT-ATTRS
            DUP _SCBA-EMIT-TEXT
            CELL-ATTRS@ CELL-A-WIDE AND IF 2 ELSE 1 THEN _SCR-LAST-COL +!
        THEN
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
VARIABLE _SCR-WORD-COUNT      \ cluster-tail words of the transaction
VARIABLE _SCR-SPAN-PEAK       \ largest span body in 32-bit words
VARIABLE _SCR-RUN-CELLS
VARIABLE _SCR-RUN-WORDS
VARIABLE _SCR-FLUSH-DEGRADE   \ cluster cells go as U+FFFD
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
    _SCR-WORD-COUNT @ _SCR-PLAN-WORDS !
    _SCR-SPAN-PEAK @ _SCR-PLAN-PEAK !
    _SCR-FLUSH-DEGRADE @ _SCR-PLAN-DEGRADE !
    -1 _SCR-PLAN-VALID ! ;

: _SCR-PLAN-LOAD?  ( -- flag )
    _SCR-PLAN-VALID @ 0= IF 0 EXIT THEN
    _SCR-PLAN-SCREEN @ _SCR-CUR @ <> IF
        _SCR-PLAN-INVALIDATE 0 EXIT
    THEN
    _SCR-PLAN-MODE @ _SCR-FLUSH-MODE !
    _SCR-PLAN-SPANS @ _SCR-SPAN-COUNT !
    _SCR-PLAN-CELLS @ _SCR-CELL-COUNT !
    _SCR-PLAN-WORDS @ _SCR-WORD-COUNT !
    _SCR-PLAN-PEAK @ _SCR-SPAN-PEAK !
    _SCR-PLAN-DEGRADE @ _SCR-FLUSH-DEGRADE !
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

\ Cluster-tail words of N back cells from A; none when degraded.
: _SCR-CELLS-WORDS  ( a n -- words )
    _SCR-FLUSH-DEGRADE @ IF 2DROP 0 EXIT THEN
    0 SWAP 8 * ROT DUP ROT + SWAP ?DO
        I @ DUP CELL-CP-CLUSTER AND IF
            SCR-CLUSTER-WORDS +
        ELSE DROP THEN
    8 +LOOP ;

: _SCR-SPAN-DONE  ( cells words -- )
    DUP _SCR-WORD-COUNT +!
    SWAP 2* + _SCR-SPAN-PEAK @ MAX _SCR-SPAN-PEAK ! ;

: _SCR-COUNT-DELTA-ROW  ( -- )
    0 _SCR-SCAN-COL !
    BEGIN _SCR-SCAN-COL @ _SCR-SCAN-W @ < WHILE
        _SCR-SCAN-CELL-DIFF? IF
            1 _SCR-SPAN-COUNT +!
            _SCR-SCAN-COL @ _SCR-SCAN-START !
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
            _SCR-SCAN-COL @ _SCR-SCAN-START @ -
            _SCR-SCAN-BACK @ _SCR-SCAN-START @ 8 * + OVER _SCR-CELLS-WORDS
            _SCR-SPAN-DONE
        ELSE
            1 _SCR-SCAN-COL +!
        THEN
    REPEAT ;

: _SCR-COUNT-CHANGES  ( -- )
    0 _SCR-SPAN-COUNT !
    0 _SCR-CELL-COUNT !
    0 _SCR-WORD-COUNT !
    0 _SCR-SPAN-PEAK !
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
            _SCR-SCAN-W @
            _SCR-SCAN-BACK @ _SCR-SCAN-W @ _SCR-CELLS-WORDS _SCR-SPAN-DONE
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
    _SCR-WORD-COUNT @ _SCR-SPAN-PEAK @
    _SCR-FLUSH-BACKEND @ SCB.CONTEXT @
    _SCR-FLUSH-BACKEND @ SCB.BEGIN-XT @ EXECUTE ;

: _SCR-CALL-SPAN  ( cells count row col -- status )
    3 PICK 3 PICK _SCR-CELLS-WORDS
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
    _SCR-RESIDUE-ADVANCE-FRONT
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
    0 _SCR-CUR @ _SCR-O-RESIDUE-DIRTY + !
    _SCR-CUR @ _SCR-O-RESIDUE-DAMAGE + @
    _SCR-CUR @ _SCR-O-H + @ 0 FILL
    _SCR-PLAN-INVALIDATE
    _SCR-CL-COLLECT ;

\ SCR-FLUSH? ( -- status )
\   Attempt one transaction.  A refusal never advances front.  In particular,
\   SESSION-LOST leaves the current backend bound: only the stream owner knows
\   whether a synchronized close has made ANSI emission safe again.
: SCR-FLUSH?  ( -- status )
    _SCR-CUR @ 0= IF SCB-S-INVALID EXIT THEN
    SCR-BACKEND@ DUP SCB-VALID? 0= IF DROP SCB-S-INVALID EXIT THEN
    _SCR-FLUSH-BACKEND !
    _SCR-PLAN-LOAD? 0= IF 0 _SCR-FLUSH-DEGRADE ! _SCR-COUNT-CHANGES THEN
    _SCR-CALL-BEGIN
    DUP SCB-S-TOO-LARGE = IF
        \ APT-1-WIRE Section 11.1: send it again with every cluster cell
        \ degraded.  Without tails the transaction always fits.
        DROP _SCR-FLUSH-DEGRADE @ IF SCB-S-INVALID _SCR-FAIL EXIT THEN
        -1 _SCR-FLUSH-DEGRADE ! _SCR-COUNT-CHANGES _SCR-CALL-BEGIN
        DUP SCB-S-TOO-LARGE = IF DROP SCB-S-INVALID THEN
    THEN
    DUP SCB-S-OK <> IF _SCR-FAIL EXIT THEN DROP
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
VARIABLE _SCR-OLD-OCCLUSION
VARIABLE _SCR-OLD-RESIDUE
VARIABLE _SCR-OLD-RESIDUE-DAMAGE
VARIABLE _SCR-OLD-RESIDUE-FRONT
VARIABLE _SCR-NEW-FRONT
VARIABLE _SCR-NEW-BACK
VARIABLE _SCR-NEW-DAMAGE
VARIABLE _SCR-NEW-TOUCHED
VARIABLE _SCR-NEW-OCCLUSION
VARIABLE _SCR-NEW-RESIDUE
VARIABLE _SCR-NEW-RESIDUE-DAMAGE
VARIABLE _SCR-NEW-RESIDUE-FRONT
VARIABLE _SCR-COPY-W
VARIABLE _SCR-COPY-H

: _SCR-EDGE-REPAIR  ( cell-a -- )
    DUP @ DUP _SCR-C-WIDE AND IF _SCR-HALF-BLANK SWAP ! ELSE 2DROP THEN ;

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
    _SCR-CUR @ _SCR-O-OCCLUSION + @ _SCR-OLD-OCCLUSION !
    _SCR-CUR @ _SCR-O-RESIDUE + @ _SCR-OLD-RESIDUE !
    _SCR-CUR @ _SCR-O-RESIDUE-DAMAGE + @ _SCR-OLD-RESIDUE-DAMAGE !
    _SCR-CUR @ _SCR-O-RESIDUE-FRONT + @ _SCR-OLD-RESIDUE-FRONT !

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

    _SCR-BUF-BYTES @ 8 / ALLOCATE DUP IF
        2DROP
        _SCR-NEW-TOUCHED @ FREE
        _SCR-NEW-DAMAGE @ FREE
        _SCR-NEW-BACK @ FREE
        _SCR-NEW-FRONT @ FREE
        -1 ABORT" SCR-RESIZE: occlusion buf alloc failed"
    THEN
    DROP _SCR-NEW-OCCLUSION !

    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP
        _SCR-NEW-OCCLUSION @ FREE
        _SCR-NEW-TOUCHED @ FREE
        _SCR-NEW-DAMAGE @ FREE
        _SCR-NEW-BACK @ FREE
        _SCR-NEW-FRONT @ FREE
        -1 ABORT" SCR-RESIZE: residue buf alloc failed"
    THEN
    DROP _SCR-NEW-RESIDUE !

    _SCR-TMP2 @ ALLOCATE DUP IF
        2DROP
        _SCR-NEW-RESIDUE @ FREE
        _SCR-NEW-OCCLUSION @ FREE
        _SCR-NEW-TOUCHED @ FREE
        _SCR-NEW-DAMAGE @ FREE
        _SCR-NEW-BACK @ FREE
        _SCR-NEW-FRONT @ FREE
        -1 ABORT" SCR-RESIZE: residue damage alloc failed"
    THEN
    DROP _SCR-NEW-RESIDUE-DAMAGE !

    _SCR-BUF-BYTES @ ALLOCATE DUP IF
        2DROP
        _SCR-NEW-RESIDUE-DAMAGE @ FREE
        _SCR-NEW-RESIDUE @ FREE
        _SCR-NEW-OCCLUSION @ FREE
        _SCR-NEW-TOUCHED @ FREE
        _SCR-NEW-DAMAGE @ FREE
        _SCR-NEW-BACK @ FREE
        _SCR-NEW-FRONT @ FREE
        -1 ABORT" SCR-RESIZE: residue front alloc failed"
    THEN
    DROP _SCR-NEW-RESIDUE-FRONT !

    \ Fill new buffers with CELL-BLANK
    _SCR-NEW-FRONT @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-NEW-BACK @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-NEW-RESIDUE @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-NEW-RESIDUE-FRONT @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-NEW-DAMAGE @ _SCR-TMP2 @ 0 FILL
    _SCR-NEW-TOUCHED @ _SCR-TMP2 @ -1 FILL
    _SCR-NEW-RESIDUE-DAMAGE @ _SCR-TMP2 @ -1 FILL
    _SCR-NEW-OCCLUSION @ _SCR-TMP @ _SCR-TMP2 @ * 0 FILL

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
        \ Preserve final-writer provenance for the same copied cells.  A
        \ later full redraw may replace it, but resize itself never invents
        \ ordinary ownership for still-visible overlay pixels.
        _SCR-OLD-OCCLUSION @ I _SCR-OLD-W @ * +
        _SCR-NEW-OCCLUSION @ I _SCR-TMP @ * +
        _SCR-COPY-W @ CMOVE
        _SCR-OLD-RESIDUE @ I _SCR-OLD-W @ * 8 * +
        _SCR-NEW-RESIDUE @ I _SCR-TMP @ * 8 * +
        _SCR-COPY-W @ 8 * CMOVE
        \ A narrower screen can cut a wide pair at its new right edge.
        _SCR-TMP @ _SCR-OLD-W @ < IF
            _SCR-NEW-BACK @ I 1+ _SCR-TMP @ * 1- 8 * + _SCR-EDGE-REPAIR
            _SCR-NEW-RESIDUE @ I 1+ _SCR-TMP @ * 1- 8 * + _SCR-EDGE-REPAIR
        THEN
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
    _SCR-NEW-OCCLUSION @ _SCR-CUR @ _SCR-O-OCCLUSION + !
    _SCR-NEW-RESIDUE @ _SCR-CUR @ _SCR-O-RESIDUE + !
    _SCR-NEW-RESIDUE-DAMAGE @ _SCR-CUR @ _SCR-O-RESIDUE-DAMAGE + !
    _SCR-NEW-RESIDUE-FRONT @ _SCR-CUR @ _SCR-O-RESIDUE-FRONT + !
    -1 _SCR-CUR @ _SCR-O-RESIDUE-DIRTY + !
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
    _SCR-OLD-TOUCHED @ FREE
    _SCR-OLD-OCCLUSION @ FREE
    _SCR-OLD-RESIDUE @ FREE
    _SCR-OLD-RESIDUE-DAMAGE @ FREE
    _SCR-OLD-RESIDUE-FRONT @ FREE ;

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
' _SCR-WITH-OCCLUSION CONSTANT _scr-with-occlusion-xt
' _SCR-WITH-REPLACEMENT CONSTANT _scr-with-replacement-xt
' _SCR-WITH-DRAW-AUTHORITY CONSTANT _scr-with-draw-authority-xt
' SCR-OCCLUSION-RECT? CONSTANT _scr-occlusion-rect-query-xt
' SCR-WITH-BACK-PLANE CONSTANT _scr-with-back-plane-xt
' SCR-WITH-PROJECTION-PLANES CONSTANT _scr-with-projection-planes-xt
' SCR-WITH-PROJECTION-FRAME-PLANES CONSTANT _scr-with-projection-frame-planes-xt
' SCR-PROJECTION-DIRTY? CONSTANT _scr-projection-dirty-xt
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
' SCR-CLUSTER         CONSTANT _scr-cluster-xt
' SCR-CLUSTER@        CONSTANT _scr-cluster-get-xt
' SCR-CLUSTER-WORDS   CONSTANT _scr-cluster-words-xt

: SCR-NEW             _scr-new-xt    _scr-guard WITH-GUARD ;
: SCR-FREE            _scr-free-xt   _scr-guard WITH-GUARD ;
: SCR-USE             _scr-use-xt    _scr-guard WITH-GUARD ;
: SCR-W               _scr-w-xt      _scr-guard WITH-GUARD ;
: SCR-H               _scr-h-xt      _scr-guard WITH-GUARD ;
: SCR-DRAW-COMPLETE   _scr-draw-complete-xt _scr-guard WITH-GUARD ;
: SCR-DRAW-GENERATION@
    _scr-draw-generation-get-xt _scr-guard WITH-GUARD ;
: _SCR-WITH-OCCLUSION
    _scr-with-occlusion-xt _scr-guard WITH-GUARD ;
: _SCR-WITH-REPLACEMENT
    _scr-with-replacement-xt _scr-guard WITH-GUARD ;
: _SCR-WITH-DRAW-AUTHORITY
    _scr-with-draw-authority-xt _scr-guard WITH-GUARD ;
: SCR-OCCLUSION-RECT?
    _scr-occlusion-rect-query-xt _scr-guard WITH-GUARD ;
: SCR-WITH-BACK-PLANE
    _scr-with-back-plane-xt _scr-guard WITH-GUARD ;
: SCR-WITH-PROJECTION-PLANES
    _scr-with-projection-planes-xt _scr-guard WITH-GUARD ;
: SCR-WITH-PROJECTION-FRAME-PLANES
    _scr-with-projection-frame-planes-xt _scr-guard WITH-GUARD ;
: SCR-PROJECTION-DIRTY?
    _scr-projection-dirty-xt _scr-guard WITH-GUARD ;
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
: SCR-CLUSTER         _scr-cluster-xt _scr-guard WITH-GUARD ;
: SCR-CLUSTER@        _scr-cluster-get-xt _scr-guard WITH-GUARD ;
: SCR-CLUSTER-WORDS   _scr-cluster-words-xt _scr-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _SCR-OWNED-END
_SCR-OWNED-END _SCR-OWNED-LIMIT !
