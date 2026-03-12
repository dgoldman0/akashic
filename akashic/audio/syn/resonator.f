\ syn/resonator.f — Resonant filter bank synthesis engine
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Pushes white or pink noise through a bank of digital bandpass
\ filters (resonators).  The filters color the noise continuously;
\ the result is a steady, sustained sound whose spectral character
\ is entirely determined by the filter center frequencies, Q values,
\ and amplitudes.
\
\ Sound character by parameter region:
\   Few wide-Q filters   → colored drone, wind-like
\   Many narrow-Q filters → pitched tone cluster, vowel-like
\   Pulsed excitation    → breath-driven instrument, flute-like
\   Amplitude-modulated  → resonant string, bow-like artifacts
\   Mixed colors + low Q → steam, bubbles, ambient texture
\
\ Each filter pole is a second-order IIR bandpass (direct-form II
\ transposed).  Biquad coefficients are computed in FP32 for
\ precision, then converted to Q16.16 fixed-point for a fast
\ integer inner loop (FX* = 3 primitives vs FP32-MUL ≈ 100).
\ Audio I/O (noise samples, PCM output) stays FP16.  Coefficients
\ are computed once at RESON-POLE! time; Q16.16 state (s1, s2)
\ persists across RESON-RENDER calls for phase continuity.
\
\ Output:
\   RESON-RENDER fills a caller-supplied PCM buffer.
\   Call repeatedly in a render loop for continuous output.
\
\ Prefix: RESON-   (public API)
\         _RS-     (internals)
\
\ Load with:   REQUIRE audio/syn/resonator.f

REQUIRE fp16-ext.f
REQUIRE fp32-trig.f
REQUIRE fixed.f
REQUIRE fp-convert.f
REQUIRE audio/noise.f
REQUIRE audio/pcm.f

PROVIDED akashic-syn-resonator

\ =====================================================================
\  Descriptor layout  (8 cells = 64 bytes base)
\ =====================================================================
\
\  +0   n-poles        Number of filter bands (integer, 1–16)
\  +8   noise-color    0=white 1=pink 2=brown (integer)
\  +16  excitation     0=continuous 1=pulsed (integer)
\  +24  intensity      Overall excitation level 0.0–1.0 (FP16)
\  +32  rate           Sample rate Hz (integer)
\  +40  poles-addr     Pointer to separately allocated pole block
\  +48  noise-eng      Pointer to persistent noise generator
\  +56  pulse-ctr      Frame counter for pulsed mode (integer)
\
\ Per-pole block: n × 56 bytes  (Q16.16 coefficients + state)
\  +0   center-hz      Filter center frequency (FP16, W@/W!)
\  +2   Q              Resonance/sharpness (FP16, W@/W!, safe up to ~80)
\  +4   amp            Pole amplitude 0.0–1.0 (FP16, W@/W!)
\  +6   (padding)      2 bytes
\  +8   b0n            Biquad coeff b0 normalized (Q16.16, @/!)
\  +16  neg-a1n        Biquad coeff -a1 normalized (Q16.16, @/!)
\  +24  neg-a2n        Biquad coeff -a2 normalized (Q16.16, @/!)
\  +32  s1             Biquad streaming state register 1 (Q16.16, @/!)
\  +40  s2             Biquad streaming state register 2 (Q16.16, @/!)
\  +48  amp-fx         Pole amplitude in Q16.16 (@/!)

64 CONSTANT RESON-DESC-SIZE
56 CONSTANT _RS-POLE-STRIDE

: RS.NPOLS   ( desc -- addr )  ;
: RS.NCOL    ( desc -- addr )  8 + ;
: RS.EXCITE  ( desc -- addr )  16 + ;
: RS.INTENS  ( desc -- addr )  24 + ;
: RS.RATE    ( desc -- addr )  32 + ;
: RS.POLES   ( desc -- addr )  40 + ;
: RS.NENG    ( desc -- addr )  48 + ;
: RS.PCTR    ( desc -- addr )  56 + ;

