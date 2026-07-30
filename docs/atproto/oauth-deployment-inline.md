# AT OAuth Confidential Inline Deployment

`akashic/atproto/oauth-deployment-inline.f` composes the local AT OAuth
deployment binder, checked P-256 JWK Set selection, and durable local P-256 key
ownership for one confidential client whose Client ID Metadata Document embeds
`jwks`.

The module is published as:

```forth
PROVIDED akashic-at-oauth-inline
```

It is a synchronous local composition. It does not acquire a Client ID Metadata
Document or a remote JWK Set, and it does not construct client assertions,
DPoP proofs, authorization requests, tokens, or sessions.

## Public contract

```forth
AT-OAUTH-INLINE-WORKSPACE-SIZE  \ 111928 bytes

AT-OAUTH-INLINE-WORKSPACE-CLEAR  ( workspace -- status )

AT-OAUTH-INLINE-STATUS-VALID?  ( status -- flag )

AT-OAUTH-INLINE-WITH
  ( document document-u config profile vault callback context workspace
    -- callback-result status )
```

The final callback ABI is:

```forth
( config-view metadata-view
  client-kid-a client-kid-u client-public-a client-thumbprint-a
  dpop-public-a dpop-thumbprint-a
  context
  -- callback-result )
```

The two views and all five byte spans are read-only, callback-scoped borrows.
The client public and DPoP public spans are each 65-byte uncompressed SEC 1
P-256 points. Each thumbprint span is a 32-byte RFC 7638 digest. The client
`kid` is the exact authenticated local record value and the exact decoded
identifier used to select the published JWK.

The callback runs exactly once only after all deployment, JWK Set, vault
record, local-key, binding, and distinctness checks succeed. Its one result is
passed through unchanged. A throw, an extra or missing result, or consumption
below the callback arguments returns zero with
`AT-OAUTH-INLINE-S-CALLBACK`. Failures before the final callback also return a
zero callback result.

## Accepted deployment

This entry point deliberately accepts only the complete confidential inline
case:

- the immutable configuration and ready AT profile select
  `private_key_jwt`, ES256, and DPoP-bound access tokens;
- the Client ID Metadata Document passes every policy enforced by
  `AT-OAUTH-DEPLOYMENT-WITH`;
- the document declares `jwks`, not `jwks_uri`;
- the configuration's opaque binding is a canonical
  `OAUTH2-P256-KEY-BINDING` containing both the client-authentication and DPoP
  roles; and
- those roles resolve through the supplied credential vault.

A public `none` deployment and a confidential `jwks_uri` deployment are both
outside this API and return `AT-OAUTH-INLINE-S-KEY-SOURCE`. There is no
fallback from inline data to a URI, no remote acquisition, and no acceptance of
an unchecked key source.

## Ordered key composition

The operation remains inside the deployment callback while the validated
configuration and metadata views, including the raw inline `jwks` token, are
live. It then performs the key work in this order:

1. Resolve the client-authentication role with
   `OAUTH2-P256-KEY-WITH-CLIENT`.
2. Inside that owner callback, run `JOSE-JWK-SET-P256-SELECT` on the borrowed
   inline object with the authenticated local client `kid`.
3. Compare both the selected 65-byte public key and selected 32-byte
   thumbprint with the locally derived values. Agreement of only one is not
   sufficient.
4. Let the client owner call return completely, including its vault borrow
   cleanup, and retain only copied public identity.
5. Reuse the one owner child workspace for a completed
   `OAUTH2-P256-KEY-WITH-DPOP` call and retain only copied DPoP public identity.
6. Enforce that the resolved client and DPoP identities remain distinct, then
   invoke the final application callback.

The client and DPoP owner calls never overlap. The final callback runs only
after both calls have returned and every credential-vault private-record borrow
has been wiped and released. It may therefore begin a later vault operation;
it never executes while this composition holds private bytes or the vault busy
state.

## Admission and workspace

The complete document span, fixed configuration, fixed profile, supplied vault
descriptor, and complete writable workspace must each pass caller-memory
qualification. The document, configuration, profile, and workspace must also
pass `CVAULT-EXTERNAL-SPAN-STATUS` against that validated vault. Thus none may
overlap the vault header, index, journal, credential region, vault workspaces,
or other vault-reserved storage. The writable workspace must also be aligned
and disjoint from every read-only input under the ordinary module alias rules.
Admission failures occur before any workspace write.

