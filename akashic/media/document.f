\ =====================================================================
\  media/document.f — a document's blocks, read as a view reaches them
\ =====================================================================
\
\  A document is text read from top to bottom, with its structure: a
\  sequence of blocks (paragraphs, headings, code, rules, figures and the
\  starts of pages), each inside the quotes and list items around it; a
\  page's start sits in none, its text the page's label.  A reader finds the blocks
\  in a media source.  DOC-OPEN runs the reader's structure pass, which
\  keeps each block's kind, its containers, the blank rows before it, and
\  where its text lies, but not the text.  DOC-CONTENT reads one block's
\  text and meanings when a view reaches it, and keeps them until DOC-KEEP
\  gives back the contents outside the view.
\
\  A reader may give a document in parts instead, a PDF a part for each
\  page: its structure pass adds parts, and no blocks, with DOC-ADD-PART,
\  and its part pass adds a part's blocks when DOC-READ-PART asks, in any
\  order.  A part's blocks go where the part lies, after the blocks of
\  the parts before it that are read; a part not read has none, and
\  takes no room.  Block indices count the blocks read, so reading a part
\  moves the blocks after it on; a block's key (BLK-KEY@), given when it
\  is added, never changes, and DOC-KEY>INDEX finds it again.  Each block
\  knows its part, so DOC-GAP finds a part not read between two blocks
\  without a search.
\
\  Memory comes from the caller's memory source, each block sized to what
\  it holds.  When the source refuses, the call says DOC-S-MEMORY.  The
\  document borrows its media source; whoever made the source releases it
\  after DOC-CLOSE.
\
\  Block and container kinds take the values of MegaPad's DOC1 body
\  (SEMANTIC-CONTENT-1), so a producer passes them through unchanged.
\
\  Prefix: DOC- (public), _DOC- (private)
\
\  Public API:
\    DOC-SIZE        ( -- bytes )
\    DOC-OPEN        ( source reader msrc doc -- status )
\    DOC-CLOSE       ( doc -- )
\    DOC-COUNT       ( doc -- blocks )
\    DOC-BLOCK       ( index doc -- block | 0 )
\    DOC-CONTAINERS  ( block doc -- first count )
\    DOC-CONTENT     ( index doc -- content status )
\    DOC-KEEP        ( first end doc -- )
\    DOC-ANCHOR      ( name-a name-u doc -- index | -1 )
\    DOC-KEY>INDEX   ( key doc -- index | -1 )
\    DOC-PARTS       ( doc -- n )
\    DOC-READ-PART   ( part doc -- status )
\    DOC-PART-READ?  ( part doc -- flag )
\    DOC-PART-FIRST  ( part doc -- index )   where its blocks lie, or will
\    DOC-PART-COUNT  ( part doc -- blocks )
\    DOC-PART-OF     ( index doc -- part | -1 )
\    DOC-GAP         ( index last? doc -- part | -1 )
\    DOC-PICTURES?   ( doc -- flag )
\    DOC-PICTURE     ( name-a name-u maker doc -- ok? )
\    DOC-ANCHOR-PART ( name-a name-u doc -- part | -1 )
\    DOC-CONTENTS    ( doc -- entries status )
\    DOC-ENTRY       ( i doc -- level title-a title-u )
\    DOC-ENTRY-GOES  ( i doc -- key target-a target-u )
\    DOC-ENTRY-CLOSED? ( i doc -- flag )
\  A reader adds with DOC-ADD-BLOCK DOC-ADD-CONTAINER DOC-ADD-PART
\  DOC-ADD-ENTRY DOC-CLOSE-ENTRY and
\  fills a block's content with DOC-CB-TEXT DOC-CB-LINK DOC-CB-KIND
\  DOC-CB-FIGURE; it finds a part with DOC-PART-LOC@.
\  A block's fields are BLK-KEY@ BLK-KIND@ BLK-LEVEL@ BLK-ROWS-BEFORE@ BLK-INSIDE@;
\  a container's CNT-KIND@ CNT-WIDTH@ CNT-NUMBER@ CNT-START?; a content's
\  DCT-KIND@ DCT-LEVEL@ DCT-TEXT DCT-MAP DCT-FIGURE DCT-LINK-COUNT
\  DCT-LINK@ DCT-LINK-AT.
\ =====================================================================

REQUIRE ../utils/memory-source.f
REQUIRE ../utils/memory-span.f
REQUIRE ../utils/string.f
REQUIRE source.f

PROVIDED akashic-media-document

0 CONSTANT DOC-S-OK
1 CONSTANT DOC-S-MEMORY      \ the memory source refused
2 CONSTANT DOC-S-READ        \ the media source could not be read
3 CONSTANT DOC-S-INVALID     \ no such block, or no open document
4 CONSTANT DOC-S-LOCKED      \ the source cannot be read without a password

\ Block kinds.
1 CONSTANT DOC-B-PARAGRAPH
2 CONSTANT DOC-B-HEADING
3 CONSTANT DOC-B-CODE
4 CONSTANT DOC-B-RULE
5 CONSTANT DOC-B-FIGURE
6 CONSTANT DOC-B-PAGE

\ Container kinds.
1 CONSTANT DOC-C-QUOTE
2 CONSTANT DOC-C-BULLET
3 CONSTANT DOC-C-NUMBERED

0x544E454D55434F44 CONSTANT _DOC-MAGIC   \ "DOCUMENT"

\ ---------------------------------------------------------------------
\  Records
\ ---------------------------------------------------------------------

\ The document.  The content builder's buffers grow as a reader fills
\ them and stay for the next content.
: _DOC.MAGIC       ( d -- a )        ;
: _DOC.MSRC        ( d -- a )    8 + ;
: _DOC.SOURCE      ( d -- a )   16 + ;
: _DOC.READER      ( d -- a )   24 + ;
: _DOC.STATE       ( d -- a )   32 + ;
: _DOC.BLOCKS-A    ( d -- a )   40 + ;
: _DOC.BLOCKS-CAP  ( d -- a )   48 + ;
: _DOC.COUNT       ( d -- a )   56 + ;
: _DOC.CONTS-A     ( d -- a )   64 + ;
: _DOC.CONTS-CAP   ( d -- a )   72 + ;
: _DOC.CONT-COUNT  ( d -- a )   80 + ;
: _DOC.CACHE-A     ( d -- a )   88 + ;
: _DOC.CACHE-CAP   ( d -- a )   96 + ;
: _DOC.CB-TEXT-A   ( d -- a )  104 + ;
: _DOC.CB-TEXT-CAP ( d -- a )  112 + ;
: _DOC.CB-TEXT-U   ( d -- a )  120 + ;
: _DOC.CB-MAP-A    ( d -- a )  128 + ;
: _DOC.CB-MAP-CAP  ( d -- a )  136 + ;
: _DOC.CB-LINKS-A  ( d -- a )  144 + ;
: _DOC.CB-LINKS-CAP ( d -- a ) 152 + ;
: _DOC.CB-LINKS    ( d -- a )  160 + ;
: _DOC.CB-STR-A    ( d -- a )  168 + ;
: _DOC.CB-STR-CAP  ( d -- a )  176 + ;
: _DOC.CB-STR-U    ( d -- a )  184 + ;
: _DOC.CB-KIND     ( d -- a )  192 + ;
: _DOC.CB-LEVEL    ( d -- a )  200 + ;
: _DOC.CB-FIG-OFF  ( d -- a )  208 + ;
: _DOC.CB-FIG-U    ( d -- a )  216 + ;
: _DOC.CB-OK       ( d -- a )  224 + ;
: _DOC.PARTS-A     ( d -- a )  232 + ;
: _DOC.PARTS-CAP   ( d -- a )  240 + ;
: _DOC.PART-COUNT  ( d -- a )  248 + ;
: _DOC.LAST-KEY    ( d -- a )  256 + ;
: _DOC.READING     ( d -- a )  264 + ;   \ the part being read, or -1
: _DOC.ENTRIES-A   ( d -- a )  272 + ;   \ the contents' entries
: _DOC.ENTRIES-CAP ( d -- a )  280 + ;
: _DOC.ENTRIES-N   ( d -- a )  288 + ;   \ how many, or -1 before they are made
: _DOC.ESTR-A      ( d -- a )  296 + ;   \ their titles' and targets' bytes
: _DOC.ESTR-CAP    ( d -- a )  304 + ;
: _DOC.ESTR-U      ( d -- a )  312 + ;
320 CONSTANT DOC-SIZE

