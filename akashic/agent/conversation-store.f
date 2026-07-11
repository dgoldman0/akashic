\ =====================================================================
\  conversation-store.f - Provider-neutral durable transcript port
\ =====================================================================
\  The port owns storage behavior but no VFS, codec, TUI, Desk, or provider
\  policy. A successful load returns a newly allocated conversation.
\ =====================================================================

PROVIDED akashic-agent-conv-store

REQUIRE conversation.f

0 CONSTANT ACSTORE-S-OK
1 CONSTANT ACSTORE-S-NOT-FOUND
2 CONSTANT ACSTORE-S-IO
3 CONSTANT ACSTORE-S-INVALID
4 CONSTANT ACSTORE-S-CAPACITY
5 CONSTANT ACSTORE-S-NOMEM
6 CONSTANT ACSTORE-S-UNAVAILABLE

 0 CONSTANT _ACS-CONTEXT
 8 CONSTANT _ACS-LOAD-XT       \ ( context -- conversation status )
16 CONSTANT _ACS-SAVE-XT       \ ( conversation context -- status )
24 CONSTANT _ACS-FREE-XT       \ ( store -- )
32 CONSTANT _ACS-LAST-STATUS
40 CONSTANT _ACS-FLAGS
48 CONSTANT AGENT-CONVERSATION-STORE-SIZE

: ACSTORE.CONTEXT     ( store -- a ) _ACS-CONTEXT + ;
: ACSTORE.LOAD-XT     ( store -- a ) _ACS-LOAD-XT + ;
: ACSTORE.SAVE-XT     ( store -- a ) _ACS-SAVE-XT + ;
: ACSTORE.FREE-XT     ( store -- a ) _ACS-FREE-XT + ;
: ACSTORE.LAST-STATUS ( store -- a ) _ACS-LAST-STATUS + ;
: ACSTORE.FLAGS       ( store -- a ) _ACS-FLAGS + ;

: ACSTORE-INIT  ( store -- )
    AGENT-CONVERSATION-STORE-SIZE 0 FILL ;

VARIABLE _ACSR-S
VARIABLE _ACSC-S
VARIABLE _ACSC-XT

: _ACSTORE-RESULT  ( status store -- status )
    _ACSR-S ! DUP _ACSR-S @ ACSTORE.LAST-STATUS ! ;

: ACSTORE-LOAD  ( store -- conversation status )
    DUP 0= IF DROP 0 ACSTORE-S-UNAVAILABLE EXIT THEN
    DUP ACSTORE.LOAD-XT @ ?DUP 0= IF
        DROP 0 ACSTORE-S-UNAVAILABLE EXIT
    THEN
    _ACSC-XT ! DUP _ACSC-S !
    ACSTORE.CONTEXT @ _ACSC-XT @ EXECUTE
    _ACSC-S @ _ACSTORE-RESULT ;

: ACSTORE-SAVE  ( conversation store -- status )
    DUP 0= IF 2DROP ACSTORE-S-UNAVAILABLE EXIT THEN
    DUP ACSTORE.SAVE-XT @ ?DUP 0= IF
        2DROP ACSTORE-S-UNAVAILABLE EXIT
    THEN
    _ACSC-XT ! DUP _ACSC-S !
    ACSTORE.CONTEXT @ _ACSC-XT @ EXECUTE
    _ACSC-S @ _ACSTORE-RESULT ;

: ACSTORE-FREE  ( store -- )
    DUP 0= IF DROP EXIT THEN
    DUP ACSTORE.FREE-XT @ ?DUP IF EXECUTE ELSE FREE THEN ;
