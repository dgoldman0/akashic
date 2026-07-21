\ =====================================================================
\  provider-auth.f - Provider-neutral account and authentication port
\ =====================================================================
\  Implementations own credentials and protocol state. The port exposes only
\  bounded account metadata, interactive challenge state, and callback-borrowed
\  access credentials.
\ =====================================================================

PROVIDED akashic-agent-auth-port

REQUIRE ../../../interop/value.f

0 CONSTANT AAUTH-S-OK
1 CONSTANT AAUTH-S-UNSUPPORTED
2 CONSTANT AAUTH-S-INVALID
3 CONSTANT AAUTH-S-CAPACITY
4 CONSTANT AAUTH-S-BUSY
5 CONSTANT AAUTH-S-PENDING
6 CONSTANT AAUTH-S-TRANSPORT
7 CONSTANT AAUTH-S-PROTOCOL
8 CONSTANT AAUTH-S-EXPIRED
9 CONSTANT AAUTH-S-CANCELLED

1 CONSTANT AAUTH-M-SECRET
2 CONSTANT AAUTH-M-DEVICE

0 CONSTANT AAUTH-STATE-UNSUPPORTED
1 CONSTANT AAUTH-STATE-SIGNED-OUT
2 CONSTANT AAUTH-STATE-STARTING
3 CONSTANT AAUTH-STATE-PENDING
4 CONSTANT AAUTH-STATE-READY
5 CONSTANT AAUTH-STATE-REFRESHING
6 CONSTANT AAUTH-STATE-ERROR

  0 CONSTANT _AA-METHODS
  8 CONSTANT _AA-STATE
 16 CONSTANT _AA-REVISION
 24 CONSTANT _AA-CONTEXT
 32 CONSTANT _AA-BEGIN-XT       \ ( context -- status )
 40 CONSTANT _AA-POLL-XT        \ ( context -- status )
 48 CONSTANT _AA-CANCEL-XT      \ ( context -- status )
 56 CONSTANT _AA-LOGOUT-XT      \ ( context -- status )
 64 CONSTANT _AA-SECRET-SET-XT  \ ( secret-a secret-u context -- status )
 72 CONSTANT _AA-WITH-ACCESS-XT \ ( callback callback-context context -- status )
 80 CONSTANT _AA-REFRESH-XT     \ ( context -- status )
 88 CONSTANT _AA-ACCOUNT-ID
_AA-ACCOUNT-ID CV-SIZE + CONSTANT _AA-ACCOUNT-LABEL
_AA-ACCOUNT-LABEL CV-SIZE + CONSTANT _AA-PLAN
_AA-PLAN CV-SIZE + CONSTANT _AA-USER-CODE
_AA-USER-CODE CV-SIZE + CONSTANT _AA-VERIFY-URI
_AA-VERIFY-URI CV-SIZE + CONSTANT _AA-ERROR
_AA-ERROR CV-SIZE + CONSTANT _AA-EXPIRES-MS
_AA-EXPIRES-MS 8 + CONSTANT _AA-POLL-INTERVAL-MS
_AA-POLL-INTERVAL-MS 8 + CONSTANT _AA-LAST-STATUS
_AA-LAST-STATUS 8 + CONSTANT _AA-DISPOSE-XT   \ ( context -- )
_AA-DISPOSE-XT 8 + CONSTANT AGENT-PROVIDER-AUTH-SIZE

: AAUTH.METHODS          ( auth -- a ) _AA-METHODS + ;
: AAUTH.STATE            ( auth -- a ) _AA-STATE + ;
: AAUTH.REVISION         ( auth -- a ) _AA-REVISION + ;
: AAUTH.CONTEXT          ( auth -- a ) _AA-CONTEXT + ;
: AAUTH.BEGIN-XT         ( auth -- a ) _AA-BEGIN-XT + ;
: AAUTH.POLL-XT          ( auth -- a ) _AA-POLL-XT + ;
: AAUTH.CANCEL-XT        ( auth -- a ) _AA-CANCEL-XT + ;
: AAUTH.LOGOUT-XT        ( auth -- a ) _AA-LOGOUT-XT + ;
: AAUTH.SECRET-SET-XT    ( auth -- a ) _AA-SECRET-SET-XT + ;
: AAUTH.WITH-ACCESS-XT   ( auth -- a ) _AA-WITH-ACCESS-XT + ;
: AAUTH.REFRESH-XT       ( auth -- a ) _AA-REFRESH-XT + ;
: AAUTH.ACCOUNT-ID       ( auth -- value ) _AA-ACCOUNT-ID + ;
: AAUTH.ACCOUNT-LABEL    ( auth -- value ) _AA-ACCOUNT-LABEL + ;
: AAUTH.PLAN             ( auth -- value ) _AA-PLAN + ;
: AAUTH.USER-CODE        ( auth -- value ) _AA-USER-CODE + ;
: AAUTH.VERIFY-URI       ( auth -- value ) _AA-VERIFY-URI + ;
: AAUTH.ERROR            ( auth -- value ) _AA-ERROR + ;
: AAUTH.EXPIRES-MS       ( auth -- a ) _AA-EXPIRES-MS + ;
: AAUTH.POLL-INTERVAL-MS ( auth -- a ) _AA-POLL-INTERVAL-MS + ;
: AAUTH.LAST-STATUS      ( auth -- a ) _AA-LAST-STATUS + ;
: AAUTH.DISPOSE-XT       ( auth -- a ) _AA-DISPOSE-XT + ;

