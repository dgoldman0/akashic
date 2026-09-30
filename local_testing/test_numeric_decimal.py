#!/usr/bin/env python3
"""numeric/decimal.f: decimal text for FP32 and FP64 values.

FP64 results are compared with Python, whose repr, f-strings, and float()
are correctly rounded: NDEC-FORMAT must equal repr(x), NDEC-FIXED must
equal f"{x:.{p}f}", and NDEC-PARSE must equal float(s), bit for bit.  FP32
results are compared with numpy's shortest float32 digits and with exact
rational arithmetic.  Every formatted value must read back as the same
bits.
"""

from __future__ import annotations

import math
import random
import re
import struct
from decimal import ROUND_HALF_EVEN, Decimal, localcontext
from fractions import Fraction

import numpy as np

from forth_snapshot import ForthSnapshot, program_output


FP32, FP64 = 6, 7
NUM_OK, E_FORMAT, E_SPACE, E_RANGE, E_SYNTAX = 0, 1, 4, 5, 8
OUT_CAP = 4096
IN_BYTES = 1 << 20
LAYOUT = {FP32: (23, 127, 32), FP64: (52, 1023, 64)}   # fraction bits, bias, width

SNAPSHOT = ForthSnapshot(
    ("numeric/decimal.f",),
    prelude=(
        f"CREATE T-OUT {OUT_CAP} ALLOT",
        "CREATE T-WS NWS-SIZE ALLOT",
        "CREATE T-SMALL NWS-SIZE ALLOT",
        "HBW-TALIGN NDEC-WS-BYTES HBW-ALLOT DUP NDEC-WS-BYTES T-WS NWS-INIT DROP"
        " 64 T-SMALL NWS-INIT DROP",
        f"{IN_BYTES} 64 + XMEM-ALLOT 63 + -64 AND CONSTANT T-IN",
        ': T-TEXT ( len status -- ) ." @S:" . DUP ." @L:" . ." ["'
        f' T-OUT SWAP {OUT_CAP} MIN TYPE ." ]" CR ;',
        ': T-R ( bits status -- ) ." @S:" . ." @B:" HEX U. DECIMAL CR ;',
    ),
)
TEXT = re.compile(r"@S:(-?\d+) @L:(\d+) \[(.*?)\]")
BITS = re.compile(r"@S:(-?\d+) @B:([0-9A-F]+) ")
_IN_ADDR: list[int] = []


# ---------------------------------------------------------------------------
# Values and oracles
# ---------------------------------------------------------------------------

