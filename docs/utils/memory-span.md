# Memory-span predicates

`akashic/utils/memory-span.f` provides allocation-free predicates and an
inline, caller-owned bounded collection for 64-bit half-open memory spans.

| Word | Stack effect | Meaning |
|---|---|---|
| `MSPAN-NONWRAPPING?` | `( address length -- flag )` | The length is nonnegative and `address + length` does not wrap in unsigned address arithmetic. |
| `MSPAN-OVERLAP?` | `( a1 u1 a2 u2 -- flag )` | Both spans are nonwrapping, nonempty, and their half-open intervals intersect. |

These words intentionally do not decide caller policy. In particular, an
empty span is nonwrapping, address zero is treated as an address rather than a
null-pointer error, and no ownership or private-range rule is implied. A
public API that rejects null, requires nonempty storage, or protects private
allocations must keep those checks at its own boundary.

Malformed or wrapping spans never overlap. Exact adjacency does not overlap.
The predicates do not dereference either address and own no mutable storage.

## Caller-owned span sets

`MSPAN-SET-BYTES` returns the inline allocation size for a fixed entry
capacity, or zero when the capacity is negative, its geometry would wrap, or
the result would not fit a nonnegative signed Forth length. The caller owns
those bytes for the complete set lifetime.

| Word | Stack effect | Meaning |
|---|---|---|
| `MSPAN-SET-INIT` | `( capacity set -- status )` | Initialize an inline set with that immutable capacity. |
| `MSPAN-SET-CLEAR` | `( set -- status )` | Forget all entries without touching the bytes they name. |
| `MSPAN-SET-VALID?` | `( set -- flag )` | Validate the inline header, total geometry, count/capacity relation, and every active entry. |
| `MSPAN-SET-COUNT@` | `( set -- count )` | Return the current entry count. |
| `MSPAN-SET-CAPACITY@` | `( set -- capacity )` | Return the initialized capacity. |
| `MSPAN-SET-OVERLAP?` | `( address length set -- flag )` | Test a span against every stored entry. |
| `MSPAN-SET-PUSH` | `( address length set -- status )` | Store valid geometry even when entries overlap one another. |
| `MSPAN-SET-ADD` | `( address length set -- status )` | Store valid geometry only when it is disjoint from every entry. |

Statuses are `MSPAN-SET-S-OK`, `MSPAN-SET-S-INVALID`,
`MSPAN-SET-S-OVERLAP`, and `MSPAN-SET-S-CAPACITY`. Failed mutations leave the
set unchanged. Zero-length spans are stored and consume a slot, but never
overlap. Exact adjacency remains disjoint.

An entry copies only its address and length. It does not copy, dereference,
clear, or free the named object. `PUSH` therefore supports a borrowed object
graph whose members may alias each other, while `ADD` supports private-region
registries that require pairwise disjointness. Concrete APIs still decide
whether a null address, empty span, or overlap with the set's own storage is
admissible.