\ Per-pole field accessors ( pole-base -- addr )
: RP.FCO     ( p -- addr )  ;
: RP.Q       ( p -- addr )  2 + ;
: RP.AMP     ( p -- addr )  4 + ;
: RP.B0N     ( p -- addr )  8 + ;
: RP.NA1N    ( p -- addr )  16 + ;
: RP.NA2N    ( p -- addr )  24 + ;
: RP.S1      ( p -- addr )  32 + ;
: RP.S2      ( p -- addr )  40 + ;
: RP.AMPFX   ( p -- addr )  48 + ;

\ Base address of pole i  ( desc i -- pole-base )
: _RS-POLE   ( desc i -- pole-base )
    _RS-POLE-STRIDE * SWAP RS.POLES @ + ;

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _RS-TMP
VARIABLE _RS-RATE
VARIABLE _RS-I
VARIABLE _RS-X          \ current noise sample (Q16.16 in render loop)
VARIABLE _RS-ACC        \ accumulator per sample (Q16.16)
VARIABLE _RS-Y          \ biquad output (Q16.16)
VARIABLE _RS-NS1        \ new s1 (Q16.16)
VARIABLE _RS-NS2        \ new s2 (Q16.16)
VARIABLE _RS-PB         \ current pole base

\ =====================================================================
\  Internal: compute biquad coefficients for a bandpass at fc, Q
\ =====================================================================
\  Stores b0n, neg_a1n, neg_a2n into the pole struct.
\  Classic RBJ Audio EQ bandpass (constant peak gain):
\    α   = sin(ω) / (2Q)
\    b0  = sin(ω) / 2
\    b1  = 0
\    b2  = -sin(ω) / 2  = -b0
\    a0  = 1 + α
\    a1  = -2·cos(ω)
\    a2  = 1 - α
\  Normalized: b0n = b0/a0,  a1n = a1/a0,  a2n = a2/a0

VARIABLE _RS-CC-OMEGA
VARIABLE _RS-CC-SIN
VARIABLE _RS-CC-COS
VARIABLE _RS-CC-ALPHA
VARIABLE _RS-CC-B0
VARIABLE _RS-CC-A0
VARIABLE _RS-CC-A1
VARIABLE _RS-CC-A2

: _RS-BIQUAD-COEF  ( pole-base -- )
    _RS-PB !

    \ ω (radians) = 2π × fc / rate   — all FP32 for precision
    _RS-PB @ RP.FCO W@  FP16>FP32    \ fc as FP32
    _RS-RATE @ INT>FP32 FP32-DIV     \ fc/rate
    F32T-2PI FP32-MUL                \ ω in radians
    _RS-CC-OMEGA !

    \ sin(ω) and cos(ω) via FP32 trig
    _RS-CC-OMEGA @ F32T-SINCOS       \ ( sin cos )
    _RS-CC-COS !  _RS-CC-SIN !

    \ α = sin(ω) / (2Q)
    _RS-CC-SIN @
    _RS-PB @ RP.Q W@  FP16>FP32     \ Q as FP32
    FP32-TWO FP32-MUL FP32-DIV      \ sin/(2Q)
    _RS-CC-ALPHA !

    \ b0 = sin(ω) / 2
    _RS-CC-SIN @ FP32-HALF FP32-MUL  _RS-CC-B0 !

    \ a0 = 1 + α
    FP32-ONE _RS-CC-ALPHA @ FP32-ADD  _RS-CC-A0 !

    \ a1 = -2·cos(ω)
    FP32-ZERO FP32-TWO _RS-CC-COS @ FP32-MUL FP32-SUB
    _RS-CC-A1 !

    \ a2 = 1 - α
    FP32-ONE _RS-CC-ALPHA @ FP32-SUB  _RS-CC-A2 !

    \ Compute FP32 coefficients, convert to Q16.16 via FP32>FX, store
    \ b0n = b0 / a0
    _RS-CC-B0 @ _RS-CC-A0 @ FP32-DIV
    FP32>FX _RS-PB @ RP.B0N !

    \ neg_a1n = -(a1/a0)
    FP32-ZERO _RS-CC-A1 @ _RS-CC-A0 @ FP32-DIV FP32-SUB
    FP32>FX _RS-PB @ RP.NA1N !

    \ neg_a2n = -(a2/a0)
    FP32-ZERO _RS-CC-A2 @ _RS-CC-A0 @ FP32-DIV FP32-SUB
    FP32>FX _RS-PB @ RP.NA2N ! ;

