\ =====================================================================
\  get-author-feed.f - Bounded app.bsky author-feed target builder
\ =====================================================================
\  This state-free adapter derives one authenticated
\  app.bsky.feed.getAuthorFeed HTTPS target from a canonical PDS origin.
\  It validates the actor as a DID or handle and writes the query fields
\  in deterministic Lexicon order:
\
\    actor, limit, optional cursor, filter, includePins
\
\  All operation state, query bytes, URI bytes, the form writer, and the
\  staged HTARGET live in caller-owned workspace.  The destination target
\  is byte-for-byte unchanged unless the complete URI is successfully
\  admitted and shown to retain the PDS origin.
\
\  HTARGET fixes the complete canonical URI capacity at 1024 bytes.
\  Consequently a syntactically valid long PDS origin, DID, handle, or
\  cursor can produce AT-GET-AUTHOR-FEED-S-CAPACITY.  This module adds no
\  smaller policy limit to those caller-provided values.
\
\  Public API:
\    AT-GET-AUTHOR-FEED-WORKSPACE-SIZE
\    AT-GET-AUTHOR-FEED-WORKSPACE-CLEAR
\    AT-GET-AUTHOR-FEED-STATUS-VALID?
\    AT-GET-AUTHOR-FEED-FILTER-VALID?
\    AT-GET-AUTHOR-FEED-FILTER$
\    AT-GET-AUTHOR-FEED-TARGET!
\      ( pds-target actor-a actor-u limit cursor-a cursor-u
\        filter include-pins? target workspace -- status )
\ =====================================================================

\ KDOS module identities are bounded to 23 bytes.
PROVIDED akashic-at-getauthfeed

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../net/form-urlencoded-writer.f
REQUIRE ../net/http-target.f
REQUIRE did.f
REQUIRE handle.f

\ =====================================================================
\  Public status and filter vocabulary
\ =====================================================================

0  CONSTANT AT-GET-AUTHOR-FEED-S-OK
1  CONSTANT AT-GET-AUTHOR-FEED-S-INVALID
2  CONSTANT AT-GET-AUTHOR-FEED-S-CAPACITY
3  CONSTANT AT-GET-AUTHOR-FEED-S-ALIAS
4  CONSTANT AT-GET-AUTHOR-FEED-S-PDS
5  CONSTANT AT-GET-AUTHOR-FEED-S-ACTOR
6  CONSTANT AT-GET-AUTHOR-FEED-S-LIMIT
7  CONSTANT AT-GET-AUTHOR-FEED-S-FILTER
8  CONSTANT AT-GET-AUTHOR-FEED-S-TARGET
9  CONSTANT AT-GET-AUTHOR-FEED-S-RANGE
10 CONSTANT AT-GET-AUTHOR-FEED-S-PROTECTED
11 CONSTANT AT-GET-AUTHOR-FEED-S-PLATFORM
12 CONSTANT AT-GET-AUTHOR-FEED-S-INTERNAL

: AT-GET-AUTHOR-FEED-STATUS-VALID?  ( status -- flag )
    DUP AT-GET-AUTHOR-FEED-S-OK >=
    SWAP AT-GET-AUTHOR-FEED-S-INTERNAL <= AND ;

0 CONSTANT AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-REPLIES
1 CONSTANT AT-GET-AUTHOR-FEED-FILTER-POSTS-NO-REPLIES
2 CONSTANT AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-MEDIA
3 CONSTANT AT-GET-AUTHOR-FEED-FILTER-POSTS-AND-AUTHOR-THREADS
4 CONSTANT AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-VIDEO

: AT-GET-AUTHOR-FEED-FILTER-VALID?  ( filter -- flag )
    DUP AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-REPLIES >=
    SWAP AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-VIDEO <= AND ;

: _ATGAF-FILTER$  ( filter -- address length )
    DUP AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-REPLIES = IF
        DROP S" posts_with_replies" EXIT
    THEN
    DUP AT-GET-AUTHOR-FEED-FILTER-POSTS-NO-REPLIES = IF
        DROP S" posts_no_replies" EXIT
    THEN
    DUP AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-MEDIA = IF
        DROP S" posts_with_media" EXIT
    THEN
    DUP AT-GET-AUTHOR-FEED-FILTER-POSTS-AND-AUTHOR-THREADS = IF
        DROP S" posts_and_author_threads" EXIT
    THEN
    DROP S" posts_with_video" ;

