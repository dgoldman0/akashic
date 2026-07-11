\ =====================================================================
\  io-port.f - Injected cooperative byte-stream transport
\ =====================================================================
\  The port is transport-neutral. Socket, TLS, fixture, and device adapters
\  supply callbacks while protocol clients retain their own parser state.
\ =====================================================================

PROVIDED akashic-net-io-port

0 CONSTANT NIO-S-OK
1 CONSTANT NIO-S-EOF
2 CONSTANT NIO-S-FAILED
3 CONSTANT NIO-S-CANCELLED

\ RECV-XT:  ( buffer capacity context -- count io-status )
\ SEND-XT:  ( buffer length context -- count io-status )
\ POLL-XT:  ( context -- )
\ CLOSE-XT: ( context -- )
 0 CONSTANT _NIO-CONTEXT
 8 CONSTANT _NIO-RECV-XT
16 CONSTANT _NIO-SEND-XT
24 CONSTANT _NIO-POLL-XT
32 CONSTANT _NIO-CLOSE-XT
40 CONSTANT NET-IO-PORT-SIZE

: NIO.CONTEXT  ( port -- a ) _NIO-CONTEXT + ;
: NIO.RECV-XT  ( port -- a ) _NIO-RECV-XT + ;
: NIO.SEND-XT  ( port -- a ) _NIO-SEND-XT + ;
: NIO.POLL-XT  ( port -- a ) _NIO-POLL-XT + ;
: NIO.CLOSE-XT ( port -- a ) _NIO-CLOSE-XT + ;

: NIO-INIT  ( port -- ) NET-IO-PORT-SIZE 0 FILL ;

: NIO-POLL  ( port -- )
    DUP 0= IF DROP EXIT THEN
    DUP NIO.POLL-XT @ ?DUP IF
        >R NIO.CONTEXT @ R> EXECUTE
    ELSE
        DROP
    THEN ;

: NIO-CLOSE  ( port -- )
    DUP 0= IF DROP EXIT THEN
    DUP NIO.CLOSE-XT @ ?DUP IF
        >R NIO.CONTEXT @ R> EXECUTE
    ELSE
        DROP
    THEN ;

VARIABLE _NIOR-PORT
VARIABLE _NIOR-XT
VARIABLE _NIOR-N
VARIABLE _NIOR-STATUS

: _NIO-RECV-INNER  ( buffer capacity -- )
    _NIOR-PORT @ NIO.CONTEXT @ _NIOR-XT @ EXECUTE
    _NIOR-STATUS ! _NIOR-N ! ;

: NIO-RECV  ( buffer capacity port -- count io-status )
    DUP 0= IF DROP 2DROP 0 NIO-S-FAILED EXIT THEN
    DUP _NIOR-PORT ! NIO.RECV-XT @ DUP 0= IF
        DROP 2DROP 0 NIO-S-FAILED EXIT
    THEN
    _NIOR-XT ! 0 _NIOR-N ! NIO-S-FAILED _NIOR-STATUS !
    ['] _NIO-RECV-INNER CATCH IF 2DROP 0 NIO-S-FAILED EXIT THEN
    _NIOR-N @ _NIOR-STATUS @ ;

VARIABLE _NIOS-PORT
VARIABLE _NIOS-XT
VARIABLE _NIOS-N
VARIABLE _NIOS-STATUS

: _NIO-SEND-INNER  ( buffer length -- )
    _NIOS-PORT @ NIO.CONTEXT @ _NIOS-XT @ EXECUTE
    _NIOS-STATUS ! _NIOS-N ! ;

: NIO-SEND  ( buffer length port -- count io-status )
    DUP 0= IF DROP 2DROP 0 NIO-S-FAILED EXIT THEN
    DUP _NIOS-PORT ! NIO.SEND-XT @ DUP 0= IF
        DROP 2DROP 0 NIO-S-FAILED EXIT
    THEN
    _NIOS-XT ! 0 _NIOS-N ! NIO-S-FAILED _NIOS-STATUS !
    ['] _NIO-SEND-INNER CATCH IF 2DROP 0 NIO-S-FAILED EXIT THEN
    _NIOS-N @ _NIOS-STATUS @ ;
