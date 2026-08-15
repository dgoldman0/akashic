\ =====================================================================
\  kdos-network-owner.f - Machine-wide KDOS network ownership boundary
\ =====================================================================
\  KDOS exposes machine-global NIC receive, transmit, TCP, and TLS state.
\  This core-0-only exact-token gate serializes transports which operate that
\  state.  Tokens are compared but never dereferenced.  Callers may hold an
\  explicit lease across a lower lifetime or use KDOSNET-WITH for one guarded
\  stack-neutral operation with exact release and separate diagnostics.
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

: KDOSNET-WITH  ( token xt -- claim-status throw release-status )
    DUP 0= IF 2DROP KDOSNET-S-INVALID 0 0 EXIT THEN
    OVER KDOSNET-CLAIM DUP IF
        >R 2DROP R> 0 0 EXIT
    THEN
    DROP
    SWAP >R CATCH
    R> KDOSNET-RELEASE
    0 -ROT ;
