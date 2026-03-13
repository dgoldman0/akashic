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
\    +88      (reserved)
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
88 CONSTANT _TXTA-O-RESERVED

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

\ _TXTA-INSERT ( cp -- )
\   Insert a codepoint at cursor.  Rejects if buffer would overflow.
: _TXTA-INSERT  ( cp -- )
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
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-DELETE ( -- )
\   Delete character at cursor (forward delete).
: _TXTA-DELETE  ( -- )
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
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-BACKSPACE ( -- )
: _TXTA-BACKSPACE  ( -- )
    _TXTA-CURSOR 0= IF EXIT THEN
    \ Move cursor back one codepoint
    _TXTA-CURSOR 1-
    BEGIN
        DUP 0 > IF
            DUP _TXTA-BUF-A + C@ _UTF8-CONT?
        ELSE 0 THEN
    WHILE 1- REPEAT
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-DELETE ;

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
        0 MAX
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
        \ Cursor highlight
        _TXTA-BUF-LEN _TXTA-DRW-L @ -
        _TXTA-CURSOR =
        _TXTA-W @ WDG-FOCUSED? AND IF
            CELL-A-REVERSE DRW-ATTR!
        THEN
        \ Decode one codepoint
        _TXTA-DRW-A @ _TXTA-DRW-L @
        UTF8-DECODE
        _TXTA-DRW-L ! _TXTA-DRW-A !       ( cp )
        _TXTA-DRW-ROW @ _TXTA-DRW-COL @ DRW-CHAR
        0 DRW-ATTR!
        1 _TXTA-DRW-COL +!
    REPEAT
    \ Cursor at end of line (or on the \n)
    _TXTA-BUF-LEN _TXTA-DRW-L @ -
    _TXTA-CURSOR =
    _TXTA-W @ WDG-FOCUSED? AND IF
        _TXTA-DRW-COL @ _TXTA-DRW-RW @ < IF
            CELL-A-REVERSE DRW-ATTR!
            32 _TXTA-DRW-ROW @ _TXTA-DRW-COL @ DRW-CHAR
            0 DRW-ATTR!
        THEN
    THEN
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
    DUP WDG-REGION RGN-W _TXTA-DRW-RW !
    WDG-REGION RGN-H                    ( vh )
    \ Set up buffer pointers starting at scroll-y line
    _TXTA-SCROLL _TXTA-LINE-OFF        ( vh off )
    _TXTA-BUF-A OVER + _TXTA-DRW-A !
    _TXTA-BUF-LEN SWAP - _TXTA-DRW-L !
    \ Draw visible rows
    0 ?DO
        I _TXTA-DRAW-LINE
    LOOP ;

\ =====================================================================
\  8. Internal handle
\ =====================================================================

: _TXTA-HANDLE  ( event widget -- consumed? )
    _TXTA-W !                           ( event )
    DUP @ KEY-T-SPECIAL = IF
        8 + @                           ( code )
        CASE
            KEY-LEFT      OF _TXTA-LEFT      -1 ENDOF
            KEY-RIGHT     OF _TXTA-RIGHT     -1 ENDOF
            KEY-UP        OF _TXTA-UP        -1 ENDOF
            KEY-DOWN      OF _TXTA-DOWN      -1 ENDOF
            KEY-HOME      OF _TXTA-HOME      -1 ENDOF
            KEY-END       OF _TXTA-END       -1 ENDOF
            KEY-DEL       OF _TXTA-DELETE    -1 ENDOF
            KEY-BACKSPACE OF _TXTA-BACKSPACE -1 ENDOF
            KEY-ENTER     OF 10 _TXTA-INSERT -1 ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
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
    0              OVER _TXTA-O-ON-CHANGE + ! ;

\ TXTA-SET-TEXT ( text-a text-u widget -- )
: TXTA-SET-TEXT  ( text-a text-u widget -- )
    >R
    R@ _TXTA-O-BUF-CAP + @ MIN
    DUP R@ _TXTA-O-BUF-LEN + !
    R@ _TXTA-O-BUF-A + @ SWAP CMOVE
    R@ _TXTA-O-BUF-LEN + @
    R@ _TXTA-O-CURSOR + !
    0 R@ _TXTA-O-SCROLL-Y + !
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
    WDG-DIRTY ;

\ TXTA-FREE ( widget -- )
: TXTA-FREE  ( widget -- )
    FREE ;

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

: TXTA-NEW       _txta-new-xt     _txta-guard WITH-GUARD ;
: TXTA-SET-TEXT  _txta-settext-xt _txta-guard WITH-GUARD ;
: TXTA-GET-TEXT  _txta-gettext-xt _txta-guard WITH-GUARD ;
: TXTA-ON-CHANGE _txta-onch-xt   _txta-guard WITH-GUARD ;
: TXTA-CLEAR     _txta-clear-xt  _txta-guard WITH-GUARD ;
: TXTA-FREE      _txta-free-xt   _txta-guard WITH-GUARD ;
[THEN] [THEN]
