\ akashic-pad-v2.f — Akashic Pad v2 (UIDL + CSS styling)
\ ============================================================
\
\ Phase 1 implementation:
\   - UIDL-TUI with CSS style= attributes for all colours
\   - APP-INIT / APP-SHUTDOWN for terminal lifecycle
\   - Purple title bar showing filename + dirty indicator
\   - Textarea editor (dark background, light text)
\   - Styled status bar (position, message, mode indicators)
\   - Declarative <action key=… do=…/> for all shortcuts
\   - Toast notifications for save/open feedback
\   - File I/O (Ctrl+S / Ctrl+Shift+S / Ctrl+O)
\   - Clipboard (Ctrl+C / Ctrl+X / Ctrl+V / Ctrl+A)
\   - Modal file-name prompt on status row
\ ============================================================

REQUIRE tui/uidl-tui.f
REQUIRE tui/app.f
REQUIRE tui/widgets/toast.f
REQUIRE utils/clipboard.f

\ ============================================================
\  §1 — UIDL Document (built in a static buffer)
\ ============================================================

CREATE _p2-xml 1024 ALLOT
VARIABLE _p2-xml-len

: _p2x  ( c-addr u -- )
    _p2-xml _p2-xml-len @ +
    SWAP DUP >R CMOVE
    R> _p2-xml-len +! ;

0 _p2-xml-len !

\ Root group — auto-sizes to region (which comes from SCR-W × SCR-H)
\ NOTE: hex colour codes in style= crash _UTUI-RESOLVE-STYLES (Bug 7).
\ We use named colours as a workaround.
S" <uidl><group id='root'>" _p2x

\ Title bar — bold white on purple
S" <label id='titlebar' text=' Akashic Pad '" _p2x
S"  style='color:white; background-color:purple; font-weight:bold'/>" _p2x

\ Editor textarea — khaki on black
S" <textarea id='editor'" _p2x
S"  style='color:khaki; background-color:black'/>" _p2x

\ Status bar — white on teal, children split equally
S" <status style='background-color:teal'>" _p2x
S" <label id='st-msg' text='Ready'" _p2x
S"  style='color:white; background-color:teal'/>" _p2x
S" <label id='st-pos' text='Ln 1, Col 1'" _p2x
S"  style='color:cyan; background-color:teal'/>" _p2x
S" <label id='st-mode' text='INSERT'" _p2x
S"  style='color:yellow; background-color:teal'/>" _p2x
S" </status>" _p2x

\ Keyboard shortcuts (declarative actions)
S" <action id='k-quit'   do='quit'    key='Ctrl+Q'/>" _p2x
S" <action id='k-save'   do='save'    key='Ctrl+S'/>" _p2x
S" <action id='k-saveas' do='save-as' key='Ctrl+Shift+S'/>" _p2x
S" <action id='k-open'   do='open'    key='Ctrl+O'/>" _p2x
S" <action id='k-copy'   do='copy'    key='Ctrl+C'/>" _p2x
S" <action id='k-cut'    do='cut'     key='Ctrl+X'/>" _p2x
S" <action id='k-paste'  do='paste'   key='Ctrl+V'/>" _p2x
S" <action id='k-selall' do='sel-all' key='Ctrl+A'/>" _p2x

S" </group></uidl>" _p2x

\ ============================================================
\  §2 — Pad state
\ ============================================================

VARIABLE _p2-quit              \ quit-requested flag

VARIABLE _p2-editor-w          \ textarea widget pointer
VARIABLE _p2-editor-elem       \ editor UIDL element

VARIABLE _p2-titlebar-elem     \ titlebar element
VARIABLE _p2-titlebar-attr     \ titlebar 'text' attr node

VARIABLE _p2-stmsg-elem       \ st-msg UIDL element
VARIABLE _p2-stmsg-attr       \ st-msg 'text' attr node
VARIABLE _p2-stpos-elem       \ st-pos UIDL element
VARIABLE _p2-stpos-attr       \ st-pos 'text' attr node

VARIABLE _p2-dirty             \ buffer modified flag

\ Current filename
CREATE _p2-fname 24 ALLOT
VARIABLE _p2-fname-len
0 _p2-fname-len !

: _P2-HAS-FNAME?  ( -- flag )  _p2-fname-len @ 0> ;

