\ syn/additive.f — Harmonic additive synthesis with spectral morphing
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Models a sound as a sum of harmonic partials (integer multiples of a
\ fundamental frequency), each with an independently controllable and
\ morphable amplitude.  This is the mathematical dual of subtractive
\ synthesis: instead of filtering away from a rich source, you build up
\ from pure sines.
\
\ Each harmonic has:
\   • A current amplitude (what it is right now)
\   • A target amplitude (what it is morphing toward)
\   • A morph rate (frames to complete the transition)
\
\ Calling ADD-RENDER continuously produces output where the harmonic
\ balance evolves over time.  ADD-MORPH! schedules per-harmonic
\ amplitude moves.  This is enough to fake:
\   - Organ drawbars (instant harmonic level changes)
\   - Vowel synthesis (formant-like partial emphasis)
\   - Evolving pads (slow morphs across many cycles)
\   - Piano-like tones (fast bright attack, slow warm decay) via
\     setting all harmonics, then scheduling them down over time
\   - Additive brass (bright 1/n harmonics with fast attack)
\
\ Output:
\   ADD-RENDER fills a caller-supplied buffer.
\   Call in a render loop for continuous pitched output.
\   Change ADD-FUND! or ADD-MORPH! between calls as desired.
\
\ Prefix: ADD-   (public API)
\         _AD-   (internals)
\
\ Load with:   REQUIRE audio/syn/additive.f

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE audio/pcm.f

PROVIDED akashic-syn-additive

\ =====================================================================
\  Descriptor layout  (8 cells = 64 bytes base)
\ =====================================================================
\
\  +0   n-harmonics   Number of harmonics (integer, 1–16)
\  +8   fundamental   Fundamental frequency Hz (FP16)
\  +16  rate          Sample rate Hz (integer)
\  +24  harm-ptr      Pointer to harmonic array
\  +32–63  (reserved)
\
\ Per-harmonic struct (16 bytes = 2 cells):
\  +0   amp-cur       Current amplitude (FP16)
\  +2   amp-tgt       Target amplitude (FP16)
\  +4   amp-start     Amplitude at morph start (FP16)
\  +6   morph-rem     Frames remaining in morph (int16)
\  +8   phase         Current phase 0.0–1.0 (FP16)
\  +10  pinc          Phase increment per sample (FP16)
\  +12  morph-tot     Total frames for current morph (int16)
\  +14  (padding)

64 CONSTANT ADD-DESC-SIZE
16 CONSTANT _AD-HARM-STRIDE

: AD.NHARM   ( desc -- addr )  ;
: AD.FUND    ( desc -- addr )  8 + ;
: AD.RATE    ( desc -- addr )  16 + ;
: AD.HPTR    ( desc -- addr )  24 + ;

\ Per-harmonic accessors ( h-base -- addr )
: AH.ACUR    ( h -- addr )  ;
: AH.ATGT    ( h -- addr )  2 + ;
: AH.ASTART  ( h -- addr )  4 + ;
: AH.MREM    ( h -- addr )  6 + ;
: AH.PHASE   ( h -- addr )  8 + ;
: AH.PINC    ( h -- addr )  10 + ;
: AH.MTOT    ( h -- addr )  12 + ;

\ Harmonic base by index 0-based  ( desc i -- h-base )
: _AD-HARM   ( desc i -- h-base )
    _AD-HARM-STRIDE * SWAP AD.HPTR @ + ;

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _AD-TMP
VARIABLE _AD-RATE
VARIABLE _AD-I
VARIABLE _AD-HB     \ harmonic base
VARIABLE _AD-ACC
VARIABLE _AD-SMP
VARIABLE _AD-K      \ harmonic number 1-based

\ =====================================================================
\  ADD-CREATE — Allocate descriptor
\ =====================================================================
\  ( n-harmonics rate -- desc )
\  All harmonic amplitudes start at 0.

VARIABLE _AD-CR-N
VARIABLE _AD-CR-R

