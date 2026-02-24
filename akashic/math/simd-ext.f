\ simd-ext.f — Batch SIMD operations for N-element FP16 arrays
\
\ Extends simd.f by handling arrays longer than 32 elements.
\ Each *-N word automatically chunks the input into 32-element
\ tiles, processes full tiles via the tile engine, and handles
\ the remainder (partial tile) with zero-padded scratch buffers.
\
\ This is the bridge between the raw tile hardware (32 lanes)
\ and arbitrary-length data sets used by statistics, signal
\ processing, and batch computation.
\
\ All source/destination addresses must be in HBW or XMEM.
\ FP16 values are packed: 2 bytes each, array of n elements
\ at consecutive addresses.
\
\ Prefix: SIMD-   (public API, shared with simd.f)
\         _SIMX-  (internal helpers)
\
\ Load with:   REQUIRE simd-ext.f
\   (auto-loads simd.f, accum.f via REQUIRE)
\
\ === Public API ===
\   SIMD-ADD-N       ( src0 src1 dst n -- )    add n FP16 pairs
\   SIMD-SUB-N       ( src0 src1 dst n -- )    subtract n pairs
\   SIMD-MUL-N       ( src0 src1 dst n -- )    multiply n pairs
\   SIMD-SCALE-N     ( src scalar dst n -- )    scale n elements
\   SIMD-DOT-N       ( src0 src1 n -- acc )     dot product of n pairs
\   SIMD-SUM-N       ( src n -- sum )           sum of n elements
\   SIMD-SUMSQ-N     ( src n -- sumsq )         sum of squares of n
\   SIMD-MIN-N       ( src n -- min )           min of n elements
\   SIMD-MAX-N       ( src n -- max )           max of n elements
\   SIMD-SAXPY-N     ( a x y dst n -- )         y[i] = a*x[i] + y[i]
\   SIMD-NORM-N      ( src n -- norm )          L2 norm of n elements
\   SIMD-NORMALIZE-N ( src dst n -- )           normalize to unit length
\   SIMD-ABS-N       ( src dst n -- )           absolute value of n elements
\   SIMD-NEG-N       ( src dst n -- )           negate n elements
\   SIMD-CLAMP-N     ( src lo hi dst n -- )     clamp n elements
\   SIMD-FILL-N      ( dst val n -- )           broadcast fill n elements
\   SIMD-ZERO-N      ( dst n -- )               zero n elements
\   SIMD-COPY-N      ( src dst n -- )           copy n FP16 values
\
\ Internal zero-padded remainder handling ensures correct results
\ even when n is not a multiple of 32.

REQUIRE simd.f
REQUIRE accum.f

PROVIDED akashic-simd-ext

\ =====================================================================
\  Internal state variables
\ =====================================================================

VARIABLE _SIMX-SRC0                    \ current source 0 pointer
VARIABLE _SIMX-SRC1                    \ current source 1 pointer
VARIABLE _SIMX-DST                     \ current destination pointer
VARIABLE _SIMX-REM                     \ remaining element count
VARIABLE _SIMX-CHUNK                   \ current chunk size (≤32)

\ Scratch tiles for partial-tile remainder handling
VARIABLE _SIMX-PA                      \ partial tile A (src0 remainder)
VARIABLE _SIMX-PB                      \ partial tile B (src1 remainder)
VARIABLE _SIMX-PD                      \ partial tile D (dst remainder)

: _SIMX-INIT-TILES  ( -- )
    64 HBW-ALLOT _SIMX-PA !
    64 HBW-ALLOT _SIMX-PB !
    64 HBW-ALLOT _SIMX-PD ! ;

_SIMX-INIT-TILES

\ =====================================================================
\  Internal: load a partial tile (< 32 elements) zero-padded
\ =====================================================================
\  Copies 'count' FP16 values from src to tile, zeros the rest.

: _SIMX-LOAD-PARTIAL  ( src tile count -- )
    >R                                 ( src tile ) ( R: count )
    DUP 64 0 FILL                      \ zero entire tile first
    R> 0 DO                            ( src tile )
        OVER I 2 * + W@               ( src tile val )
        OVER I 2 * + W!               ( src tile )
    LOOP
    2DROP ;

