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
REQUIRE ../../../utils/toml.f
REQUIRE ../../../liraq/uidl.f
REQUIRE ../../../utils/binimg.f

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
 8 CONSTANT _SLOT-O-RGN        \ region handle (0 if no region)
16 CONSTANT _SLOT-O-STATE      \ state enum
24 CONSTANT _SLOT-O-UCTX       \ UIDL context pointer (0 = no UIDL)
32 CONSTANT _SLOT-O-HAS-UIDL   \ flag: app has UIDL?
40 CONSTANT _SLOT-O-NEXT       \ → next slot in list (0 = tail)
48 CONSTANT _SLOT-O-ID         \ unique ID (monotonic)
56 CONSTANT _SLOT-O-UIDL-BUF   \ shell-loaded UIDL file buffer (0 = none)
64 CONSTANT _SLOT-SZ

0 CONSTANT _ST-EMPTY
1 CONSTANT _ST-RUNNING
2 CONSTANT _ST-MINIMIZED
3 CONSTANT _ST-FOCUSED

\ Slot field access helpers  ( slot-addr -- field-addr )
: _SL-DESC     ( sa -- a )  _SLOT-O-DESC     + ;
: _SL-RGN      ( sa -- a )  _SLOT-O-RGN      + ;
: _SL-STATE    ( sa -- a )  _SLOT-O-STATE    + ;
: _SL-UCTX     ( sa -- a )  _SLOT-O-UCTX     + ;
: _SL-HAS-UIDL ( sa -- a )  _SLOT-O-HAS-UIDL + ;
: _SL-NEXT     ( sa -- a )  _SLOT-O-NEXT     + ;
: _SL-ID       ( sa -- a )  _SLOT-O-ID       + ;
: _SL-UIDL-BUF ( sa -- a )  _SLOT-O-UIDL-BUF + ;

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

VARIABLE _DESK-HEAD       \ → first slot in linked list (0 = empty)
0 _DESK-HEAD !

VARIABLE _DESK-FOCUS-SA   \ slot address of focused slot (0 = none)
0 _DESK-FOCUS-SA !

VARIABLE _DESK-NEXT-ID    \ monotonic ID counter, starts at 1
1 _DESK-NEXT-ID !

VARIABLE _DESK-VH         \ 0 = V-pref (cols first), 1 = H-pref
0 _DESK-VH !

VARIABLE _DESK-FULLFRAME  \ flag: full-frame mode active
0 _DESK-FULLFRAME !

VARIABLE _DESK-LAST-MIN-SA  \ last minimized slot (for restore)
0 _DESK-LAST-MIN-SA !

\ Active UIDL context tracking lives in the shell.
\ Desk delegates via ASHELL-CTX-SWITCH.

\ Config TOML buffer (kept alive so zero-copy strings remain valid).
VARIABLE _DESK-CFG-A   VARIABLE _DESK-CFG-L
0 _DESK-CFG-A !  0 _DESK-CFG-L !

\ Startup applet: set via DESK-QUEUE-LAUNCH before DESK-RUN.
\ DESK-INIT-CB launches this after the screen & region are ready.
VARIABLE _DESK-PENDING
0 _DESK-PENDING !

VARIABLE _DESK-BG-DIRTY     \ -1 = need full background fill next paint
-1 _DESK-BG-DIRTY !

\ =====================================================================
\  §2b — Theme
\ =====================================================================
\  14 colour slots used by the taskbar, dividers, hotbar, and clock.
\  _DESK-THEME-DEFAULTS sets a dark-blue palette.  _DESK-LOAD-THEME
\  overrides any slot that appears in [desk.theme] of a TOML config.

VARIABLE _DTH-TBAR-FG    VARIABLE _DTH-TBAR-BG    VARIABLE _DTH-TBAR-ATTR
VARIABLE _DTH-ACT-FG     VARIABLE _DTH-ACT-BG     VARIABLE _DTH-ACT-ATTR
VARIABLE _DTH-MIN-FG     VARIABLE _DTH-MIN-BG
VARIABLE _DTH-PIN-FG     VARIABLE _DTH-PIN-BG
VARIABLE _DTH-DIV-FG     VARIABLE _DTH-DIV-BG
VARIABLE _DTH-CLOCK-FG   VARIABLE _DTH-CLOCK-BG
VARIABLE _DTH-DESK-BG                             \ desktop background (layer 0)

