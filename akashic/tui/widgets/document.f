\ =====================================================================
\  akashic/tui/widgets/document.f — a document, read top to bottom
\ =====================================================================
\
\  Shows a document (media/document.f): its blocks one after another, each
\  inside its quotes and list items, on the rows SEMANTIC-CONTENT-1 gives
\  them, so CELL and a rich terminal show the same rows.  A block's indent
\  is its containers' widths; its text breaks into lines at the width left
\  by APT-1-TEXT Section 12, code into hard lines; a rule is one row; and a
\  figure's picture takes the rows its size needs at that width, at most
\  the view's height, then its caption's lines.  Blank rows lie between
\  blocks as the document says.
\
\  CELL draws each block as MegaPad's reference renderer does: a quote bar
\  on every row of a quote, a list item's bullet (another at each deeper
\  list) or its number on the first row of the block that starts it,
\  headings in the heading look with levels 1 and 2 underlined, code on a
\  dark background, a rule as a line, and a figure's caption muted.  It
\  draws over the owner's style (DRW-STYLE-RESTORE), each meaning in the
\  style palette's look with its block's attributes kept, as a list's
\  fields are drawn.  A figure's picture is a picture widget drawn into
\  its rows: a CELL copy for QOI, and the picture's facts otherwise; a
\  figure partly scrolled out shows the part in view.  The text comes from
\  outside the application, so it is laid out as DRW-TEXT-UNTRUSTED lays
\  text out.
\
\  The arrow keys, Page Up and Down, Home, End and the wheel scroll the
\  view by rows.  A press on a link follows it: a link to one of the
\  document's own headings (#name) scrolls there, and any other goes to
\  the owner's follow word.  The view keeps each block's row count at its
\  width, so a scroll lays out only the blocks it passes, and each draw
\  keeps the contents of the blocks it shows, giving back the others.
\
\  The document is the owner's, opened and closed by it.  The owner says
\  where a figure's picture comes from: a resolve word ( name-a name-u ctx
\  -- source | 0 ) gives a media source for a picture's name, which the
\  view gives back with a release word ( source ctx -- ).  A followed
\  link's target goes to the owner's follow word ( target-a target-u ctx
\  -- ); it lies in the document, so the owner copies it before closing
\  the document.  Memory comes from the owner's memory source.
\
\  Document View Descriptor:
\    +0..+32 widget header (type=WDG-T-DOCUMENT)
\    +40  doc          the document, or 0
\    +48  msrc         memory for counts, figures and names
\    +56  cols         the width the counts are for, or 0 for none
\    +64  height       the height a figure's rows were capped at
\    +72  counts-a     a block's rows at that width, a cell each, -1 unknown
\    +80  counts-cap
\    +88  top          the block the view's top row lies in
\    +96  top-row      its rows above the view
\   +104  end          the block after the last the last draw showed
\   +112  resolve-xt   ( name-a name-u ctx -- source | 0 )
\   +120  release-xt   ( source ctx -- )
\   +128  follow-xt    ( target-a target-u ctx -- )
\   +136  ctx          the owner's, passed to all three
\   +144  figs-a       figures known: _FIG-SIZE bytes each
\   +152  figs-cap
\   +160  figs-n
\   +168  revision     counts every change in what the view shows
\   +176  draws        counts draws, to find figures no longer shown
\
\  The view publishes the blocks its last draw showed as a renderer-neutral
\  DOCUMENT entry (semantic-collections.f) on the rows CELL drew them:
\  DOCV-DOCUMENT-CAPTURE.
\
\  Prefix: DOCV- (public), _DOCV- and _DV- (internal)
\  Provider: akashic-tui-document
\  Dependencies: widget.f, draw.f, picture.f, media/document.f, text-lines.f,
\                bidi.f, semantic-collections.f

PROVIDED akashic-tui-document

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../keys.f
REQUIRE ../region.f
REQUIRE ../style-palette.f
REQUIRE picture.f
REQUIRE ../../media/document.f
REQUIRE ../../media/picture.f
REQUIRE ../../text/text-lines.f
REQUIRE ../../text/bidi.f
REQUIRE ../../utils/memory-source.f
REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/string.f
REQUIRE ../semantic-collections.f

CREATE _DOCV-OWNED-START
VARIABLE _DOCV-OWNED-LIMIT
0 _DOCV-OWNED-LIMIT !

 40 CONSTANT _DOCV-O-DOC
 48 CONSTANT _DOCV-O-MSRC
 56 CONSTANT _DOCV-O-COLS
 64 CONSTANT _DOCV-O-HEIGHT
 72 CONSTANT _DOCV-O-COUNTS-A
 80 CONSTANT _DOCV-O-COUNTS-CAP
 88 CONSTANT _DOCV-O-TOP
 96 CONSTANT _DOCV-O-TOP-ROW
104 CONSTANT _DOCV-O-END
112 CONSTANT _DOCV-O-RESOLVE
120 CONSTANT _DOCV-O-RELEASE
128 CONSTANT _DOCV-O-FOLLOW
136 CONSTANT _DOCV-O-CTX
144 CONSTANT _DOCV-O-FIGS-A
152 CONSTANT _DOCV-O-FIGS-CAP
160 CONSTANT _DOCV-O-FIGS-N
168 CONSTANT _DOCV-O-REVISION
176 CONSTANT _DOCV-O-DRAWS
184 CONSTANT _DOCV-DESC-SIZE

\ A figure: its block, its picture's size (0 0 when it has none), and,
\ while it is shown, its source, its picture widget, the region that
\ widget draws in, a copy of the picture's name, and the draw that last
\ showed it.
 0 CONSTANT _FIG.BLOCK
 8 CONSTANT _FIG.PW
16 CONSTANT _FIG.PH
24 CONSTANT _FIG.SOURCE
32 CONSTANT _FIG.PICT
40 CONSTANT _FIG.RGN
48 CONSTANT _FIG.NAME-A
56 CONSTANT _FIG.NAME-U
64 CONSTANT _FIG.SEEN
72 CONSTANT _FIG-SIZE

3 CONSTANT _DOCV-WHEEL-ROWS

\ The looks CELL draws a document's own parts in: xterm-256 colours.
245 CONSTANT _DOCV-MUTED      \ marks, captions and a figure's name
244 CONSTANT _DOCV-RULE
235 CONSTANT _DOCV-CODE-BG

9474 CONSTANT _DOCV-BAR       \ a quote's bar
9472 CONSTANT _DOCV-LINE      \ a rule

VARIABLE _DV-W            \ the view being worked on

: _DV@  ( offset -- x )  _DV-W @ + @ ;
: _DV!  ( x offset -- )  _DV-W @ + ! ;
: _DV-DOC  ( -- doc )  _DOCV-O-DOC _DV@ ;
: _DV-BLOCKS  ( -- n )  _DV-DOC ?DUP IF DOC-COUNT ELSE 0 THEN ;
: _DV-RGN  ( -- rgn )  _DV-W @ WDG-REGION ;
: _DV-H  ( -- rows )  _DV-RGN RGN-H ;
: _DV-REVISE  ( -- )  _DOCV-O-REVISION _DV@ 1+ _DOCV-O-REVISION _DV! ;
: _DV-CHANGED  ( -- )  _DV-REVISE _DV-W @ WDG-DIRTY ;

\ =====================================================================
\  1. Memory and the owner
\ =====================================================================

: _DV-ALLOC  ( bytes -- a|0 )  _DOCV-O-MSRC _DV@ MSRC-ALLOC ;
: _DV-FREE   ( a bytes -- )
    OVER 0= IF 2DROP EXIT THEN _DOCV-O-MSRC _DV@ MSRC-FREE ;

\ The owner's words run with the view kept, whatever they do.
: _DV-OWNER  ( i*x xt -- j*x )
    _DV-W @ >R _DOCV-O-CTX _DV@ SWAP EXECUTE R> _DV-W ! ;

