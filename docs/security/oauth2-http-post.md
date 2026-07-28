# OAuth 2 HTTP form POST owner

`security/oauth2/http-post.f` owns one bounded OAuth 2
`application/x-www-form-urlencoded` POST in caller memory. It is a generic
Akashic security/network component. It contains no AT Protocol, PDS, Streams,
endpoint-discovery, redirect-following, retry, credential-persistence, or
success/error JSON-decoding policy.

The owner copies one admitted `HTARGET`, builds one request through
`FUEW-*` and `HREQ-*`, drives one caller-supplied cooperative `NIO` port
through `HBUF-*`, and hardens the completed response before publishing a
semantic outcome.

## Memory and configuration

The caller supplies four mutually safe regions:

```forth
target
request-a request-capacity
form-a form-capacity
response-a response-capacity
post OAUTH2-HTTP-POST-CONFIGURE
```

`post` must be eight-byte aligned and span `OAUTH2-HTTP-POST-SIZE`. The
request arena must be at least 64 bytes and the response arena must be
nonempty. Every complete span is qualified through `CALLER-SPAN-STATUS`.
The descriptor, source target, request arena, form arena, and response arena
must have the documented disjoint geometry; exact adjacency is allowed.

Configuration accepts uninitialized nonmagic descriptor storage or the
canonical `EMPTY` descriptor produced by `WIPE`. It rejects a live descriptor
instead of rebinding it and stranding an old port or credential-bearing
arena. Successful configuration clears all three arenas and copies the
target into the descriptor.

`OAUTH2-HTTP-POST-TARGET@` returns the copied target, and
`OAUTH2-HTTP-POST-HTU$` returns its RFC 9449 `htu` view. The underlying
generic `HTARGET-HTU$` removes the query and preserves the canonical absolute
HTTPS URI otherwise; fragments cannot enter an admitted `HTARGET`.

These and all other raw accessors require a structurally valid descriptor.
Call `OAUTH2-HTTP-POST-VALID?` first. Target accessors are meaningful from
`CONFIGURED` onward; request-inclusion predicates from `SEALED` onward; and
body, nonce, HTTP, and semantic-result accessors in `RESULT` or quarantined
`CLEANUP`.

## Lifecycle

Start either a PAR-style operation, whose expected success status is `201`,
or a token-style operation, whose expected status is `200`:

```forth
OAUTH2-HTTP-POST-KIND-TOKEN post OAUTH2-HTTP-POST-BEGIN

S" grant_type" S" authorization_code"
    post OAUTH2-HTTP-POST-FIELD
S" code" code-a code-u post OAUTH2-HTTP-POST-FIELD

dpop-a dpop-u authorization-a authorization-u
    post OAUTH2-HTTP-POST-SEAL
```

`FIELD` delegates encoding to the generic bounded form writer. Field order is
preserved. Names and values are borrowed only for the call. `SEAL` accepts
optional complete DPoP and Authorization field values; absence is exactly
`0 0`. Nonempty values are caller-qualified and cannot alias the request
arena or owner descriptor. The owner adds `Host`, `Accept:
application/json`, `Content-Type: application/x-www-form-urlencoded`,
`Connection: close`, and the exact content length.

The owner never wipes those borrowed source spans. Callers remain responsible
for promptly clearing authorization codes, refresh tokens, client secrets,
DPoP proofs, and other sensitive input storage after `FIELD` or `SEAL`
returns.

`DPOP-INCLUDED?` and `AUTHORIZATION-INCLUDED?` mean that the complete sealed
request contains those headers. `DPOP-SENT?` and `AUTHORIZATION-SENT?` become
true immediately before the first transport send callback can be invoked.
They therefore remain true after a partial write, a zero-byte write, or a
failing send whose adapter may have transmitted bytes. They stay false if the
operation is cancelled or fails before request transmission is attempted.

`START` accepts one direct port:

```forth
port post OAUTH2-HTTP-POST-START
post OAUTH2-HTTP-POST-POLL
```

The port must be caller-qualified, cooperative, detached, and disjoint from
the owner and all three arenas. The caller must bind that port to the exact
host and numeric port in `OAUTH2-HTTP-POST-TARGET@`, with authenticated TLS
and the copied host as the server identity. `NIO` intentionally treats its
adapter context as opaque, so this destination binding is the caller's
explicit trust-boundary obligation. The owner never redirects or rebinds the
port.

`START` and `POLL` return `S-PENDING` while work remains. A clean terminal
exchange returns `S-OK`; inspect `OUTCOME@`, `DETAIL@`, and the lower
diagnostics to distinguish HTTP, header, media, protocol, transport, and
cancelled results. This owner has no clock or built-in deadline: the caller
must impose one and invoke `CANCEL` when it expires. `CANCEL` is cooperative.
If a response is already complete, that admitted response wins; otherwise
the owner publishes cancellation.

## Response admission

Every response whose `HSTR` parser reached `DONE` undergoes header hardening
and nonce capture before its semantic HTTP outcome is chosen, including a
response completed while close or cancellation is in progress.

