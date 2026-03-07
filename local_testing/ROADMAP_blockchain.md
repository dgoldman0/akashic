# Blockchain Library — Roadmap

A full-featured, STARK-provable blockchain for KDOS / Megapad-64,
built entirely on existing Akashic infrastructure.  The core thesis:
most of the hard work is already done — SHA3, CBOR, Merkle trees,
STARK proofs, WebSocket networking, HTTP/JSON-RPC, and concurrency
primitives all exist.  What remains is digital signatures (Ed25519 +
SPHINCS+), chain structural modules (transactions, state, blocks),
pluggable consensus (PoW, PoA, PoS — with optional STARK validity
overlays), node infrastructure (mempool, gossip, RPC, sync,
persistence), and a sandboxed Forth VM for on-chain smart contracts.

**Important:** Phases 1–7 produce a **custom chain** — it is *not*
wire-compatible with Ethereum, Bitcoin, or any existing blockchain.
The signature scheme (Ed25519/SPHINCS+), hashing (SHA3-256),
serialization (CBOR), consensus model, and smart-contract execution
(Forth VM) are all purpose-built for STARK provability, post-quantum
safety, and Megapad-64's native 64-bit architecture.  Phase 8 adds
standard blockchain compatibility (Ethereum, etc.) as a separate
library layer that coexists with — but does not replace — the custom
chain.

**Date:** 2026-03-07
**Status:** Living document

---

## Table of Contents

