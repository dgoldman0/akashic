# akashic-tx — Blockchain Transaction Structure

Signed, CBOR-encoded transaction for the Akashic blockchain on
Megapad-64.  Supports Ed25519, SPHINCS+, and hybrid (both) signatures.

```forth
REQUIRE ../store/tx.f
```

`PROVIDED akashic-tx` — depends on `ed25519.f`, `sphincs-plus.f`,
`sha3.f`, `cbor.f`, `fmt.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Buffer Layout](#buffer-layout)
- [Lifecycle](#lifecycle)
- [Setters](#setters)
- [Getters](#getters)
- [Hashing](#hashing)
- [Signing](#signing)
- [Verification](#verification)
- [CBOR Encoding / Decoding](#cbor-encoding--decoding)
- [Validation](#validation)
- [Comparison](#comparison)
- [Debug Printing](#debug-printing)
- [Constants](#constants)
- [Usage Examples](#usage-examples)
- [Quick Reference](#quick-reference)
- [Internals](#internals)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Self-contained** | Every transaction is a flat 8296-byte buffer — no heap allocations, no pointers |
| **Hybrid signatures** | Ed25519 for speed, SPHINCS+ for post-quantum safety, or both for defence-in-depth |
| **Deterministic hashing** | `TX-HASH` serialises unsigned fields to DAG-CBOR (canonical key ordering), then SHA3-256 hashes the result |
| **CBOR wire format** | `TX-ENCODE` / `TX-DECODE` use DAG-CBOR for compact, standards-based serialisation |
| **Not reentrant** | Module-level VARIABLEs are used for scratch state.  One encode/decode/sign at a time |

---

## Buffer Layout

```
Offset  Size    Field
------  ------  -----
  0     32      from       — sender Ed25519 public key
 32     32      from_pq    — sender SPHINCS+ public key (optional)
 64     32      to         — recipient Ed25519 public key
 96      8      amount     — u64 transfer value
