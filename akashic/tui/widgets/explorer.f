\ =================================================================
\  explorer.f  —  File Explorer Widget
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: EXPL- / _EXPL-
\  Depends on: akashic-tui-tree, akashic-tui-draw, akashic-tui-region,
\              akashic-tui-keys, akashic-tui-input, akashic-tui-dialog,
\              akashic-vfs, akashic-places
\
\  Persistent, non-modal file explorer that bridges tree.f to a place
\  set (utils/fs/places.f).  Its top rows are the set's places, by
\  label; each opens onto its folder, and the rows below are that
\  folder's directories and files.  An unavailable place shows why and
\  stays closed.  Supports expand/collapse, selection, inline rename,
\  delete with confirmation, and new file/dir, each of which a
\  read-only place refuses.
\
\  A top row's node is the place handle the set gave out; every other
\  node is a VFS inode pointer.  No node cache, no mapping arrays, no
\  order arrays: the child→sibling linked-list structure of VFS inodes
\  maps directly to tree.f's children/next callback model.  A place's
\  key comes from its name (EXPL-PLACE-KEY) and an entry's from its
\  parent's key and its name (EXPL-ENTRY-KEY), so keys survive refreshes
\  and reloads.  Opening a place or a directory expands or collapses it;
\  opening a file runs the on-open callback.
\
\  The tree calls the key callback for each row in order and a query
\  stops at the row it finds, so the last place the callback saw is the
\  place of that row.  That is how a selected entry's place is known
\  even when two places show the same folder.
\
\  Descriptor layout (header + 15 cells = 160 bytes):
\   +40  tree-widget   Embedded TREE-* widget pointer
\   +48  set           Place set
\   +56  walk-place    Place of the rows the tree last walked
\   +64  on-open-xt    Callback: ( inode place explorer -- ) file opened
\   +72  on-select-xt  Callback: ( inode place explorer -- ) sel changed
\   +80  rename-input  INP-* widget for inline rename (0 = inactive)
\   +88  flags2        Bit 0: show-hidden  Bit 1: rename-active
\   +96  rename-buf    Rename buffer address (256 bytes)
\   +104 delete        The entry a delete question asks about
\   +112 seen          Its tree's, input's and set's revisions, counted
\   +120 labels        The place rows' labels, one block
\   +128 path-buf      Path scratch (VFS-PATH-MAX bytes)
\   +136 delete-place  The place of the entry a delete question asks about
\   +144 first         The set's first place when the tree was made
\   +152 set-rev       The set's revision the labels were made at
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
REQUIRE ../../utils/fs/places.f

\ 3DROP may already be defined by tree.f — define only if absent.
[UNDEFINED] 3DROP [IF]
: 3DROP  ( a b c -- )  DROP 2DROP ;
[THEN]

\ =====================================================================
\  §1 — Layout constants
\ =====================================================================

40  CONSTANT _EXPL-O-TREE
48  CONSTANT _EXPL-O-SET
56  CONSTANT _EXPL-O-PLACE     \ place of the rows the tree last walked
64  CONSTANT _EXPL-O-ON-OPEN
72  CONSTANT _EXPL-O-ON-SEL
80  CONSTANT _EXPL-O-REN-INP
88  CONSTANT _EXPL-O-FLAGS2
96  CONSTANT _EXPL-O-REN-BUF
104 CONSTANT _EXPL-O-DELETE    \ the entry a delete question asks about
112 CONSTANT _EXPL-O-SEEN      \ its tree's and input's revisions, counted
120 CONSTANT _EXPL-O-LABELS    \ the place rows' labels, one block
128 CONSTANT _EXPL-O-PATH      \ path scratch
136 CONSTANT _EXPL-O-DEL-PLACE \ the place of the entry a delete asks about
144 CONSTANT _EXPL-O-FIRST     \ the set's first place when the tree was made
152 CONSTANT _EXPL-O-SET-REV   \ the set's revision the labels were made at
160 CONSTANT _EXPL-DESC-SZ

VFS-PATH-MAX CONSTANT _EXPL-PATH-CAP

256 CONSTANT _EXPL-REN-CAP     \ rename buffer capacity

