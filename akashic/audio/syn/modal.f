\ syn/modal.f — Inharmonic partial (modal) synthesis engine
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Generates a struck/plucked sound as a sum of N sinusoidal partials,
\ each with its own frequency ratio, initial amplitude, and T60 decay.
\ Higher partials typically decay faster, producing the characteristic
\ brightness-over-time shape of bells, gongs, metallic objects, stone,
\ glass, wood — and equally anything with no physical referent.
\
\ This is an algorithm, not an instrument.  It has no opinion about
\ what the sound should be.  Partial ratios, amplitudes, and decays
\ are all configurable.  Built-in ratio tables are provided for
\ common timbral starting points.
\
\ Amplitude envelope strategy:
\   Per-sample exponential decay requires a multiplier astronomically
\   close to 1.0 (e.g. 0.9999739 for a 2-second T60 at 44100 Hz).
\   FP16 precision near 1.0 is ~0.001 — the value would round to
\   either 1.0 (no decay) or the next representable step (too fast).
\
\   Solution: block-rate amplitude update, 32 samples per block.
\   The 32-sample block decay factor for a 2-second T60 is ~0.9975,
\   which FP16 represents cleanly.  0.73 ms per block is finer than
\   the DX7's control rate (~2.67 ms) and inaudibly smooth.
\
\   Block decay factor computation:
\     x = 32 * ln(1000) / (decay_sec * damping * rate)
\     factor = exp(-x) ≈ 1 - x + x²/2 - x³/6  (3-term Taylor)
\   Accurate to < 0.1% for decay_sec >= 0.05 s.
\
\ Strike transient (optional):
\   A burst of HP-filtered white noise mixed in at the attack, with
\   its own fast AR decay.  Controlled by noise-ms and noise-bw.
\   HP is a 1-pole filter: y = x - x_prev + alpha * y_prev,
\   alpha ≈ 1 - 2π * fc / rate.  Computable in FP16 without exp().
\
\ Output:
\   MODAL-STRIKE returns a freshly allocated PCM buffer (mono, 16-bit,
\   FP16 samples).  Caller owns it and must call PCM-FREE when done.
\   MODAL-STRIKE-INTO adds into an existing buffer instead.
\
\ Memory:
\   Descriptor:   80 bytes (heap)
\   Partial data: N × 6 bytes (heap, pointer in descriptor)
\   Strike temps: 4 × N × 2 bytes (heap, freed before MODAL-STRIKE
\                 returns)
\   Output PCM:   allocated by MODAL-STRIKE, returned to caller
\
\ Prefix: MODAL-   (public API)
\         _MD-     (internals)
\
\ Load with:   REQUIRE audio/syn/modal.f
\
\ === Public API ===
\   MODAL-CREATE       ( n-partials rate -- desc )
\   MODAL-FREE         ( desc -- )
\   MODAL-FUND!        ( freq desc -- )        FP16 Hz
\   MODAL-PARTIAL!     ( ratio amp decay-sec i desc -- )
\   MODAL-LOAD-TABLE   ( table n desc -- )     packed FP16 triplets
\   MODAL-BRIGHTNESS!  ( brightness desc -- )  FP16 0.0–1.0
\   MODAL-DAMPING!     ( damping desc -- )     FP16 0.0–2.0
\   MODAL-NOISE!       ( ms bw desc -- )       integer ms, FP16 bw Hz
\   MODAL-DURATION     ( desc -- ms )          estimated audible ms
\   MODAL-STRIKE       ( velocity desc -- buf ) render → new PCM buf
\   MODAL-STRIKE-INTO  ( buf velocity desc -- ) render → add into buf

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE audio/osc.f
REQUIRE audio/noise.f
REQUIRE audio/env.f
REQUIRE audio/pcm.f

PROVIDED akashic-syn-modal

\ =====================================================================
\  Descriptor layout  (10 cells = 80 bytes)
\ =====================================================================
\
\  +0   n-partials   Number of partials (integer)
\  +8   fundamental  Base frequency Hz (FP16)
\  +16  brightness   Strike energy bias toward high partials (FP16 0–1)
\  +24  damping      Global T60 multiplier (FP16, default 1.0)
\  +32  noise-ms     Strike transient duration in ms (integer, 0=off)
\  +40  noise-bw     Transient bandpass high-pass cutoff Hz (FP16)
\  +48  rate         Sample rate Hz (integer)
\  +56  pdata        Pointer to partial array (N × 6 bytes)
\                      each entry: ratio(FP16) amp(FP16) decay-sec(FP16)
\  +64  (reserved)
\  +72  (reserved)

80 CONSTANT MODAL-DESC-SIZE

: MD.N     ( desc -- addr )  ;
: MD.FUND  ( desc -- addr )  8 + ;
: MD.BRI   ( desc -- addr )  16 + ;
: MD.DAMP  ( desc -- addr )  24 + ;
: MD.NMS   ( desc -- addr )  32 + ;
: MD.NBW   ( desc -- addr )  40 + ;
: MD.RATE  ( desc -- addr )  48 + ;
: MD.PDATA ( desc -- addr )  56 + ;

\ Partial stride: 3 FP16 values × 2 bytes = 6 bytes per partial
6 CONSTANT _MD-PSTRIDE

