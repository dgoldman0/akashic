# akashic-sphincs-plus — SLH-DSA-SHAKE-128s (FIPS 205)

Post-quantum digital signatures using only hash functions.
Instantiation: SPHINCS+-SHAKE-128s (NIST security level 1).
General hashing uses the checked SHAKE-256 stream, and WOTS+ chain iteration
uses the checked production WOTS sequencer.

```forth
REQUIRE sphincs-plus.f
```

`PROVIDED akashic-sphincs-plus` — depends on `akashic-sha3`,
`akashic-random`, and the checked BIOS `WOTS-CHAIN` word.

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
| **Hardware-accelerated** | Segmented hashes use checked SHAKE-256; complete WOTS chains use the shared-Keccak production sequencer |
| **Checked interfaces** | No raw MMIO transaction words; nonzero SHAKE or WOTS status is thrown unchanged through the result-only SPHINCS API |
| **Pure Forth** | No assembly; checked accelerator access is through `sha3.f` and the BIOS `WOTS-CHAIN` word |
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

The earlier software-chain measurements no longer describe this
implementation. Each `_SPX-CHAIN` request now performs one checked 64-byte
context transaction and lets the production sequencer execute all zero to
fifteen steps. New key-generation, signing, and verification measurements
must come from the qualified checked-interface build; no speedup or wall-time
claim is inferred from the interface cutover alone.

The "s" (small) variant intentionally trades signing speed for its 7,856-byte
signature. The WOTS sequencer changes chain execution cost, not the FIPS 205
parameter set or signature format.

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
| `_SPX-ADRS-WOTS-PK!` | `( -- )` | Select WOTS_PK while retaining keypair and zeroing its chain/hash padding words |
| `_SPX-WOTS-CONTEXT!` | `( src -- )` | Build `PK.seed[16] || ADRS[32] || node[16]` in the caller-owned 64-byte workspace |
| `_SPX-CHAIN` | `( src start steps dst -- )` | Checked WOTS+ adapter; zero steps are the identity result and nonzero status is thrown unchanged |
| `_SPX-WOTS-PK-GEN` | `( idx dst -- )` | Generate WOTS+ public key for leaf |
| `_SPX-XMSS-NODE` | `( start height dst -- )` | Compute XMSS subtree root via treehash |
| `_SPX-FORS-SIGN` | `( sig-out -- )` | FORS signing (k trees) |
| `_SPX-FORS-PK-FROM-SIG` | `( sig-in dst -- )` | Reconstruct FORS pk from signature |
| `_SPX-HT-SIGN` | `( msg tree leaf sig-out -- )` | Full hypertree signing |
| `_SPX-HT-VERIFY` | `( msg tree leaf sig-in root -- flag )` | Full hypertree verification |

### Hash Functions

All non-chain hash operations use the checked segmented SHAKE-256 surface:

- **T₁** — `PRF(PK.seed, ADRS, input)` → n bytes
- **T₂** — `Hash(PK.seed, ADRS, left ∥ right)` → n bytes (Merkle node)
- **T_len** — `Hash(PK.seed, ADRS, len×n bytes)` → n bytes (WOTS+ pk compress)
- **PRF** — `PRF(PK.seed, ADRS, SK.seed)` → n bytes (secret derivation)
- **H_msg** — `Hash(R, PK.seed, PK.root, M)` → message digest (30 bytes)

WOTS chain iteration instead passes the exact 64-byte
`PK.seed || ADRS || node` context to `WOTS-CHAIN`. The sequencer replaces
ADRS bytes 28 through 31 with each big-endian hash-step index and returns the
final 16-byte node. Those mutations apply to the copied context, not the
module's source ADRS. Focused tests compare `_SPX-CHAIN` directly with
externally generated SHAKE-256 known answers, including zero-step identity and
in-place source/destination cases. No private software-chain fallback remains.

### Important Implementation Notes

- `DO..LOOP` uses VARIABLEs (not `>R`/`R@`) because the return stack
  holds the loop index — `R@` inside a loop returns the loop counter,
  not a saved value.
- Nested `DO..LOOP` uses `I` (inner) and `J` (outer) for loop indices.
- All parameter passing to internal words uses module-level VARIABLEs
  (e.g., `_SPX-PK-SEED`, `_SPX-SK-SEED`), not stack parameters.
- `_SPX-CHAIN` stores its four arguments before constructing the context; it
  does not place saved parameters on the return stack of a caller's loop.
- Both WOTS public-key compression paths use `_SPX-ADRS-WOTS-PK!`; they retain
  the layer, tree, and keypair address fields but explicitly zero bytes 24
  through 31 instead of inheriting the preceding chain/hash state.
- The checked BIOS word stages its result and clears the device before
  publication. Source/destination identity is therefore supported, and a
  failed request leaves all 16 destination bytes unchanged. The caller-owned
  context is wiped before a returned status is propagated.
- Accelerator status values use the common checked vocabulary: `0` succeeds;
  `1` unsupported, `2` state/owner, `3` range, `4` protected, `5` timeout,
  and `6` hardware/protocol are thrown unchanged by this result-only API.

### Bug Fixes (Phase 6.6 Hardening)

1. **HT-SIGN buffer clobber** — `_SPX-XMSS-SIGN` internally overwrites
   `_SPX-NODE`, which was also used to pass msg to `_SPX-XMSS-ROOT`.
   Fix: save msg to dedicated `_SPX-HT-MSG` buffer before signing.
2. **HT-VERIFY wrong stack pick** — `OVER` picked `_SPX-NODE` instead
   of `sig-in` in the layer loop.  Fix: changed to `2 PICK`.
3. **XMSS tree-hash ADRS residual** — When TYPE switches to TREE for
   Merkle combines, the KP field (bytes 20-23) retained stale values
   from WOTS operations, causing hash mismatches between keygen and
   verify.  Fix: added `0 _SPX-ADRS-KP!` after setting TREE type.
4. **FORS-PK-FROM-SIG stack underflow** — Inner loop used `OVER`/`DUP`
   to reach `sig-in`, but after consuming stack items only 1 remained.
   `OVER` needs 2 items, so it read stale memory.  Fix: save `sig-in`
   to `_SPX-V-FPKSIG` variable at entry, use `_SPX-V-FPKSIG @`.
5. **WOTS-SK-I spurious DUP** — Stack leak in secret key derivation.
   Fix: removed the extra `DUP`.
6. **WOTS_PK residual address words** — Public-key compression inherited the
   preceding WOTS_HASH chain/hash words. Fix: both compression paths now
   select WOTS_PK and explicitly zero its trailing padding words.

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
