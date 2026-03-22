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
REQUIRE ../../text/gap-buf.f
REQUIRE ../../text/undo.f
REQUIRE ../../text/cell-width.f
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

\ --- Phase-0 extension fields (all default to 0) ---
 96 CONSTANT _TXTA-O-GB           \ gap-buf handle or 0
104 CONSTANT _TXTA-O-UNDO         \ undo state handle or 0
112 CONSTANT _TXTA-O-DRAW-LINE-XT \ per-line draw hook or 0
120 CONSTANT _TXTA-O-GUTTER-XT    \ gutter draw hook or 0
128 CONSTANT _TXTA-O-GUTTER-W     \ gutter column width (0 = off)
136 CONSTANT _TXTA-O-SCROLL-X     \ horizontal scroll offset

144 CONSTANT _TXTA-DESC-SIZE

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

\ --- Gap-buf mode helpers ---

\ _TXTA-GB? ( -- flag )   True if a gap buffer is bound.
: _TXTA-GB?  ( -- flag )
    _TXTA-W @ _TXTA-O-GB + @ 0<> ;

\ _TXTA-GB ( -- gb )   Return the bound gap-buf handle.
: _TXTA-GB  ( -- gb )
    _TXTA-W @ _TXTA-O-GB + @ ;

\ _TXTA-UD ( -- ud | 0 )   Return the bound undo handle (or 0).
: _TXTA-UD  ( -- ud )
    _TXTA-W @ _TXTA-O-UNDO + @ ;

\ _TXTA-CONTENT-LEN ( -- n )   Content length in either mode.
: _TXTA-CONTENT-LEN  ( -- n )
    _TXTA-GB? IF _TXTA-GB GB-LEN ELSE _TXTA-BUF-LEN THEN ;

\ _TXTA-CONTENT-BYTE@ ( pos -- c )   Logical byte access.
: _TXTA-CONTENT-BYTE@  ( pos -- c )
    _TXTA-GB? IF _TXTA-GB GB-BYTE@ ELSE _TXTA-BUF-A + C@ THEN ;

\ _TXTA-SYNC-CURSOR! ( new-pos -- )
\   Set cursor in widget descriptor.  In GB mode also move the gap.
: _TXTA-SYNC-CURSOR!  ( n -- )
    DUP _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-GB? IF _TXTA-GB GB-MOVE! ELSE DROP THEN ;

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
\   In GB mode: O(log n) binary search via GB-CURSOR-LINE.
: _TXTA-CURSOR-LINE  ( -- line )
    _TXTA-GB? IF _TXTA-GB GB-CURSOR-LINE EXIT THEN
    0  _TXTA-CURSOR 0 ?DO
        _TXTA-BUF-A I + C@ 10 = IF 1+ THEN
    LOOP ;

\ _TXTA-LINE-COUNT ( -- n )
\   Total number of lines (count newlines + 1).
\   In GB mode: O(1) via GB-LINES.
: _TXTA-LINE-COUNT  ( -- n )
    _TXTA-GB? IF _TXTA-GB GB-LINES EXIT THEN
    1  _TXTA-BUF-LEN 0 ?DO
        _TXTA-BUF-A I + C@ 10 = IF 1+ THEN
    LOOP ;

\ _TXTA-SOL ( -- byte-off )
\   Byte offset of start of current line.
\   In GB mode: uses GB-CURSOR-LINE + GB-LINE-OFF.
: _TXTA-SOL  ( -- off )
    _TXTA-GB? IF
        _TXTA-GB GB-CURSOR-LINE _TXTA-GB GB-LINE-OFF EXIT
    THEN
    _TXTA-CURSOR
    BEGIN
        DUP 0 > IF
            DUP 1- _TXTA-BUF-A + C@ 10 <>
        ELSE 0 THEN
    WHILE 1- REPEAT ;

\ _TXTA-EOL ( -- byte-off )
\   Byte offset of end of current line (the \n position or content-len).
\   In GB mode: SOL + GB-LINE-LEN.
: _TXTA-EOL  ( -- off )
    _TXTA-GB? IF
        _TXTA-GB GB-CURSOR-LINE DUP
        _TXTA-GB GB-LINE-OFF  SWAP
        _TXTA-GB GB-LINE-LEN  +
        EXIT
    THEN
    _TXTA-CURSOR
    BEGIN
        DUP _TXTA-BUF-LEN < IF
            DUP _TXTA-BUF-A + C@ 10 <>
        ELSE 0 THEN
    WHILE 1+ REPEAT ;

