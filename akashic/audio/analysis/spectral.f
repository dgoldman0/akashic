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

REQUIRE ../../math/fp16.f
REQUIRE ../../math/fp16-ext.f
REQUIRE ../../math/fp32.f
REQUIRE ../../math/trig.f
REQUIRE ../../math/fft.f
REQUIRE ../pcm.f

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
    _SP-NFFT 2* ALLOCATE
    DUP IF 2DROP -1 ABORT" spectral: real-array allocation failed" THEN
    DROP _SP-RE !

    _SP-NFFT 2* ALLOCATE
    DUP IF
        2DROP
        _SP-RE @ FREE  0 _SP-RE !
        -1 ABORT" spectral: imaginary-array allocation failed"
    THEN
    DROP _SP-IM !

    _SP-NFFT 2* ALLOCATE
    DUP IF
        2DROP
        _SP-IM @ FREE  0 _SP-IM !
        _SP-RE @ FREE  0 _SP-RE !
        -1 ABORT" spectral: power-array allocation failed"
    THEN
    DROP _SP-PWR !
    1 _SP-ALLOCATED ! ;

\ =====================================================================
\  Internal: setup — copy PCM data into RE, zero IM, compute power
\ =====================================================================
\  ( buf -- )  Fills _SP-RE with samples (zero-padded), clears _SP-IM,
\  runs FFT-FORWARD + FFT-POWER.

: _SP-SETUP  ( buf -- )
    DUP PCM-FP16-MONO? 0=
        ABORT" spectral: buffer must be mono FP16 PCM"
    DUP PCM-RATE 1 < ABORT" spectral: sample rate must be positive"
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

: _SP-BIN>HZ32  ( bin -- freq-fp32 )
    INT>FP32
    _SP-RATE @ INT>FP32 _SP-NFFT INT>FP32 FP32-DIV
    FP32-MUL ;

: _SP-BIN>HZ  ( bin -- freq-fp16 )
    _SP-BIN>HZ32 FP32>FP16 ;

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
        I _SP-BIN>HZ32                    ( pk32 freq32 )
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
        I _SP-BIN>HZ32
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
        I _SP-BIN>HZ32                 ( pk32 freq32 )
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
VARIABLE _SP-BE-LOBIN
VARIABLE _SP-BE-HIBIN
VARIABLE _SP-BE-NYQUIST

