\ tls-inbound-failure-vertical.f - inbound TLS failure/recovery capstone
\
\ The host defines _ktif-chain, _KTIF-CHAIN-U, and the 32-byte
\ little-endian d=3 _ktif-key before requiring this source.  It installs a
\ different raw-TCP peer at each READY gate and releases the gate with KEY.

PROVIDED ktif-real-server-failures

2500 CONSTANT _KTIF-NORMAL-TIMEOUT-MS
250 CONSTANT _KTIF-SHORT-TIMEOUT-MS
4096 CONSTANT _KTIF-EARLY-WIRE-BUDGET
32768 CONSTANT _KTIF-ACCEPT-STEP-LIMIT
32768 CONSTANT _KTIF-IO-STEP-LIMIT
32768 CONSTANT _KTIF-CLOSE-STEP-LIMIT
64 CONSTANT _KTIF-FINAL-POLL-LIMIT
5 CONSTANT _KTIF-PAYLOAD-U

VARIABLE _ktif-checks
VARIABLE _ktif-stage
VARIABLE _ktif-fail-stage
VARIABLE _ktif-depth

: _ktif-fail!  ( stage -- )
    _ktif-fail-stage @ 0= IF _ktif-fail-stage ! ELSE DROP THEN ;

: _ktif-check  ( flag -- flag )
    1 _ktif-checks +!
    DUP 0= IF _ktif-stage @ _ktif-fail! THEN ;

CREATE _ktif-alpn 8 ALLOT
CREATE _ktif-peer-ip 4 ALLOT
CREATE _ktif-peer-mac 6 ALLOT
CREATE _ktif-rx _KTIF-PAYLOAD-U ALLOT
CREATE _ktif-tx _KTIF-PAYLOAD-U ALLOT

CREATE _ktif-xio-service XIO-SERVICE-SIZE ALLOT
CREATE _ktif-listener-owner KDOSTLSL-SIZE ALLOT
CREATE _ktif-preclaim-port KDOSTLSP-SIZE ALLOT
CREATE _ktif-cancel-port KDOSTLSP-SIZE ALLOT
CREATE _ktif-timeout-port KDOSTLSP-SIZE ALLOT
CREATE _ktif-malformed-port KDOSTLSP-SIZE ALLOT
CREATE _ktif-success-port KDOSTLSP-SIZE ALLOT

\ Tokens are compared but never dereferenced.  This address is deliberately
\ disjoint from the listener owner and every shared port record.
VARIABLE _ktif-foreign-token

VARIABLE _ktif-credential-h1
VARIABLE _ktif-credential-generation
VARIABLE _ktif-credential-ior
VARIABLE _ktif-listener-sd
VARIABLE _ktif-listener-h1
VARIABLE _ktif-listener-generation
VARIABLE _ktif-listener-ior
VARIABLE _ktif-owner-generation
VARIABLE _ktif-old-owner-generation
VARIABLE _ktif-init-timeout

VARIABLE _ktif-current-port
VARIABLE _ktif-returned-port
VARIABLE _ktif-status
VARIABLE _ktif-ticks
VARIABLE _ktif-retries
VARIABLE _ktif-terminal-seen
VARIABLE _ktif-expected-terminal

VARIABLE _ktif-captured-ctx
VARIABLE _ktif-captured-ctx-generation
VARIABLE _ktif-captured-tcb
VARIABLE _ktif-captured-tcb-generation
VARIABLE _ktif-deadline

VARIABLE _ktif-alert-seen
VARIABLE _ktif-alert-error
VARIABLE _ktif-alert-result

VARIABLE _ktif-nio
VARIABLE _ktif-io-offset
VARIABLE _ktif-io-count
VARIABLE _ktif-io-status
VARIABLE _ktif-io-ticks
VARIABLE _ktif-close-status
VARIABLE _ktif-close-ticks

VARIABLE _ktif-close-ior
VARIABLE _ktif-close-attempts
VARIABLE _ktif-delete-ior
VARIABLE _ktif-delete-attempts

: _ktif-setup-strings  ( -- )
    _ktif-alpn 8 0 FILL
    S" http/1.1" _ktif-alpn SWAP MOVE
    _ktif-rx _KTIF-PAYLOAD-U 0 FILL
    _ktif-tx _KTIF-PAYLOAD-U 0 FILL
    S" pong!" _ktif-tx SWAP MOVE ;

: _ktif-live-sockets  ( -- count )
    0 SOCK-MAX 0 DO
        I SOCK-N SOCK.STATE @ SOCKST-FREE <> IF 1+ THEN
    LOOP ;

