# OAuth DPoP ES256 proof construction

`security/oauth2/dpop-es256.f` constructs one RFC 9449 DPoP proof JWT with a
P-256 private key. It is a standalone proof-construction boundary: it does not
perform HTTP, endpoint discovery, URI normalization, OAuth exchanges, nonce or
token storage, clock reads, session persistence, or proof verification.

```forth
REQUIRE security/oauth2/dpop-es256.f
```

## Public API

```forth
OAUTH2-DPOP-ES256-MAX-METHOD-BYTES  ( -- 32 )
OAUTH2-DPOP-ES256-MAX-HTU-BYTES     ( -- 4096 )
OAUTH2-DPOP-ES256-MAX-NONCE-BYTES   ( -- 4096 )
OAUTH2-DPOP-ES256-JTI-SIZE          ( -- 22 )
OAUTH2-DPOP-ES256-MAX-PROOF-BYTES   ( -- 11459 )
OAUTH2-DPOP-ES256-WORKSPACE-SIZE    ( -- bytes )

OAUTH2-DPOP-ES256-STATUS-VALID?  ( status -- flag )
OAUTH2-DPOP-ES256-WORKSPACE-CLEAR
  ( workspace -- status )

OAUTH2-DPOP-ES256-PROOF
  ( htm htm-u htu htu-u iat
    nonce nonce-u access-token access-token-u private
    destination capacity workspace -- written status )
```

On success, `PROOF` publishes an unpadded three-segment compact JWT and returns
its exact byte length with `OAUTH2-DPOP-ES256-S-OK`.

The protected header is:

```json
{"typ":"dpop+jwt","alg":"ES256","jwk":{...public P-256 JWK...}}
```

The payload always contains `jti`, `htm`, `htu`, and `iat`. It includes
`nonce` when a nonempty nonce is supplied and `ath` when a nonempty access
token is supplied. `ath` is the canonical unpadded Base64url encoding of
SHA-256 over the ASCII encoding of the exact access-token value.

## Caller and transport boundary

The caller supplies the creation time as a nonnegative integer NumericDate.
The constructor does not read or assess a clock.

`htm` must be a nonempty RFC 9110 method token of at most 32 bytes. It is
copied exactly and remains case-sensitive.

`htu` must be the transport's already normalized request target:

- an absolute HTTP target beginning exactly with `http://` or `https://`;
- at most 4096 visible ASCII bytes;
- without a query (`?`) or fragment (`#`);
- directly JSON-safe, excluding a raw quote or backslash; and
- with a nonempty authority prefix.

These checks enforce the proof-construction boundary but do not normalize or
fully parse a URI, and they deliberately do not impose TLS policy. In
particular, this module does not lowercase hosts,
remove default ports, resolve dot segments, choose the externally visible
origin, or strip query/fragment components. The HTTP/URI layer must perform
those operations before calling `PROOF` and must pass the exact normalized
value that corresponds to the outgoing request. A production OAuth/ATProto
transport profile is responsible for requiring HTTPS.

An optional value is absent only when supplied as `(0,0)`. A present nonce
must satisfy RFC 9449's `1*NQCHAR` syntax and is copied exactly; the
constructor does not decode, compare, rotate, or otherwise interpret it. A
present access token must satisfy RFC 9449's `token68` credential syntax:
one or more ASCII letters, digits, `-`, `.`, `_`, `~`, `+`, or `/`, followed
only by optional `=` padding. The value remains opaque and is never copied
into the proof; only the SHA-256 digest of its exact ASCII bytes contributes
to `ath`.

## Key and unique identifier

The caller supplies one 32-byte P-256 private scalar. The constructor derives
the matching public key internally, validates it through the P-256 boundary,
and emits only that public key through the strict JWK encoder. A mismatched
caller-supplied public key is therefore impossible, and private key material
never enters the JOSE header.

