# akashic-hmac-sha256 — Transactional HMAC-SHA-256

`hmac-sha256.f` provides a generic RFC 2104 HMAC-SHA-256 primitive. It owns no
key, protocol state, or mutable module scratch.

```forth
REQUIRE akashic/math/hmac-sha256.f
```

`PROVIDED akashic-hmac-sha256` — requires `math/sha256.f` and
`utils/memory-span.f`.

## API

```forth
HMAC-SHA256-DIGEST-SIZE      ( -- 32 )
HMAC-SHA256-WORKSPACE-SIZE   ( -- 192 )
HMAC-SHA256-STATUS-VALID?    ( status -- flag )
HMAC-SHA256-WORKSPACE-CLEAR  ( workspace -- status )

HMAC-SHA256
  ( key key-u message message-u digest workspace -- status )
```

Keys of any nonnegative length are accepted. Keys longer than SHA-256's
64-byte block size are hashed before use. Empty keys and messages may use
address zero with length zero.

The caller supplies a writable 192-byte workspace. It holds all transient
pointers, normalized key material, inner state, and staged output. The key and
message may overlap one another, but neither input may overlap the 32-byte
digest or the workspace; the digest and workspace must also be disjoint.

Geometry and alias rejection occur before either the digest or workspace is
changed. Once admitted:

- both SHA-256 passes complete before the digest is published;
- the entire workspace is cleared before success or a lower-layer failure is
  returned;
- any nonzero checked SHA-256 status is mapped to
  `HMAC-SHA256-S-CRYPTO`;
- an unexpected pre-publication computation `THROW` is mapped to
  `HMAC-SHA256-S-CRYPTO` only after the workspace wipe completes;
- digest publication is outside that exception-normalizing boundary;
- the digest remains unchanged on every returned failure.

A `THROW` is intentionally different from a returned status. If digest
publication throws, `MOVE` may already have written part or all of the
destination. HMAC makes a best-effort workspace wipe and rethrows the
publication exception when that wipe succeeds. If any mandatory workspace
wipe throws—after computation failure, publication failure, or successful
publication—the cleanup exception propagates. A pre-publication cleanup
fault still leaves the digest unchanged, but workspace containment is
unknown. A publication fault makes the digest ambiguous; when its original
exception is rethrown, the workspace wipe completed. A cleanup exception
during or after publication makes both properties ambiguous. No ordinary
status is returned with a false containment guarantee.

`HMAC-SHA256-WORKSPACE-CLEAR` explicitly clears a valid workspace and is
useful before releasing or reassigning caller storage. Its returned
`HMAC-SHA256-S-OK` proves the wipe completed; a cleanup `THROW` propagates.

## Status values

| Status | Meaning |
|---|---|
| `HMAC-SHA256-S-OK` | The 32-byte digest was published and the workspace was cleared. |
| `HMAC-SHA256-S-INVALID` | A length or fixed-span geometry is invalid. |
| `HMAC-SHA256-S-ALIAS` | A forbidden input, output, or workspace overlap was found. |
| `HMAC-SHA256-S-CRYPTO` | A checked SHA-256 operation failed before public digest publication and the workspace was cleared. |

## Example

```forth
CREATE mac       HMAC-SHA256-DIGEST-SIZE ALLOT
CREATE hmac-work HMAC-SHA256-WORKSPACE-SIZE ALLOT

key key-u message message-u mac hmac-work HMAC-SHA256
DUP IF
    \ mac was not published.
    THROW
THEN
DROP
```

Independent calls may use independent workspaces. SHA-256's shared hardware
accumulator and engine state are serialized by the lower-level hash boundary.
