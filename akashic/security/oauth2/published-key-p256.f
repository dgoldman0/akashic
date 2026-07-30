\ =====================================================================
\  published-key-p256.f - Published OAuth P-256 key ownership
\ =====================================================================
\  This state-free composition selects the authenticated local client
\  identity from one complete checked public P-256 JWK Set, compares both
\  its public point and RFC 7638 thumbprint with durable ownership, then
\  resolves a distinct DPoP identity before invoking application code.
\
\  Client and DPoP credential-vault borrows are strictly sequential.  The
\  final callback runs only after both private-record borrows have returned
\  and been wiped.  This module owns no client metadata, provider profile,
\  HTTP, AT Protocol, token, session, or application state.
\
\  Public API:
\    OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE
\    OAUTH2-P256-PUBLISHED-WORKSPACE-CLEAR
\    OAUTH2-P256-PUBLISHED-STATUS-VALID?
\    OAUTH2-P256-PUBLISHED-WITH
\      ( jwks-a jwks-u binding-a binding-u vault callback context
\        workspace -- callback-result status )
\
\  Application callback ABI:
\      ( kid-a kid-u client-public-a client-thumbprint-a
\        dpop-public-a dpop-thumbprint-a context -- callback-result )
\ =====================================================================

\ KDOS module identities are bounded to 23 bytes.
PROVIDED akashic-oauth2-p256-pub

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../credential-vault.f
REQUIRE ../jose/jwk-set-p256.f
REQUIRE key-p256.f

\ =====================================================================
\  Public status vocabulary
\ =====================================================================

0  CONSTANT OAUTH2-P256-PUBLISHED-S-OK
1  CONSTANT OAUTH2-P256-PUBLISHED-S-INVALID
2  CONSTANT OAUTH2-P256-PUBLISHED-S-CAPACITY
3  CONSTANT OAUTH2-P256-PUBLISHED-S-ALIAS
4  CONSTANT OAUTH2-P256-PUBLISHED-S-BINDING
5  CONSTANT OAUTH2-P256-PUBLISHED-S-JWKS
6  CONSTANT OAUTH2-P256-PUBLISHED-S-NOT-FOUND
7  CONSTANT OAUTH2-P256-PUBLISHED-S-ABSENT
8  CONSTANT OAUTH2-P256-PUBLISHED-S-REVOKED
9  CONSTANT OAUTH2-P256-PUBLISHED-S-CONFLICT
10 CONSTANT OAUTH2-P256-PUBLISHED-S-BUSY
11 CONSTANT OAUTH2-P256-PUBLISHED-S-LOCKED
12 CONSTANT OAUTH2-P256-PUBLISHED-S-ENTROPY
13 CONSTANT OAUTH2-P256-PUBLISHED-S-CRYPTO
14 CONSTANT OAUTH2-P256-PUBLISHED-S-AUTH
15 CONSTANT OAUTH2-P256-PUBLISHED-S-CORRUPT
16 CONSTANT OAUTH2-P256-PUBLISHED-S-UNSUPPORTED
17 CONSTANT OAUTH2-P256-PUBLISHED-S-IO
18 CONSTANT OAUTH2-P256-PUBLISHED-S-RECOVERY
19 CONSTANT OAUTH2-P256-PUBLISHED-S-ROLLBACK
20 CONSTANT OAUTH2-P256-PUBLISHED-S-FORMAT
21 CONSTANT OAUTH2-P256-PUBLISHED-S-KEY
22 CONSTANT OAUTH2-P256-PUBLISHED-S-MISMATCH
23 CONSTANT OAUTH2-P256-PUBLISHED-S-DISTINCT
24 CONSTANT OAUTH2-P256-PUBLISHED-S-CALLBACK
25 CONSTANT OAUTH2-P256-PUBLISHED-S-INTERNAL
26 CONSTANT OAUTH2-P256-PUBLISHED-S-RANGE
27 CONSTANT OAUTH2-P256-PUBLISHED-S-PROTECTED
28 CONSTANT OAUTH2-P256-PUBLISHED-S-PLATFORM

: OAUTH2-P256-PUBLISHED-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-P256-PUBLISHED-S-OK >=
    SWAP OAUTH2-P256-PUBLISHED-S-PLATFORM <= AND ;

