\ =====================================================================
\  akashic/tui/list.f — Scrollable List Widget
\ =====================================================================
\
\  A vertically scrollable list of rows, one or more columns wide, with
\  one selected row.  The widget does not own its rows: the caller gives
\  a row count and two callbacks,
\
\    key-xt    ( index widget -- key )
\    field-xt  ( index column widget -- addr len )
\
\  Rows show in index order.  A row's key names it from draw to draw: it
\  is nonzero and unique among the rows.  Columns are a caller-owned array
\  of LST-COLUMN-SIZE records: kind (LST-TEXT-COLUMN or LST-NUMBER-COLUMN),
\  label address, label length, and width in cells, 0 for a share of the
\  rest of the row.  With no columns the list has one unlabelled text
\  column.  When a column has a label, the region's first row shows the
\  labels.  Text columns are left-aligned and number columns
\  right-aligned, one cell apart.
\
\  An optional row callback, ( index widget -- flags ), marks rows with
\  LST-ROW-SECTION, LST-ROW-CHECKABLE and LST-ROW-CHECKED.  When the first
\  row is a section heading the list is in sections: a heading starts each
\  section, is drawn in bold across the row, and is never selected, and
\  the rows under it are indented.  A checkable row shows a check box
\  before its first column; the list reports a check to its check
\  callback and leaves the row's state to the caller.
\
\  Up/Down/PgUp/PgDn/Home/End move the selection past headings, Enter
\  opens it, Space checks it, a press selects the row under it, opens it
\  if it is already selected, or checks it on its check box, and the wheel
\  scrolls.  A renderer's item events select, open and check rows by key.
\
\  In LST-CARDS mode each row is a card of one line per column, its first
\  field on the first line and the others indented under it.  In
\  LST-UNTRUSTED mode the text comes from outside the application, so it
\  is drawn as DRW-TEXT-UNTRUSTED draws and published without direction
\  controls.  An optional style source, ( text-a text-u map index column
\  widget -- ), marks what each byte of a field means (text-style.f), as
\  a highlighter does; CELL draws each meaning in the palette's look, and
\  the item view carries it as style runs.
\
\  The list publishes its shown rows, and the selected row wherever it is,
\  as a renderer-neutral item view (semantic-collections.f): CARDS in card
\  mode, SECTIONS when it is in sections, a TABLE when it has more than one
\  column or a label, and a LIST otherwise.  Control characters, which CELL
\  shows as U+FFFD, are published as U+FFFD.
\
\  Descriptor (header + 15 cells = 160 bytes):
\    +0..+32  widget header   type=WDG-T-LIST
\    +40      count           Number of rows
\    +48      selected        Selected row, or -1
\    +56      scroll-top      First shown row
\    +64      select-xt       ( index widget -- ) the selection moved, or 0
\    +72      open-xt         ( index widget -- ) a row was opened, or 0
\    +80      key-xt          ( index widget -- key )
\    +88      field-xt        ( index column widget -- addr len )
\    +96      columns-a       Column records, or 0
\    +104     columns-n       Column count, or 0 for one text column
\    +112     instance        Nonzero allocation-lifetime instance token
\    +120     context         Caller's context cell
\    +128     row-xt          ( index widget -- flags ), or 0
\    +136     check-xt        ( index widget -- ) a row was checked, or 0
\    +144     mode            LST-CARDS, LST-UNTRUSTED
\    +152     style-xt        ( text-a text-u map index column widget -- ), or 0
\
\  Prefix: LST- (public), _LST- (internal)
\  Provider: akashic-tui-list
\  Dependencies: widget.f, draw.f, keys.f, semantic-collections.f

PROVIDED akashic-tui-list

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../keys.f
REQUIRE ../semantic-collections.f
REQUIRE ../style-palette.f
REQUIRE ../../text/text-style.f
REQUIRE ../../utils/memory-span.f

CREATE _LST-OWNED-START
VARIABLE _LST-OWNED-LIMIT
0 _LST-OWNED-LIMIT !

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40  CONSTANT _LST-O-COUNT
48  CONSTANT _LST-O-SEL
56  CONSTANT _LST-O-SCROLL
64  CONSTANT _LST-O-SEL-XT
72  CONSTANT _LST-O-OPEN-XT
80  CONSTANT _LST-O-KEY-XT
88  CONSTANT _LST-O-FIELD-XT
96  CONSTANT _LST-O-COLUMNS-A
104 CONSTANT _LST-O-COLUMNS-N
112 CONSTANT _LST-O-INSTANCE
120 CONSTANT _LST-O-CONTEXT
128 CONSTANT _LST-O-ROW-XT
136 CONSTANT _LST-O-CHECK-XT
144 CONSTANT _LST-O-MODE
152 CONSTANT _LST-O-STYLE-XT
160 CONSTANT _LST-DESC-SIZE

\ Column record.
 0 CONSTANT LST-COLUMN-KIND
 8 CONSTANT LST-COLUMN-LABEL-A
16 CONSTANT LST-COLUMN-LABEL-U
24 CONSTANT LST-COLUMN-WIDTH
32 CONSTANT LST-COLUMN-SIZE

\ Column kinds.  The list maps them onto its item view's column kinds, so
\ callers never name the collection model.
USCOL-IV-TEXT   CONSTANT LST-TEXT-COLUMN
USCOL-IV-NUMBER CONSTANT LST-NUMBER-COLUMN

\ Modes.
1 CONSTANT LST-CARDS            \ each row a card, one line per column
2 CONSTANT LST-UNTRUSTED        \ the text comes from outside the application

\ Row flags, from the caller's optional row callback.
1 CONSTANT LST-ROW-SECTION      \ a heading that starts a section
2 CONSTANT LST-ROW-CHECKABLE    \ the row has a check box
4 CONSTANT LST-ROW-CHECKED      \ its check box is checked

VARIABLE _LST-NEXT-INSTANCE
0 _LST-NEXT-INSTANCE !

: _LST-CLAIM-INSTANCE  ( -- token )
    _LST-NEXT-INSTANCE @ DUP -1 =
        IF DROP 1 ELSE 1+ DUP 0= IF DROP 1 THEN THEN
    DUP _LST-NEXT-INSTANCE ! ;

\ =====================================================================
\ 2. Rows and columns
\ =====================================================================

: _LST-KEY  ( index widget -- key )  DUP _LST-O-KEY-XT + @ EXECUTE ;
: _LST-FIELD  ( index column widget -- addr len )
    DUP _LST-O-FIELD-XT + @ EXECUTE ;

: _LST-NCOLS  ( widget -- n )  _LST-O-COLUMNS-N + @ 1 MAX ;

\ _LST-COLUMN ( column widget -- record|0 )   0 for the default column.
: _LST-COLUMN  ( column widget -- record|0 )
    DUP _LST-O-COLUMNS-N + @ 0= IF 2DROP 0 EXIT THEN
    _LST-O-COLUMNS-A + @ SWAP LST-COLUMN-SIZE * + ;

: _LST-COL-KIND  ( column widget -- kind )
    _LST-COLUMN ?DUP IF LST-COLUMN-KIND + @ ELSE LST-TEXT-COLUMN THEN ;

: _LST-COL-LABEL  ( column widget -- addr len )
    _LST-COLUMN ?DUP IF
        DUP LST-COLUMN-LABEL-A + @ SWAP LST-COLUMN-LABEL-U + @
    ELSE
        0 0
    THEN ;

