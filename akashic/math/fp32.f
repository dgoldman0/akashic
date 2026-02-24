\ fp32.f — Software IEEE 754 single-precision (binary32) arithmetic
\
\ Emulates FP32 using the 64-bit integer ALU.  A float is packed in
\ the low 32 bits of a 64-bit Forth cell.  ~10-20 cycles per op —
\ acceptable for final-stage statistics, not for tight inner loops
\ (that's what the tile engine is for).
\
\ Layout of an IEEE 754 binary32 value (32 bits):
\   [31]    sign       1 bit
\   [30:23] exponent   8 bits (biased by 127)
\   [22:0]  mantissa   23 bits (implicit leading 1 for normals)
\
\ Prefix: FP32-   (public API)
\         _FP32-  (internal helpers)
\
\ Load with:   REQUIRE fp32.f
\
\ === Public API ===
\   FP32-ADD     ( a b -- a+b )      addition
\   FP32-SUB     ( a b -- a-b )      subtraction
\   FP32-MUL     ( a b -- a*b )      multiplication
\   FP32-DIV     ( a b -- a/b )      division
\   FP32-NEGATE  ( a -- -a )         flip sign bit
\   FP32-ABS     ( a -- |a| )        clear sign bit
\   FP32-SQRT    ( a -- sqrt )       square root (Newton, 4 iter)
\   FP32-RECIP   ( a -- 1/a )        reciprocal (Newton, 3 iter)
\   FP32-FMA     ( a b c -- a*b+c )  fused multiply-add
\   FP32<        ( a b -- flag )     less-than
\   FP32>        ( a b -- flag )     greater-than
\   FP32=        ( a b -- flag )     equality (exact, ±0 equal)
\   FP32<=       ( a b -- flag )     less-or-equal
\   FP32>=       ( a b -- flag )     greater-or-equal
\   FP32-0=      ( a -- flag )       is ±0?
\   FP32-MIN     ( a b -- min )      minimum
\   FP32-MAX     ( a b -- max )      maximum
\   FP16>FP32    ( fp16 -- fp32 )    widen (lossless)
\   FP32>FP16    ( fp32 -- fp16 )    narrow (round-to-nearest-even)
\   FP32>FX      ( fp32 -- fx16.16 ) to fixed-point
\   FX>FP32      ( fx16.16 -- fp32 ) from fixed-point
\   FP32>INT     ( fp32 -- n )       truncate to integer
\   INT>FP32     ( n -- fp32 )       integer to FP32
\   ACC>FP32     ( -- fp32 )         read tile accumulator as FP32

PROVIDED akashic-fp32

\ =====================================================================
\  Constants: well-known FP32 bit patterns
\ =====================================================================

0x00000000 CONSTANT FP32-ZERO
0x3F800000 CONSTANT FP32-ONE
0x3F000000 CONSTANT FP32-HALF
0x40000000 CONSTANT FP32-TWO
0x40490FDB CONSTANT FP32-PI
0x402DF854 CONSTANT FP32-E
0x7F800000 CONSTANT FP32-INF
0x7FC00000 CONSTANT FP32-NAN

0xFFFFFFFF CONSTANT _FP32-MASK

\ =====================================================================
\  Internal: field extraction / packing
\ =====================================================================

: _FP32-SIGN  ( fp32 -- 0|1 )
    31 RSHIFT 1 AND ;

: _FP32-EXP  ( fp32 -- biased-exp )
    23 RSHIFT 0xFF AND ;

: _FP32-FRAC  ( fp32 -- 23-bit-fraction )
    0x7FFFFF AND ;

: _FP32-PACK  ( sign biased-exp frac23 -- fp32 )
    >R >R                             ( sign ) ( R: frac exp )
    31 LSHIFT                          ( sign-bit )
    R> 23 LSHIFT OR                    ( sign|exp )
    R> 0x7FFFFF AND OR                 ( fp32 )
    _FP32-MASK AND ;

\ =====================================================================
\  Internal: classify
\ =====================================================================

: _FP32-INF?  ( fp32 -- flag )
    _FP32-MASK AND 0x7FFFFFFF AND 0x7F800000 = ;

: _FP32-NAN?  ( fp32 -- flag )
    _FP32-MASK AND 0x7FFFFFFF AND
    0x7F800000 > ;

: _FP32-ZERO?  ( fp32 -- flag )
    _FP32-MASK AND 0x7FFFFFFF AND 0= ;

\ =====================================================================
\  Unary: negate, abs, sign queries
\ =====================================================================

: FP32-NEGATE  ( a -- -a )
    0x80000000 XOR _FP32-MASK AND ;

: FP32-ABS  ( a -- |a| )
    0x7FFFFFFF AND ;

: FP32-0=  ( a -- flag )
    _FP32-ZERO? ;

\ =====================================================================
\  Comparison: sign-magnitude to sortable key, then integer compare
\ =====================================================================
\  Same approach as fp16-ext.f but for 32-bit FP.

VARIABLE _F32-KA
VARIABLE _F32-KB

: _FP32-SORTKEY  ( fp32 -- key )
    _FP32-MASK AND
    \ Canonicalize ±0 → +0
    DUP 0x7FFFFFFF AND 0= IF DROP 0 THEN
    DUP 0x80000000 AND IF
        0xFFFFFFFF XOR                 \ negative → flip all bits
    ELSE
        0x80000000 +                   \ positive → shift above negatives
    THEN ;

: FP32<  ( a b -- flag )
    _FP32-SORTKEY SWAP _FP32-SORTKEY SWAP U< ;

: FP32>  ( a b -- flag )
    SWAP FP32< ;

: FP32=  ( a b -- flag )
    _FP32-SORTKEY SWAP _FP32-SORTKEY = ;

: FP32<=  ( a b -- flag )
    FP32> 0= ;

: FP32>=  ( a b -- flag )
    FP32< 0= ;

: FP32-MIN  ( a b -- min )
    2DUP FP32> IF SWAP THEN DROP ;

: FP32-MAX  ( a b -- max )
    2DUP FP32< IF SWAP THEN DROP ;

\ =====================================================================
\  FP32-ADD — IEEE 754 binary32 addition
\ =====================================================================
\  Algorithm:
\    1. Handle special cases (zero, inf, NaN)
\    2. Unpack both operands to (sign, exp, mantissa24)
\    3. Align mantissas by shifting the smaller one right
\    4. Add or subtract mantissas (depending on sign combination)
\    5. Normalize: shift mantissa, adjust exponent
\    6. Round to nearest even and pack

VARIABLE _FA-SA    \ sign A
VARIABLE _FA-SB    \ sign B
VARIABLE _FA-EA    \ biased exponent A
VARIABLE _FA-EB    \ biased exponent B
VARIABLE _FA-MA    \ mantissa A (24 bits: implicit 1 + 23 fraction)
VARIABLE _FA-MB    \ mantissa B
VARIABLE _FA-DIFF  \ exponent difference
VARIABLE _FA-RS    \ result sign
VARIABLE _FA-RE    \ result exponent
VARIABLE _FA-RM    \ result mantissa (with guard bits)

: FP32-ADD  ( a b -- a+b )
    _FP32-MASK AND SWAP _FP32-MASK AND SWAP
    \ NaN check
    OVER _FP32-NAN? IF DROP EXIT THEN
    DUP  _FP32-NAN? IF NIP  EXIT THEN
    \ Zero + x = x, x + 0 = x
    OVER _FP32-ZERO? IF NIP  EXIT THEN
    DUP  _FP32-ZERO? IF DROP EXIT THEN
    \ Inf handling
    OVER _FP32-INF? IF
        DUP _FP32-INF? IF
            \ inf + inf: same sign → inf, diff sign → NaN
            OVER 0x80000000 AND OVER 0x80000000 AND = IF
                DROP EXIT             \ same sign: return a (inf)
            ELSE
                2DROP FP32-NAN EXIT   \ opposite: NaN
            THEN
        THEN
        DROP EXIT                      \ inf + finite = inf
    THEN
    DUP _FP32-INF? IF NIP EXIT THEN   \ finite + inf = inf
    \ --- Unpack A ---
    OVER _FP32-SIGN _FA-SA !
    OVER _FP32-EXP  _FA-EA !
    OVER _FP32-FRAC 0x800000 OR _FA-MA !   \ implicit 1
    \ --- Unpack B ---
    DUP _FP32-SIGN _FA-SB !
    DUP _FP32-EXP  _FA-EB !
    DUP _FP32-FRAC 0x800000 OR _FA-MB !
    2DROP
    \ --- Exponent alignment ---
    \ Shift mantissa of the smaller exponent right.
    \ Use 3 guard bits (26-bit working mantissa) for rounding.
    _FA-MA @ 3 LSHIFT _FA-MA !         \ 27-bit working
    _FA-MB @ 3 LSHIFT _FA-MB !
    _FA-EA @ _FA-EB @ - _FA-DIFF !
    _FA-DIFF @ 0 > IF
        \ A has larger exponent — shift B right
        _FA-DIFF @ 27 MIN DUP >R
        _FA-MB @ SWAP RSHIFT _FA-MB !
        R> DROP
        _FA-EA @ _FA-RE !
    ELSE _FA-DIFF @ 0 < IF
        \ B has larger exponent — shift A right
        _FA-DIFF @ NEGATE 27 MIN DUP >R
        _FA-MA @ SWAP RSHIFT _FA-MA !
        R> DROP
        _FA-EB @ _FA-RE !
    ELSE
        _FA-EA @ _FA-RE !
    THEN THEN
    \ --- Add or subtract mantissas ---
    _FA-SA @ _FA-SB @ = IF
        \ Same sign: add magnitudes, result has same sign
        _FA-SA @ _FA-RS !
        _FA-MA @ _FA-MB @ + _FA-RM !
    ELSE
        \ Different signs: subtract smaller from larger
        _FA-MA @ _FA-MB @ > IF
            _FA-SA @ _FA-RS !
            _FA-MA @ _FA-MB @ - _FA-RM !
        ELSE _FA-MA @ _FA-MB @ < IF
            _FA-SB @ _FA-RS !
            _FA-MB @ _FA-MA @ - _FA-RM !
        ELSE
            \ Equal magnitudes, different signs → +0.0
            FP32-ZERO EXIT
        THEN THEN
    THEN
    \ --- Normalize ---
    _FA-RM @ 0= IF FP32-ZERO EXIT THEN
    \ Shift right first if overflow (bit 27+)
    BEGIN _FA-RM @ 0x8000000 AND WHILE
        _FA-RM @ 1 RSHIFT _FA-RM !
        _FA-RE @ 1+ _FA-RE !
    REPEAT
    \ Then shift left until bit 26 is set (implicit 1 position with 3 guard bits)
    BEGIN _FA-RM @ 0x4000000 AND 0= WHILE
        _FA-RM @ 1 LSHIFT _FA-RM !
        _FA-RE @ 1- _FA-RE !
    REPEAT
    \ --- Round to nearest even (on 3 guard bits) ---
    _FA-RM @ 7 AND                     ( guard bits )
    _FA-RM @ 3 RSHIFT _FA-RM !        ( drop guard bits → 24-bit mantissa )
    DUP 4 > IF                         \ > 0.5 → round up
        _FA-RM @ 1+ _FA-RM !
    ELSE 4 = IF                         \ exactly 0.5 → round to even
        _FA-RM @ 1 AND IF              \ odd → round up
            _FA-RM @ 1+ _FA-RM !
        THEN
    THEN THEN
    \ Check for mantissa overflow after rounding
    _FA-RM @ 0x1000000 AND IF
        _FA-RM @ 1 RSHIFT _FA-RM !
        _FA-RE @ 1+ _FA-RE !
    THEN
    \ --- Overflow / underflow ---
    _FA-RE @ 255 >= IF
        _FA-RS @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT   \ ±inf
    THEN
    _FA-RE @ 0 <= IF
        FP32-ZERO _FA-RS @ IF FP32-NEGATE THEN EXIT   \ underflow → ±0
    THEN
    \ --- Pack ---
    _FA-RS @ _FA-RE @ _FA-RM @ 0x7FFFFF AND _FP32-PACK ;

\ =====================================================================
\  FP32-SUB — subtraction: a - b = a + (-b)
\ =====================================================================

: FP32-SUB  ( a b -- a-b )
    FP32-NEGATE FP32-ADD ;

\ =====================================================================
\  FP32-MUL — IEEE 754 binary32 multiplication
\ =====================================================================
\  Algorithm:
\    1. Result sign = sign_a XOR sign_b
\    2. Result exponent = exp_a + exp_b - 127
\    3. Mantissa: 24×24 → 48-bit product (fits in 64-bit cell)
\    4. Normalize (shift so bit 47 is the implicit 1)
\    5. Round to 24 bits, pack

VARIABLE _FM-SA
VARIABLE _FM-SB
VARIABLE _FM-EA
VARIABLE _FM-EB
VARIABLE _FM-RE
VARIABLE _FM-RS
VARIABLE _FM-PROD   \ 48-bit product (fits in 64-bit cell)

: FP32-MUL  ( a b -- a*b )
    _FP32-MASK AND SWAP _FP32-MASK AND SWAP
    \ NaN
    OVER _FP32-NAN? IF DROP EXIT THEN
    DUP  _FP32-NAN? IF NIP  EXIT THEN
    \ Sign of result
    OVER _FP32-SIGN OVER _FP32-SIGN XOR _FM-RS !
    \ Inf × 0 = NaN; Inf × finite = Inf
    OVER _FP32-INF? IF
        DUP _FP32-ZERO? IF 2DROP FP32-NAN EXIT THEN
        2DROP _FM-RS @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT
    THEN
    DUP _FP32-INF? IF
        OVER _FP32-ZERO? IF 2DROP FP32-NAN EXIT THEN
        2DROP _FM-RS @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT
    THEN
    \ Zero
    OVER _FP32-ZERO? IF 2DROP _FM-RS @ 31 LSHIFT _FP32-MASK AND EXIT THEN
    DUP  _FP32-ZERO? IF 2DROP _FM-RS @ 31 LSHIFT _FP32-MASK AND EXIT THEN
    \ Unpack
    OVER _FP32-EXP _FM-EA !
    OVER _FP32-FRAC 0x800000 OR   ( mant_a )
    >R
    DUP _FP32-EXP _FM-EB !
    _FP32-FRAC 0x800000 OR        ( a mant_b ) ( R: mant_a )
    NIP                            \ drop a, keep mant_b
    R>                             ( mant_b mant_a )
    \ 24×24 → 48-bit product
    * _FM-PROD !
    \ Result exponent (before normalization)
    _FM-EA @ _FM-EB @ + 127 - _FM-RE !
    \ Normalize: the product of two 1.23 mantissas is in [1.0, 4.0)
    \ i.e., bits 46 or 47 hold the implicit 1.
    \ If bit 47 set (product >= 2.0): shift right 1, exp+1
    _FM-PROD @ 47 RSHIFT 1 AND IF
        \ Product in [2.0, 4.0) — bit 47 set
        \ Take bits [47:24] as 24-bit mantissa (drop bit 47 = implicit 1)
        _FM-RE @ 1+ _FM-RE !
        \ Round: check bit 23 (first dropped) and sticky bits [22:0]
        _FM-PROD @ 23 RSHIFT 1 AND    ( round bit )
        _FM-PROD @ 0x7FFFFF AND 0<>   ( sticky )
        OR IF
            _FM-PROD @ 24 RSHIFT 1+
        ELSE
            _FM-PROD @ 24 RSHIFT
        THEN
    ELSE
        \ Product in [1.0, 2.0) — bit 46 set
        \ Take bits [46:23] as 24-bit mantissa
        _FM-PROD @ 22 RSHIFT 1 AND    ( round bit )
        _FM-PROD @ 0x3FFFFF AND 0<>   ( sticky )
        OR IF
            _FM-PROD @ 23 RSHIFT 1+
        ELSE
            _FM-PROD @ 23 RSHIFT
        THEN
    THEN
    ( mantissa24 )
    \ Handle rounding overflow (24-bit mantissa → 25 bits)
    DUP 0x1000000 AND IF
        1 RSHIFT
        _FM-RE @ 1+ _FM-RE !
    THEN
    \ Overflow / underflow
    _FM-RE @ 255 >= IF
        DROP _FM-RS @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT
    THEN
    _FM-RE @ 0 <= IF
        DROP _FM-RS @ 31 LSHIFT _FP32-MASK AND EXIT
    THEN
    0x7FFFFF AND
    _FM-RS @ _FM-RE @ ROT _FP32-PACK ;

\ =====================================================================
\  FP32-DIV — IEEE 754 binary32 division
\ =====================================================================
\  Uses integer long division: shift numerator mantissa left 24 bits,
\  divide by denominator mantissa, yielding a 24-bit quotient.

VARIABLE _FD-SA
VARIABLE _FD-SB
VARIABLE _FD-EA
VARIABLE _FD-EB
VARIABLE _FD-RS
VARIABLE _FD-RE
VARIABLE _FD-NUMA
VARIABLE _FD-DENB
VARIABLE _FD-Q

: FP32-DIV  ( a b -- a/b )
    _FP32-MASK AND SWAP _FP32-MASK AND SWAP
    \ NaN
    OVER _FP32-NAN? IF DROP EXIT THEN
    DUP  _FP32-NAN? IF NIP  EXIT THEN
    \ Sign
    OVER _FP32-SIGN OVER _FP32-SIGN XOR _FD-RS !
    \ 0/0 = NaN, x/0 = ±inf
    DUP _FP32-ZERO? IF
        OVER _FP32-ZERO? IF 2DROP FP32-NAN EXIT THEN
        2DROP _FD-RS @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT
    THEN
    \ inf/inf = NaN, inf/x = ±inf
    OVER _FP32-INF? IF
        DUP _FP32-INF? IF 2DROP FP32-NAN EXIT THEN
        2DROP _FD-RS @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT
    THEN
    \ x/inf = ±0
    DUP _FP32-INF? IF
        2DROP _FD-RS @ 31 LSHIFT _FP32-MASK AND EXIT
    THEN
    \ 0/x = ±0
    OVER _FP32-ZERO? IF
        2DROP _FD-RS @ 31 LSHIFT _FP32-MASK AND EXIT
    THEN
    \ Unpack
    OVER _FP32-EXP _FD-EA !
    OVER _FP32-FRAC 0x800000 OR _FD-NUMA !
    DUP  _FP32-EXP _FD-EB !
    _FP32-FRAC 0x800000 OR _FD-DENB !
    DROP                               \ drop a
    \ Result exponent
    _FD-EA @ _FD-EB @ - 127 + _FD-RE !
    \ Long division: (numa << 23) / denb → quotient is ~24 bits
    _FD-NUMA @ 23 LSHIFT _FD-DENB @ / _FD-Q !
    \ Remainder for rounding
    _FD-NUMA @ 23 LSHIFT _FD-DENB @ MOD 0<> IF
        _FD-Q @ 1+ _FD-Q !            \ round up if remainder
    THEN
    \ Normalize quotient: should have bit 23 set (implicit 1)
    \ If bit 24 set, shift right
    _FD-Q @ 0x1000000 AND IF
        _FD-Q @ 1 RSHIFT _FD-Q !
        _FD-RE @ 1+ _FD-RE !
    THEN
    \ If bit 23 not set, shift left
    BEGIN _FD-Q @ 0x800000 AND 0= _FD-Q @ 0<> AND WHILE
        _FD-Q @ 1 LSHIFT _FD-Q !
        _FD-RE @ 1- _FD-RE !
    REPEAT
    \ Overflow / underflow
    _FD-RE @ 255 >= IF
        _FD-RS @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT
    THEN
    _FD-RE @ 0 <= IF
        _FD-RS @ 31 LSHIFT _FP32-MASK AND EXIT
    THEN
    _FD-Q @ 0x7FFFFF AND
    _FD-RS @ _FD-RE @ ROT _FP32-PACK ;

\ =====================================================================
\  FP32-FMA — fused multiply-add: a * b + c
\ =====================================================================
\  Full FMA requires keeping 48-bit product and adding c before
\  rounding.  For simplicity and correctness in stats (where this
\  is used for Welford updates), we implement as MUL then ADD.
\  This gives MUL-then-ADD rounding (two roundings) which is
\  acceptable for our precision needs.

: FP32-FMA  ( a b c -- a*b+c )
    >R FP32-MUL R> FP32-ADD ;

\ =====================================================================
\  FP32-RECIP — reciprocal via Newton-Raphson
\ =====================================================================
\  Initial estimate: manipulate exponent bits.
\  Magic constant: 0x7EF127EA - x gives a good initial reciprocal
\  for x in normal range.  Then refine with r = r * (2 - x*r).

: FP32-RECIP  ( a -- 1/a )
    _FP32-MASK AND
    DUP _FP32-NAN? IF EXIT THEN
    DUP _FP32-ZERO? IF DROP FP32-INF EXIT THEN
    DUP _FP32-INF?  IF DROP FP32-ZERO EXIT THEN
    DUP >R                             ( a ) ( R: a )
    \ Save sign, work with |a|
    FP32-ABS
    DUP >R                             ( |a| ) ( R: a |a| )
    \ Initial estimate: 0x7EF127EA - |a|
    0x7EF127EA SWAP - _FP32-MASK AND   ( r0 )
    \ Newton iteration 1: r = r * (2 - |a|*r)
    DUP R@ FP32-MUL                    ( r0 |a|*r0 )
    FP32-TWO SWAP FP32-SUB             ( r0 2-|a|*r0 )
    FP32-MUL                           ( r1 )
    \ Newton iteration 2
    DUP R@ FP32-MUL
    FP32-TWO SWAP FP32-SUB
    FP32-MUL                           ( r2 )
    \ Newton iteration 3
    DUP R> FP32-MUL
    FP32-TWO SWAP FP32-SUB
    FP32-MUL                           ( r3 )
    \ Restore original sign
    R> _FP32-SIGN IF FP32-NEGATE THEN ;

\ =====================================================================
\  FP32-SQRT — square root via Newton-Raphson
\ =====================================================================
\  Initial estimate: halve the exponent.
\  Magic: sqrt0 = (x >> 1) + 0x1FBB4000
\  Then refine: s' = 0.5 * (s + x/s)   [4 iterations]
\
\  Negative input → NaN.  Zero → Zero.  Inf → Inf.

: FP32-SQRT  ( a -- sqrt[a] )
    _FP32-MASK AND
    DUP _FP32-NAN?  IF EXIT THEN
    DUP _FP32-ZERO? IF EXIT THEN
    DUP _FP32-INF?  IF
        DUP _FP32-SIGN IF DROP FP32-NAN EXIT THEN   \ sqrt(-inf) = NaN
        EXIT                           \ sqrt(+inf) = inf
    THEN
    DUP _FP32-SIGN IF DROP FP32-NAN EXIT THEN   \ negative → NaN
    DUP >R                             ( x ) ( R: x )
    \ Initial estimate: (x >> 1) + 0x1FBB4000
    1 RSHIFT 0x1FBB4000 + _FP32-MASK AND   ( s0 )
    \ Newton iteration 1: s = 0.5 * (s + x/s)
    DUP R@ SWAP FP32-DIV               ( s0 x/s0 )
    FP32-ADD FP32-HALF FP32-MUL        ( s1 )
    \ Newton iteration 2
    DUP R@ SWAP FP32-DIV
    FP32-ADD FP32-HALF FP32-MUL        ( s2 )
    \ Newton iteration 3
    DUP R@ SWAP FP32-DIV
    FP32-ADD FP32-HALF FP32-MUL        ( s3 )
    \ Newton iteration 4
    DUP R> SWAP FP32-DIV
    FP32-ADD FP32-HALF FP32-MUL ;      ( s4 )

\ =====================================================================
\  Conversions: FP16 ↔ FP32
\ =====================================================================
\  FP16: sign(1) | exp(5) | mant(10)
\  FP32: sign(1) | exp(8) | mant(23)
\  Widening: exponent rebias (15 → 127), mantissa shift left 13.
\  Narrowing: exponent rebias (127 → 15), mantissa shift right 13
\             with round-to-nearest-even.

: FP16>FP32  ( fp16 -- fp32 )
    0xFFFF AND
    DUP 0x7FFF AND 0= IF              \ ±0
        0x8000 AND IF 0x80000000 ELSE 0 THEN EXIT
    THEN
    DUP 0x7C00 AND 0x7C00 = IF        \ Inf or NaN
        DUP 0x7FFF AND 0x7C00 = IF    \ exactly Inf
            0x8000 AND IF 0xFF800000 ELSE 0x7F800000 THEN EXIT
        THEN
        \ NaN: preserve payload
        DUP 0x8000 AND 16 LSHIFT       ( fp16 sign-bit-fp32 )
        SWAP 0x3FF AND 13 LSHIFT       ( sign payload )
        0x7FC00000 OR OR _FP32-MASK AND EXIT
    THEN
    \ Normal value
    DUP 0x8000 AND 16 LSHIFT >R        ( fp16 ) ( R: sign32 )  \ 0x8000<<16 = 0x80000000
    DUP 10 RSHIFT 0x1F AND             ( fp16 exp5 )
    112 +                              ( fp16 biased-exp8 )  \ 127 - 15 = 112
    SWAP 0x3FF AND 13 LSHIFT           ( exp8 frac23 )
    SWAP 23 LSHIFT OR R> OR _FP32-MASK AND ;

: FP32>FP16  ( fp32 -- fp16 )
    _FP32-MASK AND
    DUP _FP32-NAN? IF
        DROP 0x7E00 EXIT               \ FP16 qNaN
    THEN
    DUP _FP32-ZERO? IF
        _FP32-SIGN IF 0x8000 ELSE 0 THEN EXIT
    THEN
    DUP _FP32-INF? IF
        _FP32-SIGN IF 0xFC00 ELSE 0x7C00 THEN EXIT
    THEN
    DUP _FP32-SIGN 15 LSHIFT >R        ( fp32 ) ( R: sign16 )
    DUP _FP32-EXP 112 -                ( fp32 exp5 )  \ rebias 127→15
    DUP 31 > IF
        2DROP R> 0x7C00 OR EXIT         \ overflow → ±inf
    THEN
    DUP 0 <= IF
        2DROP R> EXIT                   \ underflow → ±0
    THEN
    SWAP _FP32-FRAC                     ( exp5 frac23 )
    \ Round-to-nearest-even on the 13 dropped bits
    DUP 0x1FFF AND                      ( exp5 frac23 guard13 )
    SWAP 13 RSHIFT                      ( exp5 guard13 frac10 )
    SWAP                                ( exp5 frac10 guard13 )
    DUP 0x1000 > IF                     \ > 0.5 → round up
        DROP 1+
    ELSE 0x1000 = IF                    \ = 0.5 → round to even
        OVER 1 AND IF 1+ THEN
    THEN THEN
    \ Check for mantissa overflow after rounding
    DUP 0x400 AND IF                    \ bit 10 set → overflow
        1 RSHIFT
        SWAP 1+ SWAP                    \ exp5++
    THEN
    0x3FF AND                           ( exp5 frac10 )
    SWAP DUP 31 > IF                    \ exp overflow after rounding
        2DROP R> 0x7C00 OR EXIT
    THEN
    10 LSHIFT OR R> OR 0xFFFF AND ;

\ =====================================================================
\  Conversions: FP32 ↔ 16.16 fixed-point
\ =====================================================================

VARIABLE _F2X-SIGN
VARIABLE _F2X-EXP
VARIABLE _F2X-MANT

: FP32>FX  ( fp32 -- fx16.16 )
    _FP32-MASK AND
    DUP _FP32-ZERO? IF DROP 0 EXIT THEN
    DUP _FP32-NAN?  IF DROP 0 EXIT THEN
    DUP _FP32-INF?  IF
        _FP32-SIGN IF -2147483648 ELSE 2147483647 THEN EXIT
    THEN
    DUP _FP32-SIGN _F2X-SIGN !
    DUP _FP32-EXP  _F2X-EXP !
    _FP32-FRAC 0x800000 OR _F2X-MANT !
    \ Unbiased exponent
    _F2X-EXP @ 127 - _F2X-EXP !
    \ 16.16: mantissa is 1.23.  To get 16.16, shift by (exp - 23 + 16) = (exp - 7)
    _F2X-EXP @ 7 - DUP 0 >= IF
        _F2X-MANT @ SWAP LSHIFT
    ELSE
        NEGATE _F2X-MANT @ SWAP RSHIFT
    THEN
    _F2X-SIGN @ IF NEGATE THEN ;

VARIABLE _X2F-SIGN
VARIABLE _X2F-MAG
VARIABLE _X2F-MSB

: FX>FP32  ( fx16.16 -- fp32 )
    DUP 0= IF DROP FP32-ZERO EXIT THEN
    DUP 0 < IF
        NEGATE 1 _X2F-SIGN !
    ELSE
        0 _X2F-SIGN !
    THEN
    _X2F-MAG !
    \ Find highest set bit position (0-based)
    0 _X2F-MSB !
    _X2F-MAG @
    BEGIN DUP 1 > WHILE
        1 RSHIFT
        _X2F-MSB @ 1+ _X2F-MSB !
    REPEAT
    DROP
    \ FP32 exponent: msb_pos - 16 + 127 = msb_pos + 111
    _X2F-MSB @ 111 + DUP 255 >= IF
        DROP _X2F-SIGN @ 31 LSHIFT 0x7F800000 OR _FP32-MASK AND EXIT
    THEN
    DUP 0 <= IF
        DROP _X2F-SIGN @ 31 LSHIFT _FP32-MASK AND EXIT
    THEN
    ( biased-exp )
    \ Extract 23-bit mantissa from magnitude
    _X2F-MSB @ 23 > IF
        _X2F-MAG @ _X2F-MSB @ 23 - RSHIFT
    ELSE
        _X2F-MAG @ 23 _X2F-MSB @ - LSHIFT
    THEN
    0x7FFFFF AND
    ( biased-exp frac23 )
    _X2F-SIGN @ ROT ROT _FP32-PACK ;

\ =====================================================================
\  Conversions: FP32 ↔ integer
\ =====================================================================

VARIABLE _F2I-SIGN
VARIABLE _F2I-EXP
VARIABLE _F2I-MANT

: FP32>INT  ( fp32 -- n )
    _FP32-MASK AND
    DUP _FP32-ZERO? IF DROP 0 EXIT THEN
    DUP _FP32-NAN?  IF DROP 0 EXIT THEN
    DUP _FP32-INF?  IF
        _FP32-SIGN IF -2147483648 ELSE 2147483647 THEN EXIT
    THEN
    DUP _FP32-SIGN _F2I-SIGN !
    DUP _FP32-EXP  _F2I-EXP !
    _FP32-FRAC 0x800000 OR _F2I-MANT !
    _F2I-EXP @ 127 - _F2I-EXP !       \ unbias
    _F2I-EXP @ 0 < IF 0 EXIT THEN     \ |val| < 1 → 0
    \ Shift mantissa: mantissa is 1.23 fixed.
    \ Integer part is mantissa >> (23 - exp) when exp < 23,
    \ or mantissa << (exp - 23) when exp >= 23.
    _F2I-EXP @ 23 >= IF
        _F2I-MANT @ _F2I-EXP @ 23 - LSHIFT
    ELSE
        _F2I-MANT @ 23 _F2I-EXP @ - RSHIFT
    THEN
    _F2I-SIGN @ IF NEGATE THEN ;

VARIABLE _I2F-SIGN
VARIABLE _I2F-MAG
VARIABLE _I2F-MSB

: INT>FP32  ( n -- fp32 )
    DUP 0= IF DROP FP32-ZERO EXIT THEN
    DUP 0 < IF
        NEGATE 1 _I2F-SIGN !
    ELSE
        0 _I2F-SIGN !
    THEN
    _I2F-MAG !
    \ Find highest set bit position (0-based)
    0 _I2F-MSB !
    _I2F-MAG @
    BEGIN DUP 1 > WHILE
        1 RSHIFT
        _I2F-MSB @ 1+ _I2F-MSB !
    REPEAT
    DROP
    \ Biased exponent: msb + 127
    _I2F-MSB @ 127 +
    \ Extract 23-bit mantissa
    _I2F-MSB @ 23 > IF
        _I2F-MAG @ _I2F-MSB @ 23 - RSHIFT
    ELSE
        _I2F-MAG @ 23 _I2F-MSB @ - LSHIFT
    THEN
    0x7FFFFF AND
    _I2F-SIGN @ ROT ROT _FP32-PACK ;

\ =====================================================================
\  ACC>FP32 — read tile accumulator CSR as FP32
\ =====================================================================
\  The tile engine accumulator (ACC@, CSR 0x19) holds the FP32 result
\  of reduction operations (TSUM, TSUMSQ, TDOT, etc.).
\  The low 32 bits of the 64-bit CSR value are the IEEE 754 binary32.

: ACC>FP32  ( -- fp32 )
    ACC@ _FP32-MASK AND ;
