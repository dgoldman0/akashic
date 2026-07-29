# Practice sandbox bindings

`sandbox-practice-binding.f` defines the inert data boundary between one
Practice and the exact pure sandbox entry points that the Practice names as
machine roles. A binding set is a canonical, pointer-free byte string. Its
identity is:

```text
SHA3-256(
    UTF-8("akashic.sandbox.practice-binding")
    || 0x00
    || exact binding-set bytes
)
```

That digest is the value stored in `PHEAD.BINDING-ROOT`. The zero value means
that the Practice has no sandbox bindings. A nonzero value identifies one
complete role map; there is no mutable per-role slot in `PHEAD`.

The loader key for the implementation file is `akashic-rt-sbx-pbind`. It is
20 bytes and intentionally unique within the loader's 23-byte `PROVIDED` key
comparison width.

## Boundary and inertness

A binding record names data. It grants nothing and invokes nothing. Durable
binding bytes contain no pointer, execution token, handler, callback, plan,
VM, Context, queue, lease, capability, grant, credential, resolver, VFS
object, storage path, native import, or selector such as `latest`.

Validation, role lookup, `PHEAD` matching, and declaration cross-checking are
pure inspection operations over caller-owned spans. Neither installing a
binding set nor matching it to a Practice or declaration can compile or run
guest code. The module exposes no dispatch operation. An authorized Practice
owner performs persistence and the `PHEAD` update outside this module; an
executor is a separate later consumer.

`SBOX-PBIND-MATCH-PHEAD` performs structural and byte-identity checks only.
It does not authenticate a `PHEAD`, authorize its owner, or publish a new
root; those remain responsibilities of the enclosing Practice activation
boundary.

The validated view contains transient source pointers for inspection. It is
address-bound, borrows an immutable source span, and is never durable data.
Copying the view invalidates it.

## Canonical format

All integers are unsigned little-endian fields. The source span must be
exact: omitted or appended bytes are invalid. Version 1 has a 128-byte header
followed by 1 through 64 fixed 544-byte records.

### Header

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | magic bytes `SBXPBIN1` |
| 8 | 2 | format, exactly `1` |
| 10 | 2 | header size, exactly `128` |
| 12 | 4 | flags, zero |
| 16 | 8 | exact total byte length |
| 24 | 4 | record count, 1 through 64 |
| 28 | 2 | budget-field count, exactly `21` |
| 30 | 2 | maximum name length, exactly `63` |
| 32 | 32 | nonzero Practice RID |
| 64 | 64 | zero-reserved |

The total length is exactly:

```text
128 + record-count * 544
```

### Role record

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 2 | role-name byte length |
| 2 | 2 | entry-name byte length |
| 4 | 2 | entry signature |
| 6 | 2 | budget-field count, exactly `21` |
| 8 | 4 | flags, zero |
| 12 | 4 | reserved, zero |
| 16 | 64 | inline, zero-tailed role name |
| 80 | 64 | inline, zero-tailed declaration entry name |
| 144 | 32 | nonzero owner RID |
| 176 | 32 | nonzero module RID |
| 208 | 8 | positive module revision |
| 216 | 32 | nonzero declaration digest |
| 248 | 32 | nonzero artifact digest |
| 280 | 32 | nonzero profile digest |
| 312 | 32 | nonzero input-schema digest |
| 344 | 32 | nonzero output-schema digest |
| 376 | 168 | 21 fixed-order `u64` Practice budget ceilings |

Version 1 accepts only
`SBOX-DECL-SIGNATURE-PURE-VALUE`. Role and entry names are ASCII:

```text
[a-z][a-z0-9._-]{0,62}
```

Every unused byte in each 64-byte name area is zero. Records are strictly
ascending by role name, which also makes roles unique. Several distinct roles
may intentionally bind the same exact declaration entry.

The declaration digest already commits the declaration's artifact, profile,
entries, schemas, and declaration ceilings. Their explicit identities in a
binding record are cross-checks: activation must not accept a declaration
whose resolved components differ from what the Practice named. They are not
additional authority or mutable lookup hints.

## Practice budget ceilings

Each record carries one value for every canonical
`SBOX-BUDGET-LIMIT-*` field, in field-ID order. Zero means that the Practice
does not add a ceiling for that field; it never means unlimited. A positive
value must not exceed that field's ratified hard maximum.

These values are Practice policy inputs. They do not replace the declaration,
trusted-host, Context, or request ceilings, and they are not a ready-to-run
budget object. Before execution, a higher layer materializes the baseline and
folds every applicable positive ceiling by minimum. Because the complete
binding set is hashed, changing any role budget changes
`PHEAD.BINDING-ROOT`.

## Activation sequence

A higher-layer activator performs these steps when a Practice revision or its
binding root changes:

1. If `PHEAD.BINDING-ROOT` is zero, activate no sandbox roles.
2. Load the binding-set bytes by the complete root digest, validate the exact
   bytes with `SBOX-PBIND-VALIDATE`, and verify that the computed digest and
   embedded Practice RID match the `PHEAD` with
   `SBOX-PBIND-MATCH-PHEAD`.
3. For a selected role, resolve the declaration by its exact declaration
   digest. Validate the declaration bytes independently and recompute their
   domain-separated declaration digest.
4. Pass the validated declaration view and recomputed digest to
   `SBOX-PBIND-RECORD-MATCH-DECLARATION`. This cross-checks owner, module,
   revision, artifact, profile, exact entry, signature, and both schema
   digests.
5. Resolve artifact, profile, and any referenced schemas only by their exact
   digests and validate each object independently.
6. Materialize and fold the effective budget.
7. Only after all checks succeed may a separate trusted host create an
   invocation.

There is no name-only fallback, current-revision lookup, best-effort schema
substitution, or automatic invocation. An activation cache may retain
validated, fully resolved host state for a specific `PHEAD` revision and
binding digest, but that cache is outside the durable format and must be
discarded when either identity changes.

## Public inspection API

The main words are:

- `SBOX-PBIND-DIGEST`
- `SBOX-PBIND-VALIDATE`
- `SBOX-PBIND-VIEW-VALID?`
- `SBOX-PBIND-SOURCE@`
- `SBOX-PBIND-PRACTICE-RID@`
- `SBOX-PBIND-DIGEST@`
- `SBOX-PBIND-RECORD-COUNT@`
- `SBOX-PBIND-RECORD@`
- `SBOX-PBIND-ROLE-FIND-EXACT`
- `SBOX-PBIND-RECORD-ROLE@`
- `SBOX-PBIND-RECORD-ENTRY@`
- the `SBOX-PBIND-RECORD-*-RID@` and
  `SBOX-PBIND-RECORD-*-DIGEST@` identity accessors
- `SBOX-PBIND-RECORD-MODULE-REVISION@`
- `SBOX-PBIND-RECORD-BUDGET@`
- `SBOX-PBIND-MATCH-PHEAD`
- `SBOX-PBIND-RECORD-MATCH-DECLARATION`

`SBOX-PBIND-DIGEST` is a mechanical identity operation and does not make
malformed bytes valid. `SBOX-PBIND-VALIDATE` performs canonical validation
and publishes the same digest into its validated view.

Validation hashes the small binding set once. Ordinary accessors do not hash,
allocate, resolve, compile, or execute. Role lookup is bounded by 64 records.
These operations belong at activation or configuration-change time, not in
the neutral VM's per-instruction path, so the binding design adds no
instruction-dispatch cost.
