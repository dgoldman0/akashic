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
\   chain_verifyProof      ( params: [addr,leaf,proof,root] → bool )
\ =================================================================

REQUIRE ../web/server.f
REQUIRE ../utils/json.f
REQUIRE ../store/mempool.f
REQUIRE ../store/state.f
REQUIRE ../store/block.f
REQUIRE ../utils/fmt.f
REQUIRE ../net/gossip.f
REQUIRE ../store/light.f

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

\ The request's params, read in place in its body, which lasts the
\ dispatch; a request without params reads as [].
VARIABLE _RPC-PARAMS-A
VARIABLE _RPC-PARAMS-LEN
: _RPC-PARAMS  ( -- a u )  _RPC-PARAMS-A @ _RPC-PARAMS-LEN @ ;

VARIABLE _RPC-ID-VAL                   \ numeric id value
VARIABLE _RPC-ID-SET                   \ -1 = id present, 0 = absent

CREATE _RPC-HTMP 32 ALLOT             \ hash scratch
CREATE _RPC-ATMP 32 ALLOT             \ address scratch
\ Hex-encoded output scratch; the longest value it holds is an account
\ entry, two hex digits a byte.
CREATE _RPC-HEX  ST-ENTRY-SIZE 2 * ALLOT
CREATE _RPC-RAW  TX-BUF-SIZE ALLOT    \ raw CBOR buffer (sendTx)
CREATE _RPC-TX   TX-BUF-SIZE ALLOT    \ tx struct (sendTx)
\ The state tree's proofs: an entry of 40 bytes, a bit position and a
\ sibling hash, for each branch above the account's leaf.  A 256-bit key
\ meets at most 256 branches, so 10240 bytes hold any proof.
40 CONSTANT _RPC-PROOF-ENTRY
256 _RPC-PROOF-ENTRY * CONSTANT _RPC-PROOF-SZ
CREATE _RPC-PROOF _RPC-PROOF-SZ ALLOT
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

\ Answer the request with error CODE and message MSG
: _RPC-FAIL  ( code msg-a msg-u -- )
    >R >R >R _RPC-RESP-BEGIN R> R> R> _RPC-RESP-ERROR _RPC-SEND ;

\ =====================================================================
\  4. Method: chain_getBalance
\ =====================================================================

: _RPC-M-GET-BALANCE  ( -- )
    \ params: first array element is address hex string
    _RPC-PARAMS
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
    _RPC-PARAMS
    JSON-ENTER
    JSON-GET-STRING                    ( hex-a hex-u )
    \ The decoded bytes must fit _RPC-RAW
    DUP 2 / TX-BUF-SIZE > IF
        2DROP RPC-E-PARAMS S" tx too large" _RPC-FAIL EXIT
    THEN
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
\ Returns { stateRoot, address, entry, leaf, balance, nonce,
\           proof: [{bit, sibling}...] }
\ entry is the account's 72-byte state entry and leaf its SHA3-256 hash,
\ the value the state tree keeps under the address.  The proof is the
\ tree's own, root to leaf: for each branch above the leaf, the branch's
\ bit position and the hash of its other child.  A lone account's leaf
\ is the root, so its proof holds no entries.  chain_verifyProof takes
\ address, leaf, proof and stateRoot as they come.

VARIABLE _RPC-GP-LEN
VARIABLE _RPC-GP-ENT

\ Write the 32 bytes at ADDR as the hex string value of key K
: _RPC-KV-HEX32  ( k-a k-u addr -- )
    32 _RPC-HEX FMT->HEX DROP  _RPC-HEX 64 JSON-KV-STR ;

