\ Focused durable authenticated AT XRPC read qualification.
\
\ This fixture uses the exact production RAM VFS, credential vault, P-256
\ key owner, OAuth session, authenticated XRPC builder, HTTP request, and
\ buffered response parser.  Only P-256/JWK/DPoP cryptographic construction
\ is supplied by the runner's deterministic seam.
\
\ One vault is configured at the session record capacity and stores two
\ distinct records: a durable DPoP key and a durable OAuth session.  The
\ fixture finalizes the first vault/session owners, reconstructs distinct
\ owners over the same VFS, reloads the key slot, rebuilds its address-free
\ binding, opens the session, builds com.atproto.server.getSession, and
\ sends that exact request through a tiny fake NIO/HBUF 200 response.

REQUIRE at-oauth-client-test.f

PROVIDED at-xrpc-auth-read

1700000200 CONSTANT _ATXR-IAT
0x4154585252455331 CONSTANT _ATXR-RESOLVER-TOKEN

O2SESSION-RECORD-SIZE CVAULT-BACKING-SIZE
    CONSTANT _ATXR-BACKING-U

\ The request arena is derived from every public variable-size contributor
\ used by this GET plus a bounded allowance for its fixed header framing.
1024 CONSTANT _ATXR-HTTP-FRAMING-RESERVE
HTARGET-REQUEST-TARGET-CAPACITY
HTARGET-HOST-CAPACITY +
O2TOK-ACCESS-CAPACITY +
OAUTH2-DPOP-ES256-MAX-PROOF-BYTES +
_ATXR-HTTP-FRAMING-RESERVE +
    CONSTANT _ATXR-REQUEST-CAPACITY

256 CONSTANT _ATXR-RESPONSE-CAPACITY
64 CONSTANT _ATXR-BODY-CAPACITY
8 CONSTANT _ATXR-POLL-LIMIT

VARIABLE _atxr-checks
VARIABLE _atxr-fails
VARIABLE _atxr-depth
VARIABLE _atxr-key-generation
VARIABLE _atxr-session-generation
VARIABLE _atxr-resolver-calls
VARIABLE _atxr-old-vfs
VARIABLE _atxr-arena
VARIABLE _atxr-vfs

VARIABLE _atxr-vault-config
VARIABLE _atxr-vault-a
VARIABLE _atxr-vault-b
VARIABLE _atxr-backing-a
VARIABLE _atxr-backing-b
VARIABLE _atxr-session-a
VARIABLE _atxr-session-b
VARIABLE _atxr-key-work
VARIABLE _atxr-xrpc-input
VARIABLE _atxr-xrpc-work
VARIABLE _atxr-request-arena
VARIABLE _atxr-sent

VARIABLE _atxr-active-vault
VARIABLE _atxr-active-backing
VARIABLE _atxr-active-session
VARIABLE _atxr-active-binding

CREATE _atxr-ops VFS-OPS-SIZE ALLOT
CREATE _atxr-binding-desc VFS-BINDING-DESC-SIZE ALLOT

CREATE _atxr-vault-id-store RID-SIZE 7 + ALLOT
CREATE _atxr-root-key-id-store RID-SIZE 7 + ALLOT
CREATE _atxr-key-rid-store RID-SIZE 7 + ALLOT
CREATE _atxr-session-rid-store RID-SIZE 7 + ALLOT
CREATE _atxr-root-key-store
    SEALED-RECORD-ROOT-KEY-SIZE 7 + ALLOT

CREATE _atxr-session-config-store
    O2SESSION-CONFIG-SIZE 7 + ALLOT
CREATE _atxr-grant-store O2SESSION-GRANT-SIZE 7 + ALLOT
CREATE _atxr-key-slot-a-store
    OAUTH2-P256-KEY-SLOT-SIZE 7 + ALLOT
CREATE _atxr-key-slot-b-store
    OAUTH2-P256-KEY-SLOT-SIZE 7 + ALLOT
CREATE _atxr-binding-a-store
    OAUTH2-P256-KEY-BINDING-SIZE 7 + ALLOT
CREATE _atxr-binding-b-store
    OAUTH2-P256-KEY-BINDING-SIZE 7 + ALLOT
CREATE _atxr-target-store HTARGET-SIZE 7 + ALLOT
CREATE _atxr-request-store HTTP-REQUEST-SIZE 7 + ALLOT
CREATE _atxr-exchange-store HTTP-BUFFERED-SIZE 7 + ALLOT
CREATE _atxr-port-store NET-IO-PORT-SIZE 7 + ALLOT

CREATE _atxr-response _ATXR-RESPONSE-CAPACITY ALLOT
CREATE _atxr-body _ATXR-BODY-CAPACITY ALLOT

VARIABLE _atxr-response-u
VARIABLE _atxr-response-pos
VARIABLE _atxr-sent-u
VARIABLE _atxr-poll-count

: _atxr-session-config  ( -- config )
    _atxr-session-config-store 7 + -8 AND ;

