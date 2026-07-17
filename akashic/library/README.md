# Library domain package

Status: Gate 4A pure model and deterministic record codecs are implemented and
qualified. The package still has no store, VFS topology, index, owner,
projection, applet, UI, or Streams integration.

The current modules are:

- `model.f`: bounded caller-owned Library records, canonical validators,
  initial-request seals, retry comparisons, and pure catalog/collection
  cross-record transition checks.
- `record-codec.f`: deterministic V1 envelopes for catalog entries,
  collections, and immutable content revisions.

Neither module performs I/O, chooses a path, publishes a resource, or imports a
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

## Deliberate next-gate boundary

Gate 4B must choose store paths, generation/commit order, recovery, and content
publication. That store also owns the cross-record catalog-to-content check:
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
