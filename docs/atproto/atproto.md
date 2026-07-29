# akashic-atproto — AT Protocol Primitives for KDOS / Megapad-64

AT Protocol identity, record-addressing, XRPC client, bounded Bluesky feed
decoding, session management, and repository CRUD. Foundation layer for
Bluesky and any AT Protocol application.

The bounded, credential-free public author-feed exchange has a separate
[lifecycle contract](public-author-feed.md). It uses the XIO/HBUF provider
contract and the shared KDOS adapter's asynchronous NIO open, close, and cancel
callbacks. It does not share the legacy XRPC/session globals described below.

```forth
REQUIRE aturi.f    \ AT URI parser + builder
REQUIRE did.f      \ strict generic DID identifier syntax
REQUIRE handle.f   \ AT Protocol handle syntax + lowercase normalization
REQUIRE did-document.f \ strict caller-owned AT Protocol identity profile
REQUIRE identity.f \ caller-owned handle/DID/PDS discovery coordinator
REQUIRE identity-hres.f \ identity over generic HTTPS resources
REQUIRE oauth-profile.f \ exact PDS-to-OAuth issuer trust-chain profile
REQUIRE oauth-profile-hres.f \ OAuth discovery over HTTPS resources
REQUIRE oauth-client.f \ AT policy over generic OAuth client configuration
REQUIRE oauth-grant.f \ AT token policy over generic OAuth grants
REQUIRE tid.f      \ TID generation + comparison
REQUIRE xrpc.f     \ XRPC client (GET/POST) + pagination
REQUIRE feed-model.f \ owned app.bsky timeline response model
REQUIRE public-author-feed.f \ bounded cooperative public-feed provider
REQUIRE session.f  \ Session auth (login/refresh/bearer)
REQUIRE repo.f     \ Record CRUD (get/create/put/delete)
```

