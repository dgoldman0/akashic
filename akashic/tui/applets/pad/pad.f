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
\   - Find, replace, go-to-line, and selection commands
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
REQUIRE ../../widgets/prompt.f
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
REQUIRE ../../../text/search.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/capability.f
REQUIRE ../../../interop/endpoint.f
REQUIRE ../../../interop/intent.f
REQUIRE ../../../interop/resource.f

\ =====================================================================
\  S2 -- Constants
\ =====================================================================

65536 CONSTANT _PAD-BUF-CAP       \ gap-buffer capacity per buffer
2097152 CONSTANT _PAD-ARENA-SIZE   \ 2 MiB XMEM arena for editor buffers
  256 CONSTANT _PAD-FNAME-CAP     \ filename capacity per slot
  128 CONSTANT _PAD-STATUS-CAP    \ status scratch
 4096 CONSTANT _PAD-IO-CAP        \ file I/O scratch
   16 CONSTANT _PAD-MAX-BUFS      \ max open buffers
    4 CONSTANT _PAD-GUTTER-W      \ compact line-number gutter
    4 CONSTANT _PAD-TAB-W         \ editor indentation columns
   64 CONSTANT _PAD-DUMMY-CAP     \ minimal buffer for TXTA-NEW
  512 CONSTANT _PAD-PROMPT-CAP    \ command-bar input capacity

0 CONSTANT _PAD-PRM-NONE
1 CONSTANT _PAD-PRM-OPEN
2 CONSTANT _PAD-PRM-SAVE-AS
3 CONSTANT _PAD-PRM-FIND
4 CONSTANT _PAD-PRM-GOTO-LINE
5 CONSTANT _PAD-PRM-REPLACE-FIND
6 CONSTANT _PAD-PRM-REPLACE-WITH

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
136 CONSTANT _PTO-SCROLL-X

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

VARIABLE _PAD-CURRENT-STATE
0 _PAD-CURRENT-STATE !
CMP-LAYOUT-BEGIN

\ ---- UIDL element handles ----
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-MBAR
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-MAIN-SPLIT
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-SIDEBAR-SCROLL
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-SIDEBAR
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-EO-SPLIT
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-EDITOR-AREA
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-OUTPUT-SCROLL
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-OUTPUT
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-SBAR
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-SBAR-FILE
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-SBAR-POS
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-SBAR-ENC
_PAD-CURRENT-STATE CMP-CELL: _PAD-E-SBAR-TABS

\ ---- Widget handles ----
_PAD-CURRENT-STATE CMP-CELL: _PAD-EXPL
_PAD-CURRENT-STATE CMP-CELL: _PAD-TXTA
_PAD-CURRENT-STATE CMP-CELL: _PAD-OUT-TXTA
_PAD-CURRENT-STATE CMP-CELL: _PAD-PROMPT
_PAD-CURRENT-STATE CMP-CELL: _PAD-PROMPT-RGN
_PAD-CURRENT-STATE CMP-CELL: _PAD-PROMPT-MODE
_PAD-CURRENT-STATE _PAD-PROMPT-CAP CMP-FIELD: _PAD-PROMPT-BUF
_PAD-CURRENT-STATE _PAD-PROMPT-CAP CMP-FIELD: _PAD-REPLACE-FIND-BUF
_PAD-CURRENT-STATE CMP-CELL: _PAD-REPLACE-FIND-U

\ ---- Buffer table ----
_PAD-CURRENT-STATE _PAD-MAX-BUFS _PAD-BUF-ENTRY-SIZE * CMP-FIELD: _PAD-BUFS
_PAD-CURRENT-STATE _PAD-MAX-BUFS _PAD-FNAME-CAP * CMP-FIELD: _PAD-FNAMES

_PAD-CURRENT-STATE CMP-CELL: _PAD-ACTIVE
_PAD-CURRENT-STATE CMP-CELL: _PAD-BUF-CNT
_PAD-CURRENT-STATE CMP-CELL: _PAD-ARENA

\ ---- Composite panel widget (mounted on editor-area) ----
_PAD-CURRENT-STATE 40 CMP-FIELD: _PAD-PANEL

\ ---- Textarea allocation buffer (GB is always bound, so minimal) ----
_PAD-CURRENT-STATE _PAD-DUMMY-CAP CMP-FIELD: _PAD-DUMMY-BUF

\ ---- File I/O scratch ----
_PAD-CURRENT-STATE _PAD-IO-CAP CMP-FIELD: _PAD-IO-BUF

\ ---- VFS ----
_PAD-CURRENT-STATE CMP-CELL: _PAD-VFS

\ ---- Toggle state ----
_PAD-CURRENT-STATE CMP-CELL: _PAD-SIDEBAR-VIS
_PAD-CURRENT-STATE CMP-CELL: _PAD-OUTPUT-VIS
_PAD-CURRENT-STATE CMP-CELL: _PAD-SHOW-HIDDEN

\ ---- Status bar scratch ----
_PAD-CURRENT-STATE _PAD-STATUS-CAP CMP-FIELD: _PAD-STXT
_PAD-CURRENT-STATE CMP-CELL: _PAD-STXT-L

\ ---- Path scratch for inode-to-path ----
_PAD-CURRENT-STATE 512 CMP-FIELD: _PAD-PATH-BUF

\ =====================================================================
\  S4b -- Theme
\ =====================================================================

_PAD-CURRENT-STATE CMP-CELL: _PTH-EDITOR-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-EDITOR-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-MENU-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-MENU-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-STATUS-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-STATUS-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-SCROLL-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-SCROLL-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-SIDEBAR-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-SIDEBAR-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-TABS-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-TABS-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-OUTPUT-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-OUTPUT-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-ATAB-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-ATAB-BG
_PAD-CURRENT-STATE CMP-CELL: _PTH-GUTTER-FG
_PAD-CURRENT-STATE CMP-CELL: _PTH-GUTTER-BG

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

