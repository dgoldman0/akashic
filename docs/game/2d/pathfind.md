# akashic-game-2d-pathfind — Grid-Based A* Pathfinding

A* search and distance fields over a collision map. A search is made once
for its map and reused: a run allocates nothing once the search's open set
and path buffer have grown to its size, and starting a run costs the same
whatever the map's size. Terrain costs come from a table indexed by a
tile's collision value, and every path found is a cheapest one.

```forth
REQUIRE game/2d/pathfind.f
```

`PROVIDED akashic-game-2d-pathfind` — safe to include multiple times.

---

## Table of Contents

- [Searches](#searches)
- [Steps and Terrain](#steps-and-terrain)
- [Running a Search](#running-a-search)
- [Distance Fields](#distance-fields)
- [How a Run Works](#how-a-run-works)
- [Costs](#costs)
- [Quick Reference](#quick-reference)

---

## Searches

### ASTAR-NEW

```
( cmap -- search )
```

Make a search for `cmap`, with a record of three cells for each tile.
The search reads the map's tiles directly, so the map must outlive it;
changing tiles between runs is fine.

### ASTAR-FREE

```
( search -- )
```

Free the search, its tile records, open set and path buffer.

---

## Steps and Terrain

### ASTAR-COST!

```
( search value cost -- )
```

Stepping onto a tile of collision value `value` costs `cost`, from 1 to
255; a cost of 0 makes such tiles impassable. By default value 0 costs 1
and every other value is impassable, so a plain collision map works as
it is.

### ASTAR-STEPS!

```
( search straight diagonal -- )
```

The weight of a straight step and of a diagonal step; a step costs its
tile's cost times its weight. A diagonal weight of 0, the default, allows
only straight steps, and a smaller nonzero diagonal is raised to the
straight weight.

| Weights  | Meaning |
|----------|---------|
| `1 0`    | Four directions (the default) |
| `1 1`    | Eight directions, every step one move |
| `5 7`, `10 14` | Eight directions, about as on the plane |

### ASTAR-CORNERS!

```
( search flag -- )
```

A diagonal step between two blocked neighbours is always refused, since
nothing fits between two walls that meet at a corner. With the flag set,
a diagonal step past any blocked neighbour is refused too, so paths keep
off wall corners.

### ASTAR-BUDGET!

```
( search n -- )
```

The expansions a run may make; 0, the default, sets no limit.

---

## Running a Search

### ASTAR-RUN

```
( search x0 y0 x1 y1 -- status )
```

Find a cheapest path from `(x0, y0)` to `(x1, y1)`. The status tells
three outcomes apart:

| Status        | Meaning |
|---------------|---------|
| `ASTAR-FOUND` | A path is in the search's path buffer |
| `ASTAR-NONE`  | No path exists, as for a goal off the map or impassable |
| `ASTAR-SPENT` | The budget ran out first |

The start may stand on any tile, even an impassable one.

### ASTAR-PATH

```
( search -- addr count )
```

The last path found: `count` tiles from the start to the goal, as cell
pairs, `addr[i*2]` the x and `addr[i*2+1]` the y of tile `i`. The search
owns the buffer and reuses it on its next run; `count` is 0 after a run
that found nothing.

### ASTAR-PATH-COST / ASTAR-EXPANDED

```
( search -- cost )
( search -- n )
```

The last path's cost, and the expansions the latest run made.

---

## Distance Fields

A field gives every reachable tile its cost from the nearest of several
sources, in one pass, so any number of creatures chasing the same targets
share it: each takes its next step with `ASTAR-DOWNHILL`.

### ASTAR-FIELD

```
( sources count search -- status )
```

`sources` is an array of `count` cell pairs `(x y)`. A source may stand
on an impassable tile, as a target on a desk does; its neighbours are
reached from it. The status is `ASTAR-FOUND` when the field is whole,
`ASTAR-SPENT` when the budget stopped it, and `ASTAR-NONE` when no source
lies on the map.

### ASTAR-DIST

```
( search x y -- d | -1 )
```

The tile's cost from the latest run's start, or from the field's nearest
source, when that run settled it; -1 otherwise.

### ASTAR-DOWNHILL

```
( search x y -- nx ny true | false )
```

The neighbour that a legal step from `(x, y)` reaches and that lies
nearest the sources, if it lies nearer than `(x, y)`. Ties go to the first
in the order left, right, up, down, then the diagonals. A tile the field
did not reach takes any reached neighbour.

---

## How a Run Works

Each tile's record holds a stamp, its cost from the start and its parent.
A run advances the search's generation, and a stamp older than the
generation marks a tile untouched in this run, so a run never clears the
map. The open set is a binary heap that doubles when it fills; its key
packs f and g so that ties go to the larger g, which keeps a run across
open ground near the straight line. The heuristic is the octile distance,
or the Manhattan distance without diagonal steps, times the least
passable cost; it never overestimates, so the first path to the goal is a
cheapest one. A field whose steps all cost the same keeps its open set as
a queue, a breadth-first pass, since tiles then leave it in order of
distance.

The phase 3 suite checks every run, field and downhill step on 48 seeded
maps against a Dijkstra on the host (`local_testing/game_models.py`).

---

## Costs

Emulator cycles, one call each, after the first run sized the buffers;
Akashic `game-library`, 2026-11-23:

| Call | Cycles | Before (Appendix A) |
|---|---:|---:|
| 40×20, five-step path | 55,503 | 191,066 |
| 40×20, 54-step detour around a wall (320 expansions) | 2,911,561 | 6,119,379 |
| 64×64, five-step path | 59,722 | 611,052 |
| 64×64, 79-step path across open ground (78 expansions) | 1,256,514 | 17,660,202 |
| Field over a 24×12 board with shelves, three sources | 1,179,572 | — |
| The same field with diagonal steps of weight 1 | 3,413,290 | — |
| `ASTAR-DOWNHILL` | 9,551 | — |

Twenty rounds alternating a 40×20 and a 64×64 search leave `XMEM-HERE`
where the first round left it.

---

## Quick Reference

| Word              | Stack Effect                               | Description              |
|-------------------|--------------------------------------------|--------------------------|
| `ASTAR-NEW`       | `( cmap -- search )`                       | Make a search            |
| `ASTAR-FREE`      | `( search -- )`                            | Free it                  |
| `ASTAR-COST!`     | `( search value cost -- )`                 | Terrain cost             |
| `ASTAR-STEPS!`    | `( search straight diagonal -- )`          | Step weights             |
| `ASTAR-CORNERS!`  | `( search flag -- )`                       | Keep off corners         |
| `ASTAR-BUDGET!`   | `( search n -- )`                          | Expansions allowed       |
| `ASTAR-RUN`       | `( search x0 y0 x1 y1 -- status )`         | Find a cheapest path     |
| `ASTAR-PATH`      | `( search -- addr count )`                 | The path found           |
| `ASTAR-PATH-COST` | `( search -- cost )`                       | Its cost                 |
| `ASTAR-EXPANDED`  | `( search -- n )`                          | Expansions made          |
| `ASTAR-FIELD`     | `( sources count search -- status )`       | Distance field           |
| `ASTAR-DIST`      | `( search x y -- d \| -1 )`                | A tile's distance        |
| `ASTAR-DOWNHILL`  | `( search x y -- nx ny true \| false )`    | Next step toward sources |
