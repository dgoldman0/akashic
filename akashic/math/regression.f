\ regression.f — Simple Linear Regression (OLS)
\
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ Prefix: REG-  (public API)
\         _RG-  (internal helpers)
\
\ Depends on: stats.f (fp16, fp16-ext, fp32, accum, simd, simd-ext, sort)
\
\ Load with:   REQUIRE regression.f
\
\ === Public API ===
\   REG-CTX-SIZE      ( -- 64 )              context size in bytes
\   REG-OLS           ( x y n ctx -- )        ordinary least squares fit
\   REG-SLOPE         ( ctx -- slope )         beta1 as FP16
\   REG-INTERCEPT     ( ctx -- intercept )     beta0 as FP16
\   REG-R-SQUARED     ( ctx -- r2 )            R-squared as FP16
\   REG-ADJ-R-SQUARED ( ctx -- r2adj )         adjusted R-squared as FP16
\   REG-PREDICT       ( ctx x -- y-hat )       predict one value
\   REG-PREDICT-N     ( ctx x-src dst n -- )   batch predict (SIMD)
\   REG-RESIDUALS     ( ctx x y dst n -- )     residuals y - y-hat to dst
\   REG-SSE           ( ctx -- sse )           sum of squared errors
\   REG-SSR           ( ctx -- ssr )           sum of squared regression
\   REG-SST           ( ctx -- sst )           total sum of squares
\   REG-RMSE          ( ctx -- rmse )          root mean squared error
\   REG-MAE           ( ctx x y n -- mae )     mean absolute error

REQUIRE stats.f

PROVIDED akashic-regression

\ =====================================================================
\  Regression context layout — 8 cells x 8 bytes = 64 bytes
\ =====================================================================
\  +0    n           observation count (integer)
\  +8    slope       beta1 (FP32)
\  +16   intercept   beta0 (FP32)
\  +24   r_squared   R-squared (FP32)
\  +32   sse         sum of squared errors (FP32)
\  +40   sst         total sum of squares (FP32 = Syy)
\  +48   x_mean      mean of x (FP32)
\  +56   y_mean      mean of y (FP32)

64 CONSTANT REG-CTX-SIZE

\ Field accessors: ctx -- addr
: _RG-N   0 + ;      \ offset +0
: _RG-SLP 8 + ;      \ offset +8
: _RG-INT 16 + ;     \ offset +16
: _RG-R2  24 + ;     \ offset +24
: _RG-SSE 32 + ;     \ offset +32
: _RG-SST 40 + ;     \ offset +40
: _RG-XM  48 + ;     \ offset +48
: _RG-YM  56 + ;     \ offset +56

\ =====================================================================
\  Internal state
\ =====================================================================

VARIABLE _RG-CTX
VARIABLE _RG-X
VARIABLE _RG-Y
VARIABLE _RG-NN      \ observation count
VARIABLE _RG-DST     \ destination buffer
VARIABLE _RG-SXX     \ Sxx as FP32
VARIABLE _RG-SXY     \ Sxy as FP32
VARIABLE _RG-SYY     \ Syy as FP32

\ =====================================================================
\  REG-OLS — Ordinary Least Squares: fit y = beta0 + beta1 * x
\ =====================================================================
\  Mixed-precision pipeline:
\    FP16 arrays -> tile deviations -> SIMD-SUMSQ/DOT (FP32)
\    -> software FP32 coefficient computation -> FP16 output
\
\  Sxx = sum of (xi - x_mean)^2
\  Sxy = sum of (xi - x_mean)(yi - y_mean)
\  Syy = sum of (yi - y_mean)^2
\  slope     = Sxy / Sxx
\  intercept = y_mean - slope * x_mean
\  R-squared = Sxy^2 / (Sxx * Syy)
\  SSE       = Syy - slope * Sxy
\  SST       = Syy

