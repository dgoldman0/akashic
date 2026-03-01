\ seq.f — Step sequencer (pattern-based, sample-accurate)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ A pattern-based step sequencer that drives any sound source via a
\ callback execution token.  Tempo-locked to sample-accurate tick
\ boundaries.
\
\ Architecture:
\   - Pattern: array of (note, velocity, gate-length) triples
\     stored as cells.  Up to 64 steps.
\   - Sequencer: BPM, tick counter, step position, callback XT.
\   - SEQ-TICK advances the sequencer by N frames.  When a step
\     boundary is crossed, the callback fires with
\     ( note velocity gate -- ).
\   - Swing: even-numbered steps can be delayed by a fraction of
\     half a tick, producing a shuffle/triplet feel.
\
\ Memory: sequencer descriptor (80 bytes) + pattern (24 bytes/step).
\
\ Prefix: SEQ-   (public API)
\         _SQ-   (internals)
\
\ Load with:   REQUIRE audio/seq.f
\
\ === Public API ===
\   SEQ-CREATE     ( bpm steps rate -- seq )
\   SEQ-FREE       ( seq -- )
\   SEQ-STEP!      ( note vel gate step# seq -- )
\   SEQ-STEP@      ( step# seq -- note vel gate )
\   SEQ-START      ( seq -- )
\   SEQ-STOP       ( seq -- )
\   SEQ-TICK       ( frames seq -- fired? )
\   SEQ-BPM!       ( bpm seq -- )
\   SEQ-SWING!     ( swing seq -- )
\   SEQ-CALLBACK!  ( xt seq -- )
\   SEQ-POSITION   ( seq -- step# )
\   SEQ-RUNNING?   ( seq -- flag )
\   SEQ-LOOP!      ( flag seq -- )

REQUIRE fp16-ext.f

PROVIDED akashic-audio-seq

\ =====================================================================
\  Sequencer descriptor layout  (10 cells = 80 bytes)
\ =====================================================================
\
\  +0   bpm          Tempo in beats per minute (integer)
\  +8   steps        Number of steps in the pattern (integer)
\  +16  rate         Sample rate in Hz (integer)
\  +24  tick-frames  Frames per step (computed from BPM + rate)
\  +32  position     Current step index (0-based)
\  +40  tick-count   Sub-step frame counter (counts up to tick-frames)
\  +48  callback     XT called with ( note vel gate -- )
\  +56  running      0 = stopped, 1 = playing
\  +64  loop         0 = one-shot, 1 = loop
\  +72  swing        Swing amount (FP16, 0.0–1.0; 0=straight)

80 CONSTANT _SQ-DESC-SIZE

: SQ.BPM       ( s -- addr )  ;
: SQ.STEPS     ( s -- addr )  8 + ;
: SQ.RATE      ( s -- addr )  16 + ;
: SQ.TICKF     ( s -- addr )  24 + ;
: SQ.POS       ( s -- addr )  32 + ;
: SQ.TCNT      ( s -- addr )  40 + ;
: SQ.CB        ( s -- addr )  48 + ;
: SQ.RUN       ( s -- addr )  56 + ;
: SQ.LOOP      ( s -- addr )  64 + ;
: SQ.SWING     ( s -- addr )  72 + ;

\ =====================================================================
\  Pattern step layout  (3 cells = 24 bytes per step)
\ =====================================================================
\
\  +0   note       MIDI note number (0–127) or 0 = rest
\  +8   velocity   0–127
\  +16  gate       Gate length in ticks (1 = staccato, steps = legato)
\
\  Pattern array lives immediately after descriptor.
\  Address of step N = desc + 80 + N × 24.

24 CONSTANT _SQ-STEP-SIZE

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _SQ-TMP     \ descriptor pointer
VARIABLE _SQ-VAL     \ temp value
VARIABLE _SQ-REM     \ remaining frames to process
VARIABLE _SQ-FIRE    \ flag: did we fire a callback?
VARIABLE _SQ-EFF     \ effective tick-frames for current step (swing)

\ =====================================================================
\  Internal: compute address of step entry
\ =====================================================================
\  ( step# seq -- addr )

: _SQ-STEP-ADDR  ( step# seq -- addr )
    _SQ-DESC-SIZE +                \ base of pattern array
    SWAP _SQ-STEP-SIZE * + ;

\ =====================================================================
\  Internal: compute tick-frames from BPM and rate
\ =====================================================================
\  tick-frames = rate × 60 / (bpm × 4)
\  (one "tick" = one 16th note)

: _SQ-COMPUTE-TICKF  ( seq -- )
    _SQ-TMP !
    _SQ-TMP @ SQ.RATE @ 60 *
    _SQ-TMP @ SQ.BPM @ 4 * /
    1 MAX                          \ minimum 1 frame per tick
    _SQ-TMP @ SQ.TICKF ! ;

\ =====================================================================
\  SEQ-CREATE — Create sequencer with pattern
\ =====================================================================
\  ( bpm steps rate -- seq )

VARIABLE _SQ-BPM
VARIABLE _SQ-STEPS
VARIABLE _SQ-RATE

: SEQ-CREATE  ( bpm steps rate -- seq )
    _SQ-RATE !
    _SQ-STEPS !
    _SQ-BPM !

    \ Validate
    _SQ-STEPS @ 1 < ABORT" SEQ-CREATE: steps must be >= 1"
    _SQ-STEPS @ 64 > ABORT" SEQ-CREATE: steps must be <= 64"

    \ Allocate descriptor + pattern array
    _SQ-DESC-SIZE _SQ-STEPS @ _SQ-STEP-SIZE * +
    ALLOCATE
    0<> ABORT" SEQ-CREATE: alloc failed"
    _SQ-TMP !

    \ Fill descriptor
    _SQ-BPM @   _SQ-TMP @ SQ.BPM   !
    _SQ-STEPS @ _SQ-TMP @ SQ.STEPS !
    _SQ-RATE @  _SQ-TMP @ SQ.RATE  !
    0           _SQ-TMP @ SQ.POS   !
    0           _SQ-TMP @ SQ.TCNT  !
    0           _SQ-TMP @ SQ.CB    !
    0           _SQ-TMP @ SQ.RUN   !
    1           _SQ-TMP @ SQ.LOOP  !  \ default: looping
    FP16-POS-ZERO _SQ-TMP @ SQ.SWING !

    \ Compute tick-frames
    _SQ-TMP @ _SQ-COMPUTE-TICKF

    \ Zero the pattern data
    _SQ-TMP @ _SQ-DESC-SIZE +
    _SQ-STEPS @ _SQ-STEP-SIZE *
    0 FILL

    _SQ-TMP @ ;

\ =====================================================================
\  SEQ-FREE — Free sequencer
\ =====================================================================

: SEQ-FREE  ( seq -- )  FREE ;

\ =====================================================================
\  SEQ-STEP! — Set step data
\ =====================================================================
\  ( note vel gate step# seq -- )

\ Scratch for step-set
VARIABLE _SQ-SNOTE
VARIABLE _SQ-SVEL
VARIABLE _SQ-SGATE
VARIABLE _SQ-SIDX

: SEQ-STEP!  ( note vel gate step# seq -- )
    _SQ-TMP !
    _SQ-SIDX !
    _SQ-SGATE !
    _SQ-SVEL !
    _SQ-SNOTE !

    _SQ-SIDX @ _SQ-TMP @ _SQ-STEP-ADDR
    _SQ-VAL !

    _SQ-SNOTE @ _SQ-VAL @       !     \ +0 note
    _SQ-SVEL @  _SQ-VAL @ 8 +   !     \ +8 velocity
    _SQ-SGATE @ _SQ-VAL @ 16 +  ! ;   \ +16 gate

\ =====================================================================
\  SEQ-STEP@ — Read step data
\ =====================================================================
\  ( step# seq -- note vel gate )

: SEQ-STEP@  ( step# seq -- note vel gate )
    _SQ-STEP-ADDR
    _SQ-VAL !
    _SQ-VAL @       @             \ note
    _SQ-VAL @ 8 +   @             \ vel
    _SQ-VAL @ 16 +  @ ;           \ gate

\ =====================================================================
\  SEQ-START / SEQ-STOP
\ =====================================================================

: SEQ-START  ( seq -- )
    DUP SQ.POS  0 SWAP !          \ reset position
    DUP SQ.TCNT 0 SWAP !          \ reset tick counter
    SQ.RUN 1 SWAP ! ;

: SEQ-STOP  ( seq -- )
    SQ.RUN 0 SWAP ! ;

\ =====================================================================
\  SEQ-BPM! — Change tempo
\ =====================================================================

: SEQ-BPM!  ( bpm seq -- )
    _SQ-TMP !
    _SQ-TMP @ SQ.BPM !
    _SQ-TMP @ _SQ-COMPUTE-TICKF ;

\ =====================================================================
\  SEQ-SWING! — Set swing amount (FP16, 0.0 to 1.0)
\ =====================================================================

: SEQ-SWING!  ( swing seq -- )  SQ.SWING ! ;

\ =====================================================================
\  SEQ-CALLBACK! — Set step-trigger callback XT
\ =====================================================================

: SEQ-CALLBACK!  ( xt seq -- )  SQ.CB ! ;

\ =====================================================================
\  SEQ-POSITION — Current step index
\ =====================================================================

: SEQ-POSITION  ( seq -- step# )  SQ.POS @ ;

\ =====================================================================
\  SEQ-RUNNING? — Is sequencer playing?
\ =====================================================================

: SEQ-RUNNING?  ( seq -- flag )  SQ.RUN @ 0<> ;

\ =====================================================================
\  SEQ-LOOP! — Set loop mode
\ =====================================================================

: SEQ-LOOP!  ( flag seq -- )  SQ.LOOP ! ;

\ =====================================================================
\  Internal: compute effective tick-frames for current step
\ =====================================================================
\  Swing delays even-numbered steps by (swing × tick-frames / 2).

: _SQ-EFF-TICKF  ( seq -- frames )
    _SQ-TMP !
    _SQ-TMP @ SQ.TICKF @          \ base tick-frames

    \ Check if current step is even (swing applies)
    _SQ-TMP @ SQ.POS @ 2 MOD 0= IF
        \ Even step — add swing offset
        \ offset = swing × (tick-frames / 2)
        DUP 2 /                    ( tick-frames half )
        INT>FP16
        _SQ-TMP @ SQ.SWING @ FP16-MUL
        FP16>INT                   ( tick-frames offset )
        +                          ( adjusted-tick-frames )
    THEN ;

\ =====================================================================
\  Internal: fire callback for current step
\ =====================================================================

: _SQ-FIRE-STEP  ( seq -- )
    _SQ-TMP !
    _SQ-TMP @ SQ.CB @ 0= IF EXIT THEN  \ no callback set

    \ Get step address
    _SQ-TMP @ SQ.POS @
    _SQ-TMP @ _SQ-STEP-ADDR
    _SQ-VAL !

    \ Read note — if 0, it's a rest
    _SQ-VAL @       @ DUP 0= IF DROP EXIT THEN
    _SQ-VAL @ 8 +   @             \ velocity
    _SQ-VAL @ 16 +  @             \ gate

    \ Call: ( note vel gate -- )
    _SQ-TMP @ SQ.CB @ EXECUTE ;

\ =====================================================================
\  SEQ-TICK — Advance sequencer by N frames
\ =====================================================================
\  ( frames seq -- fired? )
\  Returns -1 if a step fired during this tick, 0 otherwise.

: SEQ-TICK  ( frames seq -- fired? )
    _SQ-TMP !
    _SQ-REM !

    \ Not running? Do nothing.
    _SQ-TMP @ SQ.RUN @ 0= IF 0 EXIT THEN

    0 _SQ-FIRE !

    BEGIN
        _SQ-REM @ 0>
    WHILE
        \ How many frames until next step boundary?
        _SQ-TMP @ _SQ-EFF-TICKF
        _SQ-TMP @ SQ.TCNT @ -         ( frames-until-next )

        _SQ-REM @ OVER < IF
            \ Won't reach boundary — just accumulate
            DROP
            _SQ-REM @ _SQ-TMP @ SQ.TCNT +!
            0 _SQ-REM !
        ELSE
            \ Cross boundary — consume those frames, fire step
            _SQ-REM @ SWAP -           ( remaining-after )
            _SQ-REM !
            0 _SQ-TMP @ SQ.TCNT !     \ reset tick counter

            \ Fire the callback for current step
            _SQ-TMP @ _SQ-FIRE-STEP
            -1 _SQ-FIRE !

            \ Advance position
            _SQ-TMP @ SQ.POS @ 1+
            DUP _SQ-TMP @ SQ.STEPS @ >= IF
                \ Past last step
                _SQ-TMP @ SQ.LOOP @ IF
                    DROP 0             \ wrap to 0
                ELSE
                    DROP
                    _SQ-TMP @ SEQ-STOP
                    0 _SQ-REM !        \ stop processing
                    _SQ-FIRE @ EXIT    \ early exit
                THEN
            THEN
            _SQ-TMP @ SQ.POS !
        THEN
    REPEAT

    _SQ-FIRE @ ;
