\ =================================================================
\  tree.f  —  PDF number trees and name trees
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF- (public), _PDTR- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f
\
\  Public API:
\   PDF-NUMS@   ( key va vu type file -- obj va' vu' type' status )
\   PDF-NAMES@  ( ka ku va vu type file -- obj va' vu' type' status )
\   PDF-NUMS-EACH ( xt va vu type file -- status )
\
\  A number tree (PDF 32000-1 section 7.9.7) maps integers to values, a
\  name tree (7.9.6) strings to values: a structure's parent tree and a
\  document's page labels are number trees, its named destinations a
\  name tree.  The root is the value VA VU, through a reference.  A node
\  holds its pairs of keys and values in /Nums or /Names, or its kids,
\  whose /Limits hold the least and greatest keys below them.  A name
\  tree's keys are strings, compared by their bytes; KA KU is the key's
\  bytes.  A node's pairs are searched whole, so keys out of order are
\  still found.  PDF-NUMS-EACH visits every pair of a number tree instead,
\  a node's pairs before its kids', as a document's page labels need.
\
\  The result is the object holding the value, to give back with
\  PDF-OBJ-FREE, or 0 when the root holds it inline; and the value, or
\  0 0 PDF-T-END for a key the tree does not hold.  A node that cannot
\  be read holds no keys.  The status is PDF-S-MEMORY when the key was
\  not found and memory was refused, else PDF-S-OK.  A walk descends
\  through no more nodes than the file has objects, so a tree that loops
\  ends.  Memory comes from the file's memory source.  One call runs at
\  a time.
\ =================================================================

PROVIDED akashic-pdf-tree

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f

VARIABLE _PDTR-F        \ the file
VARIABLE _PDTR-NUM      \ a number tree's key
VARIABLE _PDTR-NAMES?   \ whether the tree is a name tree
VARIABLE _PDTR-KA   VARIABLE _PDTR-KU   \ a name tree's key
VARIABLE _PDTR-VISITS
VARIABLE _PDTR-STATUS   \ PDF-S-MEMORY once memory is refused
VARIABLE _PDTR-AO       \ the object holding a node's array, when apart

: _PDTR-FREE    ( obj -- )  _PDTR-F @ PDF-OBJ-FREE ;
: _PDTR-FAILED  ( status -- )  PDF-S-MEMORY = IF PDF-S-MEMORY _PDTR-STATUS ! THEN ;

\ The result, with its status.
: _PDTR-DONE  ( obj va vu type -- obj va vu type status )
    DUP PDF-T-END = IF _PDTR-STATUS @ ELSE PDF-S-OK THEN ;
: _PDTR-END   ( -- obj va vu type status )  0 0 0 PDF-T-END _PDTR-DONE ;

\ A value through a reference when it is of type WANT: false, its object
\ given back, when it is not or cannot be read.
: _PDTR-RESOLVE  ( va vu type want -- obj va' vu' ok? )
    >R _PDTR-F @ PDF-RESOLVE ?DUP IF
        _PDTR-FAILED R> 2DROP 2DROP _PDTR-FREE 0 0 0 0 EXIT
    THEN
    R> = IF -1 ELSE 2DROP _PDTR-FREE 0 0 0 0 THEN ;

\ A string's bytes, into a buffer that grows from the file's memory
\ source and is given back after each walk.
CREATE _PDTR-SB-S PDF-BUF-SIZE 7 + ALLOT
: _PDTR-SB  ( -- buf )  _PDTR-SB-S 7 + -8 AND ;
VARIABLE _PDTR-ST   VARIABLE _PDTR-SN

: _PDTR-STRING  ( va vu type -- a u ok? )
    _PDTR-ST !
    2DUP _PDTR-ST @ 0 0 PDF-STRING _PDTR-SN !
    _PDTR-SN @ _PDTR-SB _PDTR-F @ PDF-FILE-MSRC PDF-BUF-GROW 0= IF
        2DROP PDF-S-MEMORY _PDTR-STATUS !  0 0 0 EXIT
    THEN
    _PDTR-ST @ _PDTR-SB PDF-BUF.A @ _PDTR-SN @ PDF-STRING DROP
    _PDTR-SB PDF-BUF.A @ _PDTR-SN @ -1 ;

\ How a key compares with the one sought: -1 below, 0 the same, 1 above
\ or no key.
: _PDTR-COMPARE  ( va vu type -- n )
    _PDTR-NAMES? @ IF
        _PDTR-STRING 0= IF 2DROP 1 EXIT THEN
        _PDTR-KA @ _PDTR-KU @ COMPARE EXIT
    THEN
    PDF-T-INT <> IF 2DROP 1 EXIT THEN
    PDF-INT _PDTR-NUM @ 2DUP < IF 2DROP -1 ELSE > IF 1 ELSE 0 THEN THEN ;

\ Whether the node's /Limits hold the key.
: _PDTR-LIMITS?  ( da du -- flag )
    S" Limits" 2SWAP PDF-DICT@ PDF-T-ARRAY _PDTR-RESOLVE 0= IF 2DROP DROP 0 EXIT THEN
    2DUP 0 -ROT PDF-ARRAY@ _PDTR-COMPARE 1 < >R
    1 -ROT PDF-ARRAY@ _PDTR-COMPARE -1 > R> AND
    SWAP _PDTR-FREE ;

\ The node's kid whose limits hold the key: its object, or 0.
: _PDTR-KID  ( da du -- obj | 0 )
    S" Kids" 2SWAP PDF-DICT@ PDF-T-ARRAY _PDTR-RESOLVE 0= IF 2DROP DROP 0 EXIT THEN
    ROT _PDTR-AO !  PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-REF <> IF DROP 2DROP 2DROP _PDTR-AO @ _PDTR-FREE 0 EXIT THEN
        DROP PDF-REF@ DROP _PDTR-F @ PDF-GET ?DUP IF
            _PDTR-FAILED _PDTR-FREE
        ELSE
            DUP PDF-OBJ-VALUE PDF-T-DICT = IF
                _PDTR-LIMITS? IF NIP NIP _PDTR-AO @ _PDTR-FREE EXIT THEN
            ELSE 2DROP THEN
            _PDTR-FREE
        THEN
    AGAIN ;

\ The object that holds the value found: the array's, when apart.
: _PDTR-HOLDER  ( obj -- obj' )  _PDTR-AO @ ?DUP IF SWAP _PDTR-FREE THEN ;

\ The key's value among the pairs of the node OBJ holds, OBJ given back
\ when it holds none.
: _PDTR-PAIRS  ( obj da du -- obj' va vu type )
    _PDTR-NAMES? @ IF S" Names" ELSE S" Nums" THEN 2SWAP PDF-DICT@
    PDF-T-ARRAY _PDTR-RESOLVE 0= IF 2DROP DROP _PDTR-FREE 0 0 0 PDF-T-END EXIT THEN
    ROT _PDTR-AO !  PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-CLOSE-ARRAY = OVER PDF-T-END = OR OVER PDF-T-BAD = OR IF
            DROP 2DROP 2DROP _PDTR-FREE _PDTR-AO @ _PDTR-FREE 0 0 0 PDF-T-END EXIT
        THEN
        _PDTR-COMPARE 0= IF
            PDF-VALUE >R 2SWAP 2DROP R>  >R >R >R _PDTR-HOLDER R> R> R> EXIT
        THEN
        PDF-VALUE DROP 2DROP
    AGAIN ;

\ The key's value in the tree whose root is the value VA VU.
: _PDTR-WALK  ( va vu type -- obj va' vu' type' status )
    0 _PDTR-VISITS !  PDF-S-OK _PDTR-STATUS !
    PDF-T-DICT _PDTR-RESOLVE 0= IF 2DROP DROP _PDTR-END EXIT THEN
    BEGIN
        2DUP S" Kids" 2SWAP PDF-DICT@ NIP NIP PDF-T-END <>
    WHILE
        _PDTR-KID SWAP _PDTR-FREE
        DUP 0= IF DROP _PDTR-END EXIT THEN
        1 _PDTR-VISITS +!  _PDTR-VISITS @ _PDTR-F @ PDF-OBJECT-COUNT > IF
            _PDTR-FREE _PDTR-END EXIT
        THEN
        DUP PDF-OBJ-VALUE DROP
    REPEAT
    _PDTR-PAIRS _PDTR-DONE ;

\ PDF-NUMS@ ( key va vu type file -- obj va' vu' type' status )
\   KEY's value in the number tree whose root is the value VA VU.
: PDF-NUMS@  ( key va vu type file -- obj va' vu' type' status )
    _PDTR-F !  >R >R >R _PDTR-NUM !  0 _PDTR-NAMES? !  R> R> R> _PDTR-WALK ;

\ PDF-NAMES@ ( ka ku va vu type file -- obj va' vu' type' status )
\   The value of the key KA KU in the name tree whose root is VA VU.
: PDF-NAMES@  ( ka ku va vu type file -- obj va' vu' type' status )
    _PDTR-F !  >R >R >R _PDTR-KU ! _PDTR-KA !  -1 _PDTR-NAMES? !
    _PDTR-SB PDF-BUF-SIZE 0 FILL
    R> R> R> _PDTR-WALK
    _PDTR-SB _PDTR-F @ PDF-FILE-MSRC PDF-BUF-FREE ;

\ =====================================================================
\  Every pair of a number tree
\ =====================================================================

VARIABLE _PDTR-XT
VARIABLE _PDTR-GO      \ false once the visitor stops
VARIABLE _PDTR-K

\ The pairs of the array whose span after its "[" is A U, which OBJ
\ holds, while the visitor goes on; OBJ is given back.
: _PDTR-EACH-PAIRS  ( obj a u -- )
    BEGIN
        _PDTR-GO @ 0= IF 2DROP _PDTR-FREE EXIT THEN
        PDF-VALUE DUP PDF-T-INT <> IF DROP 2DROP 2DROP _PDTR-FREE EXIT THEN
        DROP PDF-INT _PDTR-K !
        PDF-VALUE DUP PDF-T-CLOSE-ARRAY = OVER PDF-T-END = OR OVER PDF-T-BAD = OR IF
            DROP 2DROP 2DROP _PDTR-FREE EXIT
        THEN
        >R >R >R _PDTR-K @ R> R> R> _PDTR-XT @ EXECUTE _PDTR-GO !
    AGAIN ;

\ The pairs of the node whose dictionary is DA DU, then its kids', in
\ order, through no more nodes than the file has objects.
: _PDTR-EACH  ( da du -- )
    2DUP S" Nums" 2SWAP PDF-DICT@ PDF-T-ARRAY _PDTR-RESOLVE IF
        PDF-TOKEN DROP 2DROP _PDTR-EACH-PAIRS
    ELSE 2DROP DROP THEN
    S" Kids" 2SWAP PDF-DICT@ PDF-T-ARRAY _PDTR-RESOLVE 0= IF 2DROP DROP EXIT THEN
    PDF-TOKEN DROP 2DROP
    BEGIN
        _PDTR-GO @ 0= IF 2DROP _PDTR-FREE EXIT THEN
        PDF-VALUE DUP PDF-T-REF <> IF DROP 2DROP 2DROP _PDTR-FREE EXIT THEN
        DROP PDF-REF@ DROP
        1 _PDTR-VISITS +!  _PDTR-VISITS @ _PDTR-F @ PDF-OBJECT-COUNT > IF
            DROP 2DROP _PDTR-FREE EXIT
        THEN
        _PDTR-F @ PDF-GET ?DUP IF _PDTR-FAILED _PDTR-FREE ELSE
            DUP PDF-OBJ-VALUE PDF-T-DICT = IF RECURSE ELSE 2DROP THEN
            _PDTR-FREE
        THEN
    AGAIN ;

\ PDF-NUMS-EACH ( xt va vu type file -- status )
\   Every pair of the number tree whose root is the value VA VU: XT ( key
\   va vu type -- go? ) for each, a node's pairs before its kids', until
\   it gives false.  A pair whose key is no integer ends its node's pairs.
\   The value is a span of a record given back once XT returns.
: PDF-NUMS-EACH  ( xt va vu type file -- status )
    _PDTR-F !  >R >R >R _PDTR-XT !  R> R> R>
    0 _PDTR-VISITS !  PDF-S-OK _PDTR-STATUS !  -1 _PDTR-GO !
    PDF-T-DICT _PDTR-RESOLVE 0= IF 2DROP DROP _PDTR-STATUS @ EXIT THEN
    ROT >R _PDTR-EACH R> _PDTR-FREE _PDTR-STATUS @ ;
