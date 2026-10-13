\ =================================================================
\  labels.f  —  a PDF's page labels
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-LABELS-, PDF-LABEL (public),
\                               _PDLB- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f, pdf/tree.f,
\              pdf/textstr.f, utils/string.f
\
\  Public API:
\   PDF-LABELS-SIZE  ( -- bytes )                  a labels record
\   PDF-LABELS-READ  ( file labels -- status )
\   PDF-LABELS-FREE  ( labels -- )
\   PDF-LABEL        ( i labels buf -- ok? )
\
\  A document's page labels (PDF 32000-1 section 12.4.2) name its pages
\  as a reader sees them printed: iv, 12, A-3.  The catalog's /PageLabels
\  number tree maps the index of the first page of each range to how the
\  range is labelled: a style, /S, of /D decimal, /R and /r roman, /A and
\  /a letters, or none; a prefix, /P, a text string; and the number its
\  first page takes, /St, 1 when absent.
\
\  PDF-LABELS-READ reads every range once (PDF-NUMS-EACH), so a page's
\  label then costs no reading.  PDF-LABEL adds page I's label, UTF-8,
\  onto the buffer BUF (pdf/filter.f), from the labels' memory source: its
\  range's prefix, then the number its first page takes plus I less the
\  range's first page, in the range's style.  Letters go A to Z, then AA
\  to ZZ, and on.  A page before every range, or in a document without
\  page labels, is labelled with its number from 1.  A range that cannot
\  be read is left out.
\
\  Memory comes from the file's memory source.  PDF-LABELS-READ gives
\  PDF-S-OK, PDF-S-MEMORY, or PDF-S-LOCKED for a locked file, whose
\  prefixes cannot be read; a damaged tree gives the ranges read.
\ =================================================================

PROVIDED akashic-pdf-labels

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f
REQUIRE tree.f
REQUIRE textstr.f
REQUIRE ../utils/string.f

\ The record: its memory source, the ranges, and their prefixes' bytes.
: _PDLB.MSRC    ( l -- a )        ;
: _PDLB.RANGES  ( l -- buf )  8 + ;
: _PDLB.TEXT    ( l -- buf ) 32 + ;
56 CONSTANT PDF-LABELS-SIZE

\ A range: its first page, its style, the number its first page takes,
\ and its prefix's offset and length.
40 CONSTANT _PDLB-RANGE

0 CONSTANT _PDLB-NONE
1 CONSTANT _PDLB-DECIMAL
2 CONSTANT _PDLB-ROMAN
3 CONSTANT _PDLB-ROMAN-LOWER
4 CONSTANT _PDLB-LETTERS
5 CONSTANT _PDLB-LETTERS-LOWER

VARIABLE _PDLB-L      \ the record
VARIABLE _PDLB-F      \ the file
VARIABLE _PDLB-OK     \ false once memory is refused

: _PDLB-MSRC  ( -- msrc )  _PDLB-L @ _PDLB.MSRC @ ;

CREATE _PDLB-NEW _PDLB-RANGE ALLOT
CREATE _PDLB-NAME 8 ALLOT
VARIABLE _PDLB-PA   VARIABLE _PDLB-PU

\ A style's name, decoded: D, R, r, A or a.
: _PDLB-STYLE  ( va vu type -- style )
    PDF-T-NAME <> IF 2DROP _PDLB-NONE EXIT THEN
    _PDLB-NAME 8 PDF-NAME 1 <> IF _PDLB-NONE EXIT THEN
    _PDLB-NAME C@ CASE
        68  OF _PDLB-DECIMAL ENDOF
        82  OF _PDLB-ROMAN ENDOF
        114 OF _PDLB-ROMAN-LOWER ENDOF
        65  OF _PDLB-LETTERS ENDOF
        97  OF _PDLB-LETTERS-LOWER ENDOF
        >R _PDLB-NONE R>
    ENDCASE ;

