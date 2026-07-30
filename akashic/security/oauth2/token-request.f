\ =====================================================================
\  token-request.f - Protected OAuth authorization-code request owner
\ =====================================================================
\  This generic, address-free object copies one consumed O2CODE grant and
\  retains the exact caller-selected token HTU.  A higher composition borrows
\  those bytes synchronously to build a first request, may claim exactly one
\  retry, and later borrows nonsecret provenance to bind a response.
\
\  The object owns no HTTP transaction, form encoding, OAuth error parsing,
\  DPoP proof or nonce policy, token decoding, session, provider, AT Protocol,
\  clock, persistence, or application policy.  One caller serializes access.
\ =====================================================================

PROVIDED akashic-oauth2-trequest

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../../net/http-target.f
REQUIRE authorization-code.f

\ =====================================================================
\  Public status, phase, attempt, and capacity vocabulary
\ =====================================================================

0  CONSTANT O2TREQ-S-OK
1  CONSTANT O2TREQ-S-INVALID
2  CONSTANT O2TREQ-S-CAPACITY
3  CONSTANT O2TREQ-S-ALIAS
4  CONSTANT O2TREQ-S-PHASE
5  CONSTANT O2TREQ-S-BUSY
6  CONSTANT O2TREQ-S-CALLBACK
7  CONSTANT O2TREQ-S-AUTHORIZATION-CODE
8  CONSTANT O2TREQ-S-RANGE
9  CONSTANT O2TREQ-S-PROTECTED
10 CONSTANT O2TREQ-S-PLATFORM
11 CONSTANT O2TREQ-S-INTERNAL

: O2TREQ-STATUS-VALID?  ( status -- flag )
    DUP O2TREQ-S-OK >=
    SWAP O2TREQ-S-INTERNAL <= AND ;

0 CONSTANT O2TREQ-PHASE-EMPTY
1 CONSTANT O2TREQ-PHASE-READY
2 CONSTANT O2TREQ-PHASE-FIRST-AWAITING
3 CONSTANT O2TREQ-PHASE-RETRY-READY
4 CONSTANT O2TREQ-PHASE-RETRY-AWAITING
5 CONSTANT O2TREQ-PHASE-TERMINAL

1 CONSTANT O2TREQ-ATTEMPT-FIRST
2 CONSTANT O2TREQ-ATTEMPT-RETRY

HTARGET-URI-CAPACITY CONSTANT O2TREQ-HTU-CAPACITY

\ =====================================================================
\  Address-free protected request object
\ =====================================================================

0x4F32545245513031 CONSTANT _O2TRQ-MAGIC-VALUE  \ "O2TREQ01"

 0 CONSTANT _O2TRQ-MAGIC
 8 CONSTANT _O2TRQ-PHASE
16 CONSTANT _O2TRQ-BORROWED
24 CONSTANT _O2TRQ-ISSUER-REQUIRED
32 CONSTANT _O2TRQ-BINDING-U
40 CONSTANT _O2TRQ-ISSUER-U
48 CONSTANT _O2TRQ-CODE-U
56 CONSTANT _O2TRQ-HTU-U
64 CONSTANT _O2TRQ-HEADER-SIZE

_O2TRQ-HEADER-SIZE CONSTANT _O2TRQ-BINDING-OFF
_O2TRQ-BINDING-OFF O2CODE-BINDING-CAPACITY +
    CONSTANT _O2TRQ-ISSUER-OFF
_O2TRQ-ISSUER-OFF O2CODE-ISSUER-CAPACITY +
    CONSTANT _O2TRQ-STATE-OFF
_O2TRQ-STATE-OFF O2CODE-STATE-SIZE +
    CONSTANT _O2TRQ-VERIFIER-OFF
_O2TRQ-VERIFIER-OFF O2CODE-VERIFIER-SIZE +
    CONSTANT _O2TRQ-CODE-OFF
_O2TRQ-CODE-OFF O2CODE-CODE-CAPACITY +
    CONSTANT _O2TRQ-HTU-OFF
_O2TRQ-HTU-OFF O2TREQ-HTU-CAPACITY +
7 + -8 AND CONSTANT O2TREQ-SIZE

