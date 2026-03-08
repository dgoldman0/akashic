\ =================================================================
\  sphincs-plus.f  —  SLH-DSA-SHAKE-128s  (FIPS 205)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SPX-
\  Depends on: sha3.f random.f
\
\  Post-quantum digital signatures using only hash functions.
\  Instantiation: SPHINCS+-SHAKE-128s (NIST security level 1).
\  All hashing via hardware-accelerated SHAKE-256.
\
\  Public API:
\   SPX-KEYGEN        ( seed pub sec -- )   keypair from 48-byte seed
\   SPX-KEYGEN-RANDOM ( pub sec -- )        keypair from system RNG
\   SPX-SIGN          ( msg len sec sig -- ) sign -> 7856-byte sig
\   SPX-VERIFY        ( msg len pub sig sig-len -- flag ) verify signature
\
\  Constants:
\   SPX-N             ( -- 16 )     security parameter (bytes)
\   SPX-SIG-LEN       ( -- 7856 )   signature length
\   SPX-PK-LEN        ( -- 32 )     public key length
\   SPX-SK-LEN        ( -- 64 )     secret key length
\   SPX-SIGN-MODE     variable      0=random (default) 1=deterministic
\   SPX-MODE-RANDOM        ( -- 0 )
\   SPX-MODE-DETERMINISTIC ( -- 1 )
\
\  BIOS primitives used:
\   SHA3-MODE! SHA3-INIT SHA3-UPDATE SHA3-FINAL
\   SHAKE256-MODE SHA3-256-MODE
\   RANDOM8
\
\  IMPORTANT: In standard Forth, DO..LOOP pushes to the return stack.
\  Therefore R@ inside DO..LOOP returns loop index, NOT a saved value.
\  All words use VARIABLEs for parameter passing instead of >R/R@.
\
\  Not reentrant.
\ =================================================================

REQUIRE sha3.f
REQUIRE random.f

PROVIDED akashic-sphincs-plus

\ =====================================================================
\  1. Constants
\ =====================================================================

16  CONSTANT SPX-N
63  CONSTANT _SPX-H
7   CONSTANT _SPX-D
9   CONSTANT _SPX-HP
12  CONSTANT _SPX-A
14  CONSTANT _SPX-K
16  CONSTANT _SPX-W
32  CONSTANT _SPX-LEN1
3   CONSTANT _SPX-LEN2
35  CONSTANT _SPX-LEN
560 CONSTANT _SPX-WLEN
7856 CONSTANT SPX-SIG-LEN
32   CONSTANT SPX-PK-LEN
64   CONSTANT SPX-SK-LEN
16   CONSTANT _SPX-SIG-FORS
2912 CONSTANT _SPX-SIG-FORS-SZ
704  CONSTANT _SPX-HT-LAYER-SZ
30   CONSTANT _SPX-MD-LEN

0 CONSTANT _SPX-T-WOTS-HASH
1 CONSTANT _SPX-T-WOTS-PK
2 CONSTANT _SPX-T-TREE
3 CONSTANT _SPX-T-FORS-TREE
4 CONSTANT _SPX-T-FORS-ROOTS
5 CONSTANT _SPX-T-WOTS-PRF
6 CONSTANT _SPX-T-FORS-PRF

\ FORS: each tree has 2^a = 4096 leaves.  k=14 trees.
\ Sig_FORS entry = n + a*n = 16 + 192 = 208 bytes.
208 CONSTANT _SPX-FORS-ENTRY

\ =====================================================================
\  2. Signing mode
\ =====================================================================

VARIABLE SPX-SIGN-MODE
0 CONSTANT SPX-MODE-RANDOM
1 CONSTANT SPX-MODE-DETERMINISTIC
SPX-MODE-RANDOM SPX-SIGN-MODE !

\ =====================================================================
\  3. Buffers
\ =====================================================================

CREATE _SPX-ADRS     32 ALLOT   _SPX-ADRS  32 0 FILL
CREATE _SPX-HASH-BUF 32 ALLOT
CREATE _SPX-DIGEST   32 ALLOT
CREATE _SPX-WOTS-MSG 40 ALLOT
CREATE _SPX-NODE     16 ALLOT
CREATE _SPX-NODE2    16 ALLOT
CREATE _SPX-FORS-RTS 224 ALLOT
CREATE _SPX-WOTS-BUF 560 ALLOT
CREATE _SPX-OPT-RAND 16 ALLOT
CREATE _SPX-RNG-SEED 48 ALLOT

\ Treehash stack: 13 entries max, entry = 16 bytes hash + 8 bytes height
CREATE _SPX-TH-STK   312 ALLOT
VARIABLE _SPX-TH-SP

\ =====================================================================
\  4. Variables for parameter passing
\ =====================================================================
\  In Forth, DO..LOOP clobbers the return stack, making R@ unsafe.
\  All complex words use VARIABLEs instead.

\ Key material pointers
VARIABLE _SPX-PK-SEED
VARIABLE _SPX-SK-SEED
VARIABLE _SPX-SK-PRF
VARIABLE _SPX-PK-ROOT

