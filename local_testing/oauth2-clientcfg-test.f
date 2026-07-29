\ Focused contracts for the immutable generic OAuth client configuration.

PROVIDED oauth2-client-config-test

VARIABLE _o2cct-fails
VARIABLE _o2cct-checks
VARIABLE _o2cct-depth

CREATE _o2cct-input-storage
    OAUTH2-CLIENT-CONFIG-INPUT-SIZE 7 + ALLOT
CREATE _o2cct-config-storage
    OAUTH2-CLIENT-CONFIG-SIZE 7 + ALLOT
CREATE _o2cct-other-storage
    OAUTH2-CLIENT-CONFIG-SIZE 7 + ALLOT
CREATE _o2cct-source-storage
    OAUTH2-CLIENT-CONFIG-CLIENT-ID-CAPACITY 7 + ALLOT

: _o2cct-input  ( -- input )
    _o2cct-input-storage 7 + -8 AND ;
: _o2cct-config  ( -- config )
    _o2cct-config-storage 7 + -8 AND ;
: _o2cct-other  ( -- config )
    _o2cct-other-storage 7 + -8 AND ;
: _o2cct-source  ( -- address )
    _o2cct-source-storage 7 + -8 AND ;

: _o2cct-assert  ( flag -- )
    1 _o2cct-checks +!
    0= IF
        1 _o2cct-fails +!
        ." OAUTH2 CLIENT CONFIG ASSERT " _o2cct-checks @ . CR
    THEN ;

: _o2cct-stack  ( -- )
    DEPTH DUP _o2cct-depth @ <> IF
        ." OAUTH2 CLIENT CONFIG STACK "
        _o2cct-depth @ . ." -> " DUP . CR .S CR
    THEN
    _o2cct-depth @ = _o2cct-assert ;

: _o2cct-zero?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _o2cct-input!  ( address length address-field length-field -- )
    >R
    OVER R@ !
    NIP !
    R> DROP ;

: _o2cct-base-input  ( -- )
    _o2cct-input OAUTH2-CLIENT-CONFIG-INPUT-CLEAR
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    S" client-config-binding"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.BINDING-A
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.BINDING-U
        _o2cct-input!
    S" https://client.example/oauth/client-metadata.json"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U
        _o2cct-input!
    S" https://client.example/oauth/callback"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-A
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-U
        _o2cct-input!
    S" profile email"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-A
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-U
        _o2cct-input!
    S" none"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-A
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-U
        _o2cct-input!
    0 _o2cct-input OAUTH2-CLIENT-CONFIG-I.FLAGS ! ;

: _o2cct-private-input  ( -- )
    _o2cct-base-input
    S" private_key_jwt"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-A
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-U
        _o2cct-input!
    S" ES256"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-A
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-U
        _o2cct-input!
    OAUTH2-CLIENT-CONFIG-F-NATIVE
    OAUTH2-CLIENT-CONFIG-F-REFRESH OR
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND OR
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.FLAGS ! ;

: _o2cct-clean-config  ( -- )
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL ;

: _o2cct-init-public  ( -- )
    _o2cct-clean-config
    _o2cct-base-input
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert ;

: _o2cct-test-vocabulary  ( -- )
    OAUTH2-CLIENT-CONFIG-INPUT-SIZE 104 = _o2cct-assert
    OAUTH2-CLIENT-CONFIG-SIZE 11072 = _o2cct-assert
    OAUTH2-CLIENT-CONFIG-BINDING-CAPACITY 256 = _o2cct-assert
    OAUTH2-CLIENT-CONFIG-CLIENT-ID-CAPACITY 2048 = _o2cct-assert
    OAUTH2-CLIENT-CONFIG-REDIRECT-URI-CAPACITY 4096 = _o2cct-assert
    OAUTH2-CLIENT-CONFIG-SCOPE-CAPACITY 4096 = _o2cct-assert
    OAUTH2-CLIENT-CONFIG-S-OK
        OAUTH2-CLIENT-CONFIG-STATUS-VALID? _o2cct-assert
    OAUTH2-CLIENT-CONFIG-S-PLATFORM
        OAUTH2-CLIENT-CONFIG-STATUS-VALID? _o2cct-assert
    OAUTH2-CLIENT-CONFIG-S-PLATFORM 1+
        OAUTH2-CLIENT-CONFIG-STATUS-VALID? 0= _o2cct-assert
    -1 OAUTH2-CLIENT-CONFIG-STATUS-VALID? 0= _o2cct-assert
    _o2cct-input 1+ OAUTH2-CLIENT-CONFIG-INPUT-CLEAR
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert
    _o2cct-config 1+ OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert
    _o2cct-stack ;

: _o2cct-test-public-copy  ( -- )
    _o2cct-init-public
    _o2cct-config OAUTH2-CLIENT-CONFIG-VALID? _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-BINDING@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" client-config-binding" COMPARE 0= _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-CLIENT-ID@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" https://client.example/oauth/client-metadata.json"
        COMPARE 0= _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-REDIRECT-URI@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" https://client.example/oauth/callback"
        COMPARE 0= _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-SCOPE@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" profile email" COMPARE 0= _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-AUTH-METHOD@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" none" COMPARE 0= _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-AUTH-ALGORITHM@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    SWAP 0= SWAP 0= AND _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-APPLICATION-TYPE@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    OAUTH2-CLIENT-CONFIG-APPLICATION-WEB = _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-REFRESH?
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    0= _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-DPOP-BOUND?
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    0= _o2cct-assert

    _o2cct-input OAUTH2-CLIENT-CONFIG-INPUT-CLEAR
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-CLIENT-ID@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" https://client.example/oauth/client-metadata.json"
        COMPARE 0= _o2cct-assert
    _o2cct-stack ;

