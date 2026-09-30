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
\   FP16>FX   ( fp16 -- fx )   FP16 → Q16.16 (via FP32)
\   FX>FP16   ( fx -- fp16 )   Q16.16 → FP16 (via FP32)
\
\ FP32>FX and FX>FP32 themselves come from fp32.f.  They convert
\ exactly or round once, and hold no state, so this module needs no
\ guard.
\
\ Range:
\   A fixed-point value is a signed cell with 16 fraction bits, so its
\   resolution is 1/65536 ≈ 0.0000153.  Biquad coefficients (typically
\   in [-2, +2]) keep 16 fractional bits of precision — far exceeding
\   FP16's 10-bit mantissa.  Conversions from FP32 saturate at the
\   cell's range.
\
\ Performance:
\   These conversions run at pole-setup time (once per pole), not in
\   the inner loop.  They are NOT speed-critical.

REQUIRE fp32.f
REQUIRE fp16-ext.f
REQUIRE fixed.f

PROVIDED akashic-fp-convert

\ =====================================================================
\  FP16>FX — FP16 → Q16.16 (via FP32 intermediate)
\ =====================================================================

: FP16>FX  ( fp16 -- fx )
    FP16>FP32 FP32>FX ;

\ =====================================================================
\  FX>FP16 — Q16.16 → FP16 (via FP32)
\ =====================================================================
\  Lossy: FP16 has 10-bit mantissa.  Only for output conversion
\  (writing PCM samples).

: FX>FP16  ( fx -- fp16 )
    FX>FP32 FP32>FP16 ;
