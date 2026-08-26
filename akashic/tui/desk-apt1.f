\ =====================================================================
\  desk-apt1.f — Explicit APT-1 composition for the Akashic Desk
\ =====================================================================
\
\  This is an opt-in boot leaf, not a dependency of Desk or the ANSI
\  desktop profile.  Loading it allocates its bounded storage but does not
\  initialize a session, install an owner, negotiate, or emit terminal
\  bytes.  A profile opts in by calling APT1-DESK-RUN instead of DESK-RUN.
\
\  Product profiles may override the four public bounds before REQUIRE.
\  Maximum screen geometry derives the one retained owner, operation ledger,
\  copy bank, and final-screen plan exactly; lower layers do not acquire a
\  second product capacity policy.
\
\  This leaf owns XMEM allocations made while it is sourced.  Keep it on the
\  source path unless a compiled shard has separately proved those external
\  allocations relocatable.
\
\  Prefix: APT1-DESK- (public), _A1D- (internal)

PROVIDED akashic-tui-desk-apt1

REQUIRE app-shell-apt1.f
REQUIRE rich-terminal/screen-adapter-apt1.f
REQUIRE rich-terminal/engine-apt1.f
REQUIRE rich-terminal/screen-plane.f
REQUIRE applets/desk/desk.f

[UNDEFINED] APT1-DESK-RX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-RX-CAPACITY
[THEN]

[UNDEFINED] APT1-DESK-TX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-TX-CAPACITY
[THEN]

[UNDEFINED] APT1-DESK-MAX-COLS [IF]
400 CONSTANT APT1-DESK-MAX-COLS
[THEN]

[UNDEFINED] APT1-DESK-MAX-ROWS [IF]
200 CONSTANT APT1-DESK-MAX-ROWS
[THEN]

: _A1D-U32-POSITIVE?  ( u -- flag )
    DUP 0> SWAP 0xFFFFFFFF U> 0= AND ;

: _A1D-CAPACITY*  ( count item-u -- total-u )
    OVER _A1D-U32-POSITIVE? 0= ABORT" desk-apt1: invalid capacity"
    DUP _A1D-U32-POSITIVE? 0= ABORT" desk-apt1: invalid item size"
    UM* DUP 0<> ABORT" desk-apt1: storage size overflow" DROP
    DUP _A1D-U32-POSITIVE? 0=
        ABORT" desk-apt1: invalid storage size" ;

: _A1D-CAPACITY+  ( a b -- total-u )
    OVER _A1D-U32-POSITIVE? 0= ABORT" desk-apt1: invalid capacity"
    DUP _A1D-U32-POSITIVE? 0= ABORT" desk-apt1: invalid item size"
    OVER + DUP ROT U< ABORT" desk-apt1: storage size overflow"
    DUP _A1D-U32-POSITIVE? 0=
        ABORT" desk-apt1: invalid storage size" ;

: _A1D-ALIGNMENT-SLOP+  ( payload-u -- allocation-u )
    DUP _A1D-U32-POSITIVE? 0=
        ABORT" desk-apt1: invalid storage size"
    7 _A1D-CAPACITY+ ;

\ Resolve every caller-controlled calculation before the first XBUF.  At a
\ C-cell maximum surface the engine needs one owner, C+1 operations, and a
\ 72+128C copy span; the producer needs one 120-byte plan item per cell.
APT1-DESK-RX-CAPACITY _A1D-U32-POSITIVE? 0=
    ABORT" desk-apt1: invalid receive capacity"
APT1-DESK-TX-CAPACITY _A1D-U32-POSITIVE? 0=
    ABORT" desk-apt1: invalid transmit capacity"

APT1-DESK-MAX-COLS APT1-DESK-MAX-ROWS _A1D-CAPACITY*
    CONSTANT _A1D-SCREEN-CELLS
1 RTAPT-OWNER-SIZE _A1D-CAPACITY*
    CONSTANT _A1D-RTAPT-OWNERS-U
_A1D-SCREEN-CELLS 1 _A1D-CAPACITY+
    CONSTANT _A1D-RTAPT-OP-RECORDS
