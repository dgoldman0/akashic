\ =====================================================================
\  oauth-inline-hres.f - Acquired confidential inline AT OAuth client
\ =====================================================================
\  This state-free adapter binds one retained generic HRES result to the
\  configured AT OAuth client_id and then submits its admitted body to the
\  confidential inline deployment/key composition.
\
\  The caller continues to own the HRES lifecycle and response buffer.
\  This module performs no DNS, HTTP, TLS, deadline, lease, jwks_uri, PAR,
\  browser, token, session, XRPC, or Streams work.
\
\  Public API:
\    AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
\    AT-OAUTH-INLINE-HRES-WORKSPACE-CLEAR
\    AT-OAUTH-INLINE-HRES-SPEC-POLICY!
\    AT-OAUTH-INLINE-HRES-STATUS-VALID?
\    AT-OAUTH-INLINE-HRES-WITH
\      ( resource config profile vault callback context workspace
\        -- callback-result status )
\ =====================================================================

PROVIDED akashic-at-oauth-ihres

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../security/credential-vault.f
REQUIRE ../security/oauth2/client-config.f
REQUIRE oauth-hres.f
REQUIRE oauth-profile.f
REQUIRE oauth-deployment-inline.f

AT-OAUTH-INLINE-WORKSPACE-SIZE
    CONSTANT AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE

42 CONSTANT AT-OAUTH-INLINE-HRES-S-HTTP

: AT-OAUTH-INLINE-HRES-STATUS-VALID?  ( status -- flag )
    DUP AT-OAUTH-INLINE-STATUS-VALID?
    SWAP AT-OAUTH-INLINE-HRES-S-HTTP = OR ;

: AT-OAUTH-INLINE-HRES-WORKSPACE-CLEAR  ( workspace -- status )
    AT-OAUTH-INLINE-WORKSPACE-CLEAR ;

: AT-OAUTH-INLINE-HRES-SPEC-POLICY!  ( spec -- hres-status )
    AT-OAUTH-HRES-SPEC-POLICY! ;

\ =====================================================================
\  Admission and status helpers
\ =====================================================================

: _ATOIH-DROP7  ( seven-values -- )
    2DROP 2DROP 2DROP DROP ;

: _ATOIH-7DUP  ( seven-values -- the-same-seven-values twice )
    6 PICK 6 PICK 6 PICK 6 PICK
    6 PICK 6 PICK 6 PICK ;

: _ATOIH-RETURN7  ( seven-values status -- status )
    >R _ATOIH-DROP7 R> ;

: _ATOIH-RETURN7-FAIL
  ( seven-values status -- callback-result status )
    >R _ATOIH-DROP7 0 R> ;

: _ATOIH-RETURN7-PAIR
  ( seven-values callback-result status -- callback-result status )
    >R >R _ATOIH-DROP7 R> R> ;

: _ATOIH-CALLER>STATUS  ( caller-status -- status )
    CASE
        CALLER-SPAN-S-OK OF AT-OAUTH-INLINE-S-OK ENDOF
        CALLER-SPAN-S-RANGE OF AT-OAUTH-INLINE-S-RANGE ENDOF
        CALLER-SPAN-S-PROTECTED OF
            AT-OAUTH-INLINE-S-PROTECTED
        ENDOF
        CALLER-SPAN-S-PLATFORM OF AT-OAUTH-INLINE-S-PLATFORM ENDOF
        AT-OAUTH-INLINE-S-PLATFORM SWAP
    ENDCASE ;

: _ATOIH-CVAULT>STATUS  ( vault-status -- status )
    CASE
        CVAULT-S-OK OF AT-OAUTH-INLINE-S-OK ENDOF
        CVAULT-S-INVALID OF AT-OAUTH-INLINE-S-INVALID ENDOF
        CVAULT-S-BUSY OF AT-OAUTH-INLINE-S-BUSY ENDOF
        CVAULT-S-RANGE OF AT-OAUTH-INLINE-S-RANGE ENDOF
        CVAULT-S-PROTECTED OF AT-OAUTH-INLINE-S-PROTECTED ENDOF
        CVAULT-S-PLATFORM OF AT-OAUTH-INLINE-S-PLATFORM ENDOF
        AT-OAUTH-INLINE-S-INTERNAL SWAP
    ENDCASE ;

