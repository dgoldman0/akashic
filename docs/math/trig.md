# akashic-trig — FP16 Trigonometric Functions

Polynomial approximations for sine, cosine, tangent, and their
inverses, all operating on FP16 bit patterns.

```forth
REQUIRE trig.f
```

`PROVIDED akashic-trig` — REQUIRE `fp16-ext.f`.

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
| **Polynomial core** | Taylor / minimax polynomials tuned for 10-bit FP16 mantissa. |
| **Range reduction** | All angles folded to $[0, 2\pi)$ then into $[0, \pi/4]$ via quadrant logic. |
| **Shared SINCOS** | `TRIG-SINCOS` evaluates both $\sin$ and $\cos$ in one pass, then selects / swaps by quadrant. `TRIG-SIN` and `TRIG-COS` are thin wrappers. |
| **No lookup tables** | Pure computation — no HBW memory footprint beyond the three `fp16.f` scratch tiles. |

### Accuracy

| Function | Max error (ULP) | Method |
|---|---|---|
| `TRIG-SIN` / `TRIG-COS` | ≤ 1 | Degree-5 Taylor on $[-\pi/4, \pi/4]$ |
| `TRIG-TAN` | ≤ 2 | sin/cos ratio |
| `TRIG-ATAN` | ≤ 2 | Degree-5 minimax on $[-1, 1]$ |
| `TRIG-ASIN` / `TRIG-ACOS` | ≤ 3 | Derived via `atan2` |

---

## Constants

| Word | Value | Description |
|---|---|---|
| `TRIG-PI` | `0x4248` | $\pi \approx 3.1406$ |
| `TRIG-2PI` | `0x4648` | $2\pi \approx 6.2812$ |
| `TRIG-PI/2` | `0x3E48` | $\pi/2 \approx 1.5703$ |
| `TRIG-PI/4` | `0x3A48` | $\pi/4 \approx 0.7852$ |
| `TRIG-INV-PI` | `0x3518` | $1/\pi \approx 0.3183$ |
| `TRIG-INV-2PI` | `0x3118` | $1/2\pi \approx 0.1592$ |
| `TRIG-DEG2RAD` | `0x2478` | $\pi/180 \approx 0.01745$ |
| `TRIG-RAD2DEG` | `0x5329` | $180/\pi \approx 57.28$ |

---

## Trigonometric Functions

### TRIG-SIN

```forth
TRIG-SIN  ( angle -- sin )
```

Compute $\sin(\text{angle})$ where *angle* is in radians (FP16).

### TRIG-COS

```forth
TRIG-COS  ( angle -- cos )
```

Compute $\cos(\text{angle})$.

### TRIG-SINCOS

```forth
TRIG-SINCOS  ( angle -- sin cos )
```

Compute both $\sin$ and $\cos$ in a single call.  More efficient
than calling `TRIG-SIN` followed by `TRIG-COS` when both values
are needed (e.g. rotation matrices).

### TRIG-TAN

```forth
TRIG-TAN  ( angle -- tan )
```

Compute $\tan(\text{angle}) = \sin / \cos$.  Returns ±∞ when
$\cos = 0$.

---

## Inverse Trigonometric Functions

### TRIG-ATAN

```forth
TRIG-ATAN  ( x -- atan )
```

Compute $\arctan(x)$.  Result in $[-\pi/2, \pi/2]$.

For $|x| > 1$, uses the identity $\arctan(x) = \pi/2 - \arctan(1/x)$.

### TRIG-ATAN2

```forth
TRIG-ATAN2  ( y x -- angle )
```

Two-argument arctangent.  Result in $[-\pi, \pi]$.  Handles all
quadrants and the $x = 0$ case.

### TRIG-ASIN

```forth
TRIG-ASIN  ( x -- angle )
```

Compute $\arcsin(x) = \text{atan2}(x, \sqrt{1 - x^2})$.
Valid for $x \in [-1, 1]$.

### TRIG-ACOS

```forth
TRIG-ACOS  ( x -- angle )
```

Compute $\arccos(x) = \pi/2 - \arcsin(x)$.

---

## Degree / Radian Conversion

### TRIG-DEG>RAD

```forth
TRIG-DEG>RAD  ( deg -- rad )
```

Multiply by $\pi/180$.

### TRIG-RAD>DEG

```forth
TRIG-RAD>DEG  ( rad -- deg )
```

Multiply by $180/\pi$.

---

## Internals

| Symbol | Purpose |
|---|---|
| `_TR-REDUCE` | Range reduction: fold angle to $[0, 2\pi)$, determine quadrant, reduce to $[0, \pi/4]$ |
| `_TR-QUAD` | VARIABLE — current quadrant (0–3) |
| `_TR-RED` | VARIABLE — reduced angle |
| `_TR-SIN-POLY` | Evaluate $\sin$ polynomial on reduced angle |
| `_TR-COS-POLY` | Evaluate $\cos$ polynomial on reduced angle |
| `_TR-SIN-C1/C3/C5` | Taylor coefficients for $\sin$ |
| `_TR-COS-D0/D2/D4` | Taylor coefficients for $\cos$ |
| `_TR-AT-A1/A3/A5` | Minimax coefficients for $\arctan$ |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `TRIG-SIN` | `( angle -- sin )` | Sine |
| `TRIG-COS` | `( angle -- cos )` | Cosine |
| `TRIG-SINCOS` | `( angle -- sin cos )` | Both sin & cos |
| `TRIG-TAN` | `( angle -- tan )` | Tangent |
| `TRIG-ATAN` | `( x -- atan )` | Arctangent |
| `TRIG-ATAN2` | `( y x -- angle )` | Two-arg arctan |
| `TRIG-ASIN` | `( x -- angle )` | Arcsine |
| `TRIG-ACOS` | `( x -- angle )` | Arccosine |
| `TRIG-DEG>RAD` | `( deg -- rad )` | Degrees → radians |
| `TRIG-RAD>DEG` | `( rad -- deg )` | Radians → degrees |
