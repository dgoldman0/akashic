# akashic-pdf-layout — a page's runs of text as a document's blocks

The runs of text a page's content shows (`pdf/content.f`), laid out as the
blocks of part 12's document: paragraphs, headings, list items and code,
each with its text and a meaning a byte of it.

```forth
REQUIRE pdf/layout.f
```

`PROVIDED akashic-pdf-layout`. It depends on `pdf/filter.f`, `pdf/page.f`,
`pdf/content.f`, `pdf/font.f`, `pdf/struct.f`, `pdf/navigate.f`,
`text/text-style.f` and `media/document.f`, whose block and container kinds
it gives.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-LAYOUT-SIZE` | `( -- 104 )` | A layout's record, zeroed before first use. |
| `PDF-LAYOUT-READ` | `( page content struct links layout -- status )` | Lay out the runs `content` read from `page`, which may be closed, by the page's structure `struct` (`pdf/struct.f`), or 0, placing the page's `links` (`pdf/navigate.f`), or 0, over their text. |
| `PDF-LAYOUT-FREE` | `( layout -- )` | Give back its blocks and their text. |
| `PDF-LAYOUT-BLOCKS` | `( layout -- n )` | How many blocks the page has. |
| `PDF-LAYOUT-BLOCK` | `( i layout -- block )` | Block `i`, in reading order. |
| `PDF-BLOCK-KIND` | `( block -- kind level )` | `DOC-B-PARAGRAPH`, `DOC-B-HEADING` with its level, `DOC-B-CODE` or `DOC-B-FIGURE`. |
| `PDF-BLOCK-ITEM` | `( block -- kind number width )` | Its container: a list item's `DOC-C-BULLET` or `DOC-C-NUMBERED` with its number, or a quote's `DOC-C-QUOTE`, and the cells its marker takes; else `0 0 0`. |
| `PDF-BLOCK-TOP` | `( block -- y )` | The top of its first line, in the page's default space, 16.16. |
| `PDF-BLOCK-LOW` | `( block -- y )` | Its low: the middle of its lowest line, a third of that line's size above its baseline; a figure's box's middle. |
| `PDF-BLOCK-ACROSS` | `( block -- x0 x1 )` | How far across its lines reach, the leftmost start to the furthest end; a figure's box. |
| `PDF-BLOCK-SIZE` | `( block -- size )` | Its first line's size; 0 for a figure. |
| `PDF-BLOCK-TEXT` | `( block layout -- a u )` | Its text, UTF-8. |
| `PDF-BLOCK-MEANINGS` | `( block layout -- a )` | A meaning (`TSTY-*`) for each byte of its text. |
| `PDF-BLOCK-FIGURE` | `( block -- num w h )` | A figure's picture object (`pdf/image.f`) and the width and height it is drawn at, 16.16. |
| `PDF-LAYOUT-LINKS` | `( layout -- n )` | How many places the links have in the blocks' text. |
| `PDF-LAYOUT-LINK` | `( i layout -- block offset length link )` | Place `i`: the block, where in its text and how many bytes, and the link's index in the links given. |

`PDF-LAYOUT-READ` gives `PDF-S-OK` or `PDF-S-MEMORY`.

## Lines

Blocks follow the order the content shows its text, the order producers
write text in. Runs make a line while each starts on the line's baseline,
within four tenths of the size, and no further left than half the size
before the line's end. A gap of more than 0.15 of the size between runs is
a word's, and gets a space unless one is there. A run whose baseline is not
level is a line of its own. Text marked as an artifact, such as a tagged
page's running heads and numbers, is left out.

## Tagged pages

On a page whose structure says which block each run's MCID belongs to, a
block is one element's text: a line never mixes two elements, and blocks
break where elements do. The element's kind makes a heading or code; a
paragraph is still judged by its lines below, since producers often map
their heading and code styles to P. The container around the element makes
a list item or a quote; a list item's label is not part of its text but
gives the item its number, from its digits or its letter's place. Lines of
code in elements one after another, at the code's line spacing, make one
block, as producers often tag each line apart. Runs with no structure lay
out as on an untagged page.

## Paragraphs

On an untagged page, and for runs with no structure, the page's body text is
the size most of its text has; its line spacing,
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

## Figures

A picture the content draws (`pdf/content.f`) is a figure, a block of its
own, where it falls among the text: before the first line of the runs read
after it, any block being built ending there. Its top is the top of the box
it is drawn in, and its text is empty. Pictures drawn as artifacts, such
as a page's background, and pictures smaller than the body text's size
either way, such as bullets and rules drawn as pictures, are left out.

## Where a block lies

Each block keeps where it lies on the page, which is how a destination's
place on its page finds a block (`pdf/document.f`): its top, its low, how
far across it reaches, and its first line's size. A block's low is the
middle of its lowest line, so a view whose top lies above it shows most of
that line. A figure's top, low and reach are its box's top, middle and
sides.

## Links

A link's rectangle (`pdf/navigate.f`) covers the text of the runs it meets:
a run whose height a third of its size above its baseline lies in the
rectangle, and whose span across meets it. The run's bytes the rectangle's
part of its span takes are found in proportion, then moved to the nearest
places where a word starts and ends: at a space, at either end of the run,
or inside punctuation that opens or closes a word, so a link's ends land
on whole words without a full stop after them. A link whose words are runs
of their own, as TeX sets them, covers the spaces between its words too.

The places keep their link through the lines and blocks the text goes
into: past a list item's marker, across a line end, and over a word joined
back from a hyphen. A link that goes on to the next line is placed in each
line it covers. `PDF-LAYOUT-LINK` gives each place's block and where in the
block's own text it lies. The lines' links are matched once the lines are
made: for each line, the links whose rectangles meet its height, then for
each of its runs, those links, so a page costs its lines times its links
and the runs that meet one.

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
