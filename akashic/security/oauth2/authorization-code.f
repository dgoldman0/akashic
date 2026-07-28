\ =====================================================================
\  authorization-code.f - Caller-owned OAuth authorization transaction
\ =====================================================================
\  This generic module owns exactly one authorization-code attempt:
\
\    EMPTY -> PREPARED -> PAR-READY -> AWAITING
\                                      |       |
\                                      v       v
\                                  CODE-READY DENIED
\                                      |
\                                      v
\                                    SPENT
\
\  PREPARE generates a 256-bit state value from checked hardware entropy
\  and an independent 256-bit S256 PKCE verifier through oauth2/pkce.f.
\  The caller supplies an opaque configuration binding and the exact issuer
\  expected in an RFC 9207 authorization response.  No raw address is ever
\  retained in the transaction object, so a higher owner can protect and
\  serialize its complete fixed-size byte representation.
\
\  The separate operation workspace holds all transient source addresses,
\  parser state, decoded response fields, entropy, and PKCE scratch.  Every
\  admitted PREPARE or ACCEPT-CALLBACK path wipes that complete workspace.
\
\  The module owns no HTTP, browser, clock source, durable storage, issuer
\  discovery, token exchange, DPoP policy, AT Protocol, or Streams policy.
\  The caller serializes access to each object.
\ =====================================================================

PROVIDED akashic-oauth2-authcode

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../../net/form-urlencoded.f
REQUIRE ../../math/entropy.f
REQUIRE ../jose/base64url.f
REQUIRE pkce.f

\ =====================================================================
\  Public status, phase, policy, and capacity vocabulary
\ =====================================================================

0  CONSTANT O2CODE-S-OK
1  CONSTANT O2CODE-S-INVALID
2  CONSTANT O2CODE-S-CAPACITY
3  CONSTANT O2CODE-S-ALIAS
4  CONSTANT O2CODE-S-PHASE
5  CONSTANT O2CODE-S-BUSY
6  CONSTANT O2CODE-S-EXPIRED
7  CONSTANT O2CODE-S-OVERFLOW
8  CONSTANT O2CODE-S-ENCODING
9  CONSTANT O2CODE-S-DUPLICATE
10 CONSTANT O2CODE-S-MISSING
11 CONSTANT O2CODE-S-STATE
12 CONSTANT O2CODE-S-ISSUER
13 CONSTANT O2CODE-S-RESPONSE
14 CONSTANT O2CODE-S-DENIED
15 CONSTANT O2CODE-S-CALLBACK
16 CONSTANT O2CODE-S-ENTROPY
17 CONSTANT O2CODE-S-CRYPTO
18 CONSTANT O2CODE-S-RANGE
19 CONSTANT O2CODE-S-PROTECTED
20 CONSTANT O2CODE-S-PLATFORM
21 CONSTANT O2CODE-S-INTERNAL

: O2CODE-STATUS-VALID?  ( status -- flag )
    DUP O2CODE-S-OK >=
    SWAP O2CODE-S-INTERNAL <= AND ;

0 CONSTANT O2CODE-PHASE-EMPTY
1 CONSTANT O2CODE-PHASE-PREPARED
2 CONSTANT O2CODE-PHASE-PAR-READY
3 CONSTANT O2CODE-PHASE-AWAITING
4 CONSTANT O2CODE-PHASE-CODE-READY
5 CONSTANT O2CODE-PHASE-DENIED
6 CONSTANT O2CODE-PHASE-SPENT

0  CONSTANT O2CODE-ISSUER-OPTIONAL
-1 CONSTANT O2CODE-ISSUER-REQUIRED

256   CONSTANT O2CODE-BINDING-CAPACITY
2048  CONSTANT O2CODE-ISSUER-CAPACITY
4096  CONSTANT O2CODE-REQUEST-URI-CAPACITY
8192  CONSTANT O2CODE-CODE-CAPACITY
256   CONSTANT O2CODE-ERROR-CAPACITY
1024  CONSTANT O2CODE-ERROR-DESCRIPTION-CAPACITY
16384 CONSTANT O2CODE-CALLBACK-QUERY-CAPACITY

43 CONSTANT O2CODE-STATE-SIZE
43 CONSTANT O2CODE-VERIFIER-SIZE
43 CONSTANT O2CODE-CHALLENGE-SIZE

2147483647 CONSTANT O2CODE-MAX-PAR-EXPIRES-IN
-1 1 RSHIFT CONSTANT _O2C-CELL-MAX

\ =====================================================================
\  Address-free transaction object
\ =====================================================================

0x4F32434F44455458 CONSTANT _O2C-MAGIC-VALUE

 0 CONSTANT _O2C-MAGIC
 8 CONSTANT _O2C-PHASE
16 CONSTANT _O2C-BORROWED
24 CONSTANT _O2C-ISSUER-REQUIRED
32 CONSTANT _O2C-BINDING-U
40 CONSTANT _O2C-ISSUER-U
48 CONSTANT _O2C-REQUEST-URI-U
56 CONSTANT _O2C-DEADLINE
64 CONSTANT _O2C-CODE-U
72 CONSTANT _O2C-ERROR-U
80 CONSTANT _O2C-DESCRIPTION-U
88 CONSTANT _O2C-HEADER-SIZE

_O2C-HEADER-SIZE CONSTANT _O2C-BINDING-OFF
_O2C-BINDING-OFF O2CODE-BINDING-CAPACITY +
    CONSTANT _O2C-ISSUER-OFF
_O2C-ISSUER-OFF O2CODE-ISSUER-CAPACITY +
    CONSTANT _O2C-STATE-OFF
_O2C-STATE-OFF O2CODE-STATE-SIZE +
    CONSTANT _O2C-VERIFIER-OFF
_O2C-VERIFIER-OFF O2CODE-VERIFIER-SIZE +
    CONSTANT _O2C-CHALLENGE-OFF
_O2C-CHALLENGE-OFF O2CODE-CHALLENGE-SIZE +
    CONSTANT _O2C-REQUEST-URI-OFF
_O2C-REQUEST-URI-OFF O2CODE-REQUEST-URI-CAPACITY +
    CONSTANT _O2C-CODE-OFF
_O2C-CODE-OFF O2CODE-CODE-CAPACITY +
    CONSTANT _O2C-ERROR-OFF
_O2C-ERROR-OFF O2CODE-ERROR-CAPACITY +
    CONSTANT _O2C-DESCRIPTION-OFF
_O2C-DESCRIPTION-OFF O2CODE-ERROR-DESCRIPTION-CAPACITY +
7 + -8 AND CONSTANT O2CODE-TRANSACTION-SIZE

: _O2C.MAGIC            ( object -- address ) _O2C-MAGIC + ;
: _O2C.PHASE            ( object -- address ) _O2C-PHASE + ;
: _O2C.BORROWED         ( object -- address ) _O2C-BORROWED + ;
: _O2C.ISSUER-REQUIRED  ( object -- address )
    _O2C-ISSUER-REQUIRED + ;
: _O2C.BINDING-U        ( object -- address ) _O2C-BINDING-U + ;
: _O2C.ISSUER-U         ( object -- address ) _O2C-ISSUER-U + ;
: _O2C.REQUEST-URI-U    ( object -- address ) _O2C-REQUEST-URI-U + ;
: _O2C.DEADLINE         ( object -- address ) _O2C-DEADLINE + ;
: _O2C.CODE-U           ( object -- address ) _O2C-CODE-U + ;
: _O2C.ERROR-U          ( object -- address ) _O2C-ERROR-U + ;
: _O2C.DESCRIPTION-U    ( object -- address ) _O2C-DESCRIPTION-U + ;

: _O2C.BINDING          ( object -- address ) _O2C-BINDING-OFF + ;
: _O2C.ISSUER           ( object -- address ) _O2C-ISSUER-OFF + ;
: _O2C.STATE            ( object -- address ) _O2C-STATE-OFF + ;
: _O2C.VERIFIER         ( object -- address ) _O2C-VERIFIER-OFF + ;
: _O2C.CHALLENGE        ( object -- address ) _O2C-CHALLENGE-OFF + ;
: _O2C.REQUEST-URI      ( object -- address ) _O2C-REQUEST-URI-OFF + ;
: _O2C.CODE             ( object -- address ) _O2C-CODE-OFF + ;
: _O2C.ERROR            ( object -- address ) _O2C-ERROR-OFF + ;
: _O2C.DESCRIPTION      ( object -- address ) _O2C-DESCRIPTION-OFF + ;

\ =====================================================================
\  Caller-owned transient workspace
\ =====================================================================

