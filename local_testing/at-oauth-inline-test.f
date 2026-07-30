\ Focused contracts for confidential inline AT OAuth key composition.
\ The exact deployment binder and checked JWK selector are loaded separately;
\ the local owner/vault seam exercises only their already-qualified public ABI.

PROVIDED at-oauth-inline-test

VARIABLE _atoit-checks
VARIABLE _atoit-fails
VARIABLE _atoit-depth
VARIABLE _atoit-expected-status
VARIABLE _atoit-expected-result
VARIABLE _atoit-callback-count

CREATE _atoit-work-storage
    AT-OAUTH-INLINE-WORKSPACE-SIZE 15 + ALLOT
CREATE _atoit-vault-storage
    CVAULT-SIZE 15 + ALLOT
CREATE _atoit-dpop-public
    OAUTH2-P256-KEY-PUBLIC-SIZE ALLOT
CREATE _atoit-dpop-thumb
    OAUTH2-P256-KEY-THUMBPRINT-SIZE ALLOT

: _atoit-work  ( -- workspace )
    _atoit-work-storage 7 + -8 AND ;

: _atoit-vault  ( -- vault )
    _atoit-vault-storage 7 + -8 AND ;

0x41544F4943545854 CONSTANT _ATOIT-CONTEXT
0x41544F4952455354 CONSTANT _ATOIT-RESULT

CREATE _atoit-client-public
0x04 C, 0x60 C, 0xFE C, 0xD4 C, 0xBA C, 0x25 C, 0x5A C, 0x9D C,
0x31 C, 0xC9 C, 0x61 C, 0xEB C, 0x74 C, 0xC6 C, 0x35 C, 0x6D C,
0x68 C, 0xC0 C, 0x49 C, 0xB8 C, 0x92 C, 0x3B C, 0x61 C, 0xFA C,
0x6C C, 0xE6 C, 0x69 C, 0x62 C, 0x2E C, 0x60 C, 0xF2 C, 0x9F C,
0xB6 C, 0x79 C, 0x03 C, 0xFE C, 0x10 C, 0x08 C, 0xB8 C, 0xBC C,
0x99 C, 0xA4 C, 0x1A C, 0xE9 C, 0xE9 C, 0x56 C, 0x28 C, 0xBC C,
0x64 C, 0xF2 C, 0xF1 C, 0xB2 C, 0x0C C, 0x2D C, 0x7E C, 0x9F C,
0x51 C, 0x77 C, 0xA3 C, 0xC2 C, 0x94 C, 0xD4 C, 0x46 C, 0x22 C,
0x99 C,

CREATE _atoit-client-thumb
0x0C C, 0xEB C, 0xF1 C, 0xBC C, 0x98 C, 0x80 C, 0x74 C, 0x8A C,
0x95 C, 0x58 C, 0x89 C, 0x05 C, 0xB7 C, 0x98 C, 0x43 C, 0xB4 C,
0x2B C, 0xA7 C, 0x5C C, 0xB1 C, 0x74 C, 0x05 C, 0x5E C, 0x3E C,
0x24 C, 0x6B C, 0xF8 C, 0x7F C, 0xE0 C, 0x0B C, 0x4A C, 0x6D C,

: _atoit-assert  ( flag -- )
    1 _atoit-checks +!
    0= IF
        1 _atoit-fails +!
        ." AT OAUTH INLINE ASSERT " _atoit-checks @ . CR
        TX-FLUSH
    THEN ;

: _atoit-status  ( actual expected -- )
    2DUP <> IF
        ." AT OAUTH INLINE STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _atoit-assert ;

: _atoit-stack  ( -- )
    DEPTH DUP _atoit-depth @ <> IF
        ." AT OAUTH INLINE STACK "
        _atoit-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _atoit-depth @ = _atoit-assert ;

: _atoit-drop9  ( nine-values -- )
    2DROP 2DROP 2DROP 2DROP DROP ;

: _atoit-work-fill  ( -- )
    _atoit-work AT-OAUTH-INLINE-WORKSPACE-SIZE 8 +
    0xA5 FILL ;

: _atoit-work-filled?  ( -- flag )
    _atoit-work AT-OAUTH-INLINE-WORKSPACE-SIZE 8 +
    0xA5 _atodt-byte? ;

: _ATOIT-WORK-WIPED?  ( -- flag )
    _atoit-work AT-OAUTH-INLINE-WORKSPACE-SIZE
    _atodt-zero?
    _atoit-work AT-OAUTH-INLINE-WORKSPACE-SIZE +
    8 0xA5 _atodt-byte? AND ;

