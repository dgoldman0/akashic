# AT Protocol public authorization-code token exchange

`akashic/atproto/oauth-token.f` is the thin AT Protocol policy adapter around
the generic protected authorization-code token-request owner, generic OAuth
form POST owner, authorization-server DPoP nonce owner, strict OAuth error
decoder, and AT token-grant admission boundary.

The adapter owns no transport, TLS connection, deadline, clock, DPoP key,
proof construction, persistent session, refresh exchange, confidential-client
assertion, XRPC request, repository state, or Streams state. It handles the
public-client authorization-code exchange only.

## Public API

Allocate one eight-byte-aligned serial operation workspace of the published
size:

```forth
AT-OAUTH-TOKEN-WORKSPACE-SIZE

AT-OAUTH-TOKEN-WORKSPACE-CLEAR
  ( workspace -- status )

AT-OAUTH-TOKEN-STATUS-VALID?
  ( status -- flag )
```

The exchange operations are:

```forth
AT-OAUTH-TOKEN-PREPARE
  ( config profile authorization token-request workspace -- status )

AT-OAUTH-TOKEN-BUILD
  ( dpop-a dpop-u config profile token-request post workspace -- status )

AT-OAUTH-TOKEN-ACCEPT-NONCE-CHALLENGE
  ( config profile token-request post nonce-owner workspace -- status )

AT-OAUTH-TOKEN-ACCEPT-SUCCESS
  ( base-ms config profile token-request post nonce-owner
    callback context workspace -- callback-result status )
```

The workspace capacity is derived symbolically from its header and the
largest subordinate workspace used serially by AT client admission, strict
OAuth error decoding, and AT grant admission. The adapter imposes no smaller
limit on caller-owned HTTP request, form, or response arenas.

## Preparation and immutable provenance

`AT-OAUTH-TOKEN-PREPARE` freshly admits the immutable client configuration
against the ready discovery profile before consuming an authorization code.
The selected client must satisfy the normal AT client policy and additionally
be a public client:

- `token_endpoint_auth_method` is exactly `none`;
- the client-authentication algorithm is absent; and
- DPoP-bound access tokens are required.

The profile must provide one normalized token target with no redirect history.
Preparation captures its RFC 9449 `htu` together with the one-shot O2CODE
grant into `O2TREQ`. It then verifies, while the copied request is borrowed,
that the authorization transaction required RFC 9207 issuer return, its
issuer exactly equals the profile issuer, and its opaque configuration binding
exactly equals the current immutable client binding. A mismatch abandons and
wipes the captured request. O2CODE remains spent because its code and verifier
were deliberately transferred through its one-shot handoff.

On success, `token-request` is in `O2TREQ-PHASE-READY`. It owns copied
code/verifier material and contains no retained raw address.

## Request construction

`AT-OAUTH-TOKEN-BUILD` accepts a nonempty caller-built DPoP proof. Proof
generation remains outside this raw adapter so a durable P-256 owner can bind
the proof to the current authorization-server nonce and a caller-supplied
trusted `iat`.

Every attempt uses a freshly configured `OAUTH2-HTTP-POST`; a retained result
from the first attempt is not reset in place. This preserves the first
challenge as evidence and gives a retry fresh caller-owned request, form, and
response arenas.

Before borrowing request secrets, BUILD re-admits the public client/profile
pair, requires the POST to be in `CONFIGURED`, and compares its complete
normalized target with the profile token target. The protected build loan then
rechecks the copied binding, mandatory issuer, token `htu`, and attempt
provenance before constructing these fields in deterministic order:

```text
grant_type=authorization_code
code=<copied authorization code>
redirect_uri=<immutable client redirect URI>
client_id=<immutable client ID>
code_verifier=<copied PKCE verifier>
```

The POST correlation token is the exact copied authorization state followed
by one internal byte identifying the first or retry attempt. This
address-free discriminator prevents retained first-attempt evidence from
being mistaken for the retry. Sealing includes the supplied `DPoP` header and
canonical absence of `Authorization`. A successful first build advances the
protected request to `FIRST-AWAITING`; a successful retry build advances it
to `RETRY-AWAITING`. An ordinary build failure does not consume the ready
attempt, although the caller must inspect and release any partially advanced
POST owner.

