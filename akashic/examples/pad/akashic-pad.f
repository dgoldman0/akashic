\ akashic-pad.f — Akashic Pad editor (Phase 1 MVP + file I/O)
\ ============================================================
\ Loaded by autoexec.f via LOAD akashic-pad.f
\
\ Phase 1: Minimal editing loop
\   - Textarea fills most of the screen (rows 0–22)
\   - Status bar at bottom row (filename | Ln/Col | INSERT)
\   - Ctrl+S save, Ctrl+Shift+S save-as, Ctrl+O open
\   - Ctrl+C/X/V clipboard, Ctrl+A select-all
\   - Ctrl+Q to quit
\ ============================================================

REQUIRE tui/uidl-tui.f
REQUIRE utils/clipboard.f

\ ============================================================
\  §1 — UIDL Document (built in a static buffer)
\ ============================================================
\ We assemble the XML string piece-by-piece to avoid hitting
\ potential S" length limits.

CREATE _pad-xml 512 ALLOT
VARIABLE _pad-xml-len

: _px  ( c-addr u -- )
    _pad-xml _pad-xml-len @ +
    SWAP DUP >R CMOVE
    R> _pad-xml-len +! ;

0 _pad-xml-len !
S" <uidl cols='80' rows='24'>" _px
S" <textarea id='editor'/>" _px
S" <status>" _px
S" <label id='st-msg' text='Ready'/>" _px
S" <label id='st-pos' text='Ln 1, Col 1'/>" _px
S" <label id='st-mode' text='INSERT'/>" _px
S" </status>" _px
S" <action id='k-quit' do='quit' key='Ctrl+Q'/>" _px
S" </uidl>" _px

\ ============================================================
\  §2 — Action Handlers
\ ============================================================

VARIABLE _pad-quit

: _PAD-ACT-QUIT  ( -- )
    -1 _pad-quit ! ;

\ Note: UTUI-DO! must be called AFTER UTUI-LOAD (which clears the
\ action table).  Moved to §4 below.

\ ============================================================
\  §3 — Screen + Region Setup
\ ============================================================

ANSI-CLEAR  ANSI-HOME  ANSI-CURSOR-OFF
80 24 SCR-NEW CONSTANT _pad-scr
_pad-scr SCR-USE
SCR-CLEAR

0 0 24 80 RGN-NEW CONSTANT _pad-rgn

\ ============================================================
\  §4 — Load the UIDL document
\ ============================================================

_pad-xml _pad-xml-len @ _pad-rgn UTUI-LOAD
0= IF
    ANSI-CURSOR-ON
    ." [pad] ERROR: Failed to load UIDL document." CR
    BYE
THEN

\ Register actions AFTER load (UTUI-LOAD clears the action table).
S" quit" ' _PAD-ACT-QUIT UTUI-DO!

\ ============================================================
\  §4a — Status bar Ln/Col plumbing
\ ============================================================
\ The textarea widget is materialized during the first UTUI-PAINT,
\ so we resolve pointers lazily inside PAD-RUN, not at load time.

VARIABLE _pad-editor-w     \ textarea widget pointer
VARIABLE _pad-editor-elem  \ editor UIDL element (for UIDL-DIRTY!)
VARIABLE _pad-stpos-elem   \ st-pos UIDL element
VARIABLE _pad-stpos-attr   \ st-pos 'text' attr node
VARIABLE _pad-stmsg-elem   \ st-msg UIDL element
VARIABLE _pad-stmsg-attr   \ st-msg 'text' attr node
VARIABLE _pad-dirty        \ buffer modified flag

\ -- Current filename state (here so _PAD-ON-CHANGE can use it) --
CREATE _pad-fname 24 ALLOT
VARIABLE _pad-fname-len
0 _pad-fname-len !

: _PAD-HAS-FNAME?  ( -- flag )  _pad-fname-len @ 0> ;

\ -- Message build buffer for st-msg label --
CREATE _pad-msg-buf 32 ALLOT
VARIABLE _pad-msg-len

\ Walk attrs of an element to find the 'text' attr node.
: _pad-find-text-attr  ( elem -- attr-node | 0 )
    UIDL-ATTR-FIRST
    BEGIN DUP 0<> WHILE
        DUP UIDL-ATTR-NAME S" text" STR-STR= IF EXIT THEN
        UIDL-ATTR-NEXT
    REPEAT ;

