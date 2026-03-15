\ akashic-pad.f — Akashic Pad v2 (Multi-Tab Editor)
\ ============================================================
\
\ UIDL-TUI multi-tab editor with explorer sidebar + VFS.
\
\ Features:
\   - Split layout: explorer sidebar (20%) + editor area (80%)
\   - Multi-tab editing (up to 8 tabs)
\   - VFS-based file I/O (ramdisk)
\   - CSS styled title bar, status bar, editor
\   - Toast notifications for save/open feedback
\   - Clipboard (copy/cut/paste/select-all)
\   - Tab management: open, close (Ctrl+W), switch (Ctrl+PgDn/Up)
\   - Inspection tab: single Enter = preview, repeat = promote
\   - Modal file-name prompt on status row
\ ============================================================

REQUIRE tui/uidl-tui.f
REQUIRE tui/app.f
REQUIRE tui/widgets/toast.f
REQUIRE tui/widgets/tabs.f
REQUIRE tui/widgets/explorer.f
REQUIRE utils/clipboard.f
REQUIRE utils/string.f

\ ============================================================
\  §1 — UIDL Document (built in a static buffer)
\ ============================================================

CREATE _pad-xml 2048 ALLOT
VARIABLE _pad-xml-len

: _padx  ( c-addr u -- )
    _pad-xml _pad-xml-len @ +
    SWAP DUP >R CMOVE
    R> _pad-xml-len +! ;

0 _pad-xml-len !

\ Root group — auto-sizes to region (SCR-W x SCR-H)
S" <uidl><group id='root'>" _padx

\ Title bar — bold white on purple
S" <label id='titlebar' text=' Akashic Pad '" _padx
S"  style='color:white; background-color:purple; font-weight:bold'/>" _padx

\ Main split: sidebar (20%) + editor area (80%)
S" <split id='main-split' ratio='20'>" _padx
S" <group id='sidebar' style='background-color:black'>" _padx
S" <label id='sb-title' text=' EXPLORER'" _padx
S"  style='color:white; background-color:black; font-weight:bold'/>" _padx
S" <region id='sb-tree' style='background-color:black'/>" _padx
S" </group>" _padx
S" <region id='editor-area' style='background-color:black'/>" _padx
S" </split>" _padx

\ Status bar — white on teal, children split equally
S" <status style='background-color:teal'>" _padx
S" <label id='st-msg' text='Ready'" _padx
S"  style='color:white; background-color:teal'/>" _padx
S" <label id='st-pos' text='Ln 1, Col 1'" _padx
S"  style='color:cyan; background-color:teal'/>" _padx
S" <label id='st-mode' text='INSERT'" _padx
S"  style='color:yellow; background-color:teal'/>" _padx
S" </status>" _padx

\ Keyboard shortcuts (declarative actions)
S" <action id='k-quit'   do='quit'       key='Ctrl+Q'/>" _padx
S" <action id='k-save'   do='save'       key='Ctrl+S'/>" _padx
S" <action id='k-saveas' do='save-as'    key='Ctrl+Shift+S'/>" _padx
S" <action id='k-open'   do='open'       key='Ctrl+O'/>" _padx
S" <action id='k-copy'   do='copy'       key='Ctrl+C'/>" _padx
S" <action id='k-cut'    do='cut'        key='Ctrl+X'/>" _padx
S" <action id='k-paste'  do='paste'      key='Ctrl+V'/>" _padx
S" <action id='k-selall' do='sel-all'    key='Ctrl+A'/>" _padx
S" <action id='k-close'  do='close-tab'  key='Ctrl+W'/>" _padx
S" <action id='k-ntab'   do='next-tab'   key='Ctrl+PageDown'/>" _padx
S" <action id='k-ptab'   do='prev-tab'   key='Ctrl+PageUp'/>" _padx
S" <action id='k-toggle' do='toggle-sb'  key='Ctrl+B'/>" _padx
S" <action id='k-focus'  do='focus-swap' key='Ctrl+E'/>" _padx

S" </group></uidl>" _padx

\ ============================================================
\  §2 — Constants
\ ============================================================

8 CONSTANT _PAD-MAX-TABS
64 CONSTANT _PAD-SLOT-SZ             \ bytes per slot descriptor
4096 CONSTANT _PAD-BUF-SZ            \ bytes per tab text buffer

\ Slot field offsets (8-byte cells)
0  CONSTANT _PAD-S-INODE             \ +0:  VFS inode pointer
8  CONSTANT _PAD-S-TXTA              \ +8:  textarea widget pointer
16 CONSTANT _PAD-S-BUF               \ +16: text buffer address
24 CONSTANT _PAD-S-FNAMEA            \ +24: filename string addr
32 CONSTANT _PAD-S-FNAMEU            \ +32: filename string length
40 CONSTANT _PAD-S-TABIDX            \ +40: index in tab widget
48 CONSTANT _PAD-S-FLAGS             \ +48: flags

\ Flags
1 CONSTANT _PAD-F-DIRTY
2 CONSTANT _PAD-F-INSPECT

\ ============================================================
\  §3 — State Variables
\ ============================================================

VARIABLE _pad-quit              \ quit-requested flag

VARIABLE _pad-vfs               \ VFS instance
VARIABLE _pad-arena             \ VFS arena

VARIABLE _pad-expl-w            \ explorer widget pointer
VARIABLE _pad-tab-w             \ tab widget pointer

VARIABLE _pad-rgn               \ root screen region

\ UIDL element pointers (resolved after UTUI-LOAD)
VARIABLE _pad-titlebar-elem
VARIABLE _pad-stmsg-elem
VARIABLE _pad-stpos-elem
VARIABLE _pad-sidebar-elem
VARIABLE _pad-sbtree-elem
VARIABLE _pad-edarea-elem

\ Panel focus: 0 = editor, 1 = explorer
VARIABLE _pad-focus

