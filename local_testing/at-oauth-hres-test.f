\ Focused deterministic AT OAuth HTTP-resource adapter contracts.
\
\ This fixture is evaluated after hres-contracts.f and
\ at-oauth-prof-test.f.  It reuses their scripted transport and metadata
\ builders while keeping the adapter qualification in bounded groups.

PROVIDED at-oauth-hres-test

VARIABLE _ATOHT-CHECKS
VARIABLE _ATOHT-FAILS
VARIABLE _ATOHT-DEPTH

VARIABLE _ATOHT-STATUS-V
VARIABLE _ATOHT-MEDIA-A
VARIABLE _ATOHT-MEDIA-U
VARIABLE _ATOHT-RESPONSE-A
VARIABLE _ATOHT-RESPONSE-U
VARIABLE _ATOHT-URI-A
VARIABLE _ATOHT-URI-U
VARIABLE _ATOHT-WEAK

2048 CONSTANT _ATOHT-BODY-CAP
1024 CONSTANT _ATOHT-TAIL-PROFILE-OFF
_ATOHT-TAIL-PROFILE-OFF AT-OAUTH-PROFILE-SIZE +
    CONSTANT _ATOHT-TAIL-BODY-CAP

CREATE _ATOHT-WORK-STORAGE
    AT-OAUTH-HRES-WORKSPACE-SIZE 7 + ALLOT
CREATE _ATOHT-TAIL-BODY-STORAGE
    _ATOHT-TAIL-BODY-CAP 7 + ALLOT

: _ATOHT-WORK  ( -- workspace )
    _ATOHT-WORK-STORAGE 7 + -8 AND ;

: _ATOHT-TAIL-BODY  ( -- body )
    _ATOHT-TAIL-BODY-STORAGE 7 + -8 AND ;

: _ATOHT-TAIL-PROFILE  ( -- profile )
    _ATOHT-TAIL-BODY _ATOHT-TAIL-PROFILE-OFF + ;

: _ATOHT-ASSERT  ( flag -- )
    1 _ATOHT-CHECKS +!
    0= IF
        1 _ATOHT-FAILS +!
        ." AT OAUTH HRES ASSERT " _ATOHT-CHECKS @ . CR
    THEN ;

: _ATOHT-STATUS  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH HRES STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _ATOHT-ASSERT ;

: _ATOHT-STACK  ( -- )
    DEPTH DUP _ATOHT-DEPTH @ <> IF
        ." AT OAUTH HRES STACK "
        _ATOHT-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _ATOHT-DEPTH @ = _ATOHT-ASSERT ;

: _ATOHT-WORK-ZERO?  ( -- flag )
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE _atopt-zero? ;

: _ATOHT-WORK-BYTE?  ( byte -- flag )
    AT-OAUTH-HRES-WORKSPACE-SIZE 0 ?DO
        DUP _ATOHT-WORK I + C@ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _ATOHT-PHASE  ( expected -- )
    >R
    _atopt-profile AT-OAUTH-PROFILE-PHASE@
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    R> = _ATOHT-ASSERT ;

: _ATOHT-FAILED  ( expected-status -- )
    >R
    AT-OAUTH-PROFILE-PHASE-FAILED _ATOHT-PHASE
    _atopt-profile AT-OAUTH-PROFILE-STATUS@
        R> _ATOHT-STATUS ;

: _ATOHT-BEGIN  ( -- )
    _atopt-build-identity
    _atopt-profile AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _atopt-id _atopt-profile AT-OAUTH-PROFILE-BEGIN
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA _ATOHT-PHASE ;

: _ATOHT-RESOURCE-TARGET  ( -- target )
    _atopt-profile
    AT-OAUTH-PROFILE-RESOURCE-METADATA-TARGET@
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS ;

: _ATOHT-AS-TARGET  ( -- target )
    _atopt-profile
    AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-METADATA-TARGET@
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS ;

