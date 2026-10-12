\ =================================================================
\  page.f  —  a PDF's pages: its page tree, what a page inherits, and
\  a page's content
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-PAGE- (public), _PDPG- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f
\
\  Public API:
\   PDF-PAGE-COUNT      ( file -- n status )       the pages the tree holds
\   PDF-PAGE-SIZE       ( -- bytes )               a page's record
\   PDF-PAGE-OPEN       ( i file page -- status )  page I, from 0
\   PDF-PAGE-CLOSE      ( page -- )                give back the page
\   PDF-PAGE-END        ( page -- )                and what the record keeps
\   PDF-PAGE-FILE       ( page -- file )           the file it is in
\   PDF-PAGE-NUM        ( page -- num )            its object's number
\   PDF-PAGE-DICT       ( page -- va vu )          its dictionary
\   PDF-PAGE-RESOURCES  ( page -- va vu type )     its resources
\   PDF-PAGE-BOX        ( page -- x0 y0 x1 y1 )    what it shows, 16.16
\   PDF-PAGE-ROTATE     ( page -- degrees )        0, 90, 180 or 270
\   PDF-PAGE-CONTENTS   ( page buf -- status )     its content, decoded
\
\  PDF-PAGE-COUNT is the root node's /Count.  PDF-PAGE-OPEN finds page I
\  by the tree's counts, reading only the nodes on the way down and their
\  kids, and gives the page the resources, media box, crop box and
\  rotation it inherits (PDF 32000-1 section 7.7.3.4).  The walk reads no
\  more nodes than the file has objects, so a tree that loops ends.  A
\  kid that cannot be read holds no pages.
\
\  A record starts zeroed.  Between pages it keeps the last page's parent
\  node and what that node passes down, so the next page, when it is the
\  parent's next kid, opens by reading only itself.  PDF-PAGE-CLOSE gives
\  back the page; close a page before the record opens another.
\  PDF-PAGE-END gives back everything, and the record is zeroed again.
\  On failure the page is closed.
\
\  PDF-PAGE-RESOURCES is a dictionary, or 0 0 PDF-T-END for a page with
\  none.  PDF-PAGE-BOX is the crop box within the media box, else the
\  media box, else US Letter, its corners ordered.  PDF-PAGE-CONTENTS
\  decodes the page's content streams onto BUF, an empty buffer, each
\  followed by a line end.  A stream that cannot be decoded whole gives
\  what it could, and its status once the rest are read; memory refused
\  ends it.  The caller gives BUF back.
\
\  The page's dictionary and resources stay valid until PDF-PAGE-CLOSE.
\  Memory comes from the file's memory source.  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-page

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f

\ The record.  The page: the file; the page's object; the object its own
\ resources were read from through a reference, and their span; its box,
\ rotation and object number.  Kept between pages: the last page's index,
\ its parent's number and object, the object holding the parent's kids
\ when they are apart, their span and where the next kid starts; which
\ values the parent passes down, and those values: its resources' bytes,
\ media box, crop box and rotation.
: _PDPG.FILE     ( p -- a )        ;
: _PDPG.OBJ      ( p -- a )    8 + ;
: _PDPG.ROBJ     ( p -- a )   16 + ;
: _PDPG.RA       ( p -- a )   24 + ;
: _PDPG.RU       ( p -- a )   32 + ;
: _PDPG.RTYPE    ( p -- a )   40 + ;
: _PDPG.BOX      ( p -- a )   48 + ;
: _PDPG.ROTATE   ( p -- a )   80 + ;
: _PDPG.NUM      ( p -- a )   88 + ;
: _PDPG.CI       ( p -- a )   96 + ;
: _PDPG.CNUM     ( p -- a )  104 + ;
: _PDPG.CPO      ( p -- a )  112 + ;
: _PDPG.CKO      ( p -- a )  120 + ;
: _PDPG.CKA      ( p -- a )  128 + ;
: _PDPG.CKU      ( p -- a )  136 + ;
: _PDPG.COFF     ( p -- a )  144 + ;
: _PDPG.HAS      ( p -- a )  152 + ;
: _PDPG.HRES     ( p -- buf ) 160 + ;
: _PDPG.HMEDIA   ( p -- a )  184 + ;
: _PDPG.HCROP    ( p -- a )  216 + ;
: _PDPG.HROT     ( p -- a )  248 + ;
256 CONSTANT PDF-PAGE-SIZE

