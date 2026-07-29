\ =====================================================================
\  oauth-profile-hres.f - AT OAuth discovery over HTTP resources
\ =====================================================================
\  This state-free adapter applies the AT Protocol OAuth discovery HTTP
\  profile to caller-owned HRES results.  It independently requires an
\  exact requested and effective target, status 200, zero redirects, and
\  application/json before parsing generic OAuth metadata and submitting
\  it to one caller-owned AT OAuth profile.
\
\  HTTP-envelope and metadata-parse failures do not advance the profile.
\  Successfully parsed metadata is submitted to oauth-profile.f, where
\  trust-chain and capability failures are terminal.  The adapter owns no
\  transport, DNS, TLS, browser, token, session, XRPC, or Streams state.
\
\  Public API:
\    AT-OAUTH-HRES-WORKSPACE-SIZE
\    AT-OAUTH-HRES-WORKSPACE-CLEAR
\    AT-OAUTH-HRES-SPEC-POLICY!
\    AT-OAUTH-HRES-RESOURCE!
\    AT-OAUTH-HRES-AUTHORIZATION-SERVER!
\ =====================================================================

\ KDOS module identities are bounded to 23 bytes.
PROVIDED akashic-at-oauth-hres

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/string.f
REQUIRE ../net/http-resource.f
REQUIRE ../security/oauth2/resource-metadata.f
REQUIRE ../security/oauth2/metadata.f
REQUIRE oauth-profile.f

\ =====================================================================
\  Caller-owned transient workspace
\ =====================================================================

\ Authorization-server metadata is the larger result and parser workspace.
\ Protected-resource metadata reuses the same disjoint result/scratch spans.
OAUTH2-METADATA-SIZE CONSTANT _ATOH-RESULT-SIZE
_ATOH-RESULT-SIZE CONSTANT _ATOH-PARSER-OFF
OAUTH2-METADATA-WORKSPACE-SIZE CONSTANT _ATOH-PARSER-SIZE
_ATOH-PARSER-OFF _ATOH-PARSER-SIZE +
    CONSTANT AT-OAUTH-HRES-WORKSPACE-SIZE

: _ATOH.RESULT  ( workspace -- metadata ) ;
: _ATOH.PARSER  ( workspace -- parser-workspace ) _ATOH-PARSER-OFF + ;

\ =====================================================================
\  Admission and ownership helpers
\ =====================================================================

: _ATOH-CALLER>STATUS  ( caller-status -- profile-status )
    DUP CALLER-SPAN-S-OK = IF
        DROP AT-OAUTH-PROFILE-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP AT-OAUTH-PROFILE-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-OAUTH-PROFILE-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-OAUTH-PROFILE-S-PLATFORM EXIT
    THEN
    DROP AT-OAUTH-PROFILE-S-PLATFORM ;

: _ATOH-SPAN-STATUS  ( address length -- profile-status )
    DUP 0< IF 2DROP AT-OAUTH-PROFILE-S-INVALID EXIT THEN
    DUP 0= IF 2DROP AT-OAUTH-PROFILE-S-OK EXIT THEN
    OVER 0= IF 2DROP AT-OAUTH-PROFILE-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATOH-CALLER>STATUS ;

: _ATOH-FIXED-STATUS  ( address size -- profile-status )
    OVER 0= IF 2DROP AT-OAUTH-PROFILE-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP AT-OAUTH-PROFILE-S-INVALID EXIT THEN
    _ATOH-SPAN-STATUS ;

: _ATOH-RETURN3  ( x1 x2 x3 status -- status )
    >R 2DROP DROP R> ;

: _ATOH-GEOMETRY  ( resource workspace profile -- profile-status )
    2 PICK HTTP-RESOURCE-SIZE _ATOH-SPAN-STATUS
    ?DUP IF _ATOH-RETURN3 EXIT THEN
    1 PICK AT-OAUTH-HRES-WORKSPACE-SIZE _ATOH-FIXED-STATUS
    ?DUP IF _ATOH-RETURN3 EXIT THEN
    DUP AT-OAUTH-PROFILE-SIZE _ATOH-FIXED-STATUS
    ?DUP IF _ATOH-RETURN3 EXIT THEN

    2 PICK HTTP-RESOURCE-SIZE
    3 PICK AT-OAUTH-HRES-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-PROFILE-S-ALIAS _ATOH-RETURN3 EXIT
    THEN
    2 PICK HTTP-RESOURCE-SIZE
    2 PICK AT-OAUTH-PROFILE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-PROFILE-S-ALIAS _ATOH-RETURN3 EXIT
    THEN
    1 PICK AT-OAUTH-HRES-WORKSPACE-SIZE
    2 PICK AT-OAUTH-PROFILE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-PROFILE-S-ALIAS _ATOH-RETURN3 EXIT
    THEN
    AT-OAUTH-PROFILE-S-OK _ATOH-RETURN3 ;

