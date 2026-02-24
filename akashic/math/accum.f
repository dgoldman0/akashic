\ accum.f — Extended-precision accumulators for tile-engine pipelines
\
\ The tile engine produces FP32 results from reductions (TSUM, TSUMSQ,
\ TDOT, etc.).  Those are exact within a single tile (32 elements).
\ But when processing thousands of elements across hundreds of tiles,
\ repeatedly adding FP32 values together loses bits as the running
\ sum grows.
\
\ This module provides 48.16 fixed-point accumulators — 64-bit
\ integers with 16 fractional bits — that accumulate tile results
\ with no intermediate rounding.  The 48-bit integer part can hold
\ sums up to ±140 trillion, far beyond what FP32 (7.2 digits) or
\ FP16 (3.3 digits) can represent exactly.
\
\ Typical pipeline:
\   1. Load 32 FP16 values into a tile
\   2. TSUM → FP32 result in ACC0
\   3. ACCUM-ADD-TILE → converts ACC0 to 48.16, adds to running sum
\   4. Repeat for all tiles
\   5. ACCUM-GET-FP32 → extract final sum as FP32
\
\ Prefix: ACCUM-  (public API)
\         _AC-    (internal helpers)
\
\ Load with:   REQUIRE accum.f
\   (auto-loads fp32.f via REQUIRE)
\
\ === Public API ===
\   ACCUM-CTX      ( -- addr )       default context (convenience)
\   ACCUM-INIT     ( ctx -- )        zero the context
\   ACCUM-ADD-FP32 ( ctx fp32 -- )   convert FP32→48.16, add
\   ACCUM-ADD-TILE ( ctx -- )        read ACC@ as FP32, add
\   ACCUM-ADD-TILE1( ctx -- )        read ACC1@ as FP32, add
\   ACCUM-SUB-FP32 ( ctx fp32 -- )   subtract FP32 from total
\   ACCUM-GET-FP32 ( ctx -- fp32 )   extract sum as FP32
\   ACCUM-GET-FP16 ( ctx -- fp16 )   extract sum as FP16
\   ACCUM-GET-INT  ( ctx -- n )      extract sum as integer (truncated)
\   ACCUM-GET-RAW  ( ctx -- raw )    raw 48.16 signed value
\   ACCUM-RESET    ( ctx -- )        same as INIT

REQUIRE fp32.f

PROVIDED akashic-accum

\ =====================================================================
\  Context layout: 2 cells = 16 bytes
\ =====================================================================
\  Offset +0: sum (signed 64-bit, 48.16 fixed-point)
\  Offset +8: (reserved / count — available for stats layer)
\
\  We use a single 64-bit cell for the accumulator.  Forth cells on
\  Megapad-64 are 64 bits, so 48.16 fits directly.

\ Default context (convenience for single-accumulator use cases)
CREATE ACCUM-CTX 16 ALLOT

\ =====================================================================
\  ACCUM-INIT / ACCUM-RESET — zero the context
\ =====================================================================

: ACCUM-INIT  ( ctx -- )
    DUP 0 SWAP !                       \ sum = 0
    8 + 0 SWAP ! ;                     \ reserved = 0

: ACCUM-RESET  ACCUM-INIT ;

\ =====================================================================
\  Internal: FP32 → 48.16 signed fixed-point
\ =====================================================================
\  Takes an IEEE 754 binary32 value and converts it to a signed
\  48.16 fixed-point integer.
\
\  Algorithm:
\    1. Extract sign, exponent, mantissa (24-bit with implicit 1)
\    2. Unbiased exponent = exp - 127
\    3. To get 48.16: shift mantissa by (unbiased_exp - 23 + 16)
\       = (unbiased_exp - 7)
\    4. Apply sign

VARIABLE _AC-SIGN
VARIABLE _AC-EXP
VARIABLE _AC-MANT

: _ACCUM-FP32>FX48  ( fp32 -- fx48.16 )
    0xFFFFFFFF AND
    DUP 0x7FFFFFFF AND 0= IF DROP 0 EXIT THEN   \ ±0 → 0
    DUP _FP32-SIGN _AC-SIGN !
    DUP _FP32-EXP  _AC-EXP !
    _FP32-FRAC 0x800000 OR _AC-MANT !
    _AC-EXP @ 127 - _AC-EXP !         \ unbias
    \ Shift amount: exp - 7
    _AC-EXP @ 7 - DUP 0 >= IF
        DUP 40 > IF                    \ prevent insane shifts
            DROP _AC-MANT @ 40 LSHIFT
        ELSE
            _AC-MANT @ SWAP LSHIFT
        THEN
    ELSE
        NEGATE DUP 63 > IF
            2DROP 0 EXIT               \ shifted to nothing
        THEN
        _AC-MANT @ SWAP RSHIFT
    THEN
    _AC-SIGN @ IF NEGATE THEN ;

