#!/usr/bin/env python3
"""utils/posix-tz.f against Python's zoneinfo applying the same TZ string.

The oracle is zoneinfo reading a TZif file that holds only the TZ string as
its footer, so it applies exactly that string's RFC 8536 rule to every
instant.  The real strings are the footers zic wrote into the system tz
database; the others cover negative and permanent daylight time, the two
day-number forms, seconds in offsets, and rule times outside 0..24 hours.

CPython's zoneinfo puts the zero-based day form one day early: it moves
"0" to December 31 and "59" to February 28 even in a leap year, where POSIX
counts day 0 as January 1 and day 59 as February 29.  That string is checked
against glibc instead, which follows POSIX there.  glibc in turn misreads
permanent daylight time in the first hour of each year, so zoneinfo stays
the oracle everywhere else.

Offsets are checked one second either side of every transition and at
spread instants; local-to-UTC conversion is checked every quarter hour
across each transition's gap or overlap and at its edges, against PEP 495
fold=0, which is RFC 5545's rule.
"""

from __future__ import annotations

import calendar
import io
import os
import random
import struct
import time
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from native_forth import NativeForth


ZONEINFO = Path("/usr/share/zoneinfo")
YEARS = (2040, 2041, 2042)

OK, INVALID, CAPACITY, SYNTAX, RANGE = 0, 1, 2, 3, 4
UNIQUE, OVERLAP, GAP = 0, 1, 2

REAL_ZONES = (
    "UTC", "America/New_York", "Europe/London", "Europe/Dublin",
    "Australia/Sydney", "Pacific/Auckland", "Pacific/Chatham",
    "Australia/Lord_Howe", "America/Nuuk", "Asia/Jerusalem",
    "America/Santiago", "Antarctica/Troll", "America/St_Johns",
    "Africa/Cairo", "America/Havana", "Asia/Kolkata", "Asia/Kathmandu",
    "America/Sao_Paulo", "Pacific/Kiritimati", "Pacific/Marquesas",
)

# String, its canonical form.
SYNTHETIC = (
    ("IST-1GMT0,M10.5.0,M3.5.0/1", "IST-1GMT0,M10.5.0,M3.5.0/1"),
    ("EST5EDT4,0/0,J365/25", "EST5EDT,0/0,J365/25"),
    ("<-03>3<-02>,J60,J300", "<-03>3<-02>,J60,J300"),
    ("<-03>3<-02>,59,299", "<-03>3<-02>,59,299"),
    ("<+0330>-3:30<+0430>,M3.4.6/24,M9.3.1/-24", "<+0330>-3:30<+0430>,M3.4.6/24,M9.3.1/-24"),
    ("AAA+3:15:07BBB2:00:30,M4.1.3/1:02:03,M10.5.2/-5:30", "AAA3:15:07BBB2:00:30,M4.1.3/1:02:03,M10.5.2/-5:30"),
)

# Strings that use the zero-based day form, checked against glibc.
GLIBC_ORACLE = ("<-03>3<-02>,59,299",)

MALFORMED = (
    "", "ES5", "EST", "EST5EDT", "EST5EDT,M3.2.0", "EST5EDT,M13.2.0,M11.1.0",
    "EST5EDT,M3.6.0,M11.1.0", "EST5EDT,M3.2.7,M11.1.0", "EST5EDT,M0.2.0,M11.1.0",
    "EST25", "EST5:60", "EST5:6", "EST5:30:6", "<AB>5", "<EST5", "<E S>5",
    "EST5EDT,J0,J365", "EST5EDT,J366,J1", "EST5EDT,366,0",
    "EST5EDT,M3.2.0/168,M11.1.0", "EST5 ", "EST5EDT,M3.2.0,M11.1.0x",
    "E1T5", "5EST", "EST5,M3.2.0,M11.1.0", "EST5EDT,M3.2.0/,M11.1.0",
    "ABCDEFGHIJKLMNOPQ5", "EST123",
)

PRELUDE = (
    "CREATE Z TZ-SIZE ALLOT",
    "CREATE OUT 256 ALLOT",
    ": SHOW3 ( a b c -- ) ROT . SWAP . . CR ;",
    ': SHOW-FORMAT ( -- ) Z OUT 256 TZ-FORMAT . ." [" OUT SWAP TYPE ." ]" CR ;',
)

