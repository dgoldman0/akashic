# akashic-inflate — DEFLATE, zlib and gzip

A resumable decoder for DEFLATE streams (RFC 1951), bare or in a zlib
(RFC 1950) or gzip (RFC 1952) wrapper. It takes input a piece at a time and
fills whatever output room it is given, so a caller never needs the whole
stream or the whole result in memory. It allocates nothing: the caller owns
its record and its window.

```forth
REQUIRE inflate.f
```

`PROVIDED akashic-inflate`. It requires `math/adler32.f` and `math/crc.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `INFL-SIZE` | `( -- bytes )` | The record's size, 3,024 bytes, cell-aligned. |
| `INFL-INIT` | `( window-a window-u wrapper infl -- )` | Start a stream. |
| `INFL-FEED` | `( in-a in-u out-a out-u infl -- in-used out-used status )` | Decode from the input into the output room. |
| `INFL-REASON@` | `( infl -- reason )` | Why a stream is damaged, or 0. |
| `INFL-TOTAL@` | `( infl -- bytes )` | Bytes the stream has given so far. |
| `INFL-DONE?` | `( infl -- flag )` | Whether the stream has ended with its sum matching. |
| `INFL-MOVED` | `( base infl -- )` | With no window, the caller has moved the whole output to `base`. |

The wrapper is `INFL-W-RAW`, `INFL-W-ZLIB` or `INFL-W-GZIP`. A zlib
stream's Adler-32 is checked; a gzip member's header fields are skipped, its
header CRC checked when it has one, and its CRC-32 and length checked. A
gzip file of several members ends with the first.

The window is a power of two from 256 bytes to 32 KB. A zlib stream says
the window it needs and is refused when the caller's is smaller. A bare or
gzip stream may refer back 32 KB, so it is refused only at a reference
farther back than the window.

A caller that keeps the whole output in one run, such as a response body in
its buffer, gives no window: a window of 0 bytes. The output is then the
window, and a reference reads back from it. Each feed's room must begin
right after the bytes the stream has given so far; before it gives one, any
room begins it. A feed whose room begins anywhere else finds the stream
damaged, for its window. A caller that grows its buffer by moving the whole
output elsewhere says where it now begins with `INFL-MOVED`.

## Statuses

| Status | Meaning |
|---|---|
| `INFL-S-MORE` | All of the input is used and the stream wants more. |
| `INFL-S-FULL` | The output room is full and the stream has more to give. |
| `INFL-S-DONE` | The stream has ended and its sum matches. |
| `INFL-S-BAD` | The stream is damaged; `INFL-REASON@` says why. |

DONE and BAD stay: a later feed uses nothing and gives nothing. A symbol
cut between feeds waits in the record's bit buffer, so after MORE the caller
gives the input that follows. After FULL or DONE, input the decoder read
ahead and did not need is not counted as used: after DONE, `in-used` ends at
the stream's last byte, and anything after it is the caller's.

| Reason | Meaning |
|---|---|
| `INFL-R-HEADER` | A zlib or gzip header that is not one, or a wrong gzip header CRC. |
| `INFL-R-WINDOW` | The window is not a power of two from 256 to 32 KB, or is too small for the stream, or, with no window, a feed's room does not follow the output. |
| `INFL-R-DICTIONARY` | A zlib stream that needs a preset dictionary. |
| `INFL-R-BLOCK` | A block of the reserved type. |
| `INFL-R-STORED` | A stored block whose length check fails. |
| `INFL-R-CODES` | Code lengths that make no prefix code, or a block with no end code. |
| `INFL-R-SYMBOL` | Bits that are no symbol, or one of the unused symbols. |
| `INFL-R-DISTANCE` | A reference before the stream's first byte. |
| `INFL-R-SUM` | An Adler-32 or CRC-32 that does not match the data. |
| `INFL-R-LENGTH` | A gzip length that does not match the data. |

## How it decodes

Each block's codes go into lookup tables in the record: a literal or length
code of up to nine bits, a distance code of up to eight, and any code-length
code are one lookup each, and the rare longer code is read a bit at a time.
The bit buffer is a cell, refilled while it has room for a byte. A length
and distance pair is taken whole or not at all, so a cut pair waits in the
buffer.

Every byte goes into the window first. A reference copies within the window
with `CMOVE`, which copies forward a byte at a time, so a run shorter than
its distance repeats as DEFLATE means. The window goes to the output in runs
with `MOVE`, and the sum is taken over each run. A stored block's bytes go
from the input to the window in runs too.

The decoder keeps a feed's working state in module variables, so one feed
runs at a time, though any number of records may take turns. In a guarded
build `INFL-FEED` takes the module's guard.

## Cost

Guest steps per byte of output, decoding 200,000 bytes in one feed:

| Stream | Steps a byte |
|---|---:|
| English-like text, raw, stored blocks (level 0) | 0.1 |
| The same, fixed codes (level 6, `Z_FIXED`) | 62 |
| The same, dynamic codes, level 1 | 112 |
| The same, dynamic codes, level 6 | 60 |
| The same, dynamic codes, level 9 | 53 |
| The same, level 6, gzip | 64 |
| The same, level 6, zlib (Adler-32 13 of them) | 73 |
| Random bytes, stored, raw | 0.1 |
| Random bytes, stored, zlib | 13 |
| One byte repeated, raw | 3.4 |

`local_testing/measure_decompression.py` counts these, each output checked
against Python's zlib.

A literal costs most; a long reference and a stored run cost little. With
no window the costs are the same, since the window's copy to the output is
one accelerated move a run: what no window saves is the window's memory.

## Example

```forth
CREATE INF  INFL-SIZE ALLOT
32768 XBUF WIN
WIN 32768 INFL-W-ZLIB INF INFL-INIT
\ Each time input arrives at IN-A, IN-U bytes:
IN-A IN-U OUT-A OUT-U INF INFL-FEED   ( in-used out-used status )
```

With no window, into one buffer `BUF` of `CAP` bytes, `N` of them given so
far:

```forth
0 0 INFL-W-GZIP INF INFL-INIT
IN-A IN-U BUF N + CAP N - INF INFL-FEED   ( in-used out-used status )
```
