\ =================================================================
\  genesis.f  —  Genesis Block Configuration
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: GEN-  / _GEN-
\  Depends on: block.f state.f consensus.f cbor.f sha3.f
\
\  The genesis block (height 0) carries chain configuration as a
\  CBOR-encoded payload in its tx data area.  This parameterizes
\  the consensus module and initial state at chain creation time.
\
\  Genesis CBOR layout (map with 8 entries):
\    "chain_id"    → uint         (chain identifier)
\    "con_mode"    → uint         (consensus mode: 0-3)
\    "stark"       → uint         (0=off, 1=on)
\    "epoch_len"   → uint         (PoS/PoSA epoch length in blocks)
\    "min_stake"   → uint         (minimum stake to qualify)
\    "lock_period" → uint         (unstake lock period in blocks)
\    "authorities" → array[bstr]  (PoA/PoSA authority pubkeys, 32B each)
\    "balances"    → array[       (initial account balances)
\                      array[bstr, uint]  (address, amount) pairs
\                    ]
\
\  Public API:
\   GEN-CREATE  ( -- )        encode genesis from current config
\   GEN-LOAD    ( -- flag )   decode genesis and configure chain
\   GEN-CHAIN-ID@ ( -- n )    return chain ID
\   GEN-HASH    ( hash -- )   compute genesis block hash
\
\  Not reentrant (uses module-level buffers).
\ =================================================================

REQUIRE block.f
REQUIRE state.f
REQUIRE ../consensus/consensus.f
REQUIRE ../cbor/cbor.f
REQUIRE ../math/sha3.f

PROVIDED akashic-genesis

\ =====================================================================
\  1. Chain ID
\ =====================================================================

VARIABLE _GEN-CHAIN-ID
1 _GEN-CHAIN-ID !                  \ default chain ID

: GEN-CHAIN-ID!  ( n -- )  _GEN-CHAIN-ID ! ;
: GEN-CHAIN-ID@  ( -- n )  _GEN-CHAIN-ID @ ;

\ =====================================================================
\  2. Genesis CBOR encoding buffer
\ =====================================================================
\  16 KB buffer for genesis payload.  Supports up to ~400 initial
\  accounts + 256 authority keys without overflow.

16384 CONSTANT _GEN-BUF-SIZE
CREATE _GEN-BUF  _GEN-BUF-SIZE ALLOT

\ String constants (stored as counted-string-like inline data)
CREATE _GEN-S-CID       8 C, CHAR c C, CHAR h C, CHAR a C, CHAR i C,
                            CHAR n C, CHAR _ C, CHAR i C, CHAR d C,
CREATE _GEN-S-CMOD      8 C, CHAR c C, CHAR o C, CHAR n C, CHAR _ C,
                            CHAR m C, CHAR o C, CHAR d C, CHAR e C,
CREATE _GEN-S-STARK     5 C, CHAR s C, CHAR t C, CHAR a C, CHAR r C,
                            CHAR k C,
CREATE _GEN-S-EPOCH     9 C, CHAR e C, CHAR p C, CHAR o C, CHAR c C,
                            CHAR h C, CHAR _ C, CHAR l C, CHAR e C,
                            CHAR n C,
CREATE _GEN-S-MSTK      9 C, CHAR m C, CHAR i C, CHAR n C, CHAR _ C,
                            CHAR s C, CHAR t C, CHAR a C, CHAR k C,
                            CHAR e C,
CREATE _GEN-S-LOCK      11 C, CHAR l C, CHAR o C, CHAR c C, CHAR k C,
                            CHAR _ C, CHAR p C, CHAR e C, CHAR r C,
                            CHAR i C, CHAR o C, CHAR d C,
CREATE _GEN-S-AUTH      11 C, CHAR a C, CHAR u C, CHAR t C, CHAR h C,
                            CHAR o C, CHAR r C, CHAR i C, CHAR t C,
                            CHAR i C, CHAR e C, CHAR s C,
