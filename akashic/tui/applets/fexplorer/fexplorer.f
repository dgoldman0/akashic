\ =================================================================
\  fexplorer.f — Full-Featured File Explorer Applet (UIDL)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: FEXP- / _FEXP-
\  Depends on: akashic-tui-explorer, akashic-tui-list,
\              akashic-tui-textarea, akashic-tui-input,
\              akashic-tui-dialog, akashic-tui-app-shell,
\              akashic-tui-app-desc, akashic-tui-uidl-tui,
\              akashic-vfs
\
\  Dual-pane file manager.  UI is declared as UIDL XML and loaded
\  by app-shell.f automatically.  The applet provides only:
\    INIT-XT      — "document ready": find elements, register actions,
\                   create explorer/list widgets, populate data
\    EVENT-XT     — intercept Backspace (parent dir); return 0 for rest
\    SHUTDOWN-XT  — free explorer + list widgets
\    PAINT-XT     — not needed (0); UTUI-PAINT handles everything
\
\  Features:
\   - Tree sidebar (EXPL-* widget mounted on <region id="sidebar">)
\   - Detail list panel (LST-* widget mounted on <region id="detail">)
\   - Text preview panel (UIDL <textarea id="preview">)
\   - Menu bar via <menubar>/<menu>/<item> + do= actions
\   - Status bar via <status>/<label> elements
\   - Clipboard (copy / cut / paste via VFS)
\   - Go-to-path dialog (Ctrl+G)
\   - Sort modes (name / size / type)
\   - Properties dialog (Ctrl+I)
\   - All shortcuts registered via key= attributes
\
\  Entry:  FEXP-ENTRY ( desc -- )   for desk/app-loader launch
\          FEXP-RUN   ( -- )        standalone execution
\ =================================================================

PROVIDED akashic-tui-fexplorer

\ =====================================================================
\  §1 — Dependencies
\ =====================================================================

REQUIRE ../../widgets/explorer.f
REQUIRE ../../widgets/list.f
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
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../utils/toml.f
REQUIRE ../../color.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/capability.f
REQUIRE ../../../interop/endpoint.f
REQUIRE ../../../interop/intent.f
REQUIRE ../../../interop/resource.f

\ =====================================================================
\  §2 — Constants
\ =====================================================================

256 CONSTANT _FEXP-MAX-DIR        \ max directory entries in detail list
 80 CONSTANT _FEXP-LINE-W         \ formatted line width (chars)
512 CONSTANT _FEXP-PATH-CAP       \ path buffer capacity
32768 CONSTANT _FEXP-PREVIEW-CAP  \ preview buffer 32 KiB
512 CONSTANT _FEXP-PROMPT-CAP     \ command-bar input capacity

\ Sort modes
0 CONSTANT FEXP-SORT-NAME
1 CONSTANT FEXP-SORT-SIZE
2 CONSTANT FEXP-SORT-TYPE

\ Command-bar modes
0 CONSTANT _FEXP-PRM-NONE
1 CONSTANT _FEXP-PRM-GOTO
2 CONSTANT _FEXP-PRM-NEW-FILE
3 CONSTANT _FEXP-PRM-NEW-DIR
4 CONSTANT _FEXP-PRM-RENAME

\ Clipboard operations
0 CONSTANT _FEXP-CLIP-NONE
1 CONSTANT _FEXP-CLIP-COPY
2 CONSTANT _FEXP-CLIP-CUT

\ =====================================================================
\  §3 — UIDL File Path (manifest declaration)
\ =====================================================================
\
\  The UI layout lives in fexplorer.uidl — a plain XML file shipped
\  alongside fexplorer.f on the VFS disk.  FEXP-ENTRY sets
\  APP.UIDL-FILE-A/U in the descriptor; the host (app-shell.f or
\  desk.f) opens, reads, and feeds it to UTUI-LOAD before calling
\  INIT-XT.  The applet does no I/O for its own markup.
\
\  Layout (see fexplorer.uidl):
\    uidl (root, arrange=stack → vertical)
\      menubar         — File / Edit / View / Tools menus
\      split ratio=30  — sidebar (explorer) | tabs (details + preview)
\      status          — item count + current path
\      action          — keyboard shortcuts (Ctrl+Q, Ctrl+G, …)

\ =====================================================================
\  §4 — Module State
\ =====================================================================

VARIABLE _FEXP-CURRENT-STATE
0 _FEXP-CURRENT-STATE !
VARIABLE _FEXP-CURRENT-INSTANCE
0 _FEXP-CURRENT-INSTANCE !
CMP-LAYOUT-BEGIN

\ UIDL element handles (set in INIT-XT via UTUI-BY-ID)
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-SIDEBAR    \ <region id="sidebar">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-DETAIL     \ <region id="detail">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-PREVIEW    \ <textarea id="preview">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-TABS       \ <tabs id="tabs">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-SBAR-L     \ <label id="sbar-left">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-SBAR-R     \ <label id="sbar-right">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-SBAR       \ <status id="sbar">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-MBAR       \ <menubar id="mbar">
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-E-SCROLLER   \ <scroll id="scroller">

\ Widget handles (native widgets mounted on UIDL regions)
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-EXPL         \ explorer widget (EXPL-NEW)
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-LIST         \ list widget (LST-NEW)
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-PROMPT       \ status-row command bar
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-PROMPT-RGN   \ caller-owned prompt region
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-PROMPT-MODE
_FEXP-CURRENT-STATE _FEXP-PROMPT-CAP CMP-FIELD: _FEXP-PROMPT-BUF

\ Business state
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-VFS           \ VFS instance
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-SORT          \ sort mode (0=name, 1=size, 2=type)
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CUR-DIR       \ inode of currently displayed directory
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-SEL-IN        \ active inode from either pane

: _FEXP-SELECTED  ( -- inode | 0 )
    _FEXP-SEL-IN @ ;

\ Clipboard
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CLIP-IN       \ clipboard inode
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CLIP-OP       \ clipboard operation (0/1/2)

\ =====================================================================
\  §4b — Theme
\ =====================================================================
\  12 colour slots — 2 per region (fg + bg).  Defaults are a
\  dark-navy palette.  _FEXP-LOAD-THEME overrides any slot that
\  appears in [fexp.theme] of a TOML config.

_FEXP-CURRENT-STATE CMP-CELL: _FTH-SIDEBAR-FG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-SIDEBAR-BG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-DETAIL-FG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-DETAIL-BG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-PREVIEW-FG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-PREVIEW-BG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-MENU-FG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-MENU-BG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-TABS-FG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-TABS-BG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-STATUS-FG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-STATUS-BG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-SCROLL-FG
_FEXP-CURRENT-STATE CMP-CELL: _FTH-SCROLL-BG

: _FEXP-THEME-DEFAULTS  ( -- )
    251 _FTH-SIDEBAR-FG !    17 _FTH-SIDEBAR-BG !
    253 _FTH-DETAIL-FG  !   235 _FTH-DETAIL-BG  !
    250 _FTH-PREVIEW-FG !   233 _FTH-PREVIEW-BG !
    255 _FTH-MENU-FG    !    60 _FTH-MENU-BG    !
    255 _FTH-TABS-FG    !    60 _FTH-TABS-BG    !
     15 _FTH-STATUS-FG  !    21 _FTH-STATUS-BG  !
     68 _FTH-SCROLL-FG  !   235 _FTH-SCROLL-BG  ! ;
\ Helper: try to load a colour key from a TOML table into a variable.
: _FTH-TRY  ( tbl-a tbl-l key-a key-l var -- )
    >R TOML-KEY?
    IF   TOML-GET-STRING TUI-PARSE-COLOR
         IF R> ! EXIT THEN DROP
    ELSE 2DROP
    THEN R> DROP ;

