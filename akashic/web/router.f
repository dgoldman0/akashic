\ router.f — Path → handler dispatch for KDOS / Megapad-64
\
\ Register routes with method + pattern + handler xt.
\ Match incoming requests, extract path parameters, dispatch.
\
\ Prefix: ROUTE-  (public API)
\         _ROUTE- (internal helpers)
\
\ Load with:   REQUIRE router.f

REQUIRE ../utils/table.f
REQUIRE ../utils/string.f
REQUIRE ../web/request.f
REQUIRE ../web/response.f

PROVIDED akashic-web-router

\ =====================================================================
\  Layer 0 — Route Table
\ =====================================================================
\
\  Route record layout (stored in TBL slot data area):
\    +0   method-a   (8 bytes, cell)
\    +8   method-u   (8 bytes, cell)
\    +16  pattern-a  (8 bytes, cell)
\    +24  pattern-u  (8 bytes, cell)
\    +32  handler-xt (8 bytes, cell)
\    = 40 bytes per route

40 CONSTANT _ROUTE-RECSZ

\ Route table: 64 slots × 40 bytes.  Allocate inline.
\ Header = 24 bytes, stride = 1 + 40 = 41, total = 24 + 64*41 = 2648
CREATE _ROUTE-TBL 2648 ALLOT

\ Initialise route table at load time.
_ROUTE-RECSZ 64 _ROUTE-TBL TBL-CREATE

\ ── Field accessors (slot-addr → field) ──

: _ROUTE-F-METH-A  ( slot -- addr )  ;          \ +0
: _ROUTE-F-METH-U  ( slot -- addr )  8 + ;      \ +8
: _ROUTE-F-PAT-A   ( slot -- addr )  16 + ;     \ +16
: _ROUTE-F-PAT-U   ( slot -- addr )  24 + ;     \ +24
: _ROUTE-F-XT      ( slot -- addr )  32 + ;     \ +32

\ ROUTE ( method-a method-u pattern-a pattern-u xt -- )
\   Register a new route.
VARIABLE _ROUTE-SLOT

: ROUTE  ( method-a method-u pattern-a pattern-u xt -- )
    >R >R >R >R >R
    _ROUTE-TBL TBL-ALLOC DUP 0= IF
        DROP R> R> R> R> R> 2DROP 2DROP DROP EXIT
    THEN
    _ROUTE-SLOT !
    R> _ROUTE-SLOT @ _ROUTE-F-METH-A !
    R> _ROUTE-SLOT @ _ROUTE-F-METH-U !
    R> _ROUTE-SLOT @ _ROUTE-F-PAT-A !
    R> _ROUTE-SLOT @ _ROUTE-F-PAT-U !
    R> _ROUTE-SLOT @ _ROUTE-F-XT ! ;

\ Convenience registration words
: ROUTE-GET     ( pat-a pat-u xt -- )  >R S" GET"    2SWAP R> ROUTE ;
: ROUTE-POST    ( pat-a pat-u xt -- )  >R S" POST"   2SWAP R> ROUTE ;
: ROUTE-PUT     ( pat-a pat-u xt -- )  >R S" PUT"    2SWAP R> ROUTE ;
: ROUTE-DELETE  ( pat-a pat-u xt -- )  >R S" DELETE" 2SWAP R> ROUTE ;

\ ROUTE-COUNT ( -- n )
\   Number of registered routes.
: ROUTE-COUNT  ( -- n )  _ROUTE-TBL TBL-COUNT ;

\ ROUTE-CLEAR ( -- )
\   Remove all routes.
: ROUTE-CLEAR  ( -- )  _ROUTE-TBL TBL-FLUSH ;

\ =====================================================================
\  Layer 1 — Path Parameters (storage)
\ =====================================================================
\
\ Captured params: 8 slots, each = name(addr+len) + value(addr+len) = 32B
\ All zero-copy pointers into the pattern and request path strings.

8 CONSTANT _ROUTE-MAX-PARAMS
CREATE _ROUTE-PARAMS  256 ALLOT   \ 8 × 32 bytes
VARIABLE _ROUTE-NPARAMS

