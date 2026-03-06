# Blockchain Library — Roadmap

A minimal, STARK-provable blockchain for KDOS / Megapad-64, built
entirely on existing Akashic infrastructure.  The core thesis: most
of the hard work is already done.  What remains is one genuinely
difficult module (digital signatures), followed by structural glue
that wires existing pieces together.

**Date:** 2026-03-06
**Status:** Living document

---

## Table of Contents

- [Current State — What Already Exists](#current-state--what-already-exists)
- [Gap Analysis](#gap-analysis)
- [Architecture Principles](#architecture-principles)
- [Phase 1 — ed25519.f: Digital Signatures](#phase-1--ed25519f-digital-signatures)
- [Phase 2 — tx.f: Transaction Structure](#phase-2--txf-transaction-structure)
- [Phase 3 — state.f: World State](#phase-3--statef-world-state)
- [Phase 4 — block.f: Block Structure & Chain](#phase-4--blockf-block-structure--chain)
- [Phase 5 — consensus.f: Consensus Mechanism](#phase-5--consensusf-consensus-mechanism)
- [Phase 6 — mempool.f: Transaction Pool](#phase-6--mempoolf-transaction-pool)
- [Dependency Graph](#dependency-graph)
- [Implementation Order](#implementation-order)
- [Design Constraints](#design-constraints)
- [Testing Strategy](#testing-strategy)

---

## Current State — What Already Exists

### Cryptographic Foundation

| Module | Words | Tests | Role in blockchain |
|--------|------:|------:|-------------------|
| sha3.f | 62 | 62 | Block hashing, address derivation, Merkle internals |
| sha256.f | — | — | Optional: Bitcoin-compatible hashing |
| sha512.f | — | — | Ed25519 internal hash |
| crc.f | 32 | 32 | Packet-level checksums |
| random.f | 18 | 18 | Nonce generation, key generation entropy |

### Field Arithmetic & Proofs

| Module | Words | Tests | Role in blockchain |
|--------|------:|------:|-------------------|
| baby-bear.f | 38 | 38 | STARK field arithmetic |
| field.f | 43 | 43 | Generic modular arithmetic |
| ntt.f | 27 | 27 | Polynomial operations for STARKs |
| merkle.f | 20 | 20 | Transaction inclusion proofs, state commitments |
| stark-air.f | 28 | 28 | Constraint descriptors for validity proofs |
| stark.f | 32 | 32 | Full STARK prover/verifier — the key enabler |

### Serialization

| Module | Role in blockchain |
|--------|-------------------|
| cbor.f | Transaction encoding, block encoding |
| dag-cbor.f | Content-addressed block references (IPLD-compatible) |
| json.f | RPC interface, debug output |

### Networking & Web

| Module | Role in blockchain |
|--------|-------------------|
| http.f, headers.f, uri.f | JSON-RPC node interface |
| ws.f | Block/tx gossip via WebSocket |
| server.f, router.f, request.f, response.f | Full RPC server |
| base64.f | Encoding signatures/hashes in API responses |

### Data Structures

| Module | Role in blockchain |
|--------|-------------------|
| table.f | Index structures |
| string.f | Address formatting |
| datetime.f | Block timestamps |
| sort.f | Mempool ordering |

### Concurrency

| Module | Role in blockchain |
|--------|-------------------|
| channel.f | Block propagation pipeline |
| semaphore.f, rwlock.f | Concurrent state access |
| future.f, par.f | Parallel tx validation |
| conc-map.f | Concurrent UTXO / account lookup |

**Bottom line:** hashing ✓, commitments ✓, validity proofs ✓,
serialization ✓, networking ✓, concurrency ✓.  The one critical
missing piece is **digital signatures**.

---

## Gap Analysis

| Gap | Impact | Complexity |
|-----|--------|-----------|
| No elliptic curve arithmetic | Cannot sign or verify anything | Hard (~500 lines) |
| No transaction format | No unit of transfer | Easy (~150 lines) |
| No persistent state model | Cannot track balances/accounts | Medium (~250 lines) |
| No block structure | Cannot build a chain | Medium (~200 lines) |
| No consensus mechanism | Cannot agree on block validity | Easy–Medium (~150 lines) |
| No mempool | Cannot queue pending transactions | Easy (~100 lines) |

Total new code: ~1,350 lines across 6 modules.  Roughly 60% of that
is ed25519.f.

---

## Architecture Principles

| Principle | Decision |
|-----------|----------|
| **Signature scheme** | Ed25519 — deterministic, no branching hazards, constant-time, uses existing SHA-512 |
| **Serialization** | CBOR everywhere — transactions, blocks, state entries.  DAG-CBOR for content addressing |
| **Hashing** | SHA3-256 for all chain hashing (block hash, address, Merkle).  Consistent with STARK internals |
| **Proof system** | STARK validity proofs optional per block — prover can attach proof that all state transitions are valid |
| **State model** | Account-based (not UTXO) — simpler for a 256-entry world, maps cleanly to a Merkle tree |
| **Block size** | 256 transactions max per block — matches STARK trace size for provability |
| **Consensus** | Pluggable — PoW (trivial), STARK-validity (already built), PoA (signature check) |
| **Not re-entrant** | Same as all Akashic modules — single-threaded per core |
| **No floating point** | All values are integers (Baby Bear field elements or 64-bit) |

---

## Phase 1 — ed25519.f: Digital Signatures

**Prefix:** `ED25519-`
**Depends on:** sha512.f, field.f
**Estimated size:** ~500 lines
**Difficulty:** Hard

### Why Ed25519

- Deterministic signatures (no nonce reuse vulnerability)
- Fixed curve parameters — no negotiation
- Constant-time scalar multiply is achievable
- SHA-512 already exists as a module
- 32-byte keys, 64-byte signatures — compact
- Widely used: Solana, AT Protocol, SSH, Signal

### What to Build

#### 1.1 Curve Constants

Ed25519 operates on the twisted Edwards curve
$-x^2 + y^2 = 1 + d \cdot x^2 \cdot y^2$ over $\text{GF}(2^{255} - 19)$.

```
p  = 2^255 - 19                     (field prime)
d  = -121665/121666 mod p            (curve constant)
L  = 2^252 + 27742317777372353535851937790883648493  (group order)
B  = (Bx, By)                       (base point)
```

Need multi-precision arithmetic for 256-bit integers — the 512-bit
Field ALU MMIO device handles this if available, otherwise software
bigint with 4 × 64-bit limbs.

#### 1.2 Field Arithmetic (mod p)

| Word | Stack | Description |
|------|-------|-------------|
| `ED-F+` | `( a b -- r )` | Addition mod p |
| `ED-F-` | `( a b -- r )` | Subtraction mod p |
| `ED-F*` | `( a b -- r )` | Multiplication mod p |
| `ED-FINV` | `( a -- r )` | Inversion mod p (Fermat) |
| `ED-FSQRT` | `( a -- r flag )` | Square root mod p |

Values stored as 4-cell (32-byte) buffers.

#### 1.3 Point Operations

| Word | Stack | Description |
|------|-------|-------------|
| `ED-PT-ADD` | `( P Q R -- )` | R = P + Q (extended coordinates) |
| `ED-PT-DBL` | `( P R -- )` | R = 2P |
| `ED-PT-MUL` | `( scalar P R -- )` | R = scalar × P (double-and-add) |
| `ED-PT-ENC` | `( P buf -- )` | Encode point to 32 bytes |
| `ED-PT-DEC` | `( buf P -- flag )` | Decode 32 bytes to point |

Extended coordinates $(X, Y, Z, T)$ where $x = X/Z$, $y = Y/Z$,
$T = X \cdot Y / Z$.  No divisions during add/double.

#### 1.4 Key Generation

| Word | Stack | Description |
|------|-------|-------------|
| `ED25519-KEYGEN` | `( seed pub priv -- )` | Derive keypair from 32-byte seed |

Uses SHA-512 internally (hash seed → clamp → scalar multiply
base point).

#### 1.5 Sign & Verify

| Word | Stack | Description |
|------|-------|-------------|
| `ED25519-SIGN` | `( msg len priv pub sig -- )` | Sign message → 64-byte signature |
| `ED25519-VERIFY` | `( msg len pub sig -- flag )` | Verify signature → TRUE/FALSE |

Sign: $r = \text{SHA-512}(\text{prefix} \| \text{msg})$,
$R = r \cdot B$, $S = r + \text{SHA-512}(R \| A \| \text{msg}) \cdot a$.
Verify: check $8 \cdot S \cdot B = 8 \cdot R + 8 \cdot \text{SHA-512}(R \| A \| \text{msg}) \cdot A$.

#### 1.6 Design Decisions

- **Multi-precision via Field ALU:** Megapad-64 has a 512-bit
  Field ALU MMIO accelerator.  If the modulus can be loaded as
  $p = 2^{255} - 19$, use it for all mod-p arithmetic.  Fallback:
  4-limb software with `UM*` and carry chains.
- **Constant-time scalar multiply:** Use a fixed-window or
  Montgomery ladder to avoid timing side channels.  Not critical
  for emulator but correct-by-construction for eventual hardware.
- **No heap allocation:** All points and scalars in stack buffers
  or `CREATE`/`ALLOT` regions.

### Testing

- Known test vectors from RFC 8032 (empty message, 1-byte, 1023-byte)
- Roundtrip: keygen → sign → verify → TRUE
- Wrong-key verify → FALSE
- Corrupted signature → FALSE
- Batch: sign 16 different messages, verify all
- Edge cases: low-order points, non-canonical encodings

---

## Phase 2 — tx.f: Transaction Structure

**Prefix:** `TX-`
**Depends on:** ed25519.f, sha3.f, cbor.f
**Estimated size:** ~150 lines
**Difficulty:** Easy

### Transaction Format

```
Transaction (CBOR map):
  "from"    : 32 bytes  (sender public key)
  "to"      : 32 bytes  (recipient public key)
  "amount"  : u64       (transfer amount)
  "nonce"   : u64       (sender's sequence number)
  "data"    : bytes     (optional payload, 0–256 bytes)
  "sig"     : 64 bytes  (Ed25519 signature over hash of above fields)
```

Transaction hash = SHA3-256 of CBOR-encoded fields (excluding sig).

### API

| Word | Stack | Description |
|------|-------|-------------|
| `TX-INIT` | `( tx -- )` | Zero a transaction buffer |
| `TX-SET-FROM` | `( pubkey tx -- )` | Set sender |
| `TX-SET-TO` | `( pubkey tx -- )` | Set recipient |
| `TX-SET-AMOUNT` | `( amount tx -- )` | Set transfer amount |
| `TX-SET-NONCE` | `( nonce tx -- )` | Set sequence number |
| `TX-SET-DATA` | `( addr len tx -- )` | Set optional payload |
| `TX-HASH` | `( tx hash -- )` | Compute SHA3-256 of unsigned fields |
| `TX-SIGN` | `( tx priv pub -- )` | Sign transaction in-place |
| `TX-VERIFY` | `( tx -- flag )` | Verify signature against from-key |
| `TX-ENCODE` | `( tx buf -- len )` | Serialize to CBOR |
| `TX-DECODE` | `( buf len tx -- flag )` | Deserialize from CBOR |

### Size Budget

Transaction buffer: 32 (from) + 32 (to) + 8 (amount) + 8 (nonce) +
2 (data-len) + 256 (data) + 64 (sig) = 402 bytes.  Round to 408
(8-byte aligned).  `CREATE TX-BUF 408 ALLOT`.

---

## Phase 3 — state.f: World State

**Prefix:** `ST-`
**Depends on:** merkle.f, sha3.f
**Estimated size:** ~250 lines
**Difficulty:** Medium

### State Model

Account-based.  Each account is identified by a 32-byte public key
(the address) and stores:

```
Account entry (48 bytes):
  +0   32 bytes   address (SHA3-256 of public key)
  +32  8 bytes    balance (u64)
  +40  8 bytes    nonce (u64, incremented on each send)
```

### Storage

Fixed-size account table: up to 256 accounts (matches Merkle leaf
count and STARK trace size).  Sorted by address for binary search.

A 256-leaf Merkle tree commits to the state — each leaf is
SHA3-256 of the account entry.  The state root goes into the
block header.

### API

| Word | Stack | Description |
|------|-------|-------------|
| `ST-INIT` | `( -- )` | Zero all accounts, reset Merkle tree |
| `ST-LOOKUP` | `( addr -- entry\|0 )` | Find account by address |
| `ST-CREATE` | `( addr balance -- flag )` | Create new account |
| `ST-BALANCE@` | `( addr -- balance )` | Read balance (0 if not found) |
| `ST-NONCE@` | `( addr -- nonce )` | Read nonce (0 if not found) |
| `ST-APPLY-TX` | `( tx -- flag )` | Apply transaction: check sig, nonce, balance; update state |
| `ST-ROOT` | `( -- hash-addr )` | Compute and return state Merkle root |
| `ST-VERIFY-TX` | `( tx -- flag )` | Validate tx without applying (dry run) |

### State Transition Integrity

`ST-APPLY-TX` checks:
1. Signature valid (`TX-VERIFY`)
2. Sender exists
3. Nonce matches sender's current nonce
4. Balance ≥ amount
5. Recipient exists (auto-create if not)

On success: debit sender, credit recipient, increment sender nonce.
On failure: no state change.

---

## Phase 4 — block.f: Block Structure & Chain

**Prefix:** `BLK-`
**Depends on:** tx.f, state.f, merkle.f, sha3.f, cbor.f
**Estimated size:** ~200 lines
**Difficulty:** Medium

### Block Format

```
Block Header (CBOR map):
  "version"    : u8        (protocol version, initially 1)
  "height"     : u64       (block number, 0 = genesis)
  "prev_hash"  : 32 bytes  (SHA3-256 of previous block header)
  "state_root" : 32 bytes  (Merkle root of world state after applying txs)
  "tx_root"    : 32 bytes  (Merkle root of transaction hashes)
  "timestamp"  : u64       (Unix seconds)
  "proof"      : bytes     (consensus-specific: PoW nonce, STARK proof ref, or PoA sig)

Block Body:
  "txs"        : array of up to 256 encoded transactions
```

Block hash = SHA3-256 of CBOR-encoded header.

### API

| Word | Stack | Description |
|------|-------|-------------|
| `BLK-INIT` | `( blk -- )` | Initialize empty block |
| `BLK-SET-PREV` | `( hash blk -- )` | Set previous block hash |
| `BLK-ADD-TX` | `( tx blk -- flag )` | Append transaction (fail if full) |
| `BLK-FINALIZE` | `( blk -- )` | Compute tx Merkle root, apply txs to state, store state root |
| `BLK-HASH` | `( blk hash -- )` | Compute block hash |
| `BLK-VERIFY` | `( blk prev-hash -- flag )` | Full block validation |
| `BLK-ENCODE` | `( blk buf -- len )` | Serialize to CBOR |
| `BLK-DECODE` | `( buf len blk -- flag )` | Deserialize from CBOR |
| `BLK-HEIGHT@` | `( blk -- n )` | Read block height |
| `BLK-TX-COUNT@` | `( blk -- n )` | Number of transactions in block |

### Chain Management

| Word | Stack | Description |
|------|-------|-------------|
| `CHAIN-INIT` | `( -- )` | Initialize chain with genesis block |
| `CHAIN-HEAD` | `( -- blk )` | Current chain tip |
| `CHAIN-APPEND` | `( blk -- flag )` | Validate and append block |
| `CHAIN-HEIGHT` | `( -- n )` | Current chain height |
| `CHAIN-BLOCK@` | `( n -- blk )` | Retrieve block by height |

Storage: circular buffer of recent blocks (last 64 or 256),
older blocks described by hash only.

### Block Validation (`BLK-VERIFY`)

1. `prev_hash` matches hash of previous block
2. Height = previous height + 1
3. Timestamp ≥ previous timestamp
4. All transactions valid (`TX-VERIFY`)
5. No duplicate nonces within block
6. Transaction Merkle root matches
7. State root matches after applying all txs in order
8. Consensus proof valid (delegated to consensus.f)

---

## Phase 5 — consensus.f: Consensus Mechanism

**Prefix:** `CON-`
**Depends on:** block.f, stark.f (optional), ed25519.f
**Estimated size:** ~150 lines
**Difficulty:** Easy–Medium

### Three Modes

The consensus module is pluggable.  A single variable `CON-MODE`
selects the active mechanism.  All three share the same interface.

#### 5.1 Proof of Work

Simplest mode.  The proof field contains a 64-bit nonce.
Valid when `SHA3-256(block-header) < target`.

| Word | Stack | Description |
|------|-------|-------------|
| `CON-POW-MINE` | `( blk target -- )` | Brute-force nonce search |
| `CON-POW-CHECK` | `( blk target -- flag )` | Verify nonce meets target |
| `CON-POW-ADJUST` | `( old-target elapsed -- new-target )` | Difficulty adjustment |

~50 lines.  The mining loop is a straightforward `BEGIN .. WHILE`
incrementing the nonce and re-hashing.

#### 5.2 STARK Validity Proof

The power play.  The block producer:
1. Fills a 256-entry STARK trace encoding all state transitions
   (each row = one tx application: old balance, new balance, amount,
   nonce check)
2. Defines an AIR descriptor constraining valid transitions
3. Calls `STARK-PROVE`
4. Attaches the proof reference (FRI final + roots) to the block

The verifier calls `STARK-VERIFY` — if it passes, all 256
transactions are valid by mathematical proof.  No need to
re-execute transactions.

| Word | Stack | Description |
|------|-------|-------------|
| `CON-STARK-PROVE` | `( blk -- )` | Build trace from block txs, prove |
| `CON-STARK-CHECK` | `( blk -- flag )` | Verify STARK proof |

This is essentially a **validity rollup** — the STARK infrastructure
we just built is the consensus mechanism.

~60 lines of glue: trace encoding (tx → trace rows) and AIR
definition (balance conservation + nonce increment + signature
validity flag).

#### 5.3 Proof of Authority

A set of authorized public keys.  The proof field contains an
Ed25519 signature from one of the authorized signers.

| Word | Stack | Description |
|------|-------|-------------|
| `CON-POA-ADD` | `( pubkey -- )` | Add authorized signer |
| `CON-POA-SIGN` | `( blk priv pub -- )` | Sign block as authority |
| `CON-POA-CHECK` | `( blk -- flag )` | Verify signer is authorized |

~40 lines.

#### 5.4 Unified Interface

| Word | Stack | Description |
|------|-------|-------------|
| `CON-MODE` | variable | 0=PoW, 1=STARK, 2=PoA |
| `CON-SEAL` | `( blk -- )` | Apply consensus (mode-dependent) |
| `CON-CHECK` | `( blk -- flag )` | Verify consensus (mode-dependent) |

---

## Phase 6 — mempool.f: Transaction Pool

**Prefix:** `MP-`
**Depends on:** tx.f, sort.f
**Estimated size:** ~100 lines
**Difficulty:** Easy

A bounded priority queue of pending transactions, ordered by nonce
(per sender) then arrival time.  The block producer drains up to 256
transactions from the mempool to build a block.

### API

| Word | Stack | Description |
|------|-------|-------------|
| `MP-INIT` | `( -- )` | Initialize empty mempool |
| `MP-ADD` | `( tx -- flag )` | Validate and insert (reject duplicates) |
| `MP-REMOVE` | `( tx-hash -- flag )` | Remove by hash |
| `MP-DRAIN` | `( n buf -- actual )` | Pop up to n txs into buffer |
| `MP-COUNT` | `( -- n )` | Pending transaction count |
| `MP-PRUNE` | `( -- n )` | Remove expired/invalid entries |
| `MP-CONTAINS?` | `( tx-hash -- flag )` | Is tx in pool? |

Storage: `CREATE MP-POOL 256 408 * ALLOT` — up to 256 pending
transactions (~102 KB).  Sorted by sender address + nonce for
efficient duplicate detection.

---

## Dependency Graph

```
                    ┌──────────┐
                    │  sha512  │
                    └────┬─────┘
                         │
                    ┌────▼─────┐
                    │ ed25519  │ ◄── Phase 1 (NEW)
                    └────┬─────┘
                         │
           ┌─────────────┼─────────────┐
           ▼             ▼             ▼
      ┌─────────┐  ┌──────────┐  ┌──────────┐
      │   tx    │  │  state   │  │ mempool  │
      │         │  │          │  │          │
      └────┬────┘  └────┬─────┘  └──────────┘
           │             │          Phase 6
           │    Phase 2  │  Phase 3
           └──────┬──────┘
                  ▼
            ┌───────────┐
            │   block   │ ◄── Phase 4
            └─────┬─────┘
                  │
            ┌─────▼──────┐
            │ consensus  │ ◄── Phase 5
            └────────────┘
                  │
         ┌───────┼────────┐
         ▼       ▼        ▼
       [PoW]  [STARK]   [PoA]
              (already
               built)

  Existing modules used throughout:
    sha3  merkle  cbor  dag-cbor  sort  datetime  json
    server  router  ws  (for node RPC / gossip)
```

---

## Implementation Order

| Order | Module | Depends on (new) | Lines | Tests |
|------:|--------|------------------|------:|------:|
| 1 | ed25519.f | — | ~500 | ~30 |
| 2 | tx.f | ed25519 | ~150 | ~20 |
| 3 | state.f | — | ~250 | ~25 |
| 4 | block.f | tx, state | ~200 | ~25 |
| 5 | consensus.f | block, stark | ~150 | ~20 |
| 6 | mempool.f | tx | ~100 | ~15 |
| | **Total** | | **~1,350** | **~135** |

Ed25519 first because everything else needs signatures.
tx.f and state.f can proceed in parallel after that.
block.f integrates tx + state.  consensus.f sits on top.
mempool.f is independent and can be built any time after tx.f.

---

## Design Constraints

### Memory

| Item | Size | Notes |
|------|-----:|-------|
| Ed25519 point buffers | ~512 B | Extended coords: 4 × 32 bytes × 4 temporaries |
| Transaction buffer | 408 B | Single tx |
| Mempool | ~102 KB | 256 × 408 bytes |
| Account table | ~12 KB | 256 × 48 bytes |
| State Merkle tree | ~16 KB | 256-leaf SHA3-256 tree |
| Block buffer | ~105 KB | Header + 256 txs |
| STARK proof data | ~12 KB | Already allocated in stark.f |
| **Total new** | **~248 KB** | Well within 16 MB ext mem |

### Gotchas (Megapad-64 / Forth)

- `>R` / `R@` inside `DO..LOOP` — use `VARIABLE` (learned the hard way)
- `?DO` for zero-trip loops — `DO` wraps to ~2^64 iterations
- `.` prints signed — values > 2^63 display negative
- `REQUIRE filepath` — single argument, not two
- Multi-precision arithmetic for Ed25519: 256-bit values don't fit
  in a single 64-bit cell.  Must use 4-limb representation or
  the Field ALU MMIO device.
- CBOR encoding must be deterministic (sorted map keys) for
  reproducible hashes — dag-cbor.f already enforces this.
- Not re-entrant: one proof, one block build at a time.

### What We Don't Need to Build

| Capability | Already exists in |
|-----------|------------------|
| Cryptographic hashing | sha3.f, sha256.f, sha512.f |
| Merkle tree commitments | merkle.f |
| Binary serialization | cbor.f, dag-cbor.f |
| JSON for RPC | json.f |
| HTTP/WebSocket server | web/ modules |
| Batch field inversion | baby-bear.f |
| Validity proofs | stark.f + stark-air.f |
| CSPRNG for key generation | random.f |
| Timestamps | datetime.f |
| Sorting | sort.f |
| Concurrent data structures | conc-map.f, channel.f |
| Content addressing | dag-cbor.f + sha3.f |

---

## Testing Strategy

### Per-Module Tests

Each module gets its own `test_<module>.py` following the standard
pattern: snapshot BIOS+KDOS+dependencies, `run_forth()` per test,
`timeout 120` wrapper.

### Ed25519 Testing (Phase 1)

- RFC 8032 test vectors (official, 7 vectors)
- Roundtrip: keygen → sign → verify for random messages
- Wrong key → FALSE
- Bit-flip in signature → FALSE
- Canonical encoding checks
- Low-order point rejection

### Integration Tests

- **End-to-end:** keygen → fund accounts → build txs → sign →
  mempool → build block → finalize → verify block.  All in Forth.
- **Tamper suite:** flip one bit in a signed tx → block rejects.
  Change state root → block rejects.  Replay tx with old nonce →
  state rejects.
- **STARK consensus test:** build block → `CON-STARK-PROVE` →
  tamper a tx → `CON-STARK-CHECK` → FALSE.
- **Chain test:** build 4 consecutive blocks, verify chain
  integrity, attempt to insert block with wrong prev_hash → reject.

### Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Ed25519 sign | < 50M steps | Dominated by scalar multiply |
| Ed25519 verify | < 60M steps | Two scalar multiplies |
| Single tx validation | < 65M steps | Verify sig + state check |
| Block of 256 txs | < 1B steps | With parallel tx validation |
| STARK proof (256 txs) | < 800M steps | Already measured: ~300M for Fibonacci |
| Block verify (PoW) | < 1M steps | Single hash + comparison |
| Block verify (STARK) | < 800M steps | STARK-VERIFY |