: _FEXP-LOAD-THEME  ( toml-a toml-l -- )
    S" fexp.theme" TOML-FIND-TABLE?
    0= IF 2DROP EXIT THEN
    2DUP S" sidebar-fg"   _FTH-SIDEBAR-FG  _FTH-TRY
    2DUP S" sidebar-bg"   _FTH-SIDEBAR-BG  _FTH-TRY
    2DUP S" detail-fg"    _FTH-DETAIL-FG   _FTH-TRY
    2DUP S" detail-bg"    _FTH-DETAIL-BG   _FTH-TRY
    2DUP S" preview-fg"   _FTH-PREVIEW-FG  _FTH-TRY
    2DUP S" preview-bg"   _FTH-PREVIEW-BG  _FTH-TRY
    2DUP S" menubar-fg"   _FTH-MENU-FG     _FTH-TRY
    2DUP S" menubar-bg"   _FTH-MENU-BG     _FTH-TRY
    2DUP S" tabs-fg"      _FTH-TABS-FG     _FTH-TRY
    2DUP S" tabs-bg"      _FTH-TABS-BG     _FTH-TRY
    2DUP S" status-fg"    _FTH-STATUS-FG   _FTH-TRY
    2DUP S" status-bg"    _FTH-STATUS-BG   _FTH-TRY
    2DUP S" scroll-fg"    _FTH-SCROLL-FG   _FTH-TRY
         S" scroll-bg"    _FTH-SCROLL-BG   _FTH-TRY ;

\ TOML config buffer (kept alive so zero-copy strings remain valid).
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CFG-A
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CFG-L

\ Config file buffer (for reading TOML from VFS).
4096 CONSTANT _FEXP-CFG-CAP
_FEXP-CURRENT-STATE _FEXP-CFG-CAP CMP-FIELD: _FEXP-CFG-BUF

_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CFG-FD

: _FEXP-LOAD-CONFIG  ( -- )
    \ Read fexplorer.toml from VFS
    VFS-CUR >R  _FEXP-VFS @ VFS-USE
    S" tui/applets/fexplorer/fexplorer.toml" VFS-OPEN
    R> VFS-USE
    DUP 0= IF DROP EXIT THEN
    _FEXP-CFG-FD !
    _FEXP-CFG-BUF _FEXP-CFG-CAP _FEXP-CFG-FD @ VFS-READ
    DUP 0= IF DROP _FEXP-CFG-FD @ VFS-CLOSE EXIT THEN
    _FEXP-CFG-BUF SWAP 2DUP _FEXP-CFG-L ! _FEXP-CFG-A !
    _FEXP-LOAD-THEME
    _FEXP-CFG-FD @ VFS-CLOSE ;

\ Apply resolved theme colours to a UIDL element's sidecar.
: _FEXP-THEME-ELEM  ( fg bg elem -- )
    _UTUI-SIDECAR >R
    0 _UTUI-PACK-STYLE R> _UTUI-SC-STYLE! ;

: _FEXP-APPLY-THEME  ( -- )
    _FTH-SIDEBAR-FG @ _FTH-SIDEBAR-BG @ _FEXP-E-SIDEBAR @ _FEXP-THEME-ELEM
    _FTH-DETAIL-FG  @ _FTH-DETAIL-BG  @ _FEXP-E-DETAIL  @ _FEXP-THEME-ELEM
    _FTH-PREVIEW-FG @ _FTH-PREVIEW-BG @ _FEXP-E-PREVIEW @ _FEXP-THEME-ELEM
    _FTH-MENU-FG    @ _FTH-MENU-BG    @ _FEXP-E-MBAR    @ _FEXP-THEME-ELEM
    _FTH-TABS-FG    @ _FTH-TABS-BG    @ _FEXP-E-TABS    @ _FEXP-THEME-ELEM
    _FTH-STATUS-FG  @ _FTH-STATUS-BG  @ S" sbar" UTUI-BY-ID _FEXP-THEME-ELEM
    _FTH-SCROLL-FG  @ _FTH-SCROLL-BG  @ _FEXP-E-SCROLLER @ _FEXP-THEME-ELEM ;

\ =====================================================================
\  §5 — Buffers
\ =====================================================================

_FEXP-CURRENT-STATE _FEXP-MAX-DIR 2 * CELLS CMP-FIELD: _FEXP-ITEMS
_FEXP-CURRENT-STATE _FEXP-MAX-DIR CELLS CMP-FIELD: _FEXP-INODES
_FEXP-CURRENT-STATE _FEXP-MAX-DIR _FEXP-LINE-W * CMP-FIELD: _FEXP-LINES
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CNT

_FEXP-CURRENT-STATE _FEXP-PREVIEW-CAP CMP-FIELD: _FEXP-PREV-BUF
_FEXP-CURRENT-STATE _FEXP-PATH-CAP CMP-FIELD: _FEXP-PATH-BUF
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-PATH-LEN

\ Status bar text scratch
_FEXP-CURRENT-STATE 128 CMP-FIELD: _FEXP-SLEFT
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-SLEFT-L

CMP-LAYOUT-SIZE CONSTANT _FEXP-STATE-SIZE

: _FEXP-ACTIVATE  ( instance -- )
    DUP _FEXP-CURRENT-INSTANCE !
    CINST-STATE _FEXP-CURRENT-STATE ! ;

\ =====================================================================
\  §6 — Utility: path builder (thin wrapper around VFS-INODE-PATH)
\ =====================================================================

: _FEXP-BUILD-PATH  ( inode -- )
    _FEXP-PATH-BUF _FEXP-PATH-CAP VFS-INODE-PATH
    _FEXP-PATH-LEN ! ;

\ =====================================================================
\  §7 — Detail List: populate / format / sort
\ =====================================================================

VARIABLE _FDL-IN
VARIABLE _FDL-I
VARIABLE _FFL-IN  VARIABLE _FFL-IDX  VARIABLE _FFL-DST  VARIABLE _FFL-COL

: _FEXP-FORMAT-LINE  ( inode index -- )
    _FFL-IDX !  _FFL-IN !
    _FFL-IDX @ _FEXP-LINE-W * _FEXP-LINES + _FFL-DST !
    _FFL-DST @ _FEXP-LINE-W 32 FILL
    0 _FFL-COL !
    _FFL-IN @ IN.NAME @ _VFS-STR-GET
    DUP 40 > IF DROP 40 THEN
    DUP >R _FFL-DST @ SWAP CMOVE
    R> _FFL-COL !
    _FFL-IN @ IN.TYPE @ VFS-T-DIR = IF
        S" <DIR>"
    ELSE
        _FFL-IN @ IN.SIZE-LO @ SIZE-FMT
    THEN
    DUP 52 SWAP -
    DUP 44 < IF DROP 44 THEN
    _FFL-DST @ + SWAP CMOVE
    _FFL-IN @ IN.TYPE @ VFS-T-DIR = IF
        S" dir "
    ELSE
        S" file"
    THEN
    _FFL-DST @ 54 + SWAP CMOVE ;