VARIABLE _TXTA-LCNT   \ temp for _TXTA-LINE-OFF (flat mode)

\ _TXTA-LINE-OFF ( target-line -- byte-off )
\   Find byte offset of start of the given line number (0-based).
\   In GB mode: O(1) via GB-LINE-OFF.
: _TXTA-LINE-OFF  ( target-line -- byte-off )
    _TXTA-GB? IF _TXTA-GB GB-LINE-OFF EXIT THEN
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
\   In GB mode: O(cursor-to-SOL) via GB-CURSOR-COL.
: _TXTA-CURSOR-COL  ( -- col )
    _TXTA-GB? IF _TXTA-GB GB-CURSOR-COL EXIT THEN
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
\   Uses _TXTA-CONTENT-BYTE@ to work in both modes.
: _TXTA-COL-OFF  ( line-off target-col -- byte-off )
    _TXTA-TCOL !
    BEGIN
        _TXTA-TCOL @ 0 >
        OVER _TXTA-CONTENT-LEN < AND
    WHILE
        DUP _TXTA-CONTENT-BYTE@ 10 = IF EXIT THEN
        DUP _TXTA-CONTENT-BYTE@ _UTF8-SEQLEN
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

\ --- GB-mode deletion helpers (used by _TXTA-DEL-RANGE, _TXTA-DEL-SEL) ---

\ _TXTA-GB-DEL-RANGE ( start len -- )
\   Delete len bytes at byte offset start via gap-buf.
\   Records undo if bound.
VARIABLE _TXTA-GBD-ST   VARIABLE _TXTA-GBD-LN
: _TXTA-GB-DEL-RANGE  ( start len -- )
    DUP 0= IF 2DROP EXIT THEN
    _TXTA-GBD-LN ! _TXTA-GBD-ST !
    _TXTA-GBD-ST @ _TXTA-GB GB-MOVE!
    _TXTA-UD IF
        \ Peek at the bytes about to be deleted for undo
        UNDO-T-DEL _TXTA-GBD-ST @
        _TXTA-GB _GB-O-BUF + @  _TXTA-GB _GB-O-GE + @ +  \ del-addr (about to be exposed)
        _TXTA-GBD-LN @
        _TXTA-UD UNDO-PUSH
    THEN
    _TXTA-GBD-LN @ _TXTA-GB GB-DEL 2DROP
    _TXTA-GB GB-CURSOR _TXTA-W @ _TXTA-O-CURSOR + ! ;

\ _TXTA-DEL-RANGE ( start len -- )
\   Delete len bytes starting at byte offset start.  Low-level:
\   shifts tail left, updates buf-len.  Does NOT fire change or dirty.
\   In GB mode: routes through gap-buf + undo.
VARIABLE _TXTA-DR-START
VARIABLE _TXTA-DR-LEN
: _TXTA-DEL-RANGE  ( start len -- )
    DUP 0= IF 2DROP EXIT THEN
    _TXTA-GB? IF _TXTA-GB-DEL-RANGE EXIT THEN
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
    _TXTA-UD IF _TXTA-UD UNDO-BREAK THEN
    2DUP _TXTA-DEL-RANGE
    DROP                             ( start )
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-GB? IF _TXTA-CURSOR _TXTA-GB GB-MOVE! THEN
    _TXTA-SEL-CLEAR
    -1 ;

\ --- GB-mode insert helper ---

\ _TXTA-GB-INS-STR ( addr len -- )
\   Insert at cursor via gap-buf.  Records undo if bound.
: _TXTA-GB-INS-STR  ( addr len -- )
    DUP 0= IF 2DROP EXIT THEN
    _TXTA-UD IF
        UNDO-T-INS _TXTA-CURSOR 2OVER _TXTA-UD UNDO-PUSH
    THEN
    _TXTA-GB GB-INS
    _TXTA-GB GB-CURSOR _TXTA-W @ _TXTA-O-CURSOR + ! ;

