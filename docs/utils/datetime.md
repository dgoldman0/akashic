# akashic-datetime — Date / Time Vocabulary for KDOS / Megapad-64

Integer-only POSIX epoch utilities: conversion between epoch seconds and
broken-down (year, month, day, hour, minute, second) values, ISO 8601
formatting and parsing, and live RTC clock access.

```forth
REQUIRE datetime.f
```

`PROVIDED akashic-datetime` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Leap Year](#leap-year)
- [Epoch → Broken-Down](#epoch--broken-down)
- [Broken-Down → Epoch](#broken-down--epoch)
- [Formatting](#formatting)
- [Parsing](#parsing)
- [RTC / Current Time](#rtc--current-time)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Integer only** | All arithmetic uses 64-bit integers; no floating point. |
| **UTC everywhere** | Epoch = seconds since 1970-01-01T00:00:00Z. No time-zone support. |
| **BIOS RTC** | `DT-NOW*` words call `EPOCH@` (MMIO `0xFFFF_FF00_0000_0B08`). |
| **No allocation** | Formatting writes into caller-supplied `(dst max)` buffers. |
| **Prefix convention** | Public API: `DT-`. Internal helpers: `_DT-` / `_DTP-`. |

---

## Constants

| Word | Value | Meaning |
|------|-------|---------|
| `_DT-SPD` | 86 400 | Seconds per day |
| `_DT-SPH` | 3 600 | Seconds per hour |
| `_DT-SPM` | 60 | Seconds per minute |

Tables (internal):

| Word | Description |
|------|-------------|
| `_DT-DBM` | Days-before-month (non-leap), indexed 1–12 |
| `_DT-DIM` | Days-in-month (non-leap), indexed 1–12 |

---

## Leap Year

### `DT-LEAP?`

```forth
DT-LEAP? ( year -- flag )
```

Gregorian leap-year test.  Returns `-1` (true) for leap years, `0`
otherwise.

```forth
2024 DT-LEAP?  \ → -1
1900 DT-LEAP?  \ → 0
2000 DT-LEAP?  \ → -1
```

### `_DT-DPY`

```forth
_DT-DPY ( year -- days )
```

Days in year — 366 for leap years, 365 otherwise.

### `_DT-DIM@`

```forth
_DT-DIM@ ( month year -- days )
```

Days in month (1-based), with leap-February handling.

---

## Epoch → Broken-Down

### `DT-EPOCH>YMD`

```forth
DT-EPOCH>YMD ( epoch -- year month day )
```

Convert Unix epoch seconds to calendar date.  Algorithm: count off
whole years from 1970, then whole months, remainder + 1 = day.

```forth
0         DT-EPOCH>YMD   \ → 1970 1 1
946684800 DT-EPOCH>YMD   \ → 2000 1 1
951782400 DT-EPOCH>YMD   \ → 2000 2 29
```

### `DT-EPOCH>HMS`

```forth
DT-EPOCH>HMS ( epoch -- hour min sec )
```

Extract time-of-day from epoch seconds via modular arithmetic.

```forth
1718465400 DT-EPOCH>HMS   \ → 15 30 0
```

---

## Broken-Down → Epoch

### `DT-YMD>EPOCH`

```forth
DT-YMD>EPOCH ( year month day -- epoch )
```

Calendar date at midnight UTC → epoch seconds.  Adds days for
complete years (1970 .. year−1), days-before-month, leap adjustment,
and remaining days, then multiplies by 86 400.

```forth
1970 1  1  DT-YMD>EPOCH   \ → 0
2000 2 29  DT-YMD>EPOCH   \ → 951782400
```

Round-trip property:

```forth
epoch DT-EPOCH>YMD DT-YMD>EPOCH  \ → epoch (at midnight)
```

---

## Formatting

All formatting words share the signature:

```forth
( epoch dst max -- written )
```

They write formatted text into the caller's buffer at `dst` (up to
`max` bytes) and return the number of bytes written.

### `DT-DATE`

Format epoch as `YYYY-MM-DD`.

```forth
1718409600 PAD 16 DT-DATE    \ PAD ← "2024-06-15", returns 10
```

### `DT-TIME`

Format epoch as `HH:MM:SS`.

```forth
1718465400 PAD 16 DT-TIME    \ PAD ← "15:30:00", returns 8
```

### `DT-ISO8601`

Format epoch as `YYYY-MM-DDTHH:MM:SSZ`.

```forth
1718465400 PAD 32 DT-ISO8601   \ PAD ← "2024-06-15T15:30:00Z", returns 20
```

---

## Parsing

### `DT-PARSE-ISO`

```forth
DT-PARSE-ISO ( addr len -- epoch ior )
```

Parse an ISO 8601 date-time string (`YYYY-MM-DDTHH:MM:SS` with
optional trailing `Z`) and return the epoch seconds.

`ior` = 0 on success, −1 on failure.

```forth
S" 2024-06-15T15:30:00Z" DT-PARSE-ISO   \ → 1718465400 0
S" bad" DT-PARSE-ISO                     \ → 0 -1
```

---

## RTC / Current Time

### `DT-NOW-MS`

```forth
DT-NOW-MS ( -- epoch-ms )
```

Read the hardware RTC via `EPOCH@` and return the epoch in
**milliseconds** (64-bit).

### `DT-NOW-S`

```forth
DT-NOW-S ( -- epoch )
```

Read the hardware RTC and return epoch **seconds** (integer
division: `EPOCH@ 1000 /`).

### `DT-NOW`

```forth
DT-NOW ( -- epoch )
```

Alias for `DT-NOW-S`.  Default resolution is seconds.

```forth
DT-NOW PAD 32 DT-ISO8601   \ format the current time
```

---

## Quick Reference

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `DT-LEAP?` | `( year -- flag )` | Gregorian leap-year test |
| `DT-EPOCH>YMD` | `( epoch -- year month day )` | Epoch → calendar date |
| `DT-EPOCH>HMS` | `( epoch -- hour min sec )` | Epoch → time of day |
| `DT-YMD>EPOCH` | `( year month day -- epoch )` | Calendar date → epoch |
| `DT-DATE` | `( epoch dst max -- written )` | Format `YYYY-MM-DD` |
| `DT-TIME` | `( epoch dst max -- written )` | Format `HH:MM:SS` |
| `DT-ISO8601` | `( epoch dst max -- written )` | Format `YYYY-MM-DDTHH:MM:SSZ` |
| `DT-PARSE-ISO` | `( addr len -- epoch ior )` | Parse ISO 8601 |
| `DT-NOW-MS` | `( -- epoch-ms )` | Current time in milliseconds |
| `DT-NOW-S` | `( -- epoch )` | Current time in seconds |
| `DT-NOW` | `( -- epoch )` | Alias for `DT-NOW-S` |
