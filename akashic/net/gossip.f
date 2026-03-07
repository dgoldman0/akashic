\ =================================================================
\  gossip.f  —  P2P Network Layer
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: GSP-  / _GSP-
\  Depends on: ws.f cbor.f tx.f block.f mempool.f guard.f
\
\  Peer-to-peer gossip over WebSocket binary frames.
\  Message format: [tag-byte][CBOR payload].
\
\  Public API:
\   GSP-INIT          ( -- )                init peer table + seen cache
\   GSP-CONNECT       ( url-a url-u -- id | -1 )   connect to peer
\   GSP-DISCONNECT    ( id -- )             drop peer connection
\   GSP-PEER-COUNT    ( -- n )              number of active peers
\   GSP-BROADCAST-TX  ( tx -- )             send tx to all peers
\   GSP-BROADCAST-BLK ( blk -- )            announce new block
\   GSP-REQUEST-BLK   ( height peer -- )    request block from peer
\   GSP-SEND-STATUS   ( peer -- )           send our chain status
\   GSP-ON-MSG        ( buf len peer -- )   dispatch incoming message
\   GSP-POLL          ( -- )                poll all peers for messages
\   GSP-SEEN?         ( hash -- flag )      check seen-hash cache
\
\  Constants:
\   GSP-MAX-PEERS     ( -- 16 )
\
\  Callbacks (set by node.f via !):
\   GSP-ON-TX-XT      — ( tx -- )          valid tx received
\   GSP-ON-BLK-ANN-XT — ( height peer -- ) block announced
\   GSP-ON-BLK-RSP-XT — ( buf len -- )     block data received
\   GSP-ON-STATUS-XT   — ( height peer -- ) peer status received
\ =================================================================

REQUIRE ws.f
REQUIRE ../cbor/cbor.f
REQUIRE ../store/tx.f
REQUIRE ../store/block.f
REQUIRE ../store/mempool.f

PROVIDED akashic-gossip

\ =====================================================================
\  1. Constants
\ =====================================================================

16 CONSTANT GSP-MAX-PEERS
256 CONSTANT _GSP-SEEN-CAP

\ Message types (first byte of binary frame)
1 CONSTANT GSP-MSG-TX
2 CONSTANT GSP-MSG-BLK-ANN
3 CONSTANT GSP-MSG-BLK-REQ
4 CONSTANT GSP-MSG-BLK-RSP
5 CONSTANT GSP-MSG-PEER-EX
6 CONSTANT GSP-MSG-STATUS

\ =====================================================================
\  2. Storage
\ =====================================================================

\ Peer table
CREATE _GSP-CTX    GSP-MAX-PEERS CELLS ALLOT   \ WS context per slot
CREATE _GSP-ACTIVE GSP-MAX-PEERS ALLOT         \ 0=free 1=active

\ Seen-hash ring buffer (256 × 32 bytes)
CREATE _GSP-SEEN   _GSP-SEEN-CAP 32 * ALLOT
VARIABLE _GSP-SEEN-POS

\ Message buffers
16384 CONSTANT _GSP-BUF-SZ
CREATE _GSP-SBUF  _GSP-BUF-SZ ALLOT           \ send buffer
CREATE _GSP-RBUF  _GSP-BUF-SZ ALLOT           \ receive buffer

\ Temp scratch
CREATE _GSP-HTMP 32 ALLOT                     \ hash scratch
CREATE _GSP-CMP  32 ALLOT                     \ comparison scratch
CREATE _GSP-TX-TMP TX-BUF-SIZE ALLOT          \ decoded tx scratch

\ Callback hooks (XTs, 0 = no handler)
VARIABLE GSP-ON-TX-XT
VARIABLE GSP-ON-BLK-ANN-XT
VARIABLE GSP-ON-BLK-RSP-XT
VARIABLE GSP-ON-STATUS-XT

\ =====================================================================
\  3. GSP-INIT
\ =====================================================================

