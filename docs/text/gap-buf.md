# akashic-gap-buf — Gap Buffer with Integrated Line Index

Efficient text-editing buffer.  Insert and delete at the cursor are
O(1) amortised; moving the cursor is O(distance).  A line-start
index is rebuilt after every mutation for fast line ↔ offset mapping.

```forth
REQUIRE text/gap-buf.f
```

`PROVIDED akashic-gap-buf` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Descriptor Layout](#descriptor-layout)
- [Constructor / Destructor](#constructor--destructor)
- [Cursor & Movement](#cursor--movement)
- [Insert](#insert)
- [Delete](#delete)
- [Bulk Operations](#bulk-operations)
- [Segment Access](#segment-access)
- [Line Queries](#line-queries)
- [Quick Reference](#quick-reference)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Gap buffer** | `[pre-content][gap][post-content]` — insert/delete at cursor = gap boundary manipulation. |
| **Auto-growing** | `ALLOCATE`/`RESIZE`-managed buffer; doubles on overflow. |
| **Integrated line index** | Array of line-start byte offsets rebuilt after every edit. |
| **UTF-8 aware** | `GB-INS-CP`, `GB-DEL-CP`, `GB-BS-CP` handle multi-byte codepoints. |
| **Prefix convention** | Public: `GB-`. Internal: `_GB-`. |

---

## Descriptor Layout

56 bytes (7 cells):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | `buf` | Byte buffer (`ALLOCATE`'d) |
| +8 | `cap` | Total buffer capacity |
| +16 | `gs` | Gap start = logical cursor position |
| +24 | `ge` | Gap end (exclusive) |
| +32 | `lidx` | Line-start offset array (`ALLOCATE`'d, cells) |
| +40 | `lcap` | Line index capacity (entries) |
| +48 | `lcnt` | Line count (always ≥ 1) |

Physical layout:

```
[content A][.....gap.....][content B]
^0         ^gs            ^ge        ^cap
```

Content length = `cap - (ge - gs)`.

---

## Constructor / Destructor

### GB-NEW

```
( cap -- gb )
```

Allocate a new gap buffer with initial capacity `cap` bytes.  The
buffer starts empty (gap spans the entire capacity).  Line index
starts with 1 line at offset 0.

### GB-FREE

```
( gb -- )
```

Free all three allocations (buffer, line index, descriptor).

```forth
4096 GB-NEW   ( gb )
\ ... use it ...
GB-FREE
```

---

## Cursor & Movement

### GB-CURSOR

```
( gb -- n )
```

Current cursor position (= gap start, a logical byte offset).

### GB-MOVE!

```
( pos gb -- )
```

Move the cursor to logical position `pos`.  Clamped to
`[0, GB-LEN]`.  Physically shifts bytes across the gap.

---

## Insert

### GB-INS

```
( addr u gb -- )
```

Insert `u` bytes at the cursor.  The gap grows automatically if
needed (buffer doubles in size).  Advances the cursor past the
inserted text.  Rebuilds the line index.

### GB-INS-CP

```
( cp gb -- )
```

Insert a single Unicode codepoint, UTF-8 encoded.  Uses
`UTF8-ENCODE` into a 4-byte scratch buffer then calls `GB-INS`.

```forth
4096 GB-NEW  ( gb )
S" Hello" OVER GB-INS
[CHAR] ! OVER GB-INS-CP
\ Content: "Hello!"
```

---

## Delete

### GB-DEL

```
( n gb -- del-addr del-u )
```

Delete `n` bytes forward from the cursor.  Returns a pointer to the
deleted bytes (valid until the next mutating call).  Clamped to
available bytes after cursor.

### GB-BS

```
( n gb -- del-addr del-u )
```

Delete `n` bytes backward from the cursor (backspace).  Returns a
pointer to deleted bytes.  Clamped to bytes before cursor.

### GB-DEL-CP

```
( gb -- del-addr del-u )
```

Delete one codepoint forward.  Uses the lead byte at `buf[ge]` to
determine the UTF-8 sequence length.

### GB-BS-CP

```
( gb -- del-addr del-u )
```

Delete one codepoint backward.  Scans back over continuation bytes
to find the codepoint start.

---

## Bulk Operations

### GB-SET

```
( addr u gb -- )
```

Replace all content.  Grows the buffer if `u` exceeds capacity.
Rebuilds the line index.

### GB-CLEAR

```
( gb -- )
```

Remove all content (reset to empty: `gs = 0`, `ge = cap`, 1 line).

### GB-FLATTEN

```
( dest gb -- u )
```

Copy all content to a contiguous destination buffer.  Returns the
content length.  Does not modify the gap buffer.

```forth
CREATE flat 8192 ALLOT
flat my-gb GB-FLATTEN   ( u )
\ flat now holds the full text
```

---

## Segment Access

### GB-PRE

```
( gb -- addr u )
```

Content before the gap (bytes `0` to `gs-1`).  Points into the
internal buffer — valid until the next mutating call.

### GB-POST

```
( gb -- addr u )
```

Content after the gap (bytes `ge` to `cap-1`).

### GB-BYTE@

```
( pos gb -- c )
```

Read the logical byte at position `pos`.  Transparent gap
translation: `pos < gs` reads `buf[pos]`; `pos >= gs` reads
`buf[pos + gap-size]`.

---

## Line Queries

### GB-LINES

```
( gb -- n )
```

Number of lines (always ≥ 1).  Newlines (`0x0A`) delimit lines.

### GB-LINE-OFF

```
( line# gb -- off )
```

Byte offset of the start of line `line#` (0-based).

### GB-LINE-LEN

```
( line# gb -- u )
```

Byte length of line `line#` excluding the trailing newline.

### GB-CURSOR-LINE

```
( gb -- line# )
```

Line number containing the cursor (0-based).  Uses binary search
over the line-start index — O(log n).

### GB-CURSOR-COL

```
( gb -- col )
```

Column of the cursor as a codepoint count from the start of its
line.  Walks codepoints from the line start to the cursor position.

```forth
my-gb GB-CURSOR-LINE   \ → 5  (6th line)
my-gb GB-CURSOR-COL    \ → 12 (13th codepoint)
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GB-NEW` | `( cap -- gb )` | Create gap buffer |
| `GB-FREE` | `( gb -- )` | Free gap buffer |
| `GB-LEN` | `( gb -- u )` | Content length |
| `GB-CURSOR` | `( gb -- n )` | Cursor position |
| `GB-BYTE@` | `( pos gb -- c )` | Logical byte access |
| `GB-MOVE!` | `( pos gb -- )` | Move cursor |
| `GB-INS` | `( addr u gb -- )` | Insert bytes |
| `GB-INS-CP` | `( cp gb -- )` | Insert codepoint |
| `GB-DEL` | `( n gb -- a u )` | Delete forward |
| `GB-BS` | `( n gb -- a u )` | Delete backward |
| `GB-DEL-CP` | `( gb -- a u )` | Delete 1 CP forward |
| `GB-BS-CP` | `( gb -- a u )` | Delete 1 CP backward |
| `GB-SET` | `( addr u gb -- )` | Replace all content |
| `GB-CLEAR` | `( gb -- )` | Clear all content |
| `GB-FLATTEN` | `( dest gb -- u )` | Copy to flat buffer |
| `GB-PRE` | `( gb -- addr u )` | Content before gap |
| `GB-POST` | `( gb -- addr u )` | Content after gap |
| `GB-LINES` | `( gb -- n )` | Line count |
| `GB-LINE-OFF` | `( line# gb -- off )` | Line start offset |
| `GB-LINE-LEN` | `( line# gb -- u )` | Line byte length |
| `GB-CURSOR-LINE` | `( gb -- line# )` | Cursor's line |
| `GB-CURSOR-COL` | `( gb -- col )` | Cursor's column |

---

## Dependencies

- `text/utf8.f` — `UTF8-ENCODE`, `UTF8-DECODE`, `_UTF8-SEQLEN`, `_UTF8-CONT?`

## Consumers

- `text/undo.f` — records edits against gap buffer
- `text/search.f` — searches over gap buffer content
- Akashic Pad — primary document buffer

## Internal State

Module-level `VARIABLE`s prefixed `_GB-`:

- `_GB-T` — current gap buffer handle (set by most public words)
- `_GB-D` — delta value for move / grow operations
- `_GB-BS-LO`, `_GB-BS-HI`, `_GB-BS-MID` — binary search cursors

Not reentrant without the `GUARDED` guard section.
