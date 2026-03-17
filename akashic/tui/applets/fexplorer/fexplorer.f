\ =================================================================
\  fexplorer.f — Full-Featured File Explorer Applet
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: FEXP- / _FEXP-
\  Depends on: akashic-tui-explorer, akashic-tui-split,
\              akashic-tui-list, akashic-tui-tabs,
\              akashic-tui-status, akashic-tui-menu,
\              akashic-tui-textarea, akashic-tui-input,
\              akashic-tui-dialog, akashic-tui-app-shell,
\              akashic-tui-app-desc, akashic-vfs
\
\  Dual-pane file manager with:
\   - Tree sidebar (EXPL-* widget: rename, delete, new, hidden)
\   - Detail list panel (file name / size / type columns)
\   - Text preview panel (read-only textarea)
\   - Menu bar (File / Edit / View / Tools)
\   - Status bar (item count, file size, path)
\   - Clipboard (copy / cut / paste via VFS)
\   - Go-to-path overlay (Ctrl+G)
\   - Sort modes (name / size / type)
\   - Properties dialog (Ctrl+I)
\
\  Runs as APP-DESC app via app-shell.f.
\  Entry:  FEXP-ENTRY ( desc -- )   for desk/app-loader launch
\          FEXP-RUN   ( -- )        standalone execution
\ =================================================================

PROVIDED akashic-tui-fexplorer

\ =====================================================================
\  §1 — Dependencies
\ =====================================================================

REQUIRE ../../widgets/explorer.f
REQUIRE ../../widgets/split.f
REQUIRE ../../widgets/list.f
REQUIRE ../../widgets/tabs.f
REQUIRE ../../widgets/status.f
REQUIRE ../../widgets/menu.f
REQUIRE ../../widgets/textarea.f
REQUIRE ../../widgets/input.f
REQUIRE ../../widgets/dialog.f
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../../utils/fs/vfs.f

\ =====================================================================
\  §2 — Constants
\ =====================================================================

256 CONSTANT _FEXP-MAX-DIR      \ max directory entries in detail list
 80 CONSTANT _FEXP-LINE-W       \ formatted line width (chars)
512 CONSTANT _FEXP-PATH-CAP     \ path buffer capacity
256 CONSTANT _FEXP-GOTO-CAP     \ goto-input buffer capacity
32768 CONSTANT _FEXP-PREVIEW-CAP  \ preview buffer 32 KiB

\ Sort modes
0 CONSTANT FEXP-SORT-NAME
1 CONSTANT FEXP-SORT-SIZE
2 CONSTANT FEXP-SORT-TYPE

\ Clipboard operations
0 CONSTANT _FEXP-CLIP-NONE
1 CONSTANT _FEXP-CLIP-COPY
2 CONSTANT _FEXP-CLIP-CUT

\ Focus targets
0 CONSTANT _FEXP-FOCUS-TREE
1 CONSTANT _FEXP-FOCUS-DETAIL
2 CONSTANT _FEXP-FOCUS-PREVIEW
3 CONSTANT _FEXP-FOCUS-MENU
4 CONSTANT _FEXP-FOCUS-GOTO

\ Default split ratio (pane A = tree width in columns)
30 CONSTANT _FEXP-DEF-RATIO

\ =====================================================================
\  §3 — Module Variables
\ =====================================================================

\ Widget handles
VARIABLE _FEXP-EXPL     \ explorer widget (tree sidebar)
VARIABLE _FEXP-SPLIT    \ split pane widget
VARIABLE _FEXP-TABS     \ tabs widget (Details / Preview)
VARIABLE _FEXP-LIST     \ list widget (detail panel)
VARIABLE _FEXP-TXTA     \ textarea widget (preview panel)
VARIABLE _FEXP-SBAR     \ status bar widget
VARIABLE _FEXP-MENU     \ menu bar widget

\ Regions
VARIABLE _FEXP-ROOT-RGN   \ root region from shell
VARIABLE _FEXP-MENU-RGN   \ top row for menu
VARIABLE _FEXP-BODY-RGN   \ rows 1..H-2 for split
VARIABLE _FEXP-STAT-RGN   \ bottom row for status bar

\ State
VARIABLE _FEXP-FOCUS    \ current focus target
VARIABLE _FEXP-VFS      \ the VFS instance
VARIABLE _FEXP-SORT     \ sort mode (0=name, 1=size, 2=type)
VARIABLE _FEXP-CUR-DIR  \ inode of currently displayed directory

\ Clipboard
VARIABLE _FEXP-CLIP-IN  \ clipboard inode
VARIABLE _FEXP-CLIP-OP  \ clipboard operation (0/1/2)

\ Goto-path overlay
VARIABLE _FEXP-GOTO-W   \ input widget for goto (0 = hidden)
VARIABLE _FEXP-GOTO-ACT \ flag: goto overlay active

\ =====================================================================
\  §3b — Buffers
\ =====================================================================

\ Detail list items: array of (addr, len) pairs = 16 bytes each
CREATE _FEXP-ITEMS  _FEXP-MAX-DIR 2 * CELLS ALLOT

\ Parallel inode array for detail list
CREATE _FEXP-INODES  _FEXP-MAX-DIR CELLS ALLOT

\ Formatted line buffer: each line is _FEXP-LINE-W chars
CREATE _FEXP-LINES  _FEXP-MAX-DIR _FEXP-LINE-W * ALLOT

\ Item count in current detail list
VARIABLE _FEXP-CNT

\ Preview buffer
CREATE _FEXP-PREV-BUF  _FEXP-PREVIEW-CAP ALLOT

\ Path buffer
CREATE _FEXP-PATH-BUF  _FEXP-PATH-CAP ALLOT
VARIABLE _FEXP-PATH-LEN

\ Goto input buffer
CREATE _FEXP-GOTO-BUF  _FEXP-GOTO-CAP ALLOT

\ Status bar text buffers (left and right)
CREATE _FEXP-SLEFT  128 ALLOT
VARIABLE _FEXP-SLEFT-L
CREATE _FEXP-SRIGHT 256 ALLOT
VARIABLE _FEXP-SRIGHT-L

\ Scratch for number formatting
CREATE _FEXP-NBUF  24 ALLOT

\ =====================================================================
\  §4 — Utility: number-to-string, size formatter, path builder
\ =====================================================================

\ _FEXP-U>S ( u -- addr len )
\   Convert unsigned number to string in scratch buffer.
\   Returns pointer into _FEXP-NBUF.  Overwrites on each call.
VARIABLE _FNU-N
VARIABLE _FNU-P

: _FEXP-U>S  ( u -- addr len )
    _FNU-N !
    _FEXP-NBUF 23 + _FNU-P !   \ start at end of buffer
    _FNU-N @ 0= IF
        [CHAR] 0 _FNU-P @ C!
        _FNU-P @ 1 EXIT
    THEN
    BEGIN _FNU-N @ 0<> WHILE
        _FNU-N @ 10 MOD [CHAR] 0 +
        _FNU-P @ C!
        -1 _FNU-P +!
        _FNU-N @ 10 / _FNU-N !
    REPEAT
    _FNU-P @ 1+                     ( addr )
    _FEXP-NBUF 24 +                 ( addr end )
    OVER -                          ( addr len )
