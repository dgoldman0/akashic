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
\   chain_getProof         ( params: [addr-hex] → proof+account )
\   chain_getBlockProof    ( params: [height]   → header fields )
\   chain_getStateRoot     ( params: [height]?  → root hex )
\   chain_verifyProof      ( params: [leaf,idx,proof,depth,root] → bool )
\ =================================================================

REQUIRE ../web/server.f
REQUIRE ../utils/json.f
REQUIRE ../store/mempool.f
REQUIRE ../store/state.f
REQUIRE ../store/block.f
REQUIRE ../utils/fmt.f
REQUIRE ../net/gossip.f
REQUIRE ../store/light.f
REQUIRE ../utils/datetime.f

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
\ [FIX A01] Raised from 256 to 10240 (320 × 32-byte siblings).
\ 256 bytes = only 8 siblings which overflows on any non-trivial tree.
CREATE _RPC-PROOF 10240 ALLOT          \ Merkle proof buffer
CREATE _RPC-LEAF  32 ALLOT            \ leaf hash scratch
CREATE _RPC-ROOT  32 ALLOT            \ root hash scratch

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
    \ [FIX P28] Broadcast to peers so tx propagates network-wide.
    _RPC-TX GSP-BROADCAST-TX
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
\  9. Method: chain_getProof — account inclusion proof
\ =====================================================================

\ params: [addr-hex]
\ Returns { stateRoot, index, depth, balance, nonce, proof: [hex...] }

VARIABLE _RPC-GP-IDX
VARIABLE _RPC-GP-DEPTH

: _RPC-M-GET-PROOF  ( -- )
    \ Parse address from params
    _RPC-PARAMS _RPC-PARAMS-LEN @
    JSON-ENTER
    JSON-GET-STRING                    ( hex-a hex-u )
    DUP 64 <> IF
        2DROP
        _RPC-RESP-BEGIN
        RPC-E-PARAMS S" address must be 64 hex chars" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    _RPC-ATMP FMT-HEX-DECODE DROP     \ 32 bytes at _RPC-ATMP
    \ Generate proof
    _RPC-ATMP _RPC-PROOF LC-STATE-PROOF
    DUP 0= IF
        DROP
        _RPC-RESP-BEGIN
        RPC-E-INTERNAL S" account not found" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    _RPC-GP-DEPTH !
    \ Get leaf index + leaf hash
    _RPC-ATMP _RPC-LEAF LC-STATE-LEAF  _RPC-GP-IDX !
    \ Get current state root
    ST-ROOT _RPC-ROOT 32 CMOVE
    \ Build response
    _RPC-RESP-BEGIN
    S" result" JSON-KEY:
    JSON-{
    \ stateRoot (hex)
    _RPC-ROOT 32 _RPC-HEX FMT->HEX DROP
    S" stateRoot" _RPC-HEX 64 JSON-KV-STR
    \ index
    S" index" _RPC-GP-IDX @ JSON-KV-NUM
    \ depth
    S" depth" _RPC-GP-DEPTH @ JSON-KV-NUM
    \ balance
    S" balance" _RPC-ATMP ST-BALANCE@ JSON-KV-NUM
    \ nonce
    S" nonce" _RPC-ATMP ST-NONCE@ JSON-KV-NUM
    \ proof array — depth × 32-byte siblings as hex strings
    S" proof" JSON-KEY:  JSON-[
    _RPC-GP-DEPTH @ 0 ?DO
        _RPC-PROOF I 32 * +  32 _RPC-HEX FMT->HEX DROP
        _RPC-HEX 64 JSON-STR
    LOOP
    JSON-]
    JSON-}
    JSON-}
    _RPC-SEND ;

\ =====================================================================
\  10. Method: chain_getBlockProof — block header fields at height
\ =====================================================================

\ params: [height]
\ Returns { height, prevHash, stateRoot, txRoot, timestamp }

