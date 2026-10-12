\ =================================================================
\  navigate.f  —  a PDF's destinations, links and outline
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-DEST, PDF-LINK-, PDF-LINKS-,
\                               PDF-OUTLINE-, PDF-ITEM- (public),
\                               _PDNV- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f, pdf/page.f,
\              pdf/tree.f, pdf/textstr.f
\
\  Public API:
\   PDF-DEST           ( va vu type file -- num left top status )
\   PDF-LINKS-SIZE     ( -- bytes )                    a page's links
\   PDF-LINKS-READ     ( page links -- status )
\   PDF-LINKS-FREE     ( links -- )
\   PDF-LINKS-COUNT    ( links -- n )
\   PDF-LINK           ( i links -- link )
\   PDF-LINK-RECT      ( link -- x0 y0 x1 y1 )
\   PDF-LINK-DEST      ( link links -- va vu type )
\   PDF-LINK-URI       ( link links -- a u )
\   PDF-OUTLINE-SIZE   ( -- bytes )                    a file's outline
\   PDF-OUTLINE-READ   ( file outline -- status )
\   PDF-OUTLINE-FREE   ( outline -- )
\   PDF-OUTLINE-COUNT  ( outline -- n )
\   PDF-OUTLINE-ITEM   ( i outline -- item )
\   PDF-ITEM-LEVEL     ( item -- level )
\   PDF-ITEM-TITLE     ( item outline -- a u )
\   PDF-ITEM-DEST      ( item outline -- va vu type )
\   PDF-ITEM-URI       ( item outline -- a u )
\
\  A destination (PDF 32000-1 section 12.3.2) is a value: an array that
\  names a page by its object; a name the catalog's /Dests maps to one,
\  or a string its /Names /Dests tree maps, each tried in the other's
\  place too, as writers mix them; through references, and a
\  dictionary's /D.  PDF-DEST reads it: the page object's number, and
\  the left and the top the destination shows in default space, 16.16:
\  the left for /XYZ and /FitR, the top for /XYZ, /FitH, /FitBH and
\  /FitR, each -1 when it gives none.  Its status is PDF-S-MISSING when the
\  destination names no page, PDF-S-MEMORY when memory is refused.
\  PDF-PAGE-INDEX (pdf/page.f) turns the page object into an index.
\
\  PDF-LINKS-READ reads an open page's link annotations (12.5.6.5): each
\  one's rectangle, its corners ordered, and where it goes.  A link to a
\  destination, through /Dest or a GoTo action's /D, keeps the
\  destination's value as it is, for PDF-DEST to read when the link is
\  followed, so a page with many links is read without looking any up.
\  A link to the web, through a URI action (12.6.4.7), keeps the
\  address's bytes.  Links that go nowhere a reader can follow are left
\  out.
\
\  PDF-OUTLINE-READ reads the document's outline (12.3.3) in the order a
\  reader shows it, each item's children after it: its level, from 0 at
\  the top; its title, as UTF-8 (pdf/textstr.f); and where it goes, as a
\  link does, or nowhere.  It reads each item once, keeping a bit for
\  each of the file's objects, so an outline that loops ends.
\
\  A destination's value, an address and a title are spans of the
\  record, valid until it is read again or given back.  What cannot be
\  read is left out; memory refused fails a read with PDF-S-MEMORY.  A
\  locked file's links, outline and destinations give PDF-S-LOCKED: their
\  strings cannot be read.  Memory comes from the file's memory source.
\  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-navigate

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f
REQUIRE page.f
REQUIRE tree.f
REQUIRE textstr.f

VARIABLE _PDNV-F        \ the file
VARIABLE _PDNV-STATUS   \ PDF-S-MEMORY once memory is refused

: _PDNV-FREE    ( obj -- )  _PDNV-F @ PDF-OBJ-FREE ;
: _PDNV-MSRC    ( -- msrc )  _PDNV-F @ PDF-FILE-MSRC ;
: _PDNV-FAILED  ( status -- )  PDF-S-MEMORY = IF PDF-S-MEMORY _PDNV-STATUS ! THEN ;

\ A value through a reference when it is of type WANT: false, its object
\ given back, when it is not or cannot be read.
: _PDNV-RESOLVE  ( va vu type want -- obj va' vu' ok? )
    >R _PDNV-F @ PDF-RESOLVE ?DUP IF
        _PDNV-FAILED R> 2DROP 2DROP _PDNV-FREE 0 0 0 0 EXIT
    THEN
    R> = IF -1 ELSE 2DROP _PDNV-FREE 0 0 0 0 THEN ;

