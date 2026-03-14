\ =====================================================================
\  akashic/tui/widgets/textarea.f — Multi-Line Text Area
\ =====================================================================
\
\  A multi-line editable text area with UTF-8 support, vertical
\  scrolling, and cursor navigation.  Uses a contiguous byte buffer
\  with newlines (0x0A) as line separators.
\
\  The edit buffer is caller-provided — the widget does not allocate
\  storage for the text.
\
\  Descriptor (96 bytes):
\    +0..+32  widget header   type=WDG-T-TEXTAREA (15)
\    +40      buf-a           Address of edit buffer
\    +48      buf-cap         Buffer capacity (bytes)
\    +56      buf-len         Current content length (bytes)
\    +64      cursor          Cursor byte offset
\    +72      scroll-y        First visible line (0-based)
\    +80      on-change-xt    Callback ( widget -- ) or 0
\    +88      sel-anchor      Selection anchor byte offset (-1 = none)
\
\  Prefix: TXTA- (public), _TXTA- (internal)
\  Provider: akashic-tui-textarea
\  Dependencies: widget.f, draw.f, ../text/utf8.f, keys.f

PROVIDED akashic-tui-textarea

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../../text/utf8.f
REQUIRE ../keys.f

\ =====================================================================
\  1. Descriptor layout
\ =====================================================================

15 CONSTANT WDG-T-TEXTAREA

40 CONSTANT _TXTA-O-BUF-A
48 CONSTANT _TXTA-O-BUF-CAP
56 CONSTANT _TXTA-O-BUF-LEN
64 CONSTANT _TXTA-O-CURSOR
72 CONSTANT _TXTA-O-SCROLL-Y
80 CONSTANT _TXTA-O-ON-CHANGE
88 CONSTANT _TXTA-O-SEL-ANCHOR

96 CONSTANT _TXTA-DESC-SIZE

\ =====================================================================
\  2. Module variables (KDOS single-threaded pattern)
\ =====================================================================

VARIABLE _TXTA-W     \ current widget pointer for all internal words

\ Shortcut accessors (read from _TXTA-W)
: _TXTA-BUF-A   ( -- addr ) _TXTA-W @ _TXTA-O-BUF-A   + @ ;
: _TXTA-BUF-LEN ( -- n )    _TXTA-W @ _TXTA-O-BUF-LEN + @ ;
: _TXTA-BUF-CAP ( -- n )    _TXTA-W @ _TXTA-O-BUF-CAP + @ ;
: _TXTA-CURSOR  ( -- n )    _TXTA-W @ _TXTA-O-CURSOR  + @ ;
: _TXTA-SCROLL  ( -- n )    _TXTA-W @ _TXTA-O-SCROLL-Y + @ ;
: _TXTA-SEL-ANCHOR ( -- n ) _TXTA-W @ _TXTA-O-SEL-ANCHOR + @ ;

\ =====================================================================
\  2b. Selection helpers
\ =====================================================================

\ _TXTA-HAS-SEL? ( -- flag )
\   True if a selection is active (anchor != -1).
: _TXTA-HAS-SEL?  ( -- flag )
    _TXTA-SEL-ANCHOR -1 <> ;

\ _TXTA-SEL-CLEAR ( -- )
\   Deactivate selection.
: _TXTA-SEL-CLEAR  ( -- )
    -1 _TXTA-W @ _TXTA-O-SEL-ANCHOR + ! ;

\ _TXTA-SEL-START! ( -- )
\   If no selection is active, set anchor to current cursor position.
: _TXTA-SEL-START!  ( -- )
    _TXTA-HAS-SEL? IF EXIT THEN
    _TXTA-CURSOR _TXTA-W @ _TXTA-O-SEL-ANCHOR + ! ;

\ _TXTA-SEL-RANGE ( -- start end )
\   Return the ordered byte range of the selection.
\   Undefined if no selection — caller must check _TXTA-HAS-SEL? first.
: _TXTA-SEL-RANGE  ( -- start end )
    _TXTA-SEL-ANCHOR _TXTA-CURSOR
    2DUP > IF SWAP THEN ;

\ =====================================================================
\  3. Line utilities
\ =====================================================================

\ _TXTA-CURSOR-LINE ( -- line )
\   Count newlines from buffer start to cursor position.
: _TXTA-CURSOR-LINE  ( -- line )
    0  _TXTA-CURSOR 0 ?DO
        _TXTA-BUF-A I + C@ 10 = IF 1+ THEN
    LOOP ;

