\ =================================================================
\  image.f  —  a PDF's pictures, as files a viewer shows
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-IMAGE- (public), _PDIM-,
\                               _PDRS- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f, utils/inflate.f,
\              render/png.f, render/qoi-rows.f, media/picture.f,
\              media/source.f
\
\  Public API:
\   PDF-IMAGE-SIZE     ( -- bytes )                  a picture's record
\   PDF-IMAGE-OPEN     ( num file image -- status )  picture XObject NUM
\   PDF-IMAGE-FREE     ( image -- )
\   PDF-IMAGE-WIDTH    ( image -- w )
\   PDF-IMAGE-HEIGHT   ( image -- h )
\   PDF-IMAGE-CODING   ( image -- coding )      its data's own coding
\   PDF-IMAGE-FORMAT   ( image -- format )      the file it becomes, or 0
\   PDF-IMAGE-STEP     ( budget image -- state )  make that file
\   PDF-IMAGE-STATE@   ( image -- state )
\   PDF-IMAGE-REASON@  ( image -- status )
\   PDF-IMAGE-SOURCE   ( image source -- )      the file, as a media source
\
\  A picture XObject (PDF 32000-1 section 8.9.5) becomes a file the
\  picture views show (media/picture.f): its JPEG data as a JPEG file,
\  PIC-F-JPEG, which a rich terminal decodes and the guest does not; or
\  its samples as a QOI file, PIC-F-QOI, which the guest writes.  Samples
\  are 1, 2, 4, 8 or 16 bits, the last by their high byte: gray, RGB,
\  CMYK made RGB plainly, or indexed over one of those; CalGray, CalRGB
\  and ICCBased spaces by their components.  /Decode maps each component.
\  A soft mask (/SMask) gives alpha, each picture pixel taking the mask's
\  nearest.  JPEG 2000, JBIG2 and CCITT data, stencil masks and other
\  spaces make no file: PDF-IMAGE-FORMAT is 0 and their facts are what a
\  view shows.
\
\  PDF-IMAGE-OPEN reads the picture's facts.  Its file is made a step at
\  a time, as media/picture.f decodes, so the caller stays responsive:
\  PDF-IMAGE-STEP makes about BUDGET pixels, at least a row, or for a
\  JPEG copies about BUDGET bytes, and gives PIC-ST-PENDING until
\  PIC-ST-READY, or PIC-ST-FAILED with PDF-IMAGE-REASON@ saying why.  A
\  JPEG under no other filter and stored as it is needs no steps: its
\  file is a span of the PDF's own media source.  One that is encrypted
\  is copied a piece at a time, decrypted.  Samples under no filter or
\  FlateDecode alone are read and inflated a piece at a time, each row's
\  predictor undone and the row encoded as it comes, so neither samples
\  nor pixels are held whole; under other filters they are decoded whole
\  on the first step.  PDF-IMAGE-SOURCE makes SOURCE, a MEDSRC-SPAN-SIZE
\  record, the ready file's media source, valid until PDF-IMAGE-FREE.
\
\  Memory comes from the file's memory source.  Pictures may take turns;
\  one call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-image

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f
REQUIRE ../utils/inflate.f
REQUIRE ../render/png.f
REQUIRE ../render/qoi-rows.f
REQUIRE ../media/picture.f
REQUIRE ../media/source.f

VARIABLE _PDIM-I    \ the picture's record
VARIABLE _PDIM-F    \ its file

: _PDIM-MSRC   ( -- msrc )  _PDIM-F @ PDF-FILE-MSRC ;
: _PDIM-FREE   ( obj -- )  _PDIM-F @ PDF-OBJ-FREE ;
: _PDIM-ALLOC  ( bytes -- a | 0 )  _PDIM-MSRC MSRC-ALLOC ;
: _PDIM-GIVE   ( a bytes -- )  OVER IF _PDIM-MSRC MSRC-FREE ELSE 2DROP THEN ;

\ An integer entry of the dictionary DA DU, through a reference, or
\ DEFAULT.
: _PDIM-INT@  ( key-a key-u da du default -- n )
    >R PDF-DICT@ _PDIM-F @ PDF-RESOLVE IF DROP 2DROP _PDIM-FREE R> EXIT THEN
    PDF-T-INT = IF PDF-INT R> DROP ELSE 2DROP R> THEN
    SWAP _PDIM-FREE ;

\ Whether the dictionary's entry is true.
: _PDIM-TRUE?  ( key-a key-u da du -- flag )
    PDF-DICT@ PDF-T-KEYWORD = IF S" true" COMPARE 0= ELSE 2DROP 0 THEN ;

\ =====================================================================
\  Rows of samples
\ =====================================================================

\ A source of a picture's rows: its stream read and inflated a piece at a
\ time, or decoded whole; each row's predictor undone.  The record: how
\ it reads; the stream read in pieces; the inflater, its window and an
\ input piece; the two rows, a filter byte before each one's samples,
\ the row being read and the row before; how much of it is read; a row's
\ bytes of samples, the predictor and its bytes a pixel; the data decoded
\ whole and where the next row starts in it; and the inflater's last
\ status.
0 CONSTANT _PDRS-STORED
1 CONSTANT _PDRS-INFLATED
2 CONSTANT _PDRS-WHOLE
4096 CONSTANT _PDRS-PIECE

: _PDRS.MODE   ( r -- a )        ;
: _PDRS.RAW    ( r -- raw )  8 + ;
8 PDF-RAW-SIZE + CONSTANT _PDRS-0
: _PDRS.INFL   ( r -- a )  _PDRS-0 + ;
: _PDRS.WIN    ( r -- a )  _PDRS-0 8 + + ;
: _PDRS.WINU   ( r -- a )  _PDRS-0 16 + + ;
: _PDRS.IN     ( r -- a )  _PDRS-0 24 + + ;
: _PDRS.INA    ( r -- a )  _PDRS-0 32 + + ;
: _PDRS.INU    ( r -- a )  _PDRS-0 40 + + ;
: _PDRS.ROWS   ( r -- a )  _PDRS-0 48 + + ;
: _PDRS.ROW    ( r -- a )  _PDRS-0 56 + + ;
: _PDRS.PREV   ( r -- a )  _PDRS-0 64 + + ;
: _PDRS.FILL   ( r -- a )  _PDRS-0 72 + + ;
: _PDRS.RB     ( r -- a )  _PDRS-0 80 + + ;
: _PDRS.PRED   ( r -- a )  _PDRS-0 88 + + ;
: _PDRS.BPP    ( r -- a )  _PDRS-0 96 + + ;
: _PDRS.WHOLE  ( r -- buf ) _PDRS-0 104 + + ;
: _PDRS.WPOS   ( r -- a )  _PDRS-0 128 + + ;
: _PDRS.LAST   ( r -- a )  _PDRS-0 136 + + ;
_PDRS-0 144 + CONSTANT _PDRS-SIZE

