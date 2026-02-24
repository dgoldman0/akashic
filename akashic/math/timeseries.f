\ timeseries.f — Time Series Analysis
\
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ Prefix: TS-  (public API)
\         _TS- (internal helpers)
\
\ Depends on: stats.f, regression.f, exp.f
\             (fp16, fp16-ext, fp32, accum, simd, simd-ext, sort inferred)
\
\ Load with:   REQUIRE timeseries.f
\
\ === Public API ===
\
\ Smoothing & Moving Averages:
\   TS-SMA            ( src n window dst -- )     simple moving average
\   TS-EMA            ( src n alpha dst -- )       exponential moving average
\   TS-EWMA           ( src n alpha -- last )      EWMA → single final value
\   TS-WMA            ( src n window dst -- )       weighted moving average
\   TS-MEDIAN-FILTER  ( src n window dst -- )       running median
\
\ Differencing & Returns:
\   TS-DIFF           ( src n dst -- )              first differences
\   TS-DIFF-K         ( src n k dst -- )            k-th order differences
\   TS-PCT-CHANGE     ( src n dst -- )              percentage change
\   TS-LOG-RETURN     ( src n dst -- )              log return
\   TS-CUMSUM         ( src n dst -- )              cumulative sum
\   TS-CUMMIN         ( src n dst -- )              cumulative minimum
\   TS-CUMMAX         ( src n dst -- )              cumulative maximum
\
\ Trend & Seasonality:
\   TS-DETREND        ( src n dst -- )              remove linear trend
\   TS-DETREND-MEAN   ( src n dst -- )              remove mean (center)
\   TS-AUTOCORR       ( src n lag -- r )            autocorrelation at lag
\   TS-AUTOCORR-N     ( src n max-lag dst -- )      ACF for lags 0..max-lag
\   TS-LAG            ( src n k dst -- )            lag operator (shift by k)
\   TS-ROLLING-STD    ( src n window dst -- )        rolling standard deviation
\   TS-DRAWDOWN       ( src n dst -- )              drawdown from running max
\   TS-MAX-DRAWDOWN   ( src n -- mdd )              maximum drawdown
\
\ Anomaly Detection:
\   TS-ZSCORE         ( src n dst -- )              z-score normalization
\   TS-OUTLIERS-IQR   ( src n dst -- m )            flag outliers by IQR rule
\   TS-OUTLIERS-Z     ( src n threshold dst -- m )  flag outliers by z-score

REQUIRE stats.f
REQUIRE regression.f
REQUIRE exp.f

PROVIDED akashic-timeseries

\ =====================================================================
\  Internal state
\ =====================================================================

VARIABLE _TS-SRC
VARIABLE _TS-DST
VARIABLE _TS-N
VARIABLE _TS-WIN       \ window size
VARIABLE _TS-K         \ order / lag / general counter
VARIABLE _TS-I         \ loop index
VARIABLE _TS-J         \ inner loop index
VARIABLE _TS-ACC       \ FP32 accumulator
VARIABLE _TS-ACC2      \ second FP32 accumulator
VARIABLE _TS-MEAN      \ FP32 mean
VARIABLE _TS-VAL

\ Dedicated scratch buffer for timeseries (not shared with _STAT-SCR0/1)
_STAT-MAX-N 2 * HBW-ALLOT CONSTANT _TS-SCR   \ timeseries scratch       \ temp FP16 value

\ =====================================================================
\  TS-SMA — Simple Moving Average
\ =====================================================================
\  For each position i where i >= window-1, compute the mean of
\  the last `window` elements.  First (window-1) positions use
\  the expanding window average.
\
\  Algorithm: sliding sum in FP32.  Add the new element, subtract
\  the departing one.  O(n) regardless of window size.