: _O2TRQ.MAGIC  ( object -- field ) _O2TRQ-MAGIC + ;
: _O2TRQ.PHASE  ( object -- field ) _O2TRQ-PHASE + ;
: _O2TRQ.BORROWED  ( object -- field ) _O2TRQ-BORROWED + ;
: _O2TRQ.ISSUER-REQUIRED
  ( object -- field )
    _O2TRQ-ISSUER-REQUIRED + ;
: _O2TRQ.BINDING-U  ( object -- field ) _O2TRQ-BINDING-U + ;
: _O2TRQ.ISSUER-U  ( object -- field ) _O2TRQ-ISSUER-U + ;
: _O2TRQ.CODE-U  ( object -- field ) _O2TRQ-CODE-U + ;
: _O2TRQ.HTU-U  ( object -- field ) _O2TRQ-HTU-U + ;

: _O2TRQ.BINDING  ( object -- address ) _O2TRQ-BINDING-OFF + ;
: _O2TRQ.ISSUER  ( object -- address ) _O2TRQ-ISSUER-OFF + ;
: _O2TRQ.STATE  ( object -- address ) _O2TRQ-STATE-OFF + ;
: _O2TRQ.VERIFIER  ( object -- address ) _O2TRQ-VERIFIER-OFF + ;
: _O2TRQ.CODE  ( object -- address ) _O2TRQ-CODE-OFF + ;
: _O2TRQ.HTU  ( object -- address ) _O2TRQ-HTU-OFF + ;

\ =====================================================================
\  Admission and object integrity
\ =====================================================================

: _O2TRQ-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP O2TREQ-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP O2TREQ-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP O2TREQ-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP O2TREQ-S-PLATFORM EXIT
    THEN
    DROP O2TREQ-S-PLATFORM ;

: _O2TRQ-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _O2TRQ-CALLER>STATUS ;

: _O2TRQ-BOOLEAN?  ( value -- flag )
    DUP 0= SWAP -1 = OR ;

: _O2TRQ-BOUNDED-LENGTH?  ( length capacity -- flag )
    OVER 0< IF 2DROP 0 EXIT THEN
    U> 0= ;

: _O2TRQ-REQUIRED-LENGTH?  ( length capacity -- flag )
    OVER 0> IF U> 0= ELSE 2DROP 0 THEN ;

: _O2TRQ-PHASE?  ( phase -- flag )
    DUP O2TREQ-PHASE-EMPTY >=
    SWAP O2TREQ-PHASE-TERMINAL <= AND ;

: _O2TRQ-LIVE-PHASE?  ( phase -- flag )
    DUP O2TREQ-PHASE-READY >=
    SWAP O2TREQ-PHASE-RETRY-AWAITING <= AND ;

: _O2TRQ-AWAITING-PHASE?  ( phase -- flag )
    DUP O2TREQ-PHASE-FIRST-AWAITING =
    SWAP O2TREQ-PHASE-RETRY-AWAITING = OR ;

: _O2TRQ-READY-PHASE?  ( phase -- flag )
    DUP O2TREQ-PHASE-READY =
    SWAP O2TREQ-PHASE-RETRY-READY = OR ;

: _O2TRQ-OBJECT-BASIC?  ( object -- flag )
    DUP _O2TRQ.MAGIC @ _O2TRQ-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP _O2TRQ.PHASE @ _O2TRQ-PHASE? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2TRQ.BORROWED @ _O2TRQ-BOOLEAN? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2TRQ.ISSUER-REQUIRED @ _O2TRQ-BOOLEAN? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2TRQ.BINDING-U @ O2CODE-BINDING-CAPACITY
        _O2TRQ-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2TRQ.ISSUER-U @ O2CODE-ISSUER-CAPACITY
        _O2TRQ-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2TRQ.CODE-U @ O2CODE-CODE-CAPACITY
        _O2TRQ-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    _O2TRQ.HTU-U @ O2TREQ-HTU-CAPACITY
    _O2TRQ-BOUNDED-LENGTH? ;

