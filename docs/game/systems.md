# akashic-game-systems — System Runner

A registry of update systems executed in priority order each tick. Each
system is an XT that receives `( runner dt -- )` and reaches its ECS, its
components and the caller's state through the runner. Systems run in
priority order, low first, and among equal priorities in the order they
were added. The runner holds the component ids its built-in systems use
and a context cell for the caller's own systems, so two worlds with
different component layouts each have a runner of their own. Includes
three built-in systems: velocity, timer, and cull-dead.

```forth
REQUIRE game/systems.f
```

`PROVIDED akashic-game-systems` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Bindings and Context](#bindings-and-context)
- [Adding Systems](#adding-systems)
- [Tick](#tick)
- [Enable / Disable / Count](#enable--disable--count)
- [Built-in Systems](#built-in-systems)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### SYSRUN-NEW

```
( ecs -- runner )
```

Allocate a runner bound to `ecs`, with room for eight systems; the table
grows as systems are added. The built-ins' components start unbound.

### SYSRUN-FREE

```
( runner -- )
```

Free the entry array and the runner descriptor.

---

## Bindings and Context

### SYSRUN-BIND

```
( runner c-pos c-vel c-hp c-tmr -- )
```

The component ids the built-in systems read: position and velocity for
`SYS-VELOCITY`, health for `SYS-CULL-DEAD`, timer for `SYS-TIMER`. Pass
-1 to leave one unbound; a built-in system whose component is unbound
aborts when it runs.

### SYSRUN-ECS

```
( runner -- ecs )
```

The runner's ECS, for a system to iterate.

### SYSRUN-CTX! / SYSRUN-CTX

```
( runner ctx -- )
( runner -- ctx )
```

A context cell the caller sets, such as its game's state, which its own
systems read from the runner.

---

## Adding Systems

### SYSRUN-ADD

```
( runner xt priority -- handle )
```

Register system `xt ( runner dt -- )` with sort key `priority` (lower
runs first), after every system of lower or equal priority. Enabled by
default. Returns a handle that names the system for as long as the
runner lives, whatever later additions do to its place.

---

## Tick

### SYSRUN-TICK

```
( runner dt -- )
```

Execute all enabled systems in priority order, passing each
`( runner dt -- )`. The tick keeps the runner, the step and its place
on the stacks, so a system may tick another runner. Add systems outside
a tick.

---

## Enable / Disable / Count

### SYSRUN-ENABLE / SYSRUN-DISABLE

```
( runner handle -- )
```

Enable, or disable so `SYSRUN-TICK` skips it, the system with that
handle. An unknown handle aborts.

### SYSRUN-COUNT

```
( runner -- n )
```

Return the number of registered systems.

---

## Built-in Systems

All built-in systems have the signature `( runner dt -- )`. Each reads
its components from the runner and hands its step, or its ECS, to its
per-entity word as the iteration's context, so the systems keep no state
between calls.

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

### Runner Descriptor (80 bytes, 10 cells)

| Offset | Field    | Description                          |
|--------|----------|--------------------------------------|
| +0     | ecs      | Bound ECS instance pointer           |
| +8     | entries  | Array of system entries              |
| +16    | count    | Number of registered systems         |
| +24    | cap      | Entries the array has room for       |
| +32    | next     | The handle the next system gets      |
| +40    | c-pos    | Position component id, -1 unbound    |
| +48    | c-vel    | Velocity component id, -1 unbound    |
| +56    | c-hp     | Health component id, -1 unbound      |
| +64    | c-tmr    | Timer component id, -1 unbound       |
| +72    | ctx      | The caller's context cell            |

### System Entry (32 bytes, 4 cells)

| Offset | Field    | Description                  |
|--------|----------|------------------------------|
| +0     | xt       | System execution token       |
| +8     | priority | Sort key (lower = earlier)   |
| +16    | enabled  | Flag (0 = skip)              |
| +24    | handle   | The system's handle          |

---

## Quick Reference

| Word             | Stack Effect                             | Description             |
|------------------|------------------------------------------|-------------------------|
| `SYSRUN-NEW`     | `( ecs -- runner )`                      | Create runner           |
| `SYSRUN-FREE`    | `( runner -- )`                          | Destroy runner          |
| `SYSRUN-BIND`    | `( runner c-pos c-vel c-hp c-tmr -- )`   | Built-ins' components   |
| `SYSRUN-ECS`     | `( runner -- ecs )`                      | The runner's ECS        |
| `SYSRUN-CTX!`    | `( runner ctx -- )`                      | Set the context         |
| `SYSRUN-CTX`     | `( runner -- ctx )`                      | Read the context        |
| `SYSRUN-ADD`     | `( runner xt pri -- handle )`            | Add system              |
| `SYSRUN-TICK`    | `( runner dt -- )`                       | Run one tick            |
| `SYSRUN-ENABLE`  | `( runner handle -- )`                   | Enable system           |
| `SYSRUN-DISABLE` | `( runner handle -- )`                   | Disable system          |
| `SYSRUN-COUNT`   | `( runner -- n )`                        | Count systems           |
| `SYS-VELOCITY`   | `( runner dt -- )`                       | Built-in: move          |
| `SYS-TIMER`      | `( runner dt -- )`                       | Built-in: timers        |
| `SYS-CULL-DEAD`  | `( runner dt -- )`                       | Built-in: cull          |