: _RPC-M-GET-BLOCK-PROOF  ( -- )
    \ Parse height from params
    _RPC-PARAMS _RPC-PARAMS-LEN @
    JSON-ENTER
    JSON-GET-NUMBER                    ( height )
    \ Look up block
    DUP CHAIN-BLOCK@ DUP 0= IF
        2DROP
        _RPC-RESP-BEGIN
        RPC-E-INTERNAL S" block not found" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    SWAP DROP                          ( blk )
    \ Build response
    _RPC-RESP-BEGIN
    S" result" JSON-KEY:
    JSON-{
    \ height
    S" height" OVER BLK-HEIGHT@ JSON-KV-NUM
    \ prevHash
    OVER BLK-PREV-HASH@ 32 _RPC-HEX FMT->HEX DROP
    S" prevHash" _RPC-HEX 64 JSON-KV-STR
    \ stateRoot
    OVER BLK-STATE-ROOT@ 32 _RPC-HEX FMT->HEX DROP
    S" stateRoot" _RPC-HEX 64 JSON-KV-STR
    \ txRoot
    OVER BLK-TX-ROOT@ 32 _RPC-HEX FMT->HEX DROP
    S" txRoot" _RPC-HEX 64 JSON-KV-STR
    \ timestamp
    S" timestamp" SWAP BLK-TIME@ JSON-KV-NUM
    JSON-}
    JSON-}
    _RPC-SEND ;

\ =====================================================================
\  11. Method: chain_getStateRoot — state root at height
\ =====================================================================

\ params: [height] or []
\ Returns hex string of 32-byte state root.

: _RPC-M-GET-STATE-ROOT  ( -- )
    \ Check if params has a height argument
    _RPC-PARAMS _RPC-PARAMS-LEN @
    JSON-ENTER
    DUP 0= IF
        \ No params — return current state root
        2DROP
        ST-ROOT _RPC-ROOT 32 CMOVE
    ELSE
        \ Parse height
        JSON-GET-NUMBER                ( height )
        LC-STATE-ROOT-AT DUP 0= IF
            DROP
            _RPC-RESP-BEGIN
            RPC-E-INTERNAL S" block not found" _RPC-RESP-ERROR
            _RPC-SEND EXIT
        THEN
        _RPC-ROOT 32 CMOVE
    THEN
    \ Encode root as hex and return
    _RPC-ROOT 32 _RPC-HEX FMT->HEX DROP
    _RPC-RESP-BEGIN
    S" result" _RPC-HEX 64 JSON-KV-STR
    JSON-}
    _RPC-SEND ;

\ =====================================================================
\  12. Method: chain_verifyProof — server-side proof verification
\ =====================================================================

\ params: [leaf-hex, index, proof-hex, depth, root-hex]
\   leaf-hex  = 64 hex chars (32 bytes)
\   index     = leaf index (number)
\   proof-hex = concatenated sibling hashes (depth × 64 hex chars)
\   depth     = proof depth (number)
\   root-hex  = 64 hex chars (32 bytes)
\ Returns boolean.

VARIABLE _RPC-VP-IDX
VARIABLE _RPC-VP-DEPTH

: _RPC-M-VERIFY-PROOF  ( -- )
    _RPC-PARAMS _RPC-PARAMS-LEN @
    JSON-ENTER
    \ 1. leaf-hex (64 chars → 32 bytes)
    JSON-GET-STRING                    ( hex-a hex-u )
    DUP 64 <> IF
        2DROP
        _RPC-RESP-BEGIN
        RPC-E-PARAMS S" leaf must be 64 hex chars" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    _RPC-LEAF FMT-HEX-DECODE DROP
    \ 2. index (number)
    JSON-NEXT-VALUE
    JSON-GET-NUMBER  _RPC-VP-IDX !
    \ 3. proof-hex (depth × 64 hex chars → depth × 32 bytes)
    JSON-NEXT-VALUE
    JSON-GET-STRING                    ( hex-a hex-u )
    DUP 2 / 10240 > IF                 \ [FIX A01] match raised buffer size
        2DROP
        _RPC-RESP-BEGIN
        RPC-E-PARAMS S" proof too large" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    _RPC-PROOF FMT-HEX-DECODE DROP
    \ 4. depth (number)
    JSON-NEXT-VALUE
    JSON-GET-NUMBER  _RPC-VP-DEPTH !
    \ 5. root-hex (64 chars → 32 bytes)
    JSON-NEXT-VALUE
    JSON-GET-STRING                    ( hex-a hex-u )
    DUP 64 <> IF
        2DROP
        _RPC-RESP-BEGIN
        RPC-E-PARAMS S" root must be 64 hex chars" _RPC-RESP-ERROR
        _RPC-SEND EXIT
    THEN
    _RPC-ROOT FMT-HEX-DECODE DROP
    \ Verify
    _RPC-LEAF _RPC-VP-IDX @ _RPC-PROOF _RPC-VP-DEPTH @ _RPC-ROOT
    LC-VERIFY-STATE                    ( flag )
    \ Return boolean result
    _RPC-RESP-BEGIN
    S" result" JSON-KEY:  JSON-BOOL
    JSON-}
    _RPC-SEND ;

\ =====================================================================
\  13. Method dispatch table
\ =====================================================================

