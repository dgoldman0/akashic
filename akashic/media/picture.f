\ =====================================================================
\  media/picture.f — a picture scaled to fit, decoded a step at a time
\ =====================================================================
\
\  A picture copy is one picture no larger than a width and height its
\  caller asks for, as raw row-major RGBA8 (the rich terminal's resource
\  format), with the SHA3-256 digest of those bytes.  It keeps the
\  picture's shape, never enlarges it, and scales it down by averaging
\  while it decodes, so the picture is never held at full size.  Each user
\  asks for the size it shows: a CELL view two pixels a cell high, a rich
\  terminal what its pixel answer said.
\
\  The work runs in bounded steps.  PIC-STEP decodes about a budget of
\  source pixels, at least one row, and returns, so its caller stays
\  responsive.  Memory comes from the caller's memory source, sized
\  exactly for this copy: one input chunk, one source row, one row of
\  sums when scaling, and the copy itself.  The input and row buffers go
\  back once the copy is ready; PIC-FREE gives back the rest.
\
\  Averaging weights each colour by its alpha, so transparent pixels do
\  not darken their neighbours.  Only QOI files decode so far; any other
\  file fails as unsupported.
\
\  Prefix: PIC- (public), _PIC- (private)
\
\  Public API:
\    PIC-SIZE           ( -- bytes )
\    PIC-FIT            ( sw sh mw mh -- ow oh )
\    PIC-START          ( max-w max-h source msrc pic -- state )
\    PIC-STEP           ( budget pic -- state )
\    PIC-FREE           ( pic -- )
\    PIC-STATE@         ( pic -- state )
\    PIC-REASON@        ( pic -- reason )
\    PIC-WIDTH@         ( pic -- w )     the copy
\    PIC-HEIGHT@        ( pic -- h )
\    PIC-SOURCE-WIDTH@  ( pic -- w )     the picture
\    PIC-SOURCE-HEIGHT@ ( pic -- h )
\    PIC-PIXELS         ( pic -- a u )   when ready, else 0 0
\    PIC-DIGEST         ( pic -- a )     32 bytes when ready, else 0
\ =====================================================================

REQUIRE ../render/qoi.f
REQUIRE ../math/sha3-context.f
REQUIRE ../utils/memory-source.f
REQUIRE source.f

PROVIDED akashic-media-picture

0 CONSTANT PIC-ST-EMPTY
1 CONSTANT PIC-ST-PENDING
2 CONSTANT PIC-ST-READY
3 CONSTANT PIC-ST-FAILED

0 CONSTANT PIC-R-NONE
1 CONSTANT PIC-R-UNSUPPORTED   \ not a picture this module decodes
2 CONSTANT PIC-R-DAMAGED       \ a bad header, a short file, or a wrong end
3 CONSTANT PIC-R-READ          \ the source could not be read
4 CONSTANT PIC-R-MEMORY        \ the caller's memory refused
5 CONSTANT PIC-R-INVALID       \ a bad bound, source, or memory source

\ How much of the file one read takes.  Only the step's pace depends on it.
4096 CONSTANT _PIC-IN-BYTES

\ One row of sums per output column: red, green and blue each times alpha,
\ alpha, and the pixel count.
40 CONSTANT _PIC-SUM-BYTES

0x31455255544349 CONSTANT _PIC-MAGIC   \ "ICTURE1"

  0 CONSTANT _PIC.MAGIC
  8 CONSTANT _PIC.STATE
 16 CONSTANT _PIC.REASON
 24 CONSTANT _PIC.SOURCE
 32 CONSTANT _PIC.MSRC
 40 CONSTANT _PIC.SW
 48 CONSTANT _PIC.SH
 56 CONSTANT _PIC.OW
 64 CONSTANT _PIC.OH
 72 CONSTANT _PIC.OFFSET      \ next byte of the file to read
 80 CONSTANT _PIC.IN          \ input chunk
 88 CONSTANT _PIC.IN-U        \ bytes in it
 96 CONSTANT _PIC.IN-P        \ bytes of it used
104 CONSTANT _PIC.ROW         \ one source row
112 CONSTANT _PIC.SUMS        \ one output row of sums, or 0
120 CONSTANT _PIC.OUT         \ the copy
128 CONSTANT _PIC.Y           \ source rows done
136 CONSTANT _PIC.OY          \ output row the sums hold, or -1
144 CONSTANT _PIC.HEADER      \ the file's first bytes, 16 bytes
160 CONSTANT _PIC.DEC
_PIC.DEC QOI-DEC-SIZE + CONSTANT _PIC.HASH
_PIC.HASH SHA3-256-CONTEXT-SIZE + CONSTANT _PIC.DIGEST
_PIC.DIGEST 32 + CONSTANT PIC-SIZE

