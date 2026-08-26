# UIDL semantic snapshots

**Module:** `akashic-uidl-semantic`

**File:** `akashic/liraq/uidl-semantic.f`

**Requires:** `akashic-uidl`, `akashic-utf8`, `akashic-memory-span`

`uidl-semantic.f` defines renderer-independent values copied from the
authoritative UIDL tree into caller-owned, bounded records. It does not own a
scene, allocate a payload bank, select an output implementation, or change
ordinary UIDL validity. An element without a supported snapshot remains a
normal UIDL element.

## Registry and dispatch

The existing 64-byte element-definition record uses its previously unused
`+56` cell as `ED.SEMANTICS`. `EL-SET-SEMANTICS` installs one hook with this
signature:

```forth
( elem destination capacity -- bytes status )
```

Exact `(destination=0, capacity=0)` requests measurement. A real capture must
receive an aligned, nonwrapping destination and sufficient caller-owned
capacity. Dispatch enters recursive guards in the canonical UIDL, semantic
scratch, LEL, then state-tree order. UIDL is outermost so a caller which already
owns the document guard can enter neutral semantics recursively without forming
a reverse document/scratch lock cycle against concurrent capture. Definition
lookup, expression evaluation, borrowed state text, validation, and the
synchronous copy share one coherent source observation. The generic API is:

```forth
UIDL-SNAPSHOT-SIZE     ( elem -- bytes status )
UIDL-SNAPSHOT-CAPTURE  ( elem destination capacity -- bytes status )
```

The stable statuses are `UIDL-SNAP-S-OK`, `UIDL-SNAP-S-UNSUPPORTED`,
`UIDL-SNAP-S-CAPACITY`, and `UIDL-SNAP-S-INVALID`. Every non-OK result is
canonicalized to `(0,status)`. Ordinary admission and preflight failures occur
before destination mutation. A caught late execution fault may have cleared or
partially filled caller memory, but LABEL publishes its magic last, so such a
record is not valid. A type with no installed hook returns `UNSUPPORTED`.

Callers which derive more than one record can hold one coherent source view:

```forth
UIDL-SEMANTIC-OBSERVE  ( i*x xt -- j*x )
```

The supplied execution token runs while the UIDL document, semantic scratch,
LEL evaluator, and state tree are all observed in that order. Public snapshot
operations may be called recursively inside the scope. This prevents a tree
walk from combining element identities or values from different source
moments; it does not publish or allocate any destination storage.

## Shared text value

```forth
UIDL-TEXT@  ( elem -- text-a text-u )
```

`bind=` takes precedence over `text=`. A bound string is used directly;
integers become decimal text; booleans become `true` or `false`; other bound
types preserve the existing single-space value. Only an element with no
`bind=` falls back to `text=`, then to an empty span.

The result is call-borrowed. Attribute and bound strings retain their normal
UIDL/state lifetime. Integer conversion uses one fixed 24-byte module scratch,
the complete native signed-decimal bound; it is protected across snapshot
capture and is not an application text capacity. A direct `UIDL-TEXT@` caller
must consume its result before another semantic text call. Snapshot capture
performs the copy synchronously. CELL label paint uses this same word but does
not consult snapshot admission.

The shared resolver also corrects the former CELL coercion bug which discarded
LEL's integer/boolean value cell and rendered the reserved zero cell instead.
String, integer, and boolean are still the only recognized bound text types;
other types retain the prior single-space behavior.

## LABEL text semantics

Every LABEL with valid resolved text is snapshot-eligible. UIDL does not carry
a retained-buffer reservation or require renderer-specific eligibility markup.
In particular, `text-capacity` is not a UIDL semantic: it describes one
renderer representation rather than application-visible behavior.

A future generic content limit is appropriate only when it is independently
observable application behavior across renderers—for example, an editable
field's semantic maximum length. Such a limit constrains the value regardless
of output mode; it is not a retained allocation hint and is not needed for a
LABEL snapshot.

Resolved text must be well-formed scalar UTF-8 and contain no NUL, CR, or LF.
Empty text is valid.

## LABEL record

The record is exactly `64 + current-text-bytes` bytes:

| Offset | Field | Meaning |
|---:|---|---|
| 0 | magic | literal bytes `UIDLSNAP`; native little-endian cell, written last |
| 8 | reserved | zero |
| 16 | kind | `UIDL-SNAPSHOT-K-LABEL` |
| 24 | bytes | exact complete record length |
| 32 | flags | zero |
| 40 | text bytes | current copied byte count |
| 48 | reserved | zero |
| 56 | reserved | zero |
| 64 | text | exact current text |

Public helpers are:

```forth
UIDL-LABEL-SNAPSHOT-BYTES           ( text-bytes -- bytes | 0 )
UIDL-LABEL-SNAPSHOT-VALID?          ( snapshot available -- flag )
UIDL-LABEL-SNAPSHOT-BYTES@          ( snapshot -- bytes )
UIDL-LABEL-SNAPSHOT-TEXT@           ( snapshot -- text-a text-u )
```

Capture resolves and validates every source fact, destination bound, overlap
with the current text, and disjointness from persistent UIDL and active
state-tree storage before modifying caller memory. It zeroes the exact record,
copies the current value, and publishes magic last. The caller must still own and
serialize independent writes to the destination; source-state serialization is
part of the neutral capture operation.
Validation rechecks all header invariants and UTF-8/control rules.

When text length changes, the next semantic observation measures and captures a
new exact record in the caller's inactive bounded bank. The generic downstream
adapter redefines or rebuilds that object while preserving its semantic
identity. If the current representation does not fit the caller's or
terminal's advertised bounds, rich materialization for that binding is refused
without truncating the value or changing complete CELL fallback. Capacity is
therefore an output-adapter fact derived from current content, never applet
markup.
