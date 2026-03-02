\ osc.f — Band-limited FP16 oscillators
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Generates FP16 audio waveforms into PCM buffers.
\ Supported shapes: sine, square, saw, triangle, pulse.
\ Phase is tracked per-oscillator for continuous output
\ across successive OSC-FILL / OSC-SAMPLE calls.
\
\ All waveform values are FP16 in the range [−1.0, +1.0].
\ PCM buffers should be 16-bit (storing FP16 bit patterns).
\
\ Memory: oscillator descriptors on heap (48 bytes each).
\
\ Prefix: OSC-   (public API)
\         _OSC-  (internals)
\
\ Load with:   REQUIRE audio/osc.f
\
\ === Public API ===
\   OSC-CREATE   ( freq shape rate -- osc )  allocate oscillator
\   OSC-FREE     ( osc -- )                  free descriptor
\   OSC-FREQ!    ( freq osc -- )             set frequency (FP16 Hz)
\   OSC-SHAPE!   ( shape osc -- )            set waveform type
\   OSC-DUTY!    ( duty osc -- )             set pulse duty (FP16)
\   OSC-TABLE!   ( addr osc -- )             set wavetable address
\   OSC-RESET    ( osc -- )                  reset phase to 0
\   OSC-FILL     ( buf osc -- )              fill PCM buffer
\   OSC-ADD      ( buf osc -- )              add to PCM buffer
\   OSC-SAMPLE   ( osc -- value )            one FP16 sample
\
\ Shape constants:
\   OSC-SINE  OSC-SQUARE  OSC-SAW  OSC-TRI  OSC-PULSE

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE audio/wavetable.f
REQUIRE audio/pcm.f

PROVIDED akashic-audio-osc

\ =====================================================================
\  Oscillator descriptor layout  (6 cells = 48 bytes)
\ =====================================================================
\
\  +0   freq    Frequency in Hz (FP16 bit pattern)
\  +8   phase   Phase accumulator 0.0–1.0 (FP16)
\  +16  rate    Sample rate in Hz (integer)
\  +24  shape   Waveform type (integer: 0–4)
\  +32  duty    Pulse duty cycle 0.0–1.0 (FP16)
\  +40  table   Wavetable address or 0

48 CONSTANT OSC-DESC-SIZE

\ Shape constants
0 CONSTANT OSC-SINE
1 CONSTANT OSC-SQUARE
2 CONSTANT OSC-SAW
3 CONSTANT OSC-TRI
4 CONSTANT OSC-PULSE

\ =====================================================================
\  Field accessors
\ =====================================================================

: O.FREQ   ( osc -- addr )  ;
: O.PHASE  ( osc -- addr )  8 + ;
: O.RATE   ( osc -- addr )  16 + ;
: O.SHAPE  ( osc -- addr )  24 + ;
: O.DUTY   ( osc -- addr )  32 + ;
: O.TABLE  ( osc -- addr )  40 + ;

\ =====================================================================
\  FP16 constants for waveform math
\ =====================================================================

0x4000 CONSTANT _OSC-FP16-TWO        \ 2.0
0x4400 CONSTANT _OSC-FP16-FOUR       \ 4.0

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _OSC-TMP      \ oscillator pointer
VARIABLE _OSC-PH       \ current phase (FP16)
VARIABLE _OSC-VAL      \ computed sample value
VARIABLE _OSC-BUF      \ target PCM buffer
VARIABLE _OSC-INC      \ phase increment (FP16)
VARIABLE _OSC-FPTR     \ raw PCM data pointer (fast path)
VARIABLE _OSC-FTAB     \ cached wavetable pointer (fast path)

\ =====================================================================
\  OSC-CREATE — Allocate oscillator descriptor
\ =====================================================================
\  ( freq shape rate -- osc )
\  freq  = frequency in Hz as FP16 (e.g., 440 INT>FP16)
\  shape = waveform type (0–4)
\  rate  = sample rate in Hz as integer (e.g., 44100)

: OSC-CREATE  ( freq shape rate -- osc )
    >R >R                             ( freq )  ( R: rate shape )
    OSC-DESC-SIZE ALLOCATE
    0<> ABORT" OSC-CREATE: alloc failed"
    _OSC-TMP !

    _OSC-TMP @ O.FREQ !              \ freq (FP16)
    FP16-POS-ZERO _OSC-TMP @ O.PHASE !  \ phase = 0.0
    R> DUP _OSC-TMP @ O.SHAPE !      \ shape (keep copy)
    R> _OSC-TMP @ O.RATE  !          \ rate (integer)
    FP16-POS-HALF _OSC-TMP @ O.DUTY  !  \ duty = 0.5 default
    OSC-SINE = IF WT-SIN-TABLE ELSE 0 THEN
    _OSC-TMP @ O.TABLE !             \ sine → wavetable, others → 0

    _OSC-TMP @ ;