\ What a parent passes down.
1 CONSTANT _PDPG-H-RES   2 CONSTANT _PDPG-H-MEDIA
4 CONSTANT _PDPG-H-CROP  8 CONSTANT _PDPG-H-ROT

VARIABLE _PDPG-F        \ the file
VARIABLE _PDPG-P        \ the page's record
VARIABLE _PDPG-WANT     \ the page asked for
VARIABLE _PDPG-I        \ pages still to pass
VARIABLE _PDPG-NODE     \ the node walked through: its number
VARIABLE _PDPG-NO       \ its object
VARIABLE _PDPG-VISITS
VARIABLE _PDPG-KIDS-O   \ the object holding its kids, when apart
VARIABLE _PDPG-KA   VARIABLE _PDPG-KU     \ its kids
VARIABLE _PDPG-PA   VARIABLE _PDPG-PU     \ the kids still to pass
VARIABLE _PDPG-KN   VARIABLE _PDPG-KO     \ a kid: its number and object
VARIABLE _PDPG-OFF      \ where the kid after the page starts in the kids

: _PDPG-P@    ( -- p )  _PDPG-P @ ;
: _PDPG-GET   ( num -- obj status )  _PDPG-F @ PDF-GET ;
: _PDPG-FREE  ( obj -- )  _PDPG-F @ PDF-OBJ-FREE ;
: _PDPG-MSRC  ( -- msrc )  _PDPG-F @ PDF-FILE-MSRC ;
: _PDPG-HAS+  ( bit -- )  _PDPG-P@ _PDPG.HAS DUP @ ROT OR SWAP ! ;

: PDF-PAGE-FILE  ( page -- file )  _PDPG.FILE @ ;
: PDF-PAGE-NUM  ( page -- num )  _PDPG.NUM @ ;
: PDF-PAGE-DICT  ( page -- va vu )  _PDPG.OBJ @ PDF-OBJ-VALUE DROP ;
: PDF-PAGE-RESOURCES  ( page -- va vu type )
    DUP _PDPG.RA @ OVER _PDPG.RU @ ROT _PDPG.RTYPE @ ;
: PDF-PAGE-BOX  ( page -- x0 y0 x1 y1 )
    _PDPG.BOX DUP @ OVER 8 + @ 2 PICK 16 + @ 3 PICK 24 + @
    >R >R >R >R DROP R> R> R> R> ;
: PDF-PAGE-ROTATE  ( page -- degrees )  _PDPG.ROTATE @ ;

\ =====================================================================
\  A dictionary's keys, read in one pass
\ =====================================================================

0 CONSTANT _PDPG-V-TYPE    1 CONSTANT _PDPG-V-KIDS    2 CONSTANT _PDPG-V-COUNT
3 CONSTANT _PDPG-V-RES     4 CONSTANT _PDPG-V-MEDIA   5 CONSTANT _PDPG-V-CROP
6 CONSTANT _PDPG-V-ROT     7 CONSTANT _PDPG-V-N

: _PDPG-NAME  ( k -- a u )
    DUP 0= IF DROP S" Type" EXIT THEN
    DUP 1 = IF DROP S" Kids" EXIT THEN
    DUP 2 = IF DROP S" Count" EXIT THEN
    DUP 3 = IF DROP S" Resources" EXIT THEN
    DUP 4 = IF DROP S" MediaBox" EXIT THEN
    5 = IF S" CropBox" EXIT THEN
    S" Rotate" ;

\ Each key's value as a span, or 0 0 PDF-T-END.
CREATE _PDPG-V _PDPG-V-N 3 * CELLS ALLOT
VARIABLE _PDPG-NA   VARIABLE _PDPG-NU

: _PDPG-V@  ( k -- va vu type )  3 * CELLS _PDPG-V + DUP @ OVER 8 + @ ROT 16 + @ ;

: _PDPG-READ  ( da du -- )
    _PDPG-V _PDPG-V-N 3 * CELLS 0 FILL
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE PDF-T-NAME <> IF 2DROP 2DROP EXIT THEN
        _PDPG-NU ! _PDPG-NA !
        PDF-VALUE DUP PDF-T-END = OVER PDF-T-BAD = OR IF DROP 2DROP 2DROP EXIT THEN
        _PDPG-V-N 0 DO
            _PDPG-NA @ _PDPG-NU @ I _PDPG-NAME PDF-NAME= IF
                I 3 * CELLS _PDPG-V + TUCK 16 + ! TUCK 8 + ! !
                0 0 0 LEAVE
            THEN
        LOOP DROP 2DROP
    AGAIN ;

