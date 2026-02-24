# akashic-regression — Simple Linear Regression (OLS)

Ordinary least squares linear regression for FP16 data arrays
in HBW math RAM, with mixed-precision internals.  Fits
$y = \beta_0 + \beta_1 x$, computes goodness-of-fit metrics, and
provides tile-accelerated batch prediction and residual computation.

```forth
REQUIRE regression.f
```

`PROVIDED akashic-regression` — auto-loads `stats.f` (and transitively
`fp16.f`, `fp16-ext.f`, `fp32.f`, `accum.f`, `simd.f`, `simd-ext.f`,
`sort.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Regression Context](#regression-context)
- [Fitting](#fitting)
- [Coefficient Accessors](#coefficient-accessors)
- [Prediction](#prediction)
- [Diagnostics](#diagnostics)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Mixed-precision** | FP16 input → tile-accelerated deviations and sums (FP32) → software FP32 coefficient arithmetic → FP16 output.  Slope, intercept, and R² are stored internally as FP32 for precision. |
| **Five tile passes** | `REG-OLS` performs exactly five SIMD passes: two `SIMD-FILL-N` + `SIMD-SUB-N` for deviations, then `SIMD-SUMSQ-N` × 2 + `SIMD-DOT-N` × 1 for the three sums.  All coefficient computation is then pure FP32 scalar math. |
| **Context-based** | Results stored in a 64-byte context struct.  Multiple regressions can coexist by allocating separate contexts. |
| **SIMD batch ops** | `REG-PREDICT-N` and `REG-RESIDUALS` use `SIMD-SAXPY-N` and `SIMD-SUB-N` — no scalar loops. |
| **VARIABLE-based state** | Module-scoped VARIABLEs for temporaries.  Not re-entrant. |

---

## Regression Context

Each context is 64 bytes (8 cells), allocated by the caller:

```forth
CREATE my-ctx REG-CTX-SIZE ALLOT
```

| Offset | Size | Field | Format | Description |
|---|---|---|---|---|
| +0 | 8 | n | 64-bit integer | Observation count |
| +8 | 8 | slope | FP32 | $\beta_1$ coefficient |
| +16 | 8 | intercept | FP32 | $\beta_0$ coefficient |
| +24 | 8 | r\_squared | FP32 | $R^2$ — coefficient of determination |
| +32 | 8 | sse | FP32 | Sum of squared errors $\sum(y_i - \hat{y}_i)^2$ |
| +40 | 8 | sst | FP32 | Total sum of squares $\sum(y_i - \bar{y})^2$ |
| +48 | 8 | x\_mean | FP32 | $\bar{x}$ — cached for predictions |
| +56 | 8 | y\_mean | FP32 | $\bar{y}$ |

`REG-CTX-SIZE` is a constant equal to 64.

---

## Fitting

### REG-OLS

```forth
REG-OLS  ( x y n ctx -- )
```

Fit an ordinary least squares regression $y = \beta_0 + \beta_1 x$
on *n* paired FP16 observations.

**Algorithm (mixed-precision):**

1. Compute $\bar{x}$ and $\bar{y}$ via `SIMD-SUM-N` → FP32 sum / *n*.
2. Compute deviation arrays in scratch:
   $dx_i = x_i - \bar{x}$, $dy_i = y_i - \bar{y}$
   using `SIMD-FILL-N` + `SIMD-SUB-N`.
3. Three tile reductions:
   - $S_{xx} = \sum dx_i^2$ via `SIMD-SUMSQ-N`
   - $S_{xy} = \sum dx_i \cdot dy_i$ via `SIMD-DOT-N`
   - $S_{yy} = \sum dy_i^2$ via `SIMD-SUMSQ-N`
4. Coefficients in software FP32:
   - $\beta_1 = S_{xy} / S_{xx}$
   - $\beta_0 = \bar{y} - \beta_1 \bar{x}$
   - $R^2 = S_{xy}^2 / (S_{xx} \cdot S_{yy})$
   - $SSE = S_{yy} - \beta_1 \cdot S_{xy}$
   - $SST = S_{yy}$

**Edge cases:**
- $n < 2$: slope = 0, intercept = $y_0$ (or 0 if $n = 0$), $R^2 = 0$.
- $S_{xx} = 0$ (all $x$ identical): slope = 0, intercept = $\bar{y}$, $R^2 = 0$.

```forth
CREATE ctx REG-CTX-SIZE ALLOT
x-arr y-arr 50 ctx REG-OLS
ctx REG-SLOPE .          \ → FP16 slope
ctx REG-R-SQUARED .      \ → FP16 R²
```

---

## Coefficient Accessors

All accessors read from a fitted context and return FP16.

### REG-SLOPE

```forth
REG-SLOPE  ( ctx -- slope )
```

Return $\beta_1$ as FP16.

### REG-INTERCEPT

```forth
REG-INTERCEPT  ( ctx -- intercept )
```

Return $\beta_0$ as FP16.

### REG-R-SQUARED

```forth
REG-R-SQUARED  ( ctx -- r2 )
```

Coefficient of determination $R^2 \in [0, 1]$.  Values near 1.0
indicate a strong linear fit.  Stored internally as FP32 for
precision (FP16 can't distinguish 0.98 from 0.99).

### REG-ADJ-R-SQUARED

```forth
REG-ADJ-R-SQUARED  ( ctx -- r2adj )
```

Adjusted $R^2$ penalized for number of predictors:

$$R^2_{adj} = 1 - \frac{(1 - R^2)(n - 1)}{n - 2}$$

Returns 0 for $n < 3$ (insufficient degrees of freedom).

---

## Prediction

### REG-PREDICT

```forth
REG-PREDICT  ( ctx x -- y-hat )
```

Predict $\hat{y} = \beta_1 x + \beta_0$ for a single FP16 value.
Internal computation in FP32; result narrowed to FP16.

```forth
ctx 0x4500 REG-PREDICT .   \ predict at x = 5.0
```

### REG-PREDICT-N

```forth
REG-PREDICT-N  ( ctx x-src dst n -- )
```

Batch predict *n* values.  Tile-accelerated via `SIMD-SAXPY-N`:
$\hat{y}_i = \text{slope} \cdot x_i + \text{intercept}$.

Two SIMD passes: one `SIMD-FILL-N` (broadcast intercept) and one
`SIMD-SAXPY-N` (fused scale + add).

```forth
x-arr pred-arr 100 ctx SWAP ROT ROT 100 REG-PREDICT-N
```

### REG-RESIDUALS

```forth
REG-RESIDUALS  ( ctx x y dst n -- )
```

Compute residuals $e_i = y_i - \hat{y}_i$ and store at *dst*.
Calls `REG-PREDICT-N` internally, then `SIMD-SUB-N`.

```forth
CREATE residuals 200 ALLOT  \ 100 × 2 bytes
ctx x-arr y-arr residuals 100 REG-RESIDUALS
```

---

## Diagnostics

### REG-SSE / REG-SSR / REG-SST

```forth
REG-SSE  ( ctx -- sse )     \ sum of squared errors
REG-SSR  ( ctx -- ssr )     \ sum of squared regression
REG-SST  ( ctx -- sst )     \ total sum of squares
```

All return FP16.  The relationship $SST = SSE + SSR$ holds
(up to FP16 rounding).

- **SSE** = $\sum(y_i - \hat{y}_i)^2$ — unexplained variance.
- **SSR** = $SST - SSE$ — variance explained by the model.
- **SST** = $\sum(y_i - \bar{y})^2$ — total variance.

### REG-RMSE

```forth
REG-RMSE  ( ctx -- rmse )
```

Root mean squared error = $\sqrt{SSE / n}$.  Computed in FP32
from stored SSE and *n*, then narrowed to FP16.

### REG-MAE

```forth
REG-MAE  ( ctx x y n -- mae )
```

Mean absolute error = $\frac{1}{n} \sum |y_i - \hat{y}_i|$.
Requires the original data arrays because absolute deviations
can't be derived from stored sums.

**Algorithm:**
1. `REG-PREDICT-N` → predictions in scratch
2. `SIMD-SUB-N` → residuals
3. `SIMD-ABS-N` → absolute residuals
4. `SIMD-SUM-N` / *n* → FP16 result

```forth
ctx x-arr y-arr 50 REG-MAE .   \ → FP16 mean absolute error
```

---

## Internals

### Module Variables

| Variable | Purpose |
|---|---|
| `_RG-CTX` | Current context pointer |
| `_RG-X` | X-array pointer |
| `_RG-Y` | Y-array pointer |
| `_RG-NN` | Observation count |
| `_RG-DST` | Destination buffer pointer |
| `_RG-SXX` | $S_{xx}$ intermediate (FP32) |
| `_RG-SXY` | $S_{xy}$ intermediate (FP32) |
| `_RG-SYY` | $S_{yy}$ intermediate (FP32) |

### Context Field Accessors

| Word | Stack | Offset |
|---|---|---|
| `_RG-N` | `( ctx -- ctx )` | +0 (no-op) |
| `_RG-SLP` | `( ctx -- ctx+8 )` | +8 |
| `_RG-INT` | `( ctx -- ctx+16 )` | +16 |
| `_RG-R2` | `( ctx -- ctx+24 )` | +24 |
| `_RG-SSE` | `( ctx -- ctx+32 )` | +32 |
| `_RG-SST` | `( ctx -- ctx+40 )` | +40 |
| `_RG-XM` | `( ctx -- ctx+48 )` | +48 |
| `_RG-YM` | `( ctx -- ctx+56 )` | +56 |

### Scratch Buffer Usage

`REG-OLS` uses both `_STAT-SCR0` and `_STAT-SCR1` (from `stats.f`)
for deviation arrays.  `REG-PREDICT-N` uses `_STAT-SCR0` for the
intercept broadcast.  `REG-MAE` uses `_STAT-SCR1` for predictions.
Maximum array size: 2048 elements (`_STAT-MAX-N`).

---

## Quick Reference

```
REG-CTX-SIZE      ( -- 64 )              context size in bytes
REG-OLS           ( x y n ctx -- )       ordinary least squares fit
REG-SLOPE         ( ctx -- slope )       beta1 as FP16
REG-INTERCEPT     ( ctx -- intercept )   beta0 as FP16
REG-R-SQUARED     ( ctx -- r2 )         R-squared as FP16
REG-ADJ-R-SQUARED ( ctx -- r2adj )      adjusted R-squared as FP16
REG-PREDICT       ( ctx x -- y-hat )    predict one value
REG-PREDICT-N     ( ctx x-src dst n -- ) batch predict (SIMD)
REG-RESIDUALS     ( ctx x y dst n -- )  residuals to dst
REG-SSE           ( ctx -- sse )        sum of squared errors
REG-SSR           ( ctx -- ssr )        sum of squared regression
REG-SST           ( ctx -- sst )        total sum of squares
REG-RMSE          ( ctx -- rmse )       root mean squared error
REG-MAE           ( ctx x y n -- mae )  mean absolute error
```

## Limitations

- Simple linear regression only — polynomial, exponential, and robust
  fitting are planned but not yet implemented.
- Maximum array size per call: 2048 elements (stats.f scratch limit).
- $R^2$ stored as FP32 internally but returned as FP16 — values
  like 0.98 and 0.99 are distinguishable in FP32 but may alias
  in FP16 output.
- Adjusted $R^2$ returns 0 for $n < 3$ (insufficient degrees of
  freedom for meaningful adjustment).
- Not re-entrant (module-scoped VARIABLEs).