\ =====================================================================
\  Fixed caller-owned workspace
\ =====================================================================

 0 CONSTANT _O2PPW-JWKS-A
 8 CONSTANT _O2PPW-JWKS-U
16 CONSTANT _O2PPW-BINDING-A
24 CONSTANT _O2PPW-BINDING-U
32 CONSTANT _O2PPW-VAULT
40 CONSTANT _O2PPW-CALLBACK
48 CONSTANT _O2PPW-CONTEXT
56 CONSTANT _O2PPW-CALLBACK-RESULT
64 CONSTANT _O2PPW-APPLICATION-DEPTH
72 CONSTANT _O2PPW-CLIENT-KID-U

80  CONSTANT _O2PPW-CLIENT-KID-OFF
336 CONSTANT _O2PPW-CLIENT-PUBLIC-OFF
408 CONSTANT _O2PPW-CLIENT-THUMBPRINT-OFF
440 CONSTANT _O2PPW-DPOP-PUBLIC-OFF
512 CONSTANT _O2PPW-DPOP-THUMBPRINT-OFF
544 CONSTANT _O2PPW-SELECTED-PUBLIC-OFF
616 CONSTANT _O2PPW-SELECTED-THUMBPRINT-OFF
648 CONSTANT _O2PPW-OWNER-OFF
18528 CONSTANT _O2PPW-JWK-OFF
58056 CONSTANT OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE

: _O2PPW.JWKS-A  ( workspace -- field ) _O2PPW-JWKS-A + ;
: _O2PPW.JWKS-U  ( workspace -- field ) _O2PPW-JWKS-U + ;
: _O2PPW.BINDING-A  ( workspace -- field ) _O2PPW-BINDING-A + ;
: _O2PPW.BINDING-U  ( workspace -- field ) _O2PPW-BINDING-U + ;
: _O2PPW.VAULT  ( workspace -- field ) _O2PPW-VAULT + ;
: _O2PPW.CALLBACK  ( workspace -- field ) _O2PPW-CALLBACK + ;
: _O2PPW.CONTEXT  ( workspace -- field ) _O2PPW-CONTEXT + ;
: _O2PPW.CALLBACK-RESULT
  ( workspace -- field )
    _O2PPW-CALLBACK-RESULT + ;
: _O2PPW.APPLICATION-DEPTH
  ( workspace -- field )
    _O2PPW-APPLICATION-DEPTH + ;
: _O2PPW.CLIENT-KID-U
  ( workspace -- field )
    _O2PPW-CLIENT-KID-U + ;

: _O2PPW.CLIENT-KID  ( workspace -- address )
    _O2PPW-CLIENT-KID-OFF + ;
: _O2PPW.CLIENT-PUBLIC  ( workspace -- address )
    _O2PPW-CLIENT-PUBLIC-OFF + ;
: _O2PPW.CLIENT-THUMBPRINT  ( workspace -- address )
    _O2PPW-CLIENT-THUMBPRINT-OFF + ;
: _O2PPW.DPOP-PUBLIC  ( workspace -- address )
    _O2PPW-DPOP-PUBLIC-OFF + ;
: _O2PPW.DPOP-THUMBPRINT  ( workspace -- address )
    _O2PPW-DPOP-THUMBPRINT-OFF + ;
: _O2PPW.SELECTED-PUBLIC  ( workspace -- address )
    _O2PPW-SELECTED-PUBLIC-OFF + ;
: _O2PPW.SELECTED-THUMBPRINT  ( workspace -- address )
    _O2PPW-SELECTED-THUMBPRINT-OFF + ;
: _O2PPW.OWNER  ( workspace -- child-workspace )
    _O2PPW-OWNER-OFF + ;
: _O2PPW.JWK  ( workspace -- child-workspace )
    _O2PPW-JWK-OFF + ;

: _O2PP-WIPE  ( workspace -- )
    OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Small stack and byte helpers
\ =====================================================================

: _O2PP-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _O2PP-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;
: _O2PP-DROP7  ( seven-values -- ) 2DROP 2DROP 2DROP DROP ;
: _O2PP-DROP8  ( eight-values -- ) 2DROP 2DROP 2DROP 2DROP ;

: _O2PP-8DUP  ( eight-values -- the-same-eight-values twice )
    7 PICK 7 PICK 7 PICK 7 PICK
    7 PICK 7 PICK 7 PICK 7 PICK ;

