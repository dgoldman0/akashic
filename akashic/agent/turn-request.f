\ =====================================================================
\  turn-request.f - Borrowed structured request passed to agent providers
\ =====================================================================
\  A provider must consume or copy this descriptor during START. The model
\  context pointer is owned by the conversation and CONTEXT-N is the immutable
\  snapshot boundary for this turn.
\ =====================================================================

PROVIDED akashic-agent-turn-request

REQUIRE model-context.f

 0 CONSTANT _ATR-THREAD-ID
 8 CONSTANT _ATR-RUN-ID
16 CONSTANT _ATR-PROMPT-A
24 CONSTANT _ATR-PROMPT-U
32 CONSTANT _ATR-CONTEXT
40 CONSTANT _ATR-CONTEXT-N
48 CONSTANT _ATR-CONTEXT-REVISION
56 CONSTANT _ATR-TOOL-GATEWAY
64 CONSTANT _ATR-FLAGS
72 CONSTANT _ATR-MAX-OUTPUT
80 CONSTANT AGENT-TURN-REQUEST-SIZE

: ATURN.THREAD-ID        ( turn -- a ) _ATR-THREAD-ID + ;
: ATURN.RUN-ID           ( turn -- a ) _ATR-RUN-ID + ;
: ATURN.PROMPT-A         ( turn -- a ) _ATR-PROMPT-A + ;
: ATURN.PROMPT-U         ( turn -- a ) _ATR-PROMPT-U + ;
: ATURN.CONTEXT          ( turn -- a ) _ATR-CONTEXT + ;
: ATURN.CONTEXT-N        ( turn -- a ) _ATR-CONTEXT-N + ;
: ATURN.CONTEXT-REVISION ( turn -- a ) _ATR-CONTEXT-REVISION + ;
: ATURN.TOOL-GATEWAY     ( turn -- a ) _ATR-TOOL-GATEWAY + ;
: ATURN.FLAGS            ( turn -- a ) _ATR-FLAGS + ;
: ATURN.MAX-OUTPUT       ( turn -- a ) _ATR-MAX-OUTPUT + ;

: ATURN-INIT  ( turn -- ) AGENT-TURN-REQUEST-SIZE 0 FILL ;

: ATURN-PROMPT  ( turn -- addr len )
    DUP ATURN.PROMPT-A @ SWAP ATURN.PROMPT-U @ ;

: ATURN-VALID?  ( turn -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP ATURN.THREAD-ID @ 1 < IF DROP 0 EXIT THEN
    DUP ATURN.RUN-ID @ 1 < IF DROP 0 EXIT THEN
    DUP ATURN.PROMPT-U @ DUP 1 < IF 2DROP 0 EXIT THEN
    OVER ATURN.PROMPT-A @ SWAP UTF8-VALID? 0= IF DROP 0 EXIT THEN
    DUP ATURN.CONTEXT @ DUP 0= IF 2DROP 0 EXIT THEN
    >R DUP ATURN.CONTEXT-N @ DUP 0< SWAP R@ ACTX.COUNT @ > OR IF
        R> 2DROP 0 EXIT
    THEN
    DUP ATURN.CONTEXT-REVISION @ R> ACTX.REVISION @ > IF DROP 0 EXIT THEN
    DROP -1 ;
