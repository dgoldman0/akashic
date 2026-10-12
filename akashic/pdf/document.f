\ =================================================================
\  document.f  —  a PDF read as a document, a page at a time
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-DOC- (public), _PDD- (private)
\  Depends on: pdf/filter.f, pdf/file.f, pdf/page.f, pdf/font.f,
\              pdf/content.f, pdf/struct.f, pdf/navigate.f, pdf/labels.f,
\              pdf/layout.f,
\              pdf/image.f,
\              media/document.f, media/picture.f, text/text-style.f,
\              utils/string.f
\
\  Public API:
\   PDF-DOC-READER   ( -- reader )     the reader, for DOC-OPEN
\
\  A reader (media/document.f) for PDF files.  The document has a part
\  for each page, so opening a PDF reads its cross-reference and how many
\  pages it has, nothing more.  A view reads a page when it nears it: the
\  page's content is read (pdf/content.f), with its structure when it is
\  tagged (pdf/struct.f), and laid out (pdf/layout.f).  The page gives a
\  page's start, labelled with its number from 1, then its blocks:
\  paragraphs, headings, code, list items, quotes and figures.  A page's
\  label is the one the file gives it (pdf/labels.f), such as iv, or its
\  number from 1.  A page
\  that cannot be opened gives its start and a paragraph saying so; one
\  whose content is damaged gives the blocks of what could be read.
\
\  Each page read keeps its text and meanings, so a block's content is
\  copied from them, never laid out again.  It keeps its links too: the
\  layout places each link of the page (pdf/navigate.f) over the text its
\  rectangle covers, which takes the link's meaning, and a block's content
\  gives its links.  A link to the web has its address as its target; a
\  link within the file has "#" and its destination's value, a byte for
\  its type and then its bytes, which DOC-ANCHOR-PART resolves to the page
\  it names only when it is followed.  Once that page is read, DOC-ANCHOR
\  gives the block the destination shows first, by where the page's
\  blocks lie (pdf/layout.f), which each page read keeps: of the blocks
\  that reach across the destination's left, the one whose low, its last
\  line's middle, is the highest at or below its top; then, of the blocks
\  within that one's reach across, as a picture centred in its column
\  is, the same.  A destination without a left looks at every block,
\  and one without a top, or whose block is the page's first, shows the
\  page's start.  A figure's name is "picture"
\  and its picture object's number.  The document holds its pictures
\  (DOC-PICTURES?): DOC-PICTURE gives a maker (media/picture.f) that
\  turns the object into a file a step at a time (pdf/image.f), for a
\  picture that makes one.
\
\  Its contents are its outline, each item at its level, going where it
\  goes as a link would; a file without an outline has its pages, each
\  "Page" and its label, going to it ("#p" and its index).
\
\  A blank row lies before each block but the first page's start, and
\  none between two list items; a blank row between two quoted blocks
\  lies inside the quote.  The pages the file says it has are at most
\  its objects, as each page is an object.  A file that needs a password
\  opens as DOC-S-LOCKED, and memory refused is DOC-S-MEMORY; any other
\  file that cannot be read is DOC-S-READ.
\
\  Memory comes from the document's memory source.  The fonts read for
\  one page serve the pages after it.  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-document

REQUIRE filter.f
REQUIRE file.f
REQUIRE page.f
REQUIRE font.f
REQUIRE content.f
REQUIRE struct.f
REQUIRE navigate.f
REQUIRE labels.f
REQUIRE layout.f
REQUIRE image.f
REQUIRE ../media/document.f
REQUIRE ../media/picture.f
REQUIRE ../text/text-style.f
REQUIRE ../utils/string.f

\ The reader's state, one allocation from the document's memory: the
\ file, its fonts, a page and what reading one takes, the destination
\ found last with its name, and a slot for each page once it is read.
0                                   CONSTANT _PDD-O-FILE
_PDD-O-FILE    PDF-FILE-SIZE +      CONSTANT _PDD-O-FONTS
_PDD-O-FONTS   PDF-FONTS-SIZE +     CONSTANT _PDD-O-PAGE
_PDD-O-PAGE    PDF-PAGE-SIZE +      CONSTANT _PDD-O-CONTENT
_PDD-O-CONTENT PDF-CONTENT-SIZE +   CONSTANT _PDD-O-STRUCT
_PDD-O-STRUCT  PDF-STRUCT-SIZE +    CONSTANT _PDD-O-LINKS
_PDD-O-LINKS   PDF-LINKS-SIZE +     CONSTANT _PDD-O-LAYOUT
_PDD-O-LAYOUT  PDF-LAYOUT-SIZE +    CONSTANT _PDD-O-LABELS
_PDD-O-LABELS  PDF-LABELS-SIZE +    CONSTANT _PDD-O-LBUF
_PDD-O-LBUF    PDF-BUF-SIZE +       CONSTANT _PDD-O-AKEY
_PDD-O-AKEY    PDF-BUF-SIZE +       CONSTANT _PDD-O-AGOT
_PDD-O-AGOT    24 +                 CONSTANT _PDD-O-SLOTS
_PDD-O-SLOTS   8 +                  CONSTANT _PDD-O-PAGES
_PDD-O-PAGES   8 +                  CONSTANT _PDD-SIZE