_PAD-CURRENT-STATE CMP-CELL: _PAD-CFG-A
_PAD-CURRENT-STATE CMP-CELL: _PAD-CFG-L
4096 CONSTANT _PAD-CFG-CAP
_PAD-CURRENT-STATE _PAD-CFG-CAP CMP-FIELD: _PAD-CFG-BUF
_PAD-CURRENT-STATE CMP-CELL: _PAD-CFG-FD

\ ---- Incremental editor paint state ----
_PAD-CURRENT-STATE CMP-CELL: _PAD-FAST-ROW
_PAD-CURRENT-STATE CMP-CELL: _PAD-FAST-COUNT
_PAD-CURRENT-STATE CMP-CELL: _PAD-EV-OLD-LINE
_PAD-CURRENT-STATE CMP-CELL: _PAD-EV-OLD-SCROLL
_PAD-CURRENT-STATE CMP-CELL: _PAD-EV-OLD-SCROLL-X

CMP-LAYOUT-SIZE CONSTANT _PAD-STATE-SIZE

: _PAD-ACTIVATE  ( instance -- )
    CINST-STATE _PAD-CURRENT-STATE ! ;

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

: _PAD-SYNC-TXTA-FOCUS  ( -- )
    _PAD-TXTA @ ?DUP IF
        DUP 32 + @ WDG-F-FOCUSED INVERT AND
        _PAD-PANEL 32 + @ WDG-F-FOCUSED AND IF WDG-F-FOCUSED OR THEN
        SWAP 32 + !
    THEN ;

VARIABLE _PDC-W
VARIABLE _PDC-RGN
VARIABLE _PDC-ROW
VARIABLE _PDC-COL
VARIABLE _PDC-AROW
VARIABLE _PDC-ACOL

: _PAD-DRAW-CARET  ( -- )
    _PAD-TXTA @ ?DUP 0= IF EXIT THEN _PDC-W !
    _PDC-W @ TXTA-CURSOR-LINE
    _PDC-W @ _PTO-SCROLL-Y + @ - _PDC-ROW !
    _PDC-W @ TXTA-CURSOR-COL
    _PDC-W @ _PTO-SCROLL-X + @ - _PAD-GUTTER-W + _PDC-COL !
    _PDC-W @ 8 + @ _PDC-RGN !
    _PDC-ROW @ 0< _PDC-COL @ 0< OR IF EXIT THEN
    _PDC-ROW @ _PDC-RGN @ RGN-H >= IF EXIT THEN
    _PDC-COL @ _PDC-RGN @ RGN-W >= IF EXIT THEN
    _PDC-RGN @ RGN-ROW _PDC-ROW @ + _PDC-AROW !
    _PDC-RGN @ RGN-COL _PDC-COL @ + _PDC-ACOL !
    _PDC-AROW @ _PDC-ACOL @ SCR-GET
    DUP CELL-ATTRS@ CELL-A-REVERSE OR SWAP CELL-ATTRS!
    _PDC-AROW @ _PDC-ACOL @ SCR-SET ;

: _PAD-PANEL-DRAW  ( widget -- )
    DUP _PAD-SYNC-TXTA-RGN
    DROP
    _PAD-SYNC-TXTA-FOCUS
    _PAD-DRAW-TABS
    _PTH-EDITOR-FG @ DRW-FG!  _PTH-EDITOR-BG @ DRW-BG!
    _PAD-TXTA @ ?DUP IF WDG-DRAW THEN
    _PAD-DRAW-CARET ;

: _PAD-PANEL-HANDLE  ( event widget -- consumed? )
    \ Reaching this handler proves the mounted editor region owns focus.
    DUP 32 + DUP @ WDG-F-FOCUSED OR SWAP !
    DROP
    _PAD-SYNC-TXTA-FOCUS
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
    ROT  0  R> 1- 0 MAX  DRW-TEXT-RIGHT
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
VARIABLE _PIO-TEXT
VARIABLE _PIO-TEXT-U
VARIABLE _PIO-NAME-A
VARIABLE _PIO-NAME-U
VARIABLE _PIO-SIZE
VARIABLE _PIO-ACT
VARIABLE _PIO-BUF

VARIABLE _PFN-A
VARIABLE _PFN-U
VARIABLE _PFN-N
VARIABLE _PFN-I

: _PAD-FILENAME!  ( fname-a fname-u index -- )
    _PFN-I ! _PFN-U ! _PFN-A !
    _PFN-U @ _PAD-FNAME-CAP MIN DUP _PFN-N !
    _PFN-I @ _PAD-BUF-ENTRY _PBE-FNAME-L + !
    _PFN-A @
    _PFN-I @ _PAD-BUF-ENTRY _PBE-FNAME-A + @
    _PFN-N @ CMOVE ;

VARIABLE _PFB-A
VARIABLE _PFB-U

: _PAD-FIND-BUFFER  ( fname-a fname-u -- index | -1 )
    _PFB-U ! _PFB-A !
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
            _PFB-A @ _PFB-U @
            I _PAD-BUF-ENTRY DUP _PBE-FNAME-A + @
            SWAP _PBE-FNAME-L + @
            STR-STR= IF I UNLOOP EXIT THEN
        THEN
    LOOP
    -1 ;

: _PAD-DO-SAVE-TO  ( fname-a fname-u -- ior )
    _PIO-NAME-U ! _PIO-NAME-A !
    VFS-CUR >R  _PAD-VFS @ VFS-USE
    _PIO-NAME-A @ _PIO-NAME-U @ VFS-OPEN
    DUP 0= IF
        DROP
        _PIO-NAME-A @ _PIO-NAME-U @ _PAD-VFS @ VFS-CREATE
        DUP 0= IF DROP R> VFS-USE -1 EXIT THEN
        DROP
        _PIO-NAME-A @ _PIO-NAME-U @ VFS-OPEN
        DUP 0= IF DROP R> VFS-USE -1 EXIT THEN
    THEN
    R> VFS-USE
    _PIO-FD !
    _PIO-FD @ VFS-REWIND
    0 _PIO-FD @ VFS-TRUNCATE IF
        _PIO-FD @ VFS-CLOSE -2 EXIT
    THEN
    _PAD-TXTA @ TXTA-GET-TEXT
    _PIO-TEXT-U ! _PIO-TEXT !
    _PIO-TEXT @ _PIO-TEXT-U @ _PIO-FD @ VFS-WRITE _PIO-ACT !
    _PIO-TEXT @ FREE
    _PIO-FD @ VFS-CLOSE
    _PAD-VFS @ VFS-SYNC DROP
    _PIO-ACT @ _PIO-TEXT-U @ = IF 0 ELSE -3 THEN ;

