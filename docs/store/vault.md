# akashic-vault — Content-Addressed Encrypted Vault

Self-hosted encrypted knowledge base for Megapad-64.  Each blob is:

1. **Content-addressed** — SHA3-256 of the entire envelope is the blob-id
2. **Encrypted at rest** — AES-256-GCM with per-blob derived keys
3. **Integrity-protected** — CRC-32C + SHA3-256 + GCM authentication tag
4. **Committed** — every mutation rebuilds a Merkle tree
5. **Optionally embedding-indexed** — 64-dimension FP16 cosine similarity search

```forth
REQUIRE ../store/vault.f
```

`PROVIDED akashic-vault` — depends on `sha3.f`, `aes.f`, `crc.f`,
`merkle.f`, `random.f`, `fp16-ext.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Lifecycle](#lifecycle)
- [Storing Blobs](#storing-blobs)
- [Retrieving Blobs](#retrieving-blobs)
- [Deletion](#deletion)
- [Integrity Checking](#integrity-checking)
- [Merkle Commitment](#merkle-commitment)
- [Embedding Search](#embedding-search)
- [Compaction](#compaction)
- [Serialization](#serialization)
- [Inspection](#inspection)
- [Error Codes](#error-codes)
- [Envelope Layout](#envelope-layout)
- [Usage Examples](#usage-examples)
- [Quick Reference](#quick-reference)
- [Internals](#internals)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Content addressing** | Blob-id = SHA3-256 of the full on-disk envelope (header + AAD + ciphertext + tag + optional embedding + CRC).  Unique, deterministic, tamper-evident. |
| **Per-blob encryption** | Each blob gets a fresh 12-byte random IV.  The AES-256-GCM key is derived: `HMAC-SHA3-256(master-key, IV)`.  Master key never touches the accelerator directly. |
| **Three-layer integrity** | CRC-32C (fast corruption check) → SHA3-256 (content-address verify) → GCM tag (authenticated decryption). |
| **Merkle commitment** | All live blob-ids are committed to a binary Merkle tree.  `VAULT-ROOT` returns the 32-byte root; `VAULT-PROVE` / `VAULT-VERIFY` produce and check inclusion proofs. |
| **Embedding search** | Optional 64-dimension FP16 embedding per blob, encrypted with a separate derived key.  `VAULT-SEARCH` performs brute-force top-k cosine similarity. |
| **Arena allocator** | All blob data lives in a flat XMEM arena.  `VAULT-COMPACT` reclaims tombstoned space.  No fragmentation overhead at rest. |
| **Not reentrant** | Uses module-level VARIABLEs.  One vault open at a time. |

---

## Lifecycle

### VAULT-OPEN

```forth
VAULT-OPEN  ( key max-blobs arena-bytes -- flag )
```

Open a new empty vault.

| Parameter | Size | Description |
|---|---|---|
| `key` | 32 bytes | Master encryption key (copied internally) |
| `max-blobs` | cell | Maximum number of live blobs |
| `arena-bytes` | cell | Size of the data arena in bytes |

Returns `TRUE` on success.  Allocates four XMEM blocks: arena, hash
index (2× max-blobs slots), Merkle tree, and embedding table.  Returns
`FALSE` if any allocation fails.

```forth
CREATE my-key 32 ALLOT   my-key 32 0xAA FILL
my-key 64 65536 VAULT-OPEN  ( -- flag )
```

### VAULT-CLOSE

```forth
VAULT-CLOSE  ( -- )
```

Close the vault.  Zeroes the master key, wipes the embedding table, and
frees all four XMEM blocks.  Safe to call multiple times or when no
vault is open.

---

## Storing Blobs

### VAULT-PUT

```forth
VAULT-PUT  ( pt ptlen aad alen -- blob-id )
```

Store a blob.  `pt`/`ptlen` is the plaintext payload; `aad`/`alen` is
Additional Authenticated Data stored in cleartext alongside the
ciphertext.

Returns the 32-byte blob-id address, or `0` if the arena is full or the
blob limit is reached.

| Step | Detail |
|---|---|
| 1 | Generate random 12-byte IV |
| 2 | Derive per-blob key: `HMAC-SHA3-256(master-key, IV)` |
| 3 | Write header, copy AAD plaintext |
| 4 | Encrypt payload with AES-256-GCM (header + AAD as authenticated data) |
| 5 | Append GCM tag, CRC-32C trailer |
| 6 | Compute blob-id = SHA3-256 of entire envelope |
| 7 | Insert into hash index, update Merkle tree |

```forth
S" hello world" my-pt SWAP CMOVE
S" metadata"    my-aad SWAP CMOVE
my-pt 11 my-aad 8 VAULT-PUT  ( -- blob-id )
```

### VAULT-PUT-EMB

```forth
VAULT-PUT-EMB  ( pt ptlen aad alen emb -- blob-id )
```

Like `VAULT-PUT` but also attaches a 128-byte (64-dimension FP16)
embedding vector.  The embedding is encrypted with a separate derived
key (`HMAC-SHA3-256(master-key, 0x01 || IV)`) and stored inside the
envelope.  A cleartext copy is kept in the in-memory embedding table
for search.

---

## Retrieving Blobs

### VAULT-GET

```forth
VAULT-GET  ( blob-id buf buflen -- ptlen flag )
```

Retrieve and decrypt a blob.

| Return | Description |
|---|---|
| `ptlen` | Plaintext length in bytes |
| `flag` | `TRUE` — decryption & auth succeeded, plaintext in `buf` |
|        | `FALSE` — CRC/SHA3/GCM failure or tombstoned blob; `buf` is zeroed |

If `buflen` < `ptlen`, returns `( ptlen FALSE )` without decrypting —
use this to query the required buffer size.

Verification order: CRC-32C → SHA3-256 (blob-id) → GCM auth-decrypt.

### VAULT-GET-AAD

```forth
VAULT-GET-AAD  ( blob-id buf buflen -- alen )
```

Copy the AAD (cleartext) of a blob into `buf`.  Returns the AAD length.
If `buflen` < `alen`, copies only `buflen` bytes.  Returns `0` for
tombstoned or nonexistent blobs.

### VAULT-GET-EMB

```forth
VAULT-GET-EMB  ( blob-id dst -- flag )
```

Decrypt the 128-byte embedding of a blob into `dst`.  Returns `FALSE`
if the blob has no embedding, doesn't exist, or is tombstoned.

### VAULT-HAS?

```forth
VAULT-HAS?  ( blob-id -- flag )
```

Return `TRUE` if the blob exists and is not tombstoned.

### VAULT-SIZE

```forth
VAULT-SIZE  ( blob-id -- ptlen )
```

Return the plaintext length of a blob, or `0` if not found / tombstoned.

---

## Deletion

### VAULT-DELETE

```forth
VAULT-DELETE  ( blob-id -- flag )
```

Soft-delete a blob by setting the tombstone flag.  The Merkle leaf is
replaced with the empty-hash sentinel and the tree is rebuilt.  The
embedding row is zeroed.  Returns `TRUE` on success, `FALSE` if the
blob doesn't exist or is already tombstoned.

The arena space is not freed until `VAULT-COMPACT` is called.

---

## Integrity Checking

### VAULT-CHECK

```forth
VAULT-CHECK  ( blob-id -- n )
```

Full three-layer integrity check without returning plaintext.

| Return `n` | Meaning |
|---|---|
| `0` | OK — CRC, SHA3, and GCM all pass |
| `1` | Not found (or tombstoned) |
| `2` | CRC-32C mismatch |
| `3` | SHA3-256 mismatch (blob-id doesn't match envelope) |
| `4` | GCM authentication failure |

Decrypts into an internal 256-byte scratch buffer in chunks — no large
allocation needed.

---

## Merkle Commitment

### VAULT-ROOT

```forth
VAULT-ROOT  ( -- addr )
```

Return a pointer to the 32-byte Merkle root.  The tree is rebuilt
automatically after every `VAULT-PUT`, `VAULT-DELETE`, and
`VAULT-COMPACT`.

### VAULT-PROVE

```forth
VAULT-PROVE  ( blob-id proof -- depth )
```

Generate a Merkle inclusion proof for a blob.  Writes sibling hashes
into the `proof` buffer (32 bytes per level).  Returns the proof depth
(number of levels), or `0` if the blob is not found.

The `proof` buffer must be large enough for `depth × 32` bytes (at most
`log₂(max-blobs) × 32`).

### VAULT-VERIFY

```forth
VAULT-VERIFY  ( blob-id proof depth root -- flag )
```

Verify a Merkle inclusion proof.  Returns `TRUE` if the proof is valid
for the given blob-id and root.

```forth
my-id my-proof VAULT-PROVE  ( -- depth )
my-id my-proof ROT VAULT-ROOT VAULT-VERIFY  ( -- flag )
```

---

## Embedding Search

### VAULT-SEARCH

```forth
VAULT-SEARCH  ( query k results -- n )
```

Find the top-`k` blobs most similar to the 128-byte FP16 query vector.
Writes up to `k` Merkle leaf indices into the `results` array (one cell
each).  Returns the number of results found (`n ≤ k`).

Uses brute-force cosine similarity via `FP16-DOT32`.  Empty embedding
rows (tombstoned blobs) are skipped automatically.

### VAULT-SEARCH-SCORE

```forth
VAULT-SEARCH-SCORE  ( query k results scores -- n )
```

Like `VAULT-SEARCH` but also writes the FP16 similarity scores into the
`scores` array (one 16-bit value per result, `k × 2` bytes).

---

## Compaction

### VAULT-COMPACT

```forth
VAULT-COMPACT  ( -- flag )
```

Reclaim arena space consumed by tombstoned blobs.  Allocates a
temporary XMEM buffer, copies only live blobs, replaces the old arena,
and rebuilds the index and Merkle tree.  Returns `TRUE` on success,
`FALSE` if the temporary allocation fails.

### VAULT-SPACE

```forth
VAULT-SPACE  ( -- bytes )
```

Return the number of free bytes remaining in the arena.

### VAULT-FRAG

```forth
VAULT-FRAG  ( -- dead-bytes )
```

Return the number of bytes occupied by tombstoned blobs — the amount
that `VAULT-COMPACT` would reclaim.

---

## Serialization

### VAULT-SAVE-SIZE

```forth
VAULT-SAVE-SIZE  ( -- n )
```

Return the number of bytes needed to serialize the entire vault
(56-byte header + arena contents).

### VAULT-SAVE

```forth
VAULT-SAVE  ( buf buflen -- actual )
```

Serialize the vault into `buf`.  Returns the actual number of bytes
written, or `0` if `buflen` is too small.

The serialization format:

| Offset | Size | Content |
|---|---|---|
| 0 | 8 | Magic: `AKASHVLT` (ASCII) |
| 8 | 4 | Version (LE32), currently `1` |
| 12 | 4 | `max-blobs` (LE32) |
| 16 | 8 | Arena used bytes (64-bit LE) |
| 24 | 32 | SHA3-256 of master key (key fingerprint) |
| 56 | … | Raw arena data |

### VAULT-LOAD

```forth
VAULT-LOAD  ( key buf len max-blobs arena-bytes -- flag )
```

Deserialize a vault from a buffer.  Verifies the magic bytes, checks
the key fingerprint (`SHA3-256(key) == stored hash`), then opens a new
vault and restores the arena contents.  Rebuilds the hash index, Merkle
tree, and embedding table from the arena data.

Returns `TRUE` on success, `FALSE` if the magic is wrong, the key
doesn't match, or allocation fails.

```forth
\ Save
my-ser 65536 VAULT-SAVE  ( -- actual )
VAULT-CLOSE
\ Load
my-key my-ser actual 64 65536 VAULT-LOAD  ( -- flag )
```

---

## Inspection

### VAULT-COUNT

```forth
VAULT-COUNT  ( -- n )
```

Return the number of live (non-tombstoned) blobs.

### VAULT-DUMP

```forth
VAULT-DUMP  ( -- )
```

Print vault summary: blob count, arena usage, and Merkle root.

### VAULT-BLOB.

```forth
VAULT-BLOB.  ( blob-id -- )
```

Print details of a single blob: ID, arena offset, envelope length,
Merkle leaf index, and flags.

---

## Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `_VLT-OK` | 0 | No error |
| `_VLT-E-NOTFOUND` | 1 | Blob not found or tombstoned |
| `_VLT-E-CRC` | 2 | CRC-32C mismatch |
| `_VLT-E-SHA3` | 3 | SHA3-256 hash mismatch |
| `_VLT-E-GCM` | 4 | AES-GCM authentication failure |

---

## Envelope Layout

Each blob is stored as a contiguous envelope in the arena:

```
┌─────────────────────────────────────────────────┐
│  Header (28 bytes)                              │
│   0: magic       (LE32)  0x564C5400             │
│   4: flags       (LE32)  bit 0=has-emb, 1=tomb  │
│   8: IV          (12 bytes)  random nonce        │
│  20: alen        (LE32)  AAD length              │
│  24: ptlen       (LE32)  plaintext length        │
├─────────────────────────────────────────────────┤
│  AAD             (alen bytes, cleartext)         │
├─────────────────────────────────────────────────┤
│  Ciphertext      (ptlen bytes, AES-GCM)         │
├─────────────────────────────────────────────────┤
│  GCM Tag         (16 bytes)                      │
├─────────────────────────────────────────────────┤
│  Embedding       (if HAS-EMB flag set)           │
│   128 bytes encrypted FP16 vector                │
│    16 bytes embedding GCM tag                    │
├─────────────────────────────────────────────────┤
│  CRC-32C         (LE32, covers bytes 0..end-4)   │
└─────────────────────────────────────────────────┘
```

The **blob-id** = `SHA3-256(entire envelope)`.

The GCM AAD scope covers the header (28 bytes) + AAD plaintext —
everything before the ciphertext.  This binds the IV, lengths, and
flags to the authentication tag.

---

## Usage Examples

### Basic Store & Retrieve

```forth
CREATE my-key 32 ALLOT   my-key 32 0xAA FILL
CREATE my-pt  64 ALLOT
CREATE my-aad 32 ALLOT
CREATE my-buf 64 ALLOT
CREATE my-id  32 ALLOT

