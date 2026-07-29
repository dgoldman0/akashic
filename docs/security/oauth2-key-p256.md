# OAuth P-256 Key Ownership

`akashic/security/oauth2/key-p256.f` owns the durable identity boundary for
OAuth client-authentication and DPoP P-256 keys. It generates private scalars
inside transient caller-owned workspace, commits typed records through the
credential vault, and resolves them into callback-scoped public identity.
Private scalars are never returned to an application callback.

The module is provider-neutral. It does not interpret an OAuth client
configuration, select a published JWK, construct an assertion or DPoP proof,
or own HTTP, AT Protocol, session, or application state.

## Public geometry

```forth
OAUTH2-P256-KEY-SLOT-SIZE          \ 80 bytes
OAUTH2-P256-KEY-BINDING-SIZE       \ 192 bytes
OAUTH2-P256-KEY-RECORD-SIZE        \ 336 bytes
OAUTH2-P256-KEY-KID-CAPACITY       \ 256 bytes
OAUTH2-P256-KEY-PUBLIC-SIZE        \ 65 bytes
OAUTH2-P256-KEY-THUMBPRINT-SIZE    \ 32 bytes
OAUTH2-P256-KEY-WORKSPACE-SIZE     \ 17879 bytes
```

The two roles are:

```forth
OAUTH2-P256-KEY-ROLE-CLIENT
OAUTH2-P256-KEY-ROLE-DPOP
```

Client-authentication and DPoP records use distinct public credential kinds.
The authenticated record also carries the exact role, so changing either the
vault kind or record role is a format failure.

## Provisioning and recovery

The caller first creates and durably retains a nonzero RID, for example with
`CVAULT-RID-NEW`. Provisioning never invents an unretained identifier:

```forth
OAUTH2-P256-KEY-PROVISION-CLIENT
  ( retained-rid kid kid-u vault slot-output workspace
    -- generation status )

OAUTH2-P256-KEY-PROVISION-DPOP
  ( retained-rid vault slot-output workspace
    -- generation status )
```

Client provisioning requires a nonempty opaque `kid` of at most 256 bytes.
DPoP records canonically have no `kid`; their callback view is `(0,0)`.
Both operations generate a fresh P-256 scalar, derive its public key and RFC
7638 thumbprint, create a generation-one credential, and publish an 80-byte
non-secret slot. Returned failure leaves generation zero.

The slot's role is written last as its validity marker. A fault after durable
creation but during slot publication is rethrown rather than mislabeled as a
returned failure. Because the caller already retained the RID, the slot is
recoverable after a fault or reboot:

```forth
OAUTH2-P256-KEY-SLOT-LOAD-CLIENT
OAUTH2-P256-KEY-SLOT-LOAD-DPOP
  ( retained-rid vault slot-output workspace -- generation status )
```

Slot loading authenticates the current vault record, enforces its exact role
and record shape, validates the private scalar by deriving its public key,
and reconstructs the current generation and thumbprint. It does not rotate,
replace, resurrect, or expose the key. Rotation uses a newly retained RID and
a newly generated key; revocation remains an explicit credential-vault
operation.

The complete owner workspace is wiped after every admitted normal outcome.
The private record scratch is never copied out. `P256-KEYGEN`,
`P256-PUBLIC-FROM-PRIVATE`, and the JWK thumbprint layer also apply their own
mandatory scratch cleanup.

## Canonical binding

One binding fits in `OAUTH2-CLIENT-CONFIG-BINDING-CAPACITY`:

```forth
OAUTH2-P256-KEY-BINDING-CLEAR  ( binding -- status )

OAUTH2-P256-KEY-BINDING-INIT
  ( client-slot|0 dpop-slot|0 binding -- status )

OAUTH2-P256-KEY-BINDING-PRESENCE@
  ( binding binding-u -- flags status )
```

`BINDING-INIT` requires an all-zero destination. A zero slot pointer means
that role is absent; at least one role must be present. A present slot carries
its exact role, a nonzero 32-byte RID, a positive generation, and a 32-byte
RFC 7638 thumbprint. An absent slot is 80 zero bytes. When both roles are
present, both the RIDs and thumbprints must differ. This prevents one private
identity, or two aliases of it, from serving simultaneously as the OAuth
client-authentication and DPoP key.

All integer fields in the 192-byte binding are nonnegative big-endian 64-bit
values:

```text
0    magic
8    version
16   total size
24   presence flags
32   client slot
112  DPoP slot
```

Each slot is:

```text
0    role
8    RID (32 bytes)
40   generation
48   RFC 7638 thumbprint (32 bytes)
```

The binding is address-free and canonical. It can therefore be copied as the
opaque binding in an immutable OAuth client configuration without embedding
a pointer or private key.

## Authenticated vault record

All integer fields use nonnegative big-endian 64-bit encoding. The exact
336-byte secret record has magic `"O2P256K1"`, version `1`, and this layout:

```text
0    magic
8    version
16   total size
24   role
32   kid length
40   flags
48   private scalar (32 bytes)
80   kid arena (256 bytes)
```

A client record sets the `kid` flag to `1`, carries a length from 1 through
256, and zero-pads the unused arena. A DPoP record has zero flags, zero `kid`
length, and an all-zero `kid` arena. The distinct vault kind and authenticated
role must agree before the scalar is accepted.

## Public identity borrowing

```forth
OAUTH2-P256-KEY-WITH-CLIENT
OAUTH2-P256-KEY-WITH-DPOP
  ( binding binding-u vault callback context workspace
    -- callback-result status )
```

