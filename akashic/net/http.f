\ http.f — HTTP/1.1 client for KDOS / Megapad-64
\
\ Stage 7-9 of the net/ library.
\ REQUIRE url.f
\ REQUIRE headers.f
\
\ Prefix: HTTP-   (public API)
\         _HTTP-  (internal helpers)
\
\ Load with:   REQUIRE http.f

PROVIDED akashic-http

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE HTTP-ERR
1 CONSTANT HTTP-E-DNS
2 CONSTANT HTTP-E-CONNECT
3 CONSTANT HTTP-E-SEND
4 CONSTANT HTTP-E-TIMEOUT
5 CONSTANT HTTP-E-PARSE
6 CONSTANT HTTP-E-OVERFLOW
7 CONSTANT HTTP-E-TLS
8 CONSTANT HTTP-E-REDIRECT

: HTTP-FAIL       ( code -- )  HTTP-ERR ! ;
: HTTP-OK?        ( -- flag )  HTTP-ERR @ 0= ;
: HTTP-CLEAR-ERR  ( -- )       0 HTTP-ERR ! ;

\ =====================================================================
\  DNS Cache (8-slot) — must appear before Layer 0 so HTTP-CONNECT
\  can call HTTP-DNS-LOOKUP.
\ =====================================================================

8 CONSTANT _DNS-SLOTS
CREATE _DNS-HOSTS  _DNS-SLOTS 64 * ALLOT     \ 8 * 64 = 512 bytes
CREATE _DNS-LENS   _DNS-SLOTS CELLS ALLOT
CREATE _DNS-IPS    _DNS-SLOTS CELLS ALLOT

\ HTTP-DNS-FLUSH ( -- )
: HTTP-DNS-FLUSH  ( -- )
    _DNS-HOSTS _DNS-SLOTS 64 * 0 FILL
    _DNS-LENS  _DNS-SLOTS CELLS 0 FILL
    _DNS-IPS   _DNS-SLOTS CELLS 0 FILL ;

HTTP-DNS-FLUSH

\ _DNS-SLOT-HOST ( n -- addr )   Host buffer for slot n.
: _DNS-SLOT-HOST  ( n -- addr )  64 * _DNS-HOSTS + ;

VARIABLE _DM-HOST
VARIABLE _DM-LEN

\ _DNS-MATCH? ( host-a host-u slot -- flag )
: _DNS-MATCH?  ( host-a host-u slot -- flag )
    DUP CELLS _DNS-LENS + @                \ stored length
    SWAP _DNS-SLOT-HOST                    \ slot host addr
    _DM-HOST ! _DM-LEN !                   \ save stored host/len
    _DM-LEN @ <> IF DROP 0 EXIT THEN       \ length mismatch; drop host-a
    \ ( host-a )  lengths match
    _DM-LEN @  _DM-HOST @  _DM-LEN @       \ ( host-a host-u slot-host stored-len )
    COMPARE 0= ;

\ HTTP-DNS-LOOKUP ( host-a host-u -- ip | 0 )
\   Check cache first, else DNS-RESOLVE and cache.
: HTTP-DNS-LOOKUP  ( host-a host-u -- ip )
    \ Search cache
    _DNS-SLOTS 0 DO
        2DUP I CELLS _DNS-LENS + @ 0> IF
            2DUP I _DNS-MATCH? IF
                2DROP I CELLS _DNS-IPS + @ UNLOOP EXIT
            THEN
        THEN
    LOOP
    \ Cache miss — resolve
    2DUP DNS-RESOLVE                       ( host-a host-u ip )
    DUP 0= IF NIP NIP EXIT THEN           \ failed
    \ Store in slot 0
    0 CELLS _DNS-IPS + !                   \ store ip;   ( host-a host-u )
    DUP 0 CELLS _DNS-LENS + !             \ store len;  ( host-a host-u )
    0 _DNS-SLOT-HOST SWAP CMOVE            \ copy host;  ( )
    0 CELLS _DNS-IPS + @ ;                 \ return ip