`PROVIDED akashic-aturi` / `akashic-did` /
`akashic-atproto-handle` / `akashic-tid` /
`akashic-atproto-diddoc` / `akashic-atproto-identity` /
`akashic-atid-hres` / `akashic-at-oauth-prof` /
`akashic-at-oauth-hres` / `akashic-at-oauth-client` /
`akashic-at-oauth-grant` /
`akashic-xrpc` / `akashic-atproto-feed-model` /
`akashic-atp-pubfeed` / `akashic-session` /
`akashic-repo` — safe to include multiple times.

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
- [OAuth token-grant admission — oauth-grant.f](#oauth-token-grant-admission--oauth-grantf)
- [TID — tid.f](#tid--tidf)
- [XRPC Client — xrpc.f](#xrpc-client--xrpcf)
- [Feed Model — feed-model.f](#feed-model--feed-modelf)
- [Session — session.f](#session--sessionf)
- [Repository — repo.f](#repository--repof)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Independent files** | Each file is independently `REQUIRE`-able with its own `PROVIDED` guard. |
| **Explicit ownership** | New identity syntax utilities are stateless; older components retain the ownership documented in their sections. |
| **AT Protocol spec** | Follows the AT Protocol specification for URI syntax, DID validation, TID encoding, XRPC, and session management. |
| **Statusful syntax** | DID and handle admission preserve capacity and platform failures rather than collapsing them into syntax errors. |
| **ASCII codes for JSON** | Manual JSON building uses numeric char codes (34 for `"`, 123 for `{`, etc.) since KDOS has no `S\"` word. |

---

## AT URI — aturi.f

AT URIs follow the format `at://authority/collection/rkey`.

### Storage

Parsed components are copied into static buffers:

| Buffer | Size | Length Variable | Component |
|---|---|---|---|
| `ATURI-AUTHORITY` | 64 bytes | `ATURI-AUTH-LEN` | DID or handle |
| `ATURI-COLLECTION` | 64 bytes | `ATURI-COLL-LEN` | NSID (e.g. `app.bsky.feed.post`) |
| `ATURI-RKEY` | 32 bytes | `ATURI-RKEY-LEN` | Record key |

A length of `0` means the component is absent.

### ATURI-PARSE

```forth
ATURI-PARSE  ( addr len -- ior )
```

Parse an AT URI string.  Returns `0` on success, `-1` on failure.

Validates:
- Scheme must be `at`
- Authority must be non-empty
- Collection and rkey are optional

Internally delegates to `URI-PARSE` from `uri.f`, then verifies the
scheme and splits the path into collection and rkey on `/`.

### ATURI-BUILD

```forth
ATURI-BUILD  ( auth-a auth-u coll-a coll-u rkey-a rkey-u dst max -- written )
```

Build an AT URI from components.  Pass `0 0` for collection and/or
rkey to omit them.  Returns bytes written to `dst`.

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

### TID-NOW

```forth
TID-NOW  ( dst -- )
```

Generate a 13-character TID at `dst`.  Uses `EPOCH@` (milliseconds)
multiplied by 1000 for approximate microsecond resolution.  Clock ID
auto-increments on each call and wraps at 1023.

### TID-COMPARE

```forth
TID-COMPARE  ( tid1 tid2 -- n )
```

Lexicographic comparison of two 13-byte TIDs.

Returns:
- `-1` if tid1 < tid2
- `0` if equal
- `1` if tid1 > tid2

---

## XRPC Client — xrpc.f

XRPC (Cross-RPC) wraps HTTP GET/POST calls to the AT Protocol lexicon
endpoint format: `https://<host>/xrpc/<nsid>`.

### Host Configuration

```forth
XRPC-SET-HOST  ( addr len -- )
```

Set the PDS hostname (max 63 chars).  Default: `bsky.social`.

### URL Building

Internally builds `https://<host>/xrpc/<nsid>?<params>&cursor=<val>`
into a 512-byte buffer.  Query parameters and cursor are appended
automatically when present.

### Cursor / Pagination

```forth
XRPC-SET-CURSOR       ( addr len -- )
XRPC-CLEAR-CURSOR     ( -- )
XRPC-HAS-CURSOR?      ( -- flag )
XRPC-EXTRACT-CURSOR   ( json-a json-u -- )
```

Pagination cursor management.  `XRPC-EXTRACT-CURSOR` parses a JSON
response and stores the `"cursor"` field value into the cursor buffer.
If no cursor key is found, clears the cursor (no more pages).

### XRPC-QUERY (GET)

```forth
XRPC-QUERY  ( nsid-a nsid-u params-a params-u -- body-a body-u ior )
```

Execute a GET request to `<host>/xrpc/<nsid>?<params>[&cursor=<val>]`.
Returns response body and `ior` (0 = success).

### XRPC-PROCEDURE (POST)

```forth
XRPC-PROCEDURE  ( nsid-a nsid-u body-a body-u -- resp-a resp-u ior )
```

Execute a POST request with JSON body.  Returns response body and `ior`.

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

## Session — session.f

Manages authentication with an AT Protocol PDS via `createSession`
and `refreshSession` XRPC procedures.  Stores access + refresh JWT
tokens and the session DID.

> **Legacy boundary:** `session.f` is process-global infrastructure, not owned
> Streams account state. `_SES-CLEAR` clears lengths but does not wipe the
> token/DID bytes, `_SES-JBUF` can retain the serialized app password, and the
> module has no owned logout/zeroization lifecycle. Streams' public-read path
> does not load or call this module. Any authenticated applet integration must
> instead own its session per instance, wipe prompt/request/token scratch, and
> never persist an app password or treat these globals as secure storage.

### Token Storage

| Buffer | Size | Purpose |
|---|---|---|
| `_SES-ACCESS` | 512 bytes | Access JWT |
| `_SES-REFRESH` | 512 bytes | Refresh JWT |
| `_SES-DID` | 128 bytes | Session DID |

### SESS-LOGIN

```forth
SESS-LOGIN  ( handle-a handle-u pass-a pass-u -- ior )
```

Authenticate with a PDS.  Builds `{"identifier":"...","password":"..."}`
and calls `com.atproto.server.createSession`.  On success, stores
JWTs, DID, and sets the HTTP bearer token for subsequent requests.

### SESS-REFRESH

```forth
SESS-REFRESH  ( -- ior )
```

Refresh the session using the stored refresh JWT.  Sends the refresh
token as a Bearer header (per AT Protocol spec) and calls
`com.atproto.server.refreshSession`.  Updates tokens on success.

### SESS-ACTIVE? / SESS-DID

```forth
SESS-ACTIVE?  ( -- flag )
SESS-DID      ( -- addr len )
```

Check if a session is active (access token stored) and retrieve
the session DID.

---

## Repository — repo.f

CRUD operations on AT Protocol records via XRPC.  All operations
require an active session (`SESS-ACTIVE?`).

### JSON Building

Uses manual string concatenation with ASCII char codes for JSON
construction (34 for `"`, 123/125 for `{}`), since KDOS has no `S\"`
word.  Record values are embedded raw (unquoted) to support
pre-built JSON records.

### REPO-GET

```forth
REPO-GET  ( aturi-a aturi-u -- json-a json-u ior )
```

Fetch a record by AT URI.  Parses the URI, builds query params
(`repo=<did>&collection=<nsid>[&rkey=<rkey>]`), and calls
`com.atproto.repo.getRecord`.

### REPO-CREATE

```forth
REPO-CREATE  ( coll-a coll-u json-a json-u -- uri-a uri-u ior )
```

Create a new record.  Builds
`{"repo":"<did>","collection":"<coll>","record":<json>}` and calls
`com.atproto.repo.createRecord`.  Returns the AT URI of the created
record.

### REPO-PUT

```forth
REPO-PUT  ( aturi-a aturi-u json-a json-u -- ior )
```

Overwrite a record at the given AT URI.  Builds
`{"repo":"<did>","collection":"<coll>","rkey":"<rkey>","record":<json>}`.

### REPO-DELETE

```forth
REPO-DELETE  ( aturi-a aturi-u -- ior )
```

Delete a record at the given AT URI.  Builds
`{"repo":"<did>","collection":"<coll>","rkey":"<rkey>"}`.

---

## Quick Reference

### aturi.f

| Word | Stack | Purpose |
|---|---|---|
| `ATURI-PARSE` | `( addr len -- ior )` | Parse AT URI |
| `ATURI-BUILD` | `( auth coll rkey dst max -- written )` | Build AT URI |
| `ATURI-AUTHORITY` | CREATE | 64-byte authority buffer |
| `ATURI-AUTH-LEN` | VARIABLE | Authority length |
| `ATURI-COLLECTION` | CREATE | 64-byte collection buffer |
| `ATURI-COLL-LEN` | VARIABLE | Collection length |
| `ATURI-RKEY` | CREATE | 32-byte rkey buffer |
| `ATURI-RKEY-LEN` | VARIABLE | Rkey length |

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
| `TID-NOW` | `( dst -- )` | Generate 13-char TID |
| `TID-COMPARE` | `( tid1 tid2 -- n )` | Compare two TIDs |

### xrpc.f

| Word | Stack | Purpose |
|---|---|---|
| `XRPC-SET-HOST` | `( addr len -- )` | Set PDS hostname |
| `XRPC-QUERY` | `( nsid params -- body ior )` | XRPC GET request |
| `XRPC-PROCEDURE` | `( nsid body -- resp ior )` | XRPC POST request |
| `XRPC-SET-CURSOR` | `( addr len -- )` | Set pagination cursor |
| `XRPC-CLEAR-CURSOR` | `( -- )` | Clear cursor |
| `XRPC-HAS-CURSOR?` | `( -- flag )` | Check if cursor set |
| `XRPC-EXTRACT-CURSOR` | `( json-a json-u -- )` | Extract cursor from JSON |
| `XRPC-HOST` | CREATE | 64-byte hostname buffer |
| `XRPC-CURSOR` | CREATE | 128-byte cursor buffer |

### session.f

| Word | Stack | Purpose |
|---|---|---|
| `SESS-LOGIN` | `( handle pass -- ior )` | Authenticate with PDS |
| `SESS-REFRESH` | `( -- ior )` | Refresh session tokens |
| `SESS-ACTIVE?` | `( -- flag )` | Check if session active |
| `SESS-DID` | `( -- addr len )` | Get session DID |

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

### repo.f

| Word | Stack | Purpose |
|---|---|---|
| `REPO-GET` | `( aturi -- json ior )` | Fetch record by AT URI |
| `REPO-CREATE` | `( coll json -- uri ior )` | Create new record |
| `REPO-PUT` | `( aturi json -- ior )` | Overwrite record |
| `REPO-DELETE` | `( aturi -- ior )` | Delete record |

---

## Cookbook

### Parse an AT URI

```forth
S" at://did:plc:abc/app.bsky.feed.post/3k2la" ATURI-PARSE DROP
ATURI-AUTHORITY ATURI-AUTH-LEN @ TYPE   \ → did:plc:abc
ATURI-COLLECTION ATURI-COLL-LEN @ TYPE \ → app.bsky.feed.post
ATURI-RKEY ATURI-RKEY-LEN @ TYPE       \ → 3k2la
```

### Build an AT URI

```forth
CREATE _BUF 128 ALLOT
S" did:plc:test" S" app.bsky.feed.post" S" 3k2la"
_BUF 128 ATURI-BUILD
_BUF SWAP TYPE
\ → at://did:plc:test/app.bsky.feed.post/3k2la
```

### Round-trip

```forth
S" at://did:plc:round/trip.test.ns/rk42" ATURI-PARSE DROP
ATURI-AUTHORITY ATURI-AUTH-LEN @
ATURI-COLLECTION ATURI-COLL-LEN @
ATURI-RKEY ATURI-RKEY-LEN @
_BUF 128 ATURI-BUILD
_BUF SWAP TYPE
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
CREATE _T1 16 ALLOT
CREATE _T2 16 ALLOT
_T1 TID-NOW
_T2 TID-NOW
_T1 13 TYPE              \ → e.g. 3kfg7h2abc222
_T1 _T2 TID-COMPARE .    \ → -1 (T1 < T2, generated earlier)
```

### XRPC: Paginated query

```forth
S" pds.example.com" XRPC-SET-HOST
XRPC-CLEAR-CURSOR
BEGIN
  S" app.bsky.feed.getTimeline"
  S" limit=25"
  XRPC-QUERY                   ( body-a body-u ior )
  0= WHILE
    \ process body...
    2DUP XRPC-EXTRACT-CURSOR
    2DROP
  XRPC-HAS-CURSOR? 0= UNTIL THEN ;
```

### Login and create a post

```forth
S" pds.example.com" XRPC-SET-HOST
S" handle.example.com" S" password"
SESS-LOGIN 0= IF
  S" app.bsky.feed.post"
  S" {\"text\":\"Hello from KDOS!\"}"
  REPO-CREATE                   ( uri-a uri-u ior )
  0= IF  TYPE CR  THEN          \ print AT URI
THEN
```

### Delete a record

```forth
S" at://did:plc:abc/app.bsky.feed.post/rk42" REPO-DELETE
0= IF ." Deleted" ELSE ." Failed" THEN
```

---

## Dependencies

- **aturi.f** — requires `uri.f` (generic URI parser) and `string.f`
  (for `STR-INDEX`).
- **did.f** — requires caller-span and memory-span qualification.
- **handle.f** — requires caller-span and memory-span qualification.
- **tid.f** — standalone, uses BIOS `EPOCH@` for timestamps.
- **xrpc.f** — requires `http.f`, `string.f`, `json.f`.
- **feed-model.f** — requires `json.f` and `string.f`; it performs no I/O.
- **public-author-feed.f** — requires external I/O, buffered HTTP, the KDOS TLS
  adapter, and `did.f`. Endpoint trust is contributed separately rather than
  loaded by the provider.
- **session.f** — requires `xrpc.f`, `json.f`, `http.f`.
- **repo.f** — requires `session.f`, `xrpc.f`, `json.f`, `aturi.f`.

Full dependency chain for `repo.f`:
```
repo.f → session.f → xrpc.f → http.f → headers.f → url.f → string.f
                                      → json.f
                   → aturi.f → uri.f
```

## Internal State

### aturi.f — prefixed `_ATU-`

- `_ATU-PA` / `_ATU-PL` — path splitting state
- `_ATU-BPOS` / `_ATU-BDST` / `_ATU-BMAX` — builder cursor
- `_ATU-RK-A/L`, `_ATU-CO-A/L` — deep stack stash for builder

### did.f and handle.f

The identity syntax modules contain no mutable module operation state.

### tid.f — prefixed `_TID-`

- `_TID-ALPHA` — 32-byte base32-sort lookup table
- `_TID-VAL` — 64-bit value being encoded
- `_TID-CLK` — clock ID counter (wraps at 1023)

### xrpc.f — prefixed `_XR-`

- `_XR-URL` — 512-byte URL build buffer
- `_XR-POS` — URL write position
- `XRPC-HOST` / `XRPC-HOST-LEN` — PDS hostname (default `bsky.social`)
- `XRPC-CURSOR` / `XRPC-CURSOR-LEN` — pagination cursor buffer

### session.f — prefixed `_SES-`

- `_SES-ACCESS` / `_SES-ACCESS-LEN` — access JWT (512 bytes)
- `_SES-REFRESH` / `_SES-REFRESH-LEN` — refresh JWT (512 bytes)
- `_SES-DID` / `_SES-DID-LEN` — session DID (128 bytes)
- `_SES-JBUF` — 512-byte JSON build buffer for login
- `_SES-EX-DST/MAX/LEN` — key extraction state
- `_SES-HA/HL/PA/PL` — login build stash

### repo.f — prefixed `_REP-`

- `_REP-JBUF` — 2048-byte JSON body buffer
- `_REP-PBUF` — 256-byte query params buffer
- `_REP-URI` / `_REP-URI-LEN` — result URI buffer (256 bytes)
- `_REP-JP` / `_REP-PP` — write positions for JSON/params
- `_REP-V1A/L`, `_REP-V2A/L` — deep stack stash slots