32   CONSTANT _O2C-MAX-PARAMETERS
2048 CONSTANT _O2C-NAME-ARENA-CAPACITY
16   CONSTANT _O2C-NAME-DESCRIPTOR-SIZE

  0 CONSTANT _O2CW-OBJECT
  8 CONSTANT _O2CW-BINDING-A
 16 CONSTANT _O2CW-BINDING-U
 24 CONSTANT _O2CW-ISSUER-A
 32 CONSTANT _O2CW-ISSUER-U
 40 CONSTANT _O2CW-ISSUER-REQUIRED
 48 CONSTANT _O2CW-SOURCE-A
 56 CONSTANT _O2CW-SOURCE-U
 64 CONSTANT _O2CW-CURSOR-A
 72 CONSTANT _O2CW-REMAINING
 80 CONSTANT _O2CW-PAIR-A
 88 CONSTANT _O2CW-PAIR-U
 96 CONSTANT _O2CW-RAW-NAME-A
104 CONSTANT _O2CW-RAW-NAME-U
112 CONSTANT _O2CW-RAW-VALUE-A
120 CONSTANT _O2CW-RAW-VALUE-U
128 CONSTANT _O2CW-NAME-A
136 CONSTANT _O2CW-NAME-U
144 CONSTANT _O2CW-NAMES-USED
152 CONSTANT _O2CW-PARAMETER-COUNT
160 CONSTANT _O2CW-PRESENCE
168 CONSTANT _O2CW-SCAN
176 CONSTANT _O2CW-NOW
184 CONSTANT _O2CW-EXPIRES
192 CONSTANT _O2CW-STATE-U
200 CONSTANT _O2CW-PARSED-ISSUER-U
208 CONSTANT _O2CW-CODE-U
216 CONSTANT _O2CW-ERROR-U
224 CONSTANT _O2CW-DESCRIPTION-U
232 CONSTANT _O2CW-HEADER-SIZE

240 CONSTANT _O2CW-RAW-STATE-OFF
272 CONSTANT _O2CW-STATE-OFF
315 CONSTANT _O2CW-VERIFIER-OFF
358 CONSTANT _O2CW-CHALLENGE-OFF
408 CONSTANT _O2CW-PKCE-OFF
632 CONSTANT _O2CW-NAME-DESCRIPTORS-OFF
1144 CONSTANT _O2CW-NAME-ARENA-OFF
3192 CONSTANT _O2CW-PARSED-STATE-OFF
3235 CONSTANT _O2CW-PARSED-ISSUER-OFF
5283 CONSTANT _O2CW-CODE-OFF
13475 CONSTANT _O2CW-ERROR-OFF
13731 CONSTANT _O2CW-DESCRIPTION-OFF
14760 CONSTANT O2CODE-WORKSPACE-SIZE

: _O2CW.OBJECT           ( workspace -- address ) _O2CW-OBJECT + ;
: _O2CW.BINDING-A        ( workspace -- address ) _O2CW-BINDING-A + ;
: _O2CW.BINDING-U        ( workspace -- address ) _O2CW-BINDING-U + ;
: _O2CW.ISSUER-A         ( workspace -- address ) _O2CW-ISSUER-A + ;
: _O2CW.ISSUER-U         ( workspace -- address ) _O2CW-ISSUER-U + ;
: _O2CW.ISSUER-REQUIRED  ( workspace -- address )
    _O2CW-ISSUER-REQUIRED + ;
: _O2CW.SOURCE-A         ( workspace -- address ) _O2CW-SOURCE-A + ;
: _O2CW.SOURCE-U         ( workspace -- address ) _O2CW-SOURCE-U + ;
: _O2CW.CURSOR-A         ( workspace -- address ) _O2CW-CURSOR-A + ;
: _O2CW.REMAINING        ( workspace -- address ) _O2CW-REMAINING + ;
: _O2CW.PAIR-A           ( workspace -- address ) _O2CW-PAIR-A + ;
: _O2CW.PAIR-U           ( workspace -- address ) _O2CW-PAIR-U + ;
: _O2CW.RAW-NAME-A       ( workspace -- address ) _O2CW-RAW-NAME-A + ;
: _O2CW.RAW-NAME-U       ( workspace -- address ) _O2CW-RAW-NAME-U + ;
: _O2CW.RAW-VALUE-A      ( workspace -- address ) _O2CW-RAW-VALUE-A + ;
: _O2CW.RAW-VALUE-U      ( workspace -- address ) _O2CW-RAW-VALUE-U + ;
: _O2CW.NAME-A           ( workspace -- address ) _O2CW-NAME-A + ;
: _O2CW.NAME-U           ( workspace -- address ) _O2CW-NAME-U + ;
: _O2CW.NAMES-USED       ( workspace -- address ) _O2CW-NAMES-USED + ;
: _O2CW.PARAMETER-COUNT  ( workspace -- address )
    _O2CW-PARAMETER-COUNT + ;
: _O2CW.PRESENCE         ( workspace -- address ) _O2CW-PRESENCE + ;
: _O2CW.SCAN             ( workspace -- address ) _O2CW-SCAN + ;
: _O2CW.NOW              ( workspace -- address ) _O2CW-NOW + ;
: _O2CW.EXPIRES          ( workspace -- address ) _O2CW-EXPIRES + ;
: _O2CW.STATE-U          ( workspace -- address ) _O2CW-STATE-U + ;
: _O2CW.PARSED-ISSUER-U  ( workspace -- address )
    _O2CW-PARSED-ISSUER-U + ;
: _O2CW.CODE-U           ( workspace -- address ) _O2CW-CODE-U + ;
: _O2CW.ERROR-U          ( workspace -- address ) _O2CW-ERROR-U + ;
: _O2CW.DESCRIPTION-U    ( workspace -- address )
    _O2CW-DESCRIPTION-U + ;

: _O2CW.RAW-STATE        ( workspace -- address )
    _O2CW-RAW-STATE-OFF + ;
: _O2CW.STATE            ( workspace -- address ) _O2CW-STATE-OFF + ;
: _O2CW.VERIFIER         ( workspace -- address ) _O2CW-VERIFIER-OFF + ;
: _O2CW.CHALLENGE        ( workspace -- address ) _O2CW-CHALLENGE-OFF + ;
: _O2CW.PKCE             ( workspace -- address ) _O2CW-PKCE-OFF + ;
: _O2CW.NAME-DESCRIPTORS ( workspace -- address )
    _O2CW-NAME-DESCRIPTORS-OFF + ;
: _O2CW.NAME-ARENA       ( workspace -- address )
    _O2CW-NAME-ARENA-OFF + ;
: _O2CW.PARSED-STATE     ( workspace -- address )
    _O2CW-PARSED-STATE-OFF + ;
: _O2CW.PARSED-ISSUER    ( workspace -- address )
    _O2CW-PARSED-ISSUER-OFF + ;
: _O2CW.CODE             ( workspace -- address ) _O2CW-CODE-OFF + ;
: _O2CW.ERROR            ( workspace -- address ) _O2CW-ERROR-OFF + ;
: _O2CW.DESCRIPTION      ( workspace -- address )
    _O2CW-DESCRIPTION-OFF + ;

: _O2C-WIPE-WORKSPACE  ( workspace -- )
    O2CODE-WORKSPACE-SIZE 0 FILL ;

: _O2C-WIPE-OBJECT  ( object -- )
    O2CODE-TRANSACTION-SIZE 0 FILL ;

\ =====================================================================
\  Admission and object integrity
\ =====================================================================

: _O2C-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP O2CODE-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP O2CODE-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP O2CODE-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP O2CODE-S-PLATFORM EXIT
    THEN
    DROP O2CODE-S-PLATFORM ;

: _O2C-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _O2C-CALLER>STATUS ;

: _O2C-BOOLEAN?  ( value -- flag )
    DUP 0= SWAP -1 = OR ;

: _O2C-BOUNDED-LENGTH?  ( length capacity -- flag )
    OVER 0< IF 2DROP 0 EXIT THEN
    U> 0= ;

: _O2C-PHASE?  ( phase -- flag )
    DUP O2CODE-PHASE-EMPTY >=
    SWAP O2CODE-PHASE-SPENT <= AND ;

: _O2C-OBJECT-BASIC?  ( object -- flag )
    DUP _O2C.MAGIC @ _O2C-MAGIC-VALUE <> IF DROP 0 EXIT THEN
    DUP _O2C.PHASE @ _O2C-PHASE? 0= IF DROP 0 EXIT THEN
    DUP _O2C.BORROWED @ _O2C-BOOLEAN? 0= IF DROP 0 EXIT THEN
    DUP _O2C.ISSUER-REQUIRED @ _O2C-BOOLEAN? 0= IF DROP 0 EXIT THEN
    DUP _O2C.BINDING-U @ O2CODE-BINDING-CAPACITY
        _O2C-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2C.ISSUER-U @ O2CODE-ISSUER-CAPACITY
        _O2C-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2C.REQUEST-URI-U @ O2CODE-REQUEST-URI-CAPACITY
        _O2C-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2C.CODE-U @ O2CODE-CODE-CAPACITY
        _O2C-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2C.ERROR-U @ O2CODE-ERROR-CAPACITY
        _O2C-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    _O2C.DESCRIPTION-U @ O2CODE-ERROR-DESCRIPTION-CAPACITY
    _O2C-BOUNDED-LENGTH? ;

