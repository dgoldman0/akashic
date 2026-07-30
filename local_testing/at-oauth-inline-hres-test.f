\ Focused gates for acquired confidential inline AT OAuth deployment.
\
\ This fixture is evaluated after hres-contracts.f and the profile,
\ deployment, and inline fixtures.  It reuses their deterministic transport,
\ builders, and checked-key seam without running their predecessor groups.

PROVIDED at-oauth-ihres-test

VARIABLE _ATOIHT-CHECKS
VARIABLE _ATOIHT-FAILS
VARIABLE _ATOIHT-DEPTH
VARIABLE _ATOIHT-STATUS-V
VARIABLE _ATOIHT-MEDIA-A
VARIABLE _ATOIHT-MEDIA-U
VARIABLE _ATOIHT-BODY-A
VARIABLE _ATOIHT-BODY-U
VARIABLE _ATOIHT-URI-A
VARIABLE _ATOIHT-URI-U
VARIABLE _ATOIHT-WEAK
VARIABLE _ATOIHT-STORAGE-A
VARIABLE _ATOIHT-STORAGE-U
VARIABLE _ATOIHT-CALLBACK
VARIABLE _ATOIHT-CALL-WORK
VARIABLE _ATOIHT-EXPECT-WORK

4096 CONSTANT _ATOIHT-TAIL-WORK-OFF
_ATOIHT-TAIL-WORK-OFF CONSTANT _ATOIHT-NORMAL-BODY-CAP
_ATOIHT-TAIL-WORK-OFF AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE +
    CONSTANT _ATOIHT-TAIL-BODY-CAP

CREATE _ATOIHT-TAIL-STORAGE
    _ATOIHT-TAIL-BODY-CAP 7 + ALLOT

: _ATOIHT-TAIL-BODY  ( -- body )
    _ATOIHT-TAIL-STORAGE 7 + -8 AND ;

: _ATOIHT-TAIL-WORK  ( -- workspace )
    _ATOIHT-TAIL-BODY _ATOIHT-TAIL-WORK-OFF + ;

: _ATOIHT-ASSERT  ( flag -- )
    1 _ATOIHT-CHECKS +!
    0= IF
        1 _ATOIHT-FAILS +!
        ." AT OAUTH INLINE HRES ASSERT " _ATOIHT-CHECKS @ . CR
        TX-FLUSH
    THEN ;

: _ATOIHT-STATUS  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH INLINE HRES STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _ATOIHT-ASSERT ;

: _ATOIHT-STACK  ( -- )
    DEPTH DUP _ATOIHT-DEPTH @ <> IF
        ." AT OAUTH INLINE HRES STACK "
        _ATOIHT-DEPTH @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _ATOIHT-DEPTH @ = _ATOIHT-ASSERT ;

: _ATOIHT-WORK-FILL  ( workspace -- )
    AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE 0xA5 FILL ;

: _ATOIHT-WORK-FILLED?  ( workspace -- flag )
    AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
    0xA5 _atodt-byte? ;

\ =====================================================================
\ Scripted Client Identifier Metadata response and retained HRES result
\ =====================================================================

: _ATOIHT-BUILD-FINAL
  ( hop status media-a media-u body-a body-u -- )
    _ATOIHT-BODY-U !
    _ATOIHT-BODY-A !
    _ATOIHT-MEDIA-U !
    _ATOIHT-MEDIA-A !
    _ATOIHT-STATUS-V !
    _hrc-response-select
    S" HTTP/1.1 " _hrc-response,
    _ATOIHT-STATUS-V @ NUM>STR _hrc-response,
    S"  Client Metadata" _hrc-response-line,
    _ATOIHT-MEDIA-U @ IF
        S" Content-Type: " _hrc-response,
        _ATOIHT-MEDIA-A @ _ATOIHT-MEDIA-U @ _hrc-response,
        _hrc-response-crlf,
    THEN
    _ATOIHT-BODY-U @ _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    _ATOIHT-BODY-A @ _ATOIHT-BODY-U @ _hrc-response, ;

: _ATOIHT-BUILD-JSON  ( hop status -- )
    S" Application/JSON; charset=utf-8"
    _atodt-document _atodt-document-u @
    _ATOIHT-BUILD-FINAL ;

: _ATOIHT-BUILD-TEXT  ( hop status -- )
    S" text/plain"
    _atodt-document _atodt-document-u @
    _ATOIHT-BUILD-FINAL ;