: AT-GET-AUTHOR-FEED-FILTER$
  ( filter -- address length status )
    DUP AT-GET-AUTHOR-FEED-FILTER-VALID? 0= IF
        DROP 0 0 AT-GET-AUTHOR-FEED-S-FILTER EXIT
    THEN
    _ATGAF-FILTER$
    AT-GET-AUTHOR-FEED-S-OK ;

\ =====================================================================
\  Caller-owned sequential workspace
\ =====================================================================

 0 CONSTANT _ATGAFW-PDS
 8 CONSTANT _ATGAFW-ACTOR-A
16 CONSTANT _ATGAFW-ACTOR-U
24 CONSTANT _ATGAFW-LIMIT
32 CONSTANT _ATGAFW-CURSOR-A
40 CONSTANT _ATGAFW-CURSOR-U
48 CONSTANT _ATGAFW-FILTER
56 CONSTANT _ATGAFW-INCLUDE-PINS
64 CONSTANT _ATGAFW-TARGET
72 CONSTANT _ATGAFW-URI-U
80 CONSTANT _ATGAFW-LIMIT-OFF
88 CONSTANT _ATGAFW-QUERY-OFF

_ATGAFW-QUERY-OFF HTARGET-URI-CAPACITY +
    CONSTANT _ATGAFW-WRITER-OFF
_ATGAFW-WRITER-OFF FUEW-SIZE +
    CONSTANT _ATGAFW-URI-OFF
_ATGAFW-URI-OFF HTARGET-URI-CAPACITY +
    CONSTANT _ATGAFW-STAGED-TARGET-OFF
_ATGAFW-STAGED-TARGET-OFF HTARGET-SIZE +
    CONSTANT AT-GET-AUTHOR-FEED-WORKSPACE-SIZE

: _ATGAFW.PDS           ( workspace -- field ) _ATGAFW-PDS + ;
: _ATGAFW.ACTOR-A       ( workspace -- field ) _ATGAFW-ACTOR-A + ;
: _ATGAFW.ACTOR-U       ( workspace -- field ) _ATGAFW-ACTOR-U + ;
: _ATGAFW.LIMIT         ( workspace -- field ) _ATGAFW-LIMIT + ;
: _ATGAFW.CURSOR-A      ( workspace -- field ) _ATGAFW-CURSOR-A + ;
: _ATGAFW.CURSOR-U      ( workspace -- field ) _ATGAFW-CURSOR-U + ;
: _ATGAFW.FILTER        ( workspace -- field ) _ATGAFW-FILTER + ;
: _ATGAFW.INCLUDE-PINS  ( workspace -- field )
    _ATGAFW-INCLUDE-PINS + ;
: _ATGAFW.TARGET        ( workspace -- field ) _ATGAFW-TARGET + ;
: _ATGAFW.URI-U         ( workspace -- field ) _ATGAFW-URI-U + ;

: _ATGAFW.LIMIT$        ( workspace -- address ) _ATGAFW-LIMIT-OFF + ;
: _ATGAFW.QUERY         ( workspace -- address ) _ATGAFW-QUERY-OFF + ;
: _ATGAFW.WRITER        ( workspace -- writer ) _ATGAFW-WRITER-OFF + ;
: _ATGAFW.URI           ( workspace -- address ) _ATGAFW-URI-OFF + ;
: _ATGAFW.STAGED-TARGET ( workspace -- target )
    _ATGAFW-STAGED-TARGET-OFF + ;

: _ATGAF-WIPE  ( workspace -- )
    AT-GET-AUTHOR-FEED-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Caller admission and subordinate status mapping
\ =====================================================================

: _ATGAF-DROP10  ( ten-values -- )
    2DROP 2DROP 2DROP 2DROP 2DROP ;

: _ATGAF-10DUP
  ( ten-values -- the-same-ten-values twice )
    9 PICK 9 PICK 9 PICK 9 PICK 9 PICK
    9 PICK 9 PICK 9 PICK 9 PICK 9 PICK ;

: _ATGAF-RETURN10  ( ten-values status -- status )
    >R _ATGAF-DROP10 R> ;

: _ATGAF-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP AT-GET-AUTHOR-FEED-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP AT-GET-AUTHOR-FEED-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-GET-AUTHOR-FEED-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-GET-AUTHOR-FEED-S-PLATFORM EXIT
    THEN
    DROP AT-GET-AUTHOR-FEED-S-PLATFORM ;

: _ATGAF-SPAN-STATUS  ( address length -- status )
    DUP 0< IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    DUP 0= IF
        2DROP AT-GET-AUTHOR-FEED-S-OK EXIT
    THEN
    OVER 0= IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS _ATGAF-CALLER>STATUS ;