: _atxr-grant  ( -- grant )
    _atxr-grant-store 7 + -8 AND ;

: _atxr-key-slot-a  ( -- slot )
    _atxr-key-slot-a-store 7 + -8 AND ;

: _atxr-key-slot-b  ( -- slot )
    _atxr-key-slot-b-store 7 + -8 AND ;

: _atxr-binding-a  ( -- binding )
    _atxr-binding-a-store 7 + -8 AND ;

: _atxr-binding-b  ( -- binding )
    _atxr-binding-b-store 7 + -8 AND ;

: _atxr-target  ( -- target )
    _atxr-target-store 7 + -8 AND ;

: _atxr-request  ( -- request )
    _atxr-request-store 7 + -8 AND ;

: _atxr-exchange  ( -- exchange )
    _atxr-exchange-store 7 + -8 AND ;

: _atxr-port  ( -- port )
    _atxr-port-store 7 + -8 AND ;

: _atxr-vault-id  ( -- rid )
    _atxr-vault-id-store 7 + -8 AND ;

: _atxr-root-key-id  ( -- rid )
    _atxr-root-key-id-store 7 + -8 AND ;

: _atxr-key-rid  ( -- rid )
    _atxr-key-rid-store 7 + -8 AND ;

: _atxr-session-rid  ( -- rid )
    _atxr-session-rid-store 7 + -8 AND ;

: _atxr-root-key  ( -- key )
    _atxr-root-key-store 7 + -8 AND ;

\ =====================================================================
\  Small assertion, storage, and byte helpers
\ =====================================================================

: _atxr-assert  ( flag -- )
    1 _atxr-checks +!
    0= IF
        1 _atxr-fails +!
        ." AT XRPC AUTH READ ASSERT " _atxr-checks @ . CR
        TX-FLUSH
    THEN ;

: _atxr-status  ( actual expected -- )
    2DUP <> IF
        ." AT XRPC AUTH READ STATUS actual/expected "
        2DUP SWAP . . CR
        TX-FLUSH
    THEN
    = _atxr-assert ;

: _atxr-stack  ( -- )
    DEPTH DUP _atxr-depth @ <> IF
        ." AT XRPC AUTH READ STACK "
        _atxr-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _atxr-depth @ = _atxr-assert ;

: _atxr-zero?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1 /STRING
    REPEAT
    2DROP -1 ;

: _atxr-filled?  ( address length byte -- flag )
    >R
    BEGIN DUP WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1 /STRING
    REPEAT
    2DROP R> DROP -1 ;

: _atxr-allocate  ( size variable -- )
    >R
    ALLOCATE ABORT" AT XRPC AUTH READ allocation"
    R> ! ;

: _atxr-free  ( variable -- )
    DUP @ ?DUP IF
        FREE
        0 SWAP !
    ELSE
        DROP
    THEN ;

: _atxr-pair!
  ( source-a source-u address-field length-field -- )
    >R
    OVER R@ !
    NIP !
    R> DROP ;

VARIABLE _atxr-hay-a
VARIABLE _atxr-hay-u
VARIABLE _atxr-needle-a
VARIABLE _atxr-needle-u

: _atxr-contains?
  ( hay-a hay-u needle-a needle-u -- flag )
    _atxr-needle-u !
    _atxr-needle-a !
    _atxr-hay-u !
    _atxr-hay-a !
    _atxr-needle-u @ 0= IF -1 EXIT THEN
    BEGIN
        _atxr-hay-u @ _atxr-needle-u @ U<
    WHILE
        0 EXIT
    REPEAT
    BEGIN
        _atxr-hay-a @ _atxr-needle-u @
        _atxr-needle-a @ _atxr-needle-u @
        COMPARE 0= IF -1 EXIT THEN
        _atxr-hay-u @ _atxr-needle-u @ =
        IF 0 EXIT THEN
        1 _atxr-hay-a +!
        -1 _atxr-hay-u +!
    AGAIN ;

\ =====================================================================
\  Exact root-key resolver and production vault construction
\ =====================================================================

VARIABLE _atxr-r-key-a
VARIABLE _atxr-r-key-u
VARIABLE _atxr-r-consumer-xt
VARIABLE _atxr-r-consumer-context
VARIABLE _atxr-r-resolver-context

: _atxr-resolver
  \ ( key-id key-id-u consumer-xt consumer-context resolver-context
  \   -- status )
    _atxr-r-resolver-context !
    _atxr-r-consumer-context !
    _atxr-r-consumer-xt !
    _atxr-r-key-u !
    _atxr-r-key-a !
    _atxr-r-resolver-context @
        _ATXR-RESOLVER-TOKEN = _atxr-assert
    _atxr-r-key-u @ RID-SIZE = _atxr-assert
    _atxr-r-key-a @ _atxr-r-key-u @
        _atxr-root-key-id RID-SIZE COMPARE 0= _atxr-assert
    1 _atxr-resolver-calls +!
    _atxr-root-key SEALED-RECORD-ROOT-KEY-SIZE
    _atxr-r-consumer-context @
    _atxr-r-consumer-xt @ EXECUTE ;

