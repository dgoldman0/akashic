\ =====================================================================
\  dpop-nonce.f - Issuer-bound OAuth DPoP nonce ownership
\ =====================================================================
\  One caller-owned, address-free record retains the latest nonempty
\  authorization-server DPoP nonce under an exact opaque server key.
\  Replacement is admitted completely before the old nonce is wiped, and
\  successful replacement advances a monotonic generation.
\
\  This module owns no HTTP transaction, retry decision, DPoP proof, key,
\  token, session, provider, persistence, clock, or application state.
\  A higher owner allocates and serializes one record per server
\  relationship and protects it durably when restart continuity is needed.
\ =====================================================================

PROVIDED akashic-oauth2-dpnonce

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE authorization-code.f
REQUIRE http-post.f

\ =====================================================================
\  Public status and capacity vocabulary
\ =====================================================================

0  CONSTANT OAUTH2-DPOP-NONCE-S-OK
1  CONSTANT OAUTH2-DPOP-NONCE-S-INVALID
2  CONSTANT OAUTH2-DPOP-NONCE-S-CAPACITY
3  CONSTANT OAUTH2-DPOP-NONCE-S-ALIAS
4  CONSTANT OAUTH2-DPOP-NONCE-S-STATE
5  CONSTANT OAUTH2-DPOP-NONCE-S-BINDING
6  CONSTANT OAUTH2-DPOP-NONCE-S-BUSY
7  CONSTANT OAUTH2-DPOP-NONCE-S-CALLBACK
8  CONSTANT OAUTH2-DPOP-NONCE-S-GENERATION
9  CONSTANT OAUTH2-DPOP-NONCE-S-RANGE
10 CONSTANT OAUTH2-DPOP-NONCE-S-PROTECTED
11 CONSTANT OAUTH2-DPOP-NONCE-S-PLATFORM
12 CONSTANT OAUTH2-DPOP-NONCE-S-INTERNAL

: OAUTH2-DPOP-NONCE-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-DPOP-NONCE-S-OK >=
    SWAP OAUTH2-DPOP-NONCE-S-INTERNAL <= AND ;

O2CODE-ISSUER-CAPACITY
CONSTANT OAUTH2-DPOP-NONCE-SERVER-CAPACITY

OAUTH2-HTTP-POST-NONCE-CAPACITY
CONSTANT OAUTH2-DPOP-NONCE-CAPACITY

-1 1 RSHIFT CONSTANT _O2DN-CELL-MAX

\ =====================================================================
\  Address-free nonce record
\ =====================================================================

0x4F3244504E4F4E31 CONSTANT _O2DN-MAGIC-VALUE  \ "O2DPNON1"

 0 CONSTANT _O2DN-MAGIC
 8 CONSTANT _O2DN-BORROWED
16 CONSTANT _O2DN-GENERATION
24 CONSTANT _O2DN-SERVER-U
32 CONSTANT _O2DN-NONCE-U
40 CONSTANT _O2DN-HEADER-SIZE

_O2DN-HEADER-SIZE CONSTANT _O2DN-SERVER-OFF
_O2DN-SERVER-OFF OAUTH2-DPOP-NONCE-SERVER-CAPACITY +
    CONSTANT _O2DN-NONCE-OFF
_O2DN-NONCE-OFF OAUTH2-DPOP-NONCE-CAPACITY +
7 + -8 AND CONSTANT OAUTH2-DPOP-NONCE-SIZE

: _O2DN.MAGIC  ( owner -- field ) _O2DN-MAGIC + ;
: _O2DN.BORROWED  ( owner -- field ) _O2DN-BORROWED + ;
: _O2DN.GENERATION  ( owner -- field ) _O2DN-GENERATION + ;
: _O2DN.SERVER-U  ( owner -- field ) _O2DN-SERVER-U + ;
: _O2DN.NONCE-U  ( owner -- field ) _O2DN-NONCE-U + ;

: _O2DN.SERVER  ( owner -- address ) _O2DN-SERVER-OFF + ;
: _O2DN.NONCE  ( owner -- address ) _O2DN-NONCE-OFF + ;

\ =====================================================================
\  Caller-memory, syntax, and object admission
\ =====================================================================

