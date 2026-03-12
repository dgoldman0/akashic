\ =====================================================================
\  akashic/tui/input.f — Single-line Text Input Field
\ =====================================================================
\
\  A single-line editable text field with cursor, supporting:
\    - Character insertion (UTF-8 aware)
\    - Backspace, Delete
\    - Cursor movement: left, right, Home, End
\    - Horizontal scrolling when content exceeds region width
\    - Placeholder text (shown when buffer is empty)
\    - Submit callback on Enter
\    - Programmatic get/set of content
\
\  The edit buffer is caller-provided — the widget does not allocate
\  storage for the text.  The caller decides where the memory lives
\  (stack, dictionary, XMEM).
\
\  Input Descriptor (header + 8 cells = 104 bytes):
\    +0..+32  widget header   type=WDG-T-INPUT
\    +40      buf-addr        Address of edit buffer
\    +48      buf-cap         Buffer capacity (bytes)
\    +56      buf-len         Current content length (bytes)
\    +64      cursor          Cursor position (byte offset)
\    +72      scroll          Horizontal scroll offset (columns)
\    +80      placeholder-a   Placeholder text address
\    +88      placeholder-u   Placeholder text length
\    +96      submit-xt       Callback on Enter ( widget -- )
\
\  Prefix: INP- (public), _INP- (internal)
\  Provider: akashic-tui-input
\  Dependencies: widget.f, draw.f, ../text/utf8.f, keys.f

PROVIDED akashic-tui-input

REQUIRE widget.f
REQUIRE draw.f
REQUIRE ../text/utf8.f
REQUIRE keys.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _INP-O-BUF-A        \ buffer address
48 CONSTANT _INP-O-BUF-CAP      \ buffer capacity (bytes)
56 CONSTANT _INP-O-BUF-LEN      \ current content length (bytes)
64 CONSTANT _INP-O-CURSOR        \ cursor byte offset
72 CONSTANT _INP-O-SCROLL        \ scroll offset (columns)
80 CONSTANT _INP-O-PH-A          \ placeholder text address
88 CONSTANT _INP-O-PH-U          \ placeholder text length
96 CONSTANT _INP-O-SUBMIT-XT     \ submit callback xt (0 = none)

104 CONSTANT _INP-DESC-SIZE       \ total descriptor size

\ =====================================================================
\ 2. UTF-8 cursor helpers
\ =====================================================================

\ _INP-BYTE-TO-COL ( buf-a byte-off -- cols )
\   Count codepoints from start of buffer to byte offset.
\   This gives the column (character) position of the cursor.
: _INP-BYTE-TO-COL  ( buf-a byte-off -- cols )
    0 >R                                    \ R: count
    BEGIN DUP 0 > WHILE
        OVER C@ _UTF8-SEQLEN               \ ( addr rem seqlen )
        DUP 0= IF DROP 1 THEN              \ treat invalid as 1 byte
        ROT OVER + -ROT                     \ addr += seqlen
        -                                   \ rem -= seqlen
        R> 1+ >R                            \ count++
    REPEAT
    2DROP R> ;

