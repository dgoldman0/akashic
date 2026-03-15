\ =================================================================
\  app-compositor.f — TUI Multi-App Compositor
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: COMP- / _COMP-
\  Depends on: akashic-tui-app-shell, akashic-tui-uidl-tui,
\              akashic-tui-screen, akashic-tui-region,
\              akashic-tui-draw, akashic-tui-keys,
\              akashic-liraq-uidl
\
\  Multi-app compositor with dynamic tiling.  No hardcoded screen
\  size or slot limit.  Slots are heap-allocated in a linked list.
\  Screen dimensions come from SCR-W / SCR-H, recomputed on resize.
\  An always-on taskbar occupies the last row.
\
\  Tiling algorithm:
\    Given N visible apps and usable area W × H:
\    - cols = ceil(sqrt(N)), rows = ceil(N / cols)  (V-pref)
\    - rows = ceil(sqrt(N)), cols = ceil(N / rows)  (H-pref)
\    - tile-w = (W - (cols-1)) / cols, tile-h = (H - (rows-1)) / rows
\    - remainder to last col/row
\    - 1-cell dividers between adjacent tiles
\
\  Public API:
\    COMP-INIT         ( -- )          Initialize compositor
\    COMP-LAUNCH       ( desc -- id )  Launch app, return slot ID
\    COMP-CLOSE-ID     ( id -- )       Close app by ID
\    COMP-FOCUS-ID     ( id -- )       Focus app by ID
\    COMP-MINIMIZE-ID  ( id -- )       Minimize by ID
\    COMP-RESTORE      ( -- )          Restore last minimized
\    COMP-FULLFRAME!   ( flag -- )     Toggle full-frame focused
\    COMP-TOGGLE-VH    ( -- )          Toggle V/H tiling pref
\    COMP-RELAYOUT     ( -- )          Recompute tile grid
\    COMP-PAINT-ALL    ( -- )          Paint all visible + taskbar
\    COMP-ROUTE-KEY    ( ev -- )       Route key to focused app
\    COMP-SHORTCUT?    ( ev -- flag )  Check shell shortcuts
\    COMP-TICK-ALL     ( -- )          Tick all alive apps
\    COMP-RUN          ( -- )          Main event loop (blocks)
\    COMP-QUIT         ( -- )          Signal exit
\    COMP-SLOT-COUNT   ( -- n )        Number of live slots
\    COMP-VCOUNT       ( -- n )        Number of visible slots
\ =================================================================

PROVIDED akashic-tui-app-compositor

REQUIRE app-shell.f
REQUIRE uidl-tui.f
REQUIRE screen.f
REQUIRE region.f
REQUIRE draw.f
REQUIRE keys.f
REQUIRE ../liraq/uidl.f

\ =====================================================================
\  §1 — UIDL Context Save / Restore
\ =====================================================================
\
\  Per-app UIDL context buffer holding 15 scalar variables and
\  10 pool arrays.  Total ~99,448 bytes (~97 KiB).

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
\  No fixed array.  Each slot is ALLOCATE'd and linked via _SL-NEXT.
\  Slot IDs are assigned from a monotonic counter (1, 2, 3, ...).
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
\  §3 — Compositor Global State
\ =====================================================================

VARIABLE _COMP-HEAD       \ → first slot in linked list (0 = empty)
0 _COMP-HEAD !

VARIABLE _COMP-FOCUS-SA   \ slot address of focused slot (0 = none)
0 _COMP-FOCUS-SA !

VARIABLE _COMP-NEXT-ID    \ monotonic ID counter, starts at 1
1 _COMP-NEXT-ID !

VARIABLE _COMP-VH         \ 0 = V-pref (cols first), 1 = H-pref
0 _COMP-VH !

VARIABLE _COMP-FULLFRAME  \ flag: full-frame mode active
0 _COMP-FULLFRAME !

VARIABLE _COMP-RUNNING    \ event loop flag
0 _COMP-RUNNING !

VARIABLE _COMP-DIRTY      \ repaint needed
0 _COMP-DIRTY !

VARIABLE _COMP-TICK-MS    \ tick interval (milliseconds)
50 _COMP-TICK-MS !

VARIABLE _COMP-LAST-TICK
0 _COMP-LAST-TICK !

VARIABLE _COMP-LAST-MIN-SA  \ last minimized slot (for restore)
0 _COMP-LAST-MIN-SA !

