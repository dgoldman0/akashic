\ =====================================================================
\  resource.f - Common resource URI helpers
\ =====================================================================

PROVIDED akashic-interop-resource

REQUIRE value.f
REQUIRE ../runtime/resource-ref.f
REQUIRE ../concurrency/guard.f

0 CONSTANT IRES-S-OK
1 CONSTANT IRES-S-INVALID
2 CONSTANT IRES-S-TYPE
3 CONSTANT IRES-S-NOMEM

: _IRES-OWNED-RESOURCE!  ( data length value -- )
    DUP CV-FREE >R
    CV-T-RESOURCE R@ CV.TYPE !
    CV-F-OWNED R@ CV.FLAGS !
    OVER R@ CV.DATA !
    R> CV.LEN !
    DROP ;

: IRES-VFS-PATH  ( uri-a uri-u -- path-a path-u flag )
    OVER 0= IF 2DROP 0 0 0 EXIT THEN
    DUP 4 < IF 2DROP 0 0 0 EXIT THEN
    OVER C@ [CHAR] v =
    2 PICK 1+ C@ [CHAR] f = AND
    2 PICK 2 + C@ [CHAR] s = AND
    2 PICK 3 + C@ [CHAR] : = AND 0= IF
        2DROP 0 0 0 EXIT
    THEN
    4 /STRING -1 ;

VARIABLE _IRV-A
VARIABLE _IRV-U
VARIABLE _IRV-V
VARIABLE _IRV-P

: IRES-VFS!  ( path-a path-u value -- ior )
    _IRV-V ! _IRV-U ! _IRV-A !
    _IRV-V @ 0= _IRV-A @ 0= OR IF IRES-S-INVALID EXIT THEN
    _IRV-U @ 4 + ALLOCATE
    DUP IF 2DROP IRES-S-NOMEM EXIT THEN
    DROP DUP _IRV-P !
    [CHAR] v OVER C! [CHAR] f OVER 1+ C!
    [CHAR] s OVER 2 + C! [CHAR] : OVER 3 + C!
    _IRV-A @ OVER 4 + _IRV-U @ CMOVE DROP
    _IRV-P @ _IRV-U @ 4 + _IRV-V @ _IRES-OWNED-RESOURCE!
    IRES-S-OK ;

\ ---------------------------------------------------------------------
\ Stable semantic resource URI
\ ---------------------------------------------------------------------
\ The canonical wire form is always:
\
\   akashic:resource:<64 lowercase hex RID>?revision=<unsigned decimal>
\
\ Keeping CV-T-RESOURCE textual preserves the existing JSON and MCP ABI.
\ `vfs:` remains a separate legacy/backing-locator form and is never
\ accepted by this parser as a semantic RREF.

17 CONSTANT IRES-RREF-PREFIX-U
64 CONSTANT IRES-RREF-ID-U
10 CONSTANT IRES-RREF-REV-PREFIX-U
92 CONSTANT IRES-RREF-URI-MIN
110 CONSTANT IRES-RREF-URI-MAX

: _IRES-NIBBLE>HEX  ( n -- c )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] a + THEN ;

: _IRES-HEX>NIBBLE  ( c -- n flag )
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND IF
        [CHAR] 0 - -1 EXIT
    THEN
    DUP [CHAR] a >= OVER [CHAR] f <= AND IF
        [CHAR] a - 10 + -1 EXIT
    THEN
    DROP 0 0 ;

VARIABLE _IRRF-REF
VARIABLE _IRRF-V
VARIABLE _IRRF-BUF
VARIABLE _IRRF-DA
VARIABLE _IRRF-DU

: _IRES-UDEC!  ( unsigned destination -- length )
    _IRRF-DA ! 0 _IRRF-DU !
    BEGIN
        DUP 10 MOD [CHAR] 0 +
            _IRRF-DA @ _IRRF-DU @ + C!
        1 _IRRF-DU +!
        10 /
        DUP 0=
    UNTIL
    DROP
    \ Digits were emitted least-significant first; reverse in place.  This
    \ uses only the caller's URI allocation, never NUM>STR's static buffer.
    _IRRF-DU @ 2 / 0 ?DO
        _IRRF-DA @ I +
        _IRRF-DA @ _IRRF-DU @ 1- I - +
        2DUP C@ SWAP C@ 2 PICK C! ROT C! DROP
    LOOP
    _IRRF-DU @ ;

