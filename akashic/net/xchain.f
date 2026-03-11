\ ====================================================================
\  xchain.f — Cross-Chain Verification
\ ====================================================================
\
\  PREFIX: XCH-
\
\  Verify foreign chain block headers and account state without
\  running a foreign chain node.  Two verification levels:
\
\  1. Block attestation — verify Ed25519 consensus signature in
\     foreign PoA/PoSA block headers.
\
\  2. State inclusion — stateless SMT proof verification against
\     the last verified foreign state root.
\
\  Together these let chain A cryptographically verify chain B's
\  account state — no inter-validator trust beyond knowing the
\  foreign chain's authority public keys.
\
\  Note: STARK-based execution proofs are a future extension
\  (requires proof serialization layer in stark.f).  Phase 7.5
\  uses signature-based attestation covering the consortium model.
\
\ ====================================================================

PROVIDED xchain.f

REQUIRE ../store/block.f
REQUIRE ../math/ed25519.f
REQUIRE ../store/smt.f
REQUIRE ../math/sha3.f
REQUIRE ../concurrency/guard.f

\ ====================================================================
\  1. Constants
\ ====================================================================

16 CONSTANT XCH-MAX-CHAINS         \ max tracked foreign chains
 8 CONSTANT XCH-MAX-AUTH           \ max authority keys per chain

\ Fault codes
 0 CONSTANT XCH-OK
 1 CONSTANT XCH-ERR-FULL           \ registry full
 2 CONSTANT XCH-ERR-NOT-FOUND      \ chain-id not in registry
 3 CONSTANT XCH-ERR-DECODE         \ CBOR block decode failed
 4 CONSTANT XCH-ERR-HEIGHT         \ height not sequential
 5 CONSTANT XCH-ERR-PREV           \ prev_hash mismatch
 6 CONSTANT XCH-ERR-SIG            \ Ed25519 signature invalid
 7 CONSTANT XCH-ERR-AUTH           \ signer not in authority table
 8 CONSTANT XCH-ERR-MODE           \ unsupported consensus mode
 9 CONSTANT XCH-ERR-IDX            \ authority index out of range

\ ====================================================================
\  2. Registry layout
\ ====================================================================
\
\  Per-chain entry: 384 bytes
\
\    Offset  Size  Field
\    ------  ----  -----
\       0      8   chain_id
\       8      8   con_mode     (1=PoA, 3=PoSA)
\      16      8   air_version  (future STARK compat)
\      24      8   n_auth       (0..8 authority key count)
\      32    256   auth_keys    (8 × 32B Ed25519 pubkeys)
\     288      8   last_height
\     296     32   last_hash    (block hash of last verified header)
\     328     32   last_root    (state root of last verified header)
\     360      8   flags        (bit0=active, bit1=has_header)
\     368     16   reserved
\
\  Registry total: 16 × 384 = 6144 bytes

384 CONSTANT _XCH-ENTRY-SZ

CREATE _XCH-REG  _XCH-ENTRY-SZ XCH-MAX-CHAINS * ALLOT
VARIABLE _XCH-COUNT

\ Field accessors  ( entry -- field-addr )
: _XCH-E-MODE   ( e -- a )    8 + ;
: _XCH-E-AIR    ( e -- a )   16 + ;
: _XCH-E-NAUTH  ( e -- a )   24 + ;
: _XCH-E-KEYS   ( e -- a )   32 + ;
: _XCH-E-HGT    ( e -- a )  288 + ;
: _XCH-E-HASH   ( e -- a )  296 + ;
: _XCH-E-ROOT   ( e -- a )  328 + ;
: _XCH-E-FLAGS  ( e -- a )  360 + ;

\ Per-authority-key accessor  ( entry idx -- key-addr )
: _XCH-E-KEY  ( e idx -- a )  32 * SWAP _XCH-E-KEYS + ;

\ ====================================================================
\  3. Registry lookup
\ ====================================================================

