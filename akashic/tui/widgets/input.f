\ =====================================================================
\  akashic/tui/input.f — Single-line Text Input Field
\ =====================================================================
\
\  A single-line editable text field with cursor, supporting:
\    - Character insertion (UTF-8 aware)
\    - Backspace, Delete
\    - Cursor movement: left, right, Home, End, and a primary press
\    - Selection: Shift with a movement key, Ctrl+A, a Shift press, or a
\      drag; typing replaces it and Backspace or Delete removes it
\    - Horizontal scrolling when content exceeds region width
\    - Placeholder text (shown when buffer is empty)
\    - Submit callback on Enter
\    - Programmatic get/set of content
\
\  Ctrl and Alt combinations other than Ctrl+A are not consumed, so they
\  reach the application's shortcuts instead of inserting their letter.
\
\  The edit buffer is caller-provided — the widget does not allocate
\  storage for the text.  The caller decides where the memory lives
\  (stack, dictionary, XMEM).
\
\  Input Descriptor (header + 11 cells = 128 bytes):
\    +0..+32  widget header   type=WDG-T-INPUT
\    +40      buf-addr        Address of edit buffer
\    +48      buf-cap         Buffer capacity (bytes)
\    +56      buf-len         Current content length (bytes)
\    +64      cursor          Cursor position (byte offset)
\    +72      scroll          Horizontal scroll offset (columns)
\    +80      placeholder-a   Placeholder text address
\    +88      placeholder-u   Placeholder text length
\    +96      submit-xt       Callback on Enter ( widget -- )
\    +104     mask-cp         Draw this codepoint instead of input (0 = plain)
\    +112     anchor          Selection anchor byte offset (-1 = none)
\    +120     pressed         True while a primary press made here is held
\
\  Prefix: INP- (public), _INP- (internal)
\  Provider: akashic-tui-input
\  Dependencies: widget.f, draw.f, ../text/utf8.f,
\                ../text/cell-width.f, keys.f

PROVIDED akashic-tui-input

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../../text/utf8.f
REQUIRE ../../text/cell-width.f
REQUIRE ../keys.f

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
104 CONSTANT _INP-O-MASK-CP      \ replacement codepoint (0 = unmasked)
112 CONSTANT _INP-O-ANCHOR       \ selection anchor byte offset (-1 = none)
120 CONSTANT _INP-O-PRESSED      \ primary press made here is held

128 CONSTANT _INP-DESC-SIZE       \ total descriptor size

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
    2DUP <= IF                             \ cursor at or past end
        NIP NIP EXIT
    THEN
    SWAP >R                                \ ( buf-a cursor  R: buf-len )
    OVER OVER + C@ _UTF8-SEQLEN           \ ( buf-a cursor seqlen )
    DUP 0= IF DROP 1 THEN                 \ treat invalid as 1
    + NIP                                  \ cursor + seqlen
    R> MIN ;                               \ clamp to buf-len

\ =====================================================================
\ 3. Selection
\ =====================================================================
\
\ The selection runs between the anchor and the caret.  An empty range is
\ no selection, so the anchor is -1 whenever it would equal the caret.

: _INP-SEL?  ( widget -- flag )
    _INP-O-ANCHOR + @ -1 <> ;

: _INP-UNSELECT  ( widget -- )
    -1 SWAP _INP-O-ANCHOR + ! ;

\ _INP-SEL-RANGE ( widget -- start end )   Ordered byte offsets.
: _INP-SEL-RANGE  ( widget -- start end )
    DUP _INP-O-ANCHOR + @ SWAP _INP-O-CURSOR + @
    2DUP > IF SWAP THEN ;

\ _INP-ANCHOR ( widget -- )   Start a selection at the caret unless one exists.
: _INP-ANCHOR  ( widget -- )
    DUP _INP-SEL? IF DROP EXIT THEN
    DUP _INP-O-CURSOR + @ SWAP _INP-O-ANCHOR + ! ;

