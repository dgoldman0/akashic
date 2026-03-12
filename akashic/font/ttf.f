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

\ Forward declaration — _TTF-DECODE-SIMPLE fills arrays from index 0.
\ _TTF-DECODE-COMPOSITE calls it per-component and accumulates.

: _TTF-DECODE-SIMPLE  ( addr ncont -- npoints ncontours | 0 0 )
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

\ =====================================================================
\  Composite glyph decoder
\ =====================================================================
\  Parses component records, decodes each sub-glyph, accumulates
\  points with x/y translation into result arrays, then copies back.
\
\  Composite flags (relevant bits):
\    0  ARG_1_AND_2_ARE_WORDS   args are 16-bit signed
\    1  ARGS_ARE_XY_OFFSETS     args are dx,dy (not point indices)
\    3  WE_HAVE_A_SCALE         one F2Dot14 scale follows
\    5  MORE_COMPONENTS         another component follows
\    6  WE_HAVE_AN_X_AND_Y_SCALE  two F2Dot14 scales follow
\    7  WE_HAVE_A_TWO_BY_TWO   four F2Dot14 values follow

\ Accumulation arrays (same size as main arrays)
HERE _TTF-MAX-PTS CELLS ALLOT CONSTANT _CG-ACC-X
HERE _TTF-MAX-PTS CELLS ALLOT CONSTANT _CG-ACC-Y
HERE _TTF-MAX-PTS       ALLOT CONSTANT _CG-ACC-FL
HERE 64                  ALLOT CONSTANT _CG-ACC-CE

VARIABLE _CG-ADDR          \ read pointer into composite data
VARIABLE _CG-TPT            \ total accumulated points
VARIABLE _CG-TCN            \ total accumulated contours
VARIABLE _CG-FLAGS          \ current component flags
VARIABLE _CG-GID            \ current component glyph-id
VARIABLE _CG-DX             \ current component x-offset
VARIABLE _CG-DY             \ current component y-offset
VARIABLE _CG-SCX            \ scale X (F2Dot14, 16384 = 1.0)
VARIABLE _CG-SCY            \ scale Y (F2Dot14, 16384 = 1.0)
VARIABLE _CG-SNP            \ sub-glyph npoints
VARIABLE _CG-SNC            \ sub-glyph ncontours
VARIABLE _CG-I              \ loop index

: _CG-PARSE-COMPONENT  ( -- )
    \ Read flags and glyph index
    _CG-ADDR @ BE-W@ _CG-FLAGS !
    _CG-ADDR @ 2 + BE-W@ _CG-GID !
    _CG-ADDR @ 4 + _CG-ADDR !
    \ Parse dx, dy
    _CG-FLAGS @ 1 AND IF              \ ARG_1_AND_2_ARE_WORDS
        _CG-ADDR @ BE-SW@ _CG-DX !
        _CG-ADDR @ 2 + BE-SW@ _CG-DY !
        _CG-ADDR @ 4 + _CG-ADDR !
    ELSE                               \ args are bytes
        _CG-ADDR @ C@ DUP 128 >= IF 256 - THEN _CG-DX !
        _CG-ADDR @ 1+ C@ DUP 128 >= IF 256 - THEN _CG-DY !
        _CG-ADDR @ 2 + _CG-ADDR !
    THEN
    \ Parse scale / matrix data (F2Dot14 signed, 16384 = 1.0)
    16384 _CG-SCX !  16384 _CG-SCY !  \ default: identity
    _CG-FLAGS @ 8 AND IF              \ WE_HAVE_A_SCALE (uniform)
        _CG-ADDR @ BE-SW@ DUP _CG-SCX !  _CG-SCY !
        _CG-ADDR @ 2 + _CG-ADDR !
    THEN
    _CG-FLAGS @ 64 AND IF             \ WE_HAVE_AN_X_AND_Y_SCALE
        _CG-ADDR @ BE-SW@ _CG-SCX !
        _CG-ADDR @ 2 + BE-SW@ _CG-SCY !
        _CG-ADDR @ 4 + _CG-ADDR !
    THEN
    _CG-FLAGS @ 128 AND IF            \ WE_HAVE_A_TWO_BY_TWO (skip 8 bytes)
        _CG-ADDR @ BE-SW@ _CG-SCX !   \ use m00 as scaleX
        _CG-ADDR @ 4 + BE-SW@ _CG-SCY !  \ use m11 as scaleY
        _CG-ADDR @ 8 + _CG-ADDR !     \ skip all 8 bytes
    THEN ;

