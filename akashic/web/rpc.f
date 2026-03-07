\ =================================================================
\  rpc.f  —  JSON-RPC 2.0 Interface
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: RPC-  / _RPC-
\  Depends on: server.f router.f json.f mempool.f state.f block.f
\              gossip.f (for GSP-PEER-COUNT)
\
\  Single endpoint: POST /rpc
\  Standard JSON-RPC 2.0 envelope.
\
\  Public API:
\   RPC-INIT      ( -- )         register /rpc route
\   RPC-DISPATCH  ( -- )         handle POST /rpc (called by router)
\
\  Supported methods:
\   chain_sendTransaction  ( params: [cbor-hex] → tx-hash )
\   chain_getBalance       ( params: [addr-hex] → u64 )
\   chain_blockNumber      ( →  u64 )
\   mempool_status         ( →  {count: n} )
\   node_info              ( →  {height, peers, mempool} )
\ =================================================================

REQUIRE ../web/server.f
REQUIRE ../utils/json.f
REQUIRE ../store/mempool.f
REQUIRE ../store/state.f
REQUIRE ../store/block.f
REQUIRE ../utils/fmt.f
REQUIRE ../net/gossip.f

PROVIDED akashic-rpc

\ =====================================================================
\  1. Constants
\ =====================================================================

4096 CONSTANT _RPC-BUF-SZ              \ JSON response buffer

\ JSON-RPC 2.0 error codes
-32700 CONSTANT RPC-E-PARSE
-32601 CONSTANT RPC-E-METHOD
-32602 CONSTANT RPC-E-PARAMS
-32000 CONSTANT RPC-E-INTERNAL

\ =====================================================================
\  2. Storage
\ =====================================================================

CREATE _RPC-OBUF _RPC-BUF-SZ ALLOT    \ JSON output buffer
CREATE _RPC-METH 64 ALLOT             \ extracted method name
VARIABLE _RPC-METH-LEN

CREATE _RPC-PARAMS 2048 ALLOT         \ extracted params region
VARIABLE _RPC-PARAMS-LEN

VARIABLE _RPC-ID-VAL                   \ numeric id value
VARIABLE _RPC-ID-SET                   \ -1 = id present, 0 = absent

CREATE _RPC-HTMP 32 ALLOT             \ hash scratch
CREATE _RPC-ATMP 32 ALLOT             \ address scratch
CREATE _RPC-HEX  128 ALLOT            \ hex-encoded output scratch
CREATE _RPC-RAW  TX-BUF-SIZE ALLOT    \ raw CBOR buffer (sendTx)
CREATE _RPC-TX   TX-BUF-SIZE ALLOT    \ tx struct (sendTx)

\ =====================================================================
\  3. JSON response helpers
\ =====================================================================

\ Start a JSON-RPC response envelope
: _RPC-RESP-BEGIN  ( -- )
    _RPC-OBUF _RPC-BUF-SZ JSON-SET-OUTPUT
    JSON-{
    S" jsonrpc" S" 2.0" JSON-KV-STR
    \ Echo "id" if present (as number)
    _RPC-ID-SET @ IF
        S" id" _RPC-ID-VAL @ JSON-KV-NUM
    THEN ;

\ Write "result": <value> and close
: _RPC-RESP-RESULT-NUM  ( n -- )
    S" result" JSON-KEY:  JSON-NUM
    JSON-} ;

\ Write "error": {code, message} and close
: _RPC-RESP-ERROR  ( code msg-a msg-u -- )
    S" error" JSON-KEY:
    JSON-{
    S" code" 4 PICK JSON-KV-NUM
    S" message" JSON-KEY:  JSON-STR
    JSON-}
    DROP                                \ drop extra code copy
    JSON-} ;

\ Send response via HTTP
: _RPC-SEND  ( -- )
    JSON-OUTPUT-RESULT RESP-JSON
    RESP-SEND ;

\ =====================================================================
\  4. Method: chain_getBalance
\ =====================================================================

: _RPC-M-GET-BALANCE  ( -- )
    \ params: first array element is address hex string
    _RPC-PARAMS _RPC-PARAMS-LEN @
    JSON-ENTER                         \ enter array (past [)
    JSON-GET-STRING                    ( hex-a hex-u )
    \ Decode hex to binary address (32 bytes = 64 hex chars)
    DUP 64 <> IF
        2DROP
        _RPC-RESP-BEGIN
        RPC-E-PARAMS S" address must be 64 hex chars" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    _RPC-ATMP FMT-HEX-DECODE DROP     \ ( -- ) 32 bytes at _RPC-ATMP
    \ Look up balance
    _RPC-ATMP ST-BALANCE@              ( balance )
    _RPC-RESP-BEGIN
    _RPC-RESP-RESULT-NUM
    _RPC-SEND ;

\ =====================================================================
\  5. Method: chain_blockNumber
\ =====================================================================

: _RPC-M-BLOCK-NUMBER  ( -- )
    _RPC-RESP-BEGIN
    CHAIN-HEIGHT _RPC-RESP-RESULT-NUM
    _RPC-SEND ;

\ =====================================================================
\  6. Method: chain_sendTransaction
\ =====================================================================

: _RPC-M-SEND-TX  ( -- )
    \ params: first array element is CBOR-hex encoded tx
    _RPC-PARAMS _RPC-PARAMS-LEN @
    JSON-ENTER
    JSON-GET-STRING                    ( hex-a hex-u )
    \ Decode hex to binary in _RPC-RAW
    _RPC-RAW FMT-HEX-DECODE           ( n-bytes )
    \ TX-DECODE ( buf len tx -- flag )
    _RPC-RAW SWAP _RPC-TX TX-DECODE    ( flag )
    0= IF
        _RPC-RESP-BEGIN
        RPC-E-INTERNAL S" tx decode failed" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    \ Add to mempool
    _RPC-TX MP-ADD 0= IF
        _RPC-RESP-BEGIN
        RPC-E-INTERNAL S" tx rejected by mempool" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    \ Compute hash and return as hex
    _RPC-TX _RPC-HTMP TX-HASH
    _RPC-HTMP 32 _RPC-HEX FMT->HEX DROP \ 64 hex chars in _RPC-HEX
    _RPC-RESP-BEGIN
    S" result" _RPC-HEX 64 JSON-KV-STR
    JSON-}
    _RPC-SEND ;