: _ATOH-BODY-GEOMETRY
  ( resource workspace profile body-a body-u -- same... status )
    2DUP _ATOH-SPAN-STATUS ?DUP IF EXIT THEN
    2DUP 6 PICK HTTP-RESOURCE-SIZE MSPAN-OVERLAP? IF
        AT-OAUTH-PROFILE-S-ALIAS EXIT
    THEN
    2DUP 5 PICK AT-OAUTH-HRES-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-PROFILE-S-ALIAS EXIT
    THEN
    2DUP 4 PICK AT-OAUTH-PROFILE-SIZE MSPAN-OVERLAP? IF
        AT-OAUTH-PROFILE-S-ALIAS EXIT
    THEN
    AT-OAUTH-PROFILE-S-OK ;

: _ATOH-WIPE  ( workspace -- )
    AT-OAUTH-HRES-WORKSPACE-SIZE 0 FILL ;

: AT-OAUTH-HRES-WORKSPACE-CLEAR  ( workspace -- profile-status )
    DUP AT-OAUTH-HRES-WORKSPACE-SIZE _ATOH-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _ATOH-WIPE
    AT-OAUTH-PROFILE-S-OK ;

\ The workspace is already admitted before this wrapper runs.  An operation
\ THROW is rethrown only after the complete transient workspace is wiped.
: _ATOH-CALL-CLEAN
  ( resource workspace profile body-a body-u operation-xt -- status )
    4 PICK >R
    R@ _ATOH-WIPE
    CATCH
    DUP IF
        >R
        3 PICK _ATOH-WIPE
        2DROP 2DROP DROP
        R> R> DROP THROW
    THEN
    DROP
    R@ _ATOH-WIPE
    R> DROP ;

\ =====================================================================
\  Exact JSON HTTP policy
\ =====================================================================

: _ATOH-JSON-MEDIA?  ( media -- flag )
    DUP MTYPE-VALID? 0= IF DROP 0 EXIT THEN
    DUP MTYPE-TYPE$ S" application" STR-STRI= 0= IF
        DROP 0 EXIT
    THEN
    MTYPE-SUBTYPE$ S" json" STR-STRI= ;

: _ATOH-MEDIA-POLICY  ( media context -- media-status )
    DROP
    _ATOH-JSON-MEDIA? IF HRES-S-OK ELSE HRES-S-INVALID THEN ;