\ Format buffer — "Ln NNNNN, Col NNNNN" max 24 chars
CREATE _pad-pos-buf 24 ALLOT
VARIABLE _pad-pos-len

: _PAD-APPEND  ( a u -- )
    _pad-pos-buf _pad-pos-len @ +
    SWAP DUP >R CMOVE
    R> _pad-pos-len +! ;

\ _PAD-INIT-POS ( -- )  Resolve cached pointers (call after first paint).
: _PAD-INIT-POS  ( -- )
    S" editor" UTUI-BY-ID DUP 0= ABORT" [pad] editor not found"
    DUP _pad-editor-elem !
    UTUI-WIDGET@ DUP 0= ABORT" [pad] editor widget not found"
    _pad-editor-w !
    S" st-pos" UTUI-BY-ID DUP 0= ABORT" [pad] st-pos not found"
    DUP _pad-stpos-elem !
    _pad-find-text-attr DUP 0= ABORT" [pad] st-pos text attr not found"
    _pad-stpos-attr !
    S" st-msg" UTUI-BY-ID DUP 0= ABORT" [pad] st-msg not found"
    DUP _pad-stmsg-elem !
    _pad-find-text-attr DUP 0= ABORT" [pad] st-msg text attr not found"
    _pad-stmsg-attr !
    0 _pad-dirty ! ;

\ _PAD-UPDATE-POS ( -- )  Recompute "Ln N, Col M" and poke attr.
: _PAD-UPDATE-POS  ( -- )
    _pad-editor-w @ 0= IF EXIT THEN
    0 _pad-pos-len !
    S" Ln " _PAD-APPEND
    _pad-editor-w @ TXTA-CURSOR-LINE 1+ NUM>STR _PAD-APPEND
    S" , Col " _PAD-APPEND
    _pad-editor-w @ TXTA-CURSOR-COL 1+ NUM>STR _PAD-APPEND
    \ Poke the attr node value pointer + length
    _pad-pos-buf _pad-stpos-attr @ 24 + !   \ UA.VAL-A
    _pad-pos-len @ _pad-stpos-attr @ 32 + ! \ UA.VAL-L
    \ Mark the label dirty so it repaints
    _pad-stpos-elem @ UIDL-DIRTY! ;

\ _PAD-UPDATE-MSG ( -- )  Rebuild st-msg label from fname + dirty state.
\   Shows: "filename" | "filename *" | "Ready" | "Modified"
: _PAD-UPDATE-MSG  ( -- )
    0 _pad-msg-len !
    _PAD-HAS-FNAME? IF
        _pad-fname _pad-fname-len @
        _pad-msg-buf SWAP DUP >R CMOVE R> _pad-msg-len !
        _pad-dirty @ IF
            32 _pad-msg-buf _pad-msg-len @ + C!  1 _pad-msg-len +!
            42 _pad-msg-buf _pad-msg-len @ + C!  1 _pad-msg-len +!
        THEN
    ELSE
        _pad-dirty @ IF
            S" Modified" _pad-msg-buf SWAP DUP >R CMOVE R> _pad-msg-len !
        ELSE
            S" Ready" _pad-msg-buf SWAP DUP >R CMOVE R> _pad-msg-len !
        THEN
    THEN
    _pad-msg-buf _pad-stmsg-attr @ 24 + !
    _pad-msg-len @ _pad-stmsg-attr @ 32 + !
    _pad-stmsg-elem @ UIDL-DIRTY! ;

\ _PAD-ON-CHANGE ( widget -- )  Callback from textarea on any edit.
: _PAD-ON-CHANGE  ( widget -- )
    DROP
    _pad-dirty @ IF EXIT THEN          \ already dirty
    -1 _pad-dirty !
    _PAD-UPDATE-MSG ;

\ ============================================================
\  §4b — File I/O helpers
\ ============================================================
\
\  Stack-based file open/create that bypass PARSE-NAME.
\  Uses NAMEBUF + FIND-BY-NAME + FD-ALLOC + FD-FILL directly.

\ _PAD-NAME! ( addr len -- )  Populate NAMEBUF from stack.
: _PAD-NAME!  ( addr len -- )
    NAMEBUF 24 0 FILL
    23 MIN NAMEBUF SWAP CMOVE ;

8 CONSTANT _PAD-FSECTORS           \ 8 sectors = 4 KB

