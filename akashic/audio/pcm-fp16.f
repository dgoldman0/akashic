\ pcm-fp16.f — Scalar conversion between Akashic FP16 audio and PCM16
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Akashic synthesis represents normalized samples as IEEE FP16 bit
\ patterns stored in 16-bit PCM slots.  Device and file boundaries usually
\ require signed integer PCM16.  This module is the canonical conversion
\ policy shared by those boundaries without making format-neutral pcm.f
\ depend on floating-point math or making a device driver depend on WAV.
\
\ Load with: REQUIRE audio/pcm-fp16.f
\
\ Public API:
\   PCM-FP16>S16  ( fp16 -- s16 )  normalized FP16 to signed PCM16
\   PCM-S16>FP16  ( s16 -- fp16 )  signed/raw PCM16 to normalized FP16

REQUIRE ../math/fp16-ext.f
REQUIRE ../math/fp32.f

PROVIDED akashic-audio-pcm-fp16

: _PCM-FP16-NAN?  ( fp16 -- flag )
    DUP 0x7C00 AND 0x7C00 =
    SWAP 0x03FF AND 0<> AND ;

\ PCM-FP16>S16 — Convert normalized FP16 to signed integer PCM16.
\ NaN maps to silence.  Infinities and finite values outside [-1, +1]
\ saturate.  +1 maps to +32767; -1 maps to -32768.
: PCM-FP16>S16  ( fp16 -- s16 )
    DUP _PCM-FP16-NAN? IF DROP 0 EXIT THEN
    DUP FP16-POS-ONE FP16-GE IF DROP 32767 EXIT THEN
    DUP FP16-NEG-ONE FP16-LE IF DROP -32768 EXIT THEN
    \ 32768 is exactly representable in FP16; 32767 truncates to 32752 and
    \ introduces avoidable landmark error (for example 0.5 -> 16376).
    \ Endpoint branches above preserve the asymmetric PCM16 rails.
    32768 INT>FP16 FP16-MUL FP16>INT
    \ KDOS MIN/MAX are unsigned; use explicit signed comparisons here.
    DUP -32768 < IF DROP -32768 THEN
    DUP  32767 > IF DROP  32767 THEN ;

\ PCM-S16>FP16 — Convert signed integer PCM16 to normalized FP16.
\ The input may be sign-extended or an unsigned 16-bit value from W@;
\ masking then sign-extending makes both representations unambiguous.
: PCM-S16>FP16  ( s16 -- fp16 )
    0xFFFF AND
    DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN
    \ FP32>FP16 currently flushes half subnormals and does not round the
    \ positive rail up to 1, so preserve those three PCM landmarks
    \ explicitly.  Every other magnitude produces a normal half value.
    DUP 32767 = IF DROP FP16-POS-ONE EXIT THEN
    DUP     1 = IF DROP 0x0200 EXIT THEN
    DUP    -1 = IF DROP 0x8200 EXIT THEN
    INT>FP32
    0x38000000 FP32-MUL       \ exact binary32 scale 2^-15
    FP32>FP16 ;