: _ATOIT-INPUTS-UNCHANGED?  ( -- flag )
    _atodt-inputs-unchanged? ;

\ =====================================================================
\ Exact checked client JWK document and opaque binding setup
\ =====================================================================

: _atoit-json-inline-jwks  ( -- )
    _atodt-comma
    S" jwks" _atodt-key
    _atodt-document _atodt-document-u @ +
    _atodt-inline-jwks-a !
    _atodt-lbrace
    S" keys" _atodt-key _atodt-lbracket
    _atodt-lbrace
    S" kid" S" client-1" _atodt-member-string
    _atodt-comma
    S" kty" S" EC" _atodt-member-string
    _atodt-comma
    S" crv" S" P-256" _atodt-member-string
    _atodt-comma
    S" x"
    S" YP7UuiVanTHJYet0xjVtaMBJuJI7Yfps5mliLmDyn7Y"
    _atodt-member-string
    _atodt-comma
    S" y"
    S" eQP-EAi4vJmkGunpVii8ZPLxsgwtfp9Rd6PClNRGIpk"
    _atodt-member-string
    _atodt-rbrace
    _atodt-rbracket
    _atodt-rbrace
    _atodt-document _atodt-document-u @ +
    _atodt-inline-jwks-a @ -
    _atodt-inline-jwks-u ! ;

: _atoit-document-build  ( -- )
    _atodt-document-reset
    _atodt-lbrace
    S" client_id"
    _atodt-metadata-client-a @
    _atodt-metadata-client-u @
    _atodt-member-string
    _atodt-json-application
    _atodt-json-grants
    _atodt-json-responses
    _atodt-json-redirects
    _atodt-json-scope
    _atodt-json-method
    _atodt-json-algorithm
    _atodt-json-dpop
    _atoit-json-inline-jwks
    _atodt-rbrace ;

: _atoit-binding-shape!  ( -- )
    _atodt-config _O2CC.BINDING
    OAUTH2-P256-KEY-BINDING-SIZE 0 FILL
    OAUTH2-P256-KEY-BINDING-SIZE
    _atodt-config _O2CC.BINDING-U ! ;

: _atoit-seam-defaults  ( -- )
    _atoit-vault _ATOID-VAULT-A !
    CVAULT-SIZE _ATOID-VAULT-U !
    S" client-1"
    _ATOID-CLIENT-KID-U !
    _ATOID-CLIENT-KID-A !
    _atoit-client-public _ATOID-CLIENT-PUBLIC !
    _atoit-client-thumb _ATOID-CLIENT-THUMB !
    _atoit-dpop-public
    OAUTH2-P256-KEY-PUBLIC-SIZE 0x6D FILL
    0x04 _atoit-dpop-public C!
    _atoit-dpop-thumb
    OAUTH2-P256-KEY-THUMBPRINT-SIZE 0x7E FILL
    _atoit-dpop-public _ATOID-DPOP-PUBLIC !
    _atoit-dpop-thumb _ATOID-DPOP-THUMB !
    _atodt-inline-jwks-a @ _ATOID-EXPECT-JWKS-A !
    _atodt-inline-jwks-u @ _ATOID-EXPECT-JWKS-U ! ;

: _atoit-baseline  ( -- )
    _atodt-web-confidential-defaults
    _atodt-config-build
    _atoit-binding-shape!
    _atoit-document-build
    _ATOID-RESET
    _atoit-seam-defaults ;

: _atoit-public  ( -- )
    _atodt-native-public-defaults
    _atodt-config-build
    _atoit-binding-shape!
    _atodt-document-build
    _ATOID-RESET
    _atoit-seam-defaults ;

: _atoit-remote  ( -- )
    _atodt-web-confidential-defaults
    2 _atodt-key-mode !
    _atodt-config-build
    _atoit-binding-shape!
    _atodt-document-build
    _ATOID-RESET
    _atoit-seam-defaults ;

\ =====================================================================
\ Final callback ABI and call helpers
\ =====================================================================

VARIABLE _atoit-cb-config
VARIABLE _atoit-cb-metadata
VARIABLE _atoit-cb-kid-a
VARIABLE _atoit-cb-kid-u
VARIABLE _atoit-cb-client-public
VARIABLE _atoit-cb-client-thumb
VARIABLE _atoit-cb-dpop-public
VARIABLE _atoit-cb-dpop-thumb
VARIABLE _atoit-cb-context