\ =====================================================================
\  Layer 0 — Connection Abstraction
\ =====================================================================
\
\  Dispatches to TCP-* or TLS-* based on a tls? flag.
\  TLS connections also set SNI hostname before connecting.

VARIABLE _HTTP-CTX              \ connection handle (TCB or TLS ctx)
VARIABLE _HTTP-TLS              \ -1=TLS, 0=plaintext
VARIABLE _HTTP-LPORT            \ local port counter
RANDOM32 16383 AND 49152 + _HTTP-LPORT !

: _HTTP-NEXT-PORT  ( -- port )
    _HTTP-LPORT @ DUP 1 +
    DUP 65535 > IF DROP 49152 THEN
    _HTTP-LPORT ! ;

VARIABLE _HC-HOST
VARIABLE _HC-HLEN

\ HTTP-CONNECT ( host-a host-u port tls? -- ctx | 0 )
\   Open TCP or TLS connection.  Resolves hostname via DNS.
: HTTP-CONNECT  ( host-a host-u port tls? -- ctx )
    _HTTP-TLS !
    >R                                     \ save port
    DUP _HC-HLEN !  OVER _HC-HOST !        \ save host for SNI
    HTTP-DNS-LOOKUP                        \ ( ip | 0 )
    DUP 0= IF
        R> DROP HTTP-E-DNS HTTP-FAIL EXIT
    THEN
    R> _HTTP-NEXT-PORT                     \ ( ip port local-port )
    _HTTP-TLS @ IF
        \ Set SNI before TLS connect
        _HC-HLEN @ 63 MIN DUP TLS-SNI-LEN !
        _HC-HOST @ TLS-SNI-HOST ROT CMOVE
        TLS-CONNECT
    ELSE
        TCP-CONNECT
    THEN
    DUP 0= IF
        HTTP-E-CONNECT HTTP-FAIL EXIT
    THEN
    _HTTP-CTX !
    \ Wait for handshake (TCP or TLS-internal)
    _HTTP-TLS @ 0= IF
        200 0 DO TCP-POLL NET-IDLE LOOP
    THEN
    _HTTP-CTX @ ;

\ HTTP-DISCONNECT ( -- )
: HTTP-DISCONNECT  ( -- )
    _HTTP-TLS @ IF
        _HTTP-CTX @ TLS-CLOSE
    ELSE
        _HTTP-CTX @ TCP-CLOSE
    THEN ;

\ HTTP-SEND ( buf len -- flag )
: HTTP-SEND  ( buf len -- flag )
    _HTTP-TLS @ IF
        _HTTP-CTX @ -ROT TLS-SEND
    ELSE
        _HTTP-CTX @ -ROT TCP-SEND
    THEN ;

\ HTTP-RECV ( buf max -- n )
: HTTP-RECV  ( buf max -- n )
    _HTTP-TLS @ IF
        _HTTP-CTX @ -ROT TLS-RECV
    ELSE
        _HTTP-CTX @ -ROT TCP-RECV
    THEN ;

\ =====================================================================
\  Layer 1 — Receive Loop
\ =====================================================================

VARIABLE HTTP-RECV-BUF
VARIABLE HTTP-RECV-LEN
VARIABLE HTTP-RECV-MAX
VARIABLE _HR-EMPTY              \ consecutive empty-read counter

\ HTTP-USE-STATIC ( addr max -- )
\   Use a caller-provided buffer for receiving.
: HTTP-USE-STATIC  ( addr max -- )
    HTTP-RECV-MAX ! HTTP-RECV-BUF ! 0 HTTP-RECV-LEN ! ;

