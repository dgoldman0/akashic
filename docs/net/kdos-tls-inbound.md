# Inbound KDOS TLS transport

`akashic/net/transports/kdos-tls-inbound.f` composes KDOS's nonblocking TLS
server substrate under Akashic's `external-io` lifecycle. KDOS still owns TCP
child transfer, credential pins, ClientHello parsing, signing and flight
construction, encrypted records, Finished authentication, alert disposition,
socket publication, and exact teardown. Akashic chooses one lower operation on
each cooperative step and publishes only an authenticated `NIO` byte stream.

```forth
REQUIRE net/transports/kdos-tls-inbound.f
```

## Lower boundary

The adapter consumes the exact listener authority assembled by the listener
owner: its configured secure-listener socket descriptor plus the opaque handle
and generation returned by `TLS-LISTEN`:

```text
( configured-listener-sd listener-h1 listener-generation )
```

Its first XIO tick claims the caller's accepted-result record as the machine
`KDOSNET` token and performs one `TCP-POLL`. Its next tick invokes
`TLS-SERVER-ACCEPT-CLAIM`. That lower transaction either returns no authority
with retryable `TLS-E-WOULD-BLOCK`/`TLS-E-BUSY`, or transfers one queued child
directly into an exact `(context, generation)` TLS server authority. It never
publishes an accepted plaintext socket.

After a successful claim, the adapter invokes only these KDOS server entries:

- `TLS-SERVER-CLIENT-HELLO-STEP`
- `TLS-SERVER-PREPARE-HELLO-EXACT`
- `TLS-SERVER-PREPARE-FLIGHT-EXACT`
- `TLS-SERVER-FLIGHT-STEP`
- `TLS-SERVER-CLIENT-FLIGHT-BEGIN-ATTACHED`
- `TLS-SERVER-CLIENT-FLIGHT-STEP`
- `TLS-SERVER-INGRESS-DISPOSITION-STEP`
- `TLS-SERVER-CLOSE-EXACT-TRY`
- `TLS-SERVER-SOCKET-PUBLISH`
- `TLS-SERVER-ABORT-EXACT` during cleanup

`TLS-E-WOULD-BLOCK` changes the descriptor to a paired poll phase. The next
XIO tick performs exactly one `TCP-POLL`, then restores the interrupted TLS
phase. Ordinary lower lock contention retries the same phase without polling.
No adapter callback idles or spins.

The handshake deadline is deliberately zero while checking an empty listener.
It is armed from the configured timeout only after an exact child has been
claimed. Empty backlog and lower contention therefore finish as small,
retryable XIO failures instead of retaining the one serialized operation.
`KDOSTLSA-RETRY?` classifies those completed failures.

## Caller-owned records

The accept descriptor is 80 bytes (`KDOSTLSA-SIZE`). It carries only the exact
listener triple, handshake timeout, early-data wire budget, result pointer,
current exact TLS context, and current phase.

The accepted-result record is 184 bytes (`KDOSTLSP-SIZE`). Its first 144 bytes
are an embedded `NET-IO-PORT-SIZE` port; the remaining cells hold publication,
socket, and cleanup state. The result address—not the accept descriptor or XIO
operation—is the exact `KDOSNET` ownership token. That stable token remains the
same across accept, `TAKE`, HCONN use, and NIO close.

Initialize and configure caller-owned storage before submission:

```forth
result  KDOSTLSP-INIT       ( -- KDOSTLSA-S-OK )
adapter KDOSTLSA-INIT       ( -- KDOSTLSA-S-OK )

listener-sd listener-h1 listener-gen
timeout-ms early-wire-budget result adapter KDOSTLSA-CONFIGURE
```

The adapter and result must be nonwrapping, disjoint spans. Submission also
requires the XIO service and operation spans to be disjoint from both records.
These checks use `memory-span.f`; the module has no second alias-set system.

The service, operation, adapter, and result are persistent service-owned
storage. They must not be allocated in an applet child or otherwise reclaimed
while an operation or its cooperative cleanup may still be pending. The
listener owner must settle every submitted operation before Desk tears down
that storage. This is the current vertical's safe composition boundary.

Submit through the already-bound XIO service:

```forth
service owner-id owner-generation request-generation operation adapter
KDOSTLSA-SUBMIT                         ( -- xio-status )
```

`KDOSTLSA-SUBMIT` installs the ordinary start/poll/cancel/wipe callbacks and
opts the request into XIO cooperative terminal cleanup. XIO supplies request
generation matching, one-operation serialization, deadlines, cancellation,
callback containment, retained success, and terminal publication.

## Success and retained ownership

Successful Finished authentication is followed by the atomic KDOS socket
publication step. The operation becomes retained `XIO-STATE-SUCCEEDED`, and
`XIOO.RESULT` is the exact accepted-result address. Adopt it with:

