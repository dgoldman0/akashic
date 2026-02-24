\ akashic/atproto/repo.f — AT Protocol Repository Record Operations
\
\ CRUD operations on AT Protocol records via XRPC.
\ All operations require an active session (SESS-ACTIVE?).
\
\ AT Protocol endpoints:
\   com.atproto.repo.getRecord      — GET
\   com.atproto.repo.createRecord   — POST
\   com.atproto.repo.putRecord      — POST
\   com.atproto.repo.deleteRecord   — POST
\
\ Prefix: REPO-   (public API)
\         _REP-   (internal helpers)
\

REQUIRE session.f
REQUIRE xrpc.f
REQUIRE ../utils/json.f
REQUIRE aturi.f

PROVIDED akashic-repo


\ ─── Internal Buffers ─────────────────────────────────────────

CREATE _REP-JBUF 2048 ALLOT             \ JSON body build buffer
CREATE _REP-PBUF  256 ALLOT             \ query params buffer
CREATE _REP-URI   256 ALLOT             \ result URI buffer
VARIABLE _REP-URI-LEN


\ ─── String Concat Helpers ────────────────────────────────────
\
\ Manual JSON building via string concatenation, because the record
\ value is already valid JSON and we need to embed it raw (unquoted).
\ Uses ASCII 34 for quotes since KDOS has no S\" word.

VARIABLE _REP-JP                         \ JSON write position
VARIABLE _REP-PP                         \ params write position

: _REP-J-RESET  ( -- )  0 _REP-JP ! ;
: _REP-P-RESET  ( -- )  0 _REP-PP ! ;

: _REP-J-APPEND  ( addr len -- )
  _REP-JBUF _REP-JP @ +  SWAP
  DUP _REP-JP +!  MOVE ;

: _REP-P-APPEND  ( addr len -- )
  _REP-PBUF _REP-PP @ +  SWAP
  DUP _REP-PP +!  MOVE ;

\ Emit one char to JSON buffer
: _REP-J-CH  ( c -- )
  _REP-JBUF _REP-JP @ + C!
  1 _REP-JP +! ;

\ Emit JSON quoted string: "value"
: _REP-J-QSTR  ( addr len -- )
  34 _REP-J-CH                          \ opening "
  _REP-J-APPEND                         \ value
  34 _REP-J-CH ;                        \ closing "

\ Emit JSON key-value pair: ,"key":"value"
: _REP-J-KV  ( key-a key-u val-a val-u -- )
  2SWAP                                  ( val-a val-u key-a key-u )
  44 _REP-J-CH                          \ ,
  34 _REP-J-CH                          \ "
  _REP-J-APPEND                          \ key
  34 _REP-J-CH                          \ "
  58 _REP-J-CH                          \ :
  34 _REP-J-CH                          \ "
  _REP-J-APPEND                          \ value
  34 _REP-J-CH ;                        \ "

\ Emit JSON key with raw value: ,"key":<raw>
: _REP-J-KRAW  ( key-a key-u raw-a raw-u -- )
  2SWAP                                  ( raw-a raw-u key-a key-u )
  44 _REP-J-CH                          \ ,
  34 _REP-J-CH                          \ "
  _REP-J-APPEND                          \ key
  34 _REP-J-CH                          \ "
  58 _REP-J-CH                          \ :
  _REP-J-APPEND ;                       \ raw JSON value


\ ─── Stash Variables ──────────────────────────────────────────

VARIABLE _REP-V1A   VARIABLE _REP-V1L   \ stash slot 1
VARIABLE _REP-V2A   VARIABLE _REP-V2L   \ stash slot 2


\ ─── REPO-GET ─────────────────────────────────────────────────
\
\ REPO-GET ( aturi-a aturi-u -- json-a json-u ior )
\   Fetch a record by AT URI.

: REPO-GET  ( aturi-a aturi-u -- json-a json-u ior )
  SESS-ACTIVE? 0= IF  2DROP 0 0 -1 EXIT  THEN
  ATURI-PARSE 0<> IF  0 0 -1 EXIT  THEN
  _REP-P-RESET
  S" repo=" _REP-P-APPEND
  ATURI-AUTHORITY ATURI-AUTH-LEN @ _REP-P-APPEND
  S" &collection=" _REP-P-APPEND
  ATURI-COLLECTION ATURI-COLL-LEN @ _REP-P-APPEND
  ATURI-RKEY-LEN @ 0> IF
    S" &rkey=" _REP-P-APPEND
    ATURI-RKEY ATURI-RKEY-LEN @ _REP-P-APPEND
  THEN
  S" com.atproto.repo.getRecord"
  _REP-PBUF _REP-PP @
  XRPC-QUERY ;