: _atxr-configure-active-vault  ( -- )
    _atxr-vault-config @ CVAULT-CONFIG-CLEAR
    CVAULT-S-OK _atxr-status
    S" /vault"
        _atxr-vault-config @ CVAULT-C.ROOT-U !
        _atxr-vault-config @ CVAULT-C.ROOT !
    O2SESSION-RECORD-SIZE
        _atxr-vault-config @ CVAULT-C.SECRET-CAPACITY !
    _atxr-active-backing @
        _atxr-vault-config @ CVAULT-C.BACKING !
    _ATXR-BACKING-U
        _atxr-vault-config @ CVAULT-C.BACKING-U !
    _atxr-vfs @
        _atxr-vault-config @ CVAULT-C.VFS !
    _atxr-vault-id
        _atxr-vault-config @ CVAULT-C.VAULT-ID !
    _atxr-root-key-id
        _atxr-vault-config @ CVAULT-C.KEY-ID !
    ['] _atxr-resolver
        _atxr-vault-config @ CVAULT-C.RESOLVER-XT !
    _ATXR-RESOLVER-TOKEN
        _atxr-vault-config @ CVAULT-C.RESOLVER-CONTEXT !
    _atxr-vault-config @ _atxr-active-vault @ CVAULT-INIT
    CVAULT-S-OK _atxr-status
    _atxr-active-vault @ CVAULT-VALID? _atxr-assert
    _atxr-active-vault @ CVAULT-SECRET-CAPACITY@
    CVAULT-S-OK _atxr-status
    O2SESSION-RECORD-SIZE = _atxr-assert ;

: _atxr-select-owner-a  ( -- )
    _atxr-vault-a @ _atxr-active-vault !
    _atxr-backing-a @ _atxr-active-backing !
    _atxr-session-a @ _atxr-active-session !
    _atxr-binding-a _atxr-active-binding ! ;

: _atxr-select-owner-b  ( -- )
    _atxr-vault-b @ _atxr-active-vault !
    _atxr-backing-b @ _atxr-active-backing !
    _atxr-session-b @ _atxr-active-session !
    _atxr-binding-b _atxr-active-binding ! ;

\ =====================================================================
\  Ready AT profile, DPoP-bound client, and durable session
\ =====================================================================

: _atxr-build-client-config  ( -- )
    _atoct-config OAUTH2-CLIENT-CONFIG-WIPE
    OAUTH2-CLIENT-CONFIG-S-OK _atxr-status
    _atoct-input OAUTH2-CLIENT-CONFIG-INPUT-CLEAR
    OAUTH2-CLIENT-CONFIG-S-OK _atxr-status

    _atxr-active-binding @ OAUTH2-P256-KEY-BINDING-SIZE
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.BINDING-U
        _atxr-pair!
    S" https://client.example/oauth/client-metadata.json"
    _atoct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U
        _atxr-pair!
    S" https://callback.example/oauth/callback"
    _atoct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-U
        _atxr-pair!
    S" atproto"
    _atoct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.SCOPE-U
        _atxr-pair!
    S" none"
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-U
        _atxr-pair!
    0 0
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-A
    _atoct-input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-U
        _atxr-pair!
    OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND
        _atoct-input OAUTH2-CLIENT-CONFIG-I.FLAGS !

    _atoct-input _atoct-config OAUTH2-CLIENT-CONFIG-INIT
    OAUTH2-CLIENT-CONFIG-S-OK _atxr-status
    _atoct-config OAUTH2-CLIENT-CONFIG-VALID? _atxr-assert
    _atoct-config _atopt-profile _atoct-work
    AT-OAUTH-CLIENT-ADMIT
    AT-OAUTH-CLIENT-S-OK _atxr-status ;

: _atxr-configure-active-session  ( -- )
    _atxr-session-config O2SESSION-CONFIG-CLEAR
    O2SESSION-S-OK _atxr-status
    _atxr-active-vault @
        _atxr-session-config O2SESSION-C.VAULT !
    _atxr-session-rid
        _atxr-session-config O2SESSION-C.RID !
    _atxr-active-binding @
        _atxr-session-config O2SESSION-C.BINDING-A !
    OAUTH2-P256-KEY-BINDING-SIZE
        _atxr-session-config O2SESSION-C.BINDING-U !
    _atopt-profile AT-OAUTH-PROFILE-ISSUER@
    AT-OAUTH-PROFILE-S-OK _atxr-status
    _atxr-session-config O2SESSION-C.ISSUER-U !
    _atxr-session-config O2SESSION-C.ISSUER-A !
    _atxr-session-config _atxr-active-session @ O2SESSION-INIT
    O2SESSION-S-OK _atxr-status
    _atxr-active-session @ O2SESSION-VALID? _atxr-assert ;

: _atxr-build-grant  ( -- )
    _atxr-grant O2SESSION-GRANT-CLEAR
    O2SESSION-S-OK _atxr-status
    S" access-vertical"
        _atxr-grant O2SESSION-G.ACCESS-U !
        _atxr-grant O2SESSION-G.ACCESS-A !
    S" DPoP"
        _atxr-grant O2SESSION-G.TOKEN-TYPE-U !
        _atxr-grant O2SESSION-G.TOKEN-TYPE-A !
    S" atproto"
        _atxr-grant O2SESSION-G.SCOPE-U !
        _atxr-grant O2SESSION-G.SCOPE-A !
    O2SESSION-GRANT-F-SCOPE
        _atxr-grant O2SESSION-G.FLAGS ! ;

: _atxr-check-key-record  ( -- )
    _atxr-key-rid _atxr-active-vault @ CVAULT-METADATA
    CVAULT-S-OK _atxr-status
    OAUTH2-P256-KEY-RECORD-SIZE = _atxr-assert
    OAUTH2-P256-KEY-DPOP-CREDENTIAL-KIND = _atxr-assert
    CVAULT-STATE-PRESENT = _atxr-assert
    _atxr-key-generation @ = _atxr-assert ;

: _atxr-check-session-record  ( -- )
    _atxr-session-rid _atxr-active-vault @ CVAULT-METADATA
    CVAULT-S-OK _atxr-status
    O2SESSION-RECORD-SIZE = _atxr-assert
    O2SESSION-CREDENTIAL-KIND = _atxr-assert
    CVAULT-STATE-PRESENT = _atxr-assert
    _atxr-session-generation @ = _atxr-assert ;

\ =====================================================================
\  Setup, provision, install, and exact owner restart
\ =====================================================================

: _ATXR-SETUP  ( -- )
    0 _atxr-checks !
    0 _atxr-fails !
    DEPTH _atxr-depth !
    0 _atxr-key-generation !
    0 _atxr-session-generation !
    0 _atxr-resolver-calls !

    CVAULT-CONFIG-SIZE
        _atxr-vault-config _atxr-allocate
    CVAULT-SIZE _atxr-vault-a _atxr-allocate
    CVAULT-SIZE _atxr-vault-b _atxr-allocate
    _ATXR-BACKING-U _atxr-backing-a _atxr-allocate
    _ATXR-BACKING-U _atxr-backing-b _atxr-allocate
    OAUTH2-SESSION-SIZE _atxr-session-a _atxr-allocate
    OAUTH2-SESSION-SIZE _atxr-session-b _atxr-allocate
    OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE
        _atxr-key-work _atxr-allocate
    AT-XRPC-AUTH-GET-INPUT-SIZE
        _atxr-xrpc-input _atxr-allocate
    AT-XRPC-AUTH-GET-WORKSPACE-SIZE
        _atxr-xrpc-work _atxr-allocate
    _ATXR-REQUEST-CAPACITY
        _atxr-request-arena _atxr-allocate
    _ATXR-REQUEST-CAPACITY
        _atxr-sent _atxr-allocate

    _atxr-vault-config @ CVAULT-CONFIG-SIZE 0 FILL
    _atxr-vault-a @ CVAULT-SIZE 0 FILL
    _atxr-vault-b @ CVAULT-SIZE 0 FILL
    _atxr-backing-a @ _ATXR-BACKING-U 0 FILL
    _atxr-backing-b @ _ATXR-BACKING-U 0 FILL
    _atxr-session-a @ OAUTH2-SESSION-SIZE 0 FILL
    _atxr-session-b @ OAUTH2-SESSION-SIZE 0 FILL
    _atxr-key-work @ OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE 0 FILL
    _atxr-xrpc-input @ AT-XRPC-AUTH-GET-INPUT-SIZE 0 FILL
    _atxr-xrpc-work @ AT-XRPC-AUTH-GET-WORKSPACE-SIZE 0 FILL
    _atxr-request-arena @ _ATXR-REQUEST-CAPACITY 0 FILL
    _atxr-sent @ _ATXR-REQUEST-CAPACITY 0 FILL

    _atxr-vault-id RID-SIZE 0x51 FILL
    _atxr-root-key-id RID-SIZE 0x52 FILL
    _atxr-key-rid RID-SIZE 0x61 FILL
    _atxr-session-rid RID-SIZE 0x62 FILL
    _atxr-root-key SEALED-RECORD-ROOT-KEY-SIZE 0x53 FILL
    _atxr-key-rid _atxr-session-rid RID= 0= _atxr-assert

    _atxr-session-config O2SESSION-CONFIG-SIZE 0 FILL
    _atxr-grant O2SESSION-GRANT-SIZE 0 FILL
    _atxr-key-slot-a OAUTH2-P256-KEY-SLOT-SIZE 0 FILL
    _atxr-key-slot-b OAUTH2-P256-KEY-SLOT-SIZE 0 FILL
    _atxr-binding-a OAUTH2-P256-KEY-BINDING-SIZE 0 FILL
    _atxr-binding-b OAUTH2-P256-KEY-BINDING-SIZE 0 FILL
    _atxr-target HTARGET-SIZE 0 FILL
    _atxr-request HTTP-REQUEST-SIZE 0 FILL
    _atxr-exchange HTTP-BUFFERED-SIZE 0 FILL
    _atxr-port NET-IO-PORT-SIZE 0 FILL
    _atxr-response _ATXR-RESPONSE-CAPACITY 0 FILL
    _atxr-body _ATXR-BODY-CAPACITY 0 FILL
    0 _atxr-response-u !
    0 _atxr-response-pos !
    0 _atxr-sent-u !

    VFS-CUR _atxr-old-vfs !
    1048576 A-XMEM ARENA-NEW
    DUP 0= _atxr-assert
    DROP _atxr-arena !
    VFS-RAM-OPS _atxr-ops VFS-OPS-SIZE CMOVE
    VFS-RAM-BINDING _atxr-binding-desc
        VFS-BINDING-DESC-SIZE CMOVE
    _atxr-ops _atxr-binding-desc VB.OPS !
    _atxr-arena @ _atxr-binding-desc 0 VFS-NEW
    DUP 0= _atxr-assert
    DROP
    DUP 0<> _atxr-assert
    _atxr-vfs !
    _atxr-vfs @ VFS-USE
    S" vault" _atxr-vfs @ VFS-MKDIR
    0 _atxr-status

    _ATOCT-INIT
    _atopt-profile-ready
    _atopt-profile AT-OAUTH-PROFILE-READY? _atxr-assert

    _atxr-select-owner-a
    _atxr-configure-active-vault
    _atxr-stack ;

: _ATXR-PROVISION  ( -- )
    _O2PKD-RESET
    _atxr-key-work @ OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE
        0 FILL
    _atxr-key-rid _atxr-active-vault @
    _atxr-key-slot-a _atxr-key-work @
    OAUTH2-P256-KEY-PROVISION-DPOP
    OAUTH2-P256-KEY-S-OK _atxr-status
    DUP 1 = _atxr-assert
    _atxr-key-generation !

    _atxr-binding-a OAUTH2-P256-KEY-BINDING-CLEAR
    OAUTH2-P256-KEY-S-OK _atxr-status
    0 _atxr-key-slot-a _atxr-binding-a
    OAUTH2-P256-KEY-BINDING-INIT
    OAUTH2-P256-KEY-S-OK _atxr-status
    _atxr-binding-a OAUTH2-P256-KEY-BINDING-SIZE
    OAUTH2-P256-KEY-BINDING-PRESENCE@
    OAUTH2-P256-KEY-S-OK _atxr-status
    OAUTH2-P256-KEY-BINDING-F-DPOP = _atxr-assert

    _atxr-build-client-config
    _atxr-configure-active-session
    _atxr-check-key-record
    _atxr-stack ;

: _ATXR-INSTALL  ( -- )
    _atxr-build-grant
    _atxr-grant _atxr-active-session @ O2SESSION-INSTALL
    O2SESSION-S-OK _atxr-status
    DUP 1 = _atxr-assert
    _atxr-session-generation !
    _atxr-active-session @ O2SESSION-STATE@
    O2SESSION-S-OK _atxr-status
    O2SESSION-PHASE-ACTIVE = _atxr-assert
    _atxr-session-generation @ = _atxr-assert
    _atxr-check-key-record
    _atxr-check-session-record
    _atxr-stack ;

: _ATXR-RESTART  ( -- )
    _atxr-session-a @ O2SESSION-CLOSE
    O2SESSION-S-OK _atxr-status
    _atxr-session-a @ O2SESSION-FINI
    O2SESSION-S-OK _atxr-status
    _atxr-session-a @ OAUTH2-SESSION-SIZE
        _atxr-zero? _atxr-assert
    _atxr-vault-a @ CVAULT-FINI
    CVAULT-S-OK _atxr-status
    _atxr-vault-a @ CVAULT-SIZE _atxr-zero? _atxr-assert
    _atxr-backing-a @ _ATXR-BACKING-U
        _atxr-zero? _atxr-assert

    _atxr-select-owner-b
    _atxr-configure-active-vault
    _atxr-key-work @ OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE
        0 FILL
    _atxr-key-rid _atxr-active-vault @
    _atxr-key-slot-b _atxr-key-work @
    OAUTH2-P256-KEY-SLOT-LOAD-DPOP
    OAUTH2-P256-KEY-S-OK _atxr-status
    _atxr-key-generation @ = _atxr-assert
    _atxr-key-slot-a OAUTH2-P256-KEY-SLOT-SIZE
    _atxr-key-slot-b OAUTH2-P256-KEY-SLOT-SIZE
        COMPARE 0= _atxr-assert

    _atxr-binding-b OAUTH2-P256-KEY-BINDING-CLEAR
    OAUTH2-P256-KEY-S-OK _atxr-status
    0 _atxr-key-slot-b _atxr-binding-b
    OAUTH2-P256-KEY-BINDING-INIT
    OAUTH2-P256-KEY-S-OK _atxr-status
    _atxr-binding-a OAUTH2-P256-KEY-BINDING-SIZE
    _atxr-binding-b OAUTH2-P256-KEY-BINDING-SIZE
        COMPARE 0= _atxr-assert

    _atxr-build-client-config
    _atxr-configure-active-session
    _atxr-active-session @ O2SESSION-OPEN
    O2SESSION-S-OK _atxr-status
    O2SESSION-PHASE-ACTIVE = _atxr-assert
    _atxr-session-generation @ = _atxr-assert
    _atxr-check-key-record
    _atxr-check-session-record
    _atxr-resolver-calls @ 0> _atxr-assert
    _atxr-stack ;

\ =====================================================================
\  Authenticated request and deterministic proof observations
\ =====================================================================

: _atxr-request-contains?  ( needle-a needle-u -- flag )
    _atxr-request HREQ.BUFFER @
    _atxr-request HREQ.LENGTH @
    2SWAP _atxr-contains? ;

: _ATXR-BUILD  ( -- )
    _atxr-target HTARGET-INIT
    S" https://pds.example/xrpc/com.atproto.server.getSession"
    _atxr-target HTARGET-PARSE
    HTARGET-S-OK _atxr-status
    _atxr-target HTARGET-VALID? _atxr-assert

    _atxr-request HTTP-REQUEST-SIZE 0 FILL
    _atxr-xrpc-input @ AT-XRPC-AUTH-GET-INPUT-CLEAR
    AT-XRPC-S-OK _atxr-status
    _ATXR-IAT
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.IAT !
    _atxr-active-vault @
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.VAULT !
    _atoct-config
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.CONFIG !
    _atopt-profile
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.PROFILE !
    _atxr-active-session @
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.SESSION !
    _atxr-target
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.TARGET !
    _atxr-request-arena @
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.REQUEST-A !
    _ATXR-REQUEST-CAPACITY
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.REQUEST-CAP !
    _atxr-request
        _atxr-xrpc-input @ AT-XRPC-AUTH-GET-I.REQUEST !

    _atxr-xrpc-work @ AT-XRPC-AUTH-GET-WORKSPACE-SIZE
        0xC3 FILL
    _O2PKD-RESET
    _atxr-xrpc-input @ _atxr-xrpc-work @
    AT-XRPC-AUTH-GET-BUILD
    AT-XRPC-S-OK _atxr-status
    _atxr-xrpc-work @ AT-XRPC-AUTH-GET-WORKSPACE-SIZE
        _atxr-zero? _atxr-assert
    _atxr-request HREQ.STATE @
        HREQ-STATE-SEALED = _atxr-assert
    _atxr-request HREQ.LENGTH @ 0> _atxr-assert

    _O2PKD-DPOP-CALLS @ 1 = _atxr-assert
    _O2PKD-DPOP-PRIVATE-OK @ _atxr-assert
    _O2PKD-DPOP-IAT @ _ATXR-IAT = _atxr-assert
    _O2PKD-DPOP-HTM-A @ _O2PKD-DPOP-HTM-U @
        S" GET" COMPARE 0= _atxr-assert
    _O2PKD-DPOP-HTU-A @ _O2PKD-DPOP-HTU-U @
        S" https://pds.example/xrpc/com.atproto.server.getSession"
        COMPARE 0= _atxr-assert
    _O2PKD-DPOP-NONCE-A @ 0= _atxr-assert
    _O2PKD-DPOP-NONCE-U @ 0= _atxr-assert
    _O2PKD-DPOP-TOKEN-U @
        S" access-vertical" NIP = _atxr-assert

    S" GET /xrpc/com.atproto.server.getSession HTTP/1.1"
        _atxr-request-contains? _atxr-assert
    S" Host: pds.example"
        _atxr-request-contains? _atxr-assert
    S" Accept: application/json"
        _atxr-request-contains? _atxr-assert
    S" Authorization: DPoP access-vertical"
        _atxr-request-contains? _atxr-assert
    S" DPoP: deterministic-dpop-proof"
        _atxr-request-contains? _atxr-assert
    S" Accept-Encoding: identity"
        _atxr-request-contains? _atxr-assert
    S" User-Agent: akashic-atproto/1"
        _atxr-request-contains? _atxr-assert
    S" Connection: close"
        _atxr-request-contains? _atxr-assert
    _atxr-stack ;

\ =====================================================================
\  Tiny fake NIO transport and exact HBUF 200 response
\ =====================================================================

: _atxr-response-append  ( address length -- )
    DUP _atxr-response-u @ +
    _ATXR-RESPONSE-CAPACITY > IF
        2DROP 0 _atxr-assert EXIT
    THEN
    DUP >R
    _atxr-response _atxr-response-u @ + SWAP CMOVE
    R> _atxr-response-u +! ;

: _atxr-response-crlf  ( -- )
    13 _atxr-response _atxr-response-u @ + C!
    1 _atxr-response-u +!
    10 _atxr-response _atxr-response-u @ + C!
    1 _atxr-response-u +! ;

: _atxr-build-response  ( -- )
    _atxr-response _ATXR-RESPONSE-CAPACITY 0 FILL
    0 _atxr-response-u !
    0 _atxr-response-pos !
    S" HTTP/1.1 200 OK" _atxr-response-append
    _atxr-response-crlf
    S" Content-Type: application/json" _atxr-response-append
    _atxr-response-crlf
    S" Content-Length: 2" _atxr-response-append
    _atxr-response-crlf
    S" Connection: close" _atxr-response-append
    _atxr-response-crlf
    _atxr-response-crlf
    S" {}" _atxr-response-append ;

VARIABLE _atxr-io-a
VARIABLE _atxr-io-u
VARIABLE _atxr-io-n

: _atxr-open  ( context -- io-status )
    DROP NIO-S-OK ;

: _atxr-send  ( buffer length context -- count io-status )
    DROP
    _atxr-io-u !
    _atxr-io-a !
    _atxr-sent-u @ _atxr-io-u @ +
    _ATXR-REQUEST-CAPACITY > IF
        0 _atxr-assert
        0 NIO-S-FAILED EXIT
    THEN
    _atxr-io-a @
    _atxr-sent @ _atxr-sent-u @ +
    _atxr-io-u @ CMOVE
    _atxr-io-u @ _atxr-sent-u +!
    _atxr-io-u @ NIO-S-OK ;

: _atxr-recv  ( buffer capacity context -- count io-status )
    DROP
    _atxr-io-u !
    _atxr-io-a !
    _atxr-response-u @ _atxr-response-pos @ -
    DUP 0= IF
        DROP 0 NIO-S-EOF EXIT
    THEN
    _atxr-io-u @ MIN
    _atxr-io-n !
    _atxr-response _atxr-response-pos @ +
    _atxr-io-a @ _atxr-io-n @ CMOVE
    _atxr-io-n @ _atxr-response-pos +!
    _atxr-io-n @ NIO-S-OK ;

: _atxr-poll  ( context -- )
    DROP ;

: _atxr-cancel  ( context -- )
    DROP ;

: _atxr-close  ( context -- io-status )
    DROP NIO-S-OK ;

: _atxr-install-port  ( -- )
    _atxr-port NIO-INIT
    _atxr-port _atxr-port NIO.CONTEXT !
    ['] _atxr-open _atxr-port NIO.OPEN-START-XT !
    ['] _atxr-open _atxr-port NIO.OPEN-POLL-XT !
    ['] _atxr-send _atxr-port NIO.SEND-XT !
    ['] _atxr-recv _atxr-port NIO.RECV-XT !
    ['] _atxr-poll _atxr-port NIO.POLL-XT !
    ['] _atxr-cancel _atxr-port NIO.CANCEL-XT !
    ['] _atxr-close _atxr-port NIO.CLOSE-START-XT !
    ['] _atxr-close _atxr-port NIO.CLOSE-POLL-XT ! ;

: _atxr-poll-response  ( -- )
    0 _atxr-poll-count !
    BEGIN
        _atxr-exchange HBUF-POLL
        DUP HBUF-S-PENDING =
    WHILE
        DROP
        1 _atxr-poll-count +!
        _atxr-poll-count @ _ATXR-POLL-LIMIT >= IF
            0 _atxr-assert EXIT
        THEN
    REPEAT
    HBUF-S-OK _atxr-status ;

: _ATXR-READ  ( -- )
    _atxr-build-response
    _atxr-sent @ _ATXR-REQUEST-CAPACITY 0 FILL
    0 _atxr-sent-u !
    _atxr-body _ATXR-BODY-CAPACITY _atxr-exchange HBUF-INIT
    HBUF-S-OK _atxr-status
    _atxr-install-port
    _atxr-request _atxr-port _atxr-exchange HBUF-START
    HBUF-S-PENDING _atxr-status
    _atxr-poll-response

    _atxr-exchange HBUF.HTTP-CODE @ 200 = _atxr-assert
    _atxr-exchange HBUF.BODY-U @ 2 = _atxr-assert
    _atxr-body 2 S" {}" COMPARE 0= _atxr-assert
    _atxr-sent-u @
        _atxr-request HREQ.LENGTH @ = _atxr-assert
    _atxr-sent @ _atxr-sent-u @
    _atxr-request HREQ.BUFFER @
    _atxr-request HREQ.LENGTH @
        COMPARE 0= _atxr-assert
    _atxr-port NIO.OPEN-STATE @
        NIO-OPEN-STATE-CLOSED = _atxr-assert
    _atxr-port NIO.CLOSE-STATE @
        NIO-CLOSE-STATE-CLOSED = _atxr-assert
    _atxr-exchange HBUF.PORT @ 0= _atxr-assert
    _atxr-stack ;

\ =====================================================================
\  Cleanup and single focused pass marker
\ =====================================================================

: _ATXR-FINISH  ( -- )
    _atxr-session-b @ ?DUP IF
        DUP O2SESSION-VALID? IF
            DUP O2SESSION-CLOSE
            O2SESSION-S-OK _atxr-status
            O2SESSION-FINI
            O2SESSION-S-OK _atxr-status
        ELSE
            DROP
        THEN
    THEN
    _atxr-vault-b @ ?DUP IF
        DUP CVAULT-VALID? IF
            CVAULT-FINI CVAULT-S-OK _atxr-status
        ELSE
            DROP
        THEN
    THEN
    _atxr-backing-b @ ?DUP IF
        _ATXR-BACKING-U _atxr-zero? _atxr-assert
    THEN

    _atxr-request HREQ-CLEAR
    _atxr-exchange HBUF-RESET
    _atxr-target HTARGET-SIZE 0 FILL
    _atxr-port NET-IO-PORT-SIZE 0 FILL
    _atxr-body _ATXR-BODY-CAPACITY 0 FILL
    _atxr-response _ATXR-RESPONSE-CAPACITY 0 FILL
    _atxr-sent @ ?DUP IF
        _ATXR-REQUEST-CAPACITY 0 FILL
    THEN
    _atxr-xrpc-input @ ?DUP IF
        AT-XRPC-AUTH-GET-INPUT-CLEAR
        AT-XRPC-S-OK _atxr-status
    THEN
    _atxr-xrpc-work @ ?DUP IF
        AT-XRPC-AUTH-GET-WORKSPACE-CLEAR
        AT-XRPC-S-OK _atxr-status
    THEN
    _atxr-key-work @ ?DUP IF
        OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE 0 FILL
    THEN
    _atxr-grant O2SESSION-GRANT-CLEAR
    O2SESSION-S-OK _atxr-status
    _atxr-session-config O2SESSION-CONFIG-CLEAR
    O2SESSION-S-OK _atxr-status
    _atoct-config OAUTH2-CLIENT-CONFIG-WIPE
    OAUTH2-CLIENT-CONFIG-S-OK _atxr-status
    _atopt-profile AT-OAUTH-PROFILE-WIPE
    AT-OAUTH-PROFILE-S-OK _atxr-status

    _atxr-key-slot-a OAUTH2-P256-KEY-SLOT-SIZE 0 FILL
    _atxr-key-slot-b OAUTH2-P256-KEY-SLOT-SIZE 0 FILL
    _atxr-binding-a OAUTH2-P256-KEY-BINDING-CLEAR
    OAUTH2-P256-KEY-S-OK _atxr-status
    _atxr-binding-b OAUTH2-P256-KEY-BINDING-CLEAR
    OAUTH2-P256-KEY-S-OK _atxr-status
    _atxr-vault-id RID-CLEAR
    _atxr-root-key-id RID-CLEAR
    _atxr-key-rid RID-CLEAR
    _atxr-session-rid RID-CLEAR
    _atxr-root-key SEALED-RECORD-ROOT-KEY-SIZE 0 FILL

    _atxr-vfs @ ?DUP IF
        _atxr-old-vfs @ VFS-USE
        VFS-DESTROY
        0 _atxr-vfs !
    THEN

    _atxr-sent _atxr-free
    _atxr-request-arena _atxr-free
    _atxr-xrpc-work _atxr-free
    _atxr-xrpc-input _atxr-free
    _atxr-key-work _atxr-free
    _atxr-session-b _atxr-free
    _atxr-session-a _atxr-free
    _atxr-backing-b _atxr-free
    _atxr-backing-a _atxr-free
    _atxr-vault-b _atxr-free
    _atxr-vault-a _atxr-free
    _atxr-vault-config _atxr-free

    0 _atxr-active-vault !
    0 _atxr-active-backing !
    0 _atxr-active-session !
    0 _atxr-active-binding !
    0 _atxr-r-key-a !
    0 _atxr-r-key-u !
    0 _atxr-r-consumer-xt !
    0 _atxr-r-consumer-context !
    0 _atxr-r-resolver-context !
    0 _atxr-hay-a !
    0 _atxr-hay-u !
    0 _atxr-needle-a !
    0 _atxr-needle-u !
    0 _atxr-io-a !
    0 _atxr-io-u !
    0 _atxr-io-n !

    _atopt-fails @ 0= _atxr-assert
    _atoct-fails @ 0= _atxr-assert
    _atxr-stack
    _atxr-fails @ IF
        ." AT XRPC AUTH READ FAIL checks/fails "
        _atxr-checks @ . _atxr-fails @ . CR
    ELSE
        ." AT XRPC AUTH READ PASS checks "
        _atxr-checks @ . CR
    THEN
    TX-FLUSH ;