: TS-SMA  ( src n window dst -- )
    _TS-DST !  _TS-WIN !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN
    _TS-WIN @ 1 MAX _TS-WIN !
    _TS-WIN @ _TS-N @ MIN _TS-WIN !

    \ Phase 1: build initial window sum (expanding window)
    FP32-ZERO _TS-ACC !
    0 _TS-I !
    BEGIN _TS-I @ _TS-WIN @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@ FP16>FP32
        _TS-ACC @ SWAP FP32-ADD _TS-ACC !
        \ dst[i] = sum / (i+1)
        _TS-ACC @
        _TS-I @ 1 + INT>FP32 FP32-DIV FP32>FP16
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT

    \ Phase 2: full window — slide
    BEGIN _TS-I @ _TS-N @ < WHILE
        \ Add new element
        _TS-SRC @ _TS-I @ 2 * + W@ FP16>FP32
        _TS-ACC @ SWAP FP32-ADD _TS-ACC !
        \ Subtract departing element
        _TS-I @ _TS-WIN @ - 2 * _TS-SRC @ + W@ FP16>FP32
        _TS-ACC @ SWAP FP32-SUB _TS-ACC !
        \ dst[i] = sum / window
        _TS-ACC @
        _TS-WIN @ INT>FP32 FP32-DIV FP32>FP16
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-EMA — Exponential Moving Average
\ =====================================================================
\  y[0] = x[0]
\  y[t] = alpha * x[t] + (1 - alpha) * y[t-1]
\  alpha is FP16 in (0, 1).

: TS-EMA  ( src n alpha dst -- )
    _TS-DST !  _TS-VAL !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN

    \ alpha and (1-alpha) as FP32
    _TS-VAL @ FP16>FP32 _TS-ACC !       \ alpha (FP32)
    FP32-ONE _TS-ACC @ FP32-SUB _TS-ACC2 !  \ 1-alpha (FP32)

    \ y[0] = x[0]
    _TS-SRC @ W@ FP16>FP32 _TS-MEAN !
    _TS-MEAN @ FP32>FP16 _TS-DST @ W!

    1 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        \ y = alpha * x[i] + (1-alpha) * y_prev
        _TS-SRC @ _TS-I @ 2 * + W@ FP16>FP32
        _TS-ACC @ FP32-MUL                   \ alpha * x[i]
        _TS-MEAN @ _TS-ACC2 @ FP32-MUL       \ (1-alpha) * y_prev
        FP32-ADD
        DUP _TS-MEAN !
        FP32>FP16 _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-EWMA — Exponential Weighted Moving Average → single final value
\ =====================================================================

: TS-EWMA  ( src n alpha -- last-fp16 )
    _TS-VAL !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF FP16-POS-ZERO EXIT THEN

    _TS-VAL @ FP16>FP32 _TS-ACC !       \ alpha
    FP32-ONE _TS-ACC @ FP32-SUB _TS-ACC2 !  \ 1-alpha

    _TS-SRC @ W@ FP16>FP32 _TS-MEAN !

    1 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@ FP16>FP32
        _TS-ACC @ FP32-MUL
        _TS-MEAN @ _TS-ACC2 @ FP32-MUL
        FP32-ADD _TS-MEAN !
        _TS-I @ 1 + _TS-I !
    REPEAT
    _TS-MEAN @ FP32>FP16 ;

\ =====================================================================
\  TS-WMA — Weighted Moving Average (linear weights)
\ =====================================================================
\  Within a window of size w, weight[j] = j+1  (j=0..w-1)
\  WMA = sum(w[j]*x[i-w+1+j]) / sum(w[j])
\  sum(w[j]) = w*(w+1)/2