The owner rejects:

- duplicate `Content-Length`, `Content-Type`, `Content-Encoding`, or
  `DPoP-Nonce`;
- a declared `Trailer` field or actual chunk trailers;
- a present `Content-Encoding` other than the exact singleton token
  `identity`;
- an empty, over-capacity, or non-`NQCHAR` DPoP nonce.

Nonce storage is cleared before each capture. A duplicate or invalid nonce is
never published. A valid singleton nonce is copied into the descriptor and
retained until the next `BEGIN` or `WIPE`.

Only the expected success status and `400`/`401` are JSON semantic
candidates. Each candidate requires a nonempty body and one syntactically
valid singleton `application/json` content type; media parameter names must
be unique case-insensitively. Expected status publishes `O-SUCCESS`, while
`400` or `401` publishes `O-OAUTH-ERROR`. Other statuses remain `O-HTTP`;
3xx is retained as a redirect result but is never followed.

This layer validates the media envelope, not the JSON schema. PAR, token, and
OAuth error decoders consume the retained body separately.

Caller-owned descriptors provide independent retained state, not parallel or
reentrant execution. The underlying `HREQ`, `HBUF`, `HSTR`, and `MTYPE`
layers use module-global scratch. Their operations and every public lifecycle
call in this owner are therefore process-wide non-reentrant: independent
owners may interleave only at completed public-call boundaries. An `NIO`
callback invoked by `START`, `POLL`, or `CANCEL` must not call this owner,
another HTTP owner, or any `HREQ`/`HBUF`/`HSTR`/`MTYPE` operation. Schedule
such work after the outer lifecycle call returns.

## Cleanup and quarantine

On every cleanup-certain terminal path, the complete request and form arenas,
embedded request/writer state, and copied Authorization/DPoP request bytes
are scrubbed. A completed response body and valid nonce remain available
until `BEGIN` or `WIPE`; an incomplete response arena is cleared.

A retained success or OAuth-error body may itself contain access tokens,
refresh tokens, or other credentials. The caller must decode or copy only
what it needs, move durable material directly into protected storage, and
call `BEGIN` or `WIPE` promptly when the retained body is no longer needed.

If `HBUF` still retains a port after cancellation or close failure, the owner
enters `STATE-CLEANUP` with `CLEANUP-UNCERTAIN`. `BEGIN`, ordinary `CANCEL`,
and `WIPE` refuse that descriptor, preserving all evidence and avoiding a
use-after-release. Quarantine intentionally leaves credential-bearing request
and form copies, plus any completed response, live until successful
finalization. The caller must keep the descriptor and all three arenas
exclusively owned and protected; none may be freed, rebound, reused, or
exposed while cleanup is uncertain.

`OAUTH2-HTTP-POST-CLEANUP-FINALIZE` is the only recovery transition. It
performs no I/O. After the external transport owner has conclusively made the
same retained port detached, `FINALIZE` requalifies its complete geometry,
requires the owner and `HBUF` port pointers to agree, re-admits a completed
response, scrubs egress, and enters `RESULT`. If detachment is not proven,
the quarantine remains unchanged. Quarantine-time lower error diagnostics
are preserved rather than overwritten by the recovered port state. The
external owner may fully deinitialize the recovered port, including clearing
its callback bindings: `FINALIZE` requires safe detached state and matching
storage geometry, not the start-time transport capabilities.

`WIPE` is allowed only when cleanup is certain and no exchange is active. It
zeroes all three arenas and the full owner, then publishes the canonical
valid `EMPTY` descriptor.

## Main inspection API

```forth
OAUTH2-HTTP-POST-VALID?                 ( post -- flag )
OAUTH2-HTTP-POST-STATE@                 ( post -- state )
OAUTH2-HTTP-POST-OUTCOME@               ( post -- outcome )
OAUTH2-HTTP-POST-DETAIL@                ( post -- detail )
OAUTH2-HTTP-POST-CLEANUP@               ( post -- cleanup )
OAUTH2-HTTP-POST-LAST-STATUS@           ( post -- status )
OAUTH2-HTTP-POST-HTTP-STATUS@           ( post -- http-status )
OAUTH2-HTTP-POST-BODY@                  ( post -- address length )
OAUTH2-HTTP-POST-NONCE@                 ( post -- address length present? )
OAUTH2-HTTP-POST-DPOP-INCLUDED?          ( post -- flag )
OAUTH2-HTTP-POST-AUTHORIZATION-INCLUDED? ( post -- flag )
OAUTH2-HTTP-POST-DPOP-SENT?              ( post -- flag )
OAUTH2-HTTP-POST-AUTHORIZATION-SENT?     ( post -- flag )
```

Lower diagnostic accessors retain the last `FUEW`, `HREQ`, `HBUF`, `HSTR`,
`NIO` open/close/cancel, and `MTYPE` statuses. The status, outcome, and detail
constant families are deliberately separate: an `S-OK` terminal operation
can still carry an HTTP or protocol semantic outcome that the caller must
handle.
