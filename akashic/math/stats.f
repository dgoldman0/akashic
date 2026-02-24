\ =================================================================
\  stats.f  —  Descriptive statistics for FP16 arrays in HBW
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: STAT-
\  Depends on: fp16.f fp16-ext.f fp32.f accum.f simd.f simd-ext.f sort.f
\
\  Load with:   REQUIRE stats.f

REQUIRE fp16.f
REQUIRE fp16-ext.f
REQUIRE fp32.f
REQUIRE accum.f
REQUIRE simd.f
REQUIRE simd-ext.f
REQUIRE sort.f

PROVIDED akashic-stats
\
\  Mixed-precision pipeline:
\    FP16 data → tile reductions (FP32 per tile) → accum.f (48.16)
\    → fp32.f (final arithmetic) → FP16 output
\
\  Public API:
\
\  Central tendency:
\   STAT-MEAN        ( src n -- mean )      arithmetic mean
\   STAT-MEDIAN      ( src n -- med )       median (non-destructive)
\
\  Dispersion:
\   STAT-VARIANCE    ( src n -- var )       population variance
\   STAT-VARIANCE-S  ( src n -- var )       sample variance (n-1)
\   STAT-STDDEV      ( src n -- sd )        population stddev
\   STAT-STDDEV-S    ( src n -- sd )        sample stddev
\   STAT-SEM         ( src n -- sem )       standard error of mean
\   STAT-MIN         ( src n -- min )       minimum value
\   STAT-MAX         ( src n -- max )       maximum value
\   STAT-RANGE       ( src n -- range )     max - min
\   STAT-ARGMIN      ( src n -- idx )       index of minimum
\   STAT-ARGMAX      ( src n -- idx )       index of maximum
\
\  Shape & percentiles:
\   STAT-PERCENTILE  ( src n p -- val )     p-th percentile (0–100)
\   STAT-QUARTILES   ( src n -- q1 q2 q3 ) all three quartiles
\   STAT-FIVE-NUM    ( src n -- min q1 med q3 max )
\
\  Bivariate:
\   STAT-COVARIANCE  ( x y n -- cov )      population covariance
\   STAT-CORRELATION ( x y n -- r )        Pearson correlation
\   STAT-COSINE-SIM  ( x y n -- sim )      cosine similarity
\   STAT-EUCLIDEAN   ( x y n -- dist )     Euclidean distance
\
\  Online / streaming (Welford + Chan):
\   STAT-ONLINE-SIZE  ( -- 64 )
\   STAT-ONLINE-INIT  ( ctx -- )
\   STAT-ONLINE-PUSH  ( ctx val -- )       add one observation
\   STAT-ONLINE-PUSH-N ( ctx src n -- )    add N observations (SIMD)
\   STAT-ONLINE-MEAN   ( ctx -- mean )
\   STAT-ONLINE-VARIANCE ( ctx -- var )
\   STAT-ONLINE-STDDEV ( ctx -- sd )
\   STAT-ONLINE-COUNT  ( ctx -- n )
\   STAT-ONLINE-MIN    ( ctx -- min )
\   STAT-ONLINE-MAX    ( ctx -- max )
\   STAT-ONLINE-MERGE  ( ctx1 ctx2 dst -- )
\   STAT-ONLINE-RESET  ( ctx -- )
\
\  All src/x/y addresses are HBW pointers to FP16 arrays.
\  Returned values are FP16 unless noted otherwise.
\ =================================================================

\ =====================================================================
\  Scratch buffers in HBW (reused by each stats call)
\ =====================================================================

2048 CONSTANT _STAT-MAX-N

_STAT-MAX-N 2 * HBW-ALLOT CONSTANT _STAT-SCR0    \ copy / temp
_STAT-MAX-N 2 * HBW-ALLOT CONSTANT _STAT-SCR1    \ deviations / temp

\ Shared working variables
VARIABLE _STAT-SRC
VARIABLE _STAT-SRC2
VARIABLE _STAT-N

