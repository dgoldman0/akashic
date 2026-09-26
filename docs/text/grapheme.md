# akashic-grapheme — Characters and Their Widths

A character is one extended grapheme cluster, as the shared text contract
([`docs/rich-terminal/APT-1-TEXT.md`](../rich-terminal/APT-1-TEXT.md)
Section 3) defines it: UAX #29 for Unicode 15.1.0, rules GB1 to GB999
including GB9c.  This module finds characters in UTF-8 text, measures them
by Section 4 of the contract, and reads ill-formed UTF-8, `Cc`, `Zl`, and
`Zp` scalars as U+FFFD (Section 5).

```forth
REQUIRE text/grapheme.f
```

`PROVIDED akashic-grapheme` — safe to include multiple times.

---

## Segmenter

`GR-BREAK? ( props state -- flag )` judges one scalar at a time: it is true
when a character boundary comes before the scalar whose packed properties
(from `UP-PROPS`) are `props`, and it moves the state past that scalar.
`GR-RESET ( state -- )` starts a text; `GR-STATE-SIZE` bytes of caller-owned
state hold everything the rules need.

The state packs the previous scalar's Grapheme_Cluster_Break value, the
GB11 emoji state, the GB9c conjunct state, and the count of regional
indicators in a row into one cell.  That cell is zero exactly when the
previous scalar was an ordinary character with nothing pending, so an
ordinary character after an ordinary character breaks after one test.
Other pairs use a 14 by 14 table of the stateless rules (GB3 to GB9b),
built at load time; only an Other after an Extend or ZWJ, or two regional
indicators, consult the state.

## Cursor

A cursor walks a UTF-8 buffer one character at a time.

| Word | Stack | Meaning |
|------|-------|---------|
| `GR-CURSOR-INIT` | `( addr u flags cursor -- )` | Start at `addr u`; `GR-F-TAB` keeps U+0009 as itself |
| `GR-NEXT` | `( cursor -- flag )` | Read the next character; false at the end |
| `GR-C-ADDR` | `( cursor -- a )` | First byte of the character |
| `GR-C-BYTES` | `( cursor -- u )` | Its length in bytes |
| `GR-C-SCALARS` | `( cursor -- n )` | Its length in scalars |
| `GR-C-WIDTH` | `( cursor -- w )` | Its width `W(c)`: 0, 1, or 2 |
| `GR-C-CP0` | `( cursor -- cp )` | Its first scalar, after replacement |
| `GR-C-PROPS0` | `( cursor -- props )` | That scalar's properties |
| `GR-C-CP1` | `( cursor -- cp\|-1 )` | Its second scalar, or -1 |

The cursor takes `GR-CURSOR-SIZE` bytes of caller-owned storage.  Separate
cursors are independent, so the cursor words are reentrant.

Width follows the contract: 0 when every scalar is default-ignorable, 2 for
a flag, 2 for an emoji followed by U+FE0F or an emoji modifier, 1 for a
character that starts with a mark or joiner, and otherwise the width of its
first scalar.

## Whole strings

| Word | Stack | Meaning |
|------|-------|---------|
| `GR-SWIDTH` | `( addr u -- width )` | Display width in cells |
| `GR-COUNT` | `( addr u -- n )` | Number of characters |
| `GR-NEXT-BOUNDARY` | `( addr u off -- off' )` | First boundary after byte offset `off`, or `u` |
| `GR-PREV-BOUNDARY` | `( addr u off -- off' )` | Last boundary before byte offset `off`, or 0 |

Each has a `-WITH` form that takes a caller cursor as its last argument.
The boundary words keep tabs as themselves, as an edited line does.  The
plain forms share one module cursor and are guarded in `GUARDED` builds.

## Cost

Printable ASCII needs no table lookup: the string words scan the bytes and
count one cell per byte, about 200 guest steps per byte.  Other text costs
decoding (with an inline path for well-formed two- and three-byte
sequences), one table load for Basic Multilingual Plane scalars, and the
segmentation shortcut: about 3,400 guest steps per scalar for Hebrew,
Chinese, and accented Latin, measured by `test_unicode_text.py`.

## Tests

`local_testing/test_unicode_text.py` runs every case in Unicode's
`GraphemeBreakTest.txt` through the Forth segmenter, compares characters
and widths of a set of mixed samples with a Python reference of the
contract, and checks boundaries, replacement, and the ASCII fast path.