\ A key's value, through a reference: OBJ is the object to give back, or 0.
: _PDPG-VALUE  ( k -- obj va vu type status )  _PDPG-V@ _PDPG-F @ PDF-RESOLVE ;

\ Whether the dictionary read is a node of the tree, not a page.
: _PDPG-NODE?  ( -- flag )
    _PDPG-V-TYPE _PDPG-V@ PDF-T-NAME = IF
        S" Page" PDF-NAME= IF 0 EXIT THEN
    ELSE 2DROP THEN
    _PDPG-V-KIDS _PDPG-V@ NIP NIP PDF-T-END <> ;

\ The node's /Count, at least 0.
: _PDPG-COUNT  ( -- n )
    _PDPG-V-COUNT _PDPG-V@ PDF-T-INT = IF PDF-INT 0 MAX ELSE 2DROP 0 THEN ;

\ =====================================================================
\  What a page inherits
\ =====================================================================

CREATE _PDPG-R 32 ALLOT
CREATE _PDPG-LETTER  0 , 0 , 612 16 LSHIFT , 792 16 LSHIFT ,

\ A rectangle's four numbers into _PDPG-R, its corners ordered: false
\ when it is no rectangle with an area.
: _PDPG-RECT  ( va vu -- ok? )
    2DUP PDF-ARRAY-N 4 < IF 2DROP 0 EXIT THEN
    4 0 DO
        2DUP I -ROT PDF-ARRAY@ DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF
            PDF-FIXED I CELLS _PDPG-R + !
        ELSE 2DROP 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP
    _PDPG-R @ _PDPG-R 16 + @ 2DUP MIN _PDPG-R ! MAX _PDPG-R 16 + !
    _PDPG-R 8 + @ _PDPG-R 24 + @ 2DUP MIN _PDPG-R 8 + ! MAX _PDPG-R 24 + !
    _PDPG-R @ _PDPG-R 16 + @ <  _PDPG-R 8 + @ _PDPG-R 24 + @ <  AND ;

\ Key K's rectangle, through a reference, into _PDPG-R.
: _PDPG-RECT@  ( k -- ok? status )
    _PDPG-VALUE ?DUP IF >R 2DROP DROP _PDPG-FREE 0 R> EXIT THEN
    PDF-T-ARRAY = IF _PDPG-RECT ELSE 2DROP 0 THEN
    SWAP _PDPG-FREE PDF-S-OK ;

\ The rotation, through a reference.
: _PDPG-ROT@  ( -- degrees ok? status )
    _PDPG-V-ROT _PDPG-VALUE ?DUP IF >R 2DROP DROP _PDPG-FREE 0 0 R> EXIT THEN
    PDF-T-INT = IF
        PDF-INT 90 / 4 MOD DUP 0< IF 4 + THEN 90 * -1
    ELSE 2DROP 0 0 THEN
    ROT _PDPG-FREE PDF-S-OK ;

\ The resources, through a reference, copied as what the node passes down.
: _PDPG-RES-DOWN  ( -- status )
    _PDPG-V-RES _PDPG-VALUE ?DUP IF >R 2DROP DROP _PDPG-FREE R> EXIT THEN
    PDF-T-DICT = IF
        0 _PDPG-P@ _PDPG.HRES PDF-BUF.U !
        _PDPG-P@ _PDPG.HRES _PDPG-MSRC PDF-BUF-APPEND 0= IF
            _PDPG-FREE PDF-S-MEMORY EXIT
        THEN
        _PDPG-H-RES _PDPG-HAS+
    ELSE 2DROP THEN
    _PDPG-FREE PDF-S-OK ;