\ Active UIDL context: slot address whose ctx is live, or 0.
VARIABLE _COMP-ACTIVE-CTX-SA
0 _COMP-ACTIVE-CTX-SA !

\ =====================================================================
\  §4 — Linked-List Helpers
\ =====================================================================

\ Count all live slots.
: COMP-SLOT-COUNT  ( -- n )
    0  _COMP-HEAD @
    BEGIN ?DUP WHILE  SWAP 1+ SWAP  _SL-NEXT @  REPEAT ;

\ Count visible (non-minimized) slots.
: COMP-VCOUNT  ( -- n )
    0  _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF SWAP 1+ SWAP THEN
        _SL-NEXT @
    REPEAT ;

\ Find slot by ID.  Returns slot address or 0.
: _COMP-FIND-ID  ( id -- sa | 0 )
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-ID @ 2 PICK = IF NIP EXIT THEN
        _SL-NEXT @
    REPEAT
    DROP 0 ;

\ Unlink a slot from the list.  Does NOT free.
VARIABLE _CUL-PREV   VARIABLE _CUL-SA
: _COMP-UNLINK  ( sa -- )
    _CUL-SA !
    _COMP-HEAD @ _CUL-SA @ = IF
        _CUL-SA @ _SL-NEXT @  _COMP-HEAD !
        EXIT
    THEN
    _COMP-HEAD @ _CUL-PREV !
    BEGIN _CUL-PREV @ WHILE
        _CUL-PREV @ _SL-NEXT @  _CUL-SA @ = IF
            _CUL-SA @ _SL-NEXT @
            _CUL-PREV @ _SL-NEXT !
            EXIT
        THEN
        _CUL-PREV @ _SL-NEXT @  _CUL-PREV !
    REPEAT ;

\ Append a slot at the tail of the list.
: _COMP-APPEND  ( sa -- )
    0 OVER _SL-NEXT !
    _COMP-HEAD @ 0= IF
        _COMP-HEAD !
        EXIT
    THEN
    _COMP-HEAD @
    BEGIN DUP _SL-NEXT @ WHILE _SL-NEXT @ REPEAT
    _SL-NEXT ! ;

\ =====================================================================
\  §5 — Visible Slot Collection Buffer
\ =====================================================================

64 CONSTANT _COMP-MAX-VIS
CREATE _COMP-VIS-BUF   _COMP-MAX-VIS CELLS ALLOT
VARIABLE _COMP-VIS-N

: _COMP-COLLECT-VISIBLE  ( -- )
    0 _COMP-VIS-N !
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _COMP-VIS-N @ _COMP-MAX-VIS < IF
                DUP  _COMP-VIS-N @ CELLS _COMP-VIS-BUF +  !
                1 _COMP-VIS-N +!
            THEN
        THEN
        _SL-NEXT @
    REPEAT ;

\ =====================================================================
\  §6 — Dynamic Tiling Layout Engine
\ =====================================================================
\
\  All computations use SCR-W and SCR-H at call time.
\  Usable area: W = SCR-W,  H = SCR-H - 1  (last row = taskbar).

\ Integer ceiling of sqrt via Newton iteration.
: _COMP-ISQRT  ( n -- root )
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
: _COMP-CDIV  ( a b -- q )
    DUP >R  1- +  R> / ;

\ Layout work variables
VARIABLE _CL-W   VARIABLE _CL-H
VARIABLE _CL-COLS  VARIABLE _CL-ROWS
VARIABLE _CL-TW    VARIABLE _CL-TH
VARIABLE _CL-LW    VARIABLE _CL-LH

\ Free all app regions.
: _COMP-FREE-REGIONS  ( -- )
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-RGN @ ?DUP IF RGN-FREE THEN
        0 OVER _SL-RGN !
        _SL-NEXT @
    REPEAT ;

\ Compute grid dimensions for N visible apps.
: _COMP-GRID  ( n -- )
    DUP 0 <= IF DROP 0 _CL-COLS ! 0 _CL-ROWS ! EXIT THEN
    DUP 1 = IF DROP 1 _CL-COLS ! 1 _CL-ROWS ! EXIT THEN
    _COMP-VH @ 0= IF
        \ V-pref: cols = ceil(sqrt(N)), rows = ceil(N/cols)
        DUP _COMP-ISQRT                  ( n s )
        DUP DUP * 2 PICK < IF 1+ THEN   ( n cols )
        DUP _CL-COLS !
        _COMP-CDIV _CL-ROWS !
    ELSE
        \ H-pref: rows = ceil(sqrt(N)), cols = ceil(N/rows)
        DUP _COMP-ISQRT                  ( n s )
        DUP DUP * 2 PICK < IF 1+ THEN   ( n rows )
        DUP _CL-ROWS !
        _COMP-CDIV _CL-COLS !
    THEN ;