my-key 16 8192 VAULT-OPEN DROP

S" hello vault" my-pt SWAP CMOVE
S" label:test"  my-aad SWAP CMOVE
my-pt 11 my-aad 10 VAULT-PUT  my-id 32 CMOVE

my-id my-buf 64 VAULT-GET  ( -- ptlen flag )
.  .  CR  \ prints: -1 11

VAULT-CLOSE
```

### Merkle Proof Round-Trip

```forth
CREATE my-proof 640 ALLOT

my-id my-proof VAULT-PROVE  ( -- depth )
my-id my-proof ROT VAULT-ROOT VAULT-VERIFY  ( -- flag )
\ flag = TRUE
```

### Serialization Round-Trip

```forth
CREATE ser-buf 65536 ALLOT

ser-buf 65536 VAULT-SAVE  ( -- actual )
VAULT-CLOSE

my-key ser-buf actual 16 8192 VAULT-LOAD  ( -- flag )
\ vault restored — all blobs accessible
```

### Embedding Search

```forth
CREATE my-emb  128 ALLOT   \ 64-dim FP16 vector
CREATE my-qry  128 ALLOT   \ query vector
CREATE results  40 ALLOT   \ up to 5 results
CREATE scores   10 ALLOT   \ FP16 scores

my-pt 11 my-aad 10 my-emb VAULT-PUT-EMB  ( -- blob-id )