: _O2PP-RETURN8  ( eight-values status -- status )
    >R _O2PP-DROP8 R> ;

: _O2PP-BYTES=  ( first-a first-u second-a second-u -- flag )
    COMPARE 0= ;

\ =====================================================================
\  Explicit subordinate status mappings
\ =====================================================================

: _O2PP-JWK-SPAN>STATUS  ( jwk-status -- status )
    CASE
        JOSE-JWK-P256-S-OK OF
            OAUTH2-P256-PUBLISHED-S-OK
        ENDOF
        JOSE-JWK-P256-S-INVALID OF
            OAUTH2-P256-PUBLISHED-S-INVALID
        ENDOF
        JOSE-JWK-P256-S-ALIAS OF
            OAUTH2-P256-PUBLISHED-S-ALIAS
        ENDOF
        JOSE-JWK-P256-S-CRYPTO OF
            OAUTH2-P256-PUBLISHED-S-CRYPTO
        ENDOF
        JOSE-JWK-P256-S-RANGE OF
            OAUTH2-P256-PUBLISHED-S-RANGE
        ENDOF
        JOSE-JWK-P256-S-PROTECTED OF
            OAUTH2-P256-PUBLISHED-S-PROTECTED
        ENDOF
        JOSE-JWK-P256-S-PLATFORM OF
            OAUTH2-P256-PUBLISHED-S-PLATFORM
        ENDOF
        OAUTH2-P256-PUBLISHED-S-PLATFORM SWAP
    ENDCASE ;

: _O2PP-CVAULT>STATUS  ( vault-status -- status )
    CASE
        CVAULT-S-OK OF OAUTH2-P256-PUBLISHED-S-OK ENDOF
        CVAULT-S-INVALID OF OAUTH2-P256-PUBLISHED-S-INVALID ENDOF
        CVAULT-S-BUSY OF OAUTH2-P256-PUBLISHED-S-BUSY ENDOF
        CVAULT-S-RANGE OF OAUTH2-P256-PUBLISHED-S-RANGE ENDOF
        CVAULT-S-PROTECTED OF
            OAUTH2-P256-PUBLISHED-S-PROTECTED
        ENDOF
        CVAULT-S-PLATFORM OF
            OAUTH2-P256-PUBLISHED-S-PLATFORM
        ENDOF
        OAUTH2-P256-PUBLISHED-S-INTERNAL SWAP
    ENDCASE ;

