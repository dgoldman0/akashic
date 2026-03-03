# akashic-syn-modal — Inharmonic Partial (Modal) Synthesis for KDOS / Megapad-64

Generates struck/plucked sounds as a sum of N sinusoidal partials,
each with its own frequency ratio, initial amplitude, and T60 decay.
Higher partials typically decay faster, producing the characteristic
brightness-over-time shape of bells, gongs, metallic objects, stone,
glass, wood — or anything with no physical referent.

```forth
REQUIRE audio/syn/modal.f
```

`PROVIDED akashic-syn-modal` — safe to include multiple times.
Depends on `akashic-fp16`, `akashic-fp16-ext`, `akashic-trig`,
`akashic-audio-osc`, `akashic-audio-noise`, `akashic-audio-env`,
`akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Setters](#setters)
- [Loading Partial Tables](#loading-partial-tables)
- [Built-in Timbre Tables](#built-in-timbre-tables)
- [Querying Duration](#querying-duration)
- [Rendering](#rendering)
- [Envelope Strategy](#envelope-strategy)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Per-partial exponential decay** | Block-rate amplitude decay (32-sample blocks) avoids FP16 precision loss near 1.0.  Block decay factor is computed via 3-term Taylor `exp(-x)`. |
| **Wavetable sine** | Inner loop uses `WT-SIN-TABLE WT-LOOKUP` (~5 ops) instead of polynomial `TRIG-SIN` (~30 ops). |
| **Brightness scaling** | `brightness` parameter biases strike energy toward higher partials: `scale = 1.0 + brightness × (i / max_i)`. |
| **Strike transient** | Optional HP-filtered white noise burst at the attack, with its own fast AR decay.  Controlled by `noise-ms` and `noise-bw`. |
| **Packed ratio tables** | Built-in timbre tables store ratio/amp/decay as packed FP16 triplets in dictionary.  `MODAL-LOAD-TABLE` copies them in one `MOVE`. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant across words. |
| **Prefix convention** | Public: `MODAL-`.  Internal: `_MD-`.  Field: `MD.xxx`. |

---

## Memory Layout

### Descriptor (10 cells = 80 bytes)

```
Offset  Size  Field
──────  ────  ──────────────────────
+0      8     n-partials    Number of partials (integer)
+8      8     fundamental   Base frequency Hz (FP16)
+16     8     brightness    Strike energy bias toward high partials (FP16 0–1)
+24     8     damping       Global T60 multiplier (FP16, default 1.0)
+32     8     noise-ms      Strike transient duration in ms (integer, 0 = off)
+40     8     noise-bw      Transient HP cutoff Hz (FP16)
+48     8     rate          Sample rate Hz (integer)
+56     8     pdata         Pointer to partial array (N × 6 bytes)
+64     8     (reserved)
+72     8     (reserved)
```

### Per-Partial Data (6 bytes per partial)

```
Offset  Size  Field
──────  ────  ──────
+0      2     ratio       Frequency ratio to fundamental (FP16)
+2      2     amp         Initial amplitude 0.0–1.0 (FP16)
+4      2     decay-sec   T60 decay time in seconds (FP16)
```

### Strike State Block (temporary, 4 × N × 2 bytes)

Allocated per strike, freed when strike completes:

```
Subarray       Offset          Content
────────       ──────          ───────
phase[0..N-1]  state + 0       Running phase accumulator (FP16)
ramp[0..N-1]   state + N×2     Running amplitude (FP16)
bdec[0..N-1]   state + N×4     Per-block decay factor (FP16)
pinc[0..N-1]   state + N×6     Phase increment per sample (FP16)
```

---

## Creation & Destruction

### MODAL-CREATE

```forth
MODAL-CREATE  ( n-partials rate -- desc )
```

Allocate a modal descriptor and its partial data array.

- **n-partials** — number of partials (integer, typically 4–8)
- **rate** — sample rate in Hz (integer)

Partial data is zeroed.  Defaults: fundamental = 220 Hz,
brightness = 0, damping = 1.0, noise transient off, noise-bw = 4000 Hz.

```forth
8 44100 MODAL-CREATE CONSTANT bell
```

### MODAL-FREE

```forth
MODAL-FREE  ( desc -- )
```

Free the descriptor and partial data array.

---

## Setters

### MODAL-FUND!

```forth
MODAL-FUND!  ( freq desc -- )
```

Set the fundamental frequency (FP16 Hz).

```forth
440 INT>FP16 bell MODAL-FUND!
```

### MODAL-BRIGHTNESS!

```forth
MODAL-BRIGHTNESS!  ( brightness desc -- )
```

Set brightness (FP16 0.0–1.0).  At 0: all partials at nominal amplitude.
At 1: highest partial receives 2× nominal.

### MODAL-DAMPING!

```forth
MODAL-DAMPING!  ( damping desc -- )
```

Set the global damping multiplier (FP16).  Values > 1.0 extend all
decay times; values < 1.0 shorten them.  Default is 1.0.

### MODAL-NOISE!

```forth
MODAL-NOISE!  ( ms bw desc -- )
```

Configure the strike transient.

- **ms** — noise burst duration in milliseconds (integer, 0 = off)
- **bw** — HP filter cutoff in Hz (FP16)

```forth
15 4000 INT>FP16 bell MODAL-NOISE!
```

### MODAL-PARTIAL!

```forth
MODAL-PARTIAL!  ( ratio amp decay-sec i desc -- )
```

Set one partial by index.

- **ratio** — frequency ratio to fundamental (FP16)
- **amp** — initial amplitude 0.0–1.0 (FP16)
- **decay-sec** — T60 decay time in seconds (FP16)
- **i** — zero-based partial index

```forth
\ Partial 0: fundamental at full amplitude, 2-second decay
FP16-POS-ONE FP16-POS-ONE 0x4000 0 bell MODAL-PARTIAL!
```

---

## Loading Partial Tables

### MODAL-LOAD-TABLE

```forth
MODAL-LOAD-TABLE  ( table n desc -- )
```

Copy N packed FP16 triplets (ratio, amp, decay-sec) from a table
into the descriptor's partial data.  `n` must be ≤ `n-partials`.

```forth
MODAL-TBL-BRONZE-DATA MODAL-TBL-BRONZE-N bell MODAL-LOAD-TABLE
```

---

## Built-in Timbre Tables

Each table is a `CREATE`d array of packed FP16 triplets.

| Table | Constant | N | Character |
|-------|----------|---|-----------|
| Bronze bell | `MODAL-TBL-BRONZE-DATA` / `MODAL-TBL-BRONZE-N` | 8 | Warm bell, typical bronze |
| Steel bell | `MODAL-TBL-STEEL-DATA` / `MODAL-TBL-STEEL-N` | 8 | Hard, bright metallic |
| Glass | `MODAL-TBL-GLASS-DATA` / `MODAL-TBL-GLASS-N` | 6 | Crisp, fast upper decay |
| Singing bowl | `MODAL-TBL-BOWL-DATA` / `MODAL-TBL-BOWL-N` | 6 | Close mode spacing, long sustain |
| Stone slab | `MODAL-TBL-SLAB-DATA` / `MODAL-TBL-SLAB-N` | 6 | Flat wood or stone, short |
| Abstract A | `MODAL-TBL-ABSTRACT-A-DATA` / `MODAL-TBL-ABSTRACT-A-N` | 6 | Near-harmonic alien tone |
| Abstract B | `MODAL-TBL-ABSTRACT-B-DATA` / `MODAL-TBL-ABSTRACT-B-N` | 6 | Spread, bell-like but alien |
| Tubular | `MODAL-TBL-TUBULAR-DATA` / `MODAL-TBL-TUBULAR-N` | 6 | Tubular chime |

---

## Querying Duration

### MODAL-DURATION

```forth
MODAL-DURATION  ( desc -- ms )
```

Estimated audible duration: finds the maximum `decay-sec` among all
partials, multiplies by damping, converts to ms, and caps at 10000.

---

## Rendering

### MODAL-STRIKE

```forth
MODAL-STRIKE  ( velocity desc -- buf )
```

Render a complete strike to a freshly allocated mono 16-bit PCM buffer.

- **velocity** — strike intensity (FP16 0.0–1.0)

Returns a `PCM-ALLOC`'d buffer.  Caller must `PCM-FREE` when done.

The duration is derived from `MODAL-DURATION`, clamped to 50–10000 ms.
Internally allocates a temporary state block (freed before return),
renders all partials via block-rate decay + wavetable sine, then
optionally mixes in the HP-filtered noise transient.

```forth
FP16-POS-ONE bell MODAL-STRIKE  ( -- buf )
\ ... process / play buf ...
PCM-FREE
```

### MODAL-STRIKE-INTO

```forth
MODAL-STRIKE-INTO  ( buf velocity desc -- )
```

Render a strike and *add* it into an existing PCM buffer, sample by
sample.  The temporary strike buffer is allocated internally and freed
after mixing.  Use for layering multiple strikes into one output.

```forth
\ Pre-allocated output buffer
2048 44100 16 1 PCM-ALLOC CONSTANT mix
mix FP16-POS-ONE bell MODAL-STRIKE-INTO   \ add first strike
mix FP16-POS-HALF bell MODAL-STRIKE-INTO   \ add softer second
```

---

## Envelope Strategy

Per-sample exponential decay requires a multiplier astronomically
close to 1.0 (e.g. 0.9999739 for a 2-second T60 at 44100 Hz).
FP16 precision near 1.0 is ~0.001 — the value would round to either
1.0 (no decay) or the next representable step (too fast).

**Solution:** Block-rate amplitude update, 32 samples per block.
The 32-sample block decay factor for a 2-second T60 is ~0.9975,
which FP16 represents cleanly.  0.73 ms per block is finer than
the DX7's control rate (~2.67 ms) and inaudibly smooth.

Block decay factor computation:

$$x = \frac{32 \cdot \ln(1000)}{\text{decay\_sec} \times \text{damping} \times \text{rate}}$$

$$\text{factor} = e^{-x} \approx 1 - x + \frac{x^2}{2} - \frac{x^3}{6}$$

Accurate to < 0.1% for `decay_sec ≥ 0.05 s`.

---

## Quick Reference

```
MODAL-CREATE       ( n-partials rate -- desc )
MODAL-FREE         ( desc -- )
MODAL-FUND!        ( freq desc -- )             FP16 Hz
MODAL-PARTIAL!     ( ratio amp decay i desc -- ) set one partial
MODAL-LOAD-TABLE   ( table n desc -- )          packed FP16 triplets
MODAL-BRIGHTNESS!  ( brightness desc -- )       FP16 0.0–1.0
MODAL-DAMPING!     ( damping desc -- )          FP16
MODAL-NOISE!       ( ms bw desc -- )            int ms, FP16 Hz
MODAL-DURATION     ( desc -- ms )               estimated audible ms
MODAL-STRIKE       ( velocity desc -- buf )     render → new PCM buf
MODAL-STRIKE-INTO  ( buf velocity desc -- )     render → add into buf
```

---

## Cookbook

### Simple Bronze Bell

```forth
8 44100 MODAL-CREATE CONSTANT bell
440 INT>FP16 bell MODAL-FUND!
MODAL-TBL-BRONZE-DATA MODAL-TBL-BRONZE-N bell MODAL-LOAD-TABLE
FP16-POS-ONE bell MODAL-STRIKE CONSTANT ring
\ ring holds the complete strike — play or process
ring PCM-FREE
bell MODAL-FREE
```

### Glass Tap with Noise Transient

```forth
6 44100 MODAL-CREATE CONSTANT glass
880 INT>FP16 glass MODAL-FUND!
MODAL-TBL-GLASS-DATA MODAL-TBL-GLASS-N glass MODAL-LOAD-TABLE
10 6000 INT>FP16 glass MODAL-NOISE!     \ 10 ms burst, 6 kHz HP
FP16-POS-ONE glass MODAL-STRIKE CONSTANT tap
tap PCM-FREE  glass MODAL-FREE
```

### Layering Strikes at Different Velocities

```forth
8 44100 MODAL-CREATE CONSTANT bell
440 INT>FP16 bell MODAL-FUND!
MODAL-TBL-BRONZE-DATA MODAL-TBL-BRONZE-N bell MODAL-LOAD-TABLE
4096 44100 16 1 PCM-ALLOC CONSTANT mix
mix FP16-POS-ONE  bell MODAL-STRIKE-INTO   \ hard strike
mix FP16-POS-HALF bell MODAL-STRIKE-INTO   \ soft overlay
mix PCM-FREE  bell MODAL-FREE
```

### Bright vs Dark: Brightness Parameter

```forth
8 44100 MODAL-CREATE CONSTANT inst
440 INT>FP16 inst MODAL-FUND!
MODAL-TBL-STEEL-DATA MODAL-TBL-STEEL-N inst MODAL-LOAD-TABLE
\ Dark strike (brightness = 0)
FP16-POS-ZERO inst MODAL-BRIGHTNESS!
FP16-POS-ONE inst MODAL-STRIKE CONSTANT dark
\ Bright strike (brightness = 1)
FP16-POS-ONE inst MODAL-BRIGHTNESS!
FP16-POS-ONE inst MODAL-STRIKE CONSTANT bright
dark PCM-FREE  bright PCM-FREE  inst MODAL-FREE
```
