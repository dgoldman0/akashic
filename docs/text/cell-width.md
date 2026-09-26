# akashic-cell-width — Terminal Cell Widths

Widths of scalars and strings on the terminal cell grid, following the
shared text contract
[`docs/rich-terminal/APT-1-TEXT.md`](../rich-terminal/APT-1-TEXT.md)
Section 4.  The data comes from the Unicode 15.1.0 tables generated into
`text/unicode-tables.f`; this module keeps no tables of its own.

```forth
REQUIRE text/cell-width.f
```

`PROVIDED akashic-cell-width` — safe to include multiple times.

---

## Public API

### CW-WIDTH

```
( cp -- n )
```

The scalar width `w(s)`: 0 for General_Category `Mn`, `Me`, `Cf` and
Hangul medial vowels and final consonants; 2 for East_Asian_Width `W` or
`F`; 1 otherwise.  A `Cc`, `Zl`, or `Zp` scalar reports 1, the width of
the U+FFFD that replaces it on the grid.

```forth
65 CW-WIDTH        \ → 1  ('A')
0x0301 CW-WIDTH    \ → 0  (combining acute accent)
0x4E00 CW-WIDTH    \ → 2  (CJK ideograph)
```

A scalar's width is not a character's width: `e` followed by U+0301 is one
character one cell wide, and a flag is two regional indicators of width 1
that together take two cells.  Use `CW-SWIDTH`, or `GR-C-WIDTH` from
[grapheme](grapheme.md), for anything that is drawn.

### CW-SWIDTH

```
( addr u -- n )
```

Display width of a UTF-8 string: the sum of its characters' widths `W(c)`.
Printable ASCII takes a byte-scan fast path.  This is `GR-SWIDTH`.

```forth
\ "Aé中" = 41 C3A9 E4B8AD → 1 + 1 + 2 = 4
```

### CW-CELL-CP

```
( cp -- cp' )
```

Projects one codepoint onto a single isolated width-one cell: anything that
is not a terminal-safe scalar of width 1 becomes U+FFFD.  This is a bridge
for the screen, which does not yet store wide and cluster cells, and it goes
away with that change.  `CW-CELL-CP-WITH ( cp state -- cp' )` is the same
word; its state argument, of `CW-STATE-SIZE` bytes, is unused.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `CW-WIDTH` | `( cp -- 0\|1\|2 )` | Scalar width `w(s)` |
| `CW-SWIDTH` | `( addr u -- n )` | String width, summed over characters |
| `CW-CELL-CP` | `( cp -- cp' )` | Bridge: project to one width-one cell |
| `CW-CELL-CP-WITH` | `( cp state -- cp' )` | Same; state unused |
| `CW-STATE-SIZE` | `( -- 8 )` | Bytes of (unused) projection state |

---

## Dependencies

- `text/unicode-props.f` — `UP-PROPS`, `UP-WIDTH`, `UP-INVALID?`
- `text/grapheme.f` — `GR-SWIDTH`
- `text/utf8.f` — `UTF8-DISPLAY-CP`, `UTF8-REPLACEMENT`

## Concurrency

`CW-WIDTH` and `CW-CELL-CP` are pure reads of immutable tables.
`CW-SWIDTH` is `GR-SWIDTH` and carries that module's guard.
