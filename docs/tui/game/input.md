# akashic-tui-game-input — Rebindable Game Input Mapping

Translates raw key events into abstract game actions.  Supports
multiple keys per action (up to 4) and edge detection
(pressed-this-frame vs held).

```forth
REQUIRE tui/game/input.f
```

`PROVIDED akashic-tui-game-input` — safe to include multiple times.

---

## Table of Contents

- [Design](#design)
- [Usage](#usage)
- [Binding Keys](#binding-keys)
- [Feeding Events](#feeding-events)
- [Per-Frame Reset](#per-frame-reset)
- [Querying State](#querying-state)
- [Managing Bindings](#managing-bindings)
- [Standard Actions](#standard-actions)
- [Quick Reference](#quick-reference)

---

## Design

Actions are small integers (0–63).  Each action can have up to 4
bound keys.  The system maintains three bitmaps:

| Bitmap | Purpose |
|--------|---------|
| **down** | Currently held (set by `GACT-FEED`, cleared by `GACT-FRAME-RESET`) |
| **pressed** | Newly pressed this frame |
| **released** | Released this frame |

Since terminals don't report key-up events, every press is treated
as a one-frame event.  `GACT-FRAME-RESET` clears all three bitmaps
at the start of each frame.

Key codes for `KEY-T-CHAR` events are the character value.  Key
codes for `KEY-T-SPECIAL` events are `KEY-xxx OR 0x10000`.

---

## Usage

```forth
\ Bind keys
[CHAR] w ACT-UP    GACT-BIND
[CHAR] s ACT-DOWN  GACT-BIND
KEY-UP 0x10000 OR  ACT-UP GACT-BIND   \ arrow key + WASD

\ In your input callback
: my-input  ( ev -- )  GACT-FEED ;
' my-input GAME-ON-INPUT

\ In your update callback
: my-update  ( dt -- )
    DROP
    GACT-FRAME-RESET
    ACT-UP GACT-DOWN? IF  player-move-up  THEN
    ACT-DOWN GACT-DOWN? IF player-move-down THEN ;
```

---

## Binding Keys

### GACT-BIND

```
( key action -- )
```

Bind a key to an action.  Finds the first empty slot (up to 4
per action).  If all 4 slots are full, silently drops.

For character keys, `key` is the character value.  For special
keys, `key` is `KEY-xxx OR 0x10000`.

```forth
[CHAR] k ACT-ACTION1 GACT-BIND   \ 'k' triggers action 1
KEY-UP 0x10000 OR ACT-UP GACT-BIND
```

---

## Feeding Events

### GACT-FEED

```
( ev -- )
```

Process a key event.  `ev` is the address of a 24-byte key event
structure (type + code + modifiers, as produced by `KEY-POLL`).

If the key matches a binding and the action is not already down,
sets both the **down** and **pressed** bits for that action.

Call this from your `GAME-ON-INPUT` callback.

---

## Per-Frame Reset

### GACT-FRAME-RESET

```
( -- )
```

Clear all bitmaps (down, pressed, released).  Call at the **start**
of each frame, before processing any `GACT-FEED` calls.

Since terminals don't report key-up, every press is a one-frame
event — if a key isn't re-fed this frame, it's not down.

---

## Querying State

| Word | Stack | Description |
|------|-------|-------------|
| `GACT-DOWN?` | `( action -- flag )` | Is action held down? |
| `GACT-PRESSED?` | `( action -- flag )` | Was action newly pressed this frame? |
| `GACT-RELEASED?` | `( action -- flag )` | Was action released this frame? |

```forth
ACT-UP GACT-DOWN? IF  move-player-up  THEN
ACT-ACTION1 GACT-PRESSED? IF  attack  THEN
```

---

## Managing Bindings

### GACT-UNBIND-ALL

```
( action -- )
```

Remove all key bindings for the given action.

### GACT-CLEAR

```
( -- )
```

Reset all bindings and bitmap state.  Use when transitioning
between game screens that need different controls.

---

## Standard Actions

Pre-defined constants for common game actions:

| Constant | Value | Typical Use |
|----------|-------|-------------|
| `ACT-UP` | 0 | Move up |
| `ACT-DOWN` | 1 | Move down |
| `ACT-LEFT` | 2 | Move left |
| `ACT-RIGHT` | 3 | Move right |
| `ACT-ACTION1` | 4 | Primary action / confirm |
| `ACT-ACTION2` | 5 | Secondary action |
| `ACT-CANCEL` | 6 | Cancel / back |
| `ACT-MENU` | 7 | Open menu |
| `ACT-INVENTORY` | 8 | Open inventory |
| `ACT-PAUSE` | 9 | Pause game |

Actions 10–63 are available for game-specific bindings.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GACT-BIND` | `( key action -- )` | Bind key to action |
| `GACT-UNBIND-ALL` | `( action -- )` | Remove all bindings |
| `GACT-FEED` | `( ev -- )` | Feed key event |
| `GACT-FRAME-RESET` | `( -- )` | Clear per-frame state |
| `GACT-DOWN?` | `( action -- flag )` | Action held? |
| `GACT-PRESSED?` | `( action -- flag )` | Action newly pressed? |
| `GACT-RELEASED?` | `( action -- flag )` | Action released? |
| `GACT-CLEAR` | `( -- )` | Reset all state |

Guarded words (when `GUARDED` is enabled): `GACT-BIND`,
`GACT-UNBIND-ALL`, `GACT-FEED`, `GACT-FRAME-RESET`, `GACT-CLEAR`.