\ Message / signature
VARIABLE _SPX-MSG-PTR
VARIABLE _SPX-MSG-LEN
VARIABLE _SPX-SIG-PTR

\ Per-word working variables
VARIABLE _SPX-XMSS-IDX
VARIABLE _SPX-FORS-KP
VARIABLE _SPX-FORS-BASE
VARIABLE _SPX-HT-TREE
VARIABLE _SPX-HT-LEAF
VARIABLE _SPX-CUR-MSG
VARIABLE _SPX-CUR-FIDX

\ Variables replacing >R/R@ inside DO..LOOP
VARIABLE _SPX-V-CHAIN-DST
VARIABLE _SPX-V-WSIG-OUT
VARIABLE _SPX-V-XNODE-HT
VARIABLE _SPX-V-XSIG-OUT
VARIABLE _SPX-V-FNODE-HT
VARIABLE _SPX-V-FSIG-OUT
VARIABLE _SPX-V-HTSIG-OUT
VARIABLE _SPX-V-HTVER-ROOT

VARIABLE _SPX-KG-PUB
VARIABLE _SPX-KG-SEC

\ =====================================================================
\  5. Big-endian helpers
\ =====================================================================

: _SPX-BE32!  ( u addr -- )
    >R
    DUP 24 RSHIFT        R@ C!
    DUP 16 RSHIFT 255 AND R@ 1+ C!
    DUP  8 RSHIFT 255 AND R@ 2 + C!
    255 AND               R> 3 + C! ;

: _SPX-BE64!  ( u addr -- )
    >R
    DUP 56 RSHIFT        R@ C!
    DUP 48 RSHIFT 255 AND R@ 1+ C!
    DUP 40 RSHIFT 255 AND R@ 2 + C!
    DUP 32 RSHIFT 255 AND R@ 3 + C!
    DUP 24 RSHIFT 255 AND R@ 4 + C!
    DUP 16 RSHIFT 255 AND R@ 5 + C!
    DUP  8 RSHIFT 255 AND R@ 6 + C!
    255 AND               R> 7 + C! ;

: _SPX-BE24@  ( addr -- u )
    DUP C@ 16 LSHIFT
    OVER 1+ C@ 8 LSHIFT OR
    SWAP 2 + C@ OR ;

: _SPX-BE16@  ( addr -- u )
    DUP C@ 8 LSHIFT SWAP 1+ C@ OR ;

\ =====================================================================
\  6. ADRS manipulation
\ =====================================================================
\  ADRS is 32 bytes big-endian:
\    0-3:  layer (u32)    4-11: tree (u64)   12-15: zero
\   16-19: type (u32)    20-23: kp/pad (u32)
\   24-27: chain/height (u32)  28-31: hash/index (u32)
\
\  NOTE: _SPX-ADRS-TYPE! does NOT auto-clear bytes 20-31.
\  Callers must explicitly set kp-addr, chain, hash after changing type.

: _SPX-ADRS-ZERO     ( -- )  _SPX-ADRS 32 0 FILL ;
: _SPX-ADRS-LAYER!   ( u -- ) _SPX-ADRS      _SPX-BE32! ;
: _SPX-ADRS-TREE!    ( u -- ) _SPX-ADRS 4 +  _SPX-BE64!
                               0 _SPX-ADRS 12 + _SPX-BE32! ;
: _SPX-ADRS-TYPE!    ( u -- ) _SPX-ADRS 16 + _SPX-BE32! ;
: _SPX-ADRS-KP!      ( u -- ) _SPX-ADRS 20 + _SPX-BE32! ;
: _SPX-ADRS-CHAIN!   ( u -- ) _SPX-ADRS 24 + _SPX-BE32! ;
: _SPX-ADRS-HASH!    ( u -- ) _SPX-ADRS 28 + _SPX-BE32! ;
: _SPX-ADRS-HEIGHT!  ( u -- ) _SPX-ADRS 24 + _SPX-BE32! ;
: _SPX-ADRS-INDEX!   ( u -- ) _SPX-ADRS 28 + _SPX-BE32! ;

\ =====================================================================
\  7. Core SHAKE-256 hash functions
\ =====================================================================
\  SHA3-FINAL always writes 32 bytes.  We need n=16.
\  _SPX-SQUEEZE-N squeezes into 32-byte temp, copies n to dst.

: _SPX-SQUEEZE-N  ( dst -- )
    _SPX-HASH-BUF SHA3-FINAL
    SHA3-256-MODE SHA3-MODE!
    _SPX-HASH-BUF SWAP SPX-N CMOVE ;

\ T_1(PK.seed, ADRS, in) -> dst.  in is n bytes.
: _SPX-T1  ( in dst -- )
    >R
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    _SPX-PK-SEED @ SPX-N SHA3-UPDATE
    _SPX-ADRS 32 SHA3-UPDATE
    SPX-N SHA3-UPDATE
    R> _SPX-SQUEEZE-N ;