: _ATOIHT-SETUP
  ( uri-a uri-u weak? storage-a storage-u -- )
    _ATOIHT-STORAGE-U !
    _ATOIHT-STORAGE-A !
    _ATOIHT-WEAK !
    _ATOIHT-URI-U !
    _ATOIHT-URI-A !
    _hrc-spec HRES-SPEC-INIT
    _ATOIHT-URI-A @ _ATOIHT-URI-U @
        _hrc-spec HRES-SPEC-TARGET!
        HRES-S-OK _ATOIHT-STATUS
    _ATOIHT-WEAK @ IF
        S" */*" _hrc-spec HRES-SPEC-ACCEPT!
            HRES-S-OK _ATOIHT-STATUS
        200 299 _hrc-spec HRES-SPEC-SUCCESS-RANGE!
            HRES-S-OK _ATOIHT-STATUS
        1 _hrc-spec HRES-SPEC-REDIRECT-MAX!
            HRES-S-OK _ATOIHT-STATUS
        HRES-MEDIA-REQUIRED _hrc-spec HRES-SPEC-MEDIA-MODE!
            HRES-S-OK _ATOIHT-STATUS
        _hrc-resource ['] _hrc-media-policy
            _hrc-spec HRES-SPEC-MEDIA!
            HRES-S-OK _ATOIHT-STATUS
    ELSE
        _hrc-spec AT-OAUTH-INLINE-HRES-SPEC-POLICY!
            HRES-S-OK _ATOIHT-STATUS
    THEN
    _hrc-resource ['] _hrc-bind ['] _hrc-release
        _hrc-spec HRES-SPEC-BINDING!
        HRES-S-OK _ATOIHT-STATUS
    _hrc-spec HRES-SPEC-SEAL HRES-S-OK _ATOIHT-STATUS
    _hrc-spec HRES-SPEC-VALID? _ATOIHT-ASSERT
    _hrc-resource HRES-INIT
    _ATOIHT-STORAGE-U @ _hrc-body-cap !
    _hrc-spec
    _ATOIHT-STORAGE-A @ _ATOIHT-STORAGE-U @
    _hrc-resource HRES-CONFIGURE
        HRES-S-OK _ATOIHT-STATUS ;

: _ATOIHT-RUN  ( -- )
    _hrc-run-resource HRES-S-OK _ATOIHT-STATUS ;

: _ATOIHT-CLEAN  ( -- )
    _hrc-resource HRES-WIPE HRES-S-OK _ATOIHT-STATUS
    _ATOIHT-STORAGE-A @ _ATOIHT-STORAGE-U @
        _hrc-zero? _ATOIHT-ASSERT
    _hrc-resource HRES-DECONFIGURE
        HRES-S-OK _ATOIHT-STATUS
    _hrc-resource HRES-STATE@ HRES-STATE-IDLE =
        _ATOIHT-ASSERT
    _hrc-lease-errors @ 0= _ATOIHT-ASSERT
    _hrc-binds @ _hrc-releases @ = _ATOIHT-ASSERT ;

\ =====================================================================
\ Inline call and rejection helpers
\ =====================================================================

: _ATOIHT-CALL  ( callback workspace -- callback-result status )
    _ATOIHT-CALL-WORK !
    _ATOIHT-CALLBACK !
    _hrc-resource
    _atodt-config
    _atopt-profile
    _atoit-vault
    _ATOIHT-CALLBACK @
    _ATOIT-CONTEXT
    _ATOIHT-CALL-WORK @
    AT-OAUTH-INLINE-HRES-WITH ;

: _ATOIHT-EXPECT-BODY-JWKS  ( -- )
    _atodt-inline-jwks-a @ _atodt-document -
    _ATOIHT-STORAGE-A @ +
    _ATOID-EXPECT-JWKS-A !
    _atodt-inline-jwks-u @ _ATOID-EXPECT-JWKS-U ! ;

: _ATOIHT-EXPECT-HTTP  ( workspace -- )
    _ATOIHT-EXPECT-WORK !
    0 _atoit-callback-count !
    _atodt-snapshot
    _ATOIHT-EXPECT-WORK @ _ATOIHT-WORK-FILL
    ['] _atoit-callback-never
    _ATOIHT-EXPECT-WORK @ _ATOIHT-CALL
    AT-OAUTH-INLINE-HRES-S-HTTP _ATOIHT-STATUS
    0 _ATOIHT-STATUS
    _ATOIHT-EXPECT-WORK @ _ATOIHT-WORK-FILLED?
        _ATOIHT-ASSERT
    _ATOIT-INPUTS-UNCHANGED? _ATOIHT-ASSERT
    _atoit-callback-count @ 0= _ATOIHT-ASSERT
    _ATOID-DEPLOY-CALLS @ 0= _ATOIHT-ASSERT ;

\ =====================================================================
\ Minimal gating groups
\ =====================================================================

: _ATOIHT-TEST-POLICY  ( -- )
    _hrc-fixture-reset
    _hrc-spec HRES-SPEC-INIT
    S" https://client.example/oauth/client-metadata.json"
        _hrc-spec HRES-SPEC-TARGET!
        HRES-S-OK _ATOIHT-STATUS
    _hrc-spec AT-OAUTH-INLINE-HRES-SPEC-POLICY!
        HRES-S-OK _ATOIHT-STATUS
    _hrc-spec HRES-SPEC-ACCEPT$
        S" application/json" STR-STR= _ATOIHT-ASSERT
    _hrc-spec HRSPEC.SUCCESS-LOW @ 200 = _ATOIHT-ASSERT
    _hrc-spec HRSPEC.SUCCESS-HIGH @ 200 = _ATOIHT-ASSERT
    _hrc-spec HRSPEC.REDIRECT-MAX @ 0= _ATOIHT-ASSERT
    _hrc-spec HRSPEC.MEDIA-MODE @ HRES-MEDIA-REQUIRED =
        _ATOIHT-ASSERT
    AT-OAUTH-INLINE-HRES-S-HTTP
        AT-OAUTH-INLINE-HRES-STATUS-VALID? _ATOIHT-ASSERT
    43 AT-OAUTH-INLINE-HRES-STATUS-VALID? 0= _ATOIHT-ASSERT
    _ATOIHT-STACK ;

: _ATOIHT-TEST-SUCCESS  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    _hrc-fixture-reset
    0 200 _ATOIHT-BUILD-JSON
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    0 _ATOIHT-TAIL-BODY _ATOIHT-NORMAL-BODY-CAP
        _ATOIHT-SETUP
    _ATOIHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOIHT-ASSERT
    _hrc-binds @ 1 = _ATOIHT-ASSERT
    _hrc-releases @ 1 = _ATOIHT-ASSERT
    _hrc-resource HRES.ACTIVE-PORT @ 0= _ATOIHT-ASSERT
    _ATOIHT-EXPECT-BODY-JWKS

    0 _atoit-callback-count !
    _atodt-snapshot
    _atoit-work-fill
    ['] _atoit-application-callback
    _atoit-work _ATOIHT-CALL
    AT-OAUTH-INLINE-S-OK _ATOIHT-STATUS
    _ATOIT-RESULT _ATOIHT-STATUS
    _atoit-callback-count @ 1 = _ATOIHT-ASSERT
    _ATOID-DEPLOY-CALLS @ 1 = _ATOIHT-ASSERT
    _ATOID-SELECT-CALLS @ 1 = _ATOIHT-ASSERT
    _ATOID-CLIENT-CALLS @ 1 = _ATOIHT-ASSERT
    _ATOID-DPOP-CALLS @ 1 = _ATOIHT-ASSERT
    _ATOID-VIOLATIONS @ 0= _ATOIHT-ASSERT
    _ATOIT-INPUTS-UNCHANGED? _ATOIHT-ASSERT
    _ATOIT-WORK-WIPED? _ATOIHT-ASSERT
    _ATOIHT-CLEAN
    _ATOIHT-STACK ;

: _ATOIHT-TEST-PROVENANCE  ( -- )
    \ A valid retained result for another request target is not replayable.
    _atopt-profile-ready
    _atoit-baseline
    _hrc-fixture-reset
    0 200 _ATOIHT-BUILD-JSON
    S" https://wrong.example/oauth/client-metadata.json"
    0 _ATOIHT-TAIL-BODY _ATOIHT-NORMAL-BODY-CAP
        _ATOIHT-SETUP
    _ATOIHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOIHT-ASSERT
    _atoit-work _ATOIHT-EXPECT-HTTP
    _ATOIHT-CLEAN

    \ A weakened caller policy may admit a same-origin redirect.
    _atopt-profile-ready
    _atoit-baseline
    _hrc-fixture-reset
    0 S" /moved" _hrc-build-redirect
    1 200 _ATOIHT-BUILD-JSON
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    -1 _ATOIHT-TAIL-BODY _ATOIHT-NORMAL-BODY-CAP
        _ATOIHT-SETUP
    _ATOIHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOIHT-ASSERT
    _hrc-resource HRES-REDIRECT-COUNT@ 1 =
        _ATOIHT-ASSERT
    _atoit-work _ATOIHT-EXPECT-HTTP
    _ATOIHT-CLEAN

    \ A weakened media callback may admit a non-JSON document.
    _atopt-profile-ready
    _atoit-baseline
    _hrc-fixture-reset
    0 200 _ATOIHT-BUILD-TEXT
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    -1 _ATOIHT-TAIL-BODY _ATOIHT-NORMAL-BODY-CAP
        _ATOIHT-SETUP
    _ATOIHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOIHT-ASSERT
    _atoit-work _ATOIHT-EXPECT-HTTP
    _ATOIHT-CLEAN

    \ A retained ordinary HTTP failure never reaches inline deployment.
    _atopt-profile-ready
    _atoit-baseline
    _hrc-fixture-reset
    0 404 _ATOIHT-BUILD-JSON
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    -1 _ATOIHT-TAIL-BODY _ATOIHT-NORMAL-BODY-CAP
        _ATOIHT-SETUP
    _ATOIHT-RUN
    _hrc-resource HRES-RESULT-VALID? 0= _ATOIHT-ASSERT
    _atoit-work _ATOIHT-EXPECT-HTTP
    _ATOIHT-CLEAN
    _ATOIHT-STACK ;

: _ATOIHT-TEST-PREFLIGHT  ( -- )
    \ The used JSON ends before the workspace, but the full caller-owned
    \ HRES body buffer contains it.  Preflight rejects that alias without
    \ invoking inline deployment or changing inputs/workspace.
    _atopt-profile-ready
    _atoit-baseline
    _hrc-fixture-reset
    0 200 _ATOIHT-BUILD-JSON
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    0 _ATOIHT-TAIL-BODY _ATOIHT-TAIL-BODY-CAP
        _ATOIHT-SETUP
    _ATOIHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOIHT-ASSERT
    _hrc-resource HRES-BODY@ NIP
        _ATOIHT-TAIL-WORK-OFF < _ATOIHT-ASSERT

    0 _atoit-callback-count !
    _atodt-snapshot
    _ATOIHT-TAIL-WORK _ATOIHT-WORK-FILL
    ['] _atoit-callback-never
    _ATOIHT-TAIL-WORK _ATOIHT-CALL
    AT-OAUTH-INLINE-S-ALIAS _ATOIHT-STATUS
    0 _ATOIHT-STATUS
    _ATOIHT-TAIL-WORK _ATOIHT-WORK-FILLED?
        _ATOIHT-ASSERT
    _ATOIT-INPUTS-UNCHANGED? _ATOIHT-ASSERT
    _atoit-callback-count @ 0= _ATOIHT-ASSERT
    _ATOID-DEPLOY-CALLS @ 0= _ATOIHT-ASSERT
    _ATOIHT-CLEAN
    _ATOIHT-STACK ;

\ =====================================================================
\ Harness entry points
\ =====================================================================

: _ATOIHT-INIT  ( -- )
    _ATOIT-INIT
    0 _ATOIHT-CHECKS !
    0 _ATOIHT-FAILS !
    0 _hrc-fails !
    DEPTH _ATOIHT-DEPTH ! ;

: _ATOIHT-FINISH  ( -- )
    _ATOIHT-STACK
    _atopt-fails @ 0= _ATOIHT-ASSERT
    _atodt-fails @ 0= _ATOIHT-ASSERT
    _atoit-fails @ 0= _ATOIHT-ASSERT
    _hrc-fails @ 0= _ATOIHT-ASSERT
    _ATOIHT-FAILS @ IF
        ." AT OAUTH INLINE HRES FAIL checks/fails "
        _ATOIHT-CHECKS @ . _ATOIHT-FAILS @ . CR
    ELSE
        ." AT OAUTH INLINE HRES PASS "
        _ATOIHT-CHECKS @ . CR
    THEN ;

_ATOIHT-TAIL-BODY-CAP HRES-BODY-MAX > [IF]
    ." AT OAuth inline HRES alias fixture exceeds body bound" CR
    ABORT
[THEN]