: _DV-RESOLVE  ( name-a name-u -- source|0 )
    _DOCV-O-RESOLVE _DV@ ?DUP 0= IF 2DROP 0 EXIT THEN _DV-OWNER ;

: _DV-RELEASE  ( source -- )
    ?DUP 0= IF EXIT THEN
    _DOCV-O-RELEASE _DV@ ?DUP 0= IF DROP EXIT THEN _DV-OWNER ;

\ =====================================================================
\  2. A block's shape
\ =====================================================================

\ The cells a block's containers take at the left of its rows.
: _DV-INDENT  ( block -- cells )
    _DV-DOC DOC-CONTAINERS 0 SWAP 0 ?DO
        OVER I CNT-SIZE * + CNT-WIDTH@ +
    LOOP NIP ;

\ T = max(W - I, 1): the cells left for a block's text.
: _DV-TEXT-WIDTH  ( block -- cells )
    _DV-INDENT _DOCV-O-COLS _DV@ SWAP - 1 MAX ;

CREATE _DV-TLN TLINES-SIZE ALLOT  _DV-TLN TLINES-INIT

\ How a block's text breaks: prose by Section 12, code in hard lines left
\ to right, both laid out as untrusted text.
: _DV-HOW  ( code? -- flags direction )
    IF TLINES-F-HARD TROW-F-UNTRUSTED OR BIDI-LTR
    ELSE TROW-F-UNTRUSTED BIDI-AUTO THEN ;

\ Read the first line of text at a width.
: _DV-LINES-START  ( a u code? width -- line? )
    >R _DV-HOW R> _DV-TLN TLINES-START ;

: _DV-COUNT-LINES  ( a u code? width -- lines ok? )
    >R _DV-HOW R> _DV-TLN TLINES-COUNT ;

\ Step over one scalar of valid UTF-8.
: _DV-SKIP-SCALAR  ( a u -- a' u' )
    1 /STRING
    BEGIN DUP IF OVER C@ 0xC0 AND 0x80 = ELSE 0 THEN WHILE 1 /STRING REPEAT ;

\ =====================================================================
\  3. Figures
\ =====================================================================

: _DV-FIG  ( i -- fig )  _FIG-SIZE * _DOCV-O-FIGS-A _DV@ + ;

\ The figure of block INDEX, or 0 when none is known.
: _DV-FIND-FIG  ( index -- fig|0 )
    _DOCV-O-FIGS-N _DV@ 0 ?DO
        I _DV-FIG DUP _FIG.BLOCK + @ 2 PICK = IF NIP UNLOOP EXIT THEN DROP
    LOOP DROP 0 ;

\ Room for one more figure; false when memory refuses it.
: _DV-FIG-ROOM?  ( -- ok? )
    _DOCV-O-FIGS-N _DV@ 1+ _FIG-SIZE * DUP _DOCV-O-FIGS-CAP _DV@ > 0= IF
        DROP -1 EXIT
    THEN
    _DOCV-O-FIGS-CAP _DV@ 2* MAX _FIG-SIZE 4 * MAX
    DUP _DV-ALLOC ?DUP 0= IF DROP 0 EXIT THEN          ( bytes new )
    _DOCV-O-FIGS-A _DV@ ?DUP IF
        OVER _DOCV-O-FIGS-N _DV@ _FIG-SIZE * MOVE
        _DOCV-O-FIGS-A _DV@ _DOCV-O-FIGS-CAP _DV@ _DV-FREE
    THEN
    _DOCV-O-FIGS-A _DV! _DOCV-O-FIGS-CAP _DV! -1 ;

VARIABLE _DVF-F

\ _DV-FIG-OF ( content index -- fig|0 )
\   The figure of block INDEX, whose content is CONTENT, known from now on
\   with its picture's size, read from the picture's file once; 0 when
\   memory refuses its record.
: _DV-FIG-OF  ( content index -- fig|0 )
    DUP _DV-FIND-FIG ?DUP IF NIP NIP EXIT THEN
    _DV-FIG-ROOM? 0= IF 2DROP 0 EXIT THEN
    _DOCV-O-FIGS-N _DV@ _DV-FIG DUP _DVF-F ! _FIG-SIZE 0 FILL
    _DVF-F @ _FIG.BLOCK + !
    _DOCV-O-FIGS-N _DV@ 1+ _DOCV-O-FIGS-N _DV!
    DCT-FIGURE DUP IF
        _DV-RESOLVE ?DUP IF
            DUP PIC-FILE IF DROP 2DROP 0 0 ELSE ROT DROP THEN
            _DVF-F @ _FIG.PH + ! _DVF-F @ _FIG.PW + !
            _DV-RELEASE
        THEN
    ELSE 2DROP THEN
    _DVF-F @ ;

\ The rows a figure's picture takes in a text area WIDTH cells wide: the
\ rows its size needs with a cell two pixels high, never wider than the
\ picture, and at most the view's height; one row when its size is unknown.
: _DV-PICTURE-ROWS  ( fig width -- rows )
    OVER 0= IF 2DROP 1 EXIT THEN
    OVER _FIG.PW + @ DUP 0= IF DROP 2DROP 1 EXIT THEN    ( fig width pw )
    TUCK MIN                                              ( fig pw cols )
    ROT _FIG.PH + @ * OVER 2* 1- + SWAP 2* /
    1 MAX _DOCV-O-HEIGHT _DV@ ?DUP IF MIN THEN ;

\ Give back a figure's picture widget, region, name and source.
: _DV-FIG-HIDE  ( fig -- )
    DUP _FIG.PICT + @ ?DUP IF PICT-FREE THEN
    DUP _FIG.RGN + @ ?DUP IF RGN-FREE THEN
    DUP _FIG.SOURCE + @ _DV-RELEASE
    DUP _FIG.NAME-A + @ OVER _FIG.NAME-U + @ _DV-FREE
    0 OVER _FIG.PICT + !  0 OVER _FIG.RGN + !  0 OVER _FIG.SOURCE + !
    0 OVER _FIG.NAME-A + !  0 SWAP _FIG.NAME-U + ! ;

: _DV-FIGS-FREE  ( -- )
    _DOCV-O-FIGS-N _DV@ 0 ?DO I _DV-FIG _DV-FIG-HIDE LOOP
    _DOCV-O-FIGS-A _DV@ _DOCV-O-FIGS-CAP _DV@ _DV-FREE
    0 _DOCV-O-FIGS-A _DV! 0 _DOCV-O-FIGS-CAP _DV! 0 _DOCV-O-FIGS-N _DV! ;

\ _DV-FIG-SHOW ( name-a name-u fig -- )
\   Give a figure a picture widget showing its picture, in a region inside
\   the view's, when its source and memory allow.  It is tried once while
\   the figure stays shown; a figure without one shows its name.
: _DV-FIG-SHOW  ( name-a name-u fig -- )
    _DVF-F !
    _DVF-F @ _FIG.NAME-A + @ IF 2DROP EXIT THEN
    DUP 0= IF 2DROP EXIT THEN
    DUP _DV-ALLOC ?DUP 0= IF 2DROP EXIT THEN            ( a u copy )
    DUP _DVF-F @ _FIG.NAME-A + !  OVER _DVF-F @ _FIG.NAME-U + !
    SWAP MOVE
    _DVF-F @ _FIG.NAME-A + @ _DVF-F @ _FIG.NAME-U + @ _DV-RESOLVE
    ?DUP 0= IF EXIT THEN
    _DVF-F @ _FIG.SOURCE + !
    _DV-RGN 0 0 1 1 RGN-SUB _DVF-F @ _FIG.RGN + !
    _DVF-F @ _FIG.RGN + @ _DOCV-O-MSRC _DV@ PICT-NEW _DVF-F @ _FIG.PICT + !
    _DVF-F @ _FIG.SOURCE + @
    _DVF-F @ _FIG.NAME-A + @ _DVF-F @ _FIG.NAME-U + @
    _DVF-F @ _FIG.PICT + @ PICT-SOURCE! ;