: _CG-ACCUMULATE  ( -- )
    \ After _TTF-DECODE-SIMPLE filled main arrays from 0,
    \ copy sub_npts/sub_ncont to accumulation arrays at offset,
    \ applying scale then dx/dy translation.
    _TTF-DEC-NPTS @ _CG-SNP !
    _TTF-DEC-NCONT @ _CG-SNC !
    _CG-SNP @ 0= IF EXIT THEN
    \ Check bounds
    _CG-TPT @ _CG-SNP @ + _TTF-MAX-PTS > IF EXIT THEN
    \ Copy X coords: apply scaleX then dx
    _CG-SNP @ 0 DO
        _TTF-PTS-X I CELLS + @
        _CG-SCX @ 16384 <> IF  _CG-SCX @ * 16384 /  THEN
        _CG-DX @ +
        _CG-ACC-X _CG-TPT @ I + CELLS + !
    LOOP
    \ Copy Y coords: apply scaleY then dy
    _CG-SNP @ 0 DO
        _TTF-PTS-Y I CELLS + @
        _CG-SCY @ 16384 <> IF  _CG-SCY @ * 16384 /  THEN
        _CG-DY @ +
        _CG-ACC-Y _CG-TPT @ I + CELLS + !
    LOOP
    \ Copy flags
    _TTF-PTS-FL  _CG-ACC-FL _CG-TPT @ +  _CG-SNP @ CMOVE
    \ Copy contour ends + adjust by accumulated point offset
    _CG-SNC @ 0 DO
        _TTF-CONT-ENDS I CELLS + @  _CG-TPT @ +
        _CG-ACC-CE _CG-TCN @ I + CELLS + !
    LOOP
    \ Advance totals
    _CG-SNP @ _CG-TPT +!
    _CG-SNC @ _CG-TCN +! ;

: _TTF-DECODE-COMPOSITE  ( addr -- npoints ncontours | 0 0 )
    10 + _CG-ADDR !                    \ skip glyph header
    0 _CG-TPT !  0 _CG-TCN !
    BEGIN
        _CG-PARSE-COMPONENT
        \ Only handle XY offsets (bit 1 set)
        _CG-FLAGS @ 2 AND IF
            \ Decode sub-glyph (fills main arrays from 0)
            _CG-GID @ TTF-GLYPH-DATA
            DUP 0<> IF
                DROP                   ( sub-addr )
                DUP TTF-GLYPH-NCONTOURS ( sub-addr sub-ncont )
                DUP 0> IF
                    _TTF-DECODE-SIMPLE
                    DROP DROP          \ discard simple's return, use accumulator
                    _CG-ACCUMULATE
                ELSE
                    2DROP              \ skip if empty or nested composite
                THEN
            ELSE
                2DROP                  \ no glyph data
            THEN
        THEN
        _CG-FLAGS @ 32 AND            \ MORE_COMPONENTS?
    0= UNTIL
    \ Copy accumulated data back to main arrays
    _CG-TPT @ 0= IF 0 0 EXIT THEN
    _CG-ACC-X  _TTF-PTS-X   _CG-TPT @ CELLS CMOVE
    _CG-ACC-Y  _TTF-PTS-Y   _CG-TPT @ CELLS CMOVE
    _CG-ACC-FL _TTF-PTS-FL  _CG-TPT @       CMOVE
    _CG-ACC-CE _TTF-CONT-ENDS _CG-TCN @ CELLS CMOVE
    _CG-TPT @ _TTF-DEC-NPTS !
    _CG-TCN @ _TTF-DEC-NCONT !
    _CG-TPT @ _CG-TCN @ ;

