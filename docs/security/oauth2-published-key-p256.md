# OAuth P-256 Published-Key Ownership

`akashic/security/oauth2/published-key-p256.f` composes the checked public
P-256 JWK Set selector with durable OAuth client-authentication and DPoP key
ownership. It proves that one complete published JWK Set contains the
authenticated local client key, then lends copied client and DPoP public
identity to one synchronous callback.

The module is provider-neutral and state-free. It does not interpret Client
Identifier Metadata, select inline versus remote key publication, establish
HTTP provenance, or depend on AT Protocol, tokens, sessions, or application
state.

It is published as:

```forth
PROVIDED akashic-oauth2-p256-pub
```

## Public contract

```forth
OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE  \ 58056 bytes

OAUTH2-P256-PUBLISHED-WORKSPACE-CLEAR
  ( workspace -- status )

OAUTH2-P256-PUBLISHED-STATUS-VALID?
  ( status -- flag )

OAUTH2-P256-PUBLISHED-WITH
  ( jwks-a jwks-u binding-a binding-u vault callback context workspace
    -- callback-result status )
```

The application callback ABI is:

```forth
( kid-a kid-u
  client-public-a client-thumbprint-a
  dpop-public-a dpop-thumbprint-a
  context
  -- callback-result )
```

`kid-a kid-u` is the exact authenticated client-record identifier and the
decoded identifier used to select the published JWK. Each public-key span is a
65-byte uncompressed SEC 1 P-256 point. Each thumbprint span is the
corresponding raw 32-byte RFC 7638 SHA-256 digest.

Every callback span is a read-only borrow into the composition workspace. It
is valid only while the callback is running and is wiped immediately
afterward. The callback result is passed through unchanged on success.
Every failure returns a zero callback result.

## Accepted binding and JWK Set

`binding-a binding-u` must be exactly one canonical
`OAUTH2-P256-KEY-BINDING` with both the client-authentication and DPoP roles
present. The durable binding rules already require distinct role, RID,
generation, and thumbprint identities. Missing roles, malformed fields, or a
wrong binding size return `OAUTH2-P256-PUBLISHED-S-BINDING`.

The JWK Set is borrowed read-only and must satisfy the complete checked profile
of `JOSE-JWK-SET-P256-SELECT`:

- no more than 65,536 source bytes;
- a nonempty set of at most 32 public EC/P-256 keys;
- a unique nonempty decoded `kid` on every key;
- no private, symmetric, certificate-linked, or unsupported
  time/revocation material;
- compatible `use`, `alg`, and `key_ops` when those members are present; and
- full validation of every key, including keys after the selected key.

The selector is never given a caller-chosen `kid`. The composition first
authenticates the durable client record and uses that record's exact copied
`kid` for selection.

## Ordered ownership proof

The operation performs the following steps synchronously:

1. Validate the exact two-role binding.
2. Resolve the client-authentication role through
   `OAUTH2-P256-KEY-WITH-CLIENT`.
3. While that owner's public callback is active, select the authenticated
   client `kid` from the complete checked JWK Set.
4. Compare both the selected public point and selected RFC 7638 thumbprint
   with the values derived from the authenticated local private record.
5. Copy only the client public identity into the outer workspace and let the
   client owner return, wipe its private borrow, and release the vault.
6. Reuse the one owner child workspace for
   `OAUTH2-P256-KEY-WITH-DPOP`.
7. Require both the resolved DPoP public point and thumbprint to differ from
   the client identity, then copy that public identity.
8. Let the DPoP owner return and release the vault before invoking the final
   application callback.

The two owner operations never overlap. Application code therefore never runs
while this composition holds a private scalar or an active credential-vault
borrow. The final callback may begin a later independent vault operation.

Agreement of only the published public point or only its thumbprint is not
sufficient. A mismatch in either comparison returns
`OAUTH2-P256-PUBLISHED-S-MISMATCH`. Binding-level distinctness is also checked
against the resolved public identities; equality of either client/DPoP point
or thumbprint returns `OAUTH2-P256-PUBLISHED-S-DISTINCT`.

## Workspace and ownership

The complete 58,056-byte workspace is caller-owned and must be eight-byte
aligned:

| Offset | Size | Purpose |
|---:|---:|---|
| 0 | 80 | Orchestration header |
| 80 | 256 | Copied client `kid` |
| 336 | 65 | Copied client public key |
| 401 | 7 | Alignment padding |
| 408 | 32 | Copied client thumbprint |
| 440 | 65 | Copied DPoP public key |
| 505 | 7 | Alignment padding |
| 512 | 32 | Copied DPoP thumbprint |
| 544 | 65 | Selected published public key |
| 609 | 7 | Alignment padding |
| 616 | 32 | Selected published thumbprint |
| 648 | 17,879 | Sequential durable-key owner workspace |
| 18,527 | 1 | Alignment padding |
| 18,528 | 39,528 | Checked JWK Set workspace |
| 58,056 | 0 | End of workspace |

Before the first workspace write, the operation qualifies:

- the complete JWK Set span;
- the exact fixed binding;
- the credential-vault descriptor;
- the callback token; and
- the complete writable workspace.

The JWK Set, binding, and workspace must each pass
`CVAULT-EXTERNAL-SPAN-STATUS` against the validated vault. This rejects
aliases of the vault descriptor, backing store, VFS descriptor, private
credential storage, vault workspaces, and dependency-private storage. The
writable workspace must also be disjoint from the complete JWK Set and
binding spans.

The JWK Set and binding remain caller-owned, borrowed, and unchanged.
Read-only overlap between those two inputs is not itself rejected; neither may
overlap the workspace or live vault storage. The caller must keep the JWK Set,
binding, and vault byte-stable for the complete synchronous call. This API is
not a defense against concurrent caller mutation.

## Cleanup and callback containment

A public geometry or ownership rejection occurs before any workspace write and
leaves the workspace unchanged. Once admission succeeds, every returned
success or failure wipes all 58,056 bytes.

The checked selector and both durable owners apply their own child-workspace
and private-record cleanup before returning. An unexpected internal throw is
contained, the admitted outer workspace is wiped, and the operation returns
`OAUTH2-P256-PUBLISHED-S-INTERNAL`.

The final callback runs exactly once only after every prior check succeeds. It
must consume its seven arguments and return exactly one cell. A throw, an
extra or missing result, or consumption below the callback arguments returns
`OAUTH2-P256-PUBLISHED-S-CALLBACK` after cleanup. Failures in the internal
client or DPoP owner callbacks are internal composition failures and do not
masquerade as an application callback failure.

`OAUTH2-P256-PUBLISHED-WORKSPACE-CLEAR` independently qualifies and wipes one
complete aligned workspace. A rejected clear does not modify it.

## Status values

Use `OAUTH2-P256-PUBLISHED-STATUS-VALID?` before accepting an arbitrary
status cell.

