\ poly.f — Polyphonic voice manager with intelligent voice stealing
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Wraps N identical synth.f voices into a polyphonic instrument with:
\   - Automatic voice allocation (quietest-steal policy)
\   - Per-voice biquad filter state save/restore
\   - Master output buffer (sum of all active voices)
\
\ One POLY descriptor manages N synth voices.  All voices share the
\ same oscillator shapes, sample rate, and block size.  Per-voice
\ parameters (cutoff, reso, detune) can be set via POLY-VOICE.
\
\ Memory: descriptor (48 bytes) + voice pointer array + filter state
\         array + master PCM buffer + N × synth voice + sub-objects.
\
\ Prefix: POLY-   (public API)
\         _PO-    (internals)
\
\ Load with:   REQUIRE audio/poly.f
\
\ === Public API ===
\   POLY-CREATE       ( n shape1 shape2 rate frames -- poly )
\   POLY-FREE         ( poly -- )
\   POLY-NOTE-ON      ( freq vel poly -- )
\   POLY-NOTE-OFF-ALL ( poly -- )
\   POLY-RENDER       ( poly -- buf )
\   POLY-VOICE        ( idx poly -- voice )
\   POLY-COUNT        ( poly -- n )
\   POLY-CUTOFF!      ( freq poly -- )
\   POLY-RESO!        ( q poly -- )

REQUIRE fp16-ext.f
REQUIRE audio/pcm.f
REQUIRE audio/osc.f
REQUIRE audio/env.f
REQUIRE audio/synth.f

PROVIDED akashic-audio-poly

\ =====================================================================
\  Descriptor layout  (6 cells = 48 bytes)
\ =====================================================================
\
\  +0   n-voices     Number of synth voices
\  +8   voices       Pointer to array of synth voice descriptors
\  +16  states       Pointer to filter state array (2 FP16 per voice)
\  +24  master-buf   Pointer to master output PCM buffer
\  +32  frames       Block size in frames
\  +40  rate         Sample rate (integer)

48 CONSTANT _PO-DESC-SIZE

: PO.NV     ( p -- addr )  ;
: PO.VOICES ( p -- addr )  8 + ;
: PO.STATES ( p -- addr )  16 + ;
: PO.MASTER ( p -- addr )  24 + ;
: PO.FRAMES ( p -- addr )  32 + ;
: PO.RATE   ( p -- addr )  40 + ;

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _PO-TMP     \ descriptor pointer
VARIABLE _PO-NV      \ n-voices
VARIABLE _PO-S1      \ shape1
VARIABLE _PO-S2      \ shape2
VARIABLE _PO-RT      \ rate
VARIABLE _PO-FR      \ frames
VARIABLE _PO-VP      \ voices array pointer
VARIABLE _PO-SP      \ states array pointer
VARIABLE _PO-SRC     \ source buffer for accumulate
VARIABLE _PO-DST     \ dest buffer for accumulate
VARIABLE _PO-IDX     \ index of selected voice
VARIABLE _PO-LOW     \ lowest envelope level seen
VARIABLE _PO-FREQ    \ freq for note-on
VARIABLE _PO-VEL     \ vel for note-on / temp for setters

\ =====================================================================
\  POLY-CREATE — Create polyphonic voice pool
\ =====================================================================
\  ( n shape1 shape2 rate frames -- poly )

: POLY-CREATE  ( n shape1 shape2 rate frames -- poly )
    _PO-FR ! _PO-RT ! _PO-S2 ! _PO-S1 ! _PO-NV !

    \ Validate minimum 1 voice
    _PO-NV @ 1 < ABORT" POLY-CREATE: need >= 1 voice"

    \ Allocate descriptor
    _PO-DESC-SIZE ALLOCATE
    0<> ABORT" POLY-CREATE: alloc fail"
    _PO-TMP !

    _PO-NV @ _PO-TMP @ PO.NV     !
    _PO-FR @ _PO-TMP @ PO.FRAMES !
    _PO-RT @ _PO-TMP @ PO.RATE   !

    \ Allocate voice pointer array (n-voices cells)
    _PO-NV @ CELLS ALLOCATE
    0<> ABORT" POLY-CREATE: voices alloc fail"
    _PO-VP !
    _PO-VP @ _PO-TMP @ PO.VOICES !

    \ Allocate filter state array (2 cells per voice)
    _PO-NV @ 2 * CELLS ALLOCATE
    0<> ABORT" POLY-CREATE: states alloc fail"
    _PO-SP !
    _PO-SP @ _PO-TMP @ PO.STATES !

    \ Create each voice and zero its filter state
    _PO-NV @ 0 DO
        _PO-S1 @ _PO-S2 @ _PO-RT @ _PO-FR @
        SYNTH-CREATE
        _PO-VP @ I CELLS + !
        FP16-POS-ZERO _PO-SP @ I 2 * CELLS + !
        FP16-POS-ZERO _PO-SP @ I 2 * 1+ CELLS + !
    LOOP

    \ Allocate master output buffer (mono, 16-bit)
    _PO-FR @ _PO-RT @ 16 1 PCM-ALLOC
    _PO-TMP @ PO.MASTER !

    _PO-TMP @ ;

