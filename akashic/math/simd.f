\ simd.f — Multi-mode SIMD primitives via tile engine
\
\ The Megapad-64 tile engine is a 512-bit (64-byte) SIMD unit with
\ six element-width modes controlled by the TMODE CSR (0x14):
\
\   EW  Mode    Lanes   TMODE value
\   0   U8      64      0x00  (unsigned)  /  0x10 (signed)
\   1   U16     32      0x01  (unsigned)  /  0x11 (signed)
\   2   U32     16      0x02  (unsigned)  /  0x12 (signed)
\   3   U64      8      0x03  (unsigned)  /  0x13 (signed)
\   4   FP16    32      0x04
\   5   BF16    32      0x05
\
\ TMODE bits:
\   [2:0] EW        element width
\   [4]   signed    0=unsigned 1=signed
\   [5]   saturate  0=wrapping 1=saturating (add/sub)
\   [6]   rounding  0=truncate 1=round-to-nearest (shifts)
\
\ This module provides:
\   Part 1 — Mode-setting words (U8-MODE .. I64-MODE, FP16-MODE)
\   Part 2 — FP16 convenience API (SIMD- prefix, sets FP16-MODE)
\   Part 3 — Mode-agnostic tile ops (TILE- prefix, caller sets mode)
\
\ All operations work on 64-byte tile buffers allocated in HBW math
\ RAM.  Addresses must be 64-byte aligned HBW pointers.
\
\ Prefix: SIMD-   FP16 convenience API (sets FP16 mode)
\         TILE-   Mode-agnostic API (caller sets mode)
\         _SIMD-  Internal helpers
\
\ Load with:   REQUIRE simd.f
\   (auto-loads fp16.f via REQUIRE)
\
\ === FP16 Convenience API (SIMD- prefix) ===
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
\ === Mode-Agnostic API (TILE- prefix) ===
\   U8-MODE .. I64-MODE                    set element mode
\   TILE-ADD       ( src0 src1 dst -- )    elementwise add
\   TILE-SUB       ( src0 src1 dst -- )    elementwise subtract
\   TILE-MUL       ( src0 src1 dst -- )    elementwise multiply (truncating)
\   TILE-WMUL      ( src0 src1 dst -- )    widening multiply (2× output)
\   TILE-FMA       ( src0 src1 dst -- )    fused multiply-add
\   TILE-MAC       ( src0 src1 dst -- )    multiply-accumulate
\   TILE-AND       ( src0 src1 dst -- )    bitwise AND
\   TILE-OR        ( src0 src1 dst -- )    bitwise OR
\   TILE-XOR       ( src0 src1 dst -- )    bitwise XOR
\   TILE-MIN       ( src0 src1 dst -- )    elementwise min
\   TILE-MAX       ( src0 src1 dst -- )    elementwise max
\   TILE-ABS       ( src dst -- )          elementwise absolute value
\   TILE-SUM       ( src -- sum )          reduction: sum → ACC@
\   TILE-RMIN      ( src -- min )          reduction: min → ACC@
\   TILE-RMAX      ( src -- max )          reduction: max → ACC@
\   TILE-DOT       ( src0 src1 -- acc )    dot product → ACC@
\   TILE-ZERO      ( dst -- )             hardware tile zero (64 bytes)
\   TILE-COPY      ( src dst -- )          copy 64 bytes
\   TILE-FILL-U8   ( dst val -- )          fill 64 bytes with val
\   TILE-FILL-U16  ( dst val -- )          fill 32 words with val
\   TILE-FILL-U32  ( dst val -- )          fill 16 dwords with val
\   TILE-FILL-U64  ( dst val -- )          fill 8 qwords with val
\   TILE-TRANS     ( src dst -- )          8×8 byte transpose
\
\ Tile buffers are 64-byte aligned.  SIMD- operations set FP16-MODE
\ before use.  TILE- operations require caller to set mode first.
\ Not re-entrant (shared scratch tiles).

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

\ #################################################################
\  Part 3 — Mode-setting words and mode-agnostic tile operations
\ #################################################################
\
\ The TILE- prefix operations do NOT set tile mode.  Caller must
\ set the desired mode first (U8-MODE, U16-MODE, FP16-MODE, etc.)
\ and then call any TILE- word.  The same hardware instructions
\ (TADD, TSUB, TMUL…) operate on whatever element width is active.

\ =====================================================================
\  Mode convenience words
\ =====================================================================
\  Each sets TMODE CSR to the appropriate value.
\  TMODE bits: [2:0]=EW  [4]=signed  [5]=saturate  [6]=rounding

: U8-MODE    ( -- ) 0x00 TMODE! ;   \ 64 lanes, unsigned 8-bit
: I8-MODE    ( -- ) 0x10 TMODE! ;   \ 64 lanes, signed 8-bit
: U8S-MODE   ( -- ) 0x20 TMODE! ;   \ 64 lanes, unsigned 8-bit, saturating
: I8S-MODE   ( -- ) 0x30 TMODE! ;   \ 64 lanes, signed 8-bit, saturating
: U16-MODE   ( -- ) 0x01 TMODE! ;   \ 32 lanes, unsigned 16-bit
: I16-MODE   ( -- ) 0x11 TMODE! ;   \ 32 lanes, signed 16-bit
: U16S-MODE  ( -- ) 0x21 TMODE! ;   \ 32 lanes, unsigned 16-bit, saturating
: I16S-MODE  ( -- ) 0x31 TMODE! ;   \ 32 lanes, signed 16-bit, saturating
: U32-MODE   ( -- ) 0x02 TMODE! ;   \ 16 lanes, unsigned 32-bit
: I32-MODE   ( -- ) 0x12 TMODE! ;   \ 16 lanes, signed 32-bit
: U64-MODE   ( -- ) 0x03 TMODE! ;   \ 8 lanes, unsigned 64-bit
: I64-MODE   ( -- ) 0x13 TMODE! ;   \ 8 lanes, signed 64-bit

