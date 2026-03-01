# akashic-audio-fm — FM Synthesis for KDOS / Megapad-64

Two-operator and four-operator FM (phase modulation) synthesis with
multiple routing algorithms, per-operator ADSR envelopes, and
operator feedback.

```forth
REQUIRE audio/fm.f
```

`PROVIDED akashic-audio-fm` — safe to include multiple times.
Depends on `akashic-fp16-ext`, `akashic-math-trig`, `akashic-audio-pcm`,
`akashic-audio-env`.

---

## Table of Contents

- [Operator Layout](#operator-layout)
- [Voice Layout](#voice-layout)
- [Algorithms](#algorithms)
- [Feedback](#feedback)
- [API](#api)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Operator Layout

Per-operator descriptor (48 bytes):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | ratio | FP16 | Frequency ratio relative to fundamental |
| +8 | index | FP16 | Modulation index (depth of modulation) |
| +16 | level | FP16 | Output level (0.0–1.0) |
| +24 | env | ptr | Per-operator ADSR envelope |
| +32 | phase | FP16 | Current phase accumulator |
| +40 | freq | FP16 | Absolute frequency (set via NOTE-ON) |

---

## Voice Layout

FM voice descriptor (56 bytes):

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| +0 | n-ops | int | Number of operators (2 or 4) |
| +8 | algo | int | Routing algorithm index |
| +16 | feedback | FP16 | Op1 self-feedback amount |
| +24 | ops | ptr | Pointer to operator array |
| +32 | work-buf | ptr | Output PCM buffer (mono) |
| +40 | rate | int | Sample rate (Hz) |
| +48 | fb-prev | FP16 | Previous feedback sample for op1 |

---

## Algorithms

### 2-Operator Modes

| Constant | Value | Topology |
|----------|-------|----------|
| `FM-ALGO-SERIAL` | 0 | `Op1 → Op2 → out` (classic FM) |
| `FM-ALGO-PARALLEL` | 1 | `Op1 + Op2 → out` (additive) |

### 4-Operator Modes

| Constant | Value | Topology |
|----------|-------|----------|
| `FM-ALGO-SERIAL` | 0 | `Op1 → Op2 → Op3 → Op4 → out` (full chain) |
| `FM-ALGO-PARALLEL` | 1 | `Op1 + Op2 + Op3 + Op4 → out` (all additive) |
| `FM-ALGO-3CHAIN` | 2 | `Op1 → Op2 → Op3 → out`, `Op4 → out` |
| `FM-ALGO-PARMOD` | 3 | `(Op1 + Op2) → Op3 → Op4 → out` |

### Signal Flow

For serial (2-op):

$$
\text{out} = \sin\!\bigl(2\pi \cdot f_2 \cdot t + I_2 \cdot \sin(2\pi \cdot f_1 \cdot t)\bigr) \times L_2 \times E_2
$$

Where $f_n = \text{freq} \times \text{ratio}_n$, $I_n$ is the modulation
index, $L_n$ is the output level, and $E_n$ is the envelope value.

---

## Feedback

Operator 1 can feed its own previous output back as phase modulation:

$$
\phi_1' = \phi_1 + \text{fb\_amount} \times \text{prev\_output}
$$

This creates richer, more complex timbres.  Use sparingly — high
feedback values can produce harsh or noise-like output.

---

## API

### FM-CREATE

```forth
FM-CREATE  ( n-ops algorithm rate frames -- voice )
```

Allocate an FM voice with **n-ops** operators (2 or 4), using the
given **algorithm**, at sample **rate**, rendering **frames** per block.

- Each operator defaults to: ratio=1.0, index=1.0, level=1.0
- Default ADSR per op: A=5ms, D=50ms, S=0.8, R=100ms
- Feedback defaults to 0.0.

### FM-FREE

```forth
FM-FREE  ( voice -- )
```

Free all operator envelopes, the operator array, work buffer, and
voice descriptor.

### FM-NOTE-ON

```forth
FM-NOTE-ON  ( freq vel voice -- )
```

Trigger a note.  Sets each operator's frequency to `freq × ratio`,
resets phases to zero, and gates all envelopes with velocity **vel**.

### FM-NOTE-OFF

```forth
FM-NOTE-OFF  ( voice -- )
```

Release all operator envelopes (enter release phase).

### FM-RENDER

```forth
FM-RENDER  ( voice -- buf )
```

Render one block of FM audio.  Routes operators according to the
current algorithm, applying per-operator envelopes and modulation.
Returns the output PCM buffer pointer.

### FM-RATIO!

```forth
FM-RATIO!  ( ratio op# voice -- )
```

Set the frequency ratio for operator **op#** (0-based).  Integer
ratios (1, 2, 3…) produce harmonic partials; non-integer ratios
produce inharmonic timbres.

### FM-INDEX!

```forth
FM-INDEX!  ( index op# voice -- )
```

Set the modulation index for operator **op#**.  Higher index = more
sidebands = brighter/harsher sound.

### FM-LEVEL!

```forth
FM-LEVEL!  ( level op# voice -- )
```

Set the output level for operator **op#** (FP16, 0.0–1.0).
Setting a carrier's level to 0 silences it.

### FM-ALGO!

```forth
FM-ALGO!  ( algo voice -- )
```

Switch the routing algorithm.  Takes effect on the next `FM-RENDER`.

### FM-FEEDBACK!

```forth
FM-FEEDBACK!  ( amount voice -- )
```

Set operator 1's self-feedback amount (FP16).  0 = no feedback.

### FM-ENV!

```forth
FM-ENV!  ( a d s r op# voice -- )
```

Set the ADSR envelope for operator **op#**.  Parameters are in
milliseconds (integer) for A, D, R and FP16 for S.

---

## Quick Reference

```
FM-CREATE       ( n-ops algo rate frames -- voice )
FM-FREE         ( voice -- )
FM-NOTE-ON      ( freq vel voice -- )
FM-NOTE-OFF     ( voice -- )
FM-RENDER       ( voice -- buf )
FM-RATIO!       ( ratio op# voice -- )
FM-INDEX!       ( index op# voice -- )
FM-LEVEL!       ( level op# voice -- )
FM-ALGO!        ( algo voice -- )
FM-FEEDBACK!    ( amount voice -- )
FM-ENV!         ( a d s r op# voice -- )
FM-ALGO-SERIAL    ( -- 0 )
FM-ALGO-PARALLEL  ( -- 1 )
FM-ALGO-3CHAIN    ( -- 2 )
FM-ALGO-PARMOD    ( -- 3 )
```

---

## Cookbook

### Classic 2-Op FM Bell

```forth
2 FM-ALGO-SERIAL 44100 256 FM-CREATE  CONSTANT mybell
\ Modulator (op0) at 7× ratio for metallic partials
0x4700 0 mybell FM-RATIO!           \ ratio = 7.0
0x4200 0 mybell FM-INDEX!           \ index = 3.0 (bright)
\ Short percussive envelope on modulator
5 80 0x0000 50  0 mybell FM-ENV!    \ A=5 D=80 S=0 R=50
\ Carrier (op1) at 1× ratio
0x3C00 1 mybell FM-RATIO!           \ ratio = 1.0
\ Trigger and render
440 INT>FP16 0x3C00 mybell FM-NOTE-ON
mybell FM-RENDER  ( → buf )
mybell FM-FREE
```

### 4-Op Electric Piano

```forth
4 FM-ALGO-3CHAIN 44100 256 FM-CREATE  CONSTANT myep
\ Op1 → Op2 → Op3 → out  +  Op4 → out
0x4400 0 myep FM-RATIO!   \ op0: ratio=4 (high modulator)
0x4000 1 myep FM-RATIO!   \ op1: ratio=2
0x3C00 2 myep FM-RATIO!   \ op2: ratio=1 (carrier)
0x4000 3 myep FM-RATIO!   \ op3: ratio=2 (parallel carrier)
0x3800 3 myep FM-LEVEL!   \ op3 quieter
330 INT>FP16 0x3C00 myep FM-NOTE-ON
myep FM-RENDER  ( → buf )
myep FM-FREE
```

### Feedback for Richer Tone

```forth
2 FM-ALGO-SERIAL 44100 256 FM-CREATE  CONSTANT myfm
0x3400 myfm FM-FEEDBACK!            \ mild op1 self-feedback
440 INT>FP16 0x3C00 myfm FM-NOTE-ON
myfm FM-RENDER  ( → buf )
myfm FM-FREE
```

### Changing Algorithm at Runtime

```forth
2 FM-ALGO-SERIAL 44100 256 FM-CREATE  CONSTANT myfm
440 INT>FP16 0x3C00 myfm FM-NOTE-ON
myfm FM-RENDER DROP                  \ serial FM sound
FM-ALGO-PARALLEL myfm FM-ALGO!      \ switch to additive
myfm FM-RENDER  ( → buf )           \ now both ops add
myfm FM-FREE
```