\ =====================================================================
\  Internal: store partial tile back (only 'count' elements)
\ =====================================================================

: _SIMX-STORE-PARTIAL  ( tile dst count -- )
    0 DO                               ( tile dst )
        OVER I 2 * + W@               ( tile dst val )
        OVER I 2 * + W!               ( tile dst )
    LOOP
    2DROP ;

\ =====================================================================
\  Binary N-element operations: SIMD-ADD-N, SIMD-SUB-N, SIMD-MUL-N
\ =====================================================================
\  Common pattern: process full 32-element tiles, then handle tail.
\  Takes a tile-op xt (execution token) so we can share the loop.

: SIMD-ADD-N  ( src0 src1 dst n -- )
    DUP 0= IF 2DROP 2DROP EXIT THEN
    _SIMX-REM !  _SIMX-DST !
    _SIMX-SRC1 !  _SIMX-SRC0 !
    \ Process full 32-element tiles
    BEGIN _SIMX-REM @ 32 >= WHILE
        _SIMX-SRC0 @ _SIMX-SRC1 @ _SIMX-DST @ SIMD-ADD
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-SRC1 @ 64 + _SIMX-SRC1 !
        _SIMX-DST  @ 64 + _SIMX-DST !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    \ Handle remainder
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-SRC1 @ _SIMX-PB @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-PA @ _SIMX-PB @ _SIMX-PD @ SIMD-ADD
        _SIMX-PD @ _SIMX-DST @ _SIMX-REM @ _SIMX-STORE-PARTIAL
    THEN ;

: SIMD-SUB-N  ( src0 src1 dst n -- )
    DUP 0= IF 2DROP 2DROP EXIT THEN
    _SIMX-REM !  _SIMX-DST !
    _SIMX-SRC1 !  _SIMX-SRC0 !
    BEGIN _SIMX-REM @ 32 >= WHILE
        _SIMX-SRC0 @ _SIMX-SRC1 @ _SIMX-DST @ SIMD-SUB
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-SRC1 @ 64 + _SIMX-SRC1 !
        _SIMX-DST  @ 64 + _SIMX-DST !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-SRC1 @ _SIMX-PB @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-PA @ _SIMX-PB @ _SIMX-PD @ SIMD-SUB
        _SIMX-PD @ _SIMX-DST @ _SIMX-REM @ _SIMX-STORE-PARTIAL
    THEN ;

: SIMD-MUL-N  ( src0 src1 dst n -- )
    DUP 0= IF 2DROP 2DROP EXIT THEN
    _SIMX-REM !  _SIMX-DST !
    _SIMX-SRC1 !  _SIMX-SRC0 !
    BEGIN _SIMX-REM @ 32 >= WHILE
        _SIMX-SRC0 @ _SIMX-SRC1 @ _SIMX-DST @ SIMD-MUL
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-SRC1 @ 64 + _SIMX-SRC1 !
        _SIMX-DST  @ 64 + _SIMX-DST !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-SRC1 @ _SIMX-PB @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-PA @ _SIMX-PB @ _SIMX-PD @ SIMD-MUL
        _SIMX-PD @ _SIMX-DST @ _SIMX-REM @ _SIMX-STORE-PARTIAL
    THEN ;

\ =====================================================================
\  SIMD-SCALE-N — broadcast scalar × n elements
\ =====================================================================

VARIABLE _SIMX-SCALAR

: SIMD-SCALE-N  ( src scalar dst n -- )
    DUP 0= IF 2DROP 2DROP EXIT THEN
    _SIMX-REM !  _SIMX-DST !
    _SIMX-SCALAR !  _SIMX-SRC0 !
    \ Fill scratch tile PB with scalar broadcast (reuse for all tiles)
    _SIMX-PB @ _SIMX-SCALAR @ SIMD-FILL
    \ Process full tiles
    BEGIN _SIMX-REM @ 32 >= WHILE
        _SIMX-SRC0 @ _SIMX-PB @ _SIMX-DST @ SIMD-MUL
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-DST  @ 64 + _SIMX-DST !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    \ Handle remainder
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-PA @ _SIMX-PB @ _SIMX-PD @ SIMD-MUL
        _SIMX-PD @ _SIMX-DST @ _SIMX-REM @ _SIMX-STORE-PARTIAL
    THEN ;

