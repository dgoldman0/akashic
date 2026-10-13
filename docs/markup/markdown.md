# Markdown read as a document

`akashic/markup/markdown.f` reads Markdown into a document
(`media/document.f`) that any application can show.

```forth
REQUIRE markup/markdown.f

source MD-READER msrc doc DOC-OPEN   ( -- status )
```

`MD-READER` is the reader record `DOC-OPEN` takes. The source is any media
source; the document reads it in 4 KiB chunks and never holds it whole.

## What it reads

It follows CommonMark 0.30: block quotes, bullet and numbered lists, ATX and
setext headings, thematic breaks, fenced and indented code, HTML blocks, link
reference definitions and paragraphs, and within them emphasis, strong
emphasis, code spans, links, pictures, autolinks, raw HTML, hard and soft
line breaks, backslash escapes and entities (`markup/html-entities.f`). The
algorithm is the one the CommonMark reference parser, commonmark.js, uses.
Where commonmark.js reads less than the specification's text allows and
markdown-it follows the text, the reader follows the text: tabs may separate
a link's destination and title, a closing fence may end with tabs, and a
destination may hold no control character. GitHub tables are found as
markdown-it finds them: a header row and a delimiter row with as many cells,
and rows until a blank line or a line that begins another block.

Lines may end with a line feed, a carriage return or both. A tab moves to
the next multiple of four columns.

## What it shows

A document shows text, not HTML:

| Markdown | Shows as |
|---|---|
| Raw HTML within text | its text |
| An HTML block, a GitHub table | its lines, unbroken, as code |
| Whitespace between words | one space, as a browser shows it; a hard break is a line break |
| Emphasis, strong emphasis, code, a link | one meaning a character: a link's, else code's, else strong's, else emphasis's |
| A picture within text | its description, as a link to the picture |
| A paragraph that is only a picture | a figure, whose caption is the description |
| An empty list item | its mark beside an empty paragraph |
| NUL, other controls, ill-formed UTF-8 | U+FFFD |

Blocks in a tight list follow one another; elsewhere one blank row comes
between blocks, inside the quotes and items both share. A numbered item's
mark takes the width of the list's widest number and two cells.

Links keep their destinations as written, with escapes and entities
resolved: following one is the application's affair.

## Checked against

The reader is compared, block for block and byte for byte, with what the
CommonMark reference parser (commonmark.js 0.30.0) makes of 31 handwritten
and 120 random documents, recorded in
`local_testing/fixtures/markdown/reference.json` by
`local_testing/generate_markdown_reference.py`; GitHub tables, which the
reference parser does not read, against markdown-it-py. Of the 652 examples
in CommonMark 0.30's specification it agrees with the reference parser on
650. The two it misses name a reference by a label in another case outside
ASCII, such as `[ΑΓΩ]` for `[αγω]`: labels match regardless of ASCII case
only, until Akashic has Unicode case folding.

markdown-it-py differs from the reference parser in a few places the
specification's examples do not reach (see the generator's notes), so it
checks only tables.

## Cost

The structure pass keeps each block's kind, containers and the source spans
of its lines (8 bytes a line), and the link reference definitions; the text
is read again, a block at a time, when a view asks for it. On a 10 KB
README-like document the structure pass takes about 1,000 guest steps a
source byte and reading every block's content about 1,500.

| Word | Stack |
|---|---|
| `MD-READER` | `( -- reader )` |
