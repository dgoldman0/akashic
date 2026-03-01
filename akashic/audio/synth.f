\ synth.f — Subtractive synthesis voice
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Classic subtractive architecture:
\   oscillator(s) → resonant filter → amplitude envelope → output
\
\ One voice per descriptor.  Polyphony is the caller's responsibility
\ (duplicate voices, manage note allocation).
\
\ Supports:
\   - Single or dual oscillator (any OSC shape)
\   - Osc2 detuning in cents
\   - Resonant low-pass, high-pass, or band-pass filter
\   - ADSR amplitude envelope
\   - ADSR filter envelope (modulates cutoff)
\   - Per-block rendering into internal work buffer
\
\ Memory: voice descriptor (72 bytes) + work PCM buffer + 2 envelopes
\         + 1–2 oscillators (from osc.f / env.f).
\
\ Prefix: SYNTH-   (public API)
\         _SY-     (internals)
\
\ Load with:   REQUIRE audio/synth.f
\
\ === Public API ===
\   SYNTH-CREATE    ( shape1 shape2 rate frames -- voice )
\   SYNTH-FREE      ( voice -- )
\   SYNTH-NOTE-ON   ( freq vel voice -- )
\   SYNTH-NOTE-OFF  ( voice -- )
\   SYNTH-RENDER    ( voice -- buf )
\   SYNTH-CUTOFF!   ( freq voice -- )
\   SYNTH-RESO!     ( q voice -- )
\   SYNTH-DETUNE!   ( cents voice -- )
\   SYNTH-FILT-TYPE! ( type voice -- )

REQUIRE fp16-ext.f
REQUIRE ../math/trig.f
REQUIRE audio/pcm.f
REQUIRE audio/osc.f
REQUIRE audio/env.f

PROVIDED akashic-audio-synth

\ =====================================================================
\  Filter type constants
\ =====================================================================

0 CONSTANT SYNTH-FILT-LP
1 CONSTANT SYNTH-FILT-HP
2 CONSTANT SYNTH-FILT-BP

\ =====================================================================
\  Voice descriptor layout  (9 cells = 72 bytes)
\ =====================================================================
\
\  +0   osc1       Primary oscillator descriptor (pointer)
\  +8   osc2       Secondary oscillator descriptor (pointer, or 0)
\  +16  filt-type  Filter type: 0=LP, 1=HP, 2=BP
\  +24  filt-cut   Filter cutoff frequency (FP16 Hz)
\  +32  filt-reso  Filter resonance / Q (FP16)
\  +40  amp-env    Amplitude envelope descriptor (pointer)
\  +48  filt-env   Filter envelope descriptor (pointer)
\  +56  work-buf   Pointer to scratch PCM buffer
\  +64  detune     Osc2 detune in cents (FP16, e.g. 7.0)

72 CONSTANT _SY-DESC-SIZE

: SY.OSC1    ( v -- addr )  ;
: SY.OSC2    ( v -- addr )  8 + ;
: SY.FTYPE   ( v -- addr )  16 + ;
: SY.FCUT    ( v -- addr )  24 + ;
: SY.FRESO   ( v -- addr )  32 + ;
: SY.AENV    ( v -- addr )  40 + ;
: SY.FENV    ( v -- addr )  48 + ;
: SY.BUF     ( v -- addr )  56 + ;
: SY.DETUNE  ( v -- addr )  64 + ;

\ =====================================================================
\  Biquad state for the filter (persistent across renders)
\ =====================================================================
\  These are per-voice but since we're non-reentrant (VARIABLE based),
\  we store them as globals.  For polyphony, caller would need to
\  save/restore or extend the descriptor.

VARIABLE _SY-FB0      \ filter b0
VARIABLE _SY-FB1      \ filter b1
VARIABLE _SY-FB2      \ filter b2
VARIABLE _SY-FA1      \ filter a1
VARIABLE _SY-FA2      \ filter a2
VARIABLE _SY-FS1      \ filter state 1 (persistent)
VARIABLE _SY-FS2      \ filter state 2 (persistent)

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _SY-TMP      \ voice descriptor pointer
VARIABLE _SY-BUF      \ work buffer
VARIABLE _SY-VAL      \ temp value
VARIABLE _SY-X        \ input sample
VARIABLE _SY-Y        \ output sample
VARIABLE _SY-CUT      \ effective cutoff
VARIABLE _SY-W0       \ angular frequency
VARIABLE _SY-SN       \ sin(w0)
VARIABLE _SY-CS       \ cos(w0)
VARIABLE _SY-ALPHA    \ alpha = sin(w0)/(2*Q)
VARIABLE _SY-NORM     \ normalization (1/a0)
VARIABLE _SY-RATE     \ sample rate
VARIABLE _SY-FENV-LEV \ filter env level