\ A page's slot: one allocation and its bytes, which hold the page's text,
\ its meanings, each layout block's span (how far across a destination's
\ left finds it, its reach widened by its size each side, and its low),
\ its links' places (a block of the layout, where in its text, how long,
\ and the link), each link's target (where and how long), and the
\ targets' bytes; the text's length, and how many places, links and spans.
: _SLOT.BUF     ( slot -- a )        ;
: _SLOT.BYTES   ( slot -- a )    8 + ;
: _SLOT.T       ( slot -- a )   16 + ;
: _SLOT.NP      ( slot -- a )   24 + ;
: _SLOT.NL      ( slot -- a )   32 + ;
: _SLOT.NB      ( slot -- a )   40 + ;
48 CONSTANT _PDD-SLOT
24 CONSTANT _PDD-SPAN
32 CONSTANT _PDD-PLACE
16 CONSTANT _PDD-TARGET

VARIABLE _PDD-D       \ the document
VARIABLE _PDD-S       \ its state

: _PDD-FILE     ( -- file )     _PDD-S @ _PDD-O-FILE + ;
: _PDD-FONTS    ( -- fonts )    _PDD-S @ _PDD-O-FONTS + ;
: _PDD-PAGE     ( -- page )     _PDD-S @ _PDD-O-PAGE + ;
: _PDD-CONTENT  ( -- content )  _PDD-S @ _PDD-O-CONTENT + ;
: _PDD-STRUCT   ( -- struct )   _PDD-S @ _PDD-O-STRUCT + ;
: _PDD-LAYOUT   ( -- layout )   _PDD-S @ _PDD-O-LAYOUT + ;
: _PDD-LINKS    ( -- links )    _PDD-S @ _PDD-O-LINKS + ;
: _PDD-LABELS   ( -- labels )   _PDD-S @ _PDD-O-LABELS + ;
: _PDD-LBUF     ( -- buf )      _PDD-S @ _PDD-O-LBUF + ;
: _PDD-AKEY     ( -- buf )      _PDD-S @ _PDD-O-AKEY + ;
: _PDD-AGOT     ( -- a )        _PDD-S @ _PDD-O-AGOT + ;

\ Page I's label in the label buffer; false when memory refuses.
: _PDD-LABEL!  ( i -- ok? )
    0 _PDD-LBUF PDF-BUF.U !  _PDD-LABELS _PDD-LBUF PDF-LABEL ;
: _PDD-LABEL  ( -- a u )  _PDD-LBUF DUP PDF-BUF.A @ SWAP PDF-BUF.U @ ;
: _PDD-PAGES    ( -- n )        _PDD-S @ _PDD-O-PAGES + @ ;
: _PDD-SLOT@    ( i -- slot )   _PDD-SLOT * _PDD-S @ _PDD-O-SLOTS + @ + ;

: _PDD-ALLOC  ( bytes -- a|0 )  _PDD-D @ DOC-MSRC@ MSRC-ALLOC ;
: _PDD-FREE   ( a bytes -- )
    OVER 0= IF 2DROP EXIT THEN _PDD-D @ DOC-MSRC@ MSRC-FREE ;

\ Work on document DOC, whose state the reader keeps.
: _PDD-USE  ( doc -- )  DUP _PDD-D ! DOC-STATE@ _PDD-S ! ;

\ Where a page's spans, places, link targets and their bytes start in its
\ buffer.
: _PDD-SPANS@    ( slot -- a )  DUP _SLOT.BUF @ SWAP _SLOT.T @ 2* 7 + -8 AND + ;
: _PDD-PLACES@   ( slot -- a )  DUP _PDD-SPANS@ SWAP _SLOT.NB @ _PDD-SPAN * + ;
: _PDD-TARGETS@  ( slot -- a )  DUP _PDD-PLACES@ SWAP _SLOT.NP @ _PDD-PLACE * + ;

: _PDD-SLOT-FREE  ( slot -- )
    DUP _SLOT.BUF @ OVER _SLOT.BYTES @ _PDD-FREE  _PDD-SLOT 0 FILL ;

\ Give back what reading a page took.
: _PDD-SCRATCH-FREE  ( -- )
    _PDD-LAYOUT PDF-LAYOUT-FREE _PDD-CONTENT PDF-CONTENT-FREE
    _PDD-STRUCT PDF-STRUCT-FREE _PDD-LINKS PDF-LINKS-FREE ;

\ =====================================================================
\  Opening and closing
\ =====================================================================

\ A status the file gave, as the document's.
: _PDD-STATUS  ( pdf-status -- status )
    DUP PDF-S-MEMORY = IF DROP DOC-S-MEMORY EXIT THEN
    PDF-S-OK = IF DOC-S-OK ELSE DOC-S-READ THEN ;

