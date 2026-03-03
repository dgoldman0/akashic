\ audio/analysis/spectral.f — Spectral analysis for PCM buffers
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Frequency-domain analysis using the existing FFT infrastructure.
\ Answers "what frequencies are present and how loud are they."
\
\ Words:
\   PCM-SPECTRAL-CENTROID   ( buf -- freq-fp16 )
\   PCM-SPECTRAL-SPREAD     ( buf -- spread-fp16 )
\   PCM-BAND-ENERGY         ( buf lo-hz hi-hz -- energy-fp16 )
\   PCM-PITCH-ESTIMATE      ( buf -- freq-fp16 )
\   PCM-SPECTRAL-ROLLOFF    ( buf pct -- freq-fp16 )
\   PCM-SPECTRAL-FLUX       ( buf n-windows -- flux-fp16 )
\
\ All words accept an FP16-valued mono PCM buffer (the native format
\ from every Akashic syn/ engine).  Results are FP16.
\
\ Implementation: zero-pad PCM to next power-of-2, run FFT-FORWARD +
\ FFT-POWER to get power spectrum, compute weighted sums with FP32
\ accumulation.
\
\ Prefix: PCM-    (public — extends audio/pcm.f namespace)
\         _SP-    (internals)
\
\ Load with:   REQUIRE audio/analysis/spectral.f

REQUIRE fp16.f
REQUIRE fp16-ext.f
REQUIRE fp32.f
REQUIRE trig.f
REQUIRE fft.f
REQUIRE audio/pcm.f

PROVIDED akashic-analysis-spectral

\ =====================================================================
\  Constants
\ =====================================================================

256 CONSTANT _SP-NFFT       \ FFT size: 256 is fine for 8 kHz 
                             \ (128 usable bins, ~31 Hz/bin)
128 CONSTANT _SP-NBINS      \ usable bins = NFFT/2

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _SP-BUF             \ source PCM buffer
VARIABLE _SP-DPTR            \ source data pointer
VARIABLE _SP-LEN             \ source frame count
VARIABLE _SP-RATE            \ sample rate

VARIABLE _SP-RE              \ real array (NFFT FP16 values)
VARIABLE _SP-IM              \ imaginary array (NFFT FP16 values)
VARIABLE _SP-PWR             \ power spectrum array (NFFT FP16 values)

VARIABLE _SP-ALLOCATED       \ flag: arrays allocated?
0 _SP-ALLOCATED !

\ =====================================================================
\  Internal: allocate FFT work arrays (once, reused)
\ =====================================================================

: _SP-ALLOC  ( -- )
    _SP-ALLOCATED @ IF EXIT THEN
    _SP-NFFT 2* ALLOCATE DROP _SP-RE  !
    _SP-NFFT 2* ALLOCATE DROP _SP-IM  !
    _SP-NFFT 2* ALLOCATE DROP _SP-PWR !
    1 _SP-ALLOCATED ! ;

\ =====================================================================
\  Internal: setup — copy PCM data into RE, zero IM, compute power
\ =====================================================================
\  ( buf -- )  Fills _SP-RE with samples (zero-padded), clears _SP-IM,
\  runs FFT-FORWARD + FFT-POWER.

: _SP-SETUP  ( buf -- )
    _SP-ALLOC
    DUP _SP-BUF !
    DUP PCM-DATA _SP-DPTR !
    DUP PCM-LEN  _SP-LEN !
    PCM-RATE _SP-RATE !

    \ Copy samples into RE (up to NFFT), then zero-pad remainder
    _SP-LEN @ _SP-NFFT MIN   ( copy-count )
    DUP 0 ?DO
        _SP-DPTR @ I 2* + W@
        _SP-RE @ I 2* + W!
    LOOP

    \ Zero-pad rest of RE
    DUP _SP-NFFT < IF
        DUP _SP-NFFT SWAP DO
            0 _SP-RE @ I 2* + W!
        LOOP
    THEN
    DROP

    \ Clear imaginary array
    _SP-NFFT 0 DO
        0 _SP-IM @ I 2* + W!
    LOOP

    \ FFT forward
    _SP-RE @ _SP-IM @ _SP-NFFT FFT-FORWARD

    \ Power spectrum
    _SP-RE @ _SP-IM @ _SP-PWR @ _SP-NFFT FFT-POWER ;

\ =====================================================================
\  Internal: bin index → frequency in Hz (FP16)
\ =====================================================================
\  freq = bin * rate / NFFT

: _SP-BIN>HZ  ( bin -- freq-fp16 )
    INT>FP16
    _SP-RATE @ INT>FP16 _SP-NFFT INT>FP16 FP16-DIV   \ rate/NFFT first
    FP16-MUL ;                                         \ then bin * (rate/NFFT)

