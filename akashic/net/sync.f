\ =================================================================
\  sync.f  —  Block Synchronisation
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SYNC-  / _SYNC-
\  Depends on: block.f gossip.f guard.f
\
\  Gap-driven sequential sync.  Detects when the local chain is
\  behind a peer, then requests missing blocks one at a time.
\  Full block bodies (header + txs) are decoded via BLK-DECODE
\  which includes B06 tx parsing.  [FIX B05: resolved by B06.]
\
\  Design:
\   - Callbacks from gossip (announcement / response / status)
\     only update state and set a deferred-request flag.
\   - SYNC-STEP (called from the main loop) performs the actual
\     network request, avoiding re-entry into the gossip guard.
\
\  States:
\   SYNC-IDLE    — fully synced, waiting for announcements
\   SYNC-ACTIVE  — actively requesting / processing blocks
\   SYNC-STALLED — too many retries, needs manual reset
\
\  Public API:
\   SYNC-INIT     ( -- )                wire callbacks, reset state
\   SYNC-STEP     ( -- )                make next request if needed
\   SYNC-RESET    ( -- )                force back to IDLE
\   SYNC-STATUS   ( -- state )          current sync state
\   SYNC-TARGET   ( -- height )         height we are syncing to
\   SYNC-PEER     ( -- id )             peer we are syncing from
\   SYNC-PROGRESS ( -- current target ) pair for monitoring
\ =================================================================

REQUIRE ../store/block.f
REQUIRE ../net/gossip.f
REQUIRE ../concurrency/guard.f

PROVIDED akashic-sync

\ =====================================================================
\  1. Constants
\ =====================================================================

0 CONSTANT SYNC-IDLE
1 CONSTANT SYNC-ACTIVE
2 CONSTANT SYNC-STALLED

5 CONSTANT _SYNC-MAX-RETRY             \ retry limit per peer
3 CONSTANT _SYNC-MAX-FALLBACK          \ max peer changes  [FIX C03]

\ =====================================================================
\  2. Storage
\ =====================================================================

VARIABLE _SYNC-STATE
VARIABLE _SYNC-TARGET                   \ peer-reported chain height
VARIABLE _SYNC-PEER                     \ peer id we're syncing from
VARIABLE _SYNC-RETRIES
VARIABLE _SYNC-NEED-REQ                 \ deferred-request flag
VARIABLE _SYNC-FALLBACKS                \ [FIX C03] peer changes so far

CREATE _SYNC-BLK BLK-STRUCT-SIZE ALLOT \ temp block struct for decode

\ [FIX C03] Find next active peer after current one (round-robin).
\ Returns peer-id or -1 if none found.
: _SYNC-NEXT-PEER  ( -- id | -1 )
    GSP-MAX-PEERS 0 ?DO
        _SYNC-PEER @ 1+ I + GSP-MAX-PEERS MOD
        DUP _GSP-ACTIVE + C@ IF
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    -1 ;

\ [FIX C03] Try switching to a fallback peer instead of stalling.
\ Returns TRUE if we found an alternate peer, FALSE if no peers left.
: _SYNC-TRY-FALLBACK  ( -- flag )
    _SYNC-FALLBACKS @ _SYNC-MAX-FALLBACK >= IF 0 EXIT THEN
    _SYNC-NEXT-PEER DUP -1 = IF DROP 0 EXIT THEN
    _SYNC-PEER !
    0 _SYNC-RETRIES !
    1 _SYNC-FALLBACKS +!
    -1 _SYNC-NEED-REQ !
    -1 ;

\ =====================================================================
\  3. SYNC-STEP — deferred block request (main-loop safe)
\ =====================================================================

: SYNC-STEP  ( -- )
    _SYNC-STATE @ SYNC-ACTIVE <> IF EXIT THEN
    _SYNC-NEED-REQ @ 0= IF EXIT THEN
    0 _SYNC-NEED-REQ !
    CHAIN-HEIGHT 1+                    ( next-height )
    DUP _SYNC-TARGET @ > IF
        DROP SYNC-IDLE _SYNC-STATE !
        EXIT
    THEN
    _SYNC-PEER @ GSP-REQUEST-BLK ;

\ =====================================================================
\  4. Response handler (wired to GSP-ON-BLK-RSP-XT)
\ =====================================================================