CREATE _GEN-S-BAL       8 C, CHAR b C, CHAR a C, CHAR l C, CHAR a C,
                            CHAR n C, CHAR c C, CHAR e C, CHAR s C,

\ Helper: emit counted string as CBOR text
: _GEN-TSTR  ( counted-str -- )
    DUP C@ SWAP 1+ SWAP CBOR-TSTR ;

\ =====================================================================
\  3. GEN-CREATE — encode current configuration as genesis CBOR
\ =====================================================================
\  Reads from CON-MODE@, CON-STARK?, CON-POA-COUNT, etc.
\  Stores result in _GEN-BUF.

VARIABLE _GEN-I

: GEN-CREATE  ( -- )
    _GEN-BUF _GEN-BUF-SIZE CBOR-RESET
    8 CBOR-MAP                     \ 8 key-value pairs
    \ 1. chain_id
    _GEN-S-CID _GEN-TSTR
    _GEN-CHAIN-ID @ CBOR-UINT
    \ 2. con_mode
    _GEN-S-CMOD _GEN-TSTR
    CON-MODE@ CBOR-UINT
    \ 3. stark
    _GEN-S-STARK _GEN-TSTR
    CON-STARK? IF 1 ELSE 0 THEN CBOR-UINT
    \ 4. epoch_len
    _GEN-S-EPOCH _GEN-TSTR
    CON-POS-EPOCH-LEN CBOR-UINT
    \ 5. min_stake
    _GEN-S-MSTK _GEN-TSTR
    CON-POS-MIN-STAKE CBOR-UINT
    \ 6. lock_period
    _GEN-S-LOCK _GEN-TSTR
    CON-POS-LOCK-PERIOD CBOR-UINT
    \ 7. authorities — array of 32-byte pubkeys
    _GEN-S-AUTH _GEN-TSTR
    CON-POA-COUNT CBOR-ARRAY
    CON-POA-COUNT 0 ?DO
        I 32 * _CON-POA-KEYS + 32 CBOR-BSTR
    LOOP
    \ 8. balances — array of [addr, amount] pairs
    _GEN-S-BAL _GEN-TSTR
    ST-COUNT CBOR-ARRAY
    ST-COUNT 0 ?DO
        2 CBOR-ARRAY              \ each entry is [addr, amount]
        I _ST-ENTRY 32 CBOR-BSTR
        I _ST-ENTRY _ST-OFF-BAL + @ CBOR-UINT
    LOOP ;

\ GEN-RESULT ( -- addr len )  Return encoded genesis payload.
: GEN-RESULT  ( -- addr len )  CBOR-RESULT ;

\ =====================================================================
\  4. GEN-LOAD — decode genesis CBOR and configure consensus + state
\ =====================================================================
\  Called once at node startup.  Reads the genesis block's data field
\  and applies all configuration.  Returns -1 on success, 0 on error.

VARIABLE _GEN-NKEYS
VARIABLE _GEN-NBAL
CREATE _GEN-TKEY 32 ALLOT          \ temp key buffer for decode

