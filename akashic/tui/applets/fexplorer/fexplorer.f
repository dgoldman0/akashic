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
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/string.f

\ =====================================================================
\  §2 — Constants
\ =====================================================================

256 CONSTANT _FEXP-MAX-DIR        \ max directory entries in detail list
 80 CONSTANT _FEXP-LINE-W         \ formatted line width (chars)
512 CONSTANT _FEXP-PATH-CAP       \ path buffer capacity
32768 CONSTANT _FEXP-PREVIEW-CAP  \ preview buffer 32 KiB

\ Sort modes
0 CONSTANT FEXP-SORT-NAME
1 CONSTANT FEXP-SORT-SIZE
2 CONSTANT FEXP-SORT-TYPE

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

\ UIDL element handles (set in INIT-XT via UTUI-BY-ID)
VARIABLE _FEXP-E-SIDEBAR    \ <region id="sidebar">
VARIABLE _FEXP-E-DETAIL     \ <region id="detail">
VARIABLE _FEXP-E-PREVIEW    \ <textarea id="preview">
VARIABLE _FEXP-E-TABS       \ <tabs id="tabs">
VARIABLE _FEXP-E-SBAR-L     \ <label id="sbar-left">
VARIABLE _FEXP-E-SBAR-R     \ <label id="sbar-right">

\ Widget handles (native widgets mounted on UIDL regions)
VARIABLE _FEXP-EXPL         \ explorer widget (EXPL-NEW)
VARIABLE _FEXP-LIST         \ list widget (LST-NEW)

\ Business state
VARIABLE _FEXP-VFS           \ VFS instance
VARIABLE _FEXP-SORT          \ sort mode (0=name, 1=size, 2=type)
VARIABLE _FEXP-CUR-DIR       \ inode of currently displayed directory

\ Clipboard
VARIABLE _FEXP-CLIP-IN       \ clipboard inode
VARIABLE _FEXP-CLIP-OP       \ clipboard operation (0/1/2)

\ =====================================================================
\  §5 — Buffers
\ =====================================================================

CREATE _FEXP-ITEMS   _FEXP-MAX-DIR 2 * CELLS ALLOT
CREATE _FEXP-INODES  _FEXP-MAX-DIR CELLS ALLOT
CREATE _FEXP-LINES   _FEXP-MAX-DIR _FEXP-LINE-W * ALLOT
VARIABLE _FEXP-CNT

CREATE _FEXP-PREV-BUF  _FEXP-PREVIEW-CAP ALLOT
CREATE _FEXP-PATH-BUF  _FEXP-PATH-CAP ALLOT
VARIABLE _FEXP-PATH-LEN

\ Status bar text scratch
CREATE _FEXP-SLEFT   128 ALLOT
VARIABLE _FEXP-SLEFT-L

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
            DUP IN.TYPE @ ROT DUP IN.TYPE @
            2DUP <> IF
                NIP NIP NIP - NEGATE
            ELSE
                2DROP SWAP
                DUP IN.NAME @ _VFS-STR-GET
                2SWAP
                DUP IN.NAME @ _VFS-STR-GET
                STR-ICMP NEGATE
            THEN
        ENDOF
        DUP IN.NAME @ _VFS-STR-GET
        ROT
        DUP IN.NAME @ _VFS-STR-GET
        >R >R DROP R> R>
        2SWAP ROT DROP
        STR-ICMP
        0
    ENDCASE ;

VARIABLE _FSW-TMP

