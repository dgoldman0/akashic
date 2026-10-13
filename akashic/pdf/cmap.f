\ =================================================================
\  cmap.f  —  a PDF CMap: a font's ToUnicode map, or its encoding
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-CMAP- (public), _PDCM- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f
\
\  Public API:
\   PDF-CMAP-SIZE    ( -- bytes )                    a map's record
\   PDF-CMAP-PARSE   ( a u msrc cmap -- status )     read a decoded CMap
\   PDF-CMAP-INIT    ( msrc cmap -- )                an empty map
\   PDF-CMAP-ADD     ( first last value cmap -- ok? )  one entry, by hand
\   PDF-CMAP-SEAL    ( cmap -- )                     ready to look up
\   PDF-CMAP-FREE    ( cmap -- )
\   PDF-CMAP-LOOKUP  ( code cmap -- a n delta true | false )
\   PDF-CMAP-BYTES   ( a u cmap -- n )               the next code's bytes
\
\  PDF-CMAP-PARSE reads a CMap's codespace ranges; its bfchar and bfrange
\  entries, which a ToUnicode map has (PDF 32000-1 section 9.10.3); and
\  its cidchar and cidrange entries, which an embedded encoding has
\  (9.7.5).  A ToUnicode destination is UTF-16BE, at most 512 bytes as
\  the section allows, surrogate pairs joined, so one code may stand for
\  several characters, as a ligature does.  An encoding's destination is
\  a CID.  A range whose destination is one string or CID counts its
\  last value up from the range's first code; a range whose destination
\  is an array takes one string a code.  Other sections are passed over.
\
\  PDF-CMAP-LOOKUP gives a code's values, characters or a CID, as N
\  32-bit values at A, of which the last is to be counted up by DELTA;
\  or false for a code the map does not hold.  N may be 0: the code
\  stands for nothing.  Of entries that hold a code, the one with the
\  greatest first code wins, and of those, the one read last.
\
\  PDF-CMAP-BYTES says how many bytes, 1 to 4, the next code of the U
\  bytes at A takes: the first length whose codespace ranges hold that
\  many bytes, byte by byte (9.7.6.2); else the shortest range's; else,
\  for a map with no ranges, the longest code its entries have.  It is
\  never more than U, nor less than 1.
\
\  A map built by hand, as a font's widths are, starts with PDF-CMAP-INIT,
\  takes entries of one value each with PDF-CMAP-ADD, and is sealed with
\  PDF-CMAP-SEAL before it is looked up; a lookup's DELTA is then the
\  code's place in its entry.
\
\  Entries that came out of order are sorted once the map is sealed, in
\  place.
\  Memory comes from the caller's memory source, sized by doubling.  An
\  entry takes 20 bytes, and a destination of more than one character
\  four bytes a character more.  PDF-CMAP-PARSE takes an empty record,
\  new or given back; a map it could not read whole still answers for
\  what it read.  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-cmap

REQUIRE lexer.f
REQUIRE filter.f

\ The record: three buffers, the entries, the characters of destinations
\ longer than one, and the codespace ranges; the longest code the entries
\ have; the memory source.
: _PDCM.E     ( m -- buf )      ;
: _PDCM.C     ( m -- buf )  24 + ;
: _PDCM.S     ( m -- buf )  48 + ;
: _PDCM.WIDE  ( m -- a )    72 + ;
: _PDCM.MSRC  ( m -- a )    80 + ;
88 CONSTANT PDF-CMAP-SIZE

\ An entry, 32-bit fields: first code, last code, how many values a code
\ has, the value itself when that is one or else the index of the first
\ in the characters, and the greatest last code of the entries up to it.
20 CONSTANT _PDCM-ENTRY
\ A codespace range, 32-bit fields: first code, last code, bytes.
12 CONSTANT _PDCM-RANGE

VARIABLE _PDCM-M    \ the map