\ Compute tile sizes from current grid and screen.
: _COMP-TILE-SIZES  ( -- )
    SCR-W _CL-W !
    SCR-H 1- _CL-H !
    _CL-W @  _CL-COLS @ 1- -  _CL-COLS @  /  _CL-TW !
    _CL-H @  _CL-ROWS @ 1- -  _CL-ROWS @  /  _CL-TH !
    _CL-W @  _CL-COLS @ 1- -  _CL-TW @ _CL-COLS @ 1- * -  _CL-LW !
    _CL-H @  _CL-ROWS @ 1- -  _CL-TH @ _CL-ROWS @ 1- * -  _CL-LH ! ;

\ Assign region to i-th visible slot.
VARIABLE _CA-R   VARIABLE _CA-C
VARIABLE _CA-TW  VARIABLE _CA-TH

: _COMP-ASSIGN-TILE  ( idx -- )
    DUP CELLS _COMP-VIS-BUF + @      ( idx sa )
    SWAP                              ( sa idx )
    DUP _CL-COLS @ /                  ( sa idx grow )
    SWAP _CL-COLS @ MOD               ( sa grow gcol )
    \ pixel-col = gcol * (tile-w + 1)
    DUP _CL-TW @ 1+ * _CA-C !
    \ width: last col? use last-w, else tile-w
    DUP _CL-COLS @ 1- = IF
        _CL-LW @
    ELSE
        _CL-TW @
    THEN _CA-TW !
    DROP                              ( sa grow )
    \ pixel-row = grow * (tile-h + 1)
    DUP _CL-TH @ 1+ * _CA-R !
    \ height: last row? use last-h, else tile-h
    _CL-ROWS @ 1- = IF
        _CL-LH @
    ELSE
        _CL-TH @
    THEN _CA-TH !
    _CA-R @ _CA-C @ _CA-TH @ _CA-TW @ RGN-NEW
    SWAP _SL-RGN ! ;

\ Draw dividers.
: _COMP-DRAW-DIVIDERS  ( -- )
    DRW-STYLE-SAVE
    240 0 0 DRW-STYLE!
    _CL-COLS @ 1 > IF
        _CL-COLS @ 1- 0 DO
            I 1+ _CL-TW @ * I +
            9474 0 OVER _CL-H @ DRW-VLINE
            DROP
        LOOP
    THEN
    _CL-ROWS @ 1 > IF
        _CL-ROWS @ 1- 0 DO
            I 1+ _CL-TH @ * I +
            9472 OVER 0 _CL-W @ DRW-HLINE
            DROP
        LOOP
    THEN
    DRW-STYLE-RESTORE ;

\ Master relayout.
: COMP-RELAYOUT  ( -- )
    _COMP-COLLECT-VISIBLE
    _COMP-FREE-REGIONS
    _COMP-VIS-N @ DUP 0= IF DROP -1 _COMP-DIRTY ! EXIT THEN
    DUP _COMP-GRID
    _COMP-TILE-SIZES
    0 DO I _COMP-ASSIGN-TILE LOOP
    -1 _COMP-DIRTY ! ;

\ =====================================================================
\  §7 — UIDL Context Switching
\ =====================================================================

: _COMP-CTX-SAVE  ( sa -- )
    _SL-UCTX @ ?DUP IF UCTX-SAVE THEN ;

: _COMP-CTX-RESTORE  ( sa -- )
    _SL-UCTX @ ?DUP IF UCTX-RESTORE THEN ;

: _COMP-CTX-SWITCH  ( sa -- )
    DUP _COMP-ACTIVE-CTX-SA @ = IF DROP EXIT THEN
    _COMP-ACTIVE-CTX-SA @ ?DUP IF _COMP-CTX-SAVE THEN
    DUP _COMP-CTX-RESTORE
    _COMP-ACTIVE-CTX-SA ! ;

\ =====================================================================
\  §8 — App Launch & Close
\ =====================================================================

