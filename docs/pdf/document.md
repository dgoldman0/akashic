# akashic-pdf-document — a PDF read as a document, a page at a time

A reader for the [document model](../media/document.md), so any view that
shows documents shows a PDF as text to read: its pages' paragraphs,
headings, list items, quotes, code and figures, reflowed to the view.

```forth
REQUIRE pdf/document.f
```

`PROVIDED akashic-pdf-document`. It depends on `pdf/filter.f`,
`pdf/file.f`, `pdf/page.f`, `pdf/font.f`, `pdf/content.f`, `pdf/struct.f`,
`pdf/navigate.f`, `pdf/labels.f`, `pdf/layout.f`, `pdf/image.f`, `media/document.f`,
`media/picture.f`, `text/text-style.f` and `utils/string.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-DOC-READER` | `( -- reader )` | The reader, for `DOC-OPEN`. |

## Pages as parts

The document has a part for each page (see "Parts" in
[media/document.md](../media/document.md)), so opening a PDF reads its
cross-reference and how many pages its tree holds, and nothing more. The
count is at most the object numbers the file's table spans, since each page
is an object, so a damaged or hostile count cannot ask for more parts than
the file could hold.

A view reads a page when it nears it. Reading a page reads its content
(`pdf/content.f`), its structure when it is tagged (`pdf/struct.f`), and lays
it out (`pdf/layout.f`). The page then gives:

- its start, a `DOC-B-PAGE` block whose text is the page's label
  ([pdf/labels.f](labels.md)), such as `iv`, or its number from 1;
- each block the layout gives, in reading order: a paragraph, heading or
  code block, in its list item or quote when it has one, or a figure.

A page the tree cannot give, or one that cannot be opened, gives its start
and the paragraph "(this page could not be read)". A page whose content is
damaged gives the blocks of what could be read.

A blank row lies before each block but the first page's start. Two list
items in a row have none between them, and the blank row between two quoted
blocks lies inside the quote. A list item's block starts its item, with the
number and marker width the layout found.

A figure has no caption. Its name is `picture` and its picture object's
number, such as `picture 30`.

## Links

Reading a page reads its links too (`pdf/navigate.f`), and the layout
places each over the text it covers. The page keeps the places and each
link's target with its text, and its text takes the link's meaning
(`TSTY-LINK`) there, so a view shows it as a link. A block's content gives
its links (`DOC-CB-LINK`):

- a link to the web has its address as its target, which a view gives to
  its owner;
- a link within the file has `#`, a byte for its destination's type (`0`
  plus the `PDF-T-` type) and the destination's value as the file holds it.

`DOC-ANCHOR-PART` (the reader's anchor word) resolves such a target only
when it is followed: `PDF-DEST` finds the page object, and `PDF-PAGE-INDEX`
its index, which is the part a view reads. A destination that names no
page of the document resolves to none.

Once the page is read, `DOC-ANCHOR` gives the block the destination shows
first, from its left and top and where the page's blocks lie
(`pdf/layout.f`). Each page read keeps, for each of its blocks, how far
across it reaches, widened by its first line's size each side, and its
low, the middle of its lowest line. The block shown first is:

1. of the blocks that reach across the destination's left, the one whose
   low is the highest at or below the destination's top, the first of
   equals;
2. then, of the blocks within that block's reach, its column, the one
   whose low is the highest at or below the top, so a picture centred
   above its caption is found though it does not reach the left.

Following a link asks for its destination twice: for its page, and once
the page is read, for its place. The file does not change while it is
open, so the reader keeps the destination it found last with its target,
and the second asking costs nothing.

A destination without a left, or with no block across it at or below the
top, looks at every block. One without a top, such as `/Fit`, or whose
block is the page's first, shows the page's start, and one below every
block shows the page's last. A link to a section shows its heading, and
on a page of two columns a link to the second column's top shows that
column's first block, not the first column's block at the same height.

On a page of a TeX document with seven links, reading them and placing
them costs about 440,000 steps, most of it reading the links' annotations,
over the 1.26 million laying the page out takes.

## Contents

The document's contents (`DOC-CONTENTS`) are the file's outline
(`pdf/navigate.f`): each item at its level, from 0, with its title, going
where it goes as a link would: a destination resolved only when it is
chosen, or an address. An item that goes nowhere only heads the items
under it. An item the outline says starts closed starts closed
(`DOC-ENTRY-CLOSED?`). A file without an outline has its pages as contents, each "Page"
and its label, going to that page (`#p` and its index). The labels are read
once, when the document opens. Making the
contents reads the outline and no page.

## Pictures

The document holds its pictures (`DOC-PICTURES?`). `DOC-PICTURE` opens the
picture object a figure's name gives with [pdf/image.f](image.md) and fills
a maker ([media/picture.f](../media/picture.md)) with its size, which makes
its file a step at a time: a JPEG as it is, or samples as a QOI file. A
picture that makes no file, such as JPEG 2000 data, or an object that is no
picture, gives no maker, and the view shows the figure's name. Each maker
holds its own picture record from the document's memory, given back with
`PIC-MAKER-FREE`.

## Text kept

Each page read keeps its text and a meaning a byte of it, its start's label
first, in one allocation; a block keeps where its text lies there. A block's
content is copied from it, a run of one meaning at a time, so a view that
gives contents back and reads them again never lays the page out again. A
page's text stays while the document is open.

## Statuses

`DOC-OPEN` gives `DOC-S-OK`; `DOC-S-LOCKED` for a file that needs a
password, or that this handler cannot decrypt (`pdf/crypt.f`);
`DOC-S-MEMORY` when memory is refused; and `DOC-S-READ` for anything else
that cannot be read, such as a file that is no PDF. Reading a page gives
`DOC-S-OK`, or `DOC-S-MEMORY`.

## Memory and cost

Memory comes from the document's memory source: the file, a set of fonts
kept from page to page, so a document's fonts are read once, a page record
kept between pages, so reading pages in order opens each by reading only
itself, and each page's text. What laying a page out takes is given back
once its blocks are added. One call runs at a time.