: _ktif-check-owner-idle  ( -- flag )
    _ktif-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-IDLE = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.STATE @
    XIO-STATE-RESET = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.CTX @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.CTX-GEN @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.BORROWED-PORT @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.STAGING-SOCKET @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.TERMINAL @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-xio-service XIO-ACTIVE? 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-xio-service XIOS.RETAINED @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ 0= _ktif-check ;

: _ktif-check-port-reset  ( port -- flag )
    DUP KDOSTLSP.STATE @ KDOSTLSP-STATE-RESET =
        _ktif-check 0= IF DROP 0 EXIT THEN
    DUP KDOSTLSP.SOCKET-SD @ 0=
        _ktif-check 0= IF DROP 0 EXIT THEN
    DUP KDOSNET-OWNER? 0=
        _ktif-check 0= IF DROP 0 EXIT THEN
    DROP -1 ;

: _ktif-check-port-reserved  ( port -- flag )
    DUP KDOSTLSP.STATE @ KDOSTLSP-STATE-RESERVED =
        _ktif-check 0= IF DROP 0 EXIT THEN
    DUP KDOSTLSP.SOCKET-SD @ 0=
        _ktif-check 0= IF DROP 0 EXIT THEN
    DUP KDOSNET-OWNER? 0=
        _ktif-check 0= IF DROP 0 EXIT THEN
    DROP -1 ;

: _ktif-check-port-closed  ( port -- flag )
    DUP KDOSTLSP.STATE @ KDOSTLSP-STATE-CLOSED =
        _ktif-check 0= IF DROP 0 EXIT THEN
    DUP KDOSTLSP.SOCKET-SD @ 0=
        _ktif-check 0= IF DROP 0 EXIT THEN
    DUP KDOSNET-OWNER? 0=
        _ktif-check 0= IF DROP 0 EXIT THEN
    DROP -1 ;

: _ktif-owner-init  ( timeout-ms -- flag )
    _ktif-init-timeout !
    _ktif-xio-service _ktif-listener-sd @ _ktif-listener-h1 @
    _ktif-listener-generation @ _ktif-init-timeout @
    _KTIF-EARLY-WIRE-BUDGET
    _ktif-listener-owner KDOSTLSL-INIT KDOSTLSL-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.TIMEOUT-MS @
    _ktif-init-timeout @ = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.OWNER-GEN @
    DUP _ktif-owner-generation ! 0> _ktif-check ;

: _ktif-setup-network  ( -- flag )
    10 _ktif-stage !
    1 TLS-CREDENTIAL-POOL-INIT 0= _ktif-check 0= IF 0 EXIT THEN
    11 _ktif-stage !
    _ktif-chain _KTIF-CHAIN-U _ktif-key TLS-CREDENTIAL-PROVISION
    _ktif-credential-ior !
    _ktif-credential-generation !
    _ktif-credential-h1 !
    _ktif-credential-ior @ 0= _ktif-check 0= IF 0 EXIT THEN
    _ktif-credential-h1 @ 0> _ktif-check 0= IF 0 EXIT THEN
    _ktif-credential-generation @ 0> _ktif-check 0= IF 0 EXIT THEN

    TCP-INIT-ALL ARP-CLEAR
    10 0 0 2 IP-SET
    255 255 255 0 NET-MASK IP!
    0 0 0 0 GW-IP IP!
    10 0 0 1 _ktif-peer-ip IP!
    _ktif-peer-mac 6 170 FILL
    _ktif-peer-ip _ktif-peer-mac ARP-INSERT

    12 _ktif-stage !
    SOCK-TYPE-TLS SOCKET DUP _ktif-listener-sd !
    -1 <> _ktif-check 0= IF 0 EXIT THEN
    13 _ktif-stage !
    _ktif-listener-sd @ 443 BIND 0=
        _ktif-check 0= IF 0 EXIT THEN
    14 _ktif-stage !
    _ktif-listener-sd @
    _ktif-credential-h1 @ _ktif-credential-generation @
    _ktif-alpn 8 _KTIF-EARLY-WIRE-BUDGET
    _KTIF-NORMAL-TIMEOUT-MS TLS-LISTEN
    _ktif-listener-ior !
    _ktif-listener-generation !
    _ktif-listener-h1 !
    _ktif-listener-ior @ 0= _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-h1 @ 0> _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-generation @ 0> _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-sd @ SOCK-TLS-LISTENER?
        _ktif-check 0= IF 0 EXIT THEN
    -1 ;

: _ktif-setup-owner  ( -- flag )
    20 _ktif-stage !
    _ktif-xio-service XIO-SERVICE-INIT XIO-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    21 _ktif-stage !
    _ktif-preclaim-port KDOSTLSP-INIT KDOSTLSP-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-cancel-port KDOSTLSP-INIT KDOSTLSP-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-timeout-port KDOSTLSP-INIT KDOSTLSP-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-malformed-port KDOSTLSP-INIT KDOSTLSP-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-success-port KDOSTLSP-INIT KDOSTLSP-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    22 _ktif-stage !
    _KTIF-NORMAL-TIMEOUT-MS _ktif-owner-init
        0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.REQUEST-GEN @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-check-owner-idle ;