VARIABLE _PDNV-SN   VARIABLE _PDNV-SBUF   VARIABLE _PDNV-SO

\ A string value's bytes, through a reference, onto the end of BUF:
\ false when memory is refused.  A value that is no string has none.
: _PDNV-BYTES+  ( va vu type buf -- ok? )
    _PDNV-SBUF !
    _PDNV-F @ PDF-RESOLVE ?DUP IF _PDNV-FAILED DROP 2DROP _PDNV-FREE _PDNV-STATUS @ 0= EXIT THEN
    >R ROT _PDNV-SO ! R>
    >R 2DUP R@ 0 0 PDF-STRING _PDNV-SN !
    _PDNV-SBUF @ PDF-BUF.U @ _PDNV-SN @ +  _PDNV-SBUF @ _PDNV-MSRC PDF-BUF-GROW 0= IF
        R> DROP 2DROP  _PDNV-SO @ _PDNV-FREE  PDF-S-MEMORY _PDNV-STATUS !  0 EXIT
    THEN
    R> _PDNV-SBUF @ DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + _PDNV-SN @ PDF-STRING
    _PDNV-SBUF @ PDF-BUF.U +!  _PDNV-SO @ _PDNV-FREE  -1 ;

\ A named destination's key, or a title before it is read as text: a
\ buffer that grows from the file's memory source.
CREATE _PDNV-SB-S PDF-BUF-SIZE 7 + ALLOT
: _PDNV-SB  ( -- buf )  _PDNV-SB-S 7 + -8 AND ;

\ =====================================================================
\  Destinations
\ =====================================================================

\ Element I of an array as a number, 16.16, or -1 when there is no such
\ element, or it is no number, as null is not; or -1 for I.
: _PDNV-NUMBER  ( aa au i -- f | -1 )
    DUP 0< IF DROP 2DROP -1 EXIT THEN
    -ROT PDF-ARRAY@ DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF PDF-FIXED ELSE 2DROP -1 THEN ;

\ An explicit destination: [page /XYZ left top zoom], /FitH or /FitBH
\ with a top, /FitR left bottom right top, or another fit; its page
\ object, left and top, each -1 when it gives none.  NUM is 0 when it
\ names no page by its object.
: _PDNV-ARRAY  ( aa au -- num left top )
    2DUP 0 -ROT PDF-ARRAY@ PDF-T-REF = IF PDF-REF@ DROP ELSE 2DROP 2DROP 0 -1 -1 EXIT THEN
    >R
    2DUP 1 -ROT PDF-ARRAY@ PDF-T-NAME = IF
        2DUP S" XYZ" PDF-NAME= IF 2DROP 2 3 ELSE
        2DUP S" FitH" PDF-NAME= >R 2DUP S" FitBH" PDF-NAME= R> OR IF 2DROP -1 2 ELSE
        S" FitR" PDF-NAME= IF 2 5 ELSE -1 -1 THEN THEN THEN
    ELSE 2DROP -1 -1 THEN                                 ( aa au li ti )
    >R >R 2DUP R> _PDNV-NUMBER -ROT R> _PDNV-NUMBER
    R> -ROT ;

\ An explicit destination, or a dictionary's /D, in OBJ, given back.
: _PDNV-EXPLICIT  ( obj va vu type -- num left top )
    DUP PDF-T-DICT = IF
        DROP S" D" 2SWAP PDF-DICT@ PDF-T-ARRAY _PDNV-RESOLVE
        IF _PDNV-ARRAY 3 ROLL _PDNV-FREE ELSE 2DROP DROP 0 -1 -1 THEN
    ELSE
        PDF-T-ARRAY = IF _PDNV-ARRAY ELSE 2DROP 0 -1 -1 THEN
    THEN
    3 ROLL _PDNV-FREE ;

\ A value naming an explicit destination, through a reference.
: _PDNV-VALUE  ( va vu type -- num left top )
    _PDNV-F @ PDF-RESOLVE ?DUP IF _PDNV-FAILED DROP 2DROP _PDNV-FREE 0 -1 -1 EXIT THEN
    _PDNV-EXPLICIT ;