: _ATGAF-REQUIRED-SPAN-STATUS  ( address length -- status )
    DUP 0> 0= IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    OVER 0= IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS _ATGAF-CALLER>STATUS ;

: _ATGAF-OPTIONAL-SPAN-STATUS  ( address length -- status )
    DUP 0< IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    DUP 0= IF
        DROP 0= IF
            AT-GET-AUTHOR-FEED-S-OK
        ELSE
            AT-GET-AUTHOR-FEED-S-INVALID
        THEN
        EXIT
    THEN
    OVER 0= IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS _ATGAF-CALLER>STATUS ;

: _ATGAF-FIXED-STATUS  ( address length -- status )
    OVER 0= IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    OVER 7 AND IF
        2DROP AT-GET-AUTHOR-FEED-S-INVALID EXIT
    THEN
    _ATGAF-SPAN-STATUS ;

: _ATGAF-FUEW>STATUS  ( writer-status -- status )
    DUP FUEW-S-OK = IF
        DROP AT-GET-AUTHOR-FEED-S-OK EXIT
    THEN
    DUP FUEW-S-CAPACITY = IF
        DROP AT-GET-AUTHOR-FEED-S-CAPACITY EXIT
    THEN
    DUP FUEW-S-ALIAS = IF
        DROP AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN
    DUP FUEW-S-RANGE = IF
        DROP AT-GET-AUTHOR-FEED-S-RANGE EXIT
    THEN
    DUP FUEW-S-PROTECTED = IF
        DROP AT-GET-AUTHOR-FEED-S-PROTECTED EXIT
    THEN
    DUP FUEW-S-PLATFORM = IF
        DROP AT-GET-AUTHOR-FEED-S-PLATFORM EXIT
    THEN
    DROP AT-GET-AUTHOR-FEED-S-INTERNAL ;

: _ATGAF-TARGET>STATUS  ( target-status -- status )
    DUP HTARGET-S-OK = IF
        DROP AT-GET-AUTHOR-FEED-S-OK EXIT
    THEN
    DUP HTARGET-S-CAPACITY = IF
        DROP AT-GET-AUTHOR-FEED-S-CAPACITY EXIT
    THEN
    DROP AT-GET-AUTHOR-FEED-S-TARGET ;

: AT-GET-AUTHOR-FEED-WORKSPACE-CLEAR  ( workspace -- status )
    DUP AT-GET-AUTHOR-FEED-WORKSPACE-SIZE
    _ATGAF-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _ATGAF-WIPE
    AT-GET-AUTHOR-FEED-S-OK ;

\ =====================================================================
\  Input semantics and operation geometry
\ =====================================================================

: _ATGAF-PDS-ORIGIN?  ( target -- flag )
    DUP HTARGET-VALID? 0= IF DROP 0 EXIT THEN
    DUP HTARGET-REDIRECT-COUNT@ IF DROP 0 EXIT THEN
    DUP HTARGET-REQUEST-TARGET$ S" /" COMPARE 0= 0= IF
        DROP 0 EXIT
    THEN
    HTARGET-URI$
    DUP 0= IF 2DROP 0 EXIT THEN
    + 1- C@ [CHAR] / = ;

: _ATGAF-ACTOR?  ( address length -- flag )
    2DUP DID-VALIDATE DID-S-OK = IF
        2DROP -1 EXIT
    THEN
    AT-HANDLE-VALIDATE AT-HANDLE-S-OK = ;

