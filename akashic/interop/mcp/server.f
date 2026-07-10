\ =====================================================================
\  server.f - Bounded catalog-driven native MCP server
\ =====================================================================
\  The server owns MCP lifecycle, validation, pagination, and wire output.
\  Registered callbacks own application behavior. No component, TUI, Desk,
\  provider, network, Python, or emulator dependency enters this module.
\ =====================================================================

PROVIDED akashic-mcp-server-core

REQUIRE protocol.f

64 CONSTANT MCP-SERVER-MAX-TOOLS
64 CONSTANT MCP-SERVER-MAX-RESOURCES
32 CONSTANT MCP-SERVER-MAX-TEMPLATES
16 CONSTANT MCP-SERVER-PAGE-SIZE
16384 CONSTANT MCP-SERVER-RESULT-CAP
8192 CONSTANT MCP-SERVER-VALUE-CAP

-32002 CONSTANT MCP-E-NOT-INITIALIZED

 0 CONSTANT _MS-STATE
 8 CONSTANT _MS-CAPS
16 CONSTANT _MS-NAME-A
24 CONSTANT _MS-NAME-U
32 CONSTANT _MS-TITLE-A
40 CONSTANT _MS-TITLE-U
48 CONSTANT _MS-VERSION-A
56 CONSTANT _MS-VERSION-U
64 CONSTANT _MS-TOOL-N
72 CONSTANT _MS-TOOLS
_MS-TOOLS MCP-SERVER-MAX-TOOLS 8 * + CONSTANT _MS-RESOURCE-N
_MS-RESOURCE-N 8 + CONSTANT _MS-RESOURCES
_MS-RESOURCES MCP-SERVER-MAX-RESOURCES 8 * + CONSTANT _MS-TEMPLATE-N
_MS-TEMPLATE-N 8 + CONSTANT _MS-TEMPLATES
_MS-TEMPLATES MCP-SERVER-MAX-TEMPLATES 8 * + CONSTANT _MS-MESSAGE
_MS-MESSAGE JRPC-MESSAGE-SIZE + CONSTANT _MS-CALL
_MS-CALL MCP-CALL-SIZE + CONSTANT _MS-READ
_MS-READ MCP-READ-SIZE + CONSTANT _MS-RESULT-BUF
_MS-RESULT-BUF MCP-SERVER-RESULT-CAP + CONSTANT _MS-VALUE-BUF
_MS-VALUE-BUF MCP-SERVER-VALUE-CAP + CONSTANT MCP-SERVER-SIZE

: MSERVER.STATE       ( server -- a ) _MS-STATE + ;
: MSERVER.CAPS        ( server -- a ) _MS-CAPS + ;
: MSERVER.NAME-A      ( server -- a ) _MS-NAME-A + ;
: MSERVER.NAME-U      ( server -- a ) _MS-NAME-U + ;
: MSERVER.TITLE-A     ( server -- a ) _MS-TITLE-A + ;
: MSERVER.TITLE-U     ( server -- a ) _MS-TITLE-U + ;
: MSERVER.VERSION-A   ( server -- a ) _MS-VERSION-A + ;
: MSERVER.VERSION-U   ( server -- a ) _MS-VERSION-U + ;
: MSERVER.TOOL-N      ( server -- a ) _MS-TOOL-N + ;
: MSERVER.TOOLS       ( server -- a ) _MS-TOOLS + ;
: MSERVER.RESOURCE-N  ( server -- a ) _MS-RESOURCE-N + ;
: MSERVER.RESOURCES   ( server -- a ) _MS-RESOURCES + ;
: MSERVER.TEMPLATE-N  ( server -- a ) _MS-TEMPLATE-N + ;
: MSERVER.TEMPLATES   ( server -- a ) _MS-TEMPLATES + ;
: MSERVER.MESSAGE     ( server -- message ) _MS-MESSAGE + ;
: MSERVER.CALL        ( server -- call ) _MS-CALL + ;
: MSERVER.READ        ( server -- read ) _MS-READ + ;
: MSERVER.RESULT-BUF  ( server -- buffer ) _MS-RESULT-BUF + ;
: MSERVER.VALUE-BUF   ( server -- buffer ) _MS-VALUE-BUF + ;

VARIABLE _MSN-NA
VARIABLE _MSN-NU
VARIABLE _MSN-VA
VARIABLE _MSN-VU

: MCP-SERVER-NEW  ( name-a name-u version-a version-u -- server ior )
    _MSN-VU ! _MSN-VA ! _MSN-NU ! _MSN-NA !
    _MSN-NU @ 0= _MSN-VU @ 0= OR IF 0 MCP-S-INVALID EXIT THEN
    MCP-SERVER-SIZE ALLOCATE
    DUP IF SWAP DROP 0 SWAP EXIT THEN
    DROP DUP MCP-SERVER-SIZE 0 FILL
    MCP-STATE-NEW OVER MSERVER.STATE !
    _MSN-NA @ OVER MSERVER.NAME-A !
    _MSN-NU @ OVER MSERVER.NAME-U !
    _MSN-VA @ OVER MSERVER.VERSION-A !
    _MSN-VU @ OVER MSERVER.VERSION-U !
    DUP MSERVER.CALL MCP-CALL-INIT
    DUP MSERVER.READ MCP-READ-INIT
    0 ;

