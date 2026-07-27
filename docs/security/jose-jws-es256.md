# akashic-security-jose-jws-es256 — Compact JWS with ES256

`jose/jws-es256.f` implements the ordinary three-segment JWS Compact
Serialization with ECDSA P-256 and SHA-256. It owns no OAuth, DPoP, AT
Protocol, JWT-claim, key-discovery, or application-header policy.

```forth
REQUIRE akashic/security/jose/jws-es256.f
```

`PROVIDED akashic-security-jose-jws-es256` — requires strict JOSE Base64url
and JSON, SHA-256, ECDSA-P256, `utils/memory-span.f`, and
`utils/caller-span.f`.

## Profile and bounds

```text
BASE64URL(protected) "." BASE64URL(payload) "." BASE64URL(r || s)
```

- the protected header is a nonempty JSON object of at most 4096 decoded
  bytes and 64 members;
- the payload is an arbitrary byte string of at most 65536 bytes and may be
  empty;
- all three segments use canonical unpadded Base64url;
- the signature is exactly 64-byte big-endian `r || s`, never DER;
- the compact serialization is at most 92932 bytes;
- detached payloads and empty protected or signature segments are rejected.

The protected object must contain exactly one decoded `alg` member whose
string value is `"ES256"`. Other protected members are retained for the
application to inspect. A `b64` member is always rejected because RFC 7797
unencoded-payload semantics are outside this API. A `crit` member is also
always rejected: this profile implements no JWS extensions and therefore
cannot truthfully claim to understand any critical extension. Applications
remain responsible for their own required noncritical headers after
successful verification.

## API

```forth
JOSE-JWS-ES256-MAX-PROTECTED-BYTES  ( -- 4096 )
JOSE-JWS-ES256-MAX-PAYLOAD-BYTES    ( -- 65536 )
JOSE-JWS-ES256-MAX-COMPACT-BYTES    ( -- 92932 )
JOSE-JWS-ES256-SIGNATURE-SIZE       ( -- 64 )
JOSE-JWS-ES256-WORKSPACE-SIZE       ( -- bytes )

JOSE-JWS-ES256-COMPACT-SIZE
  ( protected-u payload-u -- compact-u status )

JOSE-JWS-ES256-SIGN
  ( protected protected-u payload payload-u private
    destination capacity workspace -- written status )

JOSE-JWS-ES256-VERIFY
  ( compact compact-u public
    protected-output protected-capacity
    payload-output payload-capacity workspace
    -- protected-u payload-u valid? status )

JOSE-JWS-ES256-WORKSPACE-CLEAR
  ( workspace -- status )
```

Signing preserves the caller's exact protected-header JSON bytes. It stages
the complete compact result, including the deterministic raw ES256
signature, before publishing any destination byte.

Verification signs over the exact first two encoded segments from the compact
input. It stages the decoded protected header and payload and publishes
neither unless the signature is valid. On success it returns their exact
decoded lengths, `TRUE`, and `JOSE-JWS-ES256-S-OK`.

A well-formed compact JWS with a mathematically incorrect signature returns:

```forth
0 0 FALSE JOSE-JWS-ES256-S-OK
```

Malformed serialization, keys, or signature scalars return a nonzero status.
No decoded output is published in either case.

All complete operation spans are admitted through `CALLER-SPAN-STATUS` and
the reserved boundaries exported by SHA-256 and ECDSA before mutation.
Range, protected-memory, and platform failures remain distinct. Operation
operands must be disjoint according to the selected sign or verify shape,
including the full supplied verification output capacities. Geometry
rejection leaves caller memory unchanged. Once admitted, the module clears
its entire caller workspace after success or ordinary rejection. An admitted
operation or publication `THROW` is reissued after cleanup; a cleanup
`THROW` propagates with precedence.

## Status values

| Status | Meaning |
|---|---|
| `JOSE-JWS-ES256-S-OK` | The operation completed; consult `valid?` for verification. |
| `JOSE-JWS-ES256-S-INVALID` | An argument or span is invalid. |
| `JOSE-JWS-ES256-S-CAPACITY` | A configured input bound or output capacity was exceeded. |
| `JOSE-JWS-ES256-S-ALIAS` | Public operands overlap. |
| `JOSE-JWS-ES256-S-COMPACT` | The three-segment compact structure is invalid. |
| `JOSE-JWS-ES256-S-ENCODING` | A Base64url segment is noncanonical or invalid. |
| `JOSE-JWS-ES256-S-JSON` | The protected segment is not a strict JSON object. |
| `JOSE-JWS-ES256-S-ALGORITHM` | `alg` is missing, duplicated, mistyped, or not `ES256`. |
| `JOSE-JWS-ES256-S-POLICY` | The protected header contains unsupported `b64` or `crit` extension semantics. |
| `JOSE-JWS-ES256-S-KEY` | The supplied P-256 key is invalid. |
| `JOSE-JWS-ES256-S-SIGNATURE` | Signature geometry or raw scalar encoding is invalid. |
| `JOSE-JWS-ES256-S-CRYPTO` | Checked SHA-256 or ECDSA processing failed. |
| `JOSE-JWS-ES256-S-INTERNAL` | An impossible subordinate result occurred. |
| `JOSE-JWS-ES256-S-RANGE` | A complete caller span has invalid or unmapped physical geometry. |
| `JOSE-JWS-ES256-S-PROTECTED` | A caller span intersects BIOS, stack, or other platform-private memory. |
| `JOSE-JWS-ES256-S-PLATFORM` | Caller-span qualification failed unexpectedly. |

`JOSE-JWS-ES256-STATUS-VALID?` validates this status vocabulary.
