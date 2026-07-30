# AT Protocol OAuth browser authorization

`akashic/atproto/oauth-authorization.f` is the state-free AT Protocol adapter
between a successful pushed authorization request and the browser portion of
one authorization-code attempt. It combines:

- one immutable generic OAuth client configuration;
- one ready AT OAuth discovery profile; and
- one generic `O2CODE` transaction in `PAR-READY`.

The adapter consumes the transaction's one-shot launch loan and constructs the
exact bounded authorization URI. It owns no browser, redirect listener or
route, persistence transaction, token POST, DPoP key, authorization-server
nonce, session, XRPC, repository, or Streams state.

## Public API and caller capacity

```forth
AT-OAUTH-AUTHORIZATION-URL-CAPACITY  \ 19480 bytes
AT-OAUTH-AUTHORIZATION-WORKSPACE-SIZE  \ 496 bytes

AT-OAUTH-AUTHORIZATION-WORKSPACE-CLEAR
  ( workspace -- status )

AT-OAUTH-AUTHORIZATION-STATUS-VALID?
  ( status -- flag )

AT-OAUTH-AUTHORIZATION-LAUNCH
  ( config profile now-seconds transaction destination capacity workspace
    -- written status )
```

`AT-OAUTH-AUTHORIZATION-URL-CAPACITY` is a symbolically derived sufficient
allocation for every admitted authorization endpoint, client identifier, and
PAR request URI. It is not a required exact destination size or a maximum
caller span. `LAUNCH` admits any positive caller capacity, and capacities
larger than the sufficient allocation are valid. A smaller destination
succeeds when the exact encoded URI fits and otherwise returns
`AT-OAUTH-AUTHORIZATION-S-CAPACITY`.

The returned output is the first `written` bytes of `destination`; it has no
terminating NUL. On success the remainder of the complete caller-declared
capacity is zero. Callers that cannot independently establish a sufficient
bound should allocate the exported symbolic capacity.

`config`, `profile`, `transaction`, and `workspace` are complete caller-owned
objects on eight-byte boundaries. The destination is a caller-owned bounded
byte span. The workspace is a 64-byte orchestration header followed by one
serial `AT-OAUTH-CLIENT-WORKSPACE-SIZE` child. No pointer or operation state
survives an admitted call.

## Exact URI and provenance

`LAUNCH` first requires a valid immutable client configuration, a structurally
valid ready AT OAuth profile, a nonnegative caller-sampled time, and a valid
nonborrowed transaction in `O2CODE-PHASE-PAR-READY`. It then freshly borrows
the configuration through `OAUTH2-CLIENT-CONFIG-WITH` and applies
`AT-OAUTH-CLIENT-VIEW-ADMIT`; it does not trust the selection merely because
the earlier PAR operation admitted it.

Inside the transaction's guarded `O2CODE-WITH-LAUNCH` loan, the adapter proves:

- the retained opaque binding exactly matches the current admitted client
  view;
- the retained issuer policy is exactly `O2CODE-ISSUER-REQUIRED`; and
- the retained issuer bytes exactly match the current ready profile issuer.

The authorization endpoint is the exact
`AT-OAUTH-PROFILE-AUTHORIZATION-TARGET@` selected from the same profile. This
is metadata-profile provenance, not a same-origin shortcut: the AT OAuth
profile does not require its authorization, token, and PAR endpoints to share
the issuer origin.

The adapter copies the canonical endpoint URI, preserves any existing query,
selects `?` or `&` as appropriate, and appends exactly these fields in this
order:

```text
client_id=<form-encoded immutable client identifier>
request_uri=<form-encoded opaque PAR request URI>
```

