\ filter.f — Digital Filters for FP16 arrays
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ Implements FIR, IIR biquad, 1D convolution, moving average,
\ median, and simple low-pass / high-pass filters on FP16 data.
\
\ FIR filtering is implemented as a sliding dot-product — each
\ output sample is the inner product of the coefficient vector with
\ a window of input samples.  The IIR biquad uses the direct-form-II
\ transposed structure for a single second-order section.
\
\ Low-pass and high-pass use a windowed-sinc kernel (Hamming window)
\ computed on-the-fly, then applied via FILT-FIR.
\
\ Prefix: FILT-  (public API)
\         _FILT- (internal helpers)
\
\ Depends on: fp16.f, fp16-ext.f, simd.f, trig.f, sort.f
\
\ Load with:   REQUIRE filter.f
\
\ === Public API ===
\   FILT-FIR       ( input coeff n-taps dst n-out -- )  FIR filter
\   FILT-IIR-BIQUAD ( input b0 b1 b2 a1 a2 dst n -- ) Second-order IIR
\   FILT-CONV1D    ( input kernel ksize dst n -- )      1D convolution
\   FILT-MA        ( input window dst n -- )            Moving average
\   FILT-MEDIAN    ( input window dst n -- )            Median filter
\   FILT-LOWPASS   ( input cutoff dst n -- )            Simple low-pass
\   FILT-HIGHPASS  ( input cutoff dst n -- )            Simple high-pass

REQUIRE fp16-ext.f
REQUIRE simd.f
REQUIRE trig.f
REQUIRE sort.f

PROVIDED akashic-filter

\ =====================================================================
\  FP16 Constants
\ =====================================================================

0x0000 CONSTANT _FILT-ZERO            \ 0.0
0x3C00 CONSTANT _FILT-ONE             \ 1.0
0x4000 CONSTANT _FILT-TWO             \ 2.0
0x3800 CONSTANT _FILT-HALF            \ 0.5
0xBC00 CONSTANT _FILT-NEG1            \ -1.0

\ Hamming window constants: 0.54 and 0.46
0x3851 CONSTANT _FILT-HAMM-A          \ 0.54  (FP16 0x3851 ≈ 0.5400)
0x375C CONSTANT _FILT-HAMM-B          \ 0.46  (FP16 0x375C ≈ 0.4600)

\ =====================================================================
\  FILT-FIR — Finite Impulse Response filter
\ =====================================================================
\  output[i] = sum_{k=0}^{ntaps-1} coeff[k] * input[i+k]
\
\  The input buffer must contain at least (n-out + n-taps - 1)
\  valid samples.  coeff[] has n-taps FP16 values.  dst[] receives
\  n-out FP16 values.
\
\  For each output sample we slide a window over input[] and
\  compute the dot-product with coeff[].

VARIABLE _FIR-IN                      \ input base address
VARIABLE _FIR-CO                      \ coefficient base address
VARIABLE _FIR-TAPS                    \ number of taps
VARIABLE _FIR-DST                     \ destination base address
VARIABLE _FIR-NOUT                    \ number of output samples
VARIABLE _FIR-I                       \ output index
VARIABLE _FIR-K                       \ tap index
VARIABLE _FIR-ACC                     \ accumulator (FP16)

: FILT-FIR  ( input coeff n-taps dst n-out -- )
    _FIR-NOUT !
    _FIR-DST !
    _FIR-TAPS !
    _FIR-CO !
    _FIR-IN !

    0 _FIR-I !
    BEGIN _FIR-I @ _FIR-NOUT @ < WHILE
        _FILT-ZERO _FIR-ACC !

        \ Dot product: sum coeff[k] * input[i+k]
        0 _FIR-K !
        BEGIN _FIR-K @ _FIR-TAPS @ < WHILE
            _FIR-CO @ _FIR-K @ 2 * + W@           ( coeff[k] )
            _FIR-IN @ _FIR-I @ _FIR-K @ + 2 * + W@  ( coeff[k] input[i+k] )
            FP16-MUL                               ( product )
            _FIR-ACC @ FP16-ADD _FIR-ACC !         ( )
            _FIR-K @ 1+ _FIR-K !
        REPEAT

        _FIR-ACC @
        _FIR-DST @ _FIR-I @ 2 * + W!
        _FIR-I @ 1+ _FIR-I !
    REPEAT ;