\ =====================================================================
\  Central Tendency
\ =====================================================================

\ Internal: mean as FP32 (used by variance, correlation, etc.)
: _STAT-MEAN-FP32  ( src n -- mean-fp32 )
    DUP 0= IF 2DROP FP32-ZERO EXIT THEN
    DUP >R
    SIMD-SUM-N
    R> INT>FP32
    FP32-DIV ;

\ STAT-MEAN — arithmetic mean, returned as FP16
: STAT-MEAN  ( src n -- mean-fp16 )
    DUP 0= IF 2DROP FP16-POS-ZERO EXIT THEN
    DUP 1 = IF DROP W@ EXIT THEN
    _STAT-MEAN-FP32 FP32>FP16 ;

\ STAT-MEDIAN — median via sort on scratch copy (non-destructive)
: STAT-MEDIAN  ( src n -- median-fp16 )
    DUP 0= IF 2DROP FP16-POS-ZERO EXIT THEN
    DUP 1 = IF DROP W@ EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-SCR0 _STAT-N @ SIMD-COPY-N
    _STAT-SCR0 _STAT-N @ SORT-FP16
    _STAT-N @ 2 MOD IF
        \ Odd: middle element
        _STAT-SCR0  _STAT-N @ 2 / 2 * + W@
    ELSE
        \ Even: average of two middle elements
        _STAT-N @ 2 / DUP
        1- 2 * _STAT-SCR0 + W@        ( k val_lo )
        SWAP 2 * _STAT-SCR0 + W@      ( val_lo val_hi )
        FP16-ADD FP16-POS-HALF FP16-MUL
    THEN ;

\ =====================================================================
\  Dispersion
\ =====================================================================

\ Internal: sum of squared deviations from mean-fp32
\  Fills SCR0 with FP16(mean), computes src - SCR0 → SCR1,
\  then SIMD-SUMSQ-N(SCR1, n) → FP32.
: _STAT-SS  ( src n mean-fp32 -- ss-fp32 )
    FP32>FP16 >R
    _STAT-N !  _STAT-SRC !
    _STAT-SCR0 R> _STAT-N @ SIMD-FILL-N
    _STAT-SRC @ _STAT-SCR0 _STAT-SCR1 _STAT-N @ SIMD-SUB-N
    _STAT-SCR1 _STAT-N @ SIMD-SUMSQ-N ;

\ STAT-VARIANCE — population variance = SS / n
: STAT-VARIANCE  ( src n -- var-fp16 )
    DUP 2 < IF 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-N @
    2DUP _STAT-MEAN-FP32               ( src n mean-fp32 )
    _STAT-SS                           ( ss-fp32 )
    _STAT-N @ INT>FP32
    FP32-DIV FP32>FP16 ;

\ STAT-VARIANCE-S — sample variance = SS / (n-1)
: STAT-VARIANCE-S  ( src n -- var-fp16 )
    DUP 2 < IF 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-N @
    2DUP _STAT-MEAN-FP32
    _STAT-SS
    _STAT-N @ 1- INT>FP32
    FP32-DIV FP32>FP16 ;

\ STAT-STDDEV — population standard deviation = sqrt(variance)
: STAT-STDDEV  ( src n -- sd-fp16 )
    DUP 2 < IF 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-N @
    2DUP _STAT-MEAN-FP32
    _STAT-SS
    _STAT-N @ INT>FP32
    FP32-DIV FP32-SQRT FP32>FP16 ;

\ STAT-STDDEV-S — sample standard deviation
: STAT-STDDEV-S  ( src n -- sd-fp16 )
    DUP 2 < IF 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-N @
    2DUP _STAT-MEAN-FP32
    _STAT-SS
    _STAT-N @ 1- INT>FP32
    FP32-DIV FP32-SQRT FP32>FP16 ;

