\ Focused gates for retained remote-JWKS AT OAuth composition.
\
\ The generic HRES transport, deployment binder, checked selector, and
\ durable-owner seam are loaded separately.  This fixture acquires two exact
\ deterministic results sequentially, snapshots each complete retained
\ result into separate caller-owned storage, and exercises only the remote
\ vertical-slice gates.

PROVIDED at-oauth-rhres-test

VARIABLE _ATORHT-CHECKS
VARIABLE _ATORHT-FAILS
VARIABLE _ATORHT-DEPTH
VARIABLE _ATORHT-CALLBACKS

VARIABLE _ATORHT-CLONE-SOURCE
VARIABLE _ATORHT-CLONE-DEST
VARIABLE _ATORHT-CLONE-BODY
VARIABLE _ATORHT-CLONE-A
VARIABLE _ATORHT-CLONE-U

VARIABLE _ATORHT-URI-A
VARIABLE _ATORHT-URI-U
VARIABLE _ATORHT-DOC-A
VARIABLE _ATORHT-DOC-U
VARIABLE _ATORHT-DEST-RESOURCE
VARIABLE _ATORHT-DEST-BODY

VARIABLE _ATORHT-RESPONSE-STATUS
VARIABLE _ATORHT-RESPONSE-MEDIA-A
VARIABLE _ATORHT-RESPONSE-MEDIA-U
VARIABLE _ATORHT-RESPONSE-BODY-A
VARIABLE _ATORHT-RESPONSE-BODY-U

VARIABLE _ATORHT-CALLBACK
VARIABLE _ATORHT-CALL-WORK

VARIABLE _ATORHT-CB-CONFIG
VARIABLE _ATORHT-CB-METADATA
VARIABLE _ATORHT-CB-KID-A
VARIABLE _ATORHT-CB-KID-U
VARIABLE _ATORHT-CB-CLIENT-PUBLIC
VARIABLE _ATORHT-CB-CLIENT-THUMB
VARIABLE _ATORHT-CB-DPOP-PUBLIC
VARIABLE _ATORHT-CB-DPOP-THUMB
VARIABLE _ATORHT-CB-CONTEXT

VARIABLE _ATORHT-SAVED-BODY-A
VARIABLE _ATORHT-SAVED-BODY-CAP
VARIABLE _ATORHT-OTHER-BODY-A
VARIABLE _ATORHT-OTHER-BODY-CAP

4096 CONSTANT _ATORHT-BODY-CAP
4096 CONSTANT _ATORHT-TAIL-WORK-OFF
_ATORHT-TAIL-WORK-OFF AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE +
    CONSTANT _ATORHT-TAIL-BODY-CAP

0x41544F5248544358 CONSTANT _ATORHT-CONTEXT
0x41544F5248545253 CONSTANT _ATORHT-RESULT

CREATE _atorht-meta-resource-storage HTTP-RESOURCE-SIZE 7 + ALLOT
CREATE _atorht-jwks-resource-storage HTTP-RESOURCE-SIZE 7 + ALLOT
CREATE _atorht-meta-body _ATORHT-BODY-CAP ALLOT
CREATE _atorht-jwks-body _ATORHT-BODY-CAP ALLOT
CREATE _atorht-acquire-body _ATORHT-BODY-CAP ALLOT
CREATE _atorht-jwks-document _ATORHT-BODY-CAP ALLOT
VARIABLE _atorht-jwks-document-u

CREATE _atorht-target-storage HTARGET-SIZE 7 + ALLOT
CREATE _atorht-work-storage
    AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE 7 + ALLOT
CREATE _atorht-tail-storage _ATORHT-TAIL-BODY-CAP 7 + ALLOT

: _atorht-meta-resource  ( -- resource )
    _atorht-meta-resource-storage 7 + -8 AND ;

: _atorht-jwks-resource  ( -- resource )
    _atorht-jwks-resource-storage 7 + -8 AND ;

: _atorht-target  ( -- target )
    _atorht-target-storage 7 + -8 AND ;

: _atorht-work  ( -- workspace )
    _atorht-work-storage 7 + -8 AND ;

: _atorht-tail-body  ( -- body )
    _atorht-tail-storage 7 + -8 AND ;

: _atorht-tail-work  ( -- workspace )
    _atorht-tail-body _ATORHT-TAIL-WORK-OFF + ;