VARIABLE _PIC-P      \ the copy being worked on

: _PIC@  ( offset -- x )  _PIC-P @ + @ ;
: _PIC!  ( x offset -- )  _PIC-P @ + ! ;

: _PIC-SCALING?  ( -- flag )
    _PIC.OW _PIC@ _PIC.SW _PIC@ <  _PIC.OH _PIC@ _PIC.SH _PIC@ < OR ;

: _PIC-ALLOC  ( bytes -- addr|0 )  _PIC.MSRC _PIC@ MSRC-ALLOC ;

\ Give back one buffer held at OFFSET, BYTES long, if it is held.
: _PIC-GIVE  ( bytes offset -- )
    DUP _PIC@ ?DUP IF
        ROT _PIC.MSRC _PIC@ MSRC-FREE  0 SWAP _PIC!
    ELSE 2DROP THEN ;

: _PIC-GIVE-WORK  ( -- )
    _PIC-IN-BYTES _PIC.IN _PIC-GIVE
    _PIC.SW _PIC@ 4 * _PIC.ROW _PIC-GIVE
    _PIC.OW _PIC@ _PIC-SUM-BYTES * _PIC.SUMS _PIC-GIVE ;

: _PIC-FAIL  ( reason -- state )
    _PIC.REASON _PIC!
    _PIC-GIVE-WORK
    _PIC.OW _PIC@ _PIC.OH _PIC@ * 4 * _PIC.OUT _PIC-GIVE
    PIC-ST-FAILED DUP _PIC.STATE _PIC! ;

\ =====================================================================
\  Fitting
\ =====================================================================

VARIABLE _PF-SW  VARIABLE _PF-SH  VARIABLE _PF-MW  VARIABLE _PF-MH

\ PIC-FIT ( sw sh mw mh -- ow oh )
\   The largest size no larger than MW by MH with the picture's shape,
\   never larger than the picture itself, and at least one pixel each way.
\   Sides must be below 2^31.
: PIC-FIT  ( sw sh mw mh -- ow oh )
    _PF-MH ! _PF-MW ! _PF-SH ! _PF-SW !
    _PF-SW @ _PF-MW @ > 0= _PF-SH @ _PF-MH @ > 0= AND IF
        _PF-SW @ _PF-SH @ EXIT
    THEN
    _PF-SW @ _PF-MH @ * _PF-SH @ _PF-MW @ * > 0= IF
        \ The height limits it: the whole height, the width in proportion.
        _PF-SW @ _PF-MH @ * _PF-SH @ 1 RSHIFT + _PF-SH @ / 1 MAX _PF-MH @
    ELSE
        _PF-MW @ _PF-SH @ _PF-MW @ * _PF-SW @ 1 RSHIFT + _PF-SW @ / 1 MAX
    THEN ;

\ =====================================================================
\  Start
\ =====================================================================

VARIABLE _PS-MW
VARIABLE _PS-MH

: _PIC-SOURCE  ( -- source )  _PIC.SOURCE _PIC@ ;

\ The file starts like a QOI file even though its header is wrong.
: _PIC-QOI-MAGIC?  ( -- flag )
    _PIC-SOURCE MEDSRC-SIZE@ 4 < IF 0 EXIT THEN
    _PIC-P @ _PIC.HEADER +
    DUP C@ 113 = OVER 1+ C@ 111 = AND OVER 2 + C@ 105 = AND
    SWAP 3 + C@ 102 = AND ;                       \ "qoif"

\ Read and check the header; on success the picture's size is set.
: _PIC-HEADER?  ( -- reason )
    _PIC-SOURCE MEDSRC-SIZE@ QOI-HDR-SIZE MIN
    _PIC-P @ _PIC.HEADER + OVER 0 _PIC-SOURCE MEDSRC-READ? IF
        DROP PIC-R-READ EXIT
    THEN
    _PIC-P @ _PIC.HEADER + SWAP QOI-HEADER 0= IF
        _PIC-QOI-MAGIC? IF PIC-R-DAMAGED ELSE PIC-R-UNSUPPORTED THEN EXIT
    THEN
    2DROP _PIC.SH _PIC! _PIC.SW _PIC!
    \ A side of 2^31 pixels or more needs more memory than any machine has.
    _PIC.SW _PIC@ 0x7FFFFFFF U> _PIC.SH _PIC@ 0x7FFFFFFF U> OR IF
        PIC-R-MEMORY EXIT
    THEN
    PIC-R-NONE ;

