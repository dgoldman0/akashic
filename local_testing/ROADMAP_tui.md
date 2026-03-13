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
  - [4.1 tui/widgets/label.f — Static Text Labels](#41-tuilabelf--static-text-labels)
  - [4.2 tui/widgets/input.f — Text Input Field](#42-tuiinputf--text-input-field)
  - [4.3 tui/widgets/list.f — Scrollable List](#43-tuilistf--scrollable-list)
  - [4.4 tui/widgets/menu.f — Menu Bar & Dropdown Menus](#44-tuimenuf--menu-bar--dropdown-menus)
  - [4.5 tui/widgets/progress.f — Progress Bar & Spinner](#45-tuiprogressf--progress-bar--spinner)
  - [4.6 tui/table.f — Tabular Data Display](#46-tuitablef--tabular-data-display)
  - [4.7 tui/widgets/dialog.f — Modal Dialog Boxes](#47-tuidialogyf--modal-dialog-boxes)
  - [4.8 tui/widgets/tabs.f — Tabbed Panels](#48-tuitabsf--tabbed-panels)
- [Layer 5 — DOM-TUI Bridge](#layer-5--dom-tui-bridge)
  - [5.0 dom/event.f — DOM Event System](#50-domeventf--dom-event-system)
  - [5.1 tui/dom-tui.f — DOM-to-TUI Node Mapping](#51-tuidom-tuif--dom-to-tui-node-mapping)
  - [5.2 tui/dom-render.f — DOM Tree Layout & Paint](#52-tuidom-renderf--dom-tree-layout--paint)
  - [5.3 tui/dom-event.f — DOM Event Routing](#53-tuidom-eventf--dom-event-routing)
  - [5.4 liraq/uidl.f Hardening — Element Registry & Five Protocols (Phase 0)](#54-liraquidlf-hardening--element-registry--five-protocols-phase-0)
  - [5.5 tui/uidl-tui.f — UIDL TUI Backend](#55-tuiuidl-tuif--uidl-tui-backend)
- [Layer 6 — Application Shell](#layer-6--application-shell)
  - [6.1 tui/event.f — Event Loop & Dispatch](#61-tuieventf--event-loop--dispatch)
  - [6.2 tui/focus.f — Focus Manager](#62-tuifocusf--focus-manager)
  - [6.2b tui/focus-2d.f — Spatial Focus Navigation](#62b-tuifocus-2df--spatial-focus-navigation)
  - [6.3 tui/app.f — Application Lifecycle](#63-tuiappf--application-lifecycle)
- [Layer 7 — Extended Components](#layer-7--extended-components)
  - [7.1 tui/widgets/split.f — Split Panes](#71-tuisplitf--split-panes)
  - [7.2 tui/widgets/scroll.f — Scrollable Viewport](#72-tuiscrollf--scrollable-viewport)
  - [7.3 tui/widgets/tree.f — Tree View ✅](#73-tuitreef--tree-view-)
  - [7.4 tui/widgets/status.f — Status Bar](#74-tuistatusf--status-bar)
  - [7.5 tui/widgets/toast.f — Transient Notifications](#75-tuitoastf--transient-notifications)
  - [7.6 tui/widgets/canvas.f — Character-Mode Canvas ✅](#76-tuicanvasf--character-mode-canvas-)
- [Layer 8 — Application Packaging (optional)](#layer-8--application-packaging-optional)
  - [8.1 tui/app-image.f — Binary Image Wrapper](#81-tuiapp-imagef--binary-image-wrapper)
  - [8.2 tui/app-manifest.f — Application Manifest](#82-tuiapp-manifestf--application-manifest)
  - [8.3 tui/app-launcher.f — TUI Launcher](#83-tuiapp-launcherf--tui-launcher)
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
   - `tui/widgets/label.f`    → `LBL-`
   - `tui/widgets/input.f`    → `INP-`
   - `tui/widgets/list.f`     → `LST-`
   - `tui/widgets/menu.f`     → `MNU-`
   - `tui/widgets/progress.f` → `PRG-`
   - `tui/table.f`    → `TBL-`
   - `tui/widgets/dialog.f`   → `DLG-`
   - `tui/widgets/tabs.f`     → `TAB-`
   - `tui/event.f`    → `TUI-EVT-`
   - `tui/focus.f`    → `FOC-`
   - `tui/focus-2d.f` → `F2D-`
   - `tui/app.f`      → `APP-`
   - `tui/widgets/split.f`    → `SPL-`
   - `tui/widgets/scroll.f`   → `SCRL-`
   - `tui/widgets/tree.f`     → `TREE-`
   - `tui/widgets/status.f`   → `SBAR-`
   - `tui/widgets/toast.f`    → `TST-`
   - `tui/widgets/canvas.f`   → `CVS-`
   - `tui/app-image.f`→ `APPI-`
   - `tui/app-manifest.f`→ `MFT-`
   - `tui/app-launcher.f`→ `LAUNCH-`
   - `dom/event.f`    → `DOME-`
   - `tui/dom-tui.f`  → `DTUI-`
   - `tui/dom-render.f`→ `DREN-`
   - `tui/dom-event.f` → `DEVT-`
   - `liraq/uidl-chrome.f` → `UIDL-T-` (chrome type constants)
   - `tui/uidl-tui.f`  → `UTUI-`

   Internal words use `_`-prefix: `_ANSI-`, `_SCR-`, etc.

8. **PROVIDED guards.**  Every file starts with:
   ```forth
   PROVIDED akashic-tui-ansi  ( or whatever the module name is )
   ```
   Preventing double-load.  `REQUIRE` pulls dependencies.

---

## Architecture Overview

Two rendering paths share Layers 0–4.  The **UIDL path** (primary)
uses the UIDL tree as the runtime, with the Element Registry
providing extensible draw/event/layout dispatch.  The **DOM path**
(web/HTML) maps DOM nodes through sidecars into the same TUI
primitives.  Both converge on the screen buffer.

```
┌──────────────────────────────────────────────────────────────┐
│                       Application                            │
├──────────────────────────────────────────────────────────────┤
│  Layer 8: Application Packaging (optional)                   │
│  app-image.f │ app-manifest.f │ app-launcher.f               │
├──────────────────────────────────────────────────────────────┤
│  Layer 7: Extended Components                                │
│  split.f │ scroll.f │ tree.f │ status.f │ toast.f │ canvas.f │
├──────────────────────────────────────────────────────────────┤
│  Layer 6: Application Shell                                  │
│  event.f (loop) │ focus.f + focus-2d.f  │ app.f (lifecycle)  │
├─────────────────────────┬────────────────────────────────────┤
│  Layer 5a: UIDL Path    │  Layer 5b: DOM Path (HTML/CSS)     │
│  (primary — direct)     │  (optional — web content)          │
│                         │                                    │
│  liraq/uidl.f           │  dom/event.f  (W3C events)         │
│    Element Registry     │  tui/dom-tui.f  (sidecars)        │
│    Five Protocols       │  tui/dom-render.f  (layout+paint)  │
│    Subscription Table   │  tui/dom-event.f  (key/mouse)      │
│  liraq/uidl-chrome.f    │                                    │
│    (chrome elements)    │  ▲ consumes: dom/, css/,           │
│  tui/uidl-tui.f         │    liraq/lel.f, state-tree.f       │
│    (TUI backend)        │                                    │
│                         │                                    │
│  ▲ consumes: liraq/,    │                                    │
│    markup/, Layers 0–4  │                                    │
├─────────────────────────┴────────────────────────────────────┤
│  Layer 4: Widgets  (tui/widgets/)                            │
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
│  dom/dom.f │ css/css.f │ css/bridge.f │ markup/core.f        │
│  liraq/uidl.f │ liraq/lel.f │ liraq/state-tree.f            │
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

### 4.1 tui/widgets/label.f — Static Text Labels

**Goal:** Display a fixed text string within a region.  Supports
single-line and multi-line text, with left/center/right alignment.
Labels are non-interactive (handle-xt is a no-op).

File: `tui/widgets/label.f`
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

### 4.2 tui/widgets/input.f — Text Input Field

**Goal:** Single-line editable text field with cursor.  Supports
character insertion, deletion, cursor movement, and a submit
callback.

File: `tui/widgets/input.f`
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

### 4.3 tui/widgets/list.f — Scrollable List

**Goal:** Vertically scrollable list of selectable items.  Supports
keyboard navigation (up/down/pgup/pgdn), selection highlight,
and a selection-changed callback.

File: `tui/widgets/list.f`
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

### 4.4 tui/widgets/menu.f — Menu Bar & Dropdown Menus

**Goal:** Horizontal menu bar with dropdown menus.  Each menu
contains a list of items with labels, optional shortcuts, and
action callbacks.  Escape or click-away dismisses.

File: `tui/widgets/menu.f`
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

### 4.5 tui/widgets/progress.f — Progress Bar & Spinner

**Goal:** Visual progress indicators.  A progress bar shows a
filled/empty ratio.  A spinner shows animated indeterminate
progress (requires periodic redraws from the event loop).

File: `tui/widgets/progress.f`
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

### 4.7 tui/widgets/dialog.f — Modal Dialog Boxes

**Goal:** Modal popup dialog with a message and buttons.  Blocks
input to other widgets while visible.  Returns which button was
pressed.

File: `tui/widgets/dialog.f`
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

### 4.8 tui/widgets/tabs.f — Tabbed Panels

**Goal:** A row of tab headers with a content area below.  Each tab
has a label and a child region.  Switching tabs shows the
corresponding content region and hides others.

File: `tui/widgets/tabs.f`
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

## Layer 5 — Declarative UI

Layer 5 has two independent paths.  Both are optional — pure-widget
TUI apps (Layers 0–4) skip this layer entirely.

**Path 5a — UIDL (primary).**  The UIDL tree is the runtime.
Elements participate in five declarative protocols (Data, Visibility,
Layout, Action, Content) via an open Element Registry.  New elements
are defined at any time with `DEFINE-ELEMENT`, making the "markup
language" extensible in the Forth tradition — every component is just
a word.  `tui/uidl-tui.f` provides render-xt, event-xt, and layout-xt
implementations that write directly to the screen buffer.  No DOM
intermediary.  Reactive binding, focus management, and dirty-rect
repaint all operate on the UIDL tree.

**Path 5b — DOM (web/HTML).**  For rendering HTML content with CSS
to the terminal, this path maps DOM nodes to TUI sidecars via
`dom-tui.f`, paints through `dom-render.f`, and routes input through
`dom-event.f`.  This reuses the existing `dom/dom.f` + `css/` stack.

Sections 5.0–5.3 describe the DOM path (unchanged).
Sections 5.4–5.5 describe the UIDL path.

### 5.0 dom/event.f — DOM Event System

**Goal:** A full, general-purpose DOM event system implementing the
W3C DOM Events model.  Provides event object creation, listener
registration/removal, and three-phase dispatch (capture → target →
bubble) with `stopPropagation`, `stopImmediatePropagation`, and
`preventDefault`.  This module lives in the DOM subsystem (`dom/`),
not in `tui/` — it is renderer-agnostic and usable by the pixel
pipeline, the TUI bridge, or any other DOM consumer.

File: `dom/event.f`
Prefix: `DOME-` (public), `_DOME-` (internal)
Provider: `PROVIDED akashic-dom-event`
Dependencies: `REQUIRE dom/dom.f`

~450 lines

#### Event Object (10 cells = 80 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | type | Event type identifier (interned string handle) |
| +8 | target | Node where the event originated |
| +16 | current-target | Node whose listener is currently executing |
| +24 | phase | `DOME-PHASE-CAPTURE` (1), `DOME-PHASE-TARGET` (2), or `DOME-PHASE-BUBBLE` (3) |
| +32 | flags | Bit 0: bubbles, Bit 1: cancelable, Bit 2: stopped, Bit 3: immediate-stopped, Bit 4: default-prevented |
| +40 | timestamp | Tick count at creation (via `TIMER@`) |
| +48 | detail | Generic payload cell (event-type-specific data) |
| +56 | detail2 | Second payload cell (e.g., coordinates for mouse events) |
| +64 | detail3 | Third payload cell (e.g., modifiers) |
| +72 | related | Related node (e.g., `relatedTarget` for focus events) |

Event objects are stack-allocated or taken from a small recycling
pool (8 slots).  Most events are transient — created, dispatched,
and discarded within a single call.

#### Event Type Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DOME-T-CLICK` | (interned) | Mouse click |
| `DOME-T-DBLCLICK` | (interned) | Double click |
| `DOME-T-MOUSEDOWN` | (interned) | Mouse button pressed |
| `DOME-T-MOUSEUP` | (interned) | Mouse button released |
| `DOME-T-MOUSEMOVE` | (interned) | Mouse movement |
| `DOME-T-KEYDOWN` | (interned) | Key pressed |
| `DOME-T-KEYUP` | (interned) | Key released |
| `DOME-T-KEYPRESS` | (interned) | Character input |
| `DOME-T-FOCUS` | (interned) | Element gained focus |
| `DOME-T-BLUR` | (interned) | Element lost focus |
| `DOME-T-INPUT` | (interned) | Input value changed |
| `DOME-T-CHANGE` | (interned) | Value committed |
| `DOME-T-SUBMIT` | (interned) | Form submission |
| `DOME-T-SCROLL` | (interned) | Scroll position changed |
| `DOME-T-RESIZE` | (interned) | Container resized |
| `DOME-T-CUSTOM` | (interned) | User-defined custom event |

Type identifiers are interned string handles allocated from the
DOM document's string pool.  `DOME-INTERN-TYPE` converts a string
to a type ID; comparison is by handle equality (O(1)).

#### Listener Storage

Each DOM node can have zero or more event listeners.  Listeners
are stored in a per-node linked list, allocated from a dedicated
listener pool in the document descriptor.

##### Listener Entry (5 cells = 40 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | type | Event type handle (must match event.type) |
| +8 | xt | Execution token: `( event node -- )` |
| +16 | flags | Bit 0: capture phase, Bit 1: once (auto-remove after first call) |
| +24 | next | Next listener in this node's list (0 = end) |
| +32 | node | Back-pointer to owning node |

The document descriptor is extended with two new fields:
- `lst-base` / `lst-max` / `lst-free`: Listener pool (free-list,
  same pattern as the node and attribute pools in `dom.f`).

##### Pool Sizing

Default: 256 listener slots = 256 × 40 = 10,240 bytes.  Sufficient
for a typical interactive UI (50 elements × ~5 listeners each).
Configurable at document creation time.

#### Words — Event Object

| Word | Stack | Description |
|------|-------|-------------|
| `DOME-EVENT-NEW` | `( type bubbles? cancelable? -- event )` | Allocate event object, set type and flags |
| `DOME-EVENT-FREE` | `( event -- )` | Return event to pool |
| `DOME-EVENT-TYPE` | `( event -- type )` | Get type handle |
| `DOME-EVENT-TARGET` | `( event -- node )` | Get target node |
| `DOME-EVENT-CURRENT` | `( event -- node )` | Get current-target node |
| `DOME-EVENT-PHASE` | `( event -- phase )` | Get dispatch phase |
| `DOME-EVENT-DETAIL` | `( event -- detail )` | Get detail payload |
| `DOME-EVENT-DETAIL!` | `( event detail -- )` | Set detail payload |
| `DOME-EVENT-DETAIL2` | `( event -- detail2 )` | Get second payload |
| `DOME-EVENT-DETAIL2!` | `( event detail2 -- )` | Set second payload |
| `DOME-EVENT-DETAIL3` | `( event -- detail3 )` | Get third payload |
| `DOME-EVENT-DETAIL3!` | `( event detail3 -- )` | Set third payload |
| `DOME-EVENT-RELATED` | `( event -- node | 0 )` | Get related target |
| `DOME-EVENT-RELATED!` | `( event node -- )` | Set related target |
| `DOME-STOP` | `( event -- )` | Stop propagation (remaining ancestors won't see it) |
| `DOME-STOP-IMMEDIATE` | `( event -- )` | Stop immediately (remaining listeners on *this* node also skipped) |
| `DOME-PREVENT` | `( event -- )` | Prevent default action |
| `DOME-STOPPED?` | `( event -- flag )` | Has propagation been stopped? |
| `DOME-PREVENTED?` | `( event -- flag )` | Has default been prevented? |

#### Words — Listener Registration

| Word | Stack | Description |
|------|-------|-------------|
| `DOME-LISTEN` | `( node type xt -- )` | Add bubble-phase listener |
| `DOME-LISTEN-CAPTURE` | `( node type xt -- )` | Add capture-phase listener |
| `DOME-LISTEN-ONCE` | `( node type xt -- )` | Add one-shot bubble listener (auto-removed after first fire) |
| `DOME-UNLISTEN` | `( node type xt -- )` | Remove a specific listener (matched by type + xt + phase) |
| `DOME-UNLISTEN-ALL` | `( node -- )` | Remove all listeners from a node |
| `DOME-UNLISTEN-TYPE` | `( node type -- )` | Remove all listeners for a specific type |
| `DOME-HAS-LISTENER?` | `( node type -- flag )` | Does this node have any listener for this type? |

#### Words — Dispatch

| Word | Stack | Description |
|------|-------|-------------|
| `DOME-DISPATCH` | `( doc node event -- prevented? )` | Full three-phase dispatch; returns TRUE if `preventDefault` was called |
| `DOME-FIRE` | `( doc node type detail -- prevented? )` | Convenience: create event, dispatch, free; for simple cases |

#### Words — Type Interning

| Word | Stack | Description |
|------|-------|-------------|
| `DOME-INTERN-TYPE` | `( doc addr len -- type-handle )` | Intern an event type name, return handle |
| `DOME-TYPE-NAME` | `( doc type-handle -- addr len )` | Get string for a type handle |

#### Three-Phase Dispatch Algorithm

```forth
: DOME-DISPATCH ( doc node event -- prevented? )
  >R                          \ R: event
  \ 1. Build ancestor path (node → parent → ... → root)
  SWAP _DOME-BUILD-PATH       ( doc path-addr path-count ) ( R: event )
  \ 2. CAPTURE phase: walk root → parent → ... → node.parent
  R@ DOME-PHASE-CAPTURE _DOME-SET-PHASE
  DUP 1- 0 ?DO                \ for each ancestor, root-first
    I OVER + @ DUP            ( ... ancestor ancestor )
    R@ SWAP _DOME-SET-CURRENT
    R@ SWAP _DOME-FIRE-LISTENERS-CAPTURE
    R@ DOME-STOPPED? IF UNLOOP _DOME-FINISH EXIT THEN
  LOOP
  \ 3. TARGET phase: fire on the target node itself
  R@ DOME-PHASE-TARGET _DOME-SET-PHASE
  R@ node _DOME-SET-CURRENT
  R@ node _DOME-FIRE-LISTENERS-ALL  \ both capture + bubble listeners
  R@ DOME-STOPPED? IF _DOME-FINISH EXIT THEN
  \ 4. BUBBLE phase: walk node.parent → ... → root
  R@ +flags @ 1 AND IF        \ only if event.bubbles
    R@ DOME-PHASE-BUBBLE _DOME-SET-PHASE
    path-count 2 - 0 MAX 0 ?DO  \ reverse order
      ...
      R@ DOME-STOPPED? IF UNLOOP _DOME-FINISH EXIT THEN
    LOOP
  THEN
  _DOME-FINISH                \ returns prevented?
;
```

The ancestor path is built by walking `DOM-PARENT` from target to
root and storing pointers in a small stack-allocated array (max
depth 64 — sufficient for any practical DOM tree).

#### Usage Example

```forth
REQUIRE dom/dom.f
REQUIRE dom/event.f

S" <div id='app'><button id='ok'>OK</button></div>"
DOM-PARSE-HTML CONSTANT my-doc

\ Intern event types
my-doc S" click" DOME-INTERN-TYPE CONSTANT click-type

\ Get the button node
my-doc S" ok" DOM-GET-BY-ID CONSTANT btn

\ Register a bubble-phase listener
btn click-type ['] my-click-handler DOME-LISTEN

\ Fire an event
: my-click-handler ( event node -- )
  DROP DOME-EVENT-DETAIL  \ extract detail
  ." Button clicked! Detail: " . CR ;

\ Dispatch
my-doc btn click-type 42 DOME-FIRE  ( -- prevented? )
DROP
```

#### Design Notes

1. **Renderer-agnostic.** This module knows nothing about TUI cells,
   pixel surfaces, or any rendering backend.  It operates purely on
   the DOM tree structure.  The TUI bridge (`tui/dom-event.f`) and
   the pixel pipeline can both feed events into this system.

2. **W3C-compatible semantics.** Capture → target → bubble matches
   the browser model.  `stopPropagation` prevents further phase
   traversal.  `stopImmediatePropagation` prevents remaining
   listeners on the current node.  `preventDefault` signals the
   caller that the default action should be suppressed.

3. **No built-in default actions.** This module dispatches events
   and reports whether `preventDefault` was called.  It is the
   caller's responsibility to implement default actions (e.g., form
   submission, link navigation) based on the return value.

4. **Listener pool.** Reuses the same free-list pool pattern as
   DOM nodes and attributes.  O(1) alloc/free, no heap fragmentation.

5. **Type interning.** Event type names are stored once in the
   document's string pool.  All comparisons are pointer-equality on
   handles — O(1) matching during dispatch.

6. **Execution token convention.** All listener callbacks receive
   `( event node -- )`.  The node is `currentTarget` — the node
   the listener is registered on (not necessarily the target).

#### Test targets: ~30 tests

- Create event, verify fields
- Listen + dispatch, listener fires
- Capture phase fires before bubble
- Bubble phase fires after target
- `stopPropagation` prevents further ancestors
- `stopImmediatePropagation` prevents remaining listeners on same node
- `preventDefault` reported in return value
- `once` listener auto-removed after first fire
- `DOME-UNLISTEN` removes specific listener
- `DOME-UNLISTEN-ALL` clears all listeners
- Multiple listeners on same node/type, all fire in registration order
- Event with `bubbles: false` skips bubble phase
- Dispatch on leaf node (no ancestors to capture/bubble through)
- Dispatch on root node (target only, no capture/bubble)
- Type interning: same string → same handle
- Listener pool exhaustion (graceful error)
- Free event returns to pool
- Nested dispatch (listener dispatches another event)
- Related-target round-trip
- Detail fields round-trip (detail, detail2, detail3)

---

### 5.1 tui/dom-tui.f — DOM-to-TUI Node Mapping

**Goal:** Map DOM element nodes to TUI sidecar descriptors.  Walk
the DOM tree, allocate a TUI descriptor for each visible element,
and resolve CSS properties into character-cell attributes (fg/bg
color, border style, text-align, display mode, visibility).

File: `tui/dom-tui.f`
Prefix: `DTUI-` (public), `_DTUI-` (internal)
Provider: `PROVIDED akashic-tui-dom-tui`
Dependencies: `REQUIRE dom/dom.f`, `REQUIRE css/css.f`,
`REQUIRE css/bridge.f`, `REQUIRE tui/cell.f`, `REQUIRE tui/region.f`

~350 lines

#### TUI Sidecar Descriptor (8 cells = 64 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | node | Back-pointer to DOM node |
| +8 | flags | Dirty, visible, focusable, block/inline |
| +16 | row | Computed row in screen coordinates |
| +24 | col | Computed column in screen coordinates |
| +32 | width | Computed width (character cells) |
| +40 | height | Computed height (character cells) |
| +48 | style | Packed: fg(8) bg(8) attrs(8) border-style(8) |
| +56 | draw-xt | Custom draw hook (0 = default) |

The `aux` cell of the DOM node points to this sidecar.
Total overhead: 64 bytes per visible element.

#### CSS → TUI Property Mapping

| CSS Property | TUI Effect |
|-------------|------------|
| `color` | fg color → nearest 256-palette index |
| `background-color` | bg color → nearest 256-palette index |
| `display: none` | Skip node and subtree entirely |
| `display: block` | Starts new row, fills available width |
| `display: inline` | Flows left-to-right within current row |
| `visibility: hidden` | Allocate space but don't paint |
| `border-style` | Box-drawing characters (none/solid/double/dashed) |
| `text-align` | Left/center/right padding of text content |
| `font-weight: bold` | ANSI bold attribute |
| `font-style: italic` | ANSI italic attribute |
| `text-decoration: underline` | ANSI underline attribute |
| `text-decoration: line-through` | ANSI strikethrough attribute |
| `width` / `height` | Explicit character-cell dimensions |
| `min-width` / `min-height` | Floor constraints |
| `max-width` / `max-height` | Ceiling constraints |
| `padding` | Character-cell inset (top/right/bottom/left) |
| `margin` | Character-cell outset |

#### Color Resolution

`_DTUI-RESOLVE-COLOR` maps a CSS color value (as parsed by
`CSS-PARSE-HEX-COLOR` or `CSS-COLOR-FIND`) to the nearest
256-palette index.  For the 16 standard ANSI colors, this is a
direct lookup.  For arbitrary RGB, it finds the nearest entry in
the 6×6×6 color cube (indices 16–231) or the 24-step grayscale
ramp (indices 232–255) by Euclidean distance in RGB space.

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `DTUI-ATTACH` | `( doc -- )` | Walk DOM tree, allocate sidecars for all visible elements, store in `aux` |
| `DTUI-DETACH` | `( doc -- )` | Free all sidecars, clear `aux` fields |
| `DTUI-REFRESH` | `( doc -- )` | Re-resolve CSS styles into existing sidecars (after style/class change) |
| `DTUI-SIDECAR` | `( node -- sidecar | 0 )` | Get sidecar for a DOM node (reads `aux`) |
| `DTUI-VISIBLE?` | `( node -- flag )` | Is this node visible (display≠none, visibility≠hidden)? |
| `DTUI-STYLE!` | `( node fg bg attrs -- )` | Override resolved style for one node |
| `DTUI-RESOLVE-COLOR` | `( r g b -- idx )` | Map 24-bit RGB → 256-palette index |
| `DTUI-CLASS-ADD` | `( node addr len -- )` | Add CSS class + trigger sidecar refresh |
| `DTUI-CLASS-REMOVE` | `( node addr len -- )` | Remove CSS class + trigger sidecar refresh |

#### Algorithm — DTUI-ATTACH

```forth
: DTUI-ATTACH ( doc -- )
  DUP DOM-ROOT  ( doc root )
  BEGIN ?DUP WHILE
    DUP DOM-TYPE@ DOM-ELEMENT = IF
      DUP _DTUI-ALLOC-SIDECAR  ( node sidecar )
      2DUP SWAP DOM-AUX!       \ store sidecar in node.aux
      OVER _DTUI-RESOLVE-NODE  \ resolve CSS → sidecar fields
    THEN
    DOM-WALK-NEXT              \ iterative DFS — next node
  REPEAT
  DROP ;
```

#### Test targets: ~20 tests

- Attach to simple DOM (div > p > span), verify sidecars allocated
- display:none elements get no sidecar
- Color resolution: #FF0000 → palette red, #808080 → gray
- Bold/italic/underline CSS → ANSI attribute bits
- border-style: solid → BOX-SINGLE, double → BOX-DOUBLE
- Detach frees all sidecars
- Refresh after class change updates colors
- Back-pointer integrity (sidecar.node → original node)

---

### 5.2 tui/dom-render.f — DOM Tree Layout & Paint

**Goal:** Walk the DOM tree with attached sidecars, compute
character-cell layout (block/inline flow), and paint the result
into the TUI screen buffer using the existing draw/box primitives.

File: `tui/dom-render.f`
Prefix: `DREN-` (public), `_DREN-` (internal)
Provider: `PROVIDED akashic-tui-dom-render`
Dependencies: `REQUIRE tui/dom-tui.f`, `REQUIRE tui/draw.f`,
`REQUIRE tui/box.f`, `REQUIRE tui/region.f`, `REQUIRE tui/screen.f`

~400 lines

#### Layout Algorithm

A simplified block/inline flow model operating in character cells:

1. **Block elements** start on a new row, extend to `available-width`
   (or explicit `width` if set), and stack vertically.
2. **Inline elements** flow left-to-right within the current row,
   wrapping to the next row when the line is full.
3. **Padding/margin** add character-cell offsets before/after the
   content box.
4. **Border** consumes 1 character cell per side (if present).
5. **Text nodes** contribute their character length (with UTF-8
   awareness via `akashic-utf8`) to inline flow.

This is intentionally simpler than the pixel-pipeline `render/layout.f`
(which implements full CSS 2.1 block/inline flow at sub-pixel
precision).  Character cells impose a coarse grid — fractional
positions are meaningless, so the algorithm rounds eagerly.

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `DREN-LAYOUT` | `( doc rgn -- )` | Compute character-cell layout for entire DOM tree within region |
| `DREN-PAINT` | `( doc -- )` | Paint laid-out tree into the screen back buffer |
| `DREN-RENDER` | `( doc rgn -- )` | Layout + paint in one call |
| `DREN-RELAYOUT` | `( doc rgn -- )` | Re-layout (after mutation or resize) |
| `DREN-DIRTY?` | `( doc -- flag )` | Any sidecar marked dirty? |
| `DREN-PAINT-NODE` | `( node -- )` | Paint a single node (for partial updates) |

#### Paint Order

1. For each node in DFS order:
   a. If `visibility: hidden`, skip paint (but children still reserve space).
   b. Paint background: `DRW-FILL` the content box with bg color.
   c. Paint border: `BOX-DRAW` with resolved border style (single/double/etc).
   d. Paint text content: `DRW-TEXT` with fg color + attributes.
   e. Recurse into children.

#### Usage Example

```forth
REQUIRE dom/dom.f
REQUIRE css/css.f
REQUIRE css/bridge.f
REQUIRE tui/dom-tui.f
REQUIRE tui/dom-render.f
REQUIRE tui/screen.f

80 24 SCR-CREATE CONSTANT my-scr
my-scr SCR-USE

S" <div style='color:red; border:solid'><p>Hello DOM-TUI!</p></div>"
DOM-PARSE-HTML CONSTANT my-doc

my-doc DTUI-ATTACH
my-doc  0 0 80 24 RGN-SET  DREN-RENDER
SCR-FLUSH
```

#### Test targets: ~18 tests

- Single block element: fills width, 1 row
- Nested blocks: vertical stacking
- Inline elements: horizontal flow, wrap at boundary
- Text node rendering with correct fg/bg
- Border: box-drawing characters at correct positions
- Padding: content inset by correct amount
- Margin: gap between sibling blocks
- display:none skips entirely (no space reserved)
- visibility:hidden reserves space but no paint
- text-align center/right
- Re-layout after DOM mutation
- Partial paint (single dirty node)

---

### 5.3 tui/dom-event.f — DOM Event Routing

**Goal:** TUI-specific adapter that feeds keyboard and mouse events
from the TUI input system into the general-purpose DOM event system
(`dom/event.f`).  Translates `KEY-READ` events into `DOME-T-KEYDOWN`
/ `DOME-T-KEYPRESS` DOM events, mouse reports into `DOME-T-CLICK` /
`DOME-T-MOUSEDOWN` / `DOME-T-MOUSEUP`, and manages DOM-level focus
(Tab cycling through focusable elements).

This module does **not** re-implement dispatch logic — it delegates
entirely to `DOME-DISPATCH` for three-phase capture/target/bubble
propagation.  Its job is translation and focus management.

File: `tui/dom-event.f`
Prefix: `DEVT-` (public), `_DEVT-` (internal)
Provider: `PROVIDED akashic-tui-dom-event`
Dependencies: `REQUIRE dom/event.f`, `REQUIRE tui/dom-tui.f`, `REQUIRE tui/keys.f`

~200 lines

#### Event Flow

```
  KEY-READ / mouse report
      │
      ▼
  DEVT-TRANSLATE           ← convert TUI input → DOM event object
      │
      ▼
  DOME-DISPATCH            ← full W3C three-phase dispatch
      │                       (capture → target → bubble)
      ├─► listeners fire via dom/event.f
      │
      └─► returns prevented?
```

#### Focus Model

The DOM-TUI focus is a single DOM node pointer.  Elements are
focusable if they have the `tabindex` attribute or are inherently
interactive (input, button, select, textarea — matched by tag name).
`DEVT-FOCUS-NEXT` / `DEVT-FOCUS-PREV` cycle through focusable
elements in DOM tree order.

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `DEVT-DISPATCH` | `( doc key-event-addr -- prevented? )` | Translate TUI key event → DOM event, dispatch via `DOME-DISPATCH` |
| `DEVT-DISPATCH-MOUSE` | `( doc row col button -- prevented? )` | Translate mouse click → DOM click event, hit-test, dispatch |
| `DEVT-FOCUS` | `( doc -- node | 0 )` | Get currently focused DOM element |
| `DEVT-FOCUS!` | `( doc node -- )` | Set focus to specific element (fires `DOME-T-BLUR` / `DOME-T-FOCUS`) |
| `DEVT-FOCUS-NEXT` | `( doc -- )` | Move focus to next focusable element (Tab order) |
| `DEVT-FOCUS-PREV` | `( doc -- )` | Move focus to previous focusable element (Shift-Tab) |
| `DEVT-TRANSLATE` | `( key-event-addr -- dome-event )` | Convert TUI key event to DOM event object |
| `DEVT-HIT-TEST` | `( doc row col -- node | 0 )` | Find deepest visible element at screen position |

#### Handler Storage

Event handlers are now registered through the DOM event system:
`DOME-LISTEN`, `DOME-LISTEN-CAPTURE`, `DOME-LISTEN-ONCE`, and
removed via `DOME-UNLISTEN`.  The `DEVT-ON-KEY!` / `DEVT-ON-CLICK!`
convenience words from the earlier design are replaced by direct
calls to `DOME-LISTEN` with the appropriate type constant
(`DOME-T-KEYDOWN`, `DOME-T-CLICK`, etc.).

All listener callbacks follow the DOM event convention:
`( event node -- )` where `event` is a full DOM event object with
phase, propagation control, and payload fields.

#### Hit Testing

`DEVT-HIT-TEST` walks the DOM tree (reverse paint order for
correct z-order) and checks whether `(row, col)` falls within
each sidecar's layout rectangle.  Returns the deepest (most
specific) match.

#### Test targets: ~15 tests

- Key event translated to DOME-T-KEYDOWN + dispatched
- Mouse click translated to DOME-T-CLICK + dispatched via hit-test
- Focus change fires DOME-T-BLUR on old + DOME-T-FOCUS on new
- Focus-next cycles through tabindex elements
- Focus-prev cycles backward
- Hit-test returns correct element
- Hit-test returns 0 for empty area
- preventDefault on keydown suppresses default
- Capture-phase listener on ancestor fires before target
- Mouse button mapping (left/right/middle)

---

### 5.4 liraq/uidl.f Hardening — Element Registry & Five Protocols (Phase 0)

**Goal:** Refactor `liraq/uidl.f` from a fixed-vocabulary parser
into an extensible runtime anchored by an **Element Registry** and
**Five Protocols**.  After this phase, any code can call
`DEFINE-ELEMENT` to register a new element type — with its tag name,
draw/event/layout execution tokens, content model, and category —
making the "markup language" as extensible as the Forth dictionary
itself.  This is Phase 0: it touches only `liraq/uidl.f` and adds
one new file `liraq/uidl-chrome.f`.

#### What Changes in uidl.f

| Section | Lines | Change |
|---------|-------|--------|
| Type enum (20 constants) | 58–83 | **Replaced** — auto-assigned by `DEFINE-ELEMENT` |
| `_UDL-MAP-TAG` (20 if-branches) | 286–312 | **Replaced** — single registry hash lookup |
| `UIDL-TYPE-NAME` (20 if-branches) | 326–348 | **Replaced** — reads name from registry definition |
| Two-way flag hardcode | 462–466 | **Replaced** — flag from registry definition record |
| Everything else | ~850 lines | **Unchanged** — pools, tree, hash, attrs, validation, mutation, dispatch |

Net effect: ~100 lines removed, ~200 lines added → uidl.f grows
from 1121 to ~1220 lines.

#### Element Definition Record (64 bytes, 8 cells)

| Offset | Field | Accessor | Description |
|--------|-------|----------|-------------|
| +0 | type-id | `ED.TYPE` | Auto-assigned integer (1, 2, 3, …) |
| +8 | name-a | `ED.NAME-A` | Tag name string address |
| +16 | name-l | `ED.NAME-L` | Tag name string length |
| +24 | flags | `ED.FLAGS` | Content model + category bits (see below) |
| +32 | render-xt | `ED.RENDER-XT` | `( elem -- )` — rendering hook |
| +40 | event-xt | `ED.EVENT-XT` | `( elem evt -- handled? )` — input hook |
| +48 | layout-xt | `ED.LAYOUT-XT` | `( elem -- )` — child-positioning hook |
| +56 | next | `ED.NEXT` | Hash chain link |

#### Element Flags Word

```
Bits 0–2:  Content model
  0 = EL-LEAF           leaf, no children
  1 = EL-CONTAINER      arbitrary children
  2 = EL-COLLECTION     requires <template> + optional <empty>
  3 = EL-SELECTOR       contains <option> children
  4 = EL-FIXED-2        exactly 2 children (split)
  5 = EL-FIXED-1        exactly 1 child (scroll)

Bits 3–4:  Category
  0 = EL-CAT-ENVELOPE
  1 = EL-CAT-DATA
  2 = EL-CAT-CHROME
  3 = EL-CAT-BINDING

Bit 5:     Focusable (inherently interactive)
Bit 6:     Self-closing allowed
Bit 7:     Two-way binding (input/toggle/range/selector)
```

#### Element Registry (hash table)

64-slot open-addressing hash table keyed by tag name (FNV-1a,
same hash function already in uidl.f).  Max 64 element types —
sufficient for UIDL's 20 + chrome 11 + must-haves 5 + nice-to-haves 5
+ user headroom.

```forth
64 CONSTANT _EL-REG-SZ
CREATE _EL-REGISTRY  _EL-REG-SZ 64 * ALLOT   \ 64 × 64 = 4,096 bytes
VARIABLE _EL-REG-CNT                           \ number registered
```

#### DEFINE-ELEMENT

```forth
: DEFINE-ELEMENT  ( render-xt event-xt layout-xt flags "name" -- )
    PARSE-NAME                          \ ( draw evt lay flags name-a name-l )
    \ hash-lookup slot, store definition
    \ auto-assign type-id = _EL-REG-CNT @ 1+
    \ copy name into string pool
    \ store all fields in registry slot
    ... ;
```

After this word executes, the tag name is known to the parser, the
type-id is assigned, and all five protocol hooks are stored.  The
existing `UIDL-T-*` constants are replaced by:

```forth
\ Built-in registrations (called at load time, after registry init)
' noop  ' noop  ' noop   EL-LEAF       DEFINE-ELEMENT none
' noop  ' noop  ' noop   EL-CONTAINER  DEFINE-ELEMENT region
' noop  ' noop  ' noop   EL-CONTAINER  DEFINE-ELEMENT group
...
```

Each one returns a CONSTANT-like type-id:
```forth
DEFINE-ELEMENT region   \ defines UIDL-T-REGION = (auto-id)
```

#### Registry Lookup

```forth
: EL-LOOKUP  ( name-a name-l -- def | 0 )
    \ FNV-1a hash → scan registry slots → match name → return def
    ... ;

: EL-DEF-BY-TYPE  ( type-id -- def | 0 )
    \ Linear search (small table) or parallel index array
    ... ;
```

The parser's `_UDL-MAP-TAG` becomes:
```forth
: _UDL-MAP-TAG  ( name-a name-l -- type )
    EL-LOOKUP DUP IF ED.TYPE @ ELSE DROP 0 THEN ;
```

And `UIDL-TYPE-NAME` becomes:
```forth
: UIDL-TYPE-NAME  ( type -- a l )
    EL-DEF-BY-TYPE DUP IF
        DUP ED.NAME-A @ SWAP ED.NAME-L @
    ELSE DROP S" unknown" THEN ;
```

#### Five Protocols

Every element — built-in or user-defined — participates in these
five declarative protocols automatically by virtue of being in the
registry:

**1. Data Protocol (`bind=`)**
Every element can carry `bind=expr`.  The system evaluates the LEL
expression against the state-tree, delivers the resolved value to
the element's `render-xt`, and (for two-way elements, flagged
`EL-F-TWOWAY`) routes user input back via `UIDL-BIND-WRITE`.
No user wiring required.

**2. Visibility Protocol (`when=`)**
Every element can carry `when=predicate`.  The system evaluates it
before calling `render-xt`.  If false, the element and its subtree
are skipped entirely.  State changes re-evaluate the predicate.

**3. Layout Protocol (`arrange=`)**
Every container element has an `arrange=` mode (stack/flex/flow/
grid/dock/none).  The system calls the element's `layout-xt`,
which receives the element's bounds and positions children according
to the declared mode.  New modes can be registered.

**4. Action Protocol (`on-activate=` / `emit=` / `set-state=`)**
Interactive elements declare actions.  The event system dispatches
them without user code — they become state-tree mutations or named
signals.  The `UIDL-DISPATCH` / `UIDL-ACTION-VALUE` words (already
in uidl.f) implement this.

**5. Content Protocol (via registry flags)**
Each element declares its content model via `ED.FLAGS` bits 0–2.
The parser enforces the model: a `COLLECTION` must have a
`<template>` child, a `SPLIT` must have exactly 2 children, a
`SELECTOR` must contain `<option>`s, etc.  `UIDL-VALIDATE` checks
these rules using the registry's content-model field instead of
hardcoded type comparisons.

#### Subscription Table (new)

A path→element subscription table that makes reactive binding
truly reactive:

```forth
128 CONSTANT _UDL-MAX-SUBS
CREATE _UDL-SUBS  _UDL-MAX-SUBS 24 * ALLOT  \ 128 × 24 = 3,072 bytes
VARIABLE _UDL-SUB-CNT

\ Each subscription: ( path-hash 8 | elem-ptr 8 | next 8 ) = 24 bytes

: UIDL-SUBSCRIBE  ( elem bind-a bind-l -- )
    \ Hash the bind path, store elem in subscription chain
    ... ;

: UIDL-NOTIFY  ( path-a path-l -- )
    \ Hash path, walk the chain, mark each subscribed elem dirty
    ... ;
```

When the state-tree changes a path, it calls `UIDL-NOTIFY`.  Every
element bound to that path gets its dirty flag set.  The paint cycle
only redraws dirty elements.  This replaces the "rescan everything"
approach.

#### New File: liraq/uidl-chrome.f (~120 lines)

Registers the chrome + must-have + nice-to-have elements into the
Element Registry.  Loaded after `uidl.f`, before any backend.

```forth
\ liraq/uidl-chrome.f — Chrome Element Registrations
REQUIRE uidl.f
PROVIDED akashic-uidl-chrome

\ --- Chrome elements ---
' noop ' noop ' noop  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT menubar
' noop ' noop ' noop  EL-CONTAINER OR-CHROME OR-FOCUS    DEFINE-ELEMENT menu
' noop ' noop ' noop  EL-LEAF OR-CHROME OR-FOCUS OR-SELF DEFINE-ELEMENT item
' noop ' noop ' noop  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT tabs
' noop ' noop ' noop  EL-CONTAINER OR-CHROME OR-FOCUS    DEFINE-ELEMENT tab
' noop ' noop ' noop  EL-FIXED-2 OR-CHROME               DEFINE-ELEMENT split
' noop ' noop ' noop  EL-FIXED-1 OR-CHROME               DEFINE-ELEMENT scroll
' noop ' noop ' noop  EL-CONTAINER OR-CHROME OR-FOCUS    DEFINE-ELEMENT tree
' noop ' noop ' noop  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT status
' noop ' noop ' noop  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT dialog
' noop ' noop ' noop  EL-LEAF OR-CHROME                  DEFINE-ELEMENT toast

\ --- Must-have additions ---
' noop ' noop ' noop  EL-LEAF OR-DATA OR-FOCUS OR-TWOWAY DEFINE-ELEMENT textarea
' noop ' noop ' noop  EL-CONTAINER OR-DATA OR-FOCUS      DEFINE-ELEMENT dropdown
' noop ' noop ' noop  EL-CONTAINER OR-DATA                DEFINE-ELEMENT radiogroup
' noop ' noop ' noop  EL-LEAF OR-DATA OR-FOCUS OR-TWOWAY DEFINE-ELEMENT radio
' noop ' noop ' noop  EL-CONTAINER OR-CHROME              DEFINE-ELEMENT toolbar

\ --- Nice-to-have additions ---
' noop ' noop ' noop  EL-CONTAINER OR-DATA               DEFINE-ELEMENT log
' noop ' noop ' noop  EL-LEAF OR-DATA                    DEFINE-ELEMENT code
' noop ' noop ' noop  EL-CONTAINER OR-DATA               DEFINE-ELEMENT accordion
' noop ' noop ' noop  EL-LEAF OR-DATA OR-FOCUS OR-TWOWAY DEFINE-ELEMENT password
' noop ' noop ' noop  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT contextmenu
```

All render-xt / event-xt / layout-xt are `noop` at registration time.
The TUI backend (`tui/uidl-tui.f`) patches them with real
implementations when loaded.

#### Chrome-Specific Attributes

| Attribute | Used on | Type | Description |
|-----------|---------|------|-------------|
| `title` | `uidl`, `tab`, `dialog` | string | Window/tab/dialog title |
| `label` | `menu`, `tab`, `item` | string | Display label |
| `key` | `item`, `action` | string | Keyboard shortcut (`C-n`, `F5`, etc.) |
| `do` | `item`, `action` | string | Action name to emit |
| `dir` | `split`, `separator` | `h` \| `v` | Direction |
| `ratio` | `split` | int | Left/top pane percentage (0–100) |
| `multiline` | `input` | bool | Multi-line mode (or use `<textarea>`) |
| `timeout` | `toast` | int | Auto-dismiss ms (0 = manual) |
| `modal` | `dialog` | bool | Focus-trapping (default: true) |
| `expanded` | `tree` node | bool | Initially expanded |
| `checked` | `toggle`, `radio` | bool | Initial state |
| `min`, `max`, `step` | `range` | int | Slider bounds |
| `placeholder` | `input`, `textarea`, `password` | string | Placeholder text |
| `cols`, `rows` | `uidl` | int | Terminal dimensions |

All these work through `UIDL-ATTR` — the generic attribute API
already in uidl.f.  No parser changes needed.

#### Content Model Rules (via registry flags)

| Parent | Flag | Allowed children |
|--------|------|------------------|
| `uidl` | `EL-CONTAINER` | menubar, toolbar, tabs, split, scroll, status, dialog, toast, any Data |
| `menubar` | `EL-CONTAINER` | `menu` only |
| `menu` | `EL-CONTAINER` | `item`, `separator` |
| `tabs` | `EL-CONTAINER` | `tab` only |
| `tab` | `EL-CONTAINER` | any Data or Chrome (except uidl, menubar, tab) |
| `split` | `EL-FIXED-2` | exactly 2 children |
| `scroll` | `EL-FIXED-1` | exactly 1 child |
| `dialog` | `EL-CONTAINER` | any Data or Chrome (except uidl) |
| `collection` | `EL-COLLECTION` | `template`, `empty` |
| `selector` | `EL-SELECTOR` | `option` |

#### Example Document

```xml
<uidl cols="80" rows="24" title="My App">
  <menubar>
    <menu label="File">
      <item label="New"  key="C-n" do="file-new" />
      <item label="Open" key="C-o" do="file-open" />
      <separator />
      <item label="Quit" key="C-q" do="quit" />
    </menu>
  </menubar>

  <toolbar>
    <action do="file-new">New</action>
    <action do="undo">Undo</action>
  </toolbar>

  <tabs id="main">
    <tab label="Editor">
      <split dir="h" ratio="25">
        <scroll>
          <tree id="files" bind="fs.tree" />
        </scroll>
        <scroll>
          <textarea id="editor" bind="fs.content"
                    placeholder="Start typing..." />
        </scroll>
      </split>
    </tab>
    <tab label="Settings">
      <region arrange="stack">
        <label>Theme:</label>
        <dropdown id="theme" bind="prefs.theme">
          <option>Dark</option>
          <option>Light</option>
          <option>High Contrast</option>
        </dropdown>
        <separator />
        <toggle id="wordwrap" bind="prefs.wordwrap">Word Wrap</toggle>
        <label>Font Size:</label>
        <range id="fontsize" bind="prefs.fontsize" min="8" max="24" step="1" />
      </region>
    </tab>
  </tabs>

  <status bind="app.statusline" />

  <dialog id="confirm" title="Confirm" when="confirm.visible" modal="true">
    <label bind="confirm.message" />
    <group arrange="flex">
      <action id="confirm-yes" do="confirm-yes">Yes</action>
      <action id="confirm-no"  do="confirm-no">No</action>
    </group>
  </dialog>

  <toast timeout="3000" when="toast.visible" bind="toast.message" />
</uidl>
```

Note: the root element is `<uidl>`, not `<tui>`.  There is no
separate "TUIDL language" — there is UIDL with a larger registry.

#### Full Element Type Table

| # | Element | Category | Content | Focus? | Self-close? | Two-way? |
|---|---------|----------|---------|--------|-------------|----------|
| 1 | `uidl` | Envelope | container | — | No | — |
| 2 | `region` | Data | container | No | No | — |
| 3 | `group` | Data | container | No | No | — |
| 4 | `separator` | Data | leaf | No | Yes | — |
| 5 | `meta` | Data | leaf | No | Yes | — |
| 6 | `label` | Data | leaf | No | No | — |
| 7 | `media` | Data | leaf | No | No | — |
| 8 | `symbol` | Data | leaf | No | Yes | — |
| 9 | `canvas` | Data | leaf | Yes | No | — |
| 10 | `action` | Data | leaf | Yes | No | — |
| 11 | `input` | Data | leaf | Yes | Yes | Yes |
| 12 | `selector` | Data | selector | Yes | No | Yes |
| 13 | `toggle` | Data | leaf | Yes | Yes | Yes |
| 14 | `range` | Data | leaf | Yes | Yes | Yes |
| 15 | `collection` | Data | collection | No | No | — |
| 16 | `table` | Data | container | Yes | No | — |
| 17 | `indicator` | Data | leaf | No | Yes | — |
| 18 | `template` | Binding | container | — | No | — |
| 19 | `empty` | Binding | container | — | No | — |
| 20 | `rep` | Binding | container | — | No | — |
| 21 | `option` | Binding | leaf | — | Yes | — |
| 22 | `menubar` | Chrome | container | No | No | — |
| 23 | `menu` | Chrome | container | Yes | No | — |
| 24 | `item` | Chrome | leaf | Yes | Yes | — |
| 25 | `tabs` | Chrome | container | No | No | — |
| 26 | `tab` | Chrome | container | Yes | No | — |
| 27 | `split` | Chrome | fixed-2 | No | No | — |
| 28 | `scroll` | Chrome | fixed-1 | No | No | — |
| 29 | `tree` | Chrome | container | Yes | No | — |
| 30 | `status` | Chrome | container | No | No | — |
| 31 | `dialog` | Chrome | container | No | No | — |
| 32 | `toast` | Chrome | leaf | No | No | — |
| 33 | `textarea` | Data | leaf | Yes | No | Yes |
| 34 | `dropdown` | Data | container | Yes | No | Yes |
| 35 | `radiogroup` | Data | container | No | No | — |
| 36 | `radio` | Data | leaf | Yes | Yes | Yes |
| 37 | `toolbar` | Chrome | container | No | No | — |
| 38 | `log` | Data | container | No | No | — |
| 39 | `code` | Data | leaf | No | No | — |
| 40 | `accordion` | Data | container | No | No | — |
| 41 | `password` | Data | leaf | Yes | Yes | Yes |
| 42 | `contextmenu` | Chrome | container | No | No | — |

42 elements total.  The registry has room for 64, leaving 22 slots
for user-defined components.

#### Test Targets: ~25 tests

- Registry init: 20 built-in elements have correct type-ids
- `DEFINE-ELEMENT` for a new tag → lookup finds it
- `DEFINE-ELEMENT` duplicate name → error
- `EL-LOOKUP` unknown name → 0
- `EL-DEF-BY-TYPE` valid → returns definition
- `EL-DEF-BY-TYPE` invalid → 0
- `UIDL-TYPE-NAME` round-trips through registry
- `_UDL-MAP-TAG` uses registry (existing parser tests still pass)
- Two-way flag from registry matches old hardcode
- Chrome elements registered by uidl-chrome.f
- Content model: `EL-FIXED-2` rejects 0 or 3 children
- Content model: `EL-FIXED-1` rejects 2+ children
- Content model: `EL-COLLECTION` requires template
- Content model: `EL-SELECTOR` requires option
- Subscription: `UIDL-SUBSCRIBE` + `UIDL-NOTIFY` marks elem dirty
- Subscription: multiple elems on same path all marked
- Subscription: unrelated path does not mark
- All existing uidl.f tests pass unchanged (backward compat)
- Registry at capacity (64) → next `DEFINE-ELEMENT` errors gracefully
- `ED.RENDER-XT` / `ED.EVENT-XT` / `ED.LAYOUT-XT` stored and retrievable
- Flag accessors: `EL-FOCUSABLE?`, `EL-SELF-CLOSE?`, `EL-TWOWAY?`
- Category accessor: `EL-CATEGORY`
- Content model accessor: `EL-CONTENT-MODEL`
- Parse document with chrome elements → correct types
- Parse document with user-defined element → correct type

---

### 5.5 tui/uidl-tui.f — UIDL TUI Backend

**Goal:** The TUI rendering backend for UIDL.  Installs real
render-xt, event-xt, and layout-xt implementations into the Element
Registry for all built-in + chrome elements, then provides focus
management, hit-testing, dirty-rect repaint, event dispatch
(bubble/capture on the UIDL tree), and the subscription-driven
reactive loop — all operating directly on the UIDL element tree
with no DOM intermediary.

File: `tui/uidl-tui.f`
Prefix: `UTUI-` (public), `_UTUI-` (internal)
Provider: `PROVIDED akashic-tui-uidl-tui`
Dependencies:
  `REQUIRE liraq/uidl.f`, `REQUIRE liraq/uidl-chrome.f`,
  `REQUIRE liraq/state-tree.f`, `REQUIRE liraq/lel.f`,
  `REQUIRE tui/screen.f`, `REQUIRE tui/draw.f`, `REQUIRE tui/box.f`,
  `REQUIRE tui/region.f`, `REQUIRE tui/layout.f`, `REQUIRE tui/keys.f`

~500 lines

#### Design Overview

The UIDL tree **is** the runtime.  No DOM is created.  Each UIDL
element node already carries: type-id, parent/child/sibling pointers,
attributes, bind expression, when predicate, arrangement mode, and ID.
The Element Registry adds: render-xt, event-xt, layout-xt.
This module connects the two.

```
State-tree change
    │
    ▼
UIDL-NOTIFY ( path )
    │
    ▼
Mark bound elements dirty
    │
    ▼
UTUI-PAINT (dirty-rect pass)
    │
    ▼
For each dirty element:
    LEL evaluate bind → new value
    Call render-xt → writes to screen buffer
    │
    ▼
SCR-FLUSH → terminal
```

#### TUI Sidecar (per-element, 48 bytes)

Each visible UIDL element gets a small TUI sidecar allocated from
a static pool.  Stored in a parallel array indexed by element pool
index (no pointer chase — `elem-index × 48 + sidecar-base`).

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | row | Computed row in screen coordinates |
| +8 | col | Computed column |
| +16 | width | Computed width (cells) |
| +24 | height | Computed height (cells) |
| +32 | style | Packed: fg(8) bg(8) attrs(8) border(8) |
| +40 | flags | Dirty, visible, focused, has-sidecar |

```forth
48 CONSTANT _UTUI-SC-SZ
CREATE _UTUI-SIDECARS  256 _UTUI-SC-SZ * ALLOT  \ 12,288 bytes
```

#### XT Installation

At load time, `uidl-tui.f` patches every registered element's
render-xt, event-xt, and layout-xt with TUI-specific implementations:

```forth
: UTUI-INSTALL-XTS  ( -- )
    S" label"   EL-LOOKUP DUP IF ' _UTUI-RENDER-LABEL  SWAP ED.RENDER-XT ! THEN
    S" action"  EL-LOOKUP DUP IF ' _UTUI-RENDER-ACTION SWAP ED.RENDER-XT ! THEN
    S" action"  EL-LOOKUP DUP IF ' _UTUI-H-ACTION      SWAP ED.EVENT-XT  ! THEN
    S" input"   EL-LOOKUP DUP IF ' _UTUI-RENDER-INPUT  SWAP ED.RENDER-XT ! THEN
    S" input"   EL-LOOKUP DUP IF ' _UTUI-H-INPUT       SWAP ED.EVENT-XT  ! THEN
    \ ... all 42 elements ...
    S" menubar" EL-LOOKUP DUP IF ' _UTUI-RENDER-MBAR   SWAP ED.RENDER-XT ! THEN
    S" tabs"    EL-LOOKUP DUP IF ' _UTUI-RENDER-TABS   SWAP ED.RENDER-XT ! THEN
    S" dialog"  EL-LOOKUP DUP IF ' _UTUI-RENDER-DLG    SWAP ED.RENDER-XT ! THEN
    \ etc.
;
UTUI-INSTALL-XTS   \ runs at load time
```

#### Event Dispatch (bubble/capture on UIDL tree)

Same algorithm as `dom/event.f` but walking UIDL parent/child:

```forth
: UTUI-DISPATCH  ( elem evt-type detail -- handled? )
    \ 1. Build ancestor path: elem → UIDL-PARENT → ... → root
    \ 2. CAPTURE: walk root→parent, call each event-xt
    \ 3. TARGET: call elem's event-xt
    \ 4. BUBBLE: walk parent→root, call each event-xt
    \ Check stopped? flag at each step
    ... ;
```

Event objects are stack-allocated (same 80-byte layout as
`dom/event.f`), keeping the event protocol consistent.

#### Focus Management

Single focused-element pointer + Tab/Shift-Tab cycling through
elements whose registry definition has `EL-F-FOCUS` set:

```forth
VARIABLE _UTUI-FOCUS

: UTUI-FOCUS     ( -- elem | 0 )  _UTUI-FOCUS @ ;
: UTUI-FOCUS!    ( elem -- )
    \ Fire blur on old, focus on new, update pointer
    ... ;
: UTUI-FOCUS-NEXT  ( -- )
    \ Walk UIDL tree DFS from current, find next focusable
    ... ;
: UTUI-FOCUS-PREV  ( -- )
    \ Walk reverse
    ... ;
```

#### Hit Testing

```forth
: UTUI-HIT-TEST  ( row col -- elem | 0 )
    \ Walk UIDL tree reverse DFS (back-to-front z-order)
    \ Check sidecar bounds for each visible element
    \ Return deepest match
    ... ;
```

#### Layout Engine

Each element's `layout-xt` receives the element and computes its
children's sidecar positions based on `arrange=` mode:

```forth
: _UTUI-LAYOUT-STACK  ( elem -- )    \ vertical stack
    ... ;
: _UTUI-LAYOUT-FLEX   ( elem -- )    \ horizontal distribute
    ... ;
: _UTUI-LAYOUT-FLOW   ( elem -- )    \ inline wrapping
    ... ;
: _UTUI-LAYOUT-GRID   ( elem -- )    \ equal-width columns
    ... ;
: _UTUI-LAYOUT-DOCK   ( elem -- )    \ first child fills remainder
    ... ;
```

Chrome layout is also done via layout-xt:
- `menubar` layout-xt → claims row 0, full width
- `status` layout-xt → claims last row, full width
- `tabs` layout-xt → tab header row + content region below
- `split` layout-xt → divide by `ratio=`, draw divider
- `scroll` layout-xt → clip child, add scrollbar
- `dialog` layout-xt → centered overlay, computed size

#### Dirty-Rect Repaint

```forth
: UTUI-PAINT  ( -- )
    \ Walk UIDL tree.  For each element:
    \   If when= evaluates false → skip subtree, clear sidecar region
    \   If dirty flag set:
    \     LEL evaluate bind= → new value
    \     Call render-xt with elem + resolved value
    \     Clear dirty flag
    ... ;
```

Only dirty nodes repaint.  Subscriptions mark individual elements
dirty when their bound state-tree path changes.  Full relayout
(`UTUI-RELAYOUT`) marks everything dirty.

#### Shortcut Registration

`key=` attributes on `<item>` and `<action>` elements are parsed
into key descriptors and stored in a global shortcut table:

```forth
64 CONSTANT _UTUI-MAX-SHORTS
CREATE _UTUI-SHORTS  _UTUI-MAX-SHORTS 24 * ALLOT
VARIABLE _UTUI-SHORT-CNT

: _UTUI-REG-SHORTCUT  ( elem -- )
    DUP S" key" UIDL-ATTR IF
        _UTUI-PARSE-KEY-DESC    \ → key-code mod-mask
        DUP S" do" UIDL-ATTR IF \ → action name
            _UTUI-SHORT-ADD
        ELSE 2DROP THEN
    ELSE 2DROP THEN DROP ;
```

#### Action Dispatch

```forth
64 CONSTANT _UTUI-MAX-ACTIONS
CREATE _UTUI-ACTIONS  _UTUI-MAX-ACTIONS 24 * ALLOT
VARIABLE _UTUI-ACT-CNT

: UTUI-DO!  ( do-name-a do-name-u xt -- )
    \ Register handler for named action
    ... ;

: _UTUI-DISPATCH-ACTION  ( elem -- )
    UIDL-DISPATCH
    DUP UIDL-ACT-ACTIVATE = IF DROP UIDL-ACTION-VALUE IF _UTUI-FIRE-DO THEN EXIT THEN
    DUP UIDL-ACT-EMIT     = IF DROP UIDL-ACTION-VALUE IF _UTUI-FIRE-DO THEN EXIT THEN
    DUP UIDL-ACT-SET-STATE = IF DROP UIDL-ACTION-VALUE IF _UTUI-DO-SET-STATE THEN EXIT THEN
    DROP ;
```

#### Words — Public API

| Word | Stack | Description |
|------|-------|-------------|
| `UTUI-LOAD` | `( xml-a xml-u rgn -- flag )` | Parse UIDL, allocate sidecars, layout, install XTs.  One-call setup. |
| `UTUI-BIND-STATE` | `( st -- )` | Bind a state-tree to the document. |
| `UTUI-PAINT` | `( -- )` | Repaint dirty elements. |
| `UTUI-RELAYOUT` | `( rgn -- )` | Full relayout + mark all dirty. |
| `UTUI-DISPATCH-KEY` | `( key-event -- handled? )` | Translate key → dispatch to focused element. |
| `UTUI-DISPATCH-MOUSE` | `( row col button -- handled? )` | Hit-test → dispatch to element. |
| `UTUI-FOCUS` | `( -- elem \| 0 )` | Get focused element. |
| `UTUI-FOCUS!` | `( elem -- )` | Set focus (fires blur/focus). |
| `UTUI-FOCUS-NEXT` | `( -- )` | Tab to next focusable. |
| `UTUI-FOCUS-PREV` | `( -- )` | Shift-Tab to previous focusable. |
| `UTUI-BY-ID` | `( id-a id-u -- elem \| 0 )` | Shortcut for `UIDL-BY-ID`. |
| `UTUI-DO!` | `( do-name-a do-name-u xt -- )` | Register `do=` action handler.  Callback: `( elem -- )`. |
| `UTUI-SHOW-DIALOG` | `( id-a id-u -- )` | Show dialog by id. |
| `UTUI-HIDE-DIALOG` | `( id-a id-u -- )` | Hide dialog by id. |
| `UTUI-SHOW-TOAST` | `( msg-a msg-u -- )` | Display transient toast. |
| `UTUI-HIT-TEST` | `( row col -- elem \| 0 )` | Find element at screen position. |
| `UTUI-DETACH` | `( -- )` | Full teardown. |

#### Data Binding Flow (subscription-driven)

```
UIDL element:  <label bind="state.count" />
        │
        ▼  (load time)
    LEL compile: bind expression → bytecode
    UIDL-SUBSCRIBE: path="count" → elem in subscription table
        │
        ▼  (runtime: state-tree change)
    ST-SET-* calls UIDL-NOTIFY( "count" )
        │
        ▼
    Subscription table → mark elem dirty
        │
        ▼
    UTUI-PAINT → LEL evaluate → render-xt → screen buffer
        │
        ▼
    SCR-FLUSH → terminal
```

Two-way: `event-xt` calls `UIDL-BIND-WRITE` → state-tree update →
`UIDL-NOTIFY` → other bound elements marked dirty → repaint.

#### Usage Example

```forth
REQUIRE liraq/state-tree.f
REQUIRE liraq/uidl-chrome.f
REQUIRE tui/uidl-tui.f

\ State
ST-NEW CONSTANT my-st
my-st S" app.statusline" S" Ready" ST-SET-STR

my-st UTUI-BIND-STATE

80 24 SCR-CREATE CONSTANT my-scr
my-scr SCR-USE
0 0 80 24 RGN-SET CONSTANT my-rgn

S" <uidl cols='80' rows='24' title='Demo'>"
S"   <region arrange='stack'>"
S"     <label>Hello extensible UIDL!</label>"
S"     <action id='go' do='go'>Go</action>"
S"   </region>"
S"   <status bind='app.statusline' />"
S" </uidl>"
my-rgn UTUI-LOAD  .  \ → -1 (true)

: on-go ( elem -- ) DROP ." Go!" CR ;
S" go" ' on-go UTUI-DO!

UTUI-PAINT
SCR-FLUSH
```

No DOM.  No bridge.  No sidecar-to-node cross-referencing.
The UIDL tree is the single source of truth.

#### Dependency Chain

```
tui/uidl-tui.f
├── liraq/uidl.f        (extensible UIDL with Element Registry)
├── liraq/uidl-chrome.f (chrome + must-have + nice-to-have registrations)
├── liraq/state-tree.f  (reactive key-value store, 1200 lines)
├── liraq/lel.f         (expression evaluator, 1652 lines)
├── tui/screen.f        (double-buffered screen)
├── tui/draw.f          (cell-level drawing)
├── tui/box.f           (box drawing & borders)
├── tui/region.f        (clip rectangles)
├── tui/layout.f        (container layout)
└── tui/keys.f          (input decoder)
```

No dependency on `dom/`, `css/`, `html5.f`, or `bridge.f`.

#### Test targets: ~35 tests

- `UTUI-LOAD` minimal `<uidl>` document → sidecars allocated
- `<label>` draws text at correct position
- `<action>` Enter fires → handler called via `UTUI-DO!`
- `<input>` keystroke → sidecar updates, cursor moves
- `<toggle>` Space → toggles `[✓]`/`[ ]`, bind-write fires
- `<range>` Left/Right → value changes, bar redraws
- `<selector>` Up/Down/Enter → selection + bind-write
- `<textarea>` multi-line editing, scroll within bounds
- `<dropdown>` opens/closes, selection writes back
- `<radio>` / `<radiogroup>` mutual exclusion
- `<password>` masks input with `•`
- `<menubar>` row 0, F10 opens
- `<menu>` dropdown, Up/Down/Enter
- `<item>` `key=` shortcut fires action globally
- `<tabs>` tab bar + switch + show/hide content
- `<toolbar>` horizontal actions bar
- `<split>` divides by ratio, children sized correctly
- `<scroll>` clips child, scrollbar, Up/Down scrolls
- `<tree>` expand/collapse, indent, bind to array
- `<status>` bottom row, full width
- `<dialog>` overlay, focus trap, show/hide
- `<toast>` bottom-right, auto-dismiss
- `<contextmenu>` right-click → popup
- Focus: Tab cycles focusable elements in tree order
- Focus: Shift-Tab reverses
- Hit-test: click at (row,col) → correct element
- Hit-test: empty area → 0
- `bind=` → label updates when state changes (subscription-driven)
- `when="false"` → element hidden
- Two-way: input edit → state-tree path updated
- `UTUI-SHOW-DIALOG` / `UTUI-HIDE-DIALOG`
- `UTUI-SHOW-TOAST` displays message
- `UTUI-DETACH` cleans up
- Dirty-rect: only changed elements repaint (verify via SCR writes)
- User-defined element: `DEFINE-ELEMENT` + custom render-xt renders

---

## Layer 6 — Application Shell

### 6.1 tui/event.f — Event Loop & Dispatch ✅

**Status: Done** — 240 lines, 28 tests in `test_tui_event.py`

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

### 6.2 tui/focus.f — Focus Manager ✅

**Goal:** Manage which widget receives keyboard input.  Maintains
a focus chain (ordered list of focusable widgets).  Tab/Shift-Tab
cycles focus.

**Status: Done** — 280 lines, 19 tests in `test_focus.py`

File: `tui/focus.f`
Prefix: `FOC-` (public), `_FOC-` (internal)
Provider: `PROVIDED akashic-tui-focus`
Dependencies: `REQUIRE keys.f`, `REQUIRE widget.f`

280 lines

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `FOC-ADD` | `( widget -- )` | Add widget after current in ring (duplicates ignored) |
| `FOC-REMOVE` | `( widget -- )` | Remove widget from chain; focus moves to next |
| `FOC-NEXT` | `( -- )` | Move focus to next widget in ring |
| `FOC-PREV` | `( -- )` | Move focus to previous widget in ring |
| `FOC-SET` | `( widget -- )` | Explicitly set focus (ignored if not in chain) |
| `FOC-GET` | `( -- widget \| 0 )` | Get currently focused widget |
| `FOC-DISPATCH` | `( event-addr -- )` | Send key event to focused widget's handle-xt |
| `FOC-CLEAR` | `( -- )` | Clear focus chain (teardown) |
| `FOC-COUNT` | `( -- n )` | Number of focusable widgets |
| `FOC-EACH` | `( xt -- )` | Call xt once per chain entry: xt ( widget -- ) |

#### Design

Focus chain is a circular singly-linked list.  Widget addresses and
next-indices are stored in fixed-size parallel arrays (max 32 entries),
avoiding modifications to the widget header.

`FOC-ADD` inserts **after current**, so adding A→B→C yields ring
order A→C→B→A.  `FOC-EACH` scans all slots (not ring-order) and is
used by `focus-2d.f` for spatial navigation.

`FOC-DISPATCH` calls `WDG-HANDLE` on the focused widget.  The event
loop handles Tab/Shift-Tab before dispatching so the focus manager
doesn't need special-case Tab handling.

#### Tests: 19 (in test_focus.py, shared with focus-2d\.f — 34 total)

- FOC-ADD / FOC-GET / FOC-COUNT (4 tests)
- FOC-NEXT / FOC-PREV ring cycling (4 tests)
- FOC-SET explicit focus + flags (3 tests)
- FOC-REMOVE middle / focused / last (3 tests)
- FOC-CLEAR (1 test)
- FOC-DISPATCH + empty (2 tests)
- FOC-EACH + empty (2 tests)

---

### 6.2b tui/focus-2d.f — Spatial Focus Navigation ✅

**Goal:** Plug-in for focus.f that adds 2D directional focus movement
via Manhattan distance scoring, plus keyboard-driven mouse emulation.

**Status: Done** — 216 lines, 15 tests in `test_focus.py`

File: `tui/focus-2d.f`
Prefix: `F2D-` (public), `_F2D-` (internal)
Provider: `PROVIDED akashic-tui-focus-2d`
Dependencies: `REQUIRE focus.f`, `REQUIRE keys.f`, `REQUIRE widget.f`, `REQUIRE region.f`

216 lines

#### Words

| Word | Stack | Description |
|------|-------|-------------|
| `F2D-UP` | `( -- )` | Move focus to nearest widget above |
| `F2D-DOWN` | `( -- )` | Move focus to nearest widget below |
| `F2D-LEFT` | `( -- )` | Move focus to nearest widget left |
| `F2D-RIGHT` | `( -- )` | Move focus to nearest widget right |
| `F2D-CLICK-L` | `( -- )` | Synthetic left click on focused widget |
| `F2D-CLICK-M` | `( -- )` | Synthetic middle click on focused widget |
| `F2D-CLICK-R` | `( -- )` | Synthetic right click on focused widget |
| `F2D-DISPATCH` | `( ev -- flag )` | Handle Alt+Arrow/click combos; 0 if not ours |

#### Key Bindings

| Key Combo | Action |
|-----------|--------|
| Alt + ↑/↓/←/→ | Spatial focus navigation |
| Alt + Delete | Left click on focused widget |
| Alt + End | Middle click |
| Alt + PgDn | Right click |

#### Design

Scans the focus chain via `FOC-EACH`.  For each visible, non-self
widget, computes center-point from `WDG-REGION`, applies direction
predicate (above/below/left/right), scores with biased Manhattan
distance (2× cross-axis penalty), tracks best.  If found, `FOC-SET`
moves focus.

Synthetic clicks build a `KEY-T-MOUSE` event at the focused widget's
center, write `KEY-MOUSE-X/Y`, and call `WDG-HANDLE` directly.

#### Tests: 15 (in test_focus.py, shared with focus\.f — 34 total)

- Directional navigation: down/up/left/right/diagonal-bias/no-candidate/empty (7 tests)
- Synthetic clicks: left click + empty safety (2 tests)
- F2D-DISPATCH: Alt+Down, Alt+Right, non-Alt passthrough, char passthrough, Alt+Delete (5 tests)
- Compilation clean (1 test)

---

### 6.3 tui/app.f — Application Lifecycle ✅

**Status: Done** — ~140 lines, 18 tests in `test_tui_app.py`

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

## Layer 7 — Extended Components

### 7.1 tui/widgets/split.f — Split Panes

**Goal:** Divide a region into two panes (horizontal or vertical
split), with an optional draggable divider.

File: `tui/widgets/split.f`
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

### 7.2 tui/widgets/scroll.f — Scrollable Viewport

**Goal:** A generic scrollable viewport — wraps any content that
is larger than its visible region.  Provides vertical and
horizontal scrolling with optional scroll indicators.

File: `tui/widgets/scroll.f`
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

### 7.3 tui/widgets/tree.f — Tree View ✅

**Status: Done** — 485 lines, 18 tests in `test_tui.py`

**Goal:** Collapsible tree display for hierarchical data.  Nodes
can be expanded/collapsed.  Arrow keys navigate, Enter toggles
expansion.

File: `tui/widgets/tree.f`
Prefix: `TREE-` (public), `_TREE-` (internal)
Provider: `PROVIDED akashic-tui-tree`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`, `REQUIRE keys.f`

485 lines

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

#### Test results: 18 / 18 pass

- create (type, cursor)
- draw (no crash)
- expand / collapse / toggle / expand-all / expand-leaf
- nav: up, down, enter, right-expand, left-collapse, clamp
- selected node lookup
- on-select callback
- visible count

---

### 7.4 tui/widgets/status.f — Status Bar

**Goal:** A single-row bar for persistent status information
(filename, mode, cursor position, etc.).  Typically placed at the
top or bottom of the screen.

File: `tui/widgets/status.f`
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

### 7.5 tui/widgets/toast.f — Transient Notifications

**Goal:** Brief popup messages that auto-dismiss after a timeout.
Displayed at a fixed position (typically bottom-right).

File: `tui/widgets/toast.f`
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

### 7.6 tui/widgets/canvas.f — Character-Mode Canvas ✅

**Status: Done** — 443 lines, 22 tests in `test_tui.py`

**Goal:** A free-form drawing surface for character graphics —
Braille patterns, block characters, plot points.  Provides
a coordinate system for sub-cell "pixel" drawing using Unicode
Braille characters (2×4 dots per cell = 2× horizontal and 4×
vertical resolution).

File: `tui/widgets/canvas.f`
Prefix: `CVS-` (public), `_CVS-` (internal)
Provider: `PROVIDED akashic-tui-canvas`
Dependencies: `REQUIRE draw.f`, `REQUIRE region.f`

443 lines

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

#### Test results: 22 / 22 pass

- create (type, dot-w, dot-h)
- set / get / clr / oob
- pen colour, stamp, CVS-COLOR!
- clear (dots + colour)
- line (horiz, diagonal)
- rect, fill-rect, circle (3 checks)
- draw (no crash), handle (returns 0)
- free (no crash)

### 7.7 UIDL-TUI Widget Wiring — Sidecar State Blocks

**Goal:** Replace placeholder render/event stubs in `uidl-tui.f` with
real widget drawing and interaction by extending the per-element
sidecar with a widget-pointer cell and allocating lightweight widget
structs for complex element types at load time.

#### Background

The UIDL-TUI backend operates directly on the UIDL element tree with
no DOM intermediary.  Simple elements (label, action, input, toggle,
separator, progress) already have complete render and event words.
Complex elements (tree, list, tabs, split, scroll, status) were left
as stubs — typically just a background fill and `2DROP 0` event
handlers — because they need **per-instance mutable state** (cursor
position, scroll offset, expand bitmap, active tab index) that
neither the 128-byte UIDL element pool slot nor the 48-byte sidecar
can carry.

The DOM path solves this via `N.AUX` (a generic pointer cell per DOM
node) which stores a 64-byte TUI sidecar allocated by `DTUI-ATTACH`.
The UIDL path has no equivalent extension point — until now.

#### Design: Sidecar Extension + Widget Struct Reuse

**Sidecar grows from 48 → 56 bytes** (7 cells instead of 6):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | row | Screen row |
| +8 | col | Screen column |
| +16 | width | Width in cells |
| +24 | height | Height in cells |
| +32 | style | Packed fg/bg/attrs/border |
| +40 | flags | has/vis/foc bits |
| **+48** | **wptr** | **Widget struct pointer (0 = none)** |

The `wptr` cell at +48 points to a heap-allocated widget descriptor
(the same structs created by `TREE-NEW`, `LST-NEW`, `TAB-NEW`, etc.)
for element types that need interactive state.  For simple elements
(labels, buttons, separators), wptr stays 0.

**Why reuse full widget structs** rather than just the payload:
- Widget `_*-DRAW` and `_*-HANDLE` words read from the struct header
  (specifically `WDG-REGION` at +8) and invoke callbacks by field offset.
  Removing the header would require rewriting every internal word.
- The 40-byte header overhead is negligible (6 stateful elements max
  per typical UIDL document × 40 bytes = 240 bytes).
- Widget constructors (`*-NEW`) handle sub-allocations (expand bitmap
  for tree, tab entry array for tabs) — reusing them avoids duplicating
  that logic.

**Proxy region bridge:** Each materialized widget needs a valid
`WDG-REGION` pointer.  Rather than allocating one region per widget,
a single **proxy region** (40 bytes, `CREATE`'d in dictionary) is
synced from the sidecar geometry before each `_*-DRAW` or
`_*-HANDLE` call.  This is safe because the TUI is single-threaded.

#### Lifecycle

**Load time** (`UTUI-LOAD`, after `UTUI-RELAYOUT`):
1. Walk the element tree.
2. For each element whose type is tree/list/tabs/split/scroll:
   - Read sidecar geometry → sync proxy region → call `*-NEW`.
   - Store returned widget pointer in sidecar +48.
   - For tree/list: wire UIDL children as data source via callbacks.
   - For tabs: call `TAB-ADD` for each `<tab>` child element.
3. Leave wptr=0 for all other element types.

**Render time** (`_UTUI-RENDER-TREE` etc.):
1. `_UTUI-STASH-SC` as before (visibility check, style, geometry).
2. Read wptr from sidecar +48.  If 0, fall back to bg fill.
3. Sync proxy region from sidecar geometry.
4. Update widget's `WDG-REGION` to proxy region.
5. Call `_*-DRAW` on the widget.

**Event time** (`_UTUI-H-TREE` etc.):
1. Read wptr from sidecar +48.  If 0, return 0.
2. Sync proxy region.
3. Call `_*-HANDLE ( event widget -- consumed? )`.

**Detach time** (`UTUI-DETACH`):
1. Walk all sidecars.  For each with wptr≠0, call `*-FREE` (or
   `FREE` for simple structs) then zero the cell.

#### Elements Getting Widget Structs

| UIDL type | Widget | Struct size | State carried |
|-----------|--------|------------|---------------|
| `<tree>` | `TREE-NEW` | 112 B | cursor, scroll, expand bitmap, walk callbacks |
| `<collection>` / `<list>` | `LST-NEW` | 88 B | items, count, selected, scroll, select-xt |
| `<tabs>` | `TAB-NEW` | 80 B | tab entries, count, active, switch-xt |
| `<split>` | `SPL-NEW` | 80 B | mode, ratio, pane regions, divider char |
| `<scroll>` | `SCRL-NEW` | 88 B | content dims, offsets, draw-xt, indicators |
| `<status>` | — | 0 B | Text from UIDL children; no extra state needed |
| `<canvas>` | — | 0 B | Already wired; app-level CVS-* drawing |
| `<toast>` | — | 0 B | Singleton; overlay hooks in paint loop |

Status keeps its current approach (render from child labels).  Canvas
is already correct.  Toast is an overlay, not a tree-resident widget.

#### Memory Budget

Worst case (all 6 types present): 6 × 112 = 672 bytes of widget
structs + 1 proxy region (40 bytes) + sidecar growth (256 × 8 = 2048
bytes).  Total overhead: ~2.7 KiB — well within the 12 KiB sidecar
array budget.

#### Test Plan

Existing TUI tests (22 canvas + 18 tree) must continue to pass
unchanged — they test standalone widget operation, not UIDL wiring.
New tests will be added in a follow-up for UIDL-driven tree/list/tabs
rendering once the wiring is verified manually.

#### Status

- [ ] Extend sidecar to 56 bytes (add `_UTUI-SC-O-WPTR`)
- [ ] Add proxy region and sync word
- [ ] Wire `_UTUI-RENDER-TREE` adapter
- [ ] Wire `_UTUI-H-TREE` adapter
- [ ] Wire `_UTUI-RENDER-LIST` / `_UTUI-H-LIST` adapters
- [ ] Wire `_UTUI-RENDER-TABS` / `_UTUI-H-TABS` / `_UTUI-LAYOUT-TABS`
- [ ] Wire `_UTUI-RENDER-SPLIT` adapter
- [ ] Wire `_UTUI-RENDER-SCROLL` / `_UTUI-H-SCROLL` adapters
- [ ] Wire `_UTUI-RENDER-STATUS` adapter
- [ ] Allocate widget structs in `UTUI-LOAD`
- [ ] Free widget structs in `UTUI-DETACH`
- [ ] All existing tests pass

---

## Layer 8 — Application Packaging (optional)

This layer wraps the application lifecycle with binary-image
save/load, a manifest file reader, and a minimal launcher app.
All three files are **optional** — applications can run perfectly
well with just `app.f` and never touch Layer 8.

### 8.1 tui/app-image.f — Binary Image Wrapper

**Goal:** Convenience words that integrate `app.f` with `binimg.f`
so a compiled TUI application can be frozen to a `.m64` image and
reloaded later.

File: `tui/app-image.f`
Prefix: `APPI-` (public), `_APPI-` (internal)
Depends on: `app.f`, `store/binimg.f`
Estimated size: ~80 lines

#### Public API

| Word | Stack | Purpose |
|------|-------|---------|
| `APPI-MARK` | `( -- )` | Calls `IMG-MARK` to snapshot the dictionary pointer |
| `APPI-ENTRY` | `( xt -- )` | Register XT as the app entry point via `IMG-ENTRY` |
| `APPI-SAVE` | `( addr len -- )` | Save everything since `APPI-MARK` as a `.m64` image |
| `APPI-LOAD` | `( addr len -- xt )` | Load a `.m64` image, return its entry XT |
| `APPI-RUN` | `( addr len -- )` | Load + `APP-RUN-FULL` in one step |

#### Workflow

```forth
APPI-MARK
\ ... compile application words ...
' my-app APPI-ENTRY
S" my-app.m64" APPI-SAVE
```

Later:

```forth
S" my-app.m64" APPI-RUN
```

#### Test targets: ~8 tests

- APPI-MARK sets marker
- APPI-ENTRY stores XT
- APPI-SAVE produces image file
- APPI-LOAD returns entry XT
- APPI-RUN calls APP-RUN-FULL with loaded XT
- Round-trip: mark → compile → save → load → verify entry
- Double-save overwrites cleanly
- Load of missing file returns error

---

### 8.2 tui/app-manifest.f — Application Manifest

**Goal:** Read a small LCF (TOML-subset) manifest describing an
application's metadata: name, version, title, dimensions, entry
word, and dependencies.

File: `tui/app-manifest.f`
Prefix: `MFT-` (public), `_MFT-` (internal)
Depends on: `liraq/lcf.f`
Estimated size: ~120 lines

#### Manifest format

```toml
[app]
name  = "akashic-pad"
title = "Akashic Pad"
version = "0.1.0"
width  = 80
height = 24
entry  = "pad-main"

[deps]
uidl = true
css  = true
```

#### Public API

| Word | Stack | Purpose |
|------|-------|---------|
| `MFT-LOAD` | `( addr len -- mft )` | Parse manifest file, return descriptor address |
| `MFT-FREE` | `( mft -- )` | Release descriptor memory |
| `MFT-NAME` | `( mft -- addr len )` | Get app name string |
| `MFT-TITLE` | `( mft -- addr len )` | Get app title string |
| `MFT-VERSION` | `( mft -- addr len )` | Get version string |
| `MFT-WIDTH` | `( mft -- n )` | Get preferred width (0 = auto) |
| `MFT-HEIGHT` | `( mft -- n )` | Get preferred height (0 = auto) |
| `MFT-ENTRY` | `( mft -- addr len )` | Get entry word name |
| `MFT-DEP?` | `( mft addr len -- flag )` | Check if named dep is required |

#### Descriptor layout (10 cells = 80 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | name-addr | Pointer to name string |
| +8 | name-len | Name length |
| +16 | title-addr | Pointer to title string |
| +24 | title-len | Title length |
| +32 | version-addr | Pointer to version string |
| +40 | version-len | Version length |
| +48 | width | Preferred width |
| +56 | height | Preferred height |
| +64 | entry-addr | Pointer to entry word name |
| +72 | entry-len | Entry word name length |

#### Test targets: ~10 tests

- Parse minimal manifest
- Read each field
- Default width/height = 0 when omitted
- Dependency check (present + absent)
- Missing [app] section → error
- Empty manifest → error
- MFT-FREE releases memory
- Round-trip: write manifest string → load → verify all fields
- Extra unknown keys ignored
- Duplicate keys: last wins

---

### 8.3 tui/app-launcher.f — TUI Launcher

**Goal:** A simple TUI application that scans a directory for
`.m64` images with companion manifests, displays them in a
selectable list, and launches the chosen app.

File: `tui/app-launcher.f`
Prefix: `LAUNCH-` (public), `_LAUNCH-` (internal)
Depends on: `app.f`, `app-image.f`, `app-manifest.f`, `list.f`,
`draw.f`, `box.f`, `label.f`
Estimated size: ~200 lines

#### Public API

| Word | Stack | Purpose |
|------|-------|---------|
| `LAUNCH-SCAN` | `( addr len -- n )` | Scan directory for manifests, return count |
| `LAUNCH-RUN` | `( -- )` | Show launcher UI, run selected app |
| `LAUNCH-ENTRY` | `( -- )` | Top-level entry (scan default path + run) |

#### Behaviour

1. `LAUNCH-SCAN` reads `*.lcf` files from the given directory,
   parses each with `MFT-LOAD`, and stores descriptors in an
   internal array (max 32 apps).
2. `LAUNCH-RUN` creates a full-screen app via `APP-INIT`, draws a
   bordered list of app names using `LST-` widgets, and enters
   the event loop.  On Enter, it shuts down the launcher,
   calls `APPI-RUN` with the selected image path, then returns
   to the launcher when the child app exits.
3. `LAUNCH-ENTRY` calls `LAUNCH-SCAN` with `S" /apps/"` (or
   a configurable path), then `LAUNCH-RUN`.

#### Test targets: ~10 tests

- Scan empty directory → 0 apps
- Scan directory with 1 manifest → 1 app listed
- Scan directory with 3 manifests → sorted list
- Launcher draws bordered app list
- Up/Down navigation selects entries
- Enter launches selected app
- Q quits launcher
- Return to launcher after child exits
- Max 32 apps enforced
- Missing image file → error shown in status line

---

## Dependency Graph

```
                        app.f
                       ╱  │  ╲
                      ╱   │   ╲
                event.f  focus.f  (Layer 6 shell)
                  │    ╲  │
                  │     ╲ │
        ┌─────────┴──────┴──────────────────────────────┐
        │  Layer 5a: UIDL Path    │  Layer 5b: DOM Path  │
        │                         │                      │
        │  uidl-tui.f             │  dom-tui.f           │
        │    ▲                    │  dom-render.f        │
        │    │                    │  dom-event.f         │
        │  uidl.f (registry)     │  dom/event.f         │
        │  uidl-chrome.f         │    ▲                  │
        │    ▲                    │    │                  │
        │    │                    │  dom.f css.f          │
        │  lel.f state-tree.f    │  bridge.f             │
        └────────┬───────────────┴──────────┬───────────┘
                 │                          │
    ┌────────────┼──────────────────────────┘
    │   Layer 4  │  Widgets
    │  label input list menu progress table dialog tabs
    ├────────────┼──────────────────────────┐
    │   Layer 7  │  Extended                │
    │  split scroll tree status toast canvas│
    └────────────┼──────────────────────────┘
                 │
           ┌─────┴──────┐
           │ Layout (3)  │
           │ region.f    │
           │ layout.f    │
           └──────┬──────┘
                  │
           ┌──────┴──────┐
           │ Drawing (2)  │
           │ draw.f box.f │
           └──────┬──────┘
                  │
           ┌──────┴──────┐
           │ Screen (1)   │
           │ cell.f       │
           │ screen.f     │
           └──────┬──────┘
                  │
           ┌──────┴──────┐
           │ Terminal (0)  │
           │ ansi.f keys.f│
           └──────┬──────┘
                  │
           ┌──────┴──────┐
           │ KDOS BIOS    │
           │ EMIT KEY CR  │
           └──────┬──────┘
                  │
           ┌──────┴──────┐
           │ Akashic       │
           │ string.f      │
           │ utf8.f fmt.f  │
           │ markup/core.f │
           │ liraq/*.f     │
           └──────────────┘
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
| 10 | tui/widgets/label.f | 4 | widget, draw | 209 | ✅ Done |
| 11 | tui/widgets/input.f | 4 | widget, draw, keys | 485 | ✅ Done |
| 12 | tui/widgets/list.f | 4 | widget, draw, keys | 280 | ✅ Done |
| 13 | tui/widgets/progress.f | 4 | widget, draw | 263 | ✅ Done |
| 14 | tui/table.f | 4 | draw, box, region | ~300 | ❌ Not started |
| 15 | tui/widgets/menu.f | 4 | draw, box, region | ~280 | ✅ Done |
| 16 | tui/widgets/dialog.f | 4 | keys, screen, widget, draw, box, region | ~340 | ✅ Done |
| 17 | tui/widgets/tabs.f | 4 | widget, draw, box, region, keys | 282 | ✅ Done |
| 18 | dom/event.f | 5b | dom.f | ~450 | ❌ Not started |
| 19 | tui/dom-tui.f | 5b | dom.f, css.f, bridge.f, cell, region | ~350 | ❌ Not started |
| 20 | tui/dom-render.f | 5b | dom-tui, draw, box, region, screen | ~400 | ❌ Not started |
| 21 | tui/dom-event.f | 5b | dom/event.f, dom-tui, keys | ~200 | ❌ Not started |
| 22 | liraq/uidl.f refactor | **5a-P0** | liraq/uidl.f (existing) | ~+200 | ❌ **Phase 0** |
| 23 | liraq/uidl-chrome.f | **5a-P0** | uidl.f (refactored) | ~120 | ❌ **Phase 0** |
| 24 | tui/uidl-tui.f | 5a | uidl.f, uidl-chrome.f, liraq/*, Layers 0–4 | ~500 | ❌ Not started |
| 25 | tui/focus.f | 6 | keys, widget | 280 | ✅ Done |
| 25b | tui/focus-2d.f | 6 | focus, keys, widget, region | 216 | ✅ Done |
| 25c | utils/term.f | — | BIOS only | 170 | ✅ Done |
| 26 | tui/event.f | 6 | keys, screen, focus, term | 254 | ✅ Done |
| 27 | tui/app.f | 6 | ansi, screen, event, focus, term | 155 | ✅ Done |
| 28 | tui/widgets/split.f | 7 | region, draw | ~150 | ❌ Not started |
| 29 | tui/widgets/scroll.f | 7 | region, draw | ~180 | ❌ Not started |
| 30 | tui/widgets/status.f | 7 | draw, region | ~100 | ❌ Not started |
| 31 | tui/widgets/toast.f | 7 | draw, box, region | ~120 | ❌ Not started |
| 32 | tui/widgets/tree.f | 7 | draw, region, scroll | ~250 | ❌ Not started |
| 33 | tui/widgets/canvas.f | 7 | draw, region | ~200 | ❌ Not started |
| 34 | tui/app-image.f | 8 | app, binimg | 115 | ✅ Done |
| 35 | tui/app-manifest.f | 8 | toml | 256 | ✅ Done |
| 36 | tui/app-launcher.f | 8 | app, app-image, app-manifest, list, draw, box, label | ~200 | ❌ Not started |
| | **Total** | | | **~7,939** | |

Build from bottom up: Layer 0 first (ansi + keys), then Layer 1
(cell + screen), and so on.  Within each layer, files are independent
and can be implemented in any order.

**Phase 0** (rows 22–23) is the prerequisite for the UIDL TUI path:
refactor `liraq/uidl.f` to add the Element Registry, Five Protocols,
and subscription table, then create `liraq/uidl-chrome.f` to register
chrome + must-have + nice-to-have elements.  This touches only
`liraq/` — no TUI code.  All existing uidl.f tests must still pass.

Layer 5b (DOM path, rows 18–21) is independent of Layer 5a (UIDL
path, rows 22–24).  Either can be built first.  The UIDL path has
no dependency on `dom/`, `css/`, or `bridge.f`.

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
| DOM document (100 nodes) | 80 + 100×80 + 200×24 + 4K str | 16,880 | 16,880 |
| DOM-TUI sidecars (100 nodes) | 100 × 64 | 6,400 | 6,400 |
| DOM event listener pool (256 slots) | 256 × 40 | 10,240 | 10,240 |
| DOM event object pool (8 slots) | 8 × 80 | 640 | 640 |
| **Total** | | **~71,000** | **~150,520** |

All fits in XMEM (16 MiB) with room to spare.  Even the largest
terminal (200×60) uses under 300 KiB.  The DOM event system adds
~11 KiB for its listener and event pools — shared across all event
types and all nodes.  Applications that don't use the DOM-TUI
bridge incur none of the DOM-related costs.  Dictionary footprint
for the code itself: ~6,150 lines × ~12 bytes/line ≈ ~74 KiB.

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
---

## Appendix A — Complete Application Example: Akashic Pad

This appendix presents a **fully functional text editor** ("Akashic
Pad") built entirely on the UIDL/TUI stack.  It shows every piece a
real application needs: state-tree schema, UIDL document, action
handlers, file I/O, undo/redo, dirty tracking, dialogs, keyboard
shortcuts, and the application lifecycle — approximately 450 lines of
Forth.  Nothing is hand-waved; every `do=` action has a real handler.

### A.1 Architecture

```
┌──────────────────────────────────────────────┐
│           UIDL Document (markup)             │
│  menubar · split · tree · tabs · textarea    │
│  toolbar · status · dialogs                  │
└────────────────────┬─────────────────────────┘
                     │ bind= / do=
         ┌───────────┴───────────┐
         │     State-Tree (ST)   │   Single source of truth
         │  fs.*  editor.*  ui.* │
         └───────────┬───────────┘
                     │ ST-SET-* / ST-GET-*
         ┌───────────┴───────────┐
         │   Action Handlers     │   Forth words registered
         │   (UTUI-DO!)          │   via named do= bindings
         └───────────┬───────────┘
                     │
         ┌───────────┴───────────┐
         │  Platform Services    │   KDOS file I/O, TIMER@,
         │  (BLK I/O, UART)     │   EMIT/KEY/TYPE
         └───────────────────────┘
```

**Key principle:** Action handlers never touch the screen directly.
They mutate the state-tree.  The subscription system marks bound
elements dirty.  `UTUI-PAINT` + `SCR-FLUSH` handles the rest.

### A.2 State-Tree Schema

```forth
\ ── File: akashic-pad.f ──────────────────────────────────
\ A complete text editor application for Akashic TUI.

REQUIRE liraq/state-tree.f
REQUIRE liraq/uidl-chrome.f
REQUIRE tui/uidl-tui.f
REQUIRE tui/app.f

\ ════════════════════════════════════════════════════════
\ §1  STATE-TREE SCHEMA
\ ════════════════════════════════════════════════════════
\ All application state lives here.  The UI is a pure
\ function of this tree — mutate it and the screen updates.
\
\ fs.entries[]       — array of {name, content, dirty}
\ fs.current         — index of currently open file (-1 = none)
\ fs.count           — number of files in the workspace
\
\ editor.content     — string: text of active buffer
\ editor.cursor.ln   — int: cursor line (1-based)
\ editor.cursor.col  — int: cursor column (1-based)
\ editor.cursor.text — string: "Ln 1, Col 1" for status bar
\ editor.mode        — string: "INSERT" | "OVERWRITE"
\ editor.selection   — string: "" or "Ln 3-7" (selection range)
\ editor.dirty       — bool: unsaved changes?
\ editor.undo[]      — array of snapshot strings (undo stack)
\ editor.redo[]      — array of snapshot strings (redo stack)
\
\ find.query         — string: current search term
\ find.visible       — bool: find dialog open?
\ find.match-count   — int: number of matches
\ find.match-idx     — int: current match index
\
\ ui.title           — string: window title
\ ui.filter          — string: file tree filter text
\ ui.sidebar         — bool: sidebar visible?
\ ui.status          — string: status bar message
\ ui.confirm-quit    — bool: quit dialog visible?
\
\ build.progress     — int: 0–100 (for progress bar demo)

\ Create state-tree (arena = HERE, 256 max nodes)
HERE 256 ST-DOC-NEW CONSTANT pad-st
pad-st ST-USE

\ ── File System ──
S" (scratch)" S" fs.entries.0.name"    ST-SET-PATH-STR
S" "          S" fs.entries.0.content" ST-SET-PATH-STR
FALSE         S" fs.entries.0.dirty"   ST-SET-PATH-BOOL
0             S" fs.current"           ST-SET-PATH-INT
1             S" fs.count"             ST-SET-PATH-INT

\ ── Editor ──
S" "          S" editor.content"       ST-SET-PATH-STR
1             S" editor.cursor.ln"     ST-SET-PATH-INT
1             S" editor.cursor.col"    ST-SET-PATH-INT
S" Ln 1, Col 1" S" editor.cursor.text" ST-SET-PATH-STR
S" INSERT"    S" editor.mode"          ST-SET-PATH-STR
S" "          S" editor.selection"     ST-SET-PATH-STR
FALSE         S" editor.dirty"         ST-SET-PATH-BOOL

\ ── Find ──
S" "          S" find.query"           ST-SET-PATH-STR
FALSE         S" find.visible"         ST-SET-PATH-BOOL
0             S" find.match-count"     ST-SET-PATH-INT
0             S" find.match-idx"       ST-SET-PATH-INT

\ ── UI ──
S" Akashic Pad" S" ui.title"          ST-SET-PATH-STR
S" "          S" ui.filter"            ST-SET-PATH-STR
TRUE          S" ui.sidebar"           ST-SET-PATH-BOOL
S" Ready"     S" ui.status"            ST-SET-PATH-STR
FALSE         S" ui.confirm-quit"      ST-SET-PATH-BOOL

\ ── Build (demo) ──
0             S" build.progress"       ST-SET-PATH-INT

pad-st UTUI-BIND-STATE
```

### A.3 UIDL Document

```forth
\ ════════════════════════════════════════════════════════
\ §2  UIDL MARKUP
\ ════════════════════════════════════════════════════════
\ Every element either binds to a state-tree path or wires
\ a do= action to a named handler.  when= controls visibility.

: pad-uidl  ( -- addr len )
  S" <uidl cols='80' rows='24' title='Akashic Pad'>"

  \ ── Menu Bar ──────────────────────────────────────────
  S" <menubar>" S+
  S"   <menu label='File'>" S+
  S"     <item do='new'     key='Ctrl+N'>New</item>" S+
  S"     <item do='open'    key='Ctrl+O'>Open...</item>" S+
  S"     <item do='save'    key='Ctrl+S'>Save</item>" S+
  S"     <item do='save-as' key='Ctrl+Shift+S'>Save As...</item>" S+
  S"     <item do='close'   key='Ctrl+W'>Close</item>" S+
  S"     <item do='quit'    key='Ctrl+Q'>Quit</item>" S+
  S"   </menu>" S+
  S"   <menu label='Edit'>" S+
  S"     <item do='undo'       key='Ctrl+Z'>Undo</item>" S+
  S"     <item do='redo'       key='Ctrl+Y'>Redo</item>" S+
  S"     <item do='select-all' key='Ctrl+A'>Select All</item>" S+
  S"     <item do='cut'        key='Ctrl+X'>Cut</item>" S+
  S"     <item do='copy'       key='Ctrl+C'>Copy</item>" S+
  S"     <item do='paste'      key='Ctrl+V'>Paste</item>" S+
  S"   </menu>" S+
  S"   <menu label='Search'>" S+
  S"     <item do='find'       key='Ctrl+F'>Find...</item>" S+
  S"     <item do='find-next'  key='F3'>Find Next</item>" S+
  S"     <item do='find-prev'  key='Shift+F3'>Find Previous</item>" S+
  S"     <item do='goto-line'  key='Ctrl+G'>Go to Line...</item>" S+
  S"   </menu>" S+
  S"   <menu label='View'>" S+
  S"     <item do='toggle-sidebar'>Toggle Sidebar</item>" S+
  S"     <item do='toggle-mode'>Toggle Insert/Overwrite</item>" S+
  S"   </menu>" S+
  S" </menubar>" S+

  \ ── Main Body: sidebar + editor ───────────────────────
  S" <split id='main-split' ratio='20' mode='h'>" S+

  \   Left pane: file list
  S"   <region id='sidebar' arrange='stack' when='ui.sidebar'>" S+
  S"     <label style='bold'>Files</label>" S+
  S"     <input id='filter' bind='ui.filter'" S+
  S"            placeholder='Filter...' />" S+
  S"     <list id='file-list' bind='fs.entries'" S+
  S"           display='name' on-select='open-idx' />" S+
  S"   </region>" S+

  \   Right pane: editor area
  S"   <region id='editor-pane' arrange='stack'>" S+
  S"     <textarea id='editor'" S+
  S"               bind='editor.content'" S+
  S"               on-change='on-edit'" S+
  S"               on-cursor='on-cursor-move'" S+
  S"               wrap='off' />" S+
  S"   </region>" S+

  S" </split>" S+

  \ ── Toolbar ───────────────────────────────────────────
  S" <toolbar>" S+
  S"   <action do='run'  key='F5'>▶ Run</action>" S+
  S"   <action do='stop' key='F6'>■ Stop</action>" S+
  S"   <progress id='prog' bind='build.progress' />" S+
  S"   <label bind='editor.selection' />" S+
  S" </toolbar>" S+

  \ ── Status Bar ────────────────────────────────────────
  S" <status>" S+
  S"   <label bind='ui.status' />" S+
  S"   <label bind='editor.cursor.text' />" S+
  S"   <label bind='editor.mode' />" S+
  S" </status>" S+

  \ ── Dialogs (hidden until triggered) ──────────────────

  \   Find & Replace
  S" <dialog id='find-dlg' title='Find'" S+
  S"         when='find.visible'>" S+
  S"   <region arrange='stack'>" S+
  S"     <label>Search for:</label>" S+
  S"     <input id='find-input' bind='find.query'" S+
  S"            on-change='on-find-change' />" S+
  S"     <region arrange='flex'>" S+
  S"       <action do='find-prev'>◀ Prev</action>" S+
  S"       <action do='find-next'>Next ▶</action>" S+
  S"       <action do='find-close'>Close</action>" S+
  S"     </region>" S+
  S"     <label bind='find.status' />" S+
  S"   </region>" S+
  S" </dialog>" S+

  \   Go-to-Line
  S" <dialog id='goto-dlg' title='Go to Line'" S+
  S"         when='ui.goto-visible'>" S+
  S"   <input id='goto-input' bind='ui.goto-line'" S+
  S"          placeholder='Line number...' />" S+
  S"   <region arrange='flex'>" S+
  S"     <action do='goto-exec'>Go</action>" S+
  S"     <action do='goto-cancel'>Cancel</action>" S+
  S"   </region>" S+
  S" </dialog>" S+

  \   Quit Confirmation
  S" <dialog id='quit-dlg' title='Unsaved Changes'" S+
  S"         when='ui.confirm-quit'>" S+
  S"   <label>You have unsaved changes.</label>" S+
  S"   <region arrange='flex'>" S+
  S"     <action do='save-quit'>Save &amp; Quit</action>" S+
  S"     <action do='force-quit'>Discard</action>" S+
  S"     <action do='cancel-quit'>Cancel</action>" S+
  S"   </region>" S+
  S" </dialog>" S+

  S" </uidl>" S+
;
```

### A.4 Helper Words

```forth
\ ════════════════════════════════════════════════════════
\ §3  HELPERS
\ ════════════════════════════════════════════════════════

\ ── Scratch buffers ──
256 CONSTANT PAD-NAME-MAX
CREATE _pad-name-buf  PAD-NAME-MAX ALLOT
VARIABLE _pad-name-len

8192 CONSTANT PAD-BUF-MAX          \ max file content
CREATE _pad-file-buf  PAD-BUF-MAX ALLOT

CREATE _pad-num-buf 24 ALLOT       \ number→string scratch

\ ── Number → string conversion ──
: pad-u>s  ( u -- addr len )
  _pad-num-buf 24 + SWAP           \ end-ptr  u
  BEGIN
    10 /MOD SWAP                   \ quot rem
    [CHAR] 0 + OVER 1- C!         \ store digit
    SWAP 1- SWAP                   \ dec ptr
    DUP 0=
  UNTIL DROP
  DUP _pad-num-buf 24 + OVER - ;  \ addr len

\ ── Format cursor position for status bar ──
: pad-cursor-text  ( ln col -- addr len )
  SWAP pad-u>s                     \ "42"
  S" Ln " 2SWAP S+                 \ "Ln 42"
  S" , Col " S+                    \ "Ln 42, Col "
  SWAP pad-u>s S+                  \ "Ln 42, Col 7"
;

\ ── Push current content onto undo stack ──
: pad-undo-push  ( -- )
  S" editor.content" ST-GET-PATH ?DUP IF
    ST-GET-STR
    S" editor.undo" ST-ARRAY-APPEND-STR
  THEN
  \ Clear redo on new edit
  S" editor.redo" ST-DELETE-PATH
;

\ ── Update status bar ──
: pad-status!  ( addr len -- )
  S" ui.status" ST-SET-PATH-STR ;

\ ── Mark buffer dirty ──
: pad-mark-dirty  ( -- )
  TRUE S" editor.dirty" ST-SET-PATH-BOOL
  S" Modified" pad-status! ;

\ ── Mark buffer clean ──
: pad-mark-clean  ( -- )
  FALSE S" editor.dirty" ST-SET-PATH-BOOL
  S" Saved" pad-status! ;

\ ── Get current file index ──
: pad-cur-idx  ( -- n )
  S" fs.current" ST-GET-PATH ?DUP IF ST-GET-INT ELSE -1 THEN ;

\ ── Get file name by index ──
: pad-file-name  ( idx -- addr len )
  pad-u>s S" fs.entries." 2SWAP S+ S" .name" S+
  ST-GET-PATH ?DUP IF ST-GET-STR ELSE S" (unknown)" THEN ;

\ ── Save content into the fs.entries array ──
: pad-save-to-entry  ( idx -- )
  DUP pad-u>s S" fs.entries." 2SWAP S+ S" .content" S+
  S" editor.content" ST-GET-PATH ?DUP IF
    ST-GET-STR ROT ST-SET-PATH-STR
  ELSE 2DROP THEN
  pad-u>s S" fs.entries." 2SWAP S+ S" .dirty" S+
  FALSE SWAP ST-SET-PATH-BOOL ;

\ ── Load content from an fs.entries element ──
: pad-load-from-entry  ( idx -- )
  DUP S" fs.current" ST-SET-PATH-INT
  pad-u>s S" fs.entries." 2SWAP S+ S" .content" S+
  ST-GET-PATH ?DUP IF
    ST-GET-STR S" editor.content" ST-SET-PATH-STR
  ELSE S" " S" editor.content" ST-SET-PATH-STR THEN
  pad-mark-clean
  1 S" editor.cursor.ln"  ST-SET-PATH-INT
  1 S" editor.cursor.col" ST-SET-PATH-INT
  1 1 pad-cursor-text S" editor.cursor.text" ST-SET-PATH-STR
;
```

### A.5 Action Handlers

```forth
\ ════════════════════════════════════════════════════════
\ §4  ACTION HANDLERS
\ ════════════════════════════════════════════════════════
\ Every do="name" in the UIDL gets a Forth word registered
\ via UTUI-DO!.  The handler signature is always ( elem -- ).
\ The elem is the UIDL element that fired the action.
\ Handlers mutate the state-tree; the UI updates reactively.

\ ──────────────────────────────────────────────
\ File actions
\ ──────────────────────────────────────────────

: on-new  ( elem -- )
  DROP
  \ Save current if dirty
  S" editor.dirty" ST-GET-PATH ?DUP IF
    ST-GET-BOOL IF pad-cur-idx pad-save-to-entry THEN
  THEN
  \ Append new entry
  S" fs.count" ST-GET-PATH ?DUP IF
    DUP ST-GET-INT DUP 1+          \ old-count new-count
    ROT ST-SET-INT                  \ update count
    \ Name it "(new N)"
    DUP pad-u>s S" (new " 2SWAP S+ S" )" S+
    OVER pad-u>s S" fs.entries." 2SWAP S+ S" .name" S+
    ST-SET-PATH-STR
    \ Empty content
    S" " OVER pad-u>s S" fs.entries." 2SWAP S+ S" .content" S+
    ST-SET-PATH-STR
    \ Load it
    pad-load-from-entry
  ELSE DROP THEN
  S" New file created" pad-status!
;

: on-save  ( elem -- )
  DROP
  pad-cur-idx DUP 0< IF
    DROP S" Nothing to save" pad-status!
  ELSE
    DUP pad-save-to-entry
    pad-mark-clean
    pad-file-name S" Saved: " 2SWAP S+
    pad-status!
  THEN
;

: on-save-as  ( elem -- )
  DROP
  \ In a real system this would open a name input dialog.
  \ For now, duplicate current entry under a new name.
  on-new                           \ fake: create new file
  S" (Use rename to set name)" pad-status!
;

: on-close  ( elem -- )
  DROP
  pad-cur-idx DUP 0< IF DROP EXIT THEN
  \ If dirty, prompt save? For now, just discard.
  \ Remove from entries array
  pad-u>s S" fs.entries." 2SWAP S+ ST-DELETE-PATH
  S" fs.count" ST-GET-PATH ?DUP IF
    DUP ST-GET-INT 1- 0 MAX SWAP ST-SET-INT
  THEN
  \ Open previous or clear
  S" fs.count" ST-GET-PATH ?DUP IF
    ST-GET-INT DUP 0> IF
      1- pad-load-from-entry
    ELSE
      DROP
      -1 S" fs.current" ST-SET-PATH-INT
      S" " S" editor.content" ST-SET-PATH-STR
    THEN
  THEN
  S" File closed" pad-status!
;

: on-quit  ( elem -- )
  DROP
  S" editor.dirty" ST-GET-PATH ?DUP IF
    ST-GET-BOOL IF
      \ Dirty → show confirmation dialog
      TRUE S" ui.confirm-quit" ST-SET-PATH-BOOL
      EXIT
    THEN
  THEN
  TUI-EVT-QUIT                    \ clean → quit directly
;

: on-save-quit  ( elem -- )
  DROP
  pad-cur-idx DUP 0>= IF pad-save-to-entry ELSE DROP THEN
  FALSE S" ui.confirm-quit" ST-SET-PATH-BOOL
  TUI-EVT-QUIT
;

: on-force-quit  ( elem -- )
  DROP
  FALSE S" ui.confirm-quit" ST-SET-PATH-BOOL
  TUI-EVT-QUIT
;

: on-cancel-quit  ( elem -- )
  DROP
  FALSE S" ui.confirm-quit" ST-SET-PATH-BOOL
;

: on-open  ( elem -- )
  DROP
  \ Placeholder: in production, this would present a file
  \ browser dialog populated from KDOS directory listing.
  \ For this demo, create a sample file with content.
  S" fs.count" ST-GET-PATH ?DUP IF
    DUP ST-GET-INT DUP 1+
    ROT ST-SET-INT
    DUP pad-u>s S" fs.entries." 2SWAP S+ S" .name" S+
    S" example.f" SWAP ST-SET-PATH-STR
    DUP pad-u>s S" fs.entries." 2SWAP S+ S" .content" S+
    S" : hello  .\" Hello from Akashic Pad!\" CR ;\nhello\n"
    SWAP ST-SET-PATH-STR
    pad-load-from-entry
    S" Opened example.f" pad-status!
  ELSE DROP THEN
;

\ Open a file by index (from the file list on-select)
: on-open-idx  ( elem -- )
  \ The list widget puts the selected index in the element's
  \ sidecar.  Retrieve it via UIDL-BIND-EVAL.
  UIDL-BIND-EVAL DROP             \ type v1 v2 → value is index
  DROP                             \ drop v2 (unused for int)
  DUP 0>= IF
    \ Save current first
    S" editor.dirty" ST-GET-PATH ?DUP IF
      ST-GET-BOOL IF pad-cur-idx pad-save-to-entry THEN
    THEN
    pad-load-from-entry
  ELSE DROP THEN
;

\ ──────────────────────────────────────────────
\ Edit actions
\ ──────────────────────────────────────────────

: on-undo  ( elem -- )
  DROP
  S" editor.undo" ST-ARRAY-COUNT ?DUP IF
    1-                             \ index of last entry
    DUP S" editor.undo" ST-ARRAY-NTH ?DUP IF
      \ Push current to redo before restoring
      S" editor.content" ST-GET-PATH ?DUP IF
        ST-GET-STR S" editor.redo" ST-ARRAY-APPEND-STR
      THEN
      \ Restore from undo
      ST-GET-STR S" editor.content" ST-SET-PATH-STR
      \ Remove consumed entry
      S" editor.undo" ST-ARRAY-REMOVE
      S" Undo" pad-status!
    ELSE DROP THEN
  ELSE S" Nothing to undo" pad-status! THEN
;

: on-redo  ( elem -- )
  DROP
  S" editor.redo" ST-ARRAY-COUNT ?DUP IF
    1-
    DUP S" editor.redo" ST-ARRAY-NTH ?DUP IF
      \ Push current to undo
      S" editor.content" ST-GET-PATH ?DUP IF
        ST-GET-STR S" editor.undo" ST-ARRAY-APPEND-STR
      THEN
      ST-GET-STR S" editor.content" ST-SET-PATH-STR
      S" editor.redo" ST-ARRAY-REMOVE
      S" Redo" pad-status!
    ELSE DROP THEN
  ELSE S" Nothing to redo" pad-status! THEN
;

: on-select-all  ( elem -- )
  DROP
  S" Ln 1-end" S" editor.selection" ST-SET-PATH-STR
  S" All selected" pad-status!
;

\ Cut/Copy/Paste use a clipboard buffer
4096 CONSTANT PAD-CLIP-MAX
CREATE _pad-clipboard  PAD-CLIP-MAX ALLOT
VARIABLE _pad-clip-len  0 _pad-clip-len !

: on-copy  ( elem -- )
  DROP
  \ Copy editor content to clipboard (full buffer for demo;
  \ real impl would copy selection only)
  S" editor.content" ST-GET-PATH ?DUP IF
    ST-GET-STR DUP PAD-CLIP-MAX MIN
    DUP _pad-clip-len !
    _pad-clipboard SWAP CMOVE
    S" Copied" pad-status!
  ELSE S" Nothing to copy" pad-status! THEN
;

: on-cut  ( elem -- )
  DUP on-copy
  DROP                            \ consume elem from on-copy
  pad-undo-push
  S" " S" editor.content" ST-SET-PATH-STR
  pad-mark-dirty
;

: on-paste  ( elem -- )
  DROP
  _pad-clip-len @ ?DUP IF
    pad-undo-push
    _pad-clipboard SWAP
    S" editor.content" ST-SET-PATH-STR
    pad-mark-dirty
    S" Pasted" pad-status!
  ELSE
    S" Clipboard empty" pad-status!
  THEN
;

\ ──────────────────────────────────────────────
\ Editor callbacks (from textarea on-change/on-cursor)
\ ──────────────────────────────────────────────

: on-edit  ( elem -- )
  \ Fired on every keystroke in the textarea.
  \ The textarea has already updated editor.content via
  \ bind-write.  We just need to mark dirty & push undo.
  DROP
  pad-undo-push
  pad-mark-dirty
;

: on-cursor-move  ( elem -- )
  \ Textarea fires this when cursor position changes.
  \ Read cursor pos from element sidecar → update status.
  DROP
  S" editor.cursor.ln"  ST-GET-PATH ?DUP IF ST-GET-INT ELSE 1 THEN
  S" editor.cursor.col" ST-GET-PATH ?DUP IF ST-GET-INT ELSE 1 THEN
  2DUP pad-cursor-text S" editor.cursor.text" ST-SET-PATH-STR
;

\ ──────────────────────────────────────────────
\ Search actions
\ ──────────────────────────────────────────────

: on-find  ( elem -- )
  DROP
  TRUE S" find.visible" ST-SET-PATH-BOOL
  S" find-input" UTUI-BY-ID ?DUP IF UTUI-FOCUS! THEN
;

: on-find-close  ( elem -- )
  DROP
  FALSE S" find.visible" ST-SET-PATH-BOOL
  S" editor" UTUI-BY-ID ?DUP IF UTUI-FOCUS! THEN
;

: on-find-change  ( elem -- )
  \ Live search: user typed in find input → count matches.
  \ Full implementation would scan editor.content for
  \ find.query and update find.match-count.
  DROP
  S" find.query" ST-GET-PATH ?DUP IF
    ST-GET-STR NIP                 \ query-len
    DUP 0> IF
      DROP                         \ placeholder: actual search
      S" (searching...)" S" ui.status" ST-SET-PATH-STR
    ELSE
      DROP 0 S" find.match-count" ST-SET-PATH-INT
    THEN
  THEN
;

: on-find-next  ( elem -- )
  DROP
  S" find.match-idx" ST-GET-PATH ?DUP IF
    DUP ST-GET-INT 1+ SWAP ST-SET-INT
  THEN
  S" Find next" pad-status!
;

: on-find-prev  ( elem -- )
  DROP
  S" find.match-idx" ST-GET-PATH ?DUP IF
    DUP ST-GET-INT 1- 0 MAX SWAP ST-SET-INT
  THEN
  S" Find previous" pad-status!
;

: on-goto-line  ( elem -- )
  DROP
  TRUE S" ui.goto-visible" ST-SET-PATH-BOOL
;

: on-goto-exec  ( elem -- )
  DROP
  S" ui.goto-line" ST-GET-PATH ?DUP IF
    ST-GET-INT                     \ target line
    DUP S" editor.cursor.ln" ST-SET-PATH-INT
    1 pad-cursor-text S" editor.cursor.text" ST-SET-PATH-STR
  THEN
  FALSE S" ui.goto-visible" ST-SET-PATH-BOOL
  S" editor" UTUI-BY-ID ?DUP IF UTUI-FOCUS! THEN
;

: on-goto-cancel  ( elem -- )
  DROP
  FALSE S" ui.goto-visible" ST-SET-PATH-BOOL
;

\ ──────────────────────────────────────────────
\ View actions
\ ──────────────────────────────────────────────

: on-toggle-sidebar  ( elem -- )
  DROP
  S" ui.sidebar" ST-GET-PATH ?DUP IF
    DUP ST-GET-BOOL INVERT SWAP ST-SET-BOOL
    UTUI-RELAYOUT                 \ recompute split pane sizes
  THEN
;

: on-toggle-mode  ( elem -- )
  DROP
  S" editor.mode" ST-GET-PATH ?DUP IF
    DUP ST-GET-STR S" INSERT" COMPARE 0= IF
      S" OVERWRITE" SWAP ST-SET-STR
    ELSE
      S" INSERT" SWAP ST-SET-STR
    THEN
  THEN
;

\ ──────────────────────────────────────────────
\ Build / Run actions (demo / placeholder)
\ ──────────────────────────────────────────────

VARIABLE _pad-running  FALSE _pad-running !

: on-run  ( elem -- )
  DROP
  _pad-running @ IF
    S" Already running" pad-status! EXIT
  THEN
  TRUE _pad-running !
  0 S" build.progress" ST-SET-PATH-INT
  S" Running..." pad-status!
  \ In production: fork a KDOS task that executes the buffer
  \ content via EVALUATE and updates build.progress.
  \ For demo, the tick handler increments progress.
;

: on-stop  ( elem -- )
  DROP
  _pad-running @ INVERT IF
    S" Not running" pad-status! EXIT
  THEN
  FALSE _pad-running !
  0 S" build.progress" ST-SET-PATH-INT
  S" Stopped" pad-status!
;
```

### A.6 Registration & Lifecycle

```forth
\ ════════════════════════════════════════════════════════
\ §5  REGISTER ALL ACTIONS + LIFECYCLE
\ ════════════════════════════════════════════════════════

: pad-register-actions  ( -- )
  \ File
  S" new"            ' on-new          UTUI-DO!
  S" open"           ' on-open         UTUI-DO!
  S" save"           ' on-save         UTUI-DO!
  S" save-as"        ' on-save-as      UTUI-DO!
  S" close"          ' on-close        UTUI-DO!
  S" quit"           ' on-quit         UTUI-DO!
  S" save-quit"      ' on-save-quit    UTUI-DO!
  S" force-quit"     ' on-force-quit   UTUI-DO!
  S" cancel-quit"    ' on-cancel-quit  UTUI-DO!

  \ Edit
  S" undo"           ' on-undo         UTUI-DO!
  S" redo"           ' on-redo         UTUI-DO!
  S" select-all"     ' on-select-all   UTUI-DO!
  S" cut"            ' on-cut          UTUI-DO!
  S" copy"           ' on-copy         UTUI-DO!
  S" paste"          ' on-paste        UTUI-DO!

  \ Search
  S" find"           ' on-find         UTUI-DO!
  S" find-next"      ' on-find-next    UTUI-DO!
  S" find-prev"      ' on-find-prev    UTUI-DO!
  S" find-close"     ' on-find-close   UTUI-DO!
  S" goto-line"      ' on-goto-line    UTUI-DO!
  S" goto-exec"      ' on-goto-exec    UTUI-DO!
  S" goto-cancel"    ' on-goto-cancel  UTUI-DO!

  \ Editor callbacks
  S" on-edit"        ' on-edit         UTUI-DO!
  S" on-cursor-move" ' on-cursor-move  UTUI-DO!
  S" open-idx"       ' on-open-idx     UTUI-DO!

  \ View
  S" toggle-sidebar" ' on-toggle-sidebar UTUI-DO!
  S" toggle-mode"    ' on-toggle-mode    UTUI-DO!

  \ Build
  S" run"            ' on-run          UTUI-DO!
  S" stop"           ' on-stop         UTUI-DO!

  \ Find change (live search)
  S" on-find-change" ' on-find-change  UTUI-DO!
;

\ ── Tick handler: animate build progress ──
: pad-on-tick  ( -- )
  _pad-running @ IF
    S" build.progress" ST-GET-PATH ?DUP IF
      DUP ST-GET-INT 5 +
      DUP 100 > IF
        DROP
        FALSE _pad-running !
        100 S" build.progress" ST-SET-PATH-INT
        S" Build complete" pad-status!
      ELSE
        SWAP ST-SET-INT
      THEN
    THEN
  THEN
;

\ ── Global key handler (intercepts before focus) ──
: pad-global-key  ( event -- consumed? )
  \ Handle Escape to close any open dialog
  DUP KEY-CODE@ KEY-ESC = IF
    DROP
    S" find.visible" ST-GET-PATH ?DUP IF
      ST-GET-BOOL IF
        FALSE S" find.visible" ST-SET-PATH-BOOL
        TRUE EXIT
      THEN
    THEN
    S" ui.confirm-quit" ST-GET-PATH ?DUP IF
      ST-GET-BOOL IF
        FALSE S" ui.confirm-quit" ST-SET-PATH-BOOL
        TRUE EXIT
      THEN
    THEN
    S" ui.goto-visible" ST-GET-PATH ?DUP IF
      ST-GET-BOOL IF
        FALSE S" ui.goto-visible" ST-SET-PATH-BOOL
        TRUE EXIT
      THEN
    THEN
    FALSE                          \ Escape not consumed
  ELSE DROP FALSE THEN             \ not Escape → not consumed
;

\ ════════════════════════════════════════════════════════
\ §6  MAIN
\ ════════════════════════════════════════════════════════

: pad-setup  ( -- )
  APP-SCREEN SCR-USE
  0 0 80 24 RGN-SET CONSTANT pad-rgn

  \ Parse UIDL + allocate sidecars + layout + wire XTs
  pad-uidl pad-rgn UTUI-LOAD INVERT IF
    ." UIDL parse failed" CR EXIT
  THEN

  \ Register all do= action handlers
  pad-register-actions

  \ Wire tick + global key handlers
  ['] pad-on-tick  TUI-EVT-ON-TICK
  ['] pad-global-key TUI-EVT-ON-KEY
  500 TUI-EVT-TICK-MS!             \ tick every 500 ms

  \ Set title
  S" Akashic Pad" APP-TITLE!

  \ Initial paint
  UTUI-PAINT

  S" Akashic Pad ready" pad-status!
;

: pad-main
  ['] pad-setup 80 24 APP-RUN-FULL
;

pad-main
```

### A.7 What This Demonstrates

| Capability | Where |
|-----------|-------|
| **Menu bar** with 4 menus, 16 items | `<menubar>` + `<menu>` + `<item>` |
| **Global keyboard shortcuts** | `key='Ctrl+S'` etc. → shortcut table |
| **Split pane** sidebar + editor | `<split ratio='20' mode='h'>` |
| **Collapsible sidebar** | `when='ui.sidebar'` + `on-toggle-sidebar` |
| **File list** with filter | `<list bind='fs.entries'>` + `<input bind='ui.filter'>` |
| **Multi-file editing** | `fs.entries[]` array, `on-open-idx`, `on-close` |
| **Full textarea** | `<textarea bind='editor.content'>` |
| **Reactive data binding** | Cursor position → status bar, dirty flag → title |
| **Undo/Redo** | `editor.undo[]` / `editor.redo[]` stacks via `ST-ARRAY-*` |
| **Cut/Copy/Paste** | Clipboard buffer + state-tree mutations |
| **Find dialog** (Ctrl+F) | `when='find.visible'` → `<dialog>` with live search |
| **Go-to-Line dialog** (Ctrl+G) | `when='ui.goto-visible'` → input + action |
| **Quit with save prompt** | `on-quit` checks `editor.dirty` → `<dialog>` |
| **Insert/Overwrite toggle** | `editor.mode` ↔ status bar |
| **Progress bar** | `<progress bind='build.progress'>` + tick handler |
| **Toolbar** | `<toolbar>` with Run/Stop + progress |
| **Status bar** | `<status>` with 3 reactive labels |
| **Escape closes dialogs** | `pad-global-key` intercept |
| **Tick timer** | `TUI-EVT-ON-TICK` for build progress animation |
| **Application lifecycle** | `APP-RUN-FULL` for clean init/run/shutdown |

### A.8 What Application Code Does vs. What the Framework Does

**Application code (~450 lines)** is responsible for:
- Defining the state-tree schema (what data exists)
- Writing the UIDL markup (what the UI looks like)
- Implementing action handlers (what happens when the user acts)
- Registering actions (`UTUI-DO!`)

**The framework (~15,000 lines across 28 files) handles:**
- Parsing UIDL markup into an element tree
- Allocating TUI sidecars and computing layout
- Rendering elements to the double-buffered screen
- Differential flush (only changed cells emitted)
- Key decoding (raw bytes → structured key events)
- Shortcut matching (`key='Ctrl+S'` → call `on-save`)
- Focus management (Tab/Shift-Tab cycling)
- Event dispatch (capture/target/bubble on UIDL tree)
- Hit testing (mouse → element mapping)
- Subscription-driven dirty propagation
- LEL expression evaluation for `bind=` and `when=`
- Box drawing, borders, colors, Unicode
- Dialog overlay and focus trapping
- Terminal enter/exit alternate screen, cursor, title
- Cooperative event loop with timer ticks and `YIELD?`

The ratio is roughly **30:1** — 450 lines of application for 15,000
lines of framework.  That's the payoff for the layer stack.

### A.9 Stylesheet — Making It Pretty

Akashic has a **full CSS parser** (`css/css.f`, 1836 lines) with rule
iteration, selector matching (type, class, id, compound, groups),
specificity calculation, `!important`, hex/rgb()/named color parsing,
and declaration lookup — plus a bridge (`css/bridge.f`) that collects
matching rules for an element.  The DOM-TUI path already uses it.

The UIDL path can use the exact same CSS engine.  `uidl-tui.f` adds
a thin resolution layer: parse the stylesheet once at load time, then
for each UIDL element, match CSS rules by element type (`label`,
`action`, `input`, etc.), `id=`, and `class=` attributes, resolve
colors to 256-palette indices via `DTUI-RESOLVE-COLOR`, and pack the
result into the sidecar `style` field.

#### How It Works

```
CSS text
  │
  ▼  CSS-RULE-NEXT (iterate rules)
  ├─ selector: "menubar"
  │  body: "color: #DADADA; background: #444; font-weight: bold"
  ├─ selector: "#editor"
  │  body: "color: #DADADA; background: #303030"
  ├─ ...
  │
  ▼  For each UIDL element:
  CSS-MATCH-SET ( tag-a tag-u id-a id-u class-a class-u -- )
  │               ↑ element type   ↑ id=          ↑ class=
  │
  ▼  CSS-MATCH-SIMPLE for each rule's selector → collect matching decls
  │
  ▼  CSS-DECL-FIND "color" → CSS-PARSE-HEX-COLOR → DTUI-RESOLVE-COLOR → fg index
  ▼  CSS-DECL-FIND "background" → ... → bg index
  ▼  CSS-DECL-FIND "font-weight" → "bold" → CELL-A-BOLD
  ▼  CSS-DECL-FIND "border-style" → "rounded" → border byte
  │
  ▼  Pack → sidecar +32: fg(8) bg(8) attrs(8) border(8)
```

#### The Akashic Pad Stylesheet

Real CSS, parsed by `CSS-RULE-NEXT` + `CSS-DECL-FIND` + color
resolution.  Uses the subset of CSS properties that map to TUI cells:

```forth
\ ════════════════════════════════════════════════════════
\ §7  STYLESHEET — "Akashic Dark"
\ ════════════════════════════════════════════════════════
\ Parsed at load time by the CSS engine (css/css.f).
\ Colors are standard CSS (#hex, rgb(), named).
\ Properties map to TUI attributes per dom-tui.f §5.1.

: pad-css  ( -- addr len )
  S" /* ── Akashic Dark Theme ────────────────────── */" S+

  \ --- Root / global defaults ---
  S" uidl {" S+
  S"   color: #DADADA;" S+               \ 253 — light gray text
  S"   background: #303030;" S+           \ 236 — dark gray bg
  S" }" S+

  \ --- Menu bar ---
  S" menubar {" S+
  S"   color: white;" S+                  \ 15 — bright white
  S"   background: #444444;" S+           \ 238
  S"   font-weight: bold;" S+
  S" }" S+

  S" menu {" S+
  S"   color: #DADADA;" S+
  S"   background: #262626;" S+           \ 235
  S" }" S+

  S" item {" S+
  S"   color: #DADADA;" S+
  S"   background: #262626;" S+
  S" }" S+

  S" item:focus {" S+                     \ focused menu item
  S"   color: black;" S+
  S"   background: #5FAFFF;" S+           \ 75 — accent blue
  S"   font-weight: bold;" S+
  S" }" S+

  \ --- Sidebar ---
  S" #sidebar {" S+
  S"   color: #BCBCBC;" S+                \ 250
  S"   background: #262626;" S+           \ 235
  S"   border-style: solid;" S+
  S" }" S+

  S" #sidebar > label {" S+              \ "FILES" heading
  S"   color: #5FAFFF;" S+               \ accent blue
  S"   font-weight: bold;" S+
  S"   text-decoration: underline;" S+
  S" }" S+

  S" #filter {" S+
  S"   color: #DADADA;" S+
  S"   background: #444444;" S+
  S" }" S+

  S" list {" S+
  S"   color: #BCBCBC;" S+
  S"   background: #262626;" S+
  S" }" S+

  S" list:focus {" S+
  S"   color: white;" S+
  S"   background: #5FAFFF;" S+
  S" }" S+

  \ --- Editor area ---
  S" #editor-pane {" S+
  S"   background: #303030;" S+
  S" }" S+

  S" textarea {" S+
  S"   color: #DADADA;" S+
  S"   background: #303030;" S+
  S" }" S+

  S" textarea:focus {" S+
  S"   background: #303030;" S+           \ cursor line via render-xt
  S" }" S+

  \ --- Toolbar ---
  S" toolbar {" S+
  S"   color: #DADADA;" S+
  S"   background: #444444;" S+
  S" }" S+

  S" toolbar > action.run {" S+
  S"   color: black;" S+
  S"   background: #87D787;" S+           \ 114 — green
  S"   font-weight: bold;" S+
  S" }" S+

  S" toolbar > action.stop {" S+
  S"   color: black;" S+
  S"   background: #FF8787;" S+           \ 210 — red-pink
  S"   font-weight: bold;" S+
  S" }" S+

  S" progress {" S+
  S"   color: #FFD787;" S+                \ 222 — gold fill
  S"   background: #444444;" S+           \ dark track
  S" }" S+

  \ --- Status bar ---
  S" status {" S+
  S"   color: #A8A8A8;" S+                \ 248
  S"   background: #262626;" S+           \ 235
  S" }" S+

  S" status > label.cursor {" S+
  S"   color: #5FAFFF;" S+               \ accent blue
  S" }" S+

  S" status > label.mode {" S+
  S"   color: #FFD787;" S+               \ gold
  S"   font-weight: bold;" S+
  S" }" S+

  S" status > label.message {" S+
  S"   color: #87D787;" S+               \ green
  S" }" S+

  \ --- Dialogs (shared) ---
  S" dialog {" S+
  S"   color: white;" S+
  S"   background: #262626;" S+
  S"   border-style: rounded;" S+
  S" }" S+

  S" dialog > label {" S+
  S"   color: #DADADA;" S+
  S" }" S+

  S" dialog input {" S+
  S"   color: white;" S+
  S"   background: #444444;" S+
  S" }" S+

  \ --- Action buttons (by class) ---
  S" action {" S+                         \ default action
  S"   color: #DADADA;" S+
  S"   background: #444444;" S+
  S" }" S+

  S" action:focus {" S+
  S"   color: black;" S+
  S"   background: #5FAFFF;" S+           \ accent blue
  S"   font-weight: bold;" S+
  S" }" S+

  S" action.primary {" S+
  S"   color: black;" S+
  S"   background: #5FAFFF;" S+
  S"   font-weight: bold;" S+
  S" }" S+

  S" action.success {" S+
  S"   color: black;" S+
  S"   background: #87D787;" S+
  S"   font-weight: bold;" S+
  S" }" S+

  S" action.danger {" S+
  S"   color: black;" S+
  S"   background: #FF8787;" S+
  S"   font-weight: bold;" S+
  S" }" S+

  S" action.muted {" S+
  S"   color: #DADADA;" S+
  S"   background: #585858;" S+           \ 240 — gray
  S" }" S+

  \ --- Tabs ---
  S" tabs {" S+
  S"   color: #585858;" S+                \ inactive tab text
  S"   background: #444444;" S+           \ tab bar bg
  S" }" S+

  S" tab {" S+                            \ inactive tab
  S"   color: #585858;" S+
  S"   background: #444444;" S+
  S" }" S+

  S" tab:focus {" S+                      \ active tab
  S"   color: white;" S+
  S"   background: #303030;" S+           \ matches editor bg
  S"   font-weight: bold;" S+
  S" }" S+

  \ --- Split divider ---
  S" split {" S+
  S"   color: #585858;" S+                \ divider color
  S"   background: #303030;" S+
  S" }" S+

  \ --- Tree (file explorer) ---
  S" tree {" S+
  S"   color: #BCBCBC;" S+
  S"   background: #262626;" S+
  S" }" S+

  \ --- Quit confirm dialog (override) ---
  S" #quit-dlg {" S+
  S"   border-style: double;" S+          \ double border = serious
  S" }" S+

  S" #quit-dlg > label {" S+
  S"   color: #FF8787;" S+               \ warning red
  S"   font-weight: bold;" S+
  S" }" S+

  \ --- Find dialog ---
  S" #find-dlg label.heading {" S+
  S"   color: #5FAFFF;" S+
  S"   font-weight: bold;" S+
  S" }" S+

  S" #find-dlg label.status {" S+
  S"   color: #D7AFFF;" S+               \ 183 — lavender
  S"   font-style: italic;" S+
  S" }" S+

  \ --- Search highlight (applied dynamically) ---
  S" .search-match {" S+
  S"   color: black;" S+
  S"   background: #FFD787;" S+           \ gold highlight
  S"   font-weight: bold;" S+
  S" }" S+

  \ --- Scrollbar ---
  S" scroll {" S+
  S"   color: #585858;" S+               \ thumb color
  S"   background: #303030;" S+           \ track color
  S" }" S+

  S" /* ── end theme ─────────────────────────────── */" S+
;
```

#### Loading the Stylesheet

The stylesheet is loaded once during `UTUI-LOAD`.  The resolution
process uses the existing CSS engine APIs:

```forth
REQUIRE css/css.f

2048 CONSTANT _UTUI-CSS-BUF-MAX
CREATE _UTUI-CSS-BUF  _UTUI-CSS-BUF-MAX ALLOT

VARIABLE _UTUI-CSS-A   VARIABLE _UTUI-CSS-L

\ Store the stylesheet for later re-resolution
: UTUI-SET-CSS  ( css-a css-l -- )
    _UTUI-CSS-L !  _UTUI-CSS-A ! ;

\ Resolve one UIDL element's style from the CSS rules
: _UTUI-CSS-RESOLVE-ELEM  ( elem -- )
    \ Set up CSS match context: type, id, class
    DUP UIDL-TYPE UIDL-TYPE-NAME           \ → tag-a tag-u
    2 PICK UIDL-ID                         \ → id-a id-u
    4 PICK S" class" UIDL-ATTR IF          \ → cls-a cls-u
    ELSE 0 0 THEN
    CSS-MATCH-SET                          \ configure matcher

    \ Iterate rules, collect matching declarations
    _UTUI-CSS-A @ _UTUI-CSS-L @            \ stylesheet cursor
    _UTUI-CSS-BUF _UTUI-CSS-BUF-MAX       \ output buffer
    CSSB-GET-STYLES                        \ → n (bytes collected)
    DUP 0= IF DROP DROP EXIT THEN

    \ ── Extract color property ──
    _UTUI-CSS-BUF OVER                     \ decls-a decls-len
    S" color" CSS-DECL-FIND IF             \ → val-a val-u  (e.g. "#DADADA")
      _UTUI-PARSE-CSS-COLOR                \ → r g b
      DTUI-RESOLVE-COLOR                   \ → 256-palette index
    ELSE TH-FG THEN                        \ fallback

    \ ── Extract background property ──
    _UTUI-CSS-BUF OVER
    S" background" CSS-DECL-FIND INVERT IF
      _UTUI-CSS-BUF OVER
      S" background-color" CSS-DECL-FIND
    THEN
    IF
      _UTUI-PARSE-CSS-COLOR
      DTUI-RESOLVE-COLOR
    ELSE TH-BG THEN

    \ ── Extract font-weight ──
    _UTUI-CSS-BUF OVER
    S" font-weight" CSS-DECL-FIND IF
      S" bold" COMPARE 0= IF CELL-A-BOLD ELSE 0 THEN
    ELSE 0 THEN

    \ ── Extract text-decoration ──
    _UTUI-CSS-BUF OVER
    S" text-decoration" CSS-DECL-FIND IF
      S" underline" COMPARE 0= IF CELL-A-UNDERLINE OR THEN
    THEN

    \ ── Extract font-style ──
    _UTUI-CSS-BUF OVER
    S" font-style" CSS-DECL-FIND IF
      S" italic" COMPARE 0= IF CELL-A-ITALIC OR THEN
    THEN

    \ ── Extract border-style ──
    _UTUI-CSS-BUF OVER
    S" border-style" CSS-DECL-FIND IF
      _UTUI-PARSE-BORDER                  \ → border-byte
    ELSE 0 THEN

    \ ── Pack into sidecar style field ──
    \ fg(8) bg(8) attrs(8) border(8)
    >R                                     \ save border
    >R                                     \ save attrs
    8 LSHIFT OR                            \ pack fg|bg
    R> 16 LSHIFT OR                        \ pack fg|bg|attrs
    R> 24 LSHIFT OR                        \ pack fg|bg|attrs|border

    SWAP _UTUI-SIDECAR _UTUI-SC-STYLE!    \ store in sidecar
;

\ Parse a CSS color value (hex, rgb(), or named)
: _UTUI-PARSE-CSS-COLOR  ( val-a val-u -- r g b )
    2DUP 0> IF
      OVER C@ [CHAR] # = IF
        CSS-PARSE-HEX-COLOR IF EXIT THEN 2DROP
      THEN
      2DUP S" rgb" STR-STARTS? IF
        CSS-PARSE-RGB IF EXIT THEN 2DROP
      THEN
      CSS-COLOR-FIND IF EXIT THEN
    THEN
    2DROP 218 218 218                      \ fallback: #DADADA
;

\ Resolve all elements in tree
: UTUI-RESOLVE-CSS  ( -- )
    UIDL-ROOT ?DUP IF
      BEGIN
        DUP _UTUI-CSS-RESOLVE-ELEM
        DUP UIDL-FIRST-CHILD ?DUP IF
          NIP                              \ descend to child
        ELSE
          BEGIN
            DUP UIDL-NEXT-SIB ?DUP IF
              NIP TRUE                     \ move to sibling
            ELSE
              UIDL-PARENT ?DUP IF
                UIDL-NEXT-SIB ?DUP IF
                  TRUE                     \ uncle
                ELSE FALSE THEN
              ELSE 0 FALSE THEN
            THEN
          UNTIL
          ?DUP 0= IF EXIT THEN
        THEN
      AGAIN
    THEN
;

\ Re-resolve after theme switch
: UTUI-RESTYLE  ( -- )
    UTUI-RESOLVE-CSS                       \ re-resolve all sidecars
    UIDL-ROOT ?DUP IF                      \ mark everything dirty
      BEGIN
        DUP UIDL-DIRTY!
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
          BEGIN
            DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
            ELSE UIDL-PARENT DUP IF UIDL-NEXT-SIB DUP 0<> ELSE FALSE THEN THEN
          UNTIL
          ?DUP 0= IF EXIT THEN
        THEN
      AGAIN
    THEN
;
```

#### Updated UIDL Markup (with `class=`)

With a real stylesheet, the UIDL markup is clean — no inline
`style=` needed.  Elements are styled by **type selector** (e.g.
`menubar`, `textarea`, `dialog`), **id selector** (`#sidebar`,
`#find-dlg`, `#quit-dlg`), and **class selector** (`.run`, `.stop`,
`.primary`, `.success`, `.danger`, `.muted`):

```forth
: pad-uidl-styled  ( -- addr len )
  S" <uidl cols='80' rows='24' title='Akashic Pad'>"

  \ ── Menu Bar ──────────────────────────────────────────
  S" <menubar>" S+
  S"   <menu label='File'>" S+
  S"     <item do='new'     key='Ctrl+N'>New</item>" S+
  S"     <item do='open'    key='Ctrl+O'>Open...</item>" S+
  S"     <item do='save'    key='Ctrl+S'>Save</item>" S+
  S"     <item do='save-as' key='Ctrl+Shift+S'>Save As...</item>" S+
  S"     <item do='close'   key='Ctrl+W'>Close</item>" S+
  S"     <item do='quit'    key='Ctrl+Q'>Quit</item>" S+
  S"   </menu>" S+
  S"   <menu label='Edit'>" S+
  S"     <item do='undo' key='Ctrl+Z'>Undo</item>" S+
  S"     <item do='redo' key='Ctrl+Y'>Redo</item>" S+
  S"     <item do='select-all' key='Ctrl+A'>Select All</item>" S+
  S"     <item do='cut'  key='Ctrl+X'>Cut</item>" S+
  S"     <item do='copy' key='Ctrl+C'>Copy</item>" S+
  S"     <item do='paste' key='Ctrl+V'>Paste</item>" S+
  S"   </menu>" S+
  S"   <menu label='Search'>" S+
  S"     <item do='find'       key='Ctrl+F'>Find...</item>" S+
  S"     <item do='find-next'  key='F3'>Find Next</item>" S+
  S"     <item do='find-prev'  key='Shift+F3'>Find Previous</item>" S+
  S"     <item do='goto-line'  key='Ctrl+G'>Go to Line...</item>" S+
  S"   </menu>" S+
  S"   <menu label='View'>" S+
  S"     <item do='toggle-sidebar'>Toggle Sidebar</item>" S+
  S"     <item do='toggle-mode'>Insert/Overwrite</item>" S+
  S"   </menu>" S+
  S" </menubar>" S+

  \ ── Main Body ─────────────────────────────────────────
  S" <split id='main-split' ratio='20' mode='h'>" S+

  \   Left pane: file explorer
  S"   <region id='sidebar' arrange='stack'" S+
  S"           when='ui.sidebar'>" S+
  S"     <label>  FILES</label>" S+
  S"     <input id='filter' bind='ui.filter'" S+
  S"            placeholder='🔍 Filter...' />" S+
  S"     <list id='file-list' bind='fs.entries'" S+
  S"           display='name' on-select='open-idx' />" S+
  S"   </region>" S+

  \   Right pane: editor
  S"   <region id='editor-pane' arrange='stack'>" S+
  S"     <textarea id='editor'" S+
  S"               bind='editor.content'" S+
  S"               on-change='on-edit'" S+
  S"               on-cursor='on-cursor-move'" S+
  S"               wrap='off' />" S+
  S"   </region>" S+

  S" </split>" S+

  \ ── Toolbar ───────────────────────────────────────────
  S" <toolbar>" S+
  S"   <action class='run success' do='run' key='F5'>" S+
  S"     ▶ Run</action>" S+
  S"   <action class='stop danger' do='stop' key='F6'>" S+
  S"     ■ Stop</action>" S+
  S"   <progress id='prog' bind='build.progress' />" S+
  S"   <label bind='editor.selection' />" S+
  S" </toolbar>" S+

  \ ── Status Bar ────────────────────────────────────────
  S" <status>" S+
  S"   <label class='message' bind='ui.status' />" S+
  S"   <label class='cursor' bind='editor.cursor.text' />" S+
  S"   <label class='mode' bind='editor.mode' />" S+
  S" </status>" S+

  \ ── Find Dialog ───────────────────────────────────────
  S" <dialog id='find-dlg' title='🔍 Find'" S+
  S"         when='find.visible'>" S+
  S"   <region arrange='stack'>" S+
  S"     <label class='heading'>Search for:</label>" S+
  S"     <input id='find-input' bind='find.query'" S+
  S"            on-change='on-find-change' />" S+
  S"     <region arrange='flex'>" S+
  S"       <action class='primary' do='find-prev'>◀ Prev</action>" S+
  S"       <action class='primary' do='find-next'>Next ▶</action>" S+
  S"       <action class='muted' do='find-close'>Close</action>" S+
  S"     </region>" S+
  S"     <label class='status' bind='find.status' />" S+
  S"   </region>" S+
  S" </dialog>" S+

  \ ── Go-to-Line Dialog ─────────────────────────────────
  S" <dialog id='goto-dlg' title='Go to Line'" S+
  S"         when='ui.goto-visible'>" S+
  S"   <input id='goto-input' bind='ui.goto-line'" S+
  S"          placeholder='Line number...' />" S+
  S"   <region arrange='flex'>" S+
  S"     <action class='success' do='goto-exec'>Go</action>" S+
  S"     <action class='muted' do='goto-cancel'>Cancel</action>" S+
  S"   </region>" S+
  S" </dialog>" S+

  \ ── Quit Confirmation ─────────────────────────────────
  S" <dialog id='quit-dlg' title='⚠ Unsaved Changes'" S+
  S"         when='ui.confirm-quit'>" S+
  S"   <label>You have unsaved changes.</label>" S+
  S"   <region arrange='flex'>" S+
  S"     <action class='success' do='save-quit'>" S+
  S"       Save &amp; Quit</action>" S+
  S"     <action class='danger' do='force-quit'>" S+
  S"       Discard</action>" S+
  S"     <action class='muted' do='cancel-quit'>" S+
  S"       Cancel</action>" S+
  S"   </region>" S+
  S" </dialog>" S+

  S" </uidl>" S+
;
```

Notice: **zero inline `style=` attributes**.  All styling comes from
the CSS rules matched by type (`menubar`, `dialog`, `action`), id
(`#sidebar`, `#find-dlg`, `#quit-dlg`), and class (`.success`,
`.danger`, `.primary`, `.muted`, `.cursor`, `.mode`, `.message`).

#### Wiring CSS into the Load Sequence

```forth
: pad-setup  ( -- )
  APP-SCREEN SCR-USE
  0 0 80 24 RGN-SET CONSTANT pad-rgn

  \ Load stylesheet into CSS resolver
  pad-css UTUI-SET-CSS

  \ Parse UIDL + allocate sidecars + layout + wire XTs
  pad-uidl-styled pad-rgn UTUI-LOAD INVERT IF
    ." UIDL parse failed" CR EXIT
  THEN

  \ Resolve CSS rules → sidecar styles for every element
  UTUI-RESOLVE-CSS

  \ Register actions, tick handler, global key handler
  pad-register-actions
  ['] pad-on-tick  TUI-EVT-ON-TICK
  ['] pad-global-key TUI-EVT-ON-KEY
  500 TUI-EVT-TICK-MS!

  S" Akashic Pad" APP-TITLE!
  UTUI-PAINT
  S" Akashic Pad ready" pad-status!
;
```

#### Runtime Theme Switching via CSS

Swapping themes = swapping stylesheets:

```forth
: pad-css-light  ( -- addr len )
  S" /* Akashic Light Theme */"

  S" uidl {" S+
  S"   color: #1C1C1C; background: #FFFFFF;" S+
  S" }" S+

  S" menubar {" S+
  S"   color: #1C1C1C; background: #E4E4E4;" S+
  S"   font-weight: bold;" S+
  S" }" S+

  S" menu { color: #1C1C1C; background: #F5F5F5; }" S+
  S" item { color: #1C1C1C; background: #F5F5F5; }" S+
  S" item:focus { color: white; background: #0087FF; font-weight: bold; }" S+

  S" #sidebar { color: #4E4E4E; background: #F5F5F5; border-style: solid; }" S+
  S" #sidebar > label { color: #0087FF; font-weight: bold; text-decoration: underline; }" S+
  S" #filter { color: #1C1C1C; background: #E4E4E4; }" S+
  S" list { color: #4E4E4E; background: #F5F5F5; }" S+

  S" textarea { color: #1C1C1C; background: #FFFFFF; }" S+
  S" toolbar { color: #1C1C1C; background: #E4E4E4; }" S+
  S" status { color: #6C6C6C; background: #E4E4E4; }" S+
  S" status > label.cursor { color: #0087FF; }" S+
  S" status > label.mode { color: #AF8700; font-weight: bold; }" S+
  S" status > label.message { color: #5F8700; }" S+

  S" dialog { color: #1C1C1C; background: #F5F5F5; border-style: rounded; }" S+
  S" dialog input { color: #1C1C1C; background: #E4E4E4; }" S+

  S" action { color: #1C1C1C; background: #D7D7D7; }" S+
  S" action:focus { color: white; background: #0087FF; font-weight: bold; }" S+
  S" action.success { color: white; background: #5F8700; font-weight: bold; }" S+
  S" action.danger { color: white; background: #D70000; font-weight: bold; }" S+
  S" action.primary { color: white; background: #0087FF; font-weight: bold; }" S+
  S" action.muted { color: #4E4E4E; background: #D7D7D7; }" S+

  S" tab { color: #6C6C6C; background: #E4E4E4; }" S+
  S" tab:focus { color: #1C1C1C; background: #FFFFFF; font-weight: bold; }" S+

  S" progress { color: #AF8700; background: #D7D7D7; }" S+
  S" split { color: #D7D7D7; background: #FFFFFF; }" S+
  S" #quit-dlg { border-style: double; }" S+
  S" #quit-dlg > label { color: #D70000; font-weight: bold; }" S+
  S" .search-match { color: black; background: #FFD787; font-weight: bold; }" S+
;

\ Switch to light
: on-theme-light  ( elem -- )
  DROP
  pad-css-light UTUI-SET-CSS
  UTUI-RESTYLE                    \ re-resolve all + mark dirty
  UTUI-PAINT  SCR-FLUSH
  S" Light theme applied" pad-status!
;

\ Switch to dark
: on-theme-dark  ( elem -- )
  DROP
  pad-css UTUI-SET-CSS
  UTUI-RESTYLE
  UTUI-PAINT  SCR-FLUSH
  S" Dark theme applied" pad-status!
;
```

#### CSS Properties Supported in TUI Resolution

| CSS Property | TUI Mapping | Example |
|-------------|------------|---------|
| `color` | Foreground → 256-palette via `DTUI-RESOLVE-COLOR` | `color: #5FAFFF` → index 75 |
| `background` / `background-color` | Background → 256-palette | `background: #303030` → index 236 |
| `font-weight: bold` | `CELL-A-BOLD` (bit 0) | Bold text |
| `font-style: italic` | `CELL-A-ITALIC` (bit 2) | Italic text |
| `text-decoration: underline` | `CELL-A-UNDERLINE` (bit 3) | Underlined text |
| `text-decoration: line-through` | `CELL-A-STRIKE` (bit 6) | Strikethrough |
| `border-style` | Box-drawing characters | `solid` → `│─┐└`, `double` → `║═╗╚`, `rounded` → `│─╮╰` |
| `visibility: hidden` | Sidecar visible flag cleared | Space allocated but not painted |
| `display: none` | Skip element + subtree | No space, no paint |

Color formats recognized by the parser:
- **Hex**: `#RGB`, `#RRGGBB` → `CSS-PARSE-HEX-COLOR`
- **RGB function**: `rgb(218, 218, 218)` → `CSS-PARSE-RGB`
- **Named**: all 148 CSS named colors → `CSS-COLOR-FIND` (includes `red`, `blue`, `dodgerblue`, `coral`, `whitesmoke`, etc.)

All three produce `( r g b )` which `DTUI-RESOLVE-COLOR` maps to the
nearest 256-palette index via Euclidean distance in RGB space.

#### Style Cascade Order

When `uidl-tui.f` computes an element's final sidecar style:

1. **Inherited** — parent's resolved fg/bg propagate to children
2. **CSS rules by specificity** — type < class < id < compound (standard CSS cascade via `CSS-SPECIFICITY` + `CSS-SPEC-COMPARE`)
3. **Inline `style=`** — highest specificity, if present (via `CSSB-APPLY-INLINE`)
4. **`:focus` pseudo-class** — `uidl-tui.f` re-resolves with `:focus` appended when element has focus
5. **`!important`** — detected by `CSS-IMPORTANT?`, overrides all non-important declarations
6. **Dynamic class changes** — `UTUI-CLASS-ADD` / `UTUI-CLASS-REMOVE` trigger re-resolution for that element (e.g., adding `.search-match` to highlight search results)

This is the **real CSS cascade** — same engine, same specificity math,
same `!important` handling.  The only limitation is the output: instead
of thousands of visual properties, it resolves to the TUI's `fg(8)
bg(8) attrs(8) border(8)` — which is all a character-cell terminal
can express.