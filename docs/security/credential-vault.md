# Credential vault

`security/credential-vault.f` is a generic, RID-addressed durable secret
owner. It stores one credential per file, authenticates the credential's
identity and revision, performs optimistic replacement, represents revocation
with a durable authenticated tombstone, and contains uncertain storage states
until explicit recovery succeeds.

The library owns no OAuth, AT Protocol, PDS, Streams, account, prompt, UI, or
credential interpretation. `kind` is an application-defined positive cell and
the secret is an opaque nonempty byte string. The caller owns RID retention,
root-key policy, the optional anti-rollback service, VFS selection and
lifecycle, directory access policy, and every application-level association.

```forth
REQUIRE security/credential-vault.f
```

## Storage and cryptographic model

Every credential is one fixed-size VFS snapshot. For a configured secret
capacity `C`, its authenticated plaintext is exactly `128 + C` bytes, its
sealed-record payload is exactly `304 + C` bytes, and the complete snapshot
file adds the 64-byte VFSNAP envelope.

The plaintext header is:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII magic `AKCVPL01` |
| 8 | 8 | version, exactly `1` |
| 16 | 8 | header size, exactly `128` |
| 24 | 8 | `CVAULT-STATE-PRESENT` or `CVAULT-STATE-TOMBSTONE` |
| 32 | 8 | snapshot generation |
| 40 | 8 | positive application-defined kind |
| 48 | 8 | exact secret length |
| 56 | 8 | flags, exactly zero |
| 64 | 32 | exact vault ID |
| 96 | 32 | exact credential RID |
| 128 | `C` | secret followed by canonical zero padding |

All numeric fields are unsigned 64-bit big-endian values whose high bit must
be clear when admitted into a Forth cell. A present record has a secret length
from 1 through `C`. A tombstone has length zero, and its complete secret
capacity is zero. Noncanonical padding, unknown state, nonpositive kind,
unsupported version or flags, a generation mismatch, or an identity mismatch
is rejected.

The plaintext is sealed with `security/sealed-record.f`. The sealed-record
purpose is fixed to ASCII `AKCVLT01`, its revision is the VFS snapshot
generation, its key ID is the configured key ID, and its record ID is:

```text
binding-id = vault-id XOR credential-rid
```

The authenticated plaintext repeats the exact vault ID and credential RID.
Consequently, moving a valid file to another RID path or another vault does
not make it a valid credential there, even when both vaults use the same root
key. The outer VFS snapshot CRCs detect storage damage; AES-256-GCM provides
the security boundary.

The implementation uses the Megapad facilities exposed through Akashic:

- `CVAULT-RID-NEW` obtains all 32 RID bytes from `ENTROPY-FILL`.
- Every seal obtains a fresh 32-byte salt through `ENTROPY-FILL`.
- Sealed records derive keys with HKDF-HMAC-SHA-256 and use the checked
  hardware SHA-256 and AES-256-GCM paths.

There is no software random source, software cipher, all-zero RID or salt,
weak fallback, or alternate record format. The vault never stores a root key.
Ordinary hardware-entropy unavailability returns `CVAULT-S-ENTROPY`. If the
architectural entropy service throws while generating a RID, the vault wipes
the complete RID destination, releases its busy ownership, and rethrows the
original exception instead of misreporting it as ordinary unavailability. An
out-of-domain returned entropy status is a nonblocking `CVAULT-S-PLATFORM`
contract failure; RID generation never creates a RID-less recovery block.

## RID paths and shard topology

`RID-SIZE` is 32 bytes. The complete RID is encoded collision-free as 64
lowercase hexadecimal characters split across three VFS components:

```text
ROOT/<first 10 RID bytes as 20 hex>/<next 11 as 22 hex>/<last 11 as 22 hex>
```

Each RID therefore names one independent snapshot file. `ROOT` must be an
absolute canonical path no longer than `CVAULT-ROOT-MAX` bytes. `/` is valid;
other roots must not end in `/`. Every existing root component must be from 1
through 23 bytes and cannot be `.` or `..`.