SUITE = NativeForth(("utils/posix-tz.f",), prelude=PRELUDE)


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 3_000_000_000) -> list[str]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.strip() for line in output.replace("\r", "").split("\n") if line.strip()]


def numbers(line: str) -> list[int]:
    return [int(token) for token in line.split()]


def footer(zone: str) -> str:
    data = (ZONEINFO / zone).read_bytes()
    return data.rstrip(b"\n").rsplit(b"\n", 1)[-1].decode()


def parse_line(tz: str) -> str:
    return f'S" {tz}" Z TZ-PARSE . CR'


# ---------------------------------------------------------------------------
# Oracles
# ---------------------------------------------------------------------------

def footer_zone(tz: str) -> ZoneInfo:
    """zoneinfo applying exactly tz: a TZif v2 file with no transitions."""

    chars = b"UTC\0"
    counts = struct.pack(">6l", 0, 0, 0, 0, 1, len(chars))
    block = b"TZif2" + bytes(15) + counts + struct.pack(">lBB", 0, 0, 0) + chars
    data = block + block + b"\n" + tz.encode() + b"\n"
    return ZoneInfo.from_file(io.BytesIO(data), key=tz)


def zone_offset(zone: ZoneInfo, ts: int) -> tuple[int, bool]:
    """The offset and whether the daylight-named period is in force."""

    moment = datetime.fromtimestamp(ts, zone)
    return int(moment.utcoffset().total_seconds()), bool(moment.dst())


class GlibcZone:
    """glibc's localtime for one TZ string."""

    def __init__(self, tz: str) -> None:
        self.tz = tz

    def __call__(self, ts: int) -> tuple[int, bool]:
        saved = os.environ.get("TZ")
        os.environ["TZ"] = self.tz
        time.tzset()
        try:
            moment = time.localtime(ts)
            return moment.tm_gmtoff, bool(moment.tm_isdst)
        finally:
            if saved is None:
                del os.environ["TZ"]
            else:
                os.environ["TZ"] = saved
            time.tzset()


def oracle(tz: str):
    if tz in GLIBC_ORACLE:
        return GlibcZone(tz)
    zone = footer_zone(tz)
    return lambda ts: zone_offset(zone, ts)


def transitions(offset_at, year: int) -> list[int]:
    """Every instant in year where the oracle's offset changes."""

    start = calendar.timegm((year, 1, 1, 0, 0, 0))
    end = calendar.timegm((year + 1, 1, 1, 0, 0, 0))
    found = []
    previous = offset_at(start)
    t = start
    while t < end:
        step = min(3600, end - t)
        current = offset_at(t + step)
        if current != previous:
            low, high = t, t + step
            while high - low > 1:
                middle = (low + high) // 2
                if offset_at(middle) == previous:
                    low = middle
                else:
                    high = middle
            found.append(high)
            previous = current
        t += step
    return found


def instants(offset_at, years=YEARS) -> list[int]:
    chosen = set()
    rng = random.Random(1789)
    for year in years:
        for change in transitions(offset_at, year):
            chosen.update((change - 1, change, change + 1))
        first = calendar.timegm((year, 1, 1, 0, 0, 0))
        last = calendar.timegm((year + 1, 1, 1, 0, 0, 0))
        chosen.update(rng.randrange(first, last) for _ in range(40))
    return sorted(chosen)


def local_points(offset_at, years=YEARS):
    """Local seconds across each transition, with the offsets either side."""

    for year in years:
        for change in transitions(offset_at, year):
            before, _ = offset_at(change - 1)
            after, _ = offset_at(change)
            low = change + min(before, after)
            high = change + max(before, after)
            points = set(range(low - 7200, high + 7200, 900))
            points.update((low - 1, low, low + 1, high - 1, high, high + 1))
            for local in sorted(points):
                yield local, before, after