: _O2C-EMPTY-SHAPE?  ( object -- flag )
    DUP _O2C.ISSUER-REQUIRED @ 0=
    OVER _O2C.BINDING-U @ 0= AND
    OVER _O2C.ISSUER-U @ 0= AND
    OVER _O2C.REQUEST-URI-U @ 0= AND
    OVER _O2C.DEADLINE @ 0= AND
    OVER _O2C.CODE-U @ 0= AND
    OVER _O2C.ERROR-U @ 0= AND
    SWAP _O2C.DESCRIPTION-U @ 0= AND ;

: _O2C-LIVE-BASE-SHAPE?  ( object -- flag )
    DUP _O2C.BINDING-U @ 0>
    SWAP _O2C.ISSUER-U @ 0> AND ;

: _O2C-PREPARED-SHAPE?  ( object -- flag )
    DUP _O2C-LIVE-BASE-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _O2C.REQUEST-URI-U @ 0=
    OVER _O2C.DEADLINE @ 0= AND
    OVER _O2C.CODE-U @ 0= AND
    OVER _O2C.ERROR-U @ 0= AND
    SWAP _O2C.DESCRIPTION-U @ 0= AND ;

: _O2C-PAR-READY-SHAPE?  ( object -- flag )
    DUP _O2C-LIVE-BASE-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _O2C.REQUEST-URI-U @ 0>
    OVER _O2C.DEADLINE @ 0> AND
    OVER _O2C.CODE-U @ 0= AND
    OVER _O2C.ERROR-U @ 0= AND
    SWAP _O2C.DESCRIPTION-U @ 0= AND ;

: _O2C-AWAITING-SHAPE?  ( object -- flag )
    DUP _O2C-LIVE-BASE-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _O2C.BORROWED @ IF
        DUP _O2C.REQUEST-URI-U @ 0>
    ELSE
        DUP _O2C.REQUEST-URI-U @ 0=
    THEN
    OVER _O2C.DEADLINE @ 0> AND
    OVER _O2C.CODE-U @ 0= AND
    OVER _O2C.ERROR-U @ 0= AND
    SWAP _O2C.DESCRIPTION-U @ 0= AND ;

: _O2C-CODE-READY-SHAPE?  ( object -- flag )
    DUP _O2C-LIVE-BASE-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _O2C.REQUEST-URI-U @ 0=
    OVER _O2C.DEADLINE @ 0> AND
    OVER _O2C.CODE-U @ 0> AND
    OVER _O2C.ERROR-U @ 0= AND
    SWAP _O2C.DESCRIPTION-U @ 0= AND ;

: _O2C-DENIED-SHAPE?  ( object -- flag )
    DUP _O2C-LIVE-BASE-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _O2C.REQUEST-URI-U @ 0=
    OVER _O2C.DEADLINE @ 0> AND
    OVER _O2C.CODE-U @ 0= AND
    SWAP _O2C.ERROR-U @ 0> AND ;

: _O2C-SPENT-SHAPE?  ( object -- flag )
    DUP _O2C-LIVE-BASE-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _O2C.REQUEST-URI-U @ 0=
    OVER _O2C.DEADLINE @ 0> AND
    OVER _O2C.BORROWED @ IF
        OVER _O2C.CODE-U @ 0>
    ELSE
        OVER _O2C.CODE-U @ 0=
    THEN
    AND
    OVER _O2C.ERROR-U @ 0= AND
    SWAP _O2C.DESCRIPTION-U @ 0= AND ;

: _O2C-OBJECT-SHAPE?  ( object -- flag )
    DUP _O2C.PHASE @
    DUP O2CODE-PHASE-EMPTY = IF
        DROP _O2C-EMPTY-SHAPE? EXIT
    THEN
    DUP O2CODE-PHASE-PREPARED = IF
        DROP _O2C-PREPARED-SHAPE? EXIT
    THEN
    DUP O2CODE-PHASE-PAR-READY = IF
        DROP _O2C-PAR-READY-SHAPE? EXIT
    THEN
    DUP O2CODE-PHASE-AWAITING = IF
        DROP _O2C-AWAITING-SHAPE? EXIT
    THEN
    DUP O2CODE-PHASE-CODE-READY = IF
        DROP _O2C-CODE-READY-SHAPE? EXIT
    THEN
    DUP O2CODE-PHASE-DENIED = IF
        DROP _O2C-DENIED-SHAPE? EXIT
    THEN
    DROP _O2C-SPENT-SHAPE? ;

: _O2C-OBJECT-STATUS  ( object -- status )
    DUP 0= IF DROP O2CODE-S-INVALID EXIT THEN
    DUP 7 AND IF DROP O2CODE-S-INVALID EXIT THEN
    DUP O2CODE-TRANSACTION-SIZE _O2C-ADMIT-SPAN
    ?DUP IF NIP EXIT THEN
    DUP _O2C-OBJECT-BASIC? 0= IF DROP O2CODE-S-INVALID EXIT THEN
    _O2C-OBJECT-SHAPE?
    IF O2CODE-S-OK ELSE O2CODE-S-INVALID THEN ;

: _O2C-WORKSPACE-STATUS  ( workspace -- status )
    DUP 0= IF DROP O2CODE-S-INVALID EXIT THEN
    DUP 7 AND IF DROP O2CODE-S-INVALID EXIT THEN
    O2CODE-WORKSPACE-SIZE _O2C-ADMIT-SPAN ;

: _O2C-INITIALIZE  ( object -- )
    DUP _O2C-WIPE-OBJECT
    _O2C-MAGIC-VALUE OVER _O2C.MAGIC !
    O2CODE-PHASE-EMPTY SWAP _O2C.PHASE ! ;

\ =====================================================================
\  Initialization, reset, phase, and denial diagnostics
\ =====================================================================

: O2CODE-INIT?  ( object -- status )
    DUP 0= IF DROP O2CODE-S-INVALID EXIT THEN
    DUP 7 AND IF DROP O2CODE-S-INVALID EXIT THEN
    DUP O2CODE-TRANSACTION-SIZE _O2C-ADMIT-SPAN
    ?DUP IF NIP EXIT THEN
    DUP _O2C-OBJECT-BASIC? IF
        DUP _O2C.BORROWED @ IF
            DROP O2CODE-S-BUSY EXIT
        THEN
    THEN
    _O2C-INITIALIZE O2CODE-S-OK ;

: O2CODE-INIT  ( object -- )
    O2CODE-INIT? DROP ;

: O2CODE-CLEAR?  ( object -- status )
    DUP _O2C-OBJECT-STATUS ?DUP IF NIP EXIT THEN
    DUP _O2C.BORROWED @ IF DROP O2CODE-S-BUSY EXIT THEN
    _O2C-INITIALIZE O2CODE-S-OK ;

: O2CODE-CLEAR  ( object -- )
    O2CODE-CLEAR? DROP ;

: O2CODE-PHASE@  ( object -- phase status )
    DUP _O2C-OBJECT-STATUS ?DUP IF
        >R DROP 0 R> EXIT
    THEN
    _O2C.PHASE @ O2CODE-S-OK ;

: O2CODE-ERROR@
  \ ( object -- error-address error-u description-address description-u
  \              status )
    DUP _O2C-OBJECT-STATUS ?DUP IF
        >R DROP 0 0 0 0 R> EXIT
    THEN
    DUP _O2C.PHASE @ O2CODE-PHASE-DENIED <> IF
        DROP 0 0 0 0 O2CODE-S-PHASE EXIT
    THEN
    DUP _O2C.ERROR
    OVER _O2C.ERROR-U @
    2 PICK _O2C.DESCRIPTION
    3 PICK _O2C.DESCRIPTION-U @
    4 ROLL DROP
    O2CODE-S-OK ;

\ =====================================================================
\  Pure validation and status translation
\ =====================================================================

: _O2C-VSCHAR?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ 32 127 WITHIN 0= IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _O2C-URI-CHAR?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ 33 127 WITHIN 0= IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _O2C-NQSCHAR?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@
        DUP 32 127 WITHIN 0= IF
            DROP 2DROP 0 EXIT
        THEN
        DUP 34 = SWAP 92 = OR IF
            2DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _O2C-CT-BYTES=  ( left right length -- flag )
    0
    BEGIN 1 PICK WHILE
        3 PICK C@
        3 PICK C@
        XOR OR
        >R
        1-
        ROT 1+ -ROT
        SWAP 1+ SWAP
        R>
    REPEAT
    >R 2DROP DROP R> 0= ;

