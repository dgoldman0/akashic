\ wavetable.f — Precomputed waveform lookup tables
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Provides a 2048-entry sine wavetable for fast oscillator rendering.
\ A table lookup + linear interpolation (~7 operations) replaces the
\ ~15-operation TRIG-SIN polynomial, cutting sine oscillator cost
\ by roughly 2×.
\
\ Phase convention: FP16 in [0.0, 1.0), matching the oscillator
\ phase accumulator convention used by osc.f and fm.f.
\
\ Table layout: 2048 cells (8 bytes each = 16 KB).  Each cell
\ stores a FP16 sine value in [-1.0, +1.0] in the low 16 bits.
\ One full sine cycle is mapped across the 2048 entries:
\   table[i] = sin(2π × i / 2048)
\
\ The global sine table (WT-SIN-TABLE) is eagerly allocated and
\ filled at module load time.  Cost: ~60 K Forth operations
\ (2048 × TRIG-SIN), a one-time expense amortised into the
\ snapshot.
\
\ Prefix: WT-    (public API)
\         _WT-   (internals)
\
\ Load with:   REQUIRE audio/wavetable.f
\
\ === Public API ===
\   WT-LOOKUP     ( phase table -- sample )   truncating lookup
\   WT-LERP       ( phase table -- sample )   linear-interpolated lookup
\   WT-SIN-TABLE  ( -- addr )                 global precomputed sine table
\   WT-FILL-SIN   ( addr -- )                 fill table with one sine cycle
\   WT-ALLOC      ( -- addr )                 allocate a blank 2048-entry table
\   WT-SIZE       ( -- 2048 )
\   WT-MASK       ( -- 2047 )

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE ../math/simd-ext.f

PROVIDED akashic-audio-wavetable

\ =====================================================================
\  Constants
\ =====================================================================

2048 CONSTANT WT-SIZE
2047 CONSTANT WT-MASK

\ FP16 bit patterns for 2048.0 and 1/2048
\ 2048 = 2^11 → FP16: sign=0, exp=11+15=26, frac=0 → 0x6800
\ 1/2048 = 2^−11 → FP16: sign=0, exp=−11+15=4,  frac=0 → 0x1000

0x6800 CONSTANT _WT-FP16-SIZE         \ 2048.0
0x1000 CONSTANT _WT-FP16-INV-SIZE     \ 1/2048

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _WT-TBL       \ table address scratch
VARIABLE _WT-IDX       \ integer index scratch
VARIABLE _WT-S0        \ sample 0 scratch
VARIABLE _WT-S1        \ sample 1 scratch

\ =====================================================================
\  WT-ALLOC — Allocate a blank wavetable (2048 cells = 16 KB)
\ =====================================================================
\  ( -- addr )

: WT-ALLOC ( -- addr )
    WT-SIZE CELLS ALLOCATE
    0<> ABORT" WT-ALLOC: alloc failed" ;

\ =====================================================================
\  WT-FILL-SIN — Fill table with sin(2π × i / 2048) for i = 0..2047
\ =====================================================================
\  ( addr -- )
\  One-time cost at load: 2048 × TRIG-SIN (~30 ops each).

: WT-FILL-SIN ( addr -- )
    WT-SIZE 0 DO
        I INT>FP16
        _WT-FP16-INV-SIZE FP16-MUL   \ i × (1/2048) = phase [0, 1)
        TRIG-2PI FP16-MUL            \ phase × 2π → angle in radians
        TRIG-SIN                      \ sin(angle) → FP16 in [-1, +1]
        OVER I CELLS + !             \ table[i] = value
    LOOP
    DROP ;

\ =====================================================================
\  WT-LOOKUP — Truncating wavetable lookup (fastest, no interpolation)
\ =====================================================================
\  ( phase table -- sample )
\  phase = FP16 in [0.0, 1.0)
\  Cost: ~4 ops (multiply, convert, mask, fetch)

