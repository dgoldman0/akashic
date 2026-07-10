\ =====================================================================
\  transport.f - Injected native MCP message transport
\ =====================================================================
\  Transports move complete JSON-RPC messages. Streamable HTTP, serial
\  framing, loopback, and future links bind here without entering protocol
\  parsing or the component adapter.
\ =====================================================================

PROVIDED akashic-mcp-transport-port

REQUIRE protocol.f

 0 CONSTANT _MTR-CONTEXT
 8 CONSTANT _MTR-SEND-XT       \ ( addr len context -- status )
16 CONSTANT _MTR-RECV-XT       \ ( buffer capacity context -- len status )
24 CONSTANT _MTR-CLOSE-XT      \ ( context -- )
32 CONSTANT _MTR-FLAGS
40 CONSTANT MCP-TRANSPORT-SIZE

: MTRANS.CONTEXT   ( transport -- a ) _MTR-CONTEXT + ;
: MTRANS.SEND-XT   ( transport -- a ) _MTR-SEND-XT + ;
: MTRANS.RECV-XT   ( transport -- a ) _MTR-RECV-XT + ;
: MTRANS.CLOSE-XT  ( transport -- a ) _MTR-CLOSE-XT + ;
: MTRANS.FLAGS     ( transport -- a ) _MTR-FLAGS + ;

: MCP-TRANSPORT-INIT  ( transport -- ) MCP-TRANSPORT-SIZE 0 FILL ;

: MCP-TRANSPORT-SEND  ( addr len transport -- status )
    DUP 0= IF DROP 2DROP MCP-S-TRANSPORT EXIT THEN
    DUP MTRANS.SEND-XT @ ?DUP 0= IF DROP 2DROP MCP-S-TRANSPORT EXIT THEN
    >R MTRANS.CONTEXT @ R> EXECUTE ;

: MCP-TRANSPORT-RECV  ( buffer capacity transport -- len status )
    DUP 0= IF DROP 2DROP 0 MCP-S-TRANSPORT EXIT THEN
    DUP MTRANS.RECV-XT @ ?DUP 0= IF DROP 2DROP 0 MCP-S-TRANSPORT EXIT THEN
    >R MTRANS.CONTEXT @ R> EXECUTE ;

: MCP-TRANSPORT-CLOSE  ( transport -- )
    DUP 0= IF DROP EXIT THEN
    DUP MTRANS.CLOSE-XT @ ?DUP IF
        >R MTRANS.CONTEXT @ R> EXECUTE
    ELSE
        DROP
    THEN ;
