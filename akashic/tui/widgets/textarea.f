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
\  Dependencies: widget.f, draw.f, semantic-collections.f,
\                ../text/utf8.f, keys.f

PROVIDED akashic-tui-textarea

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../semantic-collections.f
REQUIRE ../../text/utf8.f
REQUIRE ../../text/gap-buf.f
REQUIRE ../../text/undo.f
REQUIRE ../../text/cell-width.f
REQUIRE ../keys.f

CREATE _TXTA-OWNED-START
VARIABLE _TXTA-OWNED-LIMIT
0 _TXTA-OWNED-LIMIT !

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

VARIABLE _TXTA-SA-GW      \ gutter width during scroll adjustment
VARIABLE _TXTA-SA-CLINE   \ cursor line
VARIABLE _TXTA-SA-VH      \ viewport height
VARIABLE _TXTA-SA-SX      \ horizontal scroll position
VARIABLE _TXTA-SA-TW      \ text viewport width
VARIABLE _TXTA-SA-CCOL    \ cursor column

: _TXTA-SCROLL-ADJ  ( -- )
    _TXTA-W @ _TXTA-O-GUTTER-W + @ _TXTA-SA-GW !
    _TXTA-CURSOR-LINE _TXTA-SA-CLINE !
    _TXTA-SA-CLINE @ _TXTA-SCROLL < IF
        \ Cursor above viewport — scroll up
        _TXTA-SA-CLINE @ _TXTA-W @ _TXTA-O-SCROLL-Y + !
        EXIT
    THEN
    _TXTA-W @ WDG-REGION RGN-H _TXTA-SA-VH !
    _TXTA-SA-CLINE @ _TXTA-SCROLL _TXTA-SA-VH @ + >= IF
        \ Cursor at or below viewport bottom — scroll down
        _TXTA-SA-CLINE @ _TXTA-SA-VH @ - 1+
        DUP 0< IF DROP 0 THEN
        _TXTA-W @ _TXTA-O-SCROLL-Y + !
    THEN
    \ --- Horizontal scroll adjustment ---
    \ A previous build could leave a negative scroll value here.  Clamp it
    \ explicitly: KDOS MAX currently compares unsigned values, so 0 MAX is
    \ not a signed clamp for a negative intermediate.
    _TXTA-W @ _TXTA-O-SCROLL-X + @
    DUP 0< IF
        DROP 0 DUP _TXTA-W @ _TXTA-O-SCROLL-X + !
    THEN
    _TXTA-SA-SX !
    _TXTA-W @ WDG-REGION RGN-W
    _TXTA-SA-GW @ - 1 MAX _TXTA-SA-TW !
    _TXTA-CURSOR-COL _TXTA-SA-CCOL !
    \ Cursor left of viewport?
    _TXTA-SA-CCOL @ _TXTA-SA-SX @ < IF
        _TXTA-SA-CCOL @ 4 -
        DUP 0< IF DROP 0 THEN
        _TXTA-W @ _TXTA-O-SCROLL-X + !
        EXIT
    THEN
    \ Cursor right of viewport?
    _TXTA-SA-CCOL @ _TXTA-SA-SX @ _TXTA-SA-TW @ + >= IF
        _TXTA-SA-CCOL @ _TXTA-SA-TW @ - 4 +
        _TXTA-W @ _TXTA-O-SCROLL-X + !
    THEN
;

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
VARIABLE _TXTA-DRW-GBFLAT \ if non-zero, ALLOCATEd visible copy (must FREE)
VARIABLE _TXTA-DRW-BASE   \ document byte offset at start of draw copy
VARIABLE _TXTA-DRW-TOTAL  \ total bytes available in draw copy
VARIABLE _TXTA-DRW-VH     \ viewport height for this paint pass
VARIABLE _TXTA-DRW-FIRST  \ first viewport row to repaint
VARIABLE _TXTA-DRW-COUNT  \ number of viewport rows to repaint

CREATE _TXTA-FLAT-BUF 1024 ALLOT   \ temp for GB line extraction (hook path)

\ _TXTA-DRW-BYTEOFF ( -- off )
\   Current document byte offset during draw.
: _TXTA-DRW-BYTEOFF  ( -- off )
    _TXTA-DRW-BASE @
    _TXTA-DRW-TOTAL @ _TXTA-DRW-L @ - + ;

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
VARIABLE _TXTA-DL-SKIP  \ codepoints clipped by horizontal scrolling

: _TXTA-DRAW-LINE  ( row -- )
    _TXTA-DRW-ROW !
    \ If draw-line hook is set and GB mode, use it
    _TXTA-W @ _TXTA-O-DRAW-LINE-XT + @ 0<>
    _TXTA-GB? AND IF
        \ Extract line bytes to flat buffer
        _TXTA-DRW-LINE# @  _TXTA-GB GB-LINE-LEN
        1024 MIN  DUP _TXTA-DL-LEN !
        _TXTA-DRW-LINE# @  _TXTA-GB GB-LINE-OFF  _TXTA-DL-OFF !
        \ Copy only this line from the gap buffer.
        _TXTA-DL-OFF @ _TXTA-FLAT-BUF _TXTA-DL-LEN @
        _TXTA-GB GB-COPY DROP
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
    \ Consume horizontally clipped codepoints before drawing.  Keeping the
    \ sequential pointer in sync also keeps selection/caret byte offsets
    \ correct for UTF-8 text.
    _TXTA-DRW-SX @ _TXTA-DL-SKIP !
    BEGIN
        _TXTA-DL-SKIP @ 0>
        _TXTA-DRW-L @ 0> AND
        _TXTA-DRW-A @ C@ 10 <> AND
    WHILE
        _TXTA-DRW-A @ _TXTA-DRW-L @ UTF8-DECODE
        _TXTA-DRW-L ! _TXTA-DRW-A ! DROP
        -1 _TXTA-DL-SKIP +!
    REPEAT
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
    \ A logical line wider than the viewport is clipped, not soft-wrapped.
    \ Consume its undisplayed tail so the next screen row begins at the next
    \ indexed/logical line.
    BEGIN
        _TXTA-DRW-L @ 0>
        _TXTA-DRW-A @ C@ 10 <> AND
    WHILE
        1 _TXTA-DRW-A +!
       -1 _TXTA-DRW-L +!
    REPEAT
    \ Skip past newline
    _TXTA-DRW-L @ 0 > IF
        _TXTA-DRW-A @ C@ 10 = IF
            1 _TXTA-DRW-A +!
            -1 _TXTA-DRW-L +!
        THEN
    THEN ;

