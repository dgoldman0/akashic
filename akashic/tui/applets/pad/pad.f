\ =================================================================
\  pad.f -- IDE-class Text Editor Applet (UIDL)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PAD- / _PAD-
\  Depends on: akashic-tui-explorer, akashic-tui-textarea,
\              akashic-tui-input, akashic-tui-dialog,
\              akashic-tui-app-shell, akashic-tui-app-desc,
\              akashic-tui-uidl-tui, akashic-vfs, akashic-clipboard
\
\  UIDL-based IDE.  UI is declared in pad.uidl and loaded by
\  app-shell.f automatically.  The applet provides:
\    INIT-XT      -- "document ready": find elements, create widgets,
\                    mount explorer+panel, register actions
\    EVENT-XT     -- return 0 (all routing via UIDL + panel widget)
\    SHUTDOWN-XT  -- free all buffers, explorer, textarea
\    PAINT-XT     -- 0 (UTUI-PAINT handles everything)
\
\  Features:
\   - Multi-buffer editing (up to 16 open files)
\   - Dynamic tab bar (composite panel widget)
\   - File explorer sidebar (EXPL-* widget on <region id=sidebar>)
\   - Line numbers (gutter callback)
\   - Undo / redo per buffer (TXTA-BIND-UNDO / TXTA-BIND-GB)
\   - Clipboard (copy / cut / paste via clipboard.f)
\   - File I/O: new, open, save, save-as via VFS
\   - Toggle sidebar / output panels (split ratio manipulation)
\   - Find / go-to-line stubs
\   - TOML theme colours (10 regions)
\   - Status bar: filename+dirty, Ln/Col, encoding, tab count
\
\  Entry:  PAD-ENTRY ( desc -- )   for desk/app-loader launch
\          PAD-RUN   ( -- )        standalone execution
\ =================================================================

PROVIDED akashic-tui-pad

\ =====================================================================
\  S1 -- Dependencies
\ =====================================================================

REQUIRE ../../widgets/explorer.f
REQUIRE ../../widgets/textarea.f
REQUIRE ../../widgets/input.f
REQUIRE ../../widgets/dialog.f
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widget.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../utils/clipboard.f
REQUIRE ../../../utils/toml.f
REQUIRE ../../color.f
REQUIRE ../../../text/gap-buf.f
REQUIRE ../../../text/undo.f

\ =====================================================================
\  S2 -- Constants
\ =====================================================================

65536 CONSTANT _PAD-BUF-CAP       \ gap-buffer capacity per buffer
2097152 CONSTANT _PAD-ARENA-SIZE   \ 2 MiB XMEM arena for editor buffers
  256 CONSTANT _PAD-FNAME-CAP     \ filename capacity per slot
  128 CONSTANT _PAD-STATUS-CAP    \ status scratch
 4096 CONSTANT _PAD-IO-CAP        \ file I/O scratch
   16 CONSTANT _PAD-MAX-BUFS      \ max open buffers
    5 CONSTANT _PAD-GUTTER-W      \ gutter width (line numbers)
   64 CONSTANT _PAD-DUMMY-CAP     \ minimal buffer for TXTA-NEW

\ Buffer entry struct offsets (11 cells = 88 bytes)
 0 CONSTANT _PBE-FLAGS      \ 0=free, -1=in-use
 8 CONSTANT _PBE-GB         \ gap-buffer handle
16 CONSTANT _PBE-UNDO       \ undo handle
24 CONSTANT _PBE-FNAME-A    \ -> filename buffer (pre-allocated)
32 CONSTANT _PBE-FNAME-L    \ filename length
40 CONSTANT _PBE-DIRTY      \ per-buffer dirty flag
48 CONSTANT _PBE-CURSOR     \ saved cursor byte-offset
56 CONSTANT _PBE-SCROLL-Y   \ saved scroll-y
64 CONSTANT _PBE-SEL-ANC    \ saved selection anchor
72 CONSTANT _PBE-INODE      \ VFS inode (0 = untitled)
80 CONSTANT _PBE-RESERVED
88 CONSTANT _PAD-BUF-ENTRY-SIZE

\ Textarea internal field offsets (from textarea.f)
\ Used for save/restore of cursor state during buffer switches.
64 CONSTANT _PTO-CURSOR
72 CONSTANT _PTO-SCROLL-Y
88 CONSTANT _PTO-SEL-ANC
96 CONSTANT _PTO-GB
104 CONSTANT _PTO-UNDO

\ =====================================================================
\  S3 -- UIDL File Path
\ =====================================================================
\
\  The UI layout lives in pad.uidl alongside this file on the VFS.
\  PAD-ENTRY sets APP.UIDL-FILE-A/U in the descriptor.
\
\  Layout (see pad.uidl):
\    uidl (stack)
\      menubar#mbar
\      split#main-split (ratio=20)
\        scroll#sidebar-scroll > region#sidebar       (EXPL widget)
\        split#eo-split (ratio=80)
\          region#editor-area                          (panel widget)
\          scroll#output-scroll > textarea#output
\      status#sbar > label * 4

\ =====================================================================
\  S4 -- Module State
\ =====================================================================

\ ---- UIDL element handles ----
VARIABLE _PAD-E-MBAR
VARIABLE _PAD-E-MAIN-SPLIT
VARIABLE _PAD-E-SIDEBAR-SCROLL
VARIABLE _PAD-E-SIDEBAR
VARIABLE _PAD-E-EO-SPLIT
VARIABLE _PAD-E-EDITOR-AREA
VARIABLE _PAD-E-OUTPUT-SCROLL
VARIABLE _PAD-E-OUTPUT
VARIABLE _PAD-E-SBAR
VARIABLE _PAD-E-SBAR-FILE
VARIABLE _PAD-E-SBAR-POS
VARIABLE _PAD-E-SBAR-ENC
VARIABLE _PAD-E-SBAR-TABS

\ ---- Widget handles ----
VARIABLE _PAD-EXPL          \ explorer widget (sidebar)
VARIABLE _PAD-TXTA          \ THE single shared textarea
VARIABLE _PAD-OUT-TXTA      \ output textarea (auto-materialized)

