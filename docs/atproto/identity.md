# AT Protocol identity and PDS discovery

`akashic/atproto/identity.f` is the caller-owned, transport-neutral policy
core for resolving an AT Protocol handle or DID. It does not perform DNS,
HTTP, TLS, caching, OAuth, repository, or application work. A caller drives
the resolver's explicit actions, obtains request material from the resolver,
performs I/O through any suitable transport, and submits complete responses.

The result and resolver have independent fixed sizes:

- `ATID-RESULT-SIZE` is a self-contained published identity result.
- `ATID-RESOLVER-SIZE` is temporary state, parser scratch, CNAME history, and
  a DID-document workspace. It can be wiped after `ATID-A-DONE`.

The module owns no mutable global state. Input buffers are borrowed only for
the duration of the consuming call. A published result owns its DID document,
including any retained handle, public key, and PDS target.

## Resolution profile

Production resolution accepts the two DID methods blessed by AT Protocol:

- `did:plc` with exactly 24 lowercase base32 identifier characters, resolved
  at `https://plc.directory/<did>`;
- hostname-level `did:web`, resolved at
  `https://<hostname>/.well-known/did.json`.

Path-based `did:web`, encoded ports, unsupported methods, noncanonical
hostname case, and non-production hostname policy fail before network work.
The handle and `did:web` hostname policy rejects the reserved TLDs `.alt`,
`.arpa`, `.example`, `.internal`, `.invalid`, `.local`, `.localhost`, and
`.onion`. It also rejects `.test`, which AT Protocol reserves for development.
A development adapter may deliberately substitute a different policy; this
production core does not silently admit those names.

## Caller-driven actions

Initialize the two objects, then begin from exactly one identifier:

```forth
result ATID-RESULT-INIT
resolver ATID-RESOLVER-CLEAR

handle-a handle-u result resolver ATID-BEGIN-HANDLE
\ or
did-a did-u result resolver ATID-BEGIN-DID
```

`ATID-ACTION@` returns one of:

| Action | Caller responsibility |
| --- | --- |
| `ATID-A-DNS-QUERY` | Read `ATID-DNS-NAME@`, obtain a fresh unpredictable 16-bit transaction ID, and call `ATID-DNS-QUERY-BUILD` |
| `ATID-A-DNS-EXCHANGE` | Send the exact packet from `ATID-DNS-QUERY$` and submit the complete response to `ATID-DNS-RESPONSE!` |
| `ATID-A-HANDLE-HTTPS` | GET the exact `ATID-HTTP-TARGET@` and submit the final response |
| `ATID-A-DID-DOCUMENT` | GET the exact `ATID-HTTP-TARGET@` and submit the final response |
| `ATID-A-DONE` | Read the published result |
| `ATID-A-FAILED` | Read `ATID-RESOLVER-STATUS@`, then clear or wipe the resolver |

Every initial DNS query and CNAME hop requires a separate
`ATID-DNS-QUERY-BUILD` call. The supplied transaction ID must be a fresh
unpredictable value and must differ from the immediately preceding hop. This
keeps entropy ownership in the platform composition, where the hardware-backed
random source is available, rather than manufacturing IDs inside protocol
policy.

`ATID-ACTION-FAIL` reports that the transport exhausted its bounded retry
policy. A DNS transport failure advances to HTTPS handle fallback. Exhausting
the handle HTTPS action makes handle input fail, but marks a claimed handle
invalid for DID input without discarding the resolved DID. Exhausting a DID
document fetch is a terminal identity failure.

## Handle resolution

Handles of at most 244 bytes first query:

```text
_atproto.<normalized-handle> IN TXT
```

Longer valid handles go directly to
`https://<handle>/.well-known/atproto-did`, because the `_atproto.` prefix
would exceed the 253-byte DNS presentation-name bound.

TXT reduction uses the generic per-RR iterator. Values without a `did=` prefix
and values whose suffix is not a syntactically valid DID are ignored. Repeated
identical valid bindings are accepted. Distinct valid DID bindings fail as a
conflict. An RR's copied bytes are provisional: the identity resolver does
not set `ATID-E-HANDLE-DNS` or use the DID until the iterator has drained all
sections, verified the exact packet end, and reached its validated terminal
state.

When there is no direct valid TXT binding, exactly one direct IN/CNAME may be
followed. Each hop produces a fresh query and transaction ID. The resolver
lowercases DNS names for comparison, rejects a repeated name, and permits at
most `ATID-DNS-CNAME-MAX` (8) hops. Duplicate or conflicting direct records
are not hidden by HTTPS fallback.