\ STAT-SEM — standard error of mean = stddev_s / sqrt(n)
: STAT-SEM  ( src n -- sem-fp16 )
    DUP 2 < IF 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-N @
    2DUP _STAT-MEAN-FP32
    _STAT-SS
    _STAT-N @ 1- INT>FP32
    FP32-DIV FP32-SQRT                 ( sd-fp32 )
    _STAT-N @ INT>FP32 FP32-SQRT      ( sd sqrtn )
    FP32-DIV FP32>FP16 ;

\ STAT-MIN — minimum (tile-accelerated)
: STAT-MIN  ( src n -- min-fp16 )
    DUP 0= IF 2DROP FP16-POS-INF EXIT THEN
    SIMD-MIN-N ;

\ STAT-MAX — maximum (tile-accelerated)
: STAT-MAX  ( src n -- max-fp16 )
    DUP 0= IF 2DROP FP16-NEG-INF EXIT THEN
    SIMD-MAX-N ;

\ STAT-RANGE — max - min
: STAT-RANGE  ( src n -- range-fp16 )
    DUP 0= IF 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-N @ SIMD-MAX-N
    _STAT-SRC @ _STAT-N @ SIMD-MIN-N
    FP16-SUB ;

\ STAT-ARGMIN — index of minimum (linear scan)
VARIABLE _SARG-BEST
VARIABLE _SARG-IDX

: STAT-ARGMIN  ( src n -- idx )
    DUP 0= IF 2DROP 0 EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ W@ _SARG-BEST !
    0 _SARG-IDX !
    _STAT-N @ 1 DO
        _STAT-SRC @ I 2 * + W@
        DUP _SARG-BEST @ FP16-LT IF
            _SARG-BEST !
            I _SARG-IDX !
        ELSE
            DROP
        THEN
    LOOP
    _SARG-IDX @ ;

\ STAT-ARGMAX — index of maximum (linear scan)
: STAT-ARGMAX  ( src n -- idx )
    DUP 0= IF 2DROP 0 EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ W@ _SARG-BEST !
    0 _SARG-IDX !
    _STAT-N @ 1 DO
        _STAT-SRC @ I 2 * + W@
        DUP _SARG-BEST @ FP16-GT IF
            _SARG-BEST !
            I _SARG-IDX !
        ELSE
            DROP
        THEN
    LOOP
    _SARG-IDX @ ;

\ =====================================================================
\  Shape & Percentiles
\ =====================================================================

\ STAT-PERCENTILE — p-th percentile (0–100) via sort
\  Uses nearest-rank: k = p * n / 100, clamped to [0, n-1]
: STAT-PERCENTILE  ( src n p -- val-fp16 )
    >R
    DUP 0= IF R> DROP 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-SCR0 _STAT-N @ SIMD-COPY-N
    _STAT-SCR0 _STAT-N @ SORT-FP16
    R> _STAT-N @ * 100 /
    DUP 0 < IF DROP 0 THEN
    DUP _STAT-N @ 1- > IF DROP _STAT-N @ 1- THEN
    2 * _STAT-SCR0 + W@ ;

\ STAT-QUARTILES — Q1, Q2, Q3 (sort once, then index)
: STAT-QUARTILES  ( src n -- q1 q2 q3 )
    DUP 0= IF 2DROP FP16-POS-ZERO FP16-POS-ZERO FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-SCR0 _STAT-N @ SIMD-COPY-N
    _STAT-SCR0 _STAT-N @ SORT-FP16
    \ Q1 at index n*25/100
    _STAT-N @ 25 * 100 /
    DUP _STAT-N @ 1- > IF DROP _STAT-N @ 1- THEN
    2 * _STAT-SCR0 + W@
    \ Q2 at index n*50/100
    _STAT-N @ 50 * 100 /
    DUP _STAT-N @ 1- > IF DROP _STAT-N @ 1- THEN
    2 * _STAT-SCR0 + W@
    \ Q3 at index n*75/100
    _STAT-N @ 75 * 100 /
    DUP _STAT-N @ 1- > IF DROP _STAT-N @ 1- THEN
    2 * _STAT-SCR0 + W@ ;

