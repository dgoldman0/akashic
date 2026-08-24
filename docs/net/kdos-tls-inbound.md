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

`local_testing/test_kdos_tls_inbound_failures.py` uses the same independent
wire peer and listener for the complementary recovery gate. It first proves
that cancellation before lower start returns the reserved port without
claiming a child. A withheld-ClientHello connection is then claimed and
cancelled while a foreign token blocks exactly one cleanup operation; the
exact context and child remain live during that contention tick and retire
after it clears. A second withheld ClientHello reaches a real 250 ms XIO
deadline. An empty TLS handshake record then produces the exact retained
`decode_error(50)` classification. Each claimed failure produces a
payload-free, sequence-exact TCP RST|ACK and leaves the persistent listener as
the only live lower resource.

Finally, a fresh Python TLS 1.3 client authenticates through that same
listener, and the returned shared NIO port receives `ping?`, sends `pong!`,
and completes bidirectional TLS/TCP shutdown. Any already-queued terminal TCP
acknowledgements are consumed by bounded, individually `KDOSNET-WITH`-guarded
service operations; no global network lease survives an operation. Teardown
then proves zero sockets, contexts, TCBs, credential pins, and network/TLS
locks. Both capstones share only fixture/image/emulator helpers and the raw
Python peer; the established TLS NIO implementation remains the production
shared port.

For current reruns, `MEGAPAD_ROOT` names the landed MegaPad `main` checkout at
documentation head `b399bd0`; executable evidence remains anchored at the
qualified `ca02a40` code ancestor.

```text
MEGAPAD_ROOT=/path/to/megapad \
  python3 -m unittest local_testing.test_kdos_tls_inbound_vertical
MEGAPAD_ROOT=/path/to/megapad \
  python3 -m unittest local_testing.test_kdos_tls_inbound_failures
```

The initial checked source runs at Akashic `af1fc81`, before retirement of the
temporary lower coordinator, completed in 1,169,609,877 guest steps (29.41 s)
for the two-client HCONN path and 951,435,597 guest steps (24.67 s) for
failure/recovery.

The original closure commit `386a8a5171390db5cdb4d436fc4d892a3ddc11ca`
reran that unchanged Akashic TLS code against MegaPad `c1d4f32`, where the
coordinator, listener lease cell, lock/scratch state, compatibility alias, and
redundant tests are absent. The two-client HCONN path passed in 1,119,547,893
guest steps (27.92 s), and failure/recovery passed in 905,769,707 steps
(23.14 s). The shared established-port, outbound, inbound, and HCONN source
profiles also passed in 724,722,756, 780,124,067, 780,424,304, and
1,043,866,636 steps respectively. All of those historical final runs used one
core, 128 MiB external memory, and the unchanged
1.5-billion-step/180-second capstone ceiling. They remain the pre-integration
secure-accept handback evidence rather than the current repository pair.

The integrated closure was requalified with executable Akashic code
`4b8680568a229b1bd114d3a05fa4e73f745157ab` against exact MegaPad code
`ca02a40c04840791c731dbb7c77ecd7e85eb4909`. The shared established-port and
inbound profiles passed at 736,487,794 and 791,511,814 guest steps. The
two-client listener/HCONN vertical passed at 1,126,636,722 steps (28.97 s), and
the cancellation/deadline/malformed-record recovery vertical passed at
915,416,913 steps (24.00 s). The outbound source profile remained 18/18 green
after packed `networking.f` shrank from 695,048 to 457,830 bytes in 10 chunks,
and the focused listener-owner terminal contract passed at 75,908 guest steps.
Later comment-only and documentation heads record that evidence but were not
substituted for the tested executable Akashic code checkpoint.

Immediately before the documentation-only landing record that contains this
disposition, local Akashic `main` had been fast-forwarded to A* closure head
`c69fbe57cb6169c80560033e94d3d9a640ad9def` and local MegaPad `main` to M*
closure head `a8cb7995363ebd5177e7e94375abd068e322329f`. Their cached
`origin/main` refs remained respectively
`d2e9551ffc37e324bb83acf51108f506599edfd5` and
`f4b8144786001e423291b9458f24e0efa7ab70ce`; neither landing had been pushed.
This disposition record descends from those closure heads but is documentation
only. It is not a newly tested code checkpoint: the executable evidence above
remains anchored at Akashic `4b8680568a229b1bd114d3a05fa4e73f745157ab`
against MegaPad `ca02a40c04840791c731dbb7c77ecd7e85eb4909`.
