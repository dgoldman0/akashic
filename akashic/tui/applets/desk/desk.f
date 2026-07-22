\ =================================================================
\  desk.f — TUI Multi-App Desktop (APP-DESC Application)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: DESK- / _DESK-
\  Depends on: akashic-tui-app-shell, akashic-tui-applet-host,
\              akashic-tui-app-desc,
\              akashic-tui-uidl-tui, akashic-tui-screen,
\              akashic-tui-region, akashic-tui-draw,
\              akashic-tui-keys, akashic-liraq-uidl
\
\  Multi-app desktop with dynamic tiling.  Runs as a normal
\  APP-DESC app inside app-shell.f — no private event loop.
\
\
\  Tiling algorithm:
\    Given N visible apps and usable area W × H:
\    - cols = ceil(sqrt(N)), rows = ceil(N / cols)  (V-pref)
\    - rows = ceil(sqrt(N)), cols = ceil(N / rows)  (H-pref)
\    - tile-w = (W - (cols-1)) / cols, tile-h = (H - (rows-1)) / rows
\    - remainder to last col/row
\    - 1-cell dividers between adjacent tiles
\    - Taskbar occupies the bottom row
\
\  Public API:
\    DESK-LAUNCH       ( desc -- id )  Launch sub-app, return slot ID
\    DESK-CLOSE-ID     ( id -- )       Close sub-app by ID
\    DESK-REQUEST-CLOSE-ID ( id reason -- decision )  Negotiate/close
\    DESK-FOCUS-ID     ( id -- )       Focus sub-app by ID
\    DESK-MINIMIZE-ID  ( id -- )       Minimize by ID
\    DESK-RESTORE      ( -- )          Restore last minimized
\    DESK-FULLFRAME!   ( flag -- )     Toggle full-frame focused
\    DESK-TOGGLE-VH    ( -- )          Toggle V/H tiling pref
\    DESK-RELAYOUT     ( -- )          Recompute tile grid
\    DESK-SLOT-COUNT   ( -- n )        Number of live slots
\    DESK-VCOUNT       ( -- n )        Number of visible slots
\    DESK-AGENT-SOURCE! ( source -- )   Transfer provider source before run
\    DESK-AGENT-ACCESS-PRESET! ( preset -- status ) Select access before run
\    DESK-AGENT-ACCESS ( -- profile|0 ) Current Desk-owned Agent scope
\    DESK-PRACTICE     ( -- head | 0 )  Active validated Practice head
\    DESK-CONTEXT      ( -- ctx | 0 )   Active root Context
\    DESK-RECOVERY?    ( -- flag )      Fail-closed recovery mode
\    DESK-CATALOG      ( -- catalog|0 ) Installed app catalog
\    DESK-TRY-LAUNCH   ( desc -- id ior ) Transactional sub-app launch
\    DESK-QUEUE-BUILTIN ( desc flags -- ) Bind built-in before run
\    DESK-QUEUE-LAUNCH ( desc -- )     Set startup applet (before DESK-RUN)
\    DESK-PACKAGE-RESOLVER! ( xt context -- ) Set lazy package resolver
\    DESK-PACKAGE-RELEASER! ( xt context -- ) Set descriptor releaser
\    DESK-RUN          ( -- )          Fill desc, call ASHELL-RUN
\ =================================================================

PROVIDED akashic-tui-desk

REQUIRE ../../app-shell.f
REQUIRE ../../applet-host/host.f
REQUIRE ../../app-desc.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../screen.f
REQUIRE ../../region.f
REQUIRE ../../draw.f
REQUIRE ../../keys.f
REQUIRE ../../color.f
REQUIRE ../../widgets/prompt.f
REQUIRE ../../app-catalog.f
REQUIRE ../../app-loader.f
REQUIRE ../../app-builder.f
REQUIRE ../../../utils/toml.f
REQUIRE ../../../liraq/uidl.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../runtime/practice-activation.f
REQUIRE ../../../runtime/resource-registry.f
REQUIRE ../../../interop/endpoint.f
REQUIRE ../../../interop/intent.f
REQUIRE ../../../interop/job.f
REQUIRE ../../../net/tls-trust-registry.f
REQUIRE ../../../net/external-io.f
REQUIRE ../../../interop/capability-facet.f
REQUIRE ../daybook/shared-document.f
REQUIRE agent-access-policy.f

\ =====================================================================
\  §1 — Host Slot Compatibility Views
\ =====================================================================
\
\  The generic host owns allocation and lifecycle. Desk keeps these aliases
\  for its layout/chrome code and focused compatibility fixtures.
\
\  State values:
\    0 = empty (should not appear in live list)
\    1 = running (visible, not focused)
\    2 = minimized (alive but hidden)
\    3 = focused (visible + receives input)

AHS-SIZE CONSTANT _SLOT-SZ

AHS-S-EMPTY     CONSTANT _ST-EMPTY
AHS-S-RUNNING   CONSTANT _ST-RUNNING
AHS-S-MINIMIZED CONSTANT _ST-MINIMIZED
AHS-S-FOCUSED   CONSTANT _ST-FOCUSED

CREATE DESK-COMP-DESC COMP-DESC ALLOT
CREATE DESK-DESC      APP-DESC ALLOT

\ Slot field access helpers  ( slot-addr -- field-addr )
: _SL-DESC     ( sa -- a ) AHS.DESC ;
: _SL-INST     ( sa -- a ) AHS.INST ;
: _SL-RGN      ( sa -- a ) AHS.RGN ;
: _SL-STATE    ( sa -- a ) AHS.STATE ;
: _SL-UCTX     ( sa -- a ) AHS.UCTX ;
: _SL-HAS-UIDL ( sa -- a ) AHS.HAS-UIDL ;
: _SL-NEXT     ( sa -- a ) AHS.NEXT ;
: _SL-ID       ( sa -- a ) AHS.ID ;
: _SL-UIDL-BUF ( sa -- a ) AHS.UIDL-BUF ;
: _SL-DIRTY    ( sa -- a ) AHS.DIRTY ;
: _SL-SEEN-REV ( sa -- a ) AHS.SEEN-REV ;

: _SL-VISIBLE?  ( sa -- flag ) AHS-VISIBLE? ;
: _SL-ALIVE?    ( sa -- flag ) AHS-ALIVE? ;

\ =====================================================================
\  §2 — DESK Global State
\ =====================================================================
\
\  Simplified from compositor: no _COMP-RUNNING, _COMP-DIRTY,
\  _COMP-TICK-MS, _COMP-LAST-TICK — the shell owns all of those.

VARIABLE _DESK-CURRENT-STATE
0 _DESK-CURRENT-STATE !
CMP-LAYOUT-BEGIN

_DESK-CURRENT-STATE AHOST-SIZE CMP-FIELD: _DESK-HOST

: _DESK-HEAD        ( -- a ) _DESK-HOST AHOST.HEAD ;
: _DESK-FOCUS-SA    ( -- a ) _DESK-HOST AHOST.FOCUS ;
: _DESK-NEXT-ID     ( -- a ) _DESK-HOST AHOST.NEXT-ID ;
: _DESK-LAST-MIN-SA ( -- a ) _DESK-HOST AHOST.LAST-MIN ;

_DESK-CURRENT-STATE CMP-CELL: _DESK-VH         \ tiling preference
_DESK-CURRENT-STATE CMP-CELL: _DESK-FULLFRAME

\ Active UIDL context tracking lives in the shell.
\ Desk delegates via ASHELL-CTX-SWITCH.

\ Pre-instance constructor inputs.  These are consumed by DESK-INIT-CB;
\ live Desk state is instance-relative below.
VARIABLE _DESK-CFG-A   VARIABLE _DESK-CFG-L
0 _DESK-CFG-A !  0 _DESK-CFG-L !
VARIABLE _DESK-PENDING-AGENT-SOURCE
0 _DESK-PENDING-AGENT-SOURCE !
VARIABLE _DESK-PENDING-AGENT-ACCESS
AAP-PRESET-CHAT-ONLY _DESK-PENDING-AGENT-ACCESS !

\ Built-ins are constructor inputs, like the startup queue.  Each entry is
\ (APP-DESC, default catalog flags).  DESK-QUEUE-LAUNCH also registers its
\ descriptor here so existing boot profiles acquire catalog entries without
\ changing their startup behavior.
32 CONSTANT _DESK-BUILTIN-MAX
16 CONSTANT _DESK-BUILTIN-SZ
CREATE _DESK-BUILTIN-BUF _DESK-BUILTIN-MAX _DESK-BUILTIN-SZ * ALLOT
VARIABLE _DESK-BUILTIN-N
0 _DESK-BUILTIN-N !

ACAT-F-ENABLED ACAT-F-PINNED OR ACAT-F-AUTOSTART OR ACAT-F-BUILTIN OR
CONSTANT _DESK-BUILTIN-DEFAULT-FLAGS

VARIABLE _DESK-PENDING-RESOLVER-XT
VARIABLE _DESK-PENDING-RESOLVER-CTX
VARIABLE _DESK-PENDING-RELEASER-XT
VARIABLE _DESK-PENDING-RELEASER-CTX
0 _DESK-PENDING-RESOLVER-XT !
0 _DESK-PENDING-RESOLVER-CTX !
0 _DESK-PENDING-RELEASER-XT !
0 _DESK-PENDING-RELEASER-CTX !

: _DESK-BUILTIN-ENTRY  ( index -- a )
    _DESK-BUILTIN-SZ * _DESK-BUILTIN-BUF + ;

VARIABLE _DBQ-DESC
VARIABLE _DBQ-FLAGS

: _DESK-QUEUE-BUILTIN-RAW  ( desc flags -- )
    _DBQ-FLAGS ! _DBQ-DESC !
    _DESK-BUILTIN-N @ 0 ?DO
        I _DESK-BUILTIN-ENTRY @ _DBQ-DESC @ = IF UNLOOP EXIT THEN
    LOOP
    _DESK-BUILTIN-N @ _DESK-BUILTIN-MAX >= IF EXIT THEN
    _DESK-BUILTIN-N @ _DESK-BUILTIN-ENTRY DUP >R
    _DBQ-DESC @ R@ ! _DBQ-FLAGS @ R> 8 + !
    1 _DESK-BUILTIN-N +! ;

\ Startup applets: set via DESK-QUEUE-LAUNCH before DESK-RUN.
\ DESK-INIT-CB launches them after the screen & region are ready.
8 CONSTANT _DESK-PEND-MAX
512 CONSTANT _DESK-AGENT-PROMPT-CAP
CREATE _DESK-PEND-BUF  _DESK-PEND-MAX CELLS ALLOT
VARIABLE _DESK-PEND-N
0 _DESK-PEND-N !

_DESK-CURRENT-STATE CMP-CELL: _DESK-BG-DIRTY
_DESK-CURRENT-STATE CMP-CELL: _DESK-LAST-W
_DESK-CURRENT-STATE CMP-CELL: _DESK-LAST-H

\ =====================================================================
\  §2b — Theme
\ =====================================================================
\  14 colour slots used by the taskbar, dividers, hotbar, and clock.
\  _DESK-THEME-DEFAULTS sets a dark-blue palette.  _DESK-LOAD-THEME
\  overrides any slot that appears in [desk.theme] of a TOML config.

_DESK-CURRENT-STATE CMP-CELL: _DTH-TBAR-FG
_DESK-CURRENT-STATE CMP-CELL: _DTH-TBAR-BG
_DESK-CURRENT-STATE CMP-CELL: _DTH-TBAR-ATTR
_DESK-CURRENT-STATE CMP-CELL: _DTH-ACT-FG
_DESK-CURRENT-STATE CMP-CELL: _DTH-ACT-BG
_DESK-CURRENT-STATE CMP-CELL: _DTH-ACT-ATTR
_DESK-CURRENT-STATE CMP-CELL: _DTH-MIN-FG
_DESK-CURRENT-STATE CMP-CELL: _DTH-MIN-BG
_DESK-CURRENT-STATE CMP-CELL: _DTH-PIN-FG
_DESK-CURRENT-STATE CMP-CELL: _DTH-PIN-BG
_DESK-CURRENT-STATE CMP-CELL: _DTH-DIV-FG
_DESK-CURRENT-STATE CMP-CELL: _DTH-DIV-BG
_DESK-CURRENT-STATE CMP-CELL: _DTH-CLOCK-FG
_DESK-CURRENT-STATE CMP-CELL: _DTH-CLOCK-BG
_DESK-CURRENT-STATE CMP-CELL: _DTH-DESK-BG

: _DESK-THEME-DEFAULTS  ( -- )
    15 _DTH-TBAR-FG !   17 _DTH-TBAR-BG !   0 _DTH-TBAR-ATTR !
     0 _DTH-ACT-FG  !   12 _DTH-ACT-BG  !   1 _DTH-ACT-ATTR  !
     8 _DTH-MIN-FG  !   17 _DTH-MIN-BG  !
   244 _DTH-PIN-FG  !    0 _DTH-PIN-BG  !
   240 _DTH-DIV-FG  !    0 _DTH-DIV-BG  !
    14 _DTH-CLOCK-FG !  17 _DTH-CLOCK-BG !
    17 _DTH-DESK-BG ! ;
\ Helper: try to load a colour key from a TOML table into a variable.
: _DTH-TRY  ( tbl-a tbl-l key-a key-l var -- )
    >R TOML-KEY?
    IF   TOML-GET-STRING TUI-PARSE-COLOR
         IF R> ! EXIT THEN DROP
    ELSE 2DROP
    THEN R> DROP ;

: _DESK-LOAD-THEME  ( toml-a toml-l -- )
    S" desk.theme" TOML-FIND-TABLE?
    0= IF 2DROP EXIT THEN
    2DUP S" taskbar-fg"     _DTH-TBAR-FG   _DTH-TRY
    2DUP S" taskbar-bg"     _DTH-TBAR-BG   _DTH-TRY
    2DUP S" active-fg"      _DTH-ACT-FG    _DTH-TRY
    2DUP S" active-bg"      _DTH-ACT-BG    _DTH-TRY
    2DUP S" minimized-fg"   _DTH-MIN-FG    _DTH-TRY
    2DUP S" minimized-bg"   _DTH-MIN-BG    _DTH-TRY
    2DUP S" pinned-fg"      _DTH-PIN-FG    _DTH-TRY
    2DUP S" pinned-bg"      _DTH-PIN-BG    _DTH-TRY
    2DUP S" divider-fg"     _DTH-DIV-FG    _DTH-TRY
    2DUP S" divider-bg"     _DTH-DIV-BG    _DTH-TRY
    2DUP S" clock-fg"       _DTH-CLOCK-FG  _DTH-TRY
    2DUP S" clock-bg"       _DTH-CLOCK-BG  _DTH-TRY
         S" desk-bg"        _DTH-DESK-BG   _DTH-TRY ;

\ =====================================================================
\  §2c — Hotbar (Pinned App Entries)
\ =====================================================================
\  Each entry: label string, file path, descriptor word name, slot-id.
\  Strings are zero-copy pointers into the TOML buffer.
\  slot-id = 0 means not yet launched; >0 = active desk slot.

 0 CONSTANT _HB-LBL-A   8 CONSTANT _HB-LBL-U
16 CONSTANT _HB-FILE-A  24 CONSTANT _HB-FILE-U
32 CONSTANT _HB-DESC-A  40 CONSTANT _HB-DESC-U
48 CONSTANT _HB-SLOT
56 CONSTANT _HB-SZ
12 CONSTANT _HB-MAX
32 CONSTANT _DESK-MAX-INSTALLED

