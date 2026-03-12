\ probability.f — Probability Distributions & Hypothesis Testing
\
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ Prefix: PROB-  (public API)
\         _PR-   (internal helpers)
\
\ Depends on: stats.f, exp.f, trig.f, counting.f
\
\ Load with:   REQUIRE probability.f
\
\ === Public API ===
\
\ Distribution Functions:
\   PROB-STANDARD-PDF  ( z -- p )            standard normal PDF
\   PROB-STANDARD-CDF  ( z -- p )            standard normal CDF (Φ)
\   PROB-NORMAL-PDF    ( x mu sigma -- p )   general normal PDF
\   PROB-NORMAL-CDF    ( x mu sigma -- p )   general normal CDF
\   PROB-NORMAL-INV    ( p -- z )            inverse normal (probit)
\   PROB-UNIFORM-PDF   ( x a b -- p )        uniform density on [a,b]
\   PROB-UNIFORM-CDF   ( x a b -- p )        uniform CDF
\   PROB-EXPONENTIAL-CDF ( x lambda -- p )   exponential CDF
\   PROB-POISSON-PMF   ( k lambda -- p )     Poisson PMF
\   PROB-BINOMIAL-PMF  ( k n p -- prob )     binomial PMF
\
\ Hypothesis Testing:
\   PROB-T-TEST-1      ( src n mu0 -- t p )  one-sample t-test
\   PROB-T-TEST-2      ( x nx y ny -- t p )  two-sample Welch's t-test
\   PROB-T-TEST-PAIRED ( x y n -- t p )      paired t-test
\   PROB-CHI2-GOF      ( obs exp n -- chi2 p ) chi-squared GOF
\
\ Confidence Intervals:
\   PROB-CI-MEAN       ( src n alpha -- lo hi ) CI for mean

REQUIRE stats.f
REQUIRE exp.f
REQUIRE trig.f
REQUIRE counting.f

PROVIDED akashic-probability

\ =====================================================================
\  Internal state
\ =====================================================================

VARIABLE _PR-A       \ general FP32
VARIABLE _PR-B       \ general FP32
VARIABLE _PR-C       \ general FP32
VARIABLE _PR-D       \ general FP32
VARIABLE _PR-X       \ FP32 input
VARIABLE _PR-ACC     \ FP32 accumulator
VARIABLE _PR-I       \ loop index
VARIABLE _PR-N       \ count
VARIABLE _PR-SRC     \ source pointer
VARIABLE _PR-SRC2    \ second source pointer

\ =====================================================================
\  Constants (FP32 packed as 32-bit in 64-bit cell)
\ =====================================================================

\ 1/sqrt(2*pi) ≈ 0.39894228   → FP32: 0x3ECC422A
0x3ECC422A CONSTANT _PR-INV-SQRT-2PI

\ sqrt(2) ≈ 1.41421356    → FP32: 0x3FB504F3
0x3FB504F3 CONSTANT _PR-SQRT2

\ 0.5 in FP32
0x3F000000 CONSTANT _PR-FP32-HALF

\ 2.0 in FP32
0x40000000 CONSTANT _PR-FP32-TWO

\ =====================================================================
\  PROB-STANDARD-PDF — Standard Normal Density
\ =====================================================================
\  φ(z) = (1/√(2π)) · exp(-z²/2)
\  All computation in FP32.

: PROB-STANDARD-PDF  ( z-fp16 -- p-fp16 )
    FP16>FP32 _PR-X !
    \ -z^2 / 2
    _PR-X @ DUP FP32-MUL           \ z^2
    FP32-NEGATE                     \ -z^2
    _PR-FP32-HALF FP32-MUL         \ -z^2/2
    FP32>FP16 EXP-EXP FP16>FP32    \ exp(-z^2/2) via FP16 exp
    _PR-INV-SQRT-2PI FP32-MUL      \ * 1/sqrt(2pi)
    FP32>FP16 ;

