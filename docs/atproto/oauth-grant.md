# AT Protocol OAuth token-grant admission

`akashic/atproto/oauth-grant.f` is the state-free policy boundary between a
generic OAuth token response, a ready AT OAuth discovery profile, and the
generic durable OAuth session owner. It admits token bytes only while they are
inside the generic decoder's ephemeral callback, stages one
`O2SESSION-GRANT-SIZE` descriptor, and lends that descriptor to one synchronous
caller callback.

The module does not perform HTTP, create DPoP proofs, own DPoP keys or nonces,
sample a clock, allocate credential RIDs, mutate sessions, or retain token
bytes. It contains no Streams or application policy.

## Public API

```forth
AT-OAUTH-GRANT-WORKSPACE-SIZE

AT-OAUTH-GRANT-WORKSPACE-CLEAR
  ( workspace -- grant-status )

AT-OAUTH-GRANT-STATUS-VALID?
  ( grant-status -- flag )

AT-OAUTH-GRANT-MODE-VALID?
  ( mode -- flag )

AT-OAUTH-GRANT-WITH
  ( source source-u mode base-ms profile callback context workspace
    -- callback-result grant-status )
```

The modes are:

```forth
AT-OAUTH-GRANT-MODE-INITIAL
AT-OAUTH-GRANT-MODE-REFRESH
```

`profile` must be a structurally valid ready `AT-OAUTH-PROFILE`. `base-ms`
must be a nonnegative timestamp from the caller's trusted time domain.

## AT token policy

Both modes require:

- a generic response with its required access token and token type;
- token type `DPoP`, compared case-insensitively as required for OAuth token
  type names;
- a returned `scope` member containing the exact case-sensitive token
  `atproto`;
- a returned `sub` member which is a syntactically valid DID; and
- exact byte equality between that decoded subject and the DID bound into the
  ready discovery profile.

Scope membership is token-based. Values such as `xatproto`, `atprotox`, or a
different case do not satisfy the requirement.

Initial authorization permits an absent refresh token. This supports valid
authentication-only clients which do not request refresh capability. A
present refresh token is included in the staged grant.

Refresh mode requires a nonempty `refresh_token` member. Omission is rejected
before a generic session can apply its retain-on-omit behavior, so
`O2SESSION-REFRESH-COMMIT` cannot accidentally reuse the exposed credential.
The response member is treated as the authorization server's replacement
credential; this adapter has no borrowed view of the previously exposed token
and does not compare their bytes.

Unknown token-response members retain the generic decoder's strict-JSON,
ignore-after-validation behavior. `id_token` is not interpreted as the AT
subject. Identity comes only from the decoded `sub` member.

## Expiry

`expires_in` remains optional at the generic OAuth boundary. When absent, the
staged grant has no known-expiry flag and an all-zero expiry field.

When present, the adapter computes:

```text
expires_at_ms = base_ms + expires_in * 1000
```

Both multiplication and addition are checked against the largest nonnegative
cell value. Overflow rejects the response before the caller callback.
`expires_in: 0` is valid and produces an immediately expired grant at exactly
`base-ms`.

The caller should sample `base-ms` immediately before dispatching the token
request. Using that conservative request-side time avoids extending the
credential lifetime by network and response-processing delay. This adapter
does not add skew, clamp lifetimes, or schedule refresh.

## Ephemeral grant callback

After every policy check succeeds, `WITH` invokes:

```forth
( grant context -- callback-result )
```

`grant` points inside the AT grant workspace. Its access token, token type,
scope, and optional refresh-token spans point into the generic token-response
workspace. The descriptor sets:

- the required access-token and token-type fields;
- `O2SESSION-GRANT-F-SCOPE`;
- `O2SESSION-GRANT-F-REFRESH` only when a refresh token is present; and
- `O2SESSION-GRANT-F-EXPIRY` only when `expires_in` is present.

The ID-token fields and flag remain zero.

The callback may synchronously call `O2SESSION-INSTALL`,
`O2SESSION-REAUTHORIZE`, or `O2SESSION-REFRESH-COMMIT`. Those generic session
operations copy the admitted values into their own protected ownership. The
callback must not retain the grant pointer or any span returned through it.

A normal callback result is returned unchanged with
`AT-OAUTH-GRANT-S-OK`. A throw or a callback which does not consume its two
arguments and return exactly one cell becomes `AT-OAUTH-GRANT-S-CALLBACK`.
The adapter does not roll back a durable mutation which the callback may
already have completed.

## Geometry and cleanup

The complete workspace and profile must be eight-byte aligned and admitted by
the caller-span boundary. The nonempty source, complete workspace, and
complete profile must be pairwise disjoint. The callback execution token must
be nonzero, the mode must be known, and `base-ms` must be nonnegative.

Qualified preflight failures leave the workspace unchanged. Once an operation
is admitted, the adapter wipes the complete workspace before parsing and again
after every success, parser or policy rejection, callback failure, or caught
internal throw. The source and profile remain unchanged.

`AT-OAUTH-GRANT-WORKSPACE-CLEAR` lets a caller clear qualified workspace after
a preflight rejection.

## Statuses

Policy failures distinguish token type, scope, subject syntax, exact subject
binding, and missing refresh replacement. Generic JSON and value failures map
to `AT-OAUTH-GRANT-S-RESPONSE`; capacity, alias, and caller-memory failures
retain their categories. `PROFILE`, `TIME`, `OVERFLOW`, `CALLBACK`, and
`INTERNAL` identify their corresponding composition boundaries.

This layer closes identity-started token admission. Server-started
authorization remains separate: its untrusted returned `sub` must first be
resolved, and that identity's PDS-to-issuer trust chain must be rebuilt before
the grant can be admitted against a ready profile.
