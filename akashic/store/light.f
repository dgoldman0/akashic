\ =================================================================
\  light.f  —  Light Client Protocol
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: LC-  / _LC-
\  Depends on: state.f block.f smt.f sha3.f fmt.f
\
\  SMT proof generation and verification for light clients.
\  A light client holds only block headers and verifies account
\  state against the state root using inclusion proofs from the
\  Sparse Merkle Tree (smt.f).
\
\  Public API:
\   LC-STATE-PROOF  ( addr proof -- len | 0 )
\       Generate SMT proof for an account.
\       addr  = 32-byte account address
\       proof = buffer (>= 10240 bytes) to receive proof data
\       Returns number of proof entries on success, 0 if not found.
\
\   LC-STATE-LEAF   ( addr leaf -- flag )
\       Find an account, hash its entry into leaf buffer.
\       addr = 32-byte account address
\       leaf = 32-byte buffer to receive entry hash
\       Returns TRUE (-1) if found, FALSE (0) if not.
\
\   LC-VERIFY-STATE ( key leaf proof len root -- flag )
\       Verify a state SMT proof.
\       key   = 32-byte account address
\       leaf  = 32-byte entry hash (SHA3-256 of 72-byte entry)
\       proof = proof data from LC-STATE-PROOF
\       len   = number of proof entries
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
\  Proof format: len × 40 bytes (8B bit-pos + 32B sibling hash),
\  ordered root-to-leaf.  Variable length depending on tree depth.
\
\  Not reentrant.
\ =================================================================

REQUIRE state.f
REQUIRE block.f
REQUIRE ../math/sha3.f

PROVIDED akashic-light

\ =====================================================================
\  1. Scratch buffers
\ =====================================================================

CREATE _LC-LEAF  32 ALLOT        \ leaf hash scratch
CREATE _LC-ROOT  32 ALLOT        \ root hash scratch

\ =====================================================================
\  2. LC-STATE-LEAF — find account, hash entry, return flag
\ =====================================================================
\  ( addr leaf -- flag )
\    addr = 32-byte account address
\    leaf = 32-byte buffer to receive SHA3-256(entry)
\  Returns TRUE if found, FALSE if not.

VARIABLE _LC-SL-LEAF

: _LC-STATE-LEAF  ( addr leaf -- flag )
    _LC-SL-LEAF !
    _ST-BSEARCH IF                        \ ( idx )  — found
        _ST-ENTRY ST-ENTRY-SIZE           \ ( entry-addr 72 )
        _LC-SL-LEAF @ SHA3-256-HASH       \ hash entry → leaf buf
        -1
    ELSE
        DROP 0                            \ not found
    THEN ;

: LC-STATE-LEAF  ( addr leaf -- flag )
    _LC-STATE-LEAF ;

\ =====================================================================
\  3. LC-STATE-PROOF — generate SMT proof for account
\ =====================================================================
\  ( addr proof -- len | 0 )
\    addr  = 32-byte account address
\    proof = buffer (>= 10240 bytes)
\  Steps:
\    1. Rebuild SMT (ensures consistency)
\    2. Generate inclusion proof via SMT-PROVE
\  Returns number of proof entries on success, 0 if not found.

: _LC-STATE-PROOF  ( addr proof -- len | 0 )
    >R
    _ST-REBUILD-TREE
    R> _ST-SMT SWAP SMT-PROVE ;

: LC-STATE-PROOF  ( addr proof -- len | 0 )
    _LC-STATE-PROOF ;

\ =====================================================================
\  4. LC-VERIFY-STATE — verify a state SMT proof
\ =====================================================================
\  ( key leaf proof len root -- flag )
\  key  = 32-byte account address
\  leaf = 32-byte entry hash
\  Thin wrapper around SMT-VERIFY.

: LC-VERIFY-STATE  ( key leaf proof len root -- flag )
    SMT-VERIFY ;

\ =====================================================================
\  5. LC-STATE-ROOT-AT — state root from block header at height
\ =====================================================================
\  ( height -- addr | 0 )
\  Returns pointer to 32-byte state root in block header,
\  or 0 if block not available in ring buffer.

: LC-STATE-ROOT-AT  ( height -- addr | 0 )
    CHAIN-BLOCK@ DUP 0= IF EXIT THEN
    BLK-STATE-ROOT@ ;

\ =====================================================================
\  6. LC-BLOCK-HEADER — block header at height
\ =====================================================================
\  ( height -- blk | 0 )
\  Alias for CHAIN-BLOCK@.

: LC-BLOCK-HEADER  ( height -- blk | 0 )
    CHAIN-BLOCK@ ;

\ =====================================================================
\  7. Concurrency guard
\ =====================================================================
\  LC-STATE-PROOF calls _ST-REBUILD-TREE then SMT-PROVE (both
\  acquire their own guards via re-entrant nesting).
\  We need our own guard to ensure atomicity of the whole sequence:
\  rebuild + prove must not interleave with state mutations.

[DEFINED] GUARDED [IF] GUARDED [IF]
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
[THEN] [THEN]

\ =================================================================
\  Done.
\ =================================================================
