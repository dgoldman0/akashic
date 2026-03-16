# akashic-cell-width — Unicode Cell-Width Lookup

Given a Unicode codepoint, returns the number of terminal cells it
occupies: 0 (combining/control), 1 (normal), or 2 (wide CJK,
fullwidth forms, some emoji).  Based on Unicode 15.1.

```forth
REQUIRE text/cell-width.f
```

`PROVIDED akashic-cell-width` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Public API](#public-api)
- [Lookup Tables](#lookup-tables)
- [Algorithm](#algorithm)
- [Quick Reference](#quick-reference)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Unicode 15.1** | Range tables derived from EAW + General Category properties. |
| **O(log n)** | Binary search over sorted range pairs. |
| **Fast ASCII** | `0x20`–`0x7E` → 1 without table lookup. |
| **Zero allocation** | Compile-time `CREATE` tables only. |
| **Prefix convention** | Public: `CW-`. Internal: `_CW-`. |

---

## Public API

### CW-WIDTH

```
( cp -- n )
```

Returns 0, 1, or 2 cells for a Unicode codepoint.

- **0** — combining marks, zero-width joiners, control characters
  (U+0000–U+001F, U+007F–U+009F, U+0300–U+036F, etc.)
- **1** — normal characters including all of ASCII printable
- **2** — CJK ideographs, fullwidth forms, wide emoji
  (U+1100–U+115F, U+2E80–U+303E, U+3040–U+9FFF, U+F900–U+FAFF,
  U+FE10–U+FE6F, U+FF01–U+FF60, U+20000–U+3FFFD, etc.)

```forth
65 CW-WIDTH        \ → 1  ('A')
0x0301 CW-WIDTH    \ → 0  (combining acute accent)
0x4E00 CW-WIDTH    \ → 2  (CJK ideograph)
```

### CW-SWIDTH

```
( addr u -- n )
```

Display width of a UTF-8 string in terminal cells.  Decodes
codepoints with `UTF8-DECODE` and sums their `CW-WIDTH` values.

```forth
\ "Aé中" = 41 C3A9 E4B8AD → 1 + 1 + 2 = 4
CREATE buf  7 ALLOT
65 buf C!  0xC3 buf 1+ C!  0xA9 buf 2 + C!
0xE4 buf 3 + C!  0xB8 buf 4 + C!  0xAD buf 5 + C!
buf 6 CW-SWIDTH   \ → 4
```

---

## Lookup Tables

### Zero-Width Table (`_CW-ZERO-TBL`)

~160 sorted `(start, end)` range pairs covering:

- C0/C1 controls (0x0000–0x001F, 0x007F–0x009F)
- Soft hyphen (0x00AD)
- Combining Diacritical Marks and script-specific combining marks
  (Arabic, Hebrew, Devanagari, Thai, Tibetan, etc.)
- Hangul Jungseong / Jongseong (0x1160–0x11FF)
- Variation selectors (0xFE00–0xFE0F, 0xE0100–0xE01EF)
- Zero-width space / joiner / non-joiner (0x200B–0x200F)
- Tags block (0xE0001–0xE007F)

### Wide Table (`_CW-WIDE-TBL`)

~50 sorted `(start, end)` range pairs covering:

- Hangul Jamo (0x1100–0x115F)
- CJK Radicals, Kangxi, ideograph blocks
- Hiragana, Katakana (0x3040–0x30FF)
- CJK Unified Ideographs (0x4E00–0x9FFF)
- CJK Compatibility Ideographs
- Fullwidth forms (0xFF01–0xFF60, 0xFFE0–0xFFE6)
- Supplementary Ideographic Plane (0x20000–0x3FFFD)

---

## Algorithm

1. **ASCII fast path**: `0x20 ≤ cp ≤ 0x7E` → return 1.
2. **Zero-width check**: binary search `_CW-ZERO-TBL` → return 0.
3. **Wide check**: binary search `_CW-WIDE-TBL` → return 2.
4. **Default**: return 1.

Binary search (`_CW-BSEARCH`) runs in O(log n) over `(start, end)`
pairs: each entry is 2 cells (16 bytes); checks `cp >= start AND
cp <= end`.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `CW-WIDTH` | `( cp -- 0\|1\|2 )` | Cell width of a codepoint |
| `CW-SWIDTH` | `( addr u -- n )` | Display width of UTF-8 string |

---

## Dependencies

- `text/utf8.f` — `UTF8-DECODE` (used by `CW-SWIDTH`)

## Consumers

- Akashic Pad — cursor positioning and line-wrap calculations
- `tui/draw.f` — display-width aware text output (planned)

## Internal State

Module-level `VARIABLE`s prefixed `_CB-`:

- `_CB-LO`, `_CB-HI`, `_CB-MID` — binary search cursors

Not reentrant without the `GUARDED` guard section.
