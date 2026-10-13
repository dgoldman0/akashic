# Buffered cooperative HTTP exchange

`akashic/net/http-buffered.f` combines a caller-owned `HTTP-REQUEST`, `NIO`
port, bounded response buffer, and incremental HTTP response parser. The
exchange owns parser and receive scratch and an inflater record only; request,
transport, response storage, cancellation authority, and semantic state remain
with its caller.

```forth
body-a body-capacity exchange HBUF-INIT
flag exchange HBUF-GZIP!
request port exchange HBUF-START
exchange HBUF-POLL
exchange HBUF-CANCEL
exchange HBUF-RESET
```

## Gzip bodies

After `HBUF-INIT`, `-1 exchange HBUF-GZIP!` asks the exchange to inflate gzip
bodies; the flag lasts through `HBUF-RESET` and persistent reuse, until the next
`HBUF-INIT`. The caller still sends its own `Accept-Encoding: gzip` and admits
the response's `Content-Encoding` itself.

A response whose one `Content-Encoding` field is `gzip` or `x-gzip`, in any
case, is inflated into the response buffer as it arrives, whatever its framing
and however the port splits it. The buffer is the [inflater's](../utils/inflate.md)
window, so a gzip body costs the exchange's 3,024-byte inflater record and no
other memory. `HBUF-CODING@` then answers `HBUF-C-GZIP`, and `HBUF.BODY-U` is
the inflated length. Any other coding, two `Content-Encoding` fields, or a
body the caller did not ask to inflate is kept as it came, `HBUF-C-IDENTITY`,
for the caller to admit or refuse.

The body as sent and the body as inflated each count against the buffer's
capacity, so a small body cannot inflate past it and a body cannot be sent
endlessly. The body must be exactly one whole gzip member. A body of no bytes,
such as a `204` or `HEAD` response's, is empty. Otherwise the exchange fails
with `HBUF-S-PROTOCOL`, cancels its port, and `HBUF-BODY-STATUS@` says why:

| Status | Meaning |
|---|---|
| `HBUF-B-CAPACITY` | The body, as sent or as inflated, passed the buffer. |
| `HBUF-B-DAMAGED` | The inflater refused the member; `exchange HBUF.INFL INFL-REASON@` says why. |
| `HBUF-B-TRAILING` | Bytes followed the member, such as a second member. |
| `HBUF-B-CUT` | The body ended inside the member. |

An uncompressed body past the buffer also reports `HBUF-B-CAPACITY` when the
parser's own body limit has not refused it first. Each message starts with
`HBUF-B-OK`, `HBUF-C-IDENTITY` and a wiped inflater record.

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

and the gzip bodies, against Python's gzip, with:

```sh
python -m pytest local_testing/test_http_gzip.py
```
