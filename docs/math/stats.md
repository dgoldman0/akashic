# stats.f — Descriptive Statistics

**Module:** `math/stats.f`
**Prefix:** `STAT-`
**Depends on:** `fp16.f`, `fp16-ext.f`, `fp32.f`, `accum.f`,
`simd.f`, `simd-ext.f`, `sort.f`

Descriptive statistics for FP16 arrays in HBW math RAM, using
the mixed-precision pipeline:

> FP16 data → tile reductions (FP32 per tile) → accum.f (48.16)
> → fp32.f arithmetic → FP16 output

## API Reference

### Central Tendency

| Word | Stack | Description |
|---|---|---|
| `STAT-MEAN` | `( src n -- mean )` | Arithmetic mean (SIMD-SUM-N / *n*) |
| `STAT-MEDIAN` | `( src n -- med )` | Median (non-destructive, sort-based) |

### Dispersion & Spread

| Word | Stack | Description |
|---|---|---|
| `STAT-VARIANCE` | `( src n -- var )` | Population variance (two-pass) |
| `STAT-VARIANCE-S` | `( src n -- var )` | Sample variance (*n* − 1) |
| `STAT-STDDEV` | `( src n -- sd )` | Population standard deviation |
| `STAT-STDDEV-S` | `( src n -- sd )` | Sample standard deviation |
| `STAT-SEM` | `( src n -- sem )` | Standard error of the mean |
| `STAT-MIN` | `( src n -- min )` | Minimum (tile-accelerated) |
| `STAT-MAX` | `( src n -- max )` | Maximum (tile-accelerated) |
| `STAT-RANGE` | `( src n -- range )` | max − min |
| `STAT-ARGMIN` | `( src n -- idx )` | Index of minimum |
| `STAT-ARGMAX` | `( src n -- idx )` | Index of maximum |

### Shape & Percentiles

| Word | Stack | Description |
|---|---|---|
| `STAT-PERCENTILE` | `( src n p -- val )` | *p*-th percentile (0–100) |
| `STAT-QUARTILES` | `( src n -- q1 q2 q3 )` | All three quartiles |
| `STAT-FIVE-NUM` | `( src n -- min q1 med q3 max )` | Five-number summary |

### Bivariate

| Word | Stack | Description |
|---|---|---|
| `STAT-COVARIANCE` | `( x y n -- cov )` | Population covariance |
| `STAT-CORRELATION` | `( x y n -- r )` | Pearson correlation coefficient |
| `STAT-COSINE-SIM` | `( x y n -- sim )` | Cosine similarity |
| `STAT-EUCLIDEAN` | `( x y n -- dist )` | Euclidean distance |

### Online / Streaming (Welford + Chan)

| Word | Stack | Description |
|---|---|---|
| `STAT-ONLINE-SIZE` | `( -- 64 )` | Context size in bytes |
| `STAT-ONLINE-INIT` | `( ctx -- )` | Initialize context |
| `STAT-ONLINE-PUSH` | `( ctx val -- )` | Add one FP16 observation |
| `STAT-ONLINE-PUSH-N` | `( ctx src n -- )` | Add *N* observations (SIMD-accelerated, Chan's algorithm) |
| `STAT-ONLINE-MEAN` | `( ctx -- mean )` | Current mean |
| `STAT-ONLINE-VARIANCE` | `( ctx -- var )` | Current population variance |
| `STAT-ONLINE-STDDEV` | `( ctx -- sd )` | Current standard deviation |
| `STAT-ONLINE-COUNT` | `( ctx -- n )` | Number of observations |
| `STAT-ONLINE-MIN` | `( ctx -- min )` | Running minimum |
| `STAT-ONLINE-MAX` | `( ctx -- max )` | Running maximum |
| `STAT-ONLINE-MERGE` | `( ctx1 ctx2 dst -- )` | Merge two contexts |
| `STAT-ONLINE-RESET` | `( ctx -- )` | Reset to empty |

## Online Context Layout

| Offset | Size | Field | Format |
|---|---|---|---|
| +0 | 8 | n | 64-bit integer |
| +8 | 8 | mean | FP32 (low 32 bits) |
| +16 | 8 | M2 | FP32 (Σ(xi − mean)²) |
| +24 | 8 | min | FP16 (low 16 bits) |
| +32 | 8 | max | FP16 (low 16 bits) |
| +40 | 8 | sum | 48.16 fixed-point |
| +48 | 16 | reserved | — |

## Mixed-Precision Pipeline

All statistics leverage the tile engine for FP16 reductions:

1. **SIMD-SUM-N** → FP32 sum (via tile `TSUM` + `accum.f`)
2. **SIMD-SUMSQ-N** → FP32 sum-of-squares
3. **SIMD-DOT-N** → FP32 dot product
4. **SIMD-MIN-N / SIMD-MAX-N** → FP16 extrema

Final arithmetic (division, square root) is done in software
FP32 (`fp32.f`), then narrowed to FP16 for output.

### Variance (two-pass algorithm)

1. Pass 1: `_STAT-MEAN-FP32` via SIMD-SUM-N
2. Fill scratch with FP16(mean), `SIMD-SUB-N` → deviations
3. Pass 2: `SIMD-SUMSQ-N` → sum of squared deviations (FP32)
4. FP32-DIV by *n* (or *n* − 1 for sample)
5. FP32>FP16

### Welford's Online Algorithm

Each `PUSH` updates in O(1):
- δ = x − mean
- mean += δ / n
- δ₂ = x − mean (updated)
- M2 += δ · δ₂

All intermediate values are FP32 for stability.

`PUSH-N` uses Chan's parallel algorithm: compute batch
statistics (mean, M2 via SIMD), then merge in O(1).

## Examples

```forth
\ Basic descriptive stats
128 HBW-ALLOT CONSTANT data
data 15360 64 SIMD-FILL-N       \ fill 64 elements with 1.0

data 64 STAT-MEAN .              \ → 15360 (FP16 for 1.0)
data 64 STAT-STDDEV .            \ → 0

\ Online streaming stats
CREATE ctx STAT-ONLINE-SIZE ALLOT
ctx STAT-ONLINE-INIT
ctx 15360 STAT-ONLINE-PUSH       \ push 1.0
ctx 16384 STAT-ONLINE-PUSH       \ push 2.0
ctx 16896 STAT-ONLINE-PUSH       \ push 3.0
ctx STAT-ONLINE-MEAN .           \ → FP16 for 2.0
ctx STAT-ONLINE-COUNT .          \ → 3
```

## Scratch Buffers

`stats.f` allocates two 4 KiB scratch buffers in HBW at load
time (`_STAT-SCR0`, `_STAT-SCR1`), limiting per-call data size
to 2048 elements.  These are reused by each call (not
thread-safe, but KDOS is single-threaded).

## Limitations

- Maximum array size per call: 2048 elements
- Median / percentile use full sort (not quickselect) —
  O(*n* log *n*) for simplicity
- Online M2 stored as FP32 — precision degrades after
  ~10⁵ observations; for larger datasets, use batch
  `PUSH-N` which reduces via tile accumulator
