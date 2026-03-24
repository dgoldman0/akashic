# akashic-game-2d-collide — Collision Detection

Tile-based collision maps, geometric primitives (point-in-rect,
AABB overlap), and sprite-level collision helpers.  Data is stored
as a byte-per-tile grid — compact and fast for tile-based games.

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
- [Sprite Helpers](#sprite-helpers)
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
(`w × h` bytes).  All tiles are initialized to 0 (passable).

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

## Sprite Helpers

These require `sprite.f` (auto-loaded via `REQUIRE`).

### SPR-CMAP-BLOCKED?

```
( spr dx dy cmap -- flag )
```

Check whether moving sprite `spr` by `(dx, dy)` would place it
on a solid tile.  Computes `(spr-x + dx, spr-y + dy)` and tests
`CMAP-SOLID?`.

```forth
player 1 0 my-cmap SPR-CMAP-BLOCKED? IF
    \ Can't move right — wall
ELSE
    player 1 0 SPR-MOVE
THEN
```

### SPR-SPR-OVERLAP?

```
( spr1 spr2 -- flag )
```

Return TRUE if two 1×1 sprites occupy the same tile (same x and
same y).

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
| `CMAP-FREE` | `( cmap -- )` | Free collision map |
| `CMAP-SET` | `( cmap col row val -- )` | Set tile value |
| `CMAP-GET` | `( cmap col row -- val )` | Get tile value |
| `CMAP-SOLID?` | `( cmap col row -- flag )` | Tile solid? |
| `CMAP-FILL` | `( cmap val -- )` | Fill all tiles |
| `CMAP-W` | `( cmap -- w )` | Map width |
| `CMAP-H` | `( cmap -- h )` | Map height |
| `PT-IN-RECT?` | `( px py rx ry rw rh -- flag )` | Point in rect? |
| `AABB-OVERLAP?` | `( x1 y1 w1 h1 x2 y2 w2 h2 -- flag )` | AABB overlap? |
| `SPR-CMAP-BLOCKED?` | `( spr dx dy cmap -- flag )` | Movement blocked? |
| `SPR-SPR-OVERLAP?` | `( spr1 spr2 -- flag )` | Sprites on same tile? |

No guard section — collision operations are pure computation.