\ =====================================================================
\  RESON-CREATE — Allocate resonator descriptor
\ =====================================================================
\  ( n-poles rate -- desc )
\  Poles initialized to silence; set with RESON-POLE!

VARIABLE _RS-CR-N
VARIABLE _RS-CR-R

: RESON-CREATE  ( n-poles rate -- desc )
    _RS-CR-R !  _RS-CR-N !

    RESON-DESC-SIZE ALLOCATE
    0<> ABORT" RESON-CREATE: desc alloc failed"
    _RS-TMP !

    _RS-CR-N @ _RS-TMP @ RS.NPOLS !
    0           _RS-TMP @ RS.NCOL  !
    0           _RS-TMP @ RS.EXCITE !
    FP16-POS-ONE _RS-TMP @ RS.INTENS !
    _RS-CR-R @ _RS-TMP @ RS.RATE  !
    0           _RS-TMP @ RS.PCTR  !
    _RS-CR-R @ _RS-RATE !

    \ Allocate pole block (n × 24 bytes), zero-filled
    _RS-CR-N @ _RS-POLE-STRIDE *
    ALLOCATE 0<> ABORT" RESON-CREATE: pole alloc failed"
    DUP _RS-TMP @ RS.POLES !
    _RS-CR-N @ _RS-POLE-STRIDE * 0 FILL

    \ Create default white noise generator
    NOISE-WHITE NOISE-CREATE
    _RS-TMP @ RS.NENG !

    _RS-TMP @ ;

\ =====================================================================
\  RESON-FREE
\ =====================================================================

: RESON-FREE  ( desc -- )
    DUP RS.NENG @ NOISE-FREE
    DUP RS.POLES @ FREE
    FREE ;

\ =====================================================================
\  RESON-POLE! — Set one filter pole
\ =====================================================================
\  ( center-hz Q amp i desc -- )
\  center-hz and Q are FP16.  amp is FP16 0.0–1.0.  i is 0-based integer.

VARIABLE _RS-PO-D

: RESON-POLE!  ( center-hz Q amp i desc -- )
    _RS-PO-D !
    _RS-PO-D @ RS.RATE @ _RS-RATE !

    \ Clamp index to [0, n-poles-1], then get pole base
    _RS-PO-D @ RS.NPOLS @ 1 - MIN 0 MAX   \ ( center Q amp clamped-i )
    _RS-PO-D @ SWAP _RS-POLE  _RS-PB !    \ ( center Q amp )

    \ Write params
    _RS-PB @ RP.AMP W!      \ ( center Q )
    _RS-PB @ RP.Q   W!      \ ( center )
    _RS-PB @ RP.FCO W!      \ ( )

    \ Convert amplitude to Q16.16 for inner loop
    _RS-PB @ RP.AMP W@ FP16>FX  _RS-PB @ RP.AMPFX !

    \ Clear streaming state (Q16.16 zeros)
    0 _RS-PB @ RP.S1 !
    0 _RS-PB @ RP.S2 !

    \ Compute biquad coefficients (FP32 then convert to Q16.16)
    _RS-PB @ _RS-BIQUAD-COEF ;

\ =====================================================================
\  RESON-NOISE! — Set noise color and intensity
\ =====================================================================
\  ( color intensity desc -- )
\  color: 0=white, 1=pink, 2=brown

VARIABLE _RS-NO-D

