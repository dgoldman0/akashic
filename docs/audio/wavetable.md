# akashic-audio-wavetable — Precomputed Waveform Lookup Tables for KDOS / Megapad-64

Fast oscillator rendering via precomputed 2048-entry wavetables.
A table lookup + linear interpolation (~7 operations) replaces the
~15-operation `TRIG-SIN` polynomial, cutting sine oscillator cost
by roughly 2×.

```forth
REQUIRE audio/wavetable.f
```

`PROVIDED akashic-audio-wavetable` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-trig`,
`akashic-math-simd-ext`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Table Layout](#table-layout)
- [Lookup API](#lookup-api)
- [Global Sine Table](#global-sine-table)
- [Block-Mode Fill](#block-mode-fill)
- [Phase Conversion](#phase-conversion)
- [Block Add (SIMD)](#block-add-simd)
- [Internal Scratch Buffer](#internal-scratch-buffer)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **FP16 phase convention** | Phase is FP16 in `[0.0, 1.0)`, matching `osc.f` and `fm.f`. |
| **2048 entries** | One full sine cycle across 2048 cells (8 bytes each = 16 KB). |
| **Eager initialisation** | `WT-SIN-TABLE` is allocated and filled at module load time (~60 K operations, amortised into the snapshot). |
| **Two lookup modes** | Truncating (`WT-LOOKUP`, ~4 ops) and interpolating (`WT-LERP`, ~10 ops). |
| **Integer phase fast path** | Block-mode words (`WT-BLOCK-FILL`, `WT-BLOCK-ADD`) use fixed-point integer phase to eliminate all FP16 arithmetic in the inner loop. |
| **Prefix convention** | Public: `WT-`.  Internal: `_WT-`. |

---

## Table Layout

Each wavetable is an array of 2048 cells (8 bytes each):

```
table[0]    = sin(2π × 0/2048)      ≈  0.0
table[512]  = sin(2π × 512/2048)    ≈ +1.0
table[1024] = sin(2π × 1024/2048)   ≈  0.0
table[1536] = sin(2π × 1536/2048)   ≈ −1.0
```

Each cell stores an FP16 value in `[−1.0, +1.0]` in the low 16 bits.
The mapping covers one complete cycle.

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `WT-SIZE` | 2048 | Number of table entries |
| `WT-MASK` | 2047 | Index wrap mask (`WT-SIZE − 1`) |

---

## Lookup API

### WT-LOOKUP

```forth
WT-LOOKUP  ( phase table -- sample )
```

**Truncating lookup** — fastest, no interpolation.

1. Multiply `phase × 2048.0`
2. Convert to integer, mask to `[0, 2047]`
3. Fetch cell

Cost: ~4 Forth operations.

### WT-LERP

```forth
WT-LERP  ( phase table -- sample )
```

**Linear-interpolated lookup** — smoother, higher quality.

1. Multiply `phase × 2048.0`
2. Floor to get integer index, save fractional part
3. Fetch two adjacent entries `table[i]` and `table[(i+1) & 2047]`
4. Interpolate: `s0 + frac × (s1 − s0)`

Cost: ~10 Forth operations.

```forth
0x3800 WT-SIN-TABLE WT-LERP     \ lookup sin at phase 0.5
\ → ≈ 0.0 (FP16)
```

---

## Global Sine Table

### WT-SIN-TABLE

```forth
WT-SIN-TABLE  ( -- addr )
```

A `CONSTANT` holding the address of the pre-filled 2048-entry sine
table.  Generated at module load time by calling `WT-FILL-SIN` on a
freshly allocated table.

This table is shared by `osc.f` (for sine oscillators), `fm.f`
(for FM operator waveforms), and any user code needing fast sine
lookup.

### WT-ALLOC

```forth
WT-ALLOC  ( -- addr )
```

Allocate a blank 2048-entry table (16 KB).  Use `WT-FILL-SIN` to
populate it, or fill with custom waveform data.

### WT-FILL-SIN

```forth
WT-FILL-SIN  ( addr -- )
```

Fill a table with `sin(2π × i / 2048)` for `i = 0..2047` using
`TRIG-SIN`.  One-time cost: ~60 K Forth operations.

---

## Block-Mode Fill

Block-mode words bypass FP16 arithmetic entirely in the inner loop
by using a fixed-point integer phase accumulator.

### Integer Phase Format

```
Bits 26–16:  table index (0–2047)
Bits 15–0:   fractional part (unused for truncating lookup)
```

The scale factor is `_WT-SCALE = 2048 × 65536 = 134,217,728`.

The byte-offset extraction uses `phase >> 13` masked with `0x3FF8`,
giving cell-aligned offsets `0, 8, 16, … 16376` directly.

### WT-BLOCK-INC

```forth
WT-BLOCK-INC  ( freq rate -- inc )
```

Compute the integer phase increment for a given frequency and
sample rate:

$$
\text{inc} = \lfloor \text{freq} \rfloor \times 134217728 \div \text{rate}
$$

Returns 0 if `freq < 1 Hz` (integer truncation), signalling that
the caller should fall back to the scalar FP16 path.

### WT-BLOCK-FILL

```forth
WT-BLOCK-FILL  ( phase inc n tbl dst -- phase' )
```

Fill **n** packed FP16 samples at **dst** (2 bytes each) using
truncating table lookup from **tbl**.  The phase advances by **inc**
each sample.

**Inner loop cost:** ~40 cycles/sample (vs ~700 with the
`WT-LERP` per-sample path).

```forth
\ Integer phase for 440 Hz at 8000 Hz sample rate
440 INT>FP16 8000 WT-BLOCK-INC   ( inc )
0                                 ( phase=0 inc )
SWAP 800                          ( 0 inc 800 )
WT-SIN-TABLE my-dst               ( 0 inc 800 tbl dst )
WT-BLOCK-FILL                     ( phase' )
```

---

## Phase Conversion

### WT-PH>INT

```forth
WT-PH>INT  ( fp16-phase -- int-phase )
```

Convert a FP16 phase `[0.0, 1.0)` to the fixed-point integer
format used by `WT-BLOCK-FILL`.

$$
\text{int} = \lfloor \text{phase} \times 2048.0 \rfloor \ll 16
$$

### WT-INT>PH

```forth
WT-INT>PH  ( int-phase -- fp16-phase )
```

Convert an integer phase back to FP16 `[0.0, 1.0)`.  Extracts the
table index, wraps to `[0, 2047]`, then divides by 2048.

These are used by `osc.f` to convert between the oscillator's FP16
phase accumulator and the block-mode integer format.

---

## Block Add (SIMD)

### WT-BLOCK-ADD

```forth
WT-BLOCK-ADD  ( phase inc n tbl dst -- phase' )
```

Add **n** wavetable samples to the existing contents of **dst**
(packed FP16, 2 bytes per sample).

**Strategy:**
1. Fill the internal scratch buffer (`_WT-SCRATCH`) via `WT-BLOCK-FILL`
2. SIMD-add scratch into dst via `SIMD-ADD-N`

This replaces ~130 cycles of scalar `FP16-ADD` per sample with
~2 cycles amortised via the tile engine.

Used by `OSC-ADD` for additive synthesis of sine oscillators.

---

## Internal Scratch Buffer

### _WT-SCRATCH

```forth
_WT-SCRATCH  ( -- addr )
```

A statically allocated 16 KB buffer (8192 samples × 2 bytes) used
as temporary storage by `WT-BLOCK-ADD` and `_FM-RENDER-2OP-BLOCK`.
Not part of the public API — included here for reference.

---

## Quick Reference

```
WT-SIZE          ( -- 2048 )                table entry count
WT-MASK          ( -- 2047 )                index wrap mask
WT-ALLOC         ( -- addr )                allocate blank table
WT-FILL-SIN      ( addr -- )                fill with sine cycle
WT-SIN-TABLE     ( -- addr )                global sine table
WT-LOOKUP        ( phase table -- sample )  truncating lookup
WT-LERP          ( phase table -- sample )  interpolated lookup
WT-BLOCK-INC     ( freq rate -- inc )       integer phase increment
WT-BLOCK-FILL    ( phase inc n tbl dst -- phase' )  fill n samples
WT-BLOCK-ADD     ( phase inc n tbl dst -- phase' )  add n samples
WT-PH>INT        ( fp16-phase -- int-phase )  FP16 → integer phase
WT-INT>PH        ( int-phase -- fp16-phase )  integer → FP16 phase
```

---

## Cookbook

### One-Shot Sine Lookup

```forth
\ Lookup sin(π/4) via table:
\ phase = 0.125 → index ≈ 256 → sin(π/4) ≈ 0.707
0x3000 WT-SIN-TABLE WT-LERP      \ → ≈ 0x399A (0.707)
```

### Fill a Buffer with 440 Hz Sine

```forth
800 44100 16 1 PCM-ALLOC CONSTANT buf

\ Block mode (fastest):
440 INT>FP16 44100 WT-BLOCK-INC CONSTANT inc440
0 inc440 800 WT-SIN-TABLE buf PCM-DATA WT-BLOCK-FILL DROP

\ Equivalent via osc.f (automatic):
440 INT>FP16 OSC-SINE 44100 OSC-CREATE CONSTANT osc
buf osc OSC-FILL    \ uses WT-BLOCK-FILL internally
```

### Additive Synthesis via Block Add

```forth
800 44100 16 1 PCM-ALLOC CONSTANT buf
\ Fill with fundamental, then add harmonics
buf osc-fund OSC-FILL        \ fundamental (uses WT-BLOCK-FILL)
buf osc-2nd  OSC-ADD         \ 2nd harmonic (uses WT-BLOCK-ADD)
buf osc-3rd  OSC-ADD         \ 3rd harmonic (uses WT-BLOCK-ADD)
```

### Custom Wavetable

```forth
WT-ALLOC CONSTANT my-table
\ Fill with custom waveform (e.g. a manually crafted wave):
2048 0 DO
    I my-custom-wave-fn        \ your function → FP16 sample
    my-table I CELLS + !
LOOP
\ Use with WT-LERP or assign to an oscillator:
my-table my-osc OSC-TABLE!
```
