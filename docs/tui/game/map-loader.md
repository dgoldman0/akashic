# akashic-tui-game-map-loader — Map Loader

Load tilemaps and collision maps from a CBOR-encoded map file.
Supports multiple tile layers (up to 4), collision data, spawn
points, and trigger zones.  Tile IDs in the file are resolved
through an atlas to produce renderable Cell values.

```forth
REQUIRE tui/game/map-loader.f
```

`PROVIDED akashic-tui-game-map-loader` — safe to include multiple
times.

---

## Table of Contents

- [Loading](#loading)
- [Accessors](#accessors)
- [Destructor](#destructor)
- [Map File Format](#map-file-format)
- [World Descriptor Layout](#world-descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Loading

### MLOAD

```
( path-a path-u atlas -- world | 0 )
```

Open a CBOR map file, read dimensions and layer count, allocate
tilemaps/collision map/spawn/trigger tables, populate them from the
file data, and return a world descriptor.  Returns 0 on any
failure (file missing, parse error, allocation failure).

Each tile layer is stored in the file as a byte-string of 8-byte
LE tile IDs.  `MLOAD` resolves every ID through `atlas` via
`ATLAS-GET` to produce packed Cell values, then stores them in
the tilemap with `TMAP-SET`.

```forth
256 ATLAS-NEW CONSTANT my-atlas
\ ... define tiles in atlas ...
S" world1.map" my-atlas MLOAD CONSTANT w
```

---

## Accessors

### MLOAD-W / MLOAD-H

```
( world -- n )
```

Return the map width or height in tiles.

### MLOAD-LAYER

```
( world n -- tmap )
```

Return the tilemap for layer `n` (0–3).  Returns 0 if that layer
was not present in the file.

```forth
w 0 MLOAD-LAYER  \ base layer tilemap
```

### MLOAD-CMAP

```
( world -- cmap )
```

Return the collision map, or 0 if none was defined.

### MLOAD-SPAWN

```
( world id -- x y )
```

Find a spawn point by `id`.  Returns the tile coordinates `x y`.
Returns `0 0` if the id is not found.

```forth
w 0 MLOAD-SPAWN  \ player spawn
```

### MLOAD-TRIGGER

```
( world id -- x y w h callback-tag )
```

Find a trigger zone by `id`.  Returns the zone rectangle
(`x y w h`) and a `callback-tag` integer that game logic can use
to dispatch events.  Returns `0 0 0 0 0` if the id is not found.

---

## Destructor

### MLOAD-FREE

```
( world -- )
```

Free all resources: tilemaps (via `TMAP-FREE`), collision map
(via `CMAP-FREE`), spawn/trigger tables, and the world descriptor
itself.

---

## Map File Format

The file is a CBOR map with the following keys:

| Key | CBOR Type | Description |
|-----|-----------|-------------|
| `"w"` | uint | Map width in tiles |
| `"h"` | uint | Map height in tiles |
| `"layers"` | uint | Number of tile layers (1–4) |
| `"L0"`–`"L3"` | bstr | Tile data for each layer (w×h × 8 bytes, LE tile IDs) |
| `"cmap"` | bstr | Collision data (w×h bytes, 0 = passable) |
| `"spawns"` | uint | Number of spawn points |
| `"SP0"`–`"SP9"` | array\[3\] | Spawn: \[id, x, y\] |
| `"triggers"` | uint | Number of trigger zones |
| `"TR0"`–`"TR9"` | array\[6\] | Trigger: \[id, x, y, w, h, callback-tag\] |

Tile IDs in the `"L0"`–`"L3"` byte strings are 8-byte
little-endian integers, one per tile, stored in row-major order
(row 0 first).

---

## World Descriptor Layout

96 bytes (12 cells):

```
Offset  Size  Field
──────  ────  ──────────
  +0      8   width       Map width in tiles
  +8      8   height      Map height in tiles
 +16      8   n-layers    Number of tile layers
 +24      8   layer-0     Tilemap for layer 0 (or 0)
 +32      8   layer-1     Tilemap for layer 1 (or 0)
 +40      8   layer-2     Tilemap for layer 2 (or 0)
 +48      8   layer-3     Tilemap for layer 3 (or 0)
 +56      8   cmap        Collision map (or 0)
 +64      8   spawns      Spawn table address (or 0)
 +72      8   n-spawns    Number of spawn points
 +80      8   triggers    Trigger table address (or 0)
 +88      8   n-trigs     Number of trigger zones
```

Spawn entry: 24 bytes (3 cells) — id, x, y

Trigger entry: 48 bytes (6 cells) — id, x, y, w, h, callback-tag

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `MLOAD` | `( path-a path-u atlas -- world \| 0 )` | Load map file |
| `MLOAD-W` | `( world -- w )` | Map width |
| `MLOAD-H` | `( world -- h )` | Map height |
| `MLOAD-LAYER` | `( world n -- tmap )` | Get layer tilemap |
| `MLOAD-CMAP` | `( world -- cmap )` | Get collision map |
| `MLOAD-SPAWN` | `( world id -- x y )` | Find spawn point |
| `MLOAD-TRIGGER` | `( world id -- x y w h tag )` | Find trigger zone |
| `MLOAD-FREE` | `( world -- )` | Free all resources |
