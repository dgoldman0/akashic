\ request.f — HTTP request parser for KDOS / Megapad-64
\
\ Parses incoming HTTP/1.1 requests from a raw receive buffer
\ into structured fields.  Zero-copy — all results are
\ (addr len) pointers into the caller's receive buffer.
\
\ Same (addr len) cursor model as headers.f, url.f, json.f.
\ Variable-based state — no deep stack gymnastics.
\
\ Prefix: REQ-   (public API)
\         _REQ-  (internal helpers)
\
\ Load with:   REQUIRE request.f

REQUIRE ../net/headers.f
REQUIRE ../net/url.f
REQUIRE ../utils/string.f

PROVIDED akashic-web-request

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE REQ-ERR
1 CONSTANT REQ-E-MALFORMED        \ request line not parseable
2 CONSTANT REQ-E-NO-CRLF          \ no CRLF found
3 CONSTANT REQ-E-TOO-LONG         \ request exceeds buffer

: REQ-FAIL       ( code -- )  REQ-ERR ! ;
: REQ-OK?        ( -- flag )  REQ-ERR @ 0= ;
: REQ-CLEAR-ERR  ( -- )       0 REQ-ERR ! ;

\ =====================================================================
\  Request State — all zero-copy into recv buffer
\ =====================================================================

VARIABLE _REQ-METHOD-A    VARIABLE _REQ-METHOD-U
VARIABLE _REQ-PATH-A      VARIABLE _REQ-PATH-U
VARIABLE _REQ-QUERY-A     VARIABLE _REQ-QUERY-U
VARIABLE _REQ-VERSION-A   VARIABLE _REQ-VERSION-U
VARIABLE _REQ-HDR-A       VARIABLE _REQ-HDR-U
VARIABLE _REQ-BODY-A      VARIABLE _REQ-BODY-U

\ Public accessors
: REQ-METHOD    ( -- a u )  _REQ-METHOD-A @  _REQ-METHOD-U @  ;
: REQ-PATH      ( -- a u )  _REQ-PATH-A @   _REQ-PATH-U @    ;
: REQ-QUERY     ( -- a u )  _REQ-QUERY-A @  _REQ-QUERY-U @   ;
: REQ-VERSION   ( -- a u )  _REQ-VERSION-A @ _REQ-VERSION-U @ ;
: REQ-BODY      ( -- a u )  _REQ-BODY-A @   _REQ-BODY-U @    ;

\ =====================================================================
\  Layer 0 — Request Line Parsing
\ =====================================================================
\
\  Request line format:
\    METHOD SP REQUEST-TARGET SP HTTP-VERSION CRLF
\    e.g. "GET /path?key=val HTTP/1.1\r\n"
\
\  This layer extracts method, path, query, and version.

\ _REQ-FIND-SP ( addr len -- idx | -1 )
\   Find first space (32) in string.
: _REQ-FIND-SP  ( addr len -- idx )
    32 STR-INDEX ;

\ _REQ-FIND-CRLF ( addr len -- idx | -1 )
\   Find first CRLF pair.  Returns index of the CR.
VARIABLE _RFC-PTR
VARIABLE _RFC-END

: _REQ-FIND-CRLF  ( addr len -- idx )
    DUP 2 < IF 2DROP -1 EXIT THEN
    OVER + _RFC-END !
    DUP _RFC-PTR !
    BEGIN
        _RFC-PTR @ 1 + _RFC-END @ <=
    WHILE
        _RFC-PTR @ C@ 13 =
        _RFC-PTR @ 1 + C@ 10 = AND IF
            _RFC-PTR @ SWAP - EXIT
        THEN
        1 _RFC-PTR +!
    REPEAT
    DROP -1 ;

\ REQ-PARSE-LINE ( addr len -- )
\   Parse request line.  Finds two spaces separating METHOD, target,
\   version.  Splits target on '?' into path and query.
VARIABLE _RPL-A
VARIABLE _RPL-U
VARIABLE _RPL-SP1
VARIABLE _RPL-SP2
VARIABLE _RPL-CRLF