: _MD-PRATIO ( i pdata -- addr )  SWAP _MD-PSTRIDE * + ;
: _MD-PAMP   ( i pdata -- addr )  SWAP _MD-PSTRIDE * + 2 + ;
: _MD-PDEC   ( i pdata -- addr )  SWAP _MD-PSTRIDE * + 4 + ;

\ =====================================================================
\  FP16 constants
\ =====================================================================

\ 1.0
: _MD-FP16-ONE  FP16-POS-ONE ;

\ 0.5
: _MD-FP16-HALF FP16-POS-HALF ;

\ 2.0
0x4000 CONSTANT _MD-FP16-TWO

\ 6.0 — for Taylor x³/6 divisor
0x4600 CONSTANT _MD-FP16-SIX

\ 0.0
: _MD-FP16-ZERO FP16-POS-ZERO ;

\ 32 × ln(1000) = 32 × 6.9078 = 221.05
\ Computed: 32 hand 6908 / 1000 * (FP16 arithmetic).
\ Stored as a single constant to avoid recomputing each strike.
VARIABLE _MD-CONST-32LN1000
: _MD-INIT-CONST
    32 INT>FP16
    6908 INT>FP16  1000 INT>FP16 FP16-DIV
    FP16-MUL
    _MD-CONST-32LN1000 ! ;
_MD-INIT-CONST

\ 3.0 — for duration estimate (3 × T60 max)
0x4200 CONSTANT _MD-FP16-THREE

\ 1000.0 ms per second
: _MD-FP16-1000  1000 INT>FP16 ;

\ Max audible duration cap: 10000 ms
10000 CONSTANT _MD-MAX-MS

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _MD-TMP      \ descriptor pointer
VARIABLE _MD-I        \ loop index
VARIABLE _MD-J        \ inner loop index / sample index
VARIABLE _MD-N        \ cached n-partials
VARIABLE _MD-RATE     \ cached rate
VARIABLE _MD-FUND     \ cached fundamental (FP16)
VARIABLE _MD-DAMP     \ cached damping (FP16)
VARIABLE _MD-VEL      \ velocity (FP16)
VARIABLE _MD-PDATA    \ cached partial data pointer
VARIABLE _MD-STATE    \ pointer to temp state block
VARIABLE _MD-BUF      \ output PCM buffer pointer
VARIABLE _MD-FRAMES   \ total frames to render
VARIABLE _MD-BLKS     \ total 32-sample blocks to render
VARIABLE _MD-SUM      \ sample accumulator (FP16)
VARIABLE _MD-X        \ FP16 temp
VARIABLE _MD-Y        \ FP16 temp
VARIABLE _MD-PH       \ phase temp (FP16)
VARIABLE _MD-AMP      \ amp temp (FP16)

\ =====================================================================
\  State block layout — allocated per-strike, freed at end
\ =====================================================================
\
\  State block = 4 subarrays of N FP16 words each
\  Total = 4 × N × 2 bytes
\
\  phase[0..N-1]      : running phase (FP16)
\  ramp [N..2N-1]     : running amplitude (FP16)
\  bdec [2N..3N-1]    : per-block decay factor (FP16)
\  pinc [3N..4N-1]    : phase increment per sample (FP16)
\
\  All accessed via N offset:

: _MD-ST-PHASE ( i n state -- addr )  SWAP DROP SWAP 2* + ;
: _MD-ST-RAMP  ( i n state -- addr )  SWAP 2* + SWAP 2* + ;
: _MD-ST-BDEC  ( i n state -- addr )  SWAP 4 * + SWAP 2* + ;
: _MD-ST-PINC  ( i n state -- addr )  SWAP 6 * + SWAP 2* + ;

\ =====================================================================
\  Internal: Taylor approximation of exp(-x) for small positive x
\ =====================================================================
\  ( x -- exp-neg-x )
\  x is FP16, positive, small (typically 0.0002 – 0.5)
\  result = 1 - x + x²/2 - x³/6
\  Clamped to 0.0 from below.

VARIABLE _MD-EX

: _MD-EXP-NEG  ( x -- approx )
    _MD-EX !                          \ save x
    \ 1 - x
    _MD-FP16-ONE
    _MD-EX @ FP16-SUB
    \ + x²/2
    _MD-EX @ _MD-EX @ FP16-MUL       \ x²
    _MD-FP16-TWO FP16-DIV             \ x²/2
    FP16-ADD
    \ - x³/6
    _MD-EX @ _MD-EX @ FP16-MUL       \ x²
    _MD-EX @ FP16-MUL                 \ x³
    _MD-FP16-SIX FP16-DIV             \ x³/6
    FP16-SUB
    \ clamp to 0
    DUP _MD-FP16-ZERO FP16-LT IF
        DROP _MD-FP16-ZERO
    THEN ;

\ =====================================================================
\  Internal: compute per-block decay factor for one partial
\ =====================================================================
\  ( decay-sec-fp16 damping-fp16 rate-int -- block-decay-fp16 )
\
\  x = 32 * ln(1000) / (decay_sec * damping * rate)
\  factor = exp(-x)

VARIABLE _MD-DRATE
VARIABLE _MD-DDAMP