\ _PAD-FOPEN ( -- fdesc | 0 )  Open existing file (NAMEBUF must be set).
: _PAD-FOPEN  ( -- fdesc | 0 )
    FS-ENSURE
    FS-OK @ 0= IF 0 EXIT THEN
    FIND-BY-NAME DUP -1 = IF DROP 0 EXIT THEN
    >R FD-ALLOC DUP 0= IF R> DROP EXIT THEN
    DUP R> FD-FILL ;

\ _PAD-FCREATE ( -- fdesc | 0 )  Create new text file + open (NAMEBUF).
VARIABLE _PFC-SLOT
VARIABLE _PFC-START

: _PAD-FCREATE  ( -- fdesc | 0 )
    FS-ENSURE
    FS-OK @ 0= IF 0 EXIT THEN
    FIND-BY-NAME -1 <> IF 0 EXIT THEN   \ already exists
    FIND-FREE-SLOT _PFC-SLOT !
    _PFC-SLOT @ -1 = IF 0 EXIT THEN
    _PAD-FSECTORS FIND-FREE _PFC-START !
    _PFC-START @ -1 = IF 0 EXIT THEN
    _PAD-FSECTORS 0 DO _PFC-START @ I + BIT-SET LOOP
    _PFC-SLOT @ DIRENT
    DUP FS-ENTRY-SIZE 0 FILL
    DUP NAMEBUF SWAP 24 CMOVE           \ name
    DUP _PFC-START @ SWAP 24 + W!       \ start sector
    DUP _PAD-FSECTORS  SWAP 26 + W!     \ sector count
    DUP 0              SWAP 28 + L!     \ used_bytes = 0
    DUP 2              SWAP 32 + C!     \ type = text
    DUP CWD @          SWAP 34 + C!     \ parent = CWD
    DUP TICKS@         SWAP 36 + L!     \ mtime
    DROP
    FS-SYNC
    FD-ALLOC DUP 0= IF EXIT THEN
    DUP _PFC-SLOT @ FD-FILL ;

\ -- Scratch buffer for file reads --
CREATE _pad-iobuf 4096 ALLOT

\ _PAD-DO-SAVE ( -- ior )  Save textarea to current filename.
\   Returns 0 on success, -1 on error.
VARIABLE _PDS-FD

: _PAD-DO-SAVE  ( -- ior )
    _pad-fname _pad-fname-len @ _PAD-NAME!
    _PAD-FOPEN DUP 0= IF
        \ File doesn't exist → create
        _pad-fname _pad-fname-len @ _PAD-NAME!
        _PAD-FCREATE DUP 0= IF -1 EXIT THEN
    THEN
    _PDS-FD !
    0 _PDS-FD @ FTRUNCATE
    _pad-editor-w @ TXTA-GET-TEXT       ( addr len )
    DUP >R
    _PDS-FD @ FWRITE
    R> _PDS-FD @ FTRUNCATE              \ exact used_bytes
    _PDS-FD @ FCLOSE
    0 ;

\ _PAD-DO-OPEN ( -- ior )  Load file into textarea.
\   Returns 0 on success, -1 on error.
VARIABLE _PDO-FD

: _PAD-DO-OPEN  ( -- ior )
    _pad-fname _pad-fname-len @ _PAD-NAME!
    _PAD-FOPEN DUP 0= IF -1 EXIT THEN
    _PDO-FD !
    _PDO-FD @ FREWIND
    _pad-iobuf 4096 _PDO-FD @ FREAD    ( actual )
    _pad-iobuf SWAP
    _pad-editor-w @ TXTA-SET-TEXT
    _PDO-FD @ FCLOSE
    0 ;

\ ============================================================
\  §4c — Status-bar prompt
\ ============================================================
\
\  Modal mini-input on the status row.  Blocks in KEY-READ loop.
\  Returns typed text on Enter, 0 0 on Escape.

\ Mark the entire status bar dirty so UTUI-PAINT redraws it
\ after the prompt has overwritten row 23.
: _PAD-DIRTY-STATUS  ( -- )
    _pad-stmsg-elem @ ?DUP IF
        DUP UIDL-PARENT ?DUP IF        \ <status> container
            DUP UIDL-DIRTY!
            UIDL-FIRST-CHILD            \ walk children
            BEGIN DUP 0<> WHILE
                DUP UIDL-DIRTY!
                UIDL-NEXT-SIB
            REPEAT DROP
        ELSE UIDL-DIRTY! THEN
    THEN ;

