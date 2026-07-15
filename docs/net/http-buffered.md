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

`HBUF-START` begins transport opening and returns `HBUF-S-PENDING`. The exchange
may enter `HBUF-STATE-OPENING`; each `HBUF-POLL` then advances exactly one port
open step. No request byte is sent before the port reports `NIO-S-OK`, and the
poll that completes opening only changes the exchange to `SENDING`. Later polls
advance one partial request send or response receive/parser step.

Cancellation during opening, request sending, or response receiving uses
`NIO-CANCEL` before publishing `HBUF-STATE-CANCELLED`. Opening callback faults,
failed polls, parser failures, and transport failures take the same lower
cleanup path. Starting a second request while opening, sending, or receiving
returns `HBUF-S-BUSY`.

Lower cleanup is part of the result, not a best-effort side effect. The exchange
clears `HBUF.PORT` only after cancel or close succeeds. If a cleanup callback
throws, the exchange reports `HBUF-S-TRANSPORT`, remains in `ERROR`, and retains
the port descriptor so the caller cannot mistake an unreleased transport for a
clean reset. `HBUF-RESET` preserves that error and retained pointer rather than
silently starting another request over uncertain lower state.

On success, `HBUF.HTTP-CODE`, `HBUF.BODY-A`, and `HBUF.BODY-U` describe the
bounded response. A nonpersistent exchange closes the port before publishing
`DONE`. Persistent reuse is allowed only for the same still-open port, an
HTTP/1.1 response with reusable framing, and a request/response pair that does
not contain `close` as an exact comma-delimited `Connection` token.
Close-delimited response bodies are never reusable: EOF completes their body
and also proves that the peer connection is finished. Multiple response
`Connection` fields are closed conservatively instead of reusing a connection
after inspecting only the first field.

Run the deterministic opening and exchange contract with:

```sh
python local_testing/akashic_tui.py smoke --profile http-buffered
```