: IRES-RREF!  ( reference value -- status )
    _IRRF-V ! _IRRF-REF !
    _IRRF-V @ 0= _IRRF-REF @ RREF-VALID? 0= OR IF
        IRES-S-INVALID EXIT
    THEN
    IRES-RREF-URI-MAX ALLOCATE DUP IF
        2DROP IRES-S-NOMEM EXIT
    THEN
    DROP DUP _IRRF-BUF ! IRES-RREF-URI-MAX 0 FILL
    S" akashic:resource:" DROP
        _IRRF-BUF @ IRES-RREF-PREFIX-U CMOVE
    RID-SIZE 0 ?DO
        _IRRF-REF @ RREF.ID I + C@
        DUP 4 RSHIFT _IRES-NIBBLE>HEX
            _IRRF-BUF @ I 2 * IRES-RREF-PREFIX-U + + C!
        15 AND _IRES-NIBBLE>HEX
            _IRRF-BUF @ I 2 * IRES-RREF-PREFIX-U 1+ + + C!
    LOOP
    S" ?revision=" DROP
        _IRRF-BUF @ IRES-RREF-PREFIX-U IRES-RREF-ID-U + +
        IRES-RREF-REV-PREFIX-U CMOVE
    _IRRF-REF @ RREF.REVISION @
        _IRRF-BUF @ IRES-RREF-PREFIX-U IRES-RREF-ID-U +
            IRES-RREF-REV-PREFIX-U + +
        _IRES-UDEC! _IRRF-DU !
    _IRRF-BUF @
        IRES-RREF-PREFIX-U IRES-RREF-ID-U +
        IRES-RREF-REV-PREFIX-U + _IRRF-DU @ +
        _IRRF-V @ _IRES-OWNED-RESOURCE!
    IRES-S-OK ;

VARIABLE _IRRD-A
VARIABLE _IRRD-U
VARIABLE _IRRD-N
VARIABLE _IRRD-D

: _IRES-DECIMAL  ( addr len -- n flag )
    _IRRD-U ! _IRRD-A !
    _IRRD-U @ DUP 0= SWAP 19 > OR IF 0 0 EXIT THEN
    _IRRD-U @ 1 > _IRRD-A @ C@ [CHAR] 0 = AND IF 0 0 EXIT THEN
    0 _IRRD-N !
    _IRRD-U @ 0 ?DO
        _IRRD-A @ I + C@ DUP [CHAR] 0 < OVER [CHAR] 9 > OR IF
            DROP 0 0 UNLOOP EXIT
        THEN
        [CHAR] 0 - DUP _IRRD-D !
        0x7FFFFFFFFFFFFFFF _IRRD-D @ - 10 /
            _IRRD-N @ < IF DROP 0 0 UNLOOP EXIT THEN
        _IRRD-N @ 10 * + _IRRD-N !
    LOOP
    _IRRD-N @ -1 ;

VARIABLE _IRRP-A
VARIABLE _IRRP-U
VARIABLE _IRRP-D
VARIABLE _IRRP-HI
VARIABLE _IRRP-LO

: _IRES-RREF-PARSE-INTO  ( uri-a uri-u destination -- status )
    _IRRP-D ! _IRRP-U ! _IRRP-A !
    _IRRP-D @ RREF-INIT
    _IRRP-A @ 0= IF IRES-S-INVALID EXIT THEN
    _IRRP-U @ IRES-RREF-URI-MIN <
    _IRRP-U @ IRES-RREF-URI-MAX > OR IF IRES-S-INVALID EXIT THEN
    _IRRP-A @ IRES-RREF-PREFIX-U
        S" akashic:resource:" STR-STR= 0= IF IRES-S-INVALID EXIT THEN
    _IRRP-A @ IRES-RREF-PREFIX-U IRES-RREF-ID-U + +
        IRES-RREF-REV-PREFIX-U S" ?revision=" STR-STR= 0= IF
        IRES-S-INVALID EXIT
    THEN
    RID-SIZE 0 ?DO
        _IRRP-A @ IRES-RREF-PREFIX-U + I 2 * + C@
            _IRES-HEX>NIBBLE 0= IF DROP IRES-S-INVALID UNLOOP EXIT THEN
            _IRRP-HI !
        _IRRP-A @ IRES-RREF-PREFIX-U + I 2 * 1+ + C@
            _IRES-HEX>NIBBLE 0= IF DROP IRES-S-INVALID UNLOOP EXIT THEN
            _IRRP-LO !
        _IRRP-HI @ 4 LSHIFT _IRRP-LO @ OR
            _IRRP-D @ RREF.ID I + C!
    LOOP
    _IRRP-A @ IRES-RREF-PREFIX-U IRES-RREF-ID-U +
        IRES-RREF-REV-PREFIX-U + +
    _IRRP-U @ IRES-RREF-PREFIX-U IRES-RREF-ID-U +
        IRES-RREF-REV-PREFIX-U + -
    _IRES-DECIMAL 0= IF DROP IRES-S-INVALID EXIT THEN
    _IRRP-D @ RREF.REVISION !
    _IRRP-D @ RREF-VALID? IF IRES-S-OK ELSE IRES-S-INVALID THEN ;