: _PDD-STRUCTURE  ( doc -- status )
    _PDD-D !
    _PDD-SIZE _PDD-ALLOC DUP 0= IF DROP DOC-S-MEMORY EXIT THEN
    DUP _PDD-S !  DUP _PDD-SIZE 0 FILL  _PDD-D @ DOC-STATE!
    _PDD-D @ DOC-SOURCE@ _PDD-D @ DOC-MSRC@ _PDD-FILE PDF-OPEN
    ?DUP IF _PDD-STATUS EXIT THEN
    _PDD-FILE PDF-FILE-LOCKED? IF DOC-S-LOCKED EXIT THEN
    _PDD-FILE PDF-PAGE-COUNT ?DUP IF NIP _PDD-STATUS EXIT THEN
    _PDD-FILE _PDD-LABELS PDF-LABELS-READ PDF-S-MEMORY = IF DROP DOC-S-MEMORY EXIT THEN
    0 MAX _PDD-FILE PDF-OBJECT-COUNT MIN                 ( pages )
    DUP 0= IF DROP DOC-S-OK EXIT THEN
    DUP _PDD-SLOT * DUP _PDD-ALLOC DUP 0= IF 2DROP DROP DOC-S-MEMORY EXIT THEN
    DUP _PDD-S @ _PDD-O-SLOTS + !  SWAP 0 FILL
    DUP _PDD-S @ _PDD-O-PAGES + !
    0 ?DO
        I 0 _PDD-D @ DOC-ADD-PART 0= IF DOC-S-MEMORY UNLOOP EXIT THEN
    LOOP
    DOC-S-OK ;

: _PDD-CLOSE  ( doc -- )
    _PDD-USE  _PDD-S @ 0= IF EXIT THEN
    _PDD-S @ _PDD-O-SLOTS + @ IF
        _PDD-PAGES 0 ?DO I _PDD-SLOT@ _PDD-SLOT-FREE LOOP
        _PDD-S @ _PDD-O-SLOTS + @ _PDD-PAGES _PDD-SLOT * _PDD-FREE
    THEN
    _PDD-SCRATCH-FREE  _PDD-PAGE PDF-PAGE-END  _PDD-FONTS PDF-FONTS-FREE
    _PDD-LABELS PDF-LABELS-FREE  _PDD-LBUF _PDD-D @ DOC-MSRC@ PDF-BUF-FREE
    _PDD-AKEY _PDD-D @ DOC-MSRC@ PDF-BUF-FREE
    _PDD-FILE PDF-CLOSE
    _PDD-S @ _PDD-SIZE _PDD-FREE  0 _PDD-D @ DOC-STATE! ;

\ =====================================================================
\  A page
\ =====================================================================

VARIABLE _PDD-I       \ the page being read
VARIABLE _PDD-SL      \ its slot, being filled
VARIABLE _PDD-AT      \ where the next text goes
VARIABLE _PDD-LAID    \ the page was laid out
VARIABLE _PDD-LINKED  \ its links were read
VARIABLE _PDD-PREV    \ the container kind of the block added last
VARIABLE _PDD-PC      \ the next place to mark


: _PDD-NOTE  ( -- a u )  S" (this page could not be read)" ;
: _PDD-BUF  ( -- a )  _PDD-SL @ _SLOT.BUF @ ;
: _PDD-T    ( -- t )  _PDD-SL @ _SLOT.T @ ;

\ Lay the page out with its links: PDF-S-OK, PDF-S-MEMORY, or why it
\ could not be opened.  A content, structure or links that are damaged
\ give what was read.
: _PDD-LAY-OUT  ( -- status )
    _PDD-I @ _PDD-FILE _PDD-PAGE PDF-PAGE-OPEN ?DUP IF EXIT THEN
    _PDD-PAGE _PDD-FONTS _PDD-CONTENT PDF-CONTENT-READ
    PDF-S-MEMORY = IF _PDD-PAGE PDF-PAGE-CLOSE PDF-S-MEMORY EXIT THEN
    _PDD-PAGE _PDD-STRUCT PDF-STRUCT-READ
    PDF-S-MEMORY = IF _PDD-PAGE PDF-PAGE-CLOSE PDF-S-MEMORY EXIT THEN
    _PDD-PAGE _PDD-LINKS PDF-LINKS-READ
    DUP PDF-S-MEMORY = IF _PDD-PAGE PDF-PAGE-CLOSE EXIT THEN
    0= DUP _PDD-LINKED !
    _PDD-PAGE _PDD-CONTENT _PDD-STRUCT 3 ROLL IF _PDD-LINKS ELSE 0 THEN
    _PDD-LAYOUT PDF-LAYOUT-READ
    _PDD-PAGE PDF-PAGE-CLOSE ;

\ The page's text bytes: its label, then its blocks' text or the note.
: _PDD-TEXT-BYTES  ( -- t )
    _PDD-LABEL NIP
    _PDD-LAID @ 0= IF _PDD-NOTE NIP + EXIT THEN
    _PDD-LAYOUT PDF-LAYOUT-BLOCKS 0 ?DO
        I _PDD-LAYOUT PDF-LAYOUT-BLOCK _PDD-LAYOUT PDF-BLOCK-TEXT NIP +
    LOOP ;

\ The page's links, the places the layout put them, and its blocks'
\ spans, when laid out.
: _PDD-NL  ( -- n )
    _PDD-LAID @ _PDD-LINKED @ AND IF _PDD-LINKS PDF-LINKS-COUNT ELSE 0 THEN ;