: _atoit-application-callback  ( config-view metadata-view kid-a kid-u client-public client-thumb dpop-public dpop-thumb context -- callback-result )
    1 _atoit-callback-count +!
    _atoit-cb-context !
    _atoit-cb-dpop-thumb !
    _atoit-cb-dpop-public !
    _atoit-cb-client-thumb !
    _atoit-cb-client-public !
    _atoit-cb-kid-u !
    _atoit-cb-kid-a !
    _atoit-cb-metadata !
    _atoit-cb-config !

    _atoit-cb-context @ _ATOIT-CONTEXT = _atoit-assert
    _atoit-cb-config @ _atodt-config = _atoit-assert
    _atoit-cb-config @ OAUTH2-CLIENT-VIEW-AUTH-METHOD@
    S" private_key_jwt" COMPARE 0= _atoit-assert
    _atoit-cb-metadata @
    OAUTH2-CLIENT-METADATA-VIEW-PRESENCE@
    OAUTH2-CLIENT-METADATA-S-OK _atoit-status
    OAUTH2-CLIENT-METADATA-P-JWKS AND 0<> _atoit-assert

    _atoit-cb-kid-a @ _atoit-cb-kid-u @
    S" client-1" COMPARE 0= _atoit-assert
    _atoit-cb-client-public @ OAUTH2-P256-KEY-PUBLIC-SIZE
    _atoit-client-public OAUTH2-P256-KEY-PUBLIC-SIZE
    COMPARE 0= _atoit-assert
    _atoit-cb-client-thumb @ OAUTH2-P256-KEY-THUMBPRINT-SIZE
    _atoit-client-thumb OAUTH2-P256-KEY-THUMBPRINT-SIZE
    COMPARE 0= _atoit-assert
    _atoit-cb-dpop-public @ OAUTH2-P256-KEY-PUBLIC-SIZE
    _atoit-dpop-public OAUTH2-P256-KEY-PUBLIC-SIZE
    COMPARE 0= _atoit-assert
    _atoit-cb-dpop-thumb @ OAUTH2-P256-KEY-THUMBPRINT-SIZE
    _atoit-dpop-thumb OAUTH2-P256-KEY-THUMBPRINT-SIZE
    COMPARE 0= _atoit-assert

    _ATOID-VAULT-BUSY @ 0= _atoit-assert
    _ATOID-OWNER-DEPTH @ 0= _atoit-assert
    _ATOID-SELECT-ACTIVE @ 0= _atoit-assert
    _ATOID-DEPLOY-ACTIVE @ 0<> _atoit-assert
    _ATOID-SEQUENCE @ 3 = _atoit-assert
    _ATOIT-RESULT ;

: _atoit-callback-never  ( nine-values -- callback-result )
    1 _atoit-callback-count +!
    _atoit-drop9
    0 _atoit-assert
    0 ;

: _atoit-callback-throw  ( nine-values -- callback-result )
    1 _atoit-callback-count +!
    _atoit-drop9
    -19841 THROW ;

: _atoit-callback-extra  ( nine-values -- result extra )
    1 _atoit-callback-count +!
    _atoit-drop9
    301 302 ;

: _atoit-callback-missing  ( nine-values -- )
    1 _atoit-callback-count +!
    _atoit-drop9 ;

: _atoit-callback-overconsume  ( guard nine-values -- result extra )
    1 _atoit-callback-count +!
    _atoit-drop9
    DROP
    401 402 ;

: _atoit-call  ( callback context -- callback-result status )
    >R >R
    _atodt-document _atodt-document-u @
    _atodt-config _atopt-profile
    _atoit-vault
    R> R>
    _atoit-work
    AT-OAUTH-INLINE-WITH ;

: _atoit-expect  ( callback expected-result expected-status -- )
    _atoit-expected-status !
    _atoit-expected-result !
    0 _atoit-callback-count !
    _atodt-snapshot
    _atoit-work-fill
    _ATOIT-CONTEXT _atoit-call
    _atoit-expected-status @ _atoit-status
    _atoit-expected-result @ _atoit-status
    _ATOIT-INPUTS-UNCHANGED? _atoit-assert
    _ATOIT-WORK-WIPED? _atoit-assert
    _atoit-stack ;

\ =====================================================================
\ Staged contract groups
\ =====================================================================

