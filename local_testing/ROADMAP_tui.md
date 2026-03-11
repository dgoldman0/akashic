# Terminal UI Library — Roadmap

A modular terminal user-interface toolkit for KDOS / Megapad-64,
layered on top of the existing `EMIT` / `KEY` / `TYPE` UART
primitives, the string library, and the concurrency scheduler.

KDOS already has the low-level byte I/O.  What it lacks is everything
above that: ANSI escape sequence generation, cursor management, screen
abstraction, character-cell buffers, input decoding, layout containers,
interactive widgets, and a component lifecycle.  This roadmap builds
those layers from the bottom up, following the same modular decomposition
pattern used throughout Akashic — each file is an independent vocabulary
with its own prefix, `PROVIDED` guard, explicit `REQUIRE` dependencies,
and no circular imports.

**Date:** 2026-03-11
**Status:** Living document

---

## Table of Contents

- [Current State — What KDOS Already Has](#current-state--what-kdos-already-has)
- [What's Missing](#whats-missing)
- [Architecture Principles](#architecture-principles)
- [Architecture Overview](#architecture-overview)
- [Layer 0 — Terminal Escape Sequences](#layer-0--terminal-escape-sequences)
  - [0.1 tui/ansi.f — ANSI Escape Code Emitter](#01-tuiansif--ansi-escape-code-emitter)
  - [0.2 tui/keys.f — Input Decoding](#02-tuikeysf--input-decoding)
- [Layer 1 — Screen Abstraction](#layer-1--screen-abstraction)
  - [1.1 tui/cell.f — Character Cell Type](#11-tuicellf--character-cell-type)
  - [1.2 tui/screen.f — Virtual Screen Buffer](#12-tuiscreenf--virtual-screen-buffer)
- [Layer 2 — Drawing Primitives](#layer-2--drawing-primitives)
  - [2.1 tui/draw.f — Cell-Level Drawing](#21-tuidrawf--cell-level-drawing)
  - [2.2 tui/box.f — Box Drawing & Borders](#22-tuiboxf--box-drawing--borders)
- [Layer 3 — Layout Engine](#layer-3--layout-engine)
  - [3.1 tui/region.f — Rectangular Regions](#31-tuiregionf--rectangular-regions)
  - [3.2 tui/layout.f — Container Layout](#32-tuilayoutf--container-layout)
- [Layer 4 — Widgets](#layer-4--widgets)
  - [4.1 tui/label.f — Static Text Labels](#41-tuilabelf--static-text-labels)
  - [4.2 tui/input.f — Text Input Field](#42-tuiinputf--text-input-field)
  - [4.3 tui/list.f — Scrollable List](#43-tuilistf--scrollable-list)
  - [4.4 tui/menu.f — Menu Bar & Dropdown Menus](#44-tuimenuf--menu-bar--dropdown-menus)
  - [4.5 tui/progress.f — Progress Bar & Spinner](#45-tuiprogressf--progress-bar--spinner)
  - [4.6 tui/table.f — Tabular Data Display](#46-tuitablef--tabular-data-display)
  - [4.7 tui/dialog.f — Modal Dialog Boxes](#47-tuidialogyf--modal-dialog-boxes)
  - [4.8 tui/tabs.f — Tabbed Panels](#48-tuitabsf--tabbed-panels)
- [Layer 5 — Application Shell](#layer-5--application-shell)
  - [5.1 tui/event.f — Event Loop & Dispatch](#51-tuieventf--event-loop--dispatch)
  - [5.2 tui/focus.f — Focus Manager](#52-tuifocusf--focus-manager)
  - [5.3 tui/app.f — Application Lifecycle](#53-tuiappf--application-lifecycle)
- [Layer 6 — Extended Components](#layer-6--extended-components)
  - [6.1 tui/split.f — Split Panes](#61-tuisplitf--split-panes)
  - [6.2 tui/scroll.f — Scrollable Viewport](#62-tuiscrollf--scrollable-viewport)
  - [6.3 tui/tree.f — Tree View](#63-tuitreef--tree-view)
  - [6.4 tui/status.f — Status Bar](#64-tuistatusf--status-bar)
  - [6.5 tui/toast.f — Transient Notifications](#65-tuitoastf--transient-notifications)
  - [6.6 tui/canvas.f — Character-Mode Canvas](#66-tuicanvasf--character-mode-canvas)
- [Dependency Graph](#dependency-graph)
- [Implementation Order](#implementation-order)
- [Memory Budget](#memory-budget)
- [Design Constraints](#design-constraints)
- [Testing Strategy](#testing-strategy)
- [Known Limitations](#known-limitations)
- [Future Extensions](#future-extensions)

---

## Current State — What KDOS Already Has

### BIOS Terminal I/O (kdos.f)

The Megapad-64 UART is a byte-serial console.  KDOS exposes the
standard ANS Forth console words:

| Word | Stack | Description |
|------|-------|-------------|
| `EMIT` | `( char -- )` | Send one byte to UART |
| `TYPE` | `( addr len -- )` | Send a string to UART |
| `KEY` | `( -- char )` | Read one byte from UART (blocking) |
| `KEY?` | `( -- flag )` | Non-blocking key check |
| `CR` | `( -- )` | Emit newline (LF or CR+LF) |
| `SPACE` | `( -- )` | Emit 0x20 |
| `SPACES` | `( n -- )` | Emit n spaces |
| `.` | `( n -- )` | Print number + space |
| `."` | (compile) | Print inline string literal |

No `AT-XY`, `PAGE`, `ROWS`, `COLS`, or any cursor/screen words exist.

### Relevant Akashic Libraries

| Library | File | Lines | Relevance |
|---------|------|-------|-----------|
| akashic-string | `utils/string.f` | 421 | String comparison, search, split, trim, case convert, num↔str |
| akashic-fmt | `utils/fmt.f` | 208 | Hex formatting, hex dump — pattern for output formatting |
| akashic-utf8 | `text/utf8.f` | ~200 | UTF-8 encode/decode, codepoint iteration |
| akashic-table | `utils/table.f` | ~200 | Fixed-stride slot allocator — could back cell buffers |
| akashic-json | `utils/json.f` | 873 | Vectored output pattern (`JSON-EMIT-XT`/`JSON-TYPE-XT`) |
| akashic-event | `concurrency/event.f` | ~300 | EVT-WAIT / EVT-NOTIFY for blocking I/O |
| akashic-channel | `concurrency/channel.f` | ~350 | Bounded channels for input event queuing |
| **Total** | | **~2,550** | |

### What This Gives Us

```
Keyboard byte ──► KEY / KEY? ──► raw byte (no decode)
                                    │
                                    ▼
                              (nothing)

Text output ──► EMIT / TYPE ──► raw bytes to UART
                                    │
                                    ▼
                              (nothing — no positioning,
                               no color, no screen model)
```

---

## What's Missing

KDOS has no:

- **ANSI escape sequence emitter** — cursor movement, color, clear, scroll
- **Input decoder** — arrow keys, function keys, mouse, bracketed paste
- **Screen model** — dimensions, character cell buffer, dirty tracking
- **Differential update** — intelligent flush (only changed cells)
- **Box drawing** — borders, frames, line characters
- **Layout engine** — regions, splits, flow containers
- **Widgets** — text fields, lists, menus, progress bars, tables, dialogs
- **Focus management** — tab order, focus ring, keyboard navigation
- **Event loop** — unified input polling + timer ticks + redraw cycle
- **Application lifecycle** — init/run/teardown, alternate screen, raw mode

All terminal output is currently linear (append-only to a scrolling
log).  There is no concept of a "screen" you can address by row and
column.

---

## Architecture Principles

1. **EMIT is the only output primitive.**  Every escape sequence,
   every positioned character, every color change ultimately goes
   through `EMIT` or `TYPE`.  No new BIOS dependencies.

2. **Double-buffered screen.**  A `SCREEN` holds two cell arrays
   (front and back).  Widgets draw to the back buffer.  Flush
   diffs the two and emits only what changed — minimizing bytes
   over a serial link.

3. **Widgets don't EMIT directly.**  They write cells into a
   region of the back buffer.  Only the flush step touches the
   UART.  This enables compositing, clipping, and z-ordering
   without interleaved output.

4. **Input is an event stream.**  Raw bytes from `KEY` are decoded
   into structured events (character, special key, resize, mouse)
   and dispatched through a focused widget chain.

5. **Composition over inheritance.**  Widgets are descriptors with
   function-pointer fields (draw-xt, handle-xt), not a class
   hierarchy.  Complex UIs compose simple widgets inside regions.

6. **Build on existing libraries.**  String manipulation uses
   `akashic-string`.  UTF-8 uses `akashic-utf8`.  Event blocking
   uses `akashic-event`.  No reinvention.

7. **Prefix convention.**  Each file gets its own prefix:
   - `tui/ansi.f`     → `ANSI-`
   - `tui/keys.f`     → `KEY-`
   - `tui/cell.f`     → `CELL-`
   - `tui/screen.f`   → `SCR-`
   - `tui/draw.f`     → `DRW-`
   - `tui/box.f`      → `BOX-`
   - `tui/region.f`   → `RGN-`
   - `tui/layout.f`   → `LAY-`
   - `tui/label.f`    → `LBL-`
   - `tui/input.f`    → `INP-`
   - `tui/list.f`     → `LST-`
   - `tui/menu.f`     → `MNU-`
   - `tui/progress.f` → `PRG-`
   - `tui/table.f`    → `TBL-`
   - `tui/dialog.f`   → `DLG-`
   - `tui/tabs.f`     → `TAB-`
   - `tui/event.f`    → `TUI-EVT-`
   - `tui/focus.f`    → `FOC-`
   - `tui/app.f`      → `APP-`
   - `tui/split.f`    → `SPL-`
   - `tui/scroll.f`   → `SCRL-`
   - `tui/tree.f`     → `TREE-`
   - `tui/status.f`   → `SBAR-`
   - `tui/toast.f`    → `TST-`
   - `tui/canvas.f`   → `CVS-`

   Internal words use `_`-prefix: `_ANSI-`, `_SCR-`, etc.

8. **PROVIDED guards.**  Every file starts with:
   ```forth
   PROVIDED akashic-tui-ansi  ( or whatever the module name is )
   ```
   Preventing double-load.  `REQUIRE` pulls dependencies.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                       Application                            │
├──────────────────────────────────────────────────────────────┤
│  Layer 6: Extended Components                                │
│  split.f │ scroll.f │ tree.f │ status.f │ toast.f │ canvas.f│
├──────────────────────────────────────────────────────────────┤
│  Layer 5: Application Shell                                  │
│  event.f (loop) │ focus.f (focus chain) │ app.f (lifecycle)  │
├──────────────────────────────────────────────────────────────┤
│  Layer 4: Widgets                                            │
│  label │ input │ list │ menu │ progress │ table │ dialog│tabs│
├──────────────────────────────────────────────────────────────┤
│  Layer 3: Layout Engine                                      │
│  region.f (clip rectangles) │ layout.f (flow containers)     │
├──────────────────────────────────────────────────────────────┤
│  Layer 2: Drawing Primitives                                 │
│  draw.f (fill, hline, vline, text) │ box.f (frames, borders) │
├──────────────────────────────────────────────────────────────┤
│  Layer 1: Screen Abstraction                                 │
│  cell.f (char+attr type) │ screen.f (double buffer, flush)   │
├──────────────────────────────────────────────────────────────┤
│  Layer 0: Terminal Escape Sequences                          │
│  ansi.f (CSI emitter) │ keys.f (input decoder)               │
├──────────────────────────────────────────────────────────────┤
│  KDOS BIOS: EMIT │ KEY │ KEY? │ TYPE │ CR                    │
├──────────────────────────────────────────────────────────────┤
│  Existing Akashic: string.f │ utf8.f │ fmt.f │ event.f       │
└──────────────────────────────────────────────────────────────┘
```

---

## Layer 0 — Terminal Escape Sequences

### 0.1 tui/ansi.f — ANSI Escape Code Emitter

**Goal:** Provide named words for all standard ANSI/VT100 escape
sequences.  Every word is a thin wrapper around `EMIT` / `TYPE`
that emits the correct CSI byte sequences.  No state, no buffers —
pure output.

File: `tui/ansi.f`
Prefix: `ANSI-` (public), `_ANSI-` (internal)
Provider: `PROVIDED akashic-tui-ansi`
Dependencies: none (uses only EMIT / TYPE from KDOS BIOS)

~250 lines

#### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `ANSI-ESC` | 27 | Escape character (0x1B) |
| `ANSI-CSI` | — | Emits ESC [ (2 bytes) |

#### Cursor Movement

| Word | Stack | Description |
|------|-------|-------------|
| `ANSI-AT` | `( row col -- )` | Move cursor to row,col (1-based) — `ESC[row;colH` |
| `ANSI-UP` | `( n -- )` | Move cursor up n rows — `ESC[nA` |
| `ANSI-DOWN` | `( n -- )` | Move cursor down n rows — `ESC[nB` |
| `ANSI-RIGHT` | `( n -- )` | Move cursor right n cols — `ESC[nC` |
| `ANSI-LEFT` | `( n -- )` | Move cursor left n cols — `ESC[nD` |
| `ANSI-HOME` | `( -- )` | Cursor to top-left — `ESC[H` |
| `ANSI-COL` | `( n -- )` | Move to column n — `ESC[nG` |
| `ANSI-SAVE` | `( -- )` | Save cursor position — `ESC[s` |
| `ANSI-RESTORE` | `( -- )` | Restore cursor position — `ESC[u` |

#### Screen Clearing

| Word | Stack | Description |
|------|-------|-------------|
| `ANSI-CLEAR` | `( -- )` | Clear entire screen — `ESC[2J` |
| `ANSI-CLEAR-EOL` | `( -- )` | Clear to end of line — `ESC[K` |
| `ANSI-CLEAR-BOL` | `( -- )` | Clear to beginning of line — `ESC[1K` |
| `ANSI-CLEAR-LINE` | `( -- )` | Clear entire line — `ESC[2K` |
| `ANSI-CLEAR-EOS` | `( -- )` | Clear to end of screen — `ESC[J` |
| `ANSI-CLEAR-BOS` | `( -- )` | Clear to beginning of screen — `ESC[1J` |

#### Scrolling

| Word | Stack | Description |
|------|-------|-------------|
| `ANSI-SCROLL-UP` | `( n -- )` | Scroll up n lines — `ESC[nS` |
| `ANSI-SCROLL-DN` | `( n -- )` | Scroll down n lines — `ESC[nT` |
| `ANSI-SCROLL-RGN` | `( top bot -- )` | Set scroll region — `ESC[top;botr` |
| `ANSI-SCROLL-RESET` | `( -- )` | Reset scroll region — `ESC[r` |

#### Text Attributes

| Word | Stack | Description |
|------|-------|-------------|
| `ANSI-RESET` | `( -- )` | Reset all attributes — `ESC[0m` |
| `ANSI-BOLD` | `( -- )` | Bold on — `ESC[1m` |
| `ANSI-DIM` | `( -- )` | Dim on — `ESC[2m` |
| `ANSI-ITALIC` | `( -- )` | Italic on — `ESC[3m` |
| `ANSI-UNDERLINE` | `( -- )` | Underline on — `ESC[4m` |
| `ANSI-BLINK` | `( -- )` | Blink on — `ESC[5m` |
| `ANSI-REVERSE` | `( -- )` | Reverse video — `ESC[7m` |
| `ANSI-HIDDEN` | `( -- )` | Hidden text — `ESC[8m` |
| `ANSI-STRIKE` | `( -- )` | Strikethrough — `ESC[9m` |
| `ANSI-NORMAL` | `( -- )` | Remove bold/dim — `ESC[22m` |

#### Colors — Standard 16

| Word | Stack | Description |
|------|-------|-------------|
| `ANSI-FG` | `( color -- )` | Set foreground (0–7) — `ESC[30+colorm` |
| `ANSI-BG` | `( color -- )` | Set background (0–7) — `ESC[40+colorm` |
| `ANSI-FG-BRIGHT` | `( color -- )` | Bright foreground (0–7) — `ESC[90+colorm` |
| `ANSI-BG-BRIGHT` | `( color -- )` | Bright background (0–7) — `ESC[100+colorm` |

Color constants: `ANSI-BLACK` (0), `ANSI-RED` (1), `ANSI-GREEN` (2),
`ANSI-YELLOW` (3), `ANSI-BLUE` (4), `ANSI-MAGENTA` (5),
`ANSI-CYAN` (6), `ANSI-WHITE` (7).

#### Colors — 256 and True-Color

| Word | Stack | Description |
|------|-------|-------------|
| `ANSI-FG256` | `( n -- )` | 256-color foreground — `ESC[38;5;nm` |
| `ANSI-BG256` | `( n -- )` | 256-color background — `ESC[48;5;nm` |
| `ANSI-FG-RGB` | `( r g b -- )` | True-color foreground — `ESC[38;2;r;g;bm` |
| `ANSI-BG-RGB` | `( r g b -- )` | True-color background — `ESC[48;2;r;g;bm` |
| `ANSI-DEFAULT-FG` | `( -- )` | Reset foreground — `ESC[39m` |
| `ANSI-DEFAULT-BG` | `( -- )` | Reset background — `ESC[49m` |

#### Terminal Modes

| Word | Stack | Description |
|------|-------|-------------|
| `ANSI-ALT-ON` | `( -- )` | Enter alternate screen — `ESC[?1049h` |
| `ANSI-ALT-OFF` | `( -- )` | Leave alternate screen — `ESC[?1049l` |
| `ANSI-CURSOR-ON` | `( -- )` | Show cursor — `ESC[?25h` |
| `ANSI-CURSOR-OFF` | `( -- )` | Hide cursor — `ESC[?25l` |
| `ANSI-MOUSE-ON` | `( -- )` | Enable mouse reporting — `ESC[?1006h` (SGR mode) |
| `ANSI-MOUSE-OFF` | `( -- )` | Disable mouse reporting — `ESC[?1006l` |
| `ANSI-PASTE-ON` | `( -- )` | Enable bracketed paste — `ESC[?2004h` |
| `ANSI-PASTE-OFF` | `( -- )` | Disable bracketed paste — `ESC[?2004l` |
| `ANSI-QUERY-SIZE` | `( -- )` | Request terminal size — `ESC[18t` |

#### Helpers

| Word | Stack | Description |
|------|-------|-------------|
| `_ANSI-NUM` | `( n -- )` | Emit decimal number (no leading zeros) |
| `_ANSI-SEP` | `( -- )` | Emit `;` separator |

#### Algorithm Notes

All words are stateless — they emit escape bytes immediately via
`EMIT`.  No buffering, no string allocation.  The CSI prefix
(`ESC [`) is 2 bytes; most sequences are 4–8 bytes total.

`_ANSI-NUM` converts an integer to decimal digits and emits them
one at a time via `EMIT`.  For single-digit numbers (the common case
for colors and small movements) this is 1 byte.

#### Test targets: ~40 tests

- Cursor movement in all directions, wrap-around verification
- Each clear mode
- All 16 standard colors, 256-color, true-color
- Attribute stacking and reset
- Alternate screen enter/leave
- Mouse and paste mode toggles
- Number formatting edge cases (0, 1, 99, 255)

---

### 0.2 tui/keys.f — Input Decoding

**Goal:** Decode raw UART bytes into structured key events.  Arrow
keys, function keys, Home/End/PgUp/PgDn, mouse clicks, and
bracketed paste boundaries all arrive as multi-byte escape sequences.
This module buffers partial sequences and resolves them into named
constants.

File: `tui/keys.f`
Prefix: `KEY-` (public), `_KEY-` (internal)
Provider: `PROVIDED akashic-tui-keys`
Dependencies: `REQUIRE ../text/utf8.f`

~350 lines

#### Key Event Descriptor (3 cells = 24 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | type | Event type: `KEY-T-CHAR`, `KEY-T-SPECIAL`, `KEY-T-MOUSE`, `KEY-T-PASTE`, `KEY-T-RESIZE` |
| +8 | code | Character codepoint, special key constant, or mouse button |
| +16 | mods | Modifier bitmask: `KEY-MOD-SHIFT` (1), `KEY-MOD-ALT` (2), `KEY-MOD-CTRL` (4) |

For mouse events, `code` encodes button (bits 0–2), and two VARIABLEs
`KEY-MOUSE-X` / `KEY-MOUSE-Y` hold the column/row (SGR 1006 format).

For resize events, `code` is 0 and `KEY-RESIZE-W` / `KEY-RESIZE-H`
hold the new dimensions.

#### Constants — Event Types

| Constant | Value | Description |
|----------|-------|-------------|
| `KEY-T-CHAR` | 0 | Printable character or Ctrl combo |
| `KEY-T-SPECIAL` | 1 | Named key (arrow, F1–F12, etc.) |
| `KEY-T-MOUSE` | 2 | Mouse button/motion event |
| `KEY-T-PASTE` | 3 | Bracketed paste start/end |
| `KEY-T-RESIZE` | 4 | Terminal size changed |

#### Constants — Special Keys

| Constant | Value |
|----------|-------|
| `KEY-UP` | 1 |
| `KEY-DOWN` | 2 |
| `KEY-RIGHT` | 3 |
| `KEY-LEFT` | 4 |
| `KEY-HOME` | 5 |
| `KEY-END` | 6 |
| `KEY-PGUP` | 7 |
| `KEY-PGDN` | 8 |
| `KEY-INS` | 9 |
| `KEY-DEL` | 10 |
| `KEY-F1` .. `KEY-F12` | 11–22 |
| `KEY-ESC` | 23 |
| `KEY-TAB` | 24 |
| `KEY-BACKTAB` | 25 |
| `KEY-ENTER` | 26 |
| `KEY-BACKSPACE` | 27 |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `KEY-READ` | `( event-addr -- flag )` | Read next event into descriptor; returns TRUE if event available, FALSE on timeout |
| `KEY-POLL` | `( event-addr -- flag )` | Non-blocking check; fills event if available |
| `KEY-WAIT` | `( event-addr timeout-ms -- flag )` | Blocking read with timeout (0 = forever) |
| `KEY-IS-CHAR?` | `( event-addr -- flag )` | Is this a character event? |
| `KEY-IS-SPECIAL?` | `( event-addr -- flag )` | Is this a special key event? |
| `KEY-IS-MOUSE?` | `( event-addr -- flag )` | Is this a mouse event? |
| `KEY-CODE@` | `( event-addr -- code )` | Get keycode from event |
| `KEY-MODS@` | `( event-addr -- mods )` | Get modifiers from event |
| `KEY-HAS-CTRL?` | `( event-addr -- flag )` | Ctrl modifier present? |
| `KEY-HAS-ALT?` | `( event-addr -- flag )` | Alt modifier present? |
| `KEY-HAS-SHIFT?` | `( event-addr -- flag )` | Shift modifier present? |
| `KEY-TIMEOUT!` | `( ms -- )` | Set default escape sequence timeout (default: 50 ms) |

#### Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_KEY-BUF` | — | 8-byte internal buffer for multi-byte sequences |
| `_KEY-FILL` | `( -- n )` | Buffer raw bytes from KEY until timeout or complete sequence |
| `_KEY-DECODE-CSI` | `( -- type code mods )` | Parse CSI sequence from buffer |
| `_KEY-DECODE-SS3` | `( -- type code mods )` | Parse SS3 sequence (some F-keys, keypad) |
| `_KEY-DECODE-MOUSE` | `( -- type code mods )` | Parse SGR mouse report |
| `_KEY-DECODE-UTF8` | `( byte -- type code mods )` | Accumulate multi-byte UTF-8 codepoint |

#### Algorithm Notes

When `KEY` returns `ESC` (27), the decoder enters a timed read:
if no further byte arrives within the timeout (default 50 ms via
`KEY?` polling), it's a literal Escape keypress.  If `[` follows,
it's a CSI sequence.  If `O` follows, it's an SS3 sequence.

The decoder is a synchronous state machine — no background task
required.  `KEY-READ` blocks on `KEY` but checks `KEY?` during
escape timeout windows.  The timeout is tunable for high-latency
serial links.

UTF-8 multi-byte characters are accumulated using `UTF8-BYTE-LEN`
from `akashic-utf8` to determine the expected sequence length, then
read byte-by-byte via `KEY`.

Mouse events in SGR mode (`ESC[<btn;col;rowM` or `m`) are parsed
by `_KEY-DECODE-MOUSE`.  Button, column, and row are extracted as
integers.  Press = `M`, release = `m`.

#### Test targets: ~35 tests

- Single printable character (ASCII, multi-byte UTF-8)
- Ctrl+letter combinations
- Arrow keys, Home/End, PgUp/PgDn
- F1–F12 in CSI and SS3 variants
- Modifier-augmented keys (Shift+Up, Ctrl+Left, Alt+F1)
- Escape timeout: standalone Escape vs. start of sequence
- SGR mouse reports (press, release, motion)
- Bracketed paste boundaries
- Resize report parsing
- Malformed / truncated sequences (graceful fallback)

---

## Layer 1 — Screen Abstraction

### 1.1 tui/cell.f — Character Cell Type

**Goal:** Define the character cell as a packed data type — one
codepoint, one foreground color, one background color, and attribute
flags.  This is the "pixel" of the terminal UI, analogous to
RGBA8888 in the render pipeline.

File: `tui/cell.f`
Prefix: `CELL-` (public), `_CELL-` (internal)
Provider: `PROVIDED akashic-tui-cell`
Dependencies: none

~120 lines

#### Cell Encoding (1 cell = 8 bytes)

```
Bits 63       48 47      40 39      32 31          0
     ┌─────────┬──────────┬──────────┬──────────────┐
     │  attrs  │   bg     │   fg     │  codepoint   │
     │ 16 bits │  8 bits  │  8 bits  │   32 bits    │
     └─────────┴──────────┴──────────┴──────────────┘
```

- **codepoint** (bits 0–31): Unicode codepoint.  0 = empty cell.
- **fg** (bits 32–39): Foreground color index (0–255, 256-palette).
- **bg** (bits 40–47): Background color index (0–255, 256-palette).
- **attrs** (bits 48–63): Attribute flags.

This packs neatly into a single Megapad-64 cell (8 bytes), so a
screen buffer is a flat array where each position is one `@` / `!`.

#### Attribute Flags (bits 48–63)

| Bit | Constant | Description |
|-----|----------|-------------|
| 48 | `CELL-A-BOLD` | Bold / bright |
| 49 | `CELL-A-DIM` | Dim / faint |
| 50 | `CELL-A-ITALIC` | Italic |
| 51 | `CELL-A-UNDERLINE` | Underline |
| 52 | `CELL-A-BLINK` | Blink |
| 53 | `CELL-A-REVERSE` | Reverse video |
| 54 | `CELL-A-STRIKE` | Strikethrough |
| 55 | `CELL-A-WIDE` | Wide character (this cell is left half) |
| 56 | `CELL-A-CONT` | Continuation cell (right half of wide char) |
| 57–63 | — | Reserved |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `CELL-MAKE` | `( cp fg bg attrs -- cell )` | Pack a cell value |
| `CELL-CP@` | `( cell -- cp )` | Extract codepoint |
| `CELL-FG@` | `( cell -- fg )` | Extract foreground |
| `CELL-BG@` | `( cell -- bg )` | Extract background |
| `CELL-ATTRS@` | `( cell -- attrs )` | Extract attributes |
| `CELL-FG!` | `( fg cell -- cell' )` | Replace foreground |
| `CELL-BG!` | `( bg cell -- cell' )` | Replace background |
| `CELL-ATTRS!` | `( attrs cell -- cell' )` | Replace attributes |
| `CELL-BLANK` | `( -- cell )` | Space, default fg/bg, no attrs |
| `CELL-EQUAL?` | `( a b -- flag )` | Compare two cells |
| `CELL-EMPTY?` | `( cell -- flag )` | Codepoint is 0 or space, default colors? |

#### Test targets: ~15 tests

- Pack/unpack round-trip for all fields
- Attribute flag setting and clearing
- Wide-character flag semantics
- Blank and empty predicates
- Edge cases: codepoint 0, max codepoint, all attrs set

---

### 1.2 tui/screen.f — Virtual Screen Buffer

**Goal:** Double-buffered character-cell screen.  Widgets write to
the back buffer.  `SCR-FLUSH` diffs front vs. back and emits only
changed cells via ANSI sequences.  This is the central coordination
point — all drawing goes through the screen, and all output goes
through flush.

File: `tui/screen.f`
Prefix: `SCR-` (public), `_SCR-` (internal)
Provider: `PROVIDED akashic-tui-screen`
Dependencies: `REQUIRE cell.f`, `REQUIRE ansi.f`, `REQUIRE ../text/utf8.f`

~400 lines

#### Screen Descriptor (8 cells = 64 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | width | Columns |
| +8 | height | Rows |
| +16 | front | Address of front buffer (width × height cells) |
| +24 | back | Address of back buffer (width × height cells) |
| +32 | cursor-row | Current cursor row (0-based) |
| +40 | cursor-col | Current cursor column (0-based) |
| +48 | cursor-vis | Cursor visible? (0/1) |
| +56 | dirty | Global dirty flag (optimization hint) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `SCR-NEW` | `( w h -- scr )` | Allocate screen descriptor + two cell buffers |
| `SCR-FREE` | `( scr -- )` | Deallocate screen and buffers |
| `SCR-USE` | `( scr -- )` | Set as current screen (for drawing words) |
| `SCR-W` | `( -- w )` | Current screen width |
| `SCR-H` | `( -- h )` | Current screen height |
| `SCR-SET` | `( cell row col -- )` | Write cell to back buffer at (row, col) |
| `SCR-GET` | `( row col -- cell )` | Read cell from back buffer |
| `SCR-FILL` | `( cell -- )` | Fill entire back buffer with cell |
| `SCR-CLEAR` | `( -- )` | Fill back buffer with CELL-BLANK |
| `SCR-FLUSH` | `( -- )` | Diff front vs back, emit ANSI for changes, copy back→front |
| `SCR-FORCE` | `( -- )` | Force full redraw (mark all cells dirty) |
| `SCR-RESIZE` | `( w h -- )` | Resize screen buffers (reallocate if needed) |
| `SCR-CURSOR-AT` | `( row col -- )` | Set logical cursor position |
| `SCR-CURSOR-ON` | `( -- )` | Show cursor on next flush |
| `SCR-CURSOR-OFF` | `( -- )` | Hide cursor on next flush |

#### Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_SCR-IDX` | `( row col -- offset )` | Convert (row, col) to buffer index |
| `_SCR-EMIT-CELL` | `( cell row col -- )` | Position cursor + emit cell via ANSI |
| `_SCR-EMIT-ATTRS` | `( prev-cell cell -- )` | Emit only changed attributes (diff) |
| `_SCR-FLUSH-ROW` | `( row -- )` | Diff and flush one row |

#### Algorithm Notes

`SCR-FLUSH` iterates every cell.  For each position where
`front[i] ≠ back[i]`, it emits:

1. `ANSI-AT` to position the cursor (only if not already there —
   track logical cursor to avoid redundant positioning)
2. Attribute/color changes (only the diff from the last emitted cell)
3. The character (UTF-8 encoded via `UTF8-ENCODE`)

After flushing, `back` is copied to `front` cell-by-cell.  The
optimization is critical: a typical 80×24 screen is 1,920 cells.
On a 115,200 baud serial link, sending all 1,920 cells with
positioning would take ~50 ms.  Differential flush keeps interactive
updates under 5 ms for typical UI changes.

**Row-coalescing optimization:** When consecutive cells in a row are
all dirty and share the same attributes, emit them as a single
`TYPE` call rather than individual `EMIT` + position calls.

#### Memory

Each cell is 8 bytes.  Two buffers:
- 80×24 = 1,920 cells × 8 bytes × 2 = **30,720 bytes** (~30 KiB)
- 132×50 = 6,600 cells × 8 bytes × 2 = **105,600 bytes** (~103 KiB)
- 200×60 = 12,000 cells × 8 bytes × 2 = **192,000 bytes** (~188 KiB)

All fit comfortably in XMEM (16 MiB available).

#### Test targets: ~30 tests

- Create/free, fill, clear
- Set/get round-trip
- Flush outputs correct ANSI for single cell change
- Flush skips unchanged cells
- Row coalescing (consecutive dirty cells)
- Cursor positioning (correct AT-XY emitted)
- Cursor show/hide
- Resize (old content preserved where possible)
- Full redraw after SCR-FORCE

---

## Layer 2 — Drawing Primitives

### 2.1 tui/draw.f — Cell-Level Drawing

**Goal:** Convenience words for common drawing operations on the
back buffer: horizontal and vertical lines, filled rectangles,
text strings placed at a position.  These operate on the current
screen (set via `SCR-USE`).

File: `tui/draw.f`
Prefix: `DRW-` (public), `_DRW-` (internal)
Provider: `PROVIDED akashic-tui-draw`
Dependencies: `REQUIRE screen.f`, `REQUIRE ../text/utf8.f`

~200 lines

#### Style State

Drawing words pick up the "current style" — a foreground, background,
and attribute set.  This avoids passing 3 extra values on every call.

| Word | Stack | Description |
|------|-------|-------------|
| `DRW-FG!` | `( fg -- )` | Set drawing foreground |
| `DRW-BG!` | `( bg -- )` | Set drawing background |
| `DRW-ATTR!` | `( attrs -- )` | Set drawing attributes |
| `DRW-STYLE!` | `( fg bg attrs -- )` | Set all three |
| `DRW-STYLE-RESET` | `( -- )` | Reset to default (7, 0, 0) |

#### Drawing Words

| Word | Stack | Description |
|------|-------|-------------|
| `DRW-CHAR` | `( cp row col -- )` | Place one character at position |
| `DRW-TEXT` | `( addr len row col -- )` | Place UTF-8 string at position (clipped to screen) |
| `DRW-HLINE` | `( cp row col len -- )` | Horizontal line of character cp |
| `DRW-VLINE` | `( cp row col len -- )` | Vertical line of character cp |
| `DRW-FILL-RECT` | `( cp row col h w -- )` | Fill rectangle with character |
| `DRW-CLEAR-RECT` | `( row col h w -- )` | Clear rectangle to blanks |
| `DRW-TEXT-CENTER` | `( addr len row col w -- )` | Center text within width |
| `DRW-TEXT-RIGHT` | `( addr len row col w -- )` | Right-align text within width |
| `DRW-REPEAT` | `( cp row col n -- )` | Synonym for DRW-HLINE (convenience) |

#### Test targets: ~20 tests

- Text placement, clipping at screen edges
- Horizontal/vertical lines
- Filled/cleared rectangles
- Centered/right-aligned text
- UTF-8 multi-byte characters
- Zero-length, zero-area edge cases

---

### 2.2 tui/box.f — Box Drawing & Borders

**Goal:** Draw rectangular borders and frames using Unicode box-drawing
characters.  Multiple border styles.  Composable with draw.f — boxes
are drawn into the same back buffer.

File: `tui/box.f`
Prefix: `BOX-` (public), `_BOX-` (internal)
Provider: `PROVIDED akashic-tui-box`
Dependencies: `REQUIRE draw.f`

~180 lines

#### Border Styles

Each style is a descriptor containing 8 codepoints:

```
Offset  Character   Example (single)  Example (double)
  +0    top-left    ┌ (0x250C)        ╔ (0x2554)
  +8    top-right   ┐ (0x2510)        ╗ (0x2557)
 +16    bot-left    └ (0x2514)        ╚ (0x255A)
 +24    bot-right   ┘ (0x2518)        ╝ (0x255D)
 +32    horizontal  ─ (0x2500)        ═ (0x2550)
 +40    vertical    │ (0x2502)        ║ (0x2551)
 +48    t-left      ├ (0x251C)        ╠ (0x2560)
 +56    t-right     ┤ (0x2524)        ╣ (0x2563)
```

Pre-defined style descriptors:

| Constant | Description |
|----------|-------------|
| `BOX-SINGLE` | Single-line box: `┌─┐│└─┘` |
| `BOX-DOUBLE` | Double-line box: `╔═╗║╚═╝` |
| `BOX-ROUND` | Rounded corners: `╭─╮│╰─╯` |
| `BOX-HEAVY` | Heavy lines: `┏━┓┃┗━┛` |
| `BOX-ASCII` | ASCII fallback: `+-+|+-+` |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `BOX-DRAW` | `( style row col h w -- )` | Draw border rectangle |
| `BOX-DRAW-TITLED` | `( style title-a title-u row col h w -- )` | Border with title in top edge |
| `BOX-HLINE` | `( style row col w -- )` | Draw horizontal rule using style's horizontal char |
| `BOX-VLINE` | `( style row col h -- )` | Draw vertical rule using style's vertical char |
| `BOX-SHADOW` | `( row col h w -- )` | Draw a drop shadow (dim block chars) along right and bottom edges |

#### Test targets: ~15 tests

- Each border style renders correct characters
- Titled boxes with long/short/empty titles
- Minimum size boxes (1×1, 2×2, 3×3)
- Shadow rendering
- Custom style creation

---

## Layer 3 — Layout Engine

### 3.1 tui/region.f — Rectangular Regions

**Goal:** A region is a clipping rectangle within the screen.
Widgets draw into regions; the region clips all cell writes to its
bounds.  Regions can be nested (child region within parent).  This
provides the spatial containment model.

File: `tui/region.f`
Prefix: `RGN-` (public), `_RGN-` (internal)
Provider: `PROVIDED akashic-tui-region`
Dependencies: `REQUIRE screen.f`, `REQUIRE draw.f`

210 lines

#### Region Descriptor (5 cells = 40 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | row | Top-left row (screen-absolute) |
| +8 | col | Top-left column (screen-absolute) |
| +16 | height | Height in rows |
| +24 | width | Width in columns |
| +32 | parent | Parent region address (0 = root) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `RGN-NEW` | `( row col h w -- rgn )` | Allocate a root region |
| `RGN-SUB` | `( parent r c h w -- rgn )` | Create sub-region (row/col relative to parent), clipped to parent bounds |
| `RGN-FREE` | `( rgn -- )` | Free region |
| `RGN-USE` | `( rgn -- )` | Set as current drawing region (draw.f words now clip to this) |
| `RGN-ROOT` | `( -- )` | Reset to full-screen root region |
| `RGN-ROW` | `( rgn -- row )` | Get absolute row |
| `RGN-COL` | `( rgn -- col )` | Get absolute column |
| `RGN-H` | `( rgn -- h )` | Get height |
| `RGN-W` | `( rgn -- w )` | Get width |
| `RGN-CONTAINS?` | `( row col -- flag )` | Is point inside current region? |
| `RGN-CLIP` | `( row col -- row' col' flag )` | Clip point to region; flag=TRUE if inside |

All `DRW-*` words, when a region is active, translate coordinates
relative to the region's top-left and clip to region bounds.  A cell
write outside the region is silently discarded.

#### Test targets: ~15 tests

- Root region spans full screen
- Sub-region clips correctly
- Nested sub-regions (grandchild within child)
- Point containment
- Drawing at region edges and outside
- Zero-size region (everything clipped)

---

### 3.2 tui/layout.f — Container Layout

**Goal:** Automatic positioning of child regions within a parent.
Three layout modes: vertical stack, horizontal stack, and fixed
positioning.  This is the terminal-UI equivalent of CSS flexbox —
simpler, but sufficient for dashboard-style layouts.

File: `tui/layout.f`
Prefix: `LAY-` (public), `_LAY-` (internal)
Provider: `PROVIDED akashic-tui-layout`
Dependencies: `REQUIRE region.f`

365 lines

#### Layout Descriptor (6 cells = 48 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | region | Region this layout manages |
| +8 | mode | `LAY-VERTICAL`, `LAY-HORIZONTAL`, `LAY-FIXED` |
| +16 | gap | Gap between children (rows or cols) |
| +24 | count | Number of children |
| +32 | children | Address of child descriptor array |
| +40 | flags | `LAY-F-EXPAND` (distribute remaining space equally) |

#### Child Descriptor (3 cells = 24 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | region | Child region (auto-created by layout engine) |
| +8 | size-hint | Requested size (rows for vertical, cols for horizontal). 0 = auto-expand. |
| +16 | min-size | Minimum size (never shrink below this) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `LAY-NEW` | `( rgn mode gap -- lay )` | Create layout over region |
| `LAY-FREE` | `( lay -- )` | Free layout + child regions |
| `LAY-ADD` | `( lay size-hint min-size -- child-rgn )` | Add child; returns its region |
| `LAY-COMPUTE` | `( lay -- )` | Recompute child positions/sizes |
| `LAY-CHILD` | `( lay n -- child-rgn )` | Get nth child region |
| `LAY-COUNT` | `( lay -- n )` | Number of children |

#### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `LAY-VERTICAL` | 0 | Stack children top-to-bottom |
| `LAY-HORIZONTAL` | 1 | Stack children left-to-right |
| `LAY-FIXED` | 2 | Children at explicit positions |
| `LAY-F-EXPAND` | 1 | flag: distribute remaining space |

#### Algorithm Notes

`LAY-COMPUTE` does a two-pass algorithm:

1. **Measure pass:** Sum all `size-hint` values + gaps.  Compute
   remaining space = parent size − total hints − total gaps.
2. **Distribute pass:** If `LAY-F-EXPAND` is set, divide remaining
   space equally among children with `size-hint = 0`.  Otherwise,
   remaining space is unused (padding at the end).

Children with `size-hint > 0` get exactly that many rows/cols.
Children with `size-hint = 0` split the remaining space.  No child
shrinks below `min-size`.

This is intentionally simpler than CSS flexbox — no grow/shrink
ratios, no wrap, no alignment.  Sufficient for 95% of terminal UIs.

#### Test targets: ~20 tests

- Vertical layout: equal split, mixed fixed+expand
- Horizontal layout: same
- Gap spacing
- Min-size enforcement
- Zero-size parent (degenerate case)
- Resize parent → recompute redistributes

---

## Layer 4 — Widgets

> **Build plan:** Layer 4 is split into three implementation sets:
>
> - **4A** — `widget.f` (shared header, constants, common words) + `label.f` + `progress.f` (~220 lines, simple foundation)
> - **4B** — `input.f` + `list.f` + `tabs.f` (~630 lines, interactive widgets)
> - **4C** — `menu.f` + `table.f` + `dialog.f` (~730 lines, complex composites)
>
> Each set gets its own commit checkpoint.

All widgets follow a uniform protocol.  A widget descriptor starts
with a common 5-cell header:

#### Widget Header (5 cells = 40 bytes, at offset +0 of every widget)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | type | Widget type constant |
| +8 | region | Region this widget occupies |
| +16 | draw-xt | Execution token: `( widget -- )` — draw into region |
| +24 | handle-xt | Execution token: `( event widget -- consumed? )` — handle input event |
| +32 | flags | `WDG-F-VISIBLE` (1), `WDG-F-FOCUSED` (2), `WDG-F-DIRTY` (4), `WDG-F-DISABLED` (8) |

Widget-specific data follows the header at +40 onwards.

The common header allows the event loop and focus manager to iterate
widgets polymorphically: call `draw-xt` to paint, call `handle-xt`
to dispatch input, check `flags` for visibility and focus state.
No `DEFER/IS` needed — function pointers in descriptors.

#### Widget Type Constants

| Constant | Value |
|----------|-------|
| `WDG-T-LABEL` | 1 |
| `WDG-T-INPUT` | 2 |
| `WDG-T-LIST` | 3 |
| `WDG-T-MENU` | 4 |
| `WDG-T-PROGRESS` | 5 |
| `WDG-T-TABLE` | 6 |
| `WDG-T-DIALOG` | 7 |
| `WDG-T-TABS` | 8 |
| `WDG-T-SPLIT` | 9 |
| `WDG-T-SCROLL` | 10 |
| `WDG-T-TREE` | 11 |
| `WDG-T-STATUS` | 12 |
| `WDG-T-TOAST` | 13 |
| `WDG-T-CANVAS` | 14 |

#### Common Widget Words

These apply to **any** widget via the common header:

| Word | Stack | Description |
|------|-------|-------------|
| `WDG-DRAW` | `( widget -- )` | Call widget's draw-xt |
| `WDG-HANDLE` | `( event widget -- consumed? )` | Call widget's handle-xt |
| `WDG-SHOW` | `( widget -- )` | Set VISIBLE flag, mark dirty |
| `WDG-HIDE` | `( widget -- )` | Clear VISIBLE flag |
| `WDG-ENABLE` | `( widget -- )` | Clear DISABLED flag |
| `WDG-DISABLE` | `( widget -- )` | Set DISABLED flag |
| `WDG-DIRTY` | `( widget -- )` | Mark widget as needing redraw |
| `WDG-DIRTY?` | `( widget -- flag )` | Is widget dirty? |
| `WDG-VISIBLE?` | `( widget -- flag )` | Is widget visible? |
| `WDG-FOCUSED?` | `( widget -- flag )` | Is widget focused? |
| `WDG-REGION` | `( widget -- rgn )` | Get widget's region |

---

### 4.1 tui/label.f — Static Text Labels

**Goal:** Display a fixed text string within a region.  Supports
single-line and multi-line text, with left/center/right alignment.
Labels are non-interactive (handle-xt is a no-op).

File: `tui/label.f`
Prefix: `LBL-` (public)
Provider: `PROVIDED akashic-tui-label`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`

~100 lines

#### Label Descriptor (header + 3 cells = 64 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-LABEL, draw-xt=_LBL-DRAW, handle-xt=NOP |
| +40 | text-addr | Address of text string |
| +48 | text-len | Length of text string |
| +56 | align | `LBL-LEFT` (0), `LBL-CENTER` (1), `LBL-RIGHT` (2) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `LBL-NEW` | `( rgn text-a text-u align -- widget )` | Create label |
| `LBL-SET-TEXT` | `( widget text-a text-u -- )` | Update text, mark dirty |
| `LBL-SET-ALIGN` | `( widget align -- )` | Change alignment |

#### Test targets: ~10 tests

- Left, center, right alignment
- Text longer than region (truncated)
- Empty text
- Multi-line text (wraps to next row)
- Update text and verify dirty flag

---

### 4.2 tui/input.f — Text Input Field

**Goal:** Single-line editable text field with cursor.  Supports
character insertion, deletion, cursor movement, and a submit
callback.

File: `tui/input.f`
Prefix: `INP-` (public), `_INP-` (internal)
Provider: `PROVIDED akashic-tui-input`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`, `REQUIRE ../text/utf8.f`

~250 lines

#### Input Descriptor (header + 8 cells = 104 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-INPUT |
| +40 | buf-addr | Address of edit buffer |
| +48 | buf-cap | Buffer capacity (bytes) |
| +56 | buf-len | Current content length (bytes) |
| +64 | cursor | Cursor position (byte offset) |
| +72 | scroll | Horizontal scroll offset (columns) |
| +80 | placeholder-a | Placeholder text address (shown when empty) |
| +88 | placeholder-u | Placeholder text length |
| +96 | submit-xt | Callback on Enter: `( widget -- )` |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `INP-NEW` | `( rgn buf cap -- widget )` | Create input field with external buffer |
| `INP-SET-TEXT` | `( widget text-a text-u -- )` | Set content programmatically |
| `INP-GET-TEXT` | `( widget -- addr len )` | Get current content |
| `INP-ON-SUBMIT` | `( widget xt -- )` | Set submit callback |
| `INP-SET-PLACEHOLDER` | `( widget text-a text-u -- )` | Set placeholder text |
| `INP-CLEAR` | `( widget -- )` | Clear content and cursor |
| `INP-CURSOR-POS` | `( widget -- n )` | Get cursor column (character, not byte) |

#### Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_INP-INSERT` | `( widget cp -- )` | Insert codepoint at cursor |
| `_INP-DELETE` | `( widget -- )` | Delete character at cursor |
| `_INP-BACKSPACE` | `( widget -- )` | Delete character before cursor |
| `_INP-LEFT` | `( widget -- )` | Move cursor left one character |
| `_INP-RIGHT` | `( widget -- )` | Move cursor right one character |
| `_INP-HOME` | `( widget -- )` | Cursor to beginning |
| `_INP-END` | `( widget -- )` | Cursor to end |
| `_INP-SCROLL-ADJ` | `( widget -- )` | Adjust scroll so cursor is visible |
| `_INP-DRAW` | `( widget -- )` | Render into region |
| `_INP-HANDLE` | `( event widget -- flag )` | Handle key events |

#### Algorithm Notes

The edit buffer is caller-provided (not allocated by the widget).
This follows the pattern of Forth string buffers — the caller decides
where the memory lives (stack, dictionary, XMEM).

Cursor movement is UTF-8 aware: `_INP-LEFT` backs up by one UTF-8
character (1–4 bytes), not one byte.  Uses `UTF8-PREV` from
`akashic-utf8`.

Horizontal scrolling kicks in when the content is wider than the
region.  `_INP-SCROLL-ADJ` ensures the cursor is always visible
with at least 3 columns of context.

#### Test targets: ~25 tests

- Type characters, verify buffer content
- Backspace, delete
- Cursor movement (left, right, home, end)
- UTF-8 multi-byte insertion and deletion
- Horizontal scroll when content exceeds width
- Submit callback invoked on Enter
- Placeholder shown when empty
- Programmatic set/get
- Buffer overflow (insertion rejected at capacity)

---

### 4.3 tui/list.f — Scrollable List

**Goal:** Vertically scrollable list of selectable items.  Supports
keyboard navigation (up/down/pgup/pgdn), selection highlight,
and a selection-changed callback.

File: `tui/list.f`
Prefix: `LST-` (public), `_LST-` (internal)
Provider: `PROVIDED akashic-tui-list`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`

~200 lines

#### List Descriptor (header + 7 cells = 96 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-LIST |
| +40 | items | Address of item array (each: addr+len = 2 cells) |
| +48 | count | Number of items |
| +56 | selected | Currently selected index (0-based, -1 = none) |
| +64 | scroll-top | Index of first visible item |
| +72 | item-xt | Optional render callback: `( index widget -- )` for custom item drawing |
| +80 | select-xt | Selection changed callback: `( index widget -- )` |
| +88 | search-buf | Address of incremental search buffer (0 = disabled) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `LST-NEW` | `( rgn items count -- widget )` | Create list from string pair array |
| `LST-SELECT` | `( widget index -- )` | Programmatically select item |
| `LST-SELECTED` | `( widget -- index )` | Get selected index |
| `LST-ON-SELECT` | `( widget xt -- )` | Set selection callback |
| `LST-SET-ITEMS` | `( widget items count -- )` | Replace item array |
| `LST-SCROLL-TO` | `( widget index -- )` | Ensure item is visible |
| `LST-SET-RENDER` | `( widget xt -- )` | Set custom item renderer |
| `LST-SEARCH-ON` | `( widget buf -- )` | Enable incremental type-to-search |

#### Algorithm Notes

Items are an external array of `( addr len )` pairs — 2 cells per
item.  The widget does not copy strings; the caller owns the data.

The default item renderer shows `" ► "` prefix on the selected item,
with reverse video highlight.  Custom renderers (via `item-xt`)
enable icons, multi-column layouts, or styled text per item.

Scroll position automatically adjusts to keep the selected item
visible.  Page-up/page-down move by `region-height` items at a time.

Incremental search: when enabled, printable characters typed while
the list is focused filter/jump to matching items.  A brief timeout
resets the search buffer.

#### Test targets: ~20 tests

- Navigate up/down, wrap at boundaries
- Page up/down
- Selection callback fires
- Scroll adjustment
- Programmatic selection
- Custom renderer
- Incremental search matching
- Empty list handling
- Replace items while selected

---

### 4.4 tui/menu.f — Menu Bar & Dropdown Menus

**Goal:** Horizontal menu bar with dropdown menus.  Each menu
contains a list of items with labels, optional shortcuts, and
action callbacks.  Escape or click-away dismisses.

File: `tui/menu.f`
Prefix: `MNU-` (public), `_MNU-` (internal)
Provider: `PROVIDED akashic-tui-menu`
Dependencies: `REQUIRE draw.f`, `REQUIRE box.f`, `REQUIRE region.f`

~250 lines

#### Menu Item Descriptor (4 cells = 32 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | label-a | Label string address |
| +8 | label-u | Label string length |
| +16 | action-xt | Callback: `( -- )` invoked on selection |
| +24 | flags | `MNU-F-SEPARATOR` (1), `MNU-F-DISABLED` (2), `MNU-F-CHECKED` (4) |

#### Menu Descriptor (header + 5 cells = 80 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-MENU |
| +40 | menus | Address of top-level menu array |
| +48 | menu-count | Number of top-level menus |
| +56 | active-menu | Currently open menu index (-1 = none) |
| +64 | active-item | Currently highlighted item in open menu |
| +72 | bar-region | Region for the menu bar row |

Each top-level menu entry: `( label-a label-u items-addr item-count )` — 4 cells.

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `MNU-NEW` | `( rgn menus count -- widget )` | Create menu bar |
| `MNU-OPEN` | `( widget index -- )` | Open dropdown for menu at index |
| `MNU-CLOSE` | `( widget -- )` | Close any open dropdown |
| `MNU-ITEM-ENABLE` | `( widget menu# item# -- )` | Enable menu item |
| `MNU-ITEM-DISABLE` | `( widget menu# item# -- )` | Disable menu item |
| `MNU-ITEM-CHECK` | `( widget menu# item# flag -- )` | Set checked state |

#### Test targets: ~15 tests

- Menu bar renders labels
- Open/close dropdown
- Navigate items, fire action
- Separator rendering
- Disabled items skipped
- Escape closes menu
- Keyboard shortcut (Alt+letter) opens menu

---

### 4.5 tui/progress.f — Progress Bar & Spinner

**Goal:** Visual progress indicators.  A progress bar shows a
filled/empty ratio.  A spinner shows animated indeterminate
progress (requires periodic redraws from the event loop).

File: `tui/progress.f`
Prefix: `PRG-` (public), `_PRG-` (internal)
Provider: `PROVIDED akashic-tui-progress`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`

~120 lines

#### Progress Descriptor (header + 4 cells = 72 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-PROGRESS |
| +40 | value | Current value (0–max) |
| +48 | max | Maximum value |
| +56 | style | `PRG-BAR` (0), `PRG-SPINNER` (1) |
| +64 | frame | Spinner animation frame counter |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `PRG-NEW` | `( rgn max style -- widget )` | Create progress indicator |
| `PRG-SET` | `( widget value -- )` | Set current value, mark dirty |
| `PRG-INC` | `( widget -- )` | Increment by 1 |
| `PRG-TICK` | `( widget -- )` | Advance spinner frame (call from timer) |
| `PRG-PCT` | `( widget -- n )` | Get percentage (0–100) |

The bar renders using `█` (full), `░` (empty), and fractional
characters `▏▎▍▌▋▊▉` for sub-character precision (8 steps per column).

The spinner cycles through `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` (Braille dot pattern).

#### Test targets: ~10 tests

- Bar at 0%, 50%, 100%
- Fractional fill
- Spinner frame cycling
- Percentage calculation
- Max=0 edge case

---

### 4.6 tui/table.f — Tabular Data Display

**Goal:** Display data in aligned columns with headers.  Supports
column width auto-sizing, fixed widths, left/right alignment per
column, and optional row selection.

File: `tui/table.f`
Prefix: `TBL-` (public), `_TBL-` (internal)
Provider: `PROVIDED akashic-tui-table`
Dependencies: `REQUIRE draw.f`, `REQUIRE box.f`, `REQUIRE region.f`

~300 lines

#### Column Descriptor (4 cells = 32 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | header-a | Column header string address |
| +8 | header-u | Column header string length |
| +16 | width | Column width (0 = auto-size) |
| +24 | align | `TBL-LEFT` (0), `TBL-RIGHT` (1), `TBL-CENTER` (2) |

#### Table Descriptor (header + 8 cells = 104 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-TABLE |
| +40 | columns | Address of column descriptor array |
| +48 | col-count | Number of columns |
| +56 | cell-xt | Cell data callback: `( row col -- addr len )` |
| +64 | row-count | Number of data rows |
| +72 | selected | Selected row (-1 = none, -2 = disabled) |
| +80 | scroll-top | First visible row |
| +88 | select-xt | Row selection callback: `( row widget -- )` |
| +96 | border-style | Box style for grid lines (0 = no grid) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `TBL-NEW` | `( rgn cols col-count cell-xt row-count -- widget )` | Create table |
| `TBL-SET-ROWS` | `( widget count -- )` | Update row count (data changed) |
| `TBL-SELECT` | `( widget row -- )` | Select row |
| `TBL-SELECTED` | `( widget -- row )` | Get selected row |
| `TBL-ON-SELECT` | `( widget xt -- )` | Set selection callback |
| `TBL-AUTO-SIZE` | `( widget -- )` | Compute column widths from data |
| `TBL-SCROLL-TO` | `( widget row -- )` | Ensure row is visible |
| `TBL-SET-BORDER` | `( widget style -- )` | Set border style (or 0 for none) |

#### Algorithm Notes

Cell data is provided via a callback (`cell-xt`), not stored in the
widget.  The callback signature `( row col -- addr len )` returns the
string for a given data cell.  This keeps the table widget decoupled
from the data source — it can display arrays, hash tables, computed
values, or remote data.

Auto-sizing measures all visible cells (not the entire dataset for
performance) and picks the widest value or header length.

#### Test targets: ~20 tests

- Header rendering
- Cell alignment (left, right, center)
- Auto-sizing columns
- Row selection and callback
- Scrolling large datasets
- Grid border styles
- Zero columns, zero rows edge cases

---

### 4.7 tui/dialog.f — Modal Dialog Boxes

**Goal:** Modal popup dialog with a message and buttons.  Blocks
input to other widgets while visible.  Returns which button was
pressed.

File: `tui/dialog.f`
Prefix: `DLG-` (public), `_DLG-` (internal)
Provider: `PROVIDED akashic-tui-dialog`
Dependencies: `REQUIRE draw.f`, `REQUIRE box.f`, `REQUIRE region.f`, `REQUIRE label.f`

~180 lines

#### Dialog Descriptor (header + 7 cells = 96 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-DIALOG |
| +40 | title-a | Title string address |
| +48 | title-u | Title string length |
| +56 | msg-a | Message string address |
| +64 | msg-u | Message string length |
| +72 | buttons | Address of button label array (addr+len pairs) |
| +80 | btn-count | Number of buttons |
| +88 | selected-btn | Currently focused button index |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-NEW` | `( title-a title-u msg-a msg-u btns count -- widget )` | Create dialog |
| `DLG-SHOW` | `( widget -- index )` | Show dialog, run modal loop, return button index |
| `DLG-INFO` | `( msg-a msg-u -- )` | Quick: show OK-only info dialog |
| `DLG-CONFIRM` | `( msg-a msg-u -- flag )` | Quick: show Yes/No dialog, return TRUE for Yes |
| `DLG-FREE` | `( widget -- )` | Free dialog |

#### Algorithm Notes

`DLG-SHOW` saves the current screen state, draws the dialog centered
on screen with a box border, runs its own event sub-loop handling
Tab (cycle buttons), Enter (select), Escape (cancel = last button),
then restores the saved screen and returns.

The dialog's region is auto-sized based on message length and button
count, centered within the current screen.

#### Test targets: ~10 tests

- Info dialog shows message, returns 0
- Confirm dialog returns correct flag
- Multiple buttons, Tab cycles
- Escape selects cancel button
- Long messages word-wrap
- Dialog centering

---

### 4.8 tui/tabs.f — Tabbed Panels

**Goal:** A row of tab headers with a content area below.  Each tab
has a label and a child region.  Switching tabs shows the
corresponding content region and hides others.

File: `tui/tabs.f`
Prefix: `TAB-` (public), `_TAB-` (internal)
Provider: `PROVIDED akashic-tui-tabs`
Dependencies: `REQUIRE draw.f`, `REQUIRE box.f`, `REQUIRE region.f`

~180 lines

#### Tab Entry (3 cells = 24 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | label-a | Tab label string address |
| +8 | label-u | Tab label string length |
| +16 | content-rgn | Region for this tab's content |

#### Tabs Descriptor (header + 5 cells = 80 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-TABS |
| +40 | tabs | Address of tab entry array |
| +48 | count | Number of tabs |
| +56 | active | Currently active tab index |
| +64 | header-rgn | Region for the tab header row |
| +72 | switch-xt | Tab-switched callback: `( index widget -- )` |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-NEW` | `( rgn -- widget )` | Create empty tab container |
| `TAB-ADD` | `( widget label-a label-u -- content-rgn )` | Add a tab; returns content region |
| `TAB-SELECT` | `( widget index -- )` | Switch to tab |
| `TAB-ACTIVE` | `( widget -- index )` | Get active tab index |
| `TAB-ON-SWITCH` | `( widget xt -- )` | Set tab-switched callback |
| `TAB-CONTENT` | `( widget index -- rgn )` | Get content region for tab |

#### Test targets: ~12 tests

- Add tabs, verify labels render
- Switch tabs, correct content visible
- Callback fires on switch
- Keyboard navigation (left/right arrows)
- Many tabs (overflow behavior)

---

## Layer 5 — Application Shell

### 5.1 tui/event.f — Event Loop & Dispatch

**Goal:** The main event loop that ties input, rendering, and timers
together.  Poll for input via `KEY-READ`, dispatch events through
the focused widget chain, trigger timer callbacks, and call
`SCR-FLUSH` to update the display.

File: `tui/event.f`
Prefix: `TUI-EVT-` (public), `_TUI-EVT-` (internal)
Provider: `PROVIDED akashic-tui-event`
Dependencies: `REQUIRE keys.f`, `REQUIRE screen.f`, `REQUIRE focus.f`

~200 lines

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `TUI-EVT-LOOP` | `( -- )` | Enter the event loop (blocks until quit) |
| `TUI-EVT-QUIT` | `( -- )` | Signal the loop to exit |
| `TUI-EVT-TICK-MS!` | `( ms -- )` | Set tick interval (default: 100 ms) |
| `TUI-EVT-ON-TICK` | `( xt -- )` | Register tick callback: `( -- )` |
| `TUI-EVT-ON-RESIZE` | `( xt -- )` | Register resize callback: `( w h -- )` |
| `TUI-EVT-ON-KEY` | `( xt -- )` | Register global key handler (before focus dispatch): `( event -- consumed? )` |
| `TUI-EVT-POST` | `( xt -- )` | Post a deferred action to run on next loop iteration |
| `TUI-EVT-REDRAW` | `( -- )` | Request full redraw on next loop iteration |

#### Loop Pseudocode

```forth
: TUI-EVT-LOOP
  BEGIN
    _TUI-EVT-RUNNING @
  WHILE
    \ 1. Check for input
    _TUI-EVT-KEY-BUF KEY-POLL IF
      \ 2. Global handler first
      _TUI-EVT-ON-KEY-XT @ ?DUP IF
        _TUI-EVT-KEY-BUF SWAP EXECUTE  ( -- consumed? )
      ELSE FALSE THEN
      \ 3. If not consumed, dispatch to focused widget
      INVERT IF
        _TUI-EVT-KEY-BUF FOC-DISPATCH
      THEN
    THEN
    \ 4. Run deferred actions
    _TUI-EVT-DRAIN-POSTED
    \ 5. Timer tick
    _TUI-EVT-CHECK-TICK
    \ 6. Draw dirty widgets
    _TUI-EVT-DRAW-DIRTY
    \ 7. Flush screen
    SCR-FLUSH
    \ 8. Cooperative yield (if KDOS scheduler is active)
    YIELD?
  REPEAT ;
```

#### Algorithm Notes

The loop is cooperative: `YIELD?` at the bottom gives the KDOS
scheduler a chance to run other tasks.  For applications that are
the only task, `YIELD?` is a no-op.

Timer ticks are checked by comparing the current time (via KDOS
`TIMER@`) against the last tick time.  No hardware timer interrupt
is required.

Deferred actions are a FIFO queue of execution tokens — max 8
entries.  `TUI-EVT-POST` is safe to call from within widget
handlers (avoids re-entrant mutation).

#### Test targets: ~15 tests

- Loop starts and quits
- Key event dispatched to focused widget
- Global handler intercepts before focus
- Tick callback fires at interval
- Resize callback fires
- Deferred actions execute in order
- YIELD? does not break the loop

---

### 5.2 tui/focus.f — Focus Manager

**Goal:** Manage which widget receives keyboard input.  Maintains
a focus chain (ordered list of focusable widgets).  Tab/Shift-Tab
cycles focus.

File: `tui/focus.f`
Prefix: `FOC-` (public), `_FOC-` (internal)
Provider: `PROVIDED akashic-tui-focus`
Dependencies: `REQUIRE keys.f`

~150 lines

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `FOC-ADD` | `( widget -- )` | Add widget to focus chain |
| `FOC-REMOVE` | `( widget -- )` | Remove widget from focus chain |
| `FOC-NEXT` | `( -- )` | Move focus to next widget |
| `FOC-PREV` | `( -- )` | Move focus to previous widget |
| `FOC-SET` | `( widget -- )` | Explicitly set focus |
| `FOC-GET` | `( -- widget | 0 )` | Get currently focused widget |
| `FOC-DISPATCH` | `( event-addr -- )` | Send key event to focused widget's handle-xt |
| `FOC-CLEAR` | `( -- )` | Clear focus chain (teardown) |
| `FOC-COUNT` | `( -- n )` | Number of focusable widgets |

#### Design

Focus chain is a circular singly-linked list.  Each widget has a
`_foc-next` field (stored outside the widget header, in a small
parallel array managed by focus.f — max 32 entries).  This avoids
adding fields to every widget descriptor.

`FOC-DISPATCH` calls `WDG-HANDLE` on the focused widget.  If the
widget returns FALSE (not consumed), the event is dropped.  The
event loop handles Tab/Shift-Tab before dispatching so the focus
manager doesn't need special-case Tab handling.

#### Test targets: ~12 tests

- Add widgets, Tab cycles forward
- Shift-Tab cycles backward
- Remove focused widget (focus moves)
- Explicit set
- Dispatch reaches correct widget
- Empty chain (no crash)

---

### 5.3 tui/app.f — Application Lifecycle

**Goal:** One-call application setup and teardown.  Enters alternate
screen, hides cursor, configures terminal, runs the event loop,
then restores everything on exit.  This is the top-level entry
point for a TUI application.

File: `tui/app.f`
Prefix: `APP-` (public), `_APP-` (internal)
Provider: `PROVIDED akashic-tui-app`
Dependencies: `REQUIRE ansi.f`, `REQUIRE screen.f`, `REQUIRE event.f`, `REQUIRE focus.f`

~120 lines

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `APP-INIT` | `( w h -- )` | Initialize: alternate screen, hide cursor, create screen, set up event loop |
| `APP-RUN` | `( -- )` | Enter the event loop (blocks until quit) |
| `APP-SHUTDOWN` | `( -- )` | Cleanup: free screen, show cursor, leave alternate screen, reset attributes |
| `APP-SIZE` | `( -- w h )` | Get current screen dimensions |
| `APP-SCREEN` | `( -- scr )` | Get the application screen descriptor |
| `APP-TITLE!` | `( addr len -- )` | Set terminal title — `ESC]2;...ST` |
| `APP-RUN-FULL` | `( init-xt w h -- )` | Convenience: APP-INIT, call init-xt, APP-RUN, APP-SHUTDOWN |

#### Usage Example

```forth
REQUIRE tui/app.f

: my-setup ( -- )
  \ Create widgets, add to focus chain, etc.
  APP-SCREEN SCR-USE
  ( ... build your UI ... )
;

: main  ['] my-setup 80 24 APP-RUN-FULL ;
main
```

#### Test targets: ~8 tests

- Init enters alternate screen
- Shutdown restores normal screen
- Title setting
- Full lifecycle runs and exits cleanly
- Terminal state restored after exception

---

## Layer 6 — Extended Components

### 6.1 tui/split.f — Split Panes

**Goal:** Divide a region into two panes (horizontal or vertical
split), with an optional draggable divider.

File: `tui/split.f`
Prefix: `SPL-` (public)
Provider: `PROVIDED akashic-tui-split`
Dependencies: `REQUIRE region.f`, `REQUIRE draw.f`

~150 lines

#### Split Descriptor (header + 5 cells = 80 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-SPLIT |
| +40 | mode | `SPL-H` (horizontal) or `SPL-V` (vertical) |
| +48 | ratio | Split position (fixed cell count or 0 for 50/50) |
| +56 | pane-a | Region for pane A |
| +64 | pane-b | Region for pane B |
| +72 | divider-char | Character for divider line (default: `│` or `─`) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `SPL-NEW` | `( rgn mode ratio -- widget )` | Create split pane |
| `SPL-PANE-A` | `( widget -- rgn )` | Get pane A region |
| `SPL-PANE-B` | `( widget -- rgn )` | Get pane B region |
| `SPL-SET-RATIO` | `( widget n -- )` | Adjust split position |
| `SPL-RECOMPUTE` | `( widget -- )` | Update pane regions after resize |

#### Test targets: ~10 tests

- Horizontal and vertical split
- Ratio adjustment
- Resize recomputes correctly
- Minimum pane sizes

---

### 6.2 tui/scroll.f — Scrollable Viewport

**Goal:** A generic scrollable viewport — wraps any content that
is larger than its visible region.  Provides vertical and
horizontal scrolling with optional scroll indicators.

File: `tui/scroll.f`
Prefix: `SCRL-` (public), `_SCRL-` (internal)
Provider: `PROVIDED akashic-tui-scroll`
Dependencies: `REQUIRE region.f`, `REQUIRE draw.f`

~180 lines

#### Scroll Descriptor (header + 6 cells = 88 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-SCROLL |
| +40 | content-h | Total content height (rows) |
| +48 | content-w | Total content width (cols) |
| +56 | offset-y | Vertical scroll offset |
| +64 | offset-x | Horizontal scroll offset |
| +72 | draw-content-xt | Callback: `( offset-y offset-x rgn -- )` to render content |
| +80 | indicator | Scroll indicator style (0=none, 1=bar, 2=arrows) |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `SCRL-NEW` | `( rgn content-h content-w draw-xt -- widget )` | Create scrollable viewport |
| `SCRL-SET-SIZE` | `( widget h w -- )` | Update content dimensions |
| `SCRL-SCROLL-TO` | `( widget y x -- )` | Set scroll offset |
| `SCRL-SCROLL-BY` | `( widget dy dx -- )` | Relative scroll |
| `SCRL-ENSURE-VISIBLE` | `( widget row col -- )` | Scroll so (row,col) is in view |
| `SCRL-OFFSET` | `( widget -- y x )` | Get current offset |

#### Test targets: ~12 tests

- Vertical scroll up/down
- Horizontal scroll
- Content smaller than viewport (no scroll)
- Scroll indicators
- Ensure-visible adjusts offset

---

### 6.3 tui/tree.f — Tree View

**Goal:** Collapsible tree display for hierarchical data.  Nodes
can be expanded/collapsed.  Arrow keys navigate, Enter toggles
expansion.

File: `tui/tree.f`
Prefix: `TREE-` (public), `_TREE-` (internal)
Provider: `PROVIDED akashic-tui-tree`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`, `REQUIRE scroll.f`

~250 lines

#### Tree Node Interface

The tree widget does not own the tree data.  It uses callbacks to
discover the tree structure:

| Callback | Signature | Description |
|----------|-----------|-------------|
| `children-xt` | `( node -- first-child \| 0 )` | Get first child |
| `next-xt` | `( node -- sibling \| 0 )` | Get next sibling |
| `label-xt` | `( node -- addr len )` | Get display label |
| `leaf?-xt` | `( node -- flag )` | Is this a leaf (no toggle)? |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-NEW` | `( rgn root children-xt next-xt label-xt leaf?-xt -- widget )` | Create tree view |
| `TREE-EXPAND` | `( widget node -- )` | Expand node |
| `TREE-COLLAPSE` | `( widget node -- )` | Collapse node |
| `TREE-TOGGLE` | `( widget node -- )` | Toggle expand/collapse |
| `TREE-EXPAND-ALL` | `( widget -- )` | Expand entire tree |
| `TREE-SELECTED` | `( widget -- node )` | Get selected node |
| `TREE-ON-SELECT` | `( widget xt -- )` | Set selection callback |
| `TREE-REFRESH` | `( widget -- )` | Re-read tree data and redraw |

The tree view uses box-drawing characters for the tree guides:
`├──`, `│  `, `└──` with proper indentation per depth level.

#### Test targets: ~15 tests

- Render flat tree (single level)
- Expand/collapse
- Deep nesting (5+ levels)
- Navigate with arrows
- Selection callback
- Refresh after data change

---

### 6.4 tui/status.f — Status Bar

**Goal:** A single-row bar for persistent status information
(filename, mode, cursor position, etc.).  Typically placed at the
top or bottom of the screen.

File: `tui/status.f`
Prefix: `SBAR-` (public)
Provider: `PROVIDED akashic-tui-status`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`

~100 lines

#### Status Bar Descriptor (header + 3 cells = 64 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-STATUS |
| +40 | left-a / left-u | Left-aligned text (addr + len) |
| +48 | right-a / right-u | Right-aligned text (addr + len) |
| +56 | style | fg/bg/attrs for the bar |

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `SBAR-NEW` | `( rgn -- widget )` | Create status bar |
| `SBAR-LEFT!` | `( widget addr len -- )` | Set left text |
| `SBAR-RIGHT!` | `( widget addr len -- )` | Set right text |
| `SBAR-STYLE!` | `( widget fg bg attrs -- )` | Set bar style |

#### Test targets: ~6 tests

---

### 6.5 tui/toast.f — Transient Notifications

**Goal:** Brief popup messages that auto-dismiss after a timeout.
Displayed at a fixed position (typically bottom-right).

File: `tui/toast.f`
Prefix: `TST-` (public)
Provider: `PROVIDED akashic-tui-toast`
Dependencies: `REQUIRE draw.f`, `REQUIRE box.f`, `REQUIRE region.f`

~120 lines

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `TST-SHOW` | `( msg-a msg-u timeout-ms -- )` | Show a toast notification |
| `TST-DISMISS` | `( -- )` | Manually dismiss current toast |
| `TST-TICK` | `( -- )` | Called from event loop tick — manages auto-dismiss timer |
| `TST-POSITION!` | `( row col -- )` | Set toast anchor position |

#### Test targets: ~6 tests

---

### 6.6 tui/canvas.f — Character-Mode Canvas

**Goal:** A free-form drawing surface for character graphics —
Braille patterns, block characters, plot points.  Provides
a coordinate system for sub-cell "pixel" drawing using Unicode
Braille characters (2×4 dots per cell = 2× horizontal and 4×
vertical resolution).

File: `tui/canvas.f`
Prefix: `CVS-` (public), `_CVS-` (internal)
Provider: `PROVIDED akashic-tui-canvas`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`

~200 lines

#### Canvas Descriptor (header + 5 cells = 80 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+32 | (widget header) | type=WDG-T-CANVAS |
| +40 | dot-buf | Bit array: 1 bit per dot (w×2 × h×4 bits) |
| +48 | dot-w | Dot-resolution width (region width × 2) |
| +56 | dot-h | Dot-resolution height (region height × 4) |
| +64 | fg | Foreground color for Braille characters |
| +72 | bg | Background color |

Each Braille character `U+2800..U+28FF` encodes a 2×4 dot pattern.
The canvas maps its dot buffer to Braille codepoints.

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `CVS-NEW` | `( rgn -- widget )` | Create canvas |
| `CVS-CLEAR` | `( widget -- )` | Clear all dots |
| `CVS-SET` | `( widget x y -- )` | Set dot at (x, y) |
| `CVS-CLR` | `( widget x y -- )` | Clear dot at (x, y) |
| `CVS-GET` | `( widget x y -- flag )` | Test dot |
| `CVS-LINE` | `( widget x0 y0 x1 y1 -- )` | Draw line (Bresenham) |
| `CVS-RECT` | `( widget x y w h -- )` | Draw rectangle outline |
| `CVS-FILL-RECT` | `( widget x y w h -- )` | Fill rectangle |
| `CVS-CIRCLE` | `( widget cx cy r -- )` | Draw circle (midpoint) |
| `CVS-TEXT` | `( widget x y addr len -- )` | Place text at dot coords (snapped to cell) |
| `CVS-PLOT` | `( widget data count x-scale y-scale -- )` | Plot array as connected line |
| `CVS-STYLE!` | `( widget fg bg -- )` | Set canvas colors |

#### Algorithm Notes

`_CVS-BRAILLE` converts a 2×4 bit block into a Braille codepoint
by OR-ing the 8 dot bits into the corresponding Braille offset bits
(the Braille block has a non-sequential bit layout: column-major
with dot 7 and 8 at the bottom).

`CVS-PLOT` draws a connected line graph from an array of integer
y-values.  `x-scale` controls how many dots per data point
horizontally; `y-scale` maps the data range to the canvas height.

This provides terminal-mode charting — sparklines, waveforms,
scatter plots — at 2× the horizontal and 4× the vertical resolution
of raw character placement.

#### Test targets: ~15 tests

- Set/clear/test individual dots
- Braille encoding correctness
- Line drawing
- Rectangle and circle
- Plot from data array
- Full-canvas clear
- Edge dots at boundaries

---

## Dependency Graph

```
                        app.f
                       ╱  │  ╲
                      ╱   │   ╲
                event.f  focus.f  (Layer 5 shell)
                  │    ╲  │
                  │     ╲ │
    ┌─────────────┼──────┼──────────────────────────┐
    │   Layer 4   │      │   Widgets                 │
    │  label  input  list  menu  progress  table     │
    │  dialog  tabs                                  │
    ├─────────────┼──────┼──────────────────────────┤
    │   Layer 6   │      │   Extended                │
    │  split  scroll  tree  status  toast  canvas    │
    └─────────────┼──────┼──────────────────────────┘
                  │      │
            ┌─────┴──────┴─────┐
            │   Layout Engine   │
            │  region.f         │
            │  layout.f         │ (Layer 3)
            └────────┬─────────┘
                     │
            ┌────────┴─────────┐
            │ Drawing Prims     │
            │  draw.f  box.f   │ (Layer 2)
            └────────┬─────────┘
                     │
            ┌────────┴─────────┐
            │ Screen Abstraction│
            │  cell.f screen.f │ (Layer 1)
            └────────┬─────────┘
                     │
            ┌────────┴─────────┐
            │ Terminal Escapes  │
            │  ansi.f  keys.f  │ (Layer 0)
            └────────┬─────────┘
                     │
            ┌────────┴─────────┐
            │ KDOS BIOS        │
            │ EMIT KEY TYPE CR │
            └────────┬─────────┘
                     │
            ┌────────┴─────────┐
            │ Akashic           │
            │ string.f utf8.f  │
            │ fmt.f event.f    │
            └──────────────────┘
```

---

## Implementation Order

| # | File | Layer | Depends On | Est. Lines | Status |
|---|------|-------|------------|------------|--------|
| 1 | tui/ansi.f | 0 | BIOS only | 550 | ✅ Done |
| 2 | tui/keys.f | 0 | utf8.f | 654 | ✅ Done |
| 3 | tui/cell.f | 1 | — | 182 | ✅ Done |
| 4 | tui/screen.f | 1 | cell, ansi, utf8 | 442 | ✅ Done |
| 5 | tui/draw.f | 2 | screen, utf8 | 309 | ✅ Done |
| 6 | tui/box.f | 2 | draw | 275 | ✅ Done |
| 7 | tui/region.f | 3 | screen, draw | 210 | ✅ Done |
| 8 | tui/layout.f | 3 | region | 365 | ✅ Done |
| 9 | tui/widget.f | 4 | region | 234 | ✅ Done |
| 10 | tui/label.f | 4 | widget, draw | 209 | ✅ Done |
| 11 | tui/input.f | 4 | draw, region, utf8 | ~250 | ❌ Not started |
| 12 | tui/list.f | 4 | draw, region | ~200 | ❌ Not started |
| 13 | tui/progress.f | 4 | widget, draw | 263 | ✅ Done |
| 14 | tui/table.f | 4 | draw, box, region | ~300 | ❌ Not started |
| 15 | tui/menu.f | 4 | draw, box, region | ~250 | ❌ Not started |
| 16 | tui/dialog.f | 4 | draw, box, region, label | ~180 | ❌ Not started |
| 17 | tui/tabs.f | 4 | draw, box, region | ~180 | ❌ Not started |
| 18 | tui/focus.f | 5 | keys | ~150 | ❌ Not started |
| 19 | tui/event.f | 5 | keys, screen, focus | ~200 | ❌ Not started |
| 20 | tui/app.f | 5 | ansi, screen, event, focus | ~120 | ❌ Not started |
| 21 | tui/split.f | 6 | region, draw | ~150 | ❌ Not started |
| 22 | tui/scroll.f | 6 | region, draw | ~180 | ❌ Not started |
| 23 | tui/status.f | 6 | draw, region | ~100 | ❌ Not started |
| 24 | tui/toast.f | 6 | draw, box, region | ~120 | ❌ Not started |
| 25 | tui/tree.f | 6 | draw, region, scroll | ~250 | ❌ Not started |
| 26 | tui/canvas.f | 6 | draw, region | ~200 | ❌ Not started |
| | **Total** | | | **~4,750** | |

Build from bottom up: Layer 0 first (ansi + keys), then Layer 1
(cell + screen), and so on.  Within each layer, files are independent
and can be implemented in any order.

---

## Memory Budget

| Component | Formula | 80×24 | 132×50 |
|-----------|---------|-------|--------|
| Front buffer | W × H × 8 | 15,360 | 52,800 |
| Back buffer | W × H × 8 | 15,360 | 52,800 |
| Screen descriptor | 64 | 64 | 64 |
| Focus chain (32 slots) | 32 × 8 | 256 | 256 |
| Event queue (8 slots) | 8 × 24 | 192 | 192 |
| Key decode buffer | 8 | 8 | 8 |
| Typical widget set (20 widgets) | 20 × ~100 | 2,000 | 2,000 |
| Region descriptors (30) | 30 × 40 | 1,200 | 1,200 |
| Layout descriptors (10) | 10 × 48 | 480 | 480 |
| Canvas dot buffer (80×24) | (W×2 × H×4) / 8 | 1,920 | 6,600 |
| **Total** | | **~36,840** | **~116,400** |

All fits in XMEM (16 MiB) with room to spare.  Even the largest
terminal (200×60) uses under 200 KiB.  Dictionary footprint for
the code itself: ~4,750 lines × ~12 bytes/line ≈ ~57 KiB.

---

## Design Constraints

1. **64-bit cells.** All descriptors use 8-byte fields.  A character
   cell packs into exactly one cell.

2. **No DEFER/IS.** Widget polymorphism uses execution tokens stored
   in descriptor fields (`draw-xt`, `handle-xt`), not late-binding.

3. **S" is compile-only.** String literals must be inside `:` defs
   or provided as address+length pairs from the caller.

4. **CREATE not inside `:`.** Widget descriptor layouts and constant
   tables are defined at the top level of each file.

5. **VARIABLE for multi-step state.** The "current screen", "current
   region", and "current drawing style" are VARIABLEs set by `SCR-USE`,
   `RGN-USE`, and `DRW-STYLE!`.

6. **CMOVE is `( src dst cnt -- )`.** Non-standard argument order.
   All buffer copies must use this order.

7. **Serial UART output.** No DMA, no frame buffer mapping.  Every
   byte goes through `EMIT`.  Differential flush is critical for
   performance.

8. **Cooperative scheduling.** `YIELD?` in the event loop lets other
   KDOS tasks run.  All UI operations are non-blocking relative to
   other tasks.

9. **No signal-based resize.** Terminal size changes are detected
   either by explicit query (`ANSI-QUERY-SIZE` + response parsing)
   or by polling.  No SIGWINCH equivalent.

---

## Testing Strategy

Each module gets a companion test file: `tests/tui/test_<module>.f`.

Tests run on the Megapad-64 emulator using the Python test harness
(same pattern as existing tests in `local_testing/`).  The harness
captures UART output and verifies that the correct escape sequences
are emitted.

**ANSI layer tests:** Inject nothing; verify emitted byte sequences
against expected CSI strings.

**Key decoder tests:** Inject multi-byte sequences via
`uart.inject_input()`; verify decoded event type, code, and modifiers.

**Screen tests:** Create a screen, set cells, flush, and verify
the UART output contains the correct ANSI positioning and character
bytes.

**Widget tests:** Set up a region, create a widget, call its draw-xt,
capture UART output after flush, verify.

**Integration tests:** Inject a sequence of keystrokes, verify the
screen converges to the expected cell pattern after each.

Estimated total: **~350 tests** across all modules.

---

## Known Limitations

1. **No true-color cell packing.** The cell encoding uses 8-bit
   color indices (256-palette).  True-color (24-bit RGB) would
   require 3 bytes per color × 2 = 6 bytes, exceeding the 8-byte
   cell budget.  Applications that need true-color can use
   `ANSI-FG-RGB` / `ANSI-BG-RGB` directly, bypassing the cell
   buffer (useful for one-off decoration, not full-screen UI).

2. **No bidirectional text.** Layout is left-to-right only.  RTL
   support would require a bidi algorithm in the text layer.

3. **No composition/combining characters.** A cell holds one
   codepoint.  Combining marks (accents, diacritics) would need a
   secondary overlay buffer — explicitly out of scope for v1.

4. **Maximum 32 focusable widgets.** The focus chain is a fixed-size
   array.  Sufficient for typical TUI applications; can be widened
   trivially.

5. **No mouse drag.** Mouse events report press, release, and
   position, but there is no built-in drag-and-drop protocol.
   Widgets can implement drag by tracking press→motion→release.

6. **Serial-speed bound.** At 115,200 baud, a full-screen redraw
   of 80×24 character cells with positioning takes ~50 ms.
   Differential flush keeps typical updates under 5 ms, but rapid
   full-screen animation will be visibly limited.

---

## Future Extensions

Explicitly **not** in scope for this roadmap but reasonable follow-on
work:

- **Theme engine** — Named color palettes and widget style presets,
  switchable at runtime (dark/light/high-contrast).
- **LIRAQ bridge** — Drive terminal widgets from LIRAQ state-tree
  bindings and UIDL documents, similar to the planned 2D UI surface.
- **SML terminal encoder** — A fifth output encoder for the 1D
  Inceptor runtime that renders SOM documents to the terminal via
  this TUI library.
- **Form validation** — Declarative input validation rules tied to
  INP- widgets (regex, length, type).
- **Clipboard** — OSC 52 escape sequence for terminal clipboard
  integration.
- **Sixel/Kitty graphics** — Inline image rendering for terminals
  that support pixel-level graphics protocols.
- **tmux/screen awareness** — Detect multiplexer presence and adjust
  escape sequences accordingly.
- **Accessibility bridge** — Expose widget state to screen readers
  via the 1D UI / Inceptor path.
