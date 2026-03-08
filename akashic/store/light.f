\ =================================================================
\  light.f  —  Light Client Protocol
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: LC-  / _LC-
\  Depends on: state.f block.f merkle.f sha3.f fmt.f
\
\  Merkle proof generation and verification for light clients.
\  A light client holds only block headers and verifies account
\  state against the state root using authentication paths from
\  the 256-leaf SHA3-256 Merkle tree.
\
\  Public API:
\   LC-STATE-PROOF  ( addr proof -- depth | 0 )
\       Generate Merkle proof for an account.
\       addr  = 32-byte account address
\       proof = buffer (>= 256 bytes) to receive auth path
\       Returns depth (8) on success, 0 if account not found.
\
\   LC-STATE-LEAF   ( addr leaf -- idx | -1 )
\       Find an account, hash its entry into leaf buffer.
\       addr = 32-byte account address
\       leaf = 32-byte buffer to receive leaf hash
\       Returns leaf index or -1 if not found.
\
\   LC-VERIFY-STATE ( leaf idx proof depth root -- flag )
\       Verify a state Merkle proof.
\       leaf  = 32-byte leaf hash
\       idx   = leaf index in tree
\       proof = auth path (depth × 32 bytes)
\       depth = tree depth (8 for 256-leaf)
\       root  = 32-byte expected root
\       Returns TRUE if valid.
\
\   LC-STATE-ROOT-AT ( height -- addr | 0 )
\       Return pointer to state root in block header at height.
\       Returns 0 if block not in ring buffer.
\
\   LC-BLOCK-HEADER ( height -- blk | 0 )
\       Return pointer to block header at height.
\       Alias for CHAIN-BLOCK@.
\
\   LC-DEPTH        ( -- 8 )
\       Proof depth for the 256-leaf state tree.
\
\  Proof format: depth × 32 bytes, bottom-to-top (sibling hashes).
\  For the 256-leaf state tree, depth = 8, proof = 256 bytes.
\
\  Not reentrant.
\ =================================================================

REQUIRE state.f
REQUIRE block.f
REQUIRE ../math/merkle.f
REQUIRE ../math/sha3.f

PROVIDED akashic-light

\ =====================================================================
\  1. Constants
\ =====================================================================

8 CONSTANT LC-DEPTH              \ log2(256) = 8

\ =====================================================================
\  2. Scratch buffers
\ =====================================================================

CREATE _LC-LEAF  32 ALLOT        \ leaf hash scratch
CREATE _LC-ROOT  32 ALLOT        \ root hash scratch

\ =====================================================================
\  3. LC-STATE-LEAF — find account, hash entry, return index
\ =====================================================================
\  ( addr leaf -- idx | -1 )
\    addr = 32-byte account address
\    leaf = 32-byte buffer to receive SHA3-256(entry)
\  Returns sorted index in state table, or -1 if not found.

VARIABLE _LC-SL-LEAF

: _LC-STATE-LEAF  ( addr leaf -- idx | -1 )
    _LC-SL-LEAF !
    _ST-BSEARCH IF                        \ ( idx )  — found
        DUP _ST-ENTRY ST-ENTRY-SIZE       \ ( idx entry-addr 72 )
        _LC-SL-LEAF @ SHA3-256-HASH       \ hash entry → leaf buf
    ELSE
        DROP -1                           \ not found
    THEN ;

: LC-STATE-LEAF  ( addr leaf -- idx | -1 )
    _LC-STATE-LEAF ;

\ =====================================================================
\  4. LC-STATE-PROOF — generate Merkle proof for account
\ =====================================================================
\  ( addr proof -- depth | 0 )
\    addr  = 32-byte account address
\    proof = buffer (>= 256 bytes)
\  Steps:
\    1. Rebuild Merkle tree (ensures consistency)
\    2. Find account index via binary search
\    3. Generate auth path via MERKLE-OPEN
\  Returns depth (8) on success, 0 if account not found.

VARIABLE _LC-SP-ADDR
VARIABLE _LC-SP-PROOF

: _LC-STATE-PROOF  ( addr proof -- depth | 0 )
    _LC-SP-PROOF !
    _LC-SP-ADDR !
    \ Rebuild tree to ensure fresh state
    _ST-REBUILD-TREE
    \ Find account
    _LC-SP-ADDR @ _ST-BSEARCH 0= IF
        DROP 0 EXIT                       \ not found
    THEN
    \ ( idx )  Generate auth path
    _ST-TREE _LC-SP-PROOF @ MERKLE-OPEN ; \ returns depth

: LC-STATE-PROOF  ( addr proof -- depth | 0 )
    _LC-STATE-PROOF ;

\ =====================================================================
\  5. LC-VERIFY-STATE — verify a state Merkle proof
\ =====================================================================
\  ( leaf idx proof depth root -- flag )
\  Thin wrapper around MERKLE-VERIFY.

: LC-VERIFY-STATE  ( leaf idx proof depth root -- flag )
    MERKLE-VERIFY ;

\ =====================================================================
\  6. LC-STATE-ROOT-AT — state root from block header at height
\ =====================================================================
\  ( height -- addr | 0 )
\  Returns pointer to 32-byte state root in block header,
\  or 0 if block not available in ring buffer.

: LC-STATE-ROOT-AT  ( height -- addr | 0 )
    CHAIN-BLOCK@ DUP 0= IF EXIT THEN
    BLK-STATE-ROOT@ ;

\ =====================================================================
\  7. LC-BLOCK-HEADER — block header at height
\ =====================================================================
\  ( height -- blk | 0 )
\  Alias for CHAIN-BLOCK@.

: LC-BLOCK-HEADER  ( height -- blk | 0 )
    CHAIN-BLOCK@ ;

\ =====================================================================
\  8. Concurrency guard
\ =====================================================================
\  LC-STATE-PROOF calls _ST-REBUILD-TREE (which calls guarded
\  MERKLE-LEAF! and MERKLE-BUILD) then MERKLE-OPEN (guarded).
\  We need our own guard to ensure atomicity of the whole sequence:
\  rebuild + search + open must not interleave with state mutations.

REQUIRE ../concurrency/guard.f
GUARD _lc-guard

' LC-STATE-PROOF   CONSTANT _lc-sp-xt
' LC-STATE-LEAF    CONSTANT _lc-sl-xt
' LC-VERIFY-STATE  CONSTANT _lc-vs-xt
' LC-STATE-ROOT-AT CONSTANT _lc-sra-xt
' LC-BLOCK-HEADER  CONSTANT _lc-bh-xt

: LC-STATE-PROOF   _lc-sp-xt   _lc-guard WITH-GUARD ;
: LC-STATE-LEAF    _lc-sl-xt   _lc-guard WITH-GUARD ;
: LC-VERIFY-STATE  _lc-vs-xt   _lc-guard WITH-GUARD ;
: LC-STATE-ROOT-AT _lc-sra-xt  _lc-guard WITH-GUARD ;
: LC-BLOCK-HEADER  _lc-bh-xt   _lc-guard WITH-GUARD ;

\ =================================================================
\  Done.
\ =================================================================
