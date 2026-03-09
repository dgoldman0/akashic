\ =================================================================
\  block.f  —  Block Structure & Chain Management
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: BLK- / _BLK-  (block)
\                                        CHAIN- / _CH-  (chain)
\  Depends on: sha3.f merkle.f cbor.f tx.f state.f fmt.f guard.f
\
\  Block structure:
\    Header  ~225 bytes  (version, height, prev_hash, state_root,
\                         tx_root, timestamp, proof)
\    Body    pointer array to up to 256 transaction buffers
\
\  Chain management:
\    Circular buffer of last 64 block headers (configurable).
\    CHAIN-APPEND is the single mutation point for state.
\
\  Validation:
\    BLK-VERIFY uses ST-SNAPSHOT / ST-RESTORE to apply txs
\    tentatively, verify state root, then restore — fully
\    non-destructive.  CHAIN-APPEND applies txs for real.
\
\  Consensus proof validation:
\    Delegated via _BLK-CON-CHECK-XT callback variable.
\    consensus.f patches this at load time.  Default = always TRUE.
\
\  Public API (block):
\   BLK-INIT         ( blk -- )               zero block header+body
\   BLK-SET-PREV     ( hash blk -- )          set previous block hash
\   BLK-SET-HEIGHT   ( n blk -- )             set block height
\   BLK-SET-TIME     ( t blk -- )             set timestamp
\   BLK-SET-PROOF    ( addr len blk -- )      set consensus proof
\   BLK-ADD-TX       ( tx blk -- flag )       append tx (fail if full)
\   BLK-FINALIZE     ( blk -- )               compute tx root + state root
\   BLK-HASH         ( blk hash -- )          SHA3-256 of CBOR header
\   BLK-VERIFY       ( blk prev-hash -- flag) full non-destructive validation
\   BLK-ENCODE       ( blk buf max -- len )   serialize full block to CBOR
\   BLK-DECODE       ( buf len blk -- flag )  deserialize full block from CBOR
\   BLK-HEIGHT@      ( blk -- n )             read height
\   BLK-TX-COUNT@    ( blk -- n )             read tx count
\   BLK-VERSION@     ( blk -- n )             read version
\   BLK-TIME@        ( blk -- n )             read timestamp
\   BLK-PREV-HASH@   ( blk -- addr )          pointer to prev_hash
\   BLK-STATE-ROOT@  ( blk -- addr )          pointer to state_root
\   BLK-TX-ROOT@     ( blk -- addr )          pointer to tx_root
\   BLK-PROOF@       ( blk -- addr len )      pointer+length of proof
\   BLK-TX@          ( idx blk -- tx )        get tx pointer by index
\   BLK-PRINT        ( blk -- )               debug dump
\
\  Public API (chain):
\   CHAIN-INIT       ( -- )                   init chain + genesis block
\   CHAIN-HEAD       ( -- blk )               current chain tip header
\   CHAIN-APPEND     ( blk -- flag )          validate + apply + append
\   CHAIN-HEIGHT     ( -- n )                 current chain height
\   CHAIN-BLOCK@     ( n -- blk | 0 )         header by height (recent only)
\
\  Constants:
\   BLK-MAX-TXS      ( -- 256 )
\   BLK-HDR-SIZE      ( -- 225 )
\   BLK-PROOF-MAX     ( -- 128 )
\   CHAIN-HISTORY     ( -- 64 )
\
\  Not reentrant.
\ =================================================================

REQUIRE sha3.f
REQUIRE merkle.f
REQUIRE cbor.f
REQUIRE tx.f
REQUIRE state.f
REQUIRE fmt.f

PROVIDED akashic-block

\ =====================================================================
\  1. Constants
\ =====================================================================

256 CONSTANT BLK-MAX-TXS
128 CONSTANT BLK-PROOF-MAX
 64 CONSTANT CHAIN-HISTORY
  1 CONSTANT _BLK-VERSION           \ protocol version

\ =====================================================================
\  2. Block Header Layout (225 bytes)
\ =====================================================================
\
\  Offset  Size    Field
\  ------  ------  -----
\    0       1     version      (u8, protocol version)
\    1       8     height       (u64, block number)
\    9      32     prev_hash    (SHA3-256 of previous block header)
\   41      32     state_root   (Merkle root of state after txs)
\   73      32     tx_root      (Merkle root of tx hashes)
\  105       8     timestamp    (u64, Unix seconds)
\  113       1     proof_len    (u8, length of proof data, 0..128)
\  114     128     proof        (consensus-specific data)
\  ------
\  242 total (allows growth; 8-byte aligned at 248 with padding)
\
\  We round up to 248 for alignment.

