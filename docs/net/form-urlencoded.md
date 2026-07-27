# Form URL encoding and decoding

`net/form-urlencoded.f` provides stateless component encoding and strict
component decoding for `application/x-www-form-urlencoded` data, including
OAuth PAR and token requests and authorization-response query components.

```forth
REQUIRE net/form-urlencoded.f
```

The module owns no buffers, builder singleton, error variable, or mutable
scratch. A caller first measures a component and then encodes or decodes it
into a disjoint caller-owned destination:

```forth
FORM-URLENCODED-MEASURE
  ( source source-u -- encoded-u status )

FORM-URLENCODED-ENCODE
  ( source source-u destination destination-capacity
    -- written status )

FORM-URLENCODED-DECODE-MEASURE
  ( source source-u -- decoded-u status )

FORM-URLENCODED-DECODE
  ( source source-u destination destination-capacity
    -- written status )
```

ASCII letters, digits, `*`, `-`, `.`, and `_` remain literal. Space becomes
`+`; every other byte becomes an uppercase `%HH` triplet. The operation is
byte-oriented: callers are responsible for supplying the UTF-8 bytes required
by their protocol.

Decoding accepts uppercase or lowercase hexadecimal digits, maps `+` to
space, and rejects every incomplete or malformed percent escape. It decodes
one component only. Callers split on raw `&` and on the first raw `=` before
decoding names and values; `;` is ordinary component data. Empty fields,
duplicate decoded names, required fields, UTF-8, control/NUL policy, and
callback policy remain the responsibility of the caller.

All four APIs qualify nonempty caller spans through the platform boundary.
`ENCODE` and `DECODE` measure and validate the complete result, check
destination capacity, and reject any source/destination overlap before
writing their first byte. Returned geometry, alias, capacity, and
malformed-encoding statuses therefore leave the destination untouched. The
source must remain stable for the duration of the call. Empty components are
valid and may use address zero with a zero length or capacity.

Statuses are:

| Status | Meaning |
|---|---|
| `FORM-URLENCODED-S-OK` | Measurement, encoding, or decoding completed |
| `FORM-URLENCODED-S-INVALID` | A signed length or nonempty null span was supplied |
| `FORM-URLENCODED-S-CAPACITY` | The measured length overflowed or the destination is too small |
| `FORM-URLENCODED-S-ALIAS` | Source and destination spans overlap |
| `FORM-URLENCODED-S-RANGE` | A caller span has invalid or unmapped physical geometry |
| `FORM-URLENCODED-S-PROTECTED` | A caller span intersects platform-private memory |
| `FORM-URLENCODED-S-PLATFORM` | Caller-span qualification failed unexpectedly |
| `FORM-URLENCODED-S-ENCODING` | A percent escape is incomplete or has a non-hexadecimal digit |

This module intentionally does not own a complete form/query parser, form
builder, or HTTP request. Higher layers retain ordering, duplicate-name,
required-field, and body-size policy while composing or enumerating
components in their transaction buffers.
