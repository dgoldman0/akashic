\ fp-convert.f — Conversions between FP32/FP16 and Q16.16 fixed-point
\
\ Bridge module connecting the IEEE 754 floating-point world (fp32.f,
\ fp16-ext.f) with the integer fixed-point world (fixed.f).
\ Designed for audio filter coefficient setup: compute biquad
\ coefficients in FP32 for precision, convert to Q16.16 for a fast
\ integer inner loop.
\
\ Prefix: FPC- (public API)
\
\ Load with:  REQUIRE fp-convert.f
\
\ === Public API ===
\   FP32>FX   ( fp32 -- fx )   FP32 → Q16.16 (bit-exact, no FP mul)
\   FP16>FX   ( fp16 -- fx )   FP16 → Q16.16 (via FP32)
\   FX>FP32   ( fx -- fp32 )   Q16.16 → FP32
\   FX>FP16   ( fx -- fp16 )   Q16.16 → FP16 (via FP32)
\
\ Range:
\   Q16.16 represents values in [-32768.0, +32767.99998] with
\   resolution 1/65536 ≈ 0.0000153.  Biquad coefficients (typically
\   in [-2, +2]) fit comfortably with 16 fractional bits of
\   precision — far exceeding FP16's 10-bit mantissa.
\
\ Performance:
\   These conversions run at pole-setup time (once per pole), not in
\   the inner loop.  They are NOT speed-critical.

REQUIRE fp32.f
REQUIRE fp16-ext.f
REQUIRE fixed.f

PROVIDED akashic-fp-convert

\ =====================================================================
\  FP32>FX — IEEE 754 binary32 → Q16.16 fixed-point
\ =====================================================================
\  Direct bit manipulation — no FP arithmetic needed.
\
\  FP32 value = (-1)^s × (1 + frac/2^23) × 2^(exp-127)
\             = (-1)^s × mantissa24 × 2^(exp-150)
\  where mantissa24 = frac | 0x800000  (24 bits with implicit 1).
\
\  Q16.16 = value × 65536 = (-1)^s × mantissa24 × 2^(exp-134)
\  since 65536 = 2^16, and 150 - 16 = 134.
\
\  If (exp-134) >= 0: shift mantissa LEFT by (exp-134).
\  If (exp-134) <  0: shift mantissa RIGHT by (134-exp).

VARIABLE _FPC-S
VARIABLE _FPC-E
VARIABLE _FPC-M
VARIABLE _FPC-SH

: FP32>FX  ( fp32 -- fx )
    _FP32-MASK AND

    \ Zero → 0
    DUP _FP32-ZERO? IF DROP 0 EXIT THEN

    \ NaN → 0
    DUP _FP32-NAN? IF DROP 0 EXIT THEN

    \ Inf → clamp to max/min Q16.16
    DUP _FP32-INF? IF
        _FP32-SIGN IF -2147483648 ELSE 2147483647 THEN EXIT
    THEN

    \ Extract fields
    DUP _FP32-SIGN _FPC-S !
    DUP _FP32-EXP  _FPC-E !
    _FP32-FRAC 0x800000 OR _FPC-M !

    \ Shift amount = exp - 134
    _FPC-E @ 134 - _FPC-SH !

    \ Underflow: value < 1/65536 (half a Q16.16 ULP)
    _FPC-SH @ -24 < IF
        0 EXIT
    THEN

    \ Overflow: value > 32767.9999
    _FPC-SH @ 15 > IF
        _FPC-S @ IF -2147483648 ELSE 2147483647 THEN EXIT
    THEN

    \ Apply shift
    _FPC-SH @ 0 >= IF
        _FPC-M @ _FPC-SH @ LSHIFT
    ELSE
        _FPC-M @ _FPC-SH @ NEGATE RSHIFT
    THEN

    \ Apply sign
    _FPC-S @ IF NEGATE THEN ;

\ =====================================================================
\  FP16>FX — FP16 → Q16.16 (via FP32 intermediate)
\ =====================================================================

: FP16>FX  ( fp16 -- fx )
    FP16>FP32 FP32>FX ;

\ =====================================================================
\  FX>FP32 — Q16.16 → FP32
\ =====================================================================
\  Strategy: convert the raw integer to FP32 via INT>FP32, then
\  divide by 65536.0 in FP32.  This is called at setup time only
\  so the ~200-step cost of FP32-DIV is acceptable.
\
\  Alternative: direct bit manipulation (find MSB, build exponent
\  = MSB + 127 - 16, extract 23-bit mantissa).  More code, same
\  precision, only saves ~100 steps.  Not worth it for setup-only use.

\ FP32 constant: 65536.0 = sign=0 exp=143 frac=0 → 0x47800000
0x47800000 CONSTANT _FPC-65536

: FX>FP32  ( fx -- fp32 )
    DUP 0= IF DROP FP32-ZERO EXIT THEN
    INT>FP32 _FPC-65536 FP32-DIV ;

\ =====================================================================
\  FX>FP16 — Q16.16 → FP16 (via FP32)
\ =====================================================================
\  Lossy: FP16 has 10-bit mantissa.  Only for output conversion
\  (writing PCM samples).

: FX>FP16  ( fx -- fp16 )
    FX>FP32 FP32>FP16 ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _fpcvt-guard

' FP32>FX         CONSTANT _fp32-to-fx-xt
' FP16>FX         CONSTANT _fp16-to-fx-xt
' FX>FP32         CONSTANT _fx-to-fp32-xt
' FX>FP16         CONSTANT _fx-to-fp16-xt

: FP32>FX         _fp32-to-fx-xt _fpcvt-guard WITH-GUARD ;
: FP16>FX         _fp16-to-fx-xt _fpcvt-guard WITH-GUARD ;
: FX>FP32         _fx-to-fp32-xt _fpcvt-guard WITH-GUARD ;
: FX>FP16         _fx-to-fp16-xt _fpcvt-guard WITH-GUARD ;
[THEN] [THEN]