248 CONSTANT BLK-HDR-SIZE

  0 CONSTANT _BLK-OFF-VER
  1 CONSTANT _BLK-OFF-HEIGHT
  9 CONSTANT _BLK-OFF-PREV
 41 CONSTANT _BLK-OFF-SROOT
 73 CONSTANT _BLK-OFF-TXROOT
105 CONSTANT _BLK-OFF-TIME
113 CONSTANT _BLK-OFF-PLEN
114 CONSTANT _BLK-OFF-PROOF

\ =====================================================================
\  3. Block Body — tx count + pointer array
\ =====================================================================
\
\  After the 248-byte header:
\    +248      8 bytes   tx_count (cell)
\    +256   2048 bytes   tx pointers (256 x 8-byte cells)
\
\  Total block struct size: 248 + 8 + 2048 = 2304 bytes
\  (The tx data lives in separate TX-BUF-SIZE buffers, not inline.)

2304 CONSTANT BLK-STRUCT-SIZE

248 CONSTANT _BLK-OFF-TXCNT
256 CONSTANT _BLK-OFF-TXPTRS

\ =====================================================================
\  4. Header field accessors
\ =====================================================================

: _BLK-VER       ( blk -- addr )  _BLK-OFF-VER + ;
: _BLK-HEIGHT    ( blk -- addr )  _BLK-OFF-HEIGHT + ;
: _BLK-PREV      ( blk -- addr )  _BLK-OFF-PREV + ;
: _BLK-SROOT     ( blk -- addr )  _BLK-OFF-SROOT + ;
: _BLK-TXROOT    ( blk -- addr )  _BLK-OFF-TXROOT + ;
: _BLK-TIME      ( blk -- addr )  _BLK-OFF-TIME + ;
: _BLK-PLEN      ( blk -- addr )  _BLK-OFF-PLEN + ;
: _BLK-PROOF     ( blk -- addr )  _BLK-OFF-PROOF + ;
: _BLK-TXCNT     ( blk -- addr )  _BLK-OFF-TXCNT + ;
: _BLK-TXPTRS    ( blk -- addr )  _BLK-OFF-TXPTRS + ;

\ =====================================================================
\  5. Public getters
\ =====================================================================

: BLK-VERSION@    ( blk -- n )     _BLK-VER C@ ;
: BLK-HEIGHT@     ( blk -- n )     _BLK-HEIGHT @ ;
: BLK-TX-COUNT@   ( blk -- n )     _BLK-TXCNT @ ;
: BLK-TIME@       ( blk -- n )     _BLK-TIME @ ;
: BLK-PREV-HASH@  ( blk -- addr )  _BLK-PREV ;
: BLK-STATE-ROOT@ ( blk -- addr )  _BLK-SROOT ;
: BLK-TX-ROOT@    ( blk -- addr )  _BLK-TXROOT ;

: BLK-PROOF@  ( blk -- addr len )
    DUP _BLK-PROOF SWAP _BLK-PLEN C@ ;

: BLK-TX@  ( idx blk -- tx )
    _BLK-TXPTRS SWAP CELLS + @ ;

\ =====================================================================
\  6. BLK-INIT — zero block struct, set version
\ =====================================================================

: BLK-INIT  ( blk -- )
    DUP BLK-STRUCT-SIZE 0 FILL
    _BLK-VERSION SWAP _BLK-VER C! ;

\ =====================================================================
\  7. Setters
\ =====================================================================

: BLK-SET-PREV  ( hash blk -- )
    _BLK-PREV 32 CMOVE ;

: BLK-SET-HEIGHT  ( n blk -- )
    _BLK-HEIGHT ! ;

: BLK-SET-TIME  ( t blk -- )
    _BLK-TIME ! ;

VARIABLE _BLK-SP-LEN
VARIABLE _BLK-SP-BLK

: BLK-SET-PROOF  ( addr len blk -- )
    _BLK-SP-BLK !
    DUP BLK-PROOF-MAX > IF 2DROP EXIT THEN   \ reject if too long
    _BLK-SP-LEN !
    _BLK-SP-BLK @ _BLK-PROOF _BLK-SP-LEN @ CMOVE
    _BLK-SP-LEN @ _BLK-SP-BLK @ _BLK-PLEN C! ;

\ =====================================================================
\  8. BLK-ADD-TX — append transaction pointer to block
\ =====================================================================

VARIABLE _BLK-AT-BLK