\ =====================================================================
\  FILT-IIR-BIQUAD — Second-order IIR (Direct Form II Transposed)
\ =====================================================================
\  Transfer function:
\    H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
\
\  Using the transposed direct form II:
\    y[n] = b0*x[n] + s1
\    s1   = b1*x[n] - a1*y[n] + s2
\    s2   = b2*x[n] - a2*y[n]
\
\  All coefficients are FP16 raw bit patterns.

VARIABLE _IIR-IN
VARIABLE _IIR-DST
VARIABLE _IIR-N
VARIABLE _IIR-B0
VARIABLE _IIR-B1
VARIABLE _IIR-B2
VARIABLE _IIR-A1
VARIABLE _IIR-A2
VARIABLE _IIR-S1                      \ state register 1
VARIABLE _IIR-S2                      \ state register 2
VARIABLE _IIR-I                       \ loop index
VARIABLE _IIR-X                       \ current input sample
VARIABLE _IIR-Y                       \ current output sample

: FILT-IIR-BIQUAD  ( input b0 b1 b2 a1 a2 dst n -- )
    _IIR-N !
    _IIR-DST !
    _IIR-A2 !
    _IIR-A1 !
    _IIR-B2 !
    _IIR-B1 !
    _IIR-B0 !
    _IIR-IN !

    \ Zero state registers
    _FILT-ZERO _IIR-S1 !
    _FILT-ZERO _IIR-S2 !

    0 _IIR-I !
    BEGIN _IIR-I @ _IIR-N @ < WHILE
        \ x = input[i]
        _IIR-IN @ _IIR-I @ 2 * + W@ _IIR-X !

        \ y = b0*x + s1
        _IIR-B0 @ _IIR-X @ FP16-MUL
        _IIR-S1 @ FP16-ADD
        _IIR-Y !

        \ s1 = b1*x - a1*y + s2
        _IIR-B1 @ _IIR-X @ FP16-MUL
        _IIR-A1 @ _IIR-Y @ FP16-MUL FP16-SUB
        _IIR-S2 @ FP16-ADD
        _IIR-S1 !

        \ s2 = b2*x - a2*y
        _IIR-B2 @ _IIR-X @ FP16-MUL
        _IIR-A2 @ _IIR-Y @ FP16-MUL FP16-SUB
        _IIR-S2 !

        \ dst[i] = y
        _IIR-Y @
        _IIR-DST @ _IIR-I @ 2 * + W!

        _IIR-I @ 1+ _IIR-I !
    REPEAT ;

\ =====================================================================
\  FILT-CONV1D — 1D Convolution
\ =====================================================================
\  output[i] = sum_{k=0}^{ksize-1} input[i+k] * kernel[k]
\
\  Identical to FIR mathematically, but the name convention signals
\  "general purpose 1D convolution" vs. "filter coefficients".
\  Input must have at least (n + ksize - 1) valid samples.

VARIABLE _C1D-IN
VARIABLE _C1D-KRN
VARIABLE _C1D-KSIZE
VARIABLE _C1D-DST
VARIABLE _C1D-N
VARIABLE _C1D-I
VARIABLE _C1D-K
VARIABLE _C1D-ACC

: FILT-CONV1D  ( input kernel ksize dst n -- )
    _C1D-N !
    _C1D-DST !
    _C1D-KSIZE !
    _C1D-KRN !
    _C1D-IN !

    0 _C1D-I !
    BEGIN _C1D-I @ _C1D-N @ < WHILE
        _FILT-ZERO _C1D-ACC !

        0 _C1D-K !
        BEGIN _C1D-K @ _C1D-KSIZE @ < WHILE
            _C1D-IN @ _C1D-I @ _C1D-K @ + 2 * + W@  ( input[i+k] )
            _C1D-KRN @ _C1D-K @ 2 * + W@             ( input[i+k] kernel[k] )
            FP16-MUL                                  ( product )
            _C1D-ACC @ FP16-ADD _C1D-ACC !
            _C1D-K @ 1+ _C1D-K !
        REPEAT

        _C1D-ACC @
        _C1D-DST @ _C1D-I @ 2 * + W!
        _C1D-I @ 1+ _C1D-I !
    REPEAT ;

