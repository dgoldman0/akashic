\ =====================================================================
\  message.f - Bounded JSON-RPC 2.0 messages and serialization
\ =====================================================================
\  Parsed strings are copied into the caller-owned message descriptor.
\  Params, result, and error data are borrowed spans into the input buffer.
\  The input buffer must remain alive while those spans are in use.
\ =====================================================================

PROVIDED akashic-jsonrpc-message

REQUIRE ../../utils/json.f
REQUIRE ../../utils/string.f
REQUIRE ../../text/utf8.f

-32700 CONSTANT JRPC-E-PARSE
-32600 CONSTANT JRPC-E-INVALID-REQUEST
-32601 CONSTANT JRPC-E-METHOD-NOT-FOUND
-32602 CONSTANT JRPC-E-INVALID-PARAMS
-32603 CONSTANT JRPC-E-INTERNAL

1 CONSTANT JRPC-IOR-CAPACITY
2 CONSTANT JRPC-IOR-VALUE

0 CONSTANT JRPC-K-INVALID
1 CONSTANT JRPC-K-REQUEST
2 CONSTANT JRPC-K-NOTIFICATION
3 CONSTANT JRPC-K-RESULT
4 CONSTANT JRPC-K-ERROR

0 CONSTANT JRPC-ID-ABSENT
1 CONSTANT JRPC-ID-NULL
2 CONSTANT JRPC-ID-INT
3 CONSTANT JRPC-ID-STRING

65536 CONSTANT JRPC-MAX-MESSAGE
16 CONSTANT JRPC-MAX-DEPTH
96 CONSTANT JRPC-MAX-METHOD
96 CONSTANT JRPC-MAX-ID-STRING
160 CONSTANT JRPC-MAX-ERROR-MESSAGE

  0 CONSTANT _JM-KIND
  8 CONSTANT _JM-ID-KIND
 16 CONSTANT _JM-ID-INT
 24 CONSTANT _JM-ID-A
 32 CONSTANT _JM-ID-U
 40 CONSTANT _JM-METHOD-A
 48 CONSTANT _JM-METHOD-U
 56 CONSTANT _JM-PARAMS-A
 64 CONSTANT _JM-PARAMS-U
 72 CONSTANT _JM-RESULT-A
 80 CONSTANT _JM-RESULT-U
 88 CONSTANT _JM-ERROR-CODE
 96 CONSTANT _JM-ERROR-MESSAGE-A
104 CONSTANT _JM-ERROR-MESSAGE-U
112 CONSTANT _JM-ERROR-DATA-A
120 CONSTANT _JM-ERROR-DATA-U
128 CONSTANT _JM-RAW-A
136 CONSTANT _JM-RAW-U
144 CONSTANT _JM-FLAGS
152 CONSTANT _JM-RESERVED
160 CONSTANT _JM-METHOD-BUF
256 CONSTANT _JM-ID-BUF
352 CONSTANT _JM-ERROR-MESSAGE-BUF
512 CONSTANT JRPC-MESSAGE-SIZE

: JRPC.KIND             ( message -- a ) _JM-KIND + ;
: JRPC.ID-KIND          ( message -- a ) _JM-ID-KIND + ;
: JRPC.ID-INT           ( message -- a ) _JM-ID-INT + ;
: JRPC.ID-A             ( message -- a ) _JM-ID-A + ;
: JRPC.ID-U             ( message -- a ) _JM-ID-U + ;
: JRPC.METHOD-A         ( message -- a ) _JM-METHOD-A + ;
: JRPC.METHOD-U         ( message -- a ) _JM-METHOD-U + ;
: JRPC.PARAMS-A         ( message -- a ) _JM-PARAMS-A + ;
: JRPC.PARAMS-U         ( message -- a ) _JM-PARAMS-U + ;
: JRPC.RESULT-A         ( message -- a ) _JM-RESULT-A + ;
: JRPC.RESULT-U         ( message -- a ) _JM-RESULT-U + ;
: JRPC.ERROR-CODE       ( message -- a ) _JM-ERROR-CODE + ;
: JRPC.ERROR-MESSAGE-A  ( message -- a ) _JM-ERROR-MESSAGE-A + ;
: JRPC.ERROR-MESSAGE-U  ( message -- a ) _JM-ERROR-MESSAGE-U + ;
: JRPC.ERROR-DATA-A     ( message -- a ) _JM-ERROR-DATA-A + ;
: JRPC.ERROR-DATA-U     ( message -- a ) _JM-ERROR-DATA-U + ;
: JRPC.RAW-A            ( message -- a ) _JM-RAW-A + ;
: JRPC.RAW-U            ( message -- a ) _JM-RAW-U + ;
: JRPC.FLAGS            ( message -- a ) _JM-FLAGS + ;
: JRPC.METHOD-BUF       ( message -- a ) _JM-METHOD-BUF + ;
: JRPC.ID-BUF           ( message -- a ) _JM-ID-BUF + ;
: JRPC.ERROR-MESSAGE-BUF ( message -- a ) _JM-ERROR-MESSAGE-BUF + ;