\ STAT-FIVE-NUM — min, Q1, median, Q3, max
: STAT-FIVE-NUM  ( src n -- min q1 med q3 max )
    DUP 0= IF 2DROP FP16-POS-ZERO FP16-POS-ZERO FP16-POS-ZERO
                     FP16-POS-ZERO FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC !
    _STAT-SRC @ _STAT-SCR0 _STAT-N @ SIMD-COPY-N
    _STAT-SCR0 _STAT-N @ SORT-FP16
    _STAT-SCR0 W@                                        \ min
    _STAT-N @ 25 * 100 /
    DUP _STAT-N @ 1- > IF DROP _STAT-N @ 1- THEN
    2 * _STAT-SCR0 + W@                                  \ q1
    _STAT-N @ 50 * 100 /
    DUP _STAT-N @ 1- > IF DROP _STAT-N @ 1- THEN
    2 * _STAT-SCR0 + W@                                  \ med
    _STAT-N @ 75 * 100 /
    DUP _STAT-N @ 1- > IF DROP _STAT-N @ 1- THEN
    2 * _STAT-SCR0 + W@                                  \ q3
    _STAT-SCR0 _STAT-N @ 1- 2 * + W@                    \ max
    ;

\ =====================================================================
\  Bivariate Statistics
\ =====================================================================

VARIABLE _STAT-FP32-TMP

\ Internal: cross-deviation SS  →  Sxy = sum((xi - mx)(yi - my))
\  dx = x - mean_x → SCR0,  dy = y - mean_y → SCR1
\  SIMD-DOT-N(SCR0, SCR1, n) → FP32
: _STAT-SXY  ( x y n -- sxy-fp32 )
    _STAT-N !  _STAT-SRC2 !  _STAT-SRC !
    \ mean_x → fill SCR0 with it
    _STAT-SRC @ _STAT-N @ _STAT-MEAN-FP32
    FP32>FP16 >R
    _STAT-SCR0 R> _STAT-N @ SIMD-FILL-N
    \ dx = x - mean_x → SCR0  (overwrite mean with deviations)
    _STAT-SRC @ _STAT-SCR0 _STAT-SCR0 _STAT-N @ SIMD-SUB-N
    \ mean_y → fill SCR1 with it
    _STAT-SRC2 @ _STAT-N @ _STAT-MEAN-FP32
    FP32>FP16 >R
    _STAT-SCR1 R> _STAT-N @ SIMD-FILL-N
    \ dy = y - mean_y → SCR1
    _STAT-SRC2 @ _STAT-SCR1 _STAT-SCR1 _STAT-N @ SIMD-SUB-N
    \ dot(dx, dy)
    _STAT-SCR0 _STAT-SCR1 _STAT-N @ SIMD-DOT-N ;

\ STAT-COVARIANCE — population covariance = Sxy / n
: STAT-COVARIANCE  ( x y n -- cov-fp16 )
    DUP 0= IF DROP 2DROP FP16-POS-ZERO EXIT THEN
    DUP >R
    _STAT-SXY
    R> INT>FP32 FP32-DIV FP32>FP16 ;

\ STAT-CORRELATION — Pearson r = Sxy / sqrt(Sxx * Syy)
: STAT-CORRELATION  ( x y n -- r-fp16 )
    DUP 2 < IF DROP 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC2 !  _STAT-SRC !

    \ Sxy
    _STAT-SRC @ _STAT-SRC2 @ _STAT-N @ _STAT-SXY
    _STAT-FP32-TMP !

    \ Sxx = sum((xi - mean_x)²)
    _STAT-SRC @ _STAT-N @
    2DUP _STAT-MEAN-FP32
    _STAT-SS                           ( sxx-fp32 )

    \ Syy = sum((yi - mean_y)²)
    _STAT-SRC2 @ _STAT-N @
    2DUP _STAT-MEAN-FP32
    _STAT-SS                           ( sxx syy )

    \ r = Sxy / sqrt(Sxx * Syy)
    FP32-MUL FP32-SQRT                 \ sqrt(Sxx*Syy)
    DUP FP32-0= IF
        DROP FP16-POS-ZERO EXIT
    THEN
    _STAT-FP32-TMP @ SWAP
    FP32-DIV FP32>FP16 ;

