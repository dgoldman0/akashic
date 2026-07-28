# Durable OAuth 2 session ownership

`security/oauth2/session.f` is a generic, provider-neutral owner for one
post-grant OAuth 2 session. It binds an immutable caller-defined client/profile
identity and an exact issuer to one credential-vault RID, persists the complete
grant as a canonical sealed record, and provides generation-checked refresh
rotation that remains safe across process failure and reboot.

The module owns no authorization-server discovery, authorization-code flow,
browser, HTTP transport, token-response parsing, JWT or OIDC validation, DPoP
algorithm, DPoP key, server nonce, clock, provider policy, AT Protocol, Streams,
UI, or root key. Those concerns compose above or below this owner without
changing its durable state machine.

```forth
REQUIRE security/oauth2/session.f
```

## Ownership model

Allocate one stable `OAUTH2-SESSION-SIZE`-byte object per session. The object
is caller-owned and address-bound for its initialized lifetime; do not copy or
relocate it. It contains:

- immutable copies of the credential RID, opaque profile binding, and issuer;
- nonsecret published token type and optional scope;
- a volatile `oauth2/token-set.f` cache containing the access token and
  optional ID token;
- one transient full-record buffer used while operating on the credential
  vault; and
- a per-object guard and callback frame.

The refresh credential is deliberately not hydrated into the embedded token
cache. It exists in the sealed vault record and, during a vault operation, in
the guarded transient record buffer. That complete buffer is wiped when the
operation finishes. Access and ID tokens do remain in volatile session memory
until `O2SESSION-CLOSE` or `O2SESSION-FINI`, so callers must place session
objects in appropriately protected memory.

The configured credential vault remains owned by the caller and must stay
initialized at a stable address while the session object is live. The session
does not finalize the vault. The caller also owns durable retention of the
opaque RID: after reboot it reconstructs the vault and session configuration
with the same RID, binding, and issuer, calls `O2SESSION-INIT`, and then calls
`O2SESSION-OPEN`.

There is no mutable module-level session state. Operations on one session are
serialized by its guard, and reentrant operations on that object return
`O2SESSION-S-BUSY`. Sharing a credential vault may impose additional
serialization at the vault boundary.

## Public geometry

The fixed descriptor and field capacities are:

| Word | Size or capacity |
| --- | ---: |
| `O2SESSION-CONFIG-SIZE` | 48 bytes |
| `O2SESSION-GRANT-SIZE` | 96 bytes |
| `O2SESSION-BINDING-CAPACITY` | 256 bytes |
| `O2SESSION-ISSUER-CAPACITY` | 2048 bytes |
| `O2SESSION-TOKEN-TYPE-CAPACITY` | 4096 bytes |
| `O2SESSION-SCOPE-CAPACITY` | 4096 bytes |
| `O2SESSION-RECORD-HEADER-SIZE` | 128 bytes |
| `O2SESSION-RECORD-SIZE` | 31104 bytes |

Access, refresh, and ID token capacities are respectively
`O2TOK-ACCESS-CAPACITY`, `O2TOK-REFRESH-CAPACITY`, and
`O2TOK-ID-CAPACITY` from `oauth2/token-set.f`. The configured vault secret
capacity must be at least `O2SESSION-RECORD-SIZE`.

Use the published size words rather than embedding object sizes in callers.

## Configuration and initialization

Clear and populate one configuration descriptor:

```forth
O2SESSION-CONFIG-CLEAR  ( config -- status )

O2SESSION-C.VAULT      ( config -- field )
O2SESSION-C.RID        ( config -- field )
O2SESSION-C.BINDING-A  ( config -- field )
O2SESSION-C.BINDING-U  ( config -- field )
O2SESSION-C.ISSUER-A   ( config -- field )
O2SESSION-C.ISSUER-U   ( config -- field )

O2SESSION-INIT         ( config session -- status )
```

Store values into the returned field cells with `!`. `VAULT` identifies an
initialized credential vault, `RID` points to one present 32-byte RID, and the
binding and issuer are required nonempty byte strings within their published
capacities.

