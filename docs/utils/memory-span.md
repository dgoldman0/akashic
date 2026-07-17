# Memory-span predicates

`akashic/utils/memory-span.f` provides two allocation-free predicates for
64-bit half-open memory spans:

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
