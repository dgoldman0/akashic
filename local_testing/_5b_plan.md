# Phase 4.5 + 5b — Combined Build Plan

## Overview

Two interleaved workstreams, done in order:

1. **Phase 4.5 — Multi-column STARK traces** (stark.f extension)
2. **Phase 5b — Consensus hardening** (genesis.f, anti-grinding,
   CON-SET-KEYS, PoW dev label, STARK overlay wiring)

Phase 4.5 is a prerequisite for 5b's STARK overlay.  Both are
prerequisites for Phase 6 (node infrastructure).

### Pre-existing regressions to fix first

test_block.py and test_consensus.py fail with "SMT-DESTROY ?
(not found)" — their load orders don't include `smt.f`, which
state.f now depends on since Phase 3b.  Fix load orders before
any new development.

---

## Step 0 — Fix Test Load Orders

**Files:** `test_block.py`, `test_consensus.py`
**Change:** Add `SMT_F` to `LOAD_ORDER` (before `STATE_F`)
**Validation:** Both test suites pass again

---

## Step 1 — Multi-Column STARK Traces (Phase 4.5)

**File:** `akashic/math/stark.f` (extend, ~600 lines)
**Tests:** `test_stark.py` (extend, ~20 new tests → ~55 total)

### 1a. Data Structures

Replace single-polynomial storage with N-column arrays:

```forth
8 CONSTANT STARK-MAX-COLS
VARIABLE _SK-NCOLS               \ active column count (1..8)

\ Per-column trace polynomials (8 × NTT-POLY)
NTT-POLY _SK-TRACES0    NTT-POLY _SK-TRACES1
NTT-POLY _SK-TRACES2    NTT-POLY _SK-TRACES3
NTT-POLY _SK-TRACES4    NTT-POLY _SK-TRACES5
NTT-POLY _SK-TRACES6    NTT-POLY _SK-TRACES7
CREATE _SK-TRACES-TBL  64 ALLOT  \ 8 cells → base addresses

\ Per-column coefficient copies (for interpolation)
NTT-POLY _SK-TCOEFFS0   ... _SK-TCOEFFS7
CREATE _SK-TCOEFFS-TBL  64 ALLOT

\ Per-column coset eval buffers (8 × 1040 bytes)
CREATE _SK-CEVALS  8320 ALLOT    \ 8 × 1040

\ Cols array for AIR-EVAL-TRANS (8 cells)
CREATE _SK-COLS  64 ALLOT        \ was 8 ALLOT

\ Per-column Merkle trees
256 MERKLE-TREE _SK-MTRACES0  ... _SK-MTRACES7
CREATE _SK-MTRACES-TBL  64 ALLOT

\ Per-column Merkle roots → combined into trace root
CREATE _SK-TROOTS  256 ALLOT     \ 8 × 32 bytes
CREATE _SK-TROOT   32 ALLOT      \ combined trace root
```

Memory budget: 8 × (1024 + 1040 + 1024 + 16352) ≈ 155 KB.
Fits comfortably in 16 MB XMEM.

**Design note:** NTT-POLY is declared statically (not XMEM).
With 8 columns we need 24 NTT polys (traces + coeffs + 2 tmp).
Each is 1024 bytes.  Statically: 24 KB.  Fine.

### 1b. API Changes

```forth
: STARK-SET-COLS   ( n -- )
    DUP 1 < OVER STARK-MAX-COLS > OR IF DROP 1 THEN
    _SK-NCOLS ! ;

: STARK-TRACE!     ( val col idx -- )
    SWAP _SK-TRACES-TBL SWAP 8 * + @    \ get NTT-POLY for column
    NTT-COEFF! ;

: STARK-TRACE@     ( col idx -- val )
    SWAP _SK-TRACES-TBL SWAP 8 * + @
    NTT-COEFF@ ;

: STARK-TRACE-ZERO ( -- )
    _SK-NCOLS @ 0 DO
        I 8 * _SK-TRACES-TBL + @ NTT-POLY-ZERO
    LOOP ;
```

### 1c. STARK-INIT Extension

After domain parameter computation, populate lookup tables:

```forth
: STARK-INIT  ( -- )
    \ ... existing domain parameter setup ...
    1 _SK-NCOLS !                  \ default: 1 column
    \ Populate trace table
    _SK-TRACES0  _SK-TRACES-TBL      !
    _SK-TRACES1  _SK-TRACES-TBL  8 + !
    \ ... etc for all 8 ...
    \ Populate coeff table
    _SK-TCOEFFS0  _SK-TCOEFFS-TBL      !
    \ ... etc ...
    \ Populate Merkle table
    _SK-MTRACES0  _SK-MTRACES-TBL      !
    \ ... etc ...
    \ Set cols array (pointers to ceval buffers)
    _SK-NCOLS @ 0 DO
        _SK-CEVALS I 1040 * +  I 8 * _SK-COLS + !
    LOOP ;
```

### 1d. STARK-PROVE Multi-Column Pipeline

```
For each column c in 0 .. _SK-NCOLS-1:
  trace[c] → tcoeff[c] via NTT-INVERSE
  tcoeff[c] → ceval[c] via coset eval
  Copy ceval[c] with 4-entry wrap for AIR max-offset
  Merkle-commit tcoeff[c] → mtrace[c]
  Store root → troots[c*32]

Cols array: _SK-COLS[c] = &ceval[c]

Combined trace root = SHA3(troots[0] || troots[1] || ... || troots[N-1])
Store → _SK-TROOT

Fiat-Shamir: absorb _SK-TROOT → alpha, beta

Constraint quotient loop (UNCHANGED except AIR-EVAL-TRANS now
reads from N columns via the cols array — this already works
because stark-air.f uses cols[col_index]):
  For each coset point i:
    residual = AIR-EVAL-TRANS(air, _SK-COLS, i)
    quotient[i] = residual * alpha + boundary_quotient[i]

Denominator computation + batch inversion: UNCHANGED (operates
on the single quotient polynomial)

FRI folding: UNCHANGED (operates on the single quotient polynomial)
```

### 1e. STARK-VERIFY Multi-Column Pipeline

```
Re-derive Fiat-Shamir from combined trace root

For each column c:
  Re-build Merkle tree from committed coefficients
  Verify root matches troots[c]

Coset-evaluate all columns, set up cols array

Re-compute constraint quotient: AIR-EVAL-TRANS (multi-column)
Compare against committed quotient

FRI verification: UNCHANGED
```

### 1f. Backward Compatibility

The `_SK-TRACE` alias can remain for test compatibility:

```forth
: _SK-TRACE  _SK-TRACES0 ;  \ backward compat
```

But `STARK-TRACE!` and `STARK-TRACE@` now require the `col` arg.
Existing test code must be updated to pass `0` for single-column.

### 1g. Tests (test_stark.py additions)

| # | Test | Description |
|---|------|-------------|
| S1 | `test_multicol_2col_fib` | 2-column Fibonacci AIR: col0=a, col1=b, transition a'=b, b'=a+b. Prove + verify. |
| S2 | `test_multicol_2col_tamper` | Tamper col1 after prove → verify fails |
| S3 | `test_multicol_5col_transfer` | 5-column balance-transfer AIR. Prove + verify. |
| S4 | `test_multicol_5col_tamper_sender` | Tamper sender column → verify fails |
| S5 | `test_multicol_5col_tamper_recip` | Tamper recipient column → verify fails |
| S6 | `test_multicol_5col_bad_boundary` | Wrong boundary value → verify fails |
| S7 | `test_multicol_cols_array` | Verify _SK-COLS populated correctly for N cols |
| S8 | `test_multicol_combined_root` | Combined trace root = SHA3 of per-column roots |
| S9 | `test_multicol_identity_1col` | 1-column with STARK-SET-COLS 1 matches old behavior |
| S10 | `test_multicol_set_cols_clamp` | STARK-SET-COLS 0 → 1, STARK-SET-COLS 9 → 1 |
| S11-S13 | `test_existing_*_with_col0` | Port 3 existing tests to use new (val col idx) API |

---

## Step 2 — genesis.f (Phase 5b.1)

**File:** `akashic/store/genesis.f` (~120 lines)
**Tests:** `test_genesis.py` (~20 tests)
**Prefix:** `GEN-`
**Depends on:** cbor.f, block.f, state.f, consensus.f

### Data Structure

Genesis config is a CBOR map stored in block 0's data field.
The map uses DAG-CBOR canonical key order (sorted UTF-8).