\ Desk owns a deliberately small service namespace.  Entries borrow their
\ immutable ID strings and late-bind each service through a getter so owner
\ availability changes are observed without rebuilding the table.
 0 CONSTANT _DSS-ID-A
 8 CONSTANT _DSS-ID-U
16 CONSTANT _DSS-GET-XT
24 CONSTANT _DSS-ENTRY-SIZE
16 CONSTANT _DESK-SERVICE-CAPACITY

0 CONSTANT _DSS-S-OK
1 CONSTANT _DSS-S-INVALID
2 CONSTANT _DSS-S-DUPLICATE
3 CONSTANT _DSS-S-FULL

_DESK-CURRENT-STATE _HB-SZ _HB-MAX * CMP-FIELD: _HB-ENTRIES
_DESK-CURRENT-STATE CMP-CELL: _DHBAR-COUNT

\ Generic runtime and interoperability ownership.
_DESK-CURRENT-STATE CMP-CELL: _DESK-REGISTRY
_DESK-CURRENT-STATE CMP-CELL: _DESK-RREG
_DESK-CURRENT-STATE CMP-CELL: _DESK-POLICY
_DESK-CURRENT-STATE CMP-CELL: _DESK-BUS
_DESK-CURRENT-STATE CMP-CELL: _DESK-AUTHORITY
_DESK-CURRENT-STATE CMP-CELL: _DESK-INTENTS
_DESK-CURRENT-STATE CMP-CELL: _DESK-JOBS
_DESK-CURRENT-STATE XIO-SERVICE-SIZE CMP-FIELD: _DESK-EXTERNAL-IO
_DESK-CURRENT-STATE RID-SIZE CMP-FIELD: _DESK-DAYBOOK-RID
_DESK-CURRENT-STATE CMP-CELL: _DESK-DAYBOOK-OWNER
_DESK-CURRENT-STATE CMP-CELL: _DESK-DAYBOOK-STATUS
_DESK-CURRENT-STATE _DSS-ENTRY-SIZE _DESK-SERVICE-CAPACITY *
    CMP-FIELD: _DESK-SERVICES
_DESK-CURRENT-STATE CMP-CELL: _DESK-SERVICE-COUNT
_DESK-CURRENT-STATE IENDPOINT-SIZE CMP-FIELD: _DESK-ENDPOINT
_DESK-CURRENT-STATE CMP-CELL: _DESK-INSTALLED-N
_DESK-CURRENT-STATE _DESK-MAX-INSTALLED CELLS CMP-FIELD: _DESK-INSTALLED
_DESK-CURRENT-STATE CMP-CELL: _DESK-CATALOG
_DESK-CURRENT-STATE CMP-CELL: _DESK-LAUNCHER-ACTIVE
_DESK-CURRENT-STATE CMP-CELL: _DESK-LAUNCHER-SELECTED
_DESK-CURRENT-STATE CMP-CELL: _DESK-LAUNCHER-SCROLL
_DESK-CURRENT-STATE CMP-CELL: _DESK-LAUNCHER-STATUS
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-SOURCE
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-PROVIDER
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-RUNTIME
_DESK-CURRENT-STATE CMP-CELL: _DESK-TOOL-GATEWAY
_DESK-CURRENT-STATE PACT-SIZE CMP-FIELD: _DESK-PRACTICE-ACTIVATION
_DESK-CURRENT-STATE CFACET-SIZE CMP-FIELD: _DESK-AGENT-FACET
_DESK-CURRENT-STATE MAND-SIZE CMP-FIELD: _DESK-AGENT-MANDATE
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-PROMPT
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-PROMPT-RGN
_DESK-CURRENT-STATE _DESK-AGENT-PROMPT-CAP CMP-FIELD: _DESK-AGENT-PROMPT-BUF

CMP-LAYOUT-SIZE CONSTANT _DESK-STATE-SIZE

: _DESK-USE-STATE  ( instance -- )
    CINST-STATE _DESK-CURRENT-STATE ! ;

: _DESK-XIO-READY?  ( -- flag )
    _DESK-EXTERNAL-IO XIO-SERVICE-BOUND? ;

: _DESK-XIO-INIT  ( -- status )
    _DESK-EXTERNAL-IO XIO-SERVICE-INIT ;

: _DESK-XIO-FINI  ( -- status )
    _DESK-XIO-READY? 0= IF XIO-S-OK EXIT THEN
    _DESK-EXTERNAL-IO XIO-SERVICE-FINI ;

VARIABLE _DXIO-INST
VARIABLE _DXIO-OP
VARIABLE _DXIO-FIRST
VARIABLE _DXIO-RESET-STATUS

: _DESK-XIO-REMEMBER  ( status -- )
    ?DUP IF
        _DXIO-FIRST @ XIO-S-OK = IF _DXIO-FIRST ! ELSE DROP THEN
    THEN ;

: _DESK-XIO-OP-OWNER?  ( operation instance -- flag )
    >R
    DUP XIOO.OWNER-ID @ R@ CINST.ID @ =
    SWAP XIOO.OWNER-GENERATION @ R> CINST.GENERATION @ = AND ;

\ A successful operation is retained until its owner consumes or discards
\ the result.  If its wipe callback reports a fault, XIO deliberately keeps
\ it retained; a second reset observes the exact-once wipe flag and releases
\ the service without invoking untrusted cleanup twice.
: _DESK-XIO-RESET-RETAINED  ( operation -- status )
    _DXIO-OP !
    _DESK-EXTERNAL-IO _DXIO-OP @ XIO-RESET DUP _DXIO-RESET-STATUS !
    XIO-S-CALLBACK = IF
        _DESK-EXTERNAL-IO _DXIO-OP @ XIO-RESET DROP
    THEN
    _DXIO-RESET-STATUS @ ;

\ Release only work bound to the component instance that is about to lose
\ its state.  This is a host-lifecycle safety net; ordinary applet shutdown
\ still gets the first opportunity to consume results and cancel its work.
: _DESK-XIO-RELEASE-OWNER  ( instance -- status )
    _DXIO-INST ! XIO-S-OK _DXIO-FIRST !
    _DESK-XIO-READY? 0= IF XIO-S-OK EXIT THEN
    _DESK-EXTERNAL-IO XIO-ACTIVE-OP ?DUP IF
        DUP _DXIO-INST @ _DESK-XIO-OP-OWNER? IF
            _DESK-EXTERNAL-IO SWAP XIO-CANCEL _DESK-XIO-REMEMBER
        ELSE
            DROP
        THEN
    THEN
    _DESK-EXTERNAL-IO XIOS.RETAINED @ ?DUP IF
        DUP _DXIO-INST @ _DESK-XIO-OP-OWNER? IF
            _DESK-XIO-RESET-RETAINED _DESK-XIO-REMEMBER
        ELSE
            DROP
        THEN
    THEN
    _DXIO-FIRST @ ;

\ Final Desk teardown also covers work owned directly by a Desk service
\ rather than a child.  At this point child-specific cleanup has already run.
: _DESK-XIO-DRAIN  ( -- status )
    XIO-S-OK _DXIO-FIRST !
    _DESK-XIO-READY? 0= IF XIO-S-OK EXIT THEN
    _DESK-EXTERNAL-IO XIO-ACTIVE-OP ?DUP IF
        _DESK-EXTERNAL-IO SWAP XIO-CANCEL _DESK-XIO-REMEMBER
    THEN
    _DESK-EXTERNAL-IO XIOS.RETAINED @ ?DUP IF
        _DESK-XIO-RESET-RETAINED _DESK-XIO-REMEMBER
    THEN
    _DXIO-FIRST @ ;

: DESK-PRACTICE  ( -- practice-head | 0 )
    _DESK-PRACTICE-ACTIVATION DUP PACT-RECOVERY? IF
        DROP 0 EXIT
    THEN
    DUP PACT-ACTIVE? IF
        PACT-HEAD
    ELSE
        DROP 0
    THEN ;

: DESK-CONTEXT  ( -- context | 0 )
    _DESK-PRACTICE-ACTIVATION PACT.CONTEXT @ ;

: DESK-RECOVERY?  ( -- flag )
    _DESK-PRACTICE-ACTIVATION PACT-RECOVERY? ;

: DESK-CATALOG  ( -- catalog | 0 )
    _DESK-CATALOG @ ;

: DESK-AGENT-ACCESS  ( -- profile | 0 )
    _DESK-AGENT-RUNTIME @ ?DUP IF
        ARUNTIME-ACCESS-PROFILE
    ELSE
        0
    THEN ;

: _DESK-PACKAGE-RESOLVER  ( entry context -- desc status )
    DROP ACE-MANIFEST$ ALOAD-PATH ;

: _DESK-PACKAGE-RELEASER  ( desc context -- )
    DROP ALOAD-DESC-FREE ;

: DESK-PACKAGE-RESOLVER!  ( xt context -- )
    \ Hook replacement is a constructor operation.  Swapping ownership
    \ policy while descriptors are cached could free with the wrong hook.
    _DESK-CURRENT-STATE @ IF 2DROP EXIT THEN
    _DESK-PENDING-RESOLVER-CTX !
    _DESK-PENDING-RESOLVER-XT !
    0 _DESK-PENDING-RELEASER-XT !
    0 _DESK-PENDING-RELEASER-CTX ! ;

: DESK-PACKAGE-RELEASER!  ( xt context -- )
    _DESK-CURRENT-STATE @ IF 2DROP EXIT THEN
    _DESK-PENDING-RELEASER-CTX !
    _DESK-PENDING-RELEASER-XT ! ;

' _DESK-PACKAGE-RESOLVER 0 DESK-PACKAGE-RESOLVER!
' _DESK-PACKAGE-RELEASER 0 DESK-PACKAGE-RELEASER!

VARIABLE _DIF-COMP

: _DESK-INSTALLED-FIND  ( comp-desc -- app-desc | 0 )
    _DIF-COMP !
    _DESK-INSTALLED-N @ 0 ?DO
        I CELLS _DESK-INSTALLED + @ DUP APP.COMP-DESC @
        _DIF-COMP @ = IF UNLOOP EXIT THEN
        DROP
    LOOP
    0 ;

VARIABLE _DII-APP
VARIABLE _DII-COMP

: DESK-INSTALL  ( app-desc -- ior )
    DUP APP-DESC-VALID? 0= IF DROP CREG-E-NOT-FOUND EXIT THEN
    _DII-APP !
    _DII-APP @ APP.COMP-DESC @ _DII-COMP !
    _DII-COMP @ _DESK-INSTALLED-FIND IF 0 EXIT THEN
    _DESK-INSTALLED-N @ _DESK-MAX-INSTALLED >= IF CREG-E-FULL EXIT THEN
    _DII-COMP @ _DESK-REGISTRY @ CREG-TYPE-ENSURE ?DUP IF EXIT THEN
    _DII-COMP @ _DESK-INTENTS @ CINT-REGISTER-COMP ?DUP IF EXIT THEN
    _DII-APP @
    _DESK-INSTALLED-N @ CELLS _DESK-INSTALLED + !
    1 _DESK-INSTALLED-N +!
    0 ;

VARIABLE _DCED-DESC
VARIABLE _DCED-ID

: _DESK-CATALOG-ENTRY-FOR-DESC  ( desc -- entry | 0 )
    _DCED-DESC !
    _DESK-CATALOG @ ?DUP 0= IF 0 EXIT THEN >R
    _DCED-DESC @ APP-DESC-VALID? 0= IF R> DROP 0 EXIT THEN
    _DCED-DESC @ APP.COMP-DESC @ DUP COMP.ID-A @ SWAP COMP.ID-U @
    R> ACAT-FIND-ID ;

: _DESK-CATALOG-MARK-DESC  ( desc slot-id -- )
    _DCED-ID ! _DCED-DESC !
    _DCED-DESC @ _DESK-CATALOG-ENTRY-FOR-DESC ?DUP IF
        _DCED-ID @ SWAP _DESK-CATALOG @ ACAT-MARK-SLOT
    THEN ;

: _HB-ENTRY  ( idx -- addr )  _HB-SZ * _HB-ENTRIES + ;

: _DESK-HOTBAR-CLEAR  ( -- )
    _HB-ENTRIES _HB-SZ _HB-MAX * 0 FILL
    0 _DHBAR-COUNT ! ;

: _DESK-HOTBAR-ADD  ( lbl-a lbl-u file-a file-u desc-a desc-u -- )
    _DHBAR-COUNT @ _HB-MAX >= IF 2DROP 2DROP 2DROP EXIT THEN
    _DHBAR-COUNT @ _HB-ENTRY >R
    R@ _HB-DESC-U + !   R@ _HB-DESC-A + !
    R@ _HB-FILE-U + !   R@ _HB-FILE-A + !
    R@ _HB-LBL-U + !    R@ _HB-LBL-A + !
    0 R> _HB-SLOT + !
    1 _DHBAR-COUNT +! ;

: _DESK-HOTBAR-MARK  ( idx slot-id -- )
    SWAP _HB-ENTRY _HB-SLOT + ! ;

: _DESK-HOTBAR-SLOT-CLOSED  ( slot-id -- )
    _DHBAR-COUNT @ 0 ?DO
        I _HB-ENTRY _HB-SLOT + @
        OVER = IF 0 I _HB-ENTRY _HB-SLOT + ! THEN
    LOOP DROP ;

\ Non-aborting wrapper for TOML array-of-tables lookup.
VARIABLE _DHBA-SAVED
: _DHBAR-ATABLE?  ( toml-a toml-l n -- body-a body-l flag )
    >R
    TOML-ABORT-ON-ERROR @ _DHBA-SAVED !
    TOML-CLEAR-ERR  0 TOML-ABORT-ON-ERROR !
    S" desk.hotbar" R> TOML-FIND-ATABLE
    _DHBA-SAVED @ TOML-ABORT-ON-ERROR !
    TOML-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;

VARIABLE _DHBL-BA  VARIABLE _DHBL-BL

: _DESK-LOAD-HOTBAR  ( toml-a toml-l -- )
    _DESK-HOTBAR-CLEAR
    _HB-MAX 0 DO
        2DUP I _DHBAR-ATABLE?
        0= IF 2DROP LEAVE THEN
        _DHBL-BL ! _DHBL-BA !
        _DHBL-BA @ _DHBL-BL @  S" label" TOML-KEY?
        0= IF 2DROP ELSE
            TOML-GET-STRING
            _DHBL-BA @ _DHBL-BL @  S" file" TOML-KEY?
            0= IF 2DROP 2DROP ELSE
                TOML-GET-STRING
                _DHBL-BA @ _DHBL-BL @  S" desc" TOML-KEY?
                IF TOML-GET-STRING ELSE 2DROP S" " THEN
                _DESK-HOTBAR-ADD
            THEN
        THEN
    LOOP
    2DROP ;

\ Paint hotbar entries.  Called from the taskbar painter.
VARIABLE _DHBP-COL

VARIABLE _DHBC-ENTRY
VARIABLE _DHBC-SHOWN
VARIABLE _DHBC-CLOSE
VARIABLE _DHBC-LABEL-A
VARIABLE _DHBC-LABEL-U