: _LST-COL-FIXED  ( column widget -- width )
    _LST-COLUMN ?DUP IF LST-COLUMN-WIDTH + @ 0 MAX ELSE 0 THEN ;

: _LST-CARDS?  ( widget -- flag )  _LST-O-MODE + @ LST-CARDS AND 0<> ;
: _LST-UNTRUSTED?  ( widget -- flag )  _LST-O-MODE + @ LST-UNTRUSTED AND 0<> ;

: _LST-FLAGS  ( index widget -- flags )
    DUP _LST-O-ROW-XT + @ ?DUP IF EXECUTE ELSE 2DROP 0 THEN ;

: _LST-SECTION?  ( index widget -- flag )
    _LST-FLAGS LST-ROW-SECTION AND 0<> ;

\ _LST-SECTIONED? ( widget -- flag )   Is the first row a section heading?
\   Cards are never in sections.
: _LST-SECTIONED?  ( widget -- flag )
    DUP _LST-CARDS? IF DROP 0 EXIT THEN
    DUP _LST-O-COUNT + @ 0> 0= IF DROP 0 EXIT THEN
    0 SWAP _LST-SECTION? ;

\ Before an item's first column: an indent under a heading, then a check
\ box when the row has one.
2 CONSTANT _LST-INDENT
4 CONSTANT _LST-BOX-W

\ _LST-HEADER? ( widget -- flag )   Does any column have a label?
: _LST-HEADER?  ( widget -- flag )
    DUP _LST-O-COLUMNS-N + @ 0 ?DO
        I OVER _LST-COL-LABEL NIP IF DROP -1 UNLOOP EXIT THEN
    LOOP
    DROP 0 ;

\ Shown rows: the region's rows below the header row, if there is one.
: _LST-BODY-TOP  ( widget -- rows )  _LST-HEADER? IF 1 ELSE 0 THEN ;
: _LST-BODY-H  ( widget -- rows )
    DUP WDG-REGION RGN-H SWAP _LST-BODY-TOP - 0 MAX ;

\ _LST-LINES ( widget -- n )   Screen rows a row takes: a card's lines.
: _LST-LINES  ( widget -- n )
    DUP _LST-CARDS? IF _LST-NCOLS ELSE DROP 1 THEN ;

\ _LST-SHOWN ( widget -- n )   How many rows the body shows.
: _LST-SHOWN  ( widget -- n )  DUP _LST-BODY-H SWAP _LST-LINES / ;

\ Column geometry for one draw: fixed columns keep their widths and the
\ rest of the row, less one-cell gaps, is shared among width-0 columns.
VARIABLE _LST-G-W
VARIABLE _LST-G-FLEX
VARIABLE _LST-G-FLEXN
VARIABLE _LST-G-LAST
VARIABLE _LST-G-X

: _LST-GEOMETRY  ( widget -- )
    DUP _LST-G-W !
    0 _LST-G-FLEXN ! -1 _LST-G-LAST !
    DUP WDG-REGION RGN-W OVER _LST-NCOLS 1- -
    OVER _LST-NCOLS 0 DO
        I 2 PICK _LST-COL-FIXED ?DUP IF
            -
        ELSE
            1 _LST-G-FLEXN +! I _LST-G-LAST !
        THEN
    LOOP
    0 MAX _LST-G-FLEX ! DROP ;

\ _LST-COL-WIDTH ( column -- width )
\   A fixed column's width, or an equal share of the flexible width, the
\   last flexible column taking what division leaves over.
: _LST-COL-WIDTH  ( column -- width )
    DUP _LST-G-W @ _LST-COL-FIXED ?DUP IF NIP EXIT THEN
    _LST-G-FLEX @ _LST-G-FLEXN @ /
    SWAP _LST-G-LAST @ = IF
        DROP _LST-G-FLEX @ _LST-G-FLEX @ _LST-G-FLEXN @ / _LST-G-FLEXN @ 1- * -
    THEN ;

\ =====================================================================
\ 3. Selection and scrolling
\ =====================================================================

\ _LST-SHOW ( index widget -- )   Scroll so a row is shown.  When no row
\   fits, the view starts at it.
: _LST-SHOW  ( index widget -- )
    >R
    DUP 0< IF DROP R> DROP EXIT THEN
    DUP R@ _LST-O-SCROLL + @ < IF R> _LST-O-SCROLL + ! EXIT THEN
    R@ _LST-SHOWN 0= IF R> _LST-O-SCROLL + ! EXIT THEN
    R@ _LST-SHOWN
    2DUP R@ _LST-O-SCROLL + @ + < IF 2DROP R> DROP EXIT THEN
    - 1+ 0 MAX R> _LST-O-SCROLL + ! ;

VARIABLE _LST-SK-DIR

\ _LST-SEEK ( index dir widget -- index|-1 )
\   The first row from INDEX, stepping by DIR, that is not a heading.
: _LST-SEEK  ( index dir widget -- index|-1 )
    >R _LST-SK-DIR !
    BEGIN
        DUP 0< OVER R@ _LST-O-COUNT + @ < 0= OR IF
            DROP R> DROP -1 EXIT
        THEN
        DUP R@ _LST-SECTION? 0= IF R> DROP EXIT THEN
        _LST-SK-DIR @ +
    AGAIN ;

\ _LST-SEEK-NEAR ( index dir widget -- index|-1 )
\   Seek by DIR, and the other way when there is no row that way.
: _LST-SEEK-NEAR  ( index dir widget -- index|-1 )
    >R 2DUP R@ _LST-SEEK DUP 0< 0= IF NIP NIP R> DROP EXIT THEN
    DROP NEGATE R> _LST-SEEK ;

\ _LST-SETTLE ( widget -- )
\   Keep the selection on a row that is not a heading, and the scroll
\   within the rows.
: _LST-SETTLE  ( widget -- )
    DUP _LST-O-COUNT + @ 0 MAX OVER _LST-O-COUNT + !
    DUP _LST-O-COUNT + @ 0= IF
        -1 OVER _LST-O-SEL + !
    ELSE
        DUP _LST-O-SEL + @ OVER _LST-O-COUNT + @ 1- MIN 0 MAX
            OVER _LST-O-SEL + !
        DUP _LST-O-SEL + @ OVER _LST-SECTION? IF
            DUP _LST-O-SEL + @ 1 2 PICK _LST-SEEK-NEAR
                OVER _LST-O-SEL + !
        THEN
    THEN
    DUP _LST-O-COUNT + @ OVER _LST-SHOWN - 0 MAX
    OVER _LST-O-SCROLL + @ MIN 0 MAX
    SWAP _LST-O-SCROLL + ! ;

\ _LST-SELECT-ROW! ( index widget -- )
\   Select a row that is not a heading, show it, report a change, and
\   mark dirty.
: _LST-SELECT-ROW!  ( index widget -- )
    2DUP _LST-SHOW
    2DUP _LST-O-SEL + @ <> IF
        2DUP _LST-O-SEL + !
        DUP _LST-O-SEL-XT + @ ?DUP IF >R 2DUP R> EXECUTE THEN
    THEN
    NIP WDG-DIRTY ;

