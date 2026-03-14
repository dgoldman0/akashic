\ akashic-pad-dom.f — Akashic Pad (DOM Edition)
\ ============================================================
\ A styled text editor built on the DOM-TUI rendering stack.
\ Uses DOM elements for layout + styled chrome, with the
\ textarea widget handling editing directly.
\
\ Layout (80x24):
\   Row  0:     Title bar  (dark purple, bold white text)
\   Rows 1-22:  Editor textarea (22 rows)
\   Row  23:    Status bar (dark blue, grey text)
\                 filename | Ln/Col | mode
\
\ Keyboard:
\   Ctrl+Q         Quit
\   Ctrl+S         Save (prompt if unnamed)
\   Ctrl+Shift+S   Save as
\   Ctrl+O         Open file
\   Ctrl+C / X / V Copy / Cut / Paste
\   Ctrl+A         Select all
\   Arrow keys     Move cursor
\   Shift+Arrow    Extend selection
\   Home / End     Start / end of line
\   PgUp / PgDn    Scroll page
\   Ctrl+Left/Right  Word movement
\ ============================================================

REQUIRE tui/dom-render.f
REQUIRE tui/widgets/textarea.f
REQUIRE utils/clipboard.f

\ ============================================================
\  §1 — Arena, DOM Document, Screen & Region
\ ============================================================

524288 A-XMEM ARENA-NEW DROP CONSTANT _pad-arena
_pad-arena 64 64 DOM-DOC-NEW CONSTANT _pad-doc
DOM-HTML-INIT

ANSI-CLEAR  ANSI-HOME  ANSI-CURSOR-OFF
80 24 SCR-NEW CONSTANT _pad-scr
_pad-scr SCR-USE
SCR-CLEAR
0 0 24 80 RGN-NEW CONSTANT _pad-rgn

\ ============================================================
\  §2 — DOM Tree Construction
\ ============================================================
\
\ Three block divs under BODY:
\   hdr  — title bar  (row 0, h=1)  visible, painted by DOM
\   edit — spacer     (row 1, h=22) visibility:hidden
\   bar  — spacer     (row 23, h=1) visibility:hidden
\
\ The editor and status bar are drawn separately by the
\ textarea widget and _PAD-DRAW-STATUS.  The DOM handles
\ the title bar rendering and layout positioning.

VARIABLE _pad-hdr
VARIABLE _pad-edit
VARIABLE _pad-bar

: _PAD-BUILD-DOM  ( -- )
    \ --- Title bar: dark purple bg, bold white text ---
    S" div" DOM-CREATE-ELEMENT _pad-hdr !
    _pad-hdr @ S" style"
    S" display:block;width:80;height:1;background-color:#5f0087;color:#ffffff;font-weight:bold"
    DOM-ATTR!
    S"  Akashic Pad" DOM-CREATE-TEXT _pad-hdr @ DOM-APPEND
    _pad-hdr @ DOM-BODY DOM-APPEND

    \ --- Editor spacer (hidden — textarea widget draws here) ---
    S" div" DOM-CREATE-ELEMENT _pad-edit !
    _pad-edit @ S" style"
    S" display:block;width:80;height:22;visibility:hidden"
    DOM-ATTR!
    _pad-edit @ DOM-BODY DOM-APPEND

    \ --- Status bar spacer (hidden — drawn manually) ---
    S" div" DOM-CREATE-ELEMENT _pad-bar !
    _pad-bar @ S" style"
    S" display:block;width:80;height:1;visibility:hidden"
    DOM-ATTR!
    _pad-bar @ DOM-BODY DOM-APPEND ;

_PAD-BUILD-DOM

\ ============================================================
\  §3 — Attach Sidecars + Initial Layout & Paint
\ ============================================================

_pad-doc DTUI-ATTACH
_pad-doc _pad-rgn DREN-RENDER

\ ============================================================
\  §4 — Textarea Widget
\ ============================================================