: _O2PP-OWNER>STATUS  ( owner-status -- status )
    CASE
        OAUTH2-P256-KEY-S-OK OF
            OAUTH2-P256-PUBLISHED-S-OK
        ENDOF
        OAUTH2-P256-KEY-S-INVALID OF
            OAUTH2-P256-PUBLISHED-S-INTERNAL
        ENDOF
        OAUTH2-P256-KEY-S-CAPACITY OF
            OAUTH2-P256-PUBLISHED-S-CAPACITY
        ENDOF
        OAUTH2-P256-KEY-S-ALIAS OF
            OAUTH2-P256-PUBLISHED-S-ALIAS
        ENDOF
        OAUTH2-P256-KEY-S-STATE OF
            OAUTH2-P256-PUBLISHED-S-BINDING
        ENDOF
        OAUTH2-P256-KEY-S-ABSENT OF
            OAUTH2-P256-PUBLISHED-S-ABSENT
        ENDOF
        OAUTH2-P256-KEY-S-REVOKED OF
            OAUTH2-P256-PUBLISHED-S-REVOKED
        ENDOF
        OAUTH2-P256-KEY-S-CONFLICT OF
            OAUTH2-P256-PUBLISHED-S-CONFLICT
        ENDOF
        OAUTH2-P256-KEY-S-BUSY OF
            OAUTH2-P256-PUBLISHED-S-BUSY
        ENDOF
        OAUTH2-P256-KEY-S-CALLBACK OF
            OAUTH2-P256-PUBLISHED-S-INTERNAL
        ENDOF
        OAUTH2-P256-KEY-S-LOCKED OF
            OAUTH2-P256-PUBLISHED-S-LOCKED
        ENDOF
        OAUTH2-P256-KEY-S-ENTROPY OF
            OAUTH2-P256-PUBLISHED-S-ENTROPY
        ENDOF
        OAUTH2-P256-KEY-S-CRYPTO OF
            OAUTH2-P256-PUBLISHED-S-CRYPTO
        ENDOF
        OAUTH2-P256-KEY-S-AUTH OF
            OAUTH2-P256-PUBLISHED-S-AUTH
        ENDOF
        OAUTH2-P256-KEY-S-CORRUPT OF
            OAUTH2-P256-PUBLISHED-S-CORRUPT
        ENDOF
        OAUTH2-P256-KEY-S-UNSUPPORTED OF
            OAUTH2-P256-PUBLISHED-S-UNSUPPORTED
        ENDOF
        OAUTH2-P256-KEY-S-IO OF
            OAUTH2-P256-PUBLISHED-S-IO
        ENDOF
        OAUTH2-P256-KEY-S-RECOVERY OF
            OAUTH2-P256-PUBLISHED-S-RECOVERY
        ENDOF
        OAUTH2-P256-KEY-S-ROLLBACK OF
            OAUTH2-P256-PUBLISHED-S-ROLLBACK
        ENDOF
        OAUTH2-P256-KEY-S-FORMAT OF
            OAUTH2-P256-PUBLISHED-S-FORMAT
        ENDOF
        OAUTH2-P256-KEY-S-KEY OF
            OAUTH2-P256-PUBLISHED-S-KEY
        ENDOF
        OAUTH2-P256-KEY-S-MISMATCH OF
            OAUTH2-P256-PUBLISHED-S-MISMATCH
        ENDOF
        OAUTH2-P256-KEY-S-RANGE OF
            OAUTH2-P256-PUBLISHED-S-RANGE
        ENDOF
        OAUTH2-P256-KEY-S-PROTECTED OF
            OAUTH2-P256-PUBLISHED-S-PROTECTED
        ENDOF
        OAUTH2-P256-KEY-S-PLATFORM OF
            OAUTH2-P256-PUBLISHED-S-PLATFORM
        ENDOF
        OAUTH2-P256-KEY-S-INTERNAL OF
            OAUTH2-P256-PUBLISHED-S-INTERNAL
        ENDOF
        OAUTH2-P256-PUBLISHED-S-INTERNAL SWAP
    ENDCASE ;

: _O2PP-JWK>STATUS  ( jwk-set-status -- status )
    CASE
        JOSE-JWK-SET-P256-S-OK OF
            OAUTH2-P256-PUBLISHED-S-OK
        ENDOF
        JOSE-JWK-SET-P256-S-INVALID OF
            OAUTH2-P256-PUBLISHED-S-INTERNAL
        ENDOF
        JOSE-JWK-SET-P256-S-CAPACITY OF
            OAUTH2-P256-PUBLISHED-S-CAPACITY
        ENDOF
        JOSE-JWK-SET-P256-S-ALIAS OF
            OAUTH2-P256-PUBLISHED-S-ALIAS
        ENDOF
        JOSE-JWK-SET-P256-S-JSON OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-MISSING OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-TYPE OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-EMPTY OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-SENSITIVE OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-UNSUPPORTED OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-KEY OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-DUPLICATE OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-USE OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-ALGORITHM OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-KEY-OPS OF
            OAUTH2-P256-PUBLISHED-S-JWKS
        ENDOF
        JOSE-JWK-SET-P256-S-NOT-FOUND OF
            OAUTH2-P256-PUBLISHED-S-NOT-FOUND
        ENDOF
        JOSE-JWK-SET-P256-S-CRYPTO OF
            OAUTH2-P256-PUBLISHED-S-CRYPTO
        ENDOF
        JOSE-JWK-SET-P256-S-INTERNAL OF
            OAUTH2-P256-PUBLISHED-S-INTERNAL
        ENDOF
        JOSE-JWK-SET-P256-S-RANGE OF
            OAUTH2-P256-PUBLISHED-S-RANGE
        ENDOF
        JOSE-JWK-SET-P256-S-PROTECTED OF
            OAUTH2-P256-PUBLISHED-S-PROTECTED
        ENDOF
        JOSE-JWK-SET-P256-S-PLATFORM OF
            OAUTH2-P256-PUBLISHED-S-PLATFORM
        ENDOF
        OAUTH2-P256-PUBLISHED-S-INTERNAL SWAP
    ENDCASE ;

