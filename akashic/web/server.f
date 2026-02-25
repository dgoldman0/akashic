\ server.f — HTTP server accept loop for KDOS / Megapad-64
\
\ Accept loop, connection handling, request→dispatch→response lifecycle.
\ Ties together request.f, response.f, and router.f into a runnable server.
\
\ All socket operations are vectored via XT variables so tests can
\ mock them without real network I/O.
\
\ Prefix: SRV-   (public API)
\         _SRV-  (internal helpers)
\
\ Load with:   REQUIRE server.f

REQUIRE ../web/request.f
REQUIRE ../web/response.f
REQUIRE ../web/router.f
REQUIRE ../utils/datetime.f
REQUIRE ../utils/string.f

PROVIDED akashic-web-server

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE SRV-ERR
1 CONSTANT SRV-E-SOCKET             \ SOCKET call failed
2 CONSTANT SRV-E-BIND               \ BIND failed
3 CONSTANT SRV-E-LISTEN             \ LISTEN failed
4 CONSTANT SRV-E-RECV               \ RECV returned 0 or error

: SRV-FAIL       ( code -- )  SRV-ERR ! ;
: SRV-OK?        ( -- flag )  SRV-ERR @ 0= ;
: SRV-CLEAR-ERR  ( -- )       0 SRV-ERR ! ;

\ =====================================================================
\  Server State
\ =====================================================================

VARIABLE _SRV-SD                    \ listener socket descriptor
VARIABLE _SRV-PORT                  \ listening port
VARIABLE _SRV-RUNNING               \ server running flag
VARIABLE _SRV-CONN-SD               \ current accepted connection sd

CREATE _SRV-RECV-BUF 8192 ALLOT    \ receive buffer
VARIABLE _SRV-RECV-LEN              \ bytes received

\ ── Connection Options ──

8192 CONSTANT SRV-MAX-REQUEST        \ max request size (bytes)
5000 CONSTANT SRV-TIMEOUT            \ recv timeout (ms) — future use
VARIABLE SRV-KEEP-ALIVE?             \ HTTP keep-alive (future)
0 SRV-KEEP-ALIVE? !

\ ── Logging ──

VARIABLE SRV-LOG-ENABLED
-1 SRV-LOG-ENABLED !                \ enabled by default

\ =====================================================================
\  Layer 0 — Vectored Socket Operations
\ =====================================================================
\
\  Each socket primitive is called via an XT variable.
\  Default implementations call the real KDOS words.
\  Tests can override these to simulate connections.

\ -- SOCKET --
: _SRV-SOCKET-DEFAULT  ( type -- sd | -1 )  SOCKET ;
VARIABLE _SRV-SOCKET-XT
' _SRV-SOCKET-DEFAULT _SRV-SOCKET-XT !

: _SRV-SOCKET  ( type -- sd | -1 )  _SRV-SOCKET-XT @ EXECUTE ;

\ -- BIND --
: _SRV-BIND-DEFAULT  ( sd port -- ior )  BIND ;
VARIABLE _SRV-BIND-XT
' _SRV-BIND-DEFAULT _SRV-BIND-XT !

: _SRV-BIND  ( sd port -- ior )  _SRV-BIND-XT @ EXECUTE ;

\ -- LISTEN --
: _SRV-LISTEN-DEFAULT  ( sd -- ior )  LISTEN ;
VARIABLE _SRV-LISTEN-XT
' _SRV-LISTEN-DEFAULT _SRV-LISTEN-XT !

: _SRV-LISTEN  ( sd -- ior )  _SRV-LISTEN-XT @ EXECUTE ;

\ -- SOCK-ACCEPT --
: _SRV-ACCEPT-DEFAULT  ( sd -- new-sd | -1 )  SOCK-ACCEPT ;
VARIABLE _SRV-ACCEPT-XT
' _SRV-ACCEPT-DEFAULT _SRV-ACCEPT-XT !

: _SRV-ACCEPT  ( sd -- new-sd | -1 )  _SRV-ACCEPT-XT @ EXECUTE ;

\ -- RECV --
: _SRV-RECV-DEFAULT  ( sd addr maxlen -- actual )  RECV ;
VARIABLE _SRV-RECV-XT
' _SRV-RECV-DEFAULT _SRV-RECV-XT !