The binding is an opaque, application-defined identity for the durable OAuth
client/profile configuration. A production binding should identify everything
whose substitution would make the stored grant unsafe to reuse, such as the
registered client configuration and the durable key identity selected by a
DPoP profile. It is an identifier, not storage for a private key. The session
compares the binding and issuer byte-for-byte whenever it opens the record; it
does not normalize an issuer URI or interpret the binding.

`O2SESSION-INIT` validates the complete object and source spans, rejects
forbidden overlap, copies the RID, binding, and issuer, initializes the
embedded token owner, and leaves the session unopened. It does not read,
create, or replace a vault record. Once initialization succeeds, the caller
may clear or reuse the configuration descriptor and the source RID, binding,
and issuer buffers. The vault itself must remain live.

The configuration and grant clear words erase only their fixed descriptors.
They do not erase any external byte spans referenced by those descriptors.

## Grant descriptor

An install, reauthorization, or refresh commit receives a caller-owned grant
descriptor:

```forth
O2SESSION-GRANT-CLEAR  ( grant -- status )

O2SESSION-G.ACCESS-A          ( grant -- field )
O2SESSION-G.ACCESS-U          ( grant -- field )
O2SESSION-G.TOKEN-TYPE-A      ( grant -- field )
O2SESSION-G.TOKEN-TYPE-U      ( grant -- field )
O2SESSION-G.REFRESH-A         ( grant -- field )
O2SESSION-G.REFRESH-U         ( grant -- field )
O2SESSION-G.SCOPE-A           ( grant -- field )
O2SESSION-G.SCOPE-U           ( grant -- field )
O2SESSION-G.ID-A              ( grant -- field )
O2SESSION-G.ID-U              ( grant -- field )
O2SESSION-G.EXPIRES-AT-MS     ( grant -- field )
O2SESSION-G.FLAGS             ( grant -- field )
```

The access token and token type are always required and nonempty. Refresh,
scope, ID token, and absolute expiry are represented by these flags:

| Flag | Meaning |
| --- | --- |
| `O2SESSION-GRANT-F-REFRESH` | A nonempty refresh token span is present |
| `O2SESSION-GRANT-F-SCOPE` | A nonempty scope span is present |
| `O2SESSION-GRANT-F-ID` | A nonempty ID token span is present |
| `O2SESSION-GRANT-F-EXPIRY` | `EXPIRES-AT-MS` is known |

For each optional byte field, a set flag requires a nonempty admitted span. An
unset flag requires both its address and length cells to be zero. An unset
expiry flag requires the expiry cell to be zero. A set expiry flag accepts any
nonnegative cell, including zero, so “known to expire at the epoch” remains
distinct from “expiry unknown.” Unknown flag bits, negative lengths or expiry,
over-capacity fields, source/session aliasing, and malformed descriptor spans
are rejected before mutation.

For `O2SESSION-INSTALL` and `O2SESSION-REAUTHORIZE`, the descriptor defines the
complete new grant: absent optional fields are absent in the new record.

For `O2SESSION-REFRESH-COMMIT`, access token and token type are replaced.
A present refresh, scope, or ID token replaces its prior value; omission
retains the prior value. Omission of expiry is intentionally different: it
clears the prior known expiry. A provider profile must validate these semantics
before commit. In particular, a profile that requires refresh-token rotation
must require a new refresh token rather than allowing generic retain-on-omit
behavior.

Grant byte spans are synchronous read-only sources. The session copies them
but never clears them, so the parser or transport owner must wipe its own token
response buffers after a successful durable handoff.

## Canonical durable record

The session is stored as a credential-vault secret with kind
`O2SESSION-CREDENTIAL-KIND`, ASCII `O2SESS01`. The record is exactly
`O2SESSION-RECORD-SIZE` bytes and begins with this unsigned, big-endian
64-bit header:

| Offset | Field |
| ---: | --- |
| 0 | magic, ASCII `AKO2SES1` |
| 8 | version, exactly `1` |
| 16 | header size, exactly `128` |
| 24 | total size, exactly `31104` |
| 32 | durable phase |
| 40 | grant-presence flags |
| 48 | binding length |
| 56 | issuer length |
| 64 | token-type length |
| 72 | scope length |
| 80 | access-token length |
| 88 | refresh-token length |
| 96 | ID-token length |
| 104 | absolute expiry in milliseconds |
| 112 | reserved, exactly zero |
| 120 | reserved, exactly zero |

The fixed arenas following the header are:

| Offset | Capacity | Field |
| ---: | ---: | --- |
| 128 | 256 | opaque profile binding |
| 384 | 2048 | issuer |
| 2432 | 4096 | token type |
| 6528 | 4096 | optional scope |
| 10624 | 8192 | access token |
| 18816 | 4096 | optional refresh token |
| 22912 | 8192 | optional ID token |

Every numeric field must have its high bit clear. Binding, issuer, token type,
and access token are required and nonempty. Presence flags must exactly match
optional field lengths, and every unused arena byte must be zero. A
non-`ACTIVE` record must contain a refresh token. On load, the record's exact
binding and issuer must equal the immutable values copied during
`O2SESSION-INIT`.

Callers should treat this as a private canonical persistence format and use the
public operations rather than constructing records. The credential vault
authenticates the kind, RID, vault identity, generation, and complete record,
and encrypts it through the configured sealed-record key path. Session
confidentiality, anti-rollback strength, root-key availability, and crash
recovery therefore inherit the configured credential-vault policy.

## Install, open, and volatile lifecycle

```forth
O2SESSION-INSTALL
  ( grant session -- generation status )

O2SESSION-OPEN
  ( session -- generation phase status )

O2SESSION-CLOSE
  ( session -- status )

O2SESSION-FINI
  ( session -- status )
```

`O2SESSION-INSTALL` creates an `ACTIVE` record at an absent RID. It cannot
overwrite an existing credential. The vault's first successful generation is
returned, and the access and optional ID token are hydrated only after the
record is durable.

`O2SESSION-OPEN` discards any prior volatile publication, loads and
authenticates the RID, checks the credential kind and canonical session format,
verifies the exact binding and issuer, and then hydrates the access and
optional ID token. It returns the authoritative durable generation and phase.
It never silently changes `REFRESH-CLAIMED` or `REFRESH-EXPOSED`; reboot
recovery policy is made explicit to the caller.

`O2SESSION-CLOSE` wipes the volatile access/ID cache, published token type and
scope, and transient record buffer. It retains the configured RID, binding,
issuer, vault association, and durable credential, so a later
`O2SESSION-OPEN` can restore the session.

`O2SESSION-FINI` wipes and invalidates the entire session object. It does not
revoke or remove the durable credential, finalize the vault, clear a rollback
floor, or erase the caller's durable RID association. Use
`O2SESSION-LOGOUT` for durable local revocation before finalization when that
is the desired policy.

The returned status must be checked before treating other return cells as a
successful result. Every successful durable mutation returns its newly
committed generation.

## Durable refresh protocol

Refresh use is a four-step, compare-and-swap transaction:

```text
ACTIVE
  |
  | O2SESSION-REFRESH-CLAIM
  v
REFRESH-CLAIMED
  |                 |
  | ABORT           | O2SESSION-REFRESH-EXPOSE
  v                 v
ACTIVE         REFRESH-EXPOSED
                       |
                       | O2SESSION-REFRESH-COMMIT
                       v
                    ACTIVE
```

The public phase values are:

```forth
O2SESSION-PHASE-EMPTY
O2SESSION-PHASE-ACTIVE
O2SESSION-PHASE-REFRESH-CLAIMED
O2SESSION-PHASE-REFRESH-EXPOSED
```

`EMPTY` is local unopened state and is never a valid durable record phase.
Every transition below requires the exact current positive generation and
publishes a new generation. A stale generation is
`O2SESSION-S-CONFLICT`; a wrong phase is `O2SESSION-S-STATE`.