: GSP-INIT  ( -- )
    _GSP-CTX GSP-MAX-PEERS CELLS 0 FILL
    _GSP-ACTIVE GSP-MAX-PEERS 0 FILL
    _GSP-SEEN _GSP-SEEN-CAP 32 * 0 FILL
    0 _GSP-SEEN-POS !
    0 GSP-ON-TX-XT !
    0 GSP-ON-BLK-ANN-XT !
    0 GSP-ON-BLK-RSP-XT !
    0 GSP-ON-STATUS-XT ! ;

\ =====================================================================
\  4. Seen-hash dedup
\ =====================================================================

: _GSP-SEEN-ADD  ( hash -- )
    _GSP-SEEN-POS @ 32 * _GSP-SEEN + 32 CMOVE
    _GSP-SEEN-POS @ 1+ _GSP-SEEN-CAP MOD _GSP-SEEN-POS ! ;

: _GSP-SEEN-MATCH?  ( idx -- flag )
    32 * _GSP-SEEN +
    0
    32 0 ?DO
        OVER I + C@  _GSP-CMP I + C@  XOR OR
    LOOP
    NIP 0= ;

: GSP-SEEN?  ( hash -- flag )
    _GSP-CMP 32 CMOVE
    _GSP-SEEN-CAP 0 ?DO
        I _GSP-SEEN-MATCH? IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

\ =====================================================================
\  5. Peer management
\ =====================================================================

: GSP-CONNECT  ( url-a url-u -- peer-id | -1 )
    \ Find free slot
    -1 GSP-MAX-PEERS 0 ?DO
        _GSP-ACTIVE I + C@ 0= IF DROP I LEAVE THEN
    LOOP
    DUP -1 = IF NIP NIP EXIT THEN     \ no free slot
    >R                                 ( url-a url-u  R: slot )
    WS-CONNECT                         ( ctx | 0     R: slot )
    DUP 0= IF R> 2DROP -1 EXIT THEN   \ connection failed → return -1
    R@ CELLS _GSP-CTX + !             \ store ws-ctx
    1 R@ _GSP-ACTIVE + C!             \ mark active
    R> ;

: GSP-DISCONNECT  ( peer-id -- )
    DUP _GSP-ACTIVE + C@ 0= IF DROP EXIT THEN
    DUP CELLS _GSP-CTX + @ WS-DISCONNECT
    0 SWAP _GSP-ACTIVE + C! ;

: GSP-PEER-COUNT  ( -- n )
    0 GSP-MAX-PEERS 0 ?DO
        _GSP-ACTIVE I + C@ IF 1+ THEN
    LOOP ;

\ =====================================================================
\  6. Message sending helpers
\ =====================================================================

VARIABLE _GSP-SND-LEN

\ Send buffer contents to one peer
: _GSP-SEND1  ( peer-id -- )
    DUP _GSP-ACTIVE + C@ 0= IF DROP EXIT THEN
    CELLS _GSP-CTX + @
    _GSP-SBUF _GSP-SND-LEN @
    WS-SEND-BINARY ;

\ Send buffer contents to ALL active peers
: _GSP-SEND-ALL  ( -- )
    GSP-MAX-PEERS 0 ?DO
        _GSP-ACTIVE I + C@ IF
            I CELLS _GSP-CTX + @
            _GSP-SBUF _GSP-SND-LEN @
            WS-SEND-BINARY
        THEN
    LOOP ;

\ =====================================================================
\  7. GSP-BROADCAST-TX
\ =====================================================================

VARIABLE _GSP-BC-TX

: GSP-BROADCAST-TX  ( tx -- )
    _GSP-BC-TX !
    \ Build message: [0x01][CBOR-encoded tx]
    GSP-MSG-TX _GSP-SBUF C!
    _GSP-BC-TX @ _GSP-SBUF 1+ _GSP-BUF-SZ 1- TX-ENCODE
    1+ _GSP-SND-LEN !
    \ Mark tx hash as seen
    _GSP-BC-TX @ _GSP-HTMP TX-HASH
    _GSP-HTMP _GSP-SEEN-ADD
    \ Send to all
    _GSP-SEND-ALL ;

\ =====================================================================
\  8. GSP-BROADCAST-BLK — announce new block
\ =====================================================================