: _XCH-FIND  ( chain-id -- entry | 0 )
    _XCH-COUNT @ 0 ?DO
        DUP  I _XCH-ENTRY-SZ * _XCH-REG + @ = IF
            DROP  I _XCH-ENTRY-SZ * _XCH-REG +
            UNLOOP EXIT
        THEN
    LOOP  DROP 0 ;

\ ====================================================================
\  4. Registry management
\ ====================================================================

: XCH-INIT  ( -- )
    _XCH-REG _XCH-ENTRY-SZ XCH-MAX-CHAINS * 0 FILL
    0 _XCH-COUNT ! ;

: XCH-REGISTER  ( chain-id con-mode -- fault )
    OVER _XCH-FIND IF  2DROP XCH-OK EXIT  THEN
    _XCH-COUNT @ XCH-MAX-CHAINS >= IF  2DROP XCH-ERR-FULL EXIT  THEN
    _XCH-COUNT @ _XCH-ENTRY-SZ * _XCH-REG +
    DUP _XCH-ENTRY-SZ 0 FILL
    >R
    R@ _XCH-E-MODE !
    R@ !
    1 R> _XCH-E-FLAGS !
    1 _XCH-COUNT +!
    XCH-OK ;

VARIABLE _XCH-T1

: XCH-SET-AUTH  ( key-addr chain-id idx -- fault )
    DUP XCH-MAX-AUTH >= IF  DROP 2DROP XCH-ERR-IDX EXIT  THEN
    >R
    _XCH-FIND DUP 0= IF  DROP R> 2DROP XCH-ERR-NOT-FOUND EXIT  THEN
    _XCH-T1 !
    _XCH-T1 @ R@ _XCH-E-KEY  32 CMOVE
    R> 1+  _XCH-T1 @ _XCH-E-NAUTH @  MAX  _XCH-T1 @ _XCH-E-NAUTH !
    XCH-OK ;

: XCH-SET-AIR  ( ver chain-id -- fault )
    _XCH-FIND DUP 0= IF  DROP DROP XCH-ERR-NOT-FOUND EXIT  THEN
    _XCH-E-AIR !
    XCH-OK ;

: XCH-UNREGISTER  ( chain-id -- fault )
    _XCH-FIND DUP 0= IF  DROP XCH-ERR-NOT-FOUND EXIT  THEN
    _XCH-T1 !
    \ Swap last entry into deleted slot, then zero last
    _XCH-COUNT @ 1-  _XCH-ENTRY-SZ * _XCH-REG +
    DUP _XCH-T1 @ <> IF
        _XCH-T1 @ _XCH-ENTRY-SZ CMOVE
    ELSE  DROP  THEN
    _XCH-COUNT @ 1-  _XCH-ENTRY-SZ * _XCH-REG +
    _XCH-ENTRY-SZ 0 FILL
    -1 _XCH-COUNT +!
    XCH-OK ;

\ ====================================================================
\  5. Block header verification helpers
\ ====================================================================

CREATE _XCH-BLK      BLK-STRUCT-SIZE ALLOT
CREATE _XCH-SIGHASH   32 ALLOT
CREATE _XCH-BLKHASH   32 ALLOT

VARIABLE _XCH-SH-BLK
VARIABLE _XCH-SH-DST

\ _XCH-SIG-HASH ( blk hash -- )
\   Hash header with proof_len temporarily zeroed.
\   Produces the message the block sealer signed.
: _XCH-SIG-HASH  ( blk hash -- )
    _XCH-SH-DST !  _XCH-SH-BLK !
    _XCH-SH-BLK @ _BLK-OFF-PLEN + C@
    0 _XCH-SH-BLK @ _BLK-OFF-PLEN + C!
    _XCH-SH-BLK @ _XCH-SH-DST @ BLK-HASH
    _XCH-SH-BLK @ _BLK-OFF-PLEN + C! ;

VARIABLE _XCH-VP-BLK

