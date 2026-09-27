\ =====================================================================
\  akashic/tui/input.f — Single-line Text Input Field
\ =====================================================================
\
\  A single-line editable text field with cursor, supporting:
\    - Text laid out as the shared text rules say: wide characters,
\      clusters, and right-to-left text (section 2)
\    - Backspace and Delete of whole characters
\    - Cursor movement over whole characters: left, right, Home, End, and
\      a primary press
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
\    +72      scroll          Horizontal scroll in cells, from the start edge
\    +80      placeholder-a   Placeholder text address
\    +88      placeholder-u   Placeholder text length
\    +96      submit-xt       Callback on Enter ( widget -- )
\    +104     mask-cp         Draw this codepoint instead of input (0 = plain)
\    +112     anchor          Selection anchor byte offset (-1 = none)
\    +120     pressed         True while a primary press made here is held
\
\  Prefix: INP- (public), _INP- (internal)
\  Provider: akashic-tui-input
\  Dependencies: widget.f, draw.f, ../text/utf8.f, ../text/grapheme.f,
\                ../text/text-row.f, ../text/cell-width.f, keys.f

PROVIDED akashic-tui-input

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../../text/utf8.f
REQUIRE ../../text/grapheme.f
REQUIRE ../../text/text-row.f
REQUIRE ../../text/cell-width.f
REQUIRE ../keys.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _INP-O-BUF-A        \ buffer address
48 CONSTANT _INP-O-BUF-CAP      \ buffer capacity (bytes)
56 CONSTANT _INP-O-BUF-LEN      \ current content length (bytes)
64 CONSTANT _INP-O-CURSOR        \ cursor byte offset
72 CONSTANT _INP-O-SCROLL        \ scroll offset (cells)
80 CONSTANT _INP-O-PH-A          \ placeholder text address
88 CONSTANT _INP-O-PH-U          \ placeholder text length
96 CONSTANT _INP-O-SUBMIT-XT     \ submit callback xt (0 = none)
104 CONSTANT _INP-O-MASK-CP      \ replacement codepoint (0 = unmasked)
112 CONSTANT _INP-O-ANCHOR       \ selection anchor byte offset (-1 = none)
120 CONSTANT _INP-O-PRESSED      \ primary press made here is held

128 CONSTANT _INP-DESC-SIZE       \ total descriptor size

\ =====================================================================
\ 2. Characters and cells
\ =====================================================================
\
\  The field's text is one paragraph of automatic direction, laid out by
\  text-row.f as the shared text rules say (APT-1-TEXT).  The caret moves
\  over whole characters (grapheme clusters), and Backspace and Delete
\  remove whole characters.  Characters take their cells in visual order:
\  left-to-right text starts at the field's left edge, right-to-left text
\  is mirrored and starts at its right edge, and the scroll moves the text
\  away from its start edge.  Printable ASCII needs no layout.  A masked
\  field shows one mask cell per character, left to right, and so does a
\  field whose text cannot be laid out for lack of memory, with U+FFFD
\  for anything but printable ASCII.
\
\  A visual column V counts cells from the text's left end.  In a field
\  FW cells wide, V shows at V plus the origin: minus the scroll for
\  left-to-right text, and FW - W plus the scroll for right-to-left text
\  W cells wide.  The words below work on the field _INP-PREP prepared.

CREATE _INP-ROW TROW-SIZE ALLOT  _INP-ROW TROW-INIT
CREATE _INP-GC GR-CURSOR-SIZE ALLOT
VARIABLE _INP-W          \ the prepared field
VARIABLE _INP-KIND       \ how its text maps to cells
VARIABLE _INP-CHARS      \ its characters, for _INP-K-UNITS
0 CONSTANT _INP-K-ASCII  \ printable ASCII: byte I in visual column I
1 CONSTANT _INP-K-ROW    \ laid out in _INP-ROW
2 CONSTANT _INP-K-UNITS  \ one cell per character, left to right

