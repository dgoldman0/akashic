\ =====================================================================
\  uidl-picture-snapshot.f -- UIDL picture snapshot
\ =====================================================================
\
\  One coherent UIDL-TUI observation describes the pictures this document's
\  <media> elements show, one pointer-free descriptor a picture, in
\  increasing source index and root key: an element's own picture, with
\  root key one, or each figure with a row in view in the document it
\  shows, with its block's key.  A picture whose file the terminal decodes is
\  described as that file, at the picture's own size, ready at once: no
\  copy is made and no pixel size is needed.  Any other picture is asked
\  for a rich copy of the pixels its rectangle covers on the terminal, from
\  the pixel size the caller gives for the whole surface, so the rich side
\  never holds more pixels than the screen shows.  A ready file or copy is
\  described by its format and size; UPICSN-PULL copies a span of its
\  bytes later, if the picture still shows that file or copy, so a caller
\  can send it a chunk at a time.  Each descriptor also names the picture's
\  revision, which every copy of that picture shares.  When the rich side
\  cannot send a picture because of the picture itself, UPICSN-FAIL has its
\  widget remember why, and it is described as failed, asking for nothing,
\  until the widget is given another source.
\
\  When the caller says the rich side takes the pictures it describes, a
\  picture going as its file, or as a copy ready or being made, is claimed,
\  so its CELL view shows what it is and decodes nothing; any other picture
\  visited is not.  A capture also tells picture widgets which file formats
\  the rich side takes, so a new picture of one of them shows what it is
\  from its first draw.  UPICSN-RELEASE-ALL lets every claim go at once,
\  when the rich side shows no picture or can take none.
\
\  A picture is described by its whole rectangle and the part of it shown,
\  its clip, so one partly hidden, such as a figure partly scrolled out of
\  its document, shows only that part, at its whole size.  A figure lies in
\  its document's rectangle, which the document's root claims.  Capture
\  holds nothing between calls, so the caller captures afresh whenever the
\  pixel size or the document may have changed.
\
\  UPICSN-CAPTURE ( descriptors-a descriptors-u ask -- count status )
\  UPICSN-PULL ( descriptor offset dest-a dest-u -- status )
\  UPICSN-FAIL ( source-index root-key revision reason -- status )
\  UPICSN-RELEASE-ALL ( -- )
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
\   +24  relation root key: one for an element's own picture, a figure's
\        block key
\   +32  row on the screen of the whole rectangle, which may lie above it
\   +40  column
\   +48  height in cells
\   +56  width in cells
\   +64  resolved UIDL paint z
\   +72  copy state, UPICSN-C-*
\   +80  why a FAILED copy failed, PIC-R-*
\   +88  copy width in pixels
\   +96  copy height
\   +104 copy bytes: width * height * 4, or the file's length
\   +112 width asked for
\   +120 height asked for
\   +128 the copy's format, PIC-F-*: PIC-F-RGBA8 for a copy the widget
\        makes, also while it is not ready, or the file's format
\   +136 the caller's document key: capture writes 0, and a caller that
\        describes several documents into one bank records which is which
\   +144 the picture's revision, shared by every copy of it
\   +152 the clip's row, in cells from the rectangle's top: the part shown
\   +160 its column, from the rectangle's left
\   +168 its height, at least one
\   +176 its width, at least one
\   +184 nonzero for a figure, which its document's root claims

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
: _UPICSN-D.CLIP-ROW    ( descriptor -- address ) 152 + ;
: _UPICSN-D.CLIP-COL    ( descriptor -- address ) 160 + ;
: _UPICSN-D.CLIP-H      ( descriptor -- address ) 168 + ;
: _UPICSN-D.CLIP-W      ( descriptor -- address ) 176 + ;
: _UPICSN-D.FIGURE      ( descriptor -- address ) 184 + ;

192 CONSTANT UPICSN-DESCRIPTOR-SIZE

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
: UPICSN-ROOT-KEY@  ( descriptor -- key )  _UPICSN-D.ROOT-KEY @ ;
: UPICSN-CLIP-ROW@     ( descriptor -- rows )  _UPICSN-D.CLIP-ROW @ ;
: UPICSN-CLIP-COLUMN@  ( descriptor -- cols )  _UPICSN-D.CLIP-COL @ ;
: UPICSN-CLIP-HEIGHT@  ( descriptor -- rows )  _UPICSN-D.CLIP-H @ ;
: UPICSN-CLIP-WIDTH@   ( descriptor -- cols )  _UPICSN-D.CLIP-W @ ;
: UPICSN-FIGURE?  ( descriptor -- flag )  _UPICSN-D.FIGURE @ 0<> ;

