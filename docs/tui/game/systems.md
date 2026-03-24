# akashic-tui-game-systems — System Runner

A registry of update systems executed in priority order each tick.
Each system is an XT that receives `( ecs dt -- )` and operates on
the ECS.  Systems are sorted by priority (low runs first).  Includes
three built-in systems: velocity, timer, and cull-dead.

```forth
REQUIRE tui/game/systems.f
```

`PROVIDED akashic-tui-game-systems` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Adding Systems](#adding-systems)
- [Tick](#tick)
- [Enable / Disable / Count](#enable--disable--count)
- [Component Binding](#component-binding)
- [Built-in Systems](#built-in-systems)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### SYSRUN-NEW

```
( ecs -- runner )
```

Allocate a system runner bound to `ecs`.  Allocates a 32-byte
descriptor and an entry array (max 16 systems × 24 bytes each).

### SYSRUN-FREE

```
( runner -- )
```

Free the entry array and the runner descriptor.

---

## Adding Systems

### SYSRUN-ADD

```
( runner xt priority -- )
```

Register system `xt` with sort key `priority` (lower runs first).
The system is inserted in sorted order via bubble-sort insertion.
Enabled by default.  ABORTs if 16 systems are already registered.

---

## Tick

### SYSRUN-TICK

```
( runner dt -- )
```

Execute all enabled systems in priority order, passing each
`( ecs dt -- )`.

---

## Enable / Disable / Count

### SYSRUN-ENABLE

```
( runner idx -- )
```

Enable the system at index `idx` (0-based, in sorted order).

### SYSRUN-DISABLE

```
( runner idx -- )
```

Disable the system at index `idx` so `SYSRUN-TICK` skips it.

### SYSRUN-COUNT

```
( runner -- n )
```

Return the number of registered systems.

---

## Component Binding

The built-in systems need to know which ECS component IDs
correspond to position, velocity, health, and timer.  Store
the IDs in these variables before using built-in systems:

| Variable     | Used by        |
|--------------|----------------|
| `SYS-C-POS`  | SYS-VELOCITY  |
| `SYS-C-VEL`  | SYS-VELOCITY  |
| `SYS-C-HP`   | SYS-CULL-DEAD |
| `SYS-C-TMR`  | SYS-TIMER     |

### SYS-BIND-COMPS

```
( c-pos c-vel c-hp c-tmr -- )
```

Store all four component IDs in one call.

---

## Built-in Systems

All built-in systems have the signature `( ecs dt -- )`.

### SYS-VELOCITY

For every entity with both position and velocity, update
position: `x += dx * dt`, `y += dy * dt`.

### SYS-TIMER

For every entity with a timer component, decrement ticks by `dt`.
When ticks reach zero, call the callback XT stored in `C-TMR.XT`
with `( eid -- )` (if nonzero).

### SYS-CULL-DEAD

For every entity with a health component whose `C-HP.CUR ≤ 0`,
call `ECS-KILL` to remove it.

---

## Descriptor Layout

### Runner Descriptor (32 bytes, 4 cells)

| Offset | Field    | Description                         |
|--------|----------|-------------------------------------|
| +0     | ecs      | Bound ECS instance pointer          |
| +8     | entries  | Array of system entries (max 16)    |
| +16    | count    | Number of registered systems        |
| +24    | reserved |                                     |

### System Entry (24 bytes, 3 cells)

| Offset | Field   | Description                  |
|--------|---------|------------------------------|
| +0     | xt      | System execution token       |
| +8     | priority| Sort key (lower = earlier)   |
| +16    | enabled | Flag (0 = skip)              |

---

## Quick Reference

| Word             | Stack Effect              | Description             |
|------------------|---------------------------|-------------------------|
| `SYSRUN-NEW`     | `( ecs -- runner )`       | Create runner           |
| `SYSRUN-FREE`    | `( runner -- )`           | Destroy runner          |
| `SYSRUN-ADD`     | `( runner xt pri -- )`    | Add system              |
| `SYSRUN-TICK`    | `( runner dt -- )`        | Run one tick            |
| `SYSRUN-ENABLE`  | `( runner idx -- )`       | Enable system           |
| `SYSRUN-DISABLE` | `( runner idx -- )`       | Disable system          |
| `SYSRUN-COUNT`   | `( runner -- n )`         | Count systems           |
| `SYS-VELOCITY`   | `( ecs dt -- )`           | Built-in: move          |
| `SYS-TIMER`      | `( ecs dt -- )`           | Built-in: timers        |
| `SYS-CULL-DEAD`  | `( ecs dt -- )`           | Built-in: cull dead     |
| `SYS-BIND-COMPS` | `( pos vel hp tmr -- )`   | Bind component IDs      |
