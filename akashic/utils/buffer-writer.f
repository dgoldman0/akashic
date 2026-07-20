\ =====================================================================
\  buffer-writer.f - Caller-owned checked bounded output
\ =====================================================================
\  Appends are all-or-nothing.  The first invalid-input or capacity error
\  is sticky; later writes are no-ops until RESET.  Writer state and target
\  storage belong to the caller, so independent writers can be interleaved.
\ =====================================================================

PROVIDED akashic-buffer-writer

REQUIRE memory-span.f

0 CONSTANT CBW-S-OK
1 CONSTANT CBW-S-INVALID
2 CONSTANT CBW-S-CAPACITY

 0 CONSTANT _CBW-BUFFER
 8 CONSTANT _CBW-CAPACITY
16 CONSTANT _CBW-LENGTH
24 CONSTANT _CBW-STATUS
32 CONSTANT CBW-SIZE

: _CBW.BUFFER    ( writer -- a ) _CBW-BUFFER + ;
: _CBW.CAPACITY  ( writer -- a ) _CBW-CAPACITY + ;
: _CBW.LENGTH    ( writer -- a ) _CBW-LENGTH + ;
: _CBW.STATUS    ( writer -- a ) _CBW-STATUS + ;

: CBW-LENGTH@  ( writer -- length ) _CBW.LENGTH @ ;
: CBW-STATUS@  ( writer -- status ) _CBW.STATUS @ ;

: _CBW-STATUS-VALID?  ( status -- flag )
    DUP CBW-S-OK >= SWAP CBW-S-CAPACITY <= AND ;

: CBW-VALID?  ( writer -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CBW-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _CBW.CAPACITY @ 0< IF DROP 0 EXIT THEN
    DUP _CBW.LENGTH @ DUP 0< IF 2DROP 0 EXIT THEN DROP
    DUP _CBW.LENGTH @ OVER _CBW.CAPACITY @ > IF DROP 0 EXIT THEN
    DUP _CBW.STATUS @ _CBW-STATUS-VALID? 0= IF DROP 0 EXIT THEN
    DUP _CBW.CAPACITY @ 0> IF
        DUP _CBW.BUFFER @ 0= IF DROP 0 EXIT THEN
    THEN
    DUP _CBW.BUFFER @ OVER _CBW.CAPACITY @
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _CBW.BUFFER @ OVER _CBW.CAPACITY @
        2 PICK CBW-SIZE MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    DROP -1 ;

: CBW-INIT  ( buffer capacity writer -- status )
    >R
    R@ 0= IF 2DROP R> DROP CBW-S-INVALID EXIT THEN
    R@ CBW-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP R> DROP CBW-S-INVALID EXIT
    THEN
    DUP 0< IF 2DROP R> DROP CBW-S-INVALID EXIT THEN
    DUP 0> 2 PICK 0= AND IF
        2DROP R> DROP CBW-S-INVALID EXIT
    THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP R> DROP CBW-S-INVALID EXIT
    THEN
    2DUP R@ CBW-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP CBW-S-INVALID EXIT
    THEN
    R@ CBW-SIZE 0 FILL
    OVER R@ _CBW.BUFFER !
    DUP R@ _CBW.CAPACITY !
    2DROP R> DROP CBW-S-OK ;

: CBW-RESET  ( writer -- status )
    DUP CBW-VALID? 0= IF DROP CBW-S-INVALID EXIT THEN
    0 OVER _CBW.LENGTH !
    0 SWAP _CBW.STATUS !
    CBW-S-OK ;

: _CBW-READY-STATUS  ( writer -- status )
    DUP CBW-VALID? 0= IF DROP CBW-S-INVALID EXIT THEN
    _CBW.STATUS @ ;

: _CBW-LATCH  ( status writer -- status )
    >R
    R@ _CBW.STATUS @ DUP IF
        NIP
    ELSE
        DROP DUP R@ _CBW.STATUS !
    THEN
    R> DROP ;

: _CBW-RESERVE  ( length writer -- destination status )
    DUP _CBW-READY-STATUS DUP IF
        >R 2DROP 0 R> EXIT
    THEN DROP
    OVER 0< IF
        CBW-S-INVALID OVER _CBW-LATCH >R 2DROP 0 R> EXIT
    THEN
    >R
    R@ _CBW.CAPACITY @ R@ _CBW.LENGTH @ - OVER < IF
        DROP CBW-S-CAPACITY R@ _CBW-LATCH
        R> DROP 0 SWAP EXIT
    THEN
    R@ _CBW.BUFFER @ R@ _CBW.LENGTH @ +
    SWAP R@ _CBW.LENGTH +!
    R> DROP CBW-S-OK ;

: _CBW-SOURCE-VALID?  ( address length -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: CBW-APPEND  ( address length writer -- status )
    DUP _CBW-READY-STATUS DUP IF
        >R DROP 2DROP R> EXIT
    THEN DROP
    2 PICK 2 PICK _CBW-SOURCE-VALID? 0= IF
        CBW-S-INVALID OVER _CBW-LATCH >R DROP 2DROP R> EXIT
    THEN
    2 PICK 2 PICK 2 PICK CBW-SIZE MSPAN-OVERLAP? IF
        CBW-S-INVALID OVER _CBW-LATCH >R DROP 2DROP R> EXIT
    THEN
    >R
    DUP R@ _CBW-RESERVE
    DUP IF
        >R DROP 2DROP R> R> DROP EXIT
    THEN DROP
    SWAP MOVE
    R> DROP CBW-S-OK ;

: CBW-CHAR  ( char writer -- status )
    DUP _CBW-READY-STATUS DUP IF
        >R 2DROP R> EXIT
    THEN DROP
    >R
    1 R@ _CBW-RESERVE
    DUP IF
        >R DROP DROP R> R> DROP EXIT
    THEN DROP C!
    R> DROP CBW-S-OK ;

\ Unsigned division by ten for one 64-bit cell.  The reciprocal formula
\ handles the magnitude of the most-negative signed cell without NEGATE.
: _CBW-U/10  ( u -- quotient remainder )
    DUP >R 0xCCCCCCCCCCCCCCCD UM* NIP 3 RSHIFT
    DUP 10 * R> SWAP - ;

: _CBW-U-DIGITS  ( u -- count )
    1 SWAP
    BEGIN DUP 10 U< 0= WHILE
        _CBW-U/10 DROP SWAP 1+ SWAP
    REPEAT
    DROP ;

: CBW-NUMBER  ( n writer -- status )
    DUP _CBW-READY-STATUS DUP IF
        >R 2DROP R> EXIT
    THEN DROP
    SWAP
    DUP 0< DUP >R IF INVERT 1+ THEN
    DUP _CBW-U-DIGITS R@ IF 1+ THEN
    DUP 3 PICK _CBW-RESERVE
    DUP IF
        >R 2DROP 2DROP R> R> DROP EXIT
    THEN DROP
    R@ IF [CHAR] - OVER C! THEN
    OVER + 1-
    >R SWAP R>
    BEGIN
        OVER _CBW-U/10
        [CHAR] 0 + 2 PICK C!
        SWAP 1- >R SWAP DROP R>
        OVER 0=
    UNTIL
    2DROP 2DROP R> DROP CBW-S-OK ;

: CBW-RESULT  ( writer -- address length status )
    DUP CBW-VALID? 0= IF DROP 0 0 CBW-S-INVALID EXIT THEN
    DUP _CBW.BUFFER @ OVER _CBW.LENGTH @ ROT _CBW.STATUS @ ;