: GSP-BROADCAST-BLK  ( blk -- )
    \ [0x02][CBOR: 2-array [hash(bstr32), height(uint)]]
    GSP-MSG-BLK-ANN _GSP-SBUF C!
    DUP _GSP-HTMP BLK-HASH             ( blk )
    _GSP-SBUF 1+ _GSP-BUF-SZ 1- CBOR-RESET
    2 CBOR-ARRAY
    _GSP-HTMP 32 CBOR-BSTR
    BLK-HEIGHT@ CBOR-UINT
    CBOR-RESULT NIP 1+ _GSP-SND-LEN !
    \ Mark hash as seen
    _GSP-HTMP _GSP-SEEN-ADD
    _GSP-SEND-ALL ;

\ =====================================================================
\  9. GSP-REQUEST-BLK — request block by height from specific peer
\ =====================================================================

: GSP-REQUEST-BLK  ( height peer -- )
    >R                                  ( height  R: peer )
    GSP-MSG-BLK-REQ _GSP-SBUF C!
    _GSP-SBUF 1+ _GSP-BUF-SZ 1- CBOR-RESET
    CBOR-UINT                           \ encode height
    CBOR-RESULT NIP 1+ _GSP-SND-LEN !
    R> _GSP-SEND1 ;

\ =====================================================================
\  10. GSP-SEND-STATUS — send our chain head to a peer
\ =====================================================================

: GSP-SEND-STATUS  ( peer -- )
    >R
    GSP-MSG-STATUS _GSP-SBUF C!
    _GSP-SBUF 1+ _GSP-BUF-SZ 1- CBOR-RESET
    2 CBOR-ARRAY
    CHAIN-HEAD _GSP-HTMP BLK-HASH
    _GSP-HTMP 32 CBOR-BSTR
    CHAIN-HEIGHT CBOR-UINT
    CBOR-RESULT NIP 1+ _GSP-SND-LEN !
    R> _GSP-SEND1 ;

\ =====================================================================
\  11. Incoming message handlers
\ =====================================================================

VARIABLE _GSP-RX-BUF
VARIABLE _GSP-RX-LEN
VARIABLE _GSP-RX-PEER

\ Handle TX-ANNOUNCE
: _GSP-H-TX  ( -- )
    _GSP-TX-TMP TX-INIT
    _GSP-RX-BUF @ 1+ _GSP-RX-LEN @ 1- _GSP-TX-TMP TX-DECODE
    0= IF EXIT THEN                    \ decode failed
    _GSP-TX-TMP _GSP-HTMP TX-HASH
    _GSP-HTMP GSP-SEEN? IF EXIT THEN   \ already seen
    _GSP-HTMP _GSP-SEEN-ADD
    _GSP-TX-TMP MP-ADD IF
        \ Added to mempool — relay to other peers
        _GSP-TX-TMP GSP-BROADCAST-TX
    THEN
    GSP-ON-TX-XT @ ?DUP IF
        _GSP-TX-TMP SWAP EXECUTE
    THEN ;

\ Handle BLOCK-ANNOUNCE
: _GSP-H-BLK-ANN  ( -- )
    _GSP-RX-BUF @ 1+ _GSP-RX-LEN @ 1- CBOR-PARSE DROP
    CBOR-NEXT-ARRAY DROP               \ 2-array
    CBOR-NEXT-BSTR                     ( hash-a hash-u )
    DUP 32 = IF
        DROP GSP-SEEN? IF EXIT THEN    \ already seen
    ELSE 2DROP THEN
    \ Re-parse to get height
    _GSP-RX-BUF @ 1+ _GSP-RX-LEN @ 1- CBOR-PARSE DROP
    CBOR-NEXT-ARRAY DROP
    CBOR-NEXT-BSTR 2DROP               \ skip hash
    CBOR-NEXT-UINT                     ( height )
    GSP-ON-BLK-ANN-XT @ ?DUP IF
        _GSP-RX-PEER @ ROT EXECUTE     \ ( height peer xt )
    ELSE DROP THEN ;

\ Handle BLOCK-RESPONSE
: _GSP-H-BLK-RSP  ( -- )
    GSP-ON-BLK-RSP-XT @ ?DUP IF
        _GSP-RX-BUF @ 1+ _GSP-RX-LEN @ 1-
        ROT EXECUTE                    \ ( buf len xt )
    THEN ;

