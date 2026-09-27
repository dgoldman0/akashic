# akashic/tui/widgets/input.f — Text Input Widget

**Layer:** 4B  
**Lines:** 714  
**Prefix:** `INP-` (public), `_INP-` (internal)  
**Provider:** `akashic-tui-input`  
**Dependencies:** `widget.f`, `draw.f`, `keys.f`, `utf8.f`, `grapheme.f`,
`text-row.f`, `cell-width.f`

## Overview

A single-line text input field with cursor movement, a selection,
insertion, deletion (backspace and forward-delete), horizontal
scrolling, and an optional placeholder shown when the buffer is empty.

The input widget stores text in a caller-provided fixed-size buffer.
Insertion is rejected when the buffer is full.

## Characters and Cells

The field's text is one bidi paragraph of automatic direction, laid out by
the shared text rules (`docs/rich-terminal/APT-1-TEXT.md`, through
[text-row](../../text/text-row.md)). A character is a grapheme cluster: an
accent built from a combining mark, an emoji sequence, or a flag is one
character. Characters take their widths in cells in visual order.
Left-to-right text starts at the field's left edge; right-to-left text is
mirrored and starts at its right edge, and the scroll moves the text away
from its start edge. Printable ASCII needs no layout.

The caret moves over whole characters, and Backspace and Delete remove whole
characters. An edit that joins the characters on both sides of the caret, as
a base typed before a lone combining mark does, leaves the caret on the
joined character's boundary. The field scrolls so the caret's character is
in view, both cells of a wide one.

A masked field shows one mask cell per character, left to right. A mask
that is not one cell wide shows as U+FFFD. If the text cannot be laid out
for lack of memory, the field shows one cell per character the same way,
with U+FFFD for anything but printable ASCII.

## Descriptor Layout (128 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=WDG-T-INPUT |
| +40 | buf-a | address | Pointer to text buffer |
| +48 | buf-cap | u | Buffer capacity in bytes |
| +56 | buf-len | u | Current text length in bytes |
| +64 | cursor | u | Cursor position (byte offset) |
| +72 | scroll | u | Scroll in cells, from the text's start edge |
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
| `INP-CURSOR-POS` | `( widget -- n )` | The characters before the caret |

### Callback

| Word | Stack | Description |
|------|-------|-------------|
| `INP-ON-SUBMIT` | `( xt widget -- )` | Set submit callback (Enter key); `( widget -- )` |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Printable char | Insert at cursor, replacing the selection |
| Backspace | Delete the selection, or the character before the cursor |
| Delete | Delete the selection, or the character at the cursor |
| Left / Right | Move cursor one character in logical order |
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
they differ. Selected characters draw in reverse video. A focused caret marks
its character in reverse video, both cells of a wide one, or at the end a
reversed blank just past the content on its end side. The caret is not drawn
while a selection shows, since beside it the caret would look like one more
selected character.

### Pointer Handling (via `WDG-HANDLE`)

A primary press inside the field places the caret at the start of the
character drawn under it. Past the text, the end side names its end and the
start side its start: right and left of left-to-right text, left and right
of right-to-left text (APT-1-TEXT Section 9.1). With Shift the press extends
the selection instead. While that press is held, a drag extends the
selection to the pointer's column, wherever the pointer is. A column past
either edge names the cell just beyond the view, so each drag step out there
scrolls the field. The release of that press ends the drag.

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
| `_INP-PREP` | `( widget -- )` | Take the field's text and lay it out |
| `_INP-CARET-V` | `( off -- v )` | Visual column where a caret shows (APT-1-TEXT 9.2) |
| `_INP-V>OFF` | `( v -- off )` | Position a visual column names (APT-1-TEXT 9.1) |
| `_INP-FIX` | `( forward? -- )` | Keep the caret on a character boundary after an edit |
| `_INP-LEFT` | `( widget -- )` | Move cursor back one character |
| `_INP-RIGHT` | `( widget -- )` | Move cursor forward one character |
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