: _O2TRQ-CLEAN-SHAPE?  ( object -- flag )
    DUP _O2TRQ.BORROWED @ 0=
    OVER _O2TRQ.ISSUER-REQUIRED @ 0= AND
    OVER _O2TRQ.BINDING-U @ 0= AND
    OVER _O2TRQ.ISSUER-U @ 0= AND
    OVER _O2TRQ.CODE-U @ 0= AND
    SWAP _O2TRQ.HTU-U @ 0= AND ;

: _O2TRQ-LIVE-SHAPE?  ( object -- flag )
    DUP _O2TRQ.BINDING-U @ O2CODE-BINDING-CAPACITY
        _O2TRQ-REQUIRED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2TRQ.ISSUER-U @ O2CODE-ISSUER-CAPACITY
        _O2TRQ-REQUIRED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2TRQ.CODE-U @ O2CODE-CODE-CAPACITY
        _O2TRQ-REQUIRED-LENGTH? 0= IF DROP 0 EXIT THEN
    _O2TRQ.HTU-U @ O2TREQ-HTU-CAPACITY
    _O2TRQ-REQUIRED-LENGTH? ;

: _O2TRQ-OBJECT-SHAPE?  ( object -- flag )
    DUP _O2TRQ.PHASE @
    DUP O2TREQ-PHASE-EMPTY = IF
        DROP _O2TRQ-CLEAN-SHAPE? EXIT
    THEN
    DUP O2TREQ-PHASE-TERMINAL = IF
        DROP _O2TRQ-CLEAN-SHAPE? EXIT
    THEN
    DROP _O2TRQ-LIVE-SHAPE? ;

: _O2TRQ-OBJECT-STATUS  ( object -- status )
    DUP 0= IF DROP O2TREQ-S-INVALID EXIT THEN
    DUP 7 AND IF DROP O2TREQ-S-INVALID EXIT THEN
    DUP O2TREQ-SIZE _O2TRQ-ADMIT-SPAN
    ?DUP IF NIP EXIT THEN
    DUP _O2TRQ-OBJECT-BASIC? 0= IF
        DROP O2TREQ-S-INVALID EXIT
    THEN
    _O2TRQ-OBJECT-SHAPE?
    IF O2TREQ-S-OK ELSE O2TREQ-S-INVALID THEN ;

: _O2TRQ-INITIALIZE  ( object -- )
    DUP O2TREQ-SIZE 0 FILL
    _O2TRQ-MAGIC-VALUE OVER _O2TRQ.MAGIC !
    O2TREQ-PHASE-EMPTY SWAP _O2TRQ.PHASE ! ;

: _O2TRQ-PUBLISH-TERMINAL  ( object -- )
    DUP O2TREQ-SIZE 0 FILL
    _O2TRQ-MAGIC-VALUE OVER _O2TRQ.MAGIC !
    O2TREQ-PHASE-TERMINAL SWAP _O2TRQ.PHASE ! ;

\ =====================================================================
\  Initialization and lifecycle inspection
\ =====================================================================

: O2TREQ-INIT?  ( object -- status )
    DUP 0= IF DROP O2TREQ-S-INVALID EXIT THEN
    DUP 7 AND IF DROP O2TREQ-S-INVALID EXIT THEN
    DUP O2TREQ-SIZE _O2TRQ-ADMIT-SPAN
    ?DUP IF NIP EXIT THEN
    DUP _O2TRQ-OBJECT-BASIC? IF
        DUP _O2TRQ-OBJECT-SHAPE? IF
            DUP _O2TRQ.BORROWED @ IF
                DROP O2TREQ-S-BUSY EXIT
            THEN
            DUP _O2TRQ.PHASE @
            DUP O2TREQ-PHASE-EMPTY <>
            SWAP O2TREQ-PHASE-TERMINAL <> AND IF
                DROP O2TREQ-S-PHASE EXIT
            THEN
        THEN
    THEN
    _O2TRQ-INITIALIZE O2TREQ-S-OK ;

: O2TREQ-INIT  ( object -- )
    O2TREQ-INIT? DROP ;

