\ =================================================================
\  document.f  —  a PDF read as a document, a page at a time
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-DOC- (public), _PDD- (private)
\  Depends on: pdf/filter.f, pdf/file.f, pdf/page.f, pdf/font.f,
\              pdf/content.f, pdf/struct.f, pdf/layout.f, pdf/image.f,
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
\  paragraphs, headings, code, list items, quotes and figures.  A page
\  that cannot be opened gives its start and a paragraph saying so; one
\  whose content is damaged gives the blocks of what could be read.
\
\  Each page read keeps its text and meanings, so a block's content is
\  copied from them, never laid out again.  A figure's name is "picture"
\  and its picture object's number.  The document holds its pictures
\  (DOC-PICTURES?): DOC-PICTURE gives a maker (media/picture.f) that
\  turns the object into a file a step at a time (pdf/image.f), for a
\  picture that makes one.
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
REQUIRE layout.f
REQUIRE image.f
REQUIRE ../media/document.f
REQUIRE ../media/picture.f
REQUIRE ../text/text-style.f
REQUIRE ../utils/string.f

\ The reader's state, one allocation from the document's memory: the
\ file, its fonts, a page and what reading one takes, and a slot for each
\ page: its text then its meanings, once it is read, and the text's length.
0                                   CONSTANT _PDD-O-FILE
_PDD-O-FILE    PDF-FILE-SIZE +      CONSTANT _PDD-O-FONTS
_PDD-O-FONTS   PDF-FONTS-SIZE +     CONSTANT _PDD-O-PAGE
_PDD-O-PAGE    PDF-PAGE-SIZE +      CONSTANT _PDD-O-CONTENT
_PDD-O-CONTENT PDF-CONTENT-SIZE +   CONSTANT _PDD-O-STRUCT
_PDD-O-STRUCT  PDF-STRUCT-SIZE +    CONSTANT _PDD-O-LAYOUT
_PDD-O-LAYOUT  PDF-LAYOUT-SIZE +    CONSTANT _PDD-O-SLOTS
_PDD-O-SLOTS   8 +                  CONSTANT _PDD-O-PAGES
_PDD-O-PAGES   8 +                  CONSTANT _PDD-SIZE
16 CONSTANT _PDD-SLOT

VARIABLE _PDD-D       \ the document
VARIABLE _PDD-S       \ its state

: _PDD-FILE     ( -- file )     _PDD-S @ _PDD-O-FILE + ;
: _PDD-FONTS    ( -- fonts )    _PDD-S @ _PDD-O-FONTS + ;
: _PDD-PAGE     ( -- page )     _PDD-S @ _PDD-O-PAGE + ;
: _PDD-CONTENT  ( -- content )  _PDD-S @ _PDD-O-CONTENT + ;
: _PDD-STRUCT   ( -- struct )   _PDD-S @ _PDD-O-STRUCT + ;
: _PDD-LAYOUT   ( -- layout )   _PDD-S @ _PDD-O-LAYOUT + ;
: _PDD-PAGES    ( -- n )        _PDD-S @ _PDD-O-PAGES + @ ;
: _PDD-SLOT@    ( i -- slot )   _PDD-SLOT * _PDD-S @ _PDD-O-SLOTS + @ + ;

: _PDD-ALLOC  ( bytes -- a|0 )  _PDD-D @ DOC-MSRC@ MSRC-ALLOC ;
: _PDD-FREE   ( a bytes -- )
    OVER 0= IF 2DROP EXIT THEN _PDD-D @ DOC-MSRC@ MSRC-FREE ;

\ Work on document DOC, whose state the reader keeps.
: _PDD-USE  ( doc -- )  DUP _PDD-D ! DOC-STATE@ _PDD-S ! ;

\ A page's text: its slot's bytes, the text's length, and the meanings.
: _PDD-TEXT  ( slot -- a t m )  DUP @ SWAP 8 + @ 2DUP + ;