: _SP-BE-CLAMP-BIN  ( bin -- bin' )
    DUP 1 < IF DROP 1 THEN
    DUP _SP-NBINS >= IF DROP _SP-NBINS 1- THEN ;

: PCM-BAND-ENERGY  ( buf lo-hz hi-hz -- energy-fp16 )
    _SP-BE-HI !
    _SP-BE-LO !
    _SP-BE-LO @ 0< ABORT" PCM-BAND-ENERGY: low bound must not be negative"
    _SP-BE-HI @ _SP-BE-LO @ <=
        ABORT" PCM-BAND-ENERGY: high bound must exceed low bound"
    _SP-SETUP

    FP32-ZERO _SP-BE-SUM !

    \ Restrict Hz inputs before multiplying by NFFT.  This both prevents
    \ integer overflow and makes a wholly out-of-range band return zero.
    _SP-RATE @ 2/ _SP-BE-NYQUIST !
    _SP-BE-LO @ _SP-BE-NYQUIST @ >= IF
        FP16-POS-ZERO EXIT
    THEN
    _SP-BE-HI @ _SP-BE-NYQUIST @ > IF
        _SP-BE-NYQUIST @ _SP-BE-HI !
    THEN

    \ Values are now <= rate/2, so freq*NFFT is small even at 96 kHz.
    _SP-BE-LO @ _SP-NFFT * _SP-RATE @ /
    _SP-BE-CLAMP-BIN _SP-BE-LOBIN !
    _SP-BE-HI @ _SP-NFFT * _SP-RATE @ /
    DUP 1 < IF DROP FP16-POS-ZERO EXIT THEN
    _SP-BE-CLAMP-BIN _SP-BE-HIBIN !
    _SP-BE-LOBIN @ _SP-BE-HIBIN @ > IF
        FP16-POS-ZERO EXIT
    THEN

    _SP-BE-HIBIN @ 1+ _SP-BE-LOBIN @ DO
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
\  after the initial dip from the origin.  The lag at that peak
\  corresponds to the fundamental period: freq = rate / lag.
\
\  Uses the power spectrum already computed: autocorrelation = IFFT
\  of power spectrum (Wiener–Khinchin theorem).
\  We reuse _SP-RE/_SP-IM for this.
\
\  Algorithm: "first peak after dip" (standard approach).
\    Phase 1 — walk from lag 2, looking for autocorrelation to
\              decline (r[lag] <= r[lag-1]).  This marks the end of
\              the origin region.
\    Phase 2 — continue walking, waiting for the first local
\              maximum: r[lag] > r[lag-1] AND r[lag] > r[lag+1].
\              That first peak corresponds to the fundamental period.
\
\  Why not "largest peak"?  For signals with rich harmonics the
\  autocorrelation at 2× the period can be nearly equal to the peak
\  at 1× the period.  FP16 rounding can flip the ordering, causing
\  the algorithm to report half the true frequency (octave-below
\  error).  Finding the *first* peak avoids this entirely.

VARIABLE _SP-PT-LAG
VARIABLE _SP-PT-PREV
VARIABLE _SP-PT-DIP      \ 0 = still in origin region, 1 = past dip

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

    \ First-peak-after-dip search
    0 _SP-PT-LAG !
    0 _SP-PT-DIP !
    _SP-RE @ 2 2* + W@ _SP-PT-PREV !    \ r[2]

    _SP-NBINS 3 DO
        _SP-PT-LAG @ 0= IF              \ only if not yet found
            _SP-RE @ I 2* + W@          ( r[lag] )

            _SP-PT-DIP @ 0= IF
                \ Phase 1: still in origin region, looking for decline
                DUP _SP-PT-PREV @
                FP16-GT 0= IF           \ r[lag] <= r[lag-1] => declining
                    1 _SP-PT-DIP !
                THEN
            ELSE
                \ Phase 2: past dip, looking for first peak
                DUP _SP-PT-PREV @
                FP16-GT IF              \ r[lag] > r[lag-1] ? (ascending)
                    DUP
                    _SP-RE @ I 1+ 2* + W@
                    FP16-GT IF          \ r[lag] > r[lag+1] ? (peak!)
                        I _SP-PT-LAG !
                    THEN
                THEN
            THEN

            _SP-PT-PREV !              \ prev = r[lag]
        THEN
    LOOP

    \ freq = rate / lag
    _SP-PT-LAG @ 0= IF
        FP16-POS-ZERO
    ELSE
        _SP-RATE @ INT>FP32
        _SP-PT-LAG @ INT>FP32
        FP32-DIV FP32>FP16
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
    DUP 0< OVER 100 > OR
        ABORT" PCM-SPECTRAL-ROLLOFF: percentage must be 0 through 100"
    SWAP _SP-SETUP

    \ Compute total energy first
    FP32-ZERO _SP-PSUM !
    _SP-NBINS 1 DO
        _SP-PWR @ I 2* + W@
        FP16>FP32
        _SP-PSUM @ FP32-ADD _SP-PSUM !
    LOOP

    \ Zero percent is defined at DC, and a silent spectrum has no
    \ meaningful first occupied bin.  Handle both before the >= walk.
    DUP 0= IF DROP FP16-POS-ZERO EXIT THEN
    _SP-PSUM @ FP32-ZERO FP32> 0= IF
        DROP FP16-POS-ZERO EXIT
    THEN

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
    _SP-RATE @ 2/ INT>FP32 FP32>FP16 ;

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
VARIABLE _SP-FL-REM          \ frames assigned to the final window

0 _SP-FL-ALLOC2 !

: _SP-FL-ALLOC-PREV  ( -- )
    _SP-FL-ALLOC2 @ IF EXIT THEN
    _SP-NFFT 2* ALLOCATE
    DUP IF 2DROP -1 ABORT" spectral flux: previous-array allocation failed" THEN
    DROP _SP-FL-PREV !
    1 _SP-FL-ALLOC2 ! ;

: PCM-SPECTRAL-FLUX  ( buf n-windows -- flux-fp16 )
    _SP-FL-NWIN !
    _SP-FL-NWIN @ 1 <
        ABORT" PCM-SPECTRAL-FLUX: window count must be positive"
    DUP PCM-FP16-MONO? 0=
        ABORT" PCM-SPECTRAL-FLUX: buffer must be mono FP16 PCM"
    DUP _SP-BUF !
    DUP PCM-DATA _SP-DPTR !
    DUP PCM-LEN _SP-LEN !
    PCM-RATE _SP-RATE !
    _SP-RATE @ 1 < ABORT" PCM-SPECTRAL-FLUX: sample rate must be positive"

    _SP-ALLOC
    _SP-FL-ALLOC-PREV

    _SP-LEN @ _SP-FL-NWIN @ <
        ABORT" PCM-SPECTRAL-FLUX: windows exceed buffer frames"
    _SP-LEN @ _SP-FL-NWIN @ / _SP-FL-WLEN !
    _SP-LEN @ _SP-FL-NWIN @ MOD _SP-FL-REM !
    _SP-FL-WLEN @ _SP-FL-REM @ + _SP-NFFT >
        ABORT" PCM-SPECTRAL-FLUX: a window exceeds the FFT size"

    FP32-ZERO _SP-FL-SUM !

    _SP-FL-NWIN @ 0 DO
        \ Clear RE + IM
        _SP-NFFT 0 ?DO
            0 _SP-RE @ I 2* + W!
            0 _SP-IM @ I 2* + W!
        LOOP

        \ Copy window i samples into RE
        _SP-FL-WLEN @
        I _SP-FL-NWIN @ 1- = IF _SP-FL-REM @ + THEN
        _SP-NFFT MIN 0 ?DO
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
        _SP-FL-NWIN @ 1- INT>FP32
        _SP-NBINS 1- INT>FP32 FP32-MUL
        FP32-DIV FP32>FP16
    ELSE
        FP16-POS-ZERO
    THEN ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _aspec-guard

' PCM-SPECTRAL-CENTROID CONSTANT _pcm-spectral-centroid-xt
' PCM-SPECTRAL-SPREAD CONSTANT _pcm-spectral-spread-xt
' PCM-BAND-ENERGY CONSTANT _pcm-band-energy-xt
' PCM-PITCH-ESTIMATE CONSTANT _pcm-pitch-estimate-xt
' PCM-SPECTRAL-ROLLOFF CONSTANT _pcm-spectral-rolloff-xt
' PCM-SPECTRAL-FLUX CONSTANT _pcm-spectral-flux-xt

: PCM-SPECTRAL-CENTROID _pcm-spectral-centroid-xt _aspec-guard WITH-GUARD ;
: PCM-SPECTRAL-SPREAD _pcm-spectral-spread-xt _aspec-guard WITH-GUARD ;
: PCM-BAND-ENERGY _pcm-band-energy-xt _aspec-guard WITH-GUARD ;
: PCM-PITCH-ESTIMATE _pcm-pitch-estimate-xt _aspec-guard WITH-GUARD ;
: PCM-SPECTRAL-ROLLOFF _pcm-spectral-rolloff-xt _aspec-guard WITH-GUARD ;
: PCM-SPECTRAL-FLUX _pcm-spectral-flux-xt _aspec-guard WITH-GUARD ;
[THEN] [THEN]
