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
port NIO-CLOSE-START   ( -- io-status )
port NIO-CLOSE-POLL    ( -- io-status )
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
Cancellation is idempotent. It invokes the adapter's cancellation callback, or
the legacy `NIO-CLOSE-STATUS` path once when no callback is supplied. That
fallback does not drive asynchronous close polls and may enter the adapter's
blocking `NIO.CLOSE-XT` implementation.

Cancel and close attempts are tracked independently of the published open
state. A cancel callback and close-start callback are each invoked at most once
per lifecycle; close-poll is invoked once per caller poll while closing.
`NIO.CANCEL-ERROR` and `NIO.CLOSE-ERROR` retain thrown cleanup codes;
after closing has begun, `NIO-CLOSE-STATUS` reports its current status,
including `NIO-S-PENDING`. From `IDLE`, it is an active compatibility call: it
invokes `NIO.CLOSE-XT` once and publishes that result. `NIO-CLOSE` remains the
compatibility word that discards the result. An unresolved cleanup failure
blocks a new open so uncertain lower state cannot be erased. If a later cancel
callback proves detachment, repeated cancel remains successful and a new open
is allowed even when the earlier close exception remains available for
diagnosis; that open resets the completed lifecycle and its diagnostics.

`NIO-OPEN` remains the blocking compatibility entry for existing adapters.
When a port has no asynchronous start callback, `NIO-OPEN-START` invokes that
legacy entry once and returns its immediate result. New external transports
provide `NIO.OPEN-START-XT` and `NIO.OPEN-POLL-XT`; compatibility callers may
continue using a separate blocking `NIO.OPEN-XT`.

## Closing

The cooperative closing interface mirrors open:

```forth
port NIO-CLOSE-START  ( -- io-status )
port NIO-CLOSE-POLL   ( -- io-status )
port NIO-CANCEL       ( -- io-status )
```

Start returns an immediate terminal status or `NIO-S-PENDING`; callers retain
all transport-owned state while pending and advance it with close-poll. The
port records `IDLE`, `CLOSING`, `CLOSED`, `FAILED`, or `CANCELLED` in
`NIO.CLOSE-STATE`. Calling start again while closing is a status read, and
terminal start/poll calls are idempotent. When no asynchronous close callbacks
are installed, close-start uses the legacy `NIO.CLOSE-XT` path once.

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