: _INP-A    ( -- a )   _INP-W @ _INP-O-BUF-A + @ ;
: _INP-U    ( -- u )   _INP-W @ _INP-O-BUF-LEN + @ ;
: _INP-CUR  ( -- off ) _INP-W @ _INP-O-CURSOR + @ ;
: _INP-FW   ( -- w )   _INP-W @ WDG-REGION RGN-W ;
: _INP-SX   ( -- n )   _INP-W @ _INP-O-SCROLL + @ 0 MAX ;

: _INP-ASCII?  ( -- flag )
    _INP-A _INP-U OVER + SWAP ?DO
        I C@ 0x20 0x7F WITHIN 0= IF UNLOOP 0 EXIT THEN
    LOOP -1 ;

\ _INP-CHARS-IN ( u -- n )   The characters in the text's first U bytes.
: _INP-CHARS-IN  ( u -- n )
    _INP-A SWAP GR-F-TAB _INP-GC GR-CURSOR-INIT
    0 BEGIN _INP-GC GR-NEXT WHILE 1+ REPEAT ;

\ _INP-CHAR-END ( n -- off )   The byte offset after N characters.
: _INP-CHAR-END  ( n -- off )
    DUP 0> 0= IF DROP 0 EXIT THEN
    _INP-A _INP-U GR-F-TAB _INP-GC GR-CURSOR-INIT
    0 SWAP 0 ?DO
        _INP-GC GR-NEXT 0= IF LEAVE THEN
        DROP _INP-GC GR-C-ADDR _INP-GC GR-C-BYTES + _INP-A -
    LOOP ;

\ _INP-PREP ( widget -- )   Take the field's text and lay it out.
: _INP-PREP  ( widget -- )
    _INP-W !
    _INP-W @ _INP-O-MASK-CP + @ 0= IF
        _INP-ASCII? IF _INP-K-ASCII _INP-KIND ! EXIT THEN
        _INP-A _INP-U TROW-F-TAB BIDI-AUTO _INP-ROW TROW-LAYOUT IF
            _INP-K-ROW _INP-KIND ! EXIT
        THEN
    THEN
    _INP-K-UNITS _INP-KIND !
    _INP-U _INP-CHARS-IN _INP-CHARS ! ;

\ The text's width in cells, and its direction.
: _INP-TW  ( -- cells )
    _INP-KIND @ _INP-K-ROW = IF _INP-ROW TROW-WIDTH EXIT THEN
    _INP-KIND @ _INP-K-ASCII = IF _INP-U EXIT THEN
    _INP-CHARS @ ;

: _INP-RTL?  ( -- flag )
    _INP-KIND @ _INP-K-ROW = IF _INP-ROW TROW-PARA 1 AND 0<> EXIT THEN
    0 ;

\ _INP-POS ( off -- pos )
\   A byte offset as the kind counts positions: scalars for laid-out
\   text, characters for units, bytes for ASCII.
: _INP-POS  ( off -- pos )
    _INP-KIND @ _INP-K-ROW = IF _INP-ROW TROW-BYTE>OFFSET EXIT THEN
    _INP-KIND @ _INP-K-UNITS = IF _INP-CHARS-IN THEN ;

\ _INP-CARET-V ( off -- v )   Where a caret there shows (APT-1-TEXT 9.2).
: _INP-CARET-V  ( off -- v )
    _INP-POS
    _INP-KIND @ _INP-K-ROW = IF _INP-ROW TROW-CARET-COLUMN THEN ;

\ _INP-CARET-CHAR ( off -- pos | -1 )
\   The start of the character a caret there marks, or -1 when it sits
\   just past the content.
: _INP-CARET-CHAR  ( off -- pos | -1 )
    _INP-KIND @ _INP-K-ROW = IF
        _INP-ROW TROW-BYTE>OFFSET _INP-ROW TROW-CARET
        DUP IF TROW.START ELSE DROP -1 THEN EXIT
    THEN
    DUP _INP-U < 0= IF DROP -1 EXIT THEN
    _INP-POS ;

\ _INP-CARET-W ( off -- cells )   The cells the caret's character takes.
: _INP-CARET-W  ( off -- cells )
    _INP-KIND @ _INP-K-ROW = IF
        _INP-ROW TROW-BYTE>OFFSET _INP-ROW TROW-CARET
        ?DUP IF TROW.WIDTH EXIT THEN 1 EXIT
    THEN
    DROP 1 ;

