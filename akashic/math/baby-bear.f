\ =================================================================
\  baby-bear.f  —  Baby Bear Field Arithmetic + Batch Inversion
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: BB-
\  Depends on: (none)
\
\  Baby Bear prime field (q = 2013265921 = 15 * 2^27 + 1) with
\  Montgomery's batch inversion trick.
\
\  Public API — Baby Bear arithmetic:
\   BB-Q          ( -- q )              the prime 2013265921
\   BB+           ( a b -- r )          modular addition
\   BB-           ( a b -- r )          modular subtraction
\   BB*           ( a b -- r )          modular multiplication
\   BB-POW        ( base exp -- r )     modular exponentiation
\   BB-INV        ( a -- 1/a )          modular inverse via Fermat
\
\  Public API — packed 32-bit array access:
\   BB-W32@       ( addr -- val )       read  4-byte LE, mask to 32 bits
\   BB-W32!       ( val addr -- )       write 4-byte LE
\
\  Public API — batch inversion:
\   BB-BATCH-INV  ( src dst n -- )      invert n packed 32-bit values
\
\  Montgomery's trick: n inversions in 3(n-1) multiplications +
\  1 Fermat inversion, vs n individual inversions at ~46 muls each.
\
\  Memory: uses two internal scratch buffers sized for up to 1024
\  values (4 KB each).  Caller's src and dst may overlap only if
\  src == dst (in-place).
\
\  Not reentrant (shared scratch buffers and variables).
\ =================================================================

PROVIDED akashic-baby-bear

\ =====================================================================
\  Constants
\ =====================================================================

2013265921 CONSTANT BB-Q

\ =====================================================================
\  Baby Bear field arithmetic
\ =====================================================================

: BB+  ( a b -- r )  + BB-Q MOD ;
: BB-  ( a b -- r )  - BB-Q + BB-Q MOD ;
: BB*  ( a b -- r )  * BB-Q MOD ;

VARIABLE _BI-POW-R
VARIABLE _BI-POW-B
VARIABLE _BI-POW-E

: BB-POW  ( base exp -- result )
    _BI-POW-E !  _BI-POW-B !  1 _BI-POW-R !
    BEGIN _BI-POW-E @ 0> WHILE
        _BI-POW-E @ 1 AND IF
            _BI-POW-R @ _BI-POW-B @ BB*  _BI-POW-R !
        THEN
        _BI-POW-B @ DUP BB*  _BI-POW-B !
        _BI-POW-E @ 1 RSHIFT  _BI-POW-E !
    REPEAT  _BI-POW-R @ ;

\ Fermat's little theorem: a^{-1} = a^{q-2} mod q
: BB-INV  ( a -- 1/a )  BB-Q 2 - BB-POW ;

\ =====================================================================
\  Packed 32-bit array access (little-endian)
\ =====================================================================

\ BB-W32! ( val addr -- )  Write val as 4-byte little-endian.
: BB-W32!  ( val addr -- )
    OVER         OVER    C!
    OVER 8 RSHIFT OVER 1 + C!
    OVER 16 RSHIFT OVER 2 + C!
    SWAP 24 RSHIFT SWAP 3 + C! ;

\ BB-W32@ ( addr -- val )  Read 4-byte LE, mask to 32 bits.
: BB-W32@  ( addr -- val )  @ 0xFFFFFFFF AND ;

\ =====================================================================
\  Batch inversion — Montgomery's trick
\ =====================================================================
\
\  Given src[0..n-1] (packed 32-bit), compute dst[i] = src[i]^{-1}
\  for all i, using:
\    1. Forward sweep:  prefix[0] = src[0]
\                       prefix[i] = prefix[i-1] * src[i]
\    2. One inversion:  inv = prefix[n-1]^{-1}
\    3. Backward sweep: dst[i] = inv * prefix[i-1]   (for i > 0)
\                       inv    = inv * src[i]
\                       dst[0] = inv                   (final)
\
\  Cost: 3(n-1) multiplications + 1 Fermat inversion.
\  Scratch: _BI-PFX buffer (up to 1024 × 4 bytes).

CREATE _BI-PFX  4096 ALLOT    \ prefix products, up to 1024 values

VARIABLE _BI-SRC
VARIABLE _BI-DST
VARIABLE _BI-N
VARIABLE _BI-INV
VARIABLE _BI-J
VARIABLE _BI-TMP

: BB-BATCH-INV  ( src dst n -- )
    _BI-N !  _BI-DST !  _BI-SRC !

    \ --- Forward sweep: build prefix products ---
    \ prefix[0] = src[0]
    _BI-SRC @ BB-W32@  _BI-PFX BB-W32!

    \ prefix[i] = prefix[i-1] * src[i]  for i = 1..n-1
    1 _BI-J !
    BEGIN _BI-J @ _BI-N @ < WHILE
        _BI-J @ 1 - 4 * _BI-PFX + BB-W32@
        _BI-J @ 4 * _BI-SRC @ + BB-W32@
        BB*
        _BI-J @ 4 * _BI-PFX + BB-W32!
        _BI-J @ 1 + _BI-J !
    REPEAT

    \ --- Single inversion ---
    _BI-N @ 1 - 4 * _BI-PFX + BB-W32@  BB-INV  _BI-INV !

    \ --- Backward sweep ---
    \ For i = n-1 down to 1:
    \   dst[i] = inv * prefix[i-1]
    \   inv    = inv * src[i]
    _BI-N @ 1 - _BI-J !
    BEGIN _BI-J @ 0> WHILE
        \ Save src[i] before dst[i] write (in-place safety)
        _BI-J @ 4 * _BI-SRC @ + BB-W32@  _BI-TMP !
        \ dst[i] = inv * prefix[i-1]
        _BI-INV @
        _BI-J @ 1 - 4 * _BI-PFX + BB-W32@
        BB*
        _BI-J @ 4 * _BI-DST @ + BB-W32!
        \ inv = inv * src[i]  (from saved tmp)
        _BI-INV @ _BI-TMP @ BB*  _BI-INV !
        _BI-J @ 1 - _BI-J !
    REPEAT
    \ dst[0] = inv  (which is now src[0]^{-1})
    _BI-INV @  _BI-DST @ BB-W32! ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _bb-guard

' BB+             CONSTANT _bb-add-xt
' BB-             CONSTANT _bb-xt
' BB*             CONSTANT _bb-mul-xt
' BB-POW          CONSTANT _bb-pow-xt
' BB-INV          CONSTANT _bb-inv-xt
' BB-W32!         CONSTANT _bb-w32-s-xt
' BB-W32@         CONSTANT _bb-w32-at-xt
' BB-BATCH-INV    CONSTANT _bb-batch-inv-xt

: BB+             _bb-add-xt _bb-guard WITH-GUARD ;
: BB-             _bb-xt _bb-guard WITH-GUARD ;
: BB*             _bb-mul-xt _bb-guard WITH-GUARD ;
: BB-POW          _bb-pow-xt _bb-guard WITH-GUARD ;
: BB-INV          _bb-inv-xt _bb-guard WITH-GUARD ;
: BB-W32!         _bb-w32-s-xt _bb-guard WITH-GUARD ;
: BB-W32@         _bb-w32-at-xt _bb-guard WITH-GUARD ;
: BB-BATCH-INV    _bb-batch-inv-xt _bb-guard WITH-GUARD ;
[THEN] [THEN]
