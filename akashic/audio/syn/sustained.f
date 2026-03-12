\ syn/sustained.f — Sustained detuned oscillator bank with LFO and filter
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ A continuously running sound generator controlled through five
\ perceptual dimensions:
\
\   brightness  — LP filter cutoff (dark velvet → bright glass)
\   warmth      — 2nd harmonic mix (pure sine → richer tone)
\   motion      — LFO vibrato depth (static → shimmering)
\   density     — oscillator count + detune (thin → thick choir)
\   breathiness — white noise mix (clean → airy → rough)
\
\ Any dimension can be driven from a data stream.  A CO₂ reading can
\ directly control breathiness.  Temperature can control brightness.
\ Variance can control motion.  Network packet loss can control
\ density to model instability.
\
\ Implementation:
\   Up to 8 pure oscillators summed (the bank).  density maps to how
\   many are active and how wide their detune spread is.  warmth adds
\   the 2nd harmonic (double-phase) to each oscillator.  An LFO at
\   5 Hz modulates all pitch increments for vibrato.  Breathiness
\   mixes white noise.  A 1-pole LP filter smooths the final sum.
\
\ Output:
\   SUST-RENDER fills a caller-supplied PCM buffer.
\   Call in a render loop for continuous output.
\   Change any parameter between calls — it takes effect immediately.
\
\ Prefix: SUST-   (public API)
\         _SU-    (internals)
\
\ Load with:   REQUIRE audio/syn/sustained.f

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE audio/osc.f
REQUIRE audio/noise.f
REQUIRE audio/lfo.f
REQUIRE audio/pcm.f

PROVIDED akashic-syn-sustained

\ =====================================================================
\  Descriptor layout  (16 cells = 128 bytes)
\ =====================================================================
\
\  +0   fund          Fundamental frequency Hz (FP16)
\  +8   rate          Sample rate Hz (integer)
\  +16  brightness    0.0–1.0 — filter brightness (FP16)
\  +24  warmth        0.0–1.0 — 2nd harmonic content (FP16)
\  +32  motion        0.0–1.0 — LFO vibrato depth (FP16)
\  +40  density       0.0–1.0 — oscillator density (FP16)
\  +48  breathiness   0.0–1.0 — noise mix (FP16)
\  +56  n-active      Active oscillator count derived from density (int)
\  +64  noise-eng     Pointer to white noise generator
\  +72  lfo           Pointer to LFO descriptor
\  +80  lp-state      1-pole LP filter state (FP16)
\  +88  lp-alpha      LP filter alpha from brightness (FP16)
\  +96  osc[0]        Phase (FP16) at +96, detune-offset (FP16) at +98
\  +100 osc[1]        Phase at +100, detune-offset at +102
\  +104 osc[2]  ...   (stride 4 bytes per osc slot)
\  +108 osc[3]
\  +112 osc[4]
\  +116 osc[5]
\  +120 osc[6]
\  +124 osc[7]

128 CONSTANT SUST-DESC-SIZE

8 CONSTANT _SU-MAX-OSC

: SU.FUND    ( desc -- addr )  ;
: SU.RATE    ( desc -- addr )  8 + ;
: SU.BRITE   ( desc -- addr )  16 + ;
: SU.WARM    ( desc -- addr )  24 + ;
: SU.MOTION  ( desc -- addr )  32 + ;
: SU.DENSE   ( desc -- addr )  40 + ;
: SU.BREATH  ( desc -- addr )  48 + ;
: SU.NACT    ( desc -- addr )  56 + ;
: SU.NENG    ( desc -- addr )  64 + ;
: SU.LFO     ( desc -- addr )  72 + ;
: SU.LPST    ( desc -- addr )  80 + ;
: SU.LPALF   ( desc -- addr )  88 + ;

\ Oscillator slot base  ( desc i -- addr )  i = 0..7
: _SU-OSC    ( desc i -- addr )  4 * 96 + + ;

\ Slot fields  ( slot-addr -- field-addr )
: _SU-OSC-PH  ( slot -- addr )  ;
: _SU-OSC-DET ( slot -- addr )  2 + ;

\ =====================================================================
\  FP16 constants and helpers
\ =====================================================================

\ max LP cutoff = 8000 Hz, min = 200 Hz.  7800 Hz range.
\ brightness maps [0,1] → fc = 200 + brightness × 7800
\ LP alpha = a / (1 + a)  where a = 6 × fc / rate  (6 ≈ 2π)