\ _INP-SETTLE ( widget -- )   Drop a selection the caret has closed.
: _INP-SETTLE  ( widget -- )
    DUP _INP-O-ANCHOR + @ OVER _INP-O-CURSOR + @ = IF
        _INP-UNSELECT
    ELSE
        DROP
    THEN ;

\ _INP-IN-SEL? ( byte-off widget -- flag )
: _INP-IN-SEL?  ( off widget -- flag )
    DUP _INP-SEL? 0= IF 2DROP 0 EXIT THEN
    _INP-SEL-RANGE >R OVER <= SWAP R> < AND ;

\ _INP-DEL-SEL ( widget -- deleted? )
\   Remove the selected bytes and leave the caret where they began.
: _INP-DEL-SEL  ( widget -- flag )
    DUP _INP-SEL? 0= IF DROP 0 EXIT THEN
    >R R@ _INP-SEL-RANGE OVER -             ( start len  R: widget )
    R@ _INP-O-BUF-A + @ 2 PICK +            ( start len dst )
    DUP 2 PICK + SWAP                       ( start len src dst )
    R@ _INP-O-BUF-LEN + @ 4 PICK - 3 PICK - ( start len src dst tail )
    DUP 0> IF CMOVE ELSE DROP 2DROP THEN    ( start len )
    R@ _INP-O-BUF-LEN + @ SWAP - R@ _INP-O-BUF-LEN + !
    R@ _INP-O-CURSOR + !
    R@ _INP-UNSELECT
    R> WDG-DIRTY -1 ;

\ _INP-SELECT-ALL ( widget -- )
: _INP-SELECT-ALL  ( widget -- )
    0 OVER _INP-O-ANCHOR + !
    DUP _INP-O-BUF-LEN + @ OVER _INP-O-CURSOR + !
    DUP _INP-SETTLE WDG-DIRTY ;

\ =====================================================================
\ 3a. Edit operations
\ =====================================================================

\ _INP-INSERT ( cp widget -- )
\   Insert codepoint at cursor position, replacing any selection.
\   Rejects insertion if buffer would overflow capacity.
VARIABLE _INP-INS-TMP
CREATE _INP-INS-BUF 4 ALLOT               \ temp encode buffer (max 4 bytes)

: _INP-INSERT  ( cp widget -- )
    DUP _INP-DEL-SEL DROP
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
\   Delete the selection, or the character at the cursor.
: _INP-DELETE  ( widget -- )
    DUP _INP-DEL-SEL IF DROP EXIT THEN
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
\   Delete the selection, or the character before the cursor.
: _INP-BACKSPACE  ( widget -- )
    DUP _INP-DEL-SEL IF DROP EXIT THEN
    DUP _INP-O-CURSOR + @ 0= IF DROP EXIT THEN  \ already at start
    \ Move cursor back one cp, then delete forward
    DUP DUP _INP-O-BUF-A + @
    OVER _INP-O-CURSOR + @
    _INP-PREV-CP                            \ ( widget widget newcur )
    SWAP _INP-O-CURSOR + !                  \ update cursor
    _INP-DELETE ;

\ Caret moves.  Each only moves the caret; _INP-MOVE applies the selection
\ rule and marks the field dirty.

\ _INP-LEFT ( widget -- )
: _INP-LEFT  ( widget -- )
    DUP _INP-O-BUF-A + @ OVER _INP-O-CURSOR + @ _INP-PREV-CP
    SWAP _INP-O-CURSOR + ! ;

\ _INP-RIGHT ( widget -- )
: _INP-RIGHT  ( widget -- )
    DUP _INP-O-BUF-A + @ OVER _INP-O-BUF-LEN + @
    2 PICK _INP-O-CURSOR + @ _INP-NEXT-CP
    SWAP _INP-O-CURSOR + ! ;

\ _INP-HOME ( widget -- )
: _INP-HOME  ( widget -- )
    0 SWAP _INP-O-CURSOR + ! ;

