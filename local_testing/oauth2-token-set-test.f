\ oauth2-token-set-test.f - Focused opaque token ownership contracts

PROVIDED akashic-o2tok-contracts

VARIABLE _otst-fails
VARIABLE _otst-checks
VARIABLE _otst-depth
VARIABLE _otst-generation
VARIABLE _otst-observed-u

: _otst-assert  ( flag -- )
    1 _otst-checks +!
    0= IF
        1 _otst-fails +!
        ." OAUTH2 TOKEN SET ASSERT " _otst-checks @ . CR
    THEN ;

: _otst-stack  ( -- )
    DEPTH DUP _otst-depth @ <> IF
        ." OAUTH2 TOKEN SET STACK "
        _otst-depth @ . ." -> " DUP . CR .S CR
    THEN
    _otst-depth @ = _otst-assert ;

: _otst-zero?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _otst-filled?  ( address length byte -- flag )
    BEGIN OVER WHILE
        2 PICK C@ OVER <> IF
            2DROP DROP 0 EXIT
        THEN
        >R 1- SWAP 1+ SWAP R>
    REPEAT
    2DROP DROP -1 ;

: _otst-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

CREATE _otst-tokens OAUTH2-TOKEN-SET-SIZE ALLOT
CREATE _otst-tokens-b OAUTH2-TOKEN-SET-SIZE ALLOT
CREATE _otst-lease OAUTH2-REFRESH-LEASE-SIZE ALLOT
CREATE _otst-lease-b OAUTH2-REFRESH-LEASE-SIZE ALLOT
CREATE _otst-old-lease OAUTH2-REFRESH-LEASE-SIZE ALLOT
CREATE _otst-id 32 ALLOT
CREATE _otst-access 64 ALLOT
CREATE _otst-refresh 64 ALLOT
CREATE _otst-new-access 64 ALLOT
CREATE _otst-new-refresh 64 ALLOT
CREATE _otst-observed 64 ALLOT

: _otst-sources  ( -- )
    _otst-id 32 0xFF FILL
    _otst-access 64 0xA1 FILL
    _otst-refresh 64 0xB2 FILL
    _otst-new-access 64 0xC3 FILL
    _otst-new-refresh 64 0xD4 FILL
    _otst-observed 64 0 FILL
    0 _otst-observed-u ! ;

: _otst-set-at  ( tokens -- status )
    >R
    _otst-id 7
    _otst-access 12
    _otst-refresh 11
    111 R> O2TOK-SET ;

: _otst-set  ( -- status )
    _otst-tokens _otst-set-at ;

: _otst-capture  ( token-a token-u context -- status )
    >R
    DUP _otst-observed-u !
    R> SWAP MOVE
    O2TOK-S-OK ;

: _otst-throw  ( token-a token-u context -- status )
    2DROP DROP
    -771 THROW ;

: _otst-reentrant-clear  ( token-a token-u tokens -- status )
    >R 2DROP R> O2TOK-CLEAR? ;

: _otst-test-vocabulary  ( -- )
    O2TOK-ACCESS-CAPACITY 8192 = _otst-assert
    O2TOK-REFRESH-CAPACITY 4096 = _otst-assert
    O2TOK-ID-CAPACITY 8192 = _otst-assert
    OAUTH2-REFRESH-LEASE-SIZE 32 = _otst-assert
    OAUTH2-TOKEN-SET-SIZE 40960 > _otst-assert
    O2TOK-S-OK O2TOK-STATUS-VALID? _otst-assert
    O2TOK-S-PLATFORM O2TOK-STATUS-VALID? _otst-assert
    O2TOK-S-PLATFORM 1+ O2TOK-STATUS-VALID? 0= _otst-assert
    -1 O2TOK-STATUS-VALID? 0= _otst-assert
    0 O2TOK-INIT? O2TOK-S-RANGE = _otst-assert
    _otst-lease O2TOK-REFRESH-LEASE-INIT?
        O2TOK-S-OK = _otst-assert
    _otst-lease-b O2TOK-REFRESH-LEASE-INIT?
        O2TOK-S-OK = _otst-assert
    _otst-old-lease O2TOK-REFRESH-LEASE-INIT?
        O2TOK-S-OK = _otst-assert
    _otst-stack ;

