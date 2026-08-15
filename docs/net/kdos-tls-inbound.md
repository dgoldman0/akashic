# Inbound KDOS TLS transport

`akashic/net/transports/kdos-tls-inbound.f` is the persistent Akashic owner
for one secure listener's cooperative accept lifecycle. It schedules the KDOS
TLS server substrate through `external-io.f` and returns an authenticated,
already-open instance of the shared `kdos-tls-port.f` NIO byte stream.

KDOS still owns the security boundary: exact TCP-child transfer, credential
authority and signing, ClientHello parsing, handshake construction, encrypted
record transport, client-Finished authentication, alerts, authenticated socket
publication, and exact lower teardown. Akashic owns request generations,
retry, deadline, cancellation, retained success, cleanup arbitration, and
publication of the final NIO port. A queued child is never exposed as a
plaintext application connection.

```forth
REQUIRE net/transports/kdos-tls-inbound.f
```

## Persistent owner

The caller supplies the canonical bound XIO service and the exact listener
triple returned by KDOS `TLS-LISTEN`:

```forth
xio-service listener-sd listener-h1 listener-generation
timeout-ms early-wire-budget owner KDOSTLSL-INIT
                                            ( -- status )
```

`owner` addresses `KDOSTLSL-SIZE` bytes of persistent writable storage. The
record contains only listener/accept composition state: listener identity,
handshake policy, owner/request generations, current exact raw TLS authority,
publication phase, terminal outcome, a borrowed shared-port pointer, a
transient socket-publication authority cell, and one embedded XIO operation.
It contains no established send, receive, poll, close, or quarantine engine.

`KDOSTLSL-INIT` requires core 0, the currently bound XIO service, positive
listener handle/generation and timeout values, a nonnegative early-data
budget, and disjoint nonwrapping service/owner spans. Reinitializing an idle
owner advances its generation. An active, retained, terminal, or
cleanup-pending owner returns `KDOSTLSL-S-BUSY` rather than erasing authority.

The XIO service is Akashic's canonical one-operation serializer. Multiple
persistent listener owners may reference it, but only one XIO request may be
active or retained at a time. That serialization ends when the handshake
request settles; an established connection never retains either XIO or the
global `KDOSNET` token.

## Accept lifecycle

Each request borrows a fresh initialized shared port:

```forth
shared-port KDOSTLSP-INIT                 ( -- port-status )
shared-port owner KDOSTLSL-ACCEPT         ( -- status )
owner KDOSTLSL-STEP                       ( -- nio-port|0 status )
```

`KDOSTLSL-ACCEPT` requires `shared-port` to be a valid
`KDOSTLSP-STATE-RESET` record whose span is disjoint from the owner and XIO
service. It reserves that record, advances the request generation, configures
the embedded XIO operation and cooperative cleanup poll, and submits it. The
caller retains the storage but must not call its NIO port while it is reserved
or published.

One public `KDOSTLSL-STEP` performs at most one XIO tick. One callback in turn
performs one bounded lower operation under an operation-scoped
`KDOSNET-WITH` claim. The lower sequence is:

1. one `TCP-POLL`, then exact `TLS-SERVER-ACCEPT-CLAIM`;
2. attached ClientHello ingress;
3. exact ServerHello and server-flight preparation;
4. ACK-paced server-flight transport;
5. attached client-flight ingress and Finished authentication;
6. terminal disposition/close when authentication fails, or authenticated
   socket publication when it succeeds.

`TLS-E-WOULD-BLOCK` from a transport phase selects a paired poll phase.
Ordinary lower lock contention retries the same phase without spinning or
polling. Empty backlog and pre-claim contention terminate the small request
with `KDOSTLSL-S-RETRY`, reset the borrowed port, and leave the persistent
owner ready for another `KDOSTLSL-ACCEPT`. The handshake deadline remains zero
while checking the listener and is armed only after an exact child is claimed.

Intermediate calls return `0 KDOSTLSL-S-PENDING`. A successful terminal call
returns `nio-port KDOSTLSL-S-OK`. The returned port is already open and the
listener owner is already idle; callers do not perform `XIO-TAKE`,
`XIO-RESET`, or a special follow-up tick.

The same owner accepts another connection by borrowing another fresh/reset
shared-port record. It never retains or reclaims a port already returned to an
HCONN or another application owner.

## Exact publication transfer

Authority moves through four explicit forms:

```text
generation-qualified raw server context
    -> durably staged authenticated KDOS socket
    -> inert PUBLISHED shared-port record
    -> adopted already-open shared NIO port
```