: _PAD-SAVE-CURRENT-AS  ( fname-a fname-u -- ior )
    2DUP _PAD-DO-SAVE-TO
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    _PAD-ACTIVE @ _PAD-FILENAME!
    0 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    _PAD-TXTA @ ?DUP IF WDG-DIRTY THEN
    _PAD-EXPL @ ?DUP IF EXPL-REFRESH THEN
    _PAD-UPDATE-STATUS
    ASHELL-DIRTY!
    0 ;

\ Load a file from path into the active buffer.
: _PAD-LOAD-FILE  ( fname-a fname-u -- ior )
    _PIO-NAME-U ! _PIO-NAME-A !
    VFS-CUR >R  _PAD-VFS @ VFS-USE
    _PIO-NAME-A @ _PIO-NAME-U @ VFS-OPEN
    R> VFS-USE
    DUP 0= IF
        DROP -1 EXIT
    THEN
    _PIO-FD !
    _PAD-ACTIVE @ 0< IF _PIO-FD @ VFS-CLOSE -2 EXIT THEN
    _PIO-FD @ VFS-SIZE _PAD-BUF-CAP MIN _PIO-SIZE !
    _PIO-SIZE @ 1 MAX ALLOCATE IF
        DROP _PIO-FD @ VFS-CLOSE -3 EXIT
    THEN
    _PIO-BUF !
    _PIO-BUF @ _PIO-SIZE @ _PIO-FD @ VFS-READ _PIO-ACT !
    _PIO-BUF @ _PIO-ACT @ _PAD-TXTA @ TXTA-SET-TEXT
    _PIO-BUF @ FREE
    _PIO-NAME-A @ _PIO-NAME-U @ _PAD-ACTIVE @ _PAD-FILENAME!
    _PIO-FD @ FD.INODE @
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-INODE + !
    _PIO-FD @ VFS-SIZE _PAD-BUF-CAP > IF
        S" File truncated to editor capacity" 2500 ASHELL-TOAST
    THEN
    _PIO-FD @ VFS-CLOSE
    0 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    _PAD-UPDATE-STATUS
    ASHELL-DIRTY!
    0 ;

VARIABLE _POP-IDX

: _PAD-OPEN-PATH  ( fname-a fname-u -- ior )
    _PIO-NAME-U ! _PIO-NAME-A !
    _PIO-NAME-A @ _PIO-NAME-U @ _PAD-FIND-BUFFER DUP 0>= IF
        _PAD-BUF-SWITCH 0 EXIT
    THEN
    DROP
    VFS-CUR >R _PAD-VFS @ VFS-USE
    _PIO-NAME-A @ _PIO-NAME-U @ VFS-OPEN
    R> VFS-USE
    DUP 0= IF DROP -1 EXIT THEN
    VFS-CLOSE
    _PAD-BUF-OPEN DUP 0< IF DROP -2 EXIT THEN
    _POP-IDX !
    _PIO-NAME-A @ _PIO-NAME-U @ _PAD-LOAD-FILE DUP IF
        _POP-IDX @ _PAD-BUF-CLOSE
    THEN ;

\ =====================================================================
\  S12 -- Explorer Callback
\ =====================================================================

: _PAD-ON-EXPL-OPEN  ( inode explorer -- )
    DROP
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP EXIT THEN
    DUP _PAD-PATH-BUF 512 VFS-INODE-PATH   ( inode len )
    SWAP DROP                              ( len )
    DUP 0= IF DROP EXIT THEN
    _PAD-PATH-BUF SWAP _PAD-OPEN-PATH
    DUP -1 = IF S" File not found" 2000 ASHELL-TOAST THEN
    DUP -2 = IF S" Max buffers reached" 2000 ASHELL-TOAST THEN
    DROP ;

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

VARIABLE _PPS-MODE
VARIABLE _PPS-LA
VARIABLE _PPS-LU
VARIABLE _PPS-IA
VARIABLE _PPS-IU

: _PAD-SHOW-PROMPT  ( mode label-a label-u initial-a initial-u -- )
    _PPS-IU ! _PPS-IA ! _PPS-LU ! _PPS-LA ! _PPS-MODE !
    _PAD-PROMPT @ 0= IF EXIT THEN
    _PPS-MODE @ _PAD-PROMPT-MODE !
    _PPS-LA @ _PPS-LU @ _PPS-IA @ _PPS-IU @
        _PAD-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _PAD-SHOW-SAVE-AS  ( -- )
    _PAD-ACTIVE @ 0< IF EXIT THEN
    _PAD-PRM-SAVE-AS S" Save as:"
    _PAD-ACTIVE @ _PAD-BUF-ENTRY
    DUP _PBE-FNAME-A + @ SWAP _PBE-FNAME-L + @
    _PAD-SHOW-PROMPT ;

: _PAD-DO-OPEN  ( elem -- )
    DROP
    _PAD-PRM-OPEN S" Open:" 0 0 _PAD-SHOW-PROMPT ;

: _PAD-DO-SAVE  ( elem -- )
    DROP
    _PAD-ACTIVE @ 0< IF EXIT THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-FNAME-L + @ 0= IF
        _PAD-SHOW-SAVE-AS EXIT
    THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY DUP _PBE-FNAME-A + @ SWAP _PBE-FNAME-L + @
    _PAD-SAVE-CURRENT-AS
    IF S" Save failed" 2000 ASHELL-TOAST EXIT THEN
    S" Saved" 1500 ASHELL-TOAST
    _PAD-UPDATE-STATUS ASHELL-DIRTY! ;

