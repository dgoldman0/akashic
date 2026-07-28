\ Deterministic AT identity and generic HTTP-resource composition contracts.
PROVIDED atproto-identity-hres-test

VARIABLE _AIHR-FAILS
VARIABLE _AIHR-CHECKS
VARIABLE _AIHR-DEPTH
VARIABLE _AIHR-DOC-U
VARIABLE _AIHR-COPY-U
VARIABLE _AIHR-URI-A
VARIABLE _AIHR-URI-U
VARIABLE _AIHR-FINAL-A
VARIABLE _AIHR-FINAL-U
VARIABLE _AIHR-FINAL-STATUS
VARIABLE _AIHR-LOCATION-A
VARIABLE _AIHR-LOCATION-U
VARIABLE _AIHR-REDIRECT-STATUS

2048 CONSTANT _AIHR-BODY-CAP

CREATE _AIHR-RESULT-STORAGE ATID-RESULT-SIZE 7 + ALLOT
CREATE _AIHR-RESOLVER-STORAGE ATID-RESOLVER-SIZE 7 + ALLOT
CREATE _AIHR-DOC _AIHR-BODY-CAP ALLOT

: _AIHR-RESULT  ( -- result )
    _AIHR-RESULT-STORAGE 7 + -8 AND ;

: _AIHR-RESOLVER  ( -- resolver )
    _AIHR-RESOLVER-STORAGE 7 + -8 AND ;

: _AIHR-ASSERT  ( flag -- )
    1 _AIHR-CHECKS +!
    0= IF
        1 _AIHR-FAILS +!
        ." AT IDENTITY HRES ASSERT " _AIHR-CHECKS @ . CR
    THEN ;

: _AIHR-STACK  ( -- )
    DEPTH DUP _AIHR-DEPTH @ <> IF
        ." AT IDENTITY HRES STACK "
        _AIHR-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _AIHR-DEPTH @ = _AIHR-ASSERT ;

: _AIHR-TEXT  ( address length -- )
    DUP _AIHR-COPY-U !
    _AIHR-DOC _AIHR-DOC-U @ + SWAP MOVE
    _AIHR-COPY-U @ _AIHR-DOC-U +! ;

: _AIHR-CHAR  ( byte -- )
    _AIHR-DOC _AIHR-DOC-U @ + C!
    1 _AIHR-DOC-U +! ;

: _AIHR-QTEXT  ( address length -- )
    34 _AIHR-CHAR
    _AIHR-TEXT
    34 _AIHR-CHAR ;

: _AIHR-BUILD-DIDDOC  ( -- )
    _AIHR-DOC _AIHR-BODY-CAP 0 FILL
    0 _AIHR-DOC-U !
    S" {" _AIHR-TEXT
    S" id" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" did:plc:abcdefghijklmnopqrstuvwx" _AIHR-QTEXT
    S" ," _AIHR-TEXT
    S" alsoKnownAs" _AIHR-QTEXT
    S" :[" _AIHR-TEXT
    S" at://alice.example.com" _AIHR-QTEXT
    S" ]," _AIHR-TEXT
    S" verificationMethod" _AIHR-QTEXT
    S" :[{" _AIHR-TEXT
    S" id" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" #atproto" _AIHR-QTEXT
    S" ," _AIHR-TEXT
    S" type" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" Multikey" _AIHR-QTEXT
    S" ," _AIHR-TEXT
    S" controller" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" did:plc:abcdefghijklmnopqrstuvwx" _AIHR-QTEXT
    S" ," _AIHR-TEXT
    S" publicKeyMultibase" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" z123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        _AIHR-QTEXT
    S" }]," _AIHR-TEXT
    S" service" _AIHR-QTEXT
    S" :[{" _AIHR-TEXT
    S" id" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" #atproto_pds" _AIHR-QTEXT
    S" ," _AIHR-TEXT
    S" type" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" AtprotoPersonalDataServer" _AIHR-QTEXT
    S" ," _AIHR-TEXT
    S" serviceEndpoint" _AIHR-QTEXT
    S" :" _AIHR-TEXT
    S" https://pds.example.com" _AIHR-QTEXT
    S" }]}" _AIHR-TEXT ;

