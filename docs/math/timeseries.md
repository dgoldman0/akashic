# akashic-timeseries — Time Series Analysis

Time-ordered data analysis for FP16 arrays in HBW math RAM.
Moving averages, differencing, trend removal, autocorrelation,
anomaly detection — all with mixed-precision internals.

```forth
REQUIRE timeseries.f
```

`PROVIDED akashic-timeseries` — auto-loads `stats.f`, `regression.f`,
`exp.f` (and transitively `fp16.f`, `fp16-ext.f`, `fp32.f`, `accum.f`,
`simd.f`, `simd-ext.f`, `sort.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Smoothing & Moving Averages](#smoothing--moving-averages)
- [Differencing & Returns](#differencing--returns)
- [Trend & Seasonality](#trend--seasonality)
- [Anomaly Detection](#anomaly-detection)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Limitations](#limitations)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Mixed-precision** | FP16 input/output, FP32 intermediate accumulation (sliding sums, EMA state), FP16 final results. |
| **Expanding window** | Moving-average functions use an expanding window for the first few positions rather than dropping data or padding with zeros. |
| **SIMD where possible** | `TS-DIFF`, `TS-DETREND-MEAN`, `TS-ZSCORE`, `TS-LAG` use SIMD bulk operations.  Sequential ops (EMA, cumulative) use FP32 scalar accumulation. |
| **Scratch isolation** | `_TS-SCR` is a dedicated HBW buffer separate from `_STAT-SCR0`/`_STAT-SCR1`, preventing clobbering when calling `REG-OLS`, `STAT-*`. |
| **VARIABLE-based state** | All loops use module-scoped VARIABLEs — no locals, no return-stack tricks. |

---

## Smoothing & Moving Averages

### TS-SMA

```forth
TS-SMA  ( src n window dst -- )
```

Simple moving average with a sliding window.  For positions
$i < \text{window}$, an expanding window average is used:

$$\text{sma}[i] = \frac{1}{\min(i+1, w)} \sum_{j=\max(0, i-w+1)}^{i} x_j$$

**Algorithm:** O(n) sliding sum in FP32.  Add the new element,
subtract the departing one — constant work per position regardless
of window size.

```forth
CREATE dst 200 HBW-ALLOT
src 100 10 dst TS-SMA     \ 10-period SMA over 100 elements
```

### TS-EMA

```forth
TS-EMA  ( src n alpha dst -- )
```

Exponential moving average.  $\alpha$ is an FP16 value in $(0, 1)$.

$$y_0 = x_0, \quad y_t = \alpha \cdot x_t + (1 - \alpha) \cdot y_{t-1}$$

Sequential by nature (each output depends on the previous), but
$\alpha$ and $(1-\alpha)$ are computed once in FP32 and reused.

```forth
CREATE dst 200 HBW-ALLOT
src 100 0x3555 dst TS-EMA   \ alpha ≈ 0.333
```

### TS-EWMA

```forth
TS-EWMA  ( src n alpha -- last )
```

Same as `TS-EMA` but returns only the final value as FP16.
No destination buffer needed.

```forth
src 100 0x3800 TS-EWMA .   \ alpha = 0.5
```

### TS-WMA

```forth
TS-WMA  ( src n window dst -- )
```

Weighted moving average with linearly increasing weights.
Within a window of size $w$: weight $j = j + 1$ for $j = 0 \ldots w-1$.

$$\text{wma}[i] = \frac{\sum_{j=0}^{k-1} (j+1) \cdot x_{i-k+1+j}}{\sum_{j=0}^{k-1} (j+1)}$$

where $k = \min(i+1, w)$.  More recent observations have higher weight.

```forth
CREATE dst 200 HBW-ALLOT
src 100 5 dst TS-WMA     \ 5-period WMA
```

### TS-MEDIAN-FILTER

```forth
TS-MEDIAN-FILTER  ( src n window dst -- )
```

Running median filter.  For each position, extracts the window,
sorts it (via `SORT-FP16`), and takes the median.  Outlier-resistant
alternative to SMA.

For even-length windows, the median is the average of the two
middle elements.  Uses `_STAT-SCR0` as sort scratch.

```forth
CREATE dst 200 HBW-ALLOT
src 100 5 dst TS-MEDIAN-FILTER   \ 5-point median filter
```

---

## Differencing & Returns

### TS-DIFF

```forth
TS-DIFF  ( src n dst -- )
```

First differences: $\text{dst}[i] = \text{src}[i+1] - \text{src}[i]$.
Output has $n-1$ elements.  Uses `SIMD-SUB-N` for bulk subtraction.

```forth
CREATE dst 198 HBW-ALLOT
src 100 dst TS-DIFF     \ 99 first differences
```

### TS-DIFF-K

```forth
TS-DIFF-K  ( src n k dst -- )
```

$k$-th order differences.  Applies first-difference $k$ times.
Result has $n - k$ elements.  For $k = 0$, copies src to dst.

Uses `_STAT-SCR0` and `_STAT-SCR1` alternately as intermediate
scratch buffers.

```forth
CREATE dst 196 HBW-ALLOT
src 100 2 dst TS-DIFF-K   \ second-order differences (98 elements)
```

### TS-PCT-CHANGE

```forth
TS-PCT-CHANGE  ( src n dst -- )
```

Percentage change: $\text{dst}[i] = (x_{i+1} - x_i) / x_i$.
Output has $n-1$ elements.  Returns zero if $x_i = 0$.

```forth
prices 50 returns TS-PCT-CHANGE   \ 49 returns
```

### TS-LOG-RETURN

```forth
TS-LOG-RETURN  ( src n dst -- )
```

Logarithmic return: $\text{dst}[i] = \ln(x_{i+1} / x_i)$.
Output has $n-1$ elements.  Uses `FP16-DIV` and `EXP-LN`.
Returns zero if $x_i = 0$.

Log returns are additive across time periods (unlike percentage
returns), making them useful for multi-period analysis.

```forth
prices 50 log_ret TS-LOG-RETURN
```

### TS-CUMSUM

```forth
TS-CUMSUM  ( src n dst -- )
```

Cumulative sum: $\text{dst}[i] = \sum_{j=0}^{i} x_j$.
Accumulated in FP32 to avoid drift, narrowed to FP16 at each position.

```forth
increments 100 running_total TS-CUMSUM
```

### TS-CUMMIN / TS-CUMMAX

```forth
TS-CUMMIN  ( src n dst -- )
TS-CUMMAX  ( src n dst -- )
```

Cumulative minimum / maximum: $\text{dst}[i] = \min(x_0, \ldots, x_i)$
or $\max(x_0, \ldots, x_i)$.  Uses `FP16-MIN` / `FP16-MAX`.

---

## Trend & Seasonality

### TS-DETREND

```forth
TS-DETREND  ( src n dst -- )
```

Remove linear trend via OLS regression.  Constructs an index array
$[0, 1, 2, \ldots, n-1]$, fits $y = \beta_0 + \beta_1 \cdot i$ via
`REG-OLS`, then computes $\text{dst}[i] = \text{src}[i] - \hat{y}_i$.

For a perfectly linear series, all residuals are zero.  For $n < 2$,
copies src to dst unchanged.

Uses `_TS-SCR` for the index array (not `_STAT-SCR0`, which `REG-OLS`
clobbers internally).

```forth
CREATE detrended 200 HBW-ALLOT
sensor_data 100 detrended TS-DETREND
```

### TS-DETREND-MEAN

```forth
TS-DETREND-MEAN  ( src n dst -- )
```

Remove the mean (center the data): $\text{dst}[i] = x_i - \bar{x}$.
Uses `STAT-MEAN`, `SIMD-FILL-N`, and `SIMD-SUB-N`.

```forth
data 100 centered TS-DETREND-MEAN
```

### TS-AUTOCORR

```forth
TS-AUTOCORR  ( src n lag -- r )
```

Autocorrelation at a given lag:

$$r(\text{lag}) = \frac{\text{Cov}(x_{0 \ldots n-\ell-1}, \, x_{\ell \ldots n-1})}{\text{Var}(x)}$$

Returns FP16.  $r(0) = 1.0$ by definition.  Returns 0 for
$\text{lag} \geq n$.

```forth
data 100 1 TS-AUTOCORR .    \ lag-1 autocorrelation
```

### TS-AUTOCORR-N

```forth
TS-AUTOCORR-N  ( src n max-lag dst -- )
```

Compute the autocorrelation function for lags $0, 1, \ldots, \text{max-lag}$.
Writes $\text{max-lag} + 1$ FP16 values to *dst*.

```forth
CREATE acf 42 HBW-ALLOT   \ 21 lags × 2 bytes
data 100 20 acf TS-AUTOCORR-N
```

### TS-LAG

```forth
TS-LAG  ( src n k dst -- )
```

Lag operator: $\text{dst}[i] = x_{i-k}$ for $i \geq k$, zero-padded
for $i < k$.  Output has $n$ elements.  Uses `SIMD-COPY-N` for the
shifted portion and `SIMD-ZERO-N` for the padding.

```forth
data 100 3 lagged TS-LAG   \ shift by 3 positions
```

### TS-ROLLING-STD

```forth
TS-ROLLING-STD  ( src n window dst -- )
```

Rolling standard deviation (population) over a trailing window.
For each position, calls `STAT-STDDEV` on the effective window.
Positions with only 1 element produce 0.

```forth
data 100 10 roll_std TS-ROLLING-STD
```

### TS-DRAWDOWN

```forth
TS-DRAWDOWN  ( src n dst -- )
```

Drawdown from running maximum:

$$\text{dd}[i] = \frac{\text{cummax}[i] - x_i}{\text{cummax}[i]}$$

Returns FP16 values in $[0, 1]$.  Zero when the series is at a
new high.

```forth
prices 100 dd TS-DRAWDOWN
```

### TS-MAX-DRAWDOWN

```forth
TS-MAX-DRAWDOWN  ( src n -- mdd )
```

Maximum drawdown — the largest peak-to-trough decline as a fraction.
Single FP16 result, no destination buffer needed.

```forth
prices 100 TS-MAX-DRAWDOWN .   \ e.g. 0.133 = 13.3% max drawdown
```

---

## Anomaly Detection

### TS-ZSCORE

```forth
TS-ZSCORE  ( src n dst -- )
```

Z-score normalization: $z_i = (x_i - \bar{x}) / \sigma$.  Computed
with `STAT-MEAN` and `STAT-STDDEV`, then SIMD broadcast subtract
and scale by $1/\sigma$ via `FP16-RECIP` + `SIMD-SCALE-N`.

If $\sigma = 0$ (constant series), all z-scores are set to 0.
Requires $n \geq 2$.

```forth
data 100 zscores TS-ZSCORE
```

### TS-OUTLIERS-IQR

```forth
TS-OUTLIERS-IQR  ( src n dst -- m )
```

Flag outliers using the IQR rule.  An outlier is any value
$x_i < Q_1 - 1.5 \cdot \text{IQR}$ or $x_i > Q_3 + 1.5 \cdot \text{IQR}$.

- *dst*: FP16 array where 1.0 = outlier, 0.0 = normal.
- Returns *m* = total outlier count.
- Requires $n \geq 4$ (needs meaningful quartiles).

```forth
data 100 flags TS-OUTLIERS-IQR .   \ prints outlier count
```

### TS-OUTLIERS-Z

```forth
TS-OUTLIERS-Z  ( src n threshold dst -- m )
```

Flag outliers by z-score.  $|z_i| > \text{threshold}$ → outlier.
Common thresholds: 2.0 (≈5% false positive), 3.0 (≈0.3%).

- *threshold*: FP16 value (e.g., `0x4000` = 2.0, `0x4200` = 3.0).
- *dst*: FP16 array where 1.0 = outlier, 0.0 = normal.
- Returns *m* = total outlier count.

```forth
data 100 0x4000 flags TS-OUTLIERS-Z .   \ z-score > 2.0
```

---

## Internals

### Module Variables

| Variable | Purpose |
|---|---|
| `_TS-SRC` | Source array pointer |
| `_TS-DST` | Destination array pointer |
| `_TS-N` | Element count |
| `_TS-WIN` | Window size |
| `_TS-K` | Order / lag / general counter |
| `_TS-I` | Loop index |
| `_TS-J` | Inner loop index |
| `_TS-ACC` | FP32 accumulator |
| `_TS-ACC2` | Second FP32 accumulator |
| `_TS-MEAN` | FP32 mean value |
| `_TS-VAL` | Temporary FP16 value |

### Scratch Buffers

| Buffer | Owner | Purpose |
|---|---|---|
| `_TS-SCR` | timeseries.f | Index array for `TS-DETREND` |
| `_STAT-SCR0` | stats.f (shared) | Sort scratch for `TS-MEDIAN-FILTER`, diff-k intermediates |
| `_STAT-SCR1` | stats.f (shared) | Diff-k intermediates, z-score scratch |

Maximum array size per call: 2048 elements (`_STAT-MAX-N`).

### Regression Context

`_TS-REG-CTX` is a module-level 64-byte context used by `TS-DETREND`
for the internal `REG-OLS` call.

---

## Quick Reference

```
TS-SMA            ( src n window dst -- )     simple moving average
TS-EMA            ( src n alpha dst -- )       exponential moving average
TS-EWMA           ( src n alpha -- last )      EWMA → single value
TS-WMA            ( src n window dst -- )       weighted moving average
TS-MEDIAN-FILTER  ( src n window dst -- )       running median

TS-DIFF           ( src n dst -- )              first differences (n-1 out)
TS-DIFF-K         ( src n k dst -- )            k-th order differences
TS-PCT-CHANGE     ( src n dst -- )              percentage change (n-1 out)
TS-LOG-RETURN     ( src n dst -- )              log return (n-1 out)
TS-CUMSUM         ( src n dst -- )              cumulative sum
TS-CUMMIN         ( src n dst -- )              cumulative minimum
TS-CUMMAX         ( src n dst -- )              cumulative maximum

TS-DETREND        ( src n dst -- )              remove linear trend
TS-DETREND-MEAN   ( src n dst -- )              remove mean (center)
TS-AUTOCORR       ( src n lag -- r )            autocorrelation at lag
TS-AUTOCORR-N     ( src n max-lag dst -- )      ACF for lags 0..max-lag
TS-LAG            ( src n k dst -- )            lag operator (shift by k)
TS-ROLLING-STD    ( src n window dst -- )        rolling stddev
TS-DRAWDOWN       ( src n dst -- )              drawdown from running max
TS-MAX-DRAWDOWN   ( src n -- mdd )              maximum drawdown

TS-ZSCORE         ( src n dst -- )              z-score normalization
TS-OUTLIERS-IQR   ( src n dst -- m )            flag outliers (IQR rule)
TS-OUTLIERS-Z     ( src n threshold dst -- m )  flag outliers (z-score)
```

---

## Limitations

- Maximum array size per call: 2048 elements (stats.f scratch limit).
- EMA/EWMA are inherently sequential — no SIMD speedup for the
  recurrence itself (the multiply-add per step is single-element).
- `TS-MEDIAN-FILTER` is O(n × w log w) — sorts each window.  For
  very large windows on large arrays, this can be slow.
- `TS-ROLLING-STD` calls `STAT-STDDEV` per position — O(n × w).
  A sliding variance algorithm would be O(n) but adds complexity.
- `TS-AUTOCORR` computes variance of the full series on every call.
  Use `TS-AUTOCORR-N` for multiple lags to amortize the variance
  computation... except the current implementation calls `TS-AUTOCORR`
  per lag, so there is no amortization yet.
- Not re-entrant (module-scoped VARIABLEs).