\ A block: its kind and heading level, the blank rows before it and how
\ many of its outermost containers those rows lie inside, its containers,
\ two cells the reader keeps to find its text, its key, and its part, or
\ -1 in a document without parts.
: _BLK.KIND        ( b -- a )        ;
: _BLK.LEVEL       ( b -- a )    8 + ;
: _BLK.ROWS-BEFORE ( b -- a )   16 + ;
: _BLK.INSIDE      ( b -- a )   24 + ;
: _BLK.CONT-FIRST  ( b -- a )   32 + ;
: _BLK.CONT-COUNT  ( b -- a )   40 + ;
: _BLK.LOC-A       ( b -- a )   48 + ;
: _BLK.LOC-B       ( b -- a )   56 + ;
: _BLK.KEY         ( b -- a )   64 + ;
: _BLK.PART        ( b -- a )   72 + ;
80 CONSTANT _BLK-SIZE

: BLK-KEY@         ( block -- key )    _BLK.KEY @ ;
: BLK-KIND@        ( block -- kind )   _BLK.KIND @ ;
: BLK-LEVEL@       ( block -- level )  _BLK.LEVEL @ ;
: BLK-ROWS-BEFORE@ ( block -- rows )   _BLK.ROWS-BEFORE @ ;
: BLK-INSIDE@      ( block -- n )      _BLK.INSIDE @ ;
: BLK-LOC@         ( block -- a b )    DUP _BLK.LOC-A @ SWAP _BLK.LOC-B @ ;
: BLK-ROWS-BEFORE! ( rows block -- )   _BLK.ROWS-BEFORE ! ;
: BLK-INSIDE!      ( n block -- )      _BLK.INSIDE ! ;

\ A container: a quote or a list item, the cells it takes at the left of
\ each of its block's rows, a numbered item's number, and whether this
\ block starts the item.
: _CNT.KIND   ( c -- a )      ;
: _CNT.WIDTH  ( c -- a )  8 + ;
: _CNT.NUMBER ( c -- a ) 16 + ;
: _CNT.START  ( c -- a ) 24 + ;
32 CONSTANT CNT-SIZE

: CNT-KIND@   ( container -- kind )    _CNT.KIND @ ;
: CNT-WIDTH@  ( container -- cells )   _CNT.WIDTH @ ;
: CNT-NUMBER@ ( container -- n )       _CNT.NUMBER @ ;
: CNT-START?  ( container -- flag )    _CNT.START @ 0<> ;
: CNT-WIDTH!  ( cells container -- )   _CNT.WIDTH ! ;

\ A block's content, one allocation: this header, the text, one meaning a
\ byte, the links, and the strings links and a figure name.
: _DCT.BYTES      ( t -- a )        ;
: _DCT.KIND       ( t -- a )    8 + ;
: _DCT.LEVEL      ( t -- a )   16 + ;
: _DCT.TEXT-A     ( t -- a )   24 + ;
: _DCT.TEXT-U     ( t -- a )   32 + ;
: _DCT.MAP-A      ( t -- a )   40 + ;
: _DCT.LINKS-A    ( t -- a )   48 + ;
: _DCT.LINKS      ( t -- a )   56 + ;
: _DCT.FIG-A      ( t -- a )   64 + ;
: _DCT.FIG-U      ( t -- a )   72 + ;
80 CONSTANT _DCT-SIZE

\ A link over the text's bytes START to END, and its target.
: _LNK.START  ( l -- a )      ;
: _LNK.END    ( l -- a )  8 + ;
: _LNK.TARGET ( l -- a ) 16 + ;
: _LNK.U      ( l -- a ) 24 + ;
32 CONSTANT _LNK-SIZE

: DCT-KIND@       ( content -- kind )    _DCT.KIND @ ;
: DCT-LEVEL@      ( content -- level )   _DCT.LEVEL @ ;
: DCT-TEXT        ( content -- a u )     DUP _DCT.TEXT-A @ SWAP _DCT.TEXT-U @ ;
: DCT-MAP         ( content -- a )       _DCT.MAP-A @ ;
: DCT-FIGURE      ( content -- a u )     DUP _DCT.FIG-A @ SWAP _DCT.FIG-U @ ;
: DCT-LINK-COUNT  ( content -- n )       _DCT.LINKS @ ;

\ DCT-LINK@ ( index content -- start end target-a target-u )
: DCT-LINK@  ( index content -- start end target-a target-u )
    _DCT.LINKS-A @ SWAP _LNK-SIZE * +
    DUP _LNK.START @ OVER _LNK.END @ ROT DUP _LNK.TARGET @ SWAP _LNK.U @ ;

VARIABLE _DLA-OFF

\ DCT-LINK-AT ( offset content -- target-a target-u | 0 0 )
\   The target of the link over the text's byte OFFSET, if one is.
: DCT-LINK-AT  ( offset content -- target-a target-u | 0 0 )
    SWAP _DLA-OFF !
    DUP _DCT.LINKS @ 0 ?DO
        DUP _DCT.LINKS-A @ I _LNK-SIZE * +
        DUP _LNK.START @ _DLA-OFF @ > 0=
        OVER _LNK.END @ _DLA-OFF @ > AND IF
            NIP DUP _LNK.TARGET @ SWAP _LNK.U @ UNLOOP EXIT
        THEN DROP
    LOOP
    DROP 0 0 ;

\ A reader: its structure pass ( doc -- status ), which adds every block
\ with DOC-ADD-BLOCK and DOC-ADD-CONTAINER, or adds parts with
\ DOC-ADD-PART; its content pass ( index doc -- status ), which fills the
\ builder with DOC-CB-TEXT, DOC-CB-LINK, DOC-CB-KIND and DOC-CB-FIGURE;
\ what it gives back ( doc -- ); its part pass ( part doc -- status ),
\ which adds a part's blocks as the structure pass adds blocks, or 0 for a
\ reader that adds no parts; its pictures ( name-a name-u maker doc --
\ ok? ), which fills a maker (media/picture.f) for a figure's picture the
\ document holds itself, or 0 for a reader whose figures name files; and
\ its anchors ( name-a name-u doc -- part index ), where a link within a
\ document in parts goes: the part, perhaps not read yet, and, once that
\ part is read, the block in it the link shows first, each -1 for none;
\ or 0; and its contents ( doc -- status ), which adds the document's
\ entries with DOC-ADD-ENTRY, or 0 for the headings.
: RDR.STRUCTURE-XT ( r -- a )        ;
: RDR.CONTENT-XT   ( r -- a )    8 + ;
: RDR.CLOSE-XT     ( r -- a )   16 + ;
: RDR.PART-XT      ( r -- a )   24 + ;
: RDR.PICTURE-XT   ( r -- a )   32 + ;
: RDR.ANCHOR-XT    ( r -- a )   40 + ;
: RDR.CONTENTS-XT  ( r -- a )   48 + ;
56 CONSTANT RDR-SIZE

\ A contents entry: its level, from 0 at the top; its title's and its
\ target's offsets and lengths among the entries' bytes; the key of the
\ block it goes to, or 0 when it goes where its target does; and whether
\ it starts closed.
: _ENT.LEVEL   ( e -- a )        ;
: _ENT.TITLE   ( e -- a )    8 + ;
: _ENT.TITLE-U ( e -- a )   16 + ;
: _ENT.TARGET  ( e -- a )   24 + ;
: _ENT.TARGET-U ( e -- a )  32 + ;
: _ENT.KEY     ( e -- a )   40 + ;
: _ENT.CLOSED  ( e -- a )   48 + ;
56 CONSTANT _ENT-SIZE

