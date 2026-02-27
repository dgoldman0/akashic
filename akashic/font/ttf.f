\ ttf.f — TrueType font parser (minimum viable subset)
\
\ Parses raw TTF data in memory.  Big-endian aware.
\
\ Prefix: TTF-  (public API)
\         _TTF- (internal helpers)
\
\ Load with:   REQUIRE ttf.f

PROVIDED akashic-ttf

\ =====================================================================
\  Big-endian byte readers (platform is little-endian)
\ =====================================================================

: BE-W@  ( addr -- u16 )
    DUP C@ 8 LSHIFT  SWAP 1+ C@ OR ;

: BE-L@  ( addr -- u32 )
    DUP C@ 24 LSHIFT
    OVER 1+ C@ 16 LSHIFT OR
    OVER 2 + C@ 8 LSHIFT OR
    SWAP 3 + C@ OR ;

: BE-SW@  ( addr -- s16 )
    BE-W@ DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN ;

: BE-SL@  ( addr -- s32 )
    BE-L@ DUP 0x80000000 AND IF 0xFFFFFFFF00000000 OR THEN ;

\ =====================================================================
\  Table directory
\ =====================================================================

VARIABLE _TTF-BASE

: TTF-BASE!  ( addr -- )  _TTF-BASE ! ;
: TTF-BASE@  ( -- addr )  _TTF-BASE @ ;
: TTF-NUM-TABLES  ( -- n )  TTF-BASE@ 4 + BE-W@ ;

: TTF-TAG  ( c-addr u -- tag )
    DROP
    DUP C@ 24 LSHIFT
    OVER 1+ C@ 16 LSHIFT OR
    OVER 2 + C@ 8 LSHIFT OR
    SWAP 3 + C@ OR ;

: TTF-FIND-TABLE  ( tag -- addr len | 0 0 )
    TTF-BASE@ 12 +
    TTF-NUM-TABLES 0 DO
        OVER OVER BE-L@ = IF
            DUP 8 + BE-L@ TTF-BASE@ +
            SWAP 12 + BE-L@
            ROT DROP
            UNLOOP EXIT
        THEN
        16 +
    LOOP
    DROP  0 0 ;

\ =====================================================================
\  head + maxp
\ =====================================================================

VARIABLE _TTF-HEAD   VARIABLE _TTF-MAXP
VARIABLE _TTF-UPEM   VARIABLE _TTF-LOCA-FMT   VARIABLE _TTF-NGLYPHS

: TTF-PARSE-HEAD  ( -- flag )
    S" head" TTF-TAG TTF-FIND-TABLE
    DUP 0= IF 2DROP FALSE EXIT THEN
    DROP _TTF-HEAD !
    _TTF-HEAD @ 18 + BE-W@ _TTF-UPEM !
    _TTF-HEAD @ 50 + BE-SW@ _TTF-LOCA-FMT !
    TRUE ;

: TTF-PARSE-MAXP  ( -- flag )
    S" maxp" TTF-TAG TTF-FIND-TABLE
    DUP 0= IF 2DROP FALSE EXIT THEN
    DROP _TTF-MAXP !
    _TTF-MAXP @ 4 + BE-W@ _TTF-NGLYPHS !
    TRUE ;

: TTF-UPEM      ( -- n )  _TTF-UPEM @ ;
: TTF-LOCA-FMT  ( -- n )  _TTF-LOCA-FMT @ ;
: TTF-NGLYPHS   ( -- n )  _TTF-NGLYPHS @ ;

\ =====================================================================
\  hhea + hmtx — horizontal metrics
\ =====================================================================

VARIABLE _TTF-HHEA   VARIABLE _TTF-HMTX
VARIABLE _TTF-ASCENDER   VARIABLE _TTF-DESCENDER
VARIABLE _TTF-LINEGAP    VARIABLE _TTF-NHMETRICS

: TTF-PARSE-HHEA  ( -- flag )
    S" hhea" TTF-TAG TTF-FIND-TABLE
    DUP 0= IF 2DROP FALSE EXIT THEN
    DROP _TTF-HHEA !
    _TTF-HHEA @ 4 + BE-SW@ _TTF-ASCENDER !
    _TTF-HHEA @ 6 + BE-SW@ _TTF-DESCENDER !
    _TTF-HHEA @ 8 + BE-SW@ _TTF-LINEGAP !
    _TTF-HHEA @ 34 + BE-W@ _TTF-NHMETRICS !
    TRUE ;