\ =====================================================================
\  Reduction N-element operations
\ =====================================================================
\  These accumulate results across tiles via accum.f for
\  numerically stable cross-tile summation.

\ Accumulator context for N-element reductions
CREATE _SIMX-ACC 16 ALLOT

: SIMD-DOT-N  ( src0 src1 n -- acc )
    DUP 0= IF 2DROP DROP 0 EXIT THEN
    _SIMX-REM !  _SIMX-SRC1 !  _SIMX-SRC0 !
    _SIMX-ACC ACCUM-INIT
    \ Process full tiles
    BEGIN _SIMX-REM @ 32 >= WHILE
        FP16-MODE
        _SIMX-SRC0 @ TSRC0!
        _SIMX-SRC1 @ TSRC1!
        _SIMX-PA @ TDST!              \ scratch dst
        TDOT
        _SIMX-ACC ACCUM-ADD-TILE
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-SRC1 @ 64 + _SIMX-SRC1 !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    \ Handle remainder
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-SRC1 @ _SIMX-PB @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        FP16-MODE
        _SIMX-PA @ TSRC0!
        _SIMX-PB @ TSRC1!
        _SIMX-PD @ TDST!
        TDOT
        _SIMX-ACC ACCUM-ADD-TILE
    THEN
    _SIMX-ACC ACCUM-GET-FP32 ;

: SIMD-SUM-N  ( src n -- sum )
    DUP 0= IF 2DROP 0 EXIT THEN
    _SIMX-REM !  _SIMX-SRC0 !
    _SIMX-ACC ACCUM-INIT
    BEGIN _SIMX-REM @ 32 >= WHILE
        FP16-MODE
        _SIMX-SRC0 @ TSRC0!
        _SIMX-PA @ TDST!
        TSUM
        _SIMX-ACC ACCUM-ADD-TILE
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        FP16-MODE
        _SIMX-PA @ TSRC0!
        _SIMX-PD @ TDST!
        TSUM
        _SIMX-ACC ACCUM-ADD-TILE
    THEN
    _SIMX-ACC ACCUM-GET-FP32 ;

: SIMD-SUMSQ-N  ( src n -- sumsq )
    DUP 0= IF 2DROP 0 EXIT THEN
    _SIMX-REM !  _SIMX-SRC0 !
    _SIMX-ACC ACCUM-INIT
    BEGIN _SIMX-REM @ 32 >= WHILE
        FP16-MODE
        _SIMX-SRC0 @ TSRC0!
        _SIMX-PA @ TDST!
        TSUMSQ
        _SIMX-ACC ACCUM-ADD-TILE
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        FP16-MODE
        _SIMX-PA @ TSRC0!
        _SIMX-PD @ TDST!
        TSUMSQ
        _SIMX-ACC ACCUM-ADD-TILE
    THEN
    _SIMX-ACC ACCUM-GET-FP32 ;

\ =====================================================================
\  SIMD-MIN-N / SIMD-MAX-N — min/max of n elements
\ =====================================================================
\  These use TRMIN/TRMAX per tile, then compare across tiles
\  using scalar FP16 operations (since there are at most n/32 tiles).

VARIABLE _SIMX-RUNNING