VARIABLE _SU-TMP
VARIABLE _SU-RATE

: _SU-LP-ALPHA  ( brightness rate -- alpha-fp16 )
    _SU-RATE !
    \ fc = 200 + brightness × 7800
    7800 INT>FP16 FP16-MUL
    200  INT>FP16 FP16-ADD
    \ a = 6fc / rate
    _SU-RATE @ INT>FP16 FP16-DIV
    6 INT>FP16 FP16-MUL
    \ alpha = a / (1 + a)  — proper one-pole coefficient
    DUP FP16-POS-ONE FP16-ADD FP16-DIV
    DUP FP16-POS-ONE FP16-GT IF DROP FP16-POS-ONE THEN ;

\ LFO depth from motion: motion=0 → depth=0, motion=1 → depth=0.01
\ (LFO center=1.0, so tick returns 1.0 ± depth — multiplies pinc)
: _SU-LFO-DEPTH  ( motion -- depth-fp16 )
    \ max depth 0.01 (≈ 1.8% pitch swing = ~30 cents)
    \ 0x211F ≈ 0.01 FP16
    0x211F FP16-MUL ;

\ Active osc count from density: 1 + floor(density × 7)
VARIABLE _SU-ACT-TMP

: _SU-N-ACTIVE  ( density-fp16 -- int )
    7 INT>FP16 FP16-MUL
    FP16>INT 1 + 8 MIN 1 MAX ;

\ =====================================================================
\  Scratch variables (render)
\ =====================================================================

VARIABLE _SU-D
VARIABLE _SU-ACC
VARIABLE _SU-SMP
VARIABLE _SU-PH
VARIABLE _SU-PINC-BASE
VARIABLE _SU-LFO-V
VARIABLE _SU-PHASE2
VARIABLE _SU-WARM
VARIABLE _SU-BYTE-NACT
VARIABLE _SU-LPALF

\ =====================================================================
\  Internal: compute detune offsets for all 8 slots
\ =====================================================================
\  density → spread in cents: 0 → 0, 1 → ±20 cents
\  cents = 100 × log2(freq_ratio) so ratio = 2^(cents/1200)
\  approx: ratio ≈ 1 + cents/1731 (1731 ≈ 1200/ln2 in FP16)
\  spread_pinc = base_pinc × detune_ratio_offset
\  For n active oscillators, spread symmetrically around 0.

VARIABLE _SU-DO-D
VARIABLE _SU-DO-SPREAD
VARIABLE _SU-DO-N
VARIABLE _SU-DO-STEP
VARIABLE _SU-DO-BASE
VARIABLE _SU-DO-SLOT

: _SU-DETUNE-UPDATE  ( desc -- )
    _SU-DO-D !
    _SU-DO-D @ SU.NACT @  _SU-DO-N !
    _SU-DO-D @ SU.FUND @  _SU-DO-D @ SU.RATE @ INT>FP16 FP16-DIV
    _SU-DO-BASE !          \ base phase increment per sample

    \ spread as fraction of base: density × 0.005 / n_active
    _SU-DO-D @ SU.DENSE @       \ density FP16
    0x1D1F FP16-MUL              \ × 0.005 (FP16 ≈0.005 = 0x1D1F)
    _SU-DO-N @ INT>FP16 FP16-DIV
    _SU-DO-SPREAD !

    \ For n oscillators, detune symmetrically: -spread, ..., +spread
    \ step = 2 × spread / max(1, n-1)
    _SU-DO-N @ 1 > IF
        _SU-DO-SPREAD @ 2 INT>FP16 FP16-MUL   \ spread × 2 (total range)
        _SU-DO-N @ 1 - INT>FP16 FP16-DIV
        _SU-DO-STEP !
    ELSE
        FP16-POS-ZERO _SU-DO-SPREAD !   \ single osc: no detune, no offset
        FP16-POS-ZERO _SU-DO-STEP !
    THEN

    \ Assign detune for each of 8 slots; inactive slots get 0
    _SU-MAX-OSC 0 DO
        _SU-DO-D @ I _SU-OSC  _SU-DO-SLOT !
        I _SU-DO-N @ < IF
            \ offset = -spread + i × step
            FP16-POS-ZERO _SU-DO-SPREAD @ FP16-SUB   \ -spread
            I INT>FP16 _SU-DO-STEP @ FP16-MUL FP16-ADD \ + i×step
            _SU-DO-SLOT @ _SU-OSC-DET W!
        ELSE
            FP16-POS-ZERO _SU-DO-SLOT @ _SU-OSC-DET W!
        THEN
    LOOP ;

