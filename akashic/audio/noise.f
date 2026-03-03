\ noise.f — FP16 noise generators (white, pink, brown)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Generates noise waveforms into PCM buffers.  Each generator
\ has a small descriptor holding its state.  Uses KDOS RANDOM16
\ for seed values.
\
\ All output values are FP16 in the range [−1.0, +1.0].
\ PCM buffers should be 16-bit (storing FP16 bit patterns).
\
\ White:  Flat spectrum, uniform distribution.
\         16-bit LFSR (Galois, maximal-length polynomial).
\ Pink:   −3 dB/octave roll-off.
\         Voss-McCartney algorithm with 8 octave-band rows.
\ Brown:  −6 dB/octave roll-off (integrated white noise).
\         Leaky integrator: state ← state × 0.98 + white × 0.02.
\
\ Memory: noise descriptors on heap (48 bytes).
\
\ Prefix: NOISE-   (public API)
\         _NZ-     (internals)
\
\ Load with:   REQUIRE audio/noise.f
\
\ === Public API ===
\   NOISE-CREATE  ( type -- desc )       allocate noise generator
\   NOISE-FREE    ( desc -- )            free descriptor
\   NOISE-FILL    ( buf desc -- )        fill PCM buffer with noise
\   NOISE-ADD     ( buf desc -- )        add noise to PCM buffer
\   NOISE-SAMPLE  ( desc -- value )      one FP16 sample
\
\ Type constants:
\   NOISE-WHITE  NOISE-PINK  NOISE-BROWN

REQUIRE fp16-ext.f
REQUIRE audio/pcm.f

PROVIDED akashic-audio-noise

\ =====================================================================
\  Noise descriptor layout  (6 cells = 48 bytes)
\ =====================================================================
\
\  +0   type      0=white, 1=pink, 2=brown
\  +8   state     LFSR state (16-bit) for white/pink
\  +16  accum     Accumulator for brown noise (FP16)
\  +24  counter   Running counter for Voss-McCartney (pink)
\  +32  rows      Pointer to 8-cell array of octave-band LFSRs (pink)
\  +40  (reserved)

48 CONSTANT NOISE-DESC-SIZE

0 CONSTANT NOISE-WHITE
1 CONSTANT NOISE-PINK
2 CONSTANT NOISE-BROWN

\ =====================================================================
\  Field accessors
\ =====================================================================

: N.TYPE    ( desc -- addr )  ;
: N.STATE   ( desc -- addr )  8 + ;
: N.ACCUM   ( desc -- addr )  16 + ;
: N.COUNTER ( desc -- addr )  24 + ;
: N.ROWS    ( desc -- addr )  32 + ;

\ =====================================================================
\  LFSR constants — Galois LFSR, maximal-length
\ =====================================================================
\  Polynomial: x^16 + x^14 + x^13 + x^11 + 1
\  Taps mask: 0xB400  (bits 15, 13, 12, 10 → feedback when bit 0 = 1)

0xB400 CONSTANT _NZ-TAPS

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _NZ-TMP       \ descriptor pointer
VARIABLE _NZ-VAL       \ computed sample
VARIABLE _NZ-BUF       \ target PCM buffer
VARIABLE _NZ-ST        \ LFSR state temp
VARIABLE _NZ-SUM       \ accumulator for pink

\ =====================================================================
\  FP16 constants for noise scaling
\ =====================================================================
\  To map LFSR [1..65535] to FP16 [-1.0, +1.0]:
\    signed = lfsr - 32768    → [-32767, +32767]
\    fp16   = INT>FP16(signed) / INT>FP16(32768)
\  Note: 1/32768 is subnormal in FP16 (below 2^-14), so FP16-RECIP
\  fails.  We split the division: /128 then /256 (128×256 = 32768).

