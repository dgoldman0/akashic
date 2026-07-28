# Sealed records

`security/sealed-record.f` is the generic authenticated-encryption boundary
for small durable secrets. It turns one nonempty caller-owned byte string into
one exact, versioned record and opens that record only when its format,
caller-expected identity, and AES-GCM authentication all agree.

The module owns no filesystem, storage path, root key, account, OAuth,
AT Protocol, PDS, Streams, UI, or application policy. It does not allocate,
perform I/O, choose a durable slot, assign an identity or revision, retain
plaintext, or make a write crash-safe. Those responsibilities belong to the
credential vault or other storage owner above it.

The cryptographic implementation uses the Megapad facilities already exposed
through Akashic:

- `ENTROPY-FILL` obtains each record's salt from the checked architectural
  entropy service.
- `HMAC-SHA256` performs RFC 5869 derivation over the checked hardware
  SHA-256 path.
- `AES-GCM-SEAL` and `AES-GCM-OPEN` use the Megapad AES-256-GCM engine.

There is no software random source, software cipher, weak-key fallback, or
alternate record format.

## Exact record format

The record is:

```text
160-byte canonical header || ciphertext[data-u] || 16-byte GCM tag
```

Its exact size is `176 + data-u`. `data-u` must be from 1 through 65,536, so
the complete record is from 177 through 65,712 bytes.

Every numeric field is an unsigned 64-bit big-endian value. Values admitted
into a Forth cell must have their high bit clear. Purpose and revision must be
positive. The header is:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII magic `AKSSEAL1` |
| 8 | 8 | version, exactly `1` |
| 16 | 8 | header size, exactly `160` |
| 24 | 8 | exact total record size, `176 + data-u` |
| 32 | 8 | plaintext/ciphertext size, 1 through 65,536 |
| 40 | 8 | caller-defined positive purpose |
| 48 | 8 | caller-defined positive revision |
| 56 | 8 | flags/reserved, exactly zero |
| 64 | 32 | nonzero opaque key ID |
| 96 | 32 | nonzero opaque record ID |
| 128 | 32 | fresh nonzero salt |
| 160 | `data-u` | ciphertext |
| `160 + data-u` | 16 | GCM authentication tag |

`OPEN` requires the supplied input length, the encoded total size, and the
size derived from `data-u` to be exactly equal. Truncation and trailing bytes
are both `SEALED-RECORD-S-FORMAT`. Other magic values, versions, header
sizes, nonzero flags, out-of-range lengths, negative-cell encodings, and an
all-zero salt are also format failures. There is no compatibility reader or
future-version fallback.

Purpose, revision, key ID, and record ID are compared with the independent
values in the caller's descriptor before a root key is resolved. A mismatch
is `SEALED-RECORD-S-MISMATCH`. These checks avoid unnecessary key access, but
the record header remains untrusted until GCM authentication succeeds.
There is deliberately no public unauthenticated header-inspection API; a
durable owner keeps the expected identity and key-selection metadata outside
the record.

## Key derivation and encryption

Each successful `SEAL` obtains a new 32-byte salt. Given the resolver's exact
32-byte root key, RFC 5869 HKDF-SHA-256 is:

```text
info = ASCII("Akashic sealed record AES-256-GCM v1")  # 36 bytes

PRK = HMAC-SHA256(salt, root-key)
T1  = HMAC-SHA256(PRK, info || 0x01)
T2  = HMAC-SHA256(PRK, T1 || info || 0x02)

AES-256 key = T1
96-bit IV   = first 12 bytes of T2
```

The IV is derived and is not stored separately. The complete 160-byte header,
including the salt and all identity and length fields, is AES-GCM additional
authenticated data. Ciphertext has the same length as plaintext and the tag
is the full 128-bit GCM tag.

Salt freshness makes the derived key/IV pair per-record. Callers must not
construct records by copying or editing a salt, header, ciphertext, or tag.
Any authenticated field change requires resealing with fresh entropy.

## Public API

Geometry and status inspection:

```forth
SEALED-RECORD-ID-SIZE          ( -- 32 )
SEALED-RECORD-ROOT-KEY-SIZE    ( -- 32 )
SEALED-RECORD-SALT-SIZE        ( -- 32 )
SEALED-RECORD-HEADER-SIZE      ( -- 160 )
SEALED-RECORD-TAG-SIZE         ( -- 16 )
SEALED-RECORD-OVERHEAD         ( -- 176 )
SEALED-RECORD-DATA-MAX         ( -- 65536 )
SEALED-RECORD-SIZE-MAX         ( -- 65712 )
SEALED-RECORD-DESCRIPTOR-SIZE  ( -- 80 )
SEALED-RECORD-WORKSPACE-SIZE   ( -- 66568 )

SEALED-RECORD-SIZE             ( data-u -- record-u|0 )
SEALED-RECORD-STATUS-VALID?    ( status -- flag )
```

`SEALED-RECORD-SIZE` returns zero for zero, negative, or over-capacity data
lengths.

Descriptor and workspace management:

```forth
SEALED-RECORD-DESCRIPTOR-CLEAR ( descriptor -- status )
SEALED-RECORD-WORKSPACE-CLEAR  ( workspace -- status )
```

The descriptor is 80 caller-owned bytes. Its field accessors return the
address of one cell:

```forth
SEALED-RECORD-D.INPUT
SEALED-RECORD-D.INPUT-U
SEALED-RECORD-D.KEY-ID
SEALED-RECORD-D.RECORD-ID
SEALED-RECORD-D.PURPOSE
SEALED-RECORD-D.REVISION
SEALED-RECORD-D.RESOLVER-XT
SEALED-RECORD-D.RESOLVER-CONTEXT
SEALED-RECORD-D.OUTPUT
SEALED-RECORD-D.OUTPUT-CAP
```

Operations return the number of bytes published followed by status:

```forth
SEALED-RECORD-SEAL  ( descriptor workspace -- written status )
SEALED-RECORD-OPEN  ( descriptor workspace -- written status )
```

Every normally returned non-`OK` result has `written = 0`.

For `SEAL`, `INPUT` is plaintext and `INPUT-U` is its length. `OUTPUT` names
the record destination, and `OUTPUT-CAP` must be at least
`SEALED-RECORD-SIZE(INPUT-U)` and no greater than
`SEALED-RECORD-SIZE-MAX`. Success returns the exact record size.
Bytes in a larger output capacity beyond that exact size are unchanged.

For `OPEN`, `INPUT` is the exact complete record and `INPUT-U` is its exact
length. `OUTPUT` is the plaintext destination. `OUTPUT-CAP` must be nonzero,
no greater than `SEALED-RECORD-DATA-MAX`, and at least as large as the
authenticated `data-u`. Success returns `data-u`. Before plaintext
publication, the complete output capacity is zeroed; therefore a successful
shorter open cannot leave a previous secret tail beyond `written`.

Callers must use only the first `written` bytes and promptly clear the
complete plaintext output capacity when the secret is no longer needed.

## Statuses

| Status | Meaning |
| --- | --- |
| `SEALED-RECORD-S-OK` | Operation completed and published its exact result |
| `SEALED-RECORD-S-INVALID` | Invalid scalar, pointer/length shape, zero ID, nonpositive purpose/revision, or unsupported capacity |
| `SEALED-RECORD-S-CAPACITY` | A valid destination is too small for the derived result |
| `SEALED-RECORD-S-ALIAS` | Two spans with distinct ownership roles overlap |
| `SEALED-RECORD-S-BUSY` | The same workspace is already in an admitted operation |
| `SEALED-RECORD-S-KEY` | The resolver has no key or supplied an inadmissible root-key borrow |
| `SEALED-RECORD-S-CALLBACK` | Resolver throw, stack-contract violation, invalid result, wrong call count, or nonfaithful return |
| `SEALED-RECORD-S-ENTROPY` | Checked entropy acquisition failed or produced the prohibited all-zero salt |
| `SEALED-RECORD-S-CRYPTO` | HKDF or AES-GCM failed for a reason other than authentication |
| `SEALED-RECORD-S-AUTH` | AES-GCM authentication failed |
| `SEALED-RECORD-S-FORMAT` | Record bytes are not the exact canonical version-1 format |
| `SEALED-RECORD-S-MISMATCH` | Authenticated identity candidates differ from the caller's expected values |
| `SEALED-RECORD-S-RANGE` | A public caller span is outside the checked caller window |
| `SEALED-RECORD-S-PROTECTED` | A public caller span intersects protected memory |
| `SEALED-RECORD-S-PLATFORM` | Physical caller-span qualification could not be completed |
| `SEALED-RECORD-S-INTERNAL` | An unexpected computation throw was contained before ordinary publication |