: _ktif-setup  ( -- flag )
    _ktif-setup-strings
    _ktif-setup-network 0= IF 0 EXIT THEN
    _ktif-setup-owner ;

: _ktif-submit-current  ( -- flag )
    0 _ktif-returned-port !
    _ktif-current-port @ _ktif-listener-owner KDOSTLSL-ACCEPT
    DUP _ktif-status ! KDOSTLSL-S-OK = ;

: _ktif-step  ( -- )
    _ktif-listener-owner KDOSTLSL-STEP
    _ktif-status ! _ktif-returned-port ! ;

: _ktif-retry-current  ( -- flag )
    _ktif-returned-port @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-current-port @ _ktif-check-port-reset 0= IF 0 EXIT THEN
    _ktif-check-owner-idle 0= IF 0 EXIT THEN
    1 _ktif-retries +!
    _ktif-submit-current _ktif-check ;

: _ktif-check-captured-authority-live  ( -- flag )
    _ktif-listener-owner _KDOSTLSL.CTX @
    _ktif-captured-ctx @ = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.CTX-GEN @
    _ktif-captured-ctx-generation @ =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX-MEMBER?
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX-CLAIMED?
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.GENERATION @
    _ktif-captured-ctx-generation @ =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.STATE @ TLSS-HANDSHAKE =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.ROLE @ TLS-ROLE-SERVER =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.SOCKET-OWNER @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.TCB @
    _ktif-captured-tcb @ = _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.TCB-GENERATION @
    _ktif-captured-tcb-generation @ =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB-MEMBER?
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.GENERATION @
    _ktif-captured-tcb-generation @ =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.STATE @ TCPS-ESTABLISHED =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ _ktif-captured-tcb-generation @
    _ktif-captured-ctx @ TCB-ATTACHED-TO?
        _ktif-check ;

: _ktif-capture-live  ( -- flag )
    _ktif-listener-owner _KDOSTLSL.CTX @
    DUP _ktif-captured-ctx ! 0<> _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.CTX-GEN @
    DUP _ktif-captured-ctx-generation !
    0> _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.TCB @
    DUP _ktif-captured-tcb ! 0<> _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.TCB-GENERATION @
    DUP _ktif-captured-tcb-generation !
    0> _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-CLIENT-HELLO =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.DEADLINE-MS @
    DUP _ktif-deadline ! 0<> _ktif-check 0= IF 0 EXIT THEN
    _ktif-current-port @ _ktif-check-port-reserved 0= IF 0 EXIT THEN
    _ktif-check-captured-authority-live ;

: _ktif-drive-to-claim  ( -- flag )
    0 _ktif-ticks !
    BEGIN
        _ktif-listener-owner _KDOSTLSL.CTX @ 0=
        _ktif-ticks @ _KTIF-ACCEPT-STEP-LIMIT < AND
    WHILE
        _ktif-step
        _ktif-status @ KDOSTLSL-S-PENDING = IF
            _ktif-returned-port @ 0=
                _ktif-check 0= IF 0 EXIT THEN
            _ktif-listener-owner _KDOSTLSL.CTX @
            _ktif-listener-owner _KDOSTLSL.CTX-GEN @ OR 0= IF
                _ktif-listener-owner _KDOSTLSL.XIO-OP
                XIOO.DEADLINE-MS @ 0=
                    _ktif-check 0= IF 0 EXIT THEN
            THEN
        ELSE
            _ktif-status @ KDOSTLSL-S-RETRY = IF
                _ktif-retry-current 0= IF 0 EXIT THEN
            ELSE
                0 _ktif-check DROP 0 EXIT
            THEN
        THEN
        1 _ktif-ticks +!
    REPEAT
    _ktif-listener-owner _KDOSTLSL.CTX @ 0<>
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-capture-live ;

: _ktif-drive-terminal  ( expected-status -- flag )
    _ktif-expected-terminal !
    0 _ktif-terminal-seen !
    0 _ktif-ticks !
    BEGIN
        _ktif-terminal-seen @ 0=
        _ktif-ticks @ _KTIF-ACCEPT-STEP-LIMIT < AND
    WHILE
        _ktif-step
        _ktif-status @ KDOSTLSL-S-PENDING = IF
            _ktif-returned-port @ 0=
                _ktif-check 0= IF 0 EXIT THEN
        ELSE
            _ktif-status @ _ktif-expected-terminal @ =
                _ktif-check 0= IF 0 EXIT THEN
            _ktif-returned-port @ 0=
                _ktif-check 0= IF 0 EXIT THEN
            -1 _ktif-terminal-seen !
        THEN
        1 _ktif-ticks +!
    REPEAT
    _ktif-terminal-seen @ _ktif-check 0= IF 0 EXIT THEN
    _ktif-status @ _ktif-expected-terminal @ = _ktif-check ;

