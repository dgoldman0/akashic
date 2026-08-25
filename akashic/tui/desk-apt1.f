\ =====================================================================
\  desk-apt1.f — Explicit APT-1 composition for the Akashic Desk
\ =====================================================================
\
\  This is an opt-in boot leaf, not a dependency of Desk or the ANSI
\  desktop profile.  Loading it allocates its bounded storage but does not
\  initialize a session, install an owner, negotiate, or emit terminal
\  bytes.  A profile opts in by calling APT1-DESK-RUN instead of DESK-RUN.
\
\  Product profiles override the six capacities before REQUIRE.  The four
\  record/copy dimensions are independent: owner tombstones, one atomic
\  retained candidate, and live UIDL bindings exhaust separately.  These
\  defaults match the current Desktop catalog's 32-entry product boundary;
\  they do not advertise retained semantics.  The host retained policy stays
\  disabled until semantic projection can admit a complete UIDL tree.
\
\  This leaf owns XMEM allocations made while it is sourced.  Keep it on the
\  source path unless a compiled shard has separately proved those external
\  allocations relocatable.
\
\  Prefix: APT1-DESK- (public), _A1D- (internal)

PROVIDED akashic-tui-desk-apt1

REQUIRE app-shell-apt1.f
REQUIRE rich-terminal/screen-adapter-apt1.f
REQUIRE rich-terminal/uidl-driver.f
REQUIRE applets/desk/desk.f

[UNDEFINED] APT1-DESK-RX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-RX-CAPACITY
[THEN]

[UNDEFINED] APT1-DESK-TX-CAPACITY [IF]
8192 CONSTANT APT1-DESK-TX-CAPACITY
[THEN]

[UNDEFINED] APT1-DESK-RTAPT-OWNER-RECORDS [IF]
32 CONSTANT APT1-DESK-RTAPT-OWNER-RECORDS
[THEN]

[UNDEFINED] APT1-DESK-RTAPT-OP-RECORDS [IF]
32 CONSTANT APT1-DESK-RTAPT-OP-RECORDS
[THEN]

[UNDEFINED] APT1-DESK-RTAPT-COPY-BYTES [IF]
2304 CONSTANT APT1-DESK-RTAPT-COPY-BYTES
[THEN]

[UNDEFINED] APT1-DESK-RTERM-BINDING-RECORDS [IF]
32 CONSTANT APT1-DESK-RTERM-BINDING-RECORDS
[THEN]

: _A1D-U32-POSITIVE?  ( u -- flag )
    DUP 0> SWAP 0xFFFFFFFF U> 0= AND ;

: _A1D-CAPACITY*  ( count item-u -- total-u )
    OVER _A1D-U32-POSITIVE? 0= ABORT" desk-apt1: invalid record count"
    UM* DUP 0<> ABORT" desk-apt1: record storage overflow" DROP ;

APT1-DESK-RTAPT-OWNER-RECORDS RTAPT-OWNER-SIZE _A1D-CAPACITY*
    CONSTANT _A1D-RTAPT-OWNERS-U
APT1-DESK-RTAPT-OP-RECORDS RTAPT-OP-SIZE _A1D-CAPACITY*
    CONSTANT _A1D-RTAPT-OPS-U
APT1-DESK-RTERM-BINDING-RECORDS RTERM-UIDL-BINDING-SIZE _A1D-CAPACITY*
    CONSTANT _A1D-UIDL-RECORDS-U

APT1-DESK-RTAPT-COPY-BYTES _A1D-U32-POSITIVE? 0=
    ABORT" desk-apt1: invalid retained copy capacity"

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

\ The concrete RTAPT engine, its unified screen publisher, and the UIDL
\ binding registry are all source-owned, aligned, pairwise separate spans.
\ Configuration and the one host-binding descriptor are call-borrowed only.
RTAPT-CONFIG-SIZE 7 + XBUF _A1D-RTAPT-CONFIG-MEM
_A1D-RTAPT-CONFIG-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-CONFIG

RTAPT-ENGINE-SIZE 7 + XBUF _A1D-RTAPT-ENGINE-MEM
_A1D-RTAPT-ENGINE-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-ENGINE

