\ audio/analysis/perceptual.f — Perceptual audio metrics for PCM buffers
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Human-ear-weighted metrics: these answer "how does this actually
\ sound to a person" rather than "what are the raw numbers."
\
\ Words:
\   PCM-A-WEIGHTED-RMS   ( buf -- rms-fp16 )
\   PCM-BRIGHTNESS       ( buf -- ratio-fp16 )
\   PCM-SPECTRAL-FLATNESS ( buf -- ratio-fp16 )
\
\ All words accept an FP16-valued mono PCM buffer.  Results are FP16.
\
\ Implementation: Uses FFT power spectrum from spectral.f approach,
\ applies A-weighting gains per bin, recomputes RMS from weighted
\ spectrum.
\
\ A-weighting curve approximation for 8 kHz system (32 Hz per bin):
\   The IEC 61672 A-weight curve is steep below 500 Hz, nearly flat
\   1-4 kHz.  We use a lookup table of gains for our 128 bins.
\
\ Prefix: PCM-    (public)
\         _PP-    (internals)
\
\ Load with:   REQUIRE audio/analysis/perceptual.f

REQUIRE fp16.f
REQUIRE fp16-ext.f
REQUIRE fp32.f
REQUIRE fft.f
REQUIRE audio/pcm.f

PROVIDED akashic-analysis-perceptual

\ =====================================================================
\  FFT parameters (must match spectral.f or stand alone)
\ =====================================================================

256 CONSTANT _PP-NFFT
128 CONSTANT _PP-NBINS

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _PP-BUF
VARIABLE _PP-DPTR
VARIABLE _PP-LEN
VARIABLE _PP-RATE

VARIABLE _PP-RE
VARIABLE _PP-IM
VARIABLE _PP-PWR

VARIABLE _PP-ALLOCATED
0 _PP-ALLOCATED !

: _PP-ALLOC  ( -- )
    _PP-ALLOCATED @ IF EXIT THEN
    _PP-NFFT 2* ALLOCATE DROP _PP-RE  !
    _PP-NFFT 2* ALLOCATE DROP _PP-IM  !
    _PP-NFFT 2* ALLOCATE DROP _PP-PWR !
    1 _PP-ALLOCATED ! ;

\ =====================================================================
\  Internal: setup — copy PCM to RE, zero IM, FFT, power spectrum
\ =====================================================================

: _PP-SETUP  ( buf -- )
    _PP-ALLOC
    DUP _PP-BUF !
    DUP PCM-DATA _PP-DPTR !
    DUP PCM-LEN  _PP-LEN !
    PCM-RATE _PP-RATE !

    _PP-LEN @ _PP-NFFT MIN
    DUP 0 ?DO
        _PP-DPTR @ I 2* + W@
        _PP-RE @ I 2* + W!
    LOOP

    DUP _PP-NFFT < IF
        DUP _PP-NFFT SWAP DO
            0 _PP-RE @ I 2* + W!
        LOOP
    THEN
    DROP

    _PP-NFFT 0 DO
        0 _PP-IM @ I 2* + W!
    LOOP

    _PP-RE @ _PP-IM @ _PP-NFFT FFT-FORWARD
    _PP-RE @ _PP-IM @ _PP-PWR @ _PP-NFFT FFT-POWER ;

\ =====================================================================
\  A-weighting lookup table
\ =====================================================================
\  For a 256-pt FFT at 8000 Hz, each bin = 31.25 Hz.
\  Bins 0..127 → frequencies 0..3968.75 Hz.
\
\  IEC 61672 A-weighting (dB) at key frequencies:
\    31 Hz: -39.4    63 Hz: -26.2   125 Hz: -16.1   250 Hz: -8.6
\   500 Hz: -3.2   1000 Hz:  0.0  2000 Hz: +1.2   4000 Hz: +1.0
\
\  We store linear gain factors (not dB) as FP16 bit patterns.
\  gain = 10^(dB/20).
\
\  For simplicity, we precompute 16 anchor points covering 8 bin
\  ranges each (0-7, 8-15, ..., 120-127) and apply the same gain
\  to all bins in each range.
\
\  Anchor gains (linear, rounded to FP16):
\    Range 0 (0-218 Hz):    ~-25 dB → gain ≈ 0.056 → 0x2B2F
\    Range 1 (250-468 Hz):  ~-8 dB  → gain ≈ 0.40  → 0x3666
\    Range 2 (500-718 Hz):  ~-3 dB  → gain ≈ 0.71  → 0x39AC
\    Range 3 (750-968 Hz):  ~-0.8dB → gain ≈ 0.91  → 0x3B47
\    Range 4 (1000-1218 Hz): 0 dB   → gain ≈ 1.00  → 0x3C00
\    Range 5 (1250-1468 Hz):+0.6 dB → gain ≈ 1.07  → 0x3C47
\    Range 6 (1500-1718 Hz):+1.0 dB → gain ≈ 1.12  → 0x3C7B
\    Range 7 (1750-1968 Hz):+1.2 dB → gain ≈ 1.15  → 0x3C9A
\    Range 8 (2000-2218 Hz):+1.2 dB → gain ≈ 1.15  → 0x3C9A
\    Range 9 (2250-2468 Hz):+1.1 dB → gain ≈ 1.13  → 0x3C87
\    Range 10(2500-2718 Hz):+1.0 dB → gain ≈ 1.12  → 0x3C7B
\    Range 11(2750-2968 Hz):+0.8 dB → gain ≈ 1.10  → 0x3C66
\    Range 12(3000-3218 Hz):+0.5 dB → gain ≈ 1.06  → 0x3C3D
\    Range 13(3250-3468 Hz):+0.1 dB → gain ≈ 1.01  → 0x3C08
\    Range 14(3500-3718 Hz):-0.3 dB → gain ≈ 0.97  → 0x3BE1
\    Range 15(3750-3968 Hz):-0.8 dB → gain ≈ 0.91  → 0x3B47