The callback ABI is:

```forth
( kid-a kid-u public-a thumbprint-a context -- callback-result )
```

The client callback receives its exact copied `kid`. The DPoP callback
receives canonical `(0,0)`. `public-a` identifies the 65-byte uncompressed
SEC 1 key and `thumbprint-a` identifies the 32-byte RFC 7638 digest. All
three views are read-only and valid only until the callback returns.

Resolution first copies and validates a complete binding snapshot. Its internal
`CVAULT-WITH` consumer then checks the pinned generation, role-specific kind,
canonical authenticated record, private scalar, derived public key, and
thumbprint. It copies only public material into the owner workspace and
returns. The application callback is invoked only after `CVAULT-WITH` has
finished, wiped the private borrow, and released the vault's busy state.
Caller code may therefore perform a later, separate vault operation; it never
runs while private bytes are borrowed.

Each active owner call requires exclusive use of its complete workspace. A
callback that resolves the other role must supply a second disjoint owner
workspace and let that nested resolution finish before returning.

The callback runs exactly once on success and must consume its five arguments
and return exactly one cell. A throw, extra result, missing result, or stack
guard violation returns a zero result with
`OAUTH2-P256-KEY-S-CALLBACK`. Every earlier failure returns a zero result and
does not invoke the callback.

## Admission and cleanup

The complete workspace, retained RID, output slot, binding, and client `kid`
are physically admitted before the first write. The workspace, RID, slot,
and binding must be eight-byte aligned; the opaque `kid` may be byte-aligned.
Mutable outputs must not overlap any input or the workspace.

Provisioning and slot loading snapshot the admitted RID before durable vault
lookup or creation and use only that copy for both vault access and slot
publication. Resolution likewise uses only its validated binding snapshot.

Every operation that uses a vault also qualifies the complete owner workspace
and all external spans through `CVAULT-EXTERNAL-SPAN-STATUS`. This rejects
aliases of the live vault descriptor, backing store, VFS descriptor, vault
private storage, and dependency-private storage before key generation,
borrowing, or output publication.

Preflight failures leave the workspace and outputs unchanged. Once admitted,
normal success and returned failure wipe the complete owner workspace.
Unexpected operation, publication, or cleanup throws propagate; they are not
converted into a status that could conceal an ambiguous durable or output
effect.

## Status values

Use `OAUTH2-P256-KEY-STATUS-VALID? ( status -- flag )` before accepting an
arbitrary status cell.

| Status | Meaning |
| --- | --- |
| `OAUTH2-P256-KEY-S-OK` | The operation and any callback completed |
| `OAUTH2-P256-KEY-S-INVALID` | Invalid pointer, role, RID, binding shape, callback token, or argument |
| `OAUTH2-P256-KEY-S-CAPACITY` | `kid`, vault secret capacity, or another public bound is insufficient |
| `OAUTH2-P256-KEY-S-ALIAS` | A forbidden caller, output, workspace, or subordinate overlap was found |
| `OAUTH2-P256-KEY-S-STATE` | Binding initialization did not receive an all-zero destination |
| `OAUTH2-P256-KEY-S-ABSENT` | The RID or requested binding role is absent |
| `OAUTH2-P256-KEY-S-REVOKED` | The credential is an authenticated tombstone |
| `OAUTH2-P256-KEY-S-CONFLICT` | Credential creation conflicted with current durable state |
| `OAUTH2-P256-KEY-S-BUSY` | The vault is already active |
| `OAUTH2-P256-KEY-S-CALLBACK` | The application callback threw or violated its exact stack contract |
| `OAUTH2-P256-KEY-S-LOCKED` | The selected vault root key is unavailable |
| `OAUTH2-P256-KEY-S-ENTROPY` | Checked key-generation or vault entropy is unavailable |
| `OAUTH2-P256-KEY-S-CRYPTO` | A cryptographic primitive failed |
| `OAUTH2-P256-KEY-S-AUTH` | Vault authentication failed |
| `OAUTH2-P256-KEY-S-CORRUPT` | Authenticated storage or its envelope is corrupt |
| `OAUTH2-P256-KEY-S-UNSUPPORTED` | A durable vault format or capability is unsupported |
| `OAUTH2-P256-KEY-S-IO` | Durable storage I/O failed |
| `OAUTH2-P256-KEY-S-RECOVERY` | Durable publication or cleanup requires recovery |
| `OAUTH2-P256-KEY-S-ROLLBACK` | The record is below its trusted rollback floor |
| `OAUTH2-P256-KEY-S-FORMAT` | The typed kind, role, record length, header, flags, `kid`, or padding is wrong |
| `OAUTH2-P256-KEY-S-KEY` | The private scalar or derived public identity is invalid |
| `OAUTH2-P256-KEY-S-MISMATCH` | The current generation or derived thumbprint differs from the binding |
| `OAUTH2-P256-KEY-S-RANGE` | A caller span has invalid physical geometry |
| `OAUTH2-P256-KEY-S-PROTECTED` | A caller span intersects protected platform storage |
| `OAUTH2-P256-KEY-S-PLATFORM` | Caller-memory qualification failed unexpectedly |
| `OAUTH2-P256-KEY-S-INTERNAL` | An undocumented subordinate result or owner invariant failed |

Every credential-vault status is mapped explicitly. A vault callback status
comes from the owner's internal consumer and maps to `INTERNAL`; only the
later application callback can produce the public `CALLBACK` status.
