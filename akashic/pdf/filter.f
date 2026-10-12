\ =================================================================
\  filter.f  —  a PDF stream's bytes through its filters
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF- (public), _PDF- (private)
\  Depends on: pdf/lexer.f, utils/inflate.f, render/png.f,
\              utils/memory-source.f
\
\  Public API:
\   PDF-BUF-SIZE   ( -- bytes )      a buffer's record: address, room, used
\   PDF-BUF-FREE   ( buf msrc -- )   give a buffer's bytes back
\   PDF-BUF-GROW   ( need buf msrc -- ok? )   room for NEED bytes
\   PDF-BUF-APPEND ( a u buf msrc -- ok? )    add bytes at the end
\   PDF-DECODE     ( in-a in-u dict-a dict-u buf msrc -- status )
\
\  PDF-DECODE reads the stream dictionary's /Filter and /DecodeParms,
\  each a direct value, and decodes the IN-U bytes at IN-A through each
\  filter in turn into a buffer it takes from MSRC and grows by doubling.
\  The caller gives the buffer back with PDF-BUF-FREE.  A stream with no
\  filter is copied.
\
\  Filters: FlateDecode with the PNG predictors (10 to 15) and the TIFF
\  predictor (2) for eight-bit samples, ASCIIHexDecode, ASCII85Decode,
\  LZWDecode (with its predictors), and RunLengthDecode, by their full or
\  abbreviated names.  A picture's DCT, JPX, JBIG2 or CCITT data, and any
\  other filter, is PDF-S-UNSUPPORTED.
\
\  Statuses: PDF-S-OK; PDF-S-MEMORY when the source refuses, with nothing
\  kept; PDF-S-DAMAGED when the data is damaged, with the bytes decoded
\  before the damage in the buffer; PDF-S-UNSUPPORTED.
\ =================================================================

PROVIDED akashic-pdf-filter

REQUIRE lexer.f
REQUIRE ../utils/inflate.f
REQUIRE ../render/png.f
REQUIRE ../utils/memory-source.f

0 CONSTANT PDF-S-OK
1 CONSTANT PDF-S-MEMORY
2 CONSTANT PDF-S-DAMAGED
3 CONSTANT PDF-S-UNSUPPORTED
4 CONSTANT PDF-S-READ

\ =====================================================================
\  Buffers
\ =====================================================================

: PDF-BUF.A    ( buf -- a )      ;
: PDF-BUF.CAP  ( buf -- a )   8 + ;
: PDF-BUF.U    ( buf -- a )  16 + ;
24 CONSTANT PDF-BUF-SIZE

\ PDF-BUF-FREE ( buf msrc -- )   Give the buffer's bytes back.
: PDF-BUF-FREE  ( buf msrc -- )
    OVER PDF-BUF.A @ IF
        >R DUP PDF-BUF.A @ OVER PDF-BUF.CAP @ R> MSRC-FREE
    ELSE DROP THEN
    PDF-BUF-SIZE 0 FILL ;

\ Start BUF empty with room for CAP bytes: false when the source refuses.
: _PDF-BUF-NEW  ( cap buf msrc -- ok? )
    >R  0 OVER PDF-BUF.U !  SWAP 8 MAX
    2DUP SWAP PDF-BUF.CAP !  R> MSRC-ALLOC
    DUP ROT PDF-BUF.A !  0<> ;

