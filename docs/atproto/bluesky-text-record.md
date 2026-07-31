# Exact Bluesky text-record encoder

`akashic/atproto/bluesky-text-record.f` is the state-free record adapter for a
text-only `app.bsky.feed.post`. It emits exactly, without optional whitespace
or extra members:

```json
{"$type":"app.bsky.feed.post","text":"...","createdAt":"..."}
```

The output is ready to be passed as the record object to the caller-owned
`create-record-codec.f` / `create-record.f` composition. Record-key generation,
authenticated XRPC, credentials, transport, persistence, facets, embeds, and
moderation remain separate owners.

## API

```forth
BSKY-TEXT-RECORD-MEASURE
  ( text-a text-u -- written status )

BSKY-TEXT-RECORD-WORKSPACE-CLEAR
  ( workspace -- status )

BSKY-TEXT-RECORD-ENCODE
  ( epoch-ms text-a text-u destination capacity workspace
    -- written status )
```

The text may be empty. Nonempty text must be valid UTF-8 and at most
`BSKY-TEXT-RECORD-TEXT-MAX` (3,000) raw bytes. The shared JSON writer performs
quote, reverse-solidus, named-control, and `\u00XX` escaping. This boundary
does not duplicate the PDS's separate grapheme policy.

`epoch-ms` is trusted caller-injected Unix wall time. The adapter checks the
range, divides by 1,000, and emits a canonical whole-second UTC value such as
`2024-06-15T15:30:00Z`. It never reads `EPOCH@`, a Streams event timestamp, or
the TID clock. `createdAt` and the repository record key therefore remain
distinct even when their callers use the same trusted time sample.

## Capacity and workspace

`BSKY-TEXT-RECORD-MEASURE` returns the exact encoded body length. The smallest
body, with empty text, is 75 bytes. A raw C0 byte can expand to six JSON bytes,
so the protocol's 3,000-byte text ceiling produces a justified worst-case body
bound of `BSKY-TEXT-RECORD-BODY-MAX` (18,075 bytes).

The caller supplies an eight-byte-aligned
`BSKY-TEXT-RECORD-WORKSPACE-SIZE` (18,176-byte) workspace. It contains only
operation fields, a checked writer descriptor, a 20-byte timestamp, and the
worst-case staging body. The staging arena is what makes publication fully
transactional: the destination is copied only after every subordinate writer
operation and the exact final length have succeeded.

The complete caller-advertised destination span, text span, and fixed
workspace span are qualified before use. The three spans must be mutually
disjoint; exact adjacency is allowed. A successful or internally admitted
operation wipes the complete workspace. Rejected geometry does not mutate
either destination or workspace.

Because the workspace maximum is derived directly from the protocol text
ceiling and JSON's maximum byte expansion, it is not a connector-instance or
application-capacity limit.

## Statuses

| Status | Meaning |
|---|---|
| `BSKY-TEXT-RECORD-S-OK` | Record published |
| `BSKY-TEXT-RECORD-S-INVALID` | Invalid call shape or workspace alignment |
| `BSKY-TEXT-RECORD-S-CAPACITY` | Destination cannot hold the measured record |
| `BSKY-TEXT-RECORD-S-ALIAS` | Text, destination, and workspace are not disjoint |
| `BSKY-TEXT-RECORD-S-UTF8` | Text is not valid UTF-8 |
| `BSKY-TEXT-RECORD-S-TEXT` | Raw text exceeds 3,000 bytes |
| `BSKY-TEXT-RECORD-S-RANGE` | Epoch or caller span is outside its range |
| `BSKY-TEXT-RECORD-S-PROTECTED` | A required span names protected memory |
| `BSKY-TEXT-RECORD-S-PLATFORM` | The platform could not qualify a span |
| `BSKY-TEXT-RECORD-S-INTERNAL` | A prequalified subordinate operation disagreed |

`BSKY-TEXT-RECORD-STATUS-VALID?` admits exactly this vocabulary. Every failed
encode returns `0 status` and leaves the complete destination unchanged.

## Example

```forth
CREATE _BTR-WORK-RAW BSKY-TEXT-RECORD-WORKSPACE-SIZE 7 + ALLOT
: _BTR-WORK  _BTR-WORK-RAW 7 + -8 AND ;

CREATE _BTR-BODY 512 ALLOT

1718465400123
S" hello from MegaPad"
_BTR-BODY 512 _BTR-WORK
BSKY-TEXT-RECORD-ENCODE
BSKY-TEXT-RECORD-S-OK = IF
    _BTR-BODY SWAP TYPE
ELSE
    DROP
THEN
```

The output uses the exact key order shown above and contains
`"createdAt":"2024-06-15T15:30:00Z"`.