\ Scratch buffers
CREATE _p2-pos-buf 32 ALLOT
VARIABLE _p2-pos-len

CREATE _p2-msg-buf 48 ALLOT
VARIABLE _p2-msg-len

CREATE _p2-title-buf 64 ALLOT
VARIABLE _p2-title-len

CREATE _p2-ev 24 ALLOT        \ key event buffer
CREATE _p2-iobuf 4096 ALLOT   \ file I/O scratch

VARIABLE _p2-rgn               \ screen region

\ ============================================================
\  §3 — Attr helpers (find 'text' attr, poke value)
\ ============================================================

: _p2-find-text-attr  ( elem -- attr-node | 0 )
    UIDL-ATTR-FIRST
    BEGIN DUP 0<> WHILE
        DUP UIDL-ATTR-NAME S" text" STR-STR= IF EXIT THEN
        UIDL-ATTR-NEXT
    REPEAT ;

\ Poke a string into an attr node's value (addr @ +24, len @ +32)
: _P2-ATTR-POKE!  ( buf len attr -- )
    DUP >R 32 + !  R> 24 + ! ;

\ ============================================================
\  §4 — Title bar
\ ============================================================

: _P2-TITLE-APPEND  ( addr u -- )
    _p2-title-buf _p2-title-len @ +
    SWAP DUP >R CMOVE
    R> _p2-title-len +! ;

: _P2-UPDATE-TITLE  ( -- )
    _p2-titlebar-attr @ 0= IF EXIT THEN
    0 _p2-title-len !
    S"  Akashic Pad" _P2-TITLE-APPEND
    _P2-HAS-FNAME? IF
        S"  - " _P2-TITLE-APPEND
        _p2-fname _p2-fname-len @ _P2-TITLE-APPEND
        _p2-dirty @ IF S"  *" _P2-TITLE-APPEND THEN
    THEN
    S"  " _P2-TITLE-APPEND
    _p2-title-buf _p2-title-len @ _p2-titlebar-attr @ _P2-ATTR-POKE!
    _p2-titlebar-elem @ UIDL-DIRTY! ;

\ ============================================================
\  §5 — Status bar updates
\ ============================================================

: _P2-POS-APPEND  ( addr u -- )
    _p2-pos-buf _p2-pos-len @ +
    SWAP DUP >R CMOVE
    R> _p2-pos-len +! ;

: _P2-UPDATE-POS  ( -- )
    _p2-editor-w @ 0= IF EXIT THEN
    0 _p2-pos-len !
    S" Ln " _P2-POS-APPEND
    _p2-editor-w @ TXTA-CURSOR-LINE 1+ NUM>STR _P2-POS-APPEND
    S" , Col " _P2-POS-APPEND
    _p2-editor-w @ TXTA-CURSOR-COL 1+ NUM>STR _P2-POS-APPEND
    _p2-pos-buf _p2-pos-len @ _p2-stpos-attr @ _P2-ATTR-POKE!
    _p2-stpos-elem @ UIDL-DIRTY! ;

: _P2-MSG-APPEND  ( addr u -- )
    _p2-msg-buf _p2-msg-len @ +
    SWAP DUP >R CMOVE
    R> _p2-msg-len +! ;

: _P2-UPDATE-MSG  ( -- )
    0 _p2-msg-len !
    _P2-HAS-FNAME? IF
        _p2-fname _p2-fname-len @
        _p2-msg-buf SWAP DUP >R CMOVE R> _p2-msg-len !
        _p2-dirty @ IF
            32 _p2-msg-buf _p2-msg-len @ + C!  1 _p2-msg-len +!
            42 _p2-msg-buf _p2-msg-len @ + C!  1 _p2-msg-len +!
        THEN
    ELSE
        _p2-dirty @ IF
            S" Modified" _p2-msg-buf SWAP DUP >R CMOVE R> _p2-msg-len !
        ELSE
            S" Ready" _p2-msg-buf SWAP DUP >R CMOVE R> _p2-msg-len !
        THEN
    THEN
    _p2-msg-buf _p2-msg-len @ _p2-stmsg-attr @ _P2-ATTR-POKE!
    _p2-stmsg-elem @ UIDL-DIRTY! ;

\ ============================================================
\  §6 — On-change callback (dirty tracking)
\ ============================================================