: _ATGAF-GEOMETRY  ( pds aa au lim ca cu filter pins target work -- status )
    DUP AT-GET-AUTHOR-FEED-WORKSPACE-SIZE
    _ATGAF-FIXED-STATUS
    ?DUP IF _ATGAF-RETURN10 EXIT THEN
    9 PICK HTARGET-SIZE _ATGAF-FIXED-STATUS
    ?DUP IF _ATGAF-RETURN10 EXIT THEN
    1 PICK HTARGET-SIZE _ATGAF-FIXED-STATUS
    ?DUP IF _ATGAF-RETURN10 EXIT THEN
    8 PICK 8 PICK _ATGAF-REQUIRED-SPAN-STATUS
    ?DUP IF _ATGAF-RETURN10 EXIT THEN
    5 PICK 5 PICK _ATGAF-OPTIONAL-SPAN-STATUS
    ?DUP IF _ATGAF-RETURN10 EXIT THEN

    9 PICK _ATGAF-PDS-ORIGIN? 0= IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-PDS EXIT
    THEN
    8 PICK 8 PICK _ATGAF-ACTOR? 0= IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ACTOR EXIT
    THEN
    6 PICK DUP 1 < SWAP 100 > OR IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-LIMIT EXIT
    THEN
    3 PICK AT-GET-AUTHOR-FEED-FILTER-VALID? 0= IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-FILTER EXIT
    THEN

    \ The workspace is cleared before use, and the output is replaced on
    \ success, so neither may overlap an input borrow or each other.
    9 PICK HTARGET-SIZE
    2 PICK AT-GET-AUTHOR-FEED-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN
    1 PICK HTARGET-SIZE
    2 PICK AT-GET-AUTHOR-FEED-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN
    8 PICK 8 PICK
    2 PICK AT-GET-AUTHOR-FEED-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK
    2 PICK AT-GET-AUTHOR-FEED-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN

    9 PICK HTARGET-SIZE 3 PICK HTARGET-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN
    8 PICK 8 PICK 3 PICK HTARGET-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK 3 PICK HTARGET-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN

    \ Input borrows must not be hidden inside the PDS object.  Actor and
    \ cursor may overlap one another because both remain immutable.
    8 PICK 8 PICK 11 PICK HTARGET-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK 11 PICK HTARGET-SIZE
    MSPAN-OVERLAP? IF
        _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-ALIAS EXIT
    THEN

    _ATGAF-DROP10 AT-GET-AUTHOR-FEED-S-OK ;

\ =====================================================================
\  Deterministic query and URI construction
\ =====================================================================

: _ATGAF-LIMIT$  ( limit workspace -- address length )
    >R
    R@ _ATGAFW.LIMIT$ 3 0 FILL
    DUP 100 = IF
        DROP
        [CHAR] 1 R@ _ATGAFW.LIMIT$ C!
        [CHAR] 0 R@ _ATGAFW.LIMIT$ 1+ C!
        [CHAR] 0 R@ _ATGAFW.LIMIT$ 2 + C!
        R> _ATGAFW.LIMIT$ 3 EXIT
    THEN
    DUP 10 >= IF
        DUP 10 / [CHAR] 0 + R@ _ATGAFW.LIMIT$ C!
        10 MOD [CHAR] 0 + R@ _ATGAFW.LIMIT$ 1+ C!
        R> _ATGAFW.LIMIT$ 2 EXIT
    THEN
    [CHAR] 0 + R@ _ATGAFW.LIMIT$ C!
    R> _ATGAFW.LIMIT$ 1 ;

: _ATGAF-FIELD
  ( name-a name-u value-a value-u workspace -- status )
    _ATGAFW.WRITER
    FUEW-FIELD _ATGAF-FUEW>STATUS ;

: _ATGAF-BUILD-QUERY  ( workspace -- status )
    >R
    R@ _ATGAFW.QUERY HTARGET-URI-CAPACITY
    R@ _ATGAFW.WRITER FUEW-INIT
    _ATGAF-FUEW>STATUS ?DUP IF R> DROP EXIT THEN

    S" actor"
    R@ _ATGAFW.ACTOR-A @ R@ _ATGAFW.ACTOR-U @
    R@ _ATGAF-FIELD ?DUP IF R> DROP EXIT THEN

    S" limit"
    R@ _ATGAFW.LIMIT @ R@ _ATGAF-LIMIT$
    R@ _ATGAF-FIELD ?DUP IF R> DROP EXIT THEN

    R@ _ATGAFW.CURSOR-U @ IF
        S" cursor"
        R@ _ATGAFW.CURSOR-A @ R@ _ATGAFW.CURSOR-U @
        R@ _ATGAF-FIELD ?DUP IF R> DROP EXIT THEN
    THEN

    S" filter"
    R@ _ATGAFW.FILTER @ _ATGAF-FILTER$
    R@ _ATGAF-FIELD ?DUP IF R> DROP EXIT THEN

    S" includePins"
    R@ _ATGAFW.INCLUDE-PINS @
    IF S" true" ELSE S" false" THEN
    R@ _ATGAF-FIELD ?DUP IF R> DROP EXIT THEN

    R@ _ATGAFW.WRITER FUEW-SEAL
    _ATGAF-FUEW>STATUS
    R> DROP ;

