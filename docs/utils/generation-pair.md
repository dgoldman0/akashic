# Generation-pair selection and publication

`akashic/utils/generation-pair.f` provides caller-owned state for selecting
between two independently decoded generation candidates and publishing the
next generation into the inactive slot. It is deliberately policy-neutral:
it owns no path, VFS handle, record format, payload bytes, checksum, semantic
validation, allocation, or domain status mapping. Callers perform those jobs
in adapters and describe only their results to this module.

The implementation has no module-global mutable scratch. A candidate occupies
`GPAIR-CANDIDATE-SIZE` bytes and a pair occupies `GPAIR-SIZE` bytes, both
allocated by the caller. Each fixed span must be nonwrapping. The two candidate
spans and the pair span must be pairwise disjoint for selection; exact
adjacency is allowed. Independently allocated pairs can be used from one
another's callbacks.

## Candidate descriptors

Initialize a candidate with `GPAIR-CANDIDATE-INIT`, then classify one decoded
slot with exactly one of these mutators:

| Word | Stack effect | Meaning |
|---|---|---|
| `GPAIR-CANDIDATE-ABSENT!` | `( detail candidate -- status )` | No record exists in this slot. |
| `GPAIR-CANDIDATE-CORRUPT!` | `( detail candidate -- status )` | A record exists but the caller rejected it. |
| `GPAIR-CANDIDATE-VALUE!` | `( value generation detail candidate -- status )` | The caller accepted a positive generation and attaches an opaque value. |

`detail` and `value` belong to the caller; zero is valid for either. A valid
candidate must have a generation greater than zero. Absent and corrupt
candidates always have generation zero. A rejected mutation leaves the
existing descriptor unchanged.

The accessors are `GPAIR-CANDIDATE-CLASS@`,
`GPAIR-CANDIDATE-GENERATION@`, `GPAIR-CANDIDATE-VALUE@`, and
`GPAIR-CANDIDATE-DETAIL@`. `GPAIR-CANDIDATE-VALID?` validates the descriptor's
magic, class, and generation invariant. Candidate classes are
`GPAIR-C-ABSENT`, `GPAIR-C-VALID`, and `GPAIR-C-CORRUPT`.

## Pair initialization and selection

Initialize a pair with:

```forth
equal-xt save-xt context pair GPAIR-INIT  ( -- status )
```

Both callbacks are required. The context cell is opaque and is returned by
`GPAIR-CONTEXT@`. `GPAIR-RESET` forgets selected and publication state while
retaining the callbacks and context.

Selection has the interface:

```forth
candidate-a candidate-b pair GPAIR-SELECT  ( -- result status )
```

Structurally invalid, wrapping, exactly aliased, or partially overlapping
descriptors are rejected before the pair is changed. Once both descriptors
are accepted, selection first revokes any old RAM authority by clearing the
selected candidate, generation, and active slot. It then classifies the new
pair as follows:

| Candidate A | Candidate B | Result | Authority |
|---|---|---|---|
| absent | absent | `GPAIR-R-ABSENT` | none |
| corrupt/absent | corrupt/absent, with at least one corrupt | `GPAIR-R-CORRUPT` | none |
| valid | absent/corrupt | `GPAIR-R-FALLBACK` | A |
| absent/corrupt | valid | `GPAIR-R-FALLBACK` | B |
| valid, newer | valid, older | `GPAIR-R-NEWEST` | A |
| valid, older | valid, newer | `GPAIR-R-NEWEST` | B |
| valid, equal generation and equal value | valid, equal generation and equal value | `GPAIR-R-EQUAL` | A |
| valid, equal generation and divergent value | valid, equal generation and divergent value | `GPAIR-R-AMBIGUOUS` | none |

Equal generations are resolved by the caller callback:

```forth
value-a value-b context equal-xt EXECUTE  ( -- equal? detail )
```

The returned detail is preserved exactly in `GPAIR-DETAIL@`. A callback throw
returns `GPAIR-S-CALLBACK`, leaves the classification at `GPAIR-R-NONE`, and
preserves the exact throw code in `GPAIR-CALLBACK-THROW@`. A rejected equal
pair, an absent/corrupt pair, or a callback failure cannot retain authority
from an earlier successful selection.