: MCP-SERVER-FREE  ( server -- )
    DUP 0= IF DROP EXIT THEN
    DUP MSERVER.CALL MCP-CALL-FREE
    DUP MSERVER.READ MCP-READ-FREE
    FREE ;

VARIABLE _MST-A
VARIABLE _MST-U
VARIABLE _MST-S

: MCP-SERVER-TITLE!  ( title-a title-u server -- )
    _MST-S ! _MST-U ! _MST-A !
    _MST-A @ _MST-S @ MSERVER.TITLE-A !
    _MST-U @ _MST-S @ MSERVER.TITLE-U ! ;

: MCP-SERVER-CATALOG-CLEAR  ( server -- )
    DUP 0 SWAP MSERVER.TOOL-N !
    DUP 0 SWAP MSERVER.RESOURCE-N !
    DUP 0 SWAP MSERVER.TEMPLATE-N !
    0 OVER MSERVER.CAPS !
    DUP MSERVER.TOOLS MCP-SERVER-MAX-TOOLS 8 * 0 FILL
    DUP MSERVER.RESOURCES MCP-SERVER-MAX-RESOURCES 8 * 0 FILL
    MSERVER.TEMPLATES MCP-SERVER-MAX-TEMPLATES 8 * 0 FILL ;

: MCP-SERVER-TOOL-NTH  ( index server -- tool | 0 )
    >R DUP 0< OVER R@ MSERVER.TOOL-N @ >= OR IF
        DROP R> DROP 0 EXIT
    THEN
    8 * R> MSERVER.TOOLS + @ ;

: MCP-SERVER-RESOURCE-NTH  ( index server -- resource | 0 )
    >R DUP 0< OVER R@ MSERVER.RESOURCE-N @ >= OR IF
        DROP R> DROP 0 EXIT
    THEN
    8 * R> MSERVER.RESOURCES + @ ;

: MCP-SERVER-TEMPLATE-NTH  ( index server -- template | 0 )
    >R DUP 0< OVER R@ MSERVER.TEMPLATE-N @ >= OR IF
        DROP R> DROP 0 EXIT
    THEN
    8 * R> MSERVER.TEMPLATES + @ ;

VARIABLE _MSF-A
VARIABLE _MSF-U
VARIABLE _MSF-S

: MCP-SERVER-TOOL-FIND  ( name-a name-u server -- tool | 0 )
    _MSF-S ! _MSF-U ! _MSF-A !
    _MSF-S @ MSERVER.TOOL-N @ 0 ?DO
        I _MSF-S @ MCP-SERVER-TOOL-NTH DUP MCP-TOOL-NAME
        _MSF-A @ _MSF-U @ STR-STR= IF UNLOOP EXIT THEN DROP
    LOOP
    0 ;

: MCP-SERVER-RESOURCE-FIND  ( uri-a uri-u server -- resource | 0 )
    _MSF-S ! _MSF-U ! _MSF-A !
    _MSF-S @ MSERVER.RESOURCE-N @ 0 ?DO
        I _MSF-S @ MCP-SERVER-RESOURCE-NTH DUP MCP-RESOURCE-URI
        _MSF-A @ _MSF-U @ STR-STR= IF UNLOOP EXIT THEN DROP
    LOOP
    0 ;

VARIABLE _MSR-D
VARIABLE _MSR-S

: MCP-SERVER-TOOL+  ( tool server -- status )
    _MSR-S ! _MSR-D !
    _MSR-D @ 0= IF MCP-S-INVALID EXIT THEN
    _MSR-D @ MCP-TOOL-NAME 2DUP MCP-TOOL-NAME-VALID? 0= IF
        2DROP MCP-S-INVALID EXIT
    THEN
    _MSR-S @ MCP-SERVER-TOOL-FIND IF MCP-S-INVALID EXIT THEN
    _MSR-D @ MTOOL.CALL-XT @ 0= IF MCP-S-INVALID EXIT THEN
    _MSR-S @ MSERVER.TOOL-N @ MCP-SERVER-MAX-TOOLS >= IF
        MCP-S-CAPACITY EXIT
    THEN
    _MSR-D @ _MSR-S @ MSERVER.TOOL-N @ 8 * _MSR-S @ MSERVER.TOOLS + !
    1 _MSR-S @ MSERVER.TOOL-N +!
    _MSR-S @ MSERVER.CAPS DUP @ MCP-CAP-TOOLS OR SWAP !
    MCP-S-OK ;

