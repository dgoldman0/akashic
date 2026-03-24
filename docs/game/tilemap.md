# akashic-tui-game-tilemap — 2D Tile Map with Viewport Scrolling

A two-dimensional grid of character cells with viewport-based
scrolling and region-clipped rendering.  Each tile is a packed
64-bit cell value (codepoint + fg + bg + attrs), the same format
used by `screen.f` and `cell.f`.

```forth
REQUIRE game/tilemap.f
```

`PROVIDED akashic-tui-game-tilemap` — safe to include multiple times.

---

## Table of Contents

- [Usage](#usage)
- [Constructor / Destructor](#constructor--destructor)
- [Tile Access](#tile-access)
- [Viewport](#viewport)
- [Rendering](#rendering)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Usage

```forth
\ Create a 40×30 tile map, fill with dots
40 30 TMAP-NEW  CONSTANT my-map
[CHAR] . 7 0 0 CELL-MAKE  my-map SWAP TMAP-FILL

\ Place a wall
[CHAR] # 7 0 0 CELL-MAKE  my-map 10 5 ROT TMAP-SET

\ Set up viewport and render into a region
my-map 0 0 TMAP-VIEWPORT!
my-map my-region TMAP-RENDER
```

---

## Constructor / Destructor

### TMAP-NEW

```
( w h -- tmap )
```

Allocate a tilemap descriptor (56 bytes) and a tile-data buffer
(`w × h × 8` bytes).  All tiles are initialized to `CELL-BLANK`.
Viewport starts at (0, 0).

### TMAP-FREE

```
( tmap -- )
```

Free the tile-data buffer and the descriptor.

---

## Tile Access

### TMAP-SET

```
( tmap col row cell -- )
```

Write a cell value to position (col, row).  Out-of-bounds writes
are silently ignored.

### TMAP-GET

```
( tmap col row -- cell )
```

Read the cell value at position (col, row).  Out-of-bounds reads
are undefined — validate indices before calling.

### TMAP-FILL

```
( tmap cell -- )
```

Fill every tile in the map with the given cell value.

```forth
[CHAR] . 7 0 0 CELL-MAKE  my-map SWAP TMAP-FILL
```

### TMAP-W / TMAP-H

```
( tmap -- w )
( tmap -- h )
```

Return the map's width and height in tiles.

---

## Viewport

The viewport defines which portion of the map is visible.  It is
specified as a (vx, vy) origin — the top-left tile that maps to
the top-left corner of the rendering region.

### TMAP-VIEWPORT!

```
( tmap vx vy -- )
```

Set the viewport origin.  Negative values are clamped to 0.

### TMAP-VIEWPORT-X / TMAP-VIEWPORT-Y

```
( tmap -- vx )
( tmap -- vy )
```

Query the current viewport position.

### TMAP-SCROLL

```
( tmap dx dy -- )
```

Scroll the viewport by a relative delta.  Adds `dx` to the
current vx and `dy` to the current vy, then clamps negatives
to 0.

```forth
my-map 1 0 TMAP-SCROLL   \ scroll one column right
my-map 0 -1 TMAP-SCROLL  \ scroll one row up (clamps at 0)
```

---

## Rendering

### TMAP-RENDER

```
( tmap rgn -- )
```

Render the visible portion of the tilemap into the screen buffer,
clipped to the given region.  For each position in the region,
reads the tile at `(vp-x + col, vp-y + row)` and writes it via
`SCR-SET`.

Tiles that fall outside the map bounds are skipped (blank).

The region is created with `RGN-NEW ( row col h w -- rgn )` from
`region.f`.

---

## Descriptor Layout

56 bytes (7 cells):

```
Offset  Size  Field
──────  ────  ──────────────────────
 +0      8   map-w (tiles)
 +8      8   map-h (tiles)
+16      8   data   (addr of tile buffer, w × h × 8 bytes)
+24      8   vp-x   (viewport origin column)
+32      8   vp-y   (viewport origin row)
+40      8   prev-vp-x  (previous viewport X, for scroll detection)
+48      8   prev-vp-y  (previous viewport Y, for scroll detection)
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `TMAP-NEW` | `( w h -- tmap )` | Allocate tilemap |
| `TMAP-FREE` | `( tmap -- )` | Free tilemap |
| `TMAP-SET` | `( tmap col row cell -- )` | Write tile |
| `TMAP-GET` | `( tmap col row -- cell )` | Read tile |
| `TMAP-FILL` | `( tmap cell -- )` | Fill all tiles |
| `TMAP-W` | `( tmap -- w )` | Map width |
| `TMAP-H` | `( tmap -- h )` | Map height |
| `TMAP-VIEWPORT!` | `( tmap vx vy -- )` | Set viewport |
| `TMAP-VIEWPORT-X` | `( tmap -- vx )` | Get viewport X |
| `TMAP-VIEWPORT-Y` | `( tmap -- vy )` | Get viewport Y |
| `TMAP-SCROLL` | `( tmap dx dy -- )` | Scroll viewport |
| `TMAP-RENDER` | `( tmap rgn -- )` | Render to screen |

All public words are guarded (`_tmap-guard`) when `GUARDED` is
enabled.