\ =====================================================================
\  SUST-CREATE — Allocate a sustained sound descriptor
\ =====================================================================
\  ( freq rate -- desc )
\  All dimensions at neutral defaults.

VARIABLE _SU-CR-F
VARIABLE _SU-CR-R

: SUST-CREATE  ( freq rate -- desc )
    _SU-CR-R !  _SU-CR-F !

    SUST-DESC-SIZE ALLOCATE
    0<> ABORT" SUST-CREATE: alloc failed"
    _SU-TMP !

    _SU-CR-F @ _SU-TMP @ SU.FUND  !
    _SU-CR-R @ _SU-TMP @ SU.RATE  !

    \ Neutral defaults
    FP16-POS-HALF  _SU-TMP @ SU.BRITE  !    \ medium brightness
    0x3266         _SU-TMP @ SU.WARM   !    \ 0.2 warmth
    0x3266         _SU-TMP @ SU.MOTION !    \ 0.2 motion
    FP16-POS-HALF  _SU-TMP @ SU.DENSE  !    \ medium density
    0x3266         _SU-TMP @ SU.BREATH !    \ 0.2 breathiness

    4 _SU-TMP @ SU.NACT !                   \ 4 active oscillators
    FP16-POS-ZERO _SU-TMP @ SU.LPST !
    FP16-POS-HALF _SU-TMP @ SU.LPALF !

    \ White noise gen
    NOISE-WHITE NOISE-CREATE  _SU-TMP @ SU.NENG !

    \ LFO: 5 Hz sine, initial depth = 0, center = 1.0 (pitch modulator)
    5 INT>FP16  OSC-SINE  FP16-POS-ZERO  FP16-POS-ONE  _SU-CR-R @
    LFO-CREATE  _SU-TMP @ SU.LFO !

    \ Zero all oscillator phases
    _SU-MAX-OSC 0 DO
        _SU-TMP @ I _SU-OSC  _SU-DO-SLOT !
        FP16-POS-ZERO _SU-DO-SLOT @ _SU-OSC-PH  W!
        FP16-POS-ZERO _SU-DO-SLOT @ _SU-OSC-DET W!
    LOOP

    \ Recompute LP alpha and detune from defaults
    _SU-TMP @ SU.BRITE @ _SU-TMP @ SU.RATE @  _SU-LP-ALPHA
    _SU-TMP @ SU.LPALF !
    _SU-TMP @ _SU-DETUNE-UPDATE

    _SU-TMP @ ;

\ =====================================================================
\  SUST-FREE
\ =====================================================================

: SUST-FREE  ( desc -- )
    DUP SU.NENG @ NOISE-FREE
    DUP SU.LFO  @ LFO-FREE
    FREE ;

\ =====================================================================
\  Setters
\ =====================================================================

VARIABLE _SU-SET-D

: SUST-FREQ!  ( freq desc -- )
    _SU-SET-D !
    _SU-SET-D @ SU.FUND !
    _SU-SET-D @ _SU-DETUNE-UPDATE ;

: SUST-BRIGHTNESS!  ( v desc -- )
    _SU-SET-D !
    _SU-SET-D @ SU.BRITE !
    _SU-SET-D @ SU.BRITE @  _SU-SET-D @ SU.RATE @  _SU-LP-ALPHA
    _SU-SET-D @ SU.LPALF ! ;

: SUST-WARMTH!  ( v desc -- )  SU.WARM ! ;

: SUST-MOTION!  ( v desc -- )
    _SU-SET-D !
    _SU-SET-D @ SU.MOTION !
    _SU-SET-D @ SU.MOTION @ _SU-LFO-DEPTH
    _SU-SET-D @ SU.LFO @ LFO-DEPTH! ;

: SUST-DENSITY!  ( v desc -- )
    _SU-SET-D !
    _SU-SET-D @ SU.DENSE !
    _SU-SET-D @ SU.DENSE @ _SU-N-ACTIVE  _SU-SET-D @ SU.NACT !
    _SU-SET-D @ _SU-DETUNE-UPDATE ;

