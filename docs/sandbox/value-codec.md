# Canonical typed-value codec

**Status:** Stage 0 ratified canonical codec; implementation has not begun
**Codec identity:** `org.akashic.sandbox.value-tree-le`

This document defines the exact address-free byte representation of typed
values crossing the neutral sandbox boundary. It is the canonical codec for
the value types in
[`profile-and-abi.md`](profile-and-abi.md):

```text
NULL BOOL I64 BYTES UTF8 LIST MAP
```

The codec represents one finite value tree. It contains no native cell,
pointer, arena handle, schema, module identity, capability, import, execution
token, allocator metadata, or padding.

Normative requirements use **MUST**, **MUST NOT**, **SHOULD**, and **MAY** in
their usual sense.

## 1. Boundary and ownership

This codec owns only:

- canonical structural value bytes;
- exact scalar and aggregate decoding;
- exact UTF-8 validation;
- canonical MAP ordering;
- deterministic tree traversal and input-handle assignment;
- structural depth, node, and byte accounting; and
- domain-separated value-content digests.

It does not own:

- module declarations or their encoding;
- domain input or output schemas;
- schema validation;
- module, entry, artifact, or profile selection;
- invocation authority or capability policy;
- VM instruction semantics;
- durable storage; or
- a public result-record serialization.

The neutral VM produces a structurally valid candidate value graph. A later
trusted host stage may validate that candidate against a separately pinned
module declaration and output schema before publishing a domain-level success.
That Stage 2 declaration/schema validation is not part of this codec and MUST
NOT be treated as having occurred merely because canonical encoding succeeds.

Likewise, canonical input decoding proves only that the supplied bytes are one
well-formed bounded value. The trusted host must separately perform any
required declaration/schema validation before admitting the decoded value as
an invocation input.

## 2. Integer conventions and complete-span rule

All multibyte integers are unsigned little-endian fixed-width fields unless a
type rule explicitly interprets their bits as signed:

- `u16` is exactly 2 bytes;
- `u32` is exactly 4 bytes; and
- `u64` is exactly 8 bytes.

An encoded value is supplied as one explicitly bounded byte span. Exactly one
root record begins at byte zero, and that record's complete extent MUST equal
the supplied span length. Leading bytes, trailing bytes, alignment padding,
concatenated roots, and out-of-band payloads are invalid.

All counts and lengths are definite. There are no indefinite-length values,
terminators, sentinel counts, backreferences, shared-object records, or
extension trailers.

Before any read, allocation, copy, traversal, or alignment operation, an
implementation MUST validate every derived count, product, sum, and subspan
with checked arithmetic. A wire `u64` that cannot be represented safely in the
implementation's admitted signed-length domain is invalid even if later
profile limits would also reject it.

## 3. Common 16-byte value header

Every value occurrence begins with this exact 16-byte header:

| Offset | Bytes | Field | Rule |
|---:|---:|---|---|
| 0 | 1 | tag | exact value tag |
| 1 | 1 | flags | zero |
| 2 | 2 | reserved | zero |
| 4 | 4 | item count | type-specific canonical value |
| 8 | 8 | payload bytes | exact number of bytes following this header for this occurrence |

`payload bytes` covers the complete recursively encoded payload of this value,
but not this value's own 16-byte header.

The tag values are:

| Tag | Type |
|---:|---|
| `0` | `NULL` |
| `1` | `BOOL` |
| `2` | `I64` |
| `3` | `BYTES` |
| `4` | `UTF8` |
| `5` | `LIST` |
| `6` | `MAP` |

Tags `7` through `255`, nonzero flags, and nonzero reserved bits are invalid
for this codec. A decoder MUST reject them; it must not skip or preserve
them as an unknown value.

No encoded occurrence contains alignment padding. The next child or sibling
begins immediately after the preceding occurrence's exact extent.

## 4. Scalar and blob encodings

### 4.1 NULL

`NULL` has:

- item count `0`;
- payload bytes `0`; and
- no payload.

Any other count or payload length is invalid.

### 4.2 BOOL

`BOOL` has:

- item count `0`;
- payload bytes `8`; and
- one little-endian `u64` payload.

The only canonical payload bit patterns are:

```text
false = 0x0000_0000_0000_0000
true  = 0xffff_ffff_ffff_ffff
```

Every other bit pattern is invalid. A decoder MUST NOT reinterpret another
nonzero integer as true.

### 4.3 I64

`I64` has:

- item count `0`;
- payload bytes `8`; and
- one little-endian `u64` payload interpreted as the complete two's-complement
  bit pattern of the signed value.

