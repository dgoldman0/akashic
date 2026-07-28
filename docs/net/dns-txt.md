# DNS TXT wire utility

`akashic/net/dns-txt.f` is a protocol-neutral, caller-owned DNS wire utility.
It builds one recursive Internet-class TXT query and either iterates all
direct matching records or applies a strict exactly-one convenience parse to
one response. A separate transaction-bound result can extract one direct
`IN/CNAME` target so a higher resolver can issue a fresh query. The utility
does not choose a resolver, open a socket, retry over TCP, cache an answer,
chase aliases, interpret application text, or confer trust on DNS data.

The implementation follows the DNS header, question, resource-record, name
compression, and TXT character-string formats in
[RFC 1035](https://www.rfc-editor.org/rfc/rfc1035.html). In particular, labels
are at most 63 octets, an expanded wire name is at most 255 octets, names are
matched with ASCII case folding, and one TXT RDATA value consists of one or
more length-prefixed binary character-strings. TTL is admitted only in the
unsigned 31-bit range clarified by
[RFC 2181](https://www.rfc-editor.org/rfc/rfc2181.html).

## Ownership and limits

The module owns no mutable state. A caller allocates one
`DNS-TXT-QUERY-SIZE` (304-byte) aligned query descriptor and then either:

- for strict parsing, one `DNS-TXT-RESULT-SIZE` (512-byte) aligned result
  descriptor and one result byte arena; or
- for iteration, one `DNS-TXT-ITER-SIZE` (512-byte) aligned iterator, one
  `DNS-TXT-RR-RESULT-SIZE` (96-byte) aligned RR result, and one RR byte arena;
  or
- for direct-alias extraction, one `DNS-TXT-CNAME-RESULT-SIZE` (512-byte)
  aligned result and one target-name arena.

TXT arenas are 1 through `DNS-TXT-VALUE-MAX` (4,096) bytes. A CNAME target
arena is 1 through `DNS-TXT-NAME-MAX` (253) bytes.

The query descriptor contains the complete packet. A strict result or
iterator contains all decompression scratch and retained response evidence, so
different caller-owned instances may be used independently. Every writable
descriptor and arena participating in one operation must be disjoint from the
others and from the query and response. Query and response are read-only and
may overlap if both complete views remain structurally valid. Exact adjacency
is valid. Public entry points qualify caller spans before reading or writing
them.

Presentation query names are a deliberately small, unescaped DNS discovery
profile: one through 253 visible ASCII bytes, dot-separated nonempty labels,
and labels no longer than 63 bytes. A dot is always a separator; binary-label
escapes and a trailing root dot are not accepted. Unlike a hostname
validator, this profile permits service-label characters such as underscore.
Case is retained in the query but is insignificant when a response is
matched.

`DNS-TXT-MESSAGE-MAX` is 65,535 bytes. Expanded response names remain bounded
at 255 bytes. Compression pointers must refer to prior message data, and a
compression chain is capped at
`DNS-TXT-COMPRESSION-HOPS-MAX` (128) pointer traversals. A cycle, reserved
label tag, out-of-range pointer, truncated label, expanded-name overflow, or
section whose declared records do not exactly consume the packet is
`DNS-TXT-S-MALFORMED`.

## Query lifecycle

```forth
DNS-TXT-QUERY-BUILD  ( name-a name-u id query -- status )
DNS-TXT-QUERY-VALID? ( query -- flag )
DNS-TXT-QUERY$       ( query -- packet-a packet-u status )
DNS-TXT-QUERY-ID@    ( query -- id status )
DNS-TXT-QUERY-WIPE   ( query -- status )
```

`DNS-TXT-QUERY-BUILD` emits one standard query with `RD=1`, `QDCOUNT=1`,
`QTYPE=TXT`, and `QCLASS=IN`. The caller supplies the 16-bit transaction ID;
randomness and ID allocation belong to the resolver adapter. The packet has
no EDNS option and is at most 271 bytes. Failed preflight, including source
overlap with the query descriptor, leaves the existing descriptor unchanged.

`DNS-TXT-QUERY$` returns a synchronous borrowed view into the descriptor.
`DNS-TXT-QUERY-WIPE` invalidates and zeroes the entire descriptor.

## Per-RR iteration

```forth
DNS-TXT-RR-RESULT-INIT     ( value-a value-cap rr-result -- status )
DNS-TXT-RR-RESULT-VALID?   ( rr-result -- flag )
DNS-TXT-RR-PRESENT?        ( rr-result -- flag )
DNS-TXT-RR-PROVISIONAL?    ( rr-result -- flag )
DNS-TXT-RR-PREFIX$         ( rr-result -- prefix-a prefix-u )
DNS-TXT-RR-TOTAL-LENGTH@   ( rr-result -- total-u )
DNS-TXT-RR-COMPLETE?       ( rr-result -- flag )
DNS-TXT-RR-STRING-COUNT@   ( rr-result -- count )
DNS-TXT-RR-TTL@            ( rr-result -- ttl )
DNS-TXT-RR-RESULT-WIPE     ( rr-result -- status )

DNS-TXT-ITER-BEGIN         ( response-a response-u query rr-result iter -- status )
DNS-TXT-ITER-NEXT          ( iter -- present? status )
DNS-TXT-ITER-VALID?        ( iter -- flag )
DNS-TXT-ITER-TERMINAL?     ( iter -- flag )
DNS-TXT-ITER-VALIDATED?    ( iter -- flag )
DNS-TXT-ITER-STATUS@       ( iter -- status )
DNS-TXT-ITER-RCODE@        ( iter -- rcode )
DNS-TXT-ITER-FLAGS@        ( iter -- header-flags )
DNS-TXT-ITER-EVIDENCE@     ( iter -- evidence )
DNS-TXT-ITER-MATCHED-COUNT@ ( iter -- count )
DNS-TXT-ITER-WIPE          ( iter -- status )
```

`DNS-TXT-ITER-BEGIN` binds the response header and echoed question to the
query, but does not publish an answer. Success starts an active iterator whose
stored status is `DNS-TXT-S-PROVISIONAL`. Each successful
`DNS-TXT-ITER-NEXT` may return `present?` true for the next direct `IN/TXT`
answer at the queried owner. Unrelated records are consumed and ignored; the
iterator does not chase aliases or apply application policy.

A present RR result is always provisional. Its character-strings are
concatenated in wire order into the bounded arena. `DNS-TXT-RR-PREFIX$`
returns the retained prefix, while `DNS-TXT-RR-TOTAL-LENGTH@` reports the full
logical length even when it exceeds the arena.
`DNS-TXT-RR-COMPLETE?`, `DNS-TXT-RR-STRING-COUNT@`, and `DNS-TXT-RR-TTL@`
report completeness, character-string count, and TTL for that RR. The same
arena is cleared and reused by the next `NEXT`, so a caller that needs several
records must copy each provisional result into its own staging storage before
advancing.

Iteration is complete only when `NEXT` returns `present?` false. Reaching that
terminal result drains every declared authority and additional RR and requires
the raw packet to end exactly at the final record boundary. A successful
terminal state has `DNS-TXT-ITER-VALIDATED?` true and returns
`DNS-TXT-S-OK` when records were yielded or `DNS-TXT-S-NODATA` when none were
found. A malformed late record, truncation, or other terminal failure leaves
validation false and invalidates every candidate yielded earlier. Consumers
must therefore keep yielded records provisional and publish them only after
observing the mandatory terminal `present?` false result and successful
validation.

`DNS-TXT-ITER-WIPE` clears the bound RR arena, RR result, and iterator.
Reinitialization and admission failures follow the same caller-ownership and
preflight rules as the strict parser.

## Direct CNAME extraction

```forth
DNS-TXT-CNAME-RESULT-INIT  ( target-a target-cap result -- status )
DNS-TXT-CNAME-RESULT-VALID? ( result -- flag )
DNS-TXT-CNAME-PARSE        ( response-a response-u query result -- status )
DNS-TXT-CNAME-STATUS@      ( result -- status )
DNS-TXT-CNAME-TARGET$      ( result -- target-a target-u )
DNS-TXT-CNAME-RCODE@       ( result -- rcode )
DNS-TXT-CNAME-FLAGS@       ( result -- header-flags )
DNS-TXT-CNAME-EVIDENCE@    ( result -- evidence )
DNS-TXT-CNAME-ANSWER-COUNT@ ( result -- count )
DNS-TXT-CNAME-MATCHED-COUNT@ ( result -- count )
DNS-TXT-CNAME-TTL@         ( result -- ttl )
DNS-TXT-CNAME-RESULT-WIPE  ( result -- status )
```

`DNS-TXT-CNAME-PARSE` binds the same response transaction, echoed TXT
question, flags, and RCODE as the TXT parsers. It structurally drains every
declared answer, authority, and additional RR and requires the packet to end
exactly at the final record boundary. Success means there was exactly one
direct `IN/CNAME` RR at the queried owner. Its compressed target must consume
the complete CNAME RDATA and decode into the utility's bounded, unescaped
dotted presentation-name profile. The target is then suitable as the name of
a fresh `DNS-TXT-QUERY-BUILD` call.

No direct CNAME is `DNS-TXT-S-NODATA`; more than one is
`DNS-TXT-S-DUPLICATE`; an invalid target or late structural fault is
`DNS-TXT-S-MALFORMED`. If the sole structurally valid target exceeds the
caller arena, the parser still drains and validates the complete packet
before returning `DNS-TXT-S-CAPACITY`. Admission failures leave a prior live
result unchanged. Parse failures clear the complete target arena and retain
bounded transaction diagnostics.

This interface extracts one progression edge; it does not chase it. The
resolver owns a bounded hop count and case-insensitive visited-name set,
supplies a fresh unpredictable transaction ID, builds a new query, and
conservatively queries the CNAME target even when the prior response also
carried records for that target. That keeps each published query/response
binding explicit and makes loops and ambiguity higher-level resolver policy.

## Strict response lifecycle

```forth
DNS-TXT-RESULT-INIT    ( value-a value-cap result -- status )
DNS-TXT-PARSE          ( response-a response-u query result -- status )
DNS-TXT-STATUS@        ( result -- status )
DNS-TXT-VALUE$         ( result -- value-a value-u )
DNS-TXT-RCODE@         ( result -- rcode )
DNS-TXT-FLAGS@         ( result -- header-flags )
DNS-TXT-EVIDENCE@      ( result -- evidence )
DNS-TXT-ANSWER-COUNT@  ( result -- count )
DNS-TXT-MATCHED-COUNT@ ( result -- count )
DNS-TXT-STRING-COUNT@  ( result -- count )
DNS-TXT-TTL@           ( result -- ttl )
DNS-TXT-RESULT-WIPE    ( result -- status )
```

`DNS-TXT-RESULT-INIT` clears the complete advertised arena and initializes an
empty result. Reinitializing a valid live result also clears its old complete
arena before rebinding. `DNS-TXT-RESULT-WIPE` clears both the arena and
descriptor.

`DNS-TXT-RESULT-VALID?` validates the completed lifecycle as well as field
bounds. `EMPTY` has no observations. Only parser outcomes may be stored;
admission failures leave the previous result untouched. Non-success outcomes
have zero published length and no value evidence. Evidence is chained:
value, truncation, and RCODE evidence require a matched question, which
requires an admitted response header and transaction ID. RCODE evidence is
present exactly when the bound four-bit RCODE is nonzero. Successful and
capacity outcomes retain one matching RR and at least one character-string;
NODATA retains none; DUPLICATE retains at least two and no fewer strings than
matches. MALFORMED admits the parser's bounded partial observations because a
wire error may stop decoding at any boundary.

`DNS-TXT-PARSE` requires a response transaction ID and one echoed question
matching the supplied query. It safely decodes compressed names throughout
the question and every declared answer, authority, and additional record. A
successful result contains exactly one direct `IN/TXT` answer whose owner is
the query owner. It is the exactly-one convenience interface: unrelated
records are structurally consumed but ignored, while more than one matching
record is an explicit duplicate result. CNAME traversal remains resolver
work; this utility never treats an unproven, differently owned TXT answer as
the requested value.

One matching TXT RR may contain several character-strings. Their binary
contents are concatenated in wire order, zero-length strings are retained as
zero contribution, and `DNS-TXT-STRING-COUNT@` records their count. An empty
RDATA is malformed. More than one matching TXT RR returns
`DNS-TXT-S-DUPLICATE`, because a generic discovery consumer must not silently
select one binding. Admission and alias failures occur before mutation and
leave an existing result unchanged. Once wire parsing begins, failure clears
the result arena and published length while retaining status and bounded parse
evidence.

The raw 16-bit response flags remain available. Once the echoed question is
matched, its four-bit header RCODE is bound into `DNS-TXT-RCODE@`. The reserved
header Z bit is rejected while the assigned AD and CD bits remain observable.
After the echoed question is matched, `TC=1` returns
`DNS-TXT-S-TRUNCATED` so a transport owner can repeat the same query over a
non-truncating channel. A nonzero header RCODE returns
`DNS-TXT-S-RCODE`; the exact value is available through `DNS-TXT-RCODE@`.
`DNS-TXT-S-NODATA` means a structurally valid successful response had no
direct matching TXT answer.

## Evidence bits

`DNS-TXT-EVIDENCE@` is an OR of:

| Constant | Meaning |
| --- | --- |
| `DNS-TXT-E-RESPONSE` | `QR=1` and standard opcode were admitted |
| `DNS-TXT-E-ID` | the 16-bit transaction ID matched |
| `DNS-TXT-E-QUESTION` | the echoed owner, type, and class matched |
| `DNS-TXT-E-TRUNCATED` | the header carried `TC=1` |
| `DNS-TXT-E-RCODE` | a nonzero header RCODE was observed |
| `DNS-TXT-E-VALUE` | exactly one direct matching TXT RR was published |
| `DNS-TXT-ITER-E-VALIDATED` | iterator reached the exact, structurally valid packet end |
| `DNS-TXT-E-CNAME` | exactly one direct CNAME target was published |

The iterator never treats a yielded provisional RR as value evidence; its
validation bit appears only after the terminal raw-wire drain succeeds. These
bits describe parser observations, not authenticity. DNSSEC validation,
resolver provenance, destination admission, and application-specific
confirmation remain separate policy.

`DNS-TXT-S-ALIAS` refers to unsafe overlapping caller memory, not a DNS CNAME.
CNAME target extraction is transaction-bound wire parsing; traversal remains
resolver work.
The remaining admission statuses distinguish invalid arguments, capacity,
physical range, protected spans, and platform qualification failure from
wire-level mismatch and malformation.
