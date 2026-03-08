# stark.f — STARK Prover / Verifier v2.5

**Module:** `akashic/math/stark.f`
**Prefix:** `STARK-`
**Depends on:** `sha3.f`, `ntt.f`, `baby-bear.f`, `merkle.f`, `stark-air.f`
**Provided:** `akashic-stark`
**Tests:** 42/42 (32 regression + 10 multi-column)

## Overview

STARK prover and verifier over the Baby Bear field
($q = 2013265921$), with 256-point traces, up to 8 columns,
coefficient-space FRI folding, and SHA3-256 Merkle commitments.
Accepts any AIR descriptor built with `stark-air.f`, making the
prover/verifier generic over arbitrary transition and boundary
constraints with multi-column traces.

## Design Principles

| Principle | Decision |
|-----------|----------|
| **Field** | Baby Bear ($q = 15 \times 2^{27} + 1$) via `baby-bear.f` |
| **Trace size** | Fixed 256 entries per column, up to 8 columns |
| **Domain** | $\omega$ = primitive 256th root of unity, extracted via NTT trick |
| **Coset** | Generator $k = 3$ (or 5 if $3^{256} = 1$), ensures disjoint evaluation domain |
| **Interpolation** | Inverse NTT for trace → coefficients; NTT for coset evaluation |
| **Commitments** | N separate SHA3-256 Merkle trees (one per column, 256 leaves each) |
| **Combined root** | SHA3-256 hash of concatenated per-column Merkle roots |
| **Fiat-Shamir** | Hash-based transcript: absorb combined root, per-boundary challenges |
| **Quotient** | Combined transition + boundary quotients with per-boundary random scaling |
| **FRI** | 8 rounds of coefficient-space folding ($256 \to 1$), each round committed |
| **Verifier** | Exhaustive: rebuilds all Merkle trees, checks all AIR constraints, replays FRI |
| **Variables over return stack** | All loop state uses `VARIABLE` — `>R`/`R@` inside `DO..LOOP` is unsafe |
| **Not re-entrant** | Shared buffers, Merkle trees, and MMIO devices |

## Protocol Overview

### Prover (`STARK-PROVE`)

1. **Per-column interpolation and commitment** — For each column $c$:
   - NTT-inverse trace[c] to get coefficients tcoeff[c]
   - Coset-evaluate tcoeff[c] → ceval[c] (twist by $k^i$, NTT-forward)
   - Copy ceval[c] with 4-entry wrap for AIR offset lookups
   - Merkle-commit tcoeff[c] → merkle_tree[c], copy root to troots[c]
   - Set `_SK-COLS[c]` = address of ceval[c]
2. **Combined trace root** — `SHA3(troots[0] || ... || troots[N-1])`
3. **Fiat-Shamir** — Absorb combined trace root, derive per-boundary challenges
4. **Build denominators** — Transition zerofier $\prod_j (x_i - \omega^{256-\text{maxoff}+j})$ and per-boundary zerofiers $(x_i - \omega^{\text{row}})$, batch-invert via `BB-BATCH-INV`
5. **Combined quotient** — For each coset point: transition residual / transition denom + $\sum_j$ challenge$_j \cdot$ (P$_{\text{col}_j}$(x$_i$) - val$_j$) / boundary denom$_j$
6. **Inverse coset** — Un-twist quotient back to coefficient space
7. **Commit quotient** — Merkle tree over quotient coefficients
8. **FRI** — 8 rounds of folding with Fiat-Shamir challenges, final constant stored

### Verifier (`STARK-VERIFY`)

1. Rebuild per-column Merkle commitments, compare each root
2. Re-derive combined trace root, compare
3. Re-derive Fiat-Shamir challenges (per-boundary)
4. NTT each column's coefficients to evaluation form, check all AIR transitions and boundaries
5. Rebuild quotient Merkle commitment, compare root
6. Replay all 8 FRI rounds: re-hash, re-fold, compare byte-for-byte
7. Verify FRI final constant

Returns `TRUE` (-1) if all checks pass, `FALSE` (0) otherwise.

## API Reference