```
Genesis Config CBOR Map:
  "authorities"  : [pubkey]    initial PoA signers (byte strings, 32 bytes each)
  "balances"     : {addr:u64}  initial account balances (32-byte key → unsigned int)
  "chain_id"     : u64         network discriminator
  "con_mode"     : u8          0=PoW, 1=PoA, 2=PoS, 3=PoSA
  "epoch_len"    : u64         blocks per epoch (PoS, default 32)
  "lock_period"  : u64         unstake lock blocks (PoS, default 64)
  "max_txs"      : u64         transactions per block (default 256)
  "min_stake"    : u64         minimum stake (PoS, default 100)
  "stark"        : bool        STARK overlay required?
```

### Builder Pattern

```forth
CREATE _GEN-BUF 4096 ALLOT       \ CBOR encoding buffer
VARIABLE _GEN-LEN

\ Builder state
VARIABLE _GEN-CHAIN-ID
VARIABLE _GEN-MODE
VARIABLE _GEN-STARK
VARIABLE _GEN-EPOCH-LEN
VARIABLE _GEN-MIN-STAKE
VARIABLE _GEN-LOCK-PERIOD
VARIABLE _GEN-MAX-TXS
VARIABLE _GEN-N-AUTH                \ authority count
CREATE _GEN-AUTH  1024 ALLOT       \ up to 32 authority pubkeys × 32 bytes
VARIABLE _GEN-N-BAL                \ initial balance count
CREATE _GEN-BAL   8192 ALLOT      \ up to 200 entries × (32+8)=40 bytes

: GEN-BEGIN        ( chain-id -- )   reset all builder state, set chain_id
: GEN-SET-MODE     ( mode -- )       0..3
: GEN-SET-STARK    ( flag -- )       TRUE/FALSE
: GEN-SET-EPOCH    ( n -- )          epoch length
: GEN-SET-STAKE    ( n -- )          min stake
: GEN-SET-LOCK     ( n -- )          lock period
: GEN-SET-MAX-TXS  ( n -- )          max txs per block
: GEN-ADD-AUTH     ( pubkey -- )      add authority pubkey (32 bytes)
: GEN-ADD-BALANCE  ( addr amount -- ) add initial balance (addr=32 bytes)
: GEN-CREATE       ( blk -- )        encode config → CBOR, build genesis block
```

### Loader

```forth
: GEN-LOAD  ( blk -- flag )
    \ Extract CBOR data from block 0
    \ Decode each field, set corresponding CON-* and ST-* globals:
    \   CON-MODE, CON-STARK?, CON-POS-EPOCH-LEN, CON-POS-MIN-STAKE,
    \   _ST-LOCK-PERIOD
    \ Apply initial balances via ST-INIT-ACCOUNT
    \ Apply initial authorities via CON-POA-ADD
    \ Return TRUE on success, FALSE on malformed config ;

: GEN-HASH     ( -- addr )    32-byte genesis block hash (= chain identity)
: GEN-CHAIN-ID ( -- id )      chain ID extracted from genesis
```

### GEN-CREATE Internals

```
1. BLK-INIT the genesis block
2. BLK-SET-HEIGHT 0
3. BLK-SET-PREV (32 zero bytes)
4. BLK-SET-TIME (configurable or 0)
5. Encode config as CBOR map → _GEN-BUF
6. Store CBOR in block proof field (≤128 bytes) or as first "tx"
   → Decision: store in proof field.  128 bytes is tight for CBOR
     with authorities.  Alternative: encode as a special tx.
   → Resolution: Use the proof field for small configs (no authorities
     or ≤ 2).  For configs with many authorities, encode as the
     block's single transaction (a special type-0 "genesis tx").
   → Simplest: always encode as first tx, type=TX-GENESIS (new type 5).
7. Apply initial balances to state
8. BLK-FINALIZE (computes state root)
```

**Decision: TX-GENESIS (type 5) in tx.f.**  The genesis block contains
one special transaction whose data field is the CBOR config.  This
avoids the 128-byte proof field limit and keeps the block structure
uniform.  `BLK-VERIFY` at height 0 skips normal tx validation and
instead calls `GEN-LOAD`.

### Tests