\ _LST-SELECT-DIR! ( index dir widget -- )
\   Select the nearest row to INDEX, clamped, that is not a heading,
\   looking by DIR first.
: _LST-SELECT-DIR!  ( index dir widget -- )
    >R
    R@ _LST-O-COUNT + @ 0= IF 2DROP R> DROP EXIT THEN
    SWAP R@ _LST-O-COUNT + @ 1- MIN 0 MAX SWAP
    R@ _LST-SEEK-NEAR DUP 0< IF DROP R> DROP EXIT THEN
    R> _LST-SELECT-ROW! ;

: _LST-SELECT!  ( index widget -- )  1 SWAP _LST-SELECT-DIR! ;

\ _LST-CHECK ( index widget -- )   Report a check of a checkable row.
: _LST-CHECK  ( index widget -- )
    2DUP _LST-FLAGS LST-ROW-CHECKABLE AND 0= IF 2DROP EXIT THEN
    DUP _LST-O-CHECK-XT + @ ?DUP IF >R 2DUP R> EXECUTE THEN
    NIP WDG-DIRTY ;

\ _LST-OPEN ( widget -- )   Open the selected row.
: _LST-OPEN  ( widget -- )
    DUP _LST-O-SEL + @ DUP 0< IF 2DROP EXIT THEN
    OVER _LST-O-OPEN-XT + @ ?DUP IF >R OVER R> EXECUTE ELSE DROP THEN
    WDG-DIRTY ;

3 CONSTANT _LST-WHEEL-ROWS

\ _LST-WHEEL-STEP ( widget -- rows )   A wheel step scrolls three screen
\   rows' worth of rows, and at least one card.
: _LST-WHEEL-STEP  ( widget -- rows )  _LST-WHEEL-ROWS SWAP _LST-LINES / 1 MAX ;

\ _LST-WHEEL ( rows widget -- )
\   Scroll the view by signed rows without moving the selection.
: _LST-WHEEL  ( rows widget -- )
    >R R@ _LST-O-SCROLL + @ +
    DUP 0< IF DROP 0 THEN
    R@ _LST-O-COUNT + @ R@ _LST-SHOWN -
    DUP 0< IF DROP 0 THEN
    2DUP > IF NIP ELSE DROP THEN
    R@ _LST-O-SCROLL + ! R> WDG-DIRTY ;

\ =====================================================================
\ 4. Draw
\ =====================================================================

VARIABLE _LST-DRW-W      \ widget during draw
VARIABLE _LST-DRW-ROW    \ local row being drawn
VARIABLE _LST-DRW-IDX    \ row index being drawn
VARIABLE _LST-DRW-COL    \ column being drawn
VARIABLE _LST-DRW-A
VARIABLE _LST-DRW-U
VARIABLE _LST-DRW-INSET  \ cells before the first column on this row
VARIABLE _LST-DRW-SECTIONED
VARIABLE _LST-DRW-FLAGS
VARIABLE _LST-DRW-FIELDS \ drawing a row's fields, not the labels

\ --- Styled and untrusted text ---

\ A field's style source fills one map, grown as a field needs it.
VARIABLE _LST-SM-A    0 _LST-SM-A !
VARIABLE _LST-SM-CAP  0 _LST-SM-CAP !
VARIABLE _LST-SF-A
VARIABLE _LST-SF-U
VARIABLE _LST-SF-I
VARIABLE _LST-SF-C
VARIABLE _LST-SF-W

\ _LST-STYLE-FIELD ( addr len index column widget -- styled? )
\   Mark what the field's bytes mean, when the list has a style source and
\   memory for the map.  A field without meanings stays plain.
: _LST-STYLE-FIELD  ( addr len index column widget -- styled? )
    _LST-SF-W ! _LST-SF-C ! _LST-SF-I ! _LST-SF-U ! _LST-SF-A !
    _LST-SF-W @ _LST-O-STYLE-XT + @ 0= IF 0 EXIT THEN
    _LST-SF-U @ 0= IF 0 EXIT THEN
    _LST-SF-U @ _LST-SM-CAP @ > IF
        _LST-SF-U @ 64 MAX DUP ALLOCATE IF 2DROP 0 EXIT THEN
        _LST-SM-A @ ?DUP IF FREE THEN
        _LST-SM-A ! _LST-SM-CAP !
    THEN
    _LST-SF-A @ _LST-SF-U @ _LST-SM-A @ _LST-SF-I @ _LST-SF-C @ _LST-SF-W @
    _LST-SF-W @ _LST-O-STYLE-XT + @ EXECUTE
    -1 ;

VARIABLE _LST-BASE-FG    \ the drawing style under a styled field
VARIABLE _LST-BASE-A
VARIABLE _LST-TX-STYLED  \ the field about to be drawn has meanings

\ _LST-LOOK ( byte -- fg attrs )   A styled field's look at that byte.
: _LST-LOOK  ( byte -- fg attrs )
    _LST-SM-A @ + C@ DUP TSTY-VALID? 0= IF
        DROP _LST-BASE-FG @ _LST-BASE-A @ EXIT
    THEN
    DUP SPAL-DEFAULT SPAL-FG@
    SWAP SPAL-DEFAULT SPAL-ATTRS@ _LST-BASE-A @ OR ;