: _P2-ON-CHANGE  ( widget -- )
    DROP
    _p2-dirty @ IF EXIT THEN
    -1 _p2-dirty !
    _P2-UPDATE-MSG
    _P2-UPDATE-TITLE ;

\ ============================================================
\  §7 — File I/O helpers
\ ============================================================

: _P2-NAME!  ( addr len -- )
    NAMEBUF 24 0 FILL
    23 MIN NAMEBUF SWAP CMOVE ;

8 CONSTANT _P2-FSECTORS

: _P2-FOPEN  ( -- fdesc | 0 )
    FS-ENSURE
    FS-OK @ 0= IF 0 EXIT THEN
    FIND-BY-NAME DUP -1 = IF DROP 0 EXIT THEN
    >R FD-ALLOC DUP 0= IF R> DROP EXIT THEN
    DUP R> FD-FILL ;

VARIABLE _P2FC-SLOT
VARIABLE _P2FC-START

: _P2-FCREATE  ( -- fdesc | 0 )
    FS-ENSURE
    FS-OK @ 0= IF 0 EXIT THEN
    FIND-BY-NAME -1 <> IF 0 EXIT THEN
    FIND-FREE-SLOT _P2FC-SLOT !
    _P2FC-SLOT @ -1 = IF 0 EXIT THEN
    _P2-FSECTORS FIND-FREE _P2FC-START !
    _P2FC-START @ -1 = IF 0 EXIT THEN
    _P2-FSECTORS 0 DO _P2FC-START @ I + BIT-SET LOOP
    _P2FC-SLOT @ DIRENT
    DUP FS-ENTRY-SIZE 0 FILL
    DUP NAMEBUF SWAP 24 CMOVE
    DUP _P2FC-START @ SWAP 24 + W!
    DUP _P2-FSECTORS  SWAP 26 + W!
    DUP 0              SWAP 28 + L!
    DUP 2              SWAP 32 + C!
    DUP CWD @          SWAP 34 + C!
    DUP TICKS@         SWAP 36 + L!
    DROP
    FS-SYNC
    FD-ALLOC DUP 0= IF EXIT THEN
    DUP _P2FC-SLOT @ FD-FILL ;

VARIABLE _P2S-FD

: _P2-DO-SAVE  ( -- ior )
    _p2-fname _p2-fname-len @ _P2-NAME!
    _P2-FOPEN DUP 0= IF
        _p2-fname _p2-fname-len @ _P2-NAME!
        _P2-FCREATE DUP 0= IF -1 EXIT THEN
    THEN
    _P2S-FD !
    0 _P2S-FD @ FTRUNCATE
    _p2-editor-w @ TXTA-GET-TEXT
    DUP >R
    _P2S-FD @ FWRITE
    R> _P2S-FD @ FTRUNCATE
    _P2S-FD @ FCLOSE
    0 ;

VARIABLE _P2O-FD

: _P2-DO-OPEN  ( -- ior )
    _p2-fname _p2-fname-len @ _P2-NAME!
    _P2-FOPEN DUP 0= IF -1 EXIT THEN
    _P2O-FD !
    _P2O-FD @ FREWIND
    _p2-iobuf 4096 _P2O-FD @ FREAD
    _p2-iobuf SWAP
    _p2-editor-w @ TXTA-SET-TEXT
    _P2O-FD @ FCLOSE
    0 ;

\ ============================================================
\  §8 — Status-bar prompt (modal)
\ ============================================================

: _P2-DIRTY-STATUS  ( -- )
    _p2-stmsg-elem @ ?DUP IF
        DUP UIDL-PARENT ?DUP IF
            DUP UIDL-DIRTY!
            UIDL-FIRST-CHILD
            BEGIN DUP 0<> WHILE
                DUP UIDL-DIRTY!
                UIDL-NEXT-SIB
            REPEAT DROP
        ELSE UIDL-DIRTY! THEN
    THEN ;

: _P2-AFTER-PROMPT  ( -- )
    _P2-DIRTY-STATUS
    _p2-editor-elem @ ?DUP IF UIDL-DIRTY! THEN
    UTUI-PAINT SCR-FLUSH ;

CREATE _p2-prompt-buf 64 ALLOT
VARIABLE _p2-prompt-len
VARIABLE _p2-pr-a
VARIABLE _p2-pr-u

