\ =================================================================
\  ansi.f  —  ANSI Terminal Escape Sequence Emitter
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ANSI-  / _ANSI-
\  No dependencies (pure KDOS EMIT / TYPE).
\
\  Stateless words that emit VT100/ANSI escape sequences to the
\  UART.  Every word is a thin wrapper around EMIT — no buffers,
\  no allocation, no state.  This is the bottom of the TUI stack.
\
\  Public API — Cursor:
\   ANSI-AT            ( row col -- )    Move cursor to (row,col) 1-based
\   ANSI-UP            ( n -- )          Cursor up n rows
\   ANSI-DOWN          ( n -- )          Cursor down n rows
\   ANSI-RIGHT         ( n -- )          Cursor right n cols
\   ANSI-LEFT          ( n -- )          Cursor left n cols
\   ANSI-HOME          ( -- )            Cursor to top-left
\   ANSI-COL           ( n -- )          Move to column n
\   ANSI-SAVE          ( -- )            Save cursor position
\   ANSI-RESTORE       ( -- )            Restore cursor position
\
\  Public API — Clear:
\   ANSI-CLEAR         ( -- )            Clear entire screen
\   ANSI-CLEAR-EOL     ( -- )            Clear to end of line
\   ANSI-CLEAR-BOL     ( -- )            Clear to beginning of line
\   ANSI-CLEAR-LINE    ( -- )            Clear entire line
\   ANSI-CLEAR-EOS     ( -- )            Clear to end of screen
\   ANSI-CLEAR-BOS     ( -- )            Clear to beginning of screen
\
\  Public API — Scroll:
\   ANSI-SCROLL-UP     ( n -- )          Scroll up n lines
\   ANSI-SCROLL-DN     ( n -- )          Scroll down n lines
\   ANSI-SCROLL-RGN    ( top bot -- )    Set scroll region
\   ANSI-SCROLL-RESET  ( -- )            Reset scroll region
\
\  Public API — Attributes:
\   ANSI-RESET         ( -- )            Reset all attributes
\   ANSI-BOLD          ( -- )            Bold on
\   ANSI-DIM           ( -- )            Dim on
\   ANSI-ITALIC        ( -- )            Italic on
\   ANSI-UNDERLINE     ( -- )            Underline on
\   ANSI-BLINK         ( -- )            Blink on
\   ANSI-REVERSE       ( -- )            Reverse video on
\   ANSI-HIDDEN        ( -- )            Hidden text on
\   ANSI-STRIKE        ( -- )            Strikethrough on
\   ANSI-NORMAL        ( -- )            Remove bold/dim
\
\  Public API — Colors (16 standard):
\   ANSI-FG            ( color -- )      Foreground 0-7
\   ANSI-BG            ( color -- )      Background 0-7
\   ANSI-FG-BRIGHT     ( color -- )      Bright foreground 0-7
\   ANSI-BG-BRIGHT     ( color -- )      Bright background 0-7
\
\  Public API — Colors (256 and true-color):
\   ANSI-FG256         ( n -- )          256-color foreground
\   ANSI-BG256         ( n -- )          256-color background
\   ANSI-FG-RGB        ( r g b -- )      True-color foreground
\   ANSI-BG-RGB        ( r g b -- )      True-color background
\   ANSI-DEFAULT-FG    ( -- )            Reset foreground
\   ANSI-DEFAULT-BG    ( -- )            Reset background
\
\  Public API — Terminal Modes:
\   ANSI-ALT-ON        ( -- )            Enter alternate screen
\   ANSI-ALT-OFF       ( -- )            Leave alternate screen
\   ANSI-CURSOR-ON     ( -- )            Show cursor
\   ANSI-CURSOR-OFF    ( -- )            Hide cursor
\   ANSI-MOUSE-ON      ( -- )            Enable SGR mouse reporting
\   ANSI-MOUSE-OFF     ( -- )            Disable mouse reporting
\   ANSI-PASTE-ON      ( -- )            Enable bracketed paste
\   ANSI-PASTE-OFF     ( -- )            Disable bracketed paste
\   ANSI-QUERY-SIZE    ( -- )            Request terminal size report
\
\  Not reentrant (scratch VARIABLEs for number formatting).
\ =================================================================

PROVIDED akashic-tui-ansi

\ =====================================================================
\  1. Constants
\ =====================================================================

