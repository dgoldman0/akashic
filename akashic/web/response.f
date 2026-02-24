\ response.f — HTTP response builder for KDOS / Megapad-64
\
\ Builds HTTP/1.1 responses into staging buffers, then sends
\ via SEND on the accepted socket descriptor.
\
\ Reuses headers.f builder (HDR-SET-OUTPUT, HDR-ADD, HDR-END,
\ HDR-RESULT) for header construction.
\
\ Prefix: RESP-  (public API)
\         _RESP- (internal helpers)
\
\ Load with:   REQUIRE response.f

REQUIRE ../net/headers.f
REQUIRE ../utils/string.f
REQUIRE ../utils/datetime.f

PROVIDED akashic-web-response

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE RESP-ERR
1 CONSTANT RESP-E-SEND             \ SEND failed or short write
2 CONSTANT RESP-E-OVERFLOW          \ body exceeds buffer

: RESP-FAIL       ( code -- )  RESP-ERR ! ;
: RESP-OK?        ( -- flag )  RESP-ERR @ 0= ;
: RESP-CLEAR-ERR  ( -- )       0 RESP-ERR ! ;

\ =====================================================================
\  Response State
\ =====================================================================

VARIABLE _RESP-CODE                 \ HTTP status code (default 200)
VARIABLE _RESP-SD                   \ socket descriptor (set by server.f)
VARIABLE _RESP-STREAMING            \ -1 = chunked mode active

CREATE _RESP-HDR-BUF 4096 ALLOT    \ header staging buffer
CREATE _RESP-BODY-BUF 8192 ALLOT   \ body staging buffer
VARIABLE _RESP-BODY-LEN            \ current body length
VARIABLE _RESP-CLEN-SET            \ -1 = user set Content-Length

200 _RESP-CODE !
0 _RESP-SD !
0 _RESP-STREAMING !
0 _RESP-BODY-LEN !
0 _RESP-CLEN-SET !

\ =====================================================================
\  Layer 0 — Status Code + Reason Phrase
\ =====================================================================

\ _RESP-REASON ( code -- addr len )
\   Return reason phrase for common HTTP status codes.
: _RESP-REASON  ( code -- addr len )
    DUP 200 = IF DROP S" OK"                    EXIT THEN
    DUP 201 = IF DROP S" Created"               EXIT THEN
    DUP 204 = IF DROP S" No Content"            EXIT THEN
    DUP 301 = IF DROP S" Moved Permanently"     EXIT THEN
    DUP 302 = IF DROP S" Found"                 EXIT THEN
    DUP 304 = IF DROP S" Not Modified"          EXIT THEN
    DUP 307 = IF DROP S" Temporary Redirect"    EXIT THEN
    DUP 400 = IF DROP S" Bad Request"           EXIT THEN
    DUP 401 = IF DROP S" Unauthorized"          EXIT THEN
    DUP 403 = IF DROP S" Forbidden"             EXIT THEN
    DUP 404 = IF DROP S" Not Found"             EXIT THEN
    DUP 405 = IF DROP S" Method Not Allowed"    EXIT THEN
    DUP 413 = IF DROP S" Payload Too Large"     EXIT THEN
    DUP 500 = IF DROP S" Internal Server Error" EXIT THEN
    DUP 502 = IF DROP S" Bad Gateway"           EXIT THEN
    DUP 503 = IF DROP S" Service Unavailable"   EXIT THEN
    DROP S" Unknown" ;

\ RESP-STATUS ( code -- )
\   Set the response status code.
: RESP-STATUS  ( code -- )  _RESP-CODE ! ;

\ =====================================================================
\  Status Line Builder (internal)
\ =====================================================================

CREATE _RESP-SL-BUF 64 ALLOT       \ status line scratch buffer
VARIABLE _RESP-SL-LEN

\ _RESP-SL-CHAR ( c -- )   Append one char to status line buffer.
: _RESP-SL-CHAR  ( c -- )
    _RESP-SL-BUF _RESP-SL-LEN @ + C!  1 _RESP-SL-LEN +! ;

\ _RESP-SL-STR ( addr len -- )  Append string to status line buffer.
: _RESP-SL-STR  ( addr len -- )
    DUP >R
    _RESP-SL-BUF _RESP-SL-LEN @ + SWAP CMOVE
    R> _RESP-SL-LEN +! ;

