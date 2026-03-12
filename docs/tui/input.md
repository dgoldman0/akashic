# akashic/tui/input.f — Text Input Widget

**Layer:** 4B  
**Lines:** 485  
**Prefix:** `INP-` (public), `_INP-` (internal)  
**Provider:** `akashic-tui-input`  
**Dependencies:** `widget.f`, `draw.f`, `keys.f`

## Overview

A single-line text input field with cursor movement, insertion,
deletion (backspace and forward-delete), horizontal scrolling, and
an optional placeholder shown when the buffer is empty.

The input widget stores text in a caller-provided fixed-size buffer.
Insertion is rejected when the buffer is full.

## Descriptor Layout (96 bytes)

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

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `INP-NEW` | `( rgn buf-a buf-cap -- widget )` | Allocate + init; empty, cursor at 0 |
| `INP-FREE` | `( widget -- )` | Free the descriptor (not the buffer) |

### Content

| Word | Stack | Description |
|------|-------|-------------|
| `INP-SET-TEXT` | `( text-a text-u widget -- )` | Set text; clamps to capacity; cursor at end |
| `INP-GET-TEXT` | `( widget -- addr len )` | Get buffer address and current length |
| `INP-CLEAR` | `( widget -- )` | Clear buffer, reset cursor and scroll |
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
| Printable char | Insert at cursor |
| Backspace | Delete before cursor |
| Delete | Delete at cursor |
| Left / Right | Move cursor one codepoint |
| Home | Move cursor to start |
| End | Move cursor to end |
| Enter | Fire submit callback |

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_INP-INSERT` | `( cp widget -- )` | Insert codepoint at cursor |
| `_INP-DELETE` | `( widget -- )` | Forward delete at cursor |
| `_INP-BACKSPACE` | `( widget -- )` | Delete before cursor |
| `_INP-LEFT` | `( widget -- )` | Move cursor left one codepoint |
| `_INP-RIGHT` | `( widget -- )` | Move cursor right one codepoint |
| `_INP-HOME` | `( widget -- )` | Move cursor to byte 0 |
| `_INP-END` | `( widget -- )` | Move cursor to end of text |
| `_INP-SCROLL-ADJ` | `( widget -- )` | Ensure cursor is visible |
| `_INP-DRAW` | `( widget -- )` | Draw visible text or placeholder |
| `_INP-HANDLE` | `( event widget -- consumed? )` | Key dispatch |

## Design Notes

- **Buffer is caller-owned.** The descriptor stores a pointer to the
  caller's buffer. The caller must keep the buffer alive.
- **UTF-8 aware.** Cursor movement, insertion, and deletion operate
  on codepoint boundaries using `_UTF8-SEQLEN` and `_INP-PREV-CP`.
- **Horizontal scroll.** When the cursor moves past the visible
  region width, `_INP-SCROLL-ADJ` shifts the scroll offset so the
  cursor remains visible.
- **KDOS CMOVE note.** Uses `CMOVE ( src dst u -- )` with non-standard
  argument order per KDOS convention.
- **KDOS FREE note.** `INP-FREE` uses `FREE` without `DROP` (KDOS FREE
  is `( addr -- )`, not standard `( addr -- ior )`).
