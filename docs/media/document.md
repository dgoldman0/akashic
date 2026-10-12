# akashic-media-document — a document read as a view reaches it

```forth
REQUIRE media/document.f
```

A document is text read from top to bottom, with its structure: a sequence
of blocks (paragraphs, headings, code, rules, figures and the starts of
pages), each inside the quotes and list items around it. A reader finds the blocks in a media
source; `markup/markdown.f` is the first. Any application can show a
document, and any reader can make one.

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
`DOC-S-READ`. The document borrows its media source; whoever made the source
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

A block's fields are `BLK-KIND@`, `BLK-LEVEL@`, `BLK-ROWS-BEFORE@` and
`BLK-INSIDE@`; a container's `CNT-KIND@`, `CNT-WIDTH@`, `CNT-NUMBER@` and
`CNT-START?`; a content's `DCT-KIND@`, `DCT-LEVEL@`, `DCT-TEXT`, `DCT-MAP`,
`DCT-FIGURE`, `DCT-LINK-COUNT`, `DCT-LINK@ ( index content -- start end
target-a target-u )` and `DCT-LINK-AT ( offset content -- target-a target-u
| 0 0 )`.

## Readers

A reader is a record of three execution tokens, `RDR-SIZE` bytes:

| Field | Stack | Job |
|---|---|---|
| `RDR.STRUCTURE-XT` | `( doc -- status )` | Add every block with `DOC-ADD-BLOCK` and its containers with `DOC-ADD-CONTAINER`. |
| `RDR.CONTENT-XT` | `( index doc -- status )` | Fill the builder with `DOC-CB-TEXT`, `DOC-CB-LINK`, `DOC-CB-KIND` and `DOC-CB-FIGURE`. |
| `RDR.CLOSE-XT` | `( doc -- )` | Give back what the reader keeps, in `DOC-STATE@`. |

A reader may keep one cell of its own with `DOC-STATE!`, and two cells in
each block's record, `BLK-LOC@`, to find the block's text again.
