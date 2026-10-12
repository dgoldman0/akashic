# akashic-pdf-content — a page's content, read for its text

A PDF page's content streams interpreted for the text they show: runs of
text with their positions, sizes, styles and marked content, which the
layout step turns into a document's lines and paragraphs.

```forth
REQUIRE pdf/content.f
```

`PROVIDED akashic-pdf-content`. It depends on `pdf/lexer.f`,
`pdf/filter.f`, `pdf/file.f`, `pdf/page.f` and `pdf/font.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-CONTENT-SIZE` | `( -- 64 )` | A page content's record, zeroed before first use. |
| `PDF-CONTENT-READ` | `( page fonts content -- status )` | Read an open page's runs, its fonts from the set `fonts`. |
| `PDF-CONTENT-FREE` | `( content -- )` | Give back the runs and their text. |
| `PDF-CONTENT-RUNS` | `( content -- n )` | How many runs were read. |
| `PDF-CONTENT-RUN` | `( i content -- run )` | Run `i`, in the order the content shows them. |
| `PDF-RUN-TEXT` | `( run content -- a u )` | Its characters, UTF-8. |
| `PDF-RUN-START` | `( run -- x y )` | Its first glyph's origin, on the baseline. |
| `PDF-RUN-END` | `( run -- x y )` | Where the last glyph's advance leaves the text position. |
| `PDF-RUN-SIZE` | `( run -- size )` | The text size as the matrices scale it. |
| `PDF-RUN-STYLE` | `( run -- flags )` | Its font's style, with `PDF-RUN-INVISIBLE` and `PDF-RUN-ARTIFACT`. |
| `PDF-RUN-MCID` | `( run -- mcid )` | The innermost marked content's MCID, or -1. |

Points and sizes are in the page's default space, in 16.16 fixed point; the
page's box and rotation are the layout's to apply. `PDF-CONTENT-READ` gives
`PDF-S-OK`, `PDF-S-MEMORY`, or a content stream's status when one could not
be decoded whole, after reading as far as it goes.

## What is read

The interpreter follows PDF 32000-1 sections 8 and 9.4:

- the graphics state's matrix (`cm`) and its saves and restores (`q`, `Q`),
  a restore never reaching past what its content stream saved;
- the text state: `Tc`, `Tw`, `Tz`, `TL`, `Tf`, `Tr`, `Ts`;
- text objects and positioning: `BT`, `ET`, `Td`, `TD`, `Tm`, `T*`;
- text showing: `Tj`, `TJ`, `'` and `"`, each glyph advancing the text
  position by its width, the character and word spacing and the
  horizontal scale (9.4.4), and `TJ`'s numbers moving it back;
- marked content: `BMC`, `BDC` with an inline property list's `/MCID`, and
  `EMC`; text inside `/Artifact` is marked as an artifact;
- form XObjects (`Do`): read inside the page's content under their
  `/Matrix`, with their own resources or else their drawer's, their state
  saved around them. A form being drawn is not drawn again inside itself.
- inline images (`BI` ... `ID` ... `EI`) are passed over, their data to an
  `EI` between white space.

Other operators, which only draw, are passed over. Text in rendering mode 3,
which scanned pages carry as recognized text, is read and marked
`PDF-RUN-INVISIBLE`.

## Runs

A run is text shown with one font at one size, style and MCID whose glyphs
follow one another: a show that starts within a tenth of the size of where
the open run ends continues it. Kerning stays inside a run, while a gap,
as between words that TeX places with `TJ` numbers, starts another, so the
layout puts spaces between runs by the gaps between them.

## Fonts

Fonts come from a set of fonts (`pdf/font.f`) the caller keeps from page to
page, so a document's fonts are read once. Each content stream looks up its
`/Font` dictionary once; a name then costs a dictionary lookup and a set
lookup by object.

## Memory and cost

The page's content is decoded whole into memory, and each form's content
while it is read. Saves, content streams and marked content nest on stacks
that grow from the file's memory source, never on the return stack, so
nesting is bounded by memory. A run takes 72 bytes, and its text its UTF-8.

A page of a TeX document, about 2,800 characters in 15 KB of content,
takes about 5.4 million steps once its fonts are read: some 1.5 million to
inflate the content, about 0.5 million to lex it, and the rest to show the
glyphs. The text size is kept until a matrix or the font changes. One call
runs at a time.
