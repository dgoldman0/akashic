# akashic-security-jose-base64url — Canonical Unpadded Base64url

`jose/base64url.f` is a strict RFC 4648 Base64url codec for JOSE. It is
independent of the permissive legacy network Base64 codec and owns no mutable
state. It has no OAuth, AT Protocol, Streams, transport, or application
policy.

```forth
REQUIRE akashic/security/jose/base64url.f
```

`PROVIDED akashic-security-jose-base64url` — requires
`utils/memory-span.f` and `utils/caller-span.f`.

## Accepted representation

Only the URL-safe alphabet is accepted:

```text
A-Z a-z 0-9 - _
```

Padding, whitespace, the standard Base64 `+` and `/` characters, and a
length congruent to one modulo four are rejected. Decoding also requires the
unused bits of a two-character tail to be zero in the low four positions and
the unused bits of a three-character tail to be zero in the low two
positions. This enforces RFC 4648 canonical pad-bit semantics even though
the JOSE representation itself is unpadded: alternate spellings of the same
byte string are rejected.

Empty input is valid, ignores its address, and therefore admits `( 0 0 )`.
Every nonempty source and every nonempty advertised destination-capacity
span must pass the generic caller-memory boundary. This rejects negative or
wrapping geometry, spans outside one mapped memory window, and protected
BIOS/private/live-stack storage before any byte is read or written.

## API

```forth
JOSE-B64URL-ENCODED-LENGTH
  ( source-u -- result-u status )

JOSE-B64URL-DECODED-LENGTH
  ( source source-u -- result-u status )

JOSE-B64URL-ENCODE
  ( source source-u destination capacity -- written status )

JOSE-B64URL-DECODE
  ( source source-u destination capacity -- written status )
```

`JOSE-B64URL-ENCODED-LENGTH` validates a raw source length and computes the
exact unpadded output length.

`JOSE-B64URL-DECODED-LENGTH` is deliberately address- and content-aware: it
first validates the complete encoded source through `CALLER-SPAN-STATUS`,
then validates its alphabet, shape, and canonical tail bits before returning
the exact decoded length.

Both transforms validate the full source span, the full advertised
destination-capacity span, result length, capacity, and alias geometry before
writing. The source and exact result span must not overlap. Unused
destination capacity is still validated as mapped caller memory but is not
part of the overlap check because it is not written; a source may therefore
occupy that unused suffix. Exact adjacency is disjoint.

Every failure returned as a status leaves the destination unchanged. The
codec intentionally does not catch unexpected faults after admission: a
faulting read or write may make publication state ambiguous, so that fault
propagates instead of being mislabeled as an ordinary nonpublishing failure.
There is no mutable codec state, secret scratch, or mandatory cleanup whose
failure could be hidden. Callers must keep borrowed source bytes stable for
the duration of an operation.

Independent calls may run concurrently because the module has no workspace
or module-owned scratch.

## Status values

| Status | Meaning |
|---|---|
| `JOSE-B64URL-S-OK` | The exact length was computed or the result was written. |
| `JOSE-B64URL-S-INVALID` | A raw length is negative or encoded text is malformed/noncanonical. |
| `JOSE-B64URL-S-CAPACITY` | The exact result does not fit the supplied capacity or cell length. |
| `JOSE-B64URL-S-ALIAS` | The source overlaps the exact destination result. |
| `JOSE-B64URL-S-RANGE` | A complete nonempty caller span is outside one mapped memory window or has invalid address geometry. |
| `JOSE-B64URL-S-PROTECTED` | A caller span intersects BIOS/private/live-stack storage. |
| `JOSE-B64URL-S-PLATFORM` | Caller-memory qualification failed unexpectedly or returned an undocumented platform result. |

`JOSE-B64URL-STATUS-VALID?` validates this status vocabulary.

For mutating operations, source geometry is checked first, then the full
destination capacity, then content/length, capacity, and exact-write aliasing.
For `JOSE-B64URL-DECODED-LENGTH`, caller geometry precedes encoded-content
validation. This makes malformed text distinct from memory that was never
safe to inspect.
