# akashic-oauth2-token-set — Opaque OAuth token ownership

`security/oauth2/token-set.f` owns bounded OAuth access, refresh, and optional
identity-token bytes in caller-supplied storage. Tokens remain opaque byte
strings: the module performs no JWT parsing, claim inspection, provider
policy, transport, persistence, or AT Protocol work.

```forth
REQUIRE security/oauth2/token-set.f
```

The module requires `utils/memory-span.f`, `utils/caller-span.f`, and
`concurrency/guard.f`. It defines no mutable module state.

## Object lifecycle

Allocate `OAUTH2-TOKEN-SET-SIZE` bytes and initialize them before publishing
the object to another execution context:

```forth
buffer O2TOK-INIT
\ or, when admission status is needed:
buffer O2TOK-INIT?  ( -- status )
```

Initialization validates the complete object span, wipes it, initializes its
embedded spin guard, and starts a nonzero generation. Reinitialization is
only valid while the caller has exclusive ownership; it is not a concurrent
reset operation. An active refresh lease makes reinitialization `BUSY`; clear
the token object first so its descriptor is invalidated.

`O2TOK-CLEAR? ( tokens -- status )` acquires the object guard, zeroizes all
live and staged token capacity, clears any refresh lease, and advances the
generation. `O2TOK-CLEAR ( tokens -- )` is the established no-result
convenience surface. Clear returns `BUSY` through `O2TOK-CLEAR?` while a
callback is borrowing bytes. An active refresh lease does not prevent an
explicit clear, so logout can invalidate an in-flight result.

`O2TOK-PRESENCE ( tokens -- present? status )` reports whether a nonempty access
token is stored. `O2TOK-S-OK` makes the flag authoritative; guard contention
and admission/object failures return an explicit status instead of being
collapsed into false. Presence does not inspect the expiration cell or assert
that a token is currently usable. Refresh and identity tokens are
independently optional.

## Initial publication

The public capacities remain:

| Token | Capacity |
|---|---:|
| `O2TOK-ACCESS-CAPACITY` | 8192 bytes |
| `O2TOK-REFRESH-CAPACITY` | 4096 bytes |
| `O2TOK-ID-CAPACITY` | 8192 bytes |

```forth
O2TOK-SET
  ( id-a id-u access-a access-u refresh-a refresh-u
    expires-ms tokens -- status )

```

`SET` publishes the result of an initial authorization grant into an empty
object and requires a nonempty access token. Refresh and identity tokens are
optional. A populated object returns `BUSY`; callers must explicitly clear it
before starting or restoring a different authorization. Expiration values are
nonnegative; a negative value is rejected before the object is locked.

There is deliberately no general update word. Once a refresh credential has
been stored, replacement access, refresh, and identity tokens can be published
only by the lease-mediated refresh transaction below. This prevents an
unleased refresh launch followed by an ordinary update from bypassing
single-use rotation.

Every complete source span and the complete token object are qualified before
the guard is acquired. Any nonempty source overlapping any part of the token
object is rejected. Source/source overlap is harmless and accepted because
sources are read-only. The caller must keep every admitted source byte stable,
readable, and immutable until the operation returns; the object guard cannot
synchronize memory owned by another component. The module never owns or wipes
source storage, so callers should erase superseded source copies—especially
the initial refresh credential—after successful publication.

Replacement bytes are copied into the object's guarded staging area before
any current token is wiped. Publication then zeroizes every live capacity,
copies the staged values, updates metadata and generation, and zeroizes the
entire staging area. Failed geometry and lease checks do not alter tokens.
Unexpected admitted-memory faults propagate after guard release and staging
cleanup.

While a refresh lease is active, `SET` returns `BUSY`; rotation must use
`O2TOK-REFRESH-COMMIT`.

## Callback borrows

```forth
O2TOK-WITH-ACCESS   ( callback context tokens -- callback-status )
O2TOK-WITH-ID       ( callback context tokens -- callback-status )
```

Callbacks have this shape:

```forth
( token-a token-u context -- callback-status )
```

