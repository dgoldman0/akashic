\ lfo.f — Low-frequency oscillators (FP16 control signals)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ A thin wrapper around osc.f configured for sub-audio rates.
\ Outputs a control signal (FP16 buffer), not an audio signal.
\ Typical rates 0.1–20 Hz.
\
\ Output formula:  value = center + depth × oscillator_output
\   where oscillator_output is in [-1.0, +1.0].
\   So value ranges from (center - depth) to (center + depth).
\
\ Use cases: vibrato, tremolo, filter wobble, auto-pan.
\
\ Memory: LFO descriptor on heap (32 bytes) + one underlying
\ oscillator descriptor (48 bytes).
\
\ Prefix: LFO-   (public API)
\         _LFO-  (internals)
\
\ Load with:   REQUIRE audio/lfo.f
\
\ === Public API ===
\   LFO-CREATE  ( freq shape depth center rate -- lfo )
\   LFO-FREE    ( lfo -- )            free LFO + underlying osc
\   LFO-FREQ!   ( freq lfo -- )       set LFO rate (Hz, FP16)
\   LFO-DEPTH!  ( depth lfo -- )      set modulation depth (FP16)
\   LFO-CENTER! ( center lfo -- )     set center value (FP16)
\   LFO-SYNC    ( lfo -- )            reset phase (key-sync)
\   LFO-FILL    ( buf lfo -- )        fill buffer with control signal
\   LFO-TICK    ( lfo -- value )      single control sample

REQUIRE audio/osc.f

PROVIDED akashic-audio-lfo

\ =====================================================================
\  LFO descriptor layout  (4 cells = 32 bytes)
\ =====================================================================
\
\  +0   osc     Pointer to underlying oscillator descriptor
\  +8   depth   Modulation depth 0.0–1.0 (FP16)
\  +16  center  Center value (DC offset of modulation, FP16)
\  +24  mode    0=free-run, 1=key-sync

32 CONSTANT LFO-DESC-SIZE

\ =====================================================================
\  Field accessors
\ =====================================================================

: L.OSC    ( lfo -- addr )  ;
: L.DEPTH  ( lfo -- addr )  8 + ;
: L.CENTER ( lfo -- addr )  16 + ;
: L.MODE   ( lfo -- addr )  24 + ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _LFO-TMP
VARIABLE _LFO-BUF

\ =====================================================================
\  LFO-CREATE — Create low-frequency oscillator
\ =====================================================================
\  ( freq shape depth center rate -- lfo )
\  freq   = LFO rate in Hz as FP16 (e.g., 5 INT>FP16 for 5 Hz)
\  shape  = waveform (OSC-SINE, OSC-TRI, etc.)
\  depth  = modulation depth as FP16 (0.0–1.0)
\  center = center value as FP16
\  rate   = audio sample rate in Hz (integer)

VARIABLE _LFO-FREQ
VARIABLE _LFO-SHP
VARIABLE _LFO-DEP
VARIABLE _LFO-CTR
VARIABLE _LFO-RATE

: LFO-CREATE  ( freq shape depth center rate -- lfo )
    _LFO-RATE !
    _LFO-CTR !
    _LFO-DEP !
    _LFO-SHP !
    _LFO-FREQ !

    \ Allocate LFO descriptor
    LFO-DESC-SIZE ALLOCATE
    0<> ABORT" LFO-CREATE: alloc failed"
    _LFO-TMP !

    \ Create underlying oscillator
    _LFO-FREQ @ _LFO-SHP @ _LFO-RATE @
    OSC-CREATE
    _LFO-TMP @ L.OSC !

    _LFO-DEP @ _LFO-TMP @ L.DEPTH  !
    _LFO-CTR @ _LFO-TMP @ L.CENTER !
    0          _LFO-TMP @ L.MODE   !     \ free-run

    _LFO-TMP @ ;

\ =====================================================================
\  LFO-FREE — Free LFO + underlying oscillator
\ =====================================================================

: LFO-FREE  ( lfo -- )
    DUP L.OSC @ OSC-FREE
    FREE ;

