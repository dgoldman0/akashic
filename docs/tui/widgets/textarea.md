# akashic/tui/widgets/textarea.f — Multi-line Text Area Widget

**Layer:** 4B  
**Prefix:** `TXTA-` (public), `_TXTA-` (internal)  
**Provider:** `akashic-tui-textarea`  
**Dependencies:** `widget.f`, `draw.f`, `semantic-collections.f`,
`style-palette.f`, `keys.f`, `utf8.f`, `grapheme.f`, `text-row.f`,
`text-style.f`, `gap-buf.f`, `undo.f`, `cell-width.f`

## Overview

A multi-line text editor widget with vertical scrolling, cursor
movement (left/right/up/down/home/end/page-up/page-down), word-level
movement (Ctrl+Left / Ctrl+Right), text insertion, deletion
(backspace and forward-delete), Enter for newline insertion, and an
on-change callback that fires after every edit operation.

The widget can use a caller-provided flat byte buffer or a bound canonical gap
buffer. In either mode `0x0A` is the line separator and the same ordinary draw,
cursor, selection, scroll, and input state is authoritative.

## Characters and Cells

Text follows the shared text rules (`docs/rich-terminal/APT-1-TEXT.md`,
through [text-row](../../text/text-row.md)). A character is a grapheme
cluster: an accent built from a combining mark, an emoji sequence, or a flag
is one character. The caret moves over whole characters, and Backspace and
Delete remove whole characters. An edit that joins the characters on both
sides of the caret, as a base typed before a lone combining mark does, leaves
the caret on the joined character's boundary.

Each line is one bidi paragraph of automatic direction. Its characters take
their widths in cells, in visual order: a wide character takes two cells, and
right-to-left runs are reordered, mirrored, and joined. A left-to-right line
starts at the text viewport's left edge; a right-to-left line is mirrored and
starts at its right edge. The horizontal scroll moves each line away from its
own start edge, and the line is clipped to the text viewport, never drawing
into the gutter. A line of printable ASCII needs no layout.

The focused caret marks its character in reverse video, both cells of a wide
one, or at a line's end a reversed blank just past the content on the end
side: right of a left-to-right line, left of a right-to-left one. A selection
marks whole characters. A click on a character names its start; past the
content, the end side names the line's end and the start side its start.

## Styles and Links

An optional style source says what each part of a line means. It has the
shape `( line-a line-u map -- )` and fills `map[0..line-u)` with one meaning
per byte from [text-style](../../text/text-style.md), 0 for plain text; the
scanners of [syntax](../../text/syntax.md) have that shape. A character takes
the meaning of its first byte. Lines are styled only as they are drawn,
published, or clicked, so a text area without a style source pays nothing.

CELL draws each meaning in the look the widget's palette
([style-palette](../style-palette.md)) gives it: the meaning's colour, with
its attributes added to the drawing style's. Plain text keeps the drawing
style, and a selection or caret adds reverse video on top of a look. Each
line is drawn in one call, whether it is printable ASCII or laid out.

The published `TEXT_AREA` entry carries each carried row's style runs,
counted in Unicode scalars, from the same style source, so CELL and a rich
renderer show the same meanings.

Ctrl and a primary press on a character a link covers follows the link
instead of placing the caret, as does a renderer's `KEY-MOUSE-TEXT-FOLLOW`
at a link. The widget calls its follow word with the link's line, the byte
offset of the press in that line, and the widget. The follow word looks up
the target and decides what happens; the line stays valid only until it
calls another textarea word, so it copies what it needs first. A plain press
on a link places the caret, so the link's text can still be edited.

## Descriptor Layout (168 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=`WDG-T-TEXTAREA` |
| +40 | buf-a | address | Pointer to text buffer |
| +48 | buf-cap | u | Buffer capacity in bytes |
| +56 | buf-len | u | Current text length in bytes |
| +64 | cursor | u | Cursor position (byte offset into buffer) |
| +72 | scroll-y | u | Vertical scroll offset (line index of first visible row) |
| +80 | on-change | xt | Change callback xt (0 = none); `( widget -- )` |
| +88 | selection anchor | i | Byte offset, or -1 when absent |
| +96 | gap buffer | address | Bound `GB` handle, or 0 for flat mode |
| +104 | undo state | address | Bound undo handle, or 0 |
| +112 | style source | xt | Marks what each byte of a line means, or 0 |
| +120 | gutter hook | xt | Optional gutter-paint hook |
| +128 | gutter width | u | Columns reserved before editor content |
| +136 | scroll-x | u | Horizontal scroll in cells, from each line's start edge |
| +144 | instance | u | Nonzero process-lifetime identity for this widget allocation |
| +152 | palette | address | CELL look of each meaning, or 0 for `SPAL-DEFAULT` |
| +160 | follow word | xt | Follows a link, or 0 |

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
| `TXTA-GET-TEXT` | `( widget -- addr len )` | Allocate a contiguous text snapshot; caller must `FREE` `addr` |
| `TXTA-CLEAR` | `( widget -- )` | Clear buffer, reset cursor and scroll |

