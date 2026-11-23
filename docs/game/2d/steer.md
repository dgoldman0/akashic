# akashic-game-2d-steer — Steering Behaviors

Movement patterns that set an entity's velocity to one step. Each
behaviour writes a dx and a dy of -1, 0 or +1 into the entity's velocity
component, toward or away from its target; moving the entity is the
caller's, as with `SYS-VELOCITY` or `TPHYS-MOVE`. The behaviours suit
turn-based games, where a creature takes one tile a turn, and grid games
that move every entity one tile at a time.

A steering context holds the components the behaviours read and write
and a seeded generator for wandering, so two worlds, or two kinds of
creature, steer independently and a wander replays from its seed.

```forth
REQUIRE game/2d/steer.f
```

`PROVIDED akashic-game-2d-steer` — safe to include multiple times.

---

## Table of Contents

- [Contexts](#contexts)
- [Basic Behaviors](#basic-behaviors)
- [Path Following](#path-following)
- [Patrol](#patrol)
- [Quick Reference](#quick-reference)

---

## Contexts

### STEER-NEW

```
( c-pos c-vel c-ai seed -- steer )
```

A steering context over the position, velocity and AI components of one
ECS layout, with its wander generator seeded by `seed`. Every behaviour
takes the context first. An entity without a position component is left
alone, and one without a velocity component is read but not written.

### STEER-FREE

```
( steer -- )
```

Free the context.

---

## Basic Behaviors

### STEER-SEEK

```
( steer eid ecs target-x target-y -- )
```

One step toward (target-x, target-y): each axis is set to -1, 0, or
+1, the sign of the difference. At the target, velocity is (0, 0).

### STEER-FLEE

```
( steer eid ecs threat-x threat-y -- )
```

One step **away** from the threat position.

### STEER-WANDER

```
( steer eid ecs -- )
```

A random step from the context's generator: each axis independently
-1, 0, or +1. Two contexts seeded alike produce the same steps.

---

## Path Following

### STEER-FOLLOW-PATH

```
( steer eid ecs path count -- )
```

Find the entity's position on the path and step toward the **next**
tile. At the path's last tile, or off the path, velocity is (0, 0).

Path format: flat cell array of (x, y) pairs, as `ASTAR-PATH` gives
it.

---

## Patrol

### STEER-PATROL

```
( steer eid ecs waypoints count -- )
```

Patrol a loop of waypoints, keeping the index of the waypoint ahead in
`C-AI.STATE` of the entity's AI component, the context's `c-ai`.

- If the entity is **at** that waypoint, the index advances to the
  next waypoint, wrapping around to 0.
- The entity then steps toward the waypoint ahead.

An entity without an AI component, or a loop of no waypoints, gets
velocity (0, 0).

---

## Quick Reference

| Word                | Stack Effect                              | Description             |
|---------------------|-------------------------------------------|-------------------------|
| `STEER-NEW`         | `( c-pos c-vel c-ai seed -- steer )`      | Steering context        |
| `STEER-FREE`        | `( steer -- )`                            | Free it                 |
| `STEER-SEEK`        | `( steer eid ecs tx ty -- )`              | Step toward a target    |
| `STEER-FLEE`        | `( steer eid ecs tx ty -- )`              | Step away from a threat |
| `STEER-WANDER`      | `( steer eid ecs -- )`                    | Random step             |
| `STEER-FOLLOW-PATH` | `( steer eid ecs path count -- )`         | Follow a path           |
| `STEER-PATROL`      | `( steer eid ecs wps count -- )`          | Patrol waypoints        |