\ A part: two cells the reader keeps to find it, where its blocks lie
\ (or will, when it is read), how many there are, and whether it is read.
: _PRT.LOC-A  ( p -- a )        ;
: _PRT.LOC-B  ( p -- a )    8 + ;
: _PRT.FIRST  ( p -- a )   16 + ;
: _PRT.COUNT  ( p -- a )   24 + ;
: _PRT.READ   ( p -- a )   32 + ;
40 CONSTANT _PRT-SIZE

\ ---------------------------------------------------------------------
\  Memory
\ ---------------------------------------------------------------------

VARIABLE _DOC-D

: _DOC-ALLOC  ( bytes -- a|0 )  _DOC-D @ _DOC.MSRC @ MSRC-ALLOC ;
: _DOC-FREE   ( a bytes -- )
    OVER 0= IF 2DROP EXIT THEN _DOC-D @ _DOC.MSRC @ MSRC-FREE ;

VARIABLE _DGW-A
VARIABLE _DGW-CAP
VARIABLE _DGW-NEW

\ _DOC-GROW ( need a-field cap-field -- ok? )
\   Make the buffer whose address and capacity are in the two fields hold
\   at least NEED bytes, keeping its contents.  It at least doubles, so
\   appending costs constant time on average.
: _DOC-GROW  ( need a-field cap-field -- ok? )
    _DGW-CAP ! _DGW-A !
    DUP _DGW-CAP @ @ U> 0= IF DROP -1 EXIT THEN
    _DGW-CAP @ @ 2* MAX 256 MAX
    DUP _DOC-ALLOC DUP 0= IF 2DROP 0 EXIT THEN _DGW-NEW !
    _DGW-A @ @ ?DUP IF
        DUP _DGW-NEW @ _DGW-CAP @ @ MOVE
        _DGW-CAP @ @ _DOC-FREE
    THEN
    _DGW-NEW @ _DGW-A @ !
    _DGW-CAP @ ! -1 ;

\ ---------------------------------------------------------------------
\  Blocks and containers, as a reader adds them
\ ---------------------------------------------------------------------

\ DOC-ADD-BLOCK ( kind level loc-a loc-b doc -- block | 0 )
\   Add the next block, with a key of its own.  Its rows before and
\   containers start empty.  The address stays valid only until the next
\   block is added.  A document in parts takes blocks only from its part
\   pass.
: DOC-ADD-BLOCK  ( kind level loc-a loc-b doc -- block | 0 )
    _DOC-D !
    _DOC-D @ _DOC.PART-COUNT @ 0<> _DOC-D @ _DOC.READING @ 0< AND IF
        2DROP 2DROP 0 EXIT
    THEN
    _DOC-D @ _DOC.COUNT @ 1+ _BLK-SIZE *
    _DOC-D @ _DOC.BLOCKS-A _DOC-D @ _DOC.BLOCKS-CAP _DOC-GROW 0= IF
        2DROP 2DROP 0 EXIT
    THEN
    _DOC-D @ _DOC.BLOCKS-A @ _DOC-D @ _DOC.COUNT @ _BLK-SIZE * +
    >R
    R@ _BLK.LOC-B ! R@ _BLK.LOC-A ! R@ _BLK.LEVEL ! R@ _BLK.KIND !
    0 R@ _BLK.ROWS-BEFORE ! 0 R@ _BLK.INSIDE !
    _DOC-D @ _DOC.CONT-COUNT @ R@ _BLK.CONT-FIRST ! 0 R@ _BLK.CONT-COUNT !
    1 _DOC-D @ _DOC.LAST-KEY +!  _DOC-D @ _DOC.LAST-KEY @ R@ _BLK.KEY !
    _DOC-D @ _DOC.READING @ R@ _BLK.PART !
    1 _DOC-D @ _DOC.COUNT +!
    R> ;

: _DOC-PART  ( part -- p )  _PRT-SIZE * _DOC-D @ _DOC.PARTS-A @ + ;

\ DOC-ADD-PART ( loc-a loc-b doc -- ok? )
\   Add a part after the parts so far, not yet read.  LOC-A and LOC-B are
\   the reader's, to find it.  False when memory refuses, or when the
\   document has blocks or a part is being read: a structure pass adds
\   parts or blocks, not both.
: DOC-ADD-PART  ( loc-a loc-b doc -- ok? )
    _DOC-D !
    _DOC-D @ _DOC.COUNT @ _DOC-D @ _DOC.READING @ 0< 0= OR IF 2DROP 0 EXIT THEN
    _DOC-D @ _DOC.PART-COUNT @ 1+ _PRT-SIZE *
    _DOC-D @ _DOC.PARTS-A _DOC-D @ _DOC.PARTS-CAP _DOC-GROW 0= IF 2DROP 0 EXIT THEN
    _DOC-D @ _DOC.PART-COUNT @ _DOC-PART >R
    R@ _PRT.LOC-B ! R@ _PRT.LOC-A !
    _DOC-D @ _DOC.COUNT @ R@ _PRT.FIRST !  0 R@ _PRT.COUNT !  0 R> _PRT.READ !
    1 _DOC-D @ _DOC.PART-COUNT +!  -1 ;

\ DOC-ADD-CONTAINER ( kind width number start? doc -- ok? )
\   Add a container, outermost first, to the block added last: false when
\   memory is refused, or when that block is a page's start, which sits in
\   no container.
: DOC-ADD-CONTAINER  ( kind width number start? doc -- ok? )
    _DOC-D !
    _DOC-D @ _DOC.COUNT @ 0= IF 2DROP 2DROP 0 EXIT THEN
    _DOC-D @ _DOC.BLOCKS-A @ _DOC-D @ _DOC.COUNT @ 1- _BLK-SIZE * +
    BLK-KIND@ DOC-B-PAGE = IF 2DROP 2DROP 0 EXIT THEN
    _DOC-D @ _DOC.CONT-COUNT @ 1+ CNT-SIZE *
    _DOC-D @ _DOC.CONTS-A _DOC-D @ _DOC.CONTS-CAP _DOC-GROW 0= IF
        2DROP 2DROP 0 EXIT
    THEN
    _DOC-D @ _DOC.CONTS-A @ _DOC-D @ _DOC.CONT-COUNT @ CNT-SIZE * +
    >R
    0<> R@ _CNT.START ! R@ _CNT.NUMBER ! R@ _CNT.WIDTH ! R> _CNT.KIND !
    1 _DOC-D @ _DOC.CONT-COUNT +!
    _DOC-D @ _DOC.BLOCKS-A @ _DOC-D @ _DOC.COUNT @ 1- _BLK-SIZE * +
    _BLK.CONT-COUNT 1 SWAP +!
    -1 ;

: DOC-COUNT  ( doc -- blocks )  _DOC.COUNT @ ;

: DOC-BLOCK  ( index doc -- block | 0 )
    2DUP _DOC.COUNT @ U< 0= IF 2DROP 0 EXIT THEN
    _DOC.BLOCKS-A @ SWAP _BLK-SIZE * + ;

: DOC-CONTAINERS  ( block doc -- first count )
    _DOC.CONTS-A @ OVER _BLK.CONT-FIRST @ CNT-SIZE * +
    SWAP _BLK.CONT-COUNT @ ;

\ A part's cells, for its reader; PART is below DOC-PARTS.
: DOC-PART-LOC@  ( part doc -- loc-a loc-b )
    _DOC.PARTS-A @ SWAP _PRT-SIZE * + DUP _PRT.LOC-A @ SWAP _PRT.LOC-B @ ;

: DOC-STATE@   ( doc -- state )   _DOC.STATE @ ;
: DOC-STATE!   ( state doc -- )   _DOC.STATE ! ;
: DOC-SOURCE@  ( doc -- source )  _DOC.SOURCE @ ;
: DOC-MSRC@    ( doc -- msrc )    _DOC.MSRC @ ;

\ ---------------------------------------------------------------------
\  The content builder, as a reader fills it
\ ---------------------------------------------------------------------