\ T_1 in-place: hash buf, result back into buf.
: _SPX-T1!  ( buf -- )
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    _SPX-PK-SEED @ SPX-N SHA3-UPDATE
    _SPX-ADRS 32 SHA3-UPDATE
    DUP SPX-N SHA3-UPDATE
    _SPX-SQUEEZE-N ;

\ T_2(PK.seed, ADRS, left||right) -> dst.  Each is n bytes.
: _SPX-T2  ( left right dst -- )
    >R >R
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    _SPX-PK-SEED @ SPX-N SHA3-UPDATE
    _SPX-ADRS 32 SHA3-UPDATE
    SPX-N SHA3-UPDATE
    R> SPX-N SHA3-UPDATE
    R> _SPX-SQUEEZE-N ;

\ T_len(PK.seed, ADRS, buf) -> dst.  buf has len*n bytes.
: _SPX-T-LEN  ( buf dst -- )
    >R
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    _SPX-PK-SEED @ SPX-N SHA3-UPDATE
    _SPX-ADRS 32 SHA3-UPDATE
    _SPX-LEN SPX-N * SHA3-UPDATE
    R> _SPX-SQUEEZE-N ;

\ T_k(PK.seed, ADRS, buf) -> dst.  buf has k*n bytes.
: _SPX-T-K  ( buf dst -- )
    >R
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    _SPX-PK-SEED @ SPX-N SHA3-UPDATE
    _SPX-ADRS 32 SHA3-UPDATE
    _SPX-K SPX-N * SHA3-UPDATE
    R> _SPX-SQUEEZE-N ;

\ PRF(PK.seed, ADRS, SK.seed) -> dst
: _SPX-PRF  ( dst -- )
    >R
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    _SPX-PK-SEED @ SPX-N SHA3-UPDATE
    _SPX-ADRS 32 SHA3-UPDATE
    _SPX-SK-SEED @ SPX-N SHA3-UPDATE
    R> _SPX-SQUEEZE-N ;

\ PRF_msg(SK.prf, opt_rand, M) -> dst
: _SPX-PRF-MSG  ( dst -- )
    >R
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    _SPX-SK-PRF @ SPX-N SHA3-UPDATE
    _SPX-OPT-RAND SPX-N SHA3-UPDATE
    _SPX-MSG-PTR @ _SPX-MSG-LEN @ SHA3-UPDATE
    R> _SPX-SQUEEZE-N ;

\ H_msg(R, PK.seed, PK.root, M) -> _SPX-DIGEST (30 bytes needed)
\ SHA3-FINAL gives 32 bytes -- first 30 are the message digest.
: _SPX-H-MSG  ( R-addr -- )
    SHAKE256-MODE SHA3-MODE! SHA3-INIT
    SPX-N SHA3-UPDATE
    _SPX-PK-SEED @ SPX-N SHA3-UPDATE
    _SPX-PK-ROOT @ SPX-N SHA3-UPDATE
    _SPX-MSG-PTR @ _SPX-MSG-LEN @ SHA3-UPDATE
    _SPX-DIGEST SHA3-FINAL
    SHA3-256-MODE SHA3-MODE! ;

\ =====================================================================
\  8. Digest index extraction
\ =====================================================================

\ Extract 12-bit FORS index i (0..k-1) from _SPX-DIGEST.
: _SPX-FORS-IDX  ( i -- idx )
    12 *                              \ bit offset
    8 /MOD SWAP                       ( byte-off bit-off-within-byte )
    >R _SPX-DIGEST + _SPX-BE24@      \ read 3 bytes big-endian
    12 R> - RSHIFT 4095 AND ;

\ Extract 54-bit tree index from digest bytes 21..27 (7 bytes).
: _SPX-TREE-IDX  ( -- idx )
    0
    7 0 DO
        8 LSHIFT
        _SPX-DIGEST 21 + I + C@ OR
    LOOP
    0x003FFFFFFFFFFFFF AND ;

\ Extract 9-bit leaf index from digest bytes 28..29.
: _SPX-LEAF-IDX  ( -- idx )
    _SPX-DIGEST 28 + _SPX-BE16@ 511 AND ;

\ =====================================================================
\  9. base_w encoding + WOTS+ checksum
\ =====================================================================

\ Encode n-byte buffer as 2n base-16 digits -> _SPX-WOTS-MSG[0..31].
: _SPX-BASE-W  ( src count -- )
    0 DO
        I 2/ OVER + C@
        I 1 AND IF 15 AND
        ELSE 4 RSHIFT THEN
        _SPX-WOTS-MSG I + C!
    LOOP DROP ;

