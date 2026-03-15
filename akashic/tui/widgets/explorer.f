\ =================================================================
\  explorer.f  —  File Explorer Widget
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: EXPL- / _EXPL-
\  Depends on: akashic-tui-tree, akashic-tui-draw, akashic-tui-region,
\              akashic-tui-keys, akashic-tui-input, akashic-tui-dialog,
\              akashic-vfs
\
\  Persistent, non-modal file explorer that bridges tree.f to the
\  Akashic VFS layer.  Shows a tree of directories and files rooted
\  at a configurable VFS inode.  Supports expand/collapse, selection,
\  inline rename, delete with confirmation, and new file/dir.
\
\  The VFS inode tree IS the tree data — each "node" is a VFS inode
\  pointer.  No node cache, no mapping arrays, no order arrays.
\  The child→sibling linked-list structure of VFS inodes maps
\  directly to tree.f's children/next callback model.
\
\  Descriptor layout (header + 8 cells = 104 bytes):
\   +40  tree-widget   Embedded TREE-* widget pointer
\   +48  vfs           VFS instance pointer
\   +56  root-inode    Root directory inode for this view
\   +64  on-open-xt    Callback: ( inode explorer -- ) file opened
\   +72  on-select-xt  Callback: ( inode explorer -- ) sel changed
\   +80  rename-input  INP-* widget for inline rename (0 = inactive)
\   +88  flags2        Bit 0: show-hidden  Bit 1: rename-active
\   +96  rename-buf    Rename buffer address (256 bytes)
\ =================================================================

PROVIDED akashic-tui-explorer

REQUIRE tree.f
REQUIRE input.f
REQUIRE dialog.f
REQUIRE ../draw.f
REQUIRE ../box.f
REQUIRE ../region.f
REQUIRE ../keys.f
REQUIRE ../../utils/fs/vfs.f

\ 3DROP may already be defined by tree.f — define only if absent.
[UNDEFINED] 3DROP [IF]
: 3DROP  ( a b c -- )  DROP 2DROP ;
[THEN]

\ =====================================================================
\  §1 — Layout constants
\ =====================================================================

40  CONSTANT _EXPL-O-TREE
48  CONSTANT _EXPL-O-VFS
56  CONSTANT _EXPL-O-ROOT
64  CONSTANT _EXPL-O-ON-OPEN
72  CONSTANT _EXPL-O-ON-SEL
80  CONSTANT _EXPL-O-REN-INP
88  CONSTANT _EXPL-O-FLAGS2
96  CONSTANT _EXPL-O-REN-BUF
104 CONSTANT _EXPL-DESC-SZ

256 CONSTANT _EXPL-REN-CAP     \ rename buffer capacity

\ Flags2 bit masks
1 CONSTANT _EXPL-F2-HIDDEN     \ show hidden files
2 CONSTANT _EXPL-F2-RENAME     \ rename mode active

\ =====================================================================
\  §2 — Explorer variable (for callbacks that need the widget)
\ =====================================================================

VARIABLE _EXPL-CUR   \ current explorer widget pointer (set in callbacks)

\ =====================================================================
\  §3 — VFS ↔ Tree callback mapping
\ =====================================================================
\  Each callback receives a VFS inode pointer as the "node" token.

\ _EXPL-CHILDREN ( inode -- first-child | 0 )
\   Tree callback: get first child.  For directories, ensures
\   children are loaded from the backing store first.
: _EXPL-CHILDREN  ( inode -- first-child | 0 )
    DUP IN.TYPE @ VFS-T-DIR <> IF  DROP 0 EXIT  THEN
    DUP _EXPL-CUR @ _EXPL-O-VFS + @  _VFS-ENSURE-CHILDREN
    IN.CHILD @ ;

\ _EXPL-NEXT ( inode -- sibling | 0 )
\   Tree callback: get next sibling.
: _EXPL-NEXT  ( inode -- sibling | 0 )
    IN.SIBLING @ ;

\ Label scratch buffer and variables
CREATE _EXPL-LABEL-BUF 320 ALLOT

