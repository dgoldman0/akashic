\ syn/granular.f — Granular synthesis over a PCM source buffer
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Granular synthesis scatters micro-events ("grains") densely across
\ a source PCM buffer.  No individual grain is perceptible on its own;
\ the emergent texture is determined by the statistical distribution
\ of grain parameters.
\
\ What you hear:
\   density 1–5 grains/sec     → distinct, separated events (spray)
\   density 10–30 grains/sec   → grainy texture, attack-y
\   density 50+ grains/sec     → smooth, fused, cloud-like
\
\   position + pos-scatter     → read location in source
\   pitch-shift + scatter      → pitch and time relationship
\   grain-ms                   → temporal resolution of texture
\   amp-scatter                → randomizes loudness, adds roughness
\   envelope                   → grain shape (Hann, trapezoidal, none)
\
\ Source buffer:
\   Pass a mono PCM buffer.  GRAN-RENDER reads from it.  The source
\   is NOT consumed or freed — caller owns it.
\   Pass 0 for a silent fallback (no grains produced).
\
\ Grain pool:
\   A fixed 16-slot grain pool is allocated per descriptor.
\   Grains play simultaneously.  New grains take over completed slots.
\   If all 16 are active (dense scheduling + long grains), new grains
\   steal the slot with highest env-phase (nearest to completion).
\
\ Output:
\   GRAN-RENDER fills a caller-supplied PCM buffer.
\   Call repeatedly in a render loop.
\   Change any parameter at any time; takes effect at next new grain.
\
\ Prefix: GRAN-   (public API)
\         _GR-    (internals)
\
\ Load with:   REQUIRE audio/syn/granular.f

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE audio/noise.f
REQUIRE audio/env.f
REQUIRE audio/pcm.f

PROVIDED akashic-syn-granular

\ =====================================================================
\  Grain pool slot (16 bytes per grain)
\ =====================================================================
\
\  +0   src-pos     Fractional read position 0.0–1.0 (FP16)
\  +2   src-step    Per-output-sample position advance (FP16)
\  +4   env-phase   Envelope position 0.0–1.0 (FP16)
\  +6   env-step    Per-sample env-phase increment (FP16)
\  +8   amp         Grain amplitude (FP16)
\  +10  active      1 = playing, 0 = free (int16)
\  +12  env-type    0=Hann 1=trapezoidal 2=flat (int16)
\  +14  (padding)

16 CONSTANT _GR-GRAIN-STRIDE
16 CONSTANT _GR-POOL-SIZE   \ max simultaneous grains

: GS.SPOS   ( g -- addr )  ;
: GS.STEP   ( g -- addr )  2 + ;
: GS.EPH    ( g -- addr )  4 + ;
: GS.ESTEP  ( g -- addr )  6 + ;
: GS.AMP    ( g -- addr )  8 + ;
: GS.ACT    ( g -- addr )  10 + ;
: GS.ETYPE  ( g -- addr )  12 + ;

\ Grain i base  ( pool i -- grain )
: _GR-GRAIN  ( pool i -- g )
    _GR-GRAIN-STRIDE * + ;

\ =====================================================================
\  Descriptor layout  (16 cells = 128 bytes)
\ =====================================================================
\
\  +0   source        PCM source buffer pointer (0 = silent)
\  +8   density       Grains per second (FP16)
\  +16  grain-ms      Grain duration ms (integer)
\  +24  position      Read head 0.0–1.0 (FP16)
\  +32  pos-scatter   Position randomization 0.0–1.0 (FP16)
\  +40  pitch-shift   Pitch ratio: 1.0 unchanged (FP16)
\  +48  pitch-scatter Pitch randomization 0.0–1.0 (FP16)
\  +56  amp-scatter   Amplitude randomization 0.0–1.0 (FP16)
\  +64  envelope      0=Hann, 1=trapezoidal, 2=flat (integer)
\  +72  rate          Sample rate Hz (integer)
\  +80  pool          Pointer to grain pool (16 × 16 bytes)
\  +88  sched-ctr     Frames since last grain triggered (integer)
\  +96  noise-eng     Pointer to noise gen (scatter)
\  +104 sched-period  Frames between grains = rate/density (integer)
\  +112 (reserved)
\  +120 (reserved)

