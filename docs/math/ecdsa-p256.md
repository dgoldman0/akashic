# akashic-ecdsa-p256 — Deterministic Raw ECDSA over P-256

`ecdsa-p256.f` provides the generic ES256 signature primitive below JOSE. It
signs and verifies already-computed 32-byte hashes; message hashing and
protocol policy belong to the caller.

```forth
REQUIRE akashic/math/ecdsa-p256.f
```

`PROVIDED akashic-ecdsa-p256` — requires `math/hmac-sha256.f`,
`math/p256.f`, `math/field.f`, `utils/caller-span.f`, and
`utils/memory-span.f`.

## Wire contract

```forth
ECDSA-P256-HASH-SIZE       ( -- 32 )
ECDSA-P256-PRIVATE-SIZE    ( -- 32 )
ECDSA-P256-PUBLIC-SIZE     ( -- 65 )
ECDSA-P256-SIGNATURE-SIZE  ( -- 64 )
ECDSA-P256-WORKSPACE-SIZE  ( -- 2064 )
```

Hashes and private scalars use 32-byte big-endian order. Public keys are
65-byte uncompressed SEC 1 points. Signatures are the fixed-width IEEE P1363
and JOSE form:

```text
r[32] || s[32]
```

ASN.1 DER signatures are deliberately outside this API.

## Operations

```forth
ECDSA-P256-SIGN-HASH
  ( hash private signature workspace -- status )

ECDSA-P256-VERIFY-HASH
  ( hash public signature workspace -- valid? status )

ECDSA-P256-WORKSPACE-CLEAR
  ( workspace -- status )
```

Signing derives its nonce with RFC 6979 HMAC-SHA-256. It needs no entropy
source and produces the same signature for the same hash and private key.
Candidate generation is bounded to 64 attempts and applies RFC 6979's
prescribed state update after a rejected candidate.

The signer does not normalize `s` to the lower half of the subgroup order.
This preserves RFC 6979 vectors exactly. Verification accepts either
mathematically valid half-order form while still requiring both `r` and `s`
to be in `1..n-1`.

A well-formed but incorrect signature returns `0 ECDSA-P256-S-OK`.
Malformed signature scalars and malformed public keys have distinct nonzero
statuses.

## Transaction and memory rules

Every complete hash, key, signature, and 2064-byte workspace span is checked
through `CALLER-SPAN-STATUS` before any caller byte is read or changed.
RANGE, PROTECTED, and PLATFORM remain distinct ECDSA statuses. Each span is
also rejected if it intersects ECDSA's immutable subgroup-order tables,
SHA-256's exposed reserved boundary, or the reserved boundaries exported by
Field and P-256.

The four public spans must be pairwise disjoint. The caller must own the
workspace exclusively from entry through return; sharing it with another task
or nested operation is invalid. Hashes, keys, and signatures borrowed as
inputs must remain immutable for that interval. Physical qualification proves
neither allocation ownership nor lifetime. Geometry and alias rejection leave
every caller span unchanged. Once admitted:

- private material, RFC 6979 state, subgroup temporaries, and subordinate
  workspaces remain inside the caller workspace;
- signing stages contiguous `r || s` and starts one 64-byte publication only
  after successful computation;
- verification has no output buffer to partially publish;
- clearing of the entire workspace is attempted on success, ordinary
  rejection, and unexpected `THROW`;
- an admitted computation `THROW` is reissued after the outer wipe attempt,
  because an untyped subordinate exception may itself represent lower-layer
  cleanup ambiguity;
- a publication or mandatory-cleanup `THROW` propagates and is never
  mislabeled as a returned status.

The final signature copy is an in-process commit point, not a promise of
power-failure or memory-fault atomicity. Normal failure before publication
leaves the signature unchanged; a fault during the final `MOVE` may expose a
partial write. The publication boundary attempts the workspace wipe and then
rethrows the publication exception. If that wipe throws, the cleanup
exception takes precedence.

Verification has no caller output, but its workspace contains borrowed
pointers, RFC 6979/field temporaries, and subordinate workspaces during the
operation. A verification cleanup fault therefore remains ambiguous and
propagates under the same rule.

The complete sign or verify operation holds the recursive Field transaction.
P-256 operations recurse through that same ownership boundary, preserving a
single lock order for the shared Field ALU and cryptographic accumulators.

## Status values

| Status | Meaning |
|---|---|
| `ECDSA-P256-S-OK` | The operation completed; consult `valid?` for verification. |
| `ECDSA-P256-S-RANGE` | A complete public span is null, signed-negative, wrapping, cross-window, or outside advertised memory. |
| `ECDSA-P256-S-PROTECTED` | A public Bank 0 span intersects BIOS/private memory, live stacks, or the result cell. |
| `ECDSA-P256-S-PLATFORM` | Caller-span qualification threw or returned an undocumented platform result. |
| `ECDSA-P256-S-ALIAS` | Public spans overlap each other or an ECDSA/subordinate reserved footprint. |
| `ECDSA-P256-S-PRIVATE` | The private scalar is zero or not less than `n`. |
| `ECDSA-P256-S-PUBLIC` | The public key is malformed, noncanonical, or off-curve. |
| `ECDSA-P256-S-SIGNATURE` | `r` or `s` is outside `1..n-1`. |
| `ECDSA-P256-S-NONCE` | The bounded RFC 6979 candidate loop exhausted. |
| `ECDSA-P256-S-CRYPTO` | A subordinate cryptographic operation failed. |
| `ECDSA-P256-S-INTERNAL` | An impossible subordinate status or result was observed before publication. |

`ECDSA-P256-STATUS-VALID?` validates this status vocabulary.