: REQ-PARSE-LINE  ( addr len -- )
    _RPL-U ! _RPL-A !

    \ Find end of request line (CRLF)
    _RPL-A @ _RPL-U @ _REQ-FIND-CRLF _RPL-CRLF !
    _RPL-CRLF @ 0< IF
        \ Try bare LF
        _RPL-A @ _RPL-U @ 10 STR-INDEX _RPL-CRLF !
        _RPL-CRLF @ 0< IF
            REQ-E-NO-CRLF REQ-FAIL EXIT
        THEN
    THEN

    \ Find first space → end of method
    _RPL-A @ _RPL-CRLF @ _REQ-FIND-SP _RPL-SP1 !
    _RPL-SP1 @ 0< IF REQ-E-MALFORMED REQ-FAIL EXIT THEN

    \ Method
    _RPL-A @ _REQ-METHOD-A !
    _RPL-SP1 @ _REQ-METHOD-U !

    \ Find second space → end of target
    _RPL-A @ _RPL-SP1 @ + 1+                \ start after first SP
    _RPL-CRLF @ _RPL-SP1 @ - 1-             \ remaining len to CRLF
    _REQ-FIND-SP _RPL-SP2 !
    _RPL-SP2 @ 0< IF REQ-E-MALFORMED REQ-FAIL EXIT THEN

    \ Target = chars between SP1+1 and SP1+1+SP2
    \ Version = chars after SP2+1 to CRLF
    _RPL-A @ _RPL-SP1 @ + 1+                 \ target addr
    _RPL-SP2 @                                \ target len

    \ Split target on '?' into path and query
    2DUP 63 STR-INDEX                          ( target-a target-u qidx )
    DUP 0< IF
        \ No '?' — path is the whole target, no query
        DROP
        _REQ-PATH-U ! _REQ-PATH-A !
        0 _REQ-QUERY-A !  0 _REQ-QUERY-U !
    ELSE
        \ path = target[0..qidx), query = target[qidx+1..]
        >R
        OVER _REQ-PATH-A !
        R@ _REQ-PATH-U !
        OVER R@ + 1+ _REQ-QUERY-A !
        R> - 1- _REQ-QUERY-U !
        DROP
    THEN

    \ Version
    _RPL-A @ _RPL-SP1 @ + 1+ _RPL-SP2 @ + 1+   _REQ-VERSION-A !
    _RPL-CRLF @ _RPL-SP1 @ - 1- _RPL-SP2 @ - 1-  _REQ-VERSION-U ! ;

\ =====================================================================
\  Layer 1 — Header Parsing
\ =====================================================================
\
\  Locates the header block after the request line (first CRLF)
\  and before the blank line (CRLFCRLF).  Delegates lookups to
\  HDR-FIND from headers.f.

\ REQ-PARSE-HEADERS ( addr len -- )
\   Find the header block in the raw request.
\   addr/len = full request buffer.
VARIABLE _RPH-HEND

: REQ-PARSE-HEADERS  ( addr len -- )
    \ Find first CRLF (end of request line)
    2DUP _REQ-FIND-CRLF                       ( addr len crlf-idx )
    DUP 0< IF
        \ Try bare LF
        DROP 2DUP 10 STR-INDEX
        DUP 0< IF DROP 2DROP EXIT THEN
        1+                                     ( addr len skip )
    ELSE
        2 +                                    ( addr len skip )
    THEN
    /STRING                                    ( hdr-start remaining-len )
    \ Find CRLFCRLF in the remaining data
    2DUP HDR-FIND-HEND _RPH-HEND !
    _RPH-HEND @ 0= IF
        \ No double-CRLF found — headers run to end of input
        _REQ-HDR-U ! _REQ-HDR-A !
    ELSE
        \ hend = offset from hdr-start to body start
        DROP _RPH-HEND @ 4 - DUP 0< IF DROP 0 THEN
        _REQ-HDR-U ! _REQ-HDR-A !
    THEN ;

\ REQ-HEADER ( name-a name-u -- val-a val-u flag )
\   Look up a header by name (case-insensitive).
\   Delegates to HDR-FIND from headers.f.
: REQ-HEADER  ( name-a name-u -- val-a val-u flag )
    _REQ-HDR-A @ _REQ-HDR-U @ 2SWAP HDR-FIND ;

\ ── Shortcut accessors ──

: REQ-CONTENT-TYPE    ( -- a u )
    S" Content-Type" REQ-HEADER IF ELSE 2DROP 0 0 THEN ;

: REQ-CONTENT-LENGTH  ( -- n )
    _REQ-HDR-A @ _REQ-HDR-U @ HDR-PARSE-CLEN ;

: REQ-HOST   ( -- a u )
    S" Host" REQ-HEADER IF ELSE 2DROP 0 0 THEN ;

: REQ-ACCEPT ( -- a u )
    S" Accept" REQ-HEADER IF ELSE 2DROP 0 0 THEN ;

: REQ-AUTH   ( -- a u )
    S" Authorization" REQ-HEADER IF ELSE 2DROP 0 0 THEN ;

: REQ-COOKIE ( -- a u )
    S" Cookie" REQ-HEADER IF ELSE 2DROP 0 0 THEN ;

\ =====================================================================
\  Layer 2 — Body
\ =====================================================================

\ REQ-PARSE-BODY ( addr len -- )
\   Locate body after the blank line (CRLFCRLF).
VARIABLE _RPB-HEND