: _FEXP-POPULATE-DIR  ( dir-inode -- )
    _FDL-IN !  0 _FDL-I !
    _FDL-IN @ _FEXP-VFS @ _VFS-ENSURE-CHILDREN
    _FDL-IN @ IN.CHILD @
    BEGIN DUP 0<> _FDL-I @ _FEXP-MAX-DIR < AND WHILE
        DUP _FDL-I @ CELLS _FEXP-INODES + !
        DUP _FDL-I @ _FEXP-FORMAT-LINE
        _FDL-I @ _FEXP-LINE-W * _FEXP-LINES +
        _FDL-I @ 2 * CELLS _FEXP-ITEMS + !
        _FEXP-LINE-W
        _FDL-I @ 2 * CELLS _FEXP-ITEMS + 8 + !
        1 _FDL-I +!
        IN.SIBLING @
    REPEAT DROP
    _FDL-I @ _FEXP-CNT ! ;

\ --- Sort ---

: _FEXP-CMP  ( inode-a inode-b -- n )
    _FEXP-SORT @ CASE
        FEXP-SORT-SIZE OF
            IN.SIZE-LO @ SWAP IN.SIZE-LO @ SWAP -
        ENDOF
        FEXP-SORT-TYPE OF
            OVER IN.TYPE @ OVER IN.TYPE @
            2DUP <> IF
                - NEGATE NIP NIP
            ELSE
                2DROP
                OVER IN.NAME @ _VFS-STR-GET
                >R >R
                IN.NAME @ _VFS-STR-GET
                R> R> 2SWAP
                STR-ICMP NEGATE NIP
            THEN
        ENDOF
        DROP
        OVER IN.NAME @ _VFS-STR-GET
        >R >R
        IN.NAME @ _VFS-STR-GET
        ROT DROP
        R> R> 2SWAP
        STR-ICMP
        0
    ENDCASE ;

VARIABLE _FSW-TMP

: _FEXP-SWAP-ITEMS  ( i j -- )
    2DUP = IF 2DROP EXIT THEN
    DUP CELLS _FEXP-INODES + @ _FSW-TMP !
    OVER CELLS _FEXP-INODES + @  OVER CELLS _FEXP-INODES + !
    _FSW-TMP @ 2 PICK CELLS _FEXP-INODES + !
    DUP 2 * CELLS _FEXP-ITEMS + @ _FSW-TMP !
    OVER 2 * CELLS _FEXP-ITEMS + @  OVER 2 * CELLS _FEXP-ITEMS + !
    _FSW-TMP @ 2 PICK 2 * CELLS _FEXP-ITEMS + !
    DUP 2 * CELLS _FEXP-ITEMS + 8 + @ _FSW-TMP !
    OVER 2 * CELLS _FEXP-ITEMS + 8 + @  OVER 2 * CELLS _FEXP-ITEMS + 8 + !
    _FSW-TMP @ 2 PICK 2 * CELLS _FEXP-ITEMS + 8 + !
    DUP _FEXP-LINE-W * _FEXP-LINES + _FEXP-PREV-BUF _FEXP-LINE-W CMOVE
    OVER _FEXP-LINE-W * _FEXP-LINES +  OVER _FEXP-LINE-W * _FEXP-LINES +
    _FEXP-LINE-W CMOVE
    _FEXP-PREV-BUF  2 PICK _FEXP-LINE-W * _FEXP-LINES +
    _FEXP-LINE-W CMOVE
    \ Update item pointers to track their new line slots
    OVER _FEXP-LINE-W * _FEXP-LINES +  2 PICK 2 * CELLS _FEXP-ITEMS + !
    DUP  _FEXP-LINE-W * _FEXP-LINES +  OVER  2 * CELLS _FEXP-ITEMS + !
    2DROP ;

: _FEXP-SORT-LIST  ( -- )
    _FEXP-CNT @ 2 < IF EXIT THEN
    _FEXP-CNT @ 1- 0
    DO
        _FEXP-CNT @ 1- I 1+
        ?DO
            J CELLS _FEXP-INODES + @
            I CELLS _FEXP-INODES + @
            _FEXP-CMP 0> IF
                J I _FEXP-SWAP-ITEMS
            THEN
        LOOP
    LOOP ;

\ =====================================================================
\  §8 — Preview: load file into textarea
\ =====================================================================

VARIABLE _FPV-FD
VARIABLE _FPV-IN

: _FEXP-LOAD-PREVIEW  ( inode -- )
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP EXIT THEN
    DUP _FPV-IN !
    _FEXP-BUILD-PATH
    VFS-CUR >R  _FEXP-VFS @ VFS-USE
    _FEXP-PATH-BUF _FEXP-PATH-LEN @ VFS-OPEN
    R> VFS-USE
    DUP 0= IF DROP EXIT THEN
    _FPV-FD !
    _FEXP-PREV-BUF _FEXP-PREVIEW-CAP _FPV-FD @ VFS-READ
    \ Set the UIDL textarea content via its materialized widget
    _FEXP-E-PREVIEW @ UTUI-WIDGET@ ?DUP IF
        _FEXP-PREV-BUF -ROT TXTA-SET-TEXT
    ELSE DROP THEN
    _FPV-FD @ VFS-CLOSE
    ASHELL-DIRTY! ;

\ =====================================================================
\  §9 — Clipboard (copy / cut / paste)
\ =====================================================================

VARIABLE _FCP-SRC  VARIABLE _FCP-DST
VARIABLE _FCP-FDS  VARIABLE _FCP-FDD  VARIABLE _FCP-ACT

: FEXP-CLIP-COPY  ( -- )
    _FEXP-SELECTED
    DUP 0= IF DROP EXIT THEN
    _FEXP-CLIP-IN !
    _FEXP-CLIP-COPY _FEXP-CLIP-OP !
    S" Copied to clipboard" 2000 ASHELL-TOAST ;

: FEXP-CLIP-CUT  ( -- )
    _FEXP-SELECTED
    DUP 0= IF DROP EXIT THEN
    _FEXP-CLIP-IN !
    _FEXP-CLIP-CUT _FEXP-CLIP-OP !
    S" Cut to clipboard" 2000 ASHELL-TOAST ;

: FEXP-CLIP-PASTE  ( -- )
    _FEXP-CLIP-OP @ _FEXP-CLIP-NONE = IF
        S" Clipboard empty" 1500 ASHELL-TOAST EXIT
    THEN
    _FEXP-CLIP-IN @ 0= IF
        S" No source" 1500 ASHELL-TOAST EXIT
    THEN
    _FEXP-SELECTED
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = IF ELSE IN.PARENT @ THEN
    _FCP-DST !
    _FEXP-CLIP-IN @ _FCP-SRC !
    _FCP-SRC @ IN.TYPE @ VFS-T-FILE <> IF
        S" Dir copy not supported" 2000 ASHELL-TOAST EXIT
    THEN
    _FCP-SRC @ IN.NAME @ _VFS-STR-GET
    _FEXP-VFS @ V.CWD @ >R
    _FCP-DST @ _FEXP-VFS @ V.CWD !
    2DUP _FEXP-VFS @ VFS-MKFILE
    DUP 0= IF
        DROP 2DROP
        R> _FEXP-VFS @ V.CWD !
        S" Paste failed: mkfile" 2000 ASHELL-TOAST EXIT
    THEN
    DROP
    VFS-CUR >R  _FEXP-VFS @ VFS-USE
    _FCP-SRC @ IN.PARENT @ _FEXP-VFS @ V.CWD !
    _FCP-SRC @ IN.NAME @ _VFS-STR-GET VFS-OPEN _FCP-FDS !
    _FCP-DST @ _FEXP-VFS @ V.CWD !
    VFS-OPEN _FCP-FDD !
    R> VFS-USE
    _FCP-FDS @ 0<> _FCP-FDD @ 0<> AND IF
        BEGIN
            _FEXP-PREV-BUF _FEXP-PREVIEW-CAP _FCP-FDS @ VFS-READ
            _FCP-ACT !
            _FCP-ACT @ 0> WHILE
            _FEXP-PREV-BUF _FCP-ACT @ _FCP-FDD @ VFS-WRITE DROP
        REPEAT
        _FCP-FDS @ VFS-CLOSE
        _FCP-FDD @ VFS-CLOSE
    THEN
    _FEXP-CLIP-OP @ _FEXP-CLIP-CUT = IF
        _FCP-SRC @ IN.PARENT @ _FEXP-VFS @ V.CWD !
        _FCP-SRC @ IN.NAME @ _VFS-STR-GET _FEXP-VFS @ VFS-RM DROP
    THEN
    R> _FEXP-VFS @ V.CWD !
    _FEXP-VFS @ VFS-SYNC DROP
    0 _FEXP-CLIP-IN !  _FEXP-CLIP-NONE _FEXP-CLIP-OP !
    _FEXP-EXPL @ EXPL-REFRESH
    _FEXP-CUR-DIR @ ?DUP IF _FEXP-POPULATE-DIR _FEXP-SORT-LIST THEN
    _FEXP-LIST @ ?DUP IF _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS THEN
    S" Pasted!" 1500 ASHELL-TOAST
    ASHELL-DIRTY! ;