: ADD-CREATE  ( n-harmonics rate -- desc )
    _AD-CR-R !  _AD-CR-N !

    ADD-DESC-SIZE ALLOCATE
    0<> ABORT" ADD-CREATE: desc alloc failed"
    _AD-TMP !

    _AD-CR-N @ _AD-TMP @ AD.NHARM !
    FP16-POS-ZERO _AD-TMP @ AD.FUND !
    _AD-CR-R @ _AD-TMP @ AD.RATE  !

    \ Allocate harmonic array (n × 16 bytes), zero-filled
    _AD-CR-N @ _AD-HARM-STRIDE *
    ALLOCATE 0<> ABORT" ADD-CREATE: harm alloc failed"
    DUP _AD-TMP @ AD.HPTR !
    _AD-CR-N @ _AD-HARM-STRIDE * 0 FILL

    _AD-TMP @ ;

\ =====================================================================
\  ADD-FREE
\ =====================================================================

: ADD-FREE  ( desc -- )
    DUP AD.HPTR @ FREE
    FREE ;

\ =====================================================================
\  ADD-FUND! — Set fundamental, recompute all phase increments
\ =====================================================================
\  ( freq-fp16 desc -- )

VARIABLE _AD-FN-D

: ADD-FUND!  ( freq desc -- )
    _AD-FN-D !
    _AD-FN-D @ AD.FUND !
    _AD-FN-D @ AD.RATE @ _AD-RATE !

    _AD-FN-D @ AD.NHARM @ 0 ?DO
        _AD-FN-D @ I _AD-HARM  _AD-HB !

        \ pinc_k = (k+1) * fund / rate  (k is 0-based, harmonic is k+1)
        I 1 + INT>FP16
        _AD-FN-D @ AD.FUND @ FP16-MUL
        _AD-RATE @ INT>FP16 FP16-DIV
        _AD-HB @ AH.PINC W!
    LOOP ;

\ =====================================================================
\  ADD-HARMONIC! — Set harmonic amplitude immediately (no morph)
\ =====================================================================
\  ( amp i desc -- )  i is 0-based

: ADD-HARMONIC!  ( amp i desc -- )
    _AD-TMP !
    _AD-TMP @ AD.NHARM @ 1- MIN 0 MAX  \ clamp i
    _AD-TMP @ SWAP _AD-HARM  _AD-HB !
    DUP _AD-HB @ AH.ACUR W!
    DUP _AD-HB @ AH.ATGT W!
    DUP _AD-HB @ AH.ASTART W!
    DROP
    0 _AD-HB @ AH.MTOT W!
    0 _AD-HB @ AH.MREM W! ;

\ =====================================================================
\  ADD-MORPH! — Schedule amplitude transition for harmonic i
\ =====================================================================
\  ( amp ms i desc -- )
\  Harmonic i will transition from its current amplitude to amp
\  over ms milliseconds.
\
\  Uses per-block lerp instead of per-sample step accumulation.
\  Stores astart (current amp), atgt, mtot, mrem.  At each
\  ADD-RENDER call, acur is recomputed as:
\      frac = (mtot - mrem) / mtot
\      acur = astart + frac × (atgt - astart)
\  This avoids FP16 underflow when the per-sample step would
\  be smaller than FP16 minimum normal (~6.1e-5).

VARIABLE _AD-MO-D
VARIABLE _AD-MO-MS
VARIABLE _AD-MO-AMP
VARIABLE _AD-MO-FRAMES

: ADD-MORPH!  ( amp ms i desc -- )
    _AD-MO-D !
    _AD-MO-D @ AD.NHARM @ 1- MIN 0 MAX
    _AD-MO-D @ SWAP _AD-HARM  _AD-HB !

    _AD-MO-MS !  _AD-MO-AMP !

    _AD-MO-MS @ _AD-MO-D @ AD.RATE @ * 1000 /  _AD-MO-FRAMES !

    \ Snapshot current amplitude as morph start point
    _AD-HB @ AH.ACUR W@  _AD-HB @ AH.ASTART W!

    _AD-MO-AMP @ _AD-HB @ AH.ATGT W!

    \ Clamp total frames to int16 max (32767)
    _AD-MO-FRAMES @ 1 MAX 32767 MIN
    DUP _AD-HB @ AH.MTOT W!
        _AD-HB @ AH.MREM W! ;

\ =====================================================================
\  ADD-RENDER — Fill buffer, advance morphs and phases
\ =====================================================================
\  ( buf desc -- )
\
\  Morph strategy: per-block lerp.  At the START of each call we
\  recompute acur for every morphing harmonic as:
\      elapsed = mtot - mrem
\      frac = elapsed / mtot        (both ints → FP16, always representable)
\      acur = astart + frac × (atgt - astart)
\      mrem -= buf-len, clamp to 0
\  Then the inner per-sample loop just reads the constant acur.
\  This avoids accumulating a sub-FP16 step per sample.