27 CONSTANT ANSI-ESC              \ ESC character (0x1B)

\ Standard color indices (same numbering as ANSI)
0 CONSTANT ANSI-BLACK
1 CONSTANT ANSI-RED
2 CONSTANT ANSI-GREEN
3 CONSTANT ANSI-YELLOW
4 CONSTANT ANSI-BLUE
5 CONSTANT ANSI-MAGENTA
6 CONSTANT ANSI-CYAN
7 CONSTANT ANSI-WHITE

\ =====================================================================
\  2. Internal helpers — emit CSI prefix and decimal numbers
\ =====================================================================

\ _ANSI-CSI ( -- )  Emit ESC [
: _ANSI-CSI  ( -- )
    ANSI-ESC EMIT [CHAR] [ EMIT ;

\ _ANSI-SEP ( -- )  Emit ; separator
: _ANSI-SEP  ( -- )
    [CHAR] ; EMIT ;

\ _ANSI-NUM ( n -- )  Emit unsigned decimal number.
\   Uses a local scratch buffer on the return stack.  Handles 0
\   correctly (emits "0"), and up to 10 digits for 32-bit values.

VARIABLE _ANSI-NB        \ scratch: numeric buffer pointer
VARIABLE _ANSI-NC        \ scratch: char count

CREATE _ANSI-NBUF  12 ALLOT   \ enough for max 64-bit decimal

: _ANSI-NUM  ( n -- )
    DUP 0= IF DROP [CHAR] 0 EMIT EXIT THEN
    0 _ANSI-NC !
    _ANSI-NBUF 12 + _ANSI-NB !       \ start from end of buffer
    BEGIN DUP 0 > WHILE
        10 /MOD SWAP                  ( quot rem )
        [CHAR] 0 + _ANSI-NB @ 1- DUP _ANSI-NB ! C!
        1 _ANSI-NC +!
    REPEAT
    DROP
    _ANSI-NB @ _ANSI-NC @ TYPE ;

\ _ANSI-SGR ( n -- )  Emit CSI n m  — a single SGR parameter.
: _ANSI-SGR  ( n -- )
    _ANSI-CSI _ANSI-NUM [CHAR] m EMIT ;

\ =====================================================================
\  3. Cursor Movement
\ =====================================================================

\ ANSI-AT ( row col -- )  Move cursor to (row, col). 1-based.
\   Emits: ESC[row;colH
: ANSI-AT  ( row col -- )
    _ANSI-CSI SWAP _ANSI-NUM _ANSI-SEP _ANSI-NUM [CHAR] H EMIT ;

\ ANSI-UP ( n -- )  Cursor up n rows.  ESC[nA
: ANSI-UP  ( n -- )
    DUP 0= IF DROP EXIT THEN
    _ANSI-CSI _ANSI-NUM [CHAR] A EMIT ;

\ ANSI-DOWN ( n -- )  Cursor down n rows.  ESC[nB
: ANSI-DOWN  ( n -- )
    DUP 0= IF DROP EXIT THEN
    _ANSI-CSI _ANSI-NUM [CHAR] B EMIT ;

\ ANSI-RIGHT ( n -- )  Cursor right n columns.  ESC[nC
: ANSI-RIGHT  ( n -- )
    DUP 0= IF DROP EXIT THEN
    _ANSI-CSI _ANSI-NUM [CHAR] C EMIT ;

\ ANSI-LEFT ( n -- )  Cursor left n columns.  ESC[nD
: ANSI-LEFT  ( n -- )
    DUP 0= IF DROP EXIT THEN
    _ANSI-CSI _ANSI-NUM [CHAR] D EMIT ;

\ ANSI-HOME ( -- )  Cursor to row 1, col 1.  ESC[H
: ANSI-HOME  ( -- )
    _ANSI-CSI [CHAR] H EMIT ;

\ ANSI-COL ( n -- )  Move cursor to column n (1-based).  ESC[nG
: ANSI-COL  ( n -- )
    _ANSI-CSI _ANSI-NUM [CHAR] G EMIT ;

\ ANSI-SAVE ( -- )  Save cursor position.  ESC[s
: ANSI-SAVE  ( -- )
    _ANSI-CSI [CHAR] s EMIT ;

\ ANSI-RESTORE ( -- )  Restore cursor position.  ESC[u
: ANSI-RESTORE  ( -- )
    _ANSI-CSI [CHAR] u EMIT ;

\ =====================================================================
\  4. Screen Clearing
\ =====================================================================

\ ANSI-CLEAR ( -- )  Clear entire screen.  ESC[2J
: ANSI-CLEAR  ( -- )
    _ANSI-CSI [CHAR] 2 EMIT [CHAR] J EMIT ;

\ ANSI-CLEAR-EOL ( -- )  Clear to end of line.  ESC[K  (same as ESC[0K)
: ANSI-CLEAR-EOL  ( -- )
    _ANSI-CSI [CHAR] K EMIT ;

\ ANSI-CLEAR-BOL ( -- )  Clear to beginning of line.  ESC[1K
: ANSI-CLEAR-BOL  ( -- )
    _ANSI-CSI [CHAR] 1 EMIT [CHAR] K EMIT ;

\ ANSI-CLEAR-LINE ( -- )  Clear entire line.  ESC[2K
: ANSI-CLEAR-LINE  ( -- )
    _ANSI-CSI [CHAR] 2 EMIT [CHAR] K EMIT ;

\ ANSI-CLEAR-EOS ( -- )  Clear to end of screen.  ESC[J  (same as ESC[0J)
: ANSI-CLEAR-EOS  ( -- )
    _ANSI-CSI [CHAR] J EMIT ;

\ ANSI-CLEAR-BOS ( -- )  Clear to beginning of screen.  ESC[1J
: ANSI-CLEAR-BOS  ( -- )
    _ANSI-CSI [CHAR] 1 EMIT [CHAR] J EMIT ;

\ =====================================================================
\  5. Scrolling
\ =====================================================================

\ ANSI-SCROLL-UP ( n -- )  Scroll up n lines.  ESC[nS
: ANSI-SCROLL-UP  ( n -- )
    DUP 0= IF DROP EXIT THEN
    _ANSI-CSI _ANSI-NUM [CHAR] S EMIT ;

\ ANSI-SCROLL-DN ( n -- )  Scroll down n lines.  ESC[nT
: ANSI-SCROLL-DN  ( n -- )
    DUP 0= IF DROP EXIT THEN
    _ANSI-CSI _ANSI-NUM [CHAR] T EMIT ;

\ ANSI-SCROLL-RGN ( top bot -- )  Set scroll region.  ESC[top;botr
: ANSI-SCROLL-RGN  ( top bot -- )
    _ANSI-CSI SWAP _ANSI-NUM _ANSI-SEP _ANSI-NUM [CHAR] r EMIT ;

\ ANSI-SCROLL-RESET ( -- )  Reset scroll region to full screen.  ESC[r
: ANSI-SCROLL-RESET  ( -- )
    _ANSI-CSI [CHAR] r EMIT ;

\ =====================================================================
\  6. Text Attributes (SGR — Select Graphic Rendition)
\ =====================================================================

\ ANSI-RESET ( -- )  Reset all attributes.  ESC[0m
: ANSI-RESET  ( -- )
    0 _ANSI-SGR ;

\ ANSI-BOLD ( -- )  Bold (bright) on.  ESC[1m
: ANSI-BOLD  ( -- )
    1 _ANSI-SGR ;

\ ANSI-DIM ( -- )  Dim (faint) on.  ESC[2m
: ANSI-DIM  ( -- )
    2 _ANSI-SGR ;

\ ANSI-ITALIC ( -- )  Italic on.  ESC[3m
: ANSI-ITALIC  ( -- )
    3 _ANSI-SGR ;

\ ANSI-UNDERLINE ( -- )  Underline on.  ESC[4m
: ANSI-UNDERLINE  ( -- )
    4 _ANSI-SGR ;

\ ANSI-BLINK ( -- )  Blink on.  ESC[5m
: ANSI-BLINK  ( -- )
    5 _ANSI-SGR ;

\ ANSI-REVERSE ( -- )  Reverse video on.  ESC[7m
: ANSI-REVERSE  ( -- )
    7 _ANSI-SGR ;

\ ANSI-HIDDEN ( -- )  Hidden on.  ESC[8m
: ANSI-HIDDEN  ( -- )
    8 _ANSI-SGR ;

\ ANSI-STRIKE ( -- )  Strikethrough on.  ESC[9m
: ANSI-STRIKE  ( -- )
    9 _ANSI-SGR ;

\ ANSI-NORMAL ( -- )  Normal intensity (remove bold/dim).  ESC[22m
: ANSI-NORMAL  ( -- )
    22 _ANSI-SGR ;

\ ---- Turn-off counterparts ----

\ ANSI-NO-ITALIC ( -- )  ESC[23m
: ANSI-NO-ITALIC  ( -- )
    23 _ANSI-SGR ;

\ ANSI-NO-UNDERLINE ( -- )  ESC[24m
: ANSI-NO-UNDERLINE  ( -- )
    24 _ANSI-SGR ;

\ ANSI-NO-BLINK ( -- )  ESC[25m
: ANSI-NO-BLINK  ( -- )
    25 _ANSI-SGR ;

\ ANSI-NO-REVERSE ( -- )  ESC[27m
: ANSI-NO-REVERSE  ( -- )
    27 _ANSI-SGR ;

\ ANSI-NO-HIDDEN ( -- )  ESC[28m
: ANSI-NO-HIDDEN  ( -- )
    28 _ANSI-SGR ;

\ ANSI-NO-STRIKE ( -- )  ESC[29m
: ANSI-NO-STRIKE  ( -- )
    29 _ANSI-SGR ;

\ =====================================================================
\  7. Colors — Standard 16 (8 base + 8 bright)
\ =====================================================================

\ ANSI-FG ( color -- )  Set foreground from 0-7.  ESC[30+colorm
: ANSI-FG  ( color -- )
    30 + _ANSI-SGR ;

\ ANSI-BG ( color -- )  Set background from 0-7.  ESC[40+colorm
: ANSI-BG  ( color -- )
    40 + _ANSI-SGR ;

\ ANSI-FG-BRIGHT ( color -- )  Bright foreground 0-7.  ESC[90+colorm
: ANSI-FG-BRIGHT  ( color -- )
    90 + _ANSI-SGR ;

\ ANSI-BG-BRIGHT ( color -- )  Bright background 0-7.  ESC[100+colorm
: ANSI-BG-BRIGHT  ( color -- )
    100 + _ANSI-SGR ;

\ =====================================================================
\  8. Colors — 256-color palette
\ =====================================================================

\ ANSI-FG256 ( n -- )  256-color foreground.  ESC[38;5;nm
: ANSI-FG256  ( n -- )
    _ANSI-CSI
    [CHAR] 3 EMIT [CHAR] 8 EMIT _ANSI-SEP
    [CHAR] 5 EMIT _ANSI-SEP
    _ANSI-NUM [CHAR] m EMIT ;

\ ANSI-BG256 ( n -- )  256-color background.  ESC[48;5;nm
: ANSI-BG256  ( n -- )
    _ANSI-CSI
    [CHAR] 4 EMIT [CHAR] 8 EMIT _ANSI-SEP
    [CHAR] 5 EMIT _ANSI-SEP
    _ANSI-NUM [CHAR] m EMIT ;

\ =====================================================================
\  9. Colors — True-color (24-bit RGB)
\ =====================================================================

\ ANSI-FG-RGB ( r g b -- )  True-color foreground.  ESC[38;2;r;g;bm
: ANSI-FG-RGB  ( r g b -- )
    _ANSI-CSI
    [CHAR] 3 EMIT [CHAR] 8 EMIT _ANSI-SEP
    [CHAR] 2 EMIT _ANSI-SEP
    ROT _ANSI-NUM _ANSI-SEP            \ r
    SWAP _ANSI-NUM _ANSI-SEP           \ g
    _ANSI-NUM [CHAR] m EMIT ;          \ b

\ ANSI-BG-RGB ( r g b -- )  True-color background.  ESC[48;2;r;g;bm
: ANSI-BG-RGB  ( r g b -- )
    _ANSI-CSI
    [CHAR] 4 EMIT [CHAR] 8 EMIT _ANSI-SEP
    [CHAR] 2 EMIT _ANSI-SEP
    ROT _ANSI-NUM _ANSI-SEP            \ r
    SWAP _ANSI-NUM _ANSI-SEP           \ g
    _ANSI-NUM [CHAR] m EMIT ;          \ b

\ ANSI-DEFAULT-FG ( -- )  Reset foreground to default.  ESC[39m
: ANSI-DEFAULT-FG  ( -- )
    39 _ANSI-SGR ;

\ ANSI-DEFAULT-BG ( -- )  Reset background to default.  ESC[49m
: ANSI-DEFAULT-BG  ( -- )
    49 _ANSI-SGR ;

\ =====================================================================
\  10. Terminal Modes — Alternate Screen, Cursor, Mouse, Paste
\ =====================================================================

\ _ANSI-PRIV ( n suffix -- )  Emit ESC[?n{suffix}
\   Used for DEC private modes.
: _ANSI-PRIV  ( n suffix -- )
    SWAP
    _ANSI-CSI [CHAR] ? EMIT
    _ANSI-NUM EMIT ;

\ ANSI-ALT-ON ( -- )  Enter alternate screen buffer.  ESC[?1049h
: ANSI-ALT-ON  ( -- )
    1049 [CHAR] h _ANSI-PRIV ;

\ ANSI-ALT-OFF ( -- )  Leave alternate screen buffer.  ESC[?1049l
: ANSI-ALT-OFF  ( -- )
    1049 [CHAR] l _ANSI-PRIV ;

\ ANSI-CURSOR-ON ( -- )  Show cursor.  ESC[?25h
: ANSI-CURSOR-ON  ( -- )
    25 [CHAR] h _ANSI-PRIV ;

\ ANSI-CURSOR-OFF ( -- )  Hide cursor.  ESC[?25l
: ANSI-CURSOR-OFF  ( -- )
    25 [CHAR] l _ANSI-PRIV ;

\ ANSI-MOUSE-ON ( -- )  Enable SGR extended mouse reporting.
\   ESC[?1000h  (basic button events)
\   ESC[?1006h  (SGR encoding — allows coordinates > 223)
: ANSI-MOUSE-ON  ( -- )
    1000 [CHAR] h _ANSI-PRIV
    1006 [CHAR] h _ANSI-PRIV ;

\ ANSI-MOUSE-OFF ( -- )  Disable mouse reporting.
\   ESC[?1006l  ESC[?1000l
: ANSI-MOUSE-OFF  ( -- )
    1006 [CHAR] l _ANSI-PRIV
    1000 [CHAR] l _ANSI-PRIV ;

\ ANSI-PASTE-ON ( -- )  Enable bracketed paste mode.  ESC[?2004h
: ANSI-PASTE-ON  ( -- )
    2004 [CHAR] h _ANSI-PRIV ;

\ ANSI-PASTE-OFF ( -- )  Disable bracketed paste mode.  ESC[?2004l
: ANSI-PASTE-OFF  ( -- )
    2004 [CHAR] l _ANSI-PRIV ;

\ =====================================================================
\  11. Queries
\ =====================================================================

\ ANSI-QUERY-SIZE ( -- )  Request terminal size via DSR.  ESC[18t
\   Terminal responds with ESC[8;rows;colst
: ANSI-QUERY-SIZE  ( -- )
    _ANSI-CSI
    [CHAR] 1 EMIT [CHAR] 8 EMIT [CHAR] t EMIT ;

\ ANSI-QUERY-CURSOR ( -- )  Request cursor position.  ESC[6n
\   Terminal responds with ESC[row;colR
: ANSI-QUERY-CURSOR  ( -- )
    _ANSI-CSI [CHAR] 6 EMIT [CHAR] n EMIT ;

\ =====================================================================
\  12. Title
\ =====================================================================

\ ANSI-TITLE ( addr len -- )  Set terminal title.  ESC]2;...ST
\   ST = ESC \  (string terminator)
: ANSI-TITLE  ( addr len -- )
    ANSI-ESC EMIT [CHAR] ] EMIT [CHAR] 2 EMIT _ANSI-SEP
    TYPE
    ANSI-ESC EMIT [CHAR] \ EMIT ;

\ =====================================================================
\  Done.
\ =====================================================================

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ansi-guard

' ANSI-AT             CONSTANT _ansi-at-xt
' ANSI-UP             CONSTANT _ansi-up-xt
' ANSI-DOWN           CONSTANT _ansi-down-xt
' ANSI-RIGHT          CONSTANT _ansi-right-xt
' ANSI-LEFT           CONSTANT _ansi-left-xt
' ANSI-HOME           CONSTANT _ansi-home-xt
' ANSI-COL            CONSTANT _ansi-col-xt
' ANSI-SAVE           CONSTANT _ansi-save-xt
' ANSI-RESTORE        CONSTANT _ansi-restore-xt
' ANSI-CLEAR          CONSTANT _ansi-clear-xt
' ANSI-CLEAR-EOL      CONSTANT _ansi-clear-eol-xt
' ANSI-CLEAR-BOL      CONSTANT _ansi-clear-bol-xt
' ANSI-CLEAR-LINE     CONSTANT _ansi-clear-line-xt
' ANSI-CLEAR-EOS      CONSTANT _ansi-clear-eos-xt
' ANSI-CLEAR-BOS      CONSTANT _ansi-clear-bos-xt
' ANSI-SCROLL-UP      CONSTANT _ansi-scrup-xt
' ANSI-SCROLL-DN      CONSTANT _ansi-scrdn-xt
' ANSI-SCROLL-RGN     CONSTANT _ansi-scrgn-xt
' ANSI-SCROLL-RESET   CONSTANT _ansi-scrrst-xt
' ANSI-RESET          CONSTANT _ansi-reset-xt
' ANSI-BOLD           CONSTANT _ansi-bold-xt
' ANSI-DIM            CONSTANT _ansi-dim-xt
' ANSI-ITALIC         CONSTANT _ansi-italic-xt
' ANSI-UNDERLINE      CONSTANT _ansi-ul-xt
' ANSI-BLINK          CONSTANT _ansi-blink-xt
' ANSI-REVERSE        CONSTANT _ansi-reverse-xt
' ANSI-HIDDEN         CONSTANT _ansi-hidden-xt
' ANSI-STRIKE         CONSTANT _ansi-strike-xt
' ANSI-NORMAL         CONSTANT _ansi-normal-xt
' ANSI-FG             CONSTANT _ansi-fg-xt
' ANSI-BG             CONSTANT _ansi-bg-xt
' ANSI-FG-BRIGHT      CONSTANT _ansi-fgb-xt
' ANSI-BG-BRIGHT      CONSTANT _ansi-bgb-xt
' ANSI-FG256          CONSTANT _ansi-fg256-xt
' ANSI-BG256          CONSTANT _ansi-bg256-xt
' ANSI-FG-RGB         CONSTANT _ansi-fgrgb-xt
' ANSI-BG-RGB         CONSTANT _ansi-bgrgb-xt
' ANSI-DEFAULT-FG     CONSTANT _ansi-deffg-xt
' ANSI-DEFAULT-BG     CONSTANT _ansi-defbg-xt
' ANSI-ALT-ON         CONSTANT _ansi-alton-xt
' ANSI-ALT-OFF        CONSTANT _ansi-altoff-xt
' ANSI-CURSOR-ON      CONSTANT _ansi-curon-xt
' ANSI-CURSOR-OFF     CONSTANT _ansi-curoff-xt
' ANSI-MOUSE-ON       CONSTANT _ansi-mson-xt
' ANSI-MOUSE-OFF      CONSTANT _ansi-msoff-xt
' ANSI-PASTE-ON       CONSTANT _ansi-pston-xt
' ANSI-PASTE-OFF      CONSTANT _ansi-pstoff-xt
' ANSI-QUERY-SIZE     CONSTANT _ansi-qsize-xt
' ANSI-QUERY-CURSOR   CONSTANT _ansi-qcur-xt
' ANSI-TITLE          CONSTANT _ansi-title-xt

: ANSI-AT             _ansi-at-xt _ansi-guard WITH-GUARD ;
: ANSI-UP             _ansi-up-xt _ansi-guard WITH-GUARD ;
: ANSI-DOWN           _ansi-down-xt _ansi-guard WITH-GUARD ;
: ANSI-RIGHT          _ansi-right-xt _ansi-guard WITH-GUARD ;
: ANSI-LEFT           _ansi-left-xt _ansi-guard WITH-GUARD ;
: ANSI-HOME           _ansi-home-xt _ansi-guard WITH-GUARD ;
: ANSI-COL            _ansi-col-xt _ansi-guard WITH-GUARD ;
: ANSI-SAVE           _ansi-save-xt _ansi-guard WITH-GUARD ;
: ANSI-RESTORE        _ansi-restore-xt _ansi-guard WITH-GUARD ;
: ANSI-CLEAR          _ansi-clear-xt _ansi-guard WITH-GUARD ;
: ANSI-CLEAR-EOL      _ansi-clear-eol-xt _ansi-guard WITH-GUARD ;
: ANSI-CLEAR-BOL      _ansi-clear-bol-xt _ansi-guard WITH-GUARD ;
: ANSI-CLEAR-LINE     _ansi-clear-line-xt _ansi-guard WITH-GUARD ;
: ANSI-CLEAR-EOS      _ansi-clear-eos-xt _ansi-guard WITH-GUARD ;
: ANSI-CLEAR-BOS      _ansi-clear-bos-xt _ansi-guard WITH-GUARD ;
: ANSI-SCROLL-UP      _ansi-scrup-xt _ansi-guard WITH-GUARD ;
: ANSI-SCROLL-DN      _ansi-scrdn-xt _ansi-guard WITH-GUARD ;
: ANSI-SCROLL-RGN     _ansi-scrgn-xt _ansi-guard WITH-GUARD ;
: ANSI-SCROLL-RESET   _ansi-scrrst-xt _ansi-guard WITH-GUARD ;
: ANSI-RESET          _ansi-reset-xt _ansi-guard WITH-GUARD ;
: ANSI-BOLD           _ansi-bold-xt _ansi-guard WITH-GUARD ;
: ANSI-DIM            _ansi-dim-xt _ansi-guard WITH-GUARD ;
: ANSI-ITALIC         _ansi-italic-xt _ansi-guard WITH-GUARD ;
: ANSI-UNDERLINE      _ansi-ul-xt _ansi-guard WITH-GUARD ;
: ANSI-BLINK          _ansi-blink-xt _ansi-guard WITH-GUARD ;
: ANSI-REVERSE        _ansi-reverse-xt _ansi-guard WITH-GUARD ;
: ANSI-HIDDEN         _ansi-hidden-xt _ansi-guard WITH-GUARD ;
: ANSI-STRIKE         _ansi-strike-xt _ansi-guard WITH-GUARD ;
: ANSI-NORMAL         _ansi-normal-xt _ansi-guard WITH-GUARD ;
: ANSI-FG             _ansi-fg-xt _ansi-guard WITH-GUARD ;
: ANSI-BG             _ansi-bg-xt _ansi-guard WITH-GUARD ;
: ANSI-FG-BRIGHT      _ansi-fgb-xt _ansi-guard WITH-GUARD ;
: ANSI-BG-BRIGHT      _ansi-bgb-xt _ansi-guard WITH-GUARD ;
: ANSI-FG256          _ansi-fg256-xt _ansi-guard WITH-GUARD ;
: ANSI-BG256          _ansi-bg256-xt _ansi-guard WITH-GUARD ;
: ANSI-FG-RGB         _ansi-fgrgb-xt _ansi-guard WITH-GUARD ;
: ANSI-BG-RGB         _ansi-bgrgb-xt _ansi-guard WITH-GUARD ;
: ANSI-DEFAULT-FG     _ansi-deffg-xt _ansi-guard WITH-GUARD ;
: ANSI-DEFAULT-BG     _ansi-defbg-xt _ansi-guard WITH-GUARD ;
: ANSI-ALT-ON         _ansi-alton-xt _ansi-guard WITH-GUARD ;
: ANSI-ALT-OFF        _ansi-altoff-xt _ansi-guard WITH-GUARD ;
: ANSI-CURSOR-ON      _ansi-curon-xt _ansi-guard WITH-GUARD ;
: ANSI-CURSOR-OFF     _ansi-curoff-xt _ansi-guard WITH-GUARD ;
: ANSI-MOUSE-ON       _ansi-mson-xt _ansi-guard WITH-GUARD ;
: ANSI-MOUSE-OFF      _ansi-msoff-xt _ansi-guard WITH-GUARD ;
: ANSI-PASTE-ON       _ansi-pston-xt _ansi-guard WITH-GUARD ;
: ANSI-PASTE-OFF      _ansi-pstoff-xt _ansi-guard WITH-GUARD ;
: ANSI-QUERY-SIZE     _ansi-qsize-xt _ansi-guard WITH-GUARD ;
: ANSI-QUERY-CURSOR   _ansi-qcur-xt _ansi-guard WITH-GUARD ;
: ANSI-TITLE          _ansi-title-xt _ansi-guard WITH-GUARD ;
[THEN] [THEN]
