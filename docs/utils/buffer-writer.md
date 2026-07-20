# Checked buffer writer

`akashic/utils/buffer-writer.f` provides caller-owned, allocation-free bounded
output. A writer descriptor contains a caller buffer, capacity, current
length, and sticky status; no process-global current writer or formatting
buffer is used.

```forth
CBW-INIT    ( buffer capacity writer -- status )
CBW-RESET   ( writer -- status )
CBW-APPEND  ( address length writer -- status )
CBW-CHAR    ( char writer -- status )
CBW-NUMBER  ( n writer -- status )
CBW-VALID?  ( writer -- flag )
CBW-LENGTH@ ( writer -- length )
CBW-STATUS@ ( writer -- status )
CBW-RESULT  ( writer -- address length status )
```

The caller supplies `CBW-SIZE` descriptor bytes and retains the target buffer
for the complete initialized lifetime. `INIT` rejects negative or wrapping
geometry, a nonempty null target, and overlap between the target and its
descriptor. A zero-capacity writer is valid and accepts only zero-length
output.

Every append is all-or-nothing. Capacity is checked against the already-safe
`capacity - length` remainder, so the check cannot itself wrap. A failed
operation changes no target byte and does not advance the length.
`CBW-S-INVALID` or `CBW-S-CAPACITY` is latched as the first error; later writes
are no-ops that return that status until `CBW-RESET`. Reset preserves the target
bytes while clearing length and status.

Zero-length append accepts address zero. A nonempty source must be nonnull and
nonwrapping and may not overlap the writer descriptor. Source overlap with the
target is supported through overlap-safe `MOVE`, which permits composing
output from an earlier target slice. Two writers that target overlapping
buffers remain a caller synchronization error; one descriptor cannot govern
another caller's target.

`CBW-NUMBER` emits signed decimal independently of the ambient Forth base. It
preflights the sign and complete digit sequence before reserving output and
handles the most-negative 64-bit cell without overflowing `NEGATE`.