\ _TXTA-LINE-COUNT ( -- n )
\   Total number of lines (count newlines + 1).
: _TXTA-LINE-COUNT  ( -- n )
    1  _TXTA-BUF-LEN 0 ?DO
        _TXTA-BUF-A I + C@ 10 = IF 1+ THEN
    LOOP ;

\ _TXTA-SOL ( -- byte-off )
\   Byte offset of start of current line (scan back from cursor).
: _TXTA-SOL  ( -- off )
    _TXTA-CURSOR
    BEGIN
        DUP 0 > IF
            DUP 1- _TXTA-BUF-A + C@ 10 <>
        ELSE 0 THEN
    WHILE 1- REPEAT ;

\ _TXTA-EOL ( -- byte-off )
\   Byte offset of end of current line (the \n position or buf-len).
: _TXTA-EOL  ( -- off )
    _TXTA-CURSOR
    BEGIN
        DUP _TXTA-BUF-LEN < IF
            DUP _TXTA-BUF-A + C@ 10 <>
        ELSE 0 THEN
    WHILE 1+ REPEAT ;

VARIABLE _TXTA-LCNT   \ temp for _TXTA-LINE-OFF

\ _TXTA-LINE-OFF ( target-line -- byte-off )
\   Find byte offset of start of the given line number (0-based).
: _TXTA-LINE-OFF  ( target-line -- byte-off )
    DUP 0= IF DROP 0 EXIT THEN
    _TXTA-LCNT !
    _TXTA-BUF-LEN 0 ?DO
        _TXTA-BUF-A I + C@ 10 = IF
            _TXTA-LCNT @ 1- DUP _TXTA-LCNT !
            0= IF I 1+ UNLOOP EXIT THEN
        THEN
    LOOP
    _TXTA-BUF-LEN ;             \ target beyond end

\ _TXTA-CURSOR-COL ( -- col )
\   Count codepoints from start of current line to cursor.
: _TXTA-CURSOR-COL  ( -- col )
    _TXTA-SOL                   ( sol-off )
    0 >R                        ( sol  R: count )
    BEGIN DUP _TXTA-CURSOR < WHILE
        DUP _TXTA-BUF-A + C@ _UTF8-SEQLEN
        DUP 0= IF DROP 1 THEN
        +
        R> 1+ >R
    REPEAT
    DROP R> ;

VARIABLE _TXTA-TCOL    \ temp for _TXTA-COL-OFF

\ _TXTA-COL-OFF ( line-off target-col -- byte-off )
\   Advance from line-start by target-col codepoints, stopping
\   at newline or end of buffer.
: _TXTA-COL-OFF  ( line-off target-col -- byte-off )
    _TXTA-TCOL !
    BEGIN
        _TXTA-TCOL @ 0 >
        OVER _TXTA-BUF-LEN < AND
    WHILE
        DUP _TXTA-BUF-A + C@ 10 = IF EXIT THEN
        DUP _TXTA-BUF-A + C@ _UTF8-SEQLEN
        DUP 0= IF DROP 1 THEN
        +
        _TXTA-TCOL @ 1- _TXTA-TCOL !
    REPEAT ;

\ =====================================================================
\  4. Edit operations
\ =====================================================================

CREATE _TXTA-INS-BUF 4 ALLOT
VARIABLE _TXTA-INS-SZ

\ _TXTA-FIRE-CHANGE ( -- )
\   Invoke the on-change callback if registered.
: _TXTA-FIRE-CHANGE  ( -- )
    _TXTA-W @ _TXTA-O-ON-CHANGE + @ ?DUP IF
        _TXTA-W @ SWAP EXECUTE
    THEN ;

\ _TXTA-DEL-RANGE ( start len -- )
\   Delete len bytes starting at byte offset start.  Low-level:
\   shifts tail left, updates buf-len.  Does NOT fire change or dirty.
VARIABLE _TXTA-DR-START
VARIABLE _TXTA-DR-LEN
: _TXTA-DEL-RANGE  ( start len -- )
    DUP 0= IF 2DROP EXIT THEN
    _TXTA-DR-LEN !  _TXTA-DR-START !
    _TXTA-BUF-A _TXTA-DR-START @ + _TXTA-DR-LEN @ +   \ src
    _TXTA-BUF-A _TXTA-DR-START @ +                     \ dst
    _TXTA-BUF-LEN _TXTA-DR-START @ - _TXTA-DR-LEN @ - \ count
    DUP 0> IF CMOVE ELSE DROP 2DROP THEN
    _TXTA-W @ _TXTA-O-BUF-LEN + @
    _TXTA-DR-LEN @ - _TXTA-W @ _TXTA-O-BUF-LEN + ! ;

