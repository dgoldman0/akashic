# akashic-pdf-font — the characters and widths of a PDF font's codes

A PDF font read for text: which characters each code of a shown string
stands for, how wide each is, and the font's style. Glyph shapes are not
read; the terminal draws text in its own fonts.

```forth
REQUIRE pdf/font.f
```

`PROVIDED akashic-pdf-font`. It depends on `pdf/lexer.f`, `pdf/filter.f`,
`pdf/file.f`, `pdf/cmap.f`, the generated `pdf/text-tables.f`, and
`pdf/textstr.f`, whose `PDF-CHAR+` writes each character as UTF-8.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-FONT-SIZE` | `( -- 328 )` | A font's record, eight-byte aligned. |
| `PDF-FONT-LOAD` | `( va vu type file font -- status )` | Read the font dictionary a value gives, through a reference. |
| `PDF-FONT-FREE` | `( font -- )` | Give back everything the font holds. |
| `PDF-FONT-NEXT` | `( a u font -- a' u' code n )` | The next code of the `u` bytes of a shown string, `u` at least one, and its bytes. |
| `PDF-FONT-TEXT+` | `( code font buf -- ok? )` | The code's characters, UTF-8, onto a buffer drawing on the font's memory source. |
| `PDF-FONT-WIDTH` | `( code font -- w )` | The code's width, in thousandths of the text size. |
| `PDF-FONT-GLYPH` | `( code font -- a u w )` | Both, from the codes kept. |
| `PDF-FONT-STYLE` | `( font -- flags )` | `PDF-FONT-BOLD`, `-ITALIC`, `-FIXED`, `-SERIF`, `-VERTICAL`. |
| `PDF-FONTS-SIZE` | `( -- 32 )` | A set of fonts, zeroed before first use. |
| `PDF-FONTS-GET` | `( va vu type file fonts -- font status )` | The font a value gives, read once by its object; 0 for one that cannot be read. |
| `PDF-FONTS-FREE` | `( fonts -- )` | Give back every font the set holds. |

`PDF-FONT-LOAD` gives `PDF-S-OK`, `PDF-S-MEMORY`, or the file's status for
a font dictionary it cannot read; on failure the font holds nothing.

## Characters

A code's characters come from the font's ToUnicode map (PDF 32000-1,
section 9.10.2) when the map holds the code. Otherwise:

- A simple font (Type 1, TrueType, Type 3) has a table of 256 characters.
  Its base is the encoding `/Encoding` names, or its `/BaseEncoding`:
  Standard, WinAnsi, MacRoman or PDFDoc. Without one, an embedded Type 1
  program's own encoding is read from the clear text of its `/FontFile`,
  its `dup code /name put` lines or `StandardEncoding`, when the font has no
  ToUnicode map; else Symbol's and ZapfDingbats' fonts have their own,
  another symbolic font is taken as Latin-1, a TrueType font as WinAnsi,
  and the rest as Standard. `/Differences` names glyphs over the base.
- A glyph name gives its character through the Adobe Glyph List for New
  Fonts and the names the encodings and the Symbol font use; its part
  before a period (`a.sc`); a ligature's letters joined by underscores
  (`f_f_i`), or else its first letter; `uniXXXX`, its first character; and
  `uXXXX` to `uXXXXXX`. The Symbol font's Delta, Omega and mu are the Greek
  letters, as Adobe's mapping of its encoding has them.
- A composite font's code is its character when its encoding is a UCS-2
  or UTF-16 CMap.
- A code with no character is U+FFFD.

`PDF-FONT-TEXT+` writes the characters as UTF-8: a ligature U+FB00 to
U+FB06 as its letters, so text reflows and searches as words; a tab or line
end as a space; other controls as nothing.

## Codes

A simple font's code is one byte. A composite (Type 0) font's code is two
bytes for Identity and UCS-2 encodings, two or four for UTF-16, and else as
the codespace ranges of its embedded encoding CMap, or for another named
CMap of its ToUnicode map, say (9.7.6.2). Word spacing applies to a code
32 of one byte.

## Widths

Widths are in thousandths of the text size:

- `/Widths` from `/FirstChar`; other codes the descriptor's `/MissingWidth`.
- A standard font with no `/Widths` takes its metrics' widths by each
  code's character: Helvetica and Arial, and Times, in their bold and
  italic forms; Courier is 600 throughout; another font 500.
- A Type 3 font's widths are scaled by its `/FontMatrix`, read to
  millionths, so a matrix of 0.001 gives the widths themselves.
- A composite font's come from its CIDFont's `/W`, else `/DW` (1000), by the
  code's CID: the code itself for Identity and other named CMaps, an
  embedded CMap's CID. Runs of equal widths are kept as one range.

## Style

From the descriptor: its flags' FixedPitch, Serif, Italic and ForceBold,
a `/FontWeight` of 600 or more, and a nonzero `/ItalicAngle`. From the font's
name, its subset prefix dropped: Bold, bold, Black, Heavy and Demi;
Italic and Oblique; Courier and Mono; and TeX's CMBX, CMTI, CMSL and CMTT.
A CMap name ending `-V` marks the font vertical.

## Codes kept

`PDF-FONT-GLYPH` keeps the codes shown last in a table of 256 by a hash of
the code: each code's width and up to 15 bytes of its characters. Both
depend on the code alone, so a code shown again costs a lookup instead of a
ToUnicode search, a width search and UTF-8 encoding. A code whose
characters are longer is written into scratch memory each time. The
characters are valid until the next call; they are at most 769 bytes, as a
ToUnicode destination is at most 512 bytes of UTF-16.

## Sets of fonts

A page names its fonts by object, and a document's pages share them. A set
reads each font object once and keeps it, with fonts that could not be
read kept as 0, until `PDF-FONTS-FREE`. A font given inline rather than by
reference is read each time it is asked for and kept the same way. A set
draws on the memory source of the file it is first used with.

## Memory and cost

A font takes 328 bytes, a simple font's tables 2 KB, the codes kept 6 KB,
and its maps their entries. Memory comes from the file's memory source.
Loading costs about a million steps for a font with a ToUnicode map or an
embedded program to read; a code shown again then costs under a hundred.
One call runs at a time.