\ A prefix's text, UTF-8, onto the prefixes' bytes, decoded in a buffer
\ of its size first.
: _PDLB-PREFIX  ( va vu type -- ok? )
    DUP PDF-T-STRING <> OVER PDF-T-HEX <> AND IF DROP 2DROP -1 EXIT THEN
    >R 2DUP R@ 0 0 PDF-STRING DUP _PDLB-PU !
    0= IF 2DROP R> DROP -1 EXIT THEN
    _PDLB-PU @ _PDLB-MSRC MSRC-ALLOC DUP _PDLB-PA ! 0= IF 2DROP R> DROP 0 EXIT THEN
    R> _PDLB-PA @ _PDLB-PU @ PDF-STRING DROP
    _PDLB-PA @ _PDLB-PU @ _PDLB-L @ _PDLB.TEXT _PDLB-MSRC PDF-TEXTSTR+
    _PDLB-PA @ _PDLB-PU @ _PDLB-MSRC MSRC-FREE ;

\ A pair of the tree: the range starting at page KEY.
: _PDLB-PAIR  ( key va vu type -- go? )
    _PDLB-NEW _PDLB-RANGE 0 FILL  1 _PDLB-NEW 16 + !
    _PDLB-L @ _PDLB.TEXT PDF-BUF.U @ _PDLB-NEW 24 + !
    _PDLB-F @ PDF-RESOLVE ?DUP IF                  ( key obj va vu type status )
        PDF-S-MEMORY = IF 0 _PDLB-OK ! THEN
        DROP 2DROP _PDLB-F @ PDF-OBJ-FREE DROP _PDLB-OK @ EXIT
    THEN
    PDF-T-DICT <> IF 2DROP _PDLB-F @ PDF-OBJ-FREE DROP -1 EXIT THEN
    3 ROLL 0 MAX _PDLB-NEW !                       ( obj da du )
    2DUP S" S" 2SWAP PDF-DICT@ _PDLB-STYLE _PDLB-NEW 8 + !
    2DUP S" St" 2SWAP PDF-DICT@ PDF-T-INT = IF PDF-INT 1 MAX _PDLB-NEW 16 + ! ELSE 2DROP THEN
    S" P" 2SWAP PDF-DICT@ _PDLB-PREFIX
    SWAP _PDLB-F @ PDF-OBJ-FREE
    0= IF 0 _PDLB-OK ! 0 EXIT THEN
    _PDLB-L @ _PDLB.TEXT PDF-BUF.U @ _PDLB-NEW 24 + @ - _PDLB-NEW 32 + !
    _PDLB-NEW _PDLB-RANGE _PDLB-L @ _PDLB.RANGES _PDLB-MSRC PDF-BUF-APPEND
    DUP 0= IF 0 _PDLB-OK ! THEN ;

\ PDF-LABELS-FREE ( labels -- )   Give back the ranges; the record is zeroed.
: PDF-LABELS-FREE  ( labels -- )
    DUP _PDLB.MSRC @ ?DUP IF
        >R DUP _PDLB.RANGES R@ PDF-BUF-FREE  DUP _PDLB.TEXT R> PDF-BUF-FREE
    THEN
    PDF-LABELS-SIZE 0 FILL ;