\ _TXTA-DEL-SEL ( -- deleted? )
\   If a selection is active, delete it, place cursor at start,
\   clear selection, return TRUE.  Otherwise return FALSE.
: _TXTA-DEL-SEL  ( -- flag )
    _TXTA-HAS-SEL? 0= IF 0 EXIT THEN
    _TXTA-SEL-RANGE                  ( start end )
    OVER -                           ( start len )
    2DUP _TXTA-DEL-RANGE
    DROP                             ( start )
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-SEL-CLEAR
    -1 ;

\ _TXTA-INS-STR ( addr len -- )
\   Insert a string of bytes at cursor.  Used by paste.
\   Assumes selection already handled.  Rejects if buffer would overflow.
: _TXTA-INS-STR  ( addr len -- )
    DUP _TXTA-BUF-LEN + _TXTA-BUF-CAP > IF 2DROP EXIT THEN
    DUP >R                                  ( addr len  R: len )
    \ Shift tail right by len
    _TXTA-BUF-A _TXTA-CURSOR +              \ src
    DUP R@ +                                \ dst
    _TXTA-BUF-LEN _TXTA-CURSOR -            \ count
    DUP 0 > IF CMOVE> ELSE DROP 2DROP THEN
    \ Copy string into gap              ( addr len  R: len )
    DROP                                ( addr  R: len )
    _TXTA-BUF-A _TXTA-CURSOR +  R@ CMOVE
    \ Update len + cursor
    R@ _TXTA-W @ _TXTA-O-BUF-LEN + @ +
    _TXTA-W @ _TXTA-O-BUF-LEN + !
    R> _TXTA-W @ _TXTA-O-CURSOR + @ +
    _TXTA-W @ _TXTA-O-CURSOR + ! ;

\ _TXTA-INSERT ( cp -- )
\   Insert a codepoint at cursor.  If a selection is active, deletes
\   it first (replacing selection).  Rejects if buffer would overflow.
: _TXTA-INSERT  ( cp -- )
    _TXTA-DEL-SEL DROP
    _TXTA-INS-BUF UTF8-ENCODE
    _TXTA-INS-BUF - _TXTA-INS-SZ !
    _TXTA-BUF-LEN _TXTA-INS-SZ @ +
    _TXTA-BUF-CAP > IF EXIT THEN
    \ Shift bytes right from cursor
    _TXTA-BUF-A _TXTA-CURSOR +             \ src
    DUP _TXTA-INS-SZ @ +                   \ dst
    _TXTA-BUF-LEN _TXTA-CURSOR -           \ count
    DUP 0 > IF CMOVE> ELSE DROP 2DROP THEN
    \ Copy encoded bytes into gap
    _TXTA-INS-BUF
    _TXTA-BUF-A _TXTA-CURSOR +
    _TXTA-INS-SZ @ CMOVE
    \ Update len + cursor
    _TXTA-INS-SZ @ _TXTA-W @ _TXTA-O-BUF-LEN + @ +
    _TXTA-W @ _TXTA-O-BUF-LEN + !
    _TXTA-INS-SZ @ _TXTA-W @ _TXTA-O-CURSOR + @ +
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-FIRE-CHANGE
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-DELETE ( -- )
\   Delete character at cursor (forward delete).
\   If selection active, deletes selection instead.
: _TXTA-DELETE  ( -- )
    _TXTA-DEL-SEL IF
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
    _TXTA-CURSOR _TXTA-BUF-LEN >= IF EXIT THEN
    _TXTA-BUF-A _TXTA-CURSOR +             ( addr )
    DUP C@ _UTF8-SEQLEN
    DUP 0= IF DROP 1 THEN                  ( addr cpsize )
    >R                                       ( addr  R: cpsize )
    DUP R@ +                                \ src = addr + cpsize
    SWAP                                     \ dst = addr
    _TXTA-BUF-LEN _TXTA-CURSOR - R@ -      \ count
    DUP 0> IF CMOVE ELSE DROP 2DROP THEN
    _TXTA-W @ _TXTA-O-BUF-LEN + @
    R> - _TXTA-W @ _TXTA-O-BUF-LEN + !
    _TXTA-FIRE-CHANGE
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-BACKSPACE ( -- )
\   If selection active, delete selection.  Otherwise delete one
\   codepoint before cursor.
: _TXTA-BACKSPACE  ( -- )
    _TXTA-DEL-SEL IF
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
    _TXTA-CURSOR 0= IF EXIT THEN
    \ Move cursor back one codepoint
    _TXTA-CURSOR 1-
    BEGIN
        DUP 0 > IF
            DUP _TXTA-BUF-A + C@ _UTF8-CONT?
        ELSE 0 THEN
    WHILE 1- REPEAT
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-DELETE
    _TXTA-FIRE-CHANGE ;

