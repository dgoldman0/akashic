#!/usr/bin/env python3
"""daybook/recurrence.f against dateutil.rrule and zoneinfo.

dateutil generates each rule's local occurrences; RFC 5545 and dateutil
agree on the subset: dates matching the rule on or after the start's date,
weeks starting Monday, and calendar-missing dates skipped without counting.
Instants come from the same footer-only zoneinfo oracle as test_posix_tz.py,
read with PEP 495 fold=0, which is RFC 5545's rule for repeated and skipped
local times.
"""

from __future__ import annotations

import calendar
import random
from datetime import datetime, timedelta, timezone
from itertools import islice

import pytest
from dateutil import rrule as du

from native_forth import NativeForth
from test_posix_tz import footer_zone


ONCE, DAILY, WEEKLY, MONTHLY, YEARLY = range(5)
BY_DAY, BY_WEEKDAY = 0, 1
END_NEVER, END_UNTIL, END_COUNT = 0, 1, 2
OK, INVALID, ENDED, NEVER, RANGE, ZONE = range(6)

PRELUDE = (
    "CREATE RL DBREC-SIZE ALLOT",
    "CREATE ZN TZ-SIZE ALLOT",
    ": RULE! ( freq interval weekdays mode mday mweekday end limit start -- )",
    "  RL DBREC.START ! RL DBREC.LIMIT ! RL DBREC.END !",
    "  RL DBREC.MONTH-WEEKDAY ! RL DBREC.MONTH-DAY ! RL DBREC.MONTH-MODE !",
    "  RL DBREC.WEEKDAYS ! RL DBREC.INTERVAL ! RL DBREC.FREQ ! ;",
    ": SHOW2 ( a b -- ) SWAP . . CR ;",
    ": SHOW3 ( a b c -- ) ROT . SWAP . . CR ;",
    "CREATE DW CBW-SIZE ALLOT",
    "CREATE DB DBREC-DESCRIBE-MAX ALLOT",
    "\\ The writer's status, then RL's description in a buffer of ROOM bytes.",
    ": DESC. ( room -- ) DB SWAP DW CBW-INIT DROP RL DW DBREC-DESCRIBE",
    "  DW CBW-RESULT . TYPE CR ;",
)

SUITE = NativeForth(("tui/applets/daybook/recurrence.f",), prelude=PRELUDE)