\ =====================================================================
\  7. Method: mempool_status
\ =====================================================================

: _RPC-M-MEMPOOL-STATUS  ( -- )
    _RPC-RESP-BEGIN
    S" result" JSON-KEY:
    JSON-{
    S" count" MP-COUNT JSON-KV-NUM
    JSON-}
    JSON-}
    _RPC-SEND ;

\ =====================================================================
\  8. Method: node_info
\ =====================================================================

: _RPC-M-NODE-INFO  ( -- )
    _RPC-RESP-BEGIN
    S" result" JSON-KEY:
    JSON-{
    S" height" CHAIN-HEIGHT JSON-KV-NUM
    S" peers" GSP-PEER-COUNT JSON-KV-NUM
    S" mempool" MP-COUNT JSON-KV-NUM
    JSON-}
    JSON-}
    _RPC-SEND ;

\ =====================================================================
\  9. Method dispatch table
\ =====================================================================

\ Helper: compare extracted method name with literal
: _RPC-METHOD=  ( caddr cu -- flag )
    _RPC-METH _RPC-METH-LEN @ STR-STR= ;

: _RPC-DISPATCH-METHOD  ( -- )
    S" chain_getBalance"       _RPC-METHOD= IF _RPC-M-GET-BALANCE   EXIT THEN
    S" chain_blockNumber"      _RPC-METHOD= IF _RPC-M-BLOCK-NUMBER  EXIT THEN
    S" chain_sendTransaction"  _RPC-METHOD= IF _RPC-M-SEND-TX       EXIT THEN
    S" mempool_status"         _RPC-METHOD= IF _RPC-M-MEMPOOL-STATUS EXIT THEN
    S" node_info"              _RPC-METHOD= IF _RPC-M-NODE-INFO     EXIT THEN
    \ Unknown method
    _RPC-RESP-BEGIN
    RPC-E-METHOD S" method not found" _RPC-RESP-ERROR
    _RPC-SEND ;

\ =====================================================================
\  10. RPC-DISPATCH — main entry point (called by router on POST /rpc)
\ =====================================================================

: RPC-DISPATCH  ( -- )
    \ Get request body (JSON-RPC envelope)
    REQ-BODY                           ( body-a body-u )
    DUP 2 < IF
        2DROP
        200 RESP-STATUS
        _RPC-OBUF _RPC-BUF-SZ JSON-SET-OUTPUT
        JSON-{
        S" jsonrpc" S" 2.0"  JSON-KV-STR
        S" error" JSON-KEY: JSON-{
        S" code" RPC-E-PARSE JSON-KV-NUM
        S" message" S" parse error" JSON-KV-STR
        JSON-} JSON-}
        JSON-OUTPUT-RESULT RESP-JSON
        RESP-SEND EXIT
    THEN
    \ Enter the JSON object
    2DUP JSON-ENTER                    ( body-a body-u inner-a inner-u )
    \ Extract "method" field
    2DUP S" method" JSON-KEY
    JSON-GET-STRING                    ( body inner meth-a meth-u )
    DUP 63 > IF 2DROP S" " THEN
    DUP _RPC-METH-LEN !
    _RPC-METH SWAP CMOVE              ( body inner )
    \ Extract "id" field (optional, numeric)
    2DUP S" id" JSON-KEY?             ( body inner val-a val-u flag )
    IF
        JSON-GET-NUMBER _RPC-ID-VAL !
        -1 _RPC-ID-SET !
    ELSE
        2DROP 0 _RPC-ID-SET !
    THEN                               ( body inner )
    \ Extract "params" (optional, could be array or object)
    2DUP S" params" JSON-KEY?         ( body inner val-a val-u flag )
    IF
        DUP 2047 > IF 2DROP S" []" THEN
        DUP _RPC-PARAMS-LEN !
        _RPC-PARAMS SWAP CMOVE        ( body inner )
    ELSE
        2DROP
        S" []" DUP _RPC-PARAMS-LEN !
        _RPC-PARAMS SWAP CMOVE        ( body inner )
    THEN
    2DROP 2DROP                        ( -- drop inner + body )
    200 RESP-STATUS
    _RPC-DISPATCH-METHOD ;

\ =====================================================================
\  11. RPC-INIT — register /rpc route
\ =====================================================================

: RPC-INIT  ( -- )
    S" /rpc" ['] RPC-DISPATCH ROUTE-POST ;

\ =====================================================================
\  12. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _rpc-guard

' RPC-INIT      CONSTANT _rpc-init-xt
' RPC-DISPATCH  CONSTANT _rpc-disp-xt

: RPC-INIT      _rpc-init-xt  _rpc-guard WITH-GUARD ;
: RPC-DISPATCH  _rpc-disp-xt  _rpc-guard WITH-GUARD ;

\ =================================================================
\  Done.
\ =================================================================
