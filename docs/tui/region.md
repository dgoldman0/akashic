# akashic-tui-region — Rectangular Clipping Regions

A region is a clipping rectangle within the screen.  Widgets draw
into regions; the region clips all cell writes to its bounds.
Regions can be nested (child within parent).

When a region is active (via `RGN-USE`), all `DRW-*` coordinates are
relative to the region's top-left, and writes outside the region
are silently discarded.  `RGN-ROOT` resets to full-screen drawing.

```forth
REQUIRE tui/region.f
```

`PROVIDED akashic-tui-region` — safe to include multiple times.

**Dependencies:** `screen.f`, `draw.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Region Descriptor](#region-descriptor)
- [Constructor / Destructor](#constructor--destructor)
- [Accessors](#accessors)
- [Activation](#activation)
- [Sub-regions](#sub-regions)
- [Point Testing](#point-testing)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Coordinate translation** | `RGN-USE` sets an origin offset; `DRW-CHAR` translates (row,col) by the region's top-left before hitting `SCR-SET`. |
| **Clip-safe** | `_DRW-IN-BOUNDS?` checks against the active region's height and width. Out-of-region writes are silently dropped. |
| **Per-region scope** | Only one region is active at a time.  Switching regions is a single `RGN-USE` call. |
| **Nested clipping** | `RGN-SUB` clips the sub-region to its parent's bounds at creation time.  No runtime parent-chain walk. |
| **Heap-allocated** | Descriptors are `ALLOCATE`d; caller frees with `RGN-FREE`. |
| **Prefix convention** | Public: `RGN-`. Internal: `_RGN-`. |

---

## Region Descriptor

Five cells (40 bytes), stored in allocated memory:

| Offset | Field   | Description |
|--------|---------|-------------|
| +0     | row     | Top-left row (screen-absolute) |
| +8     | col     | Top-left column (screen-absolute) |
| +16    | height  | Height in rows |
| +24    | width   | Width in columns |
| +32    | parent  | Parent region address (0 = root) |

---

## Constructor / Destructor

### RGN-NEW

```forth
RGN-NEW  ( row col h w -- rgn )
```

Allocate a root region (no parent).

```forth
0 0 24 80 RGN-NEW   \ full terminal region
```

### RGN-FREE

```forth
RGN-FREE  ( rgn -- )
```

Free region descriptor memory.

---

## Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `RGN-ROW` | `( rgn -- row )` | Absolute top-left row |
| `RGN-COL` | `( rgn -- col )` | Absolute top-left column |
| `RGN-H`   | `( rgn -- h )`   | Height in rows |
| `RGN-W`   | `( rgn -- w )`   | Width in columns |

---

## Activation

### RGN-USE

```forth
RGN-USE  ( rgn -- )
```

Set as the current drawing region.  All subsequent `DRW-*` calls
will translate coordinates relative to this region's origin and
clip to its bounds.

```forth
my-region RGN-USE
65 0 0 DRW-CHAR       \ 'A' at region-relative (0,0)
```

### RGN-ROOT

```forth
RGN-ROOT  ( -- )
```

Reset to full-screen drawing — no translation, no region clipping.
Clip bounds revert to `SCR-H × SCR-W`.

---

## Sub-regions

### RGN-SUB

```forth
RGN-SUB  ( parent r c h w -- rgn )
```

Create a sub-region at position *(r, c)* relative to the parent's
top-left.  The sub-region is automatically clipped to the parent's
bounds:

- If `r + h > parent-h`, height is reduced.
- If `c + w > parent-w`, width is reduced.
- Negative overflow clamps to zero.

```forth
parent 2 4 10 20 RGN-SUB   \ 10×20 sub at parent-relative (2,4)
```

---

## Point Testing

### RGN-CONTAINS?

```forth
RGN-CONTAINS?  ( row col -- flag )
```

Test whether a region-relative point is inside the current region.
Returns `TRUE` (-1) if `0 ≤ row < h` and `0 ≤ col < w`.

### RGN-CLIP

```forth
RGN-CLIP  ( row col -- row' col' flag )
```

Translate region-relative `(row, col)` to screen-absolute
`(row', col')` and test if the point is inside the region.
`flag` is `TRUE` if inside, `FALSE` if outside.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `RGN-NEW` | `( row col h w -- rgn )` | Allocate root region |
| `RGN-FREE` | `( rgn -- )` | Free region |
| `RGN-ROW` | `( rgn -- row )` | Get absolute row |
| `RGN-COL` | `( rgn -- col )` | Get absolute column |
| `RGN-H` | `( rgn -- h )` | Get height |
| `RGN-W` | `( rgn -- w )` | Get width |
| `RGN-USE` | `( rgn -- )` | Set as current drawing region |
| `RGN-ROOT` | `( -- )` | Reset to full-screen |
| `RGN-SUB` | `( parent r c h w -- rgn )` | Create clipped sub-region |
| `RGN-CONTAINS?` | `( row col -- flag )` | Point inside current region? |
| `RGN-CLIP` | `( row col -- row' col' flag )` | Translate + test |
