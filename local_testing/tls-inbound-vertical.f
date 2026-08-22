\ tls-inbound-vertical.f - real inbound TLS -> NIO -> HCONN gate
\
\ The host defines _ktiv-chain, _KTIV-CHAIN-U, and the 32-byte
\ little-endian d=3 _ktiv-key before requiring this source.  It then releases
\ each printed gate only after installing the corresponding independent TLS
\ peer on the emulated NIC.

PROVIDED ktiv-real-server

2500 CONSTANT _KTIV-HANDSHAKE-TIMEOUT-MS
4096 CONSTANT _KTIV-EARLY-WIRE-BUDGET
32768 CONSTANT _KTIV-ACCEPT-STEP-LIMIT
32768 CONSTANT _KTIV-HCONN-STEP-LIMIT

512 CONSTANT _KTIV-REQUEST-HEADER-CAPACITY
256 CONSTANT _KTIV-RESPONSE-HEADER-CAPACITY
7 CONSTANT _KTIV-RESPONSE-SEND-CAPACITY
512 CONSTANT _KTIV-RX-CAPACITY
8 CONSTANT _KTIV-ROUTE-OPERATION-CAPACITY
25 CONSTANT _KTIV-RESPONSE-BODY-U

VARIABLE _ktiv-checks
VARIABLE _ktiv-stage
VARIABLE _ktiv-fail-stage
VARIABLE _ktiv-depth
VARIABLE _ktiv-connection-index

: _ktiv-fail!  ( stage -- )
    _ktiv-fail-stage @ 0= IF _ktiv-fail-stage ! ELSE DROP THEN ;

: _ktiv-check  ( flag -- flag )
    1 _ktiv-checks +!
    DUP 0= IF _ktiv-stage @ _ktiv-fail! THEN ;

: _ktiv-phase-stage  ( offset -- )
    _ktiv-connection-index @ 100 * + _ktiv-stage ! ;

CREATE _ktiv-alpn 8 ALLOT
CREATE _ktiv-authority 16 ALLOT
CREATE _ktiv-response-body _KTIV-RESPONSE-BODY-U ALLOT
CREATE _ktiv-peer-ip 4 ALLOT
CREATE _ktiv-peer-mac 6 ALLOT

CREATE _ktiv-xio-service XIO-SERVICE-SIZE ALLOT
CREATE _ktiv-listener-owner KDOSTLSL-SIZE ALLOT
CREATE _ktiv-result-a KDOSTLSP-SIZE ALLOT
CREATE _ktiv-result-b KDOSTLSP-SIZE ALLOT

CREATE _ktiv-router-entry HROUTER-ENTRY-SIZE ALLOT
CREATE _ktiv-router-arena 32 ALLOT
CREATE _ktiv-router HROUTER-SIZE ALLOT
CREATE _ktiv-match HROUTER-MATCH-SIZE ALLOT
CREATE _ktiv-request WEB-HTTP-REQUEST-STREAM-SIZE ALLOT
CREATE _ktiv-request-header _KTIV-REQUEST-HEADER-CAPACITY ALLOT
CREATE _ktiv-response HTTP-RESPONSE-WRITER-SIZE ALLOT
CREATE _ktiv-response-header _KTIV-RESPONSE-HEADER-CAPACITY ALLOT
CREATE _ktiv-response-send _KTIV-RESPONSE-SEND-CAPACITY ALLOT
CREATE _ktiv-rx _KTIV-RX-CAPACITY ALLOT
CREATE _ktiv-route-operation _KTIV-ROUTE-OPERATION-CAPACITY ALLOT
CREATE _ktiv-connection HTTP-CONNECTION-OWNER-SIZE ALLOT
VARIABLE _ktiv-handler-context

VARIABLE _ktiv-credential-h1
VARIABLE _ktiv-credential-generation
VARIABLE _ktiv-credential-ior
VARIABLE _ktiv-listener-sd
VARIABLE _ktiv-listener-h1
VARIABLE _ktiv-listener-generation
VARIABLE _ktiv-listener-ior

VARIABLE _ktiv-result
VARIABLE _ktiv-port
VARIABLE _ktiv-accept-status
VARIABLE _ktiv-accept-ticks
VARIABLE _ktiv-accept-retries
VARIABLE _ktiv-accept-failed
VARIABLE _ktiv-accept-successes
VARIABLE _ktiv-hconn-ticks