104      8      nonce      — u64 sender sequence number
112      2      data_len   — u16 payload length (0..256)
114    256      data       — optional payload bytes
370     64      sig        — Ed25519 signature
434   7856      sig_pq     — SPHINCS+ signature
8290     1      sig_mode   — 0 = Ed25519, 1 = SPHINCS+, 2 = hybrid
8291     1      _flags     — internal (bit 0 = signed, bit 1 = PQ-signed)
8292     4      _pad       — alignment padding
------
8296 total (8-byte aligned)
```

The `data_len` field is stored as little-endian 16-bit using internal
`_TX-W!` / `_TX-W@` helpers (KDOS does not provide `W!` / `W@`).

---

## Lifecycle

### TX-INIT

```forth
TX-INIT  ( tx -- )
```

Zero the entire 8296-byte transaction buffer.  Must be called before
setting any fields.

```forth
CREATE my-tx TX-BUF-SIZE ALLOT
my-tx TX-INIT
```

---

## Setters

### TX-SET-FROM

```forth
TX-SET-FROM  ( pubkey tx -- )
```

Copy 32-byte Ed25519 public key into the `from` field.

### TX-SET-FROM-PQ

```forth
TX-SET-FROM-PQ  ( pq-pubkey tx -- )
```

Copy 32-byte SPHINCS+ public key into the `from_pq` field.  Only
needed for SPHINCS+ or hybrid signing.

### TX-SET-TO

```forth
TX-SET-TO  ( pubkey tx -- )
```

Copy 32-byte Ed25519 public key into the `to` field.

### TX-SET-AMOUNT

```forth
TX-SET-AMOUNT  ( amount tx -- )
```

Store 64-bit unsigned transfer amount.

### TX-SET-NONCE

```forth
TX-SET-NONCE  ( nonce tx -- )
```

Store 64-bit sender sequence number.

### TX-SET-DATA

```forth
TX-SET-DATA  ( addr len tx -- )
```

Copy `len` bytes from `addr` into the data payload.  If `len` exceeds
`TX-MAX-DATA` (256), the call is silently rejected.

---

## Getters

| Word | Stack | Returns |
|---|---|---|
| `TX-FROM@` | `( tx -- addr )` | Address of 32-byte `from` field |
| `TX-FROM-PQ@` | `( tx -- addr )` | Address of 32-byte `from_pq` field |
| `TX-TO@` | `( tx -- addr )` | Address of 32-byte `to` field |
| `TX-AMOUNT@` | `( tx -- n )` | 64-bit amount |
| `TX-NONCE@` | `( tx -- n )` | 64-bit nonce |
| `TX-DATA-LEN@` | `( tx -- n )` | 16-bit data payload length |
| `TX-DATA@` | `( tx -- addr )` | Address of data payload |
| `TX-SIG-MODE@` | `( tx -- n )` | Signature mode (0/1/2) |

---

## Hashing

### TX-HASH

```forth
TX-HASH  ( tx hash -- )
```

Compute the SHA3-256 hash of the unsigned transaction fields.  The hash
covers a DAG-CBOR-encoded map of six fields in canonical key order:

1. `"to"` (32-byte bstr)
2. `"data"` (data payload bstr)
3. `"from"` (32-byte bstr)
4. `"nonce"` (uint)
5. `"amount"` (uint)
6. `"from_pq"` (32-byte bstr)

Writes 32 bytes to `hash`.

---

## Signing

All signing words compute `TX-HASH` internally.

### TX-SIGN

```forth
TX-SIGN  ( tx ed-priv ed-pub -- )
```

Sign with Ed25519.  Sets `sig_mode` to `TX-SIG-ED25519` (0) and
stores the 64-byte signature.

### TX-SIGN-PQ

```forth
TX-SIGN-PQ  ( tx spx-sec -- )
```

Sign with SPHINCS+.  Sets `sig_mode` to `TX-SIG-SPHINCS` (1) and
stores the 7856-byte signature.

**Note:** SPHINCS+ signing is computationally expensive (~200M
emulator steps).

### TX-SIGN-HYBRID

```forth
TX-SIGN-HYBRID  ( tx ed-priv ed-pub spx-sec -- )
```

Sign with both Ed25519 and SPHINCS+.  Sets `sig_mode` to
`TX-SIG-HYBRID` (2) and stores both signatures.

---

## Verification

### TX-VERIFY

```forth
TX-VERIFY  ( tx -- flag )
```

Verify the transaction signature(s).  Dispatches by `sig_mode`:

| Mode | Checks |
|---|---|
| 0 (Ed25519) | Ed25519 sig against `from` key |
| 1 (SPHINCS+) | SPHINCS+ sig against `from_pq` key |
| 2 (Hybrid) | Both sigs; returns `TRUE` if **either** verifies |

Returns `TRUE` (-1) on success, `FALSE` (0) on failure.

Internally recomputes `TX-HASH` and verifies the signature(s) against
it using the public key(s) stored in the transaction.

---

## CBOR Encoding / Decoding

### TX-ENCODE

```forth
TX-ENCODE  ( tx buf max -- len )
```

Serialise the transaction to DAG-CBOR into `buf` (up to `max` bytes).
Returns the number of bytes written.  Returns 0 if the buffer is too
small.

The CBOR map contains 9 keys in DAG-CBOR canonical order (shorter
keys first, then lexicographic within the same length):

| Order | Key | Length | Type |
|---|---|---|---|
| 1 | `"to"` | 2 | bstr (32) |
| 2 | `"sig"` | 3 | bstr (64) |
| 3 | `"data"` | 4 | bstr (data_len) |
| 4 | `"from"` | 4 | bstr (32) |
| 5 | `"nonce"` | 5 | uint |
| 6 | `"amount"` | 6 | uint |
| 7 | `"sig_pq"` | 6 | bstr (7856) |
| 8 | `"from_pq"` | 7 | bstr (32) |
| 9 | `"sig_mode"` | 8 | uint |

### TX-DECODE

```forth
TX-DECODE  ( buf len tx -- flag )
```

Deserialize CBOR bytes into a transaction buffer.  Calls `TX-INIT` on
`tx` first.  Returns `TRUE` on success, `FALSE` on parse error or
unexpected data.

**All 9 keys must be present.**  Unknown keys cause failure.

---

## Validation

### TX-VALID?

```forth
TX-VALID?  ( tx -- flag )
```

Structural validity check (does **not** verify the signature).

- `from` key must not be all-zero
- `to` key must not be all-zero
- `sig_mode` must be 0, 1, or 2
- `data_len` must be ≤ `TX-MAX-DATA`

---

## Comparison

### TX-HASH=

```forth
TX-HASH=  ( tx1 tx2 -- flag )
```

Compute SHA3-256 hashes of both transactions and compare.  Returns
`TRUE` if the unsigned content is identical.

---

## Debug Printing

### TX-PRINT

```forth
TX-PRINT  ( tx -- )
```

Print a one-line summary to UART:

```
TX{ from=d75a9801..  to=3d4017c3..  amt=1000  n=7  dlen=0  mode=0 }
```

Shows the first 8 bytes of `from` and `to` keys in hex.

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `TX-BUF-SIZE` | 8296 | Size of one transaction buffer |
| `TX-SIG-ED25519` | 0 | Signature mode: Ed25519 only |
| `TX-SIG-SPHINCS` | 1 | Signature mode: SPHINCS+ only |
| `TX-SIG-HYBRID` | 2 | Signature mode: hybrid (both) |
| `TX-MAX-DATA` | 256 | Maximum data payload bytes |

---

## Usage Examples

### Basic Transfer

```forth
\ Allocate and initialise
CREATE my-tx TX-BUF-SIZE ALLOT
my-tx TX-INIT