\ Table stored as 16 FP16 values (32 bytes)
VARIABLE _PP-AWT-ADDR
VARIABLE _PP-AWT-DONE
0 _PP-AWT-DONE !

: _PP-AWT-INIT  ( -- )
    _PP-AWT-DONE @ IF EXIT THEN
    32 ALLOCATE DROP _PP-AWT-ADDR !

    \ Store the 16 gain values
    0x2B2F _PP-AWT-ADDR @  0 + W!   \ range 0:  ~0.056
    0x3666 _PP-AWT-ADDR @  2 + W!   \ range 1:  ~0.40
    0x39AC _PP-AWT-ADDR @  4 + W!   \ range 2:  ~0.71
    0x3B47 _PP-AWT-ADDR @  6 + W!   \ range 3:  ~0.91
    0x3C00 _PP-AWT-ADDR @  8 + W!   \ range 4:  1.00
    0x3C47 _PP-AWT-ADDR @ 10 + W!   \ range 5:  ~1.07
    0x3C7B _PP-AWT-ADDR @ 12 + W!   \ range 6:  ~1.12
    0x3C9A _PP-AWT-ADDR @ 14 + W!   \ range 7:  ~1.15
    0x3C9A _PP-AWT-ADDR @ 16 + W!   \ range 8:  ~1.15
    0x3C87 _PP-AWT-ADDR @ 18 + W!   \ range 9:  ~1.13
    0x3C7B _PP-AWT-ADDR @ 20 + W!   \ range 10: ~1.12
    0x3C66 _PP-AWT-ADDR @ 22 + W!   \ range 11: ~1.10
    0x3C3D _PP-AWT-ADDR @ 24 + W!   \ range 12: ~1.06
    0x3C08 _PP-AWT-ADDR @ 26 + W!   \ range 13: ~1.01
    0x3BE1 _PP-AWT-ADDR @ 28 + W!   \ range 14: ~0.97
    0x3B47 _PP-AWT-ADDR @ 30 + W!   \ range 15: ~0.91

    1 _PP-AWT-DONE ! ;

\ Get A-weight gain for bin index
: _PP-AWT-GAIN  ( bin -- gain-fp16 )
    8 /                               \ bin → range index
    _PP-NBINS 8 / 1- MIN             \ clamp to [0, 15]
    0 MAX
    2* _PP-AWT-ADDR @ + W@ ;

\ =====================================================================
\  PCM-A-WEIGHTED-RMS — A-weighted loudness
\ =====================================================================
\  ( buf -- rms-fp16 )
\  Computes RMS from the A-weighted power spectrum:
\    sum( gain_k² × power_k ) / N_bins  →  sqrt → RMS
\
\  Sub-bass at 80 Hz that looks loud in raw RMS is actually ~-25 dB
\  perceptually.  This metric catches that.

VARIABLE _PP-AWRMS-SUM

