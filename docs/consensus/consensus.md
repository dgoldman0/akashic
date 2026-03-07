# akashic-consensus — Consensus Mechanism

Three leader-election modes (PoW, PoA, PoS) with an orthogonal STARK
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
- [Signatory Hash](#signatory-hash)
- [Proof of Work](#proof-of-work)
- [Proof of Authority](#proof-of-authority)
- [Proof of Stake](#proof-of-stake)
- [Unified Dispatch](#unified-dispatch)
- [STARK Overlay](#stark-overlay)
- [Constants](#constants)
- [Usage Examples](#usage-examples)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Three modes** | PoW (mode 0), PoA (mode 1), PoS (mode 2) — switchable at runtime |
| **Two hashes per block** | Signatory hash (header with empty proof) for signing; block hash (with proof) for chain linkage |
| **Callback patching** | `CON-CHECK` auto-wired into `BLK-VERIFY` via `_BLK-CON-CHECK-XT` |
| **Extension dispatch** | Staking tx handler wired into `state.f` via `_ST-TX-EXT-XT` |
| **STARK-ready** | Orthogonal overlay stubs (`_CON-STARK-*-XT`) for Stage C |
| **Concurrency-safe** | Public API wrapped with `WITH-GUARD` |

---

## Mode Selection

### CON-MODE!

```forth
CON-MODE!  ( mode -- )
```

Set the active consensus mode.  Valid values: `CON-POW` (0),
`CON-POA` (1), `CON-POS` (2).

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
1. `seed = SHA3-256(prev_hash ∥ height)`
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

## Unified Dispatch

### CON-SEAL

```forth
CON-SEAL  ( blk -- )
```

Produce a consensus proof based on the current mode:
- **PoW:** Calls `CON-POW-MINE`
- **PoA:** No-op (caller must use `CON-POA-SIGN` directly — needs priv+pub)
- **PoS:** Calls `_CON-POS-SEAL-XT` (caller should use `CON-POS-SIGN` directly)

If the STARK overlay is enabled, also calls the STARK prover.

### CON-CHECK

```forth
CON-CHECK  ( blk -- flag )
```

Validate a block's consensus proof based on the current mode:
- **PoW:** Calls `CON-POW-CHECK`
- **PoA:** Calls `CON-POA-CHECK`
- **PoS:** Calls `CON-POS-CHECK`

If the STARK overlay is enabled, also verifies the STARK proof.

This word is automatically wired into `BLK-VERIFY` at load time.

---

## STARK Overlay

Stage C (not yet implemented).  The overlay is orthogonal to the
leader-election mode — when enabled, every block carries an additional
validity proof.

Stubs are in place:
- `_CON-STARK-PROVE-XT` — called by `CON-SEAL` (currently a no-op)
- `_CON-STARK-CHECK-XT` — called by `CON-CHECK` (currently returns TRUE)

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `CON-POW` | 0 | Proof of Work mode |
| `CON-POA` | 1 | Proof of Authority mode |
| `CON-POS` | 2 | Proof of Stake mode |
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

\ Register authority
my-pubkey CON-POA-ADD

\ Sign block
my-block my-privkey my-pubkey CON-POA-SIGN

\ Verify via unified dispatch
my-block CON-CHECK   \ -> TRUE
```

### PoS — Staking and Validation

```forth
CON-POS CON-MODE!

\ (After staking transactions have been applied via ST-APPLY-TX)

\ Rebuild validator set
CON-POS-EPOCH

\ Get expected leader for a block
my-block CON-POS-LEADER   \ -> validator address

\ Sign as leader
my-block my-privkey my-pubkey CON-POS-SIGN

\ Verify
my-block CON-CHECK   \ -> TRUE
```

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `CON-MODE!` | `( mode -- )` | Set consensus mode |
| `CON-MODE@` | `( -- mode )` | Get consensus mode |
| `CON-STARK!` | `( flag -- )` | Enable/disable STARK overlay |
| `CON-STARK?` | `( -- flag )` | Query STARK overlay |
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
