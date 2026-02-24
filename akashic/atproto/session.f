\ akashic/atproto/session.f — AT Protocol Session Management
\
\ Manages authentication with an AT Protocol PDS via createSession
\ and refreshSession XRPC procedures.  Stores access + refresh JWT
\ tokens and the session DID.
\
\ Prefix: SESS-   (public API)
\         _SES-   (internal helpers)
\

REQUIRE xrpc.f
REQUIRE json.f
REQUIRE http.f

PROVIDED akashic-session


\ ─── Token Storage ────────────────────────────────────────────

CREATE _SES-ACCESS  512 ALLOT           \ accessJwt buffer
VARIABLE _SES-ACCESS-LEN

CREATE _SES-REFRESH  512 ALLOT          \ refreshJwt buffer
VARIABLE _SES-REFRESH-LEN

CREATE _SES-DID  128 ALLOT              \ session DID
VARIABLE _SES-DID-LEN

: _SES-CLEAR  ( -- )
  0 _SES-ACCESS-LEN !
  0 _SES-REFRESH-LEN !
  0 _SES-DID-LEN !
  HTTP-CLEAR-BEARER ;
_SES-CLEAR


\ ─── Helpers ──────────────────────────────────────────────────

\ Extract a JSON string field into a buffer.
\ Uses dedicated variables to avoid stack gymnastics.

VARIABLE _SES-EX-DST
VARIABLE _SES-EX-MAX
VARIABLE _SES-EX-LEN

: _SES-STORE  ( str-a str-u -- flag )
  DUP _SES-EX-MAX @ > IF
    2DROP 0 EXIT                         \ too long, fail
  THEN
  DUP _SES-EX-LEN @ !                   \ store length (lenvar @ = actual var)
  _SES-EX-DST @ SWAP MOVE               \ copy string
  -1 ;                                   \ success

: _SES-EXTRACT-KEY  ( json-a json-u key-a key-u dst max lenvar -- flag )
  _SES-EX-LEN !  _SES-EX-MAX !  _SES-EX-DST !
  JSON-KEY?                              ( val-a val-u flag )
  IF
    JSON-GET-STRING                       ( str-a str-u )
    _SES-STORE
  ELSE
    2DROP 0
  THEN ;


\ ─── Build Login JSON ────────────────────────────────────────

CREATE _SES-JBUF 512 ALLOT              \ JSON build buffer

VARIABLE _SES-HA
VARIABLE _SES-HL
VARIABLE _SES-PA
VARIABLE _SES-PL

: _SES-BUILD-LOGIN  ( handle-a handle-u pass-a pass-u -- json-a json-u )
  _SES-PL ! _SES-PA !
  _SES-HL ! _SES-HA !
  _SES-JBUF 512 JSON-SET-OUTPUT
  JSON-{
    S" identifier" _SES-HA @ _SES-HL @ JSON-KV-STR
    S" password"   _SES-PA @ _SES-PL @ JSON-KV-STR
  JSON-}
  JSON-OUTPUT-RESULT ;


\ ─── Parse Session Response ──────────────────────────────────

: _SES-PARSE-RESPONSE  ( json-a json-u -- ior )
  JSON-ENTER                             \ enter top-level {}
  \ Extract accessJwt
  2DUP S" accessJwt" _SES-ACCESS 511 _SES-ACCESS-LEN _SES-EXTRACT-KEY
  0= IF  2DROP -1 EXIT  THEN

  \ Extract refreshJwt
  2DUP S" refreshJwt" _SES-REFRESH 511 _SES-REFRESH-LEN _SES-EXTRACT-KEY
  0= IF  2DROP -1 EXIT  THEN

  \ Extract did
  S" did" _SES-DID 127 _SES-DID-LEN _SES-EXTRACT-KEY
  0= IF  -1 EXIT  THEN

  \ Set bearer token for subsequent HTTP requests
  _SES-ACCESS _SES-ACCESS-LEN @ HTTP-SET-BEARER
  0 ;


\ ─── Public API ───────────────────────────────────────────────

: SESS-LOGIN  ( handle-a handle-u pass-a pass-u -- ior )
  _SES-CLEAR
  _SES-BUILD-LOGIN                       ( json-a json-u )
  S" com.atproto.server.createSession"
  2SWAP                                  ( nsid-a nsid-u json-a json-u )
  XRPC-PROCEDURE                         ( resp-a resp-u ior )
  DUP 0<> IF                            \ XRPC failed
    DROP 2DROP -1 EXIT
  THEN
  DROP                                   \ drop ior=0
  _SES-PARSE-RESPONSE ;


\ Build refresh JSON: {"refreshJwt":"<token>"}
\ AT Protocol sends refresh JWT as Bearer header, not body.
: SESS-REFRESH  ( -- ior )
  _SES-REFRESH-LEN @ 0= IF  -1 EXIT  THEN
  \ Temporarily set bearer to refresh token
  _SES-REFRESH _SES-REFRESH-LEN @ HTTP-SET-BEARER
  S" com.atproto.server.refreshSession"
  S" {}"
  XRPC-PROCEDURE                         ( resp-a resp-u ior )
  DUP 0<> IF
    DROP 2DROP -1 EXIT
  THEN
  DROP
  _SES-PARSE-RESPONSE ;                 \ sets new access token as bearer


: SESS-DID  ( -- addr len )
  _SES-DID _SES-DID-LEN @ ;


: SESS-ACTIVE?  ( -- flag )
  _SES-ACCESS-LEN @ 0<> ;
