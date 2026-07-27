# akashic-jose-jsonobj — Strict Caller-Owned JSON Mechanics

`jose/json-object.f` supplies strict JSON object and string decoding for JOSE
consumers. It understands JSON syntax and Unicode, but deliberately owns no
JWT, OAuth, key, authorization, or application field policy.

```forth
REQUIRE akashic/security/jose/json-object.f
```

`PROVIDED akashic-jose-jsonobj` — requires
`utils/memory-span.f` and `utils/caller-span.f`.

## Bounds

```forth
JOSE-JSON-MAX-DOCUMENT-BYTES  ( -- 65536 )
JOSE-JSON-MAX-DEPTH           ( -- 32 )
JOSE-JSON-MAX-MEMBERS         ( -- 64 )
JOSE-JSON-MAX-NAME-BYTES      ( -- 4096 )
JOSE-JSON-MAX-VALUE-STRING-BYTES
                                  ( -- 65536 )

JOSE-JSON-STRING-WORKSPACE-SIZE  ( -- 72 )
JOSE-JSON-OBJECT-WORKSPACE-SIZE  ( -- bytes )
```

The parser validates the complete document before publishing output. It
enforces strict UTF-8, JSON number grammar, escapes and UTF-16 surrogate
pairs, bounded nesting, bounded member names, document-sized string values,
complete nested values, and duplicate member-name rejection after names are
unescaped. Trailing JSON whitespace is accepted; trailing non-whitespace
input is rejected.

`JOSE-JSON-MAX-NAME-BYTES` applies to each decoded member name and to the
combined decoded top-level and currently nested member names simultaneously
staged by one object parse. `JOSE-JSON-MAX-VALUE-STRING-BYTES` applies
independently to each decoded JSON value string and to standalone string
operations. It equals the document bound; because a standalone string source
also includes its two quote bytes, the largest reachable decoded standalone
string is 65534 bytes.

## Offset-only object descriptors

```forth
JOSE-JSON-OBJECT-BYTES
  ( member-capacity -- descriptor-bytes status )

JOSE-JSON-OBJECT-PARSE
  ( source source-u descriptor member-capacity
    names names-capacity workspace -- status )

JOSE-JSON-OBJECT-VALID?
  ( descriptor -- flag )

JOSE-JSON-OBJECT-COUNT@
  ( descriptor -- count status )

JOSE-JSON-OBJECT-NAMES-USED@
  ( descriptor -- names-u status )

JOSE-JSON-OBJECT-MEMBER@
  ( index descriptor
    -- name-offset name-u value-offset value-u type status )
```

`JOSE-JSON-OBJECT-BYTES` computes the exact descriptor allocation for up to
64 top-level members.

On successful parse, `descriptor` contains only scalar metadata, offsets,
lengths, and type tags. It retains no pointer to the source or names buffer.
The caller therefore keeps the source and decoded-name buffer and resolves:

- `name-offset/name-u` relative to the `names` buffer supplied to `PARSE`;
- `value-offset/value-u` relative to the original JSON source.

The value span is the exact source token, including quotes for a string and
braces or brackets for a container. The public type values are:

| Type | JSON value |
|---|---|
| `JOSE-JSON-T-STRING` | string |
| `JOSE-JSON-T-NUMBER` | number |
| `JOSE-JSON-T-OBJECT` | object |
| `JOSE-JSON-T-ARRAY` | array |
| `JOSE-JSON-T-BOOL` | `true` or `false` |
| `JOSE-JSON-T-NULL` | `null` |

Use `JOSE-JSON-TYPE-VALID?` when validating a type value. Descriptor accessors
validate the complete descriptor geometry before returning data.

Before any mutation, every complete public span is qualified through
`CALLER-SPAN-STATUS`, including the full advertised descriptor, names, and
workspace capacities. Range failures map to `JOSE-JSON-S-INVALID`, protected
platform aliases map to `JOSE-JSON-S-ALIAS`, and qualification-platform
failures map to `JOSE-JSON-S-INTERNAL`. The full source, descriptor, names, and
workspace spans must be pairwise disjoint where the API requires it; checks do
not shrink to the prefixes eventually used.

Parsing stages the descriptor and decoded names, so neither published output
changes on ordinary rejection. An unexpected validation/staging `THROW`
scrubs the complete admitted descriptor, the first
`min(names-capacity, JOSE-JSON-MAX-NAME-BYTES)` bytes of the names span, and
the complete workspace; it becomes `JOSE-JSON-S-INTERNAL` only when that
mandatory scrub succeeds. A scrub `THROW` propagates instead.

Publication invalidates descriptor magic first, copies metadata, names, and
entries, and writes magic last. A publication `THROW` propagates after
mandatory workspace cleanup and cannot leave a valid partial descriptor;
names and non-magic descriptor bytes may be partially published. A mandatory
cleanup `THROW` also propagates and takes precedence over an operation
`THROW`. The admitted object workspace is cleared on every normal return.

## Standalone JSON strings

```forth
JOSE-JSON-STRING-MEASURE
  ( source source-u workspace -- decoded-u status )

JOSE-JSON-STRING-DECODE
  ( source source-u destination capacity workspace -- written status )
```

The source must be exactly one quoted JSON string token and may be at most
`JOSE-JSON-MAX-DOCUMENT-BYTES` bytes. Measurement performs the same escape,
UTF-8, surrogate, value-string length, and trailing-input checks as decoding.
Decode measures first and accepts any caller capacity large enough for the
measured result; an undersized destination returns
`JOSE-JSON-S-CAPACITY` before any destination write. Its publishing pass
independently rechecks complete source consumption. Rejection leaves the
destination unchanged provided the caller keeps the source bytes immutable
for the whole call. In particular, the caller must not mutate the source
between decode's measurement and publication passes.

The source, destination, and workspace must not overlap. All complete
advertised spans are caller-qualified before mutation. The standalone 72-byte
workspace is cleared after each admitted operation. Operation or mandatory
cleanup `THROW` propagates; if decode publication throws, the destination may
contain a partial decoded string.

Explicit clearing is also available:

```forth
JOSE-JSON-OBJECT-WORKSPACE-CLEAR  ( workspace -- status )
JOSE-JSON-STRING-WORKSPACE-CLEAR  ( workspace -- status )
```

## Status values

| Status | Meaning |
|---|---|
| `JOSE-JSON-S-OK` | The operation completed successfully. |
| `JOSE-JSON-S-INVALID` | An argument, span, descriptor, or index is invalid. |
| `JOSE-JSON-S-SYNTAX` | JSON grammar or document shape is invalid. |
| `JOSE-JSON-S-UTF8` | UTF-8 or Unicode scalar encoding is invalid. |
| `JOSE-JSON-S-CAPACITY` | A caller output cannot hold the accepted result. |
| `JOSE-JSON-S-ALIAS` | Public spans overlap in a forbidden way. |
| `JOSE-JSON-S-DEPTH` | The nesting bound was exceeded. |
| `JOSE-JSON-S-MEMBERS` | A bounded object-member limit was exceeded. |
| `JOSE-JSON-S-STRING` | A decoded member name, aggregate staged names, or value string exceeded its corresponding bound. |
| `JOSE-JSON-S-DUPLICATE` | An object repeats a decoded member name. |
| `JOSE-JSON-S-DOCUMENT` | The document exceeds the public byte bound. |
| `JOSE-JSON-S-INTERNAL` | Caller-span qualification had a platform failure, or validation/staging threw and every mandatory scrub succeeded. Publication and cleanup throws propagate instead. |

`JOSE-JSON-STATUS-VALID?` validates this status vocabulary.
