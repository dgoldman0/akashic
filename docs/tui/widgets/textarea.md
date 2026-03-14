# akashic/tui/widgets/textarea.f — Multi-line Text Area Widget

**Layer:** 4B  
**Lines:** ~591  
**Prefix:** `TXTA-` (public), `_TXTA-` (internal)  
**Provider:** `akashic-tui-textarea`  
**Dependencies:** `widget.f`, `draw.f`, `keys.f`, `utf8.f`

## Overview

A multi-line text editor widget with vertical scrolling, cursor
movement (left/right/up/down/home/end/page-up/page-down), word-level
movement (Ctrl+Left / Ctrl+Right), text insertion, deletion
(backspace and forward-delete), Enter for newline insertion, and an
on-change callback that fires after every edit operation.

The widget stores text in a caller-provided fixed-size buffer as
a flat byte array with `0x0A` (newline) as the line separator.
Insertion is rejected when the buffer is full.

## Descriptor Layout (96 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=WDG-T-TEXTAREA (15) |
| +40 | buf-a | address | Pointer to text buffer |
| +48 | buf-cap | u | Buffer capacity in bytes |
| +56 | buf-len | u | Current text length in bytes |
| +64 | cursor | u | Cursor position (byte offset into buffer) |
| +72 | scroll-y | u | Vertical scroll offset (line index of first visible row) |
| +80 | on-change | xt | Change callback xt (0 = none); `( widget -- )` |
| +88 | reserved | — | Padding to 96 bytes |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `TXTA-NEW` | `( rgn buf-a buf-cap -- widget )` | Allocate + init; empty, cursor at 0, scroll at 0 |
| `TXTA-FREE` | `( widget -- )` | Free the descriptor (not the buffer) |

### Content

| Word | Stack | Description |
|------|-------|-------------|
| `TXTA-SET-TEXT` | `( text-a text-u widget -- )` | Set text; clamps to capacity; cursor at end |
| `TXTA-GET-TEXT` | `( widget -- addr len )` | Get buffer address and current length |
| `TXTA-CLEAR` | `( widget -- )` | Clear buffer, reset cursor and scroll |

### Cursor Queries

| Word | Stack | Description |
|------|-------|-------------|
| `TXTA-CURSOR-LINE` | `( widget -- n )` | 0-based line number of cursor position |
| `TXTA-CURSOR-COL` | `( widget -- n )` | 0-based column (codepoint count from start of line) |

### Callback