: JRPC-MESSAGE-INIT  ( message -- )
    JRPC-MESSAGE-SIZE 0 FILL ;

: JRPC-METHOD  ( message -- addr len )
    DUP JRPC.METHOD-A @ SWAP JRPC.METHOD-U @ ;

: JRPC-ID-TEXT  ( message -- addr len )
    DUP JRPC.ID-A @ SWAP JRPC.ID-U @ ;

\ Generic JSON grammar and Unicode decoding live in utils/json.f.  This
\ module adds only the JSON-RPC size bound and maps JSON errors to its IORs.
: _JRPC-DIGIT?  ( c -- flag )
    DUP 48 >= SWAP 57 <= AND ;

: JRPC-JSON-VALID?  ( addr len -- flag )
    DUP JRPC-MAX-MESSAGE > IF 2DROP 0 EXIT THEN
    JSON-VALID? ;

: _JRPC-UNESCAPE  ( src len dest cap -- decoded-len ior )
    JSON-UNESCAPE
    JSON-OK? IF 0 EXIT THEN
    DROP 0
    JSON-ERR @ JSON-E-OVERFLOW = IF
        JRPC-IOR-CAPACITY
    ELSE
        JRPC-IOR-VALUE
    THEN ;

\ =====================================================================
\  Message parsing
\ =====================================================================

VARIABLE _JPM-A
VARIABLE _JPM-U
VARIABLE _JPM-M
VARIABLE _JPM-ROOT-A
VARIABLE _JPM-ROOT-U
VARIABLE _JPM-HAS-METHOD
VARIABLE _JPM-HAS-RESULT
VARIABLE _JPM-HAS-ERROR
VARIABLE _JPM-LOOKUP-ERROR

VARIABLE _JLK-TARGET-A
VARIABLE _JLK-TARGET-U
VARIABLE _JLK-CUR-A
VARIABLE _JLK-CUR-U
VARIABLE _JLK-KEY-A
VARIABLE _JLK-KEY-U
VARIABLE _JLK-FOUND-A
VARIABLE _JLK-FOUND-U
VARIABLE _JLK-COUNT
CREATE _JLK-KEY-BUF 96 ALLOT

: _JRPC-LOOKUP-IN  ( object-a object-u key-a key-u -- value-a value-u flag )
    _JLK-TARGET-U ! _JLK-TARGET-A !
    JSON-ENTER _JLK-CUR-U ! _JLK-CUR-A !
    0 _JLK-COUNT !
    BEGIN
        _JLK-CUR-A @ _JLK-CUR-U @ JSON-EACH-KEY
        IF
            _JLK-KEY-U ! _JLK-KEY-A ! _JLK-CUR-U ! _JLK-CUR-A !
            _JLK-KEY-U @ _JLK-TARGET-U @ 12 * <= IF
                _JLK-KEY-A @ _JLK-KEY-U @ _JLK-KEY-BUF 96
                _JRPC-UNESCAPE
                DUP IF
                    2DROP -1 _JPM-LOOKUP-ERROR !
                ELSE
                    DROP _JLK-KEY-BUF SWAP
                    _JLK-TARGET-A @ _JLK-TARGET-U @ STR-STR= IF
                        _JLK-COUNT @ IF -1 _JPM-LOOKUP-ERROR ! THEN
                        _JLK-CUR-A @ _JLK-FOUND-A !
                        _JLK-CUR-U @ _JLK-FOUND-U !
                        1 _JLK-COUNT +!
                    THEN
                THEN
            THEN
            _JLK-CUR-A @ _JLK-CUR-U @ JSON-NEXT DROP
            _JLK-CUR-U ! _JLK-CUR-A !
        ELSE
            2DROP 2DROP
            _JLK-COUNT @ IF
                _JLK-FOUND-A @ _JLK-FOUND-U @ -1
            ELSE
                0 0 0
            THEN
            EXIT
        THEN
    AGAIN ;