: _SRV-RECV  ( sd addr maxlen -- actual )  _SRV-RECV-XT @ EXECUTE ;

\ -- CLOSE (connection) --
: _SRV-CLOSE-DEFAULT  ( sd -- )  CLOSE ;
VARIABLE _SRV-CLOSE-XT
' _SRV-CLOSE-DEFAULT _SRV-CLOSE-XT !

: _SRV-CLOSE  ( sd -- )  _SRV-CLOSE-XT @ EXECUTE ;

\ -- TCP-POLL --
: _SRV-POLL-DEFAULT  ( -- )  TCP-POLL ;
VARIABLE _SRV-POLL-XT
' _SRV-POLL-DEFAULT _SRV-POLL-XT !

: _SRV-POLL  ( -- )  _SRV-POLL-XT @ EXECUTE ;

\ -- NET-IDLE --
: _SRV-IDLE-DEFAULT  ( -- )  NET-IDLE ;
VARIABLE _SRV-IDLE-XT
' _SRV-IDLE-DEFAULT _SRV-IDLE-XT !

: _SRV-IDLE  ( -- )  _SRV-IDLE-XT @ EXECUTE ;

\ =====================================================================
\  Layer 1 — Logging
\ =====================================================================
\
\  SRV-LOG ( a u -- )
\    Print timestamped log line.  Respects SRV-LOG-ENABLED flag.

CREATE _SRV-LOG-BUF 32 ALLOT

: SRV-LOG  ( a u -- )
    SRV-LOG-ENABLED @ 0= IF 2DROP EXIT THEN
    ." [" DT-NOW-S _SRV-LOG-BUF 32 DT-ISO8601 _SRV-LOG-BUF SWAP TYPE ." ] "
    TYPE CR ;

\ SRV-LOG-REQUEST ( -- )
\   Log the current request: [timestamp] METHOD /path
: SRV-LOG-REQUEST  ( -- )
    SRV-LOG-ENABLED @ 0= IF EXIT THEN
    ." [" DT-NOW-S _SRV-LOG-BUF 32 DT-ISO8601
    _SRV-LOG-BUF SWAP TYPE ." ] "
    REQ-METHOD TYPE SPACE
    REQ-PATH TYPE CR ;

\ =====================================================================
\  Layer 2 — Socket Setup
\ =====================================================================
\
\  SRV-INIT ( port -- )
\    Create listening socket, bind to port, start listening.

: SRV-INIT  ( port -- )
    SRV-CLEAR-ERR
    DUP _SRV-PORT !

    \ Allocate a TCP socket
    SOCK-TYPE-TCP _SRV-SOCKET
    DUP -1 = IF
        DROP SRV-E-SOCKET SRV-FAIL EXIT
    THEN
    _SRV-SD !

    \ Bind to port
    _SRV-SD @ _SRV-PORT @ _SRV-BIND
    0<> IF
        SRV-E-BIND SRV-FAIL EXIT
    THEN

    \ Start listening
    _SRV-SD @ _SRV-LISTEN
    0<> IF
        SRV-E-LISTEN SRV-FAIL EXIT
    THEN

    -1 _SRV-RUNNING !

    \ Log startup
    SRV-LOG-ENABLED @ IF
        ." Listening on :" _SRV-PORT @ . CR
    THEN ;

\ =====================================================================
\  Layer 3 — Connection Handling
\ =====================================================================

\ _SRV-DISPATCH-XT — vectored dispatch hook.
\   Default: ROUTE-DISPATCH from router.f.
\   Can be replaced with MW-RUN when middleware.f is loaded.
VARIABLE _SRV-DISPATCH-XT
' ROUTE-DISPATCH _SRV-DISPATCH-XT !

: SRV-SET-DISPATCH  ( xt -- )  _SRV-DISPATCH-XT ! ;

\ SRV-HANDLE ( sd -- )
\   Handle one accepted connection:
\   1. Set response socket descriptor.
\   2. RECV request into buffer.
\   3. REQ-PARSE the received data.
\   4. Dispatch (via CATCH for safety).
\   5. CLOSE the accepted socket.

