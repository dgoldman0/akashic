\ =================================================================
\  smt.f  —  Sparse Merkle Tree (Compact / Patricia)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SMT-  / _SMT-
\  Depends on: sha3.f
\
\  General-purpose compact sparse Merkle tree keyed by 32-byte
\  keys with 32-byte value hashes.  Uses Patricia compression:
\  only populated leaves and their branch points are stored.
\  For n leaves there are exactly n-1 branch nodes.
\
\  Node pool is allocated in XMEM.  Descriptor lives in base RAM.
\
\  Node layout (96 bytes = 12 cells, uniform for branch + leaf):
\    +0    cell    type     0=free, 1=branch, 2=leaf
\    +8    cell    x0       branch: bit-position / leaf: 0
\    +16   cell    x1       branch: left-child idx / leaf: 0
\    +24   cell    x2       branch: right-child idx / leaf: free-next
\    +32   32B     fa       branch: cached hash / leaf: key (32 bytes)
\    +64   32B     fb       branch: (unused) / leaf: value (32 bytes)
\
\  Hashing (same domain tags as merkle.f):
\    Leaf:   SHA3-256( 0x00 || key[32] || value[32] )   65 bytes
\    Branch: SHA3-256( 0x01 || left-hash[32] || right-hash[32] )
\
\  Proof format: variable-length array of 40-byte entries.
\    Each entry: 8-byte bit-position + 32-byte sibling hash.
\    Entries ordered root-to-leaf.
\
\  Public API:
\   SMT-INIT      ( tree -- flag )
\   SMT-DESTROY   ( tree -- )
\   SMT-INSERT    ( key val tree -- flag )
\   SMT-LOOKUP    ( key tree -- val-a flag )
\   SMT-DELETE    ( key tree -- flag )
\   SMT-ROOT      ( tree -- addr )
\   SMT-PROVE     ( key buf buf-len tree -- proof-len flag )
\   SMT-VERIFY    ( key val proof len root -- flag )
\   SMT-COUNT     ( tree -- n )
\   SMT-EMPTY?    ( tree -- flag )
\   SMT-MAX       ( tree -- n )
\
\  Not reentrant (shares SHA3 device and scratch buffers).
\ =================================================================

REQUIRE ../math/sha3.f

PROVIDED akashic-smt

\ =====================================================================
\  1. Constants
\ =====================================================================

4096 CONSTANT SMT-MAX-LEAVES
8191 CONSTANT _SMT-MAX-NODES      \ 2 * SMT-MAX-LEAVES - 1
  96 CONSTANT _SMT-NODE-SZ        \ bytes per node

\ Node types
0 CONSTANT _SMT-FREE
1 CONSTANT _SMT-BRANCH
2 CONSTANT _SMT-LEAF

\ Node field offsets
 0 CONSTANT _SN-TYPE
 8 CONSTANT _SN-X0
16 CONSTANT _SN-X1
24 CONSTANT _SN-X2
32 CONSTANT _SN-FA
64 CONSTANT _SN-FB

\ Descriptor field offsets (64 bytes)
 0 CONSTANT _SD-POOL       \ XMEM pool base address
 8 CONSTANT _SD-MAX        \ max nodes
16 CONSTANT _SD-ROOT       \ root node index (0 = empty)
24 CONSTANT _SD-LCNT       \ leaf count
32 CONSTANT _SD-NCNT       \ total allocated node count
40 CONSTANT _SD-FREE       \ free list head (node index, 0 = empty)
48 CONSTANT _SD-MAXL       \ max leaves (user-facing)
56 CONSTANT _SD-RSVD

\ =====================================================================
\  2. Scratch buffers
\ =====================================================================

CREATE _SMT-HSC  65 ALLOT         \ hash scratch: 1 tag + 32 + 32
CREATE _SMT-TMP  32 ALLOT         \ temp hash result
CREATE _SMT-TM2  32 ALLOT         \ second temp (empty root)

\ =====================================================================
\  3. Node addressing
\ =====================================================================

