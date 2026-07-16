# KDOS TLS Transport

`akashic/net/transports/kdos-tls.f` binds Akashic's caller-owned `NIO`
byte-stream port to KDOS DNS, TCP, and authenticated TLS 1.3 services.
It contains no HTTP, credential, Agent, provider, Desk, TUI, emulator, or host
bridge code.

```forth
REQUIRE net/transports/kdos-tls.f
```

## Lifecycle

```forth
CREATE transport KDOSTLS-SIZE ALLOT

transport KDOSTLS-INIT
S" api.openai.com" 443 transport KDOSTLS-CONFIGURE THROW

\ Optional only for a separately reviewed policy. The default is public IPv4.
policy-context ['] my-address-policy transport KDOSTLS-ADDRESS-POLICY! THROW

transport KDOSTLS.PORT NIO-OPEN-START
\ Poll NIO-OPEN-POLL until it returns a terminal status.
\ Use transport KDOSTLS.PORT with HREQ-SEND-STEP or HSTR-PUMP.
transport KDOSTLS.PORT NIO-CLOSE-START
\ Poll NIO-CLOSE-POLL until it returns a terminal status.
```

`KDOSTLS-CONFIGURE` accepts one validated DNS hostname of at most 64 bytes and a
remote port from 1 through 65535. `KDOSTLS-INIT` installs native
`NIO.OPEN-START-XT`, `NIO.OPEN-POLL-XT`, `NIO.CLOSE-START-XT`,
`NIO.CLOSE-POLL-XT`, and `NIO.CANCEL-XT` callbacks. `NIO-OPEN` and `NIO-CLOSE`
remain blocking compatibility words, but they drive the same connector and
close state machines rather than selecting a second transport path. The legacy
open remains deliberately blocking and may enter `NET-IDLE` between at most
4096 state-machine polls. Compatibility close performs at most 256 nonwaiting
polls and aborts if teardown is still pending; new consumers use the explicit
asynchronous callbacks for both directions.

Open invokes one scheduled network or handshake phase per poll: TLS/ClientHello
preparation, cooperative DNS and ARP, TCP establishment, at most one incoming
frame or one reassembled handshake message, and client Finished. The connector
has a 15-second deadline, rechecks route-cache state immediately before lower
sends, and accepts success only while it still owns the adapter, the recorded
TCB identity still matches, TCP and TLS are established, and peer authentication
is set. The request uses HTTP/1.1 ALPN, and the KDOS trust store must already
contain an applicable anchor.

Normal close is also cooperative. It retains the TLS context and machine owner
while it sends `close_notify`, waits for that alert to be acknowledged, sends
FIN, and polls until the TCB reaches `CLOSED` or `TIME_WAIT`. At `TIME_WAIT` the
adapter wipes and detaches its TLS context and releases its owner; the lower TCB
remains in KDOS's global table to expire normally. A cold route is resolved
cooperatively within the same two-second close deadline. If graceful teardown
cannot make progress, the deadline expires, or the close-notify operation
rejects the send, the connector falls back to `TLS-ABORT`, which uses the lower
`TCP-ABORT` path when a matching live TCB is still present. Peer-first shutdown
can drain authenticated plaintext, reply with `close_notify` from TCP
`CLOSE_WAIT`, send FIN, and recognize the lower `LAST_ACK` reclamation without
misreporting an abort fallback.

Cancellation, failed open, and abnormal higher-level teardown use that abort
path directly. `KDOSTLS-FREE` first requires `NIO-CANCEL` to report
`NIO-S-CANCELLED`; it does not erase or free a descriptor after uncertain lower
cleanup. Callback exceptions are retained as cleanup failure instead of being
reported as a successful detach. Abort never initiates ARP, polls the NIC, or
waits: its only possible wire action is a cached-route best-effort RST, followed
by unconditional local TCB reclamation and TLS-context wipe.

`NIO-SEND` and `NIO-RECV` preserve partial progress. A zero-byte receive while
the TLS context is established is idle; an authenticated `close_notify` maps to
`NIO-S-EOF`. A bare TCP FIN may drain already authenticated plaintext, but the
next receive is TLS truncation and maps to `NIO-S-FAILED`. Malformed records,
authentication loss, invalid callback counts, and other transport faults also
map to `NIO-S-FAILED`.

Default post-open I/O never falls into KDOS's blocking ARP fallback. If the
remote next-hop cache entry has gone cold, default `NIO-SEND` and `NIO-RECV`
fail immediately with `KDOSTLS-E-IO`; the owner can cancel and retry through a
fresh cooperative open. Default `NIO-POLL` performs no ARP and admits at most
one frame, entering a TCP reply path only after both the adapter route and the
incoming source route have cached next hops.

## Resolved-address admission

