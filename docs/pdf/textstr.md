# akashic-pdf-textstr — PDF text strings and characters, as UTF-8

PDF stores a document's own text, such as an outline item's title or the
document's title, as a text string (PDF 32000-1, section 7.9.2.2). This
module turns one into UTF-8, and writes a single character as UTF-8 for
`pdf/font.f`, which gives each glyph of a page's text.

```forth
REQUIRE pdf/textstr.f
```

`PROVIDED akashic-pdf-textstr`. It depends on `pdf/filter.f` and the
generated `pdf/text-tables.f`, whose `PDF-ENC-PDFDOC` maps PDFDocEncoding.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-CHAR+` | `( cp buf msrc -- ok? )` | Character `cp` onto `buf` as UTF-8. |
| `PDF-TEXTSTR+` | `( a u buf msrc -- ok? )` | A text string's `u` bytes at `a` onto `buf` as UTF-8. |

`buf` is a `pdf/filter.f` buffer growing from `msrc`; the flag is false when
the source refuses.

## Text strings

- After the byte order mark FE FF, the string is UTF-16BE. Surrogate pairs
  are joined; a language escape, from one U+001B to the next, is left out.
- After FF FE, which some writers give though the standard does not, it is
  UTF-16LE.
- After EF BB BF, as PDF 2.0 allows, it is UTF-8, copied as it is.
- Otherwise it is PDFDocEncoding.

A code with no character, and half a surrogate pair, is U+FFFD. A tab or a
line end is a space; any other control is left out.

## Cost

`PDF-CHAR+` encodes into the buffer itself rather than through
`text/utf8.f`'s `UTF8-ENCODE`. In a guarded build that word takes the UTF-8
guard on each call: 372 steps a character against 49 for the encoding
alone. `PDF-CHAR+` runs for every glyph of a page's text, so the guard
would add about a million steps to a page of 3,000 characters. One call
runs at a time.