: _ATGAF-URI-APPEND
  ( source-a source-u workspace -- status )
    >R
    DUP R@ _ATGAFW.URI-U @
    HTARGET-URI-CAPACITY SWAP - U> IF
        2DROP R> DROP AT-GET-AUTHOR-FEED-S-CAPACITY EXIT
    THEN
    OVER
    R@ _ATGAFW.URI R@ _ATGAFW.URI-U @ +
    2 PICK CMOVE
    DUP R@ _ATGAFW.URI-U +!
    2DROP
    R> DROP AT-GET-AUTHOR-FEED-S-OK ;

: _ATGAF-BUILD-URI  ( workspace -- status )
    >R
    R@ _ATGAFW.URI HTARGET-URI-CAPACITY 0 FILL
    0 R@ _ATGAFW.URI-U !

    R@ _ATGAFW.PDS @ HTARGET-URI$ 1-
    R@ _ATGAF-URI-APPEND ?DUP IF R> DROP EXIT THEN
    S" /xrpc/app.bsky.feed.getAuthorFeed"
    R@ _ATGAF-URI-APPEND ?DUP IF R> DROP EXIT THEN
    S" ?"
    R@ _ATGAF-URI-APPEND ?DUP IF R> DROP EXIT THEN

    R@ _ATGAFW.WRITER FUEW-BODY@
    DUP FUEW-S-OK <> IF
        _ATGAF-FUEW>STATUS >R
        2DROP R> R> DROP EXIT
    THEN
    DROP
    R@ _ATGAF-URI-APPEND
    R> DROP ;

\ =====================================================================
\  Transactional target publication
\ =====================================================================

: _ATGAF-CLEAN  ( status workspace -- status )
    DUP _ATGAF-WIPE DROP ;

: _ATGAF-TARGET-OP  ( pds aa au lim ca cu filter pins target work -- status )
    DUP >R
    R@ _ATGAF-WIPE
    9 PICK R@ _ATGAFW.PDS !
    8 PICK R@ _ATGAFW.ACTOR-A !
    7 PICK R@ _ATGAFW.ACTOR-U !
    6 PICK R@ _ATGAFW.LIMIT !
    5 PICK R@ _ATGAFW.CURSOR-A !
    4 PICK R@ _ATGAFW.CURSOR-U !
    3 PICK R@ _ATGAFW.FILTER !
    2 PICK R@ _ATGAFW.INCLUDE-PINS !
    1 PICK R@ _ATGAFW.TARGET !
    _ATGAF-DROP10

    R@ _ATGAF-BUILD-QUERY
    ?DUP IF R> _ATGAF-CLEAN EXIT THEN
    R@ _ATGAF-BUILD-URI
    ?DUP IF R> _ATGAF-CLEAN EXIT THEN

    R@ _ATGAFW.URI R@ _ATGAFW.URI-U @
    R@ _ATGAFW.STAGED-TARGET HTARGET-PARSE
    _ATGAF-TARGET>STATUS
    ?DUP IF R> _ATGAF-CLEAN EXIT THEN

    R@ _ATGAFW.PDS @ R@ _ATGAFW.STAGED-TARGET
    HTARGET-SAME-ORIGIN? 0= IF
        AT-GET-AUTHOR-FEED-S-INTERNAL
        R> _ATGAF-CLEAN EXIT
    THEN

    R@ _ATGAFW.STAGED-TARGET
    R@ _ATGAFW.TARGET @
    HTARGET-SIZE CMOVE
    AT-GET-AUTHOR-FEED-S-OK
    R> _ATGAF-CLEAN ;

: _ATGAF-TARGET-CALL
  ( ten-values operation-xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _ATGAF-WIPE
        _ATGAF-DROP10
        R> DROP
        AT-GET-AUTHOR-FEED-S-INTERNAL EXIT
    THEN
    DROP R> DROP ;

: AT-GET-AUTHOR-FEED-TARGET!
  ( pds aa au limit cursor-a cursor-u filter pins target work -- status )
    _ATGAF-10DUP _ATGAF-GEOMETRY
    ?DUP IF _ATGAF-RETURN10 EXIT THEN
    ['] _ATGAF-TARGET-OP _ATGAF-TARGET-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _ATGAF-GEOMETRY-ABORT  ( -- )
    ." AT getAuthorFeed workspace geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _ATGAF-GEOMETRY-ABORT
[THEN]

_ATGAFW-WRITER-OFF 7 AND [IF]
    _ATGAF-GEOMETRY-ABORT
[THEN]

_ATGAFW-STAGED-TARGET-OFF 7 AND [IF]
    _ATGAF-GEOMETRY-ABORT
[THEN]
