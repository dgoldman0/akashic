# akashic-pdf-page — a PDF's pages

A PDF's page tree (PDF 32000-1, section 7.7.3): how many pages it holds,
each page's dictionary with what it inherits from the nodes above it, and
its content streams decoded.

```forth
REQUIRE pdf/page.f
```

`PROVIDED akashic-pdf-page`. It depends on `pdf/lexer.f`, `pdf/filter.f`
and `pdf/file.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-PAGE-COUNT` | `( file -- n status )` | The pages the root node's `/Count` says the tree holds. |
| `PDF-PAGE-INDEX` | `( num file -- i status )` | The index, from 0, of the page whose object is `num`. |
| `PDF-PAGE-SIZE` | `( -- 256 )` | A page's record, eight-byte aligned, zeroed before first use. |
| `PDF-PAGE-OPEN` | `( i file page -- status )` | Page `i`, from 0. |
| `PDF-PAGE-CLOSE` | `( page -- )` | Give back the page. |
| `PDF-PAGE-END` | `( page -- )` | Give back the page and what the record keeps between pages; the record is zeroed. |
| `PDF-PAGE-FILE` | `( page -- file )` | The file the page is in. |
| `PDF-PAGE-NUM` | `( page -- num )` | The page object's number, which links and the outline name. |
| `PDF-PAGE-DICT` | `( page -- va vu )` | The page's dictionary. |
| `PDF-PAGE-RESOURCES` | `( page -- va vu type )` | Its resources, a dictionary, or `0 0 PDF-T-END`. |
| `PDF-PAGE-BOX` | `( page -- x0 y0 x1 y1 )` | What the page shows, in 16.16 fixed point, its corners ordered. |
| `PDF-PAGE-ROTATE` | `( page -- degrees )` | 0, 90, 180 or 270. |
| `PDF-PAGE-CONTENTS` | `( page buf -- status )` | The page's content streams decoded onto an empty buffer. |

Statuses are `pdf/filter.f`'s and `pdf/file.f`'s: `PDF-S-OK`,
`PDF-S-MEMORY`, `PDF-S-DAMAGED` for a tree that cannot be walked, and
`PDF-S-MISSING` for a page the tree does not hold, or an object that is no
page of it.

## Finding a page

`PDF-PAGE-OPEN` walks down from the catalog's `/Pages` by the nodes'
`/Count`s, reading only the nodes on the way and the kids it passes. A node
is a dictionary with `/Kids` whose `/Type` is not `/Page`; the root may
itself be the one page. A kid that cannot be read, or is no reference,
holds no pages. The walk reads no more nodes than the file has objects, so
a tree that loops ends with `PDF-S-DAMAGED`.

Each dictionary is read once, its keys noted in one pass, so a node with
a long `/Kids` array is lexed once.

## A page's index

Links and the outline name a page by its object (`pdf/navigate.f`).
`PDF-PAGE-INDEX` goes up from that object through each `/Parent`, adding
the pages of the kids before it in each node's `/Kids`: one for a page,
a node's `/Count` for a node, as `PDF-PAGE-OPEN` counts them, so the index
opens the same page. The way up must end at the catalog's `/Pages`, and
each node must list the object it came from among its kids; otherwise the
object is no page of the tree and the status is `PDF-S-MISSING`. A kid
that cannot be read holds no pages; memory refused gives `PDF-S-MEMORY`.
The walk reads no more nodes than the file has objects.

A reader looks an index up when a link is followed, not when it is shown.

## What a page inherits

`/Resources`, `/MediaBox`, `/CropBox` and `/Rotate` come from the page, or
else from the nearest node above it that has them, each followed through a
reference. The box is the crop box within the media box, or the media box
when the crop box is missing, holds no area, or misses the media box; US
Letter when there is no media box. A rotation is a multiple of 90, taken
modulo 360.

## Reading pages in order

Between pages, the record keeps the last page's parent node, where the next
kid starts in its `/Kids`, and the values the parent passes down: its
resources' bytes, copied, its boxes and its rotation. When the page asked
for is the next kid of that parent, `PDF-PAGE-OPEN` reads only the page, so
reading a document front to back costs the same on every page however wide
the tree is. Any other page walks down from the root. Close a page with
`PDF-PAGE-CLOSE` before the record opens another, and give the record back
with `PDF-PAGE-END` when done. A record moved to another file forgets what
it kept.

In a flat tree of 200 pages, opening page 152 from the root takes about
3,000,000 steps, and opening it after page 151 about 22,000.

## Content

`PDF-PAGE-CONTENTS` decodes the page's `/Contents`, one stream or an array
of them, directly or through a reference, each followed by a line end: the
format divides a page's content between streams only between tokens. A stream
that cannot be decoded whole gives what it could, and the first such status
is returned once the rest are read; memory refused ends the content. The
caller gives the buffer back with `PDF-BUF-FREE`.

The page's dictionary and resources stay valid until `PDF-PAGE-CLOSE`.
Memory comes from the file's memory source. One call runs at a time.