;

\ _FEXP-SIZE-FMT ( size -- addr len )
\   Format file size as human-readable string.
\   Uses a separate 24-byte buffer to avoid corruption.
\   e.g., 0 → "0", 512 → "512", 2048 → "2K", 1048576 → "1M"
VARIABLE _FSF-SZ
CREATE _FSF-BUF  24 ALLOT
VARIABLE _FSF-P

: _FEXP-SIZE-FMT  ( size -- addr len )
    _FSF-SZ !
    _FSF-SZ @ 1024 < IF
        _FSF-SZ @ _FEXP-U>S EXIT
    THEN
    _FSF-SZ @ 1048576 < IF
        \ KiB — copy number digits into _FSF-BUF, then append K
        _FSF-SZ @ 1024 / _FEXP-U>S      ( addr len )
        DUP >R
        OVER _FSF-BUF R@ CMOVE          ( addr len )
        2DROP
        [CHAR] K _FSF-BUF R@ + C!
        _FSF-BUF R> 1+                   ( buf-addr len+1 )
        EXIT
    THEN
    \ MiB — same pattern with M
    _FSF-SZ @ 1048576 / _FEXP-U>S        ( addr len )
    DUP >R
    OVER _FSF-BUF R@ CMOVE               ( addr len )
    2DROP
    [CHAR] M _FSF-BUF R@ + C!
    _FSF-BUF R> 1+                        ( buf-addr len+1 )
;

\ _FEXP-BUILD-PATH ( inode -- )
\   Build full path from root to inode into _FEXP-PATH-BUF.
\   Sets _FEXP-PATH-LEN.
\   Strategy: walk up via IN.PARENT, collect names, then reverse.
\   Use iterative approach with a small stack of name segments.

\ Max depth for path building
16 CONSTANT _FBP-MAX-DEPTH
CREATE _FBP-ADDRS  _FBP-MAX-DEPTH CELLS ALLOT
CREATE _FBP-LENS   _FBP-MAX-DEPTH CELLS ALLOT
VARIABLE _FBP-D   \ depth counter

: _FEXP-BUILD-PATH  ( inode -- )
    0 _FBP-D !
    \ Walk up, collecting name segments
    BEGIN
        DUP IN.PARENT @ 0<>               \ stop at root (parent=0)
        _FBP-D @ _FBP-MAX-DEPTH < AND
    WHILE
        DUP IN.NAME @ _VFS-STR-GET        ( inode na nu )
        _FBP-D @ CELLS _FBP-LENS + !      ( inode na )
        _FBP-D @ CELLS _FBP-ADDRS + !     ( inode )
        1 _FBP-D +!
        IN.PARENT @
    REPEAT
    DROP
    \ Build forward path: /seg1/seg2/.../segN
    0 _FEXP-PATH-LEN !
    _FBP-D @ 0= IF
        \ Root only
        [CHAR] / _FEXP-PATH-BUF C!
        1 _FEXP-PATH-LEN !
        EXIT
    THEN
    _FBP-D @ 1- 0 SWAP
    DO
        \ Append "/"
        [CHAR] / _FEXP-PATH-BUF _FEXP-PATH-LEN @ + C!
        1 _FEXP-PATH-LEN +!
        \ Append segment name
        I CELLS _FBP-ADDRS + @        ( seg-addr )
        I CELLS _FBP-LENS + @         ( seg-addr seg-len )
        DUP _FEXP-PATH-LEN @ + _FEXP-PATH-CAP >= IF
            \ Truncate
            2DROP LEAVE
        THEN
        OVER                           ( seg-addr seg-len seg-addr )
        _FEXP-PATH-BUF _FEXP-PATH-LEN @ +  ( sa sl sa dst )
        SWAP DROP                      ( sa sl dst )
        SWAP DUP >R                    ( sa dst sl  R: sl )
        CMOVE                          ( --  R: sl )
        R> _FEXP-PATH-LEN +!
    -1 +LOOP
;

\ =====================================================================
\  §5 — Detail List: populate from directory inode children
\ =====================================================================
\
\  Walks children of a directory inode and fills _FEXP-ITEMS,
\  _FEXP-INODES, _FEXP-LINES with formatted entries.

VARIABLE _FDL-IN    \ current child inode during walk
VARIABLE _FDL-I     \ current item index

\ _FEXP-FORMAT-LINE ( inode index -- )
\   Format one detail-list line at _FEXP-LINES[index * LINE-W].
\   Format: "name________________  size  type"
VARIABLE _FFL-IN
VARIABLE _FFL-IDX
VARIABLE _FFL-DST
VARIABLE _FFL-COL

