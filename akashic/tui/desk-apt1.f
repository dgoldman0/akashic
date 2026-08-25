\ =====================================================================
\  desk-apt1.f — Explicit APT-1 composition for the Akashic Desk
\ =====================================================================
\
\  This is an opt-in boot leaf, not a dependency of Desk or the ANSI
\  desktop profile.  Loading it allocates its bounded storage but does not
\  initialize a session, install an owner, negotiate, or emit terminal
\  bytes.  A profile opts in by calling APT1-DESK-RUN instead of DESK-RUN.
\
\  The two capacities may be defined by the profile before REQUIRE.  The
\  bounded defaults admit the APT-1 control reserve and a complete CELL_SPAN
\  for up to 1017 columns.
\  A wider terminal is refused before OPEN and remains on ANSI.
\
\  This leaf owns XMEM allocations made while it is sourced.  Keep it on the
\  source path unless a compiled shard has separately proved those external
\  allocations relocatable.
\
\  Prefix: APT1-DESK- (public), _A1D- (internal)

PROVIDED akashic-tui-desk-apt1

REQUIRE app-shell-apt1.f
REQUIRE applets/desk/desk.f

[UNDEFINED] APT1-DESK-RX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-RX-CAPACITY
[THEN]

[UNDEFINED] APT1-DESK-TX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-TX-CAPACITY
[THEN]

\ PT-INIT borrows all seven ranges for the lifetime of the session.  The
\ event scratch is intentionally distinct from APTAS's embedded poll event.
APT1-DESK-RX-CAPACITY XBUF _A1D-RX
APT1-DESK-TX-CAPACITY XBUF _A1D-TX
PT-EVENT-SIZE XBUF _A1D-EVENT

PT-SESSION-SIZE 7 + XBUF _A1D-SESS-MEM
_A1D-SESS-MEM 7 + -8 AND CONSTANT _A1D-SESSION

APTSCB-SIZE 7 + XBUF _A1D-SCB-MEM
_A1D-SCB-MEM 7 + -8 AND CONSTANT _A1D-ADAPTER

APTAS-SIZE 7 + XBUF _A1D-OWNER-MEM
_A1D-OWNER-MEM 7 + -8 AND CONSTANT _A1D-OWNER

VARIABLE _A1D-INSTALLED
VARIABLE _A1D-RUN-IOR
VARIABLE _A1D-UNINSTALL-S

0 _A1D-INSTALLED !

\ Setup has no negotiation side effect.  ASHELL-RUN invokes the installed
\ owner's preflight/acquire callbacks only after Desk enters its lifecycle.
: _A1D-SETUP  ( -- status )
    _A1D-INSTALLED @ IF SCB-S-INVALID EXIT THEN
    _A1D-RX APT1-DESK-RX-CAPACITY
    _A1D-TX APT1-DESK-TX-CAPACITY
    _A1D-EVENT PT-EVENT-SIZE _A1D-SESSION PT-INIT
    DUP PT-S-OK <> IF EXIT THEN DROP
    _A1D-SESSION _A1D-ADAPTER APTSCB-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-ADAPTER _A1D-OWNER APTAS-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-OWNER APTAS-INSTALL
    DUP SCB-S-OK = IF TRUE _A1D-INSTALLED ! THEN ;

\ This is the only release path.  APTAS-UNINSTALL performs the exact-owner,
\ shell-idle, ANSI-safe, retained-legacy, and key-source-lease checks before
\ mutating anything.  On refusal the installed latch and every borrowed
\ allocation remain live for retry or the required attachment reset.
: _A1D-UNINSTALL  ( -- status )
    _A1D-INSTALLED @ 0= IF SCB-S-OK EXIT THEN
    _A1D-OWNER APTAS-UNINSTALL
    DUP SCB-S-OK = IF FALSE _A1D-INSTALLED ! THEN ;

: _A1D-STATUS-THROW  ( status -- )
    -3400 SWAP - THROW ;

: _A1D-RUN-BODY  ( -- )
    _A1D-SETUP
    DUP SCB-S-OK <> IF _A1D-STATUS-THROW THEN DROP
    DESK-RUN ;

\ APT1-DESK-RUN ( -- )
\   Construct and install the optional owner, run the real Desk lifecycle,
\   then attempt only the synchronized safe uninstall.  A Desk exception is
\   preserved after cleanup.  With no primary exception, a setup or release
\   status S throws -3400-S.  A refused release deliberately leaves the
\   exact owner and its storage installed.  A caller that catches an error
\   must suppress terminal diagnostics while PT-STREAM-OWNED? remains true.
: APT1-DESK-RUN  ( -- )
    ['] _A1D-RUN-BODY CATCH _A1D-RUN-IOR !
    _A1D-UNINSTALL _A1D-UNINSTALL-S !
    _A1D-RUN-IOR @ ?DUP IF THROW THEN
    _A1D-UNINSTALL-S @ DUP SCB-S-OK <> IF
        _A1D-STATUS-THROW
    THEN DROP ;
