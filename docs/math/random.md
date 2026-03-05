# akashic-random — True Random / CSPRNG

Hardware-backed cryptographic random number generator.  Delegates all
entropy generation to the BIOS TRNG coprocessor at MMIO
`0xFFFF_FF00_0000_0800`, which sources entropy from the OS
(`std::random_device` / `/dev/urandom`).

```forth
REQUIRE random.f
```

`PROVIDED akashic-random` — depends on `fp16.f` (for `RNG-FP16`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Core Primitives](#core-primitives)
- [Buffer Fill](#buffer-fill)
- [Bounded Range](#bounded-range)
- [Boolean](#boolean)
- [FP16 Random](#fp16-random)
- [Entropy Seeding](#entropy-seeding)
- [Display](#display)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Hardware CSPRNG** | All entropy comes from a C++ TRNG device backed by OS randomness — suitable for cryptographic key generation. |
| **Rejection sampling** | `RNG-RANGE` uses bitmask-and-reject to eliminate modulo bias. |
| **FP16 support** | `RNG-FP16` produces uniformly distributed half-precision floats in [0.0, 1.0) via bit construction and `FP16-SUB`. |
| **Thin wrappers** | Core words (`RNG-U64`, `RNG-BYTE`) delegate directly to BIOS primitives with zero overhead. |
| **Not re-entrant** | Single hardware device, one caller at a time. |

---

## Constants

### RNG-AVAILABLE

```forth
RNG-AVAILABLE  ( -- flag )
```

Always `TRUE` (-1) — hardware TRNG is present.

---

## Core Primitives

### RNG-U64

```forth
RNG-U64  ( -- u64 )
```

64 random bits from hardware TRNG.

### RNG-U32

```forth
RNG-U32  ( -- u32 )
```

32 random bits (low 32 bits of a 64-bit hardware read).

### RNG-BYTE

```forth
RNG-BYTE  ( -- b )
```

Single random byte (0–255).

---

## Buffer Fill

### RNG-BYTES

```forth
RNG-BYTES  ( dst n -- )
```

Fill *n* bytes at *dst* with hardware random data.  Suitable for
generating cryptographic keys, nonces, and IVs.

```forth
CREATE key 32 ALLOT
key 32 RNG-BYTES
\ key now contains 32 random bytes
```

---

## Bounded Range

### RNG-RANGE

```forth
RNG-RANGE  ( lo hi -- n )
```

Uniform random integer in [*lo*, *hi*).  Uses rejection sampling
with a power-of-two bitmask to avoid modulo bias.  *hi* must be
greater than *lo*.

```forth
0 100 RNG-RANGE   \ random integer 0–99
1 7 RNG-RANGE     \ random die roll 1–6
```

---

## Boolean

### RNG-BOOL

```forth
RNG-BOOL  ( -- flag )
```

Random `TRUE` (-1) or `FALSE` (0), each with 50% probability.

---

## FP16 Random

### RNG-FP16

```forth
RNG-FP16  ( -- fp16 )
```

Random IEEE 754 half-precision float uniformly distributed in
[0.0, 1.0).  Constructed by building a value in [1.0, 2.0)
with 10 random mantissa bits and subtracting 1.0 via `FP16-SUB`.

Resolution: 1/1024 ≈ 0.000977.

Requires `fp16.f` to be loaded (provides `FP16-SUB` and
`FP16-POS-ONE`).

---

## Entropy Seeding

### RNG-SEED

```forth
RNG-SEED  ( u -- )
```

XOR-mix a 64-bit user-supplied value into the hardware entropy
pool.  Useful for adding application-specific entropy (timestamps,
user input hashes, etc.) on top of the OS entropy source.

---

## Display

### RNG-BYTES-.

```forth
RNG-BYTES-.  ( addr n -- )
```

Print *n* bytes at *addr* as lowercase hex characters.

```forth
CREATE buf 8 ALLOT
buf 8 RNG-BYTES
buf 8 RNG-BYTES-.   \ prints e.g. "3a7f02b8e1c95d44"
```

---

## Hardware Detail

The BIOS TRNG coprocessor lives at MMIO base
`0xFFFF_FF00_0000_0800`:

| Offset | Register | R/W | Description |
|--------|----------|-----|-------------|
| `+0x00` | RAND8 | R | One random byte |
| `+0x08` | RAND64 | R | 8 random bytes (read byte-at-a-time) |
| `+0x10` | STATUS | R | Always 1 (entropy available) |
| `+0x18` | SEED | W | XOR-mix 8 bytes into pool |

Entropy source: C++ `std::random_device` → 64-byte pool, refilled
from OS entropy when exhausted.

BIOS words used: `RANDOM`, `RANDOM8`, `SEED-RNG`.
KDOS words used: `RANDOM32`.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `RNG-AVAILABLE` | `( -- flag )` | TRUE (hardware present) |
| `RNG-U64` | `( -- u64 )` | 64-bit hardware random |
| `RNG-U32` | `( -- u32 )` | 32-bit hardware random |
| `RNG-BYTE` | `( -- b )` | Single random byte |
| `RNG-BYTES` | `( dst n -- )` | Fill buffer with random bytes |
| `RNG-RANGE` | `( lo hi -- n )` | Uniform in [lo, hi) |
| `RNG-BOOL` | `( -- flag )` | Random TRUE or FALSE |
| `RNG-FP16` | `( -- fp16 )` | Random FP16 in [0.0, 1.0) |
| `RNG-SEED` | `( u -- )` | Mix entropy into pool |
| `RNG-BYTES-.` | `( addr n -- )` | Print bytes as hex |