The original authorization fields are not repeated. This is the PAR browser
continuation required by the
[AT Protocol OAuth specification](https://atproto.com/specs/oauth).
The request URI remains opaque; it is neither parsed nor used to infer the
authorization server.

## One-shot lifecycle and durable ordering

`O2CODE-WITH-LAUNCH` checks the retained PAR deadline and moves the transaction
from `PAR-READY` to `AWAITING` before invoking the adapter callback. It wipes
the retained request URI after callback return, throw, or stack-contract
failure. Once that loan begins, the transition is deliberately not rolled
back.

This matters for caller-selected capacities. A too-small destination can be
discovered only while the one-shot request URI is borrowed. Such a
`CAPACITY` result is terminal for that transaction: it returns zero written
bytes, clears the admitted destination, leaves the transaction in `AWAITING`,
and cannot be retried. The exported sufficient capacity avoids this failure
for every admitted input.

The durable caller should order the continuation as follows:

1. copy the successful PAR response nonce into the explicit
   authorization-server nonce owner and checkpoint the nonborrowed
   `PAR-READY` transaction;
2. call `AT-OAUTH-AUTHORIZATION-LAUNCH`;
3. on success, checkpoint the now-nonborrowed `AWAITING` transaction and its
   caller-owned launch URI before performing the browser side effect;
4. admit the returned redirect through the exact route selected by the
   immutable client configuration;
5. pass only the raw redirect query, without the leading `?` or any fragment,
   to `O2CODE-ACCEPT-CALLBACK`; and
6. after `CODE-READY`, use `O2CODE-WITH-GRANT` to copy the exact binding,
   authorization code, and PKCE verifier into a separately owned protected
   token request before returning.

`O2CODE-ACCEPT-CALLBACK` enforces the generated state and mandatory exact
issuer. A valid authorization denial enters `DENIED`; malformed encoding,
mix-up evidence, or an unsolicited response leaves the genuine `AWAITING`
attempt unchanged. `O2CODE-WITH-GRANT` publishes `SPENT` before its callback
and wipes the code, verifier, state, and challenge afterward.

The AT adapter itself performs none of those external actions and does not
wrap callback parsing. It only constructs the browser URI under the generic
one-shot transaction contract.

## Memory and cleanup

All fixed objects, the complete caller-declared destination span, and the
workspace must be pairwise disjoint; exact adjacency is allowed. Geometry,
alignment, phase, and initial shape failures occur before mutation and return
zero written bytes.

After geometry succeeds, the complete workspace is wiped on every normal or
caught path. A failure before the one-shot callback begins leaves the
destination unchanged and the transaction retryable in `PAR-READY`. Once the
callback begins, the complete destination capacity is cleared before
publication and cleared again on failure; the transaction remains
`AWAITING`. A caught internal throw also clears both destination and
workspace. Callers must consume destination bytes only when status is `OK`.

The configuration and profile are read-only. The transaction is the only
persistent object this adapter mutates, through the generic O2CODE owner.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| `AT-OAUTH-AUTHORIZATION-S-OK` | The exact URI was published and `written` is valid |
| `AT-OAUTH-AUTHORIZATION-S-INVALID` | An address, alignment, capacity, or time input is malformed |
| `AT-OAUTH-AUTHORIZATION-S-CAPACITY` | The destination is empty or cannot hold the exact encoded URI |
| `AT-OAUTH-AUTHORIZATION-S-ALIAS` | Caller-owned objects or the complete destination span overlap |
| `AT-OAUTH-AUTHORIZATION-S-CONFIG` | The immutable client configuration cannot be admitted |
| `AT-OAUTH-AUTHORIZATION-S-PROFILE` | The profile is invalid, not ready, or incompatible with the selected AT client |
| `AT-OAUTH-AUTHORIZATION-S-TRANSACTION` | The O2CODE object is invalid, busy, or not in `PAR-READY` |
| `AT-OAUTH-AUTHORIZATION-S-BINDING` | The retained transaction binding differs from the selected configuration |
| `AT-OAUTH-AUTHORIZATION-S-ISSUER` | Mandatory issuer policy or exact profile issuer provenance failed |
| `AT-OAUTH-AUTHORIZATION-S-EXPIRED` | The retained PAR request URI has reached its deadline |
| `AT-OAUTH-AUTHORIZATION-S-ENCODING` | Form encoding rejected a borrowed value |
| `AT-OAUTH-AUTHORIZATION-S-RANGE` | Caller storage lies outside the admitted memory range |
| `AT-OAUTH-AUTHORIZATION-S-PROTECTED` | Caller storage aliases protected platform memory |
| `AT-OAUTH-AUTHORIZATION-S-PLATFORM` | Caller-span platform qualification failed |
| `AT-OAUTH-AUTHORIZATION-S-INTERNAL` | An admitted invariant, subordinate result, or caught throw failed |
| `AT-OAUTH-AUTHORIZATION-S-CALLBACK` | The guarded internal launch callback violated its stack contract or threw |

All failures return `written = 0`. Callers must inspect the transaction phase
to distinguish a rejection before the one-shot loan from a terminal failure
after it began.

## Focused qualification and deferred matrices

The focused production-shaped gate continues the existing durable
proof-bearing public PAR success from `PAR-READY`. It covers one exact
authorization URI, transition to `AWAITING`, request-URI consumption,
workspace/output cleanup, one wrong-issuer callback that preserves the
genuine `AWAITING` attempt, one exact callback to `CODE-READY`, and one
`WITH-GRANT` loan exposing the exact durable binding, authorization code, and
valid verifier before `SPENT` and secret cleanup.

Both static gates passed. The generic authorization-code linked suite loaded
12 modules and passed in 191,292,455 guest steps and 104.79 seconds. The
combined durable public AT OAuth vertical passed 54 sequential phases: 34 raw
production-module loads, five composition loads, seven fixture loads, seven
focused runtime groups, and finish. It completed in 1,205,055,297 guest steps
and 677.68 summed stage seconds on one core with 128 MiB of external machine
memory. Its largest phase used 90,150,958 steps, below the unchanged
180,000,000-step ceiling.

The following are recorded non-gating follow-up work rather than implied
coverage: authorization endpoints with preexisting query variants; broad
percent-encoding and boundary-capacity matrices; cross-wired
configuration/profile/binding and expiry matrices; full alias, protected-span,
canary, subordinate-status, callback-denial, and malformed-query
cross-products; live browser and redirect-route integration; durable restart;
and token transport. The generic O2CODE suite retains its broader callback,
denial, parser, throw, and stack-containment coverage; this AT slice does not
duplicate those matrices.
