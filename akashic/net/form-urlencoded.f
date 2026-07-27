\ =====================================================================
\  form-urlencoded.f - Stateless application/x-www-form-urlencoded
\ =====================================================================
\  This byte-oriented utility measures and encodes one form component.
\  It owns no storage or mutable operation state.  Callers compose complete
\  bodies by writing separators and encoded names/values into their own
\  transaction buffer.
\
\  Encoding follows the HTML form rules used by OAuth:
\    ALPHA / DIGIT / "*" / "-" / "." / "_" remain literal,
\    SP becomes "+", and every other byte becomes uppercase "%HH".
\
\  Public API:
\    FORM-URLENCODED-MEASURE
\      ( source source-u -- encoded-u status )
\    FORM-URLENCODED-ENCODE
\      ( source source-u destination destination-capacity
\        -- written status )
\ =====================================================================

PROVIDED akashic-form-urlencoded

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

0 CONSTANT FORM-URLENCODED-S-OK
1 CONSTANT FORM-URLENCODED-S-INVALID
2 CONSTANT FORM-URLENCODED-S-CAPACITY
3 CONSTANT FORM-URLENCODED-S-ALIAS
4 CONSTANT FORM-URLENCODED-S-RANGE
5 CONSTANT FORM-URLENCODED-S-PROTECTED
6 CONSTANT FORM-URLENCODED-S-PLATFORM

-1 1 RSHIFT CONSTANT _FUE-LENGTH-MAX

: FORM-URLENCODED-STATUS-VALID?  ( status -- flag )
    DUP FORM-URLENCODED-S-OK >=
    SWAP FORM-URLENCODED-S-PLATFORM <= AND ;

: _FUE-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP FORM-URLENCODED-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP FORM-URLENCODED-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP FORM-URLENCODED-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP FORM-URLENCODED-S-PLATFORM EXIT
    THEN
    DROP FORM-URLENCODED-S-PLATFORM ;

: _FUE-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP FORM-URLENCODED-S-INVALID EXIT THEN
    DUP 0= IF 2DROP FORM-URLENCODED-S-OK EXIT THEN
    OVER 0= IF 2DROP FORM-URLENCODED-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _FUE-CALLER>STATUS ;

: _FUE-LITERAL?  ( byte -- flag )
    DUP 48 58 WITHIN IF DROP -1 EXIT THEN
    DUP 65 91 WITHIN IF DROP -1 EXIT THEN
    DUP 97 123 WITHIN IF DROP -1 EXIT THEN
    DUP 42 = IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    95 = ;

: _FUE-BYTE-SIZE  ( byte -- encoded-u )
    DUP _FUE-LITERAL? IF DROP 1 EXIT THEN
    32 = IF 1 ELSE 3 THEN ;

: FORM-URLENCODED-MEASURE  ( source source-u -- encoded-u status )
    2DUP _FUE-SPAN-STATUS ?DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    0 SWAP 0 ?DO                         ( source encoded-u )
        OVER I + C@ _FUE-BYTE-SIZE       ( source encoded-u add-u )
        DUP _FUE-LENGTH-MAX SWAP -       ( source encoded-u add-u room )
        2 PICK U> IF
            2DROP DROP 0 FORM-URLENCODED-S-CAPACITY
            UNLOOP EXIT
        THEN
        +                                ( source encoded-u' )
    LOOP
    NIP FORM-URLENCODED-S-OK ;

: _FUE-GEOMETRY
  ( source source-u destination destination-capacity -- encoded-u status )
    2>R
    2DUP _FUE-SPAN-STATUS ?DUP IF
        -ROT 2DROP
        2R> 2DROP 0 SWAP EXIT
    THEN
    2R@ _FUE-SPAN-STATUS ?DUP IF
        -ROT 2DROP
        2R> 2DROP 0 SWAP EXIT
    THEN
    2DUP 2R@ MSPAN-OVERLAP? IF
        2DROP 2R> 2DROP
        0 FORM-URLENCODED-S-ALIAS EXIT
    THEN
    FORM-URLENCODED-MEASURE              ( encoded-u measure-status )
    ?DUP IF
        NIP 2R> 2DROP 0 SWAP EXIT
    THEN
    2R@ NIP OVER < IF
        DROP 2R> 2DROP
        0 FORM-URLENCODED-S-CAPACITY EXIT
    THEN
    2R> 2DROP FORM-URLENCODED-S-OK ;

: _FUE-HEX  ( nibble -- byte )
    DUP 10 < IF 48 + ELSE 10 - 65 + THEN ;

: _FUE-ESCAPE  ( byte destination -- destination' )
    DUP 37 SWAP C!
    OVER 4 RSHIFT _FUE-HEX OVER 1+ C!
    OVER 15 AND _FUE-HEX OVER 2 + C!
    NIP 3 + ;

: FORM-URLENCODED-ENCODE
  ( source source-u destination destination-capacity -- written status )
    2OVER 2OVER _FUE-GEOMETRY            ( source source-u dest cap n s )
    ?DUP IF
        >R DROP 2DROP 2DROP 0 R> EXIT
    THEN
    >R DROP                              ( source source-u dest ) ( R: n )
    SWAP 0 ?DO                           ( source destination )
        OVER I + C@                      ( source destination byte )
        DUP _FUE-LITERAL? IF
            OVER C! 1+
        ELSE
            DUP 32 = IF
                DROP 43 OVER C! 1+
            ELSE
                SWAP _FUE-ESCAPE
            THEN
        THEN
    LOOP
    2DROP R> FORM-URLENCODED-S-OK ;
