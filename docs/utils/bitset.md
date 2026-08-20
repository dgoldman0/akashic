# Checked LSB0 bitsets

`akashic/utils/bitset.f` provides stateless bitmap operations over a caller-
described byte buffer and a nonnegative logical bit count. Bit zero is the
least-significant bit of the first byte. The logical count, rather than the
rounded byte span, determines which bits belong to the set.

| Word | Stack effect | Meaning |
|---|---|---|
| `BITSET-BYTES?` | `( bit-count -- byte-count valid? )` | Compute `ceil(bit-count / 8)` without an overflowing `bit-count + 7`. |
| `BITSET-TEST?` | `( buffer bit-count bit -- set? valid? )` | Read one bounded bit. |
| `BITSET-BIT-SET?` | `( buffer bit-count bit -- valid? )` | Set one bounded bit. |
| `BITSET-BIT-CLEAR?` | `( buffer bit-count bit -- valid? )` | Clear one bounded bit. |
| `BITSET-ALL-SET?` | `( buffer bit-count first count -- all-set? valid? )` | Test whether every bit in a bounded range is set. |
| `BITSET-ALL-CLEAR?` | `( buffer bit-count first count -- all-clear? valid? )` | Test whether every bit in a bounded range is clear. |
| `BITSET-RANGE-SET?` | `( buffer bit-count first count -- valid? )` | Set a complete validated range. |
| `BITSET-RANGE-CLEAR?` | `( buffer bit-count first count -- valid? )` | Clear a complete validated range. |
| `BITSET-COUNT-SET?` | `( buffer bit-count -- set-count valid? )` | Count set logical bits, ignoring final-byte padding. |
| `BITSET-FIND-CLEAR?` | `( buffer bit-count first -- bit found? valid? )` | Find the first clear bit at or after `first`. |

Counts use the ordinary Forth convention of a nonnegative signed cell. A null
buffer is valid only when the logical bit count is zero. Empty ranges at any
index through the logical end are valid; both universal range predicates are
true for an empty range. `BITSET-FIND-CLEAR?` returns `0 false true` when a
valid search has no result and `0 false false` for invalid geometry.

The caller must provide at least the successful `BITSET-BYTES?` byte span at
`buffer`. Invalid queries return zero in their value field and a false validity
flag. Invalid mutations return false without changing any byte. Range
mutations validate the whole range before the first write. Mutations touch only
named logical bits, so padding bits in the final byte are preserved. Popcount
ignores those padding bits without normalizing them.

The utility does not own storage or define allocation search policy. It does
not update filesystem checksums, dirty flags, free-space counters, transaction
state, or format-specific padding. Those policies remain with each consumer.
