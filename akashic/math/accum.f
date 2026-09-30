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
\ A 48.16 value is the fixed-point cell of fixed.f, so the conversions
\ are fp32.f's FP32>FX, which truncates toward zero, and FX>FP32, which
\ rounds.
\
\ Prefix: ACCUM-  (public API)
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
\  ACCUM-ADD-FP32 — add an FP32 value to the accumulator
\ =====================================================================

: ACCUM-ADD-FP32  ( ctx fp32 -- )
    FP32>FX                            ( ctx fx48 )
    OVER @ +                           ( ctx new-sum )
    SWAP ! ;

\ =====================================================================
\  ACCUM-SUB-FP32 — subtract an FP32 value from the accumulator
\ =====================================================================

: ACCUM-SUB-FP32  ( ctx fp32 -- )
    FP32>FX                            ( ctx fx48 )
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
    @ FX>FP32 ;

: ACCUM-GET-FP16  ( ctx -- fp16 )
    ACCUM-GET-FP32 FP32>FP16 ;

: ACCUM-GET-INT  ( ctx -- n )
    @ 16 RSHIFT ;                      \ drop 16 fractional bits

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _accum-guard

' ACCUM-INIT      CONSTANT _accum-init-xt
' ACCUM-RESET     CONSTANT _accum-reset-xt
' ACCUM-ADD-FP32  CONSTANT _accum-add-fp32-xt
' ACCUM-SUB-FP32  CONSTANT _accum-sub-fp32-xt
' ACCUM-ADD-TILE  CONSTANT _accum-add-tile-xt
' ACCUM-ADD-TILE1 CONSTANT _accum-add-tile1-xt
' ACCUM-GET-RAW   CONSTANT _accum-get-raw-xt
' ACCUM-GET-FP32  CONSTANT _accum-get-fp32-xt
' ACCUM-GET-FP16  CONSTANT _accum-get-fp16-xt
' ACCUM-GET-INT   CONSTANT _accum-get-int-xt

: ACCUM-INIT      _accum-init-xt _accum-guard WITH-GUARD ;
: ACCUM-RESET     _accum-reset-xt _accum-guard WITH-GUARD ;
: ACCUM-ADD-FP32  _accum-add-fp32-xt _accum-guard WITH-GUARD ;
: ACCUM-SUB-FP32  _accum-sub-fp32-xt _accum-guard WITH-GUARD ;
: ACCUM-ADD-TILE  _accum-add-tile-xt _accum-guard WITH-GUARD ;
: ACCUM-ADD-TILE1 _accum-add-tile1-xt _accum-guard WITH-GUARD ;
: ACCUM-GET-RAW   _accum-get-raw-xt _accum-guard WITH-GUARD ;
: ACCUM-GET-FP32  _accum-get-fp32-xt _accum-guard WITH-GUARD ;
: ACCUM-GET-FP16  _accum-get-fp16-xt _accum-guard WITH-GUARD ;
: ACCUM-GET-INT   _accum-get-int-xt _accum-guard WITH-GUARD ;
[THEN] [THEN]
