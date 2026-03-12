\ audio/analysis/envelope.f — Temporal envelope analysis for PCM buffers
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Analyses the loudness shape of a sound over time: how fast it
\ attacks, how long it decays, whether it sustains, and what the
\ overall envelope curve looks like.
\
\ Words:
\   PCM-ATTACK-TIME     ( buf -- frames )
\   PCM-DECAY-TIME      ( buf thresh-fp16 -- frames )
\   PCM-SUSTAIN-LEVEL   ( buf -- ratio-fp16 )
\   PCM-SILENCE-RATIO   ( buf thresh-fp16 -- ratio-fp16 )
\   PCM-ENVELOPE-DUMP   ( buf n-points -- )
\   PCM-ENVELOPE-CLASS  ( buf -- class )
\
\ Implementation: sliding RMS window of 64 samples (8ms at 8kHz).
\ Walk the buffer once, computing windowed RMS at each position.
\
\ Prefix: PCM-    (public)
\         _EN-    (internals)
\
\ Load with:   REQUIRE audio/analysis/envelope.f

REQUIRE fp16.f
REQUIRE fp16-ext.f
REQUIRE fp32.f
REQUIRE audio/pcm.f

PROVIDED akashic-analysis-envelope

\ =====================================================================
\  Constants
\ =====================================================================

64 CONSTANT _EN-WINSZ        \ Window size in samples (8ms at 8kHz)

\ Envelope class codes
0 CONSTANT ENV-PERCUSSIVE    \ fast attack, no sustain
1 CONSTANT ENV-SUSTAINED     \ slow attack or flat body
2 CONSTANT ENV-SWELL         \ energy increases over time
3 CONSTANT ENV-SILENCE       \ effectively silent
4 CONSTANT ENV-OTHER         \ none of the above

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _EN-BUF
VARIABLE _EN-DPTR
VARIABLE _EN-LEN
VARIABLE _EN-RATE

\ Windowed RMS computation
VARIABLE _EN-NWIN            \ number of windows
VARIABLE _EN-PKRMS           \ peak windowed RMS (FP16)
VARIABLE _EN-PKIDX           \ window index of peak RMS

\ =====================================================================
\  Internal: setup buffer pointers
\ =====================================================================

: _EN-SETUP  ( buf -- )
    DUP _EN-BUF !
    DUP PCM-DATA _EN-DPTR !
    DUP PCM-LEN  _EN-LEN !
    PCM-RATE _EN-RATE !
    _EN-LEN @ _EN-WINSZ / _EN-NWIN ! ;

\ =====================================================================
\  Internal: compute RMS for a single window starting at frame `start`
\ =====================================================================
\  ( start -- rms-fp16 )
\  Uses FP32 accumulation.  Window size = min(WINSZ, remaining).

VARIABLE _EN-WRMS-SUM