: TS-WMA  ( src n window dst -- )
    _TS-DST !  _TS-WIN !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN
    _TS-WIN @ 1 MAX _TS-WIN !
    _TS-WIN @ _TS-N @ MIN _TS-WIN !

    \ weight_sum = window * (window + 1) / 2  (FP32)
    _TS-WIN @ _TS-WIN @ 1 + * 2 / INT>FP32 _TS-ACC2 !

    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        \ Compute actual window at position i
        _TS-I @ 1 + _TS-WIN @ MIN _TS-K !    \ effective window

        \ Weighted sum
        FP32-ZERO _TS-ACC !
        0 _TS-J !
        BEGIN _TS-J @ _TS-K @ < WHILE
            \ element index: i - k + 1 + j
            _TS-I @ _TS-K @ - 1 + _TS-J @ + 2 * _TS-SRC @ + W@
            FP16>FP32
            _TS-J @ 1 + INT>FP32 FP32-MUL
            _TS-ACC @ SWAP FP32-ADD _TS-ACC !
            _TS-J @ 1 + _TS-J !
        REPEAT

        \ Divide by sum of weights for this window
        _TS-K @ _TS-K @ 1 + * 2 / INT>FP32
        _TS-ACC @ SWAP FP32-DIV FP32>FP16
        _TS-DST @ _TS-I @ 2 * + W!

        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-MEDIAN-FILTER — Running Median
\ =====================================================================
\  For each position, extract the window, copy to scratch, sort,
\  take the median.  Uses _STAT-SCR0 as scratch (shared with stats.f).

: TS-MEDIAN-FILTER  ( src n window dst -- )
    _TS-DST !  _TS-WIN !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN
    _TS-WIN @ 1 MAX _TS-WIN !
    _TS-WIN @ _TS-N @ MIN _TS-WIN !

    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        \ Effective window: min(i+1, window)
        _TS-I @ 1 + _TS-WIN @ MIN _TS-K !
        \ Start index in src
        _TS-I @ _TS-K @ - 1 + _TS-J !

        \ Copy window to SCR0
        _TS-SRC @ _TS-J @ 2 * +
        _STAT-SCR0 _TS-K @ SIMD-COPY-N

        \ Sort SCR0
        _STAT-SCR0 _TS-K @ SORT-FP16

        \ Median: middle element (or avg of two middle for even k)
        _TS-K @ 1 AND IF
            \ odd: middle element
            _TS-K @ 2 / 2 * _STAT-SCR0 + W@
        ELSE
            \ even: average of two middle elements
            _TS-K @ 2 / 1 - 2 * _STAT-SCR0 + W@ FP16>FP32
            _TS-K @ 2 / 2 * _STAT-SCR0 + W@ FP16>FP32
            FP32-ADD
            2 INT>FP32 FP32-DIV FP32>FP16
        THEN
        _TS-DST @ _TS-I @ 2 * + W!

        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-DIFF — First Differences
\ =====================================================================
\  dst[i] = src[i+1] - src[i],  dst has n-1 elements.
\  Uses SIMD for the subtraction where possible.

: TS-DIFF  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 2 < IF EXIT THEN
    \ src[1..n-1] - src[0..n-2]
    _TS-SRC @ 2 +          \ src+1
    _TS-SRC @               \ src
    _TS-DST @
    _TS-N @ 1 -
    SIMD-SUB-N ;

\ =====================================================================
\  TS-DIFF-K — K-th Order Differences
\ =====================================================================
\  Apply first-difference k times.  Result has n-k elements.
\  Uses _STAT-SCR0 and _STAT-SCR1 alternately as scratch.