\ _SMT-NODE ( idx tree -- addr )
\   Node index is 1-based. Index 0 means "empty".
\   Guard: if idx=0, return 0 (NULL) — prevents wrapped addressing.
: _SMT-NODE  ( idx tree -- addr )
    OVER 0= IF 2DROP 0 EXIT THEN
    _SD-POOL + @ SWAP 1 - _SMT-NODE-SZ * + ;

\ =====================================================================
\  4. SMT-INIT — allocate XMEM pool, build free list
\ =====================================================================
VARIABLE _smt-init-tree   \ temp — holds tree addr during DO LOOP

: _SMT-INIT  ( tree -- flag )
    DUP _smt-init-tree !
    DUP >R
    _SMT-MAX-NODES _SMT-NODE-SZ * XMEM-ALLOT
    DUP 0= IF DROP R> DROP 0 EXIT THEN
    R@ _SD-POOL + !
    _SMT-MAX-NODES R@ _SD-MAX  + !
    0              R@ _SD-ROOT + !
    0              R@ _SD-LCNT + !
    0              R@ _SD-NCNT + !
    SMT-MAX-LEAVES R@ _SD-MAXL + !
    0              R@ _SD-RSVD + !
    \ Zero entire pool
    R@ _SD-POOL + @ _SMT-MAX-NODES _SMT-NODE-SZ * 0 FILL
    \ Build free list: chain 1→2→3→...→max→0
    \ NOTE: R@ inside DO LOOP returns loop index, not tree.
    \       Use _smt-init-tree @ instead.
    _SMT-MAX-NODES 1+ 1 DO
        _SMT-FREE I _smt-init-tree @ _SMT-NODE _SN-TYPE + !
        I _SMT-MAX-NODES < IF I 1+ ELSE 0 THEN
        I _smt-init-tree @ _SMT-NODE _SN-X2 + !
    LOOP
    1 R> _SD-FREE + !
    -1 ;

: SMT-INIT  _SMT-INIT ;

\ =====================================================================
\  5. SMT-DESTROY — free XMEM pool
\ =====================================================================

: _SMT-DESTROY  ( tree -- )
    DUP _SD-POOL + @ _SMT-MAX-NODES _SMT-NODE-SZ * XMEM-FREE-BLOCK
    0 OVER _SD-POOL + !
    0 OVER _SD-ROOT + !
    0 OVER _SD-LCNT + !
    0 OVER _SD-NCNT + !
    0 SWAP _SD-FREE + ! ;

: SMT-DESTROY  _SMT-DESTROY ;

\ =====================================================================
\  6. Free list management
\ =====================================================================

VARIABLE _smt-al-tree

: _SMT-ALLOC  ( tree -- idx | 0 )
    _smt-al-tree !
    _smt-al-tree @ _SD-FREE + @ DUP 0= IF EXIT THEN
    DUP _smt-al-tree @ _SMT-NODE _SN-X2 + @
    _smt-al-tree @ _SD-FREE + !
    _smt-al-tree @ _SD-NCNT + DUP @ 1+ SWAP ! ;

VARIABLE _smt-fr-tree

: _SMT-FREE-NODE  ( idx tree -- )
    _smt-fr-tree !
    DUP _smt-fr-tree @ _SMT-NODE _SMT-NODE-SZ 0 FILL
    _smt-fr-tree @ _SD-FREE + @ OVER
    _smt-fr-tree @ _SMT-NODE _SN-X2 + !
    _smt-fr-tree @ _SD-FREE + !
    _smt-fr-tree @ _SD-NCNT + DUP @ 1- SWAP ! ;

\ =====================================================================
\  7. Key-bit extraction
\ =====================================================================