_A1D-RTAPT-OWNERS-U 7 + XBUF _A1D-RTAPT-OWNERS-MEM
_A1D-RTAPT-OWNERS-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-OWNERS

_A1D-RTAPT-OPS-U 7 + XBUF _A1D-RTAPT-OPS-MEM
_A1D-RTAPT-OPS-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-OPS

APT1-DESK-RTAPT-COPY-BYTES 7 + XBUF _A1D-RTAPT-COPY-MEM
_A1D-RTAPT-COPY-MEM 7 + -8 AND CONSTANT _A1D-RTAPT-COPY

RTAPTSCB-SIZE 7 + XBUF _A1D-RTAPTSCB-MEM
_A1D-RTAPTSCB-MEM 7 + -8 AND CONSTANT _A1D-RTAPTSCB

RTERM-UIDL-BACKEND-SIZE 7 + XBUF _A1D-UIDL-BACKEND-MEM
_A1D-UIDL-BACKEND-MEM 7 + -8 AND CONSTANT _A1D-UIDL-BACKEND

_A1D-UIDL-RECORDS-U 7 + XBUF _A1D-UIDL-RECORDS-MEM
_A1D-UIDL-RECORDS-MEM 7 + -8 AND CONSTANT _A1D-UIDL-RECORDS

RTERM-HOST-BINDING-SIZE 7 + XBUF _A1D-HOST-BINDING-MEM
_A1D-HOST-BINDING-MEM 7 + -8 AND CONSTANT _A1D-HOST-BINDING

0 CONSTANT _A1D-PHASE-COLD
1 CONSTANT _A1D-PHASE-SESSION
2 CONSTANT _A1D-PHASE-ENGINE
3 CONSTANT _A1D-PHASE-PUBLISHER
4 CONSTANT _A1D-PHASE-OWNER
5 CONSTANT _A1D-PHASE-INSTALLED

0 CONSTANT _A1D-UIDL-UNBOUND
1 CONSTANT _A1D-UIDL-BOUND

VARIABLE _A1D-PHASE
VARIABLE _A1D-UIDL-PHASE
VARIABLE _A1D-RUN-IOR
VARIABLE _A1D-DESK-IOR
VARIABLE _A1D-UNINSTALL-S

VARIABLE _A1D-HOST-CB-HOST
VARIABLE _A1D-HOST-CB-CONTEXT
VARIABLE _A1D-HOST-CB-RESULT

_A1D-PHASE-COLD _A1D-PHASE !
_A1D-UIDL-UNBOUND _A1D-UIDL-PHASE !

: _A1D-PHASE-VALID?  ( phase -- flag )
    _A1D-PHASE-INSTALLED 1+ U< ;

: _A1D-UIDL-PHASE-VALID?  ( phase -- flag )
    _A1D-UIDL-BOUND 1+ U< ;

\ Called only at the proven-cold boundary.  Large record/copy banks are
\ initialized by their checked constructors after all span preflights pass;
\ clearing only construction records here avoids redundant profile-sized work.
: _A1D-CLEAR-INERT  ( -- )
    _A1D-SESSION PT-SESSION-SIZE 0 FILL
    _A1D-ADAPTER APTSCB-SIZE 0 FILL
    _A1D-OWNER APTAS-SIZE 0 FILL
    _A1D-RTAPT-CONFIG RTAPT-CONFIG-SIZE 0 FILL
    _A1D-RTAPT-ENGINE RTAPT-ENGINE-SIZE 0 FILL
    _A1D-RTAPTSCB RTAPTSCB-SIZE 0 FILL
    _A1D-UIDL-BACKEND RTERM-UIDL-BACKEND-SIZE 0 FILL
    _A1D-HOST-BINDING RTERM-HOST-BINDING-SIZE 0 FILL
    0 _A1D-HOST-CB-HOST !
    0 _A1D-HOST-CB-CONTEXT !
    0 _A1D-HOST-CB-RESULT !
    _A1D-UIDL-UNBOUND _A1D-UIDL-PHASE !
    _A1D-PHASE-COLD _A1D-PHASE ! ;