: _PAD-DO-SAVE-AS  ( elem -- )
    DROP _PAD-SHOW-SAVE-AS ;

VARIABLE _PSA-ORIG
VARIABLE _PSA-SAVED
VARIABLE _PSA-SKIPPED
VARIABLE _PSA-FAILED

: _PAD-DO-SAVE-ALL  ( elem -- )
    DROP
    _PAD-ACTIVE @ _PSA-ORIG !
    0 _PSA-SAVED ! 0 _PSA-SKIPPED ! 0 _PSA-FAILED !
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY DUP _PBE-FLAGS + @ IF
            DUP _PBE-DIRTY + @ IF
                DUP _PBE-FNAME-L + @ 0= IF
                    DROP 1 _PSA-SKIPPED +!
                ELSE
                    DROP I _PAD-BUF-SWITCH
                    I _PAD-BUF-ENTRY DUP _PBE-FNAME-A + @
                    SWAP _PBE-FNAME-L + @ _PAD-DO-SAVE-TO
                    IF
                        1 _PSA-FAILED +!
                    ELSE
                        0 I _PAD-BUF-ENTRY _PBE-DIRTY + !
                        1 _PSA-SAVED +!
                    THEN
                THEN
            ELSE
                DROP
            THEN
        ELSE
            DROP
        THEN
    LOOP
    _PSA-ORIG @ DUP 0>= IF
        DUP _PAD-BUF-ENTRY _PBE-FLAGS + @ IF
            _PAD-BUF-SWITCH
        ELSE DROP THEN
    ELSE DROP THEN
    _PAD-TXTA @ ?DUP IF WDG-DIRTY THEN
    _PAD-EXPL @ ?DUP IF EXPL-REFRESH THEN
    _PAD-UPDATE-STATUS ASHELL-DIRTY!
    _PSA-FAILED @ IF
        S" Some buffers failed to save" 2500 ASHELL-TOAST EXIT
    THEN
    _PSA-SKIPPED @ IF
        S" Saved named buffers; untitled buffers remain" 2500 ASHELL-TOAST EXIT
    THEN
    _PSA-SAVED @ IF
        S" All modified buffers saved" 1800 ASHELL-TOAST
    ELSE
        S" Nothing to save" 1200 ASHELL-TOAST
    THEN ;

: _PAD-HAS-DIRTY?  ( -- flag )
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY DUP _PBE-FLAGS + @ IF
            _PBE-DIRTY + @ IF TRUE UNLOOP EXIT THEN
        ELSE DROP THEN
    LOOP
    FALSE ;

: _PAD-DO-CLOSE-TAB  ( elem -- )
    DROP
    _PAD-ACTIVE @ 0< IF EXIT THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ IF
        S" Discard unsaved changes?" DLG-CONFIRM 0= IF EXIT THEN
    THEN
    _PAD-ACTIVE @ _PAD-BUF-CLOSE ;

: _PAD-DO-CLOSE-ALL  ( elem -- )
    DROP
    _PAD-HAS-DIRTY? IF
        S" Close all and discard unsaved changes?" DLG-CONFIRM 0= IF EXIT THEN
    THEN
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
    DROP
    _PAD-HAS-DIRTY? IF
        S" Quit and discard unsaved changes?" DLG-CONFIRM 0= IF EXIT THEN
    THEN
    ASHELL-QUIT ;

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

VARIABLE _PSR-START
VARIABLE _PSR-END

: _PAD-SELECT-RANGE  ( start end -- )
    _PSR-END ! _PSR-START !
    _PAD-TXTA @ 0= IF EXIT THEN
    _PSR-START @ _PAD-TXTA @ _PTO-SEL-ANC + !
    _PSR-END @ DUP
    _PAD-TXTA @ _PTO-GB + @ GB-MOVE!
    _PAD-TXTA @ _PTO-CURSOR + !
    _PAD-TXTA @ WDG-DIRTY
    ASHELL-DIRTY! ;

VARIABLE _PLR-GB
VARIABLE _PLR-LINE
VARIABLE _PLR-START
VARIABLE _PLR-END

: _PAD-CURRENT-LINE-RANGE  ( -- start end )
    _PAD-TXTA @ _PTO-GB + @ _PLR-GB !
    _PLR-GB @ GB-CURSOR-LINE _PLR-LINE !
    _PLR-LINE @ _PLR-GB @ GB-LINE-OFF DUP _PLR-START !
    _PLR-LINE @ _PLR-GB @ GB-LINE-LEN + _PLR-END !
    _PLR-LINE @ 1+ _PLR-GB @ GB-LINES < IF
        1 _PLR-END +!
    ELSE
        _PLR-START @ 0> IF -1 _PLR-START +! THEN
    THEN
    _PLR-START @ _PLR-END @ ;

: _PAD-DO-DELETE-LINE  ( elem -- )
    DROP
    _PAD-TXTA @ 0= IF EXIT THEN
    _PAD-CURRENT-LINE-RANGE 2DUP = IF 2DROP EXIT THEN
    _PAD-SELECT-RANGE
    _PAD-TXTA @ TXTA-DEL-SEL DROP
    ASHELL-DIRTY! ;

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
\  S16 -- Actions: Find / Replace / Goto
\ =====================================================================

VARIABLE _PFT-A
VARIABLE _PFT-U
VARIABLE _PFT-GB
VARIABLE _PFT-START
VARIABLE _PFT-MATCH

: _PAD-FIND-MATCH  ( find-a find-u -- flag )
    _PFT-U ! _PFT-A !
    _PFT-U @ 0= IF 0 EXIT THEN
    _PAD-TXTA @ 0= IF 0 EXIT THEN
    _PAD-TXTA @ _PTO-GB + @ DUP 0= IF DROP 0 EXIT THEN _PFT-GB !
    _PAD-TXTA @ _PTO-CURSOR + @ _PFT-START !
    _PFT-START @ _PFT-A @ _PFT-U @ _PFT-GB @ SRCH-FIND
    DUP 0< IF
        DROP 0 _PFT-A @ _PFT-U @ _PFT-GB @ SRCH-FIND
    THEN
    DUP 0< IF DROP 0 EXIT THEN
    DUP _PFT-MATCH !
    _PFT-U @ +
    _PFT-MATCH @ SWAP _PAD-SELECT-RANGE
    -1 ;