\ =====================================================================
\  PROB-STANDARD-CDF — Standard Normal CDF (Φ)
\ =====================================================================
\  Abramowitz & Stegun approximation (formula 26.2.17)
\  |error| < 7.5e-8 — far exceeds FP16 precision needs.
\
\  For z >= 0:
\    t = 1 / (1 + 0.2316419 * z)
\    Φ(z) = 1 - φ(z) * (a1*t + a2*t² + a3*t³ + a4*t⁴ + a5*t⁵)
\  For z < 0:  Φ(z) = 1 - Φ(-z)

\ Coefficients as FP32
0x3E6D3389 CONSTANT _PR-P          \ 0.2316419 → FP32
0x3EA385FA CONSTANT _PR-A1         \ 0.319381530
0xBEB68F87 CONSTANT _PR-A2         \ -0.356563782
0x3FE40778 CONSTANT _PR-A3         \  1.781477937
0xBFE91EEA CONSTANT _PR-A4         \ -1.821255978
0x3FAA466F CONSTANT _PR-A5         \  1.330274429

: _PR-HORNER5  ( t -- poly )
    \ Evaluate a1 + t*(a2 + t*(a3 + t*(a4 + t*a5)))
    \ But actually: a5*t + a4, then *t + a3, ...
    _PR-D !    \ save t (consume from stack)
    _PR-A5 _PR-D @ FP32-MUL _PR-A4 FP32-ADD
    _PR-D @ FP32-MUL _PR-A3 FP32-ADD
    _PR-D @ FP32-MUL _PR-A2 FP32-ADD
    _PR-D @ FP32-MUL _PR-A1 FP32-ADD
    _PR-D @ FP32-MUL ;     \ final multiply by t

: PROB-STANDARD-CDF  ( z-fp16 -- p-fp16 )
    FP16>FP32 _PR-X !

    \ Save sign flag before _PR-X gets clobbered by PROB-STANDARD-PDF
    _PR-X @ 31 RSHIFT _PR-I !
    _PR-X @ FP32-ABS _PR-A !     \ |z| in FP32

    \ t = 1 / (1 + p * |z|)
    _PR-P _PR-A @ FP32-MUL FP32-ONE FP32-ADD
    FP32-ONE SWAP FP32-DIV _PR-B !    \ t

    \ φ(|z|)
    _PR-A @ FP32>FP16 PROB-STANDARD-PDF FP16>FP32 _PR-C !

    \ poly = horner eval
    _PR-B @ _PR-HORNER5 _PR-ACC !

    \ Φ(|z|) = 1 - φ(|z|) * poly
    _PR-C @ _PR-ACC @ FP32-MUL
    FP32-ONE SWAP FP32-SUB _PR-ACC !

    \ If original z < 0: result = 1 - Φ(|z|)
    _PR-I @ 0 > IF
        FP32-ONE _PR-ACC @ FP32-SUB _PR-ACC !
    THEN

    \ Clamp to [0, 1]
    _PR-ACC @
    DUP FP32-ZERO FP32< IF DROP FP32-ZERO THEN
    DUP FP32-ONE FP32> IF DROP FP32-ONE THEN
    FP32>FP16 ;

\ =====================================================================
\  PROB-NORMAL-PDF / PROB-NORMAL-CDF — General Normal
\ =====================================================================
\  Transform to standard: z = (x - mu) / sigma

: PROB-NORMAL-PDF  ( x mu sigma -- p )
    DUP >R
    >R FP16-SUB R> FP16-DIV
    PROB-STANDARD-PDF
    R> FP16-DIV ;

: PROB-NORMAL-CDF  ( x mu sigma -- p )
    >R FP16-SUB R> FP16-DIV
    PROB-STANDARD-CDF ;

\ =====================================================================
\  PROB-NORMAL-INV — Inverse Normal (Probit / Quantile)
\ =====================================================================
\  Rational approximation for Φ⁻¹(p).
\  Beasley-Springer-Moro algorithm (simplified for FP16).
\
\  For 0.5 <= p < 1:
\    t = sqrt(-2 * ln(1 - p))
\    z = t - (c0 + c1*t + c2*t²) / (1 + d1*t + d2*t² + d3*t³)
\  For p < 0.5: z = -Φ⁻¹(1-p)
\
\  Simplified: Use Abramowitz & Stegun 26.2.23 (rational approx)
\  For p in (0, 0.5):
\    t = sqrt(-2 * ln(p))
\    z = -(t - (2.515517 + 0.802853*t + 0.010328*t²)
\                / (1 + 1.432788*t + 0.189269*t² + 0.001308*t³))

