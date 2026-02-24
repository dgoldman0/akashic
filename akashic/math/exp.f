\ exp.f — FP16 exponentials, logarithms, and activation functions
\
\ Polynomial approximations for exp, ln, exp2, log2, pow,
\ sigmoid, tanh.  All optimised for FP16's 10-bit mantissa.
\
\ exp2/log2 are the primitives; exp/ln are derived via ln(2).
\
\ Prefix: EXP-  (public API)
\         _EX-  (internal helpers)
\
\ Load with:   REQUIRE exp.f
\
\ === Public API ===
\   EXP-EXP      ( x -- e^x )         natural exponential
\   EXP-LN       ( x -- ln[x] )       natural logarithm
\   EXP-EXP2     ( x -- 2^x )         base-2 exponential
\   EXP-LOG2     ( x -- log2[x] )     base-2 logarithm
\   EXP-POW      ( base exp -- r )     general power
\   EXP-SIGMOID  ( x -- σ[x] )        logistic sigmoid
\   EXP-TANH     ( x -- tanh[x] )     hyperbolic tangent

REQUIRE fp16-ext.f

PROVIDED akashic-exp

\ =====================================================================
\  Constants
\ =====================================================================

0x398C CONSTANT _EX-LN2             \ ln(2)   = 0.6931
0x3DC5 CONSTANT _EX-INV-LN2        \ 1/ln(2) = 1.4427
0x3C00 CONSTANT _EX-ONE             \ 1.0
0x4000 CONSTANT _EX-TWO             \ 2.0
0x3800 CONSTANT _EX-HALF            \ 0.5

\ EXP2 polynomial coefficients: 2^x ≈ 1 + c1*x + c2*x² + c3*x³
\ on [0, 1).  Coefficients = ln(2)^k / k!
0x3C00 CONSTANT _EX-E2-C0           \ 1.0
0x398C CONSTANT _EX-E2-C1           \ 0.6931 (ln2)
0x33B0 CONSTANT _EX-E2-C2           \ 0.2402 (ln2²/2)
0x2B1B CONSTANT _EX-E2-C3           \ 0.0555 (ln2³/6)

\ LOG2 polynomial coefficients: log2(1+m) on [0, 1)
\ log2(1+m) ≈ m * (c0 + m * (c1 + m * c2))
\ Minimax cubic fit
0x3DC5 CONSTANT _EX-L2-C0           \ 1.4427  (1/ln2)
0xB9C5 CONSTANT _EX-L2-C1           \ −0.7214
0x33D6 CONSTANT _EX-L2-C2           \ 0.2810

\ =====================================================================
\  EXP-EXP2 — 2^x
\ =====================================================================
\  Algorithm:
\    Split x = n + f  where n = floor(x), f ∈ [0,1)
\    2^x = 2^n * 2^f
\    2^n: adjust FP16 exponent bits directly
\    2^f: polynomial on [0,1)
\
\  FP16 range: 2^15.9 ≈ 61035 (max normal), 2^(-14) = denormal boundary
\  So valid for x roughly in [−14, 15].

VARIABLE _EX-N
VARIABLE _EX-F

: _EX-POW2-INT  ( n -- fp16 )
    \ Compute 2^n as FP16 (n is integer, biased exp = n + 15)
    \ FP16 of 2^n = ((n+15) << 10) for n in [−14, 15]
    DUP -14 < IF DROP FP16-POS-ZERO EXIT THEN
    DUP  15 > IF DROP FP16-POS-INF  EXIT THEN
    15 + 10 LSHIFT 0xFFFF AND ;

: EXP-EXP2  ( x -- 2^x )
    \ Handle sign: if x < 0, 2^x = 1 / 2^|x| but we can still
    \ split x = n + f and handle directly.
    DUP FP16-FLOOR                    ( x floor_x )
    DUP FP16>INT _EX-N !             \ n = integer part
    FP16-SUB                          \ f = fractional part [0, 1)
    \ Polynomial for 2^f: c0 + f*(c1 + f*(c2 + f*c3))  Horner
    DUP _EX-E2-C3 FP16-MUL _EX-E2-C2 FP16-ADD
    OVER FP16-MUL _EX-E2-C1 FP16-ADD
    SWAP FP16-MUL _EX-E2-C0 FP16-ADD ( 2^f )
    \ Multiply by 2^n: adjust exponent
    _EX-N @ _EX-POW2-INT             ( 2^f 2^n )
    FP16-MUL ;

