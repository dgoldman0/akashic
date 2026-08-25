\ =====================================================================
\  desk-apt1.f — Explicit APT-1 composition for the Akashic Desk
\ =====================================================================
\
\  This is an opt-in boot leaf, not a dependency of Desk or the ANSI
\  desktop profile.  Loading it allocates its bounded storage but does not
\  initialize a session, install an owner, negotiate, or emit terminal
\  bytes.  A profile opts in by calling APT1-DESK-RUN instead of DESK-RUN.
\
\  The capacities may be defined by the profile before REQUIRE.  The
\  bounded defaults admit the APT-1 control reserve and a complete CELL_SPAN
\  for up to 1017 columns.  Presentation scope records match Desk's current
\  maximum concurrently installed applets and remain caller-owned here.
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
REQUIRE presentation/broker.f

[UNDEFINED] APT1-DESK-RX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-RX-CAPACITY
[THEN]

[UNDEFINED] APT1-DESK-TX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-TX-CAPACITY
[THEN]

[UNDEFINED] APT1-DESK-PRES-SCOPE-COUNT [IF]
CREG-MAX-INSTANCES CONSTANT APT1-DESK-PRES-SCOPE-COUNT
[THEN]

APT1-DESK-PRES-SCOPE-COUNT PRES-SCOPE-RECORD-SIZE *
CONSTANT _A1D-PRES-SCOPE-BYTES

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

\ The rich composition, not Desk or the backend, owns every presentation
\ byte.  Padding permits an exact aligned subspan without assuming XBUF's
\ placement.  The activation descriptor is separate borrowed resolver
\ scratch and never aliases broker-owned records.
PRES-API-SIZE 7 + XBUF _A1D-PRES-API-MEM
_A1D-PRES-API-MEM 7 + -8 AND CONSTANT _A1D-PRES-API

PRES-SCOPED-BROKER-SIZE 7 + XBUF _A1D-PRES-BROKER-MEM
_A1D-PRES-BROKER-MEM 7 + -8 AND CONSTANT _A1D-PRES-BROKER

PRES-BROKER-CONFIG-SIZE 7 + XBUF _A1D-PRES-CONFIG-MEM
_A1D-PRES-CONFIG-MEM 7 + -8 AND CONSTANT _A1D-PRES-CONFIG

_A1D-PRES-SCOPE-BYTES 7 + XBUF _A1D-PRES-SCOPES-MEM
_A1D-PRES-SCOPES-MEM 7 + -8 AND CONSTANT _A1D-PRES-SCOPES

PRES-ACTIVATION-DESC-SIZE 7 + XBUF _A1D-PRES-ACTIVATION-MEM
_A1D-PRES-ACTIVATION-MEM 7 + -8 AND CONSTANT _A1D-PRES-ACTIVATION

VARIABLE _A1D-INSTALLED
VARIABLE _A1D-PRES-READY
VARIABLE _A1D-RUN-IOR
VARIABLE _A1D-UNINSTALL-S

0 _A1D-INSTALLED !
0 _A1D-PRES-READY !

\ =====================================================================
\  Exact Desk activation resolver and host callbacks
\ =====================================================================

VARIABLE _A1DR-CALLER
VARIABLE _A1DR-CONTEXT
VARIABLE _A1DR-SLOT
VARIABLE _A1DR-REGISTRY
VARIABLE _A1DR-RGN

: _A1D-PRES-LIVE-STATE?  ( state -- flag )
    DUP AHS-S-RUNNING =
    OVER AHS-S-MINIMIZED = OR
    SWAP AHS-S-FOCUSED = OR ;

: _A1D-PRES-FIND-CALLER  ( caller-instance -- slot | 0 )
    _A1DR-CALLER !
    _A1DR-CALLER @ 0= _DESK-CURRENT-STATE @ 0= OR IF 0 EXIT THEN
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-INST @ _A1DR-CALLER @ =
        OVER _SL-STATE @ _A1D-PRES-LIVE-STATE? AND IF EXIT THEN
        _SL-NEXT @
    REPEAT
    0 ;