\ =====================================================================
\  The pixels a rectangle covers
\ =====================================================================

\ What a capture asks for, in the caller's record of native cells: the
\ pixels the whole SURFACE-COLS by SURFACE-ROWS surface covers, zero when
\ unknown; the most pixels across and down and the most bytes, as decoded,
\ one picture may have, each zero for no limit; the picture files the
\ terminal decodes, PIC-F- format N at bit N-1; and whether the rich side
\ takes the pictures it is given, nonzero when it does.
: UPICSN-ASK.SURFACE-COLS  ( ask -- a )       ;
: UPICSN-ASK.SURFACE-ROWS  ( ask -- a )   8 + ;
: UPICSN-ASK.PIXEL-W       ( ask -- a )  16 + ;
: UPICSN-ASK.PIXEL-H       ( ask -- a )  24 + ;
: UPICSN-ASK.MAX-W         ( ask -- a )  32 + ;
: UPICSN-ASK.MAX-H         ( ask -- a )  40 + ;
: UPICSN-ASK.BUDGET        ( ask -- a )  48 + ;
: UPICSN-ASK.FORMATS       ( ask -- a )  56 + ;
: UPICSN-ASK.CLAIM         ( ask -- a )  64 + ;
72 CONSTANT UPICSN-ASK-SIZE

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
VARIABLE _UPICSN-PRIOR-KEY
VARIABLE _UPICSN-HAVE-PRIOR

VARIABLE _UPICSN-V-INDEX
VARIABLE _UPICSN-V-KEY
VARIABLE _UPICSN-V-RESOLVED-A
VARIABLE _UPICSN-V-D
VARIABLE _UPICSN-V-ROW
VARIABLE _UPICSN-V-COL
VARIABLE _UPICSN-V-H
VARIABLE _UPICSN-V-W
VARIABLE _UPICSN-V-CLIP-ROW
VARIABLE _UPICSN-V-CLIP-COL
VARIABLE _UPICSN-V-CLIP-H
VARIABLE _UPICSN-V-CLIP-W
VARIABLE _UPICSN-V-PIC

: _UPICSN-UMIN  ( a b -- min )  2DUP U< IF DROP ELSE NIP THEN ;

: _UPICSN-SET  ( status -- )
    _UPICSN-STATUS @ UPICSN-S-OK = IF _UPICSN-STATUS ! ELSE DROP THEN ;

\ The picture's whole rectangle and the part of it shown, which must be
\ some of it.
: _UPICSN-V-GEOMETRY?  ( -- flag )
    _UTUI-PICTURE-GEOMETRY 0= IF 2DROP 2DROP 2DROP 2DROP 0 EXIT THEN
    ( origin-row origin-col extent-h extent-w clip-row clip-col clip-h clip-w )
    _UPICSN-V-CLIP-W ! _UPICSN-V-CLIP-H !
    _UPICSN-V-CLIP-COL ! _UPICSN-V-CLIP-ROW !
    _UPICSN-V-W ! _UPICSN-V-H ! _UPICSN-V-COL ! _UPICSN-V-ROW !
    _UPICSN-V-H @ 0> _UPICSN-V-W @ 0> AND
    _UPICSN-V-CLIP-H @ 0> AND _UPICSN-V-CLIP-W @ 0> AND 0= IF 0 EXIT THEN
    _UPICSN-V-ROW @ NEGATE _UPICSN-V-CLIP-ROW +!
    _UPICSN-V-COL @ NEGATE _UPICSN-V-CLIP-COL +!
    _UPICSN-V-CLIP-ROW @ 0< _UPICSN-V-CLIP-COL @ 0< OR IF 0 EXIT THEN
    _UPICSN-V-CLIP-ROW @ _UPICSN-V-CLIP-H @ + _UPICSN-V-H @ > IF 0 EXIT THEN
    _UPICSN-V-CLIP-COL @ _UPICSN-V-CLIP-W @ + _UPICSN-V-W @ > 0= ;