128 CONSTANT GRAN-DESC-SIZE

: GD.SRC    ( desc -- addr )  ;
: GD.DENS   ( desc -- addr )  8 + ;
: GD.GMS    ( desc -- addr )  16 + ;
: GD.POS    ( desc -- addr )  24 + ;
: GD.PSCTR  ( desc -- addr )  32 + ;
: GD.PITCH  ( desc -- addr )  40 + ;
: GD.PTSCTR ( desc -- addr )  48 + ;
: GD.ASCTR  ( desc -- addr )  56 + ;
: GD.ENV    ( desc -- addr )  64 + ;
: GD.RATE   ( desc -- addr )  72 + ;
: GD.POOL   ( desc -- addr )  80 + ;
: GD.SCTR   ( desc -- addr )  88 + ;
: GD.NENG   ( desc -- addr )  96 + ;
: GD.SPER   ( desc -- addr )  104 + ;

\ =====================================================================
\  Scratch / internal variables
\ =====================================================================

VARIABLE _GR-TMP
VARIABLE _GR-D
VARIABLE _GR-POOL
VARIABLE _GR-I
VARIABLE _GR-G       \ current grain address
VARIABLE _GR-ACC     \ per-sample accumulator
VARIABLE _GR-SRC
VARIABLE _GR-SLEN
VARIABLE _GR-SPTR

\ =====================================================================
\  Internal: Hann window at env-phase
\ =====================================================================
\  w = sin(π × phase)  — rises 0→1→0 as phase goes 0→1

: _GR-HANN  ( phase-fp16 -- w-fp16 )
    \ π as FP16 ≈ 3.1416 → 0x4248
    0x4248 FP16-MUL TRIG-SIN ;

\ =====================================================================
\  Internal: trapezoidal envelope
\ =====================================================================
\  First 10% ramp up, middle 80% sustain, last 10% ramp down.

: _GR-TRAP  ( phase-fp16 -- w-fp16 )
    DUP
    \ Phase < 0.1: ramp up → w = phase / 0.1 = phase × 10
    0x2E66 FP16-LT IF   \ 0.1 in FP16
        10 INT>FP16 FP16-MUL
        DUP FP16-POS-ONE FP16-GT IF DROP FP16-POS-ONE THEN
        EXIT
    THEN
    DUP
    \ Phase > 0.9: ramp down → w = (1 - phase) / 0.1 = (1-phase)*10
    0x3B33 FP16-GT IF   \ 0.9 in FP16
        FP16-POS-ONE SWAP FP16-SUB  10 INT>FP16 FP16-MUL
        DUP FP16-POS-ONE FP16-GT IF DROP FP16-POS-ONE THEN
        EXIT
    THEN
    DROP FP16-POS-ONE ;  \ flat region

\ =====================================================================
\  Internal: envelope value  ( phase env-type -- w )
\ =====================================================================

: _GR-ENV  ( phase type -- w )
    CASE
        0 OF _GR-HANN ENDOF        \ Hann
        1 OF _GR-TRAP ENDOF        \ trapezoidal
        DROP FP16-POS-ONE EXIT     \ flat (type 2 or any other)
    ENDCASE ;

\ =====================================================================
\  Internal: compute scheduling period from density
\ =====================================================================
\  period = rate / density (in frames)

: _GR-PERIOD  ( desc -- )
    _GR-TMP !
    _GR-TMP @ GD.DENS @  FP16-POS-ZERO FP16-GT IF
        _GR-TMP @ GD.RATE @ INT>FP16
        _GR-TMP @ GD.DENS @ FP16-DIV FP16>INT  1 MAX
        _GR-TMP @ GD.SPER !
    ELSE
        99999 _GR-TMP @ GD.SPER !     \ very long → effectively no grains
    THEN ;

\ =====================================================================
\  Internal: scatter rand — return FP16 random in [-scatter, +scatter]
\ =====================================================================
\  ( scatter-fp16 desc -- rand-fp16 )

VARIABLE _GR-SC-V

: _GR-SCATTER  ( scatter desc -- rand )
    GD.NENG @ NOISE-SAMPLE   \ [-1, +1]
    SWAP                      \ scatter rand
    FP16-MUL ;                \ ± scatter