: _PDD-NP  ( -- n )  _PDD-NL IF _PDD-LAYOUT PDF-LAYOUT-LINKS ELSE 0 THEN ;
: _PDD-NB  ( -- n )  _PDD-LAID @ IF _PDD-LAYOUT PDF-LAYOUT-BLOCKS ELSE 0 THEN ;

\ Link K's target: its address, or "#", its destination's type, and its
\ value's bytes.
: _PDD-TARGET-BYTES  ( k -- u )
    _PDD-LINKS PDF-LINK DUP _PDD-LINKS PDF-LINK-URI NIP ?DUP IF NIP EXIT THEN
    _PDD-LINKS PDF-LINK-DEST DROP NIP 2 + ;

\ The bytes the page's slot needs: text and meanings, spans, places,
\ targets.
: _PDD-SLOT-BYTES  ( -- u )
    _PDD-T 2* 7 + -8 AND  _PDD-SL @ _SLOT.NB @ _PDD-SPAN * +
    _PDD-SL @ _SLOT.NP @ _PDD-PLACE * +
    _PDD-SL @ _SLOT.NL @ DUP _PDD-TARGET * ROT +
    SWAP 0 ?DO I _PDD-TARGET-BYTES + LOOP ;

VARIABLE _PDF-AT
VARIABLE _PDF-PL

\ Copy the layout's places and each link's target to the slot.
: _PDD-FILL-LINKS  ( -- )
    _PDD-SL @ _SLOT.NP @ 0 ?DO
        _PDD-SL @ _PDD-PLACES@ I _PDD-PLACE * + _PDF-PL !
        I _PDD-LAYOUT PDF-LAYOUT-LINK
        _PDF-PL @ 24 + !  _PDF-PL @ 16 + !  _PDF-PL @ 8 + !  _PDF-PL @ !
    LOOP
    _PDD-SL @ _PDD-TARGETS@ _PDD-SL @ _SLOT.NL @ _PDD-TARGET * + _PDD-BUF - _PDF-AT !
    _PDD-SL @ _SLOT.NL @ 0 ?DO
        _PDD-SL @ _PDD-TARGETS@ I _PDD-TARGET * +  _PDF-AT @ OVER !
        I _PDD-TARGET-BYTES SWAP 8 + !
        I _PDD-LINKS PDF-LINK DUP _PDD-LINKS PDF-LINK-URI ?DUP IF
            _PDD-BUF _PDF-AT @ + SWAP DUP _PDF-AT +! MOVE DROP
        ELSE
            DROP _PDD-LINKS PDF-LINK-DEST                 ( va vu type )
            35 _PDD-BUF _PDF-AT @ + C!  48 + _PDD-BUF _PDF-AT @ + 1+ C!
            _PDD-BUF _PDF-AT @ + 2 + SWAP DUP 2 + _PDF-AT +! MOVE
        THEN
    LOOP ;

VARIABLE _PDS-P

\ Copy each layout block's span to the slot: its reach across, widened by
\ its size each side, and its low.
: _PDD-FILL-SPANS  ( -- )
    _PDD-SL @ _SLOT.NB @ 0 ?DO
        _PDD-SL @ _PDD-SPANS@ I _PDD-SPAN * + _PDS-P !
        I _PDD-LAYOUT PDF-LAYOUT-BLOCK
        DUP PDF-BLOCK-LOW _PDS-P @ 16 + !
        DUP PDF-BLOCK-SIZE SWAP PDF-BLOCK-ACROSS              ( size x0 x1 )
        2 PICK + _PDS-P @ 8 + !  SWAP - _PDS-P @ !
    LOOP ;

VARIABLE _PDP-U

\ Copy U bytes of text at A to the page's buffer, with the meanings at M,
\ or plain for M = 0; the offset the text starts at.
: _PDD-PUT  ( a u m -- offset )
    SWAP _PDP-U !                                        ( a m )
    ?DUP IF _PDD-BUF _PDD-T + _PDD-AT @ + _PDP-U @ MOVE
    ELSE _PDD-BUF _PDD-T + _PDD-AT @ + _PDP-U @ 0 FILL THEN
    _PDD-BUF _PDD-AT @ + _PDP-U @ MOVE
    _PDD-AT @ _PDP-U @ _PDD-AT +! ;

\ The text of layout block J, put at OFFSET, takes the link's meaning
\ where the layout placed a link.
: _PDD-MARK  ( j offset -- )
    BEGIN
        _PDD-PC @ _PDD-SL @ _SLOT.NP @ < IF
            _PDD-SL @ _PDD-PLACES@ _PDD-PC @ _PDD-PLACE * + @ 2 PICK =
        ELSE 0 THEN
    WHILE
        _PDD-SL @ _PDD-PLACES@ _PDD-PC @ _PDD-PLACE * +
        DUP 8 + @ 2 PICK + _PDD-BUF + _PDD-T + SWAP 16 + @ TSTY-LINK FILL
        1 _PDD-PC +!
    REPEAT 2DROP ;

\ Add a block, with the blank rows before it; false when memory refuses.
: _PDD-BLOCK  ( kind level loc-a loc-b rows inside -- block|0 )
    >R >R _PDD-D @ DOC-ADD-BLOCK R> R>                   ( block rows inside )
    2 PICK 0= IF 2DROP EXIT THEN
    2 PICK BLK-INSIDE! OVER BLK-ROWS-BEFORE! ;