VARIABLE _PDNV-CO   VARIABLE _PDNV-CA   VARIABLE _PDNV-CU   \ the catalog
VARIABLE _PDNV-NAME?   \ whether the key was a name

\ The catalog, read: false when it cannot be.
: _PDNV-CATALOG  ( -- ok? )
    S" Root" _PDNV-F @ PDF-TRAILER@ PDF-T-DICT _PDNV-RESOLVE
    IF _PDNV-CU ! _PDNV-CA ! _PDNV-CO ! -1 ELSE 2DROP DROP 0 THEN ;

\ The destination the catalog's /Dests gives the key KA KU.
: _PDNV-IN-DESTS  ( ka ku -- num left top )
    S" Dests" _PDNV-CA @ _PDNV-CU @ PDF-DICT@ PDF-T-DICT _PDNV-RESOLVE
    0= IF 2DROP DROP 2DROP 0 -1 -1 EXIT THEN
    ROT >R PDF-DICT@ _PDNV-VALUE R> _PDNV-FREE ;

\ The destination the catalog's /Names /Dests tree gives the key KA KU.
: _PDNV-IN-NAMES  ( ka ku -- num left top )
    S" Names" _PDNV-CA @ _PDNV-CU @ PDF-DICT@ PDF-T-DICT _PDNV-RESOLVE
    0= IF 2DROP DROP 2DROP 0 -1 -1 EXIT THEN
    ROT >R  S" Dests" 2SWAP PDF-DICT@ _PDNV-F @ PDF-NAMES@
    _PDNV-FAILED  _PDNV-VALUE 3 ROLL _PDNV-FREE  R> _PDNV-FREE ;

: _PDNV-LOOKUP  ( ka ku dests? -- num left top )
    IF _PDNV-IN-DESTS ELSE _PDNV-IN-NAMES THEN ;

\ The destination named by the key in _PDNV-SB: a name through /Dests
\ first, a string through the /Names tree first, then the other.
: _PDNV-NAMED  ( -- num left top )
    _PDNV-CATALOG 0= IF 0 -1 -1 EXIT THEN
    _PDNV-SB PDF-BUF.A @ _PDNV-SB PDF-BUF.U @
    2DUP _PDNV-NAME? @ _PDNV-LOOKUP
    2 PICK IF >R >R >R 2DROP R> R> R> ELSE DROP 2DROP _PDNV-NAME? @ 0= _PDNV-LOOKUP THEN
    _PDNV-CO @ _PDNV-FREE ;

\ A name's or a string's bytes into _PDNV-SB, the key of a named
\ destination: false when memory is refused.
: _PDNV-KEY  ( va vu type -- ok? )
    0 _PDNV-SB PDF-BUF.U !
    DUP PDF-T-NAME = DUP _PDNV-NAME? ! IF
        DROP 2DUP 0 0 PDF-NAME DUP _PDNV-SB _PDNV-MSRC PDF-BUF-GROW 0= IF
            DROP 2DROP  PDF-S-MEMORY _PDNV-STATUS !  0 EXIT
        THEN
        DUP _PDNV-SB PDF-BUF.U !  >R _PDNV-SB PDF-BUF.A @ R> PDF-NAME DROP -1 EXIT
    THEN
    _PDNV-SB _PDNV-BYTES+ ;

\ A destination's page, left and top, through a reference.
: _PDNV-DEST  ( va vu type -- num left top )
    _PDNV-F @ PDF-RESOLVE ?DUP IF _PDNV-FAILED DROP 2DROP _PDNV-FREE 0 -1 -1 EXIT THEN
    DUP PDF-T-NAME = OVER PDF-T-STRING = OR OVER PDF-T-HEX = OR IF
        _PDNV-KEY SWAP _PDNV-FREE IF _PDNV-NAMED ELSE 0 -1 -1 THEN EXIT
    THEN
    _PDNV-EXPLICIT ;

\ Start a read of FILE: false, with PDF-S-LOCKED, when it is locked.
: _PDNV-START  ( file -- ok? )
    DUP _PDNV-F !  PDF-S-OK _PDNV-STATUS !  _PDNV-SB PDF-BUF-SIZE 0 FILL
    PDF-FILE-LOCKED? 0= ;