\ =====================================================================
\  POLY-FREE — Free all voices and descriptor
\ =====================================================================

: POLY-FREE  ( poly -- )
    _PO-TMP !
    \ Free each synth voice
    _PO-TMP @ PO.NV @ 0 DO
        _PO-TMP @ PO.VOICES @ I CELLS + @ SYNTH-FREE
    LOOP
    \ Free arrays and master buffer
    _PO-TMP @ PO.VOICES @ FREE
    _PO-TMP @ PO.STATES @ FREE
    _PO-TMP @ PO.MASTER @ PCM-FREE
    _PO-TMP @ FREE ;

\ =====================================================================
\  POLY-VOICE — Get voice descriptor by index
\ =====================================================================

: POLY-VOICE  ( idx poly -- voice )
    PO.VOICES @ SWAP CELLS + @ ;

\ =====================================================================
\  POLY-COUNT — Number of voices
\ =====================================================================

: POLY-COUNT  ( poly -- n )  PO.NV @ ;

\ =====================================================================
\  Internal: Find quietest voice (lowest amp envelope level)
\ =====================================================================
\  Uses ENV-LEVEL on each voice's amplitude envelope.
\  Prefers idle/done voices (level=0) over active ones.

: _PO-FIND-QUIETEST  ( poly -- idx )
    _PO-TMP !

    \ First pass: prefer IDLE or DONE voices (guaranteed inactive)
    -1 _PO-IDX !
    _PO-TMP @ PO.NV @ 0 DO
        _PO-TMP @ PO.VOICES @ I CELLS + @
        SY.AENV @ E.PHASE @
        DUP ENV-IDLE = SWAP ENV-DONE = OR IF
            _PO-IDX @ -1 = IF
                I _PO-IDX !
            THEN
        THEN
    LOOP

    _PO-IDX @ -1 <> IF _PO-IDX @ EXIT THEN

    \ No idle voices — steal the one with lowest envelope level
    0 _PO-IDX !
    0x7BFF _PO-LOW !            \ FP16 max finite positive

    _PO-TMP @ PO.NV @ 0 DO
        _PO-TMP @ PO.VOICES @ I CELLS + @
        SY.AENV @ ENV-LEVEL
        DUP _PO-LOW @ FP16-LT IF
            _PO-LOW !
            I _PO-IDX !
        ELSE
            DROP
        THEN
    LOOP
    _PO-IDX @ ;

\ =====================================================================
\  POLY-NOTE-ON — Allocate voice and trigger note
\ =====================================================================
\  Steals the quietest voice.  Resets its filter state and triggers
\  SYNTH-NOTE-ON on the stolen voice.

: POLY-NOTE-ON  ( freq vel poly -- )
    _PO-TMP !
    _PO-VEL !
    _PO-FREQ !

    \ Find the quietest voice to steal
    _PO-TMP @ _PO-FIND-QUIETEST
    _PO-IDX !

    \ Reset filter state for this voice
    _PO-TMP @ PO.STATES @ _PO-SP !
    FP16-POS-ZERO _PO-SP @ _PO-IDX @ 2 * CELLS + !
    FP16-POS-ZERO _PO-SP @ _PO-IDX @ 2 * 1+ CELLS + !

    \ Trigger note on the stolen voice
    _PO-FREQ @
    _PO-VEL @
    _PO-TMP @ PO.VOICES @ _PO-IDX @ CELLS + @
    SYNTH-NOTE-ON ;

\ =====================================================================
\  POLY-NOTE-OFF-ALL — Release all voices
\ =====================================================================

: POLY-NOTE-OFF-ALL  ( poly -- )
    _PO-TMP !
    _PO-TMP @ PO.NV @ 0 DO
        _PO-TMP @ PO.VOICES @ I CELLS + @ SYNTH-NOTE-OFF
    LOOP ;

\ =====================================================================
\  Internal: Accumulate source buffer into destination buffer
\ =====================================================================
\  Adds each FP16 sample from src to dst (frame by frame, mono).

: _PO-ACCUM  ( src dst -- )
    _PO-DST ! _PO-SRC !
    _PO-SRC @ PCM-LEN 0 DO
        I _PO-SRC @ PCM-FRAME@
        I _PO-DST @ PCM-FRAME@
        FP16-ADD
        I _PO-DST @ PCM-FRAME!
    LOOP ;

