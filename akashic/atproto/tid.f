\ =====================================================================
\  tid.f - Caller-owned AT Protocol Timestamp Identifiers
\ =====================================================================
\  A clock is a caller-owned 24-byte object containing a fixed 10-bit ID
\  and the last committed logical microsecond.  Generation accepts trusted
\  Unix epoch milliseconds, remains monotonic across equal/backward input,
\  and changes neither output nor clock on any rejected operation.
\ =====================================================================

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

PROVIDED akashic-tid

0 CONSTANT TID-S-OK
1 CONSTANT TID-S-INVALID
2 CONSTANT TID-S-CAPACITY
3 CONSTANT TID-S-ALIAS
4 CONSTANT TID-S-SYNTAX
5 CONSTANT TID-S-RANGE
6 CONSTANT TID-S-PROTECTED
7 CONSTANT TID-S-PLATFORM
8 CONSTANT TID-S-EXHAUSTED

13 CONSTANT TID-LENGTH
24 CONSTANT TID-CLOCK-SIZE

0 CONSTANT _TID-CLOCK-MAGIC-OFF
8 CONSTANT _TID-CLOCK-ID-OFF
16 CONSTANT _TID-CLOCK-LAST-OFF

0x544944434C4F434B CONSTANT _TID-CLOCK-MAGIC
1023 CONSTANT _TID-CLOCK-ID-MAX
9007199254740991 CONSTANT _TID-MICROSECOND-MAX
9007199254740 CONSTANT _TID-EPOCH-MS-MAX

: TID-STATUS-VALID?  ( status -- flag )
    DUP TID-S-OK >= SWAP TID-S-EXHAUSTED <= AND ;

: _TID-3DROP  ( x1 x2 x3 -- )
    DROP 2DROP ;

: _TID-4DUP  ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 x3 x4 )
    3 PICK 3 PICK 3 PICK 3 PICK ;

: _TID-4DROP  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _TID-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP TID-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP TID-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF DROP TID-S-PROTECTED EXIT THEN
    DROP TID-S-PLATFORM ;

