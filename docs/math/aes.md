# akashic-aes — AES-256/128-GCM Authenticated Encryption

Hardware-accelerated AES-GCM authenticated encryption and decryption.
Wraps the Megapad-64 AES MMIO accelerator at `0x0700` with a clean
Akashic-layer API supporting AES-256 and AES-128, optional AAD
(Additional Authenticated Data), and both one-shot and streaming modes.

```forth
REQUIRE aes.f
```

`PROVIDED akashic-aes` — no dependencies (uses BIOS/KDOS AES MMIO primitives).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Mode Selection](#mode-selection)
- [One-Shot Encryption](#one-shot-encryption)
- [One-Shot Decryption](#one-shot-decryption)
- [Encryption with AAD](#encryption-with-aad)
- [Decryption with AAD](#decryption-with-aad)
- [Streaming API](#streaming-api)
- [Tag Operations](#tag-operations)
- [Usage Examples](#usage-examples)
- [Quick Reference](#quick-reference)
- [Internals](#internals)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Hardware-accelerated** | All AES-GCM operations go through the MMIO accelerator — no software AES |
| **AEAD** | GCM provides both confidentiality and authenticity in a single operation |
| **Variable-length data** | Handles any length including non-16-aligned via zero-padded partial blocks |
| **AES-256 and AES-128** | Both key sizes supported; AES-256 is the default |
| **Not reentrant** | Uses module-level VARIABLEs; one encryption at a time |

---

## Constants

```forth
AES-GCM-KEY-LEN     ( -- 32 )    \ AES-256 key size in bytes
AES-GCM-KEY128-LEN  ( -- 16 )    \ AES-128 key size in bytes
AES-GCM-IV-LEN      ( -- 12 )    \ Nonce size in bytes
AES-GCM-TAG-LEN     ( -- 16 )    \ Authentication tag size in bytes
AES-GCM-BLK-LEN     ( -- 16 )    \ Block size in bytes
```

---

## Mode Selection

```forth
AES-GCM-USE-256  ( -- )    \ Select AES-256 (default, 14 rounds)
AES-GCM-USE-128  ( -- )    \ Select AES-128 (10 rounds)
```

Mode persists until changed. Default after module load is AES-256.

---

## One-Shot Encryption

### AES-GCM-ENCRYPT

```forth
AES-GCM-ENCRYPT  ( key iv pt ct len -- )
```

Encrypt `len` bytes from `pt` to `ct`. The 16-byte authentication tag is
stored internally — retrieve it with `AES-GCM-TAG@` or display with
`AES-GCM-TAG.`.

| Parameter | Size | Description |
|---|---|---|
| `key` | 32 bytes (or 16 for AES-128) | Encryption key |
| `iv` | 12 bytes | Nonce / initialization vector |
| `pt` | `len` bytes | Plaintext input |
| `ct` | `len` bytes | Ciphertext output |
| `len` | cell | Data length (any size, including non-16-aligned) |

---

## One-Shot Decryption

### AES-GCM-DECRYPT

```forth
AES-GCM-DECRYPT  ( key iv ct pt len tag -- flag )
```

Decrypt `len` bytes from `ct` to `pt` and verify the authentication tag.
Returns TRUE (-1) if the tag matches, FALSE (0) on authentication failure.

| Parameter | Size | Description |
|---|---|---|
| `tag` | 16 bytes | Expected authentication tag |
| Returns | flag | TRUE = authentic, FALSE = tampered |

**Important:** On authentication failure, the plaintext output should be
considered invalid and discarded.

---

## Encryption with AAD

### AES-GCM-ENCRYPT-AAD

```forth
AES-GCM-ENCRYPT-AAD  ( key iv aad alen pt ct len -- )
```

Encrypt with Additional Authenticated Data. AAD is authenticated but not
encrypted — used for headers, sequence numbers, etc.

| Parameter | Size | Description |
|---|---|---|
| `aad` | `alen` bytes | Additional authenticated data (max 16 bytes per block) |
| `alen` | cell | AAD length |

---

## Decryption with AAD

### AES-GCM-DECRYPT-AAD

```forth
AES-GCM-DECRYPT-AAD  ( key iv aad alen ct pt len tag -- flag )
```

Decrypt and verify with AAD. Both the AAD and ciphertext are authenticated.

---

## Streaming API

For multi-step operations where key setup, AAD, and data feeding happen
in separate phases.

### AES-GCM-BEGIN

```forth
AES-GCM-BEGIN  ( key iv aadlen datalen dir -- )
```

Initialize a GCM context. `dir`: 0 = encrypt, 1 = decrypt.
For decryption, write the expected tag via `AES-TAG!` before calling this.

### AES-GCM-FEED-AAD

```forth
AES-GCM-FEED-AAD  ( addr len -- )
```

Feed AAD data. Call once, before feeding any data blocks.

### AES-GCM-FEED-DATA

```forth
AES-GCM-FEED-DATA  ( src dst len -- )
```

Feed data blocks through the engine. Handles partial final blocks.

### AES-GCM-FINISH

```forth
AES-GCM-FINISH  ( -- )
```

Finalize the GCM operation. Reads the computed tag into the internal
tag buffer.

---

## Tag Operations

### AES-GCM-TAG@

```forth
AES-GCM-TAG@  ( dst -- )
```

Copy the 16-byte tag from the last encryption to `dst`.

### AES-GCM-TAG.

```forth
AES-GCM-TAG.  ( -- )
```

Print the last tag as 32 lowercase hex characters.

### AES-GCM-TAG-EQ?

```forth
AES-GCM-TAG-EQ?  ( a -- flag )
```

Constant-time compare 16-byte buffer at `a` against the last computed tag.
Returns TRUE if equal.

### AES-GCM-STATUS

```forth
AES-GCM-STATUS  ( -- n )
```

Return hardware status: 0 = idle, 2 = done (OK), 3 = auth fail.

---

## Usage Examples

### Basic Encrypt / Decrypt

```forth
REQUIRE akashic/math/aes.f

CREATE MY-KEY 32 ALLOT   \ fill with key bytes
CREATE MY-IV  12 ALLOT   \ fill with nonce
CREATE MY-PT  64 ALLOT   \ plaintext
CREATE MY-CT  64 ALLOT   \ ciphertext
CREATE MY-TAG 16 ALLOT   \ tag buffer
CREATE MY-OUT 64 ALLOT   \ decrypted output

\ Encrypt 64 bytes
MY-KEY MY-IV MY-PT MY-CT 64 AES-GCM-ENCRYPT
MY-TAG AES-GCM-TAG@

\ Decrypt and verify
MY-KEY MY-IV MY-CT MY-OUT 64 MY-TAG AES-GCM-DECRYPT
IF ." Authentic" ELSE ." TAMPERED" THEN
```

### With AAD (e.g., TLS record header)

```forth
CREATE HDR 5 ALLOT   \ TLS record header

MY-KEY MY-IV HDR 5 MY-PT MY-CT 64 AES-GCM-ENCRYPT-AAD
MY-TAG AES-GCM-TAG@

MY-KEY MY-IV HDR 5 MY-CT MY-OUT 64 MY-TAG AES-GCM-DECRYPT-AAD
IF ." OK" THEN
```

### AES-128 Mode

```forth
AES-GCM-USE-128
CREATE KEY128 16 ALLOT
\ ... encrypt with 16-byte key ...
AES-GCM-USE-256   \ restore default
```

### Streaming

```forth
MY-KEY MY-IV 5 64 0 AES-GCM-BEGIN   \ encrypt, 5B AAD, 64B data
HDR 5 AES-GCM-FEED-AAD
MY-PT MY-CT 64 AES-GCM-FEED-DATA
AES-GCM-FINISH
MY-TAG AES-GCM-TAG@
```

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `AES-GCM-KEY-LEN` | `( -- 32 )` | AES-256 key size |
| `AES-GCM-KEY128-LEN` | `( -- 16 )` | AES-128 key size |
| `AES-GCM-IV-LEN` | `( -- 12 )` | Nonce size |
| `AES-GCM-TAG-LEN` | `( -- 16 )` | Tag size |
| `AES-GCM-BLK-LEN` | `( -- 16 )` | Block size |
| `AES-GCM-USE-256` | `( -- )` | Select AES-256 |
| `AES-GCM-USE-128` | `( -- )` | Select AES-128 |
| `AES-GCM-ENCRYPT` | `( key iv pt ct len -- )` | Encrypt (no AAD) |
| `AES-GCM-DECRYPT` | `( key iv ct pt len tag -- flag )` | Decrypt + verify |
| `AES-GCM-ENCRYPT-AAD` | `( key iv aad alen pt ct len -- )` | Encrypt with AAD |
| `AES-GCM-DECRYPT-AAD` | `( key iv aad alen ct pt len tag -- flag )` | Decrypt with AAD |
| `AES-GCM-BEGIN` | `( key iv aadlen datalen dir -- )` | Init streaming |
| `AES-GCM-FEED-AAD` | `( addr len -- )` | Feed AAD block |
| `AES-GCM-FEED-DATA` | `( src dst len -- )` | Feed data |
| `AES-GCM-FINISH` | `( -- )` | Finalize, tag ready |
| `AES-GCM-TAG@` | `( dst -- )` | Copy tag to dst |
| `AES-GCM-TAG.` | `( -- )` | Print tag hex |
| `AES-GCM-TAG-EQ?` | `( a -- flag )` | Compare tag |
| `AES-GCM-STATUS` | `( -- n )` | Hardware status |

---

## Internals

### Hardware

The AES-GCM accelerator lives at MMIO base `0xFFFF_FF00_0000_0700`.
It implements AES-256-GCM and AES-128-GCM with hardware key expansion,
CTR-mode encryption, and GHASH authentication in GF(2^128).

Block processing is triggered by writing byte 15 of the DIN register.
Tag finalization happens automatically after the last data block.

### Scratch Buffers

| Buffer | Size | Purpose |
|---|---|---|
| `_AES-TAG-BUF` | 16 bytes | Last computed authentication tag |
| `_AES-PAD` | 16 bytes | Zero-padding for AAD and partial blocks |

### Variables

| Variable | Purpose |
|---|---|
| `_AES-VSRC` | Current source pointer during block feed |
| `_AES-VDST` | Current destination pointer during block feed |
| `_AES-VLEN` | Data length for current operation |
| `_AES-VAAD` | AAD source address |
| `_AES-VAADL` | AAD length |

---

## Test Coverage

27 tests covering:

- Constants (5)
- Module compilation (1)
- AES-256 encryption: 1-block, 2-block, ciphertext + tag verification (4)
- Decrypt roundtrip: plaintext recovery + auth success (2)
- Authentication failure: corrupted tag detection (1)
- AAD: encrypt + decrypt with associated data (3)
- Partial blocks: non-16-aligned data with AAD (3)
- AES-128: ciphertext + tag against reference (2)
- Tag display, constant-time comparison (3)
- Streaming API: encrypt with AAD (2)
- Two-block decrypt roundtrip (1)

Source: 205 lines of Forth. Test file: `local_testing/test_aes.py`.