\ =====================================================================
\  PCM-SPECTRAL-CENTROID — center of mass of spectrum in Hz
\ =====================================================================
\  centroid = sum(freq_k × power_k) / sum(power_k)  for k = 1..N/2-1
\
\  Skip bin 0 (DC).  Use FP32 accumulation for the weighted sums.
\
\  Returns the "average frequency" of the sound.  A pure sine at 440 Hz
\  gives ~440.  White noise gives ~Nyquist/2.  A bass drone gives <200.

VARIABLE _SP-WSUM            \ FP32: sum(freq × power)
VARIABLE _SP-PSUM            \ FP32: sum(power)

: PCM-SPECTRAL-CENTROID  ( buf -- freq-fp16 )
    _SP-SETUP

    FP32-ZERO _SP-WSUM !
    FP32-ZERO _SP-PSUM !

    _SP-NBINS 1 DO                       \ bins 1..127
        _SP-PWR @ I 2* + W@              \ power_k (FP16)
        DUP FP16>FP32                     ( pk pk32 )
        _SP-PSUM @ FP32-ADD _SP-PSUM !   \ psum += pk

        FP16>FP32                         ( pk32 )
        I _SP-BIN>HZ FP16>FP32           ( pk32 freq32 )
        FP32-MUL                          ( freq*pk )
        _SP-WSUM @ FP32-ADD _SP-WSUM !   \ wsum += freq*pk
    LOOP

    \ centroid = wsum / psum
    _SP-PSUM @ FP32-ZERO FP32> IF
        _SP-WSUM @ _SP-PSUM @ FP32-DIV FP32>FP16
    ELSE
        FP16-POS-ZERO
    THEN ;

\ =====================================================================
\  PCM-SPECTRAL-SPREAD — std dev of spectrum around centroid (Hz)
\ =====================================================================
\  spread = sqrt( sum( (freq_k - centroid)^2 × power_k ) / sum(power_k) )
\
\  Requires centroid already computed.  We compute both in one pass
\  by storing centroid in a variable.

VARIABLE _SP-CENT-FP32       \ centroid in FP32 (from first pass)
VARIABLE _SP-VSUM            \ FP32: sum( (f-c)^2 * p )

: PCM-SPECTRAL-SPREAD  ( buf -- spread-fp16 )
    _SP-SETUP

    FP32-ZERO _SP-WSUM !
    FP32-ZERO _SP-PSUM !

    \ First pass: compute centroid
    _SP-NBINS 1 DO
        _SP-PWR @ I 2* + W@
        DUP FP16>FP32
        _SP-PSUM @ FP32-ADD _SP-PSUM !
        FP16>FP32
        I _SP-BIN>HZ FP16>FP32
        FP32-MUL
        _SP-WSUM @ FP32-ADD _SP-WSUM !
    LOOP

    _SP-PSUM @ FP32-ZERO FP32> IF
        _SP-WSUM @ _SP-PSUM @ FP32-DIV _SP-CENT-FP32 !
    ELSE
        FP16-POS-ZERO EXIT
    THEN

    \ Second pass: compute variance around centroid
    FP32-ZERO _SP-VSUM !

    _SP-NBINS 1 DO
        _SP-PWR @ I 2* + W@           \ power_k FP16
        FP16>FP32                       ( pk32 )
        I _SP-BIN>HZ FP16>FP32         ( pk32 freq32 )
        _SP-CENT-FP32 @ FP32-SUB       ( pk32 diff32 )
        DUP FP32-MUL                    ( pk32 diff^2 )
        FP32-MUL                        ( pk*diff^2 )
        _SP-VSUM @ FP32-ADD _SP-VSUM !
    LOOP

    _SP-VSUM @ _SP-PSUM @ FP32-DIV
    FP32-SQRT FP32>FP16 ;

\ =====================================================================
\  PCM-BAND-ENERGY — sum of power in [lo, hi] Hz range
\ =====================================================================
\  ( buf lo-hz hi-hz -- energy-fp16 )
\  lo-hz and hi-hz are plain integers (Hz).  Returns the total power
\  in that frequency band as an FP16 value.

VARIABLE _SP-BE-LO
VARIABLE _SP-BE-HI
VARIABLE _SP-BE-SUM

