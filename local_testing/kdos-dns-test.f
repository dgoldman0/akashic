\ Focused offline contracts for the caller-owned KDOS DNS exchange adapter.
PROVIDED akashic-kdos-dns-contracts

VARIABLE _kdt-fails
VARIABLE _kdt-checks
VARIABLE _kdt-depth
VARIABLE _kdt-now
VARIABLE _kdt-step-a
VARIABLE _kdt-ra
VARIABLE _kdt-ru
VARIABLE _kdt-rs
VARIABLE _kdt-tcb
VARIABLE _kdt-nested-start-status
VARIABLE _kdt-nested-poll-status

CREATE _kdt-a-allocation KDOSDNS-SIZE 7 + ALLOT
_kdt-a-allocation 7 + -8 AND CONSTANT _kdt-a
CREATE _kdt-b-allocation KDOSDNS-SIZE 7 + ALLOT
_kdt-b-allocation 7 + -8 AND CONSTANT _kdt-b
CREATE _kdt-response-a 1024 ALLOT
CREATE _kdt-response-b 1024 ALLOT
CREATE _kdt-query 64 ALLOT
CREATE _kdt-root-query 32 ALLOT
CREATE _kdt-wire-response 64 ALLOT
CREATE _kdt-server 4 ALLOT

: _kdt-assert  ( flag -- )
    1 _kdt-checks +!
    0= IF
        1 _kdt-fails +!
        ." KDOS DNS ASSERT " _kdt-checks @ . CR
    THEN ;

: _kdt-stack  ( -- )
    DEPTH DUP _kdt-depth @ <> IF
        ." KDOS DNS STACK " _kdt-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _kdt-depth @ = _kdt-assert ;

: _kdt-byte?  ( address length byte -- flag )
    >R
    BEGIN
        DUP
    WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _kdt-response!  ( adapter -- )
    KDOSDNS-RESPONSE$ _kdt-rs ! _kdt-ru ! _kdt-ra ! ;

: _kdt-build-query  ( -- )
    _kdt-query 64 0 FILL
    0xBEEF _kdt-query NW16!
    0x0100 _kdt-query 2 + NW16!
    1 _kdt-query 4 + NW16!
    8 _kdt-query 12 + C!
    S" _DnsTest" _kdt-query 13 + SWAP CMOVE
    7 _kdt-query 21 + C!
    S" Example" _kdt-query 22 + SWAP CMOVE
    0 _kdt-query 29 + C!
    16 _kdt-query 30 + NW16!
    1 _kdt-query 32 + NW16! ;

: _kdt-build-root-query  ( -- )
    _kdt-root-query 32 0 FILL
    0x1234 _kdt-root-query NW16!
    0x0100 _kdt-root-query 2 + NW16!
    1 _kdt-root-query 4 + NW16!
    0 _kdt-root-query 12 + C!
    16 _kdt-root-query 13 + NW16!
    1 _kdt-root-query 15 + NW16! ;

: _kdt-build-response  ( flags -- )
    _kdt-query _kdt-wire-response 34 CMOVE
    _kdt-wire-response 2 + NW16! ;

: _kdt-now@  ( adapter -- ms )
    DROP _kdt-now @ ;

: _kdt-now-throw  ( adapter -- ms )
    DROP -908 THROW ;

: _kdt-step-pending  ( adapter -- status )
    DROP KDOSDNS-S-PENDING ;

: _kdt-step-throw  ( adapter -- status )
    DROP -909 THROW ;

: _kdt-step-invalid-ok  ( adapter -- status )
    DROP KDOSDNS-S-OK ;

: _kdt-now-reenter-start  ( adapter -- ms )
    DROP
    _kdt-query 34 _kdt-server _kdt-a KDOSDNS-START
        _kdt-nested-start-status !
    0 ;

: _kdt-step-reenter-poll  ( adapter -- status )
    DUP KDOSDNS-POLL _kdt-nested-poll-status !
    DROP KDOSDNS-S-PENDING ;

: _kdt-step-transfer-owner  ( adapter -- status )
    DUP KDOSNET-RELEASE KDOSNET-S-OK = _kdt-assert
    DROP
    _kdt-b KDOSNET-CLAIM KDOSNET-S-OK = _kdt-assert
    KDOSDNS-S-PENDING ;

