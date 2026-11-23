# akashic-game-ai-btree — Behaviour Trees

Behaviour trees order an entity's choices: each node, when run, returns
SUCCESS, FAILURE or RUNNING, and composites and decorators combine their
children's results. One tree serves any number of entities. What a node
remembers between runs for one entity, a repeat's count and a cooldown's
countdown and last result, lives in that entity's state block, so the tree
itself never changes after it is built.

```forth
REQUIRE game/ai/btree.f
```

`PROVIDED akashic-game-ai-btree` — safe to include multiple times.

---

## Table of Contents

- [Statuses](#statuses)
- [Leaves](#leaves)
- [Composites](#composites)
- [Decorators](#decorators)
- [State Blocks](#state-blocks)
- [Running and Freeing](#running-and-freeing)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Statuses

| Constant     | Value | Meaning                          |
|--------------|-------|----------------------------------|
| `BT-SUCCESS` | 0     | The node did what it does        |
| `BT-FAILURE` | 1     | The node could not               |
| `BT-RUNNING` | 2     | The node needs further runs      |

---

## Leaves

### BT-ACTION

```
( xt -- node )
```

A leaf that calls `xt ( eid ecs -- status )` and returns its status.

### BT-CONDITION

```
( xt -- node )
```

A leaf that calls `xt ( eid ecs -- flag )` and returns SUCCESS for a true
flag and FAILURE for a false one.

---

## Composites

A composite takes the address of an array of `count` child nodes and copies
it, so the caller's array (a `CREATE`d table, say) can be reused. A
composite of no children needs no array.

### BT-SEQUENCE

```
( children count -- node )
```

Runs the children in order. The first status other than SUCCESS is the
sequence's; when every child succeeds, the sequence succeeds.

### BT-SELECTOR

```
( children count -- node )
```

Runs the children in order. The first status other than FAILURE is the
selector's; when every child fails, the selector fails.

### BT-PARALLEL

```
( children count threshold -- node )
```

Runs every child each time. It succeeds when at least `threshold` children
succeed, fails when more than `count - threshold` fail, and otherwise runs.

---

## Decorators

### BT-INVERT

```
( child -- node )
```

Swaps the child's SUCCESS and FAILURE; RUNNING passes through.

### BT-REPEAT

```
( child n -- node )
```

Counts the child's successes and returns RUNNING until the `n`th, when it
returns SUCCESS and starts counting again. A failure returns FAILURE and
starts the count again. With `n` = 0 it returns RUNNING forever. It owns one
cell of state.

### BT-COOLDOWN

```
( child ticks -- node )
```

After the child returns SUCCESS or FAILURE, returns that result for the
next `ticks` runs without running the child. It owns two cells of state.

---

## State Blocks

### BT-STATE-CELLS

```
( root -- n )
```

The cells of state one entity needs to run the tree rooted at `root`. Each
subtree owns a fixed run of cells, laid out in the order the nodes appear
depth first, so the count and every node's place are settled when the tree
is built.

An entity's block starts zeroed. A convenient home for it is a component of
`n` cells registered with `ECS-REG-COMP`, since `ECS-ATTACH` zeroes the
component it attaches. A tree whose count is 0 needs no block and runs with
a state of 0.

---

## Running and Freeing

### BT-RUN

```
( node state eid ecs -- status )
```

Run the tree at `node` for entity `eid` of `ecs`, with `state` the entity's
block. `eid` and `ecs` pass unchanged to every leaf. `BT-RUN` keeps its
loop state on the data and return stacks, so composites nest to any depth
and a leaf may run another tree.

### BT-FREE

```
( node -- )
```

Free `node`, its children array and every node below it, each once. A node
belongs to one parent, since freeing the parent frees it. State blocks
belong to their entities and stay.

---

## Descriptor Layout

### Node (40 bytes, 5 cells)

| Offset | Field   | Description                                           |
|--------|---------|-------------------------------------------------------|
| +0     | type    | `BT-NODE-ACTION` … `BT-NODE-COOLDOWN` (0 to 7)        |
| +8     | data1   | xt (leaf), children array (composite), child          |
| +16    | data2   | count (composite), `n` (repeat), ticks (cooldown)     |
| +24    | data3   | threshold (parallel)                                  |
| +32    | cells   | State cells of the subtree, its own and below         |

A repeat's cell holds its completions so far; a cooldown's two cells hold
the runs left to skip and the result it returns meanwhile. A node's own
cells come before its child's.

---

## Quick Reference

| Word             | Stack Effect                               | Description              |
|------------------|--------------------------------------------|--------------------------|
| `BT-ACTION`      | `( xt -- node )`                           | Action leaf              |
| `BT-CONDITION`   | `( xt -- node )`                           | Condition leaf           |
| `BT-SEQUENCE`    | `( children count -- node )`               | All must succeed         |
| `BT-SELECTOR`    | `( children count -- node )`               | First that succeeds      |
| `BT-PARALLEL`    | `( children count threshold -- node )`     | Run all, count successes |
| `BT-INVERT`      | `( child -- node )`                        | Swap success and failure |
| `BT-REPEAT`      | `( child n -- node )`                      | Repeat `n` successes     |
| `BT-COOLDOWN`    | `( child ticks -- node )`                  | Rest after finishing     |
| `BT-STATE-CELLS` | `( root -- n )`                            | State an entity needs    |
| `BT-RUN`         | `( node state eid ecs -- status )`         | Run for one entity       |
| `BT-FREE`        | `( node -- )`                              | Free the tree            |
