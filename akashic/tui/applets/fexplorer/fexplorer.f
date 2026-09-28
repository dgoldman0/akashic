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
\   - Detail table (LST-* widget mounted on <region id="detail">):
\     Name, Size, and Type columns; opening a row enters a directory or
\     opens a file with its application
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
REQUIRE ../../../utils/fs/vfs-access.f
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

512 CONSTANT _FEXP-PATH-CAP       \ path buffer capacity
32768 CONSTANT _FEXP-PREVIEW-CAP  \ preview buffer 32 KiB
 4096 CONSTANT _FEXP-CAP-TEXT-MAX \ Agent-visible UTF-8 preview bytes
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

\ Paste transaction results.  Expected storage failures stay in-band so a
\ failed file operation cannot unwind the Desk event loop.
0  CONSTANT _FCP-S-OK
1  CONSTANT _FCP-S-SOURCE
2  CONSTANT _FCP-S-DESTINATION
3  CONSTANT _FCP-S-SAME
4  CONSTANT _FCP-S-CONFLICT
5  CONSTANT _FCP-S-CREATE
6  CONSTANT _FCP-S-IO
7  CONSTANT _FCP-S-VERIFY
8  CONSTANT _FCP-S-DELETE
9  CONSTANT _FCP-S-DELETE-SYNC
10 CONSTANT _FCP-S-ROLLBACK
11 CONSTANT _FCP-S-INTERNAL

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
_FEXP-CURRENT-STATE VFA-SCOPE-SIZE CMP-FIELD: _FEXP-PREVIEW-SCOPE
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-SORT          \ sort mode (0=name, 1=size, 2=type)

\ The listed directory and the selection, from either pane, are kept as
\ paths, never as VFS entries.  Another applet may replace or remove an
\ entry at any time (a save that renames a new copy over a file frees the
\ old entry), so an entry is looked up by its path when it is used.
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-DIR-LEN
_FEXP-CURRENT-STATE _FEXP-PATH-CAP CMP-FIELD: _FEXP-DIR-PATH
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-SEL-LEN       \ 0 when nothing is selected
_FEXP-CURRENT-STATE _FEXP-PATH-CAP CMP-FIELD: _FEXP-SEL-PATH

\ _FEXP-SELECTED ( -- inode | 0 )
\   The selected entry as it is now, valid until the next VFS operation.
: _FEXP-SELECTED  ( -- inode | 0 )
    _FEXP-SEL-LEN @ 0= IF 0 EXIT THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-VFS @ VFS-RESOLVE ;

\ Clipboard
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CLIP-OP       \ clipboard operation (0/1/2)
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CLIP-PATH-LEN
_FEXP-CURRENT-STATE _FEXP-PATH-CAP CMP-FIELD: _FEXP-CLIP-PATH

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

VARIABLE _FOV-A
VARIABLE _FOV-U
VARIABLE _FOV-OLD

: _FEXP-OPEN-VFS-BODY  ( -- fd|0 )
    VFS-CUR _FOV-OLD !
    _FEXP-VFS @ VFS-USE
    _FOV-A @ _FOV-U @ VFS-OPEN
    _FOV-OLD @ VFS-USE ;

