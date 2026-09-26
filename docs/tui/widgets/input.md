# akashic/tui/widgets/input.f — Text Input Widget

**Layer:** 4B  
**Lines:** 670  
**Prefix:** `INP-` (public), `_INP-` (internal)  
**Provider:** `akashic-tui-input`  
**Dependencies:** `widget.f`, `draw.f`, `keys.f`

## Overview

A single-line text input field with cursor movement, a selection,
insertion, deletion (backspace and forward-delete), horizontal
scrolling, and an optional placeholder shown when the buffer is empty.

The input widget stores text in a caller-provided fixed-size buffer.
Insertion is rejected when the buffer is full.

## Descriptor Layout (128 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=WDG-T-INPUT |
| +40 | buf-a | address | Pointer to text buffer |
| +48 | buf-cap | u | Buffer capacity in bytes |
| +56 | buf-len | u | Current text length in bytes |
| +64 | cursor | u | Cursor position (byte offset) |
| +72 | scroll | u | Scroll offset (codepoints) |
| +80 | placeholder-a | address | Placeholder text address |
| +88 | placeholder-u | u | Placeholder text length |
| +96 | submit-xt | xt | Enter callback |
| +104 | mask-cp | codepoint | Render replacement; zero means plain text |
| +112 | anchor | offset | Selection anchor byte offset; -1 means none |
| +120 | pressed | flag | A primary press made in this field is held |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `INP-NEW` | `( rgn buf-a buf-cap -- widget )` | Allocate + init; empty, cursor at 0 |
| `INP-FREE` | `( widget -- )` | Free the descriptor (not the buffer) |

### Content

| Word | Stack | Description |
|------|-------|-------------|
| `INP-SET-TEXT` | `( text-a text-u widget -- )` | Set text; clamps to capacity; cursor at end; no selection |
| `INP-GET-TEXT` | `( widget -- addr len )` | Get buffer address and current length |
| `INP-CLEAR` | `( widget -- )` | Clear buffer, reset cursor, scroll, and selection |
| `INP-WIPE` | `( widget -- )` | Zero the full caller-owned buffer, then clear |
| `INP-MASK!` | `( codepoint widget -- )` | Set a render-only replacement; zero disables masking |
| `INP-SET-PLACEHOLDER` | `( text-a text-u widget -- )` | Set placeholder text; marks dirty |

### Cursor

| Word | Stack | Description |
|------|-------|-------------|
| `INP-CURSOR-POS` | `( widget -- n )` | Get cursor column (codepoint count, not byte offset) |

### Callback

| Word | Stack | Description |
|------|-------|-------------|
| `INP-ON-SUBMIT` | `( xt widget -- )` | Set submit callback (Enter key); `( widget -- )` |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Printable char | Insert at cursor, replacing the selection |
| Backspace | Delete the selection, or the codepoint before the cursor |
| Delete | Delete the selection, or the codepoint at the cursor |
| Left / Right | Move cursor one codepoint |
| Home | Move cursor to start |
| End | Move cursor to end |
| Shift with Left, Right, Home, or End | Extend the selection |
| Ctrl+A | Select all |
| Enter | Fire submit callback |

A movement key without Shift drops the selection. Any other Ctrl or Alt
combination is not consumed, so it reaches the application's shortcuts
instead of inserting its letter. Keys the field does not handle are not
consumed either.

### Selection

The selection runs between the anchor and the cursor, and exists only while
they differ. Selected codepoints draw in reverse video. The caret is not
drawn while a selection shows, since beside it the caret would look like one
more selected character.

### Pointer Handling (via `WDG-HANDLE`)

A primary press inside the field places the caret at the codepoint drawn
under it, counting from the scroll offset, or at the end of the text when
the press is past it. With Shift the press extends the selection instead.
While that press is held, a drag extends the selection to the pointer's
column, wherever the pointer is. A column past either edge names one
codepoint beyond the visible text, so each drag step out there scrolls the
field one column. The release of that press ends the drag.