: PCM-A-WEIGHTED-RMS  ( buf -- rms-fp16 )
    _PP-SETUP
    _PP-AWT-INIT

    FP32-ZERO _PP-AWRMS-SUM !

    _PP-NBINS 1 DO
        _PP-PWR @ I 2* + W@          \ power_k (FP16)
        I _PP-AWT-GAIN                 \ gain_k (FP16)
        DUP FP16-MUL                   \ gain_k²
        FP16-MUL                       \ weighted_power = gain² × power
        FP16>FP32
        _PP-AWRMS-SUM @ FP32-ADD _PP-AWRMS-SUM !
    LOOP

    \ RMS = sqrt( 2 × sum / NFFT² )  — Parseval normalization
    \ NFFT²/2 = 256²/2 = 32768
    _PP-AWRMS-SUM @
    _PP-NFFT DUP * 2/ INT>FP16 FP16>FP32
    FP32-DIV
    FP32-SQRT FP32>FP16 ;

\ =====================================================================
\  PCM-BRIGHTNESS — energy above 2 kHz / total energy
\ =====================================================================
\  ( buf -- ratio-fp16 )
\  Quick "is there any treble" check.
\  A snare should be 0.3+; a bass drone is <0.05.

VARIABLE _PP-BR-HI
VARIABLE _PP-BR-TOT

\ 2000 Hz → bin = 2000 * NFFT / rate = 2000 * 256 / 8000 = 64
64 CONSTANT _PP-BR-CUTOFF-BIN

: PCM-BRIGHTNESS  ( buf -- ratio-fp16 )
    _PP-SETUP

    FP32-ZERO _PP-BR-HI  !
    FP32-ZERO _PP-BR-TOT !

    _PP-NBINS 1 DO
        _PP-PWR @ I 2* + W@
        FP16>FP32
        DUP _PP-BR-TOT @ FP32-ADD _PP-BR-TOT !

        I _PP-BR-CUTOFF-BIN >= IF
            _PP-BR-HI @ FP32-ADD _PP-BR-HI !
        ELSE
            DROP
        THEN
    LOOP

    _PP-BR-TOT @ FP32-ZERO FP32> IF
        _PP-BR-HI @ _PP-BR-TOT @ FP32-DIV FP32>FP16
    ELSE
        FP16-POS-ZERO
    THEN ;

\ =====================================================================
\  PCM-SPECTRAL-FLATNESS — geometric mean / arithmetic mean of spectrum
\ =====================================================================
\  ( buf -- ratio-fp16 )
\  1.0 = white noise (all bins equal), 0.0 = pure tone.
\  Immediately separates noise-based sounds from tonal ones.
\
\  geom_mean = exp( mean(log(power)) )
\  arith_mean = mean(power)
\
\  We approximate log via FP32 and the exponent field:
\  For FP16 x > 0: log2(x) ≈ exponent + mantissa/1024
\  Then convert to natural log: ln(x) = log2(x) × ln(2)
\
\  Actually, for ratio purposes we can use log2 directly since
\  the ln(2) factors cancel in geom/arith:
\  geom/arith = exp(mean(log(p))) / mean(p)
\             = 2^(mean(log2(p))) / mean(p)

VARIABLE _PP-SF-LOGSUM      \ FP32 sum of log2(power)
VARIABLE _PP-SF-ARSUM       \ FP32 sum of power
VARIABLE _PP-SF-CNT

: _PP-LOG2-APPROX  ( fp16 -- log2-fp32 )
    \ Quick log2 approximation for positive FP16 values.
    \ log2(x) ≈ exponent + mantissa/1024 - 15
    \ FP16: seee eemm mmmm mmmm
    \ exponent = bits[14:10], mantissa = bits[9:0]
    DUP 0x7FFF AND                    \ clear sign
    DUP 0x7C00 AND 10 RSHIFT          \ exponent (0-30)
    15 -                               \ unbias → signed exp
    INT>FP16 FP16>FP32                 ( fp16 exp32 )
    SWAP 0x03FF AND                    \ mantissa (0-1023)
    INT>FP16 FP16>FP32                 ( exp32 mant32 )
    1024 INT>FP16 FP16>FP32 FP32-DIV   ( exp32 mant/1024 )
    FP32-ADD ;                          ( log2 ≈ exp + mant/1024 )

