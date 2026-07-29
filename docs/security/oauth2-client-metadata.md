# OAuth 2 Client ID Metadata Documents

`security/oauth2/client-metadata.f` is a generic, bounded decoder for an OAuth
Client ID Metadata Document. It validates one complete JSON object, exposes a
callback-scoped decoded view, and wipes its complete caller-owned workspace
after every admitted operation.

The component is deliberately below transport and deployment policy. It does
not fetch a document, follow redirects, normalize or compare URLs, apply
metadata defaults, validate a JWK Set, select keys, or decide whether an AT
Protocol deployment is usable. Parse success means that the document passed
this structural boundary; it is not by itself a claim of complete Client ID
Metadata Document validity.

The implementation follows
[Client ID Metadata Document draft -02](https://www.ietf.org/archive/id/draft-ietf-oauth-client-id-metadata-document-02.html),
[RFC 7591](https://www.rfc-editor.org/rfc/rfc7591.html), and the JSON rules in
[RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html). Relevant field
definitions also come from
[OpenID Connect Dynamic Client Registration](https://openid.net/specs/openid-connect-registration-1_0.html)
and [RFC 9449](https://www.rfc-editor.org/rfc/rfc9449.html).

## Recognized members

`client_id` is the only required member. Recognized optional members preserve
their explicit presence; this decoder never replaces omission with an RFC
default.

| Member | Structural rule |
|---|---|
| `client_id` | required, nonempty decoded string |
| `application_type` | optional, nonempty decoded string |
| `grant_types` | optional array of nonempty decoded strings |
| `response_types` | optional array of nonempty decoded strings |
| `redirect_uris` | optional array of nonempty decoded strings |
| `scope` | optional nonempty RFC 6749 scope string |
| `token_endpoint_auth_method` | optional nonempty string; the three registered `client_secret_*` methods are rejected |
| `token_endpoint_auth_signing_alg` | optional nonempty string; `none` is rejected |
| `dpop_bound_access_tokens` | optional JSON boolean |
| `jwks` | optional strict JSON object, retained as its exact source token |
| `jwks_uri` | optional nonempty decoded string |

`jwks` and `jwks_uri` are mutually exclusive. The forbidden
`client_secret` and `client_secret_expires_at` members are rejected even
though unknown extension members are otherwise accepted.

The three registered `client_secret_*` methods are known shared-secret
methods. Other method names remain structurally unclassified: parser
acceptance does not establish that an extension method is free of shared
secrets. A deployment qualifier must positively admit supported non-secret
methods and reject every unsupported method.

Unknown members are ignored only after strict recursive JSON validation.
Malformed UTF-8, invalid escapes or Unicode scalars, trailing input, excessive
nesting, invalid numbers, and duplicate decoded object member names are
rejected, including inside unknown members and the raw `jwks` object.

The three arrays preserve declaration order. A present empty array is distinct
from an absent array and is accepted at this generic layer. Each array is
bounded to 64 values and 4096 aggregate decoded bytes. Empty values and
duplicate decoded values are rejected. The specifications do not require
array values to be unique; duplicate rejection is an intentional canonical
subset used by this implementation rather than a claim about JSON syntax.

The scope validator accepts RFC 6749 `scope-token` bytes separated by exactly
one ASCII space. It rejects leading, trailing, or repeated spaces.

## Callback API

Allocate one 8-byte-aligned workspace:

```forth
OAUTH2-CLIENT-METADATA-WORKSPACE-SIZE  \ 53256 bytes

OAUTH2-CLIENT-METADATA-WORKSPACE-CLEAR
( workspace -- status )
```

Decode a document with:

```forth
OAUTH2-CLIENT-METADATA-WITH
( source source-u callback context workspace
  -- callback-status metadata-status )
```

The callback has this contract:

```forth
( view context -- callback-status )
```

After successful validation, the callback runs exactly once with the supplied
context cell and returns one uninterpreted application-status cell. A parse
or admission failure does not invoke it and returns zero as
`callback-status`. A callback throw, extra result, missing result, or attempt
to consume below its arguments becomes
`OAUTH2-CLIENT-METADATA-S-CALLBACK`.

The callback boundary checks both data-stack depth and a private guard
immediately below the callback arguments. An over-consuming callback cannot
evade the contract by returning compensating cells.

## Ephemeral view

Every view accessor first validates the complete live view and returns a
component status. The recognized-member bitset is available through:

```forth
OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
( view -- presence status )
```

The presence constants correspond one-for-one to the eleven recognized
members:

```forth
OAUTH2-CLIENT-METADATA-P-CLIENT-ID
OAUTH2-CLIENT-METADATA-P-APPLICATION-TYPE
OAUTH2-CLIENT-METADATA-P-GRANT-TYPES
OAUTH2-CLIENT-METADATA-P-RESPONSE-TYPES
OAUTH2-CLIENT-METADATA-P-REDIRECT-URIS
OAUTH2-CLIENT-METADATA-P-SCOPE
OAUTH2-CLIENT-METADATA-P-TOKEN-AUTH-METHOD
OAUTH2-CLIENT-METADATA-P-TOKEN-AUTH-SIGNING-ALG
OAUTH2-CLIENT-METADATA-P-DPOP-BOUND
OAUTH2-CLIENT-METADATA-P-JWKS
OAUTH2-CLIENT-METADATA-P-JWKS-URI
```

`OAUTH2-CLIENT-METADATA-P-ALL` is the mask of every known bit, not an
attainable exact valid declaration: the two key-source bits cannot coexist.

Decoded scalar accessors return `( address length status )`:

```forth
OAUTH2-CLIENT-METADATA-VIEW-CLIENT-ID@
OAUTH2-CLIENT-METADATA-VIEW-APPLICATION-TYPE@
OAUTH2-CLIENT-METADATA-VIEW-SCOPE@
OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-METHOD@
OAUTH2-CLIENT-METADATA-VIEW-TOKEN-AUTH-SIGNING-ALG@
OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
```

The boolean accessor returns `( flag status )`:

```forth
OAUTH2-CLIENT-METADATA-VIEW-DPOP-BOUND?
```

Each retained array has count, indexed, and exact-membership accessors:

```forth
OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE-COUNT@
OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE@
OAUTH2-CLIENT-METADATA-VIEW-GRANT-TYPE?

OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE-COUNT@
OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE@
OAUTH2-CLIENT-METADATA-VIEW-RESPONSE-TYPE?

OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI-COUNT@
OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI@
OAUTH2-CLIENT-METADATA-VIEW-REDIRECT-URI?
```

Count accessors return `( count status )`, indexed accessors return
`( address length status )`, and membership accessors return
`( present status )`. Membership comparison is exact and case-sensitive over
decoded bytes. A missing optional member returns
`OAUTH2-CLIENT-METADATA-S-MISSING`; a present empty array returns count zero
with `S-OK`.

`OAUTH2-CLIENT-METADATA-VIEW-JWKS@` returns the exact JSON object token:

```forth
( view -- source-address source-length status )
```

Unlike decoded strings, that span points into the input document. The source
must therefore remain readable and byte-stable throughout the callback.

The view, its decoded spans, and the raw `jwks` span are borrowed only during
the callback. The mandatory final wipe invalidates the view magic. Retaining
the view or any returned address after the callback is an error; subsequent
accessor calls fail with `S-INVALID`. Copy durable facts while the callback is
active, and treat the view as read-only.

## Bounds and admission

The parser reads at most
`OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES`, currently 5120 bytes. This
implements the current draft's recommended five-kilobyte processing ceiling.
The root object admits at most 64 members and 4096 aggregate decoded
member-name bytes.

Decoded scalar capacities are:

| Field | Bytes |
|---|---:|
| client identifier | 4096 |
| application type | 256 |
| scope | 4096 |
| token authentication method | 256 |
| token authentication signing algorithm | 256 |
| JWKS URI | 4096 |

Before taking ownership, `WITH` qualifies the complete source and workspace
spans, checks the workspace alignment, rejects a zero callback, enforces the
document bound, and proves source/workspace disjointness. A preflight failure
returns `( 0 metadata-status )` without changing any workspace byte.

Once admitted, the complete workspace is cleared before staging and wiped
again after success, parse rejection, callback failure, or a caught internal
throw. The source is never changed. Independent concurrent calls require
independent workspaces and stable source buffers.

## Downstream qualification

A fetch/qualification owner must still enforce the parts that require
transport context or semantic modules:

- exact HTTP 200 handling, accepted JSON media type, no automatic redirects,
  and hardened SSRF/address policy;
- byte-for-byte equality between decoded `client_id`, the Client Identifier
  URL, and the actual fetch URL, without URL normalization;
- Client Identifier URL and `jwks_uri` syntax and scheme policy;
- defining-spec defaults where a profile deliberately permits omission;
- allowed `application_type`, grant, response, authentication, signing, and
  scope values;
- defining-spec relationships among application type and redirects,
  response and grant declarations, and the authentication method, signing
  algorithm, and selected key source;
- checked selection with `JOSE-JWK-SET-P256-SELECT` for either inline `jwks`
  or a bounded fetched `jwks_uri` body, including full-set validation and
  rejection of private, symmetric, or unsupported key metadata; and
- exact agreement with the locally selected immutable client configuration.

The AT Protocol binder additionally requires its profile fields and values,
including DPoP, `atproto` scope, authorization-code declarations, selected
redirect membership, and explicit public or confidential authentication.
In particular, omission of `token_endpoint_auth_method` must not silently
become RFC 7591's `client_secret_basic` default.

## Status model

Use `OAUTH2-CLIENT-METADATA-STATUS-VALID?` before accepting an arbitrary
status cell.

| Status | Meaning |
|---|---|
| `OAUTH2-CLIENT-METADATA-S-OK` | structural validation and callback return completed |
| `OAUTH2-CLIENT-METADATA-S-INVALID` | invalid argument, alignment, live-view geometry, or index |
| `OAUTH2-CLIENT-METADATA-S-CAPACITY` | document, member, name, decoded field, or array bound exceeded |
| `OAUTH2-CLIENT-METADATA-S-ALIAS` | source overlaps the operation workspace |
| `OAUTH2-CLIENT-METADATA-S-JSON` | strict JSON, UTF-8, Unicode, or nesting rejection |
| `OAUTH2-CLIENT-METADATA-S-MISSING` | required `client_id` or a requested optional member is absent |
| `OAUTH2-CLIENT-METADATA-S-TYPE` | a recognized member or array element has the wrong JSON type |
| `OAUTH2-CLIENT-METADATA-S-VALUE` | a recognized value is empty, forbidden, or violates its field grammar |
| `OAUTH2-CLIENT-METADATA-S-DUPLICATE` | duplicate decoded member name or retained array value |
| `OAUTH2-CLIENT-METADATA-S-CALLBACK` | callback throw or stack-contract violation |
| `OAUTH2-CLIENT-METADATA-S-INTERNAL` | impossible subordinate result or caught non-callback throw |
| `OAUTH2-CLIENT-METADATA-S-RANGE` | caller span has invalid physical geometry |
| `OAUTH2-CLIENT-METADATA-S-PROTECTED` | caller span intersects protected platform storage |
| `OAUTH2-CLIENT-METADATA-S-PLATFORM` | caller-span qualification failed unexpectedly |

Consumers must check `metadata-status` before interpreting
`callback-status`.