: _SYNC-ON-RSP  ( buf len -- )
    _SYNC-STATE @ SYNC-ACTIVE <> IF 2DROP EXIT THEN
    \ Decode header into temp block
    _SYNC-BLK BLK-INIT
    _SYNC-BLK BLK-DECODE               ( flag )
    0= IF
        \ Decode failed — retry or try fallback  [FIX C03]
        1 _SYNC-RETRIES +!
        _SYNC-RETRIES @ _SYNC-MAX-RETRY >= IF
            _SYNC-TRY-FALLBACK 0= IF
                SYNC-STALLED _SYNC-STATE !
            THEN
        ELSE
            -1 _SYNC-NEED-REQ !
        THEN
        EXIT
    THEN
    \ Try to append to chain (validates + applies state)
    _SYNC-BLK CHAIN-APPEND             ( flag )
    IF
        \ Success — check if done
        0 _SYNC-RETRIES !
        CHAIN-HEIGHT _SYNC-TARGET @ >= IF
            SYNC-IDLE _SYNC-STATE !
        ELSE
            -1 _SYNC-NEED-REQ !        \ request next block
        THEN
    ELSE
        \ Append failed — retry or try fallback  [FIX C03]
        1 _SYNC-RETRIES +!
        _SYNC-RETRIES @ _SYNC-MAX-RETRY >= IF
            _SYNC-TRY-FALLBACK 0= IF
                SYNC-STALLED _SYNC-STATE !
            THEN
        ELSE
            -1 _SYNC-NEED-REQ !
        THEN
    THEN ;

\ =====================================================================
\  5. Announcement handler (wired to GSP-ON-BLK-ANN-XT)
\ =====================================================================

: _SYNC-ON-ANN  ( height peer -- )
    \ Ignore if we're already at or past that height
    OVER CHAIN-HEIGHT <= IF 2DROP EXIT THEN
    \ If already syncing, update target only if higher
    _SYNC-STATE @ SYNC-ACTIVE = IF
        OVER _SYNC-TARGET @ > IF
            _SYNC-PEER ! _SYNC-TARGET !
        ELSE
            2DROP
        THEN
        EXIT
    THEN
    \ Start syncing
    _SYNC-PEER ! _SYNC-TARGET !
    0 _SYNC-RETRIES !
    0 _SYNC-FALLBACKS !                  \ [FIX C03]
    SYNC-ACTIVE _SYNC-STATE !
    -1 _SYNC-NEED-REQ ! ;

\ =====================================================================
\  6. Status handler (wired to GSP-ON-STATUS-XT)
\ =====================================================================

: _SYNC-ON-STATUS  ( height peer -- )
    _SYNC-ON-ANN ;                     \ identical logic

\ =====================================================================
\  7. SYNC-INIT — wire callbacks, reset state
\ =====================================================================

: SYNC-INIT  ( -- )
    SYNC-IDLE  _SYNC-STATE !
    0          _SYNC-TARGET !
    -1         _SYNC-PEER !
    0          _SYNC-RETRIES !
    0          _SYNC-NEED-REQ !
    0          _SYNC-FALLBACKS !       \ [FIX C03]
    ['] _SYNC-ON-ANN    GSP-ON-BLK-ANN-XT !
    ['] _SYNC-ON-RSP    GSP-ON-BLK-RSP-XT !
    ['] _SYNC-ON-STATUS GSP-ON-STATUS-XT ! ;

\ =====================================================================
\  8. SYNC-RESET — force back to IDLE
\ =====================================================================

: SYNC-RESET  ( -- )
    SYNC-IDLE _SYNC-STATE !
    0 _SYNC-RETRIES !
    0 _SYNC-NEED-REQ !
    0 _SYNC-FALLBACKS ! ;             \ [FIX C03]

\ =====================================================================
\  9. Public queries
\ =====================================================================

: SYNC-STATUS   ( -- state )  _SYNC-STATE @ ;
: SYNC-TARGET   ( -- height ) _SYNC-TARGET @ ;
: SYNC-PEER     ( -- id )     _SYNC-PEER @ ;
: SYNC-PROGRESS ( -- cur tgt ) CHAIN-HEIGHT _SYNC-TARGET @ ;

\ =====================================================================
\  10. Concurrency guard
\ =====================================================================

GUARD _sync-guard

' SYNC-INIT  CONSTANT _sync-init-xt
' SYNC-STEP  CONSTANT _sync-step-xt
' SYNC-RESET CONSTANT _sync-reset-xt

: SYNC-INIT  _sync-init-xt  _sync-guard WITH-GUARD ;
: SYNC-STEP  _sync-step-xt  _sync-guard WITH-GUARD ;
: SYNC-RESET _sync-reset-xt _sync-guard WITH-GUARD ;

\ =================================================================
\  Done.
\ =================================================================
