\ =================================================================
\  desk.f — TUI Multi-App Desktop (APP-DESC Application)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: DESK- / _DESK-
\  Depends on: akashic-tui-app-shell, akashic-tui-app-desc,
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
\    DESK-FOCUS-ID     ( id -- )       Focus sub-app by ID
\    DESK-MINIMIZE-ID  ( id -- )       Minimize by ID
\    DESK-RESTORE      ( -- )          Restore last minimized
\    DESK-FULLFRAME!   ( flag -- )     Toggle full-frame focused
\    DESK-TOGGLE-VH    ( -- )          Toggle V/H tiling pref
\    DESK-RELAYOUT     ( -- )          Recompute tile grid
\    DESK-SLOT-COUNT   ( -- n )        Number of live slots
\    DESK-VCOUNT       ( -- n )        Number of visible slots
\    DESK-AGENT-SOURCE! ( source -- )   Transfer provider source before run
\    DESK-QUEUE-LAUNCH ( desc -- )     Set startup applet (before DESK-RUN)
\    DESK-RUN          ( -- )          Fill desc, call ASHELL-RUN
\ =================================================================

PROVIDED akashic-tui-desk

REQUIRE ../../app-shell.f
REQUIRE ../../app-desc.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../screen.f
REQUIRE ../../region.f
REQUIRE ../../draw.f
REQUIRE ../../keys.f
REQUIRE ../../color.f
REQUIRE ../../widgets/prompt.f
REQUIRE ../../../utils/toml.f
REQUIRE ../../../liraq/uidl.f
REQUIRE ../../../utils/binimg.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/endpoint.f
REQUIRE ../../../interop/intent.f
REQUIRE ../../../interop/job.f
REQUIRE ../../../agent/runtime.f
REQUIRE ../../../agent/providers/offline.f

\ =====================================================================
\  §1 — Slot Struct (linked list, heap-allocated)
\ =====================================================================
\
\  Same struct as compositor.  Each slot is ALLOCATE'd and linked
\  via _SL-NEXT.  Slot IDs are monotonic (1, 2, 3, …).
\
\  State values:
\    0 = empty (should not appear in live list)
\    1 = running (visible, not focused)
\    2 = minimized (alive but hidden)
\    3 = focused (visible + receives input)

 0 CONSTANT _SLOT-O-DESC       \ APP-DESC pointer
 8 CONSTANT _SLOT-O-INST       \ generic component instance
16 CONSTANT _SLOT-O-RGN        \ region handle (0 if no region)
24 CONSTANT _SLOT-O-STATE      \ state enum
32 CONSTANT _SLOT-O-UCTX       \ UIDL context pointer (0 = no UIDL)
40 CONSTANT _SLOT-O-HAS-UIDL   \ flag: app has UIDL?
48 CONSTANT _SLOT-O-NEXT       \ -> next slot in list (0 = tail)
56 CONSTANT _SLOT-O-ID         \ unique Desk ID (monotonic)
64 CONSTANT _SLOT-O-UIDL-BUF   \ shell-loaded UIDL file buffer (0 = none)
72 CONSTANT _SLOT-O-DIRTY      \ child surface needs repaint
80 CONSTANT _SLOT-O-SEEN-REV   \ last painted component revision
88 CONSTANT _SLOT-SZ

0 CONSTANT _ST-EMPTY
1 CONSTANT _ST-RUNNING
2 CONSTANT _ST-MINIMIZED
3 CONSTANT _ST-FOCUSED

CREATE DESK-COMP-DESC COMP-DESC ALLOT
CREATE DESK-DESC      APP-DESC ALLOT

\ Slot field access helpers  ( slot-addr -- field-addr )
: _SL-DESC     ( sa -- a )  _SLOT-O-DESC     + ;
: _SL-INST     ( sa -- a )  _SLOT-O-INST     + ;
: _SL-RGN      ( sa -- a )  _SLOT-O-RGN      + ;
: _SL-STATE    ( sa -- a )  _SLOT-O-STATE    + ;
: _SL-UCTX     ( sa -- a )  _SLOT-O-UCTX     + ;
: _SL-HAS-UIDL ( sa -- a )  _SLOT-O-HAS-UIDL + ;
: _SL-NEXT     ( sa -- a )  _SLOT-O-NEXT     + ;
: _SL-ID       ( sa -- a )  _SLOT-O-ID       + ;
: _SL-UIDL-BUF ( sa -- a )  _SLOT-O-UIDL-BUF + ;
: _SL-DIRTY    ( sa -- a )  _SLOT-O-DIRTY    + ;
: _SL-SEEN-REV ( sa -- a )  _SLOT-O-SEEN-REV + ;

: _SL-VISIBLE?  ( sa -- flag )
    _SL-STATE @ DUP _ST-RUNNING = SWAP _ST-FOCUSED = OR ;

: _SL-ALIVE?  ( sa -- flag )
    _SL-STATE @ _ST-EMPTY <> ;

