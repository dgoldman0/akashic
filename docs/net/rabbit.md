# Rabbit transport-neutral foundation

Akashic implements a deliberately strict, provisional `RABBIT/1.0` profile.
The profile is pinned to `dgoldman0/Rabbit` commit
`c79f25697868645d958d2a43aec1c2e4f566585a`; it does not claim complete Rabbit
conformance. The frame, lane, session, and protocol sources in the developer's
current `47cb7261a92fb6c415c035a772b1c2bc29a52b7c` checkout are byte-identical to
that pin.

## Layer and ownership boundary

`net/rabbit` owns the portable wire, message, session, connection, client,
subscription, routing, and server mechanics. It knows nothing
about Desk, Streams, Worlds, Practice, Library, Agent, TLS implementations, or
socket devices. Streams will operate configured Rabbit instances for applets
and own application-profile adapters, semantic caches, durable attempts,
Practice integration, and visible delivery truth. It does not own generic
Rabbit pumping, transaction correlation, subscription/replay state, selector
routing, or server-peer dispatch. Worlds remains Rabbit-free.

Rabbit uses the existing `net/io-port.f` cooperative byte-stream interface.
There is intentionally no second Rabbit transport abstraction. The deterministic
fixture binds two caller-owned rings to two ordinary `NET-IO-PORT` records
through `net/transports/memory-duplex.f`, which is itself protocol-neutral.
Shared wire-scalar bounds and capability bits live in `net/rabbit/profile.f`,
below both message construction and the NIO-owning session layer.

## Supported frame profile

The admitted grammar is:

```text
<nonempty start line> CRLF
*(<nonempty name>: SP <value> CRLF)
End: CRLF
[exactly Length octets]
```

- Start lines, headers, and bodies are strict UTF-8 in this profile.
- CRLF is mandatory. Bare LF and bare CR are malformed.
- Header names and values are separated by exactly one ASCII space, matching
  the pinned `Key: Value` grammar. Empty values are encoded as `Key: `.
- `End:` is recognized only as an exact header-block line. Its bytes inside a
  length-bounded body have no framing meaning.
- A body requires exactly one strict unsigned-ASCII-decimal `Length` header.
  Absent `Length` means a zero-byte body.
- Length is checked for numeric overflow and against the caller's frame arena
  before body bytes are accepted.
- Duplicate core singleton headers are rejected. Unknown headers and verbs are
  retained structurally so the frame layer does not freeze the protocol.
- `Transfer: chunked` and `Part` are parsed as unsupported rather than
  half-implemented. The specification describes chunking while also listing it
  as post-MVP, and the reference multipart splitter can divide a UTF-8 codepoint.
- Encoding measures and validates the complete frame before writing. Invalid
  input or insufficient output capacity writes zero bytes.

The incremental parser consumes at most one frame per call sequence. `FEED`
returns the exact number of source bytes consumed and stops at `READY`, so a
caller can retain and feed the unconsumed suffix containing another frame.
Published start/header/body slices are borrowed from the caller's parser arena
and remain valid only until reset or teardown.

Parser and frame descriptor storage is caller-allocated but opaque. Callers
choose its capacity and lifetime, but must not mutate descriptor cells between
initialization and reset. Validation defends the public API and ordinary
geometry; it is not a memory-corruption recovery boundary.

No product body, header, or frame limit is embedded in the module. The caller's
arena is the bound and capacity failure is explicit.

## Typed message profile

`net/rabbit/message.f` is a state-free semantic layer over a READY frame. It
does not retain a second descriptor: typed header and body accessors borrow the
frame's arena and expire when that frame is reset. This prevents a connection
from accidentally retaining an undetectably stale parser view. An outbound
connection must encode into its own caller-provided queue slot before returning
from enqueue.