def fold_zero(zone: ZoneInfo, local: int) -> tuple[int, int]:
    """PEP 495 fold=0 for a local time: the UTC instant and its kind."""

    naive = datetime.fromtimestamp(local, timezone.utc).replace(tzinfo=None)
    first = naive.replace(tzinfo=zone, fold=0).timestamp()
    second = naive.replace(tzinfo=zone, fold=1).timestamp()
    if first == second:
        return int(first), UNIQUE
    return int(first), OVERLAP if first < second else GAP


def from_offsets(offset_at, local: int, before: int, after: int) -> tuple[int, int]:
    """RFC 5545 from an offset oracle: a reading consistent with it, the
    first of two, or the offset before the change when none is."""

    held = [local - offset for offset in sorted({before, after})
            if offset_at(local - offset)[0] == offset]
    if len(held) == 2:
        return min(held), OVERLAP
    if held:
        return held[0], UNIQUE
    return local - min(before, after), GAP


def local_cases(tz: str) -> list[tuple[int, int, int]]:
    """(local seconds, expected UTC, expected kind) across each transition."""

    offset_at = oracle(tz)
    if tz in GLIBC_ORACLE:
        return [(local, *from_offsets(offset_at, local, before, after))
                for local, before, after in local_points(offset_at)]
    zone = footer_zone(tz)
    return [(local, *fold_zero(zone, local))
            for local, _, _ in local_points(offset_at)]


# ---------------------------------------------------------------------------
# Parsing and the canonical form
# ---------------------------------------------------------------------------

def test_real_zone_strings_parse_and_format_canonically(forth) -> None:
    strings = [footer(zone) for zone in REAL_ZONES]
    lines = []
    for tz in strings:
        lines += [parse_line(tz), "SHOW-FORMAT"]
    output = run(forth, lines)
    assert len(output) == 2 * len(strings), output
    for index, tz in enumerate(strings):
        assert output[2 * index] == "0", (tz, output[2 * index])
        assert output[2 * index + 1] == f"0 [{tz}]", tz


def test_synthetic_strings_canonicalize(forth) -> None:
    lines = []
    for tz, _ in SYNTHETIC:
        lines += [parse_line(tz), "SHOW-FORMAT"]
    output = run(forth, lines)
    for index, (tz, canonical) in enumerate(SYNTHETIC):
        assert output[2 * index] == "0", tz
        assert output[2 * index + 1] == f"0 [{canonical}]", tz


def test_malformed_strings_are_refused_and_leave_no_zone(forth) -> None:
    lines = []
    for tz in MALFORMED:
        lines += [parse_line(tz), "0 Z TZ-OFFSET SHOW3"]
    output = run(forth, lines)
    for index, tz in enumerate(MALFORMED):
        assert output[2 * index] == str(SYNTAX), (tz, output[2 * index])
        assert numbers(output[2 * index + 1]) == [0, 0, INVALID], tz


def test_overlong_string_and_bad_length_are_refused(forth) -> None:
    long_tz = "<" + "A" * 120 + ">5" + "X" * 10
    assert len(long_tz) > 128
    output = run(forth, [
        parse_line(long_tz),
        'S" EST5" DROP -1 Z TZ-PARSE . CR',
    ])
    assert output == [str(RANGE), str(INVALID)]


def test_format_refuses_short_destination_without_writing(forth) -> None:
    output = run(forth, [
        parse_line("EST5EDT,M3.2.0,M11.1.0"),
        "OUT 256 165 FILL",
        "Z OUT 21 TZ-FORMAT . . CR",
        "OUT C@ . OUT 20 + C@ . CR",
        "Z OUT 22 TZ-FORMAT . . CR",
        "Z OUT -1 TZ-FORMAT . . CR",
    ])
    assert output == ["0", f"{CAPACITY} 0", "165 165", "0 22", f"{INVALID} 0"]


# ---------------------------------------------------------------------------
# Offsets
# ---------------------------------------------------------------------------

ALL_STRINGS = [footer(zone) for zone in REAL_ZONES] + [tz for tz, _ in SYNTHETIC]


@pytest.mark.parametrize("tz", ALL_STRINGS)
def test_offsets_match_the_oracle(forth, tz) -> None:
    offset_at = oracle(tz)
    times = instants(offset_at)
    output = run(forth, [parse_line(tz)]
                 + [f"{ts} Z TZ-OFFSET SHOW3" for ts in times])
    assert output[0] == "0"
    for ts, line in zip(times, output[1:], strict=True):
        offset, dst = offset_at(ts)
        assert numbers(line) == [offset, -1 if dst else 0, OK], (tz, ts)


