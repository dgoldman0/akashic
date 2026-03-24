# akashic-game-2d-tile-physics — Discrete Tile-Based Movement

Discrete tile-based movement engine with wall sliding, optional
gravity, one-way platforms, and per-collision callbacks.  Works
on the collision map from `game/2d/collide.f`.

```forth
REQUIRE game/2d/tile-physics.f
```

`PROVIDED akashic-game-2d-tile-physics` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Configuration](#configuration)
- [Movement](#movement)
- [Queries](#queries)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### TPHYS-NEW

```
( cmap -- phys )
```

Allocate a physics descriptor (40 bytes) bound to the given collision
map.  Gravity is zero (top-down mode), callback is disabled,
one-way platforms are off.

### TPHYS-FREE

```
( phys -- )
```

Free the physics descriptor.

---

## Configuration

### TPHYS-GRAVITY!

```
( phys gx gy -- )
```

Set per-tick gravity.  For a side-scroller, use `phys 0 1 TPHYS-GRAVITY!`.
For top-down, leave at `0 0` (the default).

### TPHYS-ONE-WAY!

```
( phys tile-val -- )
```

Register a tile value as a one-way platform.  Entities moving
**downward** (positive dy) into a one-way tile are blocked;
upward and horizontal movement passes through.  Set to 0 to
disable one-way platforms.

### TPHYS-ON-COLLIDE

```
( phys xt -- )
```

Register a collision callback.  The callback is called whenever
movement is blocked by a solid tile:

```
xt signature: ( eid tile-x tile-y tile-val -- )
```

Set XT to 0 to disable callbacks.

---

## Movement

### TPHYS-MOVE

```
( phys eid ecs dx dy -- rx ry )
```

Attempt to move entity `eid` by (dx, dy) tiles.  Movement is
split into separate X and Y steps.  If X is blocked, the entity
slides on Y (and vice versa).  Returns the entity's final
position (rx, ry).  The entity's C-POS component is updated
in place.

### TPHYS-APPLY-GRAV

```
( phys eid ecs -- rx ry )
```

Apply one tick of gravity to the entity.  Equivalent to calling
`TPHYS-MOVE` with the configured gravity vector.

---

## Queries

### TPHYS-GROUNDED?

```
( phys eid ecs -- flag )
```

Returns TRUE if the tile directly below the entity is solid
(non-zero in the collision map).

---

## Descriptor Layout

| Offset | Size | Field       | Description                    |
|--------|------|-------------|--------------------------------|
| +0     | 8    | cmap        | Collision map pointer          |
| +8     | 8    | grav-x      | Gravity X per tick             |
| +16    | 8    | grav-y      | Gravity Y per tick             |
| +24    | 8    | on-collide  | Callback XT (0 = none)         |
| +32    | 8    | one-way     | One-way tile value (0 = off)   |

Total: 40 bytes.

---

## Quick Reference

| Word               | Stack Effect                        | Description               |
|--------------------|-------------------------------------|---------------------------|
| `TPHYS-NEW`        | `( cmap -- phys )`                  | Create physics descriptor |
| `TPHYS-FREE`       | `( phys -- )`                       | Free descriptor           |
| `TPHYS-GRAVITY!`   | `( phys gx gy -- )`                | Set gravity vector        |
| `TPHYS-ONE-WAY!`   | `( phys tile-val -- )`             | Set one-way tile value    |
| `TPHYS-ON-COLLIDE` | `( phys xt -- )`                   | Set collision callback    |
| `TPHYS-MOVE`       | `( phys eid ecs dx dy -- rx ry )`  | Move with wall sliding    |
| `TPHYS-GROUNDED?`  | `( phys eid ecs -- flag )`         | Check ground below        |
| `TPHYS-APPLY-GRAV` | `( phys eid ecs -- rx ry )`        | Apply gravity             |