0x4020FE3B CONSTANT _PR-C0    \ 2.515517
0x3F4D87C6 CONSTANT _PR-C1    \ 0.802853
0x3C2936C6 CONSTANT _PR-C2    \ 0.010328
0x3FB76599 CONSTANT _PR-D1    \ 1.432788
0x3E41CFBC CONSTANT _PR-D2    \ 0.189269
0x3AAB7132 CONSTANT _PR-D3    \ 0.001308

: PROB-NORMAL-INV  ( p-fp16 -- z-fp16 )
    FP16>FP32 _PR-X !

    \ Handle p <= 0 or p >= 1
    _PR-X @ FP32-ZERO FP32<= IF FP16-NEG-INF EXIT THEN
    _PR-X @ FP32-ONE FP32>= IF FP16-POS-INF EXIT THEN

    \ Special-case p = 0.5 -> z = 0 exactly
    _PR-X @ _PR-FP32-HALF FP32= IF FP16-POS-ZERO EXIT THEN

    \ If p > 0.5, use symmetry: z = -Φ⁻¹(1-p)
    0 _PR-I !     \ sign flag
    _PR-X @ _PR-FP32-HALF FP32> IF
        1 _PR-I !
        FP32-ONE _PR-X @ FP32-SUB _PR-X !
    THEN

    \ t = sqrt(-2 * ln(p))
    _PR-X @ FP32>FP16 EXP-LN FP16>FP32    \ ln(p)
    _PR-FP32-TWO FP32-MUL FP32-NEGATE      \ -2*ln(p)
    FP32-SQRT _PR-A !                      \ t

    \ Numerator: c0 + c1*t + c2*t²
    _PR-C2 _PR-A @ FP32-MUL _PR-C1 FP32-ADD
    _PR-A @ FP32-MUL _PR-C0 FP32-ADD _PR-B !

    \ Denominator: 1 + d1*t + d2*t² + d3*t³
    _PR-D3 _PR-A @ FP32-MUL _PR-D2 FP32-ADD
    _PR-A @ FP32-MUL _PR-D1 FP32-ADD
    _PR-A @ FP32-MUL FP32-ONE FP32-ADD _PR-C !

    \ z = -(t - num/den)
    _PR-B @ _PR-C @ FP32-DIV
    _PR-A @ SWAP FP32-SUB FP32-NEGATE _PR-ACC !

    _PR-I @ IF
        _PR-ACC @ FP32-NEGATE _PR-ACC !
    THEN
    _PR-ACC @ FP32>FP16 ;

\ =====================================================================
\  PROB-UNIFORM-PDF / PROB-UNIFORM-CDF
\ =====================================================================

: PROB-UNIFORM-PDF  ( x a b -- p )
    FP16>FP32 _PR-C !   \ b as FP32
    FP16>FP32 _PR-B !   \ a as FP32
    FP16>FP32 _PR-A !   \ x as FP32
    \ Check x < a or x > b
    _PR-A @ _PR-B @ FP32< IF FP16-POS-ZERO EXIT THEN
    _PR-A @ _PR-C @ FP32> IF FP16-POS-ZERO EXIT THEN
    \ 1 / (b - a)
    _PR-C @ _PR-B @ FP32-SUB
    DUP FP32-0= IF DROP FP16-POS-ZERO EXIT THEN
    FP32-ONE SWAP FP32-DIV FP32>FP16 ;