: _PAD-CURSOR!  ( pos -- )
    _PAD-TXTA @ 0= IF DROP EXIT THEN
    0 MAX
    _PAD-TXTA @ _PTO-GB + @ GB-LEN MIN
    DUP _PAD-TXTA @ _PTO-GB + @ GB-MOVE!
    _PAD-TXTA @ _PTO-CURSOR + !
    -1 _PAD-TXTA @ _PTO-SEL-ANC + !
    _PAD-TXTA @ WDG-DIRTY
    ASHELL-DIRTY! ;

: _PAD-GOTO-LINE-TEXT  ( addr len -- )
    STR>NUM 0= IF
        DROP S" Invalid line number" 1800 ASHELL-TOAST EXIT
    THEN
    DUP 1 < IF DROP S" Line numbers start at 1" 1800 ASHELL-TOAST EXIT THEN
    1-
    _PAD-TXTA @ _PTO-GB + @ >R
    DUP R@ GB-LINES >= IF
        DROP R> DROP S" Line is outside the document" 1800 ASHELL-TOAST EXIT
    THEN
    R> GB-LINE-OFF _PAD-CURSOR! ;

: _PAD-DO-FIND  ( elem -- )
    DROP _PAD-PRM-FIND S" Find:" 0 0 _PAD-SHOW-PROMPT ;

: _PAD-DO-REPLACE  ( elem -- )
    DROP _PAD-PRM-REPLACE-FIND S" Replace:" 0 0 _PAD-SHOW-PROMPT ;

: _PAD-DO-GOTO-LINE  ( elem -- )
    DROP _PAD-PRM-GOTO-LINE S" Go to line:" 0 0 _PAD-SHOW-PROMPT ;

: _PAD-DO-GOTO-FILE  ( elem -- )
    DROP _PAD-PRM-OPEN S" Open:" 0 0 _PAD-SHOW-PROMPT ;

VARIABLE _PPSUB-A
VARIABLE _PPSUB-U
VARIABLE _PPSUB-MODE

: _PAD-PROMPT-SUBMIT  ( prompt -- )
    PRM-GET-TEXT _PPSUB-U ! _PPSUB-A !
    _PAD-E-SBAR @ ?DUP IF UIDL-DIRTY! THEN
    _PAD-PROMPT-MODE @ _PPSUB-MODE !
    _PAD-PRM-NONE _PAD-PROMPT-MODE !
    _PPSUB-MODE @ _PAD-PRM-REPLACE-WITH <
    _PPSUB-U @ 0= AND IF EXIT THEN
    _PPSUB-MODE @ CASE
        _PAD-PRM-OPEN OF
            _PPSUB-A @ _PPSUB-U @ _PAD-OPEN-PATH
            DUP -1 = IF S" File not found" 2000 ASHELL-TOAST THEN
            DUP -2 = IF S" Max buffers reached" 2000 ASHELL-TOAST THEN
            DROP
        ENDOF
        _PAD-PRM-SAVE-AS OF
            _PPSUB-A @ _PPSUB-U @ _PAD-SAVE-CURRENT-AS
            IF S" Save failed" 2000 ASHELL-TOAST
            ELSE S" Saved" 1500 ASHELL-TOAST THEN
        ENDOF
        _PAD-PRM-FIND OF
            _PPSUB-A @ _PPSUB-U @ _PAD-FIND-MATCH 0= IF
                S" Text not found" 1800 ASHELL-TOAST
            THEN
        ENDOF
        _PAD-PRM-GOTO-LINE OF
            _PPSUB-A @ _PPSUB-U @ _PAD-GOTO-LINE-TEXT
        ENDOF
        _PAD-PRM-REPLACE-FIND OF
            _PPSUB-U @ _PAD-PROMPT-CAP MIN
            DUP _PAD-REPLACE-FIND-U !
            _PPSUB-A @ _PAD-REPLACE-FIND-BUF ROT CMOVE
            _PAD-PRM-REPLACE-WITH S" Replace with:" 0 0 _PAD-SHOW-PROMPT
        ENDOF
        _PAD-PRM-REPLACE-WITH OF
            _PAD-REPLACE-FIND-BUF _PAD-REPLACE-FIND-U @
            _PAD-FIND-MATCH IF
                _PAD-TXTA @ TXTA-DEL-SEL DROP
                _PPSUB-A @ _PPSUB-U @ _PAD-TXTA @ TXTA-INS-STR
                S" Replaced" 1200 ASHELL-TOAST
            ELSE
                S" Text not found" 1800 ASHELL-TOAST
            THEN
        ENDOF
    ENDCASE
    ASHELL-DIRTY! ;

: _PAD-PROMPT-CANCEL  ( prompt -- )
    DROP _PAD-PRM-NONE _PAD-PROMPT-MODE !
    _PAD-E-SBAR @ ?DUP IF UIDL-DIRTY! THEN
    ASHELL-DIRTY! ;

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

VARIABLE _PSW-GB
VARIABLE _PSW-LEN
VARIABLE _PSW-POS
VARIABLE _PSW-START
VARIABLE _PSW-END
VARIABLE _PSW-BYTE

: _PAD-WORD-BYTE?  ( c -- flag )
    _PSW-BYTE !
    _PSW-BYTE @ [CHAR] 0 >= _PSW-BYTE @ [CHAR] 9 <= AND
    _PSW-BYTE @ [CHAR] A >= _PSW-BYTE @ [CHAR] Z <= AND OR
    _PSW-BYTE @ [CHAR] a >= _PSW-BYTE @ [CHAR] z <= AND OR
    _PSW-BYTE @ [CHAR] _ = OR
    _PSW-BYTE @ 128 >= OR ;

