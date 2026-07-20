# Refactor Landing L2 checked spans and bounded output

Landing L2 generalizes two small, repeated mechanisms without changing an
applet's product behavior: bounded collections of borrowed memory geometry and
all-or-nothing output into caller storage. Both APIs are independent Akashic
utilities with explicit state ownership and multiple real consumers.

## Neutral APIs

`utils/memory-span.f` now includes inline span sets sized by
`MSPAN-SET-BYTES`. The caller owns the complete set allocation. `PUSH` records
valid borrowed geometry whose members may overlap; `ADD` additionally enforces
pairwise disjointness. Zero-length entries consume capacity but never overlap,
exact adjacency remains disjoint, invalid or wrapping geometry is rejected,
and every failed mutation leaves the set unchanged.

`utils/buffer-writer.f` adds a caller-owned `CBW-SIZE` descriptor over a caller
buffer. Append, character, and signed-decimal operations reserve the complete
write before changing bytes. The first invalid-input or capacity error is
sticky until reset. Target/source overlap is supported with `MOVE`, and
independent descriptors have independent length and error state.

Neither utility imports TUI or an applet, allocates storage, embeds product
policy, or owns process-global mutable state.

## Proving consumers and deleted duplicates

The span-set consumers are:

- VFS fixed snapshots embed a 16-entry disjoint set in each caller-owned
  specification. This replaces the private count, manual entry addressing,
  iteration, and insertion logic while preserving VFSNAP statuses, sealing,
  null/empty policy, and alias rejection.
- Resource acquisition collects its four possibly overlapping borrowed inputs
  with `PUSH`, adds the first public output, and checks the second output against
  that set. This replaces the exact nine output-facing pair checks without
  imposing a new input-versus-input restriction.

The writer consumers are:

- Grid embeds a writer in each component state allocation. It replaces the
  manual append address/length/count scratch and private I/O-error field while
  preserving the CSV serializer's public capacity and invalid status mapping.
- App-builder owns one manifest writer. It replaces the manifest length,
  serialization-error, one-byte character scratch, and ambient number-string
  formatter while preserving exact manifest content and `ABUILD-E-SERIALIZE`
  behavior.

The VFSNAP specification grows from 320 to 328 activation-local bytes because
the inline set has a count and capacity header. All callers allocate through
`VFSNAP-SPEC-SIZE`. Snapshot header, payload, checksum, publication, and other
durable bytes are unchanged.

## Boundary contract

| Case | Span set | Checked writer |
| --- | --- | --- |
| signed length / unsigned wrap | rejected without mutation | descriptor, target, and source geometry rejected without mutation |
| overlap | `ADD` rejects; `PUSH` intentionally admits borrowed-member overlap | source/target overlap uses `MOVE`; source/descriptor overlap rejects |
| exact adjacency | disjoint | ordinary bounded append |
| zero length | stored and consumes one set slot, but never overlaps | succeeds without touching bytes, including a null source |
| borrowed object | only address/length are copied; clear never touches the object | source bytes are copied only after complete reservation |
| full capacity | returns capacity with count unchanged | latches capacity with length and target bytes unchanged |
| corrupt active state | invalid active entry invalidates the complete set | invalid descriptor or sticky error prevents later writes |
| independent callers | separate sets do not share count or entries | one writer's failure cannot poison another writer |

The focused Gate 2A fixture covers the signed maximum allocation boundary,
active-entry corruption, wraparound, overlap symmetry, adjacency, empty spans,
borrowed storage, capacity atomicity, overlapping `MOVE`, writer isolation,
ambient-base independence, and both signed 64-bit decimal extrema.

## Functional-preservation scope

The production changes touch these L1 behavior groups:

- `library.model-and-durable-semantics` through VFSNAP;
- `library.query-and-projection` through resource acquisition;
- `streams.observation-truth-and-recovery` through its VFSNAP-backed stores;
- `grid.formulas-csv-and-actions` through CSV output;
- `desk.catalog-launch-and-lifecycle` through app-builder manifest output.

No conditional L1 prerequisite is triggered. L2 does not replace an
observation-store format or retention policy, change Grid input dispatch or
dirty-close behavior, or begin Desk child-host extraction.

Daybook and Pad deliberately retain their clipping/truncation writers because
that behavior is not the checked writer's all-or-nothing contract. SoundLab is
reserved for its later MediaLab direction. Game and Worlds remain frozen and
untouched.

## Qualification

The following emulator profiles pass:

- `gate2a-contracts` — 176 checks;
- `vfs-fixed-snapshot-contracts` — 526 checks;
- `gate3a-resource-contracts` — 409 checks;
- `grid-contracts` — 142 checks;
- `package-contracts` — 163 checks;
- `streams-source-store-contracts` — 191 checks;
- `streams-observation-store-contracts` — 130 checks;
- `library-vfs-store-contracts` — 400 checks;
- `library-projection-owner-contracts`;
- `desktop-local-applet`, including build/install/launch through the linked
  Desk image.

The architecture and functional ledgers and the host packaging/Desk suite are
also part of the landing gate. None of this qualification requires ext4; VFS
consumers use the existing generic contract and MP64FS fixtures.

## Architecture ratchet

The reviewed L2 graph has 381 production modules, 1,286 resolved `REQUIRE`
occurrences, and 1,285 unique resolved edges. The new neutral writer accounts
for one module; its memory-span dependency and Grid's consumer edge account for
the two net edges. App-builder replaces its obsolete string dependency rather
than retaining it as compatibility glut.

Placement debt, layer violations, unresolved imports, dependency cycles,
identity/addressability debt, and the placement/unresolved digests are
unchanged. The state digest is intentionally updated for the deleted consumer
scratch declarations.