: MCP-SERVER-RESOURCE+  ( resource server -- status )
    _MSR-S ! _MSR-D !
    _MSR-D @ 0= IF MCP-S-INVALID EXIT THEN
    _MSR-D @ MCP-RESOURCE-URI 2DUP MCP-URI-VALID? 0= IF
        2DROP MCP-S-INVALID EXIT
    THEN
    _MSR-S @ MCP-SERVER-RESOURCE-FIND IF MCP-S-INVALID EXIT THEN
    _MSR-D @ MRES.READ-XT @ 0= IF MCP-S-INVALID EXIT THEN
    _MSR-S @ MSERVER.RESOURCE-N @ MCP-SERVER-MAX-RESOURCES >= IF
        MCP-S-CAPACITY EXIT
    THEN
    _MSR-D @ _MSR-S @ MSERVER.RESOURCE-N @ 8 *
    _MSR-S @ MSERVER.RESOURCES + !
    1 _MSR-S @ MSERVER.RESOURCE-N +!
    _MSR-S @ MSERVER.CAPS DUP @ MCP-CAP-RESOURCES OR SWAP !
    MCP-S-OK ;

: MCP-SERVER-TEMPLATE+  ( template server -- status )
    _MSR-S ! _MSR-D !
    _MSR-D @ 0= IF MCP-S-INVALID EXIT THEN
    _MSR-D @ DUP MRT.URI-A @ SWAP MRT.URI-U @ MCP-URI-VALID? 0= IF
        MCP-S-INVALID EXIT
    THEN
    _MSR-S @ MSERVER.TEMPLATE-N @ MCP-SERVER-MAX-TEMPLATES >= IF
        MCP-S-CAPACITY EXIT
    THEN
    _MSR-D @ _MSR-S @ MSERVER.TEMPLATE-N @ 8 *
    _MSR-S @ MSERVER.TEMPLATES + !
    1 _MSR-S @ MSERVER.TEMPLATE-N +!
    _MSR-S @ MSERVER.CAPS DUP @
    MCP-CAP-RESOURCES MCP-CAP-RESOURCE-TEMPLATES OR OR SWAP !
    MCP-S-OK ;

\ =====================================================================
\  Request parsing and response output
\ =====================================================================

VARIABLE _MSH-IN-A
VARIABLE _MSH-IN-U
VARIABLE _MSH-OUT-A
VARIABLE _MSH-OUT-CAP
VARIABLE _MSH-S
VARIABLE _MSH-M
VARIABLE _MSH-RESULT-U

: _MS-RESULT-BEGIN  ( -- )
    JSON-BUILD-RESET
    _MSH-S @ MSERVER.RESULT-BUF MCP-SERVER-RESULT-CAP JSON-SET-OUTPUT ;

: _MS-RESULT-END  ( -- status )
    JSON-OUTPUT-OK? 0= IF MCP-S-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP _MSH-RESULT-U ! MCP-S-OK ;

: _MS-WRAP-RESULT  ( -- output-len status )
    _MSH-M @
    _MSH-S @ MSERVER.RESULT-BUF _MSH-RESULT-U @
    _MSH-OUT-A @ _MSH-OUT-CAP @ JRPC-BUILD-RESULT
    DUP IF DROP DROP 0 MCP-S-CAPACITY ELSE DROP MCP-S-OK THEN ;

VARIABLE _MSE-CODE
VARIABLE _MSE-A
VARIABLE _MSE-U

: _MS-ERROR  ( code message-a message-u -- output-len status )
    _MSE-U ! _MSE-A ! _MSE-CODE !
    _MSH-M @ _MSE-CODE @ _MSE-A @ _MSE-U @ 0 0
    _MSH-OUT-A @ _MSH-OUT-CAP @ JRPC-BUILD-ERROR
    DUP IF DROP DROP 0 MCP-S-CAPACITY ELSE DROP MCP-S-OK THEN ;

: _MS-PARSE-ERROR  ( code -- output-len status )
    DUP JRPC-E-PARSE = IF
        DROP JRPC-E-PARSE S" Parse error"
    ELSE
        DROP JRPC-E-INVALID-REQUEST S" Invalid Request"
    THEN
    0 _MSH-M ! _MS-ERROR ;

VARIABLE _MSPF-M
VARIABLE _MSPF-KA
VARIABLE _MSPF-KU

: _MS-PARAM-FIELD  ( message key-a key-u -- value-a value-u found ior )
    _MSPF-KU ! _MSPF-KA ! _MSPF-M !
    _MSPF-M @ JRPC.PARAMS-U @ 0= IF 0 0 0 0 EXIT THEN
    _MSPF-M @ JRPC.PARAMS-A @ _MSPF-M @ JRPC.PARAMS-U @
    2DUP JSON-OBJECT? 0= IF 2DROP 0 0 0 JRPC-E-INVALID-PARAMS EXIT THEN
    _MSPF-KA @ _MSPF-KU @ JRPC-FIELD ;

CREATE _MS-TEXT-BUF MCP-MAX-URI ALLOT

