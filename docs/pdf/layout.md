# akashic-pdf-layout — a page's runs of text as a document's blocks

The runs of text a page's content shows (`pdf/content.f`), laid out as the
blocks of part 12's document: paragraphs, headings, list items and code,
each with its text and a meaning a byte of it.

```forth
REQUIRE pdf/layout.f
```

`PROVIDED akashic-pdf-layout`. It depends on `pdf/filter.f`, `pdf/page.f`,
`pdf/content.f`, `pdf/font.f`, `text/text-style.f` and `media/document.f`,
whose block and container kinds it gives.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-LAYOUT-SIZE` | `( -- 80 )` | A layout's record, zeroed before first use. |
| `PDF-LAYOUT-READ` | `( page content layout -- status )` | Lay out the runs `content` read from `page`, which may be closed. |
| `PDF-LAYOUT-FREE` | `( layout -- )` | Give back its blocks and their text. |
| `PDF-LAYOUT-BLOCKS` | `( layout -- n )` | How many blocks the page has. |
| `PDF-LAYOUT-BLOCK` | `( i layout -- block )` | Block `i`, in reading order. |
| `PDF-BLOCK-KIND` | `( block -- kind level )` | `DOC-B-PARAGRAPH`, `DOC-B-HEADING` with its level, or `DOC-B-CODE`. |
| `PDF-BLOCK-ITEM` | `( block -- kind number width )` | A list item's `DOC-C-BULLET` or `DOC-C-NUMBERED`, its number and the cells its marker takes; else `0 0 0`. |
| `PDF-BLOCK-TOP` | `( block -- y )` | The top of its first line, in the page's default space, 16.16. |
| `PDF-BLOCK-TEXT` | `( block layout -- a u )` | Its text, UTF-8. |
| `PDF-BLOCK-MEANINGS` | `( block layout -- a )` | A meaning (`TSTY-*`) for each byte of its text. |

`PDF-LAYOUT-READ` gives `PDF-S-OK` or `PDF-S-MEMORY`.

## Lines

Blocks follow the order the content shows its text, the order producers
write text in. Runs make a line while each starts on the line's baseline,
within four tenths of the size, and no further left than half the size
before the line's end. A gap of more than 0.15 of the size between runs is
a word's, and gets a space unless one is there. A run whose baseline is not
level is a line of its own. Text marked as an artifact, such as a tagged
page's running heads and numbers, is left out.

## Paragraphs

The page's body text is the size most of its text has; its line spacing,
the distance between body lines' baselines most of them share; and its
right margin, where its longest line ends. A line starts a new block when:

- it, or the line before, is not level;
- its font's pitch, fixed or not, differs from the block's;
- its size differs from the block's by more than a tenth;
- its baseline is not below the last, or is more than 1.3 times the block's
  line spacing below it;
- it starts a list item;
- in a list item, it does not start where the item's text starts;
- it is indented past the block's left by more than its size, as a
  paragraph's first line is; or
- in body text, the line before it ends more than four times the size short
  of the right margin, as a paragraph's last line does, unless that line
  ends with a hyphen.

Lines join with a space between, except a word split by a hyphen at a line's
end between lowercase letters, which is joined back into one. Lines of code
join with a line end, each indented by the fixed-pitch characters its start
lies right of the block's first line.

## Kinds

- **Code:** lines in a fixed-pitch font.
- **Heading:** a block of up to three lines larger than the body text:
  level 1 at 1.6 times the body's size, 2 at 1.3, 3 at 1.15; or a single bold
  line of body size and under a hundred bytes, level 4.
- **List item:** a block that starts with a bullet (•, ‣, –, ⁃, ◦, ▪, ▫, ■,
  □, ◾, the Symbol font's bullets, ·, - or *) and a space, or with up to three
  digits or a letter followed by `.` or `)` and a space, or in parentheses.
  The marker is left out of the text and kept as the item's kind, number and
  width.
- **Paragraph:** anything else.

A line of digits alone that is the page's topmost or lowest line is its
number, and is left out.

## Meanings

A paragraph's bytes mean what their runs' fonts say: `TSTY-STRONG` for bold,
`TSTY-EMPHASIS` for italic, `TSTY-CODE` for fixed-pitch text within prose,
`TSTY-PLAIN` otherwise and for the spaces put between runs. A heading's and
code's text is plain, since their kind says what they are.

## Memory and cost

Lines are built in buffers given back when the page is laid out; the blocks
and their text stay until `PDF-LAYOUT-FREE`. Memory comes from the page's
file's memory source. Laying out a page of a TeX document costs about
600,000 steps, a tenth of reading its content. One call runs at a time.

A paragraph that a page break splits is two blocks, one on each page.
