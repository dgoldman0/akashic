# Canonical sandbox schema format

**Codec identity:** `org.akashic.sandbox.schema-tree-le`

This document defines the one canonical, pointer-free schema representation
used by the trusted sandbox host. It describes values encoded by
[`value-codec.md`](value-codec.md); it is not part of the neutral VM, bytecode
artifact, execution profile, or guest-visible ABI.

The format deliberately supports only:

```text
NULL BOOL I64 BYTES UTF8 LIST MAP
```

There are no unions, `ANY`, open maps, references, recursive definitions,
imports, native types, extension tags, or unknown-field preservation.

Normative requirements use **MUST**, **MUST NOT**, **SHOULD**, and **MAY** in
their usual sense.

## 1. Boundary and ownership

A schema is one immutable caller-owned byte span. Exactly one document starts
at byte zero, and its declared total must equal the supplied span length.
Leading bytes, trailing bytes, padding, concatenated roots, and out-of-band
payloads are invalid.

The trusted runtime owns schema validation and schema/value matching. The
neutral VM does not parse schemas and receives no schema pointer. A host may
retain validated schema bytes or a digest-pinned declaration, but guest code
cannot inspect or mutate either.

Validation is allocation-free. The caller supplies a cell-aligned, self-bound
workspace sized for an explicit maximum depth. The implementation keeps no
mutable module scratch. Schema bytes, value bytes, and the workspace must remain
mapped and quiescent for the complete synchronous call. The workspace must
not overlap either input span.

## 2. Integer and span rules

All multibyte integers are unsigned little-endian fixed-width fields:

- `u16` is 2 bytes;
- `u32` is 4 bytes; and
- `u64` is 8 bytes.

Every count, length, sum, extent, and pointer addition is checked before use.
A wire `u64` that cannot be represented as a nonnegative host length is
invalid. Counts and lengths are definite; there are no terminators,
indefinite records, offsets, handles, backreferences, or alignment padding.

## 3. Document header

Every document begins with this exact 32-byte header:

| Offset | Bytes | Field | Canonical rule |
|---:|---:|---|---|
| 0 | 8 | magic | ASCII `AKSCHEMA` |
| 8 | 2 | version | `1` |
| 10 | 2 | flags | zero |
| 12 | 4 | node count | exact positive count of schema nodes |
| 16 | 4 | maximum depth | exact positive tree depth; root depth is 1 |
| 20 | 4 | reserved | zero |
| 24 | 8 | total bytes | exact complete document span |

One schema node immediately follows the header. Its complete extent must equal
`total bytes - 32`. The validator recomputes node count and maximum depth and
requires exact agreement with the header. These fields are canonical
cross-checks, not trusted allocation instructions.

## 4. Common schema-node header

Every schema occurrence starts with this exact 32-byte header:

| Offset | Bytes | Field | Meaning |
|---:|---:|---|---|
| 0 | 1 | tag | exact schema type |
| 1 | 1 | flags | zero |
| 2 | 2 | reserved | zero |
| 4 | 4 | child/member count | type-specific |
| 8 | 8 | lower bound | type-specific |
| 16 | 8 | upper bound | type-specific |
| 24 | 8 | payload bytes | exact bytes following this header |

Tags match the canonical value tags:

| Tag | Type |
|---:|---|
| `0` | `NULL` |
| `1` | `BOOL` |
| `2` | `I64` |
| `3` | `BYTES` |
| `4` | `UTF8` |
| `5` | `LIST` |
| `6` | `MAP` |

Tags `7` through `255` are invalid. An implementation must reject rather than
skip an unknown tag.

## 5. Type records and constraints

### 5.1 `NULL`, `BOOL`, and `I64`

These types have:

- child/member count `0`;
- lower bound `0`;
- upper bound `0`;
- payload bytes `0`; and
- no payload.

`I64` intentionally has no numeric-range constraint in version 1. Domain
range policy belongs in a later explicitly defined schema version rather than
an alternate interpretation of reserved fields.

### 5.2 `BYTES` and `UTF8`

These types have:

- child/member count `0`;
- lower bound equal to the minimum byte length;
- upper bound equal to the maximum byte length;
- payload bytes `0`; and
- no payload.

Both bounds are finite nonnegative lengths and `lower <= upper`. `UTF8` length
is the exact canonical UTF-8 byte length, not a code-point, grapheme, display,
or normalized length. The value codec's canonical UTF-8 rules still apply
independently.

### 5.3 `LIST`

`LIST` has:

- child count `1`;
- lower bound equal to the minimum item count;
- upper bound equal to the maximum item count; and
- payload bytes equal to the complete extent of exactly one inline child
  schema.

Both bounds are finite nonnegative counts and `lower <= upper`. Every value
element is matched against that same child schema. The child is an ordinary
inline schema node, so list element schemas are homogeneous and the schema
tree remains finite.

### 5.4 `MAP`

`MAP` has:

- member count equal to the exact number of declared fields;
- lower and upper bounds both zero; and
- payload bytes equal to the exact concatenation of its field records.