VARIABLE _IRRPA-A
VARIABLE _IRRPA-U
VARIABLE _IRRPA-D
VARIABLE _IRRPA-T

: IRES-RREF-PARSE  ( uri-a uri-u destination -- status )
    _IRRPA-D ! _IRRPA-U ! _IRRPA-A !
    _IRRPA-D @ 0= IF IRES-S-INVALID EXIT THEN
    _IRRPA-A @ 0= IF _IRRPA-D @ RREF-INIT IRES-S-INVALID EXIT THEN
    RREF-SIZE ALLOCATE DUP IF
        2DROP _IRRPA-D @ RREF-INIT IRES-S-NOMEM EXIT
    THEN
    DROP _IRRPA-T !
    _IRRPA-A @ _IRRPA-U @ _IRRPA-T @ _IRES-RREF-PARSE-INTO DUP
    IRES-S-OK = IF
        DROP _IRRPA-T @ _IRRPA-D @ RREF-COPY DROP IRES-S-OK
    ELSE
        _IRRPA-D @ RREF-INIT
    THEN
    _IRRPA-T @ RREF-SIZE 0 FILL _IRRPA-T @ FREE ;

VARIABLE _IRRAT-V
VARIABLE _IRRAT-D

: IRES-RREF@  ( value destination -- status )
    _IRRAT-D ! _IRRAT-V !
    _IRRAT-D @ 0= IF IRES-S-INVALID EXIT THEN
    _IRRAT-V @ 0= IF _IRRAT-D @ RREF-INIT IRES-S-INVALID EXIT THEN
    _IRRAT-V @ CV-TYPE@ CV-T-RESOURCE <> IF
        _IRRAT-D @ RREF-INIT IRES-S-TYPE EXIT
    THEN
    _IRRAT-V @ CV-DATA@ DUP 0= IF
        DROP _IRRAT-D @ RREF-INIT IRES-S-INVALID EXIT
    THEN
    _IRRAT-V @ CV-LEN@
        _IRRAT-D @ IRES-RREF-PARSE ;

\ URI constructors/parsers above use bounded module scratch.  Public callers
\ need no ambient lock: one recursive cross-core guard protects both the
\ semantic RREF form and the legacy VFS constructor.  Pure prefix inspection
\ in IRES-VFS-PATH has no shared state and remains lock-free.
' IRES-VFS!        CONSTANT _IRES-VFS-XT
' IRES-RREF!       CONSTANT _IRES-RREF-STORE-XT
' IRES-RREF-PARSE  CONSTANT _IRES-RREF-PARSE-XT
' IRES-RREF@       CONSTANT _IRES-RREF-FETCH-XT

GUARD _IRES-GUARD

: IRES-VFS!  ( path-a path-u value -- ior )
    _IRES-VFS-XT _IRES-GUARD WITH-GUARD ;
: IRES-RREF!  ( reference value -- status )
    _IRES-RREF-STORE-XT _IRES-GUARD WITH-GUARD ;
: IRES-RREF-PARSE  ( uri-a uri-u destination -- status )
    _IRES-RREF-PARSE-XT _IRES-GUARD WITH-GUARD ;
: IRES-RREF@  ( value destination -- status )
    _IRES-RREF-FETCH-XT _IRES-GUARD WITH-GUARD ;
