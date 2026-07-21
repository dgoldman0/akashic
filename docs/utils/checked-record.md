# Checked records

`akashic/utils/checked-record.f` provides one allocation-free envelope for
fixed-size and aligned variable-size records. It is a byte codec, not a
storage service: it selects no path, opens no file, chooses no A/B slot,
orders no generation, and publishes no live applet state.

The caller owns an immutable specification, one workspace per concurrent or
nested operation, the encoded record buffer, and all domain payloads. The
module has no mutable private scratch or process-global current operation.

## Envelope

Every record begins with this 64-byte native little-endian MegaPad-64 header:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 8 | specification magic, compared as exactly eight bytes |
| 8 | 8 | format |
| 16 | 8 | header size, exactly 64 |
| 24 | 8 | caller-defined verified tag |
| 32 | 8 | logical payload size |
| 40 | 8 | CRC-32 of the logical payload |
| 48 | 8 | CRC-32 of header bytes 0–47 and 56–63 |
| 56 | 8 | flags, currently zero |
| 64 | variable | logical payload, followed by canonical zero padding |

The tag is deliberately neutral. A generation-based store can require a
positive tag; a record without such an identity can require zero; a domain
that owns the complete cell can admit any tag. The record codec verifies and
returns the tag but never compares two tags or assigns ordering semantics.

A fixed specification names one exact payload size and one exact record size.
The record may reserve a zero tail after the payload. A framed specification
names minimum and maximum payload sizes plus a power-of-two alignment. Its
record size is `ALIGN(64 + payload-u, alignment)`. All geometry is checked in
the nonnegative signed-length domain before arithmetic is performed.

## Statuses

```text
CREC-S-OK          CREC-S-INVALID      CREC-S-CAPACITY
CREC-S-CHECKSUM    CREC-S-UNSUPPORTED  CREC-S-CORRUPT
CREC-S-SEMANTIC    CREC-S-CALLBACK     CREC-S-BUSY
CREC-S-FAULT
```

`INVALID` describes a bad API argument, descriptor, span, tag supplied for
encoding, or prohibited alias. `CAPACITY` describes a valid request that does
not fit a declared bound. `CHECKSUM`, `UNSUPPORTED`, and `CORRUPT` classify
record bytes. `SEMANTIC` is the conventional domain-validator rejection.
`CALLBACK` contains a thrown callback or an out-of-range callback status.
`BUSY` rejects recursive use of the same workspace. `FAULT` contains a throw
from codec machinery or a dependency such as the hardware CRC transaction.

Typed adapters should explicitly translate these statuses into their own
public domain. The generic status set is not an applet status namespace.

## Specification lifecycle

The caller allocates `CREC-SPEC-SIZE` bytes. Initialization copies the
eight-byte record magic into the descriptor, so no borrowed magic pointer
survives.

```forth
CREC-SPEC-INIT
  ( magic-a magic-u format tag-policy encode-xt validate-xt spec -- status )
CREC-SPEC-FIXED!  ( payload-u record-u spec -- status )
CREC-SPEC-FRAMED!
  ( payload-min payload-max alignment spec -- status )
CREC-SPEC-SEAL    ( spec -- status )
CREC-SPEC-VALID?  ( spec -- flag )
CREC-SPEC-SEALED? ( spec -- flag )
CREC-MEASURE      ( payload-u spec -- record-u status )
```

The tag policies are `CREC-TAG-ANY`, `CREC-TAG-ZERO`, and
`CREC-TAG-POSITIVE`. Geometry can be selected once. Sealing validates the
complete descriptor and makes it admissible to record operations; the public
API provides no post-seal mutation. A raw byte-copy of a specification is
invalid because each descriptor is bound to its own address.

Initialization and geometry setters validate all inputs before changing the
descriptor. A magic span may not overlap its destination specification.
Reinitialize a fresh descriptor rather than constructing format-version
stacks or compatibility readers around an obsolete prototype layout.

## Callback ABI

The specification owns two execution tokens. Encoding receives a bounded,
zeroed payload span inside the output record:

```forth
( context-a context-u payload-a payload-u verified-tag -- crec-status )
```

Validation receives the same shape after all mechanical checks succeed:

```forth
( context-a context-u immutable-payload-a payload-u verified-tag
  -- crec-status )
```