The root must already exist and resolve, without following its final
component, to a directory. The vault never creates or chooses the trusted
root. `CVAULT-CREATE` creates or verifies the two shard directories
sequentially, rejects file and symbolic-link collisions, and performs
`VFS-SYNC` before credential publication. Operations on an existing RID do
not manufacture missing topology; a missing shard is recovery state.

```forth
CVAULT-PATH
  ( rid destination capacity vault -- written status )
```

`CVAULT-PATH` computes the exact path without accessing the credential file
and without appending a NUL byte. On success, only the first `written` bytes
are authoritative. With the maximum root, the longest path is 254 bytes. The
RID, complete output
capacity, vault descriptor, backing store, and registered private spans must
have valid nonoverlapping ownership. Path inspection is available for an idle
valid vault, including a blocked vault, but returns `CVAULT-S-BUSY` during an
active operation.

`CVAULT-RID-NEW ( destination vault -- status )` writes one random nonzero
RID that differs from the vault ID. It does not reserve a file or remember the
RID. The caller must retain the RID durably and handle the extremely unlikely
`CVAULT-CREATE` conflict by generating another RID. A caller-supplied RID must
also be nonzero and cannot equal the vault ID because that would produce an
all-zero binding ID.

## Geometry

The public geometry words are:

```forth
CVAULT-CONFIG-SIZE             ( -- 104 )
CVAULT-SIZE                    ( -- 3480 )
CVAULT-PLAINTEXT-HEADER-SIZE   ( -- 128 )
CVAULT-SECRET-CAPACITY-MAX     ( -- 65408 )
CVAULT-ROOT-MAX                ( -- 187 )

CVAULT-PLAINTEXT-SIZE          ( secret-capacity -- plaintext-u|0 )
CVAULT-RECORD-SIZE             ( secret-capacity -- record-u|0 )
CVAULT-BACKING-SIZE            ( secret-capacity -- backing-u|0 )
```

A secret capacity must be from 1 through
`CVAULT-SECRET-CAPACITY-MAX`. The three size functions return zero for an
invalid capacity. `CVAULT-BACKING-SIZE` includes the exact VFS snapshot
scratch, a loaded sealed record, fixed plaintext, and complete sealed-record
workspace. Allocate exactly that many caller-owned bytes; a larger or smaller
configured backing length is rejected.

The vault descriptor and backing store are address-bound initialized
objects. Keep both at stable addresses for the complete initialized lifetime
and do not copy their bytes.

## Configuration

Allocate and clear one `CVAULT-CONFIG-SIZE` descriptor:

```forth
CVAULT-CONFIG-CLEAR  ( config -- status )
```

The field accessors return cell addresses:

| Accessor | Value stored in the cell |
| --- | --- |
| `CVAULT-C.ROOT` | address of the canonical root bytes |
| `CVAULT-C.ROOT-U` | exact root length |
| `CVAULT-C.SECRET-CAPACITY` | fixed per-record secret capacity |
| `CVAULT-C.BACKING` | address of the caller-owned backing store |
| `CVAULT-C.BACKING-U` | exact result of `CVAULT-BACKING-SIZE` |
| `CVAULT-C.VFS` | initialized VFS descriptor |
| `CVAULT-C.VAULT-ID` | address of a nonzero 32-byte vault ID |
| `CVAULT-C.KEY-ID` | address of a nonzero 32-byte key-selection ID |
| `CVAULT-C.RESOLVER-XT` | nonzero sealed-record root-key resolver |
| `CVAULT-C.RESOLVER-CONTEXT` | opaque resolver context |
| `CVAULT-C.FLOOR-READ-XT` | optional rollback-floor read callback |
| `CVAULT-C.FLOOR-ADVANCE-XT` | optional rollback-floor advance callback |
| `CVAULT-C.FLOOR-CONTEXT` | opaque floor-provider context |