\ =====================================================================
\  OSC-FREE — Free descriptor
\ =====================================================================

: OSC-FREE  ( osc -- ) FREE ;

\ =====================================================================
\  Setters
\ =====================================================================

: OSC-FREQ!   ( freq osc -- )  O.FREQ  ! ;
: OSC-SHAPE!  ( shape osc -- )
    _OSC-TMP !
    DUP _OSC-TMP @ O.SHAPE !
    OSC-SINE = IF WT-SIN-TABLE ELSE 0 THEN
    _OSC-TMP @ O.TABLE ! ;
: OSC-DUTY!   ( duty osc -- )  O.DUTY  ! ;
: OSC-TABLE!  ( addr osc -- )  O.TABLE ! ;
: OSC-RESET   ( osc -- )       FP16-POS-ZERO SWAP O.PHASE ! ;

\ =====================================================================
\  Getters (for test introspection)
\ =====================================================================

: OSC-FREQ    ( osc -- freq )  O.FREQ  @ ;
: OSC-PHASE   ( osc -- phase ) O.PHASE @ ;
: OSC-RATE    ( osc -- rate )  O.RATE  @ ;
: OSC-SHAPE   ( osc -- shape ) O.SHAPE @ ;
: OSC-DUTY    ( osc -- duty )  O.DUTY  @ ;

\ =====================================================================
\  Internal: generate one waveform sample from phase
\ =====================================================================
\  _OSC-GEN-SHAPE ( phase shape duty -- value )
\  phase = FP16 in [0.0, 1.0)
\  shape = integer 0–4
\  duty  = FP16 (only used for pulse)
\  value = FP16 in [-1.0, +1.0]

VARIABLE _OSC-GEN-PH
VARIABLE _OSC-GEN-DU

: _OSC-GEN-SHAPE  ( phase shape duty -- value )
    _OSC-GEN-DU !
    SWAP _OSC-GEN-PH !
    CASE
        0 OF  \ sine: sin(phase × 2π)
            _OSC-GEN-PH @ TRIG-2PI FP16-MUL TRIG-SIN
        ENDOF
        1 OF  \ square: phase < 0.5 → +1, else −1
            _OSC-GEN-PH @ FP16-POS-HALF FP16-LT IF
                FP16-POS-ONE
            ELSE
                FP16-NEG-ONE
            THEN
        ENDOF
        2 OF  \ saw: phase × 2 − 1
            _OSC-GEN-PH @ _OSC-FP16-TWO FP16-MUL
            FP16-POS-ONE FP16-SUB
        ENDOF
        3 OF  \ triangle: 4 × |phase − 0.5| − 1
            _OSC-GEN-PH @ FP16-POS-HALF FP16-SUB FP16-ABS
            _OSC-FP16-FOUR FP16-MUL
            FP16-POS-ONE FP16-SUB
        ENDOF
        4 OF  \ pulse: phase < duty → +1, else −1
            _OSC-GEN-PH @ _OSC-GEN-DU @ FP16-LT IF
                FP16-POS-ONE
            ELSE
                FP16-NEG-ONE
            THEN
        ENDOF
        \ default: silence
        FP16-POS-ZERO SWAP
    ENDCASE ;

\ =====================================================================
\  OSC-SAMPLE — Generate one FP16 sample, advance phase
\ =====================================================================
\  ( osc -- value )

: OSC-SAMPLE  ( osc -- value )
    _OSC-TMP !

    \ Read current phase
    _OSC-TMP @ O.PHASE @  _OSC-PH !

    \ Generate sample — wavetable fast path or shape dispatch
    _OSC-TMP @ O.TABLE @ DUP IF
        _OSC-PH @ SWAP WT-LERP
    ELSE
        DROP
        _OSC-PH @
        _OSC-TMP @ O.SHAPE @
        _OSC-TMP @ O.DUTY @
        _OSC-GEN-SHAPE
    THEN
    _OSC-VAL !

    \ Compute phase increment: freq / rate (both as FP16)
    _OSC-TMP @ O.FREQ @
    _OSC-TMP @ O.RATE @ INT>FP16
    FP16-DIV
    _OSC-INC !

    \ Advance phase
    _OSC-PH @ _OSC-INC @ FP16-ADD

    \ Wrap: if phase >= 1.0, subtract 1.0
    DUP FP16-POS-ONE FP16-GE IF
        FP16-POS-ONE FP16-SUB
    THEN
    _OSC-TMP @ O.PHASE !

    _OSC-VAL @ ;