\ _TXTA-DRAW-RANGE ( widget first count -- )
\   Scroll-adjust, set up state, and draw a range of viewport rows.
\   In GB mode with draw-line hook: per-line extraction from gap-buf.
\   In flat mode: sequential pointer walk as before.
: _TXTA-DRAW-RANGE  ( widget first count -- )
    _TXTA-DRW-COUNT ! _TXTA-DRW-FIRST !
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
    WDG-REGION RGN-H _TXTA-DRW-VH !
    _TXTA-DRW-FIRST @ DUP 0< IF DROP 0 THEN
    _TXTA-DRW-VH @ MIN _TXTA-DRW-FIRST !
    _TXTA-DRW-COUNT @ DUP 0< IF DROP 0 THEN
    _TXTA-DRW-VH @ _TXTA-DRW-FIRST @ - MIN _TXTA-DRW-COUNT !
    0 _TXTA-DRW-GBFLAT !
    \ Set up buffer pointers for a sequential visible-line walk.
    _TXTA-SCROLL _TXTA-DRW-FIRST @ +
    _TXTA-LINE-OFF DUP _TXTA-DRW-BASE !
    _TXTA-GB? IF
        _TXTA-W @ _TXTA-O-DRAW-LINE-XT + @ IF
            \ Draw-line hook handles its own extraction per line
            DROP
        ELSE
            DROP
            \ Default GB renderer copies only the logical lines that can
            \ appear in this viewport, rather than the whole document.
            _TXTA-SCROLL _TXTA-DRW-FIRST @ +
            _TXTA-DRW-COUNT @ + _TXTA-LINE-COUNT MIN
            DUP _TXTA-LINE-COUNT < IF
                _TXTA-LINE-OFF
            ELSE
                DROP _TXTA-CONTENT-LEN
            THEN
            _TXTA-DRW-BASE @ -
            DUP 0< IF DROP 0 THEN
            DUP _TXTA-DRW-TOTAL !
            \ Most viewports fit the module scratch buffer, avoiding an
            \ ALLOCATE/FREE pair on every keystroke.  Unusually large
            \ visible spans still fall back to a right-sized allocation.
            1024 <= IF
                _TXTA-FLAT-BUF
            ELSE
                _TXTA-DRW-TOTAL @ 1 MAX
                ALLOCATE 0<> ABORT" draw:visible"
                DUP _TXTA-DRW-GBFLAT !
            THEN
            _TXTA-DRW-BASE @ OVER _TXTA-DRW-TOTAL @
            _TXTA-GB GB-COPY DROP
            _TXTA-DRW-A !
            _TXTA-DRW-TOTAL @ _TXTA-DRW-L !
        THEN
    ELSE
        DUP _TXTA-BUF-A + _TXTA-DRW-A !
        _TXTA-BUF-LEN SWAP - DUP _TXTA-DRW-TOTAL !
        _TXTA-DRW-L !
    THEN
    \ Draw visible rows
    0 _TXTA-DRW-CDONE !
    _TXTA-SCROLL _TXTA-DRW-FIRST @ + _TXTA-DRW-LINE# !
    _TXTA-DRW-FIRST @ _TXTA-DRW-COUNT @ +
    _TXTA-DRW-FIRST @ ?DO
        I _TXTA-DRAW-LINE
        \ Draw the gutter last: the default renderer clears the full row.
        DRW-STYLE-SAVE
        I _TXTA-DRW-GUTTER
        DRW-STYLE-RESTORE
        1 _TXTA-DRW-LINE# +!
    LOOP
    \ Free flattened copy if allocated
    _TXTA-DRW-GBFLAT @ ?DUP IF FREE THEN ;

\ _TXTA-DRAW ( widget -- )
\   Standard widget draw repaints the complete viewport.
: _TXTA-DRAW  ( widget -- )
    DUP WDG-REGION RGN-H >R
    0 R> _TXTA-DRAW-RANGE ;

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
\   Return an allocated contiguous snapshot.  Caller must FREE addr.
: TXTA-GET-TEXT  ( widget -- addr len )
    DUP _TXTA-O-GB + @ IF
        _TXTA-O-GB + @
        DUP GB-LEN 1 MAX ALLOCATE 0<> ABORT" TXTA-GET-TEXT: alloc"
        DUP ROT GB-FLATTEN EXIT
    THEN
    DUP _TXTA-O-BUF-LEN + @ >R
    R@ 1 MAX ALLOCATE 0<> ABORT" TXTA-GET-TEXT: alloc"
    SWAP _TXTA-O-BUF-A + @ OVER R@ CMOVE
    R> ;

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