\ =====================================================================
\  FILT-MA — Moving Average filter
\ =====================================================================
\  output[i] = (1/window) * sum_{k=0}^{window-1} input[i+k]
\
\  The input buffer must contain at least (n + window - 1) valid
\  samples.  'window' is an integer (the window size).
\
\  We use a running sum: add the new sample entering the window,
\  subtract the sample leaving.

VARIABLE _MA-IN
VARIABLE _MA-WIN                      \ window size (integer)
VARIABLE _MA-DST
VARIABLE _MA-N
VARIABLE _MA-I
VARIABLE _MA-K
VARIABLE _MA-SUM                      \ running sum (FP16)
VARIABLE _MA-INVW                     \ 1/window (FP16)

: FILT-MA  ( input window dst n -- )
    _MA-N !
    _MA-DST !
    _MA-WIN !
    _MA-IN !

    \ Compute 1/window
    _FILT-ONE _MA-WIN @ INT>FP16 FP16-DIV _MA-INVW !

    \ Compute first window sum
    _FILT-ZERO _MA-SUM !
    0 _MA-K !
    BEGIN _MA-K @ _MA-WIN @ < WHILE
        _MA-IN @ _MA-K @ 2 * + W@
        _MA-SUM @ FP16-ADD _MA-SUM !
        _MA-K @ 1+ _MA-K !
    REPEAT

    \ First output
    _MA-SUM @ _MA-INVW @ FP16-MUL
    _MA-DST @ W!

    \ Sliding window for remaining outputs
    1 _MA-I !
    BEGIN _MA-I @ _MA-N @ < WHILE
        \ Subtract outgoing sample: input[i-1]
        _MA-IN @ _MA-I @ 1- 2 * + W@
        _MA-SUM @ SWAP FP16-SUB _MA-SUM !

        \ Add incoming sample: input[i + window - 1]
        _MA-IN @ _MA-I @ _MA-WIN @ + 1- 2 * + W@
        _MA-SUM @ FP16-ADD _MA-SUM !

        \ output[i] = sum * (1/window)
        _MA-SUM @ _MA-INVW @ FP16-MUL
        _MA-DST @ _MA-I @ 2 * + W!

        _MA-I @ 1+ _MA-I !
    REPEAT ;

\ =====================================================================
\  FILT-MEDIAN — Median filter
\ =====================================================================
\  output[i] = median of input[i .. i+window-1]
\
\  For each output position, copies the window into a scratch
\  buffer, sorts it (via SORT-FP16), and picks the middle element.
\  Input must have at least (n + window - 1) valid samples.

VARIABLE _MED-IN
VARIABLE _MED-WIN
VARIABLE _MED-DST
VARIABLE _MED-N
VARIABLE _MED-I
VARIABLE _MED-K
VARIABLE _MED-BUF                     \ scratch buffer for sorting
VARIABLE _MED-HALF                    \ window / 2

: FILT-MEDIAN  ( input window dst n -- )
    _MED-N !
    _MED-DST !
    _MED-WIN !
    _MED-IN !

    \ Allocate scratch: window * 2 bytes
    _MED-WIN @ 2 * HBW-ALLOT _MED-BUF !
    _MED-WIN @ 2/ _MED-HALF !

    0 _MED-I !
    BEGIN _MED-I @ _MED-N @ < WHILE
        \ Copy input[i .. i+window-1] → scratch
        0 _MED-K !
        BEGIN _MED-K @ _MED-WIN @ < WHILE
            _MED-IN @ _MED-I @ _MED-K @ + 2 * + W@
            _MED-BUF @ _MED-K @ 2 * + W!
            _MED-K @ 1+ _MED-K !
        REPEAT

        \ Sort the scratch buffer
        _MED-BUF @ _MED-WIN @ SORT-FP16

        \ Pick median (middle element for odd window, lower-middle for even)
        _MED-BUF @ _MED-HALF @ 2 * + W@
        _MED-DST @ _MED-I @ 2 * + W!

        _MED-I @ 1+ _MED-I !
    REPEAT ;