: SUST-BREATHINESS!  ( v desc -- )  SU.BREATH ! ;

\ =====================================================================
\  SUST-MORPH — Instantly set all params to a target descriptor
\ =====================================================================
\  ( target frames desc -- )
\  Currently a direct cut; future work can interpolate over frames.

: SUST-MORPH  ( target frames desc -- )
    _SU-SET-D !  DROP  \ frames ignored in this implementation
    DUP SU.BRITE  @  _SU-SET-D @ SUST-BRIGHTNESS!
    DUP SU.WARM   @  _SU-SET-D @ SUST-WARMTH!
    DUP SU.MOTION @  _SU-SET-D @ SUST-MOTION!
    DUP SU.DENSE  @  _SU-SET-D @ SUST-DENSITY!
        SU.BREATH @  _SU-SET-D @ SUST-BREATHINESS! ;

\ =====================================================================
\  SUST-RENDER — Fill buffer with sustained oscillator output
\ =====================================================================
\  ( buf desc -- )

VARIABLE _SU-RN-D
VARIABLE _SU-RN-BUF
VARIABLE _SU-RN-DPTR
VARIABLE _SU-RN-LEN
VARIABLE _SU-RN-N
VARIABLE _SU-RN-BPINC  \ base phase increment fund/rate
VARIABLE _SU-RN-SLOT
VARIABLE _SU-RN-DPHASE \ double-phase for warmth

: SUST-RENDER  ( buf desc -- )
    _SU-RN-D !  _SU-RN-BUF !

    _SU-RN-D @ SU.NACT  @  _SU-RN-N !
    _SU-RN-D @ SU.WARM  @  _SU-WARM !
    _SU-RN-D @ SU.LPALF @  _SU-LPALF !
    _SU-RN-D @ SU.FUND  @
    _SU-RN-D @ SU.RATE  @ INT>FP16 FP16-DIV  _SU-RN-BPINC !

    _SU-RN-BUF @ PCM-DATA  _SU-RN-DPTR !
    _SU-RN-BUF @ PCM-LEN   _SU-RN-LEN  !

    _SU-RN-LEN @ 0 ?DO
        FP16-POS-ZERO _SU-ACC !

        \ LFO tick: pitch vibrato multiplier (≈ 1.0 ± small depth)
        _SU-RN-D @ SU.LFO @ LFO-TICK  _SU-LFO-V !

        \ === Oscillator bank ===
        _SU-RN-N @ 0 ?DO
            _SU-RN-D @ I _SU-OSC  _SU-RN-SLOT !

            \ Load phase
            _SU-RN-SLOT @ _SU-OSC-PH W@  _SU-PH !

            \ Fundamental sine: sin(phase × 2π)
            _SU-PH @ WT-SIN-TABLE WT-LOOKUP  _SU-SMP !

            \ Warmth: add 2nd harmonic sin(frac(2×phase) × 2π)
            _SU-WARM @ FP16-POS-ZERO FP16-GT IF
                _SU-PH @ 2 INT>FP16 FP16-MUL
                BEGIN DUP FP16-POS-ONE FP16-GE WHILE FP16-POS-ONE FP16-SUB REPEAT
                WT-SIN-TABLE WT-LOOKUP        \ sin(2×phase) via wavetable
                _SU-WARM @ FP16-MUL
                _SU-SMP @ FP16-ADD  _SU-SMP !
            THEN

            _SU-ACC @ _SU-SMP @ FP16-ADD  _SU-ACC !

            \ Advance phase: pinc = (base_pinc + detune) × lfo_val
            _SU-RN-BPINC @
            _SU-RN-SLOT @ _SU-OSC-DET W@  FP16-ADD    \ + detune
            _SU-LFO-V @ FP16-MUL                       \ × lfo
            _SU-PH @ FP16-ADD                           \ + phase
            BEGIN DUP FP16-POS-ONE FP16-GE WHILE FP16-POS-ONE FP16-SUB REPEAT
            _SU-RN-SLOT @ _SU-OSC-PH W!
        LOOP

        \ Scale: divide by n_active for uniform loudness
        _SU-ACC @  _SU-RN-N @ INT>FP16 FP16-DIV  _SU-ACC !

        \ Breathiness: add white noise
        _SU-RN-D @ SU.BREATH @ FP16-POS-ZERO FP16-GT IF
            _SU-RN-D @ SU.NENG @ NOISE-SAMPLE
            _SU-RN-D @ SU.BREATH @ FP16-MUL
            _SU-ACC @ FP16-ADD  _SU-ACC !
        THEN

        \ LP filter (1-pole):  lpstate += alpha × (x - lpstate)
        _SU-ACC @  _SU-RN-D @ SU.LPST @  FP16-SUB   \ x - lpstate
        _SU-LPALF @ FP16-MUL                          \ × alpha
        _SU-RN-D @ SU.LPST @  FP16-ADD               \ + lpstate
        DUP _SU-RN-D @ SU.LPST !                     \ update state
        \ Write filtered output
        _SU-RN-DPTR @ I 2* + W!
    LOOP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _ssust-guard

