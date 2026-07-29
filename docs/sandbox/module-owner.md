# In-memory sandbox module owner

`sandbox-module-owner.f` is the bounded Stage 2 ownership boundary between
validated module data and the neutral sandbox runtime. It owns exact profile
identities, canonical schemas, verified-plan cache entries, installed module
bytes, and explicit entry leases. It never invokes an entry.

This is one general multi-module path. It is not a one-module facade and it
does not introduce a second evaluator, verifier, or VM. Distinct owner RIDs,
module RIDs, revisions, and entries coexist in one configured owner. Modules
may share an entry name. Different module revisions may share one cached plan
when and only when their complete artifact and profile digests are identical.

The linked-loader identity is `akashic-rt-sbx-owner`. It is 20 bytes and is
unique within KDOS's 23-byte `PROVIDED` comparison width.

## Boundary

The owner is activation-local memory, not durable truth. It contains no VFS,
path, catalog, persistence, Practice, Context, Desk, Agent, capability,
credential, host import, native callback, execution token, or authority. It
does not choose a current revision and it has no `latest`, default, alias, or
fallback lookup.

A future durable adapter may load exact bytes into this owner. A future
revocation adapter may stop publication, drain leases, and destroy or replace
an owner. Those adapters must not weaken the exact in-memory keys and are not
implemented here.

All mutable lifecycle operations are serialized by a spin guard embedded in
the particular owner. There is no module-global operation scratch or
process-wide owner lock. The 640-byte owner descriptor is caller-owned and
self-bound; its backing tables and immutable payloads are owner allocations.
A successful release frees every owned allocation and clears the descriptor.
The caller must unpublish the owner before release so a new call cannot race
descriptor destruction.

## Configured bounds

`SBOX-MOWNER-INIT` takes independent module, profile, schema, and plan
capacities plus a maximum canonical-schema depth:

```text
( module-cap profile-cap schema-cap plan-cap schema-depth owner -- status )
```

The backing table size is available from
`SBOX-MOWNER-BACKING-MEASURE`. Configured counts are exact, and every admitted
payload also remains under its canonical format bound. Defensive hard maxima
bound validation walks even if configuration memory is corrupted:

| Resource | Maximum configured count |
| --- | ---: |
| installed modules | 64 |
| profile identities | 16 |
| canonical schemas | 256 |
| verified plans | 64 |
| schema depth | 256 |

Profile descriptor bytes are bounded to 262,144. Declarations, artifacts, and
individual schemas retain the smaller or equal bounds published by their
own codecs. Allocation failure publishes no partial registry row, plan row,
or module row.

## Profile registry

Registration is:

```text
SBOX-MOWNER-PROFILE-REGISTER
( profile-id profile-id-u descriptor descriptor-u
  expected-profile-digest sealed-profile owner -- status )
```

The trusted bootstrap supplies exact canonical descriptor bytes and a sealed
runtime profile already admitted by the profile loader or a ratified local
bootstrap. The owner:

1. validates the identifier and source spans;
2. recomputes the complete domain-separated profile digest;
3. compares all 32 digest bytes;
4. deep-copies the identifier and descriptor and recomputes the descriptor
   digest from the owned copy;
5. reconstructs a new self-bound sealed profile from the supplied profile's
   public tag, limits, and enabled opcodes;
6. publishes the row last.

The owner never borrows the caller's descriptor or runtime profile. A profile
digest can name only one identifier, descriptor byte string, and runtime
semantics in an owner; an incompatible repeated registration is a conflict.
Module installation resolves the declaration's complete `(profile ID,
profile digest)` pair. The plan cache uses the profile digest because the
registry has already enforced that one-to-one semantic binding.

Descriptor grammar and rule-table loading do not belong in this owner. In
particular, profile registration is a trusted host configuration operation,
not an operation exposed to sandbox code and not a substitute for canonical
profile loading.

## Schema registry

Registration is:

```text
SBOX-MOWNER-SCHEMA-REGISTER
( schema schema-u expected-schema-digest owner -- status )
```

The owner recomputes all 32 digest bytes, structurally validates the complete
canonical schema with its configured-depth workspace, allocates an exact
copy, validates and re-hashes that owned copy, and publishes it keyed by the
full schema digest. The same digest and same bytes register idempotently. The
same digest with different length or bytes is a conflict.

Embedded declaration schemas are also structurally validated during module
installation and their complete digests are recomputed. A referenced schema
must already exist under its full digest, its exact declared byte length must
match, and the owned canonical bytes are revalidated. No name or truncated
digest resolves a schema.

## Module installation and plan sharing

Installation is:

```text
SBOX-MOWNER-MODULE-INSTALL
( declaration declaration-u declaration-digest
  artifact artifact-u owner -- status )