: O2TREQ-CLEAR?  ( object -- status )
    DUP _O2TRQ-OBJECT-STATUS ?DUP IF NIP EXIT THEN
    DUP _O2TRQ.BORROWED @ IF DROP O2TREQ-S-BUSY EXIT THEN
    DUP _O2TRQ.PHASE @
    DUP O2TREQ-PHASE-EMPTY =
    SWAP O2TREQ-PHASE-TERMINAL = OR 0= IF
        DROP O2TREQ-S-PHASE EXIT
    THEN
    _O2TRQ-INITIALIZE O2TREQ-S-OK ;

: O2TREQ-CLEAR  ( object -- )
    O2TREQ-CLEAR? DROP ;

: O2TREQ-PHASE@  ( object -- phase status )
    DUP _O2TRQ-OBJECT-STATUS ?DUP IF
        >R DROP 0 R> EXIT
    THEN
    _O2TRQ.PHASE @ O2TREQ-S-OK ;

\ =====================================================================
\  Capture of one consumed authorization-code grant
\ =====================================================================

: _O2TRQ-DROP3  ( x1 x2 x3 -- )
    DROP 2DROP ;

: _O2TRQ-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _O2TRQ-DROP12
  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 -- )
    2DROP 2DROP 2DROP 2DROP 2DROP 2DROP ;

: _O2TRQ-3DUP  ( x1 x2 x3 -- x1 x2 x3 x1 x2 x3 )
    2 PICK 2 PICK 2 PICK ;

: _O2TRQ-4DUP
  ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 x3 x4 )
    3 PICK 3 PICK 3 PICK 3 PICK ;

: _O2TRQ-COPY-TEXT
  ( source source-u destination length-field -- )
    >R
    OVER R@ !
    R> DROP
    SWAP MOVE ;

: _O2TRQ-COPY-BYTES  ( source source-u destination -- )
    SWAP MOVE ;

: _O2TRQ-O2CODE>STATUS  ( code-status -- request-status )
    DUP O2CODE-S-OK = IF DROP O2TREQ-S-OK EXIT THEN
    DUP O2CODE-S-INVALID = IF DROP O2TREQ-S-INVALID EXIT THEN
    DUP O2CODE-S-CAPACITY = IF DROP O2TREQ-S-CAPACITY EXIT THEN
    DUP O2CODE-S-ALIAS = IF DROP O2TREQ-S-ALIAS EXIT THEN
    DUP O2CODE-S-PHASE = IF DROP O2TREQ-S-PHASE EXIT THEN
    DUP O2CODE-S-BUSY = IF DROP O2TREQ-S-BUSY EXIT THEN
    DUP O2CODE-S-CALLBACK = IF DROP O2TREQ-S-CALLBACK EXIT THEN
    DUP O2CODE-S-RANGE = IF DROP O2TREQ-S-RANGE EXIT THEN
    DUP O2CODE-S-PROTECTED = IF DROP O2TREQ-S-PROTECTED EXIT THEN
    DUP O2CODE-S-PLATFORM = IF DROP O2TREQ-S-PLATFORM EXIT THEN
    DROP O2TREQ-S-AUTHORIZATION-CODE ;