: AAUTH-INIT  ( auth -- )
    DUP AGENT-PROVIDER-AUTH-SIZE 0 FILL
    1 OVER AAUTH.REVISION !
    AAUTH-STATE-UNSUPPORTED SWAP AAUTH.STATE ! ;

: AAUTH-READY?  ( auth -- flag )
    DUP 0= IF DROP 0 EXIT THEN AAUTH.STATE @ AAUTH-STATE-READY = ;

: AAUTH-PENDING?  ( auth -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    AAUTH.STATE @ DUP AAUTH-STATE-STARTING =
    OVER AAUTH-STATE-PENDING = OR
    SWAP AAUTH-STATE-REFRESHING = OR ;

: _AAUTH-NOARG  ( auth xt-field-offset -- status )
    >R DUP 0= IF DROP R> DROP AAUTH-S-UNSUPPORTED EXIT THEN
    DUP R> + @ ?DUP 0= IF DROP AAUTH-S-UNSUPPORTED EXIT THEN
    >R AAUTH.CONTEXT @ R> EXECUTE ;

: AAUTH-BEGIN    ( auth -- status ) _AA-BEGIN-XT _AAUTH-NOARG ;
: AAUTH-POLL     ( auth -- status ) _AA-POLL-XT _AAUTH-NOARG ;
: AAUTH-CANCEL   ( auth -- status ) _AA-CANCEL-XT _AAUTH-NOARG ;
: AAUTH-LOGOUT   ( auth -- status ) _AA-LOGOUT-XT _AAUTH-NOARG ;
: AAUTH-REFRESH  ( auth -- status ) _AA-REFRESH-XT _AAUTH-NOARG ;

: AAUTH-SECRET-SET  ( secret-a secret-u auth -- status )
    DUP 0= IF DROP 2DROP AAUTH-S-UNSUPPORTED EXIT THEN
    DUP AAUTH.SECRET-SET-XT @ ?DUP 0= IF
        DROP 2DROP AAUTH-S-UNSUPPORTED EXIT
    THEN
    >R AAUTH.CONTEXT @ R> EXECUTE ;

: AAUTH-WITH-ACCESS  ( callback callback-context auth -- status )
    DUP 0= IF DROP 2DROP AAUTH-S-UNSUPPORTED EXIT THEN
    DUP AAUTH.WITH-ACCESS-XT @ ?DUP 0= IF
        DROP 2DROP AAUTH-S-UNSUPPORTED EXIT
    THEN
    >R AAUTH.CONTEXT @ R> EXECUTE ;

: AAUTH-METADATA-CLEAR  ( auth -- )
    DUP AAUTH.ACCOUNT-ID CV-FREE
    DUP AAUTH.ACCOUNT-LABEL CV-FREE
    DUP AAUTH.PLAN CV-FREE
    DUP AAUTH.USER-CODE CV-FREE
    DUP AAUTH.VERIFY-URI CV-FREE
    DUP AAUTH.ERROR CV-FREE
    0 OVER AAUTH.EXPIRES-MS !
    0 SWAP AAUTH.POLL-INTERVAL-MS ! ;

: AAUTH-DESTROY  ( auth -- )
    DUP 0= IF DROP EXIT THEN
    DUP AAUTH.DISPOSE-XT @ ?DUP IF
        >R DUP AAUTH.CONTEXT @ R> EXECUTE
    THEN
    DUP AAUTH-METADATA-CLEAR
    AGENT-PROVIDER-AUTH-SIZE 0 FILL ;
