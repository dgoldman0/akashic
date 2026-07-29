\ Focused caller-owned AT Protocol OAuth grant contracts.
\
\ The staged runner loads the existing AT OAuth profile fixture first.
\ This fixture exercises only response admission and the synchronous public
\ O2SESSION grant descriptor loan.  It does not install or mutate a session.

PROVIDED at-oauth-grant-test

VARIABLE _atogt-checks
VARIABLE _atogt-fails
VARIABLE _atogt-depth
VARIABLE _atogt-callback-count
VARIABLE _atogt-saved-grant
VARIABLE _atogt-mode
VARIABLE _atogt-base-ms
VARIABLE _atogt-callback
VARIABLE _atogt-context
VARIABLE _atogt-body-copy-u
VARIABLE _atogt-expected-scope-a
VARIABLE _atogt-expected-scope-u

CREATE _atogt-work-storage
    AT-OAUTH-GRANT-WORKSPACE-SIZE 7 + ALLOT
CREATE _atogt-body-copy _ATOPT-BODY-CAPACITY ALLOT
CREATE _atogt-profile-copy AT-OAUTH-PROFILE-SIZE ALLOT

911 CONSTANT _ATOGT-CONTEXT

: _atogt-work  ( -- workspace )
    _atogt-work-storage 7 + -8 AND ;

: _atogt-assert  ( flag -- )
    1 _atogt-checks +!
    0= IF
        1 _atogt-fails +!
        ." AT OAUTH GRANT ASSERT " _atogt-checks @ . CR
    THEN ;

: _atogt-status  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH GRANT STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _atogt-assert ;

: _atogt-stack  ( -- )
    DEPTH DUP _atogt-depth @ <> IF
        ." AT OAUTH GRANT STACK "
        _atogt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _atogt-depth @ = _atogt-assert ;

: _atogt-zero?  ( address length -- flag )
    BEGIN
        DUP
    WHILE
        OVER C@ IF
            2DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _atogt-filled?  ( address length -- flag )
    BEGIN
        DUP
    WHILE
        OVER C@ 0xA5 <> IF
            2DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _atogt-fill-work  ( -- )
    _atogt-work AT-OAUTH-GRANT-WORKSPACE-SIZE 0xA5 FILL ;

: _atogt-work-zero?  ( -- flag )
    _atogt-work AT-OAUTH-GRANT-WORKSPACE-SIZE _atogt-zero? ;

: _atogt-work-filled?  ( -- flag )
    _atogt-work AT-OAUTH-GRANT-WORKSPACE-SIZE _atogt-filled? ;

: _atogt-snapshot-inputs  ( -- )
    _atopt-body-u @ DUP _atogt-body-copy-u !
    _atopt-body _atogt-body-copy ROT MOVE
    _atopt-profile _atogt-profile-copy
    AT-OAUTH-PROFILE-SIZE MOVE ;

: _atogt-inputs-unchanged?  ( -- flag )
    _atopt-body-u @ _atogt-body-copy-u @ =
    _atopt-body _atopt-body-u @
    _atogt-body-copy _atogt-body-copy-u @
    COMPARE 0= AND
    _atopt-profile AT-OAUTH-PROFILE-SIZE
    _atogt-profile-copy AT-OAUTH-PROFILE-SIZE
    COMPARE 0= AND ;

\ =====================================================================
\  Strict token-response builders
\ =====================================================================

: _atogt-json-access  ( -- )
    S" access_token" _atopt-key
    S" access-opaque" _atopt-string ;

: _atogt-json-dpop  ( -- )
    S" token_type" _atopt-key
    S" dPoP" _atopt-string ;

: _atogt-json-bearer  ( -- )
    S" token_type" _atopt-key
    S" Bearer" _atopt-string ;

: _atogt-json-dpop-long  ( -- )
    S" token_type" _atopt-key
    S" DPoP-1" _atopt-string ;

: _atogt-json-refresh  ( -- )
    S" refresh_token" _atopt-key
    S" refresh~1" _atopt-string ;

: _atogt-json-scope  ( -- )
    S" scope" _atopt-key
    S" transition:generic atproto" _atopt-string ;

: _atogt-json-wrong-scope  ( -- )
    S" scope" _atopt-key
    S" transition:generic atproto:write" _atopt-string ;

: _atogt-json-prefix-scope  ( -- )
    S" scope" _atopt-key
    S" xatproto transition:generic" _atopt-string ;

: _atogt-json-exact-scope  ( -- )
    S" scope" _atopt-key
    S" atproto" _atopt-string ;

: _atogt-json-middle-scope  ( -- )
    S" scope" _atopt-key
    S" transition:generic atproto repo:write" _atopt-string ;