\ =====================================================================
\  4. Rows
\ =====================================================================

: _DV-COUNT  ( index -- a )  CELLS _DOCV-O-COUNTS-A _DV@ + ;

\ Counts for the document's blocks at the region's width and height,
\ forgotten when either changes; false when there are no blocks to show
\ or memory refuses the counts.
: _DV-COUNTS?  ( -- ok? )
    _DV-BLOCKS 0= IF 0 EXIT THEN
    _DV-RGN RGN-W _DV-H
    OVER _DOCV-O-COLS _DV@ = OVER _DOCV-O-HEIGHT _DV@ = AND
    _DOCV-O-COUNTS-A _DV@ 0<> AND IF 2DROP -1 EXIT THEN
    _DOCV-O-HEIGHT _DV! _DOCV-O-COLS _DV!
    _DV-BLOCKS CELLS
    DUP _DOCV-O-COUNTS-CAP _DV@ > IF
        _DOCV-O-COUNTS-A _DV@ _DOCV-O-COUNTS-CAP _DV@ _DV-FREE
        0 _DOCV-O-COUNTS-A _DV! 0 _DOCV-O-COUNTS-CAP _DV!
        DUP _DV-ALLOC ?DUP 0= IF DROP 0 EXIT THEN
        _DOCV-O-COUNTS-A _DV! DUP _DOCV-O-COUNTS-CAP _DV!
    THEN
    _DOCV-O-COUNTS-A _DV@ SWAP -1 FILL
    _DV-REVISE -1 ;

\ Give the counts back; the next count makes them again.
: _DV-COUNTS-FREE  ( -- )
    _DOCV-O-COUNTS-A _DV@ _DOCV-O-COUNTS-CAP _DV@ _DV-FREE
    0 _DOCV-O-COUNTS-A _DV! 0 _DOCV-O-COUNTS-CAP _DV! 0 _DOCV-O-COLS _DV! ;

VARIABLE _DVC-I
VARIABLE _DVC-T
VARIABLE _DVC-C
VARIABLE _DVC-OK

\ _DV-CONTENT-ROWS ( index -- rows ok? )
\   The rows block INDEX's content takes after its rows before: one for a
\   rule, a figure's picture rows and its caption's lines, or its lines.
\   A block whose content cannot be read or laid out now takes one row,
\   and OK is false, so the count is not kept.
: _DV-CONTENT-ROWS  ( index -- rows ok? )
    DUP _DVC-I ! -1 _DVC-OK !
    _DV-DOC DOC-BLOCK DUP BLK-KIND@ DOC-B-RULE = IF DROP 1 -1 EXIT THEN
    _DV-TEXT-WIDTH _DVC-T !
    _DVC-I @ _DV-DOC DOC-CONTENT IF DROP 1 0 EXIT THEN _DVC-C !
    _DVC-C @ DCT-KIND@ DOC-B-FIGURE = IF
        _DVC-C @ _DVC-I @ _DV-FIG-OF DUP 0= IF 0 _DVC-OK ! THEN
        _DVC-T @ _DV-PICTURE-ROWS
        _DVC-C @ DCT-TEXT NIP IF
            _DVC-C @ DCT-TEXT 0 _DVC-T @ _DV-COUNT-LINES
            _DVC-OK @ AND _DVC-OK ! +
        THEN
        _DVC-OK @ EXIT
    THEN
    _DVC-C @ DCT-TEXT _DVC-C @ DCT-KIND@ DOC-B-CODE = _DVC-T @ _DV-COUNT-LINES ;

\ The rows block INDEX takes, its rows before included, counted once at
\ the view's width.
: _DV-ROWS  ( index -- rows )
    DUP _DV-COUNT @ DUP 0< 0= IF NIP EXIT THEN DROP
    DUP _DV-DOC DOC-BLOCK BLK-ROWS-BEFORE@ OVER _DV-CONTENT-ROWS
    >R + R> IF DUP ROT _DV-COUNT ! ELSE NIP THEN ;

\ =====================================================================
\  5. Scrolling
\ =====================================================================

: _DV-TOP      ( -- index )  _DOCV-O-TOP _DV@ ;
: _DV-TOP-ROW  ( -- rows )   _DOCV-O-TOP-ROW _DV@ ;

VARIABLE _DVS-N

\ Move the view's top down N rows, no further than the document's last.
: _DV-DOWN  ( n -- )
    _DVS-N !
    BEGIN _DVS-N @ 0> WHILE
        _DV-TOP _DV-ROWS _DV-TOP-ROW -                  ( left )
        DUP _DVS-N @ > IF
            DROP _DV-TOP-ROW _DVS-N @ + _DOCV-O-TOP-ROW _DV! 0 _DVS-N !
        ELSE _DV-TOP 1+ _DV-BLOCKS < IF
            NEGATE _DVS-N +!
            _DV-TOP 1+ _DOCV-O-TOP _DV! 0 _DOCV-O-TOP-ROW _DV!
        ELSE
            1- _DV-TOP-ROW + _DOCV-O-TOP-ROW _DV! 0 _DVS-N !
        THEN THEN
    REPEAT ;

\ Move the view's top up N rows, no further than the document's first.
: _DV-UP  ( n -- )
    _DVS-N !
    BEGIN _DVS-N @ 0> WHILE
        _DV-TOP-ROW _DVS-N @ < 0= IF
            _DV-TOP-ROW _DVS-N @ - _DOCV-O-TOP-ROW _DV! 0 _DVS-N !
        ELSE _DV-TOP 0= IF
            0 _DOCV-O-TOP-ROW _DV! 0 _DVS-N !
        ELSE
            _DV-TOP-ROW 1+ NEGATE _DVS-N +!
            _DV-TOP 1- _DOCV-O-TOP _DV!
            _DV-TOP _DV-ROWS 1- _DOCV-O-TOP-ROW _DV!
        THEN THEN
    REPEAT ;

VARIABLE _DVB-SUM
VARIABLE _DVB-I

\ The rows from the view's top to the document's end, counted no further
\ than LIMIT.
: _DV-ROWS-BELOW  ( limit -- rows )
    _DV-TOP-ROW + 0 _DVB-SUM ! _DV-TOP _DVB-I !
    BEGIN _DVB-I @ _DV-BLOCKS < _DVB-SUM @ 2 PICK < AND WHILE
        _DVB-I @ _DV-ROWS _DVB-SUM +! 1 _DVB-I +!
    REPEAT DROP
    _DVB-SUM @ _DV-TOP-ROW - ;

\ Keep the view on the document: its last row no higher than the view's
\ bottom, unless the whole document is shorter than the view.
: _DV-CLAMP  ( -- )
    _DV-TOP _DV-BLOCKS 1- MIN 0 MAX _DOCV-O-TOP _DV!
    _DV-TOP-ROW _DV-TOP _DV-ROWS 1- MIN 0 MAX _DOCV-O-TOP-ROW _DV!
    _DV-H _DV-ROWS-BELOW DUP _DV-H < IF _DV-H SWAP - _DV-UP ELSE DROP THEN ;

: _DV-SCROLL  ( rows -- )
    _DV-COUNTS? 0= IF DROP EXIT THEN
    _DV-TOP >R _DV-TOP-ROW >R
    DUP 0< IF NEGATE _DV-UP ELSE _DV-DOWN THEN
    _DV-CLAMP
    _DV-TOP-ROW R> <> _DV-TOP R> <> OR IF _DV-CHANGED THEN ;

\ Put block INDEX at the view's top, as near as the document allows.
: _DV-GO  ( index -- )
    _DV-COUNTS? 0= IF DROP EXIT THEN
    0 MAX _DV-BLOCKS 1- MIN _DOCV-O-TOP _DV! 0 _DOCV-O-TOP-ROW _DV!
    _DV-CLAMP _DV-CHANGED ;