\ _GEN-STR= ( addr1 len1 addr2 len2 -- flag )
\   Compare two byte strings for equality.
: _GEN-STR=  ( addr1 len1 addr2 len2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN  \ lengths differ
    0 ?DO
        OVER I + C@  OVER I + C@  <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ _GEN-EXPECT-KEY ( counted-str -- flag )
\   Read next CBOR text string and validate it matches the expected
\   key name.  Returns -1 on match, 0 on mismatch.
: _GEN-EXPECT-KEY  ( counted-str -- flag )
    DUP 1+ SWAP C@                 ( str-body len )
    CBOR-NEXT-TSTR                 ( str-body len cbor-addr cbor-len )
    _GEN-STR= ;

: GEN-LOAD  ( genesis-data len -- flag )
    CBOR-PARSE DROP
    \ Expect map with 8 entries
    CBOR-NEXT-MAP 8 <> IF 0 EXIT THEN
    \ 1. chain_id
    _GEN-S-CID _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT _GEN-CHAIN-ID !
    \ 2. con_mode
    _GEN-S-CMOD _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT CON-MODE!
    \ 3. stark
    _GEN-S-STARK _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT 0<> CON-STARK!
    \ 4. epoch_len — apply from genesis (runtime-configurable)
    _GEN-S-EPOCH _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT CON-POS-EPOCH-LEN !
    \ 5. min_stake — apply from genesis (runtime-configurable)
    _GEN-S-MSTK _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT CON-POS-MIN-STAKE !
    \ 6. lock_period
    _GEN-S-LOCK _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT _ST-LOCK-PERIOD !
    \ 7. authorities
    _GEN-S-AUTH _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-ARRAY _GEN-NKEYS !
    _GEN-NKEYS @ 0 ?DO
        CBOR-NEXT-BSTR             ( addr len )
        32 <> IF DROP 0 UNLOOP EXIT THEN  \ bad key length
        _GEN-TKEY 32 CMOVE
        _GEN-TKEY CON-POA-ADD
    LOOP
    \ 8. balances
    _GEN-S-BAL _GEN-EXPECT-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-ARRAY _GEN-NBAL !
    _GEN-NBAL @ 0 ?DO
        CBOR-NEXT-ARRAY 2 <> IF 0 UNLOOP EXIT THEN
        CBOR-NEXT-BSTR             ( addr len )
        32 <> IF DROP 0 UNLOOP EXIT THEN
        _GEN-TKEY 32 CMOVE
        CBOR-NEXT-UINT             ( amount )
        \ Create account with initial balance
        _GEN-TKEY SWAP ST-CREATE
        0= IF 0 UNLOOP EXIT THEN  \ account creation failed
    LOOP
    -1 ;

\ =====================================================================
\  5. GEN-HASH — compute genesis block hash
\ =====================================================================

CREATE _GEN-BLK  BLK-STRUCT-SIZE ALLOT

: GEN-HASH  ( hash -- )
    >R
    _GEN-BLK BLK-INIT
    0 _GEN-BLK BLK-SET-HEIGHT
    \ prev_hash = all zeros (already zero from BLK-INIT)
    0 _GEN-BLK BLK-SET-TIME
    \ Include state root — two chains with different initial balances
    \ must produce different genesis hashes.  (Fix P24)
    ST-ROOT IF
        _GEN-BLK BLK-STATE-ROOT@ 32 CMOVE
    ELSE
        DROP  \ ST-ROOT returned 0 (empty state, no root)
    THEN
    _GEN-BLK R> BLK-HASH ;

\ =====================================================================
\  Done — genesis configuration for chain bootstrapping.
\ =====================================================================

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _gen-guard

' GEN-CHAIN-ID!   CONSTANT _gen-chain-id-s-xt
' GEN-CHAIN-ID@   CONSTANT _gen-chain-id-at-xt
' GEN-CREATE      CONSTANT _gen-create-xt
' GEN-RESULT      CONSTANT _gen-result-xt
' GEN-LOAD        CONSTANT _gen-load-xt
' GEN-HASH        CONSTANT _gen-hash-xt

: GEN-CHAIN-ID!   _gen-chain-id-s-xt _gen-guard WITH-GUARD ;
: GEN-CHAIN-ID@   _gen-chain-id-at-xt _gen-guard WITH-GUARD ;
: GEN-CREATE      _gen-create-xt _gen-guard WITH-GUARD ;
: GEN-RESULT      _gen-result-xt _gen-guard WITH-GUARD ;
: GEN-LOAD        _gen-load-xt _gen-guard WITH-GUARD ;
: GEN-HASH        _gen-hash-xt _gen-guard WITH-GUARD ;
[THEN] [THEN]
