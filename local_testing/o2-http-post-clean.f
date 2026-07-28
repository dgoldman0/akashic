\ Uncertain cleanup quarantine and external finalization qualification.

REQUIRE o2-http-post-common.f
PROVIDED akashic-o2http-clean

: _o2hpt-test-cleanup-finalize  ( -- )
    _o2hpt-build-server
    _o2hpt-build-request-lean
    _o2hpt-transport-reset
    -772 _o2hpt-close-fault !
    -773 _o2hpt-cancel-fault !
    _o2hpt-start OAUTH2-HTTP-POST-S-PENDING _o2hpt-status
    _o2hpt-pump OAUTH2-HTTP-POST-S-CLEANUP _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
        OAUTH2-HTTP-POST-STATE-CLEANUP = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-CLEANUP@
        OAUTH2-HTTP-POST-CLEANUP-UNCERTAIN = _o2hpt-assert
    OAUTH2-HTTP-POST-O-SUCCESS OAUTH2-HTTP-POST-D-NONE 200
        _o2hpt-semantic
    _o2hpt-nonce? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-NIO-CLOSE-ERROR@
        -772 = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-NIO-CANCEL-ERROR@
        -773 = _o2hpt-assert
    _o2hpt-close-calls @ 1 = _o2hpt-assert
    _o2hpt-cancel-calls @ 1 = _o2hpt-assert

    _o2hpt-post OAUTH2-HTTP-POST-CLEANUP-FINALIZE
        OAUTH2-HTTP-POST-S-CLEANUP _o2hpt-status
    _o2hpt-close-calls @ 1 = _o2hpt-assert
    _o2hpt-cancel-calls @ 1 = _o2hpt-assert

    _o2hpt-port NIO-INIT
    _o2hpt-post OAUTH2-HTTP-POST-CLEANUP-FINALIZE
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
        OAUTH2-HTTP-POST-STATE-RESULT = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-CLEANUP@
        OAUTH2-HTTP-POST-CLEANUP-CERTAIN = _o2hpt-assert
    OAUTH2-HTTP-POST-O-SUCCESS OAUTH2-HTTP-POST-D-NONE 200
        _o2hpt-semantic
    _o2hpt-post OAUTH2-HTTP-POST-BODY@
        S" {}" STR-STR= _o2hpt-assert
    _o2hpt-nonce? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-NIO-CLOSE-ERROR@
        -772 = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-NIO-CANCEL-ERROR@
        -773 = _o2hpt-assert
    _o2hpt-close-calls @ 1 = _o2hpt-assert
    _o2hpt-cancel-calls @ 1 = _o2hpt-assert
    _o2hpt-request _O2HPT-REQUEST-CAPACITY
        _o2hpt-zero? _o2hpt-assert
    _o2hpt-form _O2HPT-FORM-CAPACITY
        _o2hpt-zero? _o2hpt-assert ;

: _o2hpt-cleanup-cases  ( -- )
    ." OAUTH2 HTTP POST STAGE cleanup-start" CR TX-FLUSH
    _o2hpt-suite-init-lean
    _o2hpt-test-cleanup-finalize
    ." OAUTH2 HTTP POST STAGE cleanup" CR TX-FLUSH
    _o2hpt-suite-finish-lean ;

: _O2HPT-RUN-CLEANUP  ( -- )
    _o2hpt-suite-begin
    _o2hpt-cleanup-cases
    _o2hpt-suite-report ;
