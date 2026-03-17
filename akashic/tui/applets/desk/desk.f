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
\  §1 — UIDL Context Save / Restore
\ =====================================================================
\
\  Per sub-app UIDL context buffer holding 15 scalar variables and
\  10 pool arrays.  Total ~99,448 bytes (~97 KiB).
\
\  Recycled from app-compositor.f §1.

15 CONSTANT _UCTX-NVAR
120 CONSTANT _UCTX-VAR-SZ       \ 15 × 8

\ Pool sizes (must match module declarations)
32768 CONSTANT _UCTX-ELEMS-SZ   \ 256 × 128
20480 CONSTANT _UCTX-ATTRS-SZ   \ 512 × 40
12288 CONSTANT _UCTX-STRS-SZ
 2048 CONSTANT _UCTX-HASH-SZ    \ 256 × 8
 4096 CONSTANT _UCTX-HIDS-SZ    \ 256 × 16
 3072 CONSTANT _UCTX-SUBS-SZ    \ 128 × 24
20480 CONSTANT _UCTX-SC-SZ      \ 256 × 80
 1536 CONSTANT _UCTX-ACTS-SZ    \ 64 × 24
 2048 CONSTANT _UCTX-SHORTS-SZ  \ 64 × 32
  512 CONSTANT _UCTX-OVBUF-SZ   \ 32 × 16

\ Offsets into context buffer
_UCTX-VAR-SZ                                       CONSTANT _UCTX-O-ELEMS
_UCTX-O-ELEMS  _UCTX-ELEMS-SZ  +                   CONSTANT _UCTX-O-ATTRS
_UCTX-O-ATTRS  _UCTX-ATTRS-SZ  +                   CONSTANT _UCTX-O-STRS
_UCTX-O-STRS   _UCTX-STRS-SZ   +                   CONSTANT _UCTX-O-HASH
_UCTX-O-HASH   _UCTX-HASH-SZ   +                   CONSTANT _UCTX-O-HIDS
_UCTX-O-HIDS   _UCTX-HIDS-SZ   +                   CONSTANT _UCTX-O-SUBS
_UCTX-O-SUBS   _UCTX-SUBS-SZ   +                   CONSTANT _UCTX-O-SC
_UCTX-O-SC     _UCTX-SC-SZ     +                   CONSTANT _UCTX-O-ACTS
_UCTX-O-ACTS   _UCTX-ACTS-SZ   +                   CONSTANT _UCTX-O-SHORTS
_UCTX-O-SHORTS _UCTX-SHORTS-SZ +                   CONSTANT _UCTX-O-OVBUF
_UCTX-O-OVBUF  _UCTX-OVBUF-SZ  +                   CONSTANT _UCTX-TOTAL

\ --- Variable table: maps index → global VARIABLE address ---
CREATE _UCTX-VARS  _UCTX-NVAR CELLS ALLOT

: _UCTX-INIT-VARS  ( -- )
    _UDL-ECNT           _UCTX-VARS  0 CELLS + !
    _UDL-ACNT           _UCTX-VARS  1 CELLS + !
    _UDL-SPOS           _UCTX-VARS  2 CELLS + !
    _UDL-ROOT           _UCTX-VARS  3 CELLS + !
    _UDL-SUB-CNT        _UCTX-VARS  4 CELLS + !
    _UTUI-ELEM-BASE     _UCTX-VARS  5 CELLS + !
    _UTUI-DOC-LOADED    _UCTX-VARS  6 CELLS + !
    _UTUI-STATE         _UCTX-VARS  7 CELLS + !
    _UTUI-FOCUS-P       _UCTX-VARS  8 CELLS + !
    _UTUI-ACT-CNT       _UCTX-VARS  9 CELLS + !
    _UTUI-SHORT-CNT     _UCTX-VARS 10 CELLS + !
    _UTUI-OVERLAY-CNT   _UCTX-VARS 11 CELLS + !
    _UTUI-SAVED-FOCUS   _UCTX-VARS 12 CELLS + !
    _UTUI-SKIP-CHILDREN _UCTX-VARS 13 CELLS + !
    _UTUI-RGN           _UCTX-VARS 14 CELLS + ! ;
_UCTX-INIT-VARS

\ --- Pool table: maps index → (global-addr, ctx-offset, size) ---
10 CONSTANT _UCTX-NPOOL
CREATE _UCTX-POOLS  _UCTX-NPOOL 3 * CELLS ALLOT