\ Flags2 bit masks
1 CONSTANT _EXPL-F2-HIDDEN     \ show hidden files
2 CONSTANT _EXPL-F2-RENAME     \ rename mode active

\ =====================================================================
\  §3 — Place rows
\ =====================================================================
\  A place row's label is the place's label, followed by why when the
\  place is unavailable.  The labels are kept in one block, so each stays
\  where a renderer was told it is until the block is made again: an
\  entry is the place, the label's length and its bytes, padded to a cell,
\  and a zero place ends the block.

: _EXPL-SET  ( explorer -- set )  _EXPL-O-SET + @ ;

: _EXPL-LABEL-BYTES  ( place -- n )
    DUP PLACE-LABEL NIP SWAP PLACE-WHY NIP ?DUP IF 3 + + THEN ;

: _EXPL-LABEL-ROOM  ( place -- n )  _EXPL-LABEL-BYTES 7 + -8 AND 16 + ;

VARIABLE _EXLB-AT

: _EXLB+  ( a u -- )  TUCK _EXLB-AT @ SWAP CMOVE _EXLB-AT +! ;

: _EXPL-LABEL-FILL  ( place entry -- )
    2DUP !
    OVER _EXPL-LABEL-BYTES OVER 8 + !
    16 + _EXLB-AT !
    DUP PLACE-LABEL _EXLB+
    PLACE-WHY ?DUP IF
        S"  (" _EXLB+ _EXLB+ S" )" _EXLB+
    ELSE
        DROP
    THEN ;

\ _EXPL-LABELS! ( explorer -- )
\   Make the place rows' labels as the places are now.
: _EXPL-LABELS!  ( explorer -- )
    DUP _EXPL-O-LABELS + @ ?DUP IF FREE THEN
    0 OVER _EXPL-O-LABELS + !
    8 OVER _EXPL-SET PLSET-FIRST
    BEGIN ?DUP WHILE
        DUP _EXPL-LABEL-ROOM ROT + SWAP PLACE-NEXT
    REPEAT                                          ( explorer bytes )
    ALLOCATE IF 2DROP EXIT THEN                     ( explorer block )
    2DUP SWAP _EXPL-O-LABELS + !
    SWAP _EXPL-SET PLSET-FIRST                      ( entry place )
    BEGIN ?DUP WHILE
        2DUP SWAP _EXPL-LABEL-FILL
        DUP _EXPL-LABEL-ROOM ROT + SWAP PLACE-NEXT
    REPEAT
    0 SWAP ! ;

: _EXPL-PLACE-LABEL  ( place explorer -- addr len )
    _EXPL-O-LABELS + @ ?DUP 0= IF PLACE-LABEL EXIT THEN
    BEGIN DUP @ WHILE
        2DUP @ = IF NIP DUP 16 + SWAP 8 + @ EXIT THEN
        DUP 8 + @ 7 + -8 AND 16 + +
    REPEAT
    DROP PLACE-LABEL ;

\ =====================================================================
\  §3b — Places and VFS ↔ Tree callback mapping
\ =====================================================================
\  Each callback receives a place handle or a VFS inode pointer as the
\  "node" token.  A token is a place when the explorer's set holds it.

: _EXPL-PLACE?  ( node -- flag )
    TREE-WALK-CONTEXT _EXPL-SET PLSET-MEMBER? ;

\ _EXPL-CHILDREN ( node -- first-child | 0 )
\   Tree callback: get first child.  A place's children are its folder's,
\   and an unavailable place has none.  For directories, ensures children
\   are loaded from the entry's own volume first.
: _EXPL-CHILDREN  ( node -- first-child | 0 )
    DUP _EXPL-PLACE? IF PLACE-ROOT DUP 0= IF EXIT THEN THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF  DROP 0 EXIT  THEN
    DUP DUP D.OWNER @ _VFS-ENSURE-CHILDREN
    IN.CHILD @ ;

\ _EXPL-NEXT ( node -- sibling | 0 )
\   Tree callback: get next sibling.
: _EXPL-NEXT  ( node -- sibling | 0 )
    DUP _EXPL-PLACE? IF PLACE-NEXT ELSE IN.SIBLING @ THEN ;