\ =====================================================================
\  §2 — DESK Global State
\ =====================================================================
\
\  Simplified from compositor: no _COMP-RUNNING, _COMP-DIRTY,
\  _COMP-TICK-MS, _COMP-LAST-TICK — the shell owns all of those.

VARIABLE _DESK-CURRENT-STATE
0 _DESK-CURRENT-STATE !
CMP-LAYOUT-BEGIN

_DESK-CURRENT-STATE CMP-CELL: _DESK-HEAD       \ first live slot
_DESK-CURRENT-STATE CMP-CELL: _DESK-FOCUS-SA   \ focused slot
_DESK-CURRENT-STATE CMP-CELL: _DESK-NEXT-ID    \ monotonic slot ID
_DESK-CURRENT-STATE CMP-CELL: _DESK-VH         \ tiling preference
_DESK-CURRENT-STATE CMP-CELL: _DESK-FULLFRAME
_DESK-CURRENT-STATE CMP-CELL: _DESK-LAST-MIN-SA

\ Active UIDL context tracking lives in the shell.
\ Desk delegates via ASHELL-CTX-SWITCH.

\ Pre-instance constructor inputs.  These are consumed by DESK-INIT-CB;
\ live Desk state is instance-relative below.
VARIABLE _DESK-CFG-A   VARIABLE _DESK-CFG-L
0 _DESK-CFG-A !  0 _DESK-CFG-L !
VARIABLE _DESK-PENDING-AGENT-SOURCE
0 _DESK-PENDING-AGENT-SOURCE !

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

_DESK-CURRENT-STATE _HB-SZ _HB-MAX * CMP-FIELD: _HB-ENTRIES
_DESK-CURRENT-STATE CMP-CELL: _DHBAR-COUNT

\ Generic runtime and interoperability ownership.
_DESK-CURRENT-STATE CMP-CELL: _DESK-REGISTRY
_DESK-CURRENT-STATE CMP-CELL: _DESK-POLICY
_DESK-CURRENT-STATE CMP-CELL: _DESK-BUS
_DESK-CURRENT-STATE CMP-CELL: _DESK-INTENTS
_DESK-CURRENT-STATE CMP-CELL: _DESK-JOBS
_DESK-CURRENT-STATE IENDPOINT-SIZE CMP-FIELD: _DESK-ENDPOINT
_DESK-CURRENT-STATE CMP-CELL: _DESK-INSTALLED-N
_DESK-CURRENT-STATE _DESK-MAX-INSTALLED CELLS CMP-FIELD: _DESK-INSTALLED
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-SOURCE
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-PROVIDER
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-RUNTIME
_DESK-CURRENT-STATE CMP-CELL: _DESK-TOOL-GATEWAY
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-PROMPT
_DESK-CURRENT-STATE CMP-CELL: _DESK-AGENT-PROMPT-RGN
_DESK-CURRENT-STATE _DESK-AGENT-PROMPT-CAP CMP-FIELD: _DESK-AGENT-PROMPT-BUF

CMP-LAYOUT-SIZE CONSTANT _DESK-STATE-SIZE

: _DESK-USE-STATE  ( instance -- )
    CINST-STATE _DESK-CURRENT-STATE ! ;

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
    0  _DESK-HEAD @
    BEGIN ?DUP WHILE  SWAP 1+ SWAP  _SL-NEXT @  REPEAT ;

\ Count visible (non-minimized) slots.
: DESK-VCOUNT  ( -- n )
    0  _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF SWAP 1+ SWAP THEN
        _SL-NEXT @
    REPEAT ;

\ Find slot by ID.  Returns slot address or 0.
: _DESK-FIND-ID  ( id -- sa | 0 )
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-ID @ 2 PICK = IF NIP EXIT THEN
        _SL-NEXT @
    REPEAT
    DROP 0 ;

\ Unlink a slot from the list.  Does NOT free.
VARIABLE _DUL-PREV   VARIABLE _DUL-SA
: _DESK-UNLINK  ( sa -- )
    _DUL-SA !
    _DESK-HEAD @ _DUL-SA @ = IF
        _DUL-SA @ _SL-NEXT @  _DESK-HEAD !
        EXIT
    THEN
    _DESK-HEAD @ _DUL-PREV !
    BEGIN _DUL-PREV @ WHILE
        _DUL-PREV @ _SL-NEXT @  _DUL-SA @ = IF
            _DUL-SA @ _SL-NEXT @
            _DUL-PREV @ _SL-NEXT !
            EXIT
        THEN
        _DUL-PREV @ _SL-NEXT @  _DUL-PREV !
    REPEAT ;

\ Append a slot at the tail of the list.
: _DESK-APPEND  ( sa -- )
    0 OVER _SL-NEXT !
    _DESK-HEAD @ 0= IF
        _DESK-HEAD !
        EXIT
    THEN
    _DESK-HEAD @
    BEGIN DUP _SL-NEXT @ WHILE _SL-NEXT @ REPEAT
    _SL-NEXT ! ;

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
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        -1 OVER _SL-DIRTY !
        _SL-NEXT @
    REPEAT ;

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
    _SL-UCTX @ ASHELL-CTX-SAVE ;

