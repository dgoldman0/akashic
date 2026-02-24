# akashic-rect — Axis-Aligned Rectangles for KDOS / Megapad-64

Axis-aligned bounding rectangle (AABB) operations using FP16
arithmetic via the tile engine.  Rectangles are stored as 4
consecutive cells in memory: `x y w h`.

```forth
REQUIRE rect.f
```

`PROVIDED akashic-rect` — safe to include multiple times.
Auto-loads `fp16-ext.f` (and transitively `fp16.f`) via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Queries](#queries)
- [Hit Testing](#hit-testing)
- [Set Operations](#set-operations)
- [Expansion](#expansion)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Memory-resident** | Rects live in memory (4 cells), not on the stack.  Words take address parameters. |
| **x y w h format** | Origin + size, not min/max corners.  Width and height must be non-negative for well-formed rects. |
| **One FP16 per cell** | Each element occupies a full 64-bit cell; only the low 16 bits are used. |
| **PREFIX convention** | Public words use `RECT-`, internals use `_RECT-`. |
| **VARIABLEs for scratch** | Two sets of scratch variables (`_R-X1` .. `_R-H1` and `_R-X2` .. `_R-H2`) hold rect elements during multi-rect operations. |
| **Not re-entrant** | Shared VARIABLEs mean concurrent callers would collide. |

---

## Memory Layout

A rectangle at address `addr`:

```
   Offset   Element   Description
   +0 CELL  x         left edge
   +1 CELL  y         top edge
   +2 CELL  w         width
   +3 CELL  h         height
```

Total size: **4 cells** (32 bytes on Megapad-64).

Right edge = $x + w$, bottom edge = $y + h$.

---

## Queries

### RECT-AREA

```forth
RECT-AREA  ( rect -- area )
```

Returns $w \times h$ as an FP16 value.

### RECT-CENTER

```forth
RECT-CENTER  ( rect -- cx cy )
```

Returns the center point:

$$c_x = x + \tfrac{w}{2}, \quad c_y = y + \tfrac{h}{2}$$

### RECT-EMPTY?

```forth
RECT-EMPTY?  ( rect -- flag )
```

True (−1) if the rectangle has zero or negative area (either $w \le 0$
or $h \le 0$).

---

## Hit Testing

### RECT-CONTAINS?

```forth
RECT-CONTAINS?  ( rect px py -- flag )
```

True (−1) if point $(p_x, p_y)$ lies inside the rectangle:

$$p_x \ge x \;\wedge\; p_x < x + w \;\wedge\; p_y \ge y \;\wedge\; p_y < y + h$$

### RECT-INTERSECT?

```forth
RECT-INTERSECT?  ( r1 r2 -- flag )
```

True (−1) if the two rectangles overlap (have a non-empty
intersection).  Uses the separating-axis test:

$$x_1 < x_2 + w_2 \;\wedge\; x_2 < x_1 + w_1 \;\wedge\; y_1 < y_2 + h_2 \;\wedge\; y_2 < y_1 + h_1$$

---

## Set Operations

### RECT-INTERSECT

```forth
RECT-INTERSECT  ( r1 r2 dst -- flag )
```

Compute the intersection of two rectangles and store it at `dst`.
Returns `TRUE` (−1) if the intersection is non-empty, `FALSE` (0) if
the rects are disjoint (in which case `dst` is zeroed).

$$\text{left} = \max(x_1, x_2), \quad \text{top} = \max(y_1, y_2)$$
$$\text{right} = \min(x_1 + w_1,\; x_2 + w_2), \quad \text{bottom} = \min(y_1 + h_1,\; y_2 + h_2)$$

### RECT-UNION

```forth
RECT-UNION  ( r1 r2 dst -- )
```

Compute the bounding rectangle that encloses both `r1` and `r2`,
storing it at `dst`.

$$\text{left} = \min(x_1, x_2), \quad \text{top} = \min(y_1, y_2)$$
$$\text{right} = \max(x_1 + w_1,\; x_2 + w_2), \quad \text{bottom} = \max(y_1 + h_1,\; y_2 + h_2)$$

---

## Expansion

### RECT-EXPAND

```forth
RECT-EXPAND  ( rect margin dst -- )
```

Expand the rectangle by `margin` on all four sides:

$$x' = x - m, \quad y' = y - m, \quad w' = w + 2m, \quad h' = h + 2m$$

`rect` and `dst` may be the same address for in-place expansion.

---

## Internals

| Word | Purpose |
|---|---|
| `_RECT-X` .. `_RECT-H` | Address helpers: `( base -- elem-addr )` for each of the 4 elements |
| `_RECT@` | `( elem-addr -- fp16 )` — fetch and mask to 16 bits |
| `_RECT!` | `( fp16 elem-addr -- )` — mask and store |
| `_RECT-READ1` | `( addr -- )` — load rect into scratch set 1 (`_R-X1` .. `_R-H1`) |
| `_RECT-READ2` | `( addr -- )` — load rect into scratch set 2 (`_R-X2` .. `_R-H2`) |
| `_RECT-WRITE1` | `( addr -- )` — write scratch set 1 to memory |
| `_R-X1` .. `_R-H1` | Scratch VARIABLEs for first rect |
| `_R-X2` .. `_R-H2` | Scratch VARIABLEs for second rect |
| `_RI-LX`, `_RI-LY`, `_RI-RX`, `_RI-RY` | Intermediate corner coords during intersection / union |
| `_RC-PX`, `_RC-PY` | Point coords during `RECT-CONTAINS?` |
| `_R-TMP` | Temporary for margin during `RECT-EXPAND` |

---

## Quick Reference

```
RECT-AREA       ( rect -- area )          width × height
RECT-CENTER     ( rect -- cx cy )         center point
RECT-EMPTY?     ( rect -- flag )          zero or negative area?
RECT-CONTAINS?  ( rect px py -- flag )    point-in-rect test
RECT-INTERSECT? ( r1 r2 -- flag )         do two rects overlap?
RECT-INTERSECT  ( r1 r2 dst -- flag )     compute intersection
RECT-UNION      ( r1 r2 dst -- )          bounding rect of two
RECT-EXPAND     ( rect margin dst -- )    expand by margin
```
