\ =================================================================
\  advanced-stats.f — Inferential Extensions & Non-Parametric Tests
\ =================================================================
\  Megapad-64 / KDOS Forth
\
\  Prefix: ADVS-  (public API)
\          _AS-   (internal helpers)
\
\  Depends on: probability.f, stats.f, sort.f, counting.f
\              (probability.f pulls in exp.f, trig.f automatically)
\
\  Load with:   REQUIRE advanced-stats.f
\
\ === Public API ===
\
\ Public CDF:
\   PROB-T-CDF           ( t-fp16 df -- p-fp16 )   Student's t CDF
\   ADVS-F-CDF           ( f df1 df2 -- p-fp16 )   F-distribution CDF
\
\ Confidence Intervals:
\   PROB-CI-PROPORTION   ( succ n alpha -- lo hi )  Wilson score CI
\   PROB-CI-DIFF-MEANS   ( x nx y ny alpha -- lo hi ) CI for μ₁−μ₂
\
\ Effect Sizes:
\   ADVS-COHENS-D        ( x nx y ny -- d )         Cohen's d
\   ADVS-HEDGES-G        ( x nx y ny -- g )         Hedges' g
\
\ Non-Parametric Tests:
\   ADVS-MANN-WHITNEY    ( x nx y ny -- U p )       Mann-Whitney U
\   ADVS-WILCOXON        ( x y n -- W p )           Wilcoxon signed-rank
\
\ ANOVA:
\   ADVS-ANOVA-1         ( g1 n1 g2 n2 g3 n3 k -- F p ) One-way ANOVA
\
\ Multiple Comparison Correction:
\   ADVS-BONFERRONI      ( alpha k -- alpha' )       Bonferroni
\   ADVS-HOLM            ( pvals n alpha dst -- )     Holm step-down

REQUIRE probability.f

PROVIDED akashic-advanced-stats

\ =====================================================================
\  Internal state
\ =====================================================================

VARIABLE _AS-A       \ general FP32
VARIABLE _AS-B       \ general FP32
VARIABLE _AS-C       \ general FP32
VARIABLE _AS-D       \ general FP32
VARIABLE _AS-E       \ general FP32
VARIABLE _AS-ACC     \ FP32 accumulator
VARIABLE _AS-I       \ loop index
VARIABLE _AS-J       \ secondary loop index
VARIABLE _AS-N       \ count
VARIABLE _AS-N2      \ second count
VARIABLE _AS-K       \ group count / general
VARIABLE _AS-SRC     \ source pointer
VARIABLE _AS-SRC2    \ second source pointer
VARIABLE _AS-DST     \ destination pointer

\ Scratch buffer for Wilcoxon sign flags (1 cell per element)
512 8 * HBW-ALLOT CONSTANT _AS-SIGNBUF

\ =====================================================================
\  PROB-T-CDF — Public Student's t CDF
\ =====================================================================
\  Wraps the internal _PR-T-CDF, accepting FP16 t-stat.

: PROB-T-CDF  ( t-fp16 df -- p-fp16 )
    SWAP FP16>FP32 SWAP _PR-T-CDF ;

\ =====================================================================
\  ADVS-F-CDF — F-Distribution CDF
\ =====================================================================
\  Wilson-Hilferty approximation (Abramowitz & Stegun 26.6.16):
\  Let y = F^(1/3)
\      a = 1 - 2/(9*df1)
\      b = 1 - 2/(9*df2)
\      va = 2/(9*df1)
\      vb = 2/(9*df2)
\  z = (b*y - a) / sqrt(va + vb*y²)
\  P(F ≤ f) ≈ Φ(z)

: ADVS-F-CDF  ( f-fp16 df1 df2 -- p-fp16 )
    _AS-N2 !  _AS-N !             \ df1, df2
    FP16>FP32 _AS-A !             \ f as FP32

    \ y = F^(1/3)  — cube root via exp(ln(F)/3)
    _AS-A @ FP32>FP16 EXP-LN FP16>FP32    \ ln(F)
    3 INT>FP32 FP32-DIV                    \ ln(F)/3
    FP32>FP16 EXP-EXP FP16>FP32 _AS-C !   \ y = F^(1/3)

    \ a = 1 - 2/(9*df1)
    9 _AS-N @ * INT>FP32                    \ 9*df1
    _PR-FP32-TWO SWAP FP32-DIV             \ 2/(9*df1)
    DUP _AS-D !                             \ save va = 2/(9*df1)
    FP32-ONE SWAP FP32-SUB _AS-E !         \ a

    \ b = 1 - 2/(9*df2)
    9 _AS-N2 @ * INT>FP32                   \ 9*df2
    _PR-FP32-TWO SWAP FP32-DIV             \ 2/(9*df2)
    DUP _AS-ACC !                           \ save vb = 2/(9*df2)
    FP32-ONE SWAP FP32-SUB                  \ b

    \ numerator = b*y - a
    _AS-C @ FP32-MUL                        \ b*y
    _AS-E @ FP32-SUB _AS-B !               \ b*y - a

    \ denominator = sqrt(va + vb * y²)
    _AS-C @ DUP FP32-MUL                   \ y²
    _AS-ACC @ FP32-MUL                      \ vb*y²
    _AS-D @ FP32-ADD                        \ va + vb*y²
    FP32-SQRT                               \ sqrt(...)

    \ z = num / den
    _AS-B @ SWAP FP32-DIV

    FP32>FP16 PROB-STANDARD-CDF ;

\ =====================================================================
\  PROB-CI-PROPORTION — Wilson Score Interval
\ =====================================================================
\  Wilson score CI for a binomial proportion p̂ = successes/n.
\  lo, hi = (p̂ + z²/(2n) ± z·√(p̂(1-p̂)/n + z²/(4n²))) / (1 + z²/n)
\
\  successes = integer, n = integer, alpha = FP16 (e.g., 0.05)

: PROB-CI-PROPORTION  ( successes n alpha -- lo-fp16 hi-fp16 )
    \ z = Φ⁻¹(1 - alpha/2)
    FP16>FP32 _PR-FP32-HALF FP32-MUL      \ alpha/2
    FP32-ONE SWAP FP32-SUB FP32>FP16       \ 1-alpha/2
    PROB-NORMAL-INV FP16>FP32 _AS-A !      \ z as FP32

    INT>FP32 _AS-B !    \ n as FP32
    INT>FP32 _AS-C !    \ successes as FP32

    \ p-hat = successes / n
    _AS-C @ _AS-B @ FP32-DIV _AS-D !       \ p-hat

    \ z²
    _AS-A @ DUP FP32-MUL _AS-E !           \ z²

    \ center = p-hat + z²/(2n)
    _AS-E @ _PR-FP32-TWO _AS-B @ FP32-MUL FP32-DIV  \ z²/(2n)
    _AS-D @ SWAP FP32-ADD _AS-ACC !         \ center

    \ discriminant = p-hat*(1-p-hat)/n + z²/(4n²)
    FP32-ONE _AS-D @ FP32-SUB              \ 1-p-hat
    _AS-D @ FP32-MUL                        \ p-hat*(1-p-hat)
    _AS-B @ FP32-DIV                        \ .../n
    _AS-E @
    4 INT>FP32 _AS-B @ DUP FP32-MUL FP32-MUL  \ 4*n²
    FP32-DIV                                \ z²/(4n²)
    FP32-ADD FP32-SQRT                      \ sqrt(disc)
    _AS-A @ FP32-MUL _AS-C !               \ z * sqrt(disc) → margin

    \ denom = 1 + z²/n
    _AS-E @ _AS-B @ FP32-DIV FP32-ONE FP32-ADD  \ 1 + z²/n

    \ lo = (center - margin) / denom
    _AS-ACC @ _AS-C @ FP32-SUB
    OVER FP32-DIV FP32>FP16

    \ hi = (center + margin) / denom
    SWAP _AS-ACC @ _AS-C @ FP32-ADD
    SWAP FP32-DIV FP32>FP16 ;

\ =====================================================================
\  PROB-CI-DIFF-MEANS — CI for Difference of Two Means
\ =====================================================================
\  Welch's t-interval: (x̄₁ - x̄₂) ± t_(α/2,df) · SE
\  SE = sqrt(s₁²/n₁ + s₂²/n₂)
\  df = min(n₁,n₂) - 1  (conservative approximation)

: PROB-CI-DIFF-MEANS  ( x nx y ny alpha -- lo-fp16 hi-fp16 )
    \ Save alpha, compute z-critical via t-distribution approximation
    FP16>FP32 _PR-FP32-HALF FP32-MUL       \ alpha/2
    FP32-ONE SWAP FP32-SUB FP32>FP16        \ 1-alpha/2
    PROB-NORMAL-INV FP16>FP32 _AS-A !       \ z-critical (using normal approx)

    _AS-N2 !  _AS-SRC2 !  _AS-N !  _AS-SRC !

    \ Means
    _AS-SRC @ _AS-N @ _STAT-MEAN-FP32 _AS-B !     \ x-bar
    _AS-SRC2 @ _AS-N2 @ _STAT-MEAN-FP32 _AS-C !   \ y-bar

    \ SE = sqrt(s1²/n1 + s2²/n2)
    _AS-SRC @ _AS-N @ STAT-VARIANCE-S FP16>FP32
    _AS-N @ INT>FP32 FP32-DIV                      \ s1²/n1
    _AS-SRC2 @ _AS-N2 @ STAT-VARIANCE-S FP16>FP32
    _AS-N2 @ INT>FP32 FP32-DIV                     \ s2²/n2
    FP32-ADD FP32-SQRT _AS-D !                      \ SE

    \ diff = x-bar - y-bar
    _AS-B @ _AS-C @ FP32-SUB _AS-E !

    \ margin = z * SE
    _AS-A @ _AS-D @ FP32-MUL _AS-ACC !

    \ lo = diff - margin
    _AS-E @ _AS-ACC @ FP32-SUB FP32>FP16
    \ hi = diff + margin
    _AS-E @ _AS-ACC @ FP32-ADD FP32>FP16 ;

\ =====================================================================
\  ADVS-COHENS-D — Cohen's d Effect Size
\ =====================================================================
\  d = (x̄₁ - x̄₂) / s_pooled
\  s_pooled = sqrt(((n₁-1)s₁² + (n₂-1)s₂²) / (n₁+n₂-2))

: ADVS-COHENS-D  ( x nx y ny -- d-fp16 )
    _AS-N2 !  _AS-SRC2 !  _AS-N !  _AS-SRC !

    \ Means
    _AS-SRC @ _AS-N @ _STAT-MEAN-FP32 _AS-A !     \ x-bar
    _AS-SRC2 @ _AS-N2 @ _STAT-MEAN-FP32 _AS-B !   \ y-bar

    \ Sample variances
    _AS-SRC @ _AS-N @ STAT-VARIANCE-S FP16>FP32 _AS-C !    \ s1²
    _AS-SRC2 @ _AS-N2 @ STAT-VARIANCE-S FP16>FP32 _AS-D !  \ s2²

    \ Pooled variance = ((n1-1)*s1² + (n2-1)*s2²) / (n1+n2-2)
    _AS-N @ 1- INT>FP32 _AS-C @ FP32-MUL           \ (n1-1)*s1²
    _AS-N2 @ 1- INT>FP32 _AS-D @ FP32-MUL          \ (n2-1)*s2²
    FP32-ADD
    _AS-N @ _AS-N2 @ + 2 - INT>FP32 FP32-DIV       \ pooled var
    FP32-SQRT _AS-E !                                \ s_pooled

    \ Handle s_pooled = 0 (identical groups) → d = 0
    _AS-E @ FP32-0= IF FP16-POS-ZERO EXIT THEN

    \ d = (x-bar - y-bar) / s_pooled
    _AS-A @ _AS-B @ FP32-SUB
    _AS-E @ FP32-DIV FP32>FP16 ;

\ =====================================================================
\  ADVS-HEDGES-G — Bias-Corrected Effect Size
\ =====================================================================
\  g = d * (1 - 3 / (4*(n₁+n₂) - 9))

: ADVS-HEDGES-G  ( x nx y ny -- g-fp16 )
    2 PICK OVER + _AS-K !        \ k = nx + ny (save before COHENS-D)
    ADVS-COHENS-D FP16>FP32      \ d as FP32
    \ correction = 1 - 3/(4*(n1+n2) - 9)
    _AS-K @ 4 * 9 - INT>FP32     \ 4*(n1+n2)-9
    3 INT>FP32 SWAP FP32-DIV     \ 3 / ...
    FP32-ONE SWAP FP32-SUB       \ 1 - ...
    FP32-MUL FP32>FP16 ;         \ g = d * correction

\ =====================================================================
\  ADVS-MANN-WHITNEY — Mann-Whitney U Test
\ =====================================================================
\  Non-parametric two-sample test.
\  1. Merge x(nx) and y(ny) into combined array
\  2. Rank all combined values (with tie averaging)
\  3. Sum ranks belonging to x → R₁
\  4. U = R₁ - nx(nx+1)/2
\  5. Normal approximation for p-value (nx+ny > 20):
\     μ_U = nx*ny/2
\     σ_U = sqrt(nx*ny*(nx+ny+1)/12)
\     z = (U - μ_U) / σ_U
\
\  Uses _STAT-SCR0 for merged data, _STAT-SCR1 for ranks,
\  and a portion of memory after _STAT-SCR1 for the index array.

\ HBW scratch for rank output — reuse area after _STAT-SCR1
\ _STAT-SCR1 is _STAT-MAX-N*2 = 4096 bytes from start
\ We use _STAT-SCR1 for ranks (2048*2 = 4096 bytes)
\ Index array for argsort needs n*8 bytes — allocated after SCR1

: ADVS-MANN-WHITNEY  ( x nx y ny -- U-fp16 p-fp16 )
    _AS-N2 !  _AS-SRC2 !  _AS-N !  _AS-SRC !

    \ Total count
    _AS-N @ _AS-N2 @ + _AS-K !     \ N = nx + ny

    \ Merge x and y into _STAT-SCR0
    \ Copy x first
    _AS-N @ 0 DO
        _AS-SRC @ I 2 * + W@
        _STAT-SCR0 I 2 * + W!
    LOOP
    \ Copy y after
    _AS-N2 @ 0 DO
        _AS-SRC2 @ I 2 * + W@
        _STAT-SCR0 _AS-N @ I + 2 * + W!
    LOOP

    \ Rank the merged array, output ranks to _STAT-SCR1
    _STAT-SCR0 _STAT-SCR1 _AS-K @ SORT-RANK

    \ Sum ranks of first nx elements (those from x)
    FP32-ZERO _AS-ACC !
    _AS-N @ 0 DO
        _STAT-SCR1 I 2 * + W@ FP16>FP32
        _AS-ACC @ SWAP FP32-ADD _AS-ACC !
    LOOP
    \ R1 = sum of ranks for x group
    _AS-ACC @ _AS-A !

    \ U = R1 - nx*(nx+1)/2
    _AS-N @ _AS-N @ 1+ * 2 / INT>FP32
    _AS-A @ SWAP FP32-SUB _AS-B !      \ U as FP32

    \ Normal approximation
    \ mu_U = nx * ny / 2
    _AS-N @ _AS-N2 @ * INT>FP32
    _PR-FP32-HALF FP32-MUL _AS-C !     \ mu_U

    \ sigma_U = sqrt(nx*ny*(N+1)/12)
    _AS-N @ _AS-N2 @ * _AS-K @ 1+ * INT>FP32
    12 INT>FP32 FP32-DIV FP32-SQRT _AS-D !   \ sigma_U

    \ z = (U - mu_U) / sigma_U
    _AS-B @ _AS-C @ FP32-SUB
    _AS-D @ FP32-DIV _AS-E !          \ z as FP32

    \ U as FP16
    _AS-B @ FP32>FP16

    \ p-value = 2 * Φ(-|z|)  two-tailed (avoids 1-CDF cancellation)
    _AS-E @ FP32-ABS FP32-NEGATE FP32>FP16 PROB-STANDARD-CDF
    FP16>FP32 _PR-FP32-TWO FP32-MUL FP32>FP16 ;

\ =====================================================================
\  ADVS-WILCOXON — Wilcoxon Signed-Rank Test
\ =====================================================================
\  Paired non-parametric test.
\  1. Compute d[i] = x[i] - y[i]
\  2. Drop zeros
\  3. Rank |d[i]|
\  4. W+ = sum of ranks where d[i] > 0
\  5. Normal approximation: z = (W+ - n'(n'+1)/4) / sqrt(n'(n'+1)(2n'+1)/24)

: ADVS-WILCOXON  ( x y n -- W-fp16 p-fp16 )
    _AS-N !  _AS-SRC2 !  _AS-SRC !

    \ Compute differences → _STAT-SCR0 (as FP16)
    \ Also compute |d[i]| → _STAT-SCR1, and keep sign info
    \ We store signs in a separate variable array approach:
    \ actually, we'll two-pass: first compute abs-diffs and count non-zero,
    \ then rank abs-diffs, then walk and sum W+.

    \ Pass 1: compute |d[i]| into _STAT-SCR0 (skip zeros)
    \         store sign flags (positive=1) as integer cells
    \         after _STAT-SCR1 area (at _STAT-SCR1 + 4096)
    0 _AS-K !    \ count of non-zero differences
    _AS-N @ 0 DO
        _AS-SRC @ I 2 * + W@
        _AS-SRC2 @ I 2 * + W@
        FP16-SUB            \ d[i] as FP16

        DUP FP16-POS-ZERO = IF
            DROP   \ skip zero differences
        ELSE
            DUP 15 RSHIFT 0= IF
                \ positive
                FP16-ABS _STAT-SCR0 _AS-K @ 2 * + W!
                1 _AS-SIGNBUF _AS-K @ 8 * + !   \ sign = positive
            ELSE
                \ negative
                FP16-ABS _STAT-SCR0 _AS-K @ 2 * + W!
                0 _AS-SIGNBUF _AS-K @ 8 * + !   \ sign = negative
            THEN
            _AS-K @ 1+ _AS-K !
        THEN
    LOOP

    \ Handle degenerate case: all diffs zero
    _AS-K @ 0= IF
        FP16-POS-ZERO FP16-POS-ONE EXIT
    THEN

    \ Rank |d[i]| — output to _STAT-SCR1
    _STAT-SCR0 _STAT-SCR1 _AS-K @ SORT-RANK

    \ W+ = sum of ranks where d[i] was positive
    FP32-ZERO _AS-ACC !
    _AS-K @ 0 DO
        _AS-SIGNBUF I 8 * + @    \ sign flag
        IF
            _STAT-SCR1 I 2 * + W@ FP16>FP32
            _AS-ACC @ SWAP FP32-ADD _AS-ACC !
        THEN
    LOOP
    _AS-ACC @ _AS-A !    \ W+ as FP32

    \ Normal approximation (n' = _AS-K, number of non-zero diffs)
    \ mu = n'(n'+1)/4
    _AS-K @ _AS-K @ 1+ * INT>FP32
    4 INT>FP32 FP32-DIV _AS-B !               \ mu

    \ sigma = sqrt(n'(n'+1)(2n'+1)/24)
    _AS-K @ _AS-K @ 1+ * _AS-K @ 2 * 1+ * INT>FP32
    24 INT>FP32 FP32-DIV FP32-SQRT _AS-C !    \ sigma

    \ z = (W+ - mu) / sigma
    _AS-A @ _AS-B @ FP32-SUB
    _AS-C @ FP32-DIV _AS-D !      \ z as FP32

    \ W+ as FP16
    _AS-A @ FP32>FP16

    \ p-value = 2 * \u03a6(-|z|)  two-tailed
    _AS-D @ FP32-ABS FP32-NEGATE FP32>FP16 PROB-STANDARD-CDF
    FP16>FP32 _PR-FP32-TWO FP32-MUL FP32>FP16 ;

\ =====================================================================
\  ADVS-ANOVA-1 — One-Way Analysis of Variance
\ =====================================================================
\  Accepts groups as stack parameters: ( g1 n1 g2 n2 ... gk nk k -- F p )
\  where each gi is an HBW pointer and ni is the group size.
\  k = number of groups (2..6).
\
\  F = MSB / MSW
\  MSB = SSB / (k-1)
\  MSW = SSW / (N-k)
\  SSB = Σ nⱼ(x̄ⱼ - x̄)²
\  SSW = Σ (nⱼ-1)sⱼ²
\
\  For simplicity, we support 2–6 groups by storing params in variables.

VARIABLE _AN-G1   VARIABLE _AN-N1
VARIABLE _AN-G2   VARIABLE _AN-N2
VARIABLE _AN-G3   VARIABLE _AN-N3
VARIABLE _AN-G4   VARIABLE _AN-N4
VARIABLE _AN-G5   VARIABLE _AN-N5
VARIABLE _AN-G6   VARIABLE _AN-N6
VARIABLE _AN-K                  \ number of groups
VARIABLE _AN-NTOT               \ total N

\ We store group addr/len arrays at fixed offsets for indexed access
\ _AN-G1 through _AN-G6 are consecutive VARIABLEs (8 bytes apart)

: _AN-SET-GROUP  ( addr n idx -- )
    \ Store group addr and n at index idx (0-based)
    CASE
        0 OF _AN-N1 !  _AN-G1 ! ENDOF
        1 OF _AN-N2 !  _AN-G2 ! ENDOF
        2 OF _AN-N3 !  _AN-G3 ! ENDOF
        3 OF _AN-N4 !  _AN-G4 ! ENDOF
        4 OF _AN-N5 !  _AN-G5 ! ENDOF
        5 OF _AN-N6 !  _AN-G6 ! ENDOF
    ENDCASE ;

: _AN-GET-GROUP  ( idx -- addr n )
    CASE
        0 OF _AN-G1 @ _AN-N1 @ ENDOF
        1 OF _AN-G2 @ _AN-N2 @ ENDOF
        2 OF _AN-G3 @ _AN-N3 @ ENDOF
        3 OF _AN-G4 @ _AN-N4 @ ENDOF
        4 OF _AN-G5 @ _AN-N5 @ ENDOF
        5 OF _AN-G6 @ _AN-N6 @ ENDOF
    ENDCASE ;

: ADVS-ANOVA-1  ( g1 n1 g2 n2 ... gk nk k -- F-fp16 p-fp16 )
    _AN-K !
    0 _AN-NTOT !

    \ Pop groups from stack in reverse order
    \ Stack has: g1 n1 g2 n2 ... gk nk (k already popped)
    \ We need to pop them backwards: last pair is group k-1
    _AN-K @ 1- BEGIN DUP 0>= WHILE
        >R
        \ top of stack is nk, then gk
        R@ _AN-SET-GROUP
        R@ _AN-GET-GROUP NIP   \ get n for this group
        _AN-NTOT @ + _AN-NTOT !
        R> 1-
    REPEAT DROP

    \ Grand mean
    FP32-ZERO _AS-ACC !
    _AN-K @ 0 DO
        I _AN-GET-GROUP             \ addr n
        DUP >R
        _STAT-MEAN-FP32             \ group mean as FP32
        R> INT>FP32 FP32-MUL        \ n * mean (sum for this group)
        _AS-ACC @ SWAP FP32-ADD _AS-ACC !
    LOOP
    _AS-ACC @ _AN-NTOT @ INT>FP32 FP32-DIV _AS-A !   \ grand mean

    \ SSB = Σ nⱼ * (x̄ⱼ - grand_mean)²
    FP32-ZERO _AS-ACC !
    _AN-K @ 0 DO
        I _AN-GET-GROUP             \ addr n
        DUP >R
        _STAT-MEAN-FP32             \ group mean
        _AS-A @ FP32-SUB            \ deviation
        DUP FP32-MUL                \ squared
        R> INT>FP32 FP32-MUL        \ * n
        _AS-ACC @ SWAP FP32-ADD _AS-ACC !
    LOOP
    _AS-ACC @ _AS-B !               \ SSB

    \ SSW = Σ (nⱼ-1) * sⱼ²
    FP32-ZERO _AS-ACC !
    _AN-K @ 0 DO
        I _AN-GET-GROUP             \ addr n
        STAT-VARIANCE-S FP16>FP32   \ sⱼ² as FP32
        I _AN-GET-GROUP NIP         \ n
        1- INT>FP32 FP32-MUL        \ (n-1)*sⱼ²
        _AS-ACC @ SWAP FP32-ADD _AS-ACC !
    LOOP
    _AS-ACC @ _AS-C !               \ SSW

    \ MSB = SSB / (k-1)
    _AS-B @ _AN-K @ 1- INT>FP32 FP32-DIV _AS-D !

    \ MSW = SSW / (N-k)
    _AS-C @ _AN-NTOT @ _AN-K @ - INT>FP32 FP32-DIV _AS-E !

    \ F = MSB / MSW
    _AS-D @ _AS-E @ FP32-DIV

    DUP FP32>FP16     \ F as FP16
    SWAP

    \ p-value via F-CDF: p = 1 - F_CDF(F, df1=k-1, df2=N-k)
    FP32>FP16 _AN-K @ 1- _AN-NTOT @ _AN-K @ - ADVS-F-CDF
    FP16>FP32 FP32-ONE SWAP FP32-SUB FP32>FP16 ;

\ =====================================================================
\  ADVS-BONFERRONI — Bonferroni Correction
\ =====================================================================
\  alpha' = alpha / k  (clamp to FP16 precision)

: ADVS-BONFERRONI  ( alpha-fp16 k -- alpha'-fp16 )
    >R FP16>FP32 R> INT>FP32 FP32-DIV FP32>FP16 ;

\ =====================================================================
\  ADVS-HOLM — Holm-Bonferroni Step-Down Correction
\ =====================================================================
\  Input:  pvals = HBW array of n p-values (FP16)
\          alpha = significance level (FP16)
\  Output: dst = HBW array of n flags (FP16: 1.0 if rejected, 0.0 if not)
\
\  Algorithm:
\  1. Sort p-values (keep track of original indices via argsort)
\  2. For i = 0, 1, ..., n-1:
\     Compare p_(i) to alpha / (n - i)
\     If p_(i) > threshold: stop, no more rejections
\  3. Scatter reject/accept flags back to original positions

: ADVS-HOLM  ( pvals n alpha dst -- )
    _AS-DST !
    FP16>FP32 _AS-A !     \ alpha as FP32
    _AS-N !
    _AS-SRC !

    \ Copy p-values to _STAT-SCR0 for sorting
    _AS-SRC @ _STAT-SCR0 _AS-N @ SIMD-COPY-N

    \ Argsort p-values (index array in _STAT-SCR1 area with cells)
    _STAT-SCR0 _STAT-SCR1 _AS-N @ SORT-ARGSORT

    \ Sort p-values in-place in _STAT-SCR0
    _STAT-SCR0 _AS-N @ SORT-FP16

    \ Initialize all dst to 0 (not rejected)
    _AS-N @ 0 DO
        FP16-POS-ZERO _AS-DST @ I 2 * + W!
    LOOP

    \ Step through sorted p-values
    _AS-N @ 0 DO
        \ threshold = alpha / (n - i)
        _AS-A @ _AS-N @ I - INT>FP32 FP32-DIV    \ alpha/(n-i)

        \ p_(i) — sorted p-value
        _STAT-SCR0 I 2 * + W@ FP16>FP32

        \ If p_(i) > threshold (i.e., threshold < p), stop
        FP32< IF LEAVE THEN

        \ Reject: set dst[original_index] = 1.0
        FP16-POS-ONE
        _AS-DST @ _STAT-SCR1 I 8 * + @   \ original index
        2 * + W!
    LOOP ;

\ ── Concurrency Guard ───────────────────────────────────
REQUIRE ../concurrency/guard.f
GUARD _advs-guard

' PROB-T-CDF          CONSTANT _advs-tcdf-xt
' ADVS-F-CDF          CONSTANT _advs-fcdf-xt
' PROB-CI-PROPORTION  CONSTANT _advs-ciprop-xt
' PROB-CI-DIFF-MEANS  CONSTANT _advs-cidm-xt
' ADVS-COHENS-D       CONSTANT _advs-cohen-xt
' ADVS-HEDGES-G       CONSTANT _advs-hedges-xt
' ADVS-MANN-WHITNEY   CONSTANT _advs-mw-xt
' ADVS-WILCOXON       CONSTANT _advs-wilcox-xt
' ADVS-ANOVA-1        CONSTANT _advs-anova-xt
' ADVS-BONFERRONI     CONSTANT _advs-bonf-xt
' ADVS-HOLM           CONSTANT _advs-holm-xt

: PROB-T-CDF          _advs-tcdf-xt   _advs-guard WITH-GUARD ;
: ADVS-F-CDF          _advs-fcdf-xt   _advs-guard WITH-GUARD ;
: PROB-CI-PROPORTION  _advs-ciprop-xt _advs-guard WITH-GUARD ;
: PROB-CI-DIFF-MEANS  _advs-cidm-xt   _advs-guard WITH-GUARD ;
: ADVS-COHENS-D       _advs-cohen-xt  _advs-guard WITH-GUARD ;
: ADVS-HEDGES-G       _advs-hedges-xt _advs-guard WITH-GUARD ;
: ADVS-MANN-WHITNEY   _advs-mw-xt     _advs-guard WITH-GUARD ;
: ADVS-WILCOXON       _advs-wilcox-xt _advs-guard WITH-GUARD ;
: ADVS-ANOVA-1        _advs-anova-xt  _advs-guard WITH-GUARD ;
: ADVS-BONFERRONI     _advs-bonf-xt   _advs-guard WITH-GUARD ;
: ADVS-HOLM           _advs-holm-xt   _advs-guard WITH-GUARD ;
