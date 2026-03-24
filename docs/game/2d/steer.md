# akashic-game-2d-steer — Steering Behaviors

High-level movement patterns that write to the C-VEL component.
Combine with `SYS-VELOCITY` for automatic position updates.
Integrates with collision-map pathfinding and ECS AI state.

```forth
REQUIRE game/2d/steer.f
```

`PROVIDED akashic-game-2d-steer` — safe to include multiple times.

---

## Table of Contents

- [Basic Behaviors](#basic-behaviors)
- [Path Following](#path-following)
- [Patrol](#patrol)
- [Configuration](#configuration)
- [Quick Reference](#quick-reference)

---

## Basic Behaviors

### STEER-SEEK

```
( eid ecs target-x target-y -- )
```

Set the entity's velocity toward (target-x, target-y).  Each
axis is set to -1, 0, or +1 (discrete signum).  If the entity
is already at the target, velocity is set to (0, 0).

### STEER-FLEE

```
( eid ecs threat-x threat-y -- )
```

Set velocity **away** from the threat position.  Opposite of
STEER-SEEK.

### STEER-WANDER

```
( eid ecs -- )
```

Set a random velocity using the built-in LCG.  Each axis is
independently set to -1, 0, or +1.  Seed the RNG with
`STEER-SEED!` for reproducible results.

---

## Path Following

### STEER-FOLLOW-PATH

```
( eid ecs path count -- )
```

Follow a waypoint path.  Finds the entity's current position
in the path and seeks toward the **next** waypoint.  If the
entity is at the last waypoint or not on the path, velocity is
set to (0, 0).

Path format: flat cell array of (x, y) pairs — compatible with
`ASTAR-FIND` output.

---

## Patrol

### STEER-PATROL

```
( eid ecs waypoints count -- )
```

Autonomous patrol between waypoints.  Uses the entity's C-AI
component (`C-AI.STATE` field) to track which waypoint the
entity is heading toward.

- If the entity is **at** the current waypoint, the state
  advances to the next waypoint (wrapping around to 0).
- The entity then seeks toward the current target waypoint.

Requires `STEER-BIND-AI` to be called first to register the
C-AI component ID.

---

## Configuration

### STEER-BIND-AI

```
( c-ai -- )
```

Register the component ID for C-AI so that `STEER-PATROL` can
read and write the `C-AI.STATE` field.

### STEER-SEED!

```
( n -- )
```

Seed the internal LCG used by `STEER-WANDER`.

---

## Quick Reference

| Word                | Stack Effect                            | Description             |
|---------------------|-----------------------------------------|-------------------------|
| `STEER-SEEK`        | `( eid ecs tx ty -- )`                  | Seek target             |
| `STEER-FLEE`        | `( eid ecs tx ty -- )`                  | Flee from threat        |
| `STEER-WANDER`      | `( eid ecs -- )`                        | Random movement         |
| `STEER-FOLLOW-PATH` | `( eid ecs path count -- )`             | Follow waypoint path    |
| `STEER-PATROL`      | `( eid ecs wps count -- )`              | Auto-patrol waypoints   |
| `STEER-BIND-AI`     | `( c-ai -- )`                           | Register AI component   |
| `STEER-SEED!`       | `( n -- )`                              | Seed wander RNG         |