: SIMD-MIN-N  ( src n -- min )
    DUP 0= IF 2DROP FP16-POS-INF EXIT THEN
    _SIMX-REM !  _SIMX-SRC0 !
    FP16-POS-INF _SIMX-RUNNING !       \ start with +inf
    BEGIN _SIMX-REM @ 32 >= WHILE
        _SIMX-SRC0 @ SIMD-RMIN         ( tile-min as FP32 accum )
        \ Convert FP32 acc result to FP16 for comparison
        FP32>FP16                       ( tile-min-fp16 )
        _SIMX-RUNNING @ FP16-MIN
        _SIMX-RUNNING !
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        \ Set unused lanes to +inf so they don't affect min
        _SIMX-REM @ 32 < IF
            _SIMX-REM @ DUP 32 SWAP - 0 DO
                FP16-POS-INF _SIMX-PA @ OVER 2 * + W!
                1+
            LOOP
            DROP
        THEN
        _SIMX-PA @ SIMD-RMIN
        FP32>FP16
        _SIMX-RUNNING @ FP16-MIN
        _SIMX-RUNNING !
    THEN
    _SIMX-RUNNING @ ;

: SIMD-MAX-N  ( src n -- max )
    DUP 0= IF 2DROP FP16-NEG-INF EXIT THEN
    _SIMX-REM !  _SIMX-SRC0 !
    FP16-NEG-INF _SIMX-RUNNING !       \ start with -inf
    BEGIN _SIMX-REM @ 32 >= WHILE
        _SIMX-SRC0 @ SIMD-RMAX
        FP32>FP16
        _SIMX-RUNNING @ FP16-MAX
        _SIMX-RUNNING !
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        \ Set unused lanes to -inf so they don't affect max
        _SIMX-REM @ 32 < IF
            _SIMX-REM @ DUP 32 SWAP - 0 DO
                FP16-NEG-INF _SIMX-PA @ OVER 2 * + W!
                1+
            LOOP
            DROP
        THEN
        _SIMX-PA @ SIMD-RMAX
        FP32>FP16
        _SIMX-RUNNING @ FP16-MAX
        _SIMX-RUNNING !
    THEN
    _SIMX-RUNNING @ ;

\ =====================================================================
\  SIMD-SAXPY-N — BLAS-1: dst[i] = a * x[i] + y[i]
\ =====================================================================
\  Three-step per tile: fill scale tile with a, TMUL(x, scale),
\  TADD(product, y) → dst.

VARIABLE _SIMX-X-PTR
VARIABLE _SIMX-Y-PTR

: SIMD-SAXPY-N  ( a x y dst n -- )
    DUP 0= IF 2DROP 2DROP DROP EXIT THEN
    _SIMX-REM !  _SIMX-DST !
    _SIMX-Y-PTR !  _SIMX-X-PTR !
    \ a is the scalar on stack
    \ Fill scratch PB with broadcast of 'a'
    _SIMX-PB @ SWAP SIMD-FILL         ( )
    \ Process full tiles
    BEGIN _SIMX-REM @ 32 >= WHILE
        \ Step 1: PA = a * x  (TMUL x-tile with broadcast-a tile)
        _SIMX-X-PTR @ _SIMX-PB @ _SIMX-PA @ SIMD-MUL
        \ Step 2: dst = PA + y  (TADD product with y-tile)
        _SIMX-PA @ _SIMX-Y-PTR @ _SIMX-DST @ SIMD-ADD
        _SIMX-X-PTR @ 64 + _SIMX-X-PTR !
        _SIMX-Y-PTR @ 64 + _SIMX-Y-PTR !
        _SIMX-DST  @ 64 + _SIMX-DST !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    \ Handle remainder
    _SIMX-REM @ 0> IF
        _SIMX-X-PTR @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-Y-PTR @ _SIMX-PD @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        \ PA = a * x-partial
        _SIMX-PA @ _SIMX-PB @ _SIMX-PA @ SIMD-MUL
        \ scratch-S0 = PA + y-partial
        _SIMX-PA @ _SIMX-PD @ _SIMX-PD @ SIMD-ADD
        _SIMX-PD @ _SIMX-DST @ _SIMX-REM @ _SIMX-STORE-PARTIAL
    THEN ;

\ =====================================================================
\  SIMD-NORM-N — L2 norm: sqrt(sum of squares)
\ =====================================================================

: SIMD-NORM-N  ( src n -- norm )
    SIMD-SUMSQ-N                       ( sumsq-fp32 )
    FP32-SQRT ;                        ( norm-fp32 )