: _DESK-PAINT-CATALOG-HOTBAR  ( row col -- )
    _DHBP-COL !
    0 _DHBC-SHOWN !
    _DESK-CATALOG @ ACAT-COUNT 0 ?DO
        _DHBC-SHOWN @ _HB-MAX >= IF LEAVE THEN
        I _DESK-CATALOG @ ACAT-NTH DUP ACE-PINNED? IF
            _DHBC-ENTRY !
            _DHBC-ENTRY @ ACE-QUARANTINED?
            _DHBC-ENTRY @ ACE.STATE @ ACAT-R-FAILED = OR IF
                33 _DHBC-CLOSE !
                15 124 1 DRW-STYLE! 33
            ELSE _DHBC-ENTRY @ ACE-ENABLED? 0= IF
                41 _DHBC-CLOSE !
                _DTH-MIN-FG @ _DTH-PIN-BG @ 0 DRW-STYLE! 40
            ELSE _DHBC-ENTRY @ ACE.SLOT @ IF
                93 _DHBC-CLOSE !
                _DTH-TBAR-FG @ _DTH-TBAR-BG @ _DTH-TBAR-ATTR @ DRW-STYLE! 91
            ELSE
                62 _DHBC-CLOSE !
                _DTH-PIN-FG @ _DTH-PIN-BG @ 0 DRW-STYLE! 60
            THEN THEN THEN
            OVER _DHBP-COL @ DRW-CHAR 1 _DHBP-COL +!
            _DHBC-ENTRY @ ACE-TITLE$ DUP 0= IF
                2DROP _DHBC-ENTRY @ ACE-ID$
            THEN
            DUP 10 > IF DROP 10 THEN
            _DHBC-LABEL-U ! _DHBC-LABEL-A !
            _DHBC-LABEL-A @ _DHBC-LABEL-U @
            2 PICK _DHBP-COL @ DRW-TEXT
            _DHBC-LABEL-U @ _DHBP-COL +!
            _DHBC-CLOSE @ OVER _DHBP-COL @ DRW-CHAR 1 _DHBP-COL +!
            32 OVER _DHBP-COL @ DRW-CHAR 1 _DHBP-COL +!
            1 _DHBC-SHOWN +!
        ELSE
            DROP
        THEN
    LOOP
    DROP ;

: _DESK-HOTBAR-PROJECTION-COUNT  ( -- n )
    _DESK-CATALOG @ ?DUP IF ACAT-PINNED-COUNT ELSE _DHBAR-COUNT @ THEN ;

: _DESK-PAINT-HOTBAR  ( row col -- )
    _DHBP-COL !
    _DHBAR-COUNT @ 0 ?DO
        I _HB-ENTRY >R
        R@ _HB-SLOT + @ IF
            _DTH-TBAR-FG @ _DTH-TBAR-BG @ _DTH-TBAR-ATTR @ DRW-STYLE!
            91                         \ '['
        ELSE
            _DTH-PIN-FG @ _DTH-PIN-BG @ 0 DRW-STYLE!
            60                         \ '<'
        THEN
        OVER _DHBP-COL @ DRW-CHAR  1 _DHBP-COL +!
        R@ _HB-LBL-A + @  R@ _HB-LBL-U + @
        2 PICK _DHBP-COL @ DRW-TEXT
        R@ _HB-LBL-U + @ _DHBP-COL +!
        R@ _HB-SLOT + @ IF 93 ELSE 62 THEN
        OVER _DHBP-COL @ DRW-CHAR  1 _DHBP-COL +!
        32 OVER _DHBP-COL @ DRW-CHAR  1 _DHBP-COL +!
        R> DROP
    LOOP
    DROP ;

\ Find first unlaunched hotbar entry, or -1.
: _DESK-HOTBAR-NEXT  ( -- idx | -1 )
    _DHBAR-COUNT @ 0 DO
        I _HB-ENTRY _HB-SLOT + @ 0= IF I UNLOOP EXIT THEN
    LOOP -1 ;

\ =====================================================================
\  §2d — Config Loader
\ =====================================================================

: DESK-LOAD-CONFIG  ( addr len -- )
    2DUP _DESK-LOAD-THEME
    _DESK-LOAD-HOTBAR ;

\ =====================================================================
\  §3 — Linked-List Helpers
\ =====================================================================

\ Count all live slots.
: DESK-SLOT-COUNT  ( -- n )
    _DESK-HOST AHOST-SLOT-COUNT ;

\ Count visible (non-minimized) slots.
: DESK-VCOUNT  ( -- n )
    _DESK-HOST AHOST-VCOUNT ;

\ Find slot by ID.  Returns slot address or 0.
: _DESK-FIND-ID  ( id -- sa | 0 )
    _DESK-HOST AHOST-FIND-ID ;

\ =====================================================================
\  §4 — Visible Slot Collection Buffer
\ =====================================================================

64 CONSTANT _DESK-MAX-VIS
CREATE _DESK-VIS-BUF   _DESK-MAX-VIS CELLS ALLOT
VARIABLE _DESK-VIS-N

: _DESK-COLLECT-VISIBLE  ( -- )
    0 _DESK-VIS-N !
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _DESK-VIS-N @ _DESK-MAX-VIS < IF
                DUP  _DESK-VIS-N @ CELLS _DESK-VIS-BUF +  !
                1 _DESK-VIS-N +!
            THEN
        THEN
        _SL-NEXT @
    REPEAT ;

\ =====================================================================
\  §5 — Dynamic Tiling Layout Engine
\ =====================================================================
\
\  Uses SCR-W and SCR-H at call time.
\  Usable area: W = SCR-W,  H = SCR-H - 1  (last row = taskbar).