: _PAD-DO-SELECT-WORD  ( elem -- )
    DROP
    _PAD-TXTA @ 0= IF EXIT THEN
    _PAD-TXTA @ _PTO-GB + @ DUP 0= IF DROP EXIT THEN _PSW-GB !
    _PSW-GB @ GB-LEN DUP 0= IF DROP EXIT THEN _PSW-LEN !
    _PAD-TXTA @ _PTO-CURSOR + @ _PSW-POS !
    _PSW-POS @ _PSW-LEN @ >= IF _PSW-LEN @ 1- _PSW-POS ! THEN
    _PSW-POS @ _PSW-GB @ GB-BYTE@ _PAD-WORD-BYTE? 0= IF
        _PSW-POS @ 0= IF EXIT THEN
        _PSW-POS @ 1- DUP _PSW-GB @ GB-BYTE@ _PAD-WORD-BYTE? 0= IF
            DROP EXIT
        THEN
        _PSW-POS !
    THEN
    _PSW-POS @ _PSW-START !
    BEGIN
        _PSW-START @ 0> IF
            _PSW-START @ 1- _PSW-GB @ GB-BYTE@ _PAD-WORD-BYTE?
        ELSE FALSE THEN
    WHILE
        -1 _PSW-START +!
    REPEAT
    _PSW-POS @ 1+ _PSW-END !
    BEGIN
        _PSW-END @ _PSW-LEN @ < IF
            _PSW-END @ _PSW-GB @ GB-BYTE@ _PAD-WORD-BYTE?
        ELSE FALSE THEN
    WHILE
        1 _PSW-END +!
    REPEAT
    _PSW-START @ _PSW-END @ _PAD-SELECT-RANGE ;

: _PAD-DO-SELECT-LINE  ( elem -- )
    DROP
    _PAD-TXTA @ 0= IF EXIT THEN
    _PAD-CURRENT-LINE-RANGE _PAD-SELECT-RANGE ;

\ =====================================================================
\  S20 -- INIT Callback
\ =====================================================================