: _O2C-FORM>STATUS  ( form-status -- status )
    DUP FORM-URLENCODED-S-OK = IF DROP O2CODE-S-OK EXIT THEN
    DUP FORM-URLENCODED-S-CAPACITY = IF
        DROP O2CODE-S-CAPACITY EXIT
    THEN
    DUP FORM-URLENCODED-S-ALIAS = IF DROP O2CODE-S-ALIAS EXIT THEN
    DUP FORM-URLENCODED-S-RANGE = IF DROP O2CODE-S-RANGE EXIT THEN
    DUP FORM-URLENCODED-S-PROTECTED = IF
        DROP O2CODE-S-PROTECTED EXIT
    THEN
    DUP FORM-URLENCODED-S-PLATFORM = IF
        DROP O2CODE-S-PLATFORM EXIT
    THEN
    DROP O2CODE-S-ENCODING ;

: _O2C-B64>STATUS  ( base64url-status -- status )
    DUP JOSE-B64URL-S-CAPACITY = IF
        DROP O2CODE-S-CAPACITY EXIT
    THEN
    DUP JOSE-B64URL-S-ALIAS = IF DROP O2CODE-S-ALIAS EXIT THEN
    DUP JOSE-B64URL-S-RANGE = IF DROP O2CODE-S-RANGE EXIT THEN
    DUP JOSE-B64URL-S-PROTECTED = IF
        DROP O2CODE-S-PROTECTED EXIT
    THEN
    DUP JOSE-B64URL-S-PLATFORM = IF
        DROP O2CODE-S-PLATFORM EXIT
    THEN
    DROP O2CODE-S-INTERNAL ;

: _O2C-PKCE>STATUS  ( pkce-status -- status )
    DUP OAUTH2-PKCE-S-ENTROPY = IF DROP O2CODE-S-ENTROPY EXIT THEN
    DUP OAUTH2-PKCE-S-CRYPTO = IF DROP O2CODE-S-CRYPTO EXIT THEN
    DUP OAUTH2-PKCE-S-CAPACITY = IF DROP O2CODE-S-CAPACITY EXIT THEN
    DUP OAUTH2-PKCE-S-ALIAS = IF DROP O2CODE-S-ALIAS EXIT THEN
    DUP OAUTH2-PKCE-S-RANGE = IF DROP O2CODE-S-RANGE EXIT THEN
    DUP OAUTH2-PKCE-S-PROTECTED = IF
        DROP O2CODE-S-PROTECTED EXIT
    THEN
    DUP OAUTH2-PKCE-S-PLATFORM = IF
        DROP O2CODE-S-PLATFORM EXIT
    THEN
    DROP O2CODE-S-INTERNAL ;

: _O2C-ENTROPY>STATUS  ( entropy-status -- status )
    DUP ENTROPY-S-UNAVAILABLE = IF DROP O2CODE-S-ENTROPY EXIT THEN
    DUP ENTROPY-S-RANGE = IF DROP O2CODE-S-RANGE EXIT THEN
    DUP ENTROPY-S-PROTECTED = IF
        DROP O2CODE-S-PROTECTED EXIT
    THEN
    DROP O2CODE-S-INTERNAL ;

\ =====================================================================
\  PREPARE geometry and hardware-backed secret generation
\ =====================================================================

: _O2C-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _O2C-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;
: _O2C-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;
: _O2C-DROP6  ( x1 x2 x3 x4 x5 x6 -- ) 2DROP 2DROP 2DROP ;
: _O2C-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- )
    2DROP 2DROP 2DROP DROP ;

: _O2C-RETURN7  ( x1 x2 x3 x4 x5 x6 x7 status -- status )
    >R _O2C-DROP7 R> ;

: _O2C-7DUP
  \ ( x1 x2 x3 x4 x5 x6 x7 --
  \   x1 x2 x3 x4 x5 x6 x7 x1 x2 x3 x4 x5 x6 x7 )
    6 PICK 6 PICK 6 PICK 6 PICK 6 PICK 6 PICK 6 PICK ;

: _O2C-PREPARE-GEOMETRY
  \ ( binding binding-u issuer issuer-u issuer-required object workspace
  \   -- status )
    DUP _O2C-WORKSPACE-STATUS ?DUP IF
        _O2C-RETURN7 EXIT
    THEN
    1 PICK _O2C-OBJECT-STATUS ?DUP IF
        _O2C-RETURN7 EXIT
    THEN
    1 PICK _O2C.BORROWED @ IF
        O2CODE-S-BUSY _O2C-RETURN7 EXIT
    THEN
    1 PICK _O2C.PHASE @ O2CODE-PHASE-EMPTY <> IF
        O2CODE-S-PHASE _O2C-RETURN7 EXIT
    THEN
    2 PICK _O2C-BOOLEAN? 0= IF
        O2CODE-S-INVALID _O2C-RETURN7 EXIT
    THEN

    5 PICK DUP 1 < IF
        DROP O2CODE-S-INVALID _O2C-RETURN7 EXIT
    THEN
    O2CODE-BINDING-CAPACITY U> IF
        O2CODE-S-CAPACITY _O2C-RETURN7 EXIT
    THEN
    6 PICK 6 PICK _O2C-ADMIT-SPAN ?DUP IF
        _O2C-RETURN7 EXIT
    THEN

    3 PICK DUP 1 < IF
        DROP O2CODE-S-INVALID _O2C-RETURN7 EXIT
    THEN
    O2CODE-ISSUER-CAPACITY U> IF
        O2CODE-S-CAPACITY _O2C-RETURN7 EXIT
    THEN
    4 PICK 4 PICK _O2C-ADMIT-SPAN ?DUP IF
        _O2C-RETURN7 EXIT
    THEN
    4 PICK 4 PICK _O2C-URI-CHAR? 0= IF
        O2CODE-S-INVALID _O2C-RETURN7 EXIT
    THEN

    1 PICK O2CODE-TRANSACTION-SIZE
    2 PICK O2CODE-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN7 EXIT
    THEN
    6 PICK 6 PICK
    3 PICK O2CODE-TRANSACTION-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN7 EXIT
    THEN
    6 PICK 6 PICK
    2 PICK O2CODE-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN7 EXIT
    THEN
    4 PICK 4 PICK
    3 PICK O2CODE-TRANSACTION-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN7 EXIT
    THEN
    4 PICK 4 PICK
    2 PICK O2CODE-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN7 EXIT
    THEN
    O2CODE-S-OK _O2C-RETURN7 ;

: _O2C-BIND-PREPARE
  \ ( binding binding-u issuer issuer-u issuer-required object workspace
  \   -- workspace )
    DUP _O2C-WIPE-WORKSPACE
    6 PICK OVER _O2CW.BINDING-A !
    5 PICK OVER _O2CW.BINDING-U !
    4 PICK OVER _O2CW.ISSUER-A !
    3 PICK OVER _O2CW.ISSUER-U !
    2 PICK OVER _O2CW.ISSUER-REQUIRED !
    1 PICK OVER _O2CW.OBJECT !
    >R _O2C-DROP6 R> ;

: _O2C-GENERATE-STATE  ( workspace -- status )
    >R
    R@ _O2CW.RAW-STATE 32 ENTROPY-FILL
    DUP ENTROPY-S-OK <> IF
        _O2C-ENTROPY>STATUS R> DROP EXIT
    THEN
    DROP
    R@ _O2CW.RAW-STATE 32
    R@ _O2CW.STATE O2CODE-STATE-SIZE
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        NIP _O2C-B64>STATUS R> DROP EXIT
    THEN
    DROP
    O2CODE-STATE-SIZE <> IF
        R> DROP O2CODE-S-INTERNAL EXIT
    THEN
    R> DROP O2CODE-S-OK ;

: _O2C-GENERATE-PKCE  ( workspace -- status )
    >R
    R@ _O2CW.VERIFIER O2CODE-VERIFIER-SIZE
    R@ _O2CW.CHALLENGE O2CODE-CHALLENGE-SIZE
    R@ _O2CW.PKCE
    OAUTH2-PKCE-GENERATE
    DUP OAUTH2-PKCE-S-OK <> IF
        >R 2DROP R> _O2C-PKCE>STATUS R> DROP EXIT
    THEN
    DROP
    DUP O2CODE-CHALLENGE-SIZE <> IF
        2DROP R> DROP O2CODE-S-INTERNAL EXIT
    THEN
    SWAP O2CODE-VERIFIER-SIZE <> IF
        DROP R> DROP O2CODE-S-INTERNAL EXIT
    THEN
    DROP
    R> DROP O2CODE-S-OK ;