\ _EXPL-LABEL ( node -- addr len )
\   Tree callback: get node label text.
\   Directories are already distinguished by their expand/collapse
\   indicator (▼/▶) in the tree widget, so no prefix is needed.
: _EXPL-LABEL  ( node -- addr len )
    DUP _EXPL-PLACE? IF TREE-WALK-CONTEXT _EXPL-PLACE-LABEL EXIT THEN
    IN.NAME @ _VFS-STR-GET ;

\ _EXPL-LEAF? ( node -- flag )
\   Tree callback: true if the node is neither a place nor a directory.
: _EXPL-LEAF?  ( node -- flag )
    DUP _EXPL-PLACE? IF DROP 0 EXIT THEN
    IN.TYPE @ VFS-T-DIR <> ;

\ A stable nonzero key: 64-bit FNV-1a over a parent's key and a name.
0xCBF29CE484222325 CONSTANT _EXPL-FNV-BASIS
0x100000001B3 CONSTANT _EXPL-FNV-PRIME
VARIABLE _EXK-H

: _EXK-BYTE  ( byte -- )  _EXK-H @ XOR _EXPL-FNV-PRIME * _EXK-H ! ;

: _EXPL-NAME-KEY  ( parent-key name-a name-u -- key )
    _EXPL-FNV-BASIS _EXK-H !
    ROT 8 0 DO DUP 255 AND _EXK-BYTE 8 RSHIFT LOOP DROP
    0 ?DO DUP I + C@ _EXK-BYTE LOOP DROP
    _EXK-H @ ?DUP 0= IF 1 THEN ;

\ EXPL-PLACE-KEY ( place -- key )
\   A place row's key, from the place's name.  Names are unique in a set.
: EXPL-PLACE-KEY  ( place -- key )  0 SWAP PLACE-NAME _EXPL-NAME-KEY ;

\ EXPL-ENTRY-KEY ( parent-key inode -- key )
\   A directory entry's key, from its parent's key and its name.  Names
\   are unique within a directory, so entries shown together get different
\   keys, and an entry keeps its key across refreshes and reloads.  The
\   parent of a place's folder's entries is the place row.
: EXPL-ENTRY-KEY  ( parent-key inode -- key )
    IN.NAME @ _VFS-STR-GET _EXPL-NAME-KEY ;

\ The bytes of a path before its first slash.
: _EXPL-NAME-END  ( a u -- n )
    0
    BEGIN
        2DUP > IF 2 PICK OVER + C@ [CHAR] / <> ELSE 0 THEN
    WHILE
        1+
    REPEAT
    NIP NIP ;

\ EXPL-PATH-KEY ( path-a path-u place -- key )
\   The key of the entry at a path of a place, as the tree keys it: the
\   place's key, then each name of the path in turn.  "/" is the place's
\   own row.  The path is one PLACE-PATH gave, so its names are the
\   entries' own, and no entry is looked up.
: EXPL-PATH-KEY  ( path-a path-u place -- key )
    EXPL-PLACE-KEY >R
    BEGIN DUP 0> WHILE
        OVER C@ [CHAR] / = IF
            1 /STRING
        ELSE
            2DUP _EXPL-NAME-END                     ( a u n )
            R> 3 PICK 2 PICK _EXPL-NAME-KEY >R
            /STRING
        THEN
    REPEAT
    2DROP R> ;

\ _EXPL-KEY ( parent-key node -- key )
\   Tree callback: a node's key.  It also notes each place as the tree
\   walks into its rows.
: _EXPL-KEY  ( parent-key node -- key )
    DUP _EXPL-PLACE? IF
        NIP DUP TREE-WALK-CONTEXT _EXPL-O-PLACE + !
        EXPL-PLACE-KEY EXIT
    THEN
    EXPL-ENTRY-KEY ;

\ =====================================================================
\  §4 — Tree callbacks
\ =====================================================================
\  The tree reports a moved selection and an opened node; the explorer
\  passes them on with the entry and its place.

\ _EXPL-SELECTION ( explorer -- inode place )
\   The selected entry and its place; inode 0 on a place's own row, and
\   0 0 when nothing is selected.
: _EXPL-SELECTION  ( explorer -- inode place )
    DUP _EXPL-O-TREE + @ TREE-SELECTED              ( explorer node )
    DUP 0= IF NIP 0 EXIT THEN
    2DUP SWAP _EXPL-SET PLSET-MEMBER? IF NIP 0 SWAP EXIT THEN
    SWAP _EXPL-O-PLACE + @ ;

