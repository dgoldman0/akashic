# akashic-game-2d-fog — Fog of War

A per-tile visibility layer. Each tile is unseen, remembered or visible;
viewers light what they see, and a hide turns what was visible into what
is remembered. The layer is pure logic: a game shows it however it shows
its board, and may also read it as part of its rules, as light that
creatures flee, say.

```forth
REQUIRE game/2d/fog.f
```

`PROVIDED akashic-game-2d-fog` — safe to include multiple times. The
module requires `collide.f` for its collision-map source.

---

## Table of Contents

- [States](#states)
- [Constructor / Destructor](#constructor--destructor)
- [What Blocks Sight](#what-blocks-sight)
- [Revealing and Hiding](#revealing-and-hiding)
- [Queries](#queries)
- [How Sight Is Computed](#how-sight-is-computed)
- [Costs](#costs)
- [Quick Reference](#quick-reference)

---

## States

| Constant         | Value | Meaning                                  |
|------------------|-------|------------------------------------------|
| `FOG-UNSEEN`     | 0     | Never seen                               |
| `FOG-REMEMBERED` | 1     | Seen before, out of sight now            |
| `FOG-VISIBLE`    | 2     | In sight of a viewer since the last hide |

---

## Constructor / Destructor

### FOG-NEW

```
( w h -- fog )
```

Allocate a fog for a map of `w` by `h` tiles, every tile unseen. Nothing
blocks sight until a source is named. Both sizes must be at least 1.

### FOG-FREE

```
( fog -- )
```

Free the visibility array, the lit list, the row stack and the descriptor.
A collision map named as the source stays with its owner.

---

## What Blocks Sight

### FOG-BLOCK-MAP!

```
( fog cmap -- )
```

Tiles whose collision value is nonzero block sight. The fog reads the
map's bytes directly, the fast path, for as long as the map is its source,
so the map must have the fog's size and outlive its use. A game whose
movement and sight differ keeps a second collision map for sight.

### FOG-BLOCK-XT!

```
( fog xt ctx -- )
```

`xt ( x y ctx -- flag )` answers whether the in-bounds tile `(x, y)`
blocks sight, given the context cell `ctx`. The token may read any fog,
but must not reveal into the fog that calls it.

---

## Revealing and Hiding

### FOG-REVEAL

```
( fog cx cy radius -- )
```

Light every tile a viewer at `(cx, cy)` sees within `radius` tiles, by
Euclidean distance. Lit tiles become visible; tiles already lit stay so.
Several reveals between hides, from lamps or relays, light one layer. A
viewer off the map sees nothing, and a radius of 0 lights only the
viewer's tile.

### FOG-HIDE-ALL

```
( fog -- )
```

Turn every visible tile into a remembered one. Each tile a reveal lights
joins the fog's lit list, so a hide costs the tiles lit since the last
hide, whatever the map's size.

### FOG-RESET

```
( fog -- )
```

Forget everything: every tile unseen.

---

## Queries

### FOG-STATE

```
( fog x y -- 0|1|2 )
```

The tile's state; a tile off the map is unseen.

### FOG-W / FOG-H

```
( fog -- w )
( fog -- h )
```

The map's width and height.

### FOG-DATA

```
( fog -- addr )
```

The tiles' states, `w × h` bytes row by row: tile `(x, y)` is at
`addr + y × w + x`. A game that writes them, as a load restores what a
player had seen, writes only `FOG-UNSEEN` and `FOG-REMEMBERED`; visible
tiles come from `FOG-REVEAL`, which keeps the list `FOG-HIDE-ALL` reads.

---

## How Sight Is Computed

`FOG-REVEAL` is symmetric shadowcasting with exact rational slopes, as
Albert Ford describes it. Each of four quadrants is scanned in rows
outward from the viewer; a row holds the tiles whose columns lie between
its start and end slopes, kept as fractions, so no rounding enters. A
floor tile is lit when its centre lies within the slopes, a blocking tile
when any part of it does, and either only within the radius. A wall after
an open tile ends the open run, which continues one row deeper with the
wall's near edge as its end; an open tile after a wall starts the next run
at its own near edge.

Three properties follow, and the phase 7 suite checks them with a host
oracle (`local_testing/game_models.py`):

- a floor tile is visible from another exactly when the other is visible
  from it, within the radius;
- a wall casts its full shadow, so the tiles behind it stay dark;
- every tile beyond the map's edge blocks sight, which lights the same
  tiles inside the map as open ground outside it would, so the edge ends
  sight without darkening anything within.

The scan keeps its rows on a stack in the descriptor. A row at depth `d`
leaves at most `d` open runs waiting, so a radius `r` needs
`(r+1)(r+2)/2 + 1` rows; the stack grows when a reveal asks for a larger
radius than any before.

---

## Costs

Emulator cycles, one call each, Akashic `game-library`, 2026-11-23:

| Call | Cycles |
|---|---:|
| `FOG-REVEAL`, radius 4, open 24×12 map | 320,485 |
| `FOG-REVEAL`, radius 6, 40×20 map with a wall | 633,343 |
| `FOG-REVEAL`, radius 10, 40×20 map with a wall | 1,521,781 |
| `FOG-REVEAL`, radius 10, open 64×64 map | 1,558,336 |
| `FOG-REVEAL`, radius 6, 40×20, sight through a token | 755,613 |
| `FOG-HIDE-ALL` after a radius 4 reveal | 7,594 |
| `FOG-HIDE-ALL` after a radius 10 reveal | 42,434 |

---

## Quick Reference

| Word             | Stack Effect                    | Description                  |
|------------------|---------------------------------|------------------------------|
| `FOG-NEW`        | `( w h -- fog )`                | Create a fog                 |
| `FOG-FREE`       | `( fog -- )`                    | Destroy it                   |
| `FOG-BLOCK-MAP!` | `( fog cmap -- )`               | Sight blocked by a map       |
| `FOG-BLOCK-XT!`  | `( fog xt ctx -- )`             | Sight blocked by a token     |
| `FOG-REVEAL`     | `( fog cx cy radius -- )`       | Light what a viewer sees     |
| `FOG-HIDE-ALL`   | `( fog -- )`                    | Visible becomes remembered   |
| `FOG-RESET`      | `( fog -- )`                    | Every tile unseen            |
| `FOG-STATE`      | `( fog x y -- 0\|1\|2 )`        | A tile's state               |
| `FOG-DATA`       | `( fog -- addr )`               | The tiles' states as bytes   |
| `FOG-W`          | `( fog -- w )`                  | Map width                    |
| `FOG-H`          | `( fog -- h )`                  | Map height                   |