my-qry 5 results scores VAULT-SEARCH-SCORE  ( -- n )
\ n = number of matches found
```

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `VAULT-OPEN` | `( key max arena -- flag )` | Open new vault |
| `VAULT-CLOSE` | `( -- )` | Close & wipe |
| `VAULT-PUT` | `( pt ptl aad al -- id )` | Store blob |
| `VAULT-PUT-EMB` | `( pt ptl aad al emb -- id )` | Store blob + embedding |
| `VAULT-GET` | `( id buf len -- ptl flag )` | Decrypt & retrieve |
| `VAULT-GET-AAD` | `( id buf len -- alen )` | Read AAD |
| `VAULT-GET-EMB` | `( id dst -- flag )` | Decrypt embedding |
| `VAULT-HAS?` | `( id -- flag )` | Existence check |
| `VAULT-SIZE` | `( id -- ptlen )` | Plaintext length |
| `VAULT-DELETE` | `( id -- flag )` | Soft-delete |
| `VAULT-CHECK` | `( id -- n )` | Full integrity check |
| `VAULT-ROOT` | `( -- addr )` | Merkle root |
| `VAULT-PROVE` | `( id proof -- depth )` | Inclusion proof |
| `VAULT-VERIFY` | `( id proof depth root -- flag )` | Verify proof |
| `VAULT-SEARCH` | `( qry k res -- n )` | Top-k search |
| `VAULT-SEARCH-SCORE` | `( qry k res scr -- n )` | Top-k + scores |
| `VAULT-COMPACT` | `( -- flag )` | Reclaim tombstones |
| `VAULT-SPACE` | `( -- bytes )` | Free arena bytes |
| `VAULT-FRAG` | `( -- bytes )` | Dead arena bytes |
| `VAULT-SAVE-SIZE` | `( -- n )` | Serialization size |
| `VAULT-SAVE` | `( buf len -- actual )` | Serialize |
| `VAULT-LOAD` | `( key buf len max arena -- flag )` | Deserialize |
| `VAULT-COUNT` | `( -- n )` | Live blob count |
| `VAULT-DUMP` | `( -- )` | Print summary |
| `VAULT-BLOB.` | `( id -- )` | Print blob details |

---

## Internals

**Prefix:** `_VLT-` (private words), `VAULT-` (public API).

**Memory layout:**
- Arena — flat XMEM buffer, blobs packed sequentially
- Hash index — open-addressing hash table, 2× max-blobs slots, 64 bytes each (hash + offset + length + Merkle index + flags)
- Merkle tree — binary tree over next-power-of-2 leaf slots; empty leaves use `SHA3-256("VAULT-EMPTY")`
- Embedding table — `max-blobs × 128` bytes in XMEM; L2-normalized FP16 vectors

**Key derivation:**
- Payload key: `HMAC-SHA3-256(master-key, IV)`
- Embedding key: `HMAC-SHA3-256(master-key, 0x01 || IV)`
- Keys are zeroed immediately after each encrypt/decrypt

**Shared variables:** `_VT-A` through `_VT-E` are used as temporaries by
multi-step operations.  Not safe across calls — each public word manages
its own usage.

**Test coverage:** 42 tests in `test_vault.py` covering lifecycle,
PUT/GET, AAD, encryption integrity, Merkle proofs, deletion, compaction,
content addressing, edge cases, large payloads, and serialization
round-trips.