An empty context is exactly `0 0`; a nonempty context must be nonnull and
nonwrapping. Callbacks may return any valid `CREC-S-*` value, although normal
typed adapters use `OK`, `SEMANTIC`, `CAPACITY`, or `INVALID`. An out-of-range
result is normalized to `CALLBACK`.

A callback throw never escapes. The operation workspace returns to idle and
publishes no result. Validation leaves the input record untouched. Encoding
preflight failures leave the destination untouched; after a callback has been
admitted, any callback failure, callback throw, or codec fault wipes the exact
derived record span so a partial record cannot be mistaken for output.

The callback can address only its context and logical payload through this
ABI. After a successful encoder returns, the core rewrites the entire header
and zeroes the complete fixed tail or framed pad before computing CRCs.
Adapters remain responsible for pointers reachable *through* an opaque
context; they must not let such a graph point into the output envelope.

## Workspace and operations

The caller allocates `CREC-WORK-SIZE` bytes for every independently active
operation:

```forth
CREC-WORK-INIT   ( work -- status )
CREC-WORK-VALID? ( work -- flag )

CREC-INSPECT-HEADER
  ( record-a available-u spec work -- status )
CREC-ENCODE
  ( context-a context-u payload-u tag record-a capacity spec work
    -- record-u status )
CREC-VALIDATE
  ( context-a context-u record-a exact-record-u spec work -- status )
```

`INSPECT-HEADER` needs only the first 64 available bytes. It authenticates the
header and publishes the derived complete record size, payload size, and tag,
but does not claim that a payload is present or valid. This is the appropriate
primitive for bounded readers and maintenance classifiers.

`VALIDATE` requires the exact complete record length. On success it publishes
a borrowed payload view. `ENCODE` derives and preflights the complete size,
zeroes exactly that span, invokes the encoder, canonicalizes the envelope and
padding, and publishes the same view. Bytes between the derived record size
and the caller's larger capacity are never changed.

Results live in the workspace and are published only after success:

```forth
CREC-WORK-STATUS@ ( work -- status )
CREC-RESULT-KIND@ ( work -- kind )
CREC-RECORD-U@    ( work -- record-u|0 )
CREC-PAYLOAD-U@   ( work -- payload-u|0 )
CREC-TAG@         ( work -- tag|0 )
CREC-PAYLOAD$     ( work -- payload-a payload-u )
```

Result kinds are `CREC-RESULT-INSPECTED`, `CREC-RESULT-VALIDATED`, and
`CREC-RESULT-ENCODED`. `PAYLOAD$` deliberately returns `0 0` for an inspected
header, even when the advertised payload size is nonzero. Failed operations
clear all prior result fields.

The same workspace cannot be entered recursively and returns `BUSY` before
its current arguments or results are touched. A callback may use another
workspace, including with another specification. CRC computation is complete
before validation callbacks begin and starts only after encoding callbacks
return, so the hardware CRC stream is never held across domain code.

## Validation order

Mechanical validation has one fixed order:

1. Validate caller spans, sealed descriptors, workspace state, and aliases.
2. Require at least the 64-byte header.
3. Compare the eight-byte magic.
4. Verify the header CRC.
5. Classify format: exact is accepted, a greater checksummed format is
   `UNSUPPORTED`, and a lower format is `CORRUPT`.
6. Check header size, zero flags, tag policy, payload bounds, and overflow-safe
   fixed/framed geometry.
7. For complete validation, require the exact derived record length.
8. Verify the payload CRC.
9. Reject nonzero fixed-tail or framed-padding bytes.
10. Invoke the semantic validator.

Thus damaged headers cannot masquerade as future formats, hidden padding is
never admitted, and domain code never runs on mechanically corrupt bytes.

## Alias and ownership rules

All declared spans use overflow-safe half-open geometry. Exact adjacency is
accepted. Specifications and workspaces must be disjoint. Record input/output
must be disjoint from both, and callback context must be disjoint from the
record, specification, and workspace. Encoding rejects a context that
overlaps any byte of the derived output record. Validation is borrowed and
read-only; a typed decoder should copy into live state only after it returns
`CREC-S-OK`.

No operation allocates, performs I/O, retains a payload, or serializes
independent workspaces. Durability, inactive-slot writes, split-brain policy,
and live publication remain responsibilities of the storage adapter above
this codec.
