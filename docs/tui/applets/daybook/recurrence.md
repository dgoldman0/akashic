# Daybook recurrence

`akashic/tui/applets/daybook/recurrence.f` describes when a Daybook schedule
repeats and finds its occurrences. It is Daybook-domain code with no UI; the
automation store keeps one rule per schedule and the runner asks it for the
next occurrence.

## Rules

A rule is a caller-owned `DBREC-SIZE`-byte record. Its fields have public
accessors (`DBREC.FREQ`, `DBREC.INTERVAL`, `DBREC.WEEKDAYS`,
`DBREC.MONTH-MODE`, `DBREC.MONTH-DAY`, `DBREC.MONTH-WEEKDAY`, `DBREC.END`,
`DBREC.LIMIT`, `DBREC.START`).

| Frequency | Repeats |
|---|---|
| `DBREC-ONCE` | Only at the start |
| `DBREC-DAILY` | Every interval days |
| `DBREC-WEEKLY` | On a set of weekdays every interval weeks; weekdays are ISO bits 1 (Monday) to 7 (Sunday), and 0 means the start's weekday |
| `DBREC-MONTHLY` | Every interval months, either on a day of the month (`DBREC-BY-DAY`: 1 to 31, -1 for the last day, 0 for the start's day) or on the nth weekday (`DBREC-BY-WEEKDAY`: nth 1 to 5 or -1 for the last, weekday ISO 1 to 7) |
| `DBREC-YEARLY` | On the start's month and day every interval years |

A series ends never (`DBREC-END-NEVER`), after a count of occurrences
(`DBREC-END-COUNT`), or at an UNTIL instant (`DBREC-END-UNTIL`). UNTIL is in
UTC and inclusive, as RFC 5545 requires for a zoned start.

The start is local seconds, as defined in [posix-tz](../../../utils/posix-tz.md),
and fixes every occurrence's time of day.

## Meaning

This is a subset of RFC 5545 and generates what it would:

- Occurrences are the dates matching the rule on or after the start's date.
  A weekly rule for Mondays starting on a Tuesday first fires the next Monday.
- Weeks start on Monday. Interval weeks count from the week holding the start.
- A date the calendar lacks is skipped and does not count: the 31st of a short
  month, a fifth weekday a month does not have, February 29 outside leap years.
- Ordinals number occurrences from 1.
- Local times become instants with RFC 5545's rule (see posix-tz): a time the
  clocks skip fires just after the change, and a repeated time fires at its
  first occurrence.

## Words

```forth
DBREC-CHECK       ( rule zone -- status )
DBREC-OCCURRENCE  ( k rule -- local-s status )
DBREC-FIRST-FROM  ( local-s rule -- k status )
DBREC-NEXT        ( after-utc rule zone -- k utc status )
```

| Status | Meaning |
|---|---|
| `DBREC-S-OK` | Done |
| `DBREC-S-INVALID` | A field is outside its range |
| `DBREC-S-ENDED` | The series has no such occurrence (past its count or UNTIL, or a one-off already past) |
| `DBREC-S-NEVER` | The rule can never produce an occurrence |
| `DBREC-S-RANGE` | The occurrence would fall after 9999-12-31 |
| `DBREC-S-ZONE` | The zone could not convert a time |

`DBREC-CHECK` validates every field, then requires a first occurrence that
falls within any UNTIL. A monthly rule for the 31st of every April, or an
UNTIL before the start, is refused as `DBREC-S-NEVER`.

`DBREC-NEXT` returns the first occurrence strictly after an instant, with its
ordinal. It starts two days earlier in local time, which covers any offset
change, and steps forward to the first instant past the one given.

## Cost

Daily and weekly rules find an ordinal arithmetically, so catching up after
a long gap costs the same as the next occurrence. Monthly and yearly rules
step one period at a time from the start. The Gregorian calendar repeats every
400 years, so a rule that finds no date in 4,800 consecutive months or 400
years is known never to fire.

The interval is at most `DBREC-INTERVAL-MAX` (9,999) and a count at most
`DBREC-COUNT-MAX`. Both are interface rules, far beyond any calendar use. The
module owns no mutable state.

## Qualification

`local_testing/test_daybook_recurrence.py` runs on the native simulator. It
checks 160 seeded random rules of every frequency against `dateutil.rrule`:
- intervals, weekday sets and the start's weekday;
- every monthly day, including the 29th to 31st and the last day;
- every nth weekday, including the fifth and the last;
- February 29 starts and counts.

It compares up to 40 occurrences per rule, `DBREC-FIRST-FROM` at
occurrences and at random times, and `DBREC-NEXT` in UTC, New York and
Sydney, with an UNTIL in every third rule. It also checks:
- the field and never-fires refusals;
- a time skipped at a spring-forward change;
- daily and weekly lookups 500 years out within a step budget that
  stepping through the gap would exceed.