`CVAULT-INIT ( config vault -- status )` qualifies every owned span, rejects
forbidden overlap, copies the root, vault ID, key ID, callbacks, and scalar
configuration into the vault, initializes and seals its fixed VFS snapshot
specification, and verifies the trusted root. The VFS descriptor, vault
descriptor, and backing store must be mutually disjoint and remain valid and
stable. The configured root and IDs must not overlap mutable vault, backing,
or VFS storage.

The root-key resolver is mandatory. Rollback protection is optional, but its
two callbacks are atomic as configuration: both must be zero or both must be
nonzero. Once initialization succeeds, the caller may clear or reuse the
configuration descriptor and the source root/ID buffers; the vault owns
copies. Objects reachable through resolver and floor contexts remain the
caller's responsibility and must stay available for the initialized
lifetime.

Before calling a root-key resolver, floor provider, secret consumer, or VFS
binding during namespace traversal, the module saves the complete vault
descriptor in private storage. It restores that snapshot and returns
`CVAULT-S-INTERNAL` if external code mutates any descriptor byte. Reentrant
mutating vault calls return `CVAULT-S-BUSY` while such a frame is active.
Callback ABI violations that do not mutate the descriptor retain their
documented `CVAULT-S-CALLBACK` result.

`CVAULT-FINI ( vault -- status )` finalizes any retained snapshot lifecycle,
wipes the complete backing store and vault descriptor, and invalidates the
object. It does not unlink a credential, remove directories, clear an
external floor, or revoke anything. It returns `CVAULT-S-BUSY` during an
active operation and leaves the object intact if snapshot finalization fails.

## Root-key resolver ABI

`CVAULT-C.RESOLVER-XT` uses the exact generic sealed-record contract:

```forth
( key-id 32 consumer-xt consumer-context resolver-context -- status )
```

It must either:

1. return `SEALED-RECORD-S-KEY` without calling the consumer; or
2. call the consumer exactly once as
   `( root-key 32 consumer-context -- status )` and return that exact status.

The root key is a synchronous callback-scoped borrow. It must be exactly 32
caller-qualified bytes with the ownership and disjointness required by
`sealed-record.f`. The resolver must not retain, publish, clear, or replace
the opaque consumer context. Callback count, stack shape, returned status,
context identity, staged key/record IDs, and the complete vault descriptor
are checked. A missing key maps to `CVAULT-S-LOCKED`; a resolver throw or
stack/return contract violation maps to `CVAULT-S-CALLBACK`; descriptor
mutation maps to `CVAULT-S-INTERNAL`. `CVAULT-S-LOCKED` is not latched as
storage damage, so the caller may unlock, reconstruct, or reauthorize its key
provider and retry the same RID.

The resolver owns unlock, hardware-keystore, user-presence, and reboot policy.
For credentials to survive reboot, it must recover the root key selected by
the same key ID without asking the vault to persist that key.

## Optional rollback-floor ABI

Without a floor provider, VFS snapshots provide crash-safe optimistic
publication and sealed records provide integrity and confidentiality, but an
attacker who can restore an older valid file can restore its older valid
generation.

The optional floor provider closes that gap. Its callbacks are synchronous:

```forth
\ FLOOR-READ-XT
( vault-id 32 rid 32 floor-context -- generation status )

\ FLOOR-ADVANCE-XT
( vault-id 32 rid 32 generation floor-context -- status )
```

Both callbacks must consume their arguments and return exactly the documented
cells. Status must belong to the `CVAULT-S-*` vocabulary, except
`CVAULT-S-REVOKED`, which is reserved exclusively for an authenticated
credential tombstone and is rejected at the floor boundary. A successful read
returns a nonnegative generation. The ID arguments are vault-owned staged
copies, and callbacks must treat them as immutable borrows. A throw, malformed
stack, invalid or reserved status, or negative successful floor maps to
`CVAULT-S-CALLBACK`. Mutation of an ID or any other vault-descriptor byte is
restored and maps to `CVAULT-S-INTERNAL`.