Known request verbs require a nonempty target plus exact `Lane` and `Txn`.
`EVENT` requires distinct nonzero `Seq` and `Event-Seq`; `ACK` and `CREDIT`
target an exact lane and carry their one matching positive scalar. PING is
canonicalized to control Lane 0. Response tokens are exactly three decimal
digits in the 100–599 range, while unknown textual verbs remain structurally
admissible for a generic router to reject or extend. Core unsigned values use
canonical decimal spelling, so leading zeroes are refused except for zero
itself. This provisional profile interprets `Since` as a nonzero u64
`Event-Seq` cursor; the reference specification's timestamp example and the
implementation's integer parser disagree and cannot both be honored silently.
`AUTH` is recognized for routing but semantic admission returns unsupported
until the channel-binding, mutual-proof, and selected PQ profile exist. Numeric
responses remain generic at this layer; the connection/client context must
validate exact `200 PONG`, handshake, and `(Lane, Txn)` response shapes.

## Typed outbound construction

`net/rabbit/builder.f` supplies the construction side of that ownership
boundary. Its opaque, caller-sized descriptor embeds an outbound frame, while
a separate caller-provided byte arena owns copies of the start line, every
header name and value, and the body. A successful constructor therefore keeps
no application slice alive. Connections can encode synchronously into their
own queue slots and immediately reset or reuse the application builder.
From successful initialization until finalization, the builder has exclusive
mutation rights over its opaque descriptor. During construction and while
READY it also has exclusive rights over the entire byte arena; reset wipes and
releases the live content without unbinding that arena. The caller may mutate
the original source slices because they were copied, but must not mutate
builder-owned bytes.

Header count and byte capacity remain caller choices. Construction failures
latch an error, reset the embedded frame, and wipe the bytes copied by the
failed operation; explicit reset wipes all bytes used by the preceding
successful construction. Seal performs both frame validation and typed message
admission and refuses a result whose admitted kind differs from its constructor.
Encoding is all-or-nothing and rejects output that overlaps either the opaque
descriptor or its arena.

An owning connection may borrow the builder's immutable READY frame only for
the duration of synchronous enqueue, allowing it to verify exact Lane, Seq,
Credit, and Txn facts before it copies the encoded bytes and commits session
state. Reset or finalization immediately expires that inspection view.

The typed surface covers the admitted HELLO, request, EVENT, ACK, CREDIT,
PING/PONG, correlated application responses, explicitly named uncorrelated
control responses, and their headers. It also covers `Since`, `Event-Seq`,
`Idem`, `View`, `Accept-View`, `Timeout`, `Burrow-ID`, QoS, extension headers,
and length-coupled bodies. HELLO capability flags and the anonymous
`Burrow-ID` round-trip through typed message accessors for connection/session
negotiation. Scalar output spans the full canonical u64 decimal range. AUTH
construction remains unavailable for the same security reason that AUTH
admission remains unsupported.

Frame, message, and builder operations still use private module scratch. Their
persistent records and byte ownership are caller-local, but calls through these
three modules must currently remain synchronous and serialized. Independent
connections on separate cores are not yet a supported concurrency claim; the
scratch must move into caller-owned connection workspaces before making one.

## Connection and route ownership

`net/rabbit/connection.f` is the persistent cooperative owner above one
session, one incremental parser, and its injected NIO port. The caller chooses
and supplies the receive carry buffer plus separate control and data queues.
Each queue has caller-owned slot metadata and uniform byte slots; one control
slot is the protocol progress minimum, while a zero-slot data queue is valid.
There is no hidden allocation, default depth, or product frame limit.

Enqueue first measures and encodes a READY builder into an unpublished byte
slot. Only then does it reserve an exact EVENT sequence, record a CREDIT grant,
or begin the client HELLO transition before infallibly publishing the slot.
Application builders may be reset immediately. Fully transmitted EVENT bytes
remain in their slot until a valid cumulative ACK releases them, so queue
capacity models a genuinely slow peer rather than merely a slow local write.
Other complete frames are wiped immediately.

The send pump never switches frames after a short write. Control traffic wins
only at a frame boundary, preventing both control starvation and byte-stream
interleaving. Attempt count, confirmed offset, frame identity, and cumulative
confirmed wire bytes remain inspectable after failure. Receive owns one stable
READY parser view at a time; a distinct carry buffer retains any coalesced
suffix until the caller commits or drops the loan. Commit alone applies
handshake, EVENT, ACK, and CREDIT session mutation. Close and cancel invalidate
loans and wipe queued/parser/carry bytes before delegating transport teardown.