Every `u64` bit pattern is a canonical `I64`; there is no separate sign byte,
variable-length integer, or alternative representation.

### 4.4 BYTES

`BYTES` has:

- item count `0`;
- payload bytes equal to the byte-string length; and
- exactly that many uninterpreted payload bytes.

The empty byte string is canonical. No terminator or padding follows it.

### 4.5 UTF8

`UTF8` has:

- item count `0`;
- payload bytes equal to the UTF-8 byte length; and
- exactly that many UTF-8 bytes.

The empty string is canonical. The payload MUST encode only Unicode scalar
values and MUST use the shortest legal UTF-8 form. Exact accepted byte
sequences are:

```text
00..7f
c2..df 80..bf
e0 a0..bf 80..bf
e1..ec 80..bf 80..bf
ed 80..9f 80..bf
ee..ef 80..bf 80..bf
f0 90..bf 80..bf 80..bf
f1..f3 80..bf 80..bf 80..bf
f4 80..8f 80..bf 80..bf
```

The decoder MUST reject:

- truncated sequences;
- stray continuation bytes;
- `c0`, `c1`, and `f5` through `ff`;
- overlong encodings;
- UTF-16 surrogate values `U+d800` through `U+dfff`; and
- values above `U+10ffff`.

The codec performs no Unicode normalization, case folding, locale operation,
grapheme processing, BOM removal, or NUL removal. U+0000 and U+FEFF are
ordinary scalar values when legally encoded. Canonically equivalent Unicode
strings with different UTF-8 bytes remain different codec values.

## 5. Aggregate encodings

### 5.1 LIST

`LIST` has:

- item count equal to the number of children;
- payload bytes equal to the checked sum of the complete encoded extents of
  those children; and
- exactly `item count` recursively encoded values concatenated without gaps.

The empty list has item count and payload bytes both zero.

The decoder MUST process exactly the advertised child count and require the
last child's end to equal the LIST payload end. Too few children, extra
children, a child crossing the payload end, or unused payload bytes are
invalid.

### 5.2 MAP

`MAP` has:

- item count equal to the number of entries;
- payload bytes equal to the checked sum of every encoded key and value
  occurrence; and
- exactly `item count` key/value pairs concatenated without gaps.

Each pair is encoded as:

```text
canonical UTF8 key occurrence
canonical value occurrence
```

A key MUST be a complete canonical `UTF8` occurrence. No other tag may be used
as a key.

MAP keys are ordered by unsigned lexicographic comparison of their raw UTF-8
payload bytes:

1. Compare the first differing byte as an unsigned value from 0 through 255.
2. The key containing the smaller byte sorts first.
3. If one complete key is a prefix of the other, the shorter key sorts first.
4. Equal byte sequences compare equal.

Keys in an encoded MAP MUST be strictly increasing under this comparison.
Equal raw key bytes are duplicates and are invalid. No normalization, case
folding, Unicode collation, locale rule, or decoded-code-point ordering is
applied before comparison. Two canonically equivalent Unicode strings may
both occur when their raw UTF-8 bytes differ and sort distinctly.

The canonical encoder requires MAP entries in this order and rejects unordered
or duplicate raw key bytes before emitting the MAP. A trusted host adapter may
sort an unordered native map before presenting it to the codec, but sorting is
not an alternative accepted wire representation. Entry insertion order, arena
allocation order, pointer order, and hash-table iteration order are not encoded
semantic data.

The empty map has item count and payload bytes both zero. As with LIST, the
decoder MUST consume exactly the advertised entry count and payload extent.

## 6. Canonical tree model

The wire representation is always a tree:

- every child is encoded inline;
- no handle or node identifier appears on the wire;
- no backreference or shared-subtree marker exists; and
- cycles are unrepresentable.

An input decoder creates one distinct input-arena node for every encoded value
occurrence. It MUST NOT intern equal strings, equal scalars, or equal
subtrees.

The VM's output arena may be a directed acyclic graph because multiple parents
may reference one already-published input or output handle. The canonical
output encoder expands that DAG into a tree. Every handle occurrence is
recursively encoded in full, even when the same handle was encoded earlier.
Sharing therefore cannot affect canonical bytes, node accounting, depth
accounting, or value-byte accounting.

Before output encoding, every referenced handle, arena selector, node tag,
payload range, and child edge MUST be validated. The encoder MUST detect and
reject a cycle defensively even though conforming output constructors cannot
publish one.