: _DOC-CB-RESET  ( -- )
    0 _DOC-D @ _DOC.CB-TEXT-U ! 0 _DOC-D @ _DOC.CB-LINKS !
    0 _DOC-D @ _DOC.CB-STR-U !
    0 _DOC-D @ _DOC.CB-KIND ! 0 _DOC-D @ _DOC.CB-LEVEL !
    0 _DOC-D @ _DOC.CB-FIG-OFF ! 0 _DOC-D @ _DOC.CB-FIG-U !
    -1 _DOC-D @ _DOC.CB-OK ! ;

\ DOC-CB-U ( doc -- u )  The text's length so far, where the next byte goes.
: DOC-CB-U  ( doc -- u )  _DOC.CB-TEXT-U @ ;

\ DOC-CB-TEXT ( a u meaning doc -- ok? )
\   Add text whose every byte has MEANING (TSTY-*, 0 for plain).
: DOC-CB-TEXT  ( a u meaning doc -- ok? )
    _DOC-D !
    OVER _DOC-D @ _DOC.CB-TEXT-U @ +
    DUP _DOC-D @ _DOC.CB-TEXT-A _DOC-D @ _DOC.CB-TEXT-CAP _DOC-GROW
    SWAP _DOC-D @ _DOC.CB-MAP-A _DOC-D @ _DOC.CB-MAP-CAP _DOC-GROW AND 0= IF
        DROP 2DROP 0 _DOC-D @ _DOC.CB-OK ! 0 EXIT
    THEN
    >R
    _DOC-D @ _DOC.CB-MAP-A @ _DOC-D @ _DOC.CB-TEXT-U @ + OVER R> FILL
    _DOC-D @ _DOC.CB-TEXT-A @ _DOC-D @ _DOC.CB-TEXT-U @ + SWAP
    DUP _DOC-D @ _DOC.CB-TEXT-U +! MOVE -1 ;

: _DOC-CB-STRING  ( a u -- offset ok? )
    _DOC-D @ _DOC.CB-STR-U @
    OVER _DOC-D @ _DOC.CB-STR-U @ +
    _DOC-D @ _DOC.CB-STR-A _DOC-D @ _DOC.CB-STR-CAP _DOC-GROW 0= IF
        NIP NIP 0 _DOC-D @ _DOC.CB-OK ! 0 EXIT
    THEN
    >R _DOC-D @ _DOC.CB-STR-A @ R@ + SWAP
    DUP _DOC-D @ _DOC.CB-STR-U +! MOVE R> -1 ;

\ DOC-CB-LINK ( start end target-a target-u doc -- ok? )
\   A link over the text's bytes START to END.
: DOC-CB-LINK  ( start end target-a target-u doc -- ok? )
    _DOC-D !
    _DOC-CB-STRING 0= IF 2DROP DROP 0 EXIT THEN >R
    _DOC-D @ _DOC.CB-LINKS @ 1+ _LNK-SIZE *
    _DOC-D @ _DOC.CB-LINKS-A _DOC-D @ _DOC.CB-LINKS-CAP _DOC-GROW 0= IF
        R> DROP 2DROP 0 _DOC-D @ _DOC.CB-OK ! 0 EXIT
    THEN
    _DOC-D @ _DOC.CB-LINKS-A @ _DOC-D @ _DOC.CB-LINKS @ _LNK-SIZE * +
    >R R@ _LNK.END ! R@ _LNK.START !
    R> R> OVER _LNK.TARGET !
    \ The target's length is the string area's growth since it began.
    _DOC-D @ _DOC.CB-STR-U @ OVER _LNK.TARGET @ - SWAP _LNK.U !
    1 _DOC-D @ _DOC.CB-LINKS +! -1 ;

\ DOC-CB-KIND ( kind level doc -- )  The block's kind, when its content
\   shows it to be another than its structure did, as a lone picture does.
: DOC-CB-KIND  ( kind level doc -- )
    >R R@ _DOC.CB-LEVEL ! R> _DOC.CB-KIND ! ;

\ DOC-CB-FIGURE ( a u doc -- ok? )  A figure's picture: what names it.
: DOC-CB-FIGURE  ( a u doc -- ok? )
    _DOC-D ! DUP >R _DOC-CB-STRING 0= IF DROP R> DROP 0 EXIT THEN
    _DOC-D @ _DOC.CB-FIG-OFF ! R> _DOC-D @ _DOC.CB-FIG-U ! -1 ;

VARIABLE _DCE-T
VARIABLE _DCE-BYTES

\ _DOC-CB-END ( -- content | 0 )
\   Copy the builder into one exact allocation.
: _DOC-CB-END  ( -- content | 0 )
    _DOC-D @ _DOC.CB-OK @ 0= IF 0 EXIT THEN
    _DCT-SIZE
    _DOC-D @ _DOC.CB-TEXT-U @ 2* 7 + 7 INVERT AND +
    _DOC-D @ _DOC.CB-LINKS @ _LNK-SIZE * +
    _DOC-D @ _DOC.CB-STR-U @ + DUP _DCE-BYTES !
    _DOC-ALLOC DUP 0= IF EXIT THEN _DCE-T !
    _DCE-BYTES @ _DCE-T @ _DCT.BYTES !
    _DOC-D @ _DOC.CB-KIND @ _DCE-T @ _DCT.KIND !
    _DOC-D @ _DOC.CB-LEVEL @ _DCE-T @ _DCT.LEVEL !
    _DCE-T @ _DCT-SIZE + DUP _DCE-T @ _DCT.TEXT-A !
    _DOC-D @ _DOC.CB-TEXT-U @ _DCE-T @ _DCT.TEXT-U !
    _DOC-D @ _DOC.CB-TEXT-U @ + DUP _DCE-T @ _DCT.MAP-A !
    _DOC-D @ _DOC.CB-TEXT-U @ + 7 + 7 INVERT AND DUP _DCE-T @ _DCT.LINKS-A !
    _DOC-D @ _DOC.CB-LINKS @ _DCE-T @ _DCT.LINKS !
    _DOC-D @ _DOC.CB-LINKS @ _LNK-SIZE * +            ( strings )
    _DOC-D @ _DOC.CB-TEXT-U @ IF
        _DOC-D @ _DOC.CB-TEXT-A @ _DCE-T @ _DCT.TEXT-A @
            _DOC-D @ _DOC.CB-TEXT-U @ MOVE
        _DOC-D @ _DOC.CB-MAP-A @ _DCE-T @ _DCT.MAP-A @
            _DOC-D @ _DOC.CB-TEXT-U @ MOVE
    THEN
    _DOC-D @ _DOC.CB-STR-U @ IF
        _DOC-D @ _DOC.CB-STR-A @ OVER _DOC-D @ _DOC.CB-STR-U @ MOVE
    THEN
    _DOC-D @ _DOC.CB-LINKS @ 0 ?DO
        _DOC-D @ _DOC.CB-LINKS-A @ I _LNK-SIZE * +
        _DCE-T @ _DCT.LINKS-A @ I _LNK-SIZE * +
        OVER _LNK.START @ OVER _LNK.START !
        OVER _LNK.END @ OVER _LNK.END !
        OVER _LNK.U @ OVER _LNK.U !
        SWAP _LNK.TARGET @ 2 PICK + SWAP _LNK.TARGET !
    LOOP
    DUP _DOC-D @ _DOC.CB-FIG-OFF @ + _DCE-T @ _DCT.FIG-A !
    DROP
    _DOC-D @ _DOC.CB-FIG-U @ _DCE-T @ _DCT.FIG-U !
    _DCE-T @ ;

\ ---------------------------------------------------------------------
\  Opening and closing
\ ---------------------------------------------------------------------

: _DOC-CACHE-SLOT  ( index -- a )  CELLS _DOC-D @ _DOC.CACHE-A @ + ;

: _DOC-FREE-CONTENT  ( index -- )
    _DOC-CACHE-SLOT DUP @ ?DUP IF DUP _DCT.BYTES @ _DOC-FREE THEN 0 SWAP ! ;