The caller binds a cooperative transport port and drives
`OAUTH2-HTTP-POST-START` / `POLL` under its own deadline.

## DPoP nonce challenge and sole retry

`AT-OAUTH-TOKEN-ACCEPT-NONCE-CHALLENGE` is valid for an awaiting attempt. It
re-admits the current client/profile and protected request provenance, then
requires all of the following retained POST evidence:

- terminal `RESULT` state with certain cleanup and successful generic POST
  processing;
- exact token target and exact authorization-state-plus-attempt correlation;
- DPoP both included and sent, with Authorization neither included nor sent;
- OAuth-error outcome with no hardening detail and HTTP status 400 or 401;
- a nonempty JSON body accepted by the strict generic OAuth error decoder;
- an error code exactly equal to `use_dpop_nonce`; and
- a mandatory retained `DPoP-Nonce`.

The nonce is installed through
`OAUTH2-DPOP-NONCE-REPLACE` for the exact copied/profile issuer. This requires
an already initialized owner for that authorization server and advances its
generation atomically. The adapter then calls `O2TREQ-CLAIM-RETRY`, which is
defined only for `FIRST-AWAITING`; therefore a second nonce challenge cannot
authorize another retry.

Caller-preflight failures and a cross-wired current configuration, profile,
protected request, target, correlation, or POST leave O2TREQ awaiting. This
lets the caller supply the correct retained result instead of destroying the
real in-flight attempt. Once exact attempt provenance and its terminal DPoP
POST envelope are established, a malformed, non-nonce, or second challenge
abandons the protected request and wipes its code/verifier material.

## Successful response

`AT-OAUTH-TOKEN-ACCEPT-SUCCESS` applies the same immutable provenance, target,
correlation, DPoP, Authorization-absence, terminal-result, and mandatory-nonce
checks. It additionally requires the successful semantic outcome, no
hardening detail, and HTTP status 200.

The retained nonce is first rotated into the exact issuer-bound nonce owner.
The JSON body is then passed to:

```forth
AT-OAUTH-GRANT-WITH  \ mode AT-OAUTH-GRANT-MODE-INITIAL
```

using the caller's nonnegative `base-ms`, profile, callback, and context. The
grant callback has the existing AT grant contract:

```forth
( grant context -- callback-result )
```

It may synchronously install the ephemeral grant into a generic protected
session. The adapter returns its one-cell result only when AT grant admission
succeeds.

After exact attempt provenance and its terminal DPoP POST envelope are
established, every success-acceptance path terminally wipes the protected
request, including malformed response policy, nonce-owner failure, token
policy rejection, and callback failure. Cross-wired selections and retained
results leave the real awaiting attempt unchanged. The retained POST remains
caller-owned diagnostic evidence.

## Ownership and cleanup

Complete fixed objects and the workspace are qualified before an operation
writes memory. Mutable owners are checked for overlap with each other, and
BUILD/ACCEPT inputs are admitted through the POST owner's external-span
boundary so they cannot alias its hidden request, form, or response arenas.
The operation workspace is wiped after every admitted return and caught
throw. It stores only transient addresses and serial subordinate scratch.

The configuration, profile, HTTP POST, nonce owner, protected request, DPoP
proof, and callback context remain caller-owned. One caller must serialize
access to each mutable owner. The proof and retained POST response spans must
remain stable for their synchronous calls.

## Status model

The closed `AT-OAUTH-TOKEN-S-*` vocabulary distinguishes:

- invalid input, capacity, alias, range, protected-memory, and platform
  failures;
- immutable client configuration, profile, protected transaction, binding,
  and exact-target failures;
- POST lifecycle, HTTP envelope, OAuth/AT response, DPoP, Authorization,
  nonce, and retry failures;
- grant-policy and callback failures; and
- internal invariant failure.

Subordinate range/protected/platform and capacity/alias categories are
preserved where the compact vocabulary has an exact equivalent. Detailed
generic lifecycle or policy failures map to their owning token-exchange
boundary. Use `AT-OAUTH-TOKEN-STATUS-VALID?` before interpreting a returned
status.