### Claim and safe abort

```forth
O2SESSION-REFRESH-CLAIM
  ( expected-generation session -- generation status )

O2SESSION-REFRESH-ABORT
  ( expected-generation session -- generation status )
```

`REFRESH-CLAIM` changes `ACTIVE` to `REFRESH-CLAIMED` durably before reporting
success. It reserves the refresh attempt without exposing the credential.
This phase gives the caller time to allocate request state and perform all
fallible preparation that does not require the refresh token.
An active session with no refresh credential returns
`O2SESSION-S-ABSENT` and remains unchanged.

`REFRESH-ABORT` is accepted only in `REFRESH-CLAIMED`. It durably returns the
record to `ACTIVE`, because no callback could yet have observed the refresh
credential. A rebooted session opened in `REFRESH-CLAIMED` may therefore be
aborted when the caller chooses to abandon the prepared attempt.

### Exposure and unknown send

```forth
O2SESSION-REFRESH-EXPOSE
  ( callback callback-context expected-generation session
    -- generation callback-result status )
```

Exposure first commits `REFRESH-EXPOSED` to the vault and advances generation.
Only after that durable commit does it invoke the callback:

```forth
( refresh-a refresh-u callback-context -- callback-result )
```

The callback is synchronous and the refresh address is valid only for that
invocation. It must treat the bytes as read-only and must not retain the
address. An HTTP owner that copies the credential into an outbound request
becomes responsible for protecting and scrubbing that copy.

On normal return, `callback-result` is application-defined and session status
is `O2SESSION-S-OK`. A callback throw or stack-contract violation returns a
zero callback result and `O2SESSION-S-CALLBACK`. In either case, the durable
phase remains `REFRESH-EXPOSED`: the callback may have launched a request
before reporting failure, and the old refresh credential must not be exposed
again. When `O2SESSION-S-CALLBACK` is returned, the generation identifies the
already committed exposed phase.

This is the unknown-send boundary. A crash after exposure, a transport timeout,
an ambiguous connection failure, a lost response, or a callback failure never
permits `REFRESH-ABORT`. The caller must resolve `REFRESH-EXPOSED` by committing
a validated response it still possesses, installing a genuinely new
authorization with `O2SESSION-REAUTHORIZE`, or revoking the local credential
with `O2SESSION-LOGOUT`.

### Commit

```forth
O2SESSION-REFRESH-COMMIT
  ( grant expected-generation session -- generation status )
```

Commit is accepted only in `REFRESH-EXPOSED`. It reloads the authoritative
record, verifies the exact exposed generation, applies the validated
replacement grant, changes the phase to `ACTIVE`, and replaces the vault
record. Only after that durable publication succeeds does it update the
volatile access/ID cache and published metadata.

The session owner deliberately does not decide whether a token response is
valid for a provider profile. The caller must first validate token type, scope,
required refresh rotation, issuer and identity consequences, and any DPoP
requirements, then populate the grant descriptor and commit.

## Reauthorization, logout, and vault recovery

```forth
O2SESSION-REAUTHORIZE
  ( grant expected-generation session -- generation status )

O2SESSION-LOGOUT
  ( expected-generation session -- generation status )

O2SESSION-RECOVER
  ( session -- generation phase status )
```

`O2SESSION-REAUTHORIZE` atomically replaces a present session record with a
complete new grant and returns it to `ACTIVE`. It may resolve an exposed
refresh attempt only when the grant came from a genuinely new authorization;
it is not permission to replay the old refresh credential. Reauthorization
first loads and authenticates the current credential kind, canonical record,
exact binding, issuer, and expected generation. It therefore cannot overwrite
a foreign or malformed credential merely because the caller knows its RID and
generation. Reauthorization uses the existing immutable RID, binding, and
issuer and cannot resurrect a tombstone.

