\ =====================================================================
\  uidl-picture-snapshot.f -- UIDL picture snapshot
\ =====================================================================
\
\  One coherent UIDL-TUI observation describes the pictures this document's
\  <media> elements show, one pointer-free descriptor a picture, in
\  increasing source index.  Capturing also asks each picture for a rich
\  copy of the pixels its rectangle covers on the terminal, from the pixel
\  size the caller gives for the whole surface, so the rich side never holds
\  more pixels than the screen shows.  A ready copy is described by its
\  format and size; UPICSN-PULL copies its bytes later, if the picture still
\  shows that copy.  Each descriptor also names the picture's revision,
\  which every copy of that picture shares, and UPICSN-SHOWS? says whether
\  the element still shows that picture.
\
\  Only pictures whose clip is their whole rectangle are described: a
\  picture partly hidden stays CELL.  Capture holds nothing between calls,
\  so the caller captures afresh whenever the pixel size or the document
\  may have changed.
\
\  UPICSN-CAPTURE ( descriptors-a descriptors-u ask -- count status )
\  UPICSN-PULL ( descriptor dest-a dest-u -- status )
\  UPICSN-SHOWS? ( source-index revision -- status )
\
\  Prefix: UPICSN- (public), _UPICSN- (private).

PROVIDED akashic-tui-uidl-picture-snapshot

REQUIRE uidl-tui.f
REQUIRE ../utils/memory-span.f

0 CONSTANT UPICSN-S-OK
1 CONSTANT UPICSN-S-CAPACITY
2 CONSTANT UPICSN-S-UNAVAILABLE
3 CONSTANT UPICSN-S-INVALID
\ A pull found the picture no longer showing the copy described.
4 CONSTANT UPICSN-S-STALE

: UPICSN-STATUS-VALID?  ( status -- flag )  5 U< ;

1 CONSTANT UPICSN-SOURCE-UIDL

\ Where a picture's rich copy stands.  NONE: nothing was asked, because the
\ caller gave no pixel size.  REFUSED: the widget's memory refused the copy.
0 CONSTANT UPICSN-C-NONE
1 CONSTANT UPICSN-C-PENDING
2 CONSTANT UPICSN-C-READY
3 CONSTANT UPICSN-C-FAILED
4 CONSTANT UPICSN-C-REFUSED

\ Descriptor fields are native cells and contain no pointer.
\
\   +0   source kind
\   +8   UIDL pool source index
\   +16  source generation (always zero)
\   +24  relation root key (always one)
\   +32  row on the screen
\   +40  column
\   +48  height in cells
\   +56  width in cells
\   +64  resolved UIDL paint z
\   +72  copy state, UPICSN-C-*
\   +80  why a FAILED copy failed, PIC-R-*
\   +88  copy width in pixels
\   +96  copy height
\   +104 copy bytes, width * height * 4
\   +112 width asked for
\   +120 height asked for
\   +128 the copy's format, PIC-F-*
\   +136 the caller's document key: capture writes 0, and a caller that
\        describes several documents into one bank records which is which
\   +144 the picture's revision, shared by every copy of it

: _UPICSN-D.SOURCE      ( descriptor -- address )       ;
: _UPICSN-D.INDEX       ( descriptor -- address )   8 + ;
: _UPICSN-D.GENERATION  ( descriptor -- address )  16 + ;
: _UPICSN-D.ROOT-KEY    ( descriptor -- address )  24 + ;
: _UPICSN-D.ROW         ( descriptor -- address )  32 + ;
: _UPICSN-D.COLUMN      ( descriptor -- address )  40 + ;
: _UPICSN-D.HEIGHT      ( descriptor -- address )  48 + ;
: _UPICSN-D.WIDTH       ( descriptor -- address )  56 + ;
: _UPICSN-D.Z           ( descriptor -- address )  64 + ;
: _UPICSN-D.STATE       ( descriptor -- address )  72 + ;
: _UPICSN-D.REASON      ( descriptor -- address )  80 + ;
: _UPICSN-D.COPY-W      ( descriptor -- address )  88 + ;
: _UPICSN-D.COPY-H      ( descriptor -- address )  96 + ;
: _UPICSN-D.COPY-U      ( descriptor -- address ) 104 + ;
: _UPICSN-D.ASK-W       ( descriptor -- address ) 112 + ;
: _UPICSN-D.ASK-H       ( descriptor -- address ) 120 + ;
: _UPICSN-D.FORMAT      ( descriptor -- address ) 128 + ;
: _UPICSN-D.DOCUMENT    ( descriptor -- address ) 136 + ;
: _UPICSN-D.REVISION    ( descriptor -- address ) 144 + ;