| # | Test | Description |
|---|------|-------------|
| G1 | `test_gen_create_pow` | Create genesis with PoW mode, verify block hash |
| G2 | `test_gen_create_poa` | Create genesis with 3 authorities |
| G3 | `test_gen_create_pos` | Create genesis with PoS params |
| G4 | `test_gen_load_roundtrip` | GEN-CREATE → GEN-LOAD → verify all globals match |
| G5 | `test_gen_balances` | Initial balances applied correctly |
| G6 | `test_gen_authorities` | CON-POA-CHECK works with loaded authorities |
| G7 | `test_gen_chain_id` | GEN-CHAIN-ID returns correct value |
| G8 | `test_gen_hash_deterministic` | Same config → same genesis hash |
| G9 | `test_gen_hash_differs` | Different chain_id → different genesis hash |
| G10 | `test_gen_stark_flag` | CON-STARK? set correctly from genesis |
| G11 | `test_gen_epoch_len` | CON-POS-EPOCH-LEN set correctly |
| G12 | `test_gen_bad_mode` | Invalid mode → GEN-LOAD returns FALSE |
| G13 | `test_gen_missing_field` | Incomplete CBOR → GEN-LOAD returns FALSE |

---

## Step 3 — Anti-Grinding (Phase 5b.2)

**File:** `akashic/consensus/consensus.f` (modify ~20 lines)
**Tests:** `test_consensus.py` (add ~5 tests)

### Change

Replace leader election seed in `CON-POS-LEADER`:

```forth
\ Current (grindable):
\   SHA3( prev_hash || height )

\ Fixed (2-block lookback):
\   SHA3( block[height-2].hash || height )
```

The `CHAIN-BLOCK@` word already exists in block.f to fetch recent
headers from the 64-block ring buffer.

```forth
: _CON-POS-SEED  ( height -- seed-addr )
    DUP 2 < IF
        \ height 0 or 1: use prev_hash directly (no 2-block lookback)
        DROP CHAIN-HEAD BLK-PREV-HASH@
        _CON-SEED-BUF 32 CMOVE
    ELSE
        DUP 2 - CHAIN-BLOCK@    ( height blk-2 )
        DUP 0= IF 2DROP _CON-SEED-BUF 32 0 FILL _CON-SEED-BUF EXIT THEN
        BLK-HASH _CON-SEED-BUF  \ hash of block at height-2
    THEN
    \ Append height
    _CON-SEED-BUF 32 + !        \ 8-byte height
    _CON-SEED-BUF 40 _CON-SEED-HASH SHA3-256-HASH
    _CON-SEED-HASH ;
```

### Tests

| # | Test | Description |
|---|------|-------------|
| AG1 | `test_anti_grind_seed_differs` | Changing txs in block H doesn't change seed for H+1 |
| AG2 | `test_anti_grind_2block_lookback` | Seed at height H uses block H-2 hash |
| AG3 | `test_anti_grind_height_0_1` | Heights 0 and 1 fall back gracefully |
| AG4 | `test_anti_grind_deterministic` | Same chain state → same seed |
| AG5 | `test_anti_grind_leader_stable` | Leader for slot H stable despite block H-1 variations |

---

## Step 4 — CON-SET-KEYS (Phase 5b.3)

**File:** `akashic/consensus/consensus.f` (modify ~30 lines)
**Tests:** `test_consensus.py` (add ~5 tests)

### Change

Add a signing context so CON-SEAL works uniformly:

```forth
CREATE _CON-SIGN-PRIV 64 ALLOT    \ Ed25519 private key
CREATE _CON-SIGN-PUB  32 ALLOT    \ Ed25519 public key
VARIABLE _CON-KEYS-SET             \ flag: keys loaded?

: CON-SET-KEYS  ( priv pub -- )
    _CON-SIGN-PUB 32 CMOVE
    _CON-SIGN-PRIV 64 CMOVE
    -1 _CON-KEYS-SET ! ;

: CON-KEYS-SET?  ( -- flag )  _CON-KEYS-SET @ ;
```

Then fix `CON-SEAL`:

```forth
: CON-SEAL  ( blk -- )
    CON-MODE @ CASE
        0 OF  CON-TARGET @ CON-POW-MINE  ENDOF
        1 OF  DUP _CON-SIGN-PRIV _CON-SIGN-PUB CON-POA-SIGN  ENDOF
        2 OF  DUP _CON-SIGN-PRIV _CON-SIGN-PUB CON-POS-SIGN  ENDOF
    ENDCASE
    CON-STARK? @ IF  CON-STARK-PROVE  THEN ;
```

### Tests

| # | Test | Description |
|---|------|-------------|
| CK1 | `test_con_set_keys` | Keys stored correctly |
| CK2 | `test_con_seal_poa` | CON-SEAL with PoA mode produces valid signature |
| CK3 | `test_con_seal_pos` | CON-SEAL with PoS mode produces valid signature |
| CK4 | `test_con_seal_pow` | CON-SEAL with PoW mode ignores keys |
| CK5 | `test_con_keys_set_flag` | CON-KEYS-SET? returns TRUE after CON-SET-KEYS |