: _PIC-HOLD  ( bytes offset -- ok? )
    SWAP _PIC-ALLOC DUP IF SWAP _PIC! -1 ELSE NIP THEN ;

\ PIC-START ( max-w max-h source msrc pic -- state )
\   Start a copy no larger than MAX-W by MAX-H of the picture in SOURCE,
\   with memory from MSRC.  PIC is a record of PIC-SIZE bytes, eight-byte
\   aligned.  The state is PENDING, or FAILED with PIC-REASON@ saying why.
: PIC-START  ( max-w max-h source msrc pic -- state )
    DUP _PIC-P !  PIC-SIZE 0 FILL
    _PIC-MAGIC _PIC.MAGIC _PIC!
    _PIC.MSRC _PIC!  _PIC.SOURCE _PIC!
    _PS-MH ! _PS-MW !
    _PS-MW @ 1 < _PS-MH @ 1 < OR
    _PIC-SOURCE MEDSRC-VALID? 0= OR
    _PIC.MSRC _PIC@ MSRC-VALID? 0= OR IF PIC-R-INVALID _PIC-FAIL EXIT THEN
    _PIC-HEADER? ?DUP IF _PIC-FAIL EXIT THEN
    _PIC.SW _PIC@ _PIC.SH _PIC@ _PS-MW @ _PS-MH @ PIC-FIT
    _PIC.OH _PIC! _PIC.OW _PIC!
    _PIC-IN-BYTES _PIC.IN _PIC-HOLD 0= IF PIC-R-MEMORY _PIC-FAIL EXIT THEN
    _PIC.SW _PIC@ 4 * _PIC.ROW _PIC-HOLD 0= IF PIC-R-MEMORY _PIC-FAIL EXIT THEN
    _PIC-SCALING? IF
        _PIC.OW _PIC@ _PIC-SUM-BYTES * _PIC.SUMS _PIC-HOLD 0= IF
            PIC-R-MEMORY _PIC-FAIL EXIT
        THEN
        _PIC.SUMS _PIC@ _PIC.OW _PIC@ _PIC-SUM-BYTES * 0 FILL
    THEN
    _PIC.OW _PIC@ _PIC.OH _PIC@ * 4 * _PIC.OUT _PIC-HOLD 0= IF
        PIC-R-MEMORY _PIC-FAIL EXIT
    THEN
    _PIC.SW _PIC@ _PIC.SH _PIC@ _PIC-P @ _PIC.DEC + QOI-DEC-INIT
    _PIC-P @ _PIC.HASH + SHA3-256-CONTEXT-INIT IF PIC-R-INVALID _PIC-FAIL EXIT THEN
    QOI-HDR-SIZE _PIC.OFFSET _PIC!
    -1 _PIC.OY _PIC!
    PIC-ST-PENDING DUP _PIC.STATE _PIC! ;

\ =====================================================================
\  Rows
\ =====================================================================

\ Add BYTES at A to the digest.
: _PIC-HASH  ( a bytes -- ok? )
    _PIC-P @ _PIC.HASH + SHA3-256-CONTEXT-UPDATE 0= ;

: _PIC-OUT-ROW  ( y -- a )  _PIC.OW _PIC@ 4 * * _PIC.OUT _PIC@ + ;

VARIABLE _PA-P     \ next source pixel
VARIABLE _PA-E     \ sums of the output column it goes to
VARIABLE _PA-ERR   \ how far that column is filled, in OW steps
VARIABLE _PA-OW
VARIABLE _PA-SW