\ =====================================================================
\  FP16 constants
\ =====================================================================

0x4248 CONSTANT _SY-PI         \ π ≈ 3.1406 (FP16 0x4248)
0x4000 CONSTANT _SY-TWO        \ 2.0
0x4400 CONSTANT _SY-FOUR       \ 4.0

\ =====================================================================
\  SYNTH-CREATE — Create subtractive voice
\ =====================================================================
\  ( shape1 shape2 rate frames -- voice )
\  shape1 = primary oscillator shape (0–4)
\  shape2 = secondary shape, or -1 for no second oscillator
\  rate   = sample rate (integer)
\  frames = work buffer size in frames

VARIABLE _SY-S1
VARIABLE _SY-S2
VARIABLE _SY-RVAL
VARIABLE _SY-FVAL

: SYNTH-CREATE  ( shape1 shape2 rate frames -- voice )
    _SY-FVAL !                        \ frames
    _SY-RVAL !                        \ rate
    _SY-S2 !                          \ shape2
    _SY-S1 !                          \ shape1

    \ Allocate descriptor
    _SY-DESC-SIZE ALLOCATE
    0<> ABORT" SYNTH-CREATE: alloc failed"
    _SY-TMP !

    \ Create primary oscillator (freq = 440 initially)
    440 INT>FP16 _SY-S1 @ _SY-RVAL @
    OSC-CREATE
    _SY-TMP @ SY.OSC1 !

    \ Create secondary oscillator if shape2 >= 0
    _SY-S2 @ 0< 0= IF
        440 INT>FP16 _SY-S2 @ _SY-RVAL @
        OSC-CREATE
        _SY-TMP @ SY.OSC2 !
    ELSE
        0 _SY-TMP @ SY.OSC2 !
    THEN

    \ Default filter: lowpass, cutoff=1000Hz, Q=0.707 (Butterworth)
    SYNTH-FILT-LP  _SY-TMP @ SY.FTYPE !
    1000 INT>FP16  _SY-TMP @ SY.FCUT  !
    \ 0.707 ≈ 707/1000 in FP16
    707 INT>FP16 1000 INT>FP16 FP16-DIV
    _SY-TMP @ SY.FRESO !

    \ Create amplitude envelope: A=10ms D=100ms S=0.7 R=200ms
    10 100 0x399A 200 _SY-RVAL @ ENV-CREATE
    _SY-TMP @ SY.AENV !

    \ Create filter envelope: A=20ms D=200ms S=0.3 R=300ms
    20 200 0x34CC 300 _SY-RVAL @ ENV-CREATE
    _SY-TMP @ SY.FENV !

    \ Allocate work buffer
    _SY-FVAL @ _SY-RVAL @ 16 1 PCM-ALLOC
    _SY-TMP @ SY.BUF !

    \ Default detune = 0 cents
    FP16-POS-ZERO _SY-TMP @ SY.DETUNE !

    \ Initialize biquad state
    FP16-POS-ZERO _SY-FS1 !
    FP16-POS-ZERO _SY-FS2 !

    _SY-TMP @ ;

\ =====================================================================
\  SYNTH-FREE — Free voice and all sub-descriptors
\ =====================================================================

: SYNTH-FREE  ( voice -- )
    _SY-TMP !
    _SY-TMP @ SY.OSC1 @ OSC-FREE
    _SY-TMP @ SY.OSC2 @ ?DUP IF OSC-FREE THEN
    _SY-TMP @ SY.AENV @ ENV-FREE
    _SY-TMP @ SY.FENV @ ENV-FREE
    _SY-TMP @ SY.BUF  @ PCM-FREE
    _SY-TMP @ FREE ;

\ =====================================================================
\  Setters
\ =====================================================================

: SYNTH-CUTOFF!    ( freq voice -- )  SY.FCUT  ! ;
: SYNTH-RESO!      ( q voice -- )     SY.FRESO ! ;
: SYNTH-FILT-TYPE! ( type voice -- )  SY.FTYPE ! ;

\ SYNTH-DETUNE! ( cents voice -- )
\ Detune amount in FP16 cents.  Applied to osc2 during NOTE-ON.
: SYNTH-DETUNE!  ( cents voice -- ) SY.DETUNE ! ;

\ =====================================================================
\  SYNTH-NOTE-ON — Trigger note
\ =====================================================================
\  ( freq vel voice -- )
\  freq = frequency in FP16 Hz
\  vel  = velocity 0.0–1.0 FP16 (reserved, currently unused)
\  Sets osc frequencies, triggers envelopes.

VARIABLE _SY-FREQ