\ ---- Buffer table ----
CREATE _PAD-BUFS  _PAD-MAX-BUFS _PAD-BUF-ENTRY-SIZE * ALLOT
CREATE _PAD-FNAMES _PAD-MAX-BUFS _PAD-FNAME-CAP * ALLOT

VARIABLE _PAD-ACTIVE        \ index of active buffer (-1 = none)
VARIABLE _PAD-BUF-CNT       \ number of open buffers
VARIABLE _PAD-ARENA          \ XMEM arena for gap-buffer memory

\ ---- Composite panel widget (mounted on editor-area) ----
CREATE _PAD-PANEL  40 ALLOT

\ ---- Textarea allocation buffer (GB is always bound, so minimal) ----
CREATE _PAD-DUMMY-BUF  _PAD-DUMMY-CAP ALLOT

\ ---- File I/O scratch ----
CREATE _PAD-IO-BUF  _PAD-IO-CAP ALLOT

\ ---- VFS ----
VARIABLE _PAD-VFS

\ ---- Toggle state ----
VARIABLE _PAD-SIDEBAR-VIS
VARIABLE _PAD-OUTPUT-VIS
VARIABLE _PAD-SHOW-HIDDEN

\ ---- Status bar scratch ----
CREATE _PAD-STXT  _PAD-STATUS-CAP ALLOT
VARIABLE _PAD-STXT-L

\ ---- Path scratch for inode-to-path ----
CREATE _PAD-PATH-BUF  512 ALLOT

\ =====================================================================
\  S4b -- Theme
\ =====================================================================

VARIABLE _PTH-EDITOR-FG  VARIABLE _PTH-EDITOR-BG
VARIABLE _PTH-MENU-FG    VARIABLE _PTH-MENU-BG
VARIABLE _PTH-STATUS-FG  VARIABLE _PTH-STATUS-BG
VARIABLE _PTH-SCROLL-FG  VARIABLE _PTH-SCROLL-BG
VARIABLE _PTH-SIDEBAR-FG VARIABLE _PTH-SIDEBAR-BG
VARIABLE _PTH-TABS-FG    VARIABLE _PTH-TABS-BG
VARIABLE _PTH-OUTPUT-FG  VARIABLE _PTH-OUTPUT-BG
VARIABLE _PTH-ATAB-FG    VARIABLE _PTH-ATAB-BG
VARIABLE _PTH-GUTTER-FG  VARIABLE _PTH-GUTTER-BG

: _PAD-THEME-DEFAULTS  ( -- )
    253 _PTH-EDITOR-FG !   234 _PTH-EDITOR-BG !
    255 _PTH-MENU-FG   !    60 _PTH-MENU-BG   !
     15 _PTH-STATUS-FG !    24 _PTH-STATUS-BG !
     68 _PTH-SCROLL-FG !   234 _PTH-SCROLL-BG !
    251 _PTH-SIDEBAR-FG !  236 _PTH-SIDEBAR-BG !
    255 _PTH-TABS-FG    !   60 _PTH-TABS-BG    !
    248 _PTH-OUTPUT-FG  !  233 _PTH-OUTPUT-BG  !
    255 _PTH-ATAB-FG    !  234 _PTH-ATAB-BG    !
    243 _PTH-GUTTER-FG  !  235 _PTH-GUTTER-BG  ! ;
_PAD-THEME-DEFAULTS

: _PTH-TRY  ( tbl-a tbl-l key-a key-l var -- )
    >R TOML-KEY?
    IF   TOML-GET-INT R> !
    ELSE 2DROP R> DROP
    THEN ;

: _PAD-LOAD-THEME  ( toml-a toml-l -- )
    S" pad.theme" TOML-FIND-TABLE?
    0= IF 2DROP EXIT THEN
    2DUP S" editor-fg"     _PTH-EDITOR-FG   _PTH-TRY
    2DUP S" editor-bg"     _PTH-EDITOR-BG   _PTH-TRY
    2DUP S" menubar-fg"    _PTH-MENU-FG     _PTH-TRY
    2DUP S" menubar-bg"    _PTH-MENU-BG     _PTH-TRY
    2DUP S" status-fg"     _PTH-STATUS-FG   _PTH-TRY
    2DUP S" status-bg"     _PTH-STATUS-BG   _PTH-TRY
    2DUP S" scroll-fg"     _PTH-SCROLL-FG   _PTH-TRY
    2DUP S" scroll-bg"     _PTH-SCROLL-BG   _PTH-TRY
    2DUP S" sidebar-fg"    _PTH-SIDEBAR-FG  _PTH-TRY
    2DUP S" sidebar-bg"    _PTH-SIDEBAR-BG  _PTH-TRY
    2DUP S" tabs-fg"       _PTH-TABS-FG     _PTH-TRY
    2DUP S" tabs-bg"       _PTH-TABS-BG     _PTH-TRY
    2DUP S" output-fg"     _PTH-OUTPUT-FG   _PTH-TRY
    2DUP S" output-bg"     _PTH-OUTPUT-BG   _PTH-TRY
    2DUP S" active-tab-fg" _PTH-ATAB-FG     _PTH-TRY
    2DUP S" active-tab-bg" _PTH-ATAB-BG     _PTH-TRY
    2DUP S" gutter-fg"     _PTH-GUTTER-FG   _PTH-TRY
         S" gutter-bg"     _PTH-GUTTER-BG   _PTH-TRY ;

VARIABLE _PAD-CFG-A  VARIABLE _PAD-CFG-L
0 _PAD-CFG-A !  0 _PAD-CFG-L !
4096 CONSTANT _PAD-CFG-CAP
CREATE _PAD-CFG-BUF  _PAD-CFG-CAP ALLOT
VARIABLE _PAD-CFG-FD

: _PAD-LOAD-CONFIG  ( -- )
    VFS-CUR >R  _PAD-VFS @ VFS-USE
    S" tui/applets/pad/pad.toml" VFS-OPEN
    R> VFS-USE
    DUP 0= IF DROP EXIT THEN
    _PAD-CFG-FD !
    _PAD-CFG-BUF _PAD-CFG-CAP _PAD-CFG-FD @ VFS-READ
    DUP 0= IF DROP _PAD-CFG-FD @ VFS-CLOSE EXIT THEN
    _PAD-CFG-BUF SWAP 2DUP _PAD-CFG-L ! _PAD-CFG-A !
    _PAD-LOAD-THEME
    _PAD-CFG-FD @ VFS-CLOSE ;