`TLS-SERVER-SOCKET-PUBLISH` transfers raw-context authority as soon as it
returns a nonzero socket descriptor. The listener owner records that descriptor
before calling `KDOSTLSP-PUBLISH` and clears the raw context immediately. A
contained throw or contradictory `(nonzero socket, nonzero ior)` tuple
therefore cannot lose the socket or abort a context whose authority has already
moved. Cleanup either recognizes that the shared port owns the exact staged
socket or retires the staging socket with `SOCK-TLS-ABORT-EXACT-TRY`.

On normal success XIO retains the exact shared-port pointer. The owner proves
the retained service topology, owner/request generations, result identity,
zero raw/staging authority, and `KDOSTLSP-STATE-PUBLISHED` socket before
calling `KDOSTLSP-ADOPT-OPEN`. Only after that local authority transfer commits
does it consume the retained result with exact `XIO-TAKE`. The adopted wipe
path performs no lower work and cannot fail, so an already-open port is not
hidden by transient XIO cleanup.

## Cancellation, timeout, and cleanup

```forth
owner KDOSTLSL-CANCEL                     ( -- status )
```

Cancellation marks or starts XIO termination and normally returns
`KDOSTLSL-S-PENDING`. Continue calling `KDOSTLSL-STEP` until it returns
`KDOSTLSL-S-CANCELLED`. Deadline expiry is driven the same way and returns
`KDOSTLSL-S-TIMED-OUT`. XIO's cancellation/deadline state remains the primary
terminal outcome; cleanup diagnostics are secondary and affect only a failed
operation.

The cancel callback only changes the owner to cleanup phase. Each cleanup poll
performs at most one exact action:

- release an unexpectedly retained `KDOSNET` claim;
- abort a generation-qualified raw context with `TLS-ABORT-EXACT`;
- retire a durably staged socket with `SOCK-TLS-ABORT-EXACT-TRY`; or
- drive `KDOSTLSP-DISCARD-STEP` until the borrowed port is reset.

Raw or staging retirement deliberately returns pending for one further tick so
the still-reserved port resets before XIO invokes its exact-once wipe. A
retained success cancelled before adoption enters XIO's pending-reset topology;
`KDOSTLSL-STEP` recognizes and pumps that topology rather than exposing reset
choreography. Uncertain lower retirement remains retained and retryable; the
owner never reports cleanup success while live authority may remain.

Early ClientHello or prepare-time policy rejection retains the positive wire
alert in the XIO result and reports a lower failure after exact abort. KDOS has
no early wire-alert sender, so Akashic does not synthesize one. Authenticated
client-flight terminal classes continue through the KDOS disposition and exact
close phases before failure publication.

## Established port and HCONN

The returned record is the same 288-byte `KDOSTLSP` implementation used by
outbound `kdos-tls.f`. All established TLS send, receive, poll, cancel,
graceful-close, abort fallback, error translation, deadline, quarantine, and
recovery behavior is documented in
[`kdos-tls-port.md`](kdos-tls-port.md). Inbound has no second implementation
of those operations.

The intended server composition is:

```text
KDOS secure listener
    -> persistent Akashic listener owner
    -> XIO-driven TLS accept request
    -> authenticated shared NIO port
    -> HCONN
```

Listener ownership and accept scheduling remain outside HCONN. HTTP parsing,
routing, and application code continue to consume an already-open NIO port and
require no TLS-specific branch.

HCONN terminal close proves that TLS and socket authority have been retired
after the TCP FIN is emitted. The unowned TCP terminal state still advances
through the ordinary machine network service; it is not retained by the NIO
port or listener for the connection lifetime. A cooperative server therefore
continues serialized network polling after HCONN becomes terminal. The real
vertical performs one `KDOSNET-WITH`-guarded `TCP-POLL` service operation per
completed connection, which consumes the independent peer's queued final ACK
and proves the child TCB reaches `CLOSED`.

When the listener owner is idle and no terminal result remains to be returned:

```forth
owner KDOSTLSL-FINI                       ( -- status )
```

`KDOSTLSL-FINI` wipes only the Akashic owner record. It returns
`KDOSTLSL-S-BUSY` while any request, retained result, cleanup, or borrowed port
is still live and never performs lower teardown itself.

## Real vertical qualification

`local_testing/test_kdos_tls_inbound_vertical.py` builds the modules from
source and drives two independent Python TLS 1.3 clients over emulated raw
Ethernet/TCP. Each client verifies the exact leaf certificate and `http/1.1`
ALPN, sends `GET /probe`, receives the HCONN response, exchanges TLS
close-notify and TCP FIN in both directions, and leaves no live socket, TLS
context, TCB, credential pin, or network/TLS lock. The second connection uses
the same secure listener and a fresh shared-port record.

```text
MEGAPAD_ROOT=/path/to/megapad-secure-server-transport \
  python3 -m unittest local_testing.test_kdos_tls_inbound_vertical
```
