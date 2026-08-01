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
`EVENT` requires a nonzero application `Lane` plus distinct nonzero `Seq` and
`Event-Seq`; `ACK` and `CREDIT` target an exact lane and carry their one
matching positive scalar. PING is
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

`RABBIT-CONNECTION-ENQUEUE-RESERVED` is the generalized publication seam for
higher neutral owners that must retain structural progress capacity. Its
caller-supplied reserve is the minimum number of empty slots that must remain
in the selected control or data queue after success. Refusal occurs before
encoding or session mutation; ordinary `RABBIT-CONNECTION-ENQUEUE` delegates
with a zero reserve. The reserve is queue space, not a permanently assigned
slot or a product capacity.

The send pump never switches frames after a short write. Control traffic wins
only at a frame boundary, preventing both control starvation and byte-stream
interleaving. Attempt count, confirmed offset, frame identity, and cumulative
confirmed wire bytes remain inspectable after failure. Receive owns one stable
READY parser view at a time; a distinct carry buffer retains any coalesced
suffix until the caller commits or drops the loan. Commit alone applies
handshake, EVENT, ACK, and CREDIT session mutation. Close and cancel invalidate
loans and wipe queued/parser/carry bytes before delegating transport teardown.

Higher neutral owners can ask whether an arbitrary span overlaps the complete
connection graph, or whether a complete builder graph overlaps it. These
queries cover the descriptor, session and its port/lane/transaction bindings,
parser and parser arena, receive carry, and both complete queue allocations;
invalid input fails closed. Client and server facades therefore do not need to
duplicate the connection's private ownership map.

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
witness. A fail-closed owned-span query covers its descriptor, complete entry
allocation, and complete arena allocation for composition by higher owners.

## Server peer ownership

`net/rabbit/server.f` is a generic one-peer server owner above one server-role
connection. It owns that connection, one dedicated reply builder, and a copied
Burrow identifier, while borrowing one immutable sealed router. A listener or
host manager may compose any caller-chosen number of these peers; accepting
transports, allocating peer graphs, scheduling them, and owning application
state are deliberately not hidden inside this record.

Initialization has one explicit caller-owned graph contract:

```text
RABBIT-SERVER-INIT
( connection sealed-router empty-reply-builder
  burrow-source-a burrow-source-u burrow-destination-a burrow-capacity
  peer-evidence admission-xt admission-context server -- status )
```

The connection must have server role, be READY or already OPEN, have no held
receive frame or queued output, and provide at least one control and one data
slot. The stronger nonzero data requirement gives every admitted request an
honest response path even though a lower connection without application output
is otherwise valid. INIT copies the identity and rejects overlap among every
persistent allocation before writing either destination. The server thereafter
owns and finalizes the connection, builder, Burrow destination, and descriptor;
it borrows the sealed router, admission callback, context, and peer evidence.

HELLO admission is a synchronous callback over the borrowed HELLO frame,
caller-supplied peer evidence, and opaque context. The callback returns an
opaque peer token and an allow/deny decision. On allowance, the owner computes
the capability intersection, prebuilds and validates the exact HELLO response,
commits the inbound handshake, then enqueues the copied response. Admission
denial or callback failure drops and cancels the peer: the current lower
handshake cannot transmit a refusal before establishment without falsely
establishing the denied session. A wire-visible pre-establishment refusal is a
recorded lower-layer extension, not an invented success transition.

For known requests, a sealed router maps the exact copied `(verb, selector)`
to a synchronous handler and context. The handler receives the borrowed frame,
typed request kind, admitted peer token, and an empty server-owned builder. A
handler response is accepted only when its Lane and Txn exactly match the held
request. Route misses become correlated 404 responses, handler denial becomes
403, and thrown, invalid, or wrongly correlated handler results become bounded
500 responses. Unknown extension verbs with complete correlation receive 501.
The owner reserves output capacity before invoking a handler, copies the
response into the connection while the request loan remains live, and commits
the request only afterward. Backpressure therefore cannot repeat application
work. PING/PONG and ACK/CREDIT remain internal control transitions.

`POLL` and `DISPATCH` return an item plus a semantic server status. A useful
handler response is `RSERVER-S-OK`; synthesized route miss, policy denial,
unsupported extension, and handler failure remain distinguishable as
`RSERVER-S-NOT-FOUND`, `RSERVER-S-DENIED`, `RSERVER-S-UNSUPPORTED`, and
`RSERVER-S-CALLBACK` even though each also enqueues a valid numeric response.
`RSERVER-S-PENDING` with no item means no callback ran and cooperative progress
may be retried. Inspection retains the last response code and exact lower
detail without making numeric application status the owner's control status.