: REG-OLS  \ x y n ctx --
    _RG-CTX !  _RG-NN !  _RG-Y !  _RG-X !
    _RG-NN @ _RG-CTX @ _RG-N !

    \ Edge case: n < 2 -> degenerate
    _RG-NN @ 2 < IF
        FP32-ZERO _RG-CTX @ _RG-SLP !
        FP32-ZERO _RG-CTX @ _RG-R2  !
        FP32-ZERO _RG-CTX @ _RG-SSE !
        FP32-ZERO _RG-CTX @ _RG-SST !
        _RG-NN @ 1 = IF
            _RG-X @ W@ FP16>FP32 _RG-CTX @ _RG-XM !
            _RG-Y @ W@ FP16>FP32
            DUP _RG-CTX @ _RG-YM !
            _RG-CTX @ _RG-INT !
        ELSE
            FP32-ZERO _RG-CTX @ _RG-XM !
            FP32-ZERO _RG-CTX @ _RG-YM !
            FP32-ZERO _RG-CTX @ _RG-INT !
        THEN
        EXIT
    THEN

    \ Step 1 — means (FP32 via SIMD-SUM-N)
    _RG-X @ _RG-NN @ SIMD-SUM-N
    _RG-NN @ INT>FP32 FP32-DIV
    _RG-CTX @ _RG-XM !

    _RG-Y @ _RG-NN @ SIMD-SUM-N
    _RG-NN @ INT>FP32 FP32-DIV
    _RG-CTX @ _RG-YM !

    \ Step 2 — deviations (FP16 arrays in stats scratch buffers)
    \ SCR0 = x - x_mean
    _RG-CTX @ _RG-XM @ FP32>FP16
    _STAT-SCR0 SWAP _RG-NN @ SIMD-FILL-N
    _RG-X @ _STAT-SCR0 _STAT-SCR0 _RG-NN @ SIMD-SUB-N

    \ SCR1 = y - y_mean
    _RG-CTX @ _RG-YM @ FP32>FP16
    _STAT-SCR1 SWAP _RG-NN @ SIMD-FILL-N
    _RG-Y @ _STAT-SCR1 _STAT-SCR1 _RG-NN @ SIMD-SUB-N

    \ Step 3 — sums via tile reductions (FP32)
    _STAT-SCR0 _RG-NN @ SIMD-SUMSQ-N  _RG-SXX !
    _STAT-SCR0 _STAT-SCR1 _RG-NN @ SIMD-DOT-N  _RG-SXY !
    _STAT-SCR1 _RG-NN @ SIMD-SUMSQ-N  _RG-SYY !

    \ SST = Syy (store before Sxx check)
    _RG-SYY @ _RG-CTX @ _RG-SST !

    \ Degenerate: Sxx = 0 -> all x identical
    _RG-SXX @ FP32-0= IF
        FP32-ZERO _RG-CTX @ _RG-SLP !
        _RG-CTX @ _RG-YM @ _RG-CTX @ _RG-INT !
        FP32-ZERO _RG-CTX @ _RG-R2 !
        _RG-SYY @ _RG-CTX @ _RG-SSE !
        EXIT
    THEN

    \ Step 4 — slope = Sxy / Sxx
    _RG-SXY @ _RG-SXX @ FP32-DIV
    _RG-CTX @ _RG-SLP !

    \ Step 5 — intercept = y_mean - slope * x_mean
    _RG-CTX @ _RG-YM @
    _RG-CTX @ _RG-SLP @ _RG-CTX @ _RG-XM @ FP32-MUL
    FP32-SUB
    _RG-CTX @ _RG-INT !

    \ Step 6 — R-squared = Sxy^2 / (Sxx * Syy)
    _RG-SXY @ DUP FP32-MUL
    _RG-SXX @ _RG-SYY @ FP32-MUL
    DUP FP32-0= IF
        DROP DROP FP32-ZERO
    ELSE
        FP32-DIV
    THEN
    _RG-CTX @ _RG-R2 !

    \ Step 7 — SSE = Syy - slope * Sxy
    _RG-SYY @
    _RG-CTX @ _RG-SLP @ _RG-SXY @ FP32-MUL
    FP32-SUB
    _RG-CTX @ _RG-SSE !
    ;

\ =====================================================================
\  Context readers — return FP16
\ =====================================================================

: REG-SLOPE     \ ctx -- slope-fp16
    _RG-SLP @ FP32>FP16 ;

: REG-INTERCEPT \ ctx -- intercept-fp16
    _RG-INT @ FP32>FP16 ;

: REG-R-SQUARED \ ctx -- r2-fp16
    _RG-R2 @ FP32>FP16 ;

