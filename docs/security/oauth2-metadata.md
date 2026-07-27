# OAuth 2 authorization-server metadata

`security/oauth2/metadata.f` is a strict, bounded parser for the subset of
OAuth authorization-server metadata needed by authorization-code, PKCE, PAR,
and DPoP clients.

```forth
REQUIRE security/oauth2/metadata.f
```

The module is deliberately transport- and profile-neutral. It does not fetch
metadata, follow redirects, cache documents, validate URLs, bind an issuer to
an HTTP origin or AT Protocol identity, or decide whether a client may
continue. Those checks belong to discovery and profile layers.

## Parsed fields

`issuer` is the only field required by this generic parser. It must be a
nonempty JSON string.

The following fields are optional. When present, each must have exactly the
listed JSON type:

| Field | Accepted value |
|---|---|
| `authorization_endpoint` | nonempty string |
| `token_endpoint` | nonempty string |
| `pushed_authorization_request_endpoint` | nonempty string |
| `require_pushed_authorization_requests` | boolean |
| `response_types_supported` | array of nonempty strings |
| `grant_types_supported` | array of nonempty strings |
| `code_challenge_methods_supported` | array of nonempty strings |
| `dpop_signing_alg_values_supported` | array of nonempty strings |
| `token_endpoint_auth_methods_supported` | array of nonempty strings |
| `scopes_supported` | array of nonempty strings |
| `token_endpoint_auth_signing_alg_values_supported` | array of nonempty strings |
| `authorization_response_iss_parameter_supported` | boolean |
| `require_request_uri_registration` | boolean |
| `client_id_metadata_document_supported` | boolean |

Each recognized array is limited to 64 decoded values and 4096 decoded bytes.
Duplicate decoded array values are rejected. Thus `"S256"` and
`"\u0053256"` are the same value for duplicate and capability purposes.

Unknown top-level members are accepted, but only after the strict JSON layer
has completely validated their values, including nested arrays and objects.
Duplicate decoded object member names, invalid UTF-8, malformed escapes,
invalid numbers, excessive nesting, trailing input, and over-limit documents
are rejected.

The parser copies JSON-decoded issuer and endpoint bytes exactly. It performs
no case folding, URL normalization, origin comparison, or trailing-slash
adjustment.

## Result and API

The caller owns a fixed result and a fixed scratch workspace:

```forth
CREATE metadata OAUTH2-METADATA-SIZE ALLOT
CREATE work     OAUTH2-METADATA-WORKSPACE-SIZE ALLOT

document document-u metadata work OAUTH2-METADATA-PARSE
```

On success, the result is self-contained and no longer borrows the source
document. Accessors return slices inside the result:

```forth
OAUTH2-METADATA-PRESENCE@          ( metadata -- presence status )
OAUTH2-METADATA-FLAGS@             ( metadata -- flags status )
OAUTH2-METADATA-ISSUER@            ( metadata -- a u status )
OAUTH2-METADATA-AUTHORIZATION-ENDPOINT@
                                     ( metadata -- a u status )
OAUTH2-METADATA-TOKEN-ENDPOINT@    ( metadata -- a u status )
OAUTH2-METADATA-PAR-ENDPOINT@      ( metadata -- a u status )

OAUTH2-METADATA-TOKEN-AUTH-COUNT@  ( metadata -- count status )
OAUTH2-METADATA-TOKEN-AUTH@        ( index metadata -- a u status )
OAUTH2-METADATA-TOKEN-AUTH-METHOD?
  ( method-a method-u metadata -- supported status )

OAUTH2-METADATA-SCOPE-COUNT@       ( metadata -- count status )
OAUTH2-METADATA-SCOPE@             ( index metadata -- a u status )
OAUTH2-METADATA-SCOPE?
  ( scope-a scope-u metadata -- supported status )

OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG-COUNT@
                                      ( metadata -- count status )
OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG@
                                      ( index metadata -- a u status )
OAUTH2-METADATA-TOKEN-AUTH-SIGNING-ALG?
  ( alg-a alg-u metadata -- supported status )
```

An accessor for an absent optional field returns
`OAUTH2-METADATA-S-MISSING`. `OAUTH2-METADATA-ISSUER@` cannot be absent from
a valid result.

`OAUTH2-METADATA-VALID?` checks the fixed result header, bounds, field
presence, canonical retained-list entry geometry, and consistency between
presence, derived capability flags, and retained list values. The result
remains caller-owned and may be cleared or discarded directly.

## Presence and capability bits

`OAUTH2-METADATA-PRESENCE@` reports which recognized fields occurred:

| Presence bit | Field |
|---|---|
| `OAUTH2-METADATA-P-ISSUER` | `issuer` |
| `OAUTH2-METADATA-P-AUTHORIZATION-ENDPOINT` | `authorization_endpoint` |
| `OAUTH2-METADATA-P-TOKEN-ENDPOINT` | `token_endpoint` |
| `OAUTH2-METADATA-P-PAR-ENDPOINT` | `pushed_authorization_request_endpoint` |
| `OAUTH2-METADATA-P-REQUIRE-PAR` | `require_pushed_authorization_requests` |
| `OAUTH2-METADATA-P-RESPONSE-TYPES` | `response_types_supported` |
| `OAUTH2-METADATA-P-GRANT-TYPES` | `grant_types_supported` |
| `OAUTH2-METADATA-P-CODE-CHALLENGE-METHODS` | `code_challenge_methods_supported` |
| `OAUTH2-METADATA-P-DPOP-ALGORITHMS` | `dpop_signing_alg_values_supported` |
| `OAUTH2-METADATA-P-TOKEN-AUTH-METHODS` | `token_endpoint_auth_methods_supported` |
| `OAUTH2-METADATA-P-SCOPES` | `scopes_supported` |
| `OAUTH2-METADATA-P-TOKEN-AUTH-SIGNING-ALGORITHMS` | `token_endpoint_auth_signing_alg_values_supported` |
| `OAUTH2-METADATA-P-AUTHORIZATION-RESPONSE-ISS` | `authorization_response_iss_parameter_supported` |
| `OAUTH2-METADATA-P-REQUIRE-REQUEST-URI-REGISTRATION` | `require_request_uri_registration` |
| `OAUTH2-METADATA-P-CLIENT-ID-METADATA-DOCUMENT` | `client_id_metadata_document_supported` |

`OAUTH2-METADATA-FLAGS@` reports validated values without imposing client
policy:

| Capability bit | Meaning |
|---|---|
| `OAUTH2-METADATA-F-PAR-REQUIRED` | the PAR-required boolean is present and `true` |
| `OAUTH2-METADATA-F-RESPONSE-CODE` | response types include `code` |
| `OAUTH2-METADATA-F-GRANT-AUTHORIZATION-CODE` | grants include `authorization_code` |
| `OAUTH2-METADATA-F-GRANT-REFRESH-TOKEN` | grants include `refresh_token` |
| `OAUTH2-METADATA-F-PKCE-S256` | PKCE methods include `S256` |
| `OAUTH2-METADATA-F-DPOP-ES256` | DPoP algorithms include `ES256` |
| `OAUTH2-METADATA-F-TOKEN-AUTH-NONE` | token authentication methods include `none` |
| `OAUTH2-METADATA-F-TOKEN-AUTH-PRIVATE-KEY-JWT` | token authentication methods include `private_key_jwt` |
| `OAUTH2-METADATA-F-TOKEN-AUTH-SIGNING-ES256` | token authentication signing algorithms include `ES256` |
| `OAUTH2-METADATA-F-AUTHORIZATION-RESPONSE-ISS` | the authorization-response issuer-parameter boolean is present and `true` |
| `OAUTH2-METADATA-F-REQUIRE-REQUEST-URI-REGISTRATION` | the request-URI-registration boolean is present and `true` |
| `OAUTH2-METADATA-F-CLIENT-ID-METADATA-DOCUMENT` | the client-ID metadata-document boolean is present and `true` |

A missing field or missing registered value leaves its bit clear and does not
make parsing fail. A later AT Protocol profile validator can therefore
distinguish absence from a present `false` boolean or a present list lacking
the required value.

The complete bounded `token_endpoint_auth_methods_supported`,
`scopes_supported`, and
`token_endpoint_auth_signing_alg_values_supported` lists are retained because
a generic OAuth client may need values beyond the convenience flags.
Enumeration preserves document order. Membership comparison is exact over
decoded bytes. In particular, this generic layer does not assign a dedicated
flag to any profile-specific scope; callers query the retained scope set.

## Status values

| Status | Meaning |
|---|---|
| `OAUTH2-METADATA-S-OK` | complete result published |
| `OAUTH2-METADATA-S-INVALID` | invalid argument or result |
| `OAUTH2-METADATA-S-CAPACITY` | document, member, string, array, or output bound exceeded |
| `OAUTH2-METADATA-S-ALIAS` | public spans overlap |
| `OAUTH2-METADATA-S-JSON` | strict JSON syntax, UTF-8, or nesting rejection |
| `OAUTH2-METADATA-S-MISSING` | required issuer missing, or an accessor selected an absent optional field |
| `OAUTH2-METADATA-S-TYPE` | a recognized field or array element has the wrong JSON type |
| `OAUTH2-METADATA-S-VALUE` | a recognized string or array element is empty |
| `OAUTH2-METADATA-S-DUPLICATE` | duplicate decoded member name or supported-list value |
| `OAUTH2-METADATA-S-INTERNAL` | an impossible subordinate result or caught staging exception |
| `OAUTH2-METADATA-S-RANGE` | caller span has invalid physical geometry |
| `OAUTH2-METADATA-S-PROTECTED` | caller span intersects platform-private storage |
| `OAUTH2-METADATA-S-PLATFORM` | caller-span qualification failed unexpectedly |

## Memory and publication contract

The complete source, result, and workspace spans are caller-qualified before
the first mutation, and all three must be pairwise disjoint. Rejected
preflight calls leave both result and workspace unchanged.

The borrowed source document must remain readable and byte-stable until
`OAUTH2-METADATA-PARSE` returns. It is not retained afterward.

After admission, strict object parsing, string decoding, array validation, and
result construction occur in the workspace. A returned failure leaves the
result unchanged and clears the complete workspace. Successful publication
invalidates the destination magic, copies all non-magic bytes, and writes the
magic last. A publication `THROW` therefore cannot leave a partially copied
result valid. Publication and cleanup `THROW`s propagate; a validation or
staging `THROW` becomes `OAUTH2-METADATA-S-INTERNAL` after successful
mandatory cleanup.

`OAUTH2-METADATA-WORKSPACE-CLEAR` explicitly clears an admitted workspace.