\ PDF-LABELS-READ ( file labels -- status )   Every range of the labels.
: PDF-LABELS-READ  ( file labels -- status )
    DUP _PDLB-L !  PDF-LABELS-SIZE 0 FILL  DUP _PDLB-F !
    PDF-FILE-MSRC _PDLB-L @ _PDLB.MSRC !  -1 _PDLB-OK !
    _PDLB-F @ PDF-FILE-LOCKED? IF PDF-S-LOCKED EXIT THEN
    S" Root" _PDLB-F @ PDF-TRAILER@ _PDLB-F @ PDF-RESOLVE ?DUP IF
        >R DROP 2DROP _PDLB-F @ PDF-OBJ-FREE R>
        PDF-S-MEMORY = IF PDF-S-MEMORY ELSE PDF-S-OK THEN EXIT
    THEN
    PDF-T-DICT <> IF 2DROP _PDLB-F @ PDF-OBJ-FREE PDF-S-OK EXIT THEN
    S" PageLabels" 2SWAP PDF-DICT@                         ( obj va vu type )
    >R >R >R ['] _PDLB-PAIR R> R> R>  _PDLB-F @ PDF-NUMS-EACH
    SWAP _PDLB-F @ PDF-OBJ-FREE
    _PDLB-OK @ 0= IF DROP PDF-S-MEMORY EXIT THEN ;

\ =====================================================================
\  A page's label
\ =====================================================================

VARIABLE _PDLB-B      \ the buffer the label goes onto
VARIABLE _PDLB-CASE   \ 32 for lower case
VARIABLE _PDLB-N      \ the number being written
VARIABLE _PDLB-V      \ a numeral's place in the table
VARIABLE _PDLB-R      \ the range found
CREATE _PDLB-CH 1 ALLOT

: _PDLB+  ( a u -- )
    _PDLB-B @ _PDLB-MSRC PDF-BUF-APPEND 0= IF 0 _PDLB-OK ! THEN ;
: _PDLB-C+  ( c -- )  _PDLB-CH C!  _PDLB-CH 1 _PDLB+ ;

CREATE _PDLB-ROMAN-V  1000 , 900 , 500 , 400 , 100 , 90 , 50 , 40 , 10 , 9 , 5 , 4 , 1 ,
\ The numerals of each value, two letters a value, a space for none.
: _PDLB-NUMERALS  ( -- a )  S" M CMD CDC XCL XLX IXV IVI " DROP ;

\ N in roman numerals, upper or lower case; the thousands repeat however
\ many there are.
: _PDLB-ROMAN+  ( n -- )
    _PDLB-N !  0 _PDLB-V !
    BEGIN _PDLB-V @ 13 < WHILE
        _PDLB-V @ CELLS _PDLB-ROMAN-V + @
        DUP _PDLB-N @ > IF DROP 1 _PDLB-V +! ELSE
            NEGATE _PDLB-N +!
            _PDLB-NUMERALS _PDLB-V @ 2* + DUP C@ _PDLB-CASE @ + _PDLB-C+
            1+ C@ DUP 32 = IF DROP ELSE _PDLB-CASE @ + _PDLB-C+ THEN
        THEN
    REPEAT ;

\ N in letters: A to Z, then AA to ZZ, and on.
: _PDLB-LETTERS+  ( n -- )
    1- 0 MAX 26 /MOD 1+                                  ( letter count )
    SWAP 65 + _PDLB-CASE @ + SWAP 0 ?DO DUP _PDLB-C+ LOOP DROP ;

\ The range page I lies in: the one with the greatest first page not past
\ it, or 0.
: _PDLB-FIND  ( i -- range | 0 )
    0 _PDLB-R !
    _PDLB-L @ _PDLB.RANGES PDF-BUF.U @ _PDLB-RANGE / 0 ?DO
        _PDLB-L @ _PDLB.RANGES PDF-BUF.A @ I _PDLB-RANGE * +
        DUP @ 2 PICK > IF DROP ELSE
            _PDLB-R @ IF DUP @ _PDLB-R @ @ < IF DROP ELSE _PDLB-R ! THEN
            ELSE _PDLB-R ! THEN
        THEN
    LOOP DROP _PDLB-R @ ;

\ PDF-LABEL ( i labels buf -- ok? )
\   Page I's label, UTF-8, onto BUF; false when memory refuses.
: PDF-LABEL  ( i labels buf -- ok? )
    _PDLB-B !  _PDLB-L !  -1 _PDLB-OK !
    DUP _PDLB-FIND ?DUP 0= IF 1+ NUM>STR _PDLB+ _PDLB-OK @ EXIT THEN   ( i range )
    DUP 24 + @ _PDLB-L @ _PDLB.TEXT PDF-BUF.A @ + OVER 32 + @ _PDLB+
    TUCK @ - OVER 16 + @ +                               ( range n )
    SWAP 8 + @ DUP _PDLB-ROMAN-LOWER = OVER _PDLB-LETTERS-LOWER = OR
    IF 32 ELSE 0 THEN _PDLB-CASE !                       ( n style )
    CASE
        _PDLB-DECIMAL       OF NUM>STR _PDLB+ ENDOF
        _PDLB-ROMAN         OF _PDLB-ROMAN+ ENDOF
        _PDLB-ROMAN-LOWER   OF _PDLB-ROMAN+ ENDOF
        _PDLB-LETTERS       OF _PDLB-LETTERS+ ENDOF
        _PDLB-LETTERS-LOWER OF _PDLB-LETTERS+ ENDOF
        NIP
    ENDCASE
    _PDLB-OK @ ;
