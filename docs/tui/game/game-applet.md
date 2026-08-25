# akashic-tui-game-applet — Game Applet Builder

A builder that stamps out a 224-byte game descriptor whose current
168-byte APP-DESC prefix is pre-wired for game lifecycle: init, update,
draw, input, and shutdown. The builder manages a game-view internally,
creating it during init and freeing it during shutdown.

> **Admission status:** this pre-admission builder is not currently a valid
> `APP-DESC` for `ASHELL-RUN` or `DESK-LAUNCH`. Its extension is rebased after
> the current APP layout so it cannot alias lifecycle fields, but the coherent
> game slice still needs component identity, instance-relative callback/widget
> state, and an exact hosted-region contract. That defect predates the rich
> terminal vertical and is intentionally not made reachable by a header-only
> patch here.

```forth
REQUIRE tui/game/game-applet.f
```

`PROVIDED akashic-tui-game-applet` — safe to include multiple times.

---

## Table of Contents

- [Creating an Applet](#creating-an-applet)
- [Configuration](#configuration)
- [Callback Wiring](#callback-wiring)
- [Title](#title)
- [Queries](#queries)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Creating an Applet

### GAME-APP-DESC

```
( -- desc )
```

Allocate a 224-byte game-applet descriptor (the current 168-byte
APP-DESC plus seven game-specific cells). The standard APP-DESC callbacks
(init, event, tick, paint, shutdown) are pre-wired to internal
handlers.  Default FPS is 30.

```forth
GAME-APP-DESC CONSTANT my-game

\ configure...
60 my-game GAPP-FPS!
' my-update my-game GAPP-ON-UPDATE!
' my-draw   my-game GAPP-ON-DRAW!
S" Space Blaster" my-game GAPP-TITLE!
```

---

## Configuration

### GAPP-FPS!

```
( fps desc -- )
```

Set the target FPS for the game-view created at init time.

---

## Callback Wiring

### GAPP-ON-INIT!

```
( xt desc -- )
```

Set the user init callback `( -- )`, called after the game-view
is created.

### GAPP-ON-UPDATE!

```
( xt desc -- )
```

Set the per-frame update callback `( dt -- )`.

### GAPP-ON-DRAW!

```
( xt desc -- )
```

Set the draw callback `( rgn -- )`.

### GAPP-ON-INPUT!

```
( xt desc -- )
```

Set the input callback `( ev -- )`.

### GAPP-ON-SHUTDOWN!

```
( xt desc -- )
```

Set the shutdown callback `( -- )`, called before the game-view
is freed.

---

## Title

### GAPP-TITLE!

```
( addr u desc -- )
```

Set the applet title string.  Stores the address and length
in the APP-DESC title fields.

```forth
S" My Game" my-game GAPP-TITLE!
```

---

## Queries

### GAPP-GV

```
( desc -- gv | 0 )
```

Return the game-view widget created during init, or 0 if init
has not yet been called.

---

## Descriptor Layout

224 bytes (the current 168-byte APP-DESC plus 7 extra cells). The standard
prefix is defined entirely by [app-desc.md](../app-desc.md); game extension
offsets are derived from `APP-DESC` rather than duplicated literals.

```
Offset         Size  Field
─────────────  ────  ──────────────
APP-DESC         8   user-init
APP-DESC + 8     8   user-update
APP-DESC + 16    8   user-draw
APP-DESC + 24    8   user-input
APP-DESC + 32    8   user-shutdown
APP-DESC + 40    8   fps (default 30)
APP-DESC + 48    8   gv-ptr (set at init)
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GAME-APP-DESC` | `( -- desc )` | Allocate the pre-admission game callback record |
| `GAPP-FPS!` | `( fps desc -- )` | Set target FPS |
| `GAPP-ON-INIT!` | `( xt desc -- )` | Wire init callback |
| `GAPP-ON-UPDATE!` | `( xt desc -- )` | Wire update callback |
| `GAPP-ON-DRAW!` | `( xt desc -- )` | Wire draw callback |
| `GAPP-ON-INPUT!` | `( xt desc -- )` | Wire input callback |
| `GAPP-ON-SHUTDOWN!` | `( xt desc -- )` | Wire shutdown callback |
| `GAPP-TITLE!` | `( addr u desc -- )` | Set title string |
| `GAPP-GV` | `( desc -- gv\|0 )` | Get game-view handle |