: PROB-UNIFORM-CDF  ( x a b -- p )
    \ p = (x - a) / (b - a), clamped to [0, 1]
    FP16>FP32 _PR-C !   \ b
    FP16>FP32 _PR-B !   \ a
    FP16>FP32 _PR-A !   \ x
    _PR-C @ _PR-B @ FP32-SUB    \ b - a
    DUP FP32-0= IF DROP FP16-POS-ZERO EXIT THEN
    _PR-A @ _PR-B @ FP32-SUB    \ x - a
    SWAP FP32-DIV                \ (x-a)/(b-a)
    \ Clamp to [0, 1]
    DUP FP32-ZERO FP32< IF DROP FP32-ZERO THEN
    DUP FP32-ONE FP32> IF DROP FP32-ONE THEN
    FP32>FP16 ;

\ =====================================================================
\  PROB-EXPONENTIAL-CDF
\ =====================================================================
\  F(x) = 1 - exp(-lambda * x) for x >= 0, else 0

: PROB-EXPONENTIAL-CDF  ( x lambda -- p )
    \ Check x < 0
    OVER 15 RSHIFT 0 > IF 2DROP FP16-POS-ZERO EXIT THEN
    FP16-MUL FP16-NEG EXP-EXP   \ exp(-lambda*x)
    FP16-POS-ONE SWAP FP16-SUB ; \ 1 - exp(...)

\ =====================================================================
\  PROB-POISSON-PMF
\ =====================================================================
\  P(X=k) = exp(-lambda) * lambda^k / k!
\  Computed in log space to avoid overflow:
\  ln P = -lambda + k*ln(lambda) - ln(k!)

: PROB-POISSON-PMF  ( k lambda -- p )
    \ k is integer, lambda is FP16
    SWAP _PR-I !  \ k
    FP16>FP32 _PR-A !  \ lambda as FP32

    \ ln(P) = -lambda + k * ln(lambda) - ln(k!)
    _PR-A @ FP32-NEGATE _PR-ACC !           \ -lambda
    _PR-A @ FP32>FP16 EXP-LN FP16>FP32     \ ln(lambda)
    _PR-I @ INT>FP32 FP32-MUL               \ k * ln(lambda)
    _PR-ACC @ SWAP FP32-ADD _PR-ACC !

    _PR-I @ COMB-LOG-FACTORIAL FP16>FP32    \ ln(k!)
    _PR-ACC @ SWAP FP32-SUB _PR-ACC !

    \ P = exp(ln_P)
    _PR-ACC @ FP32>FP16 EXP-EXP ;

\ =====================================================================
\  PROB-BINOMIAL-PMF
\ =====================================================================
\  P(X=k) = C(n,k) * p^k * (1-p)^(n-k)
\  Computed in log space:
\  ln P = ln(C(n,k)) + k*ln(p) + (n-k)*ln(1-p)

: PROB-BINOMIAL-PMF  ( k n p -- prob )
    \ k is integer, n is integer, p is FP16
    FP16>FP32 _PR-C !   \ p as FP32
    _PR-N !              \ n
    _PR-I !              \ k

    \ ln(C(n,k))
    _PR-N @ _PR-I @ COMB-LOG-CHOOSE FP16>FP32 _PR-ACC !

    \ + k * ln(p)
    _PR-C @ FP32>FP16 EXP-LN FP16>FP32
    _PR-I @ INT>FP32 FP32-MUL
    _PR-ACC @ SWAP FP32-ADD _PR-ACC !

    \ + (n-k) * ln(1-p)
    FP32-ONE _PR-C @ FP32-SUB
    FP32>FP16 EXP-LN FP16>FP32
    _PR-N @ _PR-I @ - INT>FP32 FP32-MUL
    _PR-ACC @ SWAP FP32-ADD _PR-ACC !

    _PR-ACC @ FP32>FP16 EXP-EXP ;

\ =====================================================================
\  _PR-T-CDF — Approximate Student's t CDF
\ =====================================================================
\  For large df (>30), approximate as normal.
\  For smaller df, use the approximation:
\    Φ_t(t, ν) ≈ Φ(t * (1 - 1/(4ν)))   for ν >= 5
\  For ν < 5, use a beta-function series (truncated).
\  We'll use the normal approx for all df — sufficient for FP16.

