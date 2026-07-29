# AT Protocol OAuth discovery profile

`akashic/atproto/oauth-profile.f` is the transport-free trust-chain layer
between AT Protocol identity resolution and the generic Akashic OAuth
libraries. It binds one resolved DID and PDS to one authorization server and
publishes the three OAuth endpoints only after the complete AT Protocol server
profile has passed.

The module does not fetch metadata. HTTP response policy is deliberately a
separate adapter concern, and tokens, DPoP keys and nonces, authorization
callbacks, durable sessions, XRPC, and Streams are outside this object.

## Ownership and lifecycle

The caller allocates `AT-OAUTH-PROFILE-SIZE` bytes on an eight-byte boundary.
The object retains no borrowed metadata or identity pointers. Each retained
HTTPS target has an object-local whole-record corruption checksum; structural
validation also requires zero redirect provenance before any target accessor
can publish it. The checksum detects accidental mutation and is not an
authentication primitive.

1. `AT-OAUTH-PROFILE-INIT` publishes an `EMPTY` profile.
2. `AT-OAUTH-PROFILE-BEGIN` accepts an `ATID-RESULT-READY?` identity with a
   declared PDS. It copies the DID and PDS target, then publishes the exact
   protected-resource metadata target.
3. `AT-OAUTH-PROFILE-RESOURCE!` accepts a valid generic
   `OAUTH2-RESOURCE-METADATA` result. It binds the `resource` member to the PDS
   and selects the sole authorization-server origin.
4. `AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!` accepts a valid generic
   `OAUTH2-METADATA` result. It binds the issuer, enforces the AT OAuth
   capabilities, parses all required endpoints, and publishes `READY`.

Caller geometry, alias, and wrong-phase errors leave the object unchanged.
Semantic identity, binding, metadata-profile, and endpoint failures wipe every
partial result and publish a structurally valid terminal `FAILED` object with
the reason in `AT-OAUTH-PROFILE-STATUS@`. Trusted accessors then fail closed.
Only `AT-OAUTH-PROFILE-INIT` can start another attempt. `WIPE` removes the
object completely and leaves all bytes zero.

OAuth discovery requires a resolved identity with a PDS, but it does not
require the DID document's repository signing key.
`ATID-PARTICIPATION-READY?` is therefore intentionally not the admission gate;
the repository key becomes relevant in the later record-writing composition.

## Exact origin binding

`HTARGET` represents an HTTPS origin target with a root request target, so its
URI view ends in `/`. AT OAuth resource and issuer identifiers use the
canonical origin serialization without that root slash:

```text
https://host.example
https://host.example:8443
```

The profile derives that serialization only after proving that the retained
target's request target is exactly `/`. It then compares the decoded
`resource`, selected `authorization_servers` value, and returned `issuer` by
exact bytes. It does not use URL equivalence or same-origin comparison for
these bindings.

Consequently, uppercase host spelling, an explicit default `:443`, a trailing
slash, path, query, credentials, fragment, or IP-literal spelling cannot be
smuggled through normalization. A nondefault port is retained and allowed.

The well-known targets are:

```text
<PDS origin>/.well-known/oauth-protected-resource
<authorization-server origin>/.well-known/oauth-authorization-server
```

The protected-resource metadata must contain `authorization_servers`, and the
array must contain exactly one canonical simple HTTPS origin.

## Authorization-server requirements

The authorization-server metadata must provide all of the following:

- authorization, token, and pushed-authorization-request endpoints;
- response type `code`;
- grant types `authorization_code` and `refresh_token`;
- PKCE method `S256`;
- DPoP signing algorithm `ES256`;
- token authentication methods `none` and `private_key_jwt`;
- token authentication signing algorithm `ES256`, with signing algorithm
  `none` absent;
- scope `atproto`;
- `require_pushed_authorization_requests: true`;
- `authorization_response_iss_parameter_supported: true`; and
- `client_id_metadata_document_supported: true`.

`require_request_uri_registration` follows the AT profile's default-true
rule: absence or explicit `true` is accepted, while explicit `false` is
rejected.

Each endpoint must independently parse as an admitted HTTPS target. OAuth does
not require the authorization, token, and PAR endpoints to share the issuer's
origin, so this layer does not impose that restriction.

## Accessors

Identity accessors become available after `BEGIN`:

- `AT-OAUTH-PROFILE-DID@`
- `AT-OAUTH-PROFILE-RESOURCE@`
- `AT-OAUTH-PROFILE-PDS-TARGET@`
- `AT-OAUTH-PROFILE-RESOURCE-METADATA-TARGET@`

Authorization-server accessors become available after protected-resource
binding:

- `AT-OAUTH-PROFILE-ISSUER@`
- `AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-TARGET@`
- `AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-METADATA-TARGET@`

The authorization, token, and PAR target accessors become available only in
`READY`. All returned strings and targets are borrowed from the profile and
remain valid until reinitialization or wipe.

## HTTP-resource composition

The
[generic HTTP-resource adapter](oauth-profile-http-resource.md)
independently requires exact status `200`, `application/json`, zero redirects,
and exact requested and effective target matches before parsing and calling
either metadata transition. Its transient parser storage is caller-owned and
is wiped after each admitted submission.

## Remaining boundaries

Later composition must still bind the token response to this profile: the
token type must be DPoP, granted scope must contain `atproto`, and the token
`sub` must match the expected DID. Server-initiated authorization additionally
requires resolving that `sub` and repeating the PDS-to-issuer trust chain.