VARIABLE _PDRS-R                       \ the rows' record
VARIABLE _PDRS-O                       \ the stream's object
VARIABLE _PDRS-DA   VARIABLE _PDRS-DU  \ its dictionary
VARIABLE _PDRS-PA   VARIABLE _PDRS-PU  \ its predictor's parameters

: _RS  ( -- r )  _PDRS-R @ ;

\ Give back what the rows hold.
: _PDRS-FREE  ( r -- )
    DUP _PDRS.INFL @ INFL-SIZE _PDIM-GIVE
    DUP _PDRS.WIN @ OVER _PDRS.WINU @ _PDIM-GIVE
    DUP _PDRS.IN @ _PDRS-PIECE _PDIM-GIVE
    DUP _PDRS.ROWS @ OVER _PDRS.RB @ 1+ 2* _PDIM-GIVE
    DUP _PDRS.WHOLE _PDIM-MSRC PDF-BUF-FREE
    _PDRS-SIZE 0 FILL ;

\ Whether the stream has no filter.
: _PDRS-STORED?  ( -- flag )
    S" Filter" _PDRS-DA @ _PDRS-DU @ PDF-DICT@ NIP NIP PDF-T-END = ;

: _PDRS-PARM  ( key-a key-u default -- n )
    >R _PDRS-PU @ 0= IF 2DROP R> EXIT THEN
    _PDRS-PA @ _PDRS-PU @ PDF-DICT@ PDF-T-INT = IF PDF-INT R> DROP ELSE 2DROP R> THEN ;

\ The stream's predictor, which a piece at a time must undo row by row:
\ false when its rows are not the picture's rows.
: _PDRS-PREDICTS?  ( -- ok? )
    _PDRS-STORED? IF 1 _RS _PDRS.PRED ! -1 EXIT THEN
    0 _PDRS-PU !
    S" DecodeParms" _PDRS-DA @ _PDRS-DU @ PDF-DICT@
    DUP PDF-T-ARRAY = IF DROP 0 -ROT PDF-ARRAY@ THEN
    PDF-T-DICT = IF _PDRS-PU ! _PDRS-PA ! ELSE 2DROP THEN
    S" Predictor" 1 _PDRS-PARM
    DUP 2 = OVER 10 16 WITHIN OR 0= IF DROP 1 _RS _PDRS.PRED ! -1 EXIT THEN
    DUP _RS _PDRS.PRED !
    S" Colors" 1 _PDRS-PARM  S" BitsPerComponent" 8 _PDRS-PARM          ( pred colors bpc )
    2DUP * 7 + 3 RSHIFT 1 MAX _RS _PDRS.BPP !
    ROT 2 = OVER 8 <> AND IF 2DROP 0 EXIT THEN
    * S" Columns" 1 _PDRS-PARM * 7 + 3 RSHIFT _RS _PDRS.RB @ = ;

\ The next piece of the stream.
: _PDRS-READ  ( -- status )
    _RS _PDRS.IN @ _PDRS-PIECE _RS _PDRS.RAW PDF-RAW-READ
    SWAP _RS _PDRS.INU !  _RS _PDRS.IN @ _RS _PDRS.INA ! ;

\ The window a zlib stream's header asks for, or the largest.
: _PDRS-WINDOW  ( -- bytes )
    _RS _PDRS.INU @ IF
        _RS _PDRS.INA @ C@ DUP 15 AND 8 = OVER 4 RSHIFT 8 < AND IF
            4 RSHIFT 8 + 1 SWAP LSHIFT EXIT
        THEN DROP
    THEN 32768 ;

\ Read the stream a piece at a time.
: _PDRS-PIECES  ( -- status )
    _PDRS-O @ _PDIM-F @ _RS _PDRS.RAW PDF-RAW-START ?DUP IF EXIT THEN
    _RS _PDRS.RB @ 1+ 2* DUP _PDIM-ALLOC DUP _RS _PDRS.ROWS !
    0= IF DROP PDF-S-MEMORY EXIT THEN
    _RS _PDRS.ROWS @ SWAP 0 FILL
    _RS _PDRS.ROWS @ DUP _RS _PDRS.ROW !  _RS _PDRS.RB @ 1+ + _RS _PDRS.PREV !
    _PDRS-STORED? IF _PDRS-STORED _RS _PDRS.MODE !  PDF-S-OK EXIT THEN
    _PDRS-INFLATED _RS _PDRS.MODE !  INFL-S-MORE _RS _PDRS.LAST !
    _PDRS-PIECE _PDIM-ALLOC DUP _RS _PDRS.IN ! 0= IF PDF-S-MEMORY EXIT THEN
    _PDRS-READ ?DUP IF EXIT THEN
    _PDRS-WINDOW DUP _RS _PDRS.WINU !  _PDIM-ALLOC DUP _RS _PDRS.WIN !
    0= IF PDF-S-MEMORY EXIT THEN
    INFL-SIZE _PDIM-ALLOC DUP _RS _PDRS.INFL ! 0= IF PDF-S-MEMORY EXIT THEN
    _RS _PDRS.WIN @ _RS _PDRS.WINU @ INFL-W-ZLIB _RS _PDRS.INFL @ INFL-INIT
    PDF-S-OK ;

\ Decode the stream whole, its predictor undone with it.
: _PDRS-ALL  ( -- status )
    _PDRS-WHOLE _RS _PDRS.MODE !  1 _RS _PDRS.PRED !
    _PDRS-O @ _RS _PDRS.WHOLE _PDIM-F @ PDF-STREAM-IMAGE
    SWAP IF DROP PDF-S-UNSUPPORTED THEN ;