: COMP-LAUNCH  ( desc -- id )
    _SLOT-SZ ALLOCATE IF DROP -1 EXIT THEN
    >R
    R@ _SLOT-SZ 0 FILL
    DUP R@ _SL-DESC !
    _ST-RUNNING R@ _SL-STATE !
    _COMP-NEXT-ID @ R@ _SL-ID !
    1 _COMP-NEXT-ID +!
    DUP APP.UIDL-A @ IF
        UCTX-ALLOC DUP IF DUP UCTX-CLEAR THEN
        R@ _SL-UCTX !
        -1 R@ _SL-HAS-UIDL !
    ELSE
        0 R@ _SL-UCTX !
        0 R@ _SL-HAS-UIDL !
    THEN
    R@ _COMP-APPEND
    _COMP-FOCUS-SA @ 0= IF
        _ST-FOCUSED R@ _SL-STATE !
        R@ _COMP-FOCUS-SA !
    THEN
    COMP-RELAYOUT
    R@ _SL-HAS-UIDL @ IF
        R@ _COMP-CTX-SWITCH
        DUP APP.UIDL-A @
        OVER APP.UIDL-U @
        R@ _SL-RGN @
        UTUI-LOAD DROP
        R@ _COMP-CTX-SAVE
    THEN
    DUP APP.INIT-XT @ ?DUP IF EXECUTE THEN
    DROP
    R> _SL-ID @ ;

: COMP-CLOSE-ID  ( id -- )
    _COMP-FIND-ID DUP 0= IF DROP EXIT THEN
    >R
    R@ _SL-DESC @ ?DUP IF
        APP.SHUTDOWN-XT @ ?DUP IF EXECUTE THEN
    THEN
    R@ _SL-HAS-UIDL @ IF
        R@ _COMP-CTX-SWITCH
        UTUI-DETACH
        0 _COMP-ACTIVE-CTX-SA !
    THEN
    R@ _SL-UCTX @ ?DUP IF UCTX-FREE THEN
    R@ _SL-RGN @ ?DUP IF RGN-FREE THEN
    R@ _COMP-FOCUS-SA @ = IF
        0 _COMP-FOCUS-SA !
    THEN
    R@ _COMP-LAST-MIN-SA @ = IF
        0 _COMP-LAST-MIN-SA !
    THEN
    R@ _COMP-UNLINK
    R> FREE
    _COMP-FOCUS-SA @ 0= IF
        _COMP-HEAD @
        BEGIN ?DUP WHILE
            DUP _SL-VISIBLE? IF
                DUP _COMP-FOCUS-SA !
                _ST-FOCUSED SWAP _SL-STATE !
                0
            ELSE
                _SL-NEXT @
            THEN
        REPEAT
    THEN
    COMP-RELAYOUT ;

\ =====================================================================
\  §9 — Focus, Minimize, Restore
\ =====================================================================

: COMP-FOCUS-ID  ( id -- )
    _COMP-FIND-ID DUP 0= IF DROP EXIT THEN
    DUP _SL-STATE @ _ST-MINIMIZED = IF DROP EXIT THEN
    _COMP-FOCUS-SA @ ?DUP IF
        DUP _SL-STATE @ _ST-FOCUSED = IF
            _ST-RUNNING SWAP _SL-STATE !
        ELSE DROP THEN
    THEN
    _ST-FOCUSED OVER _SL-STATE !
    _COMP-FOCUS-SA !
    -1 _COMP-DIRTY ! ;

: COMP-MINIMIZE-ID  ( id -- )
    _COMP-FIND-ID DUP 0= IF DROP EXIT THEN
    DUP _SL-STATE @ _ST-MINIMIZED = IF DROP EXIT THEN
    _ST-MINIMIZED OVER _SL-STATE !
    DUP _COMP-LAST-MIN-SA !
    DUP _COMP-FOCUS-SA @ = IF
        0 _COMP-FOCUS-SA !
        _COMP-HEAD @
        BEGIN ?DUP WHILE
            DUP _SL-VISIBLE? IF
                DUP _COMP-FOCUS-SA !
                _ST-FOCUSED SWAP _SL-STATE !
                0
            ELSE
                _SL-NEXT @
            THEN
        REPEAT
    THEN
    DROP
    COMP-RELAYOUT ;

