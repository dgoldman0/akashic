# akashic-tui-game-canvas — Canvas Game View Widget

A composite widget that wraps a game-view with a Braille canvas,
giving games a pixel-addressable drawing surface at 2×4 sub-cell
resolution.  Manages canvas lifecycle, auto-clear, and delegates
tick/input to the inner game-view.

```forth
REQUIRE tui/game/game-canvas.f
```

`PROVIDED akashic-tui-game-canvas` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Callback Wiring](#callback-wiring)
- [Lifecycle](#lifecycle)
- [Canvas Access](#canvas-access)
- [Configuration](#configuration)
- [Pause / Resume](#pause--resume)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### GCVS-NEW

```
( rgn fps -- widget )
```

Allocate an 80-byte game-canvas widget.  Creates an internal
game-view (at the given FPS) and a Braille canvas sized to the
region.  Widget type is 18 (`WDG-T-GAME-CANVAS`), flags default
to `VISIBLE | DIRTY`.  Auto-clear is enabled by default.

### GCVS-FREE

```
( widget -- )
```

Free the game-canvas, its inner game-view, and the canvas.

---

## Callback Wiring

### GCVS-ON-UPDATE

```
( widget xt -- )
```

Set the per-frame update callback on the inner game-view.
The XT receives `( dt -- )`.

### GCVS-ON-DRAW

```
( widget xt -- )
```

Set the draw callback.  The XT receives `( cvs -- )` where cvs
is the Braille canvas.  If auto-clear is on, the canvas is cleared
before this callback is invoked.

### GCVS-ON-INPUT

```
( widget xt -- )
```

Set the input callback.  The XT receives `( ev -- )`.

---

## Lifecycle

### GCVS-TICK

```
( widget -- )
```

Delegate to the inner game-view's tick, then blit the canvas
to the widget's region.

---

## Canvas Access

### GCVS-CANVAS

```
( widget -- cvs )
```

Return the internal Braille canvas handle.

### GCVS-DOT-W

```
( widget -- w )
```

Return the dot-width of the canvas (region width × 2).

### GCVS-DOT-H

```
( widget -- h )
```

Return the dot-height of the canvas (region height × 4).

---

## Configuration

### GCVS-AUTO-CLEAR!

```
( widget flag -- )
```

Enable (TRUE) or disable (FALSE) automatic canvas clearing
before each draw callback.  Default is enabled.

---

## Pause / Resume

### GCVS-PAUSE

```
( widget -- )
```

Pause the inner game-view.

### GCVS-RESUME

```
( widget -- )
```

Resume the inner game-view.

---

## Descriptor Layout

80 bytes (header + 5 cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0      40  Widget header (type=18, region, draw-xt, handle-xt, flags)
+40       8  gv            Inner game-view widget pointer
+48       8  cvs           Braille canvas handle
+56       8  user-draw     User draw XT ( cvs -- )
+64       8  auto-clear    Flag: auto-clear before draw
+72       8  user-input    User input XT ( ev -- )
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GCVS-NEW` | `( rgn fps -- widget )` | Create canvas game view |
| `GCVS-FREE` | `( widget -- )` | Free all resources |
| `GCVS-ON-UPDATE` | `( widget xt -- )` | Wire update callback |
| `GCVS-ON-DRAW` | `( widget xt -- )` | Wire draw callback |
| `GCVS-ON-INPUT` | `( widget xt -- )` | Wire input callback |
| `GCVS-TICK` | `( widget -- )` | Drive loop + blit |
| `GCVS-CANVAS` | `( widget -- cvs )` | Get canvas handle |
| `GCVS-DOT-W` | `( widget -- w )` | Canvas dot width |
| `GCVS-DOT-H` | `( widget -- h )` | Canvas dot height |
| `GCVS-AUTO-CLEAR!` | `( widget flag -- )` | Toggle auto-clear |
| `GCVS-PAUSE` | `( widget -- )` | Pause loop |
| `GCVS-RESUME` | `( widget -- )` | Resume loop |