\ =====================================================================
\  5. Cursor movement
\ =====================================================================

: _TXTA-LEFT  ( -- )
    _TXTA-CURSOR 0= IF EXIT THEN
    _TXTA-CURSOR 1-
    BEGIN
        DUP 0 > IF
            DUP _TXTA-BUF-A + C@ _UTF8-CONT?
        ELSE 0 THEN
    WHILE 1- REPEAT
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-RIGHT  ( -- )
    _TXTA-CURSOR _TXTA-BUF-LEN >= IF EXIT THEN
    _TXTA-BUF-A _TXTA-CURSOR + C@ _UTF8-SEQLEN
    DUP 0= IF DROP 1 THEN
    _TXTA-CURSOR + _TXTA-BUF-LEN MIN
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-HOME  ( -- )
    _TXTA-SOL
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-END  ( -- )
    _TXTA-EOL
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-UP  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 0= IF DROP EXIT THEN           \ already on line 0
    _TXTA-CURSOR-COL                    ( cline ccol )
    SWAP 1- _TXTA-LINE-OFF             ( ccol target-line-off )
    SWAP _TXTA-COL-OFF                  ( byte-off )
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-DOWN  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 1+ _TXTA-LINE-COUNT >= IF DROP EXIT THEN
    _TXTA-CURSOR-COL                    ( cline ccol )
    SWAP 1+ _TXTA-LINE-OFF             ( ccol target-line-off )
    SWAP _TXTA-COL-OFF                  ( byte-off )
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-PGUP ( -- )
\   Move cursor up by viewport height lines.
: _TXTA-PGUP  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 0= IF DROP EXIT THEN
    _TXTA-CURSOR-COL                    ( cline ccol )
    SWAP
    _TXTA-W @ WDG-REGION RGN-H -       ( ccol target-line )
    DUP 0< IF DROP 0 THEN
    _TXTA-LINE-OFF                      ( ccol target-off )
    SWAP _TXTA-COL-OFF
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-PGDN ( -- )
\   Move cursor down by viewport height lines.
: _TXTA-PGDN  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 1+ _TXTA-LINE-COUNT >= IF DROP EXIT THEN
    _TXTA-CURSOR-COL                    ( cline ccol )
    SWAP
    _TXTA-W @ WDG-REGION RGN-H +       ( ccol target-line )
    _TXTA-LINE-COUNT 1- MIN             ( ccol clamped )
    _TXTA-LINE-OFF                      ( ccol target-off )
    SWAP _TXTA-COL-OFF
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

\ =====================================================================
\  5b. Word-level movement (Ctrl+Left / Ctrl+Right)
\ =====================================================================

\ _TXTA-IS-WORD-CHAR ( byte -- flag )
\   True if the byte is a word character (alphanumeric or underscore).
: _TXTA-IS-WORD-CHAR  ( b -- flag )
    DUP [CHAR] a >= OVER [CHAR] z <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] A >= OVER [CHAR] Z <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND IF DROP -1 EXIT THEN
    [CHAR] _ = ;