: TTF-PARSE-HMTX  ( -- flag )
    S" hmtx" TTF-TAG TTF-FIND-TABLE
    DUP 0= IF 2DROP FALSE EXIT THEN
    DROP _TTF-HMTX !
    TRUE ;

: TTF-ADVANCE  ( glyph-id -- advance-width )
    DUP _TTF-NHMETRICS @ >= IF
        DROP _TTF-NHMETRICS @ 1-
    THEN
    4 * _TTF-HMTX @ + BE-W@ ;

: TTF-LSB  ( glyph-id -- lsb )
    DUP _TTF-NHMETRICS @ < IF
        4 * _TTF-HMTX @ + 2 + BE-SW@
    ELSE
        _TTF-NHMETRICS @ - 2 *
        _TTF-NHMETRICS @ 4 * +
        _TTF-HMTX @ + BE-SW@
    THEN ;

: TTF-ASCENDER   ( -- n )  _TTF-ASCENDER @ ;
: TTF-DESCENDER  ( -- n )  _TTF-DESCENDER @ ;
: TTF-LINEGAP    ( -- n )  _TTF-LINEGAP @ ;

\ =====================================================================
\  loca + glyf — glyph outline lookup
\ =====================================================================

VARIABLE _TTF-LOCA   VARIABLE _TTF-GLYF

: TTF-PARSE-LOCA  ( -- flag )
    S" loca" TTF-TAG TTF-FIND-TABLE
    DUP 0= IF 2DROP FALSE EXIT THEN
    DROP _TTF-LOCA !  TRUE ;

: TTF-PARSE-GLYF  ( -- flag )
    S" glyf" TTF-TAG TTF-FIND-TABLE
    DUP 0= IF 2DROP FALSE EXIT THEN
    DROP _TTF-GLYF !  TRUE ;

: _TTF-GLYPH-OFF  ( glyph-id -- offset )
    TTF-LOCA-FMT IF
        4 * _TTF-LOCA @ + BE-L@
    ELSE
        2 * _TTF-LOCA @ + BE-W@ 2 *
    THEN ;

: TTF-GLYPH-DATA  ( glyph-id -- addr len | 0 0 )
    DUP _TTF-GLYPH-OFF
    SWAP 1+ _TTF-GLYPH-OFF
    OVER - DUP 0= IF
        2DROP 0 0
    ELSE
        SWAP _TTF-GLYF @ + SWAP
    THEN ;

: TTF-GLYPH-NCONTOURS  ( glyph-addr -- n )   BE-SW@ ;
: TTF-GLYPH-XMIN       ( glyph-addr -- n )   2 + BE-SW@ ;
: TTF-GLYPH-YMIN       ( glyph-addr -- n )   4 + BE-SW@ ;
: TTF-GLYPH-XMAX       ( glyph-addr -- n )   6 + BE-SW@ ;
: TTF-GLYPH-YMAX       ( glyph-addr -- n )   8 + BE-SW@ ;

\ =====================================================================
\  Simple glyph point decoder
\ =====================================================================
\  Flag bits:
\    0  ON_CURVE_POINT
\    1  X_SHORT_VECTOR (1-byte x delta)
\    2  Y_SHORT_VECTOR (1-byte y delta)
\    3  REPEAT_FLAG
\    4  X_IS_SAME / POSITIVE_X_SHORT
\    5  Y_IS_SAME / POSITIVE_Y_SHORT

256 CONSTANT _TTF-MAX-PTS

HERE _TTF-MAX-PTS CELLS ALLOT CONSTANT _TTF-PTS-X
HERE _TTF-MAX-PTS CELLS ALLOT CONSTANT _TTF-PTS-Y
HERE _TTF-MAX-PTS       ALLOT CONSTANT _TTF-PTS-FL
HERE 64                  ALLOT CONSTANT _TTF-CONT-ENDS

VARIABLE _TTF-DEC-NPTS
VARIABLE _TTF-DEC-NCONT

\ --- Flag decoder ---
VARIABLE _TFD-SRC    VARIABLE _TFD-DST