The per-object guard remains held while the callback runs, and a guarded
borrow flag rejects recursive mutation by the same execution owner.
Independent token objects remain concurrent. A callback `THROW` is caught and
reported as `O2TOK-S-CALLBACK`; the borrow flag and guard are released before
return. On ordinary return, the callback's single status cell is passed
through unchanged, so application callback statuses need not belong to the
`O2TOK` status vocabulary.

There is no unleased refresh-token borrow. Refresh bytes are exposed only by
the one-shot lease callback below.

## Refresh lease transaction

```forth
OAUTH2-REFRESH-LEASE-SIZE

lease O2TOK-REFRESH-LEASE-INIT
\ or:
lease O2TOK-REFRESH-LEASE-INIT?  ( -- status )

O2TOK-REFRESH-BEGIN
  ( lease tokens -- status )

O2TOK-WITH-REFRESH-LEASE
  ( callback context lease tokens -- callback-status )

O2TOK-REFRESH-COMMIT
  ( id-a id-u access-a access-u refresh-a refresh-u
    expires-ms lease tokens -- status )

O2TOK-REFRESH-ABORT
  ( lease tokens -- status )
```

Each asynchronous refresh context owns an
`OAUTH2-REFRESH-LEASE-SIZE`-byte descriptor. Initialize it under exclusive
ownership before first use and keep the descriptor admitted, disjoint from
the token object, and stable until a terminal commit, abort, or token clear.
A descriptor must not be shared by concurrent refresh operations.

`BEGIN` atomically binds a free descriptor to the exact token-object address,
current generation, and a nonzero per-object nonce. A descriptor active for
another transaction and a second begin both return `BUSY`; a set without a
refresh token returns `ABSENT`. Descriptor/object overlap returns `ALIAS`.

`WITH-REFRESH-LEASE` validates that exact lease and permits exactly one
callback invocation. It marks the lease consumed before invoking the
callback. This is deliberate: a callback may have launched a request before
returning an error or throwing. Either outcome releases the object guard but
leaves the lease active and consumed, preventing an accidental second launch.
The caller must later commit the response or explicitly abort when it knows
the refresh token was not spent.

`COMMIT` requires a descriptor bound to that exact token object, its original
generation and nonce, the completed one-shot borrow, and a nonempty replacement
access token. A descriptor from another object is `STALE`, even when both
objects happen to have equal generations and nonce values. Descriptor/source
overlap is rejected. Zero-length identity and refresh fields retain their
current values, as does an expiration of zero. The operation stages the
complete replacement, zeroizes retired secrets, advances generation, and
invalidates the descriptor atomically.

`ABORT` invalidates only the matching descriptor and does not change token
bytes or generation. A mismatched descriptor or a result invalidated by clear
returns `STALE`. `O2TOK-CLEAR?` also invalidates the active descriptor.
Descriptor fields are private transaction metadata and must not be inspected
or modified by callers.

## Status values

| Status | Meaning |
|---|---|
| `O2TOK-S-OK` | Operation completed. |
| `O2TOK-S-INVALID` | Invalid object, callback, lease descriptor, or object state. |
| `O2TOK-S-CAPACITY` | A source length exceeds its public token capacity. |
| `O2TOK-S-ABSENT` | A required token or token set is absent. |
| `O2TOK-S-BUSY` | The guard, borrow state, active lease, or one-shot use prevents the operation. |
| `O2TOK-S-CALLBACK` | A token callback threw. |
| `O2TOK-S-ALIAS` | A source, lease descriptor, or token object has a forbidden overlap. |
| `O2TOK-S-STALE` | The supplied refresh lease is not the active generation-bound lease. |
| `O2TOK-S-RANGE` | A complete caller span has invalid or unmapped geometry. |
| `O2TOK-S-PROTECTED` | A caller span intersects protected platform storage. |
| `O2TOK-S-PLATFORM` | Caller-span qualification returned an unexpected platform result. |

`O2TOK-STATUS-VALID? ( status -- flag )` validates this vocabulary. Borrow
callbacks may return application-specific nonzero statuses on normal return;
only module-produced statuses are guaranteed to satisfy the predicate.