\ TXTA-ADJUST-SCROLL ( widget -- )
\   Apply the same cursor-visibility adjustment used by draw.  Composite
\   owners use this before deciding whether a row-local repaint is safe.
: TXTA-ADJUST-SCROLL  ( widget -- )
    _TXTA-W ! _TXTA-SCROLL-ADJ ;

\ TXTA-DRAW-ROWS ( first count widget -- )
\   Repaint only a caller-verified range of viewport rows and clean the
\   widget.  This is intended for edits known not to alter line mapping;
\   structural edits should use the normal full WDG-DRAW path.
: TXTA-DRAW-ROWS  ( first count widget -- )
    DUP WDG-VISIBLE? 0= IF DROP 2DROP EXIT THEN
    >R
    R@ WDG-REGION RGN-USE
    R@ -ROT _TXTA-DRAW-RANGE
    R> WDG-CLEAN ;

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
\  10. Renderer-neutral TEXT_AREA observation
\ =====================================================================
\
\ This is a read-only observation of the same canonical widget state used by
\ _TXTA-DRAW and _TXTA-HANDLE.  It does not know about UIDL attachments,
\ applets, rich-terminal protocols, retained identities, or publication
\ revisions.  The caller supplies the root key, builder scratch, and exact
\ output storage.  Destination 0/capacity 0 is exact measure mode.
\
\ Only document rows visible in the logical viewport, plus an off-viewport
\ caret or selection-anchor row, are copied.  Missing rows inside the logical
\ viewport are blank rows, not truncated content.  Each carried line has the
\ stable coordinate subkey line+1 and exact UTF-8 bytes excluding its newline.

VARIABLE _TXTA-SEM-ROOT-KEY
VARIABLE _TXTA-SEM-DST
VARIABLE _TXTA-SEM-CAP
VARIABLE _TXTA-SEM-BUILDER

VARIABLE _TXTA-SEM-CONTENT-U
VARIABLE _TXTA-SEM-LINE-SCALARS
VARIABLE _TXTA-SEM-MAX-SCALARS
VARIABLE _TXTA-SEM-ACTUAL-ROWS
VARIABLE _TXTA-SEM-SEG-A
VARIABLE _TXTA-SEM-SEG-U
VARIABLE _TXTA-SEM-SEG-I

VARIABLE _TXTA-SEM-CURSOR-LINE
VARIABLE _TXTA-SEM-CURSOR-COL
VARIABLE _TXTA-SEM-ANCHOR-LINE
VARIABLE _TXTA-SEM-ANCHOR-COL
VARIABLE _TXTA-SEM-ANCHOR?

VARIABLE _TXTA-SEM-RAW-H
VARIABLE _TXTA-SEM-RAW-W
VARIABLE _TXTA-SEM-GUTTER
VARIABLE _TXTA-SEM-ROOT-ROW
VARIABLE _TXTA-SEM-ROOT-COL
VARIABLE _TXTA-SEM-ROOT-H
VARIABLE _TXTA-SEM-ROOT-W

VARIABLE _TXTA-SEM-VROW
VARIABLE _TXTA-SEM-VCOL
VARIABLE _TXTA-SEM-VROW-END
VARIABLE _TXTA-SEM-VCOL-END
VARIABLE _TXTA-SEM-ROWS
VARIABLE _TXTA-SEM-COLS
VARIABLE _TXTA-SEM-STATE

VARIABLE _TXTA-SEM-POS
VARIABLE _TXTA-SEM-POS-OFF
VARIABLE _TXTA-SEM-POS-LINE
VARIABLE _TXTA-SEM-POS-COL

VARIABLE _TXTA-SEM-SPAN-A
VARIABLE _TXTA-SEM-SPAN-U
VARIABLE _TXTA-SEM-LIVE-A
VARIABLE _TXTA-SEM-LIVE-U
VARIABLE _TXTA-SEM-GB
VARIABLE _TXTA-SEM-GB-CAP
VARIABLE _TXTA-SEM-GB-GS
VARIABLE _TXTA-SEM-GB-GE
VARIABLE _TXTA-SEM-GB-LCAP
VARIABLE _TXTA-SEM-GB-LCNT
VARIABLE _TXTA-SEM-GB-LINE
VARIABLE _TXTA-SEM-GB-PREV
VARIABLE _TXTA-SEM-GB-OFF

VARIABLE _TXTA-SEM-EMIT-LINE
VARIABLE _TXTA-SEM-EMIT-OFF
VARIABLE _TXTA-SEM-EMIT-END
VARIABLE _TXTA-SEM-EMIT-U
VARIABLE _TXTA-SEM-EMIT-DST
VARIABLE _TXTA-SEM-CARRY-LINE

: _TXTA-SEM-U32?  ( value -- flag )
    DUP 0< IF DROP 0 EXIT THEN 0x100000000 U< ;

: _TXTA-SEM-POSITIVE-U32?  ( value -- flag )
    DUP 0> SWAP _TXTA-SEM-U32? AND ;

: _TXTA-SEM-AXIS?  ( origin extent -- flag )
    _TXTA-SEM-SPAN-U ! _TXTA-SEM-SPAN-A !
    _TXTA-SEM-SPAN-A @ _TXTA-SEM-U32? 0= IF 0 EXIT THEN
    _TXTA-SEM-SPAN-U @ _TXTA-SEM-POSITIVE-U32? 0= IF 0 EXIT THEN
    0x100000000 _TXTA-SEM-SPAN-A @ -
        _TXTA-SEM-SPAN-U @ U< 0= ;

: _TXTA-SEM-U32+  ( a b -- sum flag )
    + DUP _TXTA-SEM-U32? ;