\ STAT-COSINE-SIM — dot(x,y) / (||x|| * ||y||)
: STAT-COSINE-SIM  ( x y n -- sim-fp16 )
    DUP 0= IF DROP 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC2 !  _STAT-SRC !
    _STAT-SRC @ _STAT-SRC2 @ _STAT-N @ SIMD-DOT-N
    _STAT-FP32-TMP !
    _STAT-SRC @ _STAT-N @ SIMD-SUMSQ-N
    _STAT-SRC2 @ _STAT-N @ SIMD-SUMSQ-N
    FP32-MUL FP32-SQRT
    DUP FP32-0= IF
        DROP FP16-POS-ZERO EXIT
    THEN
    _STAT-FP32-TMP @ SWAP
    FP32-DIV FP32>FP16 ;

\ STAT-EUCLIDEAN — sqrt(sum((xi - yi)²))
: STAT-EUCLIDEAN  ( x y n -- dist-fp16 )
    DUP 0= IF DROP 2DROP FP16-POS-ZERO EXIT THEN
    _STAT-N !  _STAT-SRC2 !  _STAT-SRC !
    _STAT-SRC @ _STAT-SRC2 @ _STAT-SCR0 _STAT-N @ SIMD-SUB-N
    _STAT-SCR0 _STAT-N @ SIMD-SUMSQ-N
    FP32-SQRT FP32>FP16 ;

\ =====================================================================
\  Online / Streaming Statistics (Welford + Chan)
\ =====================================================================
\
\  Context layout (8 cells × 8 bytes = 64 bytes):
\    +0   n     — observation count (integer)
\    +8   mean  — running mean (FP32, in low 32 bits)
\   +16   m2    — running M2 (FP32: Σ(xi-mean)²)
\   +24   min   — running minimum (FP16, in low 16 bits)
\   +32   max   — running maximum (FP16, in low 16 bits)
\   +40   sum   — running sum (48.16 fixed-point)
\   +48   reserved
\   +56   reserved

64 CONSTANT STAT-ONLINE-SIZE

\ Field accessors
: _SOL-N    ( ctx -- addr )   ;
: _SOL-MEAN ( ctx -- addr )   8 + ;
: _SOL-M2   ( ctx -- addr )  16 + ;
: _SOL-MIN  ( ctx -- addr )  24 + ;
: _SOL-MAX  ( ctx -- addr )  32 + ;
: _SOL-SUM  ( ctx -- addr )  40 + ;

\ STAT-ONLINE-INIT — zero context, set min=+inf, max=-inf
: STAT-ONLINE-INIT  ( ctx -- )
    DUP 64 0 FILL
    FP16-POS-INF OVER _SOL-MIN !
    FP16-NEG-INF SWAP _SOL-MAX ! ;

: STAT-ONLINE-RESET STAT-ONLINE-INIT ;

\ Read-only accessors
: STAT-ONLINE-COUNT  ( ctx -- n )         _SOL-N @ ;
: STAT-ONLINE-MEAN   ( ctx -- mean-fp16 ) _SOL-MEAN @ FP32>FP16 ;
: STAT-ONLINE-MIN    ( ctx -- min-fp16 )  _SOL-MIN @ 0xFFFF AND ;
: STAT-ONLINE-MAX    ( ctx -- max-fp16 )  _SOL-MAX @ 0xFFFF AND ;

\ STAT-ONLINE-VARIANCE — population variance = M2 / n
: STAT-ONLINE-VARIANCE  ( ctx -- var-fp16 )
    DUP _SOL-N @ DUP 0= IF
        2DROP FP16-POS-ZERO EXIT
    THEN
    INT>FP32                           ( ctx n-fp32 )
    SWAP _SOL-M2 @                     ( n-fp32 m2-fp32 )
    SWAP FP32-DIV FP32>FP16 ;