\ PDF-DEST ( va vu type file -- num left top status )
\   A destination's page object, left and top.
: PDF-DEST  ( va vu type file -- num left top status )
    _PDNV-START 0= IF DROP 2DROP 0 -1 -1 PDF-S-LOCKED EXIT THEN
    _PDNV-DEST  _PDNV-SB _PDNV-MSRC PDF-BUF-FREE
    2 PICK IF PDF-S-OK ELSE _PDNV-STATUS @ ?DUP 0= IF PDF-S-MISSING THEN THEN ;

\ =====================================================================
\  Targets: where a link or an outline item goes
\ =====================================================================

0 CONSTANT _PDNV-NONE
1 CONSTANT _PDNV-GOTO
2 CONSTANT _PDNV-URI

: _PDNV-NOWHERE  ( -- obj va vu type kind )  0 0 0 PDF-T-END _PDNV-NONE ;

\ Where the dictionary DA DU goes: a destination, /Dest or a GoTo
\ action's /D, or a URI action's /URI, as its value; OBJ is the action's
\ object to give back, or 0.
: _PDNV-TARGET  ( da du -- obj va vu type kind )
    2DUP S" Dest" 2SWAP PDF-DICT@ DUP PDF-T-END <> IF
        >R 2SWAP 2DROP 0 -ROT R> _PDNV-GOTO EXIT
    THEN DROP 2DROP
    S" A" 2SWAP PDF-DICT@ PDF-T-DICT _PDNV-RESOLVE 0= IF 2DROP DROP _PDNV-NOWHERE EXIT THEN
    2DUP S" S" 2SWAP PDF-DICT@ PDF-T-NAME <> IF 2DROP 2DROP _PDNV-FREE _PDNV-NOWHERE EXIT THEN
    2DUP S" GoTo" PDF-NAME= IF 2DROP S" D" 2SWAP PDF-DICT@ _PDNV-GOTO EXIT THEN
    S" URI" PDF-NAME= IF S" URI" 2SWAP PDF-DICT@ _PDNV-URI EXIT THEN
    2DROP _PDNV-FREE _PDNV-NOWHERE ;

\ A target's four cells: its kind, its destination's type, and its
\ bytes' offset and length in a buffer.
VARIABLE _PDNV-T    \ the target's cells
VARIABLE _PDNV-TB   \ the buffer its bytes go onto

\ The target into _PDNV-T, its bytes onto _PDNV-TB: a destination's value
\ as it is, an address's bytes.  OBJ is given back.  False when memory is
\ refused.
: _PDNV-TARGET!  ( obj va vu type kind -- ok? )
    _PDNV-T @ 32 0 FILL
    OVER PDF-T-END = IF 2DROP 2DROP _PDNV-FREE -1 EXIT THEN
    _PDNV-TB @ PDF-BUF.U @ _PDNV-T @ 16 + !
    DUP _PDNV-T @ !
    _PDNV-URI = IF
        _PDNV-TB @ _PDNV-BYTES+
    ELSE
        _PDNV-T @ 8 + !  _PDNV-TB @ _PDNV-MSRC PDF-BUF-APPEND
        DUP 0= IF PDF-S-MEMORY _PDNV-STATUS ! THEN
    THEN
    _PDNV-TB @ PDF-BUF.U @ _PDNV-T @ 16 + @ - DUP _PDNV-T @ 24 + !
    0= IF _PDNV-NONE _PDNV-T @ ! THEN
    SWAP _PDNV-FREE ;

\ A target's destination, its value's span in BUF, or 0 0 PDF-T-END.
: _PDNV-DEST@  ( t buf -- va vu type )
    OVER @ _PDNV-GOTO <> IF 2DROP 0 0 PDF-T-END EXIT THEN
    PDF-BUF.A @ OVER 16 + @ +  OVER 24 + @  ROT 8 + @ ;

\ A target's address, its bytes in BUF, or 0 0.
: _PDNV-URI@  ( t buf -- a u )
    OVER @ _PDNV-URI <> IF 2DROP 0 0 EXIT THEN
    PDF-BUF.A @ OVER 16 + @ +  SWAP 24 + @ ;

\ =====================================================================
\  Links
\ =====================================================================

\ The record: its memory source, its links, and the bytes of their
\ targets.  A link: its rectangle and its target.
: _PDNV.MSRC  ( l -- a )        ;
: _PDNV.L     ( l -- buf )  8 + ;
: _PDNV.T     ( l -- buf ) 32 + ;
56 CONSTANT PDF-LINKS-SIZE
64 CONSTANT _PDNV-LINK

