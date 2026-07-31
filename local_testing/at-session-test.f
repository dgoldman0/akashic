\ Focused AT grant-to-durable-session continuation.
\
\ The token fixture has already built the retry DPoP proof and sealed request.
\ The deterministic credential-vault seam stores only one record, so this
\ fixture releases the now-unused key vault before obtaining and installing
\ the accepted grant into an exact production session/vault pair.
\ It then reconstructs distinct vault and session objects and uses ordinary
\ O2SESSION-OPEN.  Simultaneous key/session persistence is deliberately not
\ claimed by this fixture-only seam.

REQUIRE at-token-p256-test.f

PROVIDED at-session-install-test

0x4154534952535631 CONSTANT _ATSI-RESOLVER-TOKEN
0x415453494C4F414E CONSTANT _ATSI-LOAN-TOKEN

VARIABLE _atsi-vault-config
VARIABLE _atsi-vault-a
VARIABLE _atsi-vault-b
VARIABLE _atsi-backing-a
VARIABLE _atsi-backing-b
VARIABLE _atsi-session-a
VARIABLE _atsi-session-b

VARIABLE _atsi-generation
VARIABLE _atsi-install-status
VARIABLE _atsi-resolver-calls
VARIABLE _atsi-resolver-before
VARIABLE _atsi-install-calls
VARIABLE _atsi-expected-a
VARIABLE _atsi-expected-u

VARIABLE _atsi-r-key-a
VARIABLE _atsi-r-key-u
VARIABLE _atsi-r-consumer-xt
VARIABLE _atsi-r-consumer-context
VARIABLE _atsi-r-resolver-context

CREATE _atsi-session-config O2SESSION-CONFIG-SIZE ALLOT
CREATE _atsi-vault-id RID-SIZE ALLOT
CREATE _atsi-key-id RID-SIZE ALLOT
CREATE _atsi-session-rid RID-SIZE ALLOT
CREATE _atsi-root-key SEALED-RECORD-ROOT-KEY-SIZE ALLOT

O2SESSION-RECORD-SIZE CVAULT-BACKING-SIZE
    CONSTANT _ATSI-BACKING-U

\ =====================================================================
\  Allocation and exact root-key resolver
\ =====================================================================

: _atsi-allocate  ( size variable -- )
    >R
    ALLOCATE ABORT" AT SESSION INSTALL allocation"
    R> ! ;

: _atsi-free  ( variable -- )
    DUP @ ?DUP IF
        FREE
        0 SWAP !
    ELSE
        DROP
    THEN ;

: _atsi-resolver
  \ ( key-id key-id-u consumer-xt consumer-context resolver-context
  \   -- status )
    _atsi-r-resolver-context !
    _atsi-r-consumer-context !
    _atsi-r-consumer-xt !
    _atsi-r-key-u !
    _atsi-r-key-a !
    _atsi-r-resolver-context @
        _ATSI-RESOLVER-TOKEN = _attt-assert
    _atsi-r-key-u @ RID-SIZE = _attt-assert
    _atsi-r-key-a @ _atsi-r-key-u @
        _atsi-key-id RID-SIZE COMPARE 0= _attt-assert
    1 _atsi-resolver-calls +!
    _atsi-root-key SEALED-RECORD-ROOT-KEY-SIZE
    _atsi-r-consumer-context @
    _atsi-r-consumer-xt @ EXECUTE ;

\ =====================================================================
\  Exact session vault and AT-bound generic session setup
\ =====================================================================

