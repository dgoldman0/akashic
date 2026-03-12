\ counting.f — Combinatorics & Frequency
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ Prefix: COMB-  (public API)
\         _CB-   (internal helpers)
\
\ Depends on: fp16.f, fp32.f, exp.f  (for LOG-FACTORIAL, LOG-CHOOSE)
\
\ Load with:   REQUIRE counting.f
\
\ === Public API ===
\   COMB-FACTORIAL      ( n -- n! )          factorial (64-bit, max n=20)
\   COMB-PERMUTE        ( n k -- nPk )       k-permutations of n
\   COMB-CHOOSE         ( n k -- nCk )       binomial coefficient
\   COMB-GCD            ( a b -- gcd )       greatest common divisor
\   COMB-LCM            ( a b -- lcm )       least common multiple
\   COMB-POWER-MOD      ( base exp mod -- r ) modular exponentiation
\   COMB-IS-PRIME?      ( n -- flag )         primality test (trial div)
\   COMB-NEXT-PRIME     ( n -- p )            smallest prime >= n
\   COMB-LOG-FACTORIAL  ( n -- ln[n!] )       log factorial (FP16)
\   COMB-LOG-CHOOSE     ( n k -- ln[nCk] )   log binomial coeff (FP16)

REQUIRE fp16.f
REQUIRE fp32.f
REQUIRE exp.f

PROVIDED akashic-counting

\ =====================================================================
\  Internal state
\ =====================================================================

VARIABLE _CB-A
VARIABLE _CB-B
VARIABLE _CB-R       \ result accumulator
VARIABLE _CB-I       \ loop index
VARIABLE _CB-M       \ modulus

\ =====================================================================
\  COMB-FACTORIAL — n! (integer, 64-bit)
\ =====================================================================
\  20! = 2,432,902,008,176,640,000 fits 64-bit.
\  21! overflows.  Returns 0 for n > 20 or n < 0.

: COMB-FACTORIAL  ( n -- n! )
    DUP 0 < IF DROP 0 EXIT THEN
    DUP 1 <= IF DROP 1 EXIT THEN
    DUP 20 > IF DROP 0 EXIT THEN
    1 _CB-R !
    2 _CB-I !
    _CB-A !
    BEGIN _CB-I @ _CB-A @ <= WHILE
        _CB-R @ _CB-I @ * _CB-R !
        _CB-I @ 1 + _CB-I !
    REPEAT
    _CB-R @ ;

\ =====================================================================
\  COMB-PERMUTE — nPk = n * (n-1) * ... * (n-k+1)
\ =====================================================================

: COMB-PERMUTE  ( n k -- nPk )
    DUP 0 <= IF 2DROP 1 EXIT THEN
    OVER SWAP -          ( n  n-k )
    1 + _CB-I !          ( n ; _CB-I = n-k+1 )
    _CB-A !              ( ; _CB-A = n )
    1 _CB-R !
    BEGIN _CB-I @ _CB-A @ <= WHILE
        _CB-R @ _CB-I @ * _CB-R !
        _CB-I @ 1 + _CB-I !
    REPEAT
    _CB-R @ ;

\ =====================================================================
\  COMB-CHOOSE — binomial coefficient C(n,k)
\ =====================================================================
\  Uses multiplicative formula:  result = 1; for i in 0..k-1:
\    result = result * (n-i) / (i+1)
\  Avoids factorial overflow, correct because C(n,k) is always integer.

: COMB-CHOOSE  ( n k -- nCk )
    _CB-B !  _CB-A !
    \ Optimize: C(n,k) = C(n, n-k) when k > n-k
    _CB-A @ _CB-B @ 2 * < IF
        _CB-A @ _CB-B @ - _CB-B !
    THEN
    _CB-B @ 0 <= IF 1 EXIT THEN
    1 _CB-R !
    0 _CB-I !
    BEGIN _CB-I @ _CB-B @ < WHILE
        _CB-R @ _CB-A @ _CB-I @ - * _CB-R !
        _CB-R @ _CB-I @ 1 + / _CB-R !
        _CB-I @ 1 + _CB-I !
    REPEAT
    _CB-R @ ;

\ =====================================================================
\  COMB-GCD — Greatest Common Divisor (Euclidean)
\ =====================================================================

: COMB-GCD  ( a b -- gcd )
    _CB-B !  _CB-A !
    BEGIN _CB-B @ 0 <> WHILE
        _CB-A @ _CB-B @ MOD
        _CB-B @ _CB-A !
        _CB-B !
    REPEAT
    _CB-A @ ;

\ =====================================================================
\  COMB-LCM — Least Common Multiple
\ =====================================================================

: COMB-LCM  ( a b -- lcm )
    2DUP COMB-GCD
    DUP 0 = IF DROP 2DROP 0 EXIT THEN
    /                  ( a  b/gcd )
    * ;                ( a * b/gcd = lcm )

\ =====================================================================
\  COMB-POWER-MOD — modular exponentiation via binary method
\ =====================================================================
\  Computes base^exp mod m.  Safe for moduli up to 2^32
\  (intermediate product < 2^64).

: COMB-POWER-MOD  ( base exp mod -- result )
    _CB-M !  _CB-B !
    _CB-M @ MOD _CB-A !           \ base = base mod m
    1 _CB-R !                     \ result = 1
    BEGIN _CB-B @ 0 <> WHILE
        _CB-B @ 1 AND IF
            _CB-R @ _CB-A @ * _CB-M @ MOD _CB-R !
        THEN
        _CB-A @ DUP * _CB-M @ MOD _CB-A !
        _CB-B @ 1 RSHIFT _CB-B !
    REPEAT
    _CB-R @ ;