VARIABLE _UPICSN-F-FORMAT
VARIABLE _UPICSN-F-W
VARIABLE _UPICSN-F-H
VARIABLE _UPICSN-F-U

\ A picture file the terminal decodes is described as itself, at the
\ picture's own size, when that is within the ask's limits on one picture.
: _UPICSN-V-FILE?  ( -- flag )
    _UTUI-PICTURE-FILE@
    _UPICSN-F-U ! _UPICSN-F-H ! _UPICSN-F-W ! _UPICSN-F-FORMAT !
    _UPICSN-F-FORMAT @ 1- 4 U< 0= IF 0 EXIT THEN
    _UPICSN-ASK UPICSN-ASK.FORMATS @ _UPICSN-F-FORMAT @ 1- RSHIFT 1 AND 0= IF
        0 EXIT
    THEN
    _UPICSN-F-U @ 0= IF 0 EXIT THEN
    _UPICSN-ASK UPICSN-ASK.MAX-W @ ?DUP IF _UPICSN-F-W @ U< IF 0 EXIT THEN THEN
    _UPICSN-ASK UPICSN-ASK.MAX-H @ ?DUP IF _UPICSN-F-H @ U< IF 0 EXIT THEN THEN
    _UPICSN-ASK UPICSN-ASK.BUDGET @ ?DUP IF
        _UPICSN-F-W @ _UPICSN-F-H @ * 4 * U< IF 0 EXIT THEN
    THEN
    UPICSN-C-READY _UPICSN-V-D @ _UPICSN-D.STATE !
    _UPICSN-F-FORMAT @ _UPICSN-V-D @ _UPICSN-D.FORMAT !
    _UPICSN-F-W @ DUP _UPICSN-V-D @ _UPICSN-D.COPY-W !
        _UPICSN-V-D @ _UPICSN-D.ASK-W !
    _UPICSN-F-H @ DUP _UPICSN-V-D @ _UPICSN-D.COPY-H !
        _UPICSN-V-D @ _UPICSN-D.ASK-H !
    _UPICSN-F-U @ _UPICSN-V-D @ _UPICSN-D.COPY-U !
    -1 ;

: _UPICSN-V-COPY  ( -- )
    PIC-F-RGBA8 _UPICSN-V-D @ _UPICSN-D.FORMAT !
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
    _UPICSN-V-PIC @ PIC-PIXELS NIP _UPICSN-V-D @ _UPICSN-D.COPY-U ! ;

\ A picture the rich side could not send, because of the picture itself,
\ is described as failed for the reason its widget remembers, and asks for
\ nothing.
: _UPICSN-V-FAILED?  ( -- flag )
    _UTUI-PICTURE-FAILED@ ?DUP 0= IF 0 EXIT THEN
    _UPICSN-V-D @ _UPICSN-D.REASON !
    UPICSN-C-FAILED _UPICSN-V-D @ _UPICSN-D.STATE !
    -1 ;

\ The rich side takes a picture it can send, when the caller says it takes
\ pictures: its file, or a copy ready or being made.
: _UPICSN-V-CLAIM  ( -- )
    _UPICSN-ASK UPICSN-ASK.CLAIM @ 0<>
    _UPICSN-V-D @ _UPICSN-D.STATE @
    DUP UPICSN-C-READY = SWAP UPICSN-C-PENDING = OR AND
    _UTUI-PICTURE-CLAIM! ;

\ Pictures come in increasing source index, and within one element in
\ increasing root key.
: _UPICSN-V-AFTER-PRIOR?  ( -- flag )
    _UPICSN-HAVE-PRIOR @ 0= IF -1 EXIT THEN
    _UPICSN-PRIOR @ _UPICSN-V-INDEX @ U< IF -1 EXIT THEN
    _UPICSN-PRIOR @ _UPICSN-V-INDEX @ =
    _UPICSN-PRIOR-KEY @ _UPICSN-V-KEY @ U< AND ;