: _PDCM-ENTRY@  ( i -- e )  _PDCM-ENTRY * _PDCM-M @ _PDCM.E PDF-BUF.A @ + ;
: _PDCM-ENTRIES  ( -- n )  _PDCM-M @ _PDCM.E PDF-BUF.U @ _PDCM-ENTRY / ;
: _PDCM-RANGE@  ( i -- r )  _PDCM-RANGE * _PDCM-M @ _PDCM.S PDF-BUF.A @ + ;
: _PDCM-RANGES  ( -- n )  _PDCM-M @ _PDCM.S PDF-BUF.U @ _PDCM-RANGE / ;

\ PDF-CMAP-FREE ( cmap -- )   Give back everything the map holds.
: PDF-CMAP-FREE  ( cmap -- )
    DUP _PDCM.MSRC @ ?DUP IF
        >R DUP _PDCM.E R@ PDF-BUF-FREE  DUP _PDCM.C R@ PDF-BUF-FREE
        DUP _PDCM.S R> PDF-BUF-FREE
    THEN
    PDF-CMAP-SIZE 0 FILL ;

: _PDCM-ADD  ( a u buf -- ok? )  _PDCM-M @ _PDCM.MSRC @ PDF-BUF-APPEND ;

CREATE _PDCM-SCR 512 ALLOT      \ a string's bytes
CREATE _PDCM-CHARS 1024 ALLOT   \ a destination's characters
VARIABLE _PDCM-N   VARIABLE _PDCM-HIGH

\ A code: a string's bytes, big-endian, and how many bytes it took.
: _PDCM-CODE  ( va vu type -- code bytes ok? )
    DUP PDF-T-HEX = OVER PDF-T-STRING = OR 0= IF DROP 2DROP 0 0 0 EXIT THEN
    _PDCM-SCR 16 PDF-STRING
    DUP 1 5 WITHIN 0= IF DROP 0 0 0 EXIT THEN
    0 OVER 0 ?DO 8 LSHIFT _PDCM-SCR I + C@ OR LOOP SWAP -1 ;

\ Whether a value can be a destination: a string, or a CID.
: _PDCM-DEST?  ( type -- flag )
    DUP PDF-T-HEX = OVER PDF-T-STRING = OR SWAP PDF-T-INT = OR ;

: _PDCM-CHAR+  ( c -- )  _PDCM-CHARS _PDCM-N @ 4 * + L!  1 _PDCM-N +! ;

\ A destination: a CID, or a string's characters, which go into the map
\ when there is more than one.  VALUE is the one value, or the index of
\ the first character.  A string of one byte is that one character.
: _PDCM-DEST  ( va vu type -- value n ok? )
    DUP PDF-T-INT = IF DROP PDF-INT 1 -1 EXIT THEN
    _PDCM-SCR 512 PDF-STRING 512 MIN
    DUP 1 = IF DROP _PDCM-SCR C@ 1 -1 EXIT THEN
    0 _PDCM-N !  0 _PDCM-HIGH !
    1 RSHIFT 0 ?DO
        _PDCM-SCR I 2* + DUP C@ 8 LSHIFT SWAP 1+ C@ OR
        DUP 0xD800 0xDC00 WITHIN IF _PDCM-HIGH ! ELSE
            DUP 0xDC00 0xE000 WITHIN _PDCM-HIGH @ 0<> AND IF
                0xDC00 - _PDCM-HIGH @ 0xD800 - 10 LSHIFT + 0x10000 +
            THEN
            0 _PDCM-HIGH !  _PDCM-CHAR+
        THEN
    LOOP
    _PDCM-N @ DUP 1 = IF DROP _PDCM-CHARS L@ 1 -1 EXIT THEN
    0= IF 0 0 -1 EXIT THEN
    _PDCM-M @ _PDCM.C PDF-BUF.U @ 2 RSHIFT
    _PDCM-CHARS _PDCM-N @ 4 * _PDCM-M @ _PDCM.C _PDCM-ADD 0= IF DROP 0 0 0 EXIT THEN
    _PDCM-N @ -1 ;

CREATE _PDCM-NEW _PDCM-ENTRY ALLOT

: _PDCM-NEW!  ( first last value n -- )
    _PDCM-NEW 8 + L!  _PDCM-NEW 12 + L!  _PDCM-NEW 4 + L!  _PDCM-NEW L! ;