```

Before it publishes anything, installation:

1. independently validates the complete declaration;
2. recomputes and compares the full declaration digest;
3. recomputes the full artifact digest and compares it with the declaration;
4. resolves the exact profile ID and full profile digest;
5. resolves and validates both schemas for every declaration entry;
6. obtains or builds a plan keyed exactly by
   `(artifact digest, profile digest)`;
7. compares every declaration entry name and signature with the same indexed
   verified artifact entry; and
8. deep-copies both declaration and artifact, revalidates the owned
   declaration, then publishes immutable rows.

The verifier remains the independent Stage 1 verifier. On a cache miss the
owner allocates an exact plan destination and calls `SBOX-VERIFY`; a failed
installation frees an unpublished tentative plan. On a cache hit it validates
the sealed plan and compares the caller's complete artifact bytes with the
plan's owned candidate bytes. Digest equality alone never permits different
bytes to share a cache row.

The cache owns one sealed plan. Installed module rows refer to that row and
retain their own declaration and artifact copies. A plan contains immutable
artifact bytes and a sealed profile reference, but no invocation stack,
memory, frames, budget, cancellation state, values, or outputs. Sharing a plan
therefore shares verification work without sharing invocation state.

An exact owner-RID/module-RID/revision tuple is immutable. Reinstalling the
same exact declaration and artifact is idempotent after full validation;
trying to bind that tuple to different bytes or digests is a conflict.

## Exact leases

Acquisition is:

```text
SBOX-MOWNER-ACQUIRE-EXACT
( owner-rid module-rid positive-revision declaration-digest
  entry-name entry-name-u lease owner -- status )
```

Every field participates. There is no owner-only, module-only, name-only,
current-revision, or default acquisition. The declaration digest must match
all 32 bytes and the entry name must match exact canonical bytes. Multiple
modules may expose the same entry name without ambiguity because their exact
module keys differ.

The 352-byte lease is caller-owned and self-bound. Acquisition constructs a
fresh validated view over the owner's pinned declaration, resolves the exact
entry and both schema spans, copies both schema digests into the lease, and
increments the module and owner reference counts. It does not invoke, allocate
an invocation, or materialize a budget.

Read-only accessors expose:

- `SBOX-MLEASE-DECLARATION@` and
  `SBOX-MLEASE-DECLARATION$`;
- `SBOX-MLEASE-PLAN@`;
- `SBOX-MLEASE-PROFILE@`;
- `SBOX-MLEASE-ENTRY-INDEX@` and
  `SBOX-MLEASE-ENTRY-NAME$`;
- `SBOX-MLEASE-INPUT-SCHEMA@`; and
- `SBOX-MLEASE-OUTPUT-SCHEMA@`.

The schema accessors return the exact pinned schema span and its complete
32-byte digest. Embedded spans point into the owned declaration; referenced
spans point into the owned schema registry.

`SBOX-MLEASE-RELEASE` is explicit and clears the entire lease after
decrementing its counts. `SBOX-MOWNER-RELEASE` refuses with `BUSY` while any
lease remains. There is no implicit lease expiry or revocation in this
in-memory layer.

## Execution cost

The owner does work at four cold boundaries:

- profile/schema registration;
- module installation and verification;
- exact entry acquisition; and
- lease/owner release.

It adds no VM opcode, no per-instruction branch, no invocation-state wrapper,
and no host dispatch. A plan cache hit avoids verification and performs
bounded exact comparisons. Lease accessors inspect pinned immutable state.
The executor consumes the returned plan/profile/entry/schema data through the
existing neutral runtime and creates a fresh invocation exactly as before.

The largest work—hashing, schema walking, artifact verification, and complete
entry cross-checking—occurs at registration or install time. Acquisition
performs bounded table lookup and declaration validation once for a lease.
None of it belongs in the instruction hot path.

## Diagnostics

Count and capacity inspection is available through:

- `SBOX-MOWNER-MODULE-COUNT@`;
- `SBOX-MOWNER-PROFILE-COUNT@`;
- `SBOX-MOWNER-SCHEMA-COUNT@`;
- `SBOX-MOWNER-PLAN-COUNT@`;
- `SBOX-MOWNER-ACTIVE-LEASES@`; and
- `SBOX-MOWNER-CAPACITIES@`.

`SBOX-MOWNER-LAST-VERIFIER@` retains the independent verifier's status,
detail, and error index from the most recent cache miss. These diagnostics do
not alter lookup or authorize fallback.