\ =====================================================================
\  Memory N-element operations (defined early — used by NORMALIZE-N)
\ =====================================================================

: SIMD-FILL-N  ( dst val n -- )
    DUP 0= IF 2DROP DROP EXIT THEN
    0 DO                               ( dst val )
        OVER I 2 * + OVER SWAP W!
    LOOP
    2DROP ;

: SIMD-ZERO-N  ( dst n -- )
    2 * 0 FILL ;                       \ n elements × 2 bytes each

: SIMD-COPY-N  ( src dst n -- )
    DUP 0= IF 2DROP DROP EXIT THEN
    2 * 0 DO                           ( src dst )
        OVER I + C@                    ( src dst byte )
        OVER I + C!                    ( src dst )
    LOOP
    2DROP ;

\ =====================================================================
\  SIMD-NORMALIZE-N — normalize array to unit length
\ =====================================================================
\  Computes L2 norm, then scales each element by 1/norm.

: SIMD-NORMALIZE-N  ( src dst n -- )
    DUP 0= IF 2DROP DROP EXIT THEN
    _SIMX-REM !  _SIMX-DST !  _SIMX-SRC0 !
    \ Compute L2 norm
    _SIMX-SRC0 @ _SIMX-REM @ SIMD-SUMSQ-N   ( sumsq-fp32 )
    FP32-SQRT                          ( norm-fp32 )
    DUP FP32-ZERO = IF
        \ Zero-length vector — zero the destination
        DROP _SIMX-DST @ _SIMX-REM @ SIMD-ZERO-N
        EXIT
    THEN
    FP32-ONE SWAP FP32-DIV             ( inv-norm-fp32 )
    FP32>FP16                          ( inv-norm-fp16 )
    \ Scale src by 1/norm → dst
    _SIMX-SRC0 @ SWAP _SIMX-DST @ _SIMX-REM @
    SIMD-SCALE-N ;

\ =====================================================================
\  Convenience unary N-element operations
\ =====================================================================

: SIMD-ABS-N  ( src dst n -- )
    DUP 0= IF 2DROP DROP EXIT THEN
    0 DO                               ( src dst )
        OVER I 2 * + W@               ( src dst val )
        0x7FFF AND                     ( src dst |val| )
        OVER I 2 * + W!               ( src dst )
    LOOP
    2DROP ;

: SIMD-NEG-N  ( src dst n -- )
    DUP 0= IF 2DROP DROP EXIT THEN
    0 DO                               ( src dst )
        OVER I 2 * + W@               ( src dst val )
        0x8000 XOR 0xFFFF AND         ( src dst -val )
        OVER I 2 * + W!               ( src dst )
    LOOP
    2DROP ;

: SIMD-CLAMP-N  ( src lo hi dst n -- )
    DUP 0= IF 2DROP 2DROP DROP EXIT THEN
    _SIMX-REM !
    _SIMX-DST !
    \ Stack now: src lo hi
    >R >R                             ( src ) ( R: hi lo )
    _SIMX-SRC0 !                      \ src
    R> _SIMX-SRC1 !                   \ lo
    R> _SIMX-SCALAR !                 \ hi
    BEGIN _SIMX-REM @ 32 >= WHILE
        _SIMX-SRC0 @ _SIMX-SRC1 @ _SIMX-SCALAR @ _SIMX-DST @
        SIMD-CLAMP
        _SIMX-SRC0 @ 64 + _SIMX-SRC0 !
        _SIMX-DST  @ 64 + _SIMX-DST !
        _SIMX-REM  @ 32 - _SIMX-REM !
    REPEAT
    _SIMX-REM @ 0> IF
        _SIMX-SRC0 @ _SIMX-PA @ _SIMX-REM @ _SIMX-LOAD-PARTIAL
        _SIMX-PA @ _SIMX-SRC1 @ _SIMX-SCALAR @ _SIMX-PD @
        SIMD-CLAMP
        _SIMX-PD @ _SIMX-DST @ _SIMX-REM @ _SIMX-STORE-PARTIAL
    THEN ;
