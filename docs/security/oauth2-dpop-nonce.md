# OAuth DPoP authorization-server nonce ownership

`security/oauth2/dpop-nonce.f` is the provider-neutral owner for the latest
nonempty DPoP nonce associated with one authorization server. It copies an
exact opaque server key and nonce into one caller-owned, address-free record,
then advances a monotonic generation whenever that nonce is replaced.

The module does not perform HTTP, recognize a nonce challenge, authorize a
retry, construct a DPoP proof, own a key or token, read a clock, install an
OAuth session, or apply provider policy. A higher exchange owner composes
those responsibilities and serializes access to this record.

```forth
REQUIRE security/oauth2/dpop-nonce.f
```

## Public geometry

```forth
OAUTH2-DPOP-NONCE-SERVER-CAPACITY  ( -- bytes )
OAUTH2-DPOP-NONCE-CAPACITY         ( -- bytes )
OAUTH2-DPOP-NONCE-SIZE             ( -- bytes )
OAUTH2-DPOP-NONCE-STATUS-VALID?    ( status -- flag )
```

The server capacity is derived from `O2CODE-ISSUER-CAPACITY`, and the nonce
capacity is derived from `OAUTH2-HTTP-POST-NONCE-CAPACITY`. Callers must use
the published symbolic words rather than embedding either limit or the
record size.

The server key is opaque to this module and is compared byte-for-byte. A
profile should consistently supply its already admitted canonical
authorization-server identity. The module does not parse, normalize, or
infer that identity from a token endpoint.

## Initialization and replacement

```forth
OAUTH2-DPOP-NONCE-INIT
  ( server-a server-u nonce-a nonce-u owner -- status )

OAUTH2-DPOP-NONCE-REPLACE
  ( server-a server-u nonce-a nonce-u owner -- status )

OAUTH2-DPOP-NONCE-GENERATION@
  ( owner -- generation status )
```

`INIT` requires nonempty admitted server and nonce spans, copies both values,
and publishes generation `1`. It rejects an already initialized record.

`REPLACE` accepts only the exact server key retained by `INIT`. It completely
admits the new nonce before changing the record, wipes the complete old nonce
arena, copies the replacement, and advances the generation by one. A server
mismatch, malformed nonce, capacity failure, alias, or other preflight
failure leaves the complete prior record unchanged.

A nonce must satisfy RFC 9449 `1*NQCHAR`: `!`, bytes `#` through `[`, or bytes
`]` through `~`. It is otherwise opaque. Empty values, spaces, quotes,
backslashes, controls, and non-ASCII bytes are rejected.

## Guarded borrow

```forth
OAUTH2-DPOP-NONCE-WITH
  ( callback context server-a server-u owner
    -- callback-result status )
```

The requested server must exactly match the retained key. On success, the
callback receives:

```forth
( nonce-a nonce-u generation context -- callback-result )
```

The nonce address is a synchronous read-only loan into the owner and is valid
only until the callback returns. The callback must consume exactly those four
arguments and return one cell. A throw or stack-contract violation returns
zero with `OAUTH2-DPOP-NONCE-S-CALLBACK`.

The owner is marked borrowed around the callback. An otherwise valid
replacement, reinitialization, destruction, or nested borrow of that same
record returns `OAUTH2-DPOP-NONCE-S-BUSY`; malformed inputs can fail their
earlier preflight instead. Generation remains observable. The module contains
no mutable module-level state, so independent caller-owned records remain
independent.

## Destruction and durable composition

```forth
OAUTH2-DPOP-NONCE-VALID?  ( owner -- flag )
OAUTH2-DPOP-NONCE-WIPE    ( owner -- status )
```

`WIPE` clears the complete record unless a callback currently borrows it.
Afterward the record is invalid and contains no retained server or nonce
bytes.

The record is address-free, but this module does not persist or authenticate
it. If restart continuity is required, a higher owner must protect and
serialize the complete `OAUTH2-DPOP-NONCE-SIZE` record and reject rollback
according to its durable policy.

For a DPoP token exchange, the higher owner normally:

1. validates the HTTP result and its singleton `DPoP-Nonce` header;
2. initializes or replaces the nonce under the exact authorization-server
   key;
3. borrows that nonce while constructing a fresh proof; and
4. independently decides whether a `use_dpop_nonce` result authorizes its
   single retry.

Nonce capture does not itself authorize transmission or retry.

## Statuses

| Status | Meaning |
|---|---|
| `OAUTH2-DPOP-NONCE-S-OK` | Operation completed |
| `OAUTH2-DPOP-NONCE-S-INVALID` | Invalid object, pointer, length, alignment, callback, or nonce syntax |
| `OAUTH2-DPOP-NONCE-S-CAPACITY` | Server or nonce exceeds its symbolic capacity |
| `OAUTH2-DPOP-NONCE-S-ALIAS` | A source or server-check span overlaps the owner |
| `OAUTH2-DPOP-NONCE-S-STATE` | Initialization was requested for an initialized owner |
| `OAUTH2-DPOP-NONCE-S-BINDING` | The supplied server does not exactly match the retained key |
| `OAUTH2-DPOP-NONCE-S-BUSY` | The record is currently borrowed |
| `OAUTH2-DPOP-NONCE-S-CALLBACK` | A callback threw or violated its stack contract |
| `OAUTH2-DPOP-NONCE-S-GENERATION` | The monotonic generation cannot advance |
| `OAUTH2-DPOP-NONCE-S-RANGE` | Caller memory has invalid physical geometry |
| `OAUTH2-DPOP-NONCE-S-PROTECTED` | Caller memory intersects protected platform storage |
| `OAUTH2-DPOP-NONCE-S-PLATFORM` | Caller-memory qualification failed unexpectedly |
| `OAUTH2-DPOP-NONCE-S-INTERNAL` | An internal invariant failed |
