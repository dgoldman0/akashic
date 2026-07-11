\ =====================================================================
\  capability-json.f - JSON arguments for native capability schemas
\ =====================================================================
\  JSON Schema projection wraps scalar inputs in an object named "value".
\  This decoder is the symmetric protocol-neutral path back to native values.
\ =====================================================================

PROVIDED akashic-capability-json-codec

REQUIRE json-value.f

0 CONSTANT CAPJSON-S-OK
1 CONSTANT CAPJSON-S-INVALID

VARIABLE _CJOC-A
VARIABLE _CJOC-U
VARIABLE _CJOC-N

: _CAPJSON-OBJECT-COUNT  ( object-a object-u -- count status )
    2DUP JSON-VALID? 0= IF 2DROP 0 CAPJSON-S-INVALID EXIT THEN
    2DUP JSON-OBJECT? 0= IF 2DROP 0 CAPJSON-S-INVALID EXIT THEN
    JSON-ENTER _CJOC-U ! _CJOC-A ! 0 _CJOC-N !
    BEGIN
        _CJOC-A @ _CJOC-U @ JSON-EACH-KEY
        IF
            2DROP JSON-NEXT DROP _CJOC-U ! _CJOC-A !
            1 _CJOC-N +! -1
        ELSE
            2DROP 2DROP 0
        THEN
    0= UNTIL
    _CJOC-N @ CAPJSON-S-OK ;

VARIABLE _CJDI-SCHEMA
VARIABLE _CJDI-VALUE
VARIABLE _CJDI-A
VARIABLE _CJDI-U
VARIABLE _CJDI-VA
VARIABLE _CJDI-VU
VARIABLE _CJDI-FOUND
VARIABLE _CJDI-IOR

: CAPJSON-DECODE-INPUT  ( args-a args-u schema value -- status )
    _CJDI-VALUE ! _CJDI-SCHEMA ! _CJDI-U ! _CJDI-A !
    _CJDI-A @ _CJDI-U @ JSON-VALID? 0= IF CAPJSON-S-INVALID EXIT THEN
    _CJDI-A @ _CJDI-U @ JSON-OBJECT? 0= IF CAPJSON-S-INVALID EXIT THEN
    _CJDI-SCHEMA @ 0= IF
        _CJDI-A @ _CJDI-U @ _CAPJSON-OBJECT-COUNT
        DUP IF NIP EXIT THEN DROP 0<> IF CAPJSON-S-INVALID EXIT THEN
        _CJDI-VALUE @ CV-NULL! CAPJSON-S-OK EXIT
    THEN
    _CJDI-SCHEMA @ CS.TYPE-MASK @ CV-T-NULL CS-TYPE-BIT = IF
        _CJDI-A @ _CJDI-U @ _CAPJSON-OBJECT-COUNT
        DUP IF NIP EXIT THEN DROP 0<> IF CAPJSON-S-INVALID EXIT THEN
        _CJDI-VALUE @ CV-NULL! CAPJSON-S-OK EXIT
    THEN
    _CJDI-SCHEMA @ CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
        _CJDI-A @ _CJDI-U @ _CJDI-SCHEMA @ _CJDI-VALUE @
        IVJSON-DECODE-AS IF CAPJSON-S-INVALID ELSE CAPJSON-S-OK THEN EXIT
    THEN
    _CJDI-A @ _CJDI-U @ _CAPJSON-OBJECT-COUNT
    DUP IF NIP EXIT THEN DROP 1 <> IF
        CAPJSON-S-INVALID EXIT
    THEN
    _CJDI-A @ _CJDI-U @ S" value" JSON-FIELD
    _CJDI-IOR ! _CJDI-FOUND ! _CJDI-VU ! _CJDI-VA !
    _CJDI-IOR @ _CJDI-FOUND @ 0= OR IF CAPJSON-S-INVALID EXIT THEN
    _CJDI-VA @ _CJDI-VU @ _CJDI-SCHEMA @ _CJDI-VALUE @
    IVJSON-DECODE-AS IF CAPJSON-S-INVALID ELSE CAPJSON-S-OK THEN ;

: CAPJSON-ENCODE-OUTPUT  ( value buffer capacity -- length status )
    IVJSON-ENCODE DUP IF
        DROP CAPJSON-S-INVALID
    ELSE
        DROP CAPJSON-S-OK
    THEN ;