: _RPC-M-GET-PROOF  ( -- )
    \ Parse address from params
    _RPC-PARAMS
    JSON-ENTER
    JSON-GET-STRING                    ( hex-a hex-u )
    DUP 64 <> IF
        2DROP RPC-E-PARAMS S" address must be 64 hex chars" _RPC-FAIL EXIT
    THEN
    _RPC-ATMP FMT-HEX-DECODE DROP     \ 32 bytes at _RPC-ATMP
    _RPC-ATMP ST-LOOKUP DUP 0= IF
        DROP RPC-E-INTERNAL S" account not found" _RPC-FAIL EXIT
    THEN
    _RPC-GP-ENT !
    \ The proof of a present account fails only when the tree cannot be
    \ built; _RPC-PROOF holds the longest proof there is.
    _RPC-ATMP _RPC-PROOF _RPC-PROOF-SZ LC-STATE-PROOF   ( len flag )
    0= IF
        DROP RPC-E-INTERNAL S" state tree unavailable" _RPC-FAIL EXIT
    THEN
    _RPC-GP-LEN !
    _RPC-ATMP _RPC-LEAF LC-STATE-LEAF DROP
    ST-ROOT DROP _RPC-ROOT 32 CMOVE
    \ Build response
    _RPC-RESP-BEGIN
    S" result" JSON-KEY:
    JSON-{
    S" stateRoot" _RPC-ROOT _RPC-KV-HEX32
    S" address" _RPC-ATMP _RPC-KV-HEX32
    _RPC-GP-ENT @ ST-ENTRY-SIZE _RPC-HEX FMT->HEX DROP
    S" entry" _RPC-HEX ST-ENTRY-SIZE 2 * JSON-KV-STR
    S" leaf" _RPC-LEAF _RPC-KV-HEX32
    S" balance" _RPC-ATMP ST-BALANCE@ JSON-KV-NUM
    S" nonce" _RPC-ATMP ST-NONCE@ JSON-KV-NUM
    S" proof" JSON-KEY:  JSON-[
    _RPC-GP-LEN @ 0 ?DO
        _RPC-PROOF I _RPC-PROOF-ENTRY * +      ( entry )
        JSON-{
        S" bit" 2 PICK @ JSON-KV-NUM
        S" sibling" ROT 8 + _RPC-KV-HEX32
        JSON-}
    LOOP
    JSON-]
    JSON-}
    JSON-}
    \ A response the output buffer could not hold goes out as an error
    JSON-OUTPUT-OK? 0= IF
        RPC-E-INTERNAL S" proof too large for the response" _RPC-FAIL EXIT
    THEN
    _RPC-SEND ;

\ =====================================================================
\  10. Method: chain_getBlockProof — block header fields at height
\ =====================================================================

\ params: [height]
\ Returns { height, prevHash, stateRoot, txRoot, timestamp }

: _RPC-M-GET-BLOCK-PROOF  ( -- )
    \ Parse height from params
    _RPC-PARAMS
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
    S" height" 2 PICK BLK-HEIGHT@ JSON-KV-NUM
    \ prevHash
    DUP BLK-PREV-HASH@ 32 _RPC-HEX FMT->HEX DROP
    S" prevHash" _RPC-HEX 64 JSON-KV-STR
    \ stateRoot
    DUP BLK-STATE-ROOT@ 32 _RPC-HEX FMT->HEX DROP
    S" stateRoot" _RPC-HEX 64 JSON-KV-STR
    \ txRoot
    DUP BLK-TX-ROOT@ 32 _RPC-HEX FMT->HEX DROP
    S" txRoot" _RPC-HEX 64 JSON-KV-STR
    \ timestamp
    S" timestamp" ROT BLK-TIME@ JSON-KV-NUM
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
    _RPC-PARAMS
    JSON-ENTER
    \ RPC-DISPATCH gives a request without params "[]", so the cursor
    \ stands at "]" when no height came.
    2DUP JSON-NUMBER? 0= IF
        \ No height — return current state root
        2DROP
        ST-ROOT DROP _RPC-ROOT 32 CMOVE
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

\ params: [address-hex, leaf-hex, proof, root-hex], as chain_getProof
\ gives them:
\   address-hex = 64 hex chars, the account's address (the tree's key)
\   leaf-hex    = 64 hex chars, SHA3-256 of the account's entry
\   proof       = [{bit, sibling}...], root to leaf; [] for a lone account
\   root-hex    = 64 hex chars, the state root the proof should reach
\ Returns boolean.

VARIABLE _RPC-VP-LEN

\ _RPC-VP-ENTRY ( a u -- flag )
\   Read the proof entry {bit, sibling} at the cursor into the next entry
\   of _RPC-PROOF.  FALSE when the value is not such an object.
: _RPC-VP-ENTRY  ( a u -- flag )
    2DUP JSON-OBJECT? 0= IF 2DROP 0 EXIT THEN
    JSON-ENTER                                   ( obj-a obj-u )
    2DUP S" bit" JSON-KEY? 0= IF 2DROP 2DROP 0 EXIT THEN
    2DUP JSON-NUMBER? 0= IF 2DROP 2DROP 0 EXIT THEN
    JSON-GET-NUMBER
    _RPC-PROOF _RPC-VP-LEN @ _RPC-PROOF-ENTRY * + !   ( obj-a obj-u )
    S" sibling" JSON-KEY? 0= IF 2DROP 0 EXIT THEN
    JSON-GET-STRING DUP 64 <> IF 2DROP 0 EXIT THEN
    _RPC-PROOF _RPC-VP-LEN @ _RPC-PROOF-ENTRY * + 8 + FMT-HEX-DECODE DROP
    -1 ;

