# akashic-game-map — Text Maps

A map is a UTF-8 text file a person writes and reads in Pad: a header of
`key: value` lines that holds a legend, then rows of glyphs. The reader
gives a game three layers in the collision map's form, the places where
things start, and the header's values. A map it refuses answers why and
at which line, so a person editing the map can find the fault.

```forth
REQUIRE game/map.f
```

`PROVIDED akashic-game-map` — safe to include multiple times. The module
requires `utf8.f`, `collide.f`, `places.f` and `vfs-access.f`.

---

## Table of Contents

- [The Format](#the-format)
- [Statuses](#statuses)
- [Reading a Map](#reading-a-map)
- [Layers](#layers)
- [The Legend](#the-legend)
- [Spawns and Values](#spawns-and-values)
- [Memory](#memory)
- [Quick Reference](#quick-reference)

---

## The Format

```
name: The Bindery
width: 6
height: 3
tile: . floor 0 clear
tile: # shelf 1 opaque
spawn: @ archivist on .
spawn: f folio on .
rows:
######
#@.f.#
######
```

- **`tile: glyph name collision sight`** declares a tile kind: its glyph,
  its name, the collision value its tiles take (0 to 255, as a collision
  map holds), and `clear` for tiles that let sight through or `opaque` for
  tiles that block it.
- **`spawn: glyph name on tile-glyph`** declares a mark: a glyph that
  shows where something starts, its name, and the glyph of a tile declared
  above it, which lies beneath the mark.
- **`width:` and `height:`** give the map's size, whole numbers from 1;
  both are required.
- **`rows:`** ends the header. Exactly `height` rows follow it, each of
  exactly `width` glyphs.
- **Any other key** holds a value the game reads, such as a room's name or
  the length of its night.

A glyph is one Unicode character other than a space or tab, and appears
once in the legend, as a tile or as a mark. Names hold letters, digits,
`-` and `_`; a tile's name is unique among tiles, a mark's among marks.
A key appears once. A map declares at most 256 tile kinds, the values a
byte of the kind layer holds; marks have no such bound. Fields on a legend line are separated by spaces or
tabs. Blank lines may stand in the header and after the rows, and a CR
before a line's end is dropped, so a map saved with CRLF ends reads the
same.

---

## Statuses

| Constant | Value | Meaning |
|---|---:|---|
| `GMAP-S-OK` | 0 | Read |
| `GMAP-S-MISSING` | 1 | No such file |
| `GMAP-S-IO` | 2 | Reading the file failed |
| `GMAP-S-NOMEM` | 3 | No memory for the map |
| `GMAP-S-UTF8` | 4 | A line that is not UTF-8 |
| `GMAP-S-HEADER` | 5 | A header line that is no `key: value`, a key given twice, or no `rows:` line |
| `GMAP-S-SIZE` | 6 | Width or height missing, or not a whole number from 1 |
| `GMAP-S-LEGEND` | 7 | A malformed `tile:` or `spawn:` line, a glyph or name given twice, a mark on no tile declared above it, or a 257th tile kind |
| `GMAP-S-ROW` | 8 | A row of another width, a row missing, or text after the rows |
| `GMAP-S-GLYPH` | 9 | A glyph in a row that the legend lacks |

---

## Reading a Map

### GMAP-LOAD

```
( path-a path-u place -- map status )
```

Read the map file a path names in a place: an applet's origin for the maps
it ships, its home for a player's own. The file's size is read first and
exactly that is allocated. The map is 0 unless the status is `GMAP-S-OK`.

### GMAP-PARSE

```
( text-a text-u -- map status )
```

Read a map from text in memory, which the map copies.

### GMAP-WHERE

```
( -- line )
```

The line, counted from 1, at which the last refused map broke. A missing
`rows:` line or a missing row names the line after the text's last.

### GMAP-FREE

```
( map -- )
```

Free the map, its layers, legend, spawns, values and text. A map is freed
in the reverse of the order a read allocates it, so reading the same map
again takes back the same holes of the heap.

---

## Layers

Each layer is a collision map (`collide.f`) of the map's size, a byte a
tile, which the map owns.

| Word | Stack | The layer |
|---|---|---|
| `GMAP-CMAP` | `( map -- cmap )` | Each tile's collision value |
| `GMAP-SIGHT` | `( map -- cmap )` | 1 where a tile blocks sight, 0 elsewhere |
| `GMAP-KINDS` | `( map -- cmap )` | Each tile's kind, its place among the `tile:` lines from 0 |

A mark's tile holds the kind of the tile beneath it. `GMAP-SIGHT` is the
sight map the fog of war takes (`FOG-BLOCK-MAP!`), and `GMAP-CMAP` the
map movement and A\* read. `GMAP-TILE@ ( map x y -- kind )` reads the
kind of one tile; `GMAP-W` and `GMAP-H` give the size.

---

## The Legend

| Word | Stack | Description |
|---|---|---|
| `GMAP-TILES` | `( map -- n )` | Tile kinds |
| `GMAP-TILE` | `( map name-a name-u -- kind \| -1 )` | A kind by name |
| `GMAP-TILE-NAME` | `( map kind -- a u )` | Its name |
| `GMAP-TILE-GLYPH` | `( map kind -- char )` | Its glyph, a code point |
| `GMAP-MARKS` | `( map -- n )` | Marks |
| `GMAP-MARK` | `( map name-a name-u -- mark \| -1 )` | A mark by name |
| `GMAP-MARK-NAME` | `( map mark -- a u )` | Its name |
| `GMAP-MARK-GLYPH` | `( map mark -- char )` | Its glyph |
| `GMAP-MARK-TILE` | `( map mark -- kind )` | The tile kind beneath it |

A game finds the kinds and marks it gives meaning to by name, so a map
may declare them in any order.

---

## Spawns and Values

`GMAP-SPAWNS ( map -- n )` counts the marks in the rows, and
`GMAP-SPAWN@ ( map i -- x y mark )` gives each, row by row from the top
and left to right within a row.

`GMAP-VALUE ( map key-a key-u -- val-a val-u found? )` gives the value of
a header key, without the spaces around it; `width` and `height` are
among the keys.

---

## Memory

One pass over the text counts the legend and the values, a second fills
exact allocations; a pass over the rows counts the spawns, and a last
fills the spawn list and the layers. A map's storage is its text, the
legend at 32 bytes an entry, the values at 32, the spawns at 24 and three
layers of a byte a tile. The layers are allocated only once the rows have
been read and counted, so the size a header declares never allocates more
than the rows hold. Ten more reads of one map, and ten more refusals of a
damaged copy, leave `XMEM-HERE` where the first left it.

Reading a map of 24 by 12 tiles, 551 bytes with five tile kinds, four
marks and twelve spawns, takes 1,432,265 emulator cycles, and freeing it
13,557 (2026-11-23), so a game reads its maps when a room opens.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `GMAP-LOAD` | `( a u place -- map status )` | Read a map file in a place |
| `GMAP-PARSE` | `( a u -- map status )` | Read a map from text |
| `GMAP-WHERE` | `( -- line )` | Where the last refusal broke |
| `GMAP-FREE` | `( map -- )` | Free a map |
| `GMAP-W` / `GMAP-H` | `( map -- n )` | Size in tiles |
| `GMAP-CMAP` | `( map -- cmap )` | Collision values |
| `GMAP-SIGHT` | `( map -- cmap )` | Sight map |
| `GMAP-KINDS` | `( map -- cmap )` | Tile kinds |
| `GMAP-TILE@` | `( map x y -- kind )` | One tile's kind |
| `GMAP-TILES` / `GMAP-MARKS` | `( map -- n )` | Legend sizes |
| `GMAP-TILE` / `GMAP-MARK` | `( map a u -- n \| -1 )` | By name |
| `GMAP-TILE-NAME` / `GMAP-MARK-NAME` | `( map n -- a u )` | Names |
| `GMAP-TILE-GLYPH` / `GMAP-MARK-GLYPH` | `( map n -- char )` | Glyphs |
| `GMAP-MARK-TILE` | `( map mark -- kind )` | The tile beneath a mark |
| `GMAP-SPAWNS` | `( map -- n )` | Spawns |
| `GMAP-SPAWN@` | `( map i -- x y mark )` | One spawn |
| `GMAP-VALUE` | `( map a u -- a u found? )` | A header value |