: _UPICSN-VISITOR
    ( source-index source-generation root-key resolved-a resolved-u -- )
    DROP _UPICSN-V-RESOLVED-A ! _UPICSN-V-KEY ! DROP _UPICSN-V-INDEX !
    0 _UPICSN-V-PIC !
    _UPICSN-STATUS @ DUP UPICSN-S-OK <> SWAP UPICSN-S-CAPACITY <> AND IF
        EXIT
    THEN
    _UPICSN-V-AFTER-PRIOR? 0= IF UPICSN-S-INVALID _UPICSN-STATUS ! EXIT THEN
    _UPICSN-V-INDEX @ _UPICSN-PRIOR ! _UPICSN-V-KEY @ _UPICSN-PRIOR-KEY !
    -1 _UPICSN-HAVE-PRIOR !
    _UPICSN-STATUS @ UPICSN-S-CAPACITY = IF
        _UPICSN-V-GEOMETRY? IF 1 _UPICSN-COUNT +! THEN EXIT
    THEN
    \ A picture with nothing of it shown stays CELL.
    _UPICSN-V-GEOMETRY? 0= IF 0 _UTUI-PICTURE-CLAIM! EXIT THEN
    \ A full bank keeps counting, so CAPACITY says how many it would take.
    _UPICSN-COUNT @ _UPICSN-CAP @ U< 0= IF
        UPICSN-S-CAPACITY _UPICSN-SET 1 _UPICSN-COUNT +! EXIT
    THEN
    _UPICSN-COUNT @ UPICSN-DESCRIPTOR-SIZE * _UPICSN-DESCRIPTORS-A @ +
        DUP _UPICSN-V-D ! UPICSN-DESCRIPTOR-SIZE 0 FILL
    UPICSN-SOURCE-UIDL _UPICSN-V-D @ _UPICSN-D.SOURCE !
    _UPICSN-V-INDEX @ _UPICSN-V-D @ _UPICSN-D.INDEX !
    _UPICSN-V-KEY @ _UPICSN-V-D @ _UPICSN-D.ROOT-KEY !
    _UPICSN-V-ROW @ _UPICSN-V-D @ _UPICSN-D.ROW !
    _UPICSN-V-COL @ _UPICSN-V-D @ _UPICSN-D.COLUMN !
    _UPICSN-V-H @ _UPICSN-V-D @ _UPICSN-D.HEIGHT !
    _UPICSN-V-W @ _UPICSN-V-D @ _UPICSN-D.WIDTH !
    _UPICSN-V-CLIP-ROW @ _UPICSN-V-D @ _UPICSN-D.CLIP-ROW !
    _UPICSN-V-CLIP-COL @ _UPICSN-V-D @ _UPICSN-D.CLIP-COL !
    _UPICSN-V-CLIP-H @ _UPICSN-V-D @ _UPICSN-D.CLIP-H !
    _UPICSN-V-CLIP-W @ _UPICSN-V-D @ _UPICSN-D.CLIP-W !
    _UTUI-PICTURE-FIGURE? _UPICSN-V-D @ _UPICSN-D.FIGURE !
    _UPICSN-V-RESOLVED-A @ 64 + @ _UPICSN-V-D @ _UPICSN-D.Z !
    _UTUI-PICTURE-REVISION@ _UPICSN-V-D @ _UPICSN-D.REVISION !
    _UPICSN-V-FAILED? 0= IF
        _UPICSN-V-FILE? 0= IF _UPICSN-V-COPY THEN
    THEN
    _UPICSN-V-CLAIM
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
    0 _UPICSN-PRIOR ! 0 _UPICSN-PRIOR-KEY ! 0 _UPICSN-HAVE-PRIOR !
    0 _UPICSN-V-INDEX ! 0 _UPICSN-V-KEY ! 0 _UPICSN-V-RESOLVED-A ! 0 _UPICSN-V-D !
    0 _UPICSN-V-ROW ! 0 _UPICSN-V-COL ! 0 _UPICSN-V-H ! 0 _UPICSN-V-W !
    0 _UPICSN-V-CLIP-ROW ! 0 _UPICSN-V-CLIP-COL !
    0 _UPICSN-V-CLIP-H ! 0 _UPICSN-V-CLIP-W !
    0 _UPICSN-V-PIC !
    0 _UPICSN-F-FORMAT ! 0 _UPICSN-F-W ! 0 _UPICSN-F-H ! 0 _UPICSN-F-U ! ;

CREATE _UPICSN-OWNED-END

: _UPICSN-BANK?  ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    DUP UPICSN-DESCRIPTOR-SIZE MOD IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _UPICSN-OWNED-START _UPICSN-OWNED-END _UPICSN-OWNED-START -
        MSPAN-OVERLAP? 0= ;