: _P2-PR-REDRAW  ( -- )
    RGN-ROOT  DRW-STYLE-RESET
    SCR-H 1- 0 1 SCR-W DRW-CLEAR-RECT
    _p2-pr-a @ _p2-pr-u @  SCR-H 1-  0  DRW-TEXT
    _p2-prompt-buf _p2-prompt-len @  SCR-H 1-  _p2-pr-u @  DRW-TEXT
    SCR-FLUSH ;

: _P2-PROMPT  ( label-a label-u -- addr len | 0 0 )
    _p2-pr-u !  _p2-pr-a !
    0 _p2-prompt-len !
    _P2-PR-REDRAW
    BEGIN
        _p2-ev KEY-READ DROP
        _p2-ev @ KEY-T-SPECIAL = IF
            _p2-ev 8 + @
            DUP KEY-ENTER = IF
                DROP _P2-AFTER-PROMPT
                _p2-prompt-buf _p2-prompt-len @ EXIT
            THEN
            DUP KEY-ESC = IF
                DROP _P2-AFTER-PROMPT
                0 0 EXIT
            THEN
            DUP KEY-BACKSPACE = IF
                DROP
                _p2-prompt-len @ 0> IF
                    -1 _p2-prompt-len +!
                    _P2-PR-REDRAW
                THEN
            ELSE DROP THEN
        ELSE
            _p2-ev @ KEY-T-CHAR = IF
                _p2-ev 8 + @
                DUP 32 >= OVER 127 < AND IF
                    _p2-prompt-len @ 60 < IF
                        _p2-prompt-buf _p2-prompt-len @ + C!
                        1 _p2-prompt-len +!
                        _P2-PR-REDRAW
                    ELSE DROP THEN
                ELSE DROP THEN
            THEN
        THEN
    AGAIN ;

\ ============================================================
\  §9 — Action handlers
\ ============================================================

: _P2-SHOW-FNAME  ( -- )
    0 _p2-dirty !
    _P2-UPDATE-MSG
    _P2-UPDATE-TITLE ;

: _P2-ACT-QUIT  ( -- )
    -1 _p2-quit ! ;

: _P2-ACT-SAVE  ( -- )
    _P2-HAS-FNAME? 0= IF
        S" Save as: " _P2-PROMPT
        DUP 0= IF 2DROP EXIT THEN
        23 MIN  2DUP _p2-fname SWAP CMOVE  _p2-fname-len !  DROP
    THEN
    _P2-DO-SAVE IF
        S" Save FAILED" 2000 TST-SHOW
    ELSE
        S" Saved." 1500 TST-SHOW
        _P2-SHOW-FNAME
    THEN
    _P2-AFTER-PROMPT ;

: _P2-ACT-SAVE-AS  ( -- )
    S" Save as: " _P2-PROMPT
    DUP 0= IF 2DROP EXIT THEN
    23 MIN  2DUP _p2-fname SWAP CMOVE  _p2-fname-len !  DROP
    _P2-DO-SAVE IF
        S" Save FAILED" 2000 TST-SHOW
    ELSE
        S" Saved." 1500 TST-SHOW
        _P2-SHOW-FNAME
    THEN
    _P2-AFTER-PROMPT ;

: _P2-ACT-OPEN  ( -- )
    S" Open: " _P2-PROMPT
    DUP 0= IF 2DROP EXIT THEN
    23 MIN  2DUP _p2-fname SWAP CMOVE  _p2-fname-len !  DROP
    _P2-DO-OPEN IF
        0 _p2-fname-len !
        S" Open FAILED" 2000 TST-SHOW
    ELSE
        _P2-SHOW-FNAME
    THEN
    _P2-AFTER-PROMPT ;

: _P2-ACT-COPY  ( -- )
    _p2-editor-w @ TXTA-GET-SEL
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP ;

: _P2-ACT-CUT  ( -- )
    _p2-editor-w @ TXTA-GET-SEL
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP
    _p2-editor-w @ TXTA-DEL-SEL DROP
    _p2-editor-elem @ UIDL-DIRTY! ;

: _P2-ACT-PASTE  ( -- )
    CLIP-PASTE
    DUP 0= IF 2DROP EXIT THEN
    _p2-editor-w @ TXTA-INS-STR
    _p2-editor-elem @ UIDL-DIRTY! ;

