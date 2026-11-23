# akashic-game-2d-collide — Collision Detection

Tile-based collision maps and geometric primitives (point-in-rect,
AABB overlap).  Data is stored as a byte-per-tile grid — compact and
fast for tile-based games.  A map read by `game/map.f` gives its
collision values, its sight map and its tile kinds in this form.

```forth
REQUIRE game/2d/collide.f
```

`PROVIDED akashic-game-2d-collide` — safe to include multiple times.

---

## Table of Contents

- [Collision Maps](#collision-maps)
  - [Constructor / Destructor](#constructor--destructor)
  - [Tile Access](#tile-access)
  - [Queries](#queries)
- [Geometric Primitives](#geometric-primitives)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Collision Maps

A collision map is a grid of bytes, one per tile.  Zero means
passable; any non-zero value means solid (or can encode different
terrain types).

### Constructor / Destructor

#### CMAP-NEW

```
( w h -- cmap )
```

Allocate a collision map descriptor (24 bytes) and a byte buffer
(`w × h` bytes).  All tiles are initialized to 0 (passable).  A failed
allocation aborts.

#### CMAP-NEW?

```
( w h -- cmap ior )
```

`CMAP-NEW` for a caller that answers running out of memory itself, as
the map reader does for a map a player wrote: the map and 0, or 0 and
the ior of the allocation that failed, with nothing left allocated.
Both sizes must be at least 1.

#### CMAP-FREE

```
( cmap -- )
```

Free the data buffer and descriptor.

---

### Tile Access

#### CMAP-SET

```
( cmap col row val -- )
```

Set the collision value at (col, row).  `val` is stored as a
byte (0–255).  Out-of-bounds writes are silently ignored.

#### CMAP-GET

```
( cmap col row -- val )
```

Get the collision value at (col, row).  Returns 0 for
out-of-bounds positions (passable by default).

#### CMAP-FILL

```
( cmap val -- )
```

Fill every tile with the given value.

```forth
my-cmap 1 CMAP-FILL   \ make everything solid
my-cmap 0 CMAP-FILL   \ make everything passable
```

#### CMAP-W / CMAP-H

```
( cmap -- w )
( cmap -- h )
```

Return the map's width and height.

#### CMAP-DATA

```
( cmap -- addr )
```

Return the address of the tile bytes, width × height of them, row by
row: the byte of tile (col, row) is at `addr + row × width + col`. The
address stays the same for the map's life, so a reader such as the fog of
war can keep it and read tiles directly.

---

### Queries

#### CMAP-SOLID?

```
( cmap col row -- flag )
```

Return TRUE if the tile at (col, row) is non-zero (solid).
Returns FALSE for out-of-bounds positions.

---

## Geometric Primitives

Standalone geometry tests, independent of collision maps.

### PT-IN-RECT?

```
( px py rx ry rw rh -- flag )
```

Return TRUE if point (px, py) is inside the rectangle defined by
origin (rx, ry) and size (rw, rh).  The left and top edges are
inclusive; the right and bottom edges are exclusive.

```forth
5 5  2 2 8 8  PT-IN-RECT?   \ TRUE  — (5,5) inside [2..10)×[2..10)
10 5  2 2 8 8  PT-IN-RECT?  \ FALSE — right edge exclusive
```

### AABB-OVERLAP?

```
( x1 y1 w1 h1 x2 y2 w2 h2 -- flag )
```

Return TRUE if two axis-aligned bounding boxes overlap.  Touching
edges (zero overlap) returns FALSE.

```forth
0 0 3 3  2 2 3 3  AABB-OVERLAP?   \ TRUE  — partial overlap
0 0 3 3  3 0 3 3  AABB-OVERLAP?   \ FALSE — touching, not overlapping
```

---

## Descriptor Layout

24 bytes (3 cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0      8   width   Map width in columns
 +8      8   height  Map height in rows
+16      8   data    Address of byte array (width × height)
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `CMAP-NEW` | `( w h -- cmap )` | Allocate collision map |
| `CMAP-NEW?` | `( w h -- cmap ior )` | The same, answering failure |
| `CMAP-FREE` | `( cmap -- )` | Free collision map |
| `CMAP-SET` | `( cmap col row val -- )` | Set tile value |
| `CMAP-GET` | `( cmap col row -- val )` | Get tile value |
| `CMAP-SOLID?` | `( cmap col row -- flag )` | Tile solid? |
| `CMAP-FILL` | `( cmap val -- )` | Fill all tiles |
| `CMAP-W` | `( cmap -- w )` | Map width |
| `CMAP-H` | `( cmap -- h )` | Map height |
| `CMAP-DATA` | `( cmap -- addr )` | Tile bytes, row by row |
| `PT-IN-RECT?` | `( px py rx ry rw rh -- flag )` | Point in rect? |
| `AABB-OVERLAP?` | `( x1 y1 w1 h1 x2 y2 w2 h2 -- flag )` | AABB overlap? |

When `GUARDED` is set, `CMAP-NEW?`, `CMAP-NEW`, `CMAP-FREE`, `CMAP-SET`
and `CMAP-FILL` take the module's guard; the reads and the geometric
words are pure computation.