\ Helper: compare extracted method name with literal
: _RPC-METHOD=  ( caddr cu -- flag )
    _RPC-METH _RPC-METH-LEN @ STR-STR= ;

: _RPC-DISPATCH-METHOD  ( -- )
    S" chain_getBalance"       _RPC-METHOD= IF _RPC-M-GET-BALANCE   EXIT THEN
    S" chain_blockNumber"      _RPC-METHOD= IF _RPC-M-BLOCK-NUMBER  EXIT THEN
    S" chain_sendTransaction"  _RPC-METHOD= IF _RPC-M-SEND-TX       EXIT THEN
    S" mempool_status"         _RPC-METHOD= IF _RPC-M-MEMPOOL-STATUS EXIT THEN
    S" node_info"              _RPC-METHOD= IF _RPC-M-NODE-INFO      EXIT THEN
    S" chain_getProof"        _RPC-METHOD= IF _RPC-M-GET-PROOF      EXIT THEN
    S" chain_getBlockProof"   _RPC-METHOD= IF _RPC-M-GET-BLOCK-PROOF EXIT THEN
    S" chain_getStateRoot"    _RPC-METHOD= IF _RPC-M-GET-STATE-ROOT EXIT THEN
    S" chain_verifyProof"     _RPC-METHOD= IF _RPC-M-VERIFY-PROOF   EXIT THEN
    \ Unknown method
    _RPC-RESP-BEGIN
    RPC-E-METHOD S" method not found" _RPC-RESP-ERROR
    _RPC-SEND ;

\ =====================================================================
\  10. Rate limiter — token-bucket  [FIX P30]
\ =====================================================================

50  CONSTANT _RPC-RATE-MAX             \ bucket capacity (requests)
1   CONSTANT _RPC-RATE-TPS             \ tokens added per second
VARIABLE _RPC-RATE-TOKENS              \ current token count
VARIABLE _RPC-RATE-LAST                \ epoch-seconds of last refill

: _RPC-RATE-INIT  ( -- )
    _RPC-RATE-MAX _RPC-RATE-TOKENS !
    DT-NOW-S _RPC-RATE-LAST ! ;

\ Refill tokens based on elapsed time, cap at _RPC-RATE-MAX.
: _RPC-RATE-REFILL  ( -- )
    DT-NOW-S DUP _RPC-RATE-LAST @ -   ( now elapsed )
    DUP 1 < IF 2DROP EXIT THEN
    _RPC-RATE-TPS *                    ( now tokens-to-add )
    _RPC-RATE-TOKENS @ +
    _RPC-RATE-MAX MIN
    _RPC-RATE-TOKENS !
    _RPC-RATE-LAST ! ;

\ Try to consume one token.  Returns TRUE if allowed, FALSE if exhausted.
: _RPC-RATE-CHECK  ( -- flag )
    _RPC-RATE-REFILL
    _RPC-RATE-TOKENS @ 0> IF
        -1 _RPC-RATE-TOKENS +!
        -1
    ELSE
        0
    THEN ;

\ Send HTTP 429 Too Many Requests as JSON-RPC error.
: _RPC-RATE-REJECT  ( -- )
    429 RESP-STATUS
    _RPC-OBUF _RPC-BUF-SZ JSON-SET-OUTPUT
    JSON-{
    S" jsonrpc" S" 2.0" JSON-KV-STR
    S" error" JSON-KEY: JSON-{
    S" code" -32000 JSON-KV-NUM
    S" message" S" rate limit exceeded" JSON-KV-STR
    JSON-} JSON-}
    JSON-OUTPUT-RESULT RESP-JSON
    RESP-SEND ;

\ =====================================================================
\  11. RPC-DISPATCH — main entry point (called by router on POST /rpc)
\ =====================================================================

: RPC-DISPATCH  ( -- )
    \ [FIX P30] Check rate limit before processing
    _RPC-RATE-CHECK 0= IF _RPC-RATE-REJECT EXIT THEN
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
    _RPC-RATE-INIT
    S" /rpc" ['] RPC-DISPATCH ROUTE-POST ;

\ =====================================================================
\  12. Concurrency guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _rpc-guard

' RPC-INIT      CONSTANT _rpc-init-xt
' RPC-DISPATCH  CONSTANT _rpc-disp-xt

: RPC-INIT      _rpc-init-xt  _rpc-guard WITH-GUARD ;
: RPC-DISPATCH  _rpc-disp-xt  _rpc-guard WITH-GUARD ;
[THEN] [THEN]

\ =================================================================
\  Done.
\ =================================================================