: _A1D-PRES-DESC-BOUNDS!  ( slot -- status )
    DUP _SL-VISIBLE? IF
        _SL-RGN @ DUP 0= IF DROP PRES-S-STALE EXIT THEN
        DUP _A1DR-RGN ! DROP
        _A1DR-RGN @ RGN-ROW _A1D-PRES-ACTIVATION PRES-ACTIVATION.ROW !
        _A1DR-RGN @ RGN-COL _A1D-PRES-ACTIVATION PRES-ACTIVATION.COL !
        _A1DR-RGN @ RGN-H _A1D-PRES-ACTIVATION PRES-ACTIVATION.HEIGHT !
        _A1DR-RGN @ RGN-W _A1D-PRES-ACTIVATION PRES-ACTIVATION.WIDTH !
        -1 _A1D-PRES-ACTIVATION PRES-ACTIVATION.VISIBLE !
    ELSE
        DROP
        0 _A1D-PRES-ACTIVATION PRES-ACTIVATION.ROW !
        0 _A1D-PRES-ACTIVATION PRES-ACTIVATION.COL !
        0 _A1D-PRES-ACTIVATION PRES-ACTIVATION.HEIGHT !
        0 _A1D-PRES-ACTIVATION PRES-ACTIVATION.WIDTH !
        0 _A1D-PRES-ACTIVATION PRES-ACTIVATION.VISIBLE !
    THEN
    PRES-S-OK ;

\ Broker resolver callback.  It never dereferences an arbitrary caller until
\ pointer equality has found that caller in this live Desk's child list.
\ Registry and endpoint agreement then bind the descriptor to the exact
\ CINST ID/generation and reject closed, foreign-Desk, or stale instances.
: _A1D-PRES-RESOLVE
  ( caller-instance resolver-context -- activation-desc status )
    _A1DR-CONTEXT ! _A1DR-CALLER !
    _A1DR-CONTEXT @ _A1D-PRES-BROKER <> IF
        0 PRES-S-INVALID EXIT
    THEN
    _A1DR-CALLER @ _A1D-PRES-FIND-CALLER DUP 0= IF
        DROP 0 PRES-S-STALE EXIT
    THEN
    _A1DR-SLOT !
    _A1DR-CALLER @ CINST.ENDPOINT @ _DESK-ENDPOINT <> IF
        0 PRES-S-STALE EXIT
    THEN
    _DESK-REGISTRY @ DUP 0= IF DROP 0 PRES-S-STALE EXIT THEN
    _A1DR-REGISTRY !
    _A1DR-CALLER @ CINST.ID @ DUP 0> 0= IF
        DROP 0 PRES-S-STALE EXIT
    THEN
    _A1DR-CALLER @ CINST.GENERATION @ DUP 0> 0= IF
        2DROP 0 PRES-S-STALE EXIT
    THEN
    _A1DR-REGISTRY @ CREG-INST-FIND _A1DR-CALLER @ <> IF
        0 PRES-S-STALE EXIT
    THEN
    _A1D-PRES-ACTIVATION PRES-ACTIVATION-DESC-INIT
    _A1DR-CALLER @ CINST.ID @
        _A1D-PRES-ACTIVATION PRES-ACTIVATION.ID !
    _A1DR-CALLER @ CINST.GENERATION @
        _A1D-PRES-ACTIVATION PRES-ACTIVATION.GENERATION !
    _A1DR-SLOT @ _A1D-PRES-DESC-BOUNDS! ?DUP IF
        0 SWAP EXIT
    THEN
    _A1D-PRES-ACTIVATION DUP PRES-ACTIVATION-DESC-VALID? 0= IF
        DROP 0 PRES-S-INVALID EXIT
    THEN
    PRES-S-OK ;

VARIABLE _A1DB-CALLER
VARIABLE _A1DB-BROKER
VARIABLE _A1DB-DESC
VARIABLE _A1DB-STATUS

: _A1D-PRES-BOUNDS  ( caller-instance broker -- status )
    _A1DB-BROKER ! _A1DB-CALLER !
    _A1DB-CALLER @ _A1DB-BROKER @ _A1D-PRES-RESOLVE
    _A1DB-STATUS ! _A1DB-DESC !
    _A1DB-STATUS @ ?DUP IF EXIT THEN
    _A1DB-DESC @ PRES-ACTIVATION.ROW @
    _A1DB-DESC @ PRES-ACTIVATION.COL @
    _A1DB-DESC @ PRES-ACTIVATION.HEIGHT @
    _A1DB-DESC @ PRES-ACTIVATION.WIDTH @
    _A1DB-DESC @ PRES-ACTIVATION.VISIBLE @
    _A1DB-CALLER @ _A1DB-BROKER @ PRES-HOST-BOUNDS! ;

