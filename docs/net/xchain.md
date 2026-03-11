# xchain.f — Cross-Chain Verification

**Module:** `akashic/net/xchain.f`  
**Prefix:** `XCH-`  
**Phase:** 7.5  
**Guard:** `_xch-guard` (all public words are guarded)

## Overview

Verify foreign chain block headers and account state without running a
foreign chain node.  Two verification levels:

1. **Block attestation** — verify Ed25519 consensus signature in foreign
   PoA/PoSA block headers.
2. **State inclusion** — stateless SMT proof verification against the
   last verified foreign state root.

Together these let chain A cryptographically verify chain B's account
state with no inter-validator trust beyond knowing the foreign chain's
authority public keys.

## Dependencies

| Module | Used for |
|--------|----------|
| `store/block.f` | `BLK-DECODE`, `BLK-HASH`, `BLK-INIT`, block struct layout |
| `math/ed25519.f` | `ED25519-VERIFY` for PoA/PoSA signature checking |
| `store/smt.f` | `SMT-VERIFY` for state proof verification |
| `math/sha3.f` | (transitive, via block/smt) |
| `concurrency/guard.f` | `GUARD`, `WITH-GUARD` for thread safety |

## Constants

| Name | Value | Description |
|------|-------|-------------|
| `XCH-MAX-CHAINS` | 16 | Max tracked foreign chains |
| `XCH-MAX-AUTH` | 8 | Max authority keys per chain |
| `XCH-OK` | 0 | Success |
| `XCH-ERR-FULL` | 1 | Registry full |
| `XCH-ERR-NOT-FOUND` | 2 | Chain-id not in registry |
| `XCH-ERR-DECODE` | 3 | CBOR block decode failed |
| `XCH-ERR-HEIGHT` | 4 | Height not sequential |
| `XCH-ERR-PREV` | 5 | prev_hash mismatch |
| `XCH-ERR-SIG` | 6 | Ed25519 signature invalid |
| `XCH-ERR-AUTH` | 7 | Signer not in authority table |
| `XCH-ERR-MODE` | 8 | Unsupported consensus mode |
| `XCH-ERR-IDX` | 9 | Authority index out of range |

## Registry Layout

Each foreign chain gets a 384-byte entry:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 8 | `chain_id` |
| 8 | 8 | `con_mode` (1=PoA, 3=PoSA) |
| 16 | 8 | `air_version` (future STARK compat) |
| 24 | 8 | `n_auth` (authority key count, 0–8) |
| 32 | 256 | `auth_keys` (8 × 32B Ed25519 pubkeys) |
| 288 | 8 | `last_height` |
| 296 | 32 | `last_hash` (block hash of last verified header) |
| 328 | 32 | `last_root` (state root of last verified header) |
| 360 | 8 | `flags` (bit0=active, bit1=has_header) |
| 368 | 16 | reserved |

Total registry: 16 × 384 = 6144 bytes (dictionary space).

## Public API

### Registry Management

#### `XCH-INIT ( -- )`
Zero the entire registry and reset chain count to 0.

#### `XCH-REGISTER ( chain-id con-mode -- fault )`
Register a foreign chain.  Idempotent — re-registering the same
chain-id returns `XCH-OK` without duplicating.  Returns `XCH-ERR-FULL`
if 16 chains already registered.

#### `XCH-SET-AUTH ( key-addr chain-id idx -- fault )`
Set authority key at index `idx` (0–7) for the given chain.  Copies 32
bytes from `key-addr`.  Automatically bumps `n_auth` if `idx+1 > n_auth`.
Returns `XCH-ERR-NOT-FOUND` or `XCH-ERR-IDX`.

#### `XCH-SET-AIR ( ver chain-id -- fault )`
Set the AIR version for a chain (future STARK compatibility).
Returns `XCH-ERR-NOT-FOUND` if chain not registered.

#### `XCH-UNREGISTER ( chain-id -- fault )`
Remove a chain from the registry.  Uses swap-with-last compaction.
Returns `XCH-ERR-NOT-FOUND` if chain not registered.

### Header Verification

#### `XCH-SUBMIT-HEADER ( buf len chain-id -- fault )`
Verify and store a foreign block header.  Steps:

1. `BLK-DECODE` the CBOR buffer into a temp block struct
2. Look up `chain-id` in registry
3. **Sequence check** (if `has_header` flag set): height must be
   previous+1 and `prev_hash` must match stored `last_hash`
4. **Consensus proof**: for PoA/PoSA, verify Ed25519 signature and
   check that the signing key is in the authority table
5. Update registry: store new height, block hash, state root, set
   `has_header` flag

Returns one of the fault codes on failure, `XCH-OK` on success.

### State Verification

#### `XCH-VERIFY-STATE ( key val proof len chain-id -- flag )`
Verify an SMT inclusion proof against the last verified state root for
`chain-id`.  Returns `FALSE` if chain not found or no header has been
verified yet.  Delegates to `SMT-VERIFY`.

- `key` — 32B account address
- `val` — 32B SHA3-256 hash of account entry
- `proof` — buffer of 40-byte SMT proof entries
- `len` — number of proof entries

### Query

#### `XCH-CHAIN-COUNT ( -- n )`
Number of currently registered foreign chains.

#### `XCH-HEIGHT ( chain-id -- n | -1 )`
Last verified height for chain, or -1 if not found / no header yet.

#### `XCH-STATE-ROOT ( chain-id -- addr | 0 )`
Address of 32-byte state root buffer, or 0 if not available.

#### `XCH-CHAIN-INFO ( chain-id -- con-mode air height | 0 0 -1 )`
Returns consensus mode, AIR version, and height.  If chain not found,
returns `0 0 -1`.  If no header verified yet, height is -1.

## Usage Example

```forth
\ Register foreign chain 42 as PoA, set authority key
42 1 XCH-REGISTER DROP
my-authority-pubkey 42 0 XCH-SET-AUTH DROP

\ Submit a CBOR-encoded foreign block header
foreign-cbor-buf cbor-len 42 XCH-SUBMIT-HEADER
0= IF ." Header accepted" THEN

\ Verify foreign account state
account-addr leaf-hash proof proof-len 42 XCH-VERIFY-STATE
IF ." State verified" THEN
```

## Consensus Modes

| Mode | Value | Proof Format | Verification |
|------|-------|-------------|--------------|
| PoW | 0 | 8B nonce | **Not supported** (returns `XCH-ERR-MODE`) |
| PoA | 1 | 32B pubkey + 64B Ed25519 sig | Verify sig + check authority |
| PoS | 2 | 32B pubkey + 64B sig | **Not yet supported** |
| PoSA | 3 | 32B pubkey + 64B Ed25519 sig | Same as PoA |

## Tests

`local_testing/test_xchain.py` — 19 tests covering:
- Compilation, init, registration, deregistration
- Authority key management, AIR version
- PoA header submission (valid, bad sig, bad auth, sequence, wrong height, wrong prev)
- SMT state verification (valid, tampered, no header)
- Unsupported consensus mode rejection

## Future Extensions

- **STARK execution proofs**: Once `stark.f` supports proof
  serialization, cross-chain verification can include execution proofs
  (not just state attestation).
- **PoS support**: Stake-weighted signature verification.
- **Multi-sig threshold**: Require k-of-n authority signatures.
