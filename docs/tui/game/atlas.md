# akashic-tui-game-atlas — Tile Atlas

Maps integer tile IDs to packed Cell values (codepoint + fg + bg +
attrs).  Provides the visual layer between game logic (which
operates on integer tile types) and rendering (which needs cells).

```forth
REQUIRE tui/game/atlas.f
```

`PROVIDED akashic-tui-game-atlas` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Define / Get](#define--get)
- [Bulk Load](#bulk-load)
- [Queries](#queries)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### ATLAS-NEW

```
( capacity -- atlas )
```

Allocate a tile atlas that can hold up to `capacity` tile
definitions.  Capacity is clamped to a minimum of 1.  All
cells are initialized to zero.

```forth
256 ATLAS-NEW CONSTANT my-atlas
```

### ATLAS-FREE

```
( atlas -- )
```

Free the atlas descriptor and its cell array.

---

## Define / Get

### ATLAS-DEFINE

```
( atlas id cp fg bg attrs -- )
```

Register the appearance for tile `id`.  The codepoint, foreground
color, background color, and attributes are packed into a single
cell value via `CELL-MAKE`.  If `id >= capacity`, the call is
silently ignored.

```forth
my-atlas 0  CHAR #  7 0 0  ATLAS-DEFINE   \ tile 0 = '#' white/black
my-atlas 1  CHAR .  2 0 0  ATLAS-DEFINE   \ tile 1 = '.' green/black
```

### ATLAS-GET

```
( atlas id -- cell )
```

Look up tile `id`.  Returns the packed cell, or `CELL-BLANK`
(space, fg=7, bg=0) if the ID is out of range.  Undefined
(but in-range) tiles return 0.

---

## Bulk Load

### ATLAS-LOAD

```
( atlas table count -- )
```

Load tile definitions from a flat table of 5-cell records:

```
id  cp  fg  bg  attrs
```

Reads `count` records and calls `ATLAS-DEFINE` for each.

```forth
CREATE my-tiles
  0 , CHAR # ,  7 , 0 , 0 ,    \ tile 0
  1 , CHAR . ,  2 , 0 , 0 ,    \ tile 1

my-atlas my-tiles 2 ATLAS-LOAD
```

---

## Queries

### ATLAS-CAP

```
( atlas -- capacity )
```

Return the atlas capacity.

---

## Descriptor Layout

24 bytes (3 cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0       8  capacity    Maximum number of tile IDs
 +8       8  data        Address of cell array (capacity × 8 bytes)
+16       8  count       Number of defined tiles
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `ATLAS-NEW` | `( capacity -- atlas )` | Create atlas |
| `ATLAS-FREE` | `( atlas -- )` | Free atlas |
| `ATLAS-DEFINE` | `( atlas id cp fg bg attrs -- )` | Define tile |
| `ATLAS-GET` | `( atlas id -- cell )` | Look up tile |
| `ATLAS-LOAD` | `( atlas table count -- )` | Bulk load tiles |
| `ATLAS-CAP` | `( atlas -- capacity )` | Get capacity |
