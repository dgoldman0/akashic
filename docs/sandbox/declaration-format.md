# Sandbox module declaration format

## Purpose and ownership

A sandbox module declaration is canonical, non-executable metadata owned above
the neutral sandbox compiler, verifier, and executor. It binds one stable
module revision to exact artifact, profile, entry, schema, and requested-budget
identities.

The declaration is not:

- executable bytecode or a verified plan;
- a package dependency graph or version-range request;
- a storage path, mutable catalog row, or “latest” selector;
- a publisher signature, certificate, trust decision, grant, or capability;
- a Practice binding; or
- an invocation, VM, Context, handler, import table, or authority.

Installation policy decides whether a valid declaration may become visible.
Practice policy may later bind an exact visible declaration. Invocation still
requires independent artifact/profile resolution and verification.

All multibyte integers are unsigned little-endian wire values. Implementations
on the production 64-bit target reject any wire `u64` whose required semantic
range is outside the positive signed-cell range.

## Identity digests

SHA3-256 produces every 32-byte digest. `akashic/sandbox/digest.f` defines the
only hashing seam used by this format. It owns no mutable scratch; callers
supply the exact source span, 32-byte destination, and complete aligned digest
workspace.

Raw hashing is:

```text
SHA3-256(exact_bytes)
```

Sandbox identity hashing is:

```text
SHA3-256(UTF8(domain) || 0x00 || exact_bytes)
```

The domains are:

| Object | Domain |
| --- | --- |
| execution profile | `akashic.sandbox.profile` |
| executable artifact | `akashic.sandbox.artifact` |
| canonical schema | `akashic.sandbox.schema` |
| module declaration | `akashic.sandbox.declaration` |
| canonical input value | `akashic.sandbox.value.input` |
| canonical output value | `akashic.sandbox.value.output` |

The declaration does not contain its own digest. Its owner records the result
of `SBOX-DECL-DIGEST` externally. This avoids a circular self-commitment.

A digest proves exact byte identity only. It does not prove validity,
verification, provenance, installation, trust, relevance, or permission.
All-zero RIDs and digests are reserved and invalid where an identity is
required.

## Closed bounds

| Quantity | Bound |
| --- | ---: |
| complete declaration | 1 MiB |
| exposed entries | 32 |
| profile identifier | 1–63 bytes |
| one entry name | 1–63 bytes |
| embedded schema section | 256 KiB |
| one canonical schema | 1–65,536 bytes |
| requested-ceiling records | at most `SBOX-BUDGET-LIMIT-FIELD-COUNT` |

These are format/admission bounds, not allocation requests or ambient grants.

## Canonical section order

The declaration is exactly:

```text
256-byte header
profile identifier bytes
zero padding through the next 8-byte boundary
requested-ceiling records
entry records
concatenated embedded schema bytes
```

There are no offsets in the header because section positions are derived
uniquely from the fixed sizes and counts. There may be no prefix, gap,
unreferenced byte, alternate padding, or appended byte. `total_bytes` must
equal the complete caller-supplied span.

## Header

The header is exactly 256 bytes.

| Offset | Size | Field | Canonical rule |
| ---: | ---: | --- | --- |
| 0 | 8 | magic | ASCII `SBXDECL1` |
| 8 | 2 | format | `1` |
| 10 | 2 | header bytes | `256` |
| 12 | 4 | flags | zero |
| 16 | 8 | total bytes | exact complete span |
| 24 | 4 | entry count | 1–32 |
| 28 | 2 | ceiling count | 0 through the shared budget field count |
| 30 | 2 | profile-ID bytes | 1–63 |
| 32 | 2 | provenance kind | `0` none, `1` package |
| 34 | 2 | reserved | zero |
| 36 | 4 | import count | zero for the pure profile |
| 40 | 8 | effects | zero for the pure profile |
| 48 | 8 | embedded-schema bytes | 0–262,144 |
| 56 | 32 | owner RID | present |
| 88 | 32 | module RID | present |
| 120 | 8 | module revision | positive; zero never means current |
| 128 | 32 | artifact digest | exact domain-separated artifact digest |
| 160 | 32 | profile digest | exact domain-separated profile digest |
| 192 | 32 | provenance RID | conditional, described below |
| 224 | 8 | provenance revision | conditional, described below |
| 232 | 24 | reserved | zero |

