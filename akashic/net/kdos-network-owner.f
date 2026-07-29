\ =====================================================================
\  kdos-network-owner.f - Machine-wide KDOS network ownership boundary
\ =====================================================================
\  KDOS exposes machine-global NIC receive, transmit, TCP, and TLS state.
\  This core-0-only exact-token gate serializes transports which operate that
\  state.  Tokens are compared but never dereferenced.  The owner remains
\  retained until its transport proves lower detachment and releases it.
\ =====================================================================

PROVIDED akashic-kdos-net-owner

0 CONSTANT KDOSNET-S-OK
1 CONSTANT KDOSNET-S-INVALID
2 CONSTANT KDOSNET-S-BUSY
3 CONSTANT KDOSNET-S-NOT-OWNER
4 CONSTANT KDOSNET-S-PLATFORM

VARIABLE _KDOSNET-OWNER
0 _KDOSNET-OWNER !

: KDOSNET-OWNER@  ( -- token | 0 )
    _KDOSNET-OWNER @ ;

: KDOSNET-OWNER?  ( token -- flag )
    DUP 0<> SWAP KDOSNET-OWNER@ = AND ;

: KDOSNET-OPERATE?  ( token -- flag )
    COREID 0= SWAP KDOSNET-OWNER? AND ;

: KDOSNET-CLAIM  ( token -- status )
    COREID 0<> IF DROP KDOSNET-S-PLATFORM EXIT THEN
    DUP 0= IF DROP KDOSNET-S-INVALID EXIT THEN
    _KDOSNET-OWNER @ IF DROP KDOSNET-S-BUSY EXIT THEN
    _KDOSNET-OWNER !
    KDOSNET-S-OK ;

: KDOSNET-RELEASE  ( token -- status )
    COREID 0<> IF DROP KDOSNET-S-PLATFORM EXIT THEN
    DUP 0= IF DROP KDOSNET-S-INVALID EXIT THEN
    _KDOSNET-OWNER @ OVER <> IF
        DROP KDOSNET-S-NOT-OWNER EXIT
    THEN
    DROP 0 _KDOSNET-OWNER !
    KDOSNET-S-OK ;
