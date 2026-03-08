# Blockchain Library — Roadmap

A full-featured, STARK-provable blockchain for KDOS / Megapad-64,
built entirely on existing Akashic infrastructure.  The core thesis:
most of the hard work is already done — SHA3, CBOR, Merkle trees,
STARK proofs, WebSocket networking, HTTP/JSON-RPC, and concurrency
primitives all exist.  What remains is digital signatures (Ed25519 +
SPHINCS+), chain structural modules (transactions, state, blocks),
pluggable consensus (PoW, PoA, PoS, PoSA — with optional STARK validity
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
**Status:** Living document — **under revision** (see assessment below)

---

## Critical Assessment (2026-03-07)

> **Honest framing:** This is a vertically integrated research
> prototype — impressive in scope, clean in architecture, but the
> plan as written presents a progression toward production when the
> foundation has hard limits that require *architectural redesign*
> (not parameter tuning) to overcome.  The notes below are scattered
> throughout the document as `⚠ REVISED` blocks.  This section
> summarises the systemic issues.

### What works today

- **Single-node demo / proof of concept.**  One node, PoA mode, a
  handful of accounts, creating blocks in a loop.  The tested modules
  (tx, state, block, consensus, mempool, persist, node) actually do
  what they claim.
- **Closed consortium of 2–5 nodes** (PoA, Ed25519-only, <50
  accounts).  This is real and functional within the constraints.
- **Research artifact.**  "A blockchain in ~3,500 lines of Forth with
  STARK validity proofs" is a genuinely interesting demonstration.
  The STARK trace integration is the novel contribution.

### What doesn't work (systemic issues)

| Issue | Root cause | Impact | Fix category |
|-------|-----------|--------|-------------|
| ~~**256-account ceiling**~~ | ✅ **Resolved by Phase 3b.** Paged state + SMT decouple account count from proof geometry. `_ST-MAX-PAGES` is an emulator testing value (16); production scales to 256+ pages (65K+ accounts). | — | Done |
| ~~**"Persistence" is an in-memory append buffer**~~ | ✅ **Resolved by Phase 6.5a.** `persist.f` rewritten with real KDOS file I/O (`OPEN`, `FREAD`, `FWRITE`, `FFLUSH`). `chain.dat` (append-only block log) + `state.snap` (periodic snapshots). | — | Done |
| ~~**No light client protocol**~~ | ✅ **Resolved.** `light.f` (160 lines) provides `LC-STATE-PROOF`, `LC-STATE-LEAF`, `LC-VERIFY-STATE`.  Four new RPC methods (`chain_getProof`, `chain_getBlockProof`, `chain_getStateRoot`, `chain_verifyProof`) are wired in `rpc.f`.  19/19 tests passing. | — | Done — see Phase 6.5b |
| **Consensus mode is a runtime `VARIABLE`** | Nothing in the protocol enforces node agreement on consensus mode. | Misconfiguration is silent — nodes produce incompatible blocks. | **Genesis-block config** — bake mode into chain ID / genesis |
| **PoS leader grinding** | Seed = `SHA3(prev_hash \|\| height)`.  Block producer influences next seed via tx selection. | Validators can bias leader election. | **Commit-reveal or VDF** |
| **No deep reorg support** | Max 1-block reorg.  64-block header ring = no deep history. | PoW with network partitions trivially forks deeper than 1. | **Acceptable for PoA/PoS** — but PoW mode should warn or be removed |
| **Serialized consensus path (not single-threaded)** | Blockchain modules serialize through `WITH-GUARD` for STARK determinism. | Consensus + execution are serial by design; I/O (gossip, RPC) and tx validation can be parallelized via `PAR-MAP`, `WITH-BACKGROUND`, and KDOS multi-core dispatch (up to 16 cores). | **Evolve** — parallelize tx validation (per-core crypto scratch), pipeline STARK proofs on background core, serve RPC on BIOS coroutine |
| **SPHINCS+ bandwidth explosion** | 7,856 B/sig × 256 txs = 2.1 MB/block.  A thousand hybrid blocks = 2 GB. | Impractical for high-throughput or bandwidth-constrained networks. | **Accept** — hybrid mode is opt-in.  Default to Ed25519-only. |
| **Software sandbox on flat address space** | No MMU, no process isolation.  One bounds-check bug = full compromise. | Adversarial public contracts are high-risk. | **Two-tier approach**: (1) capability-based isolation via .m64 import whitelisting + bounds-checked memory (trusted consortium deployers), (2) full shadow-dictionary ITC interpreter for adversarial deployments.  Extensive fuzzing either way. |
| **256-tx-per-block cap is proof-geometric** | Tied to STARK trace width, not a tunable parameter. | Can't increase per-block throughput without redesigning the proof system. | **Mitigate** — throughput = txs/block × blocks/time.  Shorten block time (PoA is near-instant), parallelize tx validation via `PAR-MAP`, pipeline proof generation (prove block N on background core while producing N+1), batch STARK proofs every K blocks.  Realistic target: hundreds of TPS. |
| ~~**PoSA (Mode 3) not implemented**~~ | ✅ **Resolved by Phase 5b.** `consensus.f` Stage D implements PoSA (Mode 3) with staked-authority election, unified `CON-SEAL`/`CON-CHECK` dispatch, and `CON-SET-KEYS` signing context.  `genesis.f` encodes chain config in block 0. | — | Done |

### Revised strategy

**Do not proceed to Phase 7 (Forth VM) or Phase 8 (Ethereum interop)
until the foundation is production-grade.**  The new priority order:

1. ~~**Phase 6.5a — Real persistence** (file I/O, crash recovery)~~ ✅ **Done** (commit 3f9ca41)
2. ~~**Phase 3b — Scalable state** (decouple accounts from trace width)~~ ✅ **Done** (commits 35a8e8c, b9e1c97, d713801)
3. ~~**Phase 5b — Consensus hardening** (genesis config, anti-grinding, **PoSA mode**)~~ ✅ **Done** (commit 63bc062)
4. ~~**Phase 6.5b — Light client protocol** (Merkle proof RPC)~~ ✅ **Done** (commit bcdaf21)
5. **Phase 6.6 — Code hardening** (fix all critical/high issues found in code review)
6. *Then* Phase 7 (Forth VM) and Phase 8 (Ethereum interop)

These are detailed inline below as `⚠ REVISED` blocks.

---

## Table of Contents

- [Critical Assessment](#critical-assessment-2026-03-07)
- [Current State — What Already Exists](#current-state--what-already-exists)
- [Gap Analysis](#gap-analysis)
- [Architecture Principles](#architecture-principles)
- [Post-Quantum Strategy](#post-quantum-strategy)
- [Phase 1 — ed25519.f: Digital Signatures](#phase-1--ed25519f-digital-signatures)
- [Phase 1b — sphincs-plus.f: Post-Quantum Signatures](#phase-1b--sphincs-plusf-post-quantum-signatures)
- [Phase 2 — tx.f: Transaction Structure](#phase-2--txf-transaction-structure)
- [Phase 3 — state.f: World State](#phase-3--statef-world-state)
- [**Phase 3b — Scalable State (NEW)**](#phase-3b--scalable-state-new)
- [Phase 4 — block.f: Block Structure & Chain](#phase-4--blockf-block-structure--chain)
- [Phase 5 — consensus.f: Consensus Mechanism](#phase-5--consensusf-consensus-mechanism)
- [**Phase 5b — Consensus Hardening (NEW)**](#phase-5b--consensus-hardening-new)
- [Phase 6 — Node Infrastructure](#phase-6--node-infrastructure)
- [**Phase 6.5 — Production Infrastructure (NEW)**](#phase-65--production-infrastructure-new)
- [**Phase 6.6 — Code Hardening (NEW)**](#phase-66--code-hardening-new)
- [Phase 7 — contract-vm.f: Sandboxed Forth VM](#phase-7--contract-vmf-sandboxed-forth-vm)
- [Phase 8 — ethereum/: Standard Blockchain Interop](#phase-8--ethereum-standard-blockchain-interop)
- [Fork in the Road Options](#fork-in-the-road-options)
- [Dependency Graph](#dependency-graph)
- [Implementation Order (REVISED)](#implementation-order)
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

> **⚠ REVISED — Gap analysis is incomplete.**  The original gap
> analysis lists only *feature* gaps (no signatures, no tx format,
> etc.).  The real gaps that block production readiness are
> *architectural*:
>
> | Gap (new) | Impact | Complexity |
> |-----------|--------|------------|
> | ~~No real disk I/O~~ | ✅ **Resolved by Phase 6.5a.** `persist.f` rewrite (commit 3f9ca41) adds sector-based file I/O via KDOS words.  Crash recovery with journal replay. | Done |
> | ~~**No PoSA consensus mode**~~ | ✅ **Resolved by Phase 5b.** `consensus.f` Stage D adds PoSA (Mode 3) with staked-authority election.  `CON-SET-KEYS` fixes the CON-SEAL abstraction leak.  Commit 63bc062. | Done |
> | ~~Account cap = STARK trace width~~ | ✅ **Resolved by Phase 3b.** Paged state + SMT decouple account count from proof geometry. `_ST-MAX-PAGES` is a single constant (16 for emulator testing, crank up for production). | Done |
> | ~~No light client protocol~~ | ✅ **Resolved by Phase 6.5b.** `light.f` + `rpc.f` extensions deliver SMT proof generation/verification and four new RPC methods.  Light clients can verify account state against the state root without running a full node. | Done |
> | ~~No genesis-block config~~ | ✅ **Resolved by Phase 5b.** `genesis.f` (207 lines) encodes chain parameters (consensus mode, epoch length, authorities, balances) as CBOR in block 0.  Commit 63bc062. | Done |
> | ~~No anti-grinding for PoS~~ | ✅ **Resolved by Phase 5b.** Leader seed uses 2-block lookback (`block[height-2].hash`).  Shared by PoS and PoSA.  Commit 63bc062. | Done |
> | ~~Persist log cap~~ | ✅ **Resolved by Phase 6.5a.** Sector-based persistence replaced the fixed in-memory append buffer.  Capacity scales with available storage. | Done |
>
> These need to be addressed *before* Phase 7 (Forth VM).

---

## Architecture Principles

| Principle | Decision |
|-----------|----------|
| **Signature scheme** | Hybrid: Ed25519 (classical) + SPHINCS+-SHA3-128s (post-quantum).  Transactions carry both signatures; verifiers accept either or both depending on policy. |
| **Serialization** | CBOR everywhere — transactions, blocks, state entries.  DAG-CBOR for content addressing |
| **Hashing** | SHA3-256 for all chain hashing (block hash, address, Merkle).  Consistent with STARK internals |
| **Proof system** | STARK validity proofs optional per block — prover can attach proof that all state transitions are valid |
| **State model** | Account-based (not UTXO) — paged state tree (Phase 3b) with SMT, scales to arbitrary account counts.  `_ST-MAX-PAGES` is an emulator testing constant; production cranks it up. |
| **Block size** | 256 transactions max per block — matches STARK trace size for provability |
| **Consensus** | Pluggable — four leader-election modes: PoW (0), PoA (1), PoS (2), **PoSA (3)** × orthogonal STARK validity overlay flag.  PoW for bootstrap/dev, PoA for consortium, PoS for staked networks, PoSA for production.  Any mode can optionally attach STARK proofs; PoSA+STARK is the production endgame. |
| **Not re-entrant** | Same as all Akashic modules — serialized per guard for STARK determinism, but parallelizable for I/O and tx validation via KDOS multi-core |
| **No floating point** | All values are integers (Baby Bear field elements or 64-bit) |
| **Post-quantum ready** | SPHINCS+ (hash-based, FIPS 205) uses only SHA3/SHAKE — leverages the existing hardware accelerator.  No new algebraic structures needed. |
| **Custom chain first** | Phases 1–7 are a self-contained, purpose-built chain with smart contracts and full node infrastructure.  Not Ethereum/Bitcoin compatible by design.  Standard chain interop is deferred to Phase 8 (`ethereum/` library). |

> **⚠ REVISED — Architecture Principles annotations.**
>
> - **State model: "simpler for a 256-entry world"** — This is the
>   core problem.  The 256-entry world is a *prototype constraint*,
>   not a design principle.  It needs to be stated as a limitation
>   with a concrete upgrade path.  See Phase 3b below.
> - **Block size: 256 txs = STARK trace size** — This couples
>   throughput to proof geometry.  Any throughput increase requires
>   proof system changes.  Alternatives: batch multiple 256-tx
>   sub-proofs, recursive proof composition, or variable-width
>   traces.  Must be addressed before production.
> - **Not re-entrant** — Fine for Megapad-64 (single-core).  Should
>   be explicitly stated as "by hardware constraint" not "by choice."
>   On multi-core hardware this serializes everything.
>   However concurrency libraries are built and we can scale up somewhat.
>   It would require some refactoring and bumping gossip peer count.
 > - ~~**Consensus mode as variable**~~ **Resolved by Phase 5b.**
>   `genesis.f` encodes consensus mode in block 0 CBOR config.
>   `GEN-LOAD` sets `CON-MODE!` from the genesis payload at startup.
> - ~~**Missing principle: Chain ID / genesis config**~~ **Resolved by
>   Phase 5b.** `genesis.f` encodes chain ID, consensus mode, STARK
>   overlay flag, epoch length, min stake, lock period, authorities,
>   and initial balances.  Genesis block hash = chain identity.

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

> **⚠ REVISED — Bandwidth reality check.**
>
> "All well within 16 MiB" is true for *one block in memory*.
> But a *running chain* accumulates:
> - 2.1 MB/block × 1 block/minute × 60 min = 126 MB/hour in
>   hybrid mode.  The 1 MB persist log fills after ~0.5 blocks.
> - Gossip bandwidth: broadcasting a 2.1 MB block to 16 peers =
>   33.6 MB of outbound traffic per block.
> - Mempool: 256 pending hybrid txs = 2.1 MB.  A second wave
>   arriving before the first drains needs 4.2 MB.
>
> **Recommendation:** Default to Ed25519-only for all node
> operations.  Hybrid/SPHINCS+ should be opt-in per transaction
> by sender choice, not a network-wide mode.  The `TX-SIG-MODE`
> variable should be per-tx (it already is in the tx format), but
> the *node default* and *documentation* should strongly recommend
> classical-only unless the user has a specific PQ threat model.
>
> **PQ Transition Path:** When quantum computing matures enough to
> threaten Ed25519, the chain can migrate to pure PQ cleanly:
> 1. Genesis config already includes `sig_mode` — new chains can
>    launch PQ-only from day one.
> 2. Existing chains: a hard fork at block height N sets
>    `sig_mode: 1` (PQ-only).  Transactions after height N carry
>    only SPHINCS+ signatures.  Accounts created before the fork
>    already have PQ keys (hybrid mode stores both).
> 3. Grace period: accept both modes for M blocks after the fork,
>    then reject classical-only transactions.
> 4. No key migration needed — hybrid accounts already have SPHINCS+
>    keys registered.  Ed25519-only accounts must re-register with
>    a PQ keypair during the grace period.
>
> This is a genesis parameter + one fork, not a protocol redesign.

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
**Depends on:** merkle.f, sha3.f, tx.f, fmt.f
**Size:** ~640 lines (after Phase 3b rewrite)
**Difficulty:** Medium
**Status:** ✅ Implemented + tested; rewritten in Phase 3b (paged state + SMT)

### State Model

Account-based.  Each account is identified by a 32-byte address
(SHA3-256 of the Ed25519 public key) and stores:

```
Account entry (72 bytes):
  +0   32 bytes   address      (SHA3-256 of Ed25519 public key)
  +32   8 bytes   balance      (u64)
  +40   8 bytes   nonce        (u64, incremented on each send)
  +48   8 bytes   staked-amt   (reserved — Phase 5 PoS, zeroed)
  +56   8 bytes   unstake-ht   (reserved — Phase 5 PoS, zeroed)
  +64   8 bytes   last-blk     (reserved — Phase 5 PoS, zeroed)
```

The 72-byte entry size is fixed from day one — staking fields
are allocated but zeroed until Phase 5 adds PoS logic.  This
avoids a structural migration when PoS lands (Merkle roots
stay compatible).

### Storage

Paged XMEM-backed account table, sorted by address for O(log n)
binary-search lookup.  Each page holds 256 entries (STARK trace
aligned).  Pages allocated on demand.

State commitment via Sparse Merkle Tree (smt.f) — depth 256,
storage proportional to active accounts, not address space.
The state root goes into the block header.  Tree is rebuilt on
`ST-ROOT` (once per block finalization, not per transaction).

> **✅ RESOLVED by Phase 3b.**
>
> The old 256-account hardcoded cap is gone.  State is now:
> - **Paged**: 256 accounts/page, pages allocated on demand from XMEM.
> - **SMT-committed**: Sparse Merkle Tree replaces the dense 256-leaf tree.
> - **STARK-decoupled**: trace proves the *touched subset* per block, not all accounts.
>
> `_ST-MAX-PAGES` (currently 16 = 4096 accounts) is an **emulator
> testing value only**.  Production: bump to 256+ (65K+ accounts).
> The paging system, SMT, and snapshot code all scale automatically.

### API

| Word | Stack | Description |
|------|-------|-------------|
| `ST-INIT` | `( -- )` | Zero all accounts, reset Merkle tree |
| `ST-LOOKUP` | `( addr -- entry\|0 )` | Find account by address |
| `ST-CREATE` | `( addr balance -- flag )` | Create new account (sorted insert) |
| `ST-BALANCE@` | `( addr -- balance )` | Read balance (0 if not found) |
| `ST-NONCE@` | `( addr -- nonce )` | Read nonce (0 if not found) |
| `ST-APPLY-TX` | `( tx -- flag )` | Apply transaction: check sig, nonce, balance; update state |
| `ST-ROOT` | `( -- hash-addr )` | Rebuild tree + return 32-byte Merkle root |
| `ST-VERIFY-TX` | `( tx -- flag )` | Validate tx without applying (dry run) |
| `ST-ADDR-FROM-KEY` | `( pubkey addr -- )` | SHA3-256 hash pubkey → account address |
| `ST-COUNT` | `( -- n )` | Number of active accounts |
| `ST-ENTRY` | `( idx -- addr )` | Raw entry by index |
| `ST-PRINT` | `( -- )` | Debug dump |

### State Transition Integrity

`ST-APPLY-TX` checks:
1. Signature valid (`TX-VERIFY`)
2. Sender exists
3. Nonce matches sender's current nonce
4. Balance ≥ amount
5. Recipient exists (auto-create if not)
6. Credit overflow check (recipient balance + amount must not wrap)

On success: debit sender, credit recipient, increment sender nonce.
On failure: no state change.

Self-transfers (sender = recipient) are handled: amount cancels out,
nonce is bumped.

The pointer-invalidation problem (inserting a new recipient can shift
the sender's table position) is handled by working with indices and
adjusting the sender index when the recipient insertion point
precedes it.

---

## Phase 3b — Scalable State ✅

**Location:** `akashic/store/state.f` (rewrite) + `akashic/store/smt.f` (new) + `akashic/store/witness.f` (new)
**Prefix:** `ST-` (same public API, new internals) / `SMT-` / `WIT-`
**Depends on:** sha3.f, merkle.f, tx.f
**Actual size:** smt.f = 717 lines, state.f = 640 lines, witness.f = 467 lines
**Difficulty:** Hard
**Status:** ✅ Complete — smt.f (25 tests), state.f (14 + 21 state_tree tests), witness.f (22 tests).
**Priority:** **Critical** — must precede Phase 7
**Commits:** smt.f (35a8e8c), state.f (b9e1c97), witness.f (d713801)

### Problem

The *original* 256-account cap was welded to three things:
1. The flat sorted array (256 × 72 = 18 KB)
2. The 256-leaf Merkle tree
3. The 256-row STARK trace width

All three constraints were eliminated by Phase 3b.  The paged
state + SMT design decouples account count from proof geometry.
`_ST-MAX-PAGES` is now the only knob (set to 16 for emulator
testing; crank up for production).

### Solution: Sparse Merkle Tree + Paged State

**Step 1: Sparse Merkle Tree (smt.f)**

Replace the dense 256-leaf Merkle tree with a **sparse Merkle tree**
(SMT) of depth 256 (one bit per address byte).  An SMT can hold
$2^{256}$ theoretical leaves but only stores populated branches.
Storage is proportional to active accounts, not the address space.

The existing `merkle.f` can be extended (or a new `smt.f` built)
with:

| Word | Stack | Description |
|------|-------|-------------|
| `SMT-INIT` | `( tree -- )` | Empty tree (root = zero hash) |
| `SMT-INSERT` | `( key val tree -- )` | Insert/update leaf by 32-byte key |
| `SMT-LOOKUP` | `( key tree -- val flag )` | Get leaf value |
| `SMT-ROOT` | `( tree -- hash )` | Current root hash |
| `SMT-PROVE` | `( key tree proof -- len )` | Generate Merkle inclusion proof |
| `SMT-VERIFY` | `( key val proof len root -- flag )` | Verify inclusion proof (for light clients) |

Memory: ~32 bytes per active leaf × path length.  For 4,096
accounts: ~400 KB (much more than 18 KB, but manageable in XMEM).

**Step 2: Paged state table**

Replace the flat 256-entry sorted array with a paged structure.
Each page holds 256 entries (preserving STARK trace alignment).
Pages are allocated from XMEM on demand.  Binary search works
within and across pages.

This lets `ST-MAX-ACCOUNTS` grow to 4,096+ without a single
contiguous 300 KB allocation.

**Step 3: Decouple STARK trace from state size**

The key insight: the STARK trace doesn't need to cover *all*
accounts — it needs to cover *all transactions in one block*.
With 256 txs/block, each block touches at most 512 accounts
(256 senders + 256 recipients).  The trace proves the *touched
subset* is correct, and the SMT root proves the rest is unchanged.

This means:
- STARK trace stays 256 rows (one per tx)
- State can grow to any size
- Each trace row includes the SMT Merkle path for the touched
  accounts (proving they were correctly read and updated)

This is exactly how Starknet and zkSync work: the proof covers
the *delta*, not the full state.

### Migration

The public `ST-` API stays the same.  Internals change.
All downstream modules (block.f, consensus.f, node.f) should
need zero or minimal changes if they use the public API.

### Testing

- Existing 43 state tests must pass unchanged (API compatibility)
- SMT: insert/lookup/prove/verify for 1, 256, 1024, 4096 entries
- SMT proof verification matches root (positive + negative)
- Paged table: binary search across page boundaries
- STARK trace: prove block with accounts > 256, verify

---

## Phase 4 — block.f: Block Structure & Chain ✅

**Status:** Implemented — `akashic/store/block.f` (775 lines),
52 tests in `test_block.py` (all pass).

**Prefix:** `BLK-` (block) / `CHAIN-` (chain)
**Depends on:** tx.f, state.f, merkle.f, sha3.f, cbor.f, fmt.f, guard.f
**Actual size:** 775 lines
**Difficulty:** Medium

### Block Format

```
Block Header (248 bytes, 8-byte aligned):
  +0     1 byte    version      (u8, protocol version, initially 1)
  +1     8 bytes   height       (u64, block number, 0 = genesis)
  +9    32 bytes   prev_hash    (SHA3-256 of previous block header)
  +41   32 bytes   state_root   (Merkle root of state after applying txs)
  +73   32 bytes   tx_root      (Merkle root of transaction hashes)
  +105   8 bytes   timestamp    (u64, Unix seconds)
  +113   1 byte    proof_len    (u8, 0..128)
  +114 128 bytes   proof        (consensus-specific, fixed-size slot)
  --- 248 bytes total (padded for alignment) ---

Block Body (stored separately in struct, not in header):
  +248   8 bytes   tx_count     (cell)
  +256  2048 bytes tx_pointers  (256 × 8-byte cells → tx buffers)
  --- 2304 bytes total struct size ---
```

Block hash = SHA3-256 of CBOR-encoded header (7-field map in
DAG-CBOR canonical key order).

### Design Decisions

- **Separate header + pointer array:** The 248-byte header is self-contained
  for hashing and chain storage; tx data lives in separate `TX-BUF-SIZE`
  buffers referenced by pointers.  Avoids 2 MB inline buffer.
- **128-byte fixed proof slot:** Length-prefixed (`proof_len` byte at +113).
  Accommodates PoW nonce (8 bytes), PoA signature (64 bytes), or a
  STARK proof reference.  No variable-length allocation needed.
- **Snapshot-and-restore validation:** `BLK-VERIFY` uses `ST-SNAPSHOT` /
  `ST-RESTORE` (18,440 bytes) to tentatively apply txs, check the state
  root, then restore original state — fully non-destructive.  This is the
  industry-standard pattern (Ethereum's copy-on-write overlay, Bitcoin's
  CCoinsViewCache, Cosmos SDK's cache-wrapped state).
- **Single mutation point:** Only `CHAIN-APPEND` permanently applies txs
  to global state.  `BLK-VERIFY` and `BLK-FINALIZE` (producer path) have
  clearly separated roles.
- **Consensus callback:** `_BLK-CON-CHECK-XT` variable holds the XT of
  the consensus proof validator.  Defaults to always-TRUE.  `consensus.f`
  (Phase 5) patches this at load time.
- **64-block circular history:** `CHAIN-HISTORY = 64`.  Easy to bump
  (single constant change).  Headers only in ring buffer (248 bytes each
  = 15.5 KB total).  Tx data is ephemeral.

### API (block)

| Word | Stack | Description |
|------|-------|-------------|
| `BLK-INIT` | `( blk -- )` | Zero struct, set version |
| `BLK-SET-PREV` | `( hash blk -- )` | Set previous block hash |
| `BLK-SET-HEIGHT` | `( n blk -- )` | Set block height |
| `BLK-SET-TIME` | `( t blk -- )` | Set timestamp |
| `BLK-SET-PROOF` | `( addr len blk -- )` | Set consensus proof (≤128 bytes) |
| `BLK-ADD-TX` | `( tx blk -- flag )` | Append tx pointer (fail if full) |
| `BLK-FINALIZE` | `( blk -- )` | Compute tx root, apply txs, store state root |
| `BLK-HASH` | `( blk hash -- )` | SHA3-256 of CBOR-encoded header |
| `BLK-VERIFY` | `( blk prev-hash -- flag )` | Full non-destructive validation |
| `BLK-ENCODE` | `( blk buf max -- len )` | Full CBOR serialization (header + txs) |
| `BLK-DECODE` | `( buf len blk -- flag )` | Deserialize header from CBOR |
| `BLK-HEIGHT@` | `( blk -- n )` | Read height |
| `BLK-TX-COUNT@` | `( blk -- n )` | Read tx count |
| `BLK-VERSION@` | `( blk -- n )` | Read version |
| `BLK-TIME@` | `( blk -- n )` | Read timestamp |
| `BLK-PREV-HASH@` | `( blk -- addr )` | Pointer to prev_hash |
| `BLK-STATE-ROOT@` | `( blk -- addr )` | Pointer to state_root |
| `BLK-TX-ROOT@` | `( blk -- addr )` | Pointer to tx_root |
| `BLK-PROOF@` | `( blk -- addr len )` | Proof data + length |
| `BLK-TX@` | `( idx blk -- tx )` | Get tx pointer by index |
| `BLK-PRINT` | `( blk -- )` | Debug dump |

### API (chain)

| Word | Stack | Description |
|------|-------|-------------|
| `CHAIN-INIT` | `( -- )` | Init chain with genesis block |
| `CHAIN-HEAD` | `( -- blk )` | Current chain tip header |
| `CHAIN-APPEND` | `( blk -- flag )` | Validate + apply + append |
| `CHAIN-HEIGHT` | `( -- n )` | Current chain height |
| `CHAIN-BLOCK@` | `( n -- blk \| 0 )` | Header by height (recent only) |

### Block Validation (`BLK-VERIFY`)

1. `prev_hash` matches supplied previous hash
2. Timestamp non-zero for non-genesis blocks
3. All transactions valid (`TX-VERIFY` signature check)
4. No duplicate (sender, nonce) pairs within block
5. Transaction Merkle root matches (recomputed)
6. State root matches (snapshot → apply → compare → restore)
7. Consensus proof valid (via `_BLK-CON-CHECK-XT` callback)

All concurrency-sensitive words wrapped with `GUARD`/`WITH-GUARD`.

---

## Phase 5 — consensus.f: Consensus Mechanism

**Prefix:** `CON-`
**Depends on:** block.f, state.f, stark.f (optional), ed25519.f, random.f
**Actual size:** 939 lines (677 Stage A+B, 262 Stage D PoSA + signing context + anti-grinding)
**Difficulty:** Medium
**Status:** ✅ Implemented (modes 0–3) — PoSA added by Phase 5b (commit 63bc062)

### Four Leader-Election Modes + STARK Overlay

The consensus module separates two orthogonal concerns:

1. **Leader election** — who produces the next block.  Selected by
   `CON-MODE` (0=PoW, 1=PoA, 2=PoS, 3=PoSA).
2. **Validity proving** — whether the block carries a STARK proof.
   Toggled by `CON-STARK?` (boolean flag, independent of mode).

This gives 8 combinations (4 modes × STARK on/off).  All share the
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
four leader-election modes (PoW, PoA, PoS, PoSA).

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

#### 5.5 Production Endgame: PoSA + STARK

The planned production configuration: `CON-MODE=3` (PoSA) +
`CON-STARK?=TRUE`.  PoSA combines an authorized validator set with
stake weighting — giving the trust assumptions of PoA with the
economic incentives of PoS.  Adding STARK brings mathematical
validity proofs on top:

- **PoSA decides who** produces the block (authorized + stake-weighted leader election)
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
| PoSA | Authorized set + stake | Signature | optional | Minimal | Identified + staked | Immediate | ~120 |
| **PoSA+STARK** | **Authorized set + stake** | **Math proof** | **✓** | **Minimal** | **Identified + staked** | **Immediate** | **~120+60** |

STARK overlay adds ~60 lines of shared glue regardless of mode.

#### 5.7 Unified Interface

| Word | Stack | Description |
|------|-------|-------------|
| `CON-MODE` | `CON-MODE@` / `CON-MODE!` | 0=PoW, 1=PoA, 2=PoS, 3=PoSA |
| `CON-STARK?` | variable | TRUE = attach STARK validity proof to blocks (any mode) |
| `CON-SEAL` | `( blk -- )` | Apply leader election + optional STARK proof |
| `CON-CHECK` | `( blk -- flag )` | Verify leader election + STARK proof (if present) |

> **⚠ REVISED — Consensus issues that must be fixed before production.**
>
> 1. ~~**`CON-MODE` is a runtime variable, not a genesis parameter.**~~
>    **Resolved by Phase 5b.** `genesis.f` encodes consensus mode in
>    block 0 CBOR payload.  `GEN-LOAD` sets `CON-MODE!` at startup.
>
> 2. ~~**`CON-SEAL` leaks its abstraction for PoA and PoS.**~~
>    **Resolved by Phase 5b.** `CON-SET-KEYS ( priv pub -- )` stores
>    the node's signing keys.  `CON-SEAL` uses them for all modes.
>
> 3. ~~**PoS leader election is grindable.**~~
>    **Resolved by Phase 5b.** Seed now uses 2-block lookback:
>    `SHA3(block[height-2].hash || height)`.  Shared by PoS and PoSA.
>
> 4. ~~**PoS validator set shares the 256-account table with users.**~~
>    ✅ Partially resolved by Phase 3b — account count is no longer
>    capped at 256.  However, the validator set may still benefit
>    from being a *separate* data structure rather than overloaded
>    onto account entries (performance optimization, not a blocker).
>
> 5. **`VM-VERIFY-SPHINCS` is missing from the contract whitelist.**
>    SPHINCS+ verify at 50M steps would consume 5× the default
>    10,000 gas limit.  Contracts cannot verify PQ signatures.
>    Either add it with proportional gas cost (~50,000 gas) or
>    document that on-chain PQ signature verification is not
>    supported.

---

## Phase 5b — Consensus Hardening (NEW)

**Location:** `akashic/consensus/consensus.f` (modified) + `akashic/store/genesis.f` (new)
**Prefix:** `GEN-` (genesis), `CON-` (consensus amendments)
**Depends on:** consensus.f, block.f, state.f, **stark.f multi-column (Phase 4.5 in STARK-design.md)**
**Actual size:** consensus.f +262 lines (677 → 939), genesis.f 207 lines new = **469 lines total**
**Difficulty:** Medium
**Status:** ✅ **Complete** (commit 63bc062) — 13/13 Phase 5b tests + 31/31 Stage A regression tests passing
**Priority:** **Critical** — must precede production multi-node deployment

> **⚠ PREREQUISITE DISCOVERED:** The STARK validity overlay (§5.2)
> needs multi-column traces (one column per field: old_bal, new_bal,
> amount, nonce_old, nonce_new).  The current stark.f v2 only has a
> single NTT polynomial trace, while stark-air.f already supports
> multi-column AIR descriptors.  **Phase 4.5 (multi-column traces in
> stark.f) must be completed before wiring the STARK overlay.**
> See STARK-design.md Phase 4.5 for the spec.

### 5b.1 Genesis Block Configuration

Create `genesis.f` that encodes chain parameters into the genesis
block's `data` field (CBOR map):

```
Genesis config (CBOR map in block 0 data):
  "chain_id"     : u64       distinguishes networks
  "con_mode"     : u8        0=PoW, 1=PoA, 2=PoS, 3=PoSA
  "stark"        : bool      STARK overlay required?
  "epoch_len"    : u64       blocks per epoch (PoS)
  "min_stake"    : u64       minimum stake (PoS)
  "lock_period"  : u64       unstake lock blocks (PoS)
  "max_accounts" : u64       state table capacity
  "max_txs"      : u64       transactions per block
  "authorities"  : [pubkey]  initial PoA signers (if PoA)
  "balances"     : {addr:u64} initial account balances
```

`NODE-INIT` reads the genesis block and sets all `CON-*` variables
from it.  Nodes that connect to a chain with a different genesis
hash are rejected during `STATUS` handshake.

| Word | Stack | Description |
|------|-------|-------------|
| `GEN-CREATE` | `( config blk -- )` | Build genesis block from config |
| `GEN-LOAD` | `( blk -- )` | Extract config from genesis, set globals |
| `GEN-HASH` | `( -- hash )` | Genesis block hash (= chain identity) |
| `GEN-CHAIN-ID` | `( -- id )` | Chain ID from genesis |

### 5b.2 Anti-Grinding for PoS Leader Election

Replace the current `SHA3(prev_hash || height)` seed with a
**2-block lookback** scheme:

```
seed = SHA3( block[height-2].hash || height )
```

The block producer at height H cannot influence the seed for
height H+1, because the seed depends on block H-1's hash
(which was finalized before the producer was elected).

For stronger guarantees, add a **RANDAO** accumulator:
- Each block producer commits `SHA3(secret)` in their first
  epoch block, reveals `secret` when producing.
- The epoch seed = XOR of all reveals.
- Withholding a reveal = forfeiting the block reward.

RANDAO is ~50 lines and a well-understood pattern (Ethereum
Beacon Chain uses it).

### 5b.3 Fix CON-SEAL Abstraction Leak

Add a **signing context** variable that holds the block producer's
key material:

```forth
CREATE _CON-SIGN-PRIV 64 ALLOT
CREATE _CON-SIGN-PUB  32 ALLOT

: CON-SET-KEYS ( priv pub -- )
    _CON-SIGN-PUB 32 CMOVE
    _CON-SIGN-PRIV 64 CMOVE ;
```

Then `CON-SEAL ( blk -- )` works uniformly for all modes:
- PoW: mine (no keys needed)
- PoA: `CON-POA-SIGN blk _CON-SIGN-PRIV _CON-SIGN-PUB`
- PoS: `CON-POS-SIGN blk _CON-SIGN-PRIV _CON-SIGN-PUB`

Caller sets keys once at startup via `CON-SET-KEYS`.

### 5b.4 PoW "Testing Only" Label

PoW mode with 1-block max reorg is fundamentally broken for real
networks.  Either:
- Implement a proper longest-chain rule with configurable reorg
  depth (complex, ~200 lines), or
- Label PoW as `CON-POW-DEV` and restrict it to single-node
  testing (simple, just documentation + a warning on multi-node
  init).

Recommendation: the latter.  PoW on a small network of identical
hardware provides no meaningful Sybil resistance anyway.

### 5b.5 PoSA Mode (Mode 3) — Production Consensus

**This is the planned production mode.**  PoSA (Proof-of-Staked-Authority)
combines an authorized validator set (like PoA) with stake weighting
(like PoS).  Validators must both be in the authorized set *and* stake
tokens, preventing participation without skin in the game.

Key design points:
- Authority set stored in genesis config (`"authorities"` key)
- Each authority must also have a stake above `min_stake`
- Leader rotation: round-robin among staked authorities, weighted
  by stake for tie-breaking / priority
- Slashing: double-sign → slash stake (reuse PoS slashing logic)
- Epoch transitions: authority set + stakes re-evaluated per epoch

Estimated ~120 lines on top of existing PoA + PoS infrastructure.
Reuses `CON-POA-AUTH*` for the authority list and `CON-POS-STAKE*`
for stake queries.  New words:

| Word | Stack | Description |
|------|-------|-------------|
| `CON-POSA-CHECK` | `( blk -- flag )` | Verify: in authority set AND staked |
| `CON-POSA-ELECT` | `( height -- pubkey )` | Stake-weighted round-robin leader |
| `CON-POSA-SIGN` | `( blk priv pub -- )` | Produce PoSA seal |

---

## Phase 6 — Node Infrastructure

**Location:** `akashic/store/` (mempool, persistence) + `akashic/web/` (gossip, RPC) + `akashic/net/` (sync)
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

For a chain with modest state (especially during early deployment),
a simple sequential sync is sufficient:

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

> **⚠ REVISED — Reorg and light client gaps.**
>
> - **1-block reorg limit is fine for PoA/PoS** (fast finality)
>   but **incompatible with PoW mode**.  Under PoW with low
>   difficulty (bootstrap), network partitions trivially produce
>   2+ block forks.  Either: (a) remove PoW as a "real" mode
>   and label it "local testing only," or (b) implement a
>   longest-chain rule with configurable reorg depth.
>
> - ~~**No light client protocol.**~~  ✅ **Resolved by Phase 6.5b.**
>   `light.f` + `rpc.f` extensions deliver proof-based light client support.
>
> - ~~**No Merkle proof-of-inclusion RPC.**~~  ✅ **Resolved by Phase 6.5b.**
>   `chain_getProof`, `chain_getBlockProof`, `chain_getStateRoot`,
>   `chain_verifyProof` all implemented and tested.

### 6e — persist.f: Chain Persistence *(superseded by Phase 6.5a)*

**Prefix:** `PST-`
**Depends on:** state.f, block.f, cbor.f
**Original estimated size:** ~80–100 lines
**Status:** ~~Superseded~~ — Phase 6.5a (commit 3f9ca41) rewrote persist.f with real KDOS file I/O (284 lines, 9 tests).

> The original 6e design described below was an in-memory append buffer.
> It has been completely replaced by Phase 6.5a's sector-based persistence.
> This section is retained for historical reference.

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

> ~~**⚠ REVISED — persist.f is not persistence.  It’s an in-memory**~~
>
> ✅ **Resolved by Phase 6.5a** (commit 3f9ca41).  `persist.f` was
> rewritten with sector-based file I/O via KDOS words.  Chain data
> and state snapshots persist to disk.  Crash recovery via journal
> replay.  The 1 MB cap and XMEM-only storage are gone.

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
\   consensus    ( 0=PoW, 1=PoA, 2=PoS, 3=PoSA )
\   stark?       ( flag — attach STARK validity proofs )
\   data-dir     ( path to chain.dat / state.snap )
```

---

## Phase 6.5 — Production Infrastructure (NEW)

**Priority:** **Critical** — prerequisite for any real deployment.
Split into two sub-phases that can proceed in parallel.

### Phase 6.5a — Real Persistence ✅

**Location:** `akashic/store/persist.f` (rewrite)
**Prefix:** `PST-`
**Depends on:** KDOS file I/O primitives, block.f, state.f
**Actual size:** 284 lines
**Difficulty:** Medium
**Status:** ✅ Complete (commit 3f9ca41) — 9 tests
**Commit:** 3f9ca41

The original `persist.f` was an in-memory append buffer using
`XMEM-ALLOT` with a 1 MB cap.  The rewrite replaced it with
real sector-based disk persistence via KDOS file I/O words.

#### KDOS File I/O Primitives (no wrapper needed)

KDOS (§7.5 raw file I/O, §7.6 MP64FS named filesystem) provides
a complete file I/O stack.  No separate `fileio.f` wrapper layer
is needed — we use the KDOS words directly:

| Need | KDOS word | Stack effect |
|------|-----------|-------------|
| Create file | `MKFILE` | `( nsectors type "name" -- )` |
| Open file | `OPEN` | `( "name" -- fdesc \| 0 )` |
| Read bytes | `FREAD` | `( addr len fdesc -- actual )` |
| Write bytes | `FWRITE` | `( addr len fdesc -- )` |
| Seek | `FSEEK` | `( pos fdesc -- )` |
| Rewind | `FREWIND` | `( fdesc -- )` |
| File size | `FSIZE` | `( fdesc -- n )` |
| Flush metadata | `FFLUSH` | `( fdesc -- )` |
| Close | `FCLOSE` | `( fdesc -- )` |
| Delete | `RMFILE` | `( "name" -- )` |

**Quirks to handle:**
- `MKFILE` pre-allocates a fixed sector count (contiguous).
  Files cannot be resized — over-allocate and track used bytes.
- `FREAD` / `FWRITE` operate via DMA (whole sectors).  The
  FREAD bug (return-stack corruption in FR-HEAD) is fixed as of
  megapad commit c574899.
- `FFLUSH` syncs the `used_bytes` metadata to the on-disk
  directory; content is written directly to disk sectors by
  `FWRITE` (DMA).
- FD pool is 16 slots — persist.f needs at most 3 (chain.dat,
  state.snap, wal.dat).

**Future migration:** When Akashic's higher-level filesystem
libraries are built (see `ROADMAP_filesystem.md`), rewrite this
module against those abstractions.  The API (`PST-INIT`,
`PST-SAVE-BLOCK`, etc.) stays the same — only the internals change.

#### Rewrite persist.f

Replace the XMEM append buffer with real file storage:

```
chain.dat: [length-prefixed CBOR blocks, append-only]
  [8B len][CBOR block 0][8B len][CBOR block 1] ...

state.snap: [periodic state snapshots]
  [8B height][8B count][count × 72B accounts][32B state root]

wal.dat: [write-ahead log for crash recovery]
  [8B seq][8B len][CBOR block][8B checksum]
```

Write-ahead log ensures atomicity: write the block to WAL first,
fsync, then append to chain.dat and update state.snap.  On
startup, replay any incomplete WAL entries.

| Word | Stack | Description |
|------|-------|-------------|
| `PST-INIT` | `( path len -- flag )` | Open/create chain files |
| `PST-SAVE-BLOCK` | `( blk -- flag )` | WAL → append → fsync |
| `PST-LOAD-BLOCK` | `( idx blk -- flag )` | Read block by index |
| `PST-SAVE-STATE` | `( -- flag )` | Write state snapshot |
| `PST-LOAD-STATE` | `( -- flag height )` | Load state snapshot |
| `PST-REPLAY-WAL` | `( -- n )` | Recovery: replay uncommitted blocks |
| `PST-BLOCK-COUNT` | `( -- n )` | Total blocks on disk |
| `PST-CLOSE` | `( -- )` | Flush + close all files |

No more arbitrary size cap.  Chain grows until disk is full.

### Phase 6.5b — Light Client Protocol

**Location:** `akashic/store/light.f` (new) + `akashic/web/rpc.f` (extended)
**Prefix:** `LC-` / `_LC-` (light.f), `RPC-` (rpc.f extensions)
**Depends on:** state.f, block.f, merkle.f (uses existing 256-leaf dense Merkle tree)
**Actual size:** ~177 lines (light.f) + ~200 lines (rpc.f additions) = ~377 total
**Difficulty:** Easy
**Status:** ✅ Done — 19/19 tests passing
**Tests:** `local_testing/test_light.py`
**Docs:** `docs/store/light.md`

#### New RPC Methods

| Method | Params | Result | Description |
|--------|--------|--------|-------------|
| `chain_getProof` | address | `{balance, nonce, proof: [hashes]}` | Merkle inclusion proof |
| `chain_getBlockProof` | height, tx_index | `{tx_hash, proof: [hashes]}` | Tx inclusion in block |
| `chain_getStateRoot` | height | `{state_root, block_hash}` | State root at height |
| `chain_verifyProof` | address, proof, root | `{valid: bool}` | Server-side proof check |

#### Light Client Verification Flow

```
1. Client requests chain_getProof(address)
2. Server returns {balance, nonce, merkle_path, state_root}
3. Client verifies: SMT-VERIFY(address, leaf, path, state_root)
4. Client trusts state_root because:
   a. STARK mode: verify block's STARK proof (math guarantee)
   b. Non-STARK: trust the RPC server (same as Ethereum pre-Verkle)
```

With STARK overlay enabled, a light client can verify:
- The state root is committed in the block header
- The block's STARK proof validates all state transitions
- The Merkle path proves the specific account in that state root

This gives **trust-minimized light client verification** — the
client only needs the block header, STARK proof, and Merkle path.
No re-execution, no trusting the RPC server.

---

## Phase 6.6 — Code Hardening (NEW)

**Depends on:** All Phase 1–6.5b modules
**Priority:** **Critical** — must precede Phase 7
**Status:** Not started

A full code review of Phases 1–6.5b uncovered **11 critical, 9 high,
and 10 medium** production-readiness issues across 15 modules (~6,300
lines).  None of these are design problems — the architecture is sound.
They are implementation gaps: timing leaks, off-by-one bugs, capacity
mismatches, dead code paths, missing bounds checks, and stub logic
that was never wired up.  All must be fixed before Phase 7.

### 6.6a — Crypto Hardening (ed25519.f, sphincs-plus.f)

| # | Severity | File | Issue | Fix |
|---|----------|------|-------|-----|
| 1 | **CRITICAL** | ed25519.f | `_ED-SMUL` branches on secret scalar bits — timing side-channel leaks private key | Constant-time conditional swap (CMOV pattern) |
| 2 | **CRITICAL** | ed25519.f | Missing `S < L` check in `ED25519-VERIFY` — signature malleability (RFC 8032 §5.1.7) | Add scalar range check before accepting signature |
| 3 | **HIGH** | ed25519.f | `_ED-PINV0` zeroed and never initialized — may break all scalar mod-L arithmetic | Verify initialization or compute on first use |
| 4 | **HIGH** | ed25519.f | `_ED-DECODE` doesn't reject `y ≥ p` — non-canonical encoding (RFC 8032 §5.1.3) | Add canonical check |
| 5 | **MEDIUM** | ed25519.f | Secret material (`_ED-H64`, `_ED-SC1`, `_ED-SC3`) never zeroed after use | Add explicit zeroization |
| 6 | **CRITICAL** | sphincs-plus.f | WOTS+ checksum extraction: `4 LSHIFT` before nibble extraction — off-by-one nibble breaks FIPS 205 interop | Remove the `4 LSHIFT` |
| 7 | **MEDIUM** | sphincs-plus.f | Secret seed `_SPX-RNG-SEED` (48 bytes) never zeroed after keygen | Add explicit zeroization |
| 8 | **MEDIUM** | sphincs-plus.f | No signature length validation in `SPX-VERIFY` — truncated sig causes OOB reads | Validate length before parse |

### 6.6b — Transaction & State Hardening (tx.f, state.f, smt.f)

| # | Severity | File | Issue | Fix |
|---|----------|------|-------|-----|
| 9 | **CRITICAL** | tx.f | Hybrid verify uses `OR` not `AND` — accepts tx if *either* sig valid, defeats defense-in-depth | Change `OR` → `AND` |
| 10 | **MEDIUM** | tx.f | `TX-SET-AMOUNT` accepts negative/zero amounts | Add validation |
| 11 | **MEDIUM** | tx.f | No CBOR output bounds check in `_TX-ENCODE-UNSIGNED` | Add buffer-length guard |
| 12 | **CRITICAL** | state.f / smt.f | SMT capacity mismatch — state allows 4096 accounts (`_ST-MAX-PAGES=16`) but `SMT-MAX-LEAVES=2048` | Align both to same value |
| 13 | **HIGH** | state.f | `_ST-REBUILD-TREE` drops `SMT-INSERT` return flag — ignores insertion failures | Check and propagate error |
| 14 | **MEDIUM** | state.f | Full SMT rebuild on every `ST-ROOT`/`ST-PROVE` — O(n log n) per call | Cache / incremental update |
| 15 | **MEDIUM** | state.f | Staking extension is stub — `TX-STAKE`/`TX-UNSTAKE` unconditionally fail | Implement or clearly gate behind feature flag |
| 16 | **HIGH** | smt.f | `_SMT-NODE(0)` causes memory underflow — `(0-1) * 96` wraps to massive offset | Guard node-0 access |
| 17 | **MEDIUM** | smt.f | `_SMT-PROVE` writes `40 × depth` bytes with no buffer size check | Add bounds check |

### 6.6c — Block & Consensus Hardening (block.f, consensus.f, genesis.f)

| # | Severity | File | Issue | Fix |
|---|----------|------|-------|-----|
| 18 | **CRITICAL** | consensus.f | STARK stubs always return TRUE (`_CON-STARK-CHECK-STUB`) — if STARK overlay enabled, all proofs auto-pass | Wire real STARK verify or make stub return FALSE (fail-closed) |
| 19 | **CRITICAL** | consensus.f | `CON-POS-LEADER` division by zero when total stake = 0 | Guard with zero-stake check |
| 20 | **CRITICAL** | consensus.f | `CON-POS-LEADER` fallback: `(-1) * 32` underflow when validator count = 0 | Guard with zero-validator check |
| 21 | **MEDIUM** | consensus.f | `CON-POW-MINE` infinite loop with no timeout/escape | Add iteration cap or yield |
| 22 | **HIGH** | block.f | `BLK-FINALIZE` and `CHAIN-APPEND` silently drop `ST-APPLY-TX` return value | Check and abort on failure |
| 23 | **MEDIUM** | genesis.f | Positional CBOR parse — no key-name validation, schema changes break silently | Validate key names |
| 24 | **MEDIUM** | genesis.f | `GEN-HASH` doesn't incorporate state/tx roots — different states produce same genesis hash | Include roots in hash preimage |
| 25 | **HIGH** | genesis.f | Stack corruption — `2DROP` on authority key length mismatch when stack has only 1 item | Fix stack discipline |

### 6.6d — Node Infrastructure Hardening (gossip.f, rpc.f, persist.f, node.f)

| # | Severity | File | Issue | Fix |
|---|----------|------|-------|-----|
| 26 | **HIGH** | gossip.f | No peer-id bounds check — id ≥ 16 causes OOB write/read | Bounds-check in `GSP-CONNECT`/`GSP-DISCONNECT` |
| 27 | **MEDIUM** | gossip.f | Seen-hash ring only 256 entries — trivially exhausted by flooding peer | Increase ring or add per-peer rate limit |
| 28 | **HIGH** | rpc.f | `chain_sendTransaction` never broadcasts tx to network after mempool add | Add `GSP-BROADCAST-TX` call |
| 29 | **HIGH** | rpc.f | `_RPC-RESP-ERROR` stack imbalance — extra `DROP` corrupts stack on every error response | Fix stack effect |
| 30 | **MEDIUM** | rpc.f | No rate limiting on POST /rpc — DoS vector | Add simple rate limiter |
| 31 | **HIGH** | persist.f | `_PST-STATE-SECTORS=40` / `_PST-CHAIN-SECTORS=1024` — emulator-sized, chain.dat can't grow | Make sector counts configurable or auto-grow |
| 32 | **CRITICAL** | node.f | `MP-DRAIN` writes tx pointers into block struct address — buffer overwrite | Use separate CELLS array |
| 33 | **CRITICAL** | node.f | `NODE-STEP` never calls `SRV-STEP` — HTTP/RPC is dead at runtime | Add `SRV-STEP` to main loop |
| 34 | **CRITICAL** | node.f | Timestamp hardcoded to `1` (TODO acknowledged) — breaks all time-dependent logic | Read RTC or KDOS timer |
| 35 | **HIGH** | node.f | `_NODE-PERSIST-TICK` never called in `NODE-STEP` — blocks never persisted during normal operation | Wire into main loop |
| 36 | **MEDIUM** | node.f | `NODE-RUN` is a busy loop — 100% CPU, no sleep/yield | Add yield/sleep |
| 37 | **MEDIUM** | node.f | `NODE-STOP` doesn't flush state, close persistence, or drain mempool | Add graceful shutdown sequence |

### Summary

| Sub-phase | Files touched | Critical | High | Medium |
|-----------|---------------|----------|------|--------|
| 6.6a — Crypto | ed25519.f, sphincs-plus.f | 3 | 2 | 3 |
| 6.6b — Tx/State | tx.f, state.f, smt.f | 2 | 2 | 5 |
| 6.6c — Block/Consensus | block.f, consensus.f, genesis.f | 3 | 2 | 3 |
| 6.6d — Node Infra | gossip.f, rpc.f, persist.f, node.f | 3 | 5 | 4 |
| **Total** | **12 files** | **11** | **11** | **15** |

Each sub-phase is independently testable.  Existing test suites
(~280 tests) must continue to pass after each fix — regressions
are the primary risk.  New tests should be added for each fix
(estimated +30–50 tests).

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
compiles to threaded code natively.  There is no need to design a
secondary instruction set — the host's own compilation machinery
(scoped to a sandbox) produces the on-chain executable format.

> **⚠ REVISED — Phase 7 is blocked on Phase 5b.**
>
> The Forth VM design is sound and the security analysis is
> unusually thorough.  Foundation blockers resolved so far:
> - ~~256-account cap~~ ✅ Phase 3b (paged state + SMT)
> - ~~No real persistence~~ ✅ Phase 6.5a (sector-based file I/O)
> - ~~No light client protocol~~ ✅ Phase 6.5b (Merkle proof RPC)
>
> **~~Remaining blocker:~~** ~~Phase 5b (consensus hardening + **PoSA mode**).~~
> ✅ **Resolved.** Phase 5b complete (commit 63bc062).
> Genesis-enforced consensus, anti-grinding, CON-SET-KEYS, and PoSA
> (Mode 3) are all implemented.
>
> **New ordering:** Phase 5b is done.  The VM has a
> solid foundation.
>
> The VM design itself is good.  The `TX-MAX-DATA` bump should use
> the gas-limited approach (no hard byte cap — remove the constant,
> let data size be bounded by gas at 1 gas/byte).  This matches
> EVM calldata semantics and avoids layout-breaking constant
> changes every time capacity needs increase.

> **⚠ REVISED — Two-Tier Sandbox Architecture (from JIT/binimg analysis)**
>
> The existing `binimg.f` / `.m64` binary image system provides a
> natural capability-based sandbox that the original ITC-only design
> overlooks.  The JIT compiler in `bios.asm` (3-tier: primitive
> inlining, literal folding, bigram fusion) is a real compiler that
> produces optimized native STC.  The `.m64` loader's
> `_IMG-RESOLVE-IMPORTS` is the single chokepoint where a loaded
> image gains access to host words — by name, from an import table.
>
> **Tier 1 — .m64 Sandbox (for trusted/consortium deployers):**
> Contracts are compiled as normal Forth (with JIT), saved as `.m64`,
> and loaded via a modified `IMG-LOAD` that:
> - Resolves imports against a **~60-word whitelist** (not `FIND`
>   against the full dictionary)
> - Maps `@`/`!` to bounds-checked `VM-@`/`VM-!`
> - Strips `EXECUTE` or maps it to a validated trampoline
> - Skips `_IMG-SPLICE-DICT` — contract is callable only through
>   its declared entry point
> - Rejects images importing unlisted words
>
> This gives **JIT-native speed** with capability-based isolation.
> ~100 lines of Forth to add (whitelist resolver, bounded accessors,
> `EXECUTE` guard).  The import manifest also enables pre-deployment
> audit: inspect exactly what a contract will call before loading.
>
> **Tier 2 — ITC Shadow Interpreter (for adversarial deployments):**
> The full shadow-dictionary ITC design (described below) for
> environments where deployers are not trusted.  Slower but with
> deeper isolation: separate return stack, scoped `HERE`, no native
> code execution.
>
> **STARK proof model — State-transition proofs (both tiers):**
> Instead of tracing every instruction (which forces ITC and kills
> JIT performance), prove *state transitions*: the contract's
> reads, writes, and final state root.  The STARK proves "given
> these inputs, the contract produced these outputs and these state
> changes."  This is how Starknet and zkSync work — prove the
> syscall trace, not every instruction.  It permits Tier 1 (JIT)
> contracts to run at full native speed while remaining
> validity-proven at the state level.
>
> **Recommendation:** Start with Tier 1 (.m64 sandbox) for the
> consortium use case.  The infrastructure already exists in
> `binimg.f`.  Tier 2 (full ITC) can be added later if/when
> adversarial public deployment becomes a requirement.

### Why Forth VM, Not EVM

| Factor | EVM | Forth VM |
|--------|-----|----------|
| Word size | 256-bit (alien to Megapad-64's 64-bit cells) | Native 64-bit cells |
| STARK provability | Painful — 256-bit ALU ops explode trace width | Natural — each primitive = 1–2 trace rows in Baby Bear field |
| Implementation cost | ~5,000+ lines (256-bit ALU, gas, memory model, precompiles) | ~400–600 lines (sandbox existing interpreter) |
| Contract language | Solidity → bytecode (need external compiler) | Forth source compiled at deploy → ITC stored on-chain |
| Ecosystem integration | Foreign stack — cannot call `SHA3`, `MERKLE-ROOT` directly | Contracts call any whitelisted Akashic word natively |
| Gas metering | Per-opcode table (256 opcodes) | Per-word decrement — trivial, ~5 lines |
| Determinism | Complex (JUMPDEST analysis, memory expansion rules) | Inherent — no floating point, no I/O in sandbox |

The EVM requires implementing a 256-bit ALU from scratch on a 64-bit
machine.  Every ADD, MUL, SMOD becomes a multi-limb software routine.
STARK-proving those operations means each EVM instruction maps to
dozens of trace rows — destroying the compact proofs that make the
custom chain valuable.  The Forth VM avoids all of this.

### Architecture: Compile-at-Deploy, Execute-on-Call

Contracts follow a **two-phase lifecycle**: deployment compiles Forth
source into indirect-threaded code (ITC) inside a sandbox; the
compiled image is stored on-chain (CBOR-encoded in the state tree).
Subsequent calls load the compiled image and execute directly — no
re-parsing, no re-compilation.

```
  DEPLOY:  source text ──► sandbox compiler ──► ITC image ──► state tree
  CALL:    state tree ──► load ITC image ──► execute in sandbox
```

This eliminates the parse-every-call overhead, shrinks on-chain
storage (~2–4× smaller than source), keeps STARK traces clean (no
parser rows), and confines the parser attack surface (S12) to deploy
transactions only.

#### Sandbox Execution Environment

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

#### ITC Image Format

The compiled image stored on-chain is a relocatable ITC blob:

```
Offset  Content
------  -------
  0     [2 B]  magic (0x4654 = "FT" — Forth Threaded)
  2     [2 B]  version (0x0001)
  4     [2 B]  entry count (number of exported entry points)
  6     [2 B]  image size (bytes, excluding this 8-byte header)
  8     [N B]  entry table: [name-len][name-chars...][2 B offset] × count
  8+E   [M B]  ITC body: sequence of cell-sized XTs (indices into
               the sandbox whitelist table, not host addresses)
```

XTs in the image are **whitelist indices** (0..N), not raw host
addresses.  On load, the sandbox maps each index to the
corresponding sandbox-local XT — a fast table lookup, no relocation
patching needed.  Literal values and branch offsets are stored inline
as cells between the XT indices, tagged with a `LIT` pseudo-opcode
(index 0) or `BRANCH`/`0BRANCH` opcodes.

This keeps the image position-independent, deterministic across
validators, and compact (a whitelist of ~60 words needs only 6 bits
per opcode, but cell-aligned storage simplifies the inner
interpreter).

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
| `VM-DEPLOY` | `( src len ctx -- addr )` | Compile source → ITC image, store in state tree, return address |
| `VM-CALL` | `( entry-xt ctx -- )` | Execute contract entry point in sandbox |
| `VM-DELEGATECALL` | `( addr entry-xt ctx -- )` | Call another contract in caller's state context |
| `VM-GAS` | `( ctx -- remaining )` | Gas remaining after execution |
| `VM-RESULT` | `( ctx -- addr len )` | Return data buffer |
| `VM-FAILED?` | `( ctx -- flag )` | TRUE if execution aborted (out-of-gas, fault) |
| `VM-TRACE` | `( ctx trace -- rows )` | Export execution trace for STARK proof |
| `VM-DESTROY` | `( ctx -- )` | Free all sandbox resources |

### Pre-requisite: TX-MAX-DATA Bump

`TX-MAX-DATA` is currently 256 bytes — a testing placeholder.  Real
contracts need room for source text (deploy) and CBOR-encoded call
arguments.  **Phase 7 Step 0** bumps the size limits:

| Constant | Current | Phase 7 | Rationale |
|---|---|---|---|
| `TX-MAX-DATA` | 256 B | **8,192 B** (8 KB) | ITC is cell-sized (8 B/XT), not as dense as bytecode — source needs room |
| `TX-BUF-SIZE` | 8,296 B | **16,232 B** | +7,936 B from data field growth |
| `_ST-MAX-PAGES` | 16 (emulator) | **256+** | Production page count — scales account capacity (256 accts/page). Not a protocol change, just an XMEM sizing knob. |
| `_PST-LOG-MAX` | 1 MB | **4 MB** | Larger txs → larger blocks → more log space |

This is a **layout-breaking change** to tx.f — all offsets after byte
114 shift, and every module that allocates `TX-BUF-SIZE` buffers
(mempool, gossip, rpc, node) must be retested.  We do this as Phase
7's first step so the entire pipeline is retested once before the VM
is built on top.

### Transaction Integration

The `TX-SET-DATA` field (up to 8,192 bytes after the Phase 7 bump)
carries:
- **Deploy transactions:** contract source (Forth text), compiled
  at block-processing time into an ITC image stored in the state
  tree.  Source is not stored on-chain — only the compiled image.
- **Call transactions:** target contract address + entry word name +
  arguments (CBOR-encoded)

The block producer, when applying transactions in `BLK-FINALIZE`:
1. Detects data-bearing txs (non-zero `TX-DATA-LEN`)
2. Decodes the payload (deploy vs. call)
3. **Deploy:** invokes `VM-DEPLOY` — compiles source in sandbox,
   stores resulting ITC image in state tree at the contract address
4. **Call:** loads the ITC image from state tree, invokes `VM-CALL`
   — direct execution, no parsing
5. Collects the execution trace via `VM-TRACE`
6. Merges the VM trace with the value-transfer trace
7. Feeds the combined trace to `CON-STARK-PROVE`

### Gas Model

Simple per-word decrement — no variable-cost opcode table.

**Deploy transactions** pay gas for compilation *and* storage.
**Call transactions** pay gas only for execution — no parsing overhead.

| Operation | Gas cost | Rationale |
|-----------|---------|----------|
| Any stack/arithmetic/logic word | 1 | One inner-interpreter cycle |
| `@` / `!` (arena memory) | 2 | Memory access |
| `VM-ST-GET` / `VM-ST-PUT` | 10 | State tree lookup (Merkle path) |
| `VM-SHA3` | 50 | Hash computation |
| `VM-VERIFY-ED25519` | 500 | Signature verification |
| `VM-MERKLE-ROOT` | 100 | Tree recomputation |
| Loop iteration (`LOOP` / `+LOOP`) | 1 | Prevents infinite loops |
| **Deploy: compilation** | 2 per source word | Parsing + compile to ITC |
| **Deploy: storage** | 1 per byte stored | ITC image persisted to state tree |

Default gas limit per transaction: 10,000.  Configurable via
`VM-GAS-LIMIT` variable.

### Memory Budget

| Item | Size | Notes |
|------|-----:|-------|
| Sandbox arena (default) | 4 KB | Per-contract isolated data space |
| Sandbox dictionary / ITC | 4 KB | Loaded ITC image (deploy: scratch compile area) |
| Return buffer | 256 B | Output data from contract |
| Gas counter | 1 cell | 64-bit decrement counter |
| Trace buffer | ~8 KB | 256 trace rows × 32 bytes |
| Whitelist XT table | ~512 B | ~64 entries × 8 bytes (index→XT mapping) |
| **Per-invocation total** | ~16.8 KB | Freed on `VM-DESTROY` |

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

The source parser runs **only during deploy** — not on every call.
This confines the entire S12 attack surface to deploy transactions.

The sandbox compiler imposes limits on contract source:
- Maximum token length: 64 characters (longer → parse fault)
- Maximum nesting depth (control structures): 16 levels
- Maximum source size: bounded by `TX-MAX-DATA` (8,192 B after
  Phase 7 bump — always finite)
- Unterminated `S"` or `."` → parse fault at end of source
- No `\` (backslash comments) or `(` (paren comments) that could
  mask malicious code in unexpected ways — comments are stripped
  before sandbox compilation
- Deploy gas covers compilation cost — a complex source that takes
  too many steps to compile exhausts gas and aborts

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
| Parser attacks | Deploy-only parsing + length/depth limits | Negligible |

**Design principle:** the sandbox is a *whitelist interpreter*, not
a blacklist filter.  It does not try to "remove dangerous words from
Forth" — it builds a **new, minimal interpreter** that only knows
safe words.  The host interpreter is never invoked by contract code.
This is the only tenable approach on a flat-address-space machine
with no hardware memory protection.

### Cross-Contract Call Performance

Per-invocation arena setup is the most expensive recurring cost in
a multi-contract system.  A naive implementation pays the full price
on every cross-contract call: allocate arena, zero it, load contract
code from the state tree, rebuild dictionary headers, set bounds
registers, execute, tear down.  In a chatty call chain (e.g.,
DEX → Token → Lending), this multiplies quickly.

For comparison: an EVM `CALL` pushes a call frame and adjusts a
memory pointer.  The callee's code is already cached.  Base cost is
~2,600 gas — microseconds on modern hardware.  A naive Leviathan
cross-contract call could be 10–100× heavier due to code reload
and arena zeroing.

Three optimizations reduce per-call overhead to the same order of
magnitude as an EVM `CALL`:

#### 7.A — Contract Code Cache

The contract's compiled ITC image (or .m64 binary for Tier 1) is
**read-only** — it never changes between calls within the same
block.  There is no reason to reload it from the Merkle-backed
state tree on every invocation.

| Item | Description |
|------|-------------|
| Structure | LRU cache of recently-loaded contract images in XMEM |
| Key | Contract address (32 bytes) |
| Value | Pointer to loaded ITC/STC image + whitelist XT table |
| Capacity | 8–16 contracts (configurable via `VM-CODE-CACHE-MAX`) |
| Lifetime | Per-block — flushed at block boundary (state tree may have changed) |
| Sharing | Safe — code segment is read-only, shared across invocations |
| Eviction | LRU.  On miss: load from state tree, insert, evict oldest |

The code cache means the second and subsequent calls to the same
contract within a block skip the state tree lookup, CBOR decode,
and dictionary rebuild entirely.  Only the data arena needs to be
fresh.

Additionally, because the manifest declares which contracts a given
contract *can* call (static call graph), the node can **pre-warm**
the cache when a contract is first invoked.  If DEX's manifest
lists Token as a dependency, Token's image is loaded into the cache
before DEX's first `VM-DELEGATECALL`.  EVM cannot do this — call
targets are runtime-computed addresses.

#### 7.B — Arena Pool

Instead of allocating and freeing an XMEM region per invocation,
pre-allocate a pool of arena slots at block start and reuse them
round-robin.

| Item | Description |
|------|-------------|
| Pool size | `VM-MAX-DEPTH` arenas (default 4 — matches max call depth) |
| Slot size | `VM-ARENA-SIZE` (default 4 KB data + 2 KB dictionary, per Memory Budget) |
| Allocation | At `BLK-FINALIZE` start: `VM-MAX-DEPTH` × slot size from XMEM, once |
| Per-call cost | Assign next slot, reset watermark (see 7.C), swap bounds registers |
| Teardown | Reset slot index.  No `XMEM-FREE` per call |
| Block-level cleanup | Free entire pool at block end |

This turns arena "allocation" into a pointer bump — O(1), a handful
of cycles.  The pool also improves cache locality: the arenas are
contiguous in XMEM, so the CPU (or emulator) doesn't chase scattered
allocations.

#### 7.C — Lazy Arena Zeroing

Zeroing a 4 KB arena (512 stores) on every cross-contract call is
wasteful when most contracts touch only a fraction of their arena.
Instead, track a **high-water mark** per arena slot:

```forth
VARIABLE _VM-ARENA-HWM   \ highest address written in this invocation

: VM-@  ( addr -- val )
    DUP _vm-bounds-check            \ existing bounds check
    DUP _VM-ARENA-HWM @ >= IF       \ above watermark?
        DROP 0 EXIT                  \ never written → return 0
    THEN
    @ ;

: VM-!  ( val addr -- )
    DUP _vm-bounds-check            \ existing bounds check
    DUP _VM-ARENA-HWM @ >= IF
        DUP CELL+ _VM-ARENA-HWM !   \ advance watermark
    THEN
    ! ;
```

On invocation start, `_VM-ARENA-HWM` is set to the arena base.
Reads above the watermark return zero (as if the memory were
zeroed).  Writes advance the watermark.  The actual memory below
the watermark from a previous invocation is overwritten naturally
by the new contract's stores.

| Scenario | Naive zero cost | Lazy zero cost |
|----------|----------------|----------------|
| Contract touches 64 bytes | 512 stores (4 KB) | 0 stores |
| Contract touches 2 KB | 512 stores (4 KB) | 0 stores |
| Contract touches full 4 KB | 512 stores (4 KB) | 0 stores |

The security guarantee is identical: no contract ever reads another
contract's residual data.  The cost shifts from a flat memset to
one additional comparison per `VM-@`, which is already doing a
bounds check anyway — the watermark check can be folded into the
same branch.

> **Note on M1 interaction:** The lazy zeroing watermark check
> folds into the existing bounds check (M1).  The new `VM-@`
> effectively checks `arena_base <= addr < min(arena_end, hwm)` for
> real reads and returns 0 for `hwm <= addr < arena_end`.  One
> branch, not two, when implemented as a single comparison against
> the watermark (which is always ≤ arena_end).

#### Combined Effect

With all three optimizations, a cross-contract call (e.g., DEX
calling Token for the second time in the same block) costs:

| Step | Naive | Optimized |
|------|-------|-----------|
| Arena allocation | XMEM alloc (~50 cycles) | Bump pool index (~5 cycles) |
| Arena zeroing | 512 stores (~4K cycles) | Reset watermark (~2 cycles) |
| Code loading | State tree lookup + CBOR decode (~100K+ cycles) | Cache hit: pointer lookup (~10 cycles) |
| Bounds register setup | 2 stores | 2 stores |
| Per-access overhead | 1 bounds check | 1 bounds check (watermark folded in) |
| Teardown | XMEM free (~20 cycles) | Reset pool slot (~2 cycles) |
| **Total setup** | **~105K cycles** | **~20 cycles** |

The 5,000× reduction means cross-contract calls stop being an
architectural bottleneck and become comparable to EVM `CALL` overhead
relative to actual contract execution cost.

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
- **ITC image correctness:** deploy contract, dump stored ITC,
  verify it matches expected threaded code sequence
- **ITC reload:** deploy → call once → restart sandbox → reload ITC
  from state tree → call again → same result (deterministic)
- **Parser hardening (S12):** submit source with 65-char token,
  unterminated string, 17-deep nesting → parse faults (deploy only)
- **Code cache hit:** deploy Token, call Token 4× in one block →
  state tree lookup count = 1 (first call), cache hits = 3
- **Code cache eviction:** deploy 20 contracts, call in round-robin
  → LRU evictions occur, correctness preserved
- **Code cache flush:** call Token in block N, mutate Token's code
  in block N+1 → block N+1 loads fresh image (cache flushed at
  block boundary)
- **Arena pool reuse:** A calls B calls C (depth 3) → 3 pool slots
  assigned, no XMEM alloc/free during call chain
- **Lazy zero correctness:** contract reads address it never wrote →
  returns 0.  Contract reads address after writing → returns written
  value.  Second invocation in same pool slot reads address previous
  contract wrote but new contract didn't → returns 0
- **Manifest pre-warm:** DEX manifest lists Token → Token image
  loaded into cache before DEX's first `VM-DELEGATECALL` to Token

---

## Phase 7.5 — Cross-Chain Verification

**Location:** `akashic/net/xchain.f` + standard contract patterns
**Prefix:** `XCH-`
**Depends on:** Phase 7 (contract VM), Phase 6.5b (light client), stark.f, merkle.f
**Estimated size:** ~150–250 lines (relay + verifier contract pattern)
**Difficulty:** Medium
**Status:** Not started

Every Leviathan chain already has a STARK verifier and a Merkle
verifier in its dictionary.  Phase 7.5 composes them into a
cross-chain verification path: chain A can verify chain B's state
transitions without trusting chain B's validators, without an
intermediary hub, and without a bridge contract with a challenge
window.

This is peer verification, not hierarchical settlement.  Neither
chain is "above" the other.  Neither chain's security depends on
the other's liveness.

### Why This Is Cheap

On EVM chains, cross-L2 proof verification is prohibitively
expensive: STARK verification costs millions of gas, contracts are
capped at 24 KB, and there are no precompiles for FRI-based math.
So cross-chain interaction routes through L1 as a hub.

On Leviathan, the STARK verifier is a dictionary word that runs at
native speed with deterministic cycle cost.  Every chain has it.
If two chains use the same field (Baby Bear), same hash (SHA3), and
same proof format, any chain can verify any other chain's proof as
a normal computation.

### Components

**1. Proof relay (xchain.f, ~80–120 lines)**

A relay mechanism for delivering chain B's block proofs to chain A.
Two options, implement whichever lands first:

- **Manual submission:** A transaction on chain A includes chain B's
  block proof + Merkle inclusion proof as payload.  The contract
  parses and verifies.  No new networking — someone submits the
  bytes.

- **Relay node:** A node that sits on both chains, listens for
  finalized blocks on chain B, and submits proofs to chain A as
  transactions.  Reuses existing gossip infrastructure with a
  second peer table pointed at chain B's network.

**2. Verifier contract pattern (~40–60 lines of Forth)**

A standard contract (or approved word set) on chain A that:

- Accepts a blob: chain B's STARK proof + a Merkle inclusion proof
  for a specific account or state entry
- Calls `STARK-VERIFY` on the block proof
- Calls the Merkle verifier on the inclusion proof against the
  state root committed in the proven block
- Emits the verified result (account state, balance, nonce, etc.)

This is composition of existing words, not new cryptography.  The
verifier word and Merkle verifier are already in the dictionary.

**3. AIR compatibility registry (~30 lines)**

A configuration word or on-chain record that identifies which AIR
version a foreign proof targets.  For chains running the same
Leviathan software version, the AIR is identical and this is a
no-op check.  For chains with different contract vocabularies, the
registry records the mapping so the verifier knows what the proof
means.

### What This Enables

- **Peer-to-peer chain composition:** Chain A verifies chain B's
  state.  Chain B verifies chain A's state.  Symmetric.  No hub.
- **Multi-chain mesh:** Chain C verifies both A and B.  The
  topology is a mesh, not a tree.
- **No stacked trust assumptions:** Each chain's proof proves its
  own correctness against its own AIR.  Verifying a foreign proof
  does not require trusting the foreign chain's validators.
- **No compounding finality latency:** Verification is a
  computation in the verifying chain's normal block execution.
  Chain A's finality is chain A's business.
- **No bridge in the EVM sense:** No "lock assets and wait for a
  challenge window."  Verify the proof, verify the Merkle path,
  act on the result.

### Comparison to Existing Cross-Chain Models

| Model | Trust basis | Latency | Hub required |
|-------|-----------|---------|-------------|
| EVM L2 → L1 → L2 | L1 as judge | 7+ days (optimistic) | Yes (L1) |
| Cosmos IBC | Validator sigs (light client) | Minutes | No |
| Leviathan cross-chain | STARK proof (math) | One block on verifying chain | No |

IBC is the closest analog — peer-to-peer light client verification
without a hub.  The difference: IBC verifies *consensus signatures*
("the validators signed it").  Leviathan cross-chain verifies
*execution proofs* ("this computation happened correctly").

### Caveats

- Cross-chain asset transfers (lock/mint/burn) require additional
  contract logic beyond proof verification.  Phase 7.5 provides the
  verification primitive; asset bridging is application-level.
- "Same field, same hash, same proof format" is an assumption.  If
  two chains diverge on proof parameters, the verifier word still
  runs but the caller must know which AIR the proof targets.
- StarkNet's Cairo can also verify STARK proofs natively.  This
  capability is not unique in principle.  What's different is that
  the verifier is a first-class dictionary word, not a contract
  someone has to write, deploy, and pay gas for.

### Testing

- **Proof roundtrip:** Generate a block on chain B, extract STARK
  proof + Merkle inclusion proof, submit to chain A's verifier
  contract → verified TRUE
- **Tampered proof:** Flip one bit in chain B's STARK proof →
  verifier returns FALSE
- **Tampered Merkle path:** Valid STARK proof but bogus inclusion
  proof → verifier returns FALSE
- **Wrong AIR version:** Proof from a chain with different contract
  vocabulary → AIR registry check fails
- **Relay latency:** Measure end-to-end time from chain B block
  finalization to verified state on chain A
- **Symmetric verification:** Chain A verifies B *and* B verifies
  A in the same test run

---

## Phase 8 — ethereum/: Standard Blockchain Interop

**Location:** `akashic/ethereum/`  (separate from `store/`)
**Depends on:** Phases 1–7.5 complete (functional custom chain with smart contracts + cross-chain)
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

## Fork in the Road Options

These are not phases on the critical path.  They are **independent
enhancement tracks** that become relevant under specific deployment
scenarios.  Each can be adopted when the need arises without
blocking the core roadmap (Phases 7 → 7.5 → 8).

### Option A — STARK LDE + ZK Hardening (`stark.f` v3)

**Trigger:** Opening block production to anonymous permissionless
validators (pure PoS without an authority gate), or requiring
transaction privacy (ZK masking hides execution traces).

**What it adds:**
- **Low-Degree Extension (4×/8× blowup):** Evaluation domain
  grows from 256 to 1024+ points.  Provides proper Reed-Solomon
  proximity testing with 128-bit cryptographic soundness.  Without
  this, FRI soundness is weaker — acceptable when validators are
  identified and staked (PoSA), but insufficient when an anonymous
  adversary has unlimited proof-forgery attempts.
- **ZK masking:** Adds a random polynomial so the execution trace
  is not recoverable from the proof.  Required for private
  computation, ML inference proofs, or any scenario where
  transaction details should not be visible to proof observers.

**Why it's not needed now:** On a PoSA consortium chain, a forged
STARK proof also requires a valid PoSA signature from a staked
authority — double barrier.  Current v2.5 soundness is more than
adequate.  The federation model (hundreds of consortium chains)
scales to hundreds of millions of users without touching this.

**Estimated cost:** ~700 lines, ~50 tests.  Main engineering
challenge: multi-pass NTT (4 × 256-point hardware NTT to cover
1024-point evaluation domain).  Full spec in
[STARK-design.md](STARK-design.md) Phase 5.

### Option B — Permissionless PoS (Remove Authority Gate)

**Trigger:** Transitioning from consortium to fully public chain
where anyone can stake and produce blocks.

**What it adds:** Remove the `authorities` list requirement from
PoSA.  Any account meeting `min_stake` can validate.  Requires
Option A (STARK hardening) because the proof becomes the
primary defense against malicious block producers.

**Depends on:** Option A.

### Option C — Transaction Privacy

**Trigger:** Use cases requiring hidden balances, amounts, or
contract state (e.g., private DeFi, confidential supply chain).

**What it adds:** ZK masking from Option A, plus potentially
encrypted transaction payloads and commitment schemes.

**Depends on:** Option A (ZK masking component).

---

## Dependency Graph

> ⚠ **REVISED — includes Phases 3b, 5b, 6.5a, 6.5b, 7.5**

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
              │             │
              │        ┌────▼──────────┐
              │        │  smt.f +      │ ◄── Phase 3b (NEW)
              │        │  state.f      │     Sparse Merkle Tree
              │        │  (reworked,   │     + paged state
              │        │   >256 accts) │     + decoupled STARK
              │        └────┬──────────┘
              │             │
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
                     │
               ┌─────▼────────┐
               │ consensus.f  │ ◄── Phase 5b (NEW)
               │  (hardened)  │     Genesis config,
               │ (hardened)   │     anti-grinding,
               └─────┬────────┘     CON-SEAL fix
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
                     │
          ┌──────────┼──────────┐
          ▼                     ▼
    ┌─────────────┐      ┌────────────┐
    │  persist.f  │      │  light.f   │ ◄── Phase 6.5 ✅
    │ (rewritten, │      │  (light    │     Real persistence
    │  KDOS I/O)  │      │   client   │     + Light client
    │  (6.5a) ✅  │      │   proto)   │
    │  sector I/O │      │  (6.5b) ✅ │
    └──────┬──────┘      └─────┬──────┘
           └────────┬──────────┘
                    ▼
              ┌────────────────┐
              │  code harden   │ ◄── Phase 6.6 🟡 NEXT
              │  (12 files,    │     11 critical + 11 high
              │   37 issues)   │     fixes across all modules
              └──────┬─────────┘
                     ▼
              ┌────────────┐
              │ contract-  │ ◄── Phase 7 (blocked on 6.6)
              │    vm      │
              │ (sandboxed │
              │  Forth)    │
              └─────┬──────┘
                    │
              ┌─────▼────────┐
              │  xchain.f   │ ◄── Phase 7.5
              │ (cross-chain │     Federation mesh
              │  STARK verify│
              └─────┬────────┘
                    │
              ┌─────▼────────┐
              │  ethereum/   │ ◄── Phase 8
              │  (interop)   │
              └──────────────┘

                              ╔═══════════════════════╗
                              ║  Fork Options         ║
                              ║  (independent tracks) ║
                              ╠═══════════════════════╣
                              ║  A: STARK LDE+ZK v3   ║
                              ║  B: Permissionless PoS ║
                              ║  C: Tx Privacy         ║
                              ╚═══════════════════════╝
```

  Existing modules used throughout:
    sha3  merkle  cbor  dag-cbor  sort  datetime  json
    server  router  ws  (for node RPC / gossip)

  Quantum-safe path:  sha3 → sphincs-plus → tx (PQ mode) → block
  Classical path:     sha512 → ed25519 → tx (classical mode) → block

---

## Implementation Order

> ⚠ **REVISED — Production-First Ordering**
>
> The original plan treated Phase 7 (Forth VM) and Phase 8 (Ethereum
> interop) as the finish line.  The revised plan inserted foundation
> phases — **3b, 5b, 6.5** — that must land before any smart-contract
> or interop work begins.  **All foundation phases are now complete.**
> Phase 7 (Forth VM) can proceed.

| Order | Module | Depends on (new) | Lines | Tests | Status |
|------:|--------|------------------|------:|------:|--------|
| 1 | ed25519.f | — | 381 | 11 | ✅ done |
| 1b | sphincs-plus.f | sha3 | 788 | 15 | ✅ done |
| 2 | tx.f | ed25519, sphincs-plus | 640 | 19 | ✅ done |
| 3 | state.f | — | 640 | 14+21 | ✅ done (rewritten in 3b) |
| **3b** | **smt.f + state.f rework + witness.f** | **state.f, merkle.f, sha3** | **1824** | **25+14+21+22** | **✅ done** |
| 4 | block.f | tx, state | 779 | 19 | ✅ done |
| 5 | consensus.f | block, state, stark, random | 677 | 19 | ✅ done |
| **5b** | **consensus.f harden + genesis.f + PoSA** | **consensus.f, block.f, state.f, cbor.f** | **469** | **13+31** | **✅ done** |
| 6a | mempool.f | tx, sort | 369 | 16 | ✅ done |
| 6b | gossip.f | ws, cbor, tx, block | 360 | 15 | ✅ done |
| 6c | rpc.f | server, router, json, mempool, state, block | 490 | 10 | ✅ done |
| 6d | sync.f | gossip, block, state, consensus | 190 | 10 | ✅ done |
| 6e | persist.f (original) | state, block, cbor | — | — | ~~superseded by 6.5a~~ |
| 6f | node.f | all Phase 6 modules + consensus | 190 | 7 | ✅ done |
| **6.5a** | **persist.f rewrite** | **state.f, block, KDOS I/O** | **284** | **9** | **✅ done** |
| **6.5b** | **light.f** | **rpc.f, state.f, block.f, merkle.f** | **159** | **12** | **✅ done** |
| **6.6** | **Code hardening (12 files)** | **all Phase 1–6.5b modules** | **~delta** | **+30–50** | **🟡 next** |
| 7 | contract-vm.f | state, consensus, tx, stark-air, node, persist | ~400–600 | ~25 | 🔴 blocked on 6.6 |
| **7.5** | **xchain.f** | **contract-vm, light.f, stark.f, merkle.f** | **~150–250** | **~15** | 🔴 future |
| | **Subtotal (custom chain, actual)** | | **~8,000+** | **~280+** | |
| 8 | ethereum/ (secp256k1, keccak, rlp, eth-tx, eth-abi, eth-rpc, eth-wallet) | Phases 1–7.5 complete | ~2,000–3,000 | ~100+ | 🔴 future |
| | **Grand total** | | **~10,000+** | **~380+** | |

### Revised Critical Path

```
Ed25519 ──┐
           ├── tx.f ──┐
SPHINCS+ ──┘          │
                      ├── block.f ──── consensus.f ──── consensus harden (5b)
state.f ── smt.f (3b) ┘                                       │
                                                               ▼
mempool ─── gossip ─── rpc ─── sync ─── persist ─── node ─── 6.5a (fileio+persist)
                                 │                                    │
                                 └──────── 6.5b (light client) ──────┘
                                                                      │
                                                                      ▼
                                                        6.6 (code hardening)
                                                                      │
                                                                      ▼
                                                              7 (Forth VM)
                                                                      │
                                                                      ▼
                                                           7.5 (Cross-chain)
                                                                      │
                                                                      ▼
                                                              8 (Ethereum)
```

### What Changed

- **Phase 3b (Scalable State)** ✅ **Done.** Removed the 256-account
  ceiling.  Paged state + SMT decouple account count from proof
  geometry.  smt.f (717 lines), state.f rewrite (640 lines),
  witness.f (467 lines).
- **Phase 5b (Consensus Hardening + PoSA)** ✅ **Done.** Genesis config,
  anti-grinding (2-block lookback), CON-SET-KEYS signing context, PoW
  testing-only flag, PoSA Mode 3.  consensus.f 939 lines, genesis.f
  207 lines.  13+31 tests.  Commit 63bc062.

- **Phase 6.5a (Real Persistence)** ✅ **Done.** `persist.f` rewritten
  with sector-based KDOS file I/O. 284 lines, 9 tests.
- **Phase 6.5b (Light Client)** ✅ **Done.** `light.f` + `rpc.f`
  extensions.  Cross-chain verification (Phase 7.5) can proceed
  as soon as Phase 7 is complete.
- **Phase 7.5 (Cross-Chain Verification)** composes the STARK
  verifier and Merkle verifier into a peer-to-peer proof
  verification path between Leviathan chains.  ~150–250 lines
  of relay plumbing + standard verifier contract pattern.
  Must land before Phase 8 because Ethereum interop is a
  special case of cross-chain, not the other way around.

Ed25519 first because it unblocks the classical signing path.
SPHINCS+ can proceed in parallel (independent dependency: sha3 only).
tx.f waits for both signature modules.  state.f can proceed in
parallel with everything after Phase 1.  block.f integrates tx +
state.  consensus.f sits on top.  mempool.f is independent after tx.f.

**Phases 1–5 = chain data structures.  Phase 3b ✅ + 5b ✅ = hardening
the foundation.  Phase 6 = running node.  Phase 6.5a ✅ + 6.5b ✅ =
production infrastructure (real I/O + light client).  Phase 6.6 = code
hardening (11 critical + 11 high issues across 12 files).  Phase 7 = smart
contracts via sandboxed Forth VM.  Phase 7.5 = cross-chain federation.
Phase 8 = Ethereum/standard blockchain interop.**

**Phase 6.6 (code hardening) is next.**  Phase 7 is blocked until all
critical and high issues are resolved.

### Federation Scaling Model

The architecture wis designed to be production-ready for **PoSA consortium chains**
and naturally extends to a **federated mesh** via Phase 7.5
cross-chain verification:

| Scope | Capacity | How |
|-------|----------|-----|
| Single chain (accounts) | ~1M (`_ST-MAX-PAGES` × 256 accts/page) | Bump `_ST-MAX-PAGES` — an XMEM sizing knob, not a protocol change |
| Single chain (throughput) | 256 TPS @ 1 s blocks | PoSA near-instant finality; sub-second blocks possible |
| Single chain (validators) | Dozens (authorized + staked) | Practical PoSA consortium |
| 100-chain federation | ~100M accounts, ~25K TPS aggregate | Peer STARK verification (Phase 7.5) — no hub, no L1 |
| 1,000-chain federation | ~1B accounts, ~256K TPS aggregate | Same mechanism, linear scaling |

Each chain is a self-contained PoSA consortium with its own
validator set, genesis config, and state tree.  Cross-chain
state verification uses STARK proofs (math-based, not
trust-based) — chain A verifies chain B's state transitions
without trusting chain B's validators.

This means dozens to hundreds of organizations and hundreds of
millions of users are reachable **without any changes to the
current proof system.**  STARK Phase 5 (LDE + ZK hardening)
becomes relevant only if a single chain opens block production to
anonymous permissionless validators, or if transaction privacy is
required.  See [Fork in the Road Options](#fork-in-the-road-options).



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
| Account table | ~18 KB | 256 × 72 bytes (includes reserved staking fields) |
| State Merkle tree | ~16 KB | 256-leaf SHA3-256 tree |
| Block buffer (Ed25519) | ~105 KB | Header + 256 txs |
| Block buffer (hybrid) | ~2.1 MB | Header + 256 txs (PQ sigs) |
| STARK proof data | ~12 KB | Already allocated in stark.f |
| **Total new (classical)** | **~248 KB** | Same as before |
| **Total new (hybrid)** | **~4.3 MB** | Well within 16 MiB test env; production XMEM can be much larger |

> ⚠ **REVISED — Phase 3b Memory Impact (Actual)**
>
> The table above reflects the original 256-account flat-table design.
> After Phase 3b (Sparse Merkle Tree + paged state) and Phase 6.5a
> (real persistence), the memory budget changes significantly.
> `_ST-MAX-PAGES` controls resident page count (16 for emulator
> testing — production cranks this up based on available SDRAM):
>
> | Item (Phase 3b + 6.5a) | Size | Notes |
> |------------------------|-----:|-------|
> | SMT hot cache (pages × entries) | ~400 KB | Depends on `_ST-MAX-PAGES`; 16 pages emulator default |
> | SMT node pages (warm) | ~128 KB | Internal tree nodes, paged in/out |
> | Page table metadata | ~16 KB | Page directory for disk-backed pages |
> | WAL write buffer (6.5a) | ~64 KB | Ring buffer for write-ahead log |
> | **Phase 3b+6.5a delta** | **~608 KB** | On top of existing budget |
>
> This brings total classical to ~856 KB, total hybrid to ~4.9 MB.
> Still well within 16 MiB test environment.  The paging system
> spills cold accounts to disk via KDOS file I/O (persist.f) when
> the hot set exceeds the budget.  Production XMEM pool can be
> much larger — 16 MiB is just the emulator testing value.

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

> ⚠ **REVISED — Additional Gotchas from Production Analysis**
>
> - **File I/O latency:** KDOS file I/O is synchronous. The WAL
>   (Phase 6.5a) must batch writes to avoid blocking block production.
>   Consider a "flush every N blocks" strategy rather than per-block.
> - **No MMU / no process isolation:** The Forth VM (Phase 7) runs
>   in the same address space as the node.  A malicious contract can
>   overwrite node state.  Phase 7 *must* include bounds-checked
>   memory access words (`VM-LOAD`, `VM-STORE`) that confine the
>   contract to its own XMEM region.
> - **Serialized consensus (not single-threaded):** KDOS provides
>   up to 16 cores, 8 tasks/core, BIOS coroutines, `PAR-MAP`,
>   channels, and structured concurrency.  The blockchain modules
>   serialize through `WITH-GUARD` to preserve STARK determinism,
>   but this is a *choice*, not a platform limit.  Concrete
>   parallelism opportunities:
>   - RPC serving on a BIOS background coroutine (`BG-POLL`)
>   - Parallel tx signature verification via `PAR-MAP` across
>     cores (requires per-core crypto scratch — ~32 KB each)
>   - STARK proof generation on a background core while block
>     N+1 is produced on the foreground
>   - Gossip polling on a separate task via `WITH-BACKGROUND`
>   These require per-core scratch buffers for crypto modules
>   (tracked in the concurrency hardening roadmap) but no
>   architectural changes.
> - **Chain ID:** There is no chain ID anywhere in the protocol.
>   tx.f should include a chain-id field in the signing payload to
>   prevent cross-chain replay attacks.  Add in Phase 3b alongside
>   the state model rework.

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
| JIT compilation | bios.asm (3-tier: inline, literal fold, bigram fusion) |
| Binary image save/load + relocation | binimg.f (.m64 format — import manifest = capability gate for sandbox) |
| Parallel combinators | par.f (PAR-MAP, PAR-DO, PAR-REDUCE) |
| Structured concurrency | scope.f (TASK-GROUP, TG-SPAWN, TG-WAIT) |
| Multi-core dispatch | KDOS §8 (CORE-RUN, BARRIER, work stealing, IPI) |

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