: COMP-RESTORE  ( -- )
    _COMP-LAST-MIN-SA @ DUP 0= IF DROP EXIT THEN
    DUP _SL-STATE @ _ST-MINIMIZED <> IF DROP EXIT THEN
    _ST-RUNNING OVER _SL-STATE !
    0 _COMP-LAST-MIN-SA !
    _COMP-FOCUS-SA @ 0= IF
        _ST-FOCUSED OVER _SL-STATE !
        DUP _COMP-FOCUS-SA !
    THEN
    DROP
    COMP-RELAYOUT ;

: COMP-FULLFRAME!  ( flag -- )
    _COMP-FULLFRAME !
    COMP-RELAYOUT ;

: COMP-TOGGLE-VH  ( -- )
    _COMP-VH @ 0= _COMP-VH !
    COMP-RELAYOUT ;

\ =====================================================================
\  §10 — Taskbar Painter
\ =====================================================================

CREATE _COMP-TB-BUF  256 ALLOT
VARIABLE _COMP-TB-POS

: _CTB-CH  ( ch -- )
    _COMP-TB-BUF _COMP-TB-POS @ + C!
    1 _COMP-TB-POS +! ;

: _CTB-STR  ( addr u -- )
    0 ?DO DUP I + C@ _CTB-CH LOOP DROP ;

: _CTB-DIGIT  ( n -- )
    DUP 10 < IF 48 + _CTB-CH EXIT THEN
    DUP 100 < IF
        DUP 10 / 48 + _CTB-CH
        10 MOD 48 + _CTB-CH EXIT
    THEN
    DUP 100 / 48 + _CTB-CH
    DUP 10 / 10 MOD 48 + _CTB-CH
    10 MOD 48 + _CTB-CH ;

: _COMP-PAINT-TASKBAR  ( -- )
    DRW-STYLE-SAVE
    255 17 0 DRW-STYLE!
    SCR-H 1-
    32 OVER 0 1 SCR-W DRW-FILL-RECT
    0 _COMP-TB-POS !
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        91 _CTB-CH
        DUP _SL-ID @ _CTB-DIGIT
        58 _CTB-CH
        DUP _SL-DESC @ ?DUP IF
            APP.TITLE-A @ ?DUP IF
                OVER _SL-DESC @ APP.TITLE-U @
                DUP 10 > IF DROP 10 THEN
                _CTB-STR
            ELSE
                S" App" _CTB-STR
            THEN
        ELSE
            S" App" _CTB-STR
        THEN
        DUP _SL-STATE @ _ST-FOCUSED = IF 42 _CTB-CH THEN
        DUP _SL-STATE @ _ST-MINIMIZED = IF 126 _CTB-CH THEN
        93 _CTB-CH
        32 _CTB-CH
        _SL-NEXT @
    REPEAT
    _COMP-TB-BUF _COMP-TB-POS @
    DUP SCR-W > IF DROP SCR-W THEN
    ROT 0 DRW-TEXT
    DRW-STYLE-RESTORE ;

\ =====================================================================
\  §11 — Paint All
\ =====================================================================

: COMP-PAINT-ALL  ( -- )
    _COMP-DIRTY @ 0= IF EXIT THEN
    0 _COMP-DIRTY !
    RGN-ROOT
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _COMP-FULLFRAME @ IF
                DUP _COMP-FOCUS-SA @ <>
            ELSE
                0
            THEN
            0= IF
                DUP _SL-RGN @ ?DUP IF
                    RGN-USE
                    OVER _SL-HAS-UIDL @ IF
                        OVER _COMP-CTX-SWITCH
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
    _COMP-FULLFRAME @ 0= IF _COMP-DRAW-DIVIDERS THEN
    _COMP-PAINT-TASKBAR
    RGN-ROOT
    SCR-FLUSH ;

\ =====================================================================
\  §12 — Key Routing & Shell Shortcuts
\ =====================================================================

CREATE _COMP-EV  24 ALLOT

: _COMP-EV-TYPE  ( ev -- type )  @ ;
: _COMP-EV-CODE  ( ev -- code )  8 + @ ;
: _COMP-EV-MODS  ( ev -- mods )  16 + @ ;

: _COMP-ALT?  ( ev ch -- flag )
    OVER _COMP-EV-MODS KEY-MOD-ALT AND IF
        SWAP _COMP-EV-CODE =
    ELSE
        2DROP 0
    THEN ;