: _O2TRQ-CAPTURE-GEOMETRY
  ( token-htu token-htu-u authcode object -- status )
    DUP _O2TRQ-OBJECT-STATUS ?DUP IF
        >R _O2TRQ-DROP4 R> EXIT
    THEN
    DUP _O2TRQ.BORROWED @ IF
        _O2TRQ-DROP4 O2TREQ-S-BUSY EXIT
    THEN
    DUP _O2TRQ.PHASE @ O2TREQ-PHASE-EMPTY <> IF
        _O2TRQ-DROP4 O2TREQ-S-PHASE EXIT
    THEN

    1 PICK O2CODE-PHASE@
    DUP IF
        >R DROP _O2TRQ-DROP4
        R> _O2TRQ-O2CODE>STATUS EXIT
    THEN
    DROP
    O2CODE-PHASE-CODE-READY <> IF
        _O2TRQ-DROP4 O2TREQ-S-PHASE EXIT
    THEN

    2 PICK DUP 0> SWAP O2TREQ-HTU-CAPACITY <= AND 0= IF
        _O2TRQ-DROP4 O2TREQ-S-CAPACITY EXIT
    THEN
    3 PICK 3 PICK _O2TRQ-ADMIT-SPAN ?DUP IF
        >R _O2TRQ-DROP4 R> EXIT
    THEN

    1 PICK O2CODE-TRANSACTION-SIZE
    2 PICK O2TREQ-SIZE MSPAN-OVERLAP? IF
        _O2TRQ-DROP4 O2TREQ-S-ALIAS EXIT
    THEN
    3 PICK 3 PICK
    2 PICK O2TREQ-SIZE MSPAN-OVERLAP? IF
        _O2TRQ-DROP4 O2TREQ-S-ALIAS EXIT
    THEN
    3 PICK 3 PICK
    3 PICK O2CODE-TRANSACTION-SIZE MSPAN-OVERLAP? IF
        _O2TRQ-DROP4 O2TREQ-S-ALIAS EXIT
    THEN
    _O2TRQ-DROP4 O2TREQ-S-OK ;

: _O2TRQ-CAPTURE-CALLBACK
  \ Receives the complete O2CODE-WITH-GRANT loan.
  \ ( context binding binding-u issuer issuer-u issuer-required
  \   state state-u code code-u verifier verifier-u -- callback-status )
    11 PICK >R
    10 PICK 10 PICK
        R@ _O2TRQ.BINDING R@ _O2TRQ.BINDING-U
        _O2TRQ-COPY-TEXT
    8 PICK 8 PICK
        R@ _O2TRQ.ISSUER R@ _O2TRQ.ISSUER-U
        _O2TRQ-COPY-TEXT
    6 PICK R@ _O2TRQ.ISSUER-REQUIRED !
    5 PICK 5 PICK R@ _O2TRQ.STATE _O2TRQ-COPY-BYTES
    3 PICK 3 PICK
        R@ _O2TRQ.CODE R@ _O2TRQ.CODE-U
        _O2TRQ-COPY-TEXT
    1 PICK 1 PICK R@ _O2TRQ.VERIFIER _O2TRQ-COPY-BYTES
    O2TREQ-PHASE-READY R@ _O2TRQ.PHASE !
    R> DROP
    _O2TRQ-DROP12
    O2TREQ-S-OK ;