: _MS-CURSOR  ( message count -- start ior )
    >R
    DUP S" cursor" _MS-PARAM-FIELD
    DUP IF >R DROP 2DROP DROP R> R> DROP 0 SWAP EXIT THEN DROP
    0= IF 2DROP DROP R> DROP 0 0 EXIT THEN
    _MS-TEXT-BUF 32 JRPC-DECODE-STRING
    DUP IF NIP R> DROP 0 JRPC-E-INVALID-PARAMS EXIT THEN DROP
    _MS-TEXT-BUF SWAP STR>NUM 0= IF
        DROP R> DROP 0 JRPC-E-INVALID-PARAMS EXIT
    THEN
    DUP 0< OVER R> > OR IF DROP 0 JRPC-E-INVALID-PARAMS ELSE 0 THEN ;

\ =====================================================================
\  Lifecycle and catalog handlers
\ =====================================================================

: _MS-HANDLE-INITIALIZE  ( -- output-len status )
    _MSH-S @ MSERVER.STATE @ MCP-STATE-NEW <> IF
        JRPC-E-INVALID-REQUEST S" Already initialized" _MS-ERROR EXIT
    THEN
    _MSH-M @ JRPC.PARAMS-U @ 0= IF
        JRPC-E-INVALID-PARAMS S" Missing initialize parameters" _MS-ERROR EXIT
    THEN
    _MSH-M @ S" protocolVersion" _MS-PARAM-FIELD
    DUP IF >R DROP 2DROP DROP R> DROP
        JRPC-E-INVALID-PARAMS S" Invalid protocolVersion" _MS-ERROR EXIT
    THEN DROP 0= IF 2DROP DROP
        JRPC-E-INVALID-PARAMS S" Missing protocolVersion" _MS-ERROR EXIT
    THEN
    _MS-TEXT-BUF 32 JRPC-DECODE-STRING DUP IF
        2DROP JRPC-E-INVALID-PARAMS S" Invalid protocolVersion" _MS-ERROR EXIT
    THEN 2DROP
    _MSH-M @ S" capabilities" _MS-PARAM-FIELD
    DUP IF >R DROP 2DROP DROP R> DROP
        JRPC-E-INVALID-PARAMS S" Invalid capabilities" _MS-ERROR EXIT
    THEN DROP 0= IF 2DROP DROP
        JRPC-E-INVALID-PARAMS S" Missing capabilities" _MS-ERROR EXIT
    THEN
    JSON-OBJECT? 0= IF
        JRPC-E-INVALID-PARAMS S" Invalid capabilities" _MS-ERROR EXIT
    THEN
    _MSH-M @ S" clientInfo" _MS-PARAM-FIELD
    DUP IF >R DROP 2DROP DROP R> DROP
        JRPC-E-INVALID-PARAMS S" Invalid clientInfo" _MS-ERROR EXIT
    THEN DROP 0= IF 2DROP DROP
        JRPC-E-INVALID-PARAMS S" Missing clientInfo" _MS-ERROR EXIT
    THEN
    JSON-OBJECT? 0= IF
        JRPC-E-INVALID-PARAMS S" Invalid clientInfo" _MS-ERROR EXIT
    THEN

    _MS-RESULT-BEGIN
    JSON-{
    S" protocolVersion" MCP-PROTOCOL-VERSION JSON-KV-ESTR
    S" capabilities" JSON-KEY: JSON-{
        _MSH-S @ MSERVER.CAPS @ MCP-CAP-TOOLS AND IF
            S" tools" JSON-KEY: JSON-{ JSON-}
        THEN
        _MSH-S @ MSERVER.CAPS @ MCP-CAP-RESOURCES AND IF
            S" resources" JSON-KEY: JSON-{ JSON-}
        THEN
    JSON-}
    S" serverInfo" JSON-KEY: JSON-{
        S" name" _MSH-S @ DUP MSERVER.NAME-A @ SWAP MSERVER.NAME-U @
        JSON-KV-ESTR
        _MSH-S @ MSERVER.TITLE-U @ IF
            S" title" _MSH-S @ DUP MSERVER.TITLE-A @ SWAP MSERVER.TITLE-U @
            JSON-KV-ESTR
        THEN
        S" version" _MSH-S @ DUP MSERVER.VERSION-A @ SWAP MSERVER.VERSION-U @
        JSON-KV-ESTR
    JSON-}
    JSON-}
    _MS-RESULT-END ?DUP IF 0 SWAP EXIT THEN
    MCP-STATE-INITIALIZING _MSH-S @ MSERVER.STATE !
    _MS-WRAP-RESULT ;

: _MS-HANDLE-PING  ( -- output-len status )
    _MS-RESULT-BEGIN JSON-{ JSON-}
    _MS-RESULT-END ?DUP IF 0 SWAP EXIT THEN
    _MS-WRAP-RESULT ;

VARIABLE _MSL-START
VARIABLE _MSL-END
VARIABLE _MSS-ERROR