: TS-DIFF-K  ( src n k dst -- )
    _TS-DST !  _TS-K !  _TS-N !  _TS-SRC !
    _TS-K @ 0 = IF
        _TS-SRC @ _TS-DST @ _TS-N @ SIMD-COPY-N EXIT
    THEN
    _TS-N @ _TS-K @ <= IF EXIT THEN

    \ First diff: src → SCR0
    _TS-SRC @ _TS-N @ _STAT-SCR0 TS-DIFF
    _TS-N @ 1 - _TS-N !
    _TS-K @ 1 - _TS-K !

    \ Remaining diffs: alternate SCR0 ↔ SCR1
    BEGIN _TS-K @ 0 > WHILE
        _TS-N @ 2 < IF
            \ Too few elements; just copy what we have
            _STAT-SCR0 _TS-DST @ _TS-N @ SIMD-COPY-N EXIT
        THEN
        _STAT-SCR0 _TS-N @ _STAT-SCR1 TS-DIFF
        _TS-N @ 1 - _TS-N !
        _TS-K @ 1 - _TS-K !
        \ Swap: copy SCR1 back to SCR0
        _TS-K @ 0 > IF
            _STAT-SCR1 _STAT-SCR0 _TS-N @ SIMD-COPY-N
        THEN
    REPEAT

    \ Copy result to dst
    _STAT-SCR1 _TS-DST @ _TS-N @ SIMD-COPY-N ;

\ =====================================================================
\  TS-PCT-CHANGE — Percentage Change
\ =====================================================================
\  dst[i] = (src[i+1] - src[i]) / src[i]
\  Result has n-1 elements.

: TS-PCT-CHANGE  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 2 < IF EXIT THEN

    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ 1 - < WHILE
        _TS-SRC @ _TS-I @ 1 + 2 * + W@    \ src[i+1]
        _TS-SRC @ _TS-I @ 2 * + W@        \ src[i]
        DUP 0x7FFF AND 0 = IF
            \ src[i] is zero → result is 0
            2DROP FP16-POS-ZERO
        ELSE
            SWAP OVER                \ src[i] src[i+1] src[i]
            FP16-SUB                 \ src[i] (src[i+1]-src[i])
            SWAP FP16-DIV
        THEN
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-LOG-RETURN — Log Return
\ =====================================================================
\  dst[i] = ln(src[i+1] / src[i])
\  Result has n-1 elements.

: TS-LOG-RETURN  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 2 < IF EXIT THEN

    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ 1 - < WHILE
        _TS-SRC @ _TS-I @ 1 + 2 * + W@    \ src[i+1]
        _TS-SRC @ _TS-I @ 2 * + W@        \ src[i]
        DUP 0x7FFF AND 0 = IF
            2DROP FP16-POS-ZERO
        ELSE
            FP16-DIV EXP-LN
        THEN
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-CUMSUM — Cumulative Sum
\ =====================================================================
\  dst[0] = src[0]
\  dst[i] = dst[i-1] + src[i]

: TS-CUMSUM  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN

    \ First element
    _TS-SRC @ W@ FP16>FP32 _TS-ACC !
    _TS-ACC @ FP32>FP16 _TS-DST @ W!

    1 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@ FP16>FP32
        _TS-ACC @ SWAP FP32-ADD _TS-ACC !
        _TS-ACC @ FP32>FP16
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-CUMMIN — Cumulative Minimum
\ =====================================================================

: TS-CUMMIN  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN
    _TS-SRC @ W@ _TS-VAL !
    _TS-VAL @ _TS-DST @ W!

    1 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@
        _TS-VAL @ FP16-MIN
        DUP _TS-VAL !
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-CUMMAX — Cumulative Maximum
\ =====================================================================

: TS-CUMMAX  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN
    _TS-SRC @ W@ _TS-VAL !
    _TS-VAL @ _TS-DST @ W!

    1 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@
        _TS-VAL @ FP16-MAX
        DUP _TS-VAL !
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-DETREND — Remove Linear Trend
\ =====================================================================
\  Fit y = a + b*x via REG-OLS on indices [0..n-1], then
\  dst[i] = src[i] - (a + b*i).  Uses _STAT-SCR0/1 as scratch.

CREATE _TS-REG-CTX REG-CTX-SIZE ALLOT