: SYNTH-NOTE-ON  ( freq vel voice -- )
    _SY-TMP !
    DROP                              \ vel (reserved)
    _SY-FREQ !

    \ Set osc1 frequency
    _SY-FREQ @ _SY-TMP @ SY.OSC1 @ OSC-FREQ!

    \ Set osc2 frequency (detuned) if present
    _SY-TMP @ SY.OSC2 @ ?DUP IF
        \ detune: freq2 = freq × 2^(cents/1200)
        \ Simplified: freq2 ≈ freq × (1 + cents/1200)
        \ cents/1200 is small, linear approx is fine
        _SY-TMP @ SY.DETUNE @
        1200 INT>FP16 FP16-DIV        ( cents/1200 )
        FP16-POS-ONE FP16-ADD         ( 1 + cents/1200 )
        _SY-FREQ @ FP16-MUL           ( freq2 )
        SWAP OSC-FREQ!
    THEN

    \ Reset oscillator phases
    _SY-TMP @ SY.OSC1 @ OSC-RESET
    _SY-TMP @ SY.OSC2 @ ?DUP IF OSC-RESET THEN

    \ Gate on both envelopes
    _SY-TMP @ SY.AENV @ ENV-GATE-ON
    _SY-TMP @ SY.FENV @ ENV-GATE-ON

    \ Reset biquad state
    FP16-POS-ZERO _SY-FS1 !
    FP16-POS-ZERO _SY-FS2 ! ;

\ =====================================================================
\  SYNTH-NOTE-OFF — Release note
\ =====================================================================

: SYNTH-NOTE-OFF  ( voice -- )
    _SY-TMP !
    _SY-TMP @ SY.AENV @ ENV-GATE-OFF
    _SY-TMP @ SY.FENV @ ENV-GATE-OFF ;

\ =====================================================================
\  Internal: compute biquad coefficients for current filter state
\ =====================================================================
\  Uses cutoff, resonance, filter type, and sample rate to compute
\  b0, b1, b2, a1, a2 (RBJ cookbook formulas).
\
\  w0 = 2π × cutoff / rate
\  alpha = sin(w0) / (2*Q)

: _SY-COMPUTE-COEFFS  ( cutoff rate -- )
    _SY-RATE !

    \ w0 = 2π × cutoff / rate
    _SY-TWO _SY-PI FP16-MUL          ( 2π )
    SWAP FP16-MUL                     ( 2π×cutoff )
    _SY-RATE @ INT>FP16 FP16-DIV     ( w0 )
    _SY-W0 !

    \ sin(w0), cos(w0)
    _SY-W0 @ TRIG-SINCOS
    _SY-CS !
    _SY-SN !

    \ alpha = sin(w0) / (2*Q)
    _SY-SN @
    _SY-TWO _SY-TMP @ SY.FRESO @ FP16-MUL
    FP16-DIV
    _SY-ALPHA !

    \ Now compute based on filter type
    _SY-TMP @ SY.FTYPE @
    CASE
        SYNTH-FILT-LP OF
            \ LPF:
            \   b0 = (1 - cos) / 2
            \   b1 = 1 - cos
            \   b2 = (1 - cos) / 2
            \   a0 = 1 + alpha
            \   a1 = -2*cos
            \   a2 = 1 - alpha
            FP16-POS-ONE _SY-CS @ FP16-SUB   ( 1-cos )
            DUP FP16-POS-HALF FP16-MUL       ( 1-cos (1-cos)/2 )
            _SY-FB0 !
            DUP _SY-FB1 !
            FP16-POS-HALF FP16-MUL _SY-FB2 !
            _SY-TWO _SY-CS @ FP16-MUL FP16-NEG _SY-FA1 !
            FP16-POS-ONE _SY-ALPHA @ FP16-SUB _SY-FA2 !
            FP16-POS-ONE _SY-ALPHA @ FP16-ADD _SY-NORM !
        ENDOF

        SYNTH-FILT-HP OF
            \ HPF:
            \   b0 = (1 + cos) / 2
            \   b1 = -(1 + cos)
            \   b2 = (1 + cos) / 2
            \   a0 = 1 + alpha
            \   a1 = -2*cos
            \   a2 = 1 - alpha
            FP16-POS-ONE _SY-CS @ FP16-ADD   ( 1+cos )
            DUP FP16-POS-HALF FP16-MUL       ( 1+cos (1+cos)/2 )
            _SY-FB0 !
            DUP FP16-NEG _SY-FB1 !
            FP16-POS-HALF FP16-MUL _SY-FB2 !
            _SY-TWO _SY-CS @ FP16-MUL FP16-NEG _SY-FA1 !
            FP16-POS-ONE _SY-ALPHA @ FP16-SUB _SY-FA2 !
            FP16-POS-ONE _SY-ALPHA @ FP16-ADD _SY-NORM !
        ENDOF

        SYNTH-FILT-BP OF
            \ BPF (constant skirt gain):
            \   b0 = alpha
            \   b1 = 0
            \   b2 = -alpha
            \   a0 = 1 + alpha
            \   a1 = -2*cos
            \   a2 = 1 - alpha
            _SY-ALPHA @ _SY-FB0 !
            FP16-POS-ZERO _SY-FB1 !
            _SY-ALPHA @ FP16-NEG _SY-FB2 !
            _SY-TWO _SY-CS @ FP16-MUL FP16-NEG _SY-FA1 !
            FP16-POS-ONE _SY-ALPHA @ FP16-SUB _SY-FA2 !
            FP16-POS-ONE _SY-ALPHA @ FP16-ADD _SY-NORM !
        ENDOF
    ENDCASE

    \ Normalize all coefficients by 1/a0
    _SY-NORM @ FP16-RECIP _SY-NORM !
    _SY-FB0 @ _SY-NORM @ FP16-MUL _SY-FB0 !
    _SY-FB1 @ _SY-NORM @ FP16-MUL _SY-FB1 !
    _SY-FB2 @ _SY-NORM @ FP16-MUL _SY-FB2 !
    _SY-FA1 @ _SY-NORM @ FP16-MUL _SY-FA1 !
    _SY-FA2 @ _SY-NORM @ FP16-MUL _SY-FA2 ! ;

