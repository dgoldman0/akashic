\ =================================================================
\  merkle.f  —  Binary Merkle Tree (SHA3-256)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: MERKLE-
\  Depends on: sha3.f
\
\  General-purpose binary Merkle tree over 32-byte leaf hashes.
\  Used by STARKs, content-addressed storage, authenticated data
\  structures, and any application needing commitment with
\  selective opening.
\
\  Public API — tree management:
\   MERKLE-TREE       ( n "name" -- )         create tree for n leaves
\   MERKLE-N          ( tree -- n )            number of leaves
\   MERKLE-LEAF!      ( hash idx tree -- )     set leaf hash at index
\   MERKLE-LEAF@      ( idx tree -- addr )     pointer to leaf hash
\   MERKLE-BUILD      ( tree -- )              compute internal nodes
\   MERKLE-ROOT       ( tree -- addr )         pointer to 32-byte root
\
\  Public API — opening and verification:
\   MERKLE-OPEN       ( idx tree proof -- d )  write auth path to proof
\   MERKLE-VERIFY     ( leaf idx proof d root -- flag )  verify opening
\
\  Constants:
\   MERKLE-HASH-LEN   ( -- 32 )
\
\  Tree layout: 1-indexed flat array of (2n - 1) 32-byte nodes.
\   Nodes 1..n-1 are internal.  Node 1 is the root.
\   Nodes n..2n-1 are leaves (leaf 0 = node n).
\   Parent of node i = i/2.  Children = 2i, 2i+1.
\
\  Hashing:
\   Leaf:     stored directly (caller hashes data before calling LEAF!)
\   Internal: SHA3-256( 0x01 || left-child || right-child )  65 bytes
\
\  Proof buffer: d × 32 bytes (one sibling per level, d = log2(n)).
\
\  Not reentrant (shares SHA3 device).
\ =================================================================

REQUIRE sha3.f

PROVIDED akashic-merkle

\ =====================================================================
\  Constants
\ =====================================================================

32 CONSTANT MERKLE-HASH-LEN

\ =====================================================================
\  Scratch buffer for internal node hashing
\ =====================================================================
\ 1 domain byte + 32 left + 32 right = 65 bytes
CREATE _MK-SCRATCH  65 ALLOT
CREATE _MK-TMP-HASH 32 ALLOT

\ =====================================================================
\  Tree creation
\ =====================================================================

\ MERKLE-TREE ( n "name" -- )
\   Create a named Merkle tree for n leaves (must be power of 2).
\   Layout: cell 0 = n, then (2n-1) × 32 bytes of node storage.
\   Nodes are 1-indexed: node i is at offset CELL + (i-1)*32.
: MERKLE-TREE  ( n "name" -- )
    CREATE DUP ,  2 * 1 - 32 * ALLOT ;

\ =====================================================================
\  Accessors
\ =====================================================================

\ MERKLE-N ( tree -- n )  Number of leaves.
: MERKLE-N  ( tree -- n )  @ ;

\ _MK-NODE ( i tree -- addr )  Address of node i (1-indexed).
: _MK-NODE  ( i tree -- addr )
    CELL+ SWAP 1 - 32 * + ;

\ MERKLE-ROOT ( tree -- addr )  Address of 32-byte root hash (node 1).
: MERKLE-ROOT  ( tree -- addr )
    1 SWAP _MK-NODE ;

\ MERKLE-LEAF@ ( idx tree -- addr )  Address of leaf hash at index (0-based).
\   Leaf idx maps to node (n + idx).
: MERKLE-LEAF@  ( idx tree -- addr )
    DUP MERKLE-N ROT + SWAP _MK-NODE ;

\ MERKLE-LEAF! ( hash idx tree -- )  Copy 32-byte hash into leaf slot.
: MERKLE-LEAF!  ( hash idx tree -- )
    MERKLE-LEAF@ 32 CMOVE ;

\ =====================================================================
\  Build tree (bottom-up)
\ =====================================================================

\ _MK-HASH-PAIR ( left-addr right-addr dst -- )
\   dst = SHA3-256( 0x01 || left || right )
: _MK-HASH-PAIR  ( left right dst -- )
    >R  SWAP
    \ Stack: right left   R: dst
    \ Copy left → scratch+1
    1 _MK-SCRATCH C!
    _MK-SCRATCH 1 +  32 CMOVE
    \ Copy right → scratch+33
    _MK-SCRATCH 33 +  32 CMOVE
    _MK-SCRATCH 65 R> SHA3-256-HASH ;

