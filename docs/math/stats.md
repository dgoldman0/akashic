# akashic-stats — Descriptive Statistics for FP16 Arrays

Descriptive statistics for FP16 arrays in HBW math RAM, using
the mixed-precision pipeline:

> FP16 data → tile reductions (FP32 per tile) → accum.f (48.16)
> → fp32.f arithmetic → FP16 output

```forth
REQUIRE stats.f
```

`PROVIDED akashic-stats` — auto-loads `fp16.f`, `fp16-ext.f`,
`fp32.f`, `accum.f`, `simd.f`, `simd-ext.f`, `sort.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Central Tendency](#central-tendency)
- [Dispersion & Spread](#dispersion--spread)
- [Shape & Percentiles](#shape--percentiles)
- [Bivariate](#bivariate)
- [Online / Streaming](#online--streaming)
- [Mixed-Precision Pipeline](#mixed-precision-pipeline)
- [Scratch Buffers](#scratch-buffers)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Mixed-precision** | FP16 inputs → tile reductions in hardware FP32 → 48.16 accumulation → software FP32 final arithmetic → FP16 output. Same precision as 32-bit float statistics on other platforms. |
| **Two-pass variance** | Numerically stable: compute mean first, then sum of squared deviations. Avoids catastrophic cancellation. |
| **Non-destructive** | `STAT-MEDIAN`, `STAT-PERCENTILE`, `STAT-QUARTILES`, and `STAT-FIVE-NUM` copy data to scratch buffers before sorting — the original array is preserved. |
| **Tile-accelerated** | All bulk operations (sum, sumsq, dot, min, max) dispatch through `simd-ext.f` for 32-lane-wide FP16 processing. |
| **Welford + Chan online** | `PUSH` uses Welford's algorithm (O(1) per observation). `PUSH-N` and `MERGE` use Chan's parallel algorithm for combining batch statistics. |
| **VARIABLE-based state** | Module-scoped VARIABLEs. Not re-entrant. |

---

## Central Tendency

### STAT-MEAN

```forth
STAT-MEAN  ( src n -- mean )
```

Arithmetic mean of *n* FP16 values at *src*.

**Algorithm:** `SIMD-SUM-N` → FP32 sum (via tile `TSUM` + `accum.f`),
then `FP32-DIV` by *n*, then `FP32>FP16`.

```forth
128 HBW-ALLOT CONSTANT data
data 15360 64 SIMD-FILL-N       \ fill 64 elements with 1.0
data 64 STAT-MEAN .              \ → 15360 (FP16 1.0)
```

### STAT-MEDIAN

```forth
STAT-MEDIAN  ( src n -- med )
```

Median of *n* FP16 values.  **Non-destructive** — copies data to
`_STAT-SCR0`, sorts the copy, then reads the middle element.

For even *n*, returns the average of the two middle elements
(via `FP16-ADD` / 2).  For odd *n*, returns `copy[n/2]`.

```forth
data 64 STAT-MEDIAN .           \ → FP16 median value
```

---

## Dispersion & Spread

### STAT-VARIANCE / STAT-VARIANCE-S

```forth
STAT-VARIANCE    ( src n -- var )    \ population (÷ n)
STAT-VARIANCE-S  ( src n -- var )    \ sample (÷ n−1, Bessel's correction)
```

Two-pass algorithm:

1. `_STAT-MEAN-FP32` → FP32 mean via SIMD-SUM-N
2. Fill `_STAT-SCR0` with FP16(mean), `SIMD-SUB-N` → deviations
3. `SIMD-SUMSQ-N` on deviations → FP32 sum of squares
4. `FP32-DIV` by *n* (or *n* − 1) → FP32 variance
5. `FP32>FP16` → FP16 output

### STAT-STDDEV / STAT-STDDEV-S

```forth
STAT-STDDEV    ( src n -- sd )      \ population
STAT-STDDEV-S  ( src n -- sd )      \ sample
```

Standard deviation = `FP32-SQRT` of variance, then `FP32>FP16`.

### STAT-SEM

```forth
STAT-SEM  ( src n -- sem )
```

Standard error of the mean: $\text{sd}_s / \sqrt{n}$.  Computes
sample stddev in FP32, divides by `FP32-SQRT(INT>FP32(n))`.

### STAT-MIN / STAT-MAX

```forth
STAT-MIN  ( src n -- min )
STAT-MAX  ( src n -- max )
```

Minimum / maximum via `SIMD-MIN-N` / `SIMD-MAX-N` — tile-accelerated
across all elements.

### STAT-RANGE

```forth
STAT-RANGE  ( src n -- range )
```

$\text{max} - \text{min}$ as FP16.  Calls `STAT-MAX` then `STAT-MIN`,
subtracts via `FP16-SUB`.

### STAT-ARGMIN / STAT-ARGMAX

```forth
STAT-ARGMIN  ( src n -- idx )
STAT-ARGMAX  ( src n -- idx )
```

Index (0-based) of the minimum / maximum element.  Linear scan
comparing each element against the running best via `FP16-LT` / `FP16-GT`.

```forth
data 64 STAT-ARGMIN .           \ → index of minimum
data 64 STAT-ARGMAX .           \ → index of maximum
```

---

## Shape & Percentiles

### STAT-PERCENTILE

```forth
STAT-PERCENTILE  ( src n p -- val )
```

*p*-th percentile (0–100) using nearest-rank method.  Copies to
scratch, sorts, indexes at $k = p \times n / 100$.

```forth
data 100 50 STAT-PERCENTILE .   \ → median
data 100 90 STAT-PERCENTILE .   \ → 90th percentile
```

### STAT-QUARTILES

```forth
STAT-QUARTILES  ( src n -- q1 q2 q3 )
```

All three quartiles in one call.  Sorts once, reads at 25%, 50%,
75% positions.

### STAT-FIVE-NUM

```forth
STAT-FIVE-NUM  ( src n -- min q1 med q3 max )
```

Five-number summary: minimum, Q1, median, Q3, maximum.  Sorts once,
reads all five positions.

```forth
data 100 STAT-FIVE-NUM
\ stack now has: min q1 med q3 max (all FP16)
```

---

## Bivariate

All bivariate words take two parallel FP16 arrays (*x* and *y*) of
equal length *n*.

### STAT-COVARIANCE

```forth
STAT-COVARIANCE  ( x y n -- cov )
```

Population covariance: $\frac{1}{n} \sum (x_i - \bar{x})(y_i - \bar{y})$.

**Algorithm:** Uses `_STAT-SXY` — computes means of *x* and *y*,
fills scratch with copies subtracted by respective means, then
`SIMD-DOT-N` on the deviation arrays → FP32 cross-product sum,
divide by *n*.

### STAT-CORRELATION

```forth
STAT-CORRELATION  ( x y n -- r )
```

Pearson correlation coefficient:
$r = \frac{S_{xy}}{\sqrt{S_{xx} \cdot S_{yy}}}$.

Three FP32 sums: $S_{xy}$ (cross-product of deviations), $S_{xx}$
and $S_{yy}$ (sum of squared deviations for each variable).
Final formula computed in software FP32 using `FP32-MUL`,
`FP32-SQRT`, `FP32-DIV`.

### STAT-COSINE-SIM

```forth
STAT-COSINE-SIM  ( x y n -- sim )
```

Cosine similarity: $\frac{\mathbf{x} \cdot \mathbf{y}}{||\mathbf{x}|| \cdot ||\mathbf{y}||}$.

Three tile passes: `SIMD-DOT-N` for numerator, `SIMD-SUMSQ-N`
× 2 for denominator norms.

### STAT-EUCLIDEAN

```forth
STAT-EUCLIDEAN  ( x y n -- dist )
```

Euclidean distance: $\sqrt{\sum (x_i - y_i)^2}$.

Copies *x* to scratch, `SIMD-SUB-N` (*y*), then `SIMD-SUMSQ-N`
on the differences, `FP32-SQRT`.

```forth
x-arr y-arr 64 STAT-CORRELATION .   \ Pearson r
x-arr y-arr 64 STAT-EUCLIDEAN .     \ L2 distance
```

---

## Online / Streaming

Context-based streaming statistics using Welford's online algorithm
for single observations and Chan's parallel algorithm for batches
and merges.

### Context Layout

Each context is 64 bytes (8 cells):

| Offset | Size | Field | Format | Description |
|---|---|---|---|---|
| +0 | 8 | n | 64-bit integer | Observation count |
| +8 | 8 | mean | FP32 (low 32 bits) | Running mean |
| +16 | 8 | M2 | FP32 | $\sum (x_i - \bar{x})^2$ |
| +24 | 8 | min | FP16 (low 16 bits) | Running minimum |
| +32 | 8 | max | FP16 (low 16 bits) | Running maximum |
| +40 | 8 | sum | 48.16 fixed-point | Running sum (for weighted variants) |
| +48 | 16 | — | reserved | — |

```forth
CREATE my-ctx STAT-ONLINE-SIZE ALLOT
my-ctx STAT-ONLINE-INIT
```

### Initialisation & Lifecycle

```forth
STAT-ONLINE-SIZE   ( -- 64 )           context size in bytes
STAT-ONLINE-INIT   ( ctx -- )          zero all fields, set min=+∞ max=−∞
STAT-ONLINE-RESET  ( ctx -- )          alias for INIT
```

### Adding Observations

#### STAT-ONLINE-PUSH

```forth
STAT-ONLINE-PUSH  ( ctx val -- )
```

Add one FP16 observation.  O(1).  Uses **Welford's algorithm**:

1. $n \leftarrow n + 1$
2. $\delta = x - \bar{x}$
3. $\bar{x} \leftarrow \bar{x} + \delta / n$
4. $\delta_2 = x - \bar{x}$ (using updated mean)
5. $M_2 \leftarrow M_2 + \delta \cdot \delta_2$

All intermediate values are FP32 for numerical stability.  Min/max
updated via `FP16-LT` / `FP16-GT`.

```forth
my-ctx 0x3C00 STAT-ONLINE-PUSH       \ push 1.0
my-ctx 0x4000 STAT-ONLINE-PUSH       \ push 2.0
my-ctx 0x4200 STAT-ONLINE-PUSH       \ push 3.0
```

#### STAT-ONLINE-PUSH-N

```forth
STAT-ONLINE-PUSH-N  ( ctx src n -- )
```

Add *n* FP16 observations from array at *src*.  Uses **Chan's
parallel algorithm**: compute batch mean, M2, min, max via SIMD
tile operations, then merge with existing context in O(1):

1. Batch mean via `SIMD-SUM-N` / *n*
2. Batch M2 via `_STAT-SS` (two-pass: mean, then sum-of-sq-dev)
3. Batch min/max via `SIMD-MIN-N` / `SIMD-MAX-N`
4. Merge: $\delta = \bar{x}_B - \bar{x}_A$,
   $M_{2_{new}} = M_{2_A} + M_{2_B} + \delta^2 \cdot \frac{n_A \cdot n_B}{n_A + n_B}$

```forth
my-ctx data 1000 STAT-ONLINE-PUSH-N  \ bulk push 1000 values
```

### Querying

```forth
STAT-ONLINE-COUNT     ( ctx -- n )         observation count
STAT-ONLINE-MEAN      ( ctx -- mean )      current mean (FP16)
STAT-ONLINE-VARIANCE  ( ctx -- var )       population variance (FP16)
STAT-ONLINE-STDDEV    ( ctx -- sd )        standard deviation (FP16)
STAT-ONLINE-MIN       ( ctx -- min )       running minimum (FP16)
STAT-ONLINE-MAX       ( ctx -- max )       running maximum (FP16)
```

Variance is computed on-the-fly from the stored M2: $\sigma^2 = M_2 / n$.

### Merging

```forth
STAT-ONLINE-MERGE  ( ctx1 ctx2 dst -- )
```

Merge two online contexts into *dst* using **Chan's parallel
algorithm**.  Enables multi-core or multi-batch statistics: split
data, compute per-batch, merge at the end.

```forth
CREATE ctx-a STAT-ONLINE-SIZE ALLOT   ctx-a STAT-ONLINE-INIT
CREATE ctx-b STAT-ONLINE-SIZE ALLOT   ctx-b STAT-ONLINE-INIT
CREATE ctx-m STAT-ONLINE-SIZE ALLOT

ctx-a data-a 500 STAT-ONLINE-PUSH-N
ctx-b data-b 500 STAT-ONLINE-PUSH-N
ctx-a ctx-b ctx-m STAT-ONLINE-MERGE
ctx-m STAT-ONLINE-MEAN .             \ mean of all 1000 values
```

---

## Mixed-Precision Pipeline

All statistics leverage the tile engine for FP16 reductions:

| Stage | Format | Precision | Operation |
|---|---|---|---|
| Input data | FP16 | 3.3 digits | Load into tiles |
| Tile reduction | FP32 (hardware) | 7.2 digits | `TSUM`, `TSUMSQ`, `TDOT`, `TMIN`, `TMAX` |
| Cross-tile accumulation | 48.16 (integer) | exact | `accum.f` running sum |
| Final arithmetic | FP32 (software) | 7.2 digits | `FP32-DIV`, `FP32-SQRT`, etc. |
| Output | FP16 | 3.3 digits | `FP32>FP16` narrow |

The 48.16 integer accumulation eliminates all rounding during the
most error-sensitive phase — summing hundreds of FP32 partial
results across tiles.

---

## Scratch Buffers

`stats.f` allocates two 4 KiB scratch buffers in HBW at module
load time:

| Buffer | Size | Purpose |
|---|---|---|
| `_STAT-SCR0` | 2048 × 2 bytes | Sorted copy (median, percentile), deviation array |
| `_STAT-SCR1` | 2048 × 2 bytes | Mean-broadcast fill, temporary |

Maximum array size per call: **2048 elements** (`_STAT-MAX-N`).
Buffers are reused by each call (not thread-safe, but KDOS is
single-threaded).

---

## Internals

### Internal Helpers

| Word | Stack | Description |
|---|---|---|
| `_STAT-MEAN-FP32` | `( src n -- mean-fp32 )` | Arithmetic mean as FP32 (for use by variance, correlation) |
| `_STAT-SS` | `( src n mean-fp32 -- ss-fp32 )` | Sum of squared deviations from given mean |
| `_STAT-SXY` | `( x y n -- sxy-fp32 )` | Cross-product of deviations: $\sum(x_i - \bar{x})(y_i - \bar{y})$ |

### Online Context Accessors

| Word | Stack | Description |
|---|---|---|
| `_SOL-N` | `( ctx -- addr )` | Address of count field |
| `_SOL-MEAN` | `( ctx -- addr )` | Address of mean field |
| `_SOL-M2` | `( ctx -- addr )` | Address of M2 field |
| `_SOL-MIN` | `( ctx -- addr )` | Address of min field |
| `_SOL-MAX` | `( ctx -- addr )` | Address of max field |
| `_SOL-SUM` | `( ctx -- addr )` | Address of sum field |

### Module Variables

| Variable | Purpose |
|---|---|
| `_STAT-SRC`, `_STAT-SRC2` | Source array addresses |
| `_STAT-N` | Element count |
| `_SARG-BEST`, `_SARG-IDX` | Running best value / index (ARGMIN/ARGMAX) |
| `_STAT-FP32-TMP` | FP32 temporary |
| `_SOL-CTX`, `_SOL-X32` | Online PUSH context / value |
| `_SOL-DELTA`, `_SOL-DELTA2` | Welford delta values |
| `_SPN-M2B`, `_SPN-MEANB` | PUSH-N batch M2 / mean |
| `_SPN-DELTA`, `_SPN-NNEW` | PUSH-N merge delta / combined count |
| `_SOM-DELTA`, `_SOM-NNEW` | MERGE delta / combined count |

### Constants

| Constant | Value | Description |
|---|---|---|
| `_STAT-MAX-N` | 2048 | Maximum elements per call |
| `STAT-ONLINE-SIZE` | 64 | Context size in bytes |

---

## Quick Reference

```
STAT-MEAN            ( src n -- mean )         arithmetic mean
STAT-MEDIAN          ( src n -- med )          median (non-destructive)

STAT-VARIANCE        ( src n -- var )          population variance
STAT-VARIANCE-S      ( src n -- var )          sample variance (n−1)
STAT-STDDEV          ( src n -- sd )           population stddev
STAT-STDDEV-S        ( src n -- sd )           sample stddev
STAT-SEM             ( src n -- sem )          standard error of mean
STAT-MIN             ( src n -- min )          minimum
STAT-MAX             ( src n -- max )          maximum
STAT-RANGE           ( src n -- range )        max − min
STAT-ARGMIN          ( src n -- idx )          index of minimum
STAT-ARGMAX          ( src n -- idx )          index of maximum

STAT-PERCENTILE      ( src n p -- val )        p-th percentile (0–100)
STAT-QUARTILES       ( src n -- q1 q2 q3 )    all three quartiles
STAT-FIVE-NUM        ( src n -- min q1 med q3 max )

STAT-COVARIANCE      ( x y n -- cov )         population covariance
STAT-CORRELATION     ( x y n -- r )           Pearson r
STAT-COSINE-SIM      ( x y n -- sim )         cosine similarity
STAT-EUCLIDEAN       ( x y n -- dist )        Euclidean distance

STAT-ONLINE-SIZE     ( -- 64 )                context size
STAT-ONLINE-INIT     ( ctx -- )               initialize
STAT-ONLINE-PUSH     ( ctx val -- )           add one (Welford)
STAT-ONLINE-PUSH-N   ( ctx src n -- )         add N (Chan)
STAT-ONLINE-MEAN     ( ctx -- mean )          current mean
STAT-ONLINE-VARIANCE ( ctx -- var )           current variance
STAT-ONLINE-STDDEV   ( ctx -- sd )            current stddev
STAT-ONLINE-COUNT    ( ctx -- n )             count
STAT-ONLINE-MIN      ( ctx -- min )           running min
STAT-ONLINE-MAX      ( ctx -- max )           running max
STAT-ONLINE-MERGE    ( ctx1 ctx2 dst -- )     merge contexts
STAT-ONLINE-RESET    ( ctx -- )               reset to empty
```

## Limitations

- Maximum array size per call: 2048 elements (scratch buffer limit).
- Median / percentile use full sort — O(*n* log *n*) for simplicity.
  For large arrays, consider `SORT-NTH` directly (O(*n*) average).
- Online M2 stored as FP32 — precision degrades after ~10⁵
  observations.  For larger datasets, use batch `PUSH-N` which
  reduces via tile accumulator before folding into Welford state.
- Not re-entrant (module-scoped VARIABLEs).
