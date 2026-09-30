\ =====================================================================
\  numeric/decimal.f - Decimal text for FP32 and FP64 values
\ =====================================================================
\  Every binary floating-point value is a finite decimal fraction, so
\  these words work exactly, on a small big-integer core:
\
\    NDEC-FORMAT  the shortest decimal that reads back as the same
\                 value, laid out like Python's repr: 0.1, 1e-05,
\                 1e+16, -0.0, inf, nan.
\    NDEC-FIXED   the value rounded to a number of decimal places, ties
\                 to even, laid out like Python's f"{x:.3f}".
\    NDEC-PARSE   decimal text read as the nearest value, ties to even,
\                 like C's strtod.
\
\  A value is raw IEEE bits in a cell (numeric/array.f), in the format
\  NUM-FP32 or NUM-FP64.  Text goes to, or comes from, a caller's
\  buffer.  Scratch comes from a caller workspace of NDEC-WS-BYTES, so
\  the words keep no module state and any core may use them.
\
\  The shortest digits come from Burger and Dybvig's free-format
\  algorithm ("Printing Floating-Point Numbers Quickly and Accurately",
\  1996), with ties to the even digit.  Fixed places round the value's
\  exact decimal expansion.  Parsing takes one rounded operation when the
\  digits and the power of ten are both exact in the format; otherwise
\  it divides exactly.  It rounds to nearest even whatever the mode in
\  FPCSR is, and leaves that mode as it found it.
\
\  Prefix: NDEC-  public API
\          _NDEC- internal helpers
\          _NDB-  big integers
\          _NDF-  workspace frame fields
\
\  Load with:   REQUIRE numeric/decimal.f
\ =====================================================================

PROVIDED akashic-numeric-decimal

REQUIRE array.f

\ =====================================================================
\  Big integers
\ =====================================================================
\  A big integer is a limb count, then up to _NDB-CAP limbs of 32 bits,
\  least significant first, one per cell.  32-bit limbs keep every
\  product, and every division by a number below 2^30, inside one cell.
\  The largest number built here is below 2^3800, 119 limbs: a parsed
\  value's 800 digits, shifted to leave 54 quotient bits over 10^1124.

128 CONSTANT _NDB-CAP
_NDB-CAP 1 + CELLS CONSTANT _NDB-BYTES

: _NDB-LIMB  ( i b -- addr )  SWAP 1 + CELLS + ;

\ Limb i of b, or 0 above its top.
: _NDB@  ( i b -- u )
    2DUP @ < IF _NDB-LIMB @ ELSE 2DROP 0 THEN ;

\ Drop zero limbs from the top.
: _NDB-TRIM  ( b -- )
    BEGIN DUP @ DUP IF CELLS OVER + @ 0= THEN WHILE -1 OVER +! REPEAT DROP ;

: _NDB-SET  ( u b -- )
    2 OVER !
    OVER 0xFFFFFFFF AND OVER 8 + !
    SWAP 32 RSHIFT OVER 16 + !
    _NDB-TRIM ;

: _NDB-COPY  ( src dst -- )  OVER @ 1 + CELLS CMOVE ;

\ b as a cell, when it has at most two limbs.
: _NDB-CELL  ( b -- u )  0 OVER _NDB@ 1 ROT _NDB@ 32 LSHIFT OR ;

\ b = b * k + c, for k and c below 2^32.
: _NDB-MULADD  ( k c b -- )
    >R
    R@ 8 + DUP R@ @ CELLS + SWAP ?DO
        OVER I @ * +
        DUP 0xFFFFFFFF AND I !
        32 RSHIFT
    8 +LOOP
    NIP ?DUP IF R@ @ 1 + DUP R@ ! CELLS R@ + ! THEN
    R> DROP ;

\ b = floor(b / d), and r = b mod d, for d below 2^30.
: _NDB-DIVMOD  ( d b -- r )
    DUP >R @ CELLS R@ + 0 SWAP
    BEGIN DUP R@ > WHILE
        DUP @ ROT 32 LSHIFT OR 2 PICK /MOD 2 PICK ! SWAP 8 -
    REPEAT
    DROP NIP R> _NDB-TRIM ;

\ -1, 0, or 1 as a is below, equal to, or above b.
: _NDB-CMP  ( a b -- n )
    OVER @ OVER @ 2DUP <> IF < IF 2DROP -1 ELSE 2DROP 1 THEN EXIT THEN
    DROP
    BEGIN DUP WHILE
        >R OVER R@ CELLS + @ OVER R@ CELLS + @
        2DUP <> IF < IF R> DROP 2DROP -1 ELSE R> DROP 2DROP 1 THEN EXIT THEN
        2DROP R> 1 -
    REPEAT
    DROP 2DROP 0 ;