: _ATOIH-CONFIG>STATUS  ( config-status -- status )
    CASE
        OAUTH2-CLIENT-CONFIG-S-INVALID OF
            AT-OAUTH-INLINE-S-CONFIG
        ENDOF
        OAUTH2-CLIENT-CONFIG-S-RANGE OF
            AT-OAUTH-INLINE-S-RANGE
        ENDOF
        OAUTH2-CLIENT-CONFIG-S-PROTECTED OF
            AT-OAUTH-INLINE-S-PROTECTED
        ENDOF
        OAUTH2-CLIENT-CONFIG-S-PLATFORM OF
            AT-OAUTH-INLINE-S-PLATFORM
        ENDOF
        AT-OAUTH-INLINE-S-INTERNAL SWAP
    ENDCASE ;

: _ATOIH-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP AT-OAUTH-INLINE-S-INVALID EXIT THEN
    DUP 0= IF 2DROP AT-OAUTH-INLINE-S-OK EXIT THEN
    OVER 0= IF 2DROP AT-OAUTH-INLINE-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATOIH-CALLER>STATUS ;

: _ATOIH-FIXED-STATUS  ( address size -- status )
    OVER 0= IF 2DROP AT-OAUTH-INLINE-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP AT-OAUTH-INLINE-S-INVALID EXIT THEN
    _ATOIH-SPAN-STATUS ;

: _ATOIH-EXTERNAL-STATUS  ( address length vault -- status )
    CVAULT-EXTERNAL-SPAN-STATUS _ATOIH-CVAULT>STATUS ;

\ Stack on entry is resource, config, profile, vault, workspace, body span.
: _ATOIH-BODY-GEOMETRY
  ( resource config profile vault workspace body-a body-u -- status )
    2DUP _ATOIH-SPAN-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN

    2DUP 5 PICK _ATOIH-EXTERNAL-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN

    2DUP 8 PICK HTTP-RESOURCE-SIZE MSPAN-OVERLAP? IF
        AT-OAUTH-INLINE-S-ALIAS _ATOIH-RETURN7 EXIT
    THEN
    2DUP 7 PICK OAUTH2-CLIENT-CONFIG-SIZE MSPAN-OVERLAP? IF
        AT-OAUTH-INLINE-S-ALIAS _ATOIH-RETURN7 EXIT
    THEN
    2DUP 6 PICK AT-OAUTH-PROFILE-SIZE MSPAN-OVERLAP? IF
        AT-OAUTH-INLINE-S-ALIAS _ATOIH-RETURN7 EXIT
    THEN
    2DUP 4 PICK AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-INLINE-S-ALIAS _ATOIH-RETURN7 EXIT
    THEN
    AT-OAUTH-INLINE-S-OK _ATOIH-RETURN7 ;