: _DESK-THEME-DEFAULTS  ( -- )
    15 _DTH-TBAR-FG !   17 _DTH-TBAR-BG !   0 _DTH-TBAR-ATTR !
     0 _DTH-ACT-FG  !   12 _DTH-ACT-BG  !   1 _DTH-ACT-ATTR  !
     8 _DTH-MIN-FG  !   17 _DTH-MIN-BG  !
   244 _DTH-PIN-FG  !    0 _DTH-PIN-BG  !
   240 _DTH-DIV-FG  !    0 _DTH-DIV-BG  !
    14 _DTH-CLOCK-FG !  17 _DTH-CLOCK-BG !
    17 _DTH-DESK-BG ! ;
_DESK-THEME-DEFAULTS

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

CREATE _HB-ENTRIES  _HB-SZ _HB-MAX * ALLOT
VARIABLE _DHBAR-COUNT
0 _DHBAR-COUNT !

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

: _DESK-CTX-SWITCH  ( sa -- )
    _SL-UCTX @ ASHELL-CTX-SWITCH ;

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
        DUP _SL-HAS-UIDL @ IF
            DUP _DESK-CTX-SWITCH
            DUP _SL-RGN @ UTUI-RGN!
            UTUI-RELAYOUT
        THEN
        DROP
    LOOP
    -1 _DESK-BG-DIRTY !
    ASHELL-DIRTY! ;

\ =====================================================================
\  §7 — App Launch & Close
\ =====================================================================
\
\  Key difference from compositor: no APP-INIT calls.  The shell
\  owns the terminal.  Sub-app INIT-XT is called, but terminal
\  setup is not the sub-app's job.

: DESK-LAUNCH  ( desc -- id )
    _SLOT-SZ ALLOCATE IF DROP -1 EXIT THEN
    >R
    R@ _SLOT-SZ 0 FILL
    DUP R@ _SL-DESC !
    _ST-RUNNING R@ _SL-STATE !
    _DESK-NEXT-ID @ R@ _SL-ID !
    1 _DESK-NEXT-ID +!
    \ Allocate UIDL context if app declares UIDL (inline or file)
    DUP APP.UIDL-A @ OVER APP.UIDL-FILE-A @ OR IF
        UCTX-ALLOC DUP IF DUP UCTX-CLEAR THEN
        R@ _SL-UCTX !
        -1 R@ _SL-HAS-UIDL !
    ELSE
        0 R@ _SL-UCTX !
        0 R@ _SL-HAS-UIDL !
    THEN
    R@ _DESK-APPEND
    \ Auto-focus if this is the first slot
    _DESK-FOCUS-SA @ 0= IF
        _ST-FOCUSED R@ _SL-STATE !
        R@ _DESK-FOCUS-SA !
    THEN
    DESK-RELAYOUT
    \ Load UIDL document into sub-app context
    R@ _SL-HAS-UIDL @ IF
        R@ _DESK-CTX-SWITCH
        DUP APP.UIDL-A @ IF
            \ --- inline UIDL ---
            DUP APP.UIDL-A @
            OVER APP.UIDL-U @
            R@ _SL-RGN @
            UTUI-LOAD DROP
        ELSE DUP APP.UIDL-FILE-A @ IF
            \ --- file-based UIDL (loaded via shared loader) ---
            DUP APP.UIDL-FILE-A @
            OVER APP.UIDL-FILE-U @  ( desc path-a path-u )
            R@ _SL-RGN @           ( desc path-a path-u rgn )
            ASHELL-LOAD-UIDL       ( desc buf|0 )
            R@ _SL-UIDL-BUF !
        THEN THEN
    THEN
    \ Call sub-app init callback while context is live so that
    \ UTUI-BY-ID, UTUI-WIDGET-SET, UTUI-DO! etc. persist.
    DUP APP.INIT-XT @ ?DUP IF EXECUTE THEN
    \ Save context AFTER init — widget mounts & actions are now captured
    R@ _SL-HAS-UIDL @ IF R@ _DESK-CTX-SAVE THEN
    DROP
    R> _SL-ID @ ;

