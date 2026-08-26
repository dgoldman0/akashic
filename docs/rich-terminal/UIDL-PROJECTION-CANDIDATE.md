# UIDL projection candidates

**Module:** `akashic-tui-rterm-uidl-projector1`

**File:** `akashic/tui/rich-terminal/uidl-projector.f`

The projector is the renderer-neutral desired-scene boundary between an active
UIDL document and optional output adapters. It captures supported UIDL
semantic snapshots into caller-owned storage. It does not query an engine,
open an owner, emit terminal bytes, select CELL versus retained output, or
change UIDL dirty state. Desk and applets do not load or call it.

## Candidate item

Each 128-byte item contains:

| Offset | Field | Meaning |
|---:|---|---|
| 0 | element index | stable current-document UIDL pool index |
| 8 | semantic subkey | zero for the primary semantic object |
| 16 | kind | neutral UIDL snapshot kind |
| 24 | snapshot offset | aligned offset in the supplied arena |
| 32 | snapshot bytes | exact semantic record length |
| 40 | flags | `HAS_RESOLVED=1`, `EFFECTIVE_VISIBLE=2` |
| 48..119 | resolved state | copied 72-byte UIDL-TUI geometry/style record, normalized root-relative |
| 120 | reserved | zero |

The element index comes only from `UIDL-ELEM-INDEX?`; markup `id=` is not
projection identity and changing or omitting it cannot renumber an element.
The subkey leaves room for a later semantic family to derive more than one
object from one element without exposing renderer identities to UIDL.

`HAS_RESOLVED` means the 72-byte record is present and valid.
`EFFECTIVE_VISIBLE` may be set only with `HAS_RESOLVED`; it records the
effective UIDL visibility after ancestor visibility and clipping have been
resolved. All other flag bits are invalid. The copied record preserves height,
width, colors, attributes, alignment, and effective paint-group z while
converting its row and column from document coordinates to coordinates
relative to the candidate root. It contains no CELL, engine, protocol, region,
Desk, or applet identity.

## Construction

```forth
RUPJ-BUILD
( items-a items-u snapshots-a snapshots-u
  -- item-count snapshot-used region-quota object-quota utf8-quota
     root-h root-w status )
```

An accepted bank can be revalidated independently of the source document:

```forth
RUPJ-CANDIDATE-VALID?
( items-a items-u item-count snapshots-a snapshots-u snapshot-used
  region-quota object-quota utf8-quota root-h root-w -- flag )
```

Validation checks exact key uniqueness, item fields, canonical contiguous
aligned offsets, each complete LABEL record, raw-capacity accounting, zero
alignment padding, the flag implications, each present resolved record against
the positive root dimensions, and zero unused bank tails. A missing resolved
record requires both flags and all 72 payload bytes to be zero. Guarded builds
serialize the projector's complete borrowed-bank lifetime. The compound
observation order is UIDL-TUI resolved state, UIDL, projector scratch, then the
semantic source observation; recursive acquisition remains within those outer
authorities.

Both spans must be nonempty, aligned, nonwrapping, mutually disjoint, and
disjoint from persistent UIDL, UIDL-TUI, and active state-tree storage. The
item span must be an exact multiple of `RUPJ-ITEM-SIZE`. `root-h` and `root-w`
must both be positive. No heap, dictionary, XMEM, engine, host, screen, or wire
storage is acquired.

The complete root tree is walked in preorder under one
compound observation. A currently supported LABEL produces key
`(element-index,0)` and a copied LABEL snapshot. Semantic eligibility determines
candidate membership independently of resolved-state availability. When
UIDL-TUI returns resolved `OK`, the projector copies and validates the record,
normalizes its coordinates, and sets `HAS_RESOLVED` plus
`EFFECTIVE_VISIBLE` when applicable. Resolved `UNAVAILABLE` retains the LABEL
item with zero resolved flags and payload, preserving an otherwise valid
semantic candidate for a later projection. The root itself must return `OK`
because its geometry defines the normalization basis; root `UNAVAILABLE` or
`INVALID` invalidates the complete build. A LABEL without the neutral
`text-capacity=` declaration is skipped and retains its ordinary CELL path.
Malformed source, tree identity,
or resolved state returns `RUPJ-S-INVALID`; local arithmetic or storage
exhaustion returns `RUPJ-S-CAPACITY`.