\ =====================================================================
\  _FILT-SINC — Compute sinc(x) = sin(πx) / (πx), or 1.0 if x≈0
\ =====================================================================
\  x is FP16.  Returns FP16.

VARIABLE _SINC-X
VARIABLE _SINC-PIX

: _FILT-SINC  ( x -- sinc )
    _SINC-X !
    \ Check if |x| ≈ 0 (exactly zero bit pattern)
    _SINC-X @ FP16-ABS _FILT-ZERO = IF
        _FILT-ONE EXIT
    THEN
    \ pi * x
    TRIG-PI _SINC-X @ FP16-MUL _SINC-PIX !
    \ sin(pi*x) / (pi*x)
    _SINC-PIX @ TRIG-SIN
    _SINC-PIX @ FP16-DIV ;

\ =====================================================================
\  _FILT-HAMMING — Hamming window value at position k of width M
\ =====================================================================
\  w(k) = 0.54 - 0.46 * cos(2π * k / M)
\  k and M are integers.

VARIABLE _HAM-K
VARIABLE _HAM-M

: _FILT-HAMMING  ( k M -- w )
    _HAM-M !
    _HAM-K !
    \ 2π * k / M
    TRIG-2PI _HAM-K @ INT>FP16 FP16-MUL
    _HAM-M @ INT>FP16 FP16-DIV         ( angle )
    TRIG-COS                            ( cos_val )
    _FILT-HAMM-B SWAP FP16-MUL         ( 0.46*cos )
    _FILT-HAMM-A SWAP FP16-SUB ;       ( 0.54 - 0.46*cos )

\ =====================================================================
\  _FILT-DESIGN-LP — Design a low-pass windowed-sinc kernel
\ =====================================================================
\  Computes n-taps coefficients for a low-pass filter with normalised
\  cutoff frequency fc (0.0 = DC, 1.0 = Nyquist).
\  Stores into coeff[0..ntaps-1].  ntaps should be odd.
\
\  h(k) = 2*fc * sinc(2*fc*(k - M/2))  *  hamming(k, M)
\  where M = ntaps - 1.
\
\  After windowing, the kernel is normalised so that its sum = 1.

VARIABLE _DLP-CO                      \ coefficient output buffer
VARIABLE _DLP-TAPS                    \ number of taps
VARIABLE _DLP-FC                      \ normalised cutoff (FP16)
VARIABLE _DLP-M                       \ M = ntaps - 1
VARIABLE _DLP-K                       \ loop index
VARIABLE _DLP-SUM                     \ sum for normalisation
VARIABLE _DLP-2FC                     \ 2*fc
VARIABLE _DLP-VAL                     \ temp value