An invalid root-key span is deliberately reported as `KEY`, not as a detailed
physical-span status. Root-key-provider geometry is private to the resolver
boundary.

## Resolver contract

The descriptor's resolver is called synchronously as:

```forth
( key-id 32 consumer-xt consumer-context resolver-context -- status )
```

It has exactly two valid behaviors:

1. Do not call the consumer and return `SEALED-RECORD-S-KEY`.
2. Call the consumer exactly once as
   `( root-key 32 consumer-context -- status )`, then return that exact
   consumer status.

The root key is a callback-scoped borrow. It must be exactly 32 bytes,
caller-qualified, and disjoint from the descriptor, workspace, input, key ID,
record ID, and complete output capacity. It is neither retained nor copied
into the record. Derived PRK, AES key, IV material, and lower crypto scratch
live only in the operation workspace and are wiped on an admitted returned
path.

The resolver must consume its five arguments and return exactly one cell. A
canary and saved data-stack depth enforce this shape. Calling the consumer
more than once, returning a different status from the consumer, returning an
out-of-range status, or throwing maps to `SEALED-RECORD-S-CALLBACK`.
The original opaque consumer context is retained beneath those arguments and
must match exactly before the consumer treats it as an address; substituting
another context also maps to `SEALED-RECORD-S-CALLBACK`.

`consumer-context` is an opaque capability owned by this module. Resolver code
must pass it through unchanged and must not inspect, retain, publish, clear,
or use it to reenter this module. The same applies to object pointers
reachable through `resolver-context`: they must not mutate any span owned by
the active call. In particular, `SEALED-RECORD-WORKSPACE-CLEAR` is an
administrative wipe and must not be called on an active workspace.

The resolver does not establish persistence. After reboot, the higher key
provider must unlock or reconstruct the root key selected by the exact key
ID. If it cannot, it must return `SEALED-RECORD-S-KEY`; this module has no
password prompt, hardware-enrollment policy, recovery key, or reauthorization
fallback.

## Span ownership, aliasing, and BUSY

The descriptor, workspace, input, output capacity, key ID, and record ID are
all required, nonempty, caller-qualified spans. They must be pairwise
disjoint; exact adjacency is allowed. In particular, expected IDs cannot
point into the untrusted input record, so identity comparison cannot become
tautological.

The module snapshots descriptor pointer and scalar values before invoking the
resolver, but all external byte spans remain borrowed. One owner must keep the
descriptor, workspace, input, expected IDs, output, resolver, and reachable
resolver context stable and exclusively owned until the public operation
returns or throws.

An admitted operation marks its workspace busy before invoking entropy, the
resolver, or crypto. A nested `SEAL` or `OPEN` with that workspace returns
`SEALED-RECORD-S-BUSY` without clearing the active transaction. Distinct
workspaces provide independent retained scratch, while the guarded lower
SHA-256 and AES engines serialize their own hardware transactions.

Rejected preflight calls do not clear the workspace or change the output.
Callers may explicitly use `SEALED-RECORD-WORKSPACE-CLEAR` when no operation
is active.

## Publication, cleanup, and THROW

`SEAL` builds the complete header, ciphertext, and tag in private workspace
staging. A returned entropy, key, callback, crypto, or other computation
failure leaves the caller's output unchanged. Successful publication:

1. invalidates the destination's eight-byte magic;
2. copies the remainder of the exact record; and
3. writes the new magic last.

This is an in-memory publication discipline, not a filesystem transaction.
Persist exactly the returned `written` bytes through an atomic durable owner.

`OPEN` checks shape and expected identity, resolves the root key, and
authenticates into private staging. It does not copy plaintext to the caller
until GCM succeeds. A normally returned `AUTH`, `FORMAT`, `MISMATCH`, `KEY`,
or other failure leaves the plaintext destination unchanged.

Every admitted normally returned path wipes the complete workspace, including
header copies, ciphertext/plaintext staging, PRK, AES key, IV derivation,
HMAC workspace, AES descriptor, and AES workspace. Successful `OPEN` also
zeroes its complete caller output capacity before publishing the authenticated
plaintext prefix.

Unexpected computation throws before publication are contained as
`SEALED-RECORD-S-INTERNAL`, followed by workspace cleanup. Publication and
cleanup throws are different: the implementation does not return a status
that would falsely claim definite publication or containment.