: _PR-T-CDF  ( t-fp32 df -- p-fp16 )
    \ Cornish-Fisher approximation:
    \ z = t * sqrt(1 - 1/(4*df))  ... simplified
    \ For moderate df this is accurate to FP16 precision.
    INT>FP32 _PR-A !     \ df as FP32
    _PR-B !              \ t as FP32
    \ correction = 1 - 1/(4*df)
    4 INT>FP32 _PR-A @ FP32-MUL   \ 4*df
    FP32-ONE SWAP FP32-DIV         \ 1/(4*df)
    FP32-ONE SWAP FP32-SUB         \ 1 - 1/(4*df)
    FP32-SQRT                      \ sqrt(...)
    _PR-B @ FP32-MUL               \ t * sqrt(...)
    FP32>FP16 PROB-STANDARD-CDF ;

\ Two-tailed p-value from t-statistic
: _PR-T-PVALUE  ( t-fp32 df -- p-fp16 )
    >R FP32-ABS R> _PR-T-CDF    \ Φ(|t|, df)
    FP16>FP32
    FP32-ONE SWAP FP32-SUB          \ 1 - Φ(|t|)
    _PR-FP32-TWO FP32-MUL           \ 2 * (1 - Φ)
    FP32>FP16 ;

\ =====================================================================
\  PROB-T-TEST-1 — One-Sample t-Test
\ =====================================================================
\  H0: mean = mu0
\  t = (x_bar - mu0) / (s / sqrt(n))
\  df = n - 1

: PROB-T-TEST-1  ( src n mu0 -- t-fp16 p-fp16 )
    FP16>FP32 _PR-C !    \ mu0 as FP32
    _PR-N !               \ n
    _PR-SRC !             \ src

    \ Mean (FP32)
    _PR-SRC @ _PR-N @ _STAT-MEAN-FP32 _PR-A !

    \ Sample stddev (FP16 → FP32)
    _PR-SRC @ _PR-N @ STAT-STDDEV-S FP16>FP32 _PR-B !

    \ SEM = s / sqrt(n), t = (mean - mu0) / SEM
    _PR-N @ INT>FP32 FP32-SQRT _PR-D !  \ sqrt(n)
    _PR-B @ _PR-D @ FP32-DIV       \ SEM = s / sqrt(n)
    DUP FP32-0= IF
        DROP _PR-A @ _PR-C @ FP32-SUB  \ mean - mu0
        DUP FP32-0= IF
            DROP FP16-POS-ZERO FP16-POS-ZERO   \ 0/0 → t=0, p=0
        ELSE
            31 RSHIFT IF FP16-NEG-INF ELSE FP16-POS-INF THEN
            FP16-POS-ZERO                       \ t=±inf, p=0
        THEN
        EXIT
    THEN
    _PR-A @ _PR-C @ FP32-SUB SWAP FP32-DIV   \ t = (mean-mu0)/SEM
    _PR-ACC !

    \ p-value (two-tailed)
    _PR-ACC @ FP32>FP16               \ t as FP16
    _PR-ACC @ _PR-N @ 1 - _PR-T-PVALUE ;  \ p-value

\ =====================================================================
\  PROB-T-TEST-2 — Two-Sample Welch's t-Test
\ =====================================================================
\  t = (x_bar - y_bar) / sqrt(sx²/nx + sy²/ny)
\  df = Welch-Satterthwaite (approx as min(nx,ny) - 1 for simplicity)

: PROB-T-TEST-2  ( x nx y ny -- t-fp16 p-fp16 )
    _PR-D !   \ ny
    _PR-SRC2 !  \ y
    _PR-N !    \ nx
    _PR-SRC !  \ x

    \ Means
    _PR-SRC @ _PR-N @ _STAT-MEAN-FP32 _PR-A !    \ x_bar
    _PR-SRC2 @ _PR-D @ _STAT-MEAN-FP32 _PR-B !   \ y_bar

    \ Sample variances
    _PR-SRC @ _PR-N @ STAT-VARIANCE-S FP16>FP32 _PR-C !   \ sx²
    _PR-SRC2 @ _PR-D @ STAT-VARIANCE-S FP16>FP32           \ sy²

    \ SE = sqrt(sx²/nx + sy²/ny)
    _PR-C @ _PR-N @ INT>FP32 FP32-DIV     \ sx²/nx
    SWAP _PR-D @ INT>FP32 FP32-DIV        \ sy²/ny
    FP32-ADD FP32-SQRT                     \ SE

    DUP FP32-0= IF
        DROP _PR-A @ _PR-B @ FP32-SUB FP32>FP16
        FP16-POS-ZERO EXIT
    THEN

    _PR-A @ _PR-B @ FP32-SUB SWAP FP32-DIV   \ t = (x_bar-y_bar)/SE
    _PR-ACC !

    \ df ≈ min(nx, ny) - 1  (conservative)
    _PR-N @ _PR-D @ MIN 1 -

    _PR-ACC @ FP32>FP16
    SWAP >R _PR-ACC @ R> _PR-T-PVALUE ;