: _ATOIT-TEST-CONTRACTS  ( -- )
    AT-OAUTH-INLINE-WORKSPACE-SIZE 111928 = _atoit-assert
    AT-OAUTH-INLINE-S-OK 0 = _atoit-assert
    AT-OAUTH-INLINE-S-BINDING 17 = _atoit-assert
    AT-OAUTH-INLINE-S-CALLBACK 37 = _atoit-assert
    AT-OAUTH-INLINE-S-PLATFORM 41 = _atoit-assert
    AT-OAUTH-INLINE-S-OK
    AT-OAUTH-INLINE-STATUS-VALID? _atoit-assert
    AT-OAUTH-INLINE-S-PLATFORM
    AT-OAUTH-INLINE-STATUS-VALID? _atoit-assert
    -1 AT-OAUTH-INLINE-STATUS-VALID? 0= _atoit-assert
    42 AT-OAUTH-INLINE-STATUS-VALID? 0= _atoit-assert

    _atoit-work-fill
    _atoit-work AT-OAUTH-INLINE-WORKSPACE-CLEAR
    AT-OAUTH-INLINE-S-OK _atoit-status
    _ATOIT-WORK-WIPED? _atoit-assert

    _atoit-work-fill
    _atoit-work 1+ AT-OAUTH-INLINE-WORKSPACE-CLEAR
    AT-OAUTH-INLINE-S-INVALID _atoit-status
    _atoit-work-filled? _atoit-assert
    _atoit-stack ;