: _TTF-DECODE-FLAGS  ( flag-addr npoints -- end-addr )
    >R                                  ( addr ) ( R: npts )
    _TFD-SRC !   0 _TFD-DST !
    BEGIN _TFD-DST @ R@ < WHILE
        _TFD-SRC @ C@                  ( flag )
        DUP _TTF-PTS-FL _TFD-DST @ + C!
        _TFD-DST @ 1+ _TFD-DST !
        _TFD-SRC @ 1+ _TFD-SRC !
        DUP 8 AND IF                   \ REPEAT_FLAG
            _TFD-SRC @ C@             ( flag count )
            _TFD-SRC @ 1+ _TFD-SRC !
            0 DO
                DUP _TTF-PTS-FL _TFD-DST @ + C!
                _TFD-DST @ 1+ _TFD-DST !
            LOOP
        THEN
        DROP
    REPEAT
    R> DROP
    _TFD-SRC @ ;

\ --- Coordinate decoder ---
\ Decodes one axis (x or y) from delta stream.
\   src     = byte address of delta data
\   npts    = number of points
\   dest    = cell array for absolute coords
\   s-bit   = bit# for SHORT_VECTOR (1=X, 2=Y)
\   p-bit   = bit# for POSITIVE/SAME (4=X, 5=Y)

VARIABLE _TCD-SRC   VARIABLE _TCD-ACC
VARIABLE _TCD-DEST  VARIABLE _TCD-SMASK  VARIABLE _TCD-PMASK

: _TTF-DECODE-COORDS  ( src npts dest s-bit p-bit -- end-src )
    1 SWAP LSHIFT _TCD-PMASK !
    1 SWAP LSHIFT _TCD-SMASK !
    _TCD-DEST !
    SWAP _TCD-SRC !
    0 _TCD-ACC !
    0 DO
        _TTF-PTS-FL I + C@            ( flag )
        DUP _TCD-SMASK @ AND IF        \ SHORT: 1-byte delta
            _TCD-SRC @ C@             ( flag byte )
            SWAP _TCD-PMASK @ AND IF   \ positive
            ELSE
                NEGATE
            THEN
            _TCD-ACC @ + _TCD-ACC !
            _TCD-SRC @ 1+ _TCD-SRC !
        ELSE                           \ not short
            _TCD-PMASK @ AND IF        \ IS_SAME: delta=0, no bytes
            ELSE                       \ 2-byte signed delta
                _TCD-SRC @ BE-SW@
                _TCD-ACC @ + _TCD-ACC !
                _TCD-SRC @ 2 + _TCD-SRC !
            THEN
        THEN
        _TCD-ACC @ _TCD-DEST @ I CELLS + !
    LOOP
    _TCD-SRC @ ;

\ --- Main decoder ---
: TTF-DECODE-GLYPH  ( glyph-id -- npoints ncontours | 0 0 )
    TTF-GLYPH-DATA
    DUP 0= IF EXIT THEN
    DROP                               ( addr )
    DUP TTF-GLYPH-NCONTOURS           ( addr ncont )
    DUP 0< IF 2DROP 0 0 EXIT THEN     \ composite — skip
    DUP 0= IF 2DROP 0 0 EXIT THEN     \ empty glyph (no contours)
    DUP _TTF-DEC-NCONT !              ( addr ncont )
    \ Read endPtsOfContours array
    SWAP 10 + SWAP                     ( epc-addr ncont )
    0 DO
        DUP BE-W@ _TTF-CONT-ENDS I CELLS + !
        2 +
    LOOP                               ( past-epc )
    \ Total points = last endPt + 1
    _TTF-CONT-ENDS _TTF-DEC-NCONT @ 1- CELLS + @
    1+ _TTF-DEC-NPTS !
    \ Skip instructions
    DUP BE-W@ + 2 +                   ( flag-addr )
    \ Decode flags
    _TTF-DEC-NPTS @ _TTF-DECODE-FLAGS ( x-addr )
    \ Decode X coordinates
    _TTF-DEC-NPTS @ _TTF-PTS-X 1 4
    _TTF-DECODE-COORDS                 ( y-addr )
    \ Decode Y coordinates
    _TTF-DEC-NPTS @ _TTF-PTS-Y 2 5
    _TTF-DECODE-COORDS                 ( end )
    DROP
    _TTF-DEC-NPTS @ _TTF-DEC-NCONT @ ;