\ =====================================================================
\  PROB-T-TEST-PAIRED — Paired t-Test
\ =====================================================================
\  Compute d[i] = x[i] - y[i], then one-sample test on d with mu0=0.

: PROB-T-TEST-PAIRED  ( x y n -- t-fp16 p-fp16 )
    _PR-N !  _PR-SRC2 !  _PR-SRC !

    \ Compute differences into _STAT-SCR0
    _PR-SRC @  _PR-SRC2 @  _STAT-SCR0 _PR-N @ SIMD-SUB-N

    \ One-sample t-test on differences with mu0 = 0
    _STAT-SCR0 _PR-N @ FP16-POS-ZERO PROB-T-TEST-1 ;

\ =====================================================================
\  PROB-CHI2-GOF — Chi-Squared Goodness of Fit
\ =====================================================================
\  chi2 = sum((O[i] - E[i])^2 / E[i])
\  p-value from chi2 distribution with df = n-1

: PROB-CHI2-GOF  ( observed expected n -- chi2-fp16 p-fp16 )
    _PR-N !  _PR-SRC2 !  _PR-SRC !

    FP32-ZERO _PR-ACC !
    0 _PR-I !
    BEGIN _PR-I @ _PR-N @ < WHILE
        _PR-SRC @ _PR-I @ 2 * + W@ FP16>FP32     \ O[i]
        _PR-SRC2 @ _PR-I @ 2 * + W@ FP16>FP32    \ E[i]
        DUP FP32-0= IF
            2DROP
        ELSE
            2DUP FP32-SUB         \ O - E
            DUP FP32-MUL          \ (O-E)^2
            SWAP FP32-DIV         \ (O-E)^2 / E
            _PR-ACC @ SWAP FP32-ADD _PR-ACC !
        THEN
        _PR-I @ 1 + _PR-I !
    REPEAT

    _PR-ACC @ FP32>FP16     \ chi2 as FP16

    \ p-value: approximate using normal for large df
    \ For chi2 with df=k: z ≈ (chi2/k)^(1/3) - (1 - 2/(9k)) / sqrt(2/(9k))
    \ Simplified: just use 1 - Φ(sqrt(2*chi2) - sqrt(2*df-1))
    \ Wilson-Hilferty approximation for large df
    DUP FP16>FP32 _PR-A !
    _PR-N @ 1 - INT>FP32 _PR-B !       \ df = n-1

    \ z ≈ sqrt(2*chi2) - sqrt(2*df - 1)
    _PR-A @ _PR-FP32-TWO FP32-MUL FP32-SQRT
    _PR-B @ _PR-FP32-TWO FP32-MUL FP32-ONE FP32-SUB FP32-SQRT
    FP32-SUB
    FP32>FP16 PROB-STANDARD-CDF      \ Φ(z)
    FP16>FP32 FP32-ONE SWAP FP32-SUB FP32>FP16 ;   \ 1 - Φ(z)

\ =====================================================================
\  PROB-CI-MEAN — Confidence Interval for the Mean
\ =====================================================================
\  CI = x_bar ± z_(alpha/2) * s / sqrt(n)
\  alpha is FP16 (e.g., 0.05 for 95% CI).
\  Returns lo and hi as FP16.