Each admitted construction obtains 16 fresh bytes through `ENTROPY-FILL` and
encodes them as the 22-character `jti`. A retry, including a retry after a
server nonce challenge, must call `PROOF` again and therefore receives a new
identifier and signature.

## Statuses

| Status | Meaning |
|---|---|
| `OAUTH2-DPOP-ES256-S-OK` | Complete compact proof published |
| `OAUTH2-DPOP-ES256-S-INVALID` | Invalid pointer, signed length/capacity, optional pair, or wrapping span |
| `OAUTH2-DPOP-ES256-S-METHOD` | `htm` is empty, too large, or not an HTTP token |
| `OAUTH2-DPOP-ES256-S-HTU` | `htu` violates the absolute HTTP/no-query/no-fragment input boundary |
| `OAUTH2-DPOP-ES256-S-NONCE` | A present nonce is too large or violates `NQCHAR` |
| `OAUTH2-DPOP-ES256-S-TOKEN` | A present access token violates DPoP `token68` credential syntax |
| `OAUTH2-DPOP-ES256-S-TIME` | `iat` is negative |
| `OAUTH2-DPOP-ES256-S-CAPACITY` | Destination cannot hold the exact proof |
| `OAUTH2-DPOP-ES256-S-ALIAS` | A wiped or secret span overlaps a forbidden operand |
| `OAUTH2-DPOP-ES256-S-ENTROPY` | Hardware entropy was unavailable |
| `OAUTH2-DPOP-ES256-S-KEY` | The private P-256 scalar is invalid |
| `OAUTH2-DPOP-ES256-S-CRYPTO` | P-256, SHA-256, or ES256 processing failed |
| `OAUTH2-DPOP-ES256-S-INTERNAL` | An impossible subordinate result or layout mismatch occurred |
| `OAUTH2-DPOP-ES256-S-RANGE` | Caller memory has invalid physical geometry |
| `OAUTH2-DPOP-ES256-S-PROTECTED` | Caller memory intersects platform-private storage |
| `OAUTH2-DPOP-ES256-S-PLATFORM` | Caller-memory qualification failed unexpectedly |

Preflight rejection returns zero and leaves the destination and workspace
unchanged. Once admitted, any returned failure leaves the destination
unpublished and clears the complete workspace.

## Staging and cleanup

The workspace contains transient operand pointers, the staged private and
derived public keys, raw and encoded `jti`, optional `ath`, exact header and
payload bytes, the complete compact proof, and nested JWK/JWS workspaces.
There is no mutable module-owned operation state.

The private key is snapshotted before construction. Entropy acquisition, key
derivation, public-JWK emission, token hashing, JSON construction, and compact
ES256 signing all finish in workspace storage before the destination changes.
Only the final proof-length span is published.

All borrowed source spans must remain readable and byte-stable until `PROOF`
returns. The constructor does not retain them afterward.

The complete advertised destination span and all borrowed inputs must be
disjoint from the workspace because that workspace is wiped independently.
The destination must also be disjoint from the private key. Other borrowed
request values may overlap destination capacity: they have all been consumed
before terminal publication.

Admitted normal returns clear the complete workspace. An operation or
publication `THROW` is reissued after cleanup, while a cleanup `THROW` takes
precedence. As with the lower JOSE primitives, a fault during the final
publication may leave a partial destination and therefore is never converted
into an ordinary status.

## Example

```forth
CREATE dpop-private 32 ALLOT
CREATE dpop-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES ALLOT
CREATE dpop-work OAUTH2-DPOP-ES256-WORKSPACE-SIZE ALLOT

S" POST"
S" https://server.example.com/token"
1710000000
0 0                         \ no server nonce
0 0                         \ no access token on a token request
dpop-private
dpop-proof OAUTH2-DPOP-ES256-MAX-PROOF-BYTES dpop-work
OAUTH2-DPOP-ES256-PROOF
```

The transport sends the published bytes as the value of the `DPoP` request
header. Protected-resource requests pass the exact access-token value so the
proof also contains `ath`.