\ _INP-END ( widget -- )
: _INP-END  ( widget -- )
    DUP _INP-O-BUF-LEN + @ SWAP _INP-O-CURSOR + ! ;

\ _INP-MOVE ( event widget xt -- )
\   Run a caret move.  With Shift it extends the selection from where the
\   caret was; without Shift it drops the selection.
: _INP-MOVE  ( event widget xt -- )
    >R SWAP 16 + @ KEY-MOD-SHIFT AND IF
        DUP _INP-ANCHOR
    ELSE
        DUP _INP-UNSELECT
    THEN
    DUP R> EXECUTE
    DUP _INP-SETTLE WDG-DIRTY ;

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
    2DUP < IF
        DROP NIP                            \ new scroll = cursorcol
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
\   A selection shows in reverse video instead, so the caret is not drawn
\   beside it where it would look like one more selected character.
: _INP-DRAW-CURSOR  ( -- )
    _INP-DRW-W @ WDG-FOCUSED? 0= IF EXIT THEN
    _INP-DRW-W @ _INP-SEL? IF EXIT THEN
    _INP-DRW-W @ _INP-O-BUF-A + @
    _INP-DRW-W @ _INP-O-CURSOR + @
    _INP-BYTE-TO-COL                        \ cursor column (codepoints)
    _INP-DRW-W @ _INP-O-SCROLL + @ -       \ visible column
    DUP 0 >= OVER _INP-DRW-RW @ < AND IF
        CELL-A-REVERSE DRW-ATTR!
        _INP-DRW-W @ _INP-O-CURSOR + @
        _INP-DRW-W @ _INP-O-BUF-LEN + @ < IF
            _INP-DRW-W @ _INP-O-MASK-CP + @ ?DUP IF
                CW-CELL-CP SWAP 0 SWAP DRW-CHAR
            ELSE
                \ Character under cursor — decode it
                _INP-DRW-W @ _INP-O-BUF-A + @
                _INP-DRW-W @ _INP-O-CURSOR + @ +
                DUP C@ _UTF8-SEQLEN
                DUP 0= IF DROP 1 THEN        \ ( viscol addr seqlen )
                0 3 PICK DRW-TEXT-UNTRUSTED
                DROP                          \ drop viscol
            THEN
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
            0 0 DRW-TEXT-UNTRUSTED
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
        _INP-DRW-A @ _INP-DRW-W @ _INP-O-BUF-A + @ -
        _INP-DRW-W @ _INP-IN-SEL? IF CELL-A-REVERSE ELSE 0 THEN DRW-ATTR!
        _INP-DRW-A @ _INP-DRW-L @
        UTF8-DECODE
        _INP-DRW-L ! _INP-DRW-A !          \ ( col cp )
        _INP-DRW-W @ _INP-O-MASK-CP + @ ?DUP IF
            SWAP DROP                        \ replace decoded cp with mask
        THEN
        CW-CELL-CP
        OVER                                \ ( col cp col )
        0 SWAP                              \ ( col cp 0 col )
        DRW-CHAR                            \ DRW-CHAR( cp row col )
        1+                                  \ col++
    REPEAT
    DROP                                    \ drop col
    0 DRW-ATTR!
    _INP-DRAW-CURSOR ;

\ =====================================================================
\ 5a. Pointer
\ =====================================================================
\
\ The field draws one codepoint per column from its scroll offset, so a
\ pointer column maps back to a codepoint.  A primary press inside the
\ field places the caret there, or with Shift extends the selection to it.
\ While that press is held, a drag extends the selection wherever the
\ pointer goes.  A column past either edge names one codepoint beyond the
\ visible text, so each drag step out there scrolls the field one column.
\ Only the release of a press made here is consumed.