: _atsi-configure-vault  ( backing vault -- )
    >R
    _atsi-vault-config @ CVAULT-CONFIG-CLEAR
    CVAULT-S-OK _attt-status
    \ The one-record deterministic VFS seam admits only this exact root.
    S" /vault"
        _atsi-vault-config @ CVAULT-C.ROOT-U !
        _atsi-vault-config @ CVAULT-C.ROOT !
    O2SESSION-RECORD-SIZE
        _atsi-vault-config @ CVAULT-C.SECRET-CAPACITY !
    _atsi-vault-config @ CVAULT-C.BACKING !
    _ATSI-BACKING-U
        _atsi-vault-config @ CVAULT-C.BACKING-U !
    _O2PKT-VFS
        _atsi-vault-config @ CVAULT-C.VFS !
    _atsi-vault-id
        _atsi-vault-config @ CVAULT-C.VAULT-ID !
    _atsi-key-id
        _atsi-vault-config @ CVAULT-C.KEY-ID !
    ['] _atsi-resolver
        _atsi-vault-config @ CVAULT-C.RESOLVER-XT !
    _ATSI-RESOLVER-TOKEN
        _atsi-vault-config @ CVAULT-C.RESOLVER-CONTEXT !
    _atsi-vault-config @ R@ CVAULT-INIT
    CVAULT-S-OK _attt-status
    R@ CVAULT-VALID? _attt-assert
    R> CVAULT-SECRET-CAPACITY@
    CVAULT-S-OK _attt-status
    O2SESSION-RECORD-SIZE = _attt-assert ;

: _atsi-configure-session  ( vault session -- )
    >R
    _atsi-session-config O2SESSION-CONFIG-CLEAR
    O2SESSION-S-OK _attt-status
    _atsi-session-config O2SESSION-C.VAULT !
    _atsi-session-rid
        _atsi-session-config O2SESSION-C.RID !

    _atoct-config OAUTH2-CLIENT-CONFIG-BINDING@
    OAUTH2-CLIENT-CONFIG-S-OK _attt-status
    _atsi-session-config O2SESSION-C.BINDING-U !
    _atsi-session-config O2SESSION-C.BINDING-A !

    _atopt-profile AT-OAUTH-PROFILE-ISSUER@
    AT-OAUTH-PROFILE-S-OK _attt-status
    _atsi-session-config O2SESSION-C.ISSUER-U !
    _atsi-session-config O2SESSION-C.ISSUER-A !

    _atsi-session-config R@ O2SESSION-INIT
    O2SESSION-S-OK _attt-status
    R@ O2SESSION-VALID? _attt-assert
    R> DROP
    _atsi-session-config O2SESSION-CONFIG-CLEAR
    O2SESSION-S-OK _attt-status ;

: _atsi-reset-vfs-after-key-proof  ( -- )
    _O2PKT-VAULT @ DUP CVAULT-VALID? _attt-assert
    CVAULT-FINI CVAULT-S-OK _attt-status
    _O2PKT-BACKING @ _O2PKT-BACKING-U
        _atpart-zero? _attt-assert
    0 VFS-USE
    _CVTD-RESET
    _O2PKT-VFS VFS-DESC-SIZE 0 FILL
    _CVTD-ROOT-INODE _O2PKT-VFS V.CWD !
    _O2PKT-VFS VFS-USE ;

: _ATSI-SETUP  ( -- )
    _atsi-vault-config @ 0= IF
        CVAULT-CONFIG-SIZE _atsi-vault-config _atsi-allocate
        CVAULT-SIZE _atsi-vault-a _atsi-allocate
        CVAULT-SIZE _atsi-vault-b _atsi-allocate
        _ATSI-BACKING-U _atsi-backing-a _atsi-allocate
        _ATSI-BACKING-U _atsi-backing-b _atsi-allocate
        OAUTH2-SESSION-SIZE _atsi-session-a _atsi-allocate
        OAUTH2-SESSION-SIZE _atsi-session-b _atsi-allocate
    THEN

    _atsi-vault-config @ CVAULT-CONFIG-SIZE 0 FILL
    _atsi-vault-a @ CVAULT-SIZE 0 FILL
    _atsi-vault-b @ CVAULT-SIZE 0 FILL
    _atsi-backing-a @ _ATSI-BACKING-U 0 FILL
    _atsi-backing-b @ _ATSI-BACKING-U 0 FILL
    _atsi-session-a @ OAUTH2-SESSION-SIZE 0 FILL
    _atsi-session-b @ OAUTH2-SESSION-SIZE 0 FILL
    _atsi-session-config O2SESSION-CONFIG-SIZE 0 FILL

    _atsi-vault-id RID-SIZE 0x51 FILL
    _atsi-key-id RID-SIZE 0x52 FILL
    _atsi-session-rid RID-SIZE 0x53 FILL
    _atsi-root-key SEALED-RECORD-ROOT-KEY-SIZE 0x54 FILL
    0 _atsi-generation !
    0 _atsi-install-status !
    0 _atsi-resolver-calls !
    0 _atsi-resolver-before !
    0 _atsi-install-calls !

    _atsi-reset-vfs-after-key-proof
    _atsi-backing-a @ _atsi-vault-a @ _atsi-configure-vault
    _atsi-vault-a @ _atsi-session-a @ _atsi-configure-session

    _atsi-session-a @ O2SESSION-STATE@
    O2SESSION-S-ABSENT _attt-status
    0= _attt-assert
    0= _attt-assert
    _attt-stack ;

\ =====================================================================
\  Ephemeral grant installation and durable publication checks
\ =====================================================================

: _atsi-install-callback  ( grant session -- callback-result )
    1 _attt-callback-count +!
    1 _atsi-install-calls +!
    OVER _attt-check-grant
    O2SESSION-INSTALL
    _atsi-install-status !
    _atsi-generation !
    _ATTT-GRANT-RESULT ;

: _atsi-expect  ( address length -- )
    _atsi-expected-u !
    _atsi-expected-a ! ;

: _atsi-expect-callback
  ( address length callback-context -- callback-result )
    _ATSI-LOAN-TOKEN = _attt-assert
    _atsi-expected-a @ _atsi-expected-u @
    COMPARE 0= _attt-assert
    _ATSI-LOAN-TOKEN ;

: _atsi-loan-ok  ( callback-result status -- )
    O2SESSION-S-OK _attt-status
    _ATSI-LOAN-TOKEN = _attt-assert ;

: _atsi-check-published  ( session -- )
    >R
    R@ O2SESSION-STATE@
    O2SESSION-S-OK _attt-status
    O2SESSION-PHASE-ACTIVE = _attt-assert
    _atsi-generation @ = _attt-assert

    S" access-vertical" _atsi-expect
    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    R@ O2SESSION-WITH-ACCESS _atsi-loan-ok

    S" dPoP" _atsi-expect
    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    R@ O2SESSION-WITH-TOKEN-TYPE _atsi-loan-ok

    S" atproto" _atsi-expect
    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    R@ O2SESSION-WITH-SCOPE _atsi-loan-ok

    _atsi-session-rid RID-SIZE _atsi-expect
    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    R@ O2SESSION-WITH-RID _atsi-loan-ok

    _atoct-config OAUTH2-CLIENT-CONFIG-BINDING@
    OAUTH2-CLIENT-CONFIG-S-OK _attt-status
    _atsi-expect
    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    R@ O2SESSION-WITH-BINDING _atsi-loan-ok

    _atopt-profile AT-OAUTH-PROFILE-ISSUER@
    AT-OAUTH-PROFILE-S-OK _attt-status
    _atsi-expect
    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    R@ O2SESSION-WITH-ISSUER _atsi-loan-ok

    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    R@ O2SESSION-WITH-ID
    O2SESSION-S-ABSENT _attt-status
    0= _attt-assert

    R@ O2SESSION-EXPIRY@
    O2SESSION-S-OK _attt-status
    0= _attt-assert
    0= _attt-assert

    R@ _O2S.RECORD O2SESSION-RECORD-SIZE
    _atpart-zero? _attt-assert
    R> DROP ;

: _ATSI-SUCCESS-INSTALL  ( -- )
    0 _atsi-install-calls !
    0 _atsi-install-status !
    ['] _atsi-install-callback
    _atsi-session-a @
    _ATTT-SUCCESS-WITH

    _atsi-install-calls @ 1 = _attt-assert
    _atsi-install-status @ O2SESSION-S-OK _attt-status
    _atsi-generation @ 1 = _attt-assert
    _atsi-resolver-calls @ 0> _attt-assert
    _atsi-session-a @ _atsi-check-published
    _attt-stack ;

\ =====================================================================
\  Distinct-owner ordinary reopen
\ =====================================================================

: _ATSI-REOPEN  ( -- )
    _atsi-session-a @ O2SESSION-CLOSE
    O2SESSION-S-OK _attt-status
    ['] _atsi-expect-callback _ATSI-LOAN-TOKEN
    _atsi-session-a @ O2SESSION-WITH-ACCESS
    O2SESSION-S-ABSENT _attt-status
    0= _attt-assert
    _atsi-session-a @ O2SESSION-FINI
    O2SESSION-S-OK _attt-status
    _atsi-session-a @ OAUTH2-SESSION-SIZE
    _atpart-zero? _attt-assert

    _atsi-vault-a @ CVAULT-FINI
    CVAULT-S-OK _attt-status
    _atsi-backing-a @ _ATSI-BACKING-U
    _atpart-zero? _attt-assert

    0 VFS-USE
    _O2PKT-VFS VFS-USE
    _atsi-backing-b @ _atsi-vault-b @ _atsi-configure-vault
    _atsi-vault-b @ _atsi-session-b @ _atsi-configure-session
    _atsi-resolver-calls @ _atsi-resolver-before !
    _atsi-session-b @ O2SESSION-OPEN
    O2SESSION-S-OK _attt-status
    O2SESSION-PHASE-ACTIVE = _attt-assert
    _atsi-generation @ = _attt-assert
    _atsi-resolver-calls @
    _atsi-resolver-before @ > _attt-assert
    _atsi-session-b @ _atsi-check-published
    _attt-stack ;

\ =====================================================================
\  Cleanup and final marker
\ =====================================================================

: _ATSI-FINISH  ( -- )
    _atsi-session-b @ ?DUP IF
        DUP O2SESSION-VALID? IF
            DUP O2SESSION-CLOSE
            O2SESSION-S-OK _attt-status
            O2SESSION-FINI
            O2SESSION-S-OK _attt-status
        ELSE
            DROP
        THEN
    THEN
    _atsi-vault-b @ ?DUP IF
        DUP CVAULT-VALID? IF
            CVAULT-FINI
            CVAULT-S-OK _attt-status
        ELSE
            DROP
        THEN
    THEN

    _atsi-backing-a @ ?DUP IF
        _ATSI-BACKING-U _atpart-zero? _attt-assert
    THEN
    _atsi-backing-b @ ?DUP IF
        _ATSI-BACKING-U _atpart-zero? _attt-assert
    THEN
    _atsi-vault-config @ ?DUP IF
        CVAULT-CONFIG-CLEAR
        CVAULT-S-OK _attt-status
    THEN
    _atsi-session-config O2SESSION-CONFIG-CLEAR
    O2SESSION-S-OK _attt-status
    _atsi-vault-id RID-CLEAR
    _atsi-key-id RID-CLEAR
    _atsi-session-rid RID-CLEAR
    _atsi-root-key SEALED-RECORD-ROOT-KEY-SIZE 0 FILL
    0 _atsi-expected-a !
    0 _atsi-expected-u !
    0 _atsi-r-key-a !
    0 _atsi-r-key-u !
    0 _atsi-r-consumer-xt !
    0 _atsi-r-consumer-context !
    0 _atsi-r-resolver-context !
    0 _attt-grant-context !

    _atsi-session-b _atsi-free
    _atsi-session-a _atsi-free
    _atsi-backing-b _atsi-free
    _atsi-backing-a _atsi-free
    _atsi-vault-b _atsi-free
    _atsi-vault-a _atsi-free
    _atsi-vault-config _atsi-free

    _ATTT-FINISH
    _attt-fails @ IF
        ." AT SESSION INSTALL FAIL checks/fails "
        _attt-checks @ . _attt-fails @ . CR
    ELSE
        ." AT SESSION INSTALL PASS checks "
        _attt-checks @ . CR
    THEN
    TX-FLUSH ;
