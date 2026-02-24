\ uri.f — Generic RFC 3986 URI parser for KDOS / Megapad-64
\
\ Decomposes any URI into: scheme, authority, userinfo, host, port,
\ path, query, fragment.  Scheme-agnostic — works with at:, did:,
\ ipfs:, urn:, mailto:, custom schemes, etc.
\
\ RFC 3986 grammar:
\   URI = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
\   hier-part = "//" authority path-abempty / path-absolute / ...
\   authority = [ userinfo "@" ] host [ ":" port ]
\
\ Prefix: URI-   (public API)
\         _URI-  (internal helpers)
\
\ Load with:   REQUIRE uri.f

REQUIRE ../utils/string.f

PROVIDED akashic-uri

\ =====================================================================
\  Result Storage — pointers into original input (zero-copy)
\ =====================================================================

\ Each component is (addr, len) pointing into the original string.
VARIABLE URI-SCHEME-A    VARIABLE URI-SCHEME-L
VARIABLE URI-AUTH-A      VARIABLE URI-AUTH-L      \ full authority
VARIABLE URI-UINFO-A    VARIABLE URI-UINFO-L     \ userinfo (before @)
VARIABLE URI-HOST-A     VARIABLE URI-HOST-L
VARIABLE URI-PORT-A     VARIABLE URI-PORT-L
VARIABLE URI-PATH-A     VARIABLE URI-PATH-L
VARIABLE URI-QUERY-A    VARIABLE URI-QUERY-L
VARIABLE URI-FRAG-A     VARIABLE URI-FRAG-L

\ =====================================================================
\  Internal State
\ =====================================================================

VARIABLE _URI-PTR        \ current pointer into input
VARIABLE _URI-REM        \ remaining bytes

\ _URI-CLEAR ( -- )  Zero all result fields.
: _URI-CLEAR  ( -- )
    0 URI-SCHEME-A !  0 URI-SCHEME-L !
    0 URI-AUTH-A   !  0 URI-AUTH-L   !
    0 URI-UINFO-A  !  0 URI-UINFO-L  !
    0 URI-HOST-A   !  0 URI-HOST-L   !
    0 URI-PORT-A   !  0 URI-PORT-L   !
    0 URI-PATH-A   !  0 URI-PATH-L   !
    0 URI-QUERY-A  !  0 URI-QUERY-L  !
    0 URI-FRAG-A   !  0 URI-FRAG-L   ! ;

\ _URI-SCAN ( char -- idx | -1 )
\   Find char in remaining input.
: _URI-SCAN  ( c -- idx )
    _URI-PTR @ _URI-REM @ ROT STR-INDEX ;

\ _URI-ADV ( n -- )  Advance pointer by n bytes.
: _URI-ADV  ( n -- )
    DUP _URI-PTR +!  NEGATE _URI-REM +! ;

\ =====================================================================
\  URI-PARSE
\ =====================================================================

