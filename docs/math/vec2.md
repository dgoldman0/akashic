# akashic-vec2 — 2D Vector Math for KDOS / Megapad-64

2D vector operations using FP16 arithmetic via the tile engine.
Vectors are represented as two FP16 values on the Forth data stack:
`( x y )`.

```forth
REQUIRE vec2.f
```

`PROVIDED akashic-vec2` — safe to include multiple times.
Auto-loads `fp16-ext.f` and `trig.f` (and transitively `fp16.f`)
via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Basic Arithmetic](#basic-arithmetic)
- [Products](#products)
- [Length & Distance](#length--distance)
- [Interpolation](#interpolation)
- [Geometric Operations](#geometric-operations)
- [Component-wise Min / Max](#component-wise-min--max)
- [Equality](#equality)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Stack-based vectors** | Vectors live as two FP16 values on the stack `( x y )`, not in memory. |
| **FP16 throughout** | All components are raw 16-bit IEEE 754 half-precision bit patterns. |
| **PREFIX convention** | All public words use the `V2-` prefix. Internal helpers use `_V2-`. |
| **VARIABLEs for scratch** | Four shared scratch variables `_V2-A` through `_V2-D` hold intermediates. No locals, no return-stack tricks beyond simple `>R` / `R>`. |
| **Not re-entrant** | Shared VARIABLEs mean concurrent callers would collide. |

---

## Constants

| Word | Stack | Description |
|---|---|---|
| `V2-ZERO` | `( -- x y )` | Push $(0, 0)$ — both components `FP16-POS-ZERO`. |
| `V2-ONE` | `( -- x y )` | Push $(1, 1)$ — both components `FP16-POS-ONE`. |

---

## Basic Arithmetic

All binary arithmetic words have the stack effect
`( ax ay bx by -- rx ry )` unless noted.

| Word | Stack | Operation |
|---|---|---|
| `V2-ADD` | `( ax ay bx by -- rx ry )` | $(a_x + b_x,\ a_y + b_y)$ |
| `V2-SUB` | `( ax ay bx by -- rx ry )` | $(a_x - b_x,\ a_y - b_y)$ |
| `V2-SCALE` | `( x y s -- rx ry )` | $(x \cdot s,\ y \cdot s)$ |
| `V2-NEG` | `( x y -- -x -y )` | Negate both components (bit-flip sign). |

```forth
0x3C00 0x4000 0x4200 0x4400 V2-ADD  \ (1,2) + (3,4) → (4,6)
```

---

## Products

| Word | Stack | Operation |
|---|---|---|
| `V2-DOT` | `( ax ay bx by -- dot )` | $a_x b_x + a_y b_y$ — scalar dot product. |
| `V2-CROSS` | `( ax ay bx by -- cross )` | $a_x b_y - a_y b_x$ — 2D cross product (z-component of the 3D cross product). |

```forth
0x3C00 0x0000  0x0000 0x3C00  V2-DOT .  \ (1,0)·(0,1) → 0
```

---

## Length & Distance

| Word | Stack | Description |
|---|---|---|
| `V2-LENSQ` | `( x y -- len² )` | Squared length $x^2 + y^2$. Avoids the cost of `FP16-SQRT`. |
| `V2-LEN` | `( x y -- len )` | Length $\sqrt{x^2 + y^2}$. |
| `V2-NORM` | `( x y -- nx ny )` | Normalize to unit length. Zero vector returns $(0, 0)$. |
| `V2-DIST` | `( ax ay bx by -- d )` | Euclidean distance $\|a - b\|$. |

```forth
0x4200 0x4400 V2-LEN .  \ |(3,4)| → 5.0 (0x4500)
```

---

## Interpolation

### V2-LERP

```forth
V2-LERP  ( ax ay bx by t -- rx ry )
```

Per-component linear interpolation:

$$r_x = a_x + t \cdot (b_x - a_x), \quad r_y = a_y + t \cdot (b_y - a_y)$$

Uses `FP16-LERP` for each component.

---

## Geometric Operations

### V2-PERP

```forth
V2-PERP  ( x y -- -y x )
```

90° counter-clockwise perpendicular.

### V2-REFLECT

```forth
V2-REFLECT  ( vx vy nx ny -- rx ry )
```

Reflect vector $v$ across the unit normal $n$:

$$r = v - 2(v \cdot n) \, n$$

Assumes $n$ is unit length.  Use `V2-NORM` first if needed.

### V2-ROTATE

```forth
V2-ROTATE  ( x y angle -- rx ry )
```

Rotate vector by `angle` (FP16 radians):

$$x' = x \cos\theta - y \sin\theta$$
$$y' = x \sin\theta + y \cos\theta$$

Uses `TRIG-SINCOS` from `trig.f`.

---

## Component-wise Min / Max

| Word | Stack | Operation |
|---|---|---|
| `V2-MIN` | `( ax ay bx by -- rx ry )` | $(\min(a_x, b_x),\ \min(a_y, b_y))$ |
| `V2-MAX` | `( ax ay bx by -- rx ry )` | $(\max(a_x, b_x),\ \max(a_y, b_y))$ |

---

## Equality

```forth
V2-EQ  ( ax ay bx by -- flag )
```

True (−1) if both components are bitwise equal.

---

## Internals

| Word | Purpose |
|---|---|
| `_V2-A`, `_V2-B`, `_V2-C`, `_V2-D` | VARIABLEs holding intermediate FP16 values during multi-operand ops |
| `_V2L-T` | VARIABLE holding the `t` parameter during `V2-LERP` |
| `_V2R-2D` | VARIABLE holding `2·(v·n)` during `V2-REFLECT` |
| `_VR-SIN`, `_VR-COS` | VARIABLEs holding sin/cos during `V2-ROTATE` |

---

## Quick Reference

```
V2-ADD     ( ax ay bx by -- rx ry )   V2-PERP     ( x y -- -y x )
V2-SUB     ( ax ay bx by -- rx ry )   V2-REFLECT  ( vx vy nx ny -- rx ry )
V2-SCALE   ( x y s -- rx ry )         V2-ROTATE   ( x y angle -- rx ry )
V2-NEG     ( x y -- -x -y )           V2-MIN      ( ax ay bx by -- rx ry )
V2-DOT     ( ax ay bx by -- dot )     V2-MAX      ( ax ay bx by -- rx ry )
V2-CROSS   ( ax ay bx by -- cross )   V2-EQ       ( ax ay bx by -- flag )
V2-LENSQ   ( x y -- len² )            V2-ZERO     ( -- x y )
V2-LEN     ( x y -- len )             V2-ONE      ( -- x y )
V2-NORM    ( x y -- nx ny )
V2-DIST    ( ax ay bx by -- d )
V2-LERP    ( ax ay bx by t -- rx ry )
```