: _TID-ID-VALID?  ( clock-id -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    _TID-CLOCK-ID-MAX <= ;

: _TID-EPOCH-MS-VALID?  ( epoch-ms -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    _TID-EPOCH-MS-MAX <= ;

: _TID-LAST-VALID?  ( last-us -- flag )
    DUP -1 = IF DROP -1 EXIT THEN
    DUP 0< IF DROP 0 EXIT THEN
    _TID-MICROSECOND-MAX <= ;

: _TID-ALPHA@  ( value -- character )
    DUP 6 < IF [CHAR] 2 + ELSE 91 + THEN ;

: _TID-CHAR?  ( character -- flag )
    DUP [CHAR] 2 >= OVER [CHAR] 7 <= AND >R
    DUP [CHAR] a >= SWAP [CHAR] z <= AND R> OR ;

: _TID-FIRST-CHAR?  ( character -- flag )
    DUP [CHAR] 2 >= OVER [CHAR] 7 <= AND >R
    DUP [CHAR] a >= SWAP [CHAR] j <= AND R> OR ;

: _TID-SYNTAX?  ( address -- flag )
    DUP C@ _TID-FIRST-CHAR? 0= IF DROP 0 EXIT THEN
    TID-LENGTH 1 ?DO
        DUP I + C@ _TID-CHAR? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: TID-VALIDATE  ( address length -- status )
    DUP 0< IF 2DROP TID-S-INVALID EXIT THEN
    DUP TID-LENGTH > IF 2DROP TID-S-CAPACITY EXIT THEN
    DUP TID-LENGTH < IF 2DROP TID-S-SYNTAX EXIT THEN
    OVER 0= IF 2DROP TID-S-INVALID EXIT THEN
    2DUP CALLER-SPAN-STATUS _TID-CALLER>STATUS
    DUP IF >R 2DROP R> EXIT THEN DROP
    DROP _TID-SYNTAX? IF TID-S-OK ELSE TID-S-SYNTAX THEN ;

: TID-VALID?  ( address length -- flag )
    TID-VALIDATE TID-S-OK = ;

: TID-COMPARE  ( tid-a tid-b -- order )
    TID-LENGTH 0 ?DO
        OVER I + C@
        OVER I + C@
        2DUP < IF 2DROP 2DROP -1 UNLOOP EXIT THEN
        > IF 2DROP 1 UNLOOP EXIT THEN
    LOOP
    2DROP 0 ;

: _TID-CLOCK-STATUS  ( clock -- status )
    DUP 0= IF DROP TID-S-INVALID EXIT THEN
    DUP 7 AND IF DROP TID-S-INVALID EXIT THEN
    DUP TID-CLOCK-SIZE CALLER-SPAN-STATUS _TID-CALLER>STATUS
    DUP IF NIP EXIT THEN DROP
    DUP _TID-CLOCK-MAGIC-OFF + @ _TID-CLOCK-MAGIC <> IF
        DROP TID-S-INVALID EXIT
    THEN
    DUP _TID-CLOCK-ID-OFF + @ _TID-ID-VALID? 0= IF
        DROP TID-S-INVALID EXIT
    THEN
    _TID-CLOCK-LAST-OFF + @ _TID-LAST-VALID? 0= IF
        TID-S-INVALID EXIT
    THEN
    TID-S-OK ;

: TID-CLOCK-VALID?  ( clock -- flag )
    _TID-CLOCK-STATUS TID-S-OK = ;

: TID-CLOCK-INIT  ( clock-id clock -- status )
    OVER _TID-ID-VALID? 0= IF 2DROP TID-S-RANGE EXIT THEN
    DUP 0= IF 2DROP TID-S-INVALID EXIT THEN
    DUP 7 AND IF 2DROP TID-S-INVALID EXIT THEN
    DUP TID-CLOCK-SIZE CALLER-SPAN-STATUS _TID-CALLER>STATUS
    DUP IF >R 2DROP R> EXIT THEN DROP
    _TID-CLOCK-MAGIC OVER _TID-CLOCK-MAGIC-OFF + !
    OVER OVER _TID-CLOCK-ID-OFF + !
    -1 OVER _TID-CLOCK-LAST-OFF + !
    2DROP TID-S-OK ;

: _TID-NEXT-STATUS  ( epoch-ms destination capacity clock -- status )
    DUP _TID-CLOCK-STATUS
    DUP IF >R _TID-4DROP R> EXIT THEN DROP
    DUP _TID-CLOCK-LAST-OFF + @ _TID-MICROSECOND-MAX = IF
        _TID-4DROP TID-S-EXHAUSTED EXIT
    THEN
    3 PICK _TID-EPOCH-MS-VALID? 0= IF
        _TID-4DROP TID-S-RANGE EXIT
    THEN
    OVER 0< IF _TID-4DROP TID-S-INVALID EXIT THEN
    OVER TID-LENGTH < IF _TID-4DROP TID-S-CAPACITY EXIT THEN
    2 PICK 0= IF _TID-4DROP TID-S-INVALID EXIT THEN
    2 PICK 2 PICK CALLER-SPAN-STATUS _TID-CALLER>STATUS
    DUP IF >R _TID-4DROP R> EXIT THEN DROP
    2 PICK 2 PICK 2 PICK TID-CLOCK-SIZE MSPAN-OVERLAP? IF
        _TID-4DROP TID-S-ALIAS EXIT
    THEN
    _TID-4DROP TID-S-OK ;

: _TID-LOGICAL-US  ( epoch-ms clock -- logical-us )
    SWAP 1000 *
    OVER _TID-CLOCK-LAST-OFF + @ 1+
    MAX NIP ;

: _TID-ENCODE  ( value destination -- )
    TID-LENGTH 0 ?DO
        OVER 12 I - 5 * RSHIFT 31 AND _TID-ALPHA@
        OVER I + C!
    LOOP
    2DROP ;

: TID-CLOCK-NEXT-MS  ( epoch-ms destination capacity clock -- status )
    _TID-4DUP _TID-NEXT-STATUS
    DUP IF >R _TID-4DROP R> EXIT THEN DROP
    3 PICK OVER _TID-LOGICAL-US
    DUP 10 LSHIFT 2 PICK _TID-CLOCK-ID-OFF + @ OR
    4 PICK _TID-ENCODE
    OVER _TID-CLOCK-LAST-OFF + !
    _TID-4DROP TID-S-OK ;