\ a = a + b.
: _NDB-ADD  ( a b -- )
    0 2 PICK @ 2 PICK @ MAX 0 ?DO
        I 3 PICK _NDB@ I 3 PICK _NDB@ + +
        DUP 0xFFFFFFFF AND 3 PICK I 1 + CELLS + !
        32 RSHIFT
    LOOP
    >R OVER @ OVER @ MAX 2 PICK ! R>
    ?DUP IF 2 PICK @ 1 + DUP 4 PICK ! CELLS 3 PICK + ! THEN
    2DROP ;

\ a = a - b, for a >= b.
: _NDB-SUB  ( a b -- )
    0 2 PICK @ 0 ?DO
        2 PICK I 1 + CELLS + DUP @
        I 4 PICK _NDB@ - ROT -
        DUP 0< IF 0x100000000 + SWAP ! 1 ELSE SWAP ! 0 THEN
    LOOP
    2DROP _NDB-TRIM ;

\ b = b * 2^s.
: _NDB-SHL  ( s b -- )
    DUP @ 0= IF 2DROP EXIT THEN
    >R 32 /MOD
    0 R@ @ 2 PICK + 1 + CELLS R@ + !
    R@ @ BEGIN DUP WHILE 1 -
        DUP 1 + CELLS R@ + @ 3 PICK LSHIFT
        OVER 3 PICK + 1 + CELLS R@ +
        OVER 0xFFFFFFFF AND OVER !
        8 + SWAP 32 RSHIFT OVER @ OR SWAP !
    REPEAT DROP
    R@ 8 + DUP 2 PICK CELLS + SWAP ?DO 0 I ! 8 +LOOP
    R@ @ + 1 + R@ ! DROP
    R> _NDB-TRIM ;

\ b = floor(b / 2).
: _NDB-HALVE  ( b -- )
    DUP @ 0 ?DO
        I OVER _NDB@ 1 RSHIFT
        I 1 + 2 PICK _NDB@ 1 AND 31 LSHIFT OR
        I 2 PICK _NDB-LIMB !
    LOOP
    _NDB-TRIM ;

\ Bits in b; 0 for zero.
: _NDB-BITS  ( b -- n )
    DUP @ DUP 0= IF NIP EXIT THEN
    DUP 1 - 32 * -ROT CELLS + @
    BEGIN DUP WHILE 1 RSHIFT SWAP 1 + SWAP REPEAT DROP ;

\ b = b * 10^k.
: _NDB-POW10  ( k b -- )
    SWAP BEGIN DUP 9 >= WHILE 1000000000 0 3 PICK _NDB-MULADD 9 - REPEAT
    1 SWAP 0 ?DO 10 * LOOP 0 ROT _NDB-MULADD ;

\ b = b * 5^k.
: _NDB-POW5  ( k b -- )
    SWAP BEGIN DUP 13 >= WHILE 1220703125 0 3 PICK _NDB-MULADD 13 - REPEAT
    1 SWAP 0 ?DO 5 * LOOP 0 ROT _NDB-MULADD ;

\ =====================================================================
\  Workspace frame
\ =====================================================================

  0 CONSTANT _NDF-FRAC       \ fraction bits: 52 or 23
  8 CONSTANT _NDF-BIAS       \ exponent bias: 1023 or 127
 16 CONSTANT _NDF-EMAX       \ biased exponent of the infinities
 24 CONSTANT _NDF-SIGN       \ the sign bit
 32 CONSTANT _NDF-N          \ digits in the digit buffer
 40 CONSTANT _NDF-X          \ decimal exponent of the first digit
 48 CONSTANT _NDF-OUT        \ output buffer
 56 CONSTANT _NDF-CAP        \ its capacity
 64 CONSTANT _NDF-LEN        \ characters written, or needed
 72 CONSTANT _NDF-EVEN       \ nonzero: the significand is even
 80 CONSTANT _NDF-STICKY     \ parsing: a nonzero digit was dropped
 88 CONSTANT _NDF-E          \ parsing: decimal exponent of the digits
 96 CONSTANT _NDF-DL         \ parsing: significant digits kept
104 CONSTANT _NDF-NEG        \ parsing: nonzero for a minus sign
112 CONSTANT _NDF-INFRAC     \ parsing: nonzero past the decimal point
128 CONSTANT _NDF-DIGITS     \ up to 800 digit characters
928 CONSTANT _NDF-BIGS       \ five big integers

_NDF-BIGS 5 _NDB-BYTES * + CONSTANT NDEC-WS-BYTES

\ Significant digits a parse keeps.  A value's exact expansion has at
\ most 767, so any further digit only breaks a tie.
800 CONSTANT _NDEC-MAX-DIGITS