: _FEXP-FORMAT-LINE  ( inode index -- )
    _FFL-IDX !  _FFL-IN !
    _FFL-IDX @ _FEXP-LINE-W * _FEXP-LINES +  _FFL-DST !
    \ Fill line with spaces
    _FFL-DST @ _FEXP-LINE-W 32 FILL
    0 _FFL-COL !
    \ Column 1: Name (max 40 chars)
    _FFL-IN @ IN.NAME @ _VFS-STR-GET      ( na nu )
    DUP 40 > IF DROP 40 THEN              ( na nu' )
    DUP >R
    _FFL-DST @ SWAP CMOVE                  ( -- )
    R> _FFL-COL !
    \ Column 2: Size at col 44 (right-aligned, 8 chars)
    _FFL-IN @ IN.TYPE @ VFS-T-DIR = IF
        \ Directories show "<DIR>"
        S" <DIR>"
    ELSE
        _FFL-IN @ IN.SIZE-LO @ _FEXP-SIZE-FMT
    THEN                                   ( sa su )
    \ Right-align: place at col (52 - len)
    DUP 52 SWAP -                          ( sa su start-col )
    DUP 44 < IF DROP 44 THEN              ( sa su col )
    _FFL-DST @ +                           ( sa su dst )
    SWAP CMOVE                             ( -- )
    \ Column 3: Type at col 54
    _FFL-IN @ IN.TYPE @ VFS-T-DIR = IF
        S" dir "
    ELSE
        S" file"
    THEN                                   ( ta tu )
    _FFL-DST @ 54 + SWAP CMOVE            ( -- )
;

\ _FEXP-POPULATE-DIR ( dir-inode -- )
\   Fill item arrays from directory children.
: _FEXP-POPULATE-DIR  ( dir-inode -- )
    _FDL-IN !
    0 _FDL-I !
    \ Ensure children loaded
    _FDL-IN @ _FEXP-VFS @ _VFS-ENSURE-CHILDREN
    \ Walk child linked list
    _FDL-IN @ IN.CHILD @
    BEGIN DUP 0<> _FDL-I @ _FEXP-MAX-DIR < AND WHILE
        \ Store inode
        DUP _FDL-I @ CELLS _FEXP-INODES + !
        \ Format line
        DUP _FDL-I @ _FEXP-FORMAT-LINE
        \ Set item entry: (addr, len)
        _FDL-I @ _FEXP-LINE-W * _FEXP-LINES +
        _FDL-I @ 2 * CELLS _FEXP-ITEMS + !        \ addr
        _FEXP-LINE-W
        _FDL-I @ 2 * CELLS _FEXP-ITEMS + 8 + !   \ len
        1 _FDL-I +!
        IN.SIBLING @
    REPEAT DROP
    _FDL-I @ _FEXP-CNT !
;

\ =====================================================================
\  §6 — Sort
\ =====================================================================
\
\  Bubble sort the parallel arrays (_FEXP-ITEMS, _FEXP-INODES,
\  _FEXP-LINES) according to _FEXP-SORT mode.

\ String compare (lexicographic, case-insensitive)
VARIABLE _FSC-A1  VARIABLE _FSC-L1
VARIABLE _FSC-A2  VARIABLE _FSC-L2

\ Simple UPPER helper
: _FEXP-UPPER  ( c -- C )
    DUP [CHAR] a >= OVER [CHAR] z <= AND IF 32 - THEN ;

VARIABLE _FSC-D   \ temp diff

: _FEXP-STR-CMP  ( a1 l1 a2 l2 -- n )
    _FSC-L2 !  _FSC-A2 !  _FSC-L1 !  _FSC-A1 !
    _FSC-L1 @ _FSC-L2 @ MIN  0
    ?DO
        _FSC-A1 @ I + C@ _FEXP-UPPER
        _FSC-A2 @ I + C@ _FEXP-UPPER
        -  _FSC-D !
        _FSC-D @ 0<> IF  _FSC-D @  UNLOOP EXIT  THEN
    LOOP
    _FSC-L1 @ _FSC-L2 @ - ;

\ Compare two inodes by current sort mode
\ Returns: negative if a<b, 0 if equal, positive if a>b
: _FEXP-CMP  ( inode-a inode-b -- n )
    _FEXP-SORT @ CASE
        FEXP-SORT-SIZE OF
            IN.SIZE-LO @ SWAP IN.SIZE-LO @ SWAP -
        ENDOF
        FEXP-SORT-TYPE OF
            \ dirs first, then files; within same type, sort by name
            DUP IN.TYPE @  ROT DUP IN.TYPE @  ( b b-type a a-type )
            2DUP <> IF
                \ Different types: dir (2) < file (1) → invert
                NIP NIP NIP - NEGATE
            ELSE
                \ Same type: compare names
                2DROP
                SWAP
                DUP IN.NAME @ _VFS-STR-GET    ( a b na nl )
                2SWAP
                DUP IN.NAME @ _VFS-STR-GET    ( na nl nb nbl )
                _FEXP-STR-CMP NEGATE
            THEN
        ENDOF
        \ Default: name sort
        DUP IN.NAME @ _VFS-STR-GET            ( a b na nl )
        ROT                                    ( a na nl b )
        DUP IN.NAME @ _VFS-STR-GET            ( a na nl b nb nbl )
        >R >R                                  ( a na nl b  R: nbl nb )
        DROP                                   ( a na nl  R: nbl nb )
        R> R>                                  ( a na nl nb nbl )
        2SWAP ROT DROP                         ( na nl nb nbl )
        _FEXP-STR-CMP
        0                                      \ dummy endof value
    ENDCASE
;

\ Swap two items in all three parallel arrays
VARIABLE _FSW-TMP

: _FEXP-SWAP-ITEMS  ( i j -- )
    2DUP = IF 2DROP EXIT THEN
    \ Swap inodes
    DUP CELLS _FEXP-INODES + @  _FSW-TMP !
    OVER CELLS _FEXP-INODES + @  OVER CELLS _FEXP-INODES + !
    _FSW-TMP @  OVER CELLS _FEXP-INODES + !
    \ Swap items (2 cells each)
    DUP 2 * CELLS _FEXP-ITEMS + @  _FSW-TMP !
    OVER 2 * CELLS _FEXP-ITEMS + @  OVER 2 * CELLS _FEXP-ITEMS + !
    _FSW-TMP @  OVER 2 * CELLS _FEXP-ITEMS + !
    DUP 2 * CELLS _FEXP-ITEMS + 8 + @  _FSW-TMP !
    OVER 2 * CELLS _FEXP-ITEMS + 8 + @  OVER 2 * CELLS _FEXP-ITEMS + 8 + !
    _FSW-TMP @  OVER 2 * CELLS _FEXP-ITEMS + 8 + !
    \ Swap formatted lines (copy LINE-W bytes through scratch)
    \ Use _FEXP-PREV-BUF as temporary (large enough)
    DUP  _FEXP-LINE-W * _FEXP-LINES +   _FEXP-PREV-BUF  _FEXP-LINE-W CMOVE
    OVER _FEXP-LINE-W * _FEXP-LINES +   OVER _FEXP-LINE-W * _FEXP-LINES +
    _FEXP-LINE-W CMOVE
    _FEXP-PREV-BUF   OVER _FEXP-LINE-W * _FEXP-LINES +
    _FEXP-LINE-W CMOVE
    2DROP
;

\ _FEXP-SORT-LIST ( -- )
\   Bubble-sort the detail list by current sort mode.
: _FEXP-SORT-LIST  ( -- )
    _FEXP-CNT @ 2 < IF EXIT THEN
    _FEXP-CNT @ 1-  0
    DO
        _FEXP-CNT @ 1-  I 1+
        DO
            J CELLS _FEXP-INODES + @
            I CELLS _FEXP-INODES + @
            _FEXP-CMP 0> IF
                J I _FEXP-SWAP-ITEMS
            THEN
        LOOP
    LOOP
;

\ =====================================================================
\  §7 — Preview: load file into textarea
\ =====================================================================

VARIABLE _FPV-FD

: _FEXP-LOAD-PREVIEW  ( inode -- )
    \ Only for files
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP EXIT THEN
    \ Build path and open
    DUP IN.NAME @ _VFS-STR-GET            ( inode na nu )
    \ Save/restore VFS-CUR
    VFS-CUR >R
    _FEXP-VFS @ VFS-USE
    VFS-OPEN                               ( inode fd|0 )
    R> VFS-USE
    DUP 0= IF 2DROP EXIT THEN
    _FPV-FD !
    DROP                                   ( -- )
    \ Read up to PREVIEW-CAP bytes
    _FEXP-PREV-BUF _FEXP-PREVIEW-CAP _FPV-FD @ VFS-READ  ( actual )
    \ Set textarea content
    _FEXP-PREV-BUF SWAP _FEXP-TXTA @ TXTA-SET-TEXT
    \ Close fd
    _FPV-FD @ VFS-CLOSE
    ASHELL-DIRTY!
;

\ =====================================================================
\  §8 — Clipboard (copy / cut / paste)
\ =====================================================================
\  For initial release: simple name-based copy within same VFS.
\  Copy: record source inode + op.
\  Cut:  record source inode + op.
\  Paste: create new entry in target dir, transfer data, optionally rm.

VARIABLE _FCP-SRC    \ source inode
VARIABLE _FCP-DST    \ destination dir inode
VARIABLE _FCP-FDS    \ source fd
VARIABLE _FCP-FDD    \ dest fd
VARIABLE _FCP-ACT    \ actual bytes read

: FEXP-CLIP-COPY  ( -- )
    _FEXP-EXPL @ EXPL-SELECTED          ( inode )
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
    \ Determine target directory
    _FEXP-EXPL @ EXPL-SELECTED           ( sel-inode )
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = IF
        \ Selected is a dir — paste into it
    ELSE
        IN.PARENT @                       \ parent of file
    THEN
    _FCP-DST !
    _FEXP-CLIP-IN @ _FCP-SRC !
    \ Only support file copy for now
    _FCP-SRC @ IN.TYPE @ VFS-T-FILE <> IF
        S" Dir copy not supported" 2000 ASHELL-TOAST EXIT
    THEN
    \ Get source name
    _FCP-SRC @ IN.NAME @ _VFS-STR-GET     ( na nu )
    \ Save CWD, set to target dir
    _FEXP-VFS @ V.CWD @ >R
    _FCP-DST @  _FEXP-VFS @ V.CWD !
    \ Create destination file
    2DUP _FEXP-VFS @ VFS-MKFILE           ( na nu new-inode|0 )
    DUP 0= IF
        DROP 2DROP
        R> _FEXP-VFS @ V.CWD !
        S" Paste failed: mkfile" 2000 ASHELL-TOAST EXIT
    THEN
    DROP                                   ( na nu )
    \ Open source and dest
    VFS-CUR >R  _FEXP-VFS @ VFS-USE
    \ CWD is source's parent for open
    _FCP-SRC @ IN.PARENT @ _FEXP-VFS @ V.CWD !
    _FCP-SRC @ IN.NAME @ _VFS-STR-GET VFS-OPEN  _FCP-FDS !
    \ CWD is dest
    _FCP-DST @ _FEXP-VFS @ V.CWD !
    VFS-OPEN  _FCP-FDD !                  ( -- )
    R> VFS-USE
    \ Copy data
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
    \ If cut, remove source
    _FEXP-CLIP-OP @ _FEXP-CLIP-CUT = IF
        _FCP-SRC @ IN.PARENT @ _FEXP-VFS @ V.CWD !
        _FCP-SRC @ IN.NAME @ _VFS-STR-GET _FEXP-VFS @ VFS-RM DROP
    THEN
    \ Restore CWD and sync
    R> _FEXP-VFS @ V.CWD !
    _FEXP-VFS @ VFS-SYNC DROP
    \ Reset clipboard
    0 _FEXP-CLIP-IN !
    _FEXP-CLIP-NONE _FEXP-CLIP-OP !
    \ Refresh
    _FEXP-EXPL @ EXPL-REFRESH
    _FEXP-CUR-DIR @ ?DUP IF _FEXP-POPULATE-DIR _FEXP-SORT-LIST THEN
    _FEXP-LIST @ ?DUP IF _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS THEN
    S" Pasted!" 1500 ASHELL-TOAST
    ASHELL-DIRTY!
;

\ =====================================================================
\  §9 — Status bar update helpers
\ =====================================================================

VARIABLE _FSU-N

: _FEXP-UPDATE-STATUS  ( -- )
    \ Left: "N items"
    _FEXP-CNT @ _FEXP-U>S                 ( na nu )
    _FEXP-SLEFT SWAP CMOVE                ( -- ; number copied )
    _FEXP-CNT @ _FEXP-U>S NIP             ( nu )
    S"  items" DUP >R
    _FEXP-SLEFT ROT + SWAP CMOVE
    _FEXP-CNT @ _FEXP-U>S NIP R> +
    _FEXP-SLEFT-L !
    _FEXP-SBAR @ _FEXP-SLEFT _FEXP-SLEFT-L @ SBAR-LEFT!
    \ Right: path of selected item
    _FEXP-EXPL @ EXPL-SELECTED            ( inode )
    DUP 0<> IF
        _FEXP-BUILD-PATH
        _FEXP-SBAR @ _FEXP-PATH-BUF _FEXP-PATH-LEN @ SBAR-RIGHT!
    ELSE
        DROP
        _FEXP-SBAR @ S" /" SBAR-RIGHT!
    THEN
    _FEXP-SBAR @ WDG-DIRTY
;

\ =====================================================================
\  §10 — Go-to-path overlay
\ =====================================================================

: _FEXP-GOTO-SUBMIT  ( input-widget -- )
    INP-GET-TEXT                            ( addr len )
    DUP 0= IF 2DROP EXIT THEN
    _FEXP-VFS @ VFS-RESOLVE                ( inode | 0 )
    DUP 0= IF
        DROP
        S" Path not found" 2000 ASHELL-TOAST
    ELSE
        DUP IN.TYPE @ VFS-T-DIR = IF
            _FEXP-EXPL @ EXPL-ROOT!
        ELSE
            _FEXP-LOAD-PREVIEW
        THEN
    THEN
    \ Hide goto overlay
    0 _FEXP-GOTO-ACT !
    _FEXP-GOTO-W @ ?DUP IF INP-FREE THEN
    0 _FEXP-GOTO-W !
    _FEXP-FOCUS-TREE _FEXP-FOCUS !
    ASHELL-DIRTY!
;

: _FEXP-GOTO-SHOW  ( -- )
    _FEXP-GOTO-ACT @ IF EXIT THEN        \ already showing
    -1 _FEXP-GOTO-ACT !
    \ Create input widget in the body region top row
    _FEXP-BODY-RGN @ 0 0 1
    _FEXP-BODY-RGN @ RGN-W RGN-SUB       ( rgn )
    _FEXP-GOTO-BUF _FEXP-GOTO-CAP INP-NEW
    DUP _FEXP-GOTO-W !
    ['] _FEXP-GOTO-SUBMIT OVER INP-ON-SUBMIT
    S" Go to: " ROT INP-SET-TEXT
    _FEXP-FOCUS-GOTO _FEXP-FOCUS !
    ASHELL-DIRTY!
;

: _FEXP-GOTO-CANCEL  ( -- )
    _FEXP-GOTO-ACT @ 0= IF EXIT THEN
    0 _FEXP-GOTO-ACT !
    _FEXP-GOTO-W @ ?DUP IF INP-FREE THEN
    0 _FEXP-GOTO-W !
    _FEXP-FOCUS-TREE _FEXP-FOCUS !
    ASHELL-DIRTY!
;

\ =====================================================================
\  §11 — Menu Data Structures & Action Callbacks
\ =====================================================================
\
\  Four menus: File, Edit, View, Tools.
\  Each menu is a top-level entry (32 bytes) pointing to an item array.
\  Each item is 32 bytes: label-addr, label-len, action-xt, flags.

\ --- File Menu Items ---
: _FEXP-ACT-NEW-FILE  ( -- )  _FEXP-EXPL @ EXPL-NEW-FILE  ASHELL-DIRTY! ;
: _FEXP-ACT-NEW-DIR   ( -- )  _FEXP-EXPL @ EXPL-NEW-DIR   ASHELL-DIRTY! ;
: _FEXP-ACT-DELETE    ( -- )  _FEXP-EXPL @ EXPL-DELETE     ASHELL-DIRTY! ;
: _FEXP-ACT-RENAME    ( -- )  _FEXP-EXPL @ EXPL-RENAME     ASHELL-DIRTY! ;
: _FEXP-ACT-REFRESH   ( -- )  _FEXP-EXPL @ EXPL-REFRESH    ASHELL-DIRTY! ;
: _FEXP-ACT-QUIT      ( -- )  ASHELL-QUIT ;

CREATE _FMNU-FILE-ITEMS  8 32 * ALLOT  \ 8 items × 32 bytes

: _FEXP-INIT-FILE-MENU  ( -- )
    _FMNU-FILE-ITEMS 8 32 * 0 FILL
    \ Item 0: New File
    S" New File"       _FMNU-FILE-ITEMS  0 + !   _FMNU-FILE-ITEMS  8 + !
    ['] _FEXP-ACT-NEW-FILE _FMNU-FILE-ITEMS 16 + !
    0                  _FMNU-FILE-ITEMS 24 + !
    \ Item 1: New Folder
    S" New Folder"     _FMNU-FILE-ITEMS 32 + !  _FMNU-FILE-ITEMS 40 + !
    ['] _FEXP-ACT-NEW-DIR  _FMNU-FILE-ITEMS 48 + !
    0                  _FMNU-FILE-ITEMS 56 + !
    \ Item 2: separator
    S" ───"            _FMNU-FILE-ITEMS 64 + !  _FMNU-FILE-ITEMS 72 + !
    0                  _FMNU-FILE-ITEMS 80 + !
    MNU-F-SEPARATOR    _FMNU-FILE-ITEMS 88 + !
    \ Item 3: Delete
    S" Delete"         _FMNU-FILE-ITEMS 96 + !  _FMNU-FILE-ITEMS 104 + !
    ['] _FEXP-ACT-DELETE   _FMNU-FILE-ITEMS 112 + !
    0                  _FMNU-FILE-ITEMS 120 + !
    \ Item 4: Rename
    S" Rename"         _FMNU-FILE-ITEMS 128 + !  _FMNU-FILE-ITEMS 136 + !
    ['] _FEXP-ACT-RENAME   _FMNU-FILE-ITEMS 144 + !
    0                  _FMNU-FILE-ITEMS 152 + !
    \ Item 5: separator
    S" ───"            _FMNU-FILE-ITEMS 160 + !  _FMNU-FILE-ITEMS 168 + !
    0                  _FMNU-FILE-ITEMS 176 + !
    MNU-F-SEPARATOR    _FMNU-FILE-ITEMS 184 + !
    \ Item 6: Refresh
    S" Refresh"        _FMNU-FILE-ITEMS 192 + !  _FMNU-FILE-ITEMS 200 + !
    ['] _FEXP-ACT-REFRESH  _FMNU-FILE-ITEMS 208 + !
    0                  _FMNU-FILE-ITEMS 216 + !
    \ Item 7: Quit
    S" Quit"           _FMNU-FILE-ITEMS 224 + !  _FMNU-FILE-ITEMS 232 + !
    ['] _FEXP-ACT-QUIT     _FMNU-FILE-ITEMS 240 + !
    0                  _FMNU-FILE-ITEMS 248 + !
;

\ --- Edit Menu Items ---
: _FEXP-ACT-COPY   ( -- )  FEXP-CLIP-COPY ;
: _FEXP-ACT-CUT    ( -- )  FEXP-CLIP-CUT ;
: _FEXP-ACT-PASTE  ( -- )  FEXP-CLIP-PASTE ;

CREATE _FMNU-EDIT-ITEMS  3 32 * ALLOT

: _FEXP-INIT-EDIT-MENU  ( -- )
    _FMNU-EDIT-ITEMS 3 32 * 0 FILL
    S" Copy"     _FMNU-EDIT-ITEMS  0 + !  _FMNU-EDIT-ITEMS  8 + !
    ['] _FEXP-ACT-COPY  _FMNU-EDIT-ITEMS 16 + !
    0                   _FMNU-EDIT-ITEMS 24 + !
    S" Cut"      _FMNU-EDIT-ITEMS 32 + !  _FMNU-EDIT-ITEMS 40 + !
    ['] _FEXP-ACT-CUT   _FMNU-EDIT-ITEMS 48 + !
    0                   _FMNU-EDIT-ITEMS 56 + !
    S" Paste"    _FMNU-EDIT-ITEMS 64 + !  _FMNU-EDIT-ITEMS 72 + !
    ['] _FEXP-ACT-PASTE  _FMNU-EDIT-ITEMS 80 + !
    0                   _FMNU-EDIT-ITEMS 88 + !
;

\ --- View Menu Items ---
: _FEXP-ACT-HIDDEN  ( -- )
    _FEXP-EXPL @ DUP EXPL-SHOW-HIDDEN? 0= SWAP EXPL-SHOW-HIDDEN!
    _FEXP-EXPL @ EXPL-REFRESH  ASHELL-DIRTY! ;
: _FEXP-ACT-SORT-NAME  ( -- )  FEXP-SORT-NAME _FEXP-SORT !  _FEXP-SORT-LIST  ASHELL-DIRTY! ;
: _FEXP-ACT-SORT-SIZE  ( -- )  FEXP-SORT-SIZE _FEXP-SORT !  _FEXP-SORT-LIST  ASHELL-DIRTY! ;
: _FEXP-ACT-SORT-TYPE  ( -- )  FEXP-SORT-TYPE _FEXP-SORT !  _FEXP-SORT-LIST  ASHELL-DIRTY! ;
: _FEXP-ACT-EXPAND-ALL  ( -- )  _FEXP-EXPL @ EXPL-EXPAND-ALL  ASHELL-DIRTY! ;
: _FEXP-ACT-COLLAPSE-ALL  ( -- )  _FEXP-EXPL @ EXPL-COLLAPSE-ALL  ASHELL-DIRTY! ;

CREATE _FMNU-VIEW-ITEMS  8 32 * ALLOT

: _FEXP-INIT-VIEW-MENU  ( -- )
    _FMNU-VIEW-ITEMS 8 32 * 0 FILL
    \ 0: Show Hidden
    S" Show Hidden"  _FMNU-VIEW-ITEMS  0 + !  _FMNU-VIEW-ITEMS  8 + !
    ['] _FEXP-ACT-HIDDEN    _FMNU-VIEW-ITEMS 16 + !
    0                       _FMNU-VIEW-ITEMS 24 + !
    \ 1: separator
    S" ───"          _FMNU-VIEW-ITEMS 32 + !  _FMNU-VIEW-ITEMS 40 + !
    0                _FMNU-VIEW-ITEMS 48 + !
    MNU-F-SEPARATOR  _FMNU-VIEW-ITEMS 56 + !
    \ 2: Sort by Name
    S" Sort: Name"   _FMNU-VIEW-ITEMS 64 + !  _FMNU-VIEW-ITEMS 72 + !
    ['] _FEXP-ACT-SORT-NAME _FMNU-VIEW-ITEMS 80 + !
    0                       _FMNU-VIEW-ITEMS 88 + !
    \ 3: Sort by Size
    S" Sort: Size"   _FMNU-VIEW-ITEMS 96 + !  _FMNU-VIEW-ITEMS 104 + !
    ['] _FEXP-ACT-SORT-SIZE _FMNU-VIEW-ITEMS 112 + !
    0                       _FMNU-VIEW-ITEMS 120 + !
    \ 4: Sort by Type
    S" Sort: Type"   _FMNU-VIEW-ITEMS 128 + !  _FMNU-VIEW-ITEMS 136 + !
    ['] _FEXP-ACT-SORT-TYPE _FMNU-VIEW-ITEMS 144 + !
    0                       _FMNU-VIEW-ITEMS 152 + !
    \ 5: separator
    S" ───"          _FMNU-VIEW-ITEMS 160 + !  _FMNU-VIEW-ITEMS 168 + !
    0                _FMNU-VIEW-ITEMS 176 + !
    MNU-F-SEPARATOR  _FMNU-VIEW-ITEMS 184 + !
    \ 6: Expand All
    S" Expand All"   _FMNU-VIEW-ITEMS 192 + !  _FMNU-VIEW-ITEMS 200 + !
    ['] _FEXP-ACT-EXPAND-ALL _FMNU-VIEW-ITEMS 208 + !
    0                       _FMNU-VIEW-ITEMS 216 + !
    \ 7: Collapse All
    S" Collapse All" _FMNU-VIEW-ITEMS 224 + !  _FMNU-VIEW-ITEMS 232 + !
    ['] _FEXP-ACT-COLLAPSE-ALL _FMNU-VIEW-ITEMS 240 + !
    0                       _FMNU-VIEW-ITEMS 248 + !
;

\ --- Tools Menu Items ---
: _FEXP-ACT-GOTO  ( -- )  _FEXP-GOTO-SHOW ;

VARIABLE _FEXP-PROP-IN

: _FEXP-ACT-PROPS  ( -- )
    _FEXP-EXPL @ EXPL-SELECTED
    DUP 0= IF DROP EXIT THEN
    _FEXP-PROP-IN !
    \ Build path for dialog message
    _FEXP-PROP-IN @ _FEXP-BUILD-PATH
    \ Build info string in preview buffer (reuse temporarily)
    _FEXP-PREV-BUF 0                       ( buf pos )
    \ "Path: "
    S" Path: " 2 PICK 2 PICK + SWAP CMOVE  ( buf pos )
    6 +                                     ( buf pos' )
    _FEXP-PATH-BUF OVER 2 PICK + SWAP
    _FEXP-PATH-LEN @ CMOVE
    _FEXP-PATH-LEN @ +
    \ "\nType: file/dir"
    S"   Type: " 2 PICK 2 PICK + SWAP CMOVE
    8 +
    _FEXP-PROP-IN @ IN.TYPE @ VFS-T-DIR = IF
        S" dir" 2 PICK 2 PICK + SWAP CMOVE
        3 +
    ELSE
        S" file" 2 PICK 2 PICK + SWAP CMOVE
        4 +
    THEN
    \ "  Size: N"
    S"   Size: " 2 PICK 2 PICK + SWAP CMOVE
    8 +
    _FEXP-PROP-IN @ IN.SIZE-LO @ _FEXP-SIZE-FMT  ( buf pos sa su )
    2 PICK 4 PICK + >R                    ( buf pos sa su  R: dst )
    R> SWAP DUP >R CMOVE                  ( buf pos  R: su )
    R> +
    \ Show dialog
    NIP                                     ( total-len )
    _FEXP-PREV-BUF SWAP DLG-CONFIRM DROP
;

CREATE _FMNU-TOOLS-ITEMS  2 32 * ALLOT

: _FEXP-INIT-TOOLS-MENU  ( -- )
    _FMNU-TOOLS-ITEMS 2 32 * 0 FILL
    S" Go to Path"   _FMNU-TOOLS-ITEMS  0 + !  _FMNU-TOOLS-ITEMS  8 + !
    ['] _FEXP-ACT-GOTO   _FMNU-TOOLS-ITEMS 16 + !
    0                    _FMNU-TOOLS-ITEMS 24 + !
    S" Properties"   _FMNU-TOOLS-ITEMS 32 + !  _FMNU-TOOLS-ITEMS 40 + !
    ['] _FEXP-ACT-PROPS  _FMNU-TOOLS-ITEMS 48 + !
    0                    _FMNU-TOOLS-ITEMS 56 + !
;

\ --- Top-level menu entries: 4 entries × 32 bytes ---
CREATE _FMNU-ENTRIES  4 32 * ALLOT

: _FEXP-INIT-MENUS  ( -- )
    _FEXP-INIT-FILE-MENU
    _FEXP-INIT-EDIT-MENU
    _FEXP-INIT-VIEW-MENU
    _FEXP-INIT-TOOLS-MENU
    _FMNU-ENTRIES 4 32 * 0 FILL
    \ File
    S" File"   _FMNU-ENTRIES  0 + !  _FMNU-ENTRIES  8 + !
    _FMNU-FILE-ITEMS  _FMNU-ENTRIES 16 + !
    8              _FMNU-ENTRIES 24 + !
    \ Edit
    S" Edit"   _FMNU-ENTRIES 32 + !  _FMNU-ENTRIES 40 + !
    _FMNU-EDIT-ITEMS  _FMNU-ENTRIES 48 + !
    3              _FMNU-ENTRIES 56 + !
    \ View
    S" View"   _FMNU-ENTRIES 64 + !  _FMNU-ENTRIES 72 + !
    _FMNU-VIEW-ITEMS  _FMNU-ENTRIES 80 + !
    8              _FMNU-ENTRIES 88 + !
    \ Tools
    S" Tools"  _FMNU-ENTRIES 96 + !  _FMNU-ENTRIES 104 + !
    _FMNU-TOOLS-ITEMS _FMNU-ENTRIES 112 + !
    2              _FMNU-ENTRIES 120 + !
;

\ =====================================================================
\  §12 — Callbacks: Explorer on-select / on-open
\ =====================================================================

: _FEXP-ON-SELECT  ( inode explorer -- )
    DROP                                    \ don't need the explorer widget
    DUP 0= IF DROP EXIT THEN
    \ If it's a directory, refresh the detail list
    DUP IN.TYPE @ VFS-T-DIR = IF
        DUP _FEXP-CUR-DIR !
        _FEXP-POPULATE-DIR
        _FEXP-SORT-LIST
        _FEXP-LIST @ ?DUP IF
            _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
        THEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY!
;

: _FEXP-ON-OPEN  ( inode explorer -- )
    DROP                                    \ don't need the explorer widget
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE = IF
        \ Load file preview and switch to Preview tab
        _FEXP-LOAD-PREVIEW
        _FEXP-TABS @ ?DUP IF 1 SWAP TAB-SELECT THEN
    ELSE
        \ Directory: update detail list
        DUP _FEXP-CUR-DIR !
        _FEXP-POPULATE-DIR
        _FEXP-SORT-LIST
        _FEXP-LIST @ ?DUP IF
            _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
        THEN
    THEN
    _FEXP-UPDATE-STATUS
    ASHELL-DIRTY!
;

\ Detail list on-select callback: update preview when item selected
: _FEXP-ON-LIST-SEL  ( index widget -- )
    DROP                                    ( index )
    DUP _FEXP-CNT @ >= IF DROP EXIT THEN
    CELLS _FEXP-INODES + @                 ( inode )
    DUP 0= IF DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE = IF
        _FEXP-LOAD-PREVIEW
    ELSE
        DROP
    THEN
    _FEXP-UPDATE-STATUS
;

\ Tab switch callback
: _FEXP-ON-TAB-SWITCH  ( index widget -- )
    2DROP ASHELL-DIRTY! ;

\ =====================================================================
\  §13 — INIT callback
\ =====================================================================

: FEXP-INIT-CB  ( -- )
    \ Initialize state
    _FEXP-FOCUS-TREE _FEXP-FOCUS !
    FEXP-SORT-NAME _FEXP-SORT !
    0 _FEXP-CNT !
    0 _FEXP-CLIP-IN !
    _FEXP-CLIP-NONE _FEXP-CLIP-OP !
    0 _FEXP-GOTO-ACT !
    0 _FEXP-GOTO-W !
    0 _FEXP-CUR-DIR !

    \ Get VFS
    VFS-CUR _FEXP-VFS !

    \ Get root region
    ASHELL-REGION _FEXP-ROOT-RGN !

    \ Build sub-regions
    \ menu-rgn: row 0, col 0, h=1, w=full
    _FEXP-ROOT-RGN @ 0 0 1
    _FEXP-ROOT-RGN @ RGN-W RGN-SUB
    _FEXP-MENU-RGN !

    \ status-rgn: last row, col 0, h=1, w=full
    _FEXP-ROOT-RGN @ RGN-H 1-              ( last-row )
    _FEXP-ROOT-RGN @
    SWAP 0 1
    _FEXP-ROOT-RGN @ RGN-W RGN-SUB
    _FEXP-STAT-RGN !

    \ body-rgn: row 1, col 0, h=total-2, w=full
    _FEXP-ROOT-RGN @ RGN-H 2 -             ( body-h )
    _FEXP-ROOT-RGN @
    1 0 ROT                                ( parent r c h )
    _FEXP-ROOT-RGN @ RGN-W RGN-SUB
    _FEXP-BODY-RGN !

    \ Initialize menu data
    _FEXP-INIT-MENUS

    \ Create menu bar
    _FEXP-MENU-RGN @ _FMNU-ENTRIES 4 MNU-NEW
    _FEXP-MENU !

    \ Create split pane (V = left/right)
    _FEXP-BODY-RGN @ SPL-V _FEXP-DEF-RATIO SPL-NEW
    _FEXP-SPLIT !

    \ Create explorer widget in pane A
    _FEXP-SPLIT @ SPL-PANE-A
    _FEXP-VFS @
    _FEXP-VFS @ V.ROOT @                    ( rgn vfs root-inode )
    EXPL-NEW
    _FEXP-EXPL !

    \ Wire explorer callbacks
    ['] _FEXP-ON-SELECT _FEXP-EXPL @ EXPL-ON-SELECT
    ['] _FEXP-ON-OPEN   _FEXP-EXPL @ EXPL-ON-OPEN

    \ Create tabs in pane B
    _FEXP-SPLIT @ SPL-PANE-B
    TAB-NEW
    _FEXP-TABS !

    \ Add "Details" tab
    S" Details" _FEXP-TABS @ TAB-ADD       ( detail-rgn )
    \ Create list in detail tab
    _FEXP-ITEMS 0 ROT LST-NEW             ( list-widget )
    _FEXP-LIST !
    ['] _FEXP-ON-LIST-SEL _FEXP-LIST @ LST-ON-SELECT

    \ Add "Preview" tab
    S" Preview" _FEXP-TABS @ TAB-ADD       ( preview-rgn )
    \ Create textarea in preview tab
    _FEXP-PREV-BUF _FEXP-PREVIEW-CAP ROT TXTA-NEW
    _FEXP-TXTA !

    \ Wire tab switch
    ['] _FEXP-ON-TAB-SWITCH _FEXP-TABS @ TAB-ON-SWITCH

    \ Select Details tab by default
    0 _FEXP-TABS @ TAB-SELECT

    \ Create status bar
    _FEXP-STAT-RGN @ SBAR-NEW
    _FEXP-SBAR !
    _FEXP-SBAR @ 15 4 0 SBAR-STYLE!       \ white on blue

    \ Populate initial directory listing from VFS root
    _FEXP-VFS @ V.ROOT @ DUP _FEXP-CUR-DIR !
    _FEXP-POPULATE-DIR
    _FEXP-SORT-LIST
    _FEXP-LIST @ _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS

    \ Update status bar
    _FEXP-UPDATE-STATUS
;

\ =====================================================================
\  §14 — EVENT callback
\ =====================================================================

VARIABLE _FEV-EV    \ current event during event handling

\ Check for Ctrl+<char> combos
: _FEXP-CTRL-CHAR?  ( ev ch -- flag )
    SWAP DUP KEY-IS-CHAR? SWAP KEY-HAS-CTRL? AND IF
        SWAP 8 + @ =                       \ compare codepoint
    ELSE
        DROP 0
    THEN ;

: FEXP-EVENT-CB  ( ev -- flag )
    _FEV-EV !

    \ ── Goto overlay active: route to input ──
    _FEXP-GOTO-ACT @ IF
        _FEV-EV @ KEY-IS-SPECIAL? IF
            _FEV-EV @ KEY-CODE@ KEY-ESC = IF
                _FEXP-GOTO-CANCEL -1 EXIT
            THEN
        THEN
        _FEV-EV @ _FEXP-GOTO-W @ WDG-HANDLE
        EXIT
    THEN

    \ ── Menu active: route to menu ──
    _FEXP-MENU @ MNU-ACTIVE -1 <> IF
        _FEV-EV @ KEY-IS-SPECIAL? IF
            _FEV-EV @ KEY-CODE@ KEY-ESC = IF
                _FEXP-MENU @ MNU-CLOSE
                _FEXP-FOCUS-TREE _FEXP-FOCUS !
                ASHELL-DIRTY!
                -1 EXIT
            THEN
        THEN
        _FEV-EV @ _FEXP-MENU @ WDG-HANDLE
        DUP IF
            \ After menu action, return focus to tree
            _FEXP-MENU @ MNU-ACTIVE -1 = IF
                _FEXP-FOCUS-TREE _FEXP-FOCUS !
            THEN
        THEN
        EXIT
    THEN

    \ ── Global shortcuts (before widget delegation) ──
    _FEV-EV @ KEY-IS-SPECIAL? IF
        _FEV-EV @ KEY-CODE@

        \ F10 — activate menu
        DUP KEY-F10 = IF
            DROP
            0 _FEXP-MENU @ MNU-OPEN
            _FEXP-FOCUS-MENU _FEXP-FOCUS !
            ASHELL-DIRTY!  -1 EXIT
        THEN

        \ Tab — cycle focus
        DUP KEY-TAB = IF
            DROP
            _FEXP-FOCUS @
            DUP _FEXP-FOCUS-TREE = IF
                DROP
                _FEXP-TABS @ TAB-ACTIVE 0= IF
                    _FEXP-FOCUS-DETAIL
                ELSE
                    _FEXP-FOCUS-PREVIEW
                THEN
            ELSE
                DUP _FEXP-FOCUS-DETAIL = OVER _FEXP-FOCUS-PREVIEW = OR IF
                    DROP _FEXP-FOCUS-TREE
                ELSE
                    DROP _FEXP-FOCUS-TREE
                THEN
            THEN
            _FEXP-FOCUS !
            ASHELL-DIRTY! -1 EXIT
        THEN

        \ Backspace — parent directory
        DUP KEY-BACKSPACE = IF
            DROP
            _FEXP-CUR-DIR @ ?DUP IF
                IN.PARENT @ ?DUP IF
                    DUP _FEXP-EXPL @ EXPL-ROOT!
                    DUP _FEXP-CUR-DIR !
                    _FEXP-POPULATE-DIR
                    _FEXP-SORT-LIST
                    _FEXP-LIST @ _FEXP-ITEMS _FEXP-CNT @ ROT LST-SET-ITEMS
                    _FEXP-UPDATE-STATUS
                    ASHELL-DIRTY!
                THEN
            THEN
            -1 EXIT
        THEN

        DROP
    THEN

    \ Ctrl+Q — quit
    _FEV-EV @ 17 _FEXP-CTRL-CHAR? IF  ASHELL-QUIT -1 EXIT  THEN

    \ Ctrl+G — goto path
    _FEV-EV @ 7 _FEXP-CTRL-CHAR? IF  _FEXP-GOTO-SHOW -1 EXIT  THEN

    \ Ctrl+I — properties
    _FEV-EV @ 9 _FEXP-CTRL-CHAR? IF  _FEXP-ACT-PROPS -1 EXIT  THEN

    \ Ctrl+C — copy
    _FEV-EV @ 3 _FEXP-CTRL-CHAR? IF  FEXP-CLIP-COPY -1 EXIT  THEN

    \ Ctrl+X — cut
    _FEV-EV @ 24 _FEXP-CTRL-CHAR? IF  FEXP-CLIP-CUT -1 EXIT  THEN

    \ Ctrl+V — paste
    _FEV-EV @ 22 _FEXP-CTRL-CHAR? IF  FEXP-CLIP-PASTE -1 EXIT  THEN

    \ Ctrl+H — toggle hidden
    _FEV-EV @ 8 _FEXP-CTRL-CHAR? IF
        _FEXP-ACT-HIDDEN -1 EXIT
    THEN

    \ Alt+1 — Details tab, Alt+2 — Preview tab
    _FEV-EV @ KEY-IS-CHAR? IF
        _FEV-EV @ KEY-HAS-ALT? IF
            _FEV-EV @ 8 + @               ( codepoint )
            DUP 49 = IF                    \ '1'
                DROP 0 _FEXP-TABS @ TAB-SELECT
                _FEXP-FOCUS-DETAIL _FEXP-FOCUS !
                ASHELL-DIRTY! -1 EXIT
            THEN
            DUP 50 = IF                    \ '2'
                DROP 1 _FEXP-TABS @ TAB-SELECT
                _FEXP-FOCUS-PREVIEW _FEXP-FOCUS !
                ASHELL-DIRTY! -1 EXIT
            THEN
            DROP
        THEN
    THEN

    \ ── Delegate to focused widget ──
    _FEXP-FOCUS @ CASE
        _FEXP-FOCUS-TREE OF
            _FEV-EV @ _FEXP-EXPL @ WDG-HANDLE
        ENDOF
        _FEXP-FOCUS-DETAIL OF
            _FEV-EV @ _FEXP-LIST @ WDG-HANDLE
        ENDOF
        _FEXP-FOCUS-PREVIEW OF
            _FEV-EV @ _FEXP-TXTA @ WDG-HANDLE
        ENDOF
        0 SWAP   \ default: not consumed
    ENDCASE
    DUP IF ASHELL-DIRTY! THEN
;

\ =====================================================================
\  §15 — PAINT callback
\ =====================================================================

: FEXP-PAINT-CB  ( -- )
    \ Draw menu bar
    _FEXP-MENU-RGN @ RGN-USE
    _FEXP-MENU @ WDG-DRAW

    \ Draw split divider
    _FEXP-BODY-RGN @ RGN-USE
    _FEXP-SPLIT @ WDG-DRAW

    \ Draw explorer in pane A
    _FEXP-SPLIT @ SPL-PANE-A RGN-USE
    _FEXP-EXPL @ WDG-DRAW

    \ Draw tabs + active tab content in pane B
    _FEXP-SPLIT @ SPL-PANE-B RGN-USE
    _FEXP-TABS @ WDG-DRAW

    \ Draw active tab content widget
    _FEXP-TABS @ TAB-ACTIVE 0= IF
        _FEXP-TABS @ 0 SWAP TAB-CONTENT RGN-USE
        _FEXP-LIST @ WDG-DRAW
    ELSE
        _FEXP-TABS @ 1 SWAP TAB-CONTENT RGN-USE
        _FEXP-TXTA @ WDG-DRAW
    THEN

    \ Draw status bar
    _FEXP-STAT-RGN @ RGN-USE
    _FEXP-SBAR @ WDG-DRAW

    \ Draw goto overlay if active
    _FEXP-GOTO-ACT @ IF
        _FEXP-BODY-RGN @ RGN-USE
        _FEXP-GOTO-W @ ?DUP IF WDG-DRAW THEN
    THEN

    \ Restore root region
    RGN-ROOT
;

\ =====================================================================
\  §16 — SHUTDOWN callback
\ =====================================================================

: FEXP-SHUTDOWN-CB  ( -- )
    \ Free goto overlay if active
    _FEXP-GOTO-W @ ?DUP IF INP-FREE THEN
    0 _FEXP-GOTO-W !
    \ Free widgets
    _FEXP-TXTA @ ?DUP IF TXTA-FREE THEN
    _FEXP-LIST @ ?DUP IF LST-FREE THEN
    _FEXP-TABS @ ?DUP IF TAB-FREE THEN
    _FEXP-EXPL @ ?DUP IF EXPL-FREE THEN
    _FEXP-SPLIT @ ?DUP IF SPL-FREE THEN
    _FEXP-SBAR @ ?DUP IF SBAR-FREE THEN
    _FEXP-MENU @ ?DUP IF MNU-FREE THEN
    \ Zero all widget handles
    0 _FEXP-EXPL !   0 _FEXP-SPLIT !
    0 _FEXP-TABS !   0 _FEXP-LIST !
    0 _FEXP-TXTA !   0 _FEXP-SBAR !
    0 _FEXP-MENU !
;

\ =====================================================================
\  §17 — Entry Point & Standalone Runner
\ =====================================================================

\ FEXP-ENTRY ( desc -- )
\   Fill an APP-DESC with fexplorer callbacks.  Called by app-loader
\   or desk DESK-LAUNCH pipeline.
: FEXP-ENTRY  ( desc -- )
    DUP APP-DESC-INIT
    ['] FEXP-INIT-CB     OVER APP.INIT-XT !
    ['] FEXP-EVENT-CB    OVER APP.EVENT-XT !
    0                    OVER APP.TICK-XT !
    ['] FEXP-PAINT-CB    OVER APP.PAINT-XT !
    ['] FEXP-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    0                    OVER APP.UIDL-A !
    0                    OVER APP.UIDL-U !
    0                    OVER APP.WIDTH !
    0                    OVER APP.HEIGHT !
    S" File Explorer"    ROT DUP >R APP.TITLE-A !
                         R> APP.TITLE-U !
;

\ FEXP-RUN ( -- )
\   Standalone entry point — creates descriptor and runs via app-shell.
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
