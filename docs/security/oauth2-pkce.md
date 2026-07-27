# OAuth 2 PKCE S256

`security/oauth2/pkce.f` is a generic RFC 7636 Proof Key for Code Exchange
utility. It validates code verifiers, derives an S256 code challenge, and can
generate a verifier/challenge pair from checked hardware entropy.

```forth
REQUIRE security/oauth2/pkce.f
```

The module exposes only S256. It has no `plain` transformation, provider
policy, redirect handling, authorization request builder, token exchange, or
application state.

## Public API

```forth
OAUTH2-PKCE-VERIFIER-MIN             ( -- 43 )
OAUTH2-PKCE-VERIFIER-MAX             ( -- 128 )
OAUTH2-PKCE-GENERATED-VERIFIER-SIZE  ( -- 43 )
OAUTH2-PKCE-CHALLENGE-SIZE           ( -- 43 )
OAUTH2-PKCE-WORKSPACE-SIZE           ( -- 219 )

OAUTH2-PKCE-STATUS-VALID?    ( status -- flag )
OAUTH2-PKCE-VERIFIER-VALID?  ( verifier verifier-u -- flag )
OAUTH2-PKCE-WORKSPACE-CLEAR  ( workspace -- status )

OAUTH2-PKCE-S256
  ( verifier verifier-u challenge challenge-capacity workspace
    -- written status )

OAUTH2-PKCE-GENERATE
  ( verifier verifier-capacity challenge challenge-capacity workspace
    -- verifier-written challenge-written status )
```

`OAUTH2-PKCE-S256` validates a borrowed verifier, hashes its exact ASCII bytes
with SHA-256, and publishes the canonical unpadded Base64url encoding of that
digest. A successful call returns `43 OAUTH2-PKCE-S-OK`.

`OAUTH2-PKCE-GENERATE` obtains 32 bytes through `ENTROPY-FILL`, encodes them as
a 43-character canonical unpadded Base64url verifier, derives S256 from that
verifier, and then publishes both outputs. A successful call returns
`43 43 OAUTH2-PKCE-S-OK`.

## Verifier syntax

A caller-provided verifier is valid only when:

- its length is from 43 through 128 bytes, inclusive;
- every byte is ASCII `A-Z`, `a-z`, `0-9`, `-`, `.`, `_`, or `~`; and
- its address and length form a non-null, nonwrapping span.

The generation API deliberately chooses the RFC 7636-recommended 32 random
bytes. Their unpadded Base64url representation is exactly 43 characters and
is therefore a valid verifier.

## Statuses

| Status | Meaning |
|---|---|
| `OAUTH2-PKCE-S-OK` | Complete result published |
| `OAUTH2-PKCE-S-INVALID` | Malformed pointer, signed length/capacity, or wrapping span |
| `OAUTH2-PKCE-S-VERIFIER` | Caller verifier has an invalid length or character |
| `OAUTH2-PKCE-S-CAPACITY` | A valid output span has fewer than 43 bytes |
| `OAUTH2-PKCE-S-ALIAS` | Disallowed span overlap |
| `OAUTH2-PKCE-S-ENTROPY` | Checked entropy acquisition failed |
| `OAUTH2-PKCE-S-CRYPTO` | Checked SHA-256 challenge derivation failed |
| `OAUTH2-PKCE-S-INTERNAL` | An impossible lower-layer result was observed |
| `OAUTH2-PKCE-S-RANGE` | A complete caller span has invalid or unmapped physical geometry |
| `OAUTH2-PKCE-S-PROTECTED` | A caller span intersects BIOS, stack, or other platform-private memory |
| `OAUTH2-PKCE-S-PLATFORM` | Caller-span qualification failed unexpectedly |

Failure returns zero written lengths. Geometry, capacity, alias, and verifier
rejections occur before operation admission and leave both destinations and
the workspace unchanged. Once admitted, a failure leaves destinations
unpublished and clears the workspace.

## Capacity and alias geometry

Both output capacities may be larger than 43 bytes. A successful call writes
only the two exact 43-byte result spans. Bytes outside the union of those
publication spans remain untouched; one result may intentionally occupy bytes
that lie in the other result's otherwise-unused advertised capacity.

Input/output and generation output/output alias checks use only those exact
43-byte publication spans. Consequently:

- exact adjacency is disjoint;
- a deterministic verifier may occupy unused challenge capacity when it does
  not intersect the first 43 challenge bytes; and
- generated verifier and challenge capacities may overlap outside their
  disjoint 43-byte result spans.

Each complete advertised output-capacity span must remain disjoint from the
workspace. The borrowed deterministic verifier must also remain disjoint from
the complete workspace. These stronger workspace checks are necessary because
the entire workspace is wiped, including on contained exceptions.

## Staging, cleanup, and crypto ownership

The 219-byte caller workspace contains transient pointers plus fixed staging
for 32 entropy bytes, the generated verifier, the SHA-256 digest, and the
challenge. The module has no mutable global operation state.

All entropy, encoding, and hashing steps complete in workspace staging before
destination publication. A returned SHA-256 failure becomes
`OAUTH2-PKCE-S-CRYPTO`. Admitted calls execute behind `CATCH`; normal returns
and explicit status failures wipe the complete workspace. A lower-layer or
publication `THROW` is reissued after cleanup, and a mandatory-cleanup
`THROW` propagates with precedence. Rejected preflight calls do not claim or
wipe the workspace.

SHA-256 owns the shared crypto-accumulator transaction and SHA engine for each
one-shot hash. PKCE relies on that ownership transitively and does not acquire
the shared accumulator directly.

## Example

```forth
CREATE pkce-work      OAUTH2-PKCE-WORKSPACE-SIZE ALLOT
CREATE code-verifier  64 ALLOT
CREATE code-challenge 64 ALLOT

code-verifier 64 code-challenge 64 pkce-work
OAUTH2-PKCE-GENERATE
\ success: 43 43 OAUTH2-PKCE-S-OK
```

The caller retains the published verifier for the later authorization-code
exchange and sends the published challenge with method `S256`.