: _NDF-R   ( frame -- b )  _NDF-BIGS + ;
: _NDF-S   ( frame -- b )  _NDF-BIGS + _NDB-BYTES + ;
: _NDF-MP  ( frame -- b )  _NDF-BIGS + _NDB-BYTES 2 * + ;
: _NDF-MM  ( frame -- b )  _NDF-BIGS + _NDB-BYTES 3 * + ;
: _NDF-T   ( frame -- b )  _NDF-BIGS + _NDB-BYTES 4 * + ;

: _NDF-DIGIT  ( i frame -- addr )  _NDF-DIGITS + + ;

\ Is the format known, and the workspace big enough?
: _NDEC-CHECK  ( fmt ws -- status )
    SWAP NUM-FORMAT? 0= IF DROP NUM-E-FORMAT EXIT THEN
    NWS-BYTES NDEC-WS-BYTES < IF NUM-E-SPACE ELSE NUM-OK THEN ;

\ Set up the frame in ws for format fmt.
: _NDEC-FRAME  ( fmt ws -- frame )
    NWS-ADDR SWAP NUM-FP64 = IF
        52 OVER _NDF-FRAC + !  1023 OVER _NDF-BIAS + !
        2047 OVER _NDF-EMAX + !  0x8000000000000000 OVER _NDF-SIGN + !
    ELSE
        23 OVER _NDF-FRAC + !  127 OVER _NDF-BIAS + !
        255 OVER _NDF-EMAX + !  0x80000000 OVER _NDF-SIGN + !
    THEN ;

: _NDEC-FP64?  ( frame -- flag )  _NDF-FRAC + @ 52 = ;

\ The biased exponent and fraction fields of a value.
: _NDEC-FIELDS  ( bits frame -- be f )
    >R
    DUP R@ _NDF-FRAC + @ RSHIFT R@ _NDF-EMAX + @ AND
    SWAP 1 R@ _NDF-FRAC + @ LSHIFT 1 - AND
    R> DROP ;

\ The significand m and binary exponent e: the value is m * 2^e.
: _NDEC-M-E  ( be f frame -- m e )
    >R
    OVER IF 1 R@ _NDF-FRAC + @ LSHIFT OR SWAP ELSE NIP 1 THEN
    R@ _NDF-BIAS + @ - R> _NDF-FRAC + @ - ;

: _NDEC-BITLEN  ( u -- n )  0 SWAP BEGIN DUP WHILE 1 RSHIFT SWAP 1 + SWAP REPEAT DROP ;

: _NDEC-INF  ( frame -- bits )  DUP _NDF-EMAX + @ SWAP _NDF-FRAC + @ LSHIFT ;

: _NDEC-NAN  ( frame -- bits )
    DUP _NDEC-INF 1 ROT _NDF-FRAC + @ 1 - LSHIFT OR ;

\ =====================================================================
\  Output
\ =====================================================================

: _NDEC-OUTPUT  ( addr cap frame -- )
    TUCK _NDF-CAP + !  TUCK _NDF-OUT + !  0 SWAP _NDF-LEN + ! ;

\ Append character c; past the capacity, only count it.
: _NDEC-EMIT  ( c frame -- )
    DUP _NDF-LEN + @ OVER _NDF-CAP + @ < IF
        DUP _NDF-OUT + @ OVER _NDF-LEN + @ + ROT SWAP C!
    ELSE
        NIP
    THEN
    1 SWAP _NDF-LEN + +! ;

: _NDEC-TYPE  ( addr n frame -- )
    -ROT 0 ?DO DUP I + C@ 2 PICK _NDEC-EMIT LOOP 2DROP ;

\ Append u in decimal.
: _NDEC-EMIT-U  ( u frame -- )
    OVER 10 < IF SWAP [CHAR] 0 + SWAP _NDEC-EMIT EXIT THEN
    OVER 10 / OVER RECURSE
    SWAP 10 MOD [CHAR] 0 + SWAP _NDEC-EMIT ;

\ The length, and NUM-OK or NUM-E-SPACE when the text did not fit.
: _NDEC-DONE  ( frame -- len status )
    DUP _NDF-LEN + @ SWAP _NDF-CAP + @ OVER < IF NUM-E-SPACE ELSE NUM-OK THEN ;

\ Append nan, inf, or -inf for a value whose exponent field is full.
: _NDEC-SPECIAL  ( bits f frame -- )
    SWAP IF NIP S" nan" ROT _NDEC-TYPE EXIT THEN
    SWAP OVER _NDF-SIGN + @ AND IF [CHAR] - OVER _NDEC-EMIT THEN
    S" inf" ROT _NDEC-TYPE ;

\ =====================================================================
\  Digits
\ =====================================================================
\  A decimal is the digit characters at _NDF-DIGITS, _NDF-N of them,
\  with the first digit weighing 10^_NDF-X.

\ Nine digits of r at addr.
: _NDEC-GROUP  ( addr r -- )
    9 0 DO 10 /MOD SWAP [CHAR] 0 + 2 PICK 8 I - + C! LOOP 2DROP ;