Polling and dispatch are cooperative and globally non-reentrant while module
scratch holds a live loan. Callbacks must copy retained data and may not pump
the peer, mutate the router, or retain the reply builder. Close, cancel, and
finalization propagate through the owned connection; finalization also wipes
the builder, copied identity, and server record, but leaves the borrowed router
for its separate owner.

Higher neutral owners can query overlap against the server's complete composed
graph, including the borrowed router, without importing private record layout.
During a routed request callback they can also ensure only the exact nonzero
Lane carried by that held request. The latter operation refuses outside the
same server's active callback scope and does not expose arbitrary session-lane
allocation.

Server-side EVENT publication is an owned operation rather than a Streams or
application adapter concern:

```text
RABBIT-SERVER-NEXT-EVENT-LANE-SEQ@
( lane server -- lane-seq|0 status )

RABBIT-SERVER-EVENT
( target-a target-u lane event-seq view-a view-u body-a body-u server
  -- lane-seq|0 status )
```

The server verifies admission and application-lane credit, copies the selector,
optional View, and body through its otherwise-empty reply builder, publishes
the exact next Lane Seq, then resets the builder before returning. Source spans
may not alias any storage the operation resets or mutates. The successful Lane
Seq is returned separately from the caller's application `Event-Seq`; credit
and terminal sequence exhaustion are explicit `RSERVER-S-CREDIT` and
`RSERVER-S-OVERFLOW` results.

Every server EVENT leaves one data-queue slot empty. Sent events remain in
`WAIT-ACK`, while application responses use the same bounded data queue. Without
that reserve, events could occupy every slot and a request received before its
ACK could block the ACK behind a response that has nowhere to go. One peer has
at most one held request, so the retained slot preserves request/ACK progress;
capacity refusal consumes neither credit nor Lane Seq.

## Server subscription ownership

`net/rabbit/server-subscription.f` takes exclusive operational ownership of one
initialized per-peer server and adds a caller-sized copied selector table. A
shared sealed router registers its SUBSCRIBE route with one stable shared token,
not a per-peer owner pointer. Wrapper `POLL` and `DISPATCH` establish the active
per-peer owner only for the synchronous server call, allowing any number of
peer wrappers to borrow the same immutable router under Rabbit's serialized
scratch contract. Driving the wrapped server directly is outside the ownership
contract. The router owner must install the exact shared route/token pair before
sealing; wrapper initialization validates the supplied token and ownership
geometry but does not guess which application selectors should mount it.

Registration is commit-gated. The route validates Lane, selector, `Txn`, and
`Since`, builds a correlated 200 response, lazily establishes only the held
application Lane, and copies a CANDIDATE. The wrapper publishes and counts that
entry only after the underlying server reports that exact response successfully
enqueued and committed; every substitution or failure wipes it. Cursor state is
therefore never live merely because a handler happened to run.

The owner receives one deterministic, read-only exact-suffix callback. SERVICE
preflights Lane/credit before calling it, asks for exactly `cursor + 1`, and
publishes at most one EVENT. The published cursor and last Lane Seq advance only
after server enqueue succeeds. Queue-reserve refusal may repeat the same suffix
lookup, so the callback must be retryable; it remains the application's sole
journal rather than copied Rabbit state. The wrapper owns server lifecycle and
wipes its registrations, selectors, server, connection, builder, and identity
on successful finalization, while the router and source context remain borrowed.
Streams remains only the configured network operator/profile adapter.

`RESET` stops future publication by wiping registrations and copied selectors;
it does not pretend to retract EVENT bytes already queued or awaiting ACK, and
it does not close application Lanes in the nested session. Whole-peer teardown
continues through the wrapper lifecycle and finalization operations.

## Client operation ownership

`net/rabbit/client.f` owns a caller-sized correlated-operation table above one
client-role connection. Each operation has a caller-selected transaction slot
and result slot; request publication copies the exact `Txn`, begins the session
transaction, and enqueues connection-owned bytes as one refusal-atomic action.
If enqueue refuses, the session transaction is rolled back and unpublished
bytes are wiped. An indeterminate rollback leaves a correlation tombstone
rather than making the same transaction identity available to a late response.