The fixed 111,928-byte workspace has this exact layout:

| Offset | Size | Purpose |
|---:|---:|---|
| 0 | 192 | Orchestration header |
| 192 | 256 | Copied client `kid` |
| 448 | 65 | Copied client public key |
| 513 | 7 | Alignment padding |
| 520 | 32 | Copied client thumbprint |
| 552 | 65 | Copied DPoP public key |
| 617 | 7 | Alignment padding |
| 624 | 32 | Copied DPoP thumbprint |
| 656 | 65 | Selected published public key |
| 721 | 7 | Alignment padding |
| 728 | 32 | Selected published thumbprint |
| 760 | 53,760 | `AT-OAUTH-DEPLOYMENT-WITH` child workspace |
| 54,520 | 17,879 | Sequential P-256 key-owner child workspace |
| 72,399 | 1 | Alignment padding |
| 72,400 | 39,528 | Checked P-256 JWK Set child workspace |
| 111,928 | 0 | End of workspace |

The header is orchestration-only. The dedicated public-output regions preserve
the client result while the owner child workspace is wiped and reused for
DPoP. They do not extend lifetime beyond the final callback.

After an admitted operation begins, every normal success or failure wipes the
complete workspace. A caught unexpected operation failure also wipes it before
returning `AT-OAUTH-INLINE-S-INTERNAL`. Rejected preflight leaves the workspace
unchanged. The module never wipes or mutates the caller's document,
configuration, profile, vault, or final callback context.

## Borrowing and TOCTOU boundary

`config-view` and `metadata-view` remain the nested borrowed views created by
the deployment binder. The inline `jwks` token still points into the caller's
document. The client `kid`, public keys, and thumbprints passed to the final
callback are copies in the composition workspace. None of these addresses may
be retained or used after the callback returns.

The operation is synchronous but is not a concurrent-mutation defense. The
caller must keep the document, configuration, profile, vault, and binding
stable for the whole call and must treat all borrowed views as read-only. A
caller or callback that mutates an admitted input while it is being validated
or consumed creates a time-of-check/time-of-use race outside this contract.
Likewise, the callback guard checks the Forth stack contract; it is not a
sandbox for deliberately hostile native code.

## Status values

Deployment statuses map one-for-one through `KEY-SOURCE`. Checked-JWK policy
failures collapse to `JWKS` except for selection absence, capacity, alias,
cryptographic, and caller-memory results. Durable key-owner outcomes remain
distinguishable. Only failure of the final application callback maps to
`CALLBACK`; a failure of an internal composition callback is `INTERNAL`.