VARIABLE _AD-RN-D
VARIABLE _AD-RN-BUF
VARIABLE _AD-RN-DPTR
VARIABLE _AD-RN-LEN
VARIABLE _AD-RN-N

: ADD-RENDER  ( buf desc -- )
    _AD-RN-D !  _AD-RN-BUF !

    _AD-RN-D @ AD.NHARM  @ _AD-RN-N    !
    _AD-RN-BUF @ PCM-DATA  _AD-RN-DPTR !
    _AD-RN-BUF @ PCM-LEN   _AD-RN-LEN  !

    \ === Per-block morph pass ===
    _AD-RN-N @ 0 ?DO
        _AD-RN-D @ I _AD-HARM  _AD-HB !

        _AD-HB @ AH.MREM W@  0> IF
            \ frac = elapsed / mtot
            _AD-HB @ AH.MTOT W@  _AD-HB @ AH.MREM W@ -  \ elapsed
            INT>FP16
            _AD-HB @ AH.MTOT W@ INT>FP16  FP16-DIV       \ frac
            \ acur = astart + frac × (atgt - astart)
            _AD-HB @ AH.ATGT W@  _AD-HB @ AH.ASTART W@  FP16-SUB
            FP16-MUL
            _AD-HB @ AH.ASTART W@  FP16-ADD
            _AD-HB @ AH.ACUR W!

            \ Advance mrem by buffer length
            _AD-HB @ AH.MREM W@  _AD-RN-LEN @  -
            DUP 1 < IF
                DROP 0
                \ Snap to target on completion
                _AD-HB @ AH.ATGT W@  _AD-HB @ AH.ACUR W!
            THEN
            _AD-HB @ AH.MREM W!
        THEN
    LOOP

    \ === Per-sample synthesis loop ===
    _AD-RN-LEN @ 0 ?DO
        FP16-POS-ZERO _AD-ACC !

        _AD-RN-N @ 0 ?DO
            _AD-RN-D @ I _AD-HARM  _AD-HB !

            \ Skip silent partials
            _AD-HB @ AH.ACUR W@  FP16-POS-ZERO FP16-GT IF

                \ --- Sine sample ---
                _AD-HB @ AH.PHASE W@ WT-SIN-TABLE WT-LOOKUP
                _AD-HB @ AH.ACUR W@  FP16-MUL
                _AD-ACC @ FP16-ADD  _AD-ACC !

                \ --- Advance phase, wrap at 1.0 ---
                _AD-HB @ AH.PHASE W@
                _AD-HB @ AH.PINC  W@  FP16-ADD
                BEGIN DUP FP16-POS-ONE FP16-GE WHILE FP16-POS-ONE FP16-SUB REPEAT
                _AD-HB @ AH.PHASE W!

            THEN
        LOOP

        _AD-ACC @  _AD-RN-DPTR @ I 2* + W!
    LOOP ;

\ =====================================================================
\  Standard harmonic presets
\ =====================================================================

\ ADD-PRESET-SAW — 1/n amplitude series  ( n desc -- )
\  Load first n harmonics with 1/harmonic_number amplitudes,
\  scaled so total energy is bounded.

VARIABLE _AD-PS-D
VARIABLE _AD-PS-N

: ADD-PRESET-SAW  ( desc -- )
    _AD-PS-D !
    _AD-PS-D @ AD.NHARM @  _AD-PS-N !

    _AD-PS-N @ 0 ?DO
        FP16-POS-ONE  I 1 + INT>FP16 FP16-DIV  \ 1 / (i+1)
        I _AD-PS-D @  ADD-HARMONIC!
    LOOP ;

\ ADD-PRESET-SQUARE — odd harmonics only at 1/n  ( desc -- )

: ADD-PRESET-SQUARE  ( desc -- )
    _AD-PS-D !
    _AD-PS-D @ AD.NHARM @  _AD-PS-N !

    _AD-PS-N @ 0 ?DO
        I 2 MOD 0= IF   \ even index = odd harmonic (1,3,5,...)
            FP16-POS-ONE  I 1 + INT>FP16 FP16-DIV
        ELSE
            FP16-POS-ZERO
        THEN
        I _AD-PS-D @  ADD-HARMONIC!
    LOOP ;

