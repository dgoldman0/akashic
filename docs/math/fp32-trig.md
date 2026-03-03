# akashic-fp32-trig — FP32 Trigonometric Functions

Polynomial approximations for sine, cosine, tangent, and their
inverses, all operating on FP32 bit patterns (IEEE 754 binary32).

```forth
REQUIRE fp32-trig.f
```

`PROVIDED akashic-fp32-trig` — REQUIRE `fp32.f`.

---

## Table of Contents

- [Design](#design)
- [Constants](#constants)
- [Trigonometric Functions](#trigonometric-functions)
- [Inverse Trigonometric Functions](#inverse-trigonometric-functions)
- [Degree / Radian Conversion](#degree--radian-conversion)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design

| Principle | Detail |
|---|---|
| **Polynomial core** | Minimax polynomials tuned for 23-bit FP32 mantissa — degree-7 $\sin$, degree-6 $\cos$, degree-7 $\arctan$. |
| **Range reduction** | All angles folded to $[0, 2\pi)$ then into $[0, \pi/4]$ via quadrant logic. |
| **Shared SINCOS** | `F32T-SINCOS` evaluates both $\sin$ and $\cos$ in one pass, then selects / swaps by quadrant. `F32T-SIN` and `F32T-COS` are thin wrappers. |
| **Pure software** | Uses `fp32.f` software arithmetic — no tile-engine or hardware FP required. |
| **Same API shape** | Mirrors `trig.f` (FP16) but with `F32T-` prefix and FP32 bit patterns. |

### Accuracy

| Function | Max error (ULP) | Method |
|---|---|---|
| `F32T-SIN` / `F32T-COS` | ≤ 4 | Degree-7/6 Taylor on $[-\pi/4, \pi/4]$ |
| `F32T-TAN` | ≤ 8 | sin/cos ratio |
| `F32T-ATAN` | ≤ 8 | Degree-7 minimax on $[-1, 1]$ with range reduction |
| `F32T-ASIN` / `F32T-ACOS` | ≤ 12 | Derived via `atan2` |

### When to Use

Use FP32 trig when you need more than FP16's ~3.3 decimal digits of
precision — for example in statistics (computing phase angles),
regression (rotation matrices), or audio DSP (precise frequency
calculations).  For graphics and UI work where FP16 precision suffices,
prefer the faster `TRIG-*` words from `trig.f`.

---

## Constants

| Word | Hex | Value | Description |
|---|---|---|---|
| `F32T-PI` | `0x40490FDB` | $\pi \approx 3.14159265$ | Pi |
| `F32T-2PI` | `0x40C90FDB` | $2\pi \approx 6.28318531$ | Two pi |
| `F32T-PI/2` | `0x3FC90FDB` | $\pi/2 \approx 1.57079633$ | Half pi |
| `F32T-PI/4` | `0x3F490FDB` | $\pi/4 \approx 0.78539816$ | Quarter pi |
| `F32T-INV-PI` | `0x3EA2F983` | $1/\pi \approx 0.31830989$ | Reciprocal of pi |
| `F32T-INV-2PI` | `0x3E22F983` | $1/2\pi \approx 0.15915494$ | Reciprocal of two pi |
| `F32T-DEG2RAD` | `0x3C8EFA35` | $\pi/180 \approx 0.01745329$ | Degrees to radians factor |
| `F32T-RAD2DEG` | `0x42652EE1` | $180/\pi \approx 57.2957795$ | Radians to degrees factor |

---

## Trigonometric Functions

### F32T-SIN

```forth
F32T-SIN  ( angle -- sin )
```

Compute $\sin(\text{angle})$ where *angle* is in radians (FP32).

### F32T-COS

```forth
F32T-COS  ( angle -- cos )
```

Compute $\cos(\text{angle})$.

### F32T-SINCOS

```forth
F32T-SINCOS  ( angle -- sin cos )
```

Compute both $\sin$ and $\cos$ in a single call.  More efficient
than calling `F32T-SIN` followed by `F32T-COS` when both values
are needed (e.g. rotation matrices, Fourier transforms).

### F32T-TAN

```forth
F32T-TAN  ( angle -- tan )
```

Compute $\tan(\text{angle}) = \sin / \cos$.  Returns ±∞ when
$\cos = 0$.

---

## Inverse Trigonometric Functions

### F32T-ATAN

```forth
F32T-ATAN  ( x -- atan )
```

Compute $\arctan(x)$.  Result in $[-\pi/2, \pi/2]$.

Three-range approach for accuracy across the full domain:
1. $|x| > 1$: $\arctan(x) = \pi/2 - \arctan(1/x)$
2. $x > \tan(\pi/8)$: $\arctan(x) = \pi/4 + \arctan((x-1)/(x+1))$
3. $|x| \le \tan(\pi/8)$: direct polynomial

### F32T-ATAN2

```forth
F32T-ATAN2  ( y x -- angle )
```

Two-argument arctangent.  Result in $[-\pi, \pi]$.  Handles all
quadrants and the $x = 0$ case.

### F32T-ASIN

```forth
F32T-ASIN  ( x -- angle )
```

Compute $\arcsin(x) = \text{atan2}(x, \sqrt{1 - x^2})$.
Valid for $x \in [-1, 1]$.

### F32T-ACOS

```forth
F32T-ACOS  ( x -- angle )
```

Compute $\arccos(x) = \pi/2 - \arcsin(x)$.

---

## Degree / Radian Conversion

### F32T-DEG>RAD

```forth
F32T-DEG>RAD  ( deg -- rad )
```

Multiply by $\pi/180$.

### F32T-RAD>DEG

```forth
F32T-RAD>DEG  ( rad -- deg )
```

Multiply by $180/\pi$.

---

## Internals

| Symbol | Purpose |
|---|---|
| `_F3T-REDUCE` | Range reduction: fold angle to $[0, 2\pi)$, determine quadrant, reduce to $[0, \pi/4]$ |
| `_F3T-QUAD` | VARIABLE — current quadrant (0–3) |
| `_F3T-RED` | VARIABLE — reduced angle |
| `_F3T-SWAP` | VARIABLE — 1 if complement applied |
| `_F3T-SIN-POLY` | Evaluate $\sin$ polynomial on reduced angle |
| `_F3T-COS-POLY` | Evaluate $\cos$ polynomial on reduced angle |
| `_F3T-S1/S3/S5/S7` | Taylor coefficients for $\sin$ (degree-7) |
| `_F3T-C0/C2/C4/C6` | Taylor coefficients for $\cos$ (degree-6) |
| `_F3T-A1/A3/A5/A7` | Minimax coefficients for $\arctan$ (degree-7) |
| `_F3T-FLOOR` | FP32 floor (truncate toward $-\infty$) |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `F32T-SIN` | `( angle -- sin )` | Sine |
| `F32T-COS` | `( angle -- cos )` | Cosine |
| `F32T-SINCOS` | `( angle -- sin cos )` | Both sin & cos |
| `F32T-TAN` | `( angle -- tan )` | Tangent |
| `F32T-ATAN` | `( x -- atan )` | Arctangent |
| `F32T-ATAN2` | `( y x -- angle )` | Two-arg arctan |
| `F32T-ASIN` | `( x -- angle )` | Arcsine |
| `F32T-ACOS` | `( x -- angle )` | Arccosine |
| `F32T-DEG>RAD` | `( deg -- rad )` | Degrees → radians |
| `F32T-RAD>DEG` | `( rad -- deg )` | Radians → degrees |