\ Add the source row to the sums.  Source column X goes to output column
\ X * OW / SW, stepped without dividing.
: _PIC-ADD-ROW  ( -- )
    _PIC.ROW _PIC@ _PA-P !  _PIC.SUMS _PIC@ _PA-E !  0 _PA-ERR !
    _PIC.OW _PIC@ _PA-OW !  _PIC.SW _PIC@ _PA-SW !
    _PA-SW @ 0 ?DO
        _PA-P @ 3 + C@
        _PA-P @ C@ OVER * _PA-E @ +!
        _PA-P @ 1+ C@ OVER * _PA-E @ 8 + +!
        _PA-P @ 2 + C@ OVER * _PA-E @ 16 + +!
        _PA-E @ 24 + +!
        1 _PA-E @ 32 + +!
        4 _PA-P +!
        _PA-OW @ _PA-ERR +!
        _PA-ERR @ _PA-SW @ < 0= IF
            _PA-SW @ NEGATE _PA-ERR +!  _PIC-SUM-BYTES _PA-E +!
        THEN
    LOOP ;

VARIABLE _PL-D     \ next output pixel
VARIABLE _PL-E
VARIABLE _PL-A     \ alpha sum

\ (SUM + DIV/2) / DIV, DIV positive.
: _PIC-ROUND/  ( sum div -- q )  TUCK 1 RSHIFT + SWAP / ;

\ Write the output row the sums hold, add it to the digest, clear the sums.
: _PIC-FLUSH  ( -- ok? )
    _PIC.OY _PIC@ _PIC-OUT-ROW _PL-D !  _PIC.SUMS _PIC@ _PL-E !
    _PIC.OW _PIC@ 0 ?DO
        _PL-E @ 24 + @ _PL-A !
        _PL-A @ IF
            _PL-E @ @        _PL-A @ _PIC-ROUND/ _PL-D @ C!
            _PL-E @ 8 + @    _PL-A @ _PIC-ROUND/ _PL-D @ 1+ C!
            _PL-E @ 16 + @   _PL-A @ _PIC-ROUND/ _PL-D @ 2 + C!
        ELSE
            0 _PL-D @ C!  0 _PL-D @ 1+ C!  0 _PL-D @ 2 + C!
        THEN
        _PL-A @ _PL-E @ 32 + @ _PIC-ROUND/ _PL-D @ 3 + C!
        4 _PL-D +!  _PIC-SUM-BYTES _PL-E +!
    LOOP
    _PIC.SUMS _PIC@ _PIC.OW _PIC@ _PIC-SUM-BYTES * 0 FILL
    _PIC.OY _PIC@ _PIC-OUT-ROW _PIC.OW _PIC@ 4 * _PIC-HASH ;

\ Use the source row the decoder finished.
: _PIC-USE-ROW  ( -- ok? )
    _PIC-SCALING? 0= IF
        \ The same size: the source row is a row of the copy.
        _PIC.ROW _PIC@ _PIC.Y _PIC@ _PIC-OUT-ROW _PIC.SW _PIC@ 4 * MOVE
        _PIC.Y _PIC@ _PIC-OUT-ROW _PIC.SW _PIC@ 4 * _PIC-HASH
    ELSE
        _PIC.Y _PIC@ _PIC.OH _PIC@ * _PIC.SH _PIC@ /       ( oy )
        DUP _PIC.OY _PIC@ <> IF
            _PIC.OY _PIC@ 0< 0= IF
                _PIC-FLUSH 0= IF DROP 0 EXIT THEN
            THEN
            _PIC.OY _PIC!
        ELSE DROP THEN
        _PIC-ADD-ROW -1
    THEN
    1 _PIC.Y _PIC@ + _PIC.Y _PIC! ;

: _PIC-FINISH  ( -- state )
    _PIC-SCALING? IF _PIC-FLUSH 0= IF PIC-R-INVALID _PIC-FAIL EXIT THEN THEN
    _PIC-P @ _PIC.DIGEST + _PIC-P @ _PIC.HASH + SHA3-256-CONTEXT-FINAL IF
        PIC-R-INVALID _PIC-FAIL EXIT
    THEN
    _PIC-GIVE-WORK
    PIC-ST-READY DUP _PIC.STATE _PIC! ;

\ =====================================================================
\  Steps
\ =====================================================================

VARIABLE _PST-BUDGET

\ Read the next chunk of the file once the last is used.
: _PIC-REFILL  ( -- reason )
    _PIC.IN-P _PIC@ _PIC.IN-U _PIC@ < IF PIC-R-NONE EXIT THEN
    _PIC-SOURCE MEDSRC-SIZE@ _PIC.OFFSET _PIC@ -          ( left )
    DUP 0= IF DROP PIC-R-DAMAGED EXIT THEN                 \ the file is short
    _PIC-IN-BYTES MIN
    _PIC.IN _PIC@ OVER _PIC.OFFSET _PIC@ _PIC-SOURCE MEDSRC-READ? IF
        DROP PIC-R-READ EXIT
    THEN
    DUP _PIC.IN-U _PIC!  _PIC.OFFSET _PIC@ + _PIC.OFFSET _PIC!
    0 _PIC.IN-P _PIC!  PIC-R-NONE ;

