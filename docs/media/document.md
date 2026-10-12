# akashic-media-document — a document read as a view reaches it

```forth
REQUIRE media/document.f
```

A document is text read from top to bottom, with its structure: a sequence
of blocks (paragraphs, headings, code, rules, figures and the starts of
pages), each inside the quotes and list items around it. A reader finds the
blocks in a media source; `markup/markdown.f` is the first. Any application
can show a document, and any reader can make one.

Block and container kinds take the values of MegaPad's DOC1 body
(SEMANTIC-CONTENT-1), so a producer passes them to a rich terminal unchanged.

| Kind | Value | | Container | Value |
|---|---|---|---|---|
| `DOC-B-PARAGRAPH` | 1 | | `DOC-C-QUOTE` | 1 |
| `DOC-B-HEADING` | 2 | | `DOC-C-BULLET` | 2 |
| `DOC-B-CODE` | 3 | | `DOC-C-NUMBERED` | 3 |
| `DOC-B-RULE` | 4 | | | |
| `DOC-B-FIGURE` | 5 | | | |
| `DOC-B-PAGE` | 6 | | | |

A page's start, `DOC-B-PAGE`, marks where a page of a paged document such as
a PDF begins. Its text is the page's label, such as `iv` or `12`, laid out as
a paragraph's, and it sits in no container: `DOC-ADD-CONTAINER` refuses one.

## Two passes

`DOC-OPEN` runs the reader's structure pass once over the source. It keeps
each block's kind and heading level, the blank rows before it, how many of
its outermost containers those rows lie inside, and its containers: a quote,
or a list item with the cells its mark takes, a numbered item's number, and
whether this block starts the item. It keeps where the block's text lies,
but not the text.