: _ktif-check-captured-retired  ( -- flag )
    _ktif-captured-ctx @ TLS-CTX-MEMBER?
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX-CLAIMED? 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.STATE @ TLSS-NONE =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.TCB @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.TCB-GENERATION @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-ctx @ TLS-CTX.SOCKET-OWNER @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB-MEMBER?
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.GENERATION @
    _ktif-captured-tcb-generation @ =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.STATE @ TCPS-CLOSED =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.OWNER @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.AUTH-STATE @ TCP-AUTH-NONE =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.PARENT-H1 @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-captured-tcb @ TCB.PARENT-GEN @ 0=
        _ktif-check ;

: _ktif-check-failure-cleanup  ( port -- flag )
    _ktif-check-port-reset 0= IF 0 EXIT THEN
    _ktif-check-owner-idle 0= IF 0 EXIT THEN
    _TLS-ANY-CONTEXT-LIVE? 0=
        _ktif-check 0= IF 0 EXIT THEN
    TCB-USAGE DROP 1 = _ktif-check 0= IF 0 EXIT THEN
    _ktif-live-sockets 1 = _ktif-check ;

: _ktif-run-preclaim-cancel  ( -- flag )
    100 _ktif-stage !
    _ktif-preclaim-port _ktif-current-port !
    _ktif-submit-current _ktif-check 0= IF 0 EXIT THEN
    _ktif-preclaim-port _ktif-check-port-reserved 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-LISTENER-POLL =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.CTX @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.CTX-GEN @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.DEADLINE-MS @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.STATE @
    XIO-STATE-ACTIVE = _ktif-check 0= IF 0 EXIT THEN
    _ktif-xio-service XIOS.ACTIVE @
    _ktif-listener-owner _KDOSTLSL.XIO-OP =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.FLAGS @
    _XIO-F-STARTED AND 0= _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner KDOSTLSL-CANCEL
    KDOSTLSL-S-PENDING = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-CLEANUP = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.STATE @
    XIO-STATE-ACTIVE = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.PENDING-TERMINAL @
    XIO-STATE-CANCELLED = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.ERROR @
    XIO-E-CANCELLED = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP
    XIO-CLEANUP-PENDING? _ktif-check 0= IF 0 EXIT THEN
    110 _ktif-stage !
    KDOSTLSL-S-CANCELLED _ktif-drive-terminal 0= IF 0 EXIT THEN
    _ktif-preclaim-port _ktif-check-failure-cleanup ;

: _ktif-run-claimed-cancel  ( -- flag )
    200 _ktif-stage !
    _ktif-cancel-port _ktif-current-port !
    _ktif-submit-current _ktif-check 0= IF 0 EXIT THEN
    _ktif-drive-to-claim 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ 0= _ktif-check 0= IF 0 EXIT THEN

    210 _ktif-stage !
    _ktif-foreign-token KDOSNET-CLAIM KDOSNET-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ _ktif-foreign-token =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner KDOSTLSL-CANCEL
    KDOSTLSL-S-PENDING = _ktif-check 0= IF 0 EXIT THEN
    _ktif-step
    _ktif-status @ KDOSTLSL-S-PENDING =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-returned-port @ 0= _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-CLEANUP = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP
    XIO-CLEANUP-PENDING? _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.PENDING-TERMINAL @
    XIO-STATE-CANCELLED = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.STATE @
    XIO-STATE-ACTIVE = _ktif-check 0= IF 0 EXIT THEN
    _ktif-cancel-port _ktif-check-port-reserved 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.DEADLINE-MS @
    _ktif-deadline @ = _ktif-check 0= IF 0 EXIT THEN
    _ktif-check-captured-authority-live 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ _ktif-foreign-token =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-foreign-token KDOSNET-RELEASE KDOSNET-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ 0= _ktif-check 0= IF 0 EXIT THEN

    220 _ktif-stage !
    KDOSTLSL-S-CANCELLED _ktif-drive-terminal 0= IF 0 EXIT THEN
    _ktif-check-captured-retired 0= IF 0 EXIT THEN
    _ktif-cancel-port _ktif-check-failure-cleanup ;