VARIABLE _EXL-SA     \ source string addr
VARIABLE _EXL-SU     \ source string len
VARIABLE _EXL-PA     \ prefix addr
VARIABLE _EXL-PU     \ prefix len

\ _EXPL-LABEL ( inode -- addr len )
\   Tree callback: get node label text.
\   Directories are already distinguished by their expand/collapse
\   indicator (▼/▶) in the tree widget, so no prefix is needed.
: _EXPL-LABEL  ( inode -- addr len )
    IN.NAME @ _VFS-STR-GET ;

\ _EXPL-LEAF? ( inode -- flag )
\   Tree callback: true if the node is not a directory.
: _EXPL-LEAF?  ( inode -- flag )
    IN.TYPE @ VFS-T-DIR <> ;

\ =====================================================================
\  §4 — Selection callback wrapper
\ =====================================================================
\  The tree widget fires this on Enter or select.  We translate it
\  to the explorer's on-select callback with the inode.

: _EXPL-ON-TREE-SEL  ( tree-widget -- )
    DROP   \ we don't need the tree widget; use _EXPL-CUR
    _EXPL-CUR @ DUP _EXPL-O-TREE + @ TREE-SELECTED NIP  ( expl inode )
    ?DUP 0= IF DROP EXIT THEN
    OVER _EXPL-O-ON-SEL + @ ?DUP IF
        >R SWAP R> EXECUTE                \ xt ( inode explorer -- )
    ELSE
        2DROP
    THEN ;

\ =====================================================================
\  §5 — Draw handler
\ =====================================================================

: _EXPL-DRAW  ( widget -- )
    DUP _EXPL-CUR !
    DUP _EXPL-O-TREE + @ WDG-DRAW
    \ If rename is active, draw the input widget on top
    DUP _EXPL-O-FLAGS2 + @ _EXPL-F2-RENAME AND IF
        DUP _EXPL-O-REN-INP + @ ?DUP IF WDG-DRAW THEN
    THEN
    DROP ;

\ =====================================================================
\  §6 — Rename helpers
\ =====================================================================

VARIABLE _EXRN-W    \ explorer widget during rename operations

VARIABLE _EXRC-INP  \ rename-commit: input widget
VARIABLE _EXRC-IN   \ rename-commit: inode being renamed
VARIABLE _EXRC-NA   \ rename-commit: new name addr
VARIABLE _EXRC-NU   \ rename-commit: new name len

\ _EXPL-RENAME-VALIDATE ( addr len parent-inode -- flag )
\   Return TRUE if name is valid: non-empty, no '/', and no
\   duplicate sibling name under parent.
: _EXPL-RENAME-VALIDATE  ( addr len parent-inode -- flag )
    >R                                    ( addr len  R: parent )
    DUP 0= IF  R> DROP 2DROP FALSE EXIT  THEN
    \ Check for '/' in name
    DUP 0 DO
        OVER I + C@ [CHAR] / = IF
            2DROP R> DROP FALSE UNLOOP EXIT
        THEN
    LOOP
    \ Check for duplicate sibling
    R> _VFS-FIND-CHILD                    ( child | 0 )
    0= ;                                  \ TRUE if 0 (no dup)

\ _EXPL-RENAME-COMMIT ( input-widget -- )
\   Called when user presses Enter in rename input.
: _EXPL-RENAME-COMMIT  ( input-widget -- )
    _EXRC-INP !
    _EXRN-W @ _EXPL-O-TREE + @ TREE-SELECTED NIP  _EXRC-IN !
    _EXRC-IN @ 0= IF  EXIT  THEN

    \ Get text from input
    _EXRC-INP @ INP-GET-TEXT  _EXRC-NU !  _EXRC-NA !

    \ Validate
    _EXRC-NA @  _EXRC-NU @  _EXRC-IN @ IN.PARENT @
    _EXPL-RENAME-VALIDATE  0= IF  EXIT  THEN

    \ Allocate new name in VFS string pool
    _EXRC-NA @  _EXRC-NU @  _EXRN-W @ _EXPL-O-VFS + @
    _VFS-STR-ALLOC                        ( new-handle )

    \ Release old name, store new
    _EXRC-IN @ IN.NAME @ _VFS-STR-RELEASE
    _EXRC-IN @ IN.NAME !                  ( -- )

    \ Mark inode dirty
    _EXRC-IN @ IN.FLAGS DUP @ VFS-IF-DIRTY OR SWAP !

    \ Sync VFS
    _EXRN-W @ _EXPL-O-VFS + @ VFS-SYNC DROP

    \ End rename mode
    _EXRN-W @ _EXPL-O-FLAGS2 + DUP @
    _EXPL-F2-RENAME INVERT AND SWAP !
    _EXRN-W @ _EXPL-O-REN-INP + @ ?DUP IF INP-FREE THEN
    0 _EXRN-W @ _EXPL-O-REN-INP + !
    _EXRN-W @ _EXPL-O-TREE + @ TREE-REFRESH ;

