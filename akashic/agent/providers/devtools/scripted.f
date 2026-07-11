\ =====================================================================
\  scripted.f - Deterministic streaming provider for tests and demos
\ =====================================================================

PROVIDED akashic-agent-scripted-provider

REQUIRE ../../provider-source.f
REQUIRE ../../../utils/string.f

0 CONSTANT _SP-IDLE
1 CONSTANT _SP-STREAMING
2 CONSTANT _SP-WAITING

 0 CONSTANT _SP-STATE
 8 CONSTANT _SP-STEP
16 CONSTANT _SP-RUN-ID
24 CONSTANT _SP-PROMPT-A
32 CONSTANT _SP-PROMPT-U
40 CONSTANT _SP-SEQUENCE
48 CONSTANT _SP-PROVIDER
56 CONSTANT _SP-TURN-CONTEXT-N
64 CONSTANT _SP-EVENT
_SP-EVENT AGENT-EVENT-SIZE + CONSTANT SCRIPTED-PROVIDER-CONTEXT-SIZE

: _SPC.STATE      ( context -- a ) _SP-STATE + ;
: _SPC.STEP       ( context -- a ) _SP-STEP + ;
: _SPC.RUN-ID     ( context -- a ) _SP-RUN-ID + ;
: _SPC.PROMPT-A   ( context -- a ) _SP-PROMPT-A + ;
: _SPC.PROMPT-U   ( context -- a ) _SP-PROMPT-U + ;
: _SPC.SEQUENCE   ( context -- a ) _SP-SEQUENCE + ;
: _SPC.PROVIDER   ( context -- a ) _SP-PROVIDER + ;
: _SPC.TURN-CONTEXT-N ( context -- a ) _SP-TURN-CONTEXT-N + ;
: _SPC.EVENT      ( context -- event ) _SP-EVENT + ;

: SCRIPTED-LAST-CONTEXT-N  ( provider -- count )
    APROV.CONTEXT @ _SPC.TURN-CONTEXT-N @ ;

VARIABLE _SPE-KIND
VARIABLE _SPE-NA
VARIABLE _SPE-NU
VARIABLE _SPE-DA
VARIABLE _SPE-DU
VARIABLE _SPE-Q
VARIABLE _SPE-C
VARIABLE _SPP-Q
VARIABLE _SPP-C

: _SCRIPTED-EMIT  ( kind name-a name-u data-a data-u queue context -- ior )
    _SPE-C ! _SPE-Q ! _SPE-DU ! _SPE-DA !
    _SPE-NU ! _SPE-NA ! _SPE-KIND !
    _SPE-C @ _SPC.EVENT AEV-FREE
    _SPE-KIND @ _SPE-C @ _SPC.EVENT AEV.KIND !
    _SPE-C @ _SPC.RUN-ID @ _SPE-C @ _SPC.EVENT AEV.RUN-ID !
    _SPE-C @ _SPC.SEQUENCE @ _SPE-C @ _SPC.EVENT AEV.SEQUENCE !
    1 _SPE-C @ _SPC.SEQUENCE +!
    _SPE-NU @ IF
        _SPE-NA @ _SPE-NU @ _SPE-C @ _SPC.EVENT AEV.NAME CV-STRING!
        IF _SPE-C @ _SPC.EVENT AEV-FREE 1 EXIT THEN
    THEN
    _SPE-DU @ IF
        _SPE-DA @ _SPE-DU @ _SPE-C @ _SPC.EVENT AEV.DATA CV-STRING!
        IF _SPE-C @ _SPC.EVENT AEV-FREE 1 EXIT THEN
    THEN
    _SPE-KIND @ AEV-TOOL-CALL = IF
        S" scripted.call" _SPE-C @ _SPC.EVENT AEV.CALL-ID CV-STRING!
        IF _SPE-C @ _SPC.EVENT AEV-FREE 1 EXIT THEN
    THEN
    _SPE-C @ _SPC.EVENT _SPE-Q @ AEQ-POST ;

: _SCRIPTED-CONNECT  ( queue context -- ior )
    _SPP-C ! _SPP-Q !
    APROV-S-READY _SPP-C @ _SPC.PROVIDER @ APROV.STATE !
    AEV-CONNECTED 0 0 S" Deterministic provider ready"
    _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT ;

: _SCRIPTED-DISCONNECT  ( queue context -- )
    _SPP-C ! _SPP-Q !
    APROV-S-OFFLINE _SPP-C @ _SPC.PROVIDER @ APROV.STATE !
    AEV-DISCONNECTED 0 0 S" Provider disconnected"
    _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT DROP ;

VARIABLE _SPS-A
VARIABLE _SPS-U
VARIABLE _SPS-T
VARIABLE _SPS-Q
VARIABLE _SPS-C

