\ fm.f — FM synthesis (2-operator and 4-operator)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Frequency modulation (technically phase modulation) synthesis.
\ Each operator is a sine oscillator with its own ADSR envelope,
\ frequency ratio, output level, and modulation index.
\
\ 2-op mode: op1(modulator) → op2(carrier) → output
\ 4-op mode: configurable algorithms (serial, parallel, etc.)
\
\ FM rendering is sample-by-sample: for each sample, compute
\ operator outputs in dependency order, with modulators feeding
\ phase offsets to carriers.
\
\ Memory: FM voice descriptor + per-operator sub-descriptors.
\
\ Prefix: FM-     (public API)
\         _FM-    (internals)
\
\ Load with:   REQUIRE audio/fm.f
\
\ === Public API ===
\   FM-CREATE     ( n-ops algorithm rate frames -- voice )
\   FM-FREE       ( voice -- )
\   FM-NOTE-ON    ( freq vel voice -- )
\   FM-NOTE-OFF   ( voice -- )
\   FM-RENDER     ( voice -- buf )
\   FM-RATIO!     ( ratio op# voice -- )
\   FM-INDEX!     ( index op# voice -- )
\   FM-ALGO!      ( algorithm voice -- )
\   FM-FEEDBACK!  ( amount voice -- )
\   FM-LEVEL!     ( level op# voice -- )
\   FM-ENV!       ( a d s r op# voice -- )

REQUIRE fp16-ext.f
REQUIRE ../math/trig.f
REQUIRE audio/pcm.f
REQUIRE audio/env.f
REQUIRE audio/wavetable.f

PROVIDED akashic-audio-fm

\ =====================================================================
\  Algorithm constants (4-op)
\ =====================================================================
\
\  Algo 0: [1]→[2]→[3]→[4]→out           (serial)
\  Algo 1: [1]→[2]→out, [3]→[4]→out      (two parallel pairs)
\  Algo 2: [1]→[2]→[3]→out, [4]→out      (3-chain + sine)
\  Algo 3: [1+2]→[3]→[4]→out             (parallel-mod into serial)
\
\  For 2-op: only algo 0 applies (op1 mod → op2 carrier).

0 CONSTANT FM-ALGO-SERIAL
1 CONSTANT FM-ALGO-PARALLEL
2 CONSTANT FM-ALGO-3CHAIN
3 CONSTANT FM-ALGO-PARMOD

\ =====================================================================
\  Per-operator descriptor layout  (6 cells = 48 bytes)
\ =====================================================================
\
\  +0   ratio     Frequency ratio (FP16, e.g. 2.0 = octave)
\  +8   index     Modulation index (FP16, depth of FM)
\  +16  level     Output level 0.0–1.0 (FP16)
\  +24  env       ADSR envelope descriptor (pointer)
\  +32  phase     Phase accumulator 0.0–1.0 (FP16)
\  +40  freq      Current frequency in Hz (FP16, = base × ratio)

48 CONSTANT _FM-OP-SIZE

: FO.RATIO  ( op -- addr )  ;
: FO.INDEX  ( op -- addr )  8 + ;
: FO.LEVEL  ( op -- addr )  16 + ;
: FO.ENV    ( op -- addr )  24 + ;
: FO.PHASE  ( op -- addr )  32 + ;
: FO.FREQ   ( op -- addr )  40 + ;

\ =====================================================================
\  FM voice descriptor layout  (7 cells = 56 bytes)
\ =====================================================================
\
\  +0   n-ops     Number of operators (2 or 4)
\  +8   algo      Algorithm index
\  +16  feedback  Op1 self-modulation amount (FP16)
\  +24  ops       Pointer to operator array (heap)
\  +32  work-buf  Pointer to scratch PCM buffer
\  +40  rate      Sample rate (integer)
\  +48  fb-prev   Previous op1 output for feedback (FP16)

56 CONSTANT _FM-DESC-SIZE

: FM.NOPS     ( v -- addr )  ;
: FM.ALGO     ( v -- addr )  8 + ;
: FM.FB       ( v -- addr )  16 + ;
: FM.OPS      ( v -- addr )  24 + ;
: FM.BUF      ( v -- addr )  32 + ;
: FM.RATE     ( v -- addr )  40 + ;
: FM.FBPREV   ( v -- addr )  48 + ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _FM-TMP      \ voice descriptor
VARIABLE _FM-BUF      \ work buffer
VARIABLE _FM-BASE     \ base frequency (FP16)
VARIABLE _FM-OUT      \ accumulated output
VARIABLE _FM-MOD      \ modulator value for current sample
VARIABLE _FM-I        \ loop index
VARIABLE _FM-OP       \ current operator pointer
VARIABLE _FM-PH       \ phase temp
VARIABLE _FM-INC      \ phase increment
VARIABLE _FM-RVAL     \ rate
VARIABLE _FM-FVAL     \ frames

\ Operator output storage (up to 4 operators)
VARIABLE _FM-O1       \ op1 output (FP16)
VARIABLE _FM-O2       \ op2 output
VARIABLE _FM-O3       \ op3 output
VARIABLE _FM-O4       \ op4 output

\ =====================================================================
\  Internal: get operator address by index
\ =====================================================================
\  ( op# voice -- op-addr )

: _FM-OP@  ( op# voice -- op-addr )
    FM.OPS @ SWAP _FM-OP-SIZE * + ;

\ =====================================================================
\  FM-CREATE — Create FM voice
\ =====================================================================
\  ( n-ops algorithm rate frames -- voice )
\  n-ops = 2 or 4
\  algorithm = routing algorithm (0–3)
\  rate = sample rate (integer)
\  frames = work buffer size

: FM-CREATE  ( n-ops algorithm rate frames -- voice )
    _FM-FVAL !
    _FM-RVAL !
    >R                                \ R: algorithm
    >R                                \ R: algorithm n-ops

    \ Allocate voice descriptor
    _FM-DESC-SIZE ALLOCATE
    0<> ABORT" FM-CREATE: desc alloc failed"
    _FM-TMP !

    R> DUP 2 MAX 4 MIN               \ clamp n-ops to [2,4]
    _FM-TMP @ FM.NOPS !
    R> _FM-TMP @ FM.ALGO !
    FP16-POS-ZERO _FM-TMP @ FM.FB !
    _FM-RVAL @ _FM-TMP @ FM.RATE !
    FP16-POS-ZERO _FM-TMP @ FM.FBPREV !

    \ Allocate operator array
    _FM-TMP @ FM.NOPS @ _FM-OP-SIZE * ALLOCATE
    0<> ABORT" FM-CREATE: ops alloc failed"
    _FM-TMP @ FM.OPS !

    \ Initialize each operator
    _FM-TMP @ FM.NOPS @ 0 DO
        I _FM-TMP @ _FM-OP@ _FM-OP !

        \ Default ratio: 1.0 (unison)
        FP16-POS-ONE  _FM-OP @ FO.RATIO !
        \ Default index: 1.0
        FP16-POS-ONE  _FM-OP @ FO.INDEX !
        \ Default level: 1.0
        FP16-POS-ONE  _FM-OP @ FO.LEVEL !
        \ Phase = 0
        FP16-POS-ZERO _FM-OP @ FO.PHASE !
        \ Freq = 440
        440 INT>FP16   _FM-OP @ FO.FREQ  !

        \ Create envelope: A=5ms D=50ms S=0.8 R=100ms
        5 50 0x3A66 100 _FM-RVAL @
        ENV-CREATE
        _FM-OP @ FO.ENV !
    LOOP

    \ Allocate work buffer
    _FM-FVAL @ _FM-RVAL @ 16 1 PCM-ALLOC
    _FM-TMP @ FM.BUF !

    _FM-TMP @ ;

\ =====================================================================
\  FM-FREE — Free voice and all resources
\ =====================================================================

: FM-FREE  ( voice -- )
    _FM-TMP !

    \ Free each operator's envelope
    _FM-TMP @ FM.NOPS @ 0 DO
        I _FM-TMP @ _FM-OP@ FO.ENV @ ENV-FREE
    LOOP

    \ Free operator array
    _FM-TMP @ FM.OPS @ FREE

    \ Free work buffer
    _FM-TMP @ FM.BUF @ PCM-FREE

    \ Free descriptor
    _FM-TMP @ FREE ;

\ =====================================================================
\  Setters
\ =====================================================================

: FM-RATIO!  ( ratio op# voice -- )  _FM-OP@ FO.RATIO ! ;
: FM-INDEX!  ( index op# voice -- )  _FM-OP@ FO.INDEX ! ;
: FM-LEVEL!  ( level op# voice -- )  _FM-OP@ FO.LEVEL ! ;
: FM-ALGO!   ( algorithm voice -- )  FM.ALGO ! ;
: FM-FEEDBACK! ( amount voice -- )   FM.FB ! ;

\ FM-ENV! — Set envelope parameters for an operator
\  ( a d s r op# voice -- )

VARIABLE _FM-EA
VARIABLE _FM-ED
VARIABLE _FM-ES
VARIABLE _FM-ER
VARIABLE _FM-EOP

: FM-ENV!  ( a d s r op# voice -- )
    _FM-TMP !
    _FM-EOP !
    _FM-ER !
    _FM-ES !
    _FM-ED !
    _FM-EA !

    \ Free old envelope
    _FM-EOP @ _FM-TMP @ _FM-OP@ FO.ENV @ ENV-FREE

    \ Create new envelope: ( a d s r rate -- env )
    _FM-EA @ _FM-ED @ _FM-ES @ _FM-ER @ _FM-TMP @ FM.RATE @
    ENV-CREATE
    _FM-EOP @ _FM-TMP @ _FM-OP@ FO.ENV ! ;

\ =====================================================================
\  FM-NOTE-ON — Trigger note
\ =====================================================================
\  ( freq vel voice -- )
\  freq = base frequency in FP16 Hz
\  vel  = velocity (reserved)
\  Sets each operator's frequency = base × ratio, gates envelopes.

: FM-NOTE-ON  ( freq vel voice -- )
    _FM-TMP !
    DROP                              \ vel (reserved)
    _FM-BASE !

    \ Set up each operator
    _FM-TMP @ FM.NOPS @ 0 DO
        I _FM-TMP @ _FM-OP@ _FM-OP !

        \ freq_i = base_freq × ratio_i
        _FM-BASE @ _FM-OP @ FO.RATIO @ FP16-MUL
        _FM-OP @ FO.FREQ !

        \ Reset phase
        FP16-POS-ZERO _FM-OP @ FO.PHASE !

        \ Gate on envelope
        _FM-OP @ FO.ENV @ ENV-GATE-ON
    LOOP

    \ Reset feedback state
    FP16-POS-ZERO _FM-TMP @ FM.FBPREV ! ;

\ =====================================================================
\  FM-NOTE-OFF — Release note
\ =====================================================================

: FM-NOTE-OFF  ( voice -- )
    _FM-TMP !
    _FM-TMP @ FM.NOPS @ 0 DO
        I _FM-TMP @ _FM-OP@ FO.ENV @ ENV-GATE-OFF
    LOOP ;

\ =====================================================================
\  Internal: compute one operator sample with phase modulation
\ =====================================================================
\  ( mod-input op-addr rate -- sample )
\  mod-input = phase modulation from modulator(s) (FP16)
\  Returns: sample × level × envelope
\
\  Phase modulation: effective_phase = phase + mod_input × index
\  Output: sin(2π × effective_phase) × level × env

VARIABLE _FM-EPHA     \ effective phase

: _FM-OP-SAMPLE  ( mod-input op-addr rate -- sample )
    _FM-RVAL !
    _FM-OP !

    \ Compute effective phase = phase + mod_input × index
    _FM-OP @ FO.INDEX @ FP16-MUL      ( mod×index )
    _FM-OP @ FO.PHASE @ FP16-ADD      ( effective phase )

    \ Wrap to [0, 1)
    DUP FP16-POS-ONE FP16-GE IF
        FP16-POS-ONE FP16-SUB
    THEN
    DUP FP16-POS-ZERO FP16-LT IF
        FP16-POS-ONE FP16-ADD
    THEN
    _FM-EPHA !

    \ Output = sin(2π × effective_phase) via wavetable
    _FM-EPHA @ WT-SIN-TABLE WT-LERP

    \ Apply envelope
    _FM-OP @ FO.ENV @ ENV-TICK FP16-MUL

    \ Apply output level
    _FM-OP @ FO.LEVEL @ FP16-MUL

    \ Advance base phase: phase += freq / rate
    _FM-OP @ FO.FREQ @
    _FM-RVAL @ INT>FP16 FP16-DIV     ( increment )
    _FM-OP @ FO.PHASE @ FP16-ADD

    \ Wrap phase
    DUP FP16-POS-ONE FP16-GE IF
        FP16-POS-ONE FP16-SUB
    THEN
    _FM-OP @ FO.PHASE ! ;

\ =====================================================================
\  Internal: render one sample for 2-op FM
\ =====================================================================
\  2-op: op1(modulator) → op2(carrier) → output
\  Op1 has optional self-feedback.

: _FM-RENDER-2OP-SAMPLE  ( voice -- sample )
    _FM-TMP !

    \ Op1 (modulator) with self-feedback
    _FM-TMP @ FM.FBPREV @
    _FM-TMP @ FM.FB @ FP16-MUL        ( feedback × prev )
    0 _FM-TMP @ _FM-OP@
    _FM-TMP @ FM.RATE @
    _FM-OP-SAMPLE
    DUP _FM-O1 !
    DUP _FM-TMP @ FM.FBPREV !         \ save for next feedback

    \ Op2 (carrier) modulated by op1
    DROP                              \ drop dup
    _FM-O1 @                          \ mod input = op1 output
    1 _FM-TMP @ _FM-OP@
    _FM-TMP @ FM.RATE @
    _FM-OP-SAMPLE ;

\ =====================================================================
\  Internal: render one sample for 4-op FM
\ =====================================================================
\  Routing depends on algorithm.

: _FM-RENDER-4OP-SAMPLE  ( voice -- sample )
    _FM-TMP !

    \ Always compute op1 first (with feedback)
    _FM-TMP @ FM.FBPREV @
    _FM-TMP @ FM.FB @ FP16-MUL
    0 _FM-TMP @ _FM-OP@
    _FM-TMP @ FM.RATE @
    _FM-OP-SAMPLE
    DUP _FM-O1 !
    _FM-TMP @ FM.FBPREV !

    _FM-TMP @ FM.ALGO @
    CASE
        FM-ALGO-SERIAL OF
            \ [1]→[2]→[3]→[4]→out
            _FM-O1 @
            1 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O2 !
            _FM-O2 @
            2 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O3 !
            _FM-O3 @
            3 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
        ENDOF

        FM-ALGO-PARALLEL OF
            \ [1]→[2]→out, [3]→[4]→out
            _FM-O1 @
            1 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O2 !
            \ Op3 (no modulation input)
            FP16-POS-ZERO
            2 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O3 !
            _FM-O3 @
            3 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O4 !
            \ Mix both carriers
            _FM-O2 @ _FM-O4 @ FP16-ADD
            FP16-POS-HALF FP16-MUL    \ average to prevent clipping
        ENDOF

        FM-ALGO-3CHAIN OF
            \ [1]→[2]→[3]→out, [4]→out
            _FM-O1 @
            1 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O2 !
            _FM-O2 @
            2 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O3 !
            \ Op4 (free-running carrier)
            FP16-POS-ZERO
            3 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O4 !
            _FM-O3 @ _FM-O4 @ FP16-ADD
            FP16-POS-HALF FP16-MUL
        ENDOF

        FM-ALGO-PARMOD OF
            \ [1+2]→[3]→[4]→out
            \ Op2 also runs free (no mod)
            FP16-POS-ZERO
            1 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O2 !
            \ Mix op1 + op2 as modulators
            _FM-O1 @ _FM-O2 @ FP16-ADD
            2 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
            _FM-O3 !
            _FM-O3 @
            3 _FM-TMP @ _FM-OP@ _FM-TMP @ FM.RATE @ _FM-OP-SAMPLE
        ENDOF

        \ Default: just op1 output
        _FM-O1 @ SWAP
    ENDCASE ;

\ =====================================================================
\  Block-mode 2-op FM rendering (Tier 2.3)
\ =====================================================================
\  When feedback = 0, the modulator has no data dependency between
\  samples, so its wavetable lookup can be done in bulk via
\  WT-BLOCK-FILL.  The per-sample cost drops from ~1350cy to ~500cy
\  per operator for the modulator, and the carrier avoids the
\  repeated FP16-DIV(freq, rate) by precomputing its increment.
\
\  Strategy:
\   1. WT-BLOCK-FILL modulator's raw sine into _WT-SCRATCH
\   2. Per-sample: read scratch[i], apply ENV-TICK × level
\      → modulator output
\   3. Per-sample: carrier effective_phase = phase + mod × index,
\      do WT-LERP, apply ENV-TICK × level → output sample
\   4. Carrier phase advance uses precomputed FP16 increment
\      (one FP16-DIV at block start, not per sample)
\
\  Falls back to scalar if:
\   - feedback ≠ 0 (mod[i] depends on mod[i-1])
\   - WT-BLOCK-INC returns 0 (sub-1Hz frequency)

VARIABLE _FM-BK-OP0      \ modulator op address
VARIABLE _FM-BK-OP1      \ carrier op address
VARIABLE _FM-BK-ENV0     \ modulator envelope
VARIABLE _FM-BK-ENV1     \ carrier envelope
VARIABLE _FM-BK-LVL0     \ modulator level
VARIABLE _FM-BK-LVL1     \ carrier level
VARIABLE _FM-BK-IDX      \ modulation index
VARIABLE _FM-BK-CINC     \ carrier FP16 phase increment
VARIABLE _FM-BK-N        \ frame count
VARIABLE _FM-BK-DST      \ output PCM data pointer

: _FM-RENDER-2OP-BLOCK  ( voice -- ok? )
    _FM-TMP !

    \ Check: feedback must be zero for block mode
    _FM-TMP @ FM.FB @ FP16-POS-ZERO = 0= IF
        0 EXIT   \ → fall back to scalar
    THEN

    \ Get operator pointers
    0 _FM-TMP @ _FM-OP@  _FM-BK-OP0 !
    1 _FM-TMP @ _FM-OP@  _FM-BK-OP1 !

    \ Compute modulator integer phase increment
    _FM-BK-OP0 @ FO.FREQ @
    _FM-TMP @ FM.RATE @
    WT-BLOCK-INC DUP 0= IF
        DROP 0 EXIT   \ sub-1Hz → scalar
    THEN
    _FM-INC !   \ modulator integer inc

    \ Compute carrier FP16 phase increment (one division, not per sample)
    _FM-BK-OP1 @ FO.FREQ @
    _FM-TMP @ FM.RATE @ INT>FP16
    FP16-DIV
    _FM-BK-CINC !

    \ Cache envelope pointers, levels, index
    _FM-BK-OP0 @ FO.ENV @   _FM-BK-ENV0 !
    _FM-BK-OP1 @ FO.ENV @   _FM-BK-ENV1 !
    _FM-BK-OP0 @ FO.LEVEL @ _FM-BK-LVL0 !
    _FM-BK-OP1 @ FO.LEVEL @ _FM-BK-LVL1 !
    _FM-BK-OP0 @ FO.INDEX @ _FM-BK-IDX  !

    \ Buffer info
    _FM-TMP @ FM.BUF @ PCM-LEN  _FM-BK-N !
    _FM-TMP @ FM.BUF @ PCM-DATA _FM-BK-DST !

    \ Step 1: fill scratch with modulator raw sine (integer phase)
    _FM-BK-OP0 @ FO.PHASE @ WT-PH>INT     \ FP16 phase → integer
    _FM-INC @
    _FM-BK-N @
    WT-SIN-TABLE
    _WT-SCRATCH
    WT-BLOCK-FILL
    \ Update modulator phase
    WT-INT>PH _FM-BK-OP0 @ FO.PHASE !

    \ Steps 2+3: per-sample loop
    _FM-BK-N @ 0 DO
        \ Read modulator raw sine from scratch
        _WT-SCRATCH I 2 * + W@

        \ Apply modulator envelope and level
        _FM-BK-ENV0 @ ENV-TICK FP16-MUL
        _FM-BK-LVL0 @ FP16-MUL

        \ Multiply by modulation index → phase offset
        _FM-BK-IDX @ FP16-MUL

        \ Carrier: effective_phase = phase + mod_offset
        _FM-BK-OP1 @ FO.PHASE @ FP16-ADD

        \ Wrap to [0, 1)
        DUP FP16-POS-ONE FP16-GE IF
            FP16-POS-ONE FP16-SUB
        THEN
        DUP FP16-POS-ZERO FP16-LT IF
            FP16-POS-ONE FP16-ADD
        THEN

        \ Carrier wavetable lookup
        WT-SIN-TABLE WT-LERP

        \ Apply carrier envelope and level
        _FM-BK-ENV1 @ ENV-TICK FP16-MUL
        _FM-BK-LVL1 @ FP16-MUL

        \ Clamp to [-1, 1]
        FP16-NEG-ONE FP16-POS-ONE FP16-CLAMP

        \ Store to output
        _FM-BK-DST @ I 2 * + W!

        \ Advance carrier phase
        _FM-BK-OP1 @ FO.PHASE @
        _FM-BK-CINC @ FP16-ADD
        DUP FP16-POS-ONE FP16-GE IF
            FP16-POS-ONE FP16-SUB
        THEN
        _FM-BK-OP1 @ FO.PHASE !
    LOOP

    1 ;   \ success

\ =====================================================================
\  FM-RENDER — Render one block
\ =====================================================================
\  ( voice -- buf )

: FM-RENDER  ( voice -- buf )
    _FM-TMP !
    _FM-TMP @ FM.BUF @ _FM-BUF !

    \ Try block-mode 2-op (no feedback) first
    _FM-TMP @ FM.NOPS @ 2 = IF
        _FM-TMP @ _FM-RENDER-2OP-BLOCK IF
            _FM-BUF @ EXIT
        THEN
    THEN

    \ Scalar fallback
    _FM-BUF @ PCM-LEN 0 DO
        _FM-TMP @ FM.NOPS @ 2 = IF
            _FM-TMP @ _FM-RENDER-2OP-SAMPLE
        ELSE
            _FM-TMP @ _FM-RENDER-4OP-SAMPLE
        THEN
        \ Clamp to [-1, 1]
        FP16-NEG-ONE FP16-POS-ONE FP16-CLAMP
        I _FM-BUF @ PCM-FRAME!
    LOOP

    _FM-BUF @ ;
