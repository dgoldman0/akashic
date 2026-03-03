\ syn/membrane.f — Membrane + noise percussive synthesis engine
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Models a struck membrane as two summed components:
\
\   Tone:  A sine oscillator whose frequency sweeps from freq-start
\          to freq-end over sweep-ms milliseconds, then holds at
\          freq-end.  Linear amplitude decay over tone-decay-ms.
\          This is the fundamental mode of the membrane — initially
\          over-excited, relaxing downward.
\
\   Noise: White or pink noise through a simple 1-pole HP + LP
\          (approximate bandpass) filter, with separate linear
\          amplitude decay over noise-decay-ms.  This is the
\          stick/mallet impact and upper mode incoherence.
\
\ The blend and decay times determine everything about sound character.
\ Low tone-ratio, deep sweep, slow decay: large resonant drum.
\ High tone-ratio, narrow sweep, fast noise decay: snare.
\ Near-zero tone ratio, all noise: dry impact.
\ No noise, very slow decay: tuned kettle.
\
\ This engine has no opinion about which instrument it is.
\
\ Output:
\   MEMB-STRIKE returns a freshly allocated mono 16-bit PCM buffer.
\   Caller must PCM-FREE when done.
\   MEMB-STRIKE-INTO adds into an existing buffer.
\
\ Prefix: MEMB-   (public API)
\         _MB-    (internals)
\
\ Load with:   REQUIRE audio/syn/membrane.f

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE audio/osc.f
REQUIRE audio/noise.f
REQUIRE audio/pcm.f

PROVIDED akashic-syn-membrane

\ =====================================================================
\  Descriptor layout  (12 cells = 96 bytes)
\ =====================================================================
\
\  +0   freq-start    Tone sweep start Hz (FP16)
\  +8   freq-end      Tone sweep end / sustain Hz (FP16)
\  +16  sweep-ms      Sweep duration in ms (integer)
\  +24  tone-decay-ms Tonal component decay time in ms (integer)
\  +32  tone-amp      Tone amplitude 0.0–1.0 (FP16)
\  +40  noise-color   0=white 1=pink (integer)
\  +48  noise-lo      Noise HP cutoff Hz (FP16, 0=no HP)
\  +56  noise-hi      Noise LP cutoff Hz (FP16, 0=no LP)
\  +64  noise-decay-ms Noise component decay time in ms (integer)
\  +72  noise-amp     Noise amplitude 0.0–1.0 (FP16)
\  +80  rate          Sample rate Hz (integer)
\  +88  (reserved)

96 CONSTANT MEMB-DESC-SIZE

: MB.FSTART  ( desc -- addr )  ;
: MB.FEND    ( desc -- addr )  8 + ;
: MB.SWP-MS  ( desc -- addr )  16 + ;
: MB.TDK-MS  ( desc -- addr )  24 + ;
: MB.TAMP    ( desc -- addr )  32 + ;
: MB.NCOL    ( desc -- addr )  40 + ;
: MB.NLO     ( desc -- addr )  48 + ;
: MB.NHI     ( desc -- addr )  56 + ;
: MB.NDK-MS  ( desc -- addr )  64 + ;
: MB.NAMP    ( desc -- addr )  72 + ;
: MB.RATE    ( desc -- addr )  80 + ;

\ =====================================================================
\  FP16 constants
\ =====================================================================

\ 6 ≈ 2π — used to compute HP/LP alpha from Hz without proper exp()
6 CONSTANT _MB-TWOPI-INT

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _MB-TMP
VARIABLE _MB-RATE
VARIABLE _MB-VEL
VARIABLE _MB-BUF
VARIABLE _MB-FRAMES
VARIABLE _MB-I

\ Tone component state
VARIABLE _MB-T-FSTART
VARIABLE _MB-T-FEND
VARIABLE _MB-T-SWPF      \ sweep frames (integer)
VARIABLE _MB-T-DKAF      \ tone decay frames (integer)
VARIABLE _MB-T-TAMP
VARIABLE _MB-T-PHASE
VARIABLE _MB-T-PINC-S    \ phase inc at freq-start (FP16)
VARIABLE _MB-T-PINC-E    \ phase inc at freq-end (FP16)
VARIABLE _MB-T-PINC      \ current phase inc (interpolating)
VARIABLE _MB-T-ENV        \ current tone envelope level (FP16)
VARIABLE _MB-T-DSTEP     \ env decrement per sample (FP16)

