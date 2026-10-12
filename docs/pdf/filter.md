# akashic-pdf-filter — a stream's bytes through its filters

A PDF stream's data passes through the filters its dictionary names (PDF
32000-1, section 7.4) before anything reads it.

```forth
REQUIRE pdf/filter.f
```

`PROVIDED akashic-pdf-filter`. It requires `pdf/lexer.f`, `utils/inflate.f`,
`render/png.f` for PNG's filters, and `utils/memory-source.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-DECODE` | `( in-a in-u dict-a dict-u buf msrc -- status )` | Decode the `in-u` bytes at `in-a` through the dictionary's filters into `buf`. |
| `PDF-DECODE-IMAGE` | `( in-a in-u dict-a dict-u buf msrc -- coding status )` | Decode a picture's stream as far as its own coding. |
| `PDF-PICTURE-FILTERS` | `( dict-a dict-u -- coding lone? )` | A picture stream's coding, and whether nothing else is in front of it. |
| `PDF-BUF-SIZE` | `( -- 24 )` | A buffer's record: `PDF-BUF.A`, `PDF-BUF.CAP`, `PDF-BUF.U`. |
| `PDF-BUF-FREE` | `( buf msrc -- )` | Give a buffer's bytes back. |
| `PDF-BUF-GROW` | `( need buf msrc -- ok? )` | Room for at least `need` bytes, the contents kept; the room doubles until it is enough. |
| `PDF-BUF-APPEND` | `( a u buf msrc -- ok? )` | Add `u` bytes at `a` to the buffer's end, growing it. |

`PDF-DECODE` reads the dictionary's `/Filter` and `/DecodeParms`, or in an
inline picture's dictionary `/F` and `/DP`, each a direct value: one filter
or an array of them, each with its parameters or `null`. It takes the buffer
from the memory source and grows it by doubling; the caller gives it back
with `PDF-BUF-FREE`. Between two filters it holds both their outputs. A
stream with no filter is copied.

The other PDF modules keep their own growing buffers with `PDF-BUF-GROW`
and `PDF-BUF-APPEND`. An empty buffer's record is all zeros, and its first
growth takes at least eight bytes.

## Filters

| Filter | Short name | Notes |
|---|---|---|
| `FlateDecode` | `Fl` | Inflated with the buffer as the inflater's window, then the PNG predictors (10 to 15) or the TIFF predictor (2, eight-bit samples) of its parameters. |
| `LZWDecode` | `LZW` | Codes of 9 to 12 bits, `/EarlyChange` 1 or 0, with the same predictors. |
| `ASCIIHexDecode` | `AHx` | |
| `ASCII85Decode` | `A85` | |
| `RunLengthDecode` | `RL` | |

A picture's `DCTDecode`, `JPXDecode`, `JBIG2Decode` or `CCITTFaxDecode`, and
any other filter, is not decoded here.

## Pictures

A picture's own coding is the last of its filters: `PDF-IMG-DCT`, a JPEG
file; `PDF-IMG-JPX`, a JPEG 2000 file; `PDF-IMG-JBIG2`; `PDF-IMG-CCITT`; or
`PDF-IMG-SAMPLES` when every filter is one this module decodes and what
comes out is the picture's samples. `PDF-DECODE-IMAGE` decodes the filters
before that coding and leaves its data in the buffer, saying which coding it
is; with no coding of its own, it decodes every filter, as `PDF-DECODE`
does. `PDF-PICTURE-FILTERS` reads a dictionary's filters without decoding:
the coding, and whether nothing else is in front of it, so `pdf/image.f`
can take a lone JPEG straight from the file, and read samples under no
filter or `FlateDecode` alone a piece at a time.

## Statuses

| Status | Meaning |
|---|---|
| `PDF-S-OK` | The bytes are in the buffer. |
| `PDF-S-MEMORY` | The memory source refused; nothing is kept. |
| `PDF-S-DAMAGED` | The data is damaged; the bytes decoded before the damage are in the buffer. A Flate stream cut short, or whose sum is wrong, is damaged. |
| `PDF-S-UNSUPPORTED` | A filter this module does not decode. |

`PDF-S-READ` is the file layer's, for a file that cannot be read.

The decoder keeps one decode's working state in module variables, so one
decode runs at a time.