: RESON-NOISE!  ( color intensity desc -- )
    _RS-NO-D !
    _RS-NO-D @ RS.INTENS !
    \ If color changed, free old gen and create new
    DUP _RS-NO-D @ RS.NCOL @ <> IF
        _RS-NO-D @ RS.NENG @ NOISE-FREE
        DUP NOISE-CREATE _RS-NO-D @ RS.NENG !
        _RS-NO-D @ RS.NCOL !
    ELSE DROP THEN ;

\ =====================================================================
\  RESON-EXCITE! — Set excitation mode
\ =====================================================================
\  ( mode desc -- )   0=continuous, 1=pulsed

: RESON-EXCITE!  ( mode desc -- )  RS.EXCITE ! ;

\ =====================================================================
\  RESON-BLOW! — Live intensity modulation
\ =====================================================================

: RESON-BLOW!  ( intensity desc -- )  RS.INTENS ! ;

\ =====================================================================
\  Internal: pulsed excitation amplitude
\ =====================================================================
\  Returns FP16 0.0→1.0 modulation factor for pulsed mode.
\  Uses a simple 40 Hz pulse wave (low duty, high peak) to simulate
\  breath turbulence.  Counter in RS.PCTR.

VARIABLE _RS-PE-PERIOD
VARIABLE _RS-PE-CTR
VARIABLE _RS-PA-D

: _RS-PULSE-ENV  ( desc -- fp16 )
    _RS-PA-D !
    _RS-PA-D @ RS.RATE @  40 /  _RS-PE-PERIOD !

    _RS-PA-D @ RS.PCTR @
    DUP _RS-PE-PERIOD @ >= IF
        DROP 0
        0 _RS-PA-D @ RS.PCTR !
    THEN
    _RS-PA-D @ RS.PCTR @
    1 + _RS-PA-D @ RS.PCTR !   \ advance counter

    _RS-PE-PERIOD @ 4 / < IF FP16-POS-ONE
    ELSE 0x2E66 THEN ;

\ =====================================================================
\  RESON-RENDER — Fill PCM buffer with resonator output
\ =====================================================================
\  ( buf desc -- )
\  Generates noise, routes through all active (non-zero) filter poles,
\  sums contributions scaled by pole amp and overall intensity.

VARIABLE _RS-RN-D
VARIABLE _RS-RN-BUF
VARIABLE _RS-RN-N
VARIABLE _RS-RN-DPTR
VARIABLE _RS-RN-LEN
VARIABLE _RS-RN-INTENS
VARIABLE _RS-RN-PULSED
VARIABLE _RS-RN-PB
VARIABLE _RS-RN-PENV

: RESON-RENDER  ( buf desc -- )
    _RS-RN-D !  _RS-RN-BUF !

    _RS-RN-D @ RS.RATE  @ _RS-RATE !
    _RS-RN-D @ RS.NPOLS @ _RS-RN-N !
    _RS-RN-D @ RS.INTENS @ _RS-RN-INTENS !
    _RS-RN-D @ RS.EXCITE @ _RS-RN-PULSED !

    _RS-RN-BUF @ PCM-DATA _RS-RN-DPTR !
    _RS-RN-BUF @ PCM-LEN  _RS-RN-LEN  !

    _RS-RN-LEN @ 0 ?DO
        \ === Noise sample scaled by intensity (FP16) ===
        _RS-RN-D @ RS.NENG @ NOISE-SAMPLE
        _RS-RN-INTENS @ FP16-MUL

        \ If pulsed, modulate by breath envelope
        _RS-RN-PULSED @ 0<> IF
            _RS-RN-D @ _RS-PULSE-ENV FP16-MUL
        THEN

        \ Convert noise sample to Q16.16 for biquad processing
        FP16>FX _RS-X !

        \ === Sum through filter bank (Q16.16 accumulator) ===
        0 _RS-ACC !

        _RS-RN-N @ 0 ?DO
            _RS-RN-D @ I _RS-POLE  _RS-RN-PB !

            \ Skip silent poles (amp_fx = 0)
            _RS-RN-PB @ RP.AMPFX @ 0<> IF

                \ Precompute b0n * x (reused in y and ns1)
                _RS-RN-PB @ RP.B0N @  _RS-X @  FX*  _RS-TMP !

                \ y = b0n * x + s1   (all Q16.16)
                _RS-TMP @  _RS-RN-PB @ RP.S1 @  +  _RS-Y !

                \ ns1 = na1n * y + s2 - b0n * x
                _RS-RN-PB @ RP.NA1N @  _RS-Y @  FX*
                _RS-RN-PB @ RP.S2 @  +
                _RS-TMP @  -  _RS-NS1 !

                \ ns2 = na2n * y
                _RS-RN-PB @ RP.NA2N @  _RS-Y @  FX*  _RS-NS2 !

                \ Save state (Q16.16)
                _RS-NS1 @  _RS-RN-PB @ RP.S1 !
                _RS-NS2 @  _RS-RN-PB @ RP.S2 !

                \ Accumulate: y * amp_fx (Q16.16)
                _RS-Y @  _RS-RN-PB @ RP.AMPFX @  FX*
                _RS-ACC @  +  _RS-ACC !

            THEN
        LOOP

        \ Convert Q16.16 accumulator to FP16 for PCM sample
        _RS-ACC @ FX>FP16  _RS-RN-DPTR @ I 2* + W!

    LOOP ;

