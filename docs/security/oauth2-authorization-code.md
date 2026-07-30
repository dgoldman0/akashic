# OAuth authorization-code transaction

`security/oauth2/authorization-code.f` is the generic, caller-owned state
machine for one OAuth authorization-code attempt. It is independent of HTTP,
provider discovery, AT Protocol, Streams, browsers, clocks, and persistence.

The transaction is a fixed-size, address-free byte object. It owns an opaque
configuration binding, the expected issuer, state, PKCE material, the accepted
PAR request URI and deadline, an authorization code, and bounded denial
diagnostics. It never retains source, callback, context, object, or workspace
addresses. A higher owner may therefore protect and serialize the complete
`O2CODE-TRANSACTION-SIZE` bytes without translating pointers.

The separate `O2CODE-WORKSPACE-SIZE` scratch area contains all transient
addresses, parser bookkeeping, decoded query fields, raw entropy, and PKCE
scratch. Every admitted `O2CODE-PREPARE` and
`O2CODE-ACCEPT-CALLBACK` path wipes the full workspace, including returned
errors and caught internal throws. Geometry failures occur before that wipe
and leave the workspace and transaction unchanged.

## Lifecycle

The phases are:

```text
EMPTY -> PREPARED -> PAR-READY -> AWAITING
                                  |       |
                                  v       v
                              CODE-READY DENIED
                                  |
                                  v
                                SPENT
```

- `PREPARE` generates separate state and PKCE secrets.
- `WITH-PAR` may be repeated while `PREPARED`, including after an HTTP-layer
  DPoP nonce challenge. Its guarded loan includes the retained issuer policy
  and state so the outgoing request owner can retain exact provenance.
- `ACCEPT-PAR` first matches that outgoing issuer policy and correlation
  token against the still-`PREPARED` transaction, then binds the opaque
  request URI and its caller-clock deadline.
- `WITH-LAUNCH` consumes that URI exactly once and enters `AWAITING` before
  calling external code.
- `ACCEPT-CALLBACK` either leaves `AWAITING` unchanged, installs a code and
  enters `CODE-READY`, or records an authorization denial and enters
  `DENIED`.
- `WITH-GRANT` consumes the code and verifier exactly once and enters
  `SPENT` before calling external code.

`O2CODE-CLEAR?` returns any non-borrowed valid object to `EMPTY` and wipes its
full fixed-size representation.

## Public API

Object and workspace management:

```forth
O2CODE-TRANSACTION-SIZE  ( -- bytes )
O2CODE-WORKSPACE-SIZE    ( -- bytes )

O2CODE-INIT?             ( object -- status )
O2CODE-INIT              ( object -- )
O2CODE-CLEAR?            ( object -- status )
O2CODE-CLEAR             ( object -- )
O2CODE-WORKSPACE-CLEAR   ( workspace -- status )
O2CODE-PHASE@            ( object -- phase status )
```

Authorization flow:

```forth
O2CODE-PREPARE
  ( binding binding-u expected-issuer expected-issuer-u
    issuer-required object workspace -- status )

O2CODE-WITH-PAR
  ( callback context object -- callback-status-or-O2CODE-status )

O2CODE-ACCEPT-PAR
  ( expected-issuer expected-issuer-u issuer-required
    correlation correlation-u request-uri request-uri-u
    expires-in now-seconds object -- status )

O2CODE-WITH-LAUNCH
  ( callback context now-seconds object
    -- callback-status-or-O2CODE-status )

O2CODE-ACCEPT-CALLBACK
  ( raw-query raw-query-u object workspace -- status )

O2CODE-WITH-GRANT
  ( callback context object -- callback-status-or-O2CODE-status )

O2CODE-ERROR@
  ( object -- error error-u description description-u status )
```

The `WITH-PAR` callback receives:

```forth
( context binding binding-u issuer issuer-u issuer-required
  state state-u challenge challenge-u -- callback-status )
```

The HTTP owner copies those values into its PAR request, retains the exact
issuer policy and state as result provenance, and supplies the literal
`S256` code-challenge method. The callback's borrowed addresses are valid
only for that invocation.

The `WITH-LAUNCH` callback receives:

```forth
( context binding binding-u issuer issuer-u issuer-required
  request-uri request-uri-u -- callback-status )
```

The transaction enters `AWAITING` before the callback. The request URI is
wiped after callback return, throw, or stack-contract violation. Because the
external launch may have occurred before a failure became observable, it is
never made retryable.

The binding, issuer, and request-URI spans are read-only borrows valid only for
that invocation. The issuer loan is the exact policy retained during
`PREPARE`. A provider adapter uses it with its independently retained metadata
to prove that the selected authorization endpoint belongs to the same
authorization-server profile that issued the accepted PAR result. This is
metadata provenance, not a same-origin inference, and it must not be inferred
from the opaque request URI.

The `WITH-GRANT` callback receives:

```forth
( context binding binding-u issuer issuer-u issuer-required
  state state-u code code-u verifier verifier-u -- callback-status )
```

The transaction enters `SPENT` before the callback. The code, verifier,
state, and challenge are wiped after callback return, throw, or
stack-contract violation. An asynchronous token request must copy the
borrowed values into its own protected request transaction before returning.
The retained state gives that request transaction one attempt-unique local
correlation value; the issuer loan lets a provider adapter prove that its
selected token endpoint belongs to the same authorization-server profile.