: _JRPC-ROOT-LOOKUP  ( key-a key-u -- value-a value-u flag )
    _JPM-ROOT-A @ _JPM-ROOT-U @ 2SWAP _JRPC-LOOKUP-IN ;

VARIABLE _JSP-A
VARIABLE _JSP-U

: _JRPC-VALUE-SPAN  ( value-a value-u -- value-a span-u )
    _JSP-U ! _JSP-A !
    _JSP-A @ _JSP-U @ JSON-SKIP-VALUE DROP _JSP-A @ -
    _JSP-A @ SWAP ;

: _JRPC-INTEGER?  ( value-a value-u -- flag )
    _JRPC-VALUE-SPAN _JSP-U ! _JSP-A !
    _JSP-U @ 0= IF 0 EXIT THEN
    _JSP-A @ C@ 45 = IF
        _JSP-U @ 1- DUP 0= SWAP 18 > OR IF 0 EXIT THEN
        _JSP-A @ 1+ _JSP-A ! -1 _JSP-U +!
    ELSE
        _JSP-U @ 18 > IF 0 EXIT THEN
    THEN
    _JSP-U @ 0 DO
        _JSP-A @ I + C@ _JRPC-DIGIT? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

VARIABLE _JSD-V-A
VARIABLE _JSD-V-U
VARIABLE _JSD-D
VARIABLE _JSD-CAP

: _JRPC-DECODE-STRING  ( value-a value-u dest cap -- length ior )
    _JSD-CAP ! _JSD-D ! _JSD-V-U ! _JSD-V-A !
    _JSD-V-A @ _JSD-V-U @ JSON-STRING? 0= IF 0 JRPC-IOR-VALUE EXIT THEN
    _JSD-V-A @ _JSD-V-U @ JSON-GET-STRING
    _JSD-D @ _JSD-CAP @ _JRPC-UNESCAPE ;

VARIABLE _JPI-V-A
VARIABLE _JPI-V-U
VARIABLE _JPI-M

: _JRPC-PARSE-ID  ( value-a value-u message -- ior )
    _JPI-M ! _JPI-V-U ! _JPI-V-A !
    _JPI-V-A @ _JPI-V-U @ JSON-NULL? IF
        JRPC-ID-NULL _JPI-M @ JRPC.ID-KIND ! 0 EXIT
    THEN
    _JPI-V-A @ _JPI-V-U @ JSON-NUMBER? IF
        _JPI-V-A @ _JPI-V-U @ _JRPC-INTEGER? 0= IF
            JRPC-E-INVALID-REQUEST EXIT
        THEN
        JRPC-ID-INT _JPI-M @ JRPC.ID-KIND !
        _JPI-V-A @ _JPI-V-U @ JSON-GET-NUMBER _JPI-M @ JRPC.ID-INT !
        0 EXIT
    THEN
    _JPI-V-A @ _JPI-V-U @ JSON-STRING? IF
        _JPI-V-A @ _JPI-V-U @ _JPI-M @ JRPC.ID-BUF
        JRPC-MAX-ID-STRING _JRPC-DECODE-STRING
        DUP IF 2DROP JRPC-E-INVALID-REQUEST EXIT THEN
        DROP _JPI-M @ JRPC.ID-U !
        _JPI-M @ JRPC.ID-BUF _JPI-M @ JRPC.ID-A !
        JRPC-ID-STRING _JPI-M @ JRPC.ID-KIND !
        0 EXIT
    THEN
    JRPC-E-INVALID-REQUEST ;

VARIABLE _JPE-A
VARIABLE _JPE-U
VARIABLE _JPE-M