\ HTTP-RECV-LOOP ( -- )
\   Receive full response into HTTP-RECV-BUF.  Polls with TCP-POLL
\   + NET-IDLE.  Stops after 10 consecutive empty reads (or 50 if
\   no data has arrived yet — prevents long spin on broken connections).
: HTTP-RECV-LOOP  ( -- )
    0 HTTP-RECV-LEN !  0 _HR-EMPTY !
    500 0 DO
        TCP-POLL NET-IDLE
        HTTP-RECV-LEN @ HTTP-RECV-MAX @ >= IF LEAVE THEN
        HTTP-RECV-BUF @ HTTP-RECV-LEN @ +
        HTTP-RECV-MAX @ HTTP-RECV-LEN @ -
        HTTP-RECV                              \ ( n )
        DUP 0> IF
            HTTP-RECV-LEN +!
            0 _HR-EMPTY !
        ELSE DUP -1 = IF
            \ TLS decrypt error
            DROP HTTP-E-TLS HTTP-FAIL LEAVE
        ELSE
            DROP
            _HR-EMPTY @ 1 + DUP _HR-EMPTY !
            HTTP-RECV-LEN @ 0> IF
                10 >= IF LEAVE THEN
            ELSE
                50 >= IF LEAVE THEN
            THEN
        THEN THEN
    LOOP ;

\ =====================================================================
\  Layer 2 — Response Processing
\ =====================================================================

VARIABLE HTTP-STATUS
VARIABLE HTTP-BODY-ADDR
VARIABLE HTTP-BODY-LEN
VARIABLE _HTTP-HEND-OFF         \ header/body boundary offset

\ HTTP-PARSE ( -- ior )
\   Parse received response.  Sets HTTP-STATUS, HTTP-BODY-ADDR/LEN.
: HTTP-PARSE  ( -- ior )
    HTTP-RECV-BUF @ HTTP-RECV-LEN @
    DUP 0= IF
        2DROP HTTP-E-TIMEOUT HTTP-FAIL -1 EXIT
    THEN
    \ Parse status code
    2DUP HDR-PARSE-STATUS HTTP-STATUS !
    \ Find header/body boundary
    2DUP HDR-FIND-HEND
    DUP 0= IF
        DROP 2DROP HTTP-E-PARSE HTTP-FAIL -1 EXIT
    THEN
    _HTTP-HEND-OFF !
    \ Extract body
    OVER _HTTP-HEND-OFF @ + HTTP-BODY-ADDR !
    DUP _HTTP-HEND-OFF @ - HTTP-BODY-LEN !
    \ Adjust body length by Content-Length if present
    2DUP HDR-PARSE-CLEN
    DUP -1 <> IF
        HTTP-BODY-LEN @ MIN HTTP-BODY-LEN !
    ELSE DROP THEN
    2DROP 0 ;

\ HTTP-DECHUNK ( addr len -- addr' len' )
\   Dechunk HTTP chunked transfer encoding in place.
\   Reads "hex-size\r\n...data...\r\n" and compacts data.
VARIABLE _HDC-SRC
VARIABLE _HDC-SLEN
VARIABLE _HDC-DST
VARIABLE _HDC-DLEN

\ _HDC-HEX ( -- n )
\   Parse hex chunk size at _HDC-SRC, advance past \r\n.
: _HDC-HEX  ( -- n )
    0                                      \ accumulator
    BEGIN
        _HDC-SLEN @ 0>
    WHILE
        _HDC-SRC @ C@                      \ peek at char
        DUP 13 = OVER 10 = OR IF           \ \r or \n — end of hex
            DROP
            _HDC-SLEN @ 0> IF
                _HDC-SRC @ C@ 13 = IF
                    1 _HDC-SRC +!  -1 _HDC-SLEN +!
                THEN
            THEN
            _HDC-SLEN @ 0> IF
                _HDC-SRC @ C@ 10 = IF
                    1 _HDC-SRC +!  -1 _HDC-SLEN +!
                THEN
            THEN
            EXIT                           \ return accumulated value
        THEN
        \ Convert hex digit
        DUP 48 >= OVER 57 <= AND IF 48 - ELSE
        DUP 65 >= OVER 70 <= AND IF 55 - ELSE
        DUP 97 >= OVER 102 <= AND IF 87 - ELSE
            DROP EXIT                      \ invalid — return what we have
        THEN THEN THEN
        SWAP 16 * +
        1 _HDC-SRC +!  -1 _HDC-SLEN +!
    REPEAT ;