VARIABLE _ktiv-handler-hits
VARIABLE _ktiv-handler-polls
VARIABLE _ktiv-handler-cancels
VARIABLE _ktiv-handler-cleanups
VARIABLE _ktiv-source-calls
VARIABLE _ktiv-source-bytes
VARIABLE _ktiv-source-partials
VARIABLE _ktiv-source-expected-offset

VARIABLE _ktiv-cb-exchange
VARIABLE _ktiv-cb-operation
VARIABLE _ktiv-cb-context
VARIABLE _ktiv-cb-response
VARIABLE _ktiv-source-offset
VARIABLE _ktiv-source-destination
VARIABLE _ktiv-source-requested
VARIABLE _ktiv-source-context
VARIABLE _ktiv-source-remaining
VARIABLE _ktiv-source-count

VARIABLE _ktiv-close-ior
VARIABLE _ktiv-close-attempts
VARIABLE _ktiv-delete-ior
VARIABLE _ktiv-delete-attempts

: _ktiv-setup-strings  ( -- )
    _ktiv-alpn 8 0 FILL
    S" http/1.1" _ktiv-alpn SWAP MOVE
    _ktiv-authority 16 0 FILL
    S" test.example.com" _ktiv-authority SWAP MOVE
    _ktiv-response-body _KTIV-RESPONSE-BODY-U 0 FILL
    S" Akashic secure transport" _ktiv-response-body SWAP MOVE
    10 _ktiv-response-body 24 + C! ;

: _ktiv-source-failed  ( stage -- count source-status )
    _ktiv-fail! 0 HRESP-SOURCE-S-FAILED ;

: _ktiv-response-source
    ( offset scratch-a requested-u context -- count source-status )
    _ktiv-source-context !
    _ktiv-source-requested !
    _ktiv-source-destination !
    _ktiv-source-offset !
    _ktiv-source-context @ _ktiv-route-operation <> IF
        311 _ktiv-source-failed EXIT
    THEN
    _ktiv-source-offset @ 0< IF 312 _ktiv-source-failed EXIT THEN
    _ktiv-source-offset @ _KTIV-RESPONSE-BODY-U > IF
        313 _ktiv-source-failed EXIT
    THEN
    _ktiv-source-offset @ _ktiv-source-expected-offset @ <> IF
        314 _ktiv-source-failed EXIT
    THEN
    _ktiv-source-requested @ 0> 0= IF
        315 _ktiv-source-failed EXIT
    THEN
    _ktiv-source-offset @ _KTIV-RESPONSE-BODY-U = IF
        0 HRESP-SOURCE-S-END EXIT
    THEN
    _KTIV-RESPONSE-BODY-U _ktiv-source-offset @ -
        _ktiv-source-remaining !
    _ktiv-source-requested @ _ktiv-source-remaining @ MIN
        _ktiv-source-count !
    _ktiv-response-body _ktiv-source-offset @ +
    _ktiv-source-destination @ _ktiv-source-count @ MOVE
    1 _ktiv-source-calls +!
    _ktiv-source-count @ _ktiv-source-bytes +!
    _ktiv-source-count @ _ktiv-source-remaining @ < IF
        1 _ktiv-source-partials +!
    THEN
    _ktiv-source-count @ _ktiv-source-expected-offset +!
    _ktiv-source-count @ HRESP-SOURCE-S-OK ;

