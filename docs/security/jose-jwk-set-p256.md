# akashic-jose-jwk-set-p256 — Checked Public P-256 JWK Sets

`jose/jwk-set-p256.f` validates a bounded homogeneous public-P-256 JWK Set
and selects one key by decoded `kid`. It is a strict selection profile for
checked ES256 client authentication, not a general-purpose RFC 7517 key-set
reader.

```forth
REQUIRE akashic/security/jose/jwk-set-p256.f
```

`PROVIDED akashic-jose-jwk-set-p256` — requires the strict offset-only JSON
object parser, the public P-256 JWK codec, and checked memory-span geometry.
It has no AT Protocol, OAuth, HTTP, session, persistence, or Streams
dependency.

## Accepted set profile

The root is one strict JSON object with exactly one decoded `keys` member:

```json
{"keys":[{"kid":"client-key-1","kty":"EC","crv":"P-256","x":"...","y":"..."}]}
```

The profile requires:

- a nonempty `keys` array containing at most 32 objects;
- no more than 32 members in the root or any individual key object;
- every array member to pass `JOSE-JWK-P256-PUBLIC-PARSE`;
- one nonempty decoded `kid` of at most 256 bytes on every key;
- globally unique decoded `kid` values;
- exact, case-sensitive selection against the caller's decoded `kid`;
- full validation of every key, including keys after the selected key;
- `use`, when present, to be the string `"sig"`;
- `alg`, when present, to be the string `"ES256"`; and
- `key_ops`, when present, to be exactly the one-element decoded array
  `["verify"]`.

`use`, `alg`, and `key_ops` are optional because neither RFC 7517 nor the AT
Protocol OAuth profile requires their presence on every published key. If a
publisher supplies them, this profile refuses values inconsistent with
ES256 signature verification.

Registered private or symmetric parameters `d`, `k`, `p`, `q`, `dp`, `dq`,
`qi`, `oth`, and `priv` are rejected regardless of value type. Decoded
member-name comparison also rejects escaped spellings. `x5u`, `x5c`, `x5t`,
and `x5t#S256` are rejected until certificate acquisition and
key-consistency checking exist. The registered time/revocation parameters
`nbf`, `exp`, and `revoked` are likewise rejected until this API has a
trusted clock and revocation-policy input. Silently accepting any of those
members would overstate what this boundary has proved. Unknown public
metadata is accepted only after complete strict JSON, UTF-8, nesting, and
duplicate-name validation.

