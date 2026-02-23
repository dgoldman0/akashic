\ headers.f — HTTP header builder & parser for KDOS / Megapad-64
\
\ Stage 5-6 of the net/ library.  Replaces duplicated header code
\ in tools.f and bsky.f with a single reusable implementation.
\
\ Prefix: HDR-   (public API)
\         _HDR-  (internal helpers)
\
\ Load with:   REQUIRE headers.f

PROVIDED akashic-http-headers

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE HDR-ERR
1 CONSTANT HDR-E-OVERFLOW
2 CONSTANT HDR-E-MALFORMED

: HDR-FAIL       ( code -- )  HDR-ERR ! ;
: HDR-OK?        ( -- flag )  HDR-ERR @ 0= ;
: HDR-CLEAR-ERR  ( -- )       0 HDR-ERR ! ;

\ =====================================================================
\  Case-Insensitive Helpers (from tools.f pattern)
\ =====================================================================

: _CI-LOWER  ( c -- c' )
    DUP 65 >= OVER 90 <= AND IF 32 + THEN ;

: _CI-EQ  ( c1 c2 -- flag )
    _CI-LOWER SWAP _CI-LOWER = ;

: _CI-PREFIX  ( src match len -- flag )
    0 DO
        OVER I + C@  OVER I + C@  _CI-EQ
        0= IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ =====================================================================
\  Header Building
\ =====================================================================

CREATE _HDR-BUF 4096 ALLOT
VARIABLE _HDR-DST
VARIABLE _HDR-MAX
VARIABLE _HDR-LEN

: _HDR-APPEND  ( addr len -- )
    _HDR-LEN @ OVER + _HDR-MAX @ > IF
        HDR-E-OVERFLOW HDR-FAIL 2DROP EXIT
    THEN
    DUP >R
    _HDR-DST @ _HDR-LEN @ + SWAP CMOVE
    R> _HDR-LEN +! ;

: _HDR-CHAR  ( c -- )
    _HDR-LEN @ _HDR-MAX @ >= IF DROP HDR-E-OVERFLOW HDR-FAIL EXIT THEN
    _HDR-DST @ _HDR-LEN @ + C!  1 _HDR-LEN +! ;

: _HDR-CRLF  ( -- )
    13 _HDR-CHAR  10 _HDR-CHAR ;

\ HDR-RESET ( -- )   Clear header buffer for a new request.
: HDR-RESET  ( -- )
    HDR-CLEAR-ERR
    _HDR-BUF _HDR-DST !
    4096 _HDR-MAX !
    0 _HDR-LEN ! ;

\ HDR-SET-OUTPUT ( addr max -- )   Use an external buffer.
: HDR-SET-OUTPUT  ( addr max -- )
    _HDR-MAX ! _HDR-DST !  0 _HDR-LEN !  HDR-CLEAR-ERR ;

\ HDR-METHOD ( method-a method-u path-a path-u -- )
\   Append "METHOD /path HTTP/1.1\r\n".
: HDR-METHOD  ( method-a method-u path-a path-u -- )
    2SWAP _HDR-APPEND
    32 _HDR-CHAR
    _HDR-APPEND
    S"  HTTP/1.1" _HDR-APPEND
    _HDR-CRLF ;

: HDR-GET     ( path-a path-u -- )  S" GET"    2SWAP HDR-METHOD ;
: HDR-POST    ( path-a path-u -- )  S" POST"   2SWAP HDR-METHOD ;
: HDR-PUT     ( path-a path-u -- )  S" PUT"    2SWAP HDR-METHOD ;
: HDR-DELETE  ( path-a path-u -- )  S" DELETE" 2SWAP HDR-METHOD ;

\ HDR-ADD ( name-a name-u val-a val-u -- )
\   Append "Name: Value\r\n".
: HDR-ADD  ( name-a name-u val-a val-u -- )
    2SWAP _HDR-APPEND
    S" : " _HDR-APPEND
    _HDR-APPEND
    _HDR-CRLF ;

: HDR-HOST  ( host-a host-u -- )
    S" Host" 2SWAP HDR-ADD ;

\ HDR-AUTH-BEARER ( token-a token-u -- )
\   Builds "Authorization: Bearer <token>\r\n" inline.
: HDR-AUTH-BEARER  ( token-a token-u -- )
    S" Authorization: Bearer " _HDR-APPEND
    _HDR-APPEND
    _HDR-CRLF ;

: HDR-CONTENT-TYPE  ( ct-a ct-u -- )
    S" Content-Type" 2SWAP HDR-ADD ;

: HDR-CONTENT-JSON  ( -- )
    S" application/json" HDR-CONTENT-TYPE ;

: HDR-CONTENT-FORM  ( -- )
    S" application/x-www-form-urlencoded" HDR-CONTENT-TYPE ;

\ HDR-CONTENT-LENGTH ( n -- )
CREATE _HCL-TMP 12 ALLOT
VARIABLE _HCL-LEN

: HDR-CONTENT-LENGTH  ( n -- )
    S" Content-Length: " _HDR-APPEND
    0 _HCL-LEN !
    DUP 0= IF
        DROP 48 _HDR-CHAR
    ELSE
        BEGIN DUP 0> WHILE
            DUP 10 MOD 48 + _HCL-TMP _HCL-LEN @ + C!
            1 _HCL-LEN +!
            10 /
        REPEAT DROP
        _HCL-LEN @ 0 DO
            _HCL-TMP _HCL-LEN @ 1 - I - + C@ _HDR-CHAR
        LOOP
    THEN
    _HDR-CRLF ;

: HDR-CONNECTION-CLOSE  ( -- )
    S" Connection" S" close" HDR-ADD ;

: HDR-ACCEPT  ( type-a type-u -- )
    S" Accept" 2SWAP HDR-ADD ;

: HDR-USER-AGENT  ( ua-a ua-u -- )
    S" User-Agent" 2SWAP HDR-ADD ;

\ HDR-END ( -- )   Append blank line (end of headers).
: HDR-END  ( -- )  _HDR-CRLF ;

\ HDR-BODY ( body-a body-u -- )   Append body data after headers.
: HDR-BODY  ( body-a body-u -- )  _HDR-APPEND ;

\ HDR-RESULT ( -- addr len )
: HDR-RESULT  ( -- addr len )  _HDR-DST @ _HDR-LEN @ ;

\ =====================================================================
\  Header Parsing
\ =====================================================================

\ HDR-FIND-HEND ( addr len -- offset | 0 )
\   Find \r\n\r\n or \n\n boundary.  Returns byte offset of body start.
VARIABLE _HFH-PTR
VARIABLE _HFH-END
VARIABLE _HFH-BASE

: HDR-FIND-HEND  ( addr len -- offset )
    OVER + _HFH-END !
    DUP _HFH-BASE !  _HFH-PTR !
    BEGIN
        _HFH-PTR @ 3 + _HFH-END @ <=
    WHILE
        \ Check \r\n\r\n
        _HFH-PTR @ C@     13 =
        _HFH-PTR @ 1 + C@ 10 = AND
        _HFH-PTR @ 2 + C@ 13 = AND
        _HFH-PTR @ 3 + C@ 10 = AND IF
            _HFH-PTR @ _HFH-BASE @ - 4 + EXIT
        THEN
        \ Check \n\n
        _HFH-PTR @ C@     10 =
        _HFH-PTR @ 1 + C@ 10 = AND IF
            _HFH-PTR @ _HFH-BASE @ - 2 + EXIT
        THEN
        1 _HFH-PTR +!
    REPEAT
    \ Final \n\n check (last 2 bytes)
    _HFH-PTR @ 1 + _HFH-END @ <= IF
        _HFH-PTR @ C@     10 =
        _HFH-PTR @ 1 + C@ 10 = AND IF
            _HFH-PTR @ _HFH-BASE @ - 2 + EXIT
        THEN
    THEN
    0 ;

\ HDR-PARSE-STATUS ( addr len -- status-code )
\   Extract 3-digit status from "HTTP/1.x NNN reason".
: HDR-PARSE-STATUS  ( addr len -- code )
    9 < IF DROP 0 EXIT THEN
    9 +
    DUP C@     48 -  100 *
    OVER 1 + C@ 48 -   10 * +
    SWAP 2 + C@ 48 -        + ;

\ HDR-PARSE-CLEN ( hdr-addr hdr-len -- content-length | -1 )
\   Find Content-Length header value, case-insensitive.
VARIABLE _HPC-PTR
VARIABLE _HPC-END
VARIABLE _HPC-ACC

: HDR-PARSE-CLEN  ( hdr-addr hdr-len -- n )
    OVER + _HPC-END !  _HPC-PTR !
    BEGIN
        _HPC-PTR @ 16 + _HPC-END @ <=
    WHILE
        _HPC-PTR @ S" content-length: " _CI-PREFIX IF
            16 _HPC-PTR +!
            0 _HPC-ACC !
            BEGIN
                _HPC-PTR @ _HPC-END @ <
                _HPC-PTR @ C@ 48 >= AND
                _HPC-PTR @ C@ 57 <= AND
            WHILE
                _HPC-PTR @ C@ 48 -  _HPC-ACC @ 10 * +  _HPC-ACC !
                1 _HPC-PTR +!
            REPEAT
            _HPC-ACC @ EXIT
        THEN
        1 _HPC-PTR +!
    REPEAT
    -1 ;

\ HDR-FIND ( hdr-a hdr-u name-a name-u -- val-a val-u flag )
\   Find response header by name (case-insensitive).
VARIABLE _HF-PTR
VARIABLE _HF-END
VARIABLE _HF-NADDR
VARIABLE _HF-NLEN
VARIABLE _HF-SCAN

: HDR-FIND  ( hdr-a hdr-u name-a name-u -- val-a val-u flag )
    _HF-NLEN ! _HF-NADDR !
    OVER + _HF-END !  _HF-PTR !
    BEGIN
        _HF-PTR @ _HF-NLEN @ + 2 + _HF-END @ <=
    WHILE
        _HF-PTR @ _HF-NADDR @ _HF-NLEN @ _CI-PREFIX IF
            _HF-PTR @ _HF-NLEN @ + C@ 58 =
            _HF-PTR @ _HF-NLEN @ + 1 + C@ 32 = AND IF
                \ Value starts after "name: "
                _HF-PTR @ _HF-NLEN @ + 2 + _HF-SCAN !
                \ Scan to end of line
                BEGIN
                    _HF-SCAN @ _HF-END @ <
                    _HF-SCAN @ C@ 13 <> AND
                    _HF-SCAN @ C@ 10 <> AND
                WHILE
                    1 _HF-SCAN +!
                REPEAT
                _HF-PTR @ _HF-NLEN @ + 2 +    \ val-start
                _HF-SCAN @ OVER -              \ val-len
                -1 EXIT
            THEN
        THEN
        1 _HF-PTR +!
    REPEAT
    0 0 0 ;

\ HDR-CHUNKED? ( hdr-a hdr-u -- flag )
: HDR-CHUNKED?  ( hdr-a hdr-u -- flag )
    S" Transfer-Encoding" HDR-FIND IF
        7 < IF DROP 0 EXIT THEN
        S" chunked" _CI-PREFIX
    ELSE
        2DROP 0
    THEN ;

\ HDR-LOCATION ( hdr-a hdr-u -- url-a url-u flag )
: HDR-LOCATION  ( hdr-a hdr-u -- url-a url-u flag )
    S" Location" HDR-FIND ;

\ HDR-SET-COOKIE ( hdr-a hdr-u -- val-a val-u flag )
: HDR-SET-COOKIE  ( hdr-a hdr-u -- val-a val-u flag )
    S" Set-Cookie" HDR-FIND ;