The provider must key its durable monotonic value by the exact pair
`(vault-id, rid)`. `FLOOR-ADVANCE-XT` must return `CVAULT-S-OK` only after the
floor is durably at least the requested generation and must never lower it.
An unseen pair has floor zero and must be reported as
`0 CVAULT-S-OK`; reporting it as `CVAULT-S-ABSENT` prevents initial creation.

On load, the vault reads the snapshot generation and then reads the floor
before asking for the root key. A snapshot generation below the floor is
`CVAULT-S-ROLLBACK`. After successful sealed-record authentication and
plaintext validation, a generation above the floor causes the parsed
plaintext to be wiped before the floor callback runs. The vault advances the
floor, then resolves the key and authenticates the sealed record again before
publishing the credential to the caller. On save, the credential snapshot is
made durable first and the floor is then advanced. Failure of that
post-publication advance is `CVAULT-S-RECOVERY`, because the file may be newer
than the trusted floor and the operation cannot safely report ordinary
success.

## Credential lifecycle

Creation, replacement, and revocation use optimistic generations:

```forth
CVAULT-CREATE
  ( rid kind secret-a secret-u vault -- generation status )

CVAULT-REPLACE
  ( rid expected-generation secret-a secret-u vault
    -- generation status )

CVAULT-REVOKE
  ( rid expected-generation vault -- generation status )
```

`CVAULT-CREATE` requires a positive `kind`, a nonempty secret no larger than
the configured capacity, and an absent target. It saves with expected
generation zero; the first successful generation is therefore one.

`CVAULT-REPLACE` requires a positive expected generation equal to the fully
loaded, authenticated current generation. It preserves the record's existing
kind and replaces only the secret. `CVAULT-REVOKE` has the same generation
check, preserves kind, and publishes a tombstone with no secret. A stale
expected generation is `CVAULT-S-CONFLICT` and never overwrites the target.

Success returns the newly committed positive generation followed by
`CVAULT-S-OK`. Every returned failure has generation zero. The source secret
is borrowed and never wiped by the vault; the caller must clear its own source
after a successful durable handoff.

Revocation never unlinks the file and a RID is never reusable. A tombstone
prevents an authenticated old present record from being mistaken for current
state when rollback protection is configured. Replacing or revoking an
already revoked RID returns `CVAULT-S-REVOKED`; resurrection requires a new
RID and an explicit new application association.

Metadata is authenticated:

```forth
CVAULT-METADATA
  ( rid vault -- generation state kind secret-u status )
```

`CVAULT-S-OK` returns present metadata.
`CVAULT-S-REVOKED` returns the authenticated tombstone generation, state,
kind, and zero secret length. Every other status returns four zero cells
before status. There is no unauthenticated header-inspection shortcut.

## Synchronous secret borrowing

Secrets are exposed only through a synchronous callback:

```forth
CVAULT-WITH
  ( rid consumer-xt consumer-context vault
    -- generation kind consumer-result status )
```

The consumer ABI is:

```forth
( secret-a secret-u kind generation consumer-context -- consumer-result )
```

After complete snapshot validation, floor reconciliation, root-key
resolution, AES-GCM authentication, and plaintext validation, the vault
copies exactly `secret-u` bytes into a transient borrow buffer and wipes the
fixed plaintext before invoking the consumer. It wipes the complete borrow
buffer immediately after the callback returns or throws.

The callback must consume its five arguments and return exactly one cell.
`consumer-result` is application-defined and does not have to be a vault
status. A callback throw, stack-contract violation, or corruption of the
retained owner/canary frame returns `0 0 0 CVAULT-S-CALLBACK`. Mutation of
the vault descriptor is restored and returns `0 0 0 CVAULT-S-INTERNAL`. On
normal return, the result is reported with the authenticated generation and
kind followed by `CVAULT-S-OK`. Every vault failure, including
`CVAULT-S-REVOKED`, returns three zero cells before status and never calls the
consumer.

