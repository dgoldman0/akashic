# Refactor Landing L4 checked records and generation pairs

Landing L4 extracts two repeated persistence mechanisms into independent
Akashic libraries: mechanically checked record envelopes and two-slot
generation selection/publication. It does not replace an applet, create a
generic repository, change a product capacity, or move applet policy into a
neutral package.

## Checked-record boundary

`utils/checked-record.f` is an allocation-free byte codec with caller-owned
sealed specifications and one caller-owned workspace per active operation. It
supports exact fixed records and aligned framed records. The descriptor names
an eight-byte magic, format, tag policy, geometry, encoder, and semantic
validator; the core owns only:

- overflow-safe record measurement and exact input/output bounds;
- the common 64-byte header, header and payload CRC-32, and canonical zero
  tail or alignment padding;
- validation order, including authenticated future-format classification;
- callback containment, failure wiping, hostile-alias checks, and same-workspace
  re-entry refusal; and
- header-only inspection that publishes geometry but no unvalidated payload.

The tag is deliberately uninterpreted. The codec does not choose a path,
perform I/O, order generations, allocate a model, or map a domain status.
Specifications, workspaces, record storage, contexts, and decoded destinations
remain owned by their callers; the neutral module declares no mutable lexical
state.

Two materially different consumers prove the contract:

- VFS fixed snapshots use a fixed record, interpret the positive tag as their
  optimistic generation, and retain VREPL publication, path, recovery latch,
  cleanup, and typed callback/status policy. The 64-byte envelope and complete
  durable record bytes remain byte-stable.
- Library record codecs use fixed catalog/collection records and a framed
  content record. Library retains identities, revisions, media, digest,
  UTF-8, model validation, borrowed-view lifetime, and exact public statuses.
  Fixed record bytes remain stable. Content keeps its 160-byte absolute data
  offset and 65,696-byte maximum while the obsolete private 160-byte envelope
  is replaced directly by the common 64-byte envelope plus 96 bytes of
  Library semantic payload. This prototype has one current reader, not an old
  and new compatibility stack.

Library maintenance now classifies head bytes through public checked-record
inspection. The private Library fixed/content header constants and CRC helpers,
and the private VFSNAP header offsets and CRC helpers, are deleted.

## Generation-pair boundary

`utils/generation-pair.f` owns only the state machine shared by two decoded
candidates. Callers allocate the candidate descriptors and pair state. They
classify each slot as absent, corrupt, or valid with a positive generation and
opaque value. The pair then reports absent, corrupt, fallback, newest, equal,
or ambiguous and publishes authority only for an unambiguous valid candidate.

Equal-generation meaning is injected by the consumer. A consumer also injects
the inactive-slot save callback and marks its progress through no-effect,
maybe-effect, and durable milestones. RAM generation and active-slot authority
advance only at durability; a throw after durability preserves the adopted
authority and the exact callback failure. The neutral layer owns no path,
format, payload, checksum, allocation, I/O, domain status, recovery mode, or
locking policy.

The proving consumers retain those policies:

- Agent conversation storage compares complete verified snapshot bytes for an
  equal generation, owns both transcript paths and codecs, and maps VFS and
  uncertain-publication outcomes into the existing conversation-store API.
  Every load now revokes prior RAM authority before inspecting either slot, so
  absent, corrupt, split-brain, decode, cleanup, and guard-release failures
  cannot retain history-dependent generation state.
- Practice compares decoded heads, owns its paths, record bytes, semantic
  fallback validation, rejected-generation evidence, readonly recovery, and
  public statuses. Semantic fallback is reclassified through the same pair so
  its selected candidate, generation, and active slot all describe the head
  actually accepted.

Both adapters use stable candidate-descriptor identity rather than retaining
transient decoded models. This closed two lifetime bugs that the extraction
made visible: Agent could otherwise retain a returned/freed conversation as
selection state, and Practice could retain a freed decoded head. Practice
reinitialization resets pair selection before publishing its new durable head.
Their current in-memory adapter size constants grow to embed the pair and two
candidates directly. Callers recompile against those constants; persisted
bytes and public word signatures stay unchanged, and no obsolete-size facade
is retained.

## Removed consumer residue

Streams source and observation stores already consumed VFSNAP. Their typed
descriptors nevertheless retained a 40-byte mirror of core magic, VFS, flags,
last status, and replacement placement plus aliases to VFSNAP's private record
header and CRC implementation. L4 embeds VFSNAP at offset zero, maps the typed
accessors directly to its public state, and removes the mirrors, duplicate
status synchronization, header offsets, and private CRC aliases. Paths,
formats, registry/observation codecs, statuses, recovery behavior, and public
typed accessors remain.

The manual-refresh fixture previously linked an unused concrete online-provider
closure into an unchanged 4,096-sector image. It now installs its deterministic
configured provider through the public Streams factory seam and initializes
the real Desk service table. This preserves the production path under test and
restores the bounded fixture without raising a storage constant or removing a
production provider.

## Functional-preservation scope

The production changes touch these L1 behavior groups:

- `library.model-and-durable-semantics`,
  `library.query-and-projection`, and Library maintenance/cold recovery;
- `streams.source-management-and-refresh`,
  `streams.observation-truth-and-recovery`, and the Desk manual-refresh path;
- `agent.persistence-and-recovery`; and
- Practice durable-head activation used by the linked Desk image.

No action, capability, provider, path, content class, retention rule, public
status, applet view, or cross-applet journey is removed. Game, Worlds,
SoundLab/MediaLab, ownership moves, indexed scaling work, interop construction,
and every L5-or-later concern remain untouched. L4 also changes no ext4 code
and requires no ext4 completion.

## Qualification

The focused and converted-consumer emulator evidence is:

| Command profile | Result |
| --- | --- |
| `checked-record-contracts` | 160 assertions; 129,653,795 steps |
| `generation-pair-contracts` | 280 assertions; 105,683,070 steps |
| `vfs-fixed-snapshot-contracts` | 556 assertions; 292,165,667 steps |
| `library-model-codecs-contracts` | 336 assertions; 414,677,377 steps |
| `library-vfs-store-contracts` | 400 assertions; 1,662,526,762 steps |
| `library-maintenance-contracts` | 221 assertions; 1,817,722,347 steps |
| `conversation-store` | 311 assertions; 358,863,432 steps |
| `agent-persistence` | 69 assertions; 606,938,192 steps |
| `practice-contracts` | 215 assertions; 464,309,971 steps |
| `streams-manual-refresh-contracts` | 245 assertions; 4,833,071,033 steps |
| `streams-persistence-contracts` | 108 assertions; 2,210,891,065 steps |
| `streams-refresh-owner-contracts` | 333 assertions; 2,932,915,594 steps |
| `streams` | 552 assertions; 2,372,947,186 steps |
| `desktop-streams` | PASS; 7,180,000,000 steps |
| `agent-ui` | PASS; 2,950,000,000 steps |
| `desktop-resource` | PASS; 6,790,000,000 steps |
| `desktop` with the supported default ceiling | PASS; ready at 8,560,000,000 steps |

Additional Library profiles pass for managed documents (169 assertions),
managed lifecycle (226), capture/collection (153), query/index (587),
projection ownership (723), managed capacity, both standalone applet contract
profiles, and the complete applet functional contract. The exact cold two-boot
journeys pass for managed documents, projection ownership, lifecycle, and
query. The literal Gate 4 exit harness also passes clean boot and independent
head, selected-bank, content-frame, and checksummed-future-head damage on a
1,463,808-byte image.

The focused contracts exercise signed and wrapping geometry, fixed tails,
framed padding, exact and future formats, checksums, semantic rejection,
callback faults, failure nonmutation/wiping, hostile aliases, recursion,
independent workspaces, absent/corrupt/fallback/newest/equal/ambiguous pairs,
generation overflow, inactive-slot alternation, pre-effect failures, uncertain
effects, and durable-then-throw adoption. Converted VFS and applet suites add
partial/short I/O, sync and cleanup faults, cold selection, semantic fallback,
split-brain refusal, and exact resource cleanup.

The combined host gate passes 205 tests, followed by both reviewed ratchets:

```bash
python3 -m pytest -q \
  local_testing/test_vfs.py \
  local_testing/test_vfs_mp64fs.py \
  local_testing/test_refactor_inventory.py \
  local_testing/test_refactor_functional_baseline.py \
  local_testing/test_akashic_tui_packaging.py \
  local_testing/test_desk_gate0_baseline.py
python3 local_testing/refactor_inventory.py --check
python3 local_testing/refactor_functional_baseline.py --check
```

No qualification ceiling above is a product capacity or scalability result.
The emulator limits provide deterministic execution headroom only.

## Architecture ratchet

The reviewed L4 graph has 384 production modules, 1,295 resolved `REQUIRE`
occurrences, and 1,295 unique resolved edges. The two neutral modules and their
real consumer edges account for the increase; Library record-codec also drops
an obsolete duplicate guard import.

Neither neutral module adds lexical mutable state. Current lexical-global
totals are 2,752 applet, 1,100 Desk ecosystem, and 7,072 independent library.
The consumer-side increases are explicit adapter evidence/comparison state;
the neutral operation and selection state is caller-owned. Streams deletes its
four status-mirror globals and both 40-byte descriptor mirrors.

The in-memory footprint cost is explicit: VFSNAP specifications grow 328 to
440 bytes and stores 1,232 to 1,424 bytes for the embedded checked-record
specification/workspace/context; Agent and Practice stores each grow by 224
bytes for one pair and two candidates. Each Streams descriptor nets a 152-byte
increase after deleting its 40-byte mirror while inheriting VFSNAP's 192-byte
workspace/context increase. These are per-instance operation-state bytes, not
larger corpus, content, source, observation, or record limits.

Placement debt, layer violations, unresolved imports, cycles, identity debt,
addressability debt, capacity policy, and scale policy are unchanged. L4 is a
mechanism-distribution landing; the later Library/Streams indexed scale
landings remain responsible for speed, dataset size, and query complexity.
