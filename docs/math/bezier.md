# akashic-bezier — Bézier Curve Primitives for KDOS / Megapad-64

Quadratic and cubic Bézier evaluation, flatness testing, and adaptive
flattening using FP16 coordinates.  Includes general-purpose 2D
interpolation helpers `LERP2D` and `MID2D`.

```forth
REQUIRE bezier.f
```

`PROVIDED akashic-bezier` — safe to include multiple times.
Auto-loads `fp16-ext.f` (and transitively `fp16.f`) via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [2D Interpolation](#2d-interpolation)
- [Bézier Evaluation](#bézier-evaluation)
- [Flatness Testing](#flatness-testing)
- [Adaptive Flattening](#adaptive-flattening)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **FP16 coordinates** | All (x, y) pairs are FP16 bit patterns, two values on the Forth stack. |
| **De Casteljau algorithm** | Evaluation uses the numerically stable recursive LERP approach. |
| **Explicit work stack** | Subdivision uses a memory-based stack (`_BZ-WSTACK`, 256 cells) to avoid Forth return-stack overflow during deep adaptive subdivision. |
| **Callback-based flattening** | `BZ-*-FLATTEN` calls a user-supplied execution token for each line segment, enabling zero-allocation rendering pipelines. |
| **Not re-entrant** | Shared VARIABLEs for point storage. The callback must NOT call `BZ-*-FLATTEN` recursively. |

---

## 2D Interpolation

### LERP2D

```forth
LERP2D  ( x0 y0 x1 y1 t -- rx ry )
```

2D linear interpolation between points $(x_0, y_0)$ and $(x_1, y_1)$
at parameter $t$ (FP16, typically in $[0, 1]$).

$$r_x = \text{LERP}(x_0, x_1, t), \quad r_y = \text{LERP}(y_0, y_1, t)$$

Uses `FP16-LERP` for each component.

### MID2D

```forth
MID2D  ( x0 y0 x1 y1 -- mx my )
```

Midpoint — equivalent to `LERP2D` at $t = 0.5$. Used extensively
in Bézier subdivision.

---

## Bézier Evaluation

### BZ-QUAD-EVAL

```forth
BZ-QUAD-EVAL  ( x0 y0 x1 y1 x2 y2 t -- rx ry )
```

Evaluate a quadratic Bézier curve at parameter $t$ using De Casteljau:

1. $Q_0 = \text{LERP2D}(P_0, P_1, t)$
2. $Q_1 = \text{LERP2D}(P_1, P_2, t)$
3. Result $= \text{LERP2D}(Q_0, Q_1, t)$

### BZ-CUBIC-EVAL

```forth
BZ-CUBIC-EVAL  ( x0 y0 x1 y1 x2 y2 x3 y3 t -- rx ry )
```

Evaluate a cubic Bézier curve at parameter $t$ using De Casteljau:

1. $Q_0 = \text{LERP2D}(P_0, P_1, t)$, $Q_1 = \text{LERP2D}(P_1, P_2, t)$, $Q_2 = \text{LERP2D}(P_2, P_3, t)$
2. $R_0 = \text{LERP2D}(Q_0, Q_1, t)$, $R_1 = \text{LERP2D}(Q_1, Q_2, t)$
3. Result $= \text{LERP2D}(R_0, R_1, t)$

---

## Flatness Testing

### BZ-QUAD-FLAT?

```forth
BZ-QUAD-FLAT?  ( x0 y0 x1 y1 x2 y2 tol -- flag )
```

Test whether a quadratic Bézier is "flat enough" to approximate as
a straight line.  Computes the $L_\infty$ distance between the
control point $P_1$ and the chord midpoint.  Returns true (−1) if
the deviation is ≤ `tol`.

### BZ-CUBIC-FLAT?

```forth
BZ-CUBIC-FLAT?  ( x0 y0 x1 y1 x2 y2 x3 y3 tol -- flag )
```

Test whether a cubic Bézier is flat.  Checks that both $P_1$ and
$P_2$ are within `tol` of the corresponding chord points at
$t = 1/3$ and $t = 2/3$.

---

## Adaptive Flattening

### BZ-QUAD-FLATTEN

```forth
BZ-QUAD-FLATTEN  ( x0 y0 x1 y1 x2 y2 tol xt -- )
```

Adaptively flatten a quadratic Bézier into line segments.
Subdivides at $t = 0.5$ until each sub-curve passes `BZ-QUAD-FLAT?`,
then calls the callback `xt` for each segment.

**Callback:** `( x0 y0 x1 y1 -- )` — receives line segment endpoints.

### BZ-CUBIC-FLATTEN

```forth
BZ-CUBIC-FLATTEN  ( x0 y0 x1 y1 x2 y2 x3 y3 tol xt -- )
```

Adaptively flatten a cubic Bézier.  Same algorithm and callback
signature as the quadratic variant.

**Important:** The callback must NOT call `BZ-*-FLATTEN` recursively —
the shared work stack would be corrupted.

---

## Internals

### Point Storage

| Variable Pair | Slot |
|---|---|
| `_BZ-AX`, `_BZ-AY` | P0 |
| `_BZ-BX`, `_BZ-BY` | P1 |
| `_BZ-CX`, `_BZ-CY` | P2 |
| `_BZ-DX`, `_BZ-DY` | P3 (cubic only) |

Helper words `_BZ!0`..`_BZ!3` store points, `_BZ@0`..`_BZ@3` fetch them.

### Work Stack

| Word | Stack | Description |
|---|---|---|
| `_BZ-WS-RESET` | `( -- )` | Reset work stack pointer to base |
| `_BZ-WS-PUSH` | `( val -- )` | Push one cell onto work stack |
| `_BZ-WS-POP` | `( -- val )` | Pop one cell from work stack |
| `_BZ-WS-EMPTY?` | `( -- flag )` | True if work stack is empty |

Work stack size: 256 cells (supports ~16 levels of subdivision for
cubic curves: 16 × 8 values per cubic = 128 cells).

### Constants

| Word | Value | Description |
|---|---|---|
| `_BZ-HALF` | `0x3800` | FP16 0.5 — subdivision midpoint |
| `_BZ-THIRD` | `0x3555` | FP16 ≈1/3 — cubic flatness test |
| `_BZ-TWO-THIRDS` | `0x3955` | FP16 ≈2/3 — cubic flatness test |

---

## Quick Reference

```
LERP2D           ( x0 y0 x1 y1 t -- rx ry )
MID2D            ( x0 y0 x1 y1 -- mx my )
BZ-QUAD-EVAL     ( x0 y0 x1 y1 x2 y2 t -- rx ry )
BZ-CUBIC-EVAL    ( x0 y0 x1 y1 x2 y2 x3 y3 t -- rx ry )
BZ-QUAD-FLAT?    ( x0 y0 x1 y1 x2 y2 tol -- flag )
BZ-CUBIC-FLAT?   ( x0 y0 x1 y1 x2 y2 x3 y3 tol -- flag )
BZ-QUAD-FLATTEN  ( x0 y0 x1 y1 x2 y2 tol xt -- )
BZ-CUBIC-FLATTEN ( x0 y0 x1 y1 x2 y2 x3 y3 tol xt -- )
```