\ _RESP-BUILD-STATUS ( -- addr len )
\   Build "HTTP/1.1 NNN Reason\r\n" in scratch buffer.
: _RESP-BUILD-STATUS  ( -- addr len )
    0 _RESP-SL-LEN !
    S" HTTP/1.1 " _RESP-SL-STR
    \ 3-digit status code
    _RESP-CODE @
    DUP 100 /           48 + _RESP-SL-CHAR
    DUP 100 MOD 10 /    48 + _RESP-SL-CHAR
    10 MOD               48 + _RESP-SL-CHAR
    32 _RESP-SL-CHAR                \ space
    _RESP-CODE @ _RESP-REASON _RESP-SL-STR
    13 _RESP-SL-CHAR  10 _RESP-SL-CHAR
    _RESP-SL-BUF _RESP-SL-LEN @ ;

\ =====================================================================
\  Layer 1 — Headers
\ =====================================================================
\
\  Delegates to headers.f builder pointed at _RESP-HDR-BUF.

\ _RESP-HDR-INIT ( -- )   Point header builder at response buffer.
: _RESP-HDR-INIT  ( -- )
    _RESP-HDR-BUF 4096 HDR-SET-OUTPUT ;

\ RESP-HEADER ( name-a name-u val-a val-u -- )
\   Add an arbitrary response header.
: RESP-HEADER  ( name-a name-u val-a val-u -- )
    HDR-ADD ;

\ RESP-CONTENT-TYPE ( a u -- )
\   Set Content-Type header.
: RESP-CONTENT-TYPE  ( a u -- )
    HDR-CONTENT-TYPE ;

\ RESP-CONTENT-LENGTH ( n -- )
\   Manually set Content-Length header.
: RESP-CONTENT-LENGTH  ( n -- )
    -1 _RESP-CLEN-SET !
    HDR-CONTENT-LENGTH ;

\ RESP-LOCATION ( a u -- )
\   Set Location header (for redirects).
: RESP-LOCATION  ( a u -- )
    S" Location" 2SWAP HDR-ADD ;

\ RESP-SET-COOKIE ( a u -- )
\   Add Set-Cookie header.
: RESP-SET-COOKIE  ( a u -- )
    S" Set-Cookie" 2SWAP HDR-ADD ;

\ RESP-CORS ( -- )
\   Add permissive CORS headers.
: RESP-CORS  ( -- )
    S" Access-Control-Allow-Origin"  S" *" HDR-ADD
    S" Access-Control-Allow-Methods" S" GET, POST, PUT, DELETE, OPTIONS" HDR-ADD
    S" Access-Control-Allow-Headers" S" Content-Type, Authorization" HDR-ADD ;

\ RESP-DATE ( -- )
\   Add Date header with current UTC time.
CREATE _RESP-DT-BUF 32 ALLOT

: RESP-DATE  ( -- )
    DT-NOW-S _RESP-DT-BUF 32 DT-ISO8601     ( written )
    S" Date" _RESP-DT-BUF ROT HDR-ADD ;

\ RESP-CACHE ( seconds -- )
\   Add Cache-Control: max-age=N header.
CREATE _RESP-CACHE-BUF 32 ALLOT

: RESP-CACHE  ( seconds -- )
    NUM>STR                                ( num-a num-u )
    DUP >R
    _RESP-CACHE-BUF 8 + SWAP CMOVE        \ copy digits after "max-age="
    S" max-age=" _RESP-CACHE-BUF SWAP CMOVE
    S" Cache-Control" _RESP-CACHE-BUF R> 8 + HDR-ADD ;

\ RESP-NO-CACHE ( -- )
: RESP-NO-CACHE  ( -- )
    S" Cache-Control" S" no-store, no-cache" HDR-ADD ;

\ =====================================================================
\  Layer 2 — Body (Buffer Mode)
\ =====================================================================

\ _RESP-BODY-APPEND ( addr len -- )
\   Append bytes to body buffer, checking overflow.
: _RESP-BODY-APPEND  ( addr len -- )
    _RESP-BODY-LEN @ OVER + 8192 > IF
        2DROP RESP-E-OVERFLOW RESP-FAIL EXIT
    THEN
    DUP >R
    _RESP-BODY-BUF _RESP-BODY-LEN @ + SWAP CMOVE
    R> _RESP-BODY-LEN +! ;