: _MD-BLOCK-DECAY  ( decay-fp16 damp-fp16 rate -- factor )
    _MD-DRATE !  _MD-DDAMP !         \ save damp and rate
    \ decay_sec * damping
    _MD-DDAMP @ FP16-MUL
    \ * rate
    _MD-DRATE @ INT>FP16 FP16-MUL
    \ x = 32*ln1000 / (above)
    _MD-CONST-32LN1000 @ SWAP FP16-DIV
    \ guard: x must be positive, cap at 6.0 (factor → ~0.0025)
    DUP _MD-FP16-ZERO FP16-LT IF DROP _MD-FP16-ZERO THEN
    DUP _MD-FP16-SIX FP16-GT IF DROP _MD-FP16-SIX THEN
    \ approximate exp(-x)
    _MD-EXP-NEG ;

\ =====================================================================
\  Internal: brightness scale for partial i
\ =====================================================================
\  Higher partials get more of the strike energy when brightness > 0.
\  Scale = 1.0 + brightness * (i / max_i)
\  At brightness=0: all partials at nominal amp.
\  At brightness=1: highest partial receives 2× nominal amp.

VARIABLE _MD-BSCALE-I
VARIABLE _MD-BSCALE-N

: _MD-BSCALE  ( i n-1 brightness -- scale-fp16 )
    \ scale = 1.0 + brightness × (i / (n-1))
    \ guard n-1 = 0 (single partial)
    >R                                ( i n-1 )  ( R: brightness )
    OVER 0= IF
        2DROP R> DROP _MD-FP16-ONE EXIT
    THEN
    INT>FP16 SWAP INT>FP16 SWAP FP16-DIV   ( i/n-1 as FP16 )
    R@ FP16-MUL                       ( brightness × i/(n-1) )
    R> DROP
    _MD-FP16-ONE FP16-ADD ;           ( 1.0 + above )

\ =====================================================================
\  MODAL-CREATE — Allocate modal descriptor
\ =====================================================================
\  ( n-partials rate -- desc )

VARIABLE _MD-C-N
VARIABLE _MD-C-R

: MODAL-CREATE  ( n-partials rate -- desc )
    _MD-C-R !  _MD-C-N !

    \ Allocate descriptor
    MODAL-DESC-SIZE ALLOCATE
    0<> ABORT" MODAL-CREATE: desc alloc failed"
    _MD-TMP !

    \ Allocate partial data array
    _MD-C-N @ _MD-PSTRIDE * ALLOCATE
    0<> ABORT" MODAL-CREATE: pdata alloc failed"
    _MD-TMP @ MD.PDATA !

    \ Zero partial data
    _MD-TMP @ MD.PDATA @
    _MD-C-N @ _MD-PSTRIDE *
    0 FILL

    \ Set defaults
    _MD-C-N @          _MD-TMP @ MD.N     !
    220 INT>FP16       _MD-TMP @ MD.FUND  !  \ A3 default
    _MD-FP16-ZERO      _MD-TMP @ MD.BRI   !  \ brightness = 0
    _MD-FP16-ONE       _MD-TMP @ MD.DAMP  !  \ damping = 1.0
    0                  _MD-TMP @ MD.NMS   !  \ no noise transient
    4000 INT>FP16      _MD-TMP @ MD.NBW   !  \ noise HP cutoff 4kHz
    _MD-C-R @          _MD-TMP @ MD.RATE  !

    _MD-TMP @ ;

\ =====================================================================
\  MODAL-FREE — Free descriptor and partial data
\ =====================================================================

: MODAL-FREE  ( desc -- )
    DUP MD.PDATA @ FREE
    FREE ;

\ =====================================================================
\  Setters
\ =====================================================================

: MODAL-FUND!       ( freq desc -- )  MD.FUND ! ;
: MODAL-BRIGHTNESS! ( b desc -- )     MD.BRI  ! ;
: MODAL-DAMPING!    ( d desc -- )     MD.DAMP ! ;

: MODAL-NOISE!  ( ms bw desc -- )
    _MD-TMP !
    _MD-TMP @ MD.NBW !
    _MD-TMP @ MD.NMS ! ;

\ =====================================================================
\  MODAL-PARTIAL! — Set one partial by index
\ =====================================================================
\  ( ratio amp decay-sec i desc -- )
\  ratio     = frequency ratio to fundamental (FP16)
\  amp       = initial amplitude 0.0–1.0 (FP16)
\  decay-sec = T60 decay time in seconds (FP16)
\  i         = zero-based partial index

VARIABLE _MD-P-PDATA

: MODAL-PARTIAL!  ( ratio amp decay-sec i desc -- )
    _MD-TMP !
    _MD-TMP @ MD.PDATA @ _MD-P-PDATA !
    \ stack: ratio amp decay-sec i
    >R                                \ R: i
    _MD-P-PDATA @ R@ SWAP _MD-PDEC W!     \ decay-sec
    _MD-P-PDATA @ R@ SWAP _MD-PAMP  W!    \ amp
    _MD-P-PDATA @ R> SWAP _MD-PRATIO W!   \ ratio
    ;

\ =====================================================================
\  MODAL-LOAD-TABLE — Load N partials from a packed FP16 table
\ =====================================================================
\  ( table n desc -- )
\  Table format: N × 3 consecutive FP16 words: ratio amp decay-sec
\  n must be <= descriptor's n-partials.

VARIABLE _MD-LT-N
VARIABLE _MD-LT-SRC
VARIABLE _MD-LT-DST