The owner RID names the semantic owner that controls revision assignment and
installation state. The module RID and positive revision form the stable
module-domain key. Neither may be inferred from an artifact digest: distinct
module revisions may intentionally use the same executable bytes.

Provenance is deliberately small:

- kind `0` requires an all-zero provenance RID and zero revision;
- kind `1` requires a present package RID and positive package revision.

It records where an installer says the declaration came from. It is not a
publisher identity, signature, trust root, or authority. Additional
publisher/PKI machinery requires its own design and is outside this format.

The profile identifier follows the header. It is nonempty, NUL-free canonical
UTF-8. Its exact bytes and the header’s exact profile digest are both part of
declaration identity. The identifier alone never selects a profile.

## Requested ceilings

Each requested-ceiling record is 16 bytes:

| Offset | Size | Field | Canonical rule |
| ---: | ---: | --- | --- |
| 0 | 2 | field ID | one public `SBOX-BUDGET-LIMIT-*` ID |
| 2 | 2 | reserved | zero |
| 4 | 4 | reserved | zero |
| 8 | 8 | requested value | positive and at most that field’s public hard maximum |

Records are strictly increasing by field ID, so duplicates and alternate
orders are invalid. An absent record means “this declaration adds no ceiling
for this field.” A zero record is invalid; zero never means unlimited.

This format does not define a second resource vocabulary. Field meaning and
hard maxima come from `akashic/sandbox/budget.f`.

At invocation the host materializes its trusted baseline and takes the minimum
of every applicable positive ceiling. A declaration can only tighten an
already bounded invocation.

## Entry records

Each entry record is exactly 192 bytes.

| Offset | Size | Field | Canonical rule |
| ---: | ---: | --- | --- |
| 0 | 2 | name bytes | 1–63 |
| 2 | 2 | machine signature ID | `1` for the pure value-handle ABI |
| 4 | 1 | input-schema storage | `1` embedded, `2` referenced |
| 5 | 1 | output-schema storage | `1` embedded, `2` referenced |
| 6 | 2 | flags | zero |
| 8 | 64 | inline name area | name then zero tail |
| 72 | 8 | input-schema bytes | 1–65,536 |
| 80 | 8 | input embedded offset | rule below |
| 88 | 32 | input schema digest | present |
| 120 | 8 | output-schema bytes | 1–65,536 |
| 128 | 8 | output embedded offset | rule below |
| 136 | 32 | output schema digest | present |
| 168 | 24 | reserved | zero |

Entry names use the same canonical machine-key grammar as executable artifact
entries:

```text
[a-z][a-z0-9._-]{0,62}
```

Records are strictly increasing by raw name bytes. This makes names unique and
permits exact lookup without case folding, Unicode normalization, aliases, or
locale policy. The host must also require the selected executable artifact
entry to have the same exact name and machine signature.

Signature ID `1` is the ratified pure-compute value-handle ABI: one input value
handle and one returned value handle. It is not a domain schema.

### Embedded schemas

Storage value `1` means the canonical schema bytes are in the final embedded
schema section. Embedded spans concatenate without padding in entry order,
input before output. The first embedded offset is zero; each later embedded
offset is exactly the end of the previous embedded span. The final end is
exactly `embedded_schema_bytes`.

The independent validator recomputes
`SBOX-DIGEST-SCHEMA` over every embedded span and compares all 32 bytes with
the record. Declaration validation treats the schema payload itself as an
opaque exact span; the separately ratified canonical schema codec must also
validate its structure before installation or invocation.

### Referenced schemas

Storage value `2` means the canonical bytes are an immutable external object
identified by the schema digest and exact advertised byte length. Its embedded
offset must be zero and it contributes no byte to the embedded section.

Structural declaration validation cannot make an absent external object
present. Before installation or invocation, the owner/host must resolve bytes
by the full digest, require the exact advertised length, independently validate
the canonical schema codec, recompute `SBOX-DIGEST-SCHEMA`, and compare all 32
bytes. It must not fall forward to another schema, path, package version, or
catalog head.

Embedded and referenced storage have identical semantic identity. The storage
choice changes declaration bytes and therefore declaration identity, but never
grants authority.

## Validation and access API

`SBOX-DECL-VALIDATE` has the stack contract:

```forth
( declaration declaration-u view digest-workspace -- status | throws )
```

The caller supplies an aligned `SBOX-DECL-VIEW-SIZE` view and aligned
`SBOX-DIGEST-WORKSPACE-SIZE` workspace. Source, view, and workspace must be
complete admitted nonoverlapping spans.

There is no owner-global serialization requirement. One validation call has
exclusive use of its passed view and digest workspace while the source remains
mapped and quiescent. Distinct calls with distinct views/workspaces may proceed
independently. After successful validation, accessors are read-only; concurrent
readers are valid only while neither the address-bound view nor its borrowed
source bytes can change.

Preflight rejection does not modify view or workspace. Once admitted, the
workspace is cleared. A returned validation failure clears the complete view;
a success publishes an address-bound validated view and leaves the digest
workspace clear. A native digest publication or mandatory cleanup fault may
throw; the incomplete view never receives its valid magic.

Validation includes:

- exact magic, format, header size, and complete-span length;
- all section bounds and canonical order;
- every reserved bit, byte, and profile-padding byte equal to zero;
- present owner/module RIDs and positive module revision;
- present artifact and profile digests;
- consistent bounded provenance;
- nonempty NUL-free canonical UTF-8 profile identity;
- empty imports and zero effects;
- sorted unique shared budget fields with positive in-range values;
- sorted unique entry names, exact grammar, zero inline-name tail;
- exact signature ID and closed storage modes;
- positive bounded schema sizes and present schema digests;
- zero offsets for references;
- contiguous, complete embedded-schema coverage; and
- full digest checks for every embedded schema.

The view is borrowed metadata, not an owning copy. Accessors reject an invalid
or byte-copied view and return explicit status:

- `SBOX-DECL-SOURCE@`
- `SBOX-DECL-OWNER-RID@`
- `SBOX-DECL-MODULE-RID@`
- `SBOX-DECL-MODULE-REVISION@`
- `SBOX-DECL-ARTIFACT-DIGEST@`
- `SBOX-DECL-PROFILE-ID@`
- `SBOX-DECL-PROFILE-DIGEST@`
- `SBOX-DECL-PROVENANCE@`
- `SBOX-DECL-CEILING-COUNT@`
- `SBOX-DECL-CEILING@`
- `SBOX-DECL-ENTRY-COUNT@`
- `SBOX-DECL-ENTRY@`
- `SBOX-DECL-ENTRY-NAME@`
- `SBOX-DECL-ENTRY-SIGNATURE@`
- `SBOX-DECL-ENTRY-INPUT-SCHEMA@`
- `SBOX-DECL-ENTRY-OUTPUT-SCHEMA@`

Schema accessors return the embedded byte address or zero for a reference,
the exact schema length, digest address, storage mode, and status.

`SBOX-DECL-ENTRY-FIND-EXACT` accepts only the canonical machine-key grammar and
does an exact raw-byte lookup. Missing entries return
`SBOX-DECL-S-NOT-FOUND`; there is no default entry.

`SBOX-DECL-DIGEST` computes the external declaration identity over the exact
complete bytes. Validation and digest publication are intentionally separate:
a caller may validate hostile bytes without treating them as installed or
trusted, and a digest alone never substitutes for validation.

## Required malformed-input contracts

Focused qualification must cover at least:

- null, wrapping, protected, aliased, undersized, and oversized spans;
- every truncation and an appended byte after an otherwise valid declaration;
- wrong total length, magic, format, or fixed extent;
- every nonzero reserved or padding byte;
- zero owner/module identity, zero revision, and zero required digest;
- inconsistent or unknown provenance;
- empty, overlong, invalid, or NUL-containing profile UTF-8;
- nonzero imports or effects;
- unknown, duplicate, unsorted, zero, or above-hard-max ceiling records;
- zero entries, excessive entries, invalid/duplicate/unsorted entry names;
- a non-`1` signature or unknown storage mode;
- zero or excessive schema size and zero schema digest;
- referenced schemas with nonzero offsets;
- embedded overlap, gap, reordering, unreferenced tail, or overrun;
- one-bit embedded-schema changes without a matching digest; and
- copied or corrupted validated views.

No failure may select a newer declaration, artifact, profile, entry, schema,
package, or Practice state.
