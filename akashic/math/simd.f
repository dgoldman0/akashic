\ simd.f — 32-lane FP16 SIMD primitives via tile engine
\
\ The Megapad-64 tile engine has 32 FP16 lanes working in parallel.
\ Existing math libraries (fp16.f, fp16-ext.f, vec2.f, etc.) use
\ only lane 0 for scalar operations — wasting 31 of 32 lanes.
\
\ This module exposes the full 32-lane width for data-parallel
\ workloads.  All operations work on 64-byte tile buffers (32 × FP16)
\ allocated in HBW math RAM.
\
\ Addresses passed to these words must be 64-byte aligned HBW
\ pointers.  Each tile buffer holds exactly 32 FP16 values (64 bytes).
\
\ Prefix: SIMD-   (public API)
\         _SIMD-  (internal helpers)
\
\ Load with:   REQUIRE simd.f
\   (auto-loads fp16.f via REQUIRE)
\
\ === Public API ===
\   SIMD-ADD       ( src0 src1 dst -- )     32-wide FP16 add
\   SIMD-SUB       ( src0 src1 dst -- )     32-wide FP16 subtract
\   SIMD-MUL       ( src0 src1 dst -- )     32-wide FP16 multiply
\   SIMD-FMA       ( src0 src1 dst -- )     32-wide FMA: dst += src0*src1
\   SIMD-MAC       ( src0 src1 dst -- )     32-wide multiply-accumulate
\   SIMD-MIN       ( src0 src1 dst -- )     32-wide elementwise min
\   SIMD-MAX       ( src0 src1 dst -- )     32-wide elementwise max
\   SIMD-ABS       ( src dst -- )           32-wide absolute value
\   SIMD-NEG       ( src dst -- )           32-wide negate
\   SIMD-SCALE     ( src scalar dst -- )    broadcast scalar × 32 elements
\   SIMD-DOT       ( src0 src1 -- acc )     32-pair dot product (FP32)
\   SIMD-SUM       ( src -- sum )           reduction: sum of 32 elements
\   SIMD-SUMSQ     ( src -- sumsq )         reduction: sum of squares
\   SIMD-RMIN      ( src -- min )           reduction: minimum
\   SIMD-RMAX      ( src -- max )           reduction: maximum
\   SIMD-ARGMIN    ( src -- index )         reduction: index of minimum
\   SIMD-ARGMAX    ( src -- index )         reduction: index of maximum
\   SIMD-L1NORM    ( src -- norm )          reduction: L1 norm
\   SIMD-POPCNT    ( src -- cnt )           reduction: population count
\   SIMD-CLAMP     ( src lo hi dst -- )     32-wide clamp to [lo,hi]
\   SIMD-FILL      ( dst val -- )           broadcast fill all 32 lanes
\   SIMD-ZERO      ( dst -- )              zero a tile (64 bytes)
\   SIMD-COPY      ( src dst -- )           copy 64 bytes
\   SIMD-LOAD2D    ( base stride rows dst -- )  strided 2D load
\   SIMD-STORE2D   ( src base stride rows -- )  strided 2D store
\   SIMD-ALLOT     ( -- addr )             allocate one 64-byte tile in HBW
\
\ Tile buffers are 64-byte aligned.  All operations set FP16-MODE
\ before use.  Not re-entrant (shared scratch tiles).

REQUIRE fp16.f

PROVIDED akashic-simd

\ =====================================================================
\  Internal scratch tiles
\ =====================================================================
\  We allocate dedicated scratch tiles for SIMD ops so they don't
\  conflict with fp16.f's scalar tiles.  Eight tiles as specified
\  in the memory budget (512 bytes HBW).

VARIABLE _SIMD-S0                      \ scratch tile 0
VARIABLE _SIMD-S1                      \ scratch tile 1
VARIABLE _SIMD-S2                      \ scratch tile 2
VARIABLE _SIMD-S3                      \ scratch tile 3
VARIABLE _SIMD-S4                      \ scratch tile 4
VARIABLE _SIMD-S5                      \ scratch tile 5
VARIABLE _SIMD-S6                      \ scratch tile 6
VARIABLE _SIMD-S7                      \ scratch tile 7

: _SIMD-INIT-TILES  ( -- )
    64 HBW-ALLOT _SIMD-S0 !
    64 HBW-ALLOT _SIMD-S1 !
    64 HBW-ALLOT _SIMD-S2 !
    64 HBW-ALLOT _SIMD-S3 !
    64 HBW-ALLOT _SIMD-S4 !
    64 HBW-ALLOT _SIMD-S5 !
    64 HBW-ALLOT _SIMD-S6 !
    64 HBW-ALLOT _SIMD-S7 !
    _SIMD-S0 @ 64 0 FILL
    _SIMD-S1 @ 64 0 FILL
    _SIMD-S2 @ 64 0 FILL
    _SIMD-S3 @ 64 0 FILL
    _SIMD-S4 @ 64 0 FILL
    _SIMD-S5 @ 64 0 FILL
    _SIMD-S6 @ 64 0 FILL
    _SIMD-S7 @ 64 0 FILL ;

