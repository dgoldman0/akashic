# OAuth 2 protected-resource metadata

`security/oauth2/resource-metadata.f` is a strict, bounded parser
for the OAuth protected-resource metadata needed to discover authorization
servers. It implements the transport-neutral portion of RFC 9728.

```forth
REQUIRE security/oauth2/resource-metadata.f
```

The parser does not fetch metadata, construct a well-known URL, interpret a
`WWW-Authenticate` challenge, follow redirects, validate URI syntax, bind the
returned resource identifier to the request, choose an authorization server,
or apply AT Protocol policy. Those checks belong to discovery and profile
layers.

## Parsed fields

`resource` is required. It must be a nonempty JSON string and is copied
exactly after JSON string decoding.

`authorization_servers` is optional in generic RFC 9728 metadata. When
present, it must be a nonempty array of nonempty JSON strings. The parser
retains at most
`OAUTH2-RESOURCE-METADATA-MAX-AUTHORIZATION-SERVERS` values and
`OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER-BYTES` aggregate decoded
bytes. Duplicate decoded values are rejected, including duplicates expressed
with different JSON escape sequences.

Unknown top-level members are accepted only after the strict JSON dependency
has validated their complete values. Duplicate decoded object member names,
invalid UTF-8, malformed escapes, excessive nesting, trailing input, and
over-limit documents are rejected. A `signed_metadata` member is therefore
syntax-checked as an unknown member but is not verified or applied.

The parser deliberately performs no URI interpretation. In particular, a
higher RFC 9728 discovery owner must verify that `resource` is identical to
the resource identifier from which the well-known request URI was derived.
It must also validate every selected authorization-server issuer identifier
before use.

## Result and API

The caller owns one fixed result and one fixed scratch workspace:

```forth
CREATE metadata OAUTH2-RESOURCE-METADATA-SIZE ALLOT
CREATE work     OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE ALLOT

document document-u metadata work
    OAUTH2-RESOURCE-METADATA-PARSE
```

On success, the result owns all retained bytes and no longer borrows the
source document. Accessors return slices within that result:

```forth
OAUTH2-RESOURCE-METADATA-PRESENCE@
  ( metadata -- presence status )

OAUTH2-RESOURCE-METADATA-RESOURCE@
  ( metadata -- address length status )

OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER-COUNT@
  ( metadata -- count status )

OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@
  ( index metadata -- address length status )
```

`OAUTH2-RESOURCE-METADATA-VALID?` checks the result magic, public bounds,
required presence, and canonical contiguous list-entry geometry.

An authorization-server accessor returns
`OAUTH2-RESOURCE-METADATA-S-MISSING` when the optional array was absent.
An out-of-range or negative index returns
`OAUTH2-RESOURCE-METADATA-S-INVALID`.

## Presence bits and bounds

`OAUTH2-RESOURCE-METADATA-PRESENCE@` returns a bit set:

| Bit | Meaning |
|---|---|
| `OAUTH2-RESOURCE-METADATA-P-RESOURCE` | `resource` was present |
| `OAUTH2-RESOURCE-METADATA-P-AUTHORIZATION-SERVERS` | `authorization_servers` was present |
| `OAUTH2-RESOURCE-METADATA-P-ALL` | both recognized fields were present |

The public bounds are:

| Word | Bound |
|---|---:|
| `OAUTH2-RESOURCE-METADATA-MAX-MEMBERS` | 64 object members |
| `OAUTH2-RESOURCE-METADATA-TEXT-CAPACITY` | 2,048 decoded bytes per retained string |
| `OAUTH2-RESOURCE-METADATA-MAX-AUTHORIZATION-SERVERS` | 16 issuers |
| `OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER-BYTES` | 4,096 aggregate issuer bytes |

These are parser bounds, not an authorization policy. For example, the AT
Protocol OAuth profile applies the stricter rule that PDS metadata contain
exactly one authorization-server origin.

## Status values

| Status | Meaning |
|---|---|
| `OAUTH2-RESOURCE-METADATA-S-OK` | complete result published |
| `OAUTH2-RESOURCE-METADATA-S-INVALID` | invalid argument, result, or index |
| `OAUTH2-RESOURCE-METADATA-S-CAPACITY` | document, member, string, list, or output bound exceeded |
| `OAUTH2-RESOURCE-METADATA-S-ALIAS` | public spans overlap |
| `OAUTH2-RESOURCE-METADATA-S-JSON` | strict JSON, UTF-8, or nesting rejection |
| `OAUTH2-RESOURCE-METADATA-S-MISSING` | required `resource` or requested optional list missing |
| `OAUTH2-RESOURCE-METADATA-S-TYPE` | a recognized member or list element has the wrong type |
| `OAUTH2-RESOURCE-METADATA-S-VALUE` | a recognized string or list is empty |
| `OAUTH2-RESOURCE-METADATA-S-DUPLICATE` | duplicate decoded member name or authorization server |
| `OAUTH2-RESOURCE-METADATA-S-INTERNAL` | impossible subordinate result or caught staging exception |
| `OAUTH2-RESOURCE-METADATA-S-RANGE` | caller span has invalid physical geometry |
| `OAUTH2-RESOURCE-METADATA-S-PROTECTED` | caller span intersects protected platform storage |
| `OAUTH2-RESOURCE-METADATA-S-PLATFORM` | caller-span qualification failed unexpectedly |

Use `OAUTH2-RESOURCE-METADATA-STATUS-VALID?` to validate a status value.

## Ownership and publication

The complete source, result, and workspace spans are caller-qualified before
the first mutation and must be pairwise disjoint. Geometry rejection leaves
both result and workspace unchanged.

An admitted parse stages every retained byte in the workspace. Ordinary
failure leaves the prior result unchanged and clears the complete workspace.
Successful publication invalidates the destination magic, copies the staged
non-magic bytes, writes the magic last, and then clears the workspace.
Unexpected validation or staging throws become
`OAUTH2-RESOURCE-METADATA-S-INTERNAL` after mandatory cleanup. Publication
and cleanup throws propagate.

`OAUTH2-RESOURCE-METADATA-WORKSPACE-CLEAR` explicitly clears an admitted
workspace.

The protocol basis is
[RFC 9728](https://www.rfc-editor.org/rfc/rfc9728.html). The stricter
DID-to-PDS-to-authorization-server rules belong to the
[AT Protocol OAuth profile](https://atproto.com/specs/oauth).