\ =====================================================================
\  Internal: apply biquad filter to work buffer in-place
\ =====================================================================
\  Uses DFII-T (direct form II transposed) with persistent state
\  in _SY-FS1 / _SY-FS2.

: _SY-APPLY-FILTER  ( buf -- )
    _SY-BUF !

    _SY-BUF @ PCM-LEN 0 DO
        I _SY-BUF @ PCM-FRAME@
        _SY-X !

        \ y = b0*x + s1
        _SY-FB0 @ _SY-X @ FP16-MUL
        _SY-FS1 @ FP16-ADD
        _SY-Y !

        \ s1 = b1*x - a1*y + s2
        _SY-FB1 @ _SY-X @ FP16-MUL
        _SY-FA1 @ _SY-Y @ FP16-MUL FP16-SUB
        _SY-FS2 @ FP16-ADD
        _SY-FS1 !

        \ s2 = b2*x - a2*y
        _SY-FB2 @ _SY-X @ FP16-MUL
        _SY-FA2 @ _SY-Y @ FP16-MUL FP16-SUB
        _SY-FS2 !

        \ Clamp output to [-1, 1] for FP16 safety
        _SY-Y @ FP16-NEG-ONE FP16-POS-ONE FP16-CLAMP
        I _SY-BUF @ PCM-FRAME!
    LOOP ;

\ =====================================================================
\  SYNTH-RENDER — Render one block
\ =====================================================================
\  ( voice -- buf )
\  1. OSC-FILL osc1 → work-buf
\  2. If osc2: OSC-ADD osc2 → work-buf
\  3. Compute filter cutoff = base_cutoff + filt-env-depth
\  4. Apply biquad filter in-place
\  5. ENV-APPLY amp-env
\  6. Return work-buf

: SYNTH-RENDER  ( voice -- buf )
    _SY-TMP !

    _SY-TMP @ SY.BUF @ _SY-BUF !

    \ Step 1: Fill work buffer with osc1
    _SY-BUF @ _SY-TMP @ SY.OSC1 @ OSC-FILL

    \ Step 2: Add osc2 if present
    _SY-TMP @ SY.OSC2 @ ?DUP IF
        _SY-BUF @ SWAP OSC-ADD
    THEN

    \ Step 3: Compute effective cutoff with filter envelope
    \ Tick the filter envelope to get current level
    _SY-TMP @ SY.FENV @ ENV-TICK
    _SY-FENV-LEV !

    \ effective_cutoff = base_cutoff × (1 + filt_env_level × 3)
    \ This gives cutoff sweep from base to 4× base at max env
    _SY-FENV-LEV @ 0x4200 FP16-MUL    ( env*3 )
    FP16-POS-ONE FP16-ADD              ( 1 + env*3 )
    _SY-TMP @ SY.FCUT @ FP16-MUL      ( effective cutoff )

    \ Clamp cutoff to [20 Hz, rate/2 − 1] for stability
    20 INT>FP16 MAX
    _SY-TMP @ SY.OSC1 @ OSC-RATE 2/ 1- INT>FP16 MIN
    _SY-CUT !

    \ Step 4: Compute biquad coefficients and apply filter
    _SY-CUT @
    _SY-TMP @ SY.OSC1 @ OSC-RATE      \ get sample rate from osc
    _SY-COMPUTE-COEFFS
    _SY-BUF @ _SY-APPLY-FILTER

    \ Step 5: Apply amplitude envelope
    _SY-BUF @ _SY-TMP @ SY.AENV @ ENV-APPLY

    _SY-BUF @ ;