: HTTP-DECHUNK  ( addr len -- addr' len' )
    _HDC-SLEN ! DUP _HDC-SRC ! _HDC-DST !  0 _HDC-DLEN !
    BEGIN
        _HDC-SLEN @ 0>
    WHILE
        _HDC-HEX                               ( chunk-size )
        DUP 0= IF DROP                         \ 0 = final chunk
            _HDC-DST @ _HDC-DLEN @ EXIT
        THEN
        \ Copy chunk-size bytes
        _HDC-SLEN @ MIN                         ( actual )
        DUP >R
        _HDC-SRC @ _HDC-DST @ _HDC-DLEN @ + R> CMOVE
        DUP _HDC-DLEN +!
        DUP _HDC-SRC +!  NEGATE _HDC-SLEN +!
        \ Skip trailing \r\n after chunk data
        _HDC-SLEN @ 0> IF
            _HDC-SRC @ C@ 13 = IF
                1 _HDC-SRC +!  -1 _HDC-SLEN +!
            THEN
        THEN
        _HDC-SLEN @ 0> IF
            _HDC-SRC @ C@ 10 = IF
                1 _HDC-SRC +!  -1 _HDC-SLEN +!
            THEN
        THEN
    REPEAT
    _HDC-DST @ _HDC-DLEN @ ;

\ HTTP-HEADER ( name-a name-u -- val-a val-u flag )
\   Find a response header from the last response.
: HTTP-HEADER  ( name-a name-u -- val-a val-u flag )
    HTTP-RECV-BUF @ _HTTP-HEND-OFF @
    2SWAP HDR-FIND ;

\ =====================================================================
\  Session / Persistent Headers
\ =====================================================================
\  Must appear before Layer 3 so HTTP-REQUEST / HTTP-POST can call
\  HTTP-APPLY-SESSION.

CREATE _HTTP-BEARER 256 ALLOT
VARIABLE _HTTP-BEARER-LEN
0 _HTTP-BEARER-LEN !

CREATE _HTTP-UA 64 ALLOT
VARIABLE _HTTP-UA-LEN
0 _HTTP-UA-LEN !

\ HTTP-SET-BEARER ( token-a token-u -- )
: HTTP-SET-BEARER  ( token-a token-u -- )
    255 MIN DUP _HTTP-BEARER-LEN !
    _HTTP-BEARER SWAP CMOVE ;

\ HTTP-CLEAR-BEARER ( -- )
: HTTP-CLEAR-BEARER  ( -- )  0 _HTTP-BEARER-LEN ! ;

\ HTTP-SET-UA ( ua-a ua-u -- )
: HTTP-SET-UA  ( ua-a ua-u -- )
    63 MIN DUP _HTTP-UA-LEN !
    _HTTP-UA SWAP CMOVE ;

\ HTTP-APPLY-SESSION ( -- )
\   Add session headers (bearer token, user-agent).
: HTTP-APPLY-SESSION  ( -- )
    _HTTP-BEARER-LEN @ 0> IF
        _HTTP-BEARER _HTTP-BEARER-LEN @ HDR-AUTH-BEARER
    THEN
    _HTTP-UA-LEN @ 0> IF
        _HTTP-UA _HTTP-UA-LEN @ HDR-USER-AGENT
    THEN ;

\ =====================================================================
\  Layer 3 — Request Execution
\ =====================================================================