: _PAD-THEME-ELEM  ( fg bg elem -- )
    _UTUI-SIDECAR >R
    0 _UTUI-PACK-STYLE R> _UTUI-SC-STYLE! ;

: _PAD-APPLY-THEME  ( -- )
    _PTH-MENU-FG    @ _PTH-MENU-BG    @ _PAD-E-MBAR           @ _PAD-THEME-ELEM
    _PTH-STATUS-FG  @ _PTH-STATUS-BG  @ _PAD-E-SBAR            @ _PAD-THEME-ELEM
    _PTH-SCROLL-FG  @ _PTH-SCROLL-BG  @ _PAD-E-SIDEBAR-SCROLL  @ _PAD-THEME-ELEM
    _PTH-SIDEBAR-FG @ _PTH-SIDEBAR-BG @ _PAD-E-SIDEBAR         @ _PAD-THEME-ELEM
    _PTH-SCROLL-FG  @ _PTH-SCROLL-BG  @ _PAD-E-OUTPUT-SCROLL   @ _PAD-THEME-ELEM
    _PTH-OUTPUT-FG  @ _PTH-OUTPUT-BG  @ _PAD-E-OUTPUT           @ _PAD-THEME-ELEM
    _PTH-EDITOR-FG  @ _PTH-EDITOR-BG  @ _PAD-E-EDITOR-AREA     @ _PAD-THEME-ELEM ;

\ =====================================================================
\  S5 -- Buffer Table Helpers
\ =====================================================================

: _PAD-BUF-ENTRY  ( index -- addr )
    _PAD-BUF-ENTRY-SIZE * _PAD-BUFS + ;

: _PAD-BUF-FNAME  ( index -- c-addr )
    _PAD-FNAME-CAP * _PAD-FNAMES + ;

: _PAD-INIT-BUF-TABLE  ( -- )
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY _PAD-BUF-ENTRY-SIZE 0 FILL
        I _PAD-BUF-FNAME I _PAD-BUF-ENTRY _PBE-FNAME-A + !
    LOOP
    -1 _PAD-ACTIVE !
    0 _PAD-BUF-CNT ! ;

: _PAD-ALLOC-SLOT  ( -- index | -1 )
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY _PBE-FLAGS + @ 0= IF
            I UNLOOP EXIT
        THEN
    LOOP -1 ;

\ Label for buffer tab: basename or "Untitled", with dirty indicator
: _PAD-BUF-LABEL  ( index -- c-addr u )
    _PAD-BUF-ENTRY DUP _PBE-FNAME-L + @
    DUP 0= IF
        2DROP S" Untitled"
    ELSE
        SWAP _PBE-FNAME-A + @ SWAP
    THEN ;

\ =====================================================================
\  S6 -- Composite Panel Widget
\ =====================================================================
\
\  Mounted on <region id=editor-area> via UTUI-WIDGET-SET.
\  Rows 0-1:  tab bar header + underline
\  Rows 2+:   textarea content (one shared textarea, buffer-swapped)
\
\  Draw: renders tab labels then delegates to WDG-DRAW for the txta.
\  Handle: syncs focus flag to textarea, forwards events.

VARIABLE _PDT-COL  \ column accumulator during tab draw

: _PAD-DRAW-TABS  ( -- )
    _PAD-PANEL 8 + @ RGN-W          ( panel-w )
    \ Set default tab colours
    _PTH-TABS-FG @ DRW-FG!  _PTH-TABS-BG @ DRW-BG!
    \ Clear header row 0
    32 0 0  3 PICK  DRW-HLINE
    0 _PDT-COL !
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
            \ Pick colours (active vs inactive)
            I _PAD-ACTIVE @ = IF
                _PTH-ATAB-FG @ DRW-FG!  _PTH-ATAB-BG @ DRW-BG!
            ELSE
                _PTH-TABS-FG @ DRW-FG!  _PTH-TABS-BG @ DRW-BG!
            THEN
            \ Draw leading space
            32  0  _PDT-COL @  DRW-CHAR
            \ Draw label
            I _PAD-BUF-LABEL                  ( c-addr u )
            0  _PDT-COL @ 1+  DRW-TEXT
            \ Draw dirty indicator
            I _PAD-BUF-ENTRY _PBE-DIRTY + @ IF
                [CHAR] * 0 _PDT-COL @ 1+ I _PAD-BUF-LABEL NIP + DRW-CHAR
                I _PAD-BUF-LABEL NIP 1+ 2 + _PDT-COL +!
            ELSE
                I _PAD-BUF-LABEL NIP 2 + _PDT-COL +!
            THEN
            0 DRW-ATTR!
        THEN
    LOOP
    \ Underline row 1
    _PTH-TABS-FG @ DRW-FG!  _PTH-TABS-BG @ DRW-BG!
    9472  1  0  3 PICK  DRW-HLINE
    0 DRW-ATTR!
    DROP ;

\ Sync textarea sub-region from panel region (call before drawing)
: _PAD-SYNC-TXTA-RGN  ( panel-widget -- )
    8 + @                              ( panel-rgn )
    _PAD-TXTA @ ?DUP 0= IF DROP EXIT THEN
    8 + @                              ( panel-rgn txta-rgn )
    OVER RGN-ROW 2 + OVER  0 + !
    OVER RGN-COL     OVER  8 + !
    OVER RGN-H 2 -   0 MAX OVER 16 + !
    SWAP RGN-W        SWAP 24 + ! ;

: _PAD-PANEL-DRAW  ( widget -- )
    DUP _PAD-SYNC-TXTA-RGN
    DROP
    _PAD-DRAW-TABS
    _PAD-TXTA @ ?DUP IF WDG-DRAW THEN ;

: _PAD-PANEL-HANDLE  ( event widget -- consumed? )
    DUP 32 + @ 2 AND          ( event widget focused? )
    IF
        _PAD-TXTA @ ?DUP IF
            DUP 32 + @ 2 OR SWAP 32 + !
        THEN
    THEN
    DROP
    _PAD-TXTA @ ?DUP IF
        WDG-HANDLE
    ELSE DROP 0 THEN ;

