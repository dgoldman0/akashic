# Exact authenticated createRecord operation

`akashic/atproto/create-record-codec.f` and
`akashic/atproto/create-record.f` implement one narrow AT Protocol write:
`com.atproto.repo.createRecord`. The codec is state-free. The operation owner
composes it with one already-bound `AT-XRPC-EXCHANGE` and exposes ordinary
cooperative XIO callbacks.

This boundary does not own a schema registry, TID clock, record model, retry
queue, cache, persistence layer, or application policy. The caller chooses a
valid record key and supplies a strict JSON object whose `$type` exactly equals
the normalized collection NSID. The codec validates that invariant and copies
the object verbatim into a deterministic outer request envelope.

## Caller-owned storage

The caller independently supplies:

- the authenticated XRPC exchange and its arenas;
- a request-body arena of the caller's chosen capacity;
- `AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE` bytes of aligned scratch;
- an initialized result descriptor and a result byte arena; and
- `AT-CREATE-RECORD-SIZE` aligned owner storage.

There is no owner table or process-wide instance count. Initialization proves
that every mutable region is pairwise disjoint and external to the exchange's
complete bound graph: exchange storage, request and response arenas, vault,
OAuth client configuration, profile, and session. Preparation performs a
separate no-write alias pass before clearing or copying anything.

The JSON object parser retains its explicit security admissions of a 65,536
byte document, 64 object members, and depth 32. Those are syntax-admission
bounds shared with the existing JOSE parser, not request-arena or live-instance
capacities.

## Codec API

```forth
AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE  ( -- bytes )
AT-CREATE-RECORD-CODEC-WORKSPACE-CLEAR ( workspace -- status )

AT-CREATE-RECORD-BODY
  ( repo-a repo-u collection-a collection-u rkey-a rkey-u
    record-a record-u destination capacity workspace
    -- written status )

AT-CREATE-RECORD-RECEIPT
  ( source-a source-u expected-uri-a expected-uri-u workspace
    -- uri-a uri-u cid-a cid-u status )
```

The body encoder requires an exact DID repository, normalized collection,
valid record key, and strict record object. It returns zero written on failure;
only a successful length publishes the destination bytes.

Receipt admission requires exactly one `uri` and one `cid`. The URI must be a
DID-backed record URI and byte-for-byte equal to the expected URI. The CID must
use the blessed DAG-CBOR CIDv1 profile; a raw blob CID is rejected. Unknown
members are accepted only after the whole response has passed strict JSON
validation. Successful URI and CID spans point into the caller's workspace,
whose prefix has already been scrubbed of every external pointer.

## Operation and durable result

```forth
AT-CREATE-RECORD-RESULT-INIT
  ( result-bytes-a result-bytes-cap result -- status )

AT-CREATE-RECORD-RESULT-VALID?    ( result -- flag )
AT-CREATE-RECORD-RESULT-OUTCOME@  ( result -- outcome status )
AT-CREATE-RECORD-RESULT-STATUS@   ( result -- status )
AT-CREATE-RECORD-RESULT-HTTP@     ( result -- code status )
AT-CREATE-RECORD-RESULT-WIRE@     ( result -- wire-state status )
AT-CREATE-RECORD-RESULT-URI@      ( result -- uri-a uri-u status )
AT-CREATE-RECORD-RESULT-CID@      ( result -- cid-a cid-u status )

AT-CREATE-RECORD-INIT
  ( exchange body-a body-cap workspace result owner -- status )

AT-CREATE-RECORD-VALID?          ( owner -- flag )
AT-CREATE-RECORD-STATE@          ( owner -- state status )
AT-CREATE-RECORD-LAST-STATUS@    ( owner -- status )
AT-CREATE-RECORD-PORT            ( owner -- port | 0 )
AT-CREATE-RECORD-CLEANUP-ERROR@  ( owner -- error )

AT-CREATE-RECORD-PREPARE
  ( iat target collection-a collection-u rkey-a rkey-u
    record-a record-u owner -- status )

AT-CREATE-RECORD-XIO-START   ( operation owner -- step-status )
AT-CREATE-RECORD-XIO-POLL    ( operation owner -- step-status )
AT-CREATE-RECORD-XIO-CANCEL  ( operation owner -- )
AT-CREATE-RECORD-XIO-WIPE    ( operation owner -- )
```

`PREPARE` derives the repository DID from the bound OAuth profile, copies the
complete request body, builds the exact expected AT URI, and proves that the
result arena also has room for the protocol's exact 59-byte CID before the
exchange can send. The target must name exactly
`/xrpc/com.atproto.repo.createRecord`. Once preparation returns successfully,
the caller may overwrite every collection, record-key, record, and target
input buffer.

The result descriptor publishes one of four outcomes:

- `PENDING`: admitted locally but not terminal;
- `NO-EFFECT`: no wire send was observed;
- `UNCERTAIN`: a send may have occurred, but no valid receipt was admitted;
- `CREATED`: a proven HTTP 200 response supplied the exact URI and a validated
  DAG-CBOR CID.

Only `CREATED` exposes `AT-CREATE-RECORD-RESULT-URI@` and
`AT-CREATE-RECORD-RESULT-CID@`. Those bytes live entirely in the caller's
result arena and remain valid after XIO wipe and after the operation owner,
exchange, and OAuth profile are released. Cleanup failures are
reported separately by `AT-CREATE-RECORD-CLEANUP-ERROR@`; they never erase or
reclassify an already admitted semantic result.

The operation performs no general write retry. The underlying authenticated
exchange may repeat the exact request once only for its narrowly admitted
`use_dpop_nonce` challenge. Because the caller supplies the record key and the
payload bytes remain identical, that protocol retry addresses the same record
identity rather than creating a second caller-selected record.