: _DOC-FREE-ALL  ( -- )
    _DOC-D @ _DOC.CACHE-A @ IF
        _DOC-D @ _DOC.COUNT @ 0 ?DO I _DOC-FREE-CONTENT LOOP
    THEN
    _DOC-D @ _DOC.READER @ ?DUP IF
        RDR.CLOSE-XT @ ?DUP IF _DOC-D @ SWAP EXECUTE THEN
    THEN
    _DOC-D @ _DOC.BLOCKS-A @ _DOC-D @ _DOC.BLOCKS-CAP @ _DOC-FREE
    _DOC-D @ _DOC.CONTS-A @ _DOC-D @ _DOC.CONTS-CAP @ _DOC-FREE
    _DOC-D @ _DOC.CACHE-A @ _DOC-D @ _DOC.CACHE-CAP @ _DOC-FREE
    _DOC-D @ _DOC.CB-TEXT-A @ _DOC-D @ _DOC.CB-TEXT-CAP @ _DOC-FREE
    _DOC-D @ _DOC.CB-MAP-A @ _DOC-D @ _DOC.CB-MAP-CAP @ _DOC-FREE
    _DOC-D @ _DOC.CB-LINKS-A @ _DOC-D @ _DOC.CB-LINKS-CAP @ _DOC-FREE
    _DOC-D @ _DOC.CB-STR-A @ _DOC-D @ _DOC.CB-STR-CAP @ _DOC-FREE
    _DOC-D @ _DOC.PARTS-A @ _DOC-D @ _DOC.PARTS-CAP @ _DOC-FREE
    _DOC-D @ _DOC.ENTRIES-A @ _DOC-D @ _DOC.ENTRIES-CAP @ _DOC-FREE
    _DOC-D @ _DOC.ESTR-A @ _DOC-D @ _DOC.ESTR-CAP @ _DOC-FREE
    _DOC-D @ DOC-SIZE 0 FILL ;

: _DOC-CLOSE  ( doc -- )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF DROP EXIT THEN
    _DOC-D ! _DOC-FREE-ALL ;

: _DOC-OPEN  ( source reader msrc doc -- status )
    DUP _DOC-D ! DOC-SIZE 0 FILL
    DUP MSRC-VALID? 0= IF DROP 2DROP DOC-S-INVALID EXIT THEN
    _DOC-D @ _DOC.MSRC !
    OVER MEDSRC-VALID? 0= IF 2DROP DOC-S-INVALID EXIT THEN
    _DOC-D @ _DOC.READER ! _DOC-D @ _DOC.SOURCE !
    _DOC-MAGIC _DOC-D @ _DOC.MAGIC !  -1 _DOC-D @ _DOC.READING !
    -1 _DOC-D @ _DOC.ENTRIES-N !
    _DOC-D @ DUP _DOC.READER @ RDR.STRUCTURE-XT @ EXECUTE
    ?DUP IF _DOC-FREE-ALL EXIT THEN
    _DOC-D @ _DOC.COUNT @ ?DUP IF
        CELLS DUP _DOC-ALLOC DUP 0= IF
            2DROP _DOC-FREE-ALL DOC-S-MEMORY EXIT
        THEN
        2DUP SWAP 0 FILL
        _DOC-D @ _DOC.CACHE-A ! _DOC-D @ _DOC.CACHE-CAP !
    THEN
    DOC-S-OK ;

\ ---------------------------------------------------------------------
\  Content
\ ---------------------------------------------------------------------

: _DOC-CONTENT  ( index doc -- content status )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF 2DROP 0 DOC-S-INVALID EXIT THEN
    _DOC-D !
    DUP _DOC-D @ _DOC.COUNT @ U< 0= IF DROP 0 DOC-S-INVALID EXIT THEN
    DUP _DOC-CACHE-SLOT @ ?DUP IF NIP DOC-S-OK EXIT THEN
    _DOC-CB-RESET
    DUP _DOC-D @ _DOC.BLOCKS-A @ SWAP _BLK-SIZE * +
    DUP _BLK.KIND @ _DOC-D @ _DOC.CB-KIND ! _BLK.LEVEL @ _DOC-D @ _DOC.CB-LEVEL !
    DUP _DOC-D @ DUP _DOC.READER @ RDR.CONTENT-XT @ EXECUTE
    ?DUP IF NIP 0 SWAP EXIT THEN
    _DOC-CB-END DUP 0= IF NIP DOC-S-MEMORY EXIT THEN
    DUP ROT _DOC-CACHE-SLOT ! DOC-S-OK ;

: _DOC-KEEP  ( first end doc -- )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF DROP 2DROP EXIT THEN
    _DOC-D !
    _DOC-D @ _DOC.COUNT @ 0 ?DO
        I 2 PICK < I 2 PICK < 0= OR IF I _DOC-FREE-CONTENT THEN
    LOOP
    2DROP ;

\ ---------------------------------------------------------------------
\  Parts
\ ---------------------------------------------------------------------

VARIABLE _DRP-PART   \ the part being read
VARIABLE _DRP-OLD    \ the blocks before it was read
VARIABLE _DRP-OLDC   \ the containers before it was read
VARIABLE _DRP-N      \ the blocks it added
VARIABLE _DRP-AT     \ where they go
VARIABLE _DRP-TMP

\ Give back what a part that failed to read added.
: _DOC-UNDO  ( status -- status )
    _DRP-OLD @ _DOC-D @ _DOC.COUNT !  _DRP-OLDC @ _DOC-D @ _DOC.CONT-COUNT ! ;

\ Move the N blocks added last, at the end, to index AT, and the blocks
\ from AT on after them; their content slots likewise, the new ones empty.
\ False when memory refuses the move's room.
: _DOC-ROTATE  ( -- ok? )
    _DRP-N @ _BLK-SIZE * DUP _DOC-ALLOC DUP _DRP-TMP ! 0= IF DROP 0 EXIT THEN
    _DOC-D @ _DOC.BLOCKS-A @ _DRP-OLD @ _BLK-SIZE * +  _DRP-TMP @  2 PICK MOVE
    _DOC-D @ _DOC.BLOCKS-A @ _DRP-AT @ _BLK-SIZE * +  DUP 2 PICK +
        _DRP-OLD @ _DRP-AT @ - _BLK-SIZE * MOVE
    _DRP-TMP @ _DOC-D @ _DOC.BLOCKS-A @ _DRP-AT @ _BLK-SIZE * +  2 PICK MOVE
    _DRP-TMP @ SWAP _DOC-FREE
    _DOC-D @ _DOC.CACHE-A @ _DRP-AT @ CELLS +  DUP _DRP-N @ CELLS +
        _DRP-OLD @ _DRP-AT @ - CELLS MOVE
    _DOC-D @ _DOC.CACHE-A @ _DRP-AT @ CELLS +  _DRP-N @ CELLS 0 FILL
    -1 ;