: TTF-DECODE-GLYPH  ( glyph-id -- npoints ncontours | 0 0 )
    TTF-GLYPH-DATA
    DUP 0= IF EXIT THEN
    DROP                               ( addr )
    DUP TTF-GLYPH-NCONTOURS           ( addr ncont )
    DUP 0< IF
        DROP _TTF-DECODE-COMPOSITE EXIT   \ composite glyph
    THEN
    _TTF-DECODE-SIMPLE ;

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

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ttf-guard

' BE-W@           CONSTANT _be-w-at-xt
' BE-L@           CONSTANT _be-l-at-xt
' BE-SW@          CONSTANT _be-sw-at-xt
' BE-SL@          CONSTANT _be-sl-at-xt
' TTF-BASE!       CONSTANT _ttf-base-s-xt
' TTF-BASE@       CONSTANT _ttf-base-at-xt
' TTF-NUM-TABLES  CONSTANT _ttf-num-tables-xt
' TTF-TAG         CONSTANT _ttf-tag-xt
' TTF-FIND-TABLE  CONSTANT _ttf-find-table-xt
' TTF-PARSE-HEAD  CONSTANT _ttf-parse-head-xt
' TTF-PARSE-MAXP  CONSTANT _ttf-parse-maxp-xt
' TTF-UPEM        CONSTANT _ttf-upem-xt
' TTF-LOCA-FMT    CONSTANT _ttf-loca-fmt-xt
' TTF-NGLYPHS     CONSTANT _ttf-nglyphs-xt
' TTF-PARSE-HHEA  CONSTANT _ttf-parse-hhea-xt
' TTF-PARSE-HMTX  CONSTANT _ttf-parse-hmtx-xt
' TTF-ADVANCE     CONSTANT _ttf-advance-xt
' TTF-LSB         CONSTANT _ttf-lsb-xt
' TTF-ASCENDER    CONSTANT _ttf-ascender-xt
' TTF-DESCENDER   CONSTANT _ttf-descender-xt
' TTF-LINEGAP     CONSTANT _ttf-linegap-xt
' TTF-PARSE-LOCA  CONSTANT _ttf-parse-loca-xt
' TTF-PARSE-GLYF  CONSTANT _ttf-parse-glyf-xt
' TTF-GLYPH-DATA  CONSTANT _ttf-glyph-data-xt
' TTF-GLYPH-NCONTOURS CONSTANT _ttf-glyph-ncontours-xt
' TTF-GLYPH-XMIN  CONSTANT _ttf-glyph-xmin-xt
' TTF-GLYPH-YMIN  CONSTANT _ttf-glyph-ymin-xt
' TTF-GLYPH-XMAX  CONSTANT _ttf-glyph-xmax-xt
' TTF-GLYPH-YMAX  CONSTANT _ttf-glyph-ymax-xt
' TTF-DECODE-GLYPH CONSTANT _ttf-decode-glyph-xt
' TTF-PT-X        CONSTANT _ttf-pt-x-xt
' TTF-PT-Y        CONSTANT _ttf-pt-y-xt
' TTF-PT-FLAG     CONSTANT _ttf-pt-flag-xt
' TTF-PT-ONCURVE? CONSTANT _ttf-pt-oncurve-q-xt
' TTF-CONT-END    CONSTANT _ttf-cont-end-xt
' TTF-PARSE-CMAP  CONSTANT _ttf-parse-cmap-xt
' TTF-CMAP-LOOKUP CONSTANT _ttf-cmap-lookup-xt