: _FEXP-SWAP-ITEMS  ( i j -- )
    2DUP = IF 2DROP EXIT THEN
    DUP CELLS _FEXP-INODES + @ _FSW-TMP !
    OVER CELLS _FEXP-INODES + @  OVER CELLS _FEXP-INODES + !
    _FSW-TMP @ OVER CELLS _FEXP-INODES + !
    DUP 2 * CELLS _FEXP-ITEMS + @ _FSW-TMP !
    OVER 2 * CELLS _FEXP-ITEMS + @  OVER 2 * CELLS _FEXP-ITEMS + !
    _FSW-TMP @ OVER 2 * CELLS _FEXP-ITEMS + !
    DUP 2 * CELLS _FEXP-ITEMS + 8 + @ _FSW-TMP !
    OVER 2 * CELLS _FEXP-ITEMS + 8 + @  OVER 2 * CELLS _FEXP-ITEMS + 8 + !
    _FSW-TMP @ OVER 2 * CELLS _FEXP-ITEMS + 8 + !
    DUP _FEXP-LINE-W * _FEXP-LINES + _FEXP-PREV-BUF _FEXP-LINE-W CMOVE
    OVER _FEXP-LINE-W * _FEXP-LINES +  OVER _FEXP-LINE-W * _FEXP-LINES +
    _FEXP-LINE-W CMOVE
    _FEXP-PREV-BUF  OVER _FEXP-LINE-W * _FEXP-LINES +
    _FEXP-LINE-W CMOVE
    2DROP ;

: _FEXP-SORT-LIST  ( -- )
    _FEXP-CNT @ 2 < IF EXIT THEN
    _FEXP-CNT @ 1- 0
    DO
        _FEXP-CNT @ 1- I 1+
        DO
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

: _FEXP-LOAD-PREVIEW  ( inode -- )
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP EXIT THEN
    DUP IN.NAME @ _VFS-STR-GET
    VFS-CUR >R  _FEXP-VFS @ VFS-USE
    VFS-OPEN
    R> VFS-USE
    DUP 0= IF 2DROP EXIT THEN
    _FPV-FD ! DROP
    _FEXP-PREV-BUF _FEXP-PREVIEW-CAP _FPV-FD @ VFS-READ
    \ Set the UIDL textarea content via its materialized widget
    _FEXP-E-PREVIEW @ UTUI-WIDGET@ ?DUP IF
        _FEXP-PREV-BUF ROT TXTA-SET-TEXT
    ELSE DROP THEN
    _FPV-FD @ VFS-CLOSE
    ASHELL-DIRTY! ;

\ =====================================================================
\  §9 — Clipboard (copy / cut / paste)
\ =====================================================================

VARIABLE _FCP-SRC  VARIABLE _FCP-DST
VARIABLE _FCP-FDS  VARIABLE _FCP-FDD  VARIABLE _FCP-ACT

: FEXP-CLIP-COPY  ( -- )
    _FEXP-EXPL @ EXPL-SELECTED
    DUP 0= IF DROP EXIT THEN
    _FEXP-CLIP-IN !
    _FEXP-CLIP-COPY _FEXP-CLIP-OP !
    S" Copied to clipboard" 2000 ASHELL-TOAST ;

: FEXP-CLIP-CUT  ( -- )
    _FEXP-EXPL @ EXPL-SELECTED
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
    _FEXP-EXPL @ EXPL-SELECTED
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
    _FEXP-SLEFT ROT + SWAP CMOVE
    _FEXP-CNT @ NUM>STR NIP R> +
    _FEXP-SLEFT-L !
    \ Update UIDL label element text= attribute
    _FEXP-E-SBAR-L @ ?DUP IF
        S" text" _FEXP-SLEFT _FEXP-SLEFT-L @ UTUI-SET-ATTR
    THEN
    \ Right: path of selected item
    _FEXP-EXPL @ EXPL-SELECTED
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

: _FEXP-ON-OPEN  ( inode explorer -- )
    DROP
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE = IF
        _FEXP-LOAD-PREVIEW
        \ Switch to Preview tab via UIDL tabs state
        _FEXP-E-TABS @ ?DUP IF UTUI-WIDGET@ ?DUP IF 1 SWAP ! THEN THEN
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
    DUP IN.TYPE @ VFS-T-FILE = IF _FEXP-LOAD-PREVIEW ELSE DROP THEN
    _FEXP-UPDATE-STATUS ;