\ DOC-READ-PART ( part doc -- status )
\   Read part PART's blocks, which go where the part lies; the blocks
\   after it, and where the parts after it lie, move on by as many.  A part
\   read already is left as it is.  When the reader fails, or memory
\   refuses, the part stays unread and the document as it was.  The part
\   pass only adds the part's blocks and their containers.
: _DOC-READ-PART  ( part doc -- status )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF 2DROP DOC-S-INVALID EXIT THEN
    _DOC-D !
    DUP _DOC-D @ _DOC.PART-COUNT @ U< 0= IF DROP DOC-S-INVALID EXIT THEN
    DUP _DOC-PART _PRT.READ @ IF DROP DOC-S-OK EXIT THEN
    _DOC-D @ _DOC.READER @ RDR.PART-XT @ 0= IF DROP DOC-S-INVALID EXIT THEN
    _DRP-PART !
    _DOC-D @ _DOC.COUNT @ _DRP-OLD !  _DOC-D @ _DOC.CONT-COUNT @ _DRP-OLDC !
    _DRP-PART @ _DOC-D @ _DOC.READING !
    _DRP-PART @ _DOC-D @ DUP >R DUP _DOC.READER @ RDR.PART-XT @ EXECUTE
    R> _DOC-D !  -1 _DOC-D @ _DOC.READING !
    ?DUP IF _DOC-UNDO EXIT THEN
    _DOC-D @ _DOC.COUNT @ _DRP-OLD @ - _DRP-N !
    _DRP-PART @ _DOC-PART _PRT.FIRST @ _DRP-AT !
    _DRP-N @ IF
        _DOC-D @ _DOC.COUNT @ CELLS _DOC-D @ _DOC.CACHE-A _DOC-D @ _DOC.CACHE-CAP _DOC-GROW
        0= IF DOC-S-MEMORY _DOC-UNDO EXIT THEN
        _DOC-ROTATE 0= IF DOC-S-MEMORY _DOC-UNDO EXIT THEN
    THEN
    _DRP-PART @ _DOC-PART  _DRP-N @ OVER _PRT.COUNT !  -1 SWAP _PRT.READ !
    _DOC-D @ _DOC.PART-COUNT @ _DRP-PART @ 1+ ?DO
        _DRP-N @ I _DOC-PART _PRT.FIRST +!
    LOOP
    DOC-S-OK ;

: DOC-PARTS  ( doc -- n )  _DOC.PART-COUNT @ ;

\ A part's record, PART below DOC-PARTS.
: _DOC-PART-IN  ( part doc -- p )  _DOC.PARTS-A @ SWAP _PRT-SIZE * + ;

: DOC-PART-READ?  ( part doc -- flag )  _DOC-PART-IN _PRT.READ @ 0<> ;
: DOC-PART-FIRST  ( part doc -- index )  _DOC-PART-IN _PRT.FIRST @ ;
: DOC-PART-COUNT  ( part doc -- blocks )  _DOC-PART-IN _PRT.COUNT @ ;

\ DOC-PART-OF ( index doc -- part | -1 )
\   The part block INDEX lies in, or -1 for none or no such block.
: DOC-PART-OF  ( index doc -- part | -1 )
    DOC-BLOCK ?DUP IF _BLK.PART @ ELSE -1 THEN ;

\ DOC-GAP ( index last? doc -- part | -1 )
\   A part not read whose blocks would lie just before block INDEX, or
\   after the last block for INDEX = DOC-COUNT: of the parts between those
\   of blocks INDEX - 1 and INDEX, the first not read, or, when LAST?, the
\   last.  Only parts read and empty lie between them besides, so this
\   looks at none in most places.
: DOC-GAP  ( index last? doc -- part | -1 )
    DUP DOC-PARTS 0= IF DROP 2DROP -1 EXIT THEN
    >R SWAP 0 MAX R@ DOC-COUNT MIN                       ( last? index )
    DUP 1- R@ DOC-PART-OF                                ( last? index q )
    SWAP DUP R@ DOC-COUNT < IF R@ DOC-PART-OF ELSE DROP R@ DOC-PARTS THEN
    ROT IF                                               ( q p )
        BEGIN 1- 2DUP < WHILE
            DUP R@ DOC-PART-READ? 0= IF NIP R> DROP EXIT THEN
        REPEAT
    ELSE
        SWAP
        BEGIN 1+ 2DUP > WHILE
            DUP R@ DOC-PART-READ? 0= IF NIP R> DROP EXIT THEN
        REPEAT
    THEN
    2DROP R> DROP -1 ;

\ ---------------------------------------------------------------------
\  Pictures a document holds
\ ---------------------------------------------------------------------

\ DOC-PICTURES? ( doc -- flag )
\   Whether the document holds its figures' pictures itself, as a PDF
\   does, rather than naming files.
: DOC-PICTURES?  ( doc -- flag )  _DOC.READER @ RDR.PICTURE-XT @ 0<> ;

\ DOC-PICTURE ( name-a name-u maker doc -- ok? )
\   Fill MAKER (media/picture.f) for the picture a figure names, which the
\   document holds; false when it holds none of that name, or memory is
\   refused.  The maker's user gives it back with PIC-MAKER-FREE, before
\   the document is closed.
: DOC-PICTURE  ( name-a name-u maker doc -- ok? )
    DUP _DOC.READER @ RDR.PICTURE-XT @ ?DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    EXECUTE ;

\ DOC-ANCHOR-PART ( name-a name-u doc -- part | -1 )
\   The part a link within a document in parts names after its "#", as
\   its reader resolves it, perhaps a part not read yet; -1 for none.
\   Its reader may read the source to find it.  Once the part is read,
\   DOC-ANCHOR gives the block in it.
: DOC-ANCHOR-PART  ( name-a name-u doc -- part | -1 )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF DROP 2DROP -1 EXIT THEN
    DUP _DOC.READER @ RDR.ANCHOR-XT @ ?DUP 0= IF DROP 2DROP -1 EXIT THEN
    EXECUTE DROP ;

\ DOC-KEY>INDEX ( key doc -- index | -1 )   The block with KEY, if read.
: DOC-KEY>INDEX  ( key doc -- index | -1 )
    DUP _DOC.BLOCKS-A @ _BLK.KEY SWAP _DOC.COUNT @ 0 ?DO       ( key a )
        2DUP @ = IF 2DROP I UNLOOP EXIT THEN _BLK-SIZE +
    LOOP 2DROP -1 ;

\ ---------------------------------------------------------------------
\  Anchors
\ ---------------------------------------------------------------------
\
\  A heading's anchor is its text in lower case, with spaces made hyphens
\  and other ASCII punctuation but hyphens and underscores left out; a
\  heading whose anchor an earlier one has takes "-1", "-2" and so on, as
\  GitHub names them.  A reader that resolves its own links within the
\  document (RDR.ANCHOR-XT) places them instead, in the parts it has read.

VARIABLE _DAN-NAME-A
VARIABLE _DAN-NAME-U
VARIABLE _DAN-SEEN-A      \ the anchors so far, each a length cell and bytes
VARIABLE _DAN-SEEN-CAP
VARIABLE _DAN-SEEN-U
VARIABLE _DAN-SLUG-A
VARIABLE _DAN-SLUG-CAP
VARIABLE _DAN-SLUG-U
VARIABLE _DAN-FOUND
VARIABLE _DAN-NEW
VARIABLE _DAN-I

: _DAN-KEEP?  ( c -- flag )
    DUP 128 U< 0= IF DROP -1 EXIT THEN
    DUP 48 58 WITHIN IF DROP -1 EXIT THEN
    DUP 65 91 WITHIN IF DROP -1 EXIT THEN
    DUP 97 123 WITHIN IF DROP -1 EXIT THEN
    DUP 45 = SWAP 95 = OR ;

\ _DAN-SLUG ( a u -- ok? )  The anchor of a heading's text, in the slug buffer.
: _DAN-SLUG  ( a u -- ok? )
    DUP 16 + _DAN-SLUG-A _DAN-SLUG-CAP _DOC-GROW 0= IF 2DROP 0 EXIT THEN
    0 _DAN-SLUG-U !
    0 ?DO
        DUP I + C@
        DUP 32 = IF DROP 45 THEN
        DUP 65 91 WITHIN IF 32 + THEN
        DUP _DAN-KEEP? IF
            _DAN-SLUG-A @ _DAN-SLUG-U @ + C! 1 _DAN-SLUG-U +!
        ELSE DROP THEN
    LOOP
    DROP -1 ;

VARIABLE _DAN-P
VARIABLE _DAN-LEFT
VARIABLE _DAN-C

\ How many earlier anchors equal the slug.
: _DAN-COUNT  ( -- n )
    0 _DAN-C ! _DAN-SEEN-A @ _DAN-P ! _DAN-SEEN-U @ _DAN-LEFT !
    BEGIN _DAN-LEFT @ 0> WHILE
        _DAN-P @ @
        _DAN-P @ CELL+ OVER _DAN-SLUG-A @ _DAN-SLUG-U @ STR-STR= IF
            1 _DAN-C +!
        THEN
        7 + 7 INVERT AND CELL+ DUP _DAN-P +! NEGATE _DAN-LEFT +!
    REPEAT
    _DAN-C @ ;

