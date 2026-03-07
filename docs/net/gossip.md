# akashic-gossip — P2P Network Layer for KDOS / Megapad-64

Peer-to-peer gossip protocol over WebSocket binary frames.
Message format: `[tag-byte][CBOR payload]`.
Manages a peer table of up to 16 connections with a seen-hash cache
for deduplication.

```forth
REQUIRE gossip.f
```

`PROVIDED akashic-gossip` — depends on `akashic-ws`, `akashic-cbor`,
`akashic-tx`, `akashic-block`, `akashic-mempool`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Message Tags](#message-tags)
- [Initialization](#initialization)
- [Peer Management](#peer-management)
- [Broadcasting](#broadcasting)
- [Block Requests](#block-requests)
- [Incoming Messages](#incoming-messages)
- [Callbacks](#callbacks)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **WebSocket binary** | All messages are binary frames — no JSON overhead |
| **Tag-length-value** | First byte is a message tag, remainder is CBOR |
| **Seen cache** | SHA3-256 hash ring prevents re-broadcasting duplicates |
| **Fixed peer table** | 16-slot array — bounded memory, O(1) lookup by id |
| **Callback hooks** | Node wires `GSP-ON-TX-XT`, `GSP-ON-BLK-ANN-XT`, etc. at init time |
| **Guard-wrapped** | Public API serialized with `WITH-GUARD` |

---

## Message Tags

| Tag | Name | Payload |
|---|---|---|
| `0x01` | TX | CBOR-encoded transaction |
| `0x02` | BLK-ANN | Block height (u64) |
| `0x03` | BLK-REQ | Requested height (u64) |
| `0x04` | BLK-RSP | CBOR-encoded block data |
| `0x05` | STATUS | Chain height (u64) |

---

## Initialization

### GSP-INIT

```forth
GSP-INIT  ( -- )
```

Zero peer table, clear seen cache, reset callback XTs to no-ops.

---

## Peer Management

### GSP-CONNECT

```forth
GSP-CONNECT  ( url-a url-u -- id | -1 )
```

Open a WebSocket connection to the given URL.  Returns a peer id
(0..15) on success, or `-1` if the table is full or connection fails.

### GSP-DISCONNECT

```forth
GSP-DISCONNECT  ( id -- )
```

Close the WebSocket for peer *id* and free the slot.

### GSP-PEER-COUNT

```forth
GSP-PEER-COUNT  ( -- n )
```

Number of currently connected peers.

---

## Broadcasting

### GSP-BROADCAST-TX

```forth
GSP-BROADCAST-TX  ( tx -- )
```

CBOR-encode the transaction, add its hash to the seen cache, and send
to all connected peers.

### GSP-BROADCAST-BLK

```forth
GSP-BROADCAST-BLK  ( blk -- )
```

Send a block announcement (height) to all peers.

### GSP-SEND-STATUS

```forth
GSP-SEND-STATUS  ( peer -- )
```

Send our current chain height to a specific peer.

---

## Block Requests

### GSP-REQUEST-BLK

```forth
GSP-REQUEST-BLK  ( height peer -- )
```

Request block data at *height* from *peer*.  The response arrives
asynchronously and is dispatched to `GSP-ON-BLK-RSP-XT`.

---

## Incoming Messages

### GSP-ON-MSG

```forth
GSP-ON-MSG  ( buf len peer -- )
```

Dispatch a received binary frame by its tag byte.  Validates CBOR,
checks the seen cache, and fires the appropriate callback.

### GSP-POLL

```forth
GSP-POLL  ( -- )
```

Poll all connected peers for incoming WebSocket frames.  Each frame
is dispatched via `GSP-ON-MSG`.

### GSP-SEEN?

```forth
GSP-SEEN?  ( hash -- flag )
```

Check whether a message hash is in the seen cache (ring buffer).

---

## Callbacks

These are `VARIABLE`s holding execution tokens.  The node daemon sets
them during `SYNC-INIT` / `NODE-INIT`:

| Variable | Signature | Purpose |
|---|---|---|
| `GSP-ON-TX-XT` | `( tx -- )` | Valid transaction received from peer |
| `GSP-ON-BLK-ANN-XT` | `( height peer -- )` | Block height announced |
| `GSP-ON-BLK-RSP-XT` | `( buf len -- )` | Block data received |
| `GSP-ON-STATUS-XT` | `( height peer -- )` | Peer chain status |

---

## Concurrency

All public words are wrapped with a module-level guard.  Callbacks
execute *inside* the guard — they must NOT call gossip words directly
(see `sync.f` deferred-request pattern).

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `GSP-INIT` | `( -- )` | Initialize peer table + seen cache |
| `GSP-CONNECT` | `( url-a url-u -- id\|-1 )` | Connect to peer |
| `GSP-DISCONNECT` | `( id -- )` | Drop peer connection |
| `GSP-PEER-COUNT` | `( -- n )` | Active peer count |
| `GSP-BROADCAST-TX` | `( tx -- )` | Broadcast transaction |
| `GSP-BROADCAST-BLK` | `( blk -- )` | Announce new block |
| `GSP-REQUEST-BLK` | `( height peer -- )` | Request block data |
| `GSP-SEND-STATUS` | `( peer -- )` | Send chain status |
| `GSP-ON-MSG` | `( buf len peer -- )` | Dispatch incoming frame |
| `GSP-POLL` | `( -- )` | Poll all peers |
| `GSP-SEEN?` | `( hash -- flag )` | Check seen cache |
| `GSP-MAX-PEERS` | `( -- 16 )` | Max peer count |