: PCM-SPECTRAL-FLATNESS  ( buf -- ratio-fp16 )
    _PP-SETUP

    FP32-ZERO _PP-SF-LOGSUM !
    FP32-ZERO _PP-SF-ARSUM  !
    0 _PP-SF-CNT !

    _PP-NBINS 1 DO
        _PP-PWR @ I 2* + W@           \ power_k (FP16)
        DUP 0x7FFF AND 0= IF          \ skip zero-power bins
            DROP
        ELSE
            DUP FP16>FP32
            _PP-SF-ARSUM @ FP32-ADD _PP-SF-ARSUM !

            _PP-LOG2-APPROX
            _PP-SF-LOGSUM @ FP32-ADD _PP-SF-LOGSUM !

            _PP-SF-CNT @ 1+ _PP-SF-CNT !
        THEN
    LOOP

    _PP-SF-CNT @ 2 < IF
        FP16-POS-ZERO EXIT              \ not enough data
    THEN

    \ geom_mean = 2^(mean_log2)
    \ mean_log2 = logsum / cnt
    _PP-SF-LOGSUM @
    _PP-SF-CNT @ INT>FP16 FP16>FP32 FP32-DIV   ( mean-log2-fp32 )

    \ 2^x approximation:
    \ Split x into integer n and fractional f.
    \ 2^x = 2^n × 2^f  where 2^f ≈ 1 + 0.6931×f (rough)
    \ But for a RATIO we can avoid full exp — just compare in log domain.
    \
    \ flatness = geom / arith = 2^mean(log2(p)) / mean(p)
    \ In log2: log2(flatness) = mean(log2(p)) - log2(mean(p))
    \ flatness = 2^(mean(log2(p)) - log2(mean(p)))
    \
    \ Compute log2(arith_mean):
    \ arith_mean = arsum / cnt
    _PP-SF-ARSUM @
    _PP-SF-CNT @ INT>FP16 FP16>FP32 FP32-DIV   ( mean-log2 arith-mean32 )
    FP32>FP16                                     ( mean-log2 arith-mean16 )

    DUP 0x7FFF AND 0= IF
        2DROP FP16-POS-ZERO EXIT        \ arith mean is zero
    THEN

    _PP-LOG2-APPROX                      ( mean-log2 log2-arith32 )
    FP32-SUB                             ( log2-flatness-fp32 )

    \ 2^x via FP16 construction (rough but good enough for [0,1]):
    \ Clamp to [-14, 0] (FP16 range is 2^-14 to 2^15)
    \ If log2-flatness > 0, clamp to 0 → flatness = 1.0
    \ If log2-flatness < -14, → 0
    DUP FP32-ZERO FP32>= IF
        DROP FP16-POS-ONE EXIT           \ flatness >= 1.0
    THEN

    \ Convert to FP16 for the 2^x approximation
    FP32>FP16                             ( log2-flat-fp16, negative )

    \ 2^x for x in [-14, 0]:
    \ Quick: negate x, then FP16 reciprocal trick
    \ Actually simpler: use 2^x ≈ 1 + 0.693×x + 0.240×x² for |x|<2
    \ But x can be large. Use: 2^x = 2^int(x) × 2^frac(x)
    \ For small output, just use the division approach:
    \ flatness = geom/arith directly.

    \ Alternative direct approach for ratio:
    \ We have log2(geom/arith). To get geom/arith:
    \ If the value is very negative (< -5), result is near 0.
    \ For modest values, approximate 2^x via polynomial.

    \ Simple piecewise: 2^(-n) for n=0..103
    DUP FP16-NEG                          ( x  |x| )
    DUP 10 INT>FP16 FP16-GT IF
        2DROP FP16-POS-ZERO EXIT          \ < 2^-10 ≈ 0
    THEN

    \ Use: 2^(-|x|) = 1 / 2^|x|
    \ 2^|x| ≈ FP16 exp trick: construct from integer/frac parts
    \ Integer part: shift 1 left by floor(|x|)
    DUP FP16-FLOOR FP16>INT              ( x |x| n )
    1 SWAP LSHIFT                         ( x |x| 2^n )
    -ROT                                  ( 2^n x |x| )
    FP16-FRAC                             ( 2^n x frac )
    \ 2^frac ≈ 1 + 0.693*frac (first-order Taylor)
    NIP                                   ( 2^n frac )
    0x3987 FP16-MUL                       \ 0x3987 ≈ 0.693 (ln2)
    FP16-POS-ONE FP16-ADD                 ( 2^n 2^frac-approx )
    SWAP INT>FP16 FP16-MUL               ( 2^|x|-approx )
    FP16-RECIP ;                           ( 2^(-|x|) = flatness )

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _aperc-guard

' PCM-A-WEIGHTED-RMS CONSTANT _pcm-a-weighted-rms-xt
' PCM-BRIGHTNESS  CONSTANT _pcm-brightness-xt
' PCM-SPECTRAL-FLATNESS CONSTANT _pcm-spectral-flatness-xt

: PCM-A-WEIGHTED-RMS _pcm-a-weighted-rms-xt _aperc-guard WITH-GUARD ;
: PCM-BRIGHTNESS  _pcm-brightness-xt _aperc-guard WITH-GUARD ;
: PCM-SPECTRAL-FLATNESS _pcm-spectral-flatness-xt _aperc-guard WITH-GUARD ;
[THEN] [THEN]