Snapshot records have exact length `64 + text-capacity` but contain native
64-bit fields and therefore require aligned starting addresses. The physical
arena stride is checked `ALIGN8(exact)`. Items store the aligned offset and the
exact record length; `snapshot-used` is the sum of physical strides. Alignment
padding is zero. This local padding is not remote quota: `utf8-quota` is the
checked sum of raw declared text capacities, `object-quota` equals item count,
and `region-quota` is one exactly when the candidate is nonempty.

Construction clears the complete destination before writing. Any ordinary
failure or caught exception clears it again and returns five zero values plus a
stable status. The UIDL lifecycle driver assigns each private binding two
caller-owned item banks, two positional identity banks, and two caller-owned
snapshot banks. Identity extent is exactly one 32-byte record per candidate
item and therefore derives from the existing item/bank geometry rather than a
new fixed capacity. A projection builds the inactive item/snapshot pair and its
positional identity bank, revalidates the neutral recipe with
`RUPJ-CANDIDATE-VALID?`, completes its bounded metadata, and publishes the new
bank by writing the binding selector last. Written bytes and inactive metadata
are never authoritative on their own.

Each published bank has a 64-byte metadata record containing generation, item
count, snapshot bytes, region/object/UTF-8 quotas, and the positive root height
and width used for capture and validation. The two records occupy offsets 144
and 208 in the 352-byte private binding record. The root dimensions travel with
the selected candidate rather than being recovered from later mutable layout.
Private owner/terminal-eligibility fields begin at offset 272; they are not part
of the neutral candidate or projector ABI and do not reserve an owner or
provider capture-bank space. The 352-byte binding record ends with one reserved
cell at offset 344.

An accepted empty candidate is still selector-published so it supersedes any
older desired scene, but `RTERM-UCTX-PROJECT` returns
`RTERM-S-UNAVAILABLE`. A build or deep-validation failure does not change the
selector, so the previously selected candidate remains authoritative. After a
valid nonempty build, the driver first maps every exact semantic key to a stable
private object ID and then reads one coherent neutral `RTE` limits snapshot.
Backpressure, missing feature support, unresolved state, unsupported resolved
attributes, or negotiated capacity refusal still publishes the newer desired
bank and its mapping, but clears terminal eligibility/materialization readiness
and returns the exact non-OK status. A terminal-eligible candidate returns
`RTERM-S-OK`.

Terminal-negotiated eligibility requires INSTRUMENT support, one region, one
object per item, each declared LABEL capacity within the per-label maximum, and
the aggregate declaration within total UTF-8. It deliberately does not infer a
provider operation count, copied retry bytes, or encoded update bytes. Those
representation-dependent facts belong exclusively to the later neutral plan
preflight. Identity mapping is independent of the eligibility result: it
copies each exact semantic key into the positional identity bank, reuses an
exact prior mapped key's object ID, and mints new IDs from a monotone per-owner
high-water. Duplicate IDs are invalid; a high-water never proves that a sparse
ID exists. Negotiation refusal, relayout, and hide may revoke eligibility or
materialization readiness but do not discard this mapping or remint unchanged
keys. The binding selector remains the final publication store after metadata,
identities, eligibility state, status, and any sticky diagnostic are complete.

## Neutral materialization preflight

The downstream `RTE-LABEL-PREFLIGHT ( plan facade -- status )` boundary is now
landed. The materializer derives its call-borrowed plan from one exact selected
candidate generation and the already assigned private identities. The aligned
112-byte header is:

| Offset | Field | Candidate mapping |
|---:|---|---|
| 0 | owner | nonzero private binding owner ID |
| 8 | generation | nonzero private binding owner generation |
| 16 | surface columns | positive surface width for the attempted publication |
| 24 | surface rows | positive surface height for the attempted publication |
| 32 | region ID | nonzero private root-region ID |
| 40 | region x | nonnegative root origin column |
| 48 | region y | nonnegative root origin row |
| 56 | region columns | positive selected root width |
| 64 | region rows | positive selected root height |
| 72 | region z | signed root paint order |
| 80 | region flags | only current bits 0 and 1 |
| 88 | items address | aligned borrowed preflight-item array |
| 96 | items bytes | positive exact multiple of 128 |
| 104 | reserved | zero |

The checked root rectangle must fit the declared positive surface. The plan and
item spans are nonwrapping, mutually disjoint, and independently disjoint from
the facade and provider. `N = items-bytes / 128`; no unrelated fixed candidate
or LABEL count is introduced.

Each selected LABEL maps to one exact 128-byte item in capture order:

| Offset | Field | Candidate mapping |
|---:|---|---|
| 0 | object | mapped nonzero object ID, strictly increasing |
| 8 | parent | zero for this root-LABEL slice |
| 16 | row | signed resolved row relative to the root |
| 24 | column | signed resolved column relative to the root |
| 32 | height | nonnegative resolved height |
| 40 | width | nonnegative resolved width |
| 48 | root height | exactly the header region rows |
| 56 | root width | exactly the header region columns |
| 64 | z | signed resolved LABEL paint order |
| 72 | visible | canonical `0` or `-1` |
| 80 | RGBA | packed numeric `0xRRGGBBAA` |
| 88 | horizontal alignment | `0` start, `1` center, `2` end |
| 96 | vertical alignment | `0` top, `1` middle, `2` bottom |
| 104 | ellipsize | canonical `0` or `-1` |
| 112 | text capacity | snapshot's nonnegative declared UTF-8 capacity |
| 120 | reserved | zero |

The neutral facade validates native-cell geometry, canonical fields, strict
object order, exact root dimensions, checked edges, and visible intersection.
It does not assume APT-1 numeric widths. RTAPT owns the subsequent exact u32/i32
representability and geometry-conversion proof, current negotiated terminal
caps, local owner/op/copy-bank fit, dynamic owner and tombstone availability,
and complete wire arithmetic.

For item capacities `c_i`, RTAPT proves the exact owner-open quotas
`(regions=1, resources=0, objects=N, series=0, resource-bytes=0,
utf8=sum(c_i), sample-slots=0)`, `1 + N` local operation records, and copied
bytes `72 + sum(ALIGN8(128 + c_i))`. The first op-bearing hidden
`REPLACE_START` transaction is exactly:

```text
START = 248 + 120 * N + declared_utf8
declared_utf8 = sum(c_i)
```

The 248-byte base is the frozen 160-byte APT-1 wire transaction envelope plus
the 88-byte root-region definition. A later empty reveal transaction is exactly
160 bytes. They are serial bounded transactions, not one combined staging
requirement, so their budgets are never summed.

Preflight is mutation-free admission advice, not a reservation. Malformed
neutral input fails before the provider preflight operation callback is
dispatched, and an ordinary provider refusal causes no owner or wire mutation.
It never writes the plan, selected candidate, operation bank, copy bank, or
wire. Ordinary results also leave the owner ledger, lifecycle queue, and PT
session unchanged; limits observation may refresh only the provider's
designated limits scratch.
Discovering an already-lost session may invoke the engine's existing
quarantine/capture-clear transition, which is structural-loss containment, not
plan admission, and emits no wire. `OK` can become stale immediately, so the
materializer must use the same selected generation and exact derived quotas in
the immediately following checked `OWNER_OPEN`/capture sequence; neither a
prior eligibility result nor an earlier preflight is an admission token.

If discovery is pending, the selected candidate and mapping remain sufficient
for the owner-loop service to repeat negotiation in place when discovery
settles. That transition must not depend on another UIDL dirty event or rebuild
the semantic recipe merely to recover the same identities. Before any
`OWNER_OPEN` or retained capture, the materializer must build this exact plan
and call `RTE-LABEL-PREFLIGHT` to recheck current terminal limits, dynamic owner
availability, representation, encoded-update arithmetic, and caller-owned
provider owner, operation, and copied-byte capacity. Eligibility and advisory
success alone admit nothing.

This slice remains output-inert. Its only facade call is `RTE-LIMITS@`; it does
not open an owner, begin or seal retained work, choose CELL versus retained
output, or materialize terminal objects.

The downstream neutral boundary can now preflight the complete declared
root-and-LABEL recipe and accept each aligned 160-byte LABEL value. LABEL height
and width are nonnegative and borrowed UTF-8 may begin at any byte address.
Visible geometry must have positive extent and intersect the positive root.
Invisible zero-extent or wholly off-root geometry is valid; RTAPT canonicalizes
it to deterministic nonempty provider bounds while preserving invisibility and
converts clipped boundaries at full `UNORM32` precision. Borrowed text must be
nonwrapping and disjoint from facade/provider storage. RTAPT copies it into an
aligned, pointer-free retry record, maintains exact active/hidden/pending object
and UTF-8 ledgers, and commits it through the typed PT LABEL writer.

The lifecycle driver does not yet construct the plan or exercise the downstream
mutation path. The next slice invokes advisory preflight immediately before it
opens an eligible private owner, materializes the exact selected generation,
and schedules it through the unified CELL/retained publication lifecycle with
completion and retirement correlation. None of that moves scene ownership,
output choice, or renderer-specific state into UIDL, UIDL-TUI, Desk, or
applets.
