# Outbound KDOS TLS Transport

`akashic/net/transports/kdos-tls.f` is the outbound connector for Akashic's
KDOS TLS byte stream. It owns DNS, address admission, ARP, TCP active open, and
the client side of the TLS 1.3 handshake. Once peer authentication succeeds,
it publishes the lower KDOS TLS socket into the common established adapter in
[`kdos-tls-port.f`](kdos-tls-port.md). Inbound and outbound connections use
that same post-authentication NIO implementation.

```forth
REQUIRE net/transports/kdos-tls.f
```

## Lifecycle

```forth
CREATE transport KDOSTLS-SIZE ALLOT

transport KDOSTLS-INIT
S" example.com" 443 transport KDOSTLS-CONFIGURE THROW

\ Optional only for a separately reviewed policy. The default is public IPv4.
policy-context ['] my-address-policy transport KDOSTLS-ADDRESS-POLICY! THROW

transport KDOSTLS.PORT NIO-OPEN-START
\ Poll NIO-OPEN-POLL until it returns a terminal status.
\ After success, use the same port with HREQ, HSTR, or another NIO consumer.

transport KDOSTLS.PORT NIO-CLOSE-START
\ Poll NIO-CLOSE-POLL until it returns a terminal status.
```

`KDOSTLS-CONFIGURE` copies one validated DNS hostname of at most 253 bytes and
accepts a remote port from 1 through 65535. Configuration and lifecycle
mutation are core-0-only. `KDOSTLS-NEW` and `KDOSTLS-FREE` provide optional
heap ownership; embedded callers use `KDOSTLS-INIT`.

The established port occupies the descriptor prefix. The connector installs
opening callbacks over that prefix while the connection is being prepared.
After lower socket publication, `KDOSTLSP-ACTIVATE` replaces data, polling,
close, and cancellation callbacks with the common established implementation
without disturbing NIO's in-progress open result. Public
`KDOSTLS.STATE`, `KDOSTLS.ABORT-STATUS`, and
`KDOSTLS.CLOSE-FALLBACKS` are aliases of the common port diagnostics rather
than a second lifecycle implementation.

## Cooperative opening

One `NIO-OPEN-POLL` advances at most one connector phase:

1. allocate a generation-qualified client TLS context and construct ClientHello;
2. resolve and admit DNS and ARP state;
3. create and exactly attach the outbound TCP TCB;
4. emit ClientHello and incrementally authenticate the server flight;
5. construct and exactly admit client Finished;
6. publish the authenticated TLS context as a KDOS TLS socket; and
7. stage and activate that socket in the shared NIO port.

The connector has a 15-second deadline and records per-step and maximum guest
cycle counts. A changed trust generation, invalid lower authority, callback
exception, cancellation, or deadline failure enters exact cleanup before a
terminal result is returned.

KDOS still has machine-global client-handshake transcript, reassembly, SNI,
and cryptographic scratch. Therefore one outbound opening operation retains a
`KDOSNET` lease across its cooperative polls. This is a temporary lower
constraint, not established-connection ownership. The lease is released after
the lower socket is durably staged and before the shared port becomes
callable.

Established send, receive, readiness, poll, graceful close, cancellation,
abort fallback, and recovery acquire `KDOSNET` only for one lower operation.
An open connection does not exclude a second connector or another established
peer for its lifetime.

## Authenticated publication

The publication seam carries exact context and TCB generations until KDOS has
created the reciprocal socket/context edge. It then proceeds in this order:

```text
raw authenticated context
  -> exact private TLS socket claim
  -> retryable reciprocal KDOS publication
  -> inert KDOSTLSP publication
  -> release outbound KDOSNET lease
  -> shared-port activation
```

`SOCK-TLS-PUBLISH-TRY` and `SOCK-CONNECT-ROLLBACK-TRY` make NET contention a
cooperative retry. The connector retains the exact original socket state and
replays that value during rollback; it does not reconstruct the state from a
boolean. A local catch/finally pairs every successful outer TLS-owner claim
with one release. It also unwinds the nested owner depth used by
`TLS-HANDSHAKE-PUBLISH` if that lower public entry throws before its normal
return helper.

The shared port remains inert while publication is incomplete. Raw context
authority is cleared only after the exact socket has been accepted by
`KDOSTLSP-PUBLISH`. A transient activation conflict leaves the published port
retryable without reacquiring the opening lease.

## Cancellation and cleanup

Before lower socket publication, failure and cancellation use
`TLS-ABORT-EXACT` with the retained context generation. Any private unbound
socket is rolled back with its exact saved state and retired with
`SOCK-TLS-ABORT-EXACT-TRY`. After socket publication, cleanup transfers the
descriptor into the shared port and drives `KDOSTLSP-DISCARD-STEP`.

Busy cleanup remains pending. A terminal result is not published until exact
lower retirement and exact `KDOSNET` release are both proven. Foreign owner
tokens are never released, and uncertain authority is retained as cleanup
failure rather than erased by reinitialization.

After activation, the common port owns graceful TLS close, deadline fallback,
abort, quarantine, and recovery. The outbound connector has no separate
established close state machine.

## Resolved-address admission

Every native open copies the selected IPv4 address into descriptor-owned
storage and advances through a distinct admission phase before remote ARP or
TCP. The default `PUBLIC-IPV4?` policy rejects unspecified, private, shared,
loopback, link-local, protocol-assignment, documentation, benchmarking,
multicast, and reserved destinations.

`KDOSTLS-ADDRESS-POLICY!` has stack effect
`( context xt adapter -- status )`; its callback has stack effect
`( ipv4-a context -- admitted? )`. It can be replaced only while closed. The
callback receives a shadow copy, and mutation of that shadow causes admission
to fail, so an accepted address cannot be redirected after review.

## Diagnostics and qualification

Opening diagnostics include `KDOSTLS.PHASE`, `KDOSTLS.LAST-ERROR`,
`KDOSTLS.NATIVE-ERROR`, `KDOSTLS.CLEANUP-ERROR`,
`KDOSTLS.CTX-GENERATION`, `KDOSTLS.TCB-GENERATION`, step count, and cycle
fields. Common established diagnostics remain available through the outbound
aliases described above or directly through `KDOSTLSP.*`.

The source-mode `tls-port` profile covers configuration, public-address
admission, start contention, cancellation, timeout, trust drift, callback
faults, retryable exact socket publication, two live established sockets with
no lifetime owner, nested TLS-owner exception unwinding, exact private-socket
rollback, complete lower retirement, and the real ClientHello-preparation
prefix. Established byte-stream behavior is qualified independently by the
`tls-established-port` profile so it is not duplicated here.
