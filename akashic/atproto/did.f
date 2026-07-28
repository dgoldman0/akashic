\ =====================================================================
\  did.f - Strict generic DID identifier syntax for AT Protocol
\ =====================================================================
\  This module validates the method-independent DID identifier syntax used
\  by AT Protocol Lexicon strings.  It deliberately accepts syntactically
\  valid unsupported methods; method support and resolution are separate
\  policy.  DID identifiers are case-sensitive and are never normalized.
\
\  The implementation owns no mutable state.  Returned method and
\  method-specific-ID spans are synchronous read-only borrows into the
\  caller's admitted source.
\
\  Public API:
\    DID-LENGTH-MIN                 ( -- 7 )
\    DID-LENGTH-MAX                 ( -- 2048 )
\    DID-STATUS-VALID?              ( status -- flag )
\    DID-VALIDATE                   ( did-a did-u -- status )
\    DID-VALID?                     ( did-a did-u -- flag )
\    DID-METHOD@                    ( did-a did-u
\                                      -- method-a method-u status )
\    DID-SPECIFIC-ID@               ( did-a did-u
\                                      -- id-a id-u status )
\ =====================================================================

PROVIDED akashic-did

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

\ =====================================================================
\  Public bounds and status vocabulary
\ =====================================================================

7    CONSTANT DID-LENGTH-MIN
2048 CONSTANT DID-LENGTH-MAX

0 CONSTANT DID-S-OK
1 CONSTANT DID-S-INVALID
2 CONSTANT DID-S-CAPACITY
3 CONSTANT DID-S-SYNTAX
4 CONSTANT DID-S-ENCODING
5 CONSTANT DID-S-RANGE
6 CONSTANT DID-S-PROTECTED
7 CONSTANT DID-S-PLATFORM

: DID-STATUS-VALID?  ( status -- flag )
    DUP DID-S-OK >= SWAP DID-S-PLATFORM <= AND ;

\ =====================================================================
\  Caller-span admission
\ =====================================================================

: _DID-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP DID-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP DID-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF DROP DID-S-PROTECTED EXIT THEN
    DUP CALLER-SPAN-S-PLATFORM = IF DROP DID-S-PLATFORM EXIT THEN
    DROP DID-S-PLATFORM ;

: _DID-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP DID-S-INVALID EXIT THEN
    DUP DID-LENGTH-MAX U> IF 2DROP DID-S-CAPACITY EXIT THEN
    DUP 0= IF 2DROP DID-S-OK EXIT THEN
    OVER 0= IF 2DROP DID-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _DID-CALLER>STATUS ;

: _DID-/STRING  ( address length prefix-u -- address' length' )
    >R SWAP R@ + SWAP R> - ;

\ =====================================================================
\  Syntax predicates
\ =====================================================================

: _DID-LOWER?  ( byte -- flag )
    [CHAR] a [CHAR] z 1+ WITHIN ;

: _DID-UPPER?  ( byte -- flag )
    [CHAR] A [CHAR] Z 1+ WITHIN ;

: _DID-DIGIT?  ( byte -- flag )
    [CHAR] 0 [CHAR] 9 1+ WITHIN ;

: _DID-ALPHA?  ( byte -- flag )
    DUP _DID-LOWER? IF DROP -1 EXIT THEN
    _DID-UPPER? ;

: _DID-HEX?  ( byte -- flag )
    DUP _DID-DIGIT? IF DROP -1 EXIT THEN
    DUP [CHAR] A [CHAR] F 1+ WITHIN IF DROP -1 EXIT THEN
    [CHAR] a [CHAR] f 1+ WITHIN ;

: _DID-ID-PLAIN?  ( byte -- flag )
    DUP _DID-ALPHA? IF DROP -1 EXIT THEN
    DUP _DID-DIGIT? IF DROP -1 EXIT THEN
    DUP [CHAR] . = IF DROP -1 EXIT THEN
    DUP [CHAR] _ = IF DROP -1 EXIT THEN
    DUP [CHAR] : = IF DROP -1 EXIT THEN
    [CHAR] - = ;

: _DID-PREFIX?  ( address length -- flag )
    OVER C@ [CHAR] d =
    2 PICK 1+ C@ [CHAR] i = AND
    2 PICK 2 + C@ [CHAR] d = AND
    2 PICK 3 + C@ [CHAR] : = AND
    >R 2DROP R> ;

\ Return the method length and true only when a nonempty lowercase method
\ is followed by a colon.  The input begins immediately after "did:".
: _DID-METHOD-LENGTH  ( address length -- method-u found? )
    0 >R
    BEGIN DUP WHILE
        OVER C@ DUP [CHAR] : = IF
            DROP 2DROP R> DUP 0<> EXIT
        THEN
        _DID-LOWER? 0= IF
            2DROP R> DROP 0 0 EXIT
        THEN
        1 _DID-/STRING
        R> 1+ >R
    REPEAT
    2DROP R> DROP 0 0 ;

: _DID-ID-STATUS  ( address length -- status )
    DUP 0= IF 2DROP DID-S-SYNTAX EXIT THEN
    BEGIN DUP WHILE
        OVER C@ DUP [CHAR] % = IF
            DROP
            DUP 3 < IF 2DROP DID-S-ENCODING EXIT THEN
            OVER 1+ C@ _DID-HEX? 0= IF
                2DROP DID-S-ENCODING EXIT
            THEN
            OVER 2 + C@ _DID-HEX? 0= IF
                2DROP DID-S-ENCODING EXIT
            THEN
            3 _DID-/STRING
        ELSE
            DUP _DID-ID-PLAIN? 0= IF
                DROP 2DROP DID-S-SYNTAX EXIT
            THEN
            [CHAR] : = OVER 1 = AND IF
                2DROP DID-S-SYNTAX EXIT
            THEN
            1 _DID-/STRING
        THEN
    REPEAT
    2DROP DID-S-OK ;

\ =====================================================================
\  Public validation and borrowed views
\ =====================================================================

: DID-VALIDATE  ( did-a did-u -- status )
    2DUP _DID-SPAN-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP DID-LENGTH-MIN < IF
        2DROP DID-S-SYNTAX EXIT
    THEN
    2DUP _DID-PREFIX? 0= IF
        2DROP DID-S-SYNTAX EXIT
    THEN
    2DUP 4 _DID-/STRING _DID-METHOD-LENGTH 0= IF
        DROP 2DROP DID-S-SYNTAX EXIT
    THEN
    5 + _DID-/STRING
    _DID-ID-STATUS ;

: DID-VALID?  ( did-a did-u -- flag )
    DID-VALIDATE DID-S-OK = ;

: DID-METHOD@  ( did-a did-u -- method-a method-u status )
    2DUP DID-VALIDATE ?DUP IF
        >R 2DROP 0 0 R> EXIT
    THEN
    2DUP 4 _DID-/STRING _DID-METHOD-LENGTH
    DROP >R
    DROP 4 +
    R> DID-S-OK ;

: DID-SPECIFIC-ID@  ( did-a did-u -- id-a id-u status )
    2DUP DID-VALIDATE ?DUP IF
        >R 2DROP 0 0 R> EXIT
    THEN
    2DUP 4 _DID-/STRING _DID-METHOD-LENGTH
    DROP 5 + _DID-/STRING
    DID-S-OK ;