---

## Step 5 — PoW Dev Label (Phase 5b.4)

**File:** `akashic/consensus/consensus.f` (minimal, ~5 lines)
**Tests:** `test_consensus.py` (add ~2 tests)

### Change

Rename/alias PoW words with DEV prefix and add a warning:

```forth
: CON-POW-DEV?  ( -- flag )  CON-MODE @ 0 = ;

\ At multi-node init (future node.f), if CON-POW-DEV? and peer count > 1:
\   emit warning "PoW mode is for development only"
```

No functional change — just documentation and a flag that node.f
can check.

### Tests

| # | Test | Description |
|---|------|-------------|
| PD1 | `test_pow_dev_flag` | CON-POW-DEV? true when mode=0 |
| PD2 | `test_pow_dev_flag_neg` | CON-POW-DEV? false when mode=1 or 2 |

---

## Step 6 — STARK Overlay Wiring (Phase 5b + 4.5)

**File:** `akashic/consensus/consensus.f` (modify ~80 lines)
**Tests:** `test_consensus.py` (add ~10 tests)
**Depends on:** Step 1 (multi-column stark.f), witness.f

### The STARK overlay connects three existing systems:

1. **witness.f** — knows which accounts were touched and their
   before/after values
2. **stark-air.f** — can describe the state-transition constraints
3. **stark.f** (multi-column) — can prove/verify the trace

### AIR Definition: Balance Conservation + Nonce Increment

5-column AIR, one row per transaction:

```
Column  Field            Description
  0     old_bal_sender   sender balance before tx
  1     amount           transfer amount
  2     new_bal_sender   old_bal_sender - amount
  3     old_bal_recip    recipient balance before tx
  4     new_bal_recip    old_bal_recip + amount
```

Transition constraints (applied to consecutive rows):
- `col2[i] = col0[i] - col1[i]`   (sender debit)
- `col4[i] = col3[i] + col1[i]`   (recipient credit)

Boundary constraints:
- `col0[0] = witness_entry[0].pre_balance_sender`
- etc., one per witness entry field at the corresponding row

```forth
: _CON-BUILD-AIR  ( -- air )
    5 AIR-BEGIN
    \ Sender debit: new_bal_sender = old_bal_sender - amount
    AIR-SUB  0 0  1 0  2 0  AIR-TRANS
    \ Recipient credit: new_bal_recip = old_bal_recip + amount
    AIR-ADD  3 0  1 0  4 0  AIR-TRANS
    \ Boundary constraints from witness entries
    WIT-COUNT 0 DO
        I WIT-ENTRY                        ( entry-addr )
        DUP 32 + @  0  I  ROT  AIR-BOUNDARY   \ col0[i] = pre_bal_sender
        DUP 48 + @  2  I  ROT  AIR-BOUNDARY   \ col2[i] = post_bal_sender
        \ ... similarly for cols 3, 4
        DROP
    LOOP
    AIR-END ;
```

### Trace Filling

```forth
: _CON-FILL-TRACE  ( -- )
    5 STARK-SET-COLS
    STARK-TRACE-ZERO
    WIT-COUNT 0 DO
        I WIT-ENTRY                        ( entry-addr )
        DUP 32 + @  0 I STARK-TRACE!       \ col0[i] = pre_bal_sender
        DUP 48 + @  2 I STARK-TRACE!       \ col2[i] = post_bal_sender
        \ Amount = pre_bal - post_bal (sender perspective)
        DUP 32 + @ OVER 48 + @ -  1 I STARK-TRACE!  \ col1[i] = amount
        \ Recipient pre/post from paired witness entry
        \ ... (details depend on witness entry pairing)
        DROP
    LOOP ;
```

### CON-STARK-PROVE / CON-STARK-CHECK

Replace the stubs:

```forth
: CON-STARK-PROVE  ( blk -- )
    DROP                          \ blk not needed — witness already populated
    STARK-INIT
    _CON-BUILD-AIR STARK-SET-AIR
    _CON-FILL-TRACE
    STARK-PROVE ;

: CON-STARK-CHECK  ( blk -- flag )
    DROP
    STARK-VERIFY ;
```

### Integration with Block Flow

In the block production path (`BLK-FINALIZE` or the node's
seal-block path):