\ URI-PARSE ( addr len -- ior )
\   Parse a URI string.  Returns 0 on success, -1 on failure.
\   Results stored in URI-SCHEME-A/L, URI-HOST-A/L, etc.
\   All result pointers point into the ORIGINAL input string.
: URI-PARSE  ( addr len -- ior )
    _URI-CLEAR
    DUP 0= IF 2DROP -1 EXIT THEN
    _URI-REM ! _URI-PTR !

    \ ── 1. Scheme: everything up to first ':' ──
    58 _URI-SCAN                 \ ':'
    DUP 0< IF DROP -1 EXIT THEN \ no colon → not a URI
    DUP 0= IF DROP -1 EXIT THEN \ empty scheme
    _URI-PTR @ URI-SCHEME-A !
    DUP URI-SCHEME-L !
    1+ _URI-ADV                  \ skip past ':'

    \ ── 2. Check for "//" authority ──
    _URI-REM @ 2 >= IF
        _URI-PTR @ C@ 47 = IF               \ '/'
        _URI-PTR @ 1+ C@ 47 = IF            \ '/'
            2 _URI-ADV                       \ skip "//"

            \ Find end of authority: next '/', '?', '#', or end
            \ Scan for the delimiter
            _URI-PTR @          \ auth-start
            0                   \ auth-len counter
            BEGIN
                DUP _URI-REM @ < IF
                    _URI-PTR @ OVER + C@
                    DUP 47 = SWAP DUP 63 = SWAP 35 = OR OR
                    IF -1 ELSE 1+ 0 THEN
                ELSE -1 THEN
            UNTIL
            \ Stack: auth-start auth-len
            OVER URI-AUTH-A !
            DUP  URI-AUTH-L !

            \ Parse authority sub-components
            \ Check for userinfo: '@' in authority
            OVER SWAP               \ auth-a auth-a auth-l
            2DUP 64 STR-INDEX       \ auth-a auth-a auth-l @-idx
            DUP 0< IF
                \ No '@': no userinfo, whole thing is host[:port]
                DROP
                \ Stack: auth-a auth-a auth-l
                DROP                 \ auth-a auth-a — drop extra
                \ Oops fix: auth-a host-a host-l
                URI-AUTH-A @ URI-AUTH-L @
            ELSE
                \ Has '@': userinfo = [0..@-idx), host part = [@-idx+1..)
                OVER OVER                         \ a a l @i a l
                DROP                              \ a a l @i a
                DROP                              \ a a l @i
                \ Stack: auth-a auth-a auth-l @-idx
                SWAP DROP                         \ auth-a auth-a @-idx
                SWAP URI-UINFO-A !                \ auth-a @-idx
                DUP  URI-UINFO-L !                \ auth-a @-idx
                \ host part starts at auth-a + @-idx + 1
                1+ OVER +                         \ auth-a host-a
                SWAP DROP                         \ host-a
                \ host-len = auth-l - @-idx - 1
                URI-AUTH-L @ URI-UINFO-L @ - 1-   \ host-a host-l
            THEN

            \ Stack: host-a host-l — parse host[:port]
            \ Check for ':' (port separator) — scan from right
            2DUP 58 STR-INDEX       \ host-a host-l colon-idx
            DUP 0< IF
                \ No port
                DROP
                URI-HOST-A !  URI-HOST-L !
            ELSE
                \ host = [0..colon), port = [colon+1..)
                2 PICK URI-HOST-A !        \ host addr
                DUP    URI-HOST-L !        \ colon-idx = host len
                \ port starts at host-a + colon-idx + 1
                1+ 2 PICK +                \ port-a
                URI-PORT-A !
                OVER URI-HOST-L @ + 1+     \ after colon
                \ port-len = host-l - colon-idx - 1
                SWAP DROP                  \ drop host-a
                URI-AUTH-A @ URI-AUTH-L @ + \ end of authority
                URI-PORT-A @ -             \ port-len
                URI-PORT-L !
            THEN

            URI-AUTH-L @ _URI-ADV    \ advance past authority
        THEN THEN
    THEN

    \ ── 3. Path: up to '?' or '#' or end ──
    _URI-REM @ 0> IF
        _URI-PTR @ URI-PATH-A !
        0                        \ path-len counter
        BEGIN
            DUP _URI-REM @ < IF
                _URI-PTR @ OVER + C@
                DUP 63 = SWAP 35 = OR
                IF -1 ELSE 1+ 0 THEN
            ELSE -1 THEN
        UNTIL
        DUP URI-PATH-L !
        _URI-ADV
    THEN

    \ ── 4. Query: after '?' up to '#' or end ──
    _URI-REM @ 0> IF
        _URI-PTR @ C@ 63 = IF   \ '?'
            1 _URI-ADV           \ skip '?'
            _URI-PTR @ URI-QUERY-A !
            0
            BEGIN
                DUP _URI-REM @ < IF
                    _URI-PTR @ OVER + C@ 35 =
                    IF -1 ELSE 1+ 0 THEN
                ELSE -1 THEN
            UNTIL
            DUP URI-QUERY-L !
            _URI-ADV
        THEN
    THEN

    \ ── 5. Fragment: after '#' to end ──
    _URI-REM @ 0> IF
        _URI-PTR @ C@ 35 = IF   \ '#'
            1 _URI-ADV
            _URI-PTR @ URI-FRAG-A !
            _URI-REM @ URI-FRAG-L !
            _URI-REM @ _URI-ADV
        THEN
    THEN

    0 ;

\ =====================================================================
\  URI-BUILD
\ =====================================================================

VARIABLE _UB-DST
VARIABLE _UB-MAX
VARIABLE _UB-POS

\ _UB-APPEND ( addr len -- )
: _UB-APPEND  ( addr len -- )
    0 ?DO
        _UB-POS @ _UB-MAX @ < IF
            DUP I + C@ _UB-DST @ _UB-POS @ + C!
            1 _UB-POS +!
        THEN
    LOOP DROP ;

\ _UB-CH ( c -- )
: _UB-CH  ( c -- )
    _UB-POS @ _UB-MAX @ < IF
        _UB-DST @ _UB-POS @ + C!  1 _UB-POS +!
    ELSE DROP THEN ;

\ URI-BUILD ( dst max -- written )
\   Reconstruct URI from current component values.
: URI-BUILD  ( dst max -- written )
    _UB-MAX ! _UB-DST !  0 _UB-POS !
    URI-SCHEME-L @ 0> IF
        URI-SCHEME-A @ URI-SCHEME-L @ _UB-APPEND
        58 _UB-CH                \ ':'
    THEN
    URI-AUTH-L @ 0> IF
        47 _UB-CH 47 _UB-CH     \ "//"
        URI-UINFO-L @ 0> IF
            URI-UINFO-A @ URI-UINFO-L @ _UB-APPEND
            64 _UB-CH            \ '@'
        THEN
        URI-HOST-L @ 0> IF
            URI-HOST-A @ URI-HOST-L @ _UB-APPEND
        THEN
        URI-PORT-L @ 0> IF
            58 _UB-CH            \ ':'
            URI-PORT-A @ URI-PORT-L @ _UB-APPEND
        THEN
    THEN
    URI-PATH-L @ 0> IF
        URI-PATH-A @ URI-PATH-L @ _UB-APPEND
    THEN
    URI-QUERY-L @ 0> IF
        63 _UB-CH                \ '?'
        URI-QUERY-A @ URI-QUERY-L @ _UB-APPEND
    THEN
    URI-FRAG-L @ 0> IF
        35 _UB-CH                \ '#'
        URI-FRAG-A @ URI-FRAG-L @ _UB-APPEND
    THEN
    _UB-POS @ ;