: _COMP-CYCLE-FOCUS  ( -- )
    _COMP-FOCUS-SA @ 0= IF EXIT THEN
    _COMP-FOCUS-SA @ _SL-NEXT @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _SL-ID @ COMP-FOCUS-ID EXIT
        THEN
        _SL-NEXT @
    REPEAT
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            _SL-ID @ COMP-FOCUS-ID EXIT
        THEN
        _SL-NEXT @
    REPEAT ;

: COMP-SHORTCUT?  ( ev -- flag )
    DUP _COMP-EV-TYPE KEY-T-CHAR <> IF DROP 0 EXIT THEN
    DUP _COMP-EV-MODS KEY-MOD-ALT AND IF
        DUP _COMP-EV-CODE DUP 49 >= SWAP 57 <= AND IF
            DUP _COMP-EV-CODE 48 - COMP-FOCUS-ID
            DROP -1 EXIT
        THEN
    THEN
    DUP 9 _COMP-ALT? IF DROP _COMP-CYCLE-FOCUS -1 EXIT THEN
    DUP 109 _COMP-ALT? IF
        DROP _COMP-FOCUS-SA @ ?DUP IF
            _SL-ID @ COMP-MINIMIZE-ID
        THEN -1 EXIT THEN
    DUP 114 _COMP-ALT? IF DROP COMP-RESTORE -1 EXIT THEN
    DUP 102 _COMP-ALT? IF
        DROP _COMP-FULLFRAME @ 0= COMP-FULLFRAME!
        -1 EXIT THEN
    DUP 108 _COMP-ALT? IF DROP COMP-TOGGLE-VH -1 EXIT THEN
    DUP 119 _COMP-ALT? IF
        DROP _COMP-FOCUS-SA @ ?DUP IF
            _SL-ID @ COMP-CLOSE-ID
        THEN -1 EXIT THEN
    DROP 0 ;

: COMP-ROUTE-KEY  ( ev -- )
    _COMP-FOCUS-SA @ DUP 0= IF 2DROP EXIT THEN
    >R
    R@ _SL-HAS-UIDL @ IF
        R@ _COMP-CTX-SWITCH
        DUP UTUI-DISPATCH-KEY IF -1 _COMP-DIRTY ! THEN
    THEN
    R@ _SL-DESC @ ?DUP IF
        APP.EVENT-XT @ ?DUP IF
            SWAP EXECUTE
            IF -1 _COMP-DIRTY ! THEN
            R> DROP EXIT
        THEN
    THEN
    DROP R> DROP ;

\ =====================================================================
\  §13 — Tick All
\ =====================================================================

VARIABLE _COMP-TICK-TMP

: COMP-TICK-ALL  ( -- )
    MS@ _COMP-TICK-TMP !
    _COMP-TICK-TMP @ _COMP-LAST-TICK @ -
    _COMP-TICK-MS @ < IF EXIT THEN
    _COMP-TICK-TMP @ _COMP-LAST-TICK !
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-ALIVE? IF
            DUP _SL-DESC @ ?DUP IF
                APP.TICK-XT @ ?DUP IF EXECUTE THEN
            THEN
        THEN
        _SL-NEXT @
    REPEAT ;

\ =====================================================================
\  §14 — Resize Handling
\ =====================================================================

: _COMP-ON-RESIZE  ( w h -- )
    SCR-RESIZE
    COMP-RELAYOUT
    _COMP-HEAD @
    BEGIN ?DUP WHILE
        DUP _SL-VISIBLE? IF
            DUP _SL-HAS-UIDL @ IF
                DUP _COMP-CTX-SWITCH
                _UTUI-RGN @ IF UTUI-RELAYOUT THEN
            THEN
        THEN
        _SL-NEXT @
    REPEAT
    -1 _COMP-DIRTY ! ;

\ =====================================================================
\  §15 — Event Loop
\ =====================================================================

: COMP-QUIT  ( -- )  0 _COMP-RUNNING ! ;

: _COMP-LOOP  ( -- )
    -1 _COMP-RUNNING !
    MS@ _COMP-LAST-TICK !
    -1 _COMP-DIRTY !
    BEGIN
        _COMP-RUNNING @
    WHILE
        _COMP-EV KEY-POLL IF
            _COMP-EV _COMP-EV-TYPE KEY-T-RESIZE = IF
                _COMP-EV _COMP-EV-CODE
                _COMP-EV _COMP-EV-MODS
                _COMP-ON-RESIZE
            ELSE
                _COMP-EV COMP-SHORTCUT? 0= IF
                    _COMP-EV COMP-ROUTE-KEY
                THEN
            THEN
        THEN
        TERM-RESIZED? IF
            TERM-SIZE _COMP-ON-RESIZE
        THEN
        COMP-TICK-ALL
        COMP-PAINT-ALL
        YIELD?
    REPEAT ;