: TS-DETREND  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 2 < IF
        _TS-SRC @ _TS-DST @ _TS-N @ SIMD-COPY-N EXIT
    THEN

    \ Build index array in _TS-SCR: 0, 1, 2, ..., n-1  (FP16)
    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-I @ INT>FP16
        _TS-SCR _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT

    \ OLS fit: x=indices, y=src
    _TS-SCR _TS-SRC @ _TS-N @ _TS-REG-CTX REG-OLS

    \ Rebuild index array (REG-OLS clobbered _STAT-SCR0/1)
    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-I @ INT>FP16
        _TS-SCR _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT

    \ Predict trend into SCR1, then dst = src - trend
    _TS-REG-CTX _TS-SCR _STAT-SCR1 _TS-N @ REG-PREDICT-N
    _TS-SRC @ _STAT-SCR1 _TS-DST @ _TS-N @ SIMD-SUB-N ;

\ =====================================================================
\  TS-DETREND-MEAN — Remove Mean (Center Data)
\ =====================================================================

: TS-DETREND-MEAN  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN
    _TS-SRC @ _TS-N @ STAT-MEAN    \ FP16 mean
    _TS-DST @ SWAP _TS-N @ SIMD-FILL-N
    _TS-SRC @ _TS-DST @ _TS-DST @ _TS-N @ SIMD-SUB-N ;

\ =====================================================================
\  TS-AUTOCORR — Autocorrelation at Given Lag
\ =====================================================================
\  r(lag) = cov(x[0..n-lag-1], x[lag..n-1]) / var(x)
\  Uses STAT-COVARIANCE and STAT-VARIANCE.

: TS-AUTOCORR  ( src n lag -- r-fp16 )
    _TS-K !  _TS-N !  _TS-SRC !
    _TS-K @ 0 = IF FP16-POS-ONE EXIT THEN
    _TS-K @ _TS-N @ >= IF FP16-POS-ZERO EXIT THEN

    \ Effective length for correlation
    _TS-N @ _TS-K @ - _TS-J !

    \ Compute covariance of x[0..eff-1] and x[lag..lag+eff-1]
    _TS-SRC @
    _TS-SRC @ _TS-K @ 2 * +
    _TS-J @
    STAT-COVARIANCE     \ cov(x, x_lagged) as FP16

    \ Divide by variance of full series
    FP16>FP32 _TS-ACC !
    _TS-SRC @ _TS-N @ STAT-VARIANCE FP16>FP32 _TS-ACC2 !
    _TS-ACC2 @ FP32-0= IF
        FP16-POS-ZERO
    ELSE
        _TS-ACC @ _TS-ACC2 @ FP32-DIV FP32>FP16
    THEN ;

\ =====================================================================
\  TS-AUTOCORR-N — Autocorrelation Function (all lags 0..max-lag)
\ =====================================================================

: TS-AUTOCORR-N  ( src n max-lag dst -- )
    _TS-DST !  _TS-K !  _TS-N !  _TS-SRC !
    _TS-K @ _TS-N @ 1 - MIN _TS-K !

    0 _TS-I !
    BEGIN _TS-I @ _TS-K @ 1 + < WHILE
        _TS-SRC @ _TS-N @ _TS-I @ TS-AUTOCORR
        _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-LAG — Lag Operator
\ =====================================================================
\  dst[i] = src[i-k] for i >= k, zero-padded for i < k.
\  Output has n elements.

: TS-LAG  ( src n k dst -- )
    _TS-DST !  _TS-K !  _TS-N !  _TS-SRC !
    _TS-K @ _TS-N @ >= IF
        _TS-DST @ _TS-N @ SIMD-ZERO-N EXIT
    THEN

    \ Zero-pad first k positions
    0 _TS-I !
    BEGIN _TS-I @ _TS-K @ < WHILE
        FP16-POS-ZERO _TS-DST @ _TS-I @ 2 * + W!
        _TS-I @ 1 + _TS-I !
    REPEAT

    \ Copy shifted data
    _TS-SRC @
    _TS-DST @ _TS-K @ 2 * +
    _TS-N @ _TS-K @ -
    SIMD-COPY-N ;