: _DAN-REMEMBER  ( -- ok? )
    _DAN-SEEN-U @ _DAN-SLUG-U @ + 16 +
    _DAN-SEEN-A _DAN-SEEN-CAP _DOC-GROW 0= IF 0 EXIT THEN
    _DAN-SLUG-U @ _DAN-SEEN-A @ _DAN-SEEN-U @ + !
    _DAN-SLUG-A @ _DAN-SEEN-A @ _DAN-SEEN-U @ + CELL+ _DAN-SLUG-U @ MOVE
    _DAN-SLUG-U @ 7 + 7 INVERT AND CELL+ _DAN-SEEN-U +! -1 ;

\ The decimal number the text holds, and whether it holds only digits.
: _DAN-NUMBER  ( a u -- n ok? )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    0 -ROT 0 ?DO
        DUP I + C@ DUP 48 58 WITHIN 0= IF 2DROP 0 UNLOOP EXIT THEN
        48 - ROT 10 * + SWAP
    LOOP DROP -1 ;

\ Does the slug, with the suffix N earlier equal anchors give it, equal
\ the name asked for?
VARIABLE _DAN-N
: _DAN-MATCH?  ( n -- flag )
    DUP _DAN-N !
    0= IF _DAN-SLUG-A @ _DAN-SLUG-U @ _DAN-NAME-A @ _DAN-NAME-U @ STR-STR= EXIT THEN
    _DAN-NAME-U @ _DAN-SLUG-U @ U> 0= IF 0 EXIT THEN
    _DAN-SLUG-A @ _DAN-SLUG-U @ _DAN-NAME-A @ _DAN-SLUG-U @ STR-STR= 0= IF 0 EXIT THEN
    _DAN-NAME-A @ _DAN-NAME-U @ _DAN-SLUG-U @ /STRING
    DUP 2 < IF 2DROP 0 EXIT THEN
    OVER C@ 45 <> IF 2DROP 0 EXIT THEN 1 /STRING
    \ The suffix's number, written without leading zeros.
    OVER C@ 48 = OVER 1 > AND IF 2DROP 0 EXIT THEN
    _DAN-NUMBER 0= IF DROP 0 EXIT THEN
    _DAN-N @ = ;

: _DAN-FREE  ( -- )
    _DAN-SEEN-A @ _DAN-SEEN-CAP @ _DOC-FREE
    _DAN-SLUG-A @ _DAN-SLUG-CAP @ _DOC-FREE
    0 _DAN-SEEN-A ! 0 _DAN-SEEN-CAP ! 0 _DAN-SLUG-A ! 0 _DAN-SLUG-CAP ! ;

: _DOC-ANCHOR  ( name-a name-u doc -- index | -1 )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF DROP 2DROP -1 EXIT THEN
    DUP _DOC.READER @ RDR.ANCHOR-XT @ ?DUP IF EXECUTE NIP EXIT THEN
    _DOC-D ! _DAN-NAME-U ! _DAN-NAME-A !
    0 _DAN-SEEN-A ! 0 _DAN-SEEN-CAP ! 0 _DAN-SEEN-U !
    0 _DAN-SLUG-A ! 0 _DAN-SLUG-CAP ! -1 _DAN-FOUND !
    _DOC-D @ _DOC.COUNT @ 0 ?DO
        I _DAN-I !
        _DAN-I @ _DOC-D @ DOC-BLOCK BLK-KIND@ DOC-B-HEADING = IF
            _DAN-I @ _DOC-CACHE-SLOT @ 0= _DAN-NEW !
            _DAN-I @ _DOC-D @ _DOC-CONTENT IF DROP LEAVE THEN
            DCT-TEXT _DAN-SLUG
            _DAN-NEW @ IF _DAN-I @ _DOC-FREE-CONTENT THEN
            0= IF LEAVE THEN
            _DAN-COUNT _DAN-MATCH? IF _DAN-I @ _DAN-FOUND ! LEAVE THEN
            _DAN-REMEMBER 0= IF LEAVE THEN
        THEN
    LOOP
    _DAN-FREE _DAN-FOUND @ ;

\ ---------------------------------------------------------------------
\  Contents
\ ---------------------------------------------------------------------
\
\  A document's contents are entries, each a title at a level, that go
\  somewhere in it: to a block, by its key, or where a link's target
\  goes.  Its reader gives them (RDR.CONTENTS-XT), as a PDF gives its
\  outline; otherwise they are its headings of levels 1 to 3, the
\  levels contents show, each going to its heading.  A document in parts
\  has no headings to give before its parts are read, so only its reader
\  gives its contents.  They are made when first asked for, and kept.
\  An entry with entries below it shows them until it is closed; a
\  reader closes one that the document says starts closed, as a PDF's
\  outline may.

VARIABLE _DCE-N

\ DOC-ADD-ENTRY ( level title-a title-u key target-a target-u doc -- ok? )
\   Add an entry: going to the block with KEY, or, for 0, where TARGET
\   goes, which may be empty for an entry that only heads others.
: DOC-ADD-ENTRY  ( level title-a title-u key target-a target-u doc -- ok? )
    _DOC-D !
    _DOC-D @ _DOC.ESTR-U @ OVER + 4 PICK +
    _DOC-D @ _DOC.ESTR-A _DOC-D @ _DOC.ESTR-CAP _DOC-GROW
    _DOC-D @ _DOC.ENTRIES-N @ 0 MAX 1+ _ENT-SIZE *
    _DOC-D @ _DOC.ENTRIES-A _DOC-D @ _DOC.ENTRIES-CAP _DOC-GROW AND 0= IF
        2DROP 2DROP 2DROP 0 EXIT
    THEN
    _DOC-D @ _DOC.ENTRIES-N @ 0 MAX DUP _DCE-N !
    _ENT-SIZE * _DOC-D @ _DOC.ENTRIES-A @ + >R
    DUP R@ _ENT.TARGET-U !  _DOC-D @ _DOC.ESTR-U @ R@ _ENT.TARGET !
    _DOC-D @ _DOC.ESTR-A @ _DOC-D @ _DOC.ESTR-U @ + SWAP DUP _DOC-D @ _DOC.ESTR-U +! MOVE
    R@ _ENT.KEY !
    DUP R@ _ENT.TITLE-U !  _DOC-D @ _DOC.ESTR-U @ R@ _ENT.TITLE !
    _DOC-D @ _DOC.ESTR-A @ _DOC-D @ _DOC.ESTR-U @ + SWAP DUP _DOC-D @ _DOC.ESTR-U +! MOVE
    0 R@ _ENT.CLOSED !  R> _ENT.LEVEL !
    _DCE-N @ 1+ _DOC-D @ _DOC.ENTRIES-N !  -1 ;

\ DOC-CLOSE-ENTRY ( doc -- )
\   The entry added last starts closed, the entries below it hidden.
: DOC-CLOSE-ENTRY  ( doc -- )
    DUP _DOC.ENTRIES-N @ DUP 0> 0= IF 2DROP EXIT THEN
    1- _ENT-SIZE * SWAP _DOC.ENTRIES-A @ + _ENT.CLOSED -1 SWAP ! ;

VARIABLE _DCH-I
VARIABLE _DCH-NEW
VARIABLE _DCH-C

\ The document's headings of levels 1 to 3 as its contents.
: _DOC-HEADINGS  ( -- status )
    0 _DOC-D @ _DOC.ENTRIES-N !
    _DOC-D @ _DOC.COUNT @ 0 ?DO
        I _DCH-I !
        I _DOC-D @ DOC-BLOCK DUP BLK-KIND@ DOC-B-HEADING = SWAP BLK-LEVEL@ 4 < AND IF
            I _DOC-CACHE-SLOT @ 0= _DCH-NEW !
            I _DOC-D @ _DOC-CONTENT ?DUP IF NIP UNLOOP EXIT THEN _DCH-C !
            _DCH-C @ DCT-LEVEL@ 1- 0 MAX _DCH-C @ DCT-TEXT
            _DCH-I @ _DOC-D @ DOC-BLOCK BLK-KEY@ 0 0 _DOC-D @ DOC-ADD-ENTRY
            _DCH-NEW @ IF _DCH-I @ _DOC-FREE-CONTENT THEN
            0= IF DOC-S-MEMORY UNLOOP EXIT THEN
        THEN
    LOOP DOC-S-OK ;