: PCM-BAND-ENERGY  ( buf lo-hz hi-hz -- energy-fp16 )
    _SP-BE-HI !
    _SP-BE-LO !
    _SP-SETUP

    FP32-ZERO _SP-BE-SUM !

    \ Convert Hz bounds to bin indices
    \ bin = freq / (rate / NFFT)  — avoid overflow from freq * NFFT
    _SP-RATE @ INT>FP16 _SP-NFFT INT>FP16 FP16-DIV    \ hz-per-bin = rate/NFFT

    DUP _SP-BE-LO @ INT>FP16 SWAP FP16-DIV FP16>INT   ( hz/bin lo-bin )
    1 MAX                                               \ at least bin 1

    SWAP _SP-BE-HI @ INT>FP16 SWAP FP16-DIV FP16>INT  ( lo-bin hi-bin )
    _SP-NBINS 1- MIN                                    \ at most bin 127

    1+ SWAP DO                                 ( -- )
        _SP-PWR @ I 2* + W@
        FP16>FP32
        _SP-BE-SUM @ FP32-ADD _SP-BE-SUM !
    LOOP

    _SP-BE-SUM @ FP32>FP16 ;

\ =====================================================================
\  PCM-PITCH-ESTIMATE — autocorrelation-based fundamental frequency
\ =====================================================================
\  ( buf -- freq-fp16 )
\  Computes autocorrelation of the signal and finds the first peak
\  after the origin.  The lag at that peak corresponds to the
\  fundamental period: freq = rate / lag.
\
\  Uses the power spectrum already computed: autocorrelation = IFFT
\  of power spectrum (Wiener–Khinchin theorem).
\  We reuse _SP-RE/_SP-IM for this.

VARIABLE _SP-PT-BEST
VARIABLE _SP-PT-LAG
VARIABLE _SP-PT-PREV

: PCM-PITCH-ESTIMATE  ( buf -- freq-fp16 )
    _SP-SETUP

    \ Autocorrelation via IFFT of power spectrum
    \ Copy power spectrum into RE, zero IM
    _SP-NFFT 0 DO
        _SP-PWR @ I 2* + W@
        _SP-RE @ I 2* + W!
        0 _SP-IM @ I 2* + W!
    LOOP

    _SP-RE @ _SP-IM @ _SP-NFFT FFT-INVERSE

    \ Now RE contains the autocorrelation (IM should be ~0).
    \ Find the first peak after lag 0.
    \ Walk from lag=2 (skip 0 and 1 which are always high)
    \ until we find a sample greater than its neighbors.

    FP16-POS-ZERO _SP-PT-BEST !
    0 _SP-PT-LAG !
    _SP-RE @ 2 2* + W@ _SP-PT-PREV !    \ r[2]

    \ Search from lag 3 to NFFT/2
    \ Looking for: r[lag] > r[lag-1] AND r[lag] > r[lag+1]
    \ and r[lag] is the largest such peak found.
    _SP-NBINS 3 DO
        _SP-RE @ I 2* + W@              \ r[lag]
        DUP _SP-PT-PREV @ FP16-GT IF    \ r[lag] > r[lag-1] ?
            DUP                            ( r[lag] r[lag] )
            _SP-RE @ I 1+ 2* + W@         ( r[lag] r[lag] r[lag+1] )
            FP16-GT IF                     \ r[lag] > r[lag+1] ?
                \ This is a peak. Is it the biggest?
                DUP _SP-PT-BEST @ FP16-GT IF
                    DUP _SP-PT-BEST !
                    I _SP-PT-LAG !
                THEN
            THEN
        THEN
        _SP-PT-PREV !                    \ prev = r[lag] for next iter
    LOOP

    \ freq = rate / lag
    _SP-PT-LAG @ 0= IF
        FP16-POS-ZERO
    ELSE
        _SP-RATE @ INT>FP16
        _SP-PT-LAG @ INT>FP16
        FP16-DIV
    THEN ;

\ =====================================================================
\  PCM-SPECTRAL-ROLLOFF — frequency below which pct% of energy sits
\ =====================================================================
\  ( buf pct -- freq-fp16 )
\  pct is an integer 0-100.  E.g. PCM-SPECTRAL-ROLLOFF with pct=85
\  returns the frequency below which 85% of spectral energy resides.

VARIABLE _SP-RO-THRESH
VARIABLE _SP-RO-ACC

: PCM-SPECTRAL-ROLLOFF  ( buf pct -- freq-fp16 )
    SWAP _SP-SETUP

    \ Compute total energy first
    FP32-ZERO _SP-PSUM !
    _SP-NBINS 1 DO
        _SP-PWR @ I 2* + W@
        FP16>FP32
        _SP-PSUM @ FP32-ADD _SP-PSUM !
    LOOP

    \ Threshold = total × pct / 100
    INT>FP16 FP16>FP32                  ( pct32 )
    _SP-PSUM @ FP32-MUL                 ( total*pct )
    100 INT>FP16 FP16>FP32 FP32-DIV     ( threshold )
    _SP-RO-THRESH !

    \ Walk bins, accumulate until >= threshold
    FP32-ZERO _SP-RO-ACC !
    _SP-NBINS 1 DO
        _SP-PWR @ I 2* + W@
        FP16>FP32
        _SP-RO-ACC @ FP32-ADD
        DUP _SP-RO-ACC !
        _SP-RO-THRESH @ FP32>= IF
            I _SP-BIN>HZ UNLOOP EXIT
        THEN
    LOOP

    \ If we didn't reach threshold, return Nyquist
    _SP-RATE @ 2/ INT>FP16 ;