-1 1 RSHIFT CONSTANT _TXTA-SEM-SIGNED-MAX

: _TXTA-SEM-STORAGE-SPAN?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _TXTA-SEM-WIDGET-STORAGE?  ( -- flag )
    _TXTA-W @ DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _TXTA-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _WDG-O-TYPE + @ WDG-T-TEXTAREA <> IF DROP 0 EXIT THEN
    DUP _WDG-O-DRAW-XT + @ ['] _TXTA-DRAW <> IF DROP 0 EXIT THEN
    DUP _WDG-O-HANDLE-XT + @ ['] _TXTA-HANDLE <> IF DROP 0 EXIT THEN
    WDG-REGION DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    RGN-SIZE MSPAN-NONWRAPPING? ;

: _TXTA-SEM-FLAT-STORAGE?  ( -- flag )
    _TXTA-BUF-A _TXTA-SEM-LIVE-A !
    _TXTA-BUF-CAP _TXTA-SEM-LIVE-U !
    _TXTA-SEM-LIVE-A @ _TXTA-SEM-LIVE-U @
        _TXTA-SEM-STORAGE-SPAN? 0= IF 0 EXIT THEN
    _TXTA-BUF-LEN DUP 0< IF DROP 0 EXIT THEN
    _TXTA-SEM-LIVE-U @ U> 0= ;

: _TXTA-SEM-GB-STORAGE?  ( -- flag )
    _TXTA-GB DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _TXTA-SEM-GB !
    _GB-DESC-SZ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN

    _TXTA-SEM-GB @ _GB-O-CAP + @ DUP 0> 0= IF DROP 0 EXIT THEN
        _TXTA-SEM-GB-CAP !
    _TXTA-SEM-GB @ _GB-O-BUF + @ _TXTA-SEM-GB-CAP @
        _TXTA-SEM-STORAGE-SPAN? 0= IF 0 EXIT THEN
    _TXTA-SEM-GB @ _GB-O-GS + @ DUP 0< IF DROP 0 EXIT THEN
    DUP _TXTA-SEM-GB-CAP @ U> IF DROP 0 EXIT THEN
        _TXTA-SEM-GB-GS !
    _TXTA-SEM-GB @ _GB-O-GE + @ DUP 0< IF DROP 0 EXIT THEN
    DUP _TXTA-SEM-GB-CAP @ U> IF DROP 0 EXIT THEN
        _TXTA-SEM-GB-GE !
    _TXTA-SEM-GB-GS @ _TXTA-SEM-GB-GE @ U> IF 0 EXIT THEN

    _TXTA-SEM-GB @ _GB-O-LCAP + @ DUP 0> 0= IF DROP 0 EXIT THEN
    DUP _TXTA-SEM-SIGNED-MAX _GB-LIDX-SZ / U> IF DROP 0 EXIT THEN
        _TXTA-SEM-GB-LCAP !
    _TXTA-SEM-GB @ _GB-O-LIDX + @ DUP 3 AND IF DROP 0 EXIT THEN
    _TXTA-SEM-GB-LCAP @ _GB-LIDX-SZ *
        _TXTA-SEM-STORAGE-SPAN? 0= IF 0 EXIT THEN
    _TXTA-SEM-GB @ _GB-O-LCNT + @ DUP 0> 0= IF DROP 0 EXIT THEN
    DUP _TXTA-SEM-GB-LCAP @ U> IF DROP 0 EXIT THEN
    _TXTA-SEM-GB-LCNT !
    -1 ;

: _TXTA-SEM-SOURCE-STORAGE?  ( -- flag )
    _TXTA-SEM-WIDGET-STORAGE? 0= IF 0 EXIT THEN
    _TXTA-GB? IF _TXTA-SEM-GB-STORAGE? ELSE _TXTA-SEM-FLAT-STORAGE? THEN ;

: _TXTA-SEM-MODULE-OVERLAP?  ( -- flag )
    _TXTA-OWNED-LIMIT @ DUP _TXTA-OWNED-START U< IF DROP -1 EXIT THEN
    _TXTA-OWNED-START - >R
    _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
        _TXTA-OWNED-START R> MSPAN-OVERLAP? ;

\ True when a caller scratch/output span aliases widget state that must remain
\ readable throughout capture.  The builder checks its own span and its
\ disjointness from the destination separately.
: _TXTA-SEM-SOURCE-OVERLAP?  ( address bytes -- flag )
    _TXTA-SEM-SPAN-U ! _TXTA-SEM-SPAN-A !
    _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
        _TXTA-SEM-STORAGE-SPAN? 0= IF -1 EXIT THEN
    _TXTA-SEM-SOURCE-STORAGE? 0= IF -1 EXIT THEN
    _TXTA-SEM-SPAN-U @ 0= IF 0 EXIT THEN
    \ Gap-backed observation calls GB-POS-LINE-COL, GB-LINE-LEN, and
    \ GB-COPY.  Reject the gap-buffer module's shared scratch before any
    \ of those lower-layer words can mutate it through a caller alias.
    _TXTA-GB? IF
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
            GB-STORAGE-DISJOINT? 0= IF -1 EXIT THEN
    THEN
    _TXTA-SEM-MODULE-OVERLAP? IF -1 EXIT THEN
    _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
        _TXTA-W @ _TXTA-DESC-SIZE MSPAN-OVERLAP? IF -1 EXIT THEN
    _TXTA-W @ WDG-REGION ?DUP IF
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
            ROT RGN-SIZE MSPAN-OVERLAP? IF -1 EXIT THEN
    THEN
    _TXTA-GB? IF
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
            _TXTA-GB _GB-DESC-SZ MSPAN-OVERLAP? IF -1 EXIT THEN
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
            _TXTA-GB _GB-O-BUF + @ _TXTA-GB _GB-O-CAP + @
            MSPAN-OVERLAP? IF -1 EXIT THEN
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
            _TXTA-GB _GB-O-LIDX + @
            _TXTA-GB _GB-O-LCAP + @ _GB-LIDX-SZ *
            MSPAN-OVERLAP? IF -1 EXIT THEN
    ELSE
        _TXTA-BUF-A _TXTA-BUF-CAP
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @
            MSPAN-OVERLAP? IF -1 EXIT THEN
    THEN
    0 ;

\ TXTA-TEXT-AREA-STORAGE-DISJOINT?
\   ( address bytes widget -- flag )
\   Check arbitrary caller scratch against every live span borrowed by the
\   TEXT_AREA observation.  Upper collectors use this before validation or
\   descriptor work that the capture call itself does not receive.
: TXTA-TEXT-AREA-STORAGE-DISJOINT?  ( address bytes widget -- flag )
    _TXTA-W !
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _TXTA-SEM-SOURCE-OVERLAP? 0= ;

\ Scan one contiguous physical segment while preserving logical line state
\ across the gap boundary.  A normal edit cursor is always on a scalar
\ boundary, but counting scalar-leading bytes remains correct even for an
\ invalid split; the upper deep validator is the sole UTF-8 authority.
: _TXTA-SEM-SCAN-SEGMENT  ( address bytes -- status )
    _TXTA-SEM-SEG-U ! _TXTA-SEM-SEG-A !
    0 _TXTA-SEM-SEG-I !
    BEGIN _TXTA-SEM-SEG-I @ _TXTA-SEM-SEG-U @ U< WHILE
        _TXTA-SEM-SEG-A @ _TXTA-SEM-SEG-I @ + C@
        DUP 10 = IF
            DROP
            _TXTA-SEM-LINE-SCALARS @ _TXTA-SEM-MAX-SCALARS @ MAX
                _TXTA-SEM-MAX-SCALARS !
            0 _TXTA-SEM-LINE-SCALARS !
            1 _TXTA-SEM-ACTUAL-ROWS +!
            _TXTA-SEM-ACTUAL-ROWS @ _TXTA-SEM-U32? 0= IF
                USCOL-S-INVALID EXIT
            THEN
        ELSE
            0xC0 AND 0x80 <> IF
                1 _TXTA-SEM-LINE-SCALARS +!
                _TXTA-SEM-LINE-SCALARS @ _TXTA-SEM-U32? 0= IF
                    USCOL-S-INVALID EXIT
                THEN
            THEN
        THEN
        1 _TXTA-SEM-SEG-I +!
    REPEAT
    USCOL-S-OK ;

\ Prove that the separately allocated packed gap-buffer line index describes
\ exactly the logical LF boundaries just counted from the authoritative byte
\ segments.  This must precede GB-POS-LINE-COL/GB-LINE-OFF use: a merely
\ in-range LCNT does not make stale or forged offsets safe semantic input.
: _TXTA-SEM-GB-INDEX?  ( -- flag )
    _TXTA-SEM-ACTUAL-ROWS @ _TXTA-SEM-GB-LCNT @ <> IF 0 EXIT THEN
    _TXTA-SEM-GB @ _GB-O-LIDX + @ L@ 0<> IF 0 EXIT THEN
    0 _TXTA-SEM-GB-PREV !
    1 _TXTA-SEM-GB-LINE !
    BEGIN _TXTA-SEM-GB-LINE @ _TXTA-SEM-GB-LCNT @ U< WHILE
        _TXTA-SEM-GB @ _GB-O-LIDX + @
        _TXTA-SEM-GB-LINE @ _GB-LIDX-SZ * + L@
        DUP _TXTA-SEM-GB-OFF !
        _TXTA-SEM-GB-PREV @ U> 0= IF 0 EXIT THEN
        _TXTA-SEM-GB-OFF @ _TXTA-SEM-CONTENT-U @ U> IF 0 EXIT THEN
        _TXTA-SEM-GB-OFF @ 1- _TXTA-CONTENT-BYTE@ 10 <> IF 0 EXIT THEN
        _TXTA-SEM-GB-OFF @ _TXTA-SEM-GB-PREV !
        1 _TXTA-SEM-GB-LINE +!
    REPEAT
    -1 ;

\ Scan once for logical row count and the maximum Unicode-scalar line width.
\ GB mode walks the two borrowed physical segments directly rather than doing
\ one guarded GB-BYTE@ call per byte.
: _TXTA-SEM-SCAN-SHAPE  ( -- status )
    _TXTA-CONTENT-LEN DUP 0< IF DROP USCOL-S-INVALID EXIT THEN
    DUP _TXTA-SEM-CONTENT-U !
    DUP _TXTA-SEM-U32? 0= IF DROP USCOL-S-INVALID EXIT THEN DROP
    0 _TXTA-SEM-LINE-SCALARS !
    1 _TXTA-SEM-MAX-SCALARS !
    1 _TXTA-SEM-ACTUAL-ROWS !
    _TXTA-GB? IF
        _TXTA-GB GB-PRE _TXTA-SEM-SCAN-SEGMENT
        DUP USCOL-S-OK <> IF EXIT THEN DROP
        _TXTA-GB GB-POST _TXTA-SEM-SCAN-SEGMENT
        DUP USCOL-S-OK <> IF EXIT THEN DROP
    ELSE
        _TXTA-BUF-A _TXTA-BUF-LEN _TXTA-SEM-SCAN-SEGMENT
        DUP USCOL-S-OK <> IF EXIT THEN DROP
    THEN
    _TXTA-GB? IF
        _TXTA-SEM-GB-INDEX? 0= IF USCOL-S-INVALID EXIT THEN
    THEN
    _TXTA-SEM-LINE-SCALARS @ _TXTA-SEM-MAX-SCALARS @ MAX
        1 MAX _TXTA-SEM-MAX-SCALARS !
    USCOL-S-OK ;

\ Resolve an arbitrary byte position without moving the authoritative cursor.
: _TXTA-SEM-POSITION  ( byte-offset -- line scalar-column status )
    DUP 0< IF DROP 0 0 USCOL-S-INVALID EXIT THEN
    DUP _TXTA-SEM-CONTENT-U @ U> IF
        DROP 0 0 USCOL-S-INVALID EXIT
    THEN
    DUP 0> OVER _TXTA-SEM-CONTENT-U @ U< AND IF
        DUP _TXTA-CONTENT-BYTE@ 0xC0 AND 0x80 = IF
            DROP 0 0 USCOL-S-INVALID EXIT
        THEN
    THEN
    _TXTA-GB? IF
        _TXTA-GB GB-POS-LINE-COL USCOL-S-OK EXIT
    THEN
    _TXTA-SEM-POS !
    0 _TXTA-SEM-POS-OFF !
    0 _TXTA-SEM-POS-LINE !
    0 _TXTA-SEM-POS-COL !
    BEGIN _TXTA-SEM-POS-OFF @ _TXTA-SEM-POS @ U< WHILE
        _TXTA-SEM-POS-OFF @ _TXTA-CONTENT-BYTE@
        DUP 10 = IF
            DROP
            1 _TXTA-SEM-POS-LINE +!
            0 _TXTA-SEM-POS-COL !
            1 _TXTA-SEM-POS-OFF +!
        ELSE
            _UTF8-SEQLEN DUP 0= IF DROP 1 THEN
            _TXTA-SEM-POS-OFF @ + _TXTA-SEM-POS @ MIN
                _TXTA-SEM-POS-OFF !
            1 _TXTA-SEM-POS-COL +!
        THEN
    REPEAT
    _TXTA-SEM-POS-LINE @ _TXTA-SEM-POS-COL @ USCOL-S-OK ;

: _TXTA-SEM-POSITIONS  ( -- status )
    _TXTA-CURSOR _TXTA-SEM-POSITION
    DUP USCOL-S-OK <> IF >R 2DROP R> EXIT THEN DROP
    _TXTA-SEM-CURSOR-COL ! _TXTA-SEM-CURSOR-LINE !
    _TXTA-SEL-ANCHOR -1 = IF
        0 _TXTA-SEM-ANCHOR? !
        0 _TXTA-SEM-ANCHOR-LINE !
        0 _TXTA-SEM-ANCHOR-COL !
        USCOL-S-OK EXIT
    THEN
    _TXTA-SEL-ANCHOR _TXTA-SEM-POSITION
    DUP USCOL-S-OK <> IF >R 2DROP R> EXIT THEN DROP
    _TXTA-SEM-ANCHOR-COL ! _TXTA-SEM-ANCHOR-LINE !
    -1 _TXTA-SEM-ANCHOR? !
    USCOL-S-OK ;

\ Derive widget-region-relative content geometry.  Translation into a chosen
\ retained region and effective clipping belong to the upper aggregate; doing
\ either here would make a clipped child reflow instead of preserving the
\ stable ordinary draw anchor.
: _TXTA-SEM-GEOMETRY  ( -- status )
    _TXTA-W @ WDG-REGION DUP 0= IF DROP USCOL-S-INVALID EXIT THEN
    DUP RGN-H _TXTA-SEM-RAW-H !
    DUP RGN-W _TXTA-SEM-RAW-W !
    DROP
    _TXTA-SEM-RAW-H @ _TXTA-SEM-POSITIVE-U32? 0= IF
        USCOL-S-UNAVAILABLE EXIT
    THEN
    _TXTA-SEM-RAW-W @ _TXTA-SEM-POSITIVE-U32? 0= IF
        USCOL-S-UNAVAILABLE EXIT
    THEN
    _TXTA-W @ _TXTA-O-GUTTER-W + @
    DUP 0< IF DROP 0 THEN
        _TXTA-SEM-RAW-W @ MIN _TXTA-SEM-GUTTER !
    _TXTA-SEM-RAW-W @ _TXTA-SEM-GUTTER @ - 0 MAX
    DUP 0= IF DROP USCOL-S-UNAVAILABLE EXIT THEN
    _TXTA-SEM-ROOT-W !
    _TXTA-SEM-RAW-H @ _TXTA-SEM-ROOT-H !
    0 _TXTA-SEM-ROOT-ROW !
    _TXTA-SEM-GUTTER @ _TXTA-SEM-ROOT-COL !
    _TXTA-SEM-ROOT-ROW @ _TXTA-SEM-ROOT-H @ _TXTA-SEM-AXIS? 0= IF
        USCOL-S-INVALID EXIT
    THEN
    _TXTA-SEM-ROOT-COL @ _TXTA-SEM-ROOT-W @ _TXTA-SEM-AXIS? 0= IF
        USCOL-S-INVALID EXIT
    THEN
    _TXTA-SCROLL DUP _TXTA-SEM-U32? 0= IF
        DROP USCOL-S-INVALID EXIT
    THEN
    _TXTA-SEM-VROW !
    _TXTA-W @ _TXTA-O-SCROLL-X + @ DUP _TXTA-SEM-U32? 0= IF
        DROP USCOL-S-INVALID EXIT
    THEN
    _TXTA-SEM-VCOL !
    _TXTA-SEM-VROW @ _TXTA-SEM-ROOT-H @
        _TXTA-SEM-U32+ 0= IF DROP USCOL-S-INVALID EXIT THEN
        DUP _TXTA-SEM-VROW-END !
    _TXTA-SEM-ACTUAL-ROWS @ MAX _TXTA-SEM-ROWS !
    _TXTA-SEM-VCOL @ _TXTA-SEM-ROOT-W @
        _TXTA-SEM-U32+ 0= IF DROP USCOL-S-INVALID EXIT THEN
        DUP _TXTA-SEM-VCOL-END !
    _TXTA-SEM-MAX-SCALARS @ MAX 1 MAX _TXTA-SEM-COLS !
    0
    _TXTA-W @ WDG-VISIBLE? IF USCOL-STATE-VISIBLE OR THEN
    _TXTA-W @ WDG-DISABLED? 0= IF USCOL-STATE-ENABLED OR THEN
    _TXTA-W @ WDG-FOCUSED?
    _TXTA-W @ WDG-VISIBLE? AND
    _TXTA-W @ WDG-DISABLED? 0= AND IF USCOL-STATE-SELECTED OR THEN
    _TXTA-SEM-STATE !
    USCOL-S-OK ;

: _TXTA-SEM-CARRY-ROW?  ( row -- flag )
    DUP _TXTA-SEM-CARRY-LINE !
    _TXTA-SEM-VROW @ U< 0=
    _TXTA-SEM-CARRY-LINE @ _TXTA-SEM-VROW-END @ U< AND
    _TXTA-SEM-CARRY-LINE @ _TXTA-SEM-CURSOR-LINE @ = OR
    _TXTA-SEM-ANCHOR? @ IF
        _TXTA-SEM-CARRY-LINE @ _TXTA-SEM-ANCHOR-LINE @ = OR
    THEN ;

: _TXTA-SEM-FIND-LINE-END  ( -- )
    _TXTA-SEM-EMIT-OFF @ _TXTA-SEM-EMIT-END !
    BEGIN
        _TXTA-SEM-EMIT-END @ _TXTA-SEM-CONTENT-U @ U<
        IF _TXTA-SEM-EMIT-END @ _TXTA-CONTENT-BYTE@ 10 <> ELSE 0 THEN
    WHILE
        1 _TXTA-SEM-EMIT-END +!
    REPEAT
    _TXTA-SEM-EMIT-END @ _TXTA-SEM-EMIT-OFF @ -
        _TXTA-SEM-EMIT-U ! ;

: _TXTA-SEM-INDEX-GB-LINE  ( -- )
    _TXTA-SEM-EMIT-LINE @ _TXTA-GB GB-LINE-OFF
        _TXTA-SEM-EMIT-OFF !
    _TXTA-SEM-EMIT-LINE @ _TXTA-GB GB-LINE-LEN
        DUP _TXTA-SEM-EMIT-U !
    _TXTA-SEM-EMIT-OFF @ + _TXTA-SEM-EMIT-END ! ;

: _TXTA-SEM-EMIT-ONE  ( -- status )
    _TXTA-SEM-EMIT-LINE @ 1+
    _TXTA-SEM-EMIT-LINE @ 0 1 _TXTA-SEM-COLS @
    USCOL-ROLE-CONTENT 0 _TXTA-SEM-EMIT-U @ _TXTA-SEM-BUILDER @
        USCOL-TEXT-ITEM-BEGIN
    DUP USCOL-S-OK <> IF NIP EXIT THEN DROP
    _TXTA-SEM-EMIT-DST !
    _TXTA-SEM-EMIT-DST @ IF
        _TXTA-GB? IF
            _TXTA-SEM-EMIT-OFF @ _TXTA-SEM-EMIT-DST @
            _TXTA-SEM-EMIT-U @ _TXTA-GB GB-COPY
            _TXTA-SEM-EMIT-U @ <> IF
                _TXTA-SEM-BUILDER @ USCOL-BUILDER-INVALID EXIT
            THEN
        ELSE
            _TXTA-BUF-A _TXTA-SEM-EMIT-OFF @ +
            _TXTA-SEM-EMIT-DST @ _TXTA-SEM-EMIT-U @ MOVE
        THEN
    THEN
    _TXTA-SEM-BUILDER @ USCOL-TEXT-ITEM-END ;

: _TXTA-SEM-EMIT-ROWS  ( -- status )
    0 _TXTA-SEM-EMIT-LINE !
    0 _TXTA-SEM-EMIT-OFF !
    BEGIN _TXTA-SEM-EMIT-LINE @ _TXTA-SEM-ACTUAL-ROWS @ U< WHILE
        _TXTA-GB? IF
            _TXTA-SEM-EMIT-LINE @ _TXTA-SEM-CARRY-ROW? IF
                _TXTA-SEM-INDEX-GB-LINE
                _TXTA-SEM-EMIT-ONE
                DUP USCOL-S-OK <> IF EXIT THEN DROP
            THEN
        ELSE
            _TXTA-SEM-FIND-LINE-END
            _TXTA-SEM-EMIT-LINE @ _TXTA-SEM-CARRY-ROW? IF
                _TXTA-SEM-EMIT-ONE
                DUP USCOL-S-OK <> IF EXIT THEN DROP
            THEN
            _TXTA-SEM-EMIT-END @ _TXTA-SEM-EMIT-OFF !
            _TXTA-SEM-EMIT-OFF @ _TXTA-SEM-CONTENT-U @ U< IF
                1 _TXTA-SEM-EMIT-OFF +!
            THEN
        THEN
        1 _TXTA-SEM-EMIT-LINE +!
    REPEAT
    USCOL-S-OK ;

\ TXTA-TEXT-AREA-CAPTURE
\   ( root-key destination capacity builder widget -- bytes status )
\   Build one pointer-free TEXT_AREA entry from canonical textarea state.
\   The consumer performs the one deep validation before freezing/publication.
: TXTA-TEXT-AREA-CAPTURE
    ( root-key destination capacity builder widget -- bytes status )
    _TXTA-W ! _TXTA-SEM-BUILDER ! _TXTA-SEM-CAP !
    _TXTA-SEM-DST ! _TXTA-SEM-ROOT-KEY !
    _TXTA-SEM-ROOT-KEY @ 0= IF 0 USCOL-S-INVALID EXIT THEN
    _TXTA-SEM-BUILDER @ USCOL-BUILDER-SIZE
        USCOL-STORAGE-DISJOINT? 0= IF 0 USCOL-S-INVALID EXIT THEN
    _TXTA-SEM-DST @ _TXTA-SEM-CAP @
        USCOL-STORAGE-DISJOINT? 0= IF 0 USCOL-S-INVALID EXIT THEN
    _TXTA-SEM-BUILDER @ USCOL-BUILDER-SIZE
        _TXTA-SEM-SOURCE-OVERLAP? IF 0 USCOL-S-INVALID EXIT THEN
    _TXTA-SEM-DST @ _TXTA-SEM-CAP @
        _TXTA-SEM-SOURCE-OVERLAP? IF 0 USCOL-S-INVALID EXIT THEN
    _TXTA-SEM-DST @ _TXTA-SEM-CAP @ _TXTA-SEM-BUILDER @
        USCOL-BUILDER-INIT
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TXTA-SEM-SCAN-SHAPE
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TXTA-SEM-POSITIONS
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TXTA-SEM-GEOMETRY
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    USCOL-F-TEXT-AREA _TXTA-SEM-ROOT-KEY @
    _TXTA-SEM-ROOT-ROW @ _TXTA-SEM-ROOT-COL @
    _TXTA-SEM-ROOT-H @ _TXTA-SEM-ROOT-W @ _TXTA-SEM-STATE @
    _TXTA-SEM-BUILDER @ USCOL-TEXT-BEGIN
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    0 _TXTA-SEM-ROWS @ _TXTA-SEM-COLS @
    _TXTA-SEM-VROW @ _TXTA-SEM-VCOL @
    _TXTA-SEM-ROOT-H @ _TXTA-SEM-ROOT-W @ _TXTA-SEM-BUILDER @
        USCOL-TEXT-SHAPE
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TXTA-SEM-CURSOR-LINE @ 1+
    _TXTA-SEM-ANCHOR? @ IF _TXTA-SEM-ANCHOR-LINE @ 1+ ELSE 0 THEN
    _TXTA-SEM-CURSOR-COL @
    _TXTA-SEM-ANCHOR? @ IF _TXTA-SEM-ANCHOR-COL @ ELSE 0 THEN
    _TXTA-SEM-BUILDER @ USCOL-TEXT-POSITIONS
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TXTA-SEM-EMIT-ROWS
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TXTA-SEM-BUILDER @ USCOL-TEXT-END
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TXTA-SEM-BUILDER @ USCOL-BUILDER-FINISH ;

\ TXTA-TEXT-AREA-MEASURE ( root-key builder widget -- bytes status )
: TXTA-TEXT-AREA-MEASURE  ( root-key builder widget -- bytes status )
    >R >R 0 0 R> R> TXTA-TEXT-AREA-CAPTURE ;

\ =====================================================================
\  11. Guard
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
' TXTA-ADJUST-SCROLL CONSTANT _txta-adjustscroll-xt
' TXTA-DRAW-ROWS  CONSTANT _txta-drawrows-xt
' TXTA-SCROLL-X@  CONSTANT _txta-scrollxrd-xt
' TXTA-SCROLL-X!  CONSTANT _txta-scrollxwr-xt
' TXTA-TEXT-AREA-CAPTURE CONSTANT _txta-text-area-capture-xt
' TXTA-TEXT-AREA-MEASURE CONSTANT _txta-text-area-measure-xt
' TXTA-TEXT-AREA-STORAGE-DISJOINT?
    CONSTANT _txta-text-area-storage-disjoint-q-xt

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
: TXTA-ADJUST-SCROLL _txta-adjustscroll-xt _txta-guard WITH-GUARD ;
: TXTA-DRAW-ROWS  _txta-drawrows-xt _txta-guard WITH-GUARD ;
: TXTA-SCROLL-X@  _txta-scrollxrd-xt _txta-guard WITH-GUARD ;
: TXTA-SCROLL-X!  _txta-scrollxwr-xt _txta-guard WITH-GUARD ;
: TXTA-TEXT-AREA-CAPTURE
                  _txta-text-area-capture-xt _txta-guard WITH-GUARD ;
: TXTA-TEXT-AREA-MEASURE
                  _txta-text-area-measure-xt _txta-guard WITH-GUARD ;
: TXTA-TEXT-AREA-STORAGE-DISJOINT?
                  _txta-text-area-storage-disjoint-q-xt
                  _txta-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _TXTA-OWNED-END
_TXTA-OWNED-END _TXTA-OWNED-LIMIT !
