# akashic-tui-game-board — A Game Board as a Text Grid

A board shows the part of a game's map that fits its region as one
canonical text grid ([text-grid.md](../widgets/text-grid.md)), each tile
one item two cells wide. The game gives each tile's text and state through
a token, and a pointer press or a rich terminal's `PLACE` on a tile reaches
the game as the tile's map position. CELL output is the text grid's own
draw, and the rich terminal receives the same model as a `TEXT_GRID`, so
the board needs no scene or renderer of its own.

```forth
REQUIRE tui/game/board.f
```

`PROVIDED akashic-tui-game-board` — safe to include multiple times.

---

## Table of Contents

- [Tiles](#tiles)
- [The Window](#the-window)
- [API](#api)
- [Banks](#banks)
- [Quick Reference](#quick-reference)

---

## Tiles

The game's token answers each tile's text and state:

```
( x y ctx -- text-a text-u state )
```

`state` is 0, `BOARD-CURRENT` for the tile the player stands on, which
draws underlined, or `BOARD-UNAVAILABLE` for a tile out of sight,
which draws dim and refuses selection. A tile is never both. The text is
what the tile shows in its two cells, such as a glyph and a space, or a
wall's glyph twice; it is copied into the model, so the token may build it
in a buffer it reuses.

The cursor's tile, set with `BOARD-CURSOR!`, is the grid's primary item,
drawn reversed, while it lies in the window and the game shows it
available. A press on an available tile selects it through the text grid's
own selection, and the board calls the game's selection token with the
tile's map position:

```
( x y ctx -- )
```

Item keys are map positions, `y × width + x + 1`, so a tile keeps its key
as the window moves.

---

## The Window

The model's root is the region, so the grid draws a cell for a cell. The
window, the tiles the region holds, is half the region's columns wide and
as tall as its rows, and no larger than the map; a window smaller than the
region sits in its middle. The game chooses the window's origin, as a
camera following the player chooses it (`game/2d/camera.f`), and the board
keeps the window on the map.

When the board's widget is attached to a UIDL region element, UIDL gives
it the element's geometry on each paint. A game asks `BOARD-FITS?` before
a turn or on a tick and rebuilds the board when the region has changed
size since the model was built.

---

## API

### BOARD-NEW

```
( row col h w map-w map-h -- board )
```

A board over a map of `map-w` by `map-h` tiles, drawing in a region of its
own at `row col` of `h` by `w` cells. The board owns its region and its
text grid; a failed allocation aborts.

### BOARD-FREE

```
( board -- )
```

Free the text grid, the region, the banks and the descriptor. Detach the
widget from its UIDL element first.

### BOARD-TOKEN! / BOARD-ON-SELECT

```
BOARD-TOKEN!     ( xt ctx board -- )
BOARD-ON-SELECT  ( xt board -- )
```

The tile token and its context, which the selection token shares, and the
selection token, or 0 for none.

### BOARD-WINDOW! / BOARD-CURSOR!

```
BOARD-WINDOW!  ( x0 y0 board -- )
BOARD-CURSOR!  ( x y board -- )
```

The window's origin in tiles, which the next rebuild keeps on the map, and
the cursor's tile, or `-1 -1` for none.

### BOARD-REBUILD

```
( board -- status )
```

Build the model for the region's size and the game's tiles, and bind it.
`USCOL-S-OK`, a collection status, or `BOARD-S-NOMEM` when the banks
cannot grow; a failed build leaves the widget its last model.

### BOARD-FITS? / BOARD-VIEW / BOARD-ORIGIN / BOARD-WIDGET

```
BOARD-FITS?   ( board -- flag )
BOARD-VIEW    ( board -- vw vh )
BOARD-ORIGIN  ( board -- x0 y0 )
BOARD-WIDGET  ( board -- widget )
```

Whether the bound model has the region's size; the window's size and
origin as the last rebuild laid them out; and the text grid, which a game
attaches to its UIDL region element with `UTUI-WIDGET-SET`.

---

## Banks

The board follows Grid's pattern of two banks: it builds the model in the
bank the widget does not hold and binds it with `TGRID-BIND`, which
validates the model whole before the widget lets go of the other. When a
build runs out of room, the board measures the model, allocates new banks
of a power of two from 256 bytes that hold it, builds in one and binds it,
and only then frees the old banks, so the widget never holds a model that
has been freed. Twenty rebuilds of one board leave `XMEM-HERE` where the
first left it.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `BOARD-NEW` | `( row col h w map-w map-h -- board )` | Make a board |
| `BOARD-FREE` | `( board -- )` | Free a board |
| `BOARD-TOKEN!` | `( xt ctx board -- )` | The tile token |
| `BOARD-ON-SELECT` | `( xt board -- )` | The selection token |
| `BOARD-WINDOW!` | `( x0 y0 board -- )` | The window's origin |
| `BOARD-CURSOR!` | `( x y board -- )` | The cursor's tile |
| `BOARD-REBUILD` | `( board -- status )` | Build and bind the model |
| `BOARD-FITS?` | `( board -- flag )` | Does the model fit the region? |
| `BOARD-VIEW` | `( board -- vw vh )` | The window's size |
| `BOARD-ORIGIN` | `( board -- x0 y0 )` | The window's origin |
| `BOARD-WIDGET` | `( board -- widget )` | The text grid |
