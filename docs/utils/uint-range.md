# Unsigned-start range algebra

`akashic/utils/uint-range.f` provides stateless half-open integer-range
predicates for geometry that is not inherently a memory address. A range is a
start cell plus a nonnegative signed-cell count; the start is interpreted as
unsigned, so high-bit starts remain valid when their exclusive end does not
wrap.

| Word | Stack effect | Meaning |
|---|---|---|
| `URANGE-VALID?` | `( start count -- flag )` | The count is nonnegative and `start + count` does not wrap in unsigned cell arithmetic. |
| `URANGE-OVERLAP?` | `( a-start a-count b-start b-count -- overlap? valid? )` | Report intersection and the validity of both ranges as separate flags. |

An empty range is valid and never overlaps. Exact adjacency is disjoint.
`URANGE-OVERLAP?` returns `false false` when either input is malformed, so a
caller that must fail closed can inspect `valid?` rather than treating the
result as ordinary non-overlap. The module does not dereference either start,
assign ownership, or decide whether zero is a valid domain value.

The count is deliberately not a full-width unsigned integer. Restricting it to
a nonnegative signed cell matches Forth length conventions and permits callers
to pass the count directly to ordinary bounded byte and entry operations after
validation.