: _MS-TOOL-ENTRY  ( tool -- )
    >R
    JSON-{
    S" name" R@ DUP MTOOL.NAME-A @ SWAP MTOOL.NAME-U @ JSON-KV-ESTR
    R@ MTOOL.TITLE-U @ IF
        S" title" R@ DUP MTOOL.TITLE-A @ SWAP MTOOL.TITLE-U @ JSON-KV-ESTR
    THEN
    R@ MTOOL.DESC-U @ IF
        S" description" R@ DUP MTOOL.DESC-A @ SWAP MTOOL.DESC-U @
        JSON-KV-ESTR
    THEN
    S" inputSchema" JSON-KEY: R@ MTOOL.IN-SCHEMA @
    CSJSON-INPUT-WRITE ?DUP IF _MSS-ERROR ! THEN
    R@ MTOOL.OUT-SCHEMA @ ?DUP IF
        S" outputSchema" JSON-KEY: CSJSON-INPUT-WRITE
        ?DUP IF _MSS-ERROR ! THEN
    THEN
    S" annotations" JSON-KEY: JSON-{
        S" readOnlyHint" R@ MTOOL.FLAGS @ MCP-TOOL-F-READ-ONLY AND 0<>
        JSON-KV-BOOL
        S" destructiveHint" R@ MTOOL.FLAGS @ MCP-TOOL-F-DESTRUCTIVE AND 0<>
        JSON-KV-BOOL
        S" idempotentHint" R@ MTOOL.FLAGS @ MCP-TOOL-F-IDEMPOTENT AND 0<>
        JSON-KV-BOOL
        S" openWorldHint" R> MTOOL.FLAGS @ MCP-TOOL-F-OPEN-WORLD AND 0<>
        JSON-KV-BOOL
    JSON-}
    JSON-} ;

: _MS-HANDLE-TOOLS-LIST  ( -- output-len status )
    _MSH-M @ _MSH-S @ MSERVER.TOOL-N @ _MS-CURSOR
    DUP IF NIP JRPC-E-INVALID-PARAMS S" Invalid cursor" _MS-ERROR EXIT THEN DROP
    DUP _MSL-START ! MCP-SERVER-PAGE-SIZE +
    _MSH-S @ MSERVER.TOOL-N @ MIN _MSL-END !
    0 _MSS-ERROR !
    _MS-RESULT-BEGIN JSON-{
    S" tools" JSON-KEY: JSON-[
    _MSL-END @ _MSL-START @ ?DO
        I _MSH-S @ MCP-SERVER-TOOL-NTH _MS-TOOL-ENTRY
        _MSS-ERROR @ IF LEAVE THEN
    LOOP
    JSON-]
    _MSL-END @ _MSH-S @ MSERVER.TOOL-N @ < IF
        S" nextCursor" _MSL-END @ NUM>STR JSON-KV-ESTR
    THEN
    JSON-}
    _MSS-ERROR @ IF
        0 MCP-S-FAILED EXIT
    THEN
    _MS-RESULT-END ?DUP IF 0 SWAP EXIT THEN _MS-WRAP-RESULT ;

VARIABLE _MSC-TOOL
VARIABLE _MSC-STATUS
VARIABLE _MSC-VALUE-U
VARIABLE _MSC-VALUE-IOR

: _MS-CALL-XT  ( -- )
    _MSH-S @ MSERVER.CALL _MSC-TOOL @ MTOOL.CONTEXT @
    _MSC-TOOL @ MTOOL.CALL-XT @ EXECUTE _MSC-STATUS ! ;

: _MS-STATUS-TEXT  ( status -- addr len )
    CASE
        MCP-S-INVALID OF S" Invalid tool arguments" ENDOF
        MCP-S-NOT-FOUND OF S" Tool target not found" ENDOF
        MCP-S-DENIED OF S" Tool call denied" ENDOF
        MCP-S-APPROVAL OF S" Tool call requires approval" ENDOF
        MCP-S-BUSY OF S" Tool target is busy" ENDOF
        MCP-S-TIMEOUT OF S" Tool call timed out" ENDOF
        MCP-S-CANCELLED OF S" Tool call cancelled" ENDOF
        S" Tool call failed" ROT DROP
    ENDCASE ;