: _DESK-ACTIVATE-CHILD  ( sa -- )
    DUP _SL-DESC @ APP.ACTIVATE-XT @ ?DUP IF
        SWAP _SL-INST @ SWAP EXECUTE
    ELSE DROP THEN ;

: _DESK-CTX-SWITCH  ( sa -- )
    DUP _SL-UCTX @ ASHELL-CTX-SWITCH
    _DESK-ACTIVATE-CHILD ;

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

VARIABLE _DL-DESC
VARIABLE _DL-INST
VARIABLE _DL-SLOT

: DESK-LAUNCH  ( desc -- id )
    DUP APP-DESC-VALID? 0= IF DROP -1 EXIT THEN
    DUP DESK-INSTALL IF DROP -1 EXIT THEN
    _DL-DESC !
    _DL-DESC @ APP.COMP-DESC @ CINST-NEW
    DUP IF 2DROP -1 EXIT THEN
    DROP _DL-INST !
    _DESK-ENDPOINT _DL-INST @ CINST.ENDPOINT !
    _DL-INST @ _DESK-REGISTRY @ CREG-INST+ IF
        _DL-INST @ CINST-FREE -1 EXIT
    THEN
    _SLOT-SZ ALLOCATE
    DUP IF
        SWAP DROP DROP
        _DL-INST @ _DESK-REGISTRY @ CREG-INST- DROP
        _DL-INST @ CINST-FREE -1 EXIT
    THEN
    DROP DUP _DL-SLOT ! _SLOT-SZ 0 FILL
    _DL-DESC @ _DL-SLOT @ _SL-DESC !
    _DL-INST @ _DL-SLOT @ _SL-INST !
    _ST-RUNNING _DL-SLOT @ _SL-STATE !
    _DESK-NEXT-ID @ _DL-SLOT @ _SL-ID !
    1 _DESK-NEXT-ID +!
    \ Allocate UIDL context if app declares UIDL (inline or file)
    _DL-DESC @ APP.UIDL-A @ _DL-DESC @ APP.UIDL-FILE-A @ OR IF
        UCTX-ALLOC DUP IF DUP UCTX-CLEAR THEN
        _DL-SLOT @ _SL-UCTX !
        -1 _DL-SLOT @ _SL-HAS-UIDL !
    ELSE
        0 _DL-SLOT @ _SL-UCTX !
        0 _DL-SLOT @ _SL-HAS-UIDL !
    THEN
    _DL-SLOT @ _DESK-APPEND
    \ Auto-focus if this is the first slot
    _DESK-FOCUS-SA @ 0= IF
        _ST-FOCUSED _DL-SLOT @ _SL-STATE !
        _DL-SLOT @ _DESK-FOCUS-SA !
    THEN
    DESK-RELAYOUT
    \ Load UIDL document into sub-app context
    _DL-SLOT @ _SL-HAS-UIDL @ IF
        _DL-SLOT @ _DESK-CTX-SWITCH
        _DL-DESC @ APP.UIDL-A @ IF
            \ --- inline UIDL ---
            _DL-DESC @ APP.UIDL-A @
            _DL-DESC @ APP.UIDL-U @
            _DL-SLOT @ _SL-RGN @
            UTUI-LOAD DROP
        ELSE _DL-DESC @ APP.UIDL-FILE-A @ IF
            \ --- file-based UIDL (loaded via shared loader) ---
            _DL-DESC @ APP.UIDL-FILE-A @
            _DL-DESC @ APP.UIDL-FILE-U @
            _DL-SLOT @ _SL-RGN @
            ASHELL-LOAD-UIDL
            _DL-SLOT @ _SL-UIDL-BUF !
        THEN THEN
    THEN
    \ Call sub-app init callback while context is live so that
    \ UTUI-BY-ID, UTUI-WIDGET-SET, UTUI-DO! etc. persist.
    _DL-DESC @ APP.INIT-XT @ ?DUP IF
        _DL-INST @ SWAP EXECUTE
    THEN
    \ Save context AFTER init — widget mounts & actions are now captured
    _DL-SLOT @ _SL-HAS-UIDL @ IF _DL-SLOT @ _DESK-CTX-SAVE THEN
    _DL-SLOT @ _SL-ID @ ;