\ What the node read passes down: its values over its parents'.
: _PDPG-DOWN!  ( -- status )
    _PDPG-RES-DOWN ?DUP IF EXIT THEN
    _PDPG-V-MEDIA _PDPG-RECT@ ?DUP IF NIP EXIT THEN
    IF _PDPG-R _PDPG-P@ _PDPG.HMEDIA 32 MOVE  _PDPG-H-MEDIA _PDPG-HAS+ THEN
    _PDPG-V-CROP _PDPG-RECT@ ?DUP IF NIP EXIT THEN
    IF _PDPG-R _PDPG-P@ _PDPG.HCROP 32 MOVE  _PDPG-H-CROP _PDPG-HAS+ THEN
    _PDPG-ROT@ ?DUP IF NIP NIP EXIT THEN
    IF _PDPG-P@ _PDPG.HROT !  _PDPG-H-ROT _PDPG-HAS+ ELSE DROP THEN
    PDF-S-OK ;

\ The page's own values over what its parent passes down.
: _PDPG-OWN!  ( -- status )
    _PDPG-P@ PDF-PAGE-DICT _PDPG-READ
    _PDPG-V-RES _PDPG-VALUE ?DUP IF >R 2DROP DROP _PDPG-FREE R> EXIT THEN
    DUP PDF-T-DICT = IF
        _PDPG-P@ _PDPG.RTYPE !  _PDPG-P@ _PDPG.RU !  _PDPG-P@ _PDPG.RA !
        _PDPG-P@ _PDPG.ROBJ !
    ELSE
        DROP 2DROP _PDPG-FREE
        _PDPG-P@ _PDPG.HAS @ _PDPG-H-RES AND IF
            _PDPG-P@ _PDPG.HRES PDF-BUF.A @ _PDPG-P@ _PDPG.RA !
            _PDPG-P@ _PDPG.HRES PDF-BUF.U @ _PDPG-P@ _PDPG.RU !
            PDF-T-DICT _PDPG-P@ _PDPG.RTYPE !
        THEN
    THEN
    _PDPG-V-MEDIA _PDPG-RECT@ ?DUP IF NIP EXIT THEN
    IF _PDPG-R ELSE
        _PDPG-P@ _PDPG.HAS @ _PDPG-H-MEDIA AND IF
            _PDPG-P@ _PDPG.HMEDIA
        ELSE _PDPG-LETTER THEN
    THEN _PDPG-P@ _PDPG.BOX 32 MOVE
    _PDPG-V-CROP _PDPG-RECT@ ?DUP IF NIP EXIT THEN
    0= IF
        _PDPG-P@ _PDPG.HAS @ _PDPG-H-CROP AND DUP IF
            _PDPG-P@ _PDPG.HCROP _PDPG-R 32 MOVE
        THEN
    ELSE -1 THEN
    IF
        _PDPG-P@ _PDPG.BOX >R
        _PDPG-R @ R@ @ MAX  _PDPG-R 8 + @ R@ 8 + @ MAX
        _PDPG-R 16 + @ R@ 16 + @ MIN  _PDPG-R 24 + @ R@ 24 + @ MIN
        2 PICK OVER < 4 PICK 3 PICK < AND IF
            R@ 24 + !  R@ 16 + !  R@ 8 + !  R> !
        ELSE 2DROP 2DROP R> DROP THEN
    THEN
    _PDPG-ROT@ ?DUP IF NIP NIP EXIT THEN
    0= IF
        DROP _PDPG-P@ _PDPG.HAS @ _PDPG-H-ROT AND IF _PDPG-P@ _PDPG.HROT @ ELSE 0 THEN
    THEN
    _PDPG-P@ _PDPG.ROTATE !  PDF-S-OK ;

\ =====================================================================
\  The page tree
\ =====================================================================

\ One more node read: false once the walk has read as many as the file
\ has objects.
: _PDPG-VISIT?  ( -- ok? )
    1 _PDPG-VISITS +!  _PDPG-VISITS @ _PDPG-F @ PDF-OBJECT-COUNT > 0= ;

\ The tree's root node, read into _PDPG-NO and _PDPG-V.
: _PDPG-ROOT  ( -- status )
    0 _PDPG-NO !
    S" Root" _PDPG-F @ PDF-TRAILER@ _PDPG-F @ PDF-RESOLVE
    ?DUP IF >R 2DROP DROP _PDPG-FREE R> EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDPG-FREE PDF-S-DAMAGED EXIT THEN
    S" Pages" 2SWAP PDF-DICT@ PDF-T-REF <> IF 2DROP _PDPG-FREE PDF-S-DAMAGED EXIT THEN
    PDF-REF@ DROP SWAP _PDPG-FREE
    _PDPG-VISIT? 0= IF DROP PDF-S-DAMAGED EXIT THEN
    DUP _PDPG-NODE !  _PDPG-GET ?DUP IF NIP EXIT THEN
    DUP PDF-OBJ-VALUE PDF-T-DICT <> IF 2DROP _PDPG-FREE PDF-S-DAMAGED EXIT THEN
    _PDPG-READ _PDPG-NO !  PDF-S-OK ;