ZONES = ("UTC0", "EST5EDT,M3.2.0,M11.1.0", "AEST-10AEDT,M10.1.0,M4.1.0/3")


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 4_000_000_000) -> list[list[int]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def local_seconds(moment: datetime) -> int:
    return calendar.timegm(moment.timetuple())


class Rule:
    """One rule, as recurrence.f fields and as a dateutil rrule."""

    def __init__(self, freq, start, interval=1, weekdays=0, mode=BY_DAY,
                 mday=0, mweekday=0, end=END_NEVER, limit=0):
        self.freq, self.start, self.interval = freq, start, interval
        self.weekdays, self.mode, self.mday, self.mweekday = (
            weekdays, mode, mday, mweekday)
        self.end, self.limit = end, limit

    def forth(self) -> str:
        return (f"{self.freq} {self.interval} {self.weekdays} {self.mode} "
                f"{self.mday} {self.mweekday} {self.end} {self.limit} "
                f"{local_seconds(self.start)} RULE!")

    def occurrences(self):
        """Local occurrences, ignoring UNTIL, which applies in UTC."""

        count = self.limit if self.end == END_COUNT else None
        if self.freq == ONCE:
            return iter([self.start])
        options = {"dtstart": self.start, "interval": self.interval,
                   "wkst": du.MO, "count": count}
        if self.freq == WEEKLY:
            mask = self.weekdays or (1 << self.start.isoweekday())
            options["byweekday"] = [du.weekday(iso - 1) for iso in range(1, 8)
                                    if mask & (1 << iso)]
            return iter(du.rrule(du.WEEKLY, **options))
        if self.freq == MONTHLY:
            if self.mode == BY_WEEKDAY:
                options["byweekday"] = du.weekday(self.mweekday - 1)(self.mday)
            else:
                options["bymonthday"] = self.mday or self.start.day
            return iter(du.rrule(du.MONTHLY, **options))
        frequency = {DAILY: du.DAILY, YEARLY: du.YEARLY}[self.freq]
        return iter(du.rrule(frequency, **options))


def random_rule(rng: random.Random) -> Rule:
    freq = rng.choice((ONCE, DAILY, DAILY, WEEKLY, WEEKLY, MONTHLY, MONTHLY,
                       MONTHLY, YEARLY))
    start = datetime(2024, 1, 1) + timedelta(
        days=rng.randrange(0, 365 * 20), minutes=rng.randrange(0, 1440))
    if rng.random() < 0.08:
        start = datetime(rng.choice((2028, 2032, 2036)), 2, 29,
                         rng.randrange(24), rng.randrange(60))
    rule = Rule(freq, start)
    if freq == ONCE:
        return rule
    rule.interval = rng.choice((1, 1, 1, 2, 3, 4, 7, 12, 13))
    if freq == WEEKLY:
        rule.weekdays = 0 if rng.random() < 0.3 else sum(
            1 << iso for iso in rng.sample(range(1, 8), rng.randrange(1, 8)))
    if freq == MONTHLY:
        if rng.random() < 0.5:
            rule.mode, rule.mday = BY_DAY, rng.choice(
                (0, 1, 15, 28, 29, 30, 31, -1, rng.randrange(1, 32)))
        else:
            rule.mode = BY_WEEKDAY
            rule.mday = rng.choice((1, 2, 3, 4, 5, -1))
            rule.mweekday = rng.randrange(1, 8)
    if rng.random() < 0.4:
        rule.end, rule.limit = END_COUNT, rng.randrange(1, 40)
    return rule


RULES = [random_rule(random.Random(seed)) for seed in range(160)]


def never_fires(rule: Rule) -> bool:
    return next(rule.occurrences(), None) is None


def test_occurrences_match_dateutil(forth) -> None:
    lines, expected = [], []
    for rule in RULES:
        if never_fires(rule):
            continue
        lines.append(rule.forth())
        listed = list(islice(rule.occurrences(), 40))
        for k, moment in enumerate(listed, start=1):
            lines.append(f"{k} RL DBREC-OCCURRENCE SHOW2")
            expected.append([local_seconds(moment), OK])
        if rule.end == END_COUNT:
            lines.append(f"{rule.limit + 1} RL DBREC-OCCURRENCE SHOW2")
            expected.append([0, ENDED])
    assert run(forth, lines) == expected


def test_first_from_matches_dateutil(forth) -> None:
    rng = random.Random(1789)
    lines, expected = [], []
    for rule in RULES:
        listed = list(islice(rule.occurrences(), 400))
        if not listed:
            continue
        lines.append(rule.forth())
        span = local_seconds(listed[-1]) - local_seconds(rule.start) + 86400 * 3
        probes = {local_seconds(rule.start) - 86400 * rng.randrange(0, 40)}
        for moment in rng.sample(listed, min(4, len(listed))):
            at = local_seconds(moment)
            probes.update((at - 1, at, at + 1))
        probes.update(local_seconds(rule.start) + rng.randrange(0, span)
                      for _ in range(6))
        last = local_seconds(listed[-1])
        for probe in sorted(p for p in probes if 0 <= p <= last):
            k = 1 + sum(1 for moment in listed if local_seconds(moment) < probe)
            lines.append(f"{probe} RL DBREC-FIRST-FROM SHOW2")
            if rule.freq == ONCE and probe > local_seconds(rule.start):
                expected.append([0, ENDED])
            else:
                expected.append([k, OK])
    assert run(forth, lines) == expected


def utc_of(zone, moment: datetime) -> int:
    return int(moment.replace(tzinfo=zone, fold=0).timestamp())


@pytest.mark.parametrize("tz", ZONES)
def test_next_matches_dateutil_in_a_zone(forth, tz) -> None:
    zone = footer_zone(tz)
    rng = random.Random(len(tz))
    lines, expected = [f'S" {tz}" ZN TZ-PARSE DROP'], []
    for index, rule in enumerate(RULES[:90]):
        listed = list(islice(rule.occurrences(), 120))
        if not listed:
            continue
        instants = [utc_of(zone, moment) for moment in listed]
        original_end = (rule.end, rule.limit)
        if index % 3 == 0 and len(instants) > 2:
            # An UNTIL between occurrences: it must stop the series there.
            rule.end, rule.limit = END_UNTIL, instants[len(instants) // 2] + 30
            kept = [u for u in instants if u <= rule.limit]
        else:
            kept = instants
        lines.append(rule.forth())
        probes = {instants[0] - 86400 * 5, instants[0] - 1}
        for u in rng.sample(instants, min(5, len(instants))):
            probes.update((u - 1, u, u + 1))
        for after in sorted(p for p in probes if p >= 0):
            if after >= instants[-1] and rule.end != END_UNTIL and len(listed) == 120:
                continue
            following = [(k, u) for k, u in enumerate(kept, start=1) if u > after]
            lines.append(f"{after} RL ZN DBREC-NEXT SHOW3")
            if following:
                expected.append([*following[0], OK])
            elif rule.end == END_UNTIL or rule.end == END_COUNT or rule.freq == ONCE:
                expected.append([0, 0, ENDED])
            else:
                expected.append(None)
        rule.end, rule.limit = original_end
    output = run(forth, lines)
    assert len(output) == len(expected)
    for got, want in zip(output, expected, strict=True):
        if want is not None:
            assert got == want


def test_long_gaps_are_found_without_stepping_through_them(forth) -> None:
    # A daily and a weekly rule asked for an occurrence 500 years out
    # within a budget far below what stepping through the gap would take.
    start = datetime(2026, 10, 12, 9, 30)
    daily = Rule(DAILY, start)
    weekly = Rule(WEEKLY, start, interval=3, weekdays=(1 << 1) | (1 << 5))
    far = local_seconds(datetime(2526, 3, 4, 12, 0))
    lines, expected = [], []
    for rule in (daily, weekly):
        listed = rule.occurrences()
        first_after = next(m for m in listed if local_seconds(m) >= far)
        lines += [rule.forth(), f"{far} RL DBREC-FIRST-FROM SHOW2"]
        k = sum(1 for m in rule.occurrences() if local_seconds(m) < far) + 1
        expected.append([k, OK])
        lines.append(f"{k} RL DBREC-OCCURRENCE SHOW2")
        expected.append([local_seconds(first_after), OK])
    assert run(forth, lines, max_steps=50_000_000) == expected


def test_check_refuses_bad_fields_and_rules_that_never_fire(forth) -> None:
    start = local_seconds(datetime(2027, 2, 1, 8, 0))
    april = local_seconds(datetime(2027, 4, 1, 8, 0))
    cases = (
        (f"{DAILY} 1 0 0 0 0 0 0 {start} RULE!", OK),
        (f"{DAILY} 0 0 0 0 0 0 0 {start} RULE!", INVALID),
        (f"{DAILY} 10000 0 0 0 0 0 0 {start} RULE!", INVALID),
        (f"5 1 0 0 0 0 0 0 {start} RULE!", INVALID),
        (f"{WEEKLY} 1 1 0 0 0 0 0 {start} RULE!", INVALID),
        (f"{WEEKLY} 1 256 0 0 0 0 0 {start} RULE!", INVALID),
        (f"{MONTHLY} 1 0 {BY_DAY} 32 0 0 0 {start} RULE!", INVALID),
        (f"{MONTHLY} 1 0 {BY_DAY} -2 0 0 0 {start} RULE!", INVALID),
        (f"{MONTHLY} 1 0 {BY_WEEKDAY} 6 1 0 0 {start} RULE!", INVALID),
        (f"{MONTHLY} 1 0 {BY_WEEKDAY} 2 8 0 0 {start} RULE!", INVALID),
        (f"{MONTHLY} 1 0 2 1 1 0 0 {start} RULE!", INVALID),
        (f"{DAILY} 1 0 0 0 0 3 0 {start} RULE!", INVALID),
        (f"{DAILY} 1 0 0 0 0 {END_COUNT} 0 {start} RULE!", INVALID),
        (f"{ONCE} 1 0 0 0 0 {END_COUNT} 1 {start} RULE!", INVALID),
        (f"{DAILY} 1 0 0 0 0 0 0 -1 RULE!", INVALID),
        # The 31st every April, and the 30th every February: never.
        (f"{MONTHLY} 12 0 {BY_DAY} 31 0 0 0 {april} RULE!", NEVER),
        (f"{MONTHLY} 12 0 {BY_DAY} 30 0 0 0 {start} RULE!", NEVER),
        # An UNTIL before the first occurrence: never.
        (f"{DAILY} 1 0 0 0 0 {END_UNTIL} {start - 3600 * 24} {start} RULE!", NEVER),
        (f"{ONCE} 1 0 0 0 0 0 0 {start} RULE!", OK),
        (f"{YEARLY} 1 0 0 0 0 0 0 {local_seconds(datetime(2028, 2, 29, 7, 0))} RULE!", OK),
    )
    lines = [f'S" UTC0" ZN TZ-PARSE DROP']
    for fill, _ in cases:
        lines += [fill, "RL ZN DBREC-CHECK . CR"]
    assert [status for status, in run(forth, lines)] == [s for _, s in cases]


def test_a_skipped_local_time_fires_after_the_change(forth) -> None:
    # 02:30 every day in New York: on the spring-forward day it fires at
    # 03:30 EDT, RFC 5545's reading with the offset before the change.
    zone = footer_zone("EST5EDT,M3.2.0,M11.1.0")
    rule = Rule(DAILY, datetime(2041, 3, 8, 2, 30))
    gap_day = datetime(2041, 3, 10, 2, 30)
    expected_utc = utc_of(zone, gap_day)
    assert datetime.fromtimestamp(expected_utc, zone).hour == 3
    output = run(forth, [
        'S" EST5EDT,M3.2.0,M11.1.0" ZN TZ-PARSE DROP',
        rule.forth(),
        f"{utc_of(zone, datetime(2041, 3, 9, 2, 30))} RL ZN DBREC-NEXT SHOW3",
    ])
    assert output == [[3, expected_utc, OK]]


DESCRIPTIONS = [
    (Rule(ONCE, datetime(2026, 10, 11, 9)), "once on 2026-10-11 at 09:00"),
    (Rule(DAILY, datetime(2026, 10, 11, 9)), "daily at 09:00 from 2026-10-11"),
    (Rule(DAILY, datetime(2026, 10, 11, 9, 5), interval=3, end=END_COUNT, limit=10),
     "every 3 days at 09:05 from 2026-10-11, 10 times"),
    (Rule(WEEKLY, datetime(2026, 10, 11, 9), interval=2, weekdays=(1 << 1) | (1 << 4)),
     "every 2 weeks on Mon, Thu at 09:00 from 2026-10-11"),
    # 2026-10-11 is a Sunday.
    (Rule(WEEKLY, datetime(2026, 10, 11, 9)), "weekly on Sun at 09:00 from 2026-10-11"),
    (Rule(MONTHLY, datetime(2026, 10, 11, 9), mday=15),
     "monthly on day 15 at 09:00 from 2026-10-11"),
    (Rule(MONTHLY, datetime(2026, 10, 11, 9)), "monthly on day 11 at 09:00 from 2026-10-11"),
    (Rule(MONTHLY, datetime(2026, 10, 11, 9), mday=-1),
     "monthly on the last day at 09:00 from 2026-10-11"),
    (Rule(MONTHLY, datetime(2026, 10, 11, 9), interval=2, mode=BY_WEEKDAY, mday=2,
          mweekday=2), "every 2 months on the 2nd Tue at 09:00 from 2026-10-11"),
    (Rule(MONTHLY, datetime(2026, 10, 11, 9), mode=BY_WEEKDAY, mday=-1, mweekday=5,
          end=END_UNTIL, limit=calendar.timegm((2027, 6, 30, 23, 0, 0))),
     "monthly on the last Fri at 09:00 from 2026-10-11, until 2027-06-30 23:00 UTC"),
    (Rule(YEARLY, datetime(2026, 10, 11, 0, 30), end=END_COUNT, limit=1),
     "yearly at 00:30 from 2026-10-11, 1 time"),
    (Rule(YEARLY, datetime(2026, 10, 11, 9), interval=4),
     "every 4 years at 09:00 from 2026-10-11"),
]

LONGEST = (Rule(WEEKLY, datetime(9999, 12, 31, 23, 59), interval=9999, weekdays=254,
                end=END_UNTIL, limit=calendar.timegm((9999, 12, 31, 23, 59, 0))),
           "every 9999 weeks on Mon, Tue, Wed, Thu, Fri, Sat, Sun at 23:59 from "
           "9999-12-31, until 9999-12-31 23:59 UTC")


def _describe(forth, rule: Rule, room: str = "DBREC-DESCRIBE-MAX") -> tuple[int, str]:
    output = forth.run([f"{rule.forth()} {room} DESC."], 400_000_000).decode("latin-1")
    assert "??" not in output, output
    status, _, text = output.replace("\r", "").strip("\n").partition(" ")
    return int(status), text


def test_a_rule_is_described_in_one_line(forth) -> None:
    for rule, text in DESCRIPTIONS:
        assert _describe(forth, rule) == (0, text)


def test_the_longest_description_fills_its_room_exactly(forth) -> None:
    rule, text = LONGEST
    assert _describe(forth, rule) == (0, text)
    rows = run(forth, ["DBREC-DESCRIBE-MAX . CR"])
    assert rows == [[len(text)]]
    # One byte less, and the writer says it ran out of room.
    status, _ = _describe(forth, rule, "DBREC-DESCRIBE-MAX 1-")
    assert status == 2