: _SCRIPTED-START  ( turn queue context -- ior )
    _SPS-C ! _SPS-Q ! _SPS-T !
    _SPS-C @ _SPC.STATE @ _SP-IDLE <> IF 1 EXIT THEN
    _SPS-T @ ATURN-VALID? 0= IF 1 EXIT THEN
    _SPS-T @ ATURN-PROMPT _SPS-U ! _SPS-A !
    _SPS-C @ _SPC.PROMPT-A @ ?DUP IF FREE THEN
    _SPS-U @ ALLOCATE DUP IF SWAP DROP EXIT THEN
    DROP DUP _SPS-C @ _SPC.PROMPT-A !
    _SPS-A @ SWAP _SPS-U @ CMOVE
    _SPS-U @ _SPS-C @ _SPC.PROMPT-U !
    _SPS-T @ ATURN.RUN-ID @ _SPS-C @ _SPC.RUN-ID !
    _SPS-T @ ATURN.CONTEXT-N @ _SPS-C @ _SPC.TURN-CONTEXT-N !
    1 _SPS-C @ _SPC.SEQUENCE !
    0 _SPS-C @ _SPC.STEP !
    _SP-STREAMING _SPS-C @ _SPC.STATE !
    AEV-RUN-STARTED 0 0 0 0 _SPS-Q @ _SPS-C @ _SCRIPTED-EMIT ;

: _SCRIPTED-CANCEL  ( run-id queue context -- ior )
    _SPP-C ! _SPP-Q !
    _SPP-C @ _SPC.RUN-ID @ <> IF 1 EXIT THEN
    _SP-IDLE _SPP-C @ _SPC.STATE !
    AEV-CANCELLED 0 0 S" Run cancelled" _SPP-Q @ _SPP-C @
    _SCRIPTED-EMIT ;

: _SCRIPTED-FINISH-MESSAGE  ( queue context -- ior )
    _SPP-C ! _SPP-Q !
    AEV-MESSAGE-DONE 0 0 0 0 _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT
    ?DUP IF EXIT THEN
    AEV-RUN-DONE 0 0 0 0 _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT ;

: _SCRIPTED-POLL  ( queue context -- ior )
    _SPP-C ! _SPP-Q !
    _SPP-C @ _SPC.STATE @ _SP-STREAMING <> IF 0 EXIT THEN
    _SPP-C @ _SPC.STEP @ CASE
        0 OF
            AEV-TEXT-DELTA 0 0
            S" Connected through Akashic's provider-neutral runtime. "
            _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT
        ENDOF
        1 OF
            AEV-TEXT-DELTA 0 0 S" You asked: "
            _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT
        ENDOF
        2 OF
            AEV-TEXT-DELTA 0 0
            _SPP-C @ _SPC.PROMPT-A @ _SPP-C @ _SPC.PROMPT-U @
            _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT
        ENDOF
        3 OF
            _SPP-C @ _SPC.PROMPT-A @ _SPP-C @ _SPC.PROMPT-U @
            S" task" STR-STRI-CONTAINS IF
                _SP-WAITING _SPP-C @ _SPC.STATE !
                AEV-TOOL-CALL S" daybook.task.capture"
                _SPP-C @ _SPC.PROMPT-A @ _SPP-C @ _SPC.PROMPT-U @
                _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT
            ELSE
            _SPP-C @ _SPC.PROMPT-A @ _SPP-C @ _SPC.PROMPT-U @
            S" approval" STR-STRI-CONTAINS IF
                _SP-WAITING _SPP-C @ _SPC.STATE !
                AEV-APPROVAL S" simulated.persist"
                S" Persist the simulated change?"
                _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT
            ELSE
                _SPP-Q @ _SPP-C @ _SCRIPTED-FINISH-MESSAGE
                _SP-IDLE _SPP-C @ _SPC.STATE !
            THEN
            THEN
        ENDOF
        0
    ENDCASE
    DUP 0= IF 1 _SPP-C @ _SPC.STEP +! THEN ;

VARIABLE _SPR-APPROVED
VARIABLE _SPR-RUN

: _SCRIPTED-RESOLVE  ( approved run-id queue context -- ior )
    _SPP-C ! _SPP-Q ! _SPR-RUN ! _SPR-APPROVED !
    _SPR-RUN @ _SPP-C @ _SPC.RUN-ID @ <> IF 1 EXIT THEN
    _SPP-C @ _SPC.STATE @ _SP-WAITING <> IF 1 EXIT THEN
    _SPR-APPROVED @ IF
        AEV-TEXT-DELTA 0 0 S"  Approved."
    ELSE
        AEV-TEXT-DELTA 0 0 S"  Denied."
    THEN
    _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT ?DUP IF EXIT THEN
    _SPP-Q @ _SPP-C @ _SCRIPTED-FINISH-MESSAGE
    _SP-IDLE _SPP-C @ _SPC.STATE ! ;

VARIABLE _SPT-STATUS

