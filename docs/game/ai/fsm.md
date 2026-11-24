# akashic-game-ai-fsm — Finite State Machines

A state machine gives an entity a mood: a current state with callbacks
for entering it, each tick in it and leaving it, and guarded transitions
that move it to another state. A machine is a shared definition, its
states and transitions, and each entity keeps its current state in a cell
of its own, so one definition serves any number of entities. States have
names, which a game can show or log.

```forth
REQUIRE game/ai/fsm.f
```

`PROVIDED akashic-game-ai-fsm` — safe to include multiple times.

---

## Table of Contents

- [Definitions](#definitions)
- [Running a Machine](#running-a-machine)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Definitions

### FSM-NEW

```
( -- fsm )
```

An empty definition. Its tables of states and transitions grow as they
are defined.

### FSM-STATE

```
( fsm name-a name-u on-enter on-tick on-leave -- state-id )
```

Define a state and return its id, from 0 in the order of definition.
Each callback may be 0:

| Callback   | Effect                |
|------------|-----------------------|
| on-enter   | `( eid ecs -- )`      |
| on-tick    | `( eid ecs dt -- )`   |
| on-leave   | `( eid ecs -- )`      |

The name's characters must outlive the definition.

### FSM-TRANSITION

```
( fsm from-id to-id guard-xt -- )
```

A transition from `from-id` to `to-id` that fires when
`guard-xt ( eid ecs -- flag )` returns true. Transitions from one state
are tried in the order they were defined.

### FSM-NAME / FSM-STATES

```
( fsm state-id -- name-a name-u )
( fsm -- n )
```

A state's name, and the number of states.

### FSM-FREE

```
( fsm -- )
```

Free the definition. The entities' state cells belong to their owners.

---

## Running a Machine

An entity's current state lives in a cell its owner provides, usually a
field of the entity's AI component, such as `C-AI.STATE`. A cell of -1
marks a machine not started.

### FSM-START

```
( fsm cell eid ecs state-id -- )
```

Put the entity's machine into `state-id`, storing it at `cell`, and call
that state's on-enter with `eid` and `ecs`.

### FSM-TICK

```
( fsm cell eid ecs dt -- )
```

Try the transitions from the entity's current state in order; the first
whose guard passes fires, calling the old state's on-leave and the new
state's on-enter. Then call the current state's on-tick with `dt`. A
machine not started does nothing. A tick keeps its place on the stacks,
so a guard or a callback may tick another machine.

---

## Descriptor Layout

### FSM (48 bytes, 6 cells)

| Offset | Field       | Description                     |
|--------|-------------|---------------------------------|
| +0     | states      | Array of state descriptors      |
| +8     | n-states    | Number of defined states        |
| +16    | max-states  | Capacity                        |
| +24    | transitions | Array of transition descriptors |
| +32    | n-trans     | Number of defined transitions   |
| +40    | max-trans   | Capacity                        |

### State (40 bytes)

| Offset | Field    | Description              |
|--------|----------|--------------------------|
| +0     | name-a   | Name string address      |
| +8     | name-u   | Name string length       |
| +16    | on-enter | xt or 0                  |
| +24    | on-tick  | xt or 0                  |
| +32    | on-leave | xt or 0                  |

### Transition (24 bytes)

| Offset | Field    | Description              |
|--------|----------|--------------------------|
| +0     | from-id  | Source state id          |
| +8     | to-id    | Target state id          |
| +16    | guard-xt | `( eid ecs -- flag )`    |

---

## Quick Reference

| Word             | Stack Effect                                              | Description          |
|------------------|-----------------------------------------------------------|----------------------|
| `FSM-NEW`        | `( -- fsm )`                                              | Empty definition     |
| `FSM-STATE`      | `( fsm name-a name-u enter tick leave -- id )`            | Define a state       |
| `FSM-TRANSITION` | `( fsm from to guard -- )`                                | Define a transition  |
| `FSM-START`      | `( fsm cell eid ecs id -- )`                              | Start an entity      |
| `FSM-TICK`       | `( fsm cell eid ecs dt -- )`                              | Tick an entity       |
| `FSM-NAME`       | `( fsm id -- name-a name-u )`                             | A state's name       |
| `FSM-STATES`     | `( fsm -- n )`                                            | Number of states     |
| `FSM-FREE`       | `( fsm -- )`                                              | Free the definition  |