: DESK-CLOSE-ID  ( id -- )
    _DESK-FIND-ID DUP 0= IF DROP EXIT THEN
    >R
    \ Sub-app shutdown callback
    R@ _SL-DESC @ ?DUP IF
        APP.SHUTDOWN-XT @ ?DUP IF EXECUTE THEN
    THEN
    \ Detach UIDL if active
    R@ _SL-HAS-UIDL @ IF
        R@ _DESK-CTX-SWITCH
        UTUI-DETACH
        0 ASHELL-CTX-SWITCH
    THEN
    \ Free resources
    R@ _SL-UIDL-BUF @ ?DUP IF FREE DROP THEN
    R@ _SL-UCTX @ ?DUP IF UCTX-FREE THEN
    R@ _SL-RGN @ ?DUP IF RGN-FREE THEN
    \ Fixup focus / last-minimized pointers
    R@ _DESK-FOCUS-SA @ = IF
        0 _DESK-FOCUS-SA !
    THEN
    R@ _DESK-LAST-MIN-SA @ = IF
        0 _DESK-LAST-MIN-SA !
    THEN
    R@ _SL-ID @ _DESK-HOTBAR-SLOT-CLOSED
    R@ _DESK-UNLINK
    R> FREE DROP
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
    DRW-STYLE-RESTORE ;

\ =====================================================================
\  §10 — APP-DESC Callbacks
\ =====================================================================
\
\  The DESK is a normal APP-DESC app.  The shell calls these
\  callbacks — no private event loop, no APP-INIT/APP-SHUTDOWN.

\ --- Init ---
: DESK-INIT-CB  ( -- )
    0 _DESK-HEAD !
    0 _DESK-FOCUS-SA !
    1 _DESK-NEXT-ID !
    0 _DESK-VH !
    0 _DESK-FULLFRAME !
    0 _DESK-LAST-MIN-SA !
    0 ASHELL-CTX-SWITCH
    _DESK-THEME-DEFAULTS
    _DESK-HOTBAR-CLEAR
    \ Load config if a buffer was supplied before DESK-RUN
    _DESK-CFG-A @ ?DUP IF _DESK-CFG-L @ DESK-LOAD-CONFIG THEN
    \ Launch queued startup applet if one was set
    _DESK-PENDING @ ?DUP IF 0 _DESK-PENDING ! DESK-LAUNCH DROP THEN ;

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
    DROP 0 ;

\ _DESK-TILE-AT ( row col -- slot | 0 )
\   Find the visible slot whose region contains (row, col).
\   Walks the slot list; returns the first match or 0.
VARIABLE _DTA-ROW  VARIABLE _DTA-COL

: _DESK-TILE-AT  ( row col -- slot | 0 )
    _DTA-COL !  _DTA-ROW !
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            DUP _SL-RGN @ ?DUP IF        ( slot rgn )
                DUP RGN-ROW _DTA-ROW @ <=
                OVER RGN-COL _DTA-COL @ <= AND
                OVER RGN-ROW OVER RGN-H + _DTA-ROW @ > AND
                SWAP RGN-COL SWAP RGN-W + _DTA-COL @ > AND
                IF EXIT THEN              ( slot — match )
            THEN
        THEN
        _SL-NEXT @
    REPEAT
    0 ;

\ _DESK-DISPATCH-MOUSE ( ev -- flag )
\   Handle a synthetic mouse event from the shell cursor.
\   Hit-test tiles, context-switch, and forward to UTUI-DISPATCH-MOUSE.
: _DESK-DISPATCH-MOUSE  ( ev -- flag )
    DUP ASHELL-MOUSE-ROW OVER ASHELL-MOUSE-COL   ( ev row col )
    2DUP _DESK-TILE-AT                             ( ev row col slot|0 )
    DUP 0= IF DROP 2DROP DROP 0 EXIT THEN
    >R                                             ( ev row col  R: slot )
    R@ _SL-HAS-UIDL @ IF
        R@ _DESK-CTX-SWITCH
        3 PICK ASHELL-MOUSE-BTN        ( ev row col btn )
        UTUI-DISPATCH-MOUSE            ( ev handled? )
        IF
            R@ _DESK-CTX-SAVE
            R> DROP
            DROP -1 EXIT
        THEN
    THEN
    R@ _SL-HAS-UIDL @ IF R@ _DESK-CTX-SAVE THEN
    R> DROP
    DROP 0 ;