: _AIHR-RESET  ( -- )
    _AIHR-RESULT ATID-RESULT-INIT ATID-S-OK = _AIHR-ASSERT
    _AIHR-RESOLVER ATID-RESOLVER-CLEAR ATID-S-OK = _AIHR-ASSERT
    _AIHR-DOC _AIHR-BODY-CAP 0 FILL
    0 _AIHR-DOC-U ! ;

: _AIHR-ACTION?  ( expected -- )
    >R
    _AIHR-RESOLVER ATID-ACTION@
    ATID-S-OK = _AIHR-ASSERT
    R> = _AIHR-ASSERT ;

: _AIHR-CURRENT-TARGET  ( -- target )
    _AIHR-RESOLVER ATID-HTTP-TARGET@
    ATID-S-OK = _AIHR-ASSERT ;

: _AIHR-BUILD-FINAL  ( hop status body-a body-u -- )
    _AIHR-FINAL-U ! _AIHR-FINAL-A ! _AIHR-FINAL-STATUS !
    _hrc-response-select
    S" HTTP/1.1 " _hrc-response,
    _AIHR-FINAL-STATUS @ NUM>STR _hrc-response,
    S"  Policy" _hrc-response-line,
    _AIHR-FINAL-U @ _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    _AIHR-FINAL-A @ _AIHR-FINAL-U @ _hrc-response, ;

: _AIHR-BUILD-REDIRECT
  ( hop status location-a location-u -- )
    _AIHR-LOCATION-U ! _AIHR-LOCATION-A ! _AIHR-REDIRECT-STATUS !
    _hrc-response-select
    S" HTTP/1.1 " _hrc-response,
    _AIHR-REDIRECT-STATUS @ NUM>STR _hrc-response,
    S"  Redirect" _hrc-response-line,
    S" Location: " _hrc-response,
    _AIHR-LOCATION-A @ _AIHR-LOCATION-U @ _hrc-response,
    _hrc-response-crlf,
    0 _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf, ;

: _AIHR-SETUP  ( uri-a uri-u -- )
    _AIHR-URI-U ! _AIHR-URI-A !
    _hrc-spec HRES-SPEC-INIT
    _AIHR-URI-A @ _AIHR-URI-U @ _hrc-spec HRES-SPEC-TARGET!
        HRES-S-OK = _AIHR-ASSERT
    S" */*" _hrc-spec HRES-SPEC-ACCEPT!
        HRES-S-OK = _AIHR-ASSERT
    _hrc-spec ATID-HRES-SPEC-POLICY!
        HRES-S-OK = _AIHR-ASSERT
    _hrc-resource ['] _hrc-bind ['] _hrc-release
        _hrc-spec HRES-SPEC-BINDING!
        HRES-S-OK = _AIHR-ASSERT
    _hrc-spec HRES-SPEC-SEAL HRES-S-OK = _AIHR-ASSERT
    _hrc-spec HRES-SPEC-VALID? _AIHR-ASSERT
    _hrc-resource HRES-INIT
    _AIHR-BODY-CAP _hrc-body-cap !
    _hrc-spec _hrc-body _AIHR-BODY-CAP
        _hrc-resource HRES-CONFIGURE
        HRES-S-OK = _AIHR-ASSERT ;

: _AIHR-SETUP-CURRENT  ( -- )
    _AIHR-CURRENT-TARGET HTARGET-URI$ _AIHR-SETUP ;

: _AIHR-RUN-RESOURCE  ( -- )
    _hrc-run-resource HRES-S-OK = _AIHR-ASSERT ;

: _AIHR-CLEAN  ( -- )
    _hrc-resource HRES-WIPE HRES-S-OK = _AIHR-ASSERT
    _hrc-body _AIHR-BODY-CAP _hrc-zero? _AIHR-ASSERT
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _AIHR-ASSERT
    _hrc-resource HRES-STATE@ HRES-STATE-IDLE = _AIHR-ASSERT
    _hrc-lease-errors @ 0= _AIHR-ASSERT
    _hrc-binds @ _hrc-releases @ = _AIHR-ASSERT ;