: PDF-LINKS-COUNT  ( links -- n )  _PDNV.L PDF-BUF.U @ _PDNV-LINK / ;
: PDF-LINK         ( i links -- link )  _PDNV.L PDF-BUF.A @ SWAP _PDNV-LINK * + ;
: PDF-LINK-RECT    ( link -- x0 y0 x1 y1 )
    DUP @ OVER 8 + @ 2 PICK 16 + @ 3 PICK 24 + @ >R >R >R >R DROP R> R> R> R> ;
: PDF-LINK-DEST    ( link links -- va vu type )  >R 32 + R> _PDNV.T _PDNV-DEST@ ;
: PDF-LINK-URI     ( link links -- a u )  >R 32 + R> _PDNV.T _PDNV-URI@ ;

: PDF-LINKS-FREE  ( links -- )
    DUP _PDNV.MSRC @ ?DUP IF
        >R DUP _PDNV.L R@ PDF-BUF-FREE  DUP _PDNV.T R> PDF-BUF-FREE
    THEN
    PDF-LINKS-SIZE 0 FILL ;

VARIABLE _PDNV-LK     \ the record
CREATE _PDNV-NEW _PDNV-LINK ALLOT

\ A rectangle, through a reference, into the new link, its corners
\ ordered: false when it is none.
: _PDNV-RECT  ( va vu type -- ok? )
    PDF-T-ARRAY _PDNV-RESOLVE 0= IF 2DROP DROP 0 EXIT THEN
    2DUP PDF-ARRAY-N 4 < IF 2DROP _PDNV-FREE 0 EXIT THEN
    4 0 DO
        2DUP I -ROT PDF-ARRAY@ DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF
            PDF-FIXED I CELLS _PDNV-NEW + !
        ELSE 2DROP 2DROP _PDNV-FREE 0 UNLOOP EXIT THEN
    LOOP 2DROP _PDNV-FREE
    _PDNV-NEW @ _PDNV-NEW 16 + @ 2DUP MIN _PDNV-NEW ! MAX _PDNV-NEW 16 + !
    _PDNV-NEW 8 + @ _PDNV-NEW 24 + @ 2DUP MIN _PDNV-NEW 8 + ! MAX _PDNV-NEW 24 + !
    -1 ;

\ One annotation, kept when it is a link that goes somewhere: false when
\ memory is refused.
: _PDNV-ANNOT  ( va vu type -- ok? )
    PDF-T-DICT _PDNV-RESOLVE 0= IF 2DROP DROP -1 EXIT THEN          ( obj da du )
    2DUP S" Subtype" 2SWAP PDF-DICT@ PDF-T-NAME = IF S" Link" PDF-NAME= ELSE 2DROP 0 THEN
    0= IF 2DROP _PDNV-FREE -1 EXIT THEN
    2DUP S" Rect" 2SWAP PDF-DICT@ _PDNV-RECT 0= IF 2DROP _PDNV-FREE -1 EXIT THEN
    _PDNV-TARGET _PDNV-TARGET!  SWAP _PDNV-FREE
    0= IF 0 EXIT THEN
    _PDNV-NEW 32 + @ _PDNV-NONE = IF -1 EXIT THEN
    _PDNV-NEW _PDNV-LINK _PDNV-LK @ _PDNV.L _PDNV-MSRC PDF-BUF-APPEND ;

\ PDF-LINKS-READ ( page links -- status )   An open page's links.
: PDF-LINKS-READ  ( page links -- status )
    DUP _PDNV-LK !  PDF-LINKS-SIZE 0 FILL
    DUP PDF-PAGE-FILE _PDNV-START 0= IF DROP PDF-S-LOCKED EXIT THEN
    _PDNV-MSRC _PDNV-LK @ _PDNV.MSRC !
    _PDNV-NEW 32 + _PDNV-T !  _PDNV-LK @ _PDNV.T _PDNV-TB !
    S" Annots" ROT PDF-PAGE-DICT PDF-DICT@ PDF-T-ARRAY _PDNV-RESOLVE
    0= IF 2DROP DROP _PDNV-STATUS @ EXIT THEN
    ROT >R  PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-REF = OVER PDF-T-DICT = OR IF
            _PDNV-ANNOT 0= IF 2DROP R> _PDNV-FREE PDF-S-MEMORY EXIT THEN
        ELSE
            DUP PDF-T-CLOSE-ARRAY = OVER PDF-T-END = OR SWAP PDF-T-BAD = OR IF
                2DROP 2DROP R> _PDNV-FREE _PDNV-STATUS @ EXIT
            THEN 2DROP
        THEN
    AGAIN ;