: _EN-WIN-RMS  ( start -- rms-fp16 )
    _EN-WRMS-SUM @ DROP                 \ touch (just for clarity)
    FP32-ZERO _EN-WRMS-SUM !

    DUP _EN-WINSZ +                      ( start end )
    _EN-LEN @ MIN                        ( start end' )
    OVER -                               ( start count )
    DUP 0= IF 2DROP FP16-POS-ZERO EXIT THEN

    SWAP                                 ( count start )
    OVER 0 DO                            ( count start )
        DUP I + 2* _EN-DPTR @ + W@       \ sample FP16
        FP16>FP32
        DUP FP32-MUL                      \ sample^2
        _EN-WRMS-SUM @ FP32-ADD _EN-WRMS-SUM !
    LOOP
    DROP                                  ( count )

    \ rms = sqrt(sum / count)
    _EN-WRMS-SUM @
    SWAP INT>FP16 FP16>FP32 FP32-DIV
    FP32-SQRT FP32>FP16 ;

\ =====================================================================
\  Internal: find peak windowed RMS and its window index
\ =====================================================================
\  Walks all windows, stores peak in _EN-PKRMS, index in _EN-PKIDX.

: _EN-FIND-PEAK  ( -- )
    FP16-POS-ZERO _EN-PKRMS !
    0 _EN-PKIDX !

    _EN-NWIN @ 0 ?DO
        I _EN-WINSZ * _EN-WIN-RMS       \ rms for window i
        DUP _EN-PKRMS @ FP16-GT IF
            _EN-PKRMS !
            I _EN-PKIDX !
        ELSE
            DROP
        THEN
    LOOP ;

\ =====================================================================
\  PCM-ATTACK-TIME — frames from start to peak windowed RMS
\ =====================================================================
\  ( buf -- frames )
\  A snare should be <40 frames (5ms at 8kHz).
\  A pad might be 1600 (200ms).
\  Returns the frame index of the start of the peak window.

: PCM-ATTACK-TIME  ( buf -- frames )
    _EN-SETUP
    _EN-FIND-PEAK
    _EN-PKIDX @ _EN-WINSZ * ;

\ =====================================================================
\  PCM-DECAY-TIME — frames from peak RMS to threshold crossing
\ =====================================================================
\  ( buf thresh-fp16 -- frames )
\  thresh-fp16 is a fraction of peak: e.g. FP16 0.1 means "10% of
\  peak RMS."  Returns the number of frames from peak window to the
\  first window whose RMS drops below thresh × peak_rms.
\
\  If the signal never drops below threshold, returns remaining
\  buffer length.

VARIABLE _EN-DT-THRESH

: PCM-DECAY-TIME  ( buf thresh-fp16 -- frames )
    _EN-DT-THRESH !
    _EN-SETUP
    _EN-FIND-PEAK

    \ Compute absolute threshold = peak_rms × thresh_fraction
    _EN-PKRMS @ _EN-DT-THRESH @ FP16-MUL  ( abs-thresh )

    \ Walk windows from peak+1 to end
    _EN-NWIN @ _EN-PKIDX @ 1+ ?DO
        I _EN-WINSZ * _EN-WIN-RMS       \ rms for window i
        OVER FP16-LT IF                  \ rms < threshold?
            DROP                           \ drop threshold
            I _EN-PKIDX @ - _EN-WINSZ *   \ (i - peak_idx) * winsz
            UNLOOP EXIT
        THEN
    LOOP

    \ Never crossed threshold
    DROP
    _EN-LEN @ _EN-PKIDX @ _EN-WINSZ * - ;

\ =====================================================================
\  PCM-SUSTAIN-LEVEL — average RMS in middle 50% / peak RMS
\ =====================================================================
\  ( buf -- ratio-fp16 )
\  Percussive → near 0.0.  Sustained → near 1.0.

VARIABLE _EN-SL-SUM
VARIABLE _EN-SL-COUNT

: PCM-SUSTAIN-LEVEL  ( buf -- ratio-fp16 )
    _EN-SETUP
    _EN-FIND-PEAK

    _EN-PKRMS @ FP16-POS-ZERO FP16-GT 0= IF
        FP16-POS-ZERO EXIT     \ silent buffer
    THEN

    FP32-ZERO _EN-SL-SUM !
    0 _EN-SL-COUNT !

    \ Middle 50%: windows from 25% to 75% of total
    _EN-NWIN @ 4 /             ( q1 )
    _EN-NWIN @ 3 * 4 /        ( q1 q3 )
    SWAP ?DO
        I _EN-WINSZ * _EN-WIN-RMS
        FP16>FP32
        _EN-SL-SUM @ FP32-ADD _EN-SL-SUM !
        _EN-SL-COUNT @ 1+ _EN-SL-COUNT !
    LOOP

    _EN-SL-COUNT @ 0= IF FP16-POS-ZERO EXIT THEN

    \ average_mid_rms = sum / count
    _EN-SL-SUM @
    _EN-SL-COUNT @ INT>FP16 FP16>FP32 FP32-DIV
    FP32>FP16

    \ ratio = average / peak
    _EN-PKRMS @ FP16-DIV ;

\ =====================================================================
\  PCM-SILENCE-RATIO — fraction of buffer duration below threshold
\ =====================================================================
\  ( buf thresh-fp16 -- ratio-fp16 )
\  thresh-fp16 is an absolute RMS level.  E.g. 0x2000 (~0.0156).
\  Returns fraction [0.0, 1.0].  1.0 = all silent.

VARIABLE _EN-SR-THRESH
VARIABLE _EN-SR-COUNT

: PCM-SILENCE-RATIO  ( buf thresh-fp16 -- ratio-fp16 )
    _EN-SR-THRESH !
    _EN-SETUP

    0 _EN-SR-COUNT !

    _EN-NWIN @ 0 ?DO
        I _EN-WINSZ * _EN-WIN-RMS
        _EN-SR-THRESH @ FP16-LT IF
            _EN-SR-COUNT @ 1+ _EN-SR-COUNT !
        THEN
    LOOP

    _EN-SR-COUNT @ INT>FP16
    _EN-NWIN @ INT>FP16 FP16-DIV ;

\ =====================================================================
\  PCM-ENVELOPE-DUMP — print windowed RMS at n equally-spaced points
\ =====================================================================
\  ( buf n-points -- )
\  Prints the envelope as n integer "thousandths" (0-1000).  Each line:
\    E<idx>: <value>
\  where value = (window_rms / peak_rms) × 1000, clamped to [0, 1000].
\
\  This is the "readable loudness curve" that an LLM can parse.

VARIABLE _EN-ED-N
VARIABLE _EN-ED-STEP

: PCM-ENVELOPE-DUMP  ( buf n-points -- )
    _EN-ED-N !
    _EN-SETUP
    _EN-FIND-PEAK

    _EN-PKRMS @ FP16-POS-ZERO FP16-GT 0= IF
        \ Silent buffer — print all zeros
        _EN-ED-N @ 0 ?DO
            ." E" I . ." : 0" CR
        LOOP
        EXIT
    THEN

    \ Step between sample points
    _EN-NWIN @ _EN-ED-N @ /  _EN-ED-STEP !
    _EN-ED-STEP @ 0= IF 1 _EN-ED-STEP ! THEN

    _EN-ED-N @ 0 ?DO
        I _EN-ED-STEP @ * _EN-WINSZ *   ( frame-start )
        DUP _EN-LEN @ _EN-WINSZ - MIN   \ don't exceed
        _EN-WIN-RMS                       ( rms-fp16 )

        \ Normalize to peak and scale to 0-1000
        _EN-PKRMS @ FP16-DIV             ( ratio )
        1000 INT>FP16 FP16-MUL           ( ratio*1000 )
        FP16>INT                          ( integer 0-1000 )
        0 MAX 1000 MIN                    ( clamped )

        ." E" I . ." : " . CR
    LOOP ;

\ =====================================================================
\  PCM-ENVELOPE-CLASS — classify the envelope shape
\ =====================================================================
\  ( buf -- class )
\  Returns one of:
\    0 = ENV-PERCUSSIVE  (attack < 10% of duration, sustain < 0.3)
\    1 = ENV-SUSTAINED   (sustain >= 0.3)
\    2 = ENV-SWELL       (peak is in last 33% of buffer)
\    3 = ENV-SILENCE     (peak RMS < 0.01)
\    4 = ENV-OTHER
\
\  This is a quick heuristic, not a precise classifier.

0x2000 CONSTANT _EN-SILENCE-THRESH   \ ~0.015 FP16

: PCM-ENVELOPE-CLASS  ( buf -- class )
    DUP _EN-SETUP
    _EN-FIND-PEAK

    \ Check silence
    _EN-PKRMS @ _EN-SILENCE-THRESH FP16-LT IF
        DROP ENV-SILENCE EXIT
    THEN

    \ Check swell: peak in last third
    _EN-PKIDX @ _EN-NWIN @ 2 * 3 / >= IF
        DROP ENV-SWELL EXIT
    THEN

    \ Compute sustain level
    PCM-SUSTAIN-LEVEL                     ( sustain-ratio )

    \ Percussive: peak in first 10% AND sustain < 0.7
    \ (A constant buffer has sustain ≈ 1.0; a decay has ≈ 0.5)
    _EN-PKIDX @ _EN-NWIN @ 10 / <= IF
        DUP 0x399A FP16-LT IF             \ 0x399A ≈ 0.7
            DROP ENV-PERCUSSIVE EXIT
        THEN
    THEN

    \ Sustained if sustain >= 0.3
    DUP 0x34CD FP16-GE IF                 \ 0x34CD ≈ 0.3
        DROP ENV-SUSTAINED EXIT
    THEN
    DROP

    ENV-OTHER ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _aenvl-guard

' PCM-ATTACK-TIME CONSTANT _pcm-attack-time-xt
' PCM-DECAY-TIME  CONSTANT _pcm-decay-time-xt
' PCM-SUSTAIN-LEVEL CONSTANT _pcm-sustain-level-xt
' PCM-SILENCE-RATIO CONSTANT _pcm-silence-ratio-xt
' PCM-ENVELOPE-DUMP CONSTANT _pcm-envelope-dump-xt
' PCM-ENVELOPE-CLASS CONSTANT _pcm-envelope-class-xt

: PCM-ATTACK-TIME _pcm-attack-time-xt _aenvl-guard WITH-GUARD ;
: PCM-DECAY-TIME  _pcm-decay-time-xt _aenvl-guard WITH-GUARD ;
: PCM-SUSTAIN-LEVEL _pcm-sustain-level-xt _aenvl-guard WITH-GUARD ;
: PCM-SILENCE-RATIO _pcm-silence-ratio-xt _aenvl-guard WITH-GUARD ;
: PCM-ENVELOPE-DUMP _pcm-envelope-dump-xt _aenvl-guard WITH-GUARD ;
: PCM-ENVELOPE-CLASS _pcm-envelope-class-xt _aenvl-guard WITH-GUARD ;
[THEN] [THEN]