: _kdt-step-complete  ( adapter -- status )
    _kdt-step-a !
    _kdt-wire-response
    _kdt-step-a @ _KDNS.RESPONSE @
    34 CMOVE
    34 _kdt-step-a @ _KDNS.RESPONSE-U !
    _kdt-step-a @ _KDNS.RESPONSE @
    34 _kdt-step-a @ _KDNS-QUESTION-MATCH? _kdt-assert
    _kdt-step-a @ _KDNS.RESPONSE @
    _kdt-step-a @ _KDNS-CAPTURE-DIAGNOSTICS
    KDOSDNS-E-DNS-HEADER KDOSDNS-E-ID OR
    KDOSDNS-E-QUESTION OR
    _kdt-step-a @ _KDNS-EVIDENCE+
    _kdt-step-a @ _KDNS-FINISH-OK ;

: _kdt-init-a  ( -- )
    _kdt-response-a 1024 _kdt-a KDOSDNS-INIT
    KDOSDNS-S-OK = _kdt-assert ;

: _kdt-init-b  ( -- )
    _kdt-response-b 1024 _kdt-b KDOSDNS-INIT
    KDOSDNS-S-OK = _kdt-assert ;

: _kdt-fake-clock-a  ( -- )
    0 _kdt-now !
    ['] _kdt-now@ _kdt-a _KDNS.NOW-XT ! ;

: _kdt-start-a  ( -- )
    _kdt-query 34 _kdt-server _kdt-a KDOSDNS-START
    KDOSDNS-S-PENDING = _kdt-assert ;

: _kdt-wipe-a  ( -- )
    _kdt-a KDOSDNS-WIPE KDOSDNS-S-OK = _kdt-assert ;

: _kdt-wipe-b  ( -- )
    _kdt-b KDOSDNS-WIPE KDOSDNS-S-OK = _kdt-assert ;

: _kdt-test-init-and-admission  ( -- )
    _kdt-a KDOSDNS-SIZE 0xA5 FILL
    _kdt-response-a 11 _kdt-a KDOSDNS-INIT
    KDOSDNS-S-CAPACITY = _kdt-assert
    _kdt-a KDOSDNS-SIZE 0xA5 _kdt-byte? _kdt-assert

    _kdt-a 12 _kdt-a KDOSDNS-INIT
    KDOSDNS-S-ALIAS = _kdt-assert
    _kdt-a KDOSDNS-SIZE 0xA5 _kdt-byte? _kdt-assert

    _kdt-init-a
    _kdt-a KDOSDNS-VALID? _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-IDLE = _kdt-assert
    _kdt-a KDOSDNS-STATUS@ KDOSDNS-S-OK = _kdt-assert
    _kdt-a KDOSDNS-PHASE@ KDOSDNS-PHASE-IDLE = _kdt-assert
    _kdt-response-a 1024 0 _kdt-byte? _kdt-assert

    _kdt-query _kdt-response-a 34 CMOVE
    _kdt-response-a 34 _kdt-server _kdt-a KDOSDNS-START
    KDOSDNS-S-ALIAS = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-IDLE = _kdt-assert

    _kdt-response-a 1024 0 FILL
    _kdt-query 34 0 _kdt-a KDOSDNS-START
    KDOSDNS-S-INVALID = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-IDLE = _kdt-assert

    2 _kdt-query 4 + NW16!
    _kdt-query 34 _kdt-server _kdt-a KDOSDNS-START
    KDOSDNS-S-INVALID = _kdt-assert
    1 _kdt-query 4 + NW16!
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-IDLE = _kdt-assert

    _kdt-wipe-a
    _kdt-a KDOSDNS-VALID? 0= _kdt-assert
    _kdt-a KDOSDNS-SIZE 0 _kdt-byte? _kdt-assert
    _kdt-stack ;

: _kdt-query-flags?  ( flags expected -- )
    >R
    _kdt-query 2 + NW16!
    _kdt-query 34 _KDNS-QUERY-VALID?
    R> = _kdt-assert ;

: _kdt-test-query-flags  ( -- )
    0x0100 -1 _kdt-query-flags?  \ RD
    0x0130 -1 _kdt-query-flags?  \ RD, AD, CD
    0x8100 0 _kdt-query-flags?   \ QR
    0x0900 0 _kdt-query-flags?   \ nonzero opcode
    0x0500 0 _kdt-query-flags?   \ AA
    0x0300 0 _kdt-query-flags?   \ TC
    0x0180 0 _kdt-query-flags?   \ RA
    0x0140 0 _kdt-query-flags?   \ reserved Z
    0x0103 0 _kdt-query-flags?   \ query RCODE
    0x0100 _kdt-query 2 + NW16!
    _kdt-stack ;

: _kdt-test-start-and-owner  ( -- )
    _kdt-init-a
    _kdt-b KDOSDNS-SIZE 0xA5 FILL
    _kdt-b KDOSNET-CLAIM KDOSNET-S-OK = _kdt-assert
    _kdt-response-b 1024 _kdt-b KDOSDNS-INIT
        KDOSDNS-S-BUSY = _kdt-assert
    _kdt-b KDOSDNS-SIZE 0xA5 _kdt-byte? _kdt-assert
    _kdt-b KDOSNET-RELEASE KDOSNET-S-OK = _kdt-assert
    _kdt-init-b
    _kdt-b KDOSNET-CLAIM KDOSNET-S-OK = _kdt-assert
    _kdt-query 34 _kdt-server _kdt-a KDOSDNS-START
        KDOSDNS-S-BUSY = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-IDLE = _kdt-assert
    KDOSNET-OWNER@ _kdt-b = _kdt-assert
    _kdt-b KDOSNET-RELEASE KDOSNET-S-OK = _kdt-assert
    _kdt-start-a
    _kdt-a KDOSDNS-VALID? _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-ACTIVE = _kdt-assert
    _kdt-a KDOSDNS-STATUS@ KDOSDNS-S-PENDING = _kdt-assert
    KDOSNET-OWNER@ _kdt-a = _kdt-assert
    _kdt-a KDOSNET-OWNER? _kdt-assert
    _kdt-response-a 1024 _kdt-a KDOSDNS-INIT
        KDOSDNS-S-BUSY = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-ACTIVE = _kdt-assert
    _kdt-a _KDNS.QUERY-U @ 34 = _kdt-assert
    _kdt-a _KDNS.QNAME-U @ 18 = _kdt-assert
    _kdt-a _KDNS.QTYPE @ 16 = _kdt-assert
    _kdt-a _KDNS.QCLASS @ 1 = _kdt-assert
    _kdt-a _KDNS.QUERY _kdt-query 34 SAMESTR? _kdt-assert
    _kdt-a _KDNS.QNAME 2 + C@ [CHAR] d = _kdt-assert
    _kdt-a _KDNS.QNAME 10 + C@ [CHAR] e = _kdt-assert

    0 _kdt-query C!
    _kdt-a _KDNS.QUERY-ID @ 0xBEEF = _kdt-assert
    0xBE _kdt-query C!

    _kdt-query 34 _kdt-server _kdt-b KDOSDNS-START
    KDOSDNS-S-BUSY = _kdt-assert
    _kdt-b KDOSDNS-STATE@ KDOSDNS-STATE-IDLE = _kdt-assert

    _kdt-a _kdt-response!
    _kdt-rs @ KDOSDNS-S-PENDING = _kdt-assert
    _kdt-ra @ 0= _kdt-assert
    _kdt-ru @ 0= _kdt-assert

    _kdt-a KDOSDNS-CANCEL
    KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-a KDOSDNS-VALID? _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-CANCELLED = _kdt-assert
    _kdt-a _KDNS.QUERY-U @ 0= _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert
    _kdt-response-a 1024 0 _kdt-byte? _kdt-assert

    _kdt-wipe-a
    _kdt-wipe-b
    _kdt-stack ;

: _kdt-test-reentry  ( -- )
    _kdt-init-a
    -1 _kdt-nested-start-status !
    ['] _kdt-now-reenter-start _kdt-a _KDNS.NOW-XT !
    _kdt-query 34 _kdt-server _kdt-a KDOSDNS-START
        KDOSDNS-S-PENDING = _kdt-assert
    _kdt-nested-start-status @ KDOSDNS-S-BUSY = _kdt-assert
    _KDS-BUSY @ 0= _kdt-assert
    KDOSNET-OWNER@ _kdt-a = _kdt-assert
    _kdt-a KDOSDNS-CANCEL
        KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a

    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    -1 _kdt-nested-poll-status !
    ['] _kdt-step-reenter-poll _kdt-a _KDNS.STEP-XT !
    _kdt-a KDOSDNS-POLL KDOSDNS-S-PENDING = _kdt-assert
    _kdt-nested-poll-status @ KDOSDNS-S-BUSY = _kdt-assert
    _KDP-BUSY @ 0= _kdt-assert
    _kdt-a KDOSDNS-STATE@
        KDOSDNS-STATE-ACTIVE = _kdt-assert
    KDOSNET-OWNER@ _kdt-a = _kdt-assert
    _kdt-a KDOSDNS-CANCEL
        KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a

    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    ['] _kdt-step-transfer-owner _kdt-a _KDNS.STEP-XT !
    _kdt-a KDOSDNS-POLL KDOSDNS-S-CLEANUP = _kdt-assert
    _kdt-a KDOSDNS-STATE@
        KDOSDNS-STATE-ACTIVE = _kdt-assert
    _kdt-a KDOSDNS-STATUS@
        KDOSDNS-S-PENDING = _kdt-assert
    _KDP-BUSY @ 0= _kdt-assert
    KDOSNET-OWNER@ _kdt-b = _kdt-assert
    _kdt-a KDOSDNS-CANCEL
        KDOSDNS-S-CLEANUP = _kdt-assert
    _kdt-b KDOSNET-RELEASE KDOSNET-S-OK = _kdt-assert
    _kdt-a KDOSNET-CLAIM KDOSNET-S-OK = _kdt-assert
    _kdt-a KDOSDNS-CANCEL
        KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a
    _kdt-stack ;

: _kdt-test-root-question  ( -- )
    _kdt-init-a
    _kdt-root-query 17 _kdt-server _kdt-a KDOSDNS-START
    KDOSDNS-S-PENDING = _kdt-assert
    _kdt-a KDOSDNS-VALID? _kdt-assert
    _kdt-a _KDNS.QNAME-U @ 1 = _kdt-assert
    _kdt-a _KDNS.QNAME C@ 0= _kdt-assert
    _kdt-a KDOSDNS-CANCEL
    KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a

    \ A quarantined terminal descriptor cannot interpret a foreign owner as
    \ proof of detachment and erase the evidence needed for later cleanup.
    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    _kdt-a KDOSNET-RELEASE KDOSNET-S-OK = _kdt-assert
    _kdt-b KDOSNET-CLAIM KDOSNET-S-OK = _kdt-assert
    KDOSDNS-S-CLEANUP _kdt-a _KDNS.STATUS !
    KDOSDNS-PHASE-FAILED _kdt-a _KDNS.PHASE !
    KDOSDNS-STATE-FAILED _kdt-a _KDNS.STATE !
    _kdt-a KDOSDNS-CANCEL
        KDOSDNS-S-CLEANUP = _kdt-assert
    _kdt-a KDOSDNS-STATE@
        KDOSDNS-STATE-FAILED = _kdt-assert
    _kdt-a KDOSDNS-STATUS@
        KDOSDNS-S-CLEANUP = _kdt-assert
    _kdt-a _KDNS.QUERY-U @ 34 = _kdt-assert
    KDOSNET-OWNER@ _kdt-b = _kdt-assert
    _kdt-b KDOSNET-RELEASE KDOSNET-S-OK = _kdt-assert
    _kdt-a KDOSNET-CLAIM KDOSNET-S-OK = _kdt-assert
    _kdt-a KDOSDNS-CANCEL
        KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a
    _kdt-stack ;

: _kdt-test-question-binding  ( -- )
    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    0x8180 _kdt-build-response
    _kdt-wire-response 34 _kdt-a
    _KDNS-QUESTION-MATCH? _kdt-assert

    0xC0 _kdt-wire-response 34 + C!
    12 _kdt-wire-response 35 + C!
    _kdt-wire-response 36 34 _kdt-a
    _KDNS-DECODE-NAME _kdt-assert
    _kdt-a _KDNS.WORK-NEXT @ 36 = _kdt-assert
    _kdt-a _KDNS.WORK-OUT-U @ 18 = _kdt-assert
    _kdt-a _KDNS.NAME-SCRATCH
    _kdt-a _KDNS.QNAME 18 SAMESTR? _kdt-assert

    0 _kdt-wire-response C!
    _kdt-wire-response 34 _kdt-a
    _KDNS-QUESTION-MATCH? 0= _kdt-assert
    0xBEEF _kdt-wire-response NW16!

    0x81C0 _kdt-wire-response 2 + NW16!
    _kdt-wire-response 34 _kdt-a
    _KDNS-QUESTION-MATCH? 0= _kdt-assert
    0x8180 _kdt-wire-response 2 + NW16!

    1 _kdt-wire-response 30 + NW16!
    _kdt-wire-response 34 _kdt-a
    _KDNS-QUESTION-MATCH? 0= _kdt-assert
    16 _kdt-wire-response 30 + NW16!

    _kdt-wire-response 33 _kdt-a
    _KDNS-QUESTION-MATCH? 0= _kdt-assert

    0x8183 _kdt-wire-response 2 + NW16!
    _kdt-wire-response _kdt-a _KDNS-CAPTURE-DIAGNOSTICS
    _kdt-a _KDNS.RCODE @ 3 = _kdt-assert
    _kdt-a _KDNS.DNS-FLAGS @ 0x8183 = _kdt-assert

    _kdt-a KDOSDNS-CANCEL DROP
    _kdt-wipe-a
    _kdt-stack ;

: _kdt-test-complete  ( -- )
    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    0x8183 _kdt-build-response
    ['] _kdt-step-complete _kdt-a _KDNS.STEP-XT !
    ." KDOS DNS COMPLETE PREP" CR TX-FLUSH KEY DROP
    _kdt-a KDOSDNS-POLL KDOSDNS-S-OK = _kdt-assert
    _kdt-a KDOSDNS-VALID? _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-COMPLETE = _kdt-assert
    _kdt-a KDOSDNS-PHASE@ KDOSDNS-PHASE-DONE = _kdt-assert
    _kdt-a KDOSDNS-RCODE@ 3 = _kdt-assert
    _kdt-a KDOSDNS-FLAGS@ 0x8183 = _kdt-assert
    _kdt-a KDOSDNS-USED-TCP? 0= _kdt-assert
    _kdt-a KDOSDNS-STEP-COUNT@ 1 = _kdt-assert
    _kdt-a KDOSDNS-MAX-STEP-CYCLES@
    _kdt-a KDOSDNS-LAST-STEP-CYCLES@ U< 0= _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert
    ." KDOS DNS COMPLETE POLL" CR TX-FLUSH KEY DROP

    _kdt-a _kdt-response!
    _kdt-rs @ KDOSDNS-S-OK = _kdt-assert
    _kdt-ru @ 34 = _kdt-assert
    _kdt-ra @ _kdt-wire-response 34 SAMESTR? _kdt-assert
    _kdt-a KDOSDNS-EVIDENCE@
    KDOSDNS-E-DNS-HEADER KDOSDNS-E-ID OR
    KDOSDNS-E-QUESTION OR KDOSDNS-E-RESPONSE OR
    AND
    KDOSDNS-E-DNS-HEADER KDOSDNS-E-ID OR
    KDOSDNS-E-QUESTION OR KDOSDNS-E-RESPONSE OR
    = _kdt-assert
    ." KDOS DNS COMPLETE RESPONSE" CR TX-FLUSH KEY DROP

    _kdt-a KDOSDNS-POLL KDOSDNS-S-OK = _kdt-assert
    _kdt-a KDOSDNS-STEP-COUNT@ 1 = _kdt-assert
    _kdt-wipe-a
    _kdt-response-a 1024 0 _kdt-byte? _kdt-assert
    _kdt-stack ;

: _kdt-test-timeout-and-faults  ( -- )
    _kdt-init-a
    ['] _kdt-now-throw _kdt-a _KDNS.NOW-XT !
    _kdt-query 34 _kdt-server _kdt-a KDOSDNS-START
    KDOSDNS-S-FAULT = _kdt-assert
    _kdt-a KDOSDNS-VALID? _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-IDLE = _kdt-assert
    _kdt-a KDOSDNS-STATUS@ KDOSDNS-S-OK = _kdt-assert
    _kdt-a _KDNS.QUERY-U @ 0= _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert
    _kdt-wipe-a

    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    ['] _kdt-now-throw _kdt-a _KDNS.NOW-XT !
    _kdt-a KDOSDNS-POLL KDOSDNS-S-FAULT = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-FAILED = _kdt-assert
    _kdt-a KDOSDNS-STATUS@ KDOSDNS-S-FAULT = _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert
    _kdt-wipe-a

    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    ['] _kdt-step-pending _kdt-a _KDNS.STEP-XT !
    _kdt-a KDOSDNS-POLL
    KDOSDNS-S-PENDING = _kdt-assert
    _kdt-a KDOSDNS-STEP-COUNT@ 1 = _kdt-assert
    _kdt-a _KDNS.DEADLINE-MS @ _kdt-now !
    _kdt-a KDOSDNS-POLL
    KDOSDNS-S-TIMEOUT = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-FAILED = _kdt-assert
    _kdt-a KDOSDNS-STATUS@ KDOSDNS-S-TIMEOUT = _kdt-assert
    _kdt-a KDOSDNS-STEP-COUNT@ 1 = _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert
    _kdt-wipe-a

    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    ['] _kdt-step-throw _kdt-a _KDNS.STEP-XT !
    _kdt-a KDOSDNS-POLL KDOSDNS-S-FAULT = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-FAILED = _kdt-assert
    _kdt-a KDOSDNS-STATUS@ KDOSDNS-S-FAULT = _kdt-assert
    _kdt-a KDOSDNS-STEP-COUNT@ 1 = _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert
    _kdt-wipe-a

    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    ['] _kdt-step-invalid-ok _kdt-a _KDNS.STEP-XT !
    _kdt-a KDOSDNS-POLL KDOSDNS-S-FAULT = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-FAILED = _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert
    _kdt-wipe-a
    _kdt-stack ;

: _kdt-test-cleanup-proof  ( -- )
    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    8 _kdt-a _KDNS.TCB !
    0x12345678 _kdt-a _KDNS.TCB-ISS !
    _kdt-a KDOSDNS-CANCEL
    KDOSDNS-S-CLEANUP = _kdt-assert
    _kdt-a KDOSDNS-STATE@
    KDOSDNS-STATE-ACTIVE = _kdt-assert
    _kdt-a _KDNS.TCB @ 8 = _kdt-assert
    _kdt-a _KDNS.TCB-ISS @ 0x12345678 = _kdt-assert
    KDOSNET-OWNER@ _kdt-a = _kdt-assert
    _kdt-a KDOSNET-OWNER? _kdt-assert

    0 _kdt-a _KDNS.TCB !
    0 _kdt-a _KDNS.TCB-ISS !
    _kdt-a KDOSDNS-CANCEL
    KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a
    _kdt-stack ;

: _kdt-test-reclaimed-tcb  ( -- )
    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    0 TCB-N DUP _kdt-tcb ! TCB-INIT
    _kdt-a _KDNS.LOCAL-PORT @
    _kdt-tcb @ TCB.LOCAL-PORT !
    53 _kdt-tcb @ TCB.REMOTE-PORT !
    _kdt-a _KDNS.SERVER-IP
    _kdt-tcb @ TCB.REMOTE-IP 4 CMOVE
    0x12345678 DUP _kdt-a _KDNS.TCB-ISS !
    _kdt-tcb @ TCB.ISS !
    TCPS-ESTABLISHED _kdt-tcb @ TCB.STATE !
    _kdt-tcb @ _kdt-a _KDNS.TCB !
    _kdt-a _KDNS-TCB@ _kdt-tcb @ = _kdt-assert

    \ Peer RST and unexpected SYN reclaim this slot through TCB-INIT.
    _kdt-tcb @ TCB-INIT
    _kdt-a _KDNS-TCB@ 0= _kdt-assert
    KDOSDNS-S-IO _kdt-a _KDNS-FAIL
    KDOSDNS-S-IO = _kdt-assert
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-FAILED = _kdt-assert
    _kdt-a _KDNS.TCB @ 0= _kdt-assert
    KDOSNET-OWNER@ 0= _kdt-assert

    _kdt-start-a
    _kdt-a KDOSDNS-STATE@ KDOSDNS-STATE-ACTIVE = _kdt-assert
    _kdt-a KDOSDNS-CANCEL
    KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a
    _kdt-stack ;

: _kdt-test-tcp-framing  ( -- )
    _kdt-init-a
    _kdt-fake-clock-a
    _kdt-start-a
    KDOSDNS-E-TRUNCATED _kdt-a _KDNS-EVIDENCE+
    _kdt-a _KDPA !
    _KDNS-BEGIN-TCP KDOSDNS-S-PENDING = _kdt-assert
    _kdt-a KDOSDNS-VALID? _kdt-assert
    _kdt-a KDOSDNS-USED-TCP? _kdt-assert
    _kdt-a KDOSDNS-PHASE@ KDOSDNS-PHASE-ARP-CHECK = _kdt-assert
    _kdt-a _KDNS.AFTER-ARP-PHASE @
    KDOSDNS-PHASE-TCP-OPEN = _kdt-assert
    _kdt-a _KDNS.TCP-FRAME NW16@ 34 = _kdt-assert
    _kdt-a _KDNS.TCP-FRAME 2 +
    _kdt-a _KDNS.QUERY = _kdt-assert
    _kdt-a _KDNS.QUERY _kdt-query 34 SAMESTR? _kdt-assert
    _kdt-a _KDNS.TCP-TX-OFFSET @ 0= _kdt-assert
    _kdt-a KDOSDNS-CANCEL
    KDOSDNS-S-CANCELLED = _kdt-assert
    _kdt-wipe-a
    _kdt-stack ;

: _KDT-RUN  ( -- )
    0 _kdt-fails !
    0 _kdt-checks !
    DEPTH _kdt-depth !
    1 1 1 1 _kdt-server IP!
    _kdt-build-query
    _kdt-build-root-query
    _kdt-test-init-and-admission
    ." KDOS DNS LIFE ADMISSION" CR TX-FLUSH KEY DROP
    _kdt-test-query-flags
    ." KDOS DNS LIFE FLAGS" CR TX-FLUSH KEY DROP
    _kdt-test-start-and-owner
    ." KDOS DNS LIFE OWNER" CR TX-FLUSH KEY DROP
    _kdt-test-reentry
    ." KDOS DNS LIFE REENTRY" CR TX-FLUSH KEY DROP
    _kdt-test-root-question
    ." KDOS DNS LIFE ROOT" CR TX-FLUSH KEY DROP
    _kdt-test-question-binding
    ." KDOS DNS LIFE BINDING" CR TX-FLUSH KEY DROP
    _kdt-test-complete
    ." KDOS DNS LIFE COMPLETE" CR TX-FLUSH KEY DROP
    _kdt-test-timeout-and-faults
    ." KDOS DNS LIFE FAULTS" CR TX-FLUSH KEY DROP
    _kdt-test-cleanup-proof
    ." KDOS DNS LIFE CLEANUP" CR TX-FLUSH KEY DROP
    _kdt-test-reclaimed-tcb
    ." KDOS DNS LIFE RECLAIM" CR TX-FLUSH KEY DROP
    _kdt-test-tcp-framing
    ." KDOS DNS LIFE FRAMING" CR TX-FLUSH KEY DROP
    _kdt-fails @ 0= IF
        ." KDOS DNS CONTRACT PASS " _kdt-checks @ . CR
    ELSE
        ." KDOS DNS CONTRACT FAIL " _kdt-fails @ .
        ." / " _kdt-checks @ . CR
    THEN ;