: MODAL-LOAD-TABLE  ( table n desc -- )
    _MD-TMP !
    _MD-LT-N !
    _MD-LT-SRC !
    _MD-TMP @ MD.PDATA @ _MD-LT-DST !
    \ copy n * 6 bytes straight
    _MD-LT-SRC @
    _MD-LT-DST @
    _MD-LT-N @ _MD-PSTRIDE *
    MOVE ;

\ =====================================================================
\  MODAL-DURATION — Estimated audible duration in ms
\ =====================================================================
\  ( desc -- ms )
\  Finds the maximum decay-sec among all partials, multiplies by
\  damping, converts to ms, clamps to _MD-MAX-MS.

VARIABLE _MD-DUR-MAX
VARIABLE _MD-DUR-I
VARIABLE _MD-DUR-PD

: MODAL-DURATION  ( desc -- ms )
    _MD-TMP !
    _MD-FP16-ZERO _MD-DUR-MAX !
    _MD-TMP @ MD.PDATA @ _MD-DUR-PD !
    _MD-TMP @ MD.N @ 0 DO
        _MD-DUR-PD @ I SWAP _MD-PDEC W@   ( decay-sec FP16 )
        DUP _MD-DUR-MAX @ FP16-GT IF
            _MD-DUR-MAX !
        ELSE
            DROP
        THEN
    LOOP
    \ ms = decay_sec * damping * 1000
    _MD-DUR-MAX @
    _MD-TMP @ MD.DAMP @ FP16-MUL
    _MD-FP16-1000 FP16-MUL
    FP16>INT
    _MD-MAX-MS MIN ;

\ =====================================================================
\  Built-in partial ratio tables
\ =====================================================================
\
\  Each table is a packed array of FP16 triplets: ratio amp decay-sec
\  All amplitudes default to 1.0 (even spread — scale with brightness).
\  Decay times are physical estimates: highest partial decays fastest.
\
\  Usage:
\    MODAL-TBL-BRONZE-DATA MODAL-TBL-BRONZE-N desc MODAL-LOAD-TABLE

\ Macro: create a named table.
\  _MD-TBL-BEGIN name n
\  ... n groups of 3 FP16 hex constants ...
\  _MD-TBL-END name n

: W,  ( fp16-bits -- )  HERE W! 2 ALLOT ;  \ compile 16-bit word into dict

\ Helper: approximate FP16 for common ratios used in tables.
\ Rather than hand-computing all FP16 bit patterns, we emit them
\ inline.  Values computed with IEEE 754 half-precision rules.

\ MODAL-TBL-BRONZE — warm bell, typical bronze
\ Ratios: 1.0 2.0 2.76 5.40 8.93 11.34 14.57 18.64
\ Amps:   1.0 0.8 0.64 0.40 0.25 0.16  0.10  0.063
\ Decays: 2.0 1.6 1.1  0.7  0.45 0.30  0.20  0.13  (seconds)
8 CONSTANT MODAL-TBL-BRONZE-N
CREATE MODAL-TBL-BRONZE-DATA
  \ ratio  amp     decay-sec
  0x3C00 W,  0x3C00 W,  0x4000 W,   \ 1.00  1.00  2.00
  0x4000 W,  0x3A66 W,  0x3E66 W,   \ 2.00  0.80  1.60
  0x4180 W,  0x3914 W,  0x3C7A W,   \ 2.76  0.64  1.10
  0x4566 W,  0x3666 W,  0x3B33 W,   \ 5.40  0.40  0.70
  0x4875 W,  0x3400 W,  0x39A3 W,   \ 8.93  0.25  0.45
  0x4BAB W,  0x3119 W,  0x34CD W,   \ 11.34 0.16  0.30
  0x4F48 W,  0x2E00 W,  0x3266 W,   \ 14.57 0.10  0.20
  0x52B5 W,  0x2814 W,  0x3020 W,   \ 18.64 0.063 0.13

\ MODAL-TBL-STEEL — hard, bright metallic bell
\ Ratios: 1.0 2.32 3.18 5.87 9.41 13.02 17.04 22.01
\ Amps:   1.0 0.75 0.55 0.35 0.22 0.14  0.09  0.055
\ Decays: 3.0 2.0  1.2  0.65 0.38 0.23  0.14  0.09
8 CONSTANT MODAL-TBL-STEEL-N
CREATE MODAL-TBL-STEEL-DATA
  0x3C00 W,  0x3C00 W,  0x4200 W,   \ 1.00  1.00  3.00
  0x4099 W,  0x3A00 W,  0x4000 W,   \ 2.32  0.75  2.00
  0x4266 W,  0x3870 W,  0x3C7A W,   \ 3.18  0.55  1.20
  0x45EB W,  0x3599 W,  0x3933 W,   \ 5.87  0.35  0.65
  0x48F5 W,  0x3311 W,  0x360A W,   \ 9.41  0.22  0.38
  0x4D04 W,  0x30F0 W,  0x3357 W,   \ 13.02 0.14  0.23
  0x5043 W,  0x2DC3 W,  0x30F0 W,   \ 17.04 0.09  0.14
  0x5584 W,  0x2B1C W,  0x2DC3 W,   \ 22.01 0.055 0.09

