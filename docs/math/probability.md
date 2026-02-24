# akashic-probability — Probability Distributions & Hypothesis Testing

Probability density/mass functions, cumulative distribution functions,
hypothesis tests, and confidence intervals for FP16 data on
Megapad-64 / KDOS.  All computations use mixed-precision internals
(FP16 input → FP32 arithmetic → FP16 output).

```forth
REQUIRE probability.f
```

`PROVIDED akashic-probability` — auto-loads `stats.f`, `exp.f`,
`trig.f`, `counting.f` (and transitively `fp16.f`, `fp16-ext.f`,
`fp32.f`, `accum.f`, `simd.f`, `simd-ext.f`, `sort.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Distribution Functions](#distribution-functions)
  - [Standard Normal PDF](#prob-standard-pdf)
  - [Standard Normal CDF](#prob-standard-cdf)
  - [General Normal PDF](#prob-normal-pdf)
  - [General Normal CDF](#prob-normal-cdf)
  - [Inverse Normal (Probit)](#prob-normal-inv)
  - [Uniform PDF](#prob-uniform-pdf)
  - [Uniform CDF](#prob-uniform-cdf)
  - [Exponential CDF](#prob-exponential-cdf)
  - [Poisson PMF](#prob-poisson-pmf)
  - [Binomial PMF](#prob-binomial-pmf)
- [Hypothesis Testing](#hypothesis-testing)
  - [One-Sample t-Test](#prob-t-test-1)
  - [Two-Sample Welch's t-Test](#prob-t-test-2)
  - [Paired t-Test](#prob-t-test-paired)
  - [Chi-Squared Goodness of Fit](#prob-chi2-gof)
- [Confidence Intervals](#confidence-intervals)
  - [CI for the Mean](#prob-ci-mean)
- [Internals](#internals)
- [Precision Notes](#precision-notes)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Mixed-precision** | FP16 inputs → FP32 software arithmetic → FP16 results.  Internal coefficients (A&S constants, Horner polynomial) are all FP32 hex literals. |
| **Variable-based state** | Eleven module-scoped `VARIABLE`s (`_PR-A` … `_PR-SRC2`) hold temporaries.  Not re-entrant. |
| **Approximation-based** | Uses Abramowitz & Stegun algorithms for CDF (§26.2.17) and inverse CDF (§26.2.23).  Cornish-Fisher first-order correction maps Student's *t* to a standard normal *z*. |
| **No dynamic allocation** | All scratch space is via VARIABLEs plus the statistics module's `_STAT-SCR0` scratch buffer. |
| **FP16 precision limits** | CDF/PDF are accurate to ≤ 3 ULP for moderate *z*.  Tail regions (*p* < 6 × 10⁻⁵) saturate to 0 or 1 in FP16. |

---

## Distribution Functions

### PROB-STANDARD-PDF

```forth
PROB-STANDARD-PDF  ( z-fp16 -- p-fp16 )
```

Standard normal probability density function:

$$\varphi(z) = \frac{1}{\sqrt{2\pi}} e^{-z^2/2}$$

**Algorithm:** Convert *z* to FP32, compute $z^2/2$ via `FP32-MUL`
and `FP32-DIV`, negate and exponentiate via `EXP-EXP`, multiply by
$1/\sqrt{2\pi}$ (FP32 constant `0x3ECC422A`), convert back to FP16.

**Precision:** ≤ 3 ULP for $|z| \le 4$.
Symmetry: $\varphi(z) = \varphi(-z)$ holds exactly.

```forth
0x3C00 PROB-STANDARD-PDF .   \ z=1.0 → ≈0.2420 (φ(1))
```

---

### PROB-STANDARD-CDF

```forth
PROB-STANDARD-CDF  ( z-fp16 -- p-fp16 )
```

Standard normal cumulative distribution function:

$$\Phi(z) = \int_{-\infty}^{z} \varphi(t)\,dt$$

**Algorithm:** Abramowitz & Stegun §26.2.17 rational approximation.
For $z \ge 0$:

$$\Phi(z) \approx 1 - \varphi(z)(a_1 t + a_2 t^2 + a_3 t^3 + a_4 t^4 + a_5 t^5)$$

where $t = 1/(1 + p|z|)$, $p = 0.2316419$.  The polynomial is
evaluated via a 5-term Horner scheme in FP32 (`_PR-HORNER5`).
For $z < 0$, uses symmetry: $\Phi(z) = 1 - \Phi(-z)$.

Result is clamped to $[0, 1]$ in FP32 before conversion to FP16.

**Precision:** ≤ 3 ULP for $|z| \le 4$.
Symmetry: $\Phi(z) + \Phi(-z) = 1$ to within 1 ULP.

```forth
0x0000 PROB-STANDARD-CDF .   \ z=0 → 0.5
0x3C00 PROB-STANDARD-CDF .   \ z=1 → ≈0.8413
```

---

### PROB-NORMAL-PDF

```forth
PROB-NORMAL-PDF  ( x-fp16 mu-fp16 sigma-fp16 -- p-fp16 )
```

General normal PDF:

$$f(x; \mu, \sigma) = \frac{1}{\sigma} \varphi\!\left(\frac{x - \mu}{\sigma}\right)$$

Computes $z = (x - \mu)/\sigma$ in FP16 arithmetic, calls
`PROB-STANDARD-PDF`, divides by $\sigma$.

---

### PROB-NORMAL-CDF

```forth
PROB-NORMAL-CDF  ( x-fp16 mu-fp16 sigma-fp16 -- p-fp16 )
```

General normal CDF: standardises to $z$ then calls
`PROB-STANDARD-CDF`.

---

### PROB-NORMAL-INV

```forth
PROB-NORMAL-INV  ( p-fp16 -- z-fp16 )
```

Inverse standard normal ($\Phi^{-1}$, probit function):

$$z = \Phi^{-1}(p)$$

**Algorithm:** Abramowitz & Stegun §26.2.23 rational approximation.
For $0 < p \le 0.5$, computes $t = \sqrt{-2 \ln p}$ then:

$$z \approx -\left(t - \frac{c_0 + c_1 t + c_2 t^2}{1 + d_1 t + d_2 t^2 + d_3 t^3}\right)$$

For $p > 0.5$, uses symmetry: $\Phi^{-1}(p) = -\Phi^{-1}(1-p)$.
Special case: $p = 0.5 \Rightarrow z = 0$.

**Precision:** ≤ 4 ULP for $0.01 \le p \le 0.99$.  Tail roundtrip
($\Phi(\Phi^{-1}(0.1))$) may differ by up to ~30 ULP due to
accumulated approximation error.

```forth
0x3800 PROB-NORMAL-INV .     \ p=0.5 → 0.0
0x3400 PROB-NORMAL-INV .     \ p=0.25 → ≈ -0.6745
```

---

### PROB-UNIFORM-PDF

```forth
PROB-UNIFORM-PDF  ( x-fp16 a-fp16 b-fp16 -- p-fp16 )
```

Uniform density on $[a, b]$:

$$f(x) = \begin{cases} \frac{1}{b-a} & a \le x \le b \\ 0 & \text{otherwise} \end{cases}$$

Uses FP32 comparisons for range checking.

---

### PROB-UNIFORM-CDF

```forth
PROB-UNIFORM-CDF  ( x-fp16 a-fp16 b-fp16 -- p-fp16 )
```

Uniform CDF on $[a, b]$:

$$F(x) = \begin{cases} 0 & x < a \\ \frac{x-a}{b-a} & a \le x \le b \\ 1 & x > b \end{cases}$$

---

### PROB-EXPONENTIAL-CDF

```forth
PROB-EXPONENTIAL-CDF  ( x-fp16 lambda-fp16 -- p-fp16 )
```

Exponential CDF:

$$F(x; \lambda) = 1 - e^{-\lambda x}, \quad x \ge 0$$

Returns 0 for $x < 0$.  Computation uses `FP16-MUL`, negate,
`EXP-EXP`, then $1 - \text{result}$.

---

### PROB-POISSON-PMF

```forth
PROB-POISSON-PMF  ( k lambda-fp16 -- p-fp16 )
```

Poisson probability mass function:

$$P(X = k) = \frac{\lambda^k e^{-\lambda}}{k!}$$

**Algorithm:** Computes in log-space to avoid overflow:
$\ln P = k \ln\lambda - \lambda - \ln(k!)$, then exponentiates.
Uses `COMB-LOG-FACTORIAL` from `counting.f` and `EXP-LN` / `EXP-EXP`
from `exp.f`.

**Precision:** ≤ 45 ULP (accumulated FP16 log/exp error for large *k*).

```forth
3 0x4000 PROB-POISSON-PMF .  \ k=3, λ=2.0 → ≈0.1804
```

---

### PROB-BINOMIAL-PMF

```forth
PROB-BINOMIAL-PMF  ( k n p-fp16 -- prob-fp16 )
```

Binomial probability mass function:

$$P(X = k) = \binom{n}{k} p^k (1-p)^{n-k}$$

**Algorithm:** Log-space computation:
$\ln P = \ln\binom{n}{k} + k\ln p + (n-k)\ln(1-p)$, using
`COMB-LOG-CHOOSE` from `counting.f`.

**Precision:** ≤ 125 ULP for large *n* (log/exp chain).

```forth
3 10 0x3800 PROB-BINOMIAL-PMF .  \ k=3, n=10, p=0.5 → ≈0.1172
```

---

## Hypothesis Testing

All hypothesis tests return two FP16 values:

```forth
( ... -- t-stat p-value )
```

where the **p-value is on top of stack** (TOS) and the test statistic
is second.  P-values are two-tailed.

### PROB-T-TEST-1

```forth
PROB-T-TEST-1  ( src n mu0 -- t-fp16 p-fp16 )
```

One-sample *t*-test: $H_0: \mu = \mu_0$.

$$t = \frac{\bar{x} - \mu_0}{s / \sqrt{n}}, \quad df = n - 1$$

- *src*: address of FP16 data array
- *n*: sample size (integer)
- *mu0*: hypothesised mean (FP16)

Uses `_STAT-MEAN-FP32` and `STAT-STDDEV-S` from `stats.f`.
P-value is two-tailed via `_PR-T-PVALUE`.

**Edge case:** If $s = 0$ (all values identical): returns
$t = \pm\infty$ and $p = 0$ when $\bar{x} \ne \mu_0$;
$t = 0$ and $p = 0$ when $\bar{x} = \mu_0$ (degenerate).

```forth
data-arr 20 0x4500 PROB-T-TEST-1 . .  \ prints p then t
```

---

### PROB-T-TEST-2

```forth
PROB-T-TEST-2  ( x nx y ny -- t-fp16 p-fp16 )
```

Two-sample Welch's *t*-test: $H_0: \mu_x = \mu_y$.

$$t = \frac{\bar{x} - \bar{y}}{\sqrt{s_x^2/n_x + s_y^2/n_y}}$$

Degrees of freedom simplified to $df = \min(n_x, n_y) - 1$
(conservative).  P-value via Cornish-Fisher normal approximation.

---

### PROB-T-TEST-PAIRED

```forth
PROB-T-TEST-PAIRED  ( x y n -- t-fp16 p-fp16 )
```

Paired *t*-test: computes $d_i = x_i - y_i$ via `SIMD-SUB-N`,
then runs `PROB-T-TEST-1` on the differences with $\mu_0 = 0$.

---

### PROB-CHI2-GOF

```forth
PROB-CHI2-GOF  ( observed expected n -- chi2-fp16 p-fp16 )
```

Chi-squared goodness-of-fit test:

$$\chi^2 = \sum_{i=0}^{n-1} \frac{(O_i - E_i)^2}{E_i}$$

- *observed*, *expected*: FP16 arrays of length *n*
- P-value via Wilson-Hilferty normal approximation:
  $z = \sqrt{2\chi^2} - \sqrt{2(n-1) - 1}$, then $p = 1 - \Phi(z)$.

**Precision:** Chi-squared statistic is typically exact (0 ULP).
P-value accuracy depends on the Wilson-Hilferty approximation quality,
which is better for larger degrees of freedom; expect ~80 ULP for
$df \le 10$.

```forth
obs-arr exp-arr 6 PROB-CHI2-GOF . .   \ prints p then chi2
```

---

## Confidence Intervals

### PROB-CI-MEAN

```forth
PROB-CI-MEAN  ( src n alpha -- lo-fp16 hi-fp16 )
```

Two-sided confidence interval for the population mean:

$$\text{CI} = \bar{x} \pm z_{\alpha/2} \cdot \frac{s}{\sqrt{n}}$$

- *alpha*: significance level (FP16, e.g. `0x2A66` for 0.05 → 95% CI)
- Uses `PROB-NORMAL-INV` for the critical value.
- Returns *lo* below TOS and *hi* on TOS.

```forth
data-arr 50 0x2A66 PROB-CI-MEAN . .   \ prints hi then lo
```

---

## Internals

### Variables

| Variable | Purpose |
|---|---|
| `_PR-A` … `_PR-D` | General-purpose FP32 temporaries |
| `_PR-X` | FP32 input (CDF sign preservation) |
| `_PR-ACC` | FP32 accumulator (polynomial result, t-stat) |
| `_PR-I` | Integer/flag (sign bit, loop counter) |
| `_PR-N` | Sample size |
| `_PR-SRC`, `_PR-SRC2` | Array addresses |

### Constants

| Constant | Hex | Value | Use |
|---|---|---|---|
| `_PR-P` | `0x3E6D3389` | 0.2316419 | A&S 26.2.17 *p* |
| `_PR-A1`…`_PR-A5` | various | — | Horner polynomial coefficients |
| `_PR-C0`…`_PR-C2` | various | — | A&S 26.2.23 numerator |
| `_PR-D1`…`_PR-D3` | various | — | A&S 26.2.23 denominator |
| `_PR-INV-SQRT2PI` | `0x3ECC422A` | $1/\sqrt{2\pi}$ | PDF normalisation |
| `_PR-SQRT2` | `0x3FB504F3` | $\sqrt{2}$ | INV `ln(p)` scaling |
| `_PR-FP32-HALF` | `0x3F000000` | 0.5 | INV symmetry |
| `_PR-FP32-TWO` | `0x40000000` | 2.0 | P-value doubling |

### Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `_PR-HORNER5` | `( t -- poly )` | Evaluate degree-5 Horner polynomial |
| `_PR-T-CDF` | `( t-fp32 df -- p-fp16 )` | Approximate Student's *t* CDF |
| `_PR-T-PVALUE` | `( t-fp32 df -- p-fp16 )` | Two-tailed p-value |

---

## Precision Notes

| Function | Typical ULP | Notes |
|---|---|---|
| `PROB-STANDARD-PDF` | ≤ 3 | Exact symmetry |
| `PROB-STANDARD-CDF` | ≤ 3 | A&S 26.2.17, 6-coefficient approximation |
| `PROB-NORMAL-INV` | ≤ 4 | A&S 26.2.23, 6-coefficient rational |
| `PROB-UNIFORM-*` | 0 | Exact (simple arithmetic) |
| `PROB-EXPONENTIAL-CDF` | ≤ 3 | Via `EXP-EXP` |
| `PROB-POISSON-PMF` | ≤ 45 | Log-space, accumulates FP16 error |
| `PROB-BINOMIAL-PMF` | ≤ 125 | Log-space, large *n* compounds error |
| `PROB-T-TEST-*` | ≤ 12 t-stat | P-value may saturate to 0 for extreme *t* |
| `PROB-CHI2-GOF` | 0 χ², ≤ 80 p | Wilson-Hilferty approx for p-value |
| `PROB-CI-MEAN` | ≤ 8 | Depends on `PROB-NORMAL-INV` accuracy |

**Tail behaviour:** FP16 has ~3.3 decimal digits.  CDF values below
~6 × 10⁻⁵ or above 1 − 6 × 10⁻⁵ cannot be represented and saturate
to 0.0 or 1.0 respectively.  P-values in this range are reported as 0.

---

## Quick Reference

```
PROB-STANDARD-PDF      ( z -- p )            Standard normal φ(z)
PROB-STANDARD-CDF      ( z -- p )            Standard normal Φ(z)
PROB-NORMAL-PDF        ( x mu sigma -- p )   General normal PDF
PROB-NORMAL-CDF        ( x mu sigma -- p )   General normal CDF
PROB-NORMAL-INV        ( p -- z )            Inverse normal Φ⁻¹(p)
PROB-UNIFORM-PDF       ( x a b -- p )        Uniform density
PROB-UNIFORM-CDF       ( x a b -- p )        Uniform CDF
PROB-EXPONENTIAL-CDF   ( x lambda -- p )     Exponential CDF
PROB-POISSON-PMF       ( k lambda -- p )     Poisson PMF
PROB-BINOMIAL-PMF      ( k n p -- prob )     Binomial PMF
PROB-T-TEST-1          ( src n mu0 -- t p )  One-sample t-test
PROB-T-TEST-2          ( x nx y ny -- t p )  Two-sample Welch's t
PROB-T-TEST-PAIRED     ( x y n -- t p )      Paired t-test
PROB-CHI2-GOF          ( obs exp n -- χ² p ) Chi-squared GOF
PROB-CI-MEAN           ( src n alpha -- lo hi ) Confidence interval
```