\ =====================================================================
\  Internal: trigger a new grain
\ =====================================================================

VARIABLE _GR-TG-D
VARIABLE _GR-TG-G
VARIABLE _GR-TG-BF
VARIABLE _GR-TG-GF
VARIABLE _GR-TG-POS
VARIABLE _GR-TG-PITCH
VARIABLE _GR-TG-AMP
VARIABLE _GR-TG-STEP

: _GR-TRIGGER  ( desc -- )
    _GR-TG-D !

    \ Find a free grain slot; if none, steal highest env-phase
    -1 _GR-TG-G !   \ slot index (-1 = not found)
    FP16-POS-ZERO _GR-TMP !  \ track highest env-phase for steal

    _GR-TG-D @ GD.POOL @  _GR-POOL !

    _GR-POOL-SIZE 0 DO
        _GR-POOL @ I _GR-GRAIN  ( g )
        DUP GS.ACT W@ 0= IF
            I _GR-TG-G !            \ free slot found
            DROP LEAVE
        THEN
        \ Track most-complete grain for potential steal
        DUP GS.EPH W@  _GR-TMP @ FP16-GT IF
            DUP GS.EPH W@  _GR-TMP !
            I _GR-TG-G !
        THEN
        DROP
    LOOP

    \ _GR-TG-G @ now holds slot index
    _GR-TG-G @ -1 = IF EXIT THEN   \ no pool (shouldn't happen with 16 slots)

    _GR-POOL @ _GR-TG-G @ _GR-GRAIN  _GR-TG-G !   \ now pointer to grain struct

    \ Compute grain position with scatter
    _GR-TG-D @ GD.POS @                \ base position
    _GR-TG-D @ GD.PSCTR @
    FP16-POS-ZERO FP16-GT IF
        _GR-TG-D @ GD.PSCTR @ _GR-TG-D @ _GR-SCATTER FP16-ADD
    THEN
    \ Clamp to [0, 1)
    DUP FP16-POS-ZERO FP16-LT IF DROP FP16-POS-ZERO THEN
    DUP FP16-POS-ONE FP16-GE IF DROP 0x3BFF THEN   \ slightly below 1.0
    _GR-TG-POS !

    \ Compute pitch (src position step per output sample)
    \ step = pitch_shift × (src_sample_rate / dst_rate) / src_len_frames
    \ Simplified: step = pitch / src_len_frames (assumes same rate)
    _GR-TG-D @ GD.PITCH @
    _GR-TG-D @ GD.PTSCTR @ FP16-POS-ZERO FP16-GT IF
        _GR-TG-D @ GD.PTSCTR @ _GR-TG-D @ _GR-SCATTER FP16-ADD
        DUP FP16-POS-ZERO FP16-LT IF DROP FP16-POS-ZERO THEN
    THEN
    _GR-TG-D @ GD.SRC @ PCM-LEN INT>FP16 FP16-DIV
    _GR-TG-PITCH !   \ normalized step in src per dst sample

    \ Amplitude with scatter
    FP16-POS-ONE
    _GR-TG-D @ GD.ASCTR @ FP16-POS-ZERO FP16-GT IF
        _GR-TG-D @ GD.ASCTR @ _GR-TG-D @ _GR-SCATTER FP16-ADD
        DUP FP16-POS-ZERO FP16-LT IF DROP FP16-POS-ZERO THEN
        DUP FP16-POS-ONE  FP16-GT IF DROP FP16-POS-ONE  THEN
    THEN
    _GR-TG-AMP !

    \ Env step = 1.0 / grain_frames
    _GR-TG-D @ GD.GMS @ _GR-TG-D @ GD.RATE @ * 1000 /  1 MAX  _GR-TG-STEP !
    FP16-POS-ONE _GR-TG-STEP @ INT>FP16 FP16-DIV  _GR-TG-STEP !

    \ Write grain fields
    _GR-TG-POS   @  _GR-TG-G @ GS.SPOS  W!
    _GR-TG-PITCH @  _GR-TG-G @ GS.STEP  W!
    FP16-POS-ZERO   _GR-TG-G @ GS.EPH   W!
    _GR-TG-STEP  @  _GR-TG-G @ GS.ESTEP W!
    _GR-TG-AMP   @  _GR-TG-G @ GS.AMP   W!
    1               _GR-TG-G @ GS.ACT   W!
    _GR-TG-D @ GD.ENV @  _GR-TG-G @ GS.ETYPE W! ;

\ =====================================================================
\  GRAN-CREATE — Allocate granular descriptor
\ =====================================================================
\  ( source-buf rate -- desc )

VARIABLE _GR-CR-SRC
VARIABLE _GR-CR-R

: GRAN-CREATE  ( source-buf rate -- desc )
    _GR-CR-R !  _GR-CR-SRC !

    GRAN-DESC-SIZE ALLOCATE
    0<> ABORT" GRAN-CREATE: desc alloc failed"
    _GR-TMP !

    _GR-CR-SRC @      _GR-TMP @ GD.SRC   !
    1 INT>FP16         _GR-TMP @ GD.DENS  !    \ 1 grain/sec default
    100                _GR-TMP @ GD.GMS   !    \ 100 ms grain
    FP16-POS-HALF      _GR-TMP @ GD.POS   !    \ middle of source
    0x3266             _GR-TMP @ GD.PSCTR !    \ 0.2 pos scatter
    FP16-POS-ONE       _GR-TMP @ GD.PITCH !    \ no pitch shift
    FP16-POS-ZERO      _GR-TMP @ GD.PTSCTR !
    0x3266             _GR-TMP @ GD.ASCTR !    \ 0.2 amp scatter
    0                  _GR-TMP @ GD.ENV   !    \ Hann envelope
    _GR-CR-R @         _GR-TMP @ GD.RATE  !
    0                  _GR-TMP @ GD.SCTR  !

    NOISE-WHITE NOISE-CREATE  _GR-TMP @ GD.NENG !

    \ Allocate grain pool, zero-fill
    _GR-POOL-SIZE _GR-GRAIN-STRIDE *
    ALLOCATE 0<> ABORT" GRAN-CREATE: pool alloc failed"
    DUP _GR-TMP @ GD.POOL !
    _GR-POOL-SIZE _GR-GRAIN-STRIDE * 0 FILL    \ mark all inactive

    _GR-TMP @ _GR-PERIOD     \ compute initial schedule period
    _GR-TMP @ ;

\ =====================================================================
\  GRAN-FREE
\ =====================================================================

: GRAN-FREE  ( desc -- )
    DUP GD.NENG @ NOISE-FREE
    DUP GD.POOL @ FREE
    FREE ;

\ =====================================================================
\  Parameter setters
\ =====================================================================

VARIABLE _GR-SET-D

: GRAN-SOURCE!    ( buf desc -- )    GD.SRC   ! ;
: GRAN-GRAIN!     ( ms desc -- )     GD.GMS   ! ;
: GRAN-POSITION!  ( pos desc -- )    GD.POS   ! ;
: GRAN-PITCH!     ( ratio desc -- )  GD.PITCH ! ;

: GRAN-DENSITY!   ( density desc -- )
    _GR-SET-D !
    _GR-SET-D @ GD.DENS !
    _GR-SET-D @ _GR-PERIOD ;

: GRAN-SCATTER!  ( pos pitch amp desc -- )
    _GR-SET-D !
    _GR-SET-D @ GD.ASCTR  !
    _GR-SET-D @ GD.PTSCTR !
    _GR-SET-D @ GD.PSCTR  ! ;

\ =====================================================================
\  GRAN-RENDER — Schedule and sum grains into output buffer
\ =====================================================================
\  ( buf desc -- )

VARIABLE _GR-RN-D
VARIABLE _GR-RN-BUF
VARIABLE _GR-RN-DPTR
VARIABLE _GR-RN-LEN
VARIABLE _GR-RN-G
VARIABLE _GR-RN-SRCV
VARIABLE _GR-RN-SRCIDX
VARIABLE _GR-RN-ENV
VARIABLE _GR-RN-W

: GRAN-RENDER  ( buf desc -- )
    _GR-RN-D !  _GR-RN-BUF !

    _GR-RN-BUF @ PCM-DATA  _GR-RN-DPTR !
    _GR-RN-BUF @ PCM-LEN   _GR-RN-LEN  !
    _GR-RN-D @ GD.POOL @   _GR-POOL !

    \ Pre-cache source info to avoid per-sample stack gymnastics
    _GR-RN-D @ GD.SRC @  _GR-SRC !
    _GR-SRC @ 0<> IF
        _GR-SRC @ PCM-LEN  _GR-SLEN !
        _GR-SRC @ PCM-DATA _GR-SPTR !
    ELSE
        0 _GR-SLEN !  0 _GR-SPTR !
    THEN

    _GR-RN-LEN @ 0 DO
        FP16-POS-ZERO _GR-ACC !

        \ === Sum all active grains ===
        _GR-POOL-SIZE 0 DO
            _GR-POOL @ I _GR-GRAIN  _GR-RN-G !
            _GR-RN-G @ GS.ACT W@  0<> IF

                \ Get source sample at src-pos
                _GR-SLEN @ 0<> IF
                    _GR-SLEN @ INT>FP16
                    _GR-RN-G @ GS.SPOS W@  FP16-MUL FP16>INT
                    _GR-SLEN @ 1- MIN  0 MAX   _GR-RN-SRCIDX !
                    _GR-SPTR @  _GR-RN-SRCIDX @ 2* +  W@  _GR-RN-SRCV !
                ELSE
                    FP16-POS-ZERO _GR-RN-SRCV !
                THEN

                \ Envelope
                _GR-RN-G @ GS.EPH W@   _GR-RN-G @ GS.ETYPE W@  _GR-ENV
                _GR-RN-G @ GS.AMP W@   FP16-MUL   _GR-RN-W !

                \ Accumulate: src × envelope × amp
                _GR-RN-SRCV @  _GR-RN-W @  FP16-MUL
                _GR-ACC @ FP16-ADD  _GR-ACC !

                \ Advance:  src-pos, env-phase
                _GR-RN-G @ GS.SPOS W@
                _GR-RN-G @ GS.STEP W@  FP16-ADD
                \ Wrap src-pos back to beginning if it overflows
                DUP FP16-POS-ONE FP16-GE IF DROP FP16-POS-ZERO THEN
                _GR-RN-G @ GS.SPOS W!

                _GR-RN-G @ GS.EPH W@
                _GR-RN-G @ GS.ESTEP W@  FP16-ADD
                DUP FP16-POS-ONE FP16-GE IF
                    \ Grain completed
                    DROP
                    0 _GR-RN-G @ GS.ACT W!
                ELSE
                    _GR-RN-G @ GS.EPH W!
                THEN

            THEN
        LOOP

        \ Write sample
        _GR-ACC @  _GR-RN-DPTR @ I 2* + W!

        \ === Grain scheduler ===
        _GR-RN-D @ GD.SCTR @  1 +  DUP
        _GR-RN-D @ GD.SCTR !         \ save incremented counter
        _GR-RN-D @ GD.SPER @  >= IF
            0  _GR-RN-D @ GD.SCTR !  \ reset after trigger
            \ Only trigger if valid source exists
            _GR-RN-D @ GD.SRC @ 0<> IF
                _GR-RN-D @ _GR-TRIGGER
            THEN
        THEN

    LOOP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _sgran-guard

' GS.SPOS         CONSTANT _gs-dotspos-xt
' GS.STEP         CONSTANT _gs-dotstep-xt
' GS.EPH          CONSTANT _gs-doteph-xt
' GS.ESTEP        CONSTANT _gs-dotestep-xt
' GS.AMP          CONSTANT _gs-dotamp-xt
' GS.ACT          CONSTANT _gs-dotact-xt
' GS.ETYPE        CONSTANT _gs-dotetype-xt
' GD.SRC          CONSTANT _gd-dotsrc-xt
' GD.DENS         CONSTANT _gd-dotdens-xt
' GD.GMS          CONSTANT _gd-dotgms-xt
' GD.POS          CONSTANT _gd-dotpos-xt
' GD.PSCTR        CONSTANT _gd-dotpsctr-xt
' GD.PITCH        CONSTANT _gd-dotpitch-xt
' GD.PTSCTR       CONSTANT _gd-dotptsctr-xt
' GD.ASCTR        CONSTANT _gd-dotasctr-xt
' GD.ENV          CONSTANT _gd-dotenv-xt
' GD.RATE         CONSTANT _gd-dotrate-xt
' GD.POOL         CONSTANT _gd-dotpool-xt
' GD.SCTR         CONSTANT _gd-dotsctr-xt
' GD.NENG         CONSTANT _gd-dotneng-xt
' GD.SPER         CONSTANT _gd-dotsper-xt
' GRAN-CREATE     CONSTANT _gran-create-xt
' GRAN-FREE       CONSTANT _gran-free-xt
' GRAN-SOURCE!    CONSTANT _gran-source-s-xt
' GRAN-GRAIN!     CONSTANT _gran-grain-s-xt
' GRAN-POSITION!  CONSTANT _gran-position-s-xt
' GRAN-PITCH!     CONSTANT _gran-pitch-s-xt
' GRAN-DENSITY!   CONSTANT _gran-density-s-xt
' GRAN-SCATTER!   CONSTANT _gran-scatter-s-xt
' GRAN-RENDER     CONSTANT _gran-render-xt

: GS.SPOS         _gs-dotspos-xt _sgran-guard WITH-GUARD ;
: GS.STEP         _gs-dotstep-xt _sgran-guard WITH-GUARD ;
: GS.EPH          _gs-doteph-xt _sgran-guard WITH-GUARD ;
: GS.ESTEP        _gs-dotestep-xt _sgran-guard WITH-GUARD ;
: GS.AMP          _gs-dotamp-xt _sgran-guard WITH-GUARD ;
: GS.ACT          _gs-dotact-xt _sgran-guard WITH-GUARD ;
: GS.ETYPE        _gs-dotetype-xt _sgran-guard WITH-GUARD ;
: GD.SRC          _gd-dotsrc-xt _sgran-guard WITH-GUARD ;
: GD.DENS         _gd-dotdens-xt _sgran-guard WITH-GUARD ;
: GD.GMS          _gd-dotgms-xt _sgran-guard WITH-GUARD ;
: GD.POS          _gd-dotpos-xt _sgran-guard WITH-GUARD ;
: GD.PSCTR        _gd-dotpsctr-xt _sgran-guard WITH-GUARD ;
: GD.PITCH        _gd-dotpitch-xt _sgran-guard WITH-GUARD ;
: GD.PTSCTR       _gd-dotptsctr-xt _sgran-guard WITH-GUARD ;
: GD.ASCTR        _gd-dotasctr-xt _sgran-guard WITH-GUARD ;
: GD.ENV          _gd-dotenv-xt _sgran-guard WITH-GUARD ;
: GD.RATE         _gd-dotrate-xt _sgran-guard WITH-GUARD ;
: GD.POOL         _gd-dotpool-xt _sgran-guard WITH-GUARD ;
: GD.SCTR         _gd-dotsctr-xt _sgran-guard WITH-GUARD ;
: GD.NENG         _gd-dotneng-xt _sgran-guard WITH-GUARD ;
: GD.SPER         _gd-dotsper-xt _sgran-guard WITH-GUARD ;
: GRAN-CREATE     _gran-create-xt _sgran-guard WITH-GUARD ;
: GRAN-FREE       _gran-free-xt _sgran-guard WITH-GUARD ;
: GRAN-SOURCE!    _gran-source-s-xt _sgran-guard WITH-GUARD ;
: GRAN-GRAIN!     _gran-grain-s-xt _sgran-guard WITH-GUARD ;
: GRAN-POSITION!  _gran-position-s-xt _sgran-guard WITH-GUARD ;
: GRAN-PITCH!     _gran-pitch-s-xt _sgran-guard WITH-GUARD ;
: GRAN-DENSITY!   _gran-density-s-xt _sgran-guard WITH-GUARD ;
: GRAN-SCATTER!   _gran-scatter-s-xt _sgran-guard WITH-GUARD ;
: GRAN-RENDER     _gran-render-xt _sgran-guard WITH-GUARD ;
[THEN] [THEN]