\ Start reading the rows of the picture stream OBJ, each RB bytes of
\ samples.  OBJ may be given back once they start.
: _PDRS-OPEN  ( obj rb r -- status )
    DUP _PDRS-SIZE 0 FILL  DUP _PDRS-R !  _PDRS.RB !  DUP _PDRS-O !
    PDF-OBJ-VALUE DROP _PDRS-DU ! _PDRS-DA !
    _PDRS-DA @ _PDRS-DU @ PDF-PICTURE-FILTERS
    SWAP IF DROP PDF-S-UNSUPPORTED EXIT THEN
    IF _PDRS-PREDICTS? IF _PDRS-PIECES EXIT THEN THEN
    _PDRS-ALL ;

\ The TIFF predictor for eight-bit samples: each byte adds the byte one
\ pixel before it.
: _PDRS-TIFF  ( -- )
    _RS _PDRS.ROW @ 1+  _RS _PDRS.BPP @
    _RS _PDRS.RB @ OVER ?DO
        OVER I + C@  2 PICK I + 2 PICK - C@ + 255 AND  2 PICK I + C!
    LOOP 2DROP ;

\ The row read, its predictor undone: its samples.
: _PDRS-PREDICT  ( -- a status )
    _RS _PDRS.PRED @ DUP 10 < IF
        2 = IF _PDRS-TIFF THEN  _RS _PDRS.ROW @ 1+ PDF-S-OK EXIT
    THEN DROP
    _RS _PDRS.ROW @ C@  _RS _PDRS.ROW @ 1+  _RS _PDRS.PREV @ 1+
    _RS _PDRS.RB @  _RS _PDRS.BPP @  PNG-UNFILTER 0= IF 0 PDF-S-DAMAGED EXIT THEN
    _RS _PDRS.ROW @  _RS _PDRS.PREV @ _RS _PDRS.ROW !  DUP _RS _PDRS.PREV !
    1+ PDF-S-OK ;

\ The next row of a stream with no filter.
: _PDRS-FROM-RAW  ( -- a status )
    0 _RS _PDRS.FILL !
    BEGIN _RS _PDRS.FILL @ _RS _PDRS.RB @ < WHILE
        _RS _PDRS.ROW @ 1+ _RS _PDRS.FILL @ +  _RS _PDRS.RB @ _RS _PDRS.FILL @ -
        _RS _PDRS.RAW PDF-RAW-READ
        ?DUP IF NIP 0 SWAP EXIT THEN
        DUP 0= IF DROP 0 PDF-S-DAMAGED EXIT THEN
        _RS _PDRS.FILL +!
    REPEAT
    _RS _PDRS.ROW @ 1+ PDF-S-OK ;

\ The next row inflated: the predictor's filter byte, when it has one,
\ then the samples.
: _PDRS-FROM-INFLATE  ( -- a status )
    _RS _PDRS.PRED @ 10 < IF 1 ELSE 0 THEN _RS _PDRS.FILL !
    BEGIN _RS _PDRS.FILL @ _RS _PDRS.RB @ 1+ < WHILE
        _RS _PDRS.LAST @ INFL-S-MORE = _RS _PDRS.INU @ 0= AND IF
            _PDRS-READ ?DUP IF 0 SWAP EXIT THEN
            _RS _PDRS.INU @ 0= IF 0 PDF-S-DAMAGED EXIT THEN
        THEN
        _RS _PDRS.INA @ _RS _PDRS.INU @
        _RS _PDRS.ROW @ _RS _PDRS.FILL @ +  _RS _PDRS.RB @ 1+ _RS _PDRS.FILL @ -
        _RS _PDRS.INFL @ INFL-FEED                               ( used given status )
        DUP _RS _PDRS.LAST !
        SWAP _RS _PDRS.FILL +!
        SWAP DUP _RS _PDRS.INA +!  NEGATE _RS _PDRS.INU +!
        DUP INFL-S-BAD = IF DROP 0 PDF-S-DAMAGED EXIT THEN
        INFL-S-DONE = _RS _PDRS.FILL @ _RS _PDRS.RB @ 1+ < AND IF 0 PDF-S-DAMAGED EXIT THEN
    REPEAT
    _PDRS-PREDICT ;

\ The next row of data decoded whole.
: _PDRS-FROM-WHOLE  ( -- a status )
    _RS _PDRS.WPOS @ _RS _PDRS.RB @ +  _RS _PDRS.WHOLE PDF-BUF.U @ > IF 0 PDF-S-DAMAGED EXIT THEN
    _RS _PDRS.WHOLE PDF-BUF.A @ _RS _PDRS.WPOS @ +
    _RS _PDRS.RB @ _RS _PDRS.WPOS +!  PDF-S-OK ;

\ The next row's samples, valid until the next row but one: their
\ address, or 0 and why there is none.
: _PDRS-NEXT  ( r -- a status )
    DUP _PDRS-R !  _PDRS.MODE @
    DUP _PDRS-WHOLE = IF DROP _PDRS-FROM-WHOLE EXIT THEN
    _PDRS-STORED = IF _PDRS-FROM-RAW EXIT THEN
    _PDRS-FROM-INFLATE ;

\ =====================================================================
\  The picture's record
\ =====================================================================

\ Its file and object; its size, coding, the file it becomes, the
\ state of making it and why it failed; how it is made and whether that
\ has started; the file made, or the span of the PDF that is the file;
\ its space, components, bits a sample and palette; the rows made, a row
\ of pixels and the encoder; its soft mask's object, size, bits a sample,
\ rows read and row; each component's table, the mask's table; and the
\ picture's and the mask's rows.
: _PDIM.FILE    ( i -- a )        ;
: _PDIM.NUM     ( i -- a )    8 + ;
: _PDIM.W       ( i -- a )   16 + ;
: _PDIM.H       ( i -- a )   24 + ;
: _PDIM.CODING  ( i -- a )   32 + ;
: _PDIM.FORMAT  ( i -- a )   40 + ;
: _PDIM.STATE   ( i -- a )   48 + ;
: _PDIM.REASON  ( i -- a )   56 + ;
: _PDIM.PATH    ( i -- a )   64 + ;
: _PDIM.STARTED ( i -- a )   72 + ;
: _PDIM.OUT     ( i -- buf ) 80 + ;
: _PDIM.SPAN    ( i -- a )  104 + ;
: _PDIM.SPACE   ( i -- a )  120 + ;
: _PDIM.NC      ( i -- a )  128 + ;
: _PDIM.BPC     ( i -- a )  136 + ;
: _PDIM.PAL     ( i -- a )  144 + ;
: _PDIM.PALN    ( i -- a )  152 + ;
: _PDIM.ROWS    ( i -- a )  160 + ;
: _PDIM.PIX     ( i -- a )  168 + ;
: _PDIM.ENC     ( i -- a )  176 + ;
: _PDIM.MASK?   ( i -- a )  184 + ;
: _PDIM.MNUM    ( i -- a )  192 + ;
: _PDIM.MW      ( i -- a )  200 + ;
: _PDIM.MH      ( i -- a )  208 + ;
: _PDIM.MBPC    ( i -- a )  216 + ;
: _PDIM.MROWS   ( i -- a )  224 + ;
: _PDIM.MROW    ( i -- a )  232 + ;
: _PDIM.LUT     ( i -- a )  240 + ;
: _PDIM.MLUT    ( i -- a ) 1264 + ;
: _PDIM.RS      ( i -- r ) 1520 + ;
: _PDIM.MRS     ( i -- r ) 1520 _PDRS-SIZE + + ;
1520 _PDRS-SIZE 2* + CONSTANT PDF-IMAGE-SIZE