: O2TREQ-CAPTURE
  ( token-htu token-htu-u authcode object -- status )
    _O2TRQ-4DUP _O2TRQ-CAPTURE-GEOMETRY
    DUP IF
        >R _O2TRQ-DROP4 R> EXIT
    THEN
    DROP

    1 PICK >R
    DUP >R
    2 PICK R@ _O2TRQ.HTU-U !
    3 PICK R@ _O2TRQ.HTU 4 PICK MOVE
    _O2TRQ-DROP4

    ['] _O2TRQ-CAPTURE-CALLBACK
    R> R>
    1 PICK >R
    O2CODE-WITH-GRANT
    DUP IF
        R@ _O2TRQ-INITIALIZE
        _O2TRQ-O2CODE>STATUS
    THEN
    R> DROP ;

\ =====================================================================
\  Guarded build loan and the sole retry transition
\ =====================================================================

-17431 CONSTANT _O2TRQ-E-CALLBACK-STACK

: _O2TRQ-ATTEMPT@  ( object -- attempt )
    _O2TRQ.PHASE @
    DUP O2TREQ-PHASE-READY =
    OVER O2TREQ-PHASE-FIRST-AWAITING = OR IF
        DROP O2TREQ-ATTEMPT-FIRST EXIT
    THEN
    DROP O2TREQ-ATTEMPT-RETRY ;

: _O2TRQ-BORROW-BASE-STATUS
  ( callback context object -- status )
    2 PICK 0= IF
        _O2TRQ-DROP3 O2TREQ-S-INVALID EXIT
    THEN
    DUP _O2TRQ-OBJECT-STATUS ?DUP IF
        >R _O2TRQ-DROP3 R> EXIT
    THEN
    DUP _O2TRQ.BORROWED @ IF
        _O2TRQ-DROP3 O2TREQ-S-BUSY EXIT
    THEN
    _O2TRQ-DROP3 O2TREQ-S-OK ;

: _O2TRQ-BUILD-STATUS
  ( callback context object -- status )
    _O2TRQ-3DUP _O2TRQ-BORROW-BASE-STATUS
    DUP IF
        >R _O2TRQ-DROP3 R> EXIT
    THEN
    DROP
    DUP _O2TRQ.PHASE @ _O2TRQ-READY-PHASE? 0= IF
        _O2TRQ-DROP3 O2TREQ-S-PHASE EXIT
    THEN
    _O2TRQ-DROP3 O2TREQ-S-OK ;

: _O2TRQ-BUILD-CALLBACK-RUN
  \ callback receives
  \ ( context binding binding-u issuer issuer-u issuer-required
  \   state state-u code code-u verifier verifier-u token-htu token-htu-u
  \   attempt -- callback-status )
  \ stack effect here is ( callback context object -- callback-status )
    DEPTH 2 - >R
    ROT >R
    >R
    R@ _O2TRQ.BINDING
    R@ _O2TRQ.BINDING-U @
    R@ _O2TRQ.ISSUER
    R@ _O2TRQ.ISSUER-U @
    R@ _O2TRQ.ISSUER-REQUIRED @
    R@ _O2TRQ.STATE
    O2CODE-STATE-SIZE
    R@ _O2TRQ.CODE
    R@ _O2TRQ.CODE-U @
    R@ _O2TRQ.VERIFIER
    O2CODE-VERIFIER-SIZE
    R@ _O2TRQ.HTU
    R@ _O2TRQ.HTU-U @
    R@ _O2TRQ-ATTEMPT@
    R> DROP
    R> EXECUTE
    DEPTH R> <> IF
        _O2TRQ-E-CALLBACK-STACK THROW
    THEN ;

: _O2TRQ-PUBLISH-AWAITING  ( object -- )
    DUP _O2TRQ.PHASE @ O2TREQ-PHASE-READY = IF
        O2TREQ-PHASE-FIRST-AWAITING SWAP _O2TRQ.PHASE !
    ELSE
        O2TREQ-PHASE-RETRY-AWAITING SWAP _O2TRQ.PHASE !
    THEN ;

: _O2TRQ-WITH-BUILD-CALL
  ( callback context object -- callback-status-or-request-status )
    DUP >R
    -1 R@ _O2TRQ.BORROWED !
    ['] _O2TRQ-BUILD-CALLBACK-RUN CATCH
    DUP IF
        DROP _O2TRQ-DROP3
        0 R@ _O2TRQ.BORROWED !
        R> DROP
        O2TREQ-S-CALLBACK EXIT
    THEN
    DROP
    DUP 0= IF R@ _O2TRQ-PUBLISH-AWAITING THEN
    0 R@ _O2TRQ.BORROWED !
    R> DROP ;

: O2TREQ-WITH-BUILD
  ( callback context object -- callback-status-or-request-status )
    _O2TRQ-3DUP _O2TRQ-BUILD-STATUS
    DUP IF
        >R _O2TRQ-DROP3 R> EXIT
    THEN
    DROP
    _O2TRQ-WITH-BUILD-CALL ;

: O2TREQ-CLAIM-RETRY  ( object -- status )
    DUP _O2TRQ-OBJECT-STATUS ?DUP IF NIP EXIT THEN
    DUP _O2TRQ.BORROWED @ IF DROP O2TREQ-S-BUSY EXIT THEN
    DUP _O2TRQ.PHASE @
        O2TREQ-PHASE-FIRST-AWAITING <> IF
        DROP O2TREQ-S-PHASE EXIT
    THEN
    O2TREQ-PHASE-RETRY-READY SWAP _O2TRQ.PHASE !
    O2TREQ-S-OK ;

\ =====================================================================
\  Awaiting-response provenance borrow
\ =====================================================================

: _O2TRQ-PROVENANCE-STATUS
  ( callback context object -- status )
    _O2TRQ-3DUP _O2TRQ-BORROW-BASE-STATUS
    DUP IF
        >R _O2TRQ-DROP3 R> EXIT
    THEN
    DROP
    DUP _O2TRQ.PHASE @ _O2TRQ-AWAITING-PHASE? 0= IF
        _O2TRQ-DROP3 O2TREQ-S-PHASE EXIT
    THEN
    _O2TRQ-DROP3 O2TREQ-S-OK ;

: _O2TRQ-PROVENANCE-CALLBACK-RUN
  \ callback receives
  \ ( context binding binding-u issuer issuer-u issuer-required
  \   state state-u token-htu token-htu-u attempt -- callback-status )
  \ stack effect here is ( callback context object -- callback-status )
    DEPTH 2 - >R
    ROT >R
    >R
    R@ _O2TRQ.BINDING
    R@ _O2TRQ.BINDING-U @
    R@ _O2TRQ.ISSUER
    R@ _O2TRQ.ISSUER-U @
    R@ _O2TRQ.ISSUER-REQUIRED @
    R@ _O2TRQ.STATE
    O2CODE-STATE-SIZE
    R@ _O2TRQ.HTU
    R@ _O2TRQ.HTU-U @
    R@ _O2TRQ-ATTEMPT@
    R> DROP
    R> EXECUTE
    DEPTH R> <> IF
        _O2TRQ-E-CALLBACK-STACK THROW
    THEN ;

: _O2TRQ-WITH-PROVENANCE-CALL
  ( callback context object -- callback-status-or-request-status )
    DUP >R
    -1 R@ _O2TRQ.BORROWED !
    ['] _O2TRQ-PROVENANCE-CALLBACK-RUN CATCH
    DUP IF
        DROP _O2TRQ-DROP3
        0 R@ _O2TRQ.BORROWED !
        R> DROP
        O2TREQ-S-CALLBACK EXIT
    THEN
    DROP
    0 R@ _O2TRQ.BORROWED !
    R> DROP ;

: O2TREQ-WITH-PROVENANCE
  ( callback context object -- callback-status-or-request-status )
    _O2TRQ-3DUP _O2TRQ-PROVENANCE-STATUS
    DUP IF
        >R _O2TRQ-DROP3 R> EXIT
    THEN
    DROP
    _O2TRQ-WITH-PROVENANCE-CALL ;

\ =====================================================================
\  Terminal and abandonment transitions
\ =====================================================================

: O2TREQ-TERMINAL  ( object -- status )
    DUP _O2TRQ-OBJECT-STATUS ?DUP IF NIP EXIT THEN
    DUP _O2TRQ.BORROWED @ IF DROP O2TREQ-S-BUSY EXIT THEN
    DUP _O2TRQ.PHASE @ _O2TRQ-AWAITING-PHASE? 0= IF
        DROP O2TREQ-S-PHASE EXIT
    THEN
    _O2TRQ-PUBLISH-TERMINAL
    O2TREQ-S-OK ;

: O2TREQ-ABANDON  ( object -- status )
    DUP _O2TRQ-OBJECT-STATUS ?DUP IF NIP EXIT THEN
    DUP _O2TRQ.BORROWED @ IF DROP O2TREQ-S-BUSY EXIT THEN
    DUP _O2TRQ.PHASE @ _O2TRQ-LIVE-PHASE? 0= IF
        DROP O2TREQ-S-PHASE EXIT
    THEN
    _O2TRQ-PUBLISH-TERMINAL
    O2TREQ-S-OK ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _O2TRQ-GEOMETRY-ABORT  ( -- )
    ." OAuth token-request geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _O2TRQ-GEOMETRY-ABORT
[THEN]

O2TREQ-HTU-CAPACITY HTARGET-URI-CAPACITY <> [IF]
    _O2TRQ-GEOMETRY-ABORT
[THEN]

_O2TRQ-HTU-OFF O2TREQ-HTU-CAPACITY +
7 + -8 AND O2TREQ-SIZE <> [IF]
    _O2TRQ-GEOMETRY-ABORT
[THEN]