The pinned ACK, CREDIT, and PING shapes forbid a control `Seq`, so the current
connection records their order only through its control queue. The session's
read-only/exact control ordinal seam remains available for a future wire
profile that actually emits such a field; this implementation does not invent
an unobservable ordinal and call it interoperability evidence.

`net/rabbit/router.f` separately owns an exact copied `(verb, selector)` table.
It never invokes handlers: sealed lookup returns a borrowed handler token and
opaque context for the generic server owner. Entry count and arena size are
caller choices, including a canonical empty deny-all router. Finalization can
recover from damaged route content when the original binding geometry remains
valid, but—as with the other opaque records—caller forgery of stored binding
pointers is outside the memory-safety contract without an external ownership
witness.

## Lane and transaction profile

- Lane identifiers are decimal unsigned 16-bit values. Lane 0 is control.
- Application lanes start with two distinct zero counters. Send credit records
  peer grants received by this endpoint; receive credit records grants this
  endpoint has successfully staged for the peer. ACK never changes either.
- A connection encodes CREDIT into an unpublished owning slot, records the
  receive grant, and only then publishes that slot. If grant recording refuses,
  it discards the staged bytes. A failed encode therefore cannot authorize an
  inbound delivery that the peer was never actually granted.
- Lane `Seq` starts at 1, admits the complete unsigned 64-bit range, and is
  independent for each lane. After `2^64-1`, the lane is terminally exhausted
  rather than wrapping to zero. It is transport ordering, never a World or
  topic `Event-Seq`.
- Outbound inspection and exact reservation are separate. A connection reads
  the next admissible `Seq`, encodes it into its owning queue slot, then commits
  that exact sequence. A stale decision, exhausted lane, or vanished credit
  changes neither the sequence nor credit counter. Failed ACK/CREDIT/PING
  construction likewise publishes no control bytes; the current profile does
  not put a synthetic control sequence on those frames.
- Inbound classification is likewise read-only. `Seq == expected` is NEW and
  requires an available receive grant on application lanes; `Seq < expected`
  is a duplicate; and `Seq > expected` is a gap carrying the unchanged expected
  sequence into a future `409 OUT-OF-ORDER` response. Only an exact NEW commit
  advances expected `Seq` and consumes one receive grant. After terminal
  sequence consumption, representable retransmissions remain duplicates.
- ACK is cumulative, monotonic, and never grants credit. Acknowledging a
  sequence that was never reserved is refused.
- Transaction identity is the exact `(Lane, Txn)` pair. Pending transactions
  live in caller-sized storage and an interleaved event can never satisfy a
  response merely because it arrived first.
- The session's lane and transaction counts are caller choices, not product
  maxima. Full tables refuse mutation.

The first memory-fixture handshake admits only exact `HELLO RABBIT/1.0`,
intersects the `lanes,async` capability flags, and reaches `200 HELLO` state.
Fixture peer evidence must be constructor-supplied and labeled fixture-only.
The foundation does not reproduce the reference's nonce-only AUTH or random
session token, because those would falsely imply the current channel-binding,
mutual-server-proof, and hybrid-PQ security contract is satisfied.

## Reference mismatches intentionally not copied

At the pin, the Rust parser overwrites duplicate headers, accepts bodies without
`Length`, truncates surplus input, and applies its body bound after allocation.
The Python parser accepts LF-only frames, replacement-decodes invalid UTF-8,
and does not reliably match `Txn`. Integrated Burrow delivery does not enforce
the credit/ACK behavior proven only by isolated lane unit tests.

The specification also reserves lane 0 for control while the implementations
use `Lane` on ACK/CREDIT as the target application lane. This profile follows
that de-facto targeting for now and records it as a Rabbit refinement. It keeps
lane `Seq`, application `Event-Seq`, and replay `Since` distinct; the reference
currently conflates them during live event delivery.

## Security and physical transport

The deterministic memory pair proves only byte-stream, frame, and session
behavior. It supplies no confidentiality, authenticated peer identity, channel
binding, or internet-hosting evidence. A future secure adapter must provide TLS
1.3 server accept, `rabbit/1` ALPN, exporter evidence, mutual identity proof,
trust policy, and the selected PQ composition beneath the same `NET-IO-PORT`
and neutral Rabbit contracts.
