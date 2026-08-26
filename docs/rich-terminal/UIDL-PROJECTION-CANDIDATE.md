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
caller-owned item banks and two caller-owned snapshot banks. A projection
builds only the inactive pair, revalidates it with
`RUPJ-CANDIDATE-VALID?`, completes its bounded metadata, and publishes the new
bank by writing the binding selector last. Written bytes and inactive metadata
are never authoritative on their own.

Each published bank has a 64-byte metadata record containing generation, item
count, snapshot bytes, region/object/UTF-8 quotas, and the positive root height
and width used for capture and validation. The two records occupy offsets 144
and 208 in the 280-byte private binding record; offset 272 remains reserved.
The root dimensions travel with the selected candidate rather than being
recovered from later mutable layout.

An accepted empty candidate is still selector-published so it supersedes any
older desired scene, but `RTERM-UCTX-PROJECT` returns
`RTERM-S-UNAVAILABLE`; an accepted nonempty candidate returns
`RTERM-S-OK`. A build, validation, capacity, or caught-exception failure does
not change the selector, so the previously selected candidate remains
authoritative. Admission is the only place the driver performs the full RUPJ
bank validation. This slice remains output-inert: it neither calls the `RTE`
facade nor assigns retained identities or materializes terminal objects.

The downstream neutral boundary can now accept an aligned 160-byte LABEL value
whose height and width are nonnegative and whose borrowed UTF-8 may begin at
any byte address. Visible geometry must have positive extent and intersect the
positive root. Invisible zero-extent or wholly off-root geometry is valid;
RTAPT canonicalizes it to deterministic nonempty provider bounds while
preserving invisibility and converts the clipped boundaries at full
`UNORM32` precision. The borrowed text must be nonwrapping and disjoint from
facade/provider storage. RTAPT copies it into an aligned, pointer-free retry
record, maintains exact active/hidden/pending object and UTF-8 ledgers, and
commits it through the typed PT LABEL writer.

The lifecycle driver does not yet exercise that downstream path. The next
slice assigns retained identities, applies negotiated admission, materializes
the selected candidate, and schedules it through the unified CELL/retained
publication lifecycle. None of that moves scene ownership, output choice, or
renderer-specific state into UIDL, UIDL-TUI, Desk, or applets.