\ Compute checksum of _SPX-WOTS-MSG[0..31], append 3 nibbles at [32..34].
: _SPX-WOTS-CSUM  ( -- )
    0
    _SPX-LEN1 0 DO
        15 _SPX-WOTS-MSG I + C@ - +
    LOOP
    \ Nibble extraction: 3 base-16 digits from raw checksum.
    \ Max csum = 32*15 = 480 = 0x1E0, fits in 12 bits (3 nibbles).
    \ NOTE: no left-shift — we extract directly from the integer
    \ at shifts 8/4/0 rather than going through byte encoding.
    DUP  8 RSHIFT 15 AND _SPX-WOTS-MSG 32 + C!
    DUP  4 RSHIFT 15 AND _SPX-WOTS-MSG 33 + C!
    15 AND                _SPX-WOTS-MSG 34 + C! ;

\ Full encode: base-w(hash, 32) then append checksum.
: _SPX-WOTS-ENCODE  ( hash-addr -- )
    _SPX-LEN1 _SPX-BASE-W
    _SPX-WOTS-CSUM ;

\ =====================================================================
\  10. WOTS+ operations
\ =====================================================================

\ Chain: copy src -> dst, iterate T_1! from step s for c steps.
\ ADRS must have type=WOTS_HASH, chain# already set.
\ Uses _SPX-V-CHAIN-DST variable (safe inside DO..LOOP).
: _SPX-CHAIN  ( src start steps dst -- )
    _SPX-V-CHAIN-DST !
    OVER + SWAP                       ( src end start )
    ROT _SPX-V-CHAIN-DST @ SPX-N CMOVE  ( end start )
    ?DO
        I _SPX-ADRS-HASH!
        _SPX-V-CHAIN-DST @ _SPX-T1!
    LOOP ;

\ Generate WOTS+ secret for chain i -> dst.
\ Briefly switches ADRS to WOTS_PRF, then back to WOTS_HASH.
: _SPX-WOTS-SK-I  ( i dst -- )
    >R
    _SPX-T-WOTS-PRF _SPX-ADRS-TYPE!
    DUP _SPX-ADRS-CHAIN!
    0 _SPX-ADRS-HASH!
    R> _SPX-PRF
    _SPX-T-WOTS-HASH _SPX-ADRS-TYPE! ;

\ WOTS+ sign msg-hash -> sig-out (len*n = 560 bytes).
\ ADRS must have layer, tree, kp set by caller.
: _SPX-WOTS-SIGN  ( msg-hash sig-out -- )
    _SPX-V-WSIG-OUT !
    _SPX-WOTS-ENCODE
    _SPX-LEN 0 DO
        I _SPX-ADRS-CHAIN!
        I _SPX-NODE _SPX-WOTS-SK-I
        _SPX-NODE 0 _SPX-WOTS-MSG I + C@
        _SPX-V-WSIG-OUT @ I SPX-N * +
        _SPX-CHAIN
    LOOP ;

\ WOTS+ pk from sig: recover compressed pk -> dst.
\ ADRS must have layer, tree, kp set by caller.
: _SPX-WOTS-PK-FROM-SIG  ( msg-hash sig-in dst -- )
    >R SWAP
    _SPX-WOTS-ENCODE                  ( sig-in  R: dst )
    _SPX-LEN 0 DO
        I _SPX-ADRS-CHAIN!
        DUP I SPX-N * +              \ sig[i]
        _SPX-WOTS-MSG I + C@         \ start
        DUP _SPX-W 1- SWAP -         \ steps = w-1 - start
        _SPX-WOTS-BUF I SPX-N * +    \ buf[i]
        _SPX-CHAIN
    LOOP
    DROP
    _SPX-T-WOTS-PK _SPX-ADRS-TYPE!
    _SPX-WOTS-BUF R> _SPX-T-LEN ;

\ =====================================================================
\  11. Treehash (iterative Merkle tree computation)
\ =====================================================================
\  Stack entry: 24 bytes = 16 bytes hash + 8 bytes height.

: _SPX-TH-RESET  ( -- )  0 _SPX-TH-SP ! ;

: _SPX-TH-PUSH  ( node height -- )
    _SPX-TH-SP @ 24 * _SPX-TH-STK +
    >R
    R@ SPX-N + !
    R> SPX-N CMOVE
    1 _SPX-TH-SP +! ;

: _SPX-TH-TOP-H  ( -- h )
    _SPX-TH-SP @ 0= IF -1 EXIT THEN
    _SPX-TH-SP @ 1- 24 * _SPX-TH-STK + SPX-N + @ ;

: _SPX-TH-POP  ( -- addr )
    -1 _SPX-TH-SP +!
    _SPX-TH-SP @ 24 * _SPX-TH-STK + ;

\ =====================================================================
\  12. XMSS operations
\ =====================================================================

\ Generate WOTS+ public key for leaf idx -> dst.
\ ADRS layer and tree must be set by caller.
: _SPX-WOTS-PK-GEN  ( idx dst -- )
    >R DUP _SPX-ADRS-KP!
    _SPX-T-WOTS-HASH _SPX-ADRS-TYPE!
    _SPX-LEN 0 DO
        I _SPX-ADRS-CHAIN!
        I _SPX-NODE2 _SPX-WOTS-SK-I
        _SPX-NODE2 0 _SPX-W 1-
        _SPX-WOTS-BUF I SPX-N * +
        _SPX-CHAIN
    LOOP
    DROP
    _SPX-T-WOTS-PK _SPX-ADRS-TYPE!
    _SPX-WOTS-BUF R> _SPX-T-LEN ;