_SIMD-INIT-TILES

\ =====================================================================
\  SIMD-ALLOT — allocate a new 64-byte HBW tile
\ =====================================================================

: SIMD-ALLOT  ( -- addr )
    64 HBW-ALLOT ;

\ =====================================================================
\  Internal: common tile setup patterns
\ =====================================================================
\  Binary op: set FP16 mode, point src0/src1/dst.
\  Unary op:  set FP16 mode, point src0/dst (src1 may be scratch).

: _SIMD-SETUP-BIN  ( src0 src1 dst -- )
    TDST!  TSRC1!  TSRC0!
    FP16-MODE ;

: _SIMD-SETUP-UNI  ( src dst -- )
    TDST!  TSRC0!
    FP16-MODE ;

\ =====================================================================
\  Binary arithmetic: elementwise on two 32-element tiles
\ =====================================================================

: SIMD-ADD  ( src0 src1 dst -- )
    _SIMD-SETUP-BIN TADD ;

: SIMD-SUB  ( src0 src1 dst -- )
    _SIMD-SETUP-BIN TSUB ;

: SIMD-MUL  ( src0 src1 dst -- )
    _SIMD-SETUP-BIN TMUL ;

: SIMD-FMA  ( src0 src1 dst -- )
    \ dst[i] += src0[i] * src1[i]
    _SIMD-SETUP-BIN TFMA ;

: SIMD-MAC  ( src0 src1 dst -- )
    \ Multiply-accumulate: acc += src0[i] * src1[i]
    _SIMD-SETUP-BIN TMAC ;

: SIMD-MIN  ( src0 src1 dst -- )
    _SIMD-SETUP-BIN TEMIN ;

: SIMD-MAX  ( src0 src1 dst -- )
    _SIMD-SETUP-BIN TEMAX ;

\ =====================================================================
\  Unary operations
\ =====================================================================
\  ABS: clear sign bit on all 32 lanes.
\  NEG: flip sign bit on all 32 lanes.
\
\  Strategy: build a mask tile in scratch, then use tile XOR/AND.
\  Alternative: iterate 32 lanes in software (simpler, still fast).

VARIABLE _SIMD-I

: SIMD-ABS  ( src dst -- )
    \ Clear bit 15 of each 16-bit lane
    OVER SWAP                          ( src src dst )
    SWAP DROP                          ( src dst )
    32 0 DO
        OVER I 2 * + W@               ( src dst val )
        0x7FFF AND                     ( src dst |val| )
        OVER I 2 * + W!               ( src dst )
    LOOP
    2DROP ;

: SIMD-NEG  ( src dst -- )
    \ Flip bit 15 of each 16-bit lane
    32 0 DO
        OVER I 2 * + W@               ( src dst val )
        0x8000 XOR 0xFFFF AND         ( src dst -val )
        OVER I 2 * + W!               ( src dst )
    LOOP
    2DROP ;

\ =====================================================================
\  SIMD-SCALE — broadcast scalar multiply
\ =====================================================================
\  Fill scratch tile with scalar, then TMUL.

: SIMD-SCALE  ( src scalar dst -- )
    >R                                 ( src scalar ) ( R: dst )
    \ Fill scratch tile S0 with the scalar value
    _SIMD-S0 @ SWAP                    ( src s0-addr scalar )
    32 0 DO
        OVER I 2 * + OVER SWAP W!     ( src s0-addr scalar )
    LOOP
    DROP                               ( src s0-addr )
    \ src0 = src, src1 = scratch (filled with scalar), dst = caller's dst
    SWAP                               ( s0-addr src )
    SWAP                               ( src s0-addr )
    R>                                 ( src s0-addr dst )
    _SIMD-SETUP-BIN TMUL ;

\ =====================================================================
\  Reductions: produce a single scalar from 32 elements
\ =====================================================================
\  The tile engine reduction instructions read from src0 and write
\  their results to the accumulator (ACC@).

: SIMD-SUM  ( src -- sum )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!                  \ dst needed by some engines
    TSUM
    ACC@ ;

: SIMD-SUMSQ  ( src -- sumsq )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!
    TSUMSQ
    ACC@ ;

: SIMD-DOT  ( src0 src1 -- acc )
    FP16-MODE
    TSRC1!  TSRC0!
    _SIMD-S0 @ TDST!
    TDOT
    ACC@ ;

: SIMD-RMIN  ( src -- min )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!
    TMIN
    ACC@ ;

: SIMD-RMAX  ( src -- max )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!
    TMAX
    ACC@ ;