\ =====================================================================
\  Caller-memory and vault-external admission
\ =====================================================================

: _O2PP-EXTERNAL-STATUS  ( address length vault -- status )
    CVAULT-EXTERNAL-SPAN-STATUS _O2PP-CVAULT>STATUS ;

: _O2PP-SPAN-STATUS  ( address length -- status )
    DUP 0< IF
        2DROP OAUTH2-P256-PUBLISHED-S-INVALID EXIT
    THEN
    DUP 0= IF
        2DROP OAUTH2-P256-PUBLISHED-S-OK EXIT
    THEN
    OVER 0= IF
        2DROP OAUTH2-P256-PUBLISHED-S-INVALID EXIT
    THEN
    JOSE-JWK-P256-CALLER-SPAN-STATUS
    _O2PP-JWK-SPAN>STATUS ;

: _O2PP-FIXED-STATUS  ( address size -- status )
    OVER 0= IF
        2DROP OAUTH2-P256-PUBLISHED-S-INVALID EXIT
    THEN
    OVER 7 AND IF
        2DROP OAUTH2-P256-PUBLISHED-S-INVALID EXIT
    THEN
    _O2PP-SPAN-STATUS ;

: _O2PP-GEOMETRY
  ( jwks-a jwks-u binding-a binding-u vault callback context workspace -- status )
    DUP OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE
    _O2PP-FIXED-STATUS
    ?DUP IF _O2PP-RETURN8 EXIT THEN

    6 PICK 0> 0= IF
        _O2PP-DROP8 OAUTH2-P256-PUBLISHED-S-INVALID EXIT
    THEN
    6 PICK JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES U> IF
        _O2PP-DROP8 OAUTH2-P256-PUBLISHED-S-CAPACITY EXIT
    THEN
    7 PICK 7 PICK _O2PP-SPAN-STATUS
    ?DUP IF _O2PP-RETURN8 EXIT THEN

    4 PICK OAUTH2-P256-KEY-BINDING-SIZE <> IF
        _O2PP-DROP8 OAUTH2-P256-PUBLISHED-S-BINDING EXIT
    THEN
    5 PICK 5 PICK _O2PP-FIXED-STATUS
    ?DUP IF _O2PP-RETURN8 EXIT THEN

    3 PICK CVAULT-SIZE _O2PP-SPAN-STATUS
    ?DUP IF _O2PP-RETURN8 EXIT THEN
    2 PICK 0= IF
        _O2PP-DROP8 OAUTH2-P256-PUBLISHED-S-INVALID EXIT
    THEN

    DUP OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE
    5 PICK _O2PP-EXTERNAL-STATUS
    ?DUP IF _O2PP-RETURN8 EXIT THEN
    7 PICK 7 PICK 5 PICK _O2PP-EXTERNAL-STATUS
    ?DUP IF _O2PP-RETURN8 EXIT THEN
    5 PICK 5 PICK 5 PICK _O2PP-EXTERNAL-STATUS
    ?DUP IF _O2PP-RETURN8 EXIT THEN

    7 PICK 7 PICK
    2 PICK OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _O2PP-DROP8 OAUTH2-P256-PUBLISHED-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK
    2 PICK OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _O2PP-DROP8 OAUTH2-P256-PUBLISHED-S-ALIAS EXIT
    THEN

    _O2PP-DROP8 OAUTH2-P256-PUBLISHED-S-OK ;

: OAUTH2-P256-PUBLISHED-WORKSPACE-CLEAR  ( workspace -- status )
    DUP OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE
    _O2PP-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _O2PP-WIPE
    OAUTH2-P256-PUBLISHED-S-OK ;

\ =====================================================================
\  Exact two-role binding admission
\ =====================================================================

: _O2PP-BINDING-PREP  ( workspace -- status )
    >R
    R@ _O2PPW.BINDING-A @
    R@ _O2PPW.BINDING-U @
    OAUTH2-P256-KEY-BINDING-PRESENCE@
    DUP OAUTH2-P256-KEY-S-INVALID = IF
        2DROP R> DROP
        OAUTH2-P256-PUBLISHED-S-BINDING EXIT
    THEN
    DUP OAUTH2-P256-KEY-S-OK <> IF
        _O2PP-OWNER>STATUS
        SWAP DROP
        R> DROP EXIT
    THEN
    DROP
    OAUTH2-P256-KEY-BINDING-F-CLIENT
    OAUTH2-P256-KEY-BINDING-F-DPOP OR
    <> IF
        R> DROP OAUTH2-P256-PUBLISHED-S-BINDING EXIT
    THEN
    R> DROP OAUTH2-P256-PUBLISHED-S-OK ;