4096 CONSTANT _PAD-BUF-SIZE
CREATE _pad-buf _PAD-BUF-SIZE ALLOT

\ Editor region: rows 1-22, cols 0-79
1 0 22 80 RGN-NEW CONSTANT _pad-ed-rgn

_pad-ed-rgn _pad-buf _PAD-BUF-SIZE TXTA-NEW CONSTANT _pad-editor-w

\ ============================================================
\  §5 — State Variables
\ ============================================================

VARIABLE _pad-quit
VARIABLE _pad-dirty

CREATE _pad-fname 24 ALLOT
VARIABLE _pad-fname-len
0 _pad-fname-len !

: _PAD-HAS-FNAME?  ( -- flag )  _pad-fname-len @ 0> ;

\ ============================================================
\  §5a — On-Change Callback
\ ============================================================

: _PAD-ON-CHANGE  ( widget -- )
    DROP
    _pad-dirty @ IF EXIT THEN
    -1 _pad-dirty ! ;

\ ============================================================
\  §6 — Status Bar Drawing
\ ============================================================

\ Palette indices
24  CONSTANT _SB-BG       \ #005f87 — dark blue
188 CONSTANT _SB-FG       \ #d7d7d7 — light grey
73  CONSTANT _SB-SEP-FG   \ #5fafaf — muted teal (separators)

23 0 1 80 RGN-NEW CONSTANT _pad-sb-rgn

\ --- Message buffer (filename + dirty indicator) ---
CREATE _pad-msg-buf 48 ALLOT
VARIABLE _pad-msg-len

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
    THEN ;

\ --- Position buffer ("Ln N, Col M") ---
CREATE _pad-pos-buf 24 ALLOT
VARIABLE _pad-pos-len

: _PAD-APPEND  ( a u -- )
    _pad-pos-buf _pad-pos-len @ +
    SWAP DUP >R CMOVE
    R> _pad-pos-len +! ;

: _PAD-UPDATE-POS  ( -- )
    0 _pad-pos-len !
    S" Ln " _PAD-APPEND
    _pad-editor-w TXTA-CURSOR-LINE 1+ NUM>STR _PAD-APPEND
    S" , Col " _PAD-APPEND
    _pad-editor-w TXTA-CURSOR-COL 1+ NUM>STR _PAD-APPEND ;

\ --- Draw the entire status bar ---
: _PAD-DRAW-STATUS  ( -- )
    _pad-sb-rgn RGN-USE
    _SB-FG DRW-FG!  _SB-BG DRW-BG!  0 DRW-ATTR!
    \ Fill background
    32 0 0 1 80 DRW-FILL-RECT
    \ Message (col 1, ~42 chars)
    _pad-msg-buf _pad-msg-len @ 0 1 DRW-TEXT
    \ Separator 1 (col 43)
    _SB-SEP-FG DRW-FG!
    S" |" 0 43 DRW-TEXT
    \ Cursor position (col 45)
    _SB-FG DRW-FG!
    _pad-pos-buf _pad-pos-len @ 0 45 DRW-TEXT
    \ Separator 2 (col 62)
    _SB-SEP-FG DRW-FG!
    S" |" 0 62 DRW-TEXT
    \ Mode indicator (col 64)
    _SB-FG DRW-FG!
    S" INSERT" 0 64 DRW-TEXT
    RGN-ROOT ;

\ ============================================================
\  §7 — File I/O Helpers
\ ============================================================

: _PAD-NAME!  ( addr len -- )
    NAMEBUF 24 0 FILL
    23 MIN NAMEBUF SWAP CMOVE ;

8 CONSTANT _PAD-FSECTORS

: _PAD-FOPEN  ( -- fdesc | 0 )
    FS-ENSURE
    FS-OK @ 0= IF 0 EXIT THEN
    FIND-BY-NAME DUP -1 = IF DROP 0 EXIT THEN
    >R FD-ALLOC DUP 0= IF R> DROP EXIT THEN
    DUP R> FD-FILL ;

VARIABLE _PFC-SLOT
VARIABLE _PFC-START

