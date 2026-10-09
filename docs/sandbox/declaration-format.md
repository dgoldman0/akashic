# Sandbox module declarations

`akashic/runtime/sandbox-declaration.f` reads and writes module declarations.
A declaration binds one revision of a named module to:

- its artifact digest and profile digest;
- its entries, each with a name, a machine signature, and input and output
  schemas;
- the limits it asks for;
- where it came from.

A declaration is metadata, not authority. It runs nothing and grants nothing,
and its limits can only narrow what a host allows (`profile-and-abi.md`
section 10.1).

The declaration's identity is
`SHA3-256("akashic.sandbox.declaration" || 0x00 || bytes)`. That digest is
kept outside the declaration, so a declaration never contains its own digest.

## Layout

All integers are little-endian. The format has no addresses and needs no
alignment. A declaration is a header, then the limit records, then the entry
records, then the schema section, with nothing between or after them.

### Header (256 bytes)

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 8 | magic | `AKSBXDCL` |
| 8 | 2 | format | 1 |
| 10 | 2 | header size | 256 |
| 12 | 4 | flags | zero |
| 16 | 8 | total bytes | the whole declaration |
| 24 | 4 | entry count | 1 through 4,096 |
| 28 | 2 | limit count | 0 through 18 |
| 30 | 2 | provenance kind | 0 none, 1 package |
| 32 | 8 | schema bytes | the schema section's length |
| 40 | 8 | module revision | positive |
| 48 | 32 | module RID | the digest of the name |
| 80 | 32 | artifact digest | not all zero |
| 112 | 32 | profile digest | not all zero |
| 144 | 32 | provenance RID | see below |
| 176 | 8 | provenance revision | see below |
| 184 | 2 | name length | 1 through 63 |
| 186 | 6 | zero | |
| 192 | 64 | module name | then zero bytes to the end |

The total is exactly `256 + 16 × limits + 168 × entries + schema bytes`, and at
most 16 MiB, the same ceiling as an artifact.

A module name is spelled as an entry name is, `[a-z][a-z0-9._-]{0,62}`, so
dots can namespace it. The module RID is
`SHA3-256("akashic.sandbox.module" || 0x00 || name)`. One name therefore
always means one module, and a host can find a module from its name alone.

Provenance records what the installer says the module came from. It is not a
trust claim. With kind 0 the RID and revision are zero. With kind 1 they name
the package and its positive revision.

The profile digest identifies the exact profile descriptor, and so its
identifier too, which is not repeated. Format 1 declares no imports and no
effects; a later format adds them.

### Limit records (16 bytes each)

| Offset | Size | Field |
|---:|---:|---|
| 0 | 2 | limit field |
| 2 | 6 | zero |
| 8 | 8 | value |

Fields strictly increase. A value is positive and below the unbounded
marker, 2^63 − 1; an unlisted field is simply not limited by the declaration.
The field numbers are fixed, and a new field is only ever appended:

| Field | Limit | Field | Limit |
|---:|---|---:|---|
| 0 | `SBOX-LIMIT-INSTRUCTION-BUDGET` | 9 | `SBOX-LIMIT-INPUT-BYTES` |
| 1 | `SBOX-LIMIT-VALUE-OP-BUDGET` | 10 | `SBOX-LIMIT-OUTPUT-ARENA-NODES` |
| 2 | `SBOX-LIMIT-COPY-BUDGET` | 11 | `SBOX-LIMIT-OUTPUT-ARENA-BYTES` |
| 3 | `SBOX-LIMIT-WALL-MS` | 12 | `SBOX-LIMIT-OUTPUT-RESULT-NODES` |
| 4 | `SBOX-LIMIT-DEPTH` | 13 | `SBOX-LIMIT-OUTPUT-RESULT-BYTES` |
| 5 | `SBOX-LIMIT-BLOB-BYTES` | 14 | `SBOX-LIMIT-DATA-STACK` |
| 6 | `SBOX-LIMIT-LIST-COUNT` | 15 | `SBOX-LIMIT-CALL-FRAMES` |
| 7 | `SBOX-LIMIT-MAP-COUNT` | 16 | `SBOX-LIMIT-LOOP-FRAMES` |
| 8 | `SBOX-LIMIT-INPUT-NODES` | 17 | `SBOX-LIMIT-MEMORY-BYTES` |

### Entry records (168 bytes each)

| Offset | Size | Field |
|---:|---:|---|
| 0 | 2 | name length, 1 through 63 |
| 2 | 2 | zero |
| 4 | 4 | machine signature, positive |
| 8 | 64 | name, then zero bytes to the end |
| 72 | 48 | input schema slot |
| 120 | 48 | output schema slot |

