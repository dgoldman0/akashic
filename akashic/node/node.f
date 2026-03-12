\ =================================================================
\  node.f  —  Node Daemon (main loop tying everything together)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: NODE-  / _NODE-
\  Depends on: mempool.f gossip.f sync.f persist.f rpc.f
\              block.f consensus.f state.f server.f guard.f
\
\  The node daemon initialises all sub-systems and runs the main
\  loop.  Each iteration:
\   1. GSP-POLL      — receive gossip messages
\   2. SYNC-STEP     — issue deferred block requests
\   3. SRV-STEP      — accept one HTTP connection (if any)
\   4. NODE-PRODUCE  — produce a block if due
\   5. NODE-PERSIST  — save new blocks periodically
\
\  Public API:
\   NODE-INIT   ( port -- )  initialise all sub-systems
\   NODE-RUN    ( -- )       main loop (runs until NODE-STOP)
\   NODE-STOP   ( -- )       signal main loop to exit + cleanup
\   NODE-STEP   ( -- )       one iteration (for testing)
\   NODE-STATUS ( -- state ) 0=stopped 1=running 2=syncing
\ =================================================================

REQUIRE ../store/mempool.f
REQUIRE ../net/gossip.f
REQUIRE ../net/sync.f
REQUIRE ../store/persist.f
REQUIRE ../web/rpc.f
REQUIRE ../store/block.f
REQUIRE ../consensus/consensus.f
REQUIRE ../store/state.f
REQUIRE ../web/server.f

PROVIDED akashic-node

\ =====================================================================
\  1. Constants
\ =====================================================================

0 CONSTANT NODE-STOPPED
1 CONSTANT NODE-RUNNING
2 CONSTANT NODE-SYNCING

\ =====================================================================
\  2. Storage
\ =====================================================================

VARIABLE _NODE-STATE                    \ daemon state
VARIABLE _NODE-PORT                     \ HTTP port

\ Block production  [FIX D03] time-based interval
VARIABLE _NODE-PRODUCE?                 \ -1 = produce blocks, 0 = relay only
VARIABLE _NODE-BLK-INTERVAL             \ seconds between block production
VARIABLE _NODE-LAST-PRODUCE-T           \ epoch of last production attempt

\ Persistence
VARIABLE _NODE-LAST-SAVED               \ last persisted chain height

\ [FIX P32] TX pointer buffer for MP-DRAIN → BLK-ADD-TX
CREATE _NODE-TX-PTRS  BLK-MAX-TXS CELLS ALLOT

\ =====================================================================
\  3. NODE-INIT — initialise all sub-systems
\ =====================================================================

: NODE-INIT  ( port -- )
    _NODE-PORT !
    \ State
    NODE-STOPPED _NODE-STATE !
    0  _NODE-PRODUCE? !
    10 _NODE-BLK-INTERVAL !
    0  _NODE-LAST-PRODUCE-T !
    0  _NODE-LAST-SAVED !
    \ Sub-systems
    ST-INIT
    MP-INIT
    GSP-INIT
    SYNC-INIT
    PST-INIT
    ROUTE-CLEAR
    RPC-INIT
    _NODE-PORT @ SRV-INIT ;

\ =====================================================================
\  4. Block production (optional)
\ =====================================================================

CREATE _NODE-BLK BLK-STRUCT-SIZE ALLOT
CREATE _NODE-HTMP 32 ALLOT

: NODE-ENABLE-PRODUCE   ( -- )  -1 _NODE-PRODUCE? ! ;
: NODE-DISABLE-PRODUCE  ( -- )   0 _NODE-PRODUCE? ! ;