| Word | Stack | Description |
|------|-------|-------------|
| `TXTA-ON-CHANGE` | `( xt widget -- )` | Set on-change callback; `( widget -- )` |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Printable char | Insert at cursor |
| Backspace / Ctrl-H | Delete before cursor |
| Delete | Delete at cursor |
| Left / Right | Move cursor one codepoint |
| Up / Down | Move cursor to same column on adjacent line |
| Home | Move cursor to start of line |
| End | Move cursor to end of line |
| Enter / CR | Insert newline (`0x0A`) |
| Page Up | Move cursor up by viewport-height lines (clamp to top) |
| Page Down | Move cursor down by viewport-height lines (clamp to last line) |
| Ctrl+Left | Move cursor left to start of previous word |
| Ctrl+Right | Move cursor right to end of next word |

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_TXTA-CURSOR-LINE` | `( -- n )` | Line index (0-based) of cursor position |
| `_TXTA-LINE-COUNT` | `( -- n )` | Total number of lines in the buffer |
| `_TXTA-SOL` | `( line -- off )` | Start-of-line byte offset for line N |
| `_TXTA-EOL` | `( line -- off )` | End-of-line byte offset for line N |
| `_TXTA-LINE-OFF` | `( line -- off len )` | Start offset and length of line N |
| `_TXTA-CURSOR-COL` | `( -- n )` | Column (codepoint count) of cursor within its line |
| `_TXTA-COL-OFF` | `( line col -- off )` | Byte offset of column C in line L |
| `_TXTA-INSERT` | `( cp -- )` | Insert codepoint at cursor, shift tail |
| `_TXTA-DELETE` | `( -- )` | Forward-delete at cursor |
| `_TXTA-BACKSPACE` | `( -- )` | Delete before cursor |
| `_TXTA-LEFT` | `( -- )` | Move cursor left one codepoint |
| `_TXTA-RIGHT` | `( -- )` | Move cursor right one codepoint |
| `_TXTA-HOME` | `( -- )` | Move cursor to start of current line |
| `_TXTA-END` | `( -- )` | Move cursor to end of current line |
| `_TXTA-UP` | `( -- )` | Move cursor to same column on previous line |
| `_TXTA-DOWN` | `( -- )` | Move cursor to same column on next line |
| `_TXTA-PGUP` | `( -- )` | Move cursor up by viewport-height lines |
| `_TXTA-PGDN` | `( -- )` | Move cursor down by viewport-height lines |
| `_TXTA-IS-WORD-CHAR` | `( byte -- flag )` | True if byte is alphanumeric or underscore |
| `_TXTA-WORD-LEFT` | `( -- )` | Move cursor to start of previous word |
| `_TXTA-WORD-RIGHT` | `( -- )` | Move cursor past end of next word |
| `_TXTA-FIRE-CHANGE` | `( -- )` | Invoke on-change callback if set |
| `_TXTA-SCROLL-ADJ` | `( -- )` | Ensure cursor line is visible (clamp scroll-y) |
| `_TXTA-DRAW-LINE` | `( row -- )` | Draw one visible line at terminal row |
| `_TXTA-DRAW` | `( widget -- )` | Full draw: scroll-adjust, draw all visible rows |
| `_TXTA-HANDLE` | `( event widget -- consumed? )` | Key dispatch |

## UIDL-TUI Integration

When a UIDL `<textarea>` element is materialized by the UIDL-TUI
backend (`uidl-tui.f`), the following happens:

1. **Materialization** (`_UTUI-MAT-TXTA`): Allocates a 4096-byte
   buffer; calls `TXTA-NEW`; sets initial text from the `text=`
   attribute if present; stores the widget pointer in the element's
   sidecar `wptr` cell.

2. **Render** (`_UTUI-RENDER-TEXTAREA`): Syncs the proxy region from
   `_UR-*` layout vars, propagates focus state from sidecar to
   widget flags, delegates to `_TXTA-DRAW`.

3. **Events** (`_UTUI-H-TEXTAREA`): Syncs proxy region and focus
   from sidecar, delegates to `_TXTA-HANDLE`.

4. **Dematerialization**: Frees the buffer (read from widget+40),
   then frees the widget descriptor via `TXTA-FREE`.

## Design Notes

- **Buffer is caller-owned.** The descriptor stores a pointer to the
  caller's buffer. `TXTA-FREE` frees only the descriptor, not the
  buffer. When used through UIDL-TUI, both are freed during
  dematerialization.
- **UTF-8 aware.** Cursor movement operates on codepoint boundaries
  using `_UTF8-SEQLEN` and `_UTF8-CONT?`. Column calculations count
  codepoints, not bytes.
- **Vertical scroll.** `_TXTA-SCROLL-ADJ` ensures the cursor's line
  is within the visible region. The scroll offset is a line index.
- **Line splitting.** Lines are separated by `0x0A` bytes. The
  buffer is scanned from the start to find line boundaries — no
  separate line table is maintained.
- **Module VARIABLE pattern.** Internal words use `_TXTA-W` to avoid
  passing the widget pointer on every call. `_TXTA-DRAW`,
  `_TXTA-HANDLE`, `TXTA-CURSOR-LINE`, and `TXTA-CURSOR-COL` set it
  at entry.
- **KDOS CMOVE note.** Uses `CMOVE ( src dst u -- )` with non-standard
  argument order per KDOS convention.
- **KDOS FREE note.** `TXTA-FREE` uses `FREE` without `DROP` (KDOS
  FREE is `( addr -- )`, not standard `( addr -- ior )`).
- **On-change callback.** `_TXTA-FIRE-CHANGE` is called at the end
  of `_TXTA-INSERT`, `_TXTA-DELETE`, and `_TXTA-BACKSPACE`. The
  callback receives the widget pointer: `( widget -- )`. It is safe
  to not set a callback (xt = 0 means no call).
- **Word movement.** `_TXTA-WORD-LEFT` and `_TXTA-WORD-RIGHT` use a
  two-phase skip: first skip non-word characters, then skip word
  characters (or vice-versa). Word characters are `a-z`, `A-Z`,
  `0-9`, and `_`.
- **Page movement.** Page Up/Down move by the widget region height
  (`WDG-REGION RGN-H`) lines, clamped to the document bounds.

## See Also

- [input.md](input.md) — Single-line input widget (same buffer model)
- [widget.md](../widget.md) — Base widget header and protocol
- [uidl-tui.md](../uidl-tui.md) — UIDL-TUI backend integration
