# akashic-pdf-labels — a PDF's page labels

A document's page labels (PDF 32000-1, section 12.4.2) name its pages as a
reader sees them printed: `iv`, `12`, `A-3`. A document's view labels each
page's start with them ([pdf/document.f](document.md)).

```forth
REQUIRE pdf/labels.f
```

`PROVIDED akashic-pdf-labels`. It depends on `pdf/lexer.f`, `pdf/filter.f`,
`pdf/file.f`, `pdf/tree.f`, `pdf/textstr.f` and `utils/string.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-LABELS-SIZE` | `( -- 56 )` | A labels record, zeroed before first use. |
| `PDF-LABELS-READ` | `( file labels -- status )` | Read every range of the document's labels. |
| `PDF-LABELS-FREE` | `( labels -- )` | Give back the ranges; the record is zeroed. |
| `PDF-LABEL` | `( i labels buf -- ok? )` | Page `i`'s label, UTF-8, onto a buffer (`pdf/filter.f`); false when memory refuses. |

## The labels

The catalog's `/PageLabels` number tree maps the index of the first page
of each range to how the range is labelled:

- a style, `/S`: `/D` decimal, `/R` and `/r` roman upper and lower case,
  `/A` and `/a` letters, or none, for a label of the prefix alone;
- a prefix, `/P`, a text string;
- the number its first page takes, `/St`, 1 when absent.

A page's label is its range's prefix, then the number its first page takes
plus the page's place in the range, in the range's style. Roman numerals
repeat their thousands however many there are. Letters go A to Z, then AA
to ZZ, AAA and on. The range a page lies in is the one with the greatest
first page not past it, so ranges out of order still label their pages. A
page before every range, or in a document without labels, is labelled with
its number from 1.

## Reading them once

`PDF-LABELS-READ` visits every pair of the tree once
(`PDF-NUMS-EACH` in [pdf/tree.f](tree.md)), keeping each range and its
prefix as UTF-8, so a page's label then costs no reading: a document's
list of pages labels every page from what it read. A range that cannot be
read is left out. It gives `PDF-S-OK`, `PDF-S-MEMORY`, or `PDF-S-LOCKED`
for a locked file, whose prefixes cannot be read. Memory comes from the
file's memory source. One call runs at a time.
