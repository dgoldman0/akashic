\ audio/analysis/metrics.f — PCM buffer analysis metrics
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Seven diagnostic metrics for inspecting PCM buffers produced by
\ synthesis engines.  All operate on FP16-valued PCM buffers (the
\ native format of every Akashic syn/ engine).
\
\ Words:
\   PCM-PEAK            ( buf -- peak-fp16 frame )
\   PCM-ZERO-CROSSINGS  ( buf -- count )
\   PCM-RMS             ( buf -- rms-fp16 )
\   PCM-DC-OFFSET       ( buf -- mean-fp16 )
\   PCM-CLIP-COUNT      ( buf -- count )
\   PCM-CREST-FACTOR    ( buf -- cf-fp16 )
\   PCM-ENERGY-REGIONS  ( buf n -- )
\
\ Implementation notes:
\   RMS and DC-OFFSET use FP32 accumulation (via FP16>FP32,
\   FP32-ADD) to avoid FP16 catastrophic cancellation when
\   summing thousands of small values.  Final results are
\   converted back to FP16.
\
\ Prefix: PCM-   (public — extends audio/pcm.f namespace)
\         _PM-   (internals)
\
\ Load with:   REQUIRE audio/analysis/metrics.f

REQUIRE fp16.f
REQUIRE fp16-ext.f
REQUIRE fp32.f
REQUIRE audio/pcm.f

PROVIDED akashic-analysis-metrics

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _PM-BUF
VARIABLE _PM-DPTR
VARIABLE _PM-LEN

\ =====================================================================
\  Internal: setup buffer access
\ =====================================================================
\  ( buf -- )  fills _PM-BUF, _PM-DPTR, _PM-LEN

: _PM-SETUP  ( buf -- )
    DUP _PM-BUF !
    DUP PCM-DATA _PM-DPTR !
    PCM-LEN _PM-LEN ! ;

\ =====================================================================
\  PCM-PEAK — Find maximum absolute sample value and its frame index
\ =====================================================================
\  ( buf -- peak-fp16 frame )
\  Scans every sample, tracks max |value|.  Returns both the peak
\  amplitude (FP16, always positive) and the frame index where it
\  was found.  For a decaying percussive sound, frame should be
\  near 0.  If it's near the end, something is probably wrong.
\
\  Empty buffer returns ( 0 0 ).

VARIABLE _PM-PK-BEST
VARIABLE _PM-PK-FRAME

: PCM-PEAK  ( buf -- peak-fp16 frame )
    _PM-SETUP
    FP16-POS-ZERO _PM-PK-BEST !
    0 _PM-PK-FRAME !

    _PM-LEN @ 0 ?DO
        _PM-DPTR @ I 2* + W@     \ raw FP16 sample
        FP16-ABS                   \ |sample|
        DUP _PM-PK-BEST @ FP16-GT IF
            _PM-PK-BEST !
            I _PM-PK-FRAME !
        ELSE
            DROP
        THEN
    LOOP

    _PM-PK-BEST @ _PM-PK-FRAME @ ;

\ =====================================================================
\  PCM-ZERO-CROSSINGS — Count sign transitions
\ =====================================================================
\  ( buf -- count )
\  Counts the number of times consecutive samples differ in sign.
\  FP16 sign bit is bit 15 (0x8000).  Skips exact-zero samples.
\
\  For a pure sine at frequency f in N frames at rate R:
\    expected crossings ≈ 2 × f × N / R
\
\  count=0 on a non-silent buffer means DC offset or broken oscillator.
\  Very high count relative to expected means noise-dominated.

VARIABLE _PM-ZC-COUNT
VARIABLE _PM-ZC-PREV
VARIABLE _PM-ZC-STARTED

: PCM-ZERO-CROSSINGS  ( buf -- count )
    _PM-SETUP
    0 _PM-ZC-COUNT !
    0 _PM-ZC-STARTED !

    _PM-LEN @ 0 ?DO
        _PM-DPTR @ I 2* + W@    \ raw FP16 sample
        DUP 0x7FFF AND 0= IF    \ exact ±zero?
            DROP                  \ skip zeros
        ELSE
            0x8000 AND            \ extract sign bit
            _PM-ZC-STARTED @ 0= IF
                \ First non-zero sample: set baseline sign
                _PM-ZC-PREV !
                1 _PM-ZC-STARTED !
            ELSE
                DUP _PM-ZC-PREV @ <> IF
                    _PM-ZC-COUNT @ 1+ _PM-ZC-COUNT !
                THEN
                _PM-ZC-PREV !
            THEN
        THEN
    LOOP

    _PM-ZC-COUNT @ ;

\ =====================================================================
\  PCM-RMS — Root mean square energy
\ =====================================================================
\  ( buf -- rms-fp16 )
\  Computes sqrt( mean( sample² ) ) over all frames.
\
\  Uses FP32 accumulation: for each sample, convert FP16→FP32,
\  square, add to running FP32 sum.  Then divide by N, sqrt,
\  and convert back to FP16.

VARIABLE _PM-RMS-SUM

: PCM-RMS  ( buf -- rms-fp16 )
    _PM-SETUP

    _PM-LEN @ 0= IF FP16-POS-ZERO EXIT THEN

    0 _PM-RMS-SUM !       \ FP32 zero = integer 0

    _PM-LEN @ 0 ?DO
        _PM-DPTR @ I 2* + W@     \ FP16 sample
        FP16>FP32                  \ → FP32
        DUP FP32-MUL              \ sample²
        _PM-RMS-SUM @ FP32-ADD    \ sum += sample²
        _PM-RMS-SUM !
    LOOP

    \ mean = sum / N
    _PM-RMS-SUM @
    _PM-LEN @ INT>FP16 FP16>FP32
    FP32-DIV

    \ sqrt → FP16
    FP32-SQRT
    FP32>FP16 ;