\ Set fields
sender-pub my-tx TX-SET-FROM
recip-pub  my-tx TX-SET-TO
1000       my-tx TX-SET-AMOUNT
42         my-tx TX-SET-NONCE

\ Sign with Ed25519
my-tx sender-priv sender-pub TX-SIGN

\ Verify
my-tx TX-VERIFY  ( -- TRUE )
```

### Encode, Transmit, Decode, Verify

```forth
\ Sender side: encode
CREATE wire-buf 16384 ALLOT
my-tx wire-buf 16384 TX-ENCODE  ( -- len )

\ ... transmit len bytes from wire-buf ...

\ Receiver side: decode and verify
CREATE rx-tx TX-BUF-SIZE ALLOT
wire-buf len rx-tx TX-DECODE    ( -- flag )
DROP
rx-tx TX-VERIFY                 ( -- flag )
```

### Hybrid (Post-Quantum) Signing

```forth
\ Set both public keys
ed-pub  my-tx TX-SET-FROM
spx-pub my-tx TX-SET-FROM-PQ
recip   my-tx TX-SET-TO
500     my-tx TX-SET-AMOUNT
0       my-tx TX-SET-NONCE

\ Sign with both schemes
my-tx ed-priv ed-pub spx-sec TX-SIGN-HYBRID

\ Verify — returns TRUE if either signature is valid
my-tx TX-VERIFY  ( -- TRUE )
```

---

## Quick Reference

```
TX-INIT          ( tx -- )
TX-SET-FROM      ( pubkey tx -- )
TX-SET-FROM-PQ   ( pq-pubkey tx -- )
TX-SET-TO        ( pubkey tx -- )
TX-SET-AMOUNT    ( amount tx -- )
TX-SET-NONCE     ( nonce tx -- )
TX-SET-DATA      ( addr len tx -- )
TX-FROM@         ( tx -- addr )
TX-FROM-PQ@      ( tx -- addr )
TX-TO@           ( tx -- addr )
TX-AMOUNT@       ( tx -- n )
TX-NONCE@        ( tx -- n )
TX-DATA-LEN@     ( tx -- n )
TX-DATA@         ( tx -- addr )
TX-SIG-MODE@     ( tx -- n )
TX-HASH          ( tx hash -- )
TX-SIGN          ( tx ed-priv ed-pub -- )
TX-SIGN-PQ       ( tx spx-sec -- )
TX-SIGN-HYBRID   ( tx ed-priv ed-pub spx-sec -- )
TX-VERIFY        ( tx -- flag )
TX-ENCODE        ( tx buf max -- len )
TX-DECODE        ( buf len tx -- flag )
TX-VALID?        ( tx -- flag )
TX-HASH=         ( tx1 tx2 -- flag )
TX-PRINT         ( tx -- )
```

---

## Internals

### Prefix Convention

Public words use the `TX-` prefix.  Private (internal) words use
`_TX-`.  Module-level VARIABLEs are used throughout — the module is
**not reentrant**.

### 16-bit Helpers

KDOS does not provide `W!` / `W@`.  The module defines private
little-endian 16-bit store and fetch:

```forth
: _TX-W!  ( n addr -- )  OVER 255 AND OVER C!  SWAP 8 RSHIFT SWAP 1+ C! ;
: _TX-W@  ( addr -- n )  DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;
```

### Hashing Strategy

`TX-HASH` encodes the six unsigned fields (from, from_pq, to, amount,
nonce, data) as a CBOR map in DAG-CBOR canonical key order, then
applies SHA3-256.  This is the message that gets signed.  Signatures
and sig_mode are excluded from the hash to prevent circular
dependencies.

### Hybrid Verification

In hybrid mode (sig_mode = 2), `TX-VERIFY` checks **both** signatures
and returns `TRUE` if **either** verifies.  This provides graceful
degradation — if one scheme is later broken, the other still protects.

### CBOR Key Ordering

All CBOR maps (both the 6-key unsigned map and the 9-key full map)
follow DAG-CBOR canonical ordering: keys sorted by length first, then
lexicographically within the same length.  Keys are compiled as inline
constants using `C,`.