\ _RPC-VP-READ-PROOF ( a u -- flag )
\   Read the proof array at the cursor into _RPC-PROOF and its entry
\   count into _RPC-VP-LEN.  FALSE when the value is not an array of
\   proof entries or holds more of them than _RPC-PROOF.
: _RPC-VP-READ-PROOF  ( a u -- flag )
    0 _RPC-VP-LEN !
    2DUP JSON-ARRAY? 0= IF 2DROP 0 EXIT THEN
    JSON-ENTER                                   ( cur-a cur-u )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 93 = IF 2DROP -1 EXIT THEN           \ [] holds no entries
    BEGIN
        _RPC-VP-LEN @ 1+ _RPC-PROOF-ENTRY * _RPC-PROOF-SZ > IF
            2DROP 0 EXIT
        THEN
        2DUP _RPC-VP-ENTRY 0= IF 2DROP 0 EXIT THEN
        1 _RPC-VP-LEN +!
        JSON-NEXT                                ( cur-a cur-u more? )
    0= UNTIL
    2DROP -1 ;

: _RPC-M-VERIFY-PROOF  ( -- )
    _RPC-PARAMS
    JSON-ENTER                         ( cur-a cur-u )
    \ Each value is read from a copy of the cursor, which then steps on.
    \ 1. address-hex (64 chars → 32 bytes)
    2DUP JSON-GET-STRING               ( cur-a cur-u hex-a hex-u )
    DUP 64 <> IF
        2DROP 2DROP
        RPC-E-PARAMS S" address must be 64 hex chars" _RPC-FAIL EXIT
    THEN
    _RPC-ATMP FMT-HEX-DECODE DROP     ( cur-a cur-u )
    \ 2. leaf-hex (64 chars → 32 bytes)
    JSON-NEXT-VALUE
    2DUP JSON-GET-STRING               ( cur-a cur-u hex-a hex-u )
    DUP 64 <> IF
        2DROP 2DROP
        RPC-E-PARAMS S" leaf must be 64 hex chars" _RPC-FAIL EXIT
    THEN
    _RPC-LEAF FMT-HEX-DECODE DROP     ( cur-a cur-u )
    \ 3. proof, an array of {bit, sibling} entries
    JSON-NEXT-VALUE
    2DUP _RPC-VP-READ-PROOF 0= IF
        2DROP RPC-E-PARAMS
        S" proof must be an array of at most 256 {bit, sibling} entries"
        _RPC-FAIL EXIT
    THEN
    \ 4. root-hex (64 chars → 32 bytes), the last value
    JSON-NEXT-VALUE
    JSON-GET-STRING                    ( hex-a hex-u )
    DUP 64 <> IF
        2DROP RPC-E-PARAMS S" root must be 64 hex chars" _RPC-FAIL EXIT
    THEN
    _RPC-ROOT FMT-HEX-DECODE DROP
    \ Verify
    _RPC-ATMP _RPC-LEAF _RPC-PROOF _RPC-VP-LEN @ _RPC-ROOT
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
VARIABLE _RPC-RATE-LAST                \ uptime seconds of last refill

: _RPC-RATE-INIT  ( -- )
    _RPC-RATE-MAX _RPC-RATE-TOKENS !
    MS@ 1000 / _RPC-RATE-LAST ! ;

\ Refill tokens based on elapsed uptime, cap at _RPC-RATE-MAX.  Uptime
\ keeps a wall-clock change from minting or withholding tokens.
: _RPC-RATE-REFILL  ( -- )
    MS@ 1000 / DUP _RPC-RATE-LAST @ - ( now elapsed )
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
    \ Extract "params" (optional, could be array or object), read in
    \ place in the body
    2DUP S" params" JSON-KEY?         ( body inner val-a val-u flag )
    0= IF 2DROP S" []" THEN
    _RPC-PARAMS-LEN ! _RPC-PARAMS-A ! ( body inner )
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
