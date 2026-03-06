\ middleware.f — Before/after hooks for KDOS web server
\
\ Middleware = a word that wraps the router dispatch.
\ Each middleware receives a "next-xt" on the stack and must
\ call it (or not) to pass control down the chain.
\
\ Middleware signature:  ( next-xt -- )
\   Pre-process, EXECUTE next-xt, post-process.
\
\ Chain is built at startup via MW-USE, executed per-request
\ via MW-RUN.  Innermost "next" is ROUTE-DISPATCH.
\
\ Plug into server.f:   ['] MW-RUN SRV-SET-DISPATCH
\
\ Prefix: MW-   (public API)
\         _MW-  (internal helpers)
\
\ Load with:   REQUIRE middleware.f

REQUIRE ../web/request.f
REQUIRE ../web/response.f
REQUIRE ../web/router.f
REQUIRE ../utils/datetime.f
REQUIRE ../utils/string.f
REQUIRE ../net/base64.f

PROVIDED akashic-web-middleware

\ =====================================================================
\  Layer 0 — Middleware Chain
\ =====================================================================

16 CONSTANT _MW-MAX
CREATE _MW-CHAIN  128 ALLOT         \ 16 cells × 8 bytes
VARIABLE _MW-COUNT
0 _MW-COUNT !

\ MW-USE ( xt -- )
\   Add middleware to the chain.  FIFO order.
: MW-USE  ( xt -- )
    _MW-COUNT @ _MW-MAX >= IF DROP EXIT THEN
    _MW-CHAIN _MW-COUNT @ 8 * + !
    1 _MW-COUNT +! ;

\ MW-CLEAR ( -- )
\   Remove all middleware from the chain.
: MW-CLEAR  ( -- )  0 _MW-COUNT ! ;

\ ── Internal: chained execution ──

\ The chain is single-threaded so a VARIABLE for the next index is safe.
VARIABLE _MW-NEXT-IDX

\ Forward declaration: _MW-RUN-FROM needs _MW-NEXT which needs
\ _MW-RUN-FROM.  Break the cycle with a vectored word.
VARIABLE _MW-RUN-FROM-XT

: _MW-NEXT  ( -- )
    _MW-NEXT-IDX @ _MW-RUN-FROM-XT @ EXECUTE ;

\ _MW-RUN-FROM ( idx -- )
\   Execute middleware chain starting from index idx.
\   When idx reaches _MW-COUNT, call ROUTE-DISPATCH.
: _MW-RUN-FROM  ( idx -- )
    DUP _MW-COUNT @ >= IF
        DROP ROUTE-DISPATCH EXIT
    THEN
    DUP 1+ _MW-NEXT-IDX !
    _MW-CHAIN SWAP 8 * + @           \ ( mw-xt )
    ['] _MW-NEXT SWAP EXECUTE ;

' _MW-RUN-FROM _MW-RUN-FROM-XT !

\ MW-RUN ( -- )
\   Execute the full middleware chain, ending with ROUTE-DISPATCH.
: MW-RUN  ( -- )
    _MW-COUNT @ 0= IF ROUTE-DISPATCH EXIT THEN
    0 _MW-RUN-FROM ;

\ =====================================================================
\  Layer 1 — Built-in Middleware: MW-LOG
\ =====================================================================
\
\ Logs: METHOD /path → STATUS
\ Uses DT-NOW-MS for start/end timing.

VARIABLE _MW-LOG-T0

: MW-LOG  ( next-xt -- )
    DT-NOW-MS _MW-LOG-T0 !
    EXECUTE
    ." [" DT-NOW-S NUM>STR TYPE ." ] "
    REQ-METHOD TYPE SPACE
    REQ-PATH TYPE
    ."  -> " _RESP-CODE @ . 
    ." (" DT-NOW-MS _MW-LOG-T0 @ - . ." ms)"
    CR ;

\ =====================================================================
\  Layer 1 — Built-in Middleware: MW-CORS
\ =====================================================================
\
\ OPTIONS request → 204 with CORS headers, skip next.
\ All other methods → add CORS headers, call next.

: MW-CORS  ( next-xt -- )
    REQ-OPTIONS? IF
        DROP
        204 RESP-STATUS
        RESP-CORS
        RESP-SEND
    ELSE
        RESP-CORS
        EXECUTE
    THEN ;

\ =====================================================================
\  Layer 1 — Built-in Middleware: MW-JSON-BODY
\ =====================================================================
\
\ If Content-Type is application/json and body present,
\ validate it's non-empty.  If missing/empty → 400.
\ Otherwise call next.

CREATE _MW-CT-JSON 16 ALLOT
\ "application/json" — stored as byte array
\ a(97) p(112) p(112) l(108) i(105) c(99) a(97) t(116) i(105) o(111) n(110) /(47) j(106) s(115) o(111) n(110)
97 _MW-CT-JSON C!
112 _MW-CT-JSON 1+ C!
112 _MW-CT-JSON 2 + C!
108 _MW-CT-JSON 3 + C!
105 _MW-CT-JSON 4 + C!
99 _MW-CT-JSON 5 + C!
97 _MW-CT-JSON 6 + C!
116 _MW-CT-JSON 7 + C!
105 _MW-CT-JSON 8 + C!
111 _MW-CT-JSON 9 + C!
110 _MW-CT-JSON 10 + C!
47 _MW-CT-JSON 11 + C!
106 _MW-CT-JSON 12 + C!
115 _MW-CT-JSON 13 + C!
111 _MW-CT-JSON 14 + C!
110 _MW-CT-JSON 15 + C!

: MW-JSON-BODY  ( next-xt -- )
    REQ-CONTENT-TYPE DUP 0= IF
        2DROP EXECUTE EXIT
    THEN
    _MW-CT-JSON 16 STR-STARTSI? IF
        REQ-BODY NIP 0= IF
            DROP
            400 RESP-ERROR EXIT
        THEN
        EXECUTE
    ELSE
        EXECUTE
    THEN ;

\ =====================================================================
\  Layer 2 — Built-in Middleware: MW-BASIC-AUTH
\ =====================================================================
\
\ HTTP Basic Authentication.
\ Store expected credentials with MW-BASIC-AUTH-SET, then register
\ MW-BASIC-AUTH via MW-USE.
\
\ Usage:
\   S" admin" S" secret" MW-BASIC-AUTH-SET
\   ' MW-BASIC-AUTH MW-USE
\
\ Authorization header absent    → 401 + WWW-Authenticate
\ Credentials wrong              → 403
\ Credentials match              → call next

VARIABLE _MW-AUTH-USER-A   VARIABLE _MW-AUTH-USER-U
VARIABLE _MW-AUTH-PASS-A   VARIABLE _MW-AUTH-PASS-U
CREATE _MW-AUTH-DEC-BUF 256 ALLOT   \ decoded "user:pass"
VARIABLE _MW-AUTH-DEC-LEN

\ MW-BASIC-AUTH-SET ( user-a user-u pass-a pass-u -- )
\   Store the expected username and password.
: MW-BASIC-AUTH-SET  ( user-a user-u pass-a pass-u -- )
    _MW-AUTH-PASS-U ! _MW-AUTH-PASS-A !
    _MW-AUTH-USER-U ! _MW-AUTH-USER-A ! ;

\ "Basic " prefix as byte array (6 chars: B=66 a=97 s=115 i=105 c=99 SP=32)
CREATE _MW-AUTH-PFX 6 ALLOT
66 _MW-AUTH-PFX C!
97 _MW-AUTH-PFX 1+ C!
115 _MW-AUTH-PFX 2 + C!
105 _MW-AUTH-PFX 3 + C!
99 _MW-AUTH-PFX 4 + C!
32 _MW-AUTH-PFX 5 + C!

\ "Basic realm=\"Akashic\"" for WWW-Authenticate header
CREATE _MW-AUTH-REALM 22 ALLOT
\ B(66) a(97) s(115) i(105) c(99) SP(32) r(114) e(101) a(97) l(108) m(109) =(61) "(34) A(65) k(107) a(97) s(115) h(104) i(105) c(99) "(34) NUL
66 _MW-AUTH-REALM      C!
97 _MW-AUTH-REALM  1 + C!
115 _MW-AUTH-REALM 2 + C!
105 _MW-AUTH-REALM 3 + C!
99 _MW-AUTH-REALM  4 + C!
32 _MW-AUTH-REALM  5 + C!
114 _MW-AUTH-REALM 6 + C!
101 _MW-AUTH-REALM 7 + C!
97 _MW-AUTH-REALM  8 + C!
108 _MW-AUTH-REALM 9 + C!
109 _MW-AUTH-REALM 10 + C!
61 _MW-AUTH-REALM  11 + C!
34 _MW-AUTH-REALM  12 + C!
65 _MW-AUTH-REALM  13 + C!
107 _MW-AUTH-REALM 14 + C!
97 _MW-AUTH-REALM  15 + C!
115 _MW-AUTH-REALM 16 + C!
104 _MW-AUTH-REALM 17 + C!
105 _MW-AUTH-REALM 18 + C!
99 _MW-AUTH-REALM  19 + C!
34 _MW-AUTH-REALM  20 + C!

\ _MW-AUTH-CHECK ( -- flag )
\   Decode the Authorization header and compare credentials.
\   Assumes REQ-AUTH returned valid (addr len) starting with "Basic ".
\   Returns true if user:pass matches stored credentials.
VARIABLE _MW-AUTH-COLON

: _MW-AUTH-CHECK  ( auth-a auth-u -- flag )
    \ Skip "Basic " prefix (6 chars)
    6 - SWAP 6 + SWAP                    ( b64-a b64-u )
    _MW-AUTH-DEC-BUF 256 B64-DECODE      ( decoded-len )
    DUP _MW-AUTH-DEC-LEN !
    0= IF 0 EXIT THEN                    \ decode failed
    \ Find ':' separator
    _MW-AUTH-DEC-BUF _MW-AUTH-DEC-LEN @ 58 STR-INDEX  ( colon-idx | -1 )
    DUP -1 = IF DROP 0 EXIT THEN
    _MW-AUTH-COLON !
    \ Compare username: [0..colon)
    _MW-AUTH-DEC-BUF _MW-AUTH-COLON @
    _MW-AUTH-USER-A @ _MW-AUTH-USER-U @
    STR-STR= 0= IF 0 EXIT THEN
    \ Compare password: [colon+1..end)
    _MW-AUTH-DEC-BUF _MW-AUTH-COLON @ + 1+
    _MW-AUTH-DEC-LEN @ _MW-AUTH-COLON @ - 1-
    _MW-AUTH-PASS-A @ _MW-AUTH-PASS-U @
    STR-STR= ;

: MW-BASIC-AUTH  ( next-xt -- )
    REQ-AUTH DUP 0= IF
        \ No Authorization header → 401
        2DROP DROP
        401 RESP-STATUS
        S" text/plain" RESP-CONTENT-TYPE
        S" WWW-Authenticate" _MW-AUTH-REALM 21 RESP-HEADER
        S" Unauthorized" RESP-BODY
        RESP-SEND EXIT
    THEN
    \ Check "Basic " prefix
    2DUP _MW-AUTH-PFX 6 STR-STARTS? 0= IF
        2DROP DROP
        403 RESP-ERROR EXIT
    THEN
    \ Decode and compare
    2DUP _MW-AUTH-CHECK IF
        2DROP EXECUTE
    ELSE
        2DROP DROP
        403 RESP-ERROR
    THEN ;

\ =====================================================================
\  Layer 2 — Built-in Middleware: MW-STATIC
\ =====================================================================
\
\ Serve static files from the KDOS filesystem.
\ If the request path starts with the configured URL prefix,
\ strip the prefix, look up the remaining filename in the FS,
\ detect MIME type from extension, and send the file content.
\ If no match or file not found → call next.
\
\ Usage:
\   S" /static/" MW-STATIC-SET
\   ' MW-STATIC MW-USE
\
\ Requires FS-LOAD to have been called (filesystem mounted).

VARIABLE _MW-STATIC-PFX-A   VARIABLE _MW-STATIC-PFX-U
CREATE _MW-STATIC-READ-BUF 4096 ALLOT

\ MW-STATIC-SET ( pfx-a pfx-u -- )
\   Set the URL prefix for static file matching (e.g., "/static/").
: MW-STATIC-SET  ( pfx-a pfx-u -- )
    _MW-STATIC-PFX-U ! _MW-STATIC-PFX-A ! ;

\ _MW-SOPEN ( addr len -- fdesc | 0 )
\   Stack-based file open.  Copies name into NAMEBUF, runs
\   FIND-BY-NAME, builds a file descriptor at HERE.
\   Returns fdesc or 0 if not found / FS not loaded.
VARIABLE _MW-SO-SLOT

: _MW-SOPEN  ( addr len -- fdesc | 0 )
    FS-OK @ 0= IF 2DROP 0 EXIT THEN
    \ Copy name to NAMEBUF (max 23 chars, null-terminate)
    DUP 23 > IF 2DROP 0 EXIT THEN
    NAMEBUF 24 0 FILL
    NAMEBUF SWAP CMOVE
    FIND-BY-NAME _MW-SO-SLOT !
    _MW-SO-SLOT @ -1 = IF 0 EXIT THEN
    \ Build standard 4-cell file descriptor at HERE
    HERE
    _MW-SO-SLOT @ DIRENT DE.SEC   ,   \ +0  start sector
    _MW-SO-SLOT @ DIRENT DE.COUNT ,   \ +8  max sectors
    _MW-SO-SLOT @ DIRENT DE.USED  ,   \ +16 used bytes
    0 , ;                              \ +24 cursor = 0

\ _MW-STATIC-EXT ( path-a path-u -- ext-a ext-u )
\   Find the file extension (after last '.').  Returns (0 0) if none.
VARIABLE _MW-EXT-DOT

: _MW-STATIC-EXT  ( path-a path-u -- ext-a ext-u )
    -1 _MW-EXT-DOT !
    2DUP OVER + SWAP DO
        I C@ 46 = IF I _MW-EXT-DOT ! THEN    \ 46 = '.'
    LOOP
    _MW-EXT-DOT @ -1 = IF 2DROP 0 0 EXIT THEN
    \ ext starts at dot+1, length = end - ext-start
    + _MW-EXT-DOT @ 1+ TUCK - ;

\ _MW-STATIC-MIME ( ext-a ext-u -- mime-a mime-u )
\   Map file extension to MIME type.  Falls back to
\   application/octet-stream for unknown extensions.
\   Supports: html css js json txt png jpg gif svg ico

CREATE _MW-M-HTML 9 ALLOT
\ "text/html"
116 _MW-M-HTML C! 101 _MW-M-HTML 1+ C! 120 _MW-M-HTML 2 + C!
116 _MW-M-HTML 3 + C! 47 _MW-M-HTML 4 + C! 104 _MW-M-HTML 5 + C!
116 _MW-M-HTML 6 + C! 109 _MW-M-HTML 7 + C! 108 _MW-M-HTML 8 + C!

CREATE _MW-M-CSS 8 ALLOT
\ "text/css"
116 _MW-M-CSS C! 101 _MW-M-CSS 1+ C! 120 _MW-M-CSS 2 + C!
116 _MW-M-CSS 3 + C! 47 _MW-M-CSS 4 + C! 99 _MW-M-CSS 5 + C!
115 _MW-M-CSS 6 + C! 115 _MW-M-CSS 7 + C!

CREATE _MW-M-JS 22 ALLOT
\ "application/javascript"
97 _MW-M-JS C! 112 _MW-M-JS 1+ C! 112 _MW-M-JS 2 + C!
108 _MW-M-JS 3 + C! 105 _MW-M-JS 4 + C! 99 _MW-M-JS 5 + C!
97 _MW-M-JS 6 + C! 116 _MW-M-JS 7 + C! 105 _MW-M-JS 8 + C!
111 _MW-M-JS 9 + C! 110 _MW-M-JS 10 + C! 47 _MW-M-JS 11 + C!
106 _MW-M-JS 12 + C! 97 _MW-M-JS 13 + C! 118 _MW-M-JS 14 + C!
97 _MW-M-JS 15 + C! 115 _MW-M-JS 16 + C! 99 _MW-M-JS 17 + C!
114 _MW-M-JS 18 + C! 105 _MW-M-JS 19 + C! 112 _MW-M-JS 20 + C!
116 _MW-M-JS 21 + C!

CREATE _MW-M-JSON 16 ALLOT
\ "application/json" — reuse _MW-CT-JSON data
97 _MW-M-JSON C! 112 _MW-M-JSON 1+ C! 112 _MW-M-JSON 2 + C!
108 _MW-M-JSON 3 + C! 105 _MW-M-JSON 4 + C! 99 _MW-M-JSON 5 + C!
97 _MW-M-JSON 6 + C! 116 _MW-M-JSON 7 + C! 105 _MW-M-JSON 8 + C!
111 _MW-M-JSON 9 + C! 110 _MW-M-JSON 10 + C! 47 _MW-M-JSON 11 + C!
106 _MW-M-JSON 12 + C! 115 _MW-M-JSON 13 + C! 111 _MW-M-JSON 14 + C!
110 _MW-M-JSON 15 + C!

CREATE _MW-M-TEXT 10 ALLOT
\ "text/plain"
116 _MW-M-TEXT C! 101 _MW-M-TEXT 1+ C! 120 _MW-M-TEXT 2 + C!
116 _MW-M-TEXT 3 + C! 47 _MW-M-TEXT 4 + C! 112 _MW-M-TEXT 5 + C!
108 _MW-M-TEXT 6 + C! 97 _MW-M-TEXT 7 + C! 105 _MW-M-TEXT 8 + C!
110 _MW-M-TEXT 9 + C!

CREATE _MW-M-PNG 9 ALLOT
\ "image/png"
105 _MW-M-PNG C! 109 _MW-M-PNG 1+ C! 97 _MW-M-PNG 2 + C!
103 _MW-M-PNG 3 + C! 101 _MW-M-PNG 4 + C! 47 _MW-M-PNG 5 + C!
112 _MW-M-PNG 6 + C! 110 _MW-M-PNG 7 + C! 103 _MW-M-PNG 8 + C!

CREATE _MW-M-OCTET 24 ALLOT
\ "application/octet-stream"
97 _MW-M-OCTET C! 112 _MW-M-OCTET 1+ C! 112 _MW-M-OCTET 2 + C!
108 _MW-M-OCTET 3 + C! 105 _MW-M-OCTET 4 + C! 99 _MW-M-OCTET 5 + C!
97 _MW-M-OCTET 6 + C! 116 _MW-M-OCTET 7 + C! 105 _MW-M-OCTET 8 + C!
111 _MW-M-OCTET 9 + C! 110 _MW-M-OCTET 10 + C! 47 _MW-M-OCTET 11 + C!
111 _MW-M-OCTET 12 + C! 99 _MW-M-OCTET 13 + C! 116 _MW-M-OCTET 14 + C!
101 _MW-M-OCTET 15 + C! 116 _MW-M-OCTET 16 + C! 45 _MW-M-OCTET 17 + C!
115 _MW-M-OCTET 18 + C! 116 _MW-M-OCTET 19 + C! 114 _MW-M-OCTET 20 + C!
101 _MW-M-OCTET 21 + C! 97 _MW-M-OCTET 22 + C! 109 _MW-M-OCTET 23 + C!

\ Extension strings for comparison
CREATE _MW-E-HTML 4 ALLOT  104 _MW-E-HTML C! 116 _MW-E-HTML 1+ C! 109 _MW-E-HTML 2 + C! 108 _MW-E-HTML 3 + C!
CREATE _MW-E-HTM  3 ALLOT  104 _MW-E-HTM C!  116 _MW-E-HTM 1+ C!  109 _MW-E-HTM 2 + C!
CREATE _MW-E-CSS  3 ALLOT  99 _MW-E-CSS C!   115 _MW-E-CSS 1+ C!  115 _MW-E-CSS 2 + C!
CREATE _MW-E-JS   2 ALLOT  106 _MW-E-JS C!   115 _MW-E-JS 1+ C!
CREATE _MW-E-JSON 4 ALLOT  106 _MW-E-JSON C!  115 _MW-E-JSON 1+ C! 111 _MW-E-JSON 2 + C! 110 _MW-E-JSON 3 + C!
CREATE _MW-E-TXT  3 ALLOT  116 _MW-E-TXT C!  120 _MW-E-TXT 1+ C!  116 _MW-E-TXT 2 + C!
CREATE _MW-E-PNG  3 ALLOT  112 _MW-E-PNG C!  110 _MW-E-PNG 1+ C!  103 _MW-E-PNG 2 + C!

: _MW-STATIC-MIME  ( ext-a ext-u -- mime-a mime-u )
    2DUP _MW-E-HTML 4 STR-STRI= IF 2DROP _MW-M-HTML 9 EXIT THEN
    2DUP _MW-E-HTM  3 STR-STRI= IF 2DROP _MW-M-HTML 9 EXIT THEN
    2DUP _MW-E-CSS  3 STR-STRI= IF 2DROP _MW-M-CSS  8 EXIT THEN
    2DUP _MW-E-JS   2 STR-STRI= IF 2DROP _MW-M-JS  22 EXIT THEN
    2DUP _MW-E-JSON 4 STR-STRI= IF 2DROP _MW-M-JSON 16 EXIT THEN
    2DUP _MW-E-TXT  3 STR-STRI= IF 2DROP _MW-M-TEXT 10 EXIT THEN
    2DUP _MW-E-PNG  3 STR-STRI= IF 2DROP _MW-M-PNG   9 EXIT THEN
    2DROP _MW-M-OCTET 24 ;

\ MW-STATIC ( next-xt -- )
\   Serve static files if path matches the configured prefix.
\   Falls through to next if prefix doesn't match or file not found.
VARIABLE _MW-STATIC-FD

: MW-STATIC  ( next-xt -- )
    _MW-STATIC-PFX-A @ 0= IF EXECUTE EXIT THEN   \ not configured
    \ Check if path starts with prefix
    REQ-PATH
    2DUP _MW-STATIC-PFX-A @ _MW-STATIC-PFX-U @
    STR-STARTS? 0= IF
        2DROP EXECUTE EXIT
    THEN
    \ Strip prefix → filename
    _MW-STATIC-PFX-U @ - SWAP _MW-STATIC-PFX-U @ + SWAP  ( fname-a fname-u )
    DUP 0= IF 2DROP EXECUTE EXIT THEN  \ empty filename
    \ Try to open
    2DUP _MW-SOPEN DUP 0= IF
        DROP 2DROP EXECUTE EXIT         \ file not found → next
    THEN
    _MW-STATIC-FD !
    \ Detect MIME type from filename extension
    _MW-STATIC-EXT _MW-STATIC-MIME     ( next-xt mime-a mime-u )
    ROT DROP                            \ discard next-xt
    200 RESP-STATUS
    RESP-CONTENT-TYPE
    \ Read file content
    _MW-STATIC-READ-BUF 4096 _MW-STATIC-FD @ FREAD ( actual )
    _MW-STATIC-READ-BUF SWAP RESP-BODY
    RESP-SEND ;

\ ── Concurrency ──
\
\ All public words in this module are NOT reentrant.  They use shared
\ VARIABLE scratch space that would be corrupted by concurrent access.
\ Callers must ensure single-task access via WITH-GUARD, WITH-CRITICAL,
\ or by running with preemption disabled.
