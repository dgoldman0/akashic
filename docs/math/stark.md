# stark.f — STARK Prover / Verifier

**Module:** `akashic/math/stark.f`
**Prefix:** `STARK-`
**Depends on:** `sha3.f`, `ntt.f`, `baby-bear.f`, `merkle.f`, `stark-air.f`
**Provided:** `akashic-stark`
**Tests:** 32/32

## Overview

STARK prover and verifier over the Baby Bear field
($q = 2013265921$), with 256-point traces, coefficient-space FRI
folding, and SHA3-256 Merkle commitments.  Accepts any AIR
descriptor built with `stark-air.f`, making the prover/verifier
generic over arbitrary transition and boundary constraints.

## Design Principles

| Principle | Decision |
|-----------|----------|
| **Field** | Baby Bear ($q = 15 \times 2^{27} + 1$) via `baby-bear.f` |
| **Trace size** | Fixed 256 entries (single column) |
| **Domain** | $\omega$ = primitive 256th root of unity, extracted via NTT trick |
| **Coset** | Generator $k = 3$ (or 5 if $3^{256} = 1$), ensures disjoint evaluation domain |
| **Interpolation** | Inverse NTT for trace → coefficients; NTT for coset evaluation |
| **Commitments** | SHA3-256 Merkle trees (256 leaves each) for trace and quotient polynomials |
| **Fiat-Shamir** | Hash-based transcript: absorb Merkle roots, squeeze challenges via SHA3-256 |
| **Quotient** | Combined transition + boundary quotients with random linear combination |
| **FRI** | 8 rounds of coefficient-space folding ($256 \to 1$), each round committed |
| **Verifier** | Exhaustive: rebuilds Merkle trees, checks all AIR constraints, replays FRI |
| **Variables over return stack** | All loop state uses `VARIABLE` — `>R`/`R@` inside `DO..LOOP` is unsafe |
| **Not re-entrant** | Shared buffers, Merkle trees, and MMIO devices |

## Protocol Overview

### Prover (`STARK-PROVE`)

1. **Interpolate** — NTT-inverse the trace to get coefficients
2. **Coset-evaluate** — twist coefficients by $k^i$, then NTT-forward
3. **Commit trace** — hash each coefficient as a Merkle leaf, build tree
4. **Fiat-Shamir** — absorb trace root, squeeze $\alpha$, $\beta$ challenges
5. **Build denominators** — transition zerofier $\prod_j (x_i - \omega^{256-\text{maxoff}+j})$ and boundary zerofiers $(x_i - \omega^{\text{row}})$, batch-invert via `BB-BATCH-INV`
6. **Combined quotient** — for each coset point: transition residual / transition denom + $\alpha \cdot$ boundary₀ quotient + $\beta \cdot$ boundary₁ quotient
7. **Inverse coset** — un-twist quotient back to coefficient space
8. **Commit quotient** — Merkle tree over quotient coefficients
9. **FRI** — 8 rounds of folding with Fiat-Shamir challenges, final constant stored

### Verifier (`STARK-VERIFY`)

1. Rebuild trace Merkle commitment, compare root
2. Re-derive Fiat-Shamir challenges from stored trace root
3. NTT trace coefficients to evaluation form, check all AIR transitions and boundaries
4. Rebuild quotient Merkle commitment, compare root
5. Replay all 8 FRI rounds: re-hash, re-fold, compare byte-for-byte
6. Verify FRI final constant

Returns `TRUE` (-1) if all checks pass, `FALSE` (0) otherwise.

## API Reference

### Initialization

| Word | Stack | Description |
|------|-------|-------------|
| `STARK-INIT` | `( -- )` | Compute domain parameters ($\omega$, $k$, $k^{256}$, $z^{-1}$), initialize FRI offset table |
| `STARK-SET-AIR` | `( air -- )` | Set the AIR descriptor for proving/verifying |

### Trace Management

| Word | Stack | Description |
|------|-------|-------------|
| `STARK-TRACE!` | `( val idx -- )` | Store value at trace index (0–255) |
| `STARK-TRACE@` | `( idx -- val )` | Read value at trace index |
| `STARK-TRACE-ZERO` | `( -- )` | Zero the entire 256-entry trace |

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
| `_SK-TRACE` | 1024 B | Raw trace values (NTT-POLY format) |
| `_SK-TCOEFF` | 1024 B | Trace polynomial coefficients |
| `_SK-TMP1`, `_SK-TMP2` | 1024 B each | Scratch polynomials |
| `_SK-QCOEFF` | 1024 B | Quotient polynomial coefficients |
| `_SK-CEVAL` | 1040 B | Extended coset evaluations (260 entries for wraparound) |
| `_SK-DENOM`, `_SK-DINV` | 4096 B each | Zerofier denominators and their batch inverses |
| `_SK-FRI-BUF` | 2048 B | FRI round data (256+128+64+...+2 = 510 entries) |
| `_SK-FRI-HASH` | 256 B | FRI round commitments (8 × 32 bytes) |
| `_SK-MTRACE`, `_SK-MQUO` | 256-leaf Merkle trees | Trace and quotient commitments |

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

## Usage Example

```forth
\ Fibonacci STARK: trace[i+2] = trace[i] + trace[i+1]

STARK-INIT

\ Define AIR
1 AIR-BEGIN
  AIR-ADD 0 0  0 1  0 2  AIR-TRANS
  0 0 1 AIR-BOUNDARY
  0 1 1 AIR-BOUNDARY
AIR-END CONSTANT FIB-AIR

FIB-AIR STARK-SET-AIR

\ Fill trace
STARK-TRACE-ZERO
1 0 STARK-TRACE!
1 1 STARK-TRACE!
254 0 DO
  I STARK-TRACE@ I 1 + STARK-TRACE@ BB+
  I 2 + STARK-TRACE!
LOOP

\ Prove
STARK-PROVE

\ Verify
STARK-VERIFY IF ." Valid proof" ELSE ." Invalid proof" THEN
```

## Tamper Detection

The verifier detects any of the following modifications after proving:

- Trace value changes (`STARK-TRACE!` after `STARK-PROVE`)
- Coefficient corruption (`_SK-TCOEFF`, `_SK-QCOEFF`)
- Merkle root tampering (`_SK-TROOT`, `_SK-QROOT`)
- FRI buffer corruption (`_SK-FRI-BUF`)
- FRI final value changes (`_SK-FRI-FINAL`)
- Wrong boundary values in the AIR descriptor

## Quick Reference

```
STARK-INIT          ( -- )
STARK-SET-AIR       ( air -- )
STARK-TRACE!        ( val idx -- )
STARK-TRACE@        ( idx -- val )
STARK-TRACE-ZERO    ( -- )
STARK-PROVE         ( -- )
STARK-VERIFY        ( -- flag )
STARK-FRI-FINAL@    ( -- val )
```