: _PDD-SLOT-FREE  ( slot -- )
    DUP @ OVER 8 + @ 2* _PDD-FREE  0 OVER ! 0 SWAP 8 + ! ;

\ Give back what reading a page took.
: _PDD-SCRATCH-FREE  ( -- )
    _PDD-LAYOUT PDF-LAYOUT-FREE _PDD-CONTENT PDF-CONTENT-FREE
    _PDD-STRUCT PDF-STRUCT-FREE ;

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
    _PDD-FILE PDF-CLOSE
    _PDD-S @ _PDD-SIZE _PDD-FREE  0 _PDD-D @ DOC-STATE! ;

\ =====================================================================
\  A page
\ =====================================================================

VARIABLE _PDD-I       \ the page being read
VARIABLE _PDD-BUF     \ its text, then its meanings
VARIABLE _PDD-T       \ the text's length
VARIABLE _PDD-AT      \ where the next text goes
VARIABLE _PDD-LAID    \ the page was laid out
VARIABLE _PDD-PREV    \ the container kind of the block added last

CREATE _PDD-LABEL 24 ALLOT
VARIABLE _PDD-LABEL-U

: _PDD-NOTE  ( -- a u )  S" (this page could not be read)" ;

\ Lay the page out: PDF-S-OK, PDF-S-MEMORY, or why it could not be
\ opened.  A content or structure that is damaged gives what was read.
: _PDD-LAY-OUT  ( -- status )
    _PDD-I @ _PDD-FILE _PDD-PAGE PDF-PAGE-OPEN ?DUP IF EXIT THEN
    _PDD-PAGE _PDD-FONTS _PDD-CONTENT PDF-CONTENT-READ
    PDF-S-MEMORY = IF _PDD-PAGE PDF-PAGE-CLOSE PDF-S-MEMORY EXIT THEN
    _PDD-PAGE _PDD-STRUCT PDF-STRUCT-READ
    PDF-S-MEMORY = IF _PDD-PAGE PDF-PAGE-CLOSE PDF-S-MEMORY EXIT THEN
    _PDD-PAGE _PDD-CONTENT _PDD-STRUCT _PDD-LAYOUT PDF-LAYOUT-READ
    _PDD-PAGE PDF-PAGE-CLOSE ;

\ The page's text bytes: its label, then its blocks' text or the note.
: _PDD-TEXT-BYTES  ( -- t )
    _PDD-LABEL-U @
    _PDD-LAID @ 0= IF _PDD-NOTE NIP + EXIT THEN
    _PDD-LAYOUT PDF-LAYOUT-BLOCKS 0 ?DO
        I _PDD-LAYOUT PDF-LAYOUT-BLOCK _PDD-LAYOUT PDF-BLOCK-TEXT NIP +
    LOOP ;

VARIABLE _PDP-U

\ Copy U bytes of text at A to the page's buffer, with the meanings at M,
\ or plain for M = 0; the offset the text starts at.
: _PDD-PUT  ( a u m -- offset )
    SWAP _PDP-U !                                        ( a m )
    ?DUP IF _PDD-BUF @ _PDD-T @ + _PDD-AT @ + _PDP-U @ MOVE
    ELSE _PDD-BUF @ _PDD-T @ + _PDD-AT @ + _PDP-U @ 0 FILL THEN
    _PDD-BUF @ _PDD-AT @ + _PDP-U @ MOVE
    _PDD-AT @ _PDP-U @ _PDD-AT +! ;

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
    _PDD-LAYOUT PDF-LAYOUT-BLOCK _PDA-B !
    _PDA-B @ PDF-BLOCK-KIND
    OVER DOC-B-FIGURE = IF
        _PDA-B @ PDF-BLOCK-FIGURE 2DROP 0
    ELSE
        _PDA-B @ _PDD-LAYOUT PDF-BLOCK-TEXT
        _PDA-B @ _PDD-LAYOUT PDF-BLOCK-MEANINGS _PDD-PUT
        _PDA-B @ _PDD-LAYOUT PDF-BLOCK-TEXT NIP
    THEN
    _PDA-B @ PDF-BLOCK-ITEM 2DROP _PDD-ROWS _PDD-BLOCK 0= IF 0 EXIT THEN
    _PDA-B @ PDF-BLOCK-ITEM ROT ?DUP IF
        -ROT SWAP -1 _PDD-D @ DOC-ADD-CONTAINER EXIT
    THEN 2DROP -1 ;

