# akashic-tui-game-loop — Fixed-Timestep Game Loop

A fixed-timestep game loop that ticks update callbacks at a
configurable frame rate.  Supports two modes: **standalone**
(`GAME-RUN` blocks until quit) and **applet** (`GAME-INIT` +
`GAME-TICK` driven by an external scheduler like the app shell).

```forth
REQUIRE game/loop.f
```

`PROVIDED akashic-tui-game-loop` — safe to include multiple times.

---

## Table of Contents

- [Usage](#usage)
- [Standalone Mode](#standalone-mode)
- [Applet Mode](#applet-mode)
- [Configuration](#configuration)
- [Callbacks](#callbacks)
- [Frame Queries](#frame-queries)
- [Deferred Actions](#deferred-actions)
- [Quick Reference](#quick-reference)

---

## Usage

Register callbacks, set the frame rate, then run:

```forth
: my-input  ( ev -- )  GACT-FEED ;
: my-update ( dt -- )  DROP  world-step ;
: my-draw   ( -- )     render-world ;
: my-quit   ( -- flag ) game-over? ;

' my-input  GAME-ON-INPUT
' my-update GAME-ON-UPDATE
' my-draw   GAME-ON-DRAW
' my-quit   GAME-ON-QUIT

30 GAME-FPS!
GAME-RUN
```

---

## Standalone Mode

### GAME-RUN

```
( -- )
```

Enter the game loop.  Blocks until `GAME-QUIT` is called or the
quit callback returns TRUE.  Each iteration:

1. Polls `MS@` for elapsed time.
2. Accumulates delta; runs `on-update` once per frame interval.
3. Calls `on-draw` once per iteration.
4. Drains the deferred-action queue.
5. Calls `YIELD?` to cooperate with the OS.

---

## Applet Mode

For integration with the app shell or desk, use init/tick instead
of the blocking loop.

### GAME-INIT

```
( -- )
```

Reset timing state: accumulator, frame counter, deferred queue,
and capture the current `MS@` as the baseline.  Call once before
the first `GAME-TICK`.

### GAME-TICK

```
( -- )
```

Run one tick cycle.  Computes elapsed time since last tick, runs
as many fixed-timestep updates as fit, drains deferred actions,
and increments the frame counter.  Does **not** call `on-draw` —
the app shell calls the paint callback separately.

---

## Configuration

### GAME-FPS!

```
( n -- )
```

Set target frame rate.  Clamped to [1, 120].  Default is 30 fps
(33 ms per frame).

```forth
60 GAME-FPS!   \ 60 fps → 16 ms per frame
```

---

## Callbacks

All callbacks default to no-op.  Register with the corresponding
`GAME-ON-*` word.

| Word | Callback Signature | Description |
|------|-------------------|-------------|
| `GAME-ON-INPUT` | `( ev -- )` | Called per key event each frame |
| `GAME-ON-UPDATE` | `( dt -- )` | Called once per fixed timestep |
| `GAME-ON-DRAW` | `( -- )` | Called once per loop iteration |
| `GAME-ON-QUIT` | `( -- flag )` | Return TRUE to exit |

```forth
' my-update GAME-ON-UPDATE
```

---

## Frame Queries

### GAME-FRAME#

```
( -- n )
```

Return the current frame counter (0-based, incremented each tick).

### GAME-DT

```
( -- ms )
```

Return the frame interval in milliseconds (e.g. 33 for 30 fps).

---

## Deferred Actions

### GAME-POST

```
( xt -- )
```

Enqueue an execution token to be called at the end of the current
tick, after update and draw.  Up to 8 deferred actions per frame.
Silently drops if the queue is full.

Useful for scene transitions, state changes, or cleanup that
should not happen mid-update.

```forth
' switch-to-game-over GAME-POST
```

### GAME-QUIT

```
( -- )
```

Signal the loop to exit.  In standalone mode, `GAME-RUN` returns
after the current frame completes.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GAME-FPS!` | `( n -- )` | Set frame rate (1–120) |
| `GAME-DT` | `( -- ms )` | Frame interval in ms |
| `GAME-FRAME#` | `( -- n )` | Current frame number |
| `GAME-ON-INPUT` | `( xt -- )` | Register input callback |
| `GAME-ON-UPDATE` | `( xt -- )` | Register update callback |
| `GAME-ON-DRAW` | `( xt -- )` | Register draw callback |
| `GAME-ON-QUIT` | `( xt -- )` | Register quit callback |
| `GAME-RUN` | `( -- )` | Enter blocking game loop |
| `GAME-QUIT` | `( -- )` | Signal loop exit |
| `GAME-POST` | `( xt -- )` | Enqueue deferred action |
| `GAME-INIT` | `( -- )` | Reset timing (applet mode) |
| `GAME-TICK` | `( -- )` | Run one tick (applet mode) |

All public words are guarded (`_game-loop-guard`) when `GUARDED`
is enabled.
