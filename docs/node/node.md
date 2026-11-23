# akashic-node — Node Daemon for KDOS / Megapad-64

Full blockchain node that ties all sub-systems together: gossip,
sync, mempool, persistence, RPC, light client proofs, and the HTTP
server.  Provides a single main loop with optional block production.

```forth
REQUIRE node.f
```

`PROVIDED akashic-node` — depends on `akashic-mempool`, `akashic-gossip`,
`akashic-sync`, `akashic-persist`, `akashic-rpc`, `akashic-block`,
`akashic-consensus`, `akashic-state`, `akashic-server`, `akashic-guard`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Node States](#node-states)
- [Initialization](#initialization)
- [Main Loop](#main-loop)
- [Block Production](#block-production)
- [Persistence](#persistence)
- [Control](#control)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Single main loop** | `NODE-RUN` drives all sub-systems in round-robin |
| **Cooperative** | No preemptive threading — each step must return quickly |
| **Optional production** | Block production is off by default; enable with `NODE-ENABLE-PRODUCE` |
| **Sub-system isolation** | Each module has its own guard; node only orchestrates |
| **Graceful shutdown** | `NODE-STOP` signals the loop and calls `SERVE-STOP` |

---

## Node States

| Constant | Value | Meaning |
|---|---|---|
| `NODE-STOPPED` | 0 | Daemon not running |
| `NODE-RUNNING` | 1 | Running and synced |
| `NODE-SYNCING` | 2 | Running but catching up to peers |

---

## Initialization

### NODE-INIT

```forth
NODE-INIT  ( port -- )
```

Initializes all sub-systems in order:

1. `ST-INIT` — world state
2. `MP-INIT` — mempool
3. `GSP-INIT` — gossip network
4. `SYNC-INIT` — block sync (wires gossip callbacks)
5. `PST-INIT` — persistence
6. `ROUTE-CLEAR` — HTTP router
7. `RPC-INIT` — JSON-RPC route (includes light client proof endpoints)
8. `SRV-INIT` — HTTP server on given port

After init, `NODE-STATUS` returns `NODE-STOPPED`.\
Call `NODE-RUN` to start the main loop.

---

## Main Loop

### NODE-RUN

```forth
NODE-RUN  ( -- )
```

Enters the main loop.  Each iteration:

1. **GSP-POLL** — receive and dispatch gossip messages
2. **SYNC-STEP** — issue deferred block requests
3. **Block production** — every N steps, attempt to produce a block
4. State tracking — reflect sync status in `NODE-STATUS`

The loop runs until `NODE-STOP` is called.

### NODE-STEP

```forth
NODE-STEP  ( -- )
```

Execute one iteration of the main loop (useful for testing).

---

## Block Production

Production is disabled by default.  When enabled, the node is synced
(`SYNC-IDLE`) and its wall clock is set (`DT-CLOCK-VALID?`):

1. Drain up to `BLK-MAX-TXS` transactions from the mempool, into a
   block stamped with the wall time
2. Finalize the block (compute the tx and state Merkle roots; the state
   is left as it was).  The block ends before the first transaction the
   state refuses (P22).
3. Seal with consensus proof (`CON-SEAL`)
4. Append to chain via `CHAIN-APPEND`, which verifies the block and
   applies its transactions to the state
5. Persist to block log and broadcast to peers.  The transaction the
   block was cut at is dropped, and those drained after it go back to
   the mempool (`MP-RETURN`).  When the chain refuses the block, every
   drained transaction goes back.  The slots no block or pool holds are
   then released.  The transaction the block was cut at is not given
   back: it would drain ahead of those after it again and cut the next
   block at the same place.

Until the clock is set it names no instant: a block stamped from it is
refused when it reads 0 and dated 1970 after that.  A node whose clock
is not set produces nothing, and its pool keeps its transactions.

### NODE-ENABLE-PRODUCE

```forth
NODE-ENABLE-PRODUCE  ( -- )
```

### NODE-DISABLE-PRODUCE

```forth
NODE-DISABLE-PRODUCE  ( -- )
```

---

## Persistence

New blocks are auto-saved to the XMEM block log when chain height
advances past `_NODE-LAST-SAVED`.  Uses `PST-SAVE-BLOCK` internally.

---

## Control

### NODE-STOP

```forth
NODE-STOP  ( -- )
```

Set state to `NODE-STOPPED` and call `SERVE-STOP` to shut down the
HTTP server.

### NODE-STATUS

```forth
NODE-STATUS  ( -- state )
```

Returns current node state (0/1/2).

---

## Concurrency

`NODE-INIT`, `NODE-STEP`, and `NODE-STOP` are wrapped with
`_node-guard`.  Sub-system calls each have their own guards, so the
node guard is held only for coordination logic.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `NODE-INIT` | `( port -- )` | Initialize all sub-systems |
| `NODE-RUN` | `( -- )` | Enter main loop |
| `NODE-STEP` | `( -- )` | One main loop iteration |
| `NODE-STOP` | `( -- )` | Signal shutdown |
| `NODE-STATUS` | `( -- state )` | Current daemon state |
| `NODE-ENABLE-PRODUCE` | `( -- )` | Enable block production |
| `NODE-DISABLE-PRODUCE` | `( -- )` | Disable block production |
| `NODE-STOPPED` | `( -- 0 )` | State constant |
| `NODE-RUNNING` | `( -- 1 )` | State constant |
| `NODE-SYNCING` | `( -- 2 )` | State constant |