\ =====================================================================
\  Setters
\ =====================================================================

: LFO-FREQ!   ( freq lfo -- )   L.OSC @ OSC-FREQ! ;
: LFO-DEPTH!  ( depth lfo -- )  L.DEPTH ! ;
: LFO-CENTER! ( center lfo -- ) L.CENTER ! ;

\ =====================================================================
\  LFO-SYNC — Reset phase (key-sync trigger)
\ =====================================================================

: LFO-SYNC  ( lfo -- )
    L.OSC @ OSC-RESET ;

\ =====================================================================
\  Getters (for test introspection)
\ =====================================================================

: LFO-DEPTH  ( lfo -- depth )  L.DEPTH @ ;
: LFO-CENTER ( lfo -- center ) L.CENTER @ ;

\ =====================================================================
\  LFO-TICK — Generate single control value
\ =====================================================================
\  value = center + depth × osc_sample
\  ( lfo -- value )

: LFO-TICK  ( lfo -- value )
    _LFO-TMP !

    _LFO-TMP @ L.OSC @ OSC-SAMPLE    ( osc-value in [-1,+1] )
    _LFO-TMP @ L.DEPTH @
    FP16-MUL                          ( depth × osc )
    _LFO-TMP @ L.CENTER @
    FP16-ADD ;                        ( center + depth × osc )

\ =====================================================================
\  LFO-FILL — Fill buffer with control signal
\ =====================================================================
\  ( buf lfo -- )

: LFO-FILL  ( buf lfo -- )
    _LFO-TMP !
    _LFO-BUF !

    _LFO-BUF @ PCM-LEN 0 DO
        _LFO-TMP @ LFO-TICK
        I _LFO-BUF @ PCM-FRAME!
    LOOP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _lfo-guard

' L.OSC           CONSTANT _l-dotosc-xt
' L.DEPTH         CONSTANT _l-dotdepth-xt
' L.CENTER        CONSTANT _l-dotcenter-xt
' L.MODE          CONSTANT _l-dotmode-xt
' LFO-CREATE      CONSTANT _lfo-create-xt
' LFO-FREE        CONSTANT _lfo-free-xt
' LFO-FREQ!       CONSTANT _lfo-freq-s-xt
' LFO-DEPTH!      CONSTANT _lfo-depth-s-xt
' LFO-CENTER!     CONSTANT _lfo-center-s-xt
' LFO-SYNC        CONSTANT _lfo-sync-xt
' LFO-DEPTH       CONSTANT _lfo-depth-xt
' LFO-CENTER      CONSTANT _lfo-center-xt
' LFO-TICK        CONSTANT _lfo-tick-xt
' LFO-FILL        CONSTANT _lfo-fill-xt

: L.OSC           _l-dotosc-xt _lfo-guard WITH-GUARD ;
: L.DEPTH         _l-dotdepth-xt _lfo-guard WITH-GUARD ;
: L.CENTER        _l-dotcenter-xt _lfo-guard WITH-GUARD ;
: L.MODE          _l-dotmode-xt _lfo-guard WITH-GUARD ;
: LFO-CREATE      _lfo-create-xt _lfo-guard WITH-GUARD ;
: LFO-FREE        _lfo-free-xt _lfo-guard WITH-GUARD ;
: LFO-FREQ!       _lfo-freq-s-xt _lfo-guard WITH-GUARD ;
: LFO-DEPTH!      _lfo-depth-s-xt _lfo-guard WITH-GUARD ;
: LFO-CENTER!     _lfo-center-s-xt _lfo-guard WITH-GUARD ;
: LFO-SYNC        _lfo-sync-xt _lfo-guard WITH-GUARD ;
: LFO-DEPTH       _lfo-depth-xt _lfo-guard WITH-GUARD ;
: LFO-CENTER      _lfo-center-xt _lfo-guard WITH-GUARD ;
: LFO-TICK        _lfo-tick-xt _lfo-guard WITH-GUARD ;
: LFO-FILL        _lfo-fill-xt _lfo-guard WITH-GUARD ;
[THEN] [THEN]
