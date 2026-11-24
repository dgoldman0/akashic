# PBKDF2-HMAC-SHA-256

`security/pbkdf2-sha256.f` derives a key from a password and a salt with
PBKDF2 (RFC 8018, section 5.2), using HMAC-SHA-256 as the pseudorandom
function. It is the password-to-key step for anything that unlocks with a
passphrase, such as a credential vault's root key, and it owns no policy:
the caller chooses the salt, the iteration count and the key length.

```forth
REQUIRE security/pbkdf2-sha256.f
```

A derivation runs in steps, so an interactive owner such as Desk can draw
and handle input while a passphrase turns into a key. A step runs at most a
budget of iterations that the caller names, and no hardware transaction
stays open between steps.

## API

```forth
PBKDF2-SHA256-WORKSPACE-SIZE ( dk-u -- u|0 )
PBKDF2-SHA256-STATUS-VALID?  ( status -- flag )

PBKDF2-SHA256-BEGIN
  ( password password-u salt salt-u iterations dk-u workspace -- status )
PBKDF2-SHA256-STEP    ( budget workspace -- remaining status )
PBKDF2-SHA256-FINISH  ( dk workspace -- status )
PBKDF2-SHA256-ABANDON ( workspace -- status )

PBKDF2-SHA256
  ( password password-u salt salt-u iterations dk dk-u workspace -- status )
```

`PBKDF2-SHA256-WORKSPACE-SIZE` gives the workspace size for a derived key
of `dk-u` bytes: 320 bytes plus 32 for each 32-byte block of the key, with
SHA-256's keyed states at today's size. It
returns zero for a length below one or above RFC 8018's limit of
2^32-1 blocks. The caller allocates that many bytes, keeps them at one
address for the whole derivation, and leaves them alone between calls.

`BEGIN` admits every argument before it writes anything: a positive key
length, at least one iteration, an iteration count whose remaining total
fits a cell, a workspace that SHA-256 may read and write, and a password
and salt that do not overlap it. An empty password or salt is admitted, as
the RFC allows. `BEGIN` then builds the two HMAC key blocks, hashing a
password longer than 64 bytes first, makes each into a SHA-256 keyed state
and wipes the block, and computes each output block's first iteration, all
in one held SHA-256 transaction. The workspace then holds everything the derivation needs; the
password and salt are not read again.

`STEP` runs at most `budget` iterations and returns how many remain.
Moving from one output block to the next costs no budget. `FINISH` copies
the key to `dk` once no iterations remain, then wipes the workspace. A
destination that overlaps the workspace, or one SHA-256 could not write, is
refused and leaves the finished derivation in place for a proper
destination or `ABANDON`. `ABANDON` wipes a live workspace.

`PBKDF2-SHA256` runs the whole derivation in one call for callers that need
not draw in between.

## Status values

| Status | Meaning |
|---|---|
| `PBKDF2-SHA256-S-OK` (0) | The operation completed. |
| `PBKDF2-SHA256-S-INVALID` (1) | A length, count, budget or address is out of range. |
| `PBKDF2-SHA256-S-ALIAS` (2) | A password, salt or key overlaps the workspace, or a span overlaps SHA-256's reserved storage. |
| `PBKDF2-SHA256-S-STATE` (3) | The workspace holds no live derivation, or the derivation has iterations left. |
| `PBKDF2-SHA256-S-CRYPTO` (4) | The SHA-256 engine failed. |

A hash failure inside `BEGIN` or `STEP` wipes the workspace and returns
`CRYPTO`. An exception from the engine wipes the workspace and propagates.

## How an iteration runs, and what it costs

Each iteration computes U = HMAC(P, U) and folds it into the block's running
value. HMAC's inner and outer hashes each continue from a keyed state, the
SHA-256 state after one 64-byte key block, with one 32-byte value. A step
takes the SHA-256 transaction once, through `SHA256-WITH-TRANSACTION`, and
runs its iterations with `SHA256-HELD-RESUME` (see
[sha256.md](../math/sha256.md)). The step admits the workspace once on
entry; the iterations then hash spans inside it that do not change.

On today's engine a keyed state is the key block itself, so each hash
absorbs the block again and an iteration is four compressions; the
workspace places each keyed state directly before the value hashed after
it, so each hash reads one span. When the SHA-2 engine saves and loads its
chaining state, as MegaPad's crypto-engines plan decides, a keyed state
becomes that chaining state and an iteration two compressions, without a
change to this module.

Measured on the emulator on 2026-11-24, at the documented 100 MHz clock:

| Work | Cycles | Seconds at 100 MHz |
|---|---:|---:|
| One iteration | 6,633 | 0.000066 |
| 1,000 iterations in one step | 6,632,532 | 0.066 |
| 1,000 iterations in ten steps of 100 | 6,727,235 | 0.067 |
| `BEGIN` for a 32-byte key | 22,003 | 0.0002 |
| RFC 7914's 80,000-iteration, 64-byte vector (160,000 iterations) | 1,059,553,909 | 10.6 |

At 100,000 iterations a 32-byte key takes about 6.6 seconds. Each step adds
about 10,500 cycles for its admission and transaction, so steps of a few
thousand iterations keep that overhead under one part in a thousand while
returning control every few hundredths of a second. The hardware work is
about 6,060 cycles of each iteration, two held hashes of 96 bytes at about
3,030 each; the rest is the step's bookkeeping. A SHA-256 engine that loads
a saved chaining state would halve the compressions through the keyed
states above, and an iteration mode in the engine would remove the software
round trips.

## Tests

`local_testing/test_pbkdf2_sha256.py` runs the guest contract
`local_testing/pbkdf2-sha256-test.f` on the emulator. It derives both
RFC 7914 vectors and keys that exercise a long password, an empty password
and salt, a partial last block, and steps of one iteration, and it checks the
lifecycle and the rejections. Its Python side recomputes every expected key
with `hashlib.pbkdf2_hmac` from the contract's own inputs and prints the
measured cycles.