| Value | Status | Meaning |
|---:|---|---|
| 0 | `OAUTH2-P256-PUBLISHED-S-OK` | Selection, ownership proof, callback, and cleanup succeeded. |
| 1 | `OAUTH2-P256-PUBLISHED-S-INVALID` | An argument, required span, alignment, callback token, or vault is invalid. |
| 2 | `OAUTH2-P256-PUBLISHED-S-CAPACITY` | The JWK Set, `kid`, or a subordinate public bound was exceeded. |
| 3 | `OAUTH2-P256-PUBLISHED-S-ALIAS` | A caller span overlaps writable or protected composition storage. |
| 4 | `OAUTH2-P256-PUBLISHED-S-BINDING` | The binding is malformed, has the wrong size, or does not contain exactly both required roles. |
| 5 | `OAUTH2-P256-PUBLISHED-S-JWKS` | The complete JWK Set failed checked JSON, public-key, or key-use policy. |
| 6 | `OAUTH2-P256-PUBLISHED-S-NOT-FOUND` | No checked JWK has the authenticated local client `kid`. |
| 7 | `OAUTH2-P256-PUBLISHED-S-ABSENT` | A bound credential is absent. |
| 8 | `OAUTH2-P256-PUBLISHED-S-REVOKED` | A bound credential is revoked. |
| 9 | `OAUTH2-P256-PUBLISHED-S-CONFLICT` | Durable generation or mutation state conflicts with the binding. |
| 10 | `OAUTH2-P256-PUBLISHED-S-BUSY` | The vault is already active. |
| 11 | `OAUTH2-P256-PUBLISHED-S-LOCKED` | The selected vault root key is unavailable. |
| 12 | `OAUTH2-P256-PUBLISHED-S-ENTROPY` | A checked subordinate entropy operation failed. |
| 13 | `OAUTH2-P256-PUBLISHED-S-CRYPTO` | Checked P-256 derivation or JWK thumbprinting failed. |
| 14 | `OAUTH2-P256-PUBLISHED-S-AUTH` | Vault authentication failed. |
| 15 | `OAUTH2-P256-PUBLISHED-S-CORRUPT` | Authenticated vault storage is corrupt. |
| 16 | `OAUTH2-P256-PUBLISHED-S-UNSUPPORTED` | A required durable format or capability is unsupported. |
| 17 | `OAUTH2-P256-PUBLISHED-S-IO` | Durable storage I/O failed. |
| 18 | `OAUTH2-P256-PUBLISHED-S-RECOVERY` | Vault recovery is required or failed. |
| 19 | `OAUTH2-P256-PUBLISHED-S-ROLLBACK` | Rollback protection rejected the durable state. |
| 20 | `OAUTH2-P256-PUBLISHED-S-FORMAT` | A typed local key record has noncanonical format or the wrong role/kind. |
| 21 | `OAUTH2-P256-PUBLISHED-S-KEY` | A local P-256 private key is invalid. |
| 22 | `OAUTH2-P256-PUBLISHED-S-MISMATCH` | The durable binding or selected published public point/thumbprint does not match. |
| 23 | `OAUTH2-P256-PUBLISHED-S-DISTINCT` | The resolved client and DPoP public identities are not distinct. |
| 24 | `OAUTH2-P256-PUBLISHED-S-CALLBACK` | The final application callback threw or violated its exact stack contract. |
| 25 | `OAUTH2-P256-PUBLISHED-S-INTERNAL` | An internal callback, operation, invariant, or undocumented subordinate result failed. |
| 26 | `OAUTH2-P256-PUBLISHED-S-RANGE` | A caller span has invalid physical geometry. |
| 27 | `OAUTH2-P256-PUBLISHED-S-PROTECTED` | A caller span intersects protected platform or dependency-private storage. |
| 28 | `OAUTH2-P256-PUBLISHED-S-PLATFORM` | Caller-memory qualification failed unexpectedly. |

Checked-JWK structural and policy failures collapse to `JWKS`, while
selection absence, capacity, alias, cryptographic, and caller-memory outcomes
remain distinct. Durable owner outcomes remain distinguishable. Only the
final application callback produces `CALLBACK`; failures of the composition's
internal owner callbacks produce `INTERNAL`.

## Composition boundary

A successful result proves published-key agreement with durable local
ownership. It does not prove where the JWK Set came from. A higher-level
deployment owner must separately establish the metadata declaration, exact
requested/effective resource target, HTTPS and DNS/SSRF policy, authenticated
TLS, HTTP status, redirect and media policy, body/time bounds, and response
storage ownership before supplying a remotely acquired body.

Inline metadata borrowers must call this operation while their raw `jwks`
token remains live. Remote acquisition owners must retain the admitted JWK Set
body for the complete call. Neither path may fall back to the other after its
declared key source fails.

## Focused qualification and recorded deferrals

The first production consumer is the confidential inline AT OAuth
composition. Its static gate checks this module's provider-neutral dependency
boundary, state-free implementation, public vocabulary, operation order,
workspace geometry, and callback containment. The retained-metadata static
gate also loads the generic source before the stripped inline composition.

On 2026-07-30, a sequential diagnostic lifecycle compiled the complete
28-module graph and passed contracts, normal success, source selection,
binding, published/local mismatch, durable-owner failures, and identity
distinctness. It exposed one real integration defect: the AT callback bridge
needed its own nine-argument stack guard inside this module's generic
seven-argument guard. After that correction:

- a focused success-and-callback lifecycle passed in 948,770,399 guest steps
  and 650.25 summed stage seconds; and
- a focused rejection-before-write preflight lifecycle passed in 877,258,595
  guest steps and 533.40 summed stage seconds.

Both runs used one core, 128 MiB of external machine memory, and the existing
checked-in 180,000,000-step phase ceiling. The static gates for both the inline
and retained-metadata consumers also passed.

A second complete nine-group rerun was deliberately not required after the
isolated callback-bridge correction. The unchanged groups had already passed,
and the patched reruns covered the changed normal/callback path plus the
security-relevant preflight and cleanup path. A standalone direct-API matrix,
every subordinate-status permutation, a full cross-product of protected alias
classes, repeated canary/capacity variants, and concurrent caller-mutation
experiments remain recorded non-gating work. Remote acquisition must still
gate exact two-resource provenance and retained-body ownership before using
this generic owner.