### Cursor and Identity Queries

| Word | Stack | Description |
|------|-------|-------------|
| `TXTA-CURSOR-LINE` | `( widget -- n )` | 0-based line number of cursor position |
| `TXTA-CURSOR-COL` | `( widget -- n )` | Characters before the caret on its line |
| `TXTA-CURSOR-CELL` | `( widget -- n )` | Cells from the caret line's start edge to the caret |
| `TXTA-CURSOR-X` | `( widget -- x )` | The caret's column in the text viewport after the gutter, scrolled |
| `TXTA-INSTANCE@` | `( widget -- token )` | Stable, nonpointer identity for this allocation's lifetime; not a document or renderer key |

### Callbacks, Styles, and Links

| Word | Stack | Description |
|------|-------|-------------|
| `TXTA-ON-CHANGE` | `( xt widget -- )` | Set on-change callback; `( widget -- )` |
| `TXTA-STYLE!` | `( xt widget -- )` | Set the style source `( line-a line-u map -- )`, or 0 |
| `TXTA-PALETTE!` | `( palette widget -- )` | Set the CELL palette, or 0 for the default |
| `TXTA-ON-FOLLOW!` | `( xt widget -- )` | Set the follow word `( line-a line-u pos widget -- )`, or 0 |

### Renderer-neutral text-area observation

| Word | Stack | Description |
|------|-------|-------------|
| `TXTA-TEXT-AREA-MEASURE` | `( root-key builder widget -- bytes status )` | Exact measure of one native `TEXT_AREA` entry |
| `TXTA-TEXT-AREA-CAPTURE` | `( root-key dst cap builder widget -- bytes status )` | Copy one exact pointer-free entry into caller storage |
| `TXTA-TEXT-AREA-STORAGE-DISJOINT?` | `( address bytes widget -- flag )` | Check caller storage against the complete live textarea source graph |

Both words run the same allocation-free build path. The root is local to the
widget region: row 0, the gutter column, region height, and region width minus
the gutter. The upper lifecycle owner supplies attachment identity and later
translates/clips that local root into its selected retained region.

The entry carries the logical viewport rows plus any off-viewport caret or
selection-anchor row. Line keys are stable coordinate keys `line + 1`. Each
row is published as CELL shows it (`UTF8-SAFE-COPY` in
[utf8](../../text/utf8.md)): bytes that are not UTF-8,
C0 controls other than TAB, and DEL become U+FFFD, one for each unit
`UTF8-DECODE` reads, so a file that is not text, such as a binary file Pad
opens, still publishes a valid row. Cursor and anchor offsets count those
published scalars; a position inside a well-formed character is refused.
Columns count cells: the widest line's width, or the scrolled viewport's right
edge when that is further. Flat lines are read in place and gap-buffer lines
through one line copy, with no 1,024-byte scratch limit or whole-document
flatten. The caller still performs the one deep collection validation before
freezing or publication.

Before either measure or copy, the producer validates the widget and region,
the flat buffer or complete gap-buffer descriptor/backing spans, its own
module scratch, and—when gap-backed—the lower gap-buffer module's complete
shared scratch span. Gap-buffer line count and packed line starts are then
correlated with the logical byte scan: line zero starts at zero, every later
start strictly increases within content and immediately follows an LF, and the
indexed count equals the actual row count. No `GB-LINE-*` or position query
consumes the index before this proof. Invalid, wrapping, unaligned, stale, or
aliased source graphs fail closed.

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Printable char | Insert at cursor |
| Backspace / Ctrl-H | Delete the character before the cursor |
| Delete | Delete the character at the cursor |
| Left / Right | Move the cursor one character in logical order |
| Up / Down | Move to the adjacent line, keeping the caret's viewport column |
| Home | Move cursor to start of line |
| End | Move cursor to end of line |
| Enter / CR | Insert newline (`0x0A`) |
| Page Up | Move up by viewport-height lines (clamp to top), keeping the viewport column |
| Page Down | Move down by viewport-height lines (clamp to last line), keeping the viewport column |
| Ctrl+Left | Move cursor left to start of previous word |
| Ctrl+Right | Move cursor right to end of next word |

### Pointer Handling (via `WDG-HANDLE`)