: _UCTX-INIT-POOLS  ( -- )
    _UDL-ELEMS        _UCTX-POOLS   0 + !
    _UCTX-O-ELEMS     _UCTX-POOLS   8 + !
    _UCTX-ELEMS-SZ    _UCTX-POOLS  16 + !
    _UDL-ATTRS        _UCTX-POOLS  24 + !
    _UCTX-O-ATTRS     _UCTX-POOLS  32 + !
    _UCTX-ATTRS-SZ    _UCTX-POOLS  40 + !
    _UDL-STRS         _UCTX-POOLS  48 + !
    _UCTX-O-STRS      _UCTX-POOLS  56 + !
    _UCTX-STRS-SZ     _UCTX-POOLS  64 + !
    _UDL-HASH         _UCTX-POOLS  72 + !
    _UCTX-O-HASH      _UCTX-POOLS  80 + !
    _UCTX-HASH-SZ     _UCTX-POOLS  88 + !
    _UDL-HIDS         _UCTX-POOLS  96 + !
    _UCTX-O-HIDS      _UCTX-POOLS 104 + !
    _UCTX-HIDS-SZ     _UCTX-POOLS 112 + !
    _UDL-SUBS         _UCTX-POOLS 120 + !
    _UCTX-O-SUBS      _UCTX-POOLS 128 + !
    _UCTX-SUBS-SZ     _UCTX-POOLS 136 + !
    _UTUI-SIDECARS    _UCTX-POOLS 144 + !
    _UCTX-O-SC        _UCTX-POOLS 152 + !
    _UCTX-SC-SZ       _UCTX-POOLS 160 + !
    _UTUI-ACTS        _UCTX-POOLS 168 + !
    _UCTX-O-ACTS      _UCTX-POOLS 176 + !
    _UCTX-ACTS-SZ     _UCTX-POOLS 184 + !
    _UTUI-SHORTS      _UCTX-POOLS 192 + !
    _UCTX-O-SHORTS    _UCTX-POOLS 200 + !
    _UCTX-SHORTS-SZ   _UCTX-POOLS 208 + !
    _UTUI-OVERLAY-BUF _UCTX-POOLS 216 + !
    _UCTX-O-OVBUF     _UCTX-POOLS 224 + !
    _UCTX-OVBUF-SZ    _UCTX-POOLS 232 + ! ;
_UCTX-INIT-POOLS

\ --- UCTX-ALLOC / FREE / SAVE / RESTORE / CLEAR ---

: UCTX-ALLOC  ( -- ctx | 0 )
    _UCTX-TOTAL ALLOCATE IF DROP 0 THEN ;

: UCTX-FREE  ( ctx -- )  FREE ;

\ Pool copy helper variables
VARIABLE _UCP-SRC   VARIABLE _UCP-DST   VARIABLE _UCP-SZ

: UCTX-SAVE  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    \ Save scalars: ctx[i] = *var
    _UCTX-NVAR 0 DO
        I CELLS _UCTX-VARS + @   \ global var addr
        @ OVER I CELLS + !
    LOOP
    \ Save pools: global → ctx
    _UCTX-NPOOL 0 DO
        I 3 * CELLS _UCTX-POOLS +
        DUP @       _UCP-SRC !
        DUP 16 + @  _UCP-SZ  !
        8 + @ OVER + _UCP-DST !
        _UCP-SRC @ _UCP-DST @ _UCP-SZ @ CMOVE
    LOOP
    DROP ;

: UCTX-RESTORE  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    \ Restore scalars: *var = ctx[i]
    _UCTX-NVAR 0 DO
        DUP I CELLS + @           \ value from ctx
        I CELLS _UCTX-VARS + @   \ global var addr
        !
    LOOP
    \ Restore pools: ctx → global
    _UCTX-NPOOL 0 DO
        I 3 * CELLS _UCTX-POOLS +
        DUP @       _UCP-DST !
        DUP 16 + @  _UCP-SZ  !
        8 + @ OVER + _UCP-SRC !
        _UCP-SRC @ _UCP-DST @ _UCP-SZ @ CMOVE
    LOOP
    DROP ;

: UCTX-CLEAR  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    _UCTX-TOTAL 0 FILL ;

\ =====================================================================
\  §2 — Slot Struct (linked list, heap-allocated)
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
56 CONSTANT _SLOT-SZ

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

: _SL-VISIBLE?  ( sa -- flag )
    _SL-STATE @ DUP _ST-RUNNING = SWAP _ST-FOCUSED = OR ;

: _SL-ALIVE?  ( sa -- flag )
    _SL-STATE @ _ST-EMPTY <> ;

\ =====================================================================
\  §3 — DESK Global State
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

\ Active UIDL context: slot address whose ctx is live, or 0.
VARIABLE _DESK-ACTIVE-CTX-SA
0 _DESK-ACTIVE-CTX-SA !

\ Config TOML buffer (kept alive so zero-copy strings remain valid).
VARIABLE _DESK-CFG-A   VARIABLE _DESK-CFG-L
0 _DESK-CFG-A !  0 _DESK-CFG-L !