\ _XCH-POA-SIG? ( blk -- flag )
\   Verify Ed25519 signature in PoA/PoSA proof.
\   Proof layout: [0..31]=pubkey, [32..95]=signature.
: _XCH-POA-SIG?  ( blk -- flag )
    _XCH-VP-BLK !
    _XCH-VP-BLK @ _XCH-SIGHASH _XCH-SIG-HASH
    _XCH-SIGHASH 32
    _XCH-VP-BLK @ _BLK-OFF-PROOF +
    DUP 32 +
    ED25519-VERIFY ;

VARIABLE _XCH-CA-PUB
VARIABLE _XCH-CA-E

\ _XCH-IN-AUTH? ( pub-addr entry -- flag )
\   Check if pubkey is in entry's authority table.
: _XCH-IN-AUTH?  ( pub entry -- flag )
    _XCH-CA-E !  _XCH-CA-PUB !
    _XCH-CA-E @ _XCH-E-NAUTH @ 0 ?DO
        _XCH-CA-PUB @ 32
        _XCH-CA-E @ I _XCH-E-KEY 32
        COMPARE 0= IF  UNLOOP TRUE EXIT  THEN
    LOOP  FALSE ;

\ ====================================================================
\  6. XCH-SUBMIT-HEADER — verify + store foreign block header
\ ====================================================================
\
\  Accepts a CBOR-encoded foreign block (header + empty txs array).
\  Decodes, verifies consensus signature, checks height/prev_hash
\  sequence, updates registry with new state root and block hash.
\
\  Input: CBOR from BLK-ENCODE with empty txs: [header-map, []]

: XCH-SUBMIT-HEADER  ( buf len chain-id -- fault )
    >R
    \ 1. Decode into temp block struct
    _XCH-BLK BLK-INIT
    _XCH-BLK BLK-DECODE 0= IF  R> DROP XCH-ERR-DECODE EXIT  THEN

    \ 2. Lookup chain in registry
    R> _XCH-FIND DUP 0= IF  DROP XCH-ERR-NOT-FOUND EXIT  THEN
    _XCH-T1 !

    \ 3. Sequence check (skip for first header)
    _XCH-T1 @ _XCH-E-FLAGS @ 2 AND IF
        _XCH-T1 @ _XCH-E-HGT @ 1+
        _XCH-BLK BLK-HEIGHT@ <> IF  XCH-ERR-HEIGHT EXIT  THEN
        _XCH-BLK BLK-PREV-HASH@ 32
        _XCH-T1 @ _XCH-E-HASH 32
        COMPARE 0<> IF  XCH-ERR-PREV EXIT  THEN
    THEN

    \ 4. Consensus proof verification
    _XCH-T1 @ _XCH-E-MODE @
    DUP 1 = SWAP 3 = OR IF
        \ PoA (1) or PoSA (3): proof = [pub32 || sig64]
        _XCH-BLK _BLK-OFF-PLEN + C@ 96 < IF  XCH-ERR-SIG EXIT  THEN
        _XCH-BLK _XCH-POA-SIG? 0= IF  XCH-ERR-SIG EXIT  THEN
        _XCH-BLK _BLK-OFF-PROOF +
        _XCH-T1 @
        _XCH-IN-AUTH? 0= IF  XCH-ERR-AUTH EXIT  THEN
    ELSE
        XCH-ERR-MODE EXIT
    THEN

    \ 5. Update registry
    _XCH-BLK BLK-HEIGHT@  _XCH-T1 @ _XCH-E-HGT !
    _XCH-BLK _XCH-BLKHASH BLK-HASH
    _XCH-BLKHASH  _XCH-T1 @ _XCH-E-HASH  32 CMOVE
    _XCH-BLK BLK-STATE-ROOT@  _XCH-T1 @ _XCH-E-ROOT  32 CMOVE
    _XCH-T1 @ _XCH-E-FLAGS @  2 OR  _XCH-T1 @ _XCH-E-FLAGS !
    XCH-OK ;