: SIMD-ARGMIN  ( src -- index )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!
    TMINIDX
    ACC@ ;

: SIMD-ARGMAX  ( src -- index )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!
    TMAXIDX
    ACC@ ;

: SIMD-L1NORM  ( src -- norm )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!
    TL1
    ACC@ ;

: SIMD-POPCNT  ( src -- cnt )
    FP16-MODE
    TSRC0!
    _SIMD-S0 @ TDST!
    TPOPCNT
    ACC@ ;

\ =====================================================================
\  SIMD-CLAMP — clamp all 32 lanes to [lo, hi]
\ =====================================================================
\  Strategy: fill two scratch tiles with lo and hi broadcasts,
\  then TEMAX(src, lo) → S2, then TEMIN(S2, hi) → dst.

: SIMD-CLAMP  ( src lo hi dst -- )
    >R                                 ( src lo hi ) ( R: dst )
    \ Fill S0 with hi broadcast
    _SIMD-S0 @ SWAP                    ( src lo s0 hi )
    32 0 DO
        OVER I 2 * + OVER SWAP W!
    LOOP
    DROP DROP                          ( src lo )
    \ Fill S1 with lo broadcast
    _SIMD-S1 @ SWAP                    ( src s1 lo )
    32 0 DO
        OVER I 2 * + OVER SWAP W!
    LOOP
    DROP DROP                          ( src )
    \ TEMAX(src, lo) → S2  (clamp from below)
    FP16-MODE
    DUP TSRC0!                         ( src )
    _SIMD-S1 @ TSRC1!
    _SIMD-S2 @ TDST!
    TEMAX
    \ TEMIN(S2, hi) → dst  (clamp from above)
    _SIMD-S2 @ TSRC0!
    _SIMD-S0 @ TSRC1!
    R> TDST!
    TEMIN
    DROP ;                             ( )

\ =====================================================================
\  Memory operations: fill, zero, copy
\ =====================================================================

: SIMD-FILL  ( dst val -- )
    \ Fill all 32 lanes with the same FP16 value
    32 0 DO                            ( dst val )
        OVER I 2 * + OVER SWAP W!
    LOOP
    2DROP ;

: SIMD-ZERO  ( dst -- )
    64 0 FILL ;

: SIMD-COPY  ( src dst -- )
    \ Copy 64 bytes from src to dst
    64 0 DO                            ( src dst )
        OVER I + C@                    ( src dst byte )
        OVER I + C!                    ( src dst )
    LOOP
    2DROP ;

\ =====================================================================
\  Strided 2D access
\ =====================================================================
\  LOAD2D: load rows of data with a stride between rows into a tile.
\  Each row contributes some columns that pack sequentially into the
\  tile.  Uses TLOAD2D hardware instruction when available.
\
\  STORE2D: write tile data back to strided memory.

: SIMD-LOAD2D  ( base stride rows dst -- )
    \ Load strided 2D data into tile buffer
    \ base  = start address of 2D array
    \ stride = bytes between row starts
    \ rows = number of rows to load
    \ dst  = 64-byte tile buffer
    \ Each row loads (64/rows) bytes, packing into dst sequentially.
    >R                                 ( base stride rows ) ( R: dst )
    R@ SIMD-ZERO                       \ zero destination first
    0                                  ( base stride rows offset )
    SWAP 0 DO                          ( base stride offset )
        \ Copy one row segment to dst+offset
        2 PICK I 3 PICK * +           ( base stride offset row-addr )
        32 I / 2 MAX                   ( base stride offset row-addr cols )
        0 DO                           ( base stride offset row-addr )
            DUP I + C@                 ( base stride offset row-addr byte )
            R@ 4 PICK I + + C!        ( base stride offset row-addr )
        LOOP
        DROP                           ( base stride offset )
        32 I / 2 MAX +                 ( base stride offset' )
    LOOP
    DROP 2DROP
    R> DROP ;

: SIMD-STORE2D  ( src base stride rows -- )
    \ Store tile data back to strided memory locations
    \ src  = 64-byte tile buffer
    \ base  = start address of 2D array
    \ stride = bytes between row starts
    \ rows = number of rows to write
    0                                  ( src base stride rows offset )
    SWAP 0 DO                          ( src base stride offset )
        \ Copy from src+offset to row in 2D array
        2 PICK I 3 PICK * +           ( src base stride offset row-addr )
        32 I / 2 MAX                   ( src base stride offset row-addr cols )
        0 DO                           ( src base stride offset row-addr )
            4 PICK 3 PICK I + + C@    ( src base stride offset row-addr byte )
            OVER I + C!               ( src base stride offset row-addr )
        LOOP
        DROP                           ( src base stride offset )
        32 I / 2 MAX +                 ( src base stride offset' )
    LOOP
    DROP 2DROP DROP ;