def f64(value: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", value))[0]


def from64(bits: int) -> float:
    return struct.unpack("<d", struct.pack("<Q", bits))[0]


def from32(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def nearest(q: Fraction, fmt: int) -> int:
    """The bits of the value of fmt nearest q, ties to even."""

    frac, bias, width = LAYOUT[fmt]
    sign = 1 if q < 0 else 0
    q = abs(q)
    inf = (2 * bias + 1) << frac
    bits = 0
    if q:
        x = q.numerator.bit_length() - q.denominator.bit_length()
        if Fraction(2) ** x > q:
            x -= 1
        if x > bias:
            bits = inf
        else:
            xe = max(x, 1 - bias)
            scaled = q / Fraction(2) ** (xe - frac)
            m = scaled.numerator // scaled.denominator
            rest = scaled - m
            if rest > Fraction(1, 2) or (rest == Fraction(1, 2) and m % 2):
                m += 1
            bits = min(((xe + bias - 1) << frac) + m, inf)
    return bits | (sign << (width - 1))


def exact_text(q: Fraction) -> str:
    """q, whose denominator is a power of two, as an exact decimal."""

    k = q.denominator.bit_length() - 1
    assert q.denominator == 1 << k
    digits = str(abs(q.numerator) * 5 ** k).rjust(k + 1, "0")
    text = digits[:-k] + "." + digits[-k:] if k else digits
    return ("-" if q < 0 else "") + text


def repr_layout(negative: bool, digits: str, x10: int) -> str:
    """Python's repr layout for significant digits whose first weighs 10^x10."""

    sign = "-" if negative else ""
    n = len(digits)
    if -4 <= x10 < 16:
        if x10 >= 0:
            whole = (digits + "0" * max(0, x10 + 1 - n))[: x10 + 1]
            return f"{sign}{whole}.{digits[x10 + 1:] or '0'}"
        return f"{sign}0.{'0' * (-x10 - 1)}{digits}"
    mantissa = digits[0] + ("." + digits[1:] if n > 1 else "")
    return f"{sign}{mantissa}e{'-' if x10 < 0 else '+'}{abs(x10):02d}"


def fp32_repr(bits: int) -> str:
    value = np.frombuffer(struct.pack("<I", bits), dtype=np.float32)[0]
    if np.isnan(value):
        return "nan"
    if np.isinf(value):
        return "-inf" if value < 0 else "inf"
    if value == 0:
        return "-0.0" if bits >> 31 else "0.0"
    text = np.format_float_scientific(value, unique=True, trim="-")
    mantissa, exponent = text.lstrip("-").split("e")
    digits = mantissa.replace(".", "").rstrip("0")
    return repr_layout(bool(bits >> 31), digits, int(exponent))


def fixed_exact(bits: int, fmt: int, places: int) -> str:
    """The value rounded to places decimal places, ties to even."""

    value = from32(bits) if fmt == FP32 else from64(bits)
    if math.isnan(value):
        return "nan"
    if math.isinf(value):
        return "-inf" if value < 0 else "inf"
    with localcontext() as context:
        context.prec = 2000
        quantum = Decimal(1).scaleb(-places)
        text = format(Decimal(value).quantize(quantum, rounding=ROUND_HALF_EVEN), "f")
    negative = bits >> (LAYOUT[fmt][2] - 1)
    if negative and not text.startswith("-"):
        text = "-" + text
    return text


def finite_values(fmt: int, seed: str, count: int) -> list[int]:
    """Special, boundary, and random finite values of fmt."""

    frac, bias, width = LAYOUT[fmt]
    rng = random.Random(seed)
    top = (2 * bias + 1) << frac
    values = [1, 2, (1 << frac) - 1, 1 << frac, top - 1,
              (bias << frac), ((bias - 1) << frac) | 0x1234]
    if fmt == FP64:
        values += [f64(x) for x in (0.1, 0.2, 0.3, 1 / 3, 2 / 3, 123456.789, 1e15, 1e16,
                                    9007199254740993.0, 1e22, 1e23, 5e-324, 2.5e-308,
                                    0.0001, 0.00001, 1e-7, 123e-20, 1.7976931348623157e308)]
        values += [f64(10.0 ** k) for k in range(-300, 301, 13)]
    else:
        values += [struct.unpack("<I", struct.pack("<f", x))[0]
                   for x in (0.1, 0.2, 1 / 3, 123456.789, 1e10, 3.4028235e38, 1e-40,
                             16777217.0, 0.0001, 0.00001)]
    for _ in range(count):
        bits = rng.getrandbits(width - 1)
        if bits < top:
            values.append(bits)
    values = [v for v in values if v < top]
    return values + [v | (1 << (width - 1)) for v in values[::3]]


# ---------------------------------------------------------------------------
# Running Forth
# ---------------------------------------------------------------------------

def in_addr() -> int:
    if not _IN_ADDR:
        lines = ["T-IN U."]
        text = program_output(SNAPSHOT.run(lines), lines)
        _IN_ADDR.append(int(re.findall(r"\d+", text)[0]))
    return _IN_ADDR[0]


def run(lines: list[str], texts: list[bytes] = ()) -> str:
    base = in_addr()

    def setup(system) -> None:
        offset = 0
        for text in texts:
            if text:
                system._raw_mem_write_span(base + offset, text)
            offset += len(text)

    lines = lines + ['DEPTH ." @D:" . CR']
    output = program_output(SNAPSHOT.run(lines, setup=setup), lines)
    assert "@D:0 " in output, output[-500:]
    return output


def formats(calls: list[str]) -> list[tuple[int, int, str]]:
    text = run([f"{call} T-TEXT" for call in calls])
    found = [(int(s), int(n), t) for s, n, t in TEXT.findall(text)]
    assert len(found) == len(calls), text[-500:]
    return found


def parses(strings: list[str], fmt: int) -> list[tuple[int, int]]:
    base = in_addr()
    texts = [s.encode() for s in strings]
    lines, offset = [], 0
    for text in texts:
        lines.append(f"{base + offset} {len(text)} {fmt} T-WS NDEC-PARSE T-R")
        offset += len(text)
    assert offset <= IN_BYTES
    output = run(lines, texts)
    found = [(int(s), int(b, 16)) for s, b in BITS.findall(output)]
    assert len(found) == len(strings), output[-500:]
    return found


def check_texts(calls: list[str], wants: list[str]) -> None:
    bad = [
        (call, want, got, status)
        for call, want, (status, length, got) in zip(calls, wants, formats(calls))
        if (status, length, got) != (NUM_OK, len(want), want)
    ]
    assert not bad, bad[:8]


def check_parses(strings: list[str], fmt: int, wants: list[int]) -> None:
    bad = [
        (s[:60], hex(want), hex(got), status)
        for s, want, (status, got) in zip(strings, wants, parses(strings, fmt))
        if (status, got) != (NUM_OK, want)
    ]
    assert not bad, bad[:8]


# ---------------------------------------------------------------------------
# Shortest digits
# ---------------------------------------------------------------------------

def test_fp64_format_matches_python_repr() -> None:
    values = finite_values(FP64, "fmt64", 300)
    values += [0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000000000,
               0xFFF8000000000000, 0x7FF0000000000001, 0, 0x8000000000000000]
    calls = [f"{v} {FP64} T-OUT {OUT_CAP} T-WS NDEC-FORMAT" for v in values]
    check_texts(calls, [repr(from64(v)) for v in values])


def test_fp32_format_gives_the_shortest_digits() -> None:
    values = finite_values(FP32, "fmt32", 300)
    values += [0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000, 0, 0x80000000]
    calls = [f"{v} {FP32} T-OUT {OUT_CAP} T-WS NDEC-FORMAT" for v in values]
    check_texts(calls, [fp32_repr(v) for v in values])


def test_formatted_values_read_back_as_the_same_bits() -> None:
    lines, wants = [], []
    for fmt in (FP32, FP64):
        for v in finite_values(fmt, f"trip{fmt}", 120):
            lines.append(
                f"{v} {fmt} T-OUT {OUT_CAP} T-WS NDEC-FORMAT DROP"
                f" T-OUT SWAP {fmt} T-WS NDEC-PARSE T-R"
            )
            wants.append(v)
    found = [(int(s), int(b, 16)) for s, b in BITS.findall(run(lines))]
    assert found == [(NUM_OK, v) for v in wants]


# ---------------------------------------------------------------------------
# Fixed places
# ---------------------------------------------------------------------------

def test_fixed_places_match_python() -> None:
    rng = random.Random("fixed")
    values = finite_values(FP64, "fixed64", 60)
    values += [f64(x) for x in (0.125, 0.375, 2.5, 3.5, 0.5, 1.5, -0.001, 999.9996,
                                0.0005, 0.00049999999999999999, -0.0)]
    cases = [(v, rng.choice([0, 1, 2, 3, 5, 10, 17, 20])) for v in values]
    cases += [(f64(x), p) for x, p in ((0.125, 2), (0.375, 2), (2.5, 0), (3.5, 0), (0.5, 0),
                                        (1.5, 0), (-0.001, 2), (999.9996, 3), (1e22, 2),
                                        (5e-324, 3), (5e-324, 330), (1.7976931348623157e308, 0),
                                        (0.1, 60), (-0.0, 4))]
    cases += [(0x7FF0000000000000, 2), (0xFFF0000000000000, 0), (0x7FF8000000000000, 3)]
    calls = [f"{v} {FP64} {p} T-OUT {OUT_CAP} T-WS NDEC-FIXED" for v, p in cases]
    check_texts(calls, [f"{from64(v):.{p}f}" for v, p in cases])


def test_fp32_fixed_places_are_exact() -> None:
    rng = random.Random("fixed32")
    values = finite_values(FP32, "fixed32", 60)
    cases = [(v, rng.choice([0, 1, 2, 4, 8, 12])) for v in values]
    cases += [(0x3E000000, 2), (0x40200000, 0), (0x00000001, 50), (0x7F7FFFFF, 0)]
    calls = [f"{v} {FP32} {p} T-OUT {OUT_CAP} T-WS NDEC-FIXED" for v, p in cases]
    check_texts(calls, [fixed_exact(v, FP32, p) for v, p in cases])


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def decimal_strings(seed: str, count: int, emax: int) -> list[str]:
    rng = random.Random(seed)
    out = []
    for _ in range(count):
        digits = "".join(rng.choice("0123456789") for _ in range(rng.randint(1, 30)))
        point = rng.randint(0, len(digits))
        text = digits[:point] + "." + digits[point:] if rng.random() < 0.7 else digits
        if rng.random() < 0.8:
            text += rng.choice("eE") + rng.choice(["", "+", "-"]) + str(rng.randint(0, emax))
        out.append(rng.choice(["", "-", "+"]) + text)
    return out


def midpoints(fmt: int, seed: str, count: int) -> list[str]:
    """Exact decimals halfway between neighbouring values, and just off."""

    frac, bias, width = LAYOUT[fmt]
    rng = random.Random(seed)
    top = (2 * bias + 1) << frac
    out = []
    for _ in range(count):
        bits = rng.randrange(1, top - 1)
        if rng.random() < 0.2:
            bits = rng.randrange(1, 1 << frac)              # subnormal
        middle = (decode(bits, fmt) + decode(bits + 1, fmt)) / 2
        tiny = Fraction(1, 2 ** (middle.denominator.bit_length() + 30))
        out += [exact_text(middle), exact_text(middle + tiny), exact_text(middle - tiny)]
    return out


def decode(bits: int, fmt: int) -> Fraction:
    frac, bias, width = LAYOUT[fmt]
    be, f = bits >> frac, bits & ((1 << frac) - 1)
    m, e = (f, 1 - bias - frac) if be == 0 else (f | (1 << frac), be - bias - frac)
    return Fraction(m) * Fraction(2) ** e


def test_fp64_parse_matches_python_float() -> None:
    strings = decimal_strings("parse64", 250, 330)
    strings += [repr(from64(v)) for v in finite_values(FP64, "reparse", 60)]
    strings += midpoints(FP64, "mid64", 25)
    strings += ["0", "-0", "0.000", "000123", ".5", "5.", "1e308", "1.7976931348623157e308",
                "1.7976931348623158e308", "1.7976931348623159e308", "2e308", "4.9e-324",
                "2.4703282292062327e-324", "2.4703282292062328e-324", "1e-400", "1e400",
                "0e999999999", "1e999999999", "1e-999999999", "9007199254740993",
                "123456789012345678901234567890", "1" + "0" * 400 + "e-400",
                "0." + "0" * 300 + "1", "Inf", "-infinity", "INFINITY"]
    check_parses(strings, FP64, [f64(float(s)) for s in strings])


def test_fp32_parse_is_correctly_rounded() -> None:
    strings = decimal_strings("parse32", 250, 50)
    strings += midpoints(FP32, "mid32", 25)
    strings += ["3.4028235e38", "3.4028236e38", "3.40282357e38", "1e39", "1.4e-45",
                "7.006e-46", "7.0064923e-46", "1e-46", "16777217", "0.1", "-0"]
    signs = [1 << 31 if s.startswith("-") else 0 for s in strings]
    check_parses(strings, FP32, [nearest(abs(Fraction(s)), FP32) | sign
                                 for s, sign in zip(strings, signs)])


def test_nan_and_its_sign() -> None:
    found = parses(["nan", "NaN", "-nan"], FP64) + parses(["nan", "-NAN"], FP32)
    assert found == [(NUM_OK, 0x7FF8000000000000), (NUM_OK, 0x7FF8000000000000),
                     (NUM_OK, 0xFFF8000000000000), (NUM_OK, 0x7FC00000),
                     (NUM_OK, 0xFFC00000)]


def test_parse_refuses_malformed_text() -> None:
    bad = ["", "-", "+", ".", "-.", "e5", "1e", "1e+", "1e-", "1..2", "1.2.3", "abc", "+-1",
           " 1", "1 ", "1f", "0x10", "infinit", "nann", "1e5.5", "--1", "1_000"]
    assert parses(bad, FP64) == [(E_SYNTAX, 0)] * len(bad)


def test_parse_rounds_to_nearest_whatever_the_fpcsr_mode() -> None:
    strings = [b"0.1", b"1" + b"0" * 30 + b"1e-30", b"2.5e-320"]
    base = in_addr()
    lines, offset = [], 0
    for text in strings:
        lines.append(
            f"3 FPCSR! {base + offset} {len(text)} {FP64} T-WS NDEC-PARSE T-R"
            ' FPCSR@ 7 AND ." @M:" . CR 0 FPCSR!'
        )
        offset += len(text)
    output = run(lines, strings)
    found = [(int(s), int(b, 16)) for s, b in BITS.findall(output)]
    assert found == [(NUM_OK, f64(float(s.decode()))) for s in strings]
    assert re.findall(r"@M:(\d+)", output) == ["3"] * len(strings)


# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

def test_small_buffers_workspaces_and_bad_arguments() -> None:
    one_tenth = f64(0.1)
    calls = [
        f"{one_tenth} {FP64} T-OUT 3 T-WS NDEC-FORMAT",
        f"{one_tenth} {FP64} T-OUT 2 T-WS NDEC-FORMAT",
        f"{one_tenth} 5 T-OUT 99 T-WS NDEC-FORMAT",
        f"{one_tenth} {FP64} T-OUT 99 T-SMALL NDEC-FORMAT",
        f"{one_tenth} {FP64} -1 T-OUT 99 T-WS NDEC-FIXED",
        f"{one_tenth} {FP64} 2 T-OUT 3 T-WS NDEC-FIXED",
    ]
    found = formats(calls)
    # Past the capacity nothing is written, but the length is still counted.
    assert found[0] == (NUM_OK, 3, "0.1")
    assert found[1][:2] == (E_SPACE, 3) and found[1][2][:2] == "0."
    assert found[2][:2] == (E_FORMAT, 0)
    assert found[3][:2] == (E_SPACE, 0)
    assert found[4][:2] == (E_RANGE, 0)
    assert found[5][:2] == (E_SPACE, 4) and found[5][2][:3] == "0.1"
    assert parses(["1.5"], 5) == [(E_FORMAT, 0)]