This is intentionally narrower than a generic
[RFC 7517](https://www.rfc-editor.org/rfc/rfc7517) implementation: generic
consumers may ignore unsupported key types and `kid` is optional there.
This module instead proves that the complete admitted set is usable by one
homogeneous P-256 selection policy. The current
[AT Protocol OAuth specification](https://atproto.com/specs/oauth) supplies
the deployment context in which the selected client-authentication key is
later bound to local private-key ownership.

## API

```forth
JOSE-JWK-SET-P256-PUBLIC-SIZE         ( -- 65 )
JOSE-JWK-SET-P256-THUMBPRINT-SIZE     ( -- 32 )
JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES ( -- 65536 )
JOSE-JWK-SET-P256-MAX-KEYS           ( -- 32 )
JOSE-JWK-SET-P256-MAX-MEMBERS        ( -- 32 )
JOSE-JWK-SET-P256-KID-CAPACITY       ( -- 256 )
JOSE-JWK-SET-P256-WORKSPACE-SIZE     ( -- 39528 )

JOSE-JWK-SET-P256-SELECT
  ( source source-u kid kid-u
    public-output thumbprint-output workspace -- status )

JOSE-JWK-SET-P256-WORKSPACE-CLEAR
  ( workspace -- status )
```

`SELECT` publishes the selected 65-byte uncompressed SEC 1 key
`0x04 || X || Y` and its raw 32-byte RFC 7638 SHA-256 thumbprint. The caller
passes the already-decoded `kid` bytes to select. JSON string unescaping is
applied to each document `kid` before uniqueness and selection comparison.

The source and selector are borrowed read-only for the complete call.
Neither output retains a JSON view or source pointer.

## Bounds and iteration

The document limit is 65,536 bytes. The 39,528-byte caller workspace contains
one reusable strict-object descriptor, decoded-name storage, the strict JSON
workspace, 32 source-relative candidate spans, an 8,192-byte decoded-`kid`
arena, the subordinate P-256 JWK workspace, and staged key/thumbprint output.

The root document first receives complete recursive strict-JSON validation.
The module then recovers and stores every exact key-object span. Per-key
parsing begins only after collection finishes. This separation is required:
the inner `key_ops` array uses the same bounded token scanner and must not
overwrite an active outer `keys` cursor.

Candidate count and object type are established before elliptic-curve work.
A selected key does not return early; a malformed, sensitive, unsupported,
or duplicate later key rejects the complete set.

## Ownership, geometry, and cleanup

Every complete source, selector, output, and workspace span is qualified
before the first write. The outer boundary composes
`JOSE-JWK-P256-CALLER-SPAN-STATUS`, so generic caller geometry plus the
P-256, immutable JWK serialization, and SHA-256 reserved footprints are
excluded. The workspace must be cell-aligned. Borrowed source and selector
spans may overlap each other, but neither may overlap an output or the
workspace; the two outputs and workspace are mutually disjoint.

All validation and cryptographic results are staged. Every returned failure
leaves both caller outputs unchanged, and every admitted normal or caught
exit clears all 39,528 workspace bytes. Unexpected staging `THROW` becomes
`INTERNAL` only after cleanup succeeds.

Final publication necessarily consists of two caller-output moves. A
publication `THROW` propagates after mandatory cleanup and can leave one
output or a prefix changed; it is never converted into a returned success or
failure status. Cleanup `THROW` has precedence. Callers that need a single
atomic durable record must perform their own magic-last commit after this
ephemeral selection call returns.

## Status values

| Status | Meaning |
|---|---|
| `JOSE-JWK-SET-P256-S-OK` | Both selected outputs were published. |
| `JOSE-JWK-SET-P256-S-INVALID` | An argument, zero-length required input, or workspace alignment is invalid. |
| `JOSE-JWK-SET-P256-S-CAPACITY` | A document, collection, member, nesting, name, or decoded-value bound was exceeded. |
| `JOSE-JWK-SET-P256-S-ALIAS` | A mutable operand overlaps another public operand or reserved cryptographic storage. |
| `JOSE-JWK-SET-P256-S-JSON` | Strict JSON, UTF-8, Unicode, grammar, or duplicate-name validation failed. |
| `JOSE-JWK-SET-P256-S-MISSING` | The root lacks `keys` or a key lacks `kid`. |
| `JOSE-JWK-SET-P256-S-TYPE` | `keys`, a key entry, or `kid` has the wrong JSON type. |
| `JOSE-JWK-SET-P256-S-EMPTY` | `keys` or a decoded key identifier is empty. |
| `JOSE-JWK-SET-P256-S-SENSITIVE` | A registered private or symmetric parameter is present. |
| `JOSE-JWK-SET-P256-S-UNSUPPORTED` | Certificate-reference or time/revocation metadata is present without the required consistency or policy input. |
| `JOSE-JWK-SET-P256-S-KEY` | A candidate is not an exact usable public EC/P-256 key. |
| `JOSE-JWK-SET-P256-S-DUPLICATE` | Two keys have the same decoded `kid`; the complete set is ambiguous. |
| `JOSE-JWK-SET-P256-S-USE` | Present `use` is not exactly `"sig"`. |
| `JOSE-JWK-SET-P256-S-ALGORITHM` | Present `alg` is not exactly `"ES256"`. |
| `JOSE-JWK-SET-P256-S-KEY-OPS` | Present `key_ops` is not exactly `["verify"]`. |
| `JOSE-JWK-SET-P256-S-NOT-FOUND` | The complete valid set contains no requested decoded `kid`. |
| `JOSE-JWK-SET-P256-S-CRYPTO` | Checked cryptographic admission or RFC 7638 thumbprint derivation failed. |
| `JOSE-JWK-SET-P256-S-INTERNAL` | An impossible subordinate result or caught staging fault occurred. |
| `JOSE-JWK-SET-P256-S-RANGE` | A span has invalid physical geometry or crosses an admitted memory window. |
| `JOSE-JWK-SET-P256-S-PROTECTED` | A span intersects protected BIOS/private/live-stack storage. |
| `JOSE-JWK-SET-P256-S-PLATFORM` | Caller-memory qualification returned an undocumented platform result. |

`JOSE-JWK-SET-P256-STATUS-VALID?` validates the complete status vocabulary.