\ =====================================================================
\  Scripted HTTP response and resource setup
\ =====================================================================

: _ATOHT-BUILD-FINAL
  ( hop status media-a media-u body-a body-u -- )
    _ATOHT-RESPONSE-U !
    _ATOHT-RESPONSE-A !
    _ATOHT-MEDIA-U !
    _ATOHT-MEDIA-A !
    _ATOHT-STATUS-V !
    _hrc-response-select
    S" HTTP/1.1 " _hrc-response,
    _ATOHT-STATUS-V @ NUM>STR _hrc-response,
    S"  OAuth Metadata" _hrc-response-line,
    _ATOHT-MEDIA-U @ IF
        S" Content-Type: " _hrc-response,
        _ATOHT-MEDIA-A @ _ATOHT-MEDIA-U @ _hrc-response,
        _hrc-response-crlf,
    THEN
    _ATOHT-RESPONSE-U @ _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    _ATOHT-RESPONSE-A @ _ATOHT-RESPONSE-U @ _hrc-response, ;

: _ATOHT-BUILD-JSON  ( hop status -- )
    S" Application/JSON; charset=utf-8"
    _atopt-body _atopt-body-u @
    _ATOHT-BUILD-FINAL ;

: _ATOHT-BUILD-TEXT  ( hop status -- )
    S" text/plain"
    _atopt-body _atopt-body-u @
    _ATOHT-BUILD-FINAL ;