\ =====================================================================
\  PCM-SPECTRAL-FLUX — spectral change between consecutive windows
\ =====================================================================
\  ( buf n-windows -- flux-fp16 )
\  Splits the buffer into n-windows time windows, computes the power
\  spectrum for each, and measures the average bin-by-bin difference
\  between consecutive windows.  High flux = timbral change.
\
\  This re-does _SP-SETUP per window, so it's relatively expensive.

VARIABLE _SP-FL-NWIN
VARIABLE _SP-FL-WLEN         \ samples per window
VARIABLE _SP-FL-PREV         \ previous window's power spectrum
VARIABLE _SP-FL-ALLOC2       \ flag: prev array allocated?
VARIABLE _SP-FL-SUM          \ FP32 accumulation of flux
VARIABLE _SP-FL-PTOT         \ FP32: total power (for normalization)

0 _SP-FL-ALLOC2 !

: _SP-FL-ALLOC-PREV  ( -- )
    _SP-FL-ALLOC2 @ IF EXIT THEN
    _SP-NFFT 2* ALLOCATE DROP _SP-FL-PREV !
    1 _SP-FL-ALLOC2 ! ;

: PCM-SPECTRAL-FLUX  ( buf n-windows -- flux-fp16 )
    _SP-FL-NWIN !
    DUP _SP-BUF !
    DUP PCM-DATA _SP-DPTR !
    DUP PCM-LEN _SP-LEN !
    PCM-RATE _SP-RATE !

    _SP-ALLOC
    _SP-FL-ALLOC-PREV

    _SP-LEN @ _SP-FL-NWIN @ / _SP-FL-WLEN !

    FP32-ZERO _SP-FL-SUM !

    _SP-FL-NWIN @ 0 DO
        \ Clear RE + IM
        _SP-NFFT 0 ?DO
            0 _SP-RE @ I 2* + W!
            0 _SP-IM @ I 2* + W!
        LOOP

        \ Copy window i samples into RE
        _SP-FL-WLEN @ _SP-NFFT MIN 0 ?DO
            _SP-DPTR @ I 2* +  J _SP-FL-WLEN @ * 2* +  W@
            _SP-RE @ I 2* + W!
        LOOP

        \ Compute power spectrum for this window
        _SP-RE @ _SP-IM @ _SP-NFFT FFT-FORWARD
        _SP-RE @ _SP-IM @ _SP-PWR @ _SP-NFFT FFT-POWER

        \ Normalize power spectrum to sum=1 so flux is scale-invariant
        FP32-ZERO _SP-FL-PTOT !
        _SP-NBINS 1 ?DO
            _SP-PWR @ I 2* + W@ FP16>FP32
            _SP-FL-PTOT @ FP32-ADD _SP-FL-PTOT !
        LOOP
        _SP-FL-PTOT @ FP32-ZERO FP32> IF
            _SP-NBINS 1 ?DO
                _SP-PWR @ I 2* + W@
                FP16>FP32  _SP-FL-PTOT @  FP32-DIV  FP32>FP16
                _SP-PWR @ I 2* + W!
            LOOP
        THEN

        \ If not the first window, accumulate flux
        I 0 > IF
            _SP-NBINS 1 ?DO
                _SP-PWR @ I 2* + W@          \ current bin
                _SP-FL-PREV @ I 2* + W@      \ previous bin
                FP16-SUB FP16-ABS             \ |curr - prev|
                FP16>FP32
                _SP-FL-SUM @ FP32-ADD _SP-FL-SUM !
            LOOP
        THEN

        \ Save current power as previous
        _SP-NBINS 0 ?DO
            _SP-PWR @ I 2* + W@
            _SP-FL-PREV @ I 2* + W!
        LOOP
    LOOP

    \ Average flux per window transition
    _SP-FL-NWIN @ 1 > IF
        _SP-FL-SUM @
        _SP-FL-NWIN @ 1- _SP-NBINS * INT>FP16 FP16>FP32  \ divisor
        FP32-DIV FP32>FP16
    ELSE
        FP16-POS-ZERO
    THEN ;