\ =====================================================================
\  COMB-IS-PRIME? — primality test via trial division
\ =====================================================================
\  Uses 6k±1 trial division up to √n.
\  Returns -1 (true) or 0 (false).

: COMB-IS-PRIME?  ( n -- flag )
    DUP 2 < IF DROP 0 EXIT THEN
    DUP 2 = IF DROP -1 EXIT THEN
    DUP 3 = IF DROP -1 EXIT THEN
    DUP 2 MOD 0 = IF DROP 0 EXIT THEN
    DUP 3 MOD 0 = IF DROP 0 EXIT THEN
    _CB-A !
    5 _CB-I !
    BEGIN _CB-I @ DUP * _CB-A @ <= WHILE
        _CB-A @ _CB-I @ MOD 0 = IF 0 EXIT THEN
        _CB-A @ _CB-I @ 2 + MOD 0 = IF 0 EXIT THEN
        _CB-I @ 6 + _CB-I !
    REPEAT
    -1 ;

\ =====================================================================
\  COMB-NEXT-PRIME — smallest prime >= n
\ =====================================================================

: COMB-NEXT-PRIME  ( n -- p )
    DUP 2 < IF DROP 2 EXIT THEN
    DUP COMB-IS-PRIME? IF EXIT THEN
    DUP 1 AND 0 = IF 1 + THEN          \ make odd
    BEGIN DUP COMB-IS-PRIME? 0 = WHILE 2 + REPEAT ;

\ =====================================================================
\  COMB-LOG-FACTORIAL — ln(n!) as FP16
\ =====================================================================
\  For n <= 12: exact via COMB-FACTORIAL then EXP-LN.
\  For n > 12: Stirling's approximation:
\    ln(n!) ≈ n·ln(n) − n + 0.5·ln(2πn)

0x4648 CONSTANT _CB-2PI    \ 2π ≈ 6.2832

: COMB-LOG-FACTORIAL  ( n -- ln[n!] )
    DUP 1 <= IF DROP 0x0000 EXIT THEN            \ ln(0!)=ln(1!)=0
    DUP 8 <= IF
        COMB-FACTORIAL INT>FP16 EXP-LN EXIT      \ 8!=40320 fits FP16
    THEN
    \ Stirling: n·ln(n) − n + 0.5·ln(2πn)
    INT>FP16 _CB-A !
    _CB-A @                  ( fp16-n )
    DUP EXP-LN              ( n  ln[n] )
    _CB-A @ FP16-MUL         ( n  n·ln[n] )
    SWAP FP16-SUB             ( n·ln[n] − n )
    _CB-2PI _CB-A @ FP16-MUL  ( ...  2πn )
    EXP-LN                    ( ...  ln[2πn] )
    FP16-HALF FP16-MUL        ( ...  0.5·ln[2πn] )
    FP16-ADD ;                ( n·ln[n] − n + 0.5·ln[2πn] )

\ =====================================================================
\  COMB-LOG-CHOOSE — ln(C(n,k)) as FP16
\ =====================================================================
\  ln(C(n,k)) = ln(n!) − ln(k!) − ln((n−k)!)

: COMB-LOG-CHOOSE  ( n k -- fp16 )
    2DUP -                           \ -- n k n-k
    ROT COMB-LOG-FACTORIAL           \ -- k n-k ln[n!]
    ROT ROT                          \ -- ln[n!] k n-k
    COMB-LOG-FACTORIAL               \ -- ln[n!] k ln[n-k!]
    SWAP COMB-LOG-FACTORIAL          \ -- ln[n!] ln[n-k!] ln[k!]
    FP16-ADD                         \ -- ln[n!] sum
    FP16-SUB ;                       \ -- result

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _comb-guard

' COMB-FACTORIAL  CONSTANT _comb-factorial-xt
' COMB-PERMUTE    CONSTANT _comb-permute-xt
' COMB-CHOOSE     CONSTANT _comb-choose-xt
' COMB-GCD        CONSTANT _comb-gcd-xt
' COMB-LCM        CONSTANT _comb-lcm-xt
' COMB-POWER-MOD  CONSTANT _comb-power-mod-xt
' COMB-IS-PRIME?  CONSTANT _comb-is-prime-q-xt
' COMB-NEXT-PRIME CONSTANT _comb-next-prime-xt
' COMB-LOG-FACTORIAL CONSTANT _comb-log-factorial-xt
' COMB-LOG-CHOOSE CONSTANT _comb-log-choose-xt

: COMB-FACTORIAL  _comb-factorial-xt _comb-guard WITH-GUARD ;
: COMB-PERMUTE    _comb-permute-xt _comb-guard WITH-GUARD ;
: COMB-CHOOSE     _comb-choose-xt _comb-guard WITH-GUARD ;
: COMB-GCD        _comb-gcd-xt _comb-guard WITH-GUARD ;
: COMB-LCM        _comb-lcm-xt _comb-guard WITH-GUARD ;
: COMB-POWER-MOD  _comb-power-mod-xt _comb-guard WITH-GUARD ;
: COMB-IS-PRIME?  _comb-is-prime-q-xt _comb-guard WITH-GUARD ;
: COMB-NEXT-PRIME _comb-next-prime-xt _comb-guard WITH-GUARD ;
: COMB-LOG-FACTORIAL _comb-log-factorial-xt _comb-guard WITH-GUARD ;
: COMB-LOG-CHOOSE _comb-log-choose-xt _comb-guard WITH-GUARD ;
[THEN] [THEN]