: BLK-ADD-TX  ( tx blk -- flag )
    _BLK-AT-BLK !
    _BLK-AT-BLK @ BLK-TX-COUNT@ BLK-MAX-TXS >= IF
        DROP 0 EXIT                       \ block full
    THEN
    \ Store tx pointer at next slot
    _BLK-AT-BLK @ _BLK-TXCNT @ CELLS    \ offset = count * CELL
    _BLK-AT-BLK @ _BLK-TXPTRS + !       \ txptrs[count] = tx
    \ Increment count
    _BLK-AT-BLK @ _BLK-TXCNT DUP @ 1+ SWAP ! ;

\ =====================================================================
\  9. Transaction Merkle tree (256-leaf, shared with state)
\ =====================================================================

256 MERKLE-TREE _BLK-TX-TREE
CREATE _BLK-TX-HASH-TMP  32 ALLOT

\ _BLK-COMPUTE-TX-ROOT ( blk -- )
\   Hash each tx, fill leaves, build tree, copy root to blk.
VARIABLE _BLK-CTR-BLK

: _BLK-COMPUTE-TX-ROOT  ( blk -- )
    _BLK-CTR-BLK !
    \ Zero all leaves
    _BLK-TX-HASH-TMP 32 0 FILL
    BLK-MAX-TXS 0 ?DO
        _BLK-TX-HASH-TMP I _BLK-TX-TREE MERKLE-LEAF!
    LOOP
    \ Hash each tx into its leaf slot
    _BLK-CTR-BLK @ BLK-TX-COUNT@ 0 ?DO
        I _BLK-CTR-BLK @ BLK-TX@ _BLK-TX-HASH-TMP TX-HASH
        _BLK-TX-HASH-TMP I _BLK-TX-TREE MERKLE-LEAF!
    LOOP
    _BLK-TX-TREE MERKLE-BUILD
    \ Copy 32-byte root into block header
    _BLK-TX-TREE MERKLE-ROOT _BLK-CTR-BLK @ _BLK-TXROOT 32 CMOVE ;

\ =====================================================================
\  10. BLK-FINALIZE — compute tx root + state root (for block producer)
\ =====================================================================
\  Called by the block producer after adding all txs.
\  1. Compute tx Merkle root.
\  2. Apply all txs to global state.
\  3. Compute state Merkle root.
\  4. Store both roots in the block header.
\
\  Note: this MUTATES global state — it's for the producer path.
\  Validators use BLK-VERIFY (non-destructive) followed by
\  CHAIN-APPEND (which re-applies).

VARIABLE _BLK-FIN-BLK

: BLK-FINALIZE  ( blk -- )
    _BLK-FIN-BLK !
    \ 1. Compute tx Merkle root
    _BLK-FIN-BLK @ _BLK-COMPUTE-TX-ROOT
    \ 2. Apply all txs to state
    _BLK-FIN-BLK @ BLK-TX-COUNT@ 0 ?DO
        I _BLK-FIN-BLK @ BLK-TX@ ST-APPLY-TX DROP
    LOOP
    \ 3. Compute and store state root
    ST-ROOT DROP _BLK-FIN-BLK @ _BLK-SROOT 32 CMOVE ;

\ =====================================================================
\  11. BLK-HASH — SHA3-256 of CBOR-encoded header
\ =====================================================================
\
\  We CBOR-encode the header fields into a scratch buffer, then
\  SHA3-256 hash the encoded bytes to produce the 32-byte block hash.

CREATE _BLK-CBUF  1024 ALLOT
1024 CONSTANT _BLK-CBUF-SZ
CREATE _BLK-HASH-SCRATCH  32 ALLOT

\ CBOR key strings for block header (DAG-CBOR canonical: shorter first, then lex)
\   "proof"(5) "height"(6) "tx_root"(7) "version"(7)
\   "prev_hash"(9) "timestamp"(9) "state_root"(10)
CREATE _BK-PROOF      5 C, 112 C, 114 C, 111 C, 111 C, 102 C,                     \ "proof"
CREATE _BK-HEIGHT     6 C, 104 C, 101 C, 105 C, 103 C, 104 C, 116 C,              \ "height"
CREATE _BK-TXROOT     7 C, 116 C, 120 C,  95 C, 114 C, 111 C, 111 C, 116 C,       \ "tx_root"
CREATE _BK-VERSION    7 C, 118 C, 101 C, 114 C, 115 C, 105 C, 111 C, 110 C,       \ "version"
CREATE _BK-PREVHASH   9 C, 112 C, 114 C, 101 C, 118 C,  95 C, 104 C,  97 C, 115 C, 104 C, \ "prev_hash"
CREATE _BK-TIMESTAMP  9 C, 116 C, 105 C, 109 C, 101 C, 115 C, 116 C,  97 C, 109 C, 112 C, \ "timestamp"
CREATE _BK-STATEROOT 10 C, 115 C, 116 C,  97 C, 116 C, 101 C,  95 C, 114 C, 111 C, 111 C, 116 C, \ "state_root"