\ _TXTA-WORD-LEFT ( -- )
\   Move cursor left to the start of the previous word.
: _TXTA-WORD-LEFT  ( -- )
    _TXTA-CURSOR 0= IF EXIT THEN
    _TXTA-CURSOR
    \ Phase 1: skip non-word chars going left
    BEGIN
        DUP 0 > IF
            DUP 1- _TXTA-BUF-A + C@ _TXTA-IS-WORD-CHAR 0=
        ELSE 0 THEN
    WHILE 1- REPEAT
    \ Phase 2: skip word chars going left
    BEGIN
        DUP 0 > IF
            DUP 1- _TXTA-BUF-A + C@ _TXTA-IS-WORD-CHAR
        ELSE 0 THEN
    WHILE 1- REPEAT
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-WORD-RIGHT ( -- )
\   Move cursor right to the start of the next word.
: _TXTA-WORD-RIGHT  ( -- )
    _TXTA-CURSOR _TXTA-BUF-LEN >= IF EXIT THEN
    _TXTA-CURSOR
    \ Phase 1: skip word chars going right
    BEGIN
        DUP _TXTA-BUF-LEN < IF
            DUP _TXTA-BUF-A + C@ _TXTA-IS-WORD-CHAR
        ELSE 0 THEN
    WHILE 1+ REPEAT
    \ Phase 2: skip non-word chars going right
    BEGIN
        DUP _TXTA-BUF-LEN < IF
            DUP _TXTA-BUF-A + C@ _TXTA-IS-WORD-CHAR 0=
        ELSE 0 THEN
    WHILE 1+ REPEAT
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-W @ WDG-DIRTY ;

\ =====================================================================
\  6. Scroll adjustment
\ =====================================================================

\ _TXTA-SCROLL-ADJ ( -- )
\   Ensure cursor line is visible within viewport height.
: _TXTA-SCROLL-ADJ  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP _TXTA-SCROLL < IF
        \ Cursor above viewport — scroll up
        _TXTA-W @ _TXTA-O-SCROLL-Y + !
        EXIT
    THEN
    _TXTA-W @ WDG-REGION RGN-H         ( cline vh )
    _TXTA-SCROLL + OVER SWAP           ( cline cline scroll+vh )
    <= IF
        \ Cursor at or below viewport bottom — scroll down
        _TXTA-W @ WDG-REGION RGN-H - 1+
        DUP 0< IF DROP 0 THEN
        _TXTA-W @ _TXTA-O-SCROLL-Y + !
        EXIT
    THEN
    DROP ;

\ =====================================================================
\  7. Internal draw
\ =====================================================================

VARIABLE _TXTA-DRW-A      \ pointer into buffer
VARIABLE _TXTA-DRW-L      \ remaining bytes
VARIABLE _TXTA-DRW-RW     \ region width
VARIABLE _TXTA-DRW-COL    \ current column during line draw
VARIABLE _TXTA-DRW-ROW    \ current row
VARIABLE _TXTA-DRW-CDONE  \ cursor already rendered flag
VARIABLE _TXTA-DRW-SELS   \ selection start byte offset (or -1)
VARIABLE _TXTA-DRW-SELE   \ selection end byte offset

\ _TXTA-DRW-BYTEOFF ( -- off )
\   Current byte offset into buffer during draw (buf-len - remaining).
: _TXTA-DRW-BYTEOFF  ( -- off )
    _TXTA-BUF-LEN _TXTA-DRW-L @ - ;

\ _TXTA-DRW-IN-SEL? ( -- flag )
\   True if current draw byte offset is inside the selection range.
: _TXTA-DRW-IN-SEL?  ( -- flag )
    _TXTA-DRW-SELS @ -1 = IF 0 EXIT THEN
    _TXTA-DRW-BYTEOFF
    DUP _TXTA-DRW-SELS @ >= SWAP _TXTA-DRW-SELE @ < AND ;