The secret address is valid only during the callback. The consumer must not
retain, mutate, publish, or clear it. The vault remains busy and the
module-wide recursive guard remains held during the borrow; recursive access
to the same vault returns `CVAULT-S-BUSY`.

## Blocking and recovery

The vault latches these statuses as blocking:

```text
CVAULT-S-CORRUPT
CVAULT-S-UNSUPPORTED
CVAULT-S-IO
CVAULT-S-RECOVERY
CVAULT-S-ROLLBACK
CVAULT-S-INTERNAL
```

A snapshot-finalization failure also becomes blocking
`CVAULT-S-RECOVERY`. Blocking preserves the active RID, canonical path, and
per-RID snapshot lifecycle rather than clearing evidence or treating the
credential as absent. Later ordinary credential operations return the latched
status until recovery succeeds or the caller abandons the object with
`CVAULT-FINI`.

```forth
CVAULT-VALID?        ( vault -- flag )
CVAULT-BLOCKED?      ( vault -- flag )
CVAULT-LAST-STATUS@  ( vault -- status )
CVAULT-SECRET-CAPACITY@
  ( vault -- secret-capacity status )

CVAULT-RECOVER
  ( expected-rid vault -- generation state status )
```

`CVAULT-VALID?` remains true for a structurally valid blocked vault.
`CVAULT-BLOCKED?` returns false for an invalid descriptor, while
`CVAULT-LAST-STATUS@` returns `CVAULT-S-INVALID` for one.
`CVAULT-SECRET-CAPACITY@` returns the immutable configured capacity for an
idle valid vault, including a blocked vault. It returns `CVAULT-S-BUSY`
during an active operation and never exposes backing-store geometry or
secret bytes.

`CVAULT-RECOVER` is valid only for a blocked vault and atomically requires
`expected-rid` to equal the RID retained by the failed operation. A different
valid RID returns `0 0 CVAULT-S-CONFLICT`; invalid RID geometry is rejected.
Either rejection leaves the vault blocked and preserves its retained RID,
path, recovery evidence, and `CVAULT-LAST-STATUS@`.

For the matching RID, recovery finalizes the retained snapshot descriptor,
re-verifies the root and shard topology, initializes a fresh per-RID snapshot
lifecycle, runs VFS replacement recovery, and then reloads, floor-checks,
authenticates, and validates the credential. A present credential returns its
generation, `CVAULT-STATE-PRESENT`, and `CVAULT-S-OK`. An authenticated
tombstone returns its generation, `CVAULT-STATE-TOMBSTONE`, and
`CVAULT-S-REVOKED`. Either result clears the block and closes the active
per-RID lifecycle. Any other recovery result returns `0 0 status` and leaves
the vault blocked for a later retry or administrative abandonment. If that
returned status is not itself a blocking status, the retained
`CVAULT-LAST-STATUS@` is normalized to `CVAULT-S-RECOVERY` so the descriptor
remains structurally valid and retryable; an invalid status is retained as
`CVAULT-S-INTERNAL`.

Recovery applies to the one RID retained by the failed operation. It is not a
filesystem scan, RID index, orphan collector, key recovery mechanism, or
rollback-floor repair service. After reboot, callers reinitialize the vault
and access the durably retained RID; a detected VFS replacement problem can
then block that operation and be resolved with `CVAULT-RECOVER`.

## Status values

`CVAULT-STATUS-VALID? ( status -- flag )` recognizes:

| Status | Meaning |
| --- | --- |
| `CVAULT-S-OK` | The requested operation completed |
| `CVAULT-S-INVALID` | Invalid object, scalar, RID, kind, callback, canonical path, or forbidden alias |
| `CVAULT-S-CAPACITY` | Secret/output capacity, configured backing size, or next generation is out of range |
| `CVAULT-S-ABSENT` | The exact credential target is proven absent |
| `CVAULT-S-REVOKED` | A valid authenticated tombstone is current |
| `CVAULT-S-CONFLICT` | Optimistic expected generation does not match |
| `CVAULT-S-LOCKED` | The configured resolver cannot supply the selected root key |
| `CVAULT-S-CALLBACK` | Resolver, floor, or consumer callback contract failed |
| `CVAULT-S-ENTROPY` | Checked RID or sealed-record salt acquisition failed |
| `CVAULT-S-CRYPTO` | Key derivation or AES-GCM failed for a reason other than authentication |
| `CVAULT-S-AUTH` | AES-GCM authentication failed |
| `CVAULT-S-CORRUPT` | Snapshot, sealed record, plaintext, identity, padding, or directory type is corrupt |
| `CVAULT-S-UNSUPPORTED` | A record version, format, flag, or storage capability is unsupported |
| `CVAULT-S-IO` | VFS I/O or contained topology execution failed |
| `CVAULT-S-RECOVERY` | Publication, cleanup, namespace, floor advancement, or replacement state is uncertain |
| `CVAULT-S-BUSY` | The vault or a contained storage operation is already active |
| `CVAULT-S-ROLLBACK` | Snapshot generation is below the trusted external floor |
| `CVAULT-S-RANGE` | A required caller span has invalid physical geometry |
| `CVAULT-S-PROTECTED` | A caller span intersects protected platform memory |
| `CVAULT-S-PLATFORM` | Caller-span qualification or a platform service contract failed |
| `CVAULT-S-INTERNAL` | An unexpected internal result was contained |

Authentication failure and missing-key status are deliberately distinct from
format/storage corruption. They do not reveal root-key bytes or plaintext.

## Durability and ownership boundary

Credential publication inherits the selected VFS binding's durability
contract through `vfs-fixed-snapshot.f` and `vfs-replace.f`. A persistent
binding must implement its file, directory, volume-flush, and `SYNCFS`
barriers correctly. `VFS-RAM-BINDING` exercises operation ordering and
recovery mechanics but does not survive power loss.

For reboot survival, the caller must durably retain:

- the opaque credential RID and its application association;
- the same vault ID, key ID, root path, and secret-capacity configuration;
- a persistent VFS medium with completed durability barriers;
- a resolver capable of recovering or unlocking the selected root key; and
- when configured, the monotonic rollback floor for the exact vault/RID pair.

The caller must keep the VFS mounted and the resolver/floor context objects
valid while the vault is initialized. Public caller spans are physically
qualified and hostile overlap with vault, backing, VFS, or registered private
state is rejected. Source bytes remain caller-owned and must stay stable until
the synchronous call returns. Namespace operations also keep the selected VFS
and saved current-directory state in module-private storage, and restore the
prior selector before returning.

## Deliberate limitations

- There is no credential enumeration, RID-to-account index, orphan
  collection, automatic RID publication, or filesystem migration.
- There is no delete operation. Revocation is an authenticated tombstone and
  `CVAULT-FINI` only wipes volatile library state.
- Secret capacity, root, vault ID, key ID, and record format are fixed for an
  initialized vault. Key rotation and capacity migration require an explicit
  higher-level procedure using a new configuration and, where appropriate, a
  new RID.
- Without both floor callbacks, confidentiality, integrity, optimistic
  concurrency, and crash recovery remain available, but hostile rollback of
  an older valid snapshot is not detected.
- The vault does not create the trusted root, configure filesystem
  permissions, provision a root key, enroll hardware, prompt a user, or
  repair an external floor provider.
- `kind` is opaque and positive; expiry, scopes, issuer, account identity,
  refresh policy, and credential syntax belong to higher generic or
  protocol-specific libraries.
- All public vault calls currently share one module guard. Distinct vault
  descriptors own disjoint storage and RID state, but calls are serialized at
  this API boundary.
- Every resolver, floor, and secret-consumer interaction is synchronous.
  Callback-owned pointers are borrows and cannot be retained for asynchronous
  work.