\ =====================================================================
\  OSC-FILL — Fill PCM buffer with oscillator output
\ =====================================================================
\  ( buf osc -- )
\  Writes one FP16 sample per frame (mono, channel 0).
\  Fast path when wavetable is set: hoists freq→inc computation,
\  uses direct W! instead of PCM-FRAME! (~2× fewer Forth words).

: OSC-FILL  ( buf osc -- )
    _OSC-TMP !
    _OSC-BUF !

    _OSC-TMP @ O.TABLE @ DUP IF
        _OSC-FTAB !

        \ Try block mode: compute integer phase increment
        _OSC-TMP @ O.FREQ @
        _OSC-TMP @ O.RATE @
        WT-BLOCK-INC DUP IF
            \ ---- Block mode (integer phase, truncating lookup) ----
            _OSC-INC !   \ integer inc
            _OSC-TMP @ O.PHASE @ WT-PH>INT   \ convert FP16 phase → int
            _OSC-INC @
            _OSC-BUF @ PCM-LEN
            _OSC-FTAB @
            _OSC-BUF @ PCM-DATA
            WT-BLOCK-FILL                     \ → phase'
            WT-INT>PH                         \ convert back to FP16
            _OSC-TMP @ O.PHASE !
        ELSE
            \ ---- Scalar wavetable fallback (sub-1Hz) ----
            DROP
            _OSC-TMP @ O.PHASE @ _OSC-PH !
            _OSC-TMP @ O.FREQ @
            _OSC-TMP @ O.RATE @ INT>FP16
            FP16-DIV _OSC-INC !
            _OSC-BUF @ PCM-DATA _OSC-FPTR !
            _OSC-BUF @ PCM-LEN 0 DO
                _OSC-PH @ _OSC-FTAB @ WT-LERP
                _OSC-FPTR @ I 2 * + W!
                _OSC-PH @ _OSC-INC @ FP16-ADD
                DUP FP16-POS-ONE FP16-GE IF
                    FP16-POS-ONE FP16-SUB
                THEN
                _OSC-PH !
            LOOP
            _OSC-PH @ _OSC-TMP @ O.PHASE !
        THEN
    ELSE
        \ ---- Generic per-sample path (non-wavetable shapes) ----
        DROP
        _OSC-BUF @ PCM-LEN 0 DO
            _OSC-TMP @ OSC-SAMPLE
            I _OSC-BUF @ PCM-FRAME!
        LOOP
    THEN ;

\ =====================================================================
\  OSC-ADD — Add oscillator output to existing PCM buffer
\ =====================================================================
\  ( buf osc -- )
\  Reads existing FP16 sample, adds new sample, writes back.
\  Fast path with direct W!/W@ when wavetable is set.

: OSC-ADD  ( buf osc -- )
    _OSC-TMP !
    _OSC-BUF !

    _OSC-TMP @ O.TABLE @ DUP IF
        _OSC-FTAB !

        _OSC-TMP @ O.FREQ @
        _OSC-TMP @ O.RATE @
        WT-BLOCK-INC DUP IF
            \ ---- Block mode add (scalar FP16-ADD per sample) ----
            _OSC-INC !
            _OSC-TMP @ O.PHASE @ WT-PH>INT
            _OSC-INC @
            _OSC-BUF @ PCM-LEN
            _OSC-FTAB @
            _OSC-BUF @ PCM-DATA
            WT-BLOCK-ADD
            WT-INT>PH
            _OSC-TMP @ O.PHASE !
        ELSE
            \ ---- Scalar wavetable fallback (sub-1Hz) ----
            DROP
            _OSC-TMP @ O.PHASE @ _OSC-PH !
            _OSC-TMP @ O.FREQ @
            _OSC-TMP @ O.RATE @ INT>FP16
            FP16-DIV _OSC-INC !
            _OSC-BUF @ PCM-DATA _OSC-FPTR !
            _OSC-BUF @ PCM-LEN 0 DO
                _OSC-PH @ _OSC-FTAB @ WT-LERP
                _OSC-FPTR @ I 2 * + DUP W@
                ROT FP16-ADD SWAP W!
                _OSC-PH @ _OSC-INC @ FP16-ADD
                DUP FP16-POS-ONE FP16-GE IF
                    FP16-POS-ONE FP16-SUB
                THEN
                _OSC-PH !
            LOOP
            _OSC-PH @ _OSC-TMP @ O.PHASE !
        THEN
    ELSE
        \ ---- Generic per-sample path ----
        DROP
        _OSC-BUF @ PCM-LEN 0 DO
            _OSC-TMP @ OSC-SAMPLE
            I _OSC-BUF @ PCM-FRAME@
            FP16-ADD
            I _OSC-BUF @ PCM-FRAME!
        LOOP
    THEN ;
