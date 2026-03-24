# akashic-tui-game-applet — Game Applet Builder

A builder that stamps out an APP-DESC (112-byte application
descriptor) pre-wired for game lifecycle: init, update, draw,
input, shutdown.  The builder manages a game-view internally,
creating it during init and freeing it during shutdown.

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

Allocate a 168-byte game-applet descriptor (extends the 112-byte
APP-DESC with extra fields).  The standard APP-DESC callbacks
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

168 bytes (APP-DESC 112 bytes + 7 extra cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0       8  APP.INIT-XT      Internal init handler
 +8       8  APP.EVENT-XT     Internal event handler
+16       8  APP.TICK-XT      Internal tick handler
+24       8  APP.PAINT-XT     Internal paint handler
+32       8  APP.SHUTDOWN-XT  Internal shutdown handler
+40      32  (reserved APP-DESC fields)
+72       8  APP.TITLE-A      Title string address
+80       8  APP.TITLE-U      Title string length
+88      24  (reserved)
+112      8  user-init        User init XT
+120      8  user-update      User update XT
+128      8  user-draw        User draw XT
+136      8  user-input       User input XT
+144      8  user-shutdown    User shutdown XT
+152      8  fps              Target FPS (default 30)
+160      8  gv-ptr           Game-view pointer (set at init)
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GAME-APP-DESC` | `( -- desc )` | Create game applet |
| `GAPP-FPS!` | `( fps desc -- )` | Set target FPS |
| `GAPP-ON-INIT!` | `( xt desc -- )` | Wire init callback |
| `GAPP-ON-UPDATE!` | `( xt desc -- )` | Wire update callback |
| `GAPP-ON-DRAW!` | `( xt desc -- )` | Wire draw callback |
| `GAPP-ON-INPUT!` | `( xt desc -- )` | Wire input callback |
| `GAPP-ON-SHUTDOWN!` | `( xt desc -- )` | Wire shutdown callback |
| `GAPP-TITLE!` | `( addr u desc -- )` | Set title string |
| `GAPP-GV` | `( desc -- gv\|0 )` | Get game-view handle |