: REQ-PARSE-BODY  ( addr len -- )
    2DUP HDR-FIND-HEND _RPB-HEND !
    _RPB-HEND @ 0= IF
        \ No double-CRLF — no body
        2DROP  0 _REQ-BODY-A !  0 _REQ-BODY-U !
    ELSE
        \ Body starts at offset hend, length = total - hend
        OVER _RPB-HEND @ +  _REQ-BODY-A !
        SWAP DROP _RPB-HEND @ -  _REQ-BODY-U !
    THEN ;

\ REQ-JSON-BODY ( -- a u )
\   Return body, asserting Content-Type is application/json.
: REQ-JSON-BODY  ( -- a u )
    REQ-CONTENT-TYPE
    DUP 0= IF 2DROP REQ-BODY EXIT THEN
    S" application/json" STR-STARTSI? IF
        REQ-BODY
    ELSE
        0 0
    THEN ;

\ REQ-FORM-BODY ( -- a u )
\   Return body, asserting Content-Type is
\   application/x-www-form-urlencoded.
\   Caller can use URL-QUERY-NEXT / URL-QUERY-FIND to iterate
\   key=value pairs (same format as query strings).
: REQ-FORM-BODY  ( -- a u )
    REQ-CONTENT-TYPE
    DUP 0= IF 2DROP REQ-BODY EXIT THEN
    S" application/x-www-form-urlencoded" STR-STARTSI? IF
        REQ-BODY
    ELSE
        0 0
    THEN ;

\ =====================================================================
\  Layer 3 — Full Parse
\ =====================================================================

\ REQ-CLEAR ( -- )
\   Reset all request state for next connection.
: REQ-CLEAR  ( -- )
    REQ-CLEAR-ERR
    0 _REQ-METHOD-A !   0 _REQ-METHOD-U !
    0 _REQ-PATH-A !     0 _REQ-PATH-U !
    0 _REQ-QUERY-A !    0 _REQ-QUERY-U !
    0 _REQ-VERSION-A !  0 _REQ-VERSION-U !
    0 _REQ-HDR-A !      0 _REQ-HDR-U !
    0 _REQ-BODY-A !     0 _REQ-BODY-U ! ;

\ REQ-PARSE ( addr len -- )
\   Full request parse: request line + headers + body.
: REQ-PARSE  ( addr len -- )
    REQ-CLEAR
    2DUP REQ-PARSE-LINE
    REQ-OK? 0= IF 2DROP EXIT THEN
    2DUP REQ-PARSE-HEADERS
    REQ-PARSE-BODY ;

\ =====================================================================
\  Layer 4 — Query Parameter Access
\ =====================================================================
\
\  Thin wrappers over URL-QUERY-FIND / URL-QUERY-NEXT from url.f,
\  operating on REQ-QUERY.

\ REQ-PARAM-FIND ( key-a key-u -- val-a val-u flag )
\   Find a query parameter by key name.
: REQ-PARAM-FIND  ( key-a key-u -- val-a val-u flag )
    REQ-QUERY 2SWAP URL-QUERY-FIND ;

\ REQ-PARAM? ( key-a key-u -- flag )
\   Test whether a query parameter exists.
: REQ-PARAM?  ( key-a key-u -- flag )
    REQ-PARAM-FIND IF 2DROP -1 ELSE 0 THEN ;

\ REQ-PARAM-NEXT ( a u -- a' u' key-a key-u val-a val-u flag )
\   Iterate query parameters from remaining cursor.
: REQ-PARAM-NEXT  ( a u -- a' u' key-a key-u val-a val-u flag )
    URL-QUERY-NEXT ;

\ =====================================================================
\  Layer 5 — Method Checks
\ =====================================================================
\
\  Convenience words for method testing in handlers.

: REQ-GET?     ( -- flag )  REQ-METHOD S" GET"    STR-STR= ;
: REQ-POST?    ( -- flag )  REQ-METHOD S" POST"   STR-STR= ;
: REQ-PUT?     ( -- flag )  REQ-METHOD S" PUT"    STR-STR= ;
: REQ-DELETE?  ( -- flag )  REQ-METHOD S" DELETE" STR-STR= ;
: REQ-HEAD?    ( -- flag )  REQ-METHOD S" HEAD"   STR-STR= ;
: REQ-OPTIONS? ( -- flag )  REQ-METHOD S" OPTIONS" STR-STR= ;
: REQ-PATCH?   ( -- flag )  REQ-METHOD S" PATCH"  STR-STR= ;

\ ── Concurrency ──
\
\ All public words in this module are NOT reentrant.  They use shared
\ VARIABLE scratch space that would be corrupted by concurrent access.
\ Callers must ensure single-task access via WITH-GUARD, WITH-CRITICAL,
\ or by running with preemption disabled.
