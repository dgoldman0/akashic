# Buffered cooperative HTTP exchange

`akashic/net/http-buffered.f` combines a caller-owned `HTTP-REQUEST`, `NIO`
port, bounded response buffer, and incremental HTTP response parser. The
exchange owns parser and receive scratch only; request, transport, response
storage, cancellation authority, and semantic state remain with its caller.

```forth
body-a body-capacity exchange HBUF-INIT
request port exchange HBUF-START
exchange HBUF-POLL
exchange HBUF-CANCEL
exchange HBUF-RESET
```

For a new or non-reused port, `HBUF-START` invokes `NIO-OPEN-START`; an eligible
persistent reuse skips opening. An accepted start returns `HBUF-S-PENDING`. The
exchange may enter `HBUF-STATE-OPENING`; each `HBUF-POLL` then advances exactly
one port open step. No request byte is sent before the port reports
`NIO-S-OK`, and the poll that completes opening only changes the exchange to
`SENDING`. Later polls advance one partial request send or response
receive/parser step.

Cancellation during opening, request sending, response receiving, or closing
uses `NIO-CANCEL` before publishing `HBUF-STATE-CANCELLED`. Opening callback
faults, failed polls, parser failures, and transport failures take the same
lower cleanup path. Starting a second request while opening, sending,
receiving, or closing returns `HBUF-S-BUSY`.

Lower cleanup is part of the result, not a best-effort side effect. The exchange
clears `HBUF.PORT` only after close succeeds or cancellation proves detachment.
A close failure still reports `HBUF-S-TRANSPORT` and leaves the exchange in
`ERROR`, even when the subsequent cancel succeeds and permits the pointer to be
cleared. If cancellation cannot prove detachment, the exchange retains the port
so the caller cannot mistake uncertain lower state for a clean reset;
`HBUF-RESET` preserves that error and pointer rather than starting another
request over it.

`HBUF-RESET` is an abandonment boundary, not normal response completion. If a
port is still attached—including a reusable persistent connection—it uses
`NIO-CANCEL`, clears the pointer only after `NIO-S-CANCELLED`, and never starts
a new graceful close of its own. It makes one cancellation attempt. When the
adapter supplies a bounded cancellation callback, as KDOS does, this keeps the
void reset/rebind API bounded; a generic port without one can enter its legacy
blocking close fallback. Normal successful teardown remains in the polled close
state below.

On success, `HBUF.HTTP-CODE`, `HBUF.BODY-A`, and `HBUF.BODY-U` describe the
bounded response. A nonpersistent exchange calls `NIO-CLOSE-START`, retains the
port and enters `HBUF-STATE-CLOSING` while pending, and advances exactly one
`NIO-CLOSE-POLL` per exchange poll. It publishes `DONE` and clears the port only
after close reports `NIO-S-OK`. Persistent reuse is allowed only for the same
still-open port, an HTTP/1.1 response with reusable framing, and a
request/response pair that does
not contain `close` as an exact comma-delimited `Connection` token.
Close-delimited response bodies are never reusable: EOF completes their body
and also proves that the peer connection is finished. Multiple response
`Connection` fields are closed conservatively instead of reusing a connection
after inspecting only the first field.

`NIO-S-OK` is the adapter's terminal cleanup result. For the KDOS TLS adapter it
can mean either completed graceful teardown or a successful bounded abort
fallback; an abort that cannot prove local detachment remains a transport
failure and prevents `DONE`.

Run the deterministic opening and exchange contract with:

```sh
python local_testing/akashic_tui.py smoke --profile http-buffered
```