A name is a canonical entry name, `[a-z][a-z0-9._-]{0,62}`, as in the artifact.
Entries strictly increase by their raw name bytes.

A schema slot is an 8-byte offset into the schema section, an 8-byte length,
and the 32-byte schema digest,
`SHA3-256("akashic.sandbox.schema" || 0x00 || bytes)`.

### Schema section

The schemas follow one another with no gaps, in entry order, each entry's
input before its output. The first starts at offset 0 and the last ends at the
section's end. Every schema is nonempty and matches its digest.

Each schema is in canonical schema bytes (`../interop/schema-bytes.md`). This
library treats them as opaque bytes bound by their digests. The interop layer
checks that they are sandbox schemas before it installs or invokes a module.

## Words

Every word works in caller memory and keeps no state of its own.

Writing:

- `SBOX-DECL-MEASURE ( entry-n limit-n schema-u -- declaration-u status )`
  gives the size for those counts.
- `SBOX-DECL-START ( revision artifact-digest profile-digest entry-n limit-n
  schema-u declaration declaration-u -- status )` clears a buffer of exactly
  that size and writes the header.
- `SBOX-DECL-MODULE! ( name name-u workspace declaration -- status )` writes
  the module name and the RID it fixes.
- `SBOX-DECL-PROVENANCE! ( kind rid revision declaration -- status )` sets
  the provenance. Kind 0 takes RID 0 and revision 0.
- `SBOX-DECL-LIMIT! ( index field value declaration -- status )` writes one
  limit.
- `SBOX-DECL-ENTRY! ( index name name-u signature declaration -- status )`
  writes one entry's name and signature.
- `SBOX-DECL-SCHEMAS! ( index input input-u output output-u workspace
  declaration -- status )` copies one entry's schemas after the previous
  entry's and computes their digests. Entries are written in order.

Checking:

- `SBOX-DECL-VALIDATE ( declaration declaration-u workspace -- status )`
  accepts only a complete canonical declaration. It recomputes every schema
  digest.
- `SBOX-DECL-DIGEST ( declaration declaration-u digest workspace -- status )`
  validates, then writes the declaration's digest.

Reading a declaration that validation accepted:

- `SBOX-DECL-MODULE@ ( declaration -- rid revision )`,
  `SBOX-DECL-MODULE-NAME$`, `SBOX-DECL-ARTIFACT-DIGEST@`,
  `SBOX-DECL-PROFILE-DIGEST@` and `SBOX-DECL-PROVENANCE@`;
- `SBOX-DECL-ENTRY-N@`, `SBOX-DECL-ENTRY-NAME$`,
  `SBOX-DECL-ENTRY-SIGNATURE@`, `SBOX-DECL-ENTRY-INPUT$` and
  `SBOX-DECL-ENTRY-OUTPUT$ ( index declaration -- schema schema-u digest )`;
- `SBOX-DECL-ENTRY-FIND ( name name-u declaration -- index|-1 )`, a binary
  search;
- `SBOX-DECL-LIMIT-N@` and `SBOX-DECL-LIMIT@ ( index declaration -- field
  value )`;
- `SBOX-DECL-LIMITS ( declaration limits -- status )` fills a sealed limit
  record with the requested limits, leaving the other fields unbounded, so the
  host can meet it with its own.

`SBOX-DECL-MODULE-RID ( name name-u rid workspace -- status )` gives the RID
of a module name without a declaration.

The workspace is `SBOX-DECL-WORKSPACE-SIZE` bytes, cell-aligned, and apart from
the declaration, the schemas and the digest.

The statuses are `SBOX-DECL-S-OK`, `-INVALID` for a noncanonical declaration
or bad argument, `-CAPACITY` for a size over a ceiling or a buffer too small,
`-ALIAS` for overlapping spans, `-STATE` for writing out of order, `-DIGEST`
for a schema that does not match its digest, and `-FAULT` for a failed digest
computation. `SBOX-DECL-LIMITS` returns an `SBOX-LIMITS-` status.

## What the host checks

A valid declaration is only well formed. Before it installs or invokes a
module, the host also checks that:

- every schema is a sandbox schema;
- the artifact has the declared digest and names the declared profile digest,
  which is the profile the host loaded;
- the artifact's entries are exactly the declared ones, in the same order and
  with the same signatures.

The interop layer checks the schemas. The module owner
(`runtime/sandbox-module-owner.f`) checks the rest when it adds a module the
host has just built or verifies one loaded from storage.

## Tests

`local_testing/test_sandbox_declaration.py` holds a Python reference. The
emulator must write the reference's bytes from the same parts, digest them as
`hashlib` does, read every field back, refuse each writer misuse, and refuse
every noncanonical variant with the reference's status.