: _otst-test-set-stage-and-alias  ( -- )
    _otst-tokens OAUTH2-TOKEN-SET-SIZE 0x5A FILL
    _otst-tokens O2TOK-INIT? O2TOK-S-OK = _otst-assert
    _otst-tokens O2TOK.GENERATION @ 1 = _otst-assert
    _otst-tokens _O2TOK.STAGE-ACCESS
        O2TOK-ACCESS-CAPACITY _otst-zero? _otst-assert

    _otst-set O2TOK-S-OK = _otst-assert
    _otst-tokens O2TOK-PRESENCE
        O2TOK-S-OK = _otst-assert
        _otst-assert
    _otst-tokens O2TOK.GENERATION @ 2 = _otst-assert
    _otst-tokens O2TOK.ID-U @ 7 = _otst-assert
    _otst-tokens O2TOK.ACCESS-U @ 12 = _otst-assert
    _otst-tokens _O2TOK.REFRESH-U @ 11 = _otst-assert
    _otst-tokens O2TOK.ID _otst-id 7 _otst-bytes= _otst-assert
    _otst-tokens O2TOK.ACCESS _otst-access 12
        _otst-bytes= _otst-assert
    _otst-tokens _O2TOK.REFRESH _otst-refresh 11
        _otst-bytes= _otst-assert
    _otst-tokens _O2TOK.STAGE-ACCESS
        O2TOK-ACCESS-CAPACITY _otst-zero? _otst-assert
    _otst-tokens _O2TOK.STAGE-REFRESH
        O2TOK-REFRESH-CAPACITY _otst-zero? _otst-assert
    _otst-tokens _O2TOK.STAGE-ID
        O2TOK-ID-CAPACITY _otst-zero? _otst-assert

    _otst-tokens O2TOK.GENERATION @ _otst-generation !
    _otst-tokens O2TOK.ACCESS 1
    _otst-access 12 _otst-refresh 11
    112 _otst-tokens O2TOK-SET
        O2TOK-S-ALIAS = _otst-assert
    _otst-tokens O2TOK.GENERATION @
        _otst-generation @ = _otst-assert
    _otst-set O2TOK-S-BUSY = _otst-assert

    0 0 _otst-access 12 0 0
    -1 _otst-tokens O2TOK-SET
        O2TOK-S-INVALID = _otst-assert
    _otst-tokens O2TOK.GENERATION @
        _otst-generation @ = _otst-assert
    _otst-stack ;

: _otst-test-optional-refresh-and-id  ( -- )
    _otst-tokens O2TOK-CLEAR? O2TOK-S-OK = _otst-assert
    0 0 _otst-access 4 0 0
    333 _otst-tokens O2TOK-SET
        O2TOK-S-OK = _otst-assert
    _otst-tokens O2TOK-PRESENCE
        O2TOK-S-OK = _otst-assert
        _otst-assert
    _otst-tokens O2TOK.ID-U @ 0= _otst-assert
    _otst-tokens _O2TOK.REFRESH-U @ 0= _otst-assert
    _otst-lease _otst-tokens O2TOK-REFRESH-BEGIN
        O2TOK-S-ABSENT = _otst-assert
    _otst-tokens O2TOK-CLEAR? O2TOK-S-OK = _otst-assert
    _otst-set O2TOK-S-OK = _otst-assert
    _otst-stack ;