def test_permanent_daylight_time_holds_across_the_new_year(forth) -> None:
    new_year = calendar.timegm((2040, 1, 1, 5, 0, 0))
    times = [new_year + delta for delta in (-3601, -1, 0, 1, 3600)]
    output = run(forth, [parse_line("EST5EDT4,0/0,J365/25")]
                 + [f"{ts} Z TZ-OFFSET SHOW3" for ts in times])
    assert [numbers(line) for line in output[1:]] == [[-14400, -1, OK]] * 5


def test_rule_applies_at_the_range_edges(forth) -> None:
    output = run(forth, [
        parse_line("AEST-10AEDT,M10.1.0,M4.1.0/3"),
        "0 Z TZ-OFFSET SHOW3",
        "253402300799 Z TZ-OFFSET SHOW3",
        parse_line("EST5EDT,M3.2.0,M11.1.0"),
        "0 Z TZ-OFFSET SHOW3",
        "253402300799 Z TZ-OFFSET SHOW3",
        "-1 Z TZ-OFFSET SHOW3",
        "253402300800 Z TZ-OFFSET SHOW3",
    ])
    assert [numbers(line) for line in output] == [
        [0], [39600, -1, OK], [39600, -1, OK],
        [0], [-18000, 0, OK], [-18000, 0, OK],
        [0, 0, RANGE], [0, 0, RANGE],
    ]


def test_names_follow_the_rule(forth) -> None:
    summer = calendar.timegm((2041, 7, 15, 12, 0, 0))
    winter = calendar.timegm((2041, 1, 15, 12, 0, 0))
    output = run(forth, [
        parse_line("EST5EDT,M3.2.0,M11.1.0"),
        f"{summer} Z TZ-NAME . TYPE CR",
        f"{winter} Z TZ-NAME . TYPE CR",
        parse_line("<+0545>-5:45"),
        f"{summer} Z TZ-NAME . TYPE CR",
    ])
    assert output == ["0", "0 EDT", "0 EST", "0", "0 +0545"]


# ---------------------------------------------------------------------------
# Local and UTC conversion
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("tz", ALL_STRINGS)
def test_local_to_utc_follows_rfc_5545(forth, tz) -> None:
    cases = local_cases(tz)
    if not cases:
        local = calendar.timegm((2041, 6, 1, 12, 0, 0))
        offset, _ = oracle(tz)(local)
        cases = [(local, local - offset, UNIQUE)]
    output = run(forth, [parse_line(tz)]
                 + [f"{local} Z TZ-LOCAL>UTC SHOW3" for local, _, _ in cases])
    assert output[0] == "0"
    for (local, expected, kind), line in zip(cases, output[1:], strict=True):
        assert numbers(line) == [expected, kind, OK], (tz, local)


def test_utc_to_local_round_trips(forth) -> None:
    tz = footer("America/Santiago")
    zone = footer_zone(tz)
    times = instants(lambda ts: zone_offset(zone, ts), years=(2041,))
    output = run(forth, [parse_line(tz)]
                 + [f"{ts} Z TZ-UTC>LOCAL . . CR" for ts in times])
    for ts, line in zip(times, output[1:], strict=True):
        offset, _ = zone_offset(zone, ts)
        assert numbers(line) == [OK, ts + offset], ts


def test_local_conversion_reports_range_and_invalid_zones(forth) -> None:
    output = run(forth, [
        "Z TZ-SIZE 0 FILL",
        "100 Z TZ-LOCAL>UTC SHOW3",
        parse_line("<+14>-14"),
        "100 Z TZ-LOCAL>UTC SHOW3",
        "-1 Z TZ-LOCAL>UTC SHOW3",
        "50400 Z TZ-LOCAL>UTC SHOW3",
    ])
    assert [numbers(line) for line in output] == [
        [0, 0, INVALID], [0], [0, 0, RANGE], [0, 0, RANGE], [0, UNIQUE, OK],
    ]