: _O2DN-CALLER>STATUS  ( caller-status -- status )
    CASE
        CALLER-SPAN-S-OK OF OAUTH2-DPOP-NONCE-S-OK ENDOF
        CALLER-SPAN-S-RANGE OF OAUTH2-DPOP-NONCE-S-RANGE ENDOF
        CALLER-SPAN-S-PROTECTED OF
            OAUTH2-DPOP-NONCE-S-PROTECTED
        ENDOF
        CALLER-SPAN-S-PLATFORM OF
            OAUTH2-DPOP-NONCE-S-PLATFORM
        ENDOF
        OAUTH2-DPOP-NONCE-S-PLATFORM SWAP
    ENDCASE ;

: _O2DN-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP OAUTH2-DPOP-NONCE-S-INVALID EXIT THEN
    DUP 0= IF
        DROP
        IF
            OAUTH2-DPOP-NONCE-S-INVALID
        ELSE
            OAUTH2-DPOP-NONCE-S-OK
        THEN
        EXIT
    THEN
    OVER 0= IF 2DROP OAUTH2-DPOP-NONCE-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _O2DN-CALLER>STATUS ;

: _O2DN-FIXED-STATUS  ( address length -- status )
    OVER 0= IF 2DROP OAUTH2-DPOP-NONCE-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP OAUTH2-DPOP-NONCE-S-INVALID EXIT THEN
    _O2DN-SPAN-STATUS ;

: _O2DN-BOOLEAN?  ( value -- flag )
    DUP 0= SWAP -1 = OR ;

: _O2DN-REQUIRED-LENGTH-STATUS  ( length capacity -- status )
    OVER 1 < IF
        2DROP OAUTH2-DPOP-NONCE-S-INVALID EXIT
    THEN
    U> IF
        OAUTH2-DPOP-NONCE-S-CAPACITY
    ELSE
        OAUTH2-DPOP-NONCE-S-OK
    THEN ;

: _O2DN-NQCHAR?  ( byte -- flag )
    DUP 33 = IF DROP -1 EXIT THEN
    DUP 35 92 WITHIN IF DROP -1 EXIT THEN
    93 127 WITHIN ;

: _O2DN-NONCE-SYNTAX?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ _O2DN-NQCHAR? 0= IF
            2DROP 0 EXIT
        THEN
        1 /STRING
    REPEAT
    2DROP -1 ;

: _O2DN-OBJECT-SHAPE?  ( owner -- flag )
    DUP _O2DN.MAGIC @ _O2DN-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP _O2DN.BORROWED @ _O2DN-BOOLEAN? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2DN.GENERATION @
    DUP 0> SWAP _O2DN-CELL-MAX U> 0= AND 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2DN.SERVER-U @
    OAUTH2-DPOP-NONCE-SERVER-CAPACITY
    _O2DN-REQUIRED-LENGTH-STATUS
    OAUTH2-DPOP-NONCE-S-OK <> IF
        DROP 0 EXIT
    THEN
    DUP _O2DN.NONCE-U @
    OAUTH2-DPOP-NONCE-CAPACITY
    _O2DN-REQUIRED-LENGTH-STATUS
    OAUTH2-DPOP-NONCE-S-OK <> IF
        DROP 0 EXIT
    THEN
    DUP _O2DN.NONCE
    SWAP _O2DN.NONCE-U @
    _O2DN-NONCE-SYNTAX? ;

: _O2DN-OBJECT-STATUS  ( owner -- status )
    DUP OAUTH2-DPOP-NONCE-SIZE _O2DN-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _O2DN-OBJECT-SHAPE?
    IF
        OAUTH2-DPOP-NONCE-S-OK
    ELSE
        OAUTH2-DPOP-NONCE-S-INVALID
    THEN ;

: OAUTH2-DPOP-NONCE-VALID?  ( owner -- flag )
    _O2DN-OBJECT-STATUS OAUTH2-DPOP-NONCE-S-OK = ;

\ =====================================================================
\  Input geometry and exact server binding
\ =====================================================================

: _O2DN-DROP5  ( x1 x2 x3 x4 x5 -- )
    2DROP 2DROP DROP ;

: _O2DN-5DUP
  ( x1 x2 x3 x4 x5 -- x1 x2 x3 x4 x5 x1 x2 x3 x4 x5 )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK ;

: _O2DN-RETURN5  ( x1 x2 x3 x4 x5 status -- status )
    >R _O2DN-DROP5 R> ;

