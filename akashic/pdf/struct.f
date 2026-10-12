\ =================================================================
\  struct.f  —  a tagged page's marked content, by its structure
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-STRUCT- (public), _PDST- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f, pdf/page.f,
\              media/document.f
\
\  Public API:
\   PDF-STRUCT-SIZE   ( -- bytes )                  a page structure's record
\   PDF-STRUCT-READ   ( page struct -- status )     a tagged page's structure
\   PDF-STRUCT-FREE   ( struct -- )
\   PDF-STRUCT-BLOCK  ( mcid struct -- id kind level item true | false )
\
\  PDF-STRUCT-READ finds, for each marked-content sequence of an open
\  page, the structure element it belongs to (PDF 32000-1 section 14.7),
\  through the page's /StructParents and the structure tree's
\  /ParentTree, and from that element the block it makes.  A page with
\  no structure has none, and PDF-STRUCT-BLOCK then knows no MCID.
\
\  PDF-STRUCT-BLOCK gives the block MCID's text belongs to: ID, the block
\  element's object number, which the MCIDs of one block share; KIND,
\  DOC-B-HEADING with LEVEL for H1 to H6 (H is 1), DOC-B-CODE for Code
\  standing as a block, DOC-B-PARAGRAPH for any other block, or 0 for a
\  list item's label, whose ID is its item's; and ITEM, the container
\  around it: DOC-C-BULLET or DOC-C-NUMBERED in a list item, by its
\  list's /ListNumbering, DOC-C-QUOTE in a BlockQuote, or 0.  Or false
\  for an MCID it does not know.
\
\  Inline elements (Span, Quote, Note, Reference, BibEntry, Link, Annot,
\  Em, Strong, Sub, Ruby and Warichu with their parts, and Code inside a
\  paragraph) belong to the block around them.  Types are read through
\  the tree's /RoleMap, which may map a name onward, never more times
\  than it has names.  Elements are read once a page, and a walk from an
\  element takes no more steps than the file has objects.  A structure
\  that cannot be read gives no blocks rather than failing the page.
\
\  Memory comes from the page's file's memory source.  One call runs at
\  a time.
\ =================================================================

PROVIDED akashic-pdf-struct

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f
REQUIRE page.f
REQUIRE ../media/document.f

\ The record: its memory source, and its entries, one an MCID: the
\ block's id, kind, level and container.
: _PDST.MSRC  ( s -- a )        ;
: _PDST.E     ( s -- buf )  8 + ;
32 CONSTANT PDF-STRUCT-SIZE
32 CONSTANT _PDST-ENTRY

\ PDF-STRUCT-BLOCK ( mcid struct -- id kind level item true | false )
: PDF-STRUCT-BLOCK  ( mcid struct -- id kind level item true | false )
    >R DUP 0< IF R> 2DROP 0 EXIT THEN
    DUP R@ _PDST.E PDF-BUF.U @ _PDST-ENTRY / < 0= IF R> 2DROP 0 EXIT THEN
    _PDST-ENTRY * R> _PDST.E PDF-BUF.A @ +
    DUP @ 0= IF DROP 0 EXIT THEN
    DUP @ OVER 8 + @ 2 PICK 16 + @ 3 PICK 24 + @ >R >R >R >R DROP R> R> R> R> -1 ;

\ PDF-STRUCT-FREE ( struct -- )   Give back its entries.
: PDF-STRUCT-FREE  ( struct -- )
    DUP _PDST.MSRC @ ?DUP IF OVER _PDST.E SWAP PDF-BUF-FREE THEN
    PDF-STRUCT-SIZE 0 FILL ;

VARIABLE _PDST-S      \ the record
VARIABLE _PDST-F      \ the file
VARIABLE _PDST-RO     \ the structure tree root's object
VARIABLE _PDST-RMO    \ its role map's object, when apart
VARIABLE _PDST-RA   VARIABLE _PDST-RU     \ its role map
VARIABLE _PDST-RN     \ how many names it maps
VARIABLE _PDST-VISITS
VARIABLE _PDST-KEY    \ the page's key in the parent tree