\ Add the entry at _PDCM-NEW, with the order it was read in in its last
\ field until the map is sealed.
: _PDCM-APPEND  ( -- ok? )
    _PDCM-ENTRIES _PDCM-NEW 16 + L!
    _PDCM-NEW _PDCM-ENTRY _PDCM-M @ _PDCM.E _PDCM-ADD ;

\ Sorting the entries by first code, then by the order they were read in:
\ a heap sort, in place.
CREATE _PDCM-TMP _PDCM-ENTRY ALLOT

: _PDCM-KEY  ( i -- key )  _PDCM-ENTRY@ DUP L@ 32 LSHIFT SWAP 16 + L@ OR ;

: _PDCM-SWAP  ( i j -- )
    _PDCM-ENTRY@ SWAP _PDCM-ENTRY@
    DUP _PDCM-TMP _PDCM-ENTRY MOVE
    OVER SWAP _PDCM-ENTRY MOVE
    _PDCM-TMP SWAP _PDCM-ENTRY MOVE ;

\ Sift entry I down the heap of the first N entries.
: _PDCM-SIFT  ( i n -- )
    >R
    BEGIN DUP 2* 1+ DUP R@ < WHILE                      ( i child )
        DUP 1+ R@ < IF
            DUP 1+ _PDCM-KEY OVER _PDCM-KEY U> IF 1+ THEN
        THEN
        2DUP _PDCM-KEY SWAP _PDCM-KEY U> 0= IF 2DROP R> DROP EXIT THEN
        2DUP _PDCM-SWAP NIP
    REPEAT 2DROP R> DROP ;

: _PDCM-SORT  ( -- )
    _PDCM-ENTRIES DUP 2 < IF DROP EXIT THEN
    DUP 2/ BEGIN DUP 0> WHILE 1- 2DUP SWAP _PDCM-SIFT REPEAT DROP
    BEGIN DUP 1 > WHILE 1- 0 OVER _PDCM-SWAP 0 OVER _PDCM-SIFT REPEAT DROP ;

\ Give each entry the greatest last code of the entries up to it.
: _PDCM-REACH  ( -- )
    0 _PDCM-ENTRIES 0 ?DO
        I _PDCM-ENTRY@ DUP 4 + L@ ROT MAX TUCK SWAP 16 + L!
    LOOP DROP ;

: _PDCM-SORTED?  ( -- flag )
    _PDCM-ENTRIES 2 < IF -1 EXIT THEN
    _PDCM-ENTRIES 1 DO
        I 1- _PDCM-ENTRY@ L@ I _PDCM-ENTRY@ L@ > IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

\ PDF-CMAP-INIT ( msrc cmap -- )   An empty map drawing on MSRC.
: PDF-CMAP-INIT  ( msrc cmap -- )  DUP PDF-CMAP-SIZE 0 FILL _PDCM.MSRC ! ;

\ PDF-CMAP-ADD ( first last value cmap -- ok? )   An entry of one value.
: PDF-CMAP-ADD  ( first last value cmap -- ok? )
    _PDCM-M !  1 _PDCM-NEW!  _PDCM-APPEND ;

\ PDF-CMAP-SEAL ( cmap -- )   Sort the entries when they came out of
\ order, and note how far each reaches.
: PDF-CMAP-SEAL  ( cmap -- )
    _PDCM-M !  _PDCM-SORTED? 0= IF _PDCM-SORT THEN _PDCM-REACH ;

: _PDCM-WIDE!  ( bytes -- )  _PDCM-M @ _PDCM.WIDE @ MAX _PDCM-M @ _PDCM.WIDE ! ;

VARIABLE _PDCM-LO   VARIABLE _PDCM-HI   VARIABLE _PDCM-I

\ The value that ends a section: its "end..." keyword, or the input's end.
: _PDCM-END?  ( type -- flag )
    DUP PDF-T-KEYWORD = OVER PDF-T-END = OR SWAP PDF-T-BAD = OR ;