\ _INP-COL>CURSOR ( cols widget -- byte-off )
\   Byte offset after cols codepoints, or the end of the content.
: _INP-COL>CURSOR  ( cols widget -- off )
    SWAP 0 SWAP                             ( widget off cols )
    0 ?DO
        OVER _INP-O-BUF-LEN + @ OVER > 0= IF LEAVE THEN
        OVER _INP-O-BUF-A + @ 2 PICK _INP-O-BUF-LEN + @ ROT _INP-NEXT-CP
    LOOP
    NIP ;

\ _INP-PT-INSIDE? ( event widget -- flag )
: _INP-PT-INSIDE?  ( event widget -- flag )
    >R 16 + @ DUP 16 RSHIFT R@ WDG-REGION RGN-ROW -
    R@ WDG-REGION RGN-H U<
    SWAP 0xFFFF AND R@ WDG-REGION RGN-COL -
    R> WDG-REGION RGN-W U< AND ;

\ _INP-PT-CURSOR ( col' widget -- byte-off )
\   The byte offset a field-relative column names, reaching at most one
\   codepoint past either visible edge.
: _INP-PT-CURSOR  ( col' widget -- off )
    >R
    DUP 0< IF DROP -1 THEN
    DUP R@ WDG-REGION RGN-W > IF DROP R@ WDG-REGION RGN-W THEN
    R@ _INP-O-SCROLL + @ +
    DUP 0< IF DROP 0 THEN
    R> _INP-COL>CURSOR ;

\ _INP-POINT-TO ( event widget -- )   Move the caret to the pointer.
: _INP-POINT-TO  ( event widget -- )
    SWAP 16 + @ 0xFFFF AND                  ( widget col )
    OVER WDG-REGION RGN-COL -               ( widget col' )
    OVER _INP-PT-CURSOR                     ( widget off )
    OVER _INP-O-CURSOR + !
    DUP _INP-SETTLE WDG-DIRTY ;

: _INP-PRESS  ( event widget -- consumed? )
    2DUP _INP-PT-INSIDE? 0= IF 2DROP 0 EXIT THEN
    -1 OVER _INP-O-PRESSED + !
    OVER 8 + @ KEY-MOUSE-SHIFT? IF DUP _INP-ANCHOR ELSE DUP _INP-UNSELECT THEN
    _INP-POINT-TO -1 ;

: _INP-DRAG  ( event widget -- consumed? )
    DUP _INP-O-PRESSED + @ 0= IF 2DROP 0 EXIT THEN
    DUP _INP-ANCHOR _INP-POINT-TO -1 ;

: _INP-RELEASE  ( event widget -- consumed? )
    NIP DUP _INP-O-PRESSED + @ 0 ROT _INP-O-PRESSED + ! ;

\ _INP-POINTER ( event widget -- consumed? )
: _INP-POINTER  ( event widget -- consumed? )
    OVER 8 + @ KEY-MOUSE-BUTTON CASE
        KEY-MOUSE-LEFT    OF _INP-PRESS   ENDOF
        KEY-MOUSE-DRAG    OF _INP-DRAG    ENDOF
        KEY-MOUSE-RELEASE OF _INP-RELEASE ENDOF
        >R 2DROP 0 R>
    ENDCASE ;

\ =====================================================================
\ 6. Internal handle
\ =====================================================================

\ _INP-SUBMIT ( widget -- )
: _INP-SUBMIT  ( widget -- )
    DUP _INP-O-SUBMIT-XT + @ ?DUP IF EXECUTE ELSE DROP THEN ;

\ _INP-SPECIAL ( event widget -- consumed? )
: _INP-SPECIAL  ( event widget -- consumed? )
    OVER 8 + @ CASE
        KEY-LEFT      OF ['] _INP-LEFT  _INP-MOVE -1 ENDOF
        KEY-RIGHT     OF ['] _INP-RIGHT _INP-MOVE -1 ENDOF
        KEY-HOME      OF ['] _INP-HOME  _INP-MOVE -1 ENDOF
        KEY-END       OF ['] _INP-END   _INP-MOVE -1 ENDOF
        KEY-DEL       OF NIP _INP-DELETE    -1 ENDOF
        KEY-BACKSPACE OF NIP _INP-BACKSPACE -1 ENDOF
        KEY-ENTER     OF NIP _INP-SUBMIT    -1 ENDOF
        >R 2DROP 0 R>
    ENDCASE ;

\ _INP-HANDLE ( event widget -- consumed? )
\   Dispatch key and pointer events for the input widget.
: _INP-HANDLE  ( event widget -- consumed? )
    OVER @ KEY-T-MOUSE = IF _INP-POINTER EXIT THEN
    OVER @ KEY-T-SPECIAL = IF _INP-SPECIAL EXIT THEN
    OVER @ KEY-T-CHAR = IF
        OVER 16 + @ KEY-MOD-CTRL KEY-MOD-ALT OR AND IF
            OVER 16 + @ KEY-MOD-CTRL =
            2 PICK 8 + @ [CHAR] a = AND IF
                NIP _INP-SELECT-ALL -1 EXIT
            THEN
            2DROP 0 EXIT
        THEN
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
    0              OVER _INP-O-SUBMIT-XT + !
    0              OVER _INP-O-MASK-CP   + !   \ unmasked
    -1             OVER _INP-O-ANCHOR    + !   \ no selection
    0              OVER _INP-O-PRESSED   + ! ;

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
    R@ _INP-UNSELECT
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
    DUP _INP-UNSELECT
    WDG-DIRTY ;

\ INP-WIPE ( widget -- )
\   Zero the caller-owned edit buffer and reset all edit state.
: INP-WIPE  ( widget -- )
    DUP _INP-O-BUF-A + @ OVER _INP-O-BUF-CAP + @ 0 FILL
    INP-CLEAR ;

\ INP-MASK! ( codepoint widget -- )
\   A nonzero codepoint masks every entered character during rendering.
: INP-MASK!  ( codepoint widget -- )
    >R DUP 0< IF DROP 0 THEN
    R@ _INP-O-MASK-CP + !
    0 R@ _INP-O-SCROLL + !
    R> WDG-DIRTY ;

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
REQUIRE ../../concurrency/guard.f
GUARD _inp-guard

' INP-NEW             CONSTANT _inp-new-xt
' INP-SET-TEXT        CONSTANT _inp-settext-xt
' INP-GET-TEXT        CONSTANT _inp-gettext-xt
' INP-ON-SUBMIT      CONSTANT _inp-onsubmit-xt
' INP-SET-PLACEHOLDER CONSTANT _inp-setph-xt
' INP-CLEAR           CONSTANT _inp-clear-xt
' INP-WIPE            CONSTANT _inp-wipe-xt
' INP-MASK!           CONSTANT _inp-mask-xt
' INP-CURSOR-POS      CONSTANT _inp-curpos-xt
' INP-FREE            CONSTANT _inp-free-xt

: INP-NEW             _inp-new-xt       _inp-guard WITH-GUARD ;
: INP-SET-TEXT        _inp-settext-xt   _inp-guard WITH-GUARD ;
: INP-GET-TEXT        _inp-gettext-xt   _inp-guard WITH-GUARD ;
: INP-ON-SUBMIT      _inp-onsubmit-xt  _inp-guard WITH-GUARD ;
: INP-SET-PLACEHOLDER _inp-setph-xt    _inp-guard WITH-GUARD ;
: INP-CLEAR           _inp-clear-xt    _inp-guard WITH-GUARD ;
: INP-WIPE            _inp-wipe-xt     _inp-guard WITH-GUARD ;
: INP-MASK!           _inp-mask-xt     _inp-guard WITH-GUARD ;
: INP-CURSOR-POS      _inp-curpos-xt   _inp-guard WITH-GUARD ;
: INP-FREE            _inp-free-xt     _inp-guard WITH-GUARD ;
[THEN] [THEN]
