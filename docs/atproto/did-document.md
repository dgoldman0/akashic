# AT Protocol DID document profile

`akashic/atproto/did-document.f` is the transport-neutral identity-profile
boundary for a caller-supplied DID document. It owns no resolver, DNS client,
HTTP exchange, OAuth state, repository, event stream, or application policy.

The profile follows the official
[AT Protocol DID document contract](https://atproto.com/specs/did):

```forth
REQUIRE atproto/did-document.f
```

## Selection contract

`AT-DIDDOC-PARSE` first validates the complete input as strict JSON. Validation
includes UTF-8 and JSON string escapes, duplicate decoded member names,
complete unknown nested values, the 32-level nesting bound, and the
64-members-per-object bound supplied by the shared JOSE JSON component.

The parser then requires `id` to be a JSON string exactly equal to the
caller's expected, syntactically valid DID. Independently, it selects:

- the first valid `verificationMethod` entry whose `id` is a relative or fully qualified
  `#atproto` fragment, whose `type` is `Multikey`, whose `controller` is the
  expected DID, and whose `publicKeyMultibase` is a bounded Base58btc
  multibase string;
- the first valid `service` entry whose `id` is a relative or fully qualified
  `#atproto_pds` fragment, whose `type` is `AtprotoPersonalDataServer`, and whose
  `serviceEndpoint` is an absolute HTTPS origin with no path, query, or fragment;
  and
- the first syntactically valid `at://<handle>` string in
  `alsoKnownAs`.

Array order is significant: irrelevant or unusable entries are skipped and
the first entry satisfying each selection is retained. Missing or unusable
handle, key, and PDS candidates do not prevent publication of the exact DID;
their evidence remains independent. A
`publicKeyJwk` entry does not satisfy the modern Multikey path. The retained
`publicKeyMultibase` is syntax-checked and copied intact; decoding its
multicodec and validating the represented curve point belong to the
signature-verification component that consumes the result.

The HTTPS endpoint uses the generic `HTARGET` admission contract. Consequently
it is canonicalized to lowercase DNS host, explicit numeric port state, and an
origin-form request target. This parser makes no certificate, DNS, address,
redirect, or trust decision.

## API and ownership

```forth
AT-DIDDOC-SIZE
AT-DIDDOC-WORKSPACE-SIZE

AT-DIDDOC-STATUS-VALID?    ( status -- flag )
AT-DIDDOC-VALID?           ( document -- flag )
AT-DIDDOC-WORKSPACE-CLEAR  ( workspace -- status )

AT-DIDDOC-PARSE
  ( source source-u expected-did expected-did-u
    document workspace -- status )

AT-DIDDOC-EVIDENCE@
  ( document -- id-e handle-e key-e pds-e status )

AT-DIDDOC-PARTICIPATION-STATUS  ( document -- status )

AT-DIDDOC-DID@                     ( document -- a u status )
AT-DIDDOC-HANDLE@                  ( document -- a u status )
AT-DIDDOC-PUBLIC-KEY-MULTIBASE@    ( document -- a u status )
AT-DIDDOC-PDS-TARGET@              ( document -- target status )
AT-DIDDOC-PDS-ORIGIN@              ( document -- a u status )
```

The source and expected DID are read-only for the duration of the call. The
result and workspace must be caller-owned and disjoint from all read-only
inputs and from each other. Read-only source and expected-DID spans may
overlap.

Parsing stages every retained byte in the workspace and publishes the result
only after strict validation and exact-ID admission succeed. Ordinary
validation, ID, or internal failure leaves the prior result unchanged. Once
the complete public geometry has been admitted, the workspace is cleared on
every status return. Geometry rejection occurs before any write and leaves
both the prior result and workspace unchanged. A successful result owns a
copy of the DID and, when selected, the normalized lowercase handle,
multibase public key, and canonical `HTARGET`; none borrows the JSON receive
buffer. Unselected optional storage and unused selected text tails are zeroed
before publication, so rejected candidates leave no residual payload in the
result.

## Bounds and evidence

| Item | Bound |
| --- | ---: |
| JSON document | `JOSE-JSON-MAX-DOCUMENT-BYTES` (65,536 bytes) |
| Members in any admitted object | `AT-DIDDOC-MAX-MEMBERS` (64) |
| DID | `AT-DIDDOC-DID-CAPACITY` (2,048 bytes) |
| Handle | `AT-DIDDOC-HANDLE-CAPACITY` (253 bytes) |
| Public-key multibase text | `AT-DIDDOC-KEY-CAPACITY` (512 bytes) |
| PDS endpoint | Generic `HTARGET` bounds |

`AT-DIDDOC-EVIDENCE@` returns `AT-DIDDOC-E-VALID` for the required ID.
Handle, key, and PDS evidence independently report `AT-DIDDOC-E-VALID` or
`AT-DIDDOC-E-MISSING`. The corresponding optional accessor reports
`AT-DIDDOC-S-MISSING` when no usable value was selected.

Identity publication and participation readiness are deliberately separate:

```forth
AT-DIDDOC-PARTICIPATION-STATUS  ( document -- status )
```

The qualifier returns `AT-DIDDOC-S-KEY` when no usable modern Multikey was
selected, `AT-DIDDOC-S-PDS` when the key exists but no HTTPS-origin PDS was
selected, and `AT-DIDDOC-S-OK` when both are available. `KEY` takes precedence
when both are missing. An invalid or corrupt result returns
`AT-DIDDOC-S-INVALID`.

## Status values

| Status | Meaning |
| --- | --- |
| `AT-DIDDOC-S-OK` | The exact identity was published, or the participation qualifier found both key and PDS |
| `AT-DIDDOC-S-INVALID` | A scalar, result, or public operation shape is invalid |
| `AT-DIDDOC-S-CAPACITY` | The document, expected/decoded ID, or strict JSON structure exceeds a global bound |
| `AT-DIDDOC-S-ALIAS` | A writable span overlaps another public operand |
| `AT-DIDDOC-S-JSON` | Strict JSON, UTF-8, nesting, or duplicate-name validation failed |
| `AT-DIDDOC-S-ID` | The required `id` is missing, malformed, or not the expected DID |
| `AT-DIDDOC-S-KEY` | Participation requires a usable modern, DID-controlled `#atproto` Multikey |
| `AT-DIDDOC-S-PDS` | Participation has a key but requires a usable HTTPS-origin `#atproto_pds` service |
| `AT-DIDDOC-S-MISSING` | An optional accessor has no retained value |
| `AT-DIDDOC-S-INTERNAL` | An impossible subordinate result or caught staging failure occurred |
| `AT-DIDDOC-S-RANGE` | A caller span has invalid physical geometry |
| `AT-DIDDOC-S-PROTECTED` | A caller span intersects protected storage |
| `AT-DIDDOC-S-PLATFORM` | Caller-memory qualification failed unexpectedly |
