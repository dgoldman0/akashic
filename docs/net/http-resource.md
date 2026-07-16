# Bounded HTTPS resource acquisition

`akashic/net/http-resource.f` is the transport-neutral boundary for fetching
one configured HTTPS resource. It owns the canonical target chain, exact GET
request, cooperative buffered exchange, header admission, syntax-parsed media
type with caller-supplied semantic admission, opaque validators, and terminal
acquisition outcome. It does not depend
on KDOS, Desk, Streams, trust anchors, credentials, or a payload decoder.

The response body is caller-owned. The resource borrows that positive,
bounded buffer while configured and wipes it on cancellation, release, and
every outcome which is not an admitted final `200` response.

## Frozen specification

A specification is built and sealed before it is copied into a resource:

```forth
CREATE spec HRES-SPEC-SIZE ALLOT

spec HRES-SPEC-INIT
S" https://feeds.example.test/feed.xml" spec HRES-SPEC-TARGET! THROW
S" application/rss+xml, application/atom+xml" spec HRES-SPEC-ACCEPT! THROW
3 spec HRES-SPEC-REDIRECT-MAX! THROW
bind-context ['] bind-target ['] release-port
    spec HRES-SPEC-BINDING! THROW
media-context ['] admit-media spec HRES-SPEC-MEDIA! THROW
spec HRES-SPEC-SEAL THROW
```

`bind-target` has stack effect
`( target bind-context -- port provider-status )`. It receives the exact
admitted `HTARGET` for every physical hop and may only configure and lease a
cooperative NIO port; it must not perform network I/O. Zero provider status
with a nonzero port means success and transfers one lease. The returned port
must be cooperative, closed, detached, and free of prior cancellation or close
errors. A zero port with zero status is an invariant fault and must not hide an
acquired lease. A nonzero provider status must return port zero and transfer
no lease. A returned port
which violates either contract is treated as a provisional bad lease and the
provider violation faults the resource. A structurally safe detached lease is
released; a cooperative non-detached lease is first cancelled and released
only after the cancelled state is proved. If the handle overlaps protected
resource memory, is noncooperative and non-detached, or otherwise cannot be
proved detached, cleanup is poisoned and the lease remains retained rather
than risking release of an active connection. A thrown bind callback likewise
must not have acquired or transferred a lease: no port handle has crossed the
callback boundary, so the resource has nothing it can safely release.

`release-port` has stack effect
`( port bind-context -- provider-status )`. It is provider bookkeeping only.
The resource calls it exactly once and only after `HBUF.PORT` is zero and the
lower open, close, or cancellation path has proved detachment. It is not called
when that proof is unavailable. A callback failure or uncertain retained port
poisons cleanup rather than being reported as an ordinary HTTP outcome.

`admit-media` has stack effect
`( media-model media-context -- media-status )`. It receives the resource-owned,
syntax-valid `MTYPE` for the final `200`. Zero admits it; a nonzero status is a
retained media rejection, and a throw is a callback fault. The callback is a
pure policy check and must not mutate the media model or perform I/O.

The module is single-threaded and non-reentrant. Its implementation shares
module-level scratch across resources, so bind, release, and media callbacks
must not call any `HRES-*` operation, even for a different resource. Owners may
drive multiple resources cooperatively, but each public call must return before
another resource is entered.

This lease boundary lets a KDOS composition configure its TLS adapter from
the supplied canonical host and port without making the generic resource know
about KDOS. It also forces a fresh bind, DNS resolution, address admission,
and physical connection for each accepted redirect hop.

## Resource lifecycle

```forth
CREATE resource HTTP-RESOURCE-SIZE ALLOT
CREATE body 131072 ALLOT

resource HRES-INIT
spec body 131072 resource HRES-CONFIGURE THROW

resource HRES-START
\ Poll HRES-POLL until it is not HRES-S-PENDING.
\ Or install HRES-XIO-START/POLL/CANCEL/WIPE on an owner XIO operation.
```

The public state is idle, configured, active, result, released, or fault. The
active implementation uses separate prepare, exchange, and admit phases. One
poll never completes one hop and starts the next physical open: terminal HBUF
work advances to admission, admission releases and accepts the redirect, and a
later prepare poll binds the next hop.