: _NODE-PRODUCE-BLOCK  ( -- )
    _NODE-PRODUCE? @ 0= IF EXIT THEN
    \ Only produce if synced
    SYNC-STATUS SYNC-IDLE <> IF EXIT THEN
    MP-COUNT 0= IF EXIT THEN           \ nothing to produce
    \ Build block
    _NODE-BLK BLK-INIT
    CHAIN-HEIGHT 1+ _NODE-BLK BLK-SET-HEIGHT
    CHAIN-HEAD _NODE-HTMP BLK-HASH
    _NODE-HTMP _NODE-BLK BLK-SET-PREV
    \ [FIX P34] Real timestamp from RTC
    DT-NOW-S _NODE-BLK BLK-SET-TIME
    \ [FIX P32] Drain mempool into temp buffer, then BLK-ADD-TX each
    MP-COUNT BLK-MAX-TXS MIN           ( n-to-drain )
    _NODE-TX-PTRS MP-DRAIN             ( actual )
    0 ?DO
        _NODE-TX-PTRS I CELLS + @      ( tx-ptr )
        _NODE-BLK BLK-ADD-TX DROP
    LOOP
    \ Finalize: compute roots, apply txs to state
    _NODE-BLK BLK-FINALIZE
    \ Seal with consensus proof
    _NODE-BLK CON-SEAL
    \ Append to chain
    _NODE-BLK CHAIN-APPEND IF
        \ Save to log & broadcast
        _NODE-BLK PST-SAVE-BLOCK DROP
        _NODE-BLK GSP-BROADCAST-BLK
        MP-RELEASE                      \ free drained slots
    THEN ;

\ =====================================================================
\  5. Persistence tick  [FIX P35] wired into NODE-STEP
\ =====================================================================

: _NODE-PERSIST-TICK  ( -- )
    CHAIN-HEIGHT _NODE-LAST-SAVED @ > IF
        CHAIN-HEAD PST-SAVE-BLOCK DROP
        CHAIN-HEIGHT _NODE-LAST-SAVED !
    THEN ;

\ =====================================================================
\  6. NODE-STEP — one main loop iteration
\ =====================================================================

: NODE-STEP  ( -- )
    GSP-POLL                           \ receive gossip
    SYNC-STEP                          \ deferred block requests
    SRV-STEP                           \ [FIX P33] accept HTTP connection
    _NODE-PERSIST-TICK                 \ [FIX P35] save new blocks
    \ [FIX D03] Time-based block production
    DT-NOW-S DUP _NODE-LAST-PRODUCE-T @ -
    _NODE-BLK-INTERVAL @ >= IF
        _NODE-LAST-PRODUCE-T !
        _NODE-PRODUCE-BLOCK
    ELSE
        DROP
    THEN ;

\ =====================================================================
\  7. Yield helper  [FIX P36]
\ =====================================================================
\  Busy-wait for at least ms milliseconds using DT-NOW-MS.
\  Prevents the main loop from consuming 100% CPU.

: _NODE-YIELD  ( ms -- )
    DT-NOW-MS +                        ( deadline )
    BEGIN DUP DT-NOW-MS > WHILE REPEAT DROP ;

\ =====================================================================
\  8. NODE-RUN / NODE-STOP
\ =====================================================================

: NODE-STOP  ( -- )
    NODE-STOPPED _NODE-STATE !
    \ [FIX P37] Graceful shutdown
    PST-SAVE-STATE DROP                \ flush state snapshot
    PST-CLOSE                          \ close persistence files
    \ Disconnect all gossip peers
    GSP-MAX-PEERS 0 ?DO
        I GSP-DISCONNECT
    LOOP
    \ Zeroize signing key  [A05]
    _CON-SIGN-PRIV 64 0 FILL
    SERVE-STOP ;

: NODE-RUN  ( -- )
    NODE-RUNNING _NODE-STATE !
    DT-NOW-S _NODE-LAST-PRODUCE-T !   \ [FIX D03] seed production timer
    BEGIN
        _NODE-STATE @ NODE-STOPPED <>
    WHILE
        \ Update state to reflect sync status
        SYNC-STATUS SYNC-ACTIVE = IF
            NODE-SYNCING _NODE-STATE !
        ELSE
            _NODE-STATE @ NODE-STOPPED <> IF
                NODE-RUNNING _NODE-STATE !
            THEN
        THEN
        NODE-STEP
        1 _NODE-YIELD                 \ [FIX P36] ~1 ms yield
    REPEAT ;

\ =====================================================================
\  9. Public queries
\ =====================================================================

: NODE-STATUS  ( -- state )  _NODE-STATE @ ;

\ =====================================================================
\  10. Concurrency guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _node-guard

' NODE-INIT CONSTANT _node-init-xt
' NODE-STEP CONSTANT _node-step-xt
' NODE-STOP CONSTANT _node-stop-xt

: NODE-INIT _node-init-xt _node-guard WITH-GUARD ;
: NODE-STEP _node-step-xt _node-guard WITH-GUARD ;
: NODE-STOP _node-stop-xt _node-guard WITH-GUARD ;
[THEN] [THEN]

\ =================================================================
\  Done.
\ =================================================================