\ MODAL-TBL-GLASS — crisp, fast upper decay
\ Ratios: 1.0 2.67 4.18 7.50 12.33 15.80
\ Amps:   1.0 0.70 0.45 0.25 0.14  0.08
\ Decays: 1.5 0.7  0.35 0.15 0.07  0.04
6 CONSTANT MODAL-TBL-GLASS-N
CREATE MODAL-TBL-GLASS-DATA
  0x3C00 W,  0x3C00 W,  0x3E00 W,   \ 1.00  1.00  1.50
  0x4155 W,  0x3B99 W,  0x3B33 W,   \ 2.67  0.70  0.70
  0x4428 W,  0x3733 W,  0x3599 W,   \ 4.18  0.45  0.35
  0x4780 W,  0x3400 W,  0x313B W,   \ 7.50  0.25  0.15
  0x4E2B W,  0x30F0 W,  0x2C7B W,   \ 12.33 0.14  0.07
  0x4BE6 W,  0x2D1C W,  0x2947 W,   \ 15.80 0.08  0.04

\ MODAL-TBL-BOWL — singing bowl, close mode spacing
\ Ratios: 1.0 2.63 4.79 7.41 10.49 14.03
\ Amps:   1.0 0.60 0.40 0.25 0.15  0.08
\ Decays: 4.0 2.5  1.4  0.7  0.35  0.18
6 CONSTANT MODAL-TBL-BOWL-N
CREATE MODAL-TBL-BOWL-DATA
  0x3C00 W,  0x3C00 W,  0x4400 W,   \ 1.00  1.00  4.00
  0x4143 W,  0x38CD W,  0x4100 W,   \ 2.63  0.60  2.50
  0x44C8 W,  0x3666 W,  0x3D99 W,   \ 4.79  0.40  1.40
  0x4765 W,  0x3400 W,  0x3B33 W,   \ 7.41  0.25  0.70
  0x4A3F W,  0x31EB W,  0x3599 W,   \ 10.49 0.15  0.35
  0x4F04 W,  0x2D1C W,  0x31EB W,   \ 14.03 0.08  0.18

\ MODAL-TBL-SLAB — flat stone or wooden slab
\ Ratios: 1.0 1.58 2.42 3.52 4.88 6.49
\ Amps:   1.0 0.75 0.55 0.38 0.25 0.15
\ Decays: 0.8 0.5  0.3  0.18 0.10 0.06
6 CONSTANT MODAL-TBL-SLAB-N
CREATE MODAL-TBL-SLAB-DATA
  0x3C00 W,  0x3C00 W,  0x3A67 W,   \ 1.00  1.00  0.80
  0x3E71 W,  0x3A00 W,  0x3800 W,   \ 1.58  0.75  0.50
  0x40EB W,  0x3870 W,  0x34CD W,   \ 2.42  0.55  0.30
  0x430A W, 0x3614 W,  0x31EB W,   \ 3.52  0.38  0.18
  0x44E8 W,  0x3400 W,  0x2E66 W,   \ 4.88  0.25  0.10
  0x46F5 W,  0x31EB W,  0x2BD0 W,   \ 6.49  0.15  0.06

\ MODAL-TBL-ABSTRACT-A — near-harmonic alien tone
\ Ratios: 1.0 1.41 2.24 3.16 4.47 5.62
\ Amps:   1.0 0.70 0.48 0.32 0.20 0.12
\ Decays: 2.5 1.8  1.1  0.65 0.38 0.22
6 CONSTANT MODAL-TBL-ABSTRACT-A-N
CREATE MODAL-TBL-ABSTRACT-A-DATA
  0x3C00 W,  0x3C00 W,  0x4100 W,   \ 1.00  1.00  2.50
  0x3DA3 W,  0x3B99 W,  0x3F33 W,   \ 1.41  0.70  1.80
  0x4047 W,  0x37AE W,  0x3C7A W,   \ 2.24  0.48  1.10
  0x424F W,  0x3524 W,  0x3933 W,   \ 3.16  0.32  0.65
  0x4479 W,  0x3266 W,  0x360A W,   \ 4.47  0.20  0.38
  0x4597 W,  0x2F5C W,  0x3311 W,   \ 5.62  0.12  0.22

\ MODAL-TBL-ABSTRACT-B — spread, bell-like but alien
\ Ratios: 1.0 3.73 7.11 12.2 19.0 27.4
\ Amps:   1.0 0.65 0.40 0.24 0.14 0.08
\ Decays: 3.0 1.5  0.65 0.28 0.12 0.05
6 CONSTANT MODAL-TBL-ABSTRACT-B-N
CREATE MODAL-TBL-ABSTRACT-B-DATA
  0x3C00 W,  0x3C00 W,  0x4200 W,   \ 1.00  1.00  3.00
  0x4374 W,  0x392E W,  0x3E00 W,   \ 3.73  0.65  1.50
  0x4717 W,  0x3666 W,  0x3933 W,   \ 7.11  0.40  0.65
  0x4E14 W,  0x33EB W,  0x347B W,   \ 12.2  0.24  0.28
  0x524C W,  0x30F0 W,  0x2F5C W,   \ 19.0  0.14  0.12
  0x56D1 W,  0x2DC3 W,  0x2A3D W,   \ 27.4  0.08  0.05

