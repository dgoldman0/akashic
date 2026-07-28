# Form URL-encoded body writer

`net/form-urlencoded-writer.f` builds one bounded
`application/x-www-form-urlencoded` body in a caller-owned byte arena. It is
a generic network utility: it owns no HTTP request, OAuth policy, AT Protocol
state, Streams state, allocation, singleton buffer, or mutable module scratch.

```forth
REQUIRE net/form-urlencoded-writer.f

CREATE form-body 4096 ALLOT
CREATE form-writer FUEW-SIZE ALLOT

form-body 4096 form-writer FUEW-INIT

S" client_id" S" https://client.example/metadata.json"
    form-writer FUEW-FIELD
S" response_type" S" code" form-writer FUEW-FIELD

form-writer FUEW-SEAL
form-writer FUEW-BODY@
\ body-a body-u FUEW-S-OK
```

Every name and value is encoded independently with
`FORM-URLENCODED-ENCODE`. ASCII letters, digits, `*`, `-`, `.`, and `_`
remain literal, space becomes `+`, and every other byte becomes uppercase
`%HH`. The writer inserts raw `=` between each encoded name and value and raw
`&` between fields. Empty names and values are valid. Field order is
preserved, and duplicate names are not rejected because required fields and
duplicate policy belong to the consuming protocol.

## Lifecycle

`FUEW-INIT` binds a complete caller-provided arena and enters
`FUEW-STATE-BUILDING`. Initialization qualifies the descriptor and complete
arena, requires them to be disjoint, and zeroes both before publishing a valid
descriptor. Zero capacity is valid and may use address zero.

While building, call:

```forth
FUEW-FIELD
( name-a name-u value-a value-u writer -- status )
```

`FUEW-SEAL` makes the body immutable and enters `FUEW-STATE-SEALED`.
`FUEW-BODY@` succeeds only in that state and returns a borrowed view of the
exact published prefix. Repeated `BODY@` calls are permitted. `FIELD` after
sealing and a second `SEAL` return `FUEW-S-STATE`.

The inspection API is:

```forth
FUEW-VALID?        ( writer -- flag )
FUEW-STATE@        ( writer -- state status )
FUEW-LENGTH@       ( writer -- length status )
FUEW-FIELD-COUNT@  ( writer -- count status )
FUEW-BODY@         ( writer -- body-a body-u status )
```

`FUEW-WIPE` accepts either live state, zeroes the complete advertised arena
including unused capacity, and then zeroes the complete descriptor. The
writer is invalid afterward and must be initialized before reuse. A second
wipe therefore returns `FUEW-S-INVALID`.

Calling `FUEW-INIT` on a valid live writer is also safe: after all new geometry
has passed preflight, initialization first clears the old complete arena,
then clears and binds the new one. A descriptor containing this module's
magic but failing structural validation is rejected instead of following an
untrusted retained arena pointer.

## Transactional field append

`FIELD` first validates the writer state, rejects either source if it overlaps
the complete arena or descriptor, and measures both encoded components. It
checks the complete optional-separator/name/equals/value size and remaining
capacity before its first write.

After preflight, the field is staged in the currently unpublished arena tail.
The writer advances its published length and field count only after both
encoders succeed and their actual lengths equal the preflight measurement. If
a subordinate encoder unexpectedly rejects the already-admitted operation,
the complete attempted tail contribution is cleared and the prior published
length, count, and body prefix remain unchanged.

Ordinary `FIELD` failures are deliberately nonsticky. The descriptor remains
in `BUILDING`, so the caller may correct an invalid, aliased, or over-capacity
field and try again. `SEAL` is the explicit decision to stop building.

Name and value bytes are borrowed for the duration of `FIELD` and must remain
readable and byte-stable until it returns. They may overlap each other, but
neither may overlap any byte of the complete arena or descriptor. Rejecting
the complete advertised arena—not merely the currently used prefix—matches
the component codec's complete-destination alias rule and prevents an input
from being destroyed by tail staging or cleanup.

## Caller-memory boundary

The descriptor must be eight-byte aligned and span `FUEW-SIZE` admitted caller
bytes. Every nonempty arena, name, and value span is qualified through
`CALLER-SPAN-STATUS`; negative lengths, wrapping ranges, and nonempty null
spans are rejected. Exact adjacency is disjoint and accepted.

Preflight failure from `INIT` leaves both the prospective arena and descriptor
unchanged. Preflight failure from `FIELD` leaves the complete writer and arena
unchanged. Once field staging begins, a returned failure may have cleared the
unpublished attempted tail, but it never changes the previously published
body.

## Status values

Use `FUEW-STATUS-VALID?` to validate a returned status.

| Status | Meaning |
|---|---|
| `FUEW-S-OK` | Operation completed |
| `FUEW-S-INVALID` | Invalid descriptor, pointer, signed length, or nonempty null span |
| `FUEW-S-STATE` | Operation is not permitted in the current lifecycle state |
| `FUEW-S-CAPACITY` | Encoded size overflowed or the body arena is too small |
| `FUEW-S-ALIAS` | Descriptor, arena, or borrowed field geometry overlaps where prohibited |
| `FUEW-S-RANGE` | A caller span is outside admitted physical memory |
| `FUEW-S-PROTECTED` | A caller span intersects platform-private memory |
| `FUEW-S-PLATFORM` | Caller-span qualification failed unexpectedly |
| `FUEW-S-INTERNAL` | An admitted subordinate result contradicted measured geometry |

The writer only constructs bytes. An HTTP owner remains responsible for
adding `Content-Type: application/x-www-form-urlencoded`, the exact
`Content-Length`, endpoint and credential policy, transmission, response
admission, and eventual `FUEW-WIPE`.
