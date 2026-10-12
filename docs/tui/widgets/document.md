# akashic/tui/widgets/document.f — Document View

**Prefix:** `DOCV-` (public), `_DOCV-` and `_DV-` (internal)  
**Provider:** `akashic-tui-document`  
**Dependencies:** `widget.f`, `draw.f`, [picture.f](picture.md),
[media/document.f](../../media/document.md), `text/text-lines.f`,
`text/bidi.f`, `memory-source.f`, `memory-span.f`,
[semantic-collections.f](../semantic-collections.md)

## Overview

Shows a [document](../../media/document.md) read from top to bottom: its
blocks one after another, each inside the quotes and list items around it.
The document is the owner's, opened and closed by it; the view only reads
it.

### Rows

Each block takes the rows SEMANTIC-CONTENT-1 gives it, so CELL and a rich
terminal show the same rows:

- its blank rows before it, as the document says;
- for a rule, one row;
- for a figure, its picture's rows, then its caption's lines;
- for any other block, its lines.

A block's indent is the cells its containers take. Its text breaks at the
width left, `max(W − indent, 1)`: prose by APT-1-TEXT Section 12, and code
into hard lines left to right. An empty paragraph is one line.

A figure's picture takes the rows its size needs in that width with a cell
two pixels high, never wider than the picture: `ceil(h · min(T, w) / 2w)`
for a `w` by `h` picture in a text area `T` cells wide, at least one row and
at most the view's height. A picture whose size is unknown takes one row.

The view counts each block's rows once at its width and height, and counts
again only when either changes, so a scroll lays out only the blocks it
passes.

### Look

CELL draws each block as MegaPad's reference renderer does:

| Part | Look |
|---|---|
| Quote | a bar (U+2502) in its first cell, on every row of the block; on the rows before it too when they lie inside the quote |
| Bullet item | a bullet in its first cell, on the first row of the block that starts the item: •, ◦ and ▪ by how deep its list lies |
| Numbered item | its number and a full stop, right-aligned before the item's last cell, on the same row |
| Heading | the palette's heading look; levels 1 and 2 underlined |
| Code | a dark background across its text area |
| Rule | a line (U+2500) across its text area |
| Page | its label muted, and a rule's line across the cells each of its lines leaves, one cell clear of the label: after it, or before it right to left |
| Figure | its picture in its picture rows, and its caption muted and italic |

It draws over the owner's style (`DRW-STYLE-RESTORE`). Each meaning of the
text takes the [style palette](../style-palette.md)'s look, keeping its
block's attributes, as a list's fields do; marks are muted. A line of a
right-to-left paragraph ends at the text area's right edge, and a character
the text area's edge cuts is not drawn.

The text comes from outside the application, so it is laid out as
`DRW-TEXT-UNTRUSTED` lays text out: explicit embeddings, overrides and
isolates are ignored.

### Scrolling

The arrow keys move the view one row, Page Up and Page Down its height less
one, and the wheel three rows; Home and End go to the document's first and
last rows. The view never scrolls above the document's first row, nor so
far that its last row rises above the view's bottom. `DOCV-TOP@` tells
which block the view's top row lies in, and how many of its rows lie above.

### Links

A press on a link follows it. A link to one of the document's own headings,
`#name`, scrolls the view to that heading (`DOC-ANCHOR`). Any other target
goes to the owner's follow word. A rich renderer that lays the text out
itself names a link with `KEY-MOUSE-TEXT-FOLLOW`: the block's key, its
index plus one, and the scalar offset in its text. A position on no link is
dropped.

### Figures

The owner says where a figure's picture comes from:

- a resolve word `( name-a name-u ctx -- source | 0 )` gives a
  [media source](../../media/source.md) for a picture's name;
- a release word `( source ctx -- )` gives it back.

The view reads a picture's size from its file once, when it first counts
the figure's rows, and gives the source straight back. While a figure has a
row in view it has a [picture widget](picture.md) of its own, drawn through
the ordinary widget draw in a region inside the view's, so a figure scrolled
partly out shows the part in view. A draw that does not show a figure gives
back its picture widget, copy and source. A figure whose picture cannot be
resolved shows its name.

`DOCV-SERVICE` decodes some more of the first figure whose picture is still
decoding, `PICT-STEP-PIXELS` source pixels a call, as the UIDL host's
service pass does for picture widgets.

The view keeps a record of each figure it has met, in block order whichever
it meets first. A rich side shows each figure with a row in view as a
picture of its own ([UIDL picture snapshot](../uidl-picture-snapshot.md)):
`DOCV-FIGURE@` gives a record's block key and its picture widget while it
has one, and `DOCV-FIGURE-PICTURE` finds the widget by key. Neither changes
the view.

