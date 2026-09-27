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

### CW-CHAR-WIDTH

```
( cp -- n )
```

The width `W(c)` of the character that is this one scalar: 0 when it is
Default_Ignorable (such a character takes no cell), 1 for a mark or joiner
with no base before it, and otherwise its `w(s)`.  A `Cc`, `Zl`, or `Zp`
scalar reports 1, the width of its U+FFFD.  The screen uses it to set a
one-scalar cell's `WIDE` bit.

```forth
0x4E00 CW-CHAR-WIDTH   \ → 2
0x0301 CW-CHAR-WIDTH   \ → 1  (a lone mark takes a cell)
0x200B CW-CHAR-WIDTH   \ → 0  (zero width space)
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `CW-WIDTH` | `( cp -- 0\|1\|2 )` | Scalar width `w(s)` |
| `CW-CHAR-WIDTH` | `( cp -- 0\|1\|2 )` | Width of a one-scalar character |
| `CW-SWIDTH` | `( addr u -- n )` | String width, summed over characters |

---

## Dependencies

- `text/unicode-props.f` — `UP-PROPS`, `UP-WIDTH`, `UP-INVALID?`,
  `UP-IGNORABLE?`
- `text/grapheme.f` — `GR-SWIDTH`

## Concurrency

`CW-WIDTH` and `CW-CHAR-WIDTH` are pure reads of immutable tables.
`CW-SWIDTH` is `GR-SWIDTH` and carries that module's guard.