: _FILT-DESIGN-LP  ( coeff ntaps fc -- )
    _DLP-FC !
    _DLP-TAPS !
    _DLP-CO !

    _DLP-TAPS @ 1- _DLP-M !
    _FILT-TWO _DLP-FC @ FP16-MUL _DLP-2FC !

    _FILT-ZERO _DLP-SUM !

    0 _DLP-K !
    BEGIN _DLP-K @ _DLP-TAPS @ < WHILE
        \ Compute k - M/2  (as FP16)
        _DLP-K @ INT>FP16
        _DLP-M @ INT>FP16 _FILT-TWO FP16-DIV
        FP16-SUB                          ( k-M/2 , FP16 )

        \ h = 2*fc * sinc(2*fc * (k - M/2))
        _DLP-2FC @ FP16-MUL              ( 2*fc*(k-M/2) )
        _FILT-SINC                        ( sinc_val )
        _DLP-2FC @ FP16-MUL              ( 2*fc*sinc )

        \ Apply Hamming window
        _DLP-K @ _DLP-M @ _FILT-HAMMING  ( window_val )
        FP16-MUL                          ( h*w )
        _DLP-VAL !

        \ Store and accumulate
        _DLP-VAL @ _DLP-CO @ _DLP-K @ 2 * + W!
        _DLP-SUM @ _DLP-VAL @ FP16-ADD _DLP-SUM !

        _DLP-K @ 1+ _DLP-K !
    REPEAT

    \ Normalise: coeff[k] /= sum
    _DLP-SUM @ FP16-ABS _FILT-ZERO = IF EXIT THEN   \ guard against zero sum

    0 _DLP-K !
    BEGIN _DLP-K @ _DLP-TAPS @ < WHILE
        _DLP-CO @ _DLP-K @ 2 * +         ( addr )
        DUP W@                            ( addr val )
        _DLP-SUM @ FP16-DIV              ( addr val/sum )
        SWAP W!
        _DLP-K @ 1+ _DLP-K !
    REPEAT ;

\ =====================================================================
\  FILT-LOWPASS — Simple low-pass filter via windowed-sinc
\ =====================================================================
\  cutoff is normalised frequency in FP16 (0.0 = DC, 1.0 = Nyquist).
\  Uses a 15-tap windowed-sinc kernel.  Input must have at least
\  (n + 14) valid samples.

VARIABLE _LP-IN
VARIABLE _LP-CUT
VARIABLE _LP-DST
VARIABLE _LP-N
VARIABLE _LP-KERN                     \ allocated kernel buffer

15 CONSTANT _FILT-LP-TAPS             \ default low-pass tap count

: FILT-LOWPASS  ( input cutoff dst n -- )
    _LP-N !
    _LP-DST !
    _LP-CUT !
    _LP-IN !

    \ Allocate kernel
    _FILT-LP-TAPS 2 * HBW-ALLOT _LP-KERN !

    \ Design low-pass kernel
    _LP-KERN @ _FILT-LP-TAPS _LP-CUT @ _FILT-DESIGN-LP

    \ Apply as FIR
    _LP-IN @ _LP-KERN @ _FILT-LP-TAPS _LP-DST @ _LP-N @ FILT-FIR ;

\ =====================================================================
\  FILT-HIGHPASS — Simple high-pass filter (spectral inversion)
\ =====================================================================
\  Designs a low-pass kernel, then applies spectral inversion:
\    hp[k] = -lp[k]              for k ≠ centre
\    hp[centre] = 1.0 - lp[centre]
\  This turns the low-pass into a high-pass.

VARIABLE _HP-IN
VARIABLE _HP-CUT
VARIABLE _HP-DST
VARIABLE _HP-N
VARIABLE _HP-KERN
VARIABLE _HP-K
VARIABLE _HP-CENTRE

: FILT-HIGHPASS  ( input cutoff dst n -- )
    _HP-N !
    _HP-DST !
    _HP-CUT !
    _HP-IN !

    \ Allocate kernel
    _FILT-LP-TAPS 2 * HBW-ALLOT _HP-KERN !

    \ Design low-pass kernel first
    _HP-KERN @ _FILT-LP-TAPS _HP-CUT @ _FILT-DESIGN-LP

    \ Spectral inversion: negate all, then add 1.0 to centre tap
    _FILT-LP-TAPS 2/ _HP-CENTRE !

    0 _HP-K !
    BEGIN _HP-K @ _FILT-LP-TAPS < WHILE
        _HP-KERN @ _HP-K @ 2 * +         ( addr )
        DUP W@ FP16-NEG SWAP W!          ( negate )
        _HP-K @ 1+ _HP-K !
    REPEAT

    \ Centre tap += 1.0
    _HP-KERN @ _HP-CENTRE @ 2 * +        ( centre-addr )
    DUP W@ _FILT-ONE FP16-ADD SWAP W!

    \ Apply as FIR
    _HP-IN @ _HP-KERN @ _FILT-LP-TAPS _HP-DST @ _HP-N @ FILT-FIR ;