\ The node's kids, through a reference.
: _PDPG-KIDS  ( -- status )
    _PDPG-V-KIDS _PDPG-VALUE ?DUP IF >R 2DROP DROP _PDPG-FREE R> EXIT THEN
    PDF-T-ARRAY <> IF 2DROP _PDPG-FREE PDF-S-DAMAGED EXIT THEN
    _PDPG-KU ! _PDPG-KA ! _PDPG-KIDS-O ! PDF-S-OK ;

-1 CONSTANT _PDPG-DOWN      \ the kid is a node holding the page
-2 CONSTANT _PDPG-LEAF      \ the kid is the page

\ Kid NUM: _PDPG-DOWN or _PDPG-LEAF when it holds page _PDPG-I, its
\ object kept in _PDPG-KO and its dictionary read; 0 when it does not,
\ its pages passed; or a status that ends the walk.
: _PDPG-KID  ( num -- result )
    DUP _PDPG-KN !  _PDPG-GET ?DUP IF
        NIP DUP PDF-S-MEMORY = IF EXIT THEN DROP 0 EXIT
    THEN
    DUP _PDPG-KO !  PDF-OBJ-VALUE
    PDF-T-DICT <> IF 2DROP _PDPG-KO @ _PDPG-FREE 0 EXIT THEN
    _PDPG-READ
    _PDPG-NODE? IF
        _PDPG-COUNT DUP _PDPG-I @ > IF DROP _PDPG-DOWN EXIT THEN
        NEGATE _PDPG-I +!
    ELSE
        _PDPG-I @ 0= IF _PDPG-LEAF EXIT THEN
        -1 _PDPG-I +!
    THEN
    _PDPG-KO @ _PDPG-FREE 0 ;

\ Pass along the kids from offset OFF to the one that holds page _PDPG-I,
\ noting where the kid after it starts.
: _PDPG-SCAN  ( off -- result )
    DUP _PDPG-KA @ + _PDPG-PA !  _PDPG-KU @ SWAP - _PDPG-PU !
    BEGIN
        _PDPG-PA @ _PDPG-PU @ PDF-VALUE >R 2SWAP _PDPG-PU ! _PDPG-PA ! R>
        DUP PDF-T-REF = IF
            DROP PDF-REF@ DROP _PDPG-KID ?DUP IF
                _PDPG-PA @ _PDPG-KA @ - _PDPG-OFF !  EXIT
            THEN
        ELSE
            DUP PDF-T-CLOSE-ARRAY = OVER PDF-T-END = OR SWAP PDF-T-BAD = OR IF
                2DROP PDF-S-MISSING EXIT
            THEN 2DROP
        THEN
    AGAIN ;

\ Forget the parent the record keeps and what it passes down.
: _PDPG-UNCURSOR  ( -- )
    _PDPG-P@ _PDPG.CPO @ _PDPG-FREE  _PDPG-P@ _PDPG.CKO @ _PDPG-FREE
    0 _PDPG-P@ _PDPG.CPO !  0 _PDPG-P@ _PDPG.CKO !  0 _PDPG-P@ _PDPG.CNUM !
    0 _PDPG-P@ _PDPG.HAS ! ;

\ The node walked through becomes the page's parent, kept.
: _PDPG-KEEP  ( -- )
    _PDPG-NODE @ _PDPG-P@ _PDPG.CNUM !  _PDPG-NO @ _PDPG-P@ _PDPG.CPO !
    _PDPG-KIDS-O @ _PDPG-P@ _PDPG.CKO !
    _PDPG-KA @ _PDPG-P@ _PDPG.CKA !  _PDPG-KU @ _PDPG-P@ _PDPG.CKU !
    _PDPG-OFF @ _PDPG-P@ _PDPG.COFF ! ;