\ ADD-PRESET-ORGAN — approximate pipe organ spectrum  ( desc -- )
\  Draws-style: harmonics 1,2,4 prominent; others quiet.
\  Works best with n-harmonics >= 8.

VARIABLE _AD-PO-D

CREATE _AD-ORGAN-AMPS
    \ Harmonic 1  2     3     4     5     6     7     8
    0x3C00 W,  \ 1.0
    0x3A00 W,  \ 0.75
    0x3400 W,  \ 0.25
    0x3800 W,  \ 0.5
    0x3200 W,  \ 0.15
    0x3000 W,  \ 0.125
    0x2E00 W,  \ 0.1
    0x2C00 W,  \ 0.075

: ADD-PRESET-ORGAN  ( desc -- )
    _AD-PO-D !
    _AD-PO-D @ AD.NHARM @  8 MIN  0 ?DO
        _AD-ORGAN-AMPS I 2* + W@
        I _AD-PO-D @  ADD-HARMONIC!
    LOOP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _sadd-guard

' AD.NHARM        CONSTANT _ad-dotnharm-xt
' AD.FUND         CONSTANT _ad-dotfund-xt
' AD.RATE         CONSTANT _ad-dotrate-xt
' AD.HPTR         CONSTANT _ad-dothptr-xt
' AH.ACUR         CONSTANT _ah-dotacur-xt
' AH.ATGT         CONSTANT _ah-dotatgt-xt
' AH.ASTART       CONSTANT _ah-dotastart-xt
' AH.MREM         CONSTANT _ah-dotmrem-xt
' AH.PHASE        CONSTANT _ah-dotphase-xt
' AH.PINC         CONSTANT _ah-dotpinc-xt
' AH.MTOT         CONSTANT _ah-dotmtot-xt
' ADD-CREATE      CONSTANT _add-create-xt
' ADD-FREE        CONSTANT _add-free-xt
' ADD-FUND!       CONSTANT _add-fund-s-xt
' ADD-HARMONIC!   CONSTANT _add-harmonic-s-xt
' ADD-MORPH!      CONSTANT _add-morph-s-xt
' ADD-RENDER      CONSTANT _add-render-xt
' ADD-PRESET-SAW  CONSTANT _add-preset-saw-xt
' ADD-PRESET-SQUARE CONSTANT _add-preset-square-xt
' ADD-PRESET-ORGAN CONSTANT _add-preset-organ-xt

: AD.NHARM        _ad-dotnharm-xt _sadd-guard WITH-GUARD ;
: AD.FUND         _ad-dotfund-xt _sadd-guard WITH-GUARD ;
: AD.RATE         _ad-dotrate-xt _sadd-guard WITH-GUARD ;
: AD.HPTR         _ad-dothptr-xt _sadd-guard WITH-GUARD ;
: AH.ACUR         _ah-dotacur-xt _sadd-guard WITH-GUARD ;
: AH.ATGT         _ah-dotatgt-xt _sadd-guard WITH-GUARD ;
: AH.ASTART       _ah-dotastart-xt _sadd-guard WITH-GUARD ;
: AH.MREM         _ah-dotmrem-xt _sadd-guard WITH-GUARD ;
: AH.PHASE        _ah-dotphase-xt _sadd-guard WITH-GUARD ;
: AH.PINC         _ah-dotpinc-xt _sadd-guard WITH-GUARD ;
: AH.MTOT         _ah-dotmtot-xt _sadd-guard WITH-GUARD ;
: ADD-CREATE      _add-create-xt _sadd-guard WITH-GUARD ;
: ADD-FREE        _add-free-xt _sadd-guard WITH-GUARD ;
: ADD-FUND!       _add-fund-s-xt _sadd-guard WITH-GUARD ;
: ADD-HARMONIC!   _add-harmonic-s-xt _sadd-guard WITH-GUARD ;
: ADD-MORPH!      _add-morph-s-xt _sadd-guard WITH-GUARD ;
: ADD-RENDER      _add-render-xt _sadd-guard WITH-GUARD ;
: ADD-PRESET-SAW  _add-preset-saw-xt _sadd-guard WITH-GUARD ;
: ADD-PRESET-SQUARE _add-preset-square-xt _sadd-guard WITH-GUARD ;
: ADD-PRESET-ORGAN _add-preset-organ-xt _sadd-guard WITH-GUARD ;
[THEN] [THEN]
