# AT OAuth Client Selection Policy

`akashic/atproto/oauth-client.f` qualifies one immutable generic OAuth client
configuration for use with one ready AT OAuth discovery profile. It is a
read-only policy adapter: it does not fetch client metadata, launch a browser,
construct PAR requests, sign assertions or DPoP proofs, resolve keys, exchange
tokens, persist sessions, call XRPC, or depend on Streams.

The provider-neutral configuration remains in
`akashic/security/oauth2/client-config.f`. AT Protocol policy is layered over
that generic library rather than embedded in it.

## Public contract

```forth
AT-OAUTH-CLIENT-WORKSPACE-SIZE  \ 432 bytes

AT-OAUTH-CLIENT-WORKSPACE-CLEAR
  ( workspace -- status )

AT-OAUTH-CLIENT-STATUS-VALID?
  ( status -- flag )

AT-OAUTH-CLIENT-ADMIT
  ( config profile workspace -- status )
```

All three objects are caller-owned and must begin on an eight-byte boundary.
`config` must be a valid `OAUTH2-CLIENT-CONFIG`; `profile` must be a
structurally valid, ready `AT-OAUTH-PROFILE`. The 432-byte workspace must not
overlap either input.

Geometry, alias, invalid-config, and non-ready-profile failures are preflight
failures and leave the workspace unchanged. After fixed-span and alias
admission, configuration-record validation deliberately precedes profile
readiness, so `AT-OAUTH-CLIENT-S-CONFIG` wins when both records are unusable.
Once both records are admitted, every normal result wipes the complete
workspace; a thrown callback path wipes it as well. The configuration and
profile are read-only on every path.

The adapter consumes the generic configuration through
`OAUTH2-CLIENT-CONFIG-WITH`: the complete 11,072-byte immutable record is
validated once per admission, then its callback-scoped borrowed view supplies
the selected fields without repeated whole-record scans.

## Borrowed-view composition

Code already running inside an `OAUTH2-CLIENT-CONFIG-WITH` callback can reuse
the same validated configuration view:

```forth
AT-OAUTH-CLIENT-VIEW-ADMIT
  ( config-view profile workspace -- status )

AT-OAUTH-CLIENT-VIEW-REDIRECT-ADMIT
  ( redirect-a redirect-u config-view workspace -- status )
```

These words accept only the borrowed `config-view` supplied to that callback.
They do not turn an arbitrary address into a configuration and do not extend
the view lifetime.

`AT-OAUTH-CLIENT-VIEW-ADMIT` applies the complete local client policy against
one ready profile. It is the composable operation used by
`AT-OAUTH-CLIENT-ADMIT`, so a metadata binder can retain the generic owner's
single-validation guarantee instead of rescanning the immutable record. It
returns the same profile and semantic-policy statuses as ordinary admission;
`AT-OAUTH-CLIENT-S-CONFIG` is not a result for a valid borrowed view.

`AT-OAUTH-CLIENT-VIEW-REDIRECT-ADMIT` applies the same client-ID,
application-type, and redirect parsing used by complete admission to one
arbitrary nonempty redirect span. It does not test whether that redirect is
declared or selected. A metadata binder first proves exact selected-redirect
membership and then calls this word for every declared redirect. An invalid
borrowed client identifier returns `AT-OAUTH-CLIENT-S-CLIENT-ID`; an invalid
candidate returns `AT-OAUTH-CLIENT-S-REDIRECT`.

Both words qualify the complete borrowed-view and workspace spans, require an
eight-byte-aligned workspace, and reject overlap with that writable workspace.
The redirect word also qualifies its complete source span, bounds it to the
generic redirect capacity, and rejects source/workspace overlap. These
geometry, capacity, alias, and non-ready-profile checks are preflight failures
and leave every workspace byte unchanged. Once admitted, an operation wipes
the complete 432-byte workspace after success, policy rejection, or a caught
internal throw. The view, profile, redirect source, and configuration remain
read-only.

## Local AT policy

The adapter enforces the selected values which can be proven locally:

