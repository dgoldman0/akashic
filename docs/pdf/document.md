# akashic-pdf-document — a PDF read as a document, a page at a time

A reader for the [document model](../media/document.md), so any view that
shows documents shows a PDF as text to read: its pages' paragraphs,
headings, list items, quotes, code and figures, reflowed to the view.

```forth
REQUIRE pdf/document.f
```

`PROVIDED akashic-pdf-document`. It depends on `pdf/filter.f`,
`pdf/file.f`, `pdf/page.f`, `pdf/font.f`, `pdf/content.f`, `pdf/struct.f`,
`pdf/layout.f`, `pdf/image.f`, `media/document.f`, `media/picture.f`,
`text/text-style.f` and `utils/string.f`.

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

- its start, a `DOC-B-PAGE` block whose text is the page's number from 1;
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