\ _EXPL-RENAME-CANCEL ( widget -- )
\   Cancel inline rename, dismiss input widget.
: _EXPL-RENAME-CANCEL  ( widget -- )
    DUP _EXPL-O-FLAGS2 + DUP @
    _EXPL-F2-RENAME INVERT AND SWAP !
    DUP _EXPL-O-REN-INP + @ ?DUP IF INP-FREE THEN
    0 OVER _EXPL-O-REN-INP + !
    _EXPL-O-TREE + @ TREE-REFRESH ;

\ =====================================================================
\  §7 — Public: rename / delete / new file / new dir / refresh
\ =====================================================================

\ EXPL-RENAME ( widget -- )
\   Start inline rename of selected entry.

VARIABLE _EXR-W
VARIABLE _EXR-IN

: EXPL-RENAME  ( widget -- )
    _EXR-W !
    _EXR-W @ _EXPL-CUR !
    _EXR-W @ _EXRN-W !
    _EXR-W @ _EXPL-O-TREE + @ TREE-SELECTED NIP  _EXR-IN !
    _EXR-IN @ 0= IF EXIT THEN

    \ Get current name
    _EXR-IN @ IN.NAME @ _VFS-STR-GET     ( addr len )

    \ Create input widget (reuse explorer region for now)
    _EXR-W @ WDG-REGION                  ( addr len rgn )
    _EXR-W @ _EXPL-O-REN-BUF + @        ( addr len rgn buf )
    _EXPL-REN-CAP INP-NEW               ( addr len inp )

    \ Set text and submit callback
    DUP >R  INP-SET-TEXT                  ( -- )
    ['] _EXPL-RENAME-COMMIT R@ INP-ON-SUBMIT
    R> _EXR-W @ _EXPL-O-REN-INP + !

    \ Set rename-active flag
    _EXR-W @ _EXPL-O-FLAGS2 + DUP @
    _EXPL-F2-RENAME OR SWAP !
    _EXR-W @ WDG-DIRTY ;

\ EXPL-DELETE ( widget -- )
\   Delete selected entry with confirmation dialog.

VARIABLE _EXD-W
VARIABLE _EXD-IN

: EXPL-DELETE  ( widget -- )
    _EXD-W !
    _EXD-W @ _EXPL-CUR !
    _EXD-W @ _EXPL-O-TREE + @ TREE-SELECTED NIP  _EXD-IN !
    _EXD-IN @ 0= IF EXIT THEN

    \ Confirm with dialog
    S" Delete?" DLG-CONFIRM               ( flag )
    0= IF  EXIT  THEN                     \ user said No

    \ Get name and VFS
    _EXD-IN @ IN.NAME @ _VFS-STR-GET      ( name-a name-u )
    _EXD-W @ _EXPL-O-VFS + @             ( name-a name-u vfs )

    \ Temporarily change CWD to parent for VFS-RM resolution
    DUP V.CWD @ >R                        ( name-a name-u vfs  R: old-cwd )
    _EXD-IN @ IN.PARENT @ OVER V.CWD !    ( name-a name-u vfs )
    VFS-RM DROP                            ( R: old-cwd )

    \ Restore CWD
    R> _EXD-W @ _EXPL-O-VFS + @ V.CWD !

    \ Sync and refresh
    _EXD-W @ _EXPL-O-VFS + @ VFS-SYNC DROP
    _EXD-W @ _EXPL-O-TREE + @ TREE-REFRESH
    _EXD-W @ WDG-DIRTY ;

\ EXPL-NEW-FILE ( widget -- )
\   Create a new file in the directory of the selected entry.

VARIABLE _EXNF-W
VARIABLE _EXNF-IN
VARIABLE _EXNF-VFS
VARIABLE _EXNF-OCWD

: EXPL-NEW-FILE  ( widget -- )
    _EXNF-W !
    _EXNF-W @ _EXPL-CUR !
    _EXNF-W @ _EXPL-O-TREE + @ TREE-SELECTED NIP  _EXNF-IN !
    _EXNF-IN @ 0= IF EXIT THEN

    \ Determine target directory
    _EXNF-IN @ IN.TYPE @ VFS-T-DIR = IF
        _EXNF-IN @
    ELSE
        _EXNF-IN @ IN.PARENT @
    THEN                                   ( target-dir )

    \ Save CWD, set to target, create file, restore
    _EXNF-W @ _EXPL-O-VFS + @  _EXNF-VFS !
    _EXNF-VFS @ V.CWD @  _EXNF-OCWD !
    _EXNF-VFS @ V.CWD !                   ( -- )
    S" newfile"  _EXNF-VFS @  VFS-MKFILE DROP
    _EXNF-OCWD @  _EXNF-VFS @  V.CWD !

    \ Sync and refresh
    _EXNF-VFS @  VFS-SYNC DROP
    _EXNF-W @ _EXPL-O-TREE + @ TREE-REFRESH
    _EXNF-W @ WDG-DIRTY ;

\ EXPL-NEW-DIR ( widget -- )
\   Create a new subdirectory under the selected directory.

VARIABLE _EXND-W
VARIABLE _EXND-IN
VARIABLE _EXND-VFS
VARIABLE _EXND-OCWD

: EXPL-NEW-DIR  ( widget -- )
    _EXND-W !
    _EXND-W @ _EXPL-CUR !
    _EXND-W @ _EXPL-O-TREE + @ TREE-SELECTED NIP  _EXND-IN !
    _EXND-IN @ 0= IF EXIT THEN

    \ Determine target directory
    _EXND-IN @ IN.TYPE @ VFS-T-DIR = IF
        _EXND-IN @
    ELSE
        _EXND-IN @ IN.PARENT @
    THEN                                   ( target-dir )

    \ Save CWD, set to target, create dir, restore
    _EXND-W @ _EXPL-O-VFS + @  _EXND-VFS !
    _EXND-VFS @ V.CWD @  _EXND-OCWD !
    _EXND-VFS @ V.CWD !                   ( -- )
    S" newfolder"  _EXND-VFS @  VFS-MKDIR DROP
    _EXND-OCWD @  _EXND-VFS @  V.CWD !

    \ Sync and refresh
    _EXND-VFS @  VFS-SYNC DROP
    _EXND-W @ _EXPL-O-TREE + @ TREE-REFRESH
    _EXND-W @ WDG-DIRTY ;

\ EXPL-REFRESH ( widget -- )
\   Re-trigger VFS lazy loading and redraw.
: EXPL-REFRESH  ( widget -- )
    DUP _EXPL-O-TREE + @ TREE-REFRESH
    WDG-DIRTY ;

\ =====================================================================
\  §8 — Event handler
\ =====================================================================

VARIABLE _EXH-W    \ explorer widget during event handling
VARIABLE _EXH-EV   \ current event
VARIABLE _EXH-IN   \ inode during event handling

: _EXPL-HANDLE  ( event widget -- consumed? )
    _EXH-W !  _EXH-EV !
    _EXH-W @ _EXPL-CUR !
    _EXH-W @ _EXRN-W !

    \ ── If rename is active, route keys to the input widget ──
    _EXH-W @ _EXPL-O-FLAGS2 + @ _EXPL-F2-RENAME AND IF
        \ Check for Escape to cancel rename
        _EXH-EV @ KEY-IS-SPECIAL? IF
            _EXH-EV @ KEY-CODE@ KEY-ESC = IF
                _EXH-W @ _EXPL-RENAME-CANCEL
                _EXH-W @ WDG-DIRTY
                -1 EXIT
            THEN
        THEN
        \ Forward everything else to the input widget
        _EXH-EV @ _EXH-W @ _EXPL-O-REN-INP + @ WDG-HANDLE
        EXIT
    THEN

    \ ── Special keys ──
    _EXH-EV @ KEY-IS-SPECIAL? IF
        _EXH-EV @ KEY-CODE@               ( code )

        \ F2 — rename
        DUP KEY-F2 = IF
            DROP _EXH-W @ EXPL-RENAME -1 EXIT
        THEN

        \ F5 — refresh
        DUP KEY-F5 = IF
            DROP _EXH-W @ EXPL-REFRESH -1 EXIT
        THEN

        \ Delete — delete with confirm
        DUP KEY-DEL = IF
            DROP _EXH-W @ EXPL-DELETE -1 EXIT
        THEN

        \ Enter — open file or toggle directory
        DUP KEY-ENTER = IF
            DROP
            _EXH-W @ _EXPL-O-TREE + @ TREE-SELECTED NIP  _EXH-IN !
            _EXH-IN @ 0= IF -1 EXIT THEN
            _EXH-IN @ IN.TYPE @ VFS-T-DIR = IF
                \ Toggle directory expand/collapse
                _EXH-W @ _EXPL-O-TREE + @
                _EXH-IN @ TREE-TOGGLE
            ELSE
                \ Fire on-open callback
                _EXH-W @ _EXPL-O-ON-OPEN + @ ?DUP IF
                    _EXH-IN @ _EXH-W @ ROT EXECUTE
                THEN
            THEN
            _EXH-W @ WDG-DIRTY
            -1 EXIT
        THEN

        \ Up / Down / Left / Right — delegate to embedded tree
        DUP KEY-UP = OVER KEY-DOWN = OR
        OVER KEY-LEFT = OR OVER KEY-RIGHT = OR IF
            DROP
            _EXH-EV @ _EXH-W @ _EXPL-O-TREE + @ WDG-HANDLE DROP
            \ After navigation, fire selection callback
            _EXH-W @ _EXPL-O-TREE + @ TREE-SELECTED NIP  ( inode )
            ?DUP IF
                _EXH-W @ _EXPL-O-ON-SEL + @ ?DUP IF
                    >R _EXH-W @ R> EXECUTE
                ELSE
                    DROP
                THEN
            THEN
            _EXH-W @ WDG-DIRTY
            -1 EXIT
        THEN

        \ Escape — no-op at top level
        DUP KEY-ESC = IF
            DROP 0 EXIT
        THEN

        DROP
    THEN

    \ ── Ctrl+key combos (char-type events) ──
    _EXH-EV @ KEY-IS-CHAR? IF
        _EXH-EV @ KEY-HAS-CTRL? IF
            _EXH-EV @ 8 + @               \ codepoint
            \ Ctrl+N = new file (codepoint 14)
            DUP 14 = IF
                DROP
                _EXH-EV @ KEY-HAS-SHIFT? IF
                    _EXH-W @ EXPL-NEW-DIR
                ELSE
                    _EXH-W @ EXPL-NEW-FILE
                THEN
                -1 EXIT
            THEN
            \ Ctrl+H = toggle hidden (codepoint 8)
            DUP 8 = IF
                DROP
                _EXH-W @ _EXPL-O-FLAGS2 + DUP @
                _EXPL-F2-HIDDEN XOR SWAP !
                _EXH-W @ WDG-DIRTY
                -1 EXIT
            THEN
            \ Ctrl+R = refresh (codepoint 18)
            DUP 18 = IF
                DROP _EXH-W @ EXPL-REFRESH -1 EXIT
            THEN
            DROP
        THEN
    THEN

    0 ;   \ not consumed

\ =====================================================================
\  §9 — Constructor
\ =====================================================================

: EXPL-NEW  ( rgn vfs root-inode -- widget )
    >R >R                                  ( rgn  R: root vfs )

    \ Allocate descriptor
    _EXPL-DESC-SZ ALLOCATE
    0<> ABORT" EXPL-NEW: alloc"

    \ Fill common header
    WDG-T-EXPLORER    OVER _WDG-O-TYPE      + !
    SWAP               OVER _WDG-O-REGION    + !
    ['] _EXPL-DRAW     OVER _WDG-O-DRAW-XT   + !
    ['] _EXPL-HANDLE   OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                       OVER _WDG-O-FLAGS     + !

    \ Fill explorer-specific fields
    R>                 OVER _EXPL-O-VFS      + !   \ vfs
    R>                 OVER _EXPL-O-ROOT     + !   \ root-inode
    0                  OVER _EXPL-O-ON-OPEN  + !
    0                  OVER _EXPL-O-ON-SEL   + !
    0                  OVER _EXPL-O-REN-INP  + !
    0                  OVER _EXPL-O-FLAGS2   + !

    \ Allocate rename buffer
    _EXPL-REN-CAP ALLOCATE
    0<> ABORT" EXPL-NEW: rename buf"
    OVER _EXPL-O-REN-BUF + !

    \ Set as current explorer (needed for callbacks)
    DUP _EXPL-CUR !

    \ Create embedded tree widget with VFS callbacks
    DUP WDG-REGION                        ( desc rgn )
    OVER _EXPL-O-ROOT + @                 ( desc rgn root-inode )
    ['] _EXPL-CHILDREN
    ['] _EXPL-NEXT
    ['] _EXPL-LABEL
    ['] _EXPL-LEAF?
    TREE-NEW                              ( desc tree )

    \ Set tree selection callback
    DUP ['] _EXPL-ON-TREE-SEL SWAP TREE-ON-SELECT

    \ Store tree widget in descriptor
    OVER _EXPL-O-TREE + ! ;              ( desc )

\ =====================================================================
\  §10 — Public API
\ =====================================================================

\ EXPL-SELECTED ( widget -- inode )
\   Get inode of the currently selected node.
: EXPL-SELECTED  ( widget -- inode )
    DUP _EXPL-CUR !
    _EXPL-O-TREE + @ TREE-SELECTED NIP ;

\ EXPL-ON-OPEN ( xt widget -- )
\   Set file-opened callback: ( inode explorer -- )
: EXPL-ON-OPEN  ( xt widget -- )
    _EXPL-O-ON-OPEN + ! ;

\ EXPL-ON-SELECT ( xt widget -- )
\   Set selection-changed callback: ( inode explorer -- )
: EXPL-ON-SELECT  ( xt widget -- )
    _EXPL-O-ON-SEL + ! ;

\ EXPL-ROOT! ( inode widget -- )
\   Change root directory and refresh.
: EXPL-ROOT!  ( inode widget -- )
    DUP _EXPL-CUR !
    DUP >R  _EXPL-O-ROOT + !
    R@ _EXPL-O-TREE + @ TREE-FREE
    R@ WDG-REGION
    R@ _EXPL-O-ROOT + @
    ['] _EXPL-CHILDREN
    ['] _EXPL-NEXT
    ['] _EXPL-LABEL
    ['] _EXPL-LEAF?
    TREE-NEW
    DUP ['] _EXPL-ON-TREE-SEL SWAP TREE-ON-SELECT
    R> _EXPL-O-TREE + ! ;

\ EXPL-EXPAND-ALL ( widget -- )
\   Expand entire tree.
: EXPL-EXPAND-ALL  ( widget -- )
    DUP _EXPL-CUR !
    _EXPL-O-TREE + @ TREE-EXPAND-ALL ;

\ EXPL-COLLAPSE-ALL ( widget -- )
\   Collapse to root only.
: EXPL-COLLAPSE-ALL  ( widget -- )
    DUP _EXPL-CUR !
    DUP _EXPL-O-TREE + @
    OVER _EXPL-O-ROOT + @
    TREE-COLLAPSE
    _EXPL-O-TREE + @ TREE-REFRESH ;

\ EXPL-SHOW-HIDDEN! ( flag widget -- )
\   Show or hide hidden files.
: EXPL-SHOW-HIDDEN!  ( flag widget -- )
    _EXPL-O-FLAGS2 + DUP @
    _EXPL-F2-HIDDEN INVERT AND            \ clear bit
    ROT IF _EXPL-F2-HIDDEN OR THEN        \ conditionally set
    SWAP ! ;

\ EXPL-SHOW-HIDDEN? ( widget -- flag )
: EXPL-SHOW-HIDDEN?  ( widget -- flag )
    _EXPL-O-FLAGS2 + @ _EXPL-F2-HIDDEN AND 0<> ;

\ EXPL-VFS ( widget -- vfs )
\   Get the VFS instance.
: EXPL-VFS  ( widget -- vfs )
    _EXPL-O-VFS + @ ;

\ EXPL-TREE ( widget -- tree-widget )
\   Get the embedded tree widget.
: EXPL-TREE  ( widget -- tree-widget )
    _EXPL-O-TREE + @ ;

\ =====================================================================
\  §11 — Free
\ =====================================================================

\ EXPL-FREE ( widget -- )
\   Free the tree widget, rename input, rename buffer, descriptor.
: EXPL-FREE  ( widget -- )
    DUP _EXPL-O-REN-INP + @ ?DUP IF INP-FREE THEN
    DUP _EXPL-O-REN-BUF + @ FREE
    DUP _EXPL-O-TREE + @ TREE-FREE
    FREE ;

\ =====================================================================
\  §12 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _expl-guard

' EXPL-NEW          CONSTANT _expl-new-xt
' EXPL-SELECTED     CONSTANT _expl-sel-xt
' EXPL-ON-OPEN      CONSTANT _expl-onopen-xt
' EXPL-ON-SELECT    CONSTANT _expl-onsel-xt
' EXPL-ROOT!        CONSTANT _expl-root-xt
' EXPL-EXPAND-ALL   CONSTANT _expl-exall-xt
' EXPL-COLLAPSE-ALL CONSTANT _expl-colall-xt
' EXPL-SHOW-HIDDEN! CONSTANT _expl-hidden-xt
' EXPL-RENAME       CONSTANT _expl-rename-xt
' EXPL-DELETE       CONSTANT _expl-delete-xt
' EXPL-NEW-FILE     CONSTANT _expl-newfile-xt
' EXPL-NEW-DIR      CONSTANT _expl-newdir-xt
' EXPL-REFRESH      CONSTANT _expl-refresh-xt
' EXPL-FREE         CONSTANT _expl-free-xt

: EXPL-NEW          _expl-new-xt     _expl-guard WITH-GUARD ;
: EXPL-SELECTED     _expl-sel-xt     _expl-guard WITH-GUARD ;
: EXPL-ON-OPEN      _expl-onopen-xt  _expl-guard WITH-GUARD ;
: EXPL-ON-SELECT    _expl-onsel-xt   _expl-guard WITH-GUARD ;
: EXPL-ROOT!        _expl-root-xt    _expl-guard WITH-GUARD ;
: EXPL-EXPAND-ALL   _expl-exall-xt   _expl-guard WITH-GUARD ;
: EXPL-COLLAPSE-ALL _expl-colall-xt  _expl-guard WITH-GUARD ;
: EXPL-SHOW-HIDDEN! _expl-hidden-xt  _expl-guard WITH-GUARD ;
: EXPL-RENAME       _expl-rename-xt  _expl-guard WITH-GUARD ;
: EXPL-DELETE        _expl-delete-xt _expl-guard WITH-GUARD ;
: EXPL-NEW-FILE     _expl-newfile-xt _expl-guard WITH-GUARD ;
: EXPL-NEW-DIR      _expl-newdir-xt  _expl-guard WITH-GUARD ;
: EXPL-REFRESH      _expl-refresh-xt _expl-guard WITH-GUARD ;
: EXPL-FREE         _expl-free-xt    _expl-guard WITH-GUARD ;
[THEN] [THEN]