- `client_id` uses HTTPS, has no userinfo, fragment, or explicit port, has a
  literal path component, and has no single-dot or double-dot path component.
  A root path is accepted. A query is accepted because the generic Client ID
  Metadata Document draft says it “SHOULD NOT”, rather than “MUST NOT”, contain
  one.
- The current KDOS network profile accepts bounded ASCII DNS hostnames. Numeric
  IP literals (including browser-recognized hexadecimal, octal, and shortened
  forms), bracketed IP literals, trailing-dot names, and malformed labels are
  rejected. DNS resolution, public-address admission, IDNA policy, and TLS
  hostname authentication remain transport responsibilities.
- A web `redirect_uri` is HTTPS. It may be cross-origin and may have a
  nondefault port, but must not explicitly spell the default port `443`.
- A native `redirect_uri` is either HTTPS at the same effective origin as the
  `client_id`, or a custom scheme equal to the client-ID hostname in
  reverse-domain order. A custom scheme uses exactly `scheme:/path`; `://` is
  rejected. Queries are allowed and fragments are rejected.
- The scope string contains the exact, case-sensitive token `atproto`.
  Additional valid OAuth scope tokens are allowed.
- A public selection uses `token_endpoint_auth_method` `none` and no signing
  algorithm. A confidential web selection uses `private_key_jwt` with `ES256`.
  This adapter deliberately narrows native selections to public clients as a
  local deployment model, not as a general AT Protocol requirement. A mobile
  or desktop architecture with a token-mediating confidential backend is
  represented here by its web application component.
- `dpop_bound_access_tokens` is true. Both refresh-enabled and
  authentication-only selections are valid.

The ordinary production profile intentionally does not implement the optional
`http://localhost` development exception. Development support should be a
separate, explicit policy so it cannot silently weaken production admission.

Statuses distinguish invalid geometry, aliasing, invalid configuration,
non-ready discovery profile, `client_id`, `redirect_uri`, scope,
authentication method, authentication algorithm, DPoP, caller-memory range,
protected-memory, platform, and internal failures.

## Deployment qualification

`AT-OAUTH-CLIENT-ADMIT` proves that a selected runtime record is locally
compatible with the ready server profile. A production deployment must also
prove facts which are not present in that record:

- Fetch the Client ID Metadata Document from the exact `client_id` with an
  exact HTTP 200 response, `application/json`, no redirect, hardened
  public-address policy, authenticated TLS, and bounded response handling.
- Require the document's `client_id` to match the fetched URL byte-for-byte.
  An absent `application_type` has the specification-defined `web` default;
  an explicit value must match the selected application type.
- Require the selected redirect URI to be an exact, case-sensitive member of
  `redirect_uris`, and apply the AT redirect policy to every declared member.
  The selected configuration may choose one member from a larger valid set.
- Require every exact scope token requested by the selected configuration to
  occur in the metadata `scope`; the requested scope is a subset of the
  declared scope, not necessarily the same serialized string.
- Bind `grant_types`, `response_types`, explicit non-secret
  `token_endpoint_auth_method`, conditional
  `token_endpoint_auth_signing_alg`, and
  `dpop_bound_access_tokens` to the selected configuration and AT profile
  without inventing defaults for omitted authentication metadata.
- A confidential deployment supplies exactly one of `jwks` or `jwks_uri`,
  publishes only public client-authentication keys, and proves that the opaque
  configuration binding resolves to the corresponding private key. The
  client-authentication key and per-session DPoP key are distinct identities.
- A native deployment proves operating-system ownership of its custom scheme
  or HTTPS universal/app link.
- PAR, PKCE, browser state, authorization-response issuer checks, server-issued
  DPoP nonces, token exchange, key rotation, and durable session recovery are
  owned by later composition layers.

The normative references are the
[AT Protocol OAuth profile](https://atproto.com/specs/oauth),
[OAuth Client ID Metadata Document
draft](https://www.ietf.org/archive/id/draft-ietf-oauth-client-id-metadata-document-02.html),
and [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html) for native
application redirects.