: DESK-CLOSE-ID  ( id -- )
    _DESK-FIND-ID DUP 0= IF DROP EXIT THEN
    >R
    \ Sub-app shutdown callback
    R@ _SL-DESC @ ?DUP IF
        APP.SHUTDOWN-XT @ ?DUP IF
            R@ _SL-INST @ SWAP EXECUTE
        THEN
    THEN
    \ Detach UIDL if active
    R@ _SL-HAS-UIDL @ IF
        R@ _DESK-CTX-SWITCH
        UTUI-DETACH
        0 ASHELL-CTX-SWITCH
    THEN
    \ Free resources
    R@ _SL-UIDL-BUF @ ?DUP IF _ASHELL-UIDL-FILE-MAX XMEM-FREE-BLOCK THEN
    R@ _SL-UCTX @ ?DUP IF UCTX-FREE THEN
    R@ _SL-RGN @ ?DUP IF RGN-FREE THEN
    R@ _SL-INST @ ?DUP IF
        DUP _DESK-REGISTRY @ CREG-INST- DROP
        CINST-FREE
    THEN
    \ Fixup focus / last-minimized pointers
    R@ _DESK-FOCUS-SA @ = IF
        0 _DESK-FOCUS-SA !
    THEN
    R@ _DESK-LAST-MIN-SA @ = IF
        0 _DESK-LAST-MIN-SA !
    THEN
    R@ _SL-ID @ _DESK-HOTBAR-SLOT-CLOSED
    R@ _DESK-UNLINK
    R> FREE
    \ Auto-focus next visible slot if focus was lost
    _DESK-FOCUS-SA @ 0= IF
        _DESK-HEAD @
        BEGIN ?DUP WHILE
            DUP _SL-VISIBLE? IF
                DUP _DESK-FOCUS-SA !
                _ST-FOCUSED SWAP _SL-STATE !
                0
            ELSE
                _SL-NEXT @
            THEN
        REPEAT
    THEN
    DESK-RELAYOUT ;

\ =====================================================================
\  §8 — Focus, Minimize, Restore
\ =====================================================================

: DESK-FOCUS-ID  ( id -- )
    _DESK-FIND-ID DUP 0= IF DROP EXIT THEN
    DUP _SL-STATE @ _ST-MINIMIZED = IF DROP EXIT THEN
    _DESK-FOCUS-SA @ ?DUP IF
        DUP _SL-STATE @ _ST-FOCUSED = IF
            _ST-RUNNING SWAP _SL-STATE !
        ELSE DROP THEN
    THEN
    _ST-FOCUSED OVER _SL-STATE !
    _DESK-FOCUS-SA !
    ASHELL-DIRTY! ;

: DESK-MINIMIZE-ID  ( id -- )
    _DESK-FIND-ID DUP 0= IF DROP EXIT THEN
    DUP _SL-STATE @ _ST-MINIMIZED = IF DROP EXIT THEN
    _ST-MINIMIZED OVER _SL-STATE !
    DUP _DESK-LAST-MIN-SA !
    DUP _DESK-FOCUS-SA @ = IF
        0 _DESK-FOCUS-SA !
        _DESK-HEAD @
        BEGIN ?DUP WHILE
            DUP _SL-VISIBLE? IF
                DUP _DESK-FOCUS-SA !
                _ST-FOCUSED SWAP _SL-STATE !
                0
            ELSE
                _SL-NEXT @
            THEN
        REPEAT
    THEN
    DROP
    DESK-RELAYOUT ;

: DESK-RESTORE  ( -- )
    _DESK-LAST-MIN-SA @ DUP 0= IF DROP EXIT THEN
    DUP _SL-STATE @ _ST-MINIMIZED <> IF DROP EXIT THEN
    _ST-RUNNING OVER _SL-STATE !
    0 _DESK-LAST-MIN-SA !
    _DESK-FOCUS-SA @ 0= IF
        _ST-FOCUSED OVER _SL-STATE !
        DUP _DESK-FOCUS-SA !
    THEN
    DROP
    DESK-RELAYOUT ;

: DESK-FULLFRAME!  ( flag -- )
    _DESK-FULLFRAME !
    DESK-RELAYOUT ;

: DESK-TOGGLE-VH  ( -- )
    _DESK-VH @ 0= _DESK-VH !
    DESK-RELAYOUT ;

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

VARIABLE _DSE-ID-A
VARIABLE _DSE-ID-U

: _DESK-ENDPOINT-SERVICE  ( id-a id-u desk-instance -- service | 0 )
    _DESK-USE-STATE _DSE-ID-U ! _DSE-ID-A !
    _DSE-ID-A @ _DSE-ID-U @ S" org.akashic.agent.runtime" STR-STR= IF
        _DESK-AGENT-RUNTIME @ EXIT
    THEN
    _DSE-ID-A @ _DSE-ID-U @ S" org.akashic.agent.tool-gateway" STR-STR= IF
        _DESK-TOOL-GATEWAY @ EXIT
    THEN
    _DSE-ID-A @ _DSE-ID-U @ S" org.akashic.agent.provider-source" STR-STR= IF
        _DESK-AGENT-SOURCE @ EXIT
    THEN
    _DSE-ID-A @ _DSE-ID-U @ S" org.akashic.runtime.registry" STR-STR= IF
        _DESK-REGISTRY @ EXIT
    THEN
    _DSE-ID-A @ _DSE-ID-U @ S" org.akashic.interop.endpoint" STR-STR= IF
        _DESK-ENDPOINT EXIT
    THEN
    0 ;

VARIABLE _DIR-ID-A
VARIABLE _DIR-ID-U
VARIABLE _DIR-REQ
VARIABLE _DIR-ENTRY
VARIABLE _DIR-COMP
VARIABLE _DIR-INST