A validated DNS mapping is authoritative and proceeds directly to DID
document resolution. HTTPS is only a fallback for DNS absence/failure or the
only method for a handle over 244 bytes. The well-known body may contain at
most `ATID-WELL-KNOWN-TRIM-MAX` (64) total bytes of ASCII space, tab, CR, or
LF around the DID. Interior whitespace and unsupported DIDs fail.

Handle input is published only when the resolved DID document's first valid
`alsoKnownAs` handle is exactly the normalized input handle. This enforces the
required bidirectional link.

## DID input and partial identity

DID input resolves the DID document first. An exact document `id` is the
identity trust boundary. Identity evidence and participation readiness remain
separate: a missing signing key or PDS service does not erase the DID document;
it only makes participation unavailable.

If the document has no usable handle, the result is published with
`ATID-E-HANDLE-MISSING`. If it claims a syntactically valid production handle,
the resolver checks that handle through the same DNS-first flow. A failure,
conflict, unsupported binding, or mapping to a different DID publishes the
original DID result with `ATID-E-HANDLE-INVALID`. Only a reverse mapping to
the exact input DID publishes `ATID-E-HANDLE-VERIFIED`.

`ATID-HANDLE@` exposes only a verified handle. A missing or invalid claimed
handle returns `ATID-S-MISSING`; callers can inspect the owned DID document
through `ATID-DOCUMENT@` when diagnostic presentation is appropriate.

## HTTP boundary

The core accepts only a final HTTP response:

```forth
body-a body-u http-status redirect-count final-target resolver
ATID-HTTP-RESPONSE!
```

The caller owns TLS, redirect target resolution, response framing, and body
collection. The target must remain HTTPS, and the redirect count must not
exceed `ATID-HTTP-REDIRECT-MAX` (3). The core requires a final 2xx status.
`final-target` must be a valid canonical `HTARGET`; with zero redirects it
must equal the target originally exposed for the action. With redirects, the
caller supplies the final HTTPS target after applying each redirect.
Handle response content type is intentionally not a trust condition, matching
the AT Protocol handle specification. DID-document JSON is delegated to the
strict caller-owned DID-document parser.

This explicit boundary avoids inheriting assumptions from a particular HTTP
resource wrapper, including mandatory content type, a hard-coded success
status, or a narrower redirect model.

## Evidence and participation

`ATID-EVIDENCE@` returns a bit set whose shape is validated with the result:

| Evidence | Meaning |
| --- | --- |
| `ATID-E-INPUT-HANDLE` | Resolution began from a handle |
| `ATID-E-INPUT-DID` | Resolution began from a DID |
| `ATID-E-HANDLE-DNS` | The verified handle mapping came from terminal-validated DNS |
| `ATID-E-HANDLE-HTTPS` | The verified handle mapping came from HTTPS well-known |
| `ATID-E-DOCUMENT-ID` | The strict document ID exactly matched the expected DID |
| `ATID-E-HANDLE-VERIFIED` | The document handle resolved back to the DID |
| `ATID-E-HANDLE-MISSING` | The document supplied no usable handle |
| `ATID-E-HANDLE-INVALID` | The claimed handle was unusable or did not resolve back |
| `ATID-E-KEY` | A modern usable AT Protocol signing key exists |
| `ATID-E-PDS` | A usable HTTPS-origin PDS service exists |
| `ATID-E-PARTICIPATION` | Both key and PDS evidence exist |

Exactly one input bit and exactly one handle-state bit are present in every
published result. A verified handle has exactly one mapping-source bit;
missing and invalid handles have none.

`ATID-PARTICIPATION-STATUS` returns:

- `ATID-S-OK` when both signing key and PDS are usable;
- `ATID-S-KEY` when the key is absent;
- `ATID-S-PDS` when the key exists but the PDS is absent.

`ATID-PARTICIPATION-READY?` is the Boolean form. The optional key and PDS
accessors return `ATID-S-MISSING` independently, so identity consumers do not
need to conflate a durable DID with immediate PDS participation.

## Lifecycle and ownership

`ATID-BEGIN-HANDLE` and `ATID-BEGIN-DID` require a valid empty result and idle
resolver. They reject overlapping source, result, and resolver spans before
publication. Response bodies and DNS packets must also be disjoint from both
caller-owned objects.

The result stays empty throughout resolution and on terminal failure.
Publication copies the complete staged DID document, writes evidence, and
seals the result magic last. Accessors reject empty or corrupted results.
`ATID-RESOLVER-WIPE` zeroes a structurally valid resolver; use
`ATID-RESOLVER-CLEAR` to create a new idle resolver afterward.