152 CONSTANT UPICSN-DESCRIPTOR-SIZE

: UPICSN-DESCRIPTOR-BYTES  ( -- bytes )  UPICSN-DESCRIPTOR-SIZE ;
: UPICSN-SOURCE-INDEX@  ( descriptor -- index )  _UPICSN-D.INDEX @ ;
: UPICSN-ROW@     ( descriptor -- row )     _UPICSN-D.ROW @ ;
: UPICSN-COLUMN@  ( descriptor -- column )  _UPICSN-D.COLUMN @ ;
: UPICSN-HEIGHT@  ( descriptor -- rows )    _UPICSN-D.HEIGHT @ ;
: UPICSN-WIDTH@   ( descriptor -- cols )    _UPICSN-D.WIDTH @ ;
: UPICSN-Z@       ( descriptor -- z )       _UPICSN-D.Z @ ;
: UPICSN-STATE@   ( descriptor -- state )   _UPICSN-D.STATE @ ;
: UPICSN-REASON@  ( descriptor -- reason )  _UPICSN-D.REASON @ ;
: UPICSN-COPY-WIDTH@   ( descriptor -- pixels )  _UPICSN-D.COPY-W @ ;
: UPICSN-COPY-HEIGHT@  ( descriptor -- pixels )  _UPICSN-D.COPY-H @ ;
: UPICSN-COPY-BYTES@   ( descriptor -- bytes )   _UPICSN-D.COPY-U @ ;
: UPICSN-ASK-WIDTH@    ( descriptor -- pixels )  _UPICSN-D.ASK-W @ ;
: UPICSN-ASK-HEIGHT@   ( descriptor -- pixels )  _UPICSN-D.ASK-H @ ;
: UPICSN-FORMAT@  ( descriptor -- format )  _UPICSN-D.FORMAT @ ;
: UPICSN-DOCUMENT@  ( descriptor -- key )  _UPICSN-D.DOCUMENT @ ;
: UPICSN-DOCUMENT!  ( key descriptor -- )  _UPICSN-D.DOCUMENT ! ;
: UPICSN-REVISION@  ( descriptor -- revision )  _UPICSN-D.REVISION @ ;

\ =====================================================================
\  The pixels a rectangle covers
\ =====================================================================

\ What a capture asks for, in the caller's record of native cells: the
\ pixels the whole SURFACE-COLS by SURFACE-ROWS surface covers, zero when
\ unknown, and the most pixels across and down and the most bytes one copy
\ may have, each zero for no limit.
: UPICSN-ASK.SURFACE-COLS  ( ask -- a )       ;
: UPICSN-ASK.SURFACE-ROWS  ( ask -- a )   8 + ;
: UPICSN-ASK.PIXEL-W       ( ask -- a )  16 + ;
: UPICSN-ASK.PIXEL-H       ( ask -- a )  24 + ;
: UPICSN-ASK.MAX-W         ( ask -- a )  32 + ;
: UPICSN-ASK.MAX-H         ( ask -- a )  40 + ;
: UPICSN-ASK.BUDGET        ( ask -- a )  48 + ;
56 CONSTANT UPICSN-ASK-SIZE

VARIABLE _UPICSN-B-W
VARIABLE _UPICSN-B-H
VARIABLE _UPICSN-B-BUDGET
VARIABLE _UPICSN-B-LO
VARIABLE _UPICSN-B-HI

\ The width W' <= W whose height, in W:H's shape, keeps W'*H'*4 within
\ BUDGET: the largest such, by bisection.  0 when even one pixel is over.
: _UPICSN-B-HEIGHT  ( w' -- h' )
    _UPICSN-B-H @ * _UPICSN-B-W @ / 1 MAX ;