: _o2cct-test-private-and-scope  ( -- )
    _o2cct-config OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    _o2cct-private-input
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-AUTH-METHOD@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" private_key_jwt" COMPARE 0= _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-AUTH-ALGORITHM@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    S" ES256" COMPARE 0= _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-APPLICATION-TYPE@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    OAUTH2-CLIENT-CONFIG-APPLICATION-NATIVE = _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-REFRESH?
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-DPOP-BOUND?
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    _o2cct-base-input
    0 _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-A !
    0 _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-U !
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-SCOPE@
    DUP OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert DROP
    SWAP 0= SWAP 0= AND _o2cct-assert
    _o2cct-stack ;

: _o2cct-expect-invalid-scope  ( scope-a scope-u -- )
    _o2cct-base-input
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-U !
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-A !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE
        _o2cct-zero? _o2cct-assert ;

: _o2cct-test-syntax  ( -- )
    S"  leading" _o2cct-expect-invalid-scope
    S" trailing " _o2cct-expect-invalid-scope
    S" two  spaces" _o2cct-expect-invalid-scope
    S" badxscope" _o2cct-source SWAP MOVE
    34 _o2cct-source 3 + C!
    _o2cct-source 9 _o2cct-expect-invalid-scope
    S" bad\scope" _o2cct-expect-invalid-scope

    _o2cct-base-input
    S" https://client.example/bad redirect"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-U !
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-A !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert

    _o2cct-base-input
    S" ES256"
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-U !
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-A !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert

    _o2cct-base-input
    0 _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert

    _o2cct-base-input
    OAUTH2-CLIENT-CONFIG-CLIENT-ID-CAPACITY 1+
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-CAPACITY = _o2cct-assert

    _o2cct-base-input
    8 _o2cct-input OAUTH2-CLIENT-CONFIG-I.FLAGS !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert

    _o2cct-base-input
    0 _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-A !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert
    _o2cct-base-input
    0 _o2cct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-U !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert

    _o2cct-base-input
    5 _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-U !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert
    _o2cct-base-input
    S" ES256" DROP
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-A !
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert
    _o2cct-stack ;

: _o2cct-test-state-alias-and-corruption  ( -- )
    _o2cct-init-public
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-STATE = _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-VALID? _o2cct-assert

    _o2cct-other OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-base-input
    S" alias-source-value"
    _o2cct-other _O2CC-CLIENT-ID-OFF + SWAP MOVE
    _o2cct-other _O2CC-CLIENT-ID-OFF + 5
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U !
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A !
    _o2cct-input _o2cct-other OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-ALIAS = _o2cct-assert

    _o2cct-other OAUTH2-CLIENT-CONFIG-SIZE 0 FILL
    _o2cct-base-input
    S" badxx" _o2cct-other _O2CC-CLIENT-ID-OFF + SWAP MOVE
    10 _o2cct-other _O2CC-CLIENT-ID-OFF + 2 + C!
    _o2cct-other _O2CC-CLIENT-ID-OFF + 5
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U !
    _o2cct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A !
    _o2cct-input _o2cct-other OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-ALIAS = _o2cct-assert
    _o2cct-other _O2CC-CLIENT-ID-OFF + 2 + C@
        10 = _o2cct-assert
    _o2cct-other _O2CC.MAGIC @ 0= _o2cct-assert

    _o2cct-config OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-SIZE
        _o2cct-zero? _o2cct-assert
    _o2cct-private-input
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    8 _o2cct-config _O2CC.FLAGS !
    _o2cct-config OAUTH2-CLIENT-CONFIG-VALID? 0= _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-CLIENT-ID@
    OAUTH2-CLIENT-CONFIG-S-INVALID = _o2cct-assert
    2DROP

    _o2cct-config OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    _o2cct-base-input
    _o2cct-input _o2cct-config OAUTH2-CLIENT-CONFIG-INIT
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    1 _o2cct-config _O2CC.CLIENT-ID
    _o2cct-config _O2CC.CLIENT-ID-U @ + C!
    _o2cct-config OAUTH2-CLIENT-CONFIG-VALID? 0= _o2cct-assert
    _o2cct-config OAUTH2-CLIENT-CONFIG-WIPE
        OAUTH2-CLIENT-CONFIG-S-OK = _o2cct-assert
    _o2cct-stack ;

: _O2CCT-RUN  ( -- )
    0 _o2cct-fails !
    0 _o2cct-checks !
    DEPTH _o2cct-depth !
    _o2cct-test-vocabulary
    _o2cct-test-public-copy
    _o2cct-test-private-and-scope
    _o2cct-test-syntax
    _o2cct-test-state-alias-and-corruption
    _o2cct-stack
    _o2cct-fails @ IF
        ." OAUTH2 CLIENT CONFIG FAIL " _o2cct-fails @ .
        ." /" _o2cct-checks @ . CR
    ELSE
        ." OAUTH2 CLIENT CONFIG PASS " _o2cct-checks @ . CR
    THEN
    TX-FLUSH ;