: _ktiv-route-start  ( exchange operation context -- outcome )
    _ktiv-cb-context !
    _ktiv-cb-operation !
    _ktiv-cb-exchange !
    1 _ktiv-handler-hits +!
    0 _ktiv-source-expected-offset !
    _ktiv-cb-context @ _ktiv-handler-context <> IF
        321 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    _ktiv-cb-operation @ _ktiv-route-operation <> IF
        322 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    _ktiv-cb-exchange @ HCONN-BODY-DISCARD
        HCONN-S-PENDING <> IF
        323 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    _ktiv-cb-exchange @ HCONN-RESPONSE@ DUP 0= IF
        DROP 324 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    _ktiv-cb-response !
    200 _ktiv-cb-response @ HRESP-BEGIN HRESP-S-OK <> IF
        325 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    S" text/plain" _ktiv-cb-response @ HRESP-CONTENT-TYPE
        HRESP-S-OK <> IF
        326 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    _KTIV-RESPONSE-BODY-U _ktiv-cb-operation @
    ['] _ktiv-response-source _ktiv-cb-response @ HRESP-BODY-SOURCE
        HRESP-S-OK <> IF
        327 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    _ktiv-cb-response @ HRESP-SEAL HRESP-S-OK <> IF
        328 _ktiv-fail! HROUTE-OUTCOME-FAILED EXIT
    THEN
    HROUTE-OUTCOME-RESPONSE ;

: _ktiv-route-poll  ( exchange operation context -- outcome )
    2DROP DROP
    1 _ktiv-handler-polls +!
    329 _ktiv-fail!
    HROUTE-OUTCOME-FAILED ;

: _ktiv-route-cancel  ( exchange operation context -- outcome )
    2DROP DROP
    1 _ktiv-handler-cancels +!
    HROUTE-OUTCOME-CANCELLED ;

: _ktiv-route-cleanup  ( exchange operation context -- error )
    2DROP DROP
    1 _ktiv-handler-cleanups +!
    0 ;

: _ktiv-setup-router  ( -- flag )
    10 _ktiv-stage !
    _ktiv-router-entry 1 _ktiv-router-arena 32 _ktiv-router
        HROUTER-INIT HROUTER-S-OK = _ktiv-check 0= IF 0 EXIT THEN
    11 _ktiv-stage !
    S" GET" S" /probe" _ktiv-handler-context
    _KTIV-ROUTE-OPERATION-CAPACITY
    ['] _ktiv-route-start ['] _ktiv-route-poll
    ['] _ktiv-route-cancel ['] _ktiv-route-cleanup
    _ktiv-router HROUTER-ADD HROUTER-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    12 _ktiv-stage !
    _ktiv-router HROUTER-SEAL HROUTER-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    -1 ;

: _ktiv-setup-network  ( -- flag )
    20 _ktiv-stage !
    1 TLS-CREDENTIAL-POOL-INIT 0= _ktiv-check 0= IF 0 EXIT THEN
    21 _ktiv-stage !
    _ktiv-chain _KTIV-CHAIN-U _ktiv-key TLS-CREDENTIAL-PROVISION
    _ktiv-credential-ior !
    _ktiv-credential-generation !
    _ktiv-credential-h1 !
    _ktiv-credential-ior @ 0= _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-credential-h1 @ 0> _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-credential-generation @ 0> _ktiv-check 0= IF 0 EXIT THEN

    TCP-INIT-ALL ARP-CLEAR
    10 0 0 2 IP-SET
    255 255 255 0 NET-MASK IP!
    0 0 0 0 GW-IP IP!
    10 0 0 1 _ktiv-peer-ip IP!
    _ktiv-peer-mac 6 170 FILL
    _ktiv-peer-ip _ktiv-peer-mac ARP-INSERT

    22 _ktiv-stage !
    SOCK-TYPE-TLS SOCKET DUP _ktiv-listener-sd !
    -1 <> _ktiv-check 0= IF 0 EXIT THEN
    23 _ktiv-stage !
    _ktiv-listener-sd @ 443 BIND 0=
        _ktiv-check 0= IF 0 EXIT THEN
    24 _ktiv-stage !
    _ktiv-listener-sd @
    _ktiv-credential-h1 @ _ktiv-credential-generation @
    _ktiv-alpn 8 _KTIV-EARLY-WIRE-BUDGET
    _KTIV-HANDSHAKE-TIMEOUT-MS TLS-LISTEN
    _ktiv-listener-ior !
    _ktiv-listener-generation !
    _ktiv-listener-h1 !
    _ktiv-listener-ior @ 0= _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-h1 @ 0> _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-generation @ 0> _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-sd @ SOCK-TLS-LISTENER?
        _ktiv-check 0= IF 0 EXIT THEN
    -1 ;

: _ktiv-setup-accept  ( -- flag )
    30 _ktiv-stage !
    _ktiv-xio-service XIO-SERVICE-INIT XIO-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    31 _ktiv-stage !
    _ktiv-result-a KDOSTLSP-INIT KDOSTLSP-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-b KDOSTLSP-INIT KDOSTLSP-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    32 _ktiv-stage !
    _ktiv-xio-service _ktiv-listener-sd @ _ktiv-listener-h1 @
    _ktiv-listener-generation @ _KTIV-HANDSHAKE-TIMEOUT-MS
    _KTIV-EARLY-WIRE-BUDGET _ktiv-listener-owner
    KDOSTLSL-INIT KDOSTLSL-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    -1 ;

: _ktiv-setup  ( -- flag )
    _ktiv-setup-strings
    _ktiv-setup-router 0= IF 0 EXIT THEN
    _ktiv-setup-network 0= IF 0 EXIT THEN
    _ktiv-setup-accept ;

: _ktiv-select-result  ( -- )
    _ktiv-connection-index @ 1 = IF
        _ktiv-result-a
    ELSE
        _ktiv-result-b
    THEN _ktiv-result ! ;

: _ktiv-begin-accept  ( -- flag )
    0 _ktiv-port !
    _ktiv-result @ _ktiv-listener-owner KDOSTLSL-ACCEPT
    DUP _ktiv-accept-status ! KDOSTLSL-S-OK = ;

: _ktiv-retry-accept  ( -- flag )
    23 _ktiv-phase-stage
    _ktiv-port @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSTLSP.STATE @ KDOSTLSP-STATE-RESET =
        _ktiv-check 0= IF 0 EXIT THEN
    1 _ktiv-accept-retries +!
    _ktiv-begin-accept _ktiv-check ;

: _ktiv-drive-accept  ( -- flag )
    0 _ktiv-port !
    0 _ktiv-accept-ticks !
    0 _ktiv-accept-failed !
    20 _ktiv-phase-stage
    _ktiv-result @ KDOSTLSP.STATE @ KDOSTLSP-STATE-RESET =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-begin-accept _ktiv-check 0= IF 0 EXIT THEN
    BEGIN
        _ktiv-port @ 0=
        _ktiv-accept-failed @ 0= AND
        _ktiv-accept-ticks @ _KTIV-ACCEPT-STEP-LIMIT < AND
    WHILE
        _ktiv-listener-owner KDOSTLSL-STEP
        _ktiv-accept-status !
        _ktiv-port !
        _ktiv-accept-status @ KDOSTLSL-S-PENDING = IF
            _ktiv-port @ 0<> IF
                25 _ktiv-phase-stage
                _ktiv-stage @ _ktiv-fail!
                -1 _ktiv-accept-failed !
            THEN
        ELSE
            _ktiv-accept-status @ KDOSTLSL-S-RETRY = IF
                _ktiv-retry-accept 0= IF -1 _ktiv-accept-failed ! THEN
            ELSE
                _ktiv-accept-status @ KDOSTLSL-S-OK = IF
                    _ktiv-port @ 0= IF
                        21 _ktiv-phase-stage
                        _ktiv-stage @ _ktiv-fail!
                        -1 _ktiv-accept-failed !
                    THEN
                ELSE
                    24 _ktiv-phase-stage
                    _ktiv-stage @ _ktiv-fail!
                    -1 _ktiv-accept-failed !
                THEN
            THEN
        THEN
        1 _ktiv-accept-ticks +!
    REPEAT
    27 _ktiv-phase-stage
    _ktiv-port @ 0<> _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-accept-failed @ 0= _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-accept-status @ KDOSTLSL-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-port @ _ktiv-result @ KDOSTLSP.PORT =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSTLSP.STATE @ KDOSTLSP-STATE-OPEN =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSTLSP.SOCKET-SD @ 0<>
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSNET-OWNER? 0=
        _ktiv-check 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ 0= _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-xio-service XIO-ACTIVE? 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-xio-service XIOS.RETAINED @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    28 _ktiv-phase-stage
    _ktiv-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-IDLE = _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.XIO-OP XIOO.STATE @
    XIO-STATE-RESET = _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.CTX @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.CTX-GEN @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.BORROWED-PORT @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.STAGING-SOCKET @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.TERMINAL @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    1 _ktiv-accept-successes +!
    -1 ;

: _ktiv-init-hconn  ( -- flag )
    30 _ktiv-phase-stage
    _ktiv-request-header _KTIV-REQUEST-HEADER-CAPACITY
    0 0 0 _ktiv-request WREQ-INIT WREQ-S-PENDING =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-response-header _KTIV-RESPONSE-HEADER-CAPACITY
    _ktiv-response-send _KTIV-RESPONSE-SEND-CAPACITY
    _ktiv-response HRESP-INIT HRESP-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-port @ NIO.OPEN-STATE @ NIO-OPEN-STATE-OPEN =
        _ktiv-check 0= IF 0 EXIT THEN
    31 _ktiv-phase-stage
    _ktiv-request _ktiv-response _ktiv-match _ktiv-router
    _ktiv-port @ _ktiv-rx _KTIV-RX-CAPACITY
    _ktiv-route-operation _KTIV-ROUTE-OPERATION-CAPACITY
    _ktiv-authority 16 _ktiv-connection HCONN-INIT
    HCONN-S-PENDING = _ktiv-check 0= IF 0 EXIT THEN
    32 _ktiv-phase-stage
    _ktiv-connection HCONN-START HCONN-S-PENDING =
        _ktiv-check ;

: _ktiv-drive-hconn  ( -- flag )
    0 _ktiv-hconn-ticks !
    BEGIN
        _ktiv-connection HCONN-TERMINAL? 0=
        _ktiv-hconn-ticks @ _KTIV-HCONN-STEP-LIMIT < AND
    WHILE
        _ktiv-connection HCONN-STEP DROP
        1 _ktiv-hconn-ticks +!
    REPEAT
    40 _ktiv-phase-stage
    _ktiv-connection HCONN-TERMINAL?
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-connection HCONN-STATUS@ HCONN-S-DONE =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-connection HCONN-RESULT@ HCONN-S-DONE =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-connection HCONN-HTTP-STATUS@ 200 =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-connection HCONN-ROUTE-OUTCOME@
        HROUTE-OUTCOME-RESPONSE = _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-connection HCONN-CLEANUP-ERROR@ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-connection HCONN-TRANSPORT-STATUS@ NIO-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN

    41 _ktiv-phase-stage
    _ktiv-port @ NIO.OPEN-STATE @ NIO-OPEN-STATE-CLOSED =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-port @ NIO.CLOSE-STATE @ NIO-CLOSE-STATE-CLOSED =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSTLSP.STATE @ KDOSTLSP-STATE-CLOSED =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSTLSP.SOCKET-SD @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSNET-OWNER? 0=
        _ktiv-check 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ 0= _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSTLSP.LAST-ERROR @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result @ KDOSTLSP.CLEANUP-ERROR @ 0=
        _ktiv-check 0= IF 0 EXIT THEN

    42 _ktiv-phase-stage
    _ktiv-handler-hits @ _ktiv-connection-index @ =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-handler-cleanups @ _ktiv-connection-index @ =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-handler-polls @ 0= _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-handler-cancels @ 0= _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-source-calls @ _ktiv-connection-index @ 4 * =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-source-partials @ _ktiv-connection-index @ 3 * =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-source-bytes @ _ktiv-connection-index @
        _KTIV-RESPONSE-BODY-U * = _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-source-expected-offset @ _KTIV-RESPONSE-BODY-U =
        _ktiv-check ;

: _ktiv-service-network-poll  ( -- flag )
    43 _ktiv-phase-stage
    _ktiv-listener-owner ['] TCP-POLL KDOSNET-WITH
    KDOSNET-S-OK = SWAP 0= AND
    SWAP KDOSNET-S-OK = AND
        _ktiv-check 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ 0= _ktiv-check ;

: _ktiv-run-one  ( -- flag )
    _ktiv-select-result
    _ktiv-drive-accept 0= IF 0 EXIT THEN
    _ktiv-init-hconn 0= IF 0 EXIT THEN
    _ktiv-drive-hconn 0= IF 0 EXIT THEN
    \ HCONN has retired TLS/socket authority after emitting its FIN.  Give
    \ the machine-wide TCP service one separately serialized operation to
    \ consume the peer's already-queued final ACK and settle LAST-ACK.
    _ktiv-service-network-poll ;

: _ktiv-prepare-second  ( -- flag )
    150 _ktiv-stage !
    _ktiv-result-a KDOSTLSP.STATE @ KDOSTLSP-STATE-CLOSED =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-a KDOSTLSP.SOCKET-SD @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-a KDOSNET-OWNER? 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-b KDOSTLSP.STATE @ KDOSTLSP-STATE-RESET =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-b KDOSTLSP.SOCKET-SD @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-b KDOSNET-OWNER? 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-IDLE = _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.XIO-OP XIOO.STATE @
    XIO-STATE-RESET = _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.CTX @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.CTX-GEN @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.BORROWED-PORT @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.STAGING-SOCKET @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner _KDOSTLSL.TERMINAL @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    -1 ;

: _ktiv-close-retryable?  ( ior -- flag )
    CASE
        TLS-E-BUSY OF -1 ENDOF
        TCP-ACCEPT-E-BUSY OF -1 ENDOF
        TLS-E-WOULD-BLOCK OF -1 ENDOF
        0 SWAP
    ENDCASE ;

: _ktiv-close-listener  ( -- flag )
    0 _ktiv-close-attempts !
    _ktiv-listener-sd @ CLOSE-TRY _ktiv-close-ior !
    BEGIN
        _ktiv-close-ior @ _ktiv-close-retryable?
        _ktiv-close-attempts @ 64 < AND
    WHILE
        TCP-POLL
        _ktiv-listener-sd @ CLOSE-TRY _ktiv-close-ior !
        1 _ktiv-close-attempts +!
    REPEAT
    _ktiv-close-ior @ 0= ;

: _ktiv-delete-credential  ( -- flag )
    0 _ktiv-delete-attempts !
    _ktiv-credential-h1 @ _ktiv-credential-generation @
        TLS-CREDENTIAL-DELETE _ktiv-delete-ior !
    BEGIN
        _ktiv-delete-ior @ TLS-CREDENTIAL-E-BUSY =
        _ktiv-delete-attempts @ 64 < AND
    WHILE
        _ktiv-credential-h1 @ _ktiv-credential-generation @
            TLS-CREDENTIAL-DELETE _ktiv-delete-ior !
        1 _ktiv-delete-attempts +!
    REPEAT
    _ktiv-delete-ior @ 0= ;

: _ktiv-live-sockets  ( -- count )
    0 SOCK-MAX 0 DO
        I SOCK-N SOCK.STATE @ SOCKST-FREE <> IF 1+ THEN
    LOOP ;

: _ktiv-report-live-tcbs  ( -- )
    /TCP-MAX-CONN 0 DO
        I TCB-N DUP TCB.STATE @ TCPS-CLOSED <>
        OVER TCB.AUTH-STATE @ TCP-AUTH-NONE <> OR IF
            ." KTIV LIVE TCB " I .
            ." STATE " DUP TCB.STATE @ .
            ." AUTH " DUP TCB.AUTH-STATE @ .
            ." OWNER " DUP TCB.OWNER @ .
            ." GEN " DUP TCB.GENERATION @ .
            ." PARENT " DUP TCB.PARENT-H1 @ .
            ." PARENT-GEN " DUP TCB.PARENT-GEN @ .
            ." LPORT " DUP TCB.LOCAL-PORT @ .
            ." RPORT " DUP TCB.REMOTE-PORT @ . CR
        THEN
        DROP
    LOOP ;

: _ktiv-teardown  ( -- flag )
    900 _ktiv-stage !
    _ktiv-listener-owner _KDOSTLSL.REQUEST-GEN @ 2 >=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-a KDOSTLSP.STATE @ KDOSTLSP-STATE-CLOSED =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-a KDOSTLSP.SOCKET-SD @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-a KDOSNET-OWNER? 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-b KDOSTLSP.STATE @ KDOSTLSP-STATE-CLOSED =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-b KDOSTLSP.SOCKET-SD @ 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-result-b KDOSNET-OWNER? 0=
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-listener-owner KDOSTLSL-FINI KDOSTLSL-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-xio-service XIO-SERVICE-FINI XIO-S-OK =
        _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-close-listener _ktiv-check 0= IF 0 EXIT THEN
    _ktiv-delete-credential _ktiv-check 0= IF 0 EXIT THEN

    901 _ktiv-stage !
    _ktiv-live-sockets 0= _ktiv-check 0= IF 0 EXIT THEN
    902 _ktiv-stage !
    _TLS-ANY-CONTEXT-LIVE? 0= _ktiv-check 0= IF 0 EXIT THEN
    903 _ktiv-stage !
    _TCP-ANY-TCB-LIVE? IF
        _ktiv-report-live-tcbs 0
    ELSE
        -1
    THEN _ktiv-check 0= IF 0 EXIT THEN
    904 _ktiv-stage !
    TLS-CREDENTIAL-ACTIVE @ 0= _ktiv-check 0= IF 0 EXIT THEN
    905 _ktiv-stage !
    KDOSNET-OWNER@ 0= _ktiv-check 0= IF 0 EXIT THEN
    906 _ktiv-stage !
    TLS-OWNER-DEPTH @ 0= _ktiv-check 0= IF 0 EXIT THEN
    907 _ktiv-stage !
    TLS-OWNER-CORE @ -1 = _ktiv-check 0= IF 0 EXIT THEN
    908 _ktiv-stage !
    TLS-OWNER-TASK @ -1 = _ktiv-check 0= IF 0 EXIT THEN
    909 _ktiv-stage !
    NET-TX-OWNER-DEPTH @ 0= _ktiv-check 0= IF 0 EXIT THEN
    910 _ktiv-stage !
    NET-TX-OWNER-CORE @ -1 = _ktiv-check 0= IF 0 EXIT THEN
    911 _ktiv-stage !
    NET-TX-OWNER-TASK @ -1 = _ktiv-check 0= IF 0 EXIT THEN
    912 _ktiv-stage !
    _TC-LOCK-OWNER-CORE @ -1 = _ktiv-check 0= IF 0 EXIT THEN
    913 _ktiv-stage !
    _TC-LOCK-OWNER-TASK @ -1 = _ktiv-check ;

: _ktiv-report  ( -- )
    _ktiv-fail-stage @ 0= IF
        ." TLS INBOUND VERTICAL PASS " _ktiv-checks @ . CR
    ELSE
        ." TLS INBOUND VERTICAL FAIL " _ktiv-fail-stage @ . CR
    THEN
    TX-FLUSH ;

: _KTIV-RUN  ( -- )
    0 _ktiv-checks !
    0 _ktiv-stage !
    0 _ktiv-fail-stage !
    0 _ktiv-handler-hits !
    0 _ktiv-handler-polls !
    0 _ktiv-handler-cancels !
    0 _ktiv-handler-cleanups !
    0 _ktiv-source-calls !
    0 _ktiv-source-bytes !
    0 _ktiv-source-partials !
    0 _ktiv-source-expected-offset !
    0 _ktiv-accept-retries !
    0 _ktiv-accept-successes !
    DEPTH _ktiv-depth !

    _ktiv-setup 0= IF _ktiv-report EXIT THEN
    ." TLS INBOUND VERTICAL READY" CR TX-FLUSH KEY DROP

    1 _ktiv-connection-index !
    _ktiv-run-one 0= IF _ktiv-report EXIT THEN
    _ktiv-prepare-second 0= IF _ktiv-report EXIT THEN
    ." TLS INBOUND FIRST DONE" CR TX-FLUSH KEY DROP

    2 _ktiv-connection-index !
    _ktiv-run-one 0= IF _ktiv-report EXIT THEN
    _ktiv-teardown 0= IF _ktiv-report EXIT THEN

    990 _ktiv-stage !
    _ktiv-handler-hits @ 2 = _ktiv-check DROP
    _ktiv-handler-cleanups @ 2 = _ktiv-check DROP
    _ktiv-handler-polls @ 0= _ktiv-check DROP
    _ktiv-handler-cancels @ 0= _ktiv-check DROP
    _ktiv-source-calls @ 8 = _ktiv-check DROP
    _ktiv-source-partials @ 6 = _ktiv-check DROP
    _ktiv-source-bytes @ 50 = _ktiv-check DROP
    _ktiv-accept-successes @ 2 = _ktiv-check DROP
    DEPTH _ktiv-depth @ = _ktiv-check DROP
    _ktiv-report ;

_KTIV-RUN