: _ATOIH-GEOMETRY
  ( resource config profile vault callback context workspace -- status )
    6 PICK HTTP-RESOURCE-SIZE _ATOIH-SPAN-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    5 PICK OAUTH2-CLIENT-CONFIG-SIZE _ATOIH-FIXED-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    4 PICK AT-OAUTH-PROFILE-SIZE _ATOIH-FIXED-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    3 PICK CVAULT-SIZE _ATOIH-SPAN-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    DUP AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
    _ATOIH-FIXED-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    2 PICK 0= IF
        _ATOIH-DROP7 AT-OAUTH-INLINE-S-INVALID EXIT
    THEN

    6 PICK HTTP-RESOURCE-SIZE 5 PICK _ATOIH-EXTERNAL-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    5 PICK OAUTH2-CLIENT-CONFIG-SIZE
    5 PICK _ATOIH-EXTERNAL-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    4 PICK AT-OAUTH-PROFILE-SIZE 5 PICK
    _ATOIH-EXTERNAL-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN
    DUP AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
    5 PICK _ATOIH-EXTERNAL-STATUS
    ?DUP IF _ATOIH-RETURN7 EXIT THEN

    6 PICK HTTP-RESOURCE-SIZE
    7 PICK OAUTH2-CLIENT-CONFIG-SIZE MSPAN-OVERLAP? IF
        _ATOIH-DROP7 AT-OAUTH-INLINE-S-ALIAS EXIT
    THEN
    6 PICK HTTP-RESOURCE-SIZE
    6 PICK AT-OAUTH-PROFILE-SIZE MSPAN-OVERLAP? IF
        _ATOIH-DROP7 AT-OAUTH-INLINE-S-ALIAS EXIT
    THEN
    6 PICK HTTP-RESOURCE-SIZE
    2 PICK AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATOIH-DROP7 AT-OAUTH-INLINE-S-ALIAS EXIT
    THEN

    5 PICK OAUTH2-CLIENT-CONFIG-SIZE
    2 PICK AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATOIH-DROP7 AT-OAUTH-INLINE-S-ALIAS EXIT
    THEN
    4 PICK AT-OAUTH-PROFILE-SIZE
    2 PICK AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATOIH-DROP7 AT-OAUTH-INLINE-S-ALIAS EXIT
    THEN

    6 PICK HRES-VALID? 0= IF
        _ATOIH-DROP7 AT-OAUTH-INLINE-HRES-S-HTTP EXIT
    THEN

    6 PICK 6 PICK 6 PICK 6 PICK 4 PICK
    4 PICK HRES-BODY-STORAGE@
    _ATOIH-BODY-GEOMETRY
    ?DUP IF _ATOIH-RETURN7 EXIT THEN

    _ATOIH-DROP7 AT-OAUTH-INLINE-S-OK ;

\ =====================================================================
\  Exact Client ID resource binding
\ =====================================================================

: _ATOIH-ENVELOPE-STATUS  ( resource config -- status )
    DUP OAUTH2-CLIENT-CONFIG-CLIENT-ID@
    DUP OAUTH2-CLIENT-CONFIG-S-OK <> IF
        >R 2DROP 2DROP R> _ATOIH-CONFIG>STATUS EXIT
    THEN
    DROP
    2SWAP DROP -ROT
    AT-OAUTH-HRES-URI-ENVELOPE?
    IF
        AT-OAUTH-INLINE-S-OK
    ELSE
        AT-OAUTH-INLINE-HRES-S-HTTP
    THEN ;

\ =====================================================================
\  Inline composition and exception containment
\ =====================================================================

: _ATOIH-WITH-OP  \ ( resource config profile vault callback context workspace -- callback-result status )
    6 PICK 6 PICK _ATOIH-ENVELOPE-STATUS
    ?DUP IF _ATOIH-RETURN7-FAIL EXIT THEN

    6 PICK HRES-BODY@
    7 PICK 7 PICK 7 PICK 7 PICK 7 PICK 7 PICK
    AT-OAUTH-INLINE-WITH
    _ATOIH-RETURN7-PAIR ;

: _ATOIH-WITH-CALL  \ ( resource config profile vault callback context workspace operation-xt -- callback-result status )
    CATCH
    DUP IF
        DROP _ATOIH-DROP7
        0 AT-OAUTH-INLINE-S-INTERNAL EXIT
    THEN
    DROP ;

: AT-OAUTH-INLINE-HRES-WITH  \ ( resource config profile vault callback context workspace -- callback-result status )
    _ATOIH-7DUP _ATOIH-GEOMETRY
    ?DUP IF _ATOIH-RETURN7-FAIL EXIT THEN
    ['] _ATOIH-WITH-OP _ATOIH-WITH-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

1 CELLS 8 <> [IF]
    ." AT OAuth inline HRES cell geometry mismatch" CR ABORT
[THEN]

AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE 111928 <> [IF]
    ." AT OAuth inline HRES workspace geometry mismatch" CR ABORT
[THEN]
