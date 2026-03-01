\ env.f — ADSR envelope generators (FP16)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Envelope generators produce a time-varying FP16 gain curve
\ in [0.0, 1.0].  Linear and exponential segment shapes.
\ Usable for amplitude, filter cutoff, pitch bend, or any
\ parameter that evolves over time.
\
\ Timing: attack/decay/release specified in milliseconds at
\ creation, converted to frame counts internally.
\
\ Usage:
\   50 100 8000 200 44100 ENV-CREATE CONSTANT my-env
\   my-env ENV-GATE-ON                \ note on → attack
\   BEGIN my-env ENV-TICK . CR  my-env ENV-DONE? UNTIL
\
\ Prefix: ENV-   (public API)
\         _ENV-  (internals)
\
\ Load with:   REQUIRE audio/env.f
\
\ === Public API ===
\   ENV-CREATE    ( a d s r rate -- env )  create ADSR envelope
\   ENV-CREATE-AR ( a r rate -- env )      create AR envelope (no sustain)
\   ENV-FREE      ( env -- )               free descriptor
\   ENV-GATE-ON   ( env -- )               trigger attack
\   ENV-GATE-OFF  ( env -- )               trigger release
\   ENV-RETRIGGER ( env -- )               retrigger from current level
\   ENV-RESET     ( env -- )               reset to idle
\   ENV-TICK      ( env -- level )         advance one frame, return level
\   ENV-FILL      ( buf env -- )           fill buffer with envelope curve
\   ENV-APPLY     ( buf env -- )           multiply buffer by envelope
\   ENV-DONE?     ( env -- flag )          true if envelope completed
\   ENV-LEVEL     ( env -- level )         current output level (FP16)

REQUIRE fp16-ext.f

PROVIDED akashic-audio-env

\ =====================================================================
\  Envelope descriptor layout  (12 cells = 96 bytes)
\ =====================================================================
\
\  +0   attack     Attack time in frames
\  +8   decay      Decay time in frames
\  +16  sustain    Sustain level 0.0–1.0 (FP16)
\  +24  release    Release time in frames
\  +32  phase      0=idle, 1=attack, 2=decay, 3=sustain, 4=release, 5=done
\  +40  position   Current position within phase (frame count)
\  +48  level      Current output level (FP16)
\  +56  curve      0=linear, 1=exponential (reserved, linear for now)
\  +64  mode       0=one-shot, 1=loop, 2=AR
\  +72  rate       Sample rate in Hz (integer)
\  +80  rel-level  Level at start of release phase (FP16)
\  +88  (reserved)

96 CONSTANT ENV-DESC-SIZE

\ Phase constants
0 CONSTANT ENV-IDLE
1 CONSTANT ENV-ATTACK
2 CONSTANT ENV-DECAY
3 CONSTANT ENV-SUSTAIN
4 CONSTANT ENV-RELEASE
5 CONSTANT ENV-DONE

\ =====================================================================
\  Field accessors
\ =====================================================================

: E.ATTACK   ( env -- addr )  ;
: E.DECAY    ( env -- addr )  8 + ;
: E.SUSTAIN  ( env -- addr )  16 + ;
: E.RELEASE  ( env -- addr )  24 + ;
: E.PHASE    ( env -- addr )  32 + ;
: E.POS      ( env -- addr )  40 + ;
: E.LEVEL    ( env -- addr )  48 + ;
: E.CURVE    ( env -- addr )  56 + ;
: E.MODE     ( env -- addr )  64 + ;
: E.RATE     ( env -- addr )  72 + ;
: E.RELLEV   ( env -- addr )  80 + ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _ENV-TMP
VARIABLE _ENV-BUF
VARIABLE _ENV-POS
VARIABLE _ENV-LEN
VARIABLE _ENV-LVL
VARIABLE _ENV-T

\ =====================================================================
\  Internal: convert milliseconds to frames
\ =====================================================================
\  ( ms rate -- frames )

: _ENV-MS>FRAMES  ( ms rate -- frames )
    * 1000 / ;

\ =====================================================================
\  ENV-CREATE — Create ADSR envelope
\ =====================================================================
\  ( a d s r rate -- env )
\  a/d/r = milliseconds (integer)
\  s = sustain level as FP16 (0.0–1.0)
\  rate = sample rate in Hz (integer)

VARIABLE _ENV-A
VARIABLE _ENV-D
VARIABLE _ENV-S
VARIABLE _ENV-R
VARIABLE _ENV-RATE