_A1D-RTAPT-OP-RECORDS RTAPT-OP-SIZE _A1D-CAPACITY*
    CONSTANT _A1D-RTAPT-OPS-U
_A1D-SCREEN-CELLS 128 _A1D-CAPACITY*
    72 _A1D-CAPACITY+
    CONSTANT _A1D-RTAPT-COPY-U
_A1D-SCREEN-CELLS RTE-GLYPH-RUN-PLAN-ITEM-SIZE _A1D-CAPACITY*
    CONSTANT _A1D-SCREEN-PLAN-U

1 CONSTANT _A1D-SCREEN-OWNER-ID
1 CONSTANT _A1D-SCREEN-OWNER-GENERATION
1 CONSTANT _A1D-SCREEN-REGION-ID
1 CONSTANT _A1D-SCREEN-FIRST-OBJECT-ID

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

\ The concrete engine, neutral facade, unified screen publisher, and screen
\ producer are source-owned aligned spans.  Constructors own initialization
\ of their large banks; this leaf owns only their XMEM lifetime.
RTAPT-CONFIG-SIZE 7 + XBUF _A1D-RTAPT-CONFIG-MEM
_A1D-RTAPT-CONFIG-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-CONFIG

RTAPT-ENGINE-SIZE 7 + XBUF _A1D-RTAPT-ENGINE-MEM
_A1D-RTAPT-ENGINE-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-ENGINE

RTE-FACADE-SIZE 7 + XBUF _A1D-RTE-FACADE-MEM
_A1D-RTE-FACADE-MEM 7 + -8 AND CONSTANT _A1D-RTE-FACADE

_A1D-RTAPT-OWNERS-U _A1D-ALIGNMENT-SLOP+
    XBUF _A1D-RTAPT-OWNERS-MEM
_A1D-RTAPT-OWNERS-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-OWNERS

_A1D-RTAPT-OPS-U _A1D-ALIGNMENT-SLOP+
    XBUF _A1D-RTAPT-OPS-MEM
_A1D-RTAPT-OPS-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-OPS

_A1D-RTAPT-COPY-U _A1D-ALIGNMENT-SLOP+
    XBUF _A1D-RTAPT-COPY-MEM
_A1D-RTAPT-COPY-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-COPY

RTAPTSCB-SIZE 7 + XBUF _A1D-RTAPTSCB-MEM
_A1D-RTAPTSCB-MEM 7 + -8 AND CONSTANT _A1D-RTAPTSCB

RTSCREEN-SIZE 7 + XBUF _A1D-SCREEN-MEM
_A1D-SCREEN-MEM 7 + -8 AND CONSTANT _A1D-SCREEN

_A1D-SCREEN-PLAN-U _A1D-ALIGNMENT-SLOP+
    XBUF _A1D-SCREEN-PLAN-MEM
_A1D-SCREEN-PLAN-MEM 7 + -8 AND CONSTANT _A1D-SCREEN-PLAN

0 CONSTANT _A1D-PHASE-COLD
1 CONSTANT _A1D-PHASE-SESSION
2 CONSTANT _A1D-PHASE-ENGINE
3 CONSTANT _A1D-PHASE-FACADE
4 CONSTANT _A1D-PHASE-PUBLISHER
5 CONSTANT _A1D-PHASE-OWNER
6 CONSTANT _A1D-PHASE-INSTALLED

VARIABLE _A1D-PHASE
VARIABLE _A1D-RUN-IOR
VARIABLE _A1D-UNINSTALL-S

\ A failed Desk run is torn down to ANSI before its exception escapes.  Keep
\ fixed-length snapshots of the three rich records that identify the failing
\ composition phase.  Their top-level addresses survive cleanup, which may
\ then erase the live components without erasing the attached host's evidence.
CREATE _A1D-FAILURE-PUBLISHER RTAPTSCB-SIZE ALLOT
CREATE _A1D-FAILURE-SCREEN RTSCREEN-SIZE ALLOT
CREATE _A1D-FAILURE-ENGINE RTAPT-ENGINE-SIZE ALLOT
VARIABLE _A1D-FAILURE-VALID
VARIABLE _A1D-FAILURE-IOR
VARIABLE _A1D-FAILURE-PHASE
VARIABLE _A1D-FAILURE-PUBLISHER-A
VARIABLE _A1D-FAILURE-SCREEN-A
VARIABLE _A1D-FAILURE-ENGINE-A