Selection classification and operation status are independent. In
particular, absent, corrupt, fallback, newest, equal, and ambiguous are
successful classifications with `GPAIR-S-OK`; they are not I/O or domain
statuses.

The selected state is exposed through `GPAIR-RESULT@`, `GPAIR-SELECTED@`,
`GPAIR-GENERATION@`, and `GPAIR-ACTIVE-SLOT@`. An active slot is
`GPAIR-SLOT-A` or `GPAIR-SLOT-B`; `-1` means no authoritative slot. Typed
consumer structures can map the state directly through the public address
accessors `GPAIR.GENERATION` and `GPAIR.ACTIVE-SLOT` without depending on
private field offsets.

## Publishing to the inactive slot

`GPAIR-SAVE` calculates the positive next generation, chooses the inactive
slot, and invokes the save callback:

```forth
payload pair GPAIR-SAVE  ( -- outcome status )

payload target-slot next-generation pair context save-xt EXECUTE
    ( -- detail )
```

The payload is an opaque cell. The adapter owns encoding, bounded staging,
path selection, writes, flushes, and its interpretation of callback detail.
If no slot is authoritative, A is the first target; subsequent durable saves
alternate A and B. Generation overflow returns `GPAIR-S-CAPACITY` without
invoking the callback.

Before its first operation that may produce an external effect, the callback
must execute `GPAIR-SAVE-MAYBE!`. After its durability boundary succeeds, it
must execute `GPAIR-SAVE-DURABLE!`. Those words enforce the only accepted
progression:

```text
GPAIR-W-NO-EFFECT -> GPAIR-W-MAYBE -> GPAIR-W-DURABLE
```

Skipping or repeating a transition returns `GPAIR-S-PROTOCOL`. The pair
adopts `next-generation` and `target-slot` in RAM only for a durable outcome.
This remains true if the callback throws after declaring durability: the
operation returns `GPAIR-S-CALLBACK`, preserves the exact throw code, and
adopts the already-durable generation. A normal callback return preserves its
exact detail and returns `GPAIR-S-OK`, regardless of which outcome the adapter
reported. The adapter decides how its detail and the three outcomes map to a
domain result.

`GPAIR-OUTCOME@`, `GPAIR-TARGET-SLOT@`, and
`GPAIR-NEXT-GENERATION@` expose the last attempted publication. The pure
queries `GPAIR-INACTIVE-SLOT?` and `GPAIR-NEXT-GENERATION?` expose the next
choice without invoking a callback. A durable save updates generation and
active slot, but it does not replace `GPAIR-SELECTED@`: that accessor continues
to identify the candidate from the last successful selection, not the saved
payload. Reset or select again before treating it as fresh read authority.

## Re-entry and ownership

A selection or save operation marks only its own pair active. Recursive use
of `GPAIR-SELECT`, `GPAIR-SAVE`, or `GPAIR-RESET` on that same pair is refused
with `GPAIR-S-BUSY`; publication marker calls outside the active save callback
are refused with `GPAIR-S-PROTOCOL`. The callback may operate on a different,
independently allocated pair.

This is a synchronous re-entry guard, not a scheduler or cross-core locking
primitive. The owner must serialize access to a pair when different tasks or
cores can reach it concurrently. Pair storage and callback context must remain
alive for the complete pair lifetime. Because a successful selection retains
the selected candidate address, both candidate descriptors must remain alive
and unchanged until reset or reselection, or until the owner has stopped
observing that selection state.

The status family is `GPAIR-S-OK`, `GPAIR-S-INVALID`, `GPAIR-S-BUSY`,
`GPAIR-S-CALLBACK`, `GPAIR-S-CAPACITY`, and `GPAIR-S-PROTOCOL`.

## Adapter boundary

A persistence adapter normally performs these steps:

1. Read each physical slot, if present.
2. Validate its framing, checksum, payload bounds, and domain semantics.
3. Populate one candidate descriptor for each slot.
4. Call `GPAIR-SELECT` and translate its classification into domain status.
5. On save, encode into caller-owned bounded storage and let the save callback
   publish to the target selected by `GPAIR-SAVE`.

Nothing in this contract requires VFS or VREPL, defines a legacy-format
transition, or removes any applet behavior. It factors only the reusable
two-slot generation machinery; payload and ecosystem policy remain with the
consumer.
