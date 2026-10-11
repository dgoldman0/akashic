# akashic-media-picture — a picture scaled to fit

```forth
REQUIRE media/picture.f
```

A picture copy is one picture no larger than a width and height its caller
asks for, as raw row-major RGBA8. Each user asks for the size it shows: a
text-mode view two pixels a cell high, and a rich terminal that decodes none
of the picture's formats what its pixel answer said. The same picture may
have several copies at once, one per user.

`PIC-F-RGBA8`, `PIC-F-QOI`, `PIC-F-PNG` and `PIC-F-JPEG` name the formats a
picture comes in: raw pixels, as a copy holds them, and the files it can be
read from.

## The file

`PIC-FILE` says which picture a file holds from its first bytes alone, so a
rich terminal that decodes the file's format can take the file as it is and
the guest decodes nothing:

| Format | What is read |
|---|---|
| QOI | The 14-byte header: `qoif`, then the width and height. |
| PNG | The signature and the IHDR chunk that must follow it: thirteen bytes, with the width and height first, each positive and below 2^31. |
| JPEG | From the SOI marker, each segment's marker and length, skipping fill bytes and the markers that stand alone, until a frame header (C0 to CF, but for C4, C8 and CC), which gives the height and width. |

A scan or the end of the picture before any frame header, a marker where no
FF is, or a header cut short makes the file damaged. A frame header whose
height a later segment gives is unsupported.

## Design

| Principle | Detail |
|---|---|
| **Never at full size** | The copy keeps the picture's shape, is never larger than the picture, and is scaled down by averaging while it decodes. Only one source row and one row of sums are held besides the copy. |
| **Bounded steps** | `PIC-STEP` decodes about a budget of source pixels, at least one row, and returns, so its caller stays responsive. |
| **Caller memory** | Every buffer comes from the caller's memory source (`utils/memory-source.f`), sized exactly: one input chunk, one source row, one row of sums when scaling, and the copy. The chunk, row and sums go back once the copy is ready; `PIC-FREE` gives back the rest. A refusal fails the copy cleanly. |
| **Alpha-weighted** | Each colour is averaged weighted by its alpha, so transparent pixels do not darken their neighbours; a fully transparent area stays transparent black. |
| **Formats** | QOI only so far. Any other file fails as unsupported. |

## Size

`PIC-FIT ( sw sh mw mh -- ow oh )` is the size a copy takes: the picture's
own size when it fits within `mw` by `mh`; otherwise the limiting side is
taken whole and the other in proportion, rounded to the nearest pixel, and at
least one pixel. Sides must be below 2^31; a picture with a larger side fails
for memory, since no machine could hold it.

Source column `x` goes to output column `x * ow / sw` and source row `y` to
output row `y * oh / sh`, both rounded down; the column is stepped without
dividing. Each output pixel is the rounded average of the source pixels that
go to it: `a = (Σa + n/2) / n`, and each colour `c = (Σ(c·a) + Σa/2) / Σa`,
or 0 when `Σa` is 0.

## API

| Word | Stack | Meaning |
|---|---|---|
| `PIC-SIZE` | `( -- bytes )` | The record, which its caller owns, eight-byte aligned. |
| `PIC-FILE` | `( source -- format width height reason )` | Which picture the file holds: `PIC-F-QOI`, `-PNG` or `-JPEG`, its size and `PIC-R-NONE`; or `0 0 0` and why not: `-UNSUPPORTED`, `-DAMAGED`, `-MEMORY` (a side of 2^31 or more), `-READ` or `-INVALID`. |
| `PIC-START` | `( max-w max-h source msrc pic -- state )` | Read the header from `source` and take the memory. `PENDING`, or `FAILED`. |
| `PIC-STEP` | `( budget pic -- state )` | Decode some more. `PENDING`, `READY`, or `FAILED`; a copy that is not pending returns its state and does nothing. |
| `PIC-FREE` | `( pic -- )` | Give back everything; the record is empty. |
| `PIC-STATE@` | `( pic -- state )` | `PIC-ST-EMPTY`, `-PENDING`, `-READY`, or `-FAILED`. |
| `PIC-REASON@` | `( pic -- reason )` | Why it failed: `PIC-R-UNSUPPORTED` (not a picture this module decodes), `-DAMAGED` (a bad header, a short file or a wrong end marker), `-READ` (the source failed), `-MEMORY` (the caller's memory refused), or `-INVALID` (a zero bound, or a dead source or memory source). |
| `PIC-WIDTH@`, `PIC-HEIGHT@` | `( pic -- n )` | The copy's size, once started. |
| `PIC-SOURCE-WIDTH@`, `PIC-SOURCE-HEIGHT@` | `( pic -- n )` | The picture's size, once started. |
| `PIC-PIXELS` | `( pic -- a u )` | The copy's RGBA8 rows when ready, else `0 0`. |

## Example

```forth
PIC-SIZE ALLOCATE THROW CONSTANT pic   \ eight-byte aligned
40 30 my-source my-msrc pic PIC-START DROP
BEGIN 4096 pic PIC-STEP PIC-ST-PENDING <> UNTIL
pic PIC-STATE@ PIC-ST-READY = IF
    pic PIC-PIXELS ( a u )  pic PIC-WIDTH@ pic PIC-HEIGHT@  ( use them )
THEN
pic PIC-FREE
```
