\ =====================================================================
\  media/document.f — a document's blocks, read as a view reaches them
\ =====================================================================
\
\  A document is text read from top to bottom, with its structure: a
\  sequence of blocks (paragraphs, headings, code, rules and figures), each
\  inside the quotes and list items around it.  A reader finds the blocks
\  in a media source.  DOC-OPEN runs the reader's structure pass, which
\  keeps each block's kind, its containers, the blank rows before it, and
\  where its text lies, but not the text.  DOC-CONTENT reads one block's
\  text and meanings when a view reaches it, and keeps them until DOC-KEEP
\  gives back the contents outside the view.
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
\  A block's fields are BLK-KIND@ BLK-LEVEL@ BLK-ROWS-BEFORE@ BLK-INSIDE@;
\  a container's CNT-KIND@ CNT-WIDTH@ CNT-NUMBER@ CNT-START?; a content's
\  DCT-KIND@ DCT-LEVEL@ DCT-TEXT DCT-MAP DCT-FIGURE DCT-LINK-COUNT
\  DCT-LINK@ DCT-LINK-AT.
\ =====================================================================

REQUIRE ../utils/memory-source.f
REQUIRE ../utils/string.f
REQUIRE source.f

PROVIDED akashic-media-document

0 CONSTANT DOC-S-OK
1 CONSTANT DOC-S-MEMORY      \ the memory source refused
2 CONSTANT DOC-S-READ        \ the media source could not be read
3 CONSTANT DOC-S-INVALID     \ no such block, or no open document

\ Block kinds.
1 CONSTANT DOC-B-PARAGRAPH
2 CONSTANT DOC-B-HEADING
3 CONSTANT DOC-B-CODE
4 CONSTANT DOC-B-RULE
5 CONSTANT DOC-B-FIGURE

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
232 CONSTANT DOC-SIZE

\ A block: its kind and heading level, the blank rows before it and how
\ many of its outermost containers those rows lie inside, its containers,
\ and two cells the reader keeps to find its text.
: _BLK.KIND        ( b -- a )        ;
: _BLK.LEVEL       ( b -- a )    8 + ;
: _BLK.ROWS-BEFORE ( b -- a )   16 + ;
: _BLK.INSIDE      ( b -- a )   24 + ;
: _BLK.CONT-FIRST  ( b -- a )   32 + ;
: _BLK.CONT-COUNT  ( b -- a )   40 + ;
: _BLK.LOC-A       ( b -- a )   48 + ;
: _BLK.LOC-B       ( b -- a )   56 + ;
64 CONSTANT _BLK-SIZE

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
\ with DOC-ADD-BLOCK and DOC-ADD-CONTAINER; its content pass ( index doc --
\ status ), which fills the builder with DOC-CB-TEXT, DOC-CB-LINK,
\ DOC-CB-KIND and DOC-CB-FIGURE; and what it gives back ( doc -- ).
: RDR.STRUCTURE-XT ( r -- a )        ;
: RDR.CONTENT-XT   ( r -- a )    8 + ;
: RDR.CLOSE-XT     ( r -- a )   16 + ;
24 CONSTANT RDR-SIZE

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
\   Add the next block.  Its rows before and containers start empty.  The
\   address stays valid only until the next block is added.
: DOC-ADD-BLOCK  ( kind level loc-a loc-b doc -- block | 0 )
    _DOC-D !
    _DOC-D @ _DOC.COUNT @ 1+ _BLK-SIZE *
    _DOC-D @ _DOC.BLOCKS-A _DOC-D @ _DOC.BLOCKS-CAP _DOC-GROW 0= IF
        2DROP 2DROP 0 EXIT
    THEN
    _DOC-D @ _DOC.BLOCKS-A @ _DOC-D @ _DOC.COUNT @ _BLK-SIZE * +
    >R
    R@ _BLK.LOC-B ! R@ _BLK.LOC-A ! R@ _BLK.LEVEL ! R@ _BLK.KIND !
    0 R@ _BLK.ROWS-BEFORE ! 0 R@ _BLK.INSIDE !
    _DOC-D @ _DOC.CONT-COUNT @ R@ _BLK.CONT-FIRST ! 0 R@ _BLK.CONT-COUNT !
    1 _DOC-D @ _DOC.COUNT +!
    R> ;

\ DOC-ADD-CONTAINER ( kind width number start? doc -- ok? )
\   Add a container, outermost first, to the block added last.
: DOC-ADD-CONTAINER  ( kind width number start? doc -- ok? )
    _DOC-D !
    _DOC-D @ _DOC.COUNT @ 0= IF 2DROP 2DROP 0 EXIT THEN
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
    _DOC-MAGIC _DOC-D @ _DOC.MAGIC !
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
\  Anchors
\ ---------------------------------------------------------------------
\
\  A heading's anchor is its text in lower case, with spaces made hyphens
\  and other ASCII punctuation but hyphens and underscores left out; a
\  heading whose anchor an earlier one has takes "-1", "-2" and so on, as
\  GitHub names them.

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
\  Public words
\ ---------------------------------------------------------------------

: DOC-OPEN     ( source reader msrc doc -- status )  _DOC-OPEN ;
: DOC-CLOSE    ( doc -- )  _DOC-CLOSE ;
: DOC-CONTENT  ( index doc -- content status )  _DOC-CONTENT ;
: DOC-KEEP     ( first end doc -- )  _DOC-KEEP ;
: DOC-ANCHOR   ( name-a name-u doc -- index | -1 )  _DOC-ANCHOR ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _doc-guard

' DOC-OPEN     CONSTANT _doc-open-xt
' DOC-CLOSE    CONSTANT _doc-close-xt
' DOC-CONTENT  CONSTANT _doc-content-xt
' DOC-KEEP     CONSTANT _doc-keep-xt
' DOC-ANCHOR   CONSTANT _doc-anchor-xt

: DOC-OPEN     _doc-open-xt _doc-guard WITH-GUARD ;
: DOC-CLOSE    _doc-close-xt _doc-guard WITH-GUARD ;
: DOC-CONTENT  _doc-content-xt _doc-guard WITH-GUARD ;
: DOC-KEEP     _doc-keep-xt _doc-guard WITH-GUARD ;
: DOC-ANCHOR   _doc-anchor-xt _doc-guard WITH-GUARD ;
[THEN] [THEN]