\ bfchar or cidchar pairs: a code and its destination, to the end.
: _PDCM-PAIRS  ( a u -- a' u' status )
    BEGIN
        PDF-OPERAND DUP _PDCM-END? IF DROP 2DROP PDF-S-OK EXIT THEN
        _PDCM-CODE >R _PDCM-WIDE! _PDCM-LO ! R>
        >R PDF-OPERAND DUP _PDCM-END? IF R> 2DROP 2DROP PDF-S-OK EXIT THEN
        R> OVER _PDCM-DEST? AND IF
            _PDCM-DEST 0= IF 2DROP PDF-S-MEMORY EXIT THEN
            >R >R _PDCM-LO @ DUP R> R> _PDCM-NEW!
            _PDCM-APPEND 0= IF PDF-S-MEMORY EXIT THEN
        ELSE DROP 2DROP THEN
    AGAIN ;

\ A bfrange's array of destinations, one a code from its first.
: _PDCM-ARRAY  ( aa au -- ok? )
    PDF-TOKEN DROP 2DROP  0 _PDCM-I !
    BEGIN _PDCM-I @ _PDCM-HI @ _PDCM-LO @ - > 0= WHILE
        PDF-OPERAND DUP _PDCM-DEST? 0= IF DROP 2DROP 2DROP -1 EXIT THEN
        _PDCM-DEST 0= IF 2DROP 2DROP 0 EXIT THEN
        >R >R _PDCM-LO @ _PDCM-I @ + DUP R> R> _PDCM-NEW!
        _PDCM-APPEND 0= IF 2DROP 0 EXIT THEN
        1 _PDCM-I +!
    REPEAT 2DROP -1 ;

\ bfrange or cidrange triples: a first and last code and a destination,
\ for bfrange perhaps an array of strings; to the end.
: _PDCM-TRIPLES  ( a u -- a' u' status )
    BEGIN
        PDF-OPERAND DUP _PDCM-END? IF DROP 2DROP PDF-S-OK EXIT THEN
        _PDCM-CODE >R _PDCM-WIDE! _PDCM-LO ! R>
        >R PDF-OPERAND DUP _PDCM-END? IF R> 2DROP 2DROP PDF-S-OK EXIT THEN
        _PDCM-CODE NIP R> AND >R _PDCM-HI ! R>                  ( a u ok? )
        _PDCM-HI @ _PDCM-LO @ < 0= AND
        >R PDF-OPERAND DUP _PDCM-END? IF R> 2DROP 2DROP PDF-S-OK EXIT THEN
        R> 0= IF DROP 2DROP ELSE
        DUP PDF-T-ARRAY = IF
            DROP _PDCM-ARRAY 0= IF PDF-S-MEMORY EXIT THEN
        ELSE DUP _PDCM-DEST? 0= IF DROP 2DROP ELSE
            _PDCM-DEST 0= IF 2DROP PDF-S-MEMORY EXIT THEN
            >R >R _PDCM-LO @ _PDCM-HI @ R> R> _PDCM-NEW!
            _PDCM-APPEND 0= IF PDF-S-MEMORY EXIT THEN
        THEN THEN THEN
    AGAIN ;

CREATE _PDCM-RNEW _PDCM-RANGE ALLOT

\ Codespace ranges: pairs of codes of the same length, to the end.
: _PDCM-SPACE  ( a u -- a' u' status )
    BEGIN
        PDF-OPERAND DUP _PDCM-END? IF DROP 2DROP PDF-S-OK EXIT THEN
        _PDCM-CODE >R _PDCM-RNEW 8 + L! _PDCM-RNEW L! R>
        >R PDF-OPERAND DUP _PDCM-END? IF R> 2DROP 2DROP PDF-S-OK EXIT THEN
        _PDCM-CODE >R _PDCM-RNEW 8 + L@ = R> AND R> AND IF
            _PDCM-RNEW 4 + L!
            _PDCM-RNEW _PDCM-RANGE _PDCM-M @ _PDCM.S _PDCM-ADD 0= IF
                PDF-S-MEMORY EXIT
            THEN
        ELSE DROP THEN
    AGAIN ;

