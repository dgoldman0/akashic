# POSIX TZ zones

`akashic/utils/posix-tz.f` turns a POSIX TZ string into a zone the caller
owns and converts between UTC and local time with it. Load it with:

```forth
REQUIRE posix-tz.f
```

It reads the form IEEE Std 1003.1 section 8.3 defines, with the RFC 8536
section 3.3.1 extensions that tz database files use: `<...>` quoted names and
rule hours from -167 to 167. Examples:

| String | Meaning |
|---|---|
| `EST5EDT,M3.2.0,M11.1.0` | US Eastern: second Sunday of March to first Sunday of November |
| `AEST-10AEDT,M10.1.0,M4.1.0/3` | Sydney: daylight time across the new year |
| `<+0545>-5:45` | Nepal: a fixed offset with a quoted name |
| `IST-1GMT0,M10.5.0,M3.5.0/1` | Negative daylight time: the winter period carries the daylight rule |
| `EST5EDT4,0/0,J365/25` | Permanent daylight time |

Every tz database file ends with such a string, so a real zone's current
rule can be copied from it. A string describes only the current rule, with
no history: every year converts by it. A zone whose law changes must be given
its new string.

A string with a daylight name must carry its rule. POSIX leaves the
rule-less form implementation-defined, and this module refuses it rather
than guessing.

## Units

- **Instants** are Unix seconds.
- **Local times** are "local seconds": the local date and time of day encoded
  as if they were UTC, that is `DT-YMD>EPOCH-S` of the local date plus the
  seconds into the day. `DT-WEEKDAY` of local seconds is the local weekday.
- **Offsets** are seconds east of UTC, so local = utc + offset. POSIX writes
  offsets the other way round (`EST5` is five hours west); the parser and
  formatter convert.

Both instants and local times stay within datetime.f's range, 1970-01-01
through 9999-12-31.

## Words

```forth
TZ-SIZE         ( -- bytes )
TZ-STRING-MAX   ( -- bytes )
TZ-NAME-MAX     ( -- bytes )
TZ-PARSE        ( addr u zone -- status )
TZ-FORMAT       ( zone destination capacity -- written status )
TZ-DST?         ( zone -- flag )
TZ-OFFSET       ( utc-s zone -- offset-s dst? status )
TZ-NAME         ( utc-s zone -- addr u status )
TZ-UTC>LOCAL    ( utc-s zone -- local-s status )
TZ-LOCAL>UTC    ( local-s zone -- utc-s kind status )
```

Statuses are datetime.f's `DT-S-*`. A word given a record that `TZ-PARSE`
did not fill returns `DT-S-INVALID`. An instant or local time outside the
range returns `DT-S-RANGE`.

`TZ-PARSE` compiles the string into the caller's `TZ-SIZE`-byte record and
returns `DT-S-OK`, or `DT-S-SYNTAX` for a malformed string, `DT-S-RANGE` for
one longer than `TZ-STRING-MAX` (128) bytes, and `DT-S-INVALID` for a negative
length. A failed parse leaves the record zeroed. Names may be up to
`TZ-NAME-MAX` (16) bytes. Real strings are under 50 bytes and their names
under 8, so both limits are interface rules sized well above use.

`TZ-FORMAT` writes the canonical string: an offset is shown only when it is
not the default (daylight time one hour ahead of standard), a transition time
only when it is not 02:00, and a name is quoted only when it needs it. It
reproduces the strings zic writes into tz database files, so equal zones
compare equal as text. It measures first and writes nothing when the
destination is too small (`DT-S-CAPACITY`).

`TZ-OFFSET` returns the offset at an instant and whether the daylight
period, the one named second in the string, is in force. A start and an end
at the same instant leave daylight time in force, which is how a string
spells permanent daylight time.

`TZ-NAME` returns the name in force at an instant. The bytes stay in the
zone record.

`TZ-LOCAL>UTC` follows RFC 5545 and returns how it resolved the time:

| Kind | When | Result |
|---|---|---|
| `TZ-K-UNIQUE` | The time occurs once | That instant |
| `TZ-K-OVERLAP` | The clocks repeat it when they go back | Its first occurrence, the earlier instant |
| `TZ-K-GAP` | The clocks skip it when they go forward | It is read with the offset in force before the change, so 02:30 on a spring-forward day in New York becomes 03:30 EDT |

## Ownership

The module owns no mutable state. `TZ-PARSE` keeps its cursor in two cells of
the caller's record and clears them when it finishes. The caller owns every
zone record and output buffer and serializes any concurrent use of the same
one.

## Qualification

`local_testing/test_posix_tz.py` runs on the native simulator. It checks 26
strings: the footers of 20 tz database zones, including negative rule times,
rules past 24 hours, half-hour daylight time and southern-hemisphere zones,
plus strings for negative and permanent daylight time, both day-number forms,
seconds in offsets, and negative transition times. It checks offsets one
second either side of every transition from 2040 to 2042 and at spread
instants. It checks local-to-UTC conversion every quarter hour across each
gap and overlap and at its edges.

The oracle is Python's zoneinfo reading a TZif file whose only content is the
string under test, so it applies exactly that rule. CPython's zoneinfo puts
the zero-based day form one day early, so that string is checked against
glibc instead. The suite also checks the canonical round trip, a corpus of
malformed strings, and the range and capacity refusals.