\ =====================================================================
\  POLY-RENDER — Render all voices and mix to master buffer
\ =====================================================================
\  For each voice:
\    1. Load per-voice filter state into synth globals
\    2. Call SYNTH-RENDER
\    3. Save filter state back to per-voice array
\    4. Accumulate voice output into master buffer
\  Returns the master PCM buffer pointer.

: POLY-RENDER  ( poly -- buf )
    _PO-TMP !

    \ Clear master buffer
    _PO-TMP @ PO.MASTER @ PCM-CLEAR

    \ Cache states array pointer
    _PO-TMP @ PO.STATES @ _PO-SP !

    _PO-TMP @ PO.NV @ 0 DO
        \ Load filter state for voice I
        _PO-SP @ I 2 * CELLS + @
        _PO-SP @ I 2 * 1+ CELLS + @
        SYNTH-LOAD-FILT

        \ Render voice
        _PO-TMP @ PO.VOICES @ I CELLS + @ SYNTH-RENDER
        _PO-SRC !

        \ Save filter state
        SYNTH-SAVE-FILT
        _PO-SP @ I 2 * 1+ CELLS + !
        _PO-SP @ I 2 * CELLS + !

        \ Accumulate into master
        _PO-SRC @ _PO-TMP @ PO.MASTER @ _PO-ACCUM
    LOOP

    _PO-TMP @ PO.MASTER @ ;

\ =====================================================================
\  Bulk setters — apply to all voices
\ =====================================================================

: POLY-CUTOFF!  ( freq poly -- )
    _PO-TMP !
    _PO-FREQ !
    _PO-TMP @ PO.NV @ 0 DO
        _PO-FREQ @ _PO-TMP @ PO.VOICES @ I CELLS + @ SYNTH-CUTOFF!
    LOOP ;

: POLY-RESO!  ( q poly -- )
    _PO-TMP !
    _PO-VEL !                    \ reuse as temp
    _PO-TMP @ PO.NV @ 0 DO
        _PO-VEL @ _PO-TMP @ PO.VOICES @ I CELLS + @ SYNTH-RESO!
    LOOP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _apoly-guard

' PO.NV           CONSTANT _po-dotnv-xt
' PO.VOICES       CONSTANT _po-dotvoices-xt
' PO.STATES       CONSTANT _po-dotstates-xt
' PO.MASTER       CONSTANT _po-dotmaster-xt
' PO.FRAMES       CONSTANT _po-dotframes-xt
' PO.RATE         CONSTANT _po-dotrate-xt
' POLY-CREATE     CONSTANT _poly-create-xt
' POLY-FREE       CONSTANT _poly-free-xt
' POLY-VOICE      CONSTANT _poly-voice-xt
' POLY-COUNT      CONSTANT _poly-count-xt
' POLY-NOTE-ON    CONSTANT _poly-note-on-xt
' POLY-NOTE-OFF-ALL CONSTANT _poly-note-off-all-xt
' POLY-RENDER     CONSTANT _poly-render-xt
' POLY-CUTOFF!    CONSTANT _poly-cutoff-s-xt
' POLY-RESO!      CONSTANT _poly-reso-s-xt

: PO.NV           _po-dotnv-xt _apoly-guard WITH-GUARD ;
: PO.VOICES       _po-dotvoices-xt _apoly-guard WITH-GUARD ;
: PO.STATES       _po-dotstates-xt _apoly-guard WITH-GUARD ;
: PO.MASTER       _po-dotmaster-xt _apoly-guard WITH-GUARD ;
: PO.FRAMES       _po-dotframes-xt _apoly-guard WITH-GUARD ;
: PO.RATE         _po-dotrate-xt _apoly-guard WITH-GUARD ;
: POLY-CREATE     _poly-create-xt _apoly-guard WITH-GUARD ;
: POLY-FREE       _poly-free-xt _apoly-guard WITH-GUARD ;
: POLY-VOICE      _poly-voice-xt _apoly-guard WITH-GUARD ;
: POLY-COUNT      _poly-count-xt _apoly-guard WITH-GUARD ;
: POLY-NOTE-ON    _poly-note-on-xt _apoly-guard WITH-GUARD ;
: POLY-NOTE-OFF-ALL _poly-note-off-all-xt _apoly-guard WITH-GUARD ;
: POLY-RENDER     _poly-render-xt _apoly-guard WITH-GUARD ;
: POLY-CUTOFF!    _poly-cutoff-s-xt _apoly-guard WITH-GUARD ;
: POLY-RESO!      _poly-reso-s-xt _apoly-guard WITH-GUARD ;
[THEN] [THEN]