\ Drop trailing zero digits.
: _NDEC-TRIM  ( frame -- )
    BEGIN
        DUP _NDF-N + @ DUP IF 1 - OVER _NDF-DIGIT C@ [CHAR] 0 = THEN
    WHILE
        -1 OVER _NDF-N + +!
    REPEAT DROP ;

\ The exact digits of the finite, nonzero value with fields be and f.
: _NDEC-EXACT  ( be f frame -- )
    >R
    R@ _NDEC-M-E SWAP R@ _NDF-R _NDB-SET
    DUP 0< IF
        DUP NEGATE R@ _NDF-R _NDB-POW5
    ELSE
        R@ _NDF-R _NDB-SHL 0
    THEN
    \ nine digits at a time, least significant first, ending at 792
    792 R@ _NDF-DIGIT
    BEGIN R@ _NDF-R @ WHILE
        9 - 1000000000 R@ _NDF-R _NDB-DIVMOD OVER SWAP _NDEC-GROUP
    REPEAT
    BEGIN DUP C@ [CHAR] 0 = WHILE 1 + REPEAT
    792 R@ _NDF-DIGIT OVER -
    ROT OVER + 1 - R@ _NDF-X + !
    DUP R@ _NDF-N + !
    0 R@ _NDF-DIGIT SWAP CMOVE
    R@ _NDEC-TRIM
    R> DROP ;

\ Add one to the last of the first n digits, carrying, and keep those
\ digits; an all-nines run becomes 1 with the exponent one higher.
: _NDEC-BUMP  ( n frame -- )
    >R DUP R@ _NDF-N + !
    BEGIN
        DUP 0= IF
            DROP [CHAR] 1 0 R@ _NDF-DIGIT C!  1 R@ _NDF-N + !
            1 R@ _NDF-X + +!  R> DROP EXIT
        THEN
        1 - DUP R@ _NDF-DIGIT C@ [CHAR] 9 =
    WHILE
        [CHAR] 0 OVER R@ _NDF-DIGIT C!
    REPEAT
    R@ _NDF-DIGIT DUP C@ 1 + SWAP C!
    R@ _NDEC-TRIM
    R> DROP ;

\ Does dropping the digits from index k on round up, ties to even?
: _NDEC-UP?  ( k frame -- flag )
    >R DUP R@ _NDF-DIGIT C@ [CHAR] 5 -
    DUP 0> IF 2DROP R> DROP -1 EXIT THEN
    IF DROP R> DROP 0 EXIT THEN
    \ exactly 5: up if a nonzero digit follows, else to the even digit
    DUP 1 + R@ _NDF-N + @ < IF DROP R> DROP -1 EXIT THEN
    DUP 0= IF DROP R> DROP 0 EXIT THEN
    1 - R@ _NDF-DIGIT C@ 1 AND 0<>
    R> DROP ;

\ Keep the first k digits, rounding ties to the even digit.  For k = 0
\ the result is the unit of the place above the first digit, or nothing.
: _NDEC-ROUND  ( k frame -- )
    >R
    DUP R@ _NDF-N + @ >= IF DROP R> DROP EXIT THEN
    DUP 0< IF DROP 0 R@ _NDF-N + ! R> DROP EXIT THEN
    DUP R@ _NDEC-UP? IF
        DUP 0= IF
            DROP [CHAR] 1 0 R@ _NDF-DIGIT C!  1 R@ _NDF-N + !
            1 R@ _NDF-X + +!  R> DROP EXIT
        THEN
        R@ _NDEC-BUMP
    ELSE
        R@ _NDF-N + !  R@ _NDEC-TRIM
    THEN
    R> DROP ;

\ The digit weighing 10^w, as a character.
: _NDEC-DIGIT@  ( w frame -- c )
    >R R@ _NDF-X + @ SWAP -
    DUP 0< OVER R@ _NDF-N + @ >= OR IF DROP [CHAR] 0 ELSE R@ _NDF-DIGIT C@ THEN
    R> DROP ;

\ Append the digits weighing 10^hi down to 10^lo.
: _NDEC-SPAN  ( hi lo frame -- )
    -ROT OVER SWAP - 1 +
    0 ?DO DUP I - 2 PICK _NDEC-DIGIT@ 2 PICK _NDEC-EMIT LOOP
    2DROP ;