A pointer cell maps back through the default layout, one logical line per
row laid out as [Characters and Cells](#characters-and-cells) says. A cell in
the gutter means the text viewport's first column; a cell above or below the
viewport, reached by a drag, clamps to its first or last row.

| Event | Action |
|-------|--------|
| Primary press | Place the caret and clear the selection |
| Shift + primary press | Move the caret, keeping or starting the selection anchor |
| Ctrl + primary press on a link | Follow the link; elsewhere, place the caret |
| Drag | Extend the selection to the cell |
| Release | Drop a selection that ended empty |
| Wheel | Scroll three lines; a caret the view leaves moves to the nearest visible line, keeping its viewport column |
| `KEY-MOUSE-TEXT-PLACE` | Place the caret at `KEY-MOUSE-TEXT-KEY` (line + 1) and `KEY-MOUSE-TEXT-OFFSET` |
| `KEY-MOUSE-TEXT-EXTEND` | Extend the selection to that text position |
| `KEY-MOUSE-TEXT-FOLLOW` | Follow the link at that text position, if one is still there |

The three text codes carry a position that a rich renderer took from its own
layout, so they need no cell mapping. They clamp to the current text, and an
offset inside a character names that character's start.

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_TXTA-CURSOR-LINE` | `( -- n )` | Line index (0-based) of cursor position |
| `_TXTA-LINE-COUNT` | `( -- n )` | Total number of lines in the buffer |
| `_TXTA-SOL` | `( line -- off )` | Start-of-line byte offset for line N |
| `_TXTA-EOL` | `( line -- off )` | End-of-line byte offset for line N |
| `_TXTA-LINE-OFF` | `( line -- off len )` | Start offset and length of line N |
| `_TXTA-CURSOR-COL` | `( -- n )` | Scalars before the cursor on its line |
| `_TXTA-COL-OFF` | `( line-off scalars -- off )` | Byte offset that many scalars into a line |
| `_TXTA-L-PREP` | `( line -- ok? )` | Take a line's text and lay it out unless it is printable ASCII |
| `_TXTA-L-CARET-V` | `( byte-off -- v )` | Visual column where the caret shows (APT-1-TEXT 9.2) |
| `_TXTA-L-V>BYTE` | `( v -- byte-off )` | Position a visual column names (APT-1-TEXT 9.1) |
| `_TXTA-L-ORIGIN` | `( -- x )` | Text viewport column of the prepared line's visual column 0 |
| `_TXTA-PREV-CHAR` / `_TXTA-NEXT-CHAR` | `( -- off )` | Character boundary before or after the cursor |
| `_TXTA-SNAP` | `( off forward? -- off' )` | Move an offset inside a character to its end or start |
| `_TXTA-VERT` | `( line -- off )` | Position on a line under the caret's viewport column |
| `_TXTA-INSERT` | `( cp -- )` | Insert codepoint at cursor, shift tail |
| `_TXTA-DELETE` | `( -- )` | Forward-delete at cursor |
| `_TXTA-BACKSPACE` | `( -- )` | Delete before cursor |
| `_TXTA-LEFT` | `( -- )` | Move cursor back one character |
| `_TXTA-RIGHT` | `( -- )` | Move cursor forward one character |
| `_TXTA-HOME` | `( -- )` | Move cursor to start of current line |
| `_TXTA-END` | `( -- )` | Move cursor to end of current line |
| `_TXTA-UP` | `( -- )` | Move cursor to the previous line, keeping its viewport column |
| `_TXTA-DOWN` | `( -- )` | Move cursor to the next line, keeping its viewport column |
| `_TXTA-PGUP` | `( -- )` | Move cursor up by viewport-height lines |
| `_TXTA-PGDN` | `( -- )` | Move cursor down by viewport-height lines |
| `_TXTA-IS-WORD-CHAR` | `( byte -- flag )` | True if byte is alphanumeric or underscore |
| `_TXTA-WORD-LEFT` | `( -- )` | Move cursor to start of previous word |
| `_TXTA-WORD-RIGHT` | `( -- )` | Move cursor past end of next word |
| `_TXTA-FIRE-CHANGE` | `( -- )` | Invoke on-change callback if set |
| `_TXTA-SCROLL-ADJ` | `( -- )` | Scroll so the caret's line and cell are visible |
| `_TXTA-DRAW-LINE` | `( row -- )` | Draw one visible line at terminal row |
| `_TXTA-L-STYLE` | `( -- )` | Style the prepared line through the style source |
| `_TXTA-LINK?` | `( off -- flag )` | Whether a link covers the character at an offset |
| `_TXTA-FOLLOW` | `( off -- followed? )` | Follow the link at an offset through the follow word |
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
- **Characters, not bytes.** The caret stays on character boundaries,
  and widths and columns count cells. If a line cannot be laid out for
  lack of memory, movement falls back to scalar boundaries.
- **Vertical scroll.** `_TXTA-SCROLL-ADJ` ensures the cursor's line
  is within the visible region. The scroll offset is a line index.
- **Line splitting.** Lines are separated by `0x0A` bytes. Flat mode scans
  sequentially; gap-buffer mode uses its maintained line index.
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