For MAP output, the encoder obtains each key's validated raw UTF-8 bytes,
requires strict canonical order, rejects duplicates, and traverses entries in
that validated order. For all other aggregates, it traverses children in
stored LIST order.

## 7. Deterministic input-handle assignment

Input handles are assigned in canonical preorder after complete structural
validation and budget preflight:

1. The root occurrence receives input handle `1`.
2. A node receives the next consecutive handle when its 16-byte header is
   encountered.
3. LIST children are visited from index zero through count minus one.
4. MAP entries are visited in their already validated canonical key order;
   within each entry, the key is visited before its value.
5. Each encoded occurrence receives a distinct handle, even when its bytes
   equal another occurrence.

The next handle is increased with checked arithmetic and may not cross
`0x7fff_ffff_ffff_ffff`. No input handle is zero or has its high bit set.

The decoder MUST validate the complete tree and reserve all required arena
capacity before publishing the root handle to an invocation. On any failure,
no partial input arena or apparently valid root handle may escape.

Deterministic handle assignment is an invocation-local ABI property. Handles
are not serialized, included in value digests, exposed as durable identities,
or accepted across invocations.

## 8. Exact accounting

The codec defines four separate measures:

- **wire bytes:** the exact encoded span length;
- **expanded nodes:** the number of recursively encoded value occurrences; and
- **expanded value bytes:** the canonical recursive semantic charge used for
  input trees and final returned roots; and
- **arena-own bytes:** the nonrecursive publication charge for one output
  arena node.

These measures are independent of native structure size, allocator headers,
alignment choices, spare capacity, and pointer width.

Define checked eight-byte padding:

```text
PAD8(n) = the least multiple of 8 greater than or equal to n
```

`PAD8(0)` is zero. Its computation MUST reject overflow.

For one occurrence `v`, wire-byte accounting is:

```text
WIRE(NULL)       = 16
WIRE(BOOL)       = 16 + 8
WIRE(I64)        = 16 + 8
WIRE(BYTES(n))   = 16 + n
WIRE(UTF8(n))    = 16 + n
WIRE(LIST)       = 16 + sum(WIRE(child))
WIRE(MAP)        = 16 + sum(WIRE(key) + WIRE(value))
```

Expanded-node accounting is:

```text
NODES(scalar-or-blob) = 1
NODES(LIST)           = 1 + sum(NODES(child))
NODES(MAP)            = 1 + sum(NODES(key) + NODES(value))
```

Expanded value-byte accounting is:

```text
VALUE-BYTES(NULL)       = 16
VALUE-BYTES(BOOL)       = 16 + 8
VALUE-BYTES(I64)        = 16 + 8
VALUE-BYTES(BYTES(n))   = 16 + PAD8(n)
VALUE-BYTES(UTF8(n))    = 16 + PAD8(n)
VALUE-BYTES(LIST)       = 16 + 8*count
                          + sum(VALUE-BYTES(child))
VALUE-BYTES(MAP)        = 16 + 16*count
                          + sum(VALUE-BYTES(key)
                                + VALUE-BYTES(value))
```

Output arena-own accounting is:

```text
ARENA-OWN(NULL)        = 16
ARENA-OWN(BOOL)        = 24
ARENA-OWN(I64)         = 24
ARENA-OWN(BYTES(n))    = 16 + PAD8(n)
ARENA-OWN(UTF8(n))     = 16 + PAD8(n)
ARENA-OWN(LIST)        = 16 + 8*count
ARENA-OWN(MAP)         = 16 + 16*count
```

The root is at depth `1`. Every child is at its parent's depth plus one. The
depth of a nonempty tree is the greatest occurrence depth; the depth of any
scalar, blob, or empty aggregate root is `1`.

All sums, products, depth increments, counters, and header extents use checked
arithmetic. Bounds are checked over the expanded tree:

- repeated DAG references count once per occurrence;
- every MAP key counts as a UTF8 node;
- every MAP value counts independently;
- identical encoded subtrees are not deduplicated; and
- sorting a MAP does not change its counts.

The effective profile limits apply simultaneously. For the pure-computation
profile these are `value_depth`, `blob_bytes`, `list_count`, `map_count`,
`input_value_nodes`, `input_value_bytes`, `output_arena_nodes`,
`output_arena_bytes`, `output_result_nodes`, and `output_result_bytes`.

Input decode checks its expanded measures against the two input fields before
publishing a root. Each successful output constructor increments
`output_arena_nodes` once and `output_arena_bytes` by only its new node's
`ARENA-OWN` charge. Referenced child content is not charged again to the
arena. Both counters are cumulative because the output arena is append-only;
unreachable published nodes remain charged until invocation teardown.