: WT-LOOKUP ( phase table -- sample )
    SWAP                              ( table phase )
    _WT-FP16-SIZE FP16-MUL           \ phase × 2048 → scaled
    FP16>INT WT-MASK AND              \ integer index, wrapped to [0,2047]
    CELLS + @ ;                       ( sample )

\ =====================================================================
\  WT-LERP — Linear-interpolated wavetable lookup
\ =====================================================================
\  ( phase table -- sample )
\  phase = FP16 in [0.0, 1.0)
\  Fetches two adjacent entries, interpolates by the fractional part.
\  Cost: ~10 ops (multiply, floor, subtract, 2 fetches, LERP)

: WT-LERP ( phase table -- sample )
    _WT-TBL !                         \ save table address
    _WT-FP16-SIZE FP16-MUL           \ phase × 2048 → scaled
    DUP FP16-FLOOR                    ( scaled floored )
    DUP FP16>INT WT-MASK AND          \ integer index, wrapped
    _WT-IDX !
    FP16-SUB                          ( frac )  \ scaled − floored
    \ Fetch two adjacent samples
    _WT-IDX @          CELLS _WT-TBL @ + @ _WT-S0 !
    _WT-IDX @ 1+ WT-MASK AND CELLS _WT-TBL @ + @ _WT-S1 !
    \ Interpolate: LERP( s0, s1, frac ) = s0 + frac×(s1−s0)
    _WT-S0 @ _WT-S1 @ ROT            ( s0 s1 frac )
    FP16-LERP ;

\ =====================================================================
\  Global sine table — eagerly filled at module load time
\ =====================================================================
\  WT-SIN-TABLE is a CONSTANT: push the address of the precomputed
\  2048-entry sine table.

WT-ALLOC DUP WT-FILL-SIN CONSTANT WT-SIN-TABLE