\ =====================================================================
\  EXP-EXP — e^x = 2^(x / ln2) = 2^(x * 1/ln2)
\ =====================================================================

: EXP-EXP  ( x -- e^x )
    _EX-INV-LN2 FP16-MUL EXP-EXP2 ;

\ =====================================================================
\  EXP-LOG2 — log2(x) for x > 0
\ =====================================================================
\  Algorithm:
\    Extract FP16 exponent and mantissa.
\    x = 1.m * 2^(e-15)
\    log2(x) = (e - 15) + log2(1.m)
\    log2(1.m) ≈ polynomial on mantissa fraction m ∈ [0, 1)

VARIABLE _EX-LEXP
VARIABLE _EX-LMANT

: EXP-LOG2  ( x -- log2[x] )
    0xFFFF AND
    DUP FP16-SIGN IF DROP FP16-QNAN EXIT THEN  \ negative → NaN
    DUP 0= IF DROP FP16-NEG-INF EXIT THEN      \ log2(0) = −inf
    DUP FP16-POS-INF = IF EXIT THEN            \ log2(inf) = inf
    \ Extract biased exponent and mantissa
    DUP 10 RSHIFT 0x1F AND _EX-LEXP !
    0x3FF AND                          ( raw_mantissa_10bit )
    \ Reconstruct m in [0, 1) as FP16: m = mantissa / 1024
    \ As FP16: we build 1.0 + m by setting exp=15, mant=raw
    \ Actually easier: build the FP16 for 1.m, then subtract 1.0
    0x3C00 OR                          ( fp16 of 1.m with exp=15 )
    _EX-ONE FP16-SUB                  \ m = mantissa frac in [0, 1)
    \ log2(1+m) = m * (c0 + m*(c1 + m*c2))  Horner
    DUP _EX-L2-C2 FP16-MUL _EX-L2-C1 FP16-ADD
    OVER FP16-MUL _EX-L2-C0 FP16-ADD
    FP16-MUL                           ( log2_frac )
    \ Add integer part: e − 15
    _EX-LEXP @ 15 - INT>FP16
    FP16-ADD ;

\ =====================================================================
\  EXP-LN — natural log: ln(x) = log2(x) * ln(2)
\ =====================================================================

: EXP-LN  ( x -- ln[x] )
    EXP-LOG2 _EX-LN2 FP16-MUL ;

\ =====================================================================
\  EXP-POW — general power: base^exp = 2^(exp * log2(base))
\ =====================================================================

: EXP-POW  ( base exp -- base^exp )
    SWAP EXP-LOG2 FP16-MUL EXP-EXP2 ;

\ =====================================================================
\  EXP-SIGMOID — logistic sigmoid: σ(x) = 1 / (1 + e^(−x))
\ =====================================================================
\  Uses the identity: σ(x) = 0.5 + 0.5 * tanh(x/2)
\  But since TANH needs SIGMOID, we implement directly.

: EXP-SIGMOID  \ x -- sigma
    FP16-NEG EXP-EXP                  \ e^(-x)
    _EX-ONE FP16-ADD                  \ 1 + e^(-x)
    FP16-RECIP ;                      \ 1 / [1 + e^(-x)]

\ =====================================================================
\  EXP-TANH — hyperbolic tangent: tanh(x) = 2σ(2x) − 1
\ =====================================================================

: EXP-TANH  \ x -- tanh
    _EX-TWO FP16-MUL                  \ 2x
    EXP-SIGMOID                        \ sigma(2x)
    _EX-TWO FP16-MUL                  \ 2*sigma(2x)
    _EX-ONE FP16-SUB ;               \ 2*sigma(2x) - 1