\ UPICSN-CAPTURE ( descriptors-a descriptors-u ask -- count status )
\   Describe every picture shown into the caller's descriptor bank: as its
\   file, when ASK names the file's format and the picture is within ASK's
\   limits, or else asking it for a rich copy of at most the pixels
\   UPICSN-BOUND gives its rectangle under ASK.  An unknown pixel size asks
\   for no copy.
\   CAPACITY, with how many descriptors it would take, when the bank holds
\   too few; then nothing is described.  Picture widgets also learn which
\   file formats the rich side takes (PICT-RICH-FORMATS!).
: UPICSN-CAPTURE  ( descriptors-a descriptors-u ask -- count status )
    _UPICSN-ASK UPICSN-ASK-SIZE MOVE
    _UPICSN-ASK UPICSN-ASK.CLAIM @ IF _UPICSN-ASK UPICSN-ASK.FORMATS @ ELSE 0 THEN
        PICT-RICH-FORMATS!
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
  ( index key revision format width height length offset dest-a dest-u -- status )
    2DUP _UTUI-STORAGE-DISJOINT-BODY? 0= IF
        2DROP 2DROP 2DROP 2DROP 2DROP UPICSN-S-INVALID EXIT
    THEN
    _UTUI-PICTURE-PULL IF UPICSN-S-OK ELSE UPICSN-S-STALE THEN ;

\ UPICSN-PULL ( descriptor offset dest-a dest-u -- status )
\   Copy DEST-U bytes of the described file or rich copy, from OFFSET, into
\   DEST; the span must lie within the file or copy.  STALE, with nothing
\   written, when the picture no longer shows it, another picture or a copy
\   of another size, or the file could not be read.
: UPICSN-PULL  ( descriptor offset dest-a dest-u -- status )
    3 PICK UPICSN-STATE@ UPICSN-C-READY <> IF
        2DROP 2DROP UPICSN-S-INVALID EXIT
    THEN
    DUP 0= IF 2DROP 2DROP UPICSN-S-INVALID EXIT THEN
    \ OFFSET and DEST-U name a span of the file or copy.
    2 PICK OVER + DUP 4 PICK U<
    SWAP 5 PICK UPICSN-COPY-BYTES@ U> OR IF
        2DROP 2DROP UPICSN-S-INVALID EXIT
    THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP UPICSN-S-INVALID EXIT THEN
    2DUP _UPICSN-OWNED-START _UPICSN-OWNED-END _UPICSN-OWNED-START -
        MSPAN-OVERLAP? IF 2DROP 2DROP UPICSN-S-INVALID EXIT THEN
    >R >R >R >R
    R@ UPICSN-SOURCE-INDEX@ R@ UPICSN-ROOT-KEY@ R@ UPICSN-REVISION@
    R@ UPICSN-FORMAT@
    R@ UPICSN-COPY-WIDTH@ R@ UPICSN-COPY-HEIGHT@ R> UPICSN-COPY-BYTES@
    R> R> R>
    ['] _UPICSN-PULL-OBSERVED UTUI-RESOLVED-OBSERVE ;

: _UPICSN-FAIL-OBSERVED  ( index key revision reason -- status )
    _UTUI-PICTURE-FAILED! IF UPICSN-S-OK ELSE UPICSN-S-STALE THEN ;

\ UPICSN-FAIL ( source-index root-key revision reason -- status )
\   The rich side could not send picture REVISION at SOURCE-INDEX with
\   ROOT-KEY because of the picture itself, for REASON, a PIC-R- reason:
\   the terminal refused its bytes as damaged, or they could not be read.
\   Its widget remembers why until it is given another source, so
\   captures describe it as FAILED, the rich side neither takes nor sends
\   it, and CELL shows it.  STALE once that element, or that figure,
\   shows another picture or none.
: UPICSN-FAIL  ( source-index root-key revision reason -- status )
    ['] _UPICSN-FAIL-OBSERVED UTUI-RESOLVED-OBSERVE ;

\ UPICSN-RELEASE-ALL ( -- )
\   The rich side shows no picture now: every claim a capture made goes at
\   once, in every document, and CELL shows each picture again.
: UPICSN-RELEASE-ALL  ( -- )  PICT-RELEASE-ALL ;