`O2SESSION-LOGOUT` publishes an authenticated credential-vault tombstone at
the expected generation and wipes volatile publication. Before revocation it
performs the same authenticated kind, record, binding, issuer, and generation
check as reauthorization, so an initialized but unopened session cannot
blindly tombstone an unrelated vault credential. The RID is permanently
revoked and cannot be reused. A later authorization after logout needs a new
RID and explicit new application association. This operation is local durable
revocation; it does not contact an authorization-server revocation endpoint
or promise that already issued remote tokens have been invalidated.

An uncertain or blocking vault outcome is not absence and must not be retried
as a fresh install or blind replacement. `O2SESSION-RECOVER` delegates to the
credential vault's recovery while supplying the session's configured RID as
the atomic expected target, then reloads, validates, and hydrates the recovered
present session. If a different RID caused the shared vault to block, recovery
returns conflict without consuming that RID's recovery evidence or marking
this session revoked. It is only for a vault that is already blocked on that
operation; it is not a filesystem scan, RID discovery mechanism, root-key
recovery mechanism, or substitute for ordinary `O2SESSION-OPEN`.

If durable mutation succeeds but volatile cache hydration fails,
`O2SESSION-S-CACHE` reports that local publication is unusable. The vault
record remains authoritative. Close/open or reconstruct/open the session to
reload it; do not blindly repeat the mutation with an old expected generation.

## Token and metadata borrows

```forth
O2SESSION-WITH-ACCESS
  ( callback callback-context session -- callback-result status )

O2SESSION-WITH-ID
  ( callback callback-context session -- callback-result status )

O2SESSION-WITH-RID
O2SESSION-WITH-BINDING
O2SESSION-WITH-ISSUER
O2SESSION-WITH-TOKEN-TYPE
O2SESSION-WITH-SCOPE
  ( callback callback-context session -- callback-result status )
```

Every borrow callback uses the same ABI:

```forth
( address length callback-context -- callback-result )
```

The address is a synchronous, read-only borrow valid only until the callback
returns. The callback must consume exactly three cells and return exactly one.
The session guard remains held, so reentrant operations on the same object
return `O2SESSION-S-BUSY`. A throw or stack-contract violation returns zero
and `O2SESSION-S-CALLBACK`; a normal callback result is passed through
unchanged with `O2SESSION-S-OK`.

Access and ID borrows require an opened published session. An absent ID token
returns `O2SESSION-S-ABSENT` without invoking the callback. Token type likewise
requires published state, and optional absent scope returns `ABSENT`. RID,
binding, and issuer are immutable configuration metadata and can be borrowed
after initialization without opening a credential.

Callbacks are trusted in-process code. The module contains throws and exact
stack shape, but cannot make an arbitrary callback that writes through another
known address memory-safe. Callbacks must not mutate the session descriptor or
borrowed bytes, retain addresses, or publish secrets beyond the intended
consumer boundary.

## State and expiry inspection

```forth
O2SESSION-VALID?  ( session -- flag )

O2SESSION-STATE@
  ( session -- generation phase status )

O2SESSION-EXPIRY@
  ( session -- expires-at-ms known? status )

O2SESSION-EXPIRED?
  ( now-ms session -- expired? known? status )
```

`STATE@` reports volatile published state; after reboot or `CLOSE`, call
`OPEN` before relying on it. `EXPIRY@` distinguishes an unknown expiry from a
known value, including known zero. `EXPIRED?` requires a nonnegative caller
time and uses an unsigned `now-ms >= expires-at-ms` comparison when expiry is
known.

The module has no clock and does not calculate an absolute expiry from
`expires_in`, apply skew, reject an expired access borrow, schedule refresh, or
enforce proactive refresh policy. The token-response/profile owner must use a
trusted clock, check arithmetic overflow, calculate the absolute millisecond
deadline, and decide how early to refresh.

## DPoP and provider-profile boundary

The durable session is compatible with DPoP but does not implement it. The
caller must:

- validate authorization-server metadata and the provider's required token
  type and scope before install or commit;