Presses outside the field, other buttons, the wheel, and drags or releases
without a press made in this field are not consumed.

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_INP-SEL?` | `( widget -- flag )` | Is a selection showing? |
| `_INP-SEL-RANGE` | `( widget -- start end )` | Ordered selection byte offsets |
| `_INP-DEL-SEL` | `( widget -- deleted? )` | Delete the selection, caret at its start |
| `_INP-INSERT` | `( cp widget -- )` | Insert codepoint at cursor, replacing the selection |
| `_INP-DELETE` | `( widget -- )` | Forward delete at cursor, or delete the selection |
| `_INP-BACKSPACE` | `( widget -- )` | Delete before cursor, or delete the selection |
| `_INP-LEFT` | `( widget -- )` | Move cursor left one codepoint |
| `_INP-RIGHT` | `( widget -- )` | Move cursor right one codepoint |
| `_INP-HOME` | `( widget -- )` | Move cursor to byte 0 |
| `_INP-END` | `( widget -- )` | Move cursor to end of text |
| `_INP-MOVE` | `( event widget xt -- )` | Run a move under the Shift selection rule |
| `_INP-SCROLL-ADJ` | `( widget -- )` | Ensure cursor is visible |
| `_INP-DRAW` | `( widget -- )` | Draw visible text or placeholder |
| `_INP-POINTER` | `( event widget -- consumed? )` | Press, drag, and release |
| `_INP-HANDLE` | `( event widget -- consumed? )` | Key and pointer dispatch |

## UIDL-TUI Integration

When a UIDL `<input>` element is materialized by the UIDL-TUI
backend (`uidl-tui.f`), the following happens:

1. **Materialization** (`_UTUI-MAT-INPUT`): Allocates a 256-byte
   buffer; calls `INP-NEW`; sets initial text from `text=` and
   placeholder from `placeholder=` attributes; stores the widget
   pointer in the element's sidecar `wptr` cell.

2. **Render** (`_UTUI-RENDER-INPUT`): Syncs the proxy region from
   `_UR-*` layout vars, propagates focus state from sidecar to
   widget flags, delegates to `_INP-DRAW`.

3. **Events** (`_UTUI-H-INPUT`): Syncs proxy region and focus
   from sidecar, delegates to `_INP-HANDLE`.

4. **Dematerialization**: Frees the buffer (read from widget+40),
   then frees the widget descriptor via `INP-FREE`.

## Design Notes

- **Buffer is caller-owned.** The descriptor stores a pointer to the
  caller's buffer. The caller must keep the buffer alive. When used
  through UIDL-TUI, both are freed during dematerialization.
- **UTF-8 aware.** Cursor movement, insertion, and deletion operate
  on codepoint boundaries using `_UTF8-SEQLEN` and `_INP-PREV-CP`.
- **Untrusted-text display.** Plain input retains the caller-owned bytes but
  projects each decoded codepoint through `CW-CELL-CP`. Terminal/bidi
  controls, width-0 combining/joining/format codepoints, and width-2 glyphs
  paint as one U+FFFD cell. This also applies to the character under the cursor,
  mask codepoints, and placeholders; it does not normalize submitted text.
- **Horizontal scroll.** When the cursor moves past the visible
  region width, `_INP-SCROLL-ADJ` shifts the scroll offset so the
  cursor remains visible.
- **Masking is render-only.** Editing and UTF-8 cursor movement continue to
  operate on the caller-owned bytes, while drawing emits one configured mask
  codepoint per input codepoint. Callers handling secrets must still invoke
  `INP-WIPE` after synchronous consumption.
- **KDOS CMOVE note.** Uses `CMOVE ( src dst u -- )` with non-standard
  argument order per KDOS convention.
- **KDOS FREE note.** `INP-FREE` uses `FREE` without `DROP` (KDOS FREE
  is `( addr -- )`, not standard `( addr -- ior )`).
