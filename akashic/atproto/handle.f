\ =====================================================================
\  handle.f - Strict AT Protocol handle syntax and normalization
\ =====================================================================
\  Handles are ASCII DNS-hostname-shaped identifiers.  Syntax validation
\  accepts all protocol-valid TLDs, including names whose later resolution
\  policy must reject.  It performs no DNS, IDNA, registration, or trust
\  decision.
\
\  This module owns no mutable state.  Normalization validates the complete
\  source before publishing its lowercase ASCII form to caller-owned
\  storage.  Exact in-place normalization and fully disjoint output are
\  supported; every partial overlap is rejected.
\
\  Public API:
\    AT-HANDLE-LENGTH-MIN            ( -- 3 )
\    AT-HANDLE-LENGTH-MAX            ( -- 253 )
\    AT-HANDLE-LABEL-MAX             ( -- 63 )
\    AT-HANDLE-STATUS-VALID?         ( status -- flag )
\    AT-HANDLE-VALIDATE              ( source source-u -- status )
\    AT-HANDLE-VALID?                ( source source-u -- flag )
\    AT-HANDLE-NORMALIZED?           ( source source-u
\                                       -- normalized? status )
\    AT-HANDLE-NORMALIZE             ( source source-u destination capacity
\                                       -- written status )
\ =====================================================================

PROVIDED akashic-atproto-handle

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

\ =====================================================================
\  Public bounds and status vocabulary
\ =====================================================================

3   CONSTANT AT-HANDLE-LENGTH-MIN
253 CONSTANT AT-HANDLE-LENGTH-MAX
63  CONSTANT AT-HANDLE-LABEL-MAX

0 CONSTANT AT-HANDLE-S-OK
1 CONSTANT AT-HANDLE-S-INVALID
2 CONSTANT AT-HANDLE-S-CAPACITY
3 CONSTANT AT-HANDLE-S-SYNTAX
4 CONSTANT AT-HANDLE-S-ALIAS
5 CONSTANT AT-HANDLE-S-RANGE
6 CONSTANT AT-HANDLE-S-PROTECTED
7 CONSTANT AT-HANDLE-S-PLATFORM

: AT-HANDLE-STATUS-VALID?  ( status -- flag )
    DUP AT-HANDLE-S-OK >=
    SWAP AT-HANDLE-S-PLATFORM <= AND ;

\ =====================================================================
\  Caller-span admission
\ =====================================================================

: _ATH-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP AT-HANDLE-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP AT-HANDLE-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-HANDLE-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-HANDLE-S-PLATFORM EXIT
    THEN
    DROP AT-HANDLE-S-PLATFORM ;

: _ATH-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP AT-HANDLE-S-INVALID EXIT THEN
    DUP 0= IF 2DROP AT-HANDLE-S-OK EXIT THEN
    OVER 0= IF 2DROP AT-HANDLE-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATH-CALLER>STATUS ;

: _ATH-/STRING  ( address length prefix-u -- address' length' )
    >R SWAP R@ + SWAP R> - ;

\ =====================================================================
\  Syntax predicates and label scanner
\ =====================================================================

: _ATH-LOWER?  ( byte -- flag )
    [CHAR] a [CHAR] z 1+ WITHIN ;

: _ATH-UPPER?  ( byte -- flag )
    [CHAR] A [CHAR] Z 1+ WITHIN ;

: _ATH-DIGIT?  ( byte -- flag )
    [CHAR] 0 [CHAR] 9 1+ WITHIN ;

: _ATH-ALPHA?  ( byte -- flag )
    DUP _ATH-LOWER? IF DROP -1 EXIT THEN
    _ATH-UPPER? ;

: _ATH-ALNUM?  ( byte -- flag )
    DUP _ATH-ALPHA? IF DROP -1 EXIT THEN
    _ATH-DIGIT? ;

: _ATH-LABEL-CHAR?  ( byte -- flag )
    DUP _ATH-ALNUM? IF DROP -1 EXIT THEN
    [CHAR] - = ;

: _ATH-LOWER  ( byte -- lowercase-byte )
    DUP _ATH-UPPER? IF 32 + THEN ;

: _ATH-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _ATH-RETURN4  ( x1 x2 x3 x4 status -- status )
    >R _ATH-DROP4 R> ;

: _ATH-RETURN4-ZERO  ( x1 x2 x3 x4 status -- 0 status )
    >R _ATH-DROP4 0 R> ;