: _ktif-reinit-timeout-owner  ( -- flag )
    300 _ktif-stage !
    _ktif-listener-owner _KDOSTLSL.OWNER-GEN @
    _ktif-old-owner-generation !
    _KTIF-SHORT-TIMEOUT-MS _ktif-owner-init 0= IF 0 EXIT THEN
    _ktif-owner-generation @ _ktif-old-owner-generation @ 1+ =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.REQUEST-GEN @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-check-owner-idle ;

: _ktif-run-timeout  ( -- flag )
    320 _ktif-stage !
    _ktif-timeout-port _ktif-current-port !
    _ktif-submit-current _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.DEADLINE-MS @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-drive-to-claim 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.DEADLINE-MS @
    DUP _ktif-deadline ! 0<> _ktif-check 0= IF 0 EXIT THEN
    330 _ktif-stage !
    KDOSTLSL-S-TIMED-OUT _ktif-drive-terminal 0= IF 0 EXIT THEN
    _ktif-check-captured-retired 0= IF 0 EXIT THEN
    _ktif-timeout-port _ktif-check-failure-cleanup ;

: _ktif-reinit-normal-owner  ( -- flag )
    400 _ktif-stage !
    _ktif-listener-owner _KDOSTLSL.OWNER-GEN @
    _ktif-old-owner-generation !
    _KTIF-NORMAL-TIMEOUT-MS _ktif-owner-init 0= IF 0 EXIT THEN
    _ktif-owner-generation @ _ktif-old-owner-generation @ 1+ =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.REQUEST-GEN @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-check-owner-idle ;

: _ktif-sample-alert  ( -- flag )
    _ktif-listener-owner _KDOSTLSL.XIO-OP
    XIO-CLEANUP-PENDING? 0= IF -1 EXIT THEN
    _ktif-alert-seen @ IF -1 EXIT THEN
    \ Empty-backlog retries also settle through XIO cleanup.  Only sample
    \ diagnostics once the real malformed-handshake outcome is retained.
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.ERROR @
    KDOSTLSL-E-HANDSHAKE-ALERT <> IF -1 EXIT THEN
    430 _ktif-stage !
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.ERROR @
    DUP _ktif-alert-error !
    KDOSTLSL-E-HANDSHAKE-ALERT =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.RESULT @
    DUP _ktif-alert-result !
    TLS-AD-DECODE-ERROR = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.CLEANUP-ERROR @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.XIO-OP XIOO.PENDING-TERMINAL @
    XIO-STATE-FAILED = _ktif-check 0= IF 0 EXIT THEN
    _ktif-listener-owner _KDOSTLSL.PHASE @
    _KDOSTLSL-PHASE-CLEANUP = _ktif-check 0= IF 0 EXIT THEN
    -1 _ktif-alert-seen !
    -1 ;

: _ktif-run-malformed  ( -- flag )
    420 _ktif-stage !
    0 _ktif-alert-seen !
    0 _ktif-terminal-seen !
    0 _ktif-ticks !
    _ktif-malformed-port _ktif-current-port !
    _ktif-submit-current _ktif-check 0= IF 0 EXIT THEN
    BEGIN
        _ktif-terminal-seen @ 0=
        _ktif-ticks @ _KTIF-ACCEPT-STEP-LIMIT < AND
    WHILE
        _ktif-step
        _ktif-sample-alert 0= IF 0 EXIT THEN
        _ktif-status @ KDOSTLSL-S-PENDING = IF
            _ktif-returned-port @ 0=
                _ktif-check 0= IF 0 EXIT THEN
        ELSE
            _ktif-status @ KDOSTLSL-S-RETRY = IF
                _ktif-retry-current 0= IF 0 EXIT THEN
            ELSE
                _ktif-status @ KDOSTLSL-S-LOWER =
                    _ktif-check 0= IF 0 EXIT THEN
                _ktif-returned-port @ 0=
                    _ktif-check 0= IF 0 EXIT THEN
                -1 _ktif-terminal-seen !
            THEN
        THEN
        1 _ktif-ticks +!
    REPEAT
    440 _ktif-stage !
    _ktif-terminal-seen @ _ktif-check 0= IF 0 EXIT THEN
    _ktif-alert-seen @ _ktif-check 0= IF 0 EXIT THEN
    _ktif-alert-error @ KDOSTLSL-E-HANDSHAKE-ALERT =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-alert-result @ TLS-AD-DECODE-ERROR =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-malformed-port _ktif-check-failure-cleanup ;

