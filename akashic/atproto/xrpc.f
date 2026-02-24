\ akashic/atproto/xrpc.f — XRPC client for AT Protocol
\
\ XRPC (Cross-RPC) wraps HTTP GET/POST calls to the AT Protocol
\ lexicon endpoint format:  https://<host>/xrpc/<nsid>
\
\ Depends on: http.f (HTTP client), string.f (STR-INDEX, /STRING),
\             json.f (JSON-KEY? for cursor extraction)
\
REQUIRE http.f
REQUIRE string.f
REQUIRE json.f

PROVIDED akashic-xrpc


\ ─── Host Configuration ───────────────────────────────────────

CREATE XRPC-HOST  64 ALLOT              \ PDS hostname buffer
VARIABLE XRPC-HOST-LEN                  \ hostname length

\ Default: bsky.social
: _XRPC-DEFAULT-HOST  ( -- )
  S" bsky.social" XRPC-HOST SWAP        ( src len )
  DUP XRPC-HOST-LEN !                   ( src len )
  MOVE ;
_XRPC-DEFAULT-HOST

: XRPC-SET-HOST  ( addr len -- )
  DUP 63 > IF  2DROP EXIT  THEN
  DUP XRPC-HOST-LEN !
  XRPC-HOST SWAP MOVE ;


\ ─── URL Builder ──────────────────────────────────────────────

CREATE _XR-URL  512 ALLOT               \ assembled URL buffer
VARIABLE _XR-POS                         \ current write position

: _XR-APPEND  ( addr len -- )
  _XR-URL _XR-POS @ +                   ( addr len dst )
  SWAP                                   ( addr dst len )
  DUP _XR-POS +!                        ( addr dst len )
  MOVE ;

: _XR-C!  ( char -- )
  _XR-URL _XR-POS @ + C!
  1 _XR-POS +! ;

\ Build "https://<host>/xrpc/<nsid>" into _XR-URL
: _XRPC-BUILD-URL  ( nsid-a nsid-u -- )
  0 _XR-POS !
  S" https://" _XR-APPEND
  XRPC-HOST XRPC-HOST-LEN @ _XR-APPEND
  S" /xrpc/" _XR-APPEND
  _XR-APPEND ;


\ ─── Query String Append ─────────────────────────────────────

\ Append "?<params>" to _XR-URL (if params non-empty)
: _XRPC-APPEND-PARAMS  ( params-a params-u -- )
  DUP 0= IF  2DROP EXIT  THEN
  [CHAR] ? _XR-C!
  _XR-APPEND ;


\ ─── Cursor / Pagination (CR-7 §19) ──────────────────────────

CREATE XRPC-CURSOR  128 ALLOT           \ cursor value buffer
VARIABLE XRPC-CURSOR-LEN                \ cursor length

: XRPC-CLEAR-CURSOR  ( -- )
  0 XRPC-CURSOR-LEN ! ;
XRPC-CLEAR-CURSOR

: XRPC-SET-CURSOR  ( addr len -- )
  DUP 127 > IF  2DROP EXIT  THEN
  DUP XRPC-CURSOR-LEN !
  XRPC-CURSOR SWAP MOVE ;

: XRPC-HAS-CURSOR?  ( -- flag )
  XRPC-CURSOR-LEN @ 0<> ;

\ Append "&cursor=<val>" or "?cursor=<val>" to _XR-URL if cursor set
: _XRPC-APPEND-CURSOR  ( -- )
  XRPC-HAS-CURSOR? 0= IF EXIT THEN
  \ Check if URL already has '?'
  _XR-URL _XR-POS @ [CHAR] ? STR-INDEX
  -1 = IF  [CHAR] ?  ELSE  [CHAR] &  THEN
  _XR-C!
  S" cursor=" _XR-APPEND
  XRPC-CURSOR XRPC-CURSOR-LEN @ _XR-APPEND ;


\ ─── Extract Cursor from JSON Response ───────────────────────
\
\ Scans response JSON for "cursor":"<value>" and stores into
\ XRPC-CURSOR.  If not present, clears cursor (no more pages).

: XRPC-EXTRACT-CURSOR  ( json-a json-u -- )
  DUP 0= IF  2DROP XRPC-CLEAR-CURSOR EXIT  THEN
  JSON-ENTER                             ( addr' len' — inside {} )
  S" cursor" JSON-KEY?                   ( val-a val-u flag )
  IF
    JSON-GET-STRING                       ( str-a str-u )
    DUP 0= IF
      2DROP XRPC-CLEAR-CURSOR EXIT
    THEN
    DUP 127 > IF
      2DROP XRPC-CLEAR-CURSOR EXIT
    THEN
    XRPC-SET-CURSOR
  ELSE
    2DROP
    XRPC-CLEAR-CURSOR
  THEN ;


\ ─── XRPC Query (GET) ────────────────────────────────────────

: XRPC-QUERY  ( nsid-a nsid-u params-a params-u -- body-a body-u ior )
  2SWAP _XRPC-BUILD-URL                 ( params-a params-u )
  _XRPC-APPEND-PARAMS                   ( )
  _XRPC-APPEND-CURSOR
  _XR-URL _XR-POS @
  HTTP-GET                               ( body-a body-u )
  DUP 0= IF  HTTP-ERR @  ELSE  0  THEN ;


\ ─── XRPC Procedure (POST) ───────────────────────────────────

: XRPC-PROCEDURE  ( nsid-a nsid-u body-a body-u -- resp-a resp-u ior )
  2SWAP _XRPC-BUILD-URL                 ( body-a body-u )
  _XR-URL _XR-POS @                     ( body-a body-u url-a url-u )
  2SWAP                                  ( url-a url-u body-a body-u )
  HTTP-POST-JSON                         ( resp-a resp-u )
  DUP 0= IF  HTTP-ERR @  ELSE  0  THEN ;