_A1D-FAILURE-PUBLISHER _A1D-FAILURE-PUBLISHER-A !
_A1D-FAILURE-SCREEN _A1D-FAILURE-SCREEN-A !
_A1D-FAILURE-ENGINE _A1D-FAILURE-ENGINE-A !

_A1D-PHASE-COLD _A1D-PHASE !

: _A1D-PHASE-VALID?  ( phase -- flag )
    _A1D-PHASE-INSTALLED 1+ U< ;

\ Called only at the proven-cold boundary.  Large engine banks are initialized
\ by RTAPT-INIT, and RTSCREEN overwrites every reachable plan item before use;
\ clearing only fixed construction records avoids redundant surface-sized
\ work and deliberately leaves the plan bank untouched.
: _A1D-CLEAR-INERT  ( -- )
    _A1D-SESSION PT-SESSION-SIZE 0 FILL
    _A1D-ADAPTER APTSCB-SIZE 0 FILL
    _A1D-OWNER APTAS-SIZE 0 FILL
    _A1D-RTAPT-CONFIG RTAPT-CONFIG-SIZE 0 FILL
    _A1D-RTAPT-ENGINE RTAPT-ENGINE-SIZE 0 FILL
    _A1D-RTE-FACADE RTE-FACADE-SIZE 0 FILL
    _A1D-RTAPTSCB RTAPTSCB-SIZE 0 FILL
    _A1D-SCREEN RTSCREEN-SIZE 0 FILL
    _A1D-PHASE-COLD _A1D-PHASE ! ;

\ Setup has no negotiation side effect.  ASHELL-RUN invokes the installed
\ owner's preflight/acquire callbacks only after Desk enters its lifecycle.
\ A phase is published only after that constructor has succeeded, so the one
\ release path can retry without clearing uncertain live state.
: _A1D-SETUP  ( -- status )
    _A1D-PHASE @ _A1D-PHASE-COLD <> IF SCB-S-INVALID EXIT THEN
    0 _A1D-FAILURE-VALID !
    0 _A1D-FAILURE-IOR !
    _A1D-PHASE-COLD _A1D-FAILURE-PHASE !
    _A1D-CLEAR-INERT

    _A1D-RX APT1-DESK-RX-CAPACITY
    _A1D-TX APT1-DESK-TX-CAPACITY
    _A1D-EVENT PT-EVENT-SIZE _A1D-SESSION PT-INIT
    DUP PT-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-SESSION _A1D-PHASE !

    _A1D-SESSION _A1D-ADAPTER APTSCB-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP

    _A1D-SESSION
    _A1D-RTAPT-OWNERS _A1D-RTAPT-OWNERS-U
    _A1D-RTAPT-OPS _A1D-RTAPT-OPS-U
    _A1D-RTAPT-COPY _A1D-RTAPT-COPY-U
    _A1D-RTAPT-CONFIG RTAPT-CONFIG-INIT
    DUP RTAPT-S-OK <> IF EXIT THEN DROP

    _A1D-RTAPT-CONFIG _A1D-RTAPT-ENGINE RTAPT-INIT
    DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-ENGINE _A1D-PHASE !

    _A1D-RTAPT-ENGINE _A1D-RTE-FACADE RTAPTE-INIT
    DUP RTE-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-FACADE _A1D-PHASE !

    _A1D-SESSION _A1D-RTAPT-ENGINE _A1D-RTAPTSCB RTAPTSCB-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-RTAPTSCB _A1D-ADAPTER RTAPTSCB-ATTACH
    DUP SCB-S-OK <> IF EXIT THEN DROP

    _A1D-RTE-FACADE
    _A1D-SCREEN-PLAN _A1D-SCREEN-PLAN-U
    _A1D-SCREEN-OWNER-ID _A1D-SCREEN-OWNER-GENERATION
    _A1D-SCREEN-REGION-ID _A1D-SCREEN-FIRST-OBJECT-ID
    _A1D-SCREEN RTSCREEN-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP

    _A1D-SCREEN RTSCREEN-SIZE
    APT1-DESK-MAX-COLS
    ['] RTSCREEN-STEP ['] RTSCREEN-PREPARE
    _A1D-RTAPTSCB RTAPTSCB-OUTPUT-PRODUCER!
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-PUBLISHER _A1D-PHASE !

    _A1D-ADAPTER _A1D-OWNER APTAS-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-OWNER _A1D-PHASE !

    _A1D-OWNER APTAS-INSTALL
    DUP SCB-S-OK = IF _A1D-PHASE-INSTALLED _A1D-PHASE ! THEN ;