\ MERKLE-BUILD ( tree -- )
\   Compute all internal nodes from leaves, bottom-up.
\   Iterates i from n-1 down to 1:
\     node[i] = H(0x01 || node[2i] || node[2i+1])
VARIABLE _MK-I
VARIABLE _MK-TREE

: MERKLE-BUILD  ( tree -- )
    DUP _MK-TREE !
    MERKLE-N 1 -  _MK-I !
    BEGIN _MK-I @ 0> WHILE
        _MK-I @ 2 *     _MK-TREE @ _MK-NODE    \ left child
        _MK-I @ 2 * 1 + _MK-TREE @ _MK-NODE    \ right child
        _MK-I @          _MK-TREE @ _MK-NODE    \ destination
        _MK-HASH-PAIR
        _MK-I @ 1 - _MK-I !
    REPEAT ;

\ =====================================================================
\  Opening (authentication path)
\ =====================================================================

\ MERKLE-OPEN ( idx tree proof -- depth )
\   Write authentication path for leaf at idx into proof buffer.
\   Returns depth (number of siblings = log2(n)).
\   Proof layout: depth × 32 bytes, bottom-to-top.
VARIABLE _MK-CUR
VARIABLE _MK-PROOF
VARIABLE _MK-DEPTH

: MERKLE-OPEN  ( idx tree proof -- depth )
    _MK-PROOF !
    DUP _MK-TREE !
    MERKLE-N +  _MK-CUR !
    \ Compute depth = log2(n)
    _MK-TREE @ MERKLE-N  0 SWAP
    BEGIN DUP 1 > WHILE 1 RSHIFT SWAP 1 + SWAP REPEAT
    DROP  _MK-DEPTH !
    _MK-DEPTH @ 0 DO
        _MK-CUR @ 1 XOR  _MK-TREE @ _MK-NODE
        _MK-PROOF @ I 32 * +
        32 CMOVE
        _MK-CUR @ 1 RSHIFT  _MK-CUR !
    LOOP
    _MK-DEPTH @ ;

\ =====================================================================
\  Verification
\ =====================================================================

\ MERKLE-VERIFY ( leaf-hash idx proof depth root -- flag )
\   Verify that leaf-hash at position idx matches the root
\   given the authentication path in proof.
\   Returns TRUE (-1) if valid, FALSE (0) otherwise.
VARIABLE _MK-V-IDX
VARIABLE _MK-V-PROOF

: MERKLE-VERIFY  ( leaf-hash idx proof depth root -- flag )
    >R
    SWAP _MK-V-PROOF !
    SWAP _MK-V-IDX !
    SWAP _MK-TMP-HASH 32 CMOVE
    0 DO
        _MK-V-IDX @ 1 AND IF
            _MK-V-PROOF @ I 32 * +
            _MK-TMP-HASH
            _MK-TMP-HASH
            _MK-HASH-PAIR
        ELSE
            _MK-TMP-HASH
            _MK-V-PROOF @ I 32 * +
            _MK-TMP-HASH
            _MK-HASH-PAIR
        THEN
        _MK-V-IDX @ 1 RSHIFT  _MK-V-IDX !
    LOOP
    _MK-TMP-HASH R> SHA3-256-COMPARE ;

\ ── Concurrency Guard ─────────────────────────────────────
\ MERKLE-TREE (defining), MERKLE-N, MERKLE-ROOT, MERKLE-LEAF@
\ are pure struct reads — left unguarded.
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _merkle-guard

' MERKLE-BUILD   CONSTANT _mk-build-xt
' MERKLE-OPEN    CONSTANT _mk-open-xt
' MERKLE-VERIFY  CONSTANT _mk-verify-xt
' MERKLE-LEAF!   CONSTANT _mk-leaf-xt

: MERKLE-BUILD   _mk-build-xt   _merkle-guard WITH-GUARD ;
: MERKLE-OPEN    _mk-open-xt    _merkle-guard WITH-GUARD ;
: MERKLE-VERIFY  _mk-verify-xt  _merkle-guard WITH-GUARD ;
: MERKLE-LEAF!   _mk-leaf-xt    _merkle-guard WITH-GUARD ;
[THEN] [THEN]