: _PAD-PANEL-INIT  ( rgn -- )
    _PAD-PANEL
    20 OVER  0 + !                     \ type = 20 (custom)
    SWAP OVER  8 + !                   \ region
    ['] _PAD-PANEL-DRAW  OVER 16 + !  \ draw-xt
    ['] _PAD-PANEL-HANDLE OVER 24 + ! \ handle-xt
    1 4 OR  SWAP 32 + ! ;             \ flags = VISIBLE | DIRTY

\ =====================================================================
\  S7 -- Gutter (Line Numbers)
\ =====================================================================
\
\  Callback signature: ( line# row gutter-width widget -- )
\  Called by textarea for each visible row.  Draws right-aligned
\  1-based line number in gutter colours.

: _PAD-GUTTER-DRAW  ( line# row gutter-width widget -- )
    DROP                               ( line# row gw )
    >R                                 ( line# row    R: gw )
    _PTH-GUTTER-FG @ DRW-FG!
    _PTH-GUTTER-BG @ DRW-BG!
    SWAP 1+  NUM>STR                   ( row addr len )
    ROT  0  R>  DRW-TEXT-RIGHT
    0 DRW-ATTR! ;

\ =====================================================================
\  S8 -- Status Bar Update
\ =====================================================================

: _PAD-UPDATE-STATUS  ( -- )
    \ ---- sbar-file: filename + dirty ----
    _PAD-ACTIVE @ 0< IF
        _PAD-E-SBAR-FILE @ ?DUP IF
            S" text" S" Ready" UTUI-SET-ATTR
        THEN
    ELSE
        \ Build label in scratch: "filename" or "filename *"
        _PAD-ACTIVE @ _PAD-BUF-LABEL          ( fa fu )
        _PAD-STXT SWAP DUP >R CMOVE           ( -- , R: fu )
        _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ IF
            S"  *" _PAD-STXT R@ + SWAP CMOVE
            R> 2 + _PAD-STXT-L !
        ELSE
            R> _PAD-STXT-L !
        THEN
        _PAD-E-SBAR-FILE @ ?DUP IF
            S" text" _PAD-STXT _PAD-STXT-L @ UTUI-SET-ATTR
        THEN
    THEN
    \ ---- sbar-pos: Ln N, Col M ----
    _PAD-TXTA @ ?DUP IF
        DUP TXTA-CURSOR-LINE 1+            ( w line1 )
        SWAP TXTA-CURSOR-COL 1+            ( line1 col1 )
        \ Build "Ln N, Col M" in _PAD-STXT
        SWAP NUM>STR                        ( col1 ln-a ln-u )
        S" Ln " _PAD-STXT SWAP CMOVE       ( col1 ln-a ln-u )
        _PAD-STXT 3 + SWAP DUP >R CMOVE    ( col1   R: ln-u )
        R> 3 +                              ( col1 off )
        S" , Col " _PAD-STXT 3 PICK + SWAP CMOVE
        6 +                                 ( col1 off' )
        SWAP NUM>STR                        ( off' col-a col-u )
        _PAD-STXT 3 PICK + SWAP DUP >R CMOVE
        R> +                                ( off'' )
        _PAD-E-SBAR-POS @ ?DUP IF
            S" text" _PAD-STXT 4 PICK UTUI-SET-ATTR
        THEN
        DROP
    THEN
    \ ---- sbar-tabs: N tabs ----
    _PAD-BUF-CNT @ NUM>STR                  ( addr len )
    _PAD-STXT SWAP DUP >R CMOVE
    S"  tabs" _PAD-STXT R@ + SWAP CMOVE
    R> 5 +                                   ( total-len )
    _PAD-E-SBAR-TABS @ ?DUP IF
        S" text" _PAD-STXT 4 PICK UTUI-SET-ATTR
    THEN
    DROP ;

\ =====================================================================
\  S9 -- Change Callback
\ =====================================================================

: _PAD-ON-CHANGE  ( widget -- )
    DROP
    _PAD-ACTIVE @ 0< IF EXIT THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0= IF
        -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    THEN
    _PAD-UPDATE-STATUS
    ASHELL-DIRTY! ;

\ =====================================================================
\  S10 -- Buffer Management
\ =====================================================================

\ Save textarea state into the currently active buffer slot.
: _PAD-SAVE-STATE  ( -- )
    _PAD-ACTIVE @ 0< IF EXIT THEN
    _PAD-TXTA @ ?DUP 0= IF EXIT THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY >R
    DUP _PTO-CURSOR + @   R@ _PBE-CURSOR + !
    DUP _PTO-SCROLL-Y + @ R@ _PBE-SCROLL-Y + !
        _PTO-SEL-ANC + @  R> _PBE-SEL-ANC + ! ;

\ Restore textarea state from a buffer slot.
: _PAD-RESTORE-STATE  ( index -- )
    _PAD-BUF-ENTRY >R
    _PAD-TXTA @ ?DUP 0= IF R> DROP EXIT THEN
    R@ _PBE-CURSOR + @   OVER _PTO-CURSOR + !
    R@ _PBE-SCROLL-Y + @ OVER _PTO-SCROLL-Y + !
    R> _PBE-SEL-ANC + @  SWAP _PTO-SEL-ANC + ! ;

\ Unbind GB + undo from the textarea.
: _PAD-UNBIND  ( -- )
    _PAD-TXTA @ ?DUP IF
        DUP TXTA-UNBIND-UNDO
            TXTA-UNBIND-GB
    THEN ;

\ Bind a buffer slot's GB + undo to the textarea.
: _PAD-BIND  ( index -- )
    _PAD-BUF-ENTRY >R
    R@ _PBE-GB + @   _PAD-TXTA @ TXTA-BIND-GB
    R> _PBE-UNDO + @ _PAD-TXTA @ TXTA-BIND-UNDO ;

\ Open a new buffer.  Returns the buffer index or -1 on failure.
: _PAD-BUF-OPEN  ( -- index | -1 )
    _PAD-ALLOC-SLOT DUP 0< IF EXIT THEN
    >R
    \ Allocate gap-buffer and undo state
    _PAD-BUF-CAP _PAD-ARENA @ GB-NEW   R@ _PAD-BUF-ENTRY _PBE-GB + !
    UNDO-NEW               R@ _PAD-BUF-ENTRY _PBE-UNDO + !
    -1                     R@ _PAD-BUF-ENTRY _PBE-FLAGS + !
    0                      R@ _PAD-BUF-ENTRY _PBE-FNAME-L + !
    0                      R@ _PAD-BUF-ENTRY _PBE-DIRTY + !
    0                      R@ _PAD-BUF-ENTRY _PBE-CURSOR + !
    0                      R@ _PAD-BUF-ENTRY _PBE-SCROLL-Y + !
    -1                     R@ _PAD-BUF-ENTRY _PBE-SEL-ANC + !
    0                      R@ _PAD-BUF-ENTRY _PBE-INODE + !
    1 _PAD-BUF-CNT +!
    \ Switch to the new buffer
    _PAD-SAVE-STATE
    _PAD-UNBIND
    R@ _PAD-ACTIVE !
    R@ _PAD-BIND
    R@ _PAD-RESTORE-STATE
    _PAD-TXTA @ WDG-DIRTY
    _PAD-UPDATE-STATUS
    ASHELL-DIRTY!
    R> ;

\ Close the buffer at index.  Does NOT check for dirty.
: _PAD-BUF-CLOSE  ( index -- )
    DUP _PAD-BUF-ENTRY >R
    \ If this is the active buffer, unbind first
    DUP _PAD-ACTIVE @ = IF
        _PAD-UNBIND
    THEN
    \ Free GB and undo
    R@ _PBE-GB + @ ?DUP IF GB-FREE THEN
    R@ _PBE-UNDO + @ ?DUP IF UNDO-FREE THEN
    \ Mark slot free
    R> _PAD-BUF-ENTRY-SIZE 0 FILL
    DUP _PAD-BUF-FNAME OVER _PAD-BUF-ENTRY _PBE-FNAME-A + !
    -1 _PAD-BUF-CNT +!
    \ If we closed the active buffer, switch to another
    _PAD-ACTIVE @ = IF
        -1 _PAD-ACTIVE !
        \ Find next active slot
        _PAD-MAX-BUFS 0 DO
            I _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
                I _PAD-ACTIVE !
                I _PAD-BIND
                I _PAD-RESTORE-STATE
                LEAVE
            THEN
        LOOP
    THEN
    _PAD-TXTA @ ?DUP IF WDG-DIRTY THEN
    _PAD-UPDATE-STATUS
    ASHELL-DIRTY! ;

\ Switch to buffer at index.
: _PAD-BUF-SWITCH  ( index -- )
    DUP _PAD-ACTIVE @ = IF DROP EXIT THEN
    DUP _PAD-BUF-ENTRY _PBE-FLAGS + @ 0= IF DROP EXIT THEN
    _PAD-SAVE-STATE
    _PAD-UNBIND
    DUP _PAD-ACTIVE !
    DUP _PAD-BIND
    _PAD-RESTORE-STATE
    _PAD-TXTA @ ?DUP IF WDG-DIRTY THEN
    _PAD-UPDATE-STATUS
    ASHELL-DIRTY! ;

\ =====================================================================
\  S11 -- File I/O Helpers
\ =====================================================================

VARIABLE _PIO-FD

: _PAD-DO-SAVE-TO  ( fname-a fname-u -- ior )
    VFS-CUR >R  _PAD-VFS @ VFS-USE
    2DUP VFS-OPEN
    DUP 0= IF
        DROP
        2DUP _PAD-VFS @ VFS-MKFILE
        DUP 0= IF 2DROP R> VFS-USE -1 EXIT THEN
        DROP
        2DUP VFS-OPEN
        DUP 0= IF 2DROP R> VFS-USE -1 EXIT THEN
    THEN
    R> VFS-USE
    >R 2DROP R>
    DUP VFS-REWIND
    _PAD-TXTA @ TXTA-GET-TEXT
    ROT DUP >R VFS-WRITE DROP
    R> DUP VFS-REWIND VFS-CLOSE
    0 ;

\ Open a file from path into the active buffer.
: _PAD-LOAD-FILE  ( fname-a fname-u -- )
    VFS-CUR >R  _PAD-VFS @ VFS-USE
    2DUP VFS-OPEN
    R> VFS-USE
    DUP 0= IF
        2DROP DROP
        S" File not found" 2000 ASHELL-TOAST EXIT
    THEN
    _PIO-FD !
    \ Store filename in active buffer
    _PAD-ACTIVE @ 0< IF 2DROP _PIO-FD @ VFS-CLOSE EXIT THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY >R
    DUP _PAD-FNAME-CAP MIN               ( fa fu u' )
    DUP R@ _PBE-FNAME-L + !             ( fa fu u' )
    NIP                                   ( fa u' )
    R> _PBE-FNAME-A + @ SWAP CMOVE       ( )
    \ Read file content
    _PAD-IO-BUF _PAD-IO-CAP _PIO-FD @ VFS-READ
    DUP 0<> IF
        _PAD-IO-BUF SWAP
        _PAD-TXTA @ TXTA-SET-TEXT
    ELSE
        DROP _PAD-TXTA @ TXTA-CLEAR
    THEN
    _PIO-FD @ VFS-CLOSE
    0 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    _PAD-UPDATE-STATUS
    ASHELL-DIRTY! ;

\ =====================================================================
\  S12 -- Explorer Callback
\ =====================================================================

: _PAD-ON-EXPL-OPEN  ( inode explorer -- )
    DROP
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP EXIT THEN
    \ Build full path from inode
    DUP _PAD-PATH-BUF 512 VFS-INODE-PATH   ( inode len )
    SWAP DROP                                ( len )
    DUP 0= IF DROP EXIT THEN
    \ Open a new buffer tab
    _PAD-BUF-OPEN DUP 0< IF
        DROP DROP S" Max buffers reached" 2000 ASHELL-TOAST EXIT
    THEN
    DROP
    \ Load the file
    _PAD-PATH-BUF SWAP _PAD-LOAD-FILE ;

\ =====================================================================
\  S13 -- Actions: File Menu
\ =====================================================================

: _PAD-DO-NEW  ( elem -- )
    DROP
    _PAD-BUF-OPEN DUP 0< IF
        DROP S" Max buffers reached" 2000 ASHELL-TOAST EXIT
    THEN DROP
    _PAD-TXTA @ ?DUP IF TXTA-CLEAR THEN
    _PAD-UPDATE-STATUS ASHELL-DIRTY! ;

: _PAD-DO-OPEN  ( elem -- )
    DROP
    S" Open: (use explorer)" 2000 ASHELL-TOAST ;

: _PAD-DO-SAVE  ( elem -- )
    DROP
    _PAD-ACTIVE @ 0< IF EXIT THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-FNAME-L + @ 0= IF
        S" Save As: not yet implemented" 2000 ASHELL-TOAST EXIT
    THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY DUP _PBE-FNAME-A + @ SWAP _PBE-FNAME-L + @
    _PAD-DO-SAVE-TO
    IF S" Save failed" 2000 ASHELL-TOAST EXIT THEN
    0 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    S" Saved" 1500 ASHELL-TOAST
    _PAD-UPDATE-STATUS ASHELL-DIRTY! ;

: _PAD-DO-SAVE-AS  ( elem -- )
    DROP
    S" Save As: not yet implemented" 2000 ASHELL-TOAST ;

: _PAD-DO-SAVE-ALL  ( elem -- )
    DROP
    S" Save All: not yet implemented" 2000 ASHELL-TOAST ;

: _PAD-DO-CLOSE-TAB  ( elem -- )
    DROP
    _PAD-ACTIVE @ 0< IF EXIT THEN
    _PAD-ACTIVE @ _PAD-BUF-CLOSE ;

: _PAD-DO-CLOSE-ALL  ( elem -- )
    DROP
    BEGIN _PAD-BUF-CNT @ 0> WHILE
        _PAD-ACTIVE @ 0< IF
            _PAD-MAX-BUFS 0 DO
                I _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
                    I _PAD-ACTIVE ! LEAVE
                THEN
            LOOP
        THEN
        _PAD-ACTIVE @ 0< IF EXIT THEN
        _PAD-ACTIVE @ _PAD-BUF-CLOSE
    REPEAT ;

: _PAD-DO-QUIT  ( elem -- )
    DROP ASHELL-QUIT ;

\ =====================================================================
\  S14 -- Actions: Clipboard
\ =====================================================================

: _PAD-DO-COPY  ( elem -- )
    DROP
    _PAD-TXTA @ DUP 0= IF DROP EXIT THEN
    TXTA-GET-SEL
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP
    S" Copied" 1000 ASHELL-TOAST ;

: _PAD-DO-CUT  ( elem -- )
    DROP
    _PAD-TXTA @ DUP 0= IF DROP EXIT THEN
    DUP TXTA-GET-SEL
    DUP 0= IF 2DROP DROP EXIT THEN
    CLIP-COPY DROP
    TXTA-DEL-SEL DROP
    ASHELL-DIRTY! ;

: _PAD-DO-PASTE  ( elem -- )
    DROP
    CLIP-PASTE
    DUP 0= IF 2DROP EXIT THEN
    _PAD-TXTA @ DUP 0= IF DROP 2DROP EXIT THEN
    TXTA-INS-STR
    ASHELL-DIRTY! ;

: _PAD-DO-SELECT-ALL  ( elem -- )
    DROP
    _PAD-TXTA @ ?DUP IF TXTA-SELECT-ALL THEN
    ASHELL-DIRTY! ;

: _PAD-DO-DELETE-LINE  ( elem -- )
    DROP
    S" Delete line: not yet implemented" 2000 ASHELL-TOAST ;

\ =====================================================================
\  S15 -- Actions: Undo / Redo
\ =====================================================================
\
\  When invoked from the menu, we call the textarea's internal undo
\  mechanism via its private fields.  Ctrl+Z/Y is handled directly
\  by the textarea's key handler (which fires on-change).

: _PAD-DO-UNDO  ( elem -- )
    DROP
    _PAD-TXTA @ ?DUP 0= IF EXIT THEN
    DUP _PTO-UNDO + @ ?DUP 0= IF DROP EXIT THEN
    OVER _PTO-GB + @ SWAP UNDO-UNDO IF
        DUP _PTO-GB + @ GB-CURSOR OVER _PTO-CURSOR + !
        WDG-DIRTY
    ELSE DROP THEN
    ASHELL-DIRTY! ;

: _PAD-DO-REDO  ( elem -- )
    DROP
    _PAD-TXTA @ ?DUP 0= IF EXIT THEN
    DUP _PTO-UNDO + @ ?DUP 0= IF DROP EXIT THEN
    OVER _PTO-GB + @ SWAP UNDO-REDO IF
        DUP _PTO-GB + @ GB-CURSOR OVER _PTO-CURSOR + !
        WDG-DIRTY
    ELSE DROP THEN
    ASHELL-DIRTY! ;

\ =====================================================================
\  S16 -- Actions: Find / Replace / Goto (stubs)
\ =====================================================================

: _PAD-DO-FIND  ( elem -- )
    DROP S" Find: not yet implemented" 2000 ASHELL-TOAST ;

: _PAD-DO-REPLACE  ( elem -- )
    DROP S" Replace: not yet implemented" 2000 ASHELL-TOAST ;

: _PAD-DO-GOTO-LINE  ( elem -- )
    DROP S" Go to line: not yet implemented" 2000 ASHELL-TOAST ;

: _PAD-DO-GOTO-FILE  ( elem -- )
    DROP S" Go to file: not yet implemented" 2000 ASHELL-TOAST ;

\ =====================================================================
\  S17 -- Actions: Toggle Sidebar / Output
\ =====================================================================

: _PAD-DO-TOGGLE-SIDEBAR  ( elem -- )
    DROP
    _PAD-SIDEBAR-VIS @ IF
        0 _PAD-SIDEBAR-VIS !
        _PAD-E-MAIN-SPLIT @ S" ratio" S" 0" UTUI-SET-ATTR
    ELSE
        -1 _PAD-SIDEBAR-VIS !
        _PAD-E-MAIN-SPLIT @ S" ratio" S" 20" UTUI-SET-ATTR
    THEN
    ASHELL-DIRTY! ;

: _PAD-DO-TOGGLE-OUTPUT  ( elem -- )
    DROP
    _PAD-OUTPUT-VIS @ IF
        0 _PAD-OUTPUT-VIS !
        _PAD-E-EO-SPLIT @ S" ratio" S" 100" UTUI-SET-ATTR
    ELSE
        -1 _PAD-OUTPUT-VIS !
        _PAD-E-EO-SPLIT @ S" ratio" S" 80" UTUI-SET-ATTR
    THEN
    ASHELL-DIRTY! ;

: _PAD-DO-TOGGLE-HIDDEN  ( elem -- )
    DROP
    _PAD-SHOW-HIDDEN @ INVERT _PAD-SHOW-HIDDEN !
    _PAD-EXPL @ ?DUP IF
        _PAD-SHOW-HIDDEN @ SWAP EXPL-SHOW-HIDDEN!
        _PAD-EXPL @ EXPL-REFRESH
    THEN
    ASHELL-DIRTY! ;

\ =====================================================================
\  S18 -- Actions: Tab Navigation
\ =====================================================================

\ Find the next active slot after current (wrapping).
: _PAD-NEXT-ACTIVE  ( -- index | -1 )
    _PAD-ACTIVE @ 1+
    _PAD-MAX-BUFS 0 DO
        DUP _PAD-MAX-BUFS MOD
        DUP _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
            NIP UNLOOP EXIT
        THEN DROP
        1+
    LOOP
    DROP -1 ;

\ Find the previous active slot before current (wrapping).
: _PAD-PREV-ACTIVE  ( -- index | -1 )
    _PAD-ACTIVE @ _PAD-MAX-BUFS + 1-
    _PAD-MAX-BUFS 0 DO
        DUP _PAD-MAX-BUFS MOD
        DUP _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
            NIP UNLOOP EXIT
        THEN DROP
        1-
    LOOP
    DROP -1 ;

: _PAD-DO-NEXT-TAB  ( elem -- )
    DROP
    _PAD-NEXT-ACTIVE DUP 0< IF DROP EXIT THEN
    _PAD-BUF-SWITCH ;

: _PAD-DO-PREV-TAB  ( elem -- )
    DROP
    _PAD-PREV-ACTIVE DUP 0< IF DROP EXIT THEN
    _PAD-BUF-SWITCH ;

\ =====================================================================
\  S19 -- Actions: Misc
\ =====================================================================

: _PAD-DO-ABOUT  ( elem -- )
    DROP
    S" Akashic Pad -- IDE-class editor" 3000 ASHELL-TOAST ;

: _PAD-DO-SHORTCUTS  ( elem -- )
    DROP
    S" Ctrl+N/O/S/W  Ctrl+Z/Y  Ctrl+C/X/V  Ctrl+B/J  Ctrl+F/G" 4000 ASHELL-TOAST ;

: _PAD-DO-SELECT-WORD  ( elem -- )
    DROP S" Select word: not yet implemented" 2000 ASHELL-TOAST ;

: _PAD-DO-SELECT-LINE  ( elem -- )
    DROP S" Select line: not yet implemented" 2000 ASHELL-TOAST ;

\ =====================================================================
\  S20 -- INIT Callback
\ =====================================================================

: PAD-INIT-CB  ( -- )
    \ ---- Initialize state ----
    _PAD-INIT-BUF-TABLE
    -1 _PAD-SIDEBAR-VIS !
    -1 _PAD-OUTPUT-VIS !
    0 _PAD-SHOW-HIDDEN !
    0 _PAD-EXPL !
    0 _PAD-TXTA !
    0 _PAD-OUT-TXTA !
    0 _PAD-ARENA !

    \ ---- Create XMEM arena for editor buffers ----
    _PAD-ARENA-SIZE A-XMEM ARENA-NEW
    ABORT" pad: arena alloc failed"
    _PAD-ARENA !

    \ ---- VFS ----
    VFS-CUR DUP 0= ABORT" pad: no VFS available"
    _PAD-VFS !
    \ ---- Find UIDL elements by ID ----
    S" mbar"           UTUI-BY-ID _PAD-E-MBAR !
    S" main-split"     UTUI-BY-ID _PAD-E-MAIN-SPLIT !
    S" sidebar-scroll" UTUI-BY-ID _PAD-E-SIDEBAR-SCROLL !
    S" sidebar"        UTUI-BY-ID _PAD-E-SIDEBAR !
    S" eo-split"       UTUI-BY-ID _PAD-E-EO-SPLIT !
    S" editor-area"    UTUI-BY-ID _PAD-E-EDITOR-AREA !
    S" output-scroll"  UTUI-BY-ID _PAD-E-OUTPUT-SCROLL !
    S" output"         UTUI-BY-ID _PAD-E-OUTPUT !
    S" sbar"           UTUI-BY-ID _PAD-E-SBAR !
    S" sbar-file"      UTUI-BY-ID _PAD-E-SBAR-FILE !
    S" sbar-pos"       UTUI-BY-ID _PAD-E-SBAR-POS !
    S" sbar-enc"       UTUI-BY-ID _PAD-E-SBAR-ENC !
    S" sbar-tabs"      UTUI-BY-ID _PAD-E-SBAR-TABS !

    \ ---- Theme ----
    _PAD-THEME-DEFAULTS
    _PAD-LOAD-CONFIG
    _PAD-APPLY-THEME

    \ ---- Get output textarea (auto-materialized by UIDL) ----
    _PAD-E-OUTPUT @ ?DUP IF
        UTUI-WIDGET@ _PAD-OUT-TXTA !
    THEN

    \ ---- Create explorer on sidebar ----
    _PAD-E-SIDEBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW
        _PAD-VFS @
        _PAD-VFS @ V.ROOT @
        EXPL-NEW _PAD-EXPL !
        ['] _PAD-ON-EXPL-OPEN _PAD-EXPL @ EXPL-ON-OPEN
        _PAD-EXPL @ _PAD-E-SIDEBAR @ UTUI-WIDGET-SET
    THEN

    \ ---- Create composite panel on editor-area ----
    _PAD-E-EDITOR-AREA @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW
        _PAD-PANEL-INIT

        \ Create the shared textarea (sub-region of panel, row 2+)
        _PAD-PANEL 8 + @  DUP >R         ( panel-rgn  R: panel-rgn )
        2 0  R@ RGN-H 2 - 0 MAX  R> RGN-W
        RGN-SUB                            ( content-rgn )
        _PAD-DUMMY-BUF _PAD-DUMMY-CAP
        TXTA-NEW _PAD-TXTA !

        \ Line number gutter
        ['] _PAD-GUTTER-DRAW _PAD-GUTTER-W _PAD-TXTA @ TXTA-GUTTER!

        \ On-change callback
        ['] _PAD-ON-CHANGE _PAD-TXTA @ TXTA-ON-CHANGE

        \ Mount panel on editor-area
        _PAD-PANEL _PAD-E-EDITOR-AREA @ UTUI-WIDGET-SET
    THEN

    \ ---- Open initial untitled buffer ----
    _PAD-BUF-OPEN DROP

    \ ---- Register all named actions ----
    S" quit"            ['] _PAD-DO-QUIT           UTUI-DO!
    S" new"             ['] _PAD-DO-NEW            UTUI-DO!
    S" open"            ['] _PAD-DO-OPEN           UTUI-DO!
    S" save"            ['] _PAD-DO-SAVE           UTUI-DO!
    S" save-as"         ['] _PAD-DO-SAVE-AS        UTUI-DO!
    S" save-all"        ['] _PAD-DO-SAVE-ALL       UTUI-DO!
    S" close-tab"       ['] _PAD-DO-CLOSE-TAB      UTUI-DO!
    S" close-all"       ['] _PAD-DO-CLOSE-ALL      UTUI-DO!
    S" undo"            ['] _PAD-DO-UNDO           UTUI-DO!
    S" redo"            ['] _PAD-DO-REDO           UTUI-DO!
    S" cut"             ['] _PAD-DO-CUT            UTUI-DO!
    S" copy"            ['] _PAD-DO-COPY           UTUI-DO!
    S" paste"           ['] _PAD-DO-PASTE          UTUI-DO!
    S" select-all"      ['] _PAD-DO-SELECT-ALL     UTUI-DO!
    S" delete-line"     ['] _PAD-DO-DELETE-LINE    UTUI-DO!
    S" find"            ['] _PAD-DO-FIND           UTUI-DO!
    S" replace"         ['] _PAD-DO-REPLACE        UTUI-DO!
    S" goto-line"       ['] _PAD-DO-GOTO-LINE      UTUI-DO!
    S" goto-file"       ['] _PAD-DO-GOTO-FILE      UTUI-DO!
    S" toggle-sidebar"  ['] _PAD-DO-TOGGLE-SIDEBAR UTUI-DO!
    S" toggle-output"   ['] _PAD-DO-TOGGLE-OUTPUT  UTUI-DO!
    S" toggle-hidden"   ['] _PAD-DO-TOGGLE-HIDDEN  UTUI-DO!
    S" next-tab"        ['] _PAD-DO-NEXT-TAB       UTUI-DO!
    S" prev-tab"        ['] _PAD-DO-PREV-TAB       UTUI-DO!
    S" about"           ['] _PAD-DO-ABOUT          UTUI-DO!
    S" shortcuts"       ['] _PAD-DO-SHORTCUTS      UTUI-DO!
    S" select-word"     ['] _PAD-DO-SELECT-WORD    UTUI-DO!
    S" select-line"     ['] _PAD-DO-SELECT-LINE    UTUI-DO!

    \ ---- Focus editor-area ----
    _PAD-E-EDITOR-AREA @ ?DUP IF UTUI-FOCUS! THEN

    \ ---- Initial status ----
    _PAD-UPDATE-STATUS ;

\ =====================================================================
\  S21 -- EVENT Callback
\ =====================================================================

: PAD-EVENT-CB  ( ev -- flag )
    DROP 0 ;

\ =====================================================================
\  S22 -- TICK Callback
\ =====================================================================

: PAD-TICK-CB  ( -- )
    _PAD-UPDATE-STATUS ;

\ =====================================================================
\  S23 -- SHUTDOWN Callback
\ =====================================================================

: PAD-SHUTDOWN-CB  ( -- )
    \ Unbind from textarea
    _PAD-UNBIND

    \ Free all open buffers (GB-FREE is a no-op; undo uses bank0 heap)
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
            I _PAD-BUF-ENTRY _PBE-GB + @ ?DUP IF GB-FREE THEN
            I _PAD-BUF-ENTRY _PBE-UNDO + @ ?DUP IF UNDO-FREE THEN
        THEN
    LOOP

    \ Destroy the editor arena (frees all GB memory in one shot)
    _PAD-ARENA @ ?DUP IF ARENA-DESTROY THEN
    0 _PAD-ARENA !

    \ Free textarea widget
    _PAD-TXTA @ ?DUP IF TXTA-FREE THEN

    \ Free explorer widget
    _PAD-EXPL @ ?DUP IF EXPL-FREE THEN

    \ Zero handles
    0 _PAD-TXTA !
    0 _PAD-EXPL !
    0 _PAD-OUT-TXTA !
    -1 _PAD-ACTIVE !
    0 _PAD-BUF-CNT ! ;

\ =====================================================================
\  S24 -- Entry Point & Standalone Runner
\ =====================================================================

: PAD-ENTRY  ( desc -- )
    DUP APP-DESC-INIT
    ['] PAD-INIT-CB     OVER APP.INIT-XT !
    ['] PAD-EVENT-CB    OVER APP.EVENT-XT !
    ['] PAD-TICK-CB     OVER APP.TICK-XT !
    0                   OVER APP.PAINT-XT !
    ['] PAD-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    S" tui/applets/pad/pad.uidl"
                        ROT DUP >R
                        APP.UIDL-FILE-U !
                        R@ APP.UIDL-FILE-A !
    0                   R@ APP.WIDTH !
    0                   R@ APP.HEIGHT !
    S" Akashic Pad"     R@ APP.TITLE-U !
                        R> APP.TITLE-A ! ;

CREATE PAD-DESC  APP-DESC ALLOT

: PAD-RUN  ( -- )
    PAD-DESC PAD-ENTRY
    PAD-DESC ASHELL-RUN ;

\ =====================================================================
\  S25 -- Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _pad-guard

' PAD-ENTRY   CONSTANT _pad-entry-xt
' PAD-RUN     CONSTANT _pad-run-xt

[THEN] [THEN]
