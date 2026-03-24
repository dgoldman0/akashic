# akashic/tui/game/widgets/minimap.f — Minimap Overlay Widget

**Layer:** 7 (TUI Game Widgets)
**Lines:** 276
**Prefix:** `MMAP-` (public), `_MMAP-` (internal)
**Provider:** `ak-tui-gw-minimap`
**Dependencies:** `widget.f`, `draw.f`, `canvas.f`, `region.f`, `tilemap.f`, `camera.f`

## Overview

Renders a zoomed-out overhead view of a tilemap using a Braille canvas.
Each canvas dot corresponds to one map tile (or a block of tiles when
scale > 1).  The camera viewport is drawn as a rectangle outline.
Arbitrary markers (waypoints, enemies, objectives) can be placed.

Non-focusable — does not consume keyboard events.

### Rendering Pipeline (`MMAP-UPDATE`)

1. Clear the internal canvas.
2. For each canvas dot, compute the corresponding map coordinate
   (applying scale and camera-centred offset).  If the tile is
   non-zero, set the dot.
3. Draw the viewport rectangle at the camera position.
4. Draw all markers as individual dots with per-marker foreground
   colour.

---

## Descriptor Layout (120 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type = `WDG-T-MINIMAP` (21) |
| +40 | tmap | addr | Tilemap address |
| +48 | cam | addr | Camera address (`CAM-X` / `CAM-Y`) |
| +56 | canvas | addr | Internal Braille canvas widget |
| +64 | scale | u | Tile-to-dot ratio (default 1) |
| +72 | vp-w | u | Viewport width in tiles |
| +80 | vp-h | u | Viewport height in tiles |
| +88 | markers | addr | Marker array address (allocated) |
| +96 | marker-max | u | Maximum markers (default 8) |
| +104 | marker-cnt | u | Current marker count |
| +112 | bg-color | u | Background colour index |

### Marker Entry (32 bytes, 4 cells)

| Offset | Field | Description |
|--------|-------|-------------|
| +0  | x  | Map tile X |
| +8  | y  | Map tile Y |
| +16 | cp | Codepoint |
| +24 | fg | Foreground colour |

---

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `MMAP-NEW` | `( rgn tmap cam -- widget )` | Allocate descriptor, internal canvas, and marker array |
| `MMAP-FREE` | `( widget -- )` | Free canvas, marker array, and descriptor |

### Configuration

| Word | Stack | Description |
|------|-------|-------------|
| `MMAP-SCALE!` | `( n widget -- )` | Set tile-to-dot ratio |
| `MMAP-VIEWPORT!` | `( w h widget -- )` | Set viewport dimensions in tiles |
| `MMAP-BG!` | `( color widget -- )` | Set background colour index |

### Markers

| Word | Stack | Description |
|------|-------|-------------|
| `MMAP-MARKER` | `( x y fg widget -- id )` | Add a marker; returns index or −1 if full |
| `MMAP-CLEAR-MARKERS` | `( widget -- )` | Remove all markers |

### Rendering

| Word | Stack | Description |
|------|-------|-------------|
| `MMAP-UPDATE` | `( widget -- )` | Re-render the minimap from tilemap + camera state |

---

## Guard

All public mutating words are wrapped through a concurrency guard
(`_mmap-guard`) using `WITH-GUARD`.

---

## Usage

```forth
REQUIRE tui/game/widgets/minimap.f

\ Create a minimap in a 10×8 corner region
my-region my-tilemap my-camera MMAP-NEW CONSTANT mmap

\ Configure
2 mmap MMAP-SCALE!
20 15 mmap MMAP-VIEWPORT!

\ Add a waypoint marker
25 18 3 mmap MMAP-MARKER DROP

\ Render
mmap MMAP-UPDATE

\ Cleanup
mmap MMAP-FREE
```