: PAD-INIT-CB  ( instance -- )
    _PAD-ACTIVATE
    \ ---- Initialize state ----
    _PAD-INIT-BUF-TABLE
    -1 _PAD-SIDEBAR-VIS !
    -1 _PAD-OUTPUT-VIS !
    0 _PAD-SHOW-HIDDEN !
    0 _PAD-EXPL !
    0 _PAD-TXTA !
    0 _PAD-OUT-TXTA !
    0 _PAD-PROMPT !
    0 _PAD-PROMPT-RGN !
    _PAD-PRM-NONE _PAD-PROMPT-MODE !
    0 _PAD-REPLACE-FIND-U !
    0 _PAD-ARENA !
   -1 _PAD-FAST-ROW !
    0 _PAD-FAST-COUNT !

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

    \ ---- Status-row command bar ----
    _PAD-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW
        DUP _PAD-PROMPT-RGN !
        _PAD-PROMPT-BUF _PAD-PROMPT-CAP PRM-NEW
        DUP _PAD-PROMPT !
        ['] _PAD-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
        ['] _PAD-PROMPT-CANCEL OVER PRM-ON-CANCEL
        _PTH-STATUS-FG @ _PTH-STATUS-BG @ ROT PRM-COLORS!
    THEN

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

: _PAD-INSERT-TAB  ( -- )
    _PAD-TXTA @ ?DUP IF
        DUP TXTA-CURSOR-COL _PAD-TAB-W MOD
        _PAD-TAB-W SWAP -
        S"     " DROP SWAP ROT TXTA-INS-STR
    THEN ;

: _PAD-FAST-CHAR?  ( ev -- flag )
    DUP @ KEY-T-CHAR <> IF DROP 0 EXIT THEN
    DUP 16 + @ KEY-MOD-CTRL AND IF DROP 0 EXIT THEN
    8 + @ 32 < IF 0 EXIT THEN
    _PAD-TXTA @ _PTO-SEL-ANC + @ -1 = ;

: _PAD-ENTER-EVENT?  ( ev -- flag )
    DUP @ KEY-T-SPECIAL = IF
        8 + @ KEY-ENTER = EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
        8 + @ 13 = EXIT
    THEN
    DROP 0 ;

: _PAD-FAST-LAST-ENTER?  ( ev -- flag )
    _PAD-ENTER-EVENT? 0= IF 0 EXIT THEN
    _PAD-TXTA @ _PTO-SEL-ANC + @ -1 <> IF 0 EXIT THEN
    _PAD-TXTA @ TXTA-CURSOR-LINE _PAD-EV-OLD-LINE !
    _PAD-TXTA @ _PTO-SCROLL-Y + @ _PAD-EV-OLD-SCROLL !
    _PAD-EV-OLD-LINE @
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-GB + @ GB-LINES 1- =
    _PAD-EV-OLD-LINE @ _PAD-EV-OLD-SCROLL @ -
    DUP 0>= SWAP 1+ _PAD-TXTA @ WDG-REGION RGN-H < AND
    AND ;

: _PAD-HANDLE-EDITOR  ( ev -- flag )
    -1 _PAD-FAST-ROW !
    0 _PAD-FAST-COUNT !
    DUP _PAD-FAST-CHAR? IF
        _PAD-TXTA @ TXTA-CURSOR-LINE _PAD-EV-OLD-LINE !
        _PAD-TXTA @ _PTO-SCROLL-Y + @ _PAD-EV-OLD-SCROLL !
        _PAD-TXTA @ _PTO-SCROLL-X + @ _PAD-EV-OLD-SCROLL-X !
        DUP _PAD-PANEL WDG-HANDLE       ( ev handled? )
        DUP IF
            _PAD-TXTA @ TXTA-ADJUST-SCROLL
            _PAD-TXTA @ TXTA-CURSOR-LINE _PAD-EV-OLD-LINE @ =
            _PAD-TXTA @ _PTO-SCROLL-Y + @ _PAD-EV-OLD-SCROLL @ = AND IF
                _PAD-TXTA @ _PTO-SCROLL-X + @
                _PAD-EV-OLD-SCROLL-X @ = IF
                    _PAD-EV-OLD-LINE @ _PAD-EV-OLD-SCROLL @ -
                    _PAD-FAST-ROW !
                    1 _PAD-FAST-COUNT !
                THEN
            THEN
        THEN
        NIP EXIT
    THEN
    DUP _PAD-FAST-LAST-ENTER? IF
        _PAD-TXTA @ _PTO-SCROLL-X + @ _PAD-EV-OLD-SCROLL-X !
        DUP _PAD-PANEL WDG-HANDLE       ( ev handled? )
        DUP IF
            _PAD-TXTA @ TXTA-ADJUST-SCROLL
            _PAD-TXTA @ TXTA-CURSOR-LINE _PAD-EV-OLD-LINE @ 1+ =
            _PAD-TXTA @ _PTO-SCROLL-Y + @ _PAD-EV-OLD-SCROLL @ = AND IF
                _PAD-TXTA @ _PTO-SCROLL-X + @
                _PAD-EV-OLD-SCROLL-X @ = IF
                    _PAD-EV-OLD-LINE @ _PAD-EV-OLD-SCROLL @ -
                    _PAD-FAST-ROW !
                    2 _PAD-FAST-COUNT !
                THEN
            THEN
        THEN
        NIP EXIT
    THEN
    _PAD-PANEL WDG-HANDLE ;

: PAD-EVENT-CB  ( ev instance -- flag )
    _PAD-ACTIVATE
    -1 _PAD-FAST-ROW !
    0 _PAD-FAST-COUNT !
    _PAD-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN
        DROP
    THEN
    \ Only bypass UIDL's region repaint while the mounted editor owns focus.
    \ Sidebar/menu events must continue through normal focused dispatch.
    UTUI-FOCUS _PAD-E-EDITOR-AREA @ <> IF DROP 0 EXIT THEN
    \ Modified keys may be registered UIDL/menu shortcuts.  Preserve that
    \ priority; UIDL will forward an unmatched key back to the textarea.
    DUP 16 + @ KEY-MOD-CTRL KEY-MOD-ALT OR AND IF DROP 0 EXIT THEN
    DUP @ KEY-T-SPECIAL = IF
        DUP 8 + @ KEY-TAB = IF
            DUP 16 + @ KEY-MOD-SHIFT AND 0= IF
                DROP _PAD-INSERT-TAB -1 EXIT
            THEN
        THEN
    THEN
    \ Route ordinary editor input directly to the mounted panel.  Letting
    \ UIDL redispatch the same event dirties and refills the entire
    \ editor-area before Pad paints its already-dirty textarea, doubling
    \ the cell work for every character.  Unhandled shortcuts still fall
    \ through to UIDL via the false result.
    _PAD-HANDLE-EDITOR ;

\ Paint the command bar after UIDL so it overlays the status row.
: PAD-PAINT-CB  ( instance -- )
    _PAD-ACTIVATE
    \ The editor is a custom widget mounted inside a UIDL region.  Its
    \ model may change from app-level prompt actions that bypass UIDL's
    \ normal focused-element invalidation, so bridge widget dirtiness here.
    _PAD-TXTA @ ?DUP IF
        DUP WDG-DIRTY? IF
            DROP
            _PAD-FAST-ROW @ 0< IF
                _PAD-PANEL WDG-DRAW
            ELSE
                \ A printable edit with unchanged line mapping only needs
                \ its viewport row.  Tabs are cheap and keep the dirty-star
                \ indicator current without repainting the editor body.
                _PAD-PANEL WDG-REGION RGN-USE
                _PAD-PANEL _PAD-SYNC-TXTA-RGN
                _PAD-SYNC-TXTA-FOCUS
                _PAD-DRAW-TABS
                _PTH-EDITOR-FG @ DRW-FG! _PTH-EDITOR-BG @ DRW-BG!
                _PAD-FAST-ROW @ _PAD-FAST-COUNT @
                _PAD-TXTA @ TXTA-DRAW-ROWS
                _PAD-DRAW-CARET
            THEN
            -1 _PAD-FAST-ROW !
            0 _PAD-FAST-COUNT !
        ELSE
            DROP
        THEN
    THEN
    _PAD-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN
    DROP
    _PAD-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN _PAD-PROMPT @ PRM-SET-BOUNDS
    THEN
    _PAD-PROMPT @ WDG-DRAW ;

\ =====================================================================
\  S22 -- TICK Callback
\ =====================================================================

: PAD-TICK-CB  ( instance -- )
    _PAD-ACTIVATE
    _PAD-UPDATE-STATUS ;

\ =====================================================================
\  S23 -- SHUTDOWN Callback
\ =====================================================================

: PAD-SHUTDOWN-CB  ( instance -- )
    _PAD-ACTIVATE
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

    \ Free command-bar allocations (outer region is caller-owned)
    _PAD-PROMPT @ ?DUP IF PRM-FREE THEN
    _PAD-PROMPT-RGN @ ?DUP IF RGN-FREE THEN

    \ Zero handles
    0 _PAD-TXTA !
    0 _PAD-EXPL !
    0 _PAD-OUT-TXTA !
    0 _PAD-PROMPT !
    0 _PAD-PROMPT-RGN !
    -1 _PAD-ACTIVE !
    0 _PAD-BUF-CNT ! ;

\ =====================================================================
\  S24 -- Entry Point & Standalone Runner
\ =====================================================================

CREATE _PAD-RESOURCE-SCHEMA CS-SIZE ALLOT
CREATE _PAD-ACTIVE-SCHEMA CS-SIZE ALLOT
2 CONSTANT _PAD-CAP-COUNT
CREATE PAD-CAPS _PAD-CAP-COUNT CAP-DESC * ALLOT
: PAD-CAP-OPEN    ( -- cap ) PAD-CAPS ;
: PAD-CAP-ACTIVE  ( -- cap ) PAD-CAPS CAP-DESC + ;

CREATE PAD-INTENTS CINT-DESC-SIZE ALLOT

VARIABLE _PCH-A
VARIABLE _PCH-U
VARIABLE _PCH-REQ

: _PAD-CAP-OPEN-HANDLER  ( request instance -- status )
    _PAD-ACTIVATE
    DUP _PCH-REQ !
    CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@
    IRES-VFS-PATH 0= IF 2DROP CBUS-S-INVALID EXIT THEN
    _PCH-U ! _PCH-A !
    _PCH-A @ _PCH-U @ _PAD-OPEN-PATH
    DUP 0= IF
        DROP
        _PCH-REQ @ CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@
        _PCH-REQ @ CBR.RESULT CV-RESOURCE! IF
            CBUS-S-FAILED EXIT
        THEN
        CBUS-S-OK EXIT
    THEN
    DROP CBUS-S-NOT-FOUND ;

: _PAD-CAP-ACTIVE-HANDLER  ( request instance -- status )
    _PAD-ACTIVATE
    _PAD-ACTIVE @ 0< IF
        DUP CBR.RESULT CV-NULL! DROP CBUS-S-OK EXIT
    THEN
    _PAD-ACTIVE @ _PAD-BUF-ENTRY
    DUP _PBE-FNAME-L + @ DUP 0= IF
        2DROP S" /untitled" ROT CBR.RESULT IRES-VFS!
    ELSE
        >R _PBE-FNAME-A + @ R> ROT CBR.RESULT IRES-VFS!
    THEN
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _PAD-CAP-SETUP  ( -- )
    _PAD-RESOURCE-SCHEMA CS-INIT
    CV-T-RESOURCE _PAD-RESOURCE-SCHEMA CS-ALLOW!
    516 _PAD-RESOURCE-SCHEMA CS-MAX-LEN!
    _PAD-ACTIVE-SCHEMA CS-INIT
    CV-T-NULL CS-TYPE-BIT CV-T-RESOURCE CS-TYPE-BIT OR
    _PAD-ACTIVE-SCHEMA CS-ALLOW-MASK!
    516 _PAD-ACTIVE-SCHEMA CS-MAX-LEN!

    PAD-CAP-OPEN CAP-DESC-INIT
    CAP-K-COMMAND PAD-CAP-OPEN CAP.KIND !
    S" pad.document.open"
    PAD-CAP-OPEN CAP.ID-U ! PAD-CAP-OPEN CAP.ID-A !
    S" Open document"
    PAD-CAP-OPEN CAP.TITLE-U ! PAD-CAP-OPEN CAP.TITLE-A !
    S" Open or focus a VFS text document in this Pad instance"
    PAD-CAP-OPEN CAP.DESC-U ! PAD-CAP-OPEN CAP.DESC-A !
    _PAD-RESOURCE-SCHEMA PAD-CAP-OPEN CAP.IN-SCHEMA !
    _PAD-RESOURCE-SCHEMA PAD-CAP-OPEN CAP.OUT-SCHEMA !
    CAP-E-NAVIGATE PAD-CAP-OPEN CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR PAD-CAP-OPEN CAP.FLAGS !
    ['] _PAD-CAP-OPEN-HANDLER PAD-CAP-OPEN CAP.HANDLER-XT !

    PAD-CAP-ACTIVE CAP-DESC-INIT
    CAP-K-RESOURCE PAD-CAP-ACTIVE CAP.KIND !
    S" pad.document.active"
    PAD-CAP-ACTIVE CAP.ID-U ! PAD-CAP-ACTIVE CAP.ID-A !
    S" Active document"
    PAD-CAP-ACTIVE CAP.TITLE-U ! PAD-CAP-ACTIVE CAP.TITLE-A !
    S" Read the active document resource"
    PAD-CAP-ACTIVE CAP.DESC-U ! PAD-CAP-ACTIVE CAP.DESC-A !
    _PAD-ACTIVE-SCHEMA PAD-CAP-ACTIVE CAP.OUT-SCHEMA !
    CAP-E-OBSERVE PAD-CAP-ACTIVE CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
    PAD-CAP-ACTIVE CAP.FLAGS !
    ['] _PAD-CAP-ACTIVE-HANDLER PAD-CAP-ACTIVE CAP.HANDLER-XT !

    PAD-INTENTS CINT-DESC-INIT
    S" resource.open"
    PAD-INTENTS CINTD.ID-U ! PAD-INTENTS CINTD.ID-A !
    PAD-CAP-OPEN PAD-INTENTS CINTD.CAP !
    100 PAD-INTENTS CINTD.PRIORITY ! ;

CREATE PAD-COMP-DESC COMP-DESC ALLOT

: _PAD-COMP-SETUP  ( -- )
    _PAD-CAP-SETUP
    PAD-COMP-DESC COMP-DESC-INIT
    S" org.akashic.pad"
    PAD-COMP-DESC COMP.ID-U ! PAD-COMP-DESC COMP.ID-A !
    S" 1.0.0"
    PAD-COMP-DESC COMP.VERSION-U ! PAD-COMP-DESC COMP.VERSION-A !
    _PAD-STATE-SIZE PAD-COMP-DESC COMP.STATE-SIZE !
    PAD-CAPS PAD-COMP-DESC COMP.CAPS-A !
    _PAD-CAP-COUNT PAD-COMP-DESC COMP.CAPS-N !
    PAD-INTENTS PAD-COMP-DESC COMP.INTENTS-A !
    1 PAD-COMP-DESC COMP.INTENTS-N ! ;

: PAD-ENTRY  ( desc -- )
    _PAD-COMP-SETUP
    DUP APP-DESC-INIT
    PAD-COMP-DESC       OVER APP.COMP-DESC !
    ['] PAD-INIT-CB     OVER APP.INIT-XT !
    ['] PAD-EVENT-CB    OVER APP.EVENT-XT !
    ['] PAD-TICK-CB     OVER APP.TICK-XT !
    ['] PAD-PAINT-CB    OVER APP.PAINT-XT !
    ['] PAD-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _PAD-ACTIVATE   OVER APP.ACTIVATE-XT !
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