\ Setup has no negotiation side effect.  ASHELL-RUN invokes the installed
\ owner's preflight/acquire callbacks only after Desk enters its lifecycle.
\ A phase is published only after that constructor has succeeded, so the one
\ release path can retry without clearing uncertain live state.
: _A1D-SETUP  ( -- status )
    _A1D-PHASE @ _A1D-PHASE-COLD <> IF SCB-S-INVALID EXIT THEN
    _A1D-UIDL-PHASE @ _A1D-UIDL-UNBOUND <> IF SCB-S-INVALID EXIT THEN
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
    _A1D-RTAPT-COPY APT1-DESK-RTAPT-COPY-BYTES
    _A1D-RTAPT-CONFIG RTAPT-CONFIG-INIT
    DUP RTAPT-S-OK <> IF EXIT THEN DROP

    _A1D-RTAPT-CONFIG _A1D-RTAPT-ENGINE RTAPT-INIT
    DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-ENGINE _A1D-PHASE !

    _A1D-SESSION _A1D-RTAPT-ENGINE _A1D-RTAPTSCB RTAPTSCB-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-RTAPTSCB _A1D-ADAPTER RTAPTSCB-ATTACH
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-PUBLISHER _A1D-PHASE !

    _A1D-ADAPTER _A1D-OWNER APTAS-INIT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _A1D-PHASE-OWNER _A1D-PHASE !

    _A1D-OWNER APTAS-INSTALL
    DUP SCB-S-OK = IF _A1D-PHASE-INSTALLED _A1D-PHASE ! THEN ;

