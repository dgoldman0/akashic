\ =====================================================================
\  provider.f - Replaceable provider port for agent runtimes
\ =====================================================================

PROVIDED akashic-agent-provider

REQUIRE event.f
REQUIRE turn-request.f
REQUIRE provider-auth.f

1  CONSTANT APROV-F-STREAMING
2  CONSTANT APROV-F-TOOLS
4  CONSTANT APROV-F-APPROVALS
8  CONSTANT APROV-F-CANCEL
16 CONSTANT APROV-F-CONTEXT
32 CONSTANT APROV-F-AUTH

0 CONSTANT APROV-S-OFFLINE
1 CONSTANT APROV-S-CONNECTING
2 CONSTANT APROV-S-READY
3 CONSTANT APROV-S-ERROR

 0 CONSTANT _AP-ID-A
 8 CONSTANT _AP-ID-U
16 CONSTANT _AP-FEATURES
24 CONSTANT _AP-CONTEXT
32 CONSTANT _AP-CONNECT-XT       \ ( event-queue context -- ior )
40 CONSTANT _AP-DISCONNECT-XT    \ ( event-queue context -- )
48 CONSTANT _AP-START-XT         \ ( turn queue context -- ior )
56 CONSTANT _AP-CANCEL-XT        \ ( run-id queue context -- ior )
64 CONSTANT _AP-POLL-XT          \ ( queue context -- ior )
72 CONSTANT _AP-RESOLVE-XT       \ ( approved run-id queue context -- ior )
80 CONSTANT _AP-TOOL-RESULT-XT   \ ( run-id name-a name-u value status queue context -- ior )
88 CONSTANT _AP-STATE
96 CONSTANT _AP-FLAGS
104 CONSTANT _AP-BIND-TOOLS-XT   \ ( gateway context -- ior )
112 CONSTANT _AP-AUTH            \ borrowed provider-auth port
120 CONSTANT _AP-FREE-XT         \ ( provider -- )
128 CONSTANT AGENT-PROVIDER-SIZE

: APROV.ID-A           ( provider -- a ) _AP-ID-A + ;
: APROV.ID-U           ( provider -- a ) _AP-ID-U + ;
: APROV.FEATURES       ( provider -- a ) _AP-FEATURES + ;
: APROV.CONTEXT        ( provider -- a ) _AP-CONTEXT + ;
: APROV.CONNECT-XT     ( provider -- a ) _AP-CONNECT-XT + ;
: APROV.DISCONNECT-XT  ( provider -- a ) _AP-DISCONNECT-XT + ;
: APROV.START-XT       ( provider -- a ) _AP-START-XT + ;
: APROV.CANCEL-XT      ( provider -- a ) _AP-CANCEL-XT + ;
: APROV.POLL-XT        ( provider -- a ) _AP-POLL-XT + ;
: APROV.RESOLVE-XT     ( provider -- a ) _AP-RESOLVE-XT + ;
: APROV.TOOL-RESULT-XT ( provider -- a ) _AP-TOOL-RESULT-XT + ;
: APROV.STATE          ( provider -- a ) _AP-STATE + ;
: APROV.FLAGS          ( provider -- a ) _AP-FLAGS + ;
: APROV.BIND-TOOLS-XT  ( provider -- a ) _AP-BIND-TOOLS-XT + ;
: APROV.AUTH           ( provider -- a ) _AP-AUTH + ;
: APROV.FREE-XT        ( provider -- a ) _AP-FREE-XT + ;

: APROV-INIT  ( provider -- ) AGENT-PROVIDER-SIZE 0 FILL ;

: APROV-CONNECT  ( queue provider -- ior )
    DUP APROV.CONNECT-XT @ ?DUP 0= IF 2DROP -1 EXIT THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-DISCONNECT  ( queue provider -- )
    DUP APROV.DISCONNECT-XT @ ?DUP 0= IF 2DROP EXIT THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-START  ( turn queue provider -- ior )
    DUP APROV.START-XT @ ?DUP 0= IF DROP 2DROP -1 EXIT THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-CANCEL  ( run-id queue provider -- ior )
    DUP APROV.CANCEL-XT @ ?DUP 0= IF 2DROP DROP -1 EXIT THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-POLL  ( queue provider -- ior )
    DUP APROV.POLL-XT @ ?DUP 0= IF 2DROP 0 EXIT THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-RESOLVE  ( approved run-id queue provider -- ior )
    DUP APROV.RESOLVE-XT @ ?DUP 0= IF 2DROP 2DROP -1 EXIT THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-TOOL-RESULT  ( run-id name-a name-u value status queue provider -- ior )
    DUP APROV.TOOL-RESULT-XT @ ?DUP 0= IF
        DROP 2DROP 2DROP 2DROP -1 EXIT
    THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-BIND-TOOLS  ( gateway provider -- ior )
    DUP APROV.BIND-TOOLS-XT @ ?DUP 0= IF 2DROP 0 EXIT THEN
    >R APROV.CONTEXT @ R> EXECUTE ;

: APROV-AUTH  ( provider -- auth | 0 ) APROV.AUTH @ ;

: APROV-FREE  ( provider -- )
    DUP 0= IF DROP EXIT THEN
    DUP APROV.FREE-XT @ ?DUP IF EXECUTE ELSE DROP THEN ;