\ =====================================================================
\  Checked JWK selection inside the client-key callback
\ =====================================================================

: _O2PP-SELECT-CALL
  ( source source-u kid kid-u public-output thumbprint-output workspace -- status )
    _O2PPW.JWK JOSE-JWK-SET-P256-SELECT ;

: _O2PP-SELECT-SAFE
  ( source source-u kid kid-u public-output thumbprint-output workspace -- status )
    ['] _O2PP-SELECT-CALL CATCH
    DUP IF
        DROP _O2PP-DROP7
        OAUTH2-P256-PUBLISHED-S-INTERNAL EXIT
    THEN
    DROP _O2PP-JWK>STATUS ;

: _O2PP-CLIENT-KEY-CALLBACK
  ( kid-a kid-u public-a thumbprint-a workspace -- callback-result )
    >R
    R@ _O2PPW.JWKS-A @
    R@ _O2PPW.JWKS-U @
    5 PICK 5 PICK
    R@ _O2PPW.SELECTED-PUBLIC
    R@ _O2PPW.SELECTED-THUMBPRINT
    R@ _O2PP-SELECT-SAFE
    ?DUP IF
        >R _O2PP-DROP4 R> R> DROP EXIT
    THEN

    1 PICK OAUTH2-P256-KEY-PUBLIC-SIZE
    R@ _O2PPW.SELECTED-PUBLIC
    OAUTH2-P256-KEY-PUBLIC-SIZE _O2PP-BYTES= 0= IF
        _O2PP-DROP4 R> DROP
        OAUTH2-P256-PUBLISHED-S-MISMATCH EXIT
    THEN
    DUP OAUTH2-P256-KEY-THUMBPRINT-SIZE
    R@ _O2PPW.SELECTED-THUMBPRINT
    OAUTH2-P256-KEY-THUMBPRINT-SIZE _O2PP-BYTES= 0= IF
        _O2PP-DROP4 R> DROP
        OAUTH2-P256-PUBLISHED-S-MISMATCH EXIT
    THEN

    3 PICK 0= 3 PICK 0> 0= OR
    3 PICK OAUTH2-P256-KEY-KID-CAPACITY U> OR IF
        _O2PP-DROP4 R> DROP
        OAUTH2-P256-PUBLISHED-S-INTERNAL EXIT
    THEN
    2 PICK R@ _O2PPW.CLIENT-KID-U !
    3 PICK R@ _O2PPW.CLIENT-KID
    R@ _O2PPW.CLIENT-KID-U @ MOVE
    1 PICK R@ _O2PPW.CLIENT-PUBLIC
    OAUTH2-P256-KEY-PUBLIC-SIZE MOVE
    DUP R@ _O2PPW.CLIENT-THUMBPRINT
    OAUTH2-P256-KEY-THUMBPRINT-SIZE MOVE

    _O2PP-DROP4 R> DROP
    OAUTH2-P256-PUBLISHED-S-OK ;

\ =====================================================================
\  DPoP identity distinctness inside the second owner callback
\ =====================================================================

: _O2PP-DPOP-KEY-CALLBACK
  ( kid-a kid-u public-a thumbprint-a workspace -- callback-result )
    >R
    3 PICK 0<> 3 PICK 0<> OR IF
        _O2PP-DROP4 R> DROP
        OAUTH2-P256-PUBLISHED-S-INTERNAL EXIT
    THEN

    1 PICK OAUTH2-P256-KEY-PUBLIC-SIZE
    R@ _O2PPW.CLIENT-PUBLIC
    OAUTH2-P256-KEY-PUBLIC-SIZE _O2PP-BYTES= IF
        _O2PP-DROP4 R> DROP
        OAUTH2-P256-PUBLISHED-S-DISTINCT EXIT
    THEN
    DUP OAUTH2-P256-KEY-THUMBPRINT-SIZE
    R@ _O2PPW.CLIENT-THUMBPRINT
    OAUTH2-P256-KEY-THUMBPRINT-SIZE _O2PP-BYTES= IF
        _O2PP-DROP4 R> DROP
        OAUTH2-P256-PUBLISHED-S-DISTINCT EXIT
    THEN

    1 PICK R@ _O2PPW.DPOP-PUBLIC
    OAUTH2-P256-KEY-PUBLIC-SIZE MOVE
    DUP R@ _O2PPW.DPOP-THUMBPRINT
    OAUTH2-P256-KEY-THUMBPRINT-SIZE MOVE
    _O2PP-DROP4 R> DROP
    OAUTH2-P256-PUBLISHED-S-OK ;

\ =====================================================================
\  Sequential owner calls with local throw containment
\ =====================================================================

: _O2PP-CLIENT-OWNER-CALL
  ( workspace -- callback-result owner-status )
    >R
    R@ _O2PPW.BINDING-A @
    R@ _O2PPW.BINDING-U @
    R@ _O2PPW.VAULT @
    ['] _O2PP-CLIENT-KEY-CALLBACK
    R@
    R@ _O2PPW.OWNER
    OAUTH2-P256-KEY-WITH-CLIENT
    R> DROP ;

: _O2PP-DPOP-OWNER-CALL
  ( workspace -- callback-result owner-status )
    >R
    R@ _O2PPW.BINDING-A @
    R@ _O2PPW.BINDING-U @
    R@ _O2PPW.VAULT @
    ['] _O2PP-DPOP-KEY-CALLBACK
    R@
    R@ _O2PPW.OWNER
    OAUTH2-P256-KEY-WITH-DPOP
    R> DROP ;

: _O2PP-CLIENT-OWNER-SAFE
  ( workspace -- callback-result status )
    ['] _O2PP-CLIENT-OWNER-CALL CATCH
    DUP IF
        2DROP 0 OAUTH2-P256-PUBLISHED-S-INTERNAL EXIT
    THEN
    DROP _O2PP-OWNER>STATUS ;

: _O2PP-DPOP-OWNER-SAFE
  ( workspace -- callback-result status )
    ['] _O2PP-DPOP-OWNER-CALL CATCH
    DUP IF
        2DROP 0 OAUTH2-P256-PUBLISHED-S-INTERNAL EXIT
    THEN
    DROP _O2PP-OWNER>STATUS ;

\ =====================================================================
\  Guarded application callback after both owner calls returned
\ =====================================================================

-19851 CONSTANT _O2PP-E-CALLBACK-STACK
0x4F32505043414C31 CONSTANT _O2PP-CALLBACK-GUARD

: _O2PP-APPLICATION-RUN  ( workspace -- callback-result )
    >R
    DEPTH R@ _O2PPW.APPLICATION-DEPTH !
    _O2PP-CALLBACK-GUARD
    R@ _O2PPW.CLIENT-KID
    R@ _O2PPW.CLIENT-KID-U @
    R@ _O2PPW.CLIENT-PUBLIC
    R@ _O2PPW.CLIENT-THUMBPRINT
    R@ _O2PPW.DPOP-PUBLIC
    R@ _O2PPW.DPOP-THUMBPRINT
    R@ _O2PPW.CONTEXT @
    R@ _O2PPW.CALLBACK @ EXECUTE
    DEPTH R@ _O2PPW.APPLICATION-DEPTH @ 2 + <> IF
        _O2PP-E-CALLBACK-STACK THROW
    THEN
    1 PICK _O2PP-CALLBACK-GUARD <> IF
        _O2PP-E-CALLBACK-STACK THROW
    THEN
    NIP R> DROP ;

: _O2PP-APPLICATION-SAFE
  ( workspace -- callback-result status )
    ['] _O2PP-APPLICATION-RUN CATCH
    DUP IF
        2DROP 0 OAUTH2-P256-PUBLISHED-S-CALLBACK
    ELSE
        DROP OAUTH2-P256-PUBLISHED-S-OK
    THEN ;

\ =====================================================================
\  Composition and mandatory cleanup
\ =====================================================================

: _O2PP-CLEAN-RESULT
  ( callback-result status workspace -- callback-result status )
    DUP _O2PP-WIPE DROP ;

: _O2PP-WITH-OP
  ( jwks-a jwks-u binding-a binding-u vault callback context workspace -- callback-result status )
    DUP >R
    R@ _O2PP-WIPE
    7 PICK R@ _O2PPW.JWKS-A !
    6 PICK R@ _O2PPW.JWKS-U !
    5 PICK R@ _O2PPW.BINDING-A !
    4 PICK R@ _O2PPW.BINDING-U !
    3 PICK R@ _O2PPW.VAULT !
    2 PICK R@ _O2PPW.CALLBACK !
    1 PICK R@ _O2PPW.CONTEXT !
    _O2PP-DROP8

    R@ _O2PP-BINDING-PREP
    ?DUP IF
        0 SWAP R> _O2PP-CLEAN-RESULT EXIT
    THEN

    R@ _O2PP-CLIENT-OWNER-SAFE
    DUP OAUTH2-P256-PUBLISHED-S-OK <> IF
        SWAP DROP
        0 SWAP
        R> _O2PP-CLEAN-RESULT EXIT
    THEN
    DROP
    DUP OAUTH2-P256-PUBLISHED-STATUS-VALID? 0= IF
        DROP 0 OAUTH2-P256-PUBLISHED-S-INTERNAL
        R> _O2PP-CLEAN-RESULT EXIT
    THEN
    ?DUP IF
        0 SWAP R> _O2PP-CLEAN-RESULT EXIT
    THEN

    R@ _O2PP-DPOP-OWNER-SAFE
    DUP OAUTH2-P256-PUBLISHED-S-OK <> IF
        SWAP DROP
        0 SWAP
        R> _O2PP-CLEAN-RESULT EXIT
    THEN
    DROP
    DUP OAUTH2-P256-PUBLISHED-STATUS-VALID? 0= IF
        DROP 0 OAUTH2-P256-PUBLISHED-S-INTERNAL
        R> _O2PP-CLEAN-RESULT EXIT
    THEN
    ?DUP IF
        0 SWAP R> _O2PP-CLEAN-RESULT EXIT
    THEN

    R@ _O2PP-APPLICATION-SAFE
    DUP OAUTH2-P256-PUBLISHED-S-OK <> IF
        R> _O2PP-CLEAN-RESULT EXIT
    THEN
    DROP
    R@ _O2PPW.CALLBACK-RESULT !
    R@ _O2PPW.CALLBACK-RESULT @
    OAUTH2-P256-PUBLISHED-S-OK
    R> _O2PP-CLEAN-RESULT ;

: _O2PP-WITH-CALL
  ( eight-values operation-xt -- callback-result status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _O2PP-WIPE
        _O2PP-DROP8
        R> DROP
        0 OAUTH2-P256-PUBLISHED-S-INTERNAL EXIT
    THEN
    DROP R> DROP ;

: OAUTH2-P256-PUBLISHED-WITH
  ( jwks-a jwks-u binding-a binding-u vault callback context workspace -- callback-result status )
    _O2PP-8DUP _O2PP-GEOMETRY
    ?DUP IF
        _O2PP-RETURN8 0 SWAP EXIT
    THEN
    ['] _O2PP-WITH-OP _O2PP-WITH-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _O2PP-GEOMETRY-ABORT  ( -- )
    ." OAuth2 published P-256 geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

OAUTH2-P256-KEY-KID-CAPACITY 256 <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

OAUTH2-P256-KEY-PUBLIC-SIZE 65 <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

OAUTH2-P256-KEY-THUMBPRINT-SIZE 32 <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

OAUTH2-P256-KEY-WORKSPACE-SIZE 17879 <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

JOSE-JWK-SET-P256-WORKSPACE-SIZE 39528 <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-CLIENT-KID-OFF 80 <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-CLIENT-PUBLIC-OFF
_O2PPW-CLIENT-KID-OFF OAUTH2-P256-KEY-KID-CAPACITY +
<> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-CLIENT-THUMBPRINT-OFF 7 AND [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-DPOP-THUMBPRINT-OFF 7 AND [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-SELECTED-THUMBPRINT-OFF 7 AND [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-OWNER-OFF 7 AND [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-JWK-OFF 7 AND [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-OWNER-OFF OAUTH2-P256-KEY-WORKSPACE-SIZE +
_O2PPW-JWK-OFF > [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]

_O2PPW-JWK-OFF JOSE-JWK-SET-P256-WORKSPACE-SIZE +
OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE <> [IF]
    _O2PP-GEOMETRY-ABORT
[THEN]