\ Accessors for decoded data
: TTF-PT-X       ( i -- x )    CELLS _TTF-PTS-X + @ ;
: TTF-PT-Y       ( i -- y )    CELLS _TTF-PTS-Y + @ ;
: TTF-PT-FLAG    ( i -- flag ) _TTF-PTS-FL + C@ ;
: TTF-PT-ONCURVE? ( i -- f )  TTF-PT-FLAG 1 AND ;
: TTF-CONT-END   ( i -- idx ) CELLS _TTF-CONT-ENDS + @ ;

\ =====================================================================
\  cmap — character to glyph mapping (format 4 only)
\ =====================================================================
\  Format 4 is "Segment mapping to delta values", the standard encoding
\  for BMP (Basic Multilingual Plane) characters in virtually all TTFs.

VARIABLE _TTF-CMAP          \ base address of cmap table
VARIABLE _TTF-CMAP4         \ base address of format 4 subtable
VARIABLE _TTF-CMAP4-NSEG    \ segment count

VARIABLE _CM-PID   VARIABLE _CM-EID

: TTF-PARSE-CMAP  ( -- flag )
    S" cmap" TTF-TAG TTF-FIND-TABLE
    DUP 0= IF 2DROP FALSE EXIT THEN
    DROP _TTF-CMAP !
    \ Scan encoding records for format 4 subtable
    \ Prefer (3,1) Windows Unicode BMP or (0,*) Unicode
    _TTF-CMAP @ 2 + BE-W@              ( numRecs )
    _TTF-CMAP @ 4 +                    ( numRecs rec )
    SWAP 0 DO
        DUP BE-W@ _CM-PID !
        DUP 2 + BE-W@ _CM-EID !
        _CM-PID @ 0=
        _CM-PID @ 3 = _CM-EID @ 1 = AND
        OR IF
            DUP 4 + BE-L@ _TTF-CMAP @ + ( rec subtable )
            DUP BE-W@ 4 = IF            \ format 4?
                _TTF-CMAP4 !
                DROP
                _TTF-CMAP4 @ 6 + BE-W@ 2 / _TTF-CMAP4-NSEG !
                TRUE UNLOOP EXIT
            THEN
            DROP
        THEN
        8 +
    LOOP
    DROP FALSE ;

\ --- Format 4 segment array accessors ---
\  endCode[i]        at subtable + 14 + 2*i
\  (reservedPad)     at subtable + 14 + 2*segCount
\  startCode[i]      at subtable + 16 + 2*segCount + 2*i
\  idDelta[i]        at subtable + 16 + 4*segCount + 2*i
\  idRangeOffset[i]  at subtable + 16 + 6*segCount + 2*i

: _CMAP4-ENDCODE    ( i -- addr )
    2 * _TTF-CMAP4 @ 14 + + ;
: _CMAP4-STARTCODE  ( i -- addr )
    2 * _TTF-CMAP4-NSEG @ 2 * + _TTF-CMAP4 @ 16 + + ;
: _CMAP4-IDDELTA    ( i -- addr )
    2 * _TTF-CMAP4-NSEG @ 4 * + _TTF-CMAP4 @ 16 + + ;
: _CMAP4-IDRANGEOFF ( i -- addr )
    2 * _TTF-CMAP4-NSEG @ 6 * + _TTF-CMAP4 @ 16 + + ;

: TTF-CMAP-LOOKUP  ( unicode -- glyph-id )
    _TTF-CMAP4-NSEG @ 0 DO
        DUP I _CMAP4-ENDCODE BE-W@ <= IF
            DUP I _CMAP4-STARTCODE BE-W@ >= IF
                \ Codepoint is in segment I
                I _CMAP4-IDRANGEOFF DUP BE-W@   ( cp ro-addr ro-val )
                DUP 0= IF
                    \ Simple delta: glyph = (cp + idDelta) mod 65536
                    2DROP I _CMAP4-IDDELTA BE-SW@ + 0xFFFF AND
                    UNLOOP EXIT
                ELSE
                    \ Indexed: addr = &rangeOff[i] + rangeOff + 2*(cp-start)
                    OVER +                          ( cp base )
                    SWAP I _CMAP4-STARTCODE BE-W@ - ( base c-s )
                    2 * + BE-W@                     ( raw-gid )
                    DUP 0<> IF
                        I _CMAP4-IDDELTA BE-SW@ + 0xFFFF AND
                    THEN
                    UNLOOP EXIT
                THEN
            THEN
        THEN
    LOOP
    DROP 0 ;
