# Public author-feed exchange

`akashic/atproto/public-author-feed.f` is a bounded, per-instance provider for
one credential-free Bluesky public author-feed request. It owns request
construction, a KDOS TLS adapter, the cooperative buffered HTTP exchange, and
the transient response allocation. It deliberately stops at wire admission:
it does not decode JSON, mutate a feed model, commit Streams state, own an XIO
service, or act as a general AT Protocol session.

The fixed request is:

```text
GET /xrpc/app.bsky.feed.getAuthorFeed?actor=<percent-encoded actor>&limit=8&filter=posts_no_replies&includePins=false HTTP/1.1
Host: public.api.bsky.app
Accept: application/json
Accept-Encoding: identity
User-Agent: Akashic-Streams/0.3
Connection: close
```

There is no `Authorization` header or credential input. The configured actor
must be a valid DNS handle or a nonempty, syntactically bounded `did:plc` or
`did:web` identifier. Query encoding is provider-owned and accepts only ASCII
actor syntax before applying RFC 3986 unreserved-byte rules. Actor storage is
2048 bytes, the encoded path is 7168 bytes, the complete request is 8192
bytes, and the transient response body is capped at 256 KiB.

## Trust contribution

`akashic/atproto/public-trust.f` provides the reviewed native-TLS trust needed
by this endpoint. Trusted boot code calls `ATPUBLIC-TRUST-REGISTER` before Desk
freezes the machine trust registry. The contribution contains Let's Encrypt's
active RSA-2048 YR1 and YR2 intermediates, sourced from its
[certificate inventory](https://letsencrypt.org/certificates/), and gives each
one the exact DNS scope `public.api.bsky.app` with subdomain matching disabled.
It grants no trust to `bsky.app`, other AT Protocol hosts, or future providers.

Both intermediates are present so ordinary YR1/YR2 leaf rotation does not
require changing the machine image. Their validity ends on 2028-09-02; a later
release must review and replace the contribution rather than downloading or
expanding trust at runtime. Registration is explicit and idempotent. Provider
construction does not register an anchor or mutate KDOS trust by itself.

## Lifecycle and XIO boundary

Allocate `PUBLIC-AUTHOR-FEED-SIZE` bytes, call `PAF-INIT`, then call
`PAF-CONFIGURE`. Configure an external operation with these callbacks and the
provider as its context:

```forth
['] PAF-XIO-START
['] PAF-XIO-POLL
['] PAF-XIO-CANCEL
['] PAF-XIO-WIPE
```

`PAF-XIO-START` first requires nonzero `NIO.OPEN-START-XT`,
`NIO.OPEN-POLL-XT`, and `NIO.CANCEL-XT` callbacks on the embedded port. It
never falls back to the legacy blocking open callback. A successful operation
retains the admitted bytes at `PAF-BODY@` until the owner calls `XIO-RESET`;
decoding and committing those bytes belong to the caller. Cancellation and
failure use XIO's exact-once cancel/wipe lifecycle. Wipe zeros request, path,
parser scratch, and body storage before freeing the transient body, and clears
all embedded response pointers.

The provider admits only HTTP 200 with exactly one `Content-Type` whose media
type is `application/json` (case-insensitive, with optional safe parameters).
`Content-Encoding` may be absent or exactly `identity`, and duplicate encoding
headers are rejected. HTTP, media, encoding, capacity, and transport failures
remain distinguishable through `PAF.ERROR-KIND`, `PAF.ERROR-CODE`, and
`XIOO.ERROR`. Cleanup failure is retained separately in
`PAF.CLEANUP-ERROR`; a poisoned provider remains failed and refuses
reconfiguration instead of claiming release.

## Current transport status

The native KDOS TLS adapter still exposes a blocking real open path. Therefore
the production adapter currently fails this provider's cooperative-port gate
as unsupported. The deterministic profile replaces only the embedded NIO
callbacks with a partial-I/O fixture to qualify request bytes, parser
admission, cancellation, and cleanup. That fixture is not evidence of live
DNS or TLS readiness. The separate `atproto-public-trust` profile validates
the anchor bytes, exact scopes, parser admission, and registry freeze contract.

Run the focused contract with:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile public-author-feed --max-steps 3000000000 --timeout 180
```
