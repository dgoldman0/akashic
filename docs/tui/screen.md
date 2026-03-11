# akashic-tui-screen — Virtual Screen Buffer

Double-buffered character-cell screen.  Widgets write to the back
buffer via `SCR-SET`.  `SCR-FLUSH` diffs front vs. back and emits
only changed cells via ANSI escape sequences.  This is the central
coordination point — all drawing goes through the screen, and all
output goes through flush.

```forth
REQUIRE tui/screen.f
```

`PROVIDED akashic-tui-screen` — safe to include multiple times.

**Dependencies:** `cell.f`, `ansi.f`, `../text/utf8.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Screen Descriptor](#screen-descriptor)
- [Constructor / Destructor](#constructor--destructor)
- [Current Screen](#current-screen)
- [Accessors](#accessors)
- [Cell Read / Write](#cell-read--write)
- [Fill / Clear](#fill--clear)
- [Cursor Management](#cursor-management)
- [Flush Algorithm](#flush-algorithm)
- [Force Redraw](#force-redraw)
- [Resize](#resize)
- [Memory](#memory)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Double-buffered** | Front buffer = screen state, back buffer = pending state. Flush diffs. |
| **Differential flush** | Only changed cells emit ANSI — keeps serial-link updates fast. |
| **One current screen** | `SCR-USE` selects the target. All drawing words use `_SCR-CUR`. |
| **XMEM buffers** | Cell buffers allocate from external memory when available. |
| **Prefix convention** | Public: `SCR-`. Internal: `_SCR-`. |
| **Not reentrant** | Scratch `VARIABLE`s are shared; call from one task only. |

---

## Screen Descriptor

Each screen is an 8-cell (64-byte) descriptor allocated on the
internal heap, plus two cell buffers in XMEM.

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | width | Columns |
| +8 | height | Rows |
| +16 | front | Address of front buffer (width × height cells) |
| +24 | back | Address of back buffer (width × height cells) |
| +32 | cursor-row | Current cursor row (0-based) |
| +40 | cursor-col | Current cursor column (0-based) |
| +48 | cursor-vis | Cursor visible flag (0 = hidden, -1 = visible) |
| +56 | dirty | Global dirty flag |

---

## Constructor / Destructor

### SCR-NEW

```
( w h -- scr )
```

Allocate a screen descriptor and two cell buffers (front + back).
Both buffers are initialized with `CELL-BLANK`.  The descriptor
is heap-allocated; buffers use `XMEM-ALLOT` when extended memory
is available, falling back to `ALLOCATE`.

```forth
80 24 SCR-NEW   \ standard 80×24 terminal
```

### SCR-FREE

```
( scr -- )
```

Free the screen descriptor.  Note: XMEM buffers are bump-allocated
and cannot be individually freed.

---

## Current Screen

### SCR-USE

```
( scr -- )
```

Set `scr` as the current screen.  All cell read/write, fill, flush,
and cursor words operate on the current screen.

```forth
80 24 SCR-NEW DUP SCR-USE   \ create and activate
```

---

## Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `SCR-W` | `( -- w )` | Width of current screen in columns |
| `SCR-H` | `( -- h )` | Height of current screen in rows |

---

## Cell Read / Write

### SCR-SET

```
( cell row col -- )
```

Write a cell to the back buffer at the given (row, col) position.
Row and column are 0-based.

```forth
65 14 0 CELL-A-BOLD CELL-MAKE  0 0 SCR-SET   \ bold yellow 'A' at top-left
```

### SCR-GET

```
( row col -- cell )
```

Read a cell from the back buffer.

### SCR-FRONT@

```
( row col -- cell )
```

Read a cell from the front buffer (the last-flushed state).

---

## Fill / Clear

### SCR-FILL

```
( cell -- )
```

Fill the entire back buffer with the given cell value.

### SCR-CLEAR

```
( -- )
```

Fill the back buffer with `CELL-BLANK` (space, white on black, no
attributes).

```forth
SCR-CLEAR   \ erase all pending content
```

---

## Cursor Management

### SCR-CURSOR-AT

```
( row col -- )
```

Set the logical cursor position (0-based).  The physical terminal
cursor will be moved here after the next `SCR-FLUSH` (if visible).

### SCR-CURSOR-ON / SCR-CURSOR-OFF

```
( -- )
```

Show or hide the cursor on the next flush.  The cursor is hidden
during flush regardless; `SCR-CURSOR-ON` restores it at the end.

---

## Flush Algorithm

### SCR-FLUSH

```
( -- )
```

Differential screen update.  Iterates every cell position.  Where
`front[i] ≠ back[i]`:

1. **Position cursor** via `ANSI-AT` (skipped if already at the
   correct position — consecutive dirty cells need no extra
   positioning).
2. **Emit attribute/color changes** — only the diff from the last
   emitted cell.  If attributes change, `ANSI-RESET` is emitted
   first, then individual SGR codes for each set flag.  Foreground
   and background colors are emitted via `ANSI-FG256` / `ANSI-BG256`
   only when they differ from the last emitted state.
3. **Emit the character** as UTF-8 via `EMIT` (ASCII fast path) or
   `UTF8-ENCODE` + `TYPE` (multi-byte).

After flushing every dirty cell, `back[]` is copied to `front[]`
cell-by-cell.  The cursor is hidden during the update
(`ANSI-CURSOR-OFF`) and optionally restored at the logical position
with `ANSI-CURSOR-ON`.

```forth
\ Typical frame loop:
SCR-CLEAR
\ ... draw widgets into back buffer ...
SCR-FLUSH
```

---

## Force Redraw

### SCR-FORCE

```
( -- )
```

Force a full redraw on the next flush by filling the front buffer
with an impossible value (-1) so every cell appears dirty.

```forth
SCR-FORCE SCR-FLUSH   \ full repaint
```

---

## Resize

### SCR-RESIZE

```
( w h -- )
```

Resize the current screen.  Allocates new buffers, copies the
overlapping region from the old back buffer to the new back buffer,
and replaces the descriptor fields.  Calls `SCR-FORCE` so the next
flush repaints everything.

Old buffers are abandoned (XMEM bump allocator cannot free
individual allocations).

```forth
132 50 SCR-RESIZE   \ switch to 132-column mode
```

---

## Memory

Each cell is 8 bytes.  Two buffers per screen:

| Size | Cells | Buffer bytes | Total (×2) |
|------|-------|-------------|------------|
| 80×24 | 1,920 | 15,360 | **30,720** (~30 KiB) |
| 132×50 | 6,600 | 52,800 | **105,600** (~103 KiB) |
| 200×60 | 12,000 | 96,000 | **192,000** (~188 KiB) |

All fit comfortably in XMEM (16 MiB available).  The 64-byte
descriptor is always on the internal heap.

---

## Quick Reference

| Word | Stack | Short |
|------|-------|-------|
| `SCR-NEW` | `( w h -- scr )` | Create screen |
| `SCR-FREE` | `( scr -- )` | Destroy screen |
| `SCR-USE` | `( scr -- )` | Set current |
| `SCR-W` | `( -- w )` | Get width |
| `SCR-H` | `( -- h )` | Get height |
| `SCR-SET` | `( cell row col -- )` | Write back buf |
| `SCR-GET` | `( row col -- cell )` | Read back buf |
| `SCR-FRONT@` | `( row col -- cell )` | Read front buf |
| `SCR-FILL` | `( cell -- )` | Fill back buf |
| `SCR-CLEAR` | `( -- )` | Clear to blank |
| `SCR-FLUSH` | `( -- )` | Diff → ANSI |
| `SCR-FORCE` | `( -- )` | Mark all dirty |
| `SCR-RESIZE` | `( w h -- )` | Reallocate |
| `SCR-CURSOR-AT` | `( row col -- )` | Set cursor pos |
| `SCR-CURSOR-ON` | `( -- )` | Show cursor |
| `SCR-CURSOR-OFF` | `( -- )` | Hide cursor |
