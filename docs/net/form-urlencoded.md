# Form URL encoding

`net/form-urlencoded.f` provides the stateless component encoder needed for
`application/x-www-form-urlencoded` request bodies, including OAuth PAR and
token requests.

```forth
REQUIRE net/form-urlencoded.f
```

The module owns no buffers, builder singleton, error variable, or mutable
scratch. A caller first measures a component and then encodes it into a
disjoint caller-owned destination:

```forth
FORM-URLENCODED-MEASURE
  ( source source-u -- encoded-u status )

FORM-URLENCODED-ENCODE
  ( source source-u destination destination-capacity
    -- written status )
```

ASCII letters, digits, `*`, `-`, `.`, and `_` remain literal. Space becomes
`+`; every other byte becomes an uppercase `%HH` triplet. The operation is
byte-oriented: callers are responsible for supplying the UTF-8 bytes required
by their protocol.

Both APIs qualify nonempty caller spans through the platform boundary.
`ENCODE` measures the complete result, checks destination capacity, and
rejects any source/destination overlap before writing its first byte.
Geometry, alias, and capacity failures therefore leave the destination
untouched. Empty components are valid and may use address zero with a zero
length or capacity.

Statuses are:

| Status | Meaning |
|---|---|
| `FORM-URLENCODED-S-OK` | Measurement or encoding completed |
| `FORM-URLENCODED-S-INVALID` | A signed length or nonempty null span was supplied |
| `FORM-URLENCODED-S-CAPACITY` | The measured length overflowed or the destination is too small |
| `FORM-URLENCODED-S-ALIAS` | Source and destination spans overlap |
| `FORM-URLENCODED-S-RANGE` | A caller span has invalid or unmapped physical geometry |
| `FORM-URLENCODED-S-PROTECTED` | A caller span intersects platform-private memory |
| `FORM-URLENCODED-S-PLATFORM` | Caller-span qualification failed unexpectedly |

This module intentionally does not own a complete form builder or HTTP
request. Higher layers retain ordering, duplicate-name, required-field, and
body-size policy while composing encoded components into their transaction
buffers.
