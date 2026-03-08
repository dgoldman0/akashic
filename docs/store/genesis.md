# akashic-genesis — Genesis Block Configuration

CBOR-encoded chain configuration stored in block 0's data field.
Parameterizes the consensus module and initial state at chain
creation time.

```forth
REQUIRE genesis.f
```

`PROVIDED akashic-genesis` — depends on `akashic-block`, `akashic-state`,
`akashic-consensus`, `akashic-cbor`, `akashic-sha3`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [CBOR Layout](#cbor-layout)
- [Chain ID](#chain-id)
- [GEN-CREATE](#gen-create)
- [GEN-LOAD](#gen-load)
- [GEN-HASH](#gen-hash)
- [Constants](#constants)
- [Usage Examples](#usage-examples)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Protocol-enforced config** | Consensus mode is set by genesis, not a runtime variable — all nodes on a chain agree |
| **Self-describing** | CBOR map with string keys — forward-compatible with new fields |
| **Single source of truth** | `GEN-LOAD` configures both `consensus.f` and `state.f` from the genesis block |
| **Chain identity** | Genesis block hash = chain identifier; nodes with different genesis hashes are on different networks |
| **Not reentrant** | Uses module-level buffers (`_GEN-BUF`, `_GEN-TKEY`) — single-threaded |

---

## CBOR Layout

The genesis block (height 0) carries a CBOR map with 8 entries in its
transaction data area:

| Key | CBOR Type | Description |
|-----|-----------|-------------|
| `"chain_id"` | uint | Chain identifier — distinguishes networks |
| `"con_mode"` | uint | Consensus mode: 0=PoW, 1=PoA, 2=PoS, 3=PoSA |
| `"stark"` | uint | STARK overlay: 0=off, 1=on |
| `"epoch_len"` | uint | PoS/PoSA epoch length in blocks |
| `"min_stake"` | uint | Minimum stake to qualify as validator |
| `"lock_period"` | uint | Unstake lock period in blocks |
| `"authorities"` | array[bstr] | PoA/PoSA authority pubkeys (32 bytes each) |
| `"balances"` | array[array[bstr, uint]] | Initial account (address, amount) pairs |

---

## Chain ID

### GEN-CHAIN-ID!

```forth
GEN-CHAIN-ID!  ( n -- )
```

Set the chain ID.  Default is 1.

### GEN-CHAIN-ID@

```forth
GEN-CHAIN-ID@  ( -- n )
```

Get the current chain ID.

---

## GEN-CREATE

```forth
GEN-CREATE  ( -- )
```

Encode the current chain configuration as a CBOR genesis payload.
Reads from:
- `GEN-CHAIN-ID@` for chain ID
- `CON-MODE@` for consensus mode
- `CON-STARK?` for STARK overlay flag
- `CON-POS-EPOCH-LEN`, `CON-POS-MIN-STAKE`, `CON-POS-LOCK-PERIOD` for PoS constants
- `CON-POA-COUNT` and the PoA key table for authority pubkeys
- `ST-COUNT` and the state table for initial balances

Result is stored in an internal 4 KB buffer.  Retrieve with
`GEN-RESULT ( -- addr len )`.

---

## GEN-LOAD

```forth
GEN-LOAD  ( genesis-data len -- flag )
```

Decode a CBOR genesis payload and configure the chain.  Called once
at node startup.

Actions:
1. Parse the CBOR map (expects 8 entries)
2. Set chain ID via `_GEN-CHAIN-ID`
3. Set consensus mode via `CON-MODE!`
4. Configure STARK overlay via `CON-STARK!`
5. Validate epoch length against compiled constant
6. Set lock period via `_ST-LOCK-PERIOD`
7. Load authority pubkeys into the PoA table via `CON-POA-ADD`
8. Create initial accounts with balances via `ST-CREATE`

Returns TRUE (-1) on success, FALSE (0) on decode error (bad map
size, invalid key lengths, or account creation failure).

---

## GEN-HASH

```forth
GEN-HASH  ( hash -- )
```

Compute the genesis block hash.  Initializes a temporary block struct
at height 0 with zeroed prev_hash and timestamp, then calls `BLK-HASH`.
The resulting 32-byte hash is written to `hash`.

The genesis hash serves as the chain identity — nodes on different
chains will have different genesis hashes.

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `_GEN-BUF-SIZE` | 4096 | CBOR encoding buffer size (bytes) |

---

## Usage Examples

### Create a PoSA Genesis

```forth
\ Configure chain parameters
42 GEN-CHAIN-ID!
CON-POSA CON-MODE!
FALSE CON-STARK!

\ Add authorities
auth1-pubkey CON-POA-ADD
auth2-pubkey CON-POA-ADD

\ Create initial accounts with balances
addr1 1000 ST-CREATE DROP
addr2 2000 ST-CREATE DROP

\ Encode genesis
GEN-CREATE

\ Get the encoded payload
GEN-RESULT   \ -> addr len
```

### Load Genesis at Startup

```forth
\ Read genesis block data from storage
genesis-block-data genesis-data-len

\ Decode and configure chain
GEN-LOAD   \ -> flag (-1 = success, 0 = error)

\ Chain ID is now set
GEN-CHAIN-ID@   \ -> 42
```

### Compute Chain Identity

```forth
CREATE my-genesis-hash 32 ALLOT
my-genesis-hash GEN-HASH

\ my-genesis-hash now holds the 32-byte chain identifier
```

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `GEN-CHAIN-ID!` | `( n -- )` | Set chain ID |
| `GEN-CHAIN-ID@` | `( -- n )` | Get chain ID |
| `GEN-CREATE` | `( -- )` | Encode genesis from current config |
| `GEN-RESULT` | `( -- addr len )` | Get encoded genesis payload |
| `GEN-LOAD` | `( data len -- flag )` | Decode genesis, configure chain |
| `GEN-HASH` | `( hash -- )` | Compute genesis block hash |