CREATE _pad-ev 24 ALLOT             \ shared event buffer (used by prompt + event loop)
CREATE _pad-prompt-buf 64 ALLOT
VARIABLE _pad-prompt-len
VARIABLE _pad-pr-a                  \ cached label address
VARIABLE _pad-pr-u                  \ cached label length

: _PAD-PR-REDRAW  ( -- )
    RGN-ROOT  DRW-STYLE-RESET
    23 0 1 80 DRW-CLEAR-RECT
    _pad-pr-a @ _pad-pr-u @ 23 0 DRW-TEXT
    _pad-prompt-buf _pad-prompt-len @ 23 _pad-pr-u @ DRW-TEXT
    SCR-FLUSH ;

\ _PAD-PROMPT ( label-a label-u -- addr len | 0 0 )
: _PAD-PROMPT  ( label-a label-u -- addr len | 0 0 )
    _pad-pr-u ! _pad-pr-a !
    0 _pad-prompt-len !
    _PAD-PR-REDRAW
    BEGIN
        _pad-ev KEY-READ DROP
        _pad-ev @ KEY-T-SPECIAL = IF
            _pad-ev 8 + @
            DUP KEY-ENTER = IF
                DROP _PAD-DIRTY-STATUS
                _pad-prompt-buf _pad-prompt-len @ EXIT
            THEN
            DUP KEY-ESC = IF
                DROP _PAD-DIRTY-STATUS
                0 0 EXIT
            THEN
            DUP KEY-BACKSPACE = IF
                DROP
                _pad-prompt-len @ 0> IF
                    -1 _pad-prompt-len +!
                    _PAD-PR-REDRAW
                THEN
            ELSE DROP THEN
        ELSE
            _pad-ev @ KEY-T-CHAR = IF
                _pad-ev 8 + @
                DUP 32 >= OVER 127 < AND IF
                    _pad-prompt-len @ 60 < IF
                        _pad-prompt-buf _pad-prompt-len @ + C!
                        1 _pad-prompt-len +!
                        _PAD-PR-REDRAW
                    ELSE DROP THEN
                ELSE DROP THEN
            THEN
        THEN
    AGAIN ;

\ ============================================================
\  §4d — File commands (Save / Open / Save-As)
\ ============================================================

\ _PAD-SHOW-FNAME ( -- )  Clear dirty flag and update st-msg.
: _PAD-SHOW-FNAME  ( -- )
    0 _pad-dirty !
    _PAD-UPDATE-MSG ;

\ _PAD-SAVE ( -- )  Ctrl+S: save to known file, or prompt.
: _PAD-SAVE  ( -- )
    _PAD-HAS-FNAME? 0= IF
        S" Save as: " _PAD-PROMPT
        DUP 0= IF 2DROP EXIT THEN
        23 MIN  2DUP _pad-fname SWAP CMOVE  _pad-fname-len !  DROP
    THEN
    _PAD-DO-SAVE IF
        S" Save FAILED" _pad-msg-buf SWAP DUP >R CMOVE R> _pad-msg-len !
        _pad-msg-buf _pad-stmsg-attr @ 24 + !
        _pad-msg-len @ _pad-stmsg-attr @ 32 + !
        _pad-stmsg-elem @ UIDL-DIRTY!
    ELSE
        _PAD-SHOW-FNAME
    THEN
    _pad-editor-elem @ UIDL-DIRTY! ;

\ _PAD-SAVE-AS ( -- )  Ctrl+Shift+S: always prompt for name.
: _PAD-SAVE-AS  ( -- )
    S" Save as: " _PAD-PROMPT
    DUP 0= IF 2DROP EXIT THEN
    23 MIN  2DUP _pad-fname SWAP CMOVE  _pad-fname-len !  DROP
    _PAD-DO-SAVE IF
        S" Save FAILED" _pad-msg-buf SWAP DUP >R CMOVE R> _pad-msg-len !
        _pad-msg-buf _pad-stmsg-attr @ 24 + !
        _pad-msg-len @ _pad-stmsg-attr @ 32 + !
        _pad-stmsg-elem @ UIDL-DIRTY!
    ELSE
        _PAD-SHOW-FNAME
    THEN
    _pad-editor-elem @ UIDL-DIRTY! ;