\ How the file is made.
0 CONSTANT _PDIM-P-NONE     \ it is not
1 CONSTANT _PDIM-P-SPAN     \ a span of the PDF
2 CONSTANT _PDIM-P-COPY     \ a JPEG copied a piece at a time
3 CONSTANT _PDIM-P-WHOLE    \ a JPEG decoded whole from its filters
4 CONSTANT _PDIM-P-ROWS     \ samples encoded row by row

\ Spaces.
0 CONSTANT _PDIM-GRAY
1 CONSTANT _PDIM-RGB
2 CONSTANT _PDIM-CMYK
3 CONSTANT _PDIM-INDEXED

: _I  ( -- i )  _PDIM-I @ ;

: PDF-IMAGE-WIDTH    ( image -- w )  _PDIM.W @ ;
: PDF-IMAGE-HEIGHT   ( image -- h )  _PDIM.H @ ;
: PDF-IMAGE-CODING   ( image -- coding )  _PDIM.CODING @ ;
: PDF-IMAGE-FORMAT   ( image -- format )  _PDIM.FORMAT @ ;
: PDF-IMAGE-STATE@   ( image -- state )  _PDIM.STATE @ ;
: PDF-IMAGE-REASON@  ( image -- status )  _PDIM.REASON @ ;

\ A space's components.
: _PDIM-NC  ( kind -- n )
    DUP _PDIM-RGB = IF DROP 3 EXIT THEN  _PDIM-CMYK = IF 4 ELSE 1 THEN ;

\ =====================================================================
\  Spaces, palettes and tables
\ =====================================================================

\ A device space by its name, or -1.
: _PDIM-NAMED  ( va vu -- kind )
    2DUP S" DeviceGray" PDF-NAME= IF 2DROP _PDIM-GRAY EXIT THEN
    2DUP S" DeviceRGB" PDF-NAME= IF 2DROP _PDIM-RGB EXIT THEN
    2DUP S" DeviceCMYK" PDF-NAME= IF 2DROP _PDIM-CMYK EXIT THEN
    2DUP S" G" PDF-NAME= IF 2DROP _PDIM-GRAY EXIT THEN
    2DUP S" RGB" PDF-NAME= IF 2DROP _PDIM-RGB EXIT THEN
    S" CMYK" PDF-NAME= IF _PDIM-CMYK ELSE -1 THEN ;

\ A space that is not indexed, through references: its kind, or -1.
: _PDIM-BASE  ( va vu type -- kind )
    _PDIM-F @ PDF-RESOLVE IF DROP 2DROP _PDIM-FREE -1 EXIT THEN
    DUP PDF-T-NAME = IF DROP _PDIM-NAMED SWAP _PDIM-FREE EXIT THEN
    PDF-T-ARRAY <> IF 2DROP _PDIM-FREE -1 EXIT THEN                     ( obj aa au )
    2DUP 0 -ROT PDF-ARRAY@ PDF-T-NAME <> IF 2DROP 2DROP _PDIM-FREE -1 EXIT THEN
    2DUP S" CalGray" PDF-NAME= IF 2DROP 2DROP _PDIM-FREE _PDIM-GRAY EXIT THEN
    2DUP S" CalRGB" PDF-NAME= IF 2DROP 2DROP _PDIM-FREE _PDIM-RGB EXIT THEN
    S" ICCBased" PDF-NAME= 0= IF 2DROP _PDIM-FREE -1 EXIT THEN
    1 -ROT PDF-ARRAY@ _PDIM-F @ PDF-RESOLVE IF DROP 2DROP _PDIM-FREE _PDIM-FREE -1 EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDIM-FREE _PDIM-FREE -1 EXIT THEN
    S" N" 2SWAP 0 _PDIM-INT@  -ROT _PDIM-FREE _PDIM-FREE
    CASE 1 OF _PDIM-GRAY ENDOF 3 OF _PDIM-RGB ENDOF 4 OF _PDIM-CMYK ENDOF -1 SWAP ENDCASE ;

VARIABLE _PDIM-PBASE   VARIABLE _PDIM-HIVAL
CREATE _PDIM-LOOK-S PDF-BUF-SIZE 7 + ALLOT
: _PDIM-LOOK  ( -- buf )  _PDIM-LOOK-S 7 + -8 AND ;   \ an indexed space's lookup
VARIABLE _PDIM-LT   VARIABLE _PDIM-LN

\ Component C of palette entry I in the lookup, or 0 past its end.
: _PDIM-LOOK@  ( i c -- v )
    SWAP _PDIM-PBASE @ _PDIM-NC * +
    DUP _PDIM-LOOK PDF-BUF.U @ < IF _PDIM-LOOK PDF-BUF.A @ + C@ ELSE DROP 0 THEN ;

\ Ink V under black K, as red, green or blue.
: _PDIM-INK  ( v k -- out )  + 255 MIN 255 SWAP - ;
: _PDIM-CMYK>RGB  ( c m y k -- r g b )
    >R  ROT R@ _PDIM-INK  ROT R@ _PDIM-INK  ROT R> _PDIM-INK ;

