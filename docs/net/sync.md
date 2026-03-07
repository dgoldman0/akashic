# akashic-sync — Block Synchronisation for KDOS / Megapad-64

Gap-driven sequential block sync.  Detects when the local chain is
behind a peer, then requests missing blocks one at a time via gossiп.
Uses a deferred-request pattern to avoid re-entering the gossip guard
from callbacks.

```forth
REQUIRE sync.f
```

`PROVIDED akashic-sync` — depends on `akashic-block`, `akashic-gossip`,
`akashic-guard`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Sync States](#sync-states)
- [Initialization](#initialization)
- [Main Loop Integration](#main-loop-integration)
- [Announcement Handling](#announcement-handling)
- [Response Handling](#response-handling)
- [Status Handling](#status-handling)
- [Queries](#queries)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Sequential sync** | Requests one block at a time — simple, avoids out-of-order issues |
| **Deferred requests** | Callbacks set a flag; `SYNC-STEP` (main loop) does the actual network call |
| **Guard safety** | Gossip callbacks execute inside gossip's guard — sync must NOT call gossip words from within them |
| **Retry + stall** | 5 retries before declaring STALLED; manual `SYNC-RESET` to recover |
| **Target tracking** | Announcements update the sync target if a higher height is seen |

---

## Sync States

| Constant | Value | Meaning |
|---|---|---|
| `SYNC-IDLE` | 0 | Fully synced, waiting for announcements |
| `SYNC-ACTIVE` | 1 | Actively requesting/processing blocks |
| `SYNC-STALLED` | 2 | Too many retries, needs manual reset |

---

## Initialization

### SYNC-INIT

```forth
SYNC-INIT  ( -- )
```

Reset state to IDLE, wire callbacks into gossip:

- `_SYNC-ON-ANN` → `GSP-ON-BLK-ANN-XT`
- `_SYNC-ON-RSP` → `GSP-ON-BLK-RSP-XT`
- `_SYNC-ON-STATUS` → `GSP-ON-STATUS-XT`

---

## Main Loop Integration

### SYNC-STEP

```forth
SYNC-STEP  ( -- )
```

Called from the node's main loop.  If state is ACTIVE and the
deferred-request flag is set, clears the flag and calls
`GSP-REQUEST-BLK` for the next needed height.  If we've reached
the target, transitions to IDLE.

This is the **only** place where sync calls gossip — safely outside
the gossip guard.

---

## Announcement Handling

When a peer announces a block height greater than our chain:

1. If IDLE → transition to ACTIVE, record target+peer, set deferred flag.
2. If ACTIVE and higher target → update target, keep syncing.
3. If at or past the announced height → ignore.

---

## Response Handling

When block data arrives (via `GSP-ON-BLK-RSP-XT`):

1. Decode block header with `BLK-DECODE`.
2. Attempt `CHAIN-APPEND` (validates + applies state).
3. On success: reset retries, set deferred flag for next block (or IDLE if complete).
4. On failure: increment retries. If ≥ 5 → STALLED.

---

## Status Handling

Identical to announcement — a peer's status message carries their
chain height, triggering sync if we're behind.

---

## Queries

### SYNC-STATUS

```forth
SYNC-STATUS  ( -- state )
```

Current sync state (0=IDLE, 1=ACTIVE, 2=STALLED).

### SYNC-TARGET

```forth
SYNC-TARGET  ( -- height )
```

The chain height we are syncing towards.

### SYNC-PEER

```forth
SYNC-PEER  ( -- id )
```

The peer id we are currently syncing from.

### SYNC-PROGRESS

```forth
SYNC-PROGRESS  ( -- current target )
```

Convenience: returns `CHAIN-HEIGHT` and `SYNC-TARGET` for monitoring.

### SYNC-RESET

```forth
SYNC-RESET  ( -- )
```

Force state back to IDLE.  Clears retries and deferred flag.

---

## Concurrency

Sync has no guard of its own.  The callbacks execute inside gossip's
guard.  `SYNC-STEP` runs from the main loop with no guard held.
This two-phase design (flag in callback → action in main loop) is the
key to avoiding guard re-entry deadlocks.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `SYNC-INIT` | `( -- )` | Wire callbacks, reset state |
| `SYNC-STEP` | `( -- )` | Make next request if needed |
| `SYNC-RESET` | `( -- )` | Force back to IDLE |
| `SYNC-STATUS` | `( -- state )` | Current sync state |
| `SYNC-TARGET` | `( -- height )` | Target height |
| `SYNC-PEER` | `( -- id )` | Peer we sync from |
| `SYNC-PROGRESS` | `( -- cur tgt )` | Chain height + target |
| `SYNC-IDLE` | `( -- 0 )` | State constant |
| `SYNC-ACTIVE` | `( -- 1 )` | State constant |
| `SYNC-STALLED` | `( -- 2 )` | State constant |