' SU.FUND         CONSTANT _su-dotfund-xt
' SU.RATE         CONSTANT _su-dotrate-xt
' SU.BRITE        CONSTANT _su-dotbrite-xt
' SU.WARM         CONSTANT _su-dotwarm-xt
' SU.MOTION       CONSTANT _su-dotmotion-xt
' SU.DENSE        CONSTANT _su-dotdense-xt
' SU.BREATH       CONSTANT _su-dotbreath-xt
' SU.NACT         CONSTANT _su-dotnact-xt
' SU.NENG         CONSTANT _su-dotneng-xt
' SU.LFO          CONSTANT _su-dotlfo-xt
' SU.LPST         CONSTANT _su-dotlpst-xt
' SU.LPALF        CONSTANT _su-dotlpalf-xt
' SUST-CREATE     CONSTANT _sust-create-xt
' SUST-FREE       CONSTANT _sust-free-xt
' SUST-FREQ!      CONSTANT _sust-freq-s-xt
' SUST-BRIGHTNESS! CONSTANT _sust-brightness-s-xt
' SUST-WARMTH!    CONSTANT _sust-warmth-s-xt
' SUST-MOTION!    CONSTANT _sust-motion-s-xt
' SUST-DENSITY!   CONSTANT _sust-density-s-xt
' SUST-BREATHINESS! CONSTANT _sust-breathiness-s-xt
' SUST-MORPH      CONSTANT _sust-morph-xt
' SUST-RENDER     CONSTANT _sust-render-xt

: SU.FUND         _su-dotfund-xt _ssust-guard WITH-GUARD ;
: SU.RATE         _su-dotrate-xt _ssust-guard WITH-GUARD ;
: SU.BRITE        _su-dotbrite-xt _ssust-guard WITH-GUARD ;
: SU.WARM         _su-dotwarm-xt _ssust-guard WITH-GUARD ;
: SU.MOTION       _su-dotmotion-xt _ssust-guard WITH-GUARD ;
: SU.DENSE        _su-dotdense-xt _ssust-guard WITH-GUARD ;
: SU.BREATH       _su-dotbreath-xt _ssust-guard WITH-GUARD ;
: SU.NACT         _su-dotnact-xt _ssust-guard WITH-GUARD ;
: SU.NENG         _su-dotneng-xt _ssust-guard WITH-GUARD ;
: SU.LFO          _su-dotlfo-xt _ssust-guard WITH-GUARD ;
: SU.LPST         _su-dotlpst-xt _ssust-guard WITH-GUARD ;
: SU.LPALF        _su-dotlpalf-xt _ssust-guard WITH-GUARD ;
: SUST-CREATE     _sust-create-xt _ssust-guard WITH-GUARD ;
: SUST-FREE       _sust-free-xt _ssust-guard WITH-GUARD ;
: SUST-FREQ!      _sust-freq-s-xt _ssust-guard WITH-GUARD ;
: SUST-BRIGHTNESS! _sust-brightness-s-xt _ssust-guard WITH-GUARD ;
: SUST-WARMTH!    _sust-warmth-s-xt _ssust-guard WITH-GUARD ;
: SUST-MOTION!    _sust-motion-s-xt _ssust-guard WITH-GUARD ;
: SUST-DENSITY!   _sust-density-s-xt _ssust-guard WITH-GUARD ;
: SUST-BREATHINESS! _sust-breathiness-s-xt _ssust-guard WITH-GUARD ;
: SUST-MORPH      _sust-morph-xt _ssust-guard WITH-GUARD ;
: SUST-RENDER     _sust-render-xt _ssust-guard WITH-GUARD ;
[THEN] [THEN]
