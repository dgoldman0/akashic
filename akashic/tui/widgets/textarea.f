\ =====================================================================
\  akashic/tui/widgets/textarea.f — Multi-Line Text Area
\ =====================================================================
\
\  A multi-line editable text area with UTF-8 support, vertical
\  scrolling, and cursor navigation.  Uses a contiguous byte buffer
\  with newlines (0x0A) as line separators.
\
\  Text follows the shared text rules (APT-1-TEXT): each line is one
\  paragraph, the caret moves over whole characters, and columns count
\  cells (section 3a).  An optional style source marks what each part of
\  a line means; CELL draws each meaning through a palette, and Ctrl and
\  a click on a link follows it (section 3b).
\
\  The edit buffer is caller-provided — the widget does not allocate
\  storage for the text.
\
\  Descriptor (168 bytes):
\    +0..+32  widget header   type=WDG-T-TEXTAREA
\    +40      buf-a           Address of edit buffer
\    +48      buf-cap         Buffer capacity (bytes)
\    +56      buf-len         Current content length (bytes)
\    +64      cursor          Cursor byte offset
\    +72      scroll-y        First visible line (0-based)
\    +80      on-change-xt    Callback ( widget -- ) or 0
\    +88      sel-anchor      Selection anchor byte offset (-1 = none)
\    +96..+136 optional gap-buffer, undo, style source, gutter, and scroll
\    +144     instance        Nonzero process-lifetime instance identity
\    +152     palette         CELL look of each meaning, or 0 for the default
\    +160     follow-xt       Follows a link ( line-a line-u pos widget -- )
\
\  Prefix: TXTA- (public), _TXTA- (internal)
\  Provider: akashic-tui-textarea
\  Dependencies: widget.f, draw.f, semantic-collections.f, style-palette.f,
\                ../text/utf8.f, ../text/grapheme.f, ../text/text-row.f,
\                ../text/text-style.f, keys.f

PROVIDED akashic-tui-textarea

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../semantic-collections.f
REQUIRE ../style-palette.f
REQUIRE ../../text/utf8.f
REQUIRE ../../text/text-style.f
REQUIRE ../../text/gap-buf.f
REQUIRE ../../text/undo.f
REQUIRE ../../text/cell-width.f
REQUIRE ../../text/grapheme.f
REQUIRE ../../text/text-row.f
REQUIRE ../keys.f

CREATE _TXTA-OWNED-START
VARIABLE _TXTA-OWNED-LIMIT
0 _TXTA-OWNED-LIMIT !

\ =====================================================================
\  1. Descriptor layout
\ =====================================================================

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
112 CONSTANT _TXTA-O-STYLE-XT     \ style source or 0 (section 3b)
120 CONSTANT _TXTA-O-GUTTER-XT    \ gutter draw hook or 0
128 CONSTANT _TXTA-O-GUTTER-W     \ gutter column width (0 = off)
136 CONSTANT _TXTA-O-SCROLL-X     \ horizontal scroll offset
144 CONSTANT _TXTA-O-INSTANCE     \ nonpointer lifetime identity
152 CONSTANT _TXTA-O-PALETTE      \ style palette or 0 for the default
160 CONSTANT _TXTA-O-FOLLOW-XT    \ link follower or 0

168 CONSTANT _TXTA-DESC-SIZE

\ =====================================================================
\  2. Module variables (KDOS single-threaded pattern)
\ =====================================================================

VARIABLE _TXTA-W     \ current widget pointer for all internal words
VARIABLE _TXTA-NEXT-INSTANCE
VARIABLE _TXTA-NEW-INSTANCE
0 _TXTA-NEXT-INSTANCE !
0 _TXTA-NEW-INSTANCE !

: _TXTA-CLAIM-INSTANCE  ( -- token )
    _TXTA-NEXT-INSTANCE @ DUP -1 =
        ABORT" textarea instance identity exhausted"
    1+
    DUP _TXTA-NEXT-INSTANCE ! ;

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
\  3a. Characters and cells
\ =====================================================================
\
\  Each line is one paragraph of AUTO direction laid out by text-row.f.
\  The caret moves over whole characters (grapheme clusters), and Backspace
\  and Delete remove whole characters.  A line's characters take their
\  cells in visual order.  An LTR line starts at the text viewport's left
\  edge; an RTL line is mirrored and starts at its right edge; the
\  horizontal scroll moves each line away from its own start edge, as
\  SEMANTIC-CONTENT-1 says for TEXT_AREA rows.  A caret at a character's
\  start marks that character's lead cell, and at the line's end it sits
\  just past the content on the end side (APT-1-TEXT Section 9.2).  A line
\  of printable ASCII needs no layout: each byte is one cell.
\
\  A visual column V counts cells from the line's left end.  In the text
\  viewport, TW cells wide after the gutter, V shows at V plus the line's
\  origin: minus the scroll for an LTR line, and TW - W plus the scroll for
\  an RTL line W cells wide.

CREATE _TXTA-ROW TROW-SIZE ALLOT  _TXTA-ROW TROW-INIT
VARIABLE _TXTA-LT-A    0 _TXTA-LT-A !    \ line copied out of the gap buffer
VARIABLE _TXTA-LT-CAP  0 _TXTA-LT-CAP !
VARIABLE _TXTA-L-OFF      \ the prepared line's first byte
VARIABLE _TXTA-L-LEN      \ its bytes, without the newline
VARIABLE _TXTA-L-TEXT     \ address of those bytes
VARIABLE _TXTA-L-ASCII    \ printable ASCII, not laid out

\ _TXTA-LINE-SPAN ( line -- off len )
: _TXTA-LINE-SPAN  ( line -- off len )
    _TXTA-GB? IF
        DUP _TXTA-GB GB-LINE-OFF SWAP _TXTA-GB GB-LINE-LEN EXIT
    THEN
    _TXTA-LINE-OFF DUP
    BEGIN
        DUP _TXTA-BUF-LEN < IF DUP _TXTA-BUF-A + C@ 10 <> ELSE 0 THEN
    WHILE 1+ REPEAT
    OVER - ;

\ _TXTA-L-COPY? ( -- ok? )   Copy the line out of the gap buffer; false
\   when memory for the copy runs out or the copy comes back short.
: _TXTA-L-COPY?  ( -- ok? )
    _TXTA-L-LEN @ _TXTA-LT-CAP @ > IF
        _TXTA-L-LEN @ 64 MAX DUP ALLOCATE IF 2DROP 0 EXIT THEN
        _TXTA-LT-A @ ?DUP IF FREE THEN
        _TXTA-LT-A ! _TXTA-LT-CAP !
    THEN
    _TXTA-L-OFF @ _TXTA-LT-A @ _TXTA-L-LEN @ _TXTA-GB
        GB-COPY _TXTA-L-LEN @ = DUP IF _TXTA-LT-A @ _TXTA-L-TEXT ! THEN ;