\ HTTP-REQUEST ( method-a method-u url-a url-u -- ior )
\   Full request cycle: parse URL → connect → build/send → recv → parse.
: HTTP-REQUEST  ( method-a method-u url-a url-u -- ior )
    HTTP-CLEAR-ERR
    \ Parse URL
    URL-PARSE 0<> IF
        2DROP HTTP-E-PARSE HTTP-FAIL -1 EXIT
    THEN
    \ Connect
    URL-HOST URL-HOST-LEN @
    URL-PORT @
    URL-SCHEME @ URL-S-HTTPS = URL-SCHEME @ URL-S-FTPS = OR
    URL-SCHEME @ URL-S-WSS = OR
    HTTP-CONNECT
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    DROP                                   \ drop ctx (stored in _HTTP-CTX)
    \ Build request
    HDR-RESET
    URL-PATH URL-PATH-LEN @ HDR-METHOD     ( method was on stack )
    URL-HOST URL-HOST-LEN @ HDR-HOST
    HDR-CONNECTION-CLOSE
    S" KDOS/1.1 Megapad-64" HDR-USER-AGENT
    HTTP-APPLY-SESSION
    HDR-END
    \ Send
    HDR-RESULT HTTP-SEND
    0= IF
        HTTP-DISCONNECT
        HTTP-E-SEND HTTP-FAIL -1 EXIT
    THEN
    \ Receive
    HTTP-RECV-LOOP
    \ Disconnect
    HTTP-DISCONNECT
    \ Parse response
    HTTP-PARSE ;

\ HTTP-GET ( url-a url-u -- body-a body-u | 0 0 )
\   Convenience: GET request, return body.
: HTTP-GET  ( url-a url-u -- body-a body-u )
    S" GET" 2SWAP HTTP-REQUEST
    0= IF
        HTTP-BODY-ADDR @ HTTP-BODY-LEN @
    ELSE 0 0 THEN ;

\ HTTP-POST ( url-a url-u body-a body-u ct-a ct-u -- resp-a resp-u | 0 0 )
\   POST with Content-Type and body.
VARIABLE _HP-BODY
VARIABLE _HP-BLEN
VARIABLE _HP-CT
VARIABLE _HP-CTLEN

: HTTP-POST  ( url-a url-u body-a body-u ct-a ct-u -- resp-a resp-u )
    _HP-CTLEN ! _HP-CT !                   \ save content-type
    _HP-BLEN ! _HP-BODY !                  \ save body
    \ Parse URL
    URL-PARSE 0<> IF
        HTTP-E-PARSE HTTP-FAIL 0 0 EXIT
    THEN
    URL-HOST URL-HOST-LEN @
    URL-PORT @
    URL-SCHEME @ URL-S-HTTPS =
    HTTP-CONNECT
    DUP 0= IF DROP 0 0 EXIT THEN
    DROP
    \ Build request
    HDR-RESET
    S" POST" URL-PATH URL-PATH-LEN @ HDR-METHOD
    URL-HOST URL-HOST-LEN @ HDR-HOST
    _HP-BLEN @ HDR-CONTENT-LENGTH
    _HP-CT @ _HP-CTLEN @ HDR-CONTENT-TYPE
    HDR-CONNECTION-CLOSE
    HTTP-APPLY-SESSION
    HDR-END
    _HP-BODY @ _HP-BLEN @ HDR-BODY         \ append body
    \ Send + recv + parse
    HDR-RESULT HTTP-SEND
    0= IF
        HTTP-DISCONNECT
        HTTP-E-SEND HTTP-FAIL 0 0 EXIT
    THEN
    HTTP-RECV-LOOP
    HTTP-DISCONNECT
    HTTP-PARSE 0= IF
        HTTP-BODY-ADDR @ HTTP-BODY-LEN @
    ELSE 0 0 THEN ;

\ HTTP-POST-JSON ( url-a url-u json-a json-u -- resp-a resp-u | 0 0 )
: HTTP-POST-JSON  ( url-a url-u json-a json-u -- resp-a resp-u )
    S" application/json" HTTP-POST ;

\ =====================================================================
\  Layer 6 — Redirect Following
\ =====================================================================

VARIABLE HTTP-MAX-REDIRECTS
5 HTTP-MAX-REDIRECTS !

VARIABLE HTTP-FOLLOW?
-1 HTTP-FOLLOW? !                          \ default: follow redirects

\ _HTTP-REDIRECT? ( -- flag )
\   Is the last status a redirect (301/302/307/308)?
: _HTTP-REDIRECT?  ( -- flag )
    HTTP-STATUS @
    DUP 301 = OVER 302 = OR
    OVER 307 = OR SWAP 308 = OR ;