: _ROUTE-PARAM-CLEAR  ( -- )  0 _ROUTE-NPARAMS ! ;

\ _ROUTE-PARAM-ADD ( name-a name-u val-a val-u -- )
\   Store a captured parameter.
VARIABLE _ROUTE-PP

: _ROUTE-PARAM-ADD  ( name-a name-u val-a val-u -- )
    _ROUTE-NPARAMS @ _ROUTE-MAX-PARAMS >= IF 2DROP 2DROP EXIT THEN
    _ROUTE-NPARAMS @ 32 * _ROUTE-PARAMS + _ROUTE-PP !
    _ROUTE-PP @ 24 + !         \ val-u
    _ROUTE-PP @ 16 + !         \ val-a
    _ROUTE-PP @ 8 + !          \ name-u
    _ROUTE-PP @ !              \ name-a
    1 _ROUTE-NPARAMS +! ;

\ ROUTE-PARAM ( name-a name-u -- val-a val-u )
\   Look up a captured path parameter by name.  Returns 0 0 if not found.
VARIABLE _ROUTE-LP-I

: ROUTE-PARAM  ( name-a name-u -- val-a val-u )
    _ROUTE-NPARAMS @ 0 ?DO
        2DUP
        I 32 * _ROUTE-PARAMS +          \ param record addr
        DUP @ SWAP 8 + @                \ name-a name-u
        STR-STR=
        IF
            2DROP
            I 32 * _ROUTE-PARAMS + 16 +
            DUP @ SWAP 8 + @            \ val-a val-u
            UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 0 ;

\ ROUTE-PARAM? ( name-a name-u -- flag )
: ROUTE-PARAM?  ( name-a name-u -- flag )
    ROUTE-PARAM NIP 0<> ;

\ =====================================================================
\  Layer 2 — Pattern Matching
\ =====================================================================

\ _ROUTE-NEXT-SEG ( addr len -- seg-a seg-u rest-a rest-u )
\   Split path at next '/'.  Skips leading '/'.
\   "/"        → "" 0 "" 0
\   "/foo"     → "foo" 3 "" 0
\   "/foo/bar" → "foo" 3 "/bar" 4

: _ROUTE-NEXT-SEG  ( addr len -- seg-a seg-u rest-a rest-u )
    \ Skip leading '/'
    DUP 0> IF OVER C@ 47 = IF 1 /STRING THEN THEN
    DUP 0= IF 0 0 EXIT THEN   \ empty → empty seg, empty rest
    2DUP 47 STR-INDEX          ( addr len idx )
    DUP 0< IF
        DROP                   \ no '/' — whole thing is segment
        0 0                    \ rest is empty
    ELSE
        >R                     \ save idx
        OVER R@ + OVER R@ -   \ rest-a=addr+idx  rest-u=len-idx
        2SWAP DROP R>          \ seg-a=addr  seg-u=idx
        2SWAP
    THEN ;

\ _ROUTE-SEG-MATCH ( pat-seg-a pat-seg-u path-seg-a path-seg-u -- flag )
\   Match one segment.  ':name' always matches (captures).
\   Literal requires exact STR-STR= match.
: _ROUTE-SEG-MATCH  ( pat-a pat-u seg-a seg-u -- flag )
    2SWAP
    DUP 0> IF
        OVER C@ 58 = IF   \ ':' — parameter capture
            \ name = pat+1, name-u = pat-u-1
            1 /STRING      ( seg-a seg-u name-a name-u )
            2SWAP          ( name-a name-u seg-a seg-u )
            _ROUTE-PARAM-ADD
            -1 EXIT
        THEN
    THEN
    2SWAP STR-STR= ;

\ _ROUTE-PATTERN-MATCH ( pat-a pat-u path-a path-u -- flag )
\   Match full pattern against full path, segment by segment.
\   Uses variables to avoid fragile stack gymnastics.
VARIABLE _RPM-PA   VARIABLE _RPM-PU    \ pattern remainder
VARIABLE _RPM-HA   VARIABLE _RPM-HU    \ path remainder
VARIABLE _RPM-PSA  VARIABLE _RPM-PSU   \ pattern segment
VARIABLE _RPM-HSA  VARIABLE _RPM-HSU   \ path segment