\ Handle STATUS
: _GSP-H-STATUS  ( -- )
    _GSP-RX-BUF @ 1+ _GSP-RX-LEN @ 1- CBOR-PARSE DROP
    CBOR-NEXT-ARRAY DROP
    CBOR-NEXT-BSTR 2DROP               \ skip hash
    CBOR-NEXT-UINT                     ( height )
    GSP-ON-STATUS-XT @ ?DUP IF
        _GSP-RX-PEER @ ROT EXECUTE
    ELSE DROP THEN ;

\ =====================================================================
\  12. GSP-ON-MSG — dispatch incoming binary frame
\ =====================================================================

: GSP-ON-MSG  ( buf len peer -- )
    _GSP-RX-PEER ! _GSP-RX-LEN ! _GSP-RX-BUF !
    _GSP-RX-LEN @ 1 < IF EXIT THEN
    _GSP-RX-BUF @ C@                  ( tag )
    DUP GSP-MSG-TX      = IF DROP _GSP-H-TX      EXIT THEN
    DUP GSP-MSG-BLK-ANN = IF DROP _GSP-H-BLK-ANN EXIT THEN
    DUP GSP-MSG-BLK-RSP = IF DROP _GSP-H-BLK-RSP EXIT THEN
    DUP GSP-MSG-STATUS  = IF DROP _GSP-H-STATUS  EXIT THEN
    DROP ;                             \ unknown type — ignore

\ =====================================================================
\  13. GSP-POLL — poll all peers for incoming messages
\ =====================================================================

: GSP-POLL  ( -- )
    GSP-MAX-PEERS 0 ?DO
        _GSP-ACTIVE I + C@ IF
            I CELLS _GSP-CTX + @
            _GSP-RBUF _GSP-BUF-SZ WS-RECV    ( opcode len )
            DUP 0> IF
                OVER WS-OP-BINARY = IF
                    DROP                      \ drop opcode
                    _GSP-RBUF SWAP I GSP-ON-MSG
                ELSE
                    OVER WS-OP-CLOSE = IF
                        2DROP I GSP-DISCONNECT
                    ELSE
                        2DROP                 \ ignore text/ping/pong
                    THEN
                THEN
            ELSE
                2DROP                         \ no data
            THEN
        THEN
    LOOP ;

\ =====================================================================
\  14. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _gsp-guard

' GSP-INIT          CONSTANT _gsp-init-xt
' GSP-CONNECT       CONSTANT _gsp-conn-xt
' GSP-DISCONNECT    CONSTANT _gsp-disc-xt
' GSP-BROADCAST-TX  CONSTANT _gsp-bctx-xt
' GSP-BROADCAST-BLK CONSTANT _gsp-bcbl-xt
' GSP-REQUEST-BLK   CONSTANT _gsp-rqbl-xt
' GSP-SEND-STATUS   CONSTANT _gsp-stat-xt
' GSP-ON-MSG        CONSTANT _gsp-onmg-xt
' GSP-POLL          CONSTANT _gsp-poll-xt

: GSP-INIT          _gsp-init-xt _gsp-guard WITH-GUARD ;
: GSP-CONNECT       _gsp-conn-xt _gsp-guard WITH-GUARD ;
: GSP-DISCONNECT    _gsp-disc-xt _gsp-guard WITH-GUARD ;
: GSP-BROADCAST-TX  _gsp-bctx-xt _gsp-guard WITH-GUARD ;
: GSP-BROADCAST-BLK _gsp-bcbl-xt _gsp-guard WITH-GUARD ;
: GSP-REQUEST-BLK   _gsp-rqbl-xt _gsp-guard WITH-GUARD ;
: GSP-SEND-STATUS   _gsp-stat-xt _gsp-guard WITH-GUARD ;
: GSP-ON-MSG        _gsp-onmg-xt _gsp-guard WITH-GUARD ;
: GSP-POLL          _gsp-poll-xt _gsp-guard WITH-GUARD ;

\ =================================================================
\  Done.
\ =================================================================
