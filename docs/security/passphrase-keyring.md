# Passphrase keyring

`akashic/security/passphrase-keyring.f` keeps the machine's root key for
sealed secrets under a passphrase the user gives once per boot. The root key
is 32 random bytes, made once when the keyring is set up. The keyring file
holds it sealed under a key derived from the passphrase with
PBKDF2-HMAC-SHA-256 ([pbkdf2-sha256.md](pbkdf2-sha256.md)), at the iteration
count the file records, so a keyring made later can use a higher count than
one made today. While the keyring is unlocked it lends the root key to the
credential vault through the sealed-record resolver contract
([credential-vault.md](credential-vault.md)); lock wipes it from memory.

## Why a root key under the passphrase

The vault seals every secret under the root key, not under the passphrase.
A changed passphrase therefore seals the same root key again, one record of
208 bytes, and every secret stays readable without being sealed again. The
passphrase never reaches the vault, and the derived key lives only while a
derivation finishes.

## The file

One fixed-size record of 304 bytes, which the keyring writes by checked
replacement (`utils/fs/place-replace.f`):

| Bytes | Field |
|---|---|
| 0-7 | magic `AKPKRNG1` |
| 8-15 | version, 1 |
| 16-23 | PBKDF2 iterations |
| 24-31 | revision, which each change raises |
| 32-63 | salt, fresh for each setup and change |
| 64-95 | keyring id, the key id the vault names the root key by |
| 96-303 | the root key's sealed record |

The sealed record's key id is the SHA-256 of the first 64 bytes, so the
count, revision and salt are bound to the record they open: a file whose
count was changed reads as corrupt, never as a wrong passphrase.

## Steps

Deriving the key takes about 6.6 s at 100,000 iterations on MegaPad, so
`KEYRING-UNLOCK`, `KEYRING-SETUP` and `KEYRING-CHANGE` only start a
derivation, and `KEYRING-STEP ( budget keyring -- status )` runs it in steps
of `budget` iterations, answering `KEYRING-S-PENDING` until it ends.
`KEYRING-PROGRESS` gives the iterations done and the total, so an owner can
draw progress between steps. The start runs the first iteration, as PBKDF2's
`BEGIN` does, so a derivation reports one done before its first step.
`KEYRING-CANCEL` returns to the state the derivation started from.

## Wanting the key

A resolver call while the keyring is locked answers `SEALED-RECORD-S-KEY`,
which the vault reports as `CVAULT-S-LOCKED`, and marks the keyring wanted.
Its owner sees `KEYRING-WANTED?` and asks for the passphrase; the vault's
caller retries once the keyring is unlocked.

## Words

| Word | Effect |
|---|---|
| `KEYRING-SIZE` | `( -- u )` The bytes a keyring takes, its PBKDF2 workspace among them. |
| `KEYRING-INIT` | `( path-a path-u place keyring -- status )` Bind a caller-owned keyring of `KEYRING-SIZE` bytes to the file at the path in the place, settle a replacement a crash interrupted, and read the file: `KEYRING-LOCKED`, or `KEYRING-ABSENT` when there is none. |
| `KEYRING-FINI` | `( keyring -- )` Abandon any derivation and wipe the keyring. |
| `KEYRING-SETUP` | `( pass-a pass-u iterations keyring -- status )` From `ABSENT`: a fresh root key, id and salt, derived at `iterations`; `KEYRING-S-PENDING`. |
| `KEYRING-UNLOCK` | `( pass-a pass-u keyring -- status )` From `LOCKED`: derive the file's key; `KEYRING-S-PENDING`. |
| `KEYRING-CHANGE` | `( pass-a pass-u iterations keyring -- status )` From `UNLOCKED`: seal the same root key under a new passphrase, salt and count; `KEYRING-S-PENDING`. |
| `KEYRING-STEP` | `( budget keyring -- status )` Run up to `budget` iterations. `KEYRING-S-PENDING` while some remain; at the end `KEYRING-S-OK`, `KEYRING-S-WRONG` for an unlock whose passphrase does not open the key, or the failure. Setup and change write the file before they answer `OK`. |
| `KEYRING-PROGRESS` | `( keyring -- done total )` The running derivation's iterations, or `0 0`. |
| `KEYRING-CANCEL` | `( keyring -- )` Abandon the derivation and return to the state it started from. |
| `KEYRING-LOCK` | `( keyring -- )` Wipe the root key. |
| `KEYRING-RESOLVER` | `( key-id u consumer-xt consumer-context keyring -- status )` The sealed-record resolver: while unlocked and for this keyring's id, lend the root key to the consumer once and return its status; otherwise `SEALED-RECORD-S-KEY`, marking the keyring wanted when it is locked. |
| `KEYRING-WANTED?` `KEYRING-WANT-CLEAR` | `( keyring -- flag )` `( keyring -- )` Whether a resolver call found the keyring locked since an unlock or a clear. |
| `KEYRING-STATE@` `KEYRING-ID` `KEYRING-ITERATIONS@` | The state, the 32-byte id the vault names the key by, and the file's count. |

States: `KEYRING-ABSENT` 0 (no file yet), `-LOCKED` 1, `-UNLOCKING` 2,
`-SETTING-UP` 3, `-CHANGING` 4, `-UNLOCKED` 5.

Statuses: `KEYRING-S-OK` 0, `-INVALID` 1, `-STATE` 2, `-PENDING` 3,
`-WRONG` 4, `-IO` 5, `-CORRUPT` 6, `-CRYPTO` 7, `-ENTROPY` 8, `-CAPACITY` 9.
A failure during setup or change leaves the keyring as it was before the
derivation started, its file unchanged.

`KEYRING-ITERATIONS-DEFAULT` is 100,000, the count an interactive owner sets
up and changes with; `KEYRING-FILE-SIZE` is 304 and `KEYRING-ID-SIZE` 32.

## Tests

`local_testing/test_passphrase_keyring.py` runs the contract
`local_testing/keyring-test.f` on the native runtime, at 64 and 96
iterations on a RAM volume: setup in steps and the progress it reports, the key the resolver
lends and the ids it refuses, lock and the wanted flag, a second keyring over
the same file with a wrong and a right passphrase, a change of passphrase and
count that keeps the key, a cancel, a sealed record opened through the
keyring's resolver before and after a lock, and a count changed in the file,
which reads as corrupt.
