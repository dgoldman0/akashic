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