\ =====================================================================
\  TS-ROLLING-STD — Rolling Standard Deviation
\ =====================================================================
\  For each position, compute stddev of the trailing window.
\  Uses two-pass per window (mean then deviations).

: TS-ROLLING-STD  ( src n window dst -- )
    _TS-DST !  _TS-WIN !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN
    _TS-WIN @ 1 MAX _TS-WIN !
    _TS-WIN @ _TS-N @ MIN _TS-WIN !

    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-I @ 1 + _TS-WIN @ MIN _TS-K !     \ effective window
        _TS-I @ _TS-K @ - 1 + _TS-J !          \ start index

        _TS-K @ 1 <= IF
            FP16-POS-ZERO _TS-DST @ _TS-I @ 2 * + W!
        ELSE
            _TS-SRC @ _TS-J @ 2 * + _TS-K @ STAT-STDDEV
            _TS-DST @ _TS-I @ 2 * + W!
        THEN

        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-DRAWDOWN — Drawdown from Running Maximum
\ =====================================================================
\  dst[i] = (cummax[i] - src[i]) / cummax[i]
\  If cummax is zero, drawdown is zero.

: TS-DRAWDOWN  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 0 = IF EXIT THEN

    _TS-SRC @ W@ _TS-VAL !   \ running max
    FP16-POS-ZERO _TS-DST @ W!

    1 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@     \ current value
        DUP _TS-VAL @ FP16-MAX _TS-VAL !  \ update running max
        \ drawdown = (max - val) / max
        _TS-VAL @ OVER FP16-SUB            \ max - val
        _TS-VAL @ DUP 0x7FFF AND 0 = IF
            2DROP FP16-POS-ZERO
        ELSE
            FP16-DIV
        THEN
        _TS-DST @ _TS-I @ 2 * + W!
        DROP  \ drop original val copy
        _TS-I @ 1 + _TS-I !
    REPEAT ;

\ =====================================================================
\  TS-MAX-DRAWDOWN — Maximum Drawdown (Peak-to-Trough)
\ =====================================================================

: TS-MAX-DRAWDOWN  ( src n -- mdd-fp16 )
    _TS-N !  _TS-SRC !
    _TS-N @ 2 < IF FP16-POS-ZERO EXIT THEN

    _TS-SRC @ W@ _TS-VAL !       \ running max
    FP16-POS-ZERO _TS-ACC !       \ max drawdown as FP16 stored in _TS-ACC

    1 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@
        DUP _TS-VAL @ FP16-MAX _TS-VAL !
        _TS-VAL @ OVER FP16-SUB
        _TS-VAL @ DUP 0x7FFF AND 0 = IF
            2DROP FP16-POS-ZERO
        ELSE
            FP16-DIV
        THEN
        \ Update max drawdown
        _TS-ACC @ FP16-MAX _TS-ACC !
        DROP  \ drop val
        _TS-I @ 1 + _TS-I !
    REPEAT
    _TS-ACC @ ;

\ =====================================================================
\  TS-ZSCORE — Z-Score Normalization
\ =====================================================================
\  dst[i] = (src[i] - mean) / stddev
\  Uses SIMD for broadcast subtract and divide.

: TS-ZSCORE  ( src n dst -- )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 2 < IF
        _TS-DST @ _TS-N @ SIMD-ZERO-N EXIT
    THEN

    \ Compute mean and stddev
    _TS-SRC @ _TS-N @ _STAT-MEAN-FP32
    DUP _TS-MEAN !
    FP32>FP16 _TS-VAL !

    _TS-SRC @ _TS-N @ STAT-STDDEV
    DUP 0x7FFF AND 0 = IF
        \ stddev = 0 → all zeros
        DROP _TS-DST @ _TS-N @ SIMD-ZERO-N EXIT
    THEN
    _TS-ACC !  \ stddev as FP16

    \ dst = src - mean (broadcast)
    _TS-DST @ _TS-VAL @ _TS-N @ SIMD-FILL-N
    _TS-SRC @ _TS-DST @ _TS-DST @ _TS-N @ SIMD-SUB-N

    \ dst = dst / stddev (element-wise via reciprocal * scale)
    _TS-ACC @ FP16-RECIP
    _TS-DST @ SWAP _TS-DST @ _TS-N @ SIMD-SCALE-N ;

