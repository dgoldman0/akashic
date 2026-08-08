# Interoperability values

`akashic/interop/value.f` provides owned scalar, list, and map values used at
capability and provider boundaries. Container accessors validate the outer
type, element stride, bounded count, data pointer, and index before deriving a
child address. Returned children are borrowed from the owning container.

Owned strings, byte strings, and resource identifiers share the
`CV-MAX-STRING-LEN` payload bound. Their setters validate the complete request
before allocating, freeing, or copying, so a rejected length leaves the
destination value unchanged.

`CV-FREE` walks valid ownership graphs iteratively and has no fixed semantic
depth or node cutoff. A small inline work area handles ordinary values; deeper
graphs use transaction-scoped dynamic scratch that is released on normal and
exceptional exits. A read-only preflight reserves all required scratch before
teardown starts, making the mutating pass allocation-free; scratch exhaustion
therefore leaves a valid graph unchanged and safe to retry. Allocation
identities are tracked in a growable set, so a malformed ownership cycle or
duplicated owner cannot free the same allocation twice. Container shape and
count are still validated before child memory is read.

`CV-OWNED-SPAN-OVERLAP? ( address bytes value -- flag )` reports whether a
caller span intersects the retained root or any recursively owned allocation.
`CV-OWNED-GRAPHS-DISJOINT? ( left right -- flag )` proves that two complete
ownership graphs share no root or allocation span. Both predicates use an
iterative, dynamically growing walk rather than a semantic node limit. They
fail closed on malformed or wrapping geometry, internal duplicate/partial
allocation ownership, allocation failure, an unexpected throw, or recursive
entry by the same execution owner.

Positive-length borrowed `DATA` is checked for nonwrapping canonical shape but
is not registered or traversed: it lies outside the root's `CV-FREE` authority.
Consequently these predicates prove the geometry of the complete owned graph,
not the lifetime or disjointness of memory retained by a borrowed child.

`CV-MAP-FIND ( key-a key-u map -- value | 0 )` is a fail-closed lookup. The
caller key must have a length from zero through `CV-MAX-STRING-LEN`; a positive
length requires a non-null address. The map must have a valid bounded map
layout, and every candidate key encountered must itself be a string with a
bounded nonnegative length and a non-null address when nonempty. No byte
comparison occurs until both strings pass those checks.

A malformed candidate invalidates the complete lookup instead of being skipped
in favor of a later match. This transactional behavior prevents damaged or
borrowed container metadata from changing which duplicate-looking entry wins,
and prevents negative or attacker-sized lengths from reaching `STR-STR=`.