\ MODAL-TBL-TUBULAR — tubular chime
\ Ratios: 1.0 2.76 5.40 8.93 13.34 18.64
\ Amps:   1.0 0.50 0.35 0.22 0.13  0.07
\ Decays: 5.0 2.5  1.2  0.55 0.25  0.11
6 CONSTANT MODAL-TBL-TUBULAR-N
CREATE MODAL-TBL-TUBULAR-DATA
  0x3C00 W,  0x3C00 W,  0x4500 W,   \ 1.00  1.00  5.00
  0x4180 W,  0x3800 W,  0x4100 W,   \ 2.76  0.50  2.50
  0x4566 W,  0x3599 W,  0x3C7A W,   \ 5.40  0.35  1.20
  0x4875 W,  0x3311 W,  0x3870 W,   \ 8.93  0.22  0.55
  0x4D56 W,  0x2FEB W,  0x3400 W,   \ 13.34 0.13  0.25
  0x52B5 W,  0x2C8F W,  0x2E7A W,   \ 18.64 0.07  0.11

\ =====================================================================
\  Internal: initialize strike state block
\ =====================================================================
\  Allocates 4×N×2-byte state block.
\  Fills phase=0, running_amp, block_decay, phase_inc.
\  ( desc velocity -- state )

VARIABLE _MD-SI-DESC
VARIABLE _MD-SI-VEL
VARIABLE _MD-SI-STATE
VARIABLE _MD-SI-PD
VARIABLE _MD-SI-I
VARIABLE _MD-SI-RATIO
VARIABLE _MD-SI-AMP
VARIABLE _MD-SI-DEC
VARIABLE _MD-SI-BSCALE
VARIABLE _MD-SI-F         \ partial freq = fund * ratio

: _MD-STRIKE-INIT  ( desc velocity -- state )
    _MD-SI-VEL !  _MD-SI-DESC !

    _MD-SI-DESC @ MD.N     @ _MD-N     !
    _MD-SI-DESC @ MD.RATE  @ _MD-RATE  !
    _MD-SI-DESC @ MD.FUND  @ _MD-FUND  !
    _MD-SI-DESC @ MD.DAMP  @ _MD-DAMP  !
    _MD-SI-DESC @ MD.PDATA @ _MD-PDATA !

    \ Allocate state block: 4 × N × 2 bytes
    _MD-N @ 8 *  ALLOCATE
    0<> ABORT" MODAL-STRIKE: state alloc failed"
    _MD-SI-STATE !

    \ Initialize all phases to 0.0
    _MD-SI-STATE @  _MD-N @ 2*  0 FILL

    _MD-N @ 1-  _MD-SI-I !          \ n-1 for brightness scaling
    _MD-N @ 0 DO
        _MD-PDATA @ I SWAP _MD-PRATIO W@ _MD-SI-RATIO !
        _MD-PDATA @ I SWAP _MD-PAMP  W@ _MD-SI-AMP   !
        _MD-PDATA @ I SWAP _MD-PDEC  W@ _MD-SI-DEC   !

        \ partial freq = fundamental × ratio
        _MD-FUND @  _MD-SI-RATIO @ FP16-MUL  _MD-SI-F !

        \ phase_inc = freq / rate  (advance per sample)
        _MD-SI-F @  _MD-RATE @ INT>FP16 FP16-DIV
        I _MD-N @ _MD-SI-STATE @ _MD-ST-PINC W!

        \ brightness scale factor
        I  _MD-SI-I @  _MD-SI-DESC @ MD.BRI @  _MD-BSCALE  _MD-SI-BSCALE !

        \ running_amp = amp × velocity × brightness_scale
        _MD-SI-AMP @
        _MD-SI-VEL @    FP16-MUL
        _MD-SI-BSCALE @ FP16-MUL
        I _MD-N @ _MD-SI-STATE @ _MD-ST-RAMP W!

        \ block decay factor for this partial × damping
        _MD-SI-DEC @
        _MD-DAMP @
        _MD-RATE @
        _MD-BLOCK-DECAY
        I _MD-N @ _MD-SI-STATE @ _MD-ST-BDEC W!
    LOOP

    _MD-SI-STATE @ ;

\ =====================================================================
\  Internal: render noise transient into PCM buffer
\ =====================================================================
\  ( buf desc -- )
\  If noise-ms = 0, does nothing.
\  Renders HP-filtered white noise with fast AR decay into the buffer,
\  adding to any existing content.

VARIABLE _MD-NT-BUF
VARIABLE _MD-NT-DESC
VARIABLE _MD-NT-MS
VARIABLE _MD-NT-HPC     \ HP alpha coefficient FP16
VARIABLE _MD-NT-FRAMES
VARIABLE _MD-NT-NG      \ noise generator
VARIABLE _MD-NT-DECF    \ per-sample decay factor FP16
VARIABLE _MD-NT-AMP
VARIABLE _MD-NT-XPREV   \ previous input sample (FP16)
VARIABLE _MD-NT-YPREV   \ previous HP output sample (FP16)
VARIABLE _MD-NT_CURAMP  \ current amplitude (FP16)
VARIABLE _MD-NT-I
VARIABLE _MD-NT-X
VARIABLE _MD-NT-Y
VARIABLE _MD-NT-DPTR    \ raw data pointer