\ =====================================================================
\  §10 — Status bar update (via UIDL label attributes)
\ =====================================================================

: _FEXP-UPDATE-STATUS  ( -- )
    \ Left: "N items"
    _FEXP-CNT @ NUM>STR
    _FEXP-SLEFT SWAP CMOVE
    _FEXP-CNT @ NUM>STR NIP
    S"  items" DUP >R
    ROT _FEXP-SLEFT + SWAP CMOVE
    _FEXP-CNT @ NUM>STR NIP R> +
    _FEXP-SLEFT-L !
    \ Update UIDL label element text= attribute
    _FEXP-E-SBAR-L @ ?DUP IF
        S" text" _FEXP-SLEFT _FEXP-SLEFT-L @ UTUI-SET-ATTR
    THEN
    \ Right: path of selected item
    _FEXP-SELECTED
    DUP 0<> IF
        _FEXP-BUILD-PATH
        _FEXP-E-SBAR-R @ ?DUP IF
            S" text" _FEXP-PATH-BUF _FEXP-PATH-LEN @ UTUI-SET-ATTR
        THEN
    ELSE
        DROP
        _FEXP-E-SBAR-R @ ?DUP IF
            S" text" S" /" UTUI-SET-ATTR
        THEN
    THEN ;

\ =====================================================================
\  §11 — Refresh detail list helper
\ =====================================================================

: _FEXP-REFRESH-DETAIL  ( -- )
    _FEXP-CUR-DIR @ ?DUP IF
        _FEXP-POPULATE-DIR
        _FEXP-SORT-LIST
        _FEXP-LIST @ ?DUP IF
            _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
        THEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY! ;

\ =====================================================================
\  §12 — Explorer callbacks (on-select / on-open)
\ =====================================================================

: _FEXP-ON-SELECT  ( inode explorer -- )
    DROP
    DUP 0= IF DROP EXIT THEN
    DUP _FEXP-SEL-IN !
    DUP IN.TYPE @ VFS-T-DIR = IF
        DUP _FEXP-CUR-DIR !
        _FEXP-POPULATE-DIR
        _FEXP-SORT-LIST
        _FEXP-LIST @ ?DUP IF
            _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
        THEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY! ;

VARIABLE _FOP-REQ

: _FEXP-OPEN-COMPLETE  ( request -- )
    DUP CBR.STATUS @
    CASE
        CBUS-S-OK OF ENDOF
        CBUS-S-NO-HANDLER OF
            S" No application can open this resource" 2200 ASHELL-TOAST
        ENDOF
        CBUS-S-STALE-INSTANCE OF
            S" The target application closed" 1800 ASHELL-TOAST
        ENDOF
        CBUS-S-INVALID OF
            S" The application rejected this resource" 2200 ASHELL-TOAST
        ENDOF
        CBUS-S-NOT-FOUND OF
            S" The resource could not be found" 2200 ASHELL-TOAST
        ENDOF
        CBUS-S-DENIED OF
            S" Permission denied while opening the resource" 2200 ASHELL-TOAST
        ENDOF
        CBUS-S-FAILED OF
            DUP CBR.ERROR-U @ ?DUP IF
                >R DUP CBR.ERROR-A @ R> 2600 ASHELL-TOAST
            ELSE
                S" The application failed to open the resource"
                2200 ASHELL-TOAST
            THEN
        ENDOF
        S" Could not open the resource" 1800 ASHELL-TOAST
    ENDCASE
    CBR-FREE ;