\ Append the digits laid out like Python's repr.
: _NDEC-REPR  ( frame -- )
    >R R@ _NDF-X + @
    DUP -4 < OVER 15 > OR IF
        0 R@ _NDF-DIGIT C@ R@ _NDEC-EMIT
        R@ _NDF-N + @ 1 > IF
            [CHAR] . R@ _NDEC-EMIT
            1 R@ _NDF-DIGIT R@ _NDF-N + @ 1 - R@ _NDEC-TYPE
        THEN
        [CHAR] e R@ _NDEC-EMIT
        DUP 0< IF [CHAR] - ELSE [CHAR] + THEN R@ _NDEC-EMIT
        ABS DUP 10 < IF [CHAR] 0 R@ _NDEC-EMIT THEN R@ _NDEC-EMIT-U
    ELSE
        DUP 0< IF
            [CHAR] 0 R@ _NDEC-EMIT  [CHAR] . R@ _NDEC-EMIT
            R@ _NDF-N + @ - 1 + -1 SWAP R@ _NDEC-SPAN
        ELSE
            DUP 0 R@ _NDEC-SPAN  [CHAR] . R@ _NDEC-EMIT
            R@ _NDF-N + @ - 1 +
            DUP 0< IF -1 SWAP R@ _NDEC-SPAN ELSE DROP [CHAR] 0 R@ _NDEC-EMIT THEN
        THEN
    THEN
    R> DROP ;

\ =====================================================================
\  Shortest digits (Burger and Dybvig)
\ =====================================================================
\  The reals that read back as the value v form an interval from
\  v - MM/S to v + MP/S, where R/S is v scaled into [0.1, 1).  Its ends
\  read back as v when the significand is even, since ties go to even.

\ Set R, S, MP, MM, and EVEN for the finite, nonzero value with fields
\ be and f.  With b = 1 at a binade's first value, whose gap below is
\ half the gap above, and b = 0 elsewhere:
\   R = m 2^(1+b+max(e,0))   S = 2^(1+b+max(-e,0))
\   MP = 2^(b+max(e,0))      MM = 2^max(e,0)
: _NDEC-INTERVAL  ( be f frame -- )
    >R
    2DUP 0= SWAP 1 > AND 1 AND
    -ROT R@ _NDEC-M-E
    OVER 1 AND 0= R@ _NDF-EVEN + !
    SWAP R@ _NDF-R _NDB-SET
    1 R@ _NDF-S _NDB-SET  1 R@ _NDF-MP _NDB-SET  1 R@ _NDF-MM _NDB-SET
    DUP 0 MAX
    DUP R@ _NDF-MM _NDB-SHL
    DUP 3 PICK + R@ _NDF-MP _NDB-SHL
    1 + 2 PICK + R@ _NDF-R _NDB-SHL
    NEGATE 0 MAX 1 + + R@ _NDF-S _NDB-SHL
    R> DROP ;

\ Is R/S at or past the interval's high end?
: _NDEC-HIGH?  ( frame -- flag )
    >R R@ _NDF-R R@ _NDF-T _NDB-COPY  R@ _NDF-T R@ _NDF-MP _NDB-ADD
    R@ _NDF-T R@ _NDF-S _NDB-CMP
    R@ _NDF-EVEN + @ IF 0>= ELSE 0> THEN
    R> DROP ;

\ Is R/S at or below the interval's low end?
: _NDEC-LOW?  ( frame -- flag )
    >R R@ _NDF-R R@ _NDF-MM _NDB-CMP
    R@ _NDF-EVEN + @ IF 0> 0= ELSE 0< THEN
    R> DROP ;

\ Scale by a power of ten so that 10^k is the first power at or above
\ the interval's high end, and return k.  The estimate from the binary
\ exponent is never above k; the loop corrects it.
: _NDEC-SCALE  ( be f frame -- k )
    >R R@ _NDEC-M-E SWAP _NDEC-BITLEN + 1 -
    1292913986 * DUP 0< IF NEGATE 32 RSHIFT NEGATE ELSE 4294967295 + 32 RSHIFT THEN
    1 -
    DUP 0< IF
        DUP NEGATE DUP R@ _NDF-R _NDB-POW10
        DUP R@ _NDF-MP _NDB-POW10 R@ _NDF-MM _NDB-POW10
    ELSE
        DUP R@ _NDF-S _NDB-POW10
    THEN
    BEGIN R@ _NDEC-HIGH? WHILE 10 0 R@ _NDF-S _NDB-MULADD 1 + REPEAT
    R> DROP ;

\ The next digit of R/S; R keeps the remainder.
: _NDEC-NEXT  ( frame -- d )
    >R
    10 0 R@ _NDF-R _NDB-MULADD  10 0 R@ _NDF-MP _NDB-MULADD
    10 0 R@ _NDF-MM _NDB-MULADD
    0 BEGIN R@ _NDF-R R@ _NDF-S _NDB-CMP 0>= WHILE
        R@ _NDF-R R@ _NDF-S _NDB-SUB 1 +
    REPEAT
    R> DROP ;

