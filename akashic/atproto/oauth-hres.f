\ =====================================================================
\  oauth-hres.f - Shared AT OAuth HTTP-resource policy
\ =====================================================================
\  This state-free helper owns the HTTP envelope shared by AT OAuth JSON
\  resources.  It configures caller-owned HRES specifications and verifies
\  retained results without owning transport, DNS, TLS, deadlines, leases,
\  metadata parsing, keys, tokens, sessions, XRPC, or application state.
\
\  Public API:
\    AT-OAUTH-HRES-SPEC-POLICY!  ( spec -- hres-status )
\    AT-OAUTH-HRES-URI-ENVELOPE?
\      ( resource expected-a expected-u -- flag )
\    AT-OAUTH-HRES-TARGET-ENVELOPE?
\      ( resource expected-target -- flag )
\ =====================================================================

PROVIDED akashic-at-oauth-http

REQUIRE ../utils/caller-span.f
REQUIRE ../utils/string.f
REQUIRE ../net/http-resource.f

: _ATOHTTP-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _ATOHTTP-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _ATOHTTP-FIXED?  ( address size -- flag )
    OVER 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _ATOHTTP-EXPECTED?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    DUP HTARGET-URI-CAPACITY > IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _ATOHTTP-JSON-MEDIA?  ( media -- flag )
    DUP MTYPE-VALID? 0= IF DROP 0 EXIT THEN
    DUP MTYPE-TYPE$ S" application" STR-STRI= 0= IF
        DROP 0 EXIT
    THEN
    MTYPE-SUBTYPE$ S" json" STR-STRI= ;

: _ATOHTTP-MEDIA-POLICY  ( media context -- media-status )
    DROP
    _ATOHTTP-JSON-MEDIA?
    IF HRES-S-OK ELSE HRES-S-INVALID THEN ;

: AT-OAUTH-HRES-SPEC-POLICY!  ( spec -- hres-status )
    DUP HRES-SPEC-SIZE _ATOHTTP-FIXED? 0= IF
        DROP HRES-S-INVALID EXIT
    THEN
    >R
    S" application/json" R@ HRES-SPEC-ACCEPT!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    200 200 R@ HRES-SPEC-SUCCESS-RANGE!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    0 R@ HRES-SPEC-REDIRECT-MAX!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    HRES-MEDIA-REQUIRED R@ HRES-SPEC-MEDIA-MODE!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    0 ['] _ATOHTTP-MEDIA-POLICY R> HRES-SPEC-MEDIA! ;

: AT-OAUTH-HRES-URI-ENVELOPE?
  ( resource expected-a expected-u -- flag )
    2 PICK HTTP-RESOURCE-SIZE _ATOHTTP-FIXED? 0= IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2DUP _ATOHTTP-EXPECTED? 0= IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2 PICK HRES-VALID? 0= IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2 PICK HRES-RESULT-VALID? 0= IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2 PICK HRES-HTTP-STATUS@ 200 <> IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2 PICK HRES-REDIRECT-COUNT@ 0<> IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2 PICK HRES-REQUESTED-URI$ 2OVER STR-STR= 0= IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2 PICK HRES-EFFECTIVE-URI$ 2OVER STR-STR= 0= IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    2 PICK HRES-MEDIA@ 0= IF
        _ATOHTTP-DROP4 0 EXIT
    THEN
    _ATOHTTP-JSON-MEDIA? 0= IF
        _ATOHTTP-DROP3 0 EXIT
    THEN
    _ATOHTTP-DROP3 -1 ;

: AT-OAUTH-HRES-TARGET-ENVELOPE?
  ( resource expected-target -- flag )
    DUP HTARGET-SIZE _ATOHTTP-FIXED? 0= IF 2DROP 0 EXIT THEN
    DUP HTARGET-VALID? 0= IF 2DROP 0 EXIT THEN
    HTARGET-URI$
    AT-OAUTH-HRES-URI-ENVELOPE? ;