\ Slot array
CREATE _pad-slots _PAD-MAX-TABS _PAD-SLOT-SZ * ALLOT
VARIABLE _pad-slot-count        \ number of occupied slots
VARIABLE _pad-inspection        \ inspection slot index, -1 = none

\ Pre-allocated text buffers (one per tab slot)
CREATE _pad-bufs _PAD-MAX-TABS _PAD-BUF-SZ * ALLOT

\ Per-slot filename storage (64 bytes each)
CREATE _pad-fnames _PAD-MAX-TABS 64 * ALLOT

\ Scratch buffers
CREATE _pad-ev      24 ALLOT   \ key event buffer
CREATE _pad-iobuf   4096 ALLOT \ file I/O scratch

CREATE _pad-pos-buf  32 ALLOT
VARIABLE _pad-pos-len

CREATE _pad-msg-buf  64 ALLOT
VARIABLE _pad-msg-len

CREATE _pad-title-buf 80 ALLOT
VARIABLE _pad-title-len

\ Track last-opened inode for inspection promote detection
VARIABLE _pad-last-open-inode

\ Sidebar visible flag
VARIABLE _pad-sb-visible

\ ============================================================
\  §4 — Slot Accessors
\ ============================================================

: _PAD-SLOT  ( idx -- addr )
    _PAD-SLOT-SZ * _pad-slots + ;

: _PAD-SLOT-BUF  ( idx -- buf-addr )
    _PAD-BUF-SZ * _pad-bufs + ;

: _PAD-SLOT-FNAMEBUF  ( idx -- addr )
    64 * _pad-fnames + ;

: _PAD-SLOT-INODE@  ( idx -- inode )
    _PAD-SLOT _PAD-S-INODE + @ ;

: _PAD-SLOT-TXTA@  ( idx -- txta )
    _PAD-SLOT _PAD-S-TXTA + @ ;

: _PAD-SLOT-FLAGS@  ( idx -- flags )
    _PAD-SLOT _PAD-S-FLAGS + @ ;

: _PAD-SLOT-TABIDX@  ( idx -- tab-index )
    _PAD-SLOT _PAD-S-TABIDX + @ ;

: _PAD-SLOT-FNAMEA@  ( idx -- addr len )
    DUP _PAD-SLOT _PAD-S-FNAMEA + @
    SWAP _PAD-SLOT _PAD-S-FNAMEU + @ ;

: _PAD-ACTIVE-SLOT  ( -- idx | -1 )
    _pad-tab-w @ 0= IF -1 EXIT THEN
    _pad-tab-w @ TAB-COUNT 0= IF -1 EXIT THEN
    _pad-tab-w @ TAB-ACTIVE
    \ Walk slots to find one with matching tab-index
    _pad-slot-count @ 0 ?DO
        DUP I _PAD-SLOT _PAD-S-TABIDX + @ = IF
            DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _PAD-FIND-INODE  ( inode -- idx | -1 )
    _pad-slot-count @ 0 ?DO
        DUP I _PAD-SLOT _PAD-S-INODE + @ = IF
            DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ Find slot index by textarea widget pointer
: _PAD-FIND-TXTA  ( txta -- idx | -1 )
    _pad-slot-count @ 0 ?DO
        DUP I _PAD-SLOT _PAD-S-TXTA + @ = IF
            DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ ============================================================
\  §5 — Sidecar → Region Helper
\ ============================================================

: _PAD-ELEM-RGN  ( elem -- rgn )
    _UTUI-SIDECAR               ( sc )
    DUP _UTUI-SC-ROW@           ( sc row )
    OVER _UTUI-SC-COL@          ( sc row col )
    2 PICK _UTUI-SC-H@          ( sc row col h )
    3 PICK _UTUI-SC-W@          ( sc row col h w )
    RGN-NEW                     ( sc rgn )
    NIP ;                       ( rgn )

\ ============================================================
\  §6 — String Helpers
\ ============================================================

: _PAD-TITLE-APPEND  ( addr u -- )
    _pad-title-buf _pad-title-len @ +
    SWAP DUP >R CMOVE
    R> _pad-title-len +! ;

: _PAD-POS-APPEND  ( addr u -- )
    _pad-pos-buf _pad-pos-len @ +
    SWAP DUP >R CMOVE
    R> _pad-pos-len +! ;

: _PAD-MSG-APPEND  ( addr u -- )
    _pad-msg-buf _pad-msg-len @ +
    SWAP DUP >R CMOVE
    R> _pad-msg-len +! ;

\ ============================================================
\  §7 — Tab Label Management
\ ============================================================

\ Build label string for a slot: "filename" or "filename *"
\ For inspection tabs: "~ filename"
CREATE _pad-lbl-buf 48 ALLOT
VARIABLE _pad-lbl-len

: _PAD-LBL-APPEND  ( addr u -- )
    _pad-lbl-buf _pad-lbl-len @ +
    SWAP DUP >R CMOVE
    R> _pad-lbl-len +! ;

: _PAD-UPDATE-TAB-LABEL  ( idx -- )
    0 _pad-lbl-len !
    DUP _PAD-SLOT-FLAGS@ _PAD-F-INSPECT AND IF
        S" ~ " _PAD-LBL-APPEND
    THEN
    DUP _PAD-SLOT-FNAMEA@
    DUP 0> IF
        _PAD-LBL-APPEND
    ELSE
        2DROP S" [new]" _PAD-LBL-APPEND
    THEN
    DUP _PAD-SLOT-FLAGS@ _PAD-F-DIRTY AND IF
        S"  *" _PAD-LBL-APPEND
    THEN
    DUP _PAD-SLOT-TABIDX@              ( idx tab-idx )
    _pad-lbl-buf _pad-lbl-len @        ( idx tab-idx la lu )
    ROT                                ( idx la lu tab-idx )
    _pad-tab-w @ TAB-LABEL!            ( idx )
    _pad-tab-w @ WDG-DIRTY
    DROP ;

