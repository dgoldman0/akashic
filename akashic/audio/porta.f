\ porta.f — Monophonic portamento / glide wrapper
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Wraps a single synth.f voice with exponential frequency glide.
\ On each PORTA-TICK (called once per render block), the current
\ frequency approaches the target:
\
\   current = current + (target − current) × speed
\
\ Speed 1.0 = instant snap (no glide).
\ Speed 0.05 ≈ 0.5 s glide at 44100 Hz / 256-frame blocks.
\
\ First note snaps to target.  Subsequent notes glide from wherever
\ the frequency currently is (legato behaviour).
\
\ Memory: descriptor (40 bytes).  Does NOT own the synth voice.
\
\ Prefix: PORTA-   (public API)
\         _PT-     (internals)
\
\ Load with:   REQUIRE audio/porta.f
\
\ === Public API ===
\   PORTA-CREATE   ( voice speed -- porta )
\   PORTA-FREE     ( porta -- )
\   PORTA-NOTE-ON  ( freq vel porta -- )
\   PORTA-NOTE-OFF ( porta -- )
\   PORTA-SPEED!   ( speed porta -- )
\   PORTA-TICK     ( porta -- )
\   PORTA-RENDER   ( porta -- buf )
\   PORTA-FREQ     ( porta -- freq )

REQUIRE fp16-ext.f
REQUIRE audio/osc.f
REQUIRE audio/synth.f

PROVIDED akashic-audio-porta

\ =====================================================================
\  Descriptor layout  (5 cells = 40 bytes)
\ =====================================================================
\
\  +0   voice        Synth voice pointer (NOT owned — caller frees)
\  +8   current-freq Current frequency (FP16 Hz)
\  +16  target-freq  Target frequency (FP16 Hz)
\  +24  glide-speed  Glide coefficient 0.0–1.0 (FP16)
\  +32  is-playing   Flag: 0 = idle, 1 = playing

40 CONSTANT _PT-DESC-SIZE

: PT.VOICE  ( p -- addr )  ;
: PT.CURR   ( p -- addr )  8 + ;
: PT.TARG   ( p -- addr )  16 + ;
: PT.SPEED  ( p -- addr )  24 + ;
: PT.PLAY   ( p -- addr )  32 + ;

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _PT-TMP     \ descriptor pointer
VARIABLE _PT-VOICE   \ voice temp for CREATE
VARIABLE _PT-SPD     \ speed temp for CREATE
VARIABLE _PT-FR      \ freq temp
VARIABLE _PT-VL      \ vel temp

\ =====================================================================
\  PORTA-CREATE — Create portamento wrapper
\ =====================================================================
\  ( voice speed -- porta )
\  voice = existing synth.f voice descriptor (NOT consumed)
\  speed = glide coefficient (FP16, 0.0–1.0; 1.0 = no glide)

: PORTA-CREATE  ( voice speed -- porta )
    _PT-SPD !
    _PT-VOICE !

    _PT-DESC-SIZE ALLOCATE
    0<> ABORT" PORTA-CREATE: alloc fail"
    _PT-TMP !

    _PT-VOICE @    _PT-TMP @ PT.VOICE !
    _PT-SPD @      _PT-TMP @ PT.SPEED !
    FP16-POS-ZERO  _PT-TMP @ PT.CURR  !
    FP16-POS-ZERO  _PT-TMP @ PT.TARG  !
    0              _PT-TMP @ PT.PLAY  !

    _PT-TMP @ ;

\ =====================================================================
\  PORTA-FREE — Free descriptor only (does NOT free the synth voice)
\ =====================================================================

: PORTA-FREE  ( porta -- ) FREE ;

\ =====================================================================
\  PORTA-SPEED! — Set glide speed
\ =====================================================================

: PORTA-SPEED!  ( speed porta -- )  PT.SPEED ! ;

\ =====================================================================
\  PORTA-FREQ — Get current frequency
\ =====================================================================

: PORTA-FREQ  ( porta -- freq )  PT.CURR @ ;

\ =====================================================================
\  PORTA-NOTE-ON — Trigger note with glide
\ =====================================================================
\  First note snaps to target.  Subsequent notes glide.

: PORTA-NOTE-ON  ( freq vel porta -- )
    _PT-TMP !
    _PT-VL !
    _PT-FR !

    \ Set target frequency
    _PT-FR @ _PT-TMP @ PT.TARG !

    \ Snap to target if not currently playing
    _PT-TMP @ PT.PLAY @ 0= IF
        _PT-FR @ _PT-TMP @ PT.CURR !
    THEN

    \ Call SYNTH-NOTE-ON with current freq (not target)
    \ so the osc starts from the current glide position
    _PT-TMP @ PT.CURR @
    _PT-VL @
    _PT-TMP @ PT.VOICE @
    SYNTH-NOTE-ON

    1 _PT-TMP @ PT.PLAY ! ;

