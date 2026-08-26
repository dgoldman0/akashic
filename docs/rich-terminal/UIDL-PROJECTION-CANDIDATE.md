# UIDL projection candidates

**Module:** `akashic-tui-rterm-uidl-projector1`

**File:** `akashic/tui/rich-terminal/uidl-projector.f`

The projector is the renderer-neutral desired-scene boundary between an active
UIDL document and optional output adapters. It captures supported UIDL
semantic snapshots into caller-owned storage. It does not query an engine,
open an owner, emit terminal bytes, select CELL versus retained output, or
change UIDL dirty state. Desk and applets do not load or call it.

## Candidate item

Each 48-byte item contains:

| Offset | Field | Meaning |
|---:|---|---|
| 0 | element index | stable current-document UIDL pool index |
| 8 | semantic subkey | zero for the primary semantic object |
| 16 | kind | neutral UIDL snapshot kind |
| 24 | snapshot offset | aligned offset in the supplied arena |
| 32 | snapshot bytes | exact semantic record length |
| 40 | reserved | zero |

The element index comes only from `UIDL-ELEM-INDEX?`; markup `id=` is not
projection identity and changing or omitting it cannot renumber an element.
The subkey leaves room for a later semantic family to derive more than one
object from one element without exposing renderer identities to UIDL.

## Construction

```forth
RUPJ-BUILD
( items-a items-u snapshots-a snapshots-u
  -- item-count snapshot-used region-quota object-quota utf8-quota status )
```

An accepted bank can be revalidated independently of the source document:

```forth
RUPJ-CANDIDATE-VALID?
( items-a items-u item-count snapshots-a snapshots-u snapshot-used
  region-quota object-quota utf8-quota -- flag )
```

Validation checks exact key uniqueness, item fields, canonical contiguous
aligned offsets, each complete LABEL record, raw-capacity accounting, zero
alignment padding, and zero unused bank tails. Guarded builds serialize the
projector's complete borrowed-bank lifetime; candidate construction acquires
UIDL before projector scratch and the compound semantic source observation.

Both spans must be nonempty, aligned, nonwrapping, mutually disjoint, and
disjoint from persistent UIDL and active state-tree storage. The item span must
be an exact multiple of `RUPJ-ITEM-SIZE`. No heap, dictionary, XMEM, engine,
host, screen, or wire storage is acquired.

The complete root tree is walked in preorder under one
`UIDL-SEMANTIC-OBSERVE`. A currently supported LABEL produces key
`(element-index,0)` and a copied LABEL snapshot. A LABEL without the neutral
`text-capacity=` declaration is skipped and retains its ordinary CELL path.
Malformed source or tree identity returns `RUPJ-S-INVALID`; local arithmetic or
storage exhaustion returns `RUPJ-S-CAPACITY`.

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

An accepted empty candidate is still selector-published so it supersedes any
older desired scene, but `RTERM-UCTX-PROJECT` returns
`RTERM-S-UNAVAILABLE`; an accepted nonempty candidate returns
`RTERM-S-OK`. A build, validation, capacity, or caught-exception failure does
not change the selector, so the previously selected candidate remains
authoritative. Admission is the only place the driver performs the full RUPJ
bank validation. This slice remains wire-inert: it neither calls the `RTE`
facade nor assigns retained identities or materializes terminal objects.
UIDL-TUI now provides a validated copied 72-byte resolved geometry/style
record; the next candidate revision will append that neutral state without
exposing sidecar storage or a renderer identity.
