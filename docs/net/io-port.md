# Cooperative byte-stream port

`akashic/net/io-port.f` is the injected transport boundary used by Akashic HTTP
clients. A port contains caller-supplied context plus open, send, receive, poll,
cancel, and close callbacks. It owns no socket, TLS state, request, parser,
credential, or application state.

Send and receive preserve partial progress:

```forth
buffer length port NIO-SEND       ( -- count io-status )
buffer capacity port NIO-RECV     ( -- count io-status )
port NIO-POLL
port NIO-CLOSE
port NIO-CLOSE-STATUS  ( -- io-status )
```

`NIO-S-OK` with a zero count means backpressure or no readable bytes, not EOF.
`NIO-S-EOF`, `NIO-S-FAILED`, and `NIO-S-CANCELLED` are distinct outcomes.
Callback throws and impossible counts are normalized by the public wrappers.

## Opening

The cooperative opening interface is:

```forth
port NIO-OPEN-START  ( -- io-status )
port NIO-OPEN-POLL   ( -- io-status )
port NIO-CANCEL      ( -- io-status )
```

Start and poll return `NIO-S-PENDING`, `NIO-S-OK`, `NIO-S-FAILED`, or
`NIO-S-CANCELLED`. The port records `CLOSED`, `OPENING`, `OPEN`, `FAILED`, or
`CANCELLED` in `NIO.OPEN-STATE`. Calling start again while opening is a harmless
status read; calling poll after opening succeeds likewise returns `NIO-S-OK`.
Cancellation is idempotent and invokes the adapter's cancellation callback, or
falls back to close when none is supplied.

Cancel and close attempts are tracked independently of the published open
state and each lower callback is invoked at most once per open lifecycle.
`NIO.CANCEL-ERROR` and `NIO.CLOSE-ERROR` retain thrown cleanup codes;
`NIO-CLOSE-STATUS` reports a truthful `OK` or `FAILED` while `NIO-CLOSE` remains
the compatibility word that discards that result. A failed cleanup blocks a
new open on the descriptor so uncertain lower state cannot be erased; only
explicit `NIO-INIT` or a new descriptor starts a fresh lifecycle.

`NIO-OPEN` remains the blocking compatibility entry for existing adapters.
When a port has no asynchronous start callback, `NIO-OPEN-START` invokes that
legacy entry once and returns its immediate result. New external transports
provide `NIO.OPEN-START-XT` and `NIO.OPEN-POLL-XT`; compatibility callers may
continue using a separate blocking `NIO.OPEN-XT`.

Port callback dispatch is stack-framed and contains callback throws. Nested
operations on a different descriptor cannot overwrite an outer callback's
port, execution token, result, or cleanup state. Live machine transports still
run through the single owner-pumped external-I/O service because KDOS networking
and TLS own shared core-0 platform state; that platform ownership constraint is
separate from the port wrapper. A port descriptor is not by itself a scheduler,
authority grant, or concurrency claim.

Run the deterministic port contract with:

```sh
python local_testing/akashic_tui.py smoke --profile io-port
```
