# akashic-mat2d — 2×3 Affine Transform Matrices for KDOS / Megapad-64

2×3 affine transformation matrices using FP16 arithmetic via the tile
engine.  A matrix is stored as 6 consecutive cells in memory, each
holding one FP16 value in its low 16 bits.

```forth
REQUIRE mat2d.f
```

`PROVIDED akashic-mat2d` — safe to include multiple times.
Auto-loads `fp16-ext.f` and `trig.f` (and transitively `fp16.f`)
via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Construction](#construction)
- [Point Transformation](#point-transformation)
- [Matrix Multiplication](#matrix-multiplication)
- [Inversion](#inversion)
- [Compound Construction](#compound-construction)
- [Copying](#copying)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Memory-resident** | Matrices live in memory (6 cells), not on the stack.  Words take an address parameter. |
| **One FP16 per cell** | Each element occupies a full 64-bit cell; only the low 16 bits are used.  Stored via `!`, fetched via `@ 0xFFFF AND`. |
| **Row-major order** | Elements are stored as `a b tx c d ty` (row 0 then row 1). |
| **PREFIX convention** | Public words use `M2D-`, internals use `_M2D-`. |
| **VARIABLEs for scratch** | Shared scratch variables hold matrix elements during computation.  No locals. |
| **Not re-entrant** | Shared VARIABLEs mean concurrent callers would collide. |

---

## Memory Layout

A 2×3 affine matrix at address `addr`:

```
         ┌            ┐
         │ a   b   tx │     x' = a·x + b·y + tx
         │ c   d   ty │     y' = c·x + d·y + ty
         └            ┘

   Offset   Element   Index
   +0 CELL  a         (0,0)
   +1 CELL  b         (0,1)
   +2 CELL  tx        (0,2)
   +3 CELL  c         (1,0)
   +4 CELL  d         (1,1)
   +5 CELL  ty        (1,2)
```

Total size: **6 cells** (48 bytes on Megapad-64).

---

## Construction

### M2D-IDENTITY

```forth
M2D-IDENTITY  ( addr -- )
```

Store the identity matrix at `addr`:
$a = 1,\ b = 0,\ tx = 0,\ c = 0,\ d = 1,\ ty = 0$.

### M2D-TRANSLATE

```forth
M2D-TRANSLATE  ( addr tx ty -- )
```

Set `addr` to a pure translation matrix.  Starts from identity,
then sets `tx` and `ty`.

### M2D-SCALE

```forth
M2D-SCALE  ( addr sx sy -- )
```

Set `addr` to a pure scale matrix:
$a = s_x,\ d = s_y$, all others zero except identity positions.

### M2D-ROTATE

```forth
M2D-ROTATE  ( addr angle -- )
```

Set `addr` to a pure rotation matrix.  `angle` is FP16 radians.

$$a = \cos\theta, \quad b = -\sin\theta$$
$$c = \sin\theta, \quad d = \cos\theta$$
$$tx = 0, \quad ty = 0$$

---

## Point Transformation

### M2D-TRANSFORM

```forth
M2D-TRANSFORM  ( addr x y -- x' y' )
```

Transform a single point:

$$x' = a \cdot x + b \cdot y + tx$$
$$y' = c \cdot x + d \cdot y + ty$$

### M2D-TRANSFORM-N

```forth
M2D-TRANSFORM-N  ( mat src dst n -- )
```

Batch-transform `n` points.  Points at `src` and `dst` are stored
as pairs of FP16 values (2 cells each).  `src` and `dst` may be
the same address for in-place transformation.

The matrix is read once into scratch variables, then the loop
applies the transform to each point.

---

## Matrix Multiplication

### M2D-MULTIPLY

```forth
M2D-MULTIPLY  ( a b dst -- )
```

Compute $\text{dst} = a \times b$ (affine matrix product).

$$\text{dst.a}  = a_a \cdot b_a  + a_b \cdot b_c$$
$$\text{dst.b}  = a_a \cdot b_b  + a_b \cdot b_d$$
$$\text{dst.tx} = a_a \cdot b_{tx} + a_b \cdot b_{ty} + a_{tx}$$

(And similarly for the second row.)

`a` or `b` must not alias `dst`.  Use a temporary buffer if needed.

---

## Inversion

### M2D-INVERT

```forth
M2D-INVERT  ( src dst -- flag )
```

Compute the inverse of the affine matrix at `src`, storing the
result at `dst`.  Returns `TRUE` (−1) on success, `FALSE` (0) if
the matrix is singular (determinant ≈ 0).

The 2×2 block is inverted analytically:

$$\det = a \cdot d - b \cdot c$$

$$a' = d / \det, \quad b' = -b / \det, \quad c' = -c / \det, \quad d' = a / \det$$

The new translation is:

$$tx' = -(a' \cdot tx + b' \cdot ty)$$
$$ty' = -(c' \cdot tx + d' \cdot ty)$$

---

## Compound Construction

### M2D-COMPOSE

```forth
M2D-COMPOSE  ( addr tx ty sx sy angle -- )
```

Build a complete TRS (translate–rotate–scale) matrix in one call.
Equivalent to applying Scale → Rotate → Translate:

$$a = s_x \cos\theta, \quad b = -s_y \sin\theta, \quad tx = tx$$
$$c = s_x \sin\theta, \quad d = s_y \cos\theta, \quad ty = ty$$

---

## Copying

### M2D-COPY

```forth
M2D-COPY  ( src dst -- )
```

Copy all 6 elements from `src` to `dst`.

---

## Internals

| Word | Purpose |
|---|---|
| `_M2D-A` .. `_M2D-TY` | Address helpers: `( base -- elem-addr )` for each of the 6 elements |
| `_M2D@` | `( elem-addr -- fp16 )` — fetch and mask to 16 bits |
| `_M2D!` | `( fp16 elem-addr -- )` — mask and store |
| `_M-A` .. `_M-TY` | Scratch VARIABLEs for matrix elements during transform / multiply |
| `_MT-X`, `_MT-Y` | Scratch for the input point during `M2D-TRANSFORM` |
| `_MN-MAT`, `_MN-SRC`, `_MN-DST` | Pointers during `M2D-TRANSFORM-N` |
| `_MM-AA` .. `_MM-BTY`, `_MM-DST` | Scratch for both matrices during `M2D-MULTIPLY` |
| `_MI-DET`, `_MI-IA` .. `_MI-ID` | Inverse computation scratch |
| `_MR-SIN`, `_MR-COS` | sin/cos during `M2D-ROTATE` |
| `_MC-SIN`, `_MC-COS` | sin/cos during `M2D-COMPOSE` |

---

## Quick Reference

```
M2D-IDENTITY    ( addr -- )                     set to identity
M2D-TRANSLATE   ( addr tx ty -- )               set to translation
M2D-SCALE       ( addr sx sy -- )               set to scale
M2D-ROTATE      ( addr angle -- )               set to rotation
M2D-COMPOSE     ( addr tx ty sx sy angle -- )    build TRS matrix
M2D-TRANSFORM   ( addr x y -- x' y' )           transform one point
M2D-TRANSFORM-N ( mat src dst n -- )             batch transform
M2D-MULTIPLY    ( a b dst -- )                   dst = a × b
M2D-INVERT      ( src dst -- flag )              invert matrix
M2D-COPY        ( src dst -- )                   copy 6 cells
```
