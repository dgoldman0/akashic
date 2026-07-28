\ Cancellation and conservative send-exposure qualification.

REQUIRE o2-http-post-common.f
PROVIDED akashic-o2http-xport

: _o2hpt-test-alias-and-cancel  ( -- )
    _o2hpt-build-request-lean
    _o2hpt-post _O2HP.FLAGS @ _o2hpt-saved-0 !
    _o2hpt-saved-0 @ OAUTH2-HTTP-POST-F-DPOP-SENT OR
        _o2hpt-post _O2HP.FLAGS !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? 0= _o2hpt-assert
    _o2hpt-saved-0 @ _o2hpt-post _O2HP.FLAGS !
    _o2hpt-post OAUTH2-HTTP-POST-VALID? _o2hpt-assert
    _o2hpt-transport-reset
    _o2hpt-form 512 + DUP _o2hpt-port-install-at
    _o2hpt-start-at OAUTH2-HTTP-POST-S-ALIAS _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-STATE@
        OAUTH2-HTTP-POST-STATE-SEALED = _o2hpt-assert
    _o2hpt-start OAUTH2-HTTP-POST-S-PENDING _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-CANCEL
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    OAUTH2-HTTP-POST-O-CANCELLED OAUTH2-HTTP-POST-D-NONE 0
        _o2hpt-semantic
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-INCLUDED? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-SENT? 0= _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-SENT?
        0= _o2hpt-assert ;

: _o2hpt-test-partial-send  ( -- )
    _o2hpt-build-request-lean
    _o2hpt-transport-reset
    1 _o2hpt-send-limit !
    _o2hpt-start OAUTH2-HTTP-POST-S-PENDING _o2hpt-status
    _o2hpt-post OAUTH2-HTTP-POST-POLL
        OAUTH2-HTTP-POST-S-PENDING _o2hpt-status
    _o2hpt-sent-u @ 1 = _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-SENT? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-SENT?
        _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-CANCEL
        OAUTH2-HTTP-POST-S-OK _o2hpt-status
    OAUTH2-HTTP-POST-O-CANCELLED OAUTH2-HTTP-POST-D-NONE 0
        _o2hpt-semantic
    _o2hpt-post OAUTH2-HTTP-POST-DPOP-SENT? _o2hpt-assert
    _o2hpt-post OAUTH2-HTTP-POST-AUTHORIZATION-SENT?
        _o2hpt-assert ;

: _o2hpt-transport-cases  ( -- )
    ." OAUTH2 HTTP POST STAGE transport-start" CR TX-FLUSH
    _o2hpt-suite-init-lean
    _o2hpt-test-alias-and-cancel
    ." OAUTH2 HTTP POST STAGE cancel" CR TX-FLUSH
    _o2hpt-test-partial-send
    ." OAUTH2 HTTP POST STAGE partial" CR TX-FLUSH
    _o2hpt-suite-finish-lean ;

: _O2HPT-RUN-TRANSPORT  ( -- )
    _o2hpt-suite-begin
    _o2hpt-transport-cases
    _o2hpt-suite-report ;
