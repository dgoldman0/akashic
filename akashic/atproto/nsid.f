\ =====================================================================
\  nsid.f - Stateless AT Protocol namespaced-identifier syntax
\ =====================================================================
\  Exact NSIDs contain a reversed DNS authority followed by one
\  case-sensitive name segment.  This module validates exact identifiers;
\  the separate trailing ".*" namespace-glob variation is deliberately not
\  admitted for XRPC method or Lexicon record identifiers.
\
\  The implementation owns no mutable state.  Split views borrow the
\  caller's admitted source synchronously.  Canonicalization lowercases only
\  the authority, preserves the name exactly, validates before publishing,
\  supports exact in-place output, and rejects every partial overlap.
\
\  Public API:
\    NSID-LENGTH-MIN                 ( -- 5 )
\    NSID-LENGTH-MAX                 ( -- 317 )
\    NSID-AUTHORITY-LENGTH-MAX       ( -- 253 )
\    NSID-LABEL-LENGTH-MAX           ( -- 63 )
\    NSID-NAME-LENGTH-MAX            ( -- 63 )
\    NSID-STATUS-VALID?              ( status -- flag )
\    NSID-CHECK                      ( source source-u -- status )
\    NSID-VALID?                     ( source source-u -- flag )
\    NSID-SPLIT                      ( source source-u
\                                      -- authority-a authority-u
\                                         name-a name-u status )
\    NSID-CANONICALIZE               ( source source-u destination capacity
\                                      -- written status )
\ =====================================================================

PROVIDED akashic-atproto-nsid

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

5   CONSTANT NSID-LENGTH-MIN
317 CONSTANT NSID-LENGTH-MAX
253 CONSTANT NSID-AUTHORITY-LENGTH-MAX
63  CONSTANT NSID-LABEL-LENGTH-MAX
63  CONSTANT NSID-NAME-LENGTH-MAX

0 CONSTANT NSID-S-OK
1 CONSTANT NSID-S-INVALID
2 CONSTANT NSID-S-CAPACITY
3 CONSTANT NSID-S-SYNTAX
4 CONSTANT NSID-S-AUTHORITY
5 CONSTANT NSID-S-NAME
6 CONSTANT NSID-S-ALIAS
7 CONSTANT NSID-S-RANGE
8 CONSTANT NSID-S-PROTECTED
9 CONSTANT NSID-S-PLATFORM

\ Return true for every status value published by this module, not merely
\ for successful validation.
: NSID-STATUS-VALID?  ( status -- flag )
    DUP NSID-S-OK >= SWAP NSID-S-PLATFORM <= AND ;

: _NSID-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP NSID-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP NSID-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF DROP NSID-S-PROTECTED EXIT THEN
    DUP CALLER-SPAN-S-PLATFORM = IF DROP NSID-S-PLATFORM EXIT THEN
    DROP NSID-S-PLATFORM ;

: _NSID-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP NSID-S-INVALID EXIT THEN
    DUP 0= IF 2DROP NSID-S-OK EXIT THEN
    OVER 0= IF 2DROP NSID-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _NSID-CALLER>STATUS ;

: _NSID-/STRING  ( address length prefix-u -- address' length' )
    >R SWAP R@ + SWAP R> - ;

: _NSID-LOWER?  ( byte -- flag )
    [CHAR] a [CHAR] z 1+ WITHIN ;

: _NSID-UPPER?  ( byte -- flag )
    [CHAR] A [CHAR] Z 1+ WITHIN ;

: _NSID-DIGIT?  ( byte -- flag )
    [CHAR] 0 [CHAR] 9 1+ WITHIN ;

: _NSID-ALPHA?  ( byte -- flag )
    DUP _NSID-LOWER? IF DROP -1 EXIT THEN
    _NSID-UPPER? ;

: _NSID-ALNUM?  ( byte -- flag )
    DUP _NSID-ALPHA? IF DROP -1 EXIT THEN
    _NSID-DIGIT? ;

: _NSID-AUTH-CHAR?  ( byte -- flag )
    DUP _NSID-ALNUM? IF DROP -1 EXIT THEN
    [CHAR] - = ;

: _NSID-LOWER  ( byte -- lowercase-byte )
    DUP _NSID-UPPER? IF 32 + THEN ;

: _NSID-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _NSID-RETURN4  ( x1 x2 x3 x4 status -- status )
    >R _NSID-DROP4 R> ;

: _NSID-RETURN4-ZERO  ( x1 x2 x3 x4 status -- 0 status )
    >R _NSID-DROP4 0 R> ;

: _NSID-FIND-DOT  ( address length -- label-u more? )
    0 >R
    BEGIN DUP WHILE
        OVER C@ [CHAR] . = IF
            2DROP R> -1 EXIT
        THEN
        1 _NSID-/STRING
        R> 1+ >R
    REPEAT
    2DROP R> 0 ;

\ Keep the candidate index on the data stack: inside a DO loop the return
\ stack belongs to the loop machinery.
: _NSID-LAST-DOT  ( address length -- index found? )
    -1 -ROT
    0 ?DO
        DUP I + C@ [CHAR] . = IF
            SWAP DROP I SWAP
        THEN
    LOOP
    DROP DUP 0>= ;

