\ =====================================================================
\  identity-hres.f - AT identity over generic HTTP resources
\ =====================================================================
\  This state-free adapter applies the AT identity HTTP profile to one
\  caller-owned HRES specification and submits one admitted HRES result to
\  the transport-neutral identity resolver.  It performs no DNS, HTTP, TLS,
\  retry, cache, credential, repository, or application work.
\ =====================================================================

PROVIDED akashic-atid-hres

REQUIRE ../net/http-resource.f
REQUIRE identity.f

: _ATID-HRES-REDIRECT-AUTHORITY
    ( current-target candidate-target context -- authority-status )
    DROP
    2DUP HTARGET-VALID? SWAP HTARGET-VALID? AND 0= IF
        2DROP ATID-S-INVALID EXIT
    THEN
    2DUP HTARGET-PORT@ 443 =
    SWAP HTARGET-PORT@ 443 = AND IF
        2DROP ATID-S-OK
    ELSE
        2DROP ATID-S-POLICY
    THEN ;

: ATID-HRES-SPEC-POLICY!  ( spec -- hres-status )
    >R
    200 299 R@ HRES-SPEC-SUCCESS-RANGE!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    HRES-MEDIA-IGNORED R@ HRES-SPEC-MEDIA-MODE!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    ATID-HTTP-REDIRECT-MAX R@ HRES-SPEC-REDIRECT-MAX!
    DUP HRES-S-OK <> IF R> DROP EXIT THEN DROP
    0 ['] _ATID-HRES-REDIRECT-AUTHORITY
    R> HRES-SPEC-REDIRECT-AUTHORITY! ;

: ATID-HRES-RESPONSE!  ( resource resolver -- atid-status )
    >R
    R@ ATID-HTTP-TARGET@
    DUP ATID-S-OK <> IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    OVER HRES-RESULT-VALID? 0= IF
        2DROP R> DROP ATID-S-HTTP EXIT
    THEN
    OVER HRES-REQUESTED-TARGET OVER HTARGET-EQUAL? 0= IF
        2DROP R> DROP ATID-S-HTTP EXIT
    THEN
    DROP >R
    R@ HRES-BODY@
    R@ HRES-HTTP-STATUS@
    R@ HRES-REDIRECT-COUNT@
    R@ HRES-EFFECTIVE-TARGET
    R> DROP
    R> ATID-HTTP-RESPONSE! ;
