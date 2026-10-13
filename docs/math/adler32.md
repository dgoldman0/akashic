# akashic-adler32 — Adler-32

The Adler-32 checksum of RFC 1950, which a zlib stream carries after its
deflate data. A sum continues from the last value it returned, so a stream
is summed a piece at a time as it arrives.

```forth
REQUIRE adler32.f
```

`PROVIDED akashic-adler32`. It depends on nothing and keeps no state of its
own, so any number of sums may be under way at once.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `ADLER32-INIT` | `( -- 1 )` | The sum of no bytes. |
| `ADLER32-UPDATE` | `( adler a u -- adler' )` | The sum `adler` continued over `u` bytes at `a`. |
| `ADLER32` | `( a u -- adler )` | The sum of `u` bytes at `a`. |
| `ADLER32-BASE` | `( -- 65521 )` | The modulus. |

## The sum

The sum is `S2 * 65536 + S1`. `S1` is one plus the bytes, and `S2` the sum
of `S1` after each byte, both modulo 65,521, the largest prime below
65,536. `"Wikipedia"` sums to `0x11E60398`.

The module adds a megabyte of bytes at a time before reducing the two sums:
on 64-bit cells neither can overflow in that span. A byte costs 13 guest
steps.
