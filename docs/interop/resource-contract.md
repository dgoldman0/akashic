# Portable common-resource contracts

`akashic/interop/resource-contract.f` publishes closed, bounded schemas and
validators for portable describe, exact snapshot, and optional replace
capabilities. These maps carry domain state. The request envelope and LBIND
continue to carry the independent live component-revision guard.

`resource.describe` accepts null and returns exactly:

`resource`, `domain_revision`, `kind`, `title`, `media_type`, `mutable`,
`size`, and `owner`.

The resource is a semantic RREF with revision zero. A positive
`domain_revision` is an owner claim about current or retained domain history;
zero explicitly means identity-only/unqualified. It is never copied from
`CINST.REVISION` merely because the numbers happen to match.

`resource.snapshot` accepts exactly `domain_revision`, `digest_kind`,
`state_digest`, and `projection`, all copied from an exact QLOC. Its result
echoes those four fields plus `resource`, `media_type`, `content`, `size`, and
`content_digest`. Validation always hashes the returned bytes and requires the
separate projection-content digest to match. For a projection-content QLOC,
that digest must also equal the locator's `state_digest`; for a semantic-state
QLOC, the two digests remain intentionally distinct.

`resource.replace` accepts the exact old evidence as
`expected_domain_revision`, `expected_digest_kind`,
`expected_state_digest`, and `projection`, plus bounded `content` and its
SHA3-256 `content_digest`. Its result contains `resource`, a strictly newer
`domain_revision`, typed new state digest/projection, and `content_digest`.
The result digest kind must equal the old locator's kind, and the returned
content digest must equal the caller's submitted digest. For
projection-content, new state and content digests must be equal. Replace is
optional; absence means read-only portable interoperation.

All maps reject missing or additional fields. Text and content are bounded,
digests are exactly 32 bytes where required, RREF revision is zero, and
projection-content results are verified rather than trusted by shape alone.
The builders never grant authority; they only construct typed operands.
`RCON-REPLACE-RESULT?` takes the old locator, submitted content digest, and
returned map; shape alone cannot authenticate a replacement.

## Construction and owner-side API

The module's builders return `RCON-S-OK`, `RCON-S-INVALID`, `RCON-S-TYPE`,
`RCON-S-NOMEM`, or `RCON-S-MISMATCH`. `INVALID` identifies an invalid caller
record, pointer, bound, or locator. `TYPE` identifies a malformed typed value
or a result that cannot satisfy its closed schema. `MISMATCH` identifies
well-formed but contradictory domain evidence, including an incorrect content
digest. Allocation failure is always `NOMEM`.

The existing client-side words remain the compact current API:

```forth
RCON-SNAPSHOT-ARGS!  ( locator value -- status )
RCON-REPLACE-ARGS!   ( locator content-a content-u digest value -- status )
```

They now stage their maps through a transactional value builder. The
destination is not changed until the complete map passes its schema, and a
failed candidate is recursively released. The transient construction
workspace is an implementation detail of these convenience words.

Owners decode request arguments into caller-owned operands:

```forth
RCON-SNAPSHOT-ARGS@  ( value owner-a owner-u reference operands -- status )
RCON-REPLACE-ARGS@   ( value owner-a owner-u reference operands -- status )
```

Allocate `RCON-SNAPSHOT-OPERANDS-SIZE` or
`RCON-REPLACE-OPERANDS-SIZE` bytes and initialize it with the corresponding
`RCON-*-OPERANDS-INIT` word. `RCONSO.LOCATOR` and `RCONRO.LOCATOR` expose the
owned reconstructed exact QLOC. Replace additionally exposes borrowed
`RCONRO-CONTENT$` and the copied, verified `RCONRO.CONTENT-DIGEST`.
`RCON-REPLACE-ARGS@` hashes the content before returning. No private decode
pointer survives either public return; failure reinitializes the complete
operand to its empty invalid state, while success scrubs its private workspace
tail. The borrowed content is valid only while the request argument value
remains alive and unchanged.

Canonical results use small pointer-bearing views:

```forth
RCON-DESCRIBE-RESULT!  ( describe-view result result-workspace -- status )
RCON-SNAPSHOT-RESULT!  ( snapshot-view result result-workspace -- status )
RCON-REPLACE-RESULT!   ( replace-view result result-workspace -- status )
```

The record sizes and initializers are `RCON-DESCRIBE-VIEW-SIZE` /
`RCON-DESCRIBE-VIEW-INIT`, `RCON-SNAPSHOT-VIEW-SIZE` /
`RCON-SNAPSHOT-VIEW-INIT`, and `RCON-REPLACE-VIEW-SIZE` /
`RCON-REPLACE-VIEW-INIT`.

A describe view supplies a revision-zero semantic RREF and the fields exposed
by `RCONDV.*`: domain revision, kind, title, media type, mutability, size, and
owner. A snapshot view supplies an exact locator, media/content spans, and the
expected content digest through `RCONSV.*`. The constructor hashes the content
itself. A replace view supplies old and new exact locators plus the verified
content digest through `RCONRV.*`; it requires the same owner, RID, digest
kind, and projection and a strictly newer domain revision. Projection-content
results also require new state digest and content digest equality.

Each concurrently usable handler path owns one
`RCON-RESULT-WORKSPACE-SIZE` record and initializes it once with
`RCON-RESULT-WORKSPACE-INIT`. The workspace exists because a result must hold
an unpublished owned CV tree, hash scratch, and call-local pointers until all
allocations and semantic checks succeed. It must not be shared by overlapping
calls. Publication transfers the complete tree into the request result without
another allocation; every error aborts and recursively frees the candidate.
This lets a replace handler construct its entire response before starting a
durable commit, with no fallible result allocation afterward.

Canonical capability descriptors use:

```forth
RCON-DESCRIBE-CAP!  ( cap-config cap cap-workspace -- status )
RCON-SNAPSHOT-CAP!  ( cap-config cap cap-workspace -- status )
RCON-REPLACE-CAP!   ( cap-config cap cap-workspace -- status )
```

Initialize `RCON-CAP-CONFIG-SIZE` with
`RCON-CAP-CONFIG-INIT ( handler-xt flags config -- status )`. Optional title and
description spans use `RCONCC.TITLE-A/U` and `RCONCC.DESC-A/U`. Initialize one
`RCON-CAP-WORKSPACE-SIZE` record with `RCON-CAP-WORKSPACE-INIT`; it contains
the unpublished CAPB candidate and detects overlapping use. The constructors
fix capability IDs, kinds, effects, schemas, zero timing, owner-commit
concurrency, and null preview/undo callbacks. The caller retains control only
of metadata, handler, and valid flags, including whether
`CAP-F-CONTEXT-DEFAULT` applies.

These helpers deliberately contain no resource registry, acquisition,
component revision, lifecycle, storage, locking, qualification, media policy,
or error-message policy. The request bus and owner continue to enforce those
contracts. A capability descriptor or successfully decoded map conveys no
authority by itself.
