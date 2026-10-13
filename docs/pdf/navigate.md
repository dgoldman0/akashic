# akashic-pdf-navigate — a PDF's destinations, links and outline

Where a PDF lets its reader go: the destinations that name a place in the
document (PDF 32000-1, section 12.3.2), a page's links (12.5.6.5), and the
document's outline (12.3.3), the table of contents a reader shows beside
it. A reader shows a page's links and the outline, and follows one when it
is chosen.

```forth
REQUIRE pdf/navigate.f
```

`PROVIDED akashic-pdf-navigate`. It depends on `pdf/lexer.f`,
`pdf/filter.f`, `pdf/file.f`, `pdf/page.f`, `pdf/tree.f` and
`pdf/textstr.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-DEST` | `( va vu type file -- num left top status )` | Where a destination goes: the page object's number, and the left and top it shows. |
| `PDF-LINKS-SIZE` | `( -- 56 )` | A page's links' record, zeroed before first use. |
| `PDF-LINKS-READ` | `( page links -- status )` | Read an open page's links. |
| `PDF-LINKS-FREE` | `( links -- )` | Give back what it read; the record is zeroed. |
| `PDF-LINKS-COUNT` | `( links -- n )` | How many links it holds. |
| `PDF-LINK` | `( i links -- link )` | Link `i`, from 0. |
| `PDF-LINK-RECT` | `( link -- x0 y0 x1 y1 )` | Where on the page it is, in default space, 16.16, its corners ordered. |
| `PDF-LINK-DEST` | `( link links -- va vu type )` | Its destination's value, or `0 0 PDF-T-END` for a link to the web. |
| `PDF-LINK-URI` | `( link links -- a u )` | Its address's bytes, or `0 0` for a link within the document. |
| `PDF-OUTLINE-SIZE` | `( -- 56 )` | An outline's record, zeroed before first use. |
| `PDF-OUTLINE-READ` | `( file outline -- status )` | Read the document's outline. |
| `PDF-OUTLINE-FREE` | `( outline -- )` | Give back what it read; the record is zeroed. |
| `PDF-OUTLINE-COUNT` | `( outline -- n )` | How many items it holds. |
| `PDF-OUTLINE-ITEM` | `( i outline -- item )` | Item `i`, from 0. |
| `PDF-ITEM-LEVEL` | `( item -- level )` | Its depth, from 0 at the top. |
| `PDF-ITEM-TITLE` | `( item outline -- a u )` | Its title, as UTF-8. |
| `PDF-ITEM-DEST` | `( item outline -- va vu type )` | Its destination's value, or `0 0 PDF-T-END`. |
| `PDF-ITEM-URI` | `( item outline -- a u )` | Its address's bytes, or `0 0`. |
| `PDF-ITEM-CLOSED?` | `( item -- flag )` | Whether it starts closed, its children hidden. |

Statuses are `pdf/filter.f`'s and `pdf/file.f`'s: `PDF-S-OK`,
`PDF-S-MEMORY` when memory is refused, `PDF-S-LOCKED` for a locked file,
whose strings cannot be read, and, from `PDF-DEST`, `PDF-S-MISSING` for a
destination that names no page.

## Destinations

A destination is a value, followed through references:

- an array that names a page by its object: `[page /XYZ left top zoom]`,
  `/FitH` or `/FitBH` with a top, `/FitR left bottom right top`, or another
  fit;
- a name, which the catalog's `/Dests` maps to one;
- a string, which the catalog's `/Names /Dests` name tree maps to one;
- or, as a value those map to, a dictionary whose `/D` is one.

Writers mix names and strings up, so a name not in `/Dests` is looked for in
the name tree too, and a string not in the tree in `/Dests`. A name's
`#xx` codes are read before it is looked up.

`PDF-DEST` gives the page object's number, and the left and the top the
destination shows in default space, 16.16: the left for `/XYZ` and `/FitR`,
the top for `/XYZ`, `/FitH`, `/FitBH` and `/FitR`, each -1 when it gives
none, as `null` does. `PDF-PAGE-INDEX` in
`pdf/page.f` turns the page object into the page's index, and says when
the object is no page of the document.

## Links

`PDF-LINKS-READ` reads the open page's `/Annots` and keeps each link
annotation that goes somewhere a reader can follow:

- to a destination, through `/Dest` or a GoTo action's `/D`;
- to the web, through a URI action's `/URI`.

A link to a destination keeps the destination's value as it is, its bytes
copied, for `PDF-DEST` to read when the link is followed. A page of a
hyperref document links every reference and citation through the name
tree, so the page is read without one lookup. A link to the web keeps its
address's bytes. Other links, such as one that launches a program, and
annotations that are not links, are left out.

## The outline

`PDF-OUTLINE-READ` reads the catalog's `/Outlines` in the order a reader
shows it, each item's children after it, through `/First` and `/Next`. Each
item has its level, its title as UTF-8 (`pdf/textstr.f`), where it goes,
as a link does, or nowhere: an item may only group the items below it;
and whether it starts closed, which a negative `/Count` says. A positive
`/Count`, or none, leaves it open, as viewers read it. The walk keeps a bit for each of the file's objects and reads each item
once, so an outline that loops ends.

## What it gives back

A destination's value, an address and a title are spans of the record,
valid until it is read again or given back with `PDF-LINKS-FREE` or
`PDF-OUTLINE-FREE`. What cannot be read is left out: a link or an item that
cannot be, an outline or name tree that is damaged. Memory refused fails a
read with `PDF-S-MEMORY`.

## Cost

In a three-page xelatex document with hyperref, whose objects all lie in
one object stream of 53, reading the outline of five items takes about
218,000 steps once the object stream is decoded, and the first page's
seven links about 329,000, most of it reading each annotation's
dictionary. Following a named destination takes 84,000 to 118,000, and
its page index 39,000 to 71,000.

Memory comes from the file's memory source. One call runs at a time.
