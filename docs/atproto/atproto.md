# akashic-atproto — AT Protocol Primitives for KDOS / Megapad-64

AT Protocol identity, record-addressing, authenticated XRPC request
construction, exact Bluesky text-record encoding, and bounded feed decoding.
Foundation layer for Bluesky and other AT Protocol applications.

The bounded, credential-free public author-feed exchange has a separate
[lifecycle contract](public-author-feed.md). It uses the XIO/HBUF provider
contract and the shared KDOS adapter's asynchronous NIO open, close, and cancel
callbacks. The authenticated path instead composes explicit OAuth profile,
durable session, DPoP key, target, request, and transport owners.

```forth
REQUIRE aturi.f    \ restricted normalized AT URI views + builder
REQUIRE did.f      \ strict generic DID identifier syntax
REQUIRE handle.f   \ AT Protocol handle syntax + lowercase normalization
REQUIRE did-document.f \ strict caller-owned AT Protocol identity profile
REQUIRE identity.f \ caller-owned handle/DID/PDS discovery coordinator
REQUIRE identity-hres.f \ identity over generic HTTPS resources
REQUIRE oauth-profile.f \ exact PDS-to-OAuth issuer trust-chain profile
REQUIRE oauth-profile-hres.f \ OAuth discovery over HTTPS resources
REQUIRE oauth-client.f \ AT policy over generic OAuth client configuration
REQUIRE oauth-deployment.f \ local Client ID Metadata deployment binding
REQUIRE oauth-grant.f \ AT token policy over generic OAuth grants
REQUIRE tid.f      \ caller-owned TID clocks, validation, comparison
REQUIRE bluesky-text-record.f \ exact caller-owned app.bsky.feed.post record
REQUIRE xrpc.f     \ caller-owned authenticated XRPC request construction
REQUIRE create-record.f \ exact authenticated createRecord operation
REQUIRE feed-model.f \ owned app.bsky timeline response model
REQUIRE public-author-feed.f \ bounded cooperative public-feed provider
```