\ STAT-ONLINE-STDDEV
: STAT-ONLINE-STDDEV  ( ctx -- sd-fp16 )
    DUP _SOL-N @ DUP 0= IF
        2DROP FP16-POS-ZERO EXIT
    THEN
    INT>FP32
    SWAP _SOL-M2 @
    SWAP FP32-DIV FP32-SQRT FP32>FP16 ;

\ ---- Welford single-element PUSH ----

VARIABLE _SOL-CTX
VARIABLE _SOL-X32
VARIABLE _SOL-DELTA
VARIABLE _SOL-DELTA2

: STAT-ONLINE-PUSH  ( ctx val-fp16 -- )
    FP16>FP32 _SOL-X32 !
    _SOL-CTX !

    \ n += 1
    _SOL-CTX @ _SOL-N  DUP @ 1+ SWAP !

    \ delta = x - old_mean
    _SOL-X32 @
    _SOL-CTX @ _SOL-MEAN @
    FP32-SUB _SOL-DELTA !

    \ mean += delta / n
    _SOL-DELTA @
    _SOL-CTX @ _SOL-N @ INT>FP32
    FP32-DIV
    _SOL-CTX @ _SOL-MEAN @ FP32-ADD
    _SOL-CTX @ _SOL-MEAN !

    \ delta2 = x - new_mean
    _SOL-X32 @
    _SOL-CTX @ _SOL-MEAN @
    FP32-SUB _SOL-DELTA2 !

    \ M2 += delta * delta2
    _SOL-DELTA @ _SOL-DELTA2 @ FP32-MUL
    _SOL-CTX @ _SOL-M2 @ FP32-ADD
    _SOL-CTX @ _SOL-M2 !

    \ sum += x (48.16 accumulator)
    _SOL-X32 @ _ACCUM-FP32>FX48
    _SOL-CTX @ _SOL-SUM @ +
    _SOL-CTX @ _SOL-SUM !

    \ Update min
    _SOL-X32 @ FP32>FP16
    DUP _SOL-CTX @ _SOL-MIN @ 0xFFFF AND FP16-LT IF
        DUP 0xFFFF AND _SOL-CTX @ _SOL-MIN !
    THEN
    \ Update max
    _SOL-CTX @ _SOL-MAX @ 0xFFFF AND FP16-GT IF
        _SOL-X32 @ FP32>FP16 0xFFFF AND _SOL-CTX @ _SOL-MAX !
    THEN ;

\ ---- Chan's parallel PUSH-N ----

VARIABLE _SPN-M2B
VARIABLE _SPN-MEANB
VARIABLE _SPN-DELTA
VARIABLE _SPN-NNEW