: _atogt-json-subject  ( -- )
    S" sub" _atopt-key
    S" did:plc:abcdefghijklmnopqrstuvwx" _atopt-string ;

: _atogt-json-escaped-subject  ( -- )
    S" sub" _atopt-key
    S" did\u003Aplc\u003Aabcdefghijklmnopqrstuvwx" _atopt-string ;

: _atogt-json-invalid-subject  ( -- )
    S" sub" _atopt-key
    S" not-a-did" _atopt-string ;

: _atogt-json-other-subject  ( -- )
    S" sub" _atopt-key
    S" did:plc:abcdefghijklmnopqrstuvwy" _atopt-string ;

: _atogt-json-expires-3600  ( -- )
    S" expires_in" _atopt-key S" 3600" _atopt-text ;

: _atogt-json-expires-zero  ( -- )
    S" expires_in" _atopt-key S" 0" _atopt-text ;

: _atogt-json-expires-one  ( -- )
    S" expires_in" _atopt-key S" 1" _atopt-text ;

: _atogt-json-expires-two  ( -- )
    S" expires_in" _atopt-key S" 2" _atopt-text ;

: _atogt-build-full  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-refresh _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-expires-3600 _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-minimal  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-wrong-type  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-bearer _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-long-type  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop-long _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-missing-scope  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-wrong-scope  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-wrong-scope _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-prefix-scope  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-prefix-scope _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-exact-scope  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-exact-scope _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-middle-scope  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-middle-scope _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-missing-subject  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope
    _atopt-rbrace ;

: _atogt-build-invalid-subject  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-invalid-subject
    _atopt-rbrace ;

: _atogt-build-other-subject  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-other-subject
    _atopt-rbrace ;

: _atogt-build-escaped-subject  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-escaped-subject
    _atopt-rbrace ;

: _atogt-build-duplicate-subject  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-subject _atopt-comma
    S" s\u0075b" _atopt-key
    S" did:plc:abcdefghijklmnopqrstuvwx" _atopt-string
    _atopt-rbrace ;

: _atogt-build-expires-zero  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-expires-zero _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-expires-one  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-expires-one _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-expires-two  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop _atopt-comma
    _atogt-json-scope _atopt-comma
    _atogt-json-expires-two _atopt-comma
    _atogt-json-subject
    _atopt-rbrace ;

: _atogt-build-malformed  ( -- )
    _atopt-reset-body _atopt-lbrace
    _atogt-json-access _atopt-comma
    _atogt-json-dpop ;

\ =====================================================================
\  Public grant inspection callbacks
\ =====================================================================

: _atogt-check-common  ( grant -- grant )
    DUP O2SESSION-G.ACCESS-A @
    OVER O2SESSION-G.ACCESS-U @
    S" access-opaque" 2SWAP COMPARE 0= _atogt-assert
    DUP O2SESSION-G.TOKEN-TYPE-A @
    OVER O2SESSION-G.TOKEN-TYPE-U @
    S" dPoP" 2SWAP COMPARE 0= _atogt-assert
    DUP O2SESSION-G.SCOPE-A @
    OVER O2SESSION-G.SCOPE-U @
    S" transition:generic atproto"
    2SWAP COMPARE 0= _atogt-assert
    DUP O2SESSION-G.ID-A @ 0= _atogt-assert
    DUP O2SESSION-G.ID-U @ 0= _atogt-assert ;

: _atogt-callback-scope  ( grant context -- callback-result )
    1 _atogt-callback-count +!
    DROP
    DUP O2SESSION-G.SCOPE-A @
    OVER O2SESSION-G.SCOPE-U @
    _atogt-expected-scope-a @
    _atogt-expected-scope-u @
    2SWAP COMPARE 0= _atogt-assert
    DUP O2SESSION-G.FLAGS @
    O2SESSION-GRANT-F-SCOPE = _atogt-assert
    DUP O2SESSION-G.ID-A @ 0= _atogt-assert
    DUP O2SESSION-G.ID-U @ 0= _atogt-assert
    DROP 955 ;

: _atogt-callback-full  ( grant context -- callback-result )
    1 _atogt-callback-count +!
    _ATOGT-CONTEXT = _atogt-assert
    DUP _atogt-saved-grant !
    _atogt-check-common
    DUP O2SESSION-G.REFRESH-A @
    OVER O2SESSION-G.REFRESH-U @
    S" refresh~1" 2SWAP COMPARE 0= _atogt-assert
    DUP O2SESSION-G.FLAGS @
    O2SESSION-GRANT-F-REFRESH
    O2SESSION-GRANT-F-SCOPE OR
    O2SESSION-GRANT-F-EXPIRY OR
    = _atogt-assert
    DUP O2SESSION-G.EXPIRES-AT-MS @
    3723000 = _atogt-assert
    DROP 911 ;