\ PIC-STEP ( budget pic -- state )
\   Decode about BUDGET source pixels, at least one row, and return the
\   state: PENDING while there is more, READY when the copy is complete,
\   FAILED with PIC-REASON@ saying why.
: PIC-STEP  ( budget pic -- state )
    DUP _PIC-P !
    _PIC.STATE + @ DUP PIC-ST-PENDING <> IF NIP EXIT THEN DROP
    _PST-BUDGET !
    BEGIN
        _PIC-REFILL ?DUP IF _PIC-FAIL EXIT THEN
        _PIC.IN _PIC@ _PIC.IN-P _PIC@ +
        _PIC.IN-U _PIC@ _PIC.IN-P _PIC@ -
        _PIC.ROW _PIC@ _PIC-P @ _PIC.DEC + QOI-DEC-FEED      ( used status )
        SWAP _PIC.IN-P _PIC@ + _PIC.IN-P _PIC!
        CASE
            QOI-S-ROW OF
                _PIC-USE-ROW 0= IF PIC-R-INVALID _PIC-FAIL EXIT THEN
                _PIC.SW _PIC@ NEGATE _PST-BUDGET +!
                _PST-BUDGET @ 1 < IF PIC-ST-PENDING EXIT THEN
            ENDOF
            QOI-S-DONE OF _PIC-FINISH EXIT ENDOF
            QOI-S-BAD OF PIC-R-DAMAGED _PIC-FAIL EXIT ENDOF
        ENDCASE
    AGAIN ;

\ =====================================================================
\  Results
\ =====================================================================

: _PIC-LIVE?  ( pic -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    _PIC.MAGIC + @ _PIC-MAGIC = ;

: PIC-STATE@  ( pic -- state )
    DUP _PIC-LIVE? 0= IF DROP PIC-ST-EMPTY EXIT THEN _PIC.STATE + @ ;
: PIC-REASON@  ( pic -- reason )
    DUP _PIC-LIVE? 0= IF DROP PIC-R-NONE EXIT THEN _PIC.REASON + @ ;
: PIC-WIDTH@          ( pic -- w )  _PIC.OW + @ ;
: PIC-HEIGHT@         ( pic -- h )  _PIC.OH + @ ;
: PIC-SOURCE-WIDTH@   ( pic -- w )  _PIC.SW + @ ;
: PIC-SOURCE-HEIGHT@  ( pic -- h )  _PIC.SH + @ ;

: PIC-PIXELS  ( pic -- a u )
    DUP PIC-STATE@ PIC-ST-READY <> IF DROP 0 0 EXIT THEN
    DUP _PIC.OUT + @ SWAP DUP PIC-WIDTH@ SWAP PIC-HEIGHT@ * 4 * ;

: PIC-DIGEST  ( pic -- a )
    DUP PIC-STATE@ PIC-ST-READY <> IF DROP 0 EXIT THEN _PIC.DIGEST + ;

\ PIC-FREE ( pic -- )
\   Give back everything the copy holds.  The record is empty afterwards.
: PIC-FREE  ( pic -- )
    DUP _PIC-LIVE? 0= IF DROP EXIT THEN
    _PIC-P !
    _PIC-GIVE-WORK
    _PIC.OW _PIC@ _PIC.OH _PIC@ * 4 * _PIC.OUT _PIC-GIVE
    0 _PIC.MAGIC _PIC!  PIC-ST-EMPTY _PIC.STATE _PIC! ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _pic-guard

' PIC-FIT    CONSTANT _pic-fit-xt
' PIC-START  CONSTANT _pic-start-xt
' PIC-STEP   CONSTANT _pic-step-xt
' PIC-FREE   CONSTANT _pic-free-xt

: PIC-FIT    _pic-fit-xt _pic-guard WITH-GUARD ;
: PIC-START  _pic-start-xt _pic-guard WITH-GUARD ;
: PIC-STEP   _pic-step-xt _pic-guard WITH-GUARD ;
: PIC-FREE   _pic-free-xt _pic-guard WITH-GUARD ;
[THEN] [THEN]