- resolve the opaque binding to the same durable DPoP key and client profile
  after reboot;
- construct a fresh proof for each token and resource request;
- track server DPoP nonces at the appropriate server/session boundary; and
- refuse generic retain-on-omit refresh behavior when the provider requires a
  rotated refresh credential.

A token bound to a DPoP key is not usable merely because its vault record
survived reboot. The corresponding private key must remain recoverable under
the exact bound profile. If it is not recoverable, the safe resolution is a new
authorization, not weakening or silently changing the binding.

For an AT Protocol profile, the ATProto layer—not this generic library—must
enforce its DPoP token type, required `atproto` scope, refresh-rotation,
protected-resource, identity, and PDS rules.

## Reboot and failure rules

The durable record, not the volatile object, is authoritative:

- `ACTIVE` may continue after `OPEN`.
- `REFRESH-CLAIMED` proves no refresh callback ran and may be safely aborted.
- `REFRESH-EXPOSED` proves the credential crossed the one-shot exposure
  boundary and must never be exposed again.
- a tombstone is final for that RID.
- a blocked vault requires `O2SESSION-RECOVER`, not speculative retry.
- a cache failure requires reloading durable truth, not replaying a mutation.

These rules preserve safety when the process fails between any two durable or
in-memory steps. They do not persist an authorization-code transaction, an
outbound HTTP request, or a returned token response. If a caller needs to
survive a crash after receiving a refresh response but before session commit,
it must give that response its own protected durable owner or reauthorize.

## Status values

`O2SESSION-STATUS-VALID? ( status -- flag )` recognizes:

| Status | Meaning |
| --- | --- |
| `O2SESSION-S-OK` | The operation completed |
| `O2SESSION-S-INVALID` | Invalid object, descriptor, callback, scalar, state shape, or forbidden alias |
| `O2SESSION-S-CAPACITY` | A field exceeds its capacity or the vault cannot contain the canonical record |
| `O2SESSION-S-ABSENT` | The credential or requested optional/published value is absent |
| `O2SESSION-S-REVOKED` | The RID contains an authenticated tombstone |
| `O2SESSION-S-CONFLICT` | The expected generation is stale or an install target already exists |
| `O2SESSION-S-STATE` | The requested transition is not valid from the current durable phase |
| `O2SESSION-S-BUSY` | The session guard, callback borrow, or underlying vault is busy |
| `O2SESSION-S-CALLBACK` | A callback threw or violated its stack contract |
| `O2SESSION-S-LOCKED` | The credential-vault root key is unavailable |
| `O2SESSION-S-ENTROPY` | The vault could not obtain required architectural entropy |
| `O2SESSION-S-CRYPTO` | A cryptographic dependency failed |
| `O2SESSION-S-AUTH` | Sealed-record authentication failed |
| `O2SESSION-S-CORRUPT` | Durable storage is structurally damaged |
| `O2SESSION-S-UNSUPPORTED` | A durable dependency format or feature is unsupported |
| `O2SESSION-S-IO` | Durable storage I/O failed |
| `O2SESSION-S-RECOVERY` | Storage publication/finalization is uncertain or the vault is blocked |
| `O2SESSION-S-ROLLBACK` | The credential is older than the configured rollback floor |
| `O2SESSION-S-RANGE` | A public span has invalid or unmapped caller geometry |
| `O2SESSION-S-PROTECTED` | A public span intersects protected platform storage |
| `O2SESSION-S-PLATFORM` | Caller-span or dependency status violated its platform contract |
| `O2SESSION-S-INTERNAL` | An admitted internal invariant failed |
| `O2SESSION-S-FORMAT` | The loaded kind, size, binding, issuer, or canonical session record is invalid |
| `O2SESSION-S-CACHE` | Durable truth exists, but the volatile token cache could not be published |

Application callback results do not belong to this status vocabulary. Always
check the final session status before interpreting an accompanying callback
result, phase, expiry, or generation, except for the specifically documented
already-durable generation returned by a refresh-exposure callback failure.