: _SMT-KEY-BIT  ( key bit# -- 0|1 )
    DUP 3 RSHIFT ROT + C@
    SWAP 7 AND 7 SWAP - RSHIFT 1 AND ;

\ _SMT-FIRST-DIFF-BIT ( a b -- bit# )
\   First bit where 32-byte keys a and b differ. 256 if identical.
: _SMT-FIRST-DIFF-BIT  ( a b -- bit# )
    32 0 DO
        OVER I + C@  OVER I + C@  XOR
        DUP 0<> IF
            \ Find highest set bit in the XOR byte
            NIP NIP
            I 8 *                  ( xor-byte base-bit )
            SWAP
            8 0 DO
                DUP 128 AND IF
                    DROP I LEAVE
                THEN
                1 LSHIFT
            LOOP                   ( base-bit bit-within )
            + UNLOOP EXIT
        THEN
        DROP
    LOOP
    2DROP 256 ;

\ =====================================================================
\  8. Hashing helpers
\ =====================================================================

\ _SMT-HASH-LEAF-ADDR ( node-addr -- )
\   Compute leaf hash → _SMT-TMP from node at address.
: _SMT-HASH-LEAF-ADDR  ( node-addr -- )
    0 _SMT-HSC C!
    DUP _SN-FA + _SMT-HSC 1 + 32 CMOVE
    _SN-FB + _SMT-HSC 33 + 32 CMOVE
    _SMT-HSC 65 _SMT-TMP SHA3-256-HASH ;

\ _SMT-NODE-HASH ( idx tree -- hash-addr )
\   Return address of 32-byte hash for node.
\   Branch: cached at _SN-FA.
\   Leaf: computed on the fly into _SMT-TMP.
: _SMT-NODE-HASH  ( idx tree -- hash-addr )
    _SMT-NODE DUP _SN-TYPE + @
    _SMT-LEAF = IF
        _SMT-HASH-LEAF-ADDR _SMT-TMP
    ELSE
        _SN-FA +
    THEN ;

\ _SMT-HASH-BRANCH-ADDR ( node-addr L-hash R-hash -- )
\   Compute branch hash and store in node's _SN-FA.
: _SMT-HASH-BRANCH-ADDR  ( node-addr L-hash R-hash -- )
    1 _SMT-HSC C!
    _SMT-HSC 33 + 32 CMOVE        \ right hash
    _SMT-HSC 1  + 32 CMOVE        \ left hash
    _SN-FA + _SMT-HSC 65 ROT SHA3-256-HASH ;

\ _SMT-RECOMPUTE ( branch-idx tree -- )
\   Recompute a branch node's hash from its children.
VARIABLE _smt-rc-tree

: _SMT-RECOMPUTE  ( branch-idx tree -- )
    _smt-rc-tree !
    DUP _smt-rc-tree @ _SMT-NODE >R   ( br-idx  R: br-addr )
    \ Left child hash
    R@ _SN-X1 + @ _smt-rc-tree @ _SMT-NODE-HASH
    \ Save it — _SMT-NODE-HASH for a leaf uses _SMT-TMP
    _SMT-TM2 32 CMOVE
    \ Right child hash
    R@ _SN-X2 + @ _smt-rc-tree @ _SMT-NODE-HASH
    \ Now: left in _SMT-TM2, right in returned addr
    R> _SMT-TM2 ROT _SMT-HASH-BRANCH-ADDR
    DROP ;

\ =====================================================================
\  9. SMT-INSERT — insert or update a leaf
\ =====================================================================
\
\  Algorithm (handles mid-path insertion correctly):
\
\  1. If tree is empty: create leaf, set as root.
\
\  2. Walk from root following key bits at each branch's bit-pos.
\     Stop when reaching a leaf. Record the entire path.
\
\  3. At the leaf: compare keys.
\     a. If keys match: update value, rehash path, done.
\     b. If keys differ: compute diff-bit.
\
\  4. Find insertion point for new branch (diff-bit):
\     Walk the path from root to find the first branch whose
\     bit-pos > diff-bit. The new branch goes BEFORE that branch
\     (or at the leaf position if all branches have bit-pos < diff-bit).
\
\  5. Create new branch with diff-bit, allocate new leaf.
\     Wire children: one child is the new leaf, the other is the
\     subtree that was previously at that position.
\
\  6. Rehash affected branch nodes bottom-up.

\ Path stack for traversal
CREATE _SMT-PATH 256 CELLS ALLOT
VARIABLE _SMT-PDEPTH

VARIABLE _smt-i-tree
VARIABLE _smt-i-key
VARIABLE _smt-i-val

\ _SMT-MAKE-LEAF ( key val tree -- idx | 0 )
: _SMT-MAKE-LEAF  ( key val tree -- idx | 0 )
    DUP >R _SMT-ALLOC DUP 0= IF R> 2DROP DROP EXIT THEN
    DUP R@ _SMT-NODE >R           ( key val idx  R: tree node )
    _SMT-LEAF R@ _SN-TYPE + !
    0 R@ _SN-X0 + !
    0 R@ _SN-X1 + !
    0 R@ _SN-X2 + !
    ROT ROT                        ( idx key val  R: tree node )
    R@ _SN-FB + 32 CMOVE          \ value → fb
    R> _SN-FA + 32 CMOVE          ( idx )  \ key → fa
    R> DROP ;

\ _SMT-REHASH-UP ( tree -- )
\   Rehash branch nodes in _SMT-PATH[0..depth-1] from bottom to top.
: _SMT-REHASH-UP  ( tree -- )
    _SMT-PDEPTH @ 0 ?DO
        _SMT-PDEPTH @ 1 - I - CELLS _SMT-PATH + @
        OVER _SMT-RECOMPUTE
    LOOP
    DROP ;

: _SMT-INSERT  ( key val tree -- flag )
    _smt-i-tree !  _smt-i-val !  _smt-i-key !
    0 _SMT-PDEPTH !

    \ ---- Empty tree ----
    _smt-i-tree @ _SD-ROOT + @ 0= IF
        \ Capacity guards
        _smt-i-tree @ _SD-LCNT + @ _smt-i-tree @ _SD-MAXL + @ >= IF
            0 EXIT
        THEN
        _smt-i-key @ _smt-i-val @ _smt-i-tree @ _SMT-MAKE-LEAF
        DUP 0= IF EXIT THEN
        _smt-i-tree @ _SD-ROOT + !
        _smt-i-tree @ _SD-LCNT + DUP @ 1+ SWAP !
        -1 EXIT
    THEN

    \ ---- Walk to leaf ----
    _smt-i-tree @ _SD-ROOT + @    ( cur-idx )
    BEGIN
        DUP _smt-i-tree @ _SMT-NODE _SN-TYPE + @
        _SMT-BRANCH =
    WHILE
        DUP _SMT-PDEPTH @ CELLS _SMT-PATH + !
        _SMT-PDEPTH @ 1+ _SMT-PDEPTH !
        DUP _smt-i-tree @ _SMT-NODE _SN-X0 + @   ( cur bit-pos )
        _smt-i-key @ SWAP _SMT-KEY-BIT   ( cur bit )
        IF
            _smt-i-tree @ _SMT-NODE _SN-X2 + @
        ELSE
            _smt-i-tree @ _SMT-NODE _SN-X1 + @
        THEN
    REPEAT                         ( leaf-idx )

    \ ---- At leaf: compare keys ----
    DUP _smt-i-tree @ _SMT-NODE _SN-FA +
    32 _smt-i-key @ 32 COMPARE 0= IF
        \ Keys match — update value
        _smt-i-val @
        SWAP _smt-i-tree @ _SMT-NODE _SN-FB + 32 CMOVE
        _smt-i-tree @ _SMT-REHASH-UP
        -1 EXIT
    THEN
    \ ( leaf-idx ) — keys differ

    \ ---- Find diff-bit ----
    DUP _smt-i-tree @ _SMT-NODE _SN-FA +
    _smt-i-key @ SWAP
    _SMT-FIRST-DIFF-BIT           ( leaf-idx diff-bit )

    \ ---- Capacity guards (B11) ----
    \ New leaf insertion needs 2 nodes (leaf + branch).
    _smt-i-tree @ _SD-LCNT + @ _smt-i-tree @ _SD-MAXL + @ >= IF
        2DROP 0 EXIT
    THEN
    _smt-i-tree @ _SD-NCNT + @ 2 + _smt-i-tree @ _SD-MAX + @ > IF
        2DROP 0 EXIT
    THEN

    \ ---- Create new leaf ----
    _smt-i-key @ _smt-i-val @ _smt-i-tree @ _SMT-MAKE-LEAF
    DUP 0= IF NIP NIP 0 EXIT THEN ( leaf-idx diff-bit new-leaf )

    \ ---- Create new branch ----
    _smt-i-tree @ _SMT-ALLOC
    DUP 0= IF
        DROP _smt-i-tree @ _SMT-FREE-NODE
        2DROP 0 EXIT
    THEN                           ( old-leaf diff new-leaf branch )

    \ Set up branch
    DUP _smt-i-tree @ _SMT-NODE >R
    _SMT-BRANCH R@ _SN-TYPE + !

    \ Store diff-bit as bit-pos
    2 PICK R@ _SN-X0 + !          ( old-leaf diff new-leaf branch  R: br-addr )

    \ Determine children: check new key's bit at diff-bit
    _smt-i-key @ 3 PICK _SMT-KEY-BIT  ( old-leaf diff new-leaf branch bit )
    IF
        \ New key bit=1 → new leaf right, old subtree left
        OVER R@ _SN-X2 + !        \ right = new-leaf
        \ Left child = what was at this tree position (determined below)
    ELSE
        \ New key bit=0 → new leaf left, old subtree right
        OVER R@ _SN-X1 + !        \ left = new-leaf
    THEN
    R> DROP                        ( old-leaf diff new-leaf branch )

    \ ---- Find insertion point ----
    \ Walk _SMT-PATH from top (root) to find where diff-bit fits.
    \ The new branch replaces the subtree at the point where the
    \ first branch has bit-pos > diff-bit (or at the leaf itself).
    \
    \ insert-pos = index into path where new branch should go.
    \ Everything at path[insert-pos..] becomes a child of new branch.

    0                              ( old-leaf diff new-leaf branch insert-pos )
    BEGIN
        DUP _SMT-PDEPTH @ <
    WHILE
        DUP CELLS _SMT-PATH + @
        _smt-i-tree @ _SMT-NODE _SN-X0 + @   ( ... path-bit-pos )
        3 PICK > IF LEAVE THEN    \ this branch's bit > diff → insert here
        1+
    REPEAT                         ( old-leaf diff new-leaf branch insert-pos )

    \ The subtree that was at position insert-pos becomes the "other"
    \ child of the new branch. If insert-pos < depth, the subtree is
    \ path[insert-pos]'s child on the key's side. If insert-pos = depth,
    \ the subtree is the old leaf.

    \ Determine the old subtree root that the new branch replaces:
    DUP _SMT-PDEPTH @ >= IF
        \ Insert at leaf level — old subtree is just the old leaf
        4 PICK                     ( ... old-leaf-idx )
    ELSE
        \ Insert mid-path — old subtree is path[insert-pos]
        DUP CELLS _SMT-PATH + @   ( ... path-node-idx )
    THEN                           ( old-leaf diff new-leaf branch insert-pos old-sub )

    \ Wire old-sub as the other child of new branch
    _smt-i-key @ 5 PICK _SMT-KEY-BIT  ( ... insert-pos old-sub bit )
    3 PICK _smt-i-tree @ _SMT-NODE >R
    IF
        \ New key bit=1 (right=new-leaf already set), left = old-sub
        R> _SN-X1 + !
    ELSE
        \ New key bit=0 (left=new-leaf already set), right = old-sub
        R> _SN-X2 + !
    THEN                           ( old-leaf diff new-leaf branch insert-pos )

    \ ---- Link new branch into tree ----
    DUP 0= IF
        \ Insert at root — drop insert-pos, set branch as root
        DROP
        DUP _smt-i-tree @ _SD-ROOT + !
    ELSE
        \ Parent = path[insert-pos - 1]
        1 - CELLS _SMT-PATH + @   ( ... branch parent-idx )
        _smt-i-key @
        OVER _smt-i-tree @ _SMT-NODE _SN-X0 + @
        _SMT-KEY-BIT               ( ... branch parent-idx bit )
        SWAP _smt-i-tree @ _SMT-NODE  ( ... branch bit parent-addr )
        SWAP IF
            _SN-X2 + OVER SWAP !   \ parent.right = branch
        ELSE
            _SN-X1 + OVER SWAP !   \ parent.left = branch
        THEN
    THEN                           ( old-leaf diff new-leaf branch )

    \ Compute new branch hash
    DUP _smt-i-tree @ _SMT-RECOMPUTE

    \ Update leaf count
    _smt-i-tree @ _SD-LCNT + DUP @ 1+ SWAP !

    \ Rehash path above insert point
    _smt-i-tree @ _SMT-REHASH-UP

    \ Clean stack
    2DROP 2DROP -1 ;

: SMT-INSERT  _SMT-INSERT ;

\ =====================================================================
\  10. SMT-LOOKUP
\ =====================================================================

VARIABLE _smt-lk-tree

: _SMT-LOOKUP  ( key tree -- val-addr flag )
    _smt-lk-tree !
    _smt-lk-tree @ _SD-ROOT + @ DUP 0= IF
        NIP 0 EXIT
    THEN
    BEGIN
        DUP _smt-lk-tree @ _SMT-NODE _SN-TYPE + @
        _SMT-BRANCH =
    WHILE
        OVER OVER
        _smt-lk-tree @ _SMT-NODE _SN-X0 + @
        _SMT-KEY-BIT               ( key node bit )
        IF
            _smt-lk-tree @ _SMT-NODE _SN-X2 + @
        ELSE
            _smt-lk-tree @ _SMT-NODE _SN-X1 + @
        THEN
    REPEAT
    \ At leaf
    DUP _smt-lk-tree @ _SMT-NODE _SN-FA +
    ROT >R 32 R> 32 COMPARE 0= IF
        _smt-lk-tree @ _SMT-NODE _SN-FB + -1
    ELSE
        DROP 0 0
    THEN ;

: SMT-LOOKUP  _SMT-LOOKUP ;

\ =====================================================================
\  11. SMT-ROOT / SMT-COUNT / SMT-EMPTY? / SMT-MAX
\ =====================================================================

: _SMT-ROOT  ( tree -- addr )
    DUP _SD-ROOT + @ DUP 0= IF
        2DROP _SMT-TM2 32 0 FILL _SMT-TM2 EXIT
    THEN
    SWAP _SMT-NODE-HASH
    \ Always copy to _SMT-TM2 so caller gets a stable pointer
    \ (_SMT-NODE-HASH may return _SMT-TMP which is volatile).
    DUP _SMT-TM2 32 CMOVE DROP _SMT-TM2 ;

: SMT-ROOT   _SMT-ROOT ;
: SMT-COUNT  ( tree -- n )    _SD-LCNT + @ ;
: SMT-EMPTY? ( tree -- flag ) SMT-COUNT 0= ;
: SMT-MAX    ( tree -- n )    _SD-MAXL + @ ;

\ =====================================================================
\  12. SMT-PROVE — generate inclusion proof
\ =====================================================================

\ Proof: len × 40-byte entries (8B bit-pos + 32B sibling hash).
\ Entries ordered root-to-leaf. Returns proof-len + flag.
\ Flag is FALSE if key not found or buf-len too small.

VARIABLE _smt-pv-tree
VARIABLE _smt-pv-proof
VARIABLE _smt-pv-len
VARIABLE _smt-pv-blen

: _SMT-PROVE  ( key buf buf-len tree -- proof-len flag )
    _smt-pv-tree !
    _smt-pv-blen !
    _smt-pv-proof !
    0 _smt-pv-len !
    _smt-pv-tree @ _SD-ROOT + @ DUP 0= IF
        NIP 0 0 EXIT
    THEN
    \ Walk down, collecting siblings
    BEGIN
        DUP _smt-pv-tree @ _SMT-NODE _SN-TYPE + @
        _SMT-BRANCH =
    WHILE
        \ Overflow check: (len+1)*40 > buf-len?
        _smt-pv-len @ 1+ 40 * _smt-pv-blen @ > IF
            2DROP 0 0 EXIT
        THEN
        \ Store bit-pos
        DUP _smt-pv-tree @ _SMT-NODE _SN-X0 + @
        _smt-pv-len @ 40 * _smt-pv-proof @ + !
        \ Determine direction
        OVER OVER
        _smt-pv-tree @ _SMT-NODE _SN-X0 + @
        _SMT-KEY-BIT               ( key node bit )
        IF
            \ Going right; sibling = left child
            DUP _smt-pv-tree @ _SMT-NODE _SN-X1 + @
            _smt-pv-tree @ _SMT-NODE-HASH
            _smt-pv-len @ 40 * 8 + _smt-pv-proof @ + 32 CMOVE
            _smt-pv-tree @ _SMT-NODE _SN-X2 + @
        ELSE
            \ Going left; sibling = right child
            DUP _smt-pv-tree @ _SMT-NODE _SN-X2 + @
            _smt-pv-tree @ _SMT-NODE-HASH
            _smt-pv-len @ 40 * 8 + _smt-pv-proof @ + 32 CMOVE
            _smt-pv-tree @ _SMT-NODE _SN-X1 + @
        THEN
        _smt-pv-len @ 1+ _smt-pv-len !
    REPEAT
    \ At leaf — verify key match
    DUP _smt-pv-tree @ _SMT-NODE _SN-FA +
    ROT >R 32 R> 32 COMPARE 0= IF
        DROP _smt-pv-len @ -1
    ELSE
        DROP 0 0
    THEN ;

: SMT-PROVE  _SMT-PROVE ;

\ =====================================================================
\  13. SMT-VERIFY — verify inclusion proof
\ =====================================================================

\ ( key val proof len root -- flag )

VARIABLE _smt-vf-key

: _SMT-VERIFY  ( key val proof len root -- flag )
    \ Sanity: reject if len > 256 (max tree depth for 256-bit keys)
    OVER 256 > IF 2DROP 2DROP DROP 0 EXIT THEN
    >R >R >R                       ( key val  R: root len proof )
    \ Compute leaf hash: SHA3-256(0x00 || key || value)
    SWAP _smt-vf-key !
    0 _SMT-HSC C!
    _smt-vf-key @ _SMT-HSC 1 + 32 CMOVE
    _SMT-HSC 33 + 32 CMOVE
    _SMT-HSC 65 _SMT-TMP SHA3-256-HASH
    R> R>                          ( proof len  R: root )
    0 ?DO                          ( proof )
        DUP I 40 * + @            ( proof bit-pos )
        _smt-vf-key @ SWAP _SMT-KEY-BIT  ( proof bit )
        1 _SMT-HSC C!
        IF
            \ bit=1: current is right
            OVER I 40 * 8 + + _SMT-HSC 1 + 32 CMOVE
            _SMT-TMP _SMT-HSC 33 + 32 CMOVE
        ELSE
            \ bit=0: current is left
            _SMT-TMP _SMT-HSC 1 + 32 CMOVE
            OVER I 40 * 8 + + _SMT-HSC 33 + 32 CMOVE
        THEN
        _SMT-HSC 65 _SMT-TMP SHA3-256-HASH
    LOOP
    DROP
    _SMT-TMP R> SHA3-256-COMPARE ;

: SMT-VERIFY  _SMT-VERIFY ;

\ =====================================================================
\  14. SMT-DELETE — remove a leaf
\ =====================================================================

VARIABLE _smt-d-tree

: _SMT-DELETE  ( key tree -- flag )
    _smt-d-tree !
    0 _SMT-PDEPTH !

    _smt-d-tree @ _SD-ROOT + @ DUP 0= IF
        NIP 0 EXIT
    THEN

    \ Walk to leaf, recording path
    BEGIN
        DUP _smt-d-tree @ _SMT-NODE _SN-TYPE + @
        _SMT-BRANCH =
    WHILE
        DUP _SMT-PDEPTH @ CELLS _SMT-PATH + !
        _SMT-PDEPTH @ 1+ _SMT-PDEPTH !
        OVER OVER
        _smt-d-tree @ _SMT-NODE _SN-X0 + @
        _SMT-KEY-BIT
        IF
            _smt-d-tree @ _SMT-NODE _SN-X2 + @
        ELSE
            _smt-d-tree @ _SMT-NODE _SN-X1 + @
        THEN
    REPEAT                         ( key leaf-idx )

    \ Verify key match
    DUP _smt-d-tree @ _SMT-NODE _SN-FA +
    ROT >R 32 R> 32 COMPARE 0<> IF
        DROP 0 EXIT
    THEN                           ( leaf-idx )

    \ Free the leaf
    DUP _smt-d-tree @ _SMT-FREE-NODE
    _smt-d-tree @ _SD-LCNT + DUP @ 1- SWAP !

    \ If leaf was root (depth=0), tree is now empty
    _SMT-PDEPTH @ 0= IF
        0 _smt-d-tree @ _SD-ROOT + !
        -1 EXIT
    THEN

    \ Parent = last branch on path
    _SMT-PDEPTH @ 1- CELLS _SMT-PATH + @  ( parent-idx )

    \ Get sibling — the child of parent that is NOT the deleted leaf
    DUP _smt-d-tree @ _SMT-NODE _SN-X1 + @
    OVER _smt-d-tree @ _SMT-NODE _SN-X2 + @
    \ One of these is the freed leaf (now invalid), the other is sibling
    \ The freed leaf index: its node was zeroed by _SMT-FREE-NODE,
    \ so we check which child still has valid type
    OVER _smt-d-tree @ _SMT-NODE _SN-TYPE + @ _SMT-FREE = IF
        \ Left child was freed → sibling is right child
        NIP
    ELSE
        \ Right child was freed → sibling is left child
        DROP
    THEN                           ( parent-idx sibling-idx )

    \ Replace parent with sibling in grandparent (or as root)
    _SMT-PDEPTH @ 1 > IF
        \ Grandparent = path[depth-2]
        _SMT-PDEPTH @ 2 - CELLS _SMT-PATH + @  ( parent sib gp-idx )
        DUP _smt-d-tree @ _SMT-NODE _SN-X1 + @
        3 PICK = IF
            \ Parent was left child of gp
            _smt-d-tree @ _SMT-NODE _SN-X1 +
            OVER SWAP !
        ELSE
            _smt-d-tree @ _SMT-NODE _SN-X2 +
            OVER SWAP !
        THEN
    ELSE
        \ Parent was root → sibling becomes root
        DUP _smt-d-tree @ _SD-ROOT + !
    THEN                           ( parent-idx sibling-idx )
    DROP

    \ Free the parent branch
    _smt-d-tree @ _SMT-FREE-NODE

    \ Rehash (path shortened by 1)
    _SMT-PDEPTH @ 1- _SMT-PDEPTH !
    _smt-d-tree @ _SMT-REHASH-UP
    -1 ;

: SMT-DELETE  _SMT-DELETE ;

\ =====================================================================
\  15. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _smt-guard

' SMT-INIT     CONSTANT _smt-init-xt
' SMT-DESTROY  CONSTANT _smt-dest-xt
' SMT-INSERT   CONSTANT _smt-ins-xt
' SMT-LOOKUP   CONSTANT _smt-lk-xt
' SMT-DELETE   CONSTANT _smt-del-xt
' SMT-ROOT     CONSTANT _smt-root-xt
' SMT-PROVE    CONSTANT _smt-pv-xt
' SMT-VERIFY   CONSTANT _smt-vfy-xt

: SMT-INIT     _smt-init-xt   _smt-guard WITH-GUARD ;
: SMT-DESTROY  _smt-dest-xt   _smt-guard WITH-GUARD ;
: SMT-INSERT   _smt-ins-xt    _smt-guard WITH-GUARD ;
: SMT-LOOKUP   _smt-lk-xt     _smt-guard WITH-GUARD ;
: SMT-DELETE   _smt-del-xt    _smt-guard WITH-GUARD ;
: SMT-ROOT     _smt-root-xt   _smt-guard WITH-GUARD ;
: SMT-PROVE    _smt-pv-xt     _smt-guard WITH-GUARD ;
: SMT-VERIFY   _smt-vfy-xt    _smt-guard WITH-GUARD ;

\ =================================================================
\  Done.
\ =================================================================