: _PAD-MARK-DIRTY  ( idx -- )
    DUP _PAD-SLOT _PAD-S-FLAGS +
    DUP @ _PAD-F-DIRTY OR SWAP !
    _PAD-UPDATE-TAB-LABEL ;

: _PAD-CLEAR-DIRTY  ( idx -- )
    DUP _PAD-SLOT _PAD-S-FLAGS +
    DUP @ _PAD-F-DIRTY INVERT AND SWAP !
    _PAD-UPDATE-TAB-LABEL ;

\ ============================================================
\  §8 — Title Bar & Status Bar Updates
\ ============================================================

: _PAD-UPDATE-TITLE  ( -- )
    _pad-titlebar-elem @ 0= IF EXIT THEN
    0 _pad-title-len !
    S"  Akashic Pad" _PAD-TITLE-APPEND
    _PAD-ACTIVE-SLOT DUP 0>= IF
        DUP _PAD-SLOT-FNAMEA@
        DUP 0> IF
            S"  - " _PAD-TITLE-APPEND
            _PAD-TITLE-APPEND
        ELSE 2DROP THEN
        _PAD-SLOT-FLAGS@ _PAD-F-DIRTY AND IF
            S"  *" _PAD-TITLE-APPEND
        THEN
    ELSE DROP THEN
    S"  " _PAD-TITLE-APPEND
    _pad-titlebar-elem @
    S" text" _pad-title-buf _pad-title-len @
    UIDL-SET-ATTR
    _pad-titlebar-elem @ UIDL-DIRTY! ;

: _PAD-UPDATE-POS  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    _PAD-SLOT-TXTA@ DUP 0= IF DROP EXIT THEN
    0 _pad-pos-len !
    S" Ln " _PAD-POS-APPEND
    DUP TXTA-CURSOR-LINE 1+ NUM>STR _PAD-POS-APPEND
    S" , Col " _PAD-POS-APPEND
    TXTA-CURSOR-COL 1+ NUM>STR _PAD-POS-APPEND
    _pad-stpos-elem @ 0= IF EXIT THEN
    _pad-stpos-elem @
    S" text" _pad-pos-buf _pad-pos-len @
    UIDL-SET-ATTR
    _pad-stpos-elem @ UIDL-DIRTY! ;

: _PAD-UPDATE-MSG-STR  ( addr u -- )
    _pad-stmsg-elem @ 0= IF 2DROP EXIT THEN
    _pad-stmsg-elem @
    S" text" 2SWAP
    UIDL-SET-ATTR
    _pad-stmsg-elem @ UIDL-DIRTY! ;

: _PAD-UPDATE-MSG  ( -- )
    0 _pad-msg-len !
    _PAD-ACTIVE-SLOT DUP 0>= IF
        DUP _PAD-SLOT-FNAMEA@
        DUP 0> IF
            _PAD-MSG-APPEND
            _PAD-SLOT-FLAGS@ _PAD-F-DIRTY AND IF
                S"  *" _PAD-MSG-APPEND
            THEN
        ELSE
            2DROP
            _PAD-SLOT-FLAGS@ _PAD-F-DIRTY AND IF
                S" Modified" _PAD-MSG-APPEND
            ELSE
                S" Ready" _PAD-MSG-APPEND
            THEN
        THEN
    ELSE
        DROP
        S" Ready" _PAD-MSG-APPEND
    THEN
    _pad-msg-buf _pad-msg-len @ _PAD-UPDATE-MSG-STR ;

\ ============================================================
\  §9 — On-change callback (dirty tracking + auto-promote)
\ ============================================================

: _PAD-ON-EDIT  ( widget -- )
    _PAD-FIND-TXTA DUP 0< IF DROP EXIT THEN
    DUP _PAD-SLOT-FLAGS@ _PAD-F-DIRTY AND 0= IF
        DUP _PAD-MARK-DIRTY
        \ Auto-promote inspection tab on first edit
        DUP _PAD-SLOT-FLAGS@ _PAD-F-INSPECT AND IF
            DUP _PAD-SLOT _PAD-S-FLAGS +
            DUP @ _PAD-F-INSPECT INVERT AND SWAP !
            -1 _pad-inspection !
            DUP _PAD-UPDATE-TAB-LABEL
        THEN
        _PAD-UPDATE-MSG
        _PAD-UPDATE-TITLE
    ELSE DROP THEN ;

\ ============================================================
\  §10 — Open / Close Tab
\ ============================================================