Cleanup poison is a terminal quarantine, not a retry state. `HRES-POLL`,
`HRES-CANCEL`, `HRES-WIPE`, `HRES-START`, and `HRES-DECONFIGURE` continue to
return `HRES-S-CLEANUP`; none retries cancellation or provider release. The
owner must keep the resource, its bind context, and the retained lease storage
alive and must not call `HRES-INIT`, reuse, or free them. Disposition requires a
provider-specific out-of-band recovery which can prove what happened to that
lease; the generic resource deliberately cannot guess.

Cleanly detached HTTP, redirect, media, encoding, capacity, protocol, and
transport failures are retained acquisition results. Inspect them with
`HRES-OUTCOME@`, `HRES-DETAIL@`, `HRES-HTTP-STATUS@`, and the exact
`HRES-PROVIDER-STATUS@`, `HRES-TRANSPORT-STATUS@`, `HRES-PARSER-STATUS@`,
`HRES-POLICY-STATUS@`, and `HRES-EXCHANGE-STATUS@` fields. This lets an owner
record a truthful failed attempt.
`HRES-XIO-*` reports such a retained result as a successful external operation;
invalid state and callback or provider-invariant faults fail the XIO operation,
while cleanup uncertainty fails it with a distinct cleanup error. Exact media
callback and lower-port diagnostics remain available through
`HRES-MEDIA-STATUS@` and `HRES-LOWER-ERROR@`. The semantic acquisition result is
never inferred from the XIO state alone.

An XIO deadline is retained as `HRES-O-TIMED-OUT`, distinct from explicit
cancellation. Automatic cancellation and wipe remove body, request, parser,
validator, and lower-port material while retaining the outcome, canonical
target chain, effective target, and per-hop statuses until the next start or
deconfiguration.

An admitted result provides:

- exact requested and effective canonical URI;
- up to four retained targets and per-hop HTTP statuses;
- final status `200`;
- one owned, syntax-valid and caller-admitted `MTYPE` model;
- optional singleton, nonempty `ETag` and `Last-Modified` copies;
- the exact admitted caller-owned body; and
- separate primary, transport/parser/policy/provider, and cleanup diagnostics.

The consuming syndication or watched-page adapter supplies the semantic media
policy callback and still owns charset policy, payload decode, and any durable
commit.

## First-version admission policy

Every request is an exact origin-form `GET` with canonical `Host` (including a
non-default port), caller-bounded `Accept`, `Accept-Encoding: identity`, a
fixed user agent, and `Connection: close`. No authorization, cookie,
conditional, or provider-specific header is accepted from configuration.

Only `301`, `302`, `303`, `307`, and `308` redirect. `HTARGET-REDIRECT` admits
only the existing strict origin-relative form or same-origin absolute HTTPS
target. Every candidate is compared with the complete retained chain, and the
configured limit cannot exceed three. Cross-origin redirects remain a
distinct authority-required outcome. `304` is deliberately an HTTP outcome,
not success, until a retained-representation owner can bind validators to the
exact prior effective URI.

Before any response is used, the resource rejects duplicate Content-Length,
Content-Type, Content-Encoding, Location, ETag, or Last-Modified fields,
Trailer declarations, and actual chunked trailers. Content-Encoding must be
absent or singleton `identity`. A final `200` requires exactly one syntactically
valid Content-Type which the sealed media callback admits; duplicate media
parameter names are rejected case-insensitively.

The body bound is the aggregate transfer-decoded body budget across redirect
hops, not a total on-wire byte counter. Redirect responses are fully consumed
and closed before their Location is admitted, so an oversized redirect body
fails capacity rather than being followed. Starting every followed hop also
requires at least one byte of remaining body capacity; exact exhaustion on a
redirect therefore terminates with `HRES-O-BODY-OVERFLOW` even if the next
response might have an empty body. Header, line, trailer, redirect, body, and
XIO deadline bounds still cap the current implementation, but early header-only
redirect handling and exact whole-wire accounting would require a lower-layer
extension.

Run the deterministic fake-transport gate with:

```sh
python3 -B local_testing/akashic_tui.py smoke --profile http-resource-contracts
```
