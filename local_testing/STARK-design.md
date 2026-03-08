# STARK Production Roadmap

Status: **Phase 0 written, untested** — MVP stark.f code exists,
needs test suite and debug pass

The MVP stark.f demonstrates end-to-end STARK functionality:
Baby Bear field arithmetic, coset evaluation via twisted NTT,
Fiat-Shamir transcript, constraint quotients, FRI folding, prove
and verify.  But it cuts corners that prevent production use:
full polynomials shipped in the proof (~3.4 KB), exhaustive
verification instead of spot-checks, hardcoded Fibonacci AIR,
no zero-knowledge.

This roadmap closes those gaps.  Each phase produces a reusable
library that serves purposes beyond STARKs.

---

## Table of Contents

- [Current State](#current-state)
- [Gap Analysis](#gap-analysis)
- [Phase 1 — merkle.f: Binary Merkle Tree](#phase-1--merklef-binary-merkle-tree)
- [Phase 2 — batch.f: Batch Field Inversion](#phase-2--batchf-batch-field-inversion)
- [Phase 3 — stark.f v2: Succinct Proofs](#phase-3--starkf-v2-succinct-proofs)
- [Phase 4 — air.f: General Constraint Compiler](#phase-4--airf-general-constraint-compiler)
- [Phase 4.5 — stark.f v2.5: Multi-Column Traces](#phase-45--starkf-v25-multi-column-traces-new)
- [Phase 5 — stark.f v3: LDE + ZK + Hardening](#phase-5--starkf-v3-lde--zk--hardening)
- [Dependency Graph](#dependency-graph)
- [Design Constraints](#design-constraints)

---

## Current State

### Phase 0 — MVP stark.f (written, untested)

| Item | Status | Detail |
|------|--------|--------|
| Baby Bear arithmetic | coded | `_BB+` `_BB-` `_BB*` `_BB-INV` `_BB-POW` in 64-bit Forth cells |
| Domain parameters | coded | ω extracted from NTT device, coset k=3, all precomputed |
| Trace buffer | coded | 256-entry single column via NTT-POLY, STARK-TRACE!/@ |
| Coset evaluation | coded | Twist by k^i → forward NTT, inverse untwist |
| Fiat-Shamir transcript | coded | Running SHA3-256 hash, ABSORB32 + CHALLENGE |
| Constraint quotient | coded | Fibonacci transition + boundary, combined on coset |
| FRI folding | coded | 8 rounds coefficient-space, 256 → 1 |
| STARK-PROVE | coded | Full pipeline: interpolate → commit → quotient → FRI |
| STARK-VERIFY | coded | Exhaustive: re-hash, re-check every row, re-fold every round |

**Expected behavior (needs testing):**
- Honest Fibonacci trace: prove then verify → TRUE
- Tampered coefficients after proving → verify catches → FALSE
- Wrong boundary values → verify catches → FALSE
- FRI consistency verified round-by-round

**What's missing (and why it matters):**

| Gap | Impact |
|-----|--------|
| Commitment = SHA3-256 of full buffer | Proof contains entire polynomial (~3.4 KB), not O(log n) opening |
| Exhaustive verification | Verifier checks all 256 rows instead of O(log n) spot-checks |
| No Merkle tree | Cannot selectively open individual evaluations |
| No batch inversion | 768 individual Fermat inversions in prover (~35K muls) |
| Hardcoded Fibonacci AIR | Cannot prove other computations |
| No blowup factor | Trace domain = evaluation domain, limited soundness |
| No ZK masking | Trace fully revealed in proof |
| Single-column trace | Real AIR needs multi-column traces — see Phase 4.5 |

---

## Gap Analysis

### Problem 1: Proof too large

The MVP ships full 1024-byte coefficient arrays for the trace,
quotient, and all 8 FRI rounds (~3.4 KB total).  A production
STARK commits to evaluation Merkle trees and opens only the
queried leaves + authentication paths.

**Solution:** merkle.f (Phase 1) + succinct proof (Phase 3).

With 256 leaves and SHA3-256:
- Merkle tree: 255 internal nodes × 32 bytes = 8,160 bytes (build once)
- Opening proof: 1 leaf (4 bytes) + 8 siblings (256 bytes) = 260 bytes
- Per query: ~260 bytes instead of 1024 bytes
- With 30 queries across 10 committed polynomials: ~78 KB worst case,
  but most queries share paths.  Realistic: ~20 KB succinct proof
  vs. ~3.4 KB exhaustive proof.

**Small-trace paradox:** for 256 leaves the succinct proof is
*larger* than just shipping the full polynomial.  Merkle trees
pay off at ≥ 1024 leaves, which requires Phase 5 (LDE blowup).
Building merkle.f now gives us:
- The reusable library for the vault, content-addressed storage, etc.
- The infrastructure ready for when LDE expands the evaluation domain

### Problem 2: Verification is O(n) not O(log n)

The MVP verifier re-evaluates the trace polynomial at all 256 points
and checks every transition constraint.  Production STARKs verify
O(log² n) random positions using Merkle openings.

**Solution:** Phase 3 rewrites the verifier to:
1. Re-derive Fiat-Shamir challenges
2. Pick O(log n) query positions
3. Open polynomials at those positions via Merkle paths
4. Check constraint and FRI consistency at just those points

### Problem 3: Brute-force inversions

The prover loop does 2 Fermat inversions per coset point (768 total,
~35K multiplications).  Montgomery's batch inversion trick does n
inversions in 3(n−1) multiplications + 1 inversion = ~770 muls.

**Solution:** batch.f (Phase 2).  This is a standalone utility
useful anywhere you need multiple modular inversions — Lagrange
interpolation, elliptic curve batch verification, etc.

### Problem 4: Hardcoded constraint

Fibonacci is baked into STARK-PROVE and STARK-VERIFY.  You can't
prove a different computation without rewriting both words.

**Solution:** air.f (Phase 4) — a small constraint description
language that STARK-PROVE and STARK-VERIFY interpret.

### Problem 5: No blowup factor / LDE

The MVP evaluates on a 256-point coset (same size as the trace).
Production STARKs use a low-degree extension (LDE) to a larger
domain (typically 4× or 8× blowup) for Reed-Solomon soundness.

**Solution:** Phase 5, which can use multiple NTT passes to handle
1024+ evaluation points.

---

## Phase 1 — `merkle.f`: Binary Merkle Tree

**File:** `akashic/math/merkle.f`
**Prefix:** `MERKLE-`
**Depends on:** `sha3.f`
**Est.:** ~120 lines

A general-purpose binary Merkle tree over 32-byte leaf hashes.
Used by STARKs, content-addressed storage, authenticated data
structures.

### The Problem

STARKs commit to polynomial evaluations by hashing them into a
Merkle tree, then selectively open individual leaves with O(log n)
authentication paths.  The vault (Phase 3 of crypto-SIMD-hardened.md)
needs the same structure for content-addressed blocks.  Without a
shared library, each consumer re-implements the same tree logic.

### Design

**Tree layout:** flat array, 1-indexed.  For n leaves:
- Nodes 1..n−1 are internal (node 1 = root)
- Nodes n..2n−1 are leaves
- Parent of node i = i/2, children = 2i and 2i+1

**Hash function:** SHA3-256 — 32 bytes in, 32 bytes out.
- Leaf hash: `SHA3-256(0x00 || data)` (domain-separated)
- Internal: `SHA3-256(0x01 || left || right)` — 65 bytes → 32 bytes

### Memory Map

For n = 256 leaves:
```
Total nodes = 511 (255 internal + 256 leaves)
Storage = 511 × 32 = 16,352 bytes per tree
```

For n = 1024 leaves (post-LDE):
```
Total nodes = 2047
Storage = 2047 × 32 = 65,504 bytes → ext_mem
```

### API

| # | Word | Stack | Description |
|---|------|-------|-------------|
| 1a | `MERKLE-TREE` | `( n "name" -- )` | Allocate tree for n leaves |
| 1b | `MERKLE-LEAF!` | `( hash idx tree -- )` | Set leaf hash at index |
| 1c | `MERKLE-BUILD` | `( tree -- )` | Compute all internal nodes bottom-up |
| 1d | `MERKLE-ROOT` | `( tree -- addr )` | Return pointer to 32-byte root hash |
| 1e | `MERKLE-OPEN` | `( idx tree proof -- depth )` | Write authentication path to proof buffer |
| 1f | `MERKLE-VERIFY` | `( leaf-hash idx proof depth root -- flag )` | Verify an opening |
| 1g | `MERKLE-LEAF@` | `( idx tree -- addr )` | Return pointer to leaf hash |

### Forth Sketch

```forth
\ Tree layout: 1-indexed flat array, 2n-1 total nodes
\ Node i at offset (i * 32)
\ Leaves at indices n..2n-1, root at index 1

: MERKLE-TREE  ( n "name" -- )
    CREATE DUP , 2 * 1 - 32 * ALLOT ;

: _MK-N@  ( tree -- n )  @ ;
: _MK-NODE  ( i tree -- addr )  CELL+ SWAP 1 - 32 * + ;

: MERKLE-LEAF!  ( hash idx tree -- )
    >R  R@ _MK-N@ +  R> _MK-NODE  32 CMOVE ;

: MERKLE-BUILD  ( tree -- )
    DUP _MK-N@ 1 - BEGIN DUP 0> WHILE
        \ node[i] = H(0x01 || node[2i] || node[2i+1])
        DUP 2 * OVER _MK-NODE ... hash children ...
    1 - REPEAT DROP ;

: MERKLE-ROOT  ( tree -- addr )  1 SWAP _MK-NODE ;
```

### Proof Buffer Layout

An opening proof for depth d is d × 32 bytes (one sibling per level).
For n=256, depth=8, proof = 256 bytes.

```forth
: MERKLE-OPEN  ( idx tree proof -- depth )
    \ Walk from leaf[n+idx] to root, copying sibling at each level
    ...
```

### Definition of Done

- Build tree from 256 known leaves, root matches hand-computed value
- Open leaf at index i, verify returns TRUE
- Tamper one sibling → verify returns FALSE
- Open every leaf (0..255) → all verify TRUE
- Works with n = 64, 128, 256 (power-of-2 only)
- ~20 tests

---

## Phase 2 — `batch.f`: Batch Field Inversion

**File:** `akashic/math/batch.f`
**Prefix:** `BATCH-`
**Depends on:** (none — uses caller's inversion function)
**Est.:** ~50 lines

Montgomery's trick for computing n modular inversions with a single
exponentiation.  Used by the STARK prover, Lagrange interpolation,
elliptic curve multi-scalar multiplication.

### The Problem

The MVP STARK prover computes 768 individual Fermat inversions
(each ~46 multiplications = ~35,000 total).  Montgomery's batch
trick reduces this to 3(n−1) multiplications + 1 inversion ≈ 2,350
multiplications — a **15× speedup** of the prover's hot loop.

### Algorithm

Given values `a_0, a_1, ..., a_{n-1}`, compute all `a_i^{-1}`:

```
1. Forward sweep: prefix[0] = a_0
                   prefix[i] = prefix[i-1] * a_i
2. One inversion: inv_all = prefix[n-1]^{-1}
3. Backward sweep: for i = n-1 down to 1:
                     result[i] = inv_all * prefix[i-1]
                     inv_all = inv_all * a_i
                   result[0] = inv_all
```

### API

| # | Word | Stack | Description |
|---|------|-------|-------------|
| 2a | `BATCH-INV-BB` | `( src dst n -- )` | Batch-invert n Baby Bear values |

Takes a source array of n 32-bit values (packed 4 bytes each),
writes n 32-bit inverses to dst.  Uses `_BB-INV` for the single
inversion.  Needs 2 scratch buffers of n × 4 bytes.

### Forth Sketch

```forth
\ Assumes: _BB* _BB-INV defined (from stark.f or shared)

CREATE _BI-PFX  1024 ALLOT   \ prefix products, up to 256 values
VARIABLE _BI-INV              \ running inverse

: BATCH-INV-BB  ( src dst n -- )
    >R  SWAP                  ( dst src ) ( R: n )
    \ Forward sweep: build prefix products
    DUP _SK-W32@  _BI-PFX _SK-W32!     \ prefix[0] = src[0]
    R@ 1 DO
        I 1 - 4 * _BI-PFX + _SK-W32@   \ prefix[i-1]
        I 4 * 2 PICK + _SK-W32@         \ src[i]
        _BB*
        I 4 * _BI-PFX + _SK-W32!        \ prefix[i] = prefix[i-1]*src[i]
    LOOP
    \ One inversion
    R@ 1 - 4 * _BI-PFX + _SK-W32@  _BB-INV  _BI-INV !
    \ Backward sweep
    R@ BEGIN 1 - DUP 0> WHILE
        DUP 1 - 4 * _BI-PFX + _SK-W32@  \ prefix[i-1]
        _BI-INV @ _BB*                    \ result[i]
        OVER 4 * 4 PICK + _SK-W32!       \ dst[i] = result[i]
        DUP 4 * 2 PICK + _SK-W32@        \ src[i]
        _BI-INV @ _BB*  _BI-INV !        \ inv_all *= src[i]
    REPEAT
    \ result[0] = inv_all
    _BI-INV @  SWAP 4 * 3 PICK + _SK-W32!
    R> 2DROP DROP ;
```

### Definition of Done

- Invert 256 random Baby Bear values, verify each `a * a^{-1} = 1`
- Invert including value 1 → identity
- Result matches individual `_BB-INV` for each element
- ~8 tests

---

## Phase 3 — `stark.f` v2: Succinct Proofs

**File:** `akashic/math/stark.f` (replace MVP)
**Prefix:** `STARK-`
**Depends on:** `sha3.f`, `ntt.f`, `merkle.f`, `batch.f`
**Est.:** ~500 lines (replaces current ~280)

### The Problem

The MVP proof is ~3.4 KB because it ships full polynomial
coefficients.  The verifier exhaustively checks every row.
This is not a "real" STARK — it's more like a non-interactive
audit.  Production STARKs have O(log² n) verification with
succinct proofs.

### What Changes

| Component | MVP | v2 |
|-----------|-----|-----|
| Commitment | SHA3-256 of full buffer | Merkle tree over evaluations |
| Proof contents | Full polynomial coefficients | Merkle openings at queried positions |
| Verification | Check every row (O(n)) | Spot-check O(log n) positions |
| Inversions | Individual Fermat | Batch Montgomery via batch.f |
| Proof size | ~3,400 bytes (fixed) | ~2,500 bytes (query-dependent) |
| FRI | Coefficient-space + full round polys | Evaluation-space + Merkle openings |

### Prover Changes

```
Step 1–4: Same as MVP (trace → interpolation → commitment → coset evaluation)
          But now "commit" means: build Merkle tree over coset evaluations

Step 5–7: Same quotient computation, but use BATCH-INV-BB for the
          768 inversions (boundary zerofiers + transition denominators)

Step 8:  Commit quotient via Merkle tree (not just SHA3-256 of buffer)

Step 9:  FRI — evaluation-space folding:
         Each round: commit evaluations (not coefficients) via Merkle,
         sample query positions, include openings in proof

Step 10: Serialize proof:
         - Merkle roots (trace, quotient, FRI rounds): 10 × 32 = 320 bytes
         - Query responses: for each query position, leaf values +
           authentication paths across all committed polynomials
         - FRI final value
```

### Verifier Changes

```
Step 1: Re-derive all Fiat-Shamir challenges from Merkle roots

Step 2: For each query position z:
        a. Verify Merkle opening of trace(z) against trace root
        b. Verify Merkle opening of quotient(z) against quotient root
        c. Check constraint: quotient(z) * zerofier(z) == constraint(z)
        d. Check FRI consistency across rounds

Step 3: All queries pass → TRUE
```

### Query Count and Soundness

With λ bits of security and ρ = 1/4 proximity parameter:
- Queries needed: q = λ / log₂(1/ρ) = 128 / 2 = 64 queries

For 256 evaluations with 64 queries, the "succinct" proof will
actually be *larger* than shipping the full polynomial.  This is
expected — **succinct proofs only win for large evaluation domains**
(≥ 1024 points, i.e., after LDE in Phase 5).

**Phase 3 value:** builds the correct protocol structure so Phase 5
only needs to increase the domain size, not restructure the proof.

### API (unchanged from MVP)

```forth
STARK-TRACE!       ( val idx -- )
STARK-TRACE@       ( idx -- val )
STARK-TRACE-ZERO   ( -- )
STARK-PROVE        ( pub0 pub1 -- )
STARK-VERIFY       ( pub0 pub1 -- flag )
STARK-FRI-FINAL@   ( -- val )
STARK-PROOF-SIZE   ( -- n )              \ NEW: return proof size in bytes
```

### Definition of Done

- All existing MVP tests still pass (same API)
- Prover uses Merkle commitments (not hash-of-buffer)
- Verifier does probabilistic spot-checks (configurable query count)
- Batch inversion measurably faster than MVP (benchmark)
- Tampered Merkle path → verify FALSE
- ~35 tests

---

## Phase 4 — `air.f`: General Constraint Compiler

**File:** `akashic/math/air.f`
**Prefix:** `AIR-`
**Depends on:** `ntt.f`
**Est.:** ~200 lines

### The Problem

The MVP hard-codes "Fibonacci" into the prover and verifier.
You cannot describe a different computation without rewriting
stark.f internals.  Real STARKs parameterise the constraint
system — the prover and verifier are generic over any AIR.

### Design

An AIR (Algebraic Intermediate Representation) describes:
- **Trace width**: number of columns
- **Transition constraints**: polynomials over adjacent rows
- **Boundary constraints**: fixed values at specific rows

The constraint compiler builds a compact descriptor that STARK-PROVE
and STARK-VERIFY interpret at runtime.

### Constraint Descriptor

Stored as a flat byte buffer:

```
Header:
  +0x00  u16  n_cols         number of trace columns
  +0x02  u16  n_trans        number of transition constraints
  +0x04  u16  n_boundary     number of boundary constraints
  +0x06  u16  reserved

Transition entries (8 bytes each):
  +0x00  u8   type           0=ADD, 1=SUB, 2=MUL, 3=CONST
  +0x01  u8   col_a          column index of left operand
  +0x02  u8   row_off_a      row offset (0=current, 1=next, 2=next-next)
  +0x03  u8   col_b          column index of right operand
  +0x04  u8   row_off_b      row offset
  +0x05  u8   col_result     column index that should equal the result
  +0x06  u8   row_off_result row offset
  +0x07  u8   reserved

Boundary entries (8 bytes each):
  +0x00  u8   col            column index
  +0x02  u16  row            row index
  +0x04  u32  value          expected value (mod q)
```

### API

| # | Word | Stack | Description |
|---|------|-------|-------------|
| 4a | `AIR-BEGIN` | `( n-cols -- )` | Start AIR definition |
| 4b | `AIR-TRANS` | `( type colA offA colB offB colR offR -- )` | Add transition constraint |
| 4c | `AIR-BOUNDARY` | `( col row val -- )` | Add boundary constraint |
| 4d | `AIR-END` | `( -- air-addr )` | Finalize, return descriptor |
| 4e | `AIR-EVAL-TRANS` | `( air trace-cols x_i -- val )` | Evaluate transition at coset point |
| 4f | `AIR-CHECK-BOUNDARY` | `( air trace-cols -- flag )` | Check all boundary constraints |

### Example: Fibonacci AIR

```forth
1 AIR-BEGIN
    0 0 0    0 1 0    0 2 0  AIR-TRANS    \ col0[i+2] = col0[i] + col0[i+1]
    0 0 1  AIR-BOUNDARY                    \ col0[0] = 1
    0 1 1  AIR-BOUNDARY                    \ col0[1] = 1
AIR-END  CONSTANT FIB-AIR
```

### Example: Range-check AIR (multi-column)

```forth
2 AIR-BEGIN
    \ col0[i+1] - col0[i] is in {0,1,...,255}
    \ col1[i] = (col0[i+1] - col0[i]) * (col0[i+1] - col0[i] - 1) * ... 
    \ (simplified — real range checks use lookup tables)
    ...
AIR-END  CONSTANT RANGE-AIR
```

### Definition of Done

- Fibonacci AIR descriptor matches hardcoded MVP behavior
- Can define 2-column AIR (e.g., memory consistency check)
- Constraint evaluator produces correct values on coset
- Boundary checker passes for valid trace, fails for invalid
- stark.f v2 can accept AIR descriptor instead of hardcoded Fibonacci
- ~15 tests

---

## Phase 4.5 — `stark.f` v2.5: Multi-Column Traces (NEW)

**File:** `akashic/math/stark.f` (extend v2)
**Prefix:** `STARK-`
**Depends on:** `sha3.f`, `ntt.f`, `merkle.f`, `baby-bear.f`, `stark-air.f`
**Est.:** ~650 lines (replaces previous ~487)
**Status:** **Done** — stark.f v2.5 committed, 42/42 tests pass (32 regression + 10 multi-column)
**Priority:** **Critical** — prerequisite for any real AIR beyond single-column Fibonacci

### The Problem

stark-air.f (Phase 4) already supports multi-column AIR descriptors:
`AIR-BEGIN(n-cols)`, `AIR-TRANS` with per-column indices, `AIR-BOUNDARY`
with column selection.  But stark.f v2 has **only one trace polynomial**
(`_SK-TRACE`), one coset evaluation buffer (`_SK-CEVAL`), and a 1-entry
cols array (`_SK-COLS`).  The prover literally cannot represent a
2-column computation.

This is a prerequisite for the consensus STARK overlay (Phase 5b in
ROADMAP_blockchain.md), which needs columns for old_bal, new_bal,
amount, nonce_old, nonce_new — minimum 5 columns.

Multi-column is **not** an optimization or a Phase 5 luxury.  It is
the minimum functionality for any real AIR beyond Fibonacci.

### What Changes

| Component | v2 | v2.5 |
|-----------|-----|------|
| Trace polynomials | 1 (`_SK-TRACE`) | N (`_SK-TRACES` array of NTT-POLY) |
| Coset eval buffers | 1 (`_SK-CEVAL` 1040 bytes) | N (1040 bytes each) |
| Cols array | 1 cell (`_SK-COLS`) | N cells (`_SK-COLS[0..N-1]`) |
| `STARK-TRACE!` | `( val idx -- )` | `( val col idx -- )` |
| `STARK-TRACE@` | `( idx -- val )` | `( col idx -- val )` |
| Merkle commitment | 1 tree (_SK-MTRACE) | N trees (or combined leaf hash) |
| Constraint quotient | Single-column residual | Multi-column residual via AIR-EVAL-TRANS |
| Proof commitment | 1 trace root | Combined trace root (hash of N roots) |

### Design: Max Columns

`STARK-MAX-COLS = 8` (compile-time constant).  Sufficient for the
consensus AIR (5 columns) with room for flags/scratch.  Memory:

```
Per column:
  NTT polynomial:    256 × 4 =  1,024 bytes
  Coset eval buffer: 260 × 4 =  1,040 bytes
  Temp coefficients: 256 × 4 =  1,024 bytes
  Merkle tree:       511 × 32 = 16,352 bytes
                              ≈  19 KB/column

8 columns: ~152 KB total (fits easily in 16 MB XMEM)
```

### API Changes

```forth
STARK-SET-COLS     ( n -- )             Set active column count (1..8)
STARK-TRACE!       ( val col idx -- )   Write trace entry (column-aware)
STARK-TRACE@       ( col idx -- val )   Read trace entry (column-aware)
STARK-TRACE-ZERO   ( -- )              Zero all active trace columns
STARK-INIT         ( -- )              Same — also allocates per-column buffers
STARK-SET-AIR      ( air -- )          Same
STARK-PROVE        ( -- )              Updated: per-column interpolation, commitment, combined quotient
STARK-VERIFY       ( -- flag )         Updated: per-column verification
```

### Prover Changes

The prove pipeline becomes:

```
For each column c in 0..N-1:
  Step 1: Copy trace[c] → tcoeff[c], NTT-INVERSE
  Step 2: Coset-evaluate tcoeff[c] → ceval[c]
  Step 3: Copy ceval[c] with wrap to extended buffer
  Step 4: Merkle-commit tcoeff[c] → mtrace[c]

Set _SK-COLS[c] = ceval[c] for all c
Combined trace root = SHA3(trace_root[0] || ... || trace_root[N-1])

Fiat-Shamir absorbs combined trace root

Constraint quotient loop:
  For each coset point i:
    residual = AIR-EVAL-TRANS(air, cols, i)   ← already multi-column!
    quotient[i] = residual * inv_zerofier[i]

  Boundary quotients: per-boundary per-column (AIR-CHECK-BOUND already
  indexes by column)

FRI on the constraint quotient polynomial (single polynomial — the
quotient combines all columns).  FRI folding unchanged.
```

The key insight: **the quotient polynomial is always single-column**
(it combines all column residuals).  FRI folding doesn't need to
change.  Only the trace storage, commitment, and residual evaluation
need multi-column support.

### Backward Compatibility

Single-column usage still works.  If `STARK-SET-COLS` is not called
(or called with 1), the API behaves identically to v2 except that
`STARK-TRACE!` and `STARK-TRACE@` take an extra `col` argument (0).

### Definition of Done

- 2-column Fibonacci AIR: col0 = a, col1 = b, transition a'=b, b'=a+b
- 5-column balance-transfer AIR:
  col0=old_bal_sender, col1=new_bal_sender, col2=amount,
  col3=old_bal_recip, col4=new_bal_recip
  Transition: new_bal_sender = old_bal_sender - amount,
              new_bal_recip = old_bal_recip + amount
- Boundary constraints on specific columns at specific rows
- Merkle commitment per column, combined root verified
- Tamper any single column → verify fails
- Original 1-column tests still pass (with col=0)
- ~20 tests (cumulative with v2: ~55 STARK tests)

---

## Phase 5 — `stark.f` v3: LDE + ZK + Hardening

**File:** `akashic/math/stark.f` (replace v2)
**Prefix:** `STARK-`
**Depends on:** `sha3.f`, `ntt.f`, `merkle.f`, `batch.f`, `air.f`
**Est.:** ~700 lines

### The Problem

Without a blowup factor, the evaluation domain equals the trace
domain (256 points).  Reed-Solomon proximity testing needs the
codeword to be evaluated on a domain significantly larger than the
polynomial degree.  Standard blowup = 4× or 8×, meaning
1024 or 2048 evaluation points.

Without ZK masking, the full trace is recoverable from the proof.
For applications like private computation or ML inference proofs,
the trace must be hidden.

### Low-Degree Extension (LDE)

Evaluate the trace polynomial (degree < 256) on a larger coset:

```
Trace domain:      {ω^0, ω^1, ..., ω^255}         256 points
Evaluation domain: {g·ω'^0, g·ω'^1, ..., g·ω'^1023}  1024 points
```

where ω' is a 1024th root of unity (exists because
(q−1) = 2^27 × 15, so 1024 | (q−1)) and g is a coset shift.

**Hardware NTT is 256-point.** For 1024-point evaluation:
- Split the degree-255 polynomial into 4 chunks of 64 coefficients
- Evaluate each chunk at the 256-point NTT domains
- Combine with appropriate twiddle factors

Or: use NTT-256 four times with shifted domains.  This is a
multi-pass NTT requiring careful bookkeeping but no new hardware.

### ZK Masking

Add a random polynomial of degree < trace_degree to the trace
polynomial, with its leading coefficients chosen so that the
constraint quotient remains unchanged.  Specifically:

```
masked_trace(x) = trace(x) + Z_trace(x) · random(x)
```

where `Z_trace(x) = x^256 − 1` is the trace zerofier and
`random(x)` is a low-degree random polynomial.  The constraints
still hold (because Z_trace vanishes on the trace domain), but
evaluations outside the trace domain are randomized.

### Changes from v2

| Component | v2 | v3 |
|-----------|-----|-----|
| Evaluation domain | 256 (coset) | 1024 (4× blowup) |
| NTT passes | 1 × 256 | 4 × 256 (multi-pass) |
| Merkle tree leaves | 256 | 1024 |
| Proof size | ~2,500 bytes | ~4,000 bytes (but 128-bit security) |
| ZK | No | Yes — random masking polynomial |
| AIR | Fibonacci or via air.f | Fully parameterized via air.f |
| FRI | 8 rounds (256→1) | 10 rounds (1024→1) |
| Soundness | ~64 bits (small domain) | ~128 bits |

### Memory Budget

```
Trace polynomial:     1024 × 4 =  4,096 bytes (ext_mem)
Evaluation domain:    1024 × 4 =  4,096 bytes (ext_mem)
Merkle tree (1024):   2047 × 32 = 65,504 bytes (ext_mem)
Quotient polynomial:  1024 × 4 =  4,096 bytes (ext_mem)
Quotient Merkle tree: 2047 × 32 = 65,504 bytes (ext_mem)
FRI (10 rounds):      ~8,192 bytes (ext_mem)
FRI Merkle trees:     10 × ~65 KB (ext_mem)
Scratch buffers:      ~12 KB

Total: ~800 KB (fits in 16 MB ext_mem)
```

### API (extends v2)

```forth
STARK-SET-BLOWUP   ( n -- )           Set blowup factor (4 or 8)
STARK-SET-AIR      ( air-addr -- )     Use custom AIR descriptor
STARK-SET-ZK       ( flag -- )         Enable/disable ZK masking
STARK-PROVE        ( -- )             Generate proof (reads AIR for boundary values)
STARK-VERIFY       ( -- flag )        Verify proof
STARK-SECURITY     ( -- bits )         Report effective security level
```

### Definition of Done

- LDE: 256-row trace evaluated on 1024-point domain via 4-pass NTT
- Merkle commitment over 1024 leaves, Merkle openings verified
- ZK: two proofs of same trace produce different transcripts
- AIR: Fibonacci and at least one non-Fibonacci AIR both work
- FRI: 10 rounds with evaluation-space folding
- 128-bit soundness with 64 queries
- Proof size < 8 KB
- Verifier runs in O(log² n)
- ~50 tests

---

## Dependency Graph

```
Done:
  sha3.f ✅    ntt.f ✅    random.f ✅    field.f ✅    crc.f ✅

Written, untested:
  stark.f MVP ⬜

Phase 1 ─→ merkle.f ←── sha3.f ✅
              │
              ├── vault (crypto-SIMD-hardened.md Phase 3a)
              ├── content-addressed storage
              └── authenticated data structures

Phase 2 ─→ batch.f ←── (standalone, uses Baby Bear or any mod arith)
              │
              ├── Lagrange interpolation
              ├── elliptic curve batch verify
              └── any multi-inversion workload

Phase 3 ─→ stark.f v2 ←── merkle.f, batch.f, sha3.f ✅, ntt.f ✅

Phase 4 ─→ air.f ←── ntt.f ✅
              │
              └── general computation proofs

Phase 4.5 ─→ stark.f v2.5 ←── stark.f v2, air.f
              │
              ├── multi-column traces (N NTT polynomials)
              ├── consensus STARK overlay (ROADMAP_blockchain Phase 5b)
              └── any real AIR beyond single-column Fibonacci

Phase 5 ─→ stark.f v3 ←── merkle.f, batch.f, air.f, sha3.f ✅, ntt.f ✅
              │
              ├── verifiable ML inference (crypto-SIMD-hardened.md Phase 3c)
              └── private computation proofs
```

---

## Design Constraints

1. **256-point hardware NTT.** Cannot be changed.  Larger domains
   require multi-pass decomposition (4 × 256 = 1024, etc.).
   This is the main engineering challenge in Phase 5.

2. **32-bit NTT coefficients.** Baby Bear fits cleanly.  Larger
   primes (Goldilocks 2^64 − 2^32 + 1) would need software NTT.

3. **64-bit Forth cells.** Products a × b fit for a,b < 2^31.
   No overflow risk with Baby Bear.

4. **16 MB ext_mem.** Merkle trees for 1024 leaves are ~65 KB each.
   With 12 committed polynomials (trace + quotient + 10 FRI rounds),
   total Merkle storage is ~780 KB.  Fits comfortably.

5. **DO..LOOP is compile-only.** All loops in colon definitions.

6. **Paren comment `)` kills compilation.** Use `\` line comments.

7. **SHA3-256 API is `( src len dst -- )`.** Not streaming for
   multi-block — concatenate in scratch buffer first.  The Merkle
   internal node hash needs a 65-byte scratch (1 domain byte +
   32 left + 32 right).

8. **Proof transport.** The emulator has no filesystem.  Proofs
   live in RAM/ext_mem buffers.  Serialization to a flat blob is
   only needed for network transport (future web integration).

---

## Testing Strategy

Same snapshot-based pattern as all other modules.

| Phase | Library | Tests | Cumulative |
|-------|---------|-------|-----------|
| 0 | stark.f MVP | ~30 | 30 |
| 1 | merkle.f | ~20 | 50 |
| 2 | batch.f | ~8 | 58 |
| 3 | stark.f v2 | ~35 | 93 |
| 4 | air.f | ~15 | 108 |
| 4.5 | stark.f v2.5 (multi-col) | ~20 | 128 |
| 5 | stark.f v3 | ~50 | 178 |

### Key test categories per phase

**merkle.f:**
- Build from known leaves, root matches reference
- Open + verify every leaf position
- Tampered sibling → verify fails
- Different tree sizes (64, 128, 256)

**batch.f:**
- Batch-invert 256 values, each `a * a^{-1} = 1`
- Matches individual inversions
- Edge: includes value 1

**stark.f v2:**
- All MVP tests pass (API compatible)
- Merkle commitment replaces hash-of-buffer
- Probabilistic verifier accepts honest proof
- Tampered Merkle path → reject
- Batch inversion used (benchmark vs MVP)

**air.f:**
- Fibonacci AIR matches hardcoded behavior
- Multi-column AIR evaluates correctly
- Invalid trace → constraint evaluator returns nonzero

**stark.f v3:**
- 4× blowup: 1024-point evaluation domain
- ZK: two proofs of same trace differ
- General AIR: Fibonacci + non-Fibonacci
- 128-bit security: 64 query positions
- Proof size under 8 KB
- Full tamper battery on Merkle paths, coefficients, commitments