: _atogt-callback-minimal  ( grant context -- callback-result )
    1 _atogt-callback-count +!
    DROP
    DUP _atogt-saved-grant !
    _atogt-check-common
    DUP O2SESSION-G.REFRESH-A @ 0= _atogt-assert
    DUP O2SESSION-G.REFRESH-U @ 0= _atogt-assert
    DUP O2SESSION-G.FLAGS @
    O2SESSION-GRANT-F-SCOPE = _atogt-assert
    DUP O2SESSION-G.EXPIRES-AT-MS @ 0= _atogt-assert
    DROP 922 ;

: _atogt-callback-expiry  ( grant expected-ms -- callback-result )
    1 _atogt-callback-count +!
    >R
    DUP _atogt-saved-grant !
    _atogt-check-common
    DUP O2SESSION-G.FLAGS @
    O2SESSION-GRANT-F-SCOPE
    O2SESSION-GRANT-F-EXPIRY OR
    = _atogt-assert
    DUP O2SESSION-G.EXPIRES-AT-MS @
    R> = _atogt-assert
    DROP 933 ;

: _atogt-callback-never  ( grant context -- callback-result )
    1 _atogt-callback-count +!
    2DROP
    0 _atogt-assert
    0 ;

: _atogt-callback-throw  ( grant context -- callback-result )
    1 _atogt-callback-count +!
    2DROP
    -733 THROW ;

: _atogt-callback-extra  ( grant context -- result extra )
    1 _atogt-callback-count +!
    2DROP
    944 945 ;

\ =====================================================================
\  Call and outcome helpers
\ =====================================================================

: _atogt-call
  ( mode base-ms callback context -- callback-result grant-status )
    _atogt-context !
    _atogt-callback !
    _atogt-base-ms !
    _atogt-mode !
    _atopt-body _atopt-body-u @
    _atogt-mode @ _atogt-base-ms @
    _atopt-profile
    _atogt-callback @ _atogt-context @
    _atogt-work
    AT-OAUTH-GRANT-WITH ;

