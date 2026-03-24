# akashic-game-2d-pathfind — Grid-Based A* Pathfinding

A* pathfinding over collision maps.  Returns a path as a
Forth-allocated array of (x, y) cell pairs.  Supports 4-connected
(Manhattan) and 8-connected (diagonal) search, configurable
heuristic, and budget limits.

```forth
REQUIRE game/2d/pathfind.f
```

`PROVIDED akashic-game-2d-pathfind` — safe to include multiple times.

---

## Table of Contents

- [Path Finding](#path-finding)
- [Configuration](#configuration)
- [Path Format](#path-format)
- [Quick Reference](#quick-reference)

---

## Path Finding

### ASTAR-FIND

```
( cmap x0 y0 x1 y1 -- path count | 0 0 )
```

Find a path from (x0, y0) to (x1, y1) on the given collision map.
Returns a freshly allocated path array and its waypoint count on
success.  Returns `0 0` if no path exists or the budget is exhausted.

Tiles with non-zero collision values are treated as impassable.

Free the path with `ASTAR-FREE` when done.

### ASTAR-FREE

```
( path -- )
```

Free a path previously returned by `ASTAR-FIND`.

---

## Configuration

### ASTAR-DIAGONAL!

```
( flag -- )
```

Enable or disable 8-connected (diagonal) search.  When TRUE,
the algorithm considers all 8 neighbours.  Default: FALSE
(4-connected, cardinal directions only).

### ASTAR-BUDGET!

```
( n -- )
```

Set the maximum number of nodes to expand before giving up.
Default: 512.  Useful for limiting CPU time on large maps.

### ASTAR-HEURISTIC!

```
( xt -- )
```

Override the distance heuristic.  The default is Manhattan distance.
Custom heuristic signature:

```
( x0 y0 x1 y1 -- h )
```

---

## Path Format

The path is a flat cell array of (x, y) pairs:

```
path[0]   = x0    (start)
path[1]   = y0
path[2]   = x1    (next waypoint)
path[3]   = y1
  ...
path[(count-1)*2]     = xN   (goal)
path[(count-1)*2 + 1] = yN
```

Access helpers:

```forth
\ Get waypoint i from path
: PATH-X  ( path i -- x )  2* CELLS + @ ;
: PATH-Y  ( path i -- y )  2* 1+ CELLS + @ ;
```

The format is compatible with `STEER-FOLLOW-PATH`.

---

## Quick Reference

| Word               | Stack Effect                             | Description              |
|--------------------|------------------------------------------|--------------------------|
| `ASTAR-FIND`       | `( cmap x0 y0 x1 y1 -- path cnt \| 0 0 )` | Find path via A*      |
| `ASTAR-FREE`       | `( path -- )`                            | Free path array          |
| `ASTAR-DIAGONAL!`  | `( flag -- )`                            | Enable diagonal search   |
| `ASTAR-BUDGET!`    | `( n -- )`                               | Set node budget          |
| `ASTAR-HEURISTIC!` | `( xt -- )`                              | Custom heuristic         |