: _otst-test-access-borrow  ( -- )
    ['] _otst-capture _otst-observed _otst-tokens
        O2TOK-WITH-ACCESS O2TOK-S-OK = _otst-assert
    _otst-observed-u @ 12 = _otst-assert
    _otst-observed _otst-access 12
        _otst-bytes= _otst-assert

    ['] _otst-throw 0 _otst-tokens
        O2TOK-WITH-ACCESS O2TOK-S-CALLBACK = _otst-assert
    _otst-tokens O2TOK.BORROWED @ 0= _otst-assert
    _otst-tokens _O2TOK.GUARD GUARD-HELD? 0= _otst-assert
    ['] _otst-capture _otst-observed _otst-tokens
        O2TOK-WITH-ACCESS O2TOK-S-OK = _otst-assert

    ['] _otst-reentrant-clear _otst-tokens _otst-tokens
        O2TOK-WITH-ACCESS O2TOK-S-BUSY = _otst-assert
    _otst-tokens O2TOK-PRESENCE
        O2TOK-S-OK = _otst-assert
        _otst-assert
    _otst-stack ;

: _otst-begin  ( -- )
    _otst-lease _otst-tokens O2TOK-REFRESH-BEGIN
        O2TOK-S-OK = _otst-assert ;

: _otst-test-lease-throw-and-abort  ( -- )
    _otst-tokens O2TOK.ACCESS _otst-tokens O2TOK-REFRESH-BEGIN
        O2TOK-S-ALIAS = _otst-assert
    _otst-begin
    _otst-lease-b _otst-tokens O2TOK-REFRESH-BEGIN
        O2TOK-S-BUSY = _otst-assert
    _otst-tokens O2TOK-INIT? O2TOK-S-BUSY = _otst-assert
    _otst-lease O2TOK-REFRESH-LEASE-INIT?
        O2TOK-S-BUSY = _otst-assert
    _otst-set O2TOK-S-BUSY = _otst-assert

    ['] _otst-throw 0 _otst-lease _otst-tokens
        O2TOK-WITH-REFRESH-LEASE
        O2TOK-S-CALLBACK = _otst-assert
    _otst-tokens _O2TOK.LEASE-ID @
        _otst-lease _O2LEASE.ID @ = _otst-assert
    _otst-tokens _O2TOK.LEASE-USED @ -1 = _otst-assert
    _otst-tokens _O2TOK.GUARD GUARD-HELD? 0= _otst-assert

    ['] _otst-capture _otst-observed
        _otst-lease _otst-tokens
        O2TOK-WITH-REFRESH-LEASE
        O2TOK-S-BUSY = _otst-assert
    _otst-lease _otst-tokens O2TOK-REFRESH-ABORT
        O2TOK-S-OK = _otst-assert
    _otst-tokens _O2TOK.LEASE-ID @ 0= _otst-assert
    _otst-lease _O2LEASE.OWNER @ 0= _otst-assert
    _otst-stack ;

: _otst-test-lease-commit  ( -- )
    _otst-begin
    _otst-lease _otst-old-lease OAUTH2-REFRESH-LEASE-SIZE MOVE
    ['] _otst-capture _otst-observed
        _otst-lease _otst-tokens
        O2TOK-WITH-REFRESH-LEASE
        O2TOK-S-OK = _otst-assert
    _otst-observed-u @ 11 = _otst-assert
    _otst-observed _otst-refresh 11
        _otst-bytes= _otst-assert

    _otst-tokens O2TOK.GENERATION @ _otst-generation !
    0 0 _otst-new-access 5 _otst-new-refresh 9
    222 _otst-lease _otst-tokens
        O2TOK-REFRESH-COMMIT O2TOK-S-OK = _otst-assert
    _otst-tokens O2TOK.GENERATION @
        _otst-generation @ 1+ = _otst-assert
    _otst-tokens _O2TOK.LEASE-ID @ 0= _otst-assert
    _otst-tokens O2TOK.ACCESS-U @ 5 = _otst-assert
    _otst-tokens _O2TOK.REFRESH-U @ 9 = _otst-assert
    _otst-tokens O2TOK.ID-U @ 7 = _otst-assert
    _otst-tokens O2TOK.EXPIRES-MS @ 222 = _otst-assert
    _otst-tokens O2TOK.ACCESS _otst-new-access 5
        _otst-bytes= _otst-assert
    _otst-tokens _O2TOK.REFRESH _otst-new-refresh 9
        _otst-bytes= _otst-assert
    _otst-tokens _O2TOK.STAGE-ACCESS
        O2TOK-ACCESS-CAPACITY _otst-zero? _otst-assert
    _otst-lease _O2LEASE.OWNER @ 0= _otst-assert
    _otst-old-lease _otst-tokens O2TOK-REFRESH-ABORT
        O2TOK-S-STALE = _otst-assert
    _otst-stack ;

: _otst-test-cross-object-lease  ( -- )
    _otst-tokens O2TOK-INIT? O2TOK-S-OK = _otst-assert
    _otst-tokens-b O2TOK-INIT? O2TOK-S-OK = _otst-assert
    _otst-set O2TOK-S-OK = _otst-assert
    _otst-tokens-b _otst-set-at O2TOK-S-OK = _otst-assert
    _otst-lease _otst-tokens O2TOK-REFRESH-BEGIN
        O2TOK-S-OK = _otst-assert
    _otst-lease-b _otst-tokens-b O2TOK-REFRESH-BEGIN
        O2TOK-S-OK = _otst-assert
    _otst-lease _O2LEASE.ID @
        _otst-lease-b _O2LEASE.ID @ = _otst-assert
    _otst-lease _O2LEASE.GENERATION @
        _otst-lease-b _O2LEASE.GENERATION @ = _otst-assert

    ['] _otst-capture _otst-observed
        _otst-lease _otst-tokens-b O2TOK-WITH-REFRESH-LEASE
        O2TOK-S-STALE = _otst-assert
    0 0 _otst-new-access 5 0 0
    222 _otst-lease _otst-tokens-b O2TOK-REFRESH-COMMIT
        O2TOK-S-STALE = _otst-assert

    _otst-lease _otst-tokens O2TOK-REFRESH-ABORT
        O2TOK-S-OK = _otst-assert
    _otst-lease-b _otst-tokens-b O2TOK-REFRESH-ABORT
        O2TOK-S-OK = _otst-assert
    _otst-stack ;

: _otst-test-clear-invalidates-lease  ( -- )
    _otst-begin
    _otst-lease _otst-old-lease OAUTH2-REFRESH-LEASE-SIZE MOVE
    _otst-tokens O2TOK-CLEAR? O2TOK-S-OK = _otst-assert
    _otst-tokens O2TOK-PRESENCE
        O2TOK-S-OK = _otst-assert
        0= _otst-assert
    _otst-tokens O2TOK.ACCESS O2TOK-ACCESS-CAPACITY
        _otst-zero? _otst-assert
    _otst-tokens _O2TOK.REFRESH O2TOK-REFRESH-CAPACITY
        _otst-zero? _otst-assert
    _otst-tokens O2TOK.ID O2TOK-ID-CAPACITY
        _otst-zero? _otst-assert
    _otst-lease _O2LEASE.OWNER @ 0= _otst-assert
    _otst-old-lease _otst-tokens O2TOK-REFRESH-ABORT
        O2TOK-S-STALE = _otst-assert
    _otst-stack ;

: _OTST-RUN  ( -- )
    0 _otst-fails !
    0 _otst-checks !
    DEPTH _otst-depth !
    _otst-sources
    ." OAUTH2 TOKEN SET RUN START" CR
    _otst-test-vocabulary
    _otst-test-set-stage-and-alias
    _otst-test-optional-refresh-and-id
    _otst-test-access-borrow
    _otst-test-lease-throw-and-abort
    _otst-test-lease-commit
    _otst-test-cross-object-lease
    _otst-test-clear-invalidates-lease
    _otst-stack
    _otst-fails @ 0= IF
        ." OAUTH2 TOKEN SET PASS " _otst-checks @ . CR
    ELSE
        ." OAUTH2 TOKEN SET FAIL " _otst-fails @ . CR
    THEN ;