: _PDD-LIST?  ( item -- flag )  DUP DOC-C-BULLET = SWAP DOC-C-NUMBERED = OR ;

\ The blank rows before a block of the page whose container is of kind
\ ITEM, or 0, and how many lie inside it: none between two list items,
\ and a row inside the quote between two quoted blocks.
: _PDD-ROWS  ( item -- rows inside )
    _PDD-PREV @ OVER _PDD-PREV !                         ( item prev )
    2DUP DOC-C-QUOTE = SWAP DOC-C-QUOTE = AND IF 2DROP 1 1 EXIT THEN
    _PDD-LIST? SWAP _PDD-LIST? AND IF 0 0 ELSE 1 0 THEN ;

\ Add laid-out block I with its container.
VARIABLE _PDA-B
: _PDD-ADD  ( i -- ok? )
    DUP _PDD-LAYOUT PDF-LAYOUT-BLOCK _PDA-B !
    _PDA-B @ PDF-BLOCK-KIND
    OVER DOC-B-FIGURE = IF
        ROT DROP _PDA-B @ PDF-BLOCK-FIGURE 2DROP 0
    ELSE
        _PDA-B @ _PDD-LAYOUT PDF-BLOCK-TEXT
        _PDA-B @ _PDD-LAYOUT PDF-BLOCK-MEANINGS _PDD-PUT   ( i kind level offset )
        DUP >R 3 ROLL R> _PDD-MARK
        _PDA-B @ _PDD-LAYOUT PDF-BLOCK-TEXT NIP
    THEN
    _PDA-B @ PDF-BLOCK-ITEM 2DROP _PDD-ROWS _PDD-BLOCK 0= IF 0 EXIT THEN
    _PDA-B @ PDF-BLOCK-ITEM ROT ?DUP IF
        -ROT SWAP -1 _PDD-D @ DOC-ADD-CONTAINER EXIT
    THEN 2DROP -1 ;

\ The page's blocks: its start, then what it was laid out as, or a note.
: _PDD-BLOCKS  ( -- ok? )
    DOC-B-PAGE 0 _PDD-LABEL 0 _PDD-PUT _PDD-LABEL NIP
    _PDD-I @ 0<> 1 AND 0 _PDD-BLOCK 0= IF 0 EXIT THEN
    0 _PDD-PREV !  0 _PDD-PC !
    _PDD-LAID @ 0= IF
        DOC-B-PARAGRAPH 0 _PDD-NOTE 0 _PDD-PUT _PDD-NOTE NIP 1 0 _PDD-BLOCK 0<> EXIT
    THEN
    _PDD-LAYOUT PDF-LAYOUT-BLOCKS 0 ?DO
        I _PDD-ADD 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

: _PDD-PART  ( part doc -- status )
    _PDD-USE _PDD-I !
    _PDD-I @ _PDD-SLOT@ DUP _PDD-SL ! _PDD-SLOT-FREE
    _PDD-I @ _PDD-LABEL! 0= IF DOC-S-MEMORY EXIT THEN
    _PDD-LAY-OUT DUP PDF-S-MEMORY = IF DROP _PDD-SCRATCH-FREE DOC-S-MEMORY EXIT THEN
    0= _PDD-LAID !
    _PDD-TEXT-BYTES _PDD-SL @ _SLOT.T !
    _PDD-NP _PDD-SL @ _SLOT.NP !  _PDD-NL _PDD-SL @ _SLOT.NL !
    _PDD-NB _PDD-SL @ _SLOT.NB !
    _PDD-SLOT-BYTES DUP _PDD-SL @ _SLOT.BYTES !
    _PDD-ALLOC DUP _PDD-SL @ _SLOT.BUF !
    0= IF _PDD-SL @ _PDD-SLOT 0 FILL _PDD-SCRATCH-FREE DOC-S-MEMORY EXIT THEN
    _PDD-FILL-SPANS  _PDD-FILL-LINKS
    0 _PDD-AT !
    _PDD-BLOCKS
    _PDD-SCRATCH-FREE
    0= IF _PDD-SL @ _PDD-SLOT-FREE DOC-S-MEMORY EXIT THEN
    DOC-S-OK ;

\ =====================================================================
\  A block's content
\ =====================================================================

VARIABLE _PDR-A
VARIABLE _PDR-U
VARIABLE _PDR-M
VARIABLE _PDR-START

\ Add text with a meaning a byte, a run of one meaning at a time.
: _PDD-RUNS  ( a u m -- ok? )
    _PDR-M ! _PDR-U ! _PDR-A !  0 _PDR-START !
    _PDR-U @ 0 ?DO
        I 1+ _PDR-U @ = IF -1 ELSE _PDR-M @ I + C@ _PDR-M @ I + 1+ C@ <> THEN
        IF
            _PDR-A @ _PDR-START @ +  I 1+ _PDR-START @ -
            _PDR-M @ _PDR-START @ + C@  _PDD-D @ DOC-CB-TEXT 0= IF 0 UNLOOP EXIT THEN
            I 1+ _PDR-START !
        THEN
    LOOP -1 ;

CREATE _PDD-NAME 32 ALLOT