\ Palette entry I, as RGB.
: _PDIM-ENTRY  ( i -- )
    DUP 3 * _I _PDIM.PAL @ + >R
    _PDIM-PBASE @ DUP _PDIM-GRAY = IF
        DROP 0 _PDIM-LOOK@ DUP DUP
    ELSE _PDIM-RGB = IF
        DUP 0 _PDIM-LOOK@ OVER 1 _PDIM-LOOK@ ROT 2 _PDIM-LOOK@
    ELSE
        DUP 0 _PDIM-LOOK@ OVER 1 _PDIM-LOOK@ 2 PICK 2 _PDIM-LOOK@ 3 PICK 3 _PDIM-LOOK@
        _PDIM-CMYK>RGB  >R >R >R DROP R> R> R>
    THEN THEN
    R@ 2 + C!  R@ 1+ C!  R> C! ;

\ An indexed space's palette, from its lookup VA VU: a string, or a
\ stream.
: _PDIM-PALETTE  ( va vu type -- status )
    _PDIM-LOOK PDF-BUF-SIZE 0 FILL
    _PDIM-F @ PDF-RESOLVE ?DUP IF >R DROP 2DROP _PDIM-FREE R> EXIT THEN
    DUP PDF-T-STRING = OVER PDF-T-HEX = OR IF
        _PDIM-LT !  2DUP _PDIM-LT @ 0 0 PDF-STRING _PDIM-LN !
        _PDIM-LN @ _PDIM-LOOK _PDIM-MSRC PDF-BUF-GROW 0= IF 2DROP _PDIM-FREE PDF-S-MEMORY EXIT THEN
        _PDIM-LT @ _PDIM-LOOK PDF-BUF.A @ _PDIM-LN @ PDF-STRING _PDIM-LOOK PDF-BUF.U !
        _PDIM-FREE
    ELSE
        DROP 2DROP
        DUP 0= IF DROP PDF-S-DAMAGED EXIT THEN
        DUP PDF-OBJ-STREAM? 0= IF _PDIM-FREE PDF-S-DAMAGED EXIT THEN
        DUP _PDIM-LOOK _PDIM-F @ PDF-STREAM SWAP _PDIM-FREE
        ?DUP IF _PDIM-LOOK _PDIM-MSRC PDF-BUF-FREE EXIT THEN
    THEN
    _PDIM-HIVAL @ 1+ DUP _I _PDIM.PALN !  3 * _PDIM-ALLOC DUP _I _PDIM.PAL !
    0= IF 0 _I _PDIM.PALN !  _PDIM-LOOK _PDIM-MSRC PDF-BUF-FREE PDF-S-MEMORY EXIT THEN
    _I _PDIM.PALN @ 0 ?DO I _PDIM-ENTRY LOOP
    _PDIM-LOOK _PDIM-MSRC PDF-BUF-FREE PDF-S-OK ;

\ Whether the space array AA AU is indexed.
: _PDIM-INDEXED?  ( aa au -- flag )
    0 -ROT PDF-ARRAY@ PDF-T-NAME = IF
        2DUP S" Indexed" PDF-NAME= >R S" I" PDF-NAME= R> OR
    ELSE 2DROP 0 THEN ;

\ An indexed space [/Indexed base hival lookup] in OBJ, given back.
: _PDIM-INDEXED-SPACE  ( obj aa au -- kind status )
    2DUP 1 -ROT PDF-ARRAY@ _PDIM-BASE DUP _PDIM-PBASE !
    0< IF 2DROP _PDIM-FREE -1 PDF-S-OK EXIT THEN
    2DUP 2 -ROT PDF-ARRAY@ PDF-T-INT = IF PDF-INT ELSE 2DROP -1 THEN
    DUP 0 256 WITHIN 0= IF DROP 2DROP _PDIM-FREE -1 PDF-S-OK EXIT THEN
    _PDIM-HIVAL !
    3 -ROT PDF-ARRAY@ _PDIM-PALETTE  SWAP _PDIM-FREE
    ?DUP IF -1 SWAP EXIT THEN
    _PDIM-INDEXED PDF-S-OK ;

\ The picture's space, through references: its kind, or -1; an indexed
\ space's palette read.
: _PDIM-SPACE  ( va vu type -- kind status )
    _PDIM-F @ PDF-RESOLVE IF DROP 2DROP _PDIM-FREE -1 PDF-S-OK EXIT THEN
    DUP PDF-T-ARRAY = IF
        DROP 2DUP _PDIM-INDEXED? IF _PDIM-INDEXED-SPACE EXIT THEN
        PDF-T-ARRAY
    THEN
    _PDIM-BASE  SWAP _PDIM-FREE  PDF-S-OK ;

VARIABLE _PDIM-TAB   VARIABLE _PDIM-DMIN   VARIABLE _PDIM-DMAX   VARIABLE _PDIM-MAX

\ A component's table: each raw sample of BPC bits, a sixteen-bit one by
\ its high byte, to eight bits through the /Decode pair DMIN DMAX, 16.16.
: _PDIM-TABLE  ( dmin dmax bpc table -- )
    _PDIM-TAB !
    DUP 16 = IF DROP 255 ELSE 1 SWAP LSHIFT 1- THEN _PDIM-MAX !
    _PDIM-DMAX ! _PDIM-DMIN !
    _PDIM-MAX @ 1+ 0 DO
        _PDIM-DMIN @ _PDIM-MAX @ *  I _PDIM-DMAX @ _PDIM-DMIN @ - * +
        255 *  _PDIM-MAX @ 32768 * +  _PDIM-MAX @ 65536 * /
        0 MAX 255 MIN  _PDIM-TAB @ I + C!
    LOOP ;

\ The /Decode pair of component C in the dictionary DA DU, or 0 1.
: _PDIM-DECODE  ( c da du -- dmin dmax )
    S" Decode" 2SWAP PDF-DICT@ PDF-T-ARRAY <> IF 2DROP DROP 0 65536 EXIT THEN    ( c aa au )
    ROT 2* >R
    2DUP R@ -ROT PDF-ARRAY@ DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF PDF-FIXED ELSE 2DROP 0 THEN
    -ROT R> 1+ -ROT PDF-ARRAY@ DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF PDF-FIXED ELSE 2DROP 65536 THEN ;

VARIABLE _PDIM-DA   VARIABLE _PDIM-DU   \ the picture's dictionary
VARIABLE _PDIM-O                        \ its object