: _FEXP-POST-OPEN  ( inode -- )
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP EXIT THEN
    _FEXP-BUILD-PATH
    CBR-NEW DUP IF
        2DROP S" Could not allocate open request" 1800 ASHELL-TOAST EXIT
    THEN
    DROP _FOP-REQ !
    CPRINC-COMPONENT _FOP-REQ @ CBR.PRINCIPAL !
    _FEXP-PATH-BUF _FEXP-PATH-LEN @ _FOP-REQ @ CBR.ARGS IRES-VFS! IF
        _FOP-REQ @ CBR-FREE
        S" Resource path is too large" 1800 ASHELL-TOAST EXIT
    THEN
    ['] _FEXP-OPEN-COMPLETE _FOP-REQ @ CBR.COMPLETE-XT !
    S" resource.open" _FOP-REQ @ _FEXP-CURRENT-INSTANCE @
    CINST-POST-INTENT
    DUP CBUS-S-OK <> IF
        DROP _FOP-REQ @ CBR-FREE
        S" Open is unavailable outside Desk" 1800 ASHELL-TOAST
    ELSE DROP THEN ;

: _FEXP-DO-OPEN  ( elem -- )
    DROP _FEXP-SELECTED _FEXP-POST-OPEN ;

: _FEXP-ON-OPEN  ( inode explorer -- )
    DROP
    DUP 0= IF DROP EXIT THEN
    DUP _FEXP-SEL-IN !
    DUP IN.TYPE @ VFS-T-FILE = IF
        DUP _FEXP-LOAD-PREVIEW
        _FEXP-POST-OPEN
        _FEXP-E-TABS @ ?DUP IF 1 SWAP UTUI-TAB-SELECT THEN
    ELSE
        DUP _FEXP-CUR-DIR !
        _FEXP-POPULATE-DIR
        _FEXP-SORT-LIST
        _FEXP-LIST @ ?DUP IF
            _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
        THEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY! ;

: _FEXP-ON-LIST-SEL  ( index widget -- )
    DROP
    DUP _FEXP-CNT @ >= IF DROP EXIT THEN
    CELLS _FEXP-INODES + @
    DUP 0= IF DROP EXIT THEN
    DUP _FEXP-SEL-IN !
    DUP IN.TYPE @ VFS-T-FILE = IF
        _FEXP-LOAD-PREVIEW
        _FEXP-E-TABS @ ?DUP IF 1 SWAP UTUI-TAB-SELECT THEN
    ELSE DROP THEN
    _FEXP-UPDATE-STATUS ;

VARIABLE _FPS-MODE
VARIABLE _FPS-LA
VARIABLE _FPS-LU
VARIABLE _FPS-IA
VARIABLE _FPS-IU

: _FEXP-SHOW-PROMPT  ( mode label-a label-u initial-a initial-u -- )
    _FPS-IU ! _FPS-IA ! _FPS-LU ! _FPS-LA ! _FPS-MODE !
    _FEXP-PROMPT @ 0= IF EXIT THEN
    _FPS-MODE @ _FEXP-PROMPT-MODE !
    _FPS-LA @ _FPS-LU @ _FPS-IA @ _FPS-IU @
        _FEXP-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _FEXP-TARGET-DIR  ( -- inode | 0 )
    _FEXP-SELECTED
    DUP 0= IF DROP _FEXP-CUR-DIR @ EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = IF EXIT THEN
    IN.PARENT @ ;

VARIABLE _FMU-A
VARIABLE _FMU-U
VARIABLE _FMU-TYPE
VARIABLE _FMU-DIR
VARIABLE _FMU-OLD-CWD
VARIABLE _FMU-OK

: _FEXP-CREATE-NAMED  ( name-a name-u type -- flag )
    _FMU-TYPE ! _FMU-U ! _FMU-A !
    _FMU-U @ 0= _FMU-U @ 23 > OR IF FALSE EXIT THEN
    _FEXP-TARGET-DIR DUP 0= IF DROP FALSE EXIT THEN _FMU-DIR !
    _FEXP-VFS @ V.CWD @ _FMU-OLD-CWD !
    _FMU-DIR @ _FEXP-VFS @ V.CWD !
    _FMU-TYPE @ VFS-T-DIR = IF
        _FMU-A @ _FMU-U @ _FEXP-VFS @ VFS-MKDIR 0=
    ELSE
        _FMU-A @ _FMU-U @ _FEXP-VFS @ VFS-MKFILE 0<>
    THEN
    _FMU-OK !
    _FMU-OLD-CWD @ _FEXP-VFS @ V.CWD !
    _FMU-OK @ IF
        _FMU-A @ _FMU-U @ _FMU-DIR @ _VFS-FIND-CHILD
        DUP _FEXP-SEL-IN !
        _FEXP-VFS @ VFS-SYNC IF 0 _FMU-OK ! THEN
        _FEXP-EXPL @ EXPL-REFRESH
        _FEXP-REFRESH-DETAIL
    THEN
    _FMU-OK @ ;

VARIABLE _FMR-IN

: _FEXP-RENAME-NAMED  ( name-a name-u -- flag )
    DUP 0= OVER 23 > OR IF 2DROP FALSE EXIT THEN
    _FEXP-SELECTED DUP 0= IF DROP 2DROP FALSE EXIT THEN
    _FMR-IN !
    _FMR-IN @ _FEXP-VFS @ VFS-RENAME IF FALSE EXIT THEN
    _FEXP-VFS @ VFS-SYNC IF FALSE EXIT THEN
    _FEXP-EXPL @ EXPL-REFRESH
    _FEXP-REFRESH-DETAIL
    TRUE ;

VARIABLE _FDEL-IN
VARIABLE _FDEL-PARENT
VARIABLE _FDEL-A
VARIABLE _FDEL-U
VARIABLE _FDEL-OLD-CWD

: _FEXP-DELETE-SELECTED  ( -- flag )
    _FEXP-SELECTED DUP 0= IF DROP FALSE EXIT THEN
    DUP _FEXP-VFS @ V.ROOT @ = IF DROP FALSE EXIT THEN _FDEL-IN !
    S" Delete the selected item?" DLG-CONFIRM 0= IF FALSE EXIT THEN
    _FDEL-IN @ IN.PARENT @ _FDEL-PARENT !
    _FDEL-IN @ IN.NAME @ _VFS-STR-GET _FDEL-U ! _FDEL-A !
    _FEXP-VFS @ V.CWD @ _FDEL-OLD-CWD !
    _FDEL-PARENT @ _FEXP-VFS @ V.CWD !
    _FDEL-A @ _FDEL-U @ _FEXP-VFS @ VFS-RM
    _FDEL-OLD-CWD @ _FEXP-VFS @ V.CWD !
    IF FALSE EXIT THEN
    _FEXP-VFS @ VFS-SYNC IF FALSE EXIT THEN
    _FDEL-PARENT @ _FEXP-SEL-IN !
    _FEXP-EXPL @ EXPL-REFRESH
    _FEXP-REFRESH-DETAIL
    TRUE ;

\ =====================================================================
\  §13 — Action handlers (registered via UTUI-DO!)
\ =====================================================================
\
\  All action handlers have signature ( elem -- ) per UTUI-DO! contract.
\  We ignore the element argument since our actions are global.

: _FEXP-DO-QUIT       ( elem -- ) DROP ASHELL-QUIT ;
: _FEXP-DO-NEW-FILE   ( elem -- )
    DROP _FEXP-PRM-NEW-FILE S" New file:" 0 0 _FEXP-SHOW-PROMPT ;
: _FEXP-DO-NEW-DIR    ( elem -- )
    DROP _FEXP-PRM-NEW-DIR S" New folder:" 0 0 _FEXP-SHOW-PROMPT ;
: _FEXP-DO-DELETE     ( elem -- )
    DROP _FEXP-DELETE-SELECTED 0= IF
        S" Delete cancelled or failed" 1800 ASHELL-TOAST
    THEN ;
: _FEXP-DO-RENAME     ( elem -- )
    DROP
    _FEXP-SELECTED DUP 0= IF DROP EXIT THEN
    _FMR-IN !
    _FEXP-PRM-RENAME S" Rename:"
    _FMR-IN @ IN.NAME @ _VFS-STR-GET _FEXP-SHOW-PROMPT ;
: _FEXP-DO-REFRESH    ( elem -- ) DROP _FEXP-EXPL @ EXPL-REFRESH   _FEXP-REFRESH-DETAIL ;
: _FEXP-DO-COPY       ( elem -- ) DROP FEXP-CLIP-COPY ;
: _FEXP-DO-CUT        ( elem -- ) DROP FEXP-CLIP-CUT ;
: _FEXP-DO-PASTE      ( elem -- ) DROP FEXP-CLIP-PASTE ;

: _FEXP-DO-TOGGLE-HIDDEN  ( elem -- )
    DROP
    _FEXP-EXPL @ DUP EXPL-SHOW-HIDDEN? 0= SWAP EXPL-SHOW-HIDDEN!
    _FEXP-EXPL @ EXPL-REFRESH _FEXP-REFRESH-DETAIL ;

: _FEXP-DO-SORT-NAME  ( elem -- ) DROP FEXP-SORT-NAME _FEXP-SORT ! _FEXP-SORT-LIST _FEXP-REFRESH-DETAIL ;
: _FEXP-DO-SORT-SIZE  ( elem -- ) DROP FEXP-SORT-SIZE _FEXP-SORT ! _FEXP-SORT-LIST _FEXP-REFRESH-DETAIL ;
: _FEXP-DO-SORT-TYPE  ( elem -- ) DROP FEXP-SORT-TYPE _FEXP-SORT ! _FEXP-SORT-LIST _FEXP-REFRESH-DETAIL ;

: _FEXP-DO-EXPAND-ALL   ( elem -- ) DROP _FEXP-EXPL @ EXPL-EXPAND-ALL   ASHELL-DIRTY! ;
: _FEXP-DO-COLLAPSE-ALL ( elem -- ) DROP _FEXP-EXPL @ EXPL-COLLAPSE-ALL ASHELL-DIRTY! ;

: _FEXP-DO-DETAILS  ( elem -- )
    DROP _FEXP-E-TABS @ ?DUP IF 0 SWAP UTUI-TAB-SELECT THEN ;

: _FEXP-DO-PREVIEW  ( elem -- )
    DROP _FEXP-E-TABS @ ?DUP IF 1 SWAP UTUI-TAB-SELECT THEN ;

: _FEXP-DO-PARENT-DIR  ( elem -- )
    DROP
    _FEXP-CUR-DIR @ ?DUP IF
        IN.PARENT @ ?DUP IF
            DUP _FEXP-EXPL @ EXPL-ROOT!
            DUP _FEXP-CUR-DIR !
            _FEXP-POPULATE-DIR _FEXP-SORT-LIST
            _FEXP-LIST @ ?DUP IF _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS THEN
            _FEXP-UPDATE-STATUS
            ASHELL-DIRTY!
        THEN
    THEN ;

VARIABLE _FEXP-PROP-IN
VARIABLE _FGP-IN

: _FEXP-GOTO-PATH  ( path-a path-u -- flag )
    _FEXP-VFS @ VFS-RESOLVE
    DUP 0= IF DROP 0 EXIT THEN
    DUP _FGP-IN !
    DUP _FEXP-SEL-IN !
    IN.TYPE @ VFS-T-DIR = IF
        _FGP-IN @ DUP _FEXP-EXPL @ EXPL-ROOT!
        DUP _FEXP-CUR-DIR !
        _FEXP-POPULATE-DIR
        _FEXP-SORT-LIST
        _FEXP-LIST @ ?DUP IF
            _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
        THEN
    ELSE
        _FGP-IN @ _FEXP-LOAD-PREVIEW
        _FEXP-E-TABS @ ?DUP IF
            1 SWAP UTUI-TAB-SELECT
        THEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY!
    -1 ;

VARIABLE _FSUB-A
VARIABLE _FSUB-U
VARIABLE _FSUB-MODE

: _FEXP-PROMPT-SUBMIT  ( prompt -- )
    PRM-GET-TEXT _FSUB-U ! _FSUB-A !
    _FEXP-E-SBAR @ ?DUP IF UIDL-DIRTY! THEN
    _FEXP-PROMPT-MODE @ _FSUB-MODE !
    _FEXP-PRM-NONE _FEXP-PROMPT-MODE !
    _FSUB-U @ 0= IF EXIT THEN
    _FSUB-MODE @ CASE
        _FEXP-PRM-GOTO OF
            _FSUB-A @ _FSUB-U @ _FEXP-GOTO-PATH 0= IF
                S" Path not found" 2000 ASHELL-TOAST
            THEN
        ENDOF
        _FEXP-PRM-NEW-FILE OF
            _FSUB-A @ _FSUB-U @ VFS-T-FILE _FEXP-CREATE-NAMED IF
                S" File created" 1400 ASHELL-TOAST
            ELSE
                S" Could not create file" 2200 ASHELL-TOAST
            THEN
        ENDOF
        _FEXP-PRM-NEW-DIR OF
            _FSUB-A @ _FSUB-U @ VFS-T-DIR _FEXP-CREATE-NAMED IF
                S" Folder created" 1400 ASHELL-TOAST
            ELSE
                S" Could not create folder" 2200 ASHELL-TOAST
            THEN
        ENDOF
        _FEXP-PRM-RENAME OF
            _FSUB-A @ _FSUB-U @ _FEXP-RENAME-NAMED IF
                S" Renamed" 1400 ASHELL-TOAST
            ELSE
                S" Could not rename" 2200 ASHELL-TOAST
            THEN
        ENDOF
    ENDCASE
    ASHELL-DIRTY! ;

: _FEXP-PROMPT-CANCEL  ( prompt -- )
    DROP
    _FEXP-PRM-NONE _FEXP-PROMPT-MODE !
    _FEXP-E-SBAR @ ?DUP IF UIDL-DIRTY! THEN
    ASHELL-DIRTY! ;

: _FEXP-DO-GOTO  ( elem -- )
    DROP
    _FEXP-CUR-DIR @ _FEXP-BUILD-PATH
    _FEXP-PRM-GOTO S" Go to:" _FEXP-PATH-BUF _FEXP-PATH-LEN @
    _FEXP-SHOW-PROMPT ;

: _FEXP-DO-PROPS  ( elem -- )
    DROP
    _FEXP-SELECTED
    DUP 0= IF DROP EXIT THEN
    _FEXP-PROP-IN !
    _FEXP-PROP-IN @ _FEXP-BUILD-PATH
    \ Build info string in preview buffer (reuse temporarily)
    _FEXP-PREV-BUF 0
    S" Path: " 2 PICK 2 PICK + SWAP CMOVE 6 +
    _FEXP-PATH-BUF OVER 2 PICK + SWAP _FEXP-PATH-LEN @ CMOVE
    _FEXP-PATH-LEN @ +
    S"   Type: " 2 PICK 2 PICK + SWAP CMOVE 8 +
    _FEXP-PROP-IN @ IN.TYPE @ VFS-T-DIR = IF
        S" dir" 2 PICK 2 PICK + SWAP CMOVE 3 +
    ELSE
        S" file" 2 PICK 2 PICK + SWAP CMOVE 4 +
    THEN
    S"   Size: " 2 PICK 2 PICK + SWAP CMOVE 8 +
    _FEXP-PROP-IN @ IN.SIZE-LO @ SIZE-FMT
    2 PICK 4 PICK + >R
    R> SWAP DUP >R CMOVE
    R> +
    NIP
    _FEXP-PREV-BUF SWAP DLG-INFO ;

\ =====================================================================
\  §14 — INIT callback ("document ready")
\ =====================================================================

: FEXP-INIT-CB  ( instance -- )
    _FEXP-ACTIVATE
    \ Initialize business state
    FEXP-SORT-NAME _FEXP-SORT !
    0 _FEXP-CNT !
    0 _FEXP-CLIP-IN !
    _FEXP-CLIP-NONE _FEXP-CLIP-OP !
    0 _FEXP-CUR-DIR !
    0 _FEXP-SEL-IN !
    0 _FEXP-PROMPT !
    0 _FEXP-PROMPT-RGN !
    _FEXP-PRM-NONE _FEXP-PROMPT-MODE !

    \ Get VFS
    VFS-CUR DUP 0= ABORT" fexplorer: no VFS available"
    _FEXP-VFS !

    \ Find UIDL elements by ID
    S" sidebar"    UTUI-BY-ID _FEXP-E-SIDEBAR !
    S" detail"     UTUI-BY-ID _FEXP-E-DETAIL !
    S" preview"    UTUI-BY-ID _FEXP-E-PREVIEW !
    S" tabs"       UTUI-BY-ID _FEXP-E-TABS !
    S" sbar-left"  UTUI-BY-ID _FEXP-E-SBAR-L !
    S" sbar-right" UTUI-BY-ID _FEXP-E-SBAR-R !
    S" sbar"       UTUI-BY-ID _FEXP-E-SBAR !
    S" mbar"       UTUI-BY-ID _FEXP-E-MBAR !
    S" scroller"   UTUI-BY-ID _FEXP-E-SCROLLER !

    \ Load TOML config and apply theme colours to UIDL sidecars
    _FEXP-THEME-DEFAULTS
    _FEXP-LOAD-CONFIG
    _FEXP-APPLY-THEME

    \ Create a command bar that overlays the status row while active.
    _FEXP-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW
        DUP _FEXP-PROMPT-RGN !
        _FEXP-PROMPT-BUF _FEXP-PROMPT-CAP PRM-NEW
        DUP _FEXP-PROMPT !
        ['] _FEXP-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
        ['] _FEXP-PROMPT-CANCEL OVER PRM-ON-CANCEL
        _FTH-STATUS-FG @ _FTH-STATUS-BG @ ROT PRM-COLORS!
    THEN

    \ Create explorer widget and mount on sidebar region
    _FEXP-E-SIDEBAR @ UTUI-ELEM-RGN     ( row col h w )
    RGN-NEW                              ( rgn )
    _FEXP-VFS @
    _FEXP-VFS @ V.ROOT @
    EXPL-NEW
    _FEXP-EXPL !
    ['] _FEXP-ON-SELECT _FEXP-EXPL @ EXPL-ON-SELECT
    ['] _FEXP-ON-OPEN   _FEXP-EXPL @ EXPL-ON-OPEN
    _FEXP-EXPL @ _FEXP-E-SIDEBAR @ UTUI-WIDGET-SET

    \ Create list widget and mount on detail region
    _FEXP-E-DETAIL @ UTUI-ELEM-RGN      ( row col h w )
    RGN-NEW                              ( rgn )
    _FEXP-ITEMS 0 LST-NEW
    _FEXP-LIST !
    ['] _FEXP-ON-LIST-SEL _FEXP-LIST @ LST-ON-SELECT
    _FEXP-LIST @ _FEXP-E-DETAIL @ UTUI-WIDGET-SET

    \ Register all named actions
    S" quit"           ['] _FEXP-DO-QUIT           UTUI-DO!
    S" open"           ['] _FEXP-DO-OPEN           UTUI-DO!
    S" new-file"       ['] _FEXP-DO-NEW-FILE       UTUI-DO!
    S" new-dir"        ['] _FEXP-DO-NEW-DIR        UTUI-DO!
    S" delete"         ['] _FEXP-DO-DELETE          UTUI-DO!
    S" rename"         ['] _FEXP-DO-RENAME          UTUI-DO!
    S" refresh"        ['] _FEXP-DO-REFRESH         UTUI-DO!
    S" copy"           ['] _FEXP-DO-COPY            UTUI-DO!
    S" cut"            ['] _FEXP-DO-CUT             UTUI-DO!
    S" paste"          ['] _FEXP-DO-PASTE           UTUI-DO!
    S" toggle-hidden"  ['] _FEXP-DO-TOGGLE-HIDDEN   UTUI-DO!
    S" sort-name"      ['] _FEXP-DO-SORT-NAME       UTUI-DO!
    S" sort-size"      ['] _FEXP-DO-SORT-SIZE       UTUI-DO!
    S" sort-type"      ['] _FEXP-DO-SORT-TYPE       UTUI-DO!
    S" expand-all"     ['] _FEXP-DO-EXPAND-ALL      UTUI-DO!
    S" collapse-all"   ['] _FEXP-DO-COLLAPSE-ALL    UTUI-DO!
    S" goto"           ['] _FEXP-DO-GOTO            UTUI-DO!
    S" props"          ['] _FEXP-DO-PROPS           UTUI-DO!
    S" parent-dir"     ['] _FEXP-DO-PARENT-DIR      UTUI-DO!
    S" show-details"   ['] _FEXP-DO-DETAILS         UTUI-DO!
    S" show-preview"   ['] _FEXP-DO-PREVIEW         UTUI-DO!

    \ Populate initial directory listing
    _FEXP-VFS @ V.ROOT @ DUP _FEXP-CUR-DIR !
    _FEXP-VFS @ V.ROOT @ _FEXP-SEL-IN !
    _FEXP-POPULATE-DIR
    _FEXP-SORT-LIST
    _FEXP-LIST @ _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS

    _FEXP-UPDATE-STATUS ;

\ =====================================================================
\  §15 — EVENT callback
\ =====================================================================
\
\  The app EVENT-XT gets first crack.  We handle only business logic
\  that UIDL can't express (e.g., forwarding keys to mounted widgets).
\  For everything else we return 0 and let the shell route to UIDL.

\ FEXP-EVENT-CB — app-level key handling.
\ Widget dispatch is now handled by the UIDL engine's _UTUI-H-REGION,
\ which automatically routes keys to mounted widgets on focused regions.
: FEXP-EVENT-CB  ( ev instance -- flag )
    _FEXP-ACTIVATE
    _FEXP-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN
        DROP
    THEN
    DROP 0 ;

: FEXP-PAINT-CB  ( instance -- )
    _FEXP-ACTIVATE
    _FEXP-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN
    DROP
    _FEXP-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN _FEXP-PROMPT @ PRM-SET-BOUNDS
    THEN
    _FEXP-PROMPT @ WDG-DRAW ;

\ =====================================================================
\  §16 — SHUTDOWN callback
\ =====================================================================

: FEXP-SHUTDOWN-CB  ( instance -- )
    _FEXP-ACTIVATE
    \ Detach widgets from UIDL elements before freeing
    _FEXP-E-SIDEBAR @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _FEXP-E-DETAIL @  ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    \ Free native widgets
    _FEXP-EXPL @ ?DUP IF EXPL-FREE THEN
    _FEXP-LIST @ ?DUP IF LST-FREE THEN
    _FEXP-PROMPT @ ?DUP IF PRM-FREE THEN
    _FEXP-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    \ (UIDL buffer is owned and freed by the host shell/desk)
    \ Zero handles
    0 _FEXP-EXPL !  0 _FEXP-LIST !
    0 _FEXP-PROMPT ! 0 _FEXP-PROMPT-RGN !
    0 _FEXP-E-SIDEBAR !  0 _FEXP-E-DETAIL !
    0 _FEXP-E-PREVIEW !  0 _FEXP-E-TABS !
    0 _FEXP-E-SBAR-L !   0 _FEXP-E-SBAR-R !
    0 _FEXP-E-MBAR !  0 _FEXP-E-SCROLLER ! ;

\ =====================================================================
\  §17 — Entry Point & Standalone Runner
\ =====================================================================

CREATE _FEXP-RESOURCE-SCHEMA CS-SIZE ALLOT
CREATE _FEXP-OPTIONAL-RESOURCE-SCHEMA CS-SIZE ALLOT
2 CONSTANT _FEXP-CAP-COUNT
CREATE FEXP-CAPS _FEXP-CAP-COUNT CAP-DESC * ALLOT
: FEXP-CAP-REVEAL    ( -- cap ) FEXP-CAPS ;
: FEXP-CAP-SELECTED  ( -- cap ) FEXP-CAPS CAP-DESC + ;

CREATE FEXP-INTENTS CINT-DESC-SIZE ALLOT

VARIABLE _FRV-IN
VARIABLE _FRV-DIR

: _FEXP-REVEAL-PATH  ( path-a path-u -- ior )
    _FEXP-VFS @ VFS-RESOLVE DUP 0= IF DROP -1 EXIT THEN
    DUP _FRV-IN !
    DUP IN.TYPE @ VFS-T-DIR = IF DUP ELSE IN.PARENT @ THEN
    DUP 0= IF DROP -1 EXIT THEN _FRV-DIR !
    _FRV-DIR @ _FEXP-CUR-DIR !
    _FRV-IN @ _FEXP-SEL-IN !
    _FRV-DIR @ _FEXP-POPULATE-DIR
    _FEXP-SORT-LIST
    _FEXP-LIST @ ?DUP IF
        _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
        _FEXP-CNT @ 0 ?DO
            I CELLS _FEXP-INODES + @ _FRV-IN @ = IF
                I _FEXP-LIST @ LST-SELECT
                I _FEXP-LIST @ LST-SCROLL-TO
                LEAVE
            THEN
        LOOP
    THEN
    _FRV-IN @ IN.TYPE @ VFS-T-FILE = IF _FRV-IN @ _FEXP-LOAD-PREVIEW THEN
    _FEXP-UPDATE-STATUS ASHELL-DIRTY!
    0 ;

VARIABLE _FRH-A
VARIABLE _FRH-U

: _FEXP-CAP-REVEAL-HANDLER  ( request instance -- status )
    _FEXP-ACTIVATE
    DUP CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@
    IRES-VFS-PATH 0= IF 2DROP DROP CBUS-S-INVALID EXIT THEN
    _FRH-U ! _FRH-A !
    _FRH-A @ _FRH-U @ _FEXP-REVEAL-PATH IF
        DROP CBUS-S-NOT-FOUND EXIT
    THEN
    DUP CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@
    ROT CBR.RESULT CV-RESOURCE! IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _FEXP-CAP-SELECTED-HANDLER  ( request instance -- status )
    _FEXP-ACTIVATE
    _FEXP-SELECTED DUP 0= IF
        DROP DUP CBR.RESULT CV-NULL! DROP CBUS-S-OK EXIT
    THEN
    _FEXP-BUILD-PATH
    _FEXP-PATH-BUF _FEXP-PATH-LEN @ ROT CBR.RESULT IRES-VFS!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _FEXP-CAP-SETUP  ( -- )
    _FEXP-RESOURCE-SCHEMA CS-INIT
    CV-T-RESOURCE _FEXP-RESOURCE-SCHEMA CS-ALLOW!
    516 _FEXP-RESOURCE-SCHEMA CS-MAX-LEN!
    _FEXP-OPTIONAL-RESOURCE-SCHEMA CS-INIT
    CV-T-NULL CS-TYPE-BIT CV-T-RESOURCE CS-TYPE-BIT OR
    _FEXP-OPTIONAL-RESOURCE-SCHEMA CS-ALLOW-MASK!
    516 _FEXP-OPTIONAL-RESOURCE-SCHEMA CS-MAX-LEN!

    FEXP-CAP-REVEAL CAP-DESC-INIT
    CAP-K-COMMAND FEXP-CAP-REVEAL CAP.KIND !
    S" fexplorer.resource.reveal"
    FEXP-CAP-REVEAL CAP.ID-U ! FEXP-CAP-REVEAL CAP.ID-A !
    S" Reveal resource"
    FEXP-CAP-REVEAL CAP.TITLE-U ! FEXP-CAP-REVEAL CAP.TITLE-A !
    S" Navigate to and select a VFS resource"
    FEXP-CAP-REVEAL CAP.DESC-U ! FEXP-CAP-REVEAL CAP.DESC-A !
    _FEXP-RESOURCE-SCHEMA FEXP-CAP-REVEAL CAP.IN-SCHEMA !
    _FEXP-RESOURCE-SCHEMA FEXP-CAP-REVEAL CAP.OUT-SCHEMA !
    CAP-E-NAVIGATE FEXP-CAP-REVEAL CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR FEXP-CAP-REVEAL CAP.FLAGS !
    ['] _FEXP-CAP-REVEAL-HANDLER FEXP-CAP-REVEAL CAP.HANDLER-XT !

    FEXP-CAP-SELECTED CAP-DESC-INIT
    CAP-K-RESOURCE FEXP-CAP-SELECTED CAP.KIND !
    S" fexplorer.resource.selected"
    FEXP-CAP-SELECTED CAP.ID-U ! FEXP-CAP-SELECTED CAP.ID-A !
    S" Selected resource"
    FEXP-CAP-SELECTED CAP.TITLE-U ! FEXP-CAP-SELECTED CAP.TITLE-A !
    S" Read the selected VFS resource"
    FEXP-CAP-SELECTED CAP.DESC-U ! FEXP-CAP-SELECTED CAP.DESC-A !
    _FEXP-OPTIONAL-RESOURCE-SCHEMA FEXP-CAP-SELECTED CAP.OUT-SCHEMA !
    CAP-E-OBSERVE FEXP-CAP-SELECTED CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
    FEXP-CAP-SELECTED CAP.FLAGS !
    ['] _FEXP-CAP-SELECTED-HANDLER FEXP-CAP-SELECTED CAP.HANDLER-XT !

    FEXP-INTENTS CINT-DESC-INIT
    S" resource.reveal"
    FEXP-INTENTS CINTD.ID-U ! FEXP-INTENTS CINTD.ID-A !
    FEXP-CAP-REVEAL FEXP-INTENTS CINTD.CAP !
    100 FEXP-INTENTS CINTD.PRIORITY ! ;

CREATE FEXP-COMP-DESC COMP-DESC ALLOT

: _FEXP-COMP-SETUP  ( -- )
    _FEXP-CAP-SETUP
    FEXP-COMP-DESC COMP-DESC-INIT
    S" org.akashic.fexplorer"
    FEXP-COMP-DESC COMP.ID-U ! FEXP-COMP-DESC COMP.ID-A !
    S" 1.0.0"
    FEXP-COMP-DESC COMP.VERSION-U ! FEXP-COMP-DESC COMP.VERSION-A !
    _FEXP-STATE-SIZE FEXP-COMP-DESC COMP.STATE-SIZE !
    FEXP-CAPS FEXP-COMP-DESC COMP.CAPS-A !
    _FEXP-CAP-COUNT FEXP-COMP-DESC COMP.CAPS-N !
    FEXP-INTENTS FEXP-COMP-DESC COMP.INTENTS-A !
    1 FEXP-COMP-DESC COMP.INTENTS-N ! ;

: FEXP-ENTRY  ( desc -- )
    _FEXP-COMP-SETUP
    DUP APP-DESC-INIT
    FEXP-COMP-DESC      OVER APP.COMP-DESC !
    ['] FEXP-INIT-CB     OVER APP.INIT-XT !
    ['] FEXP-EVENT-CB    OVER APP.EVENT-XT !
    0                    OVER APP.TICK-XT !
    ['] FEXP-PAINT-CB    OVER APP.PAINT-XT !
    ['] FEXP-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _FEXP-ACTIVATE   OVER APP.ACTIVATE-XT !
    \ S" pushes two values — switch to R-stack for desc
    S" tui/applets/fexplorer/fexplorer.uidl"
                         ROT DUP >R
                         APP.UIDL-FILE-U !
                         R@ APP.UIDL-FILE-A !
    0                    R@ APP.WIDTH !
    0                    R@ APP.HEIGHT !
    S" File Explorer"    R@ APP.TITLE-U !
                         R> APP.TITLE-A ! ;

CREATE FEXP-DESC  APP-DESC ALLOT

: FEXP-RUN  ( -- )
    FEXP-DESC FEXP-ENTRY
    FEXP-DESC ASHELL-RUN ;

\ =====================================================================
\  §18 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _fexp-guard

' FEXP-ENTRY       CONSTANT _fexp-entry-xt
' FEXP-RUN         CONSTANT _fexp-run-xt
' FEXP-CLIP-COPY   CONSTANT _fexp-clip-copy-xt
' FEXP-CLIP-CUT    CONSTANT _fexp-clip-cut-xt
' FEXP-CLIP-PASTE  CONSTANT _fexp-clip-paste-xt

: FEXP-ENTRY       _fexp-entry-xt      _fexp-guard WITH-GUARD ;
: FEXP-RUN         _fexp-run-xt        _fexp-guard WITH-GUARD ;
: FEXP-CLIP-COPY   _fexp-clip-copy-xt  _fexp-guard WITH-GUARD ;
: FEXP-CLIP-CUT    _fexp-clip-cut-xt   _fexp-guard WITH-GUARD ;
: FEXP-CLIP-PASTE  _fexp-clip-paste-xt _fexp-guard WITH-GUARD ;
[THEN] [THEN]