\ _TXTA-L-PREP ( line -- ok? )
\   Take the line's text, and lay it out unless it is printable ASCII.
\   False only when memory for the copy or the layout runs out.
: _TXTA-L-PREP  ( line -- ok? )
    _TXTA-LINE-SPAN _TXTA-L-LEN ! _TXTA-L-OFF !
    _TXTA-GB? IF
        _TXTA-L-COPY? 0= IF 0 EXIT THEN
    ELSE
        _TXTA-BUF-A _TXTA-L-OFF @ + _TXTA-L-TEXT !
    THEN
    -1 _TXTA-L-ASCII !
    _TXTA-L-TEXT @ _TXTA-L-LEN @ OVER + SWAP ?DO
        I C@ 0x20 0x7F WITHIN 0= IF 0 _TXTA-L-ASCII ! LEAVE THEN
    LOOP
    _TXTA-L-ASCII @ IF -1 EXIT THEN
    _TXTA-L-TEXT @ _TXTA-L-LEN @ TROW-F-TAB BIDI-AUTO _TXTA-ROW TROW-LAYOUT ;

\ The prepared line's width in cells and its direction.
: _TXTA-L-W  ( -- cells )
    _TXTA-L-ASCII @ IF _TXTA-L-LEN @ ELSE _TXTA-ROW TROW-WIDTH THEN ;

: _TXTA-L-RTL?  ( -- flag )
    _TXTA-L-ASCII @ IF 0 ELSE _TXTA-ROW TROW-PARA 1 AND 0<> THEN ;

\ Document byte offsets and the line's scalar offsets.
: _TXTA-L-BYTE>POS  ( byte-off -- pos )
    _TXTA-L-OFF @ - 0 MAX _TXTA-L-LEN @ MIN
    _TXTA-L-ASCII @ 0= IF _TXTA-ROW TROW-BYTE>OFFSET THEN ;

: _TXTA-L-POS>BYTE  ( pos -- byte-off )
    _TXTA-L-ASCII @ IF
        0 MAX _TXTA-L-LEN @ MIN
    ELSE
        _TXTA-ROW TROW-OFFSET>BYTE
    THEN
    _TXTA-L-OFF @ + ;

\ _TXTA-L-CARET-V ( byte-off -- v )   Where the caret shows (Section 9.2).
: _TXTA-L-CARET-V  ( byte-off -- v )
    _TXTA-L-BYTE>POS
    _TXTA-L-ASCII @ IF EXIT THEN
    _TXTA-ROW TROW-CARET-COLUMN ;

\ _TXTA-L-CARET-POS ( byte-off -- pos | -1 )
\   The start of the character a caret there marks: its own, or the next
\   one with cells when its own has none.  -1 when the caret sits just
\   past the content.
: _TXTA-L-CARET-POS  ( byte-off -- pos | -1 )
    _TXTA-L-BYTE>POS
    _TXTA-L-ASCII @ IF DUP _TXTA-L-LEN @ < 0= IF DROP -1 THEN EXIT THEN
    _TXTA-ROW TROW-CARET DUP IF TROW.START ELSE DROP -1 THEN ;

\ _TXTA-L-V>BYTE ( v -- byte-off )   The position a point names (9.1).
: _TXTA-L-V>BYTE  ( v -- byte-off )
    _TXTA-L-ASCII @ IF
        0 MAX _TXTA-L-LEN @ MIN _TXTA-L-OFF @ + EXIT
    THEN
    _TXTA-ROW TROW-POSITION-AT _TXTA-L-POS>BYTE ;

\ The text viewport: its width after the gutter and its scroll.
: _TXTA-TW  ( -- cells )
    _TXTA-W @ WDG-REGION RGN-W
    _TXTA-W @ _TXTA-O-GUTTER-W + @ - 1 MAX ;

: _TXTA-SX  ( -- cells )
    _TXTA-W @ _TXTA-O-SCROLL-X + @ 0 MAX ;

\ _TXTA-L-ORIGIN ( -- x )   The viewport column of visual column 0.
: _TXTA-L-ORIGIN  ( -- x )
    _TXTA-L-RTL? IF
        _TXTA-TW _TXTA-L-W - _TXTA-SX +
    ELSE
        _TXTA-SX NEGATE
    THEN ;

\ _TXTA-L-EDGE ( v -- cells )   Cells from the line's start edge.
: _TXTA-L-EDGE  ( v -- cells )
    _TXTA-L-RTL? IF _TXTA-L-W 1- SWAP - THEN ;