\ _TXTA-INS-STR ( addr len -- )
\   Insert a string of bytes at cursor.  Used by paste.
\   Assumes selection already handled.  Rejects if buffer would overflow.
\   In GB mode: routes through gap-buf + undo (auto-grows).
: _TXTA-INS-STR  ( addr len -- )
    _TXTA-GB? IF _TXTA-GB-INS-STR EXIT THEN
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
\   it first (replacing selection).  Rejects if buffer would overflow
\   (flat mode only; GB mode auto-grows).
: _TXTA-INSERT  ( cp -- )
    _TXTA-DEL-SEL DROP
    _TXTA-INS-BUF UTF8-ENCODE
    _TXTA-INS-BUF - _TXTA-INS-SZ !
    _TXTA-GB? IF
        _TXTA-INS-BUF _TXTA-INS-SZ @ _TXTA-GB-INS-STR
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
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
\   In GB mode: uses GB-DEL-CP + undo.
: _TXTA-DELETE  ( -- )
    _TXTA-DEL-SEL IF
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
    _TXTA-CURSOR _TXTA-CONTENT-LEN >= IF EXIT THEN
    _TXTA-GB? IF
        _TXTA-CURSOR _TXTA-GB GB-MOVE!
        \ Peek at codepoint about to be deleted for undo
        _TXTA-UD IF
            _TXTA-GB _GB-O-BUF + @  _TXTA-GB _GB-O-GE + @ +
            C@ _UTF8-SEQLEN DUP 0= IF DROP 1 THEN   ( cpsize )
            UNDO-T-DEL _TXTA-CURSOR
            _TXTA-GB _GB-O-BUF + @  _TXTA-GB _GB-O-GE + @ +
            ROT _TXTA-UD UNDO-PUSH
        THEN
        _TXTA-GB GB-DEL-CP 2DROP
        _TXTA-GB GB-CURSOR _TXTA-W @ _TXTA-O-CURSOR + !
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
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
\   In GB mode: uses GB-BS-CP + undo.
: _TXTA-BACKSPACE  ( -- )
    _TXTA-DEL-SEL IF
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
    _TXTA-CURSOR 0= IF EXIT THEN
    _TXTA-GB? IF
        _TXTA-CURSOR _TXTA-GB GB-MOVE!
        \ Determine codepoint size for undo
        _TXTA-GB _GB-O-GS + @             ( gs )
        DUP 1-                             ( gs phys )
        BEGIN DUP 0 > IF
            DUP _TXTA-GB _GB-O-BUF + @ + C@ _UTF8-CONT?
        ELSE 0 THEN WHILE 1- REPEAT       ( gs cp-start )
        SWAP OVER -                        ( cp-start cpsize )
        _TXTA-UD IF
            UNDO-T-DEL
            OVER                           ( cp-start cpsize  T-DEL cp-start )
            2 PICK _TXTA-GB _GB-O-BUF + @ + ( ... del-addr )
            2 PICK                         ( ... del-len )
            _TXTA-UD UNDO-PUSH
        THEN
        DROP DROP                          ( -- )
        _TXTA-GB GB-BS-CP 2DROP
        _TXTA-GB GB-CURSOR _TXTA-W @ _TXTA-O-CURSOR + !
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
    \ Flat mode: move cursor back one codepoint then delete forward
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
            DUP _TXTA-CONTENT-BYTE@ _UTF8-CONT?
        ELSE 0 THEN
    WHILE 1- REPEAT
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-RIGHT  ( -- )
    _TXTA-CURSOR _TXTA-CONTENT-LEN >= IF EXIT THEN
    _TXTA-CURSOR _TXTA-CONTENT-BYTE@ _UTF8-SEQLEN
    DUP 0= IF DROP 1 THEN
    _TXTA-CURSOR + _TXTA-CONTENT-LEN MIN
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-HOME  ( -- )
    _TXTA-SOL
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-END  ( -- )
    _TXTA-EOL
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-UP  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 0= IF DROP EXIT THEN           \ already on line 0
    _TXTA-CURSOR-COL                    ( cline ccol )
    SWAP 1- _TXTA-LINE-OFF             ( ccol target-line-off )
    SWAP _TXTA-COL-OFF                  ( byte-off )
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-DOWN  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 1+ _TXTA-LINE-COUNT >= IF DROP EXIT THEN
    _TXTA-CURSOR-COL                    ( cline ccol )
    SWAP 1+ _TXTA-LINE-OFF             ( ccol target-line-off )
    SWAP _TXTA-COL-OFF                  ( byte-off )
    _TXTA-SYNC-CURSOR!
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
    _TXTA-SYNC-CURSOR!
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
    _TXTA-SYNC-CURSOR!
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
            DUP 1- _TXTA-CONTENT-BYTE@ _TXTA-IS-WORD-CHAR 0=
        ELSE 0 THEN
    WHILE 1- REPEAT
    \ Phase 2: skip word chars going left
    BEGIN
        DUP 0 > IF
            DUP 1- _TXTA-CONTENT-BYTE@ _TXTA-IS-WORD-CHAR
        ELSE 0 THEN
    WHILE 1- REPEAT
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-WORD-RIGHT ( -- )
\   Move cursor right to the start of the next word.
: _TXTA-WORD-RIGHT  ( -- )
    _TXTA-CURSOR _TXTA-CONTENT-LEN >= IF EXIT THEN
    _TXTA-CURSOR
    \ Phase 1: skip word chars going right
    BEGIN
        DUP _TXTA-CONTENT-LEN < IF
            DUP _TXTA-CONTENT-BYTE@ _TXTA-IS-WORD-CHAR
        ELSE 0 THEN
    WHILE 1+ REPEAT
    \ Phase 2: skip non-word chars going right
    BEGIN
        DUP _TXTA-CONTENT-LEN < IF
            DUP _TXTA-CONTENT-BYTE@ _TXTA-IS-WORD-CHAR 0=
        ELSE 0 THEN
    WHILE 1+ REPEAT
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

