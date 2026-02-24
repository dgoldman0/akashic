# akashic-sort — Sorting & Rank Operations for FP16 Arrays

In-place sorting and selection primitives for FP16 arrays stored in
HBW math RAM.  Underpins the entire stats suite — median, percentile,
quartiles, and IQR all depend on sorted data.

```forth
REQUIRE sort.f
```

`PROVIDED akashic-sort` — auto-loads `fp16.f`, `fp16-ext.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Sorting](#sorting)
- [Selection](#selection)
- [Utilities](#utilities)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **In-place** | All operations modify the array directly — no auxiliary buffer needed. |
| **FP16 sort-key encoding** | Comparisons via `_FP16-SORTKEY` (from `fp16-ext.f`) convert sign-magnitude FP16 to integer-comparable encoding. Handles ±0, ±∞, NaN correctly. |
| **Shell sort** | Knuth gap sequence (3*h* + 1) gives O(*n*^1.5) average — good balance of simplicity, cache behaviour, and in-place operation for arrays up to several thousand elements. |
| **Iterative quickselect** | Lomuto partition avoids recursion (no return stack pressure). O(*n*) average for *k*-th order statistic. |
| **VARIABLE-based state** | Module-scoped VARIABLEs for loop counters and temporaries. Not re-entrant. |

---

## Sorting

### SORT-FP16

```forth
SORT-FP16  ( addr n -- )
```

In-place ascending sort of *n* FP16 values starting at *addr*.

**Algorithm:** Shell sort with Knuth's gap sequence
(*h* = 3*h* + 1 → 1, 4, 13, 40, 121, 364, 1093, …).

1. Find the largest gap ≤ *n*/3 by tripling from 1.
2. For each gap *h*, perform gapped insertion sort: compare
   element[*i*] with element[*i* − *h*], sliding elements right
   until the correct position is found.
3. Shrink gap by dividing by 3 and repeat until gap = 0.

Complexity: O(*n*^1.5) average, O(*n*²) worst case.

```forth
20 HBW-ALLOT CONSTANT my-arr
\ ... fill my-arr with 10 FP16 values ...
my-arr 10 SORT-FP16
my-arr 10 SORT-IS-SORTED? .   \ → -1  (true)
```

### SORT-FP16-DESC

```forth
SORT-FP16-DESC  ( addr n -- )
```

In-place descending sort.  Calls `SORT-FP16` then `SORT-REVERSE`.

```forth
my-arr 10 SORT-FP16-DESC
\ my-arr[0] is now the maximum, my-arr[9] the minimum
```

---

## Selection

### SORT-NTH

```forth
SORT-NTH  ( addr n k -- val )
```

Return the *k*-th smallest element (0-based) from *n* FP16 values
starting at *addr*.  **Destructive** — rearranges the array.

**Algorithm:** Iterative quickselect with Lomuto partition.

1. Choose the last element as pivot.
2. Partition into [≤ pivot | > pivot] using a single scan.
3. If the pivot's final position = *k*, return it.
4. Otherwise narrow the search to the left or right sub-range
   and repeat (iterative — no recursion).

Complexity: O(*n*) average, O(*n*²) worst case (rare with
non-adversarial data).

```forth
\ Find the median of 9 values (middle element = index 4)
\ WARNING: rearranges the array!
my-arr 9 4 SORT-NTH   \ → FP16 value

\ For non-destructive selection, copy first:
my-arr _STAT-SCR0 18 SIMD-COPY-N   \ copy 9×2=18 bytes
_STAT-SCR0 9 4 SORT-NTH
```

---

## Utilities

### SORT-IS-SORTED?

```forth
SORT-IS-SORTED?  ( addr n -- flag )
```

Return −1 (true) if the *n* FP16 values at *addr* are in ascending
order, 0 (false) otherwise.  Linear scan using `FP16-LT`.

```forth
my-arr 10 SORT-FP16
my-arr 10 SORT-IS-SORTED? .   \ → -1
```

### SORT-REVERSE

```forth
SORT-REVERSE  ( addr n -- )
```

Reverse *n* FP16 values in-place.  Swaps element[0] ↔ element[*n*−1],
element[1] ↔ element[*n*−2], etc.

```forth
my-arr 10 SORT-REVERSE
\ first element is now what was last, and vice versa
```

---

## Internals

### Shell Sort Variables

| Variable | Purpose |
|---|---|
| `_SH-BASE` | Base address of array being sorted |
| `_SH-LEN` | Number of elements |
| `_SH-GAP` | Current gap in the gap sequence |
| `_SH-KEY` | Value being inserted (inner loop) |
| `_SH-J` | Comparison index (inner loop) |

### Quickselect Variables

| Variable | Purpose |
|---|---|
| `_QS-BASE` | Base address of array |
| `_QS-LO` | Left bound of active sub-range |
| `_QS-HI` | Right bound of active sub-range |
| `_QS-K` | Target rank (0-based) |
| `_QS-I` | Scan index during Lomuto partition |
| `_QS-PIVOT-VAL` | Pivot value (FP16) |

### Internal Helpers

| Word | Stack | Description |
|---|---|---|
| `_SORT-SWAP` | `( addr1 addr2 -- )` | Swap two 16-bit values at HBW addresses |
| `_QS-ELEM` | `( idx -- val )` | Read element[idx] from `_QS-BASE` |
| `_QS-SWAP-IDX` | `( i j -- )` | Swap elements at indices *i* and *j* |
| `_QS-PARTITION` | `( lo hi -- pivot-pos )` | Lomuto partition around last element |

---

## Quick Reference

```
SORT-FP16        ( addr n -- )           Shell sort, ascending, O(n^1.5)
SORT-FP16-DESC   ( addr n -- )           sort + reverse
SORT-NTH         ( addr n k -- val )     k-th smallest (destructive), O(n)
SORT-IS-SORTED?  ( addr n -- flag )      check ascending order
SORT-REVERSE     ( addr n -- )           reverse in-place
```

## Limitations

- Shell sort is O(*n*^1.5) average — not O(*n* log *n*).  Adequate for
  the typical stats use case (≤ 2048 elements via scratch buffers).
- `SORT-NTH` is destructive — it rearranges the array.  Use
  `SIMD-COPY-N` to preserve the original, or use `STAT-MEDIAN` /
  `STAT-PERCENTILE` which handle the copy internally.
- Not stable — equal elements may be reordered.
- Not re-entrant (module-scoped VARIABLEs).