\ =====================================================================
\  Convenience: set all poles to equal-tempered harmonics
\ =====================================================================
\  RESON-HARM-FILL  ( fundamental-hz Q n-poles desc -- )
\  Fills poles 0..n-1 with harmonics f, 2f, 3f ... at equal amplitude.

VARIABLE _RS-HF-D
VARIABLE _RS-HF-N
VARIABLE _RS-HF-FUND
VARIABLE _RS-HF-Q
VARIABLE _RS-HF-AQ

: RESON-HARM-FILL  ( fund-hz Q n desc -- )
    _RS-HF-D !  _RS-HF-N !  _RS-HF-Q !  _RS-HF-FUND !

    \ amp = 1 / (n_poles^0.5) — equal loudness across bank
    \ Use 1/n as simple approximation (avoids sqrt)
    FP16-POS-ONE _RS-HF-N @ INT>FP16 FP16-DIV  _RS-HF-AQ !

    _RS-HF-N @ 0 ?DO
        I 1 + INT>FP16  _RS-HF-FUND @ FP16-MUL  ( (i+1)*fund )
        _RS-HF-Q @      ( center Q )
        _RS-HF-AQ @     ( center Q amp )
        I  _RS-HF-D @  RESON-POLE!
    LOOP ;

\ =====================================================================
\  Convenience: set formant-like poles (vowel / voice approximation)
\ =====================================================================
\  RESON-VOWEL-FILL  ( desc -- )
\  Loads 5 formant bands approximating an open vowel 'a'.

VARIABLE _RS-VF-D

: _RS-VOWEL-POLE  ( center-fp16 Q-fp16 amp-fp16 i desc -- )
    RESON-POLE! ;

: RESON-VOWEL-FILL  ( desc -- )
    _RS-VF-D !
    \ F0–F4 of open 'a' vowel in Hz (approximate), Q≈10, equal amp
    800  INT>FP16  10 INT>FP16  0x3599   0  _RS-VF-D @  RESON-POLE!
    1200 INT>FP16  8  INT>FP16  0x3599   1  _RS-VF-D @  RESON-POLE!
    2500 INT>FP16  12 INT>FP16  0x3400   2  _RS-VF-D @  RESON-POLE!
    3700 INT>FP16  10 INT>FP16  0x3200   3  _RS-VF-D @  RESON-POLE!
    5000 INT>FP16  6  INT>FP16  0x3000   4  _RS-VF-D @  RESON-POLE! ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _sreso-guard