: _AIHR-TEST-PARTICIPATION  ( -- )
    _AIHR-RESET
    S" Alice.Example.Com" _AIHR-RESULT _AIHR-RESOLVER
    ATID-BEGIN-HANDLE ATID-S-OK = _AIHR-ASSERT
    ATID-A-DNS-QUERY _AIHR-ACTION?
    _AIHR-RESOLVER ATID-ACTION-FAIL ATID-S-OK = _AIHR-ASSERT
    ATID-A-HANDLE-HTTPS _AIHR-ACTION?

    _hrc-fixture-reset
    0 302 S" https://identity.example.com/value"
        _AIHR-BUILD-REDIRECT
    1 203 S" did:plc:abcdefghijklmnopqrstuvwx"
        _AIHR-BUILD-FINAL
    _AIHR-SETUP-CURRENT
    _AIHR-RUN-RESOURCE
    _hrc-resource HRES-RESULT-VALID? _AIHR-ASSERT
    _hrc-resource HRES-HTTP-STATUS@ 203 = _AIHR-ASSERT
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _AIHR-ASSERT
    _hrc-resource HRES-REQUESTED-URI$
        S" https://alice.example.com/.well-known/atproto-did"
        STR-STR= _AIHR-ASSERT
    _hrc-resource HRES-EFFECTIVE-URI$
        S" https://identity.example.com/value"
        STR-STR= _AIHR-ASSERT
    _hrc-resource HRES-BODY@
        S" did:plc:abcdefghijklmnopqrstuvwx"
        STR-STR= _AIHR-ASSERT
    _hrc-resource HRES-MEDIA@
        0= _AIHR-ASSERT 0= _AIHR-ASSERT
    _hrc-binds @ 2 = _AIHR-ASSERT
    _hrc-resource _AIHR-RESOLVER ATID-HRES-RESPONSE!
        ATID-S-OK = _AIHR-ASSERT
    _AIHR-RESOLVER _ATIDW.HTTP-STATUS @ 203 = _AIHR-ASSERT
    ATID-A-DID-DOCUMENT _AIHR-ACTION?
    _hrc-resource _AIHR-RESOLVER ATID-HRES-RESPONSE!
        ATID-S-HTTP = _AIHR-ASSERT
    ATID-A-DID-DOCUMENT _AIHR-ACTION?
    _AIHR-RESULT ATID-RESULT-READY? 0= _AIHR-ASSERT
    _AIHR-CLEAN

    _AIHR-BUILD-DIDDOC
    _hrc-fixture-reset
    0 307 S" https://documents.example.com/alice"
        _AIHR-BUILD-REDIRECT
    1 200 _AIHR-DOC _AIHR-DOC-U @ _AIHR-BUILD-FINAL
    _AIHR-SETUP-CURRENT
    _AIHR-RUN-RESOURCE
    _hrc-resource HRES-RESULT-VALID? _AIHR-ASSERT
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _AIHR-ASSERT
    _hrc-resource HRES-EFFECTIVE-URI$
        S" https://documents.example.com/alice"
        STR-STR= _AIHR-ASSERT
    _hrc-resource _AIHR-RESOLVER ATID-HRES-RESPONSE!
        ATID-S-OK = _AIHR-ASSERT
    _AIHR-RESOLVER _ATIDW.HTTP-STATUS @ 200 = _AIHR-ASSERT
    ATID-A-DONE _AIHR-ACTION?
    _hrc-resource _AIHR-RESOLVER ATID-HRES-RESPONSE!
        ATID-S-STATE = _AIHR-ASSERT
    ATID-A-DONE _AIHR-ACTION?
    _AIHR-RESULT ATID-RESULT-READY? _AIHR-ASSERT
    _AIHR-RESULT ATID-PARTICIPATION-READY? _AIHR-ASSERT
    _AIHR-RESULT ATID-DID@
        ATID-S-OK = _AIHR-ASSERT
        S" did:plc:abcdefghijklmnopqrstuvwx"
        STR-STR= _AIHR-ASSERT
    _AIHR-RESULT ATID-HANDLE@
        ATID-S-OK = _AIHR-ASSERT
        S" alice.example.com" STR-STR= _AIHR-ASSERT
    _AIHR-RESULT ATID-PUBLIC-KEY-MULTIBASE@
        ATID-S-OK = _AIHR-ASSERT
        S" z123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        STR-STR= _AIHR-ASSERT
    _AIHR-RESULT ATID-PDS-ORIGIN@
        ATID-S-OK = _AIHR-ASSERT
        S" https://pds.example.com/" STR-STR= _AIHR-ASSERT
    _AIHR-CLEAN
    _AIHR-RESOLVER ATID-RESOLVER-WIPE
        ATID-S-OK = _AIHR-ASSERT
    _AIHR-RESOLVER ATID-RESOLVER-SIZE
        _hrc-zero? _AIHR-ASSERT
    _AIHR-STACK ;