### Initialization

| Word | Stack | Description |
|------|-------|-------------|
| `STARK-INIT` | `( -- )` | Compute domain parameters, initialize per-column Merkle tree headers, default 1 column |
| `STARK-SET-COLS` | `( n -- )` | Set active column count (clamped to 1..8) |
| `STARK-SET-AIR` | `( air -- )` | Set the AIR descriptor for proving/verifying |

### Trace Management

| Word | Stack | Description |
|------|-------|-------------|
| `STARK-TRACE!` | `( val col idx -- )` | Store value at trace column/index |
| `STARK-TRACE@` | `( col idx -- val )` | Read value at trace column/index |
| `STARK-TRACE-ZERO` | `( -- )` | Zero all active trace columns |

### Proving and Verifying

| Word | Stack | Description |
|------|-------|-------------|
| `STARK-PROVE` | `( -- )` | Generate a STARK proof (populates all internal buffers) |
| `STARK-VERIFY` | `( -- flag )` | Exhaustive verification; returns TRUE or FALSE |
| `STARK-FRI-FINAL@` | `( -- val )` | Read the FRI final constant from the last proof |

## Domain Parameters

`STARK-INIT` computes and stores:

| Variable | Value | Description |
|----------|-------|-------------|
| `_SK-OMEGA` | $\omega$ | Primitive 256th root of unity ($\omega^{256} = 1$, $\omega^{128} \neq 1$) |
| `_SK-OMEGA-INV` | $\omega^{-1}$ | Inverse of $\omega$ |
| `_SK-K` | 3 | Coset generator (shifted to 5 if $3^{256} = 1$) |
| `_SK-K-INV` | $k^{-1}$ | Inverse of $k$ |
| `_SK-K256` | $k^{256}$ | Used to verify coset is disjoint ($k^{256} \neq 1$) |
| `_SK-ZINV` | $(k^{256} - 1)^{-1}$ | Zerofier-domain scaling factor |

## Buffer Layout

| Buffer | Size | Purpose |
|--------|------|---------|
| `_SK-TRACES` | 8192 B | Per-column raw trace values (8 × 1024) |
| `_SK-TCOEFFS` | 8192 B | Per-column trace coefficients (8 × 1024) |
| `_SK-CEVALS` | 8320 B | Per-column extended coset evals (8 × 1040) |
| `_SK-COLS` | 64 B | Cell array of ceval base addresses (8 cells) |
| `_SK-MTREES` | 130880 B | Per-column Merkle trees (8 × 16360) |
| `_SK-TROOTS` | 256 B | Per-column Merkle roots (8 × 32) |
| `_SK-TROOT` | 32 B | Combined trace root |
| `_SK-TMP1`, `_SK-TMP2` | 1024 B each | Scratch polynomials |
| `_SK-QCOEFF` | 1024 B | Quotient polynomial coefficients |
| `_SK-DENOM`, `_SK-DINV` | 18432 B each | Zerofier denominators and batch inverses (up to 16 boundaries) |
| `_SK-BCHAL` | 128 B | Per-boundary Fiat-Shamir challenges (up to 16 boundaries) |
| `_SK-FRI-BUF` | 2048 B | FRI round data |
| `_SK-FRI-HASH` | 256 B | FRI round commitments (8 × 32 bytes) |
| `_SK-MQUO` | 16360 B | Quotient Merkle tree (256-leaf) |

**Total static buffers: ~215 KB** (fits in 2 MB RAM with KDOS overhead).

## Address Helpers

| Word | Stack | Description |
|------|-------|-------------|
| `_SK-TRACE-ADDR` | `( col -- addr )` | Address of trace polynomial for column |
| `_SK-TCOEFF-ADDR` | `( col -- addr )` | Address of coefficient buffer for column |
| `_SK-CEVAL-ADDR` | `( col -- addr )` | Address of coset eval buffer for column |
| `_SK-MTREE-ADDR` | `( col -- addr )` | Address of Merkle tree for column |

## FRI Folding

The FRI protocol reduces the quotient polynomial from degree < 256
to a constant in 8 rounds:

| Round | Input size | Output size | Offset in `_SK-FRI-BUF` |
|-------|-----------|------------|-------------------------|
| 0 | 256 | 128 | 0 |
| 1 | 128 | 64 | 1024 |
| 2 | 64 | 32 | 1536 |
| 3 | 32 | 16 | 1792 |
| 4 | 16 | 8 | 1920 |
| 5 | 8 | 4 | 1984 |
| 6 | 4 | 2 | 2016 |
| 7 | 2 | 1 | 2032 |

Each round: hash data → absorb into Fiat-Shamir → squeeze challenge
→ fold pairs $(c_{2i}, c_{2i+1}) \mapsto c_{2i} + r \cdot c_{2i+1}$.
Round 7 produces the final constant stored in `_SK-FRI-FINAL`.

## Usage Example — Single Column (Backward Compatible)

```forth
STARK-INIT

1 AIR-BEGIN
  AIR-ADD 0 0  0 1  0 2  AIR-TRANS
  0 0 1 AIR-BOUNDARY
  0 1 1 AIR-BOUNDARY
AIR-END CONSTANT FIB-AIR

FIB-AIR STARK-SET-AIR

STARK-TRACE-ZERO
1 0 0 STARK-TRACE!
1 0 1 STARK-TRACE!
254 0 DO
  0 I STARK-TRACE@ 0 I 1 + STARK-TRACE@ BB+
  0 I 2 + STARK-TRACE!
LOOP

STARK-PROVE
STARK-VERIFY IF ." Valid" ELSE ." Invalid" THEN
```

## Usage Example — Multi-Column (2-Column Fibonacci + Running Sum)

```forth
STARK-INIT
2 STARK-SET-COLS

2 AIR-BEGIN
  AIR-ADD 0 0  0 1  0 2  AIR-TRANS     \ col0[i] + col0[i+1] = col0[i+2]
  AIR-ADD 1 0  0 0  1 1  AIR-TRANS     \ col1[i] + col0[i] = col1[i+1]
  0 0 1 AIR-BOUNDARY                    \ col0[0] = 1
  0 1 1 AIR-BOUNDARY                    \ col0[1] = 1
  1 0 0 AIR-BOUNDARY                    \ col1[0] = 0
AIR-END CONSTANT MC-AIR

MC-AIR STARK-SET-AIR

\ Fill col0: Fibonacci
STARK-TRACE-ZERO
1 0 0 STARK-TRACE!   1 0 1 STARK-TRACE!
254 0 DO
  0 I STARK-TRACE@ 0 I 1 + STARK-TRACE@ BB+
  0 I 2 + STARK-TRACE!
LOOP

\ Fill col1: running sum of col0
0 1 0 STARK-TRACE!
255 0 DO
  1 I STARK-TRACE@ 0 I STARK-TRACE@ BB+
  1 I 1 + STARK-TRACE!
LOOP

STARK-PROVE
STARK-VERIFY IF ." Valid" ELSE ." Invalid" THEN
```

## Tamper Detection

The verifier detects any of the following modifications after proving:

- Trace value changes on any column (`STARK-TRACE!` after `STARK-PROVE`)
- Coefficient corruption (`_SK-TCOEFFS`, `_SK-QCOEFF`)
- Per-column Merkle root tampering (`_SK-TROOTS`)
- Combined trace root tampering (`_SK-TROOT`)
- Quotient root tampering (`_SK-QROOT`)
- FRI buffer corruption (`_SK-FRI-BUF`)
- FRI final value changes (`_SK-FRI-FINAL`)
- Wrong boundary values in the AIR descriptor (any column)

## Quick Reference

```
STARK-INIT          ( -- )
STARK-SET-COLS      ( n -- )
STARK-SET-AIR       ( air -- )
STARK-TRACE!        ( val col idx -- )
STARK-TRACE@        ( col idx -- val )
STARK-TRACE-ZERO    ( -- )
STARK-PROVE         ( -- )
STARK-VERIFY        ( -- flag )
STARK-FRI-FINAL@    ( -- val )
```