\ =====================================================================
\  6. Scroll adjustment
\ =====================================================================

\ _TXTA-SCROLL-ADJ ( -- )
\   Ensure cursor line is visible within viewport height.

VARIABLE _TXTA-SA-GW   \ gutter width during scroll adj
: _TXTA-SCROLL-ADJ  ( -- )
    _TXTA-W @ _TXTA-O-GUTTER-W + @ _TXTA-SA-GW !
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
    DROP
    \ --- Horizontal scroll adjustment ---
    _TXTA-W @ _TXTA-O-SCROLL-X + @     ( scroll-x )
    _TXTA-W @ WDG-REGION RGN-W
    _TXTA-SA-GW @ -                     ( scroll-x text-w )
    DUP 1 < IF DROP 1 THEN             ( scroll-x tw )   \ safety
    _TXTA-CURSOR-COL                    ( scroll-x tw ccol )
    \ Cursor left of viewport?
    2 PICK OVER > IF
        NIP NIP                          ( ccol )
        4 - 0 MAX
        _TXTA-W @ _TXTA-O-SCROLL-X + !
        EXIT
    THEN
    \ Cursor right of viewport?
    ROT 2 PICK + OVER <= IF            ( tw ccol )
        SWAP - 4 +                       ( new-scroll-x )
        _TXTA-W @ _TXTA-O-SCROLL-X + !
        EXIT
    THEN
    2DROP ;

\ =====================================================================
\  7. Internal draw
\ =====================================================================

VARIABLE _TXTA-DRW-A      \ pointer into buffer (flat mode)
VARIABLE _TXTA-DRW-L      \ remaining bytes (flat mode)
VARIABLE _TXTA-DRW-RW     \ region width (total, including gutter)
VARIABLE _TXTA-DRW-TW     \ text area width (RW - gutter-w)
VARIABLE _TXTA-DRW-COL    \ current column during line draw
VARIABLE _TXTA-DRW-ROW    \ current row
VARIABLE _TXTA-DRW-CDONE  \ cursor already rendered flag
VARIABLE _TXTA-DRW-SELS   \ selection start byte offset (or -1)
VARIABLE _TXTA-DRW-SELE   \ selection end byte offset
VARIABLE _TXTA-DRW-LINE#  \ which document line we're painting
VARIABLE _TXTA-DRW-GW     \ gutter width for this paint pass
VARIABLE _TXTA-DRW-SX     \ horizontal scroll offset
VARIABLE _TXTA-DRW-GBFLAT \ if non-zero, ALLOCATEd flat copy (must FREE)

CREATE _TXTA-FLAT-BUF 1024 ALLOT   \ temp for GB line extraction (hook path)

\ _TXTA-DRW-BYTEOFF ( -- off )
\   Current byte offset into buffer during draw (content-len - remaining).
: _TXTA-DRW-BYTEOFF  ( -- off )
    _TXTA-CONTENT-LEN _TXTA-DRW-L @ - ;

\ _TXTA-DRW-IN-SEL? ( -- flag )
\   True if current draw byte offset is inside the selection range.
: _TXTA-DRW-IN-SEL?  ( -- flag )
    _TXTA-DRW-SELS @ -1 = IF 0 EXIT THEN
    _TXTA-DRW-BYTEOFF
    DUP _TXTA-DRW-SELS @ >= SWAP _TXTA-DRW-SELE @ < AND ;