: ENV-CREATE  ( a d s r rate -- env )
    _ENV-RATE !                       \ rate (integer)
    _ENV-R !                          \ release (ms, integer)
    _ENV-S !                          \ sustain (FP16)
    _ENV-D !                          \ decay (ms, integer)
    _ENV-A !                          \ attack (ms, integer)

    ENV-DESC-SIZE ALLOCATE
    0<> ABORT" ENV-CREATE: alloc failed"
    _ENV-TMP !

    _ENV-A @ _ENV-RATE @ _ENV-MS>FRAMES
    DUP 0= IF DROP 1 THEN            \ minimum 1 frame
    _ENV-TMP @ E.ATTACK !

    _ENV-D @ _ENV-RATE @ _ENV-MS>FRAMES
    DUP 0= IF DROP 1 THEN
    _ENV-TMP @ E.DECAY !

    _ENV-S @  _ENV-TMP @ E.SUSTAIN !

    _ENV-R @ _ENV-RATE @ _ENV-MS>FRAMES
    DUP 0= IF DROP 1 THEN
    _ENV-TMP @ E.RELEASE !

    ENV-IDLE           _ENV-TMP @ E.PHASE  !
    0                  _ENV-TMP @ E.POS    !
    FP16-POS-ZERO      _ENV-TMP @ E.LEVEL  !
    0                  _ENV-TMP @ E.CURVE  !    \ linear
    0                  _ENV-TMP @ E.MODE   !    \ one-shot
    _ENV-RATE @        _ENV-TMP @ E.RATE   !
    FP16-POS-ZERO      _ENV-TMP @ E.RELLEV !

    _ENV-TMP @ ;

\ =====================================================================
\  ENV-CREATE-AR — Create attack-release envelope (no sustain)
\ =====================================================================
\  ( a r rate -- env )

: ENV-CREATE-AR  ( a r rate -- env )
    >R >R                             ( a ) ( R: rate r )
    0                                 \ decay = 0 ms
    FP16-POS-ZERO                     \ sustain = 0.0 (unused)
    R> R>                             ( a 0 0.0 r rate )
    ENV-CREATE
    DUP 2 SWAP E.MODE ! ;            \ mode = 2 = AR

\ =====================================================================
\  ENV-FREE
\ =====================================================================

: ENV-FREE  ( env -- ) FREE ;

\ =====================================================================
\  ENV-GATE-ON — Trigger attack phase
\ =====================================================================

: ENV-GATE-ON  ( env -- )
    _ENV-TMP !
    ENV-ATTACK  _ENV-TMP @ E.PHASE !
    0           _ENV-TMP @ E.POS   !
    ;
    \ Level starts from current value (allows retriggering from non-zero)

\ =====================================================================
\  ENV-GATE-OFF — Trigger release phase
\ =====================================================================

: ENV-GATE-OFF  ( env -- )
    _ENV-TMP !
    _ENV-TMP @ E.LEVEL @  _ENV-TMP @ E.RELLEV !  \ save current level
    ENV-RELEASE  _ENV-TMP @ E.PHASE !
    0            _ENV-TMP @ E.POS   !
    ;

\ =====================================================================
\  ENV-RETRIGGER — Retrigger from current level
\ =====================================================================

: ENV-RETRIGGER  ( env -- )
    ENV-GATE-ON ;                     \ attack from current level

\ =====================================================================
\  ENV-RESET — Reset to idle
\ =====================================================================

: ENV-RESET  ( env -- )
    _ENV-TMP !
    ENV-IDLE       _ENV-TMP @ E.PHASE !
    0              _ENV-TMP @ E.POS   !
    FP16-POS-ZERO  _ENV-TMP @ E.LEVEL !
    ;

\ =====================================================================
\  ENV-DONE? — True if envelope completed
\ =====================================================================

: ENV-DONE?  ( env -- flag )
    E.PHASE @ ENV-DONE = ;

\ =====================================================================
\  ENV-LEVEL — Current output level (FP16)
\ =====================================================================

: ENV-LEVEL  ( env -- level )
    E.LEVEL @ ;

\ =====================================================================
\  Internal: linear interpolation between two FP16 values
\ =====================================================================
\  ( start end position length -- value )
\  value = start + (end - start) × position / length
\  All FP16 except position and length are integers.

