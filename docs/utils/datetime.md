# Checked UTC date and time

`akashic/utils/datetime.f` provides state-free Gregorian calendar conversion
and exact bounded UTC formatting. Load it with:

```forth
REQUIRE datetime.f
```

The supported civil interval is `1970-01-01T00:00:00Z` through
`9999-12-31T23:59:59Z`, corresponding to Unix epoch seconds
`0..253402300799`. Units are part of every public word name; the module never
silently guesses whether a scalar is seconds or milliseconds.

## Statuses

| Status | Meaning |
|---|---|
| `DT-S-OK` | Operation completed |
| `DT-S-INVALID` | Invalid call shape, such as negative capacity |
| `DT-S-CAPACITY` | Destination is smaller than the exact result |
| `DT-S-SYNTAX` | Invalid calendar month or day |
| `DT-S-RANGE` | Epoch/year or caller span is outside its range |
| `DT-S-PROTECTED` | Destination names protected memory |
| `DT-S-PLATFORM` | The platform could not qualify the span |
| `DT-S-INTERNAL` | Reserved internal failure class |

`DT-STATUS-VALID? ( status -- flag )` admits exactly this status vocabulary.

## Calendar conversion

```forth
DT-MONTH-DAYS   ( year month -- days status )
DT-EPOCH-S>YMD  ( epoch-s -- year month day status )
DT-YMD>EPOCH-S  ( year month day -- epoch-s status )
```

These words validate their public inputs and use constant-time civil-date
arithmetic. Failure results are zero-filled before the status: `0 status`, or
`0 0 0 status` for `DT-EPOCH-S>YMD`.

```forth
2000 2 DT-MONTH-DAYS        \ 29 DT-S-OK
0 DT-EPOCH-S>YMD            \ 1970 1 1 DT-S-OK
2000 2 29 DT-YMD>EPOCH-S    \ 951782400 DT-S-OK
```

## Exact formatters

```forth
DT-DATE-S          ( epoch-s destination capacity -- written status )
DT-RFC3339-UTC-S   ( epoch-s destination capacity -- written status )
```

`DT-DATE-S` writes exactly 10 bytes as `YYYY-MM-DD`.
`DT-RFC3339-UTC-S` writes exactly 20 bytes as
`YYYY-MM-DDTHH:MM:SSZ`. Neither appends a terminator.

The formatter qualifies the complete caller-advertised destination span before
writing. Invalid epochs, negative or insufficient capacities, and inaccessible
spans return `0 status` without changing any destination byte. On success only
the exact 10- or 20-byte prefix is changed; additional capacity and canaries
remain untouched.

```forth
CREATE stamp 32 ALLOT
1718465400 stamp 32 DT-RFC3339-UTC-S
\ returns 20 DT-S-OK; stamp contains 2024-06-15T15:30:00Z
```

The fixed lengths are available as `DT-DATE-S-LENGTH` and
`DT-RFC3339-UTC-S-LENGTH`. The upper scalar bound is
`DT-EPOCH-S-MAX`.

## Clock access

```forth
DT-NOW-MS  ( -- epoch-ms )
DT-NOW-S   ( -- epoch-s )
```

These thin BIOS accessors read `EPOCH@`; they do not participate in calendar
conversion state. Code that needs deterministic or authenticated time should
accept the scalar from its caller and use the conversion/formatting words
directly.

## Ownership and concurrency

The module contains no `VARIABLE`, writable table, guard, clock singleton, or
formatter workspace. Independent calls may be interleaved freely. The caller
owns every output buffer and is responsible for serializing concurrent writes
to the same bytes.

The former truncating formatters, permissive ISO parser, ambiguous `DT-NOW`
alias, and process-global calendar scratch have been removed rather than kept
as compatibility surfaces.