\ A figure's name: "picture" and its object's number.
: _PDD-FIGURE  ( num -- ok? )
    S" picture " _PDD-NAME SWAP MOVE
    NUM>STR DUP 8 + >R _PDD-NAME 8 + SWAP MOVE
    _PDD-NAME R> _PDD-D @ DOC-CB-FIGURE ;

\ The links the layout placed over layout block J's text.
: _PDD-BLOCK-LINKS  ( slot j -- ok? )
    OVER _SLOT.NP @ 0 ?DO
        OVER _PDD-PLACES@ I _PDD-PLACE * +  DUP @ 2 PICK = IF
            DUP 8 + @ OVER 16 + @ OVER +                       ( slot j place start end )
            ROT 24 + @ _PDD-TARGET * 4 PICK _PDD-TARGETS@ +    ( slot j start end target )
            DUP @ 5 PICK _SLOT.BUF @ + SWAP 8 + @
            _PDD-D @ DOC-CB-LINK 0= IF 2DROP 0 UNLOOP EXIT THEN
        ELSE DROP THEN
    LOOP 2DROP -1 ;

\ A block's content: a figure's name, or its text with its meanings and
\ its links.  The page's start is the part's first block, so a block's
\ place in the layout is its place in the part less one.
: _PDD-CONTENT  ( index doc -- status )
    _PDD-USE
    DUP _PDD-D @ DOC-BLOCK DUP BLK-KIND@ DOC-B-FIGURE = IF
        NIP BLK-LOC@ DROP _PDD-FIGURE IF DOC-S-OK ELSE DOC-S-MEMORY THEN EXIT
    THEN                                                     ( index block )
    OVER _PDD-D @ DOC-PART-OF DUP _PDD-SLOT@ >R              ( index block part )
    ROT SWAP _PDD-D @ DOC-PART-FIRST - 1- SWAP               ( j block )
    BLK-LOC@ R@ _SLOT.BUF @ ROT + SWAP                       ( j a u )
    OVER R@ _SLOT.BUF @ - R@ _SLOT.T @ + R@ _SLOT.BUF @ +    ( j a u m )
    _PDD-RUNS 0= IF DROP R> DROP DOC-S-MEMORY EXIT THEN
    R> SWAP _PDD-BLOCK-LINKS IF DOC-S-OK ELSE DOC-S-MEMORY THEN ;

\ =====================================================================
\  A figure's picture
\ =====================================================================

VARIABLE _PDK-N

\ The picture object a figure's name gives: "picture" and its number.
: _PDD-PICTURE-NUM  ( name-a name-u -- num ok? )
    DUP 9 < IF 2DROP 0 0 EXIT THEN
    OVER 8 S" picture " STR-STR= 0= IF 2DROP 0 0 EXIT THEN
    8 /STRING 0 _PDK-N !
    BEGIN DUP WHILE
        OVER C@ DUP 48 58 WITHIN 0= IF DROP 2DROP 0 0 EXIT THEN
        48 - _PDK-N @ 10 * + _PDK-N !  1 /STRING
    REPEAT 2DROP _PDK-N @ -1 ;

\ A picture's job: the memory source it came from, then its record.
: _PDD-PIC-STEP    ( budget job -- state )  8 + PDF-IMAGE-STEP ;
: _PDD-PIC-SOURCE  ( source job -- )  8 + SWAP PDF-IMAGE-SOURCE ;
: _PDD-PIC-FREE    ( job -- )
    DUP 8 + PDF-IMAGE-FREE  DUP @ SWAP PDF-IMAGE-SIZE 8 + ROT MSRC-FREE ;