### Publication

A rich terminal draws the document itself, from the blocks the last draw
showed, published as a renderer-neutral DOCUMENT entry
([semantic-collections.f](../semantic-collections.md)) on the rows CELL drew
them (`DOCV-DOCUMENT-CAPTURE`). The entry carries:

- the top block's rows above the view;
- for each block shown: its key (its index plus one), its kind and level, its
  blank rows before it and how many of them lie inside its containers, its
  containers, and for a figure the picture rows the view gave it;
- its text as CELL shows it (`UTF8-SAFE-COPY`, with line feeds), with each
  explicit embedding, override and isolate made an inert stand-in
  (`BIDI-INERT`), and its meanings as style runs.

The terminal breaks the text into rows itself, by the same rules, so the
rows match CELL's. The capture reads only what the view and the document
keep for those blocks, never the source. When a block's content or figure
is not kept, or the counts were made at another size, the view is
`USCOL-S-UNAVAILABLE`, and CELL shows it.

### Memory

Row counts, figure records and copies of figures' names come from the
owner's memory source, as do the pictures' copies. The descriptor, and the
regions and picture widgets of the figures in view, come from `ALLOCATE`, as
other widgets' do. Each draw keeps the contents of the blocks it shows and
gives back the others (`DOC-KEEP`). `DOCV-FREE` gives back all the view
holds; the document stays open.

When a block's content cannot be read, it takes one row and says "(this
part could not be read)"; its rows are counted again at the next pass.

## API

| Word | Stack | Meaning |
|---|---|---|
| `DOCV-NEW` | `( rgn msrc -- widget )` | A view showing nothing yet. |
| `DOCV-OWNER!` | `( resolve-xt release-xt follow-xt ctx widget -- )` | Where figures' pictures come from, where followed links go, and the context those words take. Any may be 0. |
| `DOCV-DOCUMENT!` | `( doc widget -- )` | Show an open document from its top, or nothing for 0. |
| `DOCV-DOCUMENT@` | `( widget -- doc \| 0 )` | The document shown. |
| `DOCV-SCROLL` | `( rows widget -- )` | Scroll by signed rows. |
| `DOCV-GO` | `( index widget -- )` | Put block `index` at the view's top, as near as the document allows. |
| `DOCV-FOLLOW` | `( target-a target-u widget -- )` | Follow a link's target as a press on it does. |
| `DOCV-TOP@` | `( widget -- block rows )` | The block the view's top row lies in, and its rows above the view. |
| `DOCV-SHOWN` | `( widget -- first end )` | The blocks the last draw showed. |
| `DOCV-ROWS` | `( index widget -- rows )` | The rows block `index` takes at the view's width, its blank rows included. |
| `DOCV-REVISION@` | `( widget -- n )` | Counts every change in what the view shows. |
| `DOCV-PENDING?` | `( widget -- flag )` | A figure's picture is still decoding. |
| `DOCV-SERVICE` | `( widget -- changed? )` | Decode some more of a figure's picture; true when what the view shows changed. |
| `DOCV-FIGURE-COUNT` | `( widget -- n )` | The figure records the view keeps. |
| `DOCV-FIGURE@` | `( i widget -- key picture \| 0 )` | Figure record `i`, in block order: its block's key and the picture widget showing it while it has a row in view; `0 0` out of range. |
| `DOCV-FIGURE-PICTURE` | `( key widget -- picture \| 0 )` | The picture widget showing the figure of the block with `key`. |
| `DOCV-FREE` | `( widget -- )` | Give back everything the view holds. |
| `DOCV-GENUINE?` | `( widget -- flag )` | A live document view, by its header. |
| `DOCV-DOCUMENT-CAPTURE` | `( root-key dst cap builder widget -- bytes status )` | Build the view's DOCUMENT entry with the caller's builder; `dst cap` of `0 0` measures. |
| `DOCV-DOCUMENT-MEASURE` | `( root-key builder widget -- bytes status )` | The entry's exact size. |
| `DOCV-STORAGE-DISJOINT?` | `( address bytes -- flag )` | A caller span misses the module's own storage. |
| `DOCV-DOCUMENT-STORAGE-DISJOINT?` | `( address bytes widget -- flag )` | A caller span also misses all the capture reads: the view's descriptor, region, counts and figures, and the document's records and the contents of the blocks shown. |

The widget's type is `WDG-T-DOCUMENT`.