: _O2C-PUBLISH-PREPARED  ( workspace -- )
    DUP _O2CW.OBJECT @ >R

    DUP _O2CW.BINDING-A @
    R@ _O2C.BINDING
    2 PICK _O2CW.BINDING-U @ MOVE
    DUP _O2CW.BINDING-U @ R@ _O2C.BINDING-U !

    DUP _O2CW.ISSUER-A @
    R@ _O2C.ISSUER
    2 PICK _O2CW.ISSUER-U @ MOVE
    DUP _O2CW.ISSUER-U @ R@ _O2C.ISSUER-U !

    DUP _O2CW.STATE R@ _O2C.STATE O2CODE-STATE-SIZE MOVE
    DUP _O2CW.VERIFIER R@ _O2C.VERIFIER O2CODE-VERIFIER-SIZE MOVE
    DUP _O2CW.CHALLENGE R@ _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE MOVE

    DUP _O2CW.ISSUER-REQUIRED @ R@ _O2C.ISSUER-REQUIRED !
    O2CODE-PHASE-PREPARED R@ _O2C.PHASE !
    DROP R> DROP ;

: _O2C-PREPARE-OP
  \ ( binding binding-u issuer issuer-u issuer-required object workspace
  \   -- status )
    _O2C-BIND-PREPARE
    DUP _O2C-GENERATE-STATE
    DUP IF NIP EXIT THEN
    DROP
    DUP _O2C-GENERATE-PKCE
    DUP IF NIP EXIT THEN
    DROP
    _O2C-PUBLISH-PREPARED
    O2CODE-S-OK ;