: _EXPL-ON-TREE-SEL  ( tree-widget -- )
    TREE-CONTEXT@ DUP _EXPL-SELECTION               ( explorer inode place )
    DUP 0= IF DROP 2DROP EXIT THEN
    ROT DUP _EXPL-O-ON-SEL + @ ?DUP IF EXECUTE ELSE DROP 2DROP THEN ;

\ Opening a place or a directory expands or collapses it; opening a file
\ reports it.
: _EXPL-ON-TREE-OPEN  ( tree-widget -- )
    DUP TREE-CONTEXT@ DUP _EXPL-SELECTION           ( tree explorer inode place )
    DUP 0= IF 2DROP 2DROP EXIT THEN
    OVER 0= IF NIP NIP TREE-TOGGLE EXIT THEN        \ a place's own row
    OVER IN.TYPE @ VFS-T-DIR = IF DROP NIP TREE-TOGGLE EXIT THEN
    ROT DUP _EXPL-O-ON-OPEN + @ ?DUP IF
        EXECUTE
    ELSE
        DROP 2DROP
    THEN
    DROP ;

\ _EXPL-NEW-TREE ( explorer -- tree )
\   A tree over the explorer's places, reporting to the explorer.
: _EXPL-NEW-TREE  ( explorer -- tree )
    DUP _EXPL-SET PLSET-FIRST OVER _EXPL-O-FIRST + !
    DUP WDG-REGION
    OVER _EXPL-O-FIRST + @
    ['] _EXPL-CHILDREN
    ['] _EXPL-NEXT
    ['] _EXPL-LABEL
    ['] _EXPL-LEAF?
    ['] _EXPL-KEY
    TREE-NEW                                        ( explorer tree )
    TUCK TREE-CONTEXT!
    ['] _EXPL-ON-TREE-SEL OVER TREE-ON-SELECT
    ['] _EXPL-ON-TREE-OPEN OVER TREE-ON-OPEN ;

\ Show hidden files, or stop.  The tree's walker does not read the flag,
\ so the tree's rows stay as they were and only the explorer changes.
: _EXPL-HIDDEN-TOGGLE  ( explorer -- )
    DUP _EXPL-O-FLAGS2 + DUP @ _EXPL-F2-HIDDEN XOR SWAP !
    WDG-DIRTY ;

\ What the explorer shows includes its tree, while it renames, its input,
\ and its set's places, so their changes move the explorer's revision
\ too.  _EXPL-FOLLOW counts a change they have made since the explorer
\ last looked.  A word that gives the explorer another tree or input marks
\ it itself, since the new widget's count starts again, and takes the
\ counts with _EXPL-SEEN!.
: _EXPL-INNER-REV  ( explorer -- n )
    DUP _EXPL-O-TREE + @ WDG-REVISION
    OVER _EXPL-SET PLSET-REVISION +
    SWAP _EXPL-O-REN-INP + @ ?DUP IF WDG-REVISION + THEN ;
: _EXPL-SEEN!  ( explorer -- )
    DUP _EXPL-INNER-REV SWAP _EXPL-O-SEEN + ! ;
: _EXPL-FOLLOW  ( explorer -- )
    DUP _EXPL-INNER-REV
    2DUP SWAP _EXPL-O-SEEN + @ = IF 2DROP EXIT THEN
    OVER _EXPL-O-SEEN + !  _WDG-CHANGED ;

\ _EXPL-PLACES-SYNC ( explorer -- )
\   Take the places as they are now: their labels, and another tree when
\   the set's first place is another, since the tree starts there.
: _EXPL-PLACES-SYNC  ( explorer -- )
    DUP _EXPL-LABELS!
    DUP _EXPL-SET PLSET-FIRST OVER _EXPL-O-FIRST + @ = IF DROP EXIT THEN
    DUP _EXPL-O-TREE + @ TREE-FREE
    DUP _EXPL-NEW-TREE OVER _EXPL-O-TREE + !
    DUP _EXPL-SEEN!  WDG-DIRTY ;

\ The embedded tree takes the explorer's focus and enabled state, which
\ UIDL maintains on the mounted explorer.
: _EXPL-SYNC-TREE  ( explorer -- )
    DUP WDG-FOCUSED? WDG-F-FOCUSED 2 PICK _EXPL-O-TREE + @ WDG-FLAG!
    DUP WDG-DISABLED? WDG-F-DISABLED ROT _EXPL-O-TREE + @ WDG-FLAG! ;

\ =====================================================================
\  §5 — Draw handler
\ =====================================================================

: _EXPL-DRAW  ( widget -- )
    DUP _EXPL-SET PLSET-REVISION OVER _EXPL-O-SET-REV + @ <> IF
        DUP _EXPL-SET PLSET-REVISION OVER _EXPL-O-SET-REV + !
        DUP _EXPL-PLACES-SYNC
    THEN
    DUP _EXPL-SYNC-TREE
    DUP _EXPL-O-TREE + @ WDG-DRAW
    \ If rename is active, draw the input widget on top
    DUP _EXPL-O-FLAGS2 + @ _EXPL-F2-RENAME AND IF
        DUP _EXPL-O-REN-INP + @ ?DUP IF WDG-DRAW THEN
    THEN
    _EXPL-FOLLOW ;

\ =====================================================================
\  §6 — Rename helpers
\ =====================================================================

VARIABLE _EXRN-W    \ explorer widget during rename operations

VARIABLE _EXRC-INP  \ rename-commit: input widget
VARIABLE _EXRC-IN   \ rename-commit: inode being renamed
VARIABLE _EXRC-PL   \ rename-commit: its place
VARIABLE _EXRC-NA   \ rename-commit: new name addr
VARIABLE _EXRC-NU   \ rename-commit: new name len

\ _EXPL-RENAME-VALIDATE ( addr len place -- flag )
\   Return TRUE if name is valid: non-empty, no '/', and no longer than
\   the place's volume takes.  The rename itself refuses a name its
\   folder already holds.
: _EXPL-RENAME-VALIDATE  ( addr len place -- flag )
    PLACE-NAME-LIMIT OVER < IF 2DROP FALSE EXIT THEN
    DUP 0= IF 2DROP FALSE EXIT THEN
    \ Check for '/' in name
    DUP 0 ?DO
        OVER I + C@ [CHAR] / = IF
            2DROP FALSE UNLOOP EXIT
        THEN
    LOOP
    2DROP TRUE ;

\ _EXPL-RENAME-CANCEL ( widget -- )
\   End inline rename and dismiss the input widget.  The input goes, so
\   the explorer marks itself.
: _EXPL-RENAME-CANCEL  ( widget -- )
    DUP _EXPL-O-FLAGS2 + DUP @
    _EXPL-F2-RENAME INVERT AND SWAP !
    DUP _EXPL-O-REN-INP + @ ?DUP IF INP-FREE THEN
    0 OVER _EXPL-O-REN-INP + !
    DUP _EXPL-O-TREE + @ TREE-REFRESH
    DUP _EXPL-SEEN!  _WDG-CHANGED ;

\ _EXPL-RENAME-COMMIT ( input-widget -- )
\   Called when user presses Enter in rename input.
: _EXPL-RENAME-COMMIT  ( input-widget -- )
    _EXRC-INP !
    _EXRN-W @ _EXPL-SELECTION _EXRC-PL ! _EXRC-IN !
    _EXRC-IN @ 0= IF  EXIT  THEN

    \ Get text from input
    _EXRC-INP @ INP-GET-TEXT  _EXRC-NU !  _EXRC-NA !

    \ Validate
    _EXRC-NA @  _EXRC-NU @  _EXRC-PL @
    _EXPL-RENAME-VALIDATE  0= IF  EXIT  THEN

    _EXRC-NA @ _EXRC-NU @ _EXRC-IN @ _EXRC-PL @ PLACE-RENAME IF EXIT THEN

    _EXRC-PL @ PLACE-SYNC DROP

    _EXRN-W @ _EXPL-RENAME-CANCEL ;

\ =====================================================================
\  §7 — Public: rename / delete / new file / new dir / refresh
\ =====================================================================
\  Each changes the selected entry's place through the PLACE- words, so a
\  read-only place refuses, and nothing renames or deletes a place's own
\  row.

\ _EXPL-CHANGEABLE ( widget -- inode place flag )
\   The selected entry and its place, and whether the place may change.
: _EXPL-CHANGEABLE  ( widget -- inode place flag )
    _EXPL-SELECTION DUP PLACE-WRITABLE? ;

\ EXPL-RENAME ( widget -- )
\   Start inline rename of selected entry.

VARIABLE _EXR-W
VARIABLE _EXR-IN

: EXPL-RENAME  ( widget -- )
    _EXR-W !
    _EXR-W @ _EXRN-W !
    _EXR-W @ _EXPL-CHANGEABLE 0= IF 2DROP EXIT THEN
    DROP _EXR-IN !
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
    _EXR-W @ _EXPL-SEEN!
    _EXR-W @ WDG-DIRTY ;

\ EXPL-DELETE ( widget -- )
\   Ask before deleting the selected entry; a confirming answer deletes it.

VARIABLE _EXD-W
VARIABLE _EXD-IN
VARIABLE _EXD-PL

\ The answer comes later, so the entry is deleted only while it is still
\ the one selected.
: _EXPL-DELETE-CONFIRMED  ( confirmed? widget -- )
    _EXD-W !
    0= IF EXIT THEN
    _EXD-W @ _EXPL-SELECTION _EXD-PL ! _EXD-IN !
    _EXD-IN @ 0= IF EXIT THEN
    _EXD-IN @ _EXD-W @ _EXPL-O-DELETE + @ <> IF EXIT THEN
    _EXD-PL @ _EXD-W @ _EXPL-O-DEL-PLACE + @ <> IF EXIT THEN

    _EXD-IN @ _EXD-PL @ _EXD-W @ _EXPL-O-PATH + @ _EXPL-PATH-CAP PLACE-PATH
    IF DROP EXIT THEN                     ( len )
    _EXD-W @ _EXPL-O-PATH + @ SWAP _EXD-PL @ PLACE-RM DROP

    \ Sync and refresh
    _EXD-PL @ PLACE-SYNC DROP
    _EXD-W @ _EXPL-O-TREE + @ TREE-REFRESH
    _EXD-W @ _EXPL-FOLLOW ;

: EXPL-DELETE  ( widget -- )
    _EXD-W !
    _EXD-W @ _EXPL-CHANGEABLE 0= IF 2DROP EXIT THEN
    _EXD-PL ! _EXD-IN !
    _EXD-IN @ 0= IF EXIT THEN
    _EXD-IN @ _EXD-W @ _EXPL-O-DELETE + !
    _EXD-PL @ _EXD-W @ _EXPL-O-DEL-PLACE + !
    S" Delete the selected entry?" S" Delete"
        ['] _EXPL-DELETE-CONFIRMED _EXD-W @ DLG-CONFIRM DROP ;

\ EXPL-NEW-FILE ( widget -- )   and   EXPL-NEW-DIR ( widget -- )
\   Create "newfile", or the folder "newfolder", in the selected
\   directory, beside the selected file, or in the selected place's
\   folder.

VARIABLE _EXN-W
VARIABLE _EXN-IN
VARIABLE _EXN-PL
VARIABLE _EXN-LEN

\ _EXPL-NEW-PATH ( name-a name-u widget -- path-a path-u place flag )
\   The path of a new entry NAME where the selection puts it, in the
\   widget's path scratch.  False when the place may not change or the
\   path does not fit.
: _EXPL-NEW-PATH  ( name-a name-u widget -- path-a path-u place flag )
    _EXN-W !
    _EXN-W @ _EXPL-CHANGEABLE 0= IF 2DROP 2DROP 0 0 0 FALSE EXIT THEN
    _EXN-PL ! _EXN-IN !
    \ The target directory: the place's folder, the selected directory,
    \ or the selected file's.
    _EXN-IN @ 0= IF
        _EXN-PL @ PLACE-ROOT
    ELSE
        _EXN-IN @ IN.TYPE @ VFS-T-DIR = IF
            _EXN-IN @
        ELSE
            _EXN-IN @ IN.PARENT @
        THEN
    THEN
    DUP 0= IF DROP 2DROP 0 0 0 FALSE EXIT THEN
    _EXN-PL @ _EXN-W @ _EXPL-O-PATH + @ _EXPL-PATH-CAP PLACE-PATH
    IF DROP 2DROP 0 0 0 FALSE EXIT THEN
    DUP 1 = IF DROP 0 THEN _EXN-LEN !     \ the folder itself is "/"
    _EXN-LEN @ 1+ OVER + _EXPL-PATH-CAP > IF 2DROP 0 0 0 FALSE EXIT THEN
    [CHAR] / _EXN-W @ _EXPL-O-PATH + @ _EXN-LEN @ + C!
    TUCK _EXN-W @ _EXPL-O-PATH + @ _EXN-LEN @ + 1+ SWAP CMOVE
    _EXN-LEN @ + 1+ _EXN-W @ _EXPL-O-PATH + @ SWAP
    _EXN-PL @ TRUE ;

: _EXPL-NEW-DONE  ( place widget -- )
    SWAP PLACE-SYNC DROP
    DUP _EXPL-O-TREE + @ TREE-REFRESH
    _EXPL-FOLLOW ;

: EXPL-NEW-FILE  ( widget -- )
    >R S" newfile" R@ _EXPL-NEW-PATH 0= IF DROP 2DROP R> DROP EXIT THEN
    DUP >R PLACE-CREATE 2DROP
    R> R> _EXPL-NEW-DONE ;

: EXPL-NEW-DIR  ( widget -- )
    >R S" newfolder" R@ _EXPL-NEW-PATH 0= IF DROP 2DROP R> DROP EXIT THEN
    DUP >R PLACE-MKDIR DROP
    R> R> _EXPL-NEW-DONE ;

\ EXPL-REFRESH ( widget -- )
\   Re-read the places, re-trigger VFS lazy loading and redraw.
: EXPL-REFRESH  ( widget -- )
    DUP _EXPL-PLACES-SYNC
    DUP _EXPL-O-TREE + @ TREE-REFRESH
    _EXPL-FOLLOW ;

\ =====================================================================
\  §8 — Event handler
\ =====================================================================

VARIABLE _EXH-W    \ explorer widget during event handling
VARIABLE _EXH-EV   \ current event

: _EXPL-HANDLE  ( event widget -- consumed? )
    _EXH-W !  _EXH-EV !
    _EXH-W @ _EXRN-W !

    \ ── If rename is active, route keys to the input widget ──
    _EXH-W @ _EXPL-O-FLAGS2 + @ _EXPL-F2-RENAME AND IF
        \ Check for Escape to cancel rename
        _EXH-EV @ KEY-IS-SPECIAL? IF
            _EXH-EV @ KEY-CODE@ KEY-ESC = IF
                _EXH-W @ _EXPL-RENAME-CANCEL
                -1 EXIT
            THEN
        THEN
        \ Forward everything else to the input widget
        _EXH-EV @ _EXH-W @ _EXPL-O-REN-INP + @ WDG-HANDLE
        _EXH-W @ _EXPL-FOLLOW
        EXIT
    THEN

    \ ── Pointer: the embedded tree selects, expands, opens, and scrolls,
    \    and reports through its callbacks ──
    _EXH-EV @ @ KEY-T-MOUSE = IF
        _EXH-EV @ _EXH-W @ _EXPL-O-TREE + @ WDG-HANDLE
        _EXH-W @ _EXPL-FOLLOW
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

        \ Escape — no-op at top level
        KEY-ESC = IF 0 EXIT THEN

        \ Navigation and Enter go to the tree, which reports through its
        \ callbacks.
        _EXH-EV @ _EXH-W @ _EXPL-O-TREE + @ WDG-HANDLE
        _EXH-W @ _EXPL-FOLLOW
        EXIT
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
                _EXH-W @ _EXPL-HIDDEN-TOGGLE
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

: EXPL-NEW  ( rgn set -- widget )
    >R                                     ( rgn  R: set )

    \ Allocate descriptor
    _EXPL-DESC-SZ ALLOCATE
    0<> ABORT" EXPL-NEW: alloc"
    DUP _EXPL-DESC-SZ 0 FILL

    \ Fill common header
    WDG-T-EXPLORER    OVER _WDG-O-TYPE      + !
    SWAP               OVER _WDG-O-REGION    + !
    ['] _EXPL-DRAW     OVER _WDG-O-DRAW-XT   + !
    ['] _EXPL-HANDLE   OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                       OVER _WDG-O-FLAGS     + !

    \ Fill explorer-specific fields
    R>                 OVER _EXPL-O-SET      + !

    \ Allocate the rename buffer and the path scratch
    _EXPL-REN-CAP ALLOCATE
    0<> ABORT" EXPL-NEW: rename buf"
    OVER _EXPL-O-REN-BUF + !
    _EXPL-PATH-CAP ALLOCATE
    0<> ABORT" EXPL-NEW: path buf"
    OVER _EXPL-O-PATH + !

    \ The place rows' labels, and the embedded tree over the places
    DUP _EXPL-SET PLSET-REVISION OVER _EXPL-O-SET-REV + !
    DUP _EXPL-LABELS!
    DUP _EXPL-NEW-TREE OVER _EXPL-O-TREE + !    ( desc )
    DUP _EXPL-SEEN! ;

\ =====================================================================
\  §10 — Public API
\ =====================================================================

\ EXPL-SELECTED ( widget -- inode place )
\   The selected entry and its place.  The inode is 0 on a place's own
\   row, and both are 0 when nothing is selected.  The inode is valid
\   until the next VFS operation.
: EXPL-SELECTED  ( widget -- inode place )
    _EXPL-SELECTION ;

\ EXPL-ON-OPEN ( xt widget -- )
\   Set file-opened callback: ( inode place explorer -- )
: EXPL-ON-OPEN  ( xt widget -- )
    _EXPL-O-ON-OPEN + ! ;

\ EXPL-ON-SELECT ( xt widget -- )
\   Set selection-changed callback: ( inode place explorer -- ), with
\   inode 0 on a place's own row.
: EXPL-ON-SELECT  ( xt widget -- )
    _EXPL-O-ON-SEL + ! ;

\ EXPL-SET ( widget -- set )
\   The place set the explorer shows.
: EXPL-SET  ( widget -- set )
    _EXPL-SET ;

\ EXPL-EXPAND-ALL ( widget -- )
\   Expand entire tree.
: EXPL-EXPAND-ALL  ( widget -- )
    DUP _EXPL-O-TREE + @ TREE-EXPAND-ALL  _EXPL-FOLLOW ;

\ EXPL-COLLAPSE-ALL ( widget -- )
\   Collapse every directory.
: EXPL-COLLAPSE-ALL  ( widget -- )
    DUP _EXPL-O-TREE + @ TREE-COLLAPSE-ALL  _EXPL-FOLLOW ;

\ EXPL-SHOW-HIDDEN? ( widget -- flag )
: EXPL-SHOW-HIDDEN?  ( widget -- flag )
    _EXPL-O-FLAGS2 + @ _EXPL-F2-HIDDEN AND 0<> ;

\ EXPL-SHOW-HIDDEN! ( flag widget -- )
\   Show or hide hidden files.
: EXPL-SHOW-HIDDEN!  ( flag widget -- )
    SWAP 0<> OVER EXPL-SHOW-HIDDEN? = IF DROP EXIT THEN
    _EXPL-HIDDEN-TOGGLE ;

\ EXPL-TREE ( widget -- tree-widget )
\   Get the embedded tree widget.
: EXPL-TREE  ( widget -- tree-widget )
    _EXPL-O-TREE + @ ;

\ =====================================================================
\  §11 — Free
\ =====================================================================

\ EXPL-FREE ( widget -- )
\   Free the tree widget, rename input, buffers, labels, descriptor.
\   The set is the caller's.
: EXPL-FREE  ( widget -- )
    DUP _EXPL-O-REN-INP + @ ?DUP IF INP-FREE THEN
    DUP _EXPL-O-REN-BUF + @ FREE
    DUP _EXPL-O-PATH + @ FREE
    DUP _EXPL-O-LABELS + @ ?DUP IF FREE THEN
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