\ Compute XMSS subtree root: treehash(start, height) -> dst.
\ ADRS layer/tree must be set by caller.
\ Uses _SPX-V-XNODE-HT for height (safe inside DO..LOOP).
\ dst stays on rstack (only accessed after loop).
: _SPX-XMSS-NODE  ( start height dst -- )
    >R
    _SPX-V-XNODE-HT !
    _SPX-TH-RESET
    DUP 1 _SPX-V-XNODE-HT @ LSHIFT + SWAP  ( end start  R: dst )
    ?DO
        I _SPX-NODE _SPX-WOTS-PK-GEN
        0                             ( cur-h )
        BEGIN
            DUP _SPX-TH-TOP-H =
            OVER _SPX-V-XNODE-HT @ < AND
        WHILE
            _SPX-T-TREE _SPX-ADRS-TYPE!
            DUP 1+ _SPX-ADRS-HEIGHT!
            I OVER 1+ RSHIFT _SPX-ADRS-INDEX!
            _SPX-TH-POP _SPX-NODE _SPX-NODE2 _SPX-T2
            _SPX-NODE2 _SPX-NODE SPX-N CMOVE
            1+
        REPEAT
        _SPX-NODE SWAP _SPX-TH-PUSH
    LOOP
    _SPX-TH-POP R> SPX-N CMOVE ;

