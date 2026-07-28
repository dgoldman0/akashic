# KDOS DNS Exchange Transport

`akashic/net/transports/kdos-dns.f` is a protocol-neutral, caller-owned DNS
exchange adapter for KDOS. It sends one already-encoded DNS query to one IPv4
recursive server, publishes the exact response packet into caller-owned memory,
and uses RFC 1035 TCP framing when a bound UDP response has `TC` set.

It contains no application-protocol, credential, feed, application-record,
resolver-cache, or CNAME-chase policy. Higher layers receive the raw DNS
message as normative transport output and compose any alternate data source
behind a separate adapter.

```forth
REQUIRE net/transports/kdos-dns.f

CREATE dns-response 4096 ALLOT
CREATE dns-adapter-allocation KDOSDNS-SIZE 7 + ALLOT
dns-adapter-allocation 7 + -8 AND CONSTANT dns-adapter

dns-response 4096 dns-adapter KDOSDNS-INIT
\ Check for KDOSDNS-S-OK.

query-a query-u server-ipv4-a dns-adapter KDOSDNS-START
\ KDOSDNS-S-PENDING means the exchange owns the KDOS network pump.

\ Cooperatively schedule KDOSDNS-POLL until it returns a terminal status.
dns-adapter KDOSDNS-RESPONSE$
\ On completion: response-a response-u KDOSDNS-S-OK.
```

## Caller-owned contract

`KDOSDNS-INIT ( response-a response-cap adapter -- status )` binds one response
arena of 12 through 65,535 bytes to one 1,368-byte `KDOSDNS-SIZE` descriptor.
The two spans must be writable, nonwrapping, eight-byte aligned where required,
and disjoint. Initialization zeros both spans. Reinitializing a valid active
descriptor returns `KDOSDNS-S-BUSY`; corrupt initialized state is rejected
rather than silently overwritten.

`KDOSDNS-START ( query-a query-u server-ip adapter -- status )` accepts 17
through 512 bytes containing exactly one standard, uncompressed question:

- `QR` and the opcode are zero;
- response-only `AA`, `TC`, and `RA`, reserved `Z`, and the query `RCODE`
  are zero;
- `QDCOUNT` is one;
- `ANCOUNT`, `NSCOUNT`, and `ARCOUNT` are zero;
- the wire name is complete and at most 255 bytes, including its root octet;
- exactly four trailing bytes hold the query type and class.

The root name is valid. Query type and class are retained generically rather
than restricted to TXT. EDNS, additional records, and pre-compressed outgoing
questions are intentionally outside this small transport contract.

Start copies the complete query and four-byte server address before returning,
so the input spans may be reused. Input query/server spans may not overlap the
descriptor or response arena. The caller supplies the transaction ID and is
responsible for choosing a fresh unpredictable value for each logical query.
The adapter obtains each UDP and TCP local ephemeral port independently from
the hardware random source. Port randomization is an additional binding, not a
substitute for transaction-ID freshness.

The descriptor owns all retained query, response, question-binding, TCP
framing, deadline, and diagnostic state. Module variables are transient KDOS
call scratch, so calls into this adapter must still be serialized.

## Cooperative exchange

UDP is the normative first attempt. The state machine warms the next-hop ARP
entry cooperatively, sends at most three consecutive UDP attempts per warmed
route, and waits one second between attempts. Route loss can restart that
sequence, but the entire transaction retains one 15-second deadline. Each poll
advances one bounded phase and admits at most one receive frame; it does not run
an unbounded receive loop.

A UDP packet becomes a candidate only after KDOS has admitted its Ethernet and
IPv4 envelope. The adapter then binds:

- the configured source IPv4 address;
- source port 53 and the retained local destination port;
- IPv4 UDP checksum semantics (a nonzero checksum must verify; the
  RFC-permitted zero checksum is accepted);
- `QR`, opcode zero, the reserved header bit, transaction ID, and one question;
- the complete decompressed question name, case-insensitively, plus exact query
  type and class.