\ _TXTA-DRAW-LINE ( row -- )
\   Draw one text line at the given viewport row.
\   Reads from _TXTA-DRW-A / _TXTA-DRW-L.
\   Advances pointers past the newline.
: _TXTA-DRAW-LINE  ( row -- )
    _TXTA-DRW-ROW !
    \ Clear row
    32 _TXTA-DRW-ROW @ 0 _TXTA-DRW-RW @ DRW-HLINE
    0 _TXTA-DRW-COL !
    BEGIN
        _TXTA-DRW-COL @ _TXTA-DRW-RW @ <
        _TXTA-DRW-L @ 0 > AND
        _TXTA-DRW-A @ C@ 10 <> AND
    WHILE
        \ Selection highlight
        _TXTA-DRW-IN-SEL? IF
            CELL-A-REVERSE DRW-ATTR!
        THEN
        \ Cursor highlight (overrides selection attr — both use reverse)
        _TXTA-DRW-CDONE @ 0= IF
        _TXTA-DRW-BYTEOFF
        _TXTA-CURSOR =
        _TXTA-W @ WDG-FOCUSED? AND IF
            CELL-A-REVERSE DRW-ATTR!
            -1 _TXTA-DRW-CDONE !
        THEN THEN
        \ Decode one codepoint
        _TXTA-DRW-A @ _TXTA-DRW-L @
        UTF8-DECODE
        _TXTA-DRW-L ! _TXTA-DRW-A !       ( cp )
        _TXTA-DRW-ROW @ _TXTA-DRW-COL @ DRW-CHAR
        0 DRW-ATTR!
        1 _TXTA-DRW-COL +!
    REPEAT
    \ Cursor at end of line (or on the \n)
    _TXTA-DRW-CDONE @ 0= IF
    _TXTA-DRW-BYTEOFF
    _TXTA-CURSOR =
    _TXTA-W @ WDG-FOCUSED? AND IF
        _TXTA-DRW-COL @ _TXTA-DRW-RW @ < IF
            CELL-A-REVERSE DRW-ATTR!
            32 _TXTA-DRW-ROW @ _TXTA-DRW-COL @ DRW-CHAR
            0 DRW-ATTR!
            -1 _TXTA-DRW-CDONE !
        THEN
    THEN THEN
    \ Skip past newline
    _TXTA-DRW-L @ 0 > IF
        _TXTA-DRW-A @ C@ 10 = IF
            1 _TXTA-DRW-A +!
            -1 _TXTA-DRW-L +!
        THEN
    THEN ;

\ _TXTA-DRAW ( widget -- )
: _TXTA-DRAW  ( widget -- )
    DUP _TXTA-W !
    _TXTA-SCROLL-ADJ
    \ Compute selection range for draw pass
    _TXTA-HAS-SEL? IF
        _TXTA-SEL-RANGE _TXTA-DRW-SELE ! _TXTA-DRW-SELS !
    ELSE
        -1 _TXTA-DRW-SELS !
    THEN
    DUP WDG-REGION RGN-W _TXTA-DRW-RW !
    WDG-REGION RGN-H                    ( vh )
    \ Set up buffer pointers starting at scroll-y line
    _TXTA-SCROLL _TXTA-LINE-OFF        ( vh off )
    _TXTA-BUF-A OVER + _TXTA-DRW-A !
    _TXTA-BUF-LEN SWAP - _TXTA-DRW-L !
    \ Draw visible rows
    0 _TXTA-DRW-CDONE !
    0 ?DO
        I _TXTA-DRAW-LINE
    LOOP ;

\ =====================================================================
\  8. Internal handle
\ =====================================================================

VARIABLE _TXTA-HND-MODS   \ cached modifier flags for current event

\ _TXTA-MOV-PRE -- call before every cursor-movement dispatch.
\ If Shift held, anchors selection (start if no sel yet); otherwise clears.
: _TXTA-MOV-PRE  ( -- )
    _TXTA-HND-MODS @ KEY-MOD-SHIFT AND IF
        _TXTA-HAS-SEL? 0= IF _TXTA-SEL-START! THEN
    ELSE
        _TXTA-SEL-CLEAR
    THEN ;

\ _TXTA-SELECT-ALL -- select entire buffer
: _TXTA-SELECT-ALL  ( -- )
    0 _TXTA-W @ _TXTA-O-SEL-ANCHOR + !
    _TXTA-BUF-LEN _TXTA-W @ _TXTA-O-CURSOR + ! ;