```
1. WIT-BEGIN
2. For each tx: WIT-APPLY-TX
3. WIT-END
4. BLK-FINALIZE (stores state root, tx root)
5. CON-SEAL (includes PoX seal + STARK-PROVE if CON-STARK? true)
```

In the verification path (`BLK-VERIFY`):
```
1. Normal BLK-VERIFY checks (prev_hash, tx validity, state root)
2. If CON-STARK?: CON-STARK-CHECK (STARK-VERIFY)
```

### Tests

| # | Test | Description |
|---|------|-------------|
| SO1 | `test_stark_overlay_prove_verify` | 1-tx block: prove + verify → TRUE |
| SO2 | `test_stark_overlay_multi_tx` | 4-tx block: prove + verify → TRUE |
| SO3 | `test_stark_overlay_tampered_bal` | Tamper trace col → verify fails |
| SO4 | `test_stark_overlay_tampered_amt` | Tamper amount col → verify fails |
| SO5 | `test_stark_overlay_air_shape` | AIR has 5 columns, correct constraint count |
| SO6 | `test_stark_overlay_boundary` | Boundary values match witness entries |
| SO7 | `test_stark_overlay_empty_block` | Zero-tx block: prove + verify (degenerate case) |
| SO8 | `test_stark_overlay_con_seal` | Full CON-SEAL with PoA+STARK: signature + proof both valid |
| SO9 | `test_stark_overlay_con_check` | Full CON-CHECK with PoA+STARK: passes |
| SO10 | `test_stark_overlay_no_stark` | CON-STARK? FALSE: no proof generated, CON-CHECK still passes |

---

## Execution Order

```
Step 0:  Fix test_block.py / test_consensus.py load orders
         → run existing tests, confirm green

Step 1:  Multi-column STARK traces (stark.f)
         1a. Data structures (NTT polys, lookup tables)
         1b. API changes (STARK-SET-COLS, STARK-TRACE! w/ col)
         1c. STARK-INIT extension (populate tables)
         1d. STARK-PROVE multi-column pipeline
         1e. STARK-VERIFY multi-column pipeline
         1f. Backward compat alias
         1g. Tests
         → commit

Step 2:  genesis.f
         → commit

Step 3:  Anti-grinding fix
         → commit (can be combined with Step 4)

Step 4:  CON-SET-KEYS
         → commit

Step 5:  PoW dev label
         → commit (can be combined with Step 3+4)

Step 6:  STARK overlay wiring
         → commit

Final:   Full regression — all test suites pass
```

## Memory Budget

| Component | XMEM | RAM |
|-----------|------|-----|
| stark.f multi-col (8 cols) | 0 | ~155 KB (NTT polys + Merkle trees) |
| witness.f (existing) | ~332 KB | ~100 bytes |
| genesis.f | 0 | ~4 KB (CBOR buffer) |
| consensus.f additions | 0 | ~200 bytes |
| **Total new** | **0** | **~159 KB** |
| **Running total** | **~608 KB** | **~400 KB** |

Well within the 16 MB XMEM and 1 MB RAM budgets.

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| 16+ NTT polys exceeds static alloc | Build fails | Use XMEM for trace columns if needed; NTT-POLY may need XMEM variant |
| Single quotient polynomial insufficient for 5-col AIR | Prover correctness | The combinedresidual is a single polynomial — standard approach. If residual exceeds degree, split into multiple quotients. |
| Genesis CBOR > 128 bytes | Can't fit in proof field | Decided: use TX-GENESIS (type 5) instead of proof field |
| Witness entry pairing (sender/recip) | STARK trace row ordering | Each tx produces 2 witness entries → 2 trace rows. Or: paired columns (5-col). Design decision in Step 6 implementation. |
| FRI folding on combined constraint poly may have different degree bound | Soundness | Degree = (n_constraints × trace_degree) / zerofier_degree. Must verify FRI parameters still work. |

## Definition of Done

- [ ] test_block.py passes (load order fixed)
- [ ] test_consensus.py passes (load order fixed)
- [ ] Multi-column STARK: 2-col and 5-col AIRs prove+verify
- [ ] Multi-column STARK: tamper any column → verify fails
- [ ] genesis.f: create/load roundtrip, all globals set
- [ ] Anti-grinding: 2-block lookback, seed deterministic
- [ ] CON-SET-KEYS: CON-SEAL works for PoA and PoS
- [ ] PoW dev label documented
- [ ] STARK overlay: prove+verify through witness entries
- [ ] Full regression: ALL test suites green