`PROVIDED akashic-atproto-aturi` / `akashic-did` /
`akashic-atproto-handle` / `akashic-tid` /
`akashic-atproto-diddoc` / `akashic-atproto-identity` /
`akashic-atid-hres` / `akashic-at-oauth-prof` /
`akashic-at-oauth-hres` / `akashic-at-oauth-client` /
`akashic-at-oauth-deployment` /
`akashic-at-oauth-grant` /
`akashic-bsky-text-rec` / `akashic-xrpc` / `akashic-at-crec-codec` /
`akashic-at-create-rec` /
`akashic-atproto-feed-model` /
`akashic-atp-pubfeed` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [AT URI — aturi.f](#at-uri--aturif)
- [DID — did.f](#did--didf)
- [Handle — handle.f](#handle--handlef)
- [DID document — did-document.f](#did-document--did-documentf)
- [Identity discovery — identity.f](#identity-discovery--identityf)
- [Identity HTTP composition — identity-hres.f](#identity-http-composition--identity-hresf)
- [OAuth discovery profile — oauth-profile.f](#oauth-discovery-profile--oauth-profilef)
- [OAuth HTTP composition — oauth-profile-hres.f](#oauth-http-composition--oauth-profile-hresf)
- [OAuth client policy — oauth-client.f](#oauth-client-policy--oauth-clientf)
- [OAuth deployment binding — oauth-deployment.f](#oauth-deployment-binding--oauth-deploymentf)
- [OAuth token-grant admission — oauth-grant.f](#oauth-token-grant-admission--oauth-grantf)
- [TID — tid.f](#tid--tidf)
- [Bluesky text record](bluesky-text-record.md)
- [Authenticated XRPC — xrpc.f](#authenticated-xrpc--xrpcf)
- [Exact createRecord operation](create-record.md)
- [Feed Model — feed-model.f](#feed-model--feed-modelf)
- [Session and repository ownership](#session-and-repository-ownership)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Independent files** | Each file is independently `REQUIRE`-able with its own `PROVIDED` guard. |
| **Explicit ownership** | Identity syntax and XRPC composition are state-free; durable secrets remain in their general security owners. |
| **AT Protocol spec** | Follows the AT Protocol specification for URI syntax, DID validation, TID encoding, OAuth-bound XRPC, and service proxying. |
| **Statusful syntax** | DID and handle admission preserve capacity and platform failures rather than collapsing them into syntax errors. |
| **ASCII codes for JSON** | Manual JSON building uses numeric char codes (34 for `"`, 123 for `{`, etc.) since KDOS has no `S\"` word. |

---

## AT URI — aturi.f

This state-free boundary accepts only the normalized Lexicon shape
`at://AUTHORITY[/COLLECTION[/RKEY]]`. The authority is a normalized DID or
lowercase handle, the optional collection is a normalized NSID, and the
optional record key uses the exact general record-key grammar. Query,
fragment, trailing-slash, userinfo, port, relative, and generic URI forms are
rejected. The protocol-wide source bound is exported as
`ATURI-LENGTH-MAX` (8,192 bytes).

`ATURI-VALIDATE` returns a precise `ATURI-S-*` status. `ATURI-SPLIT` returns
synchronous borrowed views into the admitted source; absent optional
components are published as `0 0`. The module owns no component buffers or
mutable parsing state.

```forth
ATURI-VALIDATE  ( source source-u -- status )
ATURI-VALID?    ( source source-u -- flag )
ATURI-SPLIT     ( source source-u -- authority-a authority-u
                                      collection-a collection-u
                                      rkey-a rkey-u status )
```

### ATURI-BUILD

```forth
ATURI-BUILD  ( authority-a authority-u collection-a collection-u
               rkey-a rkey-u destination capacity writer
               -- written status )
```

Construction accepts caller-provided destination storage and a caller-owned
`CBW-SIZE` workspace. It validates and measures all components before
initializing the writer or changing the destination, rejects every source or
workspace overlap with the exact output span, and never truncates. Pass `0 0`
for both collection and record key to build an authority-only URI; a record
key cannot be present without a collection.

---

## DID — did.f

The [generic DID syntax component](did.md) validates any method-independent
AT Protocol DID identifier up to 2048 bytes. Unsupported methods remain
syntactically valid so that the identity layer can distinguish them from
malformed identifiers and resolution failures.

```forth
DID-VALIDATE       ( did-a did-u -- status )
DID-VALID?         ( did-a did-u -- flag )
DID-METHOD@        ( did-a did-u -- method-a method-u status )
DID-SPECIFIC-ID@   ( did-a did-u -- id-a id-u status )
```

Borrowed method and identifier views point into the caller's source. DIDs are
case-sensitive and are not normalized.

## Handle — handle.f

The [handle syntax component](handle.md) validates the complete AT Protocol
ASCII hostname profile and publishes lowercase canonical bytes into
caller-owned storage.

```forth
AT-HANDLE-VALIDATE       ( source source-u -- status )
AT-HANDLE-VALID?         ( source source-u -- flag )
AT-HANDLE-NORMALIZED?    ( source source-u -- normalized? status )
AT-HANDLE-NORMALIZE
  ( source source-u destination capacity -- written status )
```

It owns no DNS, HTTPS, IDNA, reserved-TLD, or bidirectional identity policy.

## DID document — did-document.f

The [DID document profile](did-document.md) strictly validates one
caller-supplied JSON DID document and publishes a self-contained exact-ID
result. Its first valid `at://` handle, modern `#atproto` Multikey, and
HTTPS-origin `#atproto_pds` service are retained as independent optional
evidence.

```forth
AT-DIDDOC-PARSE
  ( source source-u expected-did expected-did-u
    document workspace -- status )
```

It owns no resolution or transport state. Missing optional evidence does not
erase a valid identity. `AT-DIDDOC-PARTICIPATION-STATUS` separately requires
both a usable Multikey and PDS endpoint before participation.

## Identity discovery — identity.f

The [identity and PDS discovery coordinator](identity.md) drives production
handle and DID resolution without owning DNS or HTTP transport state. It
publishes exact document identity independently from optional handle, key, and
PDS participation evidence.

```forth
ATID-BEGIN-HANDLE  ( handle-a handle-u result resolver -- status )
ATID-BEGIN-DID     ( did-a did-u result resolver -- status )
ATID-ACTION@       ( resolver -- action status )
```

DNS TXT, bounded CNAME progression, HTTPS well-known fallback, DID-document
fetch, and reverse handle confirmation are explicit caller-driven actions.

## Identity HTTP composition — identity-hres.f

The [state-free HTTP-resource adapter](identity-http-resource.md) applies the
AT identity HTTP profile to a generic caller-owned HTTPS resource and submits
only an admitted result bound to the resolver's exact current action target.
It admits final 2xx responses without treating `Content-Type` as identity
evidence, bounds redirects to three, and permits cross-authority redirects
only between default-port HTTPS targets. DNS, public-address admission, TLS
hostname authentication, port leases, and retry exhaustion remain platform
composition responsibilities.

## OAuth discovery profile — oauth-profile.f

The [caller-owned OAuth discovery profile](oauth-profile.md) binds a resolved
DID and PDS to the PDS-selected authorization server using exact RFC 9728 and
RFC 8414 identifiers. It enforces the AT OAuth capabilities and exposes
authorization, token, and PAR targets only after the complete trust chain is
ready.

The profile owns no transport, browser, token, DPoP, session, XRPC, or Streams
state. A separate HTTP-resource adapter supplies metadata responses under the
required exact-200, JSON, and no-redirect policy.

## OAuth HTTP composition — oauth-profile-hres.f

The
[state-free HTTP-resource adapter](oauth-profile-http-resource.md)
connects admitted generic `HRES` results to the OAuth discovery profile. It
uses one caller-owned transient workspace for the generic protected-resource
and authorization-server metadata parsers, independently rechecks the exact
requested and effective targets, status 200, zero redirects, and
`application/json`, and submits only successful parses to the trust-chain
state machine.

HTTP-envelope and parse failures leave the pending discovery phase retryable.
Successfully parsed resource, issuer, capability, or endpoint violations are
terminal profile failures. DNS, public-address admission, authenticated TLS,
and port-lease ownership remain responsibilities of the caller's `HRES` bind
provider.

## OAuth client policy — oauth-client.f

The [AT OAuth client-selection adapter](oauth-client.md) qualifies an immutable
generic OAuth client configuration against the AT client profile and a ready
OAuth discovery profile. It enforces production client-ID, redirect, scope,
client-authentication, and DPoP declarations without owning metadata transport,
keys, browser state, tokens, sessions, XRPC, or Streams state.

The adapter uses one 432-byte caller-owned transient workspace and wipes it
after every geometrically admitted result.

## OAuth deployment binding — oauth-deployment.f

The [AT OAuth client deployment binder](oauth-deployment.md) composes one
validated generic client configuration, one ready AT OAuth profile, and one
structurally decoded Client ID Metadata Document. It enforces exact deployment
identity, application, grant, response, redirect, scope, authentication, DPoP,
and key-source declarations, then lends both callback-scoped views to one
synchronous caller callback.

The state-free adapter uses one 53,760-byte caller-owned workspace and wipes it
after every admitted outcome. HTTP provenance, checked JWK Set qualification,
`jwks_uri` acquisition, private-key ownership, browser authorization, and
session installation remain explicit later boundaries.

## OAuth confidential inline deployment — oauth-deployment-inline.f

The
[confidential inline deployment composition](oauth-deployment-inline.md)
extends the deployment binder with checked P-256 JWK Set selection and durable
local client-authentication and DPoP key ownership. It accepts only inline
`jwks`, requires an exact two-role key binding, compares both the selected
public key and thumbprint with the authenticated local client identity, and
resolves the distinct DPoP identity without nesting vault borrows.

The state-free composition uses one 111,928-byte caller-owned workspace and
wipes it after every admitted outcome. Client-metadata acquisition,
`jwks_uri`, assertion and DPoP-proof construction, browser authorization, token
exchange, and durable session installation remain separate boundaries.

## OAuth token-grant admission — oauth-grant.f

The
[state-free AT grant adapter](oauth-grant.md)
applies the token-response requirements to the generic ephemeral OAuth decoder
and a ready discovery profile. It requires `DPoP`, exact `atproto` scope-token
membership, a valid `sub` DID exactly matching the identity-started profile,
checked expiry conversion, and a refresh-token member for refresh rotation.

Only after those checks does it lend a populated generic `O2SESSION` grant to
one synchronous callback. HTTP, DPoP proof and nonce ownership, durable session
mutation, credential-RID association, and Streams remain outside the adapter.

---

## TID — tid.f

Timestamp Identifiers (TIDs) are 13-character, base32-sort-encoded
64-bit values used as record keys in the AT Protocol.

### Bit Layout

```
Bit 63:     0 (reserved, must be zero)
Bits 62–10: Microsecond timestamp (53 bits)
Bits 9–0:   Clock ID (10 bits, 0–1023)
```

### Base32-Sort Alphabet

```
234567abcdefghijklmnopqrstuvwxyz
```

Index 0 = `2`, index 31 = `z`.  Characters sort lexicographically
in timestamp order.

### Caller-owned clocks

A clock is a caller-owned, eight-byte-aligned 24-byte object containing a
fixed ID in `0..1023` and the last committed logical microsecond. The module
does not read `EPOCH@` or own a process-wide counter.

```forth
TID-CLOCK-INIT     ( clock-id clock -- status )
TID-CLOCK-VALID?   ( clock -- flag )
TID-CLOCK-NEXT-MS  ( epoch-ms destination capacity clock -- status )
```

`TID-CLOCK-NEXT-MS` converts trusted Unix epoch milliseconds to physical
microseconds, then chooses the greater of physical time and the prior logical
microsecond plus one. Equal and backward physical inputs therefore remain
strictly increasing. The fixed clock ID is encoded into the low ten bits; it
does not wrap or mutate.

Generation qualifies the complete caller-advertised output span and rejects
overlap with the clock. Every failure preserves both output and clock. Success
publishes all 13 bytes before committing the new logical microsecond.

### Validation and comparison

```forth
TID-VALIDATE  ( address length -- status )
TID-VALID?    ( address length -- flag )
TID-COMPARE   ( tid-a tid-b -- order )
```

Validation enforces exact length, the base32-sort alphabet, and the restricted
first character `234567abcdefghij`. `TID-COMPARE` performs lexicographic
comparison of two already admitted 13-byte TIDs.

The explicit status classes are `TID-S-OK`, `TID-S-INVALID`,
`TID-S-CAPACITY`, `TID-S-ALIAS`, `TID-S-SYNTAX`, `TID-S-RANGE`,
`TID-S-PROTECTED`, `TID-S-PLATFORM`, and `TID-S-EXHAUSTED`.

Returns:
- `-1` if tid1 < tid2
- `0` if equal
- `1` if tid1 > tid2

---

## Bluesky text record — bluesky-text-record.f

The state-free text-record adapter encodes exactly one
`app.bsky.feed.post` object with deterministic member order:

```json
{"$type":"app.bsky.feed.post","text":"...","createdAt":"..."}
```

It admits at most 3,000 raw UTF-8 bytes, uses the shared JSON writer for all
escaping, and formats caller-injected Unix epoch milliseconds as whole-second
UTC RFC3339. A fixed caller-owned staging workspace preserves the destination
on every failure, including unexpected subordinate writer failures. It owns no
clock, credentials, transport, schema registry, or persistence. See the
[complete encoder contract](bluesky-text-record.md).

---

## Authenticated XRPC — xrpc.f

`xrpc.f` is a state-free authenticated query/JSON-procedure composition. It
accepts an already parsed caller-owned `HTARGET`, requires its origin to equal
the ready OAuth profile's PDS, validates the top-level `/xrpc/<nsid>` path, and
seals one caller-owned `HREQ`. GET admits no body; POST borrows exact JSON bytes
only long enough to copy them into the caller-sized request arena.

The builder sequentially qualifies the AT client configuration and durable
session metadata before borrowing the access token once. Inside that loan it
constructs a vault-backed P-256 DPoP proof for the exact method and query-free
HTU, then copies `Authorization: DPoP ...` and `DPoP: ...` into the request.
An optional `atproto-proxy` service reference supports authenticated AppView
requests through the PDS.

There is no default host, ambient bearer token, cursor singleton, response
buffer, blocking HTTP call, or compatibility alias for the removed prototype.
Pagination belongs to the operation/connector that owns the response model.
The cooperative exchange borrows a stable procedure body through completion so
the sole strict DPoP nonce retry can rebuild it. It publishes whether the
current attempt never reached send, may have reached the peer, or has a
detached response; it does not infer repository effects from transport state.

See [Authenticated XRPC request construction](xrpc.md) for the complete input,
workspace, status, cleanup, and wire contract.

---

## Feed Model — feed-model.f

`feed-model.f` is a Bluesky-specific adapter for the bounded
author-feed/timeline response subset used by Streams. It is not a
provider-neutral representation for RSS, Atom, Rabbit, or unrelated protocols.
`BFM-DECODE-FEED ( json-a json-u feed -- status )` requires strict JSON in a
document of at most `BFM-DOCUMENT-CAP`, then validates the bounded projection
that Streams actually retains. It copies and JSON-unescapes those strings into
caller-owned storage, accepts at most eight posts, and commits transactionally:
a rejected response does not alter the destination feed.

The adapter retains the stable AT URI, CID, author DID/handle/display name,
post text, creation and indexing times, nonnegative counts, reply root and
parent URIs, typed repost/pin reasons, and the opaque page cursor. Its retained
text, display-name, handle, and DID buffers reflect the relevant app.bsky/AT
Protocol bounds; AT URIs have an explicit 3,072-byte implementation bound. It
also verifies that each post URI names `app.bsky.feed.post` under the reported
author DID with a syntactically valid TID record key. CID, handle, and datetime
format normalization outside that retained identity check is still trusted to
the AppView. The adapter is not a complete Lexicon or moderation validator: it
owns no HTTP buffers, credentials, session, retained app state, or global
pagination state, and it ignores embeds, facets, labels, moderation decisions,
and viewer state. The explicit Bluesky provider composition preserves those
boundaries; a successful projection decode is not presented as complete
moderation or response validation.

Call `BFM-FEED-INIT` on `BFM-FEED-SIZE` bytes before first use. Feed and item
accessors (`BFM.ITEM.URI`, `BFM.ITEM.TEXT`, and peers) return views into that
caller-owned model. `BFM.FEED.ITEM` returns zero for a negative, out-of-count,
or out-of-capacity index. Capacity, missing-field, type, identity, and malformed
integer failures are explicit `BFM-S-*` statuses.

---

## Session and repository ownership

AT authentication now uses the provider-neutral durable owner in
`akashic/security/oauth2/session.f`. AT grant admission installs exact issuer,
client binding, token type, scope, and token bytes into a RID-addressed sealed
record. XRPC borrows those values synchronously and never retains a loaned
address.

The former AT-local password/JWT singleton and global repository CRUD wrapper
have been retired. They were incompatible with per-connector ownership,
durable DPoP identity, explicit cancellation, and secret cleanup. Repository
operations compose the caller-owned XRPC request/exchange seam; no obsolete
API is preserved in parallel.

---

## Quick Reference

### aturi.f

| Word | Stack | Purpose |
|---|---|---|
| `ATURI-LENGTH-MAX` | `( -- 8192 )` | Protocol-wide source bound |
| `ATURI-STATUS-VALID?` | `( status -- flag )` | Recognize the status vocabulary |
| `ATURI-VALIDATE` | `( source source-u -- status )` | Validate restricted normalized syntax |
| `ATURI-VALID?` | `( source source-u -- flag )` | Boolean validation convenience |
| `ATURI-SPLIT` | `( source source-u -- authority collection rkey status )` | Borrow validated component views |
| `ATURI-BUILD` | `( authority collection rkey destination capacity writer -- written status )` | Transactionally build into caller storage |

### did.f

| Word | Stack | Purpose |
|---|---|---|
| `DID-VALIDATE` | `( addr len -- status )` | Validate generic DID syntax |
| `DID-VALID?` | `( addr len -- flag )` | Validate DID format |
| `DID-METHOD@` | `( addr len -- method-a method-u status )` | Borrow method |
| `DID-SPECIFIC-ID@` | `( addr len -- id-a id-u status )` | Borrow method-specific ID |

### handle.f

| Word | Stack | Purpose |
|---|---|---|
| `AT-HANDLE-VALIDATE` | `( addr len -- status )` | Validate handle syntax |
| `AT-HANDLE-VALID?` | `( addr len -- flag )` | Collapse validation to a predicate |
| `AT-HANDLE-NORMALIZED?` | `( addr len -- flag status )` | Inspect lowercase canonical form |
| `AT-HANDLE-NORMALIZE` | `( source source-u destination capacity -- written status )` | Publish lowercase canonical form |

### tid.f

| Word | Stack | Purpose |
|---|---|---|
| `TID-LENGTH` | `( -- 13 )` | Exact encoded length |
| `TID-CLOCK-SIZE` | `( -- 24 )` | Caller clock object size |
| `TID-STATUS-VALID?` | `( status -- flag )` | Admit the status vocabulary |
| `TID-VALIDATE` | `( address length -- status )` | Validate exact TID syntax |
| `TID-VALID?` | `( address length -- flag )` | Boolean syntax convenience |
| `TID-COMPARE` | `( tid-a tid-b -- order )` | Compare admitted TIDs |
| `TID-CLOCK-INIT` | `( clock-id clock -- status )` | Initialize a fixed-ID clock |
| `TID-CLOCK-VALID?` | `( clock -- flag )` | Inspect clock shape/state |
| `TID-CLOCK-NEXT-MS` | `( epoch-ms destination capacity clock -- status )` | Publish the next TID |

### bluesky-text-record.f

| Word | Stack | Purpose |
|---|---|---|
| `BSKY-TEXT-RECORD-TEXT-MAX` | `( -- 3000 )` | Protocol raw-text byte ceiling |
| `BSKY-TEXT-RECORD-BODY-MAX` | `( -- 18075 )` | Worst-case escaped record size |
| `BSKY-TEXT-RECORD-WORKSPACE-SIZE` | `( -- 18176 )` | Aligned caller staging workspace |
| `BSKY-TEXT-RECORD-STATUS-VALID?` | `( status -- flag )` | Admit the status vocabulary |
| `BSKY-TEXT-RECORD-MEASURE` | `( text-a text-u -- written status )` | Measure exact encoded bytes |
| `BSKY-TEXT-RECORD-WORKSPACE-CLEAR` | `( workspace -- status )` | Wipe a qualified workspace |
| `BSKY-TEXT-RECORD-ENCODE` | `( epoch-ms text-a text-u destination capacity workspace -- written status )` | Publish an exact record |

### xrpc.f

| Word | Stack | Purpose |
|---|---|---|
| `AT-XRPC-AUTH-REQUEST-INPUT-CLEAR` | `( input -- status )` | Clear the caller input descriptor |
| `AT-XRPC-AUTH-REQUEST-WORKSPACE-CLEAR` | `( workspace -- status )` | Wipe transient proof/build storage |
| `AT-XRPC-AUTH-REQUEST-BUILD` | `( input workspace -- status )` | Seal one OAuth/DPoP-authenticated PDS query or JSON procedure |
| `AT-XRPC-STATUS-VALID?` | `( status -- flag )` | Recognize the closed published status vocabulary |

### feed-model.f

| Word | Stack | Purpose |
|---|---|---|
| `BFM-FEED-INIT` | `( feed -- )` | Clear caller-owned feed storage |
| `BFM-DECODE-FEED` | `( json-a json-u feed -- status )` | Transactionally decode a bounded timeline page |
| `BFM.FEED.COUNT` | `( feed -- a )` | Address of retained item count |
| `BFM.FEED.ITEM` | `( index feed -- item \| 0 )` | Address a retained item with bounds checking |
| `BFM.ITEM.URI` | `( item -- a u )` | Read the stable AT URI |
| `BFM.ITEM.TEXT` | `( item -- a u )` | Read copied post text |
| `BFM.ITEM.ROOT-URI` | `( item -- a u )` | Read the retained reply root URI, or an empty string |
| `BFM.ITEM.PARENT-URI` | `( item -- a u )` | Read the retained direct parent URI, or an empty string |

---

## Cookbook

### Validate and split an AT URI

```forth
S" at://did:plc:abc/app.bsky.feed.post/3k2la" ATURI-SPLIT
DUP ATURI-S-OK = IF
    DROP
    TYPE CR  \ record key: 3k2la
    TYPE CR  \ collection: app.bsky.feed.post
    TYPE CR  \ authority: did:plc:abc
ELSE
    >R 2DROP 2DROP 2DROP R> .  \ report the failure status
THEN
```

### Build an AT URI

```forth
CREATE _BUF 128 ALLOT
CREATE _ATURI-WRITER CBW-SIZE ALLOT
S" did:plc:test" S" app.bsky.feed.post" S" 3k2la"
_BUF 128 _ATURI-WRITER ATURI-BUILD
DUP ATURI-S-OK = IF DROP _BUF SWAP TYPE ELSE 2DROP THEN
\ → at://did:plc:test/app.bsky.feed.post/3k2la
```

### Round-trip

```forth
S" at://did:plc:round/trip.test.ns/rk42" ATURI-SPLIT DROP
_BUF 128 _ATURI-WRITER ATURI-BUILD
DUP ATURI-S-OK = IF DROP _BUF SWAP TYPE ELSE 2DROP THEN
\ → at://did:plc:round/trip.test.ns/rk42
```

### Validate a DID

```forth
S" did:plc:abc123" DID-VALID? .    \ → -1 (valid)
S" did:key:z6Mk" DID-VALID? .     \ → -1 (valid unsupported method)
S" hello" DID-VALID? .            \ → 0  (not a DID)
```

### Extract DID method

```forth
S" did:web:example.com" DID-METHOD@
DID-S-OK = IF TYPE ELSE 2DROP THEN        \ → web
```

### Generate and compare TIDs

```forth
CREATE _TC-RAW TID-CLOCK-SIZE 7 + ALLOT
: _TC  _TC-RAW 7 + -8 AND ;
CREATE _T1 16 ALLOT
CREATE _T2 16 ALLOT
7 _TC TID-CLOCK-INIT DROP
1718465400123 _T1 16 _TC TID-CLOCK-NEXT-MS DROP
1718465400123 _T2 16 _TC TID-CLOCK-NEXT-MS DROP
_T1 13 TYPE              \ → e.g. 3kfg7h2abc222
_T1 _T2 TID-COMPARE .    \ → -1 (logical time advanced by one)
```

### Authenticated XRPC

Prepare an exact HTTPS `HTARGET`, a fresh `HREQ` descriptor and wire arena,
the ready OAuth client/profile, a reopened durable session, its shared
credential vault, and trusted epoch seconds in
`AT-XRPC-AUTH-REQUEST-INPUT-SIZE` bytes. Then call:

```forth
_xrpc-input _xrpc-work AT-XRPC-AUTH-REQUEST-BUILD
AT-XRPC-S-OK = IF
  \ The caller-owned HREQ is sealed. Attach it to the cooperative
  \ HTTP/TLS operation owner, then clear it after transport detaches.
THEN
```

See [xrpc.md](xrpc.md) for the complete field and cleanup contract. Cursor
state belongs to the response/connector owner rather than XRPC globals.

---

## Dependencies

- **aturi.f** — requires `uri.f` (generic URI parser) and `string.f`
  (for `STR-INDEX`).
- **did.f** — requires caller-span and memory-span qualification.
- **handle.f** — requires caller-span and memory-span qualification.
- **tid.f** — requires caller-span and memory-span qualification; trusted Unix
  epoch milliseconds are injected by the caller.
- **bluesky-text-record.f** — composes caller-span, memory-span, the checked
  buffer/JSON writers, UTF-8 validation, and the checked UTC formatter.
- **xrpc.f** — composes caller-owned HTTP target/request, AT OAuth
  client/profile policy, generic durable OAuth session, credential vault, and
  vault-backed P-256 DPoP proof owners.
- **feed-model.f** — requires `json.f` and `string.f`; it performs no I/O.
- **public-author-feed.f** — requires external I/O, buffered HTTP, the KDOS TLS
  adapter, and `did.f`. Endpoint trust is contributed separately rather than
  loaded by the provider.

## Internal State

### aturi.f — prefixed `_ATU-`

- `_ATU-PA` / `_ATU-PL` — path splitting state
- `_ATU-BPOS` / `_ATU-BDST` / `_ATU-BMAX` — builder cursor
- `_ATU-RK-A/L`, `_ATU-CO-A/L` — deep stack stash for builder

### did.f and handle.f

The identity syntax modules contain no mutable module operation state.

### tid.f — prefixed `_TID-`

The module has no mutable operation state or clock singleton. Its private
constants describe the 24-byte caller-owned clock layout, the representable
53-bit microsecond bound, and arithmetic base32-sort mapping.

### bluesky-text-record.f — prefixed `_BSKYTR-`

The module has no mutable module state. Operation fields, the checked writer,
timestamp, and maximum escaped body staging arena live entirely in the
caller-owned workspace and are wiped after each admitted operation.

### xrpc.f — prefixed `_ATX-`

The module has no persistent or process-global operation state. Its input,
copied binding, proof descriptor, proof bytes, host scratch, and serial child
workspace all live in the caller's advertised transient workspace and are
wiped after every admitted operation.