\ _INP-PREV-CP ( buf-a cursor -- cursor' )
\   Move cursor back by one UTF-8 character.
\   buf-a is start of buffer, cursor is current byte offset.
\   Returns new byte offset (or 0 if already at start).
: _INP-PREV-CP  ( buf-a cursor -- cursor' )
    DUP 0= IF NIP EXIT THEN               \ already at start
    1-                                      \ ( buf-a off )
    BEGIN
        DUP 0 > IF
            OVER OVER + C@ _UTF8-CONT?     \ continuation byte?
        ELSE
            0                               \ at position 0, stop
        THEN
    WHILE
        1-
    REPEAT
    NIP ;

\ _INP-NEXT-CP ( buf-a buf-len cursor -- cursor' )
\   Move cursor forward by one UTF-8 character.
\   Returns new byte offset (or buf-len if already at end).
: _INP-NEXT-CP  ( buf-a buf-len cursor -- cursor' )
    2DUP >= IF                             \ at or past end
        NIP NIP EXIT
    THEN
    SWAP >R                                \ ( buf-a cursor  R: buf-len )
    OVER OVER + C@ _UTF8-SEQLEN           \ ( buf-a cursor seqlen )
    DUP 0= IF DROP 1 THEN                 \ treat invalid as 1
    + NIP                                  \ cursor + seqlen
    DUP R> MIN ;                           \ clamp to buf-len

\ =====================================================================
\ 3. Edit operations
\ =====================================================================

\ _INP-INSERT ( cp widget -- )
\   Insert codepoint at cursor position.
\   Rejects insertion if buffer would overflow capacity.
VARIABLE _INP-INS-TMP
CREATE _INP-INS-BUF 4 ALLOT               \ temp encode buffer (max 4 bytes)

: _INP-INSERT  ( cp widget -- )
    SWAP                                    \ ( widget cp )
    _INP-INS-BUF UTF8-ENCODE               \ ( widget buf' )
    _INP-INS-BUF - _INP-INS-TMP !          \ byte count of encoded cp
    \ Check capacity
    DUP _INP-O-BUF-LEN + @
    _INP-INS-TMP @ +                        \ new length
    OVER _INP-O-BUF-CAP + @
    > IF DROP EXIT THEN                     \ would overflow — reject
    \ Shift bytes right from cursor to make room
    DUP >R                                  \ R: widget
    R@ _INP-O-BUF-A + @
    R@ _INP-O-CURSOR + @ +                 \ src = buf + cursor
    DUP _INP-INS-TMP @ +                   \ dst = src + encoded-bytes
    R@ _INP-O-BUF-LEN + @
    R@ _INP-O-CURSOR + @ -                 \ count = len - cursor
    DUP 0 > IF
        \ CMOVE> ( src dst u -- ) copies high-to-low for rightward shift
        CMOVE>                              \ shift right safely
    ELSE
        DROP 2DROP                          \ nothing to shift
    THEN
    DROP                                    \ drop widget copy
    \ Copy encoded bytes into gap
    _INP-INS-BUF
    R@ _INP-O-BUF-A + @
    R@ _INP-O-CURSOR + @ +                 \ dst = buf + cursor
    _INP-INS-TMP @
    CMOVE                                   \ copy
    \ Update len and cursor
    _INP-INS-TMP @
    R@ _INP-O-BUF-LEN + @ + R@ _INP-O-BUF-LEN + !
    _INP-INS-TMP @
    R@ _INP-O-CURSOR + @ + R@ _INP-O-CURSOR + !
    R> WDG-DIRTY ;

\ _INP-DELETE ( widget -- )
\   Delete character at cursor (forward delete).
: _INP-DELETE  ( widget -- )
    >R
    R@ _INP-O-CURSOR + @                   \ cursor
    R@ _INP-O-BUF-LEN + @                  \ ( cursor len )
    2DUP >= IF 2DROP R> DROP EXIT THEN      \ cursor at end — nothing to delete
    \ addr = buf + cursor
    R@ _INP-O-BUF-A + @  2 PICK +          \ ( cursor len addr )
    \ Find byte length of character at cursor
    DUP C@ _UTF8-SEQLEN                    \ ( cursor len addr seqlen )
    DUP 0= IF DROP 1 THEN                  \ treat invalid as 1 byte
    >R                                      \ ( cursor len addr ) R: widget cpbytes
    \ count = len - cursor - cpbytes
    SWAP ROT - R@ -                         \ ( addr count )
    DUP 0> IF
        \ CMOVE ( src dst u -- )
        OVER R@ +                           \ src = addr + cpbytes ( addr count src )
        2 PICK                              \ dst = addr           ( addr count src addr )
        ROT                                 \ ( addr src addr count )
        CMOVE                               \ ( addr )
    ELSE
        DROP                                \ ( addr )
    THEN
    DROP                                    \ ( )
    \ Update len: new-len = old-len - cpbytes
    R>  R@ _INP-O-BUF-LEN + @ SWAP -
    R@ _INP-O-BUF-LEN + !
    R> WDG-DIRTY ;

\ _INP-BACKSPACE ( widget -- )
\   Delete character before cursor.
: _INP-BACKSPACE  ( widget -- )
    DUP _INP-O-CURSOR + @ 0= IF DROP EXIT THEN  \ already at start
    \ Move cursor back one cp, then delete forward
    DUP DUP _INP-O-BUF-A + @
    OVER _INP-O-CURSOR + @
    _INP-PREV-CP                            \ ( widget widget newcur )
    SWAP _INP-O-CURSOR + !                  \ update cursor
    _INP-DELETE ;

\ _INP-LEFT ( widget -- )
: _INP-LEFT  ( widget -- )
    DUP _INP-O-CURSOR + @ 0= IF DROP EXIT THEN
    DUP DUP _INP-O-BUF-A + @
    OVER _INP-O-CURSOR + @
    _INP-PREV-CP
    SWAP _INP-O-CURSOR + !
    WDG-DIRTY ;

\ _INP-RIGHT ( widget -- )
: _INP-RIGHT  ( widget -- )
    DUP DUP _INP-O-BUF-A + @
    OVER _INP-O-BUF-LEN + @
    ROT _INP-O-CURSOR + @
    _INP-NEXT-CP
    SWAP _INP-O-CURSOR + !
    WDG-DIRTY ;

\ _INP-HOME ( widget -- )
: _INP-HOME  ( widget -- )
    DUP _INP-O-CURSOR + @ 0= IF DROP EXIT THEN
    0 OVER _INP-O-CURSOR + !
    WDG-DIRTY ;

\ _INP-END ( widget -- )
: _INP-END  ( widget -- )
    DUP _INP-O-BUF-LEN + @
    OVER _INP-O-CURSOR + !
    WDG-DIRTY ;

\ =====================================================================
\ 4. Scroll adjustment
\ =====================================================================

\ _INP-SCROLL-ADJ ( widget -- )
\   Ensure cursor column is visible within the region width.
\   Keeps at least 1 column of context when possible.
: _INP-SCROLL-ADJ  ( widget -- )
    DUP WDG-REGION RGN-W                  \ ( widget rgnw )
    OVER _INP-O-BUF-A + @
    2 PICK _INP-O-CURSOR + @
    _INP-BYTE-TO-COL                       \ ( widget rgnw cursorcol )
    ROT                                     \ ( rgnw cursorcol widget )
    DUP >R _INP-O-SCROLL + @              \ ( rgnw cursorcol scroll  R: widget )
    \ If cursorcol < scroll → scroll = cursorcol
    2DUP > IF
        NIP NIP                             \ new scroll = cursorcol
        R> _INP-O-SCROLL + ! EXIT
    THEN
    \ If cursorcol >= scroll + width → scroll = cursorcol - width + 1
    ROT                                     \ ( cursorcol scroll rgnw )
    2DUP + >R                               \ R2: scroll+width  R: widget
    ROT                                     \ ( scroll rgnw cursorcol )
    DUP R> >= IF                            \ cursorcol >= scroll+width
        SWAP - 1+ NIP                      \ cursorcol - width + 1
        R> _INP-O-SCROLL + ! EXIT
    THEN
    DROP 2DROP R> DROP ;

\ =====================================================================
\ 5. Internal draw
\ =====================================================================

VARIABLE _INP-DRW-A      \ current byte address during draw
VARIABLE _INP-DRW-L      \ remaining bytes during draw
VARIABLE _INP-DRW-W      \ widget pointer during draw
VARIABLE _INP-DRW-RW     \ region width during draw

\ _INP-DRAW-CURSOR ( -- )
\   Draw cursor indicator if widget is focused.  Uses _INP-DRW-W / _INP-DRW-RW.
: _INP-DRAW-CURSOR  ( -- )
    _INP-DRW-W @ WDG-FOCUSED? 0= IF EXIT THEN
    _INP-DRW-W @ _INP-O-BUF-A + @
    _INP-DRW-W @ _INP-O-CURSOR + @
    _INP-BYTE-TO-COL                        \ cursor column (codepoints)
    _INP-DRW-W @ _INP-O-SCROLL + @ -       \ visible column
    DUP 0 >= OVER _INP-DRW-RW @ < AND IF
        CELL-A-REVERSE DRW-ATTR!
        _INP-DRW-W @ _INP-O-CURSOR + @
        _INP-DRW-W @ _INP-O-BUF-LEN + @ < IF
            \ Character under cursor — decode it
            _INP-DRW-W @ _INP-O-BUF-A + @
            _INP-DRW-W @ _INP-O-CURSOR + @ +
            DUP C@ _UTF8-SEQLEN
            DUP 0= IF DROP 1 THEN           \ ( viscol addr seqlen )
            0 3 PICK DRW-TEXT                \ DRW-TEXT( addr len row col )
            DROP                             \ drop viscol
        ELSE
            \ Cursor past end — draw space
            32 0 ROT DRW-CHAR               \ DRW-CHAR( cp=32 row=0 col=viscol )
        THEN
        0 DRW-ATTR!
    ELSE
        DROP                                 \ drop viscol
    THEN ;

\ _INP-DRAW ( widget -- )
: _INP-DRAW  ( widget -- )
    DUP _INP-SCROLL-ADJ
    DUP _INP-DRW-W !
    DUP WDG-REGION RGN-W _INP-DRW-RW !
    \ Clear row 0
    32 0 0 _INP-DRW-RW @ DRW-HLINE
    DUP _INP-O-BUF-LEN + @ 0= IF
        \ Show placeholder if empty
        DUP _INP-O-PH-U + @ 0 > IF
            DUP _INP-O-PH-A + @
            OVER _INP-O-PH-U + @
            0 0 DRW-TEXT
        THEN
        DROP _INP-DRAW-CURSOR EXIT
    THEN
    \ Content is not empty — set up draw pointers
    DUP _INP-O-BUF-A + @ _INP-DRW-A !
    DUP _INP-O-BUF-LEN + @ _INP-DRW-L !
    \ Skip `scroll` codepoints
    DUP _INP-O-SCROLL + @
    DUP 0 > IF
        0 ?DO
            _INP-DRW-L @ 0= IF LEAVE THEN
            _INP-DRW-A @ _INP-DRW-L @
            UTF8-DECODE
            _INP-DRW-L ! _INP-DRW-A !
            DROP
        LOOP
    ELSE
        DROP
    THEN
    DROP                                    \ drop widget, using vars now
    \ Draw up to `width` codepoints — stack: ( col )
    0
    BEGIN
        DUP _INP-DRW-RW @ <                \ col < width?
        _INP-DRW-L @ 0 >                   \ bytes remain?
        AND
    WHILE
        _INP-DRW-A @ _INP-DRW-L @
        UTF8-DECODE
        _INP-DRW-L ! _INP-DRW-A !          \ ( col cp )
        OVER                                \ ( col cp col )
        0 SWAP                              \ ( col cp 0 col )
        DRW-CHAR                            \ DRW-CHAR( cp row col )
        1+                                  \ col++
    REPEAT
    DROP                                    \ drop col
    _INP-DRAW-CURSOR ;

\ =====================================================================
\ 6. Internal handle
\ =====================================================================

\ _INP-HANDLE ( event widget -- consumed? )
\   Dispatch key events for the input widget.
: _INP-HANDLE  ( event widget -- consumed? )
    OVER @ KEY-T-SPECIAL = IF
        OVER 8 + @                          \ event code
        CASE
            KEY-LEFT      OF NIP _INP-LEFT     -1 ENDOF
            KEY-RIGHT     OF NIP _INP-RIGHT    -1 ENDOF
            KEY-HOME      OF NIP _INP-HOME     -1 ENDOF
            KEY-END       OF NIP _INP-END      -1 ENDOF
            KEY-DEL       OF NIP _INP-DELETE   -1 ENDOF
            KEY-BACKSPACE OF NIP _INP-BACKSPACE -1 ENDOF
            KEY-ENTER     OF
                NIP DUP _INP-O-SUBMIT-XT + @ DUP 0<> IF
                    OVER SWAP EXECUTE
                ELSE
                    DROP
                THEN
                -1
            ENDOF
            \ default: not consumed
            0 SWAP
        ENDCASE
        SWAP DROP                           \ drop event addr
        EXIT
    THEN
    OVER @ KEY-T-CHAR = IF
        OVER 8 + @                          \ codepoint
        DUP 32 >= IF                        \ printable?
            ROT DROP SWAP _INP-INSERT -1 EXIT
        THEN
        DUP 8 = IF                          \ Ctrl-H = backspace
            DROP NIP _INP-BACKSPACE -1 EXIT
        THEN
        DROP
    THEN
    2DROP 0 ;                               \ not consumed

\ =====================================================================
\ 7. Constructor
\ =====================================================================

\ INP-NEW ( rgn buf cap -- widget )
\   Create an input field with an external buffer.
\   Buffer starts empty (len=0, cursor=0).
: INP-NEW  ( rgn buf cap -- widget )
    >R >R                                  \ R: cap buf ; ( rgn )
    _INP-DESC-SIZE ALLOCATE
    0<> ABORT" INP-NEW: alloc failed"      \ ( rgn addr )
    \ Fill header
    WDG-T-INPUT    OVER _WDG-O-TYPE      + !
    SWAP           OVER _WDG-O-REGION    + !
    ['] _INP-DRAW  OVER _WDG-O-DRAW-XT   + !
    ['] _INP-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                   OVER _WDG-O-FLAGS     + !
    \ Fill input fields
    R>             OVER _INP-O-BUF-A     + !   \ buf
    R>             OVER _INP-O-BUF-CAP   + !   \ cap
    0              OVER _INP-O-BUF-LEN   + !   \ len = 0
    0              OVER _INP-O-CURSOR    + !   \ cursor = 0
    0              OVER _INP-O-SCROLL    + !   \ scroll = 0
    0              OVER _INP-O-PH-A      + !   \ no placeholder
    0              OVER _INP-O-PH-U      + !
    0              OVER _INP-O-SUBMIT-XT + ! ; \ no callback

\ =====================================================================
\ 8. Public API
\ =====================================================================

\ INP-SET-TEXT ( text-a text-u widget -- )
\   Set content programmatically.  Clamps to capacity.
: INP-SET-TEXT  ( text-a text-u widget -- )
    >R                                      \ R: widget
    R@ _INP-O-BUF-CAP + @ MIN              \ clamp len
    DUP R@ _INP-O-BUF-LEN + !             \ store len
    R@ _INP-O-BUF-A + @                   \ dst
    SWAP CMOVE                              \ copy text ( src dst u -- ) in KDOS
    R@ _INP-O-BUF-LEN + @
    R@ _INP-O-CURSOR + !                   \ cursor at end
    R> WDG-DIRTY ;

\ INP-GET-TEXT ( widget -- addr len )
: INP-GET-TEXT  ( widget -- addr len )
    DUP _INP-O-BUF-A + @
    SWAP _INP-O-BUF-LEN + @ ;

\ INP-ON-SUBMIT ( xt widget -- )
: INP-ON-SUBMIT  ( xt widget -- )
    _INP-O-SUBMIT-XT + ! ;

\ INP-SET-PLACEHOLDER ( text-a text-u widget -- )
: INP-SET-PLACEHOLDER  ( text-a text-u widget -- )
    >R
    R@ _INP-O-PH-U + !
    R@ _INP-O-PH-A + !
    R> WDG-DIRTY ;

\ INP-CLEAR ( widget -- )
\   Clear content, reset cursor.
: INP-CLEAR  ( widget -- )
    0 OVER _INP-O-BUF-LEN + !
    0 OVER _INP-O-CURSOR + !
    0 OVER _INP-O-SCROLL + !
    WDG-DIRTY ;

\ INP-CURSOR-POS ( widget -- n )
\   Get cursor column (codepoint position, not byte offset).
: INP-CURSOR-POS  ( widget -- n )
    DUP _INP-O-BUF-A + @
    SWAP _INP-O-CURSOR + @
    _INP-BYTE-TO-COL ;

\ INP-FREE ( widget -- )
: INP-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\ 9. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _inp-guard

' INP-NEW             CONSTANT _inp-new-xt
' INP-SET-TEXT        CONSTANT _inp-settext-xt
' INP-GET-TEXT        CONSTANT _inp-gettext-xt
' INP-ON-SUBMIT      CONSTANT _inp-onsubmit-xt
' INP-SET-PLACEHOLDER CONSTANT _inp-setph-xt
' INP-CLEAR           CONSTANT _inp-clear-xt
' INP-CURSOR-POS      CONSTANT _inp-curpos-xt
' INP-FREE            CONSTANT _inp-free-xt

: INP-NEW             _inp-new-xt       _inp-guard WITH-GUARD ;
: INP-SET-TEXT        _inp-settext-xt   _inp-guard WITH-GUARD ;
: INP-GET-TEXT        _inp-gettext-xt   _inp-guard WITH-GUARD ;
: INP-ON-SUBMIT      _inp-onsubmit-xt  _inp-guard WITH-GUARD ;
: INP-SET-PLACEHOLDER _inp-setph-xt    _inp-guard WITH-GUARD ;
: INP-CLEAR           _inp-clear-xt    _inp-guard WITH-GUARD ;
: INP-CURSOR-POS      _inp-curpos-xt   _inp-guard WITH-GUARD ;
: INP-FREE            _inp-free-xt     _inp-guard WITH-GUARD ;
[THEN] [THEN]
