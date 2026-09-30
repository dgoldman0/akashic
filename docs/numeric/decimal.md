# akashic-numeric-decimal — Decimal text for FP32 and FP64

Converts FP32 and FP64 values to decimal text and back, exactly.

```forth
REQUIRE numeric/decimal.f
```

`PROVIDED akashic-numeric-decimal`. Requires `numeric/array.f`.

The module holds no state. Text goes to, or comes from, a caller's buffer,
and scratch comes from a caller workspace, so any core may use the words.

---

## Words

| Word | Stack | Result |
|---|---|---|
| `NDEC-WS-BYTES` | `( -- bytes )` | Workspace the words need (about 6 KiB) |
| `NDEC-FORMAT` | `( bits fmt addr cap ws -- len status )` | The shortest decimal that reads back as the same value |
| `NDEC-FIXED` | `( bits fmt places addr cap ws -- len status )` | The value rounded to `places` decimal places, ties to even |
| `NDEC-PARSE` | `( addr len fmt ws -- bits status )` | Decimal text read as the nearest value, ties to even |

`bits` is a value in format `fmt`, `NUM-FP32` or `NUM-FP64` (`array.md`).
`addr` and `cap` are the output buffer and its size in characters, and `ws`
is a workspace descriptor (`NWS-INIT`) of at least `NDEC-WS-BYTES`.

## Text

`NDEC-FORMAT` lays the digits out like Python's `repr`: `0.1`, `100.0`,
`1e-05`, `1.5e+16`, `-0.0`, `inf`, `-inf`, and `nan`. It uses fixed
notation when the first digit's exponent is from −4 to 15, and exponent
notation otherwise. The digits are the fewest that read back as the same
value; among those, the nearest to it.

`NDEC-FIXED` lays the value out like Python's `f"{x:.3f}"`: at least one
digit before the point, then exactly `places` digits, and no point when
`places` is 0. A negative value keeps its minus sign even when it rounds to
zero, so −0.001 to two places is `-0.00`. It gives `inf`, `-inf`, or `nan`
for those values. A value's exact decimal expansion is finite, so every
digit is exact before the one rounding.

`NDEC-PARSE` reads an optional sign, then digits with an optional decimal
point and at least one digit, then an optional exponent: `e` or `E`, an
optional sign, and digits. It also reads `inf`, `infinity`, and `nan` in any
case, with an optional sign. Anything else, including spaces, is
`NUM-E-SYNTAX`. Values beyond the format's range read as infinity, and
values below half its smallest subnormal read as zero, keeping the sign.

## Rounding

`NDEC-PARSE` rounds to nearest, ties to even, whatever the rounding mode in
`FPCSR` is, and leaves that mode as it found it. When the digits and the
power of ten are both exact in the format, it takes one rounded multiply or
divide. Otherwise it divides exactly, keeping up to 800 significant digits;
digits past those can only decide a tie, so it keeps a flag for whether any
of them is nonzero.

## Status

| Status | When |
|---|---|
| `NUM-OK` | Success |
| `NUM-E-FORMAT` | `fmt` is not FP32 or FP64 |
| `NUM-E-SPACE` | The workspace is too small, or the text did not fit in `cap` |
| `NUM-E-RANGE` | `places` is negative |
| `NUM-E-SYNTAX` | The text is not a decimal number |

When the text did not fit, `len` is still its full length, and the first
`cap` characters are written, so a caller can retry with a buffer of `len`.
A refused call returns `len` 0, or `bits` 0.

## Cost

Emulator cycles for typical FP64 calls: formatting `0.1` about 26 K,
a 17-digit value 130–170 K, and a value near the extremes of the range about
400 K; `NDEC-FIXED` to two places about 25 K; parsing `3.14159` about 12 K,
17 digits about 190 K, and `1e-300` about 1.4 M.