: _P2-ACT-SEL-ALL  ( -- )
    _p2-editor-w @ TXTA-SELECT-ALL
    _p2-editor-elem @ UIDL-DIRTY! ;

\ ============================================================
\  §10 — Init: APP-INIT, UTUI-LOAD, register actions
\ ============================================================
\
\  PAD-V2-INIT ( w h -- )
\    Initialise the pad with explicit dimensions.
\    Pass 0 0 for auto-detect from terminal.

: PAD-V2-INIT  ( w h -- )
    APP-INIT

    0 0 SCR-H SCR-W RGN-NEW _p2-rgn !

    _p2-xml _p2-xml-len @ _p2-rgn @ UTUI-LOAD
    0= IF
        APP-SHUTDOWN
        ." [pad-v2] ERROR: UTUI-LOAD failed." CR
        EXIT
    THEN

    \ Register actions (must be AFTER UTUI-LOAD which clears table)
    S" quit"    ' _P2-ACT-QUIT    UTUI-DO!
    S" save"    ' _P2-ACT-SAVE    UTUI-DO!
    S" save-as" ' _P2-ACT-SAVE-AS UTUI-DO!
    S" open"    ' _P2-ACT-OPEN    UTUI-DO!
    S" copy"    ' _P2-ACT-COPY    UTUI-DO!
    S" cut"     ' _P2-ACT-CUT     UTUI-DO!
    S" paste"   ' _P2-ACT-PASTE   UTUI-DO!
    S" sel-all" ' _P2-ACT-SEL-ALL UTUI-DO!

    \ Configure toast position & style (white on dark green)
    SCR-H 3 - SCR-W 30 - TST-POSITION!
    15 22 BOX-ROUND TST-STYLE! ;

\ ============================================================
\  §11 — Resolve cached pointers (after first paint)
\ ============================================================

: _P2-INIT-PTRS  ( -- )
    S" editor" UTUI-BY-ID DUP 0= ABORT" [pad-v2] editor not found"
    DUP _p2-editor-elem !
    UTUI-WIDGET@ DUP 0= ABORT" [pad-v2] editor widget not found"
    _p2-editor-w !

    S" titlebar" UTUI-BY-ID DUP 0= ABORT" [pad-v2] titlebar not found"
    DUP _p2-titlebar-elem !
    _p2-find-text-attr DUP 0= ABORT" [pad-v2] titlebar text attr not found"
    _p2-titlebar-attr !

    S" st-msg" UTUI-BY-ID DUP 0= ABORT" [pad-v2] st-msg not found"
    DUP _p2-stmsg-elem !
    _p2-find-text-attr DUP 0= ABORT" [pad-v2] st-msg text attr not found"
    _p2-stmsg-attr !

    S" st-pos" UTUI-BY-ID DUP 0= ABORT" [pad-v2] st-pos not found"
    DUP _p2-stpos-elem !
    _p2-find-text-attr DUP 0= ABORT" [pad-v2] st-pos text attr not found"
    _p2-stpos-attr !

    0 _p2-dirty ! ;

\ ============================================================
\  §12 — Event loop
\ ============================================================

: PAD-V2-RUN  ( -- )
    0 0 PAD-V2-INIT

    0 _p2-quit !
    1 KEY-TIMEOUT!

    \ Initial paint (materialises widgets)
    UTUI-PAINT SCR-FLUSH

    \ Now resolve pointers to materialised widgets
    _P2-INIT-PTRS
    ['] _P2-ON-CHANGE _p2-editor-w @ TXTA-ON-CHANGE
    _P2-UPDATE-POS
    _P2-UPDATE-TITLE
    UTUI-PAINT SCR-FLUSH

    BEGIN
        _p2-ev KEY-READ DROP
        _p2-ev UTUI-DISPATCH-KEY DROP
        _P2-UPDATE-POS
        UTUI-PAINT
        TST-TICK
        TST-VISIBLE? IF TST-DRAW THEN
        SCR-FLUSH
        _p2-quit @
    UNTIL

    UTUI-DETACH
    APP-SHUTDOWN
    ." [pad-v2] Akashic Pad exited." CR ;

PAD-V2-RUN
