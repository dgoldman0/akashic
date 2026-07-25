# Cooperative HTTP ownership

The cooperative HTTP path is a caller-owned server substrate for accepted
HTTP/1.1 connections. It keeps protocol parsing, route selection, response
construction, and transport progress under `web/`; an application owns only
its route configuration and operation state.

## Modules

| Module | Responsibility |
| --- | --- |
| `http-request-stream.f` | Strict incremental request framing and bounded body delivery |
| `http-router-owner.f` | Caller-owned route configuration with copied method and path bytes |
| `http-response-writer.f` | Bounded response headers, pull-source bodies, and partial sends |
| `http-connection-owner.f` | One cooperative request/response lifecycle on one already-open port |

All mutable state is supplied by the caller. The modules allocate no storage,
open no listener, persist no descriptor, and contain no process-global current
request, response, route, or connection.

## Request framing

`WREQ-INIT` binds a request descriptor to a caller-supplied header arena and a
caller-selected body limit. `WREQ-FEED` returns the exact number of input bytes
it consumed. It stops at `WREQ-S-HEADERS-READY` before consuming a positive
body, so an owner can route the request and explicitly select a body sink or
discard policy. Bytes following that boundary remain with the connection
owner.

The parser accepts only the supported HTTP/1.1 framing:

- CRLF request and header lines;
- one syntactically valid `Host`;
- an origin-form request target;
- zero or one `Content-Length`; and
- no `Transfer-Encoding`, `Expect`, folded headers, bare LF, or control bytes.

Header metadata stays in the supplied arena. `WREQ-HEADER-LOOKUP` returns the
first trimmed value and the complete occurrence count, allowing
duplicate-sensitive application policy without reparsing the wire bytes.

The body limit is an admission policy supplied at initialization, not a
module-wide payload constant. Body callbacks receive only the currently
borrowed slice and must consume it before returning.

## Routing

`HROUTER-INIT` binds a route descriptor to a caller-supplied entry array and
byte arena. `HROUTER-ADD` copies the method and exact path into that arena and
records the route's operation size plus its `START`, `POLL`, `CANCEL`, and
`CLEANUP` callbacks. `HROUTER-SEAL` makes the configured table immutable.

Matching is an exact method/path comparison. Once the router, match storage,
and input-span geometry are safe to access, any failed or invalid match clears
the caller-owned result, so a prior route cannot survive as stale authority.
Inputs that alias the match result or cannot name a safe span are rejected
without touching either region. Route count and byte capacity are properties
of the supplied arenas; there is no separate global route ceiling.

## Responses

`HRESP-INIT` binds separate caller-supplied header and send arenas.
`HRESP-BEGIN`, `HRESP-HEADER-FIELD`, and `HRESP-CONTENT-TYPE` construct a
bounded header block. Framing-owned fields cannot be injected through the
generic header API. `HRESP-BODY-SOURCE` installs an exact-length pull source,
and `HRESP-SEAL` adds the one authoritative `Content-Length` and
`Connection: close`.

`HRESP-SEND-STEP` makes at most one source or transport call. It preserves
partial-send offsets and distinguishes failure or cancellation before versus
after acknowledged bytes. Cancellation during a borrowed source or transport
callback is deferred until the callback returns; acknowledgement of the final
byte wins over a late cancellation request.

## Connection lifecycle

`HCONN-INIT` receives pristine request, response, match, sealed router, open
`NIO` port, receive arena, route-operation arena, and configured authority.
It seals their exact non-overlapping geometry and installs the request-body
bridge. `HCONN-START` begins one request, and every `HCONN-STEP` performs at
most one transport action.

For a matched route, the owner calls:

```forth
( exchange operation handler-context -- outcome )  START
( exchange operation handler-context -- outcome )  POLL
( exchange operation handler-context -- outcome )  CANCEL
( exchange operation handler-context -- error )    CLEANUP
```

`START` is entered once. Once it has been entered, `CLEANUP` is entered exactly
once, after the response pull source can no longer reference route-operation
storage. Cleanup wipes that storage before the port closes. Parser, routing,
handler, response, transport, cancellation, and cleanup results remain
distinct. The first decisive transport result and first primary connection
failure remain authoritative when cancellation or close later reports a
secondary problem. Automatic `400`, `404`, `413`, `421`, `431`, `500`, and
`503` responses do not overwrite that primary result.

Listener ownership, accept scheduling, TLS policy, keep-alive, pipelining, and
Desk service hosting are outside this one-request owner. They can schedule any
number of descriptors without introducing shared protocol state.

## Streams composition

`tui/applets/streams/http-route.f` composes these general facilities with one
caller-owned Streams execution pool. It admits only a pool whose complete
descriptor, carrier, byte, operation, and connector geometry is disjoint from
the router and connection owner. Each matched connection gets a fresh route
operation containing its exact flow generation and pool lease.

Positive request bodies are appended from borrowed parser slices into the
leased ingress carrier. A successful transform leaves its sealed terminal
egress readable while the response writer pulls the exact JSON bytes. The
operation pins the carrier's independent payload generation for those reads;
the flow generation remains the authority for cancellation and retirement.
Only after the response source is unreachable does route cleanup retire the
exact flow generation, wipe both carriers and operation storage, and release
the lease. No response buffer is copied into every flow cell, and request,
response, profile, route-table, and pool capacities remain caller-selected
bounds.

## Prerelease convergence

`web/server.f`, `web/rpc.f`, and their current Node consumers still require
the earlier process-global web composition. The cooperative owner does not
wrap or emulate those APIs, and Streams does not depend on them. Those
consumers should move directly to the caller-owned facilities before the
first supported release; once the final consumer moves, the displaced global
modules and their obsolete documentation should be deleted rather than kept
as a second maintained server surface.