\ Noise component state
VARIABLE _MB-N-COL
VARIABLE _MB-N-DKAF      \ noise decay frames (integer)
VARIABLE _MB-N-NAMP
VARIABLE _MB-N-ENG        \ noise generator pointer
VARIABLE _MB-N-ENV        \ current noise envelope level (FP16)
VARIABLE _MB-N-DSTEP     \ env decrement per sample (FP16)
VARIABLE _MB-N-HPALPHA   \ HP filter alpha (FP16)
VARIABLE _MB-N-LPALPHA   \ LP filter alpha (FP16)
VARIABLE _MB-N-XPREV     \ HP previous input (FP16)
VARIABLE _MB-N-HPOUT     \ HP previous output (FP16)
VARIABLE _MB-N-LPSTATE   \ LP state (FP16)

\ Per-render output
VARIABLE _MB-DPTR
VARIABLE _MB-SUM
VARIABLE _MB-TSMP
VARIABLE _MB-NSMP

\ =====================================================================
\  Internal: linear envelope decrement per sample
\ =====================================================================
\  ( decay-frames -- step-fp16 )
\  step = 1.0 / decay-frames

: _MB-ENV-STEP  ( frames -- step )
    DUP 0= IF DROP FP16-POS-ONE EXIT THEN
    INT>FP16
    FP16-POS-ONE SWAP FP16-DIV ;

\ =====================================================================
\  Internal: compute LP alpha from cutoff Hz
\ =====================================================================
\  Proper one-pole LP coefficient: alpha = a / (1 + a)
\  where a = 2π × fc / rate.
\  The naive formula "alpha = a, clip to 1" broke noise filtering
\  for any fc above rate/6 (~1273 Hz at 8 kHz) because both LP
\  clipped to 1.0 and HP became 1 − 1.0 = 0.0 → dead silence.
\  LP: y = y + alpha * (x - y)

: _MB-LP-ALPHA  ( fc-fp16 rate -- alpha-fp16 )
    INT>FP16 FP16-DIV              \ fc / rate
    _MB-TWOPI-INT INT>FP16 FP16-MUL   \ a = 6 × fc / rate  ≈ 2π fc/rate
    DUP FP16-POS-ONE FP16-ADD     \ ( a  1+a )
    FP16-DIV                       \ a / (1+a) — always in [0, 1)
    DUP FP16-POS-ONE FP16-GT IF DROP FP16-POS-ONE THEN ;  \ safety

\ =====================================================================
\  Internal: compute HP alpha from cutoff Hz
\ =====================================================================
\  HP: y = alpha * (y + x - x_prev)
\  alpha = 1 / (1 + a)  where a = 2π fc / rate  (= 1 - LP alpha)

: _MB-HP-ALPHA  ( fc-fp16 rate -- alpha-fp16 )
    _MB-LP-ALPHA
    FP16-POS-ONE SWAP FP16-SUB
    DUP FP16-POS-ZERO FP16-LT IF DROP FP16-POS-ZERO THEN ;

\ =====================================================================
\  MEMB-CREATE — Allocate membrane descriptor with defaults
\ =====================================================================
\  ( rate -- desc )
\
\  Defaults:
\    freq-start = 200 Hz, freq-end = 60 Hz, sweep-ms = 20
\    tone-decay-ms = 300, tone-amp = 0.8
\    noise = white, lo = 200 Hz, hi = 8000 Hz, decay = 80ms, amp = 0.5

VARIABLE _MB-C-RATE