\ PDF-BUF-GROW ( need buf msrc -- ok? )
\   Room in BUF for at least NEED bytes, its contents kept, doubling.
: PDF-BUF-GROW  ( need buf msrc -- ok? )
    >R OVER OVER PDF-BUF.CAP @ > 0= IF 2DROP R> DROP -1 EXIT THEN
    DUP PDF-BUF.CAP @ 8 MAX BEGIN DUP 3 PICK < WHILE 2* REPEAT
    ROT DROP DUP R@ MSRC-ALLOC                                 ( buf cap' new )
    DUP 0= IF 2DROP DROP R> DROP 0 EXIT THEN
    2 PICK PDF-BUF.A @ ?DUP IF
        OVER 4 PICK PDF-BUF.U @ MOVE
        2 PICK PDF-BUF.A @ 3 PICK PDF-BUF.CAP @ R@ MSRC-FREE
    THEN
    R> DROP ROT TUCK PDF-BUF.A ! PDF-BUF.CAP ! -1 ;

\ PDF-BUF-APPEND ( a u buf msrc -- ok? )   Add U bytes at A to BUF's end.
: PDF-BUF-APPEND  ( a u buf msrc -- ok? )
    >R 2DUP PDF-BUF.U @ + OVER R> PDF-BUF-GROW 0= IF DROP 2DROP 0 EXIT THEN
    DUP >R PDF-BUF.A @ R@ PDF-BUF.U @ + SWAP DUP R> PDF-BUF.U +! MOVE -1 ;

\ =====================================================================
\  One byte at a time, for the small filters
\ =====================================================================

VARIABLE _PDF-OB    \ the output buffer
VARIABLE _PDF-OM    \ its memory source
VARIABLE _PDF-OK    \ false once the source has refused
VARIABLE _PDF-BAD   \ true once the data is damaged

\ Put a byte in the output buffer, growing it when it is full.
: _PDF-PUT  ( c -- )
    _PDF-OK @ 0= IF DROP EXIT THEN
    _PDF-OB @ PDF-BUF.U @ _PDF-OB @ PDF-BUF.CAP @ = IF
        _PDF-OB @ PDF-BUF.U @ 1+ _PDF-OB @ _PDF-OM @ PDF-BUF-GROW 0= IF
            DROP 0 _PDF-OK ! EXIT
        THEN
    THEN
    _PDF-OB @ DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + C!
    1 _PDF-OB @ PDF-BUF.U +! ;

\ The status of a filter that put its bytes one at a time.
: _PDF-PUT-STATUS  ( -- status )
    _PDF-OK @ 0= IF PDF-S-MEMORY EXIT THEN
    _PDF-BAD @ IF PDF-S-DAMAGED ELSE PDF-S-OK THEN ;

: _PDF-WHITE?  ( c -- flag )
    DUP 32 = OVER 9 = OR OVER 10 = OR OVER 12 = OR OVER 13 = OR SWAP 0= OR ;

VARIABLE _PDF-HI    \ a hex pair's first digit, or -1

\ ASCIIHexDecode: pairs of hex digits, white space between, ">" ends.
: _PDF-AHX  ( a u -- status )
    -1 _PDF-HI !
    OVER + SWAP ?DO
        I C@ DUP 62 = IF DROP LEAVE THEN
        DUP _PDF-WHITE? IF DROP ELSE
            _PDL-HEXVAL DUP 0< IF DROP -1 _PDF-BAD ! LEAVE THEN
            _PDF-HI @ DUP 0< IF DROP _PDF-HI ! ELSE
                4 LSHIFT OR _PDF-PUT -1 _PDF-HI !
            THEN
        THEN
    LOOP
    _PDF-HI @ DUP 0< _PDF-BAD @ OR IF DROP ELSE 4 LSHIFT _PDF-PUT THEN
    _PDF-PUT-STATUS ;

VARIABLE _PDF-85N   \ digits in the group
VARIABLE _PDF-85V   \ the group's value so far

\ ASCII85Decode's last group of N digits, made whole with "u", as N-1
\ bytes.
: _PDF-85-FLUSH  ( -- )
    _PDF-85N @ 2 < IF EXIT THEN
    _PDF-85V @  5 _PDF-85N @ ?DO 85 * 84 + LOOP
    _PDF-85N @ 1- 0 ?DO
        DUP 24 I 8 * - RSHIFT 255 AND _PDF-PUT
    LOOP DROP ;

\ ASCII85Decode: five digits for four bytes, "z" for four zeros, "~>" ends.
: _PDF-A85  ( a u -- status )
    0 _PDF-85N !  0 _PDF-85V !
    OVER + SWAP ?DO
        I C@ DUP 126 = IF DROP LEAVE THEN
        DUP _PDF-WHITE? IF DROP ELSE
        DUP 122 = _PDF-85N @ 0= AND IF
            DROP 0 _PDF-PUT 0 _PDF-PUT 0 _PDF-PUT 0 _PDF-PUT
        ELSE
            DUP 33 118 WITHIN 0= IF DROP -1 _PDF-BAD ! LEAVE THEN
            33 - _PDF-85V @ 85 * + _PDF-85V !  1 _PDF-85N +!
            _PDF-85N @ 5 = IF
                _PDF-85V @ DUP 0xFFFFFFFF > IF DROP -1 _PDF-BAD ! LEAVE THEN
                DUP 24 RSHIFT _PDF-PUT  DUP 16 RSHIFT 255 AND _PDF-PUT
                DUP 8 RSHIFT 255 AND _PDF-PUT  255 AND _PDF-PUT
                0 _PDF-85N !  0 _PDF-85V !
            THEN
        THEN THEN
    LOOP
    _PDF-85-FLUSH _PDF-PUT-STATUS ;

\ RunLengthDecode: a length byte, then that many bytes plus one, or one
\ byte repeated 257 less the length; 128 ends.
: _PDF-RL  ( a u -- status )
    BEGIN DUP WHILE
        OVER C@ DUP 128 = IF DROP 2DROP _PDF-PUT-STATUS EXIT THEN
        >R 1 _PDL-ADV R>
        DUP 128 < IF
            1+ 2DUP < IF DROP 2DROP -1 _PDF-BAD ! _PDF-PUT-STATUS EXIT THEN
            >R OVER R@ OVER + SWAP ?DO I C@ _PDF-PUT LOOP R> _PDL-ADV
        ELSE
            OVER 0= IF DROP 2DROP -1 _PDF-BAD ! _PDF-PUT-STATUS EXIT THEN
            257 SWAP - 2 PICK C@ SWAP 0 ?DO DUP _PDF-PUT LOOP DROP 1 _PDL-ADV
        THEN
    REPEAT 2DROP _PDF-PUT-STATUS ;

\ =====================================================================
\  LZW
\ =====================================================================

\ The table: for each code its prefix code (16 bits), its last byte, its
\ first byte and its length (16 bits), six bytes a code.
4096 6 * CONSTANT _PDF-LZW-TABLE
VARIABLE _PDF-LT    \ the table
VARIABLE _PDF-LN    \ the next code
VARIABLE _PDF-LW    \ the code width
VARIABLE _PDF-LE    \ early change: 1 or 0
VARIABLE _PDF-LB    \ bit buffer
VARIABLE _PDF-LC    \ bits in it
VARIABLE _PDF-LP    \ the code before; -1 after a clear

: _PDF-LZW-ENTRY  ( code -- a )  6 * _PDF-LT @ + ;
: _PDF-LZW-LEN  ( code -- n )
    DUP 256 < IF DROP 1 EXIT THEN _PDF-LZW-ENTRY 4 + W@ ;
: _PDF-LZW-FIRST  ( code -- c )
    DUP 256 < IF EXIT THEN _PDF-LZW-ENTRY 3 + C@ ;

\ Put a code's bytes, walking its prefixes from the end.
: _PDF-LZW-EMIT  ( code -- )
    _PDF-OK @ 0= IF DROP EXIT THEN
    DUP _PDF-LZW-LEN _PDF-OB @ PDF-BUF.U @ + _PDF-OB @ _PDF-OM @ PDF-BUF-GROW 0= IF
        DROP 0 _PDF-OK ! EXIT
    THEN
    DUP _PDF-LZW-LEN _PDF-OB @ DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + OVER +
    ROT BEGIN DUP 256 < 0= WHILE                       ( len end code )
        SWAP 1- OVER _PDF-LZW-ENTRY 2 + C@ OVER C!  SWAP _PDF-LZW-ENTRY W@
    REPEAT
    SWAP 1- C!  _PDF-OB @ PDF-BUF.U +! ;

\ A new code: PREFIX's bytes and then C.
: _PDF-LZW-ADD  ( prefix c -- )
    _PDF-LN @ 4096 < 0= IF 2DROP EXIT THEN
    OVER _PDF-LN @ _PDF-LZW-ENTRY W!
    _PDF-LN @ _PDF-LZW-ENTRY 2 + C!
    DUP _PDF-LZW-FIRST _PDF-LN @ _PDF-LZW-ENTRY 3 + C!
    _PDF-LZW-LEN 1+ _PDF-LN @ _PDF-LZW-ENTRY 4 + W!
    1 _PDF-LN +!
    _PDF-LN @ _PDF-LE @ + DUP 512 = IF 10 _PDF-LW ! THEN
    DUP 1024 = IF 11 _PDF-LW ! THEN 2048 = IF 12 _PDF-LW ! THEN ;

: _PDF-LZW-CLEAR  ( -- )  258 _PDF-LN !  9 _PDF-LW !  -1 _PDF-LP ! ;

\ One code.
: _PDF-LZW-CODE  ( code -- )
    DUP 256 = IF DROP _PDF-LZW-CLEAR EXIT THEN
    _PDF-LP @ 0< IF
        DUP 256 < 0= IF DROP -1 _PDF-BAD ! EXIT THEN
        DUP _PDF-LZW-EMIT _PDF-LP ! EXIT
    THEN
    DUP _PDF-LN @ < IF
        DUP _PDF-LZW-EMIT
        _PDF-LP @ OVER _PDF-LZW-FIRST _PDF-LZW-ADD _PDF-LP ! EXIT
    THEN
    DUP _PDF-LN @ = IF
        _PDF-LP @ DUP _PDF-LZW-FIRST _PDF-LZW-ADD
        DUP _PDF-LZW-EMIT _PDF-LP ! EXIT
    THEN
    DROP -1 _PDF-BAD ! ;

\ LZWDecode: codes most significant bit first; 256 clears, 257 ends.
: _PDF-LZW  ( a u early -- status )
    _PDF-LE !  _PDF-LZW-CLEAR  0 _PDF-LB !  0 _PDF-LC !
    _PDF-LZW-TABLE _PDF-OM @ MSRC-ALLOC DUP _PDF-LT ! 0= IF
        2DROP PDF-S-MEMORY EXIT
    THEN
    OVER + SWAP ?DO
        _PDF-LB @ 8 LSHIFT I C@ OR _PDF-LB !  8 _PDF-LC +!
        _PDF-LC @ _PDF-LW @ < 0= IF
            _PDF-LC @ _PDF-LW @ - DUP _PDF-LC !
            _PDF-LB @ SWAP RSHIFT  1 _PDF-LW @ LSHIFT 1- AND
            _PDF-LB @ 1 _PDF-LC @ LSHIFT 1- AND _PDF-LB !
            DUP 257 = IF DROP LEAVE THEN
            _PDF-LZW-CODE
            _PDF-BAD @ IF LEAVE THEN
        THEN
    LOOP
    _PDF-LT @ _PDF-LZW-TABLE _PDF-OM @ MSRC-FREE
    _PDF-PUT-STATUS ;

\ =====================================================================
\  Flate
\ =====================================================================

VARIABLE _PDF-FR    \ the inflater's record
VARIABLE _PDF-FA    \ input left
VARIABLE _PDF-FU

: _PDF-FLATE-FREE  ( -- )  _PDF-FR @ INFL-SIZE _PDF-OM @ MSRC-FREE ;

\ FlateDecode: a zlib stream, inflated with the output as its window.
: _PDF-FLATE  ( a u -- status )
    _PDF-FU ! _PDF-FA !
    INFL-SIZE _PDF-OM @ MSRC-ALLOC DUP _PDF-FR ! 0= IF PDF-S-MEMORY EXIT THEN
    0 0 INFL-W-ZLIB _PDF-FR @ INFL-INIT
    BEGIN
        _PDF-FA @ _PDF-FU @
        _PDF-OB @ DUP PDF-BUF.A @ SWAP PDF-BUF.U @ +
        _PDF-OB @ DUP PDF-BUF.CAP @ SWAP PDF-BUF.U @ -
        _PDF-FR @ INFL-FEED                          ( used given status )
        SWAP _PDF-OB @ PDF-BUF.U +!
        SWAP DUP _PDF-FA +! NEGATE _PDF-FU +!        ( status )
        DUP INFL-S-FULL =
    WHILE
        DROP _PDF-OB @ PDF-BUF.CAP @ 2* _PDF-OB @ _PDF-OM @ PDF-BUF-GROW 0= IF
            _PDF-FLATE-FREE PDF-S-MEMORY EXIT
        THEN
        _PDF-OB @ PDF-BUF.A @ _PDF-FR @ INFL-MOVED
    REPEAT
    _PDF-FLATE-FREE
    INFL-S-DONE = IF PDF-S-OK ELSE PDF-S-DAMAGED THEN ;

\ =====================================================================
\  Predictors
\ =====================================================================

VARIABLE _PDF-PA  VARIABLE _PDF-PU  VARIABLE _PDF-PT   \ this filter's parameters

\ A parameter of the filter's dictionary, or DEFAULT.
: _PDF-PARM  ( name-a name-u default -- n )
    >R _PDF-PT @ PDF-T-DICT <> IF 2DROP R> EXIT THEN
    _PDF-PA @ _PDF-PU @ PDF-DICT@ PDF-T-INT = IF PDF-INT R> DROP ELSE 2DROP R> THEN ;

VARIABLE _PDF-PRED  VARIABLE _PDF-COLORS  VARIABLE _PDF-BPC  VARIABLE _PDF-COLUMNS
VARIABLE _PDF-RB    \ bytes a row
VARIABLE _PDF-BPP   \ bytes a pixel, at least one

: _PDF-ROW-SHAPE  ( -- )
    _PDF-COLORS @ _PDF-BPC @ * DUP 7 + 3 RSHIFT 1 MAX _PDF-BPP !
    _PDF-COLUMNS @ * 7 + 3 RSHIFT _PDF-RB ! ;

VARIABLE _PDF-SRC  VARIABLE _PDF-DST  VARIABLE _PDF-PREVROW  VARIABLE _PDF-ZERO

\ The PNG predictors: each row a filter byte and its filtered bytes,
\ undone in place, the filter bytes squeezed out.  A last row cut short
\ is dropped.
: _PDF-PNG-ROWS  ( -- status )
    _PDF-RB @ 0= IF PDF-S-DAMAGED EXIT THEN
    _PDF-RB @ _PDF-OM @ MSRC-ALLOC DUP _PDF-ZERO ! 0= IF PDF-S-MEMORY EXIT THEN
    _PDF-ZERO @ _PDF-RB @ 0 FILL
    _PDF-ZERO @ _PDF-PREVROW !  0 _PDF-SRC !  0 _PDF-DST !
    PDF-S-OK
    BEGIN
        DUP PDF-S-OK =
        _PDF-SRC @ 1+ _PDF-RB @ + _PDF-OB @ PDF-BUF.U @ > 0= AND
    WHILE
        _PDF-OB @ PDF-BUF.A @ _PDF-SRC @ + C@
        _PDF-OB @ PDF-BUF.A @ _PDF-SRC @ + 1+
        _PDF-OB @ PDF-BUF.A @ _PDF-DST @ +  _PDF-RB @ CMOVE
        _PDF-OB @ PDF-BUF.A @ _PDF-DST @ +                ( st filter row )
        DUP >R _PDF-PREVROW @ _PDF-RB @ _PDF-BPP @ PNG-UNFILTER
        R> _PDF-PREVROW !
        0= IF DROP PDF-S-DAMAGED THEN
        _PDF-RB @ _PDF-DST +!  _PDF-RB @ 1+ _PDF-SRC +!
    REPEAT
    _PDF-DST @ _PDF-OB @ PDF-BUF.U !
    _PDF-ZERO @ _PDF-RB @ _PDF-OM @ MSRC-FREE ;

\ The TIFF predictor for eight-bit samples: each byte adds the byte one
\ pixel before it in its row.
: _PDF-TIFF-ROWS  ( -- status )
    _PDF-BPC @ 8 <> IF PDF-S-UNSUPPORTED EXIT THEN
    _PDF-RB @ 0= IF PDF-S-DAMAGED EXIT THEN
    _PDF-OB @ PDF-BUF.A @ DUP _PDF-OB @ PDF-BUF.U @ + SWAP     ( end row )
    BEGIN 2DUP _PDF-RB @ + < 0= WHILE
        DUP _PDF-RB @ + OVER _PDF-BPP @ + ?DO
            I C@ I _PDF-BPP @ - C@ + I C!
        LOOP _PDF-RB @ +
    REPEAT 2DROP PDF-S-OK ;

\ Undo the predictor the filter's parameters name, if any.
: _PDF-PREDICT  ( -- status )
    S" Predictor" 1 _PDF-PARM _PDF-PRED !
    S" Colors" 1 _PDF-PARM _PDF-COLORS !
    S" BitsPerComponent" 8 _PDF-PARM _PDF-BPC !
    S" Columns" 1 _PDF-PARM _PDF-COLUMNS !
    _PDF-ROW-SHAPE
    _PDF-PRED @ 2 = IF _PDF-TIFF-ROWS EXIT THEN
    _PDF-PRED @ 10 16 WITHIN IF _PDF-PNG-ROWS EXIT THEN
    PDF-S-OK ;

\ =====================================================================
\  The filters in turn
\ =====================================================================

0 CONSTANT _PDF-F-NONE
1 CONSTANT _PDF-F-FLATE
2 CONSTANT _PDF-F-AHX
3 CONSTANT _PDF-F-A85
4 CONSTANT _PDF-F-LZW
5 CONSTANT _PDF-F-RL
6 CONSTANT _PDF-F-OTHER

: _PDF-NAMED?  ( na nu full-a full-u short-a short-u -- flag )
    2>R 2OVER 2SWAP PDF-NAME= -ROT 2R> PDF-NAME= OR ;

: _PDF-FILTER-KIND  ( na nu -- kind )
    2DUP S" FlateDecode" S" Fl" _PDF-NAMED? IF 2DROP _PDF-F-FLATE EXIT THEN
    2DUP S" ASCIIHexDecode" S" AHx" _PDF-NAMED? IF 2DROP _PDF-F-AHX EXIT THEN
    2DUP S" ASCII85Decode" S" A85" _PDF-NAMED? IF 2DROP _PDF-F-A85 EXIT THEN
    2DUP S" LZWDecode" S" LZW" _PDF-NAMED? IF 2DROP _PDF-F-LZW EXIT THEN
    S" RunLengthDecode" S" RL" _PDF-NAMED? IF _PDF-F-RL EXIT THEN
    _PDF-F-OTHER ;

\ The Ith filter of the /Filter value: one name or an array of names.
\ -1 past the last; none at all is one filter that copies, and any other
\ value one this module does not know.
: _PDF-FILTER@  ( i fa fu ft -- kind | -1 )
    DUP PDF-T-NAME = IF DROP ROT IF 2DROP -1 ELSE _PDF-FILTER-KIND THEN EXIT THEN
    DUP PDF-T-ARRAY = IF
        DROP PDF-ARRAY@ DUP PDF-T-END = IF DROP 2DROP -1 EXIT THEN
        PDF-T-NAME = IF _PDF-FILTER-KIND ELSE 2DROP _PDF-F-OTHER THEN EXIT
    THEN
    >R 2DROP IF R> DROP -1 EXIT THEN
    R> PDF-T-END = IF _PDF-F-NONE ELSE _PDF-F-OTHER THEN ;

\ The Ith filter's parameters: one dictionary or an array of them.
: _PDF-PARMS@  ( i pa pu pt -- pa' pu' pt' )
    DUP PDF-T-ARRAY = IF DROP PDF-ARRAY@ EXIT THEN
    >R ROT IF R> DROP 2DROP 0 0 PDF-T-END ELSE R> THEN ;

VARIABLE _PDF-DIA   VARIABLE _PDF-DIU     \ the dictionary
VARIABLE _PDF-IA    VARIABLE _PDF-IU      \ this filter's input
VARIABLE _PDF-STAGE                       \ the filter's index
CREATE _PDF-PREV PDF-BUF-SIZE ALLOT       \ the filter before's output

\ A dictionary entry by its full name, or in an inline picture by its
\ short one.
: _PDF-DICT2@  ( full-a full-u short-a short-u -- va vu type )
    2SWAP _PDF-DIA @ _PDF-DIU @ PDF-DICT@ DUP PDF-T-END = IF
        DROP 2DROP _PDF-DIA @ _PDF-DIU @ PDF-DICT@ EXIT
    THEN
    >R 2SWAP 2DROP R> ;

: _PDF-STAGE-FILTER  ( -- kind | -1 )
    _PDF-STAGE @ S" Filter" S" F" _PDF-DICT2@ _PDF-FILTER@ ;

: _PDF-STAGE-PARMS!  ( -- )
    _PDF-STAGE @ S" DecodeParms" S" DP" _PDF-DICT2@ _PDF-PARMS@
    _PDF-PT ! _PDF-PU ! _PDF-PA ! ;

\ One filter of KIND from the stage's input into the output buffer.
: _PDF-ONE  ( kind -- status )
    _PDF-IA @ _PDF-IU @ ROT CASE
        _PDF-F-FLATE OF _PDF-FLATE ENDOF
        _PDF-F-AHX OF _PDF-AHX ENDOF
        _PDF-F-A85 OF _PDF-A85 ENDOF
        _PDF-F-LZW OF S" EarlyChange" 1 _PDF-PARM _PDF-LZW ENDOF
        _PDF-F-RL OF _PDF-RL ENDOF
        _PDF-F-NONE OF
            DUP _PDF-OB @ _PDF-OM @ PDF-BUF-GROW 0= IF 2DROP PDF-S-MEMORY ELSE
                DUP >R _PDF-OB @ PDF-BUF.A @ SWAP MOVE
                R> _PDF-OB @ PDF-BUF.U ! PDF-S-OK
            THEN
        ENDOF
        >R 2DROP PDF-S-UNSUPPORTED R>
    ENDCASE ;

\ PDF-DECODE ( in-a in-u dict-a dict-u buf msrc -- status )
\   The stream's IN-U bytes at IN-A through the filters its dictionary
\   names, into BUF.
: PDF-DECODE  ( in-a in-u dict-a dict-u buf msrc -- status )
    _PDF-OM ! _PDF-OB ! _PDF-DIU ! _PDF-DIA ! _PDF-IU ! _PDF-IA !
    _PDF-PREV PDF-BUF-SIZE 0 FILL  0 _PDF-STAGE !
    BEGIN
        _PDF-STAGE-FILTER
        DUP -1 = _PDF-STAGE @ 0= AND IF DROP _PDF-F-NONE THEN
        DUP -1 = IF
            DROP _PDF-PREV _PDF-OB @ PDF-BUF-SIZE MOVE PDF-S-OK EXIT
        THEN
        _PDF-OB @ PDF-BUF-SIZE 0 FILL
        _PDF-IU @ 2* 64 MAX _PDF-OB @ _PDF-OM @ _PDF-BUF-NEW 0= IF
            DROP _PDF-PREV _PDF-OM @ PDF-BUF-FREE PDF-S-MEMORY EXIT
        THEN
        -1 _PDF-OK !  0 _PDF-BAD !  _PDF-STAGE-PARMS!
        DUP _PDF-ONE                                   ( kind status )
        OVER _PDF-F-FLATE = ROT _PDF-F-LZW = OR
        OVER DUP PDF-S-OK = SWAP PDF-S-DAMAGED = OR AND IF
            _PDF-PREDICT ?DUP IF NIP THEN
        THEN
        _PDF-PREV _PDF-OM @ PDF-BUF-FREE
        DUP PDF-S-OK <> IF
            DUP PDF-S-MEMORY = IF _PDF-OB @ _PDF-OM @ PDF-BUF-FREE THEN EXIT
        THEN DROP
        _PDF-OB @ _PDF-PREV PDF-BUF-SIZE MOVE
        _PDF-PREV PDF-BUF.A @ _PDF-IA !  _PDF-PREV PDF-BUF.U @ _PDF-IU !
        1 _PDF-STAGE +!
    AGAIN ;