\ The soft mask, when one can give alpha: a gray picture of samples.
: _PDIM-MASK  ( -- status )
    S" SMask" _PDIM-DA @ _PDIM-DU @ PDF-DICT@ PDF-T-REF <> IF 2DROP PDF-S-OK EXIT THEN
    PDF-REF@ DROP DUP _I _PDIM.MNUM !  _PDIM-F @ PDF-GET ?DUP IF
        SWAP _PDIM-FREE DUP PDF-S-MEMORY = IF EXIT THEN DROP PDF-S-OK EXIT
    THEN
    DUP PDF-OBJ-STREAM? 0= IF _PDIM-FREE PDF-S-OK EXIT THEN
    DUP PDF-OBJ-VALUE DROP                                               ( mobj da du )
    2DUP PDF-PICTURE-FILTERS DROP IF 2DROP _PDIM-FREE PDF-S-OK EXIT THEN
    S" Width" 2OVER 0 _PDIM-INT@ _I _PDIM.MW !
    S" Height" 2OVER 0 _PDIM-INT@ _I _PDIM.MH !
    S" BitsPerComponent" 2OVER 8 _PDIM-INT@ _I _PDIM.MBPC !
    _I _PDIM.MW @ 1 < _I _PDIM.MH @ 1 < OR
    _I _PDIM.MBPC @ DUP 1 = OVER 2 = OR OVER 4 = OR OVER 8 = OR SWAP 16 = OR 0= OR IF
        2DROP _PDIM-FREE PDF-S-OK EXIT
    THEN
    0 -ROT _PDIM-DECODE _I _PDIM.MBPC @ _I _PDIM.MLUT _PDIM-TABLE
    _PDIM-FREE  -1 _I _PDIM.MASK? !  PDF-S-OK ;

\ A JPEG under its own filter alone: a span of the PDF when stored as it
\ is, else copied a piece at a time, decrypted.
: _PDIM-JPEG-PIECES  ( -- status )
    _PDIM-O @ _PDIM-F @ _I _PDIM.RS _PDRS.RAW PDF-RAW-START ?DUP IF EXIT THEN
    _I _PDIM.RS _PDRS.RAW PDF-RAW-SPAN                     ( offset u stored? )
    -ROT _I _PDIM.SPAN 8 + !  _I _PDIM.SPAN !
    IF _PDIM-P-SPAN _I _PDIM.PATH !  PIC-ST-READY ELSE _PDIM-P-COPY _I _PDIM.PATH !  PIC-ST-PENDING THEN
    _I _PDIM.STATE !  PDF-S-OK ;

\ The facts of a picture of samples, its file QOI when it can be made.
: _PDIM-SAMPLES  ( -- status )
    S" ImageMask" _PDIM-DA @ _PDIM-DU @ _PDIM-TRUE? IF PDF-S-OK EXIT THEN
    S" BitsPerComponent" _PDIM-DA @ _PDIM-DU @ 8 _PDIM-INT@ DUP _I _PDIM.BPC !
    DUP 1 = OVER 2 = OR OVER 4 = OR OVER 8 = OR SWAP 16 = OR 0= IF PDF-S-OK EXIT THEN
    S" ColorSpace" _PDIM-DA @ _PDIM-DU @ PDF-DICT@ _PDIM-SPACE ?DUP IF NIP EXIT THEN
    DUP 0< IF DROP PDF-S-OK EXIT THEN
    DUP _I _PDIM.SPACE !
    DUP _PDIM-INDEXED = IF DROP 1 ELSE _PDIM-NC THEN _I _PDIM.NC !
    _I _PDIM.SPACE @ _PDIM-INDEXED = _I _PDIM.BPC @ 16 = AND IF PDF-S-OK EXIT THEN
    _I _PDIM.SPACE @ _PDIM-INDEXED <> IF
        _I _PDIM.NC @ 0 ?DO
            I _PDIM-DA @ _PDIM-DU @ _PDIM-DECODE
            _I _PDIM.BPC @  I 256 * _I _PDIM.LUT +  _PDIM-TABLE
        LOOP
    THEN
    _PDIM-MASK ?DUP IF EXIT THEN
    PIC-F-QOI _I _PDIM.FORMAT !  _PDIM-P-ROWS _I _PDIM.PATH !
    PIC-ST-PENDING _I _PDIM.STATE !  PDF-S-OK _I _PDIM.REASON !  PDF-S-OK ;

\ The facts of the picture whose dictionary is _PDIM-DA _PDIM-DU.
: _PDIM-FACTS  ( -- status )
    S" Subtype" _PDIM-DA @ _PDIM-DU @ PDF-DICT@ PDF-T-NAME = IF
        S" Image" PDF-NAME=
    ELSE 2DROP 0 THEN
    0= IF PDF-S-DAMAGED EXIT THEN
    S" Width" _PDIM-DA @ _PDIM-DU @ 0 _PDIM-INT@ _I _PDIM.W !
    S" Height" _PDIM-DA @ _PDIM-DU @ 0 _PDIM-INT@ _I _PDIM.H !
    _I _PDIM.W @ 1 < _I _PDIM.H @ 1 < OR IF PDF-S-DAMAGED EXIT THEN
    _PDIM-DA @ _PDIM-DU @ PDF-PICTURE-FILTERS SWAP DUP _I _PDIM.CODING !     ( lone? coding )
    DUP PDF-IMG-DCT = IF
        DROP PIC-F-JPEG _I _PDIM.FORMAT !  PDF-S-OK _I _PDIM.REASON !
        IF _PDIM-JPEG-PIECES EXIT THEN
        _PDIM-P-WHOLE _I _PDIM.PATH !  PIC-ST-PENDING _I _PDIM.STATE !  PDF-S-OK EXIT
    THEN
    NIP IF PDF-S-OK EXIT THEN
    _PDIM-SAMPLES ;

\ PDF-IMAGE-OPEN ( num file image -- status )
\   The facts of picture XObject NUM.  The record is given back with
\   PDF-IMAGE-FREE whatever the status.
: PDF-IMAGE-OPEN  ( num file image -- status )
    DUP _PDIM-I !  PDF-IMAGE-SIZE 0 FILL
    DUP _PDIM-F !  _I _PDIM.FILE !  DUP _I _PDIM.NUM !
    PIC-ST-FAILED _I _PDIM.STATE !  PDF-S-UNSUPPORTED _I _PDIM.REASON !
    _PDIM-F @ PDF-GET ?DUP IF SWAP _PDIM-FREE DUP _I _PDIM.REASON ! EXIT THEN
    DUP PDF-OBJ-STREAM? 0= IF _PDIM-FREE PDF-S-DAMAGED DUP _I _PDIM.REASON ! EXIT THEN
    DUP _PDIM-O !  PDF-OBJ-VALUE DROP _PDIM-DU ! _PDIM-DA !
    _PDIM-FACTS
    _PDIM-O @ _PDIM-FREE
    DUP IF PIC-ST-FAILED _I _PDIM.STATE !  DUP _I _PDIM.REASON ! THEN ;

