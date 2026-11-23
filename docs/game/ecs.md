# akashic-game-ecs — Entity-Component Store

Lightweight archetype-free ECS.  Entities are integer IDs (0-based)
with generation counters to detect stale references.  Components are
fixed-size byte arrays stored in parallel pools indexed by entity ID.
The component table grows as components register, so an ECS holds as
many kinds of component as its creator registers.

```forth
REQUIRE game/ecs.f
```

`PROVIDED akashic-game-ecs` — safe to include multiple times.

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
Allocates a zeroed data pool of `max-ents × size` bytes and an
attached bitfield, and grows the component table when it is full.
Returns the component index (0-based, sequential).  A component of
size 0 has no pool: it marks the entities it is attached to.

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
component fields at offsets from this address.  A component
attached anew starts zeroed, whatever an entity that held the
slot before left there; attaching one already attached returns
its data unchanged.

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

Each iteration keeps its ECS, descriptors, token and context on the
data stack, under the callback's arguments, so a callback may
iterate again, over the same ECS or another, and may kill the
entity it was given.  The context cell `ctx` reaches every call
unchanged, so a caller hands its state to the callback without a
global.

### ECS-EACH

```
( ecs comp-id xt ctx -- )
```

Call `xt` for every alive entity that has `comp-id` attached.
The callback signature is:

```
xt: ( eid comp-addr ctx -- )
```

### ECS-EACH2

```
( ecs c1 c2 xt ctx -- )
```

Call `xt` for every alive entity that has **both** `c1` and `c2`
attached.  The callback receives the two addresses in the
components' order:

```
xt: ( eid c1-addr c2-addr ctx -- )
```

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

### ECS Descriptor (48 bytes, 6 cells)

| Offset | Field      | Description                           |
|--------|------------|---------------------------------------|
| +0     | max-ents   | Maximum entity slots                  |
| +8     | alive      | Bitfield array (1 bit per entity)     |
| +16    | gen        | Generation array (1 cell per entity)  |
| +24    | comp-descs | Component descriptor array            |
| +32    | num-comps  | Number of registered components       |
| +40    | comp-cap   | Descriptors the array has room for    |

### Component Descriptor (24 bytes, 3 cells)

| Offset | Field     | Description                            |
|--------|-----------|----------------------------------------|
| +0     | comp-size | Byte size of one component instance    |
| +8     | data      | Data array (max-ents × size bytes), 0 for size 0 |
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
| `ECS-EACH`     | `( ecs cid xt ctx -- )`          | Iterate one component    |
| `ECS-EACH2`    | `( ecs c1 c2 xt ctx -- )`        | Iterate two components   |
| `ECS-COUNT`    | `( ecs -- n )`                   | Count alive entities     |
| `ECS-GEN`      | `( ecs eid -- gen )`             | Get generation           |
| `ECS-MAX`      | `( ecs -- n )`                   | Get max capacity         |