: _ATORHT-ASSERT  ( flag -- )
    1 _ATORHT-CHECKS +!
    0= IF
        1 _ATORHT-FAILS +!
        ." AT OAUTH REMOTE HRES ASSERT " _ATORHT-CHECKS @ . CR
        TX-FLUSH
    THEN ;

: _ATORHT-STATUS  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH REMOTE HRES STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _ATORHT-ASSERT ;

: _ATORHT-STACK  ( -- )
    DEPTH DUP _ATORHT-DEPTH @ <> IF
        ." AT OAUTH REMOTE HRES STACK "
        _ATORHT-DEPTH @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _ATORHT-DEPTH @ = _ATORHT-ASSERT ;

: _ATORHT-WORK-FILL  ( workspace -- )
    AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE 0xA5 FILL ;

: _ATORHT-WORK-FILLED?  ( workspace -- flag )
    AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE
    0xA5 _atodt-byte? ;

: _ATORHT-WORK-ZERO?  ( workspace -- flag )
    AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE _atodt-zero? ;

: _ATORHT-TARGET-FILL  ( -- )
    _atorht-target HTARGET-SIZE 0xA5 FILL ;

: _ATORHT-TARGET-FILLED?  ( -- flag )
    _atorht-target HTARGET-SIZE 0xA5 _atodt-byte? ;

: _ATORHT-BUILD-FINAL
  ( hop status media-a media-u body-a body-u -- )
    _ATORHT-RESPONSE-BODY-U !
    _ATORHT-RESPONSE-BODY-A !
    _ATORHT-RESPONSE-MEDIA-U !
    _ATORHT-RESPONSE-MEDIA-A !
    _ATORHT-RESPONSE-STATUS !
    _hrc-response-select
    S" HTTP/1.1 " _hrc-response,
    _ATORHT-RESPONSE-STATUS @ NUM>STR _hrc-response,
    S"  OAuth Resource" _hrc-response-line,
    S" Content-Type: " _hrc-response,
    _ATORHT-RESPONSE-MEDIA-A @
    _ATORHT-RESPONSE-MEDIA-U @ _hrc-response,
    _hrc-response-crlf,
    _ATORHT-RESPONSE-BODY-U @ _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    _ATORHT-RESPONSE-BODY-A @
    _ATORHT-RESPONSE-BODY-U @ _hrc-response, ;

