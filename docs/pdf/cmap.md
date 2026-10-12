# akashic-pdf-cmap — a font's ToUnicode map, or its encoding

A PDF CMap read from its decoded bytes: the ToUnicode map that says which
characters a font's codes stand for (PDF 32000-1, section 9.10.3), or an
embedded encoding that says which CID each code selects (9.7.5). The font
layer uses one to turn shown strings into characters and the other to find
a code's CID, and builds a map by hand for a composite font's widths.

```forth
REQUIRE pdf/cmap.f
```

`PROVIDED akashic-pdf-cmap`. It depends on `pdf/lexer.f` and
`pdf/filter.f`, whose buffers and statuses it uses.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-CMAP-SIZE` | `( -- bytes )` | A map's record, 88 bytes, eight-byte aligned. |
| `PDF-CMAP-PARSE` | `( a u msrc cmap -- status )` | Read the decoded CMap at `a` into an empty record. |
| `PDF-CMAP-INIT` | `( msrc cmap -- )` | An empty map, to be built by hand. |
| `PDF-CMAP-ADD` | `( first last value cmap -- ok? )` | An entry of one value for the codes `first` to `last`. |
| `PDF-CMAP-SEAL` | `( cmap -- )` | Make a map built by hand ready to look up. |
| `PDF-CMAP-FREE` | `( cmap -- )` | Give back everything the map holds; the record is empty again. |
| `PDF-CMAP-LOOKUP` | `( code cmap -- a n delta true \| false )` | A code's values, or false. |
| `PDF-CMAP-BYTES` | `( a u cmap -- n )` | How many bytes the next code of a string takes. |

`PDF-CMAP-PARSE` gives `PDF-S-OK`, or `PDF-S-MEMORY` when the memory source
refuses; a map read only in part still answers for what it read.

## What it reads

- `begincodespacerange` pairs: the lengths codes have.
- `beginbfchar` and `begincidchar` pairs: a code and its destination.
- `beginbfrange` and `begincidrange` triples: a first and last code and a
  destination. A destination that is one string or CID counts its last
  value up from the range's first code; a `bfrange` destination that is an
  array gives one string a code, and codes past the array's end are left
  out.

A ToUnicode destination is UTF-16BE, at most 512 bytes, with surrogate pairs
joined, so a code may stand for several characters, as a ligature does, or
for none. A destination of one byte is taken as that one character. A
destination that is no string or CID, such as a glyph name, is passed over,
as are other sections, the header's dictionaries and procedures, and
`usecmap`.

## A map built by hand

The same sorted ranges serve any map from codes to one value each. A map
starts with `PDF-CMAP-INIT`, takes entries with `PDF-CMAP-ADD` in any order,
and is sealed with `PDF-CMAP-SEAL` before it is looked up. A lookup's
`delta` is then the code's place in its entry, which a value that does not
count up, such as a width, ignores.

## Looking up

`PDF-CMAP-LOOKUP` gives the code's values, characters or a CID, as `n`
32-bit values at `a`, of which the last is to be counted up by `delta`. `n`
may be 0. The address points into the map and is good until it is given
back. Of entries that hold a code, the one with the greatest first code
wins, and of those, the one read last, so a character listed inside a range
overrides the range there.

`PDF-CMAP-BYTES` follows section 9.7.6.2: it tries the string's first byte
against the one-byte codespace ranges, then its first two bytes against the
two-byte ranges, and so on to four, each byte between the range's bytes at
the same place. When none holds the code, it takes the shortest range's
length; a map with no codespace ranges takes the longest code its entries
have. The answer is never more than the bytes left, nor less than one.

## Cost

Reading takes one pass over the CMap, its values read with `PDF-OPERAND`,
since a CMap holds no references. Entries are appended as they come; when
the map is sealed and any came out of order, they are heap-sorted once, in
place, by first code and then by the order they were read. A lookup is a
binary search, then a step back over any entries that overlap the one it
found. An entry takes 20 bytes, and a destination of more than one
character four bytes a character more; buffers grow by doubling from the
caller's memory source.

One call runs at a time: the words keep the map they work on, and a few
scratch values, in variables.