\ ─── REPO-CREATE ──────────────────────────────────────────────
\
\ REPO-CREATE ( coll-a coll-u json-a json-u -- uri-a uri-u ior )
\   Create a new record.  Returns AT URI of created record.
\   Body: {"repo":"<did>","collection":"<coll>","record":<json>}

: REPO-CREATE  ( coll-a coll-u json-a json-u -- uri-a uri-u ior )
  SESS-ACTIVE? 0= IF  2DROP 2DROP 0 0 -1 EXIT  THEN
  _REP-V2L ! _REP-V2A !                 \ stash record json
  _REP-V1L ! _REP-V1A !                 \ stash collection

  _REP-J-RESET
  123 _REP-J-CH                          \ {
  34 _REP-J-CH  S" repo" _REP-J-APPEND  34 _REP-J-CH   \ "repo"
  58 _REP-J-CH                          \ :
  SESS-DID _REP-J-QSTR                  \ "did:plc:xxx"
  S" collection" _REP-V1A @ _REP-V1L @ _REP-J-KV
  S" record" _REP-V2A @ _REP-V2L @ _REP-J-KRAW
  125 _REP-J-CH                          \ }

  S" com.atproto.repo.createRecord"
  _REP-JBUF _REP-JP @
  XRPC-PROCEDURE                         ( resp-a resp-u ior )
  DUP 0<> IF  DROP 2DROP 0 0 -1 EXIT  THEN
  DROP

  \ Extract "uri" from response
  JSON-ENTER                             \ enter top-level {}
  S" uri" JSON-KEY?                      ( val-a val-u flag )
  IF
    JSON-GET-STRING                       ( str-a str-u )
    DUP 255 > IF  2DROP 0 0 -1 EXIT  THEN
    DUP _REP-URI-LEN !
    _REP-URI SWAP MOVE
    _REP-URI _REP-URI-LEN @ 0
  ELSE
    2DROP 0 0 -1
  THEN ;


\ ─── REPO-PUT ─────────────────────────────────────────────────
\
\ REPO-PUT ( aturi-a aturi-u json-a json-u -- ior )
\   Put (overwrite) a record at the given AT URI.
\   Body: {"repo":"<did>","collection":"<coll>","rkey":"<rkey>","record":<json>}

: REPO-PUT  ( aturi-a aturi-u json-a json-u -- ior )
  SESS-ACTIVE? 0= IF  2DROP 2DROP -1 EXIT  THEN
  _REP-V2L ! _REP-V2A !                 \ stash record json
  ATURI-PARSE 0<> IF  -1 EXIT  THEN

  _REP-J-RESET
  123 _REP-J-CH                          \ {
  34 _REP-J-CH  S" repo" _REP-J-APPEND  34 _REP-J-CH
  58 _REP-J-CH
  SESS-DID _REP-J-QSTR
  S" collection" ATURI-COLLECTION ATURI-COLL-LEN @ _REP-J-KV
  S" rkey" ATURI-RKEY ATURI-RKEY-LEN @ _REP-J-KV
  S" record" _REP-V2A @ _REP-V2L @ _REP-J-KRAW
  125 _REP-J-CH                          \ }

  S" com.atproto.repo.putRecord"
  _REP-JBUF _REP-JP @
  XRPC-PROCEDURE                         ( resp-a resp-u ior )
  DUP 0<> IF  DROP 2DROP -1 EXIT  THEN
  DROP 2DROP 0 ;


\ ─── REPO-DELETE ──────────────────────────────────────────────
\
\ REPO-DELETE ( aturi-a aturi-u -- ior )
\   Delete a record at the given AT URI.
\   Body: {"repo":"<did>","collection":"<coll>","rkey":"<rkey>"}

: REPO-DELETE  ( aturi-a aturi-u -- ior )
  SESS-ACTIVE? 0= IF  2DROP -1 EXIT  THEN
  ATURI-PARSE 0<> IF  -1 EXIT  THEN

  _REP-J-RESET
  123 _REP-J-CH                          \ {
  34 _REP-J-CH  S" repo" _REP-J-APPEND  34 _REP-J-CH
  58 _REP-J-CH
  SESS-DID _REP-J-QSTR
  S" collection" ATURI-COLLECTION ATURI-COLL-LEN @ _REP-J-KV
  S" rkey" ATURI-RKEY ATURI-RKEY-LEN @ _REP-J-KV
  125 _REP-J-CH                          \ }

  S" com.atproto.repo.deleteRecord"
  _REP-JBUF _REP-JP @
  XRPC-PROCEDURE                         ( resp-a resp-u ior )
  DUP 0<> IF  DROP 2DROP -1 EXIT  THEN
  DROP 2DROP 0 ;