: _MD-NOISE-TRANSIENT  ( buf desc -- )
    _MD-NT-DESC !
    _MD-NT-BUF  !

    _MD-NT-DESC @ MD.NMS @ _MD-NT-MS !
    _MD-NT-MS @ 0= IF EXIT THEN        \ disabled

    \ compute HP alpha = 1 - 2π × bw / rate
    \ alpha = (rate - 2π*bw) / rate — computed in integer domain
    \ approximate: alpha ≈ 1 - bw*6/rate  (6 ≈ 2π, good enough)
    _MD-NT-DESC @ MD.NBW @ FP16>INT    \ bw as integer Hz
    6 *                                \ × 6 ≈ 2π
    _MD-NT-DESC @ MD.RATE @ SWAP -     \ rate - 2π*bw
    DUP 0< IF DROP 0 THEN              \ clamp to 0
    INT>FP16
    _MD-NT-DESC @ MD.RATE @ INT>FP16 FP16-DIV
    _MD-NT-HPC !                       \ alpha FP16

    \ frames to render for transient
    _MD-NT-MS @
    _MD-NT-DESC @ MD.RATE @ *
    1000 /
    _MD-NT-FRAMES !

    \ compute per-sample amplitude decay over noise-ms:
    \ want to reach ~1/1000 in noise-ms samples
    \ x = ln(1000) / frames ≈ 6.908 / frames
    6908 INT>FP16
    1000 INT>FP16 FP16-DIV             \ 6.908 FP16
    _MD-NT-FRAMES @ INT>FP16 FP16-DIV \ x per sample
    _MD-EXP-NEG  _MD-NT-DECF !        \ per-sample decay factor

    \ init noise generator
    NOISE-WHITE NOISE-CREATE _MD-NT-NG !

    \ init HP state
    _MD-FP16-ZERO _MD-NT-XPREV !
    _MD-FP16-ZERO _MD-NT-YPREV !
    _MD-FP16-ONE  _MD-NT_CURAMP !

    \ raw data pointer for direct write
    _MD-NT-BUF @ PCM-DATA _MD-NT-DPTR !

    _MD-NT-FRAMES @ 0 DO
        \ HP-filtered noise sample
        _MD-NT-NG @ NOISE-SAMPLE _MD-NT-X !
        _MD-NT-X @
        _MD-NT-XPREV @ FP16-SUB          \ x - x_prev
        _MD-NT-HPC @  _MD-NT-YPREV @ FP16-MUL  FP16-ADD  \ + alpha*y_prev
        _MD-NT-YPREV !
        _MD-NT-X @ _MD-NT-XPREV !        \ x_prev = x

        \ scale by current amplitude and add into output
        _MD-NT-YPREV @
        _MD-NT_CURAMP @ FP16-MUL
        \ add to existing sample
        _MD-NT-DPTR @ I 2* + W@
        FP16-ADD
        _MD-NT-DPTR @ I 2* + W!

        \ decay amplitude
        _MD-NT_CURAMP @  _MD-NT-DECF @  FP16-MUL  _MD-NT_CURAMP !
    LOOP

    _MD-NT-NG @ NOISE-FREE ;

\ =====================================================================
\  Internal: render modal partials into PCM buffer
\ =====================================================================
\  ( buf state desc -- )

VARIABLE _MD-R-BUF
VARIABLE _MD-R-STATE
VARIABLE _MD-R-DESC
VARIABLE _MD-R-FRAMES
VARIABLE _MD-R-BLKS
VARIABLE _MD-R-BLK
VARIABLE _MD-R-SMP
VARIABLE _MD-R-I
VARIABLE _MD-R-SUM
VARIABLE _MD-R-PH
VARIABLE _MD-R-AMP
VARIABLE _MD-R-INC
VARIABLE _MD-R-DPTR   \ raw sample data pointer
VARIABLE _MD-R-BLKEND \ last full 32-sample block end