| Value | Status | Meaning |
|---:|---|---|
| 0 | `AT-OAUTH-INLINE-S-OK` | The complete composition succeeded and the callback returned one result. |
| 1 | `AT-OAUTH-INLINE-S-INVALID` | A required argument, span shape, alignment, callback, or subordinate input is invalid. |
| 2 | `AT-OAUTH-INLINE-S-CAPACITY` | A public bound or subordinate fixed capacity was exceeded. |
| 3 | `AT-OAUTH-INLINE-S-ALIAS` | Public operands overlap contrary to the composition or subordinate alias contract. |
| 4 | `AT-OAUTH-INLINE-S-CONFIG` | The immutable client configuration is invalid. |
| 5 | `AT-OAUTH-INLINE-S-PROFILE` | The AT OAuth profile is not structurally ready. |
| 6 | `AT-OAUTH-INLINE-S-METADATA` | Client metadata failed strict structural validation. |
| 7 | `AT-OAUTH-INLINE-S-CLIENT-ID` | The selected or declared client identifier failed local policy or equality. |
| 8 | `AT-OAUTH-INLINE-S-APPLICATION` | The application declaration does not match the selection. |
| 9 | `AT-OAUTH-INLINE-S-GRANT` | The grant declaration is not the exact selected set. |
| 10 | `AT-OAUTH-INLINE-S-RESPONSE` | The response declaration is not exactly `code`. |
| 11 | `AT-OAUTH-INLINE-S-REDIRECT` | The redirect declarations fail selected-client policy. |
| 12 | `AT-OAUTH-INLINE-S-SCOPE` | The declared scope omits a configured requested token. |
| 13 | `AT-OAUTH-INLINE-S-AUTH-METHOD` | The authentication method is absent, unsupported, or mismatched. |
| 14 | `AT-OAUTH-INLINE-S-AUTH-ALGORITHM` | The signing-algorithm declaration is absent or not the selected ES256 value. |
| 15 | `AT-OAUTH-INLINE-S-DPOP` | The deployment does not consistently require DPoP-bound access tokens. |
| 16 | `AT-OAUTH-INLINE-S-KEY-SOURCE` | The deployment is public, uses `jwks_uri`, or otherwise is not confidential inline `jwks`. |
| 17 | `AT-OAUTH-INLINE-S-BINDING` | The configuration binding is malformed or lacks a required client or DPoP role. |
| 18 | `AT-OAUTH-INLINE-S-JWKS` | The complete inline JWK Set failed checked structure or key-use policy. |
| 19 | `AT-OAUTH-INLINE-S-NOT-FOUND` | No checked JWK has the authenticated local client `kid`. |
| 20 | `AT-OAUTH-INLINE-S-ABSENT` | A bound credential is absent from the vault. |
| 21 | `AT-OAUTH-INLINE-S-REVOKED` | A bound credential has been revoked. |
| 22 | `AT-OAUTH-INLINE-S-CONFLICT` | Vault generation or mutation state conflicts with the binding. |
| 23 | `AT-OAUTH-INLINE-S-BUSY` | The vault rejected the operation as already busy. |
| 24 | `AT-OAUTH-INLINE-S-LOCKED` | The vault is locked. |
| 25 | `AT-OAUTH-INLINE-S-ENTROPY` | A subordinate key-owner entropy operation failed. |
| 26 | `AT-OAUTH-INLINE-S-CRYPTO` | Checked cryptographic derivation or JWK thumbprinting failed. |
| 27 | `AT-OAUTH-INLINE-S-AUTH` | Vault authentication failed. |
| 28 | `AT-OAUTH-INLINE-S-CORRUPT` | Authenticated vault state is corrupt. |
| 29 | `AT-OAUTH-INLINE-S-UNSUPPORTED` | A required vault or key format/feature is unsupported. |
| 30 | `AT-OAUTH-INLINE-S-IO` | Vault persistence I/O failed. |
| 31 | `AT-OAUTH-INLINE-S-RECOVERY` | Vault recovery is required or failed. |
| 32 | `AT-OAUTH-INLINE-S-ROLLBACK` | Vault rollback protection rejected the state. |
| 33 | `AT-OAUTH-INLINE-S-FORMAT` | A local authenticated key record has noncanonical format or the wrong role/kind. |
| 34 | `AT-OAUTH-INLINE-S-KEY` | A local P-256 private key is invalid. |
| 35 | `AT-OAUTH-INLINE-S-MISMATCH` | A pinned local identity or selected published public key/thumbprint does not match. |
| 36 | `AT-OAUTH-INLINE-S-DISTINCT` | The resolved client-authentication and DPoP identities are not distinct. |
| 37 | `AT-OAUTH-INLINE-S-CALLBACK` | The final application callback threw or violated its exact stack contract. |
| 38 | `AT-OAUTH-INLINE-S-INTERNAL` | An operation threw internally or a subordinate result was impossible. |
| 39 | `AT-OAUTH-INLINE-S-RANGE` | A caller span has invalid physical geometry or crosses an admitted memory window. |
| 40 | `AT-OAUTH-INLINE-S-PROTECTED` | A caller span intersects protected BIOS, dependency-private, or live-stack storage. |
| 41 | `AT-OAUTH-INLINE-S-PLATFORM` | Caller-memory or vault-external qualification returned an undocumented platform result. |

## Remaining remote boundary

This module closes the checked-inline-JWKS and corresponding-local-private-key
boundaries for one already supplied metadata document. It does not prove how
that document was obtained. A production acquisition owner must still bind the
configured `client_id` to the exact requested and effective HTTPS target,
apply hardened DNS and SSRF policy, authenticate TLS and the hostname, reject
redirects, require the intended status and media type, enforce body and time
bounds, and preserve the response bytes for this synchronous call.

Remote `jwks_uri` deployments remain a separate composition. They require the
same transport controls for the JWK Set resource, followed by checked
`JOSE-JWK-SET-P256-SELECT` and the same comparison to durable local key
identity. This inline entry point intentionally does not partially implement or
silently bridge that acquisition path.