\ Fill MAKER for the picture a figure names, when it makes a file.
: _PDD-PICTURE  ( name-a name-u maker doc -- ok? )
    _PDD-USE >R
    _PDD-PICTURE-NUM 0= IF DROP R> DROP 0 EXIT THEN
    PDF-IMAGE-SIZE 8 + _PDD-ALLOC ?DUP 0= IF DROP R> DROP 0 EXIT THEN
    _PDD-D @ DOC-MSRC@ OVER !                            ( num job )
    TUCK 8 + _PDD-FILE SWAP PDF-IMAGE-OPEN               ( job status )
    PDF-S-OK <> OVER 8 + PDF-IMAGE-FORMAT 0= OR IF _PDD-PIC-FREE R> DROP 0 EXIT THEN
    DUP 8 + PDF-IMAGE-WIDTH OVER 8 + PDF-IMAGE-HEIGHT
    ['] _PDD-PIC-STEP ['] _PDD-PIC-SOURCE ['] _PDD-PIC-FREE 5 ROLL
    R> PIC-MAKER-INIT -1 ;

\ =====================================================================
\  Following a link within the file
\ =====================================================================

VARIABLE _PDN-N

\ A page's index after "p".
: _PDD-PAGE-NUM  ( a u -- i | -1 )
    0 _PDN-N !
    BEGIN DUP WHILE
        OVER C@ DUP 48 58 WITHIN 0= IF DROP 2DROP -1 EXIT THEN
        48 - _PDN-N @ 10 * + _PDN-N !  1 /STRING
    REPEAT 2DROP _PDN-N @ ;

VARIABLE _PDW-X   VARIABLE _PDW-Y     \ the destination's left and top
VARIABLE _PDW-SL                      \ its page's slot
VARIABLE _PDW-HOW                     \ which spans are looked at
VARIABLE _PDW-L   VARIABLE _PDW-R     \ a column's reach
VARIABLE _PDW-BEST   VARIABLE _PDW-LOW

: _PDD-SPAN@  ( j -- span )  _PDD-SPAN * _PDW-SL @ _PDD-SPANS@ + ;

\ Whether a span is looked at: any (0), one that reaches across the
\ destination's left (1), or one within the column's reach (2).
: _PDD-LOOKED?  ( span -- flag )
    _PDW-HOW @ 0= IF DROP -1 EXIT THEN
    _PDW-HOW @ 1 = IF DUP @ _PDW-X @ > 0= SWAP 8 + @ _PDW-X @ < 0= AND EXIT THEN
    DUP @ _PDW-L @ < 0= SWAP 8 + @ _PDW-R @ > 0= AND ;

\ Of the blocks looked at, the one whose low is the highest at or below
\ the destination's top, the first of equals; or -1.
: _PDD-HIGHEST  ( -- j | -1 )
    -1 _PDW-BEST !
    _PDW-SL @ _SLOT.NB @ 0 ?DO
        I _PDD-SPAN@ DUP _PDD-LOOKED? IF
            16 + @ DUP _PDW-Y @ > IF DROP ELSE
                _PDW-BEST @ 0< OVER _PDW-LOW @ > OR
                IF _PDW-LOW ! I _PDW-BEST ! ELSE DROP THEN
            THEN
        ELSE DROP THEN
    LOOP _PDW-BEST @ ;

\ The layout block the destination shows first: of those that reach
\ across its left, the highest at or below its top; then, of those within
\ that one's reach, its column, the highest.  Without a left, or with no
\ block across it at or below the top, every block is looked at.  -1
\ when no block lies at or below the top.
: _PDD-CHOOSE  ( -- j | -1 )
    _PDW-X @ -1 <> IF
        1 _PDW-HOW !  _PDD-HIGHEST DUP 0< 0= IF
            _PDD-SPAN@ DUP @ _PDW-L !  8 + @ _PDW-R !
            2 _PDW-HOW !  _PDD-HIGHEST EXIT
        THEN DROP
    THEN
    0 _PDW-HOW !  _PDD-HIGHEST ;

\ The block of page I a destination at left X and top Y, each -1 when it
\ gives none, shows first, as the document's index: the page's start for
\ no top, or when its block is the page's first; the page's last block
\ when none lies at or below the top.  -1 when the page is not read.
: _PDD-PLACE  ( x y i -- index | -1 )
    DUP _PDD-D @ DOC-PART-READ? 0= IF DROP 2DROP -1 EXIT THEN
    DUP _PDD-SLOT@ _PDW-SL !  _PDD-D @ DOC-PART-FIRST >R
    _PDW-Y !  _PDW-X !
    _PDW-Y @ -1 = IF R> EXIT THEN
    _PDD-CHOOSE DUP 0< IF DROP _PDW-SL @ _SLOT.NB @ 1- THEN
    DUP 0> IF R> + 1+ ELSE DROP R> THEN ;

\ Whether NAME is the target whose destination was found last.
: _PDD-KEPT?  ( name-a name-u -- flag )
    _PDD-AKEY PDF-BUF.U @ 0= IF 2DROP 0 EXIT THEN
    _PDD-AKEY DUP PDF-BUF.A @ SWAP PDF-BUF.U @ STR-STR= ;

\ The page index, left and top a target's destination names: its type
\ and its value's bytes after the "#".  Following a link asks twice, for
\ its page and then, once the page is read, for its place, and the file
\ does not change while it is open, so the destination found last is
\ kept with its target, when memory allows, and not looked up again.
: _PDD-RESOLVE  ( name-a name-u -- x y i ok? )
    2DUP _PDD-KEPT? IF
        2DROP _PDD-AGOT @ _PDD-AGOT 8 + @ _PDD-AGOT 16 + @ -1 EXIT
    THEN
    2DUP 2>R
    OVER C@ 48 - >R 1 /STRING R>                          ( va vu type )
    _PDD-FILE PDF-DEST IF DROP 2DROP 2R> 2DROP 0 0 0 0 EXIT THEN    ( num x y )
    ROT _PDD-FILE PDF-PAGE-INDEX IF DROP 2DROP 2R> 2DROP 0 0 0 0 EXIT THEN
    0 _PDD-AKEY PDF-BUF.U !                                ( x y i )
    2R> _PDD-AKEY _PDD-D @ DOC-MSRC@ PDF-BUF-APPEND IF
        DUP _PDD-AGOT 16 + !  OVER _PDD-AGOT 8 + !  2 PICK _PDD-AGOT !
    ELSE 0 _PDD-AKEY PDF-BUF.U ! THEN
    -1 ;

\ Where a link's target goes, after the "#": "p" and a page's index, to
\ the page's start; or its destination's type and its value's bytes, to
\ the page it names and, once that page is read, the block the
\ destination shows first.  -1 for a part, or a block, that is not.
: _PDD-ANCHOR  ( name-a name-u doc -- part index )
    _PDD-USE
    DUP 2 < IF 2DROP -1 -1 EXIT THEN
    OVER C@ 112 = IF
        1 /STRING _PDD-PAGE-NUM DUP 0 _PDD-PAGES WITHIN 0= IF DROP -1 -1 EXIT THEN
        -1 -1 ROT DUP >R _PDD-PLACE R> SWAP EXIT
    THEN
    _PDD-RESOLVE 0= IF 2DROP DROP -1 -1 EXIT THEN         ( x y i )
    DUP 0 _PDD-PAGES WITHIN 0= IF DROP 2DROP -1 -1 EXIT THEN
    DUP >R _PDD-PLACE R> SWAP ;

\ =====================================================================
\  Contents
\ =====================================================================

CREATE _PDD-OUTLINE-S PDF-OUTLINE-SIZE 7 + ALLOT
: _PDD-OUTLINE  ( -- outline )  _PDD-OUTLINE-S 7 + -8 AND ;
_PDD-OUTLINE PDF-OUTLINE-SIZE 0 FILL

CREATE _PDD-ETARGET 32 ALLOT
VARIABLE _PDD-TG   VARIABLE _PDD-TGU   VARIABLE _PDD-TGOWN

\ An outline item's target: "#", its destination's type and its value's
\ bytes, in a buffer of its own from the document's memory; or its
\ address; or none.  False when memory refuses the buffer.
: _PDD-ITEM-TARGET  ( item -- ok? )
    0 _PDD-TG !  0 _PDD-TGU !  0 _PDD-TGOWN !
    DUP _PDD-OUTLINE PDF-ITEM-URI ?DUP IF _PDD-TGU ! _PDD-TG ! DROP -1 EXIT THEN DROP
    _PDD-OUTLINE PDF-ITEM-DEST                           ( va vu type )
    OVER 0= IF DROP 2DROP -1 EXIT THEN
    OVER 2 + DUP _PDD-ALLOC ?DUP 0= IF DROP DROP 2DROP 0 EXIT THEN
    DUP _PDD-TG !  OVER _PDD-TGU !  NIP  -1 _PDD-TGOWN !  ( va vu type buf )
    35 OVER C!  SWAP 48 + OVER 1+ C!  2 + SWAP MOVE -1 ;

\ The outline as the contents; false when memory refuses.
: _PDD-ITEMS  ( -- ok? )
    _PDD-OUTLINE PDF-OUTLINE-COUNT 0 ?DO
        I _PDD-OUTLINE PDF-OUTLINE-ITEM
        DUP _PDD-ITEM-TARGET 0= IF DROP 0 UNLOOP EXIT THEN
        DUP PDF-ITEM-LEVEL SWAP _PDD-OUTLINE PDF-ITEM-TITLE 0 _PDD-TG @ _PDD-TGU @
        _PDD-D @ DOC-ADD-ENTRY
        _PDD-TGOWN @ IF _PDD-TG @ _PDD-TGU @ _PDD-FREE THEN
        0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

\ The pages as the contents: "Page" and each one's label, going to it.
: _PDD-PAGE-ENTRIES  ( -- ok? )
    35 _PDD-ETARGET C!  112 _PDD-ETARGET 1+ C!
    _PDD-PAGES 0 ?DO
        0 _PDD-LBUF PDF-BUF.U !
        S" Page " _PDD-LBUF _PDD-D @ DOC-MSRC@ PDF-BUF-APPEND 0= IF 0 UNLOOP EXIT THEN
        I _PDD-LABELS _PDD-LBUF PDF-LABEL 0= IF 0 UNLOOP EXIT THEN
        I NUM>STR DUP 2 + _PDD-TGU ! _PDD-ETARGET 2 + SWAP MOVE
        0 _PDD-LABEL 0 _PDD-ETARGET _PDD-TGU @
        _PDD-D @ DOC-ADD-ENTRY 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

: _PDD-CONTENTS  ( doc -- status )
    _PDD-USE
    _PDD-FILE _PDD-OUTLINE PDF-OUTLINE-READ
    DUP PDF-S-MEMORY = IF DROP _PDD-OUTLINE PDF-OUTLINE-FREE DOC-S-MEMORY EXIT THEN
    0= _PDD-OUTLINE PDF-OUTLINE-COUNT 0<> AND IF _PDD-ITEMS ELSE _PDD-PAGE-ENTRIES THEN
    _PDD-OUTLINE PDF-OUTLINE-FREE
    IF DOC-S-OK ELSE DOC-S-MEMORY THEN ;

CREATE _PDD-READER RDR-SIZE ALLOT
' _PDD-STRUCTURE _PDD-READER RDR.STRUCTURE-XT !
' _PDD-CONTENT   _PDD-READER RDR.CONTENT-XT !
' _PDD-CLOSE     _PDD-READER RDR.CLOSE-XT !
' _PDD-PART      _PDD-READER RDR.PART-XT !
' _PDD-PICTURE   _PDD-READER RDR.PICTURE-XT !
' _PDD-ANCHOR    _PDD-READER RDR.ANCHOR-XT !
' _PDD-CONTENTS  _PDD-READER RDR.CONTENTS-XT !

: PDF-DOC-READER  ( -- reader )  _PDD-READER ;
