# OAuth P-256 Key Ownership

`akashic/security/oauth2/key-p256.f` owns the durable identity boundary for
OAuth client-authentication and DPoP P-256 keys. It generates private scalars
inside transient caller-owned workspace, commits typed records through the
credential vault, resolves them into callback-scoped public identity, and can
construct one DPoP proof while the authenticated DPoP scalar remains inside
an owner-controlled vault borrow. Private scalars are never returned to an
application callback or copied into proof output.

The module is provider-neutral. It does not interpret an OAuth client
configuration, select a published JWK, construct a client assertion, or own
HTTP, AT Protocol, session, nonce-retry, or application state. The DPoP
operation applies only generic RFC 9449/ES256 construction policy by
delegating to `security/oauth2/dpop-es256.f`.

## Public geometry

```forth
OAUTH2-P256-KEY-SLOT-SIZE          \ 80 bytes
OAUTH2-P256-KEY-BINDING-SIZE       \ 192 bytes
OAUTH2-P256-KEY-RECORD-SIZE        \ 336 bytes
OAUTH2-P256-KEY-KID-CAPACITY       \ 256 bytes
OAUTH2-P256-KEY-PUBLIC-SIZE        \ 65 bytes
OAUTH2-P256-KEY-THUMBPRINT-SIZE    \ 32 bytes
OAUTH2-P256-KEY-WORKSPACE-SIZE     \ 17879 bytes
OAUTH2-P256-KEY-DPOP-INPUT-SIZE    \ 88 bytes
OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE \ derived bytes
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

## Vault-backed DPoP proofs

The purpose-scoped proof operation closes the generic boundary between a
durable DPoP key and the standalone DPoP constructor without introducing a
raw-private-key API:

```forth
OAUTH2-P256-KEY-DPOP-INPUT-CLEAR  ( input -- status )
OAUTH2-P256-KEY-DPOP-WORKSPACE-CLEAR  ( workspace -- status )

OAUTH2-P256-KEY-DPOP-PROOF
  ( binding binding-u vault input owner-workspace
    -- written status )
```

The caller clears and fills one aligned 88-byte descriptor through these
field accessors:

```forth
OAUTH2-P256-KEY-DPOP-I.HTM-A
OAUTH2-P256-KEY-DPOP-I.HTM-U
OAUTH2-P256-KEY-DPOP-I.HTU-A
OAUTH2-P256-KEY-DPOP-I.HTU-U
OAUTH2-P256-KEY-DPOP-I.IAT
OAUTH2-P256-KEY-DPOP-I.NONCE-A
OAUTH2-P256-KEY-DPOP-I.NONCE-U
OAUTH2-P256-KEY-DPOP-I.TOKEN-A
OAUTH2-P256-KEY-DPOP-I.TOKEN-U
OAUTH2-P256-KEY-DPOP-I.DESTINATION
OAUTH2-P256-KEY-DPOP-I.CAPACITY
```

`HTM` and `HTU` are required. The nonce and access token are independently
optional and use canonical `(0,0)` absence. `IAT` and destination capacity
have the same meaning as in `OAUTH2-DPOP-ES256-PROOF`; zero output capacity
uses canonical `(0,0)`. The proof operation takes the larger
`OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE`, while every other key-owner operation
continues to use `OAUTH2-P256-KEY-WORKSPACE-SIZE`.

Like the module's provisioning workspace, the DPoP owner workspace is
caller-allocated but exclusively lent to the owner for the synchronous call.
The caller must not inspect, alias, or access it concurrently.

The owner validates and snapshots the complete binding and descriptor,
requires the DPoP role, pins its credential generation and thumbprint, and
qualifies all public spans against both caller memory and the live credential
vault. Its internal vault consumer authenticates the typed record, validates
the scalar by deriving the expected public identity, and invokes the generic
DPoP constructor before returning from `CVAULT-WITH`. The constructor's
private-key scratch and first proof publication remain inside the exclusively
borrowed owner-operation workspace; neither address is caller-selectable.
The scalar address never crosses the owner API.

Only after the vault borrow has released does the owner publish the fully
staged compact proof to the advertised caller destination. The complete DPoP
owner workspace is wiped on every admitted return and on terminal publication
throws. Publication throws are rethrown after successful cleanup rather than
being collapsed into an ordinary status. The caller owns the published proof
and should clear it promptly after sealing the HTTP request. This operation
performs no nonce caching, automatic retry, endpoint selection, HTTP work, or
token/session mutation.

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
Terminal caller-output publication and outer cleanup throws propagate. An
internal vault-consumer throw maps to `OAUTH2-P256-KEY-S-INTERNAL` only after
the vault has wiped its private borrow; DPoP output is still confined to owner
staging at that point, and the complete owner workspace is then wiped, so the
status cannot conceal an ambiguous caller-output effect.

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
| `OAUTH2-P256-KEY-S-METHOD` | The DPoP HTTP method is invalid |
| `OAUTH2-P256-KEY-S-HTU` | The normalized DPoP target URI is invalid |
| `OAUTH2-P256-KEY-S-NONCE` | The optional DPoP nonce is invalid |
| `OAUTH2-P256-KEY-S-TOKEN` | The optional access token is invalid |
| `OAUTH2-P256-KEY-S-TIME` | The DPoP issued-at time is invalid |

Every credential-vault status is mapped explicitly. A vault callback status
comes from the owner's internal consumer and maps to `INTERNAL`; only the
later application callback can produce the public `CALLBACK` status.
