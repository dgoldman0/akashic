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