Responses match only the exact `(Lane, Txn)` pair. A fitting body is copied to
the operation's result slot before the receive loan is committed; an oversized
body publishes its exact required size and no prefix. A supplied synchronous
callback also sees the complete correlated response before commit, allowing an
application-profile adapter to validate the exact label, `View`, and extension
metadata that the neutral operation does not persist. Rejecting that terminal
response cancels the connection rather than leaving an impossible pending
transaction. Operation pointers are paired with nonzero generations advanced
on reuse so release and cancellation can reject stale handles. Generation
exhaustion refuses another publication rather than wrapping into an ABA. Local
cancellation deliberately preserves a tombstone
until the response or connection teardown makes reuse unambiguous.

`POLL` and `DISPATCH` deliver EVENT, extension, and optionally correlated
response frames to one synchronous opaque callback. The callback must copy any
bytes it retains and explicitly chooses commit or drop; borrowed parser
pointers are cleared before the call returns. Recursive polling or dispatch is
refused before it can overwrite the live outer loan. An event may therefore be
committed while an unrelated request is
still pending without satisfying or disturbing that operation. Inbound HELLO,
ACK/CREDIT, and the exact PONG control shape remain client/connection state
transitions rather than callback items. The HELLO `Burrow-ID` is copied into
its own caller span before commit and published only after session admission
succeeds. Client records, operation metadata, transaction bytes, identity, and
result bytes are all caller-owned. A canonical zero-operation client remains
useful for handshake and unsolicited dispatch.

An established client may also enqueue an already typed ACK, CREDIT, or PING
through the same owning connection. This narrow control surface validates the
builder kind and graph disjointness and preserves the connection's
encode-before-mutate behavior; it does not bypass correlated publication for
ordinary requests.

A READY client has an equally narrow typed HELLO surface. It accepts only a
disjoint READY HELLO builder, delegates capability equality and HELLO-BEGIN to
the owning connection, and publishes the resulting control slot without
exposing the connection as the application's protocol interface.

## Subscription and replay ownership

`net/rabbit/subscription.f` owns a caller-sized table of generic subscription
registrations above one client. Each registration copies its exact selector,
records its nonzero application lane and callback, and carries a nonzero
generation so
released or reused entry pointers cannot be mistaken for live handles. The
caller supplies the metadata array plus uniform selector and event slots. A
zero-entry table is a valid configuration; no product subscription count or
event-body limit is embedded in the module. Entry-generation exhaustion likewise
refuses registration rather than reissuing an old generation.

Registration takes the caller's last durably applied application
`Event-Seq`. Binding constructs an ordinary correlated `SUBSCRIBE` request and
emits that cursor as `Since` when it is nonzero. The terminal response remains
an inspectable client operation until the caller explicitly accepts or refuses
the bind result; the neutral layer does not infer application success from an
arbitrary numeric response. Selector registration state, transport lane
sequence, last observed application sequence, and committed replay cursor are
kept distinct.

An exact next `Event-Seq` is copied in full and offered synchronously to the
registered application callback. Only callback acceptance plus successful
connection commit advances the replay cursor. An already committed sequence is
reported as a duplicate and remains available for application digest or
idempotency validation without advancing the cursor, including at the maximum
cursor so a lost final transport ACK remains recoverable. A gap or oversized
body invokes no application callback, copies no prefix, and leaves the
committed cursor unchanged; `NEXT-EVENT@` reports cursor exhaustion directly.
Event staging bytes are wiped before
`POLL` or `DISPATCH` returns; callbacks may not retain any supplied slice or
reenter subscription dispatch or lifecycle mutation. A callback throw or
invalid decision remains explicit even for extension and other fallback traffic.

Disconnect currently represents whole-connector loss: it cancels the attached
client, clears lane-local and bind-operation evidence, preserves copied
selectors, generations, callbacks, and committed cursors, and marks every live
entry for rebind. The caller can attach a fresh READY or ACTIVE client and bind
the same handles again, producing `Since` from the preserved cursor. Detach
preflights every owned bind handle and releases only terminal operations before
clearing entry evidence; an unsafe cleanup refusal retains the client and
handles for recovery. This is
the reconnect/replay foundation, not a complete subscription-management API:
per-entry `UNSUBSCRIBE`, independent cancellation on a still-live connector,
and automatic ACK-window policy remain to be added. Generic callers can send
validated cumulative ACK and CREDIT controls through the client control seam
without moving that policy into Streams.

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