: _SCRIPTED-TOOL-ERROR-TEXT  ( status -- addr len )
    CASE
        1 OF S" Tool input was invalid." ENDOF
        2 OF S" Tool capability was unavailable." ENDOF
        3 OF S" Tool target was closed." ENDOF
        4 OF S" Tool target state changed." ENDOF
        5 OF S" Tool request was denied." ENDOF
        6 OF S" Tool approval was not resolved." ENDOF
        7 OF S" Tool request queue was busy." ENDOF
        8 OF S" Tool request timed out." ENDOF
        9 OF S" Tool request was cancelled." ENDOF
        10 OF S" Tool handler failed." ENDOF
        11 OF S" Tool handler was not installed." ENDOF
        DROP S" Tool request was not completed."
    ENDCASE ;

: _SCRIPTED-TOOL-RESULT  ( run-id name-a name-u value status queue context -- ior )
    _SPP-C ! _SPP-Q ! _SPT-STATUS ! DROP 2DROP
    _SPP-C @ _SPC.RUN-ID @ <> IF 1 EXIT THEN
    _SPP-C @ _SPC.STATE @ _SP-WAITING <> IF 1 EXIT THEN
    _SPT-STATUS @ 0= IF
        AEV-TOOL-RESULT 0 0 S" Daybook task captured."
    ELSE
        AEV-TOOL-RESULT 0 0 _SPT-STATUS @ _SCRIPTED-TOOL-ERROR-TEXT
    THEN
    _SPP-Q @ _SPP-C @ _SCRIPTED-EMIT ?DUP IF EXIT THEN
    _SPP-Q @ _SPP-C @ _SCRIPTED-FINISH-MESSAGE
    _SP-IDLE _SPP-C @ _SPC.STATE ! ;

VARIABLE _SPN-P
VARIABLE _SPN-C

: SCRIPTED-PROVIDER-FREE  ( provider -- )
    DUP 0= IF DROP EXIT THEN
    DUP APROV.CONTEXT @ ?DUP IF
        DUP _SPC.PROMPT-A @ ?DUP IF FREE THEN
        DUP _SPC.EVENT AEV-FREE
        FREE
    THEN
    FREE ;

: SCRIPTED-PROVIDER-NEW  ( -- provider ior )
    0 _SPN-P ! 0 _SPN-C !
    AGENT-PROVIDER-SIZE ALLOCATE
    DUP IF SWAP DROP 0 SWAP EXIT THEN
    DROP DUP _SPN-P ! APROV-INIT
    SCRIPTED-PROVIDER-CONTEXT-SIZE ALLOCATE
    DUP IF SWAP DROP _SPN-P @ FREE 0 SWAP EXIT THEN
    DROP DUP _SPN-C ! SCRIPTED-PROVIDER-CONTEXT-SIZE 0 FILL
    _SPN-P @ _SPN-C @ _SPC.PROVIDER !
    _SPN-C @ _SPN-P @ APROV.CONTEXT !
    S" org.akashic.agent.testing.scripted"
    _SPN-P @ APROV.ID-U ! _SPN-P @ APROV.ID-A !
    APROV-F-STREAMING APROV-F-CANCEL OR APROV-F-APPROVALS OR
    APROV-F-TOOLS OR APROV-F-CONTEXT OR
    _SPN-P @ APROV.FEATURES !
    ['] _SCRIPTED-CONNECT _SPN-P @ APROV.CONNECT-XT !
    ['] _SCRIPTED-DISCONNECT _SPN-P @ APROV.DISCONNECT-XT !
    ['] _SCRIPTED-START _SPN-P @ APROV.START-XT !
    ['] _SCRIPTED-CANCEL _SPN-P @ APROV.CANCEL-XT !
    ['] _SCRIPTED-POLL _SPN-P @ APROV.POLL-XT !
    ['] _SCRIPTED-RESOLVE _SPN-P @ APROV.RESOLVE-XT !
    ['] _SCRIPTED-TOOL-RESULT _SPN-P @ APROV.TOOL-RESULT-XT !
    ['] SCRIPTED-PROVIDER-FREE _SPN-P @ APROV.FREE-XT !
    _SPN-P @ 0 ;

: _SCRIPTED-SOURCE-CREATE  ( context -- provider status )
    DROP SCRIPTED-PROVIDER-NEW ;

: SCRIPTED-SOURCE-FREE  ( source -- )
    DUP AGENT-PROVIDER-SOURCE-SIZE 0 FILL FREE ;

VARIABLE _SPSRC-SOURCE

: SCRIPTED-SOURCE-NEW  ( -- source status )
    AGENT-PROVIDER-SOURCE-SIZE ALLOCATE
    DUP IF 2DROP 0 APSOURCE-S-NOMEM EXIT THEN
    DROP DUP _SPSRC-SOURCE ! APSOURCE-INIT
    S" org.akashic.agent.source.testing.scripted"
    _SPSRC-SOURCE @ APSOURCE.ID-U ! _SPSRC-SOURCE @ APSOURCE.ID-A !
    ['] _SCRIPTED-SOURCE-CREATE _SPSRC-SOURCE @ APSOURCE.NEW-XT !
    ['] SCRIPTED-SOURCE-FREE _SPSRC-SOURCE @ APSOURCE.FREE-XT !
    _SPSRC-SOURCE @ APSOURCE-S-OK ;
