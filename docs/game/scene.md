# akashic-tui-game-scene — Scene Manager

A stack-based scene manager with enter/leave/update/draw lifecycle
callbacks.  Push and pop scenes to navigate menus, gameplay states,
pause screens, etc.  Supports up to 8 nested scenes.

```forth
REQUIRE game/scene.f
```

`PROVIDED akashic-tui-game-scene` — safe to include multiple times.

---

## Table of Contents

- [Defining Scenes](#defining-scenes)
- [Scene Stack](#scene-stack)
  - [Push / Pop / Switch](#push--pop--switch)
  - [Queries](#queries)
- [Dispatchers](#dispatchers)
- [Integration Helpers](#integration-helpers)
  - [Standalone Mode](#standalone-mode)
  - [Applet Mode](#applet-mode)
- [Descriptor Layout](#descriptor-layout)
- [Quick Reference](#quick-reference)

---

## Defining Scenes

### SCN-DEFINE

```
( xt-enter xt-leave xt-update xt-draw -- scene )
```

Allocate a 32-byte scene descriptor and set the four lifecycle
callbacks:

| Callback | Signature | Called when |
|----------|-----------|------------|
| on-enter  | `( -- )` | Scene is pushed or switched to |
| on-leave  | `( -- )` | Scene is popped or switched away from |
| on-update | `( -- )` | Each frame, via `SCN-UPDATE` |
| on-draw   | `( -- )` | Each frame, via `SCN-DRAW` |

Use `0` for any callback you don't need.

```forth
' menu-enter ' menu-leave ' menu-update ' menu-draw SCN-DEFINE
CONSTANT scn-menu
```

### SCN-FREE

```
( scene -- )
```

Free the scene descriptor.

---

## Scene Stack

Scenes are managed on an internal stack (maximum depth 8).

### Push / Pop / Switch

#### SCN-PUSH

```
( scene -- )
```

Push a scene onto the top of the stack.  Calls the scene's
`on-enter` callback.

#### SCN-POP

```
( -- )
```

Pop the top scene.  Calls the popped scene's `on-leave` callback.
If the stack is empty, the call is silently ignored.

#### SCN-SWITCH

```
( scene -- )
```

Replace the top scene.  Calls `on-leave` on the old scene, then
`on-enter` on the new one.  If the stack is empty, equivalent to
`SCN-PUSH`.

```forth
scn-menu SCN-PUSH       \ menu active
scn-game SCN-SWITCH     \ replace menu with game
SCN-POP                  \ back to empty stack
```

---

### Queries

#### SCN-ACTIVE

```
( -- scene | 0 )
```

Return the top scene descriptor, or 0 if the stack is empty.

#### SCN-DEPTH

```
( -- n )
```

Return the number of scenes currently on the stack.

---

## Dispatchers

These words call callbacks on the current top-of-stack scene.
If the stack is empty, they are no-ops.

### SCN-UPDATE

```
( -- )
```

Call the active scene's `on-update` callback (if non-zero).

### SCN-DRAW

```
( -- )
```

Call the active scene's `on-draw` callback (if non-zero).

---

## Integration Helpers

### Standalone Mode

#### SCN-BIND-LOOP

```
( -- )
```

Wire the scene manager into the game loop by setting
`GAME-ON-UPDATE` to `SCN-UPDATE` and `GAME-ON-DRAW` to
`SCN-DRAW`.  After this call, `GAME-RUN` dispatches to
whatever scene is on top of the stack.

```forth
scn-title SCN-PUSH
SCN-BIND-LOOP
60 GAME-FPS!
GAME-RUN
```

### Applet Mode

#### SCN-BIND-APPLET

```
( -- applet-desc )
```

Create a TUI applet descriptor whose `on-update` and `on-draw`
handlers point to the scene dispatchers.  Returns the descriptor
address suitable for use with the app-shell.

```forth
scn-game SCN-PUSH
SCN-BIND-APPLET  CONSTANT my-app
\ register my-app with the app-shell
```

---

## Descriptor Layout

32 bytes (4 cells):

```
Offset  Size  Field
──────  ────  ──────────────
 +0      8   on-enter   XT called on push / switch-to
 +8      8   on-leave   XT called on pop / switch-from
+16      8   on-update  XT called each frame via SCN-UPDATE
+24      8   on-draw    XT called each frame via SCN-DRAW
```

All fields hold execution tokens (XTs).  A value of 0 means
"no callback" — the dispatcher will skip it.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `SCN-DEFINE` | `( xt-enter xt-leave xt-update xt-draw -- scene )` | Create scene |
| `SCN-FREE` | `( scene -- )` | Free scene descriptor |
| `SCN-PUSH` | `( scene -- )` | Push scene (calls on-enter) |
| `SCN-POP` | `( -- )` | Pop scene (calls on-leave) |
| `SCN-SWITCH` | `( scene -- )` | Replace top scene |
| `SCN-ACTIVE` | `( -- scene\|0 )` | Get top scene |
| `SCN-DEPTH` | `( -- n )` | Stack depth |
| `SCN-UPDATE` | `( -- )` | Dispatch on-update |
| `SCN-DRAW` | `( -- )` | Dispatch on-draw |
| `SCN-BIND-LOOP` | `( -- )` | Wire into GAME-RUN |
| `SCN-BIND-APPLET` | `( -- desc )` | Create applet descriptor |

No guard section — scene operations are not protected by a
concurrency guard.
