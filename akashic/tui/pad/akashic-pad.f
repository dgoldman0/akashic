\ akashic-pad.f — Akashic Pad editor (Phase 1 MVP)
\ ============================================================
\ Loaded by autoexec.f via LOAD akashic-pad.f
\
\ Phase 1: Minimal editing loop
\   - Textarea fills most of the screen (rows 0–22)
\   - Status bar at bottom row (Ready | Ln/Col | INSERT)
\   - Ctrl+Q to quit
\ ============================================================

REQUIRE tui/uidl-tui.f

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
VARIABLE _pad-stpos-elem   \ st-pos UIDL element
VARIABLE _pad-stpos-attr   \ st-pos 'text' attr node
VARIABLE _pad-stmsg-elem   \ st-msg UIDL element
VARIABLE _pad-stmsg-attr   \ st-msg 'text' attr node
VARIABLE _pad-dirty        \ buffer modified flag

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

\ _PAD-ON-CHANGE ( widget -- )  Callback from textarea on any edit.
: _PAD-ON-CHANGE  ( widget -- )
    DROP
    _pad-dirty @ IF EXIT THEN          \ already dirty
    -1 _pad-dirty !
    \ Poke "Modified" into st-msg label
    S" Modified" DROP _pad-stmsg-attr @ 24 + !
    8                _pad-stmsg-attr @ 32 + !
    _pad-stmsg-elem @ UIDL-DIRTY! ;

\ ============================================================
\  §5 — Event Loop
\ ============================================================

CREATE _pad-ev 24 ALLOT

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
        _pad-ev UTUI-DISPATCH-KEY DROP
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