\ Return the bytes preceding the first period and whether a period exists.
: _ATH-FIND-DOT  ( address length -- label-u more? )
    0 >R
    BEGIN DUP WHILE
        OVER C@ [CHAR] . = IF
            2DROP R> -1 EXIT
        THEN
        1 _ATH-/STRING
        R> 1+ >R
    REPEAT
    2DROP R> 0 ;

: _ATH-LABEL-STATUS  ( address length -- status )
    DUP 0= IF 2DROP AT-HANDLE-S-SYNTAX EXIT THEN
    DUP AT-HANDLE-LABEL-MAX U> IF
        2DROP AT-HANDLE-S-SYNTAX EXIT
    THEN
    OVER C@ _ATH-ALNUM? 0= IF
        2DROP AT-HANDLE-S-SYNTAX EXIT
    THEN
    2DUP + 1- C@ _ATH-ALNUM? 0= IF
        2DROP AT-HANDLE-S-SYNTAX EXIT
    THEN
    0 ?DO
        DUP I + C@ _ATH-LABEL-CHAR? 0= IF
            DROP AT-HANDLE-S-SYNTAX UNLOOP EXIT
        THEN
    LOOP
    DROP AT-HANDLE-S-OK ;

\ The third stack item counts completed non-final labels.
: _ATH-GRAMMAR  ( address length -- status )
    0
    BEGIN
        2 PICK 2 PICK _ATH-FIND-DOT
        IF
            3 PICK OVER _ATH-LABEL-STATUS
            ?DUP IF _ATH-RETURN4 EXIT THEN
            SWAP >R
            1+ _ATH-/STRING
            R> 1+
        ELSE
            3 PICK OVER _ATH-LABEL-STATUS
            ?DUP IF _ATH-RETURN4 EXIT THEN
            OVER 1+ 2 < IF
                _ATH-DROP4 AT-HANDLE-S-SYNTAX EXIT
            THEN
            3 PICK C@ _ATH-ALPHA? 0= IF
                _ATH-DROP4 AT-HANDLE-S-SYNTAX EXIT
            THEN
            _ATH-DROP4 AT-HANDLE-S-OK EXIT
        THEN
    AGAIN ;

\ =====================================================================
\  Public validation and normalization
\ =====================================================================

: AT-HANDLE-VALIDATE  ( source source-u -- status )
    DUP 0< IF
        2DROP AT-HANDLE-S-INVALID EXIT
    THEN
    DUP AT-HANDLE-LENGTH-MAX U> IF
        2DROP AT-HANDLE-S-CAPACITY EXIT
    THEN
    2DUP _ATH-SPAN-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP AT-HANDLE-LENGTH-MIN < IF
        2DROP AT-HANDLE-S-SYNTAX EXIT
    THEN
    _ATH-GRAMMAR ;

: AT-HANDLE-VALID?  ( source source-u -- flag )
    AT-HANDLE-VALIDATE AT-HANDLE-S-OK = ;

: AT-HANDLE-NORMALIZED?  ( source source-u -- normalized? status )
    2DUP AT-HANDLE-VALIDATE ?DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    0 ?DO
        DUP I + C@ _ATH-UPPER? IF
            DROP 0 AT-HANDLE-S-OK UNLOOP EXIT
        THEN
    LOOP
    DROP -1 AT-HANDLE-S-OK ;

: AT-HANDLE-NORMALIZE
  ( source source-u destination capacity -- written status )
    3 PICK 3 PICK AT-HANDLE-VALIDATE ?DUP IF
        >R _ATH-DROP4 0 R> EXIT
    THEN
    2DUP _ATH-SPAN-STATUS ?DUP IF
        >R _ATH-DROP4 0 R> EXIT
    THEN
    2 PICK OVER U> IF
        AT-HANDLE-S-CAPACITY _ATH-RETURN4-ZERO EXIT
    THEN
    3 PICK 2 PICK = 0= IF
        2OVER 2OVER MSPAN-OVERLAP? IF
            AT-HANDLE-S-ALIAS _ATH-RETURN4-ZERO EXIT
        THEN
    THEN
    DROP
    OVER 0 ?DO
        2 PICK I + C@ _ATH-LOWER
        OVER I + C!
    LOOP
    DROP NIP AT-HANDLE-S-OK ;