: _ENV-LERP  ( start end pos len -- value )
    _ENV-LEN !  _ENV-POS !
    OVER FP16-SUB                     ( start end-start )
    _ENV-POS @ INT>FP16 FP16-MUL     ( start (end-start)*pos )
    _ENV-LEN @ INT>FP16 FP16-DIV     ( start (end-start)*pos/len )
    FP16-ADD ;                        ( start + fraction )

\ =====================================================================
\  ENV-TICK — Advance envelope by one frame
\ =====================================================================
\  ( env -- level )
\  Returns current FP16 level [0.0, 1.0].

: ENV-TICK  ( env -- level )
    _ENV-TMP !

    _ENV-TMP @ E.PHASE @
    CASE
        ENV-IDLE OF
            FP16-POS-ZERO
        ENDOF

        ENV-ATTACK OF
            \ Linear ramp from current level (or 0) to 1.0
            \ level = pos / attack_frames
            _ENV-TMP @ E.POS @
            _ENV-TMP @ E.ATTACK @
            DUP _ENV-POS !
            >R
            INT>FP16 R> INT>FP16 FP16-DIV  ( pos/attack = level )

            \ If we've reached end of attack, transition to decay
            _ENV-TMP @ E.POS @ 1+
            DUP _ENV-TMP @ E.POS !
            _ENV-TMP @ E.ATTACK @ >= IF
                \ AR mode: skip sustain, go to release
                _ENV-TMP @ E.MODE @ 2 = IF
                    FP16-POS-ONE _ENV-TMP @ E.RELLEV !
                    ENV-RELEASE _ENV-TMP @ E.PHASE !
                    0 _ENV-TMP @ E.POS !
                ELSE
                    ENV-DECAY _ENV-TMP @ E.PHASE !
                    0 _ENV-TMP @ E.POS !
                THEN
            THEN
        ENDOF

        ENV-DECAY OF
            \ Linear ramp from 1.0 to sustain level
            FP16-POS-ONE
            _ENV-TMP @ E.SUSTAIN @
            _ENV-TMP @ E.POS @
            _ENV-TMP @ E.DECAY @
            _ENV-LERP

            \ Advance position
            _ENV-TMP @ E.POS @ 1+
            DUP _ENV-TMP @ E.POS !
            _ENV-TMP @ E.DECAY @ >= IF
                ENV-SUSTAIN _ENV-TMP @ E.PHASE !
                0 _ENV-TMP @ E.POS !
            THEN
        ENDOF

        ENV-SUSTAIN OF
            \ Hold at sustain level
            _ENV-TMP @ E.SUSTAIN @
        ENDOF

        ENV-RELEASE OF
            \ Linear ramp from release-start level to 0
            _ENV-TMP @ E.RELLEV @
            FP16-POS-ZERO
            _ENV-TMP @ E.POS @
            _ENV-TMP @ E.RELEASE @
            _ENV-LERP

            \ Advance position
            _ENV-TMP @ E.POS @ 1+
            DUP _ENV-TMP @ E.POS !
            _ENV-TMP @ E.RELEASE @ >= IF
                ENV-DONE _ENV-TMP @ E.PHASE !
            THEN
        ENDOF

        ENV-DONE OF
            FP16-POS-ZERO
        ENDOF

        \ default: silence
        FP16-POS-ZERO SWAP
    ENDCASE

    \ Store level
    DUP _ENV-TMP @ E.LEVEL !
    ;

\ =====================================================================
\  ENV-FILL — Fill PCM buffer with envelope curve
\ =====================================================================
\  ( buf env -- )

: ENV-FILL  ( buf env -- )
    _ENV-TMP !
    _ENV-BUF !

    _ENV-BUF @ PCM-LEN 0 DO
        _ENV-TMP @ ENV-TICK
        I _ENV-BUF @ PCM-FRAME!
    LOOP ;

\ =====================================================================
\  ENV-APPLY — Multiply PCM buffer by envelope (in-place gain)
\ =====================================================================
\  ( buf env -- )
\  Each sample = sample × envelope_level

: ENV-APPLY  ( buf env -- )
    _ENV-TMP !
    _ENV-BUF !

    _ENV-BUF @ PCM-LEN 0 DO
        _ENV-TMP @ ENV-TICK           ( env-level )
        I _ENV-BUF @ PCM-FRAME@       ( env-level sample )
        FP16-MUL                       ( scaled )
        I _ENV-BUF @ PCM-FRAME!
    LOOP ;