\ _INP-V>OFF ( v -- off )   The position a visual column names (9.1).
: _INP-V>OFF  ( v -- off )
    _INP-KIND @ _INP-K-ROW = IF
        _INP-ROW TROW-POSITION-AT _INP-ROW TROW-OFFSET>BYTE EXIT
    THEN
    0 MAX _INP-TW MIN
    _INP-KIND @ _INP-K-UNITS = IF _INP-CHAR-END THEN ;

\ _INP-ORIGIN ( -- x )   The field column of visual column 0.
: _INP-ORIGIN  ( -- x )
    _INP-RTL? IF _INP-FW _INP-TW - _INP-SX + ELSE _INP-SX NEGATE THEN ;

\ _INP-EDGE ( v -- cells )   Cells from the text's start edge.
: _INP-EDGE  ( v -- cells )
    _INP-RTL? IF _INP-TW 1- SWAP - THEN ;

\ The character boundaries before and after the caret.
: _INP-PREV-CHAR  ( -- off )
    _INP-CUR DUP 0= IF EXIT THEN
    _INP-KIND @ _INP-K-ASCII = IF 1- EXIT THEN
    _INP-A _INP-U ROT GR-PREV-BOUNDARY ;

: _INP-NEXT-CHAR  ( -- off )
    _INP-CUR DUP _INP-U < 0= IF EXIT THEN
    _INP-KIND @ _INP-K-ASCII = IF 1+ EXIT THEN
    _INP-A _INP-U ROT GR-NEXT-BOUNDARY ;

\ _INP-FIX ( forward? -- )
\   An edit can join the text on both sides of the caret into one
\   character, as a base typed before a lone combining mark does.  Move the
\   caret to that character's end when FORWARD? and to its start otherwise.
\   Only a non-ASCII byte after the caret can continue a character, so
\   plain text pays nothing.
: _INP-FIX  ( forward? -- )
    _INP-CUR DUP _INP-U < 0= IF 2DROP EXIT THEN
    DUP _INP-A + C@ 0x80 < IF 2DROP EXIT THEN
    _INP-A _INP-U 2 PICK 1+ GR-PREV-BOUNDARY       ( fwd cur b )
    2DUP = IF 2DROP DROP EXIT THEN
    NIP SWAP IF _INP-A _INP-U ROT GR-NEXT-BOUNDARY THEN
    _INP-W @ _INP-O-CURSOR + ! ;

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

\ _INP-DEL-BYTES ( start end widget -- )
\   Remove the bytes [START, END) and leave the caret at START.
: _INP-DEL-BYTES  ( start end widget -- )
    >R OVER -                               ( start len  R: widget )
    DUP 0> 0= IF 2DROP R> DROP EXIT THEN
    R@ _INP-O-BUF-A + @ 2 PICK +            ( start len dst )
    DUP 2 PICK + SWAP                       ( start len src dst )
    R@ _INP-O-BUF-LEN + @ 4 PICK - 3 PICK - ( start len src dst tail )
    DUP 0> IF CMOVE ELSE DROP 2DROP THEN    ( start len )
    R@ _INP-O-BUF-LEN + @ SWAP - R@ _INP-O-BUF-LEN + !
    R> _INP-O-CURSOR + ! ;

\ _INP-DEL-SEL ( widget -- deleted? )
\   Remove the selected characters and leave the caret where they began.
: _INP-DEL-SEL  ( widget -- flag )
    DUP _INP-SEL? 0= IF DROP 0 EXIT THEN
    DUP _INP-W !
    DUP _INP-SEL-RANGE 2 PICK _INP-DEL-BYTES
    DUP _INP-UNSELECT
    0 _INP-FIX
    WDG-DIRTY -1 ;

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
    R@ _INP-W ! -1 _INP-FIX
    R> WDG-DIRTY ;

