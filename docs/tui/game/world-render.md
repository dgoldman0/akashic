# akashic-tui-game-world-render — World Renderer

Composites tilemap layers and sprites through a camera viewport
into a TUI region.  Reads tile IDs from tilemaps, looks up their
visual representation through an atlas, and writes the resulting
cells to the output region.  Supports up to 4 tilemap layers and
one sprite pool.

```forth
REQUIRE tui/game/world-render.f
```

`PROVIDED akashic-tui-game-world-render` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Layer Setup](#layer-setup)
- [Sprite Setup](#sprite-setup)
- [Rendering](#rendering)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### WREN-NEW

```
( rgn atlas cam -- wren )
```

Allocate a 64-byte world-renderer.  Stores references to the
output region, tile atlas, and camera.  All layer and sprite
pointers start as 0 (unused).

```forth
my-rgn my-atlas my-cam WREN-NEW CONSTANT my-wren
```

### WREN-FREE

```
( wren -- )
```

Free the world-renderer descriptor.  Does **not** free the
atlas, camera, or tilemaps — those are owned by the caller.

---

## Layer Setup

### WREN-SET-MAP

```
( wren layer tmap -- )
```

Assign a tilemap to layer 0–3.  Layer 0 is drawn first
(background), layer 3 last (foreground).  Pass 0 to clear
a layer.

```forth
my-wren 0 ground-map WREN-SET-MAP    \ background
my-wren 1 overlay-map WREN-SET-MAP   \ overlay
```

---

## Sprite Setup

### WREN-SET-SPRITES

```
( wren spool -- )
```

Assign a sprite pool for rendering on top of all tilemap
layers.  Pass 0 to disable sprites.

---

## Rendering

### WREN-PAINT

```
( wren -- )
```

Render the visible portion of all active layers and sprites
into the output region.  Uses the camera position to determine
which tiles are visible.  For each visible cell:

1. Iterate layers 0–3; for each non-zero tilemap, read the
   tile ID at the world coordinate and look it up in the atlas.
2. If the cell value is non-zero, write it to the region.
3. After all layers, render sprites from the sprite pool.

---

## Descriptor Layout

64 bytes (8 cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0       8  atlas      Tile atlas pointer
 +8       8  cam        Camera pointer
+16       8  rgn        Output region pointer
+24       8  layer-0    Tilemap pointer (background)
+32       8  layer-1    Tilemap pointer
+40       8  layer-2    Tilemap pointer
+48       8  layer-3    Tilemap pointer (foreground)
+56       8  spool      Sprite pool pointer
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `WREN-NEW` | `( rgn atlas cam -- wren )` | Create renderer |
| `WREN-FREE` | `( wren -- )` | Free descriptor |
| `WREN-SET-MAP` | `( wren layer tmap -- )` | Assign tilemap layer |
| `WREN-SET-SPRITES` | `( wren spool -- )` | Assign sprite pool |
| `WREN-PAINT` | `( wren -- )` | Render to region |