\ =====================================================================
\  Mode-agnostic pointer setup (no mode change)
\ =====================================================================

: _TILE-BIN  ( src0 src1 dst -- )
    TDST!  TSRC1!  TSRC0! ;

: _TILE-UNI  ( src dst -- )
    TDST!  TSRC0! ;

\ =====================================================================
\  Elementwise arithmetic  (TILE- prefix, mode-agnostic)
\ =====================================================================

: TILE-ADD   ( src0 src1 dst -- )  _TILE-BIN TADD ;
: TILE-SUB   ( src0 src1 dst -- )  _TILE-BIN TSUB ;
: TILE-MUL   ( src0 src1 dst -- )  _TILE-BIN TMUL ;
: TILE-WMUL  ( src0 src1 dst -- )  _TILE-BIN TWMUL ;
: TILE-FMA   ( src0 src1 dst -- )  _TILE-BIN TFMA ;
: TILE-MAC   ( src0 src1 dst -- )  _TILE-BIN TMAC ;
: TILE-MIN   ( src0 src1 dst -- )  _TILE-BIN TEMIN ;
: TILE-MAX   ( src0 src1 dst -- )  _TILE-BIN TEMAX ;

\ =====================================================================
\  Bitwise operations  (work in any mode, operate on raw bits)
\ =====================================================================

: TILE-AND   ( src0 src1 dst -- )  _TILE-BIN TAND ;
: TILE-OR    ( src0 src1 dst -- )  _TILE-BIN TOR ;
: TILE-XOR   ( src0 src1 dst -- )  _TILE-BIN TXOR ;

\ =====================================================================
\  Unary operations
\ =====================================================================

: TILE-ABS   ( src dst -- )  _TILE-UNI TABS ;

\ =====================================================================
\  Reductions  (result in ACC@, returned on stack)
\ =====================================================================
\  In FP modes: ACC holds FP32 bit pattern.
\  In integer modes: ACC holds integer value.

: TILE-SUM     ( src -- sum )
    TSRC0!  _SIMD-S0 @ TDST!  TSUM   ACC@ ;

: TILE-RMIN    ( src -- min )
    TSRC0!  _SIMD-S0 @ TDST!  TMIN   ACC@ ;

: TILE-RMAX    ( src -- max )
    TSRC0!  _SIMD-S0 @ TDST!  TMAX   ACC@ ;

: TILE-SUMSQ   ( src -- sumsq )
    TSRC0!  _SIMD-S0 @ TDST!  TSUMSQ ACC@ ;

: TILE-DOT     ( src0 src1 -- acc )
    TSRC1!  TSRC0!  _SIMD-S0 @ TDST!  TDOT ACC@ ;

: TILE-ARGMIN  ( src -- index )
    TSRC0!  _SIMD-S0 @ TDST!  TMINIDX ACC@ ;

: TILE-ARGMAX  ( src -- index )
    TSRC0!  _SIMD-S0 @ TDST!  TMAXIDX ACC@ ;

: TILE-L1NORM  ( src -- norm )
    TSRC0!  _SIMD-S0 @ TDST!  TL1 ACC@ ;

: TILE-POPCNT  ( src -- cnt )
    TSRC0!  _SIMD-S0 @ TDST!  TPOPCNT ACC@ ;

\ =====================================================================
\  Utility operations
\ =====================================================================

: TILE-ZERO   ( dst -- )
    64 0 FILL ;

: TILE-COPY   ( src dst -- )
    \ 64-byte copy, byte-by-byte (proven pattern from SIMD-COPY)
    64 0 DO
        OVER I + C@
        OVER I + C!
    LOOP
    2DROP ;

: TILE-TRANS  ( src dst -- )
    _TILE-UNI TTRANS ;

\ =====================================================================
\  Mode-aware fill helpers
\ =====================================================================
\  Fill all lanes of a tile with a single scalar value.
\  Use the variant matching your current mode's element width.

: TILE-FILL-U8   ( dst val -- )
    \ Fill 64 bytes with val (0-255)
    SWAP 64 ROT FILL ;

: TILE-FILL-U16  ( dst val -- )
    \ Fill 32 × 16-bit lanes with val (0-65535)
    32 0 DO
        OVER I 2 * +  OVER  SWAP W!
    LOOP
    2DROP ;

: TILE-FILL-U32  ( dst val -- )
    \ Fill 16 × 32-bit lanes with val
    16 0 DO
        OVER I 4 * +  OVER  SWAP L!
    LOOP
    2DROP ;

: TILE-FILL-U64  ( dst val -- )
    \ Fill 8 × 64-bit lanes with val
    8 0 DO
        OVER I 8 * +  OVER  SWAP !
    LOOP
    2DROP ;
