#!/usr/bin/env python3
"""math/fp32.f on MegaPad's scalar FP32 words.

Every word is compared bit for bit with MegaPad's exact IEEE 754 oracle
(shared/ieee_fp.py): arithmetic is correctly rounded, to nearest even
unless FPCSR says otherwise; comparisons are false when either value is
NaN; MIN and MAX propagate NaN and order -0 below +0; FP16 widening is
exact, subnormals included; and the conversions to integers and fixed
point truncate toward zero, give 0 for NaN, and saturate.
"""

from __future__ import annotations

import random
import re
import struct

from forth_snapshot import ForthSnapshot, program_output
from numeric_reference import fp


F32, F16 = fp.FP32, fp.FP16
MASK64 = (1 << 64) - 1
ONE, TWO16, TWO_M16 = 0x3F800000, 0x47800000, 0x37800000

SNAPSHOT = ForthSnapshot(
    ("math/fp32.f",),
    prelude=(': T-X ( u -- ) ." @" HEX U. DECIMAL ;',),
)


def f32(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", value))[0]


SPECIALS = [
    0x00000000, 0x80000000,              # zeros
    0x00000001, 0x80000001, 0x007FFFFF,  # subnormals
    0x00800000, 0x80800000,              # smallest normals
    0x3F800000, 0xBF800000, 0x3F800001, 0x40490FDB,
    0x7F7FFFFF, 0xFF7FFFFF,              # largest finite
    0x7F800000, 0xFF800000,              # infinities
    0x7FC00000, 0xFFC00000, 0x7FC12345,  # quiet NaNs
    0x7F800001,                          # signalling NaN
    f32(0.1), f32(-2.5), f32(3.0), f32(65504.0), f32(65520.0),
    f32(1e10), f32(-1e-30),
]


def values(seed: str, count: int) -> list[int]:
    rng = random.Random(seed)
    out = list(SPECIALS)
    for _ in range(count):
        if rng.random() < 0.5:
            out.append(rng.getrandbits(32))
        else:
            out.append(f32(rng.uniform(-1000.0, 1000.0)))
    return out


def run(expressions: list[str]) -> list[int]:
    """Run expressions that each leave one result; return the results."""

    lines, line = [], ""
    for expression in expressions:
        part = f"{expression} T-X "
        if len(line) + len(part) > 200:
            lines.append(line)
            line = ""
        line += part
    lines += [line, 'DEPTH ." @" .']
    text = program_output(SNAPSHOT.run(lines), lines)
    results = [int(value, 16) for value in re.findall(r"@([0-9A-F]+) ", text)]
    assert results[-1] == 0, "stack not empty"
    assert len(results) == len(expressions) + 1, text[-400:]
    return results[:-1]


def hexed(value: int) -> str:
    return f"0x{value & MASK64:X}"


def check(cases: list[tuple[str, int]]) -> None:
    got = run([expression for expression, _ in cases])
    bad = [
        (expression, f"{want:#x}", f"{result:#x}")
        for (expression, want), result in zip(cases, got)
        if result != want & MASK64
    ]
    assert not bad, bad[:10]


# ---------------------------------------------------------------------------
# Arithmetic
# ---------------------------------------------------------------------------

def test_arithmetic_is_correctly_rounded() -> None:
    xs = values("arith", 40)
    rng = random.Random("pairs")
    pairs = [(a, b) for a in SPECIALS for b in SPECIALS]
    pairs += [(rng.choice(xs), rng.choice(xs)) for _ in range(300)]
    cases = []
    for a, b in pairs:
        cases += [
            (f"{hexed(a)} {hexed(b)} FP32-ADD", fp.add(F32, a, b)[0]),
            (f"{hexed(a)} {hexed(b)} FP32-SUB", fp.sub(F32, a, b)[0]),
            (f"{hexed(a)} {hexed(b)} FP32-MUL", fp.mul(F32, a, b)[0]),
            (f"{hexed(a)} {hexed(b)} FP32-DIV", fp.div(F32, a, b)[0]),
        ]
    for a in xs:
        cases += [
            (f"{hexed(a)} FP32-SQRT", fp.sqrt(F32, a)[0]),
            (f"{hexed(a)} FP32-RECIP", fp.div(F32, ONE, a)[0]),
        ]
    for _ in range(300):
        a, b, c = rng.choice(xs), rng.choice(xs), rng.choice(xs)
        cases.append((f"{hexed(a)} {hexed(b)} {hexed(c)} FP32-FMA", fp.fma(F32, a, b, c)[0]))
    # One rounding: a*b needs 25 bits, so rounding it before adding c
    # would lose its last bit.
    a, b, c = f32(1.0 + 2.0 ** -12), f32(1.0 + 2.0 ** -12), f32(-1.0)
    cases.append((f"{hexed(a)} {hexed(b)} {hexed(c)} FP32-FMA", fp.fma(F32, a, b, c)[0]))
    check(cases)


def test_arithmetic_follows_the_fpcsr_rounding_mode() -> None:
    xs = values("modes", 30)
    rng = random.Random("modes")
    cases = []
    for rm in (fp.RTZ, fp.RDN, fp.RUP):
        for _ in range(40):
            a, b = rng.choice(xs), rng.choice(xs)
            cases.append((
                f"{rm} FPCSR! {hexed(a)} {hexed(b)} FP32-MUL 0 FPCSR!",
                fp.mul(F32, a, b, rm)[0],
            ))
    check(cases)


# ---------------------------------------------------------------------------
# Comparisons and sign
# ---------------------------------------------------------------------------

def _less(a: int, b: int, equal: bool) -> int:
    if fp.is_nan(F32, a) or fp.is_nan(F32, b):
        return 0
    x, y = fp.to_double(F32, a), fp.to_double(F32, b)
    return -1 if (x < y or (equal and x == y)) else 0


def test_comparisons_min_and_max() -> None:
    xs = values("compare", 20)
    pairs = [(a, b) for a in xs for b in xs[:30]]
    cases = []
    for a, b in pairs:
        eq = 0 if fp.is_nan(F32, a) or fp.is_nan(F32, b) else (
            -1 if fp.to_double(F32, a) == fp.to_double(F32, b) else 0)
        cases += [
            (f"{hexed(a)} {hexed(b)} FP32<", _less(a, b, False)),
            (f"{hexed(a)} {hexed(b)} FP32>", _less(b, a, False)),
            (f"{hexed(a)} {hexed(b)} FP32<=", _less(a, b, True)),
            (f"{hexed(a)} {hexed(b)} FP32>=", _less(b, a, True)),
            (f"{hexed(a)} {hexed(b)} FP32=", eq),
            (f"{hexed(a)} {hexed(b)} FP32-MIN", fp.minimum(F32, a, b)),
            (f"{hexed(a)} {hexed(b)} FP32-MAX", fp.maximum(F32, a, b)),
        ]
    check(cases)


def test_sign_words_change_only_the_sign_bit() -> None:
    cases = []
    for a in values("sign", 10):
        cases += [
            (f"{hexed(a)} FP32-NEGATE", a ^ 0x80000000),
            (f"{hexed(a)} FP32-ABS", a & 0x7FFFFFFF),
            (f"{hexed(a)} FP32-0=", -1 if a & 0x7FFFFFFF == 0 else 0),
        ]
    check(cases)


# ---------------------------------------------------------------------------
# Conversions
# ---------------------------------------------------------------------------

def test_fp16_conversions_are_exact_or_correctly_rounded() -> None:
    halves = list(range(0, 0x10000, 97)) + [
        0x0001, 0x03FF, 0x0400, 0x7BFF, 0x7C00, 0x7C01, 0x7E00, 0x8001, 0x83FF, 0xFC00,
    ]
    narrow = values("narrow", 60) + [
        f32(2.0 ** -24), f32(2.0 ** -25), f32(3 * 2.0 ** -25), f32(2.0 ** -14 - 2.0 ** -25),
        f32(65519.0), f32(65520.0), f32(-65504.0),
    ]
    cases = [(f"{h:#x} FP16>FP32", fp.convert(F32, F16, h)[0]) for h in halves]
    cases += [(f"{hexed(x)} FP32>FP16", fp.convert(F16, F32, x)[0]) for x in narrow]
    check(cases)


def test_integer_and_fixed_point_conversions() -> None:
    xs = values("ints", 60) + [
        f32(2.0 ** 31), f32(-(2.0 ** 31)), f32(2.0 ** 62), f32(2.0 ** 63), f32(-(2.0 ** 63)),
        f32(2.0 ** 47), f32(-0.99), f32(1.5 * 2.0 ** -16), f32(2.0 ** -17),
    ]
    rng = random.Random("ints")
    ints = [0, 1, -1, (1 << 24) + 1, (1 << 24) + 3, -((1 << 24) + 3), 123456789,
            (1 << 63) - 1, -(1 << 63)] + [rng.getrandbits(64) - (1 << 63) for _ in range(40)]
    ints += [rng.randrange(-(1 << 40), 1 << 40) for _ in range(40)]

    def fixed(x: int) -> int:
        return fp.to_int(F32, fp.mul(F32, x, TWO16)[0], 64, True, fp.RTZ)[0]

    def unfixed(n: int) -> int:
        return fp.mul(F32, fp.from_int(F32, n)[0], TWO_M16)[0]

    cases = []
    for x in xs:
        cases += [
            (f"{hexed(x)} FP32>INT", fp.to_int(F32, x, 64, True, fp.RTZ)[0]),
            (f"{hexed(x)} FP32>FX", fixed(x)),
        ]
    for n in ints:
        cases += [
            (f"{hexed(n)} INT>FP32", fp.from_int(F32, n)[0]),
            (f"{hexed(n)} FX>FP32", unfixed(n)),
        ]
    check(cases)


def test_fixed_point_conversions_match_their_definitions() -> None:
    """FP32>FX is x * 65536 truncated; FX>FP32 is n / 65536 rounded."""

    check([
        (f"{hexed(f32(1.5))} FP32>FX", 98304),
        (f"{hexed(f32(-1.5))} FP32>FX", -98304),
        (f"{hexed(f32(2.0 ** -17))} FP32>FX", 0),
        (f"{hexed(f32(-0.99))} FP32>FX", -64880),
        ("0x7FC00000 FP32>FX", 0),
        ("0x7F800000 FP32>FX", (1 << 63) - 1),
        ("0xFF800000 FP32>FX", -(1 << 63)),
        ("98304 FX>FP32", f32(1.5)),
        ("-1 FX>FP32", f32(-(2.0 ** -16))),
    ])