: MEMB-CREATE  ( rate -- desc )
    _MB-C-RATE !

    MEMB-DESC-SIZE ALLOCATE
    0<> ABORT" MEMB-CREATE: alloc failed"
    _MB-TMP !

    200 INT>FP16   _MB-TMP @ MB.FSTART !
    60  INT>FP16   _MB-TMP @ MB.FEND   !
    20             _MB-TMP @ MB.SWP-MS !
    300            _MB-TMP @ MB.TDK-MS !
    \ tone-amp = 0.8 ≈ FP16 0x3A66
    0x3A66         _MB-TMP @ MB.TAMP   !
    0              _MB-TMP @ MB.NCOL   !   \ white
    200 INT>FP16   _MB-TMP @ MB.NLO    !
    8000 INT>FP16  _MB-TMP @ MB.NHI    !
    80             _MB-TMP @ MB.NDK-MS !
    \ noise-amp = 0.5 = FP16 0x3800
    FP16-POS-HALF  _MB-TMP @ MB.NAMP   !
    _MB-C-RATE @   _MB-TMP @ MB.RATE   !

    _MB-TMP @ ;

\ =====================================================================
\  MEMB-FREE
\ =====================================================================

: MEMB-FREE  ( desc -- ) FREE ;

\ =====================================================================
\  MEMB-TONE! — Set tonal component parameters
\ =====================================================================
\  ( start-hz end-hz sweep-ms tone-decay-ms desc -- )
\  Hz values are FP16.  ms values are integers.

: MEMB-TONE!  ( start end sweep-ms decay-ms desc -- )
    _MB-TMP !
    _MB-TMP @ MB.TDK-MS !
    _MB-TMP @ MB.SWP-MS !
    _MB-TMP @ MB.FEND   !
    _MB-TMP @ MB.FSTART ! ;

\ =====================================================================
\  MEMB-NOISE! — Set noise component parameters
\ =====================================================================
\  ( lo-hz hi-hz noise-decay-ms desc -- )
\  Hz values are FP16.  ms is integer.

: MEMB-NOISE!  ( lo-hz hi-hz decay-ms desc -- )
    _MB-TMP !
    _MB-TMP @ MB.NDK-MS !
    _MB-TMP @ MB.NHI    !
    _MB-TMP @ MB.NLO    ! ;

\ =====================================================================
\  MEMB-MIX! — Set amplitude blend between tone and noise
\ =====================================================================
\  ( tone-amp noise-amp desc -- )
\  Both FP16 0.0–1.0.

: MEMB-MIX!  ( tone-amp noise-amp desc -- )
    _MB-TMP !
    _MB-TMP @ MB.NAMP !
    _MB-TMP @ MB.TAMP ! ;

\ =====================================================================
\  MEMB-COLOR! — Set noise color (0=white, 1=pink)
\ =====================================================================

: MEMB-COLOR!  ( color desc -- )  MB.NCOL ! ;

\ =====================================================================
\  Internal: setup all render state from descriptor + velocity
\ =====================================================================

