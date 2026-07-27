# akashic-jose-jwk-p256 — Strict Public P-256 JWKs

`jose/jwk-p256.f` converts between uncompressed SEC 1 P-256 public keys and a
strict public JSON Web Key, and computes RFC 7638 thumbprints. It is generic
JOSE infrastructure: key selection and `kid`, `use`, `alg`, OAuth, DPoP, and
application policy belong above it.

```forth
REQUIRE akashic/security/jose/jwk-p256.f
```

`PROVIDED akashic-jose-jwk-p256` — requires strict JOSE Base64url
and JSON, SHA-256, P-256, `utils/memory-span.f`, and
`utils/caller-span.f`.

## Accepted public JWK

The parser requires exactly one of each core member, in any JSON member
order:

```json
{"kty":"EC","crv":"P-256","x":"...","y":"..."}
```

The policy is exact:

- `kty` is the string `"EC"`;
- `crv` is the string `"P-256"`;
- `x` and `y` are canonical unpadded Base64url encodings of exactly 32 bytes;
- up to 32 total members are accepted;
- additional non-secret metadata members are strictly parsed but otherwise
  ignored by this binary-key conversion;
- a decoded member name `d` is rejected unconditionally, including escaped
  spellings such as `"\u0064"`;
- duplicate decoded names and trailing non-whitespace input are rejected by
  the strict JSON layer;
- decoded coordinates must form a valid P-256 point.

The binary boundary is the 65-byte uncompressed SEC 1 encoding
`0x04 || X || Y`.

`PUBLIC-PARSE` publishes only that SEC 1 key; it does not copy or interpret
unknown metadata. The JSON source remains caller-owned, so a higher layer can
enumerate the same document with `jose/json-object.f` and enforce `kid`,
`use`, `alg`, `key_ops`, certificate, or application policy without making
those policies part of this generic key codec. Applications that rely on
metadata must inspect it themselves rather than treating acceptance here as a
policy decision.

## API

```forth
JOSE-JWK-P256-PUBLIC-SIZE      ( -- 65 )
JOSE-JWK-P256-CANONICAL-SIZE   ( -- 126 )
JOSE-JWK-P256-THUMBPRINT-SIZE  ( -- 32 )
JOSE-JWK-P256-MAX-MEMBERS      ( -- 32 )
JOSE-JWK-P256-WORKSPACE-SIZE   ( -- bytes )

JOSE-JWK-P256-PUBLIC-PARSE
  ( source source-u public-output workspace -- status )

JOSE-JWK-P256-PUBLIC-EMIT
  ( public destination capacity workspace -- written status )

JOSE-JWK-P256-THUMBPRINT
  ( public digest-output workspace -- status )

JOSE-JWK-P256-WORKSPACE-CLEAR
  ( workspace -- status )
```

`PUBLIC-EMIT` validates the SEC 1 point and always writes the 126-byte RFC
7638 canonical serialization:

```json
{"crv":"P-256","kty":"EC","x":"...","y":"..."}
```

`THUMBPRINT` hashes exactly that canonical serialization with SHA-256 and
publishes the raw 32-byte digest.

Every complete public document, key, advertised output-capacity, fixed
output, and workspace span is admitted through `CALLER-SPAN-STATUS` before
mutation. `RANGE`, `PROTECTED`, and `PLATFORM` remain distinct JWK statuses.
All public spans are also rejected if they overlap P-256's exported reserved
footprint, this module's immutable serialization tables, or SHA-256's
reserved/admission boundary. Operation operands must be mutually disjoint as
documented; output capacity participates in full, not merely the prefix
eventually written.

The caller must keep borrowed source bytes stable for the complete call.
`PUBLIC-PARSE` retains only offsets while validating and decoding the
document. `PUBLIC-EMIT` and `THUMBPRINT` snapshot the admitted 65-byte public
key into the workspace before point validation and canonicalization.

Geometry rejection and every returned validation failure leave caller output
unchanged. Validation and staging occur behind an exception boundary; a
staging `THROW` becomes `INTERNAL` only after mandatory workspace cleanup
succeeds. Final caller-output `MOVE` is a separate publication phase.
Publication `THROW` propagates after cleanup, and mandatory cleanup `THROW`
propagates with precedence. Publication faults may therefore leave a partial
caller output rather than returning a misleading status.

## Status values

| Status | Meaning |
|---|---|
| `JOSE-JWK-P256-S-OK` | The requested result was published. |
| `JOSE-JWK-P256-S-INVALID` | An argument or span is invalid. |
| `JOSE-JWK-P256-S-CAPACITY` | The canonical output does not fit. |
| `JOSE-JWK-P256-S-ALIAS` | Public operands overlap. |
| `JOSE-JWK-P256-S-JSON` | Strict JSON validation or string decoding failed. |
| `JOSE-JWK-P256-S-POLICY` | A required member or literal is missing/invalid, or a private `d` member is present. |
| `JOSE-JWK-P256-S-ENCODING` | A coordinate is not an exact canonical 32-byte Base64url value. |
| `JOSE-JWK-P256-S-PUBLIC` | The decoded SEC 1 point is invalid. |
| `JOSE-JWK-P256-S-CRYPTO` | Checked SHA-256 thumbprint derivation failed. |
| `JOSE-JWK-P256-S-INTERNAL` | Validation/staging threw and cleanup succeeded, or an impossible subordinate status occurred. |
| `JOSE-JWK-P256-S-RANGE` | A caller span has invalid physical geometry or crosses an admitted memory window. |
| `JOSE-JWK-P256-S-PROTECTED` | A caller span intersects BIOS/private/live-stack storage. |
| `JOSE-JWK-P256-S-PLATFORM` | Caller-memory qualification failed unexpectedly or returned an undocumented result. |

`JOSE-JWK-P256-STATUS-VALID?` validates this status vocabulary.