: _ktif-drive-success  ( -- flag )
    500 _ktif-stage !
    0 _ktif-terminal-seen !
    0 _ktif-ticks !
    0 _ktif-nio !
    _ktif-success-port _ktif-current-port !
    _ktif-success-port _ktif-check-port-reset 0= IF 0 EXIT THEN
    _ktif-submit-current _ktif-check 0= IF 0 EXIT THEN
    BEGIN
        _ktif-terminal-seen @ 0=
        _ktif-ticks @ _KTIF-ACCEPT-STEP-LIMIT < AND
    WHILE
        _ktif-step
        _ktif-status @ KDOSTLSL-S-PENDING = IF
            _ktif-returned-port @ 0=
                _ktif-check 0= IF 0 EXIT THEN
        ELSE
            _ktif-status @ KDOSTLSL-S-RETRY = IF
                _ktif-retry-current 0= IF 0 EXIT THEN
            ELSE
                _ktif-status @ KDOSTLSL-S-OK =
                    _ktif-check 0= IF 0 EXIT THEN
                _ktif-returned-port @ DUP _ktif-nio ! 0<>
                    _ktif-check 0= IF 0 EXIT THEN
                -1 _ktif-terminal-seen !
            THEN
        THEN
        1 _ktif-ticks +!
    REPEAT
    _ktif-terminal-seen @ _ktif-check 0= IF 0 EXIT THEN
    _ktif-status @ KDOSTLSL-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-nio @ _ktif-success-port KDOSTLSP.PORT =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-success-port KDOSTLSP.STATE @ KDOSTLSP-STATE-OPEN =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-success-port KDOSTLSP.SOCKET-SD @ 0<>
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-success-port KDOSNET-OWNER? 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-nio @ NIO.OPEN-STATE @ NIO-OPEN-STATE-OPEN =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-check-owner-idle ;

: _ktif-receive-ping  ( -- flag )
    520 _ktif-stage !
    0 _ktif-io-offset !
    0 _ktif-io-ticks !
    BEGIN
        _ktif-io-offset @ _KTIF-PAYLOAD-U <
        _ktif-io-ticks @ _KTIF-IO-STEP-LIMIT < AND
    WHILE
        _ktif-rx _ktif-io-offset @ +
        _KTIF-PAYLOAD-U _ktif-io-offset @ - _ktif-nio @ NIO-RECV
        _ktif-io-status ! _ktif-io-count !
        _ktif-io-status @ NIO-S-OK =
            _ktif-check 0= IF 0 EXIT THEN
        _ktif-io-count @ 0< 0=
            _ktif-check 0= IF 0 EXIT THEN
        _ktif-io-count @
        _KTIF-PAYLOAD-U _ktif-io-offset @ - <=
            _ktif-check 0= IF 0 EXIT THEN
        _ktif-io-count @ _ktif-io-offset +!
        _ktif-io-count @ 0= IF _ktif-nio @ NIO-POLL THEN
        1 _ktif-io-ticks +!
    REPEAT
    _ktif-io-offset @ _KTIF-PAYLOAD-U =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-rx _KTIF-PAYLOAD-U S" ping?" COMPARE 0= _ktif-check ;

: _ktif-send-pong  ( -- flag )
    530 _ktif-stage !
    0 _ktif-io-offset !
    0 _ktif-io-ticks !
    BEGIN
        _ktif-io-offset @ _KTIF-PAYLOAD-U <
        _ktif-io-ticks @ _KTIF-IO-STEP-LIMIT < AND
    WHILE
        _ktif-tx _ktif-io-offset @ +
        _KTIF-PAYLOAD-U _ktif-io-offset @ - _ktif-nio @ NIO-SEND
        _ktif-io-status ! _ktif-io-count !
        _ktif-io-status @ NIO-S-OK =
            _ktif-check 0= IF 0 EXIT THEN
        _ktif-io-count @ 0< 0=
            _ktif-check 0= IF 0 EXIT THEN
        _ktif-io-count @
        _KTIF-PAYLOAD-U _ktif-io-offset @ - <=
            _ktif-check 0= IF 0 EXIT THEN
        _ktif-io-count @ _ktif-io-offset +!
        _ktif-io-count @ 0= IF _ktif-nio @ NIO-POLL THEN
        1 _ktif-io-ticks +!
    REPEAT
    _ktif-io-offset @ _KTIF-PAYLOAD-U = _ktif-check ;

: _ktif-close-success  ( -- flag )
    540 _ktif-stage !
    0 _ktif-close-ticks !
    _ktif-nio @ NIO-CLOSE-START DUP _ktif-close-status !
    DUP NIO-S-OK = SWAP NIO-S-PENDING = OR
        _ktif-check 0= IF 0 EXIT THEN
    BEGIN
        _ktif-close-status @ NIO-S-PENDING =
        _ktif-close-ticks @ _KTIF-CLOSE-STEP-LIMIT < AND
    WHILE
        _ktif-nio @ NIO-CLOSE-POLL _ktif-close-status !
        1 _ktif-close-ticks +!
    REPEAT
    _ktif-close-status @ NIO-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-nio @ NIO.OPEN-STATE @ NIO-OPEN-STATE-CLOSED =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-nio @ NIO.CLOSE-STATE @ NIO-CLOSE-STATE-CLOSED =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-success-port _ktif-check-port-closed 0= IF 0 EXIT THEN
    _ktif-success-port KDOSTLSP.LAST-ERROR @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-success-port KDOSTLSP.CLEANUP-ERROR @ 0=
        _ktif-check 0= IF 0 EXIT THEN
    KDOSNET-OWNER@ 0= _ktif-check ;