: _A1D-PRES-RETIRE  ( caller-instance broker -- status )
    PRES-HOST-RETIRE ;

\ =====================================================================
\  Caller-owned broker construction
\ =====================================================================

: _A1D-PRES-SETUP  ( -- status )
    _A1D-PRES-READY @ IF PRES-S-INVALID EXIT THEN
    _A1D-PRES-API PRES-BROKER-API-INIT
    _A1D-PRES-BROKER PRES-SCOPED-BROKER-INIT
    _A1D-PRES-API _A1D-PRES-BROKER PRES-SCOPED-BROKER-BIND
    DUP PRES-S-OK <> IF EXIT THEN DROP
    _A1D-PRES-CONFIG PRES-BROKER-CONFIG-INIT
    ['] _A1D-PRES-RESOLVE
        _A1D-PRES-CONFIG PRES-BROKER-C.RESOLVER-XT !
    _A1D-PRES-BROKER
        _A1D-PRES-CONFIG PRES-BROKER-C.RESOLVER-CONTEXT !
    _A1D-PRES-SCOPES
        _A1D-PRES-CONFIG PRES-BROKER-C.SCOPE-RECORDS !
    _A1D-PRES-SCOPE-BYTES
        _A1D-PRES-CONFIG PRES-BROKER-C.SCOPE-RECORD-BYTES !
    APT1-DESK-PRES-SCOPE-COUNT
        _A1D-PRES-CONFIG PRES-BROKER-C.SCOPE-RECORD-COUNT !
    \ Retained wire discovery is not implemented in this transitional slice.
    \ The broker remains globally discoverable but acquisition is unavailable.
    0 _A1D-PRES-CONFIG PRES-BROKER-C.SUPPORTED !
    _A1D-PRES-CONFIG _A1D-PRES-BROKER PRES-SERVICE-INIT
    DUP PRES-S-OK <> IF EXIT THEN DROP
    -1 _A1D-PRES-READY !
    _A1D-PRES-BROKER
    ['] _A1D-PRES-BOUNDS
    ['] _A1D-PRES-RETIRE
    _A1D-PRES-BROKER DESK-PRESENTATION-INJECT ;

\ Setup has no negotiation side effect.  ASHELL-RUN invokes the installed
\ owner's preflight/acquire callbacks only after Desk enters its lifecycle.
: _A1D-SETUP  ( -- status )
    _A1D-INSTALLED @ _A1D-PRES-READY @ OR IF SCB-S-INVALID EXIT THEN
    _A1D-RX APT1-DESK-RX-CAPACITY
    _A1D-TX APT1-DESK-TX-CAPACITY
    _A1D-EVENT PT-EVENT-SIZE _A1D-SESSION PT-INIT
    DUP PT-S-OK <> IF EXIT THEN DROP
    _A1D-SESSION _A1D-ADAPTER APTSCB-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-ADAPTER _A1D-OWNER APTAS-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-OWNER APTAS-INSTALL
    DUP SCB-S-OK <> IF EXIT THEN DROP
    TRUE _A1D-INSTALLED !
    _A1D-PRES-SETUP ;

\ This is the only release path.  APTAS-UNINSTALL performs the exact-owner,
\ shell-idle, ANSI-safe, retained-legacy, and key-source-lease checks before
\ mutating anything.  The broker is finalized only after that synchronized
\ terminal close; a refused close or a remaining live/tombstone record keeps
\ its latch and every caller-owned allocation live for retry.
: _A1D-UNINSTALL  ( -- status )
    _A1D-INSTALLED @ IF
        _A1D-OWNER APTAS-UNINSTALL
        DUP SCB-S-OK <> IF EXIT THEN DROP
        FALSE _A1D-INSTALLED !
    THEN
    _A1D-PRES-READY @ IF
        _A1D-PRES-BROKER PRES-SERVICE-FINI
        DUP PRES-S-OK <> IF EXIT THEN DROP
        FALSE _A1D-PRES-READY !
    THEN
    SCB-S-OK ;

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