\ ====================================================================
\  7. State proof verification
\ ====================================================================
\
\  Stateless SMT verification against last verified foreign root.
\  key = 32B account address, val = 32B SHA3-256 of account entry,
\  proof = SMT proof entries, len = proof entry count.

: XCH-VERIFY-STATE  ( key val proof len chain-id -- flag )
    _XCH-FIND DUP 0= IF
        DROP 2DROP 2DROP FALSE EXIT
    THEN
    DUP _XCH-E-FLAGS @ 2 AND 0= IF
        DROP 2DROP 2DROP FALSE EXIT
    THEN
    _XCH-E-ROOT
    SMT-VERIFY ;

\ ====================================================================
\  8. Query words
\ ====================================================================

: XCH-CHAIN-COUNT  ( -- n )  _XCH-COUNT @ ;

: XCH-HEIGHT  ( chain-id -- n | -1 )
    _XCH-FIND DUP 0= IF  DROP -1 EXIT  THEN
    DUP _XCH-E-FLAGS @ 2 AND 0= IF  DROP -1 EXIT  THEN
    _XCH-E-HGT @ ;

: XCH-STATE-ROOT  ( chain-id -- addr | 0 )
    _XCH-FIND DUP 0= IF  EXIT  THEN
    DUP _XCH-E-FLAGS @ 2 AND 0= IF  DROP 0 EXIT  THEN
    _XCH-E-ROOT ;

: XCH-CHAIN-INFO  ( chain-id -- con-mode air height | 0 0 -1 )
    _XCH-FIND DUP 0= IF  DROP 0 0 -1 EXIT  THEN
    DUP _XCH-E-MODE @
    OVER _XCH-E-AIR @
    ROT DUP _XCH-E-FLAGS @ 2 AND IF
        _XCH-E-HGT @
    ELSE
        DROP -1
    THEN ;

\ ====================================================================
\  9. Concurrency Guard
\ ====================================================================

GUARD _xch-guard

' XCH-INIT           CONSTANT _xch-init-xt
' XCH-REGISTER       CONSTANT _xch-reg-xt
' XCH-SET-AUTH       CONSTANT _xch-sa-xt
' XCH-SET-AIR        CONSTANT _xch-sai-xt
' XCH-UNREGISTER     CONSTANT _xch-ur-xt
' XCH-SUBMIT-HEADER  CONSTANT _xch-sh-xt
' XCH-VERIFY-STATE   CONSTANT _xch-vs-xt
' XCH-CHAIN-COUNT    CONSTANT _xch-cc-xt
' XCH-HEIGHT         CONSTANT _xch-hgt-xt
' XCH-STATE-ROOT     CONSTANT _xch-sr-xt
' XCH-CHAIN-INFO     CONSTANT _xch-ci-xt

: XCH-INIT           _xch-init-xt  _xch-guard WITH-GUARD ;
: XCH-REGISTER       _xch-reg-xt   _xch-guard WITH-GUARD ;
: XCH-SET-AUTH       _xch-sa-xt    _xch-guard WITH-GUARD ;
: XCH-SET-AIR        _xch-sai-xt   _xch-guard WITH-GUARD ;
: XCH-UNREGISTER     _xch-ur-xt    _xch-guard WITH-GUARD ;
: XCH-SUBMIT-HEADER  _xch-sh-xt    _xch-guard WITH-GUARD ;
: XCH-VERIFY-STATE   _xch-vs-xt    _xch-guard WITH-GUARD ;
: XCH-CHAIN-COUNT    _xch-cc-xt    _xch-guard WITH-GUARD ;
: XCH-HEIGHT         _xch-hgt-xt   _xch-guard WITH-GUARD ;
: XCH-STATE-ROOT     _xch-sr-xt    _xch-guard WITH-GUARD ;
: XCH-CHAIN-INFO     _xch-ci-xt    _xch-guard WITH-GUARD ;