: _DV-END  ( -- )
    _DV-COUNTS? 0= IF EXIT THEN
    _DV-BLOCKS 1- _DOCV-O-TOP _DV!
    _DV-TOP _DV-ROWS 1- _DOCV-O-TOP-ROW _DV!
    _DV-CLAMP _DV-CHANGED ;

\ =====================================================================
\  6. Drawing
\ =====================================================================

VARIABLE _DVD-I        \ the block being drawn
VARIABLE _DVD-B        \ its record
VARIABLE _DVD-C        \ its content
VARIABLE _DVD-TOP      \ the view row of its first content row
VARIABLE _DVD-X        \ its text area's first column
VARIABLE _DVD-T        \ its text area's width
VARIABLE _DVD-KIND     \ its content's kind
VARIABLE _DVD-SEEN     \ the draw's number

: _DVD-VISIBLE?  ( row -- flag )  0 _DV-H WITHIN ;
: _DVD-CONTAINERS  ( -- n )  _DVD-B @ _DV-DOC DOC-CONTAINERS NIP ;

\ --- Marks ---------------------------------------------------------------

VARIABLE _DVG-ROW
VARIABLE _DVG-N
VARIABLE _DVG-FIRST
VARIABLE _DVG-X
VARIABLE _DVG-DEPTH
VARIABLE _DVG-C

\ A list item's number and a full stop, right-aligned before the item's
\ last cell; the clip cuts a number wider than its cells.
: _DVG-NUMBER-PAINT  ( -- )
    DRW-STYLE-RESTORE _DOCV-MUTED DRW-FG!
    _DVG-C @ CNT-NUMBER@ NUM>STR                         ( a u )
    _DVG-X @ _DVG-C @ CNT-WIDTH@ 1- + OVER 1+ -          ( a u col )
    >R TUCK _DVG-ROW @ R@ DRW-TEXT
    46 _DVG-ROW @ ROT R> + DRW-CHAR ;