Separately, every new aggregate carries saturating expanded metadata calculated
from its children, and a constructor rejects any new root that is already
above the effective output-result bounds. At successful return the selected
root's expanded measures are independently validated and charged exactly once
to `output_result_nodes` and `output_result_bytes` before canonical transfer.
Repeated DAG references count once per occurrence in these result measures.
Arena and result counters never refund, offset, or substitute for one another.

Wire bytes, expanded value bytes, and arena-own bytes are deliberately
different. Wire bytes contain no alignment padding or edge charge; the other
two are deterministic semantic resource measures rather than claims about
native allocation size.

## 9. Canonical input and output digests

The canonical content digest of an admitted input value is:

```text
SHA3-256(
  ASCII("akashic.sandbox.value.input") ||
  0x00 ||
  exact canonical root bytes
)
```

The canonical content digest of a structurally valid output candidate is:

```text
SHA3-256(
  ASCII("akashic.sandbox.value.output") ||
  0x00 ||
  exact canonical root bytes
)
```

`ASCII(...)` contributes exactly the displayed bytes without a terminator.
The displayed `0x00` is one additional byte. SHA3-256 is the standardized
Keccak SHA-3 function with a 32-byte result.

The same canonical root bytes therefore have different input and output
digests. These digests identify value content and direction only. They do not
prove a schema match, artifact identity, profile identity, module ownership,
publisher trust, installation, invocation authority, or successful execution.
They are distinct from module-schema digests and from the artifact/profile
digests recorded by the sandbox.

### 9.1 Golden vectors

Hex below is lowercase and contains no separators. Hashes are SHA3-256 under
the exact domains above.

| Value | Bytes | Canonical hex |
|---|---:|---|
| `NULL` | 16 | `00000000000000000000000000000000` |
| `BOOL false` | 24 | `010000000000000008000000000000000000000000000000` |
| empty `LIST` | 16 | `05000000000000000000000000000000` |
| `LIST[I64(1), UTF8("a")]` | 57 | `050000000200000029000000000000000200000000000000080000000000000001000000000000000400000000000000010000000000000061` |

| Value | Input digest | Output digest |
|---|---|---|
| `NULL` | `3679ab8fa4f056e0afb71507aba719731b5eeec61e67c32815f45f72f6b17985` | `d1c81f321018107e79f2c9fe56cd3c4c2a9cd05643aa509c198c29ad20bb6a57` |
| `BOOL false` | `923ec17b4f307b8783910ee2c7840364c98bd7a6e60ec93d09afa4a2d569e31f` | `979d98a7fe52f23e6f11c43b74c4c3b593376a77d55a163e86731414e7a322c8` |
| empty `LIST` | `f3bf58e103e958028e01da5a7e9fe854984d7c54278108b2bad8ee0e305825f9` | `cae893dd996127304e724f4e23263b2c11c621695be2c1d48f00b3e8eb6930d0` |
| `LIST[I64(1), UTF8("a")]` | `5088c61570cb9bcb98f7248b203ab93754e9948749b08725edfe292d77947f58` | `33f888fd8bd796eeb978412ffdb67632b57cf05e556797a34f297ace60e64d4d` |

## 10. Determinism and result layering

For one semantic value, this codec emits exactly one canonical byte span.
A conforming decoder followed by a conforming encoder MUST reproduce that span
byte for byte.

The neutral execution layers are:

```text
verified VM execution
        |
        v
structurally valid candidate value graph
        |
        v
disjoint result-owned canonical bytes and output-content digest
        |
        v
Stage 2 declaration and domain-schema validation
        |
        v
trusted host publication or domain-level rejection
```

The precise placement of encoding relative to Stage 2 schema validation may be
fused by an implementation, but the checks and failure ownership remain
distinct. Codec success MUST NOT be reported as schema success, and schema
failure MUST NOT be reported as malformed canonical bytes.

There is no claim that two in-memory value arenas, candidate graphs, host
objects, result records, or allocator buffers are byte-identical. They may
contain different addresses, padding, capacities, scratch state, and
invocation-local handles. Determinism applies to:

- the semantic structural result;
- the exact canonical encoded root bytes;
- the corresponding direction-specific content digest; and
- separately specified semantic usage counters.

This document does not define a byte serialization for the neutral result
record. Any future durable or transport result envelope requires its own
canonical format and domain separation.

## 11. Decoder and encoder failure boundary

