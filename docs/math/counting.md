# akashic-counting — Integer Combinatorics & Number Theory

Pure 64-bit integer combinatorics: factorials, binomial coefficients,
permutations, GCD/LCM, modular exponentiation, and primality testing.
Log-space variants (FP16 output via `exp.f`) handle values too large
for exact integer representation.

```forth
REQUIRE counting.f
```

`PROVIDED akashic-counting` — auto-loads `fp16.f`, `fp32.f`, `exp.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Factorials & Combinations](#factorials--combinations)
- [Number Theory](#number-theory)
- [Log-Space Variants](#log-space-variants)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Pure integer** | No tile engine or SIMD needed — scalar 64-bit arithmetic only. |
| **Overflow-safe C(n,k)** | Multiplicative formula computes $\binom{n}{k}$ without computing $n!$. |
| **Symmetry optimization** | `COMB-CHOOSE` uses $\min(k, n-k)$ to minimize iterations. |
| **Log-space for large values** | `COMB-LOG-FACTORIAL` and `COMB-LOG-CHOOSE` return FP16 natural logs, avoiding integer overflow entirely. |
| **VARIABLE-based state** | Module-scoped VARIABLEs for loop state. Not re-entrant. |

---

## Factorials & Combinations

### COMB-FACTORIAL

```forth
COMB-FACTORIAL  ( n -- n! )
```

64-bit integer factorial.  $20! = 2{,}432{,}902{,}008{,}176{,}640{,}000$
fits in 64 bits; returns 0 for $n > 20$ or $n < 0$.

```forth
5 COMB-FACTORIAL .     \ → 120
20 COMB-FACTORIAL .    \ → 2432902008176640000
21 COMB-FACTORIAL .    \ → 0  (overflow guard)
```

### COMB-CHOOSE

```forth
COMB-CHOOSE  ( n k -- nCk )
```

Binomial coefficient $\binom{n}{k}$ via the multiplicative formula:

$$\binom{n}{k} = \prod_{i=0}^{k-1} \frac{n - i}{i + 1}$$

Each step produces an exact integer (the partial products are always
divisible), so no rounding occurs.  Uses $\min(k, n-k)$ iterations.

```forth
10 3 COMB-CHOOSE .     \ → 120
20 10 COMB-CHOOSE .    \ → 184756
52 5 COMB-CHOOSE .     \ → 2598960  (poker hands)
```

### COMB-PERMUTE

```forth
COMB-PERMUTE  ( n k -- nPk )
```

$k$-permutations of $n$: $\frac{n!}{(n-k)!} = n \cdot (n-1) \cdots (n-k+1)$.

```forth
10 3 COMB-PERMUTE .    \ → 720
5 5 COMB-PERMUTE .     \ → 120  (same as 5!)
```

---

## Number Theory

### COMB-GCD

```forth
COMB-GCD  ( a b -- gcd )
```

Greatest common divisor via the Euclidean algorithm.

```forth
48 18 COMB-GCD .       \ → 6
100 75 COMB-GCD .      \ → 25
```

### COMB-LCM

```forth
COMB-LCM  ( a b -- lcm )
```

Least common multiple: $\text{lcm}(a, b) = \frac{a \cdot b}{\gcd(a, b)}$.

```forth
12 18 COMB-LCM .       \ → 36
7 5 COMB-LCM .         \ → 35
```

### COMB-POWER-MOD

```forth
COMB-POWER-MOD  ( base exp mod -- result )
```

Modular exponentiation via binary (square-and-multiply) method.
Computes $\text{base}^{\text{exp}} \bmod \text{mod}$.  Safe for
moduli up to $2^{32}$ (intermediate products fit 64 bits).

```forth
2 10 1000 COMB-POWER-MOD .    \ → 24  (2^10 mod 1000)
3 13 100 COMB-POWER-MOD .     \ → 97  (3^13 mod 100)
```

### COMB-IS-PRIME?

```forth
COMB-IS-PRIME?  ( n -- flag )
```

Primality test using 6$k$±1 trial division up to $\sqrt{n}$.
Returns −1 (true) or 0 (false).  Complexity O($\sqrt{n}$).

```forth
7 COMB-IS-PRIME? .     \ → -1  (true)
100 COMB-IS-PRIME? .   \ → 0   (false)
```

### COMB-NEXT-PRIME

```forth
COMB-NEXT-PRIME  ( n -- p )
```

Smallest prime $\ge n$.  Increments by 2 from the nearest odd
and tests each with `COMB-IS-PRIME?`.

```forth
10 COMB-NEXT-PRIME .   \ → 11
100 COMB-NEXT-PRIME .  \ → 101
```

---

## Log-Space Variants

For values too large for 64-bit exact representation ($n > 20$),
the log-space words return $\ln(\cdot)$ as FP16.

### COMB-LOG-FACTORIAL

```forth
COMB-LOG-FACTORIAL  ( n -- ln[n!] )
```

Natural logarithm of $n!$ as FP16.

- For $n \le 12$: exact via `COMB-FACTORIAL` → `INT>FP16` → `EXP-LN`.
- For $n > 12$: Stirling's approximation:

$$\ln n! \approx n \ln n - n + \tfrac{1}{2} \ln(2\pi n)$$

### COMB-LOG-CHOOSE

```forth
COMB-LOG-CHOOSE  ( n k -- ln[nCk] )
```

Log binomial coefficient: $\ln\binom{n}{k} = \ln n! - \ln k! - \ln(n-k)!$

Useful for probability computations where the binomial coefficient
itself would overflow, but the log fits comfortably in FP16.

---

## Internals

### Module Variables

| Variable | Purpose |
|---|---|
| `_CB-A` | First operand / running state |
| `_CB-B` | Second operand |
| `_CB-R` | Result accumulator |
| `_CB-I` | Loop index |
| `_CB-M` | Modulus (for POWER-MOD) |

### Constants

| Constant | Value | Description |
|---|---|---|
| `_CB-2PI` | `0x4648` | FP16 for 2π ≈ 6.2832 (Stirling's) |

---

## Quick Reference

```
COMB-FACTORIAL      ( n -- n! )          64-bit, max n=20
COMB-CHOOSE         ( n k -- nCk )       binomial coefficient
COMB-PERMUTE        ( n k -- nPk )       k-permutations

COMB-GCD            ( a b -- gcd )       Euclidean algorithm
COMB-LCM            ( a b -- lcm )       via GCD
COMB-POWER-MOD      ( base exp mod -- r ) binary method
COMB-IS-PRIME?      ( n -- flag )         6k±1 trial division
COMB-NEXT-PRIME     ( n -- p )            smallest prime ≥ n

COMB-LOG-FACTORIAL  ( n -- ln[n!] )      FP16, Stirling's for n>12
COMB-LOG-CHOOSE     ( n k -- ln[nCk] )   FP16, via log-factorial
```

## Limitations

- `COMB-FACTORIAL` returns 0 for $n > 20$ (64-bit overflow).
- `COMB-POWER-MOD` intermediate products overflow for moduli $> 2^{32}$.
- `COMB-IS-PRIME?` uses trial division — O($\sqrt{n}$), not
  suitable for cryptographic-size primes.
- Log-space words inherit FP16's ≈3.3 decimal digit precision.