: PROB-CI-MEAN  ( src n alpha -- lo-fp16 hi-fp16 )
    \ z-critical: Φ⁻¹(1 - alpha/2)
    FP16>FP32 _PR-FP32-HALF FP32-MUL    \ alpha/2
    FP32-ONE SWAP FP32-SUB FP32>FP16     \ 1 - alpha/2
    PROB-NORMAL-INV FP16>FP32 _PR-C !    \ z-critical (FP32)

    _PR-N !  _PR-SRC !

    \ Mean (FP32)
    _PR-SRC @ _PR-N @ _STAT-MEAN-FP32 _PR-A !

    \ SEM = s / sqrt(n) (FP32)
    _PR-SRC @ _PR-N @ STAT-STDDEV-S FP16>FP32
    _PR-N @ INT>FP32 FP32-SQRT FP32-DIV _PR-B !

    \ margin = z * SEM
    _PR-C @ _PR-B @ FP32-MUL _PR-D !

    \ lo = mean - margin
    _PR-A @ _PR-D @ FP32-SUB FP32>FP16

    \ hi = mean + margin
    _PR-A @ _PR-D @ FP32-ADD FP32>FP16 ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _prob-guard

' PROB-STANDARD-PDF CONSTANT _prob-standard-pdf-xt
' PROB-STANDARD-CDF CONSTANT _prob-standard-cdf-xt
' PROB-NORMAL-PDF CONSTANT _prob-normal-pdf-xt
' PROB-NORMAL-CDF CONSTANT _prob-normal-cdf-xt
' PROB-NORMAL-INV CONSTANT _prob-normal-inv-xt
' PROB-UNIFORM-PDF CONSTANT _prob-uniform-pdf-xt
' PROB-UNIFORM-CDF CONSTANT _prob-uniform-cdf-xt
' PROB-EXPONENTIAL-CDF CONSTANT _prob-exponential-cdf-xt
' PROB-POISSON-PMF CONSTANT _prob-poisson-pmf-xt
' PROB-BINOMIAL-PMF CONSTANT _prob-binomial-pmf-xt
' PROB-T-TEST-1   CONSTANT _prob-t-test-1-xt
' PROB-T-TEST-2   CONSTANT _prob-t-test-2-xt
' PROB-T-TEST-PAIRED CONSTANT _prob-t-test-paired-xt
' PROB-CHI2-GOF   CONSTANT _prob-chi2-gof-xt
' PROB-CI-MEAN    CONSTANT _prob-ci-mean-xt

: PROB-STANDARD-PDF _prob-standard-pdf-xt _prob-guard WITH-GUARD ;
: PROB-STANDARD-CDF _prob-standard-cdf-xt _prob-guard WITH-GUARD ;
: PROB-NORMAL-PDF _prob-normal-pdf-xt _prob-guard WITH-GUARD ;
: PROB-NORMAL-CDF _prob-normal-cdf-xt _prob-guard WITH-GUARD ;
: PROB-NORMAL-INV _prob-normal-inv-xt _prob-guard WITH-GUARD ;
: PROB-UNIFORM-PDF _prob-uniform-pdf-xt _prob-guard WITH-GUARD ;
: PROB-UNIFORM-CDF _prob-uniform-cdf-xt _prob-guard WITH-GUARD ;
: PROB-EXPONENTIAL-CDF _prob-exponential-cdf-xt _prob-guard WITH-GUARD ;
: PROB-POISSON-PMF _prob-poisson-pmf-xt _prob-guard WITH-GUARD ;
: PROB-BINOMIAL-PMF _prob-binomial-pmf-xt _prob-guard WITH-GUARD ;
: PROB-T-TEST-1   _prob-t-test-1-xt _prob-guard WITH-GUARD ;
: PROB-T-TEST-2   _prob-t-test-2-xt _prob-guard WITH-GUARD ;
: PROB-T-TEST-PAIRED _prob-t-test-paired-xt _prob-guard WITH-GUARD ;
: PROB-CHI2-GOF   _prob-chi2-gof-xt _prob-guard WITH-GUARD ;
: PROB-CI-MEAN    _prob-ci-mean-xt _prob-guard WITH-GUARD ;
[THEN] [THEN]
