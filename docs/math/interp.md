# akashic-interp — Interpolation, Easing & Splines

Easing curves for CSS transitions/animations and general-purpose
spline interpolation, all in FP16.

```forth
REQUIRE interp.f
```

`PROVIDED akashic-interp` — REQUIRE `fp16-ext.f`, `trig.f`, `exp.f`.

---

## Table of Contents

- [Design](#design)
- [Smoothstep](#smoothstep)
- [Quadratic Easing](#quadratic-easing)
- [Cubic Easing](#cubic-easing)
- [Sinusoidal Easing](#sinusoidal-easing)
- [Elastic & Bounce](#elastic--bounce)
- [CSS cubic-bezier()](#css-cubic-bezier)
- [Splines](#splines)
- [Quick Reference](#quick-reference)

---

## Design

| Principle | Detail |
|---|---|
| **CSS-first** | Easing functions match the CSS Easing Functions Level 2 spec. `INTERP-CUBIC-BEZIER` implements CSS `cubic-bezier()` directly. |
| **Normalized input** | Parameter `t` is expected in $[0, 1]$ unless otherwise noted. |
| **Clamping** | `INTERP-SMOOTHSTEP` and `INTERP-SMOOTHERSTEP` clamp internally. Other functions assume valid input. |
| **Dependencies** | Sine easing requires `trig.f`; elastic easing requires `exp.f`. |

---

## Smoothstep

### INTERP-SMOOTHSTEP

```forth
INTERP-SMOOTHSTEP  ( edge0 edge1 x -- r )
```

Hermite smoothstep: maps $x$ from $[\text{edge0}, \text{edge1}]$ to
$[0, 1]$ via $3t^2 - 2t^3$.  Clamped to $[0, 1]$.

### INTERP-SMOOTHERSTEP

```forth
INTERP-SMOOTHERSTEP  ( edge0 edge1 x -- r )
```

Perlin's improved version: $6t^5 - 15t^4 + 10t^3$.  First and
second derivatives are zero at the boundaries.

---

## Quadratic Easing

### INTERP-EASE-IN-QUAD

```forth
INTERP-EASE-IN-QUAD  ( t -- r )
```

$r = t^2$ — accelerating from zero velocity.

### INTERP-EASE-OUT-QUAD

```forth
INTERP-EASE-OUT-QUAD  ( t -- r )
```

$r = 1 - (1-t)^2$ — decelerating to zero velocity.

### INTERP-EASE-IN-OUT-QUAD

```forth
INTERP-EASE-IN-OUT-QUAD  ( t -- r )
```

Smooth acceleration/deceleration: $2t^2$ for $t < 0.5$,
$1 - (-2t+2)^2/2$ otherwise.

---

## Cubic Easing

### INTERP-EASE-IN-CUBIC

```forth
INTERP-EASE-IN-CUBIC  ( t -- r )
```

$r = t^3$

### INTERP-EASE-OUT-CUBIC

```forth
INTERP-EASE-OUT-CUBIC  ( t -- r )
```

$r = 1 - (1-t)^3$

### INTERP-EASE-IN-OUT-CUBIC

```forth
INTERP-EASE-IN-OUT-CUBIC  ( t -- r )
```

$4t^3$ for $t < 0.5$, $1 - (-2t+2)^3/2$ otherwise.

---

## Sinusoidal Easing

### INTERP-EASE-IN-SINE

```forth
INTERP-EASE-IN-SINE  ( t -- r )
```

$r = 1 - \cos(t \cdot \pi/2)$

### INTERP-EASE-OUT-SINE

```forth
INTERP-EASE-OUT-SINE  ( t -- r )
```

$r = \sin(t \cdot \pi/2)$

---

## Elastic & Bounce

### INTERP-EASE-ELASTIC

```forth
INTERP-EASE-ELASTIC  ( t -- r )
```

Elastic oscillation: $-2^{10(t-1)} \cdot \sin\bigl((t - 1.075) \cdot 2\pi / 0.3\bigr)$.
Returns 0 at $t=0$ and 1 at $t=1$.

### INTERP-EASE-BOUNCE

```forth
INTERP-EASE-BOUNCE  ( t -- r )
```

Bounce-in effect (piecewise quadratic).  Internally uses
`_IP-BOUNCE-OUT` computed on $1-t$.

---

## CSS cubic-bezier()

### INTERP-CUBIC-BEZIER

```forth
INTERP-CUBIC-BEZIER  ( t x1 y1 x2 y2 -- r )
```

Implements the CSS `cubic-bezier(x1, y1, x2, y2)` timing function.

Control points are $P_0 = (0,0)$, $P_1 = (x_1, y_1)$,
$P_2 = (x_2, y_2)$, $P_3 = (1,1)$.

**Algorithm:**
1. 5 Newton-Raphson iterations to find parameter $u$ such that
   $B_x(u) = t$.
2. Evaluate $B_y(u)$ at the converged $u$.

**Example — CSS `ease`:**

```forth
\ CSS ease = cubic-bezier(0.25, 0.1, 0.25, 1.0)
0x3400  \ t = 0.25 (some progress point)
0x3400  \ x1 = 0.25
0x2E66  \ y1 = 0.1
0x3400  \ x2 = 0.25
0x3C00  \ y2 = 1.0
INTERP-CUBIC-BEZIER .
```

---

## Splines

### INTERP-CATMULL-ROM

```forth
INTERP-CATMULL-ROM  ( p0 p1 p2 p3 t -- r )
```

Catmull-Rom spline interpolation through four control points.
The curve passes through $p_1$ at $t=0$ and $p_2$ at $t=1$,
using $p_0$ and $p_3$ to determine tangent direction.

$$q(t) = \tfrac{1}{2}\bigl[2p_1 + (-p_0 + p_2)t + (2p_0 - 5p_1 + 4p_2 - p_3)t^2 + (-p_0 + 3p_1 - 3p_2 + p_3)t^3\bigr]$$

### INTERP-HERMITE

```forth
INTERP-HERMITE  ( p0 m0 p1 m1 t -- r )
```

Cubic Hermite interpolation with explicit tangents.

- $p_0$, $p_1$ — endpoint values
- $m_0$, $m_1$ — endpoint tangents
- $t$ — parameter in $[0, 1]$

$$H(t) = (2t^3 - 3t^2 + 1)p_0 + (t^3 - 2t^2 + t)m_0 + (-2t^3 + 3t^2)p_1 + (t^3 - t^2)m_1$$

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `INTERP-SMOOTHSTEP` | `( edge0 edge1 x -- r )` | Hermite smoothstep |
| `INTERP-SMOOTHERSTEP` | `( edge0 edge1 x -- r )` | Perlin's improved |
| `INTERP-EASE-IN-QUAD` | `( t -- r )` | $t^2$ |
| `INTERP-EASE-OUT-QUAD` | `( t -- r )` | $1-(1-t)^2$ |
| `INTERP-EASE-IN-OUT-QUAD` | `( t -- r )` | Smooth quad in-out |
| `INTERP-EASE-IN-CUBIC` | `( t -- r )` | $t^3$ |
| `INTERP-EASE-OUT-CUBIC` | `( t -- r )` | $1-(1-t)^3$ |
| `INTERP-EASE-IN-OUT-CUBIC` | `( t -- r )` | Smooth cubic in-out |
| `INTERP-EASE-IN-SINE` | `( t -- r )` | Sinusoidal ease-in |
| `INTERP-EASE-OUT-SINE` | `( t -- r )` | Sinusoidal ease-out |
| `INTERP-EASE-ELASTIC` | `( t -- r )` | Elastic oscillation |
| `INTERP-EASE-BOUNCE` | `( t -- r )` | Bounce |
| `INTERP-CUBIC-BEZIER` | `( t x1 y1 x2 y2 -- r )` | CSS `cubic-bezier()` |
| `INTERP-CATMULL-ROM` | `( p0 p1 p2 p3 t -- r )` | Catmull-Rom spline |
| `INTERP-HERMITE` | `( p0 m0 p1 m1 t -- r )` | Cubic Hermite |
