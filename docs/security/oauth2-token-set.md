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
reset operation.

`O2TOK-CLEAR? ( tokens -- status )` acquires the object guard, zeroizes all
live and staged token capacity, clears any refresh lease, and advances the
generation. `O2TOK-CLEAR ( tokens -- )` is the established no-result
convenience surface. Clear returns `BUSY` through `O2TOK-CLEAR?` while a
callback is borrowing bytes. An active refresh lease does not prevent an
explicit clear, so logout can invalidate an in-flight result.

`O2TOK-PRESENT? ( tokens -- flag )` is true when a usable access token is
present. Refresh and identity tokens are independently optional.

## Set and update

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

O2TOK-UPDATE
  ( id-a id-u access-a access-u refresh-a refresh-u
    expires-ms tokens -- status )
```

`SET` requires a nonempty access token. Refresh and identity tokens are
optional. `UPDATE` requires an existing usable access token; a zero length
retains the corresponding token, and an expiration of zero retains the
current expiration. Expiration values are nonnegative; a negative value is
rejected before the object is locked.

Every complete source span and the complete token object are qualified before
the guard is acquired. Any nonempty source overlapping any part of the token
object is rejected. Source/source overlap is harmless and accepted because
sources are read-only.

Replacement bytes are copied into the object's guarded staging area before
any current token is wiped. Publication then zeroizes every live capacity,
copies the staged values, updates metadata and generation, and zeroizes the
entire staging area. Failed geometry and lease checks do not alter tokens.
Unexpected admitted-memory faults propagate after guard release and staging
cleanup.

While a refresh lease is active, ordinary `SET` and `UPDATE` return `BUSY`;
rotation must use `O2TOK-REFRESH-COMMIT`.

## Callback borrows

```forth
O2TOK-WITH-ACCESS   ( callback context tokens -- callback-status )
O2TOK-WITH-REFRESH  ( callback context tokens -- callback-status )
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

`O2TOK-WITH-REFRESH` is an ordinary opaque borrow. A caller preparing a
refresh-token grant must use the lease path below, which prevents a generally
single-use refresh token from being launched twice.

## Refresh lease transaction

```forth
O2TOK-REFRESH-BEGIN
  ( tokens -- lease status )

O2TOK-WITH-REFRESH-LEASE
  ( callback context lease tokens -- callback-status )

O2TOK-REFRESH-COMMIT
  ( id-a id-u access-a access-u refresh-a refresh-u
    expires-ms lease tokens -- status )

O2TOK-REFRESH-ABORT
  ( lease tokens -- status )
```

`BEGIN` atomically creates one opaque, nonzero lease bound to the current
token generation. A second begin returns `BUSY`; a set without a refresh
token returns `ABSENT`.

`WITH-REFRESH-LEASE` validates that exact lease and permits exactly one
callback invocation. It marks the lease consumed before invoking the
callback. This is deliberate: a callback may have launched a request before
returning an error or throwing. Either outcome releases the object guard but
leaves the lease active and consumed, preventing an accidental second launch.
The caller must later commit the response or explicitly abort when it knows
the refresh token was not spent.

`COMMIT` requires the active lease, its original generation, the completed
one-shot borrow, and a nonempty replacement access token. Zero-length identity
and refresh fields retain their current values, as does an expiration of zero.
The operation stages the complete replacement, zeroizes retired secrets,
advances generation, and clears the lease atomically.

`ABORT` clears only the matching lease and does not change token bytes or
generation. A mismatched lease or a result invalidated by clear returns
`STALE`. Lease values are opaque and must not be derived from generation
numbers.

## Status values

| Status | Meaning |
|---|---|
| `O2TOK-S-OK` | Operation completed. |
| `O2TOK-S-INVALID` | Invalid object, callback, lease value, or object state. |
| `O2TOK-S-CAPACITY` | A source length exceeds its public token capacity. |
| `O2TOK-S-ABSENT` | A required token or token set is absent. |
| `O2TOK-S-BUSY` | The guard, borrow state, active lease, or one-shot use prevents the operation. |
| `O2TOK-S-CALLBACK` | A token callback threw. |
| `O2TOK-S-ALIAS` | A source overlaps the mutable token object. |
| `O2TOK-S-STALE` | The supplied refresh lease is not the active generation-bound lease. |
| `O2TOK-S-RANGE` | A complete caller span has invalid or unmapped geometry. |
| `O2TOK-S-PROTECTED` | A caller span intersects protected platform storage. |
| `O2TOK-S-PLATFORM` | Caller-span qualification returned an unexpected platform result. |

`O2TOK-STATUS-VALID? ( status -- flag )` validates this vocabulary. Borrow
callbacks may return application-specific nonzero statuses on normal return;
only module-produced statuses are guaranteed to satisfy the predicate.