\ _INP-DELETE ( widget -- )
\   Delete the selection, or the character at the cursor.
: _INP-DELETE  ( widget -- )
    DUP _INP-DEL-SEL IF DROP EXIT THEN
    _INP-PREP
    _INP-CUR _INP-NEXT-CHAR _INP-W @ _INP-DEL-BYTES
    0 _INP-FIX
    _INP-W @ WDG-DIRTY ;

\ _INP-BACKSPACE ( widget -- )
\   Delete the selection, or the character before the cursor.
: _INP-BACKSPACE  ( widget -- )
    DUP _INP-DEL-SEL IF DROP EXIT THEN
    _INP-PREP
    _INP-PREV-CHAR _INP-CUR _INP-W @ _INP-DEL-BYTES
    0 _INP-FIX
    _INP-W @ WDG-DIRTY ;

\ Caret moves.  Each only moves the caret; _INP-MOVE applies the selection
\ rule and marks the field dirty.  Left and Right move over whole
\ characters in logical order.

: _INP-LEFT  ( widget -- )
    _INP-PREP _INP-PREV-CHAR _INP-W @ _INP-O-CURSOR + ! ;

: _INP-RIGHT  ( widget -- )
    _INP-PREP _INP-NEXT-CHAR _INP-W @ _INP-O-CURSOR + ! ;

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

\ _INP-SCROLL-ADJ ( -- )
\   Scroll the prepared field so the caret's character, both cells of a
\   wide one, or the cell past the content is in view.
VARIABLE _INP-SA-LO     \ the caret's first cell from the start edge
VARIABLE _INP-SA-N      \ its cells

: _INP-SCROLL-ADJ  ( -- )
    _INP-CUR _INP-CARET-W _INP-SA-N !
    _INP-CUR _INP-CARET-V _INP-EDGE
    _INP-RTL? IF _INP-SA-N @ - 1+ THEN _INP-SA-LO !
    _INP-SA-LO @ _INP-SX < IF
        _INP-SA-LO @ _INP-W @ _INP-O-SCROLL + ! EXIT
    THEN
    _INP-SA-LO @ _INP-SA-N @ + _INP-SX _INP-FW + > IF
        _INP-SA-LO @ _INP-SA-N @ + _INP-FW - 0 MAX
        _INP-W @ _INP-O-SCROLL + !
    THEN ;

\ =====================================================================
\ 5. Internal draw
\ =====================================================================

VARIABLE _INP-DRW-X      \ field column of visual column 0
VARIABLE _INP-DRW-MS     \ marked positions [MS, ME), as _INP-POS counts
VARIABLE _INP-DRW-ME
VARIABLE _INP-DRW-EOC    \ the caret shows just past the content

