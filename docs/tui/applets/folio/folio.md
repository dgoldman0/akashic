# Folio Watch

At night an archive's reading rooms lie dark. The night archivist walks
them with a hand lamp that lights what it reaches, and the room stays in
memory where the lamp has been. Folio Watch is the game library's first
game ([GAME-LIBRARY-PLAN.md](../../../game/GAME-LIBRARY-PLAN.md), section
3.1), an ordinary Desk applet built on the library's logic modules and the
canonical widgets.

This is the game's first skeleton: one room, an archivist who moves a tile
a turn, the fog of war, and nights saved and loaded. The inkmites, folios,
wall lamps and the three rooms come with the game's rules in the next
stage of the plan.

```forth
REQUIRE tui/applets/folio/folio.f
```

Entry: `FOLIO-ENTRY ( desc -- )` for Desk, `FOLIO-RUN ( -- )` standalone.

---

## Playing

| Key | Does |
|---|---|
| Arrows, `h` `j` `k` `l` | Step a tile |
| `y` `u` `b` `n` | Step diagonally |
| `.` or Space | Wait a turn |
| Select a tile | Take the path's first step toward it |
| Ctrl+N | Start a new night |
| Ctrl+S | Save the night |
| Ctrl+O | Load the saved night |
| F1 | List the keys |
| Ctrl+Q | Quit |

A step into a shelf or a desk takes no turn, and a diagonal step needs
both straight neighbours open, so the archivist never squeezes between two
shelves. The status bar names the room and shows the turn and whether the
night is saved. Loading or starting a night over unsaved turns asks first,
and so does closing.

---

## How It Is Built

- **The room** is a text map, `tui/applets/folio/reading-room.map`, read
  from the applet's origin with `GMAP-LOAD` ([map.md](../../../game/map.md)).
  Its legend gives floor, rug, shelves and desks; its spawn marks place the
  archivist, and the folios, nests and lamps the next stage uses.
- **The board** is `tui/game/board.f` ([board.md](../../game/board.md)), a
  canonical text grid on the UIDL region element `board`: the archivist's
  tile is current, tiles the lamp does not light are unavailable and show
  what the archivist remembers, and a selected tile is the grid's primary
  item. A camera (`game/2d/camera.f`) chooses the window when the room is
  larger than the board.
- **The lamp** is the fog of war (`game/2d/fog.f`) over the room's sight
  map: each turn hides what the lamp lit and reveals radius 4 around the
  archivist.
- **Walking to a tile** takes A\*'s path (`game/2d/pathfind.f`) over the
  room's collision map, with diagonal steps that never cut a corner.
- **Nights** are saved in the applet's home as `/night.sav`
  ([save.md](../../../game/save.md)): the room's path, the turn, where the
  archivist stands and the tiles seen. A load refuses a save of another
  room or with the archivist off an open tile.

The applet's instance state lives in its component instance, so two
instances run apart, and it asks for a home with `PLACES-NEED-HOME`.