: _ROUTE-PATTERN-MATCH  ( pat-a pat-u path-a path-u -- flag )
    _RPM-HU ! _RPM-HA !  _RPM-PU ! _RPM-PA !
    _ROUTE-PARAM-CLEAR
    BEGIN
        \ Get next pattern segment → store in variables
        _RPM-PA @ _RPM-PU @ _ROUTE-NEXT-SEG
        _RPM-PU ! _RPM-PA !
        _RPM-PSU ! _RPM-PSA !

        \ Get next path segment → store in variables
        _RPM-HA @ _RPM-HU @ _ROUTE-NEXT-SEG
        _RPM-HU ! _RPM-HA !
        _RPM-HSU ! _RPM-HSA !

        \ Both segments empty? → match if both remainders exhausted
        _RPM-PSU @ 0=  _RPM-HSU @ 0=  AND IF
            _RPM-PU @ 0= _RPM-HU @ 0= AND EXIT
        THEN

        \ One empty, other not? → no match
        _RPM-PSU @ 0=  _RPM-HSU @ 0<>  AND IF 0 EXIT THEN
        _RPM-PSU @ 0<>  _RPM-HSU @ 0=  AND IF 0 EXIT THEN

        \ Match this segment pair
        _RPM-PSA @ _RPM-PSU @  _RPM-HSA @ _RPM-HSU @
        _ROUTE-SEG-MATCH
        0= IF 0 EXIT THEN

        \ Both remainders exhausted? → success
        _RPM-PU @ 0= _RPM-HU @ 0= AND IF -1 EXIT THEN
        \ One exhausted, other not? → fail
        _RPM-PU @ 0= _RPM-HU @ 0<> AND IF 0 EXIT THEN
        _RPM-PU @ 0<> _RPM-HU @ 0= AND IF 0 EXIT THEN
    AGAIN ;

\ ROUTE-MATCH ( method-a method-u path-a path-u -- xt | 0 )
\   Find first matching route.  Returns handler xt or 0.
VARIABLE _RM-MA   VARIABLE _RM-MU
VARIABLE _RM-PA   VARIABLE _RM-PU
VARIABLE _RM-RESULT

: _ROUTE-TRY-SLOT  ( slot-addr -- flag )
    DUP @ OVER 8 + @              \ method-a method-u from slot
    _RM-MA @ _RM-MU @ STR-STR=
    0= IF DROP 0 EXIT THEN        \ method mismatch
    DUP 16 + @ OVER 24 + @        \ pattern-a pattern-u
    _RM-PA @ _RM-PU @
    _ROUTE-PATTERN-MATCH
    IF 32 + @ _RM-RESULT ! -1
    ELSE DROP 0 THEN ;

: ROUTE-MATCH  ( method-a method-u path-a path-u -- xt | 0 )
    _RM-PU ! _RM-PA !  _RM-MU ! _RM-MA !
    0 _RM-RESULT !
    _ROUTE-TBL ['] _ROUTE-TRY-SLOT TBL-FIND DROP
    _RM-RESULT @ ;

\ =====================================================================
\  Layer 3 — Dispatch
\ =====================================================================

\ ROUTE-DISPATCH ( -- )
\   Read REQ-METHOD and REQ-PATH, find matching route, execute handler.
\   If no match: 404.

: ROUTE-DISPATCH  ( -- )
    REQ-METHOD REQ-PATH ROUTE-MATCH
    DUP 0= IF DROP RESP-NOT-FOUND EXIT THEN
    EXECUTE ;

\ ── Concurrency ──
\
\ All public words in this module are NOT reentrant.  They use shared
\ VARIABLE scratch space that would be corrupted by concurrent access.
\ Callers must ensure single-task access via WITH-GUARD, WITH-CRITICAL,
\ or by running with preemption disabled.