\ Desk invokes this after constructing the exact AHOST and before autostart.
\ Publish the partial-init phase before any fallible work: Desk's paired fini
\ is then sufficient for every refusal or caught throw.
: _A1D-HOST-INIT-BODY  ( -- )
    _A1D-HOST-CB-CONTEXT @ _A1D-UIDL-BACKEND <> IF
        RTERM-S-INVALID _A1D-HOST-CB-RESULT ! EXIT
    THEN
    _A1D-PHASE @ _A1D-PHASE-INSTALLED <> IF
        RTERM-S-INVALID _A1D-HOST-CB-RESULT ! EXIT
    THEN
    _A1D-UIDL-PHASE @ _A1D-UIDL-UNBOUND <> IF
        RTERM-S-INVALID _A1D-HOST-CB-RESULT ! EXIT
    THEN
    _A1D-UIDL-BOUND _A1D-UIDL-PHASE !
    _A1D-HOST-BINDING RTERM-HOST-BINDING-INIT

    _A1D-HOST-CB-HOST @
    _A1D-UIDL-RECORDS _A1D-UIDL-RECORDS-U
    _A1D-UIDL-BACKEND RTERM-UIDL-INIT
    DUP _A1D-HOST-CB-RESULT !
    RTERM-S-OK <> IF EXIT THEN

    _A1D-UIDL-BACKEND RTERM-UIDL-INSTALL
    DUP _A1D-HOST-CB-RESULT !
    RTERM-S-OK <> IF EXIT THEN

    ['] RTERM-AHOST-UIDL-READY _A1D-HOST-BINDING
    _A1D-HOST-CB-HOST @ AHOST-UIDL-READY!
    RTERM-S-OK _A1D-HOST-CB-RESULT ! ;

: _A1D-HOST-INIT  ( host context -- ior )
    _A1D-HOST-CB-CONTEXT ! _A1D-HOST-CB-HOST !
    RTERM-S-INVALID _A1D-HOST-CB-RESULT !
    ['] _A1D-HOST-INIT-BODY CATCH ?DUP IF
        DROP RTERM-S-INVALID _A1D-HOST-CB-RESULT !
    THEN
    _A1D-HOST-CB-RESULT @
    0 _A1D-HOST-CB-HOST !
    0 _A1D-HOST-CB-CONTEXT !
    0 _A1D-HOST-CB-RESULT ! ;

\ RTERM-UIDL-FINI first proves that no binding still borrows this AHOST.
\ Only then is the host callback cleared and its pointer-free descriptor
\ restored.  Every refusal leaves the complete retry authority installed.
: _A1D-HOST-FINI-BODY  ( -- )
    _A1D-HOST-CB-CONTEXT @ _A1D-UIDL-BACKEND <> IF
        RTERM-S-INVALID _A1D-HOST-CB-RESULT ! EXIT
    THEN
    _A1D-PHASE @ _A1D-PHASE-INSTALLED <> IF
        RTERM-S-INVALID _A1D-HOST-CB-RESULT ! EXIT
    THEN
    _A1D-UIDL-PHASE @ _A1D-UIDL-PHASE-VALID? 0= IF
        RTERM-S-INVALID _A1D-HOST-CB-RESULT ! EXIT
    THEN
    _A1D-UIDL-BACKEND RTERM-UIDL-FINI
    DUP _A1D-HOST-CB-RESULT !
    RTERM-S-OK <> IF EXIT THEN

    0 0 _A1D-HOST-CB-HOST @ AHOST-UIDL-READY!
    _A1D-HOST-BINDING RTERM-HOST-BINDING-INIT
    _A1D-UIDL-UNBOUND _A1D-UIDL-PHASE !
    RTERM-S-OK _A1D-HOST-CB-RESULT ! ;

: _A1D-HOST-FINI  ( host context -- ior )
    _A1D-HOST-CB-CONTEXT ! _A1D-HOST-CB-HOST !
    RTERM-S-INVALID _A1D-HOST-CB-RESULT !
    ['] _A1D-HOST-FINI-BODY CATCH ?DUP IF
        DROP RTERM-S-INVALID _A1D-HOST-CB-RESULT !
    THEN
    _A1D-HOST-CB-RESULT @
    0 _A1D-HOST-CB-HOST !
    0 _A1D-HOST-CB-CONTEXT !
    0 _A1D-HOST-CB-RESULT ! ;

\ This is the only product release path.  A live UIDL composition is a hard
\ pre-uninstall gate.  APTAS then proves exact-owner, shell-idle, ANSI-safe,
\ retained-legacy, and key-source state before RTAPT may erase its ledgers.
\ Every refusal preserves its current phase and all remaining storage.
: _A1D-UNINSTALL  ( -- status )
    _A1D-PHASE @ _A1D-PHASE-VALID? 0= IF SCB-S-INVALID EXIT THEN
    _A1D-UIDL-PHASE @ _A1D-UIDL-PHASE-VALID? 0= IF
        SCB-S-INVALID EXIT
    THEN
    _A1D-UIDL-PHASE @ _A1D-UIDL-UNBOUND <> IF
        RTERM-S-WOULD-BLOCK EXIT
    THEN
    _A1D-PHASE @ _A1D-PHASE-COLD = IF SCB-S-OK EXIT THEN

    _A1D-PHASE @ _A1D-PHASE-INSTALLED = IF
        _A1D-OWNER APTAS-UNINSTALL
        DUP SCB-S-OK <> IF EXIT THEN DROP
        _A1D-PHASE-OWNER _A1D-PHASE !
    THEN

    _A1D-PHASE @ _A1D-PHASE-ENGINE U< 0= IF
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
    ['] _A1D-HOST-INIT ['] _A1D-HOST-FINI _A1D-UIDL-BACKEND
        DESK-HOST-LIFECYCLE!
    ['] DESK-RUN CATCH _A1D-DESK-IOR !
    \ The tuple is a constructor input.  A quarantined Desk retains its
    \ per-instance copy; disarm only future plain DESK-RUN constructors.
    0 0 0 DESK-HOST-LIFECYCLE!
    _A1D-DESK-IOR @
    0 _A1D-DESK-IOR !
    ?DUP IF THROW THEN ;

\ APT1-DESK-RUN ( -- )
\   Construct the session, unified CELL/retained publisher, optional UIDL
\   driver, and exact terminal owner, then run the real Desk lifecycle.
\   Cleanup preserves a primary Desk exception.  With no primary exception,
\   setup or release status S throws -3400-S.  A refused release deliberately
\   leaves the exact phase and storage live.  A caller that catches an error
\   must suppress terminal diagnostics while PT-STREAM-OWNED? remains true.
: APT1-DESK-RUN  ( -- )
    ['] _A1D-RUN-BODY CATCH _A1D-RUN-IOR !
    _A1D-UNINSTALL _A1D-UNINSTALL-S !
    _A1D-RUN-IOR @ ?DUP IF THROW THEN
    _A1D-UNINSTALL-S @ DUP SCB-S-OK <> IF
        _A1D-STATUS-THROW
    THEN DROP ;
