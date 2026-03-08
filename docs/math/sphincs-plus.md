# akashic-sphincs-plus — SLH-DSA-SHAKE-128s (FIPS 205)

Post-quantum digital signatures using only hash functions.
Instantiation: SPHINCS+-SHAKE-128s (NIST security level 1).
All hashing via hardware-accelerated SHAKE-256.

```forth
REQUIRE sphincs-plus.f
```

`PROVIDED akashic-sphincs-plus` — depends on `akashic-sha3`, `akashic-random`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Key Generation](#key-generation)
- [Signing](#signing)
- [Verification](#verification)
- [Signing Mode](#signing-mode)
- [Performance](#performance)
- [Usage Example](#usage-example)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **FIPS 205 compliant** | Full SLH-DSA-SHAKE-128s implementation matching the specification |
| **Hardware-accelerated** | All hashing via MMIO SHA3/SHAKE-256 engine |
| **Pure Forth** | No assembly; only MMIO through `sha3.f` |
| **Stateless** | "s" variant — small signatures (7856 bytes), no state to manage |
| **Concurrency-safe** | Public API words wrapped with `WITH-GUARD` (not reentrant internally) |
| **Variable-free loops** | All `DO..LOOP` parameter passing uses VARIABLEs (not `>R`/`R@`) to avoid return-stack conflicts |
| **Secret zeroization** | `SPX-KEYGEN-RANDOM` zeroes internal seed buffer after use |
| **Length-validated** | `SPX-VERIFY` rejects signatures with wrong length before parsing |

---

## Constants

### SPX-N

```forth
SPX-N  ( -- 16 )
```

Security parameter in bytes (n = 16 for 128-bit security).

### SPX-SIG-LEN

```forth
SPX-SIG-LEN  ( -- 7856 )
```

Total signature length in bytes.

### SPX-PK-LEN

```forth
SPX-PK-LEN  ( -- 32 )
```

Public key length: PK.seed (16) ∥ PK.root (16).

### SPX-SK-LEN

```forth
SPX-SK-LEN  ( -- 64 )
```

Secret key length: SK.seed (16) ∥ SK.prf (16) ∥ PK.seed (16) ∥ PK.root (16).

---

## Key Generation

### SPX-KEYGEN

```forth
SPX-KEYGEN  ( seed pub sec -- )
```

Derive a keypair from a 48-byte seed.

| Parameter | Size | Description |
|---|---|---|
| `seed` | 48 bytes | SK.seed (16) ∥ SK.prf (16) ∥ PK.seed (16) |
| `pub` | 32 bytes | Output public key |
| `sec` | 64 bytes | Output secret key |

**Algorithm:**
1. Copy seed into sec[0..47]
2. Compute XMSS root of full hypertree (d=7 layers, 512 leaves)
3. Store root in sec[48..63] and pub[16..31]
4. Copy PK.seed into pub[0..15]

### SPX-KEYGEN-RANDOM

```forth
SPX-KEYGEN-RANDOM  ( pub sec -- )
```

Generate a keypair from the system RNG (`RANDOM8`).  Fills a 48-byte
seed from hardware randomness, then calls `SPX-KEYGEN`.  Zeroizes the
internal seed buffer (`_SPX-RNG-SEED`) on completion.

---

## Signing

### SPX-SIGN

```forth
SPX-SIGN  ( msg len sec sig -- )
```

Sign an arbitrary-length message.

| Parameter | Description |
|---|---|
| `msg` | Message buffer address |
| `len` | Message length in bytes |
| `sec` | 64-byte secret key |
| `sig` | 7856-byte output signature buffer |

**Signature layout** (7856 bytes):
```
[0..15]       R       — randomizer (16 bytes)
[16..2927]    FORS    — FORS signature (k=14 trees × 208 bytes = 2912)
[2928..7855]  HT      — Hypertree signature (d=7 layers × 704 bytes = 4928)
```

### SPX-SIGN-MODE

```forth
VARIABLE SPX-SIGN-MODE
SPX-MODE-RANDOM        ( -- 0 )   \ default: randomized signing
SPX-MODE-DETERMINISTIC ( -- 1 )   \ deterministic signing
```

When `SPX-MODE-RANDOM` (default), the randomizer R is derived from
`SK.prf`, an optional random value, and the message.  When
`SPX-MODE-DETERMINISTIC`, R is derived deterministically (no RNG call).

---

## Verification

### SPX-VERIFY

```forth
SPX-VERIFY  ( msg len pub sig sig-len -- flag )
```

Verify a signature.  Returns TRUE (-1) on success, FALSE (0) on failure.
Rejects immediately if `sig-len ≠ SPX-SIG-LEN` (7856).

| Parameter | Description |
|---|---|
| `msg` | Message buffer address |
| `len` | Message length in bytes |
| `pub` | 32-byte public key |
| `sig` | 7856-byte signature |
| `sig-len` | Byte length of `sig` buffer (must be exactly `SPX-SIG-LEN`) |

**Algorithm:**
1. Extract randomizer R from sig
2. Compute message digest H_msg(R, PK.seed, PK.root, M)
3. Reconstruct FORS public key from FORS signature
4. Verify hypertree signature against FORS pk

---

## Performance

Measured on the Megapad-64 emulator (Phase 3 STC, SHA3 MMIO accelerated):

| Operation | Cycles | Notes |
|---|---|---|
| SHA3-256-HASH (per hash in loop) | ~7,800 | Keccak in hardware |
| WOTS-PK-GEN (single key) | 1.53M | 35 chains × 15 hashes |
| XMSS-NODE(0,3) — 8 leaves | 9.61M | |
| XMSS-NODE(0,6) — 64 leaves | 74.2M | |
| **SPX-KEYGEN** | **591M** | 512 leaves (h'=9) |
| **SPX-SIGN** (estimated) | **~4.73G** | ~8× keygen |
| **SPX-VERIFY** (estimated) | **~45M** | ~100× faster than sign |

**At various clock speeds:**

| Clock | KEYGEN | SIGN | VERIFY |
|---|---|---|---|
| 200 MHz | 3.0 s | 23.7 s | 0.22 s |
| 500 MHz | 1.2 s | 9.5 s | 0.09 s |
| 1 GHz | 0.6 s | 4.7 s | 0.05 s |

The "s" (small) variant intentionally trades signing speed for compact
signatures (7856 bytes vs 49856 for the "f" variant).  Signing is a
one-time user action; verification is the hot path and runs very fast.

Compared to the reference C implementation (~7–8G cycles), our
Forth+HW-accelerated implementation achieves ~63% of the reference
cycle count thanks to the SHA3 MMIO engine.

**Bottleneck analysis:** 82% of per-hash cycle cost is Forth dispatch
overhead (stack shuffling, 6 MMIO transactions, ADRS byte writes).
A proposed WOTS+ chain MMIO accelerator would reduce signing to ~1.47G
cycles (~3.2× speedup).  See `local_testing/wots-chain-accelerator-request.md`.

---

## Usage Example

```forth
\ -- Generate keypair --
CREATE my-seed 48 ALLOT
\ ... fill my-seed with 48 random bytes ...
CREATE my-pub  32 ALLOT
CREATE my-sec  64 ALLOT
my-seed my-pub my-sec SPX-KEYGEN

\ -- Sign a message --
CREATE my-msg  5 ALLOT
S" hello" my-msg 5 CMOVE
CREATE my-sig  SPX-SIG-LEN ALLOT
my-msg 5 my-sec my-sig SPX-SIGN

\ -- Verify --
my-msg 5 my-pub my-sig SPX-SIG-LEN SPX-VERIFY   \ -> TRUE (-1)
```

---

## Internals

### Parameter Set (SHAKE-128s)

| Symbol | Value | Description |
|---|---|---|
| n | 16 | Security parameter (bytes) |
| h | 63 | Total tree height |
| d | 7 | Number of hypertree layers |
| h' | 9 | Height per XMSS tree (h/d) |
| a | 12 | FORS tree height |
| k | 14 | Number of FORS trees |
| w | 16 | Winternitz parameter |
| len₁ | 32 | WOTS+ message blocks |
| len₂ | 3 | WOTS+ checksum blocks |
| len | 35 | Total WOTS+ chains |

### Key Internal Words

| Word | Stack | Description |
|---|---|---|
| `_SPX-CHAIN` | `( src start steps dst -- )` | WOTS+ chain: iterate T₁ hash |
| `_SPX-WOTS-PK-GEN` | `( idx dst -- )` | Generate WOTS+ public key for leaf |
| `_SPX-XMSS-NODE` | `( start height dst -- )` | Compute XMSS subtree root via treehash |
| `_SPX-FORS-SIGN` | `( sig-out -- )` | FORS signing (k trees) |
| `_SPX-FORS-PK-FROM-SIG` | `( sig-in dst -- )` | Reconstruct FORS pk from signature |
| `_SPX-HT-SIGN` | `( msg tree leaf sig-out -- )` | Full hypertree signing |
| `_SPX-HT-VERIFY` | `( msg tree leaf sig-in root -- flag )` | Full hypertree verification |

### Hash Functions

All hash operations use SHAKE-256 via the SHA3 MMIO engine:

- **T₁** — `PRF(PK.seed, ADRS, input)` → n bytes
- **T₂** — `Hash(PK.seed, ADRS, left ∥ right)` → n bytes (Merkle node)
- **T_len** — `Hash(PK.seed, ADRS, len×n bytes)` → n bytes (WOTS+ pk compress)
- **PRF** — `PRF(PK.seed, ADRS, SK.seed)` → n bytes (secret derivation)
- **H_msg** — `Hash(R, PK.seed, PK.root, M)` → message digest (30 bytes)

### Important Implementation Notes

- `DO..LOOP` uses VARIABLEs (not `>R`/`R@`) because the return stack
  holds the loop index — `R@` inside a loop returns the loop counter,
  not a saved value.
- Nested `DO..LOOP` uses `I` (inner) and `J` (outer) for loop indices.
- All parameter passing to internal words uses module-level VARIABLEs
  (e.g., `_SPX-PK-SEED`, `_SPX-SK-SEED`), not stack parameters.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `SPX-KEYGEN` | `( seed pub sec -- )` | Keypair from 48-byte seed |
| `SPX-KEYGEN-RANDOM` | `( pub sec -- )` | Keypair from system RNG |
| `SPX-SIGN` | `( msg len sec sig -- )` | Sign message → 7856-byte sig |
| `SPX-VERIFY` | `( msg len pub sig sig-len -- flag )` | Verify signature |
| `SPX-N` | `( -- 16 )` | Security parameter |
| `SPX-SIG-LEN` | `( -- 7856 )` | Signature size |
| `SPX-PK-LEN` | `( -- 32 )` | Public key size |
| `SPX-SK-LEN` | `( -- 64 )` | Secret key size |
| `SPX-SIGN-MODE` | variable | 0=random, 1=deterministic |