Unrelated frames are consumed but do not publish response evidence. The
adapter deliberately does not walk answer, authority, or additional sections;
the caller's DNS wire parser must validate the complete returned message before
using records.

A question-bound UDP response with `TC` set retries the exact retained query
over TCP. The adapter prepends the RFC 1035 two-byte length, establishes a new
source-port-bound KDOS TCB, preserves partial send/receive progress, admits a
12-through-65,535-byte response frame, and repeats the header/ID/question
binding. A second truncated result over TCP is malformed. TCP teardown has its
own two-second deadline and falls back to synchronous local abort if graceful
close cannot finish.

References: [RFC 1035](https://www.rfc-editor.org/rfc/rfc1035.html) and
[RFC 7766](https://www.rfc-editor.org/rfc/rfc7766.html).

## Results and diagnostics

`KDOSDNS-POLL` returns `KDOSDNS-S-PENDING` while active. A successful terminal
exchange returns `KDOSDNS-S-OK`, changes the state to
`KDOSDNS-STATE-COMPLETE`, and makes the exact packet available through
`KDOSDNS-RESPONSE$`. Capacity, timeout, I/O, malformed framing, semantic
mismatch, callback fault, cancellation, and uncertain cleanup have distinct
statuses.

An otherwise bound DNS response with NXDOMAIN, SERVFAIL, or another nonzero
RCODE is still a successful transport exchange. `KDOSDNS-RCODE@` and
`KDOSDNS-FLAGS@` expose the final response diagnostics so resolver policy can
decide whether to stop, retry, or try another server. Transport success does
not mean that an application record exists.

`KDOSDNS-EVIDENCE@` reports which bindings were actually established, including
server tuple, UDP checksum admission, DNS header, transaction ID, semantic
question, truncation, TCP connection/length, response publication, and cleanup
fallback. These are parser and transport observations, not DNS authenticity.
The adapter does not implement DNSSEC.

`KDOSDNS-STEP-COUNT@`, `KDOSDNS-LAST-STEP-CYCLES@`, and
`KDOSDNS-MAX-STEP-CYCLES@` expose cooperative work measurements. They are
intended for deterministic resource gates and production telemetry; they do
not by themselves establish a platform-independent real-time ceiling.

## Cancellation, erasure, and ownership

`KDOSDNS-CANCEL` aborts a live matching TCB when necessary, releases the module
owner, clears all transaction and response material, and leaves a valid
cancelled descriptor. If lower cleanup throws or ownership cannot be proven,
it returns `KDOSDNS-S-CLEANUP` without erasing the state needed to retry
cleanup. A failure reached through polling follows the same rule: uncertain
TCP cleanup retains the owner and TCB fingerprint.

`KDOSDNS-WIPE` first performs that cancellation contract, then zeros the entire
response arena and descriptor. It refuses to erase either span after
`KDOSDNS-S-CLEANUP`. A wiped descriptor is no longer valid and must be
initialized before reuse.

KDOS has machine-global NIC receive storage, ARP state, TCP tables, transmit
scratch, and network configuration. `_KDOSDNS-OWNER` therefore allows one
active `kdos-dns` adapter at a time. That gate coordinates only instances of
this module: a machine composition must also serialize every other KDOS NIC
reader and TCP consumer, including `kdos-tls`. It is not safe to let two
independent network pumps consume frames concurrently.

## Resolver boundary

This transport performs one exchange. A production resolver owns:

- construction of TXT queries and fresh IDs;
- raw-message record validation;
- record selection and any CNAME policy;
- bounded hop and loop detection;
- re-querying each alias with a fresh transaction;
- cache and negative-cache policy;
- server selection, retry policy, and user-visible failure mapping.

The focused offline contract exercises admission, semantic question binding,
caller-owned lifecycle, owner contention, timeout/fault containment, exact TCP
query framing, cancellation, erasure, and step accounting without touching the
network. A real recursive-server journey and noisy-link qualification remain
separate integration evidence rather than claims of the offline gate.