\ The CMap's sections, read into the map.
: _PDCM-READ  ( a u -- status )
    BEGIN
        PDF-TOKEN                                       ( a u ta tu type )
        DUP PDF-T-END = IF DROP 2DROP 2DROP PDF-S-OK EXIT THEN
        PDF-T-KEYWORD = IF
            2DUP S" beginbfchar" COMPARE 0= >R
            2DUP S" begincidchar" COMPARE 0= R> OR IF 2DROP _PDCM-PAIRS ELSE
            2DUP S" beginbfrange" COMPARE 0= >R
            2DUP S" begincidrange" COMPARE 0= R> OR IF 2DROP _PDCM-TRIPLES ELSE
            S" begincodespacerange" COMPARE 0= IF _PDCM-SPACE ELSE PDF-S-OK THEN
            THEN THEN
            ?DUP IF NIP NIP EXIT THEN
        ELSE 2DROP THEN
    AGAIN ;

\ PDF-CMAP-PARSE ( a u msrc cmap -- status )   Read the decoded CMap at A.
: PDF-CMAP-PARSE  ( a u msrc cmap -- status )
    DUP >R PDF-CMAP-INIT  R@ _PDCM-M !
    _PDCM-READ  R> PDF-CMAP-SEAL ;

VARIABLE _PDCM-K   VARIABLE _PDCM-FOUND   VARIABLE _PDCM-EV

\ PDF-CMAP-LOOKUP ( code cmap -- a n delta true | false )
\   The code's values: N at A, 32 bits each, the last counted up by DELTA.
: PDF-CMAP-LOOKUP  ( code cmap -- a n delta true | false )
    _PDCM-M !  _PDCM-K !  -1 _PDCM-FOUND !
    0 _PDCM-LO !  _PDCM-ENTRIES 1- _PDCM-HI !
    BEGIN _PDCM-LO @ _PDCM-HI @ > 0= WHILE
        _PDCM-LO @ _PDCM-HI @ + 2/
        DUP _PDCM-ENTRY@ L@ _PDCM-K @ > IF
            1- _PDCM-HI !
        ELSE DUP _PDCM-FOUND ! 1+ _PDCM-LO ! THEN
    REPEAT
    \ Back from the last entry starting at or below the code, to one that
    \ holds it, while one still may.
    _PDCM-FOUND @
    BEGIN DUP 0< 0= WHILE
        DUP _PDCM-ENTRY@                                ( i e )
        DUP 16 + L@ _PDCM-K @ < IF 2DROP 0 EXIT THEN
        DUP 4 + L@ _PDCM-K @ < 0= IF
            NIP _PDCM-EV !
            _PDCM-EV @ 8 + L@ 1 = IF _PDCM-EV @ 12 +
            ELSE _PDCM-EV @ 12 + L@ 4 * _PDCM-M @ _PDCM.C PDF-BUF.A @ + THEN
            _PDCM-EV @ 8 + L@  _PDCM-K @ _PDCM-EV @ L@ -  -1 EXIT
        THEN
        DROP 1-
    REPEAT DROP 0 ;

VARIABLE _PDCM-R

\ Whether the K bytes at A lie in codespace range R, byte by byte.
: _PDCM-IN?  ( a k r -- flag )
    DUP 8 + L@ 2 PICK <> IF DROP 2DROP 0 EXIT THEN
    _PDCM-R !
    DUP 0 ?DO                                           ( a k )
        OVER I + C@  OVER 1- I - 8 *                    ( a k b sh )
        _PDCM-R @ L@ OVER RSHIFT 255 AND                ( a k b sh lo )
        SWAP _PDCM-R @ 4 + L@ SWAP RSHIFT 255 AND 1+    ( a k b lo hi+1 )
        WITHIN 0= IF 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP -1 ;

\ PDF-CMAP-BYTES ( a u cmap -- n )   How many bytes the next code takes.
: PDF-CMAP-BYTES  ( a u cmap -- n )
    _PDCM-M !
    _PDCM-RANGES 0= IF NIP _PDCM-M @ _PDCM.WIDE @ 1 MAX MIN 1 MAX EXIT THEN
    5 1 DO
        DUP I < IF LEAVE THEN
        _PDCM-RANGES 0 ?DO
            OVER J I _PDCM-RANGE@ _PDCM-IN? IF 2DROP J UNLOOP UNLOOP EXIT THEN
        LOOP
    LOOP
    NIP 4 _PDCM-RANGES 0 ?DO I _PDCM-RANGE@ 8 + L@ MIN LOOP MIN 1 MAX ;
