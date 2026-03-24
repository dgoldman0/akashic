# akashic-tui-game-view — Game View Widget

A widget that hosts a fixed-timestep game loop inside the TUI
widget tree.  It bridges the app-shell tick/paint lifecycle with
game-oriented callbacks: on-update, on-draw, on-input, on-resize.

```forth
REQUIRE tui/game/game-view.f
```

`PROVIDED akashic-tui-game-view` — safe to include multiple times.

---

## Table of Contents

- [Constructor / Destructor](#constructor--destructor)
- [Configuration](#configuration)
- [Callback Wiring](#callback-wiring)
- [Lifecycle](#lifecycle)
- [Queries](#queries)
- [Pause / Resume](#pause--resume)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Constructor / Destructor

### GV-NEW

```
( rgn -- widget )
```

Allocate a 120-byte game-view widget.  Sets widget type to 17
(`WDG-T-GAME-VIEW`), stores the region, sets flags to
`VISIBLE | DIRTY`, and defaults to 30 FPS.

### GV-FREE

```
( widget -- )
```

Free the game-view descriptor.

---

## Configuration

### GV-FPS!

```
( widget fps -- )
```

Set the target FPS.  Clamped to a minimum of 1.  Also updates
the internal `frame-ms` field to `1000 / fps`.

```forth
my-gv 60 GV-FPS!    \ target 60 frames per second
```

---

## Callback Wiring

### GV-ON-UPDATE

```
( widget xt -- )
```

Set the per-frame update callback.  The XT receives `( dt -- )`
where dt is the fixed timestep in milliseconds.

### GV-ON-DRAW

```
( widget xt -- )
```

Set the draw callback.  The XT receives `( rgn -- )` and should
render game content into the given region.

### GV-ON-INPUT

```
( widget xt -- )
```

Set the input callback.  The XT receives `( ev -- )` where ev
is a key/mouse event code.

### GV-ON-RESIZE

```
( widget xt -- )
```

Set the resize callback.  The XT receives `( w h -- )`.

---

## Lifecycle

### GV-TICK

```
( widget -- )
```

Drive the game loop.  Call this from the app-shell's TICK-XT.
Accumulates elapsed time, fires update callbacks at the fixed
timestep, then calls the draw callback once per tick.  Increments
the frame counter after each draw.

If the widget is paused, this is a no-op.

---

## Queries

### GV-FRAME#

```
( widget -- n )
```

Return the current frame counter.

---

## Pause / Resume

### GV-PAUSE

```
( widget -- )
```

Pause the game loop.  `GV-TICK` becomes a no-op until resumed.

### GV-RESUME

```
( widget -- )
```

Resume the game loop after a pause.

### GV-PAUSED?

```
( widget -- flag )
```

Return TRUE if the game view is paused.

---

## Descriptor Layout

120 bytes (header + 10 cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0      40  Widget header (type, region, draw-xt, handle-xt, flags)
+40       8  update-xt     ( dt -- ) fixed-step update callback
+48       8  draw-xt       ( rgn -- ) draw callback
+56       8  input-xt      ( ev -- ) key/mouse event callback
+64       8  resize-xt     ( w h -- ) resize callback
+72       8  fps           Target FPS (default 30)
+80       8  frame-ms      Milliseconds per frame (1000/fps)
+88       8  accum         Frame time accumulator
+96       8  last-ms       MS@ of last tick
+104      8  frame-num     Frame counter
+112      8  gv-flags      GV-F-PAUSED etc.
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GV-NEW` | `( rgn -- widget )` | Create game view |
| `GV-FREE` | `( widget -- )` | Free descriptor |
| `GV-FPS!` | `( widget fps -- )` | Set target FPS |
| `GV-ON-UPDATE` | `( widget xt -- )` | Wire update callback |
| `GV-ON-DRAW` | `( widget xt -- )` | Wire draw callback |
| `GV-ON-INPUT` | `( widget xt -- )` | Wire input callback |
| `GV-ON-RESIZE` | `( widget xt -- )` | Wire resize callback |
| `GV-TICK` | `( widget -- )` | Drive game loop |
| `GV-FRAME#` | `( widget -- n )` | Get frame counter |
| `GV-PAUSE` | `( widget -- )` | Pause loop |
| `GV-RESUME` | `( widget -- )` | Resume loop |
| `GV-PAUSED?` | `( widget -- flag )` | Check paused |
