# akashic-pdf-struct — a tagged page's marked content, by its structure

The structure a tagged PDF gives its page (PDF 32000-1, section 14.7): which
block each marked-content sequence's text belongs to, and what that block
is. The layout (`pdf/layout.f`) takes a tagged page's blocks from it.

```forth
REQUIRE pdf/struct.f
```

`PROVIDED akashic-pdf-struct`. It depends on `pdf/lexer.f`, `pdf/filter.f`,
`pdf/file.f`, `pdf/page.f`, `pdf/tree.f` and `media/document.f`, whose block
and container kinds it gives.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-STRUCT-SIZE` | `( -- 32 )` | A page structure's record, zeroed before first use. |
| `PDF-STRUCT-READ` | `( page struct -- status )` | Read an open page's structure. |
| `PDF-STRUCT-FREE` | `( struct -- )` | Give back what it read. |
| `PDF-STRUCT-BLOCK` | `( mcid struct -- id kind level item true \| false )` | The block an MCID's text belongs to, or false. |

`PDF-STRUCT-READ` gives `PDF-S-OK`, or `PDF-S-MEMORY` when memory is
refused. A page with no `/StructParents`, or a structure that cannot be
read, has no blocks, and the layout lays it out as an untagged page.

## What a block is

The page's `/StructParents` is its key in the structure tree's
`/ParentTree`, a number tree `pdf/tree.f` reads; its value lists each
MCID's element. From an element, the walk goes up past
inline elements (Span, Quote, Note, Reference, BibEntry, Link, Annot, Em,
Strong, Sub, Ruby and Warichu and their parts) to the block they sit in.
`PDF-STRUCT-BLOCK` then gives:

- `id`, the block element's object number, which every MCID of one block
  shares;
- `kind`: `DOC-B-HEADING` with its `level` for H1 to H6 (H is level 1),
  `DOC-B-CODE` for Code standing as a block, `DOC-B-PARAGRAPH` for any other
  block, or 0 for a list item's label (Lbl), whose `id` is its item's;
- `item`, the container around it: `DOC-C-BULLET` or `DOC-C-NUMBERED` inside
  a list item, as its list's `/ListNumbering` attribute says (None, Disc,
  Circle and Square are bullets, the rest number), `DOC-C-QUOTE` inside a
  BlockQuote, or 0. A grouping element (Document, Part, Art, Sect, Div,
  tables and the like) ends the search.

Code inside a paragraph is inline there. Types are read through the tree's
`/RoleMap`, which may map a name to another it maps onward, never more
times than it has names; names are read with their `#xx` codes, up to the
127 bytes a name may have. A paragraph keeps the layout's own judgement of
headings and code, since producers map their own heading and code styles to
P as often as not.

## Memory and cost

Each element is read once a page and kept until the page's structure is
read; a walk from one takes no more steps than the file has objects, so a
structure whose parents loop ends. The record keeps one entry of 32 bytes
an MCID. Memory comes from the page's file's memory source. One call runs
at a time.