: SRV-HANDLE  ( sd -- )
    DUP _SRV-CONN-SD !

    \ Reset request and response state
    REQ-CLEAR
    RESP-CLEAR

    \ Set the response socket so RESP-SEND writes to this connection
    DUP RESP-SET-SD

    \ Poll-then-receive: RECV is non-blocking, so we must ensure
    \ TCP-POLL has ingested the data segment before reading.
    0                                        ( sd attempts )
    BEGIN
        _SRV-POLL                            \ process pending TCP segments
        OVER _SRV-RECV-BUF SRV-MAX-REQUEST _SRV-RECV  ( sd att actual )
        DUP 0> IF                            \ got data
            _SRV-RECV-LEN !
            DROP                             ( sd )
            TRUE                             \ break
        ELSE
            DROP 1+                          ( sd att+1 )
            DUP 100 >= IF                    \ ~2 s timeout at 20ms idle
                DROP 0 _SRV-RECV-LEN !      ( sd )
                TRUE                         \ break — 0 bytes
            ELSE
                _SRV-IDLE FALSE              \ retry
            THEN
        THEN
    UNTIL

    _SRV-RECV-LEN @ 1 < IF
        \ No data or timeout — close and skip
        DROP _SRV-CONN-SD @ _SRV-CLOSE EXIT
    THEN

    DROP   \ drop sd (already saved in _SRV-CONN-SD)

    \ Parse the request
    _SRV-RECV-BUF _SRV-RECV-LEN @ REQ-PARSE

    REQ-OK? 0= IF
        \ Parse failed — send 400 Bad Request
        400 RESP-ERROR
        _SRV-CONN-SD @ _SRV-CLOSE EXIT
    THEN

    \ Log the request
    SRV-LOG-REQUEST

    \ Dispatch handler, wrapped in CATCH
    _SRV-DISPATCH-XT @ CATCH
    IF
        \ Handler threw an exception — send 500 if not already sent
        RESP-CLEAR
        500 RESP-ERROR
    THEN

    \ Close the connection
    _SRV-CONN-SD @ _SRV-CLOSE ;

\ =====================================================================
\  Layer 4 — Accept Loop
\ =====================================================================

\ SRV-LOOP ( -- )
\   Main accept loop.  Runs until _SRV-RUNNING is cleared.
: SRV-LOOP  ( -- )
    BEGIN
        _SRV-RUNNING @ 0<>
    WHILE
        _SRV-SD @ _SRV-ACCEPT         ( new-sd | -1 )
        DUP -1 <> IF
            SRV-HANDLE
        ELSE
            DROP
        THEN
        _SRV-POLL
        _SRV-IDLE
    REPEAT ;

\ =====================================================================
\  Layer 5 — Lifecycle
\ =====================================================================

\ SRV-CLEANUP ( -- )
\   Close the listening socket, print shutdown message.
: SRV-CLEANUP  ( -- )
    _SRV-SD @ _SRV-CLOSE
    S" Server stopped." SRV-LOG ;

\ SERVE-STOP ( -- )
\   Signal the accept loop to stop.  Can be called from any handler.
: SERVE-STOP  ( -- )
    0 _SRV-RUNNING ! ;

\ SERVE ( port -- )
\   Top-level entry point.  Initialise, run accept loop, clean up.
: SERVE  ( port -- )
    SRV-INIT
    SRV-OK? 0= IF EXIT THEN
    SRV-LOOP
    SRV-CLEANUP ;

\ =====================================================================
\  Layer 6 — Direct Handle (for testing / single-request processing)
\ =====================================================================
\
\  SRV-HANDLE-BUF ( addr len -- )
\    Process a request from a pre-filled buffer (no socket I/O).
\    Useful for testing the full pipeline without a live network.

: SRV-HANDLE-BUF  ( addr len -- )
    REQ-CLEAR
    RESP-CLEAR
    2DUP REQ-PARSE
    2DROP
    REQ-OK? 0= IF
        400 RESP-ERROR EXIT
    THEN
    SRV-LOG-REQUEST
    _SRV-DISPATCH-XT @ CATCH
    IF
        RESP-CLEAR
        500 RESP-ERROR
    THEN ;