- [Current State — What Already Exists](#current-state--what-already-exists)
- [Gap Analysis](#gap-analysis)
- [Architecture Principles](#architecture-principles)
- [Post-Quantum Strategy](#post-quantum-strategy)
- [Phase 1 — ed25519.f: Digital Signatures](#phase-1--ed25519f-digital-signatures)
- [Phase 1b — sphincs-plus.f: Post-Quantum Signatures](#phase-1b--sphincs-plusf-post-quantum-signatures)
- [Phase 2 — tx.f: Transaction Structure](#phase-2--txf-transaction-structure)
- [Phase 3 — state.f: World State](#phase-3--statef-world-state)
- [Phase 4 — block.f: Block Structure & Chain](#phase-4--blockf-block-structure--chain)
- [Phase 5 — consensus.f: Consensus Mechanism](#phase-5--consensusf-consensus-mechanism)
- [Phase 6 — Node Infrastructure](#phase-6--node-infrastructure)
- [Phase 7 — contract-vm.f: Sandboxed Forth VM](#phase-7--contract-vmf-sandboxed-forth-vm)
- [Phase 8 — ethereum/: Standard Blockchain Interop](#phase-8--ethereum-standard-blockchain-interop)
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
serialization ✓, networking ✓, concurrency ✓.  The missing pieces
are **digital signatures** (Ed25519 for classical, SPHINCS+ for
post-quantum) and the chain structural modules.

---

## Gap Analysis

| Gap | Impact | Complexity |
|-----|--------|-----------|
| No elliptic curve arithmetic | Cannot sign or verify (classical) | Hard (~500 lines) |
| No post-quantum signatures | Vulnerable to quantum computers | Hard (~600 lines) |
| No transaction format | No unit of transfer | Easy (~200 lines) |
| No persistent state model | Cannot track balances/accounts | Medium (~250 lines) |
| No block structure | Cannot build a chain | Medium (~200 lines) |
| No consensus mechanism | Cannot agree on block validity | Medium (~380 lines) |
| No mempool | Cannot queue pending transactions | Easy (~100 lines) |

Total new code: ~3,200–3,800 lines across 12 modules (Phases 1–7).
The two signature modules (ed25519.f + sphincs-plus.f) account for
roughly a third of that.  Phase 8 (Ethereum interop) adds another
~2,000–3,000 lines.

---

## Architecture Principles

| Principle | Decision |
|-----------|----------|
| **Signature scheme** | Hybrid: Ed25519 (classical) + SPHINCS+-SHA3-128s (post-quantum).  Transactions carry both signatures; verifiers accept either or both depending on policy. |
| **Serialization** | CBOR everywhere — transactions, blocks, state entries.  DAG-CBOR for content addressing |
| **Hashing** | SHA3-256 for all chain hashing (block hash, address, Merkle).  Consistent with STARK internals |
| **Proof system** | STARK validity proofs optional per block — prover can attach proof that all state transitions are valid |
| **State model** | Account-based (not UTXO) — simpler for a 256-entry world, maps cleanly to a Merkle tree |
| **Block size** | 256 transactions max per block — matches STARK trace size for provability |
| **Consensus** | Pluggable — three leader-election modes (PoW, PoA, PoS) × orthogonal STARK validity overlay flag.  PoW for bootstrap/dev, PoA for consortium, PoS for production.  Any mode can optionally attach STARK proofs; PoS+STARK is the production endgame. |
| **Not re-entrant** | Same as all Akashic modules — single-threaded per core |
| **No floating point** | All values are integers (Baby Bear field elements or 64-bit) |
| **Post-quantum ready** | SPHINCS+ (hash-based, FIPS 205) uses only SHA3/SHAKE — leverages the existing hardware accelerator.  No new algebraic structures needed. |
| **Custom chain first** | Phases 1–7 are a self-contained, purpose-built chain with smart contracts and full node infrastructure.  Not Ethereum/Bitcoin compatible by design.  Standard chain interop is deferred to Phase 8 (`ethereum/` library). |

---

## Post-Quantum Strategy

Ed25519 is broken by Shor's algorithm in polynomial time on a
sufficiently large quantum computer.  The vault module is already
quantum-resistant (AES-256 + SHA3-256 — symmetric primitives only),
but the blockchain's transaction signatures are the weak link.

### Approach: Hybrid Signatures

Rather than replacing Ed25519, we run **both** schemes in parallel:

| Layer | Classical | Post-Quantum |
|-------|-----------|-------------|
| Signature scheme | Ed25519 (64 B sig) | SPHINCS+-SHA3-128s (7,856 B sig) |
| Public key | 32 B | 32 B |
| Secret key | 64 B | 64 B |
| Security | 128-bit classical | 128-bit post-quantum |
| Speed | Fast (~50M steps) | Slower (~200M steps) |
| Broken by | Shor's algorithm | Nothing known |

**Transaction signing policy** (configurable via `TX-SIG-MODE`):

| Mode | Behaviour | Wire size |
|------|-----------|----------|
| `TX-SIG-ED25519` | Ed25519 only (legacy compat) | +64 B |
| `TX-SIG-SPHINCS` | SPHINCS+ only (full PQ) | +7,856 B |
| `TX-SIG-HYBRID` | Both signatures (maximum security) | +7,920 B |

Hybrid mode means: even if one scheme is broken, the other still
protects the chain.  Validators in hybrid mode reject a tx only if
**both** signatures fail.

### Why SPHINCS+ (FIPS 205)

- **Hash-based** — security relies solely on the preimage/collision
  resistance of the hash function.  No lattices, no hidden algebraic
  structure.
- **Stateless** — unlike XMSS/LMS, no state to track between
  signatures.  Safe for Forth's single-threaded model.
- **SHA3 native** — SPHINCS+-SHA3 instantiation uses SHA3-256 and
  SHAKE-256, both of which are hardware-accelerated on Megapad-64.
  No new primitives needed.
- **NIST standardized** — FIPS 205 (August 2024).  Not experimental.
- **Conservative assumption** — if SHA3 is secure, SPHINCS+ is secure.
  Period.

### Tradeoff: Signature Size

SPHINCS+-SHA3-128s signatures are 7,856 bytes — ~123× larger than
Ed25519.  Impact:

| Metric | Ed25519-only | SPHINCS+-only | Hybrid |
|--------|-------------|--------------|--------|
| Tx sig field | 64 B | 7,856 B | 7,920 B |
| 256-tx block body | ~104 KB | ~2.06 MB | ~2.08 MB |
| Mempool (256 txs) | ~102 KB | ~2.1 MB | ~2.1 MB |

All well within even the 16 MiB test environment (production
extended memory can be significantly larger).  The tradeoff is
acceptable for a system that values long-term security over bandwidth.

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

## Phase 1b — sphincs-plus.f: Post-Quantum Signatures

**Prefix:** `SPX-`
**Depends on:** sha3.f (SHA3-256, SHAKE-256)
**Estimated size:** ~600 lines
**Difficulty:** Hard

### Why This Exists

Ed25519 is fast and compact but will be broken by a sufficiently
large quantum computer running Shor's algorithm.  SPHINCS+ is a
hash-based signature scheme whose security depends only on the
hash function — if SHA3 stands, SPHINCS+ stands.

### Parameter Set: SPHINCS+-SHA3-128s (small)

| Parameter | Value |
|-----------|-------|
| Security level | NIST Level 1 (128-bit PQ) |
| Hash | SHA3-256 + SHAKE-256 |
| Public key | 32 bytes |
| Secret key | 64 bytes |
| Signature | 7,856 bytes |
| Tree height (h) | 63 (3 layers × 21) |
| FORS trees (k) | 14 |
| FORS height (a) | 12 |
| Winternitz (w) | 16 |

The "s" (small) variant minimizes signature size at the cost of
slower signing (~2× slower than "f" variant).  For a blockchain
where signatures are stored forever, this is the right tradeoff.

### What to Build

#### 1b.1 WOTS+ (Winternitz One-Time Signatures)

The inner one-time signature used at every tree leaf.

| Word | Stack | Description |
|------|-------|-------------|
| `SPX-WOTS-SIGN` | `( msg sk-seed pk-seed addr sig -- )` | Generate WOTS+ signature |
| `SPX-WOTS-PK-FROM-SIG` | `( msg sig pk-seed addr pk-out -- )` | Recover public key from sig |

Internally computes `w`-step hash chains via `SPX-CHAIN` using
SHA3-256.  67 × 16-step chains per signature.

#### 1b.2 XMSS Trees

Merkle trees of WOTS+ public keys.  One XMSS tree per hypertree layer.

| Word | Stack | Description |
|------|-------|-------------|
| `SPX-XMSS-SIGN` | `( idx msg sk pk-seed addr sig -- )` | Sign at leaf `idx` in one XMSS tree |
| `SPX-XMSS-VERIFY` | `( idx msg sig pk-seed addr root -- flag )` | Verify XMSS signature against root |

#### 1b.3 Hypertree

3-layer tree of XMSS trees.  Signs FORS tree roots.

| Word | Stack | Description |
|------|-------|-------------|
| `SPX-HT-SIGN` | `( msg sk-seed pk-seed addr sig -- )` | Hypertree signature |
| `SPX-HT-VERIFY` | `( msg sig pk-seed addr root -- flag )` | Hypertree verification |

#### 1b.4 FORS (Forest of Random Subsets)

Few-time signature scheme.  14 binary trees of height 12.

| Word | Stack | Description |
|------|-------|-------------|
| `SPX-FORS-SIGN` | `( md sk-seed pk-seed addr sig -- )` | Generate FORS signature |
| `SPX-FORS-PK-FROM-SIG` | `( md sig pk-seed addr pk-out -- )` | Recover FORS public key |

#### 1b.5 Top-Level API

| Word | Stack | Description |
|------|-------|-------------|
| `SPX-KEYGEN` | `( seed pub sec -- )` | Generate keypair from 48-byte seed |
| `SPX-SIGN` | `( msg len sec sig -- )` | Sign message → 7,856-byte signature (uses current `SPX-SIGN-MODE`) |
| `SPX-VERIFY` | `( msg len pub sig -- flag )` | Verify signature → TRUE/FALSE |
| `SPX-SIG-LEN` | `( -- 7856 )` | Signature length constant |
| `SPX-PK-LEN` | `( -- 32 )` | Public key length constant |
| `SPX-SK-LEN` | `( -- 64 )` | Secret key length constant |
| `SPX-SIGN-MODE` | variable | 0 = randomized (default), 1 = deterministic |
| `SPX-MODE-RANDOM` | `( -- 0 )` | Constant for randomized mode |
| `SPX-MODE-DETERMINISTIC` | `( -- 1 )` | Constant for deterministic mode |

#### 1b.6 Tweakable Hash (internal)

All internal hashing goes through a tweakable hash function
`SPX-THASH` that incorporates an address structure (layer, tree
index, type, key-pair address) to domain-separate every hash call.

| Word | Stack | Description |
|------|-------|-------------|
| `SPX-THASH-1` | `( in pk-seed addr out -- )` | Tweaked hash, 1-block input |
| `SPX-THASH-2` | `( in pk-seed addr out -- )` | Tweaked hash, 2-block input |
| `SPX-THASH-N` | `( in n pk-seed addr out -- )` | Tweaked hash, n-block input |
| `SPX-PRF` | `( sk-seed addr out -- )` | Pseudorandom function for secret values |
| `SPX-H-MSG` | `( R pk msg len out -- )` | Message hash (randomized) |

All implemented via SHAKE-256 (hardware-accelerated).

### Design Decisions

- **SHA3 instantiation only:** No SHA-256 variant — we have
  hardware SHA3/SHAKE, so SPHINCS+-SHA3 is the natural fit.
- **All buffers in XMEM:** A single WOTS+ signature is 1,088 bytes;
  FORS signatures are ~5 KB.  Stack buffers won't cut it.
  `XMEM-ALLOT` for working space, freed after sign/verify.
- **Address structure as 8-cell buffer:** The SPHINCS+ ADRS
  (address) is 32 bytes with typed fields — layer, tree index,
  type, chain/hash/key-pair addresses.  One `CREATE` per
  call frame.
- **Randomized signing by default:** FIPS 205 recommends
  randomized signing — `opt_rand` is a fresh 32-byte nonce from
  the system CSPRNG, mixed into `H_msg`.  This hardens against
  fault injection (glitched signing can't be correlated across
  runs), side-channel averaging (no two traces for the same
  message are identical), and hedges against subtle hash
  weaknesses.  Controlled by `SPX-SIGN-MODE`:
  - `SPX-MODE-RANDOM` (default) — `opt_rand` from CSPRNG.
  - `SPX-MODE-DETERMINISTIC` — `opt_rand = pk.seed` for
    reproducible signatures (required for KAT testing, useful
    for debugging).
  Ed25519 remains purely deterministic per RFC 8032.

### Testing

- Known Answer Tests from the NIST SPHINCS+ reference implementation
- Roundtrip: keygen → sign → verify for multiple message lengths
- Wrong key → FALSE
- Bit-flip in signature → FALSE
- Verify independently against Python `sphincs` reference
- Performance: sign < 200M steps, verify < 50M steps target

---

## Phase 2 — tx.f: Transaction Structure

**Prefix:** `TX-`
**Depends on:** ed25519.f, sphincs-plus.f, sha3.f, cbor.f
**Estimated size:** ~200 lines
**Difficulty:** Easy

### Transaction Format

```
Transaction (CBOR map):
  "from"      : 32 bytes  (sender public key — Ed25519)
  "from_pq"   : 32 bytes  (sender PQ public key — SPHINCS+, optional)
  "to"        : 32 bytes  (recipient public key)
  "amount"    : u64       (transfer amount)
  "nonce"     : u64       (sender's sequence number)
  "data"      : bytes     (optional payload, 0–256 bytes)
  "sig"       : 64 bytes  (Ed25519 signature, present if mode includes classical)
  "sig_pq"    : 7856 bytes (SPHINCS+ signature, present if mode includes PQ)
  "sig_mode"  : u8        (0=Ed25519, 1=SPHINCS+, 2=hybrid)
```

Transaction hash = SHA3-256 of CBOR-encoded fields (excluding sig, sig_pq, sig_mode).

### API

| Word | Stack | Description |
|------|-------|-------------|
| `TX-INIT` | `( tx -- )` | Zero a transaction buffer |
| `TX-SET-FROM` | `( pubkey tx -- )` | Set sender (Ed25519 key) |
| `TX-SET-FROM-PQ` | `( pq-pubkey tx -- )` | Set sender PQ key |
| `TX-SET-TO` | `( pubkey tx -- )` | Set recipient |
| `TX-SET-AMOUNT` | `( amount tx -- )` | Set transfer amount |
| `TX-SET-NONCE` | `( nonce tx -- )` | Set sequence number |
| `TX-SET-DATA` | `( addr len tx -- )` | Set optional payload |
| `TX-HASH` | `( tx hash -- )` | Compute SHA3-256 of unsigned fields |
| `TX-SIGN` | `( tx ed-priv ed-pub -- )` | Sign with Ed25519 |
| `TX-SIGN-PQ` | `( tx spx-sec -- )` | Sign with SPHINCS+ |
| `TX-SIGN-HYBRID` | `( tx ed-priv ed-pub spx-sec -- )` | Sign with both |
| `TX-VERIFY` | `( tx -- flag )` | Verify signature(s) per sig_mode |
| `TX-ENCODE` | `( tx buf -- len )` | Serialize to CBOR |
| `TX-DECODE` | `( buf len tx -- flag )` | Deserialize from CBOR |
| `TX-SIG-MODE` | variable | 0=Ed25519, 1=SPHINCS+, 2=hybrid |

### Size Budget

Transaction buffer: 32 (from) + 32 (from_pq) + 32 (to) + 8 (amount)
+ 8 (nonce) + 2 (data-len) + 256 (data) + 64 (sig) + 7856 (sig_pq)
+ 1 (sig_mode) = 8,291 bytes.  Round to 8,296 (8-byte aligned).
`CREATE TX-BUF 8296 ALLOT`.

For Ed25519-only mode, the sig_pq field is zeroed and
not encoded in CBOR — wire size stays compact (~410 bytes).

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
**Depends on:** block.f, state.f, stark.f (optional), ed25519.f, random.f
**Estimated size:** ~380 lines
**Difficulty:** Medium

### Three Leader-Election Modes + STARK Overlay

The consensus module separates two orthogonal concerns:

1. **Leader election** — who produces the next block.  Selected by
   `CON-MODE` (0=PoW, 1=PoA, 2=PoS).
2. **Validity proving** — whether the block carries a STARK proof.
   Toggled by `CON-STARK?` (boolean flag, independent of mode).

This gives 6 combinations (3 modes × STARK on/off).  All share the
same `CON-SEAL` / `CON-CHECK` interface.

#### 5.1 Proof of Work

Bootstrap and testing mode.  Requires zero trust setup — no genesis
validator set, no stake distribution.  Start a node, it mines.
The proof field contains a 64-bit nonce.
Valid when `SHA3-256(block-header) < target`.

SHA3 is hardware-accelerated on the Megapad-64, making per-hash
cost genuinely low.  All Megapad-64 nodes hash at roughly equal
speed — no ASIC advantage, which makes PoW fairer here than on
heterogeneous networks like Bitcoin.  But it still burns cycles
for a Sybil defense that's overkill on small networks.

**Use case:** day-one bootstrapping, local development, single-node
testing.  Not recommended for production multi-node networks.

| Word | Stack | Description |
|------|-------|-------------|
| `CON-POW-MINE` | `( blk target -- )` | Brute-force nonce search |
| `CON-POW-CHECK` | `( blk target -- flag )` | Verify nonce meets target |
| `CON-POW-ADJUST` | `( old-target elapsed -- new-target )` | Difficulty adjustment |

~50 lines.  The mining loop is a straightforward `BEGIN .. WHILE`
incrementing the nonce and re-hashing.

#### 5.2 STARK Validity Overlay

Orthogonal to leader election.  When `CON-STARK?` is TRUE, the
block producer additionally:
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
is an overlay that any leader-election mode can attach.

~60 lines of glue: trace encoding (tx → trace rows) and AIR
definition (balance conservation + nonce increment + signature
validity flag).

**Not a standalone mode:** STARK proves *what* is in the block, but
does not decide *who* produces it.  It always pairs with one of the
three leader-election modes (PoW, PoA, or PoS).

#### 5.3 Proof of Authority

A set of authorized public keys.  The proof field contains an
Ed25519 signature from one of the authorized signers.

| Word | Stack | Description |
|------|-------|-------------|
| `CON-POA-ADD` | `( pubkey -- )` | Add authorized signer |
| `CON-POA-SIGN` | `( blk priv pub -- )` | Sign block as authority |
| `CON-POA-CHECK` | `( blk -- flag )` | Verify signer is authorized |

~40 lines.

#### 5.4 Proof of Stake

Production-grade permissionless consensus.  Validators lock tokens
as stake; the protocol selects a block producer per slot weighted
by stake amount.  Misbehaviour (equivocation) results in slashing.

##### Validator State

Extends the account model in state.f with staking fields:

```forth
\ Per-account staking fields (appended to account record)
\   offset  size   field
\   48      8      staked-amount    ( u64 — locked tokens )
\   56      8      unstake-height   ( u64 — 0 if staked, else unlock height )
\   64      8      last-signed-blk  ( u64 — for equivocation detection )
```

Validator set: accounts with `staked-amount > 0` and
`unstake-height = 0`.  Rebuilt at epoch boundaries.

##### Epoch & Slot Mechanics

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CON-POS-EPOCH-LEN` | 32 blocks | Validator set recomputation interval |
| `CON-POS-SLOT-TIME` | configurable | Target block interval |
| `CON-POS-MIN-STAKE` | 100 | Minimum tokens to become a validator |
| `CON-POS-LOCK-PERIOD` | 64 blocks | Unstaking lock-up duration |

At each epoch boundary, the validator set is sorted by stake
(descending).  Leader selection for each slot uses the block
parent hash as a seed to `RANDOM` (deterministic given the same
chain state), weighted by cumulative stake.

##### Slashing

If a validator signs two different blocks at the same height
(equivocation), any node that observes both signatures can submit
a **slashing proof** — the two conflicting block headers + sigs.
`CON-POS-SLASH` verifies both signatures against the validator's
pubkey, confirms different block hashes at the same height, and
burns the validator's entire stake.  The slashed tokens are either
burned (supply deflation) or redistributed to the reporter (bounty).

##### Staking Transactions

Two new transaction types (encoded in `TX-SET-DATA`):

| Tx type | Effect |
|---------|--------|
| `TX-STAKE` | Lock `amount` tokens from balance → staked-amount |
| `TX-UNSTAKE` | Set `unstake-height` = current height + lock period; tokens unlock after lock period, moved back to balance |

##### API

| Word | Stack | Description |
|------|-------|-------------|
| `CON-POS-LEADER` | `( slot -- pubkey )` | Compute leader for slot |
| `CON-POS-SIGN` | `( blk priv pub -- )` | Sign block as elected leader |
| `CON-POS-CHECK` | `( blk -- flag )` | Verify: signer = correct leader for slot |
| `CON-POS-SLASH` | `( hdr1 sig1 hdr2 sig2 -- flag )` | Verify & apply slashing proof |
| `CON-POS-EPOCH` | `( -- )` | Rebuild validator set at epoch boundary |
| `CON-POS-VALIDATORS` | `( buf max -- n )` | List current validator pubkeys |
| `CON-POS-STAKE-OF` | `( pubkey -- amount )` | Query validator's stake |

~200 lines.  Depends on: state.f (validator fields), random.f
(deterministic leader selection), ed25519.f (block signing).

#### 5.5 Production Endgame: PoS + STARK

The recommended production configuration: `CON-MODE=2` (PoS) +
`CON-STARK?=TRUE`.  This is what the cutting edge (Starknet, zkSync)
is converging on:

- **PoS decides who** produces the block (leader election by stake)
- **STARK proves the block is valid** (no re-execution by validators)

Validators don't re-run 256 transactions.  They verify:
1. The STARK proof (`CON-STARK-CHECK`) — mathematically proves all
   state transitions are correct
2. The leader signature (`CON-POS-CHECK`) — proves the block was
   produced by the legitimately elected validator for this slot

If both pass, the block is accepted.  This is not a separate mode —
it is the natural result of combining PoS (mode 2) with the STARK
overlay flag.

**Why this is the endgame:**
- No wasted energy (unlike PoW)
- No trusted committee (unlike PoA)
- Validators don't re-execute transactions (unlike plain PoS)
- Mathematically proven correctness (STARK)
- Economically backed leader election (PoS)
- Post-quantum safe if using SPHINCS+ for block signatures

#### 5.6 Consensus Comparison

| Mode | Leader election | Block validity | STARK overlay | Energy | Trust | Finality | Lines |
|------|----------------|---------------|:---:|--------|-------|----------|------:|
| PoW | Hash puzzle | Re-execute txs | optional | Wasteful | Trustless | Probabilistic | ~50 |
| PoW+STARK | Hash puzzle | Math proof | ✓ | Wasteful | Trustless | Probabilistic | ~50+60 |
| PoA | Authorized set | Signature | optional | Minimal | Trusted committee | Immediate | ~40 |
| PoA+STARK | Authorized set | Math proof | ✓ | Minimal | Trusted committee | Immediate | ~40+60 |
| PoS | Stake-weighted random | Re-execute txs | optional | Minimal | Trustless | ~epoch | ~200 |
| **PoS+STARK** | **Stake-weighted random** | **Math proof** | **✓** | **Minimal** | **Trustless** | **Immediate** | **~200+60** |

STARK overlay adds ~60 lines of shared glue regardless of mode.

#### 5.7 Unified Interface

| Word | Stack | Description |
|------|-------|-------------|
| `CON-MODE` | variable | 0=PoW, 1=PoA, 2=PoS |
| `CON-STARK?` | variable | TRUE = attach STARK validity proof to blocks (any mode) |
| `CON-SEAL` | `( blk -- )` | Apply leader election + optional STARK proof |
| `CON-CHECK` | `( blk -- flag )` | Verify leader election + STARK proof (if present) |

---

## Phase 6 — Node Infrastructure

**Location:** `akashic/store/` (mempool, persistence) + `akashic/net/` (gossip, RPC)
**Depends on:** tx.f, block.f, consensus.f, state.f, web/ modules
**Estimated size:** ~600–800 lines across 5 modules
**Difficulty:** Medium
**Status:** Not started

Phases 1–5 produce chain *data structures* (transactions, blocks,
state, consensus proofs).  Phase 6 turns them into a **running node**
that accepts transactions, talks to peers, produces blocks, and
survives restarts.  The existing web/ stack (HTTP server, WebSocket,
JSON, routing) provides the transport — Phase 6 adds the
protocol-level logic on top.

### 6a — mempool.f: Transaction Pool

**Prefix:** `MP-`
**Depends on:** tx.f, sort.f
**Estimated size:** ~100 lines

A bounded priority queue of pending transactions, ordered by nonce
(per sender) then arrival time.  The block producer drains up to 256
transactions from the mempool to build a block.

#### API

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

### 6b — gossip.f: P2P Network Layer

**Prefix:** `GSP-`
**Depends on:** ws.f, cbor.f, tx.f, block.f
**Estimated size:** ~200 lines

Peer-to-peer communication over WebSocket connections.  Each peer
connection is one persistent WS session.  Messages are CBOR-encoded.

#### Peer Management

| Word | Stack | Description |
|------|-------|-------------|
| `GSP-INIT` | `( -- )` | Initialize peer table (max 16 peers) |
| `GSP-CONNECT` | `( addr len port -- flag )` | Connect to peer via WS |
| `GSP-DISCONNECT` | `( peer-id -- )` | Drop peer connection |
| `GSP-PEERS` | `( buf max -- n )` | List connected peer IDs |
| `GSP-PEER-COUNT` | `( -- n )` | Number of active peers |
| `GSP-BOOTSTRAP` | `( addr len port -- )` | Connect + request peer exchange |

#### Message Protocol

| Message type | Tag | Payload | Direction |
|-------------|-----|---------|----------|
| `TX-ANNOUNCE` | 0x01 | CBOR-encoded tx | Broadcast |
| `BLOCK-ANNOUNCE` | 0x02 | Block header hash + height | Broadcast |
| `BLOCK-REQUEST` | 0x03 | Block hash or height | Request |
| `BLOCK-RESPONSE` | 0x04 | Full CBOR-encoded block | Response |
| `PEER-EXCHANGE` | 0x05 | List of `(addr, port)` pairs | Request/Response |
| `STATUS` | 0x06 | Chain head hash + height | Handshake |

#### Gossip Logic

| Word | Stack | Description |
|------|-------|-------------|
| `GSP-BROADCAST-TX` | `( tx -- )` | Send tx to all connected peers |
| `GSP-BROADCAST-BLK` | `( blk -- )` | Announce new block to all peers |
| `GSP-ON-MSG` | `( buf len peer-id -- )` | Handle incoming message (dispatch by tag) |
| `GSP-SEEN?` | `( hash -- flag )` | Duplicate suppression (recent hash cache) |

Duplicate suppression: a 256-entry ring buffer of recently seen
message hashes.  If a tx/block hash is in the ring, the message
is dropped silently.  Prevents infinite gossip loops.

### 6c — rpc.f: JSON-RPC Interface

**Prefix:** `RPC-`
**Depends on:** server.f, router.f, json.f, mempool.f, state.f, block.f
**Estimated size:** ~150–200 lines

External API for wallets, explorers, and test scripts.  Runs on the
existing HTTP server with a single `/rpc` endpoint.  Standard
JSON-RPC 2.0 request/response format.

#### Methods

| Method | Params | Result | Description |
|--------|--------|--------|-------------|
| `chain_sendTransaction` | CBOR-hex tx | tx hash | Submit signed tx to mempool |
| `chain_getBalance` | address | u64 | Account balance |
| `chain_getBlock` | height or hash | JSON block | Block header + tx hashes |
| `chain_getBlockFull` | height or hash | JSON block | Block header + full txs |
| `chain_getTransaction` | tx hash | JSON tx | Transaction by hash |
| `chain_blockNumber` | — | u64 | Current head height |
| `chain_getState` | — | JSON | Full state tree snapshot |
| `mempool_status` | — | JSON | Pending count, pool usage |
| `mempool_content` | — | JSON | List of pending tx hashes |
| `node_peers` | — | JSON | Connected peer list |
| `node_info` | — | JSON | Chain ID, head, sync status |
| `vm_call` | contract addr + entry + args | JSON | Read-only contract call (no state mutation) |
| `vm_deploy` | CBOR-hex source | contract addr | Deploy contract (creates tx) |

#### Implementation

The router maps `POST /rpc` to `RPC-DISPATCH`, which parses the
JSON-RPC envelope, extracts `method` and `params`, and dispatches
to the appropriate handler.  Each handler is a Forth word that
reads params from the JSON parser and writes the result to the
response buffer via `json.f`.

Error codes follow JSON-RPC 2.0: `-32700` (parse error), `-32601`
(method not found), `-32602` (invalid params), `-32000` (chain
rejected tx / block not found).

### 6d — sync.f: Block Synchronization

**Prefix:** `SYNC-`
**Depends on:** gossip.f, block.f, state.f, consensus.f
**Estimated size:** ~100–150 lines

When a node starts up or discovers a peer with a longer chain, it
needs to catch up.

#### Strategy

For a 256-account chain with small state, a simple sequential sync
is sufficient:

1. **Handshake:** on `GSP-CONNECT`, exchange `STATUS` messages
   (head hash + height)
2. **Gap detection:** if peer's height > ours, compute the gap
3. **Sequential fetch:** request blocks one at a time from our
   height + 1 to peer's height via `BLOCK-REQUEST`
4. **Validate and apply:** for each received block, run
   `CON-CHECK` + `BLK-APPLY` to update local state
5. **Fast-path for fresh nodes:** if local height is 0 (genesis
   only), request a state snapshot instead — the full state tree
   is ~12 KB, vastly cheaper than replaying the entire chain

#### API

| Word | Stack | Description |
|------|-------|-------------|
| `SYNC-START` | `( peer-id -- )` | Begin sync with a specific peer |
| `SYNC-STATUS` | `( -- state )` | 0=idle, 1=syncing, 2=caught-up |
| `SYNC-PROGRESS` | `( -- current target )` | Current/target heights |
| `SYNC-CANCEL` | `( -- )` | Abort in-progress sync |

#### Fork Handling

If two blocks claim the same height with different hashes:
- **PoW mode:** pick the block with the lower (harder) hash
- **STARK mode:** both must have valid proofs — pick the one
  received first (deterministic tie-break by block hash)
- **PoA mode:** reject the block from the non-authorized signer

Reorgs deeper than 1 block are rejected — the chain does not
support deep reorganization.  A 1-block reorg replays the
alternate block's transactions against the parent state.

### 6e — persist.f: Chain Persistence

**Prefix:** `PST-`
**Depends on:** state.f, block.f, cbor.f
**Estimated size:** ~80–100 lines

The chain state must survive node restarts.

#### Storage Layout

Flat file, append-only blocks + periodic state snapshots:

```
chain.dat:
  [genesis block CBOR] [block 1 CBOR] [block 2 CBOR] ...

state.snap:
  [height u64] [state tree CBOR] [state Merkle root 32B]
```

State snapshots are written every N blocks (default 16) or on
graceful shutdown.  On startup, the node loads the latest snapshot
and replays blocks after the snapshot height.

#### API

| Word | Stack | Description |
|------|-------|-------------|
| `PST-INIT` | `( path len -- flag )` | Open/create chain data file |
| `PST-APPEND-BLK` | `( blk -- flag )` | Append block to chain file |
| `PST-LOAD-BLK` | `( height blk -- flag )` | Read block at height |
| `PST-SAVE-SNAP` | `( -- flag )` | Write state snapshot |
| `PST-LOAD-SNAP` | `( -- flag height )` | Load latest state snapshot |
| `PST-CLOSE` | `( -- )` | Flush and close files |

Total file sizes are modest: the full state is ~12 KB, and 1000
blocks in classical mode total ~100 MB.  Hybrid mode (SPHINCS+
signatures) grows to ~2 GB for 1000 blocks — still manageable
on any storage device.

### 6f — node.f: Node Daemon

**Prefix:** `NODE-`
**Depends on:** all Phase 6 modules + consensus.f
**Estimated size:** ~100–150 lines

The main loop that ties everything together.

#### Lifecycle

```
NODE-INIT
  │
  ├─ PST-INIT (load chain / state from disk)
  ├─ MP-INIT (empty mempool)
  ├─ GSP-INIT (peer table)
  ├─ RPC-INIT (start HTTP server on configured port)
  ├─ GSP-BOOTSTRAP (connect to seed peers)
  ├─ SYNC-START (catch up if behind)
  │
  ▼
NODE-RUN (main loop)
  │
  ├─ Poll RPC requests → dispatch
  ├─ Poll gossip messages → validate, relay, apply
  ├─ If block producer:
  │    ├─ MP-DRAIN 256 txs
  │    ├─ BLK-BUILD → BLK-FINALIZE → CON-SEAL
  │    ├─ GSP-BROADCAST-BLK
  │    └─ PST-APPEND-BLK
  ├─ Periodic: MP-PRUNE, PST-SAVE-SNAP
  │
  ▼
NODE-SHUTDOWN
  │
  ├─ PST-SAVE-SNAP (final state snapshot)
  ├─ PST-CLOSE
  ├─ GSP-DISCONNECT (all peers)
  └─ done
```

#### API

| Word | Stack | Description |
|------|-------|-------------|
| `NODE-INIT` | `( config -- )` | Initialize node from config (ports, seed peers, mode) |
| `NODE-RUN` | `( -- )` | Enter main event loop (does not return) |
| `NODE-SHUTDOWN` | `( -- )` | Graceful shutdown (persist + disconnect) |
| `NODE-MODE` | `( -- mode )` | 0=full, 1=light (verify only), 2=producer |
| `NODE-PRODUCE?` | `( -- flag )` | TRUE if this node produces blocks |

#### Configuration

```forth
CREATE NODE-CFG 256 ALLOT

\ Populated from CBOR config file or hardcoded defaults:
\   rpc-port     ( default 8545 )
\   gossip-port  ( default 9000 )
\   seed-peers   ( list of addr:port )
\   chain-id     ( u64 — distinguishes testnets )
\   producer?    ( flag — should this node mine/sign blocks? )
\   consensus    ( 0=PoW, 1=PoA, 2=PoS )
\   stark?       ( flag — attach STARK validity proofs )
\   data-dir     ( path to chain.dat / state.snap )
```

---

## Phase 7 — contract-vm.f: Sandboxed Forth VM

**Location:** `akashic/store/contract-vm.f`
**Prefix:** `VM-`
**Depends on:** state.f, consensus.f, tx.f, stark-air.f
**Estimated size:** ~400–600 lines
**Difficulty:** Medium
**Status:** Not started

Phases 1–6 deliver a working chain that transfers value between
accounts.  Phase 7 adds **programmable smart contracts** by sandboxing
the Forth interpreter itself.  This is the natural choice: the entire
Akashic stack is Forth, the Megapad-64 *is* a Forth machine, and Forth
source is its own bytecode.  There is no need to design a secondary
instruction set.

### Why Forth VM, Not EVM

| Factor | EVM | Forth VM |
|--------|-----|----------|
| Word size | 256-bit (alien to Megapad-64's 64-bit cells) | Native 64-bit cells |
| STARK provability | Painful — 256-bit ALU ops explode trace width | Natural — each primitive = 1–2 trace rows in Baby Bear field |
| Implementation cost | ~5,000+ lines (256-bit ALU, gas, memory model, precompiles) | ~400–600 lines (sandbox existing interpreter) |
| Contract language | Solidity → bytecode (need external compiler) | Forth source **is** the program — no separate compilation step |
| Ecosystem integration | Foreign stack — cannot call `SHA3`, `MERKLE-ROOT` directly | Contracts call any whitelisted Akashic word natively |
| Gas metering | Per-opcode table (256 opcodes) | Per-word decrement — trivial, ~5 lines |
| Determinism | Complex (JUMPDEST analysis, memory expansion rules) | Inherent — no floating point, no I/O in sandbox |

The EVM requires implementing a 256-bit ALU from scratch on a 64-bit
machine.  Every ADD, MUL, SMOD becomes a multi-limb software routine.
STARK-proving those operations means each EVM instruction maps to
dozens of trace rows — destroying the compact proofs that make the
custom chain valuable.  The Forth VM avoids all of this.

### Architecture

A contract is a Forth source blob stored on-chain (CBOR-encoded in
the state tree).  Execution proceeds in an **isolated sandbox**:

1. **Isolated memory** — each contract gets its own XMEM arena.
   No access to the host dictionary, data space, or other contracts'
   memory.  Arena is freed after execution.
2. **Restricted dictionary** — only a whitelisted set of words is
   available.  Arithmetic, stack ops, comparisons, and explicitly
   exposed state-access words.  No `REQUIRE`, no file I/O, no
   raw memory access (`@` / `!` limited to the contract's arena).
3. **Gas metering** — a gas counter decrements on every word
   execution.  When gas reaches zero, execution aborts with an
   out-of-gas error.  The caller specifies the gas limit.
4. **State access** — contracts read/write account state exclusively
   through `VM-ST-GET` / `VM-ST-PUT`, which log all mutations for
   the STARK trace.
5. **STARK traceability** — every word execution emits a trace row
   (opcode tag, stack top, gas remaining, state delta).  The block
   producer feeds this trace to `STARK-PROVE` alongside the value
   transfer trace from Phase 5.

### Whitelisted Word Set

| Category | Words |
|----------|-------|
| Stack | `DUP` `DROP` `SWAP` `OVER` `ROT` `NIP` `TUCK` `2DUP` `2DROP` `2SWAP` `>R` `R>` `R@` |
| Arithmetic | `+` `-` `*` `/` `MOD` `/MOD` `NEGATE` `ABS` `MIN` `MAX` |
| Logic | `AND` `OR` `XOR` `INVERT` `LSHIFT` `RSHIFT` |
| Comparison | `=` `<>` `<` `>` `<=` `>=` `0=` `0<` `0>` |
| Control | `IF` `ELSE` `THEN` `BEGIN` `WHILE` `REPEAT` `UNTIL` `DO` `LOOP` `+LOOP` `?DO` `LEAVE` `EXIT` |
| Memory | `@` `!` `C@` `C!` `CELLS` `CELL+` (arena-relative only) |
| Variables | `VARIABLE` `CONSTANT` `CREATE` `ALLOT` (arena-scoped) |
| Strings | `TYPE` `COUNT` `S"` (read-only, no I/O — for return data) |
| State | `VM-ST-GET` `VM-ST-PUT` `VM-ST-HAS?` `VM-BALANCE` `VM-CALLER` `VM-SELF` `VM-BLOCK#` |
| Crypto | `VM-SHA3` `VM-VERIFY-ED25519` `VM-MERKLE-ROOT` |
| Output | `VM-EMIT` `VM-RETURN` (write to return buffer, not console) |

Words **not** available: `REQUIRE` `INCLUDED` `REFILL` `ACCEPT`
`KEY` `OPEN-FILE` `READ-FILE` `WRITE-FILE` `BYE` `SYSTEM` and all
raw MMIO / XMEM / OS primitives.

### Public API

| Word | Stack | Description |
|------|-------|-------------|
| `VM-INIT` | `( gas arena-sz -- ctx )` | Create isolated execution context |
| `VM-DEPLOY` | `( src len ctx -- addr )` | Compile contract source, store in state tree, return address |
| `VM-CALL` | `( entry-xt ctx -- )` | Execute contract entry point in sandbox |
| `VM-DELEGATECALL` | `( addr entry-xt ctx -- )` | Call another contract in caller's state context |
| `VM-GAS` | `( ctx -- remaining )` | Gas remaining after execution |
| `VM-RESULT` | `( ctx -- addr len )` | Return data buffer |
| `VM-FAILED?` | `( ctx -- flag )` | TRUE if execution aborted (out-of-gas, fault) |
| `VM-TRACE` | `( ctx trace -- rows )` | Export execution trace for STARK proof |
| `VM-DESTROY` | `( ctx -- )` | Free all sandbox resources |

### Transaction Integration

The `TX-SET-DATA` field (up to 256 bytes, expandable) carries:
- **Deploy transactions:** contract source (Forth text)
- **Call transactions:** target contract address + entry word name +
  arguments (CBOR-encoded)

The block producer, when applying transactions in `BLK-FINALIZE`:
1. Detects data-bearing txs (non-zero `TX-DATA-LEN`)
2. Decodes the payload (deploy vs. call)
3. Invokes `VM-DEPLOY` or `VM-CALL` in a sandbox
4. Collects the execution trace via `VM-TRACE`
5. Merges the VM trace with the value-transfer trace
6. Feeds the combined trace to `CON-STARK-PROVE`

### Gas Model

Simple per-word decrement — no variable-cost opcode table:

| Operation | Gas cost | Rationale |
|-----------|---------|----------|
| Any stack/arithmetic/logic word | 1 | One inner-interpreter cycle |
| `@` / `!` (arena memory) | 2 | Memory access |
| `VM-ST-GET` / `VM-ST-PUT` | 10 | State tree lookup (Merkle path) |
| `VM-SHA3` | 50 | Hash computation |
| `VM-VERIFY-ED25519` | 500 | Signature verification |
| `VM-MERKLE-ROOT` | 100 | Tree recomputation |
| Loop iteration (`LOOP` / `+LOOP`) | 1 | Prevents infinite loops |

Default gas limit per transaction: 10,000.  Configurable via
`VM-GAS-LIMIT` variable.

### Memory Budget

| Item | Size | Notes |
|------|-----:|-------|
| Sandbox arena (default) | 4 KB | Per-contract isolated data space |
| Sandbox dictionary | 2 KB | Compiled words within contract |
| Return buffer | 256 B | Output data from contract |
| Gas counter | 1 cell | 64-bit decrement counter |
| Trace buffer | ~8 KB | 256 trace rows × 32 bytes |
| **Per-invocation total** | ~14.3 KB | Freed on `VM-DESTROY` |

### STARK Integration

The VM trace feeds directly into the existing STARK infrastructure:

- Each trace row: `( word-tag  stack-top  gas  state-root-delta )`
- The AIR constraints for contract execution:
  - Gas decrements by the correct cost per word
  - Stack operations preserve the expected invariants
  - State mutations match the logged deltas
  - Gas ≥ 0 at every step (no underflow)
- Combined with the value-transfer AIR from Phase 5, the block
  producer generates a single STARK proof covering both plain
  transfers and contract executions.

This is the key advantage over the EVM: Forth primitives map to
1–2 AIR constraint rows each.  A 256-bit EVM ADD would require
~8 constraint rows just for the multi-limb arithmetic.  The Forth
VM keeps proofs compact and verification fast.

### Security Considerations

Running untrusted Forth source on a real machine with a flat address
space (no MMU/virtual memory) is fundamentally different from running
EVM bytecode in a process-isolated VM.  Every attack vector below
must be addressed in implementation — the sandbox is only as strong
as its weakest check.

#### Attack Surface Catalog

| # | Vector | Severity | Description |
|---|--------|----------|-------------|
| S1 | **Memory address escape** | **Critical** | Forth's `@` and `!` take absolute addresses.  If a contract computes an address outside its XMEM arena (e.g., `0 @` to probe low memory, or a known MMIO address), it reads/writes host memory, other contracts' state, or hardware registers. |
| S2 | **Dictionary escape** | **Critical** | If the sandbox uses the host `FIND` (or `'` tick), a contract can look up any word by name — including `BYE`, `SYSTEM`, raw MMIO words, `XMEM-*` primitives — regardless of the "whitelist." |
| S3 | **Return stack corruption** | **High** | `>R` / `R>` manipulate the return stack.  A contract that pushes a crafted address via `>R` and then exits a word causes the interpreter to jump to an arbitrary location — effectively arbitrary code execution on the host. |
| S4 | **Outer interpreter injection** | **High** | If the sandbox's compilation/interpretation loop resolves words against the full host dictionary (not just the whitelist), embedded strings like `S" BYE" EVALUATE` bypass the whitelist entirely. |
| S5 | **Stack overflow into adjacent memory** | **High** | Deep recursion or unbounded `DUP` chains grow the data/return stack into adjacent memory regions.  On a flat address space with no guard pages, this silently corrupts host data. |
| S6 | **`CREATE`/`ALLOT` host corruption** | **Medium** | `CREATE` advances `HERE` (the dictionary pointer).  If `HERE` isn't confined to the sandbox dictionary region, `CREATE` + `ALLOT` writes into host dictionary space. |
| S7 | **Reentrancy (DAO-style)** | **Medium** | `VM-DELEGATECALL` lets Contract A call Contract B.  If B calls back into A before A's state mutation is committed, A's invariants are violated — the classic reentrancy exploit. |
| S8 | **Integer overflow in balances** | **Medium** | 64-bit arithmetic wraps silently.  `VM-BALANCE` + amount could overflow to a small number, or a subtraction could underflow to a huge number, creating or destroying value. |
| S9 | **Stale arena memory** | **Low** | If the XMEM allocator reuses memory from a previous contract invocation without zeroing, the new contract reads residual data (information leak across contract boundaries). |
| S10 | **Gas undercount / DoS** | **Low** | If expensive operations (large `LSHIFT`, deep recursion) cost the same gas as trivial ones, an attacker can construct worst-case execution that consumes disproportionate wall-clock time relative to gas spent. |
| S11 | **Non-determinism** | **Low** | If any reachable word has non-deterministic behaviour (uninitialized memory reads, timing, etc.), validators compute different STARK traces and fail to reach consensus. |
| S12 | **Source parsing exploits** | **Low** | Malformed contract source (unterminated strings, extremely long tokens, deeply nested control structures) could crash or hang the parser. |

#### Mitigations

**M1 — Bounds-checked memory access (→ S1, S9)**

The sandbox does **not** expose the host `@` and `!`.  Instead, it
provides wrapped versions that enforce arena bounds on every access:

```forth
: VM-@   ( addr -- val )
    DUP _VM-ARENA-BASE @ _VM-ARENA-END @ WITHIN 0= IF
        _VM-FAULT-OOB EXIT THEN
    @ ;

: VM-!   ( val addr -- )
    DUP _VM-ARENA-BASE @ _VM-ARENA-END @ WITHIN 0= IF
        _VM-FAULT-OOB EXIT THEN
    ! ;
```

Every `@`, `!`, `C@`, `C!` in the whitelist is actually
`VM-@`, `VM-!`, `VM-C@`, `VM-C!`.  The contract source still
writes `@` and `!`, but the sandbox compiler resolves these names
to the bounds-checked variants.  Zero-cost at compile time, one
comparison per access at runtime.

Arena memory is zeroed on `VM-INIT` (→ S9 stale data).

**M2 — Shadow dictionary (→ S2, S4)**

The sandbox maintains its own **shadow dictionary** — a flat
table mapping word names to execution tokens.  Only whitelisted
words are entered.  The sandbox's `FIND` (`_VM-FIND`) searches
*only* this shadow dictionary, never the host dictionary:

```forth
: _VM-FIND  ( addr len -- xt flag | 0 )
    _VM-DICT _VM-DICT-COUNT @
    0 ?DO
        2DUP I _VM-DICT-ENTRY NAME= IF
            2DROP I _VM-DICT-ENTRY XT@ TRUE UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;
```

`'` (tick) and `[']` are also shadowed to use `_VM-FIND`.
`EVALUATE` is **not whitelisted** — there is no way for a
contract to invoke the outer interpreter on an arbitrary string.

**M3 — Separate return stack (→ S3)**

The sandbox allocates a **dedicated return stack** within the XMEM
arena (e.g., 256 cells = 2 KB).  `>R`, `R>`, `R@` operate on this
sandbox return stack, not the host's R.  The sandbox inner
interpreter uses a local return-stack pointer (`_VM-RSP`) rather
than the hardware R3 register:

- Overflow check: `>R` faults if `_VM-RSP` reaches the top of
  the return-stack region.
- Underflow check: `R>` faults if `_VM-RSP` is at the base.
- On sandbox exit, `_VM-RSP` is discarded — no host R corruption.

The host interpreter's R3 is saved/restored around `VM-CALL`,
similar to how `PAUSE` saves/restores task contexts in coroutine.f.

**M4 — Bounded stacks (→ S5)**

Both the data stack and the sandbox return stack have explicit
depth limits (e.g., 256 cells each).  Every push operation checks
against the limit; every pop checks for underflow.  These checks
are compiled inline by the sandbox compiler — approximately 3
instructions per stack operation.  Overflow/underflow triggers
`_VM-FAULT-STACK`, which aborts execution and sets `VM-FAILED?`.

**M5 — Scoped `CREATE`/`ALLOT`/`HERE` (→ S6)**

The sandbox maintains its own `HERE` pointer (`_VM-HERE`) that
advances within the sandbox dictionary region (2 KB).  `CREATE`
writes the new header to `_VM-HERE`, not the host's `HERE`.
`ALLOT` advances `_VM-HERE` and faults if it would exceed the
dictionary region.  The host dictionary is untouched.

**M6 — Reentrancy guard (→ S7)**

`VM-DELEGATECALL` sets a per-contract **call-depth counter**.
The maximum call depth is 4 (configurable via `VM-MAX-DEPTH`).
Additionally, state mutations from `VM-ST-PUT` within a
`VM-DELEGATECALL` frame are **journaled** — they are not committed
to the state tree until the outermost call frame returns
successfully.  If any nested call faults, all journaled mutations
for the entire call chain are rolled back (similar to Ethereum's
revert semantics, but simpler because there's no gas refund
complexity).

```
Call chain:  A → B → A  (reentrant)
  - A's first ST-PUT is journaled, not committed
  - B calls back into A — call depth = 2
  - A's second ST-PUT is journaled separately
  - If B or A faults: ALL journals rolled back
  - If all succeed: journals committed in order
```

**M7 — Checked balance arithmetic (→ S8)**

`VM-BALANCE`, `VM-ST-PUT` (for balance fields), and the
value-transfer logic use **checked arithmetic** — additions that
would overflow 2^63 - 1 (the signed positive range) and
subtractions that would go negative both trigger `_VM-FAULT-OVERFLOW`.
This is enforced at the state-access layer, not in general
arithmetic (general `+` and `-` remain wrapping, as contracts may
legitimately use modular arithmetic for hashing/crypto).

**M8 — Gas proportionality (→ S10)**

Expensive whitelist words have proportionally higher gas costs
(already defined in the gas model table).  Additionally:
- `LSHIFT` / `RSHIFT` clamp the shift amount to 0–63.  Shifts
  beyond 63 produce 0 (matching hardware behaviour) and cost 1 gas.
- `VM-SHA3` gas cost is proportional to input length: 50 + 1 per
  32 bytes.
- Recursion depth is bounded by the return stack limit (M4),
  so deep recursion hits a stack fault before consuming
  unbounded time.

**M9 — Deterministic execution (→ S11)**

Guaranteed by construction:
- Arena zeroed on init (no uninitialised reads)
- No I/O, no `RANDOM`, no timing words in whitelist
- All arithmetic is 64-bit two's-complement (hardware-defined)
- `VM-BLOCK#` reads from the block being processed (same for all
  validators)
- Dictionary lookup order is fixed (shadow dictionary, linear scan)

**M10 — Parser hardening (→ S12)**

The sandbox compiler imposes limits on contract source:
- Maximum token length: 64 characters (longer → parse fault)
- Maximum nesting depth (control structures): 16 levels
- Maximum source size: bounded by `TX-MAX-DATA` (currently 256 B,
  expandable but always finite)
- Unterminated `S"` or `."` → parse fault at end of source
- No `\` (backslash comments) or `(` (paren comments) that could
  mask malicious code in unexpected ways — comments are stripped
  before sandbox compilation

#### Security Summary

| Threat | Mitigation | Overhead |
|--------|-----------|----------|
| Memory escape | Bounds-checked `VM-@`/`VM-!` | 1 comparison per access |
| Dictionary escape | Shadow dictionary, no host `FIND` | Zero (compile-time) |
| Return stack corruption | Separate sandbox R-stack | 1 bounds check per `>R`/`R>` |
| Interpreter injection | No `EVALUATE`, shadow `FIND` only | Zero |
| Stack overflow | Depth-limited data + return stacks | 1 check per push/pop |
| `CREATE`/`ALLOT` escape | Scoped `_VM-HERE` | 1 bounds check |
| Reentrancy | Journal + call-depth limit | Journal commit on return |
| Balance overflow | Checked arithmetic in state ops | 1 overflow check |
| Stale memory | Arena zeroed on init | One `XMEM-ZERO` call |
| Gas DoS | Proportional costs + stack bounds | Negligible |
| Non-determinism | Eliminated by construction | Zero |
| Parser attacks | Length/depth limits | Negligible |

**Design principle:** the sandbox is a *whitelist interpreter*, not
a blacklist filter.  It does not try to "remove dangerous words from
Forth" — it builds a **new, minimal interpreter** that only knows
safe words.  The host interpreter is never invoked by contract code.
This is the only tenable approach on a flat-address-space machine
with no hardware memory protection.

### Testing

- **Sandbox isolation:** attempt to call `BYE`, `SYSTEM`, raw `@`
  outside arena → rejected
- **Memory escape (S1):** compute address outside arena, attempt
  `VM-@` / `VM-!` → `_VM-FAULT-OOB`, `VM-FAILED?` = TRUE
- **Dictionary escape (S2):** embed `S" BYE"` as a word name,
  attempt lookup → `_VM-FIND` returns 0 (not found)
- **Return stack attack (S3):** push crafted address via `>R`,
  `EXIT` → sandbox R-stack, host R untouched, fault on bad jump
- **Stack overflow (S5):** `BEGIN DUP AGAIN` → stack depth limit
  hit, `_VM-FAULT-STACK`
- **Reentrancy (S7):** A calls B calls A → depth limit or journal
  rollback on fault
- **Integer overflow (S8):** transfer that would overflow balance →
  `_VM-FAULT-OVERFLOW`
- **Gas exhaustion:** infinite loop → aborts with `VM-FAILED? TRUE`
- **State access:** deploy counter contract, call increment 3×,
  verify state = 3
- **STARK proof:** execute contract, extract trace, prove, tamper
  one row, verify fails
- **Cross-contract call:** A calls B via `VM-DELEGATECALL`, verify
  state consistency
- **Roundtrip:** deploy (CBOR) → call → verify return data → prove
- **Parser hardening (S12):** submit source with 65-char token,
  unterminated string, 17-deep nesting → parse faults

---

## Phase 8 — ethereum/: Standard Blockchain Interop

**Location:** `akashic/ethereum/`  (separate from `store/`)
**Depends on:** Phases 1–7 complete (functional custom chain with smart contracts)
**Estimated size:** ~2,000–3,000 lines across 5+ modules
**Difficulty:** Hard
**Status:** Future — not started

Phases 1–7 deliver a working, unique chain with smart contracts,
optimised for Megapad-64.  Phase 8 adds a **separate library** for
interoperating with standard
blockchains (Ethereum first, others later).  This is not a rewrite of
the custom chain — it is an independent set of modules that speak the
wire protocols of existing networks.

### Why Separate

The custom chain and Ethereum use fundamentally different primitives:

| Layer | Custom chain (Phases 1–7) | Ethereum |
|-------|---------------------------|----------|
| Signatures | Ed25519 + SPHINCS+ | secp256k1 ECDSA |
| Hashing | SHA3-256 (FIPS 202) | Keccak-256 (pre-NIST, different padding) |
| Serialization | CBOR / DAG-CBOR | RLP (Recursive Length Prefix) |
| State tree | 256-leaf Merkle | Modified Merkle Patricia Trie |
| Addresses | 32-byte pubkey hash | 20-byte Keccak of secp256k1 pubkey |
| Execution | Forth words | EVM bytecode |
| Consensus | PoW / PoA / PoS (× optional STARK overlay) | Proof of Stake (Casper) |

Forcing the custom chain to mimic Ethereum's wire format would
compromise its design goals (STARK provability, PQ safety, simplicity).
Instead, the Ethereum library stands alone and can optionally be used
alongside the custom chain for bridging.

### Planned Modules

| Module | Description | Est. lines |
|--------|-------------|----------:|
| `secp256k1.f` | Elliptic curve arithmetic on secp256k1 + ECDSA sign/verify | ~600 |
| `keccak.f` | Keccak-256 (Ethereum's hash, distinct from FIPS SHA3-256) | ~200 |
| `rlp.f` | RLP encoder/decoder | ~150 |
| `eth-tx.f` | Ethereum transaction format (EIP-1559 / EIP-2718 typed txs) | ~300 |
| `eth-abi.f` | ABI encoding/decoding for smart contract calls | ~300 |
| `eth-rpc.f` | JSON-RPC client (eth_sendRawTransaction, eth_call, etc.) | ~200 |
| `eth-wallet.f` | Key derivation (BIP-32/39/44), address generation | ~250 |

### Use Cases

- **Bridge:** Lock assets on Ethereum, mint on custom chain (and vice versa)
- **Light client:** Verify Ethereum block headers from within KDOS
- **Wallet:** Sign and broadcast Ethereum transactions from Megapad-64
- **Oracle:** Read Ethereum state (balances, contract storage) via JSON-RPC

### Non-Goals (Phase 8)

- Full EVM implementation (no smart contract execution on Megapad-64)
- Ethereum consensus participation (no staking/validation)
- Replacing the custom chain with Ethereum — they coexist

---

## Dependency Graph

```
              ┌──────────┐     ┌──────────┐
              │  sha512  │     │   sha3   │
              └────┬─────┘     └────┬─────┘
                   │                │
              ┌────▼─────┐    ┌────▼──────────┐
              │ ed25519  │    │ sphincs-plus  │
              │          │    │  (FIPS 205)   │
              └────┬─────┘    └──────┬────────┘
                   │  Phase 1        │ Phase 1b
                   └────────┬────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
         ┌─────────┐  ┌──────────┐
         │   tx    │  │  state   │
         │ (hybrid │  │          │
         │  sigs)  │  │          │
         └────┬────┘  └────┬─────┘
              │    Phase 2  │  Phase 3
              └──────┬──────┘
                     ▼
               ┌───────────┐
               │   block   │ ◄── Phase 4
               └─────┬─────┘
                     │
               ┌─────▼──────┐
               │ consensus  │ ◄── Phase 5
               └─────┬───────┘
                     │
            ┌───────┼────────┐
            ▼       ▼        ▼
          [PoW]  [PoA]     [PoS]
                             │
                      ┌──────┘
                      ▼
               [STARK overlay]
               (optional, any
                mode — endgame
                = PoS+STARK)
                     │
     ┌───────────────┼────────────────┐
     ▼               ▼                ▼
┌──────────┐  ┌────────────┐  ┌────────────┐
│ mempool  │  │  gossip    │  │   rpc      │ ◄── Phase 6
│ (6a)     │  │  (6b)      │  │   (6c)     │     Node
└──────────┘  └────────────┘  └────────────┘     Infra
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
    ┌──────────┐ ┌─────────┐ ┌──────────┐
    │  sync    │ │ persist │ │  node    │
    │  (6d)    │ │  (6e)   │ │  (6f)    │
    └──────────┘ └─────────┘ └──────────┘

  Existing modules used throughout:
    sha3  merkle  cbor  dag-cbor  sort  datetime  json
    server  router  ws  (for node RPC / gossip)

  Quantum-safe path:  sha3 → sphincs-plus → tx (PQ mode) → block
  Classical path:     sha512 → ed25519 → tx (classical mode) → block

               ┌────────────┐
               │ contract-  │ ◄── Phase 7
               │    vm      │
               │ (sandboxed │
               │  Forth)    │
               └─────┬──────┘
                     │  depends on:
                     │  state, consensus,
                     │  tx, stark-air, node
                     ▼
              ┌──────────────┐
              │  ethereum/   │ ◄── Phase 8
              │  (interop)   │
              └──────────────┘
```

---

## Implementation Order

| Order | Module | Depends on (new) | Lines | Tests |
|------:|--------|------------------|------:|------:|
| 1 | ed25519.f | — | ~500 | ~30 |
| 1b | sphincs-plus.f | sha3 | ~600 | ~25 |
| 2 | tx.f | ed25519, sphincs-plus | ~200 | ~25 |
| 3 | state.f | — | ~250 | ~25 |
| 4 | block.f | tx, state | ~200 | ~25 |
| 5 | consensus.f | block, state, stark, random | ~380 | ~35 |
| 6a | mempool.f | tx, sort | ~100 | ~15 |
| 6b | gossip.f | ws, cbor, tx, block | ~200 | ~15 |
| 6c | rpc.f | server, router, json, mempool, state, block | ~150–200 | ~20 |
| 6d | sync.f | gossip, block, state, consensus | ~100–150 | ~15 |
| 6e | persist.f | state, block, cbor | ~80–100 | ~10 |
| 6f | node.f | all Phase 6 modules + consensus | ~100–150 | ~10 |
| 7 | contract-vm.f | state, consensus, tx, stark-air, node | ~400–600 | ~25 |
| | **Subtotal (custom chain)** | | **~3,160–3,780** | **~240** |
| 8 | ethereum/ (secp256k1, keccak, rlp, eth-tx, eth-abi, eth-rpc, eth-wallet) | Phases 1–7 complete | ~2,000–3,000 | ~100+ |
| | **Grand total** | | **~5,160–6,780** | **~340+** |

Ed25519 first because it unblocks the classical signing path.
SPHINCS+ can proceed in parallel (independent dependency: sha3 only).
tx.f waits for both signature modules.  state.f can proceed in
parallel with everything after Phase 1.  block.f integrates tx +
state.  consensus.f sits on top.  mempool.f is independent after tx.f.

**Phases 1–5 = chain data structures.  Phase 6 = running node
(mempool, gossip, RPC, sync, persistence, daemon).  Phase 7 adds
smart contracts via sandboxed Forth VM.  Phases 1–7 = complete
custom chain.**  Phase 8 adds Ethereum/standard blockchain interop
as a separate library — it does not modify the custom chain modules.

---

## Design Constraints

### Memory

| Item | Size | Notes |
|------|-----:|-------|
| Ed25519 point buffers | ~512 B | Extended coords: 4 × 32 bytes × 4 temporaries |
| SPHINCS+ work buffers | ~32 KB | WOTS+ chains, FORS trees, auth paths (XMEM, freed after use) |
| Transaction buffer | 8,296 B | Single tx (hybrid mode, worst case) |
| Mempool (Ed25519 mode) | ~102 KB | 256 × ~408 bytes |
| Mempool (hybrid mode) | ~2.1 MB | 256 × ~8,296 bytes |
| Account table | ~12 KB | 256 × 48 bytes |
| State Merkle tree | ~16 KB | 256-leaf SHA3-256 tree |
| Block buffer (Ed25519) | ~105 KB | Header + 256 txs |
| Block buffer (hybrid) | ~2.1 MB | Header + 256 txs (PQ sigs) |
| STARK proof data | ~12 KB | Already allocated in stark.f |
| **Total new (classical)** | **~248 KB** | Same as before |
| **Total new (hybrid)** | **~4.3 MB** | Well within 16 MiB test env; production XMEM can be much larger |

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
| Cryptographic hashing | sha3.f, sha256.f, sha512.f (+ SHAKE-256 for SPHINCS+) |
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

### SPHINCS+ Testing (Phase 1b)

- Known Answer Tests from NIST SPHINCS+ reference (deterministic mode)
- Roundtrip: keygen → sign → verify for 0-byte, 1-byte, 256-byte messages
- Wrong key → FALSE
- Bit-flip in any of 7,856 signature bytes → FALSE
- Cross-validate against Python `pyspx` or reference C implementation
- Performance regression: sign < 200M steps, verify < 50M steps

### Integration Tests

- **End-to-end (classical):** keygen → fund accounts → build txs
  → sign (Ed25519) → mempool → build block → finalize → verify.
- **End-to-end (hybrid):** same flow with hybrid signatures —
  verify accepts if either sig passes, rejects only if both fail.
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
| SPHINCS+ sign | < 200M steps | Dominated by WOTS+ chain hashing |
| SPHINCS+ verify | < 50M steps | Hash-path verification (fast) |
| Single tx validation (classical) | < 65M steps | Ed25519 verify + state check |
| Single tx validation (hybrid) | < 120M steps | Both verify + state check |
| Block of 256 txs (classical) | < 1B steps | With parallel tx validation |
| Block of 256 txs (hybrid) | < 2B steps | Both sigs per tx |
| STARK proof (256 txs) | < 800M steps | Already measured: ~300M for Fibonacci |
| Block verify (PoW) | < 1M steps | Single hash + comparison |
| Block verify (STARK) | < 800M steps | STARK-VERIFY |
