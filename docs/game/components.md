# akashic-game-components — Common ECS Components

Pre-defined component types for common game patterns.  Each component
is a fixed-size struct accessed via field offset constants.  Register
with `ECS-REG-COMP`, attach with `ECS-ATTACH`, then read/write fields
at the returned address.

```forth
REQUIRE game/components.f
```

`PROVIDED akashic-game-components` — safe to include multiple times.

---

## Table of Contents

- [Components](#components)
- [Bulk Registration](#bulk-registration)
- [Usage Pattern](#usage-pattern)
- [Quick Reference](#quick-reference)

---

## Components

### C-POS — Position (16 bytes)

| Field    | Offset | Description       |
|----------|--------|-------------------|
| C-POS.X  | +0     | X coordinate      |
| C-POS.Y  | +8     | Y coordinate      |

Size constant: `C-POS-SZ` = 16.

### C-VEL — Velocity (16 bytes)

| Field    | Offset | Description       |
|----------|--------|-------------------|
| C-VEL.DX | +0     | X velocity        |
| C-VEL.DY | +8     | Y velocity        |

Size constant: `C-VEL-SZ` = 16.

### C-SPR — Sprite (8 bytes)

| Field     | Offset | Description           |
|-----------|--------|-----------------------|
| C-SPR.TILE| +0     | Atlas tile or handle  |

Size constant: `C-SPR-SZ` = 8.

### C-HP — Health (16 bytes)

| Field   | Offset | Description    |
|---------|--------|----------------|
| C-HP.CUR| +0     | Current HP     |
| C-HP.MAX| +8     | Maximum HP     |

Size constant: `C-HP-SZ` = 16.

### C-COL — Collider (8 bytes)

| Field    | Offset | Description           |
|----------|--------|-----------------------|
| C-COL.MASK| +0    | Collision layer mask  |

Size constant: `C-COL-SZ` = 8.

### C-TMR — Timer (16 bytes)

| Field      | Offset | Description              |
|------------|--------|--------------------------|
| C-TMR.TICKS| +0     | Ticks remaining          |
| C-TMR.XT   | +8     | Callback XT (or 0)       |

Size constant: `C-TMR-SZ` = 16.

### C-TAG — Tag (8 bytes)

| Field    | Offset | Description          |
|----------|--------|----------------------|
| C-TAG.VAL| +0     | User-defined integer |

Size constant: `C-TAG-SZ` = 8.

### C-AI — AI State (8 bytes)

| Field     | Offset | Description    |
|-----------|--------|----------------|
| C-AI.STATE| +0     | FSM state      |

Size constant: `C-AI-SZ` = 8.

---

## Bulk Registration

### COMPS-REG-ALL

```
( ecs -- c-pos c-vel c-spr c-hp c-col c-tmr c-tag c-ai )
```

Register all 8 standard component types on `ecs` and push their
component IDs (0–7) in order.

---

## Usage Pattern

```forth
\ Create ECS and register components
64 ECS-NEW CONSTANT my-ecs
my-ecs COMPS-REG-ALL
CONSTANT c-ai  CONSTANT c-tag  CONSTANT c-tmr
CONSTANT c-col  CONSTANT c-hp  CONSTANT c-spr
CONSTANT c-vel  CONSTANT c-pos

\ Spawn entity, attach position
my-ecs ECS-SPAWN CONSTANT e0
my-ecs e0 c-pos ECS-ATTACH CONSTANT e0-pos
42 e0-pos C-POS.X + !
99 e0-pos C-POS.Y + !

\ Read back
e0-pos C-POS.X + @   \ → 42
```

---

## Quick Reference

| Constant     | Value | Description          |
|--------------|-------|----------------------|
| `C-POS-SZ`   | 16   | Position byte size   |
| `C-VEL-SZ`   | 16   | Velocity byte size   |
| `C-SPR-SZ`   |  8   | Sprite byte size     |
| `C-HP-SZ`    | 16   | Health byte size     |
| `C-COL-SZ`   |  8   | Collider byte size   |
| `C-TMR-SZ`   | 16   | Timer byte size      |
| `C-TAG-SZ`   |  8   | Tag byte size        |
| `C-AI-SZ`    |  8   | AI byte size         |