\ =====================================================================
\  The outline
\ =====================================================================

\ The record: its memory source, its items, and their titles' and
\ targets' bytes.  An item: its level, its title's offset and length,
\ and its target.
: _PDNV.OMSRC  ( o -- a )        ;
: _PDNV.OI     ( o -- buf )  8 + ;
: _PDNV.OT     ( o -- buf ) 32 + ;
56 CONSTANT PDF-OUTLINE-SIZE
56 CONSTANT _PDNV-ITEM

: PDF-OUTLINE-COUNT  ( outline -- n )  _PDNV.OI PDF-BUF.U @ _PDNV-ITEM / ;
: PDF-OUTLINE-ITEM   ( i outline -- item )  _PDNV.OI PDF-BUF.A @ SWAP _PDNV-ITEM * + ;
: PDF-ITEM-LEVEL     ( item -- level )  @ ;
: PDF-ITEM-TITLE     ( item outline -- a u )
    _PDNV.OT PDF-BUF.A @ OVER 8 + @ + SWAP 16 + @ ;
: PDF-ITEM-DEST      ( item outline -- va vu type )  >R 24 + R> _PDNV.OT _PDNV-DEST@ ;
: PDF-ITEM-URI       ( item outline -- a u )  >R 24 + R> _PDNV.OT _PDNV-URI@ ;

: PDF-OUTLINE-FREE  ( outline -- )
    DUP _PDNV.OMSRC @ ?DUP IF
        >R DUP _PDNV.OI R@ PDF-BUF-FREE  DUP _PDNV.OT R> PDF-BUF-FREE
    THEN
    PDF-OUTLINE-SIZE 0 FILL ;

VARIABLE _PDNV-OL     \ the record
CREATE _PDNV-TODO-S PDF-BUF-SIZE 7 + ALLOT
: _PDNV-TODO  ( -- buf )  _PDNV-TODO-S 7 + -8 AND ;   \ items to read: number, level
CREATE _PDNV-PAIR 16 ALLOT
CREATE _PDNV-ITEMNEW _PDNV-ITEM ALLOT
VARIABLE _PDNV-LEVEL
VARIABLE _PDNV-SEEN   VARIABLE _PDNV-SEENB    \ a bit for each object, its bytes

\ Whether item NUM was read already, or is none of the file's objects;
\ it is marked read.
: _PDNV-SEEN?  ( num -- flag )
    DUP _PDNV-F @ PDF-OBJECT-COUNT < 0= IF DROP -1 EXIT THEN
    DUP 3 RSHIFT _PDNV-SEEN @ +  1 ROT 7 AND LSHIFT        ( a bit )
    OVER C@ OVER AND IF 2DROP -1 EXIT THEN
    OVER C@ OR SWAP C!  0 ;

\ Item NUM at LEVEL, to read later: false when memory is refused.
: _PDNV-TODO+  ( num level -- ok? )
    _PDNV-PAIR 8 + !  _PDNV-PAIR !  _PDNV-PAIR 16 _PDNV-TODO _PDNV-MSRC PDF-BUF-APPEND ;

\ A reference in the dictionary DA DU, by key: its number, or 0.
: _PDNV-REF@  ( key-a key-u da du -- num | 0 )
    PDF-DICT@ PDF-T-REF = IF PDF-REF@ DROP ELSE 2DROP 0 THEN ;

\ An item's title, as UTF-8, onto the record's titles.
: _PDNV-TITLE  ( da du -- ok? )
    S" Title" 2SWAP PDF-DICT@  0 _PDNV-SB PDF-BUF.U !  _PDNV-SB _PDNV-BYTES+ 0= IF 0 EXIT THEN
    _PDNV-SB PDF-BUF.A @ _PDNV-SB PDF-BUF.U @ _PDNV-OL @ _PDNV.OT _PDNV-MSRC PDF-TEXTSTR+ ;