\ =====================================================================
\  Making the file
\ =====================================================================

\ Give back what making the file holds while it runs.
: _PDIM-WORK-FREE  ( -- )
    _I _PDIM.RS _PDRS-FREE  _I _PDIM.MRS _PDRS-FREE
    _I _PDIM.PIX @ _I _PDIM.W @ 4 * _PDIM-GIVE  0 _I _PDIM.PIX !
    _I _PDIM.ENC @ QOI-ENC-SIZE _PDIM-GIVE  0 _I _PDIM.ENC ! ;

: _PDIM-FAIL  ( status -- )
    _I _PDIM.REASON !  PIC-ST-FAILED _I _PDIM.STATE !
    _PDIM-WORK-FREE  _I _PDIM.OUT _PDIM-MSRC PDF-BUF-FREE ;

: _PDIM-READY  ( -- )  _PDIM-WORK-FREE  PIC-ST-READY _I _PDIM.STATE ! ;

\ Room for U more bytes in the file.
: _PDIM-ROOM  ( u -- ok? )
    _I _PDIM.OUT PDF-BUF.U @ + _I _PDIM.OUT _PDIM-MSRC PDF-BUF-GROW ;

\ A JPEG copied, about BUDGET bytes a step.
: _PDIM-COPY  ( budget -- )
    _I _PDIM.OUT PDF-BUF.A @ 0= IF
        _I _PDIM.SPAN 8 + @ 1 MAX DUP _PDIM-ALLOC DUP 0= IF
            2DROP DROP PDF-S-MEMORY _PDIM-FAIL EXIT
        THEN
        _I _PDIM.OUT PDF-BUF.A !  _I _PDIM.OUT PDF-BUF.CAP !
    THEN
    _PDRS-PIECE MAX
    _I _PDIM.OUT DUP PDF-BUF.A @ SWAP PDF-BUF.U @ +  SWAP
    _I _PDIM.OUT DUP PDF-BUF.CAP @ SWAP PDF-BUF.U @ - MIN
    _I _PDIM.RS _PDRS.RAW PDF-RAW-READ ?DUP IF NIP _PDIM-FAIL EXIT THEN
    DUP 0= IF DROP _PDIM-READY EXIT THEN
    _I _PDIM.OUT PDF-BUF.U +! ;

\ A JPEG decoded whole from the filters before its own.
: _PDIM-JPEG-WHOLE  ( budget -- )
    DROP  _I _PDIM.NUM @ _PDIM-F @ PDF-GET ?DUP IF SWAP _PDIM-FREE _PDIM-FAIL EXIT THEN
    DUP _I _PDIM.OUT _PDIM-F @ PDF-STREAM-IMAGE ROT _PDIM-FREE
    ?DUP IF NIP _PDIM-FAIL EXIT THEN
    PDF-IMG-DCT <> IF PDF-S-UNSUPPORTED _PDIM-FAIL EXIT THEN
    _PDIM-READY ;

\ Begin the rows: the picture's and its mask's, a row of pixels, the
\ encoder and the file's header.
: _PDIM-START  ( -- status )
    _I _PDIM.NUM @ _PDIM-F @ PDF-GET ?DUP IF SWAP _PDIM-FREE EXIT THEN
    DUP  _I _PDIM.W @ _I _PDIM.NC @ * _I _PDIM.BPC @ * 7 + 3 RSHIFT  _I _PDIM.RS _PDRS-OPEN
    SWAP _PDIM-FREE ?DUP IF EXIT THEN
    _I _PDIM.MASK? @ IF
        _I _PDIM.MNUM @ _PDIM-F @ PDF-GET ?DUP IF SWAP _PDIM-FREE EXIT THEN
        DUP  _I _PDIM.MW @ _I _PDIM.MBPC @ * 7 + 3 RSHIFT  _I _PDIM.MRS _PDRS-OPEN
        SWAP _PDIM-FREE ?DUP IF EXIT THEN
    THEN
    _I _PDIM.W @ 4 * _PDIM-ALLOC DUP _I _PDIM.PIX ! 0= IF PDF-S-MEMORY EXIT THEN
    QOI-ENC-SIZE _PDIM-ALLOC DUP _I _PDIM.ENC ! 0= IF PDF-S-MEMORY EXIT THEN
    QOI-HDR-SIZE _PDIM-ROOM 0= IF PDF-S-MEMORY EXIT THEN
    _I _PDIM.W @ _I _PDIM.H @ _I _PDIM.MASK? @ IF 4 ELSE 3 THEN
    _I _PDIM.OUT PDF-BUF.A @ QOI-ENC-HEADER DROP  QOI-HDR-SIZE _I _PDIM.OUT PDF-BUF.U !
    _I _PDIM.ENC @ QOI-ENC-START
    -1 _I _PDIM.STARTED !  PDF-S-OK ;

\ Sample I of the row at ROW, BPC bits each, a sixteen-bit one by its
\ high byte.
: _PDIM-BITS  ( i row bpc -- v )
    DUP 8 = IF DROP + C@ EXIT THEN
    DUP 16 = IF DROP SWAP 2* + C@ EXIT THEN
    >R SWAP R@ *  DUP 3 RSHIFT ROT + C@
    SWAP 7 AND R@ + 8 SWAP - RSHIFT  1 R> LSHIFT 1- AND ;

VARIABLE _PDIM-SA     \ the picture's row
VARIABLE _PDIM-SP     \ the row of pixels

\ Component C of pixel X, through its table.
: _PDIM-C@  ( x c -- v )
    SWAP _I _PDIM.NC @ * OVER + _PDIM-SA @ _I _PDIM.BPC @ _PDIM-BITS
    SWAP 256 * _I _PDIM.LUT + + C@ ;

