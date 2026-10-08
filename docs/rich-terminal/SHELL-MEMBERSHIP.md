# Frozen shell document membership

`tui/rich-terminal/shell-membership.f` joins a frozen SHM shell model, the
240-byte RUHA document directory, and the successful RSHPL plan's 192-byte
correlations. It reads no live host, UCTX, app descriptor, name, or title to
infer membership. The caller must first establish that the source snapshots
and shell plan belong to the same completed draw and immutable candidate.
The helper checks coherent nonzero correlation DRAW/ATTACHMENT and exact SHM
root owner/generation/epoch; a directory alone contains no completed-draw
field with which to independently prove that outer lifecycle relation.

```forth
RSHMM-BUILD
  ( model-a model-u directory-a directory-u correlations-a correlations-u
    destination capacity -- count used status )
RSHMM-FIND ( token validated-map-a map-u -- entry-or-zero )
RSHMM-RECT-MEMBER
  ( row col height width validated-map-a map-u -- content-region status )
RSHMM-STORAGE-DISJOINT? ( address bytes -- flag )
```

Statuses are `RSHMM-S-OK=0`, `CAPACITY=1`, `UNAVAILABLE=2`, and `INVALID=3`.
No storage is allocated. Every input span and the full destination capacity
must be pairwise disjoint and outside invoked module scratch. All validation
and capacity checks precede the first destination write; every refusal leaves
the destination unchanged. Success writes only the used prefix and preserves
the tail. Empty spans are canonical `(0,0)`; record spans are eight-byte aligned.

One 112-byte pointer-free record is emitted per admitted PANE correlation,
in correlation order. `RSHMM-ENTRY-SIZE` is 112. The required size is exactly
`112 * admitted-pane-count`, bounded by `112 * (correlation-bytes / 192)`.

| Offset | `RSHMM.*` field |
|---:|---|
| 0 | TOKEN; document attachment token, or zero when absent |
| 8 | SLOT-ID; signed ordinary host identity |
| 16, 24 | OWNER, GENERATION; component instance identity |
| 32 | CONTENT-REGION |
| 40 | SOURCE-INDEX; SHM entry ordinal |
| 48 | DIRECTORY-INDEX; RUHA ordinal, or −1 when absent |
| 56, 64, 72, 80 | ROW, COL, HEIGHT, WIDTH; absolute content rectangle |
| 88 | CHROME-REGION |
| 96 | PANE-ID |
| 104 | RESERVED; zero |

The helper deep-validates frozen SHM first. Each PANE correlation must exactly
match its SHM ordinal, kind, key, signed identity, child component tuple, outer
rectangle, flags and action. Retained pane/chrome/content identities must be
nonzero, and content differs from chrome. Source owner/generation/epoch match
SHM; draw and shell attachment match throughout the correlation vector.
Duplicate pane ordinals, signed identities, retained pane IDs or content region
IDs are refused. Non-PANE correlations are not membership rows.

Directory tokens and signed slot identities must be unique. For an emitted
pane, no directory with that signed slot identity means a legitimate pane
without a UIDL document: TOKEN=0 and DIRECTORY-INDEX=−1. If a same-slot directory
exists, its actual CINST owner/generation and entire content rectangle must
match exactly. Stale metadata is never reinterpreted as an empty pane.
Directories for omitted or unrelated slots remain unmapped. Positive and
negative identities remain distinct even when their unsigned source keys
coincide.

`RSHMM-TOKEN@` and `RSHMM-CONTENT-REGION@` are scalar getters. The other
`RSHMM.*` words return field addresses. `FIND` is read-only and requires an
exact immutable successful output span; token zero never matches. CONTROL and
STATIC correlation attachment tokens can therefore resolve membership without
changing object IDs or parent hierarchy.

`RECT-MEMBER` requires the same validated map. It returns a region only when
exactly one content rectangle fully contains the requested positive rectangle.
No match, a run crossing a boundary, or overlapping candidates return
UNAVAILABLE. The helper chooses no overlay priority and splits no UTF-8. A
residual glyph producer may split runs at the exposed rectangle boundaries
while retaining ordinary CELL/grapheme semantics, then query each resulting
rectangle. Its root coordinates remain unchanged when catalog regions use
surface-sized logical bounds with exact content clips.

The map contains only scalars and remains valid after its source banks are
released or reused. `local_testing/test_shell_membership.py` executes the real
native dependency closure, covering exact joins, absent directories, signed
overlays, frozen-source lifetime, stale tuples/geometry, duplicate ambiguity,
capacity and alias refusal, and rectangle containment.