: _MS-TOOL-RESULT  ( status -- output-len status )
    _MSC-STATUS !
    0 _MSC-VALUE-U ! 0 _MSC-VALUE-IOR !
    _MSC-STATUS @ MCP-S-OK = IF
        _MSH-S @ MSERVER.CALL MCALL.RESULT
        _MSH-S @ MSERVER.VALUE-BUF MCP-SERVER-VALUE-CAP IVJSON-ENCODE
        _MSC-VALUE-IOR ! _MSC-VALUE-U !
        _MSC-VALUE-IOR @ IF
            S" Result encoding failed" _MSH-S @ MSERVER.CALL MCP-CALL-ERROR!
            MCP-S-FAILED _MSC-STATUS !
        THEN
    THEN
    _MS-RESULT-BEGIN JSON-{
    S" content" JSON-KEY: JSON-[ JSON-{
        S" type" S" text" JSON-KV-ESTR
        S" text" JSON-KEY:
        _MSC-STATUS @ MCP-S-OK = IF
            _MSH-S @ MSERVER.CALL MCALL.RESULT DUP CV-TYPE@
            DUP CV-T-STRING = SWAP CV-T-RESOURCE = OR IF
                DUP CV-DATA@ SWAP CV-LEN@ JSON-ESTR
            ELSE
                DROP _MSH-S @ MSERVER.VALUE-BUF _MSC-VALUE-U @ JSON-ESTR
            THEN
        ELSE
            _MSH-S @ MSERVER.CALL DUP MCALL.ERROR-U @ IF
                DUP MCALL.ERROR-A @ SWAP MCALL.ERROR-U @
            ELSE
                DROP _MSC-STATUS @ _MS-STATUS-TEXT
            THEN
            JSON-ESTR
        THEN
    JSON-} JSON-]
    _MSC-STATUS @ MCP-S-OK = IF
        S" structuredContent" JSON-KEY:
        _MSH-S @ MSERVER.CALL MCALL.RESULT CV-TYPE@ CV-T-MAP = IF
            _MSH-S @ MSERVER.VALUE-BUF _MSC-VALUE-U @ JSON-RAW
        ELSE
            JSON-{
            S" value" _MSH-S @ MSERVER.VALUE-BUF _MSC-VALUE-U @
            JSON-KV-RAW
            JSON-}
        THEN
    THEN
    S" isError" _MSC-STATUS @ MCP-S-OK <> JSON-KV-BOOL
    JSON-}
    _MS-RESULT-END ?DUP IF 0 SWAP EXIT THEN _MS-WRAP-RESULT ;