\ _TXTA-DRW-GUTTER ( row -- )
\   Draw the gutter for a given row using the app's gutter callback.
: _TXTA-DRW-GUTTER  ( row -- )
    _TXTA-DRW-GW @ 0= IF DROP EXIT THEN
    _TXTA-W @ _TXTA-O-GUTTER-XT + @ ?DUP IF
        >R  _TXTA-DRW-LINE# @  SWAP  _TXTA-DRW-GW @  _TXTA-W @
        R> EXECUTE
    ELSE DROP THEN ;

\ _TXTA-DRAW-LINE ( row -- )
\   Draw one text line at the given viewport row.
\
\   If a draw-line hook is installed AND we are in GB mode,
\   delegates to it.  Otherwise uses the default monochrome renderer.
\
\   The draw-line hook signature:
\     ( line-addr line-len line# row col-offset widget -- )
\   where line-addr/len point to a flat copy of the line bytes,
\   line# is the 0-based document line number, row is the screen
\   row, col-offset is the gutter width, widget is the textarea.

VARIABLE _TXTA-DL-OFF   \ byte offset of this line's start
VARIABLE _TXTA-DL-LEN   \ byte length of this line (excl newline)

: _TXTA-DRAW-LINE  ( row -- )
    _TXTA-DRW-ROW !
    \ If draw-line hook is set and GB mode, use it
    _TXTA-W @ _TXTA-O-DRAW-LINE-XT + @ 0<>
    _TXTA-GB? AND IF
        \ Extract line bytes to flat buffer
        _TXTA-DRW-LINE# @  _TXTA-GB GB-LINE-LEN
        1024 MIN  DUP _TXTA-DL-LEN !
        _TXTA-DRW-LINE# @  _TXTA-GB GB-LINE-OFF  _TXTA-DL-OFF !
        \ Copy bytes from gap-buf to flat buf
        _TXTA-DL-LEN @ 0 ?DO
            _TXTA-DL-OFF @ I +  _TXTA-GB GB-BYTE@
            _TXTA-FLAT-BUF I + C!
        LOOP
        \ Call hook: ( line-addr line-len line# row col-offset widget -- )
        _TXTA-FLAT-BUF  _TXTA-DL-LEN @
        _TXTA-DRW-LINE# @  _TXTA-DRW-ROW @
        _TXTA-DRW-GW @  _TXTA-W @
        _TXTA-W @ _TXTA-O-DRAW-LINE-XT + @ EXECUTE
        \ Advance pointers for next line is handled in _TXTA-DRAW
        EXIT
    THEN
    \ --- Default monochrome renderer (works for both flat & GB) ---
    \ Clear row (whole width including gutter)
    32 _TXTA-DRW-ROW @ 0 _TXTA-DRW-RW @ DRW-HLINE
    _TXTA-DRW-GW @ _TXTA-DRW-COL !   \ start text after gutter
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
\   Top-level draw: scroll adjust, set up state, draw each visible row.
\   In GB mode with draw-line hook: per-line extraction from gap-buf.
\   In flat mode: sequential pointer walk as before.
: _TXTA-DRAW  ( widget -- )
    DUP _TXTA-W !
    _TXTA-SCROLL-ADJ
    \ Compute selection range for draw pass
    _TXTA-HAS-SEL? IF
        _TXTA-SEL-RANGE _TXTA-DRW-SELE ! _TXTA-DRW-SELS !
    ELSE
        -1 _TXTA-DRW-SELS !
    THEN
    _TXTA-W @ _TXTA-O-GUTTER-W + @  _TXTA-DRW-GW !
    _TXTA-W @ _TXTA-O-SCROLL-X + @  _TXTA-DRW-SX !
    DUP WDG-REGION RGN-W  DUP _TXTA-DRW-RW !
    _TXTA-DRW-GW @ -  _TXTA-DRW-TW !
    WDG-REGION RGN-H                    ( vh )
    0 _TXTA-DRW-GBFLAT !
    \ Set up buffer pointers for sequential walk
    _TXTA-SCROLL _TXTA-LINE-OFF        ( vh off )
    _TXTA-GB? IF
        _TXTA-W @ _TXTA-O-DRAW-LINE-XT + @ IF
            \ Draw-line hook handles its own extraction per line
            DROP
        ELSE
            \ Default renderer in GB mode: flatten entire gap-buf
            _TXTA-GB GB-LEN 1 MAX ALLOCATE 0<> ABORT" draw:flat"
            ( vh off flat-buf )
            DUP _TXTA-DRW-GBFLAT !     \ save base for FREE later
            DUP _TXTA-GB GB-FLATTEN DROP  ( vh off flat-buf )
            OVER + _TXTA-DRW-A !       ( vh off )
            _TXTA-CONTENT-LEN SWAP - _TXTA-DRW-L !  ( vh )
        THEN
    ELSE
        _TXTA-BUF-A OVER + _TXTA-DRW-A !
        _TXTA-BUF-LEN SWAP - _TXTA-DRW-L !
    THEN
    \ Draw visible rows
    0 _TXTA-DRW-CDONE !
    _TXTA-SCROLL _TXTA-DRW-LINE# !
    0 ?DO
        I _TXTA-DRW-GUTTER
        I _TXTA-DRAW-LINE
        1 _TXTA-DRW-LINE# +!
    LOOP
    \ Free flattened copy if allocated
    _TXTA-DRW-GBFLAT @ ?DUP IF FREE DROP THEN ;

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
    _TXTA-CONTENT-LEN _TXTA-SYNC-CURSOR! ;

\ _TXTA-UNDO ( -- )
\   Undo the last edit operation via gap-buf + undo state.
: _TXTA-UNDO  ( -- )
    _TXTA-GB? 0= IF EXIT THEN
    _TXTA-UD 0= IF EXIT THEN
    _TXTA-GB _TXTA-UD UNDO-UNDO IF
        _TXTA-GB GB-CURSOR
        _TXTA-SYNC-CURSOR!
        _TXTA-SEL-CLEAR
        _TXTA-FIRE-CHANGE
        _TXTA-W @ WDG-DIRTY
    THEN ;

\ _TXTA-REDO ( -- )
\   Redo the last undone operation.
: _TXTA-REDO  ( -- )
    _TXTA-GB? 0= IF EXIT THEN
    _TXTA-UD 0= IF EXIT THEN
    _TXTA-GB _TXTA-UD UNDO-REDO IF
        _TXTA-GB GB-CURSOR
        _TXTA-SYNC-CURSOR!
        _TXTA-SEL-CLEAR
        _TXTA-FIRE-CHANGE
        _TXTA-W @ WDG-DIRTY
    THEN ;

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
            DUP [CHAR] z = IF          \ Ctrl+Z → undo
                DROP _TXTA-UNDO -1 EXIT
            THEN
            DUP [CHAR] y = IF          \ Ctrl+Y → redo
                DROP _TXTA-REDO -1 EXIT
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
    -1             OVER _TXTA-O-SEL-ANCHOR + !
    \ New Phase-0 fields (gap-buf, undo, hooks, gutter, h-scroll)
    0              OVER _TXTA-O-GB         + !
    0              OVER _TXTA-O-UNDO       + !
    0              OVER _TXTA-O-DRAW-LINE-XT + !
    0              OVER _TXTA-O-GUTTER-XT  + !
    0              OVER _TXTA-O-GUTTER-W   + !
    0              OVER _TXTA-O-SCROLL-X   + ! ;

\ TXTA-SET-TEXT ( text-a text-u widget -- )
\   In GB mode: calls GB-SET.  In flat mode: copies to flat buffer.
: TXTA-SET-TEXT  ( text-a text-u widget -- )
    >R
    R@ _TXTA-O-GB + @ IF
        \ GB mode — delegate to GB-SET, which clears and inserts
        R@ _TXTA-O-GB + @ GB-SET
        R@ _TXTA-O-GB + @ GB-LEN
        R@ _TXTA-O-CURSOR + !
        0 R@ _TXTA-O-SCROLL-Y + !
        0 R@ _TXTA-O-SCROLL-X + !
        -1 R@ _TXTA-O-SEL-ANCHOR + !
        R@ _TXTA-O-UNDO + @ ?DUP IF UNDO-CLEAR THEN
        R> WDG-DIRTY EXIT
    THEN
    R@ _TXTA-O-BUF-CAP + @ MIN
    DUP R@ _TXTA-O-BUF-LEN + !
    R@ _TXTA-O-BUF-A + @ SWAP CMOVE
    R@ _TXTA-O-BUF-LEN + @
    R@ _TXTA-O-CURSOR + !
    0 R@ _TXTA-O-SCROLL-Y + !
    0 R@ _TXTA-O-SCROLL-X + !
    -1 R@ _TXTA-O-SEL-ANCHOR + !
    R> WDG-DIRTY ;

\ TXTA-GET-TEXT ( widget -- addr len )
\   In GB mode: returns GB-FLATTEN result (caller must FREE).
\   In flat mode: returns pointer into flat buffer (no alloc).
: TXTA-GET-TEXT  ( widget -- addr len )
    DUP _TXTA-O-GB + @ IF
        _TXTA-O-GB + @ GB-FLATTEN EXIT
    THEN
    DUP _TXTA-O-BUF-A + @
    SWAP _TXTA-O-BUF-LEN + @ ;

\ TXTA-ON-CHANGE ( xt widget -- )
: TXTA-ON-CHANGE  ( xt widget -- )
    _TXTA-O-ON-CHANGE + ! ;

\ TXTA-CLEAR ( widget -- )
: TXTA-CLEAR  ( widget -- )
    DUP _TXTA-O-GB + @ IF
        DUP _TXTA-O-GB + @ GB-CLEAR
        DUP _TXTA-O-UNDO + @ ?DUP IF UNDO-CLEAR THEN
    ELSE
        0 OVER _TXTA-O-BUF-LEN + !
    THEN
    0 OVER _TXTA-O-CURSOR + !
    0 OVER _TXTA-O-SCROLL-Y + !
    0 OVER _TXTA-O-SCROLL-X + !
    -1 OVER _TXTA-O-SEL-ANCHOR + !
    WDG-DIRTY ;

\ TXTA-SCROLL-INFO ( widget -- content-h offset visible-h )
\   Return vertical scroll parameters for the scroll container.
: TXTA-SCROLL-INFO  ( widget -- content-h offset visible-h )
    _TXTA-W !
    _TXTA-LINE-COUNT
    _TXTA-W @ _TXTA-O-SCROLL-Y + @
    _TXTA-W @ WDG-REGION RGN-H ;

\ TXTA-SCROLL-SET ( offset widget -- )
\   Set vertical scroll offset directly (clamped).
: TXTA-SCROLL-SET  ( offset widget -- )
    >R
    R@ _TXTA-W !
    _TXTA-LINE-COUNT R@ WDG-REGION RGN-H -
    DUP 0< IF DROP 0 THEN              \ max scroll
    MIN  0 MAX                          \ clamp 0..max
    R@ _TXTA-O-SCROLL-Y + !
    R> WDG-DIRTY ;

\ TXTA-FREE ( widget -- )
: TXTA-FREE  ( widget -- )
    FREE ;

\ TXTA-CURSOR-LINE ( widget -- line )
\   Return 0-based cursor line number.
: TXTA-CURSOR-LINE  ( widget -- line )
    _TXTA-W ! _TXTA-CURSOR-LINE ;

\ TXTA-CURSOR-COL ( widget -- col )
\   Return 0-based cursor column (codepoint count from SOL).
: TXTA-CURSOR-COL  ( widget -- col )
    _TXTA-W ! _TXTA-CURSOR-COL ;

\ TXTA-GET-SEL ( widget -- addr len | 0 0 )
\   Return the selected text range.  Returns 0 0 if no selection.
\   In GB mode: copies to _TXTA-FLAT-BUF (max 1024 bytes).
\   In flat mode: returns pointer into flat buffer (no alloc).
: TXTA-GET-SEL  ( widget -- addr len | 0 0 )
    _TXTA-W !
    _TXTA-HAS-SEL? 0= IF 0 0 EXIT THEN
    _TXTA-SEL-RANGE              ( start end )
    OVER -                       ( start len )
    _TXTA-GB? IF
        1024 MIN                 ( start len' )
        SWAP                     ( len start )
        OVER 0 ?DO               ( len start )
            DUP I + _TXTA-GB GB-BYTE@
            _TXTA-FLAT-BUF I + C!
        LOOP
        DROP _TXTA-FLAT-BUF SWAP EXIT
    THEN
    SWAP _TXTA-BUF-A +           ( len addr )  \ addr = buf + start
    SWAP ;

\ TXTA-DEL-SEL ( widget -- flag )
\   Delete the selected text.  Returns TRUE if a selection existed.
: TXTA-DEL-SEL  ( widget -- flag )
    _TXTA-W !
    _TXTA-DEL-SEL DUP IF
        _TXTA-FIRE-CHANGE
        _TXTA-W @ WDG-DIRTY
    THEN ;

\ TXTA-INS-STR ( addr len widget -- )
\   Insert a string at cursor.  Deletes any active selection first.
: TXTA-INS-STR  ( addr len widget -- )
    _TXTA-W !
    _TXTA-DEL-SEL DROP
    _TXTA-INS-STR
    _TXTA-FIRE-CHANGE
    _TXTA-W @ WDG-DIRTY ;

\ TXTA-SELECT-ALL ( widget -- )
\   Select the entire buffer.
: TXTA-SELECT-ALL  ( widget -- )
    _TXTA-W ! _TXTA-SELECT-ALL ;

\ --- Phase-0 API: gap-buf / undo binding & hooks ---

\ TXTA-BIND-GB ( gb widget -- )
\   Attach a gap-buf to the textarea (enables GB mode).
\   The gap-buf is NOT owned — caller manages its lifetime.
: TXTA-BIND-GB  ( gb widget -- )
    _TXTA-O-GB + ! ;

\ TXTA-UNBIND-GB ( widget -- )
\   Detach gap-buf, reverting to flat-buffer mode.
: TXTA-UNBIND-GB  ( widget -- )
    0 SWAP _TXTA-O-GB + ! ;

\ TXTA-BIND-UNDO ( ud widget -- )
\   Attach an undo state to the textarea.
: TXTA-BIND-UNDO  ( ud widget -- )
    _TXTA-O-UNDO + ! ;

\ TXTA-UNBIND-UNDO ( widget -- )
\   Detach undo state.
: TXTA-UNBIND-UNDO  ( widget -- )
    0 SWAP _TXTA-O-UNDO + ! ;

\ TXTA-DRAW-LINE! ( xt widget -- )
\   Set the draw-line hook.  xt: ( addr u line# row col-off widget -- )
: TXTA-DRAW-LINE!  ( xt widget -- )
    _TXTA-O-DRAW-LINE-XT + ! ;

\ TXTA-GUTTER! ( xt width widget -- )
\   Set gutter callback & width.  xt: ( line# row width widget -- )
: TXTA-GUTTER!  ( xt width widget -- )
    >R R@ _TXTA-O-GUTTER-W + !
    R> _TXTA-O-GUTTER-XT + ! ;

\ TXTA-SCROLL-X@ ( widget -- n )
\   Get current horizontal scroll offset.
: TXTA-SCROLL-X@  ( widget -- n )
    _TXTA-O-SCROLL-X + @ ;

\ TXTA-SCROLL-X! ( n widget -- )
\   Set horizontal scroll offset.
: TXTA-SCROLL-X!  ( n widget -- )
    DUP >R _TXTA-O-SCROLL-X + !
    R> WDG-DIRTY ;

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
' TXTA-BIND-GB   CONSTANT _txta-bindgb-xt
' TXTA-UNBIND-GB CONSTANT _txta-unbindgb-xt
' TXTA-BIND-UNDO CONSTANT _txta-bindundo-xt
' TXTA-UNBIND-UNDO CONSTANT _txta-unbindundo-xt
' TXTA-DRAW-LINE! CONSTANT _txta-drawline-xt
' TXTA-GUTTER!    CONSTANT _txta-gutter-xt
' TXTA-SCROLL-X@  CONSTANT _txta-scrollxrd-xt
' TXTA-SCROLL-X!  CONSTANT _txta-scrollxwr-xt

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
: TXTA-BIND-GB   _txta-bindgb-xt  _txta-guard WITH-GUARD ;
: TXTA-UNBIND-GB _txta-unbindgb-xt _txta-guard WITH-GUARD ;
: TXTA-BIND-UNDO _txta-bindundo-xt _txta-guard WITH-GUARD ;
: TXTA-UNBIND-UNDO _txta-unbindundo-xt _txta-guard WITH-GUARD ;
: TXTA-DRAW-LINE! _txta-drawline-xt _txta-guard WITH-GUARD ;
: TXTA-GUTTER!    _txta-gutter-xt  _txta-guard WITH-GUARD ;
: TXTA-SCROLL-X@  _txta-scrollxrd-xt _txta-guard WITH-GUARD ;
: TXTA-SCROLL-X!  _txta-scrollxwr-xt _txta-guard WITH-GUARD ;
[THEN] [THEN]