\ One scalar back or forward, when a line cannot be prepared.
: _TXTA-CP-BEFORE  ( off -- off' )
    1-
    BEGIN
        DUP 0 > IF DUP _TXTA-CONTENT-BYTE@ _UTF8-CONT? ELSE 0 THEN
    WHILE 1- REPEAT ;

: _TXTA-CP-AFTER  ( off -- off' )
    DUP _TXTA-CONTENT-BYTE@ _UTF8-SEQLEN DUP 0= IF DROP 1 THEN
    + _TXTA-CONTENT-LEN MIN ;

\ _TXTA-PREV-CHAR ( -- off )
\   The character boundary before the caret; at a line start, the
\   previous line's end.
: _TXTA-PREV-CHAR  ( -- off )
    _TXTA-CURSOR DUP 0= IF EXIT THEN
    DUP _TXTA-SOL = IF 1- EXIT THEN
    _TXTA-CURSOR-LINE _TXTA-L-PREP 0= IF _TXTA-CP-BEFORE EXIT THEN
    _TXTA-L-ASCII @ IF 1- EXIT THEN
    _TXTA-L-OFF @ - _TXTA-L-TEXT @ _TXTA-L-LEN @ ROT GR-PREV-BOUNDARY
    _TXTA-L-OFF @ + ;

\ _TXTA-NEXT-CHAR ( -- off )
\   The character boundary after the caret; at a line end, the next line's
\   start.
: _TXTA-NEXT-CHAR  ( -- off )
    _TXTA-CURSOR DUP _TXTA-CONTENT-LEN >= IF EXIT THEN
    DUP _TXTA-CONTENT-BYTE@ 10 = IF 1+ EXIT THEN
    _TXTA-CURSOR-LINE _TXTA-L-PREP 0= IF _TXTA-CP-AFTER EXIT THEN
    _TXTA-L-ASCII @ IF 1+ EXIT THEN
    _TXTA-L-OFF @ - _TXTA-L-TEXT @ _TXTA-L-LEN @ ROT GR-NEXT-BOUNDARY
    _TXTA-L-OFF @ + ;

\ _TXTA-OFF-LINE ( off -- line )
: _TXTA-OFF-LINE  ( off -- line )
    _TXTA-GB? IF _TXTA-GB GB-POS-LINE-COL DROP EXIT THEN
    0 SWAP 0 ?DO _TXTA-BUF-A I + C@ 10 = IF 1+ THEN LOOP ;

\ _TXTA-SNAP ( off forward? -- off' )
\   A byte-wise move can stop inside a character: move to its end when
\   FORWARD? and to its start otherwise.
VARIABLE _TXTA-SNAP-FWD
: _TXTA-SNAP  ( off forward? -- off' )
    _TXTA-SNAP-FWD !
    DUP _TXTA-OFF-LINE _TXTA-L-PREP 0= IF EXIT THEN
    _TXTA-L-ASCII @ IF EXIT THEN
    _TXTA-L-OFF @ -
    DUP 0= OVER _TXTA-L-LEN @ >= OR IF _TXTA-L-OFF @ + EXIT THEN
    _TXTA-L-TEXT @ _TXTA-L-LEN @ 2 PICK 1+ GR-PREV-BOUNDARY   ( rel b )
    2DUP = IF DROP _TXTA-L-OFF @ + EXIT THEN
    NIP _TXTA-SNAP-FWD @ IF
        _TXTA-L-TEXT @ _TXTA-L-LEN @ ROT GR-NEXT-BOUNDARY
    THEN
    _TXTA-L-OFF @ + ;

\ _TXTA-FIX-CARET ( forward? -- )
\   An edit can join the text on both sides of the caret into one
\   character, as a base typed before a combining mark does.  Move the
\   caret to that character's end when FORWARD? and to its start
\   otherwise.  Only a non-ASCII byte after the caret can continue a
\   character, so plain text pays nothing.
: _TXTA-FIX-CARET  ( forward? -- )
    _TXTA-CURSOR DUP _TXTA-CONTENT-LEN < IF
        DUP _TXTA-CONTENT-BYTE@ 0x80 < IF 2DROP EXIT THEN
        SWAP _TXTA-SNAP _TXTA-SYNC-CURSOR!
    ELSE 2DROP THEN ;

\ _TXTA-CARET-X ( -- x )   The caret's text viewport column.
: _TXTA-CARET-X  ( -- x )
    _TXTA-CURSOR-LINE _TXTA-L-PREP 0= IF
        _TXTA-CURSOR-COL _TXTA-SX - EXIT
    THEN
    _TXTA-CURSOR _TXTA-L-CARET-V _TXTA-L-ORIGIN + ;

\ _TXTA-VERT ( target-line -- off )
\   The position on TARGET-LINE under the caret's viewport column.
VARIABLE _TXTA-VX
: _TXTA-VERT  ( target-line -- off )
    _TXTA-CARET-X _TXTA-VX !
    DUP _TXTA-L-PREP 0= IF
        _TXTA-LINE-OFF _TXTA-CURSOR-COL _TXTA-COL-OFF EXIT
    THEN
    DROP _TXTA-VX @ _TXTA-L-ORIGIN - _TXTA-L-V>BYTE ;

\ =====================================================================
\  3b. Styles and links
\ =====================================================================
\
\  An optional style source, ( line-a line-u map -- ), marks what each
\  byte of a line means (../../text/text-style.f), as the highlighters in
\  ../../text/syntax.f do.  CELL draws each meaning in the look the
\  widget's palette gives it (../style-palette.f): its colour, with its
\  attributes added to the drawing style's.  Plain text keeps the drawing
\  style.  A character takes the meaning of its first byte.  Lines are
\  styled only as they are drawn, published, or clicked, and a widget
\  without a style source pays nothing.
\
\  Ctrl and a primary press on a link, or a renderer's FOLLOW at a link,
\  calls the widget's follow word with the link's line, the byte offset
\  of the press in it, and the widget.  The follow word looks up the
\  target and decides what happens.  The line stays valid only until it
\  calls another textarea word, so it copies what it needs first.

VARIABLE _TXTA-SM-A    0 _TXTA-SM-A !     \ the prepared line's style map
VARIABLE _TXTA-SM-CAP  0 _TXTA-SM-CAP !
VARIABLE _TXTA-L-STYLED                   \ the map holds the prepared line
VARIABLE _TXTA-PAL                        \ palette of the line being drawn
VARIABLE _TXTA-BASE-FG                    \ the drawing style under it
VARIABLE _TXTA-BASE-A

\ _TXTA-L-STYLE ( -- )
\   Style the prepared line when the widget has a style source.  A line
\   without memory for its map stays plain.
: _TXTA-L-STYLE  ( -- )
    0 _TXTA-L-STYLED !
    _TXTA-W @ _TXTA-O-STYLE-XT + @ 0= IF EXIT THEN
    _TXTA-L-LEN @ 0= IF EXIT THEN
    _TXTA-L-LEN @ _TXTA-SM-CAP @ > IF
        _TXTA-L-LEN @ 64 MAX DUP ALLOCATE IF 2DROP EXIT THEN
        _TXTA-SM-A @ ?DUP IF FREE THEN
        _TXTA-SM-A ! _TXTA-SM-CAP !
    THEN
    _TXTA-L-TEXT @ _TXTA-L-LEN @ _TXTA-SM-A @
    _TXTA-W @ _TXTA-O-STYLE-XT + @ EXECUTE
    -1 _TXTA-L-STYLED ! ;

\ _TXTA-STYLE-OF ( byte -- fg attrs )
\   The look of the styled line's byte at that offset.
: _TXTA-STYLE-OF  ( byte -- fg attrs )
    _TXTA-SM-A @ + C@ DUP TSTY-VALID? 0= IF
        DROP _TXTA-BASE-FG @ _TXTA-BASE-A @ EXIT
    THEN
    DUP _TXTA-PAL @ SPAL-FG@
    SWAP _TXTA-PAL @ SPAL-ATTRS@ _TXTA-BASE-A @ OR ;

: _TXTA-PALETTE  ( -- palette )
    _TXTA-W @ _TXTA-O-PALETTE + @ ?DUP 0= IF SPAL-DEFAULT THEN ;

\ _TXTA-LINK? ( byte-off -- flag )
\   Does a link cover the character that starts at that offset?
: _TXTA-LINK?  ( off -- flag )
    _TXTA-W @ _TXTA-O-STYLE-XT + @ 0= IF DROP 0 EXIT THEN
    DUP _TXTA-OFF-LINE _TXTA-L-PREP 0= IF DROP 0 EXIT THEN
    _TXTA-L-STYLE
    _TXTA-L-STYLED @ 0= IF DROP 0 EXIT THEN
    _TXTA-L-OFF @ -
    DUP 0< OVER _TXTA-L-LEN @ < 0= OR IF DROP 0 EXIT THEN
    _TXTA-SM-A @ + C@ TSTY-LINK = ;

\ _TXTA-FOLLOW ( byte-off -- followed? )
\   Follow the link at that offset, when there is one and a follow word.
: _TXTA-FOLLOW  ( off -- followed? )
    _TXTA-W @ _TXTA-O-FOLLOW-XT + @ 0= IF DROP 0 EXIT THEN
    DUP _TXTA-LINK? 0= IF DROP 0 EXIT THEN
    _TXTA-L-OFF @ -  _TXTA-L-TEXT @ _TXTA-L-LEN @ ROT
    _TXTA-W @ DUP _TXTA-O-FOLLOW-XT + @ EXECUTE -1 ;

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
    0 _TXTA-FIX-CARET
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
    _TXTA-GB? IF _TXTA-GB-INS-STR -1 _TXTA-FIX-CARET EXIT THEN
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
    _TXTA-W @ _TXTA-O-CURSOR + !
    -1 _TXTA-FIX-CARET ;

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
        -1 _TXTA-FIX-CARET
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
    -1 _TXTA-FIX-CARET
    _TXTA-FIRE-CHANGE
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-DELETE ( -- )
\   Delete the character at the caret, or the selection.
: _TXTA-DELETE  ( -- )
    _TXTA-DEL-SEL IF
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
    _TXTA-CURSOR _TXTA-CONTENT-LEN >= IF EXIT THEN
    _TXTA-CURSOR _TXTA-NEXT-CHAR OVER - _TXTA-DEL-RANGE
    _TXTA-GB? IF _TXTA-GB GB-CURSOR _TXTA-W @ _TXTA-O-CURSOR + ! THEN
    0 _TXTA-FIX-CARET
    _TXTA-FIRE-CHANGE
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-BACKSPACE ( -- )
\   Delete the character before the caret, or the selection.
: _TXTA-BACKSPACE  ( -- )
    _TXTA-DEL-SEL IF
        _TXTA-FIRE-CHANGE _TXTA-W @ WDG-DIRTY EXIT
    THEN
    _TXTA-CURSOR 0= IF EXIT THEN
    _TXTA-PREV-CHAR DUP _TXTA-CURSOR OVER - _TXTA-DEL-RANGE
    _TXTA-W @ _TXTA-O-CURSOR + !
    _TXTA-GB? IF _TXTA-CURSOR _TXTA-GB GB-MOVE! THEN
    0 _TXTA-FIX-CARET
    _TXTA-FIRE-CHANGE
    _TXTA-W @ WDG-DIRTY ;

\ =====================================================================
\  5. Cursor movement
\ =====================================================================

\ Left and Right move over whole characters in logical order.
: _TXTA-LEFT  ( -- )
    _TXTA-CURSOR 0= IF EXIT THEN
    _TXTA-PREV-CHAR
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-RIGHT  ( -- )
    _TXTA-CURSOR _TXTA-CONTENT-LEN >= IF EXIT THEN
    _TXTA-NEXT-CHAR
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

\ Up and Down keep the caret's viewport column.
: _TXTA-UP  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 0= IF DROP EXIT THEN           \ already on line 0
    1- _TXTA-VERT
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

: _TXTA-DOWN  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 1+ _TXTA-LINE-COUNT >= IF DROP EXIT THEN
    1+ _TXTA-VERT
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-PGUP ( -- )
\   Move cursor up by viewport height lines.
: _TXTA-PGUP  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 0= IF DROP EXIT THEN
    _TXTA-W @ WDG-REGION RGN-H -       ( target-line )
    0 MAX _TXTA-VERT
    _TXTA-SYNC-CURSOR!
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-PGDN ( -- )
\   Move cursor down by viewport height lines.
: _TXTA-PGDN  ( -- )
    _TXTA-CURSOR-LINE                   ( cline )
    DUP 1+ _TXTA-LINE-COUNT >= IF DROP EXIT THEN
    _TXTA-W @ WDG-REGION RGN-H +       ( target-line )
    _TXTA-LINE-COUNT 1- MIN _TXTA-VERT
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
    0 _TXTA-SNAP
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
    -1 _TXTA-SNAP
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
    \ The caret's cells from its line's start edge, whichever the edge.
    _TXTA-CURSOR-LINE _TXTA-L-PREP IF
        _TXTA-CURSOR _TXTA-L-CARET-V _TXTA-L-EDGE
    ELSE
        _TXTA-CURSOR-COL
    THEN _TXTA-SA-CCOL !
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

VARIABLE _TXTA-DRW-RW     \ region width (total, including gutter)
VARIABLE _TXTA-DRW-COL    \ current column during line draw
VARIABLE _TXTA-DRW-ROW    \ current row
VARIABLE _TXTA-DRW-SELS   \ selection start byte offset (or -1)
VARIABLE _TXTA-DRW-SELE   \ selection end byte offset
VARIABLE _TXTA-DRW-LINE#  \ which document line we're painting
VARIABLE _TXTA-DRW-GW     \ gutter width for this paint pass
VARIABLE _TXTA-DRW-VH     \ viewport height for this paint pass
VARIABLE _TXTA-DRW-FIRST  \ first viewport row to repaint
VARIABLE _TXTA-DRW-COUNT  \ number of viewport rows to repaint
VARIABLE _TXTA-DRW-CLINE  \ the caret's line
VARIABLE _TXTA-DRW-LINES  \ lines in the document
VARIABLE _TXTA-DRW-MS     \ marked scalar offsets [MS, ME) of the line
VARIABLE _TXTA-DRW-ME
VARIABLE _TXTA-DRW-EOC    \ the caret shows just past the line's content

CREATE _TXTA-FLAT-BUF 1024 ALLOT   \ temp for GB selection extraction

\ _TXTA-DRW-GUTTER ( row -- )
\   Draw the gutter for a given row using the app's gutter callback.
: _TXTA-DRW-GUTTER  ( row -- )
    _TXTA-DRW-GW @ 0= IF DROP EXIT THEN
    _TXTA-W @ _TXTA-O-GUTTER-XT + @ ?DUP IF
        >R  _TXTA-DRW-LINE# @  SWAP  _TXTA-DRW-GW @  _TXTA-W @
        R> EXECUTE
    ELSE DROP THEN ;

\ _TXTA-ASCII-LOOK ( byte -- fg attrs )
\   The look of a styled ASCII line's byte, reversed when it is marked: an
\   ASCII line's bytes are its scalars.
: _TXTA-ASCII-LOOK  ( byte -- fg attrs )
    DUP _TXTA-STYLE-OF ROT
    DUP _TXTA-DRW-MS @ < 0= SWAP _TXTA-DRW-ME @ < AND IF CELL-A-REVERSE OR THEN ;

\ _TXTA-DRAW-STYLED ( -- )
\   The styled line's characters from _TXTA-DRW-COL, each in its look,
\   the marked ones reversed.
: _TXTA-DRAW-STYLED  ( -- )
    _TXTA-PALETTE _TXTA-PAL !
    DRW-FG@ _TXTA-BASE-FG !  DRW-ATTR@ _TXTA-BASE-A !
    _TXTA-L-ASCII @ IF
        _TXTA-L-TEXT @ _TXTA-L-LEN @ _TXTA-DRW-ROW @ _TXTA-DRW-COL @
        ['] _TXTA-ASCII-LOOK DRW-TEXT-STYLED EXIT
    THEN
    _TXTA-ROW _TXTA-DRW-ROW @ _TXTA-DRW-COL @
    _TXTA-DRW-MS @ _TXTA-DRW-ME @ CELL-A-REVERSE
    ['] _TXTA-STYLE-OF DRW-TROW-STYLED ;

\ _TXTA-DRAW-TEXT ( -- )
\   The prepared line's characters from _TXTA-DRW-COL, the marked ones
\   reversed.
: _TXTA-DRAW-TEXT  ( -- )
    _TXTA-L-STYLED @ IF _TXTA-DRAW-STYLED EXIT THEN
    _TXTA-L-ASCII @ IF
        _TXTA-L-TEXT @ _TXTA-L-LEN @
        _TXTA-DRW-ROW @ _TXTA-DRW-COL @ DRW-TEXT
        _TXTA-DRW-MS @ _TXTA-DRW-ME @ < IF
            CELL-A-REVERSE DRW-ATTR!
            _TXTA-L-TEXT @ _TXTA-DRW-MS @ +
            _TXTA-DRW-ME @ _TXTA-L-LEN @ MIN _TXTA-DRW-MS @ - 0 MAX
            _TXTA-DRW-ROW @ _TXTA-DRW-COL @ _TXTA-DRW-MS @ + DRW-TEXT
            0 DRW-ATTR!
        THEN
        EXIT
    THEN
    _TXTA-ROW _TXTA-DRW-ROW @ _TXTA-DRW-COL @
    _TXTA-DRW-MS @ _TXTA-DRW-ME @ CELL-A-REVERSE DRW-TROW-MARK ;

\ _TXTA-DRAW-LINE ( row -- )
\   Draw one text line at the given viewport row.
: _TXTA-DRAW-LINE  ( row -- )
    _TXTA-DRW-ROW !
    \ Clear row (whole width including gutter)
    32 _TXTA-DRW-ROW @ 0 _TXTA-DRW-RW @ DRW-HLINE
    _TXTA-DRW-LINE# @ _TXTA-DRW-LINES @ < 0= IF EXIT THEN
    _TXTA-DRW-LINE# @ _TXTA-L-PREP 0= IF EXIT THEN
    _TXTA-L-STYLE
    _TXTA-DRW-GW @ _TXTA-L-ORIGIN + _TXTA-DRW-COL !
    \ The marked characters: the selection, or else a focused caret's
    \ character.  A caret past the content is a reversed blank cell.
    0 _TXTA-DRW-MS ! 0 _TXTA-DRW-ME ! 0 _TXTA-DRW-EOC !
    _TXTA-DRW-SELS @ -1 <> IF
        _TXTA-DRW-SELS @ _TXTA-L-OFF @ MAX
        _TXTA-DRW-SELE @ _TXTA-L-OFF @ _TXTA-L-LEN @ + MIN
        2DUP < IF
            _TXTA-L-BYTE>POS _TXTA-DRW-ME ! _TXTA-L-BYTE>POS _TXTA-DRW-MS !
        ELSE 2DROP THEN
    ELSE
        _TXTA-DRW-LINE# @ _TXTA-DRW-CLINE @ =
        _TXTA-W @ WDG-FOCUSED? AND IF
            _TXTA-CURSOR _TXTA-L-CARET-POS DUP 0< IF
                DROP -1 _TXTA-DRW-EOC !
            ELSE
                DUP _TXTA-DRW-MS ! 1+ _TXTA-DRW-ME !
            THEN
        THEN
    THEN
    \ A line that starts left of the text viewport, scrolled or wider
    \ than it, is clipped to the viewport, out of the gutter.
    _TXTA-DRW-COL @ _TXTA-DRW-GW @ < IF
        ['] _TXTA-DRAW-TEXT _TXTA-DRW-ROW @ _TXTA-DRW-GW @
        1 _TXTA-DRW-RW @ _TXTA-DRW-GW @ - DRW-WITH-CLIP
    ELSE
        _TXTA-DRAW-TEXT
    THEN
    _TXTA-DRW-EOC @ IF
        _TXTA-CURSOR _TXTA-L-CARET-V _TXTA-DRW-COL @ +
        DUP _TXTA-DRW-GW @ _TXTA-DRW-RW @ WITHIN IF
            CELL-A-REVERSE DRW-ATTR!
            32 _TXTA-DRW-ROW @ ROT DRW-CHAR
            0 DRW-ATTR!
        ELSE DROP THEN
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
    DUP WDG-REGION RGN-W _TXTA-DRW-RW !
    WDG-REGION RGN-H _TXTA-DRW-VH !
    _TXTA-DRW-FIRST @ DUP 0< IF DROP 0 THEN
    _TXTA-DRW-VH @ MIN _TXTA-DRW-FIRST !
    _TXTA-DRW-COUNT @ DUP 0< IF DROP 0 THEN
    _TXTA-DRW-VH @ _TXTA-DRW-FIRST @ - MIN _TXTA-DRW-COUNT !
    _TXTA-CURSOR-LINE _TXTA-DRW-CLINE !
    _TXTA-LINE-COUNT _TXTA-DRW-LINES !
    \ Draw visible rows
    _TXTA-SCROLL _TXTA-DRW-FIRST @ + _TXTA-DRW-LINE# !
    _TXTA-DRW-FIRST @ _TXTA-DRW-COUNT @ +
    _TXTA-DRW-FIRST @ ?DO
        I _TXTA-DRAW-LINE
        \ Draw the gutter last: the default renderer clears the full row.
        DRW-STYLE-SAVE
        I _TXTA-DRW-GUTTER
        DRW-STYLE-RESTORE
        1 _TXTA-DRW-LINE# +!
    LOOP ;

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

\ =====================================================================
\  8b. Pointer
\ =====================================================================
\
\ The default renderer draws one logical line per row after the gutter, laid
\ out as section 3a says.  A pointer cell maps back through exactly that
\ layout.  A renderer-named
\ text position arrives as the item key this widget published (line + 1)
\ and a scalar offset, and needs no cell mapping at all.  Both clamp to the
\ current text, so a position from a slightly older frame stays valid.

3 CONSTANT _TXTA-WHEEL-LINES

\ KDOS MIN and MAX compare unsigned; pointer arithmetic needs signed clamps.
: _TXTA-AT-LEAST  ( n lo -- n' )
    2DUP < IF NIP ELSE DROP THEN ;

: _TXTA-CLAMP  ( n lo hi -- n' )
    >R _TXTA-AT-LEAST
    DUP R@ > IF DROP R> ELSE R> DROP THEN ;

VARIABLE _TXTA-PT-COL

\ _TXTA-POSITION ( line scalar-col -- byte-off )
\   A scalar inside a character names that character's start.
: _TXTA-POSITION  ( line col -- off )
    0 _TXTA-AT-LEAST _TXTA-PT-COL !
    0 _TXTA-LINE-COUNT 1- _TXTA-CLAMP
    _TXTA-LINE-OFF _TXTA-PT-COL @ _TXTA-COL-OFF
    0 _TXTA-SNAP ;

\ _TXTA-CELL>POSITION ( row col -- byte-off )
\   A cell above or below the viewport (a drag that left it) clamps to its
\   first or last row; a cell in the gutter means column zero.
\   A cell on a line's characters names the character's start; past the
\   content, the end side names the line's end (APT-1-TEXT Section 9.1).
: _TXTA-CELL>POSITION  ( row col -- off )
    _TXTA-W @ WDG-REGION RGN-COL -
    _TXTA-W @ _TXTA-O-GUTTER-W + @ -
    0 _TXTA-AT-LEAST _TXTA-PT-COL !        ( row )
    _TXTA-W @ WDG-REGION RGN-ROW -
    0 _TXTA-W @ WDG-REGION RGN-H 1- _TXTA-CLAMP
    _TXTA-SCROLL +
    0 _TXTA-LINE-COUNT 1- _TXTA-CLAMP      ( line )
    DUP _TXTA-L-PREP 0= IF
        _TXTA-PT-COL @ _TXTA-SX + _TXTA-POSITION EXIT
    THEN
    DROP _TXTA-PT-COL @ _TXTA-L-ORIGIN - _TXTA-L-V>BYTE ;

\ _TXTA-PLACE ( byte-off -- )   Move the caret there and drop the selection.
: _TXTA-PLACE  ( off -- )
    _TXTA-SEL-CLEAR _TXTA-SYNC-CURSOR! _TXTA-W @ WDG-DIRTY ;

\ _TXTA-EXTEND ( byte-off -- )
\   Move the caret there, keeping the selection anchor or starting one at the
\   prior caret.  An empty range is no selection.
: _TXTA-EXTEND  ( off -- )
    _TXTA-SEL-START! _TXTA-SYNC-CURSOR!
    _TXTA-SEL-ANCHOR _TXTA-CURSOR = IF _TXTA-SEL-CLEAR THEN
    _TXTA-W @ WDG-DIRTY ;

\ _TXTA-WHEEL ( lines -- )
\   Scroll the viewport by signed lines.  A caret the viewport leaves moves to
\   its nearest visible line, keeping its viewport column, so the next draw
\   does not scroll back to it.
: _TXTA-WHEEL  ( lines -- )
    _TXTA-SCROLL +
    0 _TXTA-LINE-COUNT _TXTA-W @ WDG-REGION RGN-H - 0 _TXTA-AT-LEAST
    _TXTA-CLAMP
    DUP _TXTA-SCROLL = IF DROP EXIT THEN
    _TXTA-W @ _TXTA-O-SCROLL-Y + !
    _TXTA-CURSOR-LINE
    _TXTA-SCROLL
    _TXTA-SCROLL _TXTA-W @ WDG-REGION RGN-H + 1-
    _TXTA-CLAMP                            ( visible-line )
    DUP _TXTA-CURSOR-LINE <> IF
        _TXTA-VERT _TXTA-PLACE
    ELSE
        DROP _TXTA-W @ WDG-DIRTY
    THEN ;

VARIABLE _TXTA-PT-CODE

\ A primary press places the caret, or with Shift extends the selection.
\ With Ctrl on a link it follows the link instead, as the rich renderer's
\ FOLLOW does; a press with Ctrl anywhere else places the caret.
: _TXTA-POINTER  ( event -- consumed? )
    DUP 8 + @ DUP KEY-MOUSE-BUTTON        ( event code button )
    CASE
        KEY-MOUSE-LEFT OF
            _TXTA-PT-CODE !
            16 + @ DUP 16 RSHIFT SWAP 0xFFFF AND
            _TXTA-CELL>POSITION            ( off )
            _TXTA-PT-CODE @ KEY-MOUSE-CTRL? IF
                DUP _TXTA-FOLLOW IF DROP -1 EXIT THEN
            THEN
            _TXTA-PT-CODE @ KEY-MOUSE-SHIFT?
            IF _TXTA-EXTEND ELSE _TXTA-PLACE THEN -1
        ENDOF
        KEY-MOUSE-DRAG OF
            DROP 16 + @ DUP 16 RSHIFT SWAP 0xFFFF AND
            _TXTA-CELL>POSITION _TXTA-EXTEND -1
        ENDOF
        KEY-MOUSE-RELEASE OF
            2DROP
            _TXTA-HAS-SEL? IF
                _TXTA-SEL-ANCHOR _TXTA-CURSOR = IF _TXTA-SEL-CLEAR THEN
            THEN
            -1
        ENDOF
        KEY-MOUSE-SCROLL-UP OF
            2DROP _TXTA-WHEEL-LINES NEGATE _TXTA-WHEEL -1
        ENDOF
        KEY-MOUSE-SCROLL-DN OF
            2DROP _TXTA-WHEEL-LINES _TXTA-WHEEL -1
        ENDOF
        KEY-MOUSE-TEXT-PLACE OF
            2DROP KEY-MOUSE-TEXT-KEY @ 1- KEY-MOUSE-TEXT-OFFSET @
            _TXTA-POSITION _TXTA-PLACE -1
        ENDOF
        KEY-MOUSE-TEXT-EXTEND OF
            2DROP KEY-MOUSE-TEXT-KEY @ 1- KEY-MOUSE-TEXT-OFFSET @
            _TXTA-POSITION _TXTA-EXTEND -1
        ENDOF
        \ A position that no longer lies on a link is dropped.
        KEY-MOUSE-TEXT-FOLLOW OF
            2DROP KEY-MOUSE-TEXT-KEY @ 1- KEY-MOUSE-TEXT-OFFSET @
            _TXTA-POSITION _TXTA-FOLLOW DROP -1
        ENDOF
        >R 2DROP 0 R>
    ENDCASE ;

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
    DUP @ KEY-T-MOUSE = IF _TXTA-POINTER EXIT THEN
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
    _TXTA-CLAIM-INSTANCE _TXTA-NEW-INSTANCE !
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
    0              OVER _TXTA-O-STYLE-XT   + !
    0              OVER _TXTA-O-GUTTER-XT  + !
    0              OVER _TXTA-O-GUTTER-W   + !
    0              OVER _TXTA-O-SCROLL-X   + !
    _TXTA-NEW-INSTANCE @ OVER _TXTA-O-INSTANCE + !
    0              OVER _TXTA-O-PALETTE   + !
    0              OVER _TXTA-O-FOLLOW-XT + !
    0 _TXTA-NEW-INSTANCE ! ;

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
\   The characters before the caret on its line.
: TXTA-CURSOR-COL  ( widget -- col )
    _TXTA-W !
    _TXTA-CURSOR-LINE _TXTA-L-PREP 0= IF _TXTA-CURSOR-COL EXIT THEN
    _TXTA-CURSOR _TXTA-L-OFF @ -
    _TXTA-L-ASCII @ IF EXIT THEN
    _TXTA-L-TEXT @ SWAP GR-COUNT ;

\ TXTA-CURSOR-CELL ( widget -- cells )
\   The cells from the caret line's start edge to the caret.
: TXTA-CURSOR-CELL  ( widget -- cells )
    _TXTA-W !
    _TXTA-CURSOR-LINE _TXTA-L-PREP 0= IF _TXTA-CURSOR-COL EXIT THEN
    _TXTA-CURSOR _TXTA-L-CARET-V _TXTA-L-EDGE ;

\ TXTA-CURSOR-X ( widget -- x )
\   The caret's column in the text viewport after the gutter, scrolled; it
\   marks the lead cell of the character the caret belongs to, or the cell
\   just past the line's content on its end side.
: TXTA-CURSOR-X  ( widget -- x )
    _TXTA-W ! _TXTA-CARET-X ;

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

\ TXTA-STYLE! ( xt widget -- )
\   Set the style source, or 0 for plain text.
\   xt: ( line-a line-u map -- ) fills map[0..line-u) with meanings.
: TXTA-STYLE!  ( xt widget -- )
    DUP >R _TXTA-O-STYLE-XT + ! R> WDG-DIRTY ;

\ TXTA-PALETTE! ( palette widget -- )
\   Set how each meaning looks in CELL, or 0 for SPAL-DEFAULT.
: TXTA-PALETTE!  ( palette widget -- )
    DUP >R _TXTA-O-PALETTE + ! R> WDG-DIRTY ;

\ TXTA-ON-FOLLOW! ( xt widget -- )
\   Set the word that follows a link, or 0.
\   xt: ( line-a line-u pos widget -- ), POS the byte offset in the line.
: TXTA-ON-FOLLOW!  ( xt widget -- )
    _TXTA-O-FOLLOW-XT + ! ;

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
    R@ WDG-CLEAN
    R> WDG-DRAW-PARTIAL-COMPLETE ;

\ TXTA-SCROLL-X@ ( widget -- n )
\   Get current horizontal scroll offset.
: TXTA-SCROLL-X@  ( widget -- n )
    _TXTA-O-SCROLL-X + @ ;

\ TXTA-SCROLL-X! ( n widget -- )
\   Set horizontal scroll offset.
: TXTA-SCROLL-X!  ( n widget -- )
    DUP >R _TXTA-O-SCROLL-X + !
    R> WDG-DIRTY ;

\ TXTA-INSTANCE@ ( widget -- token )
\   Stable, nonpointer identity for this allocation's lifetime.  It is not a
\   document/root key and carries no renderer or attachment authority.
: TXTA-INSTANCE@  ( widget -- token )
    _TXTA-O-INSTANCE + @ ;

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
VARIABLE _TXTA-SEM-MAX-CELLS
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
VARIABLE _TXTA-SEM-POS-LINE

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

\ TXTA-STORAGE-DISJOINT? ( address bytes -- flag )
\   Pure first-line authority check for the textarea module itself.  It is
\   deliberately outside the guarded surface: a caller must be able to
\   reject an alias of textarea scratch (or of the guard) before either the
\   guard or a semantic query writes any module state.
: TXTA-STORAGE-DISJOINT?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _TXTA-OWNED-LIMIT @ DUP _TXTA-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _TXTA-OWNED-START - >R
    _TXTA-OWNED-START R> MSPAN-OVERLAP? 0= ;

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
    \ The line copy and the style map are written while a capture runs.
    _TXTA-LT-A @ ?DUP IF
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @ ROT _TXTA-LT-CAP @
            MSPAN-OVERLAP? IF -1 EXIT THEN
    THEN
    _TXTA-SM-A @ ?DUP IF
        _TXTA-SEM-SPAN-A @ _TXTA-SEM-SPAN-U @ ROT _TXTA-SM-CAP @
            MSPAN-OVERLAP? IF -1 EXIT THEN
    THEN
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
    >R
    2DUP TXTA-STORAGE-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    R> _TXTA-W !
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
        10 = IF
            1 _TXTA-SEM-ACTUAL-ROWS +!
            _TXTA-SEM-ACTUAL-ROWS @ _TXTA-SEM-U32? 0= IF
                USCOL-S-INVALID EXIT
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

\ The widest line in cells: TEXT_AREA columns count cells, each character
\ taking its width (SEMANTIC-CONTENT-1, APT-1-TEXT Section 4).
: _TXTA-SEM-SCAN-WIDTH  ( -- status )
    1 _TXTA-SEM-MAX-CELLS !
    _TXTA-SEM-ACTUAL-ROWS @ 0 ?DO
        I _TXTA-LINE-SPAN _TXTA-L-LEN ! _TXTA-L-OFF !
        _TXTA-GB? IF
            _TXTA-L-COPY? 0= IF USCOL-S-CAPACITY UNLOOP EXIT THEN
        ELSE
            _TXTA-BUF-A _TXTA-L-OFF @ + _TXTA-L-TEXT !
        THEN
        _TXTA-L-TEXT @ _TXTA-L-LEN @ GR-SWIDTH
        _TXTA-SEM-MAX-CELLS @ MAX _TXTA-SEM-MAX-CELLS !
    LOOP
    _TXTA-SEM-MAX-CELLS @ _TXTA-SEM-U32? 0= IF USCOL-S-INVALID EXIT THEN
    USCOL-S-OK ;

\ Count the logical rows, then find the widest in cells.  GB mode walks the
\ two borrowed physical segments directly rather than doing one guarded
\ GB-BYTE@ call per byte.
: _TXTA-SEM-SCAN-SHAPE  ( -- status )
    _TXTA-CONTENT-LEN DUP 0< IF DROP USCOL-S-INVALID EXIT THEN
    DUP _TXTA-SEM-CONTENT-U !
    DUP _TXTA-SEM-U32? 0= IF DROP USCOL-S-INVALID EXIT THEN DROP
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
    _TXTA-SEM-SCAN-WIDTH ;

\ _TXTA-SEM-LINE-TEXT ( -- status )
\   Make _TXTA-L-TEXT the line at _TXTA-L-OFF, _TXTA-L-LEN long, in one
\   piece: the flat buffer itself, or a copy out of the gap buffer.
: _TXTA-SEM-LINE-TEXT  ( -- status )
    _TXTA-GB? IF
        _TXTA-L-COPY? 0= IF USCOL-S-CAPACITY EXIT THEN
    ELSE
        _TXTA-BUF-A _TXTA-L-OFF @ + _TXTA-L-TEXT !
    THEN
    USCOL-S-OK ;

\ Resolve an arbitrary byte position without moving the authoritative cursor:
\ its line, and its published scalar column (UTF8-UNIT-INDEX), so
\ positions agree with the published text whatever bytes the line holds.  A
\ position inside a scalar is refused.
: _TXTA-SEM-POSITION  ( byte-offset -- line scalar-column status )
    DUP 0< IF DROP 0 0 USCOL-S-INVALID EXIT THEN
    DUP _TXTA-SEM-CONTENT-U @ U> IF
        DROP 0 0 USCOL-S-INVALID EXIT
    THEN
    DUP _TXTA-SEM-POS !
    _TXTA-GB? IF
        _TXTA-GB GB-POS-LINE-COL DROP
    ELSE
        0 SWAP 0 ?DO I _TXTA-CONTENT-BYTE@ 10 = IF 1+ THEN LOOP
    THEN
    DUP _TXTA-SEM-POS-LINE !
    _TXTA-LINE-SPAN _TXTA-L-LEN ! _TXTA-L-OFF !
    _TXTA-SEM-LINE-TEXT DUP USCOL-S-OK <> IF 0 0 ROT EXIT THEN DROP
    _TXTA-L-TEXT @ _TXTA-L-LEN @ _TXTA-SEM-POS @ _TXTA-L-OFF @ -
        UTF8-UNIT-INDEX 0= IF DROP 0 0 USCOL-S-INVALID EXIT THEN
    _TXTA-SEM-POS-LINE @ SWAP USCOL-S-OK ;

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
    _TXTA-SEM-MAX-CELLS @ MAX 1 MAX _TXTA-SEM-COLS !
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

\ A carried row's style runs come from the same style source that draws it,
\ so CELL and the published text mean the same.  A row whose style map
\ cannot be allocated is plain in both.
: _TXTA-SEM-RUN  ( start length meaning -- ok? )
    _TXTA-SEM-BUILDER @ USCOL-TEXT-ITEM-RUN USCOL-S-OK = ;

\ The runs of the line in _TXTA-L-TEXT.
: _TXTA-SEM-EMIT-RUNS  ( -- )
    _TXTA-W @ _TXTA-O-STYLE-XT + @ 0= IF EXIT THEN
    _TXTA-L-STYLE
    _TXTA-L-STYLED @ IF
        \ A builder failure latches in the builder; the item's end reports it.
        _TXTA-L-TEXT @ _TXTA-L-LEN @ _TXTA-SM-A @ ['] _TXTA-SEM-RUN TSTY-RUNS
        DROP
    THEN ;

\ A carried row is published as CELL shows it (UTF8-SAFE-COPY): the
\ text of a file that is not UTF-8 text still makes a valid row.
: _TXTA-SEM-EMIT-ONE  ( -- status )
    _TXTA-SEM-EMIT-OFF @ _TXTA-L-OFF !
    _TXTA-SEM-EMIT-U @ _TXTA-L-LEN !
    _TXTA-SEM-LINE-TEXT DUP USCOL-S-OK <> IF EXIT THEN DROP
    _TXTA-SEM-EMIT-LINE @ 1+
    _TXTA-SEM-EMIT-LINE @ 0 1 _TXTA-SEM-COLS @
    USCOL-ROLE-CONTENT 0
    _TXTA-L-TEXT @ _TXTA-L-LEN @ -1 UTF8-SAFE-BYTES
    _TXTA-SEM-BUILDER @ USCOL-TEXT-ITEM-BEGIN
    DUP USCOL-S-OK <> IF NIP EXIT THEN DROP
    ?DUP IF >R _TXTA-L-TEXT @ _TXTA-L-LEN @ -1 R> UTF8-SAFE-COPY THEN
    _TXTA-SEM-EMIT-RUNS
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
    1 PICK USCOL-BUILDER-SIZE TXTA-STORAGE-DISJOINT? 0= IF
        2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT
    THEN
    3 PICK 3 PICK TXTA-STORAGE-DISJOINT? 0= IF
        2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT
    THEN
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
' TXTA-CURSOR-CELL CONSTANT _txta-curcell-xt
' TXTA-CURSOR-X    CONSTANT _txta-curx-xt
' TXTA-GET-SEL   CONSTANT _txta-getsel-xt
' TXTA-DEL-SEL   CONSTANT _txta-delsel-xt
' TXTA-INS-STR   CONSTANT _txta-insstr-xt
' TXTA-SELECT-ALL CONSTANT _txta-selall-xt
' TXTA-BIND-GB   CONSTANT _txta-bindgb-xt
' TXTA-UNBIND-GB CONSTANT _txta-unbindgb-xt
' TXTA-BIND-UNDO CONSTANT _txta-bindundo-xt
' TXTA-UNBIND-UNDO CONSTANT _txta-unbindundo-xt
' TXTA-STYLE!    CONSTANT _txta-style-xt
' TXTA-PALETTE!  CONSTANT _txta-palette-xt
' TXTA-ON-FOLLOW! CONSTANT _txta-onfollow-xt
' TXTA-GUTTER!    CONSTANT _txta-gutter-xt
' TXTA-ADJUST-SCROLL CONSTANT _txta-adjustscroll-xt
' TXTA-DRAW-ROWS  CONSTANT _txta-drawrows-xt
' TXTA-SCROLL-X@  CONSTANT _txta-scrollxrd-xt
' TXTA-SCROLL-X!  CONSTANT _txta-scrollxwr-xt
' TXTA-INSTANCE@  CONSTANT _txta-instance-at-xt
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
: TXTA-CURSOR-CELL _txta-curcell-xt _txta-guard WITH-GUARD ;
: TXTA-CURSOR-X    _txta-curx-xt    _txta-guard WITH-GUARD ;
: TXTA-GET-SEL   _txta-getsel-xt  _txta-guard WITH-GUARD ;
: TXTA-DEL-SEL   _txta-delsel-xt  _txta-guard WITH-GUARD ;
: TXTA-INS-STR   _txta-insstr-xt  _txta-guard WITH-GUARD ;
: TXTA-SELECT-ALL _txta-selall-xt _txta-guard WITH-GUARD ;
: TXTA-BIND-GB   _txta-bindgb-xt  _txta-guard WITH-GUARD ;
: TXTA-UNBIND-GB _txta-unbindgb-xt _txta-guard WITH-GUARD ;
: TXTA-BIND-UNDO _txta-bindundo-xt _txta-guard WITH-GUARD ;
: TXTA-UNBIND-UNDO _txta-unbindundo-xt _txta-guard WITH-GUARD ;
: TXTA-STYLE!    _txta-style-xt   _txta-guard WITH-GUARD ;
: TXTA-PALETTE!  _txta-palette-xt _txta-guard WITH-GUARD ;
: TXTA-ON-FOLLOW! _txta-onfollow-xt _txta-guard WITH-GUARD ;
: TXTA-GUTTER!    _txta-gutter-xt  _txta-guard WITH-GUARD ;
: TXTA-ADJUST-SCROLL _txta-adjustscroll-xt _txta-guard WITH-GUARD ;
: TXTA-DRAW-ROWS  _txta-drawrows-xt _txta-guard WITH-GUARD ;
: TXTA-SCROLL-X@  _txta-scrollxrd-xt _txta-guard WITH-GUARD ;
: TXTA-SCROLL-X!  _txta-scrollxwr-xt _txta-guard WITH-GUARD ;
: TXTA-INSTANCE@  _txta-instance-at-xt _txta-guard WITH-GUARD ;
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