\ Walk down from the node _PDPG-NO, its dictionary read, to page _PDPG-I,
\ which is left in _PDPG-KO and _PDPG-KN.
: _PDPG-DESCEND  ( -- status )
    BEGIN
        _PDPG-DOWN! ?DUP IF _PDPG-NO @ _PDPG-FREE EXIT THEN
        _PDPG-KIDS ?DUP IF _PDPG-NO @ _PDPG-FREE EXIT THEN
        _PDPG-KA @ _PDPG-KU @ PDF-TOKEN DROP 2DROP NIP _PDPG-KU @ SWAP -
        _PDPG-SCAN
        DUP _PDPG-LEAF = IF DROP _PDPG-KEEP PDF-S-OK EXIT THEN
        _PDPG-KIDS-O @ _PDPG-FREE  _PDPG-NO @ _PDPG-FREE
        DUP _PDPG-DOWN <> IF EXIT THEN DROP
        _PDPG-VISIT? 0= IF _PDPG-KO @ _PDPG-FREE PDF-S-DAMAGED EXIT THEN
        _PDPG-KO @ _PDPG-NO !  _PDPG-KN @ _PDPG-NODE !
    AGAIN ;

\ Page _PDPG-WANT from the parent the record keeps, when it is the next
\ kid there: true with the page in _PDPG-KO and _PDPG-KN.
: _PDPG-NEXT?  ( -- found? )
    _PDPG-P@ _PDPG.CNUM @ 0= IF 0 EXIT THEN
    _PDPG-P@ _PDPG.CI @ 1+ _PDPG-WANT @ <> IF 0 EXIT THEN
    _PDPG-P@ _PDPG.CKA @ _PDPG-KA !  _PDPG-P@ _PDPG.CKU @ _PDPG-KU !
    0 _PDPG-I !  _PDPG-P@ _PDPG.COFF @ _PDPG-SCAN
    DUP _PDPG-LEAF = IF DROP _PDPG-OFF @ _PDPG-P@ _PDPG.COFF ! -1 EXIT THEN
    _PDPG-DOWN = IF _PDPG-KO @ _PDPG-FREE THEN 0 ;

\ PDF-PAGE-COUNT ( file -- n status )   The root node's /Count.
: PDF-PAGE-COUNT  ( file -- n status )
    _PDPG-F !  0 _PDPG-VISITS !
    _PDPG-ROOT ?DUP IF 0 SWAP EXIT THEN
    _PDPG-NODE? IF _PDPG-COUNT ELSE 1 THEN
    _PDPG-NO @ _PDPG-FREE PDF-S-OK ;

\ PDF-PAGE-CLOSE ( page -- )   Give back the page's objects.
: PDF-PAGE-CLOSE  ( page -- )
    DUP _PDPG.FILE @ ?DUP IF
        >R DUP _PDPG.OBJ @ R@ PDF-OBJ-FREE  DUP _PDPG.ROBJ @ R> PDF-OBJ-FREE
    THEN
    0 OVER _PDPG.OBJ !  0 OVER _PDPG.ROBJ !  0 OVER _PDPG.RA !  0 OVER _PDPG.RU !
    PDF-T-END SWAP _PDPG.RTYPE ! ;

\ PDF-PAGE-END ( page -- )   Give back everything; the record is zeroed.
: PDF-PAGE-END  ( page -- )
    DUP PDF-PAGE-CLOSE
    DUP _PDPG.FILE @ ?DUP IF
        >R DUP _PDPG.CPO @ R@ PDF-OBJ-FREE  DUP _PDPG.CKO @ R@ PDF-OBJ-FREE
        DUP _PDPG.HRES R> PDF-FILE-MSRC PDF-BUF-FREE
    THEN
    PDF-PAGE-SIZE 0 FILL ;