\ Store filename from inode into slot
: _PAD-SET-FNAME  ( inode idx -- )
    >R
    IN.NAME @ _VFS-STR-GET           ( addr len )
    63 MIN DUP                        ( addr len' len' )
    R@ _PAD-SLOT _PAD-S-FNAMEU + !
    R@ _PAD-SLOT-FNAMEBUF             ( addr len' fbuf )
    SWAP CMOVE                        ( )
    R@ _PAD-SLOT-FNAMEBUF
    R> _PAD-SLOT _PAD-S-FNAMEA + ! ;

\ Load VFS file content into a slot's buffer + textarea
VARIABLE _pad-load-fd

: _PAD-LOAD-INODE  ( inode idx -- )
    >R
    \ Open file by inode name
    IN.NAME @ _VFS-STR-GET           ( addr len )
    VFS-OPEN                          ( fd | 0 )
    DUP 0= IF DROP R> DROP EXIT THEN
    _pad-load-fd !
    \ Read content into slot buffer
    R@ _PAD-SLOT-BUF _PAD-BUF-SZ 1-
    _pad-load-fd @ VFS-READ           ( actual )
    \ Null-terminate
    DUP R@ _PAD-SLOT-BUF + 0 SWAP C!
    \ Set textarea text
    R@ _PAD-SLOT-BUF SWAP
    R@ _PAD-SLOT-TXTA@ TXTA-SET-TEXT
    \ Close FD
    _pad-load-fd @ VFS-CLOSE
    R> DROP ;

\ Open a file in a new dedicated tab
: _PAD-OPEN-DEDICATED  ( inode -- )
    _pad-slot-count @ _PAD-MAX-TABS >= IF
        DROP S" Too many tabs" 2000 TST-SHOW EXIT
    THEN
    \ Allocate the next slot index
    _pad-slot-count @                 ( inode slot-idx )
    \ Zero the slot descriptor
    DUP _PAD-SLOT _PAD-SLOT-SZ 0 FILL
    \ Create tab in tab widget (returns content region)
    S" loading..." _pad-tab-w @ TAB-ADD   ( inode slot-idx content-rgn )
    \ Create textarea in content region
    OVER _PAD-SLOT-BUF                ( inode idx rgn buf )
    _PAD-BUF-SZ TXTA-NEW             ( inode idx txta )
    \ Wire on-change callback
    ['] _PAD-ON-EDIT OVER TXTA-ON-CHANGE   ( inode idx txta )
    \ Fill slot descriptor
    OVER _PAD-SLOT >R                 ( inode idx txta  R: slot-addr )
    R@ _PAD-S-TXTA + !               \ store txta
    SWAP R@ _PAD-S-INODE + !         \ store inode   ( idx  R: slot-addr )
    DUP _PAD-SLOT-BUF R@ _PAD-S-BUF + !  \ store buf addr
    _pad-tab-w @ TAB-COUNT 1-
    R@ _PAD-S-TABIDX + !             \ store tab-index
    0 R> _PAD-S-FLAGS + !            \ flags = 0 (dedicated, clean)
    \ Store filename from inode
    DUP _PAD-SLOT-INODE@ OVER _PAD-SET-FNAME   ( idx )
    \ Increment slot count
    1 _pad-slot-count +!
    \ Load file content from VFS
    DUP _PAD-SLOT-INODE@ OVER _PAD-LOAD-INODE  ( idx )
    \ Update tab label with actual filename
    DUP _PAD-UPDATE-TAB-LABEL
    \ Select the new tab
    DUP _PAD-SLOT-TABIDX@ _pad-tab-w @ TAB-SELECT
    DROP
    \ Update title + status + switch focus to editor
    _PAD-UPDATE-TITLE
    _PAD-UPDATE-MSG
    0 _pad-focus ! ;

\ Open a file in the inspection tab (reuses or creates one)
: _PAD-OPEN-INSPECTION  ( inode -- )
    _pad-inspection @ 0>= IF
        \ --- Reuse existing inspection slot ---
        _pad-inspection @             ( inode insp-idx )
        \ Update inode in slot
        2DUP _PAD-SLOT _PAD-S-INODE + !  DROP  ( inode insp-idx )
        \ Clear textarea contents
        DUP _PAD-SLOT-TXTA@ TXTA-CLEAR
        \ Clear dirty flag
        DUP _PAD-SLOT _PAD-S-FLAGS +
        DUP @ _PAD-F-DIRTY INVERT AND SWAP !
        \ Store new filename
        2DUP SWAP _PAD-SET-FNAME      ( inode insp-idx )
        \ Load content
        SWAP OVER _PAD-LOAD-INODE     ( insp-idx )
        \ Update label + select
        DUP _PAD-UPDATE-TAB-LABEL
        DUP _PAD-SLOT-TABIDX@ _pad-tab-w @ TAB-SELECT
        DROP
    ELSE
        \ --- Create new inspection slot ---
        _pad-slot-count @ _PAD-MAX-TABS >= IF
            DROP S" Too many tabs" 2000 TST-SHOW EXIT
        THEN
        _pad-slot-count @             ( inode slot-idx )
        DUP _PAD-SLOT _PAD-SLOT-SZ 0 FILL
        \ Create tab in widget
        S" ~ ..." _pad-tab-w @ TAB-ADD  ( inode idx content-rgn )
        \ Create textarea
        OVER _PAD-SLOT-BUF            ( inode idx rgn buf )
        _PAD-BUF-SZ TXTA-NEW          ( inode idx txta )
        \ Wire on-change
        ['] _PAD-ON-EDIT OVER TXTA-ON-CHANGE   ( inode idx txta )
        \ Fill slot
        OVER _PAD-SLOT >R
        R@ _PAD-S-TXTA + !
        SWAP R@ _PAD-S-INODE + !      ( idx  R: slot )
        DUP _PAD-SLOT-BUF R@ _PAD-S-BUF + !
        _pad-tab-w @ TAB-COUNT 1-
        R@ _PAD-S-TABIDX + !
        _PAD-F-INSPECT
        R> _PAD-S-FLAGS + !           \ flags = INSPECT
        \ Record as inspection slot
        DUP _pad-inspection !
        \ Store filename
        DUP _PAD-SLOT-INODE@ OVER _PAD-SET-FNAME
        1 _pad-slot-count +!
        \ Load content
        DUP _PAD-SLOT-INODE@ OVER _PAD-LOAD-INODE
        \ Update label + select
        DUP _PAD-UPDATE-TAB-LABEL
        DUP _PAD-SLOT-TABIDX@ _pad-tab-w @ TAB-SELECT
        DROP
    THEN
    _PAD-UPDATE-TITLE
    _PAD-UPDATE-MSG
    0 _pad-focus ! ;

\ Promote inspection tab to dedicated
: _PAD-PROMOTE  ( idx -- )
    DUP _PAD-SLOT _PAD-S-FLAGS +
    DUP @ _PAD-F-INSPECT INVERT AND SWAP !
    -1 _pad-inspection !
    _PAD-UPDATE-TAB-LABEL ;

\ Master open logic
: _PAD-OPEN-FILE  ( inode -- )
    DUP _PAD-FIND-INODE DUP 0>= IF
        \ Already open
        DUP _PAD-SLOT-FLAGS@ _PAD-F-INSPECT AND IF
            \ It's the inspection tab — check if active → promote
            DUP _PAD-ACTIVE-SLOT = IF
                _PAD-PROMOTE
                DROP                  \ drop inode
            ELSE
                _PAD-SLOT-TABIDX@
                _pad-tab-w @ TAB-SELECT
                DROP                  \ drop inode
                0 _pad-focus !
            THEN
        ELSE
            \ Dedicated tab — select it
            _PAD-SLOT-TABIDX@
            _pad-tab-w @ TAB-SELECT
            DROP                      \ drop inode
            0 _pad-focus !
        THEN
        _PAD-UPDATE-TITLE
        _PAD-UPDATE-MSG
        EXIT
    THEN
    DROP                              \ drop -1 from FIND-INODE

    \ Not open yet — open in inspection tab
    DUP _pad-last-open-inode !
    _PAD-OPEN-INSPECTION ;

\ Close the currently active tab
VARIABLE _pad-close-i

: _PAD-CLOSE-TAB  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    _pad-close-i !

    \ If dirty AND dedicated, confirm discard
    _pad-close-i @ _PAD-SLOT-FLAGS@
    DUP _PAD-F-DIRTY AND
    SWAP _PAD-F-INSPECT AND 0= AND IF
        S" Unsaved changes. Discard?" DLG-CONFIRM 0= IF EXIT THEN
    THEN

    \ Free textarea widget
    _pad-close-i @ _PAD-SLOT-TXTA@ ?DUP IF TXTA-FREE THEN

    \ Zero the slot's buffer
    _pad-close-i @ _PAD-SLOT-BUF _PAD-BUF-SZ 0 FILL

    \ Remove tab from tab widget
    _pad-close-i @ _PAD-SLOT-TABIDX@
    _pad-tab-w @ TAB-REMOVE

    \ If this was the inspection tab, clear it
    _pad-close-i @ _pad-inspection @ = IF
        -1 _pad-inspection !
    THEN

    \ Shift slots above this one down by one
    _pad-slot-count @ 1- _pad-close-i @ ?DO
        I 1+ _PAD-SLOT                   ( src )
        I _PAD-SLOT                       ( src dst )
        _PAD-SLOT-SZ CMOVE
    LOOP

    \ Decrement count
    -1 _pad-slot-count +!

    \ Fix tab-index fields for shifted slots
    _pad-slot-count @ _pad-close-i @ ?DO
        I _PAD-SLOT _PAD-S-TABIDX +
        DUP @ 1- SWAP !
        \ Fix inspection index if it pointed to a shifted slot
        I 1+ _pad-inspection @ = IF
            I _pad-inspection !
        THEN
    LOOP

    \ Update UI
    _pad-tab-w @ WDG-DIRTY
    _PAD-UPDATE-TITLE
    _PAD-UPDATE-MSG ;

\ Close all tabs (shutdown cleanup)
: _PAD-CLOSE-ALL  ( -- )
    _pad-slot-count @ 0 ?DO
        I _PAD-SLOT-TXTA@ ?DUP IF TXTA-FREE THEN
        I _PAD-SLOT-BUF _PAD-BUF-SZ 0 FILL
    LOOP
    0 _pad-slot-count !
    -1 _pad-inspection ! ;

\ ============================================================
\  §11 — Explorer Callbacks
\ ============================================================

: _PAD-ON-EXPL-OPEN  ( inode explorer -- )
    DROP                               \ don't need explorer ptr
    DUP IN.TYPE @ VFS-T-DIR = IF
        DROP EXIT                      \ ignore directories
    THEN
    _PAD-OPEN-FILE ;

: _PAD-ON-EXPL-SELECT  ( inode explorer -- )
    DROP
    IN.NAME @ _VFS-STR-GET             ( addr len )
    _PAD-UPDATE-MSG-STR ;

\ ============================================================
\  §12 — File I/O (VFS-based)
\ ============================================================

VARIABLE _pad-sav-fd

: _PAD-DO-SAVE  ( idx -- ior )
    DUP _PAD-SLOT-INODE@ DUP 0= IF 2DROP -1 EXIT THEN
    \ Open file by inode name
    IN.NAME @ _VFS-STR-GET             ( idx addr len )
    VFS-OPEN                           ( idx fd|0 )
    DUP 0= IF NIP -1 EXIT THEN
    _pad-sav-fd !                      ( idx )
    \ Get text from textarea
    DUP _PAD-SLOT-TXTA@ TXTA-GET-TEXT  ( idx addr len )
    \ Rewind then write
    _pad-sav-fd @ VFS-REWIND
    _pad-sav-fd @ VFS-WRITE            ( idx actual )
    DROP                               ( idx )
    _pad-sav-fd @ VFS-CLOSE
    \ Update inode size
    DUP _PAD-SLOT-TXTA@ TXTA-GET-TEXT NIP
    OVER _PAD-SLOT-INODE@ IN.SIZE-LO !
    DROP 0 ;

\ ============================================================
\  §13 — Status-bar prompt (modal mini-prompt)
\ ============================================================

: _PAD-DIRTY-STATUS  ( -- )
    _pad-stmsg-elem @ ?DUP IF
        DUP UIDL-PARENT ?DUP IF
            DUP UIDL-DIRTY!
            UIDL-FIRST-CHILD
            BEGIN DUP 0<> WHILE
                DUP UIDL-DIRTY!
                UIDL-NEXT-SIB
            REPEAT DROP
        ELSE UIDL-DIRTY! THEN
    THEN ;

: _PAD-AFTER-PROMPT  ( -- )
    _PAD-DIRTY-STATUS
    _PAD-ACTIVE-SLOT DUP 0>= IF
        _PAD-SLOT-TXTA@ ?DUP IF WDG-DIRTY THEN
    ELSE DROP THEN
    _pad-expl-w @ ?DUP IF WDG-DIRTY THEN
    _pad-tab-w @ ?DUP IF WDG-DIRTY THEN
    UTUI-PAINT SCR-FLUSH ;

CREATE _pad-pr-buf 64 ALLOT
VARIABLE _pad-pr-len
VARIABLE _pad-pr-a
VARIABLE _pad-pr-u

: _PAD-PR-REDRAW  ( -- )
    RGN-ROOT DRW-STYLE-RESET
    SCR-H 1- 0 1 SCR-W DRW-CLEAR-RECT
    _pad-pr-a @ _pad-pr-u @  SCR-H 1-  0  DRW-TEXT
    _pad-pr-buf _pad-pr-len @  SCR-H 1-  _pad-pr-u @  DRW-TEXT
    SCR-FLUSH ;

: _PAD-PROMPT  ( label-a label-u -- addr len | 0 0 )
    _pad-pr-u !  _pad-pr-a !
    0 _pad-pr-len !
    _PAD-PR-REDRAW
    BEGIN
        _pad-ev KEY-READ DROP
        _pad-ev @ KEY-T-SPECIAL = IF
            _pad-ev 8 + @
            DUP KEY-ENTER = IF
                DROP _PAD-AFTER-PROMPT
                _pad-pr-buf _pad-pr-len @ EXIT
            THEN
            DUP KEY-ESC = IF
                DROP _PAD-AFTER-PROMPT
                0 0 EXIT
            THEN
            DUP KEY-BACKSPACE = IF
                DROP
                _pad-pr-len @ 0> IF
                    -1 _pad-pr-len +!
                    _PAD-PR-REDRAW
                THEN
            ELSE DROP THEN
        ELSE
            _pad-ev @ KEY-T-CHAR = IF
                _pad-ev 8 + @
                DUP 32 >= OVER 127 < AND IF
                    _pad-pr-len @ 60 < IF
                        _pad-pr-buf _pad-pr-len @ + C!
                        1 _pad-pr-len +!
                        _PAD-PR-REDRAW
                    ELSE DROP THEN
                ELSE DROP THEN
            THEN
        THEN
    AGAIN ;

\ ============================================================
\  §14 — Action Handlers
\ ============================================================

: _PAD-ACT-QUIT  ( -- )
    \ Check for any unsaved dedicated (non-inspection) tabs
    _pad-slot-count @ 0 ?DO
        I _PAD-SLOT-FLAGS@
        DUP _PAD-F-DIRTY AND
        SWAP _PAD-F-INSPECT AND 0= AND IF
            S" Unsaved changes exist. Quit?" DLG-CONFIRM IF
                -1 _pad-quit !
            THEN
            UNLOOP EXIT
        THEN
    LOOP
    -1 _pad-quit ! ;

: _PAD-ACT-SAVE  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    DUP _PAD-SLOT-FNAMEA@ NIP 0= IF
        \ No filename — prompt for one
        S" Save as: " _PAD-PROMPT
        DUP 0= IF 2DROP DROP _PAD-AFTER-PROMPT EXIT THEN
        63 MIN
        \ Copy to slot filename buffer
        2DUP 2 PICK _PAD-SLOT-FNAMEBUF SWAP CMOVE
        OVER _PAD-SLOT _PAD-S-FNAMEU + !
        OVER _PAD-SLOT-FNAMEBUF
        OVER _PAD-SLOT _PAD-S-FNAMEA + !
        DROP
        \ Create VFS file for the new name
        DUP _PAD-SLOT-FNAMEA@
        _pad-vfs @ VFS-MKFILE
        DUP 0= IF
            DROP S" Create FAILED" 2000 TST-SHOW
            _PAD-AFTER-PROMPT EXIT
        THEN
        OVER _PAD-SLOT _PAD-S-INODE + !
    THEN
    DUP _PAD-DO-SAVE IF
        S" Save FAILED" 2000 TST-SHOW
    ELSE
        S" Saved." 1500 TST-SHOW
        DUP _PAD-CLEAR-DIRTY
        DUP _PAD-UPDATE-TAB-LABEL
    THEN
    DROP
    _PAD-UPDATE-MSG
    _PAD-UPDATE-TITLE
    _PAD-AFTER-PROMPT ;

: _PAD-ACT-SAVE-AS  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    S" Save as: " _PAD-PROMPT
    DUP 0= IF 2DROP DROP _PAD-AFTER-PROMPT EXIT THEN
    63 MIN
    2DUP 2 PICK _PAD-SLOT-FNAMEBUF SWAP CMOVE
    OVER _PAD-SLOT _PAD-S-FNAMEU + !
    OVER _PAD-SLOT-FNAMEBUF
    OVER _PAD-SLOT _PAD-S-FNAMEA + !
    DROP
    \ Create VFS file
    DUP _PAD-SLOT-FNAMEA@
    _pad-vfs @ VFS-MKFILE
    DUP 0= IF
        DROP S" Create FAILED" 2000 TST-SHOW
        _PAD-AFTER-PROMPT EXIT
    THEN
    OVER _PAD-SLOT _PAD-S-INODE + !
    DUP _PAD-DO-SAVE IF
        S" Save FAILED" 2000 TST-SHOW
    ELSE
        S" Saved." 1500 TST-SHOW
        DUP _PAD-CLEAR-DIRTY
        DUP _PAD-UPDATE-TAB-LABEL
    THEN
    DROP
    _PAD-UPDATE-MSG
    _PAD-UPDATE-TITLE
    _PAD-AFTER-PROMPT ;

: _PAD-ACT-OPEN  ( -- )
    S" Open: " _PAD-PROMPT
    DUP 0= IF 2DROP _PAD-AFTER-PROMPT EXIT THEN
    \ Try to resolve the path in VFS
    2DUP VFS-OPEN DUP 0= IF
        DROP 2DROP
        S" File not found" 2000 TST-SHOW
        _PAD-AFTER-PROMPT EXIT
    THEN
    \ Get inode from FD
    DUP FD.INODE @                    ( addr len fd inode )
    SWAP VFS-CLOSE                    ( addr len inode )
    NIP NIP                           ( inode )
    _PAD-OPEN-FILE
    _PAD-AFTER-PROMPT ;

: _PAD-ACT-COPY  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    _PAD-SLOT-TXTA@
    TXTA-GET-SEL
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP ;

: _PAD-ACT-CUT  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    _PAD-SLOT-TXTA@ DUP >R
    TXTA-GET-SEL
    DUP 0= IF 2DROP R> DROP EXIT THEN
    CLIP-COPY DROP
    R> TXTA-DEL-SEL DROP ;

: _PAD-ACT-PASTE  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    _PAD-SLOT-TXTA@
    CLIP-PASTE
    DUP 0= IF 2DROP DROP EXIT THEN
    ROT TXTA-INS-STR ;

: _PAD-ACT-SEL-ALL  ( -- )
    _PAD-ACTIVE-SLOT DUP 0< IF DROP EXIT THEN
    _PAD-SLOT-TXTA@ TXTA-SELECT-ALL ;

: _PAD-ACT-CLOSE-TAB  ( -- )
    _PAD-CLOSE-TAB ;

: _PAD-ACT-NEXT-TAB  ( -- )
    _pad-tab-w @ 0= IF EXIT THEN
    _pad-tab-w @ TAB-COUNT 0= IF EXIT THEN
    _pad-tab-w @ TAB-ACTIVE 1+
    DUP _pad-tab-w @ TAB-COUNT >= IF DROP 0 THEN
    _pad-tab-w @ TAB-SELECT
    _pad-tab-w @ WDG-DIRTY
    _PAD-UPDATE-TITLE _PAD-UPDATE-MSG ;

: _PAD-ACT-PREV-TAB  ( -- )
    _pad-tab-w @ 0= IF EXIT THEN
    _pad-tab-w @ TAB-COUNT 0= IF EXIT THEN
    _pad-tab-w @ TAB-ACTIVE
    DUP 0= IF DROP _pad-tab-w @ TAB-COUNT 1- ELSE 1- THEN
    _pad-tab-w @ TAB-SELECT
    _pad-tab-w @ WDG-DIRTY
    _PAD-UPDATE-TITLE _PAD-UPDATE-MSG ;

: _PAD-ACT-TOGGLE-SB  ( -- )
    _pad-sb-visible @ IF
        \ Hide sidebar: set split ratio to 0
        S" main-split" UTUI-BY-ID ?DUP IF
            S" ratio" S" 0" UIDL-SET-ATTR
        THEN
        0 _pad-sb-visible !
        0 _pad-focus !
    ELSE
        \ Show sidebar: restore split ratio to 20
        S" main-split" UTUI-BY-ID ?DUP IF
            S" ratio" S" 20" UIDL-SET-ATTR
        THEN
        -1 _pad-sb-visible !
    THEN
    UTUI-RELAYOUT
    UTUI-PAINT
    \ Force redraw all manual widgets after relayout
    _pad-expl-w @ ?DUP IF DUP WDG-DIRTY WDG-DRAW THEN
    _pad-tab-w @ ?DUP IF DUP WDG-DIRTY WDG-DRAW THEN
    _PAD-ACTIVE-SLOT DUP 0>= IF
        _PAD-SLOT-TXTA@ ?DUP IF DUP WDG-DIRTY WDG-DRAW THEN
    ELSE DROP THEN
    SCR-FLUSH ;

: _PAD-ACT-FOCUS-SWAP  ( -- )
    _pad-focus @ IF
        0 _pad-focus !
    ELSE
        _pad-sb-visible @ IF 1 ELSE 0 THEN _pad-focus !
    THEN ;

\ ============================================================
\  §15 — Key Dispatch (panel routing)
\ ============================================================

: _PAD-DISPATCH-PANEL  ( ev -- consumed? )
    _pad-focus @ IF
        \ Explorer has focus
        _pad-expl-w @ 0= IF DROP 0 EXIT THEN
        _pad-expl-w @ WDG-HANDLE
    ELSE
        \ Editor has focus — route to active tab's textarea
        _PAD-ACTIVE-SLOT DUP 0< IF DROP DROP 0 EXIT THEN
        _PAD-SLOT-TXTA@ DUP 0= IF DROP DROP 0 EXIT THEN
        WDG-HANDLE
    THEN ;

\ ============================================================
\  §16 — Draw Helpers
\ ============================================================

: _PAD-DRAW-WIDGETS  ( -- )
    \ Draw explorer if dirty
    _pad-expl-w @ ?DUP IF
        DUP WDG-DIRTY? IF WDG-DRAW ELSE DROP THEN
    THEN
    \ Draw tab widget if dirty
    _pad-tab-w @ ?DUP IF
        DUP WDG-DIRTY? IF WDG-DRAW ELSE DROP THEN
    THEN
    \ Draw active tab's textarea if dirty
    _PAD-ACTIVE-SLOT DUP 0>= IF
        _PAD-SLOT-TXTA@ ?DUP IF
            DUP WDG-DIRTY? IF WDG-DRAW ELSE DROP THEN
        THEN
    ELSE DROP THEN ;

\ ============================================================
\  §17 — VFS Initialization
\ ============================================================

: _PAD-VFS-INIT  ( -- )
    524288 A-XMEM ARENA-NEW IF
        ." [pad] VFS arena alloc failed" CR EXIT
    THEN
    _pad-arena !
    _pad-arena @ VFS-RAM-VTABLE VFS-NEW
    DUP _pad-vfs !
    VFS-USE
    \ Create a sample welcome file so explorer has content
    S" welcome.txt" _pad-vfs @ VFS-MKFILE DROP ;

\ ============================================================
\  §18 — Init: APP-INIT, UTUI-LOAD, create widgets, register
\ ============================================================

: PAD-INIT  ( w h -- )
    APP-INIT

    \ Create root region from screen dimensions
    0 0 SCR-H SCR-W RGN-NEW _pad-rgn !

    \ Parse UIDL and layout
    _pad-xml _pad-xml-len @ _pad-rgn @ UTUI-LOAD
    0= IF
        APP-SHUTDOWN
        ." [pad] ERROR: UTUI-LOAD failed." CR
        EXIT
    THEN

    \ Resolve UIDL element pointers
    S" titlebar"    UTUI-BY-ID _pad-titlebar-elem !
    S" st-msg"      UTUI-BY-ID _pad-stmsg-elem !
    S" st-pos"      UTUI-BY-ID _pad-stpos-elem !
    S" sidebar"     UTUI-BY-ID _pad-sidebar-elem !
    S" sb-tree"     UTUI-BY-ID _pad-sbtree-elem !
    S" editor-area" UTUI-BY-ID _pad-edarea-elem !

    \ Initialize VFS (ramdisk)
    _PAD-VFS-INIT

    \ Create explorer in sidebar tree sub-region
    _pad-sbtree-elem @ _PAD-ELEM-RGN
    _pad-vfs @
    _pad-vfs @ V.ROOT @
    EXPL-NEW _pad-expl-w !

    \ Wire explorer callbacks
    ['] _PAD-ON-EXPL-OPEN  _pad-expl-w @ EXPL-ON-OPEN
    ['] _PAD-ON-EXPL-SELECT _pad-expl-w @ EXPL-ON-SELECT

    \ Create tab widget in editor-area region
    _pad-edarea-elem @ _PAD-ELEM-RGN
    TAB-NEW _pad-tab-w !

    \ Register action handlers (must be AFTER UTUI-LOAD)
    S" quit"       ['] _PAD-ACT-QUIT       UTUI-DO!
    S" save"       ['] _PAD-ACT-SAVE       UTUI-DO!
    S" save-as"    ['] _PAD-ACT-SAVE-AS    UTUI-DO!
    S" open"       ['] _PAD-ACT-OPEN       UTUI-DO!
    S" copy"       ['] _PAD-ACT-COPY       UTUI-DO!
    S" cut"        ['] _PAD-ACT-CUT        UTUI-DO!
    S" paste"      ['] _PAD-ACT-PASTE      UTUI-DO!
    S" sel-all"    ['] _PAD-ACT-SEL-ALL    UTUI-DO!
    S" close-tab"  ['] _PAD-ACT-CLOSE-TAB  UTUI-DO!
    S" next-tab"   ['] _PAD-ACT-NEXT-TAB   UTUI-DO!
    S" prev-tab"   ['] _PAD-ACT-PREV-TAB   UTUI-DO!
    S" toggle-sb"  ['] _PAD-ACT-TOGGLE-SB  UTUI-DO!
    S" focus-swap" ['] _PAD-ACT-FOCUS-SWAP UTUI-DO!

    \ Configure toast position & style (white on dark green)
    SCR-H 3 - SCR-W 30 - TST-POSITION!
    15 22 BOX-ROUND TST-STYLE!

    \ Initialize state
    0 _pad-quit !
    0 _pad-slot-count !
    -1 _pad-inspection !
    0 _pad-focus !
    -1 _pad-sb-visible !
    0 _pad-last-open-inode !
    _pad-slots _PAD-MAX-TABS _PAD-SLOT-SZ * 0 FILL
    _pad-bufs  _PAD-MAX-TABS _PAD-BUF-SZ * 0 FILL ;

\ ============================================================
\  §19 — Event Loop
\ ============================================================

: PAD-RUN  ( -- )
    0 0 PAD-INIT

    1 KEY-TIMEOUT!

    \ Initial paint (materializes UIDL widgets)
    UTUI-PAINT

    \ Draw manually-created widgets
    _pad-expl-w @ DUP WDG-DIRTY WDG-DRAW
    _pad-tab-w  @ DUP WDG-DIRTY WDG-DRAW
    RGN-ROOT                           \ restore full-screen clip
    SCR-FLUSH

    \ Initial status updates
    _PAD-UPDATE-POS
    _PAD-UPDATE-TITLE
    _PAD-UPDATE-MSG
    UTUI-PAINT SCR-FLUSH

    \ Drain any stale bytes from terminal init
    BEGIN KEY? WHILE KEY DROP REPEAT

    BEGIN
        _pad-ev KEY-READ DROP

        \ 1. Try UTUI-DISPATCH-KEY (shortcuts → actions)
        _pad-ev UTUI-DISPATCH-KEY 0= IF
            \ 2. If not consumed, route to focused panel
            _pad-ev _PAD-DISPATCH-PANEL DROP
        THEN

        \ 3. Update status bar
        _PAD-UPDATE-POS

        \ 4. Paint UIDL elements (title, status labels)
        UTUI-PAINT

        \ 5. Paint manually-created widgets
        _PAD-DRAW-WIDGETS
        RGN-ROOT                       \ restore full-screen clip for toast

        \ 6. Toast overlay
        TST-TICK
        TST-VISIBLE? IF TST-DRAW THEN

        \ 7. Flush to screen
        SCR-FLUSH

        _pad-quit @
    UNTIL

    \ Cleanup
    _PAD-CLOSE-ALL
    UTUI-DETACH
    APP-SHUTDOWN
    ." [pad] Akashic Pad exited." CR ;

PAD-RUN
