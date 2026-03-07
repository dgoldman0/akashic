# akashic-state — Blockchain World State

Account-based world state with 256-leaf SHA3-256 Merkle commitment.
Accounts are sorted by address for O(log n) binary-search lookup.

```forth
REQUIRE state.f
```

`PROVIDED akashic-state` — depends on `akashic-sha3`, `akashic-merkle`,
`akashic-tx`, `akashic-fmt`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Account Entry Layout](#account-entry-layout)
- [Initialization](#initialization)
- [Account Lookup](#account-lookup)
- [Account Creation](#account-creation)
- [Accessors](#accessors)
- [Transaction Application](#transaction-application)
- [Staking Extension](#staking-extension)
- [Merkle Root](#merkle-root)
- [Snapshot / Restore](#snapshot--restore)
- [Constants](#constants)
- [Usage Example](#usage-example)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Sorted table** | Accounts sorted by 32-byte address (SHA3-256 of public key) for binary search |
| **Fixed-size entries** | 72 bytes per account — includes Phase 5 staking fields from day one |
| **Merkle commitment** | 256-leaf SHA3-256 Merkle tree rebuilt per block for state root |
| **Extension dispatch** | Pluggable `_ST-TX-EXT-XT` callback for staking and future tx types |
| **Concurrency-safe** | Public API wrapped with `WITH-GUARD` |
| **Not reentrant** | Module-level VARIABLEs for scratch state |

---

## Account Entry Layout

Each account is a 72-byte record:

```
Offset  Size    Field         Description
------  ------  -----------   -----------
  0     32      address       SHA3-256 of Ed25519 public key
 32      8      balance       Available balance (u64)
 40      8      nonce         Transaction sequence number (u64)
 48      8      staked-amt    Staked amount for PoS (u64)
 56      8      unstake-ht    Height when unstaking initiated (u64)
 64      8      last-blk      Height of last staking operation (u64)
------
 72 total (8-byte aligned)
```

Staking fields (offsets 48–71) are zeroed until `consensus.f` activates
PoS logic.  The 72-byte layout is fixed from genesis to avoid migration.

---

## Initialization

### ST-INIT

```forth
ST-INIT  ( -- )
```

Zero all accounts, reset count to 0, rebuild the Merkle tree.

---

## Account Lookup

### ST-LOOKUP

```forth
ST-LOOKUP  ( addr -- entry | 0 )
```

Find an account by 32-byte address.  Returns the entry base address,
or 0 if not found.  Uses binary search over the sorted table.

### ST-ADDR-FROM-KEY

```forth
ST-ADDR-FROM-KEY  ( pubkey addr -- )
```

Convenience helper: `SHA3-256(pubkey)` → 32-byte account address.
Use before `ST-LOOKUP`, `ST-CREATE`, `ST-BALANCE@`, `ST-NONCE@`.

---

## Account Creation

### ST-CREATE

```forth
ST-CREATE  ( addr balance -- flag )
```

Create a new account with the given address and initial balance.
Returns TRUE on success, FALSE if the table is full (256 max) or the
address already exists.  Maintains sorted order via shift-right insertion.

---

## Accessors

### ST-BALANCE@

```forth
ST-BALANCE@  ( addr -- balance )
```

Read account balance.  Returns 0 if the account does not exist.

### ST-NONCE@

```forth
ST-NONCE@  ( addr -- nonce )
```

Read account nonce.  Returns 0 if the account does not exist.

### ST-STAKED@

```forth
ST-STAKED@  ( addr -- amount )
```

Read staked amount.  Returns 0 if the account does not exist.

### ST-UNSTAKE-H@

```forth
ST-UNSTAKE-H@  ( addr -- height )
```

Read unstake-initiation height.  Returns 0 if the account does not
exist or has not begun unstaking.

### ST-COUNT

```forth
ST-COUNT  ( -- n )
```

Number of active accounts.

### ST-ENTRY

```forth
ST-ENTRY  ( idx -- addr )
```

Raw entry base address by table index (0-based).

---

## Transaction Application

### ST-APPLY-TX

```forth
ST-APPLY-TX  ( tx -- flag )
```

Validate and apply a transaction to the world state:

1. Verify Ed25519/SPHINCS+ signature
2. Hash sender public key → address; sender must exist
3. Nonce must match
4. **Extension dispatch:** If `data_len ≥ 1` and `data[0] ≥ 3`, call
   the extension handler (`_ST-TX-EXT-XT`).  If the handler returns
   TRUE, nonce is bumped and the function returns.
5. Balance ≥ amount
6. Hash recipient public key → address
7. If self-transfer, just bump nonce
8. Credit recipient (create if new), debit sender, bump nonce

Returns TRUE on success, FALSE on any validation failure (no state change).

### ST-VERIFY-TX

```forth
ST-VERIFY-TX  ( tx -- flag )
```

Validate a transaction against current state without mutating.
Same checks as `ST-APPLY-TX` steps 1–5.

### ST-SET-HEIGHT

```forth
ST-SET-HEIGHT  ( h -- )
```

Set the current block height.  Must be called before applying staking
transactions so that lock-period logic has the correct height.

---

## Staking Extension

The staking extension hook (`_ST-TX-EXT-XT`) is wired up by
`consensus.f` at load time.  It handles two transaction types:

| Type | `data[0]` | Constant | Effect |
|---|---|---|---|
| Stake | 3 | `TX-STAKE` | Move `amount` from balance → staked-amt; record height |
| Unstake | 4 | `TX-UNSTAKE` | Move all staked back to balance (if lock period expired) |

The lock period defaults to 64 blocks (`_ST-LOCK-PERIOD`), overridden
by `consensus.f` to `CON-POS-LOCK-PERIOD` (also 64) at load time.

---

## Merkle Root

### ST-ROOT

```forth
ST-ROOT  ( -- addr )
```

Rebuild the 256-leaf Merkle tree from current state and return the
32-byte root address.  Call once per block finalization, not per
transaction.

---

## Snapshot / Restore

### ST-SNAPSHOT

```forth
ST-SNAPSHOT  ( dst -- )
```

Copy the full account table + count to a buffer.
Total size: 18,440 bytes (256 × 72 + 8).

### ST-RESTORE

```forth
ST-RESTORE  ( src -- )
```

Restore the account table + count from a previously saved snapshot.
Used by `BLK-VERIFY` for non-destructive block validation (apply
transactions tentatively, check state root, then restore).

### ST-SNAPSHOT-SIZE

```forth
ST-SNAPSHOT-SIZE  ( -- 18440 )
```

Size of a snapshot buffer in bytes.

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `ST-MAX-ACCOUNTS` | 256 | Maximum accounts in the table |
| `ST-ENTRY-SIZE` | 72 | Bytes per account entry |
| `ST-ADDR-LEN` | 32 | Account address length (SHA3-256 hash) |
| `ST-SNAPSHOT-SIZE` | 18440 | Snapshot buffer size |

---

## Usage Example

```forth
\ Initialize state
ST-INIT

\ Create an account
CREATE alice-key 32 ALLOT   \ Ed25519 public key
CREATE alice-addr 32 ALLOT
alice-key alice-addr ST-ADDR-FROM-KEY
alice-addr 1000 ST-CREATE   \ -> TRUE

\ Query
alice-addr ST-BALANCE@      \ -> 1000
alice-addr ST-NONCE@        \ -> 0

\ Merkle commitment
ST-ROOT                     \ -> 32-byte root address
```

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `ST-INIT` | `( -- )` | Zero state, rebuild tree |
| `ST-LOOKUP` | `( addr -- entry \| 0 )` | Find account by address |
| `ST-CREATE` | `( addr balance -- flag )` | Create new account |
| `ST-BALANCE@` | `( addr -- balance )` | Read balance |
| `ST-NONCE@` | `( addr -- nonce )` | Read nonce |
| `ST-STAKED@` | `( addr -- amount )` | Read staked amount |
| `ST-UNSTAKE-H@` | `( addr -- height )` | Read unstake height |
| `ST-APPLY-TX` | `( tx -- flag )` | Validate + apply transaction |
| `ST-VERIFY-TX` | `( tx -- flag )` | Validate without applying |
| `ST-ROOT` | `( -- addr )` | Compute Merkle root |
| `ST-ADDR-FROM-KEY` | `( pubkey addr -- )` | Hash pubkey → address |
| `ST-COUNT` | `( -- n )` | Number of active accounts |
| `ST-ENTRY` | `( idx -- addr )` | Raw entry by index |
| `ST-SET-HEIGHT` | `( h -- )` | Set current block height |
| `ST-SNAPSHOT` | `( dst -- )` | Save state to buffer |
| `ST-RESTORE` | `( src -- )` | Restore state from buffer |