\ =====================================================================
\  §16 — Init & Run
\ =====================================================================

: COMP-INIT  ( -- )
    BEGIN _COMP-HEAD @ ?DUP WHILE
        DUP _SL-UCTX @ ?DUP IF UCTX-FREE THEN
        DUP _SL-RGN @ ?DUP IF RGN-FREE THEN
        DUP _SL-NEXT @
        SWAP FREE
        _COMP-HEAD !
    REPEAT
    0 _COMP-HEAD !
    0 _COMP-FOCUS-SA !
    1 _COMP-NEXT-ID !
    0 _COMP-VH !
    0 _COMP-FULLFRAME !
    0 _COMP-RUNNING !
    0 _COMP-DIRTY !
    50 _COMP-TICK-MS !
    0 _COMP-LAST-MIN-SA !
    0 _COMP-ACTIVE-CTX-SA ! ;

: COMP-RUN  ( -- )
    SCR-W SCR-H APP-INIT
    COMP-INIT
    1 KEY-TIMEOUT!
    ['] _COMP-LOOP CATCH
    BEGIN _COMP-HEAD @ ?DUP WHILE
        _SL-ID @ COMP-CLOSE-ID
    REPEAT
    APP-SHUTDOWN
    ?DUP IF THROW THEN ;

\ =====================================================================
\  §17 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _comp-guard

' COMP-INIT         CONSTANT _comp-init-xt
' COMP-LAUNCH       CONSTANT _comp-launch-xt
' COMP-CLOSE-ID     CONSTANT _comp-closeid-xt
' COMP-FOCUS-ID     CONSTANT _comp-focusid-xt
' COMP-MINIMIZE-ID  CONSTANT _comp-minimizeid-xt
' COMP-RESTORE      CONSTANT _comp-restore-xt
' COMP-FULLFRAME!   CONSTANT _comp-fullframe-xt
' COMP-TOGGLE-VH    CONSTANT _comp-togglevh-xt
' COMP-RELAYOUT     CONSTANT _comp-relayout-xt
' COMP-PAINT-ALL    CONSTANT _comp-paintall-xt
' COMP-ROUTE-KEY    CONSTANT _comp-routekey-xt
' COMP-SHORTCUT?    CONSTANT _comp-shortcut-xt
' COMP-TICK-ALL     CONSTANT _comp-tickall-xt
' COMP-RUN          CONSTANT _comp-run-xt
' COMP-QUIT         CONSTANT _comp-quit-xt

: COMP-INIT         _comp-init-xt         _comp-guard WITH-GUARD ;
: COMP-LAUNCH       _comp-launch-xt       _comp-guard WITH-GUARD ;
: COMP-CLOSE-ID     _comp-closeid-xt      _comp-guard WITH-GUARD ;
: COMP-FOCUS-ID     _comp-focusid-xt      _comp-guard WITH-GUARD ;
: COMP-MINIMIZE-ID  _comp-minimizeid-xt   _comp-guard WITH-GUARD ;
: COMP-RESTORE      _comp-restore-xt      _comp-guard WITH-GUARD ;
: COMP-FULLFRAME!   _comp-fullframe-xt    _comp-guard WITH-GUARD ;
: COMP-TOGGLE-VH    _comp-togglevh-xt     _comp-guard WITH-GUARD ;
: COMP-RELAYOUT     _comp-relayout-xt     _comp-guard WITH-GUARD ;
: COMP-PAINT-ALL    _comp-paintall-xt     _comp-guard WITH-GUARD ;
: COMP-ROUTE-KEY    _comp-routekey-xt     _comp-guard WITH-GUARD ;
: COMP-SHORTCUT?    _comp-shortcut-xt     _comp-guard WITH-GUARD ;
: COMP-TICK-ALL     _comp-tickall-xt      _comp-guard WITH-GUARD ;
: COMP-RUN          _comp-run-xt          _comp-guard WITH-GUARD ;
: COMP-QUIT         _comp-quit-xt         _comp-guard WITH-GUARD ;
[THEN] [THEN]