' RS.NPOLS        CONSTANT _rs-dotnpols-xt
' RS.NCOL         CONSTANT _rs-dotncol-xt
' RS.EXCITE       CONSTANT _rs-dotexcite-xt
' RS.INTENS       CONSTANT _rs-dotintens-xt
' RS.RATE         CONSTANT _rs-dotrate-xt
' RS.POLES        CONSTANT _rs-dotpoles-xt
' RS.NENG         CONSTANT _rs-dotneng-xt
' RS.PCTR         CONSTANT _rs-dotpctr-xt
' RP.FCO          CONSTANT _rp-dotfco-xt
' RP.Q            CONSTANT _rp-dotq-xt
' RP.AMP          CONSTANT _rp-dotamp-xt
' RP.B0N          CONSTANT _rp-dotb0n-xt
' RP.NA1N         CONSTANT _rp-dotna1n-xt
' RP.NA2N         CONSTANT _rp-dotna2n-xt
' RP.S1           CONSTANT _rp-dots1-xt
' RP.S2           CONSTANT _rp-dots2-xt
' RP.AMPFX        CONSTANT _rp-dotampfx-xt
' RESON-CREATE    CONSTANT _reson-create-xt
' RESON-FREE      CONSTANT _reson-free-xt
' RESON-POLE!     CONSTANT _reson-pole-s-xt
' RESON-NOISE!    CONSTANT _reson-noise-s-xt
' RESON-EXCITE!   CONSTANT _reson-excite-s-xt
' RESON-BLOW!     CONSTANT _reson-blow-s-xt
' RESON-RENDER    CONSTANT _reson-render-xt
' RESON-HARM-FILL CONSTANT _reson-harm-fill-xt
' RESON-VOWEL-FILL CONSTANT _reson-vowel-fill-xt

: RS.NPOLS        _rs-dotnpols-xt _sreso-guard WITH-GUARD ;
: RS.NCOL         _rs-dotncol-xt _sreso-guard WITH-GUARD ;
: RS.EXCITE       _rs-dotexcite-xt _sreso-guard WITH-GUARD ;
: RS.INTENS       _rs-dotintens-xt _sreso-guard WITH-GUARD ;
: RS.RATE         _rs-dotrate-xt _sreso-guard WITH-GUARD ;
: RS.POLES        _rs-dotpoles-xt _sreso-guard WITH-GUARD ;
: RS.NENG         _rs-dotneng-xt _sreso-guard WITH-GUARD ;
: RS.PCTR         _rs-dotpctr-xt _sreso-guard WITH-GUARD ;
: RP.FCO          _rp-dotfco-xt _sreso-guard WITH-GUARD ;
: RP.Q            _rp-dotq-xt _sreso-guard WITH-GUARD ;
: RP.AMP          _rp-dotamp-xt _sreso-guard WITH-GUARD ;
: RP.B0N          _rp-dotb0n-xt _sreso-guard WITH-GUARD ;
: RP.NA1N         _rp-dotna1n-xt _sreso-guard WITH-GUARD ;
: RP.NA2N         _rp-dotna2n-xt _sreso-guard WITH-GUARD ;
: RP.S1           _rp-dots1-xt _sreso-guard WITH-GUARD ;
: RP.S2           _rp-dots2-xt _sreso-guard WITH-GUARD ;
: RP.AMPFX        _rp-dotampfx-xt _sreso-guard WITH-GUARD ;
: RESON-CREATE    _reson-create-xt _sreso-guard WITH-GUARD ;
: RESON-FREE      _reson-free-xt _sreso-guard WITH-GUARD ;
: RESON-POLE!     _reson-pole-s-xt _sreso-guard WITH-GUARD ;
: RESON-NOISE!    _reson-noise-s-xt _sreso-guard WITH-GUARD ;
: RESON-EXCITE!   _reson-excite-s-xt _sreso-guard WITH-GUARD ;
: RESON-BLOW!     _reson-blow-s-xt _sreso-guard WITH-GUARD ;
: RESON-RENDER    _reson-render-xt _sreso-guard WITH-GUARD ;
: RESON-HARM-FILL _reson-harm-fill-xt _sreso-guard WITH-GUARD ;
: RESON-VOWEL-FILL _reson-vowel-fill-xt _sreso-guard WITH-GUARD ;
[THEN] [THEN]