: _MB-SETUP  ( velocity desc -- )
    _MB-TMP !  _MB-VEL !

    _MB-TMP @ MB.RATE @ _MB-RATE !

    \ ---- tone state ----
    _MB-TMP @ MB.FSTART @ _MB-T-FSTART !
    _MB-TMP @ MB.FEND   @ _MB-T-FEND   !
    _MB-TMP @ MB.SWP-MS @ _MB-RATE @ * 1000 / _MB-T-SWPF !
    _MB-TMP @ MB.TDK-MS @ _MB-RATE @ * 1000 / _MB-T-DKAF !
    _MB-TMP @ MB.TAMP   @ _MB-VEL @ FP16-MUL  _MB-T-TAMP !
    FP16-POS-ZERO _MB-T-PHASE !

    \ phase increments at start and end frequencies
    _MB-T-FSTART @ _MB-RATE @ INT>FP16 FP16-DIV  _MB-T-PINC-S !
    _MB-T-FEND   @ _MB-RATE @ INT>FP16 FP16-DIV  _MB-T-PINC-E !

    \ envelope step (linear decay from 1.0 to 0.0 over tone-decay-ms)
    _MB-T-DKAF @ _MB-ENV-STEP  _MB-T-DSTEP !
    FP16-POS-ONE _MB-T-ENV !

    \ ---- noise state ----
    _MB-TMP @ MB.NCOL   @ _MB-N-COL  !
    _MB-TMP @ MB.NDK-MS @ _MB-RATE @ * 1000 / _MB-N-DKAF !
    _MB-TMP @ MB.NAMP   @ _MB-VEL @ FP16-MUL  _MB-N-NAMP !

    _MB-N-DKAF @ _MB-ENV-STEP  _MB-N-DSTEP !
    FP16-POS-ONE _MB-N-ENV !

    \ HP filter: y = alpha × (y + x - x_prev),  alpha from noise-lo
    _MB-TMP @ MB.NLO @ _MB-RATE @ _MB-HP-ALPHA  _MB-N-HPALPHA !
    FP16-POS-ZERO _MB-N-XPREV  !
    FP16-POS-ZERO _MB-N-HPOUT  !

    \ LP filter: y += alpha × (x - y),  alpha from noise-hi
    _MB-TMP @ MB.NHI @ _MB-RATE @ _MB-LP-ALPHA  _MB-N-LPALPHA !
    FP16-POS-ZERO _MB-N-LPSTATE !

    \ Create noise generator
    _MB-N-COL @ NOISE-CREATE  _MB-N-ENG ! ;

\ =====================================================================
\  Internal: render one sample
\ =====================================================================
\  ( sample-index -- fp16-sample )

VARIABLE _MB-RS-I
VARIABLE _MB-RS-T      \ tone sample (FP16)
VARIABLE _MB-RS-N      \ noise sample (FP16)
VARIABLE _MB-RS-FRAC   \ sweep fraction (FP16)
VARIABLE _MB-RS-PINC   \ interpolated phase inc (FP16)

: _MB-RENDER-ONE  ( i -- fp16 )
    _MB-RS-I !
    FP16-POS-ZERO _MB-RS-T !
    FP16-POS-ZERO _MB-RS-N !

    \ ---- Tone component ----
    _MB-T-ENV @ FP16-POS-ZERO FP16-GT IF
        \ Frequency sweep: lerp pinc from start to end over sweep frames
        _MB-RS-I @ _MB-T-SWPF @ < IF
            \ frac = i / swpf (how far into sweep)
            _MB-RS-I @ INT>FP16
            _MB-T-SWPF @ INT>FP16 FP16-DIV  _MB-RS-FRAC !
            \ pinc = pinc-start + frac * (pinc-end - pinc-start)
            _MB-T-PINC-E @ _MB-T-PINC-S @ FP16-SUB   \ delta
            _MB-RS-FRAC @ FP16-MUL
            _MB-T-PINC-S @ FP16-ADD
            _MB-RS-PINC !
        ELSE
            _MB-T-PINC-E @ _MB-RS-PINC !
        THEN

        \ sine sample
        _MB-T-PHASE @ WT-SIN-TABLE WT-LOOKUP
        _MB-T-TAMP @ FP16-MUL
        _MB-T-ENV  @ FP16-MUL
        _MB-RS-T !

        \ advance phase, wrap
        _MB-T-PHASE @ _MB-RS-PINC @ FP16-ADD
        BEGIN DUP FP16-POS-ONE FP16-GE WHILE FP16-POS-ONE FP16-SUB REPEAT
        _MB-T-PHASE !

        \ decay envelope
        _MB-T-ENV @  _MB-T-DSTEP @  FP16-SUB
        DUP FP16-POS-ZERO FP16-LT IF DROP FP16-POS-ZERO THEN
        _MB-T-ENV !
    THEN

    \ ---- Noise component ----
    _MB-N-ENV @ FP16-POS-ZERO FP16-GT IF
        \ raw noise
        _MB-N-ENG @ NOISE-SAMPLE

        \ HP filter (removes low frequencies below noise-lo)
        \ y = alpha * (y_prev + x - x_prev)
        DUP _MB-N-XPREV @ FP16-SUB   \ x - x_prev
        _MB-N-HPOUT @ FP16-ADD        \ + y_prev
        _MB-N-HPALPHA @ FP16-MUL      \ * alpha
        SWAP _MB-N-XPREV !            \ update x_prev with original x
        DUP _MB-N-HPOUT !             \ update y_prev

        \ LP filter: new_lp = lp + alpha*(hp - lp)
        \ Stack before: ( hp_out )
        DUP _MB-N-LPSTATE @ FP16-SUB  \ ( hp  hp-lp )
        _MB-N-LPALPHA @ FP16-MUL      \ ( hp  alpha*(hp-lp) )
        _MB-N-LPSTATE @ FP16-ADD      \ ( hp  new_lp )
        DUP _MB-N-LPSTATE !
        NIP                            \ ( new_lp ) — discard hp_out

        \ scale
        _MB-N-NAMP @ FP16-MUL
        _MB-N-ENV  @ FP16-MUL
        _MB-RS-N !

        \ decay envelope
        _MB-N-ENV @  _MB-N-DSTEP @  FP16-SUB
        DUP FP16-POS-ZERO FP16-LT IF DROP FP16-POS-ZERO THEN
        _MB-N-ENV !
    THEN

    _MB-RS-T @  _MB-RS-N @  FP16-ADD ;