: _O2DN-SOURCE-GEOMETRY
  ( server-a server-u nonce-a nonce-u owner -- status )
    3 PICK
    OAUTH2-DPOP-NONCE-SERVER-CAPACITY
    _O2DN-REQUIRED-LENGTH-STATUS
    ?DUP IF _O2DN-RETURN5 EXIT THEN
    1 PICK
    OAUTH2-DPOP-NONCE-CAPACITY
    _O2DN-REQUIRED-LENGTH-STATUS
    ?DUP IF _O2DN-RETURN5 EXIT THEN

    4 PICK 4 PICK _O2DN-SPAN-STATUS
    ?DUP IF _O2DN-RETURN5 EXIT THEN
    2 PICK 2 PICK _O2DN-SPAN-STATUS
    ?DUP IF _O2DN-RETURN5 EXIT THEN

    2 PICK 2 PICK _O2DN-NONCE-SYNTAX? 0= IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-INVALID EXIT
    THEN

    4 PICK 4 PICK 2 PICK OAUTH2-DPOP-NONCE-SIZE
    MSPAN-OVERLAP? IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-ALIAS EXIT
    THEN
    2 PICK 2 PICK 2 PICK OAUTH2-DPOP-NONCE-SIZE
    MSPAN-OVERLAP? IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-ALIAS EXIT
    THEN
    _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-OK ;

: _O2DN-SERVER-MATCH?
  ( server-a server-u owner -- flag )
    >R
    R@ _O2DN.SERVER
    R> _O2DN.SERVER-U @
    COMPARE 0= ;

: _O2DN-PUBLISH
  ( server-a server-u nonce-a nonce-u generation owner -- )
    >R
    R@ OAUTH2-DPOP-NONCE-SIZE 0 FILL
    DUP R@ _O2DN.GENERATION !
    DROP
    DUP R@ _O2DN.NONCE-U !
    R@ _O2DN.NONCE SWAP MOVE
    DUP R@ _O2DN.SERVER-U !
    R@ _O2DN.SERVER SWAP MOVE
    _O2DN-MAGIC-VALUE R@ _O2DN.MAGIC !
    R> DROP ;

\ =====================================================================
\  Atomic initialization and nonce replacement
\ =====================================================================

: OAUTH2-DPOP-NONCE-INIT
  ( server-a server-u nonce-a nonce-u owner -- status )
    _O2DN-5DUP _O2DN-SOURCE-GEOMETRY
    ?DUP IF _O2DN-RETURN5 EXIT THEN
    DUP OAUTH2-DPOP-NONCE-SIZE _O2DN-FIXED-STATUS
    ?DUP IF _O2DN-RETURN5 EXIT THEN
    DUP _O2DN-OBJECT-SHAPE? IF
        DUP _O2DN.BORROWED @ IF
            _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-BUSY EXIT
        THEN
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-STATE EXIT
    THEN
    1 SWAP _O2DN-PUBLISH
    OAUTH2-DPOP-NONCE-S-OK ;

: OAUTH2-DPOP-NONCE-REPLACE
  ( server-a server-u nonce-a nonce-u owner -- status )
    DUP _O2DN-OBJECT-STATUS ?DUP IF
        _O2DN-RETURN5 EXIT
    THEN
    DUP _O2DN.BORROWED @ IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-BUSY EXIT
    THEN
    _O2DN-5DUP _O2DN-SOURCE-GEOMETRY
    ?DUP IF _O2DN-RETURN5 EXIT THEN
    4 PICK 4 PICK 2 PICK _O2DN-SERVER-MATCH? 0= IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-BINDING EXIT
    THEN
    DUP _O2DN.GENERATION @ _O2DN-CELL-MAX = IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-GENERATION EXIT
    THEN

    >R
    R@ _O2DN.NONCE OAUTH2-DPOP-NONCE-CAPACITY 0 FILL
    0 R@ _O2DN.NONCE-U !
    DUP R@ _O2DN.NONCE-U !
    R@ _O2DN.NONCE SWAP MOVE
    R@ _O2DN.GENERATION @ 1+
    R@ _O2DN.GENERATION !
    2DROP
    R> DROP
    OAUTH2-DPOP-NONCE-S-OK ;

\ =====================================================================
\  Guarded nonce borrow
\ =====================================================================

-17447 CONSTANT _O2DN-E-CALLBACK-STACK