: _PAD-FCREATE  ( -- fdesc | 0 )
    FS-ENSURE
    FS-OK @ 0= IF 0 EXIT THEN
    FIND-BY-NAME -1 <> IF 0 EXIT THEN
    FIND-FREE-SLOT _PFC-SLOT !
    _PFC-SLOT @ -1 = IF 0 EXIT THEN
    _PAD-FSECTORS FIND-FREE _PFC-START !
    _PFC-START @ -1 = IF 0 EXIT THEN
    _PAD-FSECTORS 0 DO _PFC-START @ I + BIT-SET LOOP
    _PFC-SLOT @ DIRENT
    DUP FS-ENTRY-SIZE 0 FILL
    DUP NAMEBUF SWAP 24 CMOVE
    DUP _PFC-START @ SWAP 24 + W!
    DUP _PAD-FSECTORS  SWAP 26 + W!
    DUP 0              SWAP 28 + L!
    DUP 2              SWAP 32 + C!
    DUP CWD @          SWAP 34 + C!
    DUP TICKS@         SWAP 36 + L!
    DROP
    FS-SYNC
    FD-ALLOC DUP 0= IF EXIT THEN
    DUP _PFC-SLOT @ FD-FILL ;

CREATE _pad-iobuf 4096 ALLOT

VARIABLE _PDS-FD

: _PAD-DO-SAVE  ( -- ior )
    _pad-fname _pad-fname-len @ _PAD-NAME!
    _PAD-FOPEN DUP 0= IF
        _pad-fname _pad-fname-len @ _PAD-NAME!
        _PAD-FCREATE DUP 0= IF -1 EXIT THEN
    THEN
    _PDS-FD !
    0 _PDS-FD @ FTRUNCATE
    _pad-editor-w TXTA-GET-TEXT
    DUP >R
    _PDS-FD @ FWRITE
    R> _PDS-FD @ FTRUNCATE
    _PDS-FD @ FCLOSE
    0 ;

VARIABLE _PDO-FD

: _PAD-DO-OPEN  ( -- ior )
    _pad-fname _pad-fname-len @ _PAD-NAME!
    _PAD-FOPEN DUP 0= IF -1 EXIT THEN
    _PDO-FD !
    _PDO-FD @ FREWIND
    _pad-iobuf 4096 _PDO-FD @ FREAD
    _pad-iobuf SWAP
    _pad-editor-w TXTA-SET-TEXT
    _PDO-FD @ FCLOSE
    0 ;

\ ============================================================
\  §8 — Status-Bar Prompt (modal mini-input)
\ ============================================================

CREATE _pad-ev 24 ALLOT
CREATE _pad-prompt-buf 64 ALLOT
VARIABLE _pad-prompt-len
VARIABLE _pad-pr-a
VARIABLE _pad-pr-u

: _PAD-PR-REDRAW  ( -- )
    _pad-sb-rgn RGN-USE
    _SB-FG DRW-FG!  _SB-BG DRW-BG!  0 DRW-ATTR!
    32 0 0 1 80 DRW-FILL-RECT
    _pad-pr-a @ _pad-pr-u @ 0 0 DRW-TEXT
    _pad-prompt-buf _pad-prompt-len @ 0 _pad-pr-u @ DRW-TEXT
    RGN-ROOT
    SCR-FLUSH ;

: _PAD-PROMPT  ( label-a label-u -- addr len | 0 0 )
    _pad-pr-u ! _pad-pr-a !
    0 _pad-prompt-len !
    _PAD-PR-REDRAW
    BEGIN
        _pad-ev KEY-READ DROP
        _pad-ev @ KEY-T-SPECIAL = IF
            _pad-ev 8 + @
            DUP KEY-ENTER = IF
                DROP _pad-prompt-buf _pad-prompt-len @ EXIT
            THEN
            DUP KEY-ESC = IF
                DROP 0 0 EXIT
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
\  §9 — File Commands
\ ============================================================

