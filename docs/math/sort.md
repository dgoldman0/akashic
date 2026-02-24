# sort.f — Sorting & Rank Operations

**Module:** `math/sort.f`
**Prefix:** `SORT-`
**Depends on:** `fp16.f`, `fp16-ext.f`

Sorting primitives for FP16 arrays stored in HBW math RAM.

## Algorithm

`SORT-FP16` uses **Shell sort** with Knuth's gap sequence
(*h* = 3*h* + 1 → 1, 4, 13, 40, 121, 364, 1093, …).
Average complexity is O(*n*^1.5), suitable for arrays up to
several thousand elements.

`SORT-NTH` uses **iterative quickselect** with Lomuto partition,
giving O(*n*) average for finding the *k*-th smallest element
without a full sort.

## API Reference

### Sorting

| Word | Stack | Description |
|---|---|---|
| `SORT-FP16` | `( addr n -- )` | In-place ascending sort |
| `SORT-FP16-DESC` | `( addr n -- )` | In-place descending sort |

### Selection

| Word | Stack | Description |
|---|---|---|
| `SORT-NTH` | `( addr n k -- val )` | *k*-th smallest element (0-based). **Destructive** — rearranges the array |

### Utilities

| Word | Stack | Description |
|---|---|---|
| `SORT-IS-SORTED?` | `( addr n -- flag )` | Check ascending order |
| `SORT-REVERSE` | `( addr n -- )` | Reverse array in-place |

## Examples

```forth
\ Sort 10 FP16 values in HBW
20 HBW-ALLOT CONSTANT my-arr
\ ... fill my-arr with data ...
my-arr 10 SORT-FP16

\ Find the median of 10 values (destructive)
my-arr 10 5 SORT-NTH   \ 5th smallest = median for odd-like

\ Check if sorted
my-arr 10 SORT-IS-SORTED?   \ → TRUE
```

## Notes

- All addresses must be HBW pointers.
- Elements are 16-bit FP16 values (2 bytes each).
- Comparisons use `FP16-LT` from `fp16-ext.f` which handles
  ±0, ±∞, and NaN correctly via sort-key encoding.
- `SORT-NTH` is destructive — use `SIMD-COPY-N` first if you
  need to preserve the original array.
- For statistics use, prefer `STAT-MEDIAN` / `STAT-PERCENTILE`
  which handle the copy internally.
