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
from enqueue; a later typed builder will supply the canonical construction side
of this same boundary.

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

## Lane and transaction profile

- Lane identifiers are decimal unsigned 16-bit values. Lane 0 is control.
- Application lanes start with zero send credit. Only an explicit positive
  `Credit` grant permits a new sequenced delivery.
- Lane `Seq` starts at 1, admits the complete unsigned 64-bit range, and is
  independent for each lane. After `2^64-1`, the lane is terminally exhausted
  rather than wrapping to zero. It is transport ordering, never a World or
  topic `Event-Seq`.
- `Seq == expected` delivers once and advances. `Seq < expected` is a duplicate
  and may be re-ACKed without redelivery. `Seq > expected` is a gap and carries
  the unchanged expected sequence into a future `409 OUT-OF-ORDER` response.
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