: _O2DN-WITH-GEOMETRY
  ( callback context server-a server-u owner -- status )
    4 PICK 0= IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-INVALID EXIT
    THEN
    DUP _O2DN-OBJECT-STATUS ?DUP IF
        _O2DN-RETURN5 EXIT
    THEN
    DUP _O2DN.BORROWED @ IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-BUSY EXIT
    THEN
    1 PICK
    OAUTH2-DPOP-NONCE-SERVER-CAPACITY
    _O2DN-REQUIRED-LENGTH-STATUS
    ?DUP IF _O2DN-RETURN5 EXIT THEN
    2 PICK 2 PICK _O2DN-SPAN-STATUS
    ?DUP IF _O2DN-RETURN5 EXIT THEN
    2 PICK 2 PICK 2 PICK OAUTH2-DPOP-NONCE-SIZE
    MSPAN-OVERLAP? IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-ALIAS EXIT
    THEN
    2 PICK 2 PICK 2 PICK _O2DN-SERVER-MATCH? 0= IF
        _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-BINDING EXIT
    THEN
    _O2DN-DROP5 OAUTH2-DPOP-NONCE-S-OK ;

: _O2DN-CALLBACK-RUN
  \ callback receives
  \   ( nonce-a nonce-u generation context -- callback-result )
  \ stack effect here is ( callback context owner -- callback-result )
    DEPTH 2 - >R
    ROT >R
    SWAP >R
    DUP _O2DN.NONCE
    OVER _O2DN.NONCE-U @
    2 PICK _O2DN.GENERATION @
    3 ROLL DROP
    R>
    R> EXECUTE
    DEPTH R> <> IF
        _O2DN-E-CALLBACK-STACK THROW
    THEN ;

: _O2DN-WITH-CALL
  ( callback context owner -- callback-result status )
    DUP >R
    -1 R@ _O2DN.BORROWED !
    ['] _O2DN-CALLBACK-RUN CATCH
    DUP IF
        DROP
        DROP 2DROP
        0 R@ _O2DN.BORROWED !
        R> DROP
        0 OAUTH2-DPOP-NONCE-S-CALLBACK EXIT
    THEN
    DROP
    0 R@ _O2DN.BORROWED !
    R> DROP
    OAUTH2-DPOP-NONCE-S-OK ;

: OAUTH2-DPOP-NONCE-WITH
  \ ( callback context server-a server-u owner
  \   -- callback-result status )
    _O2DN-5DUP _O2DN-WITH-GEOMETRY
    ?DUP IF
        >R _O2DN-DROP5 0 R> EXIT
    THEN
    >R 2DROP R>
    _O2DN-WITH-CALL ;

\ =====================================================================
\  Generation and explicit destruction
\ =====================================================================

: OAUTH2-DPOP-NONCE-GENERATION@
  ( owner -- generation status )
    DUP _O2DN-OBJECT-STATUS ?DUP IF
        >R DROP 0 R> EXIT
    THEN
    _O2DN.GENERATION @ OAUTH2-DPOP-NONCE-S-OK ;

: OAUTH2-DPOP-NONCE-WIPE  ( owner -- status )
    DUP OAUTH2-DPOP-NONCE-SIZE _O2DN-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    DUP _O2DN-OBJECT-SHAPE? IF
        DUP _O2DN.BORROWED @ IF
            DROP OAUTH2-DPOP-NONCE-S-BUSY EXIT
        THEN
    THEN
    OAUTH2-DPOP-NONCE-SIZE 0 FILL
    OAUTH2-DPOP-NONCE-S-OK ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _O2DN-GEOMETRY-ABORT  ( -- )
    ." OAuth DPoP nonce geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _O2DN-GEOMETRY-ABORT
[THEN]

OAUTH2-DPOP-NONCE-SERVER-CAPACITY
O2CODE-ISSUER-CAPACITY <> [IF]
    _O2DN-GEOMETRY-ABORT
[THEN]

OAUTH2-DPOP-NONCE-CAPACITY
OAUTH2-HTTP-POST-NONCE-CAPACITY <> [IF]
    _O2DN-GEOMETRY-ABORT
[THEN]

_O2DN-NONCE-OFF OAUTH2-DPOP-NONCE-CAPACITY +
7 + -8 AND OAUTH2-DPOP-NONCE-SIZE <> [IF]
    _O2DN-GEOMETRY-ABORT
[THEN]