: _TXTA-HANDLE  ( event widget -- consumed? )
    _TXTA-W !                           ( event )
    DUP 16 + @ _TXTA-HND-MODS !        \ cache modifiers
    DUP @ KEY-T-SPECIAL = IF
        DUP 16 + @                      ( ev mods )
        SWAP 8 + @                      ( mods code )
        \ Ctrl+Left / Ctrl+Right = word movement (shift-aware)
        OVER KEY-MOD-CTRL AND IF
            DUP KEY-LEFT = IF
                2DROP _TXTA-MOV-PRE _TXTA-WORD-LEFT -1 EXIT
            THEN
            DUP KEY-RIGHT = IF
                2DROP _TXTA-MOV-PRE _TXTA-WORD-RIGHT -1 EXIT
            THEN
        THEN
        NIP                             ( code )
        CASE
            KEY-LEFT      OF _TXTA-MOV-PRE _TXTA-LEFT      -1 ENDOF
            KEY-RIGHT     OF _TXTA-MOV-PRE _TXTA-RIGHT     -1 ENDOF
            KEY-UP        OF _TXTA-MOV-PRE _TXTA-UP        -1 ENDOF
            KEY-DOWN      OF _TXTA-MOV-PRE _TXTA-DOWN      -1 ENDOF
            KEY-HOME      OF _TXTA-MOV-PRE _TXTA-HOME      -1 ENDOF
            KEY-END       OF _TXTA-MOV-PRE _TXTA-END       -1 ENDOF
            KEY-PGUP      OF _TXTA-MOV-PRE _TXTA-PGUP      -1 ENDOF
            KEY-PGDN      OF _TXTA-MOV-PRE _TXTA-PGDN      -1 ENDOF
            KEY-DEL       OF _TXTA-DELETE    -1 ENDOF
            KEY-BACKSPACE OF _TXTA-BACKSPACE -1 ENDOF
            KEY-ENTER     OF 10 _TXTA-INSERT -1 ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
        DUP 16 + @ KEY-MOD-CTRL AND IF
            8 + @                       ( code -- Ctrl+letter )
            DUP [CHAR] a = IF          \ Ctrl+A → select all
                DROP _TXTA-SELECT-ALL -1 EXIT
            THEN
            \ Ctrl+C / Ctrl+X / Ctrl+V / Ctrl+S / Ctrl+O → not consumed (app layer)
            DUP [CHAR] c = IF DROP 0 EXIT THEN
            DUP [CHAR] x = IF DROP 0 EXIT THEN
            DUP [CHAR] v = IF DROP 0 EXIT THEN
            DUP [CHAR] s = IF DROP 0 EXIT THEN
            DUP [CHAR] o = IF DROP 0 EXIT THEN
            DROP 0 EXIT
        THEN
        8 + @                           ( codepoint )
        DUP 32 >= IF
            _TXTA-INSERT -1 EXIT
        THEN
        DUP 8 = IF
            DROP _TXTA-BACKSPACE -1 EXIT
        THEN
        DUP 13 = IF
            DROP 10 _TXTA-INSERT -1 EXIT
        THEN
        DROP 0 EXIT
    THEN
    DROP 0 ;

\ =====================================================================
\  9. Constructor / Public API
\ =====================================================================