: BE-W@           _be-w-at-xt _ttf-guard WITH-GUARD ;
: BE-L@           _be-l-at-xt _ttf-guard WITH-GUARD ;
: BE-SW@          _be-sw-at-xt _ttf-guard WITH-GUARD ;
: BE-SL@          _be-sl-at-xt _ttf-guard WITH-GUARD ;
: TTF-BASE!       _ttf-base-s-xt _ttf-guard WITH-GUARD ;
: TTF-BASE@       _ttf-base-at-xt _ttf-guard WITH-GUARD ;
: TTF-NUM-TABLES  _ttf-num-tables-xt _ttf-guard WITH-GUARD ;
: TTF-TAG         _ttf-tag-xt _ttf-guard WITH-GUARD ;
: TTF-FIND-TABLE  _ttf-find-table-xt _ttf-guard WITH-GUARD ;
: TTF-PARSE-HEAD  _ttf-parse-head-xt _ttf-guard WITH-GUARD ;
: TTF-PARSE-MAXP  _ttf-parse-maxp-xt _ttf-guard WITH-GUARD ;
: TTF-UPEM        _ttf-upem-xt _ttf-guard WITH-GUARD ;
: TTF-LOCA-FMT    _ttf-loca-fmt-xt _ttf-guard WITH-GUARD ;
: TTF-NGLYPHS     _ttf-nglyphs-xt _ttf-guard WITH-GUARD ;
: TTF-PARSE-HHEA  _ttf-parse-hhea-xt _ttf-guard WITH-GUARD ;
: TTF-PARSE-HMTX  _ttf-parse-hmtx-xt _ttf-guard WITH-GUARD ;
: TTF-ADVANCE     _ttf-advance-xt _ttf-guard WITH-GUARD ;
: TTF-LSB         _ttf-lsb-xt _ttf-guard WITH-GUARD ;
: TTF-ASCENDER    _ttf-ascender-xt _ttf-guard WITH-GUARD ;
: TTF-DESCENDER   _ttf-descender-xt _ttf-guard WITH-GUARD ;
: TTF-LINEGAP     _ttf-linegap-xt _ttf-guard WITH-GUARD ;
: TTF-PARSE-LOCA  _ttf-parse-loca-xt _ttf-guard WITH-GUARD ;
: TTF-PARSE-GLYF  _ttf-parse-glyf-xt _ttf-guard WITH-GUARD ;
: TTF-GLYPH-DATA  _ttf-glyph-data-xt _ttf-guard WITH-GUARD ;
: TTF-GLYPH-NCONTOURS _ttf-glyph-ncontours-xt _ttf-guard WITH-GUARD ;
: TTF-GLYPH-XMIN  _ttf-glyph-xmin-xt _ttf-guard WITH-GUARD ;
: TTF-GLYPH-YMIN  _ttf-glyph-ymin-xt _ttf-guard WITH-GUARD ;
: TTF-GLYPH-XMAX  _ttf-glyph-xmax-xt _ttf-guard WITH-GUARD ;
: TTF-GLYPH-YMAX  _ttf-glyph-ymax-xt _ttf-guard WITH-GUARD ;
: TTF-DECODE-GLYPH _ttf-decode-glyph-xt _ttf-guard WITH-GUARD ;
: TTF-PT-X        _ttf-pt-x-xt _ttf-guard WITH-GUARD ;
: TTF-PT-Y        _ttf-pt-y-xt _ttf-guard WITH-GUARD ;
: TTF-PT-FLAG     _ttf-pt-flag-xt _ttf-guard WITH-GUARD ;
: TTF-PT-ONCURVE? _ttf-pt-oncurve-q-xt _ttf-guard WITH-GUARD ;
: TTF-CONT-END    _ttf-cont-end-xt _ttf-guard WITH-GUARD ;
: TTF-PARSE-CMAP  _ttf-parse-cmap-xt _ttf-guard WITH-GUARD ;
: TTF-CMAP-LOOKUP _ttf-cmap-lookup-xt _ttf-guard WITH-GUARD ;
[THEN] [THEN]