: AT-OAUTH-HRES-SPEC-POLICY!  ( spec -- hres-status )
    DUP HRES-SPEC-SIZE _ATOH-SPAN-STATUS
    AT-OAUTH-PROFILE-S-OK <> IF DROP HRES-S-INVALID EXIT THEN
    >R
    S" application/json" R@ HRES-SPEC-ACCEPT!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    200 200 R@ HRES-SPEC-SUCCESS-RANGE!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    0 R@ HRES-SPEC-REDIRECT-MAX!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    HRES-MEDIA-REQUIRED R@ HRES-SPEC-MEDIA-MODE!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    0 ['] _ATOH-MEDIA-POLICY R> HRES-SPEC-MEDIA! ;

: _ATOH-ENVELOPE?  ( resource expected-target -- flag )
    OVER HRES-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER HRES-RESULT-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER HRES-HTTP-STATUS@ 200 <> IF 2DROP 0 EXIT THEN
    OVER HRES-REDIRECT-COUNT@ 0<> IF 2DROP 0 EXIT THEN
    OVER HRES-REQUESTED-TARGET OVER HTARGET-EQUAL? 0= IF
        2DROP 0 EXIT
    THEN
    OVER HRES-EFFECTIVE-TARGET OVER HTARGET-EQUAL? 0= IF
        2DROP 0 EXIT
    THEN
    OVER HRES-MEDIA@ 0= IF
        DROP 2DROP 0 EXIT
    THEN
    _ATOH-JSON-MEDIA? 0= IF 2DROP 0 EXIT THEN
    2DROP -1 ;

: _ATOH-PREPARE
  ( resource workspace profile target-xt -- same... body-a body-u status )
    >R
    DUP R> EXECUTE
    DUP IF
        >R DROP 0 0 R> EXIT
    THEN
    DROP
    3 PICK OVER _ATOH-ENVELOPE? 0= IF
        DROP 0 0 AT-OAUTH-PROFILE-S-HTTP EXIT
    THEN
    DROP
    2 PICK HRES-BODY-STORAGE@
    _ATOH-BODY-GEOMETRY
    ?DUP IF
        >R 2DROP 0 0 R> EXIT
    THEN
    2DROP
    2 PICK HRES-BODY@
    AT-OAUTH-PROFILE-S-OK ;

\ =====================================================================
\  Generic parser status mapping
\ =====================================================================

: _ATOH-RMETA>STATUS  ( parser-status -- profile-status )
    DUP OAUTH2-RESOURCE-METADATA-S-CAPACITY = IF
        DROP AT-OAUTH-PROFILE-S-CAPACITY EXIT
    THEN
    DUP OAUTH2-RESOURCE-METADATA-S-ALIAS = IF
        DROP AT-OAUTH-PROFILE-S-ALIAS EXIT
    THEN
    DUP OAUTH2-RESOURCE-METADATA-S-INTERNAL = IF
        DROP AT-OAUTH-PROFILE-S-INTERNAL EXIT
    THEN
    DUP OAUTH2-RESOURCE-METADATA-S-RANGE = IF
        DROP AT-OAUTH-PROFILE-S-RANGE EXIT
    THEN
    DUP OAUTH2-RESOURCE-METADATA-S-PROTECTED = IF
        DROP AT-OAUTH-PROFILE-S-PROTECTED EXIT
    THEN
    DUP OAUTH2-RESOURCE-METADATA-S-PLATFORM = IF
        DROP AT-OAUTH-PROFILE-S-PLATFORM EXIT
    THEN
    OAUTH2-RESOURCE-METADATA-STATUS-VALID? IF
        AT-OAUTH-PROFILE-S-RESOURCE-METADATA
    ELSE
        AT-OAUTH-PROFILE-S-INTERNAL
    THEN ;

: _ATOH-METADATA>STATUS  ( parser-status -- profile-status )
    DUP OAUTH2-METADATA-S-CAPACITY = IF
        DROP AT-OAUTH-PROFILE-S-CAPACITY EXIT
    THEN
    DUP OAUTH2-METADATA-S-ALIAS = IF
        DROP AT-OAUTH-PROFILE-S-ALIAS EXIT
    THEN
    DUP OAUTH2-METADATA-S-INTERNAL = IF
        DROP AT-OAUTH-PROFILE-S-INTERNAL EXIT
    THEN
    DUP OAUTH2-METADATA-S-RANGE = IF
        DROP AT-OAUTH-PROFILE-S-RANGE EXIT
    THEN
    DUP OAUTH2-METADATA-S-PROTECTED = IF
        DROP AT-OAUTH-PROFILE-S-PROTECTED EXIT
    THEN
    DUP OAUTH2-METADATA-S-PLATFORM = IF
        DROP AT-OAUTH-PROFILE-S-PLATFORM EXIT
    THEN
    OAUTH2-METADATA-STATUS-VALID? IF
        AT-OAUTH-PROFILE-S-AUTHORIZATION-SERVER
    ELSE
        AT-OAUTH-PROFILE-S-INTERNAL
    THEN ;

\ =====================================================================
\  Parse and profile transitions
\ =====================================================================

: _ATOH-PARSE-RESOURCE
  ( resource workspace profile body-a body-u -- profile-status )
    3 PICK
    4 PICK _ATOH.PARSER
    OAUTH2-RESOURCE-METADATA-PARSE
    DUP OAUTH2-RESOURCE-METADATA-S-OK <> IF
        _ATOH-RMETA>STATUS
        >R 2DROP DROP R> EXIT
    THEN
    DROP
    1 PICK
    1 PICK AT-OAUTH-PROFILE-RESOURCE!
    >R 2DROP DROP R> ;

: _ATOH-PARSE-AUTHORIZATION-SERVER
  ( resource workspace profile body-a body-u -- profile-status )
    3 PICK
    4 PICK _ATOH.PARSER
    OAUTH2-METADATA-PARSE
    DUP OAUTH2-METADATA-S-OK <> IF
        _ATOH-METADATA>STATUS
        >R 2DROP DROP R> EXIT
    THEN
    DROP
    1 PICK
    1 PICK AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!
    >R 2DROP DROP R> ;

: AT-OAUTH-HRES-RESOURCE!
  ( resource workspace profile -- profile-status )
    2 PICK 2 PICK 2 PICK _ATOH-GEOMETRY
    ?DUP IF
        >R 2DROP DROP R> EXIT
    THEN
    ['] AT-OAUTH-PROFILE-RESOURCE-METADATA-TARGET@
        _ATOH-PREPARE
    ?DUP IF
        >R 2DROP 2DROP DROP R> EXIT
    THEN
    ['] _ATOH-PARSE-RESOURCE _ATOH-CALL-CLEAN ;

: AT-OAUTH-HRES-AUTHORIZATION-SERVER!
  ( resource workspace profile -- profile-status )
    2 PICK 2 PICK 2 PICK _ATOH-GEOMETRY
    ?DUP IF
        >R 2DROP DROP R> EXIT
    THEN
    ['] AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-METADATA-TARGET@
        _ATOH-PREPARE
    ?DUP IF
        >R 2DROP 2DROP DROP R> EXIT
    THEN
    ['] _ATOH-PARSE-AUTHORIZATION-SERVER _ATOH-CALL-CLEAN ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _ATOH-GEOMETRY-ABORT  ( -- )
    ." AT OAuth HRES workspace geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _ATOH-GEOMETRY-ABORT
[THEN]

OAUTH2-RESOURCE-METADATA-SIZE _ATOH-RESULT-SIZE > [IF]
    _ATOH-GEOMETRY-ABORT
[THEN]

OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE _ATOH-PARSER-SIZE > [IF]
    _ATOH-GEOMETRY-ABORT
[THEN]

_ATOH-PARSER-OFF 7 AND [IF]
    _ATOH-GEOMETRY-ABORT
[THEN]