: _PDST-MSRC  ( -- msrc )  _PDST-S @ _PDST.MSRC @ ;
: _PDST-GET   ( num -- obj status )  _PDST-F @ PDF-GET ;
: _PDST-FREE  ( obj -- )  _PDST-F @ PDF-OBJ-FREE ;
: _PDST-RESOLVE  ( va vu type -- obj va' vu' type' status )  _PDST-F @ PDF-RESOLVE ;
: _PDST-ADV   ( a u n -- a+n u-n )  TUCK - >R + R> ;

\ One more step of a walk: false once it has taken as many as the file
\ has objects.
: _PDST-VISIT?  ( -- ok? )
    1 _PDST-VISITS +!  _PDST-VISITS @ _PDST-F @ PDF-OBJECT-COUNT > 0= ;

\ =====================================================================
\  Names and types
\ =====================================================================

\ A name's bytes with its #xx codes read, without its slash; a name is at
\ most 127 bytes (PDF 32000-1 Annex C).
CREATE _PDST-NB 128 ALLOT
VARIABLE _PDST-NN

: _PDST-HEX  ( c -- n )  DUP 58 < IF 48 - ELSE 32 OR 87 - THEN 15 AND ;

: _PDST-NB+  ( c -- )
    _PDST-NN @ 127 < IF _PDST-NB _PDST-NN @ + C! ELSE DROP THEN  1 _PDST-NN +! ;

: _PDST-NAME  ( va vu -- a u )
    1 _PDST-ADV  0 _PDST-NN !
    BEGIN DUP WHILE
        OVER C@ 35 = OVER 2 > AND IF
            OVER 1+ C@ _PDST-HEX 4 LSHIFT  2 PICK 2 + C@ _PDST-HEX OR _PDST-NB+
            3 _PDST-ADV
        ELSE OVER C@ _PDST-NB+ 1 _PDST-ADV THEN
    REPEAT 2DROP
    _PDST-NB _PDST-NN @ 127 MIN ;

\ A name through the role map: the standard name it stands for, or itself.
: _PDST-ROLE  ( a u -- a' u' )
    _PDST-RU @ 0= IF EXIT THEN
    _PDST-RN @ 0 ?DO
        2DUP _PDST-RA @ _PDST-RU @ PDF-DICT@ PDF-T-NAME <> IF 2DROP UNLOOP EXIT THEN
        2SWAP 2DROP _PDST-NAME
    LOOP ;

0 CONSTANT _PDST-T-BLOCK      \ a block of its own: P and the rest
1 CONSTANT _PDST-T-INLINE
2 CONSTANT _PDST-T-LABEL
3 CONSTANT _PDST-T-HEADING
4 CONSTANT _PDST-T-CODE
5 CONSTANT _PDST-T-LBODY
6 CONSTANT _PDST-T-LI
7 CONSTANT _PDST-T-LIST
8 CONSTANT _PDST-T-QUOTE      \ BlockQuote
9 CONSTANT _PDST-T-GROUP      \ Document, Part, Art, Sect, Div and the like

VARIABLE _PDST-NA   VARIABLE _PDST-NU
: _PDST-IS?  ( a u -- flag )  _PDST-NA @ _PDST-NU @ COMPARE 0= ;

\ A standard type's code, and a heading's level.
: _PDST-TYPE  ( a u -- type level )
    _PDST-NU ! _PDST-NA !
    _PDST-NU @ 2 = IF _PDST-NA @ C@ 72 = IF
        _PDST-NA @ 1+ C@ 49 55 WITHIN IF _PDST-T-HEADING _PDST-NA @ 1+ C@ 48 - EXIT THEN
    THEN THEN
    S" H" _PDST-IS? IF _PDST-T-HEADING 1 EXIT THEN
    S" Lbl" _PDST-IS? IF _PDST-T-LABEL 0 EXIT THEN
    S" LBody" _PDST-IS? IF _PDST-T-LBODY 0 EXIT THEN
    S" LI" _PDST-IS? IF _PDST-T-LI 0 EXIT THEN
    S" L" _PDST-IS? IF _PDST-T-LIST 0 EXIT THEN
    S" BlockQuote" _PDST-IS? IF _PDST-T-QUOTE 0 EXIT THEN
    S" Code" _PDST-IS? IF _PDST-T-CODE 0 EXIT THEN
    S" Span" _PDST-IS? S" Quote" _PDST-IS? OR S" Note" _PDST-IS? OR
    S" Reference" _PDST-IS? OR S" BibEntry" _PDST-IS? OR S" Link" _PDST-IS? OR
    S" Annot" _PDST-IS? OR S" Em" _PDST-IS? OR S" Strong" _PDST-IS? OR
    S" Sub" _PDST-IS? OR S" Ruby" _PDST-IS? OR S" RB" _PDST-IS? OR
    S" RT" _PDST-IS? OR S" RP" _PDST-IS? OR S" Warichu" _PDST-IS? OR
    S" WT" _PDST-IS? OR S" WP" _PDST-IS? OR IF _PDST-T-INLINE 0 EXIT THEN
    S" Document" _PDST-IS? S" Part" _PDST-IS? OR S" Art" _PDST-IS? OR
    S" Sect" _PDST-IS? OR S" Div" _PDST-IS? OR S" TOC" _PDST-IS? OR
    S" Index" _PDST-IS? OR S" Table" _PDST-IS? OR S" TR" _PDST-IS? OR
    S" THead" _PDST-IS? OR S" TBody" _PDST-IS? OR S" TFoot" _PDST-IS? OR
    S" DocumentFragment" _PDST-IS? OR S" Aside" _PDST-IS? OR
    IF _PDST-T-GROUP 0 EXIT THEN
    _PDST-T-BLOCK 0 ;

\ One attribute object, through a reference: the item kind its
\ /ListNumbering says, if it has one.
: _PDST-ATTR  ( va vu type -- item found? )
    _PDST-RESOLVE IF DROP 2DROP _PDST-FREE 0 0 EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDST-FREE 0 0 EXIT THEN
    S" ListNumbering" 2SWAP PDF-DICT@ PDF-T-NAME <> IF 2DROP _PDST-FREE 0 0 EXIT THEN
    2DUP S" None" PDF-NAME= >R 2DUP S" Disc" PDF-NAME= R> OR >R
    2DUP S" Circle" PDF-NAME= R> OR >R S" Square" PDF-NAME= R> OR
    IF DOC-C-BULLET ELSE DOC-C-NUMBERED THEN
    SWAP _PDST-FREE -1 ;

\ A list's item kind, from its attributes: bullets unless they number.
: _PDST-NUMBERING  ( da du -- item )
    S" A" 2SWAP PDF-DICT@
    DUP PDF-T-ARRAY = IF
        DROP PDF-TOKEN DROP 2DROP
        BEGIN
            PDF-VALUE DUP PDF-T-DICT = OVER PDF-T-REF = OR IF
                _PDST-ATTR IF NIP NIP EXIT THEN DROP
            ELSE DUP PDF-T-INT = IF
                DROP 2DROP
            ELSE DROP 2DROP 2DROP DOC-C-BULLET EXIT THEN THEN
        AGAIN
    THEN
    _PDST-ATTR 0= IF DROP DOC-C-BULLET THEN ;

\ =====================================================================
\  Elements, read once a page
\ =====================================================================

\ An element kept: its number, type, level, parent's number, and for a
\ list its item kind.
CREATE _PDST-KEPT-S PDF-BUF-SIZE 7 + ALLOT
: _PDST-KEPT  ( -- buf )  _PDST-KEPT-S 7 + -8 AND ;
40 CONSTANT _PDST-EL
CREATE _PDST-NEW _PDST-EL ALLOT

: _PDST-TYPE@    ( el -- type )  8 + @ ;
: _PDST-PARENT@  ( el -- num )  24 + @ ;

\ Element NUM, read once a page: its kept record, or 0.
: _PDST-ELEMENT  ( num -- el | 0 )
    _PDST-KEPT PDF-BUF.A @ _PDST-KEPT PDF-BUF.U @ _PDST-EL / 0 ?DO
        DUP I _PDST-EL * + @ 2 PICK = IF I _PDST-EL * + NIP UNLOOP EXIT THEN
    LOOP DROP
    _PDST-NEW _PDST-EL 0 FILL  DUP _PDST-NEW !
    _PDST-GET IF _PDST-FREE 0 EXIT THEN
    DUP PDF-OBJ-VALUE PDF-T-DICT <> IF 2DROP _PDST-FREE 0 EXIT THEN
    2DUP S" S" 2SWAP PDF-DICT@ PDF-T-NAME = IF
        _PDST-NAME _PDST-ROLE _PDST-TYPE
    ELSE 2DROP _PDST-T-GROUP 0 THEN
    _PDST-NEW 16 + !  DUP _PDST-NEW 8 + !
    _PDST-T-LIST = IF 2DUP _PDST-NUMBERING _PDST-NEW 32 + ! THEN
    S" P" 2SWAP PDF-DICT@ PDF-T-REF = IF PDF-REF@ DROP ELSE 2DROP 0 THEN _PDST-NEW 24 + !
    _PDST-FREE
    _PDST-NEW _PDST-EL _PDST-KEPT _PDST-MSRC PDF-BUF-APPEND 0= IF 0 EXIT THEN
    _PDST-KEPT DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + _PDST-EL - ;

\ An element's parent, one step of a walk.
: _PDST-UP  ( el -- el' | 0 )
    _PDST-VISIT? 0= IF DROP 0 EXIT THEN
    _PDST-PARENT@ ?DUP IF _PDST-ELEMENT ELSE 0 THEN ;

\ =====================================================================
\  The block an element makes
\ =====================================================================

CREATE _PDST-OUT _PDST-ENTRY ALLOT

\ The container around element EL: a list item's, by its list, or a
\ quote's; none past a grouping element.
: _PDST-CONTAINER  ( el -- item )
    BEGIN
        _PDST-UP DUP 0= IF EXIT THEN
        DUP _PDST-TYPE@ DUP _PDST-T-LBODY = SWAP _PDST-T-LI = OR IF
            BEGIN DUP _PDST-TYPE@ _PDST-T-LIST <> WHILE
                _PDST-UP DUP 0= IF EXIT THEN
            REPEAT
            32 + @ EXIT
        THEN
        DUP _PDST-TYPE@ _PDST-T-QUOTE = IF DROP DOC-C-QUOTE EXIT THEN
        DUP _PDST-TYPE@ _PDST-T-GROUP = IF DROP 0 EXIT THEN
    AGAIN ;

\ What element NUM's marked content makes, into _PDST-OUT: false when
\ it cannot be read.
: _PDST-CLASSIFY  ( num -- ok? )
    _PDST-OUT _PDST-ENTRY 0 FILL  0 _PDST-VISITS !
    _PDST-ELEMENT DUP 0= IF EXIT THEN
    BEGIN DUP _PDST-TYPE@ _PDST-T-INLINE = WHILE
        _PDST-UP DUP 0= IF EXIT THEN
    REPEAT
    DUP _PDST-TYPE@ _PDST-T-LABEL = IF
        DUP _PDST-PARENT@ _PDST-OUT !
        _PDST-CONTAINER _PDST-OUT 24 + !  -1 EXIT
    THEN
    \ Code inside a paragraph is inline there; standing alone, a block.
    DUP _PDST-TYPE@ _PDST-T-CODE = IF
        DUP _PDST-PARENT@ ?DUP IF _PDST-ELEMENT ?DUP IF
            DUP _PDST-TYPE@ DUP _PDST-T-GROUP = SWAP _PDST-T-QUOTE = OR IF DROP ELSE NIP THEN
        THEN THEN
    THEN
    DUP @ _PDST-OUT !
    DUP _PDST-TYPE@ CASE
        _PDST-T-HEADING OF DOC-B-HEADING OVER 16 + @ ENDOF
        _PDST-T-CODE    OF DOC-B-CODE 0 ENDOF
        >R DOC-B-PARAGRAPH 0 R>
    ENDCASE
    _PDST-OUT 16 + !  _PDST-OUT 8 + !
    DUP _PDST-TYPE@ _PDST-T-QUOTE = IF DROP DOC-C-QUOTE ELSE _PDST-CONTAINER THEN
    _PDST-OUT 24 + !  -1 ;

\ =====================================================================
\  The parent tree
\ =====================================================================

\ The value of the page's key in a number tree node's /Nums, if there.
: _PDST-IN-NUMS  ( da du -- va vu type found? )
    S" Nums" 2SWAP PDF-DICT@ PDF-T-ARRAY <> IF 2DROP 0 0 0 0 EXIT THEN
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE PDF-T-INT <> IF 2DROP 2DROP 0 0 0 0 EXIT THEN
        PDF-INT _PDST-KEY @ = IF PDF-VALUE >R 2SWAP 2DROP R> -1 EXIT THEN
        PDF-VALUE DROP 2DROP
    AGAIN ;

\ Whether node NUM's /Limits hold the key.
: _PDST-LIMITS?  ( num -- flag )
    _PDST-GET IF _PDST-FREE 0 EXIT THEN
    DUP PDF-OBJ-VALUE DROP S" Limits" 2SWAP PDF-DICT@ PDF-T-ARRAY = IF
        2DUP 0 -ROT PDF-ARRAY@ DROP PDF-INT _PDST-KEY @ > 0=
        >R 1 -ROT PDF-ARRAY@ DROP PDF-INT _PDST-KEY @ < 0= R> AND
    ELSE 2DROP 0 THEN
    SWAP _PDST-FREE ;

\ The kid of a node whose limits hold the key: its number, or 0.
: _PDST-KID  ( da du -- num | 0 )
    S" Kids" 2SWAP PDF-DICT@ PDF-T-ARRAY <> IF 2DROP 0 EXIT THEN
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-REF <> IF DROP 2DROP 2DROP 0 EXIT THEN
        DROP PDF-REF@ DROP DUP _PDST-LIMITS? IF NIP NIP EXIT THEN DROP
    AGAIN ;

\ The page's key in the number tree whose root node is OBJ's span DA DU:
\ the object holding its value, to give back, and the value; or 0 0 0
\ PDF-T-END.
: _PDST-NUMS  ( obj da du -- obj va vu type )
    BEGIN
        2DUP _PDST-IN-NUMS IF >R >R >R 2DROP R> R> R> EXIT THEN
        DROP 2DROP
        _PDST-KID SWAP _PDST-FREE
        DUP 0= IF DROP 0 0 0 PDF-T-END EXIT THEN
        _PDST-VISIT? 0= IF DROP 0 0 0 PDF-T-END EXIT THEN
        _PDST-GET IF _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
        DUP PDF-OBJ-VALUE PDF-T-DICT <> IF 2DROP _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
    AGAIN ;

\ The structure tree's role map, kept and its names counted.
: _PDST-ROLEMAP  ( ra ru -- )
    S" RoleMap" 2SWAP PDF-DICT@ _PDST-RESOLVE IF DROP 2DROP _PDST-FREE EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDST-FREE EXIT THEN
    ROT _PDST-RMO !  2DUP _PDST-RU ! _PDST-RA !
    PDF-TOKEN DROP 2DROP
    BEGIN PDF-VALUE PDF-T-NAME = WHILE 2DROP PDF-VALUE DROP 2DROP 1 _PDST-RN +! REPEAT
    2DROP 2DROP ;

\ The structure tree's root kept, its role map read, and the page's key's
\ value in its parent tree: the object holding the value, to give back,
\ and the value; or 0 0 0 PDF-T-END.
: _PDST-TREE  ( -- obj va vu type )
    S" Root" _PDST-F @ PDF-TRAILER@ _PDST-RESOLVE IF DROP 2DROP _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
    S" StructTreeRoot" 2SWAP PDF-DICT@ _PDST-RESOLVE
    >R >R >R >R >R _PDST-FREE R> R> R> R> R>
    IF DROP 2DROP _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
    ROT _PDST-RO !
    2DUP _PDST-ROLEMAP
    S" ParentTree" 2SWAP PDF-DICT@ _PDST-RESOLVE IF DROP 2DROP _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDST-FREE 0 0 0 PDF-T-END EXIT THEN
    0 _PDST-VISITS !  _PDST-NUMS ;

\ Each element of the page's array, an entry; false when memory is refused.
: _PDST-ENTRIES  ( aa au -- ok? )
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-CLOSE-ARRAY = OVER PDF-T-END = OR OVER PDF-T-BAD = OR IF
            DROP 2DROP 2DROP -1 EXIT
        THEN
        PDF-T-REF = IF
            PDF-REF@ DROP _PDST-CLASSIFY 0= IF _PDST-OUT _PDST-ENTRY 0 FILL THEN
        ELSE 2DROP _PDST-OUT _PDST-ENTRY 0 FILL THEN
        _PDST-OUT _PDST-ENTRY _PDST-S @ _PDST.E _PDST-MSRC PDF-BUF-APPEND 0= IF 2DROP 0 EXIT THEN
    AGAIN ;

\ PDF-STRUCT-READ ( page struct -- status )   The open page's structure.
: PDF-STRUCT-READ  ( page struct -- status )
    DUP _PDST-S !  PDF-STRUCT-SIZE 0 FILL
    DUP PDF-PAGE-FILE DUP _PDST-F !  PDF-FILE-MSRC _PDST-S @ _PDST.MSRC !
    0 _PDST-RO !  0 _PDST-RMO !  0 _PDST-RU !  0 _PDST-RN !
    _PDST-KEPT PDF-BUF-SIZE 0 FILL
    S" StructParents" ROT PDF-PAGE-DICT PDF-DICT@ PDF-T-INT <> IF 2DROP PDF-S-OK EXIT THEN
    PDF-INT _PDST-KEY !
    _PDST-TREE _PDST-RESOLVE
    0= OVER PDF-T-ARRAY = AND IF
        DROP _PDST-ENTRIES IF PDF-S-OK ELSE PDF-S-MEMORY THEN
    ELSE 2DROP DROP PDF-S-OK THEN
    >R _PDST-FREE _PDST-FREE R>
    _PDST-RO @ _PDST-FREE  _PDST-RMO @ _PDST-FREE
    _PDST-KEPT _PDST-MSRC PDF-BUF-FREE ;