\ _PAD-FILE-OPEN ( -- )  Ctrl+O: prompt for filename and load.
: _PAD-FILE-OPEN  ( -- )
    S" Open: " _PAD-PROMPT
    DUP 0= IF 2DROP EXIT THEN
    23 MIN  2DUP _pad-fname SWAP CMOVE  _pad-fname-len !  DROP
    _PAD-DO-OPEN IF
        S" Open FAILED" _pad-msg-buf SWAP DUP >R CMOVE R> _pad-msg-len !
        _pad-msg-buf _pad-stmsg-attr @ 24 + !
        _pad-msg-len @ _pad-stmsg-attr @ 32 + !
        _pad-stmsg-elem @ UIDL-DIRTY!
    ELSE
        _PAD-SHOW-FNAME
    THEN
    _pad-editor-elem @ UIDL-DIRTY! ;

\ ============================================================
\  §4e — Clipboard (Ctrl+C / Ctrl+X / Ctrl+V)
\ ============================================================

\ _PAD-COPY ( -- )  Copy selection to system clipboard.
: _PAD-COPY  ( -- )
    _pad-editor-w @ TXTA-GET-SEL   ( addr len | 0 0 )
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP ;

\ _PAD-CUT ( -- )  Copy selection then delete it.
: _PAD-CUT  ( -- )
    _pad-editor-w @ TXTA-GET-SEL
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP
    _pad-editor-w @ TXTA-DEL-SEL DROP
    _pad-editor-elem @ UIDL-DIRTY! ;

\ _PAD-PASTE ( -- )  Paste most recent clipboard entry at cursor.
: _PAD-PASTE  ( -- )
    CLIP-PASTE                        ( addr len )
    DUP 0= IF 2DROP EXIT THEN
    _pad-editor-w @ TXTA-INS-STR
    _pad-editor-elem @ UIDL-DIRTY! ;

\ _PAD-CLIPBOARD? ( ev -- flag )  If Ctrl+C/X/V, handle and return TRUE.
: _PAD-CLIPBOARD?  ( ev -- flag )
    DUP @ KEY-T-CHAR <> IF DROP 0 EXIT THEN
    DUP 16 + @ KEY-MOD-CTRL AND 0= IF DROP 0 EXIT THEN
    DUP 16 + @ >R                     \ R: mods
    8 + @
    DUP [CHAR] c = IF DROP R> DROP _PAD-COPY      -1 EXIT THEN
    DUP [CHAR] x = IF DROP R> DROP _PAD-CUT       -1 EXIT THEN
    DUP [CHAR] v = IF DROP R> DROP _PAD-PASTE     -1 EXIT THEN
    DUP [CHAR] s = IF DROP
        R> KEY-MOD-SHIFT AND IF _PAD-SAVE-AS ELSE _PAD-SAVE THEN
        -1 EXIT THEN
    DUP [CHAR] o = IF DROP R> DROP _PAD-FILE-OPEN -1 EXIT THEN
    DROP R> DROP 0 ;

\ ============================================================
\  §5 — Event Loop
\ ============================================================

: PAD-RUN  ( -- )
    0 _pad-quit !

    \ Reduce CR→LF timeout from 50 ms to 1 ms (emulator sends bare CR)
    1 KEY-TIMEOUT!

    \ Initial paint (materializes widgets)
    UTUI-PAINT  SCR-FLUSH

    \ Now that widgets exist, resolve cached pointers
    _PAD-INIT-POS
    \ Wire up on-change callback for dirty indicator
    ['] _PAD-ON-CHANGE _pad-editor-w @ TXTA-ON-CHANGE
    _PAD-UPDATE-POS
    UTUI-PAINT  SCR-FLUSH

    BEGIN
        _pad-ev KEY-READ DROP
        _pad-ev UTUI-DISPATCH-KEY 0= IF
            _pad-ev _PAD-CLIPBOARD? DROP
        THEN
        _PAD-UPDATE-POS
        UTUI-PAINT
        SCR-FLUSH
        _pad-quit @
    UNTIL

    \ Cleanup
    UTUI-DETACH
    ANSI-CLEAR  ANSI-HOME  ANSI-CURSOR-ON
    ." [pad] Akashic Pad exited." CR ;

PAD-RUN
