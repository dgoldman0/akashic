# akashic-text-row — One Row of Text on the Cell Grid

Lays out one row of UTF-8 text the way the shared text contract
([`docs/rich-terminal/APT-1-TEXT.md`](../rich-terminal/APT-1-TEXT.md)
Sections 3 to 9) describes, and maps between logical positions and cells.

```forth
REQUIRE text/text-row.f
```

`PROVIDED akashic-text-row` — safe to include multiple times.

---

## What a layout holds

`TROW-LAYOUT ( addr u flags direction row -- ok? )` reads the row once:

- it decodes UTF-8 with Section 5 replacement (`TROW-F-TAB` keeps a tab
  as a blank one-cell character);
- it splits the text into characters and measures each one;
- when any scalar is `R`, `AL`, `AN`, `RLE`, `RLO`, `RLI`, or `FSI`, or
  the direction is `BIDI-RTL`, it resolves bidi levels, mirrors glyphs at
  odd levels, and gives Arabic letters their joined presentation forms;
- it orders the visible characters left to right and assigns columns.

`TROW-F-UNTRUSTED` treats explicit embeddings, overrides, and isolates as
boundary neutrals, so network or document text can only use implicit
bidi and cannot visually reorder its surroundings.

Each character has a record:

| Field | Meaning |
|-------|---------|
| `TROW.START` | First scalar offset in the logical row |
| `TROW.SCALARS` | Number of scalars |
| `TROW.BYTE` `TROW.BYTES` | Byte offset and length in the source |
| `TROW.WIDTH` | 0, 1, or 2 cells |
| `TROW.LEVEL` | Resolved level of its first kept scalar |
| `TROW.COLUMN` | First cell, counted from the row's left edge |
| `TROW.CP0` | Displayed first scalar, after mirroring and joining |

`TROW-CHAR` walks every character in logical order, including those of
width 0; `TROW-VCHAR` walks the visible ones left to right.
`TROW-DISPLAY` writes a character's display scalars (the displayed first
scalar, then the rest in logical order) as 32-bit values.

## Mapping

| Word | Meaning |
|------|---------|
| `TROW-AT-COLUMN ( column row -- rec \| 0 )` | The visible character covering a column |
| `TROW-POSITION-AT ( column row -- offset )` | Section 9.1: the start of the character under the column; past the content, the row's end on the paragraph's end side and its start on the other |
| `TROW-CARET ( offset row -- rec \| 0 )` | Section 9.2: the visible character a caret at `offset` belongs to, or 0 at the row's end |
| `TROW-CARET-COLUMN ( offset row -- column )` | Section 9.2: the column where that caret shows, its character's lead cell, or at the row's end just past the content on the end side: the width for LTR, -1 for RTL |
| `TROW-OFFSET>BYTE` `TROW-BYTE>OFFSET` | Convert between scalar offsets and byte offsets |

Columns count from the row's left edge.  A caller that mirrors a
right-to-left row, as a text area does, converts its own coordinates
before and after.

## Storage

A row object is `TROW-SIZE` bytes of caller storage; `TROW-INIT` clears
it and `TROW-FREE` releases its buffer.  The buffer comes from the heap
and grows to the longest row laid out in it, about 66 bytes per source
byte plus the bidi stacks; `TROW-LAYOUT` returns false only when it
cannot grow.  There is no fixed row length.

## Cost

Measured by `local_testing/test_text_row.py`, in guest steps per scalar:
about 1,200 for printable ASCII (the byte path, no table lookups), 10,000
for CJK text (no bidi), and 21,000 for Hebrew (with bidi).  Drawing and
editors lay out only rows that are not plain ASCII.

## Tests

`local_testing/test_text_row.py` lays out twenty mixed rows (CJK, combining
accents, emoji sequences and flags, Hebrew, Arabic with joining and
non-joiners, digits and brackets in right-to-left text, tabs, explicit
controls, and forced directions) and compares every visible character
with MegaPad's independent `rich_terminal/text_rules.py` layout.  It also
checks untrusted text, positions, carets, and offset conversion.

## Concurrency

Layout keeps its scratch state in module variables, so the public words
take the module guard in `GUARDED` builds.  Separate row objects never
share storage.
