# akashic-consensus — Consensus Mechanism

Four leader-election modes (PoW, PoA, PoS, PoSA) with an orthogonal STARK
validity-proof overlay.  Unified dispatch via `CON-SEAL` / `CON-CHECK`.

```forth
REQUIRE consensus.f
```

`PROVIDED akashic-consensus` — depends on `akashic-block`, `akashic-ed25519`,
`akashic-sha3`, `akashic-guard`, `akashic-random`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Mode Selection](#mode-selection)
- [Signing Context](#signing-context)
- [Signatory Hash](#signatory-hash)
- [Proof of Work](#proof-of-work)
- [Proof of Authority](#proof-of-authority)
- [Proof of Stake](#proof-of-stake)
- [Anti-Grinding](#anti-grinding)
- [Proof of Staked Authority](#proof-of-staked-authority)
- [Unified Dispatch](#unified-dispatch)
- [STARK Overlay](#stark-overlay)
- [Constants](#constants)
- [Usage Examples](#usage-examples)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Four modes** | PoW (mode 0), PoA (mode 1), PoS (mode 2), PoSA (mode 3) — switchable at runtime |
| **Unified signing** | `CON-SET-KEYS ( priv pub -- )` stores node keys once; `CON-SEAL` uses them for all modes |
| **Two hashes per block** | Signatory hash (header with empty proof) for signing; block hash (with proof) for chain linkage |
| **Anti-grinding** | PoS/PoSA leader seed uses 2-block lookback (`block[height-2].hash`) to prevent producer manipulation |
| **Callback patching** | `CON-CHECK` auto-wired into `BLK-VERIFY` via `_BLK-CON-CHECK-XT` |
| **Extension dispatch** | Staking tx handler wired into `state.f` via `_ST-TX-EXT-XT` |
| **STARK-ready** | Orthogonal overlay stubs (`_CON-STARK-*-XT`) for Stage C.  Multi-column backend (`stark.f` v2.5) is complete. |
| **Concurrency-safe** | Public API wrapped with `WITH-GUARD` |

---

## Mode Selection

### CON-MODE!

```forth
CON-MODE!  ( mode -- )
```

Set the active consensus mode.  Valid values: `CON-POW` (0),
`CON-POA` (1), `CON-POS` (2), `CON-POSA` (3).

### CON-MODE@

```forth
CON-MODE@  ( -- mode )
```

Get the active consensus mode.

### CON-STARK!

```forth
CON-STARK!  ( flag -- )
```

Enable (TRUE) or disable (FALSE) the STARK validity-proof overlay.

### CON-STARK?

```forth
CON-STARK?  ( -- flag )
```

Query whether the STARK overlay is active.

---

## Signing Context

### CON-SET-KEYS

```forth
CON-SET-KEYS  ( priv pub -- )
```

Store the node's Ed25519 signing keys.  `priv` is 64 bytes (Ed25519
expanded private key), `pub` is 32 bytes.  Call once at node startup.

`CON-SEAL` uses these stored keys for PoA, PoS, and PoSA modes,
eliminating the need to pass `(priv pub)` on every seal call.  PoW
does not require keys.

Concurrency-safe (wrapped with `WITH-GUARD`).

---

## Signatory Hash

### CON-SIG-HASH

```forth
CON-SIG-HASH  ( blk hash -- )
```

Hash the block header with proof_len temporarily set to 0.  This is
the message that PoA and PoS signers sign, avoiding the circular
dependency where the signature is part of the proof which is part of
the hash.

---

## Proof of Work

> **Testing / bootstrap only.**  PoW with 1-block max reorg provides
> no meaningful Sybil resistance on a small network of identical hardware.
> Use PoA or PoSA for production deployments.  The compile-time flag
> `_CON-POW-TESTING-ONLY` is set to TRUE.

PoW stores a u64 nonce (LE) in the block's proof field (proof_len = 8).
Mining increments the nonce until `SHA3-256(CBOR-header)` interpreted as
a big-endian u64 is less than the target.

### CON-POW-MINE

```forth
CON-POW-MINE  ( blk -- )
```

Brute-force nonce search.  Blocks until a valid nonce is found.

### CON-POW-CHECK

```forth
CON-POW-CHECK  ( blk -- flag )
```

Verify the nonce in the proof produces a hash below the target.

### CON-POW-TARGET!

```forth
CON-POW-TARGET!  ( target -- )
```

Set the PoW difficulty target.  Larger values = easier.

### CON-POW-TARGET@

```forth
CON-POW-TARGET@  ( -- target )
```

Get the current PoW difficulty target.

### CON-POW-ADJUST

```forth
CON-POW-ADJUST  ( elapsed expected -- )
```

Adjust difficulty: `new = old × expected / elapsed`, clamped to
`[old/2, old×2]` to prevent wild swings.

---

## Proof of Authority

PoA uses a table of up to 256 authorized Ed25519 public keys.
Proof format: `[0..31]` signer pubkey ∥ `[32..95]` Ed25519 signature
(proof_len = 96).

### CON-POA-ADD

```forth
CON-POA-ADD  ( pubkey -- )
```

Add a 32-byte public key to the authority table.  Silently ignored
if the table is full (256).

### CON-POA-REMOVE

```forth
CON-POA-REMOVE  ( pubkey -- flag )
```

Remove a public key from the authority table.  Returns TRUE if found.

### CON-POA-SIGN

```forth
CON-POA-SIGN  ( blk priv pub -- )
```

Sign a block as an authorized signer:
1. Compute signatory hash
2. `ED25519-SIGN(hash, 32, priv, pub, sig)`
3. Store pubkey + sig in proof field

### CON-POA-CHECK

```forth
CON-POA-CHECK  ( blk -- flag )
```

Verify: signer is in the authority table AND the signature is valid.

### CON-POA-COUNT

```forth
CON-POA-COUNT  ( -- n )
```

Number of registered authorities.

---

## Proof of Stake

PoS builds on the staking extension in `state.f` and provides
epoch-based validator set management, deterministic leader election,
and block signing/verification.

### Staking Transactions

Two transaction types are dispatched via the `state.f` extension hook:

| Type | `data[0]` | Constant | Effect |
|---|---|---|---|
| Stake | 3 | `TX-STAKE` | Move `amount` from balance → staked-amt |
| Unstake | 4 | `TX-UNSTAKE` | Move all staked back to balance after lock period |

**Lock period:** `CON-POS-LOCK-PERIOD` (64 blocks).  Unstaking is
rejected if `current_height < last_block + lock_period`.

### CON-POS-EPOCH

```forth
CON-POS-EPOCH  ( -- )
```

Rebuild the validator set by scanning all state accounts.  An account
qualifies if `staked-amount ≥ CON-POS-MIN-STAKE` (100) and
`unstake-height = 0`.  Validators are sorted by stake descending.

Called lazily — `_CON-POS-ENSURE-EPOCH` triggers a rebuild at epoch
boundaries (every `CON-POS-EPOCH-LEN` = 32 blocks).

### CON-POS-LEADER

```forth
CON-POS-LEADER  ( blk -- addr )
```

Deterministic leader selection for a given block:
1. `seed = SHA3-256(anchor_hash || height)` where `anchor_hash = block[height-2].hash` (anti-grinding; see [Anti-Grinding](#anti-grinding))
2. `target = LE_u64(seed[0..7]) MOD total_stake`
3. Walk cumulative stakes to find the selected validator

Returns the 32-byte validator address (account address, not raw pubkey).

### CON-POS-SIGN

```forth
CON-POS-SIGN  ( blk priv pub -- )
```

Sign a block as the elected PoS leader.  Identical proof layout to
PoA (pubkey + Ed25519 sig), so callers use the same format.

### CON-POS-CHECK

```forth
CON-POS-CHECK  ( blk -- flag )
```

Verify a PoS block:
1. Extract signer pubkey from proof
2. Compute expected leader from prev_hash + height
3. Hash signer pubkey → address; compare with expected leader
4. Verify Ed25519 signature

### Validator Queries

```forth
CON-POS-VALIDATORS   ( -- count )   \ number of validators
CON-POS-TOTAL-STAKE  ( -- total )   \ sum of all stakes
CON-POS-VAL-KEY      ( idx -- addr ) \ validator pubkey by index
CON-POS-VAL-STAKE    ( idx -- stake ) \ validator stake by index
```

---

## Anti-Grinding

PoS and PoSA leader election uses a **2-block lookback** seed to
prevent the current block producer from influencing the next leader
selection.

```
seed = SHA3-256( block[height-2].hash || height )
```

The block at `height-2` is already finalized when the `height-1`
producer is elected, so manipulating transaction selection cannot
change the seed.  For `height < 2` (genesis and block 1), the seed
falls back to `prev_hash` since those blocks are fixed.

The anchor hash is computed by `_CON-ANCHOR-HASH!` and shared by
both `CON-POS-LEADER` and `CON-POSA-ELECT`.

---

## Proof of Staked Authority

PoSA (Mode 3) is the **planned production consensus mode**.  It combines
PoA's permissioned authority set with PoS's stake requirement:

- Authority must be in the PoA key table (`CON-POA-ADD`)
- Authority must have stake >= `CON-POS-MIN-STAKE`
- Leader elected by stake-weighted selection among qualified validators
- Proof format: identical to PoA/PoS (pubkey[32] + sig[64], 96 bytes)

The **staked-authority set** is the intersection of the PoA authority
table and the staked validator set.  It is rebuilt on each election by
`_CON-SA-BUILD`, which hashes each PoA pubkey to an address and matches
against the PoS validator keys.

### CON-POSA-ELECT

```forth
CON-POSA-ELECT  ( blk -- addr )
```

Compute the expected leader for a PoSA block:
1. Ensure the PoS epoch is current, rebuild staked-authority set
2. Compute anti-grinding seed (`anchor_hash || height`)
3. `target = LE_u64(SHA3-256(seed)[0..7]) MOD total_staked_authority_stake`
4. Walk cumulative stakes of staked authorities to find the leader

Returns the 32-byte validator address.  If no staked authorities
exist, returns a junk address (will fail verification).

### CON-POSA-CHECK

```forth
CON-POSA-CHECK  ( blk -- flag )
```

Verify a PoSA block (6-step check):
1. `proof_len` must be 96
2. Extract signer pubkey from `proof[0..31]`
3. Compute expected leader via `CON-POSA-ELECT`
4. Hash signer pubkey to address; compare with expected leader
5. Verify signer is in the PoA authority table
6. Verify Ed25519 signature against signatory hash

### CON-POSA-COUNT

```forth
CON-POSA-COUNT  ( -- n )
```

Number of staked authorities (intersection of PoA table and staked
validators).  Updated by `_CON-SA-BUILD` during election.

---

## Unified Dispatch

### CON-SEAL

```forth
CON-SEAL  ( blk -- )
```

Produce a consensus proof based on the current mode.  Requires
`CON-SET-KEYS` to have been called for PoA, PoS, and PoSA modes.

- **PoW:** Calls `CON-POW-MINE`
- **PoA:** Signs using stored keys via `CON-POA-SIGN`
- **PoS:** Calls `_CON-POS-SEAL-XT` (signs using stored keys)
- **PoSA:** Calls `_CON-POSA-SEAL-XT` (signs using stored keys)

If the STARK overlay is enabled, also calls the STARK prover.

### CON-CHECK

```forth
CON-CHECK  ( blk -- flag )
```

Validate a block's consensus proof based on the current mode:
- **PoW:** Calls `CON-POW-CHECK`
- **PoA:** Calls `CON-POA-CHECK`
- **PoS:** Calls `CON-POS-CHECK`
- **PoSA:** Calls `CON-POSA-CHECK`

If the STARK overlay is enabled, also verifies the STARK proof.

This word is automatically wired into `BLK-VERIFY` at load time.

---

## STARK Overlay

Stage C (not yet implemented).  The overlay is orthogonal to the
leader-election mode — when enabled, every block carries an additional
validity proof.

The multi-column trace backend (`stark.f` v2.5, Phase 4.5) is now
complete, making Stage C wiring possible.

Stubs are in place:
- `_CON-STARK-PROVE-XT` — called by `CON-SEAL` (currently a no-op)
- `_CON-STARK-CHECK-XT` — called by `CON-CHECK` (currently returns TRUE)

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `CON-POW` | 0 | Proof of Work mode (testing/bootstrap only) |
| `CON-POA` | 1 | Proof of Authority mode |
| `CON-POS` | 2 | Proof of Stake mode |
| `CON-POSA` | 3 | Proof of Staked Authority mode (production) |
| `CON-POS-EPOCH-LEN` | 32 | Blocks per epoch |
| `CON-POS-MIN-STAKE` | 100 | Minimum stake to qualify as validator |
| `CON-POS-LOCK-PERIOD` | 64 | Blocks before unstake completes |

---

## Usage Examples

### PoW — Mine and Verify

```forth
CON-POW CON-MODE!

\ Set easy target for testing
0x00FFFFFFFFFFFFFF CON-POW-TARGET!

\ Mine block
my-block CON-POW-MINE

\ Verify
my-block CON-POW-CHECK   \ -> TRUE
```

### PoA — Authority Signing

```forth
CON-POA CON-MODE!

\ Register authority and store signing keys
my-pubkey CON-POA-ADD
my-privkey my-pubkey CON-SET-KEYS

\ Seal block via unified dispatch (uses stored keys)
my-block CON-SEAL

\ Verify
my-block CON-CHECK   \ -> TRUE
```

### PoS — Staking and Validation

```forth
CON-POS CON-MODE!
my-privkey my-pubkey CON-SET-KEYS

\ (After staking transactions have been applied via ST-APPLY-TX)

\ Rebuild validator set
CON-POS-EPOCH

\ Get expected leader for a block
my-block CON-POS-LEADER   \ -> validator address

\ Seal as leader via unified dispatch
my-block CON-SEAL

\ Verify
my-block CON-CHECK   \ -> TRUE
```

### PoSA — Proof of Staked Authority (Production)

```forth
CON-POSA CON-MODE!
my-privkey my-pubkey CON-SET-KEYS

\ Register authority + stake
my-pubkey CON-POA-ADD
\ (Stake via ST-APPLY-TX with TX-STAKE type)

\ At election time
my-block CON-POSA-ELECT    \ -> expected leader address

\ Seal block (uses stored keys)
my-block CON-SEAL

\ Verify — checks authority table + stake + signature
my-block CON-CHECK         \ -> TRUE

\ Query staked authority count
CON-POSA-COUNT             \ -> n
```

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `CON-MODE!` | `( mode -- )` | Set consensus mode |
| `CON-MODE@` | `( -- mode )` | Get consensus mode |
| `CON-STARK!` | `( flag -- )` | Enable/disable STARK overlay |
| `CON-STARK?` | `( -- flag )` | Query STARK overlay |
| `CON-SET-KEYS` | `( priv pub -- )` | Store node signing keys |
| `CON-SIG-HASH` | `( blk hash -- )` | Signatory hash |
| `CON-SEAL` | `( blk -- )` | Unified seal dispatch |
| `CON-CHECK` | `( blk -- flag )` | Unified check dispatch |
| `CON-POW-MINE` | `( blk -- )` | PoW nonce search |
| `CON-POW-CHECK` | `( blk -- flag )` | PoW verify |
| `CON-POW-TARGET!` | `( target -- )` | Set PoW difficulty |
| `CON-POW-TARGET@` | `( -- target )` | Get PoW difficulty |
| `CON-POW-ADJUST` | `( elapsed expected -- )` | Adjust difficulty |
| `CON-POA-ADD` | `( pubkey -- )` | Add authority |
| `CON-POA-REMOVE` | `( pubkey -- flag )` | Remove authority |
| `CON-POA-SIGN` | `( blk priv pub -- )` | Sign as authority |
| `CON-POA-CHECK` | `( blk -- flag )` | Verify authority sig |
| `CON-POA-COUNT` | `( -- n )` | Number of authorities |
| `CON-POS-EPOCH` | `( -- )` | Rebuild validator set |
| `CON-POS-LEADER` | `( blk -- addr )` | Get expected leader |
| `CON-POS-SIGN` | `( blk priv pub -- )` | Sign as PoS leader |
| `CON-POS-CHECK` | `( blk -- flag )` | Verify PoS block |
| `CON-POS-VALIDATORS` | `( -- count )` | Validator count |
| `CON-POS-TOTAL-STAKE` | `( -- total )` | Total staked |
| `CON-POS-VAL-KEY` | `( idx -- addr )` | Validator pubkey |
| `CON-POS-VAL-STAKE` | `( idx -- stake )` | Validator stake |
| `CON-POSA-ELECT` | `( blk -- addr )` | PoSA leader election |
| `CON-POSA-CHECK` | `( blk -- flag )` | Verify PoSA block |
| `CON-POSA-COUNT` | `( -- n )` | Staked authority count |