\ PDF-PAGE-OPEN ( i file page -- status )   Page I, from 0.
: PDF-PAGE-OPEN  ( i file page -- status )
    _PDPG-P !  _PDPG-F !  _PDPG-WANT !
    _PDPG-P@ _PDPG.FILE @ ?DUP IF _PDPG-F @ <> IF _PDPG-P@ PDF-PAGE-END THEN THEN
    _PDPG-F @ _PDPG-P@ _PDPG.FILE !
    _PDPG-P@ PDF-PAGE-CLOSE
    _PDPG-NEXT? 0= IF
        _PDPG-UNCURSOR
        _PDPG-WANT @ _PDPG-I !  0 _PDPG-VISITS !
        _PDPG-ROOT ?DUP IF EXIT THEN
        _PDPG-NODE? IF
            _PDPG-DESCEND ?DUP IF EXIT THEN
        ELSE
            \ The root is the one page.
            _PDPG-I @ IF _PDPG-NO @ _PDPG-FREE PDF-S-MISSING EXIT THEN
            _PDPG-NO @ _PDPG-KO !  _PDPG-NODE @ _PDPG-KN !
        THEN
    THEN
    _PDPG-KO @ _PDPG-P@ _PDPG.OBJ !  _PDPG-KN @ _PDPG-P@ _PDPG.NUM !
    _PDPG-WANT @ _PDPG-P@ _PDPG.CI !
    _PDPG-OWN! DUP IF _PDPG-P@ PDF-PAGE-CLOSE THEN ;

\ =====================================================================
\  Content
\ =====================================================================

VARIABLE _PDPG-OUT      \ the buffer the content goes onto
VARIABLE _PDPG-STATUS
CREATE _PDPG-ONE-S PDF-BUF-SIZE 7 + ALLOT
: _PDPG-ONE  ( -- buf )  _PDPG-ONE-S 7 + -8 AND ;
CREATE _PDPG-NL 10 C,

\ The stream OBJ decoded onto the end of the output.
: _PDPG-DECODE+  ( obj -- status )
    DUP PDF-OBJ-STREAM? 0= IF DROP PDF-S-OK EXIT THEN
    _PDPG-ONE PDF-BUF-SIZE 0 FILL
    _PDPG-ONE _PDPG-F @ PDF-STREAM
    DUP PDF-S-MEMORY = IF EXIT THEN
    _PDPG-ONE PDF-BUF.A @ IF
        _PDPG-ONE PDF-BUF.A @ _PDPG-ONE PDF-BUF.U @ _PDPG-OUT @ _PDPG-MSRC PDF-BUF-APPEND
        _PDPG-NL 1 _PDPG-OUT @ _PDPG-MSRC PDF-BUF-APPEND AND
        _PDPG-ONE _PDPG-MSRC PDF-BUF-FREE
        0= IF DROP PDF-S-MEMORY THEN
    THEN ;

\ The stream a value names, decoded onto the end of the output.
: _PDPG-STREAM+  ( va vu type -- status )
    _PDPG-F @ PDF-RESOLVE ?DUP IF >R 2DROP DROP _PDPG-FREE R> EXIT THEN
    2DROP DROP DUP _PDPG-DECODE+ SWAP _PDPG-FREE ;

\ Keep a stream's status: the first that is not OK, or memory, which
\ ends the content.
: _PDPG-NOTED  ( status -- stop? )
    DUP PDF-S-MEMORY = IF _PDPG-STATUS ! -1 EXIT THEN
    _PDPG-STATUS @ 0= IF _PDPG-STATUS ! ELSE DROP THEN 0 ;

\ PDF-PAGE-CONTENTS ( page buf -- status )
\   The page's content streams, decoded one after another onto BUF.
: PDF-PAGE-CONTENTS  ( page buf -- status )
    _PDPG-OUT !  DUP _PDPG.FILE @ _PDPG-F !
    PDF-S-OK _PDPG-STATUS !
    S" Contents" ROT PDF-PAGE-DICT PDF-DICT@ _PDPG-F @ PDF-RESOLVE
    ?DUP IF >R 2DROP DROP _PDPG-FREE R> EXIT THEN
    PDF-T-ARRAY = IF
        PDF-TOKEN DROP 2DROP
        BEGIN
            PDF-VALUE DUP PDF-T-REF = IF
                _PDPG-STREAM+ _PDPG-NOTED IF 2DROP _PDPG-FREE _PDPG-STATUS @ EXIT THEN
            ELSE
                DUP PDF-T-CLOSE-ARRAY = OVER PDF-T-END = OR SWAP PDF-T-BAD = OR IF
                    2DROP 2DROP _PDPG-FREE _PDPG-STATUS @ EXIT
                THEN 2DROP
            THEN
        AGAIN
    THEN
    2DROP DUP IF DUP _PDPG-DECODE+ _PDPG-NOTED DROP THEN
    _PDPG-FREE _PDPG-STATUS @ ;