\ RESP-BODY ( a u -- )
\   Append raw bytes to body buffer.
: RESP-BODY  ( a u -- )  _RESP-BODY-APPEND ;

\ RESP-TEXT ( a u -- )
\   Set Content-Type text/plain, append body.
: RESP-TEXT  ( a u -- )
    S" text/plain" RESP-CONTENT-TYPE
    _RESP-BODY-APPEND ;

\ RESP-HTML ( a u -- )
\   Set Content-Type text/html, append body.
: RESP-HTML  ( a u -- )
    S" text/html; charset=utf-8" RESP-CONTENT-TYPE
    _RESP-BODY-APPEND ;

\ =====================================================================
\  Layer 3 — Sending
\ =====================================================================

\ _RESP-SEND-DEFAULT ( addr len -- )
\   Default send: use SEND on the response socket descriptor.
: _RESP-SEND-DEFAULT  ( addr len -- )
    _RESP-SD @ -ROT SEND DROP ;

\ _RESP-SEND-XT — vectored hook for send.  Allows test overrides.
VARIABLE _RESP-SEND-XT
' _RESP-SEND-DEFAULT _RESP-SEND-XT !

\ _RESP-SEND-RAW ( addr len -- )
\   Send via the current send hook.
: _RESP-SEND-RAW  ( addr len -- )
    _RESP-SEND-XT @ EXECUTE ;

\ CRLF constant
CREATE _RESP-CRLF 2 ALLOT
13 _RESP-CRLF C!  10 _RESP-CRLF 1+ C!

\ RESP-SEND ( -- )
\   Finalize and send: status line + headers + CRLF + body.
\   Auto-computes Content-Length if not set by user.
: RESP-SEND  ( -- )
    \ Auto-set Content-Length if not manually provided
    _RESP-CLEN-SET @ 0= IF
        _RESP-BODY-LEN @ HDR-CONTENT-LENGTH
    THEN
    \ Send status line
    _RESP-BUILD-STATUS _RESP-SEND-RAW
    \ Send headers
    HDR-RESULT _RESP-SEND-RAW
    \ Send blank line (end of headers)
    _RESP-CRLF 2 _RESP-SEND-RAW
    \ Send body
    _RESP-BODY-LEN @ 0> IF
        _RESP-BODY-BUF _RESP-BODY-LEN @ _RESP-SEND-RAW
    THEN ;

\ =====================================================================
\  Layer 4 — JSON Convenience
\ =====================================================================

\ RESP-JSON ( a u -- )
\   Set Content-Type application/json, append body.
: RESP-JSON  ( a u -- )
    S" application/json" RESP-CONTENT-TYPE
    _RESP-BODY-APPEND ;

\ =====================================================================
\  Layer 5 — Streaming (Chunked Transfer Encoding)
\ =====================================================================

\ Hex conversion for chunk sizes
CREATE _RESP-HEX-BUF 18 ALLOT
VARIABLE _RESP-HEX-POS

: _RESP-NIBBLE  ( n -- c )
    DUP 10 < IF 48 + ELSE 10 - 97 + THEN ;

\ _RESP-NUM>HEX ( n -- addr len )
\   Convert number to lowercase hex string.
: _RESP-NUM>HEX  ( n -- addr len )
    DUP 0= IF DROP _RESP-HEX-BUF 48 OVER C! 1 EXIT THEN
    17 _RESP-HEX-POS !
    BEGIN DUP 0> WHILE
        DUP 15 AND _RESP-NIBBLE
        _RESP-HEX-BUF _RESP-HEX-POS @ + C!
        -1 _RESP-HEX-POS +!
        4 RSHIFT
    REPEAT DROP
    _RESP-HEX-BUF _RESP-HEX-POS @ + 1+
    17 _RESP-HEX-POS @ - ;