\ The digit to emit for d, and whether it is the last.  Inside both
\ ends, the nearer of d and d + 1, ties to the even digit.
: _NDEC-FINISH  ( d low high frame -- d' last )
    >R
    2DUP AND IF
        2DROP
        R@ _NDF-R R@ _NDF-T _NDB-COPY  1 R@ _NDF-T _NDB-SHL
        R@ _NDF-T R@ _NDF-S _NDB-CMP
        DUP 0= IF DROP DUP 1 AND ELSE 0> THEN IF 1 + THEN
        -1
    ELSE
        IF DROP 1 + -1 ELSE 0<> THEN
    THEN
    R> DROP ;

\ Append digit d, 0 to 10, carrying a 10 into the digits before it.
: _NDEC-APPEND  ( d frame -- )
    >R
    DUP 9 MIN [CHAR] 0 + R@ _NDF-N + @ R@ _NDF-DIGIT C!
    1 R@ _NDF-N + +!
    9 > IF R@ _NDF-N + @ R@ _NDEC-BUMP THEN
    R> DROP ;

: _NDEC-SHORTEST  ( frame -- )
    >R 0 R@ _NDF-N + !
    BEGIN
        R@ _NDEC-NEXT R@ _NDEC-LOW? R@ _NDEC-HIGH? R@ _NDEC-FINISH
        SWAP R@ _NDEC-APPEND
    UNTIL
    R> DROP ;

\ =====================================================================
\  Public words: output
\ =====================================================================

\ The shortest decimal that reads back as bits, laid out like Python's
\ repr, into the cap characters at addr.  len is the full length even
\ when it did not fit.
: NDEC-FORMAT  ( bits fmt addr cap ws -- len status )
    3 PICK OVER _NDEC-CHECK ?DUP IF >R 2DROP 2DROP DROP 0 R> EXIT THEN
    >R ROT R> _NDEC-FRAME
    DUP >R _NDEC-OUTPUT
    DUP R@ _NDEC-FIELDS
    OVER R@ _NDF-EMAX + @ = IF NIP R@ _NDEC-SPECIAL R> _NDEC-DONE EXIT THEN
    ROT R@ _NDF-SIGN + @ AND IF [CHAR] - R@ _NDEC-EMIT THEN
    2DUP OR 0= IF 2DROP S" 0.0" R@ _NDEC-TYPE R> _NDEC-DONE EXIT THEN
    2DUP R@ _NDEC-INTERVAL
    R@ _NDEC-SCALE 1 - R@ _NDF-X + !
    R@ _NDEC-SHORTEST
    R@ _NDEC-REPR
    R> _NDEC-DONE ;

\ bits rounded to places decimal places, ties to even, laid out like
\ Python's f"{x:.3f}", into the cap characters at addr.
: NDEC-FIXED  ( bits fmt places addr cap ws -- len status )
    4 PICK OVER _NDEC-CHECK ?DUP IF >R 2DROP 2DROP 2DROP 0 R> EXIT THEN
    3 PICK 0< IF 2DROP 2DROP 2DROP 0 NUM-E-RANGE EXIT THEN
    >R ROT >R ROT R> R> ROT SWAP _NDEC-FRAME
    DUP >R SWAP >R _NDEC-OUTPUT R>
    OVER R@ _NDEC-FIELDS
    OVER R@ _NDF-EMAX + @ = IF NIP NIP R@ _NDEC-SPECIAL R> _NDEC-DONE EXIT THEN
    3 PICK R@ _NDF-SIGN + @ AND IF [CHAR] - R@ _NDEC-EMIT THEN
    2DUP OR IF
        R@ _NDEC-EXACT
    ELSE
        2DROP 0 R@ _NDF-N + !  0 R@ _NDF-X + !
    THEN
    NIP
    DUP R@ _NDF-X + @ + 1 + R@ _NDEC-ROUND
    R@ _NDF-X + @ 0 MAX 0 R@ _NDEC-SPAN
    DUP IF [CHAR] . R@ _NDEC-EMIT -1 OVER NEGATE R@ _NDEC-SPAN THEN
    DROP R> _NDEC-DONE ;

\ =====================================================================
\  Parsing
\ =====================================================================

\ The character at p, or 0 at the end.
: _NDEC-PEEK  ( p end -- c )  OVER > IF C@ ELSE DROP 0 THEN ;

\ Does the text from p to end spell the lowercase word s, in any case?
: _NDEC-WORD?  ( p end s n -- flag )
    >R -ROT OVER - R@ <> IF 2DROP R> DROP 0 EXIT THEN
    R> 0 ?DO
        OVER I + C@ OVER I + C@ 32 OR <> IF 2DROP UNLOOP 0 EXIT THEN
    LOOP
    2DROP -1 ;

: _NDEC-SIGNED  ( bits frame -- bits' )
    DUP _NDF-NEG + @ IF _NDF-SIGN + @ OR ELSE DROP THEN ;

\ Take one mantissa digit d.
: _NDEC-TAKE  ( d frame -- )
    >R
    DUP 0= R@ _NDF-DL + @ 0= AND IF
        DROP R@ _NDF-INFRAC + @ IF -1 R@ _NDF-E + +! THEN R> DROP EXIT
    THEN
    R@ _NDF-DL + @ _NDEC-MAX-DIGITS < IF
        10 SWAP R@ _NDF-R _NDB-MULADD
        1 R@ _NDF-DL + +!
        R@ _NDF-INFRAC + @ IF -1 R@ _NDF-E + +! THEN
    ELSE
        IF -1 R@ _NDF-STICKY + ! THEN
        R@ _NDF-INFRAC + @ 0= IF 1 R@ _NDF-E + +! THEN
    THEN
    R> DROP ;

\ Take the mantissa digits at p; count them.
: _NDEC-MANTISSA  ( p end frame -- p' end count )
    >R 0
    BEGIN 2 PICK 2 PICK _NDEC-PEEK DUP [CHAR] 0 - 10 U< WHILE
        [CHAR] 0 - R@ _NDEC-TAKE
        ROT 1 + -ROT 1 +
    REPEAT
    DROP R> DROP ;

\ The exponent digits at p, saturating far past any finite value.
: _NDEC-EXPONENT  ( p end -- p' end n count )
    0 0
    BEGIN 3 PICK 3 PICK _NDEC-PEEK DUP [CHAR] 0 - 10 U< WHILE
        [CHAR] 0 - ROT 10 * + 100000000 MIN SWAP 1 +
        >R >R SWAP 1 + SWAP R> R>
    REPEAT
    DROP ;

\ Past these decimal exponents a value is infinite or zero.
: _NDEC-DMAX  ( frame -- n )  _NDEC-FP64? IF 309 ELSE 39 THEN ;
: _NDEC-DMIN  ( frame -- n )  _NDEC-FP64? IF -324 ELSE -46 THEN ;

\ Largest power of ten, and largest integer, exact in the format.
: _NDEC-P10MAX  ( frame -- n )  _NDEC-FP64? IF 22 ELSE 10 THEN ;

: _NDEC>FLOAT  ( n frame -- r )  _NDEC-FP64? IF S>F64 ELSE S>F32 THEN ;
: _NDEC-MUL  ( a b frame -- r )  _NDEC-FP64? IF F64* ELSE F32* THEN ;
: _NDEC-DIV  ( a b frame -- r )  _NDEC-FP64? IF F64/ ELSE F32/ THEN ;

\ 10^k as a value of the format, exact for k up to _NDEC-P10MAX.
: _NDEC-POW10F  ( k frame -- r )
    DUP _NDEC-FP64? IF 0x3FF0000000000000 ELSE 0x3F800000 THEN
    ROT 0 ?DO
        OVER _NDEC-FP64? IF 0x4024000000000000 ELSE 0x41200000 THEN 2 PICK _NDEC-MUL
    LOOP
    NIP ;

\ Are the digits and the power of ten both exact in the format?
: _NDEC-FAST?  ( frame -- flag )
    >R
    R@ _NDF-STICKY + @ 0=
    R@ _NDF-R @ 3 < AND
    R@ _NDF-E + @ ABS R@ _NDEC-P10MAX <= AND
    DUP IF DROP R@ _NDF-R _NDB-CELL 1 R@ _NDF-FRAC + @ 1 + LSHIFT U< THEN
    R> DROP ;

\ One correctly rounded multiply or divide, to nearest even.
: _NDEC-FAST  ( frame -- bits )
    >R FPCSR@ DUP -8 AND FPCSR!
    R@ _NDF-R _NDB-CELL R@ _NDEC>FLOAT
    R@ _NDF-E + @ DUP ABS R@ _NDEC-POW10F
    SWAP 0< IF R@ _NDEC-DIV ELSE R@ _NDEC-MUL THEN
    SWAP FPCSR@ -8 AND SWAP 7 AND OR FPCSR!
    R> DROP ;

\ q = floor(R/S) and whether a remainder is left, for R/S below
\ 2^(FRAC+2); R keeps the remainder and S is spent.
: _NDEC-DIVIDE  ( frame -- q rest )
    >R R@ _NDF-FRAC + @ 1 + DUP R@ _NDF-S _NDB-SHL
    0 SWAP
    BEGIN DUP 0>= WHILE
        R@ _NDF-R R@ _NDF-S _NDB-CMP 0>= IF
            R@ _NDF-R R@ _NDF-S _NDB-SUB
            SWAP 1 2 PICK LSHIFT OR SWAP
        THEN
        R@ _NDF-S _NDB-HALVE
        1 -
    REPEAT DROP
    R@ _NDF-R @ 0<>
    R> DROP ;

\ The value of the digits in R times 10^E, rounded to nearest even:
\ with x the binary exponent (never below the smallest normal's), q is
\ floor(value * 2^(FRAC+1-x)), whose low bit is the rounding bit.
: _NDEC-SLOW  ( frame -- bits )
    >R
    1 R@ _NDF-S _NDB-SET
    R@ _NDF-E + @ DUP 0< IF NEGATE R@ _NDF-S ELSE R@ _NDF-R THEN _NDB-POW10
    R@ _NDF-R _NDB-BITS R@ _NDF-S _NDB-BITS -
    DUP 0< IF
        R@ _NDF-R R@ _NDF-T _NDB-COPY  DUP NEGATE R@ _NDF-T _NDB-SHL
        R@ _NDF-T R@ _NDF-S _NDB-CMP 0< IF 1 - THEN
    ELSE
        R@ _NDF-S R@ _NDF-T _NDB-COPY  DUP R@ _NDF-T _NDB-SHL
        R@ _NDF-R R@ _NDF-T _NDB-CMP 0< IF 1 - THEN
    THEN
    DUP R@ _NDF-BIAS + @ > IF DROP R@ _NDEC-INF R> DROP EXIT THEN
    1 R@ _NDF-BIAS + @ - MAX
    R@ _NDF-FRAC + @ 1 + OVER -
    DUP 0< IF NEGATE R@ _NDF-S ELSE R@ _NDF-R THEN _NDB-SHL
    R@ _NDEC-DIVIDE R@ _NDF-STICKY + @ OR
    SWAP DUP 1 RSHIFT SWAP 1 AND
    IF SWAP IF 1 + ELSE DUP 1 AND IF 1 + THEN THEN ELSE NIP THEN
    SWAP R@ _NDF-BIAS + @ + 1 - R@ _NDF-FRAC + @ LSHIFT +
    R@ _NDEC-INF MIN
    R> DROP ;

\ The magnitude of the digits in R times 10^E.
: _NDEC-VALUE  ( frame -- bits )
    >R
    R@ _NDF-DL + @ R@ _NDF-E + @ +
    DUP 1 - R@ _NDEC-DMAX >= IF DROP R@ _NDEC-INF R> DROP EXIT THEN
    R@ _NDEC-DMIN <= IF 0 R> DROP EXIT THEN
    R@ _NDEC-FAST? IF R@ _NDEC-FAST ELSE R@ _NDEC-SLOW THEN
    R> DROP ;

\ Read the decimal text at addr, len as the nearest value of format
\ fmt, ties to even.  The text is an optional sign, then digits with an
\ optional decimal point and at least one digit, then an optional
\ exponent: e or E, an optional sign, and digits.  inf, infinity, and
\ nan, in any case, are read too.  Anything else is NUM-E-SYNTAX.
: NDEC-PARSE  ( addr len fmt ws -- bits status )
    2DUP _NDEC-CHECK ?DUP IF >R 2DROP 2DROP 0 R> EXIT THEN
    _NDEC-FRAME >R
    OVER +
    0 R@ _NDF-NEG + !
    2DUP _NDEC-PEEK DUP [CHAR] - = IF
        DROP -1 R@ _NDF-NEG + !  SWAP 1 + SWAP
    ELSE
        [CHAR] + = IF SWAP 1 + SWAP THEN
    THEN
    2DUP S" inf" _NDEC-WORD? >R 2DUP S" infinity" _NDEC-WORD? R> OR IF
        2DROP R@ _NDEC-INF R> _NDEC-SIGNED NUM-OK EXIT
    THEN
    2DUP S" nan" _NDEC-WORD? IF
        2DROP R@ _NDEC-NAN R> _NDEC-SIGNED NUM-OK EXIT
    THEN
    0 R@ _NDF-DL + !  0 R@ _NDF-STICKY + !  0 R@ _NDF-E + !
    0 R@ _NDF-INFRAC + !  0 R@ _NDF-R !
    R@ _NDEC-MANTISSA -ROT
    2DUP _NDEC-PEEK [CHAR] . = IF
        SWAP 1 + SWAP  -1 R@ _NDF-INFRAC + !
        R@ _NDEC-MANTISSA >R ROT R> + -ROT
    THEN
    ROT 0= IF 2DROP R> DROP 0 NUM-E-SYNTAX EXIT THEN
    2DUP _NDEC-PEEK 32 OR [CHAR] e = IF
        SWAP 1 + SWAP
        2DUP _NDEC-PEEK DUP [CHAR] - = IF
            DROP SWAP 1 + SWAP -1
        ELSE
            [CHAR] + = IF SWAP 1 + SWAP THEN 0
        THEN
        >R _NDEC-EXPONENT
        0= IF 2DROP DROP R> DROP R> DROP 0 NUM-E-SYNTAX EXIT THEN
        R> IF NEGATE THEN R@ _NDF-E + +!
    THEN
    - IF R> DROP 0 NUM-E-SYNTAX EXIT THEN
    R@ _NDF-R @ IF R@ _NDEC-VALUE ELSE 0 THEN
    R> _NDEC-SIGNED NUM-OK ;