: _PAD-SHOW-FNAME  ( -- )
    0 _pad-dirty ! ;

: _PAD-SAVE  ( -- )
    _PAD-HAS-FNAME? 0= IF
        S" Save as: " _PAD-PROMPT
        DUP 0= IF 2DROP EXIT THEN
        23 MIN  2DUP _pad-fname SWAP CMOVE  _pad-fname-len !  DROP
    THEN
    _PAD-DO-SAVE DROP
    _PAD-SHOW-FNAME ;

: _PAD-SAVE-AS  ( -- )
    S" Save as: " _PAD-PROMPT
    DUP 0= IF 2DROP EXIT THEN
    23 MIN  2DUP _pad-fname SWAP CMOVE  _pad-fname-len !  DROP
    _PAD-DO-SAVE DROP
    _PAD-SHOW-FNAME ;

: _PAD-FILE-OPEN  ( -- )
    S" Open: " _PAD-PROMPT
    DUP 0= IF 2DROP EXIT THEN
    23 MIN  2DUP _pad-fname SWAP CMOVE  _pad-fname-len !  DROP
    _PAD-DO-OPEN DROP
    _PAD-SHOW-FNAME ;

\ ============================================================
\  §10 — Clipboard
\ ============================================================

: _PAD-COPY  ( -- )
    _pad-editor-w TXTA-GET-SEL
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP ;

: _PAD-CUT  ( -- )
    _pad-editor-w TXTA-GET-SEL
    DUP 0= IF 2DROP EXIT THEN
    CLIP-COPY DROP
    _pad-editor-w TXTA-DEL-SEL DROP ;

: _PAD-PASTE  ( -- )
    CLIP-PASTE
    DUP 0= IF 2DROP EXIT THEN
    _pad-editor-w TXTA-INS-STR ;

\ ============================================================
\  §11 — Event Shortcuts
\ ============================================================

: _PAD-SHORTCUT?  ( ev -- flag )
    DUP @ KEY-T-CHAR <> IF DROP 0 EXIT THEN
    DUP 16 + @ KEY-MOD-CTRL AND 0= IF DROP 0 EXIT THEN
    DUP 16 + @ >R
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
\  §12 — Event Loop
\ ============================================================

: PAD-RUN  ( -- )
    0 _pad-quit !
    0 _pad-dirty !
    1 KEY-TIMEOUT!

    \ Wire on-change callback
    ['] _PAD-ON-CHANGE _pad-editor-w TXTA-ON-CHANGE

    \ Initial paint (title bar already in back buffer from §3)
    _PAD-UPDATE-MSG  _PAD-UPDATE-POS
    _pad-editor-w WDG-DIRTY  _pad-editor-w WDG-DRAW
    _PAD-DRAW-STATUS
    SCR-FLUSH

    BEGIN
        _pad-ev KEY-READ DROP

        \ --- Ctrl+Q to quit ---
        _pad-ev @ KEY-T-CHAR = IF
            _pad-ev 8 + @ [CHAR] q =
            _pad-ev 16 + @ KEY-MOD-CTRL AND AND IF
                -1 _pad-quit !
            THEN
        THEN

        _pad-quit @ 0= IF
            \ App-level shortcuts (clipboard, file I/O)
            _pad-ev _PAD-SHORTCUT? 0= IF
                \ Pass to textarea widget
                _pad-ev _pad-editor-w WDG-HANDLE DROP
            THEN

            \ Update status bar content
            _PAD-UPDATE-MSG  _PAD-UPDATE-POS

            \ Repaint editor + status bar
            _pad-editor-w WDG-DIRTY  _pad-editor-w WDG-DRAW
            _PAD-DRAW-STATUS
            SCR-FLUSH
        THEN

        _pad-quit @
    UNTIL

    \ Cleanup
    _pad-doc DTUI-DETACH
    ANSI-CLEAR  ANSI-HOME  ANSI-CURSOR-ON
    ." [pad] Akashic Pad exited." CR ;

PAD-RUN