: _ATORHT-SETUP  ( uri-a uri-u storage-a storage-u -- )
    _ATORHT-CLONE-U !
    _ATORHT-CLONE-A !
    _ATORHT-URI-U !
    _ATORHT-URI-A !

    _hrc-spec HRES-SPEC-INIT
    _ATORHT-URI-A @ _ATORHT-URI-U @
    _hrc-spec HRES-SPEC-TARGET!
        HRES-S-OK _ATORHT-STATUS
    _hrc-spec AT-OAUTH-REMOTE-HRES-SPEC-POLICY!
        HRES-S-OK _ATORHT-STATUS
    _hrc-resource ['] _hrc-bind ['] _hrc-release
    _hrc-spec HRES-SPEC-BINDING!
        HRES-S-OK _ATORHT-STATUS
    _hrc-resource ['] _hrc-media-policy
    _hrc-spec HRES-SPEC-MEDIA!
        HRES-S-OK _ATORHT-STATUS
    _hrc-spec HRES-SPEC-SEAL HRES-S-OK _ATORHT-STATUS
    _hrc-spec HRES-SPEC-VALID? _ATORHT-ASSERT

    _hrc-resource HRES-INIT
    _hrc-spec
    _ATORHT-CLONE-A @ _ATORHT-CLONE-U @
    _hrc-resource HRES-CONFIGURE
        HRES-S-OK _ATORHT-STATUS ;

: _ATORHT-RUN  ( -- status )
    _hrc-resource HRES-START
    DUP HRES-S-PENDING <> IF EXIT THEN
    DROP
    BEGIN
        _hrc-resource HRES-POLL
        DUP HRES-S-PENDING =
    WHILE
        DROP
    REPEAT ;

\ A completed HRES value is self-contained except for its caller-owned body
\ and the request buffer's self pointer.  The clone is never polled or cleaned;
\ it is a stable retained-result value for this adapter-only qualification.
: _ATORHT-CLONE-RESULT  ( source destination body -- )
    _ATORHT-CLONE-BODY !
    _ATORHT-CLONE-DEST !
    _ATORHT-CLONE-SOURCE !

    _ATORHT-CLONE-SOURCE @ HRES-BODY@
    _ATORHT-CLONE-U !
    _ATORHT-CLONE-A !
    _ATORHT-CLONE-U @ _ATORHT-BODY-CAP <= _ATORHT-ASSERT

    _ATORHT-CLONE-SOURCE @
    _ATORHT-CLONE-DEST @
    HTTP-RESOURCE-SIZE MOVE
    _ATORHT-CLONE-A @
    _ATORHT-CLONE-BODY @
    _ATORHT-CLONE-U @ MOVE
    _ATORHT-CLONE-BODY @
    _ATORHT-CLONE-DEST @ HRES.BODY-A !
    _ATORHT-CLONE-DEST @ HRES.WIRE
    _ATORHT-CLONE-DEST @ HRES.REQUEST HREQ.BUFFER !

    _ATORHT-CLONE-DEST @ HRES-VALID? _ATORHT-ASSERT
    _ATORHT-CLONE-DEST @ HRES-RESULT-VALID? _ATORHT-ASSERT ;

: _ATORHT-ACQUIRE
  ( uri-a uri-u document-a document-u destination body -- )
    _ATORHT-DEST-BODY !
    _ATORHT-DEST-RESOURCE !
    _ATORHT-DOC-U !
    _ATORHT-DOC-A !
    _ATORHT-URI-U !
    _ATORHT-URI-A !

    _hrc-fixture-reset
    0 200
    S" Application/JSON; charset=utf-8"
    _ATORHT-DOC-A @ _ATORHT-DOC-U @
    _ATORHT-BUILD-FINAL
    _ATORHT-URI-A @ _ATORHT-URI-U @
    _atorht-acquire-body _ATORHT-BODY-CAP
    _ATORHT-SETUP
    _ATORHT-RUN HRES-S-OK _ATORHT-STATUS
    _hrc-resource HRES-RESULT-VALID? _ATORHT-ASSERT
    _hrc-binds @ 1 = _ATORHT-ASSERT
    _hrc-releases @ 1 = _ATORHT-ASSERT
    _hrc-lease-errors @ 0= _ATORHT-ASSERT

    _hrc-resource
    _ATORHT-DEST-RESOURCE @
    _ATORHT-DEST-BODY @
    _ATORHT-CLONE-RESULT

    _hrc-resource HRES-WIPE HRES-S-OK _ATORHT-STATUS
    _hrc-resource HRES-DECONFIGURE HRES-S-OK _ATORHT-STATUS ;

: _ATORHT-SEAM-RESET  ( -- )
    _ATOID-RESET
    _atoit-seam-defaults
    _atorht-jwks-resource HRES-BODY@
    _ATOID-EXPECT-JWKS-U !
    _ATOID-EXPECT-JWKS-A ! ;

: _ATORHT-DERIVE  ( -- status )
    _atorht-meta-resource
    _atodt-config
    _atopt-profile
    _atorht-target
    _atorht-work
    AT-OAUTH-REMOTE-HRES-JWKS-TARGET! ;

: _ATORHT-CALL  ( callback workspace -- callback-result status )
    _ATORHT-CALL-WORK !
    _ATORHT-CALLBACK !
    _atorht-meta-resource
    _atorht-jwks-resource
    _atodt-config
    _atopt-profile
    _atoit-vault
    _ATORHT-CALLBACK @
    _ATORHT-CONTEXT
    _ATORHT-CALL-WORK @
    AT-OAUTH-REMOTE-HRES-WITH ;

: _ATORHT-REMOTE-CALLBACK
  ( config-view metadata-view kid-a kid-u client-public client-thumb dpop-public dpop-thumb context -- callback-result )
    1 _ATORHT-CALLBACKS +!
    _ATORHT-CB-CONTEXT !
    _ATORHT-CB-DPOP-THUMB !
    _ATORHT-CB-DPOP-PUBLIC !
    _ATORHT-CB-CLIENT-THUMB !
    _ATORHT-CB-CLIENT-PUBLIC !
    _ATORHT-CB-KID-U !
    _ATORHT-CB-KID-A !
    _ATORHT-CB-METADATA !
    _ATORHT-CB-CONFIG !

    _ATORHT-CB-CONTEXT @ _ATORHT-CONTEXT =
        _ATORHT-ASSERT
    _ATORHT-CB-CONFIG @ _atodt-config = _ATORHT-ASSERT
    _ATORHT-CB-CONFIG @ OAUTH2-CLIENT-VIEW-AUTH-METHOD@
    S" private_key_jwt" COMPARE 0= _ATORHT-ASSERT

    _ATORHT-CB-METADATA @
    OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-OK _ATORHT-STATUS
    DUP OAUTH2-CLIENT-METADATA-P-JWKS-URI AND 0<>
        _ATORHT-ASSERT
    OAUTH2-CLIENT-METADATA-P-JWKS AND 0=
        _ATORHT-ASSERT
    _ATORHT-CB-METADATA @
    OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@
    OAUTH2-CLIENT-METADATA-S-OK _ATORHT-STATUS
    S" https://client.example/oauth/jwks.json"
    COMPARE 0= _ATORHT-ASSERT

    _ATORHT-CB-KID-A @ _ATORHT-CB-KID-U @
    S" client-1" COMPARE 0= _ATORHT-ASSERT
    _ATORHT-CB-CLIENT-PUBLIC @ OAUTH2-P256-KEY-PUBLIC-SIZE
    _atoit-client-public OAUTH2-P256-KEY-PUBLIC-SIZE
    COMPARE 0= _ATORHT-ASSERT
    _ATORHT-CB-CLIENT-THUMB @ OAUTH2-P256-KEY-THUMBPRINT-SIZE
    _atoit-client-thumb OAUTH2-P256-KEY-THUMBPRINT-SIZE
    COMPARE 0= _ATORHT-ASSERT
    _ATORHT-CB-DPOP-PUBLIC @ OAUTH2-P256-KEY-PUBLIC-SIZE
    _atoit-dpop-public OAUTH2-P256-KEY-PUBLIC-SIZE
    COMPARE 0= _ATORHT-ASSERT
    _ATORHT-CB-DPOP-THUMB @ OAUTH2-P256-KEY-THUMBPRINT-SIZE
    _atoit-dpop-thumb OAUTH2-P256-KEY-THUMBPRINT-SIZE
    COMPARE 0= _ATORHT-ASSERT

    _ATOID-VAULT-BUSY @ 0= _ATORHT-ASSERT
    _ATOID-OWNER-DEPTH @ 0= _ATORHT-ASSERT
    _ATOID-SELECT-ACTIVE @ 0= _ATORHT-ASSERT
    _ATOID-DEPLOY-ACTIVE @ 0<> _ATORHT-ASSERT
    _ATOID-SEQUENCE @ 3 = _ATORHT-ASSERT
    _ATORHT-RESULT ;

: _ATORHT-CALLBACK-THROW  ( nine-values -- callback-result )
    1 _ATORHT-CALLBACKS +!
    _atoit-drop9
    -19891 THROW ;

: _ATORHT-REMOTE-BASELINE  ( -- )
    _atopt-profile-ready
    _atoit-baseline

    _atodt-inline-jwks-u @ _ATORHT-BODY-CAP <=
        _ATORHT-ASSERT
    _atodt-inline-jwks-a @
    _atorht-jwks-document
    _atodt-inline-jwks-u @ MOVE
    _atodt-inline-jwks-u @ _atorht-jwks-document-u !

    2 _atodt-key-mode !
    _atodt-document-build
    _atodt-snapshot

    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    _atodt-document
    _atodt-document-u @
    _atorht-meta-resource
    _atorht-meta-body
    _ATORHT-ACQUIRE

    _ATORHT-TARGET-FILL
    _atorht-work _ATORHT-WORK-FILL
    _ATORHT-DERIVE
    AT-OAUTH-REMOTE-HRES-S-OK _ATORHT-STATUS
    _atorht-target HTARGET-VALID? _ATORHT-ASSERT
    _atorht-target HTARGET-URI$
    S" https://client.example/oauth/jwks.json"
    STR-STR= _ATORHT-ASSERT
    _atorht-work _ATORHT-WORK-ZERO? _ATORHT-ASSERT

    _atorht-target HTARGET-URI$
    _atorht-jwks-document
    _atorht-jwks-document-u @
    _atorht-jwks-resource
    _atorht-jwks-body
    _ATORHT-ACQUIRE

    _ATORHT-SEAM-RESET ;

\ =====================================================================
\ Minimal gating groups
\ =====================================================================

: _ATORHT-TEST-CONTRACTS  ( -- )
    AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE 115336 =
        _ATORHT-ASSERT
    AT-OAUTH-REMOTE-HRES-S-OK
        AT-OAUTH-REMOTE-HRES-STATUS-VALID? _ATORHT-ASSERT
    AT-OAUTH-REMOTE-HRES-S-JWKS-HTTP
        AT-OAUTH-REMOTE-HRES-STATUS-VALID? _ATORHT-ASSERT
    45 AT-OAUTH-REMOTE-HRES-STATUS-VALID? 0=
        _ATORHT-ASSERT

    _hrc-spec HRES-SPEC-INIT
    _hrc-spec AT-OAUTH-REMOTE-HRES-SPEC-POLICY!
        HRES-S-OK _ATORHT-STATUS
    _hrc-spec HRES-SPEC-ACCEPT$
    S" application/json" STR-STR= _ATORHT-ASSERT
    _hrc-spec HRSPEC.SUCCESS-LOW @ 200 = _ATORHT-ASSERT
    _hrc-spec HRSPEC.SUCCESS-HIGH @ 200 = _ATORHT-ASSERT
    _hrc-spec HRSPEC.REDIRECT-MAX @ 0= _ATORHT-ASSERT
    _hrc-spec HRSPEC.MEDIA-MODE @ HRES-MEDIA-REQUIRED =
        _ATORHT-ASSERT

    _atorht-work _ATORHT-WORK-FILL
    _atorht-work AT-OAUTH-REMOTE-HRES-WORKSPACE-CLEAR
        AT-OAUTH-REMOTE-HRES-S-OK _ATORHT-STATUS
    _atorht-work _ATORHT-WORK-ZERO? _ATORHT-ASSERT
    _ATORHT-STACK ;

: _ATORHT-TEST-SUCCESS  ( -- )
    _ATORHT-REMOTE-BASELINE

    0 _ATORHT-CALLBACKS !
    _atorht-work _ATORHT-WORK-FILL
    ['] _ATORHT-REMOTE-CALLBACK
    _atorht-work _ATORHT-CALL
    AT-OAUTH-REMOTE-HRES-S-OK _ATORHT-STATUS
    _ATORHT-RESULT _ATORHT-STATUS
    _ATORHT-CALLBACKS @ 1 = _ATORHT-ASSERT
    _ATOID-DEPLOY-CALLS @ 1 = _ATORHT-ASSERT
    _ATOID-SELECT-CALLS @ 1 = _ATORHT-ASSERT
    _ATOID-CLIENT-CALLS @ 1 = _ATORHT-ASSERT
    _ATOID-DPOP-CALLS @ 1 = _ATORHT-ASSERT
    _ATOID-VIOLATIONS @ 0= _ATORHT-ASSERT
    _atorht-work _ATORHT-WORK-ZERO? _ATORHT-ASSERT

    _ATORHT-SEAM-RESET
    1 _ATOID-SELECT-MUTATION !
    _atorht-work _ATORHT-WORK-FILL
    ['] _atoit-callback-never
    _atorht-work _ATORHT-CALL
    AT-OAUTH-REMOTE-HRES-S-MISMATCH _ATORHT-STATUS
    0 _ATORHT-STATUS
    _ATOID-SELECT-CALLS @ 1 = _ATORHT-ASSERT
    _ATOID-DPOP-CALLS @ 0= _ATORHT-ASSERT
    _atorht-work _ATORHT-WORK-ZERO? _ATORHT-ASSERT

    _ATORHT-SEAM-RESET
    0 _ATORHT-CALLBACKS !
    _atorht-work _ATORHT-WORK-FILL
    ['] _ATORHT-CALLBACK-THROW
    _atorht-work _ATORHT-CALL
    AT-OAUTH-REMOTE-HRES-S-CALLBACK _ATORHT-STATUS
    0 _ATORHT-STATUS
    _ATORHT-CALLBACKS @ 1 = _ATORHT-ASSERT
    _ATOID-DPOP-CALLS @ 1 = _ATORHT-ASSERT
    _atorht-work _ATORHT-WORK-ZERO? _ATORHT-ASSERT
    _ATORHT-STACK ;

: _ATORHT-TEST-PROVENANCE  ( -- )
    S" https://wrong.example/oauth/client-metadata.json"
    _atorht-meta-resource HRES-REQUESTED-TARGET
    HTARGET-PARSE HTARGET-S-OK _ATORHT-STATUS
    _ATORHT-TARGET-FILL
    _atorht-work _ATORHT-WORK-FILL
    _ATORHT-DERIVE
    AT-OAUTH-REMOTE-HRES-S-METADATA-HTTP _ATORHT-STATUS
    _ATORHT-TARGET-FILLED? _ATORHT-ASSERT
    _atorht-work _ATORHT-WORK-FILLED? _ATORHT-ASSERT

    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    _atorht-meta-resource HRES-REQUESTED-TARGET
    HTARGET-PARSE HTARGET-S-OK _ATORHT-STATUS

    S" https://wrong.example/oauth/jwks.json"
    _atorht-jwks-resource HRES-REQUESTED-TARGET
    HTARGET-PARSE HTARGET-S-OK _ATORHT-STATUS
    _atorht-work _ATORHT-WORK-FILL
    ['] _atoit-callback-never
    _atorht-work _ATORHT-CALL
    AT-OAUTH-REMOTE-HRES-S-JWKS-HTTP _ATORHT-STATUS
    0 _ATORHT-STATUS
    _atorht-work _ATORHT-WORK-ZERO? _ATORHT-ASSERT

    S" https://client.example/oauth/jwks.json"
    _atorht-jwks-resource HRES-REQUESTED-TARGET
    HTARGET-PARSE HTARGET-S-OK _ATORHT-STATUS

    _atoit-baseline
    _atodt-document-u @ _ATORHT-BODY-CAP <= _ATORHT-ASSERT
    _atodt-document
    _atorht-meta-body
    _atodt-document-u @ MOVE
    _atodt-document-u @
    _atorht-meta-resource HRES.BODY-U !
    _ATORHT-TARGET-FILL
    _atorht-work _ATORHT-WORK-FILL
    _ATORHT-DERIVE
    AT-OAUTH-REMOTE-HRES-S-KEY-SOURCE _ATORHT-STATUS
    _ATORHT-TARGET-FILLED? _ATORHT-ASSERT
    _atorht-work _ATORHT-WORK-ZERO? _ATORHT-ASSERT
    _ATORHT-STACK ;

: _ATORHT-TEST-PREFLIGHT  ( -- )
    _atorht-jwks-resource HRES-BODY-STORAGE@
    _ATORHT-SAVED-BODY-CAP !
    _ATORHT-SAVED-BODY-A !
    _atorht-meta-resource HRES-BODY-STORAGE@
    _ATORHT-OTHER-BODY-CAP !
    _ATORHT-OTHER-BODY-A !

    _ATORHT-OTHER-BODY-A @
    _atorht-jwks-resource HRES.BODY-A !
    _ATORHT-OTHER-BODY-CAP @
    _atorht-jwks-resource HRES.BODY-CAP !
    _atorht-work _ATORHT-WORK-FILL
    ['] _atoit-callback-never
    _atorht-work _ATORHT-CALL
    AT-OAUTH-REMOTE-HRES-S-ALIAS _ATORHT-STATUS
    0 _ATORHT-STATUS
    _atorht-work _ATORHT-WORK-FILLED? _ATORHT-ASSERT

    _atorht-tail-body
    _atorht-jwks-resource HRES.BODY-A !
    _ATORHT-TAIL-BODY-CAP
    _atorht-jwks-resource HRES.BODY-CAP !
    _atorht-tail-work _ATORHT-WORK-FILL
    ['] _atoit-callback-never
    _atorht-tail-work _ATORHT-CALL
    AT-OAUTH-REMOTE-HRES-S-ALIAS _ATORHT-STATUS
    0 _ATORHT-STATUS
    _atorht-tail-work _ATORHT-WORK-FILLED? _ATORHT-ASSERT

    _ATORHT-SAVED-BODY-A @
    _atorht-jwks-resource HRES.BODY-A !
    _ATORHT-SAVED-BODY-CAP @
    _atorht-jwks-resource HRES.BODY-CAP !
    _ATORHT-STACK ;

: _ATORHT-INIT  ( -- )
    _ATOIT-INIT
    0 _ATORHT-CHECKS !
    0 _ATORHT-FAILS !
    0 _ATORHT-CALLBACKS !
    DEPTH _ATORHT-DEPTH ! ;

: _ATORHT-FINISH  ( -- )
    _atopt-fails @ 0= _ATORHT-ASSERT
    _atodt-fails @ 0= _ATORHT-ASSERT
    _atoit-fails @ 0= _ATORHT-ASSERT
    _ATORHT-STACK
    _ATORHT-FAILS @ IF
        ." AT OAUTH REMOTE HRES FAIL checks/fails "
        _ATORHT-CHECKS @ . _ATORHT-FAILS @ . CR
    ELSE
        ." AT OAUTH REMOTE HRES PASS "
        _ATORHT-CHECKS @ . CR
    THEN ;