\ Helper: push counted string as ( addr len )
: _BK>  ( cstr -- addr len )  DUP 1+ SWAP C@ ;

\ _BLK-ENCODE-HEADER ( blk -- len )
\   CBOR-encode block header into _BLK-CBUF.  Returns encoded length.
VARIABLE _BLK-EH-BLK

: _BLK-ENCODE-HEADER  ( blk -- len )
    _BLK-EH-BLK !
    _BLK-CBUF _BLK-CBUF-SZ CBOR-RESET

    7 CBOR-MAP                            \ 7 header fields

    \ 1. "proof" (5)
    _BK-PROOF _BK> CBOR-TSTR
    _BLK-EH-BLK @ _BLK-PROOF
    _BLK-EH-BLK @ _BLK-PLEN C@ CBOR-BSTR

    \ 2. "height" (6)
    _BK-HEIGHT _BK> CBOR-TSTR
    _BLK-EH-BLK @ BLK-HEIGHT@ CBOR-UINT

    \ 3. "tx_root" (7)
    _BK-TXROOT _BK> CBOR-TSTR
    _BLK-EH-BLK @ _BLK-TXROOT 32 CBOR-BSTR

    \ 4. "version" (7)
    _BK-VERSION _BK> CBOR-TSTR
    _BLK-EH-BLK @ BLK-VERSION@ CBOR-UINT

    \ 5. "prev_hash" (9)
    _BK-PREVHASH _BK> CBOR-TSTR
    _BLK-EH-BLK @ _BLK-PREV 32 CBOR-BSTR

    \ 6. "timestamp" (9)
    _BK-TIMESTAMP _BK> CBOR-TSTR
    _BLK-EH-BLK @ BLK-TIME@ CBOR-UINT

    \ 7. "state_root" (10)
    _BK-STATEROOT _BK> CBOR-TSTR
    _BLK-EH-BLK @ _BLK-SROOT 32 CBOR-BSTR

    CBOR-RESULT NIP ;

: BLK-HASH  ( blk hash -- )
    SWAP _BLK-ENCODE-HEADER           \ -- hash len
    _BLK-CBUF SWAP                     \ -- hash cbuf len
    ROT SHA3-256-HASH ;               \ SHA3-256(cbuf, len) -> hash

\ =====================================================================
\  12. BLK-ENCODE — full block CBOR serialization
\ =====================================================================
\
\  Outer structure: CBOR array of 2 items:
\    [0] = header (CBOR map, 7 fields)
\    [1] = txs    (CBOR array, each tx encoded inline via TX-ENCODE)
\
\  We encode into the caller-provided buffer.

VARIABLE _BLK-E-BLK
VARIABLE _BLK-E-DST
VARIABLE _BLK-E-MAX
CREATE _BLK-TX-SCRATCH  16384 ALLOT

: BLK-ENCODE  ( blk buf max -- len )
    _BLK-E-MAX ! _BLK-E-DST ! _BLK-E-BLK !

    _BLK-E-DST @ _BLK-E-MAX @ CBOR-RESET

    2 CBOR-ARRAY                          \ [ header, txs ]

    \ --- header map (inline) ---
    7 CBOR-MAP

    _BK-PROOF _BK> CBOR-TSTR
    _BLK-E-BLK @ _BLK-PROOF _BLK-E-BLK @ _BLK-PLEN C@ CBOR-BSTR

    _BK-HEIGHT _BK> CBOR-TSTR
    _BLK-E-BLK @ BLK-HEIGHT@ CBOR-UINT

    _BK-TXROOT _BK> CBOR-TSTR
    _BLK-E-BLK @ _BLK-TXROOT 32 CBOR-BSTR

    _BK-VERSION _BK> CBOR-TSTR
    _BLK-E-BLK @ BLK-VERSION@ CBOR-UINT

    _BK-PREVHASH _BK> CBOR-TSTR
    _BLK-E-BLK @ _BLK-PREV 32 CBOR-BSTR

    _BK-TIMESTAMP _BK> CBOR-TSTR
    _BLK-E-BLK @ BLK-TIME@ CBOR-UINT

    _BK-STATEROOT _BK> CBOR-TSTR
    _BLK-E-BLK @ _BLK-SROOT 32 CBOR-BSTR

    \ --- txs array ---
    _BLK-E-BLK @ BLK-TX-COUNT@ CBOR-ARRAY
    _BLK-E-BLK @ BLK-TX-COUNT@ 0 ?DO
        I _BLK-E-BLK @ BLK-TX@ _BLK-TX-SCRATCH 16384 TX-ENCODE
        \ Encode the tx CBOR as a nested byte string
        _BLK-TX-SCRATCH SWAP CBOR-BSTR
    LOOP

    CBOR-RESULT NIP ;