\ =====================================================================
\  §3b — Theme
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

: _DESK-THEME-DEFAULTS  ( -- )
    15 _DTH-TBAR-FG !   17 _DTH-TBAR-BG !   0 _DTH-TBAR-ATTR !
     0 _DTH-ACT-FG  !   12 _DTH-ACT-BG  !   1 _DTH-ACT-ATTR  !
     8 _DTH-MIN-FG  !   17 _DTH-MIN-BG  !
   244 _DTH-PIN-FG  !    0 _DTH-PIN-BG  !
   240 _DTH-DIV-FG  !    0 _DTH-DIV-BG  !
    14 _DTH-CLOCK-FG !  17 _DTH-CLOCK-BG ! ;
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
         S" clock-bg"       _DTH-CLOCK-BG  _DTH-TRY ;

\ =====================================================================
\  §3c — Hotbar (Pinned App Entries)
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
    _DHBAR-COUNT @ 0 DO
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
\  §3d — Config Loader
\ =====================================================================

: DESK-LOAD-CONFIG  ( addr len -- )
    2DUP _DESK-LOAD-THEME
    _DESK-LOAD-HOTBAR ;

\ =====================================================================
\  §4 — Linked-List Helpers
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
\  §5 — Visible Slot Collection Buffer
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
\  §6 — Dynamic Tiling Layout Engine
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
\  §7 — UIDL Context Switching
\ =====================================================================

: _DESK-CTX-SAVE  ( sa -- )
    _SL-UCTX @ ?DUP IF UCTX-SAVE THEN ;

: _DESK-CTX-RESTORE  ( sa -- )
    _SL-UCTX @ ?DUP IF UCTX-RESTORE THEN ;

: _DESK-CTX-SWITCH  ( sa -- )
    DUP _DESK-ACTIVE-CTX-SA @ = IF DROP EXIT THEN
    _DESK-ACTIVE-CTX-SA @ ?DUP IF _DESK-CTX-SAVE THEN
    DUP _DESK-CTX-RESTORE
    _DESK-ACTIVE-CTX-SA ! ;

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
            DUP _SL-RGN @ _UTUI-RGN !
            UTUI-RELAYOUT
        THEN
        DROP
    LOOP
    ASHELL-DIRTY! ;

\ =====================================================================
\  §8 — App Launch & Close
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
    \ Allocate UIDL context if app declares UIDL
    DUP APP.UIDL-A @ IF
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
        DUP APP.UIDL-A @
        OVER APP.UIDL-U @
        R@ _SL-RGN @
        UTUI-LOAD DROP
        R@ _DESK-CTX-SAVE
    THEN
    \ Call sub-app init callback
    DUP APP.INIT-XT @ ?DUP IF EXECUTE THEN
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
        0 _DESK-ACTIVE-CTX-SA !
    THEN
    \ Free resources
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
\  §9 — Focus, Minimize, Restore
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
\  §10 — Taskbar Painter
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
\  §11 — APP-DESC Callbacks
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
    0 _DESK-ACTIVE-CTX-SA !
    _DESK-THEME-DEFAULTS
    _DESK-HOTBAR-CLEAR
    \ Load config if a buffer was supplied before DESK-RUN
    _DESK-CFG-A @ ?DUP IF _DESK-CFG-L @ DESK-LOAD-CONFIG THEN ;

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

\ --- Event ---
\
\  Routes events to the focused sub-app.  If the sub-app calls
\  ASHELL-QUIT, we intercept it: re-set _ASHELL-RUNNING to -1
\  and close that tile instead of shutting down the whole shell.
: DESK-EVENT-CB  ( ev -- flag )
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
                _ASHELL-RUNNING @ 0= IF
                    -1 _ASHELL-RUNNING !
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
    _DESK-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _DESK-FULLFRAME @ IF
                DUP _DESK-FOCUS-SA @ <>
            ELSE
                0
            THEN
            0= IF
                DUP _SL-RGN @ ?DUP IF
                    RGN-USE
                    OVER _SL-HAS-UIDL @ IF
                        OVER _DESK-CTX-SWITCH
                        UTUI-PAINT
                    THEN
                    OVER _SL-DESC @ ?DUP IF
                        APP.PAINT-XT @ ?DUP IF EXECUTE THEN
                    THEN
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
\  §12 — DESK Descriptor & Entry Point
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
    S" DESK"  DESK-DESC APP.TITLE-A !
              DESK-DESC APP.TITLE-U ! ;

: DESK-RUN  ( -- )
    _DESK-FILL-DESC
    DESK-DESC ASHELL-RUN ;

\ =====================================================================
\  §13 — Guard (Concurrency Safety)
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