: REG-SSE       \ ctx -- sse-fp16
    _RG-SSE @ FP32>FP16 ;

: REG-SST       \ ctx -- sst-fp16
    _RG-SST @ FP32>FP16 ;

: REG-SSR       \ ctx -- ssr-fp16
    DUP _RG-SST @
    SWAP _RG-SSE @
    FP32-SUB FP32>FP16 ;

: REG-ADJ-R-SQUARED  \ ctx -- r2adj-fp16
    _RG-CTX !
    _RG-CTX @ _RG-N @ 3 < IF FP16-POS-ZERO EXIT THEN
    FP32-ONE _RG-CTX @ _RG-R2 @ FP32-SUB     \ 1 - R2
    _RG-CTX @ _RG-N @ 1 - INT>FP32 FP32-MUL  \ * (n - 1)
    _RG-CTX @ _RG-N @ 2 - INT>FP32 FP32-DIV  \ / (n - 2)
    FP32-ONE SWAP FP32-SUB                    \ 1 - ...
    FP32>FP16 ;

: REG-RMSE      \ ctx -- rmse-fp16
    DUP _RG-N @ 0 = IF DROP FP16-POS-ZERO EXIT THEN
    DUP _RG-SSE @
    SWAP _RG-N @ INT>FP32 FP32-DIV
    FP32-SQRT FP32>FP16 ;

\ =====================================================================
\  REG-PREDICT — single-point prediction
\ =====================================================================
\  y-hat = slope * x + intercept

: REG-PREDICT   \ ctx x -- y-hat-fp16
    FP16>FP32 >R
    DUP _RG-SLP @ R> FP32-MUL
    SWAP _RG-INT @ FP32-ADD
    FP32>FP16 ;

\ =====================================================================
\  REG-PREDICT-N — batch prediction (SIMD-accelerated)
\ =====================================================================
\  y-hat[i] = slope * x[i] + intercept
\  Uses SIMD-SAXPY-N: dst = a * x + y  (y filled with intercept)

: REG-PREDICT-N \ ctx x-src dst n --
    _RG-NN !  _RG-DST !  _RG-X !  _RG-CTX !
    _RG-NN @ 0 = IF EXIT THEN
    \ Fill SCR0 with intercept (FP16 broadcast)
    _RG-CTX @ _RG-INT @ FP32>FP16
    _STAT-SCR0 SWAP _RG-NN @ SIMD-FILL-N
    \ SAXPY: dst = slope * x + intercept
    _RG-CTX @ _RG-SLP @ FP32>FP16
    _RG-X @ _STAT-SCR0 _RG-DST @ _RG-NN @ SIMD-SAXPY-N ;

\ =====================================================================
\  REG-RESIDUALS — residual array: dst = y - y-hat
\ =====================================================================

: REG-RESIDUALS \ ctx x y dst n --
    _RG-NN !  _RG-DST !  _RG-Y !  _RG-X !  _RG-CTX !
    _RG-NN @ 0 = IF EXIT THEN
    \ Predict into dst
    _RG-CTX @ _RG-X @ _RG-DST @ _RG-NN @ REG-PREDICT-N
    \ dst = y - y-hat
    _RG-Y @ _RG-DST @ _RG-DST @ _RG-NN @ SIMD-SUB-N ;

\ =====================================================================
\  REG-MAE — mean absolute error (needs original data)
\ =====================================================================

: REG-MAE       \ ctx x y n -- mae-fp16
    _RG-NN !  _RG-Y !  _RG-X !  _RG-CTX !
    _RG-NN @ 0 = IF FP16-POS-ZERO EXIT THEN
    \ Predict into SCR1
    _RG-CTX @ _RG-X @ _STAT-SCR1 _RG-NN @ REG-PREDICT-N
    \ Residuals: y - predictions -> SCR1
    _RG-Y @ _STAT-SCR1 _STAT-SCR1 _RG-NN @ SIMD-SUB-N
    \ Absolute residuals
    _STAT-SCR1 _STAT-SCR1 _RG-NN @ SIMD-ABS-N
    \ Mean = sum / n
    _STAT-SCR1 _RG-NN @ SIMD-SUM-N
    _RG-NN @ INT>FP32 FP32-DIV FP32>FP16 ;