\ Pixel X's red, green and blue.
: _PDIM-RGB@  ( x -- r g b )
    _I _PDIM.SPACE @
    DUP _PDIM-GRAY = IF DROP 0 _PDIM-C@ DUP DUP EXIT THEN
    DUP _PDIM-RGB = IF DROP DUP 0 _PDIM-C@ OVER 1 _PDIM-C@ ROT 2 _PDIM-C@ EXIT THEN
    _PDIM-CMYK = IF
        DUP 0 _PDIM-C@ OVER 1 _PDIM-C@ 2 PICK 2 _PDIM-C@ 3 PICK 3 _PDIM-C@
        _PDIM-CMYK>RGB  >R >R >R DROP R> R> R> EXIT
    THEN
    _PDIM-SA @ _I _PDIM.BPC @ _PDIM-BITS  _I _PDIM.PALN @ 1- MIN
    3 * _I _PDIM.PAL @ +  DUP C@ OVER 1+ C@ ROT 2 + C@ ;

\ Pixel X's alpha, the mask's nearest pixel's.
: _PDIM-ALPHA@  ( x -- a )
    _I _PDIM.MASK? @ 0= IF DROP 255 EXIT THEN
    _I _PDIM.MW @ * _I _PDIM.W @ /
    _I _PDIM.MROW @ _I _PDIM.MBPC @ _PDIM-BITS  _I _PDIM.MLUT + C@ ;

\ The row of samples at A as pixels, each 32 bits, red highest.
: _PDIM-PIXELS  ( a -- )
    _PDIM-SA !  _I _PDIM.PIX @ _PDIM-SP !
    _I _PDIM.W @ 0 ?DO
        I _PDIM-RGB@  I _PDIM-ALPHA@
        SWAP 8 LSHIFT OR  SWAP 16 LSHIFT OR  SWAP 24 LSHIFT OR
        _PDIM-SP @ I 4 * + L!
    LOOP ;

\ The mask's row for the next picture row: its nearest.
: _PDIM-MASK-ROW  ( -- status )
    _I _PDIM.MASK? @ 0= IF PDF-S-OK EXIT THEN
    _I _PDIM.ROWS @ _I _PDIM.MH @ * _I _PDIM.H @ /
    BEGIN DUP _I _PDIM.MROWS @ < 0= WHILE
        _I _PDIM.MRS _PDRS-NEXT ?DUP IF NIP NIP EXIT THEN
        _I _PDIM.MROW !  1 _I _PDIM.MROWS +!
    REPEAT DROP PDF-S-OK ;

\ The next row made into pixels and encoded.
: _PDIM-ROW  ( -- status )
    _I _PDIM.RS _PDRS-NEXT ?DUP IF NIP EXIT THEN
    _PDIM-MASK-ROW ?DUP IF NIP EXIT THEN
    _PDIM-PIXELS
    _I _PDIM.W @ QOI-ENC-ROOM QOI-END-SIZE + 1+ _PDIM-ROOM 0= IF PDF-S-MEMORY EXIT THEN
    _I _PDIM.PIX @ _I _PDIM.W @
    _I _PDIM.OUT DUP PDF-BUF.A @ SWAP PDF-BUF.U @ +  _I _PDIM.ENC @ QOI-ENC-PIXELS
    _I _PDIM.OUT PDF-BUF.A @ - _I _PDIM.OUT PDF-BUF.U !
    1 _I _PDIM.ROWS +!  PDF-S-OK ;

\ The file's end.
: _PDIM-FINISH  ( -- )
    _I _PDIM.OUT DUP PDF-BUF.A @ SWAP PDF-BUF.U @ +  _I _PDIM.ENC @ QOI-ENC-END
    _I _PDIM.OUT PDF-BUF.A @ - _I _PDIM.OUT PDF-BUF.U !
    _PDIM-READY ;

VARIABLE _PDIM-BUDGET   VARIABLE _PDIM-DONE

\ About BUDGET pixels of rows, at least one row.
: _PDIM-ROWS  ( budget -- )
    _I _PDIM.STARTED @ 0= IF _PDIM-START ?DUP IF NIP _PDIM-FAIL EXIT THEN THEN
    _PDIM-BUDGET !  0 _PDIM-DONE !
    BEGIN
        _PDIM-ROW ?DUP IF _PDIM-FAIL EXIT THEN
        _I _PDIM.ROWS @ _I _PDIM.H @ = IF _PDIM-FINISH EXIT THEN
        _I _PDIM.W @ _PDIM-DONE +!  _PDIM-DONE @ _PDIM-BUDGET @ < 0=
    UNTIL ;

\ PDF-IMAGE-STEP ( budget image -- state )
\   Make about BUDGET more of the picture's file.
: PDF-IMAGE-STEP  ( budget image -- state )
    DUP _PDIM-I !  _PDIM.FILE @ _PDIM-F !
    _I _PDIM.STATE @ PIC-ST-PENDING <> IF DROP _I _PDIM.STATE @ EXIT THEN
    _I _PDIM.PATH @
    DUP _PDIM-P-COPY = IF DROP _PDIM-COPY ELSE
    DUP _PDIM-P-WHOLE = IF DROP _PDIM-JPEG-WHOLE ELSE
    _PDIM-P-ROWS = IF _PDIM-ROWS ELSE DROP THEN THEN THEN
    _I _PDIM.STATE @ ;

\ PDF-IMAGE-SOURCE ( image source -- )
\   SOURCE, MEDSRC-SPAN-SIZE bytes, reads the picture's ready file.
: PDF-IMAGE-SOURCE  ( image source -- )
    >R
    DUP _PDIM.PATH @ _PDIM-P-SPAN = IF
        DUP _PDIM.SPAN @  OVER _PDIM.SPAN 8 + @  ROT _PDIM.FILE @ PDF-FILE-SOURCE
        R> MEDSRC-SPAN EXIT
    THEN
    _PDIM.OUT DUP PDF-BUF.A @ SWAP PDF-BUF.U @ R> MEDSRC-MEMORY ;

\ PDF-IMAGE-FREE ( image -- )   Give back the picture's memory.
: PDF-IMAGE-FREE  ( image -- )
    DUP _PDIM-I !  DUP _PDIM.FILE @ ?DUP IF
        _PDIM-F !  _PDIM-WORK-FREE  _I _PDIM.OUT _PDIM-MSRC PDF-BUF-FREE
        _I _PDIM.PAL @ _I _PDIM.PALN @ 3 * _PDIM-GIVE
    THEN
    PDF-IMAGE-SIZE 0 FILL ;