\ =====================================================================
\  TS-OUTLIERS-IQR — Flag Outliers by IQR Rule
\ =====================================================================
\  An outlier is any value < Q1 - 1.5*IQR or > Q3 + 1.5*IQR.
\  dst[i] = 1 (FP16) if outlier, 0 otherwise.
\  Returns m = number of outliers.

0x3E00 CONSTANT _TS-FP16-1.5   \ 1.5 in FP16

: TS-OUTLIERS-IQR  ( src n dst -- m )
    _TS-DST !  _TS-N !  _TS-SRC !
    _TS-N @ 4 < IF
        _TS-DST @ _TS-N @ SIMD-ZERO-N 0 EXIT
    THEN

    \ Compute Q1, Q3
    _TS-SRC @ _TS-N @ 25 STAT-PERCENTILE _TS-ACC !   \ Q1 (FP16)
    _TS-SRC @ _TS-N @ 75 STAT-PERCENTILE _TS-ACC2 !  \ Q3 (FP16)

    \ IQR = Q3 - Q1
    _TS-ACC2 @ _TS-ACC @ FP16-SUB _TS-VAL !

    \ lower = Q1 - 1.5 * IQR
    _TS-VAL @ _TS-FP16-1.5 FP16-MUL
    DUP _TS-ACC @ SWAP FP16-SUB _TS-MEAN !   \ lower bound (FP16, stored in MEAN)

    \ upper = Q3 + 1.5 * IQR
    _TS-ACC2 @ SWAP FP16-ADD _TS-K !          \ upper bound (FP16, stored in K)

    0 _TS-J !   \ outlier count
    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _TS-SRC @ _TS-I @ 2 * + W@
        DUP _TS-MEAN @ FP16-LT IF
            DROP FP16-POS-ONE _TS-DST @ _TS-I @ 2 * + W!
            _TS-J @ 1 + _TS-J !
        ELSE
            _TS-K @ FP16-GT IF
                FP16-POS-ONE _TS-DST @ _TS-I @ 2 * + W!
                _TS-J @ 1 + _TS-J !
            ELSE
                FP16-POS-ZERO _TS-DST @ _TS-I @ 2 * + W!
            THEN
        THEN
        _TS-I @ 1 + _TS-I !
    REPEAT
    _TS-J @ ;

\ =====================================================================
\  TS-OUTLIERS-Z — Flag Outliers by Z-Score
\ =====================================================================
\  dst[i] = 1 if |z-score[i]| > threshold, 0 otherwise.
\  Returns m = number of outliers.

: TS-OUTLIERS-Z  ( src n threshold dst -- m )
    _TS-DST !  _TS-K !  _TS-N !  _TS-SRC !
    _TS-N @ 2 < IF
        _TS-DST @ _TS-N @ SIMD-ZERO-N 0 EXIT
    THEN

    \ Compute z-scores into SCR0
    _TS-SRC @ _TS-N @ _STAT-SCR0 TS-ZSCORE

    \ Scan for |z| > threshold
    0 _TS-J !
    0 _TS-I !
    BEGIN _TS-I @ _TS-N @ < WHILE
        _STAT-SCR0 _TS-I @ 2 * + W@ FP16-ABS
        _TS-K @ FP16-GT IF
            FP16-POS-ONE _TS-DST @ _TS-I @ 2 * + W!
            _TS-J @ 1 + _TS-J !
        ELSE
            FP16-POS-ZERO _TS-DST @ _TS-I @ 2 * + W!
        THEN
        _TS-I @ 1 + _TS-I !
    REPEAT
    _TS-J @ ;