\ This is the only product release path.  APTAS first proves exact-owner,
\ shell-idle, ANSI-safe, pending-output, and key-source state before the
\ facade and engine ledgers may be erased.  Every refusal preserves its
\ current phase and all remaining storage.
: _A1D-UNINSTALL  ( -- status )
    _A1D-PHASE @ _A1D-PHASE-VALID? 0= IF SCB-S-INVALID EXIT THEN
    _A1D-PHASE @ _A1D-PHASE-COLD = IF SCB-S-OK EXIT THEN

    _A1D-PHASE @ _A1D-PHASE-INSTALLED = IF
        _A1D-OWNER APTAS-UNINSTALL
        DUP SCB-S-OK <> IF EXIT THEN DROP
        _A1D-PHASE-OWNER _A1D-PHASE !
    THEN

    _A1D-PHASE @ _A1D-PHASE-FACADE U< 0= IF
        _A1D-RTE-FACADE RTAPTE-FINI
        DUP RTE-S-OK <> IF EXIT THEN DROP
        _A1D-PHASE-ENGINE _A1D-PHASE !
    THEN

    _A1D-PHASE @ _A1D-PHASE-ENGINE = IF
        _A1D-RTAPT-ENGINE RTAPT-FINI
        DUP RTAPT-S-OK <> IF EXIT THEN DROP
        _A1D-PHASE-SESSION _A1D-PHASE !
    THEN

    _A1D-CLEAR-INERT
    SCB-S-OK ;

: _A1D-STATUS-THROW  ( status -- )
    -3400 SWAP - THROW ;

: _A1D-RUN-BODY  ( -- )
    _A1D-SETUP
    DUP SCB-S-OK <> IF _A1D-STATUS-THROW THEN DROP
    DESK-RUN ;

: _A1D-CAPTURE-FAILURE  ( -- )
    _A1D-RUN-IOR @ DUP _A1D-FAILURE-IOR !
    0= IF EXIT THEN
    _A1D-PHASE @ _A1D-FAILURE-PHASE !
    _A1D-RTAPTSCB _A1D-FAILURE-PUBLISHER RTAPTSCB-SIZE MOVE
    _A1D-SCREEN _A1D-FAILURE-SCREEN RTSCREEN-SIZE MOVE
    _A1D-RTAPT-ENGINE _A1D-FAILURE-ENGINE RTAPT-ENGINE-SIZE MOVE
    -1 _A1D-FAILURE-VALID ! ;

\ APT1-DESK-RUN ( -- )
\   Construct the session, unified CELL/rich publisher, final-screen producer,
\   and exact terminal owner, then run the ordinary Desk lifecycle.  Cleanup
\   preserves a primary Desk exception.  With no primary exception, setup or
\   release status S throws -3400-S.  A refused release deliberately leaves
\   the exact phase and storage live.  A caller that catches an error must
\   suppress terminal diagnostics while PT-STREAM-OWNED? remains true.
: APT1-DESK-RUN  ( -- )
    ['] _A1D-RUN-BODY CATCH _A1D-RUN-IOR !
    _A1D-CAPTURE-FAILURE
    _A1D-UNINSTALL _A1D-UNINSTALL-S !
    _A1D-RUN-IOR @ ?DUP IF THROW THEN
    _A1D-UNINSTALL-S @ DUP SCB-S-OK <> IF
        _A1D-STATUS-THROW
    THEN DROP ;