: _DVG-ITEM-MARK  ( -- )
    _DVG-C @ CNT-WIDTH@ 0> 0= IF EXIT THEN
    _DVG-C @ CNT-KIND@ DOC-C-BULLET = IF
        _DVG-DEPTH @ 3 MOD DUP 0= IF DROP 8226 ELSE 1 = IF 9702 ELSE 9642 THEN THEN
        DRW-STYLE-RESTORE _DOCV-MUTED DRW-FG! _DVG-ROW @ _DVG-X @ DRW-CHAR EXIT
    THEN
    ['] _DVG-NUMBER-PAINT _DVG-ROW @ _DVG-X @ 1 _DVG-C @ CNT-WIDTH@ 1- DRW-WITH-CLIP ;

\ _DVD-GUTTER ( row n first? -- )
\   The marks at the left of view row ROW, which lies inside the block's
\   first N containers: a quote's bar in its first cell, and on the first
\   content row (FIRST?) the mark of each item the block starts.
: _DVD-GUTTER  ( row n first? -- )
    _DVG-FIRST ! _DVG-N ! _DVG-ROW !
    _DVG-ROW @ _DVD-VISIBLE? 0= IF EXIT THEN
    0 _DVG-X ! 0 _DVG-DEPTH !
    _DVD-B @ _DV-DOC DOC-CONTAINERS _DVG-N @ MIN 0 ?DO
        DUP I CNT-SIZE * + _DVG-C !
        _DVG-C @ CNT-KIND@ DOC-C-QUOTE = IF
            _DVG-C @ CNT-WIDTH@ 0> IF
                DRW-STYLE-RESTORE _DOCV-MUTED DRW-FG!
                _DOCV-BAR _DVG-ROW @ _DVG-X @ DRW-CHAR
            THEN
        ELSE
            _DVG-C @ CNT-START? _DVG-FIRST @ AND IF _DVG-ITEM-MARK THEN
            _DVG-C @ CNT-KIND@ DOC-C-BULLET = IF 1 _DVG-DEPTH +! THEN
        THEN
        _DVG-C @ CNT-WIDTH@ _DVG-X +!
    LOOP DROP ;

\ --- Text ----------------------------------------------------------------

VARIABLE _DVL-BASE-FG     \ the block's look where its text means nothing
VARIABLE _DVL-BASE-A
VARIABLE _DVL-AT          \ where the drawn text starts in the block's text
VARIABLE _DVL-ROW
VARIABLE _DVL-PAD         \ cells before a right-to-left line

\ The look at a byte of the drawn text: its meaning's, with the block's
\ attributes as well, or the block's.
: _DVL-LOOK  ( byte -- fg attrs )
    _DVL-AT @ + _DVD-C @ DCT-MAP + C@
    DUP TSTY-VALID? 0= IF DROP _DVL-BASE-FG @ _DVL-BASE-A @ EXIT THEN
    DUP SPAL-DEFAULT SPAL-FG@
    SWAP SPAL-DEFAULT SPAL-ATTRS@ _DVL-BASE-A @ OR ;

\ The block's own look over the owner's style: a heading's, underlined at
\ levels 1 and 2; a caption's, muted and italic; or the style itself.
: _DVL-BASE!  ( -- )
    DRW-STYLE-RESTORE DRW-FG@ _DVL-BASE-FG ! DRW-ATTR@ _DVL-BASE-A !
    _DVD-KIND @ DOC-B-HEADING = IF
        TSTY-HEADING SPAL-DEFAULT SPAL-FG@ _DVL-BASE-FG !
        TSTY-HEADING SPAL-DEFAULT SPAL-ATTRS@ _DVL-BASE-A @ OR
        _DVD-C @ DCT-LEVEL@ 3 < IF CELL-A-UNDERLINE OR THEN _DVL-BASE-A !
        EXIT
    THEN
    _DVD-KIND @ DOC-B-FIGURE = IF
        _DOCV-MUTED _DVL-BASE-FG ! CELL-A-ITALIC _DVL-BASE-A @ OR _DVL-BASE-A !
    THEN ;

: _DVL-PAINT  ( -- )
    _DVL-BASE-FG @ DRW-FG! _DVL-BASE-A @ DRW-ATTR!
    _DVD-KIND @ DOC-B-CODE = IF _DOCV-CODE-BG DRW-BG! THEN
    _DV-TLN TLINES-ROW ?DUP IF
        _DVL-ROW @ _DVD-X @ _DVL-PAD @ + 0 0 0 ['] _DVL-LOOK DRW-TROW-STYLED
        EXIT
    THEN
    _DV-TLN TLINES-BYTES _DVL-ROW @ _DVD-X @ ['] _DVL-LOOK
    DRW-TEXT-STYLED-UNTRUSTED ;

\ Draw the line the cursor has read on view row ROW, cut at the text area;
\ a line of a right-to-left paragraph ends at the area's right edge.
: _DVL-DRAW  ( row -- )
    DUP _DVL-ROW !
    _DVD-VISIBLE? 0= IF EXIT THEN
    DRW-STYLE-RESTORE
    _DVD-KIND @ DOC-B-CODE = IF
        _DOCV-CODE-BG DRW-BG! 32 _DVL-ROW @ _DVD-X @ 1 _DVD-T @ DRW-FILL-RECT
    THEN
    _DV-TLN TLINES-ROW IF
        _DV-TLN TLINES-PARAGRAPH _DVD-C @ DCT-TEXT DROP - _DVL-AT !
        _DV-TLN TLINES-RTL? IF _DVD-T @ _DV-TLN TLINES-WIDTH - 0 MAX ELSE 0 THEN
    ELSE
        _DV-TLN TLINES-BYTES DROP _DVD-C @ DCT-TEXT DROP - _DVL-AT ! 0
    THEN _DVL-PAD !
    ['] _DVL-PAINT _DVL-ROW @ _DVD-X @ 1 _DVD-T @ DRW-WITH-CLIP
    DRW-STYLE-RESTORE ;

VARIABLE _DVL-K

\ Draw the block's lines from view row ROW, while they lie above the
\ view's bottom, each with its marks.
: _DVD-LINES  ( row -- )
    _DVL-K !
    _DVD-C @ DCT-TEXT
    DUP 0= _DVD-KIND @ DOC-B-FIGURE = AND IF 2DROP EXIT THEN
    _DVD-KIND @ DOC-B-CODE = _DVD-T @ _DV-LINES-START
    BEGIN _DVL-K @ _DV-H < AND WHILE
        _DVL-K @ _DVD-CONTAINERS _DVL-K @ _DVD-TOP @ = _DVD-GUTTER
        _DVL-K @ _DVL-DRAW
        1 _DVL-K +!
        _DV-TLN TLINES-NEXT
    REPEAT ;

\ --- Rules and figures ---------------------------------------------------

: _DVD-RULE  ( -- )
    _DVD-TOP @ _DVD-VISIBLE? 0= IF EXIT THEN
    _DVD-TOP @ _DVD-CONTAINERS -1 _DVD-GUTTER
    DRW-STYLE-RESTORE _DOCV-RULE DRW-FG!
    _DOCV-LINE _DVD-TOP @ _DVD-X @ _DVD-T @ DRW-HLINE DRW-STYLE-RESTORE ;

: _DVD-NAME-PAINT  ( -- )
    DRW-STYLE-RESTORE _DOCV-MUTED DRW-FG!
    _DVD-C @ DCT-FIGURE _DVD-TOP @ _DVD-X @ DRW-TEXT-UNTRUSTED ;

VARIABLE _DVP-FIG
VARIABLE _DVP-ROWS

\ A figure's picture rows: its marks, and its picture widget drawn over
\ the whole rectangle, which the view's region cuts; a figure with no
\ picture shows its name.  Only a figure with a row in view is shown.
: _DVD-PICTURE  ( -- )
    _DVD-C @ _DVD-I @ _DV-FIG-OF DUP _DVP-FIG !
    _DVD-T @ _DV-PICTURE-ROWS _DVP-ROWS !
    _DVP-ROWS @ 0 ?DO
        _DVD-TOP @ I + _DVD-CONTAINERS I 0= _DVD-GUTTER
    LOOP
    _DVD-TOP @ _DVP-ROWS @ + 0> _DVD-TOP @ _DV-H < AND 0= IF EXIT THEN
    _DVP-FIG @ IF
        _DVD-SEEN @ _DVP-FIG @ _FIG.SEEN + !
        _DVD-C @ DCT-FIGURE _DVP-FIG @ _DV-FIG-SHOW
        _DVP-FIG @ _FIG.PICT + @ ?DUP IF
            _DV-RGN RGN-ROW _DVD-TOP @ + _DV-RGN RGN-COL _DVD-X @ +
            _DVP-ROWS @ _DVD-T @ _DVP-FIG @ _FIG.RGN + @ RGN-BOUNDS!
            DRW-STYLE-RESTORE _DV-RGN WDG-DRAW-IN EXIT
        THEN
    THEN
    _DVD-TOP @ _DVD-VISIBLE? IF
        ['] _DVD-NAME-PAINT _DVD-TOP @ _DVD-X @ 1 _DVD-T @ DRW-WITH-CLIP
        DRW-STYLE-RESTORE
    THEN ;

\ --- Blocks --------------------------------------------------------------

: _DVD-UNREAD-PAINT  ( -- )
    DRW-STYLE-RESTORE _DOCV-MUTED DRW-FG!
    S" (this part could not be read)" _DVD-TOP @ _DVD-X @ DRW-TEXT ;

\ Draw block INDEX, whose first row lies at view row ROW.
: _DVD-BLOCK  ( index row -- )
    OVER _DVD-I ! SWAP _DV-DOC DOC-BLOCK _DVD-B !
    _DVD-B @ _DV-INDENT _DVD-X !  _DVD-B @ _DV-TEXT-WIDTH _DVD-T !
    \ The rows before, inside the containers they lie in.
    _DVD-B @ BLK-ROWS-BEFORE@ 0 ?DO
        DUP I + _DVD-B @ BLK-INSIDE@ 0 _DVD-GUTTER
    LOOP
    _DVD-B @ BLK-ROWS-BEFORE@ + _DVD-TOP !
    _DVD-B @ BLK-KIND@ DOC-B-RULE = IF _DVD-RULE EXIT THEN
    _DVD-I @ _DV-DOC DOC-CONTENT IF
        DROP
        _DVD-TOP @ _DVD-VISIBLE? IF
            _DVD-TOP @ _DVD-CONTAINERS -1 _DVD-GUTTER
            ['] _DVD-UNREAD-PAINT _DVD-TOP @ _DVD-X @ 1 _DVD-T @ DRW-WITH-CLIP
            DRW-STYLE-RESTORE
        THEN EXIT
    THEN
    DUP _DVD-C ! DCT-KIND@ _DVD-KIND !
    _DVL-BASE!
    _DVD-KIND @ DOC-B-FIGURE = IF
        _DVD-PICTURE _DVD-TOP @ _DVP-ROWS @ + _DVD-LINES EXIT
    THEN
    _DVD-TOP @ _DVD-LINES ;

\ Hide the figures this draw did not show.
: _DVD-HIDE-UNSEEN  ( -- )
    _DOCV-O-FIGS-N _DV@ 0 ?DO
        I _DV-FIG DUP _FIG.SEEN + @ _DVD-SEEN @ <> IF _DV-FIG-HIDE ELSE DROP THEN
    LOOP ;

: _DV-DRAW  ( widget -- )
    _DV-W !
    DRW-STYLE-RESTORE
    32 0 0 _DV-H _DV-RGN RGN-W DRW-FILL-RECT
    _DV-COUNTS? 0= IF 0 _DOCV-O-END _DV! EXIT THEN
    _DOCV-O-DRAWS _DV@ 1+ DUP _DOCV-O-DRAWS _DV! _DVD-SEEN !
    _DV-TOP >R _DV-TOP-ROW >R
    _DV-CLAMP
    _DV-TOP-ROW R> <> _DV-TOP R> <> OR IF _DV-REVISE THEN
    _DV-TOP-ROW NEGATE _DV-TOP                          ( row index )
    BEGIN DUP _DV-BLOCKS < 2 PICK _DV-H < AND WHILE
        2DUP SWAP _DVD-BLOCK
        DUP _DV-ROWS ROT + SWAP 1+
    REPEAT
    NIP _DOCV-O-END _DV!
    _DVD-HIDE-UNSEEN
    \ Keep the contents shown; give back the rest.
    _DV-TOP _DOCV-O-END _DV@ _DV-DOC DOC-KEEP
    DRW-STYLE-RESTORE ;

\ =====================================================================
\  7. Input
\ =====================================================================

\ The byte of the block's text at view column COL of the line the cursor
\ read, or -1 when no character covers it.
: _DVH-BYTE-AT  ( col -- byte | -1 )
    _DVD-X @ - DUP 0< OVER _DVD-T @ < 0= OR IF DROP -1 EXIT THEN
    _DV-TLN TLINES-ROW IF
        _DV-TLN TLINES-RTL? IF _DVD-T @ _DV-TLN TLINES-WIDTH - 0 MAX - THEN
        _DV-TLN TROW-AT-COLUMN ?DUP 0= IF -1 EXIT THEN
        TROW.BYTE _DV-TLN TLINES-PARAGRAPH + _DVD-C @ DCT-TEXT DROP - EXIT
    THEN
    \ A line shown as its bytes: a scalar a cell.
    >R _DV-TLN TLINES-BYTES R> 0 ?DO DUP 0= IF LEAVE THEN _DV-SKIP-SCALAR LOOP
    0= IF DROP -1 EXIT THEN
    _DVD-C @ DCT-TEXT DROP - ;

VARIABLE _DVH-ROW
VARIABLE _DVH-COL
VARIABLE _DVH-BYTE
VARIABLE _DVH-BLOCK

\ Find the byte of the text at the press, in block INDEX, whose first row
\ lies at view row ROW.
: _DVH-IN-BLOCK  ( row index -- )
    DUP _DVD-I ! _DV-DOC DOC-BLOCK _DVD-B !
    _DVD-B @ BLK-ROWS-BEFORE@ + _DVD-TOP !
    _DVD-B @ _DV-INDENT _DVD-X !  _DVD-B @ _DV-TEXT-WIDTH _DVD-T !
    _DVD-B @ BLK-KIND@ DOC-B-RULE = IF EXIT THEN
    _DVD-I @ _DV-DOC DOC-CONTENT IF DROP EXIT THEN
    DUP _DVD-C ! DCT-KIND@ _DVD-KIND !
    _DVD-TOP @
    _DVD-KIND @ DOC-B-FIGURE = IF
        _DVD-C @ DCT-TEXT NIP 0= IF DROP EXIT THEN
        _DVD-C @ _DVD-I @ _DV-FIG-OF _DVD-T @ _DV-PICTURE-ROWS +
    THEN
    _DVH-ROW @ SWAP - DUP 0< IF DROP EXIT THEN          ( line )
    _DVD-C @ DCT-TEXT _DVD-KIND @ DOC-B-CODE = _DVD-T @ _DV-LINES-START
    SWAP 0 ?DO DUP IF DROP _DV-TLN TLINES-NEXT THEN LOOP
    0= IF EXIT THEN
    _DVH-COL @ _DVH-BYTE-AT DUP 0< IF DROP EXIT THEN
    _DVH-BYTE ! _DVD-I @ _DVH-BLOCK ! ;

\ _DVH-HIT ( row col -- )
\   Find the block, and the byte of its text, at view cell (row, col);
\   _DVH-BLOCK is -1 when the cell shows no text.
: _DVH-HIT  ( row col -- )
    _DVH-COL ! _DVH-ROW ! -1 _DVH-BLOCK ! -1 _DVH-BYTE !
    _DVH-ROW @ _DVD-VISIBLE? 0= IF EXIT THEN
    _DV-COUNTS? 0= IF EXIT THEN
    _DV-TOP-ROW NEGATE _DV-TOP                          ( row index )
    BEGIN DUP _DV-BLOCKS < WHILE
        2DUP _DV-ROWS + _DVH-ROW @ > IF _DVH-IN-BLOCK EXIT THEN
        DUP _DV-ROWS ROT + SWAP 1+
    REPEAT 2DROP ;

\ Follow a link: to one of the document's headings, or to the owner.
: _DV-FOLLOW  ( target-a target-u -- )
    DUP 0= IF 2DROP EXIT THEN
    OVER C@ 35 = IF
        1 /STRING _DV-DOC DOC-ANCHOR DUP 0< IF DROP EXIT THEN _DV-GO EXIT
    THEN
    _DOCV-O-FOLLOW _DV@ ?DUP 0= IF 2DROP EXIT THEN _DV-OWNER ;

\ Follow the link at byte BYTE of block BLOCK's text, if one is there.
: _DV-FOLLOW-AT  ( byte block -- )
    OVER 0< IF 2DROP EXIT THEN
    _DV-DOC DOC-CONTENT IF 2DROP EXIT THEN
    DCT-LINK-AT DUP 0= IF 2DROP EXIT THEN
    _DV-FOLLOW ;

\ The byte where scalar OFFSET of block BLOCK's text starts, or -1.
: _DV-SCALAR>BYTE  ( offset block -- byte | -1 )
    _DV-DOC DOC-CONTENT IF 2DROP -1 EXIT THEN
    DCT-TEXT ROT >R OVER SWAP R>                         ( a a u offset )
    0 ?DO DUP 0= IF LEAVE THEN _DV-SKIP-SCALAR LOOP
    0= IF 2DROP -1 EXIT THEN
    SWAP - ;

: _DV-POINTER  ( event -- consumed? )
    DUP 8 + @ KEY-MOUSE-BUTTON
    CASE
        KEY-MOUSE-LEFT OF
            16 + @                          \ mods = row<<16 | col
            DUP 16 RSHIFT _DV-RGN RGN-ROW -
            SWAP 0xFFFF AND _DV-RGN RGN-COL - _DVH-HIT
            _DVH-BYTE @ _DVH-BLOCK @ _DV-FOLLOW-AT -1
        ENDOF
        KEY-MOUSE-SCROLL-UP OF DROP _DOCV-WHEEL-ROWS NEGATE _DV-SCROLL -1 ENDOF
        KEY-MOUSE-SCROLL-DN OF DROP _DOCV-WHEEL-ROWS _DV-SCROLL -1 ENDOF
        \ A link the rich renderer laid out: its block's key and the
        \ scalar it starts at.  A position on no link is dropped.
        KEY-MOUSE-TEXT-FOLLOW OF
            DROP KEY-MOUSE-TEXT-OFFSET @ KEY-MOUSE-TEXT-KEY @ 1-
            DUP >R _DV-SCALAR>BYTE R> _DV-FOLLOW-AT -1
        ENDOF
        >R DROP 0 R>
    ENDCASE ;

: _DV-PAGE  ( -- rows )  _DV-H 1- 1 MAX ;

: _DV-HANDLE  ( event widget -- consumed? )
    _DV-W !
    _DV-DOC 0= IF DROP 0 EXIT THEN
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-UP   OF -1 _DV-SCROLL -1 ENDOF
            KEY-DOWN OF 1 _DV-SCROLL -1 ENDOF
            KEY-PGUP OF _DV-PAGE NEGATE _DV-SCROLL -1 ENDOF
            KEY-PGDN OF _DV-PAGE _DV-SCROLL -1 ENDOF
            KEY-HOME OF 0 _DV-GO -1 ENDOF
            KEY-END  OF _DV-END -1 ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DUP @ KEY-T-MOUSE = IF _DV-POINTER EXIT THEN
    DROP 0 ;

\ =====================================================================
\  8. Public API
\ =====================================================================

\ DOCV-NEW ( rgn msrc -- widget )   A document view showing nothing yet.
: DOCV-NEW  ( rgn msrc -- widget )
    _DOCV-DESC-SIZE ALLOCATE 0<> ABORT" DOCV-NEW: alloc"
    DUP _DOCV-DESC-SIZE 0 FILL
    >R
    R@ _DOCV-O-MSRC + !
    R@ WDG-T-DOCUMENT ROT ['] _DV-DRAW ['] _DV-HANDLE WDG-INIT
    R> ;

\ DOCV-OWNER! ( resolve-xt release-xt follow-xt ctx widget -- )
\   Where figures' pictures come from, where followed links go, and the
\   context those words take.  Any word may be 0: a figure then shows its
\   name, and only links to the document's own headings are followed.
: DOCV-OWNER!  ( resolve-xt release-xt follow-xt ctx widget -- )
    _DV-W !
    _DV-FIGS-FREE
    _DOCV-O-CTX _DV! _DOCV-O-FOLLOW _DV! _DOCV-O-RELEASE _DV!
    _DOCV-O-RESOLVE _DV!
    0 _DOCV-O-COLS _DV!  _DV-CHANGED ;

\ DOCV-DOCUMENT! ( doc widget -- )
\   Show an open document from its top, or nothing for 0, giving back
\   all the view held for the one before.  The owner keeps the document
\   open while the view shows it.
: DOCV-DOCUMENT!  ( doc widget -- )
    _DV-W !
    _DV-FIGS-FREE _DV-COUNTS-FREE
    _DOCV-O-DOC _DV!
    0 _DOCV-O-TOP _DV! 0 _DOCV-O-TOP-ROW _DV! 0 _DOCV-O-END _DV!
    _DV-CHANGED ;

: DOCV-DOCUMENT@  ( widget -- doc|0 )  _DOCV-O-DOC + @ ;
: DOCV-REVISION@  ( widget -- n )  _DOCV-O-REVISION + @ ;

\ DOCV-TOP@ ( widget -- block rows )
\   The block the view's top row lies in, and its rows above the view.
: DOCV-TOP@  ( widget -- block rows )
    DUP _DOCV-O-TOP + @ SWAP _DOCV-O-TOP-ROW + @ ;

\ DOCV-SHOWN ( widget -- first end )
\   The blocks the last draw showed, END after the last.
: DOCV-SHOWN  ( widget -- first end )
    DUP _DOCV-O-TOP + @ SWAP _DOCV-O-END + @ ;

\ DOCV-ROWS ( index widget -- rows )
\   The rows block INDEX takes at the view's width, its rows before
\   included, or 0 when nothing is shown.
: DOCV-ROWS  ( index widget -- rows )
    _DV-W ! _DV-COUNTS? 0= IF DROP 0 EXIT THEN
    DUP 0 _DV-BLOCKS WITHIN 0= IF DROP 0 EXIT THEN _DV-ROWS ;

\ DOCV-SCROLL ( rows widget -- )   Scroll by signed rows.
: DOCV-SCROLL  ( rows widget -- )  _DV-W ! _DV-SCROLL ;

\ DOCV-GO ( index widget -- )   Show block INDEX at the view's top.
: DOCV-GO  ( index widget -- )  _DV-W ! _DV-GO ;

\ DOCV-FOLLOW ( target-a target-u widget -- )
\   Follow a link's target as a press on it does.
: DOCV-FOLLOW  ( target-a target-u widget -- )
    _DV-W ! _DV-DOC 0= IF 2DROP EXIT THEN _DV-FOLLOW ;

\ DOCV-PENDING? ( widget -- flag )   A figure's picture is still pending.
: DOCV-PENDING?  ( widget -- flag )
    _DV-W !
    _DOCV-O-FIGS-N _DV@ 0 ?DO
        I _DV-FIG _FIG.PICT + @ ?DUP IF
            PICT-PENDING? IF -1 UNLOOP EXIT THEN
        THEN
    LOOP 0 ;

\ DOCV-SERVICE ( widget -- changed? )
\   Decode some more of the first figure whose picture is pending.  True
\   when what the view shows changed.
: DOCV-SERVICE  ( widget -- changed? )
    _DV-W !
    _DOCV-O-FIGS-N _DV@ 0 ?DO
        I _DV-FIG _FIG.PICT + @ ?DUP IF
            DUP PICT-PENDING? IF
                PICT-STEP-PIXELS SWAP PICT-SERVICE
                DUP IF _DV-W @ WDG-DIRTY THEN
                UNLOOP EXIT
            THEN
            DROP
        THEN
    LOOP 0 ;

\ DOCV-FREE ( widget -- )
\   Give back everything the view holds; the document stays the owner's.
: DOCV-FREE  ( widget -- )
    _DV-W !
    _DV-FIGS-FREE _DV-COUNTS-FREE
    _DV-W @ FREE ;

\ =====================================================================
\  9. Storage authority and the document's capture
\ =====================================================================
\
\  The view publishes the blocks its last draw showed: each block's key is
\  its index plus one, its kind its content's, a figure's picture rows
\  those the view gave it, its containers, and its text as CELL shows it
\  (UTF8-SAFE-COPY), its direction controls inert stand-ins (BIDI-INERT)
\  and its meanings style runs.  The capture reads only what the view and
\  the document keep for those blocks, never the source; a block whose
\  content or figure is not kept, or counts made at another size, leave
\  the view UNAVAILABLE, and CELL shows it.

\ DOCV-GENUINE? ( widget -- flag )   A live document view, by its header.
: DOCV-GENUINE?  ( widget -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _DOCV-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _WDG-O-TYPE + @ WDG-T-DOCUMENT <> IF DROP 0 EXIT THEN
    DUP _WDG-O-DRAW-XT + @ ['] _DV-DRAW <> IF DROP 0 EXIT THEN
    DUP _WDG-O-HANDLE-XT + @ ['] _DV-HANDLE <> IF DROP 0 EXIT THEN
    WDG-REGION DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    RGN-SIZE MSPAN-NONWRAPPING? ;

\ DOCV-STORAGE-DISJOINT? ( address bytes -- flag )
\   Pure and deliberately unguarded: a caller span against the module's
\   mutable scratch.
: DOCV-STORAGE-DISJOINT?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _DOCV-OWNED-LIMIT @ DUP _DOCV-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _DOCV-OWNED-START - >R
    _DOCV-OWNED-START R> MSPAN-OVERLAP? 0= ;

VARIABLE _DVSD-A
VARIABLE _DVSD-U
VARIABLE _DVSD-W

: _DVSD-CLEAR?  ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    _DVSD-A @ _DVSD-U @ 2SWAP MSPAN-OVERLAP? 0= ;

\ DOCV-DOCUMENT-STORAGE-DISJOINT? ( address bytes widget -- flag )
\   A caller span against the module and all the capture of one live view
\   reads: its descriptor, region, counts and figures, and the document's
\   records and the contents of the blocks the view shows.
: DOCV-DOCUMENT-STORAGE-DISJOINT?  ( address bytes widget -- flag )
    >R
    2DUP DOCV-STORAGE-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    _DVSD-U ! _DVSD-A ! R> _DVSD-W !
    _DVSD-W @ DOCV-GENUINE? 0= IF 0 EXIT THEN
    _DVSD-U @ 0= IF -1 EXIT THEN
    _DVSD-W @ _DOCV-DESC-SIZE _DVSD-CLEAR? 0= IF 0 EXIT THEN
    _DVSD-W @ WDG-REGION RGN-SIZE _DVSD-CLEAR? 0= IF 0 EXIT THEN
    _DVSD-W @ _DOCV-O-COUNTS-A + @ _DVSD-W @ _DOCV-O-COUNTS-CAP + @
        _DVSD-CLEAR? 0= IF 0 EXIT THEN
    _DVSD-W @ _DOCV-O-FIGS-A + @ _DVSD-W @ _DOCV-O-FIGS-CAP + @
        _DVSD-CLEAR? 0= IF 0 EXIT THEN
    _DVSD-W @ _DOCV-O-DOC + @ ?DUP 0= IF -1 EXIT THEN
    >R _DVSD-A @ _DVSD-U @ _DVSD-W @ DOCV-SHOWN R> DOC-STORAGE-DISJOINT? ;

VARIABLE _DVK-ROOT
VARIABLE _DVK-DST
VARIABLE _DVK-CAP
VARIABLE _DVK-B           \ the builder
VARIABLE _DVK-I
VARIABLE _DVK-BLOCK
VARIABLE _DVK-C           \ the block's content
VARIABLE _DVK-KIND
VARIABLE _DVK-TEXT-A
VARIABLE _DVK-TEXT-U
VARIABLE _DVK-SAFE-U
VARIABLE _DVK-DST-T

: _DVK-PREFLIGHT?  ( root destination capacity builder widget -- flag )
    DUP DOCV-GENUINE? 0= IF 0 EXIT THEN
    4 PICK 0= IF 0 EXIT THEN
    3 PICK 3 PICK 2 PICK DOCV-DOCUMENT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    1 PICK USCOL-BUILDER-SIZE 2 PICK
        DOCV-DOCUMENT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    1 PICK USCOL-BUILDER-SIZE USCOL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    3 PICK 3 PICK USCOL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    -1 ;

: _DVK-STATE  ( -- state )
    0
    _DV-W @ WDG-VISIBLE? IF USCOL-STATE-VISIBLE OR THEN
    _DV-W @ WDG-DISABLED? 0= IF USCOL-STATE-ENABLED OR THEN
    _DV-W @ WDG-FOCUSED?
    _DV-W @ WDG-VISIBLE? AND
    _DV-W @ WDG-DISABLED? 0= AND IF USCOL-STATE-SELECTED OR THEN ;

: _DVK-CONTAINERS  ( -- )
    _DVK-BLOCK @ _DV-DOC DOC-CONTAINERS 0 ?DO
        DUP I CNT-SIZE * +
        DUP CNT-KIND@ OVER CNT-WIDTH@ 2 PICK CNT-NUMBER@ 3 PICK CNT-START?
        _DVK-B @ USCOL-DOC-CONTAINER 2DROP
    LOOP DROP ;

: _DVK-RUN  ( start length meaning -- ok? )
    _DVK-B @ USCOL-DOC-TEXT-RUN DROP -1 ;

\ The block's text as CELL shows it, and its meanings as style runs.
: _DVK-TEXT  ( -- )
    _DVK-C @ DCT-TEXT _DVK-TEXT-U ! _DVK-TEXT-A !
    _DVK-TEXT-U @ 0= IF EXIT THEN
    _DVK-TEXT-A @ _DVK-TEXT-U @ UTF8-KEEP-LF UTF8-SAFE-BYTES DUP _DVK-SAFE-U !
    _DVK-B @ USCOL-DOC-TEXT-BEGIN DROP
    ?DUP IF
        DUP _DVK-DST-T !
        >R _DVK-TEXT-A @ _DVK-TEXT-U @ UTF8-KEEP-LF R> UTF8-SAFE-COPY
        _DVK-DST-T @ _DVK-SAFE-U @ BIDI-INERT
    THEN
    _DVK-TEXT-A @ _DVK-TEXT-U @ _DVK-C @ DCT-MAP ['] _DVK-RUN TSTY-RUNS DROP ;

\ Block INDEX, from what the view and the document keep; false when they
\ do not keep it.
: _DVK-BLOCK!  ( index -- ok? )
    DUP _DVK-I ! _DV-DOC DOC-BLOCK _DVK-BLOCK !
    _DVK-BLOCK @ BLK-KIND@ DOC-B-RULE = IF
        _DVK-I @ 1+ DOC-B-RULE 0
        _DVK-BLOCK @ BLK-ROWS-BEFORE@ _DVK-BLOCK @ BLK-INSIDE@ 0
        _DVK-B @ USCOL-DOC-BLOCK-BEGIN DROP
        _DVK-CONTAINERS
        _DVK-B @ USCOL-DOC-BLOCK-END DROP -1 EXIT
    THEN
    _DVK-I @ _DV-DOC DOC-KEPT DUP _DVK-C ! 0= IF 0 EXIT THEN
    _DVK-C @ DCT-KIND@ _DVK-KIND !
    _DVK-I @ 1+ _DVK-KIND @
    _DVK-KIND @ DOC-B-HEADING = IF _DVK-C @ DCT-LEVEL@ ELSE 0 THEN
    _DVK-BLOCK @ BLK-ROWS-BEFORE@ _DVK-BLOCK @ BLK-INSIDE@
    _DVK-KIND @ DOC-B-FIGURE = IF
        _DVK-I @ _DV-FIND-FIG ?DUP 0= IF 2DROP 2DROP DROP 0 EXIT THEN
        _DVK-BLOCK @ _DV-TEXT-WIDTH _DV-PICTURE-ROWS
    ELSE 0 THEN
    _DVK-B @ USCOL-DOC-BLOCK-BEGIN DROP
    _DVK-CONTAINERS
    _DVK-TEXT
    _DVK-B @ USCOL-DOC-BLOCK-END DROP -1 ;

\ DOCV-DOCUMENT-CAPTURE
\   ( root-key destination capacity builder widget -- bytes status )
\   Build the view's document with the caller's builder: copy mode with a
\   destination, exact measure mode with (0, 0).
: DOCV-DOCUMENT-CAPTURE
    ( root-key destination capacity builder widget -- bytes status )
    _DVK-PREFLIGHT? 0= IF 2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT THEN
    _DV-W ! _DVK-B ! _DVK-CAP ! _DVK-DST ! _DVK-ROOT !
    _DVK-DST @ _DVK-CAP @ _DVK-B @ USCOL-BUILDER-INIT
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _DV-DOC 0= IF 0 USCOL-S-UNAVAILABLE EXIT THEN
    _DV-H 0> 0= _DV-RGN RGN-W 0> 0= OR IF 0 USCOL-S-UNAVAILABLE EXIT THEN
    \ The last draw's counts and blocks, at this size.
    _DOCV-O-COUNTS-A _DV@ 0= IF 0 USCOL-S-UNAVAILABLE EXIT THEN
    _DOCV-O-COLS _DV@ _DV-RGN RGN-W <> IF 0 USCOL-S-UNAVAILABLE EXIT THEN
    _DOCV-O-HEIGHT _DV@ _DV-H <> IF 0 USCOL-S-UNAVAILABLE EXIT THEN
    _DOCV-O-END _DV@ _DV-TOP > 0= IF 0 USCOL-S-UNAVAILABLE EXIT THEN
    _DVK-ROOT @ 0 0 _DV-H _DV-RGN RGN-W _DVK-STATE _DVK-B @ USCOL-DOC-BEGIN
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    0 _DV-TOP-ROW _DVK-B @ USCOL-DOC-SHAPE
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _DOCV-O-END _DV@ _DV-TOP ?DO
        I _DVK-BLOCK! 0= IF 0 USCOL-S-UNAVAILABLE UNLOOP EXIT THEN
    LOOP
    _DVK-B @ USCOL-DOC-END DROP
    _DVK-B @ USCOL-BUILDER-FINISH ;

\ DOCV-DOCUMENT-MEASURE ( root-key builder widget -- bytes status )
: DOCV-DOCUMENT-MEASURE  ( root-key builder widget -- bytes status )
    >R >R 0 0 R> R> DOCV-DOCUMENT-CAPTURE ;

CREATE _DOCV-OWNED-END
_DOCV-OWNED-END _DOCV-OWNED-LIMIT !

\ =====================================================================
\  10. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _docv-guard

' DOCV-NEW       CONSTANT _docv-new-xt
' DOCV-OWNER!    CONSTANT _docv-owner-xt
' DOCV-DOCUMENT! CONSTANT _docv-document-xt
' DOCV-ROWS      CONSTANT _docv-rows-xt
' DOCV-SCROLL    CONSTANT _docv-scroll-xt
' DOCV-GO        CONSTANT _docv-go-xt
' DOCV-FOLLOW    CONSTANT _docv-follow-xt
' DOCV-SERVICE   CONSTANT _docv-service-xt
' DOCV-FREE      CONSTANT _docv-free-xt

: DOCV-NEW       _docv-new-xt      _docv-guard WITH-GUARD ;
: DOCV-OWNER!    _docv-owner-xt    _docv-guard WITH-GUARD ;
: DOCV-DOCUMENT! _docv-document-xt _docv-guard WITH-GUARD ;
: DOCV-ROWS      _docv-rows-xt     _docv-guard WITH-GUARD ;
: DOCV-SCROLL    _docv-scroll-xt   _docv-guard WITH-GUARD ;
: DOCV-GO        _docv-go-xt       _docv-guard WITH-GUARD ;
: DOCV-FOLLOW    _docv-follow-xt   _docv-guard WITH-GUARD ;
: DOCV-SERVICE   _docv-service-xt  _docv-guard WITH-GUARD ;
: DOCV-FREE      _docv-free-xt     _docv-guard WITH-GUARD ;
[THEN] [THEN]