\ _LST-PUT ( addr len row col -- )   Draw text as the list draws it:
\   styled when it has meanings, untrusted in LST-UNTRUSTED mode.
: _LST-PUT  ( addr len row col -- )
    _LST-TX-STYLED @ IF
        DRW-FG@ _LST-BASE-FG !  DRW-ATTR@ _LST-BASE-A !
        ['] _LST-LOOK
        _LST-DRW-W @ _LST-UNTRUSTED? IF
            DRW-TEXT-STYLED-UNTRUSTED
        ELSE
            DRW-TEXT-STYLED
        THEN
        EXIT
    THEN
    _LST-DRW-W @ _LST-UNTRUSTED? IF DRW-TEXT-UNTRUSTED ELSE DRW-TEXT THEN ;

\ --- Rows ---

\ _LST-DRW-WIDTH ( column -- width )   The first column gives up the inset.
: _LST-DRW-WIDTH  ( column -- width )
    DUP _LST-COL-WIDTH SWAP 0= IF _LST-DRW-INSET @ - 0 MAX THEN ;

\ One cell: the text, clipped to the column.
: _LST-DRAW-TEXT  ( -- )
    _LST-DRW-A @ _LST-DRW-U @ _LST-DRW-ROW @ _LST-G-X @
    _LST-DRW-COL @ _LST-G-W @ _LST-COL-KIND LST-NUMBER-COLUMN = IF
        _LST-DRW-COL @ _LST-DRW-WIDTH DRW-TEXT-RIGHT
    ELSE
        _LST-PUT
    THEN ;

: _LST-DRAW-CELL  ( addr len -- )
    2DUP _LST-DRW-U ! _LST-DRW-A !
    _LST-DRW-FIELDS @ IF
        _LST-DRW-IDX @ _LST-DRW-COL @ _LST-DRW-W @ _LST-STYLE-FIELD
    ELSE
        2DROP 0
    THEN _LST-TX-STYLED !
    ['] _LST-DRAW-TEXT
    _LST-DRW-ROW @ _LST-G-X @ 1
    _LST-DRW-COL @ _LST-DRW-WIDTH
    DRW-WITH-CLIP ;

\ _LST-DRAW-COLUMNS ( xt -- )   For each column, xt ( column -- addr len ),
\   drawn in that column on _LST-DRW-ROW, after the row's inset.
: _LST-DRAW-COLUMNS  ( xt -- )
    _LST-DRW-INSET @ _LST-G-X !
    _LST-DRW-W @ _LST-NCOLS 0 DO
        I _LST-DRW-COL !
        I OVER EXECUTE _LST-DRAW-CELL
        I _LST-DRW-WIDTH 1+ _LST-G-X +!
    LOOP
    DROP ;

: _LST-LABEL-CB  ( column -- addr len )  _LST-DRW-W @ _LST-COL-LABEL ;
: _LST-FIELD-CB  ( column -- addr len )
    _LST-DRW-IDX @ SWAP _LST-DRW-W @ _LST-FIELD ;

\ A heading: its first field in bold across the whole row.
: _LST-HEADING-TEXT  ( -- )
    _LST-DRW-A @ _LST-DRW-U @ _LST-DRW-ROW @ 0 _LST-PUT ;

: _LST-DRAW-HEADING  ( -- )
    _LST-DRW-IDX @ 0 _LST-DRW-W @ _LST-FIELD _LST-DRW-U ! _LST-DRW-A !
    0 _LST-TX-STYLED !
    CELL-A-BOLD DRW-ATTR!
    ['] _LST-HEADING-TEXT _LST-DRW-ROW @ 0 1
        _LST-DRW-W @ WDG-REGION RGN-W DRW-WITH-CLIP ;

\ _LST-BOX-COL ( widget -- col )   Where a row's check box starts.
: _LST-BOX-COL  ( widget -- col )
    DUP _LST-CARDS? IF DROP 1 EXIT THEN
    _LST-SECTIONED? IF _LST-INDENT ELSE 0 THEN ;

: _LST-DRAW-BOX  ( row col -- )
    0 _LST-TX-STYLED !
    _LST-DRW-FLAGS @ LST-ROW-CHECKED AND IF S" [x]" ELSE S" [ ]" THEN
    2SWAP DRW-TEXT ;

: _LST-DRAW-ITEM  ( -- )
    _LST-DRW-SECTIONED @ IF _LST-INDENT ELSE 0 THEN _LST-DRW-INSET !
    _LST-DRW-FLAGS @ LST-ROW-CHECKABLE AND IF
        _LST-DRW-ROW @ _LST-DRW-INSET @ _LST-DRAW-BOX
        _LST-BOX-W _LST-DRW-INSET +!
    THEN
    -1 _LST-DRW-FIELDS !
    ['] _LST-FIELD-CB _LST-DRAW-COLUMNS ;

\ A card: its first field on its first line, after its check box, and
\ each other field on a line of its own, indented under it.
2 CONSTANT _LST-CARD-INDENT
VARIABLE _LST-CD-X

: _LST-CARD-TEXT  ( -- )
    _LST-DRW-A @ _LST-DRW-U @ _LST-DRW-ROW @ _LST-CD-X @ _LST-PUT ;

: _LST-DRAW-CARD  ( -- )
    _LST-DRW-ROW @
    _LST-DRW-W @ _LST-NCOLS 0 DO
        DUP I + _LST-DRW-ROW !
        I 0= IF
            1 _LST-CD-X !
            _LST-DRW-FLAGS @ LST-ROW-CHECKABLE AND IF
                _LST-DRW-ROW @ 1 _LST-DRAW-BOX
                _LST-BOX-W 1+ _LST-CD-X !
            THEN
        ELSE
            _LST-CARD-INDENT 1+ _LST-CD-X !
        THEN
        _LST-DRW-IDX @ I _LST-DRW-W @ _LST-FIELD 2DUP _LST-DRW-U ! _LST-DRW-A !
        _LST-DRW-IDX @ I _LST-DRW-W @ _LST-STYLE-FIELD _LST-TX-STYLED !
        ['] _LST-CARD-TEXT _LST-DRW-ROW @ _LST-CD-X @ 1
            _LST-DRW-W @ WDG-REGION RGN-W _LST-CD-X @ - 0 MAX DRW-WITH-CLIP
    LOOP
    DROP ;

: _LST-DRAW  ( widget -- )
    DUP _LST-DRW-W !
    DUP _LST-SETTLE
    DUP _LST-GEOMETRY
    DUP _LST-SECTIONED? _LST-DRW-SECTIONED !
    DRW-STYLE-RESTORE
    32 0 0 3 PICK WDG-REGION RGN-H 4 PICK WDG-REGION RGN-W DRW-FILL-RECT
    DUP _LST-HEADER? IF
        0 _LST-DRW-ROW ! 0 _LST-DRW-INSET ! 0 _LST-DRW-FIELDS !
        CELL-A-BOLD DRW-ATTR!
        ['] _LST-LABEL-CB _LST-DRAW-COLUMNS
        DRW-STYLE-RESTORE
    THEN
    DUP _LST-SHOWN 0 ?DO
        DUP _LST-O-SCROLL + @ I + DUP _LST-DRW-IDX !
        OVER _LST-O-COUNT + @ < 0= IF LEAVE THEN
        DUP _LST-BODY-TOP I 2 PICK _LST-LINES * + _LST-DRW-ROW !
        _LST-DRW-IDX @ OVER _LST-FLAGS _LST-DRW-FLAGS !
        _LST-DRW-SECTIONED @ _LST-DRW-FLAGS @ LST-ROW-SECTION AND AND IF
            _LST-DRAW-HEADING
        ELSE
            _LST-DRW-IDX @ OVER _LST-O-SEL + @ = IF
                CELL-A-REVERSE DRW-ATTR!
                32 _LST-DRW-ROW @ 0 3 PICK _LST-LINES 4 PICK WDG-REGION RGN-W
                    DRW-FILL-RECT
            THEN
            DUP _LST-CARDS? IF _LST-DRAW-CARD ELSE _LST-DRAW-ITEM THEN
        THEN
        DRW-STYLE-RESTORE
    LOOP
    DROP ;

\ =====================================================================
\ 5. Handle
\ =====================================================================

VARIABLE _LST-HND-W   \ widget saved during handle

\ _LST-FIND-KEY ( key widget -- index|-1 )
\   A renderer names only rows it was sent: the shown rows and the
\   selected row.
VARIABLE _LST-FK-KEY
: _LST-FIND-KEY  ( key widget -- index|-1 )
    SWAP _LST-FK-KEY !
    DUP _LST-SETTLE
    DUP _LST-O-SEL + @ DUP 0< 0= IF
        DUP 2 PICK _LST-KEY _LST-FK-KEY @ = IF NIP EXIT THEN
    THEN DROP
    DUP _LST-SHOWN OVER _LST-O-COUNT + @ 2 PICK _LST-O-SCROLL + @ - MIN
    0 MAX 0 ?DO
        DUP _LST-O-SCROLL + @ I +
        DUP 2 PICK _LST-KEY _LST-FK-KEY @ = IF NIP UNLOOP EXIT THEN
        DROP
    LOOP
    DROP -1 ;

\ A heading is never selected, opened or checked.
: _LST-ITEM-EVENT  ( widget -- consumed? )
    KEY-MOUSE-ITEM-KEY @ OVER _LST-FIND-KEY
    DUP 0< IF 2DROP -1 EXIT THEN
    2DUP SWAP _LST-SECTION? IF 2DROP -1 EXIT THEN
    KEY-MOUSE-ITEM-ACTION @ CASE
        KEY-ITEM-SELECT OF OVER _LST-SELECT-ROW! ENDOF
        KEY-ITEM-OPEN OF OVER _LST-SELECT-ROW! DUP _LST-OPEN ENDOF
        KEY-ITEM-CHECK OF OVER _LST-CHECK ENDOF
        NIP
    ENDCASE
    DROP -1 ;

VARIABLE _LST-HND-COL    \ column of a press, relative to the region
VARIABLE _LST-HND-LINE   \ line of a press within its row's card

\ _LST-BOX-HIT? ( index widget -- flag )   Is the press on the row's box?
: _LST-BOX-HIT?  ( index widget -- flag )
    _LST-HND-LINE @ IF 2DROP 0 EXIT THEN
    2DUP _LST-FLAGS LST-ROW-CHECKABLE AND 0= IF 2DROP 0 EXIT THEN
    NIP _LST-BOX-COL _LST-HND-COL @ SWAP - _LST-BOX-W 1- U< ;

: _LST-POINTER  ( event widget -- consumed? )
    _LST-HND-W !
    DUP 8 + @ KEY-MOUSE-BUTTON CASE
        KEY-MOUSE-LEFT OF
            16 + @                          \ mods = row<<16 | col
            DUP 0xFFFF AND _LST-HND-W @ WDG-REGION RGN-COL - _LST-HND-COL !
            16 RSHIFT                       \ absolute row (0-based)
            _LST-HND-W @ WDG-REGION RGN-ROW -
            _LST-HND-W @ _LST-BODY-TOP -
            DUP 0< IF DROP -1 EXIT THEN      \ the header row
            _LST-HND-W @ _LST-LINES /MOD SWAP _LST-HND-LINE !
            _LST-HND-W @ _LST-O-SCROLL + @ +   \ row index
            DUP _LST-HND-W @ _LST-O-COUNT + @ < IF
                DUP _LST-HND-W @ _LST-SECTION? IF DROP -1 EXIT THEN
                DUP _LST-HND-W @ _LST-BOX-HIT? IF
                    _LST-HND-W @ _LST-CHECK -1 EXIT
                THEN
                \ A press on the selected row opens it, as the second press
                \ of a double press does in a rich terminal.
                DUP _LST-HND-W @ _LST-O-SEL + @ = IF
                    DROP _LST-HND-W @ _LST-OPEN -1 EXIT
                THEN
                _LST-HND-W @ _LST-SELECT-ROW! -1 EXIT
            THEN
            DROP -1 EXIT                    \ in the list, past its rows
        ENDOF
        KEY-MOUSE-SCROLL-UP OF
            DROP _LST-HND-W @ _LST-WHEEL-STEP NEGATE _LST-HND-W @ _LST-WHEEL -1 EXIT
        ENDOF
        KEY-MOUSE-SCROLL-DN OF
            DROP _LST-HND-W @ _LST-WHEEL-STEP _LST-HND-W @ _LST-WHEEL -1 EXIT
        ENDOF
        KEY-MOUSE-ITEM OF DROP _LST-HND-W @ _LST-ITEM-EVENT EXIT ENDOF
    ENDCASE
    DROP 0 ;

: _LST-KEYS  ( code widget -- consumed? )
    DUP _LST-SETTLE
    DUP _LST-O-COUNT + @ 0= IF 2DROP 0 EXIT THEN
    _LST-HND-W !
    CASE
        KEY-UP OF
            _LST-HND-W @ _LST-O-SEL + @ 1- -1 _LST-HND-W @ _LST-SELECT-DIR! -1
        ENDOF
        KEY-DOWN OF
            _LST-HND-W @ _LST-O-SEL + @ 1+ 1 _LST-HND-W @ _LST-SELECT-DIR! -1
        ENDOF
        KEY-PGUP OF
            _LST-HND-W @ _LST-O-SEL + @ _LST-HND-W @ _LST-SHOWN -
            -1 _LST-HND-W @ _LST-SELECT-DIR! -1
        ENDOF
        KEY-PGDN OF
            _LST-HND-W @ _LST-O-SEL + @ _LST-HND-W @ _LST-SHOWN +
            1 _LST-HND-W @ _LST-SELECT-DIR! -1
        ENDOF
        KEY-HOME OF 0 1 _LST-HND-W @ _LST-SELECT-DIR! -1 ENDOF
        KEY-END OF
            _LST-HND-W @ _LST-O-COUNT + @ 1- -1 _LST-HND-W @ _LST-SELECT-DIR! -1
        ENDOF
        KEY-ENTER OF _LST-HND-W @ _LST-OPEN -1 ENDOF
        0 SWAP
    ENDCASE ;

\ _LST-CHAR ( event widget -- consumed? )   Space checks a checkable row.
: _LST-CHAR  ( event widget -- consumed? )
    >R
    DUP 16 + @ IF DROP R> DROP 0 EXIT THEN
    8 + @ BL <> IF R> DROP 0 EXIT THEN
    R@ _LST-SETTLE
    R@ _LST-O-SEL + @ DUP 0< IF DROP R> DROP 0 EXIT THEN
    DUP R@ _LST-FLAGS LST-ROW-CHECKABLE AND 0= IF DROP R> DROP 0 EXIT THEN
    R> _LST-CHECK -1 ;

\ _LST-HANDLE ( event widget -- consumed? )
: _LST-HANDLE  ( event widget -- consumed? )
    OVER @ KEY-T-MOUSE = IF _LST-POINTER EXIT THEN
    OVER @ KEY-T-SPECIAL = IF SWAP 8 + @ SWAP _LST-KEYS EXIT THEN
    OVER @ KEY-T-CHAR = IF _LST-CHAR EXIT THEN
    2DROP 0 ;

\ =====================================================================
\ 6. Storage authority
\ =====================================================================

: _LST-GENUINE?  ( widget -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _LST-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _WDG-O-TYPE + @ WDG-T-LIST <> IF DROP 0 EXIT THEN
    DUP _WDG-O-DRAW-XT + @ ['] _LST-DRAW <> IF DROP 0 EXIT THEN
    DUP _WDG-O-HANDLE-XT + @ ['] _LST-HANDLE <> IF DROP 0 EXIT THEN
    DUP _LST-O-INSTANCE + @ 0= IF DROP 0 EXIT THEN
    WDG-REGION DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    RGN-SIZE MSPAN-NONWRAPPING? ;

\ Pure and deliberately unguarded: a caller span against the module's
\ mutable scratch.
: LST-STORAGE-DISJOINT?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _LST-OWNED-LIMIT @ DUP _LST-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _LST-OWNED-START - >R
    _LST-OWNED-START R> MSPAN-OVERLAP? 0= ;

VARIABLE _LST-SD-A
VARIABLE _LST-SD-U
VARIABLE _LST-SD-W

\ LST-ITEM-VIEW-STORAGE-DISJOINT? ( address bytes widget -- flag )
\   A caller span against the module and one live list's descriptor,
\   region, and column records.
: LST-ITEM-VIEW-STORAGE-DISJOINT?  ( address bytes widget -- flag )
    >R
    2DUP LST-STORAGE-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    _LST-SD-U ! _LST-SD-A ! R> _LST-SD-W !
    _LST-SD-W @ _LST-GENUINE? 0= IF 0 EXIT THEN
    _LST-SD-U @ 0= IF -1 EXIT THEN
    _LST-SD-A @ _LST-SD-U @
        _LST-SD-W @ _LST-DESC-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _LST-SD-A @ _LST-SD-U @
        _LST-SD-W @ WDG-REGION RGN-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _LST-SD-W @ _LST-O-COLUMNS-N + @ ?DUP IF
        LST-COLUMN-SIZE *
        _LST-SD-A @ _LST-SD-U @ ROT _LST-SD-W @ _LST-O-COLUMNS-A + @ SWAP
            MSPAN-OVERLAP? IF 0 EXIT THEN
    THEN
    -1 ;

\ =====================================================================
\ 7. Item view capture
\ =====================================================================

VARIABLE _LST-C-ROOT
VARIABLE _LST-C-DST
VARIABLE _LST-C-CAP
VARIABLE _LST-C-BUILDER
VARIABLE _LST-C-W
VARIABLE _LST-C-H
VARIABLE _LST-C-WIDTH
VARIABLE _LST-C-FIRST
VARIABLE _LST-C-COUNT
VARIABLE _LST-C-SEL

VARIABLE _LST-C-SECTIONED
VARIABLE _LST-C-PARENT     \ key of the heading over the rows being captured
VARIABLE _LST-CR-I
VARIABLE _LST-CR-F

\ _LST-C-SECTION-OF ( index -- key )   The key of the heading over a row.
: _LST-C-SECTION-OF  ( index -- key )
    BEGIN DUP 0< 0= WHILE
        DUP _LST-C-W @ _LST-SECTION? IF _LST-C-W @ _LST-KEY EXIT THEN
        1-
    REPEAT
    DROP 0 ;

\ _LST-C-SECTION-FROM ( index -- )   Start a run of carried rows.
: _LST-C-SECTION-FROM  ( index -- )
    _LST-C-SECTIONED @ IF _LST-C-SECTION-OF _LST-C-PARENT ! ELSE DROP THEN ;

\ A field is published as CELL shows it: each control character as
\ U+FFFD, and in LST-UNTRUSTED mode each explicit embedding, override or
\ isolate as U+200B, which is invisible and does not reorder.  Both keep
\ the scalar count, so style runs taken from the source still fit.
VARIABLE _LST-CF-A
VARIABLE _LST-CF-U
VARIABLE _LST-CF-COL
VARIABLE _LST-CF-DST
VARIABLE _LST-CF-O
VARIABLE _LST-CF-I

: _LST-CONTROL?  ( c -- flag )  DUP BL < SWAP 127 = OR ;

\ _LST-BIDI-CONTROL? ( addr -- flag )   Do the three bytes there encode
\   U+202A..U+202E or U+2066..U+2069?
: _LST-BIDI-CONTROL?  ( addr -- flag )
    DUP C@ 0xE2 <> IF DROP 0 EXIT THEN
    DUP 1+ C@ DUP 0x80 = IF DROP 2 + C@ 0xAA 0xAF WITHIN EXIT THEN
    0x81 = IF 2 + C@ 0xA6 0xAA WITHIN EXIT THEN
    DROP 0 ;

: _LST-CONTROLS  ( addr len -- n )
    0 -ROT 0 ?DO DUP I + C@ _LST-CONTROL? IF SWAP 1+ SWAP THEN LOOP DROP ;

: _LST-PUT-BYTE  ( c -- )  _LST-CF-DST @ _LST-CF-O @ + C! 1 _LST-CF-O +! ;

: _LST-COPY-FIELD  ( -- )
    0 _LST-CF-O ! 0 _LST-CF-I !
    BEGIN _LST-CF-I @ _LST-CF-U @ < WHILE
        _LST-CF-A @ _LST-CF-I @ + C@
        DUP _LST-CONTROL? IF
            DROP 0xEF _LST-PUT-BYTE 0xBF _LST-PUT-BYTE 0xBD _LST-PUT-BYTE
            1 _LST-CF-I +!
        ELSE
            _LST-C-W @ _LST-UNTRUSTED? _LST-CF-I @ 2 + _LST-CF-U @ < AND IF
                _LST-CF-A @ _LST-CF-I @ + _LST-BIDI-CONTROL?
            ELSE 0 THEN
            IF
                DROP 0xE2 _LST-PUT-BYTE 0x80 _LST-PUT-BYTE 0x8B _LST-PUT-BYTE
                3 _LST-CF-I +!
            ELSE
                _LST-PUT-BYTE 1 _LST-CF-I +!
            THEN
        THEN
    REPEAT ;

: _LST-C-RUN  ( start length meaning -- ok? )
    _LST-C-BUILDER @ USCOL-ITEMS-FIELD-RUN DROP -1 ;

: _LST-CAPTURE-FIELD  ( addr len column -- )
    _LST-CF-COL ! _LST-CF-U ! _LST-CF-A !
    _LST-CF-U @ _LST-CF-A @ _LST-CF-U @ _LST-CONTROLS 2* +
    _LST-C-BUILDER @ USCOL-ITEMS-FIELD-BEGIN DROP
    DUP _LST-CF-DST ! IF _LST-COPY-FIELD THEN
    _LST-CF-A @ _LST-CF-U @ _LST-CR-I @ _LST-CF-COL @ _LST-C-W @
    _LST-STYLE-FIELD IF
        _LST-CF-A @ _LST-CF-U @ _LST-SM-A @ ['] _LST-C-RUN TSTY-RUNS DROP
    THEN
    _LST-C-BUILDER @ USCOL-ITEMS-FIELD-END DROP ;

: _LST-CAPTURE-FIELDS  ( n -- )
    0 ?DO
        _LST-CR-I @ I _LST-C-W @ _LST-FIELD I _LST-CAPTURE-FIELD
    LOOP ;

: _LST-C-ITEM-STATE  ( -- state )
    0
    _LST-CR-I @ _LST-C-SEL @ = IF USCOL-IV-SELECTED OR THEN
    _LST-CR-F @ LST-ROW-CHECKABLE AND IF
        USCOL-IV-CHECKABLE OR
        _LST-CR-F @ LST-ROW-CHECKED AND IF USCOL-IV-CHECKED OR THEN
    THEN ;

\ The builder latches its first failure, which USCOL-BUILDER-FINISH
\ reports, so building a row does not stop on one.  In sections a heading
\ carries its first field and every other row names its heading.
: _LST-CAPTURE-ROW  ( index -- )
    DUP _LST-CR-I !
    _LST-C-W @ _LST-FLAGS _LST-CR-F !
    _LST-C-SECTIONED @ _LST-CR-F @ LST-ROW-SECTION AND AND IF
        _LST-CR-I @ _LST-C-W @ _LST-KEY DUP _LST-C-PARENT !
        0 _LST-CR-I @ 0 0 USCOL-IV-SECTION
        _LST-C-BUILDER @ USCOL-ITEMS-ITEM-BEGIN DROP
        1 _LST-CAPTURE-FIELDS
    ELSE
        _LST-CR-I @ _LST-C-W @ _LST-KEY
        _LST-C-SECTIONED @ IF _LST-C-PARENT @ 1 ELSE 0 0 THEN
        _LST-CR-I @ SWAP
        _LST-C-ITEM-STATE USCOL-IV-ITEM
        _LST-C-BUILDER @ USCOL-ITEMS-ITEM-BEGIN DROP
        _LST-C-W @ _LST-NCOLS _LST-CAPTURE-FIELDS
    THEN
    _LST-C-BUILDER @ USCOL-ITEMS-ITEM-END DROP ;

: _LST-CAPTURE-PREFLIGHT?  ( root destination capacity builder widget -- flag )
    DUP _LST-GENUINE? 0= IF 0 EXIT THEN
    4 PICK 0= IF 0 EXIT THEN
    3 PICK 3 PICK 2 PICK LST-ITEM-VIEW-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    1 PICK USCOL-BUILDER-SIZE 2 PICK
        LST-ITEM-VIEW-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    1 PICK USCOL-BUILDER-SIZE USCOL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    3 PICK 3 PICK USCOL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    -1 ;

: _LST-C-ROOT-STATE  ( -- state )
    0
    _LST-C-W @ WDG-VISIBLE? IF USCOL-STATE-VISIBLE OR THEN
    _LST-C-W @ WDG-DISABLED? 0= IF USCOL-STATE-ENABLED OR THEN
    _LST-C-W @ WDG-FOCUSED?
    _LST-C-W @ WDG-VISIBLE? AND
    _LST-C-W @ WDG-DISABLED? 0= AND IF USCOL-STATE-SELECTED OR THEN ;

: _LST-C-ROLE  ( -- role )
    _LST-C-W @ _LST-CARDS? IF USCOL-IV-CARDS EXIT THEN
    _LST-C-SECTIONED @ IF USCOL-IV-SECTIONS EXIT THEN
    _LST-C-W @ _LST-NCOLS 1 > _LST-C-W @ _LST-HEADER? OR
    IF USCOL-IV-TABLE ELSE USCOL-IV-LIST THEN ;

\ LST-ITEM-VIEW-CAPTURE
\   ( root-key destination capacity builder widget -- bytes status )
\   Build the list's item view with the caller's builder: copy mode with a
\   destination, exact measure mode with (0, 0).
: LST-ITEM-VIEW-CAPTURE
    ( root-key destination capacity builder widget -- bytes status )
    _LST-CAPTURE-PREFLIGHT? 0= IF
        2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT
    THEN
    _LST-C-W ! _LST-C-BUILDER ! _LST-C-CAP !
    _LST-C-DST ! _LST-C-ROOT !
    _LST-C-DST @ _LST-C-CAP @ _LST-C-BUILDER @ USCOL-BUILDER-INIT
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _LST-C-W @ WDG-REGION RGN-H DUP 0> 0= IF
        DROP 0 USCOL-S-UNAVAILABLE EXIT
    THEN _LST-C-H !
    _LST-C-W @ WDG-REGION RGN-W DUP 0> 0= IF
        DROP 0 USCOL-S-UNAVAILABLE EXIT
    THEN _LST-C-WIDTH !
    _LST-C-W @ _LST-SHOWN 0= IF 0 USCOL-S-UNAVAILABLE EXIT THEN
    _LST-C-W @ _LST-SETTLE
    _LST-C-W @ _LST-O-SCROLL + @ _LST-C-FIRST !
    _LST-C-W @ _LST-O-COUNT + @ _LST-C-FIRST @ -
        _LST-C-W @ _LST-SHOWN MIN 0 MAX _LST-C-COUNT !
    _LST-C-W @ _LST-O-SEL + @ _LST-C-SEL !
    _LST-C-W @ _LST-SECTIONED? _LST-C-SECTIONED !
    _LST-C-ROOT @ 0 0 _LST-C-H @ _LST-C-WIDTH @ _LST-C-ROOT-STATE
        _LST-C-BUILDER @ USCOL-ITEMS-BEGIN
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _LST-C-ROLE 0 _LST-C-W @ _LST-O-COUNT + @ _LST-C-FIRST @ _LST-C-COUNT @
        _LST-C-BUILDER @ USCOL-ITEMS-SHAPE
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _LST-C-W @ _LST-NCOLS 0 DO
        I _LST-C-W @ _LST-COL-KIND
        I _LST-C-W @ _LST-COL-LABEL
        _LST-C-BUILDER @ USCOL-ITEMS-COLUMN
        DUP USCOL-S-OK <> IF 0 SWAP UNLOOP EXIT THEN DROP
    LOOP
    \ Carried rows in index order: a selection above the view, the view,
    \ and a selection below it.
    _LST-C-SEL @ DUP 0< 0= SWAP _LST-C-FIRST @ < AND IF
        _LST-C-SEL @ DUP _LST-C-SECTION-FROM _LST-CAPTURE-ROW
    THEN
    _LST-C-FIRST @ _LST-C-SECTION-FROM
    _LST-C-COUNT @ 0 ?DO
        _LST-C-FIRST @ I + _LST-CAPTURE-ROW
    LOOP
    _LST-C-SEL @ _LST-C-FIRST @ _LST-C-COUNT @ + < 0= IF
        _LST-C-SEL @ DUP _LST-C-SECTION-FROM _LST-CAPTURE-ROW
    THEN
    _LST-C-BUILDER @ USCOL-ITEMS-END DROP
    _LST-C-BUILDER @ USCOL-BUILDER-FINISH ;

\ LST-ITEM-VIEW-MEASURE ( root-key builder widget -- bytes status )
: LST-ITEM-VIEW-MEASURE  ( root-key builder widget -- bytes status )
    >R >R 0 0 R> R> LST-ITEM-VIEW-CAPTURE ;

\ =====================================================================
\ 8. Constructor
\ =====================================================================

\ LST-NEW ( rgn key-xt field-xt -- widget )
\   An empty list with one text column; LST-ROWS! gives it rows.
: LST-NEW  ( rgn key-xt field-xt -- widget )
    >R >R                                  \ R: field key ; ( rgn )
    _LST-DESC-SIZE ALLOCATE
    0<> ABORT" LST-NEW: alloc failed"      \ ( rgn addr )
    DUP _LST-DESC-SIZE 0 FILL
    WDG-T-LIST     OVER _WDG-O-TYPE      + !
    SWAP           OVER _WDG-O-REGION    + !
    ['] _LST-DRAW  OVER _WDG-O-DRAW-XT   + !
    ['] _LST-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                   OVER _WDG-O-FLAGS     + !
    R>             OVER _LST-O-KEY-XT    + !
    R>             OVER _LST-O-FIELD-XT  + !
    -1             OVER _LST-O-SEL       + !
    _LST-CLAIM-INSTANCE OVER _LST-O-INSTANCE + ! ;

\ =====================================================================
\ 9. Public API
\ =====================================================================

\ LST-ROWS! ( count widget -- )
\   The rows changed: there are now COUNT, the first row that is not a
\   heading is selected, and the view is at the top.
: LST-ROWS!  ( count widget -- )
    >R
    0 MAX R@ _LST-O-COUNT + !
    -1 R@ _LST-O-SEL + !
    R@ _LST-O-COUNT + @ IF 0 1 R@ _LST-SEEK R@ _LST-O-SEL + ! THEN
    0 R@ _LST-O-SCROLL + !
    R> WDG-DIRTY ;

\ LST-COUNT ( widget -- count )
: LST-COUNT  ( widget -- count )  _LST-O-COUNT + @ ;

\ LST-COLUMNS! ( columns-a count widget -- )
\   Use COUNT caller-owned column records; 0 0 for one text column.
: LST-COLUMNS!  ( columns-a count widget -- )
    >R
    DUP 0> IF R@ _LST-O-COLUMNS-N + ! ELSE DROP 0 R@ _LST-O-COLUMNS-N + ! THEN
    R@ _LST-O-COLUMNS-A + !
    R@ _LST-SETTLE
    R> WDG-DIRTY ;

\ LST-SELECT ( index widget -- )
\   Select a row and show it, or the next row that is not a heading.  The
\   selection callback runs if it moved.
: LST-SELECT  ( index widget -- )
    _LST-SELECT! ;

\ LST-SELECTED ( widget -- index )   The selected row, or -1.
: LST-SELECTED  ( widget -- index )
    DUP _LST-SETTLE _LST-O-SEL + @ ;

\ LST-ON-SELECT ( xt widget -- )   Callback ( index widget -- ).
: LST-ON-SELECT  ( xt widget -- )
    _LST-O-SEL-XT + ! ;

\ LST-ON-OPEN ( xt widget -- )   Callback ( index widget -- ) when the
\   selected row is opened by Enter or a renderer's OPEN.
: LST-ON-OPEN  ( xt widget -- )
    _LST-O-OPEN-XT + ! ;

\ LST-ROW-FLAGS! ( xt widget -- )   Row callback ( index widget -- flags ),
\   LST-ROW-SECTION, LST-ROW-CHECKABLE and LST-ROW-CHECKED, or 0 for none.
: LST-ROW-FLAGS!  ( xt widget -- )
    TUCK _LST-O-ROW-XT + ! DUP _LST-SETTLE WDG-DIRTY ;

\ LST-MODE! ( mode widget -- )   LST-CARDS and LST-UNTRUSTED, or 0.
: LST-MODE!  ( mode widget -- )
    TUCK _LST-O-MODE + ! DUP _LST-SETTLE WDG-DIRTY ;

\ LST-STYLE! ( xt widget -- )   Field style source ( text-a text-u map
\   index column widget -- ), or 0 for plain text.
: LST-STYLE!  ( xt widget -- )
    TUCK _LST-O-STYLE-XT + ! WDG-DIRTY ;

\ LST-ON-CHECK ( xt widget -- )   Callback ( index widget -- ) when a
\   checkable row is checked or unchecked.  The caller changes the row.
: LST-ON-CHECK  ( xt widget -- )
    _LST-O-CHECK-XT + ! ;

\ LST-CONTEXT! ( context widget -- ) and LST-CONTEXT@ ( widget -- context )
: LST-CONTEXT!  ( context widget -- )  _LST-O-CONTEXT + ! ;
: LST-CONTEXT@  ( widget -- context )  _LST-O-CONTEXT + @ ;

\ LST-SCROLL-TO ( index widget -- )   Scroll so a row is shown.
: LST-SCROLL-TO  ( index widget -- )
    TUCK _LST-SHOW WDG-DIRTY ;

\ LST-SCROLL-INFO ( widget -- content-h offset visible-h )
\   Return scroll parameters for the scroll container.
: LST-SCROLL-INFO  ( widget -- content-h offset visible-h )
    DUP _LST-SETTLE
    DUP _LST-O-COUNT + @
    OVER _LST-O-SCROLL + @
    ROT _LST-SHOWN ;

\ LST-SCROLL-SET ( offset widget -- )
\   Set scroll-top directly (clamped).  Does NOT change selection.
: LST-SCROLL-SET  ( offset widget -- )
    >R
    R@ _LST-O-COUNT + @ R@ _LST-SHOWN -
    DUP 0< IF DROP 0 THEN              \ max scroll
    MIN  0 MAX                          \ clamp 0..max
    R@ _LST-O-SCROLL + !
    R> WDG-DIRTY ;

: LST-INSTANCE@  ( widget -- token )
    DUP _LST-GENUINE? 0= IF DROP 0 EXIT THEN
    _LST-O-INSTANCE + @ ;

\ LST-FREE ( widget -- )
: LST-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\ 10. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _lst-guard

' LST-NEW         CONSTANT _lst-new-xt
' LST-ROWS!       CONSTANT _lst-rows-xt
' LST-COUNT       CONSTANT _lst-count-xt
' LST-COLUMNS!    CONSTANT _lst-columns-xt
' LST-SELECT      CONSTANT _lst-select-xt
' LST-SELECTED    CONSTANT _lst-selected-xt
' LST-ON-SELECT   CONSTANT _lst-onsel-xt
' LST-ON-OPEN     CONSTANT _lst-onopen-xt
' LST-ROW-FLAGS!  CONSTANT _lst-rowflags-xt
' LST-ON-CHECK    CONSTANT _lst-oncheck-xt
' LST-MODE!       CONSTANT _lst-mode-xt
' LST-STYLE!      CONSTANT _lst-style-xt
' LST-CONTEXT!    CONSTANT _lst-context-s-xt
' LST-CONTEXT@    CONSTANT _lst-context-g-xt
' LST-SCROLL-TO   CONSTANT _lst-scrollto-xt
' LST-INSTANCE@   CONSTANT _lst-instance-xt
' LST-ITEM-VIEW-CAPTURE CONSTANT _lst-capture-xt
' LST-ITEM-VIEW-MEASURE CONSTANT _lst-measure-xt
' LST-ITEM-VIEW-STORAGE-DISJOINT? CONSTANT _lst-disjoint-q-xt
' LST-FREE        CONSTANT _lst-free-xt

: LST-NEW         _lst-new-xt       _lst-guard WITH-GUARD ;
: LST-ROWS!       _lst-rows-xt      _lst-guard WITH-GUARD ;
: LST-COUNT       _lst-count-xt     _lst-guard WITH-GUARD ;
: LST-COLUMNS!    _lst-columns-xt   _lst-guard WITH-GUARD ;
: LST-SELECT      _lst-select-xt    _lst-guard WITH-GUARD ;
: LST-SELECTED    _lst-selected-xt  _lst-guard WITH-GUARD ;
: LST-ON-SELECT   _lst-onsel-xt     _lst-guard WITH-GUARD ;
: LST-ON-OPEN     _lst-onopen-xt    _lst-guard WITH-GUARD ;
: LST-ROW-FLAGS!  _lst-rowflags-xt  _lst-guard WITH-GUARD ;
: LST-ON-CHECK    _lst-oncheck-xt   _lst-guard WITH-GUARD ;
: LST-MODE!       _lst-mode-xt      _lst-guard WITH-GUARD ;
: LST-STYLE!      _lst-style-xt     _lst-guard WITH-GUARD ;
: LST-CONTEXT!    _lst-context-s-xt _lst-guard WITH-GUARD ;
: LST-CONTEXT@    _lst-context-g-xt _lst-guard WITH-GUARD ;
: LST-SCROLL-TO   _lst-scrollto-xt  _lst-guard WITH-GUARD ;
: LST-INSTANCE@   _lst-instance-xt  _lst-guard WITH-GUARD ;
: LST-ITEM-VIEW-CAPTURE _lst-capture-xt _lst-guard WITH-GUARD ;
: LST-ITEM-VIEW-MEASURE _lst-measure-xt _lst-guard WITH-GUARD ;
: LST-ITEM-VIEW-STORAGE-DISJOINT?
    _lst-disjoint-q-xt _lst-guard WITH-GUARD ;
: LST-FREE        _lst-free-xt      _lst-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _LST-OWNED-END
_LST-OWNED-END _LST-OWNED-LIMIT !