: _AIHR-TEST-NONDEFAULT-PORT  ( -- )
    _AIHR-RESET
    S" did:plc:abcdefghijklmnopqrstuvwx"
        _AIHR-RESULT _AIHR-RESOLVER
        ATID-BEGIN-DID ATID-S-OK = _AIHR-ASSERT
    ATID-A-DID-DOCUMENT _AIHR-ACTION?
    _hrc-fixture-reset
    0 302 S" https://other.example.com:8443/document"
        _AIHR-BUILD-REDIRECT
    _AIHR-SETUP-CURRENT
    _AIHR-RUN-RESOURCE
    _hrc-resource HRES-OUTCOME@
        HRES-O-AUTHORITY-REQUIRED = _AIHR-ASSERT
    _hrc-resource HRES-POLICY-STATUS@
        ATID-S-POLICY = _AIHR-ASSERT
    _hrc-resource HRES-REDIRECT-COUNT@ 0= _AIHR-ASSERT
    1 _hrc-resource HRES-TARGET-NTH
        HTARGET-VALID? 0= _AIHR-ASSERT
    _hrc-binds @ 1 = _AIHR-ASSERT
    _hrc-resource HRES-RESULT-VALID? 0= _AIHR-ASSERT
    _hrc-resource _AIHR-RESOLVER ATID-HRES-RESPONSE!
        ATID-S-HTTP = _AIHR-ASSERT
    ATID-A-DID-DOCUMENT _AIHR-ACTION?
    _AIHR-RESULT ATID-RESULT-READY? 0= _AIHR-ASSERT
    _AIHR-RESOLVER ATID-ACTION-FAIL
        ATID-S-HTTP = _AIHR-ASSERT
    ATID-A-FAILED _AIHR-ACTION?
    _AIHR-RESULT ATID-RESULT-READY? 0= _AIHR-ASSERT
    _AIHR-CLEAN
    _AIHR-STACK ;

: _AIHR-TEST-REQUEST-BINDING  ( -- )
    _AIHR-RESET
    S" did:plc:abcdefghijklmnopqrstuvwx"
        _AIHR-RESULT _AIHR-RESOLVER
        ATID-BEGIN-DID ATID-S-OK = _AIHR-ASSERT
    _AIHR-BUILD-DIDDOC
    _hrc-fixture-reset
    0 200 _AIHR-DOC _AIHR-DOC-U @ _AIHR-BUILD-FINAL
    S" https://wrong.example.com/document" _AIHR-SETUP
    _hrc-spec ATID-HRES-SPEC-POLICY!
        HRES-S-STATE = _AIHR-ASSERT
    _hrc-spec HRES-SPEC-VALID? _AIHR-ASSERT
    _AIHR-RUN-RESOURCE
    _hrc-resource HRES-RESULT-VALID? _AIHR-ASSERT
    _hrc-resource _AIHR-RESOLVER ATID-HRES-RESPONSE!
        ATID-S-HTTP = _AIHR-ASSERT
    ATID-A-DID-DOCUMENT _AIHR-ACTION?
    _AIHR-RESULT ATID-RESULT-READY? 0= _AIHR-ASSERT
    _AIHR-CLEAN
    _AIHR-STACK ;

: _AIHR-RUN  ( -- )
    0 _AIHR-FAILS !
    0 _AIHR-CHECKS !
    0 _hrc-fails !
    DEPTH _AIHR-DEPTH !
    _AIHR-TEST-PARTICIPATION
    _AIHR-TEST-NONDEFAULT-PORT
    _AIHR-TEST-REQUEST-BINDING
    _hrc-fails @ 0= _AIHR-ASSERT
    _AIHR-STACK
    _AIHR-FAILS @ IF
        ." AT IDENTITY HRES FAIL " _AIHR-FAILS @ .
        ." / " _AIHR-CHECKS @ . CR
    ELSE
        ." AT IDENTITY HRES PASS " _AIHR-CHECKS @ . CR
    THEN ;