\ _INP-CELL-CP ( cp -- cp' )
\   A mask shows in one cell, so a mask that is not one cell wide shows as
\   U+FFFD.
: _INP-CELL-CP  ( cp -- cp' )
    DUP 0x20 0x7F WITHIN IF EXIT THEN
    DUP CW-CHAR-WIDTH 1 <> IF DROP 0xFFFD THEN ;

\ One cell per character, left to right: the mask, or the character when
\ it is printable ASCII, else U+FFFD.
: _INP-DRAW-UNITS  ( -- )
    _INP-A _INP-U GR-F-TAB _INP-GC GR-CURSOR-INIT
    0 BEGIN _INP-GC GR-NEXT WHILE                 ( i )
        DUP _INP-DRW-X @ + DUP 0 _INP-FW WITHIN IF  ( i col )
            OVER _INP-DRW-MS @ _INP-DRW-ME @ WITHIN
            IF CELL-A-REVERSE ELSE 0 THEN DRW-ATTR!
            _INP-W @ _INP-O-MASK-CP + @ ?DUP 0= IF
                _INP-GC GR-C-CP0
                DUP 0x20 0x7F WITHIN 0= IF DROP 0xFFFD THEN
            THEN
            _INP-CELL-CP 0 ROT DRW-CHAR
        ELSE DROP THEN
        1+
    REPEAT DROP
    0 DRW-ATTR! ;

\ The prepared text from _INP-DRW-X, the marked characters reversed.
: _INP-DRAW-TEXT  ( -- )
    _INP-KIND @ _INP-K-ROW = IF
        _INP-ROW 0 _INP-DRW-X @ _INP-DRW-MS @ _INP-DRW-ME @
        CELL-A-REVERSE DRW-TROW-MARK EXIT
    THEN
    _INP-KIND @ _INP-K-UNITS = IF _INP-DRAW-UNITS EXIT THEN
    _INP-A _INP-U 0 _INP-DRW-X @ DRW-TEXT
    _INP-DRW-MS @ _INP-DRW-ME @ < IF
        CELL-A-REVERSE DRW-ATTR!
        _INP-A _INP-DRW-MS @ +
        _INP-DRW-ME @ _INP-U MIN _INP-DRW-MS @ - 0 MAX
        0 _INP-DRW-X @ _INP-DRW-MS @ + DRW-TEXT
        0 DRW-ATTR!
    THEN ;

\ _INP-DRAW ( widget -- )
\   The text or the placeholder.  A focused caret marks its character in
\   reverse video, or at the end a reversed blank just past the content.
\   A selection shows in reverse video instead, so the caret is not drawn
\   beside it where it would look like one more selected character.
: _INP-DRAW  ( widget -- )
    _INP-PREP
    _INP-SCROLL-ADJ
    32 0 0 _INP-FW DRW-HLINE
    _INP-U 0= IF
        _INP-W @ _INP-O-PH-U + @ 0> IF
            _INP-W @ _INP-O-PH-A + @ _INP-W @ _INP-O-PH-U + @
            0 0 DRW-TEXT-UNTRUSTED
        THEN
    THEN
    _INP-ORIGIN _INP-DRW-X !
    0 _INP-DRW-MS ! 0 _INP-DRW-ME ! 0 _INP-DRW-EOC !
    _INP-W @ _INP-SEL? IF
        _INP-W @ _INP-SEL-RANGE
        _INP-POS _INP-DRW-ME ! _INP-POS _INP-DRW-MS !
    ELSE
        _INP-W @ WDG-FOCUSED? IF
            _INP-CUR _INP-CARET-CHAR DUP 0< IF
                DROP -1 _INP-DRW-EOC !
            ELSE
                DUP _INP-DRW-MS ! 1+ _INP-DRW-ME !
            THEN
        THEN
    THEN
    _INP-U IF _INP-DRAW-TEXT THEN
    _INP-DRW-EOC @ IF
        _INP-CUR _INP-CARET-V _INP-DRW-X @ +
        DUP 0 _INP-FW WITHIN IF
            CELL-A-REVERSE DRW-ATTR!
            32 0 ROT DRW-CHAR
            0 DRW-ATTR!
        ELSE DROP THEN
    THEN ;

\ =====================================================================
\ 5a. Pointer
\ =====================================================================
\
\ A field column maps back through the layout the field draws: a point on
\ a character names its start, and past the content the end side names
\ the text's end and the start side its start (APT-1-TEXT 9.1).  A
\ primary press inside the field places the caret there, or with Shift
\ extends the selection to it.  While that press is held, a drag extends
\ the selection wherever the pointer goes.  A column past either edge
\ names the cell just beyond the view, so each drag step out there
\ scrolls the field.  Only the release of a press made here is consumed.

\ _INP-PT-INSIDE? ( event widget -- flag )
: _INP-PT-INSIDE?  ( event widget -- flag )
    >R 16 + @ DUP 16 RSHIFT R@ WDG-REGION RGN-ROW -
    R@ WDG-REGION RGN-H U<
    SWAP 0xFFFF AND R@ WDG-REGION RGN-COL -
    R> WDG-REGION RGN-W U< AND ;

\ _INP-PT-CURSOR ( col' widget -- byte-off )
\   The position a field-relative column names, at most one cell past
\   either visible edge.
: _INP-PT-CURSOR  ( col' widget -- off )
    _INP-PREP
    -1 MAX _INP-FW MIN
    _INP-ORIGIN - _INP-V>OFF ;

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
\   The characters before the caret.
: INP-CURSOR-POS  ( widget -- n )
    _INP-W ! _INP-CUR _INP-CHARS-IN ;

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