\ --- Event ---
\
\  Routes events to the focused sub-app.  If the sub-app calls
\  ASHELL-QUIT, we intercept it via ASHELL-QUIT-PENDING? /
\  ASHELL-CANCEL-QUIT, and close that tile instead of shutting
\  down the whole shell.
: DESK-EVENT-CB  ( ev -- flag )
    \ 0. Mouse events → tile hit-test routing
    DUP ASHELL-MOUSE? IF
        _DESK-DISPATCH-MOUSE EXIT
    THEN
    \ 1. Route to focused sub-app
    _DESK-FOCUS-SA @ ?DUP IF
        >R
        R@ _SL-HAS-UIDL @ IF
            R@ _DESK-CTX-SWITCH
            OVER UTUI-DISPATCH-KEY IF
                R@ _DESK-CTX-SAVE
                R> DROP
                ASHELL-DIRTY! DROP -1 EXIT
            THEN
        THEN
        R@ _SL-DESC @ ?DUP IF
            APP.EVENT-XT @ ?DUP IF
                2 PICK SWAP EXECUTE       ( ev consumed? )
                \ Intercept sub-app ASHELL-QUIT
                ASHELL-QUIT-PENDING? IF
                    ASHELL-CANCEL-QUIT
                    R@ _SL-HAS-UIDL @ IF R@ _DESK-CTX-SAVE THEN
                    R@ _SL-ID @ DESK-CLOSE-ID
                    R> DROP
                    DROP -1 EXIT
                THEN
                IF
                    R@ _SL-HAS-UIDL @ IF R@ _DESK-CTX-SAVE THEN
                    R> DROP
                    ASHELL-DIRTY! DROP -1 EXIT
                THEN
            THEN
        THEN
        R@ _SL-HAS-UIDL @ IF R@ _DESK-CTX-SAVE THEN
        R> DROP
    THEN
    \ 2. DESK's own shortcuts
    DUP _DESK-SHORTCUT? IF DROP -1 EXIT THEN
    DROP 0 ;

\ --- Tick ---
: DESK-TICK-CB  ( -- )
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-ALIVE? IF
            DUP _SL-DESC @ ?DUP IF
                APP.TICK-XT @ ?DUP IF EXECUTE THEN
            THEN
        THEN
        _SL-NEXT @
    REPEAT ;

\ --- Paint ---
\
\  Iterates visible sub-apps, context-switches to each, and calls
\  their UTUI-PAINT + PAINT-XT within their tile region.  Then
\  draws dividers and the taskbar.
: DESK-PAINT-CB  ( -- )
    RGN-ROOT
    \ Layer 0: fill tile area with desk background colour
    \ Only runs when geometry changed (relayout / init / resize)
    _DESK-BG-DIRTY @ IF
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
                DUP _SL-RGN @ IF
                    DUP _SL-UCTX @
                    OVER _SL-RGN @
                    2 PICK _SL-HAS-UIDL @
                    3 PICK _SL-DESC @
                    ASHELL-PAINT-CHILD
                THEN
            THEN
        THEN
        _SL-NEXT @
    REPEAT
    RGN-ROOT
    _DESK-FULLFRAME @ 0= IF _DESK-DRAW-DIVIDERS THEN
    _DESK-PAINT-TASKBAR ;

\ --- Shutdown ---
: DESK-SHUTDOWN-CB  ( -- )
    BEGIN _DESK-HEAD @ ?DUP WHILE
        _SL-ID @ DESK-CLOSE-ID
    REPEAT ;

\ =====================================================================
\  §11 — DESK Descriptor & Entry Point
\ =====================================================================

CREATE DESK-DESC  APP-DESC ALLOT

: _DESK-FILL-DESC  ( -- )
    DESK-DESC APP-DESC-INIT
    ['] DESK-INIT-CB     DESK-DESC APP.INIT-XT !
    ['] DESK-EVENT-CB    DESK-DESC APP.EVENT-XT !
    ['] DESK-TICK-CB     DESK-DESC APP.TICK-XT !
    ['] DESK-PAINT-CB    DESK-DESC APP.PAINT-XT !
    ['] DESK-SHUTDOWN-CB DESK-DESC APP.SHUTDOWN-XT !
    0                    DESK-DESC APP.UIDL-A !
    0                    DESK-DESC APP.UIDL-U !
    0                    DESK-DESC APP.WIDTH !
    0                    DESK-DESC APP.HEIGHT !
    S" DESK"  DESK-DESC APP.TITLE-U !
              DESK-DESC APP.TITLE-A ! ;

\ DESK-QUEUE-LAUNCH ( desc -- )
\   Set the applet to auto-launch at desk startup.
\   Must be called BEFORE DESK-RUN.
: DESK-QUEUE-LAUNCH  ( desc -- )
    _DESK-PENDING ! ;

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
: DESK-RUN          _desk-run-xt          _desk-guard WITH-GUARD ;
[THEN] [THEN]
