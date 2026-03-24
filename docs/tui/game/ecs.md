# akashic-tui-game-ecs — Entity-Component Store

Lightweight archetype-free ECS.  Entities are integer IDs (0-based)
with generation counters to detect stale references.  Components are
fixed-size byte arrays stored in parallel pools indexed by entity ID.
Supports up to 16 component types per ECS instance.

```forth
REQUIRE tui/game/ecs.f
```

`PROVIDED akashic-tui-game-ecs` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Component Registration](#component-registration)
- [Entity Lifecycle](#entity-lifecycle)
- [Component Access](#component-access)
- [Iteration](#iteration)
- [Queries](#queries)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### ECS-NEW

```
( max-ents -- ecs )
```

Allocate a new ECS instance supporting up to `max-ents` entities
(clamped to a minimum of 1).  Returns a 40-byte descriptor with
freshly allocated bitfields and generation arrays.

### ECS-FREE

```
( ecs -- )
```

Free all component data arrays, attached bitfields, generation
array, alive bitfield, component descriptor array, and the ECS
descriptor itself.

---

## Component Registration

### ECS-REG-COMP

```
( ecs size -- comp-id )
```

Register a new component type of `size` bytes per entity.
Allocates a data pool of `max-ents × size` bytes and an attached
bitfield.  Returns the component index (0-based, sequential).
ABORTs if 16 components are already registered.

---

## Entity Lifecycle

### ECS-SPAWN

```
( ecs -- eid )
```

Find the first unused entity slot, mark it alive, increment its
generation counter, and return the entity ID.  Returns -1 if all
slots are full.

### ECS-KILL

```
( ecs eid -- )
```

Mark entity `eid` as dead and clear its attached bit in every
registered component's bitfield.

### ECS-ALIVE?

```
( ecs eid -- flag )
```

Return TRUE if entity `eid` is currently alive.

---

## Component Access

### ECS-ATTACH

```
( ecs eid comp-id -- addr )
```

Mark entity `eid` as having component `comp-id` and return
the address of its component data slot.  The caller writes
component fields at offsets from this address.

### ECS-DETACH

```
( ecs eid comp-id -- )
```

Clear the attached bit for entity `eid` on component `comp-id`.
Does not zero the data slot.

### ECS-GET

```
( ecs eid comp-id -- addr | 0 )
```

If entity `eid` has component `comp-id` attached, return the
address of the data slot.  Otherwise return 0.

### ECS-HAS?

```
( ecs eid comp-id -- flag )
```

Return TRUE if entity `eid` has component `comp-id` attached.

---

## Iteration

### ECS-EACH

```
( ecs comp-id xt -- )
```

Call `xt` for every alive entity that has `comp-id` attached.
The callback signature is:

```
xt: ( eid comp-addr -- )
```

### ECS-EACH2

```
( ecs c1 c2 xt -- )
```

Call `xt` for every alive entity that has **both** `c1` and `c2`
attached.  The callback receives:

```
xt: ( eid c2-addr c1-addr -- )
```

> **Note:** addresses are pushed in reverse argument order — `c2`
> address first, then `c1`.

---

## Queries

### ECS-COUNT

```
( ecs -- n )
```

Return the number of currently alive entities.

### ECS-GEN

```
( ecs eid -- gen )
```

Return the generation counter for entity `eid`.  Incremented each
time the slot is respawned; useful for detecting stale references.

### ECS-MAX

```
( ecs -- max-ents )
```

Return the maximum entity capacity.

---

## Descriptor Layout

### ECS Descriptor (40 bytes, 5 cells)

| Offset | Field      | Description                           |
|--------|------------|---------------------------------------|
| +0     | max-ents   | Maximum entity slots                  |
| +8     | alive      | Bitfield array (1 bit per entity)     |
| +16    | gen        | Generation array (1 cell per entity)  |
| +24    | comp-descs | Component descriptor array (max 16)   |
| +32    | num-comps  | Number of registered components       |

### Component Descriptor (24 bytes, 3 cells)

| Offset | Field     | Description                            |
|--------|-----------|----------------------------------------|
| +0     | comp-size | Byte size of one component instance    |
| +8     | data      | Data array (max-ents × size bytes)     |
| +16    | attached  | Bitfield array (1 bit per entity)      |

---

## Quick Reference

| Word           | Stack Effect                     | Description              |
|----------------|----------------------------------|--------------------------|
| `ECS-NEW`      | `( max -- ecs )`                 | Create ECS               |
| `ECS-FREE`     | `( ecs -- )`                     | Destroy ECS              |
| `ECS-REG-COMP` | `( ecs size -- id )`             | Register component type  |
| `ECS-SPAWN`    | `( ecs -- eid )`                 | Spawn entity             |
| `ECS-KILL`     | `( ecs eid -- )`                 | Kill entity              |
| `ECS-ALIVE?`   | `( ecs eid -- ? )`               | Alive check              |
| `ECS-ATTACH`   | `( ecs eid cid -- addr )`        | Attach component         |
| `ECS-DETACH`   | `( ecs eid cid -- )`             | Detach component         |
| `ECS-GET`      | `( ecs eid cid -- addr\|0 )`    | Get component or 0       |
| `ECS-HAS?`     | `( ecs eid cid -- ? )`           | Has component?           |
| `ECS-EACH`     | `( ecs cid xt -- )`              | Iterate one component    |
| `ECS-EACH2`    | `( ecs c1 c2 xt -- )`           | Iterate two components   |
| `ECS-COUNT`    | `( ecs -- n )`                   | Count alive entities     |
| `ECS-GEN`      | `( ecs eid -- gen )`             | Get generation           |
| `ECS-MAX`      | `( ecs -- n )`                   | Get max capacity         |