\ =====================================================================
\  PCM-DC-OFFSET — Mean sample value (DC bias)
\ =====================================================================
\  ( buf -- mean-fp16 )
\  Computes the arithmetic mean of all samples.  For properly
\  centered audio this should be very close to 0.0.  A significant
\  nonzero value indicates a DC bias bug in the synthesis engine.

VARIABLE _PM-DC-SUM

: PCM-DC-OFFSET  ( buf -- mean-fp16 )
    _PM-SETUP

    _PM-LEN @ 0= IF FP16-POS-ZERO EXIT THEN

    0 _PM-DC-SUM !

    _PM-LEN @ 0 ?DO
        _PM-DPTR @ I 2* + W@     \ FP16 sample
        FP16>FP32
        _PM-DC-SUM @ FP32-ADD
        _PM-DC-SUM !
    LOOP

    _PM-DC-SUM @
    _PM-LEN @ INT>FP16 FP16>FP32
    FP32-DIV
    FP32>FP16 ;

\ =====================================================================
\  PCM-CLIP-COUNT — Count samples at or above full scale
\ =====================================================================
\  ( buf -- count )
\  Counts samples with |value| >= 1.0 (FP16 0x3C00).
\  Clearing the sign bit and comparing >= 0x3C00 catches all values
\  with magnitude >= 1.0 including Inf/NaN (also bad).

VARIABLE _PM-CL-COUNT

: PCM-CLIP-COUNT  ( buf -- count )
    _PM-SETUP
    0 _PM-CL-COUNT !

    _PM-LEN @ 0 ?DO
        _PM-DPTR @ I 2* + W@
        0x7FFF AND                 \ |value| bit pattern
        0x3C00 >= IF
            _PM-CL-COUNT @ 1+ _PM-CL-COUNT !
        THEN
    LOOP

    _PM-CL-COUNT @ ;

\ =====================================================================
\  PCM-CREST-FACTOR — Peak / RMS ratio
\ =====================================================================
\  ( buf -- cf-fp16 )
\  Crest factor = peak / RMS.
\    Sine wave: √2 ≈ 1.414
\    Square wave: 1.0
\    Very high (>10): sparse peaks in mostly quiet audio
\  Returns 0 if RMS is zero (silent buffer).

VARIABLE _PM-CF-PK
VARIABLE _PM-CF-RMS

: PCM-CREST-FACTOR  ( buf -- cf-fp16 )
    DUP PCM-RMS _PM-CF-RMS !
    PCM-PEAK DROP _PM-CF-PK !   \ drop frame index, keep peak

    _PM-CF-RMS @ FP16-POS-ZERO FP16-GT IF
        _PM-CF-PK @ _PM-CF-RMS @ FP16-DIV
    ELSE
        FP16-POS-ZERO
    THEN ;

\ =====================================================================
\  PCM-ENERGY-REGIONS — Per-region energy profile
\ =====================================================================
\  ( buf n -- )
\  Splits the buffer into n equal regions and prints one line per
\  region to UART:
\
\    R0: rms=<int> pk=<int> zc=<int>
\    R1: rms=<int> pk=<int> zc=<int>
\    ...
\
\  rms and pk are FP16 bit patterns printed as integers (for easy
\  parsing by test harness).  zc is zero-crossing count.
\
\  Decay profile:
\    Percussive strike → R0 highest, declining
\    Sustained pad     → roughly equal across regions
\    Silent buffer     → all rms=0
\
\  Creates a temporary 80-byte PCM descriptor (no sample data
\  allocation) that points into successive slices of the source.

VARIABLE _PM-ER-N
VARIABLE _PM-ER-RLEN
VARIABLE _PM-ER-SUB
VARIABLE _PM-ER-DBASE

: PCM-ENERGY-REGIONS  ( buf n -- )
    _PM-ER-N !
    _PM-SETUP
    _PM-DPTR @ _PM-ER-DBASE !
    _PM-LEN @ _PM-ER-N @ / _PM-ER-RLEN !

    \ Allocate a raw descriptor (80 bytes) — just a view, no data alloc
    80 ALLOCATE DROP _PM-ER-SUB !
    _PM-BUF @ PCM-RATE  _PM-ER-SUB @ 16 + !    \ P.RATE
    16                   _PM-ER-SUB @ 24 + !    \ P.BITS
    1                    _PM-ER-SUB @ 32 + !    \ P.CHANS

    _PM-ER-N @ 0 ?DO
        \ Point descriptor at region i's data
        _PM-ER-DBASE @ I _PM-ER-RLEN @ * 2* +
        _PM-ER-SUB @ !                          \ P.DATA (+0)
        _PM-ER-RLEN @ _PM-ER-SUB @ 8 + !       \ P.LEN  (+8)

        ." R" I . ." : rms="
        _PM-ER-SUB @ PCM-RMS .
        ."  pk="
        _PM-ER-SUB @ PCM-PEAK DROP .
        ."  zc="
        _PM-ER-SUB @ PCM-ZERO-CROSSINGS .
        CR
    LOOP

    _PM-ER-SUB @ FREE ;