\ Read item NUM: its title, its target, then its next and its first kid
\ to read, the kid first: false when memory is refused.
: _PDNV-OITEM  ( num -- ok? )
    _PDNV-F @ PDF-GET ?DUP IF _PDNV-FAILED _PDNV-FREE _PDNV-STATUS @ 0= EXIT THEN
    DUP PDF-OBJ-VALUE PDF-T-DICT <> IF 2DROP _PDNV-FREE -1 EXIT THEN    ( obj da du )
    _PDNV-ITEMNEW _PDNV-ITEM 0 FILL  _PDNV-LEVEL @ _PDNV-ITEMNEW !
    _PDNV-OL @ _PDNV.OT PDF-BUF.U @ _PDNV-ITEMNEW 8 + !
    2DUP _PDNV-TITLE 0= IF 2DROP _PDNV-FREE 0 EXIT THEN
    _PDNV-OL @ _PDNV.OT PDF-BUF.U @ _PDNV-ITEMNEW 8 + @ - _PDNV-ITEMNEW 16 + !
    2DUP _PDNV-TARGET _PDNV-TARGET! 0= IF 2DROP _PDNV-FREE 0 EXIT THEN
    2DUP S" Next" 2SWAP _PDNV-REF@ ?DUP IF
        _PDNV-LEVEL @ _PDNV-TODO+ 0= IF 2DROP _PDNV-FREE 0 EXIT THEN
    THEN
    S" First" 2SWAP _PDNV-REF@ ?DUP IF
        _PDNV-LEVEL @ 1+ _PDNV-TODO+ 0= IF _PDNV-FREE 0 EXIT THEN
    THEN
    _PDNV-FREE
    _PDNV-ITEMNEW _PDNV-ITEM _PDNV-OL @ _PDNV.OI _PDNV-MSRC PDF-BUF-APPEND ;

\ The outline's first item, through the catalog's /Outlines: or 0.
: _PDNV-FIRST  ( -- num )
    _PDNV-CATALOG 0= IF 0 EXIT THEN
    S" Outlines" _PDNV-CA @ _PDNV-CU @ PDF-DICT@ PDF-T-DICT _PDNV-RESOLVE
    IF S" First" 2SWAP _PDNV-REF@ SWAP _PDNV-FREE ELSE 2DROP DROP 0 THEN
    _PDNV-CO @ _PDNV-FREE ;

: _PDNV-OUTLINE-DONE  ( status -- status )
    _PDNV-TODO _PDNV-MSRC PDF-BUF-FREE  _PDNV-SB _PDNV-MSRC PDF-BUF-FREE
    _PDNV-SEEN @ ?DUP IF _PDNV-SEENB @ _PDNV-MSRC MSRC-FREE THEN ;

\ PDF-OUTLINE-READ ( file outline -- status )   The document's outline.
: PDF-OUTLINE-READ  ( file outline -- status )
    DUP _PDNV-OL !  PDF-OUTLINE-SIZE 0 FILL
    _PDNV-START 0= IF PDF-S-LOCKED EXIT THEN
    _PDNV-MSRC _PDNV-OL @ _PDNV.OMSRC !
    _PDNV-ITEMNEW 24 + _PDNV-T !  _PDNV-OL @ _PDNV.OT _PDNV-TB !
    _PDNV-TODO PDF-BUF-SIZE 0 FILL
    _PDNV-F @ PDF-OBJECT-COUNT 7 + 3 RSHIFT 1 MAX DUP _PDNV-SEENB !
    _PDNV-MSRC MSRC-ALLOC DUP _PDNV-SEEN !
    0= IF PDF-S-MEMORY _PDNV-OUTLINE-DONE EXIT THEN
    _PDNV-SEEN @ _PDNV-SEENB @ 0 FILL
    _PDNV-FIRST ?DUP IF 0 _PDNV-TODO+ 0= IF PDF-S-MEMORY _PDNV-OUTLINE-DONE EXIT THEN THEN
    BEGIN _PDNV-TODO PDF-BUF.U @ WHILE
        -16 _PDNV-TODO PDF-BUF.U +!
        _PDNV-TODO DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + DUP 8 + @ _PDNV-LEVEL ! @
        DUP _PDNV-SEEN? IF DROP ELSE
            _PDNV-OITEM 0= IF PDF-S-MEMORY _PDNV-OUTLINE-DONE EXIT THEN
        THEN
    REPEAT
    _PDNV-STATUS @ _PDNV-OUTLINE-DONE ;