: _NSID-AUTH-LABEL-STATUS  ( address length -- status )
    DUP 0= IF 2DROP NSID-S-AUTHORITY EXIT THEN
    DUP NSID-LABEL-LENGTH-MAX U> IF
        2DROP NSID-S-AUTHORITY EXIT
    THEN
    OVER C@ _NSID-ALNUM? 0= IF
        2DROP NSID-S-AUTHORITY EXIT
    THEN
    2DUP + 1- C@ _NSID-ALNUM? 0= IF
        2DROP NSID-S-AUTHORITY EXIT
    THEN
    0 ?DO
        DUP I + C@ _NSID-AUTH-CHAR? 0= IF
            DROP NSID-S-AUTHORITY UNLOOP EXIT
        THEN
    LOOP
    DROP NSID-S-OK ;

\ The third item counts completed authority labels.  The first authority
\ label is the reversed top-level domain and must begin with a letter.
: _NSID-AUTHORITY-STATUS  ( address length -- status )
    DUP NSID-AUTHORITY-LENGTH-MAX U> IF
        2DROP NSID-S-AUTHORITY EXIT
    THEN
    0
    BEGIN
        2 PICK 2 PICK _NSID-FIND-DOT
        IF
            3 PICK OVER _NSID-AUTH-LABEL-STATUS
            ?DUP IF _NSID-RETURN4 EXIT THEN
            OVER 0= IF
                3 PICK C@ _NSID-ALPHA? 0= IF
                    _NSID-DROP4 NSID-S-AUTHORITY EXIT
                THEN
            THEN
            SWAP >R
            1+ _NSID-/STRING
            R> 1+
        ELSE
            3 PICK OVER _NSID-AUTH-LABEL-STATUS
            ?DUP IF _NSID-RETURN4 EXIT THEN
            OVER 1+ 2 < IF
                _NSID-DROP4 NSID-S-AUTHORITY EXIT
            THEN
            _NSID-DROP4 NSID-S-OK EXIT
        THEN
    AGAIN ;

: _NSID-NAME-STATUS  ( address length -- status )
    DUP 0= IF 2DROP NSID-S-NAME EXIT THEN
    DUP NSID-NAME-LENGTH-MAX U> IF 2DROP NSID-S-NAME EXIT THEN
    OVER C@ _NSID-ALPHA? 0= IF 2DROP NSID-S-NAME EXIT THEN
    0 ?DO
        DUP I + C@ _NSID-ALNUM? 0= IF
            DROP NSID-S-NAME UNLOOP EXIT
        THEN
    LOOP
    DROP NSID-S-OK ;

: _NSID-CHECK-PARTS  ( source source-u last-dot -- status )
    >R
    OVER R@ _NSID-AUTHORITY-STATUS ?DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    OVER R@ 1+ +
    SWAP R@ - 1-
    ROT DROP
    _NSID-NAME-STATUS
    R> DROP ;

: NSID-CHECK  ( source source-u -- status )
    DUP 0< IF 2DROP NSID-S-INVALID EXIT THEN
    DUP NSID-LENGTH-MAX U> IF 2DROP NSID-S-CAPACITY EXIT THEN
    2DUP _NSID-SPAN-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP NSID-LENGTH-MIN < IF 2DROP NSID-S-SYNTAX EXIT THEN
    2DUP _NSID-LAST-DOT 0= IF
        DROP 2DROP NSID-S-SYNTAX EXIT
    THEN
    _NSID-CHECK-PARTS ;

: NSID-VALID?  ( source source-u -- flag )
    NSID-CHECK NSID-S-OK = ;

: NSID-SPLIT
  ( source source-u -- authority-a authority-u name-a name-u status )
    2DUP NSID-CHECK ?DUP IF
        >R 2DROP 0 0 0 0 R> EXIT
    THEN
    2DUP _NSID-LAST-DOT DROP >R
    OVER R@
    3 PICK R@ 1+ +
    3 PICK R@ - 1-
    >R >R >R >R 2DROP
    R> R> R> R>
    R> DROP
    NSID-S-OK ;

: NSID-CANONICALIZE
  ( source source-u destination capacity -- written status )
    3 PICK 3 PICK NSID-CHECK ?DUP IF
        >R _NSID-DROP4 0 R> EXIT
    THEN
    2DUP _NSID-SPAN-STATUS ?DUP IF
        >R _NSID-DROP4 0 R> EXIT
    THEN
    2 PICK OVER U> IF
        NSID-S-CAPACITY _NSID-RETURN4-ZERO EXIT
    THEN
    3 PICK 2 PICK = 0= IF
        2OVER 2OVER MSPAN-OVERLAP? IF
            NSID-S-ALIAS _NSID-RETURN4-ZERO EXIT
        THEN
    THEN
    \ Equal base addresses are exact in-place publication.  Capacity may be
    \ larger than source-u, but the loop writes exactly source-u bytes.
    DROP
    2 PICK 2 PICK _NSID-LAST-DOT DROP
    2 PICK 0 ?DO
        3 PICK I + C@
        OVER I > IF _NSID-LOWER THEN
        2 PICK I + C!
    LOOP
    DROP DROP NIP
    NSID-S-OK ;
