# akashic-exp — FP16 Exponentials, Logarithms & Activations

Polynomial approximations for $\exp$, $\ln$, $\exp_2$, $\log_2$,
general power, sigmoid, and tanh — all on FP16 bit patterns.

```forth
REQUIRE exp.f
```

`PROVIDED akashic-exp` — REQUIRE `fp16-ext.f`.

---

## Table of Contents

- [Design](#design)
- [Base-2 Primitives](#base-2-primitives)
- [Natural Exp / Ln](#natural-exp--ln)
- [General Power](#general-power)
- [Activation Functions](#activation-functions)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design

| Principle | Detail |
|---|---|
| **Base-2 core** | `EXP-EXP2` and `EXP-LOG2` are the primitives. `EXP-EXP` and `EXP-LN` are thin wrappers via $\ln 2$. |
| **Range reduction** | `EXP-EXP2` splits $x = n + f$, computes $2^n$ by exponent-bit manipulation, $2^f$ by polynomial on $[0,1)$. |
| **Mantissa extraction** | `EXP-LOG2` extracts the FP16 biased exponent and 10-bit mantissa, evaluates a minimax polynomial for $\log_2(1 + m)$. |
| **Degree-3 polynomials** | Sufficient for FP16's 10-bit mantissa. |

### Accuracy

| Function | Max error (ULP) |
|---|---|
| `EXP-EXP2` | ≤ 2 |
| `EXP-LOG2` | ≤ 2 |
| `EXP-EXP` | ≤ 3 |
| `EXP-LN` | ≤ 3 |
| `EXP-SIGMOID` | ≤ 4 |
| `EXP-TANH` | ≤ 4 |

---

## Base-2 Primitives

### EXP-EXP2

```forth
EXP-EXP2  ( x -- 2^x )
```

Base-2 exponential.  Valid for $x \in [-14, 15]$ (the FP16 normal
range).  Returns +0 for very negative inputs, +∞ for very large.

**Algorithm:**
1. Split $x = n + f$ where $n = \lfloor x \rfloor$, $f \in [0, 1)$.
2. $2^n$ by constructing the FP16 exponent bits directly.
3. $2^f \approx c_0 + f(c_1 + f(c_2 + f \cdot c_3))$ — Horner form.
4. Return $2^n \times 2^f$.

### EXP-LOG2

```forth
EXP-LOG2  ( x -- log2[x] )
```

Base-2 logarithm.  Returns NaN for $x < 0$, $-\infty$ for $x = 0$.

**Algorithm:**
1. Extract biased exponent $e$ and 10-bit mantissa.
2. Reconstruct $m \in [0, 1)$ from the mantissa bits.
3. $\log_2(1 + m) \approx m \cdot (c_0 + m(c_1 + m \cdot c_2))$.
4. Return $(e - 15) + \log_2(1 + m)$.

---

## Natural Exp / Ln

### EXP-EXP

```forth
EXP-EXP  ( x -- e^x )
```

Natural exponential: $e^x = 2^{x / \ln 2} = 2^{x \cdot 1.4427}$.

### EXP-LN

```forth
EXP-LN  ( x -- ln[x] )
```

Natural logarithm: $\ln x = \log_2 x \cdot \ln 2$.

---

## General Power

### EXP-POW

```forth
EXP-POW  ( base exp -- base^exp )
```

General power function: $\text{base}^{\text{exp}} = 2^{\text{exp} \cdot \log_2(\text{base})}$.

Works for any positive base and any exponent (including fractional).

---

## Activation Functions

These are commonly needed for neural-network inference and
UI animation curves.

### EXP-SIGMOID

```forth
EXP-SIGMOID  ( x -- σ )
```

Logistic sigmoid: $\sigma(x) = \dfrac{1}{1 + e^{-x}}$.

Implemented as `FP16-NEG EXP-EXP FP16-ONE FP16-ADD FP16-RECIP`.

### EXP-TANH

```forth
EXP-TANH  ( x -- tanh )
```

Hyperbolic tangent: $\tanh(x) = 2\sigma(2x) - 1$.

---

## Internals

| Symbol | Purpose |
|---|---|
| `_EX-LN2` | $\ln 2 \approx 0.6931$ (FP16 `0x398C`) |
| `_EX-INV-LN2` | $1/\ln 2 \approx 1.4427$ (FP16 `0x3DC5`) |
| `_EX-E2-C0..C3` | Polynomial coefficients for $2^f$ on $[0,1)$ |
| `_EX-L2-C0..C2` | Polynomial coefficients for $\log_2(1+m)$ |
| `_EX-N` | VARIABLE — integer part of exponent split |
| `_EX-F` | VARIABLE — fractional part |
| `_EX-POW2-INT` | Construct FP16 for $2^n$ by bit manipulation |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `EXP-EXP2` | `( x -- 2^x )` | Base-2 exponential |
| `EXP-LOG2` | `( x -- log₂x )` | Base-2 logarithm |
| `EXP-EXP` | `( x -- eˣ )` | Natural exponential |
| `EXP-LN` | `( x -- ln x )` | Natural logarithm |
| `EXP-POW` | `( base exp -- r )` | General power |
| `EXP-SIGMOID` | `( x -- σ(x) )` | Logistic sigmoid |
| `EXP-TANH` | `( x -- tanh x )` | Hyperbolic tangent |