A map is closed. A matching value may contain only declared keys, must contain
every required key, and may omit optional keys. The empty closed map is
canonical with member count and payload bytes both zero.

There is no open-map bit and no additional-properties schema.

## 6. MAP field record

Every field begins with this exact 16-byte header:

| Offset | Bytes | Field | Canonical rule |
|---:|---:|---|---|
| 0 | 4 | key bytes | raw UTF-8 key byte length |
| 4 | 1 | flags | exactly `1` required or `2` optional |
| 5 | 1 | reserved | zero |
| 6 | 2 | reserved | zero |
| 8 | 8 | schema bytes | exact complete child-schema extent |

The header is followed immediately by:

```text
raw canonical UTF-8 key bytes
inline child schema node
```

There is no padding between these spans or after the field.

Fields are strictly increasing by unsigned lexicographic comparison of raw
UTF-8 key bytes, using the same comparison rule as canonical value MAP keys.
Equal keys are duplicates and invalid. No normalization, case folding,
locale collation, or decoded-code-point ordering is applied. Empty UTF-8 keys
are permitted and sort before every nonempty key.

Exactly one required/optional flag must be present. Zero, both bits, and every
unknown bit pattern are invalid.

## 7. Canonical-value validation and matching order

`SBOX-SCHEMA-VALUE-VALIDATE` performs three separate passes:

1. Validate the complete schema document.
2. Validate the complete value directly against
   `org.akashic.sandbox.value-tree-le`, including all headers, extents,
   canonical booleans, UTF-8, child counts, payload extents, and sorted unique
   MAP keys.
3. Match the already-valid value against the already-valid schema.

This order is normative. A malformed value is not downgraded to a type,
length, missing-key, or unknown-key mismatch merely because the mismatch is
discoverable first. Conversely, a canonical value with the wrong type,
out-of-range byte/item count, missing required field, or unknown field returns
`VALUE_MISMATCH`.

Schema and value validation use the exact complete-span rule. The matcher
does not materialize native value objects and does not publish borrowed
subspans; it walks the canonical bytes directly.

## 8. Exact schema digest

After successful complete-document validation, the schema content digest is:

```text
SHA3-256(
  ASCII("akashic.sandbox.schema") ||
  0x00 ||
  exact canonical schema document bytes
)
```

The ASCII domain contributes exactly the displayed bytes without a
terminator. The following `0x00` is one separate byte.

This digest identifies schema content only. It does not prove module,
declaration, artifact, profile, Practice, package, or owner identity. Those
identities must be pinned separately by the Stage 2 resolver and included in
the declaration/module digest domains where specified.

## 9. Runtime API

`akashic/runtime/sandbox-schema.f` publishes:

```forth
SBOX-SCHEMA-WORKSPACE-MEASURE
  ( max-depth -- bytes|0 status )

SBOX-SCHEMA-WORKSPACE-INIT
  ( max-depth workspace workspace-u -- status )

SBOX-SCHEMA-WORKSPACE-VALID?
  ( workspace -- flag )

SBOX-SCHEMA-WORKSPACE-RELEASE
  ( workspace -- status )

SBOX-SCHEMA-VALIDATE
  ( schema schema-u workspace -- status )

SBOX-SCHEMA-VALUE-VALIDATE
  ( schema schema-u value value-u workspace -- status )
```

Metric queries report the most recent completed walk:

```forth
SBOX-SCHEMA-WORKSPACE-MAX-DEPTH@
SBOX-SCHEMA-WORKSPACE-SCHEMA-NODES@
SBOX-SCHEMA-WORKSPACE-SCHEMA-DEPTH@
SBOX-SCHEMA-WORKSPACE-VALUE-NODES@
SBOX-SCHEMA-WORKSPACE-VALUE-DEPTH@
```

Public statuses are:

| Status | Meaning |
|---|---|
| `OK` | complete validation and, where requested, match |
| `INVALID` | invalid API argument or workspace state |
| `MALFORMED_SCHEMA` | noncanonical or structurally invalid schema bytes |
| `MALFORMED_VALUE` | noncanonical or structurally invalid value bytes |
| `VALUE_MISMATCH` | canonical value does not satisfy the schema |
| `CAPACITY` | caller workspace depth cannot admit the declared/walked depth |
| `ALIAS` | an input overlaps the mutable workspace |
| `RANGE` | caller span is not an admitted mapped range |
| `PROTECTED` | caller span reaches protected memory |
| `PLATFORM` | caller-span qualification failed at the platform boundary |

The workspace is synchronous operation state, not a durable schema object.
It self-binds to detect relocation, retains no input pointers after return,
and is explicitly releasable by zeroing.

## 10. Host integration

Schema validation is admission policy, not an instruction-loop operation.
A Stage 2 host should validate and digest declaration schemas when publishing
or retaining its exact immutable plan. Per invocation, canonical input bytes
are independently validated and matched before VM input publication;
canonical output candidate bytes are independently validated and matched
before trusted output publication.

No schema walk belongs in the VM hot loop. Reusing an already validated,
digest-pinned immutable schema does not weaken per-value validation and avoids
re-parsing schema policy on each execution slice.