: _ATOHT-SETUP  ( uri-a uri-u weak? -- )
    _ATOHT-WEAK !
    _ATOHT-URI-U !
    _ATOHT-URI-A !
    _hrc-spec HRES-SPEC-INIT
    _ATOHT-URI-A @ _ATOHT-URI-U @
        _hrc-spec HRES-SPEC-TARGET!
        HRES-S-OK _ATOHT-STATUS
    _ATOHT-WEAK @ IF
        S" */*" _hrc-spec HRES-SPEC-ACCEPT!
            HRES-S-OK _ATOHT-STATUS
        200 299 _hrc-spec HRES-SPEC-SUCCESS-RANGE!
            HRES-S-OK _ATOHT-STATUS
        1 _hrc-spec HRES-SPEC-REDIRECT-MAX!
            HRES-S-OK _ATOHT-STATUS
        HRES-MEDIA-REQUIRED _hrc-spec HRES-SPEC-MEDIA-MODE!
            HRES-S-OK _ATOHT-STATUS
        _hrc-resource ['] _hrc-media-policy
            _hrc-spec HRES-SPEC-MEDIA!
            HRES-S-OK _ATOHT-STATUS
    ELSE
        _hrc-spec AT-OAUTH-HRES-SPEC-POLICY!
            HRES-S-OK _ATOHT-STATUS
    THEN
    _hrc-resource ['] _hrc-bind ['] _hrc-release
        _hrc-spec HRES-SPEC-BINDING!
        HRES-S-OK _ATOHT-STATUS
    _hrc-spec HRES-SPEC-SEAL HRES-S-OK _ATOHT-STATUS
    _hrc-spec HRES-SPEC-VALID? _ATOHT-ASSERT
    _hrc-resource HRES-INIT
    _ATOHT-BODY-CAP _hrc-body-cap !
    _hrc-spec _hrc-body _ATOHT-BODY-CAP
        _hrc-resource HRES-CONFIGURE
        HRES-S-OK _ATOHT-STATUS ;

: _ATOHT-SETUP-TARGET  ( target weak? -- )
    >R HTARGET-URI$ R> _ATOHT-SETUP ;

: _ATOHT-RUN  ( -- )
    _hrc-run-resource HRES-S-OK _ATOHT-STATUS ;

: _ATOHT-CLEAN  ( -- )
    _hrc-resource HRES-WIPE HRES-S-OK _ATOHT-STATUS
    _hrc-body _ATOHT-BODY-CAP _hrc-zero? _ATOHT-ASSERT
    _hrc-resource HRES-DECONFIGURE HRES-S-OK _ATOHT-STATUS
    _hrc-resource HRES-STATE@ HRES-STATE-IDLE =
        _ATOHT-ASSERT
    _hrc-lease-errors @ 0= _ATOHT-ASSERT
    _hrc-binds @ _hrc-releases @ = _ATOHT-ASSERT ;

: _ATOHT-CALL-RESOURCE  ( weak? -- profile-status )
    >R
    _hrc-fixture-reset
    0 200 _ATOHT-BUILD-JSON
    _ATOHT-RESOURCE-TARGET R> _ATOHT-SETUP-TARGET
    _ATOHT-RUN
    _hrc-resource _ATOHT-WORK _atopt-profile
        AT-OAUTH-HRES-RESOURCE!
    >R _ATOHT-CLEAN R> ;

: _ATOHT-CALL-AS  ( weak? -- profile-status )
    >R
    _hrc-fixture-reset
    0 200 _ATOHT-BUILD-JSON
    _ATOHT-AS-TARGET R> _ATOHT-SETUP-TARGET
    _ATOHT-RUN
    _hrc-resource _ATOHT-WORK _atopt-profile
        AT-OAUTH-HRES-AUTHORIZATION-SERVER!
    >R _ATOHT-CLEAN R> ;

: _ATOHT-ADMIT-RESOURCE  ( -- )
    _atopt-rmeta-defaults
    _atopt-build-rmeta
    0 _ATOHT-CALL-RESOURCE
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA
        _ATOHT-PHASE ;

\ =====================================================================
\  Contract groups
\ =====================================================================

: _ATOHT-TEST-POLICY  ( -- )
    _hrc-fixture-reset
    _hrc-spec HRES-SPEC-INIT
    S" https://pds.example/.well-known/oauth-protected-resource"
        _hrc-spec HRES-SPEC-TARGET!
        HRES-S-OK _ATOHT-STATUS
    S" */*" _hrc-spec HRES-SPEC-ACCEPT!
        HRES-S-OK _ATOHT-STATUS
    200 299 _hrc-spec HRES-SPEC-SUCCESS-RANGE!
        HRES-S-OK _ATOHT-STATUS
    3 _hrc-spec HRES-SPEC-REDIRECT-MAX!
        HRES-S-OK _ATOHT-STATUS
    HRES-MEDIA-IGNORED _hrc-spec HRES-SPEC-MEDIA-MODE!
        HRES-S-OK _ATOHT-STATUS
    _hrc-spec AT-OAUTH-HRES-SPEC-POLICY!
        HRES-S-OK _ATOHT-STATUS
    _hrc-spec HRES-SPEC-ACCEPT$
        S" application/json" STR-STR= _ATOHT-ASSERT
    _hrc-spec HRSPEC.SUCCESS-LOW @ 200 = _ATOHT-ASSERT
    _hrc-spec HRSPEC.SUCCESS-HIGH @ 200 = _ATOHT-ASSERT
    _hrc-spec HRSPEC.REDIRECT-MAX @ 0= _ATOHT-ASSERT
    _hrc-spec HRSPEC.MEDIA-MODE @ HRES-MEDIA-REQUIRED =
        _ATOHT-ASSERT
    _hrc-spec HRSPEC.MEDIA-CONTEXT @ 0= _ATOHT-ASSERT
    _hrc-spec HRSPEC.MEDIA-XT @ 0<> _ATOHT-ASSERT
    _hrc-resource ['] _hrc-bind ['] _hrc-release
        _hrc-spec HRES-SPEC-BINDING!
        HRES-S-OK _ATOHT-STATUS
    _hrc-spec HRES-SPEC-SEAL HRES-S-OK _ATOHT-STATUS
    _hrc-spec HRES-SPEC-VALID? _ATOHT-ASSERT
    _hrc-spec AT-OAUTH-HRES-SPEC-POLICY!
        HRES-S-STATE _ATOHT-STATUS
    0 AT-OAUTH-HRES-SPEC-POLICY!
        HRES-S-INVALID _ATOHT-STATUS
    _ATOHT-STACK ;

: _ATOHT-TEST-HAPPY  ( -- )
    _ATOHT-BEGIN
    _ATOHT-ADMIT-RESOURCE
    _atopt-as-defaults
    _atopt-build-asmeta
    0 _ATOHT-CALL-AS
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-READY _ATOHT-PHASE
    _atopt-profile AT-OAUTH-PROFILE-READY? _ATOHT-ASSERT
    _atopt-profile AT-OAUTH-PROFILE-TOKEN-TARGET@
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
        HTARGET-URI$ S" https://auth.example/token"
        STR-STR= _ATOHT-ASSERT
    _ATOHT-STACK ;

: _ATOHT-EXPECT-RESOURCE-HTTP  ( -- )
    _hrc-resource _ATOHT-WORK _atopt-profile
        AT-OAUTH-HRES-RESOURCE!
        AT-OAUTH-PROFILE-S-HTTP _ATOHT-STATUS
    165 _ATOHT-WORK-BYTE? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA _ATOHT-PHASE ;

: _ATOHT-TEST-ENVELOPE  ( -- )
    _ATOHT-BEGIN
    _atopt-rmeta-defaults
    _atopt-build-rmeta

    \ A deliberately weakened HRES status range admits 201.  The adapter
    \ still requires the discovery profile's exact status 200.
    _hrc-fixture-reset
    0 201 _ATOHT-BUILD-JSON
    _ATOHT-RESOURCE-TARGET -1 _ATOHT-SETUP-TARGET
    _ATOHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOHT-ASSERT
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 165 FILL
    _ATOHT-EXPECT-RESOURCE-HTTP
    _ATOHT-CLEAN

    \ A permissive HRES media callback admits text/plain.  The adapter
    \ independently requires application/json.
    _hrc-fixture-reset
    0 200 _ATOHT-BUILD-TEXT
    _ATOHT-RESOURCE-TARGET -1 _ATOHT-SETUP-TARGET
    _ATOHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOHT-ASSERT
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 165 FILL
    _ATOHT-EXPECT-RESOURCE-HTTP
    _ATOHT-CLEAN

    \ A weakened redirect budget admits a same-origin hop.  The adapter
    \ independently requires zero redirects and an unchanged target.
    _hrc-fixture-reset
    0 S" /moved" _hrc-build-redirect
    1 200 _ATOHT-BUILD-JSON
    _ATOHT-RESOURCE-TARGET -1 _ATOHT-SETUP-TARGET
    _ATOHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOHT-ASSERT
    _hrc-resource HRES-REDIRECT-COUNT@ 1 =
        _ATOHT-ASSERT
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 165 FILL
    _ATOHT-EXPECT-RESOURCE-HTTP
    _ATOHT-CLEAN

    \ A valid result for a different request target cannot be replayed
    \ into the current profile phase.
    _hrc-fixture-reset
    0 200 _ATOHT-BUILD-JSON
    S" https://wrong.example/.well-known/oauth-protected-resource"
        -1 _ATOHT-SETUP
    _ATOHT-RUN
    _hrc-resource HRES-RESULT-VALID? _ATOHT-ASSERT
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 165 FILL
    _ATOHT-EXPECT-RESOURCE-HTTP
    _ATOHT-CLEAN

    \ Envelope rejection is retryable.
    _atopt-build-rmeta
    0 _ATOHT-CALL-RESOURCE
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA
        _ATOHT-PHASE
    _ATOHT-STACK ;

: _ATOHT-MALFORMED  ( -- )
    _atopt-reset-body
    S" {" _atopt-text ;

: _ATOHT-TEST-RETRY  ( -- )
    _ATOHT-BEGIN
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 165 FILL
    _ATOHT-MALFORMED
    0 _ATOHT-CALL-RESOURCE
        AT-OAUTH-PROFILE-S-RESOURCE-METADATA _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA _ATOHT-PHASE

    \ The failed parse cannot leave a reusable result in the workspace.
    _atopt-rmeta-defaults
    _atopt-build-rmeta
    0 _ATOHT-CALL-RESOURCE
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA
        _ATOHT-PHASE

    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 90 FILL
    _ATOHT-MALFORMED
    0 _ATOHT-CALL-AS
        AT-OAUTH-PROFILE-S-AUTHORIZATION-SERVER _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA
        _ATOHT-PHASE

    _atopt-as-defaults
    _atopt-build-asmeta
    0 _ATOHT-CALL-AS
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-READY _ATOHT-PHASE
    _ATOHT-STACK ;

: _ATOHT-TEST-SEMANTIC  ( -- )
    \ Parse success exposes the resource binding mismatch to the pure
    \ profile, which terminalizes the trust chain.
    _ATOHT-BEGIN
    _atopt-rmeta-defaults
    S" https://other-pds.example"
        _atopt-resource-u ! _atopt-resource-a !
    _atopt-build-rmeta
    0 _ATOHT-CALL-RESOURCE
        AT-OAUTH-PROFILE-S-RESOURCE-BINDING _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-S-RESOURCE-BINDING _ATOHT-FAILED

    \ The authorization-server document is fetched from the selected
    \ server, but a different issuer inside it is still terminal.
    _ATOHT-BEGIN
    _ATOHT-ADMIT-RESOURCE
    _atopt-as-defaults
    S" https://other-auth.example"
        _atopt-issuer-u ! _atopt-issuer-a !
    _atopt-build-asmeta
    0 _ATOHT-CALL-AS
        AT-OAUTH-PROFILE-S-ISSUER-BINDING _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT
    AT-OAUTH-PROFILE-S-ISSUER-BINDING _ATOHT-FAILED
    _ATOHT-STACK ;

: _ATOHT-TEST-GEOMETRY  ( -- )
    _ATOHT-BEGIN

    \ Rejected clear geometry is non-mutating; admitted clear wipes all
    \ transient result and parser bytes.
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 90 FILL
    _ATOHT-WORK 1+ AT-OAUTH-HRES-WORKSPACE-CLEAR
        AT-OAUTH-PROFILE-S-INVALID _ATOHT-STATUS
    _ATOHT-WORK C@ 90 = _ATOHT-ASSERT
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-CLEAR
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _ATOHT-WORK-ZERO? _ATOHT-ASSERT

    \ Workspace/profile alignment and pairwise ownership are admitted
    \ before any HRES or profile state is consumed.
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 90 FILL
    _hrc-resource _ATOHT-WORK 1+ _atopt-profile
        AT-OAUTH-HRES-RESOURCE!
        AT-OAUTH-PROFILE-S-INVALID _ATOHT-STATUS
    _hrc-resource _ATOHT-WORK _atopt-profile 1+
        AT-OAUTH-HRES-RESOURCE!
        AT-OAUTH-PROFILE-S-INVALID _ATOHT-STATUS
    _ATOHT-WORK _ATOHT-WORK _atopt-profile
        AT-OAUTH-HRES-RESOURCE!
        AT-OAUTH-PROFILE-S-ALIAS _ATOHT-STATUS
    _atopt-profile _ATOHT-WORK _atopt-profile
        AT-OAUTH-HRES-RESOURCE!
        AT-OAUTH-PROFILE-S-ALIAS _ATOHT-STATUS
    _ATOHT-WORK C@ 90 = _ATOHT-ASSERT
    AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA _ATOHT-PHASE
    _ATOHT-WORK AT-OAUTH-HRES-WORKSPACE-SIZE 0 FILL

    \ The used body ends before this profile, but the complete configured
    \ HRES buffer still owns the tail.  The storage accessor must expose
    \ that alias before parser cleanup can wipe the profile.
    _atopt-rmeta-defaults
    _atopt-build-rmeta
    _hrc-fixture-reset
    0 200 _ATOHT-BUILD-JSON
    _ATOHT-RESOURCE-TARGET 0 _ATOHT-SETUP-TARGET
    _hrc-resource HRES-DECONFIGURE HRES-S-OK _ATOHT-STATUS
    _hrc-spec _ATOHT-TAIL-BODY _ATOHT-TAIL-BODY-CAP
        _hrc-resource HRES-CONFIGURE
        HRES-S-OK _ATOHT-STATUS
    _ATOHT-RUN
    _hrc-resource HRES-BODY@ NIP
        _ATOHT-TAIL-PROFILE-OFF < _ATOHT-ASSERT
    _ATOHT-TAIL-PROFILE AT-OAUTH-PROFILE-INIT
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _atopt-id _ATOHT-TAIL-PROFILE AT-OAUTH-PROFILE-BEGIN
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
    _hrc-resource _ATOHT-WORK _ATOHT-TAIL-PROFILE
        AT-OAUTH-HRES-RESOURCE!
        AT-OAUTH-PROFILE-S-ALIAS _ATOHT-STATUS
    _ATOHT-TAIL-PROFILE AT-OAUTH-PROFILE-VALID?
        _ATOHT-ASSERT
    _ATOHT-TAIL-PROFILE AT-OAUTH-PROFILE-PHASE@
        AT-OAUTH-PROFILE-S-OK _ATOHT-STATUS
        AT-OAUTH-PROFILE-PHASE-RESOURCE-METADATA =
        _ATOHT-ASSERT
    _hrc-resource HRES-WIPE HRES-S-OK _ATOHT-STATUS
    _ATOHT-TAIL-BODY _ATOHT-TAIL-BODY-CAP
        _hrc-zero? _ATOHT-ASSERT
    _hrc-resource HRES-DECONFIGURE HRES-S-OK _ATOHT-STATUS
    _hrc-lease-errors @ 0= _ATOHT-ASSERT
    _hrc-binds @ _hrc-releases @ = _ATOHT-ASSERT
    _ATOHT-STACK ;

\ =====================================================================
\  Harness entry points
\ =====================================================================

: _ATOHT-INIT  ( -- )
    0 _ATOHT-CHECKS !
    0 _ATOHT-FAILS !
    0 _hrc-fails !
    _ATOPT-INIT
    DEPTH _ATOHT-DEPTH ! ;

: _ATOHT-FINISH  ( -- )
    _ATOHT-STACK
    _atopt-fails @ 0= _ATOHT-ASSERT
    _hrc-fails @ 0= _ATOHT-ASSERT
    _ATOHT-FAILS @ _atopt-fails @ + IF
        ." AT OAUTH HRES FAIL checks/fails "
        _ATOHT-CHECKS @ _atopt-checks @ + .
        _ATOHT-FAILS @ _atopt-fails @ + . CR
    ELSE
        ." AT OAUTH HRES PASS "
        _ATOHT-CHECKS @ _atopt-checks @ + . CR
    THEN ;

: _ATOHT-RUN-ALL  ( -- )
    _ATOHT-INIT
    _ATOHT-TEST-POLICY
    _ATOHT-TEST-HAPPY
    _ATOHT-TEST-ENVELOPE
    _ATOHT-TEST-RETRY
    _ATOHT-TEST-SEMANTIC
    _ATOHT-TEST-GEOMETRY
    _ATOHT-FINISH ;

_ATOHT-TAIL-BODY-CAP HRES-BODY-MAX > [IF]
    ." AT OAuth HRES tail-alias fixture exceeds HRES body bound" CR
    ABORT
[THEN]