\ =====================================================================
\  Internal: free per-render resources
\ =====================================================================

: _MB-CLEANUP  _MB-N-ENG @ NOISE-FREE ;

\ =====================================================================
\  MEMB-STRIKE — Render a strike, return new PCM buffer
\ =====================================================================
\  ( velocity desc -- buf )
\  velocity = FP16 0.0–1.0

VARIABLE _MB-STK-V
VARIABLE _MB-STK-D
VARIABLE _MB-STK-MS
VARIABLE _MB-STK-BUF

: MEMB-STRIKE  ( velocity desc -- buf )
    _MB-STK-D !  _MB-STK-V !

    \ Setup state
    _MB-STK-V @  _MB-STK-D @  _MB-SETUP

    \ Duration = max(tone-decay-ms, noise-decay-ms), min 10, max 8000
    _MB-STK-D @ MB.TDK-MS @
    _MB-STK-D @ MB.NDK-MS @
    MAX  10 MAX  8000 MIN  _MB-STK-MS !

    \ Allocate output buffer
    _MB-STK-MS @
    _MB-STK-D @ MB.RATE @ * 1000 /
    _MB-STK-D @ MB.RATE @
    16 1 PCM-ALLOC
    _MB-STK-BUF !

    _MB-STK-BUF @ PCM-DATA _MB-DPTR !
    _MB-STK-BUF @ PCM-LEN  _MB-FRAMES !

    _MB-FRAMES @ 0 ?DO
        I _MB-RENDER-ONE
        _MB-DPTR @ I 2* + W!
    LOOP

    _MB-CLEANUP
    _MB-STK-BUF @ ;

\ =====================================================================
\  MEMB-STRIKE-INTO — Render, add into existing PCM buffer
\ =====================================================================
\  ( buf velocity desc -- )

VARIABLE _MB-STI-BUF
VARIABLE _MB-STI-V
VARIABLE _MB-STI-D
VARIABLE _MB-STI-SPTR
VARIABLE _MB-STI-DPTR
VARIABLE _MB-STI-LEN

: MEMB-STRIKE-INTO  ( buf velocity desc -- )
    _MB-STI-D !  _MB-STI-V !  _MB-STI-BUF !

    _MB-STI-V @  _MB-STI-D @  MEMB-STRIKE  ( strike-buf )

    DUP PCM-LEN  _MB-STI-BUF @ PCM-LEN  MIN  _MB-STI-LEN !
    DUP PCM-DATA _MB-STI-SPTR !
    _MB-STI-BUF @ PCM-DATA _MB-STI-DPTR !

    _MB-STI-LEN @ 0 ?DO
        _MB-STI-SPTR @ I 2* + W@
        _MB-STI-DPTR @ I 2* + W@
        FP16-ADD
        _MB-STI-DPTR @ I 2* + W!
    LOOP

    PCM-FREE ;