```forth
service owner-id owner-generation request-generation operation adapter
KDOSTLSA-TAKE                            ( -- port|0 status )
```

`TAKE` verifies the retained operation/adapter association, result identity,
the live owner/request generations, publication state, and KDOS network
ownership. A relaunched owner or replaced request therefore cannot adopt a
stale accepted socket. `TAKE` calls callback-free `NIO-OPEN` on the embedded
port and returns that already-open port. All embedded-port callbacks reject
before `TAKE`; adoption reinitializes its NIO bookkeeping after proving the
exact retained authority, so premature wrapper calls cannot pump transport,
retire XIO-owned authority, or poison the eventual port. `TAKE` does not reset
XIO; the owner must then call `XIO-RESET`. That call returns `XIO-S-PENDING`;
one subsequent owner `XIO-TICK` runs the configured cleanup poll, which returns
immediate success after TAKE and leaves the result record—not XIO—in control
of the KDOS token. The owner must observe `XIO-STATE-RESET` before reusing its
service storage.

Resetting a retained success without TAKE is the discard operation. XIO drives
the same cleanup poll until the published TLS socket has been exactly aborted,
then releases KDOSNET and clears the operation. No one-shot wipe or caller
discard protocol is involved.

## Failure, cancellation, and terminal alerts

Malformed ClientHello or prepare-time peer policy errors retain their positive
wire alert in `XIOO.RESULT` and fail with
`KDOSTLSA-E-HANDSHAKE-ALERT`. This matches the frozen KDOS coordinator's early
disposition: it latches and returns the alert but does not emit it. KDOS has no
public early-alert transport step, so Akashic does not synthesize one; XIO
retires that exact context by abort. Authenticated client-flight terminal
classes latch their lower authentication error in `KDOSTLSP.LAST-ERROR`, and
normally mirror it in `XIOO.ERROR`; their alert description is in
`XIOO.RESULT`. Those protected post-flight cases do continue through
`TLS-SERVER-INGRESS-DISPOSITION-STEP` and exact terminal close before
publishing failure. If disposition or close cannot finish, XIO cleanup
switches to exact abort. XIO cancellation or deadline expiry remains the
terminal operation cause and may replace `XIOO.ERROR`, while the result latch
preserves the underlying authentication diagnostic until the result is next
initialized or reserved.

For all failure, explicit cancellation, timeout, post-callback cancellation,
and discarded-success paths, the XIO cancel callback only marks cleanup. Each
cleanup poll attempts at most one exact context or socket retirement. KDOSNET
is released only after retirement is proven. The wipe callback performs no
lower operation and refuses to erase live authority. A contradictory lower
publication tuple with both a nonzero socket and an error is treated as
potentially published: the socket is retained and aborted through that same
cleanup path instead of falling back to possibly transferred raw-context
authority.

## NIO port behavior

The accepted NIO port delegates application records to KDOS `SEND` and `RECV`
and pumps one `TCP-POLL` per `NIO-POLL`. A zero receive is interpreted with
`SOCK-TLS-IO-STATUS` and `SOCKET-READY?`: authenticated close becomes
`NIO-S-EOF`, lock contention/backpressure remains zero `NIO-S-OK`, and sticky
TLS failure becomes `NIO-S-FAILED`. Send and receive buffers must be
nonwrapping and disjoint from the accepted-result record; those checks also
use `memory-span.f`.

`NIO-CLOSE-START` and `NIO-CLOSE-POLL` alternate one `CLOSE-TRY` with one
transport poll until TLS close-notify/TCP retirement completes. A terminal
graceful-close fault changes to a cooperative socket-abort phase and reports
failure only after detachment. The result releases its KDOSNET token at that
point and may be reused with `KDOSTLSP-RESET`. A clean `NIO-CANCEL` likewise
publishes a resettable cancelled result after abort and token release.

Because `io-port.f` contains callback exceptions, the adapter first translates
every lower send, receive, status, poll, close, and abort throw into durable
result state. Data and graceful-close throws enter cooperative abort; an abort
or one-shot cancellation throw enters quarantine. Thus callback containment
cannot leave an apparently terminal NIO object hiding an unrecoverable live
socket or KDOSNET token.

NIO cancellation and the legacy noncooperative close entry have pre-existing
one-shot callback contracts. If one call cannot prove retirement, the result
is deliberately quarantined and retains KDOSNET. `KDOSTLSP-RECOVER-STEP` is
the narrow diagnostic recovery entry for that port-level limitation. Normal
HCONN shutdown uses the cooperative close pair, and normal XIO accept cleanup
never enters this quarantine path.

The intended server composition is:

```text
KDOS secure listener
    -> XIO-driven TLS accept
    -> authenticated, already-open NIO port
    -> HCONN
```

Listener ownership and accept scheduling stay outside HCONN, so HTTP parser,
router, and application code require no TLS-specific changes.