: _MD-RENDER-PARTIALS  ( buf state desc -- )
    _MD-R-DESC !  _MD-R-STATE !  _MD-R-BUF !

    _MD-R-DESC @ MD.N @ _MD-N !

    _MD-R-BUF @ PCM-LEN    _MD-R-FRAMES !
    _MD-R-BUF @ PCM-DATA   _MD-R-DPTR   !

    \ floor(frames / 32) full blocks
    _MD-R-FRAMES @ 32 /  _MD-R-BLKS !
    _MD-R-BLKS @ 32 *    _MD-R-BLKEND !

    \ ---- Main render: full 32-sample blocks ----
    _MD-R-BLKS @ 0 DO
        I 32 *  _MD-R-BLK !   \ block start sample index

        \ Inner: 32 samples — sum all partials
        32 0 DO
            _MD-R-BLK @ I + _MD-R-SMP !  \ absolute sample index
            _MD-FP16-ZERO _MD-R-SUM !

            _MD-N @ 0 DO
                I _MD-N @ _MD-R-STATE @ _MD-ST-PHASE W@  _MD-R-PH  !
                I _MD-N @ _MD-R-STATE @ _MD-ST-RAMP  W@  _MD-R-AMP !
                I _MD-N @ _MD-R-STATE @ _MD-ST-PINC  W@  _MD-R-INC !

                \ sample = amp × sin(phase) via wavetable
                _MD-R-PH @ WT-SIN-TABLE WT-LOOKUP
                _MD-R-AMP @ FP16-MUL
                _MD-R-SUM @ FP16-ADD  _MD-R-SUM !

                \ advance phase, wrap into [0,1)
                _MD-R-PH @ _MD-R-INC @ FP16-ADD
                BEGIN DUP _MD-FP16-ONE FP16-GE WHILE _MD-FP16-ONE FP16-SUB REPEAT
                I _MD-N @ _MD-R-STATE @ _MD-ST-PHASE W!
            LOOP

            \ write accumulated sum to buffer
            _MD-R-SUM @
            _MD-R-DPTR @ _MD-R-SMP @ 2* + W!
        LOOP

        \ ---- After each block: apply decay to all running amps ----
        _MD-N @ 0 DO
            I _MD-N @ _MD-R-STATE @ _MD-ST-RAMP W@
            I _MD-N @ _MD-R-STATE @ _MD-ST-BDEC W@
            FP16-MUL
            I _MD-N @ _MD-R-STATE @ _MD-ST-RAMP W!
        LOOP
    LOOP

    \ ---- Tail: remaining frames past last full block ----
    _MD-R-FRAMES @ _MD-R-BLKEND @ ?DO
        _MD-FP16-ZERO _MD-R-SUM !
        _MD-N @ 0 DO
            I _MD-N @ _MD-R-STATE @ _MD-ST-PHASE W@  _MD-R-PH  !
            I _MD-N @ _MD-R-STATE @ _MD-ST-RAMP  W@  _MD-R-AMP !
            I _MD-N @ _MD-R-STATE @ _MD-ST-PINC  W@  _MD-R-INC !

            _MD-R-PH @ WT-SIN-TABLE WT-LOOKUP
            _MD-R-AMP @ FP16-MUL
            _MD-R-SUM @ FP16-ADD  _MD-R-SUM !

            _MD-R-PH @ _MD-R-INC @ FP16-ADD
            BEGIN DUP _MD-FP16-ONE FP16-GE WHILE _MD-FP16-ONE FP16-SUB REPEAT
            I _MD-N @ _MD-R-STATE @ _MD-ST-PHASE W!
        LOOP
        _MD-R-SUM @
        _MD-R-DPTR @ I 2* + W!
    LOOP ;

\ =====================================================================
\  MODAL-STRIKE — Render a strike, return new PCM buffer
\ =====================================================================
\  ( velocity desc -- buf )
\  velocity = FP16 0.0–1.0
\  Returns freshly allocated mono 16-bit PCM buffer.
\  Caller must PCM-FREE when done.

VARIABLE _MD-STK-DESC
VARIABLE _MD-STK-VEL
VARIABLE _MD-STK-STATE
VARIABLE _MD-STK-BUF
VARIABLE _MD-STK-MS
VARIABLE _MD-STK-FRAMES

: MODAL-STRIKE  ( velocity desc -- buf )
    _MD-STK-DESC !  _MD-STK-VEL !

    \ Duration in ms: clamp to 50–_MD-MAX-MS
    _MD-STK-DESC @ MODAL-DURATION
    50 MAX  _MD-MAX-MS MIN  _MD-STK-MS !

    \ Allocate output buffer (mono, 16-bit FP16 samples)
    _MD-STK-MS @
    _MD-STK-DESC @ MD.RATE @
    *  1000 /                          \ frames = ms * rate / 1000
    _MD-STK-DESC @ MD.RATE @
    16 1 PCM-ALLOC
    _MD-STK-BUF !

    _MD-STK-BUF @ PCM-CLEAR             \ zero buffer

    \ Initialize strike state
    _MD-STK-DESC @  _MD-STK-VEL @  _MD-STRIKE-INIT  _MD-STK-STATE !

    \ Render partials
    _MD-STK-BUF @  _MD-STK-STATE @  _MD-STK-DESC @  _MD-RENDER-PARTIALS

    \ Add noise transient (if enabled)
    _MD-STK-BUF @  _MD-STK-DESC @  _MD-NOISE-TRANSIENT

    \ Free temp state
    _MD-STK-STATE @ FREE

    _MD-STK-BUF @ ;

\ =====================================================================
\  MODAL-STRIKE-INTO — Render, add into existing PCM buffer
\ =====================================================================
\  ( buf velocity desc -- )
\  Renders at desc's parameters and velocity, sums into buf.
\  buf must be mono 16-bit.  Renders min(buf length, strike length)
\  frames.

VARIABLE _MD-STI-BUF
VARIABLE _MD-STI-VEL
VARIABLE _MD-STI-DESC
VARIABLE _MD-STI-STATE
VARIABLE _MD-STI-SPTR   \ raw source data
VARIABLE _MD-STI-DPTR   \ raw dest data
VARIABLE _MD-STI-LEN

: MODAL-STRIKE-INTO  ( buf velocity desc -- )
    _MD-STI-DESC !  _MD-STI-VEL !  _MD-STI-BUF !

    \ Render to temp buffer first
    _MD-STI-VEL @  _MD-STI-DESC @  MODAL-STRIKE
    ( strike-buf )

    \ Mix: add sample-by-sample for min(src, dst) frames
    DUP PCM-LEN  _MD-STI-BUF @ PCM-LEN  MIN  _MD-STI-LEN !
    DUP PCM-DATA _MD-STI-SPTR !
    _MD-STI-BUF @ PCM-DATA  _MD-STI-DPTR !

    _MD-STI-LEN @ 0 DO
        _MD-STI-SPTR @ I 2* + W@
        _MD-STI-DPTR @ I 2* + W@
        FP16-ADD
        _MD-STI-DPTR @ I 2* + W!
    LOOP
    PCM-FREE ;