\ =====================================================================
\  Internal: 48.16 signed → FP32
\ =====================================================================
\  Finds the MSB, computes exponent, extracts 23-bit mantissa.

VARIABLE _AC-F-SIGN
VARIABLE _AC-F-MAG
VARIABLE _AC-F-MSB

: _ACCUM-FX48>FP32  ( fx48.16 -- fp32 )
    DUP 0= IF DROP FP32-ZERO EXIT THEN
    DUP 0 < IF
        NEGATE 1 _AC-F-SIGN !
    ELSE
        0 _AC-F-SIGN !
    THEN
    _AC-F-MAG !
    \ Find MSB position (0-based)
    0 _AC-F-MSB !
    _AC-F-MAG @
    BEGIN DUP 1 > WHILE
        1 RSHIFT
        _AC-F-MSB @ 1+ _AC-F-MSB !
    REPEAT
    DROP
    \ FP32 exponent: the value is mag / 2^16
    \ So real value = mag * 2^(-16)
    \ If MSB is at position p, then mag ≈ 2^p, value ≈ 2^(p-16)
    \ FP32 biased exponent = (p - 16) + 127 = p + 111
    _AC-F-MSB @ 111 + DUP 255 >= IF
        DROP _AC-F-SIGN @ 31 LSHIFT 0x7F800000 OR 0xFFFFFFFF AND EXIT
    THEN
    DUP 0 <= IF
        DROP _AC-F-SIGN @ 31 LSHIFT 0xFFFFFFFF AND EXIT
    THEN
    ( biased-exp )
    \ Extract 23-bit mantissa
    _AC-F-MSB @ 23 > IF
        _AC-F-MAG @ _AC-F-MSB @ 23 - RSHIFT
    ELSE
        _AC-F-MAG @ 23 _AC-F-MSB @ - LSHIFT
    THEN
    0x7FFFFF AND
    _AC-F-SIGN @ ROT ROT _FP32-PACK ;

\ =====================================================================
\  ACCUM-ADD-FP32 — add an FP32 value to the accumulator
\ =====================================================================

: ACCUM-ADD-FP32  ( ctx fp32 -- )
    _ACCUM-FP32>FX48                   ( ctx fx48 )
    OVER @ +                           ( ctx new-sum )
    SWAP ! ;

\ =====================================================================
\  ACCUM-SUB-FP32 — subtract an FP32 value from the accumulator
\ =====================================================================

: ACCUM-SUB-FP32  ( ctx fp32 -- )
    _ACCUM-FP32>FX48                   ( ctx fx48 )
    NEGATE
    OVER @ +                           ( ctx new-sum )
    SWAP ! ;

\ =====================================================================
\  ACCUM-ADD-TILE / ACCUM-ADD-TILE1 — add tile accumulator result
\ =====================================================================
\  Reads ACC@ (CSR 0x19) or ACC1@ (CSR 0x1A) as FP32, converts
\  to 48.16, adds to running sum.

: ACCUM-ADD-TILE  ( ctx -- )
    ACC>FP32 ACCUM-ADD-FP32 ;

: ACCUM-ADD-TILE1  ( ctx -- )
    ACC1@ 0xFFFFFFFF AND               ( fp32 from ACC1 )
    SWAP OVER                          ( fp32 ctx fp32 )
    DROP                               ( fp32 ctx )
    SWAP ACCUM-ADD-FP32 ;

\ =====================================================================
\  ACCUM-GET-* — extract the accumulated value
\ =====================================================================

: ACCUM-GET-RAW  ( ctx -- raw )
    @ ;

: ACCUM-GET-FP32  ( ctx -- fp32 )
    @ _ACCUM-FX48>FP32 ;

: ACCUM-GET-FP16  ( ctx -- fp16 )
    ACCUM-GET-FP32 FP32>FP16 ;

: ACCUM-GET-INT  ( ctx -- n )
    @ 16 RSHIFT ;                      \ drop 16 fractional bits