: _O2C-PREPARE-CALL
  \ ( binding binding-u issuer issuer-u issuer-required object workspace xt
  \   -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _O2C-WIPE-WORKSPACE
        _O2C-DROP7
        R> DROP
        O2CODE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2C-WIPE-WORKSPACE
    R> DROP ;

: O2CODE-PREPARE
  \ ( binding binding-u issuer issuer-u issuer-required object workspace
  \   -- status )
    _O2C-7DUP _O2C-PREPARE-GEOMETRY
    DUP IF
        >R _O2C-DROP7 R> EXIT
    THEN
    DROP
    ['] _O2C-PREPARE-OP _O2C-PREPARE-CALL ;

\ =====================================================================
\  PAR binding, acceptance, and one-shot authorization launch
\ =====================================================================

: _O2C-RETURN5  ( x1 x2 x3 x4 x5 status -- status )
    >R _O2C-DROP5 R> ;

: _O2C-5DUP
  ( x1 x2 x3 x4 x5 -- x1 x2 x3 x4 x5 x1 x2 x3 x4 x5 )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK ;

: _O2C-ACCEPT-PAR-GEOMETRY
  ( request-uri request-uri-u expires-in now-seconds object -- status )
    DUP _O2C-OBJECT-STATUS ?DUP IF
        _O2C-RETURN5 EXIT
    THEN
    DUP _O2C.BORROWED @ IF
        O2CODE-S-BUSY _O2C-RETURN5 EXIT
    THEN
    DUP _O2C.PHASE @ O2CODE-PHASE-PREPARED <> IF
        O2CODE-S-PHASE _O2C-RETURN5 EXIT
    THEN

    3 PICK DUP 1 < IF
        DROP O2CODE-S-INVALID _O2C-RETURN5 EXIT
    THEN
    O2CODE-REQUEST-URI-CAPACITY U> IF
        O2CODE-S-CAPACITY _O2C-RETURN5 EXIT
    THEN
    4 PICK 4 PICK _O2C-ADMIT-SPAN ?DUP IF
        _O2C-RETURN5 EXIT
    THEN
    4 PICK 4 PICK _O2C-VSCHAR? 0= IF
        O2CODE-S-INVALID _O2C-RETURN5 EXIT
    THEN

    2 PICK DUP 1 < IF
        DROP O2CODE-S-INVALID _O2C-RETURN5 EXIT
    THEN
    O2CODE-MAX-PAR-EXPIRES-IN U> IF
        O2CODE-S-INVALID _O2C-RETURN5 EXIT
    THEN
    1 PICK DUP 0< IF
        DROP O2CODE-S-INVALID _O2C-RETURN5 EXIT
    THEN
    _O2C-CELL-MAX U> IF
        O2CODE-S-INVALID _O2C-RETURN5 EXIT
    THEN
    2 PICK _O2C-CELL-MAX 3 PICK -
    U> IF
        O2CODE-S-OVERFLOW _O2C-RETURN5 EXIT
    THEN

    4 PICK 4 PICK
    2 PICK O2CODE-TRANSACTION-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN5 EXIT
    THEN
    O2CODE-S-OK _O2C-RETURN5 ;

: O2CODE-ACCEPT-PAR
  ( request-uri request-uri-u expires-in now-seconds object -- status )
    _O2C-5DUP _O2C-ACCEPT-PAR-GEOMETRY
    DUP IF
        >R _O2C-DROP5 R> EXIT
    THEN
    DROP
    >R
    3 PICK R@ _O2C.REQUEST-URI 4 PICK MOVE
    2 PICK R@ _O2C.REQUEST-URI-U !
    2DUP + R@ _O2C.DEADLINE !
    O2CODE-PHASE-PAR-READY R@ _O2C.PHASE !
    _O2C-DROP4
    R> DROP
    O2CODE-S-OK ;

-17401 CONSTANT _O2C-E-CALLBACK-STACK

: _O2C-BORROW-STATUS
  ( callback context object required-phase -- status )
    >R
    2 PICK 0= IF
        _O2C-DROP3 R> DROP O2CODE-S-INVALID EXIT
    THEN
    DUP _O2C-OBJECT-STATUS ?DUP IF
        >R _O2C-DROP3 R> R> DROP EXIT
    THEN
    DUP _O2C.BORROWED @ IF
        _O2C-DROP3 R> DROP O2CODE-S-BUSY EXIT
    THEN
    DUP _O2C.PHASE @ R> <> IF
        _O2C-DROP3 O2CODE-S-PHASE EXIT
    THEN
    _O2C-DROP3 O2CODE-S-OK ;

: _O2C-PAR-CALLBACK-RUN
  \ callback receives
  \   ( context binding binding-u state state-u challenge challenge-u
  \     -- callback-status )
  \ stack effect here is ( callback context object -- callback-status )
    DEPTH 2 - >R
    ROT >R
    >R
    R@ _O2C.BINDING
    R@ _O2C.BINDING-U @
    R@ _O2C.STATE
    O2CODE-STATE-SIZE
    R@ _O2C.CHALLENGE
    O2CODE-CHALLENGE-SIZE
    R> DROP
    R> EXECUTE
    DEPTH R> <> IF
        _O2C-E-CALLBACK-STACK THROW
    THEN ;

: _O2C-WITH-PAR-CALL
  ( callback context object -- callback-status-or-O2CODE-status )
    DUP >R
    -1 R@ _O2C.BORROWED !
    ['] _O2C-PAR-CALLBACK-RUN CATCH
    DUP IF
        DROP _O2C-DROP3
        0 R@ _O2C.BORROWED !
        R> DROP
        O2CODE-S-CALLBACK EXIT
    THEN
    DROP
    0 R@ _O2C.BORROWED !
    R> DROP ;

: O2CODE-WITH-PAR
  \ ( callback context object -- callback-status-or-O2CODE-status )
    2 PICK 2 PICK 2 PICK O2CODE-PHASE-PREPARED
    _O2C-BORROW-STATUS
    DUP IF
        >R _O2C-DROP3 R> EXIT
    THEN
    DROP
    _O2C-WITH-PAR-CALL ;

: _O2C-LAUNCH-STATUS
  ( callback context now-seconds object -- status )
    3 PICK 0= IF _O2C-DROP4 O2CODE-S-INVALID EXIT THEN
    DUP _O2C-OBJECT-STATUS ?DUP IF
        >R _O2C-DROP4 R> EXIT
    THEN
    DUP _O2C.BORROWED @ IF
        _O2C-DROP4 O2CODE-S-BUSY EXIT
    THEN
    DUP _O2C.PHASE @ O2CODE-PHASE-PAR-READY <> IF
        _O2C-DROP4 O2CODE-S-PHASE EXIT
    THEN
    1 PICK DUP 0< IF
        DROP _O2C-DROP4 O2CODE-S-INVALID EXIT
    THEN
    OVER _O2C.DEADLINE @ U< 0= IF
        _O2C-DROP4 O2CODE-S-EXPIRED EXIT
    THEN
    _O2C-DROP4 O2CODE-S-OK ;

: _O2C-LAUNCH-CALLBACK-RUN
  \ callback receives
  \   ( context binding binding-u request-uri request-uri-u
  \     -- callback-status )
  \ stack effect here is ( callback context object -- callback-status )
    DEPTH 2 - >R
    ROT >R
    >R
    R@ _O2C.BINDING
    R@ _O2C.BINDING-U @
    R@ _O2C.REQUEST-URI
    R@ _O2C.REQUEST-URI-U @
    R> DROP
    R> EXECUTE
    DEPTH R> <> IF
        _O2C-E-CALLBACK-STACK THROW
    THEN ;

: _O2C-FINISH-LAUNCH  ( object -- )
    DUP _O2C.REQUEST-URI O2CODE-REQUEST-URI-CAPACITY 0 FILL
    0 OVER _O2C.REQUEST-URI-U !
    0 SWAP _O2C.BORROWED ! ;

: _O2C-WITH-LAUNCH-CALL
  ( callback context object -- callback-status-or-O2CODE-status )
    DUP >R
    -1 R@ _O2C.BORROWED !
    O2CODE-PHASE-AWAITING R@ _O2C.PHASE !
    ['] _O2C-LAUNCH-CALLBACK-RUN CATCH
    DUP IF
        DROP _O2C-DROP3
        R@ _O2C-FINISH-LAUNCH
        R> DROP
        O2CODE-S-CALLBACK EXIT
    THEN
    DROP
    R@ _O2C-FINISH-LAUNCH
    R> DROP ;

: O2CODE-WITH-LAUNCH
  \ ( callback context now-seconds object
  \   -- callback-status-or-O2CODE-status )
    3 PICK 3 PICK 3 PICK 3 PICK _O2C-LAUNCH-STATUS
    DUP IF
        >R _O2C-DROP4 R> EXIT
    THEN
    DROP
    SWAP DROP
    _O2C-WITH-LAUNCH-CALL ;

\ =====================================================================
\  Strict authorization-response form query parser
\ =====================================================================

1  CONSTANT _O2C-P-CODE
2  CONSTANT _O2C-P-STATE
4  CONSTANT _O2C-P-ISSUER
8  CONSTANT _O2C-P-ERROR
16 CONSTANT _O2C-P-DESCRIPTION

: _O2C-RETURN4  ( x1 x2 x3 x4 status -- status )
    >R _O2C-DROP4 R> ;

: _O2C-4DUP
  ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 x3 x4 )
    3 PICK 3 PICK 3 PICK 3 PICK ;

: _O2C-CALLBACK-GEOMETRY
  ( query query-u object workspace -- status )
    DUP _O2C-WORKSPACE-STATUS ?DUP IF
        _O2C-RETURN4 EXIT
    THEN
    1 PICK _O2C-OBJECT-STATUS ?DUP IF
        _O2C-RETURN4 EXIT
    THEN
    1 PICK _O2C.BORROWED @ IF
        O2CODE-S-BUSY _O2C-RETURN4 EXIT
    THEN
    1 PICK _O2C.PHASE @ O2CODE-PHASE-AWAITING <> IF
        O2CODE-S-PHASE _O2C-RETURN4 EXIT
    THEN

    2 PICK DUP 0< IF
        DROP O2CODE-S-INVALID _O2C-RETURN4 EXIT
    THEN
    O2CODE-CALLBACK-QUERY-CAPACITY U> IF
        O2CODE-S-CAPACITY _O2C-RETURN4 EXIT
    THEN
    3 PICK 3 PICK _O2C-ADMIT-SPAN ?DUP IF
        _O2C-RETURN4 EXIT
    THEN

    1 PICK O2CODE-TRANSACTION-SIZE
    2 PICK O2CODE-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN4 EXIT
    THEN
    3 PICK 3 PICK
    3 PICK O2CODE-TRANSACTION-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN4 EXIT
    THEN
    3 PICK 3 PICK
    2 PICK O2CODE-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        O2CODE-S-ALIAS _O2C-RETURN4 EXIT
    THEN
    O2CODE-S-OK _O2C-RETURN4 ;

: _O2C-BIND-CALLBACK
  ( query query-u object workspace -- workspace )
    DUP _O2C-WIPE-WORKSPACE
    3 PICK OVER _O2CW.SOURCE-A !
    2 PICK OVER _O2CW.SOURCE-U !
    1 PICK OVER _O2CW.OBJECT !
    3 PICK OVER _O2CW.CURSOR-A !
    2 PICK OVER _O2CW.REMAINING !
    >R _O2C-DROP3 R> ;

: _O2C-FIND-PAIR-END  ( workspace -- )
    0 OVER _O2CW.SCAN !
    BEGIN
        DUP _O2CW.SCAN @
        OVER _O2CW.REMAINING @ U< IF
            DUP _O2CW.CURSOR-A @
            OVER _O2CW.SCAN @ + C@
            38 <>
        ELSE
            0
        THEN
    WHILE
        1 OVER _O2CW.SCAN +!
    REPEAT
    DUP _O2CW.SCAN @ SWAP _O2CW.PAIR-U ! ;

: _O2C-FIND-EQUALS  ( workspace -- )
    0 OVER _O2CW.SCAN !
    BEGIN
        DUP _O2CW.SCAN @
        OVER _O2CW.PAIR-U @ U< IF
            DUP _O2CW.PAIR-A @
            OVER _O2CW.SCAN @ + C@
            61 <>
        ELSE
            0
        THEN
    WHILE
        1 OVER _O2CW.SCAN +!
    REPEAT
    DROP ;

: _O2C-BIND-RAW-COMPONENTS  ( workspace -- status )
    DUP _O2CW.PAIR-A @ OVER _O2CW.RAW-NAME-A !
    DUP _O2CW.SCAN @
    OVER _O2CW.PAIR-U @ U< IF
        DUP _O2CW.SCAN @ OVER _O2CW.RAW-NAME-U !
        DUP _O2CW.PAIR-A @ OVER _O2CW.SCAN @ + 1+
        OVER _O2CW.RAW-VALUE-A !
        DUP _O2CW.PAIR-U @ OVER _O2CW.SCAN @ - 1-
        OVER _O2CW.RAW-VALUE-U !
    ELSE
        DUP _O2CW.PAIR-U @ OVER _O2CW.RAW-NAME-U !
        DUP _O2CW.PAIR-A @ OVER _O2CW.PAIR-U @ +
        OVER _O2CW.RAW-VALUE-A !
        0 OVER _O2CW.RAW-VALUE-U !
    THEN
    DUP _O2CW.RAW-NAME-U @ 0= IF
        DROP O2CODE-S-RESPONSE EXIT
    THEN
    DROP O2CODE-S-OK ;

: _O2C-SPLIT-PAIR  ( workspace -- status )
    DUP _O2CW.CURSOR-A @ OVER _O2CW.PAIR-A !
    DUP _O2C-FIND-PAIR-END
    DUP _O2CW.PAIR-U @ 0= IF
        DROP O2CODE-S-RESPONSE EXIT
    THEN
    DUP _O2CW.PAIR-U @ OVER _O2CW.REMAINING @ U< IF
        DUP _O2CW.PAIR-U @ 1+
        OVER _O2CW.REMAINING @ = IF
            DROP O2CODE-S-RESPONSE EXIT
        THEN
    THEN
    DUP _O2C-FIND-EQUALS
    _O2C-BIND-RAW-COMPONENTS ;

: _O2C-NAME-DESCRIPTOR  ( index workspace -- address )
    SWAP _O2C-NAME-DESCRIPTOR-SIZE *
    SWAP _O2CW.NAME-DESCRIPTORS + ;

: _O2C-DESCRIPTOR-NAME=  ( descriptor workspace -- flag )
    >R
    DUP @
    SWAP 8 + @
    R@ _O2CW.NAME-A @
    R@ _O2CW.NAME-U @
    COMPARE 0=
    R> DROP ;

: _O2C-NAME-DUPLICATE?  ( workspace -- flag )
    0 OVER _O2CW.SCAN !
    BEGIN
        DUP _O2CW.SCAN @
        OVER _O2CW.PARAMETER-COUNT @ U<
    WHILE
        DUP _O2CW.SCAN @
        OVER _O2C-NAME-DESCRIPTOR
        OVER _O2C-DESCRIPTOR-NAME= IF
            DROP -1 EXIT
        THEN
        1 OVER _O2CW.SCAN +!
    REPEAT
    DROP 0 ;

: _O2C-STORE-NAME-DESCRIPTOR  ( workspace -- )
    DUP _O2CW.PARAMETER-COUNT @
    OVER _O2C-NAME-DESCRIPTOR
    >R
    DUP _O2CW.NAME-A @ R@ !
    DUP _O2CW.NAME-U @ R@ 8 + !
    R> DROP
    DUP _O2CW.NAME-U @ OVER _O2CW.NAMES-USED +!
    1 SWAP _O2CW.PARAMETER-COUNT +! ;

: _O2C-DECODE-NAME  ( workspace -- status )
    DUP _O2CW.PARAMETER-COUNT @ _O2C-MAX-PARAMETERS >= IF
        DROP O2CODE-S-CAPACITY EXIT
    THEN
    DUP _O2CW.RAW-NAME-A @
    OVER _O2CW.RAW-NAME-U @
    FORM-URLENCODED-DECODE-MEASURE
    DUP FORM-URLENCODED-S-OK <> IF
        >R 2DROP R> _O2C-FORM>STATUS EXIT
    THEN
    DROP
    DUP 0= IF 2DROP O2CODE-S-RESPONSE EXIT THEN
    2DUP SWAP _O2CW.NAMES-USED @ +
    _O2C-NAME-ARENA-CAPACITY U> IF
        2DROP O2CODE-S-CAPACITY EXIT
    THEN
    OVER _O2CW.NAME-ARENA
    2 PICK _O2CW.NAMES-USED @ +
    OVER
    3 PICK _O2CW.RAW-NAME-A @
    4 PICK _O2CW.RAW-NAME-U @
    2SWAP
    FORM-URLENCODED-DECODE
    DUP FORM-URLENCODED-S-OK <> IF
        >R _O2C-DROP3 R> _O2C-FORM>STATUS EXIT
    THEN
    DROP
    OVER <> IF
        2DROP O2CODE-S-INTERNAL EXIT
    THEN
    OVER _O2CW.NAME-ARENA
    2 PICK _O2CW.NAMES-USED @ +
    2 PICK _O2CW.NAME-A !
    OVER _O2CW.NAME-U !
    DUP _O2C-NAME-DUPLICATE? IF
        DROP O2CODE-S-DUPLICATE EXIT
    THEN
    DUP _O2C-STORE-NAME-DESCRIPTOR
    DROP O2CODE-S-OK ;

: _O2C-ADVANCE-PAIR  ( workspace -- )
    DUP _O2CW.PAIR-U @ OVER _O2CW.REMAINING @ U< IF
        DUP _O2CW.PAIR-U @ 1+ >R
        R@ OVER _O2CW.CURSOR-A +!
        R> NEGATE OVER _O2CW.REMAINING +!
    ELSE
        0 OVER _O2CW.REMAINING !
    THEN
    DROP ;

: _O2C-NAME=  ( expected expected-u workspace -- flag )
    >R
    R@ _O2CW.NAME-A @
    R@ _O2CW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _O2C-DECODE-VALUE
  ( destination destination-capacity workspace -- written status )
    >R
    R@ _O2CW.RAW-VALUE-A @
    R@ _O2CW.RAW-VALUE-U @
    2SWAP
    FORM-URLENCODED-DECODE
    _O2C-FORM>STATUS
    R> DROP ;

: _O2C-VALIDATE-UNKNOWN-VALUE  ( workspace -- status )
    DUP _O2CW.RAW-VALUE-A @
    SWAP _O2CW.RAW-VALUE-U @
    FORM-URLENCODED-DECODE-MEASURE
    _O2C-FORM>STATUS
    DUP IF NIP EXIT THEN
    NIP ;

: _O2C-STAGE-CODE  ( workspace -- status )
    DUP _O2CW.CODE O2CODE-CODE-CAPACITY
    2 PICK _O2C-DECODE-VALUE
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    DUP 0= IF 2DROP O2CODE-S-RESPONSE EXIT THEN
    DUP 2 PICK _O2CW.CODE SWAP _O2C-VSCHAR? 0= IF
        2DROP O2CODE-S-RESPONSE EXIT
    THEN
    OVER _O2CW.CODE-U !
    _O2C-P-CODE OVER _O2CW.PRESENCE +!
    DROP O2CODE-S-OK ;

: _O2C-STAGE-STATE  ( workspace -- status )
    DUP _O2CW.PARSED-STATE O2CODE-STATE-SIZE
    2 PICK _O2C-DECODE-VALUE
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    DUP 0= IF 2DROP O2CODE-S-STATE EXIT THEN
    DUP 2 PICK _O2CW.PARSED-STATE SWAP _O2C-VSCHAR? 0= IF
        2DROP O2CODE-S-STATE EXIT
    THEN
    OVER _O2CW.STATE-U !
    _O2C-P-STATE OVER _O2CW.PRESENCE +!
    DROP O2CODE-S-OK ;

: _O2C-STAGE-ISSUER  ( workspace -- status )
    DUP _O2CW.PARSED-ISSUER O2CODE-ISSUER-CAPACITY
    2 PICK _O2C-DECODE-VALUE
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    DUP 0= IF 2DROP O2CODE-S-ISSUER EXIT THEN
    DUP 2 PICK _O2CW.PARSED-ISSUER SWAP _O2C-URI-CHAR? 0= IF
        2DROP O2CODE-S-ISSUER EXIT
    THEN
    OVER _O2CW.PARSED-ISSUER-U !
    _O2C-P-ISSUER OVER _O2CW.PRESENCE +!
    DROP O2CODE-S-OK ;

: _O2C-STAGE-ERROR  ( workspace -- status )
    DUP _O2CW.ERROR O2CODE-ERROR-CAPACITY
    2 PICK _O2C-DECODE-VALUE
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    DUP 0= IF 2DROP O2CODE-S-RESPONSE EXIT THEN
    DUP 2 PICK _O2CW.ERROR SWAP _O2C-NQSCHAR? 0= IF
        2DROP O2CODE-S-RESPONSE EXIT
    THEN
    OVER _O2CW.ERROR-U !
    _O2C-P-ERROR OVER _O2CW.PRESENCE +!
    DROP O2CODE-S-OK ;

: _O2C-STAGE-DESCRIPTION  ( workspace -- status )
    DUP _O2CW.DESCRIPTION O2CODE-ERROR-DESCRIPTION-CAPACITY
    2 PICK _O2C-DECODE-VALUE
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    DUP 0= IF 2DROP O2CODE-S-RESPONSE EXIT THEN
    DUP 2 PICK _O2CW.DESCRIPTION SWAP _O2C-NQSCHAR? 0= IF
        2DROP O2CODE-S-RESPONSE EXIT
    THEN
    OVER _O2CW.DESCRIPTION-U !
    _O2C-P-DESCRIPTION OVER _O2CW.PRESENCE +!
    DROP O2CODE-S-OK ;

: _O2C-PROCESS-VALUE  ( workspace -- status )
    S" code" 2 PICK _O2C-NAME= IF
        _O2C-STAGE-CODE EXIT
    THEN
    S" state" 2 PICK _O2C-NAME= IF
        _O2C-STAGE-STATE EXIT
    THEN
    S" iss" 2 PICK _O2C-NAME= IF
        _O2C-STAGE-ISSUER EXIT
    THEN
    S" error" 2 PICK _O2C-NAME= IF
        _O2C-STAGE-ERROR EXIT
    THEN
    S" error_description" 2 PICK _O2C-NAME= IF
        _O2C-STAGE-DESCRIPTION EXIT
    THEN
    _O2C-VALIDATE-UNKNOWN-VALUE ;

: _O2C-PARSE-PAIRS  ( workspace -- status )
    BEGIN
        DUP _O2CW.REMAINING @
    WHILE
        DUP _O2C-SPLIT-PAIR ?DUP IF
            NIP EXIT
        THEN
        DUP _O2C-DECODE-NAME ?DUP IF
            NIP EXIT
        THEN
        DUP _O2C-PROCESS-VALUE ?DUP IF
            NIP EXIT
        THEN
        DUP _O2C-ADVANCE-PAIR
    REPEAT
    DROP O2CODE-S-OK ;

: _O2C-VALIDATE-STATE  ( workspace -- status )
    DUP _O2CW.PRESENCE @ _O2C-P-STATE AND 0= IF
        DROP O2CODE-S-MISSING EXIT
    THEN
    DUP _O2CW.STATE-U @ O2CODE-STATE-SIZE <> IF
        DROP O2CODE-S-STATE EXIT
    THEN
    DUP _O2CW.PARSED-STATE
    OVER _O2CW.OBJECT @ _O2C.STATE
    O2CODE-STATE-SIZE _O2C-CT-BYTES= 0= IF
        DROP O2CODE-S-STATE EXIT
    THEN
    DROP O2CODE-S-OK ;

: _O2C-VALIDATE-ISSUER  ( workspace -- status )
    DUP _O2CW.PRESENCE @ _O2C-P-ISSUER AND IF
        DUP _O2CW.PARSED-ISSUER-U @
        OVER _O2CW.OBJECT @ _O2C.ISSUER-U @ <> IF
            DROP O2CODE-S-ISSUER EXIT
        THEN
        DUP _O2CW.PARSED-ISSUER
        OVER _O2CW.PARSED-ISSUER-U @
        2 PICK _O2CW.OBJECT @
        DUP _O2C.ISSUER
        SWAP _O2C.ISSUER-U @
        COMPARE 0= IF
            DROP O2CODE-S-OK EXIT
        THEN
        DROP O2CODE-S-ISSUER EXIT
    THEN
    DUP _O2CW.OBJECT @ _O2C.ISSUER-REQUIRED @ IF
        DROP O2CODE-S-ISSUER EXIT
    THEN
    DROP O2CODE-S-OK ;

: _O2C-RESPONSE-KIND  ( workspace -- kind status )
    DUP _O2CW.PRESENCE @ _O2C-P-CODE AND 0<>
    OVER _O2CW.PRESENCE @ _O2C-P-ERROR AND 0<>
    2DUP = IF
        2DROP DROP 0 O2CODE-S-RESPONSE EXIT
    THEN
    DUP 0= IF
        2 PICK _O2CW.PRESENCE @ _O2C-P-DESCRIPTION AND IF
            2DROP DROP 0 O2CODE-S-RESPONSE EXIT
        THEN
    THEN
    IF
        2DROP 2 O2CODE-S-OK
    ELSE
        2DROP 1 O2CODE-S-OK
    THEN ;

: _O2C-PUBLISH-CODE  ( workspace -- status )
    DUP _O2CW.OBJECT @ >R
    R@ _O2C.CODE O2CODE-CODE-CAPACITY 0 FILL
    DUP _O2CW.CODE
    R@ _O2C.CODE
    2 PICK _O2CW.CODE-U @ MOVE
    DUP _O2CW.CODE-U @ R@ _O2C.CODE-U !
    O2CODE-PHASE-CODE-READY R@ _O2C.PHASE !
    DROP R> DROP
    O2CODE-S-OK ;

: _O2C-WIPE-DENIED-SECRETS  ( object -- )
    DUP _O2C.STATE O2CODE-STATE-SIZE 0 FILL
    DUP _O2C.VERIFIER O2CODE-VERIFIER-SIZE 0 FILL
    DUP _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE 0 FILL
    DUP _O2C.REQUEST-URI O2CODE-REQUEST-URI-CAPACITY 0 FILL
    DUP _O2C.CODE O2CODE-CODE-CAPACITY 0 FILL
    DUP _O2C.ERROR O2CODE-ERROR-CAPACITY 0 FILL
    _O2C.DESCRIPTION O2CODE-ERROR-DESCRIPTION-CAPACITY 0 FILL ;

: _O2C-PUBLISH-DENIAL  ( workspace -- status )
    DUP _O2CW.OBJECT @ >R
    R@ _O2C-WIPE-DENIED-SECRETS
    0 R@ _O2C.REQUEST-URI-U !
    0 R@ _O2C.CODE-U !

    DUP _O2CW.ERROR
    R@ _O2C.ERROR
    2 PICK _O2CW.ERROR-U @ MOVE
    DUP _O2CW.ERROR-U @ R@ _O2C.ERROR-U !

    DUP _O2CW.DESCRIPTION
    R@ _O2C.DESCRIPTION
    2 PICK _O2CW.DESCRIPTION-U @ MOVE
    DUP _O2CW.DESCRIPTION-U @ R@ _O2C.DESCRIPTION-U !

    O2CODE-PHASE-DENIED R@ _O2C.PHASE !
    DROP R> DROP
    O2CODE-S-DENIED ;

: _O2C-VALIDATE-AND-PUBLISH  ( workspace -- status )
    DUP _O2C-VALIDATE-STATE
    DUP IF NIP EXIT THEN
    DROP
    DUP _O2C-VALIDATE-ISSUER
    DUP IF NIP EXIT THEN
    DROP
    DUP _O2C-RESPONSE-KIND
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    1 = IF
        _O2C-PUBLISH-CODE
    ELSE
        _O2C-PUBLISH-DENIAL
    THEN ;

: _O2C-CALLBACK-OP
  ( query query-u object workspace -- status )
    _O2C-BIND-CALLBACK
    DUP _O2C-PARSE-PAIRS
    DUP IF NIP EXIT THEN
    DROP
    _O2C-VALIDATE-AND-PUBLISH ;

: _O2C-CALLBACK-CALL
  ( query query-u object workspace operation-xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _O2C-WIPE-WORKSPACE
        _O2C-DROP4
        R> DROP
        O2CODE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2C-WIPE-WORKSPACE
    R> DROP ;

: O2CODE-ACCEPT-CALLBACK
  ( raw-query raw-query-u object workspace -- status )
    _O2C-4DUP _O2C-CALLBACK-GEOMETRY
    DUP IF
        >R _O2C-DROP4 R> EXIT
    THEN
    DROP
    ['] _O2C-CALLBACK-OP _O2C-CALLBACK-CALL ;

\ =====================================================================
\  One-shot authorization-code and verifier handoff
\ =====================================================================

: _O2C-GRANT-CALLBACK-RUN
  \ callback receives
  \   ( context binding binding-u code code-u verifier verifier-u
  \     -- callback-status )
  \ stack effect here is ( callback context object -- callback-status )
    DEPTH 2 - >R
    ROT >R
    >R
    R@ _O2C.BINDING
    R@ _O2C.BINDING-U @
    R@ _O2C.CODE
    R@ _O2C.CODE-U @
    R@ _O2C.VERIFIER
    O2CODE-VERIFIER-SIZE
    R> DROP
    R> EXECUTE
    DEPTH R> <> IF
        _O2C-E-CALLBACK-STACK THROW
    THEN ;

: _O2C-FINISH-GRANT  ( object -- )
    DUP _O2C.STATE O2CODE-STATE-SIZE 0 FILL
    DUP _O2C.VERIFIER O2CODE-VERIFIER-SIZE 0 FILL
    DUP _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE 0 FILL
    DUP _O2C.CODE O2CODE-CODE-CAPACITY 0 FILL
    0 OVER _O2C.CODE-U !
    0 SWAP _O2C.BORROWED ! ;

: _O2C-WITH-GRANT-CALL
  ( callback context object -- callback-status-or-O2CODE-status )
    DUP >R
    -1 R@ _O2C.BORROWED !
    O2CODE-PHASE-SPENT R@ _O2C.PHASE !
    ['] _O2C-GRANT-CALLBACK-RUN CATCH
    DUP IF
        DROP _O2C-DROP3
        R@ _O2C-FINISH-GRANT
        R> DROP
        O2CODE-S-CALLBACK EXIT
    THEN
    DROP
    R@ _O2C-FINISH-GRANT
    R> DROP ;

: O2CODE-WITH-GRANT
  \ ( callback context object -- callback-status-or-O2CODE-status )
    2 PICK 2 PICK 2 PICK O2CODE-PHASE-CODE-READY
    _O2C-BORROW-STATUS
    DUP IF
        >R _O2C-DROP3 R> EXIT
    THEN
    DROP
    _O2C-WITH-GRANT-CALL ;

: O2CODE-WORKSPACE-CLEAR  ( workspace -- status )
    DUP _O2C-WORKSPACE-STATUS
    DUP IF NIP EXIT THEN
    DROP
    _O2C-WIPE-WORKSPACE
    O2CODE-S-OK ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _O2C-GEOMETRY-ABORT  ( -- )
    ." OAuth authorization-code geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _O2C-GEOMETRY-ABORT
[THEN]

_O2C-DESCRIPTION-OFF O2CODE-ERROR-DESCRIPTION-CAPACITY +
7 + -8 AND O2CODE-TRANSACTION-SIZE <> [IF]
    _O2C-GEOMETRY-ABORT
[THEN]

_O2CW-PKCE-OFF OAUTH2-PKCE-WORKSPACE-SIZE +
_O2CW-NAME-DESCRIPTORS-OFF U> [IF]
    _O2C-GEOMETRY-ABORT
[THEN]

_O2CW-NAME-DESCRIPTORS-OFF
_O2C-MAX-PARAMETERS _O2C-NAME-DESCRIPTOR-SIZE * +
_O2CW-NAME-ARENA-OFF <> [IF]
    _O2C-GEOMETRY-ABORT
[THEN]

_O2CW-NAME-ARENA-OFF _O2C-NAME-ARENA-CAPACITY +
_O2CW-PARSED-STATE-OFF <> [IF]
    _O2C-GEOMETRY-ABORT
[THEN]

_O2CW-DESCRIPTION-OFF O2CODE-ERROR-DESCRIPTION-CAPACITY +
7 + -8 AND O2CODE-WORKSPACE-SIZE <> [IF]
    _O2C-GEOMETRY-ABORT
[THEN]