\ TXTA-NEW ( rgn buf cap -- widget )
: TXTA-NEW  ( rgn buf cap -- widget )
    >R >R
    _TXTA-DESC-SIZE ALLOCATE
    0<> ABORT" TXTA-NEW: alloc"
    \ Header
    WDG-T-TEXTAREA OVER _WDG-O-TYPE      + !
    SWAP           OVER _WDG-O-REGION    + !
    ['] _TXTA-DRAW   OVER _WDG-O-DRAW-XT   + !
    ['] _TXTA-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                   OVER _WDG-O-FLAGS     + !
    \ Textarea fields
    R>             OVER _TXTA-O-BUF-A     + !
    R>             OVER _TXTA-O-BUF-CAP   + !
    0              OVER _TXTA-O-BUF-LEN   + !
    0              OVER _TXTA-O-CURSOR    + !
    0              OVER _TXTA-O-SCROLL-Y  + !
    0              OVER _TXTA-O-ON-CHANGE + !
    -1             OVER _TXTA-O-SEL-ANCHOR + ! ;

\ TXTA-SET-TEXT ( text-a text-u widget -- )
: TXTA-SET-TEXT  ( text-a text-u widget -- )
    >R
    R@ _TXTA-O-BUF-CAP + @ MIN
    DUP R@ _TXTA-O-BUF-LEN + !
    R@ _TXTA-O-BUF-A + @ SWAP CMOVE
    R@ _TXTA-O-BUF-LEN + @
    R@ _TXTA-O-CURSOR + !
    0 R@ _TXTA-O-SCROLL-Y + !
    -1 R@ _TXTA-O-SEL-ANCHOR + !
    R> WDG-DIRTY ;

\ TXTA-GET-TEXT ( widget -- addr len )
: TXTA-GET-TEXT  ( widget -- addr len )
    DUP _TXTA-O-BUF-A + @
    SWAP _TXTA-O-BUF-LEN + @ ;

\ TXTA-ON-CHANGE ( xt widget -- )
: TXTA-ON-CHANGE  ( xt widget -- )
    _TXTA-O-ON-CHANGE + ! ;

\ TXTA-CLEAR ( widget -- )
: TXTA-CLEAR  ( widget -- )
    0 OVER _TXTA-O-BUF-LEN + !
    0 OVER _TXTA-O-CURSOR + !
    0 OVER _TXTA-O-SCROLL-Y + !
    -1 OVER _TXTA-O-SEL-ANCHOR + !
    WDG-DIRTY ;

\ TXTA-FREE ( widget -- )
: TXTA-FREE  ( widget -- )
    FREE ;

\ TXTA-CURSOR-LINE ( widget -- line )
\   Return 0-based cursor line number.
: TXTA-CURSOR-LINE  ( widget -- line )
    DUP _TXTA-W ! _TXTA-CURSOR-LINE ;

\ TXTA-CURSOR-COL ( widget -- col )
\   Return 0-based cursor column (codepoint count from SOL).
: TXTA-CURSOR-COL  ( widget -- col )
    DUP _TXTA-W ! _TXTA-CURSOR-COL ;

\ TXTA-GET-SEL ( widget -- addr len | 0 0 )
\   Return the selected text range.  Returns 0 0 if no selection.
: TXTA-GET-SEL  ( widget -- addr len | 0 0 )
    DUP _TXTA-W !
    _TXTA-HAS-SEL? 0= IF DROP 0 0 EXIT THEN
    _TXTA-SEL-RANGE              ( start end )
    OVER -                       ( start len )
    SWAP _TXTA-BUF-A +           ( len addr )  \ addr = buf + start
    SWAP ;

\ TXTA-DEL-SEL ( widget -- flag )
\   Delete the selected text.  Returns TRUE if a selection existed.
: TXTA-DEL-SEL  ( widget -- flag )
    DUP _TXTA-W !
    _TXTA-DEL-SEL DUP IF
        _TXTA-FIRE-CHANGE
        _TXTA-W @ WDG-DIRTY
    THEN ;

\ TXTA-INS-STR ( addr len widget -- )
\   Insert a string at cursor.  Deletes any active selection first.
: TXTA-INS-STR  ( addr len widget -- )
    DUP _TXTA-W !
    _TXTA-DEL-SEL DROP
    ROT ROT _TXTA-INS-STR
    _TXTA-FIRE-CHANGE
    _TXTA-W @ WDG-DIRTY ;

\ TXTA-SELECT-ALL ( widget -- )
\   Select the entire buffer.
: TXTA-SELECT-ALL  ( widget -- )
    DUP _TXTA-W ! _TXTA-SELECT-ALL ;

\ =====================================================================
\  10. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _txta-guard

' TXTA-NEW       CONSTANT _txta-new-xt
' TXTA-SET-TEXT  CONSTANT _txta-settext-xt
' TXTA-GET-TEXT  CONSTANT _txta-gettext-xt
' TXTA-ON-CHANGE CONSTANT _txta-onch-xt
' TXTA-CLEAR     CONSTANT _txta-clear-xt
' TXTA-FREE      CONSTANT _txta-free-xt
' TXTA-CURSOR-LINE CONSTANT _txta-curline-xt
' TXTA-CURSOR-COL  CONSTANT _txta-curcol-xt
' TXTA-GET-SEL   CONSTANT _txta-getsel-xt
' TXTA-DEL-SEL   CONSTANT _txta-delsel-xt
' TXTA-INS-STR   CONSTANT _txta-insstr-xt
' TXTA-SELECT-ALL CONSTANT _txta-selall-xt

: TXTA-NEW       _txta-new-xt     _txta-guard WITH-GUARD ;
: TXTA-SET-TEXT  _txta-settext-xt _txta-guard WITH-GUARD ;
: TXTA-GET-TEXT  _txta-gettext-xt _txta-guard WITH-GUARD ;
: TXTA-ON-CHANGE _txta-onch-xt   _txta-guard WITH-GUARD ;
: TXTA-CLEAR     _txta-clear-xt  _txta-guard WITH-GUARD ;
: TXTA-FREE      _txta-free-xt   _txta-guard WITH-GUARD ;
: TXTA-CURSOR-LINE _txta-curline-xt _txta-guard WITH-GUARD ;
: TXTA-CURSOR-COL  _txta-curcol-xt  _txta-guard WITH-GUARD ;
: TXTA-GET-SEL   _txta-getsel-xt  _txta-guard WITH-GUARD ;
: TXTA-DEL-SEL   _txta-delsel-xt  _txta-guard WITH-GUARD ;
: TXTA-INS-STR   _txta-insstr-xt  _txta-guard WITH-GUARD ;
: TXTA-SELECT-ALL _txta-selall-xt _txta-guard WITH-GUARD ;
[THEN] [THEN]