: _JRPC-PARSE-ERROR  ( error-a error-u message -- ior )
    _JPE-M ! _JPE-U ! _JPE-A !
    _JPE-A @ _JPE-U @ JSON-OBJECT? 0= IF JRPC-E-INVALID-REQUEST EXIT THEN
    _JPE-A @ _JPE-U @ S" code" _JRPC-LOOKUP-IN 0= IF
        2DROP JRPC-E-INVALID-REQUEST EXIT
    THEN
    2DUP JSON-NUMBER? 0= IF 2DROP JRPC-E-INVALID-REQUEST EXIT THEN
    2DUP _JRPC-INTEGER? 0= IF 2DROP JRPC-E-INVALID-REQUEST EXIT THEN
    JSON-GET-NUMBER _JPE-M @ JRPC.ERROR-CODE !
    _JPE-A @ _JPE-U @ S" message" _JRPC-LOOKUP-IN 0= IF
        2DROP JRPC-E-INVALID-REQUEST EXIT
    THEN
    _JPE-M @ JRPC.ERROR-MESSAGE-BUF JRPC-MAX-ERROR-MESSAGE
    _JRPC-DECODE-STRING
    DUP IF 2DROP JRPC-E-INVALID-REQUEST EXIT THEN
    DROP _JPE-M @ JRPC.ERROR-MESSAGE-U !
    _JPE-M @ JRPC.ERROR-MESSAGE-BUF _JPE-M @ JRPC.ERROR-MESSAGE-A !
    _JPE-A @ _JPE-U @ S" data" _JRPC-LOOKUP-IN IF
        _JRPC-VALUE-SPAN
        _JPE-M @ JRPC.ERROR-DATA-U ! _JPE-M @ JRPC.ERROR-DATA-A !
    ELSE
        2DROP
    THEN
    0 ;

: JRPC-PARSE  ( json-a json-u message -- ior )
    _JPM-M ! _JPM-U ! _JPM-A !
    _JPM-M @ JRPC-MESSAGE-INIT
    _JPM-A @ _JPM-U @ _JPM-M @ JRPC.RAW-U ! _JPM-M @ JRPC.RAW-A !
    _JPM-U @ JRPC-MAX-MESSAGE > IF JRPC-E-INVALID-REQUEST EXIT THEN
    _JPM-A @ _JPM-U @ JRPC-JSON-VALID? 0= IF JRPC-E-PARSE EXIT THEN
    _JPM-A @ _JPM-U @ JSON-OBJECT? 0= IF JRPC-E-INVALID-REQUEST EXIT THEN
    _JPM-A @ _JPM-U @ JSON-ENTER _JPM-ROOT-U ! _JPM-ROOT-A !
    0 _JPM-LOOKUP-ERROR !

    S" jsonrpc" _JRPC-ROOT-LOOKUP 0= IF
        2DROP JRPC-E-INVALID-REQUEST EXIT
    THEN
    _JPM-M @ JRPC.ERROR-MESSAGE-BUF 8 _JRPC-DECODE-STRING
    DUP IF 2DROP JRPC-E-INVALID-REQUEST EXIT THEN
    DROP _JPM-M @ JRPC.ERROR-MESSAGE-BUF SWAP
    S" 2.0" STR-STR= 0= IF JRPC-E-INVALID-REQUEST EXIT THEN

    JRPC-ID-ABSENT _JPM-M @ JRPC.ID-KIND !
    S" id" _JRPC-ROOT-LOOKUP IF
        _JPM-M @ _JRPC-PARSE-ID ?DUP IF EXIT THEN
    ELSE
        2DROP
    THEN

    0 _JPM-HAS-METHOD ! 0 _JPM-HAS-RESULT ! 0 _JPM-HAS-ERROR !
    S" method" _JRPC-ROOT-LOOKUP IF
        -1 _JPM-HAS-METHOD !
        _JPM-M @ JRPC.METHOD-BUF JRPC-MAX-METHOD _JRPC-DECODE-STRING
        DUP IF 2DROP JRPC-E-INVALID-REQUEST EXIT THEN
        DROP _JPM-M @ JRPC.METHOD-U !
        _JPM-M @ JRPC.METHOD-BUF _JPM-M @ JRPC.METHOD-A !
    ELSE
        2DROP
    THEN

    S" params" _JRPC-ROOT-LOOKUP IF
        2DUP JSON-OBJECT? >R 2DUP JSON-ARRAY? R> OR 0= IF
            2DROP JRPC-E-INVALID-PARAMS EXIT
        THEN
        _JRPC-VALUE-SPAN
        _JPM-M @ JRPC.PARAMS-U ! _JPM-M @ JRPC.PARAMS-A !
    ELSE
        2DROP
    THEN

    S" result" _JRPC-ROOT-LOOKUP IF
        -1 _JPM-HAS-RESULT !
        _JRPC-VALUE-SPAN
        _JPM-M @ JRPC.RESULT-U ! _JPM-M @ JRPC.RESULT-A !
    ELSE
        2DROP
    THEN

    S" error" _JRPC-ROOT-LOOKUP IF
        -1 _JPM-HAS-ERROR !
        _JPM-M @ _JRPC-PARSE-ERROR ?DUP IF EXIT THEN
    ELSE
        2DROP
    THEN

    _JPM-LOOKUP-ERROR @ IF JRPC-E-INVALID-REQUEST EXIT THEN

    _JPM-HAS-METHOD @ IF
        _JPM-HAS-RESULT @ _JPM-HAS-ERROR @ OR IF
            JRPC-E-INVALID-REQUEST EXIT
        THEN
        _JPM-M @ JRPC.ID-KIND @ JRPC-ID-ABSENT = IF
            JRPC-K-NOTIFICATION
        ELSE
            JRPC-K-REQUEST
        THEN
        _JPM-M @ JRPC.KIND ! 0 EXIT
    THEN

    _JPM-M @ JRPC.ID-KIND @ JRPC-ID-ABSENT = IF
        JRPC-E-INVALID-REQUEST EXIT
    THEN
    _JPM-HAS-RESULT @ _JPM-HAS-ERROR @ = IF
        JRPC-E-INVALID-REQUEST EXIT
    THEN
    _JPM-HAS-RESULT @ IF JRPC-K-RESULT ELSE JRPC-K-ERROR THEN
    _JPM-M @ JRPC.KIND ! 0 ;