After a publication throw, output cleanup and workspace cleanup are each
attempted independently. For `SEAL`, output cleanup invalidates the magic; for
`OPEN`, it wipes the complete plaintext output capacity. If cleanup itself
throws, exception precedence is:

```text
workspace-cleanup exception
    > output-cleanup exception
    > original publication exception
```

Thus a cleanup fault cannot be hidden behind the earlier publication fault.
A successful publication followed by a workspace-wipe throw also escapes as a
throw: callers must treat any thrown operation as indeterminate and quarantine
all involved storage until external ownership and cleanup are re-established.

## Key rotation and durable ownership

`key-id` is an opaque identifier, not key material. A resolver may keep
several root keys available at once. To rotate:

1. provision a fresh root key under a fresh nonzero key ID;
2. reseal each live secret with that key ID and a fresh generated salt;
3. durably replace and verify each record; and
4. retire the old root key only after no retained record depends on it.

Editing a key ID in place is not rotation: it changes authenticated header
bytes and causes authentication failure. If the old key is removed too early,
old records become unavailable with `SEALED-RECORD-S-KEY`.

The record ID, purpose, and revision are authenticated bindings supplied by
the storage owner. A typical vault uses record ID as the opaque credential
RID, purpose as a record-type/domain discriminator, and revision as the
expected generation. This codec requires positive values but does not assign
IDs, compare two revisions, enforce monotonicity, maintain tombstones, or
prevent ID reuse.

An old, correctly authenticated record remains cryptographically valid.
Therefore revision does not by itself prevent rollback. The durable owner must
compare against trusted current metadata. Resistance to a hostile storage
rollback requires a monotonic floor held outside the rollbackable store. In
the absence of such a provider, the system can claim authenticated records
and crash consistency, not adversarial rollback protection.

Likewise, the magic-last memory publication does not provide durable atomicity.
The storage layer must write an inactive slot or equivalent atomic snapshot,
flush it, recover split or interrupted writes, publish the new generation only
after verification, and retain or revoke old records according to its policy.

## Independent reference vector

This vector exercises the exact header, RFC 5869 expansion, AES-256-GCM AAD,
ciphertext, and tag. Hex ranges below are inclusive consecutive byte values;
the root and plaintext have equal bytes but occupy separate spans.

```text
root key:  000102030405060708090a0b0c0d0e0f
           101112131415161718191a1b1c1d1e1f

key ID:    202122232425262728292a2b2c2d2e2f
           303132333435363738393a3b3c3d3e3f

record ID: 404142434445464748494a4b4c4d4e4f
           505152535455565758595a5b5c5d5e5f

salt:      a0a1a2a3a4a5a6a7a8a9aaabacadaeaf
           b0b1b2b3b4b5b6b7b8b9babbbcbdbebf

plaintext: 000102030405060708090a0b0c0d0e0f
           101112131415161718191a1b1c1d1e1f

purpose:   0x0102030405060708
revision:  0x1112131415161718
data-u:    32
total-u:   208
```

The exact 160-byte header is the concatenation of these lines:

```text
414b535345414c31000000000000000100000000000000a000000000000000d0
0000000000000020010203040506070811121314151617180000000000000000
202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f
404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f
a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf
```

Intermediate and final values:

```text
PRK:
417e7502c38837c356dc6d3f1c84cfac0efea0e929628cb89ce52f74716620ad

T1 / AES-256 key:
12839ff96b75c11a3b9b2d579d116cc2e0a0383ff45d45990728dfcfd5229b86

T2:
f92c4cf60589a1c00f192d48e8e4ce61df83c08be56837ba220207c3df00dfb6

96-bit IV:
f92c4cf60589a1c00f192d48

ciphertext:
130072e2fedc9f7d2e04f4d01d0d1eb92204aa54255f59c27fcb38347ee1c87a

tag:
e332e8c1a2b877469db5472cda0843b7

SHA-256(header || ciphertext || tag):
895763a5dfd58652b4edb040277d4dbd39768fe66213ff3ab02b36251b690115
```

The vector was independently reproduced with RFC 5869 HKDF-SHA-256 and two
independent AES-GCM implementations. A qualification fixture can inject the
complete record into `OPEN` without replacing the production entropy source;
ordinary `SEAL` qualification should instead validate fresh-salt shape and
round-trip behavior.