\ RESP-STREAM-START ( -- )
\   Send status + headers with Transfer-Encoding: chunked.
\   No Content-Length.  Further output via RESP-CHUNK.
: RESP-STREAM-START  ( -- )
    -1 _RESP-STREAMING !
    S" Transfer-Encoding" S" chunked" HDR-ADD
    _RESP-BUILD-STATUS _RESP-SEND-RAW
    HDR-RESULT _RESP-SEND-RAW
    _RESP-CRLF 2 _RESP-SEND-RAW ;

\ RESP-CHUNK ( a u -- )
\   Send one HTTP chunk: hex-len CRLF data CRLF.
: RESP-CHUNK  ( a u -- )
    DUP _RESP-NUM>HEX _RESP-SEND-RAW       \ hex length
    _RESP-CRLF 2 _RESP-SEND-RAW            \ CRLF
    _RESP-SEND-RAW                          \ data
    _RESP-CRLF 2 _RESP-SEND-RAW ;          \ CRLF

\ RESP-STREAM-END ( -- )
\   Send terminal chunk "0\r\n\r\n".
CREATE _RESP-TERM-CHUNK 5 ALLOT
48 _RESP-TERM-CHUNK C!
13 _RESP-TERM-CHUNK 1+ C!  10 _RESP-TERM-CHUNK 2 + C!
13 _RESP-TERM-CHUNK 3 + C!  10 _RESP-TERM-CHUNK 4 + C!

: RESP-STREAM-END  ( -- )
    _RESP-TERM-CHUNK 5 _RESP-SEND-RAW
    0 _RESP-STREAMING ! ;

\ =====================================================================
\  Layer 6 — Common Responses
\ =====================================================================

\ RESP-REDIRECT ( code url-a url-u -- )
\   Send redirect with Location header and empty body.
: RESP-REDIRECT  ( code url-a url-u -- )
    ROT RESP-STATUS
    RESP-LOCATION
    RESP-SEND ;

\ _RESP-BODY-CHAR ( c -- )   Append one char to body buffer.
: _RESP-BODY-CHAR  ( c -- )
    _RESP-BODY-LEN @ 8192 >= IF DROP RESP-E-OVERFLOW RESP-FAIL EXIT THEN
    _RESP-BODY-BUF _RESP-BODY-LEN @ + C!
    1 _RESP-BODY-LEN +! ;

\ RESP-ERROR ( code -- )
\   Send error response with JSON body:
\   {"error":NNN,"message":"Reason"}
: RESP-ERROR  ( code -- )
    DUP RESP-STATUS
    S" application/json" RESP-CONTENT-TYPE
    \ Build JSON body: {"error":NNN,"message":"Reason"}
    S" {" _RESP-BODY-APPEND
    34 _RESP-BODY-CHAR S" error" _RESP-BODY-APPEND 34 _RESP-BODY-CHAR
    S" :" _RESP-BODY-APPEND
    DUP NUM>STR _RESP-BODY-APPEND
    S" ," _RESP-BODY-APPEND
    34 _RESP-BODY-CHAR S" message" _RESP-BODY-APPEND 34 _RESP-BODY-CHAR
    S" :" _RESP-BODY-APPEND
    34 _RESP-BODY-CHAR _RESP-REASON _RESP-BODY-APPEND 34 _RESP-BODY-CHAR
    S" }" _RESP-BODY-APPEND
    RESP-SEND ;

\ RESP-NOT-FOUND ( -- )
: RESP-NOT-FOUND  ( -- )  404 RESP-ERROR ;

\ RESP-METHOD-NOT-ALLOWED ( -- )
: RESP-METHOD-NOT-ALLOWED  ( -- )  405 RESP-ERROR ;

\ RESP-INTERNAL-ERROR ( -- )
: RESP-INTERNAL-ERROR  ( -- )  500 RESP-ERROR ;

\ =====================================================================
\  RESP-CLEAR — Reset for Next Response
\ =====================================================================

\ RESP-CLEAR ( -- )
\   Reset all response state for a new connection.
: RESP-CLEAR  ( -- )
    RESP-CLEAR-ERR
    200 _RESP-CODE !
    0 _RESP-BODY-LEN !
    0 _RESP-CLEN-SET !
    0 _RESP-STREAMING !
    _RESP-HDR-INIT ;

\ RESP-SET-SD ( sd -- )
\   Set the socket descriptor for sending.  Called by server.f.
: RESP-SET-SD  ( sd -- )  _RESP-SD ! ;