\ =====================================================================
\  Internal: step the LFSR once, return new state
\ =====================================================================
\  ( state -- state' )

: _NZ-LFSR-STEP  ( state -- state' )
    DUP 1 AND IF
        1 RSHIFT _NZ-TAPS XOR
    ELSE
        1 RSHIFT
    THEN
    0xFFFF AND ;

\ =====================================================================
\  Internal: convert LFSR 16-bit value to FP16 in [-1.0, +1.0]
\ =====================================================================
\  ( lfsr -- fp16 )

: _NZ-LFSR>FP16  ( lfsr -- fp16 )
    0xFFFF AND
    32768 -                           \ center: [-32768, +32767]
    INT>FP16                          \ convert to FP16
    128 INT>FP16 FP16-DIV             \ ÷128
    256 INT>FP16 FP16-DIV ;           \ ÷256  (total ÷32768)

\ =====================================================================
\  NOISE-CREATE — Allocate noise generator
\ =====================================================================
\  ( type -- desc )
\  Seeds LFSR from RANDOM16.  For pink, allocates 8-cell row array.

: NOISE-CREATE  ( type -- desc )
    >R                                ( ) ( R: type )
    NOISE-DESC-SIZE ALLOCATE
    0<> ABORT" NOISE-CREATE: alloc failed"
    _NZ-TMP !

    R> _NZ-TMP @ N.TYPE !            \ type

    RANDOM16 DUP 0= IF DROP 1 THEN   \ ensure LFSR state ≠ 0
    _NZ-TMP @ N.STATE !

    FP16-POS-ZERO _NZ-TMP @ N.ACCUM !  \ brown accumulator = 0
    0 _NZ-TMP @ N.COUNTER !          \ pink counter = 0

    \ For pink noise: allocate 8-cell array of LFSR rows
    _NZ-TMP @ N.TYPE @ NOISE-PINK = IF
        64 ALLOCATE                   \ 8 cells × 8 bytes
        0<> ABORT" NOISE-CREATE: pink rows alloc failed"
        DUP _NZ-TMP @ N.ROWS !
        \ Seed each row with a different RANDOM16
        8 0 DO
            RANDOM16 DUP 0= IF DROP 1 THEN
            OVER I 8 * + !
        LOOP
        DROP
    ELSE
        0 _NZ-TMP @ N.ROWS !
    THEN

    _NZ-TMP @ ;

\ =====================================================================
\  NOISE-FREE — Free descriptor
\ =====================================================================

: NOISE-FREE  ( desc -- )
    DUP N.ROWS @ ?DUP IF FREE THEN
    FREE ;

\ =====================================================================
\  Internal: white noise — one sample
\ =====================================================================

: _NZ-WHITE-SAMPLE  ( desc -- value )
    DUP N.STATE @
    _NZ-LFSR-STEP
    DUP ROT N.STATE !                \ update state in descriptor
    _NZ-LFSR>FP16 ;

\ =====================================================================
\  Internal: pink noise — one sample (Voss-McCartney)
\ =====================================================================
\  Uses 8 octave-band LFSR rows.  On each step:
\  1. Increment counter
\  2. Find lowest set bit of counter (trailing zeros)
\  3. Update that row's LFSR
\  4. Sum all 8 rows, normalize
\
\  The sum of 8 values in [-32767, 32767] can reach [-262136, 262136].
\  We divide by 8 to keep in range, then normalize.

VARIABLE _NZ-PINK-ROWS
VARIABLE _NZ-PINK-CTR
VARIABLE _NZ-PINK-BIT

: _NZ-CTZ  ( n -- bit )
    \ Count trailing zeros (0-based index of lowest set bit)
    \ Returns 0..7 (clamped to 7 for our 8-row case)
    DUP 0= IF DROP 0 EXIT THEN
    0 SWAP
    BEGIN
        DUP 1 AND 0= WHILE
        1 RSHIFT SWAP 1+ SWAP
    REPEAT
    DROP
    7 MIN ;

: _NZ-PINK-SAMPLE  ( desc -- value )
    _NZ-TMP !

    \ Read & increment counter
    _NZ-TMP @ N.COUNTER @
    1+ DUP _NZ-TMP @ N.COUNTER !
    _NZ-PINK-CTR !

    \ Find which row to update
    _NZ-PINK-CTR @ _NZ-CTZ _NZ-PINK-BIT !

    \ Update that row's LFSR
    _NZ-TMP @ N.ROWS @
    DUP _NZ-PINK-BIT @ 8 * + @       \ old state
    _NZ-LFSR-STEP                     \ new state
    OVER _NZ-PINK-BIT @ 8 * + !      \ store back
    _NZ-PINK-ROWS !

    \ Sum all 8 rows → signed sum
    0 _NZ-SUM !
    8 0 DO
        _NZ-PINK-ROWS @ I 8 * + @    \ LFSR state
        0xFFFF AND 32768 -            \ center to signed
        _NZ-SUM +!
    LOOP

    \ Divide by 8, then convert to FP16, normalize ÷32768
    _NZ-SUM @ 8 /
    INT>FP16
    128 INT>FP16 FP16-DIV
    256 INT>FP16 FP16-DIV ;

\ =====================================================================
\  Internal: brown noise — one sample (leaky integrator)
\ =====================================================================
\  accum = accum × 0.98 + white × 0.02

0x3BD7 CONSTANT _NZ-BROWN-DECAY   \ FP16 0.98  (98/100)
0x251F CONSTANT _NZ-BROWN-INPUT   \ FP16 0.02  (2/100)

VARIABLE _NZ-BROWN-W

: _NZ-BROWN-SAMPLE  ( desc -- value )
    _NZ-TMP !

    \ Generate white noise sample
    _NZ-TMP @ _NZ-WHITE-SAMPLE
    _NZ-BROWN-W !

    \ Read current accumulator (FP16)
    _NZ-TMP @ N.ACCUM @

    \ accum = accum × 0.98 + white × 0.02
    _NZ-BROWN-DECAY FP16-MUL           ( accum×0.98 )
    _NZ-BROWN-W @
    _NZ-BROWN-INPUT FP16-MUL           ( ax0.98 white×0.02 )
    FP16-ADD                           ( new_accum )

    \ Clamp to [-1.0, +1.0]
    FP16-NEG-ONE FP16-POS-ONE FP16-CLAMP

    \ Store back and return
    DUP _NZ-TMP @ N.ACCUM !
    ;

\ =====================================================================
\  NOISE-SAMPLE — Generate one FP16 noise sample
\ =====================================================================
\  ( desc -- value )

: NOISE-SAMPLE  ( desc -- value )
    DUP N.TYPE @
    CASE
        NOISE-WHITE OF _NZ-WHITE-SAMPLE ENDOF
        NOISE-PINK  OF _NZ-PINK-SAMPLE  ENDOF
        NOISE-BROWN OF _NZ-BROWN-SAMPLE ENDOF
        \ default: silence
        NIP FP16-POS-ZERO SWAP
    ENDCASE ;

\ =====================================================================
\  NOISE-FILL — Fill PCM buffer with noise
\ =====================================================================
\  ( buf desc -- )

: NOISE-FILL  ( buf desc -- )
    _NZ-TMP !
    _NZ-BUF !

    _NZ-BUF @ PCM-LEN 0 DO
        _NZ-TMP @ NOISE-SAMPLE
        I _NZ-BUF @ PCM-FRAME!
    LOOP ;

\ =====================================================================
\  NOISE-ADD — Add noise to existing PCM buffer
\ =====================================================================
\  ( buf desc -- )

: NOISE-ADD  ( buf desc -- )
    _NZ-TMP !
    _NZ-BUF !

    _NZ-BUF @ PCM-LEN 0 DO
        _NZ-TMP @ NOISE-SAMPLE        ( noise )
        I _NZ-BUF @ PCM-FRAME@        ( noise existing )
        FP16-ADD
        I _NZ-BUF @ PCM-FRAME!
    LOOP ;