\ =====================================================================
\  13. BLK-DECODE — full block CBOR deserialization
\ =====================================================================
\
\  Expects: CBOR array of 2 = [ header-map, txs-array ]
\  For txs: each is a CBOR byte string containing an encoded tx.
\  The caller must provide pre-allocated tx buffers via BLK-ADD-TX
\  AFTER decode, or we can decode into a pool.
\
\  Strategy: decode header fields from the map.  For txs, decode
\  each bstr and TX-DECODE into caller-provided tx buffers.
\  The blk must already have tx buffers registered via a tx pool.
\
\  For simplicity: BLK-DECODE only populates the header.  Tx decode
\  is handled separately since tx buffer allocation is caller's
\  responsibility.  Returns -1 on success, 0 on failure.

VARIABLE _BLK-D-BLK
VARIABLE _BLK-D-PAIRS
VARIABLE _BLK-D-KA
VARIABLE _BLK-D-KL

\ Helper: compare two byte sequences
: _BLK-STREQ  ( a1 l1 a2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    0 ?DO
        OVER I + C@  OVER I + C@
        <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

: BLK-DECODE  ( buf len blk -- flag )
    _BLK-D-BLK !
    _BLK-D-BLK @ BLK-INIT

    CBOR-PARSE DROP

    \ Expect outer array of 2
    CBOR-TYPE 4 <> IF 0 EXIT THEN
    CBOR-NEXT-ARRAY 2 <> IF 0 EXIT THEN

    \ First element: header map
    CBOR-TYPE 5 <> IF 0 EXIT THEN
    CBOR-NEXT-MAP _BLK-D-PAIRS !

    _BLK-D-PAIRS @ 0 ?DO
        CBOR-TYPE 3 <> IF 0 UNLOOP EXIT THEN
        CBOR-NEXT-TSTR _BLK-D-KL ! _BLK-D-KA !

        _BLK-D-KA @ _BLK-D-KL @
        _BK-VERSION _BK> _BLK-STREQ IF
            CBOR-NEXT-UINT _BLK-D-BLK @ _BLK-VER C!
        ELSE _BLK-D-KA @ _BLK-D-KL @
        _BK-HEIGHT _BK> _BLK-STREQ IF
            CBOR-NEXT-UINT _BLK-D-BLK @ _BLK-HEIGHT !
        ELSE _BLK-D-KA @ _BLK-D-KL @
        _BK-PREVHASH _BK> _BLK-STREQ IF
            CBOR-NEXT-BSTR DROP          \ -- addr
            _BLK-D-BLK @ _BLK-PREV 32 CMOVE
        ELSE _BLK-D-KA @ _BLK-D-KL @
        _BK-STATEROOT _BK> _BLK-STREQ IF
            CBOR-NEXT-BSTR DROP
            _BLK-D-BLK @ _BLK-SROOT 32 CMOVE
        ELSE _BLK-D-KA @ _BLK-D-KL @
        _BK-TXROOT _BK> _BLK-STREQ IF
            CBOR-NEXT-BSTR DROP
            _BLK-D-BLK @ _BLK-TXROOT 32 CMOVE
        ELSE _BLK-D-KA @ _BLK-D-KL @
        _BK-TIMESTAMP _BK> _BLK-STREQ IF
            CBOR-NEXT-UINT _BLK-D-BLK @ _BLK-TIME !
        ELSE _BLK-D-KA @ _BLK-D-KL @
        _BK-PROOF _BK> _BLK-STREQ IF
            CBOR-NEXT-BSTR               \ -- addr len
            DUP BLK-PROOF-MAX > IF 2DROP 0 UNLOOP EXIT THEN
            _BLK-D-BLK @ BLK-SET-PROOF
        ELSE
            CBOR-SKIP
        THEN THEN THEN THEN THEN THEN THEN
    LOOP

    \ Second element: txs array — skip for now (header-only decode)
    \ Caller can re-parse the buffer to extract txs if needed.
    CBOR-SKIP

    -1 ;

\ =====================================================================
\  14. Consensus proof callback
\ =====================================================================
\  Default: always accept.  consensus.f will overwrite this XT.

: _BLK-CON-TRUE  ( blk -- flag )  DROP -1 ;
VARIABLE _BLK-CON-CHECK-XT
' _BLK-CON-TRUE _BLK-CON-CHECK-XT !

\ =====================================================================
\  15. BLK-VERIFY — full non-destructive block validation
\ =====================================================================
\
\  Checks:
\    1. prev_hash matches supplied previous hash
\    2. Height = prev height + 1 (caller-supplied via block)
\    3. Timestamp >= 0 (basic sanity; more checks in consensus.f)
\    4. All txs pass TX-VERIFY (signature check)
\    5. No duplicate nonces per sender within block
\    6. Tx Merkle root matches
\    7. State root matches (snapshot, apply, compare, restore)
\    8. Consensus proof valid (via callback)
\
\  Returns -1 (TRUE) if valid, 0 (FALSE) if invalid.

VARIABLE _BLK-V-SNAP-PTR                       \ XMEM snapshot buffer (lazy)
0 _BLK-V-SNAP-PTR !
: _BLK-V-SNAP  ( -- addr )
    _BLK-V-SNAP-PTR @ ?DUP IF EXIT THEN
    ST-SNAPSHOT-SIZE XMEM-ALLOT DUP _BLK-V-SNAP-PTR ! ;
CREATE _BLK-V-HASH   32 ALLOT                  \ scratch for hashes
CREATE _BLK-V-ROOT   32 ALLOT                  \ computed state root
CREATE _BLK-V-TXROOT 32 ALLOT                  \ computed tx root
VARIABLE _BLK-V-BLK
VARIABLE _BLK-V-PREV

\ _BLK-CHECK-DUP-NONCES ( blk -- flag )
\   TRUE if no duplicate (sender, nonce) pairs within block.
\   O(n²) but n ≤ 256 per block — acceptable.
VARIABLE _BLK-DN-I
VARIABLE _BLK-DN-J
VARIABLE _BLK-DN-BLK
CREATE _BLK-DN-A 32 ALLOT
CREATE _BLK-DN-B 32 ALLOT

: _BLK-CHECK-DUP-NONCES  ( blk -- flag )
    _BLK-DN-BLK !
    _BLK-DN-BLK @ BLK-TX-COUNT@ DUP 2 < IF DROP -1 EXIT THEN
    DUP 1-   \ -- count count-1
    0 ?DO
        I _BLK-DN-I !
        DUP _BLK-DN-I @ 1+ ?DO
            \ Compare sender + nonce of tx I and tx J
            _BLK-DN-I @ _BLK-DN-BLK @ BLK-TX@
            I          _BLK-DN-BLK @ BLK-TX@
            \ Same sender?
            OVER TX-FROM@ OVER TX-FROM@ 32
            _BLK-DN-A 32 0 FILL
            0                             \ accumulate diff
            32 0 ?DO                      ( tx-i tx-j diff )
                3 PICK TX-FROM@ I + C@
                3 PICK TX-FROM@ I + C@
                XOR OR
            LOOP
            0= IF                          \ same sender
                \ Same nonce?
                OVER TX-NONCE@ OVER TX-NONCE@ = IF
                    2DROP DROP DROP 0 UNLOOP UNLOOP EXIT   \ duplicate found
                THEN
            THEN
            2DROP
        LOOP
    LOOP
    DROP -1 ;

: BLK-VERIFY  ( blk prev-hash -- flag )
    _BLK-V-PREV !
    _BLK-V-BLK !

    \ 1. prev_hash matches
    _BLK-V-BLK @ _BLK-PREV _BLK-V-PREV @ 32
    0                                     \ accumulate XOR diff
    32 0 ?DO
        3 PICK I + C@  3 PICK I + C@
        XOR OR
    LOOP
    NIP NIP                               \ -- diff
    0<> IF 0 EXIT THEN

    \ 2. Timestamp sanity (must be non-zero for non-genesis)
    _BLK-V-BLK @ BLK-HEIGHT@ 0> IF
        _BLK-V-BLK @ BLK-TIME@ 0= IF 0 EXIT THEN
    THEN

    \ 3. All txs valid (signature check)
    _BLK-V-BLK @ BLK-TX-COUNT@ 0 ?DO
        I _BLK-V-BLK @ BLK-TX@ TX-VERIFY 0= IF
            0 UNLOOP EXIT
        THEN
    LOOP

    \ 4. No duplicate nonces per sender
    _BLK-V-BLK @ _BLK-CHECK-DUP-NONCES 0= IF 0 EXIT THEN

    \ 5. Tx Merkle root check — recompute and compare
    _BLK-V-BLK @ _BLK-COMPUTE-TX-ROOT
    _BLK-TX-TREE MERKLE-ROOT _BLK-V-TXROOT 32 CMOVE
    _BLK-V-BLK @ _BLK-TXROOT _BLK-V-TXROOT 32
    0
    32 0 ?DO
        3 PICK I + C@  3 PICK I + C@
        XOR OR
    LOOP
    NIP NIP
    0<> IF 0 EXIT THEN

    \ 6. State root check — snapshot, apply txs, compare, restore
    _BLK-V-SNAP ST-SNAPSHOT
    \ Apply all txs tentatively
    _BLK-V-BLK @ BLK-TX-COUNT@ 0 ?DO
        I _BLK-V-BLK @ BLK-TX@ ST-APPLY-TX 0= IF
            \ Tx failed — restore and reject
            _BLK-V-SNAP ST-RESTORE
            0 UNLOOP EXIT
        THEN
    LOOP
    \ Compute state root and compare
    ST-ROOT DROP _BLK-V-ROOT 32 CMOVE
    _BLK-V-SNAP ST-RESTORE               \ restore original state
    _BLK-V-BLK @ _BLK-SROOT _BLK-V-ROOT 32
    0
    32 0 ?DO
        3 PICK I + C@  3 PICK I + C@
        XOR OR
    LOOP
    NIP NIP
    0<> IF 0 EXIT THEN

    \ 7. Consensus proof check (via callback)
    _BLK-V-BLK @ _BLK-CON-CHECK-XT @ EXECUTE
    0= IF 0 EXIT THEN

    -1 ;

\ =====================================================================
\  16. BLK-PRINT — debug dump
\ =====================================================================

: BLK-PRINT  ( blk -- )
    DUP ." BLK{ v=" BLK-VERSION@ .
    DUP ."  h=" BLK-HEIGHT@ .
    DUP ."  txs=" BLK-TX-COUNT@ .
    DUP ."  t=" BLK-TIME@ .
    DUP ."  prev=" _BLK-PREV 8 FMT-.HEX ." .."
    DUP ."  sr=" _BLK-SROOT 8 FMT-.HEX ." .."
        ."  tr=" _BLK-TXROOT 8 FMT-.HEX ." .."
    ." }" CR ;

\ =====================================================================
\  17. Chain storage — circular buffer of block headers
\ =====================================================================
\
\  We store the last CHAIN-HISTORY (64) block headers.
\  Only headers are stored; tx data is ephemeral.
\  Access to older blocks requires re-fetch from network.

CREATE _CH-RING   CHAIN-HISTORY BLK-HDR-SIZE * ALLOT
VARIABLE _CH-HEIGHT           \ current chain height (-1 = empty)
CREATE _CH-HEAD-HASH  32 ALLOT   \ hash of chain tip

\ _CH-SLOT ( height -- addr )  Map height to ring buffer slot.
: _CH-SLOT  ( height -- addr )
    CHAIN-HISTORY MOD BLK-HDR-SIZE * _CH-RING + ;

\ =====================================================================
\  18. CHAIN-INIT — initialize chain with genesis block
\ =====================================================================
\
\  Genesis block: height 0, all-zero prev_hash, empty txs.
\  State root computed from current (presumably freshly initialized) state.

CREATE _CH-GENESIS  BLK-STRUCT-SIZE ALLOT
CREATE _CH-ZERO-HASH  32 ALLOT

: CHAIN-INIT  ( -- )
    \ Zero ring buffer and height
    _CH-RING CHAIN-HISTORY BLK-HDR-SIZE * 0 FILL
    -1 _CH-HEIGHT !
    _CH-HEAD-HASH 32 0 FILL
    _CH-ZERO-HASH 32 0 FILL

    \ Build genesis block
    _CH-GENESIS BLK-INIT
    0 _CH-GENESIS BLK-SET-HEIGHT
    _CH-ZERO-HASH _CH-GENESIS BLK-SET-PREV
    0 _CH-GENESIS BLK-SET-TIME
    \ Compute state root from current state for genesis
    ST-ROOT DROP _CH-GENESIS _BLK-SROOT 32 CMOVE
    \ Tx root = empty tree root
    _CH-GENESIS _BLK-COMPUTE-TX-ROOT

    \ Store genesis header in ring slot 0
    _CH-GENESIS 0 _CH-SLOT BLK-HDR-SIZE CMOVE
    0 _CH-HEIGHT !
    \ Compute and store genesis hash
    _CH-GENESIS _CH-HEAD-HASH BLK-HASH ;

\ =====================================================================
\  19. Chain accessors
\ =====================================================================

: CHAIN-HEIGHT  ( -- n )  _CH-HEIGHT @ ;

: CHAIN-HEAD  ( -- blk )
    _CH-HEIGHT @ _CH-SLOT ;

: CHAIN-BLOCK@  ( n -- blk | 0 )
    DUP _CH-HEIGHT @ > IF DROP 0 EXIT THEN          \ future block
    DUP 0< IF DROP 0 EXIT THEN                      \ negative height
    _CH-HEIGHT @ OVER - CHAIN-HISTORY >= IF
        DROP 0 EXIT                                  \ too old, evicted
    THEN
    _CH-SLOT ;

\ =====================================================================
\  20. CHAIN-APPEND — validate and append block to chain
\ =====================================================================
\
\  Single mutation point for state.  Steps:
\    1. Validate block via BLK-VERIFY (non-destructive).
\    2. Apply all txs to global state (permanent).
\    3. Copy header into ring buffer.
\    4. Update chain height and head hash.

VARIABLE _CH-APP-BLK

: CHAIN-APPEND  ( blk -- flag )
    _CH-APP-BLK !

    \ Height must be exactly chain height + 1
    _CH-APP-BLK @ BLK-HEIGHT@ _CH-HEIGHT @ 1+ <> IF
        0 EXIT
    THEN

    \ Validate block (non-destructive)
    _CH-APP-BLK @ _CH-HEAD-HASH BLK-VERIFY
    0= IF 0 EXIT THEN

    \ Apply all txs to state (permanent mutation)
    _CH-APP-BLK @ BLK-TX-COUNT@ 0 ?DO
        I _CH-APP-BLK @ BLK-TX@ ST-APPLY-TX DROP
    LOOP

    \ Copy header into ring buffer
    _CH-APP-BLK @
    _CH-APP-BLK @ BLK-HEIGHT@ _CH-SLOT
    BLK-HDR-SIZE CMOVE

    \ Update height
    _CH-APP-BLK @ BLK-HEIGHT@ _CH-HEIGHT !

    \ Update head hash
    _CH-APP-BLK @  _CH-HEAD-HASH BLK-HASH

    -1 ;

\ =====================================================================
\  21. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _blk-guard

' BLK-INIT          CONSTANT _blk-init-xt
' BLK-SET-PREV      CONSTANT _blk-sp-xt
' BLK-SET-HEIGHT    CONSTANT _blk-sh-xt
' BLK-SET-TIME      CONSTANT _blk-st-xt
' BLK-SET-PROOF     CONSTANT _blk-spr-xt
' BLK-ADD-TX        CONSTANT _blk-at-xt
' BLK-FINALIZE      CONSTANT _blk-fin-xt
' BLK-HASH          CONSTANT _blk-hash-xt
' BLK-VERIFY        CONSTANT _blk-ver-xt
' BLK-ENCODE        CONSTANT _blk-enc-xt
' BLK-DECODE        CONSTANT _blk-dec-xt
' CHAIN-INIT        CONSTANT _ch-init-xt
' CHAIN-APPEND      CONSTANT _ch-app-xt

: BLK-INIT          _blk-init-xt  _blk-guard WITH-GUARD ;
: BLK-SET-PREV      _blk-sp-xt    _blk-guard WITH-GUARD ;
: BLK-SET-HEIGHT    _blk-sh-xt    _blk-guard WITH-GUARD ;
: BLK-SET-TIME      _blk-st-xt    _blk-guard WITH-GUARD ;
: BLK-SET-PROOF     _blk-spr-xt   _blk-guard WITH-GUARD ;
: BLK-ADD-TX        _blk-at-xt    _blk-guard WITH-GUARD ;
: BLK-FINALIZE      _blk-fin-xt   _blk-guard WITH-GUARD ;
: BLK-HASH          _blk-hash-xt  _blk-guard WITH-GUARD ;
: BLK-VERIFY        _blk-ver-xt   _blk-guard WITH-GUARD ;
: BLK-ENCODE        _blk-enc-xt   _blk-guard WITH-GUARD ;
: BLK-DECODE        _blk-dec-xt   _blk-guard WITH-GUARD ;
: CHAIN-INIT        _ch-init-xt   _blk-guard WITH-GUARD ;
: CHAIN-APPEND      _ch-app-xt    _blk-guard WITH-GUARD ;

\ =====================================================================
\  Done.
\ =====================================================================
