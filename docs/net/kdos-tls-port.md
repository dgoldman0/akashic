# Shared KDOS TLS port

`akashic/net/transports/kdos-tls-port.f` is the canonical Akashic NIO
adapter for an already-authenticated KDOS TLS socket. It is shared by the
outbound connector and the inbound listener/accept owner. DNS, TCP opening,
TLS handshake scheduling, listener policy, and XIO request ownership do not
belong to this record.

The caller provides `KDOSTLSP-SIZE` bytes. A producer initializes and reserves
the record before beginning a handshake:

```forth
established KDOSTLSP-INIT
established KDOSTLSP-RESERVE
```

After KDOS has atomically published an authenticated TLS `/SOCK` descriptor,
the producer stages that descriptor with:

```forth
socket-sd established KDOSTLSP-PUBLISH
```

`PUBLISH` transfers the lower socket authority into the record but deliberately
leaves its NIO callbacks application-inert. This gives XIO cancellation and
deadline precedence a safe post-callback cleanup point. While exact XIO success
is still retained, an inbound owner calls `KDOSTLSP-ADOPT-OPEN` to commit the
external authority transfer and then consumes that same result with `XIO-TAKE`.
The outbound connector uses `KDOSTLSP-ACTIVATE` before its existing NIO open
callback publishes success.

The active `KDOSTLSP.PORT` implements the ordinary NIO byte-stream contract:
cooperative send, receive, polling, cancellation, graceful close, deadline
fallback to `SOCK-ABORT`, and quarantined recovery. A producer that does not
commit a staged socket repeatedly calls `KDOSTLSP-DISCARD-STEP`; a quarantined
record is settled only through `KDOSTLSP-RECOVER-STEP`.

## Ownership

The record address is its opaque KDOS network-owner token. Every established
lower operation runs through `KDOSNET-WITH`, which claims and exactly releases
that token around one logical operation. Send plus status, receive plus
status/readiness, one poll, one close attempt, or one abort attempt are each a
single guarded scope. No established callback returns while retaining
`KDOSNET`.

Ordinary owner contention is cooperative backpressure: send and receive return
zero progress, poll is a no-op, and close/discard/recovery remains pending.
Callback exceptions and exact-release failures remain separate diagnostics.
Uncertain retirement retains the socket in `KDOSTLSP-STATE-QUARANTINED`; the
adapter never clears live authority merely to make the wrapper reusable.

The temporary outbound exception is handshake setup, not established I/O.
The outbound connector retains an explicit KDOSNET lease across open polls
while KDOS client-handshake transcript and reassembly scratch remain global.
It releases that lease before the shared port becomes active.

## Lifecycle invariants

- `RESERVED` has no socket authority.
- `PUBLISHED` has one authenticated socket but an inert NIO port.
- `OPEN` has one callable NIO port and no retained KDOSNET lease.
- A successful `CLOSE-TRY` or `SOCK-ABORT` proves lower retirement before the
  descriptor is cleared.
- Contention never converts a healthy connection into a terminal error.
- A release failure never overwrites the primary lower error and never removes
  a foreign owner.
- Reset is permitted only after lower authority has been proven absent.

The lower callback fields exist for deterministic qualification. Production
initialization installs the KDOS `/SOCK` implementations and a monotonic clock.