: _MS-HANDLE-TOOLS-CALL  ( -- output-len status )
    _MSH-M @ S" name" _MS-PARAM-FIELD
    DUP IF >R DROP 2DROP DROP R> DROP
        JRPC-E-INVALID-PARAMS S" Invalid tool name" _MS-ERROR EXIT
    THEN DROP 0= IF 2DROP DROP
        JRPC-E-INVALID-PARAMS S" Missing tool name" _MS-ERROR EXIT
    THEN
    _MS-TEXT-BUF MCP-MAX-NAME JRPC-DECODE-STRING
    DUP IF 2DROP JRPC-E-INVALID-PARAMS S" Invalid tool name" _MS-ERROR EXIT THEN
    DROP _MS-TEXT-BUF SWAP _MSH-S @ MCP-SERVER-TOOL-FIND DUP 0= IF
        DROP JRPC-E-INVALID-PARAMS S" Unknown tool" _MS-ERROR EXIT
    THEN _MSC-TOOL !
    _MSH-S @ MSERVER.CALL DUP MCP-CALL-FREE MCP-CALL-INIT
    _MSH-M @ S" arguments" _MS-PARAM-FIELD
    DUP IF >R DROP 2DROP DROP R> DROP
        JRPC-E-INVALID-PARAMS S" Invalid tool arguments" _MS-ERROR EXIT
    THEN DROP
    IF
        2DUP JSON-OBJECT? 0= IF 2DROP
            JRPC-E-INVALID-PARAMS S" Tool arguments must be an object"
            _MS-ERROR EXIT
        THEN
    ELSE
        2DROP S" {}"
    THEN
    _MSH-S @ MSERVER.CALL DUP >R MCALL.ARGS-U ! R> MCALL.ARGS-A !
    MCP-S-FAILED _MSC-STATUS !
    ['] _MS-CALL-XT CATCH IF MCP-S-FAILED _MSC-STATUS ! THEN
    _MSC-STATUS @ _MS-TOOL-RESULT ;

: _MS-RESOURCE-ENTRY  ( resource -- )
    >R JSON-{
    S" uri" R@ DUP MRES.URI-A @ SWAP MRES.URI-U @ JSON-KV-ESTR
    S" name" R@ DUP MRES.NAME-A @ SWAP MRES.NAME-U @ JSON-KV-ESTR
    R@ MRES.TITLE-U @ IF
        S" title" R@ DUP MRES.TITLE-A @ SWAP MRES.TITLE-U @ JSON-KV-ESTR
    THEN
    R@ MRES.DESC-U @ IF
        S" description" R@ DUP MRES.DESC-A @ SWAP MRES.DESC-U @ JSON-KV-ESTR
    THEN
    R@ MRES.MIME-U @ IF
        S" mimeType" R@ DUP MRES.MIME-A @ SWAP MRES.MIME-U @ JSON-KV-ESTR
    THEN
    R> DROP JSON-} ;

: _MS-HANDLE-RESOURCES-LIST  ( -- output-len status )
    _MSH-M @ _MSH-S @ MSERVER.RESOURCE-N @ _MS-CURSOR
    DUP IF NIP JRPC-E-INVALID-PARAMS S" Invalid cursor" _MS-ERROR EXIT THEN DROP
    DUP _MSL-START ! MCP-SERVER-PAGE-SIZE +
    _MSH-S @ MSERVER.RESOURCE-N @ MIN _MSL-END !
    _MS-RESULT-BEGIN JSON-{ S" resources" JSON-KEY: JSON-[
    _MSL-END @ _MSL-START @ ?DO
        I _MSH-S @ MCP-SERVER-RESOURCE-NTH _MS-RESOURCE-ENTRY
    LOOP
    JSON-]
    _MSL-END @ _MSH-S @ MSERVER.RESOURCE-N @ < IF
        S" nextCursor" _MSL-END @ NUM>STR JSON-KV-ESTR
    THEN
    JSON-}
    _MS-RESULT-END ?DUP IF 0 SWAP EXIT THEN _MS-WRAP-RESULT ;

: _MS-TEMPLATE-ENTRY  ( template -- )
    >R JSON-{
    S" uriTemplate" R@ DUP MRT.URI-A @ SWAP MRT.URI-U @ JSON-KV-ESTR
    S" name" R@ DUP MRT.NAME-A @ SWAP MRT.NAME-U @ JSON-KV-ESTR
    R@ MRT.TITLE-U @ IF
        S" title" R@ DUP MRT.TITLE-A @ SWAP MRT.TITLE-U @ JSON-KV-ESTR
    THEN
    R@ MRT.DESC-U @ IF
        S" description" R@ DUP MRT.DESC-A @ SWAP MRT.DESC-U @ JSON-KV-ESTR
    THEN
    R@ MRT.MIME-U @ IF
        S" mimeType" R@ DUP MRT.MIME-A @ SWAP MRT.MIME-U @ JSON-KV-ESTR
    THEN
    R> DROP JSON-} ;

: _MS-HANDLE-TEMPLATES-LIST  ( -- output-len status )
    _MSH-M @ _MSH-S @ MSERVER.TEMPLATE-N @ _MS-CURSOR
    DUP IF NIP JRPC-E-INVALID-PARAMS S" Invalid cursor" _MS-ERROR EXIT THEN DROP
    DUP _MSL-START ! MCP-SERVER-PAGE-SIZE +
    _MSH-S @ MSERVER.TEMPLATE-N @ MIN _MSL-END !
    _MS-RESULT-BEGIN JSON-{ S" resourceTemplates" JSON-KEY: JSON-[
    _MSL-END @ _MSL-START @ ?DO
        I _MSH-S @ MCP-SERVER-TEMPLATE-NTH _MS-TEMPLATE-ENTRY
    LOOP
    JSON-]
    _MSL-END @ _MSH-S @ MSERVER.TEMPLATE-N @ < IF
        S" nextCursor" _MSL-END @ NUM>STR JSON-KV-ESTR
    THEN
    JSON-}
    _MS-RESULT-END ?DUP IF 0 SWAP EXIT THEN _MS-WRAP-RESULT ;

VARIABLE _MSRR-RES
VARIABLE _MSRR-STATUS

: _MS-READ-XT  ( -- )
    _MSH-S @ MSERVER.READ _MSRR-RES @ MRES.CONTEXT @
    _MSRR-RES @ MRES.READ-XT @ EXECUTE _MSRR-STATUS ! ;

: _MS-HANDLE-RESOURCES-READ  ( -- output-len status )
    _MSH-M @ S" uri" _MS-PARAM-FIELD
    DUP IF >R DROP 2DROP DROP R> DROP
        JRPC-E-INVALID-PARAMS S" Invalid resource URI" _MS-ERROR EXIT
    THEN DROP 0= IF 2DROP DROP
        JRPC-E-INVALID-PARAMS S" Missing resource URI" _MS-ERROR EXIT
    THEN
    _MS-TEXT-BUF MCP-MAX-URI JRPC-DECODE-STRING
    DUP IF 2DROP JRPC-E-INVALID-PARAMS S" Invalid resource URI" _MS-ERROR EXIT THEN
    DROP _MS-TEXT-BUF SWAP _MSH-S @ MCP-SERVER-RESOURCE-FIND DUP 0= IF
        DROP JRPC-E-INVALID-PARAMS S" Unknown resource" _MS-ERROR EXIT
    THEN _MSRR-RES !
    _MSH-S @ MSERVER.READ DUP MCP-READ-FREE MCP-READ-INIT
    _MSRR-RES @ DUP MRES.URI-A @ SWAP MRES.URI-U @
    _MSH-S @ MSERVER.READ DUP >R MREAD.URI-U ! R> MREAD.URI-A !
    _MSRR-RES @ DUP MRES.MIME-A @ SWAP MRES.MIME-U @
    _MSH-S @ MSERVER.READ DUP >R MREAD.MIME-U ! R> MREAD.MIME-A !
    MCP-S-FAILED _MSRR-STATUS !
    ['] _MS-READ-XT CATCH IF MCP-S-FAILED _MSRR-STATUS ! THEN
    _MSRR-STATUS @ MCP-S-OK <> IF
        JRPC-E-INVALID-PARAMS
        _MSH-S @ MSERVER.READ DUP MREAD.ERROR-U @ IF
            DUP MREAD.ERROR-A @ SWAP MREAD.ERROR-U @
        ELSE
            DROP S" Resource read failed"
        THEN
        _MS-ERROR EXIT
    THEN
    _MSH-S @ MSERVER.READ MREAD.CONTENT
    DUP CV-TYPE@ DUP CV-T-STRING = SWAP CV-T-RESOURCE = OR IF
        DUP CV-DATA@ SWAP CV-LEN@
        _MSH-RESULT-U ! _MSH-IN-A !
    ELSE
        _MSH-S @ MSERVER.VALUE-BUF MCP-SERVER-VALUE-CAP IVJSON-ENCODE
        DUP IF 2DROP JRPC-E-INTERNAL S" Resource encoding failed" _MS-ERROR EXIT THEN
        DROP _MSH-RESULT-U !
        _MSH-S @ MSERVER.VALUE-BUF _MSH-IN-A !
    THEN
    _MS-RESULT-BEGIN JSON-{ S" contents" JSON-KEY: JSON-[ JSON-{
        S" uri" _MSRR-RES @ DUP MRES.URI-A @ SWAP MRES.URI-U @ JSON-KV-ESTR
        _MSRR-RES @ MRES.MIME-U @ IF
            S" mimeType" _MSRR-RES @ DUP MRES.MIME-A @ SWAP MRES.MIME-U @
            JSON-KV-ESTR
        ELSE
            S" mimeType" S" text/plain" JSON-KV-ESTR
        THEN
        S" text" _MSH-IN-A @ _MSH-RESULT-U @ JSON-KV-ESTR
    JSON-} JSON-] JSON-}
    _MS-RESULT-END ?DUP IF 0 SWAP EXIT THEN _MS-WRAP-RESULT ;

\ =====================================================================
\  Public dispatch
\ =====================================================================

: _MS-HANDLE-NOTIFICATION  ( -- output-len status )
    _MSH-M @ S" notifications/initialized" MCP-METHOD? IF
        _MSH-S @ MSERVER.STATE @ MCP-STATE-INITIALIZING = IF
            MCP-STATE-READY _MSH-S @ MSERVER.STATE !
        THEN
        0 MCP-S-OK EXIT
    THEN
    \ No asynchronous operation is retained by this core server, so valid
    \ cancellation notifications are intentionally safe no-ops.
    _MSH-M @ S" notifications/cancelled" MCP-METHOD? IF 0 MCP-S-OK EXIT THEN
    0 MCP-S-OK ;

: _MS-HANDLE-REQUEST  ( -- output-len status )
    _MSH-M @ S" initialize" MCP-METHOD? IF _MS-HANDLE-INITIALIZE EXIT THEN
    _MSH-M @ S" ping" MCP-METHOD? IF _MS-HANDLE-PING EXIT THEN
    _MSH-S @ MSERVER.STATE @ MCP-STATE-READY <> IF
        MCP-E-NOT-INITIALIZED S" Server not initialized" _MS-ERROR EXIT
    THEN
    _MSH-M @ S" tools/list" MCP-METHOD? IF _MS-HANDLE-TOOLS-LIST EXIT THEN
    _MSH-M @ S" tools/call" MCP-METHOD? IF _MS-HANDLE-TOOLS-CALL EXIT THEN
    _MSH-M @ S" resources/list" MCP-METHOD? IF
        _MS-HANDLE-RESOURCES-LIST EXIT
    THEN
    _MSH-M @ S" resources/templates/list" MCP-METHOD? IF
        _MS-HANDLE-TEMPLATES-LIST EXIT
    THEN
    _MSH-M @ S" resources/read" MCP-METHOD? IF
        _MS-HANDLE-RESOURCES-READ EXIT
    THEN
    JRPC-E-METHOD-NOT-FOUND S" Method not found" _MS-ERROR ;

: MCP-SERVER-HANDLE  ( input-a input-u output-a output-cap server -- output-u status )
    _MSH-S ! _MSH-OUT-CAP ! _MSH-OUT-A ! _MSH-IN-U ! _MSH-IN-A !
    _MSH-S @ MSERVER.MESSAGE DUP _MSH-M !
    _MSH-IN-A @ _MSH-IN-U @ ROT JRPC-PARSE ?DUP IF _MS-PARSE-ERROR EXIT THEN
    _MSH-M @ JRPC.KIND @ CASE
        JRPC-K-NOTIFICATION OF _MS-HANDLE-NOTIFICATION ENDOF
        JRPC-K-REQUEST OF _MS-HANDLE-REQUEST ENDOF
        JRPC-E-INVALID-REQUEST S" Invalid Request" _MS-ERROR ROT DROP
    ENDCASE ;