: _UPICSN-B-FITS?  ( w' -- flag )
    DUP _UPICSN-B-HEIGHT * 4 * _UPICSN-B-BUDGET @ U> 0= ;
: _UPICSN-BUDGET-FIT  ( w h budget -- w' h' )
    _UPICSN-B-BUDGET ! _UPICSN-B-H ! _UPICSN-B-W !
    _UPICSN-B-W @ _UPICSN-B-FITS? IF _UPICSN-B-W @ _UPICSN-B-H @ EXIT THEN
    1 _UPICSN-B-FITS? 0= IF 0 0 EXIT THEN
    1 _UPICSN-B-LO ! _UPICSN-B-W @ _UPICSN-B-HI !
    BEGIN _UPICSN-B-HI @ _UPICSN-B-LO @ - 1 > WHILE
        _UPICSN-B-LO @ _UPICSN-B-HI @ + 2/
        DUP _UPICSN-B-FITS? IF _UPICSN-B-LO ! ELSE _UPICSN-B-HI ! THEN
    REPEAT
    _UPICSN-B-LO @ DUP _UPICSN-B-HEIGHT ;

\ No surface is wider or taller than 2^30 - 1 pixels: that keeps every
\ product below in a signed cell.  A larger answer is taken as unknown.
1073741823 CONSTANT _UPICSN-MOST-PIXELS

\ A at most LIMIT, unless LIMIT is 0, with B scaled to keep A:B.
: _UPICSN-LIMIT  ( a b limit -- a' b' )
    DUP 0= IF DROP EXIT THEN
    2 PICK OVER U> 0= IF DROP EXIT THEN
    DUP >R * SWAP / 1 MAX R> SWAP ;

\ UPICSN-BOUND ( cols rows ask -- max-w max-h )
\   The most pixels a COLS by ROWS rectangle, no larger than the surface,
\   covers when the whole surface covers the pixels ASK gives, at least one
\   each way, kept within ASK's limits on one copy by shrinking it in its
\   own shape.  0 0 when the size is unknown or the budget holds no pixel.
VARIABLE _UPICSN-BD-ASK
: UPICSN-BOUND  ( cols rows ask -- max-w max-h )
    _UPICSN-BD-ASK !
    _UPICSN-BD-ASK @ UPICSN-ASK.PIXEL-W @ DUP 0= SWAP _UPICSN-MOST-PIXELS U> OR
    _UPICSN-BD-ASK @ UPICSN-ASK.PIXEL-H @ DUP 0= SWAP _UPICSN-MOST-PIXELS U> OR OR
    _UPICSN-BD-ASK @ UPICSN-ASK.SURFACE-COLS @ 0= OR
    _UPICSN-BD-ASK @ UPICSN-ASK.SURFACE-ROWS @ 0= OR IF 2DROP 0 0 EXIT THEN
    SWAP _UPICSN-BD-ASK @ UPICSN-ASK.PIXEL-W @ *
        _UPICSN-BD-ASK @ UPICSN-ASK.SURFACE-COLS @ / 1 MAX
    SWAP _UPICSN-BD-ASK @ UPICSN-ASK.PIXEL-H @ *
        _UPICSN-BD-ASK @ UPICSN-ASK.SURFACE-ROWS @ / 1 MAX
    _UPICSN-BD-ASK @ UPICSN-ASK.MAX-W @ _UPICSN-LIMIT
    SWAP _UPICSN-BD-ASK @ UPICSN-ASK.MAX-H @ _UPICSN-LIMIT SWAP
    _UPICSN-BD-ASK @ UPICSN-ASK.BUDGET @ ?DUP IF _UPICSN-BUDGET-FIT THEN ;

\ =====================================================================
\  Capture
\ =====================================================================

CREATE _UPICSN-OWNED-START

VARIABLE _UPICSN-DESCRIPTORS-A
VARIABLE _UPICSN-DESCRIPTORS-U
VARIABLE _UPICSN-CAP
VARIABLE _UPICSN-COUNT
VARIABLE _UPICSN-STATUS
\ The caller's ask, copied for the capture.
CREATE _UPICSN-ASK-S UPICSN-ASK-SIZE 7 + ALLOT
: _UPICSN-ASK  ( -- ask )  _UPICSN-ASK-S 7 + -8 AND ;
VARIABLE _UPICSN-PRIOR
VARIABLE _UPICSN-HAVE-PRIOR

VARIABLE _UPICSN-V-INDEX
VARIABLE _UPICSN-V-RESOLVED-A
VARIABLE _UPICSN-V-D
VARIABLE _UPICSN-V-ROW
VARIABLE _UPICSN-V-COL
VARIABLE _UPICSN-V-H
VARIABLE _UPICSN-V-W
VARIABLE _UPICSN-V-PIC

: _UPICSN-UMIN  ( a b -- min )  2DUP U< IF DROP ELSE NIP THEN ;

: _UPICSN-SET  ( status -- )
    _UPICSN-STATUS @ UPICSN-S-OK = IF _UPICSN-STATUS ! ELSE DROP THEN ;

\ The picture's whole rectangle, when nothing clips it.
: _UPICSN-V-GEOMETRY?  ( -- flag )
    _UTUI-PICTURE-GEOMETRY 0= IF 2DROP 2DROP 2DROP 2DROP 0 EXIT THEN
    ( origin-row origin-col extent-h extent-w clip-row clip-col clip-h clip-w )
    >R >R >R >R
    _UPICSN-V-W ! _UPICSN-V-H ! _UPICSN-V-COL ! _UPICSN-V-ROW !
    R> _UPICSN-V-ROW @ = R> _UPICSN-V-COL @ = AND
    R> _UPICSN-V-H @ = AND R> _UPICSN-V-W @ = AND
    _UPICSN-V-H @ 0> AND _UPICSN-V-W @ 0> AND
    _UPICSN-V-ROW @ 0< 0= AND _UPICSN-V-COL @ 0< 0= AND ;

: _UPICSN-V-COPY  ( -- )
    _UPICSN-V-W @ _UPICSN-V-H @ _UPICSN-ASK UPICSN-BOUND
    2DUP _UPICSN-V-D @ _UPICSN-D.ASK-H ! _UPICSN-V-D @ _UPICSN-D.ASK-W !
    OVER 0= IF 2DROP UPICSN-C-NONE _UPICSN-V-D @ _UPICSN-D.STATE ! EXIT THEN
    _UTUI-PICTURE-ASK 0= IF
        UPICSN-C-REFUSED _UPICSN-V-D @ _UPICSN-D.STATE ! EXIT
    THEN
    _UTUI-PICTURE-COPY@ DUP _UPICSN-V-PIC ! 0= IF
        UPICSN-C-REFUSED _UPICSN-V-D @ _UPICSN-D.STATE ! EXIT
    THEN
    _UPICSN-V-PIC @ PIC-STATE@
    DUP PIC-ST-PENDING = IF
        DROP UPICSN-C-PENDING _UPICSN-V-D @ _UPICSN-D.STATE ! EXIT
    THEN
    PIC-ST-READY <> IF
        UPICSN-C-FAILED _UPICSN-V-D @ _UPICSN-D.STATE !
        _UPICSN-V-PIC @ PIC-REASON@ _UPICSN-V-D @ _UPICSN-D.REASON ! EXIT
    THEN
    UPICSN-C-READY _UPICSN-V-D @ _UPICSN-D.STATE !
    _UPICSN-V-PIC @ PIC-WIDTH@ _UPICSN-V-D @ _UPICSN-D.COPY-W !
    _UPICSN-V-PIC @ PIC-HEIGHT@ _UPICSN-V-D @ _UPICSN-D.COPY-H !
    _UPICSN-V-PIC @ PIC-PIXELS NIP _UPICSN-V-D @ _UPICSN-D.COPY-U !
    PIC-F-RGBA8 _UPICSN-V-D @ _UPICSN-D.FORMAT ! ;

: _UPICSN-VISITOR
    ( source-index source-generation root-key resolved-a resolved-u -- )
    DROP _UPICSN-V-RESOLVED-A ! 2DROP _UPICSN-V-INDEX !
    0 _UPICSN-V-PIC !
    _UPICSN-STATUS @ DUP UPICSN-S-OK <> SWAP UPICSN-S-CAPACITY <> AND IF
        EXIT
    THEN
    _UPICSN-HAVE-PRIOR @ IF
        _UPICSN-PRIOR @ _UPICSN-V-INDEX @ U< 0= IF
            UPICSN-S-INVALID _UPICSN-STATUS ! EXIT
        THEN
    THEN
    _UPICSN-V-INDEX @ _UPICSN-PRIOR ! -1 _UPICSN-HAVE-PRIOR !
    _UPICSN-STATUS @ UPICSN-S-CAPACITY = IF
        _UPICSN-V-GEOMETRY? IF 1 _UPICSN-COUNT +! THEN EXIT
    THEN
    _UPICSN-V-GEOMETRY? 0= IF EXIT THEN
    \ A full bank keeps counting, so CAPACITY says how many it would take.
    _UPICSN-COUNT @ _UPICSN-CAP @ U< 0= IF
        UPICSN-S-CAPACITY _UPICSN-SET 1 _UPICSN-COUNT +! EXIT
    THEN
    _UPICSN-COUNT @ UPICSN-DESCRIPTOR-SIZE * _UPICSN-DESCRIPTORS-A @ +
        DUP _UPICSN-V-D ! UPICSN-DESCRIPTOR-SIZE 0 FILL
    UPICSN-SOURCE-UIDL _UPICSN-V-D @ _UPICSN-D.SOURCE !
    _UPICSN-V-INDEX @ _UPICSN-V-D @ _UPICSN-D.INDEX !
    1 _UPICSN-V-D @ _UPICSN-D.ROOT-KEY !
    _UPICSN-V-ROW @ _UPICSN-V-D @ _UPICSN-D.ROW !
    _UPICSN-V-COL @ _UPICSN-V-D @ _UPICSN-D.COLUMN !
    _UPICSN-V-H @ _UPICSN-V-D @ _UPICSN-D.HEIGHT !
    _UPICSN-V-W @ _UPICSN-V-D @ _UPICSN-D.WIDTH !
    _UPICSN-V-RESOLVED-A @ 64 + @ _UPICSN-V-D @ _UPICSN-D.Z !
    _UTUI-PICTURE-REVISION@ _UPICSN-V-D @ _UPICSN-D.REVISION !
    _UPICSN-V-COPY
    0 _UPICSN-V-PIC !
    1 _UPICSN-COUNT +! ;

: _UPICSN-MAP  ( mc-status -- )
    DUP _UTUI-MC-S-OK = IF DROP EXIT THEN
    _UTUI-MC-S-UNAVAILABLE = IF UPICSN-S-UNAVAILABLE ELSE UPICSN-S-INVALID THEN
    _UPICSN-SET ;

: _UPICSN-CAPTURE-BODY  ( -- count status )
    \ No descriptor may land in the document's own storage.
    _UPICSN-DESCRIPTORS-U @ IF
        _UPICSN-DESCRIPTORS-A @ _UPICSN-DESCRIPTORS-U @
            _UTUI-STORAGE-DISJOINT-BODY? 0= IF 0 UPICSN-S-INVALID EXIT THEN
    THEN
    ['] _UPICSN-VISITOR _UTUI-PICTURE-EACH-PREFLIGHTED _UPICSN-MAP
    _UPICSN-STATUS @ UPICSN-S-OK <> IF
        _UPICSN-DESCRIPTORS-A @
            _UPICSN-COUNT @ _UPICSN-CAP @ _UPICSN-UMIN UPICSN-DESCRIPTOR-SIZE *
            0 FILL
        _UPICSN-STATUS @ UPICSN-S-CAPACITY = IF
            _UPICSN-COUNT @ ELSE 0 THEN
        _UPICSN-STATUS @ EXIT
    THEN
    _UPICSN-COUNT @ UPICSN-S-OK ;

: _UPICSN-CAPTURE-CALL  ( -- count status )
    ['] _UPICSN-CAPTURE-BODY UTUI-RESOLVED-OBSERVE ;

: _UPICSN-SCRUB  ( -- )
    0 _UPICSN-DESCRIPTORS-A ! 0 _UPICSN-DESCRIPTORS-U ! 0 _UPICSN-CAP !
    0 _UPICSN-COUNT ! 0 _UPICSN-STATUS !
    _UPICSN-ASK UPICSN-ASK-SIZE 0 FILL
    0 _UPICSN-PRIOR ! 0 _UPICSN-HAVE-PRIOR !
    0 _UPICSN-V-INDEX ! 0 _UPICSN-V-RESOLVED-A ! 0 _UPICSN-V-D !
    0 _UPICSN-V-ROW ! 0 _UPICSN-V-COL ! 0 _UPICSN-V-H ! 0 _UPICSN-V-W !
    0 _UPICSN-V-PIC ! ;

CREATE _UPICSN-OWNED-END

: _UPICSN-BANK?  ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    DUP UPICSN-DESCRIPTOR-SIZE MOD IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _UPICSN-OWNED-START _UPICSN-OWNED-END _UPICSN-OWNED-START -
        MSPAN-OVERLAP? 0= ;

\ UPICSN-CAPTURE ( descriptors-a descriptors-u ask -- count status )
\   Describe every picture shown into the caller's descriptor bank, asking
\   each for a rich copy of at most the pixels UPICSN-BOUND gives its
\   rectangle under ASK.  An unknown pixel size asks for nothing.
\   CAPACITY, with how many descriptors it would take, when the bank holds
\   too few; then nothing is described.
: UPICSN-CAPTURE  ( descriptors-a descriptors-u ask -- count status )
    _UPICSN-ASK UPICSN-ASK-SIZE MOVE
    2DUP _UPICSN-BANK? 0= IF 2DROP 0 UPICSN-S-INVALID _UPICSN-SCRUB EXIT THEN
    DUP UPICSN-DESCRIPTOR-SIZE / _UPICSN-CAP !
    _UPICSN-DESCRIPTORS-U ! _UPICSN-DESCRIPTORS-A !
    0 _UPICSN-COUNT ! UPICSN-S-OK _UPICSN-STATUS ! 0 _UPICSN-HAVE-PRIOR !
    ['] _UPICSN-CAPTURE-CALL CATCH ?DUP IF
        DROP 0 UPICSN-S-INVALID
    THEN
    _UPICSN-SCRUB ;

\ The pull writes only outside the document's own storage.
: _UPICSN-PULL-OBSERVED
  ( index revision width height dest-a dest-u -- status )
    2DUP _UTUI-STORAGE-DISJOINT-BODY? 0= IF
        2DROP 2DROP 2DROP UPICSN-S-INVALID EXIT
    THEN
    _UTUI-PICTURE-PULL IF UPICSN-S-OK ELSE UPICSN-S-STALE THEN ;

\ UPICSN-PULL ( descriptor dest-a dest-u -- status )
\   Copy the described picture's rich copy into DEST, DEST-U bytes, which
\   must be the copy's.  STALE, with nothing written, when the picture no
\   longer shows that copy: another picture, or a copy of another size.
: UPICSN-PULL  ( descriptor dest-a dest-u -- status )
    2 PICK UPICSN-STATE@ UPICSN-C-READY <> IF 2DROP DROP UPICSN-S-INVALID EXIT THEN
    DUP 3 PICK UPICSN-COPY-BYTES@ <> IF 2DROP DROP UPICSN-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP DROP UPICSN-S-INVALID EXIT THEN
    2DUP _UPICSN-OWNED-START _UPICSN-OWNED-END _UPICSN-OWNED-START -
        MSPAN-OVERLAP? IF 2DROP DROP UPICSN-S-INVALID EXIT THEN
    >R >R >R
    R@ UPICSN-SOURCE-INDEX@ R@ UPICSN-REVISION@
    R@ UPICSN-COPY-WIDTH@ R> UPICSN-COPY-HEIGHT@
    R> R>
    ['] _UPICSN-PULL-OBSERVED UTUI-RESOLVED-OBSERVE ;

: _UPICSN-SHOWS-OBSERVED  ( index revision -- status )
    _UTUI-PICTURE-SHOWS? IF UPICSN-S-OK ELSE UPICSN-S-STALE THEN ;

\ UPICSN-SHOWS? ( source-index revision -- status )
\   OK while the picture at SOURCE-INDEX is still picture REVISION, the
\   one a descriptor described, whatever copy of it it has now; STALE once
\   it is another picture or none.
: UPICSN-SHOWS?  ( source-index revision -- status )
    ['] _UPICSN-SHOWS-OBSERVED UTUI-RESOLVED-OBSERVE ;