Every native open copies the first selected DNS A-record address into
descriptor-owned storage, then advances through a distinct
`KDOSTLS-PHASE-DNS-ADMIT` poll before remote ARP or TCP can begin. The default
policy is `PUBLIC-IPV4?`: it rejects unspecified, private, shared, loopback,
link-local, protocol-assignment, documentation, benchmarking, multicast, and
reserved IPv4 destinations. A rejection is terminal `KDOSTLS-E-ADDRESS`, and
ordinary connector cleanup wipes the chosen address and releases ownership.

`KDOSTLS-ADDRESS-POLICY!` has stack effect
`( context xt adapter -- status )`; the callback has stack effect
`( ipv4-a context -- admitted? )`. Policy can be replaced only while the
adapter is closed. This is the explicit seam for a separately reviewed local
network policy; source configuration and DNS data cannot change it. The
callback receives a shadow of the exact address retained for TCP, and mutation
of that shadow is detected and denied, so an admit callback cannot redirect
the subsequent connection by rewriting its argument.

Each new physical open resolves and admits again. Higher layers which follow a
redirect or retry a request should use a nonpersistent connection when they
need that fresh selection. The current KDOS resolver selects one IPv4 A record;
the connector does not skip a rejected first result in search of a later one.

## Ownership

The adapter descriptor owns configuration and connection state but not the
KDOS trust store. `KDOSTLS-NEW`/`KDOSTLS-FREE` are available for heap ownership;
`KDOSTLS-INIT` supports embedded or static descriptors.

Normal Akashic boots provision KDOS through the
[machine trust registry](tls-trust-registry.md): reviewed modules contribute
scoped anchors, and Desk freezes the composed snapshot before external I/O is
initialized. Provider constructors and applets do not call `TLS-TRUST-LOAD` or
`TLS-TRUST-RESET`; those remain platform provisioning primitives.

KDOS currently shares its TLS handshake, SNI, record, and receive scratch.
`kdos-tls.f` therefore permits one active adapter at a time and reports
`KDOSTLS-E-BUSY` to another opener. This is an explicit machine-layer limit, not
a provider or Desk policy. Concurrent TLS requires descriptor-owned KDOS record
state in a later KDOS change.

Graceful detach and `TLS-ABORT` wipe the adapter's TLS context and the
connector-owned staging fields. They do **not** yet prove sanitization of all
machine-global TLS and cryptographic scratch, such as shared handshake, key
agreement, transcript, and record buffers. The current lifecycle guarantee is
lower ownership detachment plus context wipe, not a comprehensive machine-wide
secret-erasure boundary.

## Diagnostics

`KDOSTLS.STATE`, `KDOSTLS.PHASE`, `KDOSTLS.LAST-ERROR`,
`KDOSTLS.NATIVE-ERROR`, `KDOSTLS.CLEANUP-ERROR`, `KDOSTLS.ABORT-STATUS`, and
`KDOSTLS.CLOSE-FALLBACKS` expose lifecycle diagnostics. Step count and cycle
fields make cooperative-poll measurements visible to deterministic profiles.
`KDOSTLS.NATIVE-ERROR` carries `TLS-CONNECT-E-*` while opening; after an
authenticated record-processing failure it instead retains the nonzero native
`TLS-E-*` context error before cleanup wipes and releases that context. It is
therefore a native-domain companion to the adapter-level `LAST-ERROR`, not one
single error enumeration. Error constants distinguish invalid configuration,
owner contention, absent or changed trust, DNS/connect/authentication failure,
timeout, cancellation, cleanup failure, I/O failure, and a thrown platform
callback. Address-policy denial has its own `KDOSTLS-E-ADDRESS` result rather
than being reported as DNS or TCP failure.

TCB identity checks validate table range and alignment plus the local/remote
tuple and initial send sequence. They reject pointer and fingerprint mismatch,
but KDOS exposes no allocation generation: a future slot reuse that recreates
the exact tuple and ISS remains theoretically indistinguishable.

Streams' explicit public-author-feed composition and the Codex source both use
this connector implementation through separate caller-owned descriptors. They
do not maintain parallel application-specific TLS connection logic; the
machine owner gate serializes their use of KDOS's shared TLS state.

The deterministic offline `tls-port` gate passes with cooperative callback
installation, exact phase progression, default-public address admission,
reviewed override and mutation hardening, cancellation across open phases,
trust drift and timeout handling, partial I/O and peer EOF, graceful close,
backpressure, half-close, deadline and notifier abort fallback, TCB-reuse
fingerprint-mismatch guarding, and context/owner release checks. It also
exercises the real lower ClientHello-preparation prefix and records guest
cycles. It has not yet measured the complete certificate-chain and
signature-verification work inside every live handshake phase, so
one-message-per-poll is not yet a demonstrated CPU ceiling for all cryptographic
leaves. Nor has a full live TAP connection or a Desk-hosted live journey been
established by that offline gate. Separately, `streams-live-public` passes its
focused real-TAP component journey; the Desk-hosted live responsiveness and
recovery journey remains pending.