\ =====================================================================
\  §13 — Action handlers (registered via UTUI-DO!)
\ =====================================================================
\
\  All action handlers have signature ( elem -- ) per UTUI-DO! contract.
\  We ignore the element argument since our actions are global.

: _FEXP-DO-QUIT       ( elem -- ) DROP ASHELL-QUIT ;
: _FEXP-DO-NEW-FILE   ( elem -- ) DROP _FEXP-EXPL @ EXPL-NEW-FILE  ASHELL-DIRTY! ;
: _FEXP-DO-NEW-DIR    ( elem -- ) DROP _FEXP-EXPL @ EXPL-NEW-DIR   ASHELL-DIRTY! ;
: _FEXP-DO-DELETE     ( elem -- ) DROP _FEXP-EXPL @ EXPL-DELETE     _FEXP-REFRESH-DETAIL ;
: _FEXP-DO-RENAME     ( elem -- ) DROP _FEXP-EXPL @ EXPL-RENAME    ASHELL-DIRTY! ;
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

\ Go-to-path: use DLG-CONFIRM for now (simple approach)
VARIABLE _FEXP-PROP-IN

: _FEXP-DO-GOTO  ( elem -- )
    DROP
    S" Go to Path" 2000 ASHELL-TOAST ;

: _FEXP-DO-PROPS  ( elem -- )
    DROP
    _FEXP-EXPL @ EXPL-SELECTED
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
    _FEXP-PREV-BUF SWAP DLG-CONFIRM DROP ;

\ =====================================================================
\  §14 — INIT callback ("document ready")
\ =====================================================================

: FEXP-INIT-CB  ( -- )
    \ Initialize business state
    FEXP-SORT-NAME _FEXP-SORT !
    0 _FEXP-CNT !
    0 _FEXP-CLIP-IN !
    _FEXP-CLIP-NONE _FEXP-CLIP-OP !
    0 _FEXP-CUR-DIR !

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
    _FEXP-ITEMS 0 ROT LST-NEW
    _FEXP-LIST !
    ['] _FEXP-ON-LIST-SEL _FEXP-LIST @ LST-ON-SELECT
    _FEXP-LIST @ _FEXP-E-DETAIL @ UTUI-WIDGET-SET

    \ Register all named actions
    S" quit"           ['] _FEXP-DO-QUIT           UTUI-DO!
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

    \ Populate initial directory listing
    _FEXP-VFS @ V.ROOT @ DUP _FEXP-CUR-DIR !
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
: FEXP-EVENT-CB  ( ev -- flag )
    DROP 0 ;

\ =====================================================================
\  §16 — SHUTDOWN callback
\ =====================================================================

: FEXP-SHUTDOWN-CB  ( -- )
    \ Detach widgets from UIDL elements before freeing
    _FEXP-E-SIDEBAR @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _FEXP-E-DETAIL @  ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    \ Free native widgets
    _FEXP-EXPL @ ?DUP IF EXPL-FREE THEN
    _FEXP-LIST @ ?DUP IF LST-FREE THEN
    \ (UIDL buffer is owned and freed by the host shell/desk)
    \ Zero handles
    0 _FEXP-EXPL !  0 _FEXP-LIST !
    0 _FEXP-E-SIDEBAR !  0 _FEXP-E-DETAIL !
    0 _FEXP-E-PREVIEW !  0 _FEXP-E-TABS !
    0 _FEXP-E-SBAR-L !   0 _FEXP-E-SBAR-R ! ;

\ =====================================================================
\  §17 — Entry Point & Standalone Runner
\ =====================================================================

: FEXP-ENTRY  ( desc -- )
    DUP APP-DESC-INIT
    ['] FEXP-INIT-CB     OVER APP.INIT-XT !
    ['] FEXP-EVENT-CB    OVER APP.EVENT-XT !
    0                    OVER APP.TICK-XT !
    0                    OVER APP.PAINT-XT !
    ['] FEXP-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
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