\ XMSS sign: sign msg at leaf idx -> sig-out.
\ sig-out = [WOTS-sig: 560B] [auth-path: h'*n = 144B] = 704B total.
\ ADRS layer/tree must be set.
\ Uses _SPX-V-XSIG-OUT for sig-out (safe inside DO..LOOP).
: _SPX-XMSS-SIGN  ( msg idx sig-out -- )
    _SPX-V-XSIG-OUT !
    DUP _SPX-XMSS-IDX !
    _SPX-ADRS-KP!
    _SPX-T-WOTS-HASH _SPX-ADRS-TYPE!
    _SPX-V-XSIG-OUT @ _SPX-WOTS-SIGN
    \ Auth path: h' levels
    _SPX-HP 0 DO
        _SPX-XMSS-IDX @ I RSHIFT 1 XOR  \ sibling index at level I
        1 I LSHIFT *                       \ start leaf
        I                                  \ height
        _SPX-V-XSIG-OUT @ _SPX-WLEN + I SPX-N * +  \ auth[I] dst
        _SPX-XMSS-NODE
    LOOP ;

\ XMSS root from sig: reconstruct Merkle root -> dst.
\ sig-in = [WOTS-sig] [auth-path].
: _SPX-XMSS-ROOT  ( msg idx sig-in dst -- )
    >R >R
    DUP _SPX-XMSS-IDX !
    _SPX-ADRS-KP!
    _SPX-T-WOTS-HASH _SPX-ADRS-TYPE!
    R>                               ( msg sig-in  R: dst )
    SWAP OVER _SPX-NODE _SPX-WOTS-PK-FROM-SIG
    \ Walk Merkle tree using auth path
    _SPX-HP 0 DO
        _SPX-T-TREE _SPX-ADRS-TYPE!
        I 1+ _SPX-ADRS-HEIGHT!
        _SPX-XMSS-IDX @ I 1+ RSHIFT _SPX-ADRS-INDEX!
        DUP _SPX-WLEN + I SPX-N * +  \ auth[I]
        _SPX-XMSS-IDX @ I RSHIFT 1 AND IF
            \ node is right child: T_2(auth, node)
            _SPX-NODE _SPX-NODE2 _SPX-T2
        ELSE
            \ node is left child: T_2(node, auth)
            _SPX-NODE SWAP _SPX-NODE2 _SPX-T2
        THEN
        _SPX-NODE2 _SPX-NODE SPX-N CMOVE
    LOOP
    DROP
    _SPX-NODE R> SPX-N CMOVE ;

\ =====================================================================
\  13. FORS operations
\ =====================================================================

\ FORS leaf hash at absolute index -> dst.
\ Switches ADRS to FORS_PRF then FORS_TREE.
: _SPX-FORS-LEAF  ( abs-idx dst -- )
    >R
    _SPX-T-FORS-PRF _SPX-ADRS-TYPE!
    _SPX-FORS-KP @ _SPX-ADRS-KP!
    DUP _SPX-ADRS-INDEX!
    _SPX-NODE2 _SPX-PRF
    _SPX-T-FORS-TREE _SPX-ADRS-TYPE!
    _SPX-FORS-KP @ _SPX-ADRS-KP!
    0 _SPX-ADRS-HEIGHT!
    _SPX-ADRS-INDEX!
    _SPX-NODE2 R> _SPX-T1 ;

\ Compute FORS subtree root via treehash -> dst.
\ Uses _SPX-V-FNODE-HT for height (safe inside DO..LOOP).
\ dst stays on rstack (only accessed after loop).
: _SPX-FORS-NODE  ( start height dst -- )
    >R
    _SPX-V-FNODE-HT !
    _SPX-TH-RESET
    DUP 1 _SPX-V-FNODE-HT @ LSHIFT + SWAP  ( end start  R: dst )
    ?DO
        I _SPX-NODE _SPX-FORS-LEAF
        0
        BEGIN
            DUP _SPX-TH-TOP-H =
            OVER _SPX-V-FNODE-HT @ < AND
        WHILE
            _SPX-T-FORS-TREE _SPX-ADRS-TYPE!
            _SPX-FORS-KP @ _SPX-ADRS-KP!
            DUP 1+ _SPX-ADRS-HEIGHT!
            I OVER 1+ RSHIFT _SPX-ADRS-INDEX!
            _SPX-TH-POP _SPX-NODE _SPX-NODE2 _SPX-T2
            _SPX-NODE2 _SPX-NODE SPX-N CMOVE
            1+
        REPEAT
        _SPX-NODE SWAP _SPX-TH-PUSH
    LOOP
    _SPX-TH-POP R> SPX-N CMOVE ;

\ FORS sign: write k*(n + a*n) = 2912 bytes to sig-out.
\ _SPX-FORS-KP must be set (= leaf_idx from message).
\ ADRS tree must be set.
\ Uses _SPX-V-FSIG-OUT for sig-out (safe inside nested DO..LOOP).
: _SPX-FORS-SIGN  ( sig-out -- )
    _SPX-V-FSIG-OUT !
    _SPX-K 0 DO                      \ I = tree# (0..13)
        I _SPX-FORS-IDX _SPX-CUR-FIDX !
        I 1 _SPX-A LSHIFT * _SPX-FORS-BASE !
        \ Secret value -> sig
        _SPX-T-FORS-PRF _SPX-ADRS-TYPE!
        _SPX-FORS-KP @ _SPX-ADRS-KP!
        _SPX-CUR-FIDX @ _SPX-FORS-BASE @ + _SPX-ADRS-INDEX!
        _SPX-V-FSIG-OUT @ I _SPX-FORS-ENTRY * + _SPX-PRF
        \ Auth path: a levels
        _SPX-A 0 DO                  \ I = auth level (0..11), J = tree#
            _SPX-CUR-FIDX @ I RSHIFT 1 XOR
            1 I LSHIFT *
            _SPX-FORS-BASE @ +
            I
            _SPX-V-FSIG-OUT @ J _SPX-FORS-ENTRY * + SPX-N + I SPX-N * +
            _SPX-FORS-NODE
        LOOP
    LOOP ;

\ FORS pk from sig -> dst.
: _SPX-FORS-PK-FROM-SIG  ( sig-in dst -- )
    >R
    _SPX-K 0 DO                      \ I = tree# (0..13)
        I _SPX-FORS-IDX _SPX-CUR-FIDX !
        I 1 _SPX-A LSHIFT * _SPX-FORS-BASE !
        \ Hash secret -> leaf node
        _SPX-T-FORS-TREE _SPX-ADRS-TYPE!
        _SPX-FORS-KP @ _SPX-ADRS-KP!
        0 _SPX-ADRS-HEIGHT!
        _SPX-CUR-FIDX @ _SPX-FORS-BASE @ + _SPX-ADRS-INDEX!
        DUP I _SPX-FORS-ENTRY * +    \ &sig_secret
        _SPX-NODE _SPX-T1
        \ Walk auth path
        _SPX-A 0 DO                  \ I = auth level (0..11), J = tree#
            _SPX-T-FORS-TREE _SPX-ADRS-TYPE!
            _SPX-FORS-KP @ _SPX-ADRS-KP!
            I 1+ _SPX-ADRS-HEIGHT!
            _SPX-CUR-FIDX @ _SPX-FORS-BASE @ +
            I 1+ RSHIFT _SPX-ADRS-INDEX!
            OVER J _SPX-FORS-ENTRY * + SPX-N + I SPX-N * +  \ auth[I]
            _SPX-CUR-FIDX @ I RSHIFT 1 AND IF
                _SPX-NODE _SPX-NODE2 _SPX-T2
            ELSE
                _SPX-NODE SWAP _SPX-NODE2 _SPX-T2
            THEN
            _SPX-NODE2 _SPX-NODE SPX-N CMOVE
        LOOP
        _SPX-NODE _SPX-FORS-RTS I SPX-N * + SPX-N CMOVE
    LOOP
    DROP
    _SPX-T-FORS-ROOTS _SPX-ADRS-TYPE!
    _SPX-FORS-KP @ _SPX-ADRS-KP!
    _SPX-FORS-RTS R> _SPX-T-K ;

\ =====================================================================
\  14. Hypertree sign / verify
\ =====================================================================

\ HT sign: sign n-byte msg with hypertree -> sig-out (d*704 = 4928 bytes).
\ Uses _SPX-V-HTSIG-OUT for sig-out (safe inside DO..LOOP).
: _SPX-HT-SIGN  ( msg tree-idx leaf-idx sig-out -- )
    _SPX-V-HTSIG-OUT !
    _SPX-HT-LEAF !
    _SPX-HT-TREE !
    _SPX-CUR-MSG !
    \ Layer 0
    _SPX-ADRS-ZERO
    0 _SPX-ADRS-LAYER!
    _SPX-HT-TREE @ _SPX-ADRS-TREE!
    _SPX-CUR-MSG @ _SPX-HT-LEAF @ _SPX-V-HTSIG-OUT @ _SPX-XMSS-SIGN
    \ Compute root of layer 0 for next layer
    _SPX-CUR-MSG @ _SPX-HT-LEAF @ _SPX-V-HTSIG-OUT @
    _SPX-NODE _SPX-XMSS-ROOT
    \ Layers 1..d-1
    _SPX-D 1 DO
        _SPX-HT-TREE @ 511 AND _SPX-HT-LEAF !
        _SPX-HT-TREE @ 9 RSHIFT _SPX-HT-TREE !
        I _SPX-ADRS-LAYER!
        _SPX-HT-TREE @ _SPX-ADRS-TREE!
        _SPX-NODE _SPX-HT-LEAF @
        _SPX-V-HTSIG-OUT @ I _SPX-HT-LAYER-SZ * + _SPX-XMSS-SIGN
        \ Compute root for next layer (skip on last)
        I _SPX-D 1- < IF
            _SPX-NODE _SPX-HT-LEAF @
            _SPX-V-HTSIG-OUT @ I _SPX-HT-LAYER-SZ * +
            _SPX-NODE2 _SPX-XMSS-ROOT
            _SPX-NODE2 _SPX-NODE SPX-N CMOVE
        THEN
    LOOP ;

\ HT verify: verify hypertree sig -> flag.
\ Uses _SPX-V-HTVER-ROOT for pk-root (safe inside DO..LOOP).
: _SPX-HT-VERIFY  ( msg tree-idx leaf-idx sig-in pk-root -- flag )
    _SPX-V-HTVER-ROOT !
    >R
    _SPX-HT-LEAF !
    _SPX-HT-TREE !
    _SPX-CUR-MSG !
    \ Layer 0: reconstruct root
    _SPX-ADRS-ZERO
    0 _SPX-ADRS-LAYER!
    _SPX-HT-TREE @ _SPX-ADRS-TREE!
    _SPX-CUR-MSG @ _SPX-HT-LEAF @ R@
    _SPX-NODE _SPX-XMSS-ROOT
    R>                               ( sig-in )
    \ Layers 1..d-1
    _SPX-D 1 DO
        _SPX-HT-TREE @ 511 AND _SPX-HT-LEAF !
        _SPX-HT-TREE @ 9 RSHIFT _SPX-HT-TREE !
        I _SPX-ADRS-LAYER!
        _SPX-HT-TREE @ _SPX-ADRS-TREE!
        _SPX-NODE _SPX-HT-LEAF @
        OVER I _SPX-HT-LAYER-SZ * +
        _SPX-NODE2 _SPX-XMSS-ROOT
        _SPX-NODE2 _SPX-NODE SPX-N CMOVE
    LOOP
    DROP
    \ Constant-time compare root vs pk-root
    0
    SPX-N 0 DO
        _SPX-NODE I + C@
        _SPX-V-HTVER-ROOT @ I + C@
        XOR OR
    LOOP
    0= ;

\ =====================================================================
\  15. Top-level API
\ =====================================================================

\ SPX-KEYGEN ( seed pub sec -- )
\ seed: 48 bytes = SK.seed(16) | SK.prf(16) | PK.seed(16)
\ sec:  64 bytes = SK.seed(16) | SK.prf(16) | PK.seed(16) | PK.root(16)
\ pub:  32 bytes = PK.seed(16) | PK.root(16)
: SPX-KEYGEN  ( seed pub sec -- )
    _SPX-KG-SEC !
    _SPX-KG-PUB !
    \ Copy seed(48 bytes) -> sec[0..47]
    DUP _SPX-KG-SEC @ 48 CMOVE
    DROP
    \ Copy PK.seed -> pub[0..15]
    _SPX-KG-SEC @ 32 + _SPX-KG-PUB @ SPX-N CMOVE
    \ Set internal pointers
    _SPX-KG-SEC @          _SPX-SK-SEED !
    _SPX-KG-SEC @ 16 +    _SPX-SK-PRF !
    _SPX-KG-SEC @ 32 +    _SPX-PK-SEED !
    \ Compute root of top XMSS tree (layer=d-1, tree=0)
    _SPX-ADRS-ZERO
    _SPX-D 1- _SPX-ADRS-LAYER!
    0 _SPX-ADRS-TREE!
    0 _SPX-HP _SPX-KG-SEC @ 48 + _SPX-XMSS-NODE
    \ Copy PK.root -> pub[16..31]
    _SPX-KG-SEC @ 48 + _SPX-KG-PUB @ 16 + SPX-N CMOVE
    \ Set root pointer
    _SPX-KG-SEC @ 48 + _SPX-PK-ROOT ! ;

\ SPX-SIGN ( msg len sec sig -- )
: SPX-SIGN  ( msg len sec sig -- )
    _SPX-SIG-PTR !
    DUP      _SPX-SK-SEED !
    DUP 16 + _SPX-SK-PRF  !
    DUP 32 + _SPX-PK-SEED !
    48 +     _SPX-PK-ROOT !
    _SPX-MSG-LEN !
    _SPX-MSG-PTR !
    \ opt_rand: randomized or deterministic
    SPX-SIGN-MODE @ SPX-MODE-DETERMINISTIC = IF
        _SPX-PK-SEED @ _SPX-OPT-RAND SPX-N CMOVE
    ELSE
        _SPX-OPT-RAND SPX-N RNG-BYTES
    THEN
    \ R = PRF_msg -> sig[0..15]
    _SPX-SIG-PTR @ _SPX-PRF-MSG
    \ H_msg -> _SPX-DIGEST (30 bytes of digest)
    _SPX-SIG-PTR @ _SPX-H-MSG
    \ Extract indices from digest
    _SPX-TREE-IDX _SPX-HT-TREE !
    _SPX-LEAF-IDX _SPX-HT-LEAF !
    \ FORS sign -> sig[16..2927]
    _SPX-ADRS-ZERO
    0 _SPX-ADRS-LAYER!
    _SPX-HT-TREE @ _SPX-ADRS-TREE!
    _SPX-HT-LEAF @ _SPX-FORS-KP !
    _SPX-SIG-PTR @ _SPX-SIG-FORS + _SPX-FORS-SIGN
    \ Compute FORS pk -> _SPX-NODE
    _SPX-SIG-PTR @ _SPX-SIG-FORS + _SPX-NODE _SPX-FORS-PK-FROM-SIG
    \ HT sign -> sig[2928..7855]
    _SPX-NODE _SPX-HT-TREE @ _SPX-HT-LEAF @
    _SPX-SIG-PTR @ _SPX-SIG-FORS + _SPX-SIG-FORS-SZ + _SPX-HT-SIGN ;

\ SPX-VERIFY ( msg len pub sig sig-len -- flag )
: SPX-VERIFY  ( msg len pub sig sig-len -- flag )
    SPX-SIG-LEN <> IF 2DROP 2DROP FALSE EXIT THEN
    _SPX-SIG-PTR !
    DUP _SPX-PK-SEED !
    SPX-N + _SPX-PK-ROOT !
    _SPX-MSG-LEN !
    _SPX-MSG-PTR !
    \ H_msg(R=sig[0..15])
    _SPX-SIG-PTR @ _SPX-H-MSG
    \ Extract indices
    _SPX-TREE-IDX _SPX-HT-TREE !
    _SPX-LEAF-IDX _SPX-HT-LEAF !
    \ FORS pk from sig -> _SPX-NODE
    _SPX-ADRS-ZERO
    0 _SPX-ADRS-LAYER!
    _SPX-HT-TREE @ _SPX-ADRS-TREE!
    _SPX-HT-LEAF @ _SPX-FORS-KP !
    _SPX-SIG-PTR @ _SPX-SIG-FORS + _SPX-NODE _SPX-FORS-PK-FROM-SIG
    \ HT verify
    _SPX-NODE _SPX-HT-TREE @ _SPX-HT-LEAF @
    _SPX-SIG-PTR @ _SPX-SIG-FORS + _SPX-SIG-FORS-SZ +
    _SPX-PK-ROOT @
    _SPX-HT-VERIFY ;

\ SPX-KEYGEN-RANDOM ( pub sec -- )
\ ── P07: zeroize seed buffer after random keygen ──
: SPX-KEYGEN-RANDOM  ( pub sec -- )
    _SPX-RNG-SEED 48 RNG-BYTES
    >R >R _SPX-RNG-SEED R> R> SPX-KEYGEN
    _SPX-RNG-SEED 48 0 FILL ;

\ ── Concurrency Guard ─────────────────────────────────────
REQUIRE ../concurrency/guard.f
GUARD _spx-guard

' SPX-KEYGEN         CONSTANT _spx-keygen-xt
' SPX-SIGN           CONSTANT _spx-sign-xt
' SPX-VERIFY         CONSTANT _spx-verify-xt
' SPX-KEYGEN-RANDOM  CONSTANT _spx-keygen-rng-xt

: SPX-KEYGEN         _spx-keygen-xt      _spx-guard WITH-GUARD ;
: SPX-SIGN           _spx-sign-xt        _spx-guard WITH-GUARD ;
: SPX-VERIFY         _spx-verify-xt      _spx-guard WITH-GUARD ;
: SPX-KEYGEN-RANDOM  _spx-keygen-rng-xt  _spx-guard WITH-GUARD ;