\ =====================================================================
\  Message serialization
\ =====================================================================

VARIABLE _JBB-BUF
VARIABLE _JBB-CAP

: _JRPC-BUILD-BEGIN  ( buffer capacity -- )
    _JBB-CAP ! _JBB-BUF !
    JSON-BUILD-RESET _JBB-BUF @ _JBB-CAP @ JSON-SET-OUTPUT ;

: _JRPC-BUILD-END  ( -- length ior )
    JSON-OUTPUT-OK? 0= IF 0 JRPC-IOR-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP 0 ;

: _JRPC-VALID-PARAMS?  ( addr len -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    2DUP JRPC-JSON-VALID? 0= IF 2DROP 0 EXIT THEN
    2DUP JSON-OBJECT? >R JSON-ARRAY? R> OR ;

VARIABLE _JBR-ID
VARIABLE _JBR-MA
VARIABLE _JBR-MU
VARIABLE _JBR-PA
VARIABLE _JBR-PU

: JRPC-BUILD-REQUEST  ( id method-a method-u params-a params-u buffer cap -- length ior )
    _JBB-CAP ! _JBB-BUF ! _JBR-PU ! _JBR-PA !
    _JBR-MU ! _JBR-MA ! _JBR-ID !
    _JBR-MU @ JRPC-MAX-METHOD >
    _JBR-MA @ _JBR-MU @ UTF8-VALID? 0= OR IF 0 JRPC-IOR-VALUE EXIT THEN
    _JBR-PA @ _JBR-PU @ _JRPC-VALID-PARAMS? 0= IF
        0 JRPC-IOR-VALUE EXIT
    THEN
    _JBB-BUF @ _JBB-CAP @ _JRPC-BUILD-BEGIN
    JSON-{ S" jsonrpc" S" 2.0" JSON-KV-ESTR
    S" id" JSON-KEY: _JBR-ID @ JSON-NUM
    S" method" JSON-KEY: _JBR-MA @ _JBR-MU @ JSON-ESTR
    _JBR-PU @ IF S" params" _JBR-PA @ _JBR-PU @ JSON-KV-RAW THEN
    JSON-} _JRPC-BUILD-END ;

: JRPC-BUILD-NOTIFICATION  ( method-a method-u params-a params-u buffer cap -- length ior )
    _JBB-CAP ! _JBB-BUF ! _JBR-PU ! _JBR-PA ! _JBR-MU ! _JBR-MA !
    _JBR-MU @ JRPC-MAX-METHOD >
    _JBR-MA @ _JBR-MU @ UTF8-VALID? 0= OR IF 0 JRPC-IOR-VALUE EXIT THEN
    _JBR-PA @ _JBR-PU @ _JRPC-VALID-PARAMS? 0= IF
        0 JRPC-IOR-VALUE EXIT
    THEN
    _JBB-BUF @ _JBB-CAP @ _JRPC-BUILD-BEGIN
    JSON-{ S" jsonrpc" S" 2.0" JSON-KV-ESTR
    S" method" JSON-KEY: _JBR-MA @ _JBR-MU @ JSON-ESTR
    _JBR-PU @ IF S" params" _JBR-PA @ _JBR-PU @ JSON-KV-RAW THEN
    JSON-} _JRPC-BUILD-END ;

: _JRPC-EMIT-ID  ( message | 0 -- )
    S" id" JSON-KEY:
    DUP 0= IF DROP JSON-NULL EXIT THEN
    DUP JRPC.ID-KIND @ CASE
        JRPC-ID-NULL OF DROP JSON-NULL ENDOF
        JRPC-ID-INT OF JRPC.ID-INT @ JSON-NUM ENDOF
        JRPC-ID-STRING OF JRPC-ID-TEXT JSON-ESTR ENDOF
        DROP JSON-NULL
    ENDCASE ;

VARIABLE _JBS-M
VARIABLE _JBS-A
VARIABLE _JBS-U

: JRPC-BUILD-RESULT  ( request-message result-a result-u buffer cap -- length ior )
    _JBB-CAP ! _JBB-BUF ! _JBS-U ! _JBS-A ! _JBS-M !
    _JBS-A @ _JBS-U @ JRPC-JSON-VALID? 0= IF 0 JRPC-IOR-VALUE EXIT THEN
    _JBB-BUF @ _JBB-CAP @ _JRPC-BUILD-BEGIN
    JSON-{ S" jsonrpc" S" 2.0" JSON-KV-ESTR
    _JBS-M @ _JRPC-EMIT-ID
    S" result" _JBS-A @ _JBS-U @ JSON-KV-RAW
    JSON-} _JRPC-BUILD-END ;

VARIABLE _JBE-M
VARIABLE _JBE-CODE
VARIABLE _JBE-MA
VARIABLE _JBE-MU
VARIABLE _JBE-DA
VARIABLE _JBE-DU

: JRPC-BUILD-ERROR  ( request-message code message-a message-u data-a data-u buffer cap -- length ior )
    _JBB-CAP ! _JBB-BUF ! _JBE-DU ! _JBE-DA !
    _JBE-MU ! _JBE-MA ! _JBE-CODE ! _JBE-M !
    _JBE-MA @ _JBE-MU @ UTF8-VALID? 0= IF 0 JRPC-IOR-VALUE EXIT THEN
    _JBE-DU @ IF
        _JBE-DA @ _JBE-DU @ JRPC-JSON-VALID? 0= IF 0 JRPC-IOR-VALUE EXIT THEN
    THEN
    _JBB-BUF @ _JBB-CAP @ _JRPC-BUILD-BEGIN
    JSON-{ S" jsonrpc" S" 2.0" JSON-KV-ESTR
    _JBE-M @ _JRPC-EMIT-ID
    S" error" JSON-KEY: JSON-{
        S" code" _JBE-CODE @ JSON-KV-NUM
        S" message" _JBE-MA @ _JBE-MU @ JSON-KV-ESTR
        _JBE-DU @ IF S" data" _JBE-DA @ _JBE-DU @ JSON-KV-RAW THEN
    JSON-}
    JSON-} _JRPC-BUILD-END ;