\ =====================================================================
\  Block-mode wavetable fill — integer phase accumulation
\ =====================================================================
\  Avoids FP16 arithmetic in the inner loop entirely.
\  Phase is a fixed-point integer: bits 16..26 = table index (0-2047),
\  bits 0..15 = fractional (unused for truncating lookup).
\  The mask 0x3FF8 applied after >> 13 extracts the 8-byte cell offset.
\
\  WT-BLOCK-INC  ( freq rate -- inc )   compute integer phase increment
\  WT-BLOCK-FILL ( phase inc n tbl dst -- phase' )  fill n FP16 samples
\  WT-BLOCK-ADD  ( phase inc n tbl src dst -- phase' ) add n samples
\  WT-PH>INT     ( fp16-phase -- int-phase )  convert FP16 [0,1) to int
\  WT-INT>PH     ( int-phase -- fp16-phase )  convert int to FP16 [0,1)

\ Scale factor: WT-SIZE << 16 = 2048 * 65536 = 134217728
2048 65536 * CONSTANT _WT-SCALE

\ Mask for extracting cell-aligned byte offset from shifted phase:
\   phase >> 13 gives bits 3..13 of the raw phase (table index * 8).
\   AND with 0x3FF8 masks to 11 bits * 8 = valid offsets 0..16376.
0x3FF8 CONSTANT _WT-BYTE-MASK

VARIABLE _WT-BPH    \ block phase accumulator
VARIABLE _WT-BINC   \ block increment
VARIABLE _WT-BTBL   \ block table base

\ WT-BLOCK-INC — compute integer phase increment
\  ( freq rate -- inc )
\  inc = FP16>INT(freq) * _WT-SCALE / rate
\  Falls back to FP16 math for sub-1Hz (returns 0 if freq < 1Hz integer)

: WT-BLOCK-INC  ( freq rate -- inc )
    SWAP FP16>INT              ( rate freq_int )
    DUP 0= IF                 \ sub-1Hz → return 0 as signal
        2DROP 0 EXIT
    THEN
    _WT-SCALE * SWAP / ;      ( inc )

\ WT-PH>INT — convert FP16 phase [0.0, 1.0) to integer phase
\  ( fp16-phase -- int-phase )
\  int = FP16>INT( phase * 2048 ) << 16
\  Precision: ~11 bits (ok for 2048-entry table)

: WT-PH>INT  ( fp16-phase -- int-phase )
    _WT-FP16-SIZE FP16-MUL    \ phase * 2048.0
    FP16>INT                   \ truncate to integer table index
    16 LSHIFT ;                \ shift to fixed-point format

\ WT-INT>PH — convert integer phase back to FP16 [0.0, 1.0)
\  ( int-phase -- fp16-phase )

: WT-INT>PH  ( int-phase -- fp16-phase )
    16 RSHIFT                  \ extract table index
    WT-MASK AND                \ wrap
    INT>FP16
    _WT-FP16-INV-SIZE FP16-MUL ;  \ index / 2048.0

\ WT-BLOCK-FILL — fill n packed FP16 samples via truncating lookup
\  ( phase inc n tbl dst -- phase' )
\  dst points to packed 2-byte FP16 array (PCM-DATA).
\  Inner loop: ~40 cycles/sample (vs ~700 with WT-LERP path).

: WT-BLOCK-FILL  ( phase inc n tbl dst -- phase' )
    SWAP _WT-BTBL !            \ save tbl.       S: phase inc n dst
    SWAP >R                    \ push n to R.     S: phase inc dst   R: n
    ROT ROT                    \                  S: dst phase inc
    _WT-BINC !                 \ save inc.        S: dst phase
    _WT-BPH !                  \ save phase.      S: dst
    R>                         \ get n back.      S: dst n
    0 DO                       \ loop n times.    S: dst
        _WT-BPH @
        13 RSHIFT _WT-BYTE-MASK AND   \ byte offset into table
        _WT-BTBL @ +          \ table + offset → cell addr
        @                      \ fetch FP16 value
        OVER I 2 * +          \ dst + I*2 → write addr
        W!                     \ store FP16 sample
        _WT-BINC @ _WT-BPH +! \ phase += inc
    LOOP
    DROP                       \ drop dst
    _WT-BPH @ ;               \ return updated phase

\ Static scratch buffer for SIMD block-add (8192 samples × 2 bytes)
8192 CONSTANT _WT-SCRATCH-SIZE
_WT-SCRATCH-SIZE 2 * ALLOCATE 0<> ABORT" WT: scratch alloc" CONSTANT _WT-SCRATCH

\ WT-BLOCK-ADD — add n samples to existing packed FP16 buffer
\  ( phase inc n tbl dst -- phase' )
\  Strategy: fill scratch via WT-BLOCK-FILL, then SIMD-ADD-N scratch+dst→dst.
\  This replaces ~130cy scalar FP16-ADD per sample with ~2cy amortised SIMD.

VARIABLE _WT-BA-DST
VARIABLE _WT-BA-N
VARIABLE _WT-BA-TBL
VARIABLE _WT-BA-INC

: WT-BLOCK-ADD  ( phase inc n tbl dst -- phase' )
    _WT-BA-DST !               \ save dst
    _WT-BA-TBL !               \ save tbl
    _WT-BA-N !                 \ save n
    _WT-BA-INC !               \ save inc.       S: phase
    \ Fill scratch with wavetable samples
    _WT-BA-INC @
    _WT-BA-N @
    _WT-BA-TBL @
    _WT-SCRATCH
    WT-BLOCK-FILL              \ ( phase inc n tbl dst -- phase' )
    \ SIMD add: dst[i] = scratch[i] + dst[i]  (result in dst)
    _WT-SCRATCH
    _WT-BA-DST @
    DUP                        \ dst is both src1 and output
    _WT-BA-N @
    SIMD-ADD-N ;               \ phase' remains on stack
