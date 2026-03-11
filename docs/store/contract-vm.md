# akashic-contract-vm — Blockchain Contract VM

Sandboxed Forth contract execution engine built on top of the ITC
(Interpreted Threaded Code) compiler.  Contracts are compiled from
Forth source, serialized as ITC images, stored in XMEM, and executed
in a bounded arena with gas metering and memory isolation.

```forth
REQUIRE store/contract-vm.f
```

`PROVIDED akashic-contract-vm` — depends on `akashic-itc`,
`akashic-state`, `akashic-block`, `akashic-consensus`, `akashic-tx`,
`akashic-sha3`, `akashic-guard`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Arena Layout](#arena-layout)
- [Fault Codes](#fault-codes)
- [Initialization](#initialization)
- [Deploy](#deploy)
- [Call](#call)
- [Gas Metering](#gas-metering)
- [Chain State Words](#chain-state-words)
- [Contract Storage](#contract-storage)
- [Bounds-Checked Memory](#bounds-checked-memory)
- [Return Data](#return-data)
- [Transaction Integration](#transaction-integration)
- [Whitelist](#whitelist)
- [Concurrency](#concurrency)
- [Constants](#constants)
- [Usage Example](#usage-example)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **ITC sandbox** | Contracts execute inside the ITC interpreter — only whitelisted words are accessible |
| **Arena isolation** | Each call allocates a fresh XMEM arena with separate data, code, and return-stack regions |
| **Gas metering** | Pre-dispatch hook charges gas per whitelisted opcode; exhaustion aborts cleanly |
| **Bounds-checked memory** | `@` / `!` / `C@` / `C!` inside contracts route through `VM-@` / `VM-!` which enforce data-region bounds |
| **Deterministic addressing** | Contract address = `SHA3-256(caller-addr ‖ nonce)` |
| **Image persistence** | Deploy compiles source → ITC image → permanent XMEM blob; call loads image into arena |
| **TX integration** | Hooks into `state.f` extension dispatch for deploy (type 5) and call (type 6) transactions |
| **Concurrency-safe** | All public API words wrapped with `WITH-GUARD` via `_vm-guard` |

---

## Arena Layout

Each `VM-CALL` / `VM-DEPLOY` allocates a single contiguous XMEM block
partitioned into three regions:

```
Offset   Size    Region          Purpose
──────   ──────  ──────────────  ──────────────────────────
  0      4096    Data region     Contract variables, VM-@ / VM-!
 4096    4096    Code region     ITC body loaded from image
 8192    2048    Return stack    ITC return stack for CALL/EXIT
──────
10240 total bytes (_VM-ARENA-TOTAL)
```

The data region is zeroed on allocation.  Code is CMOVE'd from the
stored ITC image.  The return stack is used exclusively by ITC-EXECUTE.

---

## Fault Codes

Extends the ITC fault range (0–4):

| Code | Constant | Meaning |
|---|---|---|
| 0  | *(success)* | No fault |
| 1  | `ITC-FAULT-BAD-OP` | Unknown opcode |
| 2  | `ITC-FAULT-STACK` | Stack overflow/underflow in ITC |
| 3  | `ITC-FAULT-ABORT` | Pre-dispatch hook returned false |
| 4  | `ITC-FAULT-COMPILE` | Compilation error |
| 10 | `VM-FAULT-OOB` | Out-of-bounds memory access |
| 11 | `VM-FAULT-GAS` | Gas exhausted |
| 12 | `VM-FAULT-NO-CODE` | Contract not found in code map |
| 13 | `VM-FAULT-DEPLOY` | Deployment / arena allocation error |
| 14 | `VM-FAULT-STORAGE` | Contract storage full |

---

## Initialization

### VM-INIT

```forth
VM-INIT  ( -- )
```

Initialize the contract VM subsystem.  Idempotent — skips if already
initialized.  Performs:

1. Populates the ITC whitelist with ~60 sandboxed words
2. Clears the code map (max 256 contracts)
3. Zeroes arena, return-data, and fault state
4. Hooks `_VM-TX-EXT` into `state.f`'s extension dispatch chain

Must be called once before any `VM-DEPLOY` or `VM-CALL`.

### VM-DESTROY

```forth
VM-DESTROY  ( -- )
```

Tear down the contract VM.  Restores the previous TX extension
handler, resets the ITC whitelist, and clears the code map.
Idempotent.

---

## Deploy

### VM-DEPLOY

```forth
VM-DEPLOY  ( src len -- contract-addr | 0 )
```

Compile Forth source into a contract and register it:

1. Allocate arena
2. `ITC-COMPILE` source into arena code region
3. `ITC-SAVE-IMAGE` → temporary XMEM buffer
4. Copy image to permanent XMEM blob
5. Derive contract address: `SHA3-256(caller-addr ‖ nonce)`
6. Register in code map: `(address, code-ptr, code-len)`
7. Free temp buffer and arena

Returns the 32-byte contract address buffer (`_VM-ADDR-OUT`) on
success, or 0 on failure (compilation error, XMEM exhaustion, or
code map full).

**Note:** The returned pointer is to a shared buffer.  Copy the
32 bytes if you need to persist the address across multiple deploys.

---

## Call

### VM-CALL

```forth
VM-CALL  ( contract-addr entry-addr entry-len gas -- fault-code )
```

Execute a named entry point of a deployed contract:

1. Look up `contract-addr` in code map (32-byte key comparison)
2. Allocate arena
3. `ITC-LOAD-IMAGE` from stored blob
4. Copy body → arena code region
5. Resolve entry name → IP via `_ITC-ENT-FIND`
6. Install gas hook and data-region pointers
7. `ITC-EXECUTE` with arena return stack
8. Clean up hook, free arena
9. If gas exhausted, override fault to `VM-FAULT-GAS`

Parameters:
- `contract-addr` — 32-byte address (from `VM-DEPLOY`)
- `entry-addr entry-len` — name of entry point (e.g., `S" inc"`)
- `gas` — maximum gas units (use `VM-DEFAULT-GAS` for 1,000,000)

Returns a fault code (0 = success).

---

## Gas Metering

Gas is charged per whitelisted opcode dispatch.  Each registered word
has a per-opcode cost stored in `_VM-GAS-TABLE` (1 byte per slot).
Pseudo-ops (LIT, BRANCH, EXIT, DO/LOOP) are **not** charged — only
whitelist dispatches trigger the gas hook.

### Cost Table

| Category | Gas | Words |
|---|---|---|
| Stack ops | 1 | `DUP DROP SWAP OVER ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER` |
| Arithmetic | 1 | `+ - * / MOD /MOD NEGATE ABS MIN MAX 1+ 1-` |
| Comparison | 1 | `= <> < > 0= 0< 0>` |
| Logic | 1 | `AND OR XOR INVERT LSHIFT RSHIFT` |
| Memory | 2 | `@ ! C@ C!` (bounds-checked) |
| Output | 1–5 | `. EMIT CR SPACE` (1), `TYPE` (5) |
| Chain state | 1–20 | `VM-CALLER VM-SELF VM-BLOCK# VM-BLOCK-TIME` (1), `VM-BALANCE VM-SELF-BALANCE VM-LOG` (5), `VM-SHA3` (20) |
| Storage | 5–20 | `VM-ST-HAS?` (5), `VM-ST-GET` (10), `VM-ST-PUT` (20) |
| Transfer | 20 | `VM-TRANSFER` |
| Return/Revert | 1 | `VM-RETURN VM-REVERT` |

### VM-GAS-USED

```forth
VM-GAS-USED  ( -- n )
```

Total gas consumed by the last `VM-CALL`.

---

## Chain State Words

Available inside contracts via the whitelist:

| Word | Stack | Gas | Description |
|---|---|---|---|
| `VM-BALANCE` | `( -- n )` | 5 | Caller's account balance |
| `VM-SELF-BALANCE` | `( -- n )` | 5 | Contract's own balance |
| `VM-CALLER` | `( -- addr )` | 1 | 32-byte caller address |
| `VM-SELF` | `( -- addr )` | 1 | 32-byte contract address |
| `VM-BLOCK#` | `( -- n )` | 1 | Current block height |
| `VM-BLOCK-TIME` | `( -- t )` | 1 | Current block timestamp |
| `VM-SHA3` | `( addr len -- hash-addr 32 )` | 20 | SHA3-256 hash |
| `VM-LOG` | `( addr len -- )` | 5 | Emit log (TYPE) |
| `VM-RETURN` | `( addr len -- )` | 1 | Set return data (max 256 bytes) |
| `VM-REVERT` | `( addr len -- )` | 1 | Set return data and abort |
| `VM-TRANSFER` | `( amount to-addr -- flag )` | 20 | Balance transfer (MVP stub) |

---

## Contract Storage

Per-contract key→value store, allocated lazily in XMEM on first write.
Layout: `[8B count][256 × (8B key, 8B value)]` = 4104 bytes.

### VM-ST-GET

```forth
VM-ST-GET  ( key -- val flag )
```

Look up `key` in the executing contract's storage.  Returns `val -1`
if found, `0 0` if not found or no storage allocated.  Gas cost: 10.

### VM-ST-PUT

```forth
VM-ST-PUT  ( val key -- )
```

Store `val` under `key`.  Allocates storage region on first use.
Updates existing slot or appends new.  Faults with
`VM-FAULT-STORAGE` if all 256 slots are full.  Gas cost: 20.

### VM-ST-HAS?

```forth
VM-ST-HAS?  ( key -- flag )
```

Check if `key` exists in storage.  Gas cost: 5.

---

## Bounds-Checked Memory

Inside contracts, `@` and `!` are replaced with bounds-checked
versions that only access the arena data region:

### VM-@

```forth
VM-@  ( addr -- n )
```

Fetch a cell from the data region.  Faults with `VM-FAULT-OOB` if
`addr` is outside `[arena-base, arena-base + 4096)`.

### VM-!

```forth
VM-!  ( n addr -- )
```

Store a cell in the data region.  Bounds-checked.  Advances the
high-water mark for lazy zero semantics.

### VM-C@ / VM-C!

Byte-level equivalents with the same bounds checking.

---

## Return Data

### VM-RETURN-DATA

```forth
VM-RETURN-DATA  ( -- addr len )
```

Retrieve the return data buffer and length set by the last
`VM-RETURN` call inside a contract.  Maximum 256 bytes.

---

## Transaction Integration

The VM hooks into `state.f`'s transaction extension dispatch.
Two transaction types are handled:

| Type | `data[0]` | Format | Action |
|---|---|---|---|
| 5 (`TX-DEPLOY`) | Deploy | `[5][source...]` | Compile & register contract |
| 6 (`TX-CALL`) | Call | `[6][32B addr][entry-name...]` | Execute named entry |

Unrecognized types are forwarded to the previous extension handler,
preserving the chain (e.g., staking types 3/4 from `consensus.f`).

---

## Whitelist

The ITC whitelist is populated by `_VM-REGISTER-CORE` during
`VM-INIT`.  Only whitelisted words can be used inside contracts.
Attempting to use non-whitelisted words causes a compile error.

The full whitelist includes ~60 words across the categories listed
in the [Gas Metering](#gas-metering) section.  Notable exclusions
for sandboxing:

- **No `BYE`** — cannot terminate the host
- **No `REQUIRE`** — cannot load files
- **No raw `@` / `!`** — replaced by bounds-checked `VM-@` / `VM-!`
- **No `HERE` / `ALLOT`** — cannot manipulate dictionary
- **No `EXECUTE`** — cannot call arbitrary XTs

---

## Concurrency

All public API words are serialized through `_vm-guard`
(spinning guard via `WITH-GUARD`).  Internal ITC calls are
additionally serialized by `_itc-guard`.  Both guards support
same-task re-entrant (recursive) acquisition.

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `VM-DEFAULT-GAS` | 1,000,000 | Default gas limit for calls |
| `VM-FAULT-OOB` | 10 | Out-of-bounds memory fault |
| `VM-FAULT-GAS` | 11 | Gas exhaustion fault |
| `VM-FAULT-NO-CODE` | 12 | Contract not found |
| `VM-FAULT-DEPLOY` | 13 | Deployment error |
| `VM-FAULT-STORAGE` | 14 | Contract storage full |
| `TX-DEPLOY` | 5 | Deploy transaction type |
| `TX-CALL` | 6 | Call transaction type |
| `_VM-ARENA-DATA-SZ` | 4096 | Data region size |
| `_VM-ARENA-CODE-SZ` | 4096 | Code region size |
| `_VM-ARENA-RSTK-SZ` | 2048 | Return stack region size |
| `_VM-ARENA-TOTAL` | 10240 | Total arena allocation |
| `_VM-CODE-MAX` | 256 | Max deployed contracts |
| `_VM-STORE-SLOTS` | 256 | Max storage slots per contract |

---

## Usage Example

```forth
\ Initialize the VM
VM-INIT

\ Set caller address (normally done by TX processing)
_VM-CALLER-ADDR 32 170 FILL

\ Deploy a contract with two entry points
S" : inc 1+ ; : double DUP + ;" VM-DEPLOY
\ -> contract-addr (or 0 on failure)

\ Call the "inc" entry point
DUP S" inc" VM-DEFAULT-GAS VM-CALL
\ -> 0 (success)

\ Call the "double" entry point
DUP S" double" VM-DEFAULT-GAS VM-CALL
\ -> 0 (success)

\ Check gas usage
VM-GAS-USED .   \ prints gas consumed

\ Tear down
VM-DESTROY
```

---

## Quick Reference

```
VM-INIT         ( -- )                            Initialize VM subsystem
VM-DESTROY      ( -- )                            Tear down VM
VM-DEPLOY       ( src len -- addr | 0 )           Compile & register contract
VM-CALL         ( addr eaddr elen gas -- fault )  Execute contract entry
VM-GAS-USED     ( -- n )                          Gas consumed by last call
VM-RETURN-DATA  ( -- addr len )                   Last call's return data
VM-CODE-COUNT   ( -- n )                          Number of deployed contracts
VM-DEFAULT-GAS  ( -- n )                          Default gas constant (1M)
VM-FAULT-OOB    ( -- n )                          Fault code: out-of-bounds
VM-FAULT-GAS    ( -- n )                          Fault code: gas exhausted
VM-FAULT-NO-CODE ( -- n )                         Fault code: contract not found
VM-FAULT-DEPLOY ( -- n )                          Fault code: deploy error
VM-FAULT-STORAGE ( -- n )                         Fault code: storage full
```
