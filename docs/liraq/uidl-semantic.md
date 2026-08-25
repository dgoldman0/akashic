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

## LABEL declaration

A LABEL is snapshot-eligible only when it explicitly declares:

```xml
<label text="Ready" text-capacity="32" />
```

`text-capacity` is the maximum byte length of the resolved UTF-8 text. It is
not a cell, glyph, source-buffer, or pool capacity. Its syntax is canonical
unsigned decimal: digits only, no sign or whitespace, and no leading zero
except the single value `0`. Parsing is checked against the native
nonnegative length range.

Omission returns `UNSUPPORTED`; malformed syntax returns `INVALID`; current
text longer than the declaration returns `CAPACITY`. None of those outcomes
changes, truncates, or hides CELL text. A declaration is an admission promise
about future values, so it must not be inferred from the current literal.

Resolved text must be well-formed scalar UTF-8 and contain no NUL, CR, or LF.
Empty text and a zero declaration are valid together.

## LABEL record

The record is exactly `64 + text-capacity` bytes:

| Offset | Field | Meaning |
|---:|---|---|
| 0 | magic | literal bytes `UIDLSNP1`; native little-endian cell, written last |
| 8 | ABI | `1` |
| 16 | kind | `UIDL-SNAPSHOT-K-LABEL` |
| 24 | bytes | exact complete record length |
| 32 | flags | zero |
| 40 | text capacity | declared UTF-8 ceiling |
| 48 | text bytes | current copied byte count |
| 56 | reserved | zero |
| 64 | text/tail | current text followed by a zero-filled reserved tail |

Public helpers are:

```forth
UIDL-LABEL-SNAPSHOT-BYTES           ( text-capacity -- bytes | 0 )
UIDL-LABEL-SNAPSHOT-VALID?          ( snapshot available -- flag )
UIDL-LABEL-SNAPSHOT-BYTES@          ( snapshot -- bytes )
UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@  ( snapshot -- bytes )
UIDL-LABEL-SNAPSHOT-TEXT@           ( snapshot -- text-a text-u )
```

Capture resolves and validates every source fact, destination bound, overlap
with the current text, and disjointness from all persistent UIDL model storage
before modifying caller memory. It zeroes the complete reserved record, copies
the current value, and publishes magic last. The caller must still own and
serialize independent writes to the destination; source-state serialization is
part of the neutral capture operation.
Validation rechecks all header invariants, UTF-8/control rules, current length,
and the zero-filled unused tail.
