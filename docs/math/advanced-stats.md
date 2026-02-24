# akashic-advanced-stats — Inferential Extensions & Non-Parametric Tests

Inferential statistics, effect sizes, non-parametric tests, ANOVA,
confidence intervals, and multiple comparison corrections for FP16
arrays in HBW math RAM.

```forth
REQUIRE advanced-stats.f
```

`PROVIDED akashic-advanced-stats` — auto-loads `probability.f`
(which chains `stats.f`, `sort.f`, `counting.f`, `exp.f`, `trig.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Public CDF](#public-cdf)
- [Confidence Intervals](#confidence-intervals)
- [Effect Sizes](#effect-sizes)
- [Non-Parametric Tests](#non-parametric-tests)
- [ANOVA](#anova)
- [Multiple Comparison Correction](#multiple-comparison-correction)
- [Precision Notes](#precision-notes)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Mixed-precision** | FP16 inputs → FP32 intermediate arithmetic → FP16 output. Same pipeline as the rest of the math suite. |
| **Approximation-based** | Distributions evaluated via polynomial/normal approximations (Wilson-Hilferty for F, Cornish-Fisher for t). Accuracy exceeds FP16 resolution. |
| **Normal-approximation p-values** | Non-parametric tests use the large-sample normal approximation for p-values. Adequate for n ≥ 10. |
| **Numerically stable** | Two-tailed p-values use `2·Φ(-|z|)` instead of `2·(1-Φ(|z|))` to avoid catastrophic cancellation for large z. |
| **VARIABLE-based state** | Module-scoped VARIABLEs (`_AS-*`). Not re-entrant. |

---

## Public CDF

### PROB-T-CDF

```forth
PROB-T-CDF  ( t-fp16 df -- p-fp16 )
```

Student's t CDF. Public wrapper of the internal `_PR-T-CDF` from
probability.f. Uses the Cornish-Fisher approximation to convert t
to a standard normal z, then evaluates Φ(z).

| Parameter | Description |
|---|---|
| `t-fp16` | Test statistic as FP16 |
| `df` | Degrees of freedom (integer) |
| Returns | P(T ≤ t) as FP16 |

**Precision:** Cornish-Fisher approximation gives ~18–107 ULP error
relative to exact t CDF, depending on df.  Excellent for df ≥ 20.

### ADVS-F-CDF

```forth
ADVS-F-CDF  ( f-fp16 df1 df2 -- p-fp16 )
```

F-distribution CDF via the Wilson-Hilferty approximation
(Abramowitz & Stegun 26.6.16):

$$y = F^{1/3}, \quad z = \frac{b \cdot y - a}{\sqrt{v_a + v_b \cdot y^2}}$$

where $a = 1 - 2/(9 \cdot d_1)$, $b = 1 - 2/(9 \cdot d_2)$,
$v_a = 2/(9 \cdot d_1)$, $v_b = 2/(9 \cdot d_2)$.

| Parameter | Description |
|---|---|
| `f-fp16` | F statistic as FP16 |
| `df1` | Numerator degrees of freedom (integer) |
| `df2` | Denominator degrees of freedom (integer) |
| Returns | P(F ≤ f) as FP16 |

**Precision:** ≤ 15 ULP vs scipy for typical inputs.

---

## Confidence Intervals

### PROB-CI-PROPORTION

```forth
PROB-CI-PROPORTION  ( successes n alpha -- lo-fp16 hi-fp16 )
```

Wilson score confidence interval for a binomial proportion.

$$\hat{p} = \frac{k}{n}, \quad z = \Phi^{-1}(1 - \alpha/2)$$

$$\text{lo, hi} = \frac{\hat{p} + z^2/(2n) \pm z\sqrt{\hat{p}(1-\hat{p})/n + z^2/(4n^2)}}{1 + z^2/n}$$

| Parameter | Description |
|---|---|
| `successes` | Number of successes (integer) |
| `n` | Total trials (integer) |
| `alpha` | Significance level as FP16 (e.g., 0.05) |
| Returns | `( lo hi )` both FP16 |

### PROB-CI-DIFF-MEANS

```forth
PROB-CI-DIFF-MEANS  ( x nx y ny alpha -- lo-fp16 hi-fp16 )
```

Confidence interval for the difference of two means using a normal
approximation for the critical value.

$$(\bar{x}_1 - \bar{x}_2) \pm z_{\alpha/2} \cdot \sqrt{s_1^2/n_1 + s_2^2/n_2}$$

| Parameter | Description |
|---|---|
| `x` | HBW array of first group (FP16) |
| `nx` | Size of first group (integer) |
| `y` | HBW array of second group (FP16) |
| `ny` | Size of second group (integer) |
| `alpha` | Significance level as FP16 |
| Returns | `( lo hi )` both FP16 |

---

## Effect Sizes

### ADVS-COHENS-D

```forth
ADVS-COHENS-D  ( x nx y ny -- d-fp16 )
```

Cohen's d effect size (standardized mean difference):

$$d = \frac{\bar{x}_1 - \bar{x}_2}{s_{\text{pooled}}}, \quad
s_{\text{pooled}} = \sqrt{\frac{(n_1-1)s_1^2 + (n_2-1)s_2^2}{n_1+n_2-2}}$$

Returns 0.0 if pooled standard deviation is zero (identical groups).

### ADVS-HEDGES-G

```forth
ADVS-HEDGES-G  ( x nx y ny -- g-fp16 )
```

Hedges' g — bias-corrected effect size:

$$g = d \cdot \left(1 - \frac{3}{4(n_1+n_2) - 9}\right)$$

Calls `ADVS-COHENS-D` internally.

---

## Non-Parametric Tests

### ADVS-MANN-WHITNEY

```forth
ADVS-MANN-WHITNEY  ( x nx y ny -- U-fp16 p-fp16 )
```

Mann-Whitney U test (non-parametric two-sample test).

**Algorithm:**
1. Merge x and y into combined array.
2. Rank all elements with tie averaging (via `SORT-RANK`).
3. Sum ranks for group x → R₁.
4. $U = R_1 - n_x(n_x+1)/2$.
5. Normal approximation: $z = (U - \mu_U) / \sigma_U$,
   where $\mu_U = n_x n_y / 2$,
   $\sigma_U = \sqrt{n_x n_y (n_x + n_y + 1) / 12}$.
6. Two-tailed $p = 2 \cdot \Phi(-|z|)$.

| Parameter | Description |
|---|---|
| `x`, `y` | HBW arrays (FP16) |
| `nx`, `ny` | Group sizes (integers) |
| Returns | `( U-fp16 p-fp16 )` |

**Memory:** Uses `_STAT-SCR0` (merged data), `_STAT-SCR1` (ranks),
and `_SORT-RANKBUF` (index permutation).

### ADVS-WILCOXON

```forth
ADVS-WILCOXON  ( x y n -- W-fp16 p-fp16 )
```

Wilcoxon signed-rank test (paired non-parametric test).

**Algorithm:**
1. Compute $d_i = x_i - y_i$.
2. Discard zeros.
3. Rank $|d_i|$ with tie averaging.
4. $W^+ = \sum \text{rank}_i$ where $d_i > 0$.
5. Normal approximation: $z = (W^+ - \mu) / \sigma$,
   where $\mu = n'(n'+1)/4$,
   $\sigma = \sqrt{n'(n'+1)(2n'+1)/24}$,
   $n'$ = number of non-zero differences.
6. Two-tailed $p = 2 \cdot \Phi(-|z|)$.

| Parameter | Description |
|---|---|
| `x`, `y` | Paired HBW arrays (FP16) |
| `n` | Number of pairs (integer) |
| Returns | `( W+-fp16 p-fp16 )` |

**Memory:** Uses `_STAT-SCR0` (|diffs|), `_STAT-SCR1` (ranks),
`_AS-SIGNBUF` (sign flags), `_SORT-RANKBUF` (index permutation).

---

## ANOVA

### ADVS-ANOVA-1

```forth
ADVS-ANOVA-1  ( g1 n1 g2 n2 ... gk nk k -- F-fp16 p-fp16 )
```

One-way analysis of variance for k groups (2 ≤ k ≤ 6).

$$F = \frac{MSB}{MSW} = \frac{SSB / (k-1)}{SSW / (N-k)}$$

**p-value** via `ADVS-F-CDF`: $p = 1 - F_{\text{CDF}}(F, k-1, N-k)$.

| Parameter | Description |
|---|---|
| `gi` | HBW pointer to group i (FP16) |
| `ni` | Size of group i (integer) |
| `k` | Number of groups (2–6, integer) |
| Returns | `( F-fp16 p-fp16 )` |

Groups are passed on the stack in order: group 1 pair first, then
group 2, etc. The `k` parameter is always the last argument popped.

---

## Multiple Comparison Correction

### ADVS-BONFERRONI

```forth
ADVS-BONFERRONI  ( alpha-fp16 k -- alpha'-fp16 )
```

Bonferroni correction: $\alpha' = \alpha / k$.

### ADVS-HOLM

```forth
ADVS-HOLM  ( pvals n alpha dst -- )
```

Holm-Bonferroni step-down correction.

**Algorithm:**
1. Sort p-values (ascending), tracking original positions.
2. For $i = 0, 1, \ldots, n-1$:
   compare $p_{(i)}$ to $\alpha / (n - i)$.
   If $p_{(i)} > \text{threshold}$: stop — no more rejections.
3. Write rejection flags (`FP16 1.0` / `0.0`) to `dst` at
   original positions.

| Parameter | Description |
|---|---|
| `pvals` | HBW array of p-values (FP16) |
| `n` | Number of p-values (integer) |
| `alpha` | Family-wise significance level as FP16 |
| `dst` | HBW output array — FP16 flags (1.0 = rejected) |

---

## Precision Notes

| Word | Typical ULP error | Source |
|---|---|---|
| `PROB-T-CDF` | 8–107 | Cornish-Fisher approximation |
| `ADVS-F-CDF` | 0–15 | Wilson-Hilferty approximation |
| CI words | 1–6 | Normal quantile + FP16 rounding |
| Effect sizes | 0–4 | FP32 arithmetic chain |
| Non-parametric p | 2–10 | Normal approximation for n ≥ 10 |
| `ADVS-BONFERRONI` | 0–2 | Simple division |
| `ADVS-HOLM` | exact flags | Comparison in FP32 |

**Subnormal p-values:** `FP32>FP16` flushes subnormals to zero.
For p-values below FP16 min normal (~6.1 × 10⁻⁵), the two-tailed
p is reported as **0.0**.  This occurs when |z| ≳ 3.9.

---

## Internals

### HBW buffers

| Buffer | Size | Owner | Purpose |
|---|---|---|---|
| `_SORT-RANKBUF` | 4096 B | sort.f | Index permutation for SORT-RANK (512 × 8 B) |
| `_STAT-SCR0` | 4096 B | stats.f | Merged data / abs-diffs workspace |
| `_STAT-SCR1` | 4096 B | stats.f | Rank output / argsort index |
| `_AS-SIGNBUF` | 4096 B | advanced-stats.f | Wilcoxon sign flags (512 × 8 B) |

### Variables

All `_AS-*` and `_AN-*` variables are module-scoped.
Not re-entrant — only one statistical test may run at a time
(which is the normal case for single-CPU Forth code).

---

## Quick Reference

```
PROB-T-CDF           ( t-fp16 df -- p-fp16 )
ADVS-F-CDF           ( f-fp16 df1 df2 -- p-fp16 )
PROB-CI-PROPORTION   ( succ n alpha -- lo hi )
PROB-CI-DIFF-MEANS   ( x nx y ny alpha -- lo hi )
ADVS-COHENS-D        ( x nx y ny -- d )
ADVS-HEDGES-G        ( x nx y ny -- g )
ADVS-MANN-WHITNEY    ( x nx y ny -- U p )
ADVS-WILCOXON        ( x y n -- W p )
ADVS-ANOVA-1         ( g1 n1 ... gk nk k -- F p )
ADVS-BONFERRONI      ( alpha k -- alpha' )
ADVS-HOLM            ( pvals n alpha dst -- )
```