\ DOC-CONTENTS ( doc -- entries status )
\   The document's contents, made when first asked for.  When they
\   cannot all be made, the entries made so far, and why.
: _DOC-CONTENTS  ( doc -- entries status )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF DROP 0 DOC-S-INVALID EXIT THEN
    _DOC-D !
    _DOC-D @ _DOC.ENTRIES-N @ 0< 0= IF _DOC-D @ _DOC.ENTRIES-N @ DOC-S-OK EXIT THEN
    0 _DOC-D @ _DOC.ENTRIES-N !
    _DOC-D @ _DOC.READER @ RDR.CONTENTS-XT @ ?DUP IF
        _DOC-D @ DUP >R SWAP EXECUTE R> _DOC-D !
    ELSE
        _DOC-D @ _DOC.PART-COUNT @ IF DOC-S-OK ELSE _DOC-HEADINGS THEN
    THEN
    _DOC-D @ _DOC.ENTRIES-N @ SWAP ;

: _DOC-ENTRY@  ( i doc -- e )  _DOC.ENTRIES-A @ SWAP _ENT-SIZE * + ;

\ DOC-ENTRY ( i doc -- level title-a title-u )   Entry I of the contents.
: DOC-ENTRY  ( i doc -- level title-a title-u )
    2DUP _DOC.ENTRIES-N @ 0 MAX U< 0= IF 2DROP 0 0 0 EXIT THEN
    TUCK _DOC-ENTRY@ DUP _ENT.LEVEL @ SWAP
    DUP _ENT.TITLE @ 3 PICK _DOC.ESTR-A @ + SWAP _ENT.TITLE-U @ 3 ROLL DROP ;

\ DOC-ENTRY-GOES ( i doc -- key target-a target-u )
\   Where entry I goes: the key of a block, or 0 and a link's target.
: DOC-ENTRY-GOES  ( i doc -- key target-a target-u )
    2DUP _DOC.ENTRIES-N @ 0 MAX U< 0= IF 2DROP 0 0 0 EXIT THEN
    TUCK _DOC-ENTRY@ DUP _ENT.KEY @ SWAP
    DUP _ENT.TARGET @ 3 PICK _DOC.ESTR-A @ + SWAP _ENT.TARGET-U @ 3 ROLL DROP ;

\ DOC-ENTRY-CLOSED? ( i doc -- flag )   Whether entry I starts closed.
: DOC-ENTRY-CLOSED?  ( i doc -- flag )
    2DUP _DOC.ENTRIES-N @ 0 MAX U< 0= IF 2DROP 0 EXIT THEN
    _DOC-ENTRY@ _ENT.CLOSED @ ;

\ ---------------------------------------------------------------------
\  What a reader of the kept contents touches
\ ---------------------------------------------------------------------

\ DOC-KEPT ( index doc -- content | 0 )
\   The content of block INDEX the document keeps, or 0; never reads.
: DOC-KEPT  ( index doc -- content | 0 )
    DUP _DOC.MAGIC @ _DOC-MAGIC <> IF 2DROP 0 EXIT THEN
    2DUP _DOC.COUNT @ U< 0= IF 2DROP 0 EXIT THEN
    _DOC.CACHE-A @ SWAP CELLS + @ ;

VARIABLE _DSD-A
VARIABLE _DSD-U
VARIABLE _DSD-D

: _DSD-CLEAR?  ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    _DSD-A @ _DSD-U @ 2SWAP MSPAN-OVERLAP? 0= ;

\ DOC-STORAGE-DISJOINT? ( a u first end doc -- flag )
\   Whether span A U lies clear of all a reader of the document's
\   structure and of the contents of blocks FIRST to END touches: its
\   record, its blocks, their containers, the slots of its contents, and
\   those contents.
: DOC-STORAGE-DISJOINT?  ( a u first end doc -- flag )
    _DSD-D ! 2SWAP _DSD-U ! _DSD-A !
    _DSD-U @ 0= IF 2DROP -1 EXIT THEN
    _DSD-D @ DOC-SIZE _DSD-CLEAR? 0= IF 2DROP 0 EXIT THEN
    _DSD-D @ _DOC.MAGIC @ _DOC-MAGIC <> IF 2DROP -1 EXIT THEN
    _DSD-D @ _DOC.BLOCKS-A @ _DSD-D @ _DOC.BLOCKS-CAP @ _DSD-CLEAR?
        0= IF 2DROP 0 EXIT THEN
    _DSD-D @ _DOC.CONTS-A @ _DSD-D @ _DOC.CONTS-CAP @ _DSD-CLEAR?
        0= IF 2DROP 0 EXIT THEN
    _DSD-D @ _DOC.PARTS-A @ _DSD-D @ _DOC.PARTS-CAP @ _DSD-CLEAR?
        0= IF 2DROP 0 EXIT THEN
    _DSD-D @ _DOC.ENTRIES-A @ _DSD-D @ _DOC.ENTRIES-CAP @ _DSD-CLEAR?
        0= IF 2DROP 0 EXIT THEN
    _DSD-D @ _DOC.ESTR-A @ _DSD-D @ _DOC.ESTR-CAP @ _DSD-CLEAR?
        0= IF 2DROP 0 EXIT THEN
    _DSD-D @ _DOC.CACHE-A @ _DSD-D @ _DOC.CACHE-CAP @ _DSD-CLEAR?
        0= IF 2DROP 0 EXIT THEN
    _DSD-D @ _DOC.COUNT @ MIN SWAP 0 MAX ?DO
        I _DSD-D @ DOC-KEPT ?DUP IF
            DUP _DCT.BYTES @ _DSD-CLEAR? 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    -1 ;

\ ---------------------------------------------------------------------
\  Public words
\ ---------------------------------------------------------------------

: DOC-OPEN     ( source reader msrc doc -- status )  _DOC-OPEN ;
: DOC-CLOSE    ( doc -- )  _DOC-CLOSE ;
: DOC-CONTENT  ( index doc -- content status )  _DOC-CONTENT ;
: DOC-KEEP     ( first end doc -- )  _DOC-KEEP ;
: DOC-ANCHOR   ( name-a name-u doc -- index | -1 )  _DOC-ANCHOR ;
: DOC-CONTENTS  ( doc -- entries status )  _DOC-CONTENTS ;
: DOC-READ-PART  ( part doc -- status )  _DOC-READ-PART ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _doc-guard

' DOC-OPEN     CONSTANT _doc-open-xt
' DOC-CLOSE    CONSTANT _doc-close-xt
' DOC-CONTENT  CONSTANT _doc-content-xt
' DOC-KEEP     CONSTANT _doc-keep-xt
' DOC-ANCHOR   CONSTANT _doc-anchor-xt
' DOC-READ-PART CONSTANT _doc-read-part-xt
' DOC-CONTENTS CONSTANT _doc-contents-xt

: DOC-OPEN     _doc-open-xt _doc-guard WITH-GUARD ;
: DOC-CLOSE    _doc-close-xt _doc-guard WITH-GUARD ;
: DOC-CONTENT  _doc-content-xt _doc-guard WITH-GUARD ;
: DOC-KEEP     _doc-keep-xt _doc-guard WITH-GUARD ;
: DOC-ANCHOR   _doc-anchor-xt _doc-guard WITH-GUARD ;
: DOC-READ-PART _doc-read-part-xt _doc-guard WITH-GUARD ;
: DOC-CONTENTS _doc-contents-xt _doc-guard WITH-GUARD ;
[THEN] [THEN]