\ The page's blocks: its start, then what it was laid out as, or a note.
: _PDD-BLOCKS  ( -- ok? )
    DOC-B-PAGE 0 _PDD-LABEL _PDD-LABEL-U @ 0 _PDD-PUT _PDD-LABEL-U @
    _PDD-I @ 0<> 1 AND 0 _PDD-BLOCK 0= IF 0 EXIT THEN
    0 _PDD-PREV !
    _PDD-LAID @ 0= IF
        DOC-B-PARAGRAPH 0 _PDD-NOTE 0 _PDD-PUT _PDD-NOTE NIP 1 0 _PDD-BLOCK 0<> EXIT
    THEN
    _PDD-LAYOUT PDF-LAYOUT-BLOCKS 0 ?DO
        I _PDD-ADD 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

: _PDD-PART  ( part doc -- status )
    _PDD-USE _PDD-I !
    _PDD-I @ _PDD-SLOT@ _PDD-SLOT-FREE
    _PDD-I @ 1+ NUM>STR DUP _PDD-LABEL-U ! _PDD-LABEL SWAP MOVE
    _PDD-LAY-OUT DUP PDF-S-MEMORY = IF DROP _PDD-SCRATCH-FREE DOC-S-MEMORY EXIT THEN
    0= _PDD-LAID !
    _PDD-TEXT-BYTES DUP _PDD-T !  2* _PDD-ALLOC DUP _PDD-BUF !
    0= IF _PDD-SCRATCH-FREE DOC-S-MEMORY EXIT THEN
    0 _PDD-AT !
    _PDD-BLOCKS
    _PDD-SCRATCH-FREE
    0= IF _PDD-BUF @ _PDD-T @ 2* _PDD-FREE DOC-S-MEMORY EXIT THEN
    _PDD-BUF @ _PDD-I @ _PDD-SLOT@ !  _PDD-T @ _PDD-I @ _PDD-SLOT@ 8 + !
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

: _PDD-CONTENT  ( index doc -- status )
    _PDD-USE
    DUP _PDD-D @ DOC-PART-OF _PDD-SLOT@ _PDD-TEXT          ( index a t m )
    3 PICK _PDD-D @ DOC-BLOCK DUP BLK-KIND@ DOC-B-FIGURE = IF
        BLK-LOC@ DROP NIP NIP NIP NIP
        S" picture " _PDD-NAME SWAP MOVE
        NUM>STR DUP 8 + >R _PDD-NAME 8 + SWAP MOVE
        _PDD-NAME R> _PDD-D @ DOC-CB-FIGURE
    ELSE
        BLK-LOC@ >R                                        ( index a t m off )
        ROT DROP TUCK + -ROT + SWAP R> SWAP                ( index a' u m' )
        _PDD-RUNS NIP
    THEN
    IF DOC-S-OK ELSE DOC-S-MEMORY THEN ;

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

CREATE _PDD-READER RDR-SIZE ALLOT
' _PDD-STRUCTURE _PDD-READER RDR.STRUCTURE-XT !
' _PDD-CONTENT   _PDD-READER RDR.CONTENT-XT !
' _PDD-CLOSE     _PDD-READER RDR.CLOSE-XT !
' _PDD-PART      _PDD-READER RDR.PART-XT !
' _PDD-PICTURE   _PDD-READER RDR.PICTURE-XT !

: PDF-DOC-READER  ( -- reader )  _PDD-READER ;