Each callback must consume its documented arguments and return exactly one
cell. A throw or wrong stack effect maps to `O2CODE-S-CALLBACK`. The phase
transition and secret consumption are not rolled back. Reentrant mutation or
another borrow while any callback is active returns `O2CODE-S-BUSY`;
`O2CODE-PHASE@` remains available for observing the transition.

## State and PKCE

`O2CODE-PREPARE` obtains 32 state bytes through the checked architectural
`ENTROPY-FILL` service and publishes their unpadded base64url encoding, which
is exactly 43 bytes. It independently calls `OAUTH2-PKCE-GENERATE`, which
obtains another 32 bytes through the same checked hardware entropy service,
publishes a 43-byte verifier, and derives the 43-byte S256 challenge with the
checked hardware SHA-256 path.

The module does not know a TRNG MMIO address and does not implement a software
random fallback. Entropy and crypto failures are explicit statuses.

## PAR and time

`O2CODE-ACCEPT-PAR` accepts the already-decoded successful PAR fields. The
HTTP owner must first require exactly `201 Created` and a JSON media type,
then use `OAUTH2-PAR-RESPONSE-WITH` to decode `request_uri` and
`expires_in`. It must also return the exact issuer bytes, issuer-required
policy, and correlation token retained from the outgoing `WITH-PAR` loan.
The issuer and policy must match the transaction or acceptance returns
`O2CODE-S-ISSUER`; the correlation token must match the retained state or
acceptance returns `O2CODE-S-STATE`. These checks, including all span and
alias admission, precede mutation.

`request_uri` remains opaque. This module binds its bytes to the current
transaction and enforces one-shot release, but does not impose a
server-specific URI format. `expires_in` must be positive and no greater than
`O2CODE-MAX-PAR-EXPIRES-IN`. `now-seconds + expires-in` is checked for signed
cell overflow before publication.

The caller owns the time source. Values must be nonnegative seconds from a
domain that does not move backward while a `PAR-READY` object may be restored.
`WITH-LAUNCH` requires `now-seconds` to be strictly less than the stored
deadline. The deadline is retained afterward as nonsecret transaction audit
metadata.

## Callback response policy

`O2CODE-ACCEPT-CALLBACK` accepts the raw query bytes without the leading `?`
or any fragment. It implements strict
`application/x-www-form-urlencoded` component decoding:

- at most 32 parameters, 16,384 source bytes, and 2,048 total decoded
  parameter-name bytes;
- `&` pair separation and the first `=` as the name/value boundary;
- malformed percent triplets rejected;
- duplicate names rejected after decoding, including unknown names and
  alternate encodings of the same name;
- unknown parameter values fully form-decoding-validated and otherwise
  ignored.

Recognized names are `code`, `state`, `iss`, `error`, and
`error_description`. `state` is mandatory and compared to the fixed 43-byte
generated value with a non-short-circuit accumulator over all 43 bytes. A
present `iss` must exactly match the configured expected issuer. With
`O2CODE-ISSUER-REQUIRED`, it is also mandatory; with
`O2CODE-ISSUER-OPTIONAL`, omission is allowed for deployments that use
another mix-up defense, but a present value is still checked.

Exactly one of `code` and `error` is required. A code is a nonempty bounded
RFC 6749 VSCHAR string. Error and description use the RFC 6749 NQSCHAR
alphabet, and a description without an error is rejected. A valid error
response enters `DENIED`, wipes authorization secrets, and returns
`O2CODE-S-DENIED`; `O2CODE-ERROR@` then exposes its bounded diagnostics.

Malformed encoding, duplicates, missing or mismatched state, missing or
mismatched issuer, and invalid success/error structure do not mutate the
`AWAITING` transaction. This prevents an unsolicited bad callback from
consuming the genuine browser attempt.

## Persistence and ownership

The opaque binding is intentionally uninterpreted. A durable owner resolves
it to immutable client configuration, endpoints, redirect URI, scope, and
the DPoP key used for this attempt. Keeping those policy objects outside the
transaction avoids provider and AT Protocol coupling.

The object has no internal lock. One owner must serialize calls and must not
checkpoint it while a callback borrow is active. Durable storage must provide
confidentiality, integrity, atomic replacement, rollback protection
appropriate to its threat model, and validation through a public operation
after restoration.

For durable sequencing, the launch or grant callback copies its borrowed
material into a protected caller transaction and returns without performing
the external side effect. The owner then checkpoints the now-nonborrowed
`AWAITING` or `SPENT` object before allowing the browser launch or token
request, respectively.

This module implements the client-side state, issuer, PKCE, and one-shot
binding rules described by
[RFC 6749](https://www.rfc-editor.org/rfc/rfc6749.html),
[RFC 7636](https://www.rfc-editor.org/rfc/rfc7636.html),
[RFC 9126](https://www.rfc-editor.org/rfc/rfc9126.html), and
[RFC 9207](https://www.rfc-editor.org/rfc/rfc9207.html). The higher OAuth
profile remains responsible for the additional deployment requirements in
[RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html).