An input codec rejection occurs before guest execution and publishes no input
root. The sandbox host maps it to the profile's pre-execution
`REQUEST_REJECTED / INPUT_CODEC_INVALID` boundary.

An output candidate that contains an invalid handle, cycle, impossible node
shape, invalid UTF-8 payload, duplicate MAP key, or expanded graph beyond the
effective limits is not a domain-schema mismatch. It fails the neutral
structural result boundary. The exact profile/result contract determines
whether a guest-reachable invalid candidate is a guest trap or resource
exhaustion and whether an impossible verified-runtime invariant is a host
failure.

A valid canonical value that fails a Stage 2 declaration schema remains a
valid codec value. The trusted host reports that later validation failure
without relabeling the bytes as malformed and without publishing a
domain-level success.

No native exception, address, partially initialized node, partial digest,
partial output span, or allocator-owned buffer may escape any codec failure.

## 12. Required adversarial qualification

Qualification MUST include deterministic cases for at least the following.

### Header and extent

- every truncation point in a scalar and nested aggregate;
- an empty supplied span;
- unknown tags;
- nonzero flags or reserved fields;
- leading, trailing, concatenated, and padding bytes;
- payload lengths smaller or larger than the actual payload;
- item counts inconsistent with payload contents;
- `u32` and `u64` values near their numeric maxima;
- checked sum, product, padding, depth, and subspan overflow; and
- lengths outside the implementation's admitted signed-length domain.

### Scalars, blobs, and UTF-8

- every noncanonical BOOL bit pattern;
- I64 minimum, maximum, zero, and negative-one bit patterns;
- empty and exact-limit BYTES and UTF8 payloads;
- blob length at the effective bound and bound plus one;
- every legal UTF-8 boundary form listed in this document;
- stray continuation, truncation, overlong, surrogate, and above-maximum
  UTF-8 sequences;
- embedded NUL and BOM bytes remaining ordinary UTF-8 content; and
- canonically equivalent but byte-distinct Unicode strings remaining
  byte-distinct codec values.

### LIST and MAP

- empty aggregates;
- exact-count and maximum-plus-one aggregates;
- a child ending exactly at and one byte beyond its parent payload;
- too few or too many children for the advertised count;
- a MAP key with every non-UTF8 tag;
- unsigned-byte ordering across `0x7f` and `0x80`;
- the shorter-prefix-first key rule;
- adjacent and nonadjacent duplicate raw key bytes;
- ascending, descending, and otherwise unsorted input keys;
- deterministic trusted-host pre-sorting independent of native insertion or
  hash iteration order, followed by rejection of any unordered codec input;
  and
- byte-distinct normalized and decomposed Unicode keys sorting only by their
  raw bytes.

### Graphs, handles, and accounting

- repeated output handles expanding once per occurrence;
- identical input subtrees receiving distinct consecutive handles;
- exact preorder input-handle assignment for nested LIST and MAP values;
- a forged, zero, wrong-arena, stale, or out-of-range output handle;
- defensive cycle detection;
- root depth one, exact depth limit, and depth limit plus one;
- expanded node count at the exact limit and limit plus one;
- wire-byte, expanded-value-byte, and arena-own-byte calculations for every
  type;
- eight-byte padding boundaries at lengths 0, 1, 7, 8, and 9;
- a small shared DAG whose expanded tree exceeds a limit; and
- unreachable published output nodes continuing to consume both cumulative
  output-arena counters.

### Digests, publication, and isolation

- fixed digest vectors for empty and nested input and output values;
- input and output domains producing different digests for identical root
  bytes;
- every one-bit mutation changing the hashed canonical content;
- canonical decode/re-encode reproducing identical bytes;
- malformed input publishing no root handle or partial arena;
- output failure publishing no partial canonical span or semantic success;
- successful result transfer leaving one disjoint result-owned buffer only
  after invocation state is scrubbed successfully;
- cleanup failure suppressing and disposing the private result or quarantining
  any buffer whose scrub cannot be proved;
- result release invalidating and scrubbing that buffer exactly once;
- allocation failure at every decoder, sorter, encoder, and digest stage;
- repeated failure followed by successful encoding with no stale state; and
- two simultaneous codec operations sharing no mutable cursor, handle
  counter, scratch table, digest state, or output buffer.

Bounded mutation fuzzing SHOULD cover nested count/length interactions, UTF-8
boundaries, MAP ordering, and checked arithmetic. It must obey the repository's
checked-in resource ceilings and must not turn malformed input into unbounded
allocation, native recursion, or superlinear work without an explicit bounded
work limit.
