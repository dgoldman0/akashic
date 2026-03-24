# akashic-tui-game-sprite — Character-Cell Sprite Objects

Single-cell sprite objects with position, z-order, visibility,
frame animation, and user-data fields.  Includes a pool system
for managing groups of sprites with z-sorted rendering.

```forth
REQUIRE tui/game/sprite.f
```

`PROVIDED akashic-tui-game-sprite` — safe to include multiple times.

---

## Table of Contents

- [Sprites](#sprites)
  - [Constructor / Destructor](#constructor--destructor)
  - [Position](#position)
  - [Appearance](#appearance)
  - [Visibility](#visibility)
  - [Z-Order](#z-order)
  - [User Data](#user-data)
  - [Animation](#animation)
- [Sprite Pools](#sprite-pools)
  - [Pool Constructor / Destructor](#pool-constructor--destructor)
  - [Pool Operations](#pool-operations)
  - [Pool Rendering](#pool-rendering)
- [Descriptor Layouts](#descriptor-layouts)
- [Quick Reference](#quick-reference)

---

## Sprites

### Constructor / Destructor

#### SPR-NEW

```
( cell -- spr )
```

Allocate a 64-byte sprite descriptor.  Sets the initial cell,
position (0, 0), z-order 0, visible, no animation, user-data 0.

```forth
[CHAR] @ 7 0 0 CELL-MAKE SPR-NEW  CONSTANT player
```

#### SPR-FREE

```
( spr -- )
```

Free the sprite descriptor.

---

### Position

#### SPR-POS!

```
( spr x y -- )
```

Set the sprite's position in world coordinates.

#### SPR-POS@

```
( spr -- x y )
```

Get the sprite's current position.  `x` is column, `y` is row.

#### SPR-MOVE

```
( spr dx dy -- )
```

Move the sprite by a relative delta.

```forth
player 1 0 SPR-MOVE   \ move one column right
player 0 -1 SPR-MOVE  \ move one row up
```

---

### Appearance

#### SPR-CELL!

```
( spr cell -- )
```

Set the sprite's display cell (codepoint + colors + attrs).

#### SPR-CELL@

```
( spr -- cell )
```

Get the sprite's current display cell.

---

### Visibility

#### SPR-VISIBLE!

```
( spr -- )
```

Make the sprite visible.  Visible sprites are drawn by pool
rendering.

#### SPR-HIDDEN!

```
( spr -- )
```

Hide the sprite.  Hidden sprites are skipped during rendering.

#### SPR-VISIBLE?

```
( spr -- flag )
```

Return TRUE if the sprite is visible.

---

### Z-Order

#### SPR-Z!

```
( spr z -- )
```

Set z-order.  Higher values render on top.  Pool rendering sorts
by z before drawing.

#### SPR-Z@

```
( spr -- z )
```

Get current z-order.

---

### User Data

#### SPR-USER!

```
( spr val -- )
```

Store an arbitrary value in the sprite's user-data field (entity
ID, hitpoints, type tag, etc.).

#### SPR-USER@

```
( spr -- val )
```

Retrieve the user-data value.

---

### Animation

#### SPR-ANIM!

```
( spr tbl count rate -- )
```

Attach a frame animation.  `tbl` is the address of a cell array
(one cell per frame).  `count` is the number of frames.  `rate`
is the number of ticks between frame advances.

The sprite's cell is immediately set to frame 0.

```forth
\ Define animation frames
CREATE walk-frames
    [CHAR] A 7 0 0 CELL-MAKE ,
    [CHAR] B 7 0 0 CELL-MAKE ,
    [CHAR] C 7 0 0 CELL-MAKE ,

player walk-frames 3 2 SPR-ANIM!  \ 3 frames, advance every 2 ticks
```

#### SPR-TICK

```
( spr -- )
```

Advance the animation by one tick.  When the tick counter reaches
the rate, the frame index advances (wrapping at `count`) and the
sprite's cell is updated from the frame table.

If no animation is attached, this is a no-op.

---

## Sprite Pools

A pool manages a group of sprites and provides batch operations.

### Pool Constructor / Destructor

#### SPOOL-NEW

```
( max -- pool )
```

Allocate a pool that can hold up to `max` sprites.

#### SPOOL-FREE

```
( pool -- )
```

Free the pool's internal array and descriptor.  Does **not** free
the sprites themselves.

---

### Pool Operations

#### SPOOL-ADD

```
( pool spr -- )
```

Add a sprite to the pool.  Silently drops if the pool is full.

#### SPOOL-REMOVE

```
( pool spr -- )
```

Remove a sprite from the pool.  Swaps with the last entry for
O(1) removal.  No-op if the sprite is not in the pool or the
pool is empty.

#### SPOOL-COUNT

```
( pool -- n )
```

Return the number of sprites currently in the pool.

#### SPOOL-TICK-ALL

```
( pool -- )
```

Call `SPR-TICK` on every sprite in the pool.

---

### Pool Rendering

#### SPOOL-RENDER

```
( pool rgn vpx vpy -- )
```

Render all visible sprites in the pool to the screen.

1. Sorts sprites by z-order (insertion sort — fast for small N).
2. For each visible sprite, converts world position to screen
   coordinates by subtracting the viewport offset (vpx, vpy).
3. Clips to the region bounds.
4. Writes the sprite's cell via `SCR-SET`.

```forth
my-pool my-region  viewport-x viewport-y  SPOOL-RENDER
```

---

## Descriptor Layouts

### Sprite (64 bytes, 8 cells)

```
Offset  Size  Field
──────  ────  ──────────────
 +0      8   cell        Current display cell
 +8      8   x           Column (world coords)
+16      8   y           Row (world coords)
+24      8   z           Z-order (higher = on top)
+32      8   flags       SPR-F-VISIBLE | SPR-F-MULTI | SPR-F-ANIM
+40      8   anim-ptr    Address of frame table (0 if none)
+48      8   anim-info   Packed: count[15:0] rate[31:16] frame[47:32] ticks[63:48]
+56      8   user        User data
```

### Pool (24 bytes, 3 cells)

```
Offset  Size  Field
──────  ────  ──────────────
 +0      8   max    Maximum sprite count
 +8      8   count  Current sprite count
+16      8   array  Address of sprite-pointer array
```

---

## Flags

| Constant | Value | Description |
|----------|-------|-------------|
| `SPR-F-VISIBLE` | 1 | Sprite is visible |
| `SPR-F-MULTI` | 2 | Multi-cell sprite (reserved) |
| `SPR-F-ANIM` | 4 | Animation active |

---

## Quick Reference

### Sprite API

| Word | Stack | Description |
|------|-------|-------------|
| `SPR-NEW` | `( cell -- spr )` | Allocate sprite |
| `SPR-FREE` | `( spr -- )` | Free sprite |
| `SPR-POS!` | `( spr x y -- )` | Set position |
| `SPR-POS@` | `( spr -- x y )` | Get position |
| `SPR-MOVE` | `( spr dx dy -- )` | Relative move |
| `SPR-CELL!` | `( spr cell -- )` | Set cell |
| `SPR-CELL@` | `( spr -- cell )` | Get cell |
| `SPR-Z!` | `( spr z -- )` | Set z-order |
| `SPR-Z@` | `( spr -- z )` | Get z-order |
| `SPR-VISIBLE!` | `( spr -- )` | Show |
| `SPR-HIDDEN!` | `( spr -- )` | Hide |
| `SPR-VISIBLE?` | `( spr -- flag )` | Visible? |
| `SPR-ANIM!` | `( spr tbl count rate -- )` | Attach animation |
| `SPR-TICK` | `( spr -- )` | Advance animation |
| `SPR-USER!` | `( spr val -- )` | Set user data |
| `SPR-USER@` | `( spr -- val )` | Get user data |

### Pool API

| Word | Stack | Description |
|------|-------|-------------|
| `SPOOL-NEW` | `( max -- pool )` | Create pool |
| `SPOOL-FREE` | `( pool -- )` | Free pool |
| `SPOOL-ADD` | `( pool spr -- )` | Add sprite |
| `SPOOL-REMOVE` | `( pool spr -- )` | Remove sprite |
| `SPOOL-COUNT` | `( pool -- n )` | Sprite count |
| `SPOOL-TICK-ALL` | `( pool -- )` | Tick all animations |
| `SPOOL-RENDER` | `( pool rgn vpx vpy -- )` | Z-sorted render |

Guarded words (when `GUARDED` is enabled): `SPR-NEW`, `SPR-FREE`,
`SPOOL-NEW`, `SPOOL-FREE`, `SPOOL-ADD`, `SPOOL-REMOVE`,
`SPOOL-RENDER`.