\ =====================================================================
\  PORTA-NOTE-OFF — Release the voice
\ =====================================================================

: PORTA-NOTE-OFF  ( porta -- )
    _PT-TMP !
    _PT-TMP @ PT.VOICE @ SYNTH-NOTE-OFF
    0 _PT-TMP @ PT.PLAY ! ;

\ =====================================================================
\  PORTA-TICK — Advance glide by one step
\ =====================================================================
\  Call once per render block, before or via PORTA-RENDER.
\  current = current + (target − current) × speed
\  Then sets osc1 (and osc2 with detune) to the new current freq.

: PORTA-TICK  ( porta -- )
    _PT-TMP !

    \ Compute new current freq
    _PT-TMP @ PT.TARG @ _PT-TMP @ PT.CURR @ FP16-SUB
    _PT-TMP @ PT.SPEED @ FP16-MUL
    _PT-TMP @ PT.CURR @ FP16-ADD
    _PT-TMP @ PT.CURR !

    \ Apply to osc1
    _PT-TMP @ PT.CURR @
    _PT-TMP @ PT.VOICE @ SY.OSC1 @ OSC-FREQ!

    \ Apply to osc2 if present (with detune)
    _PT-TMP @ PT.VOICE @ SY.OSC2 @ ?DUP IF
        \ freq2 = current × (1 + detune_cents/1200)
        _PT-TMP @ PT.VOICE @ SY.DETUNE @
        1200 INT>FP16 FP16-DIV         ( osc2 cents/1200 )
        FP16-POS-ONE FP16-ADD          ( osc2 1+cents/1200 )
        _PT-TMP @ PT.CURR @ FP16-MUL   ( osc2 freq2 )
        SWAP OSC-FREQ!
    THEN ;

\ =====================================================================
\  PORTA-RENDER — Tick glide and render voice
\ =====================================================================
\  Convenience: PORTA-TICK + SYNTH-RENDER in one call.

: PORTA-RENDER  ( porta -- buf )
    DUP PORTA-TICK
    PT.VOICE @ SYNTH-RENDER ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _porta-guard

' PT.VOICE        CONSTANT _pt-dotvoice-xt
' PT.CURR         CONSTANT _pt-dotcurr-xt
' PT.TARG         CONSTANT _pt-dottarg-xt
' PT.SPEED        CONSTANT _pt-dotspeed-xt
' PT.PLAY         CONSTANT _pt-dotplay-xt
' PORTA-CREATE    CONSTANT _porta-create-xt
' PORTA-FREE      CONSTANT _porta-free-xt
' PORTA-SPEED!    CONSTANT _porta-speed-s-xt
' PORTA-FREQ      CONSTANT _porta-freq-xt
' PORTA-NOTE-ON   CONSTANT _porta-note-on-xt
' PORTA-NOTE-OFF  CONSTANT _porta-note-off-xt
' PORTA-TICK      CONSTANT _porta-tick-xt
' PORTA-RENDER    CONSTANT _porta-render-xt

: PT.VOICE        _pt-dotvoice-xt _porta-guard WITH-GUARD ;
: PT.CURR         _pt-dotcurr-xt _porta-guard WITH-GUARD ;
: PT.TARG         _pt-dottarg-xt _porta-guard WITH-GUARD ;
: PT.SPEED        _pt-dotspeed-xt _porta-guard WITH-GUARD ;
: PT.PLAY         _pt-dotplay-xt _porta-guard WITH-GUARD ;
: PORTA-CREATE    _porta-create-xt _porta-guard WITH-GUARD ;
: PORTA-FREE      _porta-free-xt _porta-guard WITH-GUARD ;
: PORTA-SPEED!    _porta-speed-s-xt _porta-guard WITH-GUARD ;
: PORTA-FREQ      _porta-freq-xt _porta-guard WITH-GUARD ;
: PORTA-NOTE-ON   _porta-note-on-xt _porta-guard WITH-GUARD ;
: PORTA-NOTE-OFF  _porta-note-off-xt _porta-guard WITH-GUARD ;
: PORTA-TICK      _porta-tick-xt _porta-guard WITH-GUARD ;
: PORTA-RENDER    _porta-render-xt _porta-guard WITH-GUARD ;
[THEN] [THEN]
