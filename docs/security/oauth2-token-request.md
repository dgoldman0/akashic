# OAuth authorization-code token-request owner

`security/oauth2/token-request.f` is the provider-neutral protected owner for
one authorization-code token request and its single permitted retry. It sits
between the one-shot `O2CODE-WITH-GRANT` loan and a higher request
composition. It does not build a form, drive HTTP, parse an OAuth response,
manage a DPoP nonce, decode tokens, install a session, or apply AT Protocol
policy.

The complete `O2TREQ-SIZE` object is fixed-size and address-free. It copies
the authorization transaction's exact configuration binding, issuer and
issuer-required policy, state, authorization code, and PKCE verifier. It also
copies the exact token-endpoint HTU selected by the caller. The HTU storage
uses `HTARGET-URI-CAPACITY`; all grant fields use the corresponding symbolic
`O2CODE-*` capacities.

## Lifecycle

```text
EMPTY -> READY -> FIRST-AWAITING -> RETRY-READY -> RETRY-AWAITING
                    |                                 |
                    +------------> TERMINAL <---------+
```

`O2TREQ-CAPTURE` preflights destination publication. Before consuming the
authorization code, it validates the endpoint span and capacity, the empty
destination, the `CODE-READY` source, and all source/destination alias
relationships. It then invokes `O2CODE-WITH-GRANT`, copies the complete loan,
and publishes `READY`. Every admitted handoff consumes the one-shot source,
which enters `SPENT` and wipes its code, verifier, state, and challenge even
if the guarded callback ultimately fails. On such a failure the request owner
returns to canonical `EMPTY`; it never publishes a partial request.

`O2TREQ-WITH-BUILD` synchronously loans the retained request material to a
higher builder. A zero callback result advances `READY` to
`FIRST-AWAITING`, or `RETRY-READY` to `RETRY-AWAITING`. A nonzero callback
result leaves the corresponding ready phase unchanged so the caller may
repair its local build inputs and try that same attempt again. A throw or
wrong callback stack effect becomes `O2TREQ-S-CALLBACK` and likewise leaves
the request ready.

`O2TREQ-CLAIM-RETRY` is the only transition out of `FIRST-AWAITING` other
than termination or abandonment. It publishes `RETRY-READY`. There is no
transition from `RETRY-AWAITING` to a ready phase, so this owner cannot
authorize a second retry. The higher composition decides whether the first
result justifies that sole retry; this owner knows nothing about OAuth errors
or DPoP nonce challenges.

`O2TREQ-TERMINAL` accepts either awaiting phase after its response has been
handled. `O2TREQ-ABANDON` accepts any live phase when the surrounding
operation must stop. Both publish the same `TERMINAL` phase and wipe the
state, code, verifier, binding, issuer policy, and HTU. `O2TREQ-CLEAR?`
returns only `EMPTY` or `TERMINAL` objects to canonical `EMPTY`, which keeps
live destruction on the explicit terminal or abandonment paths.

## Public API

```forth
O2TREQ-SIZE                  ( -- bytes )
O2TREQ-HTU-CAPACITY          ( -- bytes )
O2TREQ-STATUS-VALID?         ( status -- flag )

O2TREQ-INIT?                 ( object -- status )
O2TREQ-INIT                  ( object -- )
O2TREQ-CLEAR?                ( object -- status )
O2TREQ-CLEAR                 ( object -- )
O2TREQ-PHASE@                ( object -- phase status )

O2TREQ-CAPTURE
  ( token-htu token-htu-u authcode object -- status )

O2TREQ-WITH-BUILD
  ( callback context object -- callback-status-or-request-status )

O2TREQ-CLAIM-RETRY           ( object -- status )

O2TREQ-WITH-PROVENANCE
  ( callback context object -- callback-status-or-request-status )

O2TREQ-TERMINAL              ( object -- status )
O2TREQ-ABANDON               ( object -- status )
```

The phases are:

```forth
O2TREQ-PHASE-EMPTY
O2TREQ-PHASE-READY
O2TREQ-PHASE-FIRST-AWAITING
O2TREQ-PHASE-RETRY-READY
O2TREQ-PHASE-RETRY-AWAITING
O2TREQ-PHASE-TERMINAL
```

The attempt values are:

```forth
O2TREQ-ATTEMPT-FIRST
O2TREQ-ATTEMPT-RETRY
```

## Build and provenance loans

The `O2TREQ-WITH-BUILD` callback receives:

```forth
( context
  binding binding-u
  issuer issuer-u issuer-required
  state state-u
  code code-u
  verifier verifier-u
  token-htu token-htu-u
  attempt
  -- callback-status )
```

The higher composition uses this loan to re-admit its immutable configuration
and endpoint metadata, build the exact request fields, retain the state as
local correlation, and create any attempt-specific proof. It must copy
anything needed after callback return. The callback is synchronous; every
address is a read-only borrow into the request owner.

Once the request is awaiting a result,
`O2TREQ-WITH-PROVENANCE` loans only the values needed to bind that result:

```forth
( context
  binding binding-u
  issuer issuer-u issuer-required
  state state-u
  token-htu token-htu-u
  attempt
  -- callback-status )
```

This lets the higher composition compare the HTTP owner's exact HTU and
correlation with the request that authorized it before parsing or acting on
the response. The authorization code and verifier are intentionally absent
from the result-side loan.

Both loans set a borrowed guard before invoking external code. Reentrant
mutation, retry claim, termination, abandonment, clearing, or another loan
returns `O2TREQ-S-BUSY`. `O2TREQ-PHASE@` remains observable. A callback must
consume its documented arguments and return exactly one cell; throws and
stack-contract violations are caught, the borrowed flag is restored, and the
safe pre-callback phase is retained.

## Ownership and ordering

The selected token HTU is opaque to this component. The caller must supply
the canonical endpoint value already admitted by its metadata policy, normally
the span returned by `HTARGET-HTU$`. This component enforces only nonempty
bounded storage and exact byte retention; it does not rediscover or infer an
endpoint.

The owner contains no lock and no raw address. One higher owner serializes its
operations and may protect or serialize the complete fixed-size object when
it is not borrowed. A durable flow copies the O2CODE loan into this object,
checkpoints the authorization transaction's `SPENT` state and this owner's
`READY` state, then permits request construction and transmission. It
checkpoints an awaiting phase before treating an external request as
authorized. Persistence remains responsible for confidentiality, integrity,
atomic replacement, and rollback protection.