: _ATOIT-TEST-SUCCESS  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    ['] _atoit-application-callback
    _ATOIT-RESULT AT-OAUTH-INLINE-S-OK
    _atoit-expect
    _atoit-callback-count @ 1 = _atoit-assert
    _ATOID-DEPLOY-CALLS @ 1 = _atoit-assert
    _ATOID-SELECT-CALLS @ 1 = _atoit-assert
    _ATOID-CLIENT-CALLS @ 1 = _atoit-assert
    _ATOID-DPOP-CALLS @ 1 = _atoit-assert
    _ATOID-OWNER-MAX-DEPTH @ 1 = _atoit-assert
    _ATOID-SEQUENCE @ 3 = _atoit-assert
    _ATOID-VIOLATIONS @ 0= _atoit-assert
    _ATOID-SELECT-CLEAN @ _atoit-assert
    _ATOID-WHOLE-SEEN @ _atoit-assert
    _ATOID-EXTERNAL-CALLS @ 7 = _atoit-assert
    _atoit-stack ;

: _ATOIT-TEST-KEY-SOURCE  ( -- )
    _atopt-profile-ready
    _atoit-public
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-KEY-SOURCE
    _atoit-expect
    _atoit-callback-count @ 0= _atoit-assert
    _ATOID-CLIENT-CALLS @ 0= _atoit-assert

    _atoit-remote
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-KEY-SOURCE
    _atoit-expect
    _atoit-callback-count @ 0= _atoit-assert
    _ATOID-SELECT-CALLS @ 0= _atoit-assert
    _atoit-stack ;

: _ATOIT-TEST-BINDING  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    OAUTH2-P256-KEY-BINDING-F-CLIENT
    _ATOID-BINDING-FLAGS !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-BINDING
    _atoit-expect

    _atoit-baseline
    OAUTH2-P256-KEY-S-INVALID
    _ATOID-BINDING-STATUS !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-BINDING
    _atoit-expect

    _atoit-baseline
    OAUTH2-P256-KEY-BINDING-SIZE 1-
    _atodt-config _O2CC.BINDING-U !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-BINDING
    _atoit-expect
    _atoit-stack ;

: _ATOIT-TEST-MISMATCH  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    1 _ATOID-SELECT-MUTATION !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-MISMATCH
    _atoit-expect
    _ATOID-DPOP-CALLS @ 0= _atoit-assert

    _atoit-baseline
    2 _ATOID-SELECT-MUTATION !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-MISMATCH
    _atoit-expect

    _atoit-baseline
    S" absent"
    _ATOID-CLIENT-KID-U !
    _ATOID-CLIENT-KID-A !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-NOT-FOUND
    _atoit-expect
    _atoit-stack ;

: _ATOIT-TEST-OWNER  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    OAUTH2-P256-KEY-S-ABSENT _ATOID-CLIENT-STATUS !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-ABSENT
    _atoit-expect
    _ATOID-SELECT-CALLS @ 0= _atoit-assert
    _ATOID-DPOP-CALLS @ 0= _atoit-assert

    _atoit-baseline
    OAUTH2-P256-KEY-S-REVOKED _ATOID-DPOP-STATUS !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-REVOKED
    _atoit-expect
    _ATOID-SELECT-CALLS @ 1 = _atoit-assert
    _ATOID-DPOP-CALLS @ 1 = _atoit-assert
    _ATOID-OWNER-MAX-DEPTH @ 1 = _atoit-assert
    _ATOID-VIOLATIONS @ 0= _atoit-assert
    _atoit-stack ;

: _ATOIT-TEST-DISTINCT  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    _atoit-client-public _ATOID-DPOP-PUBLIC !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-DISTINCT
    _atoit-expect

    _atoit-baseline
    _atoit-client-thumb _ATOID-DPOP-THUMB !
    ['] _atoit-callback-never
    0 AT-OAUTH-INLINE-S-DISTINCT
    _atoit-expect
    _atoit-stack ;

: _ATOIT-TEST-CALLBACKS  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    ['] _atoit-callback-throw
    0 AT-OAUTH-INLINE-S-CALLBACK
    _atoit-expect
    _atoit-callback-count @ 1 = _atoit-assert

    _atoit-baseline
    ['] _atoit-callback-extra
    0 AT-OAUTH-INLINE-S-CALLBACK
    _atoit-expect

    _atoit-baseline
    ['] _atoit-callback-missing
    0 AT-OAUTH-INLINE-S-CALLBACK
    _atoit-expect

    _atoit-baseline
    ['] _atoit-callback-overconsume
    0 AT-OAUTH-INLINE-S-CALLBACK
    _atoit-expect
    _atoit-stack ;

: _ATOIT-TEST-PREFLIGHT  ( -- )
    _atopt-profile-ready
    _atoit-baseline
    0 _atoit-callback-count !
    _atodt-snapshot
    _atoit-work-fill
    CVAULT-S-BUSY _ATOID-EXTERNAL-STATUS !
    ['] _atoit-callback-never _ATOIT-CONTEXT _atoit-call
    AT-OAUTH-INLINE-S-BUSY _atoit-status
    0 _atoit-status
    _ATOIT-INPUTS-UNCHANGED? _atoit-assert
    _atoit-work-filled? _atoit-assert
    _ATOID-DEPLOY-CALLS @ 0= _atoit-assert
    _atoit-callback-count @ 0= _atoit-assert

    _atoit-baseline
    _atoit-work-fill
    _atodt-document _atodt-document-u @
    _atodt-config _atopt-profile _atoit-vault
    ['] _atoit-callback-never _ATOIT-CONTEXT
    _atoit-work 1+
    AT-OAUTH-INLINE-WITH
    AT-OAUTH-INLINE-S-INVALID _atoit-status
    0 _atoit-status
    _atoit-work-filled? _atoit-assert
    _ATOID-DEPLOY-CALLS @ 0= _atoit-assert

    _atoit-baseline
    _atoit-work-fill
    _atoit-work 8
    _atodt-config _atopt-profile _atoit-vault
    ['] _atoit-callback-never _ATOIT-CONTEXT
    _atoit-work
    AT-OAUTH-INLINE-WITH
    AT-OAUTH-INLINE-S-ALIAS _atoit-status
    0 _atoit-status
    _atoit-work-filled? _atoit-assert

    _atoit-baseline
    _atoit-work-fill
    _atodt-document _atodt-document-u @
    _atoit-work _atopt-profile _atoit-vault
    ['] _atoit-callback-never _ATOIT-CONTEXT
    _atoit-work
    AT-OAUTH-INLINE-WITH
    AT-OAUTH-INLINE-S-ALIAS _atoit-status
    0 _atoit-status
    _atoit-work-filled? _atoit-assert
    _atoit-stack ;

: _ATOIT-INIT  ( -- )
    _ATODT-INIT
    0 _atoit-checks !
    0 _atoit-fails !
    0 _atoit-callback-count !
    DEPTH _atoit-depth ! ;

: _ATOIT-FINISH  ( -- )
    _atopt-fails @ 0= _atoit-assert
    _atodt-fails @ 0= _atoit-assert
    _atoit-stack
    _atoit-fails @ IF
        ." AT OAUTH INLINE FAIL checks/fails "
        _atoit-checks @ . _atoit-fails @ . CR
    ELSE
        ." AT OAUTH INLINE PASS " _atoit-checks @ . CR
    THEN ;