\ Integer ceiling of sqrt via Newton iteration.
: _DESK-ISQRT  ( n -- root )
    DUP 1 <= IF EXIT THEN
    DUP                               ( n x )
    BEGIN
        OVER OVER /                   ( n x n/x )
        OVER +  2 /                   ( n x x' )
        DUP 2 PICK < WHILE           \ while x' < x
        NIP                           ( n x' )
    REPEAT
    NIP NIP ;

\ Ceiling divide: ( a b -- ceil(a/b) )
: _DESK-CDIV  ( a b -- q )
    DUP >R  1- +  R> / ;

\ Layout work variables
VARIABLE _DL-W   VARIABLE _DL-H
VARIABLE _DL-COLS  VARIABLE _DL-ROWS
VARIABLE _DL-TW    VARIABLE _DL-TH
VARIABLE _DL-LW    VARIABLE _DL-LH

\ Free all sub-app regions.
: _DESK-FREE-REGIONS  ( -- )
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-RGN @ ?DUP IF RGN-FREE THEN
        0 OVER _SL-RGN !
        _SL-NEXT @
    REPEAT ;

: _DESK-MARK-ALL-CHILDREN  ( -- )
    _DESK-HOST AHOST-MARK-ALL ;

\ Compute grid dimensions for N visible apps.
: _DESK-GRID  ( n -- )
    DUP 0 <= IF DROP 0 _DL-COLS ! 0 _DL-ROWS ! EXIT THEN
    DUP 1 = IF DROP 1 _DL-COLS ! 1 _DL-ROWS ! EXIT THEN
    _DESK-VH @ 0= IF
        \ V-pref: cols = ceil(sqrt(N)), rows = ceil(N/cols)
        DUP _DESK-ISQRT                  ( n s )
        DUP DUP * 2 PICK < IF 1+ THEN   ( n cols )
        DUP _DL-COLS !
        _DESK-CDIV _DL-ROWS !
    ELSE
        \ H-pref: rows = ceil(sqrt(N)), cols = ceil(N/rows)
        DUP _DESK-ISQRT                  ( n s )
        DUP DUP * 2 PICK < IF 1+ THEN   ( n rows )
        DUP _DL-ROWS !
        _DESK-CDIV _DL-COLS !
    THEN ;

\ Compute tile sizes from current grid and screen.
: _DESK-TILE-SIZES  ( -- )
    SCR-W _DL-W !
    SCR-H 1- _DL-H !
    _DL-W @  _DL-COLS @ 1- -  _DL-COLS @  /  _DL-TW !
    _DL-H @  _DL-ROWS @ 1- -  _DL-ROWS @  /  _DL-TH !
    _DL-W @  _DL-COLS @ 1- -  _DL-TW @ _DL-COLS @ 1- * -  _DL-LW !
    _DL-H @  _DL-ROWS @ 1- -  _DL-TH @ _DL-ROWS @ 1- * -  _DL-LH ! ;

\ Assign region to i-th visible slot.
VARIABLE _DA-R   VARIABLE _DA-C
VARIABLE _DA-TW  VARIABLE _DA-TH

: _DESK-ASSIGN-TILE  ( idx -- )
    DUP CELLS _DESK-VIS-BUF + @      ( idx sa )
    SWAP                              ( sa idx )
    DUP _DL-COLS @ /                  ( sa idx grow )
    SWAP _DL-COLS @ MOD               ( sa grow gcol )
    \ pixel-col = gcol * (tile-w + 1)
    DUP _DL-TW @ 1+ * _DA-C !
    \ width: last col? use last-w, else tile-w
    DUP _DL-COLS @ 1- = IF
        _DL-LW @
    ELSE
        _DL-TW @
    THEN _DA-TW !
    DROP                              ( sa grow )
    \ pixel-row = grow * (tile-h + 1)
    DUP _DL-TH @ 1+ * _DA-R !
    \ height: last row? use last-h, else tile-h
    _DL-ROWS @ 1- = IF
        _DL-LH @
    ELSE
        _DL-TH @
    THEN _DA-TH !
    _DA-R @ _DA-C @ _DA-TH @ _DA-TW @ RGN-NEW
    SWAP _SL-RGN ! ;

\ Draw dividers between tiles.
: _DESK-DRAW-DIVIDERS  ( -- )
    DRW-STYLE-SAVE
    _DTH-DIV-FG @ _DTH-DIV-BG @ 0 DRW-STYLE!
    _DL-COLS @ 1 > IF
        _DL-COLS @ 1- 0 DO
            I 1+ _DL-TW @ * I +
            9474 0 OVER _DL-H @ DRW-VLINE
            DROP
        LOOP
    THEN
    _DL-ROWS @ 1 > IF
        _DL-ROWS @ 1- 0 DO
            I 1+ _DL-TH @ * I +
            9472 OVER 0 _DL-W @ DRW-HLINE
            DROP
        LOOP
    THEN
    DRW-STYLE-RESTORE ;

\ =====================================================================
\  §6 — UIDL Context Switching
\ =====================================================================

: _DESK-CTX-SAVE  ( sa -- )
    AHS-CTX-SAVE ;

: _DESK-ACTIVATE-CHILD  ( sa -- )
    AHS-ACTIVATE ;

: _DESK-CTX-SWITCH  ( sa -- )
    AHS-CTX-SWITCH ;

\ Master relayout.
: DESK-RELAYOUT  ( -- )
    _DESK-COLLECT-VISIBLE
    _DESK-FREE-REGIONS
    _DESK-VIS-N @ DUP 0= IF DROP ASHELL-DIRTY! EXIT THEN
    DUP _DESK-GRID
    _DESK-TILE-SIZES
    0 DO I _DESK-ASSIGN-TILE LOOP
    \ Re-load UIDL for visible sub-apps into their new regions
    _DESK-VIS-N @ 0 DO
        I CELLS _DESK-VIS-BUF + @          ( sa )
        -1 OVER _SL-DIRTY !
        DUP _SL-HAS-UIDL @ IF
            DUP _DESK-CTX-SWITCH
            DUP _SL-RGN @ UTUI-RGN!
            UTUI-RELAYOUT
        THEN
        DROP
    LOOP
    -1 _DESK-BG-DIRTY !
    ASHELL-DIRTY! ;

: _DESK-SYNC-GEOMETRY  ( -- )
    SCR-W _DESK-LAST-W @ <>
    SCR-H _DESK-LAST-H @ <> OR 0= IF EXIT THEN
    SCR-W _DESK-LAST-W !
    SCR-H _DESK-LAST-H !
    DESK-RELAYOUT ;

\ =====================================================================
\  §7 — App Launch & Close
\ =====================================================================
\
\  Key difference from compositor: no APP-INIT calls.  The shell
\  owns the terminal.  Sub-app INIT-XT is called, but terminal
\  setup is not the sub-app's job.

AHOST-LAUNCH-E-DESC     CONSTANT DESK-LAUNCH-E-DESC
AHOST-LAUNCH-E-INSTANCE CONSTANT DESK-LAUNCH-E-INSTANCE
AHOST-LAUNCH-E-REGISTRY CONSTANT DESK-LAUNCH-E-REGISTRY
AHOST-LAUNCH-E-SLOT     CONSTANT DESK-LAUNCH-E-SLOT
AHOST-LAUNCH-E-CONTEXT  CONSTANT DESK-LAUNCH-E-CONTEXT
AHOST-LAUNCH-E-UIDL     CONSTANT DESK-LAUNCH-E-UIDL

\ The generic host owns child mechanics. Desk injects only the product
\ projections and resources which remain Desk-specific.
: _DESK-HOST-RELAYOUT  ( desk-instance -- )
    _DESK-USE-STATE DESK-RELAYOUT ;

: _DESK-HOST-RELEASE  ( child-instance desk-instance -- ior )
    _DESK-USE-STATE _DESK-XIO-RELEASE-OWNER ;

: _DESK-HOST-CLOSED  ( slot-id desk-instance -- )
    _DESK-USE-STATE
    DUP _DESK-HOTBAR-SLOT-CLOSED
    _DESK-CATALOG @ ?DUP IF ACAT-SLOT-CLOSED ELSE DROP THEN ;

VARIABLE _DTL-DESC

: _DTL-PREFLIGHT  ( -- )
    _DTL-DESC @ APP-DESC-VALID? 0= IF
        DESK-LAUNCH-E-DESC THROW
    THEN
    _DTL-DESC @ DESK-INSTALL ?DUP IF
        THROW
    THEN ;

: DESK-TRY-LAUNCH  ( desc -- id ior )
    _DTL-DESC !
    ['] _DTL-PREFLIGHT CATCH ?DUP IF -1 SWAP EXIT THEN
    _DTL-DESC @ _DESK-HOST AHOST-TRY-LAUNCH
    DUP 0= IF
        _DTL-DESC @ 2 PICK _DESK-CATALOG-MARK-DESC
    THEN ;

: DESK-LAUNCH  ( desc -- id )
    DESK-TRY-LAUNCH DUP IF 2DROP -1 ELSE DROP THEN ;

: DESK-REQUEST-CLOSE-ID  ( id reason -- decision )
    _DESK-HOST AHOST-REQUEST-CLOSE-ID ;

: DESK-CLOSE-ID  ( id -- )
    APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID DROP ;

\ =====================================================================
\  §8 — Focus, Minimize, Restore
\ =====================================================================

: DESK-FOCUS-ID  ( id -- )
    _DESK-HOST AHOST-FOCUS-ID ;

: DESK-MINIMIZE-ID  ( id -- )
    _DESK-HOST AHOST-MINIMIZE-ID ;

: DESK-RESTORE  ( -- )
    _DESK-HOST AHOST-RESTORE ;

: DESK-FULLFRAME!  ( flag -- )
    _DESK-FULLFRAME !
    DESK-RELAYOUT ;

: DESK-TOGGLE-VH  ( -- )
    _DESK-VH @ 0= _DESK-VH !
    DESK-RELAYOUT ;

VARIABLE _DCO-ENTRY
VARIABLE _DCO-SLOT
VARIABLE _DCO-DESC
VARIABLE _DCO-STATUS
VARIABLE _DCA-CAT


: _DESK-OPEN-CATALOG-ENTRY  ( entry -- status )
    _DCO-ENTRY !
    _DCO-ENTRY @ ACE.SLOT @ DUP _DCO-SLOT ! IF
        _DCO-SLOT @ _DESK-FIND-ID IF
            _DCO-SLOT @ DESK-FOCUS-ID ACAT-S-OK EXIT
        THEN
        0 _DCO-ENTRY @ _DESK-CATALOG @ ACAT-MARK-SLOT
    THEN
    _DCO-ENTRY @ _DESK-CATALOG @ ACAT-RESOLVE
    _DCO-STATUS ! _DCO-DESC !
    _DCO-STATUS @ IF _DCO-STATUS @ EXIT THEN
    _DCO-DESC @ DESK-TRY-LAUNCH
    _DCO-STATUS ! _DCO-SLOT !
    _DCO-STATUS @ IF
        ACAT-R-FAILED _DCO-ENTRY @ ACE.STATE !
        _DCO-STATUS @ _DCO-ENTRY @ ACE.ERROR !
        _DCO-STATUS @ EXIT
    THEN
    _DCO-SLOT @ _DCO-ENTRY @ _DESK-CATALOG @ ACAT-MARK-SLOT
    ACAT-R-LOADED _DCO-ENTRY @ ACE.STATE !
    0 _DCO-ENTRY @ ACE.ERROR !
    ACAT-S-OK ;

: _DESK-AUTOSTART-CATALOG  ( -- )
    _DESK-CATALOG @ ?DUP 0= IF EXIT THEN _DCA-CAT !
    _DCA-CAT @ ACAT-COUNT 0 ?DO
        I _DCA-CAT @ ACAT-NTH DUP ACE-AUTOSTART? OVER ACE.SLOT @ 0= AND IF
            _DESK-OPEN-CATALOG-ENTRY DROP
        ELSE
            DROP
        THEN
    LOOP
    _DCA-CAT @ ACAT-RECOVERY? IF
        \ A corrupt/read-only catalog cannot accept a newly queued built-in.
        \ Keep existing profiles bootable, but only for descriptors which
        \ have no persisted row whose flags should remain authoritative.
        _DESK-PEND-N @ 0 ?DO
            I CELLS _DESK-PEND-BUF + @ DUP
            _DESK-CATALOG-ENTRY-FOR-DESC 0= IF
                DESK-TRY-LAUNCH 2DROP
            ELSE
                DROP
            THEN
        LOOP
    THEN ;

\ =====================================================================
\  §8b — Runtime Registry and Interoperability Endpoint
\ =====================================================================

VARIABLE _DFI-INST

: _DESK-FOCUS-INSTANCE  ( instance -- )
    _DFI-INST !
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-INST @ _DFI-INST @ = IF
            _SL-ID @ DESK-FOCUS-ID EXIT
        THEN
        _SL-NEXT @
    REPEAT ;

: _DESK-ENDPOINT-POST  ( request desk-instance -- status )
    _DESK-USE-STATE
    _DESK-BUS @ CBUS-POST ;

\ The table contains only routing metadata.  Service ownership and lifetime
\ remain with Desk; getters make those lifetimes visible at lookup time.
: _DESK-SERVICE-ENTRY  ( index -- entry )
    _DSS-ENTRY-SIZE * _DESK-SERVICES + ;

VARIABLE _DSSF-ID-A
VARIABLE _DSSF-ID-U
VARIABLE _DSSF-ENTRY

: _DESK-SERVICE-FIND  ( id-a id-u -- entry | 0 )
    _DSSF-ID-U ! _DSSF-ID-A !
    _DESK-SERVICE-COUNT @ 0 ?DO
        I _DESK-SERVICE-ENTRY DUP _DSSF-ENTRY ! DROP
        _DSSF-ID-A @ _DSSF-ID-U @
        _DSSF-ENTRY @ _DSS-ID-A + @
        _DSSF-ENTRY @ _DSS-ID-U + @ STR-STR= IF
            _DSSF-ENTRY @ UNLOOP EXIT
        THEN
    LOOP
    0 ;

VARIABLE _DSSA-ID-A
VARIABLE _DSSA-ID-U
VARIABLE _DSSA-GET-XT
VARIABLE _DSSA-ENTRY

: _DESK-SERVICE+  ( id-a id-u getter-xt -- status )
    _DSSA-GET-XT ! _DSSA-ID-U ! _DSSA-ID-A !
    _DSSA-ID-A @ 0= _DSSA-ID-U @ 0> 0= OR
    _DSSA-GET-XT @ 0= OR IF _DSS-S-INVALID EXIT THEN
    _DSSA-ID-A @ _DSSA-ID-U @ _DESK-SERVICE-FIND IF
        _DSS-S-DUPLICATE EXIT
    THEN
    _DESK-SERVICE-COUNT @ _DESK-SERVICE-CAPACITY >= IF
        _DSS-S-FULL EXIT
    THEN
    _DESK-SERVICE-COUNT @ _DESK-SERVICE-ENTRY DUP _DSSA-ENTRY !
    _DSS-ENTRY-SIZE 0 FILL
    _DSSA-ID-A @ _DSSA-ENTRY @ _DSS-ID-A + !
    _DSSA-ID-U @ _DSSA-ENTRY @ _DSS-ID-U + !
    _DSSA-GET-XT @ _DSSA-ENTRY @ _DSS-GET-XT + !
    1 _DESK-SERVICE-COUNT +!
    _DSS-S-OK ;

: _DESK-SERVICE@  ( id-a id-u -- service | 0 )
    _DESK-SERVICE-FIND ?DUP IF
        _DSS-GET-XT + @ EXECUTE
    ELSE
        0
    THEN ;

: _DESK-SERVICE-TABLE-INIT  ( -- )
    _DESK-SERVICES _DSS-ENTRY-SIZE _DESK-SERVICE-CAPACITY * 0 FILL
    0 _DESK-SERVICE-COUNT ! ;

: _DESK-SERVICE-TABLE-FINI  ( -- )
    _DESK-SERVICE-TABLE-INIT ;

: _DESK-SERVICE-XIO@  ( -- service | 0 )
    _DESK-XIO-READY? IF _DESK-EXTERNAL-IO ELSE 0 THEN ;

: _DESK-SERVICE-AGENT-RUNTIME@  ( -- service | 0 )
    _DESK-AGENT-RUNTIME @ ;

: _DESK-SERVICE-TOOL-GATEWAY@  ( -- service | 0 )
    _DESK-TOOL-GATEWAY @ ;

: _DESK-SERVICE-PROVIDER-SOURCE@  ( -- service | 0 )
    _DESK-AGENT-SOURCE @ ;

: _DESK-SERVICE-ACCESS-PROFILE@  ( -- service | 0 )
    _DESK-AGENT-RUNTIME @ ?DUP IF ARUNTIME-ACCESS-PROFILE ELSE 0 THEN ;

: _DESK-SERVICE-REGISTRY@  ( -- service | 0 )
    _DESK-REGISTRY @ ;

: _DESK-SERVICE-CONTEXT@  ( -- service | 0 )
    DESK-CONTEXT ;

: _DESK-SERVICE-RESOURCE-REGISTRY@  ( -- service | 0 )
    _DESK-RREG @ ;

: _DESK-SERVICE-REQUEST-BUS@  ( -- service | 0 )
    _DESK-BUS @ ;

: _DESK-SERVICE-DAYBOOK@  ( -- service | 0 )
    _DESK-DAYBOOK-STATUS @ 0=
    _DESK-DAYBOOK-OWNER @ 0<> AND IF SDOC-SERVICE ELSE 0 THEN ;

: _DESK-SERVICE-ENDPOINT@  ( -- service )
    _DESK-ENDPOINT ;

: _DESK-SERVICE-TABLE-SETUP  ( -- status )
    _DESK-SERVICE-TABLE-INIT
    S" org.akashic.net.external-io" ['] _DESK-SERVICE-XIO@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.agent.runtime" ['] _DESK-SERVICE-AGENT-RUNTIME@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.agent.tool-gateway" ['] _DESK-SERVICE-TOOL-GATEWAY@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.agent.provider-source" ['] _DESK-SERVICE-PROVIDER-SOURCE@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.agent.access-profile" ['] _DESK-SERVICE-ACCESS-PROFILE@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.runtime.registry" ['] _DESK-SERVICE-REGISTRY@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.runtime.context" ['] _DESK-SERVICE-CONTEXT@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.runtime.resource-registry"
        ['] _DESK-SERVICE-RESOURCE-REGISTRY@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.interop.request-bus" ['] _DESK-SERVICE-REQUEST-BUS@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.resource.daybook" ['] _DESK-SERVICE-DAYBOOK@
        _DESK-SERVICE+ DUP IF EXIT THEN DROP
    S" org.akashic.interop.endpoint" ['] _DESK-SERVICE-ENDPOINT@
        _DESK-SERVICE+ ;

: _DESK-ENDPOINT-SERVICE  ( id-a id-u desk-instance -- service | 0 )
    _DESK-USE-STATE _DESK-SERVICE@ ;

VARIABLE _DIR-ID-A
VARIABLE _DIR-ID-U
VARIABLE _DIR-REQ
VARIABLE _DIR-ENTRY
VARIABLE _DIR-COMP
VARIABLE _DIR-INST

: _DESK-ENDPOINT-INTENT  ( id-a id-u request desk-instance -- status )
    _DESK-USE-STATE
    _DIR-REQ ! _DIR-ID-U ! _DIR-ID-A !
    _DIR-ID-A @ _DIR-ID-U @ _DESK-INTENTS @ CINT-RESOLVE-STATUS
    DUP CINT-S-OK = IF
        DROP _DIR-ENTRY !
    ELSE
        CINT-S-AMBIGUOUS = IF
            DROP CBUS-S-AMBIGUOUS-HANDLER EXIT
        THEN
        DROP CBUS-S-NO-HANDLER EXIT
    THEN
    _DIR-ENTRY @ CIE.COMP-DESC @ _DIR-COMP !
    0 _DIR-INST !

    \ Prefer a focused compatible instance.
    _DESK-FOCUS-SA @ ?DUP IF
        _SL-INST @ DUP CINST-DESC _DIR-COMP @ = IF
            _DIR-INST !
        ELSE DROP THEN
    THEN

    \ Then any live compatible instance.
    _DIR-INST @ 0= IF
        _DIR-COMP @ _DESK-REGISTRY @ CREG-INST-BY-DESC _DIR-INST !
    THEN

    \ Finally launch the installed TUI binding for that component type.
    _DIR-INST @ 0= IF
        _DIR-COMP @ _DESK-INSTALLED-FIND ?DUP IF
            DESK-LAUNCH DROP
            _DIR-COMP @ _DESK-REGISTRY @ CREG-INST-BY-DESC _DIR-INST !
        THEN
    THEN
    _DIR-INST @ 0= IF CBUS-S-NO-HANDLER EXIT THEN

    _DIR-INST @ _DESK-FOCUS-INSTANCE
    _DIR-INST @ _DIR-REQ @ CBR-TARGET!
    _DIR-ENTRY @ CIE.CAP @ _DIR-REQ @ CBR.CAP !
    _DIR-REQ @ _DESK-BUS @ CBUS-POST ;

VARIABLE _DINI-INST
VARIABLE _DINI-CONTEXT
VARIABLE _DCI-CAT
VARIABLE _DCI-STATUS

: _DESK-CATALOG-INIT  ( -- )
    VFS-CUR ACAT-NEW _DCI-STATUS ! _DCI-CAT !
    _DCI-STATUS @ ACAT-S-OK <> ABORT" desk: catalog allocation failed"
    _DCI-CAT @ _DESK-CATALOG !
    _DCI-CAT @ ACAT-ACTIVATE DUP
    ACAT-S-OK = OVER ACAT-S-MISSING = OR
    OVER ACAT-S-RECOVERY = OR 0=
    ABORT" desk: catalog activation failed"
    DROP
    _DESK-PENDING-RESOLVER-XT @ ?DUP IF
        _DESK-PENDING-RESOLVER-CTX @ _DCI-CAT @ ACAT-RESOLVER!
    THEN
    _DESK-PENDING-RELEASER-XT @
    _DESK-PENDING-RELEASER-CTX @ _DCI-CAT @ ACAT-RELEASER!
    _DESK-BUILTIN-N @ 0 ?DO
        I _DESK-BUILTIN-ENTRY DUP @ SWAP 8 + @ _DCI-CAT @
        ACAT-BIND-BUILTIN DUP ACAT-S-OK <> IF
            _DCI-CAT @ ACAT-RECOVERY? 0=
            ABORT" desk: built-in catalog binding failed"
        THEN DROP
    LOOP
    _DESK-CATALOG @ ABUILD-CATALOG! ;

: _DESK-BIND-AGENT-STORE  ( -- )
    VFS-CUR ?DUP 0= IF EXIT THEN
    AVFSSTORE-NEW DUP IF
        NIP _DESK-AGENT-RUNTIME @ ARUNTIME.STORE-STATUS ! EXIT
    THEN
    DROP _DESK-AGENT-RUNTIME @ ARUNTIME-CONVERSATION-STORE! DROP ;

: _DESK-AGENT-PROMPT-SUBMIT  ( prompt -- )
    PRM-GET-TEXT _DESK-AGENT-RUNTIME @ ARUNTIME-SEND
    DUP 0= IF
        DROP S" Agent request started" 1000 ASHELL-TOAST
    ELSE
        DROP S" Agent is busy" 1600 ASHELL-TOAST
    THEN
    ASHELL-DIRTY! ;

: _DESK-AGENT-PROMPT-CANCEL  ( prompt -- )
    DROP ASHELL-DIRTY! ;

VARIABLE _DSFA-SLOT

: _DESK-FOCUS-AGENT  ( -- )
    _DESK-HEAD @
    BEGIN DUP WHILE
        DUP _DSFA-SLOT ! _SL-DESC @ APP.COMP-DESC @ ?DUP IF
            DUP COMP.ID-A @ SWAP COMP.ID-U @
            S" org.akashic.agent" STR-STR= IF
                _DSFA-SLOT @ _SL-ID @ DESK-FOCUS-ID EXIT
            THEN
        THEN
        _DSFA-SLOT @ _SL-NEXT @
    REPEAT
    DROP ;

: _DESK-SHOW-AGENT-PROMPT  ( -- )
    DESK-RECOVERY? IF
        S" Practice recovery: Agent is disabled" 1800 ASHELL-TOAST EXIT
    THEN
    _DESK-AGENT-PROMPT @ 0= IF EXIT THEN
    _DESK-AGENT-RUNTIME @ ARUNTIME-AUTH ?DUP IF
        AAUTH-READY? 0= IF
            _DESK-FOCUS-AGENT
            S" Agent sign-in required" 1600 ASHELL-TOAST EXIT
        THEN
    THEN
    _DESK-AGENT-RUNTIME @ ARUNTIME-RUN-SETTINGS ?DUP IF
        ARSET.STATE @ ARSET-STATE-READY <> IF
            _DESK-FOCUS-AGENT
            S" Agent models are not ready" 1600 ASHELL-TOAST EXIT
        THEN
    THEN
    S" Ask:" 0 0 _DESK-AGENT-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

VARIABLE _DMF-DESK
VARIABLE _DMF-RUN-ID
VARIABLE _DMF-CHILD
VARIABLE _DMF-STATUS
VARIABLE _DMF-TAG-A
VARIABLE _DMF-TAG-U
VARIABLE _DMF-DEST
VARIABLE _DMF-PROFILE
VARIABLE _DMF-EFFECTS

: _DESK-DAYBOOK-RID!  ( -- )
    SHA3-256-BEGIN
    DESK-PRACTICE PHEAD.ID RID-SIZE SHA3-256-ADD
    S" org.akashic.resource.daybook" SHA3-256-ADD
    _DESK-DAYBOOK-RID SHA3-256-END ;

: _DESK-DAYBOOK-INIT  ( -- )
    0 _DESK-RREG !
    0 _DESK-DAYBOOK-OWNER !
    SDOC-S-INVALID _DESK-DAYBOOK-STATUS !
    _DESK-DAYBOOK-RID!
    _DESK-REGISTRY @ DESK-CONTEXT RREG-NEW
    DUP IF
        _DESK-DAYBOOK-STATUS ! DROP EXIT
    THEN
    DROP _DESK-RREG !
    DESK-CONTEXT CTX.VFS @ _DESK-DAYBOOK-RID DESK-CONTEXT
        _DESK-RREG @ _DESK-REGISTRY @ SDOC-ACTIVATE
    DUP _DESK-DAYBOOK-STATUS ! IF
        DROP EXIT
    THEN
    _DESK-DAYBOOK-OWNER ! ;

VARIABLE _DMA-A
VARIABLE _DMA-U
VARIABLE _DMA-EXPECTED
VARIABLE _DMA-FLAGS
VARIABLE _DMA-MAX-RESULT
VARIABLE _DMA-EFFECTS
VARIABLE _DMA-INST
VARIABLE _DMA-DESC
VARIABLE _DMA-CAP

VARIABLE _DTC-A
VARIABLE _DTC-U
VARIABLE _DTC-FOUND
VARIABLE _DTC-DESC

\ Resolve authority only from the exact component descriptor pointer carried
\ by Desk's trusted built-in constructor list.  Registry text identity alone
\ is insufficient because an installed descriptor may impersonate a built-in
\ component id.
: _DESK-TRUSTED-COMP  ( id-a id-u -- descriptor | 0 )
    _DTC-U ! _DTC-A ! 0 _DTC-FOUND !
    _DESK-BUILTIN-N @ 0 ?DO
        I _DESK-BUILTIN-ENTRY @ APP.COMP-DESC @ _DTC-DESC !
        _DTC-DESC @ IF
            _DTC-DESC @ DUP COMP.ID-A @ SWAP COMP.ID-U @
                _DTC-A @ _DTC-U @ STR-STR= IF
                _DTC-FOUND @ ?DUP IF
                    _DTC-DESC @ <> IF 0 UNLOOP EXIT THEN
                ELSE
                    _DTC-DESC @ _DTC-FOUND !
                THEN
            THEN
        THEN
    LOOP
    _DTC-FOUND @ ;

\ Add the focused live implementation, or otherwise the first live
\ implementation, of one explicitly named built-in
\ operation.  Missing applets are not an error; they simply do not appear in
\ this run's frozen facet.  No descriptor enumeration can expand the list.
: _DESK-MANDATE-CAP+
  ( expected-desc id-a id-u effects facet-flags max-result -- status )
    _DMA-MAX-RESULT ! _DMA-FLAGS ! _DMA-EFFECTS !
    _DMA-U ! _DMA-A ! _DMA-EXPECTED !
    _DMA-EFFECTS @ _DMF-PROFILE @ AAP.EFFECTS @ AND
        _DMA-EFFECTS @ <> IF CFACET-S-INVALID EXIT THEN
    0 _DMA-INST !
    _DESK-FOCUS-SA @ ?DUP IF
        _SL-INST @ DUP CINST-DESC _DMA-EXPECTED @ = IF
            _DMA-INST !
        ELSE
            DROP
        THEN
    THEN
    _DMA-INST @ 0= IF
        _DMA-EXPECTED @ _DESK-REGISTRY @ CREG-INST-BY-DESC _DMA-INST !
    THEN
    _DMA-INST @ 0= IF CFACET-S-OK EXIT THEN
    _DMA-INST @ CINST-DESC _DMA-DESC !
    _DMA-A @ _DMA-U @ _DMA-DESC @ COMP-CAP-FIND DUP 0= IF
        DROP CFACET-S-OK EXIT
    THEN
    _DMA-CAP !
    _DMA-CAP @ CAP.EFFECTS @ _DMA-EFFECTS @ <> IF
        CFACET-S-INVALID EXIT
    THEN
    _DMA-INST @ CINST.ID @ _DMA-INST @ CINST.GENERATION @
    _DMA-EFFECTS @ _DMA-FLAGS @ _DMA-MAX-RESULT @
    _DMA-A @ _DMA-U @ _DESK-AGENT-FACET CFACET-ADD
    DUP IF EXIT THEN DROP
    _DMA-EFFECTS @ _DMF-EFFECTS @ OR _DMF-EFFECTS !
    CFACET-S-OK ;

CFENTRY-F-VISIBLE CFENTRY-F-INVOKE OR CFENTRY-F-AUTO-OBSERVE OR
CFENTRY-F-DISCLOSE-RESULT OR CONSTANT _DESK-AGENT-OBSERVE-FLAGS

CFENTRY-F-VISIBLE CFENTRY-F-INVOKE OR CFENTRY-F-REVIEW-COMMIT OR
CFENTRY-F-DISCLOSE-RESULT OR CONSTANT _DESK-AGENT-REVIEW-FLAGS

\ 4 KiB raw can expand roughly 6x in capability JSON and is escaped a second
\ time on the OpenAI continuation wire; larger results require pagination.
4096 CONSTANT _DESK-AGENT-TEXT-MAX

: _DESK-MANDATE-OBSERVE-LIST  ( -- status )
    S" org.akashic.daybook" _DESK-TRUSTED-COMP
        S" daybook.agenda.markdown" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS _DESK-AGENT-TEXT-MAX
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.daybook" _DESK-TRUSTED-COMP
        S" daybook.source" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS 516
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.pad" _DESK-TRUSTED-COMP
        S" pad.document.active" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS 516
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.pad" _DESK-TRUSTED-COMP
        S" pad.document.text" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS _DESK-AGENT-TEXT-MAX
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.fexplorer" _DESK-TRUSTED-COMP
        S" fexplorer.resource.selected" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS 516
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.fexplorer" _DESK-TRUSTED-COMP
        S" fexplorer.preview.text" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS _DESK-AGENT-TEXT-MAX
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.grid" _DESK-TRUSTED-COMP
        S" grid.cell.selected" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS 40
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.grid" _DESK-TRUSTED-COMP
        S" grid.workbook.csv" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS _DESK-AGENT-TEXT-MAX
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.grid" _DESK-TRUSTED-COMP
        S" grid.source" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS 516
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    \ Streams source discovery is deliberately read-only here.  The facet
    \ exposes sanitized source metadata, never endpoints/configuration, and
    \ grants no ambient refresh or registry mutation authority.
    S" org.akashic.streams" _DESK-TRUSTED-COMP
        S" streams.source.query" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS _DESK-AGENT-TEXT-MAX
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.streams" _DESK-TRUSTED-COMP
        S" streams.source.read" CAP-E-OBSERVE
        _DESK-AGENT-OBSERVE-FLAGS _DESK-AGENT-TEXT-MAX
        _DESK-MANDATE-CAP+ ;

: _DESK-MANDATE-REVIEW-LIST  ( -- status )
    S" org.akashic.daybook" _DESK-TRUSTED-COMP
        S" daybook.task.capture"
        CAP-E-MUTATE CAP-E-PERSIST OR _DESK-AGENT-REVIEW-FLAGS 8
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.pad" _DESK-TRUSTED-COMP
        S" pad.document.open" CAP-E-NAVIGATE
        _DESK-AGENT-REVIEW-FLAGS 516
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.fexplorer" _DESK-TRUSTED-COMP
        S" fexplorer.resource.reveal" CAP-E-NAVIGATE
        _DESK-AGENT-REVIEW-FLAGS 516
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.grid" _DESK-TRUSTED-COMP
        S" grid.cell.set-selected" CAP-E-MUTATE
        _DESK-AGENT-REVIEW-FLAGS 40
        _DESK-MANDATE-CAP+ ?DUP IF EXIT THEN
    S" org.akashic.grid" _DESK-TRUSTED-COMP
        S" grid.workbook.save" CAP-E-PERSIST
        _DESK-AGENT-REVIEW-FLAGS 8
        _DESK-MANDATE-CAP+ ;

: _DESK-MANDATE-COMPILE-ACCESS  ( -- status )
    _DMF-PROFILE @ AAP.FLAGS @ AAP-F-CONTEXT-OBSERVE AND IF
        _DESK-MANDATE-OBSERVE-LIST ?DUP IF EXIT THEN
    THEN
    _DMF-PROFILE @ AAP.FLAGS @ AAP-F-REVIEW-CHANGES AND IF
        _DESK-MANDATE-REVIEW-LIST ?DUP IF EXIT THEN
    THEN
    CFACET-S-OK ;

: _DESK-MANDATE-ID!  ( tag-a tag-u destination -- )
    _DMF-DEST ! _DMF-TAG-U ! _DMF-TAG-A !
    SHA3-256-BEGIN
    DESK-PRACTICE PHEAD.ID RID-SIZE SHA3-256-ADD
    _DESK-PRACTICE-ACTIVATION PACT.EPOCH 8 SHA3-256-ADD
    _DMF-RUN-ID 8 SHA3-256-ADD
    _DMF-CHILD @ CTX.ID 16 SHA3-256-ADD
    _DMF-TAG-A @ _DMF-TAG-U @ SHA3-256-ADD
    _DMF-DEST @ SHA3-256-END ;

: _DESK-MANDATE-FACTORY  ( run-id desk-instance -- mandate-run status )
    _DMF-DESK ! _DMF-RUN-ID !
    _DMF-DESK @ _DESK-USE-STATE
    DESK-RECOVERY? DESK-PRACTICE 0= OR IF 0 AMRUN-S-DENIED EXIT THEN
    _DESK-AGENT-RUNTIME @ ARUNTIME-ACCESS-PROFILE
        DUP 0= IF DROP 0 AMRUN-S-DENIED EXIT THEN
    DUP DAP-PROFILE-VALID? 0= IF DROP 0 AMRUN-S-DENIED EXIT THEN
    _DMF-PROFILE !
    \ Built-in targets are optional.  An empty exact facet is a legitimate
    \ chat-only run and never expands into the gateway's ambient catalog.
    DESK-CONTEXT CTX-CHILD-NEW DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP DUP _DMF-CHILD !
    DUP CTX.FLAGS DUP @ CTX-F-ACTIVE OR SWAP ! DROP

    _DESK-AGENT-FACET CFACET-INIT
    S" desk.agent.facet" _DESK-AGENT-FACET CFACET.ID _DESK-MANDATE-ID!
    DESK-PRACTICE PHEAD.ID _DESK-AGENT-FACET CFACET.PRACTICE-ID RID-COPY
    DESK-CONTEXT CTX.EPOCH @ _DESK-AGENT-FACET CFACET.EPOCH !
    _DMF-CHILD @ CTX.ID @ _DESK-AGENT-FACET CFACET.CONTEXT-ID !
    _DMF-CHILD @ CTX.GENERATION @ _DESK-AGENT-FACET CFACET.CONTEXT-GEN !
    1 _DESK-AGENT-FACET CFACET.REVISION !
    0 _DMF-EFFECTS !
    _DESK-MANDATE-COMPILE-ACCESS DUP _DMF-STATUS ! IF
        _DMF-CHILD @ CTX-FREE 0 _DMF-STATUS @ EXIT
    THEN

    _DESK-AGENT-MANDATE MAND-INIT
    S" desk.agent.mandate" _DESK-AGENT-MANDATE MAND.ID _DESK-MANDATE-ID!
    DESK-PRACTICE PHEAD.ID
        _DESK-AGENT-MANDATE MAND.PRACTICE-ID RID-COPY
    _DESK-AGENT-FACET CFACET.ID
        _DESK-AGENT-MANDATE MAND.INPUT-FACET-ID RID-COPY
    _DESK-AGENT-FACET CFACET.ID
        _DESK-AGENT-MANDATE MAND.DISCLOSURE-FACET-ID RID-COPY
    DESK-CONTEXT CTX.EPOCH @
        _DESK-AGENT-MANDATE MAND.ACTIVATION-EPOCH !
    CPRINC-AGENT _DESK-AGENT-MANDATE MAND.PRINCIPAL !
    _DMF-CHILD @ CTX.ID @ _DESK-AGENT-MANDATE MAND.CONTEXT-ID !
    _DMF-CHILD @ CTX.GENERATION @
        _DESK-AGENT-MANDATE MAND.CONTEXT-GENERATION !
    _DMF-EFFECTS @ _DESK-AGENT-MANDATE MAND.EFFECTS !
    _DMF-EFFECTS @ CAP-E-NAVIGATE CAP-E-MUTATE OR CAP-E-PERSIST OR AND IF
        _DMF-PROFILE @ AAP.DISPOSITION @
    ELSE
        MAND-D-READ-ONLY
    THEN _DESK-AGENT-MANDATE MAND.DISPOSITION !
    _DMF-PROFILE @ AAP.TIME-BUDGET-MS @
        _DESK-AGENT-MANDATE MAND.TIME-BUDGET-MS !
    _DMF-PROFILE @ AAP.MEMORY-BUDGET @
        _DESK-AGENT-MANDATE MAND.MEMORY-BUDGET !
    _DMF-PROFILE @ AAP.TOKEN-BUDGET @
        _DESK-AGENT-MANDATE MAND.TOKEN-BUDGET !
    _DESK-AGENT-FACET CFACET.COUNT @ IF
        _DMF-PROFILE @ AAP.TOOL-BUDGET @
    ELSE
        0
    THEN _DESK-AGENT-MANDATE MAND.TOOL-BUDGET !
    _DMF-PROFILE @ AAP.DISCLOSURE-BUDGET @
        _DESK-AGENT-MANDATE MAND.DISCLOSURE-BUDGET !
    DESK-PRACTICE _DMF-CHILD @ _DESK-AGENT-MANDATE _DESK-AGENT-FACET
        AMRUN-NEW DUP IF
        _DMF-STATUS ! DROP _DMF-CHILD @ CTX-FREE
        0 _DMF-STATUS @
    THEN ;

: _DESK-INTEROP-INIT  ( desk-instance -- )
    DUP _DINI-INST ! _DESK-USE-STATE
    DESK-CONTEXT DUP 0= ABORT" desk: no active Practice Context"
    _DINI-CONTEXT !
    MTRUST-FREEZE MTRUST-S-OK <>
    ABORT" desk: machine TLS trust unavailable"
    _DESK-XIO-INIT XIO-S-OK <>
    ABORT" desk: external I/O service unavailable"
    0 _DESK-INSTALLED-N !
    CREG-NEW 0<> ABORT" desk: registry allocation failed" _DESK-REGISTRY !
    CPOLICY-SIZE ALLOCATE
    0<> ABORT" desk: policy allocation failed"
    DUP _DESK-POLICY ! CPOLICY-INIT
    CINT-NEW 0<> ABORT" desk: intent router allocation failed" _DESK-INTENTS !
    CJOB-TABLE-NEW 0<> ABORT" desk: job table allocation failed" _DESK-JOBS !
    _DESK-REGISTRY @ _DESK-POLICY @ CBUS-NEW
    0<> ABORT" desk: request bus allocation failed" _DESK-BUS !
    _DINI-CONTEXT @ CTX.EPOCH @ RANDOM AHT-NEW
    0<> ABORT" desk: authority table allocation failed" _DESK-AUTHORITY !
    _DESK-AUTHORITY @ _DESK-BUS @ CBUS-AUTHORITY!
    _DESK-AUTHORITY @ _DINI-CONTEXT @ CTX.AUTHORITY !
    _DESK-BUS @ _DINI-CONTEXT @ CTX.QUEUE !
    _DESK-POLICY @ _DINI-CONTEXT @ CTX.POLICY !
    VFS-CUR _DINI-CONTEXT @ CTX.VFS !
    _DESK-DAYBOOK-INIT
    _DESK-PENDING-AGENT-SOURCE @ ?DUP 0= IF
        OFFLINE-SOURCE-NEW
        0<> ABORT" desk: offline source allocation failed"
    THEN
    0 _DESK-PENDING-AGENT-SOURCE !
    DUP _DESK-AGENT-SOURCE !
    APSOURCE-PROVIDER-NEW
    0<> ABORT" desk: agent provider allocation failed" _DESK-AGENT-PROVIDER !
    _DESK-AGENT-PROVIDER @ ARUNTIME-NEW
    0<> ABORT" desk: agent runtime allocation failed" _DESK-AGENT-RUNTIME !
    _DESK-BIND-AGENT-STORE
    _DESK-REGISTRY @ _DESK-BUS @ _DINI-INST @ ATOOLG-NEW
    0<> ABORT" desk: agent tool gateway allocation failed"
    DUP _DESK-TOOL-GATEWAY !
    _DESK-AGENT-RUNTIME @ ARUNTIME-TOOL-GATEWAY!
    ['] _DESK-MANDATE-FACTORY _DINI-INST @
        _DESK-AGENT-RUNTIME @ ARUNTIME-MANDATE-FACTORY!
    ['] DAP-RUNTIME-POLICY ['] DAP-RUNTIME-VALID? 0
        _DESK-AGENT-RUNTIME @ ARUNTIME-ACCESS-POLICY!
    ABORT" desk: agent access policy binding failed"
    _DESK-TOOL-GATEWAY @ _DESK-AGENT-PROVIDER @ APROV-BIND-TOOLS
    ABORT" desk: provider tool binding failed"
    _DESK-PENDING-AGENT-ACCESS @ _DESK-AGENT-RUNTIME @
        ARUNTIME-ACCESS-PRESET!
    ABORT" desk: unavailable or invalid agent access preset"

    _DESK-SERVICE-TABLE-SETUP _DSS-S-OK <>
    ABORT" desk: service table setup failed"
    _DESK-ENDPOINT IENDPOINT-INIT
    _DINI-INST @ _DESK-ENDPOINT IEND.CONTEXT !
    ['] _DESK-ENDPOINT-POST _DESK-ENDPOINT IEND.POST-XT !
    ['] _DESK-ENDPOINT-INTENT _DESK-ENDPOINT IEND.INTENT-XT !
    ['] _DESK-ENDPOINT-SERVICE _DESK-ENDPOINT IEND.SERVICE-XT !
    _DESK-ENDPOINT _DINI-INST @ CINST.ENDPOINT !

    _DESK-CATALOG-INIT

    DESK-COMP-DESC _DESK-REGISTRY @ CREG-TYPE-ENSURE
    ABORT" desk: could not register Desk type"
    _DINI-INST @ _DESK-REGISTRY @ CREG-INST+
    ABORT" desk: could not register Desk instance"

    SCR-H 1- 0 1 SCR-W RGN-NEW DUP _DESK-AGENT-PROMPT-RGN !
    _DESK-AGENT-PROMPT-BUF _DESK-AGENT-PROMPT-CAP PRM-NEW
    DUP _DESK-AGENT-PROMPT !
    ['] _DESK-AGENT-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
    ['] _DESK-AGENT-PROMPT-CANCEL OVER PRM-ON-CANCEL
    _DTH-TBAR-FG @ _DTH-TBAR-BG @ ROT PRM-COLORS! ;

VARIABLE _DIFI-XIO-STATUS

: _DESK-DAYBOOK-ACTIVATION-CLEANUP  ( -- )
    \ Failed owner publication leaves no instance for SDOC-DEACTIVATE, but
    \ its retryable rollback can still own a pool which borrows this exact
    \ Context and both registries.  Finish that rollback before freeing any
    \ of those dependencies.
    BEGIN
        DESK-CONTEXT _DESK-RREG @ _DESK-REGISTRY @
            SDOC-ACTIVATION-CLEANUP
        DUP SDOC-S-RESOURCE =
    WHILE
        DROP YIELD?
    REPEAT
    SDOC-S-OK <> ABORT" desk: shared document activation cleanup failed" ;

: _DESK-DAYBOOK-DEACTIVATE  ( -- )
    _DESK-DAYBOOK-OWNER @ ?DUP 0= IF EXIT THEN
    \ A failed final anchor release preserves the exact live owner and token.
    \ Finish that retry while Desk still owns the borrowed runtime graph.
    BEGIN
        DUP SDOC-DEACTIVATE
        DUP SDOC-S-RESOURCE =
    WHILE
        DROP YIELD?
    REPEAT
    NIP SDOC-S-OK <>
        ABORT" desk: shared document teardown failed" ;

: _DESK-INTEROP-FINI-QUIESCED  ( -- )
    XIO-S-OK _DIFI-XIO-STATUS !
    _DESK-XIO-DRAIN ?DUP IF _DIFI-XIO-STATUS ! THEN
    _DESK-XIO-FINI ?DUP IF
        _DIFI-XIO-STATUS @ XIO-S-OK = IF
            _DIFI-XIO-STATUS !
        ELSE
            DROP
        THEN
    THEN
    _DESK-AGENT-PROMPT @ ?DUP IF PRM-FREE THEN
    _DESK-AGENT-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _DESK-BUS @ ?DUP IF
        DUP CBUS-CANCEL-ALL DROP
    THEN
    _DESK-SERVICE-TABLE-FINI
    _DESK-DAYBOOK-DEACTIVATE
    _DESK-DAYBOOK-ACTIVATION-CLEANUP
    _DESK-RREG @ ?DUP IF RREG-FREE THEN
    _DESK-AGENT-RUNTIME @ ?DUP IF
        DUP ARUNTIME-ACCESS-PROFILE ?DUP IF
            AAP.PRESET @ _DESK-PENDING-AGENT-ACCESS !
        THEN
        ARUNTIME-FREE
    THEN
    _DESK-TOOL-GATEWAY @ ?DUP IF ATOOLG-FREE THEN
    _DESK-BUS @ ?DUP IF CBUS-FREE THEN
    _DESK-AUTHORITY @ ?DUP IF AHT-FREE THEN
    _DESK-AGENT-PROVIDER @ ?DUP IF APROV-FREE THEN
    _DESK-AGENT-SOURCE @ ?DUP IF APSOURCE-FREE THEN
    _DESK-JOBS @ ?DUP IF CJOB-TABLE-FREE THEN
    _DESK-INTENTS @ ?DUP IF CINT-FREE THEN
    _DESK-POLICY @ ?DUP IF FREE THEN
    _DESK-REGISTRY @ ?DUP IF CREG-FREE THEN
    0 ABUILD-CATALOG!
    _DESK-CATALOG @ ?DUP IF ACAT-FREE THEN
    DESK-CONTEXT ?DUP IF
        0 OVER CTX.AUTHORITY !
        0 OVER CTX.QUEUE !
        0 SWAP CTX.POLICY !
    THEN
    0 _DESK-BUS ! 0 _DESK-AUTHORITY ! 0 _DESK-JOBS ! 0 _DESK-INTENTS !
    0 _DESK-POLICY ! 0 _DESK-REGISTRY ! 0 _DESK-RREG !
    0 _DESK-DAYBOOK-OWNER !
    SDOC-S-INVALID _DESK-DAYBOOK-STATUS !
    _DESK-DAYBOOK-RID RID-CLEAR
    0 _DESK-CATALOG !
    0 _DESK-AGENT-SOURCE !
    0 _DESK-AGENT-RUNTIME ! 0 _DESK-AGENT-PROVIDER !
    0 _DESK-TOOL-GATEWAY !
    0 _DESK-AGENT-PROMPT ! 0 _DESK-AGENT-PROMPT-RGN !
    _DESK-ENDPOINT IENDPOINT-SIZE 0 FILL
    _DIFI-XIO-STATUS @ ?DUP IF THROW THEN ;

: _DESK-INTEROP-FINI  ( -- )
    \ Children are already closed.  Keep cancellation, owner unpublication,
    \ registry teardown, and bus free inside one dispatch-quiesced boundary so
    \ no stale endpoint can begin work between those dependent lifetime steps.
    ['] _DESK-INTEROP-FINI-QUIESCED CBUS-WITH-DISPATCH-QUIESCED ;

\ =====================================================================
\  §9 — Taskbar Painter
\ =====================================================================

CREATE _DESK-TB-BUF  256 ALLOT
VARIABLE _DESK-TB-POS

: _DTB-CH  ( ch -- )
    _DESK-TB-BUF _DESK-TB-POS @ + C!
    1 _DESK-TB-POS +! ;

: _DTB-STR  ( addr u -- )
    0 ?DO DUP I + C@ _DTB-CH LOOP DROP ;

: _DTB-DIGIT  ( n -- )
    DUP 10 < IF 48 + _DTB-CH EXIT THEN
    DUP 100 < IF
        DUP 10 / 48 + _DTB-CH
        10 MOD 48 + _DTB-CH EXIT
    THEN
    DUP 100 / 48 + _DTB-CH
    DUP 10 / 10 MOD 48 + _DTB-CH
    10 MOD 48 + _DTB-CH ;

\ Build the exact live-slot label used by both painting and pointer
\ hit-testing.  The separator cell is deliberately not part of the label.
: _DESK-TASKBAR-LABEL  ( slot -- addr len )
    0 _DESK-TB-POS !
    91 _DTB-CH
    DUP _SL-ID @ _DTB-DIGIT
    58 _DTB-CH
    DUP _SL-DESC @ ?DUP IF
        APP.TITLE-A @ ?DUP IF
            OVER _SL-DESC @ APP.TITLE-U @
            DUP 10 > IF DROP 10 THEN
            _DTB-STR
        ELSE S" App" _DTB-STR THEN
    ELSE S" App" _DTB-STR THEN
    DUP _SL-STATE @ _ST-FOCUSED = IF 42 _DTB-CH THEN
    _SL-STATE @ _ST-MINIMIZED = IF 126 _DTB-CH THEN
    93 _DTB-CH
    _DESK-TB-BUF _DESK-TB-POS @ ;

VARIABLE _DTB-COL
VARIABLE _DTB-ROW
VARIABLE _DAS-A
VARIABLE _DAS-U
VARIABLE _DAS-COL

: _DESK-AGENT-STATE-TEXT  ( -- addr len )
    DESK-RECOVERY? IF S" [Practice: recovery]" EXIT THEN
    _DESK-PRACTICE-ACTIVATION PACT-FALLBACK? IF
        S" [Practice: fallback]" EXIT
    THEN
    _DESK-AGENT-RUNTIME @ 0= IF S" [Agent: unavailable]" EXIT THEN
    _DESK-AGENT-RUNTIME @ ARUNTIME.STORE-STATUS @ ACSTORE-S-OK <> IF
        S" [Agent: history error]" EXIT
    THEN
    _DESK-AGENT-RUNTIME @ ARUNTIME.STATUS @ CASE
        ARUN-S-IDLE OF S" [Agent: ready]" ENDOF
        ARUN-S-RUNNING OF S" [Agent: working]" ENDOF
        ARUN-S-APPROVAL OF S" [Agent: review]" ENDOF
        ARUN-S-OFFLINE OF S" [Agent: offline]" ENDOF
        ARUN-S-ERROR OF S" [Agent: error]" ENDOF
        ARUN-S-CANCELLED OF S" [Agent: cancelled]" ENDOF
        ARUN-S-EXPIRED OF S" [Agent: expired]" ENDOF
        S" [Agent: unknown]" ROT
    ENDCASE ;

: _DESK-PAINT-AGENT-STATE  ( -- )
    _DESK-AGENT-STATE-TEXT _DAS-U ! _DAS-A !
    SCR-W _DAS-U @ - 1- 0 MAX _DAS-COL !
    _DAS-COL @ _DTB-COL @ <= IF EXIT THEN
    _DESK-AGENT-RUNTIME @ ?DUP IF
        ARUNTIME.STATUS @ ARUN-S-APPROVAL =
    ELSE
        0
    THEN IF
        0 220 1 DRW-STYLE!
    ELSE
        _DTH-CLOCK-FG @ _DTH-CLOCK-BG @ 0 DRW-STYLE!
    THEN
    _DAS-A @ _DAS-U @ _DTB-ROW @ _DAS-COL @ DRW-TEXT ;

: _DESK-PAINT-TASKBAR  ( -- )
    DRW-STYLE-SAVE
    _DTH-TBAR-FG @ _DTH-TBAR-BG @ _DTH-TBAR-ATTR @ DRW-STYLE!
    SCR-H 1- _DTB-ROW !
    32 _DTB-ROW @ 0 1 SCR-W DRW-FILL-RECT
    0 _DTB-COL !
    \ ---- running slot entries ----
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        \ Per-slot style
        DUP _SL-STATE @ _ST-FOCUSED = IF
            _DTH-ACT-FG @ _DTH-ACT-BG @ _DTH-ACT-ATTR @ DRW-STYLE!
        ELSE DUP _SL-STATE @ _ST-MINIMIZED = IF
            _DTH-MIN-FG @ _DTH-MIN-BG @ 0 DRW-STYLE!
        ELSE
            _DTH-TBAR-FG @ _DTH-TBAR-BG @ _DTH-TBAR-ATTR @ DRW-STYLE!
        THEN THEN
        \ Build label: [id:title*] or [id:title~]
        DUP _DESK-TASKBAR-LABEL
        _DTB-ROW @ _DTB-COL @ DRW-TEXT
        _DESK-TB-POS @ _DTB-COL +!
        \ space separator
        32 _DTB-ROW @ _DTB-COL @ DRW-CHAR
        1 _DTB-COL +!
        _SL-NEXT @
    REPEAT
    \ ---- hotbar entries ----
    _DESK-HOTBAR-PROJECTION-COUNT IF
        _DTH-DIV-FG @ _DTH-DIV-BG @ 0 DRW-STYLE!
        124 _DTB-ROW @ _DTB-COL @ DRW-CHAR    \ '|'
        1 _DTB-COL +!
        32 _DTB-ROW @ _DTB-COL @ DRW-CHAR
        1 _DTB-COL +!
        _DESK-CATALOG @ IF
            _DTB-ROW @ _DTB-COL @ _DESK-PAINT-CATALOG-HOTBAR
        ELSE
            _DTB-ROW @ _DTB-COL @ _DESK-PAINT-HOTBAR
        THEN
    THEN
    _DESK-PAINT-AGENT-STATE
    DRW-STYLE-RESTORE ;

VARIABLE _DTS-COL
VARIABLE _DTS-START
VARIABLE _DTS-END

: _DESK-TASKBAR-SLOT-AT  ( col -- slot | 0 )
    _DTS-COL ! 0 _DTS-START !
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _DESK-TASKBAR-LABEL NIP
        _DTS-START @ + _DTS-END !
        _DTS-COL @ _DTS-START @ >=
        _DTS-COL @ _DTS-END @ < AND IF EXIT THEN
        _DTS-END @ 1+ _DTS-START !
        _SL-NEXT @
    REPEAT
    0 ;

\ =====================================================================
\  §10 — APP-DESC Callbacks
\ =====================================================================
\
\  The DESK is a normal APP-DESC app.  The shell calls these
\  callbacks — no private event loop, no APP-INIT/APP-SHUTDOWN.

\ --- Init ---
: DESK-INIT-CB  ( instance -- )
    DUP _DINI-INST ! _DESK-USE-STATE
    _DESK-HOST AHOST-INIT
    _DINI-INST @ _DESK-HOST AHOST-CONTEXT!
    ['] _DESK-HOST-RELAYOUT _DESK-HOST AHOST-RELAYOUT!
    ['] _DESK-HOST-RELEASE _DESK-HOST AHOST-RELEASE!
    ['] _DESK-HOST-CLOSED _DESK-HOST AHOST-CLOSED!
    0 _DESK-VH !
    0 _DESK-FULLFRAME !
    0 _DESK-CATALOG !
    0 _DESK-LAUNCHER-ACTIVE !
    0 _DESK-LAUNCHER-SELECTED !
    0 _DESK-LAUNCHER-SCROLL !
    0 _DESK-LAUNCHER-STATUS !
    0 _DESK-RREG !
    0 _DESK-DAYBOOK-OWNER !
    SDOC-S-INVALID _DESK-DAYBOOK-STATUS !
    _DESK-DAYBOOK-RID RID-CLEAR
    -1 _DESK-BG-DIRTY !
    SCR-W _DESK-LAST-W !
    SCR-H _DESK-LAST-H !
    0 ASHELL-CTX-SWITCH
    _DESK-THEME-DEFAULTS
    _DESK-HOTBAR-CLEAR
    \ Load config if a buffer was supplied before DESK-RUN
    _DESK-CFG-A @ ?DUP IF _DESK-CFG-L @ DESK-LOAD-CONFIG THEN
    _DESK-PRACTICE-ACTIVATION PACT-INIT
    VFS-CUR _DESK-PRACTICE-ACTIVATION PACT-ACTIVATE
    DUP PACT-S-OK <> SWAP PACT-S-RECOVERY <> AND
    ABORT" desk: Practice activation failed"
    DESK-RECOVERY? IF
        0 _DESK-PEND-N ! EXIT
    THEN
    _DINI-INST @ _DESK-INTEROP-INIT
    _DESK-REGISTRY @ _DESK-HOST AHOST-REGISTRY!
    _DESK-ENDPOINT _DESK-HOST AHOST-ENDPOINT!
    \ DESK-QUEUE-LAUNCH rows were migrated by _DESK-CATALOG-INIT.
    \ Autostart now honors their persisted enabled/quarantine flags.
    _DESK-AUTOSTART-CATALOG
    0 _DESK-PEND-N ! ;

\ --- Shortcuts ---
CREATE _DESK-EV  24 ALLOT

: _DESK-EV-TYPE  ( ev -- type )  @ ;
: _DESK-EV-CODE  ( ev -- code )  8 + @ ;
: _DESK-EV-MODS  ( ev -- mods )  16 + @ ;

: _DESK-ALT?  ( ev ch -- flag )
    OVER _DESK-EV-MODS KEY-MOD-ALT AND IF
        SWAP _DESK-EV-CODE =
    ELSE
        2DROP 0
    THEN ;

: _DESK-CYCLE-FOCUS  ( -- )
    _DESK-FOCUS-SA @ 0= IF EXIT THEN
    _DESK-FOCUS-SA @ _SL-NEXT @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _SL-ID @ DESK-FOCUS-ID EXIT
        THEN
        _SL-NEXT @
    REPEAT
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _SL-ID @ DESK-FOCUS-ID EXIT
        THEN
        _SL-NEXT @
    REPEAT ;

\ ---------------------------------------------------------------------
\ Catalog launcher.  This is a Desk-owned modal state machine, not a
\ blocking dialog, so the shell's normal event/tick loop remains live.

VARIABLE _DLA-COUNT
VARIABLE _DLA-PAGE
VARIABLE _DLA-ENTRY
VARIABLE _DLA-W
VARIABLE _DLA-H
VARIABLE _DLA-ROW
VARIABLE _DLA-COL
VARIABLE _DLA-LABEL-A
VARIABLE _DLA-LABEL-U
VARIABLE _DLA-STATUS-A
VARIABLE _DLA-STATUS-U

: _DESK-LAUNCHER-COUNT  ( -- n )
    _DESK-CATALOG @ ?DUP IF ACAT-COUNT ELSE 0 THEN ;

: _DESK-LAUNCHER-PAGE  ( -- n )
    SCR-H 8 - 1 MAX 10 MIN ;

: _DESK-LAUNCHER-ENSURE-VISIBLE  ( -- )
    _DESK-LAUNCHER-COUNT DUP _DLA-COUNT ! 0= IF
        0 _DESK-LAUNCHER-SELECTED ! 0 _DESK-LAUNCHER-SCROLL ! EXIT
    THEN
    _DESK-LAUNCHER-SELECTED @ 0 MAX _DLA-COUNT @ 1- MIN
    DUP _DESK-LAUNCHER-SELECTED !
    _DESK-LAUNCHER-SCROLL @ OVER > IF
        DUP _DESK-LAUNCHER-SCROLL !
    THEN
    _DESK-LAUNCHER-PAGE _DLA-PAGE !
    DUP _DESK-LAUNCHER-SCROLL @ _DLA-PAGE @ + >= IF
        _DLA-PAGE @ - 1+ 0 MAX _DESK-LAUNCHER-SCROLL !
    ELSE
        DROP
    THEN ;

: _DESK-LAUNCHER-MOVE  ( delta -- )
    _DESK-LAUNCHER-SELECTED @ +
    _DESK-LAUNCHER-COUNT DUP 0= IF 2DROP EXIT THEN
    1- MIN 0 MAX _DESK-LAUNCHER-SELECTED !
    0 _DESK-LAUNCHER-STATUS !
    _DESK-LAUNCHER-ENSURE-VISIBLE
    ASHELL-DIRTY! ;

: _DESK-LAUNCHER-HIDE  ( -- )
    0 _DESK-LAUNCHER-ACTIVE !
    -1 _DESK-BG-DIRTY !
    _DESK-MARK-ALL-CHILDREN
    ASHELL-DIRTY! ;

: _DESK-SHOW-LAUNCHER  ( -- )
    _DESK-AGENT-PROMPT @ ?DUP IF PRM-HIDE THEN
    -1 _DESK-LAUNCHER-ACTIVE !
    0 _DESK-LAUNCHER-SELECTED !
    0 _DESK-LAUNCHER-SCROLL !
    0 _DESK-LAUNCHER-STATUS !
    _DESK-LAUNCHER-ENSURE-VISIBLE
    ASHELL-DIRTY! ;

: _DESK-LAUNCHER-ACTIVATE  ( -- )
    _DESK-LAUNCHER-COUNT 0= IF
        ACAT-S-NOT-FOUND _DESK-LAUNCHER-STATUS !
        ASHELL-DIRTY! EXIT
    THEN
    _DESK-LAUNCHER-SELECTED @ _DESK-CATALOG @ ACAT-NTH
    DUP 0= IF
        DROP ACAT-S-NOT-FOUND _DESK-LAUNCHER-STATUS !
        ASHELL-DIRTY! EXIT
    THEN
    _DESK-OPEN-CATALOG-ENTRY DUP _DESK-LAUNCHER-STATUS !
    IF
        ASHELL-DIRTY!
    ELSE
        \ Opening from the interactive launcher transfers focus to the
        \ selected applet.  Startup catalog activation deliberately keeps
        \ its existing first-app focus policy.
        _DCO-SLOT @ DESK-FOCUS-ID
        _DESK-LAUNCHER-HIDE
    THEN ;

: _DESK-LAUNCHER-HANDLE  ( ev -- consumed? )
    DUP _DESK-EV-TYPE KEY-T-SPECIAL <> IF DROP -1 EXIT THEN
    _DESK-EV-CODE CASE
        KEY-ESC OF _DESK-LAUNCHER-HIDE ENDOF
        KEY-UP OF -1 _DESK-LAUNCHER-MOVE ENDOF
        KEY-DOWN OF 1 _DESK-LAUNCHER-MOVE ENDOF
        KEY-PGUP OF _DESK-LAUNCHER-PAGE NEGATE _DESK-LAUNCHER-MOVE ENDOF
        KEY-PGDN OF _DESK-LAUNCHER-PAGE _DESK-LAUNCHER-MOVE ENDOF
        KEY-HOME OF
            0 _DESK-LAUNCHER-SELECTED !
            0 _DESK-LAUNCHER-STATUS !
            _DESK-LAUNCHER-ENSURE-VISIBLE ASHELL-DIRTY!
        ENDOF
        KEY-END OF
            _DESK-LAUNCHER-COUNT 1- 0 MAX _DESK-LAUNCHER-SELECTED !
            0 _DESK-LAUNCHER-STATUS !
            _DESK-LAUNCHER-ENSURE-VISIBLE ASHELL-DIRTY!
        ENDOF
        KEY-ENTER OF _DESK-LAUNCHER-ACTIVATE ENDOF
        DROP
    ENDCASE
    -1 ;

: _DESK-CATALOG-STATUS$  ( status -- a u )
    DUP 0< IF DROP S" launch failed" EXIT THEN
    CASE
        ACAT-S-OK OF S" ready" ENDOF
        ACAT-S-MISSING OF S" catalog missing" ENDOF
        ACAT-S-INVALID OF S" invalid catalog" ENDOF
        ACAT-S-IO OF S" storage error" ENDOF
        ACAT-S-FULL OF S" catalog full" ENDOF
        ACAT-S-DUPLICATE OF S" duplicate ID" ENDOF
        ACAT-S-NOT-FOUND OF S" not found" ENDOF
        ACAT-S-READONLY OF S" read-only" ENDOF
        ACAT-S-NO-RESOLVER OF S" loader unavailable" ENDOF
        ACAT-S-RESOLVE OF S" load failed" ENDOF
        ACAT-S-INCOMPATIBLE OF S" incompatible" ENDOF
        ACAT-S-QUARANTINED OF S" quarantined" ENDOF
        ACAT-S-DISABLED OF S" disabled" ENDOF
        ACAT-S-RECOVERY OF S" recovery mode" ENDOF
        ACAT-S-BUSY OF S" applet is open" ENDOF
        DROP S" unknown error"
    ENDCASE ;

: _DESK-CATALOG-ENTRY-STATUS$  ( entry -- a u )
    DUP ACE-QUARANTINED? IF DROP S" quarantined" EXIT THEN
    DUP ACE-ENABLED? 0= IF DROP S" disabled" EXIT THEN
    DUP ACE.SLOT @ IF DROP S" running" EXIT THEN
    DUP ACE.STATE @ ACAT-R-FAILED = IF DROP S" load failed" EXIT THEN
    DUP ACE-BUILTIN? OVER ACE.STATE @ ACAT-R-UNBOUND = AND IF
        DROP S" unavailable" EXIT
    THEN
    DROP S" ready" ;

: _DESK-PAINT-LAUNCHER-ENTRY  ( index screen-row -- )
    >R
    DUP _DESK-CATALOG @ ACAT-NTH _DLA-ENTRY !
    DUP _DESK-LAUNCHER-SELECTED @ = IF
        _DTH-ACT-FG @ _DTH-ACT-BG @ _DTH-ACT-ATTR @ DRW-STYLE!
        62
    ELSE
        _DTH-TBAR-FG @ _DTH-TBAR-BG @ 0 DRW-STYLE!
        32
    THEN
    NIP
    R@ _DLA-COL @ 1+ DRW-CHAR
    _DLA-ENTRY @ ACE-TITLE$ DUP 0= IF
        2DROP _DLA-ENTRY @ ACE-ID$
    THEN
    DUP _DLA-W @ 22 - 1 MAX > IF DROP _DLA-W @ 22 - 1 MAX THEN
    _DLA-LABEL-U ! _DLA-LABEL-A !
    _DLA-LABEL-A @ _DLA-LABEL-U @ R@ _DLA-COL @ 3 + DRW-TEXT
    _DLA-ENTRY @ _DESK-CATALOG-ENTRY-STATUS$
    _DLA-STATUS-U ! _DLA-STATUS-A !
    _DLA-STATUS-A @ _DLA-STATUS-U @ R@
    _DLA-COL @ _DLA-W @ + _DLA-STATUS-U @ - 2 - DRW-TEXT
    R> DROP ;

: _DESK-PAINT-LAUNCHER  ( -- )
    _DESK-LAUNCHER-ACTIVE @ 0= IF EXIT THEN
    _DESK-LAUNCHER-ENSURE-VISIBLE
    SCR-W 4 - 68 MIN DUP 24 < IF DROP SCR-W 2 - THEN _DLA-W !
    _DESK-LAUNCHER-PAGE DUP _DLA-PAGE ! 4 + _DLA-H !
    SCR-H _DLA-H @ - 2 / 0 MAX _DLA-ROW !
    SCR-W _DLA-W @ - 2 / 0 MAX _DLA-COL !
    DRW-STYLE-SAVE
    _DTH-TBAR-FG @ _DTH-TBAR-BG @ 0 DRW-STYLE!
    32 _DLA-ROW @ _DLA-COL @ _DLA-H @ _DLA-W @ DRW-FILL-RECT
    S" Applets" _DLA-ROW @ _DLA-COL @ 2 + DRW-TEXT
    _DESK-LAUNCHER-STATUS @ DUP IF
        _DESK-CATALOG-STATUS$
    ELSE
        DROP _DESK-CATALOG @ ?DUP IF ACAT-RECOVERY? ELSE 0 THEN IF
            S" catalog recovery: read-only"
        ELSE
            S" select an applet"
        THEN
    THEN
    _DLA-ROW @ 1+ _DLA-COL @ 2 + DRW-TEXT
    _DLA-PAGE @ 0 ?DO
        _DESK-LAUNCHER-SCROLL @ I + DUP
        _DESK-LAUNCHER-COUNT < IF
            _DLA-ROW @ 2 + I + _DESK-PAINT-LAUNCHER-ENTRY
        ELSE
            DROP
        THEN
    LOOP
    S" Up/Down PgUp/PgDn Home/End  Enter open  Esc close"
    DUP _DLA-W @ 4 - > IF DROP _DLA-W @ 4 - THEN
    _DLA-ROW @ _DLA-H @ + 1- _DLA-COL @ 2 + DRW-TEXT
    DRW-STYLE-RESTORE ;

\ Launch the first unlaunched hotbar entry.
\ file field = .m64 binary path, desc field = entry word name.
: _DESK-HOTBAR-LAUNCH-NEXT  ( -- )
    _DESK-SHOW-LAUNCHER ;

: _DESK-SHORTCUT?  ( ev -- flag )
    DUP _DESK-EV-TYPE KEY-T-CHAR <> IF DROP 0 EXIT THEN
    DUP _DESK-EV-CODE 32 =
    OVER _DESK-EV-MODS KEY-MOD-CTRL AND 0<> AND IF
        DROP _DESK-SHOW-AGENT-PROMPT -1 EXIT
    THEN
    DUP _DESK-EV-MODS KEY-MOD-ALT AND IF
        DUP _DESK-EV-CODE DUP 49 >= SWAP 57 <= AND IF
            DUP _DESK-EV-CODE 48 - DESK-FOCUS-ID
            DROP -1 EXIT
        THEN
    THEN
    DUP 9 _DESK-ALT? IF DROP _DESK-CYCLE-FOCUS -1 EXIT THEN
    DUP 109 _DESK-ALT? IF
        DROP _DESK-FOCUS-SA @ ?DUP IF
            _SL-ID @ DESK-MINIMIZE-ID
        THEN -1 EXIT THEN
    DUP 114 _DESK-ALT? IF DROP DESK-RESTORE -1 EXIT THEN
    DUP 102 _DESK-ALT? IF
        DROP _DESK-FULLFRAME @ 0= DESK-FULLFRAME!
        -1 EXIT THEN
    DUP 108 _DESK-ALT? IF DROP DESK-TOGGLE-VH -1 EXIT THEN
    DUP 119 _DESK-ALT? IF
        DROP _DESK-FOCUS-SA @ ?DUP IF
            _SL-ID @ DESK-CLOSE-ID
        THEN -1 EXIT THEN
    DUP 104 _DESK-ALT? IF
        DROP _DESK-SHOW-LAUNCHER -1 EXIT THEN
    DUP 97 _DESK-ALT? IF
        DROP _DESK-SHOW-AGENT-PROMPT -1 EXIT THEN
    DROP 0 ;

\ _DESK-TILE-AT ( row col -- slot | 0 )
\   Compatibility view of the generic host hit test.
: _DESK-TILE-AT  ( row col -- slot | 0 )
    _DESK-HOST AHOST-TILE-AT ;

: _DESK-DISPATCH-TASKBAR  ( ev -- handled? )
    DUP ASHELL-MOUSE-BTN KEY-MOUSE-LEFT <> IF DROP 0 EXIT THEN
    DUP ASHELL-MOUSE-ROW SCR-H 1- <> IF DROP 0 EXIT THEN
    ASHELL-MOUSE-COL _DESK-TASKBAR-SLOT-AT ?DUP IF
        _SL-ID @ DESK-FOCUS-ID -1
    ELSE
        0
    THEN ;

: _DESK-DISPATCH-MOUSE  ( ev -- handled? )
    DUP _DESK-DISPATCH-TASKBAR IF DROP -1 EXIT THEN
    _DESK-HOST AHOST-DISPATCH-MOUSE ;

\ --- Event ---
\
\  Routes events to the focused sub-app.  If the sub-app calls
\  ASHELL-QUIT, we intercept it via ASHELL-QUIT-PENDING? /
\  ASHELL-CANCEL-QUIT, and close that tile instead of shutting
\  down the whole shell.
: DESK-EVENT-CB  ( ev instance -- flag )
    _DESK-USE-STATE
    _DESK-LAUNCHER-ACTIVE @ IF _DESK-LAUNCHER-HANDLE EXIT THEN
    _DESK-AGENT-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    DUP ASHELL-MOUSE? IF
        _DESK-DISPATCH-MOUSE EXIT
    THEN
    DUP _DESK-SHORTCUT? IF DROP -1 EXIT THEN
    _DESK-HOST AHOST-DISPATCH-KEY ;

\ --- Tick ---
: DESK-TICK-CB  ( instance -- )
    _DESK-USE-STATE
    _DESK-HOST AHOST-FOCUSED-INSTANCE
    _DESK-TOOL-GATEWAY @ ?DUP IF
        ATOOLG-FOCUSED! DROP
    ELSE
        DROP
    THEN
    _DESK-AGENT-RUNTIME @ ?DUP IF
        8 SWAP ARUNTIME-PUMP ?DUP IF
            DROP _DESK-MARK-ALL-CHILDREN ASHELL-DIRTY!
        THEN
    THEN
    _DESK-BUS @ ?DUP IF 8 SWAP CBUS-PUMP DROP THEN
    _DESK-XIO-READY? IF _DESK-EXTERNAL-IO XIO-TICK THEN
    _DESK-HOST AHOST-TICK ;

\ --- Paint ---
\
\  Iterates visible sub-apps, context-switches to each, and calls
\  their UTUI-PAINT + PAINT-XT within their tile region.  Then
\  draws dividers and the taskbar.
VARIABLE _DPC-PAINT-ALL

: DESK-PAINT-CB  ( instance -- )
    _DESK-USE-STATE
    _DESK-SYNC-GEOMETRY
    RGN-ROOT
    \ Layer 0: fill tile area with desk background colour.
    _DESK-BG-DIRTY @ DUP _DPC-PAINT-ALL ! IF
        0 _DESK-BG-DIRTY !
        DRW-STYLE-SAVE
        0 _DTH-DESK-BG @ 0 DRW-STYLE!
        32 0 0 SCR-H 1- SCR-W DRW-FILL-RECT
        DRW-STYLE-RESTORE
    THEN
    _DPC-PAINT-ALL @ _DESK-FULLFRAME @ _DESK-HOST AHOST-PAINT
    RGN-ROOT
    _DESK-FULLFRAME @ 0= IF _DESK-DRAW-DIVIDERS THEN
    _DESK-PAINT-TASKBAR
    _DESK-PAINT-LAUNCHER
    _DESK-AGENT-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF
            SCR-H 1- 0 1 SCR-W 4 PICK PRM-SET-BOUNDS
            WDG-DRAW
        ELSE DROP THEN
    THEN ;

\ --- Close negotiation and shutdown ---
: DESK-REQUEST-CLOSE-CB  ( reason instance -- decision )
    SWAP DROP _DESK-USE-STATE
    APP-CLOSE-R-HOST-SHUTDOWN _DESK-HOST AHOST-REQUEST-CLOSE-ALL ;

VARIABLE _DSD-IOR

: _DSD-REMEMBER  ( ior -- )
    ?DUP IF
        _DSD-IOR @ 0= IF _DSD-IOR ! ELSE DROP THEN
    THEN ;

: _DSD-INTEROP-FINI  ( -- )
    _DESK-INTEROP-FINI ;

: _DSD-PRACTICE-FINI  ( -- )
    _DESK-PRACTICE-ACTIVATION PACT-DEACTIVATE ;

: DESK-SHUTDOWN-CB  ( instance -- )
    _DESK-USE-STATE
    0 _DSD-IOR !
    _DESK-HOST AHOST-DRAIN _DSD-REMEMBER
    ['] _DSD-INTEROP-FINI CATCH DUP _DSD-REMEMBER
    0= IF
        ['] _DSD-PRACTICE-FINI CATCH _DSD-REMEMBER
    THEN
    _DSD-IOR @ ?DUP IF THROW THEN ;

\ =====================================================================
\  §11 — DESK Descriptor & Entry Point
\ =====================================================================

: _DESK-FILL-COMP-DESC  ( -- )
    DESK-COMP-DESC COMP-DESC-INIT
    S" org.akashic.desk"
    DESK-COMP-DESC COMP.ID-U ! DESK-COMP-DESC COMP.ID-A !
    S" 1.0.0"
    DESK-COMP-DESC COMP.VERSION-U ! DESK-COMP-DESC COMP.VERSION-A !
    _DESK-STATE-SIZE DESK-COMP-DESC COMP.STATE-SIZE ! ;

: _DESK-FILL-DESC  ( -- )
    _DESK-FILL-COMP-DESC
    DESK-DESC APP-DESC-INIT
    DESK-COMP-DESC       DESK-DESC APP.COMP-DESC !
    ['] DESK-INIT-CB     DESK-DESC APP.INIT-XT !
    ['] DESK-EVENT-CB    DESK-DESC APP.EVENT-XT !
    ['] DESK-TICK-CB     DESK-DESC APP.TICK-XT !
    ['] DESK-PAINT-CB    DESK-DESC APP.PAINT-XT !
    ['] DESK-SHUTDOWN-CB DESK-DESC APP.SHUTDOWN-XT !
    ['] _DESK-USE-STATE  DESK-DESC APP.ACTIVATE-XT !
    ['] DESK-REQUEST-CLOSE-CB DESK-DESC APP.REQUEST-CLOSE-XT !
    0                    DESK-DESC APP.UIDL-A !
    0                    DESK-DESC APP.UIDL-U !
    0                    DESK-DESC APP.WIDTH !
    0                    DESK-DESC APP.HEIGHT !
    S" DESK"  DESK-DESC APP.TITLE-U !
              DESK-DESC APP.TITLE-A ! ;

\ DESK-QUEUE-LAUNCH ( desc -- )
\   Queue an applet for auto-launch at desk startup.
\   May be called multiple times (up to 8).  Must be called BEFORE DESK-RUN.
: DESK-QUEUE-LAUNCH  ( desc -- )
    DUP _DESK-BUILTIN-DEFAULT-FLAGS _DESK-QUEUE-BUILTIN-RAW
    _DESK-PEND-N @ DUP _DESK-PEND-MAX < IF
        CELLS _DESK-PEND-BUF + !
        1 _DESK-PEND-N +!
    ELSE 2DROP THEN ;

: DESK-QUEUE-BUILTIN  ( desc flags -- )
    _DESK-QUEUE-BUILTIN-RAW ;

VARIABLE _DASSET-SOURCE
VARIABLE _DASSET-ACCESS

: DESK-AGENT-SOURCE!  ( source -- )
    _DASSET-SOURCE !
    _DASSET-SOURCE @ _DESK-PENDING-AGENT-SOURCE @ = IF EXIT THEN
    _DESK-PENDING-AGENT-SOURCE @ ?DUP IF APSOURCE-FREE THEN
    _DASSET-SOURCE @ _DESK-PENDING-AGENT-SOURCE ! ;

: DESK-AGENT-ACCESS-PRESET!  ( preset -- status )
    DUP _DASSET-ACCESS !
    DUP DAP-PRESET? 0= IF DROP AAP-S-INVALID EXIT THEN
    _DESK-CURRENT-STATE @ IF
        _DESK-AGENT-RUNTIME @ ?DUP 0= IF DROP AAP-S-INVALID EXIT THEN
        ARUNTIME-ACCESS-PRESET!
        DUP AAP-S-OK = IF
            _DASSET-ACCESS @ _DESK-PENDING-AGENT-ACCESS !
        THEN
    ELSE
        _DESK-PENDING-AGENT-ACCESS ! AAP-S-OK
    THEN ;

: DESK-RUN  ( -- )
    _DESK-FILL-DESC
    DESK-DESC ASHELL-RUN ;

\ =====================================================================
\  §12 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _desk-guard

' DESK-LAUNCH       CONSTANT _desk-launch-xt
' DESK-TRY-LAUNCH   CONSTANT _desk-trylaunch-xt
' DESK-CLOSE-ID     CONSTANT _desk-closeid-xt
' DESK-REQUEST-CLOSE-ID CONSTANT _desk-request-closeid-xt
' DESK-FOCUS-ID     CONSTANT _desk-focusid-xt
' DESK-MINIMIZE-ID  CONSTANT _desk-minimizeid-xt
' DESK-RESTORE      CONSTANT _desk-restore-xt
' DESK-FULLFRAME!   CONSTANT _desk-fullframe-xt
' DESK-TOGGLE-VH    CONSTANT _desk-togglevh-xt
' DESK-RELAYOUT     CONSTANT _desk-relayout-xt
' DESK-SLOT-COUNT   CONSTANT _desk-slotcount-xt
' DESK-VCOUNT       CONSTANT _desk-vcount-xt
' DESK-AGENT-SOURCE! CONSTANT _desk-agent-source-xt
' DESK-AGENT-ACCESS-PRESET! CONSTANT _desk-agent-access-preset-xt
' DESK-AGENT-ACCESS CONSTANT _desk-agent-access-xt
' DESK-PRACTICE     CONSTANT _desk-practice-xt
' DESK-CONTEXT      CONSTANT _desk-context-xt
' DESK-RECOVERY?    CONSTANT _desk-recovery-xt
' DESK-CATALOG      CONSTANT _desk-catalog-xt
' DESK-QUEUE-BUILTIN CONSTANT _desk-queuebuiltin-xt
' DESK-PACKAGE-RESOLVER! CONSTANT _desk-package-resolver-xt
' DESK-PACKAGE-RELEASER! CONSTANT _desk-package-releaser-xt
' DESK-RUN          CONSTANT _desk-run-xt

\ Launch and close can invoke arbitrary app code.  These are owner-core
\ lifecycle entries, not metadata critical sections; cross-core producers
\ must post requests to Desk's owner.
: DESK-LAUNCH       _desk-launch-xt EXECUTE ;
: DESK-TRY-LAUNCH   _desk-trylaunch-xt EXECUTE ;
: DESK-CLOSE-ID     _desk-closeid-xt EXECUTE ;
: DESK-REQUEST-CLOSE-ID _desk-request-closeid-xt EXECUTE ;
: DESK-FOCUS-ID     _desk-focusid-xt      _desk-guard WITH-GUARD ;
: DESK-MINIMIZE-ID  _desk-minimizeid-xt   _desk-guard WITH-GUARD ;
: DESK-RESTORE      _desk-restore-xt      _desk-guard WITH-GUARD ;
: DESK-FULLFRAME!   _desk-fullframe-xt    _desk-guard WITH-GUARD ;
: DESK-TOGGLE-VH    _desk-togglevh-xt     _desk-guard WITH-GUARD ;
: DESK-RELAYOUT     _desk-relayout-xt     _desk-guard WITH-GUARD ;
: DESK-SLOT-COUNT   _desk-slotcount-xt    _desk-guard WITH-GUARD ;
: DESK-VCOUNT       _desk-vcount-xt       _desk-guard WITH-GUARD ;
: DESK-AGENT-SOURCE! _desk-agent-source-xt _desk-guard WITH-GUARD ;
: DESK-AGENT-ACCESS-PRESET!
    _desk-agent-access-preset-xt _desk-guard WITH-GUARD ;
: DESK-AGENT-ACCESS _desk-agent-access-xt _desk-guard WITH-GUARD ;
: DESK-PRACTICE     _desk-practice-xt     _desk-guard WITH-GUARD ;
: DESK-CONTEXT      _desk-context-xt      _desk-guard WITH-GUARD ;
: DESK-RECOVERY?    _desk-recovery-xt     _desk-guard WITH-GUARD ;
: DESK-CATALOG      _desk-catalog-xt      _desk-guard WITH-GUARD ;
: DESK-QUEUE-BUILTIN _desk-queuebuiltin-xt _desk-guard WITH-GUARD ;
: DESK-PACKAGE-RESOLVER! _desk-package-resolver-xt _desk-guard WITH-GUARD ;
: DESK-PACKAGE-RELEASER! _desk-package-releaser-xt _desk-guard WITH-GUARD ;
\ Like ASHELL-RUN, DESK-RUN is the owner-core yielding lifecycle driver.
\ Task-aware CATCH may span the loop; a lifetime metadata guard may not,
\ because it would exclude bounded control operations while this task yields.
: DESK-RUN          _desk-run-xt EXECUTE ;
[THEN] [THEN]
