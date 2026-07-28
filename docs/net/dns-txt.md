# DNS TXT wire utility

`akashic/net/dns-txt.f` is a protocol-neutral, caller-owned DNS wire utility.
It builds one recursive Internet-class TXT query and parses one matching
response. It does not choose a resolver, open a socket, retry over TCP, cache
an answer, chase aliases, interpret application text, or confer trust on DNS
data.

The implementation follows the DNS header, question, resource-record, name
compression, and TXT character-string formats in
[RFC 1035](https://www.rfc-editor.org/rfc/rfc1035.html). In particular, labels
are at most 63 octets, an expanded wire name is at most 255 octets, names are
matched with ASCII case folding, and one TXT RDATA value consists of one or
more length-prefixed binary character-strings. TTL is admitted only in the
unsigned 31-bit range clarified by
[RFC 2181](https://www.rfc-editor.org/rfc/rfc2181.html).

## Ownership and limits

The module owns no mutable state. A caller allocates:

- one `DNS-TXT-QUERY-SIZE` (304-byte) aligned query descriptor;
- one `DNS-TXT-RESULT-SIZE` (512-byte) aligned result descriptor; and
- a result byte arena of 1 through `DNS-TXT-VALUE-MAX` (4,096) bytes.

The query descriptor contains the complete packet. The result descriptor
contains all decompression and parse scratch as well as retained evidence, so
different descriptors may be used independently. The result arena and result
descriptor must be disjoint from each other, the query descriptor, and the
response being parsed. Query and response are read-only and may overlap if
both complete views remain structurally valid. Exact adjacency is valid.
Public entry points qualify caller spans before reading or writing them.

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

## Response lifecycle

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
the query owner. Unrelated records are structurally consumed but ignored.
CNAME traversal remains resolver work; this utility never treats an
unproven, differently owned TXT answer as the requested value.

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

These bits describe parser observations, not authenticity. DNSSEC validation,
resolver provenance, destination admission, and application-specific
confirmation remain separate policy.

`DNS-TXT-S-ALIAS` refers to unsafe overlapping caller memory, not a DNS CNAME.
The remaining admission statuses distinguish invalid arguments, capacity,
physical range, protected spans, and platform qualification failure from
wire-level mismatch and malformation.