: _FEXP-OPEN-VFS  ( path-a path-u -- fd|0 )
    _FOV-U ! _FOV-A !
    ['] _FEXP-OPEN-VFS-BODY VFS-TRANSACTION ;

: _FEXP-LOAD-CONFIG  ( -- )
    \ Read fexplorer.toml from VFS
    S" tui/applets/fexplorer/fexplorer.toml" _FEXP-OPEN-VFS
    DUP 0= IF DROP EXIT THEN
    _FEXP-CFG-FD !
    _FEXP-CFG-FD @ VFS-SIZE DUP 0= OVER _FEXP-CFG-CAP > OR IF
        DROP _FEXP-CFG-FD @ VFS-CLOSE EXIT
    THEN
    DUP >R _FEXP-CFG-BUF SWAP _FEXP-CFG-FD @ VFS-READ-EXACT IF
        R> DROP _FEXP-CFG-FD @ VFS-CLOSE EXIT
    THEN
    R> _FEXP-CFG-BUF SWAP 2DUP _FEXP-CFG-L ! _FEXP-CFG-A !
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

_FEXP-CURRENT-STATE CMP-CELL: _FEXP-ROWS      \ the table's row block, or 0
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-CNT
_FEXP-CURRENT-STATE CMP-CELL: _FEXP-DIR-KEY    \ key of the listed directory
_FEXP-CURRENT-STATE LST-COLUMN-SIZE 3 * CMP-FIELD: _FEXP-COLUMNS

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

VARIABLE _FBP-IN

: _FEXP-BUILD-PATH-EXACT?  ( inode -- flag )
    DUP _FBP-IN ! _FEXP-BUILD-PATH
    \ VFS-INODE-PATH reports the number of bytes written, not whether either
    \ its byte or ancestor ceiling was reached.  Resolve the reconstruction
    \ and require the exact selected inode before exposing or reopening it.
    _FEXP-PATH-LEN @ _FEXP-PATH-CAP >= IF 0 EXIT THEN
    _FEXP-PATH-BUF _FEXP-PATH-LEN @ _FEXP-VFS @ VFS-RESOLVE
    _FBP-IN @ = ;

\ Paths are kept in _FEXP-PATH-CAP buffers.  A path that does not fit is
\ refused rather than cut short.
: _FEXP-DIR-PATH!  ( path-a path-u -- flag )
    DUP _FEXP-PATH-CAP > IF 2DROP FALSE EXIT THEN
    DUP _FEXP-DIR-LEN ! _FEXP-DIR-PATH SWAP CMOVE TRUE ;

: _FEXP-SEL-PATH!  ( path-a path-u -- flag )
    DUP _FEXP-PATH-CAP > IF 2DROP FALSE EXIT THEN
    DUP _FEXP-SEL-LEN ! _FEXP-SEL-PATH SWAP CMOVE TRUE ;

: _FEXP-SELECT-NONE  ( -- )  0 _FEXP-SEL-LEN ! ;

\ _FEXP-SELECT-INODE ( inode -- flag )
\   Select a live entry by its exact path.  Nothing is selected when the
\   entry is 0 or its path does not fit.
: _FEXP-SELECT-INODE  ( inode -- flag )
    DUP 0= IF DROP _FEXP-SELECT-NONE FALSE EXIT THEN
    _FEXP-BUILD-PATH-EXACT? 0= IF _FEXP-SELECT-NONE FALSE EXIT THEN
    _FEXP-PATH-BUF _FEXP-PATH-LEN @ _FEXP-SEL-PATH! ;

\ _FEXP-PARENT-LEN ( path-a path-u -- len )
\   The length of a path's parent, 0 for the root.
: _FEXP-PARENT-LEN  ( path-a path-u -- len )
    DUP 1 > 0= IF 2DROP 0 EXIT THEN
    1- BEGIN
        DUP 0> WHILE
        2DUP + C@ [CHAR] / = IF NIP EXIT THEN
        1-
    REPEAT
    2DROP 1 ;

\ _FEXP-BASENAME ( path-a path-u -- name-a name-u )   Empty for the root.
: _FEXP-BASENAME  ( path-a path-u -- name-a name-u )
    2DUP _FEXP-PARENT-LEN
    DUP 0= IF DROP + 0 EXIT THEN
    DUP 1 > IF 1+ THEN
    TUCK - >R + R> ;

VARIABLE _FJN-A
VARIABLE _FJN-U
VARIABLE _FJN-DST
VARIABLE _FJN-AT

\ _FEXP-JOIN ( name-a name-u dst -- len flag )
\   The listed directory's path joined with an entry name, in dst.
: _FEXP-JOIN  ( name-a name-u dst -- len flag )
    _FJN-DST ! _FJN-U ! _FJN-A !
    _FEXP-DIR-LEN @ DUP 1 > IF 1+ THEN _FJN-AT !
    _FJN-AT @ _FJN-U @ + DUP _FEXP-PATH-CAP > IF DROP 0 FALSE EXIT THEN
    _FEXP-DIR-PATH _FJN-DST @ _FEXP-DIR-LEN @ CMOVE
    _FEXP-DIR-LEN @ 1 > IF [CHAR] / _FJN-DST @ _FEXP-DIR-LEN @ + C! THEN
    _FJN-A @ _FJN-DST @ _FJN-AT @ + _FJN-U @ CMOVE
    TRUE ;

\ =====================================================================
\  §7 — Detail List: populate / format / sort
\ =====================================================================

\ _FEXP-ENTRY-KEY ( inode -- key )
\   The explorer tree's key for an entry, chained from the root, so a row
\   and its tree node share a key.
: _FEXP-ENTRY-KEY  ( inode -- key )
    DUP IN.PARENT @ ?DUP IF RECURSE ELSE 0 THEN SWAP EXPL-ENTRY-KEY ;

\ The table's rows are copies, one record per entry, made when the
\ directory is listed, so drawing and capture never touch a VFS entry.
\ One allocated block holds the records and then their names.
: _FEXP-R.NAME-A  ( row -- a ) ;
: _FEXP-R.NAME-U  ( row -- a )  8 + ;
: _FEXP-R.TYPE    ( row -- a ) 16 + ;
: _FEXP-R.BYTES   ( row -- a ) 24 + ;     \ file size
: _FEXP-R.KEY     ( row -- a ) 32 + ;
40 CONSTANT _FEXP-ROW-SIZE

: _FEXP-ROW  ( index -- row )  _FEXP-ROW-SIZE * _FEXP-ROWS @ + ;

: _FEXP-ROW-NAME  ( row -- addr len )
    DUP _FEXP-R.NAME-A @ SWAP _FEXP-R.NAME-U @ ;

: _FEXP-ROWS-CLEAR  ( -- )
    _FEXP-ROWS @ ?DUP IF FREE THEN
    0 _FEXP-ROWS ! 0 _FEXP-CNT ! ;

VARIABLE _FLD-DIR
VARIABLE _FLD-N
VARIABLE _FLD-NAMES
VARIABLE _FLD-BLOCK
VARIABLE _FLD-ROW
VARIABLE _FLD-TEXT

: _FEXP-READ-DIR-BODY  ( -- ior )
    _FEXP-DIR-PATH _FEXP-DIR-LEN @ _FEXP-VFS @ VFS-RESOLVE?
    ?DUP IF NIP EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP VFS-E-NOTDIR EXIT THEN
    _FLD-DIR !
    _FLD-DIR @ _FEXP-VFS @ _VFS-ENSURE-CHILDREN? ?DUP IF EXIT THEN
    0 _FLD-N ! 0 _FLD-NAMES !
    _FLD-DIR @ IN.CHILD @
    BEGIN ?DUP WHILE
        1 _FLD-N +!
        DUP IN.NAME @ _VFS-STR-GET NIP _FLD-NAMES +!
        IN.SIBLING @
    REPEAT
    0 _FLD-BLOCK !
    _FLD-N @ IF
        _FLD-N @ _FEXP-ROW-SIZE * _FLD-NAMES @ + ALLOCATE
        ?DUP IF NIP EXIT THEN _FLD-BLOCK !
    THEN
    _FLD-DIR @ _FEXP-ENTRY-KEY _FEXP-DIR-KEY !
    _FLD-BLOCK @ _FLD-ROW !
    _FLD-BLOCK @ _FLD-N @ _FEXP-ROW-SIZE * + _FLD-TEXT !
    _FLD-DIR @ IN.CHILD @
    BEGIN ?DUP WHILE
        DUP IN.NAME @ _VFS-STR-GET                   ( in a u )
        DUP _FLD-ROW @ _FEXP-R.NAME-U !
        _FLD-TEXT @ _FLD-ROW @ _FEXP-R.NAME-A !
        TUCK _FLD-TEXT @ SWAP CMOVE _FLD-TEXT +!     ( in )
        DUP IN.TYPE @ _FLD-ROW @ _FEXP-R.TYPE !
        DUP IN.SIZE-LO @ _FLD-ROW @ _FEXP-R.BYTES !
        _FEXP-DIR-KEY @ OVER EXPL-ENTRY-KEY _FLD-ROW @ _FEXP-R.KEY !
        _FEXP-ROW-SIZE _FLD-ROW +!
        IN.SIBLING @
    REPEAT
    _FEXP-ROWS-CLEAR
    _FLD-BLOCK @ _FEXP-ROWS ! _FLD-N @ _FEXP-CNT !
    0 ;

\ _FEXP-READ-DIR ( -- ior )   Copy the listed directory's entries into rows.
: _FEXP-READ-DIR  ( -- ior )
    ['] _FEXP-READ-DIR-BODY VFS-TRANSACTION ;

\ --- Sort ---

: _FEXP-NAME-CMP  ( row-a row-b -- n )
    >R _FEXP-ROW-NAME R> _FEXP-ROW-NAME STR-ICMP ;

\ Names ascend.  The size sort puts smaller files first, and the type sort
\ puts directories first with names ascending within each type.
: _FEXP-CMP  ( row-a row-b -- n )
    _FEXP-SORT @ FEXP-SORT-SIZE = IF
        _FEXP-R.BYTES @ SWAP _FEXP-R.BYTES @ SWAP - EXIT
    THEN
    _FEXP-SORT @ FEXP-SORT-TYPE = IF
        OVER _FEXP-R.TYPE @ OVER _FEXP-R.TYPE @ -
        ?DUP IF NIP NIP NEGATE EXIT THEN
    THEN
    _FEXP-NAME-CMP ;

CREATE _FEXP-ROW-TMP _FEXP-ROW-SIZE ALLOT

: _FEXP-SWAP-ROWS  ( i j -- )
    2DUP = IF 2DROP EXIT THEN
    _FEXP-ROW SWAP _FEXP-ROW                      ( row-j row-i )
    DUP _FEXP-ROW-TMP _FEXP-ROW-SIZE CMOVE
    2DUP _FEXP-ROW-SIZE CMOVE
    DROP _FEXP-ROW-TMP SWAP _FEXP-ROW-SIZE CMOVE ;

: _FEXP-SORT-LIST  ( -- )
    _FEXP-CNT @ 2 < IF EXIT THEN
    _FEXP-CNT @ 1- 0 DO
        _FEXP-CNT @ I 1+ ?DO
            J _FEXP-ROW I _FEXP-ROW _FEXP-CMP 0> IF J I _FEXP-SWAP-ROWS THEN
        LOOP
    LOOP ;

\ --- Detail table ---

\ The table may be drawn or captured while another instance is active, so
\ a row callback first activates the table's own instance.
: _FEXP-TABLE-ROW  ( index widget -- row )
    LST-CONTEXT@ _FEXP-ACTIVATE _FEXP-ROW ;

: _FEXP-LIST-KEY  ( index widget -- key )
    _FEXP-TABLE-ROW _FEXP-R.KEY @ ;

: _FEXP-LIST-FIELD  ( index column widget -- addr len )
    ROT SWAP _FEXP-TABLE-ROW SWAP              ( row column )
    DUP 0= IF DROP _FEXP-ROW-NAME EXIT THEN
    1 = IF
        DUP _FEXP-R.TYPE @ VFS-T-DIR = IF DROP 0 0 EXIT THEN
        _FEXP-R.BYTES @ SIZE-FMT EXIT
    THEN
    _FEXP-R.TYPE @ VFS-T-DIR = IF S" dir" ELSE S" file" THEN ;

: _FEXP-NAME$  S" Name" ;
: _FEXP-SIZE$  S" Size" ;
: _FEXP-TYPE$  S" Type" ;

: _FEXP-COLUMN!  ( kind label-a label-u width index -- )
    LST-COLUMN-SIZE * _FEXP-COLUMNS + >R
    R@ LST-COLUMN-WIDTH + !
    R@ LST-COLUMN-LABEL-U + ! R@ LST-COLUMN-LABEL-A + !
    R> LST-COLUMN-KIND + ! ;

: _FEXP-COLUMNS-INIT  ( -- )
    LST-TEXT-COLUMN _FEXP-NAME$ 0 0 _FEXP-COLUMN!
    LST-NUMBER-COLUMN _FEXP-SIZE$ 8 1 _FEXP-COLUMN!
    LST-TEXT-COLUMN _FEXP-TYPE$ 4 2 _FEXP-COLUMN! ;

\ The table and the sidebar are caller-mounted widgets.  UIDL repaints an
\ element only when it is marked dirty, so a change made here, rather than
\ through the element's own input, marks its element.
: _FEXP-DETAIL-DIRTY   ( -- )  _FEXP-E-DETAIL @ ?DUP IF UIDL-DIRTY! THEN ;
: _FEXP-SIDEBAR-DIRTY  ( -- )  _FEXP-E-SIDEBAR @ ?DUP IF UIDL-DIRTY! THEN ;
: _FEXP-TREE-REFRESH  ( -- )
    _FEXP-EXPL @ ?DUP IF EXPL-REFRESH THEN _FEXP-SIDEBAR-DIRTY ;

\ _FEXP-SEL-IN-DIR? ( -- flag )   Is the selection an entry of the listed
\   directory?
: _FEXP-SEL-IN-DIR?  ( -- flag )
    _FEXP-SEL-LEN @ 0= IF FALSE EXIT THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-PARENT-LEN
    DUP _FEXP-DIR-LEN @ <> IF DROP FALSE EXIT THEN
    _FEXP-SEL-PATH SWAP _FEXP-DIR-PATH _FEXP-DIR-LEN @ COMPARE 0= ;

VARIABLE _FST-A
VARIABLE _FST-U

\ _FEXP-SYNC-TABLE ( -- )   Put the table's selection on the selected
\   entry when it is in the listed directory.
: _FEXP-SYNC-TABLE  ( -- )
    _FEXP-LIST @ 0= IF EXIT THEN
    _FEXP-SEL-IN-DIR? 0= IF EXIT THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-BASENAME _FST-U ! _FST-A !
    _FEXP-CNT @ 0 ?DO
        I _FEXP-ROW _FEXP-ROW-NAME _FST-A @ _FST-U @ COMPARE 0= IF
            I _FEXP-LIST @ LST-SELECT UNLOOP EXIT
        THEN
    LOOP ;

\ _FEXP-SHOW-DIR ( -- )   List the directory at _FEXP-DIR-PATH in the
\   table, or the root when that directory is gone.
: _FEXP-SHOW-DIR  ( -- )
    _FEXP-READ-DIR IF
        S" /" _FEXP-DIR-PATH! DROP
        _FEXP-READ-DIR IF _FEXP-ROWS-CLEAR THEN
    THEN
    _FEXP-SORT-LIST
    _FEXP-LIST @ ?DUP IF _FEXP-CNT @ SWAP LST-ROWS! THEN
    _FEXP-SYNC-TABLE
    _FEXP-DETAIL-DIRTY ;

\ =====================================================================
\  §8 — Preview: load file into textarea
\ =====================================================================

VARIABLE _FPV-FD
VARIABLE _FPV-LEN

\ _FEXP-LOAD-PREVIEW ( -- )   Load the selected file into the preview.
: _FEXP-LOAD-PREVIEW  ( -- )
    _FEXP-SEL-LEN @ 0= IF EXIT THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-OPEN-VFS
    DUP 0= IF DROP EXIT THEN
    _FPV-FD !
    _FPV-FD @ VFS-SIZE _FEXP-PREVIEW-CAP MIN DUP _FPV-LEN !
    _FEXP-PREV-BUF SWAP _FPV-FD @ VFS-READ-EXACT IF
        _FPV-FD @ VFS-CLOSE EXIT
    THEN
    \ Set the UIDL textarea content via its materialized widget
    _FEXP-E-PREVIEW @ UTUI-WIDGET@ ?DUP IF
        _FEXP-PREV-BUF _FPV-LEN @ ROT TXTA-SET-TEXT
    THEN
    _FPV-FD @ VFS-CLOSE
    ASHELL-DIRTY! ;

\ =====================================================================
\  §9 — Clipboard (copy / cut / paste)
\ =====================================================================

16 CONSTANT _FCP-MAX-PATH-DEPTH
_FEXP-PREVIEW-CAP 2 / CONSTANT _FCP-CHUNK-CAP

VARIABLE _FCP-SRC       VARIABLE _FCP-DST
VARIABLE _FCP-FDS       VARIABLE _FCP-FDD
VARIABLE _FCP-SIZE      VARIABLE _FCP-POS
VARIABLE _FCP-WANT      VARIABLE _FCP-BASE
VARIABLE _FCP-RESULT    VARIABLE _FCP-CREATED
VARIABLE _FCP-COMMITTED VARIABLE _FCP-RESIDUE
VARIABLE _FCP-TARGET-MAYBE
VARIABLE _FCP-OLD-VFS   VARIABLE _FCP-OLD-CWD
VARIABLE _FCP-THROW
VARIABLE _FCP-CLEANUP-THROW
VARIABLE _FCP-CLOSE-THROW
VARIABLE _FCP-PRIMARY-RESULT
VARIABLE _FCP-PATH-IN   VARIABLE _FCP-PATH-BUF
VARIABLE _FCP-PATH-DEPTH
VARIABLE _FCP-CLIP-SET-IN  VARIABLE _FCP-CLIP-SET-OP

\ Deterministic seams for cleanup after-effect tests.  Product bindings stay
\ on the KDOS primitives; callers do not use these internal vectors.
VARIABLE _FCP-CLOSE-XT
VARIABLE _FCP-USE-XT
VARIABLE _FCP-RM-XT
VARIABLE _FCP-SYNC-XT
' VFS-CLOSE _FCP-CLOSE-XT !
' VFS-USE   _FCP-USE-XT !
' VFS-RM    _FCP-RM-XT !
' VFS-SYNC  _FCP-SYNC-XT !

: _FCP-CLOSE  ( fd -- )
    _FCP-CLOSE-XT @ EXECUTE ;

: _FCP-USE  ( vfs -- )
    _FCP-USE-XT @ EXECUTE ;

: _FCP-RM  ( path-a path-u vfs -- ior )
    _FCP-RM-XT @ EXECUTE ;

: _FCP-SYNC  ( vfs -- ior )
    _FCP-SYNC-XT @ EXECUTE ;

: _FCP-INODE-PATH?  ( inode buf -- len flag )
    _FCP-PATH-BUF ! _FCP-PATH-IN !
    0 _FCP-PATH-DEPTH !
    _FCP-PATH-IN @
    BEGIN DUP IN.PARENT @ 0<> WHILE
        1 _FCP-PATH-DEPTH +!
        _FCP-PATH-DEPTH @ _FCP-MAX-PATH-DEPTH > IF
            DROP 0 FALSE EXIT
        THEN
        IN.PARENT @
    REPEAT
    DROP
    _FCP-PATH-IN @ _FCP-PATH-BUF @ _FEXP-PATH-CAP VFS-INODE-PATH
    DUP _FEXP-PATH-CAP < ;

: _FEXP-CLIP-CLEAR  ( -- )
    0 _FEXP-CLIP-PATH-LEN !
    _FEXP-CLIP-NONE _FEXP-CLIP-OP ! ;

: _FEXP-CLIP-SET-BODY  ( -- flag )
    _FEXP-SELECTED DUP 0= IF DROP FALSE EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF
        DROP S" Directory clipboard operations are not supported"
        2500 ASHELL-TOAST FALSE EXIT
    THEN
    _FCP-CLIP-SET-IN !
    _FCP-CLIP-SET-IN @ _FEXP-CLIP-PATH _FCP-INODE-PATH?
    0= IF
        DROP S" Source path is too deep" 2000 ASHELL-TOAST FALSE EXIT
    THEN
    _FEXP-CLIP-PATH-LEN !
    _FCP-CLIP-SET-OP @ _FEXP-CLIP-OP !
    TRUE ;

: _FEXP-CLIP-SET  ( operation -- flag )
    _FCP-CLIP-SET-OP !
    ['] _FEXP-CLIP-SET-BODY VFS-TRANSACTION ;

: FEXP-CLIP-COPY  ( -- )
    _FEXP-CLIP-COPY _FEXP-CLIP-SET IF
        S" Copied to clipboard" 2000 ASHELL-TOAST
    THEN ;

: FEXP-CLIP-CUT  ( -- )
    _FEXP-CLIP-CUT _FEXP-CLIP-SET IF
        S" Cut to clipboard" 2000 ASHELL-TOAST
    THEN ;

: _FCP-SOURCE-BASENAME  ( -- addr len flag )
    0 _FCP-BASE !
    _FEXP-CLIP-PATH-LEN @ 0 DO
        _FEXP-CLIP-PATH I + C@ [CHAR] / = IF I 1+ _FCP-BASE ! THEN
    LOOP
    _FEXP-CLIP-PATH-LEN @ _FCP-BASE @ - DUP 0= IF
        DROP 0 0 FALSE EXIT
    THEN
    _FEXP-CLIP-PATH _FCP-BASE @ + SWAP TRUE ;

VARIABLE _FCP-NAME-A  VARIABLE _FCP-NAME-U
VARIABLE _FCP-DIR-LEN VARIABLE _FCP-TARGET-LEN

: _FCP-BUILD-TARGET  ( -- flag )
    _FCP-DST @ _FEXP-PATH-BUF _FCP-INODE-PATH? 0= IF
        DROP FALSE EXIT
    THEN
    _FCP-DIR-LEN !
    _FCP-SOURCE-BASENAME 0= IF 2DROP FALSE EXIT THEN
    _FCP-NAME-U ! _FCP-NAME-A !
    _FCP-DIR-LEN @ 1 > IF 1 ELSE 0 THEN
    _FCP-DIR-LEN @ + _FCP-NAME-U @ +
    DUP _FEXP-PATH-CAP > IF DROP FALSE EXIT THEN
    _FCP-TARGET-LEN !
    _FCP-DIR-LEN @ 1 > IF
        [CHAR] / _FEXP-PATH-BUF _FCP-DIR-LEN @ + C!
        _FCP-DIR-LEN @ 1+
    ELSE
        _FCP-DIR-LEN @
    THEN
    _FEXP-PATH-BUF + _FCP-NAME-A @ _FCP-NAME-U @ ROT SWAP CMOVE
    TRUE ;

: _FCP-CLOSE-SRC  ( -- )
    \ Clear ownership before close so an after-effect THROW cannot cause a
    \ second close of a descriptor that the VFS has already recycled.
    _FCP-FDS @ ?DUP IF 0 _FCP-FDS ! _FCP-CLOSE THEN ;

: _FCP-CLOSE-DST  ( -- )
    _FCP-FDD @ ?DUP IF 0 _FCP-FDD ! _FCP-CLOSE THEN ;

: _FCP-RECORD-CLOSE-THROW  ( ior -- )
    ?DUP IF
        _FCP-CLOSE-THROW @ 0= IF _FCP-CLOSE-THROW ! ELSE DROP THEN
    THEN ;

: _FCP-CLOSE-FDS  ( -- )
    \ Both descriptors are independent resources.  Attempt both closes even
    \ when the first one throws, then rethrow the first fault to the phase
    \ boundary after all ownership has been relinquished.
    0 _FCP-CLOSE-THROW !
    ['] _FCP-CLOSE-SRC CATCH _FCP-RECORD-CLOSE-THROW
    ['] _FCP-CLOSE-DST CATCH _FCP-RECORD-CLOSE-THROW
    _FCP-CLOSE-THROW @ ?DUP IF THROW THEN ;

: _FCP-COPY-BYTES  ( -- flag )
    0 _FCP-POS !
    BEGIN _FCP-POS @ _FCP-SIZE @ < WHILE
        _FCP-SIZE @ _FCP-POS @ - _FCP-CHUNK-CAP MIN _FCP-WANT !
        _FEXP-PREV-BUF _FCP-WANT @ _FCP-FDS @ VFS-READ-EXACT IF
            FALSE EXIT
        THEN
        _FEXP-PREV-BUF _FCP-WANT @ _FCP-FDD @ VFS-WRITE-EXACT IF
            FALSE EXIT
        THEN
        _FCP-WANT @ _FCP-POS +!
    REPEAT
    TRUE ;

: _FCP-VERIFY-BYTES  ( -- flag )
    _FCP-FDS @ VFS-SIZE _FCP-SIZE @ <> IF FALSE EXIT THEN
    _FCP-FDD @ VFS-SIZE _FCP-SIZE @ <> IF FALSE EXIT THEN
    0 _FCP-POS !
    BEGIN _FCP-POS @ _FCP-SIZE @ < WHILE
        _FCP-SIZE @ _FCP-POS @ - _FCP-CHUNK-CAP MIN _FCP-WANT !
        _FEXP-PREV-BUF _FCP-WANT @ _FCP-FDS @ VFS-READ-EXACT IF
            FALSE EXIT
        THEN
        _FEXP-PREV-BUF _FCP-CHUNK-CAP +
        _FCP-WANT @ _FCP-FDD @ VFS-READ-EXACT IF FALSE EXIT THEN
        _FEXP-PREV-BUF _FCP-WANT @
        _FEXP-PREV-BUF _FCP-CHUNK-CAP + _FCP-WANT @
        COMPARE 0<> IF FALSE EXIT THEN
        _FCP-WANT @ _FCP-POS +!
    REPEAT
    TRUE ;

: _FCP-OPEN-PAIR  ( -- flag )
    _FEXP-CLIP-PATH _FEXP-CLIP-PATH-LEN @ VFS-OPEN
    DUP 0= IF DROP FALSE EXIT THEN _FCP-FDS !
    _FEXP-PATH-BUF _FCP-TARGET-LEN @ VFS-OPEN
    DUP 0= IF DROP FALSE EXIT THEN _FCP-FDD !
    TRUE ;

: _FCP-COPY-CORE  ( -- )
    _FEXP-CLIP-PATH-LEN @ 0= IF _FCP-S-SOURCE _FCP-RESULT ! EXIT THEN
    _FEXP-CLIP-PATH _FEXP-CLIP-PATH-LEN @ _FEXP-VFS @ VFS-RESOLVE
    DUP 0= IF DROP _FCP-S-SOURCE _FCP-RESULT ! EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP _FCP-S-SOURCE _FCP-RESULT ! EXIT THEN
    DUP _FCP-SRC ! IN.SIZE-LO @ _FCP-SIZE !

    _FEXP-SELECTED DUP 0= IF DROP _FCP-S-DESTINATION _FCP-RESULT ! EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = IF ELSE IN.PARENT @ THEN
    DUP 0= IF DROP _FCP-S-DESTINATION _FCP-RESULT ! EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP _FCP-S-DESTINATION _FCP-RESULT ! EXIT THEN
    _FCP-DST !
    _FCP-BUILD-TARGET 0= IF _FCP-S-DESTINATION _FCP-RESULT ! EXIT THEN

    _FEXP-CLIP-PATH _FEXP-CLIP-PATH-LEN @
    _FEXP-PATH-BUF _FCP-TARGET-LEN @ COMPARE 0= IF
        _FCP-S-SAME _FCP-RESULT ! EXIT
    THEN
    _FEXP-PATH-BUF _FCP-TARGET-LEN @ _FEXP-VFS @ VFS-RESOLVE
    ?DUP IF DROP _FCP-S-CONFLICT _FCP-RESULT ! EXIT THEN

    _FCP-S-CREATE _FCP-RESULT !
    TRUE _FCP-TARGET-MAYBE !
    _FEXP-PATH-BUF _FCP-TARGET-LEN @ _FEXP-VFS @ VFS-CREATE
    DUP 0= IF DROP _FCP-S-CREATE _FCP-RESULT ! EXIT THEN DROP
    TRUE _FCP-CREATED !
    _FCP-S-IO _FCP-RESULT !
    _FCP-OPEN-PAIR 0= IF _FCP-S-IO _FCP-RESULT ! EXIT THEN
    _FCP-COPY-BYTES 0= IF _FCP-S-IO _FCP-RESULT ! EXIT THEN
    _FCP-CLOSE-FDS
    _FEXP-VFS @ _FCP-SYNC IF _FCP-S-IO _FCP-RESULT ! EXIT THEN

    _FCP-S-VERIFY _FCP-RESULT !
    _FCP-OPEN-PAIR 0= IF _FCP-S-VERIFY _FCP-RESULT ! EXIT THEN
    _FCP-VERIFY-BYTES 0= IF _FCP-S-VERIFY _FCP-RESULT ! EXIT THEN
    _FCP-CLOSE-FDS
    TRUE _FCP-COMMITTED !
    FALSE _FCP-TARGET-MAYBE !

    _FEXP-CLIP-OP @ _FEXP-CLIP-CUT = IF
        \ Once a verified destination is published, a throwing delete/sync
        \ may have removed the source.  Predeclare the conservative status
        \ so an after-effect fault cannot leave a stale "internal" outcome.
        _FCP-S-DELETE-SYNC _FCP-RESULT !
        _FEXP-CLIP-PATH _FEXP-CLIP-PATH-LEN @ _FEXP-VFS @ _FCP-RM IF
            _FCP-S-DELETE _FCP-RESULT ! EXIT
        THEN
        _FEXP-VFS @ _FCP-SYNC IF
            _FCP-S-DELETE-SYNC _FCP-RESULT ! EXIT
        THEN
    THEN
    _FCP-S-OK _FCP-RESULT ! ;

: _FCP-ROLLBACK  ( -- )
    _FCP-COMMITTED @ IF EXIT THEN
    _FCP-CREATED @ _FCP-TARGET-MAYBE @ OR 0= IF EXIT THEN
    _FCP-RESULT @ _FCP-PRIMARY-RESULT !
    \ From this point until delete+sync both complete, a target may remain or
    \ its absence may be non-durable.  Establish uncertainty before invoking
    \ either operation so after-effect THROWs retain the conservative state.
    TRUE _FCP-RESIDUE ! _FCP-S-ROLLBACK _FCP-RESULT !
    _FEXP-PATH-BUF _FCP-TARGET-LEN @ _FEXP-VFS @ VFS-RESOLVE
    DUP 0= IF
        DROP
        FALSE _FCP-CREATED ! FALSE _FCP-TARGET-MAYBE !
        FALSE _FCP-RESIDUE !
        _FCP-PRIMARY-RESULT @ _FCP-RESULT ! EXIT
    THEN DROP
    _FEXP-PATH-BUF _FCP-TARGET-LEN @ _FEXP-VFS @ _FCP-RM IF
        EXIT
    THEN
    _FEXP-VFS @ _FCP-SYNC IF
        EXIT
    THEN
    FALSE _FCP-CREATED ! FALSE _FCP-TARGET-MAYBE !
    FALSE _FCP-RESIDUE !
    _FCP-PRIMARY-RESULT @ _FCP-RESULT ! ;

: _FCP-RECORD-CLEANUP-THROW  ( ior -- )
    ?DUP IF
        _FCP-CLEANUP-THROW @ 0= IF
            _FCP-CLEANUP-THROW !
        ELSE
            DROP
        THEN
    THEN ;

: _FCP-RESTORE-CWD  ( -- )
    _FCP-OLD-CWD @ _FEXP-VFS @ V.CWD ! ;

: _FCP-RESTORE-VFS  ( -- )
    _FCP-OLD-VFS @ _FCP-USE ;

: _FCP-RESTORE-VFS-RAW  ( -- )
    _FCP-OLD-VFS @ VFS-USE ;

: _FCP-CLEANUP  ( -- )
    \ Cleanup stages are independent: no close, rollback, or selector fault
    \ may suppress a later release/restoration attempt.  Preserve the first
    \ cleanup THROW for deterministic diagnostics.
    0 _FCP-CLEANUP-THROW !
    ['] _FCP-CLOSE-SRC CATCH _FCP-RECORD-CLEANUP-THROW
    ['] _FCP-CLOSE-DST CATCH _FCP-RECORD-CLEANUP-THROW
    ['] _FCP-ROLLBACK CATCH _FCP-RECORD-CLEANUP-THROW
    ['] _FCP-RESTORE-CWD CATCH _FCP-RECORD-CLEANUP-THROW
    ['] _FCP-RESTORE-VFS CATCH _FCP-RECORD-CLEANUP-THROW
    VFS-CUR _FCP-OLD-VFS @ <> IF
        ['] _FCP-RESTORE-VFS-RAW CATCH _FCP-RECORD-CLEANUP-THROW
    THEN ;

: _FCP-TRANSACTION-BODY  ( -- )
    \ Selecting the Explorer VFS is itself part of the caught operation.  An
    \ after-effect selector fault must still reach the restoration pipeline.
    _FEXP-VFS @ _FCP-USE
    _FCP-COPY-CORE ;

: _FCP-TRANSACTION  ( -- status )
    0 _FCP-FDS ! 0 _FCP-FDD !
    0 _FCP-CREATED ! 0 _FCP-COMMITTED ! 0 _FCP-RESIDUE !
    0 _FCP-TARGET-MAYBE !
    _FCP-S-INTERNAL _FCP-RESULT !
    VFS-CUR _FCP-OLD-VFS !
    _FEXP-VFS @ V.CWD @ _FCP-OLD-CWD !
    ['] _FCP-TRANSACTION-BODY CATCH _FCP-THROW !
    _FCP-CLEANUP
    \ Rollback uncertainty has highest precedence.  Otherwise preserve the
    \ phase-specific primary status; only a cleanup-only fault following an
    \ apparent success is normalized to INTERNAL.  COMMITTED/RESIDUE remain
    \ orthogonal publication facts for the UI refresh path.
    _FCP-RESIDUE @ IF
        _FCP-S-ROLLBACK _FCP-RESULT !
    ELSE
        _FCP-CLEANUP-THROW @ _FCP-RESULT @ _FCP-S-OK = AND IF
            _FCP-S-INTERNAL _FCP-RESULT !
        THEN
    THEN
    _FCP-RESULT @ ;

: _FCP-RUN  ( -- status )
    ['] _FCP-TRANSACTION VFS-TRANSACTION ;

: _FEXP-REFRESH-AFTER-MUTATION  ( -- )
    _FEXP-TREE-REFRESH
    _FEXP-SHOW-DIR
    ASHELL-DIRTY! ;

: _FCP-REPORT-FAILURE  ( status -- )
    CASE
        _FCP-S-SOURCE OF S" Paste failed: source unavailable" ENDOF
        _FCP-S-DESTINATION OF S" Paste failed: invalid destination" ENDOF
        _FCP-S-SAME OF S" Paste refused: source equals destination" ENDOF
        _FCP-S-CONFLICT OF S" Paste refused: destination exists" ENDOF
        _FCP-S-CREATE OF S" Paste failed: cannot create destination" ENDOF
        _FCP-S-VERIFY OF S" Paste failed: destination did not verify" ENDOF
        _FCP-S-ROLLBACK OF S" Paste failed: cleanup is uncertain" ENDOF
        _FCP-S-INTERNAL OF S" Paste failed: internal storage error" ENDOF
        S" Paste failed: storage I/O"
    ENDCASE
    3000 ASHELL-TOAST ;

: FEXP-CLIP-PASTE  ( -- )
    _FEXP-CLIP-OP @ _FEXP-CLIP-NONE = IF
        S" Clipboard empty" 1500 ASHELL-TOAST EXIT
    THEN
    _FEXP-CLIP-PATH-LEN @ 0= IF
        S" No source" 1500 ASHELL-TOAST EXIT
    THEN
    _FCP-RUN
    DUP _FCP-S-OK = IF
        DROP
        _FEXP-CLIP-OP @ _FEXP-CLIP-CUT = IF _FEXP-CLIP-CLEAR THEN
        _FEXP-REFRESH-AFTER-MUTATION
        S" Pasted!" 1500 ASHELL-TOAST EXIT
    THEN
    DUP _FCP-S-DELETE = IF
        DROP _FEXP-CLIP-CLEAR
        _FEXP-REFRESH-AFTER-MUTATION
        S" Copied, but source could not be removed" 3500 ASHELL-TOAST EXIT
    THEN
    DUP _FCP-S-DELETE-SYNC = IF
        DROP _FEXP-CLIP-CLEAR
        _FEXP-REFRESH-AFTER-MUTATION
        S" Copied; source cleanup durability is uncertain"
        4000 ASHELL-TOAST EXIT
    THEN
    _FCP-COMMITTED @ _FCP-RESIDUE @ OR IF
        _FEXP-REFRESH-AFTER-MUTATION
    THEN
    _FCP-REPORT-FAILURE ;

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
    \ Right: path of the selection
    _FEXP-E-SBAR-R @ ?DUP IF
        S" text"
        _FEXP-SEL-LEN @ IF _FEXP-SEL-PATH _FEXP-SEL-LEN @ ELSE S" /" THEN
        UTUI-SET-ATTR
    THEN ;

\ =====================================================================
\  §11 — Refresh detail list helper
\ =====================================================================

: _FEXP-REFRESH-DETAIL  ( -- )
    _FEXP-SHOW-DIR
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY! ;

\ =====================================================================
\  §12 — Explorer callbacks (on-select / on-open)
\ =====================================================================

\ The tree hands over a live entry; it is kept only as its path.
: _FEXP-ON-SELECT  ( inode explorer -- )
    DROP
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = SWAP
    _FEXP-SELECT-INODE AND IF
        _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-DIR-PATH! DROP
        _FEXP-SHOW-DIR
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

\ _FEXP-POST-OPEN ( -- )   Ask Desk to open the selected file.
: _FEXP-POST-OPEN  ( -- )
    _FEXP-SEL-LEN @ 0= IF EXIT THEN
    CBR-NEW DUP IF
        2DROP S" Could not allocate open request" 1800 ASHELL-TOAST EXIT
    THEN
    DROP _FOP-REQ !
    CPRINC-COMPONENT _FOP-REQ @ CBR.PRINCIPAL !
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FOP-REQ @ CBR.ARGS IRES-VFS! IF
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
    DROP _FEXP-SELECTED DUP 0= IF DROP EXIT THEN
    IN.TYPE @ VFS-T-FILE = IF _FEXP-POST-OPEN THEN ;

\ The explorer expands and collapses directories itself and reports only
\ opened files here.
: _FEXP-ON-OPEN  ( inode explorer -- )
    DROP
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP EXIT THEN
    _FEXP-SELECT-INODE IF
        _FEXP-LOAD-PREVIEW
        _FEXP-POST-OPEN
        _FEXP-E-TABS @ ?DUP IF 1 SWAP UTUI-TAB-SELECT THEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY! ;

\ _FEXP-SELECT-ROW ( index -- row flag )
\   Make a row the selection; FALSE when its path does not fit.
: _FEXP-SELECT-ROW  ( index -- row flag )
    _FEXP-ROW DUP _FEXP-ROW-NAME _FEXP-SEL-PATH _FEXP-JOIN   ( row len flag )
    IF _FEXP-SEL-LEN ! TRUE ELSE DROP _FEXP-SELECT-NONE FALSE THEN ;

: _FEXP-ROW-INDEX?  ( index -- flag )  DUP 0< 0= SWAP _FEXP-CNT @ < AND ;

\ Selecting a row loads a file's preview, ready in the Preview tab, and
\ keeps the table in view so the row can be opened.
: _FEXP-ON-LIST-SEL  ( index widget -- )
    DROP
    DUP _FEXP-ROW-INDEX? 0= IF DROP EXIT THEN
    _FEXP-SELECT-ROW IF
        _FEXP-R.TYPE @ VFS-T-FILE = IF _FEXP-LOAD-PREVIEW THEN
    ELSE
        DROP S" The path is too long" 2000 ASHELL-TOAST
    THEN
    _FEXP-UPDATE-STATUS ;

\ Opening a row enters a directory or opens a file with its application.
: _FEXP-ON-LIST-OPEN  ( index widget -- )
    DROP
    DUP _FEXP-ROW-INDEX? 0= IF DROP EXIT THEN
    _FEXP-SELECT-ROW 0= IF
        DROP S" The path is too long" 2000 ASHELL-TOAST
        _FEXP-UPDATE-STATUS EXIT
    THEN
    _FEXP-R.TYPE @ VFS-T-DIR = IF
        _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-DIR-PATH! DROP
        _FEXP-SHOW-DIR
    ELSE
        _FEXP-POST-OPEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY! ;

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
    DUP 0= IF DROP _FEXP-DIR-PATH _FEXP-DIR-LEN @ _FEXP-VFS @ VFS-RESOLVE EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = IF EXIT THEN
    IN.PARENT @ ;

VARIABLE _FMU-A
VARIABLE _FMU-U
VARIABLE _FMU-TYPE
VARIABLE _FMU-DIR
VARIABLE _FMU-OLD-CWD
VARIABLE _FMU-OK

: _FEXP-CREATE-NAMED-BODY  ( -- flag )
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
        _FEXP-SELECT-INODE DROP
        _FEXP-VFS @ VFS-SYNC IF 0 _FMU-OK ! THEN
        _FEXP-TREE-REFRESH
        _FEXP-REFRESH-DETAIL
    THEN
    _FMU-OK @ ;

: _FEXP-CREATE-NAMED  ( name-a name-u type -- flag )
    _FMU-TYPE ! _FMU-U ! _FMU-A !
    ['] _FEXP-CREATE-NAMED-BODY VFS-TRANSACTION ;

VARIABLE _FMR-IN
VARIABLE _FMR-A
VARIABLE _FMR-U
VARIABLE _FMR-LISTED

\ _FEXP-SEL-LISTED? ( -- flag )   Is the selection the listed directory?
: _FEXP-SEL-LISTED?  ( -- flag )
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-DIR-PATH _FEXP-DIR-LEN @ COMPARE 0= ;

: _FEXP-RENAME-NAMED-BODY  ( -- flag )
    _FMR-U @ 0= _FMR-U @ 23 > OR IF FALSE EXIT THEN
    _FEXP-SELECTED DUP 0= IF DROP FALSE EXIT THEN
    _FMR-IN !
    _FEXP-SEL-LISTED? _FMR-LISTED !
    _FMR-A @ _FMR-U @ _FMR-IN @ _FEXP-VFS @ VFS-RENAME IF FALSE EXIT THEN
    \ The selection, and the listing when it was the renamed directory,
    \ follow the new name.
    _FMR-IN @ _FEXP-SELECT-INODE
    _FMR-LISTED @ AND IF
        _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-DIR-PATH! DROP
    THEN
    _FEXP-VFS @ VFS-SYNC IF FALSE EXIT THEN
    _FEXP-TREE-REFRESH
    _FEXP-REFRESH-DETAIL
    TRUE ;

: _FEXP-RENAME-NAMED  ( name-a name-u -- flag )
    _FMR-U ! _FMR-A !
    ['] _FEXP-RENAME-NAMED-BODY VFS-TRANSACTION ;

VARIABLE _FDEL-IN
VARIABLE _FDEL-PARENT
VARIABLE _FDEL-A
VARIABLE _FDEL-U
VARIABLE _FDEL-OLD-CWD
VARIABLE _FDEL-LISTED

: _FEXP-DELETE-BODY  ( -- flag )
    \ Look the selection up again: other applets ran during confirmation.
    _FEXP-SELECTED DUP 0= IF DROP FALSE EXIT THEN
    DUP _FEXP-VFS @ V.ROOT @ = IF DROP FALSE EXIT THEN
    _FDEL-IN !
    _FEXP-SEL-LISTED? _FDEL-LISTED !
    _FDEL-IN @ IN.PARENT @ _FDEL-PARENT !
    _FDEL-IN @ IN.NAME @ _VFS-STR-GET _FDEL-U ! _FDEL-A !
    _FEXP-VFS @ V.CWD @ _FDEL-OLD-CWD !
    _FDEL-PARENT @ _FEXP-VFS @ V.CWD !
    _FDEL-A @ _FDEL-U @ _FEXP-VFS @ VFS-RM
    _FDEL-OLD-CWD @ _FEXP-VFS @ V.CWD !
    IF FALSE EXIT THEN
    \ The selection moves to the parent, and so does the listing when it
    \ was the deleted directory.
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-PARENT-LEN _FEXP-SEL-LEN !
    _FDEL-LISTED @ IF _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-DIR-PATH! DROP THEN
    _FEXP-VFS @ VFS-SYNC IF FALSE EXIT THEN
    _FEXP-TREE-REFRESH
    _FEXP-REFRESH-DETAIL
    TRUE ;

: _FEXP-DELETE-SELECTED  ( -- flag )
    _FEXP-SEL-LEN @ 0= IF FALSE EXIT THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ S" /" COMPARE 0= IF FALSE EXIT THEN
    \ Never hold the VFS guard, or a VFS entry, across the modal
    \ confirmation/yield loop.
    S" Delete the selected item?" DLG-CONFIRM 0= IF FALSE EXIT THEN
    ['] _FEXP-DELETE-BODY VFS-TRANSACTION ;

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
    _FEXP-SEL-LEN @ 0= IF EXIT THEN
    _FEXP-PRM-RENAME S" Rename:"
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-BASENAME _FEXP-SHOW-PROMPT ;
: _FEXP-DO-REFRESH    ( elem -- ) DROP _FEXP-TREE-REFRESH   _FEXP-REFRESH-DETAIL ;
: _FEXP-DO-COPY       ( elem -- ) DROP FEXP-CLIP-COPY ;
: _FEXP-DO-CUT        ( elem -- ) DROP FEXP-CLIP-CUT ;
: _FEXP-DO-PASTE      ( elem -- ) DROP FEXP-CLIP-PASTE ;

: _FEXP-DO-TOGGLE-HIDDEN  ( elem -- )
    DROP
    _FEXP-EXPL @ DUP EXPL-SHOW-HIDDEN? 0= SWAP EXPL-SHOW-HIDDEN!
    _FEXP-TREE-REFRESH _FEXP-REFRESH-DETAIL ;

: _FEXP-DO-SORT-NAME  ( elem -- ) DROP FEXP-SORT-NAME _FEXP-SORT ! _FEXP-REFRESH-DETAIL ;
: _FEXP-DO-SORT-SIZE  ( elem -- ) DROP FEXP-SORT-SIZE _FEXP-SORT ! _FEXP-REFRESH-DETAIL ;
: _FEXP-DO-SORT-TYPE  ( elem -- ) DROP FEXP-SORT-TYPE _FEXP-SORT ! _FEXP-REFRESH-DETAIL ;

: _FEXP-DO-EXPAND-ALL  ( elem -- )
    DROP _FEXP-EXPL @ EXPL-EXPAND-ALL _FEXP-SIDEBAR-DIRTY ASHELL-DIRTY! ;
: _FEXP-DO-COLLAPSE-ALL  ( elem -- )
    DROP _FEXP-EXPL @ EXPL-COLLAPSE-ALL _FEXP-SIDEBAR-DIRTY ASHELL-DIRTY! ;

: _FEXP-DO-DETAILS  ( elem -- )
    DROP _FEXP-E-TABS @ ?DUP IF 0 SWAP UTUI-TAB-SELECT THEN ;

: _FEXP-DO-PREVIEW  ( elem -- )
    DROP _FEXP-E-TABS @ ?DUP IF 1 SWAP UTUI-TAB-SELECT THEN ;

\ The sidebar stays rooted at the VFS root, so moving the listing never
\ leaves the tree holding an entry another applet may remove.
: _FEXP-DO-PARENT-DIR  ( elem -- )
    DROP
    _FEXP-DIR-PATH _FEXP-DIR-LEN @ _FEXP-PARENT-LEN ?DUP IF
        _FEXP-DIR-LEN !
        _FEXP-SHOW-DIR
        _FEXP-UPDATE-STATUS
        ASHELL-DIRTY!
    THEN ;

VARIABLE _FGP-TYPE

: _FEXP-GOTO-PATH  ( path-a path-u -- flag )
    _FEXP-VFS @ VFS-RESOLVE
    DUP 0= IF EXIT THEN
    DUP IN.TYPE @ _FGP-TYPE !
    _FEXP-SELECT-INODE 0= IF 0 EXIT THEN
    _FGP-TYPE @ VFS-T-DIR = IF
        _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FEXP-DIR-PATH! DROP
        _FEXP-SHOW-DIR
    ELSE
        _FEXP-LOAD-PREVIEW
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
    _FEXP-PRM-GOTO S" Go to:" _FEXP-DIR-PATH _FEXP-DIR-LEN @
    _FEXP-SHOW-PROMPT ;

VARIABLE _FPR-LEN

\ _FPR+ ( addr len -- )   Append to the properties text.
: _FPR+  ( addr len -- )
    _FEXP-PREVIEW-CAP _FPR-LEN @ - MIN
    DUP >R _FEXP-PREV-BUF _FPR-LEN @ + SWAP CMOVE R> _FPR-LEN +! ;

: _FEXP-DO-PROPS  ( elem -- )
    DROP
    _FEXP-SELECTED DUP 0= IF DROP EXIT THEN
    \ The text is built in the preview buffer, reused for the moment.
    0 _FPR-LEN !
    S" Path: " _FPR+
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FPR+
    S"   Type: " _FPR+
    DUP IN.TYPE @ VFS-T-DIR = IF S" dir" ELSE S" file" THEN _FPR+
    S"   Size: " _FPR+
    IN.SIZE-LO @ SIZE-FMT _FPR+
    _FEXP-PREV-BUF _FPR-LEN @ DLG-INFO ;

\ =====================================================================
\  §14 — INIT callback ("document ready")
\ =====================================================================

: FEXP-INIT-CB  ( instance -- )
    _FEXP-ACTIVATE
    \ Initialize business state
    FEXP-SORT-NAME _FEXP-SORT !
    0 _FEXP-CNT ! 0 _FEXP-ROWS !
    _FEXP-CLIP-CLEAR
    S" /" _FEXP-DIR-PATH! DROP
    S" /" _FEXP-SEL-PATH! DROP
    0 _FEXP-PROMPT !
    0 _FEXP-PROMPT-RGN !
    _FEXP-PRM-NONE _FEXP-PROMPT-MODE !

    \ Get VFS
    VFS-CUR DUP 0= ABORT" fexplorer: no VFS available"
    _FEXP-VFS !
    _FEXP-VFS @ _FEXP-PREVIEW-SCOPE VFA-SCOPE-INIT
    0<> ABORT" fexplorer: preview scope initialization failed"

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

    \ Create the detail table and mount it on the detail region
    _FEXP-E-DETAIL @ UTUI-ELEM-RGN      ( row col h w )
    RGN-NEW                              ( rgn )
    ['] _FEXP-LIST-KEY ['] _FEXP-LIST-FIELD LST-NEW
    _FEXP-LIST !
    _FEXP-CURRENT-INSTANCE @ _FEXP-LIST @ LST-CONTEXT!
    _FEXP-COLUMNS-INIT
    _FEXP-COLUMNS 3 _FEXP-LIST @ LST-COLUMNS!
    ['] _FEXP-ON-LIST-SEL _FEXP-LIST @ LST-ON-SELECT
    ['] _FEXP-ON-LIST-OPEN _FEXP-LIST @ LST-ON-OPEN
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
    _FEXP-SHOW-DIR

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
    _FEXP-ROWS-CLEAR
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
CREATE _FEXP-PREVIEW-SCHEMA CS-SIZE ALLOT
3 CONSTANT _FEXP-CAP-COUNT
CREATE FEXP-CAPS _FEXP-CAP-COUNT CAP-DESC * ALLOT
: FEXP-CAP-REVEAL    ( -- cap ) FEXP-CAPS ;
: FEXP-CAP-SELECTED  ( -- cap ) FEXP-CAPS CAP-DESC + ;
: FEXP-CAP-PREVIEW   ( -- cap ) FEXP-CAPS CAP-DESC 2 * + ;

CREATE FEXP-INTENTS CINT-DESC-SIZE ALLOT

VARIABLE _FRV-TYPE

\ Listing a file's directory selects its row as well.
: _FEXP-REVEAL-PATH  ( path-a path-u -- ior )
    _FEXP-VFS @ VFS-RESOLVE DUP 0= IF DROP -1 EXIT THEN
    DUP IN.TYPE @ _FRV-TYPE !
    _FEXP-SELECT-INODE 0= IF -1 EXIT THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @
    _FRV-TYPE @ VFS-T-DIR <> IF 2DUP _FEXP-PARENT-LEN NIP THEN
    _FEXP-DIR-PATH! DROP
    _FEXP-SHOW-DIR
    _FRV-TYPE @ VFS-T-FILE = IF _FEXP-LOAD-PREVIEW THEN
    _FEXP-UPDATE-STATUS ASHELL-DIRTY!
    0 ;

VARIABLE _FRH-A
VARIABLE _FRH-U
VARIABLE _FRS-REQ
VARIABLE _FRP-REQ
VARIABLE _FRP-LEN
VARIABLE _FRP-SIZE
VARIABLE _FRP-STATUS
VARIABLE _FRP-TEXT-A
VARIABLE _FRP-TEXT-U
VARIABLE _FRP-TEXT-TRUNC
VARIABLE _FRP-TEXT-CHECK
VARIABLE _FRP-TEXT-OUT
VARIABLE _FRP-TEXT-EDGE-OK

: _FEXP-CAP-TEXT-LEN?  ( addr len truncated? -- preview-len flag )
    _FRP-TEXT-TRUNC ! _FRP-TEXT-U ! _FRP-TEXT-A !
    _FRP-TEXT-TRUNC @ 0= IF
        _FRP-TEXT-A @ _FRP-TEXT-U @ UTF8-VALID? IF
            _FRP-TEXT-U @ -1
        ELSE
            0 0
        THEN
        EXIT
    THEN
    \ Prove the bytes at the output edge complete a valid codepoint using
    \ the caller's three-byte lookahead.  This distinguishes a split valid
    \ sequence from an arbitrary malformed suffix that backoff could hide.
    0 _FRP-TEXT-EDGE-OK !
    _FEXP-CAP-TEXT-MAX _FRP-TEXT-CHECK !
    BEGIN
        _FRP-TEXT-CHECK @ _FRP-TEXT-U @ <=
        _FRP-TEXT-EDGE-OK @ 0= AND
    WHILE
        _FRP-TEXT-A @ _FRP-TEXT-CHECK @ UTF8-VALID? IF
            -1 _FRP-TEXT-EDGE-OK !
        ELSE
            1 _FRP-TEXT-CHECK +!
        THEN
    REPEAT
    _FRP-TEXT-EDGE-OK @ 0= IF 0 0 EXIT THEN

    _FEXP-CAP-TEXT-MAX _FRP-TEXT-OUT !
    4 0 DO
        _FRP-TEXT-A @ _FRP-TEXT-OUT @ UTF8-VALID? IF
            _FRP-TEXT-OUT @ -1 UNLOOP EXIT
        THEN
        -1 _FRP-TEXT-OUT +!
    LOOP
    0 0 ;

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

: _FEXP-CAP-SELECTED-BODY  ( -- status )
    _FEXP-SEL-LEN @ 0= IF
        _FRS-REQ @ CBR.RESULT CV-NULL! CBUS-S-OK EXIT
    THEN
    _FEXP-SELECTED 0= IF CBUS-S-NOT-FOUND EXIT THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ _FRS-REQ @ CBR.RESULT IRES-VFS!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _FEXP-CAP-SELECTED-HANDLER  ( request instance -- status )
    _FEXP-ACTIVATE _FRS-REQ !
    ['] _FEXP-CAP-SELECTED-BODY VFS-TRANSACTION ;

: _FEXP-CAP-PREVIEW-BODY  ( -- )
    \ Keep the lookup, open, and read in one VFS exclusion region.  A
    \ rename cannot redirect the looked-up path between calls.
    _FEXP-SEL-LEN @ 0= IF
        _FRP-REQ @ CBR.RESULT CV-NULL!
        CBUS-S-OK _FRP-STATUS ! EXIT
    THEN
    _FEXP-SELECTED DUP 0= IF
        DROP CBUS-S-NOT-FOUND _FRP-STATUS ! EXIT
    THEN
    IN.TYPE @ VFS-T-FILE <> IF
        _FRP-REQ @ CBR.RESULT CV-NULL!
        CBUS-S-OK _FRP-STATUS ! EXIT
    THEN
    _FEXP-SEL-PATH _FEXP-SEL-LEN @ VFS-FF-READ
    _FEXP-PREVIEW-SCOPE VFA-SCOPE-OPEN?
    DUP IF
        VFS-IOR-REASON VFS-R-NOENT = IF
            CBUS-S-NOT-FOUND _FRP-STATUS !
        THEN
        DROP EXIT
    THEN
    DROP
    _FEXP-PREV-BUF _FEXP-CAP-TEXT-MAX 3 + ROT VFA-READ-PREFIX?
    DUP IF 2DROP 2DROP EXIT THEN
    DROP DROP _FRP-SIZE ! _FRP-LEN !
    _FEXP-PREV-BUF _FRP-LEN @
    _FRP-SIZE @ _FEXP-CAP-TEXT-MAX > _FEXP-CAP-TEXT-LEN? 0= IF
        DROP EXIT
    THEN
    _FRP-LEN !
    _FEXP-PREV-BUF _FRP-LEN @ _FRP-REQ @ CBR.RESULT CV-STRING!
    IF EXIT THEN
    CBUS-S-OK _FRP-STATUS ! ;

: _FEXP-CAP-PREVIEW-HANDLER  ( request instance -- status )
    _FEXP-ACTIVATE _FRP-REQ !
    CBUS-S-FAILED _FRP-STATUS !
    ['] _FEXP-CAP-PREVIEW-BODY _FEXP-PREVIEW-SCOPE VFA-SCOPE-CALL
    OR IF CBUS-S-FAILED ELSE _FRP-STATUS @ THEN ;

: _FEXP-CAP-SETUP  ( -- )
    _FEXP-RESOURCE-SCHEMA CS-INIT
    CV-T-RESOURCE _FEXP-RESOURCE-SCHEMA CS-ALLOW!
    516 _FEXP-RESOURCE-SCHEMA CS-MAX-LEN!
    _FEXP-OPTIONAL-RESOURCE-SCHEMA CS-INIT
    CV-T-NULL CS-TYPE-BIT CV-T-RESOURCE CS-TYPE-BIT OR
    _FEXP-OPTIONAL-RESOURCE-SCHEMA CS-ALLOW-MASK!
    516 _FEXP-OPTIONAL-RESOURCE-SCHEMA CS-MAX-LEN!
    _FEXP-PREVIEW-SCHEMA CS-INIT
    CV-T-NULL CS-TYPE-BIT CV-T-STRING CS-TYPE-BIT OR
    _FEXP-PREVIEW-SCHEMA CS-ALLOW-MASK!
    _FEXP-CAP-TEXT-MAX _FEXP-PREVIEW-SCHEMA CS-MAX-LEN!

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

    FEXP-CAP-PREVIEW CAP-DESC-INIT
    CAP-K-RESOURCE FEXP-CAP-PREVIEW CAP.KIND !
    S" fexplorer.preview.text"
    FEXP-CAP-PREVIEW CAP.ID-U ! FEXP-CAP-PREVIEW CAP.ID-A !
    S" Selected file preview"
    FEXP-CAP-PREVIEW CAP.TITLE-U ! FEXP-CAP-PREVIEW CAP.TITLE-A !
    S" Read a bounded valid UTF-8 preview of the selected VFS file"
    FEXP-CAP-PREVIEW CAP.DESC-U ! FEXP-CAP-PREVIEW CAP.DESC-A !
    _FEXP-PREVIEW-SCHEMA FEXP-CAP-PREVIEW CAP.OUT-SCHEMA !
    CAP-E-OBSERVE FEXP-CAP-PREVIEW CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
    FEXP-CAP-PREVIEW CAP.FLAGS !
    ['] _FEXP-CAP-PREVIEW-HANDLER FEXP-CAP-PREVIEW CAP.HANDLER-XT !

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
\ FEXP-RUN owns the shell lifecycle and may block/yield in its event loop.
\ Invoke it only on the applet's owner core; cross-core callers must post a
\ launch request rather than holding _fexp-guard for the applet lifetime.
: FEXP-RUN         _fexp-run-xt EXECUTE ;
: FEXP-CLIP-COPY   _fexp-clip-copy-xt  _fexp-guard WITH-GUARD ;
: FEXP-CLIP-CUT    _fexp-clip-cut-xt   _fexp-guard WITH-GUARD ;
: FEXP-CLIP-PASTE  _fexp-clip-paste-xt _fexp-guard WITH-GUARD ;
[THEN] [THEN]