: _atogt-expect-rejection  ( mode base-ms expected-status -- )
    >R
    0 _atogt-callback-count !
    _atogt-fill-work
    ['] _atogt-callback-never 0 _atogt-call
    R> _atogt-status
    0= _atogt-assert
    _atogt-callback-count @ 0= _atogt-assert
    _atogt-work-zero? _atogt-assert ;

: _atogt-expect-preflight  ( mode base-ms expected-status -- )
    >R
    0 _atogt-callback-count !
    _atogt-fill-work
    ['] _atogt-callback-never 0 _atogt-call
    R> _atogt-status
    0= _atogt-assert
    _atogt-callback-count @ 0= _atogt-assert
    _atogt-work-filled? _atogt-assert ;

: _atogt-expect-admitted-scope  ( expected-a expected-u -- )
    _atogt-expected-scope-u !
    _atogt-expected-scope-a !
    0 _atogt-callback-count !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-INITIAL 0
    ['] _atogt-callback-scope 0 _atogt-call
    AT-OAUTH-GRANT-S-OK _atogt-status
    955 = _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert ;

: _atogt-saved-grant-zero?  ( -- flag )
    _atogt-saved-grant @
    DUP 0= IF DROP 0 EXIT THEN
    O2SESSION-GRANT-SIZE _atogt-zero? ;

\ =====================================================================
\  Contract groups
\ =====================================================================

: _ATOGT-TEST-HAPPY  ( -- )
    _atopt-profile-ready
    _atogt-build-full
    0 _atogt-callback-count !
    0 _atogt-saved-grant !
    _atogt-fill-work
    _atogt-snapshot-inputs
    AT-OAUTH-GRANT-MODE-INITIAL 123000
    ['] _atogt-callback-full _ATOGT-CONTEXT
    _atogt-call
    AT-OAUTH-GRANT-S-OK _atogt-status
    911 = _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert
    _atogt-saved-grant-zero? _atogt-assert
    _atogt-inputs-unchanged? _atogt-assert
    _atopt-profile AT-OAUTH-PROFILE-READY? _atogt-assert
    _atogt-stack ;

: _ATOGT-TEST-POLICY  ( -- )
    _atopt-profile-ready
    _atogt-build-wrong-type
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-TOKEN-TYPE _atogt-expect-rejection

    _atogt-build-long-type
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-TOKEN-TYPE _atogt-expect-rejection

    _atogt-build-missing-scope
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-SCOPE _atogt-expect-rejection

    _atogt-build-prefix-scope
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-SCOPE _atogt-expect-rejection

    _atogt-build-exact-scope
    S" atproto" _atogt-expect-admitted-scope

    _atogt-build-middle-scope
    S" transition:generic atproto repo:write"
    _atogt-expect-admitted-scope

    _atogt-build-wrong-scope
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-SCOPE _atogt-expect-rejection

    _atogt-build-missing-subject
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-SUBJECT _atogt-expect-rejection

    _atogt-build-invalid-subject
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-SUBJECT _atogt-expect-rejection

    _atogt-build-other-subject
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-SUBJECT-BINDING _atogt-expect-rejection

    _atogt-build-escaped-subject
    0 _atogt-callback-count !
    0 _atogt-saved-grant !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-INITIAL 0
    ['] _atogt-callback-minimal 0 _atogt-call
    AT-OAUTH-GRANT-S-OK _atogt-status
    922 = _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert
    _atogt-saved-grant-zero? _atogt-assert
    _atogt-stack ;

: _ATOGT-TEST-REFRESH  ( -- )
    _atopt-profile-ready
    _atogt-build-full
    0 _atogt-callback-count !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-REFRESH 123000
    ['] _atogt-callback-full _ATOGT-CONTEXT
    _atogt-call
    AT-OAUTH-GRANT-S-OK _atogt-status
    911 = _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert

    _atogt-build-minimal
    AT-OAUTH-GRANT-MODE-REFRESH 0
    AT-OAUTH-GRANT-S-REFRESH _atogt-expect-rejection

    _atogt-build-minimal
    0 _atogt-callback-count !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-INITIAL 0
    ['] _atogt-callback-minimal 0 _atogt-call
    AT-OAUTH-GRANT-S-OK _atogt-status
    922 = _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert
    _atogt-stack ;

: _ATOGT-TEST-EXPIRY  ( -- )
    _atopt-profile-ready
    _atogt-build-expires-zero
    0 _atogt-callback-count !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-INITIAL 555
    ['] _atogt-callback-expiry 555 _atogt-call
    AT-OAUTH-GRANT-S-OK _atogt-status
    933 = _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert

    _atogt-build-expires-two
    0 _atogt-callback-count !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-INITIAL 1000
    ['] _atogt-callback-expiry 3000 _atogt-call
    AT-OAUTH-GRANT-S-OK _atogt-status
    933 = _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert

    _atogt-build-expires-one
    AT-OAUTH-GRANT-MODE-INITIAL
    -1 1 RSHIFT
    AT-OAUTH-GRANT-S-OVERFLOW _atogt-expect-rejection

    _atogt-build-minimal
    AT-OAUTH-GRANT-MODE-INITIAL -1
    AT-OAUTH-GRANT-S-TIME _atogt-expect-preflight
    _atogt-stack ;

: _ATOGT-TEST-CALLBACKS  ( -- )
    _atopt-profile-ready
    _atogt-build-malformed
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-RESPONSE _atogt-expect-rejection

    _atogt-build-duplicate-subject
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-RESPONSE _atogt-expect-rejection

    _atogt-build-full
    0 _atogt-callback-count !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-INITIAL 0
    ['] _atogt-callback-throw 0 _atogt-call
    AT-OAUTH-GRANT-S-CALLBACK _atogt-status
    0= _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert

    _atogt-build-full
    0 _atogt-callback-count !
    _atogt-fill-work
    AT-OAUTH-GRANT-MODE-INITIAL 0
    ['] _atogt-callback-extra 0 _atogt-call
    AT-OAUTH-GRANT-S-CALLBACK _atogt-status
    0= _atogt-assert
    _atogt-callback-count @ 1 = _atogt-assert
    _atogt-work-zero? _atogt-assert
    _atogt-stack ;

: _ATOGT-TEST-GEOMETRY  ( -- )
    AT-OAUTH-GRANT-S-OK
    AT-OAUTH-GRANT-STATUS-VALID? _atogt-assert
    AT-OAUTH-GRANT-S-PLATFORM
    AT-OAUTH-GRANT-STATUS-VALID? _atogt-assert
    -1 AT-OAUTH-GRANT-STATUS-VALID? 0= _atogt-assert
    AT-OAUTH-GRANT-S-PLATFORM 1+
    AT-OAUTH-GRANT-STATUS-VALID? 0= _atogt-assert
    AT-OAUTH-GRANT-MODE-INITIAL
    AT-OAUTH-GRANT-MODE-VALID? _atogt-assert
    AT-OAUTH-GRANT-MODE-REFRESH
    AT-OAUTH-GRANT-MODE-VALID? _atogt-assert
    AT-OAUTH-GRANT-MODE-REFRESH 1+
    AT-OAUTH-GRANT-MODE-VALID? 0= _atogt-assert

    _atogt-fill-work
    _atogt-work AT-OAUTH-GRANT-WORKSPACE-CLEAR
    AT-OAUTH-GRANT-S-OK _atogt-status
    _atogt-work-zero? _atogt-assert
    _atogt-fill-work
    _atogt-work 1+ AT-OAUTH-GRANT-WORKSPACE-CLEAR
    AT-OAUTH-GRANT-S-INVALID _atogt-status
    _atogt-work-filled? _atogt-assert

    _atopt-profile AT-OAUTH-PROFILE-INIT
    AT-OAUTH-PROFILE-S-OK _atopt-status
    _atogt-build-minimal
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-PROFILE _atogt-expect-preflight

    _atopt-profile-ready
    _atogt-build-minimal
    AT-OAUTH-GRANT-MODE-REFRESH 1+
    0 AT-OAUTH-GRANT-S-INVALID _atogt-expect-preflight

    _atogt-fill-work
    _atopt-body _atopt-body-u @
    AT-OAUTH-GRANT-MODE-INITIAL 0
    _atopt-profile 0 0 _atogt-work
    AT-OAUTH-GRANT-WITH
    AT-OAUTH-GRANT-S-INVALID _atogt-status
    0= _atogt-assert
    _atogt-work-filled? _atogt-assert

    _atopt-profile AT-OAUTH-PROFILE-SIZE 1- +
    DUP C@ 1 XOR SWAP C!
    _atogt-build-minimal
    AT-OAUTH-GRANT-MODE-INITIAL 0
    AT-OAUTH-GRANT-S-PROFILE _atogt-expect-preflight

    _atopt-profile-ready
    _atogt-build-minimal
    _atogt-fill-work
    _atopt-body _atopt-body-u @
    AT-OAUTH-GRANT-MODE-INITIAL 0
    _atopt-profile 1+ ['] _atogt-callback-never 0 _atogt-work
    AT-OAUTH-GRANT-WITH
    AT-OAUTH-GRANT-S-INVALID _atogt-status
    0= _atogt-assert
    _atogt-work-filled? _atogt-assert

    _atogt-fill-work
    _atopt-body _atopt-body-u @
    AT-OAUTH-GRANT-MODE-INITIAL 0
    _atogt-work ['] _atogt-callback-never 0 _atogt-work
    AT-OAUTH-GRANT-WITH
    AT-OAUTH-GRANT-S-ALIAS _atogt-status
    0= _atogt-assert
    _atogt-work-filled? _atogt-assert

    _atogt-fill-work
    _atogt-work 2
    AT-OAUTH-GRANT-MODE-INITIAL 0
    _atopt-profile ['] _atogt-callback-never 0 _atogt-work
    AT-OAUTH-GRANT-WITH
    AT-OAUTH-GRANT-S-ALIAS _atogt-status
    0= _atogt-assert
    _atogt-work-filled? _atogt-assert

    _atogt-fill-work
    _atopt-profile 1
    AT-OAUTH-GRANT-MODE-INITIAL 0
    _atopt-profile ['] _atogt-callback-never 0 _atogt-work
    AT-OAUTH-GRANT-WITH
    AT-OAUTH-GRANT-S-ALIAS _atogt-status
    0= _atogt-assert
    _atogt-work-filled? _atogt-assert

    _atogt-fill-work
    _atopt-body _atopt-body-u @
    AT-OAUTH-GRANT-MODE-INITIAL 0
    _atopt-profile ['] _atogt-callback-never 0
    _atogt-work 1+
    AT-OAUTH-GRANT-WITH
    AT-OAUTH-GRANT-S-INVALID _atogt-status
    0= _atogt-assert
    _atogt-work-filled? _atogt-assert
    _atogt-stack ;

: _ATOGT-INIT  ( -- )
    _ATOPT-INIT
    _atopt-build-identity
    0 _atogt-checks !
    0 _atogt-fails !
    0 _atogt-callback-count !
    0 _atogt-saved-grant !
    DEPTH _atogt-depth ! ;

: _ATOGT-FINISH  ( -- )
    _atopt-fails @ 0= _atogt-assert
    _atogt-stack
    _atogt-fails @ IF
        ." AT OAUTH GRANT FAIL checks/fails "
        _atogt-checks @ . _atogt-fails @ . CR
    ELSE
        ." AT OAUTH GRANT PASS " _atogt-checks @ . CR
    THEN ;