`DOC-CONTENT` reads one block's text and meanings from the source when a
view reaches it, and keeps them until `DOC-KEEP` gives back the contents
outside the range the view still needs. A content holds the block's text,
one meaning a byte (`text/text-style.f`'s `TSTY-` values), its links, each a
byte range and a target, and for a figure the name of its picture. A
paragraph that turns out to be only a picture comes back as a figure.

## Parts

A reader may give a document in parts instead, such as a PDF with a part for
each page, so that a long document opens without reading every page. Its
structure pass adds parts, and no blocks, with `DOC-ADD-PART`; the document
then starts with no blocks. `DOC-READ-PART` runs the reader's part pass for
one part, which adds that part's blocks with `DOC-ADD-BLOCK` and
`DOC-ADD-CONTAINER`, and finds the part again with `DOC-PART-LOC@`.

Parts may be read in any order. A part's blocks go where the part lies:
after the blocks of the parts before it that are read, and before those of
the parts after it. A part not read has no blocks and takes no room. Block
indices count the blocks read, so reading a part moves the blocks after it
on, with their kept contents, and where the parts after it lie. A part read
already is left as it is. When the reader fails, or memory refuses, the part
stays unread and the document is as it was.

Each block gets a key, `BLK-KEY@`, when it is added, and keeps it while the
document is open, whatever is read around it; `DOC-KEY>INDEX` finds the
block again. A view publishes these keys as DOC1 block keys, which must stay
the same while the same document is shown.

Each block also knows its part, so `DOC-GAP ( index last? doc -- part | -1 )`
finds a part not read between blocks INDEX - 1 and INDEX without a search.
The parts between two neighbouring blocks are all unread or read and empty,
so it looks at none in most places. With `LAST?` it gives the last such part
(the one next to block INDEX), and otherwise the first; INDEX may be
`DOC-COUNT`, for the parts after the last block. A view stops at such a gap
and reads the part when it needs it (`tui/widgets/document.f`).

## Anchors

`DOC-ANCHOR ( name-a name-u doc -- index | -1 )` finds the heading a link
such as `#notes` names. A heading's anchor is its text in lower case, with
spaces made hyphens and other ASCII punctuation but hyphens and underscores
left out; a heading whose anchor an earlier one has takes `-1`, `-2` and so
on, as GitHub names them. The suffix is written without leading zeros.

## Memory

Every buffer comes from the caller's memory source
(`utils/memory-source.f`), each sized to what it holds and grown by doubling
as a reader fills it. When the source refuses, the call says `DOC-S-MEMORY`
and gives back what it took. A source that cannot be read gives
`DOC-S-READ`, and one that needs a password to be read, as an encrypted PDF
may, `DOC-S-LOCKED`. The document borrows its media source; whoever made the source
releases it after `DOC-CLOSE`, which gives back every byte.

## API

| Word | Stack | Meaning |
|---|---|---|
| `DOC-SIZE` | `( -- bytes )` | The record a document needs. |
| `DOC-OPEN` | `( source reader msrc doc -- status )` | Read the structure. |
| `DOC-CLOSE` | `( doc -- )` | Give everything back. |
| `DOC-COUNT` | `( doc -- blocks )` | How many blocks. |
| `DOC-BLOCK` | `( index doc -- block \| 0 )` | A block's record. |
| `DOC-CONTAINERS` | `( block doc -- first count )` | Its containers, outermost first, `CNT-SIZE` bytes apart. |
| `DOC-CONTENT` | `( index doc -- content status )` | A block's text, read once and kept. |
| `DOC-KEEP` | `( first end doc -- )` | Give back the contents outside blocks FIRST to END. |
| `DOC-KEPT` | `( index doc -- content \| 0 )` | The content of a block the document keeps, or 0; it never reads the source. |
| `DOC-STORAGE-DISJOINT?` | `( a u first end doc -- flag )` | Whether a span lies clear of the document's record, blocks, containers and content slots, and of the kept contents of blocks FIRST to END. |
| `DOC-ANCHOR` | `( name-a name-u doc -- index \| -1 )` | The heading a name points to. |
| `DOC-KEY>INDEX` | `( key doc -- index \| -1 )` | The block with a key, if read. |
| `DOC-PARTS` | `( doc -- n )` | How many parts; 0 for a document without parts. |
| `DOC-READ-PART` | `( part doc -- status )` | Read a part's blocks into place. |
| `DOC-PART-READ?` | `( part doc -- flag )` | Whether a part is read. |
| `DOC-PART-FIRST` | `( part doc -- index )` | Where its blocks lie, or will when it is read. |
| `DOC-PART-COUNT` | `( part doc -- blocks )` | Its blocks; 0 while it is not read. |
| `DOC-PART-OF` | `( index doc -- part \| -1 )` | The part a block lies in. |
| `DOC-GAP` | `( index last? doc -- part \| -1 )` | A part not read just before block INDEX. |

The part words take a part below `DOC-PARTS`.

A block's fields are `BLK-KEY@`, `BLK-KIND@`, `BLK-LEVEL@`,
`BLK-ROWS-BEFORE@` and `BLK-INSIDE@`; a container's `CNT-KIND@`, `CNT-WIDTH@`, `CNT-NUMBER@` and
`CNT-START?`; a content's `DCT-KIND@`, `DCT-LEVEL@`, `DCT-TEXT`, `DCT-MAP`,
`DCT-FIGURE`, `DCT-LINK-COUNT`, `DCT-LINK@ ( index content -- start end
target-a target-u )` and `DCT-LINK-AT ( offset content -- target-a target-u
| 0 0 )`.

## Readers

A reader is a record of four execution tokens, `RDR-SIZE` bytes:

| Field | Stack | Job |
|---|---|---|
| `RDR.STRUCTURE-XT` | `( doc -- status )` | Add every block with `DOC-ADD-BLOCK` and its containers with `DOC-ADD-CONTAINER`, or add parts with `DOC-ADD-PART`. |
| `RDR.CONTENT-XT` | `( index doc -- status )` | Fill the builder with `DOC-CB-TEXT`, `DOC-CB-LINK`, `DOC-CB-KIND` and `DOC-CB-FIGURE`. |
| `RDR.CLOSE-XT` | `( doc -- )` | Give back what the reader keeps, in `DOC-STATE@`. |
| `RDR.PART-XT` | `( part doc -- status )` | Add one part's blocks and their containers; 0 for a reader that adds no parts. |

A reader may keep one cell of its own with `DOC-STATE!`, two cells in each
block's record, `BLK-LOC@`, to find the block's text again, and two in each
part's, `DOC-PART-LOC@ ( part doc -- loc-a loc-b )`, to find the part.
`DOC-ADD-PART ( loc-a loc-b doc -- ok? )` refuses a part once the document
has blocks, and `DOC-ADD-BLOCK` refuses a block in a document with parts
outside its part pass, so a structure pass adds one or the other. A part pass
only adds its part's blocks: it does not read contents or other parts.