: _DESK-ENDPOINT-INTENT  ( id-a id-u request desk-instance -- status )
    _DESK-USE-STATE
    _DIR-REQ ! _DIR-ID-U ! _DIR-ID-A !
    _DIR-ID-A @ _DIR-ID-U @ _DESK-INTENTS @ CINT-RESOLVE
    DUP 0= IF DROP CBUS-S-NO-HANDLER EXIT THEN
    _DIR-ENTRY !
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

: _DESK-SHOW-AGENT-PROMPT  ( -- )
    _DESK-AGENT-PROMPT @ 0= IF EXIT THEN
    S" Ask:" 0 0 _DESK-AGENT-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _DESK-INTEROP-INIT  ( desk-instance -- )
    DUP _DINI-INST ! _DESK-USE-STATE
    0 _DESK-INSTALLED-N !
    CREG-NEW 0<> ABORT" desk: registry allocation failed" _DESK-REGISTRY !
    CPOLICY-SIZE ALLOCATE
    0<> ABORT" desk: policy allocation failed"
    DUP _DESK-POLICY ! CPOLICY-INIT
    CINT-NEW 0<> ABORT" desk: intent router allocation failed" _DESK-INTENTS !
    CJOB-TABLE-NEW 0<> ABORT" desk: job table allocation failed" _DESK-JOBS !
    _DESK-REGISTRY @ _DESK-POLICY @ CBUS-NEW
    0<> ABORT" desk: request bus allocation failed" _DESK-BUS !
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
    _DESK-REGISTRY @ _DESK-BUS @ _DINI-INST @ ATOOLG-NEW
    0<> ABORT" desk: agent tool gateway allocation failed"
    DUP _DESK-TOOL-GATEWAY !
    _DESK-AGENT-RUNTIME @ ARUNTIME-TOOL-GATEWAY!
    _DESK-TOOL-GATEWAY @ _DESK-AGENT-PROVIDER @ APROV-BIND-TOOLS
    ABORT" desk: provider tool binding failed"

    _DESK-ENDPOINT IENDPOINT-INIT
    _DINI-INST @ _DESK-ENDPOINT IEND.CONTEXT !
    ['] _DESK-ENDPOINT-POST _DESK-ENDPOINT IEND.POST-XT !
    ['] _DESK-ENDPOINT-INTENT _DESK-ENDPOINT IEND.INTENT-XT !
    ['] _DESK-ENDPOINT-SERVICE _DESK-ENDPOINT IEND.SERVICE-XT !
    _DESK-ENDPOINT _DINI-INST @ CINST.ENDPOINT !

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

: _DESK-INTEROP-FINI  ( -- )
    _DESK-AGENT-PROMPT @ ?DUP IF PRM-FREE THEN
    _DESK-AGENT-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _DESK-BUS @ ?DUP IF
        DUP CBUS-CANCEL-ALL DROP
    THEN
    _DESK-TOOL-GATEWAY @ ?DUP IF ATOOLG-FREE THEN
    _DESK-BUS @ ?DUP IF CBUS-FREE THEN
    _DESK-AGENT-RUNTIME @ ?DUP IF ARUNTIME-FREE THEN
    _DESK-AGENT-PROVIDER @ ?DUP IF APROV-FREE THEN
    _DESK-AGENT-SOURCE @ ?DUP IF APSOURCE-FREE THEN
    _DESK-JOBS @ ?DUP IF CJOB-TABLE-FREE THEN
    _DESK-INTENTS @ ?DUP IF CINT-FREE THEN
    _DESK-POLICY @ ?DUP IF FREE THEN
    _DESK-REGISTRY @ ?DUP IF CREG-FREE THEN
    0 _DESK-BUS ! 0 _DESK-JOBS ! 0 _DESK-INTENTS !
    0 _DESK-POLICY ! 0 _DESK-REGISTRY !
    0 _DESK-AGENT-SOURCE !
    0 _DESK-AGENT-RUNTIME ! 0 _DESK-AGENT-PROVIDER !
    0 _DESK-TOOL-GATEWAY !
    0 _DESK-AGENT-PROMPT ! 0 _DESK-AGENT-PROMPT-RGN !
    _DESK-ENDPOINT IENDPOINT-SIZE 0 FILL ;

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

VARIABLE _DTB-COL
VARIABLE _DTB-ROW
VARIABLE _DAS-A
VARIABLE _DAS-U
VARIABLE _DAS-COL

: _DESK-AGENT-STATE-TEXT  ( -- addr len )
    _DESK-AGENT-RUNTIME @ ARUNTIME.STATUS @ CASE
        ARUN-S-RUNNING OF S" [Agent: working]" ENDOF
        ARUN-S-APPROVAL OF S" [Agent: review]" ENDOF
        ARUN-S-OFFLINE OF S" [Agent: offline]" ENDOF
        ARUN-S-ERROR OF S" [Agent: error]" ENDOF
        ARUN-S-CANCELLED OF S" [Agent: cancelled]" ENDOF
        DROP S" [Agent: ready]"
    ENDCASE ;

: _DESK-PAINT-AGENT-STATE  ( -- )
    _DESK-AGENT-STATE-TEXT _DAS-U ! _DAS-A !
    SCR-W _DAS-U @ - 1- 0 MAX _DAS-COL !
    _DAS-COL @ _DTB-COL @ <= IF EXIT THEN
    _DESK-AGENT-RUNTIME @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = IF
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
        DUP _SL-STATE @ _ST-MINIMIZED = IF 126 _DTB-CH THEN
        93 _DTB-CH
        _DESK-TB-BUF _DESK-TB-POS @
        _DTB-ROW @ _DTB-COL @ DRW-TEXT
        _DESK-TB-POS @ _DTB-COL +!
        \ space separator
        32 _DTB-ROW @ _DTB-COL @ DRW-CHAR
        1 _DTB-COL +!
        _SL-NEXT @
    REPEAT
    \ ---- hotbar entries ----
    _DHBAR-COUNT @ IF
        _DTH-DIV-FG @ _DTH-DIV-BG @ 0 DRW-STYLE!
        124 _DTB-ROW @ _DTB-COL @ DRW-CHAR    \ '|'
        1 _DTB-COL +!
        32 _DTB-ROW @ _DTB-COL @ DRW-CHAR
        1 _DTB-COL +!
        _DTB-ROW @ _DTB-COL @ _DESK-PAINT-HOTBAR
    THEN
    _DESK-PAINT-AGENT-STATE
    DRW-STYLE-RESTORE ;

\ =====================================================================
\  §10 — APP-DESC Callbacks
\ =====================================================================
\
\  The DESK is a normal APP-DESC app.  The shell calls these
\  callbacks — no private event loop, no APP-INIT/APP-SHUTDOWN.

\ --- Init ---
: DESK-INIT-CB  ( instance -- )
    DUP _DINI-INST ! _DESK-USE-STATE
    0 _DESK-HEAD !
    0 _DESK-FOCUS-SA !
    1 _DESK-NEXT-ID !
    0 _DESK-VH !
    0 _DESK-FULLFRAME !
    0 _DESK-LAST-MIN-SA !
    -1 _DESK-BG-DIRTY !
    SCR-W _DESK-LAST-W !
    SCR-H _DESK-LAST-H !
    0 ASHELL-CTX-SWITCH
    _DESK-THEME-DEFAULTS
    _DESK-HOTBAR-CLEAR
    \ Load config if a buffer was supplied before DESK-RUN
    _DESK-CFG-A @ ?DUP IF _DESK-CFG-L @ DESK-LOAD-CONFIG THEN
    _DINI-INST @ _DESK-INTEROP-INIT
    \ Launch queued startup applets
    _DESK-PEND-N @ 0 DO
        I CELLS _DESK-PEND-BUF + @ DESK-LAUNCH DROP
    LOOP
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

\ Scratch buffer for building EVALUATE strings
CREATE _DESK-EVAL-BUF 80 ALLOT

\ Launch the first unlaunched hotbar entry.
\ file field = .m64 binary path, desc field = entry word name.
: _DESK-HOTBAR-LAUNCH-NEXT  ( -- )
    _DESK-HOTBAR-NEXT DUP 0< IF DROP EXIT THEN
    DUP _HB-ENTRY                 ( idx entry )
    DUP _HB-FILE-U + @ 0= IF 2DROP EXIT THEN
    \ Build "IMG-LOAD-EXEC <filename>" and EVALUATE it
    \ "IMG-LOAD-EXEC " = 14 chars (13 letters + 1 trailing space)
    S" IMG-LOAD-EXEC " _DESK-EVAL-BUF SWAP CMOVE
    DUP _HB-FILE-A + @            ( idx entry file-a )
    OVER _HB-FILE-U + @           ( idx entry file-a file-u )
    _DESK-EVAL-BUF 14 + SWAP DUP >R CMOVE
    _DESK-EVAL-BUF  14 R> +       ( idx entry buf total-len )
    EVALUATE                       ( idx entry xt ior )
    ?DUP IF DROP 2DROP EXIT THEN   ( idx entry xt )
    DROP                           ( idx entry )
    \ Now entry word is in dictionary — EVALUATE the desc name
    DUP _HB-DESC-U + @ 0= IF 2DROP EXIT THEN
    DUP _HB-DESC-A + @ SWAP _HB-DESC-U + @
    EVALUATE                      ( idx desc-addr )
    DESK-LAUNCH                   ( idx slot-id )
    _DESK-HOTBAR-MARK ;

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
        DROP _DESK-HOTBAR-LAUNCH-NEXT -1 EXIT THEN
    DUP 97 _DESK-ALT? IF
        DROP _DESK-SHOW-AGENT-PROMPT -1 EXIT THEN
    DROP 0 ;

\ _DESK-TILE-AT ( row col -- slot | 0 )
\   Find the visible slot whose region contains (row, col).
\   Walks the slot list; returns the first match or 0.
VARIABLE _DTA-ROW  VARIABLE _DTA-COL
VARIABLE _DTA-RR   VARIABLE _DTA-RC
VARIABLE _DTA-RH   VARIABLE _DTA-RW

: _DESK-TILE-AT  ( row col -- slot | 0 )
    _DTA-COL !  _DTA-ROW !
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            DUP _SL-RGN @ ?DUP IF        ( slot rgn )
                DUP RGN-ROW _DTA-RR !
                DUP RGN-COL _DTA-RC !
                DUP RGN-H   _DTA-RH !
                    RGN-W   _DTA-RW !     ( slot )
                _DTA-RR @ _DTA-ROW @ <=
                _DTA-RC @ _DTA-COL @ <= AND
                _DTA-RR @ _DTA-RH @ + _DTA-ROW @ > AND
                _DTA-RC @ _DTA-RW @ + _DTA-COL @ > AND
                IF EXIT THEN              ( slot — match )
            THEN
        THEN
        _SL-NEXT @
    REPEAT
    0 ;

\ _DESK-DISPATCH-MOUSE ( ev -- flag )
\   Handle a synthetic mouse event from the shell cursor.
\   Hit-test tiles, context-switch, and forward to UTUI-DISPATCH-MOUSE.
VARIABLE _DDM-EV

: _DESK-DISPATCH-MOUSE  ( ev -- flag )
    DUP _DDM-EV !
    DUP ASHELL-MOUSE-ROW OVER ASHELL-MOUSE-COL   ( ev row col )
    2DUP _DESK-TILE-AT                             ( ev row col slot|0 )
    DUP 0= IF DROP 2DROP DROP 0 EXIT THEN
    >R 2DROP DROP                                  ( R: slot )
    R@ _SL-HAS-UIDL @ IF
        R@ _DESK-CTX-SWITCH
        _DDM-EV @ ASHELL-MOUSE-ROW
        _DDM-EV @ ASHELL-MOUSE-COL
        _DDM-EV @ ASHELL-MOUSE-BTN        ( row col btn )
        UTUI-DISPATCH-MOUSE               ( handled? )
        IF
            -1 R@ _SL-DIRTY !
            R> DROP
            -1 EXIT
        THEN
    THEN
    R> DROP
    0 ;

\ --- Event ---
\
\  Routes events to the focused sub-app.  If the sub-app calls
\  ASHELL-QUIT, we intercept it via ASHELL-QUIT-PENDING? /
\  ASHELL-CANCEL-QUIT, and close that tile instead of shutting
\  down the whole shell.
: DESK-EVENT-CB  ( ev instance -- flag )
    _DESK-USE-STATE
    _DESK-AGENT-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    \ 0. Mouse events → tile hit-test routing
    DUP ASHELL-MOUSE? IF
        _DESK-DISPATCH-MOUSE EXIT
    THEN
    \ 1. Desktop-global shortcuts take precedence over child input.
    DUP _DESK-SHORTCUT? IF DROP -1 EXIT THEN
    \ 2. Route to focused sub-app
    _DESK-FOCUS-SA @ ?DUP IF
        >R
        R@ _SL-HAS-UIDL @ IF
            R@ _DESK-CTX-SWITCH
        THEN
        \ Match ASHELL routing: the app callback owns modal input such
        \ as command bars before the focused UIDL widget sees the key.
        R@ _SL-DESC @ ?DUP IF
            APP.EVENT-XT @ ?DUP IF
                OVER R@ _SL-INST @ ROT EXECUTE  ( ev consumed? )
                \ Intercept sub-app ASHELL-QUIT
                ASHELL-QUIT-PENDING? IF
                    ASHELL-CANCEL-QUIT
                    R@ _SL-ID @ DESK-CLOSE-ID
                    R> DROP
                    2DROP -1 EXIT
                THEN
                IF
                    -1 R@ _SL-DIRTY !
                    R> DROP
                    ASHELL-DIRTY! DROP -1 EXIT
                THEN
            THEN
        THEN
        R@ _SL-HAS-UIDL @ IF
            DUP UTUI-DISPATCH-KEY IF
                -1 R@ _SL-DIRTY !
                R> DROP
                ASHELL-DIRTY! DROP -1 EXIT
            THEN
        THEN
        R> DROP
    THEN
    DROP 0 ;

\ --- Tick ---
: DESK-TICK-CB  ( instance -- )
    _DESK-USE-STATE
    _DESK-FOCUS-SA @ ?DUP IF _SL-INST @ ELSE 0 THEN
    _DESK-TOOL-GATEWAY @ ATOOLG-FOCUSED! DROP
    8 _DESK-AGENT-RUNTIME @ ARUNTIME-PUMP ?DUP IF
        DROP _DESK-MARK-ALL-CHILDREN ASHELL-DIRTY!
    THEN
    8 _DESK-BUS @ CBUS-PUMP DROP
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-ALIVE? IF
            DUP >R
            R@ _SL-INST @ CINST.REVISION @
            R@ _SL-SEEN-REV @ <> IF -1 R@ _SL-DIRTY ! THEN
            R@ _SL-DIRTY @
            R@ _SL-DESC @ APP.FLAGS @ APP-F-TICK-WHEN-CLEAN AND OR IF
                R@ _SL-HAS-UIDL @ IF R@ _DESK-CTX-SWITCH THEN
                R@ _DESK-ACTIVATE-CHILD
                R@ _SL-DESC @ ?DUP IF
                    APP.TICK-XT @ ?DUP IF R@ _SL-INST @ SWAP EXECUTE THEN
                THEN
            THEN
            R> DROP
        THEN
        _SL-NEXT @
    REPEAT ;

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
    \ Layer 0: fill tile area with desk background colour
    \ Only runs when geometry changed (relayout / init / resize)
    _DESK-BG-DIRTY @ DUP _DPC-PAINT-ALL ! IF
        0 _DESK-BG-DIRTY !
        DRW-STYLE-SAVE
        0 _DTH-DESK-BG @ 0 DRW-STYLE!
        32 0 0 SCR-H 1- SCR-W DRW-FILL-RECT
        DRW-STYLE-RESTORE
    THEN
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _DESK-FULLFRAME @ IF
                DUP _DESK-FOCUS-SA @ <>
            ELSE
                0
            THEN
            0= IF
                DUP _SL-DIRTY @ _DPC-PAINT-ALL @ OR IF
                    DUP _SL-RGN @ IF
                        DUP _SL-UCTX @
                        OVER _SL-RGN @
                        2 PICK _SL-HAS-UIDL @
                        3 PICK _SL-DESC @
                        4 PICK _SL-INST @
                        ASHELL-PAINT-CHILD
                        DUP _SL-INST @ CINST.REVISION @
                        OVER _SL-SEEN-REV !
                        0 OVER _SL-DIRTY !
                    THEN
                THEN
            THEN
        THEN
        _SL-NEXT @
    REPEAT
    RGN-ROOT
    _DESK-FULLFRAME @ 0= IF _DESK-DRAW-DIVIDERS THEN
    _DESK-PAINT-TASKBAR
    _DESK-AGENT-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF
            SCR-H 1- 0 1 SCR-W 4 PICK PRM-SET-BOUNDS
            WDG-DRAW
        ELSE DROP THEN
    THEN ;

\ --- Shutdown ---
: DESK-SHUTDOWN-CB  ( instance -- )
    _DESK-USE-STATE
    BEGIN _DESK-HEAD @ ?DUP WHILE
        _SL-ID @ DESK-CLOSE-ID
    REPEAT
    _DESK-INTEROP-FINI ;

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
    _DESK-PEND-N @ DUP _DESK-PEND-MAX < IF
        CELLS _DESK-PEND-BUF + !
        1 _DESK-PEND-N +!
    ELSE 2DROP THEN ;

VARIABLE _DASSET-SOURCE

: DESK-AGENT-SOURCE!  ( source -- )
    _DASSET-SOURCE !
    _DASSET-SOURCE @ _DESK-PENDING-AGENT-SOURCE @ = IF EXIT THEN
    _DESK-PENDING-AGENT-SOURCE @ ?DUP IF APSOURCE-FREE THEN
    _DASSET-SOURCE @ _DESK-PENDING-AGENT-SOURCE ! ;

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
' DESK-CLOSE-ID     CONSTANT _desk-closeid-xt
' DESK-FOCUS-ID     CONSTANT _desk-focusid-xt
' DESK-MINIMIZE-ID  CONSTANT _desk-minimizeid-xt
' DESK-RESTORE      CONSTANT _desk-restore-xt
' DESK-FULLFRAME!   CONSTANT _desk-fullframe-xt
' DESK-TOGGLE-VH    CONSTANT _desk-togglevh-xt
' DESK-RELAYOUT     CONSTANT _desk-relayout-xt
' DESK-SLOT-COUNT   CONSTANT _desk-slotcount-xt
' DESK-VCOUNT       CONSTANT _desk-vcount-xt
' DESK-AGENT-SOURCE! CONSTANT _desk-agent-source-xt
' DESK-RUN          CONSTANT _desk-run-xt

: DESK-LAUNCH       _desk-launch-xt       _desk-guard WITH-GUARD ;
: DESK-CLOSE-ID     _desk-closeid-xt      _desk-guard WITH-GUARD ;
: DESK-FOCUS-ID     _desk-focusid-xt      _desk-guard WITH-GUARD ;
: DESK-MINIMIZE-ID  _desk-minimizeid-xt   _desk-guard WITH-GUARD ;
: DESK-RESTORE      _desk-restore-xt      _desk-guard WITH-GUARD ;
: DESK-FULLFRAME!   _desk-fullframe-xt    _desk-guard WITH-GUARD ;
: DESK-TOGGLE-VH    _desk-togglevh-xt     _desk-guard WITH-GUARD ;
: DESK-RELAYOUT     _desk-relayout-xt     _desk-guard WITH-GUARD ;
: DESK-SLOT-COUNT   _desk-slotcount-xt    _desk-guard WITH-GUARD ;
: DESK-VCOUNT       _desk-vcount-xt       _desk-guard WITH-GUARD ;
: DESK-AGENT-SOURCE! _desk-agent-source-xt _desk-guard WITH-GUARD ;
: DESK-RUN          _desk-run-xt          _desk-guard WITH-GUARD ;
[THEN] [THEN]