: STAT-ONLINE-PUSH-N  ( ctx src n -- )
    DUP 0= IF DROP 2DROP EXIT THEN
    _STAT-N !  _STAT-SRC !  _SOL-CTX !

    \ Batch mean
    _STAT-SRC @ _STAT-N @ _STAT-MEAN-FP32
    _SPN-MEANB !

    \ M2B = sum of squared deviations of batch
    _SPN-MEANB @ FP32>FP16 >R
    _STAT-SCR0 R> _STAT-N @ SIMD-FILL-N
    _STAT-SRC @ _STAT-SCR0 _STAT-SCR0 _STAT-N @ SIMD-SUB-N
    _STAT-SCR0 _STAT-N @ SIMD-SUMSQ-N
    _SPN-M2B !

    \ Batch min / max
    _STAT-SRC @ _STAT-N @ SIMD-MIN-N
    _SOL-CTX @ _SOL-MIN @ 0xFFFF AND FP16-MIN
    0xFFFF AND _SOL-CTX @ _SOL-MIN !
    _STAT-SRC @ _STAT-N @ SIMD-MAX-N
    _SOL-CTX @ _SOL-MAX @ 0xFFFF AND FP16-MAX
    0xFFFF AND _SOL-CTX @ _SOL-MAX !

    \ delta = meanB - meanA
    _SPN-MEANB @
    _SOL-CTX @ _SOL-MEAN @
    FP32-SUB _SPN-DELTA !

    \ n_new = nA + nB
    _SOL-CTX @ _SOL-N @ _STAT-N @ + _SPN-NNEW !

    \ mean_new = meanA + delta * nB / n_new
    _SPN-DELTA @
    _STAT-N @ INT>FP32 FP32-MUL
    _SPN-NNEW @ INT>FP32 FP32-DIV
    _SOL-CTX @ _SOL-MEAN @ FP32-ADD
    _SOL-CTX @ _SOL-MEAN !

    \ M2_new = M2A + M2B + delta² * nA * nB / n_new
    _SPN-DELTA @ DUP FP32-MUL
    _SOL-CTX @ _SOL-N @ INT>FP32 FP32-MUL
    _STAT-N @ INT>FP32 FP32-MUL
    _SPN-NNEW @ INT>FP32 FP32-DIV
    _SOL-CTX @ _SOL-M2 @ FP32-ADD
    _SPN-M2B @ FP32-ADD
    _SOL-CTX @ _SOL-M2 !

    \ n = n_new
    _SPN-NNEW @ _SOL-CTX @ _SOL-N !

    \ sum accumulator
    _STAT-SRC @ _STAT-N @ SIMD-SUM-N
    _ACCUM-FP32>FX48
    _SOL-CTX @ _SOL-SUM @ +
    _SOL-CTX @ _SOL-SUM ! ;

\ ---- Chan's parallel MERGE ----

VARIABLE _SOM-DELTA
VARIABLE _SOM-NNEW

: STAT-ONLINE-MERGE  ( ctx1 ctx2 dst -- )
    >R

    \ If ctx1 empty → copy ctx2 to dst
    OVER _SOL-N @ 0= IF
        DROP R> 64 0 FILL
        \ Actually just byte-copy ctx2
        DROP R> 2DROP EXIT         \ placeholder — need to copy
    THEN

    \ If ctx2 empty → copy ctx1 to dst
    DUP _SOL-N @ 0= IF
        DROP R> 2DROP EXIT
    THEN

    \ delta = mean2 - mean1
    DUP _SOL-MEAN @
    2 PICK _SOL-MEAN @
    FP32-SUB _SOM-DELTA !             ( ctx1 ctx2 )

    \ n_new
    OVER _SOL-N @  OVER _SOL-N @ + _SOM-NNEW !

    \ mean_new
    _SOM-DELTA @
    OVER _SOL-N @ INT>FP32 FP32-MUL
    _SOM-NNEW @ INT>FP32 FP32-DIV
    2 PICK _SOL-MEAN @ FP32-ADD
    R@ _SOL-MEAN !

    \ M2_new = M2_1 + M2_2 + delta² * n1 * n2 / n_new
    _SOM-DELTA @ DUP FP32-MUL
    2 PICK _SOL-N @ INT>FP32 FP32-MUL
    OVER _SOL-N @ INT>FP32 FP32-MUL
    _SOM-NNEW @ INT>FP32 FP32-DIV
    2 PICK _SOL-M2 @ FP32-ADD
    OVER _SOL-M2 @ FP32-ADD
    R@ _SOL-M2 !

    \ min, max
    OVER _SOL-MIN @ 0xFFFF AND
    OVER _SOL-MIN @ 0xFFFF AND
    FP16-MIN 0xFFFF AND R@ _SOL-MIN !
    OVER _SOL-MAX @ 0xFFFF AND
    OVER _SOL-MAX @ 0xFFFF AND
    FP16-MAX 0xFFFF AND R@ _SOL-MAX !

    \ sum, n
    OVER _SOL-SUM @ OVER _SOL-SUM @ + R@ _SOL-SUM !
    _SOM-NNEW @ R@ _SOL-N !

    R> DROP 2DROP ;
