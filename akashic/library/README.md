# Library domain package

Status: Gate 4A pure model and deterministic record codecs and the first Gate
4B pure storage-format layer are implemented and qualified. The package still
has no qualified VFS publication/recovery owner, index, domain owner,
projection, applet, UI, or Streams integration.

The current modules are:

- `model.f`: bounded caller-owned Library records, canonical validators,
  initial-request seals, retry comparisons, and pure catalog/collection
  cross-record transition checks.
- `record-codec.f`: deterministic V1 envelopes for catalog entries,
  collections, and immutable content revisions.
- `store-format.f`: deterministic V1 arena, catalog-bank, and head formats plus
  the ordered content-frame commitment used by the future VFS owner.

These modules perform no I/O, choose no path, publish no resource, and import no
sibling domain or applet.

## Sealed Gate 4A bounds

The initial catalog holds at most 128 entries and 32 collections. A collection
uses a canonical 128-bit membership bitmap. Entries admit at most 16 tags and
four typed lineage locators. Managed documents retain at most four content
revisions; content is valid UTF-8 bounded to 65,536 bytes.

The persisted widths are fixed for V1:

| Shape | Bytes |
| --- | ---: |
| VFS locator | 320 |
| origin union | 328 |
| lineage slot | 328 |
| immutable receipt | 328 |
| catalog entry payload | 2,832 |
| catalog record | 3,072 |
| collection payload | 224 |
| collection record | 320 |
| transient content view | 128 |
| content header | 160 |
| largest content record | 65,696 |

A full set of fixed catalog and collection records occupies at most 403,456
bytes before store framing. Titles are bounded to 128 bytes, tag text to 24,
collection titles to 64, and VFS snapshot paths to 255.

## Canonical model rules

All unused fixed-capacity bytes must be zero. Tags and direct qualified lineage
locators are strict bytewise sorted sets, so duplicates and alternate orderings
are rejected. Catalog and collection identities and operation keys are unique
and globally disjoint. Collection membership may name only allocated catalog
slots.

Revision-one entries are active initial requests. Their domain-separated
request seal covers the caller's request payload, including the expected
catalog generation; the operation key is compared separately. The seal excludes
owner-generated identity, operation counters, and clocks. Later archive,
content, metadata, and tombstone revisions preserve
the byte-exact immutable receipt. A tombstone erases content, metadata, origin,
lineage, and non-deletion clocks while permanently retaining identity and the
receipt.

The pure transition validators freeze identity, kind, media, initial request
facts, and tombstones; prevent content rollback and same-revision digest
substitution; and require both the domain revision and mutation sequence to
advance whenever a persisted entry or collection changes.

## Codec and lifetime rules

Fixed records have a 64-byte envelope and canonical zero padding. Content
records have a 160-byte header, an exact eight-byte-aligned record length, and
zero padding. Decoders validate magic, header CRC, format, lengths, flags,
payload CRC, canonical padding, and the model. Content additionally validates
SHA3-256 identity and UTF-8. A checksummed future format is reported as
unsupported rather than malformed.

`LIB-CONTENT-RECORD-DECODE` returns `LIBCT.DATA-A` as a borrowed pointer into
the caller's encoded record buffer. The view is valid only while that buffer is
alive and unchanged. `LIB-CONTENT-RECORD-MEASURE` safely derives the required
record size from a complete V1 header; it does not prove payload integrity.
Source, payload, and destination aliases are rejected before modifying the
aliased bytes.

## Sealed Gate 4B pure store ABI

The content arena is 655,360 bytes: one 512-byte immutable header followed by
654,848 bytes of sector-framed content. Each frame is the exact aligned content
record padded to a 512-byte boundary and is at most 66,048 bytes. Its immutable
arena identity, exact committed tail, record count, and ordered chain prevent
an owner from treating uncommitted suffix bytes as published content.

Each complete catalog bank is 403,968 bytes: one 512-byte header followed by
the complete 403,456-byte fixed catalog/collection body. The body holds all 128
catalog slots followed by all 32 collection slots. Its header seals generation,
counts, mutation sequence, arena identity and committed content facts, body
CRC32, and body SHA3-256. A 448-byte VFS fixed-snapshot payload seals the chosen
bank, complete-bank SHA3-256, the same catalog/content facts, and all format
geometry. The payload generation and selected bank generation must equal the
outer snapshot generation.

Arena, bank, and head headers have canonical zero tails. They verify CRC before
format dispatch, so intact future evidence is reported as unsupported while a
damaged future header remains a checksum failure. Caller-owned decoded facts
are written only after full validation, aliases with codec-private state are
rejected, and head-to-bank/head-to-arena comparisons require every duplicated
generation, catalog, mutation, arena, tail, count, and chain fact to agree.

The content commitment starts at
`SHA3-256("org.akashic.library.content-chain.genesis.v1")`. Each step commits the
prior chain, absolute arena offset, sector span, and SHA3-256 of the complete
padded frame under the separate
`org.akashic.library.content-chain.step.v1` domain. Absolute offsets and spans
are bounded, sector aligned, and encoded as native little-endian 64-bit cells.

There is no earlier Library store or Library on-disk state to migrate. These V1
shapes are new and intentionally do not decode or wrap the old taxonomy/vault
prototypes, Streams draft bytes, or another owner's files. No existing durable
format or path changes in this landing; future Library formats remain explicit
unsupported evidence until a separately qualified migration exists.

## Deliberate VFS-owner boundary

The remaining Gate 4B VFS owner must choose private paths, generation/commit
order, recovery, and content publication. It also owns the cross-record
catalog-to-content check:
the catalog's current revision must resolve to its current content facts, while
older content is valid only inside the bounded retained window. This cannot be
decided by the isolated record codec because the same entry legitimately has
both a current and retained historical record.

Ordinary VFS imports must be owner-qualified against
`SHA3-256("org.akashic.library.vfs-snapshot.v1")`. The pure model deliberately
admits another present contract digest for an explicitly reviewed migration;
the future import owner decides whether that exception is authorized.

No current code should infer a VFS path, generation scheme, retry lookup order,
index policy, capability, projection owner, or UI route from these records.
For the broader product boundary and gate handoff, see
[`../../docs/library/library.md`](../../docs/library/library.md).
