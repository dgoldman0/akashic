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

Production is disabled by default.  When enabled and the node is
synced (`SYNC-IDLE`):

1. Drain up to `BLK-MAX-TXS` transactions from the mempool
2. Finalize the block (compute Merkle roots, apply state transitions)
3. Seal with consensus proof (`CON-SEAL`)
4. Append to chain via `CHAIN-APPEND`
5. Persist to block log and broadcast to peers

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