: _ktif-service-network-once  ( -- flag )
    _ktif-listener-owner ['] TCP-POLL KDOSNET-WITH
    KDOSNET-S-OK = SWAP 0= AND
    SWAP KDOSNET-S-OK = AND
        _ktif-check ;

: _ktif-service-final-ack  ( -- flag )
    550 _ktif-stage !
    0 _ktif-close-ticks !
    BEGIN
        TCB-USAGE DROP 1 >
        _ktif-close-ticks @ _KTIF-FINAL-POLL-LIMIT < AND
    WHILE
        _ktif-service-network-once 0= IF 0 EXIT THEN
        1 _ktif-close-ticks +!
    REPEAT
    551 _ktif-stage !
    KDOSNET-OWNER@ 0= _ktif-check 0= IF 0 EXIT THEN
    552 _ktif-stage !
    _TLS-ANY-CONTEXT-LIVE? 0=
        _ktif-check 0= IF 0 EXIT THEN
    553 _ktif-stage !
    TCB-USAGE DROP 1 = _ktif-check 0= IF 0 EXIT THEN
    554 _ktif-stage !
    _ktif-live-sockets 1 = _ktif-check ;

: _ktif-run-recovery  ( -- flag )
    _ktif-drive-success 0= IF 0 EXIT THEN
    _ktif-receive-ping 0= IF 0 EXIT THEN
    _ktif-send-pong 0= IF 0 EXIT THEN
    _ktif-close-success 0= IF 0 EXIT THEN
    _ktif-service-final-ack ;

: _ktif-close-retryable?  ( ior -- flag )
    CASE
        TLS-E-BUSY OF -1 ENDOF
        TCP-ACCEPT-E-BUSY OF -1 ENDOF
        TLS-E-WOULD-BLOCK OF -1 ENDOF
        0 SWAP
    ENDCASE ;

: _ktif-close-listener  ( -- flag )
    0 _ktif-close-attempts !
    _ktif-listener-sd @ CLOSE-TRY _ktif-close-ior !
    BEGIN
        _ktif-close-ior @ _ktif-close-retryable?
        _ktif-close-attempts @ 64 < AND
    WHILE
        TCP-POLL
        _ktif-listener-sd @ CLOSE-TRY _ktif-close-ior !
        1 _ktif-close-attempts +!
    REPEAT
    _ktif-close-ior @ 0= ;

: _ktif-delete-credential  ( -- flag )
    0 _ktif-delete-attempts !
    _ktif-credential-h1 @ _ktif-credential-generation @
        TLS-CREDENTIAL-DELETE _ktif-delete-ior !
    BEGIN
        _ktif-delete-ior @ TLS-CREDENTIAL-E-BUSY =
        _ktif-delete-attempts @ 64 < AND
    WHILE
        _ktif-credential-h1 @ _ktif-credential-generation @
            TLS-CREDENTIAL-DELETE _ktif-delete-ior !
        1 _ktif-delete-attempts +!
    REPEAT
    _ktif-delete-ior @ 0= ;

: _ktif-report-live-tcbs  ( -- )
    /TCP-MAX-CONN 0 DO
        I TCB-N DUP TCB.STATE @ TCPS-CLOSED <>
        OVER TCB.AUTH-STATE @ TCP-AUTH-NONE <> OR IF
            ." KTIF LIVE TCB " I .
            ." STATE " DUP TCB.STATE @ .
            ." AUTH " DUP TCB.AUTH-STATE @ .
            ." OWNER " DUP TCB.OWNER @ .
            ." GEN " DUP TCB.GENERATION @ .
            ." PARENT " DUP TCB.PARENT-H1 @ .
            ." PARENT-GEN " DUP TCB.PARENT-GEN @ . CR
        THEN
        DROP
    LOOP ;

: _ktif-teardown  ( -- flag )
    900 _ktif-stage !
    _ktif-listener-owner _KDOSTLSL.REQUEST-GEN @ 2 >=
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-owner-generation @ 3 >= _ktif-check 0= IF 0 EXIT THEN
    _ktif-preclaim-port _ktif-check-port-reset 0= IF 0 EXIT THEN
    _ktif-cancel-port _ktif-check-port-reset 0= IF 0 EXIT THEN
    _ktif-timeout-port _ktif-check-port-reset 0= IF 0 EXIT THEN
    _ktif-malformed-port _ktif-check-port-reset 0= IF 0 EXIT THEN
    _ktif-success-port _ktif-check-port-closed 0= IF 0 EXIT THEN
    _ktif-check-owner-idle 0= IF 0 EXIT THEN
    _ktif-listener-owner KDOSTLSL-FINI KDOSTLSL-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-xio-service XIO-SERVICE-FINI XIO-S-OK =
        _ktif-check 0= IF 0 EXIT THEN
    _ktif-close-listener _ktif-check 0= IF 0 EXIT THEN
    _ktif-delete-credential _ktif-check 0= IF 0 EXIT THEN

    901 _ktif-stage !
    _ktif-live-sockets 0= _ktif-check 0= IF 0 EXIT THEN
    902 _ktif-stage !
    _TLS-ANY-CONTEXT-LIVE? 0= _ktif-check 0= IF 0 EXIT THEN
    903 _ktif-stage !
    _TCP-ANY-TCB-LIVE? IF
        _ktif-report-live-tcbs 0
    ELSE
        -1
    THEN _ktif-check 0= IF 0 EXIT THEN
    904 _ktif-stage !
    TLS-CREDENTIAL-ACTIVE @ 0= _ktif-check 0= IF 0 EXIT THEN
    905 _ktif-stage !
    KDOSNET-OWNER@ 0= _ktif-check 0= IF 0 EXIT THEN
    906 _ktif-stage !
    TLS-OWNER-DEPTH @ 0= _ktif-check 0= IF 0 EXIT THEN
    907 _ktif-stage !
    TLS-OWNER-CORE @ -1 = _ktif-check 0= IF 0 EXIT THEN
    908 _ktif-stage !
    TLS-OWNER-TASK @ -1 = _ktif-check 0= IF 0 EXIT THEN
    909 _ktif-stage !
    NET-TX-OWNER-DEPTH @ 0= _ktif-check 0= IF 0 EXIT THEN
    910 _ktif-stage !
    NET-TX-OWNER-CORE @ -1 = _ktif-check 0= IF 0 EXIT THEN
    911 _ktif-stage !
    NET-TX-OWNER-TASK @ -1 = _ktif-check 0= IF 0 EXIT THEN
    912 _ktif-stage !
    _TC-LOCK-OWNER-CORE @ -1 = _ktif-check 0= IF 0 EXIT THEN
    913 _ktif-stage !
    _TC-LOCK-OWNER-TASK @ -1 = _ktif-check ;

: _ktif-report  ( -- )
    _ktif-fail-stage @ 0= IF
        ." TLS INBOUND FAILURE PASS " _ktif-checks @ . CR
    ELSE
        ." TLS INBOUND FAILURE FAIL " _ktif-fail-stage @ . CR
    THEN
    TX-FLUSH ;

: _KTIF-RUN  ( -- )
    0 _ktif-checks !
    0 _ktif-stage !
    0 _ktif-fail-stage !
    0 _ktif-retries !
    DEPTH _ktif-depth !

    _ktif-setup 0= IF _ktif-report EXIT THEN
    _ktif-run-preclaim-cancel 0= IF _ktif-report EXIT THEN

    ." TLS INBOUND FAILURE CANCEL READY" CR TX-FLUSH KEY DROP
    _ktif-run-claimed-cancel 0= IF _ktif-report EXIT THEN
    ." TLS INBOUND FAILURE CANCEL DONE" CR TX-FLUSH

    _ktif-reinit-timeout-owner 0= IF _ktif-report EXIT THEN
    ." TLS INBOUND FAILURE TIMEOUT READY" CR TX-FLUSH KEY DROP
    _ktif-run-timeout 0= IF _ktif-report EXIT THEN
    ." TLS INBOUND FAILURE TIMEOUT DONE" CR TX-FLUSH

    _ktif-reinit-normal-owner 0= IF _ktif-report EXIT THEN
    ." TLS INBOUND FAILURE MALFORMED READY" CR TX-FLUSH KEY DROP
    _ktif-run-malformed 0= IF _ktif-report EXIT THEN
    ." TLS INBOUND FAILURE MALFORMED DONE" CR TX-FLUSH

    ." TLS INBOUND FAILURE RECOVERY READY" CR TX-FLUSH KEY DROP
    _ktif-run-recovery 0= IF _ktif-report EXIT THEN
    _ktif-teardown 0= IF _ktif-report EXIT THEN

    990 _ktif-stage !
    _ktif-alert-seen @ _ktif-check DROP
    _ktif-retries @ 0< 0= _ktif-check DROP
    DEPTH _ktif-depth @ = _ktif-check DROP
    _ktif-report ;

_KTIF-RUN
