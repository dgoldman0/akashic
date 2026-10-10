\ =====================================================================
\  akashic/tui/widgets/media.f — a file, shown the way its kind is shown
\ =====================================================================
\
\  Given a file, the media widget finds what kind of thing it is and shows
\  it through the matching view: a picture widget for the pictures it can
\  show, a text area for text, and the file's facts (name, kind and size)
\  for anything else.  Each view is a canonical widget drawn the ordinary
\  way (WDG-DRAW-IN), so a rich terminal sees the same views it sees
\  anywhere else and CELL shows each one completely.  Focus and keys go to
\  the view shown.
\
\  The widget owns the file it shows.  MEDIA-OPEN-VFS opens it, and the
\  next open, MEDIA-CLEAR or MEDIA-FREE closes it; a text file is read whole
\  and closed at once.  Picture decoding runs from MEDIA-SERVICE, which the
\  UIDL host calls each pass, so drawing never waits for it.  The text view
\  holds the whole file in a buffer sized to it, and the name is kept in a
\  copy sized to it, both from the widget's memory source; when that memory
\  refuses the text, the widget says so instead of cutting it.
\
\  Media Descriptor:
\    +0..+32 widget header (type=WDG-T-MEDIA)
\    +40  msrc       memory for views and the name
\    +48  kind       MEDIA-K-*, or -1 while no file is known
\    +56  size       the file's bytes
\    +64  view       MEDIA-V-*
\    +72  picture    picture widget, made on first use, or 0
\    +80  text       text area of the current text view, or 0
\    +88  text-buf   its buffer, from msrc
\    +96  text-cap
\   +104  note       why a file shows only its facts: MEDIA-N-*
\   +112  name-a     the file's name, from msrc
\   +120  name-u
\   +128  alt-a      text alternative for pictures (borrowed), or 0
\   +136  alt-u
\   +144  source     MEDSRC-VFS-SIZE bytes: the open file
\
\  Prefix: MEDIA- (public), _MEDIA- (internal)
\  Provider: akashic-tui-media
\  Dependencies: widget.f, draw.f, picture.f, textarea.f, media/*

PROVIDED akashic-tui-media

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE picture.f
REQUIRE textarea.f
REQUIRE ../../media/source.f
REQUIRE ../../media/vfs-source.f
REQUIRE ../../media/kind.f
REQUIRE ../../utils/memory-source.f
REQUIRE ../../utils/string.f

 40 CONSTANT _MEDIA-O-MSRC
 48 CONSTANT _MEDIA-O-KIND
 56 CONSTANT _MEDIA-O-SIZE
 64 CONSTANT _MEDIA-O-VIEW
 72 CONSTANT _MEDIA-O-PICTURE
 80 CONSTANT _MEDIA-O-TEXT
 88 CONSTANT _MEDIA-O-TEXT-BUF
 96 CONSTANT _MEDIA-O-TEXT-CAP
104 CONSTANT _MEDIA-O-NOTE
112 CONSTANT _MEDIA-O-NAME-A
120 CONSTANT _MEDIA-O-NAME-U
128 CONSTANT _MEDIA-O-ALT-A
136 CONSTANT _MEDIA-O-ALT-U
144 CONSTANT _MEDIA-O-SOURCE
_MEDIA-O-SOURCE MEDSRC-VFS-SIZE + CONSTANT _MEDIA-DESC-SIZE

0 CONSTANT MEDIA-V-NONE
1 CONSTANT MEDIA-V-PICTURE
2 CONSTANT MEDIA-V-TEXT
3 CONSTANT MEDIA-V-FACTS

0 CONSTANT MEDIA-N-NONE
1 CONSTANT MEDIA-N-NO-VIEW    \ this kind has no view yet
2 CONSTANT MEDIA-N-MEMORY     \ not enough memory to show it
3 CONSTANT MEDIA-N-READ       \ the file could not be opened or read

: _MEDIA@  ( w offset -- x )  + @ ;
: _MEDIA-SOURCE  ( w -- source )  _MEDIA-O-SOURCE + ;
: _MEDIA-MSRC  ( w -- msrc )  _MEDIA-O-MSRC _MEDIA@ ;

\ =====================================================================
\  1. Memory for widgets made from UIDL
\ =====================================================================
\
\  A <media> element's widget takes its memory from the machine's heap,
\  with no budget beyond the heap's own.

: _MEDIA-HEAP-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: _MEDIA-HEAP-FREE  ( addr bytes ctx -- )  2DROP FREE ;

CREATE _MEDIA-HEAP-MEM MSRC-SIZE 7 + ALLOT
_MEDIA-HEAP-MEM 7 + -8 AND CONSTANT MEDIA-HEAP
' _MEDIA-HEAP-ALLOC ' _MEDIA-HEAP-FREE 0 0 MEDIA-HEAP MSRC-INIT

\ =====================================================================
\  2. Views
\ =====================================================================

\ The text alternative pictures show: the caller's, else the name.
: _MEDIA-ALT  ( w -- a u )
    DUP _MEDIA-O-ALT-U _MEDIA@ IF
        DUP _MEDIA-O-ALT-A _MEDIA@ SWAP _MEDIA-O-ALT-U _MEDIA@ EXIT
    THEN
    DUP _MEDIA-O-NAME-A _MEDIA@ SWAP _MEDIA-O-NAME-U _MEDIA@ ;

: _MEDIA-DROP-TEXT  ( w -- )
    DUP _MEDIA-O-TEXT _MEDIA@ ?DUP IF TXTA-FREE THEN
    0 OVER _MEDIA-O-TEXT + !
    DUP _MEDIA-O-TEXT-BUF _MEDIA@ ?DUP IF
        OVER _MEDIA-O-TEXT-CAP _MEDIA@ 2 PICK _MEDIA-MSRC MSRC-FREE
    THEN
    0 OVER _MEDIA-O-TEXT-BUF + !  0 SWAP _MEDIA-O-TEXT-CAP + ! ;

: _MEDIA-DROP-NAME  ( w -- )
    DUP _MEDIA-O-NAME-A _MEDIA@ ?DUP IF
        OVER _MEDIA-O-NAME-U _MEDIA@ 2 PICK _MEDIA-MSRC MSRC-FREE
    THEN
    0 OVER _MEDIA-O-NAME-A + !  0 SWAP _MEDIA-O-NAME-U + ! ;

\ Keep a copy of NAME, or no name when memory refuses it.
: _MEDIA-NAME!  ( name-a name-u w -- )
    >R DUP R@ _MEDIA-MSRC MSRC-ALLOC                ( a u copy|0 )
    DUP 0= IF DROP 2DROP R> DROP EXIT THEN
    DUP R@ _MEDIA-O-NAME-A + !  OVER R@ _MEDIA-O-NAME-U + !
    SWAP CMOVE R> DROP ;

\ Stop showing anything and close the file.
: _MEDIA-RELEASE  ( w -- )
    DUP _MEDIA-O-PICTURE _MEDIA@ ?DUP IF >R 0 0 0 R> PICT-SOURCE! THEN
    DUP _MEDIA-DROP-TEXT
    DUP _MEDIA-DROP-NAME
    DUP _MEDIA-SOURCE MEDSRC-RELEASE
    -1 OVER _MEDIA-O-KIND + !  0 OVER _MEDIA-O-SIZE + !
    MEDIA-V-NONE OVER _MEDIA-O-VIEW + !
    MEDIA-N-NONE SWAP _MEDIA-O-NOTE + ! ;

: _MEDIA-FACTS  ( note w -- )
    TUCK _MEDIA-O-NOTE + !
    MEDIA-V-FACTS SWAP _MEDIA-O-VIEW + ! ;

\ Show the open file as a picture.
: _MEDIA-PICTURE  ( w -- )
    DUP _MEDIA-O-PICTURE _MEDIA@ 0= IF
        DUP WDG-REGION OVER _MEDIA-MSRC PICT-NEW
        OVER _MEDIA-O-PICTURE + !
    THEN
    DUP _MEDIA-SOURCE OVER _MEDIA-ALT 3 PICK _MEDIA-O-PICTURE _MEDIA@ PICT-SOURCE!
    MEDIA-V-PICTURE SWAP _MEDIA-O-VIEW + ! ;

VARIABLE _MT-W

\ Show the open file as text: read it whole, then close it.  The ior is
\ the read's; a memory refusal is no read error, and the widget says so.
: _MEDIA-TEXT  ( w -- ior )
    _MT-W !
    _MT-W @ _MEDIA-O-SIZE _MEDIA@ 1 MAX            ( cap )
    DUP _MT-W @ _MEDIA-MSRC MSRC-ALLOC
    DUP 0= IF
        2DROP _MT-W @ _MEDIA-SOURCE MEDSRC-RELEASE
        MEDIA-N-MEMORY _MT-W @ _MEDIA-FACTS 0 EXIT
    THEN
    _MT-W @ _MEDIA-O-TEXT-BUF + !  _MT-W @ _MEDIA-O-TEXT-CAP + !
    _MT-W @ _MEDIA-O-SIZE _MEDIA@ IF
        _MT-W @ _MEDIA-O-TEXT-BUF _MEDIA@ _MT-W @ _MEDIA-O-SIZE _MEDIA@ 0
        _MT-W @ _MEDIA-SOURCE MEDSRC-READ? ?DUP IF
            _MT-W @ _MEDIA-DROP-TEXT _MT-W @ _MEDIA-SOURCE MEDSRC-RELEASE
            MEDIA-N-READ _MT-W @ _MEDIA-FACTS EXIT
        THEN
    THEN
    _MT-W @ _MEDIA-SOURCE MEDSRC-RELEASE
    _MT-W @ WDG-REGION _MT-W @ _MEDIA-O-TEXT-BUF _MEDIA@
    _MT-W @ _MEDIA-O-TEXT-CAP _MEDIA@ TXTA-NEW
    DUP _MT-W @ _MEDIA-O-TEXT + !
    _MT-W @ _MEDIA-O-TEXT-BUF _MEDIA@ _MT-W @ _MEDIA-O-SIZE _MEDIA@ ROT TXTA-SET-TEXT
    MEDIA-V-TEXT _MT-W @ _MEDIA-O-VIEW + ! 0 ;

\ The name after the last slash of a path.
: _MEDIA-BASENAME  ( path-a path-u -- name-a name-u )
    DUP BEGIN DUP WHILE
        2 PICK OVER 1- + C@ 47 = IF
            ROT OVER + -ROT - EXIT
        THEN 1-
    REPEAT DROP ;

CREATE _MEDIA-SNIFF MEDIA-SNIFF-BYTES ALLOT
VARIABLE _MO-W
VARIABLE _MO-N

\ Give the focus of the media widget to the view it shows.
: _MEDIA-FOCUS-TO  ( view-widget w -- )
    WDG-FOCUSED? IF WDG-FOCUS-SET ELSE WDG-FOCUS-CLR THEN ;

\ =====================================================================
\  3. Public API
\ =====================================================================

: MEDIA-KIND@     ( widget -- kind )      _MEDIA-O-KIND _MEDIA@ ;
: MEDIA-SIZE@     ( widget -- bytes )     _MEDIA-O-SIZE _MEDIA@ ;
: MEDIA-VIEW@     ( widget -- view )      _MEDIA-O-VIEW _MEDIA@ ;
: MEDIA-NOTE@     ( widget -- note )      _MEDIA-O-NOTE _MEDIA@ ;
: MEDIA-NAME@     ( widget -- a u )
    DUP _MEDIA-O-NAME-A _MEDIA@ SWAP _MEDIA-O-NAME-U _MEDIA@ ;
: MEDIA-PICTURE@  ( widget -- picture|0 ) _MEDIA-O-PICTURE _MEDIA@ ;
: MEDIA-TEXT@     ( widget -- text|0 )    _MEDIA-O-TEXT _MEDIA@ ;

\ MEDIA-VIEW-WIDGET@ ( widget -- view-widget|0 )
\   The canonical widget the current view draws: the picture or the text
\   area.  Zero for the facts view and for nothing.
: MEDIA-VIEW-WIDGET@  ( widget -- view-widget|0 )
    DUP MEDIA-VIEW@ CASE
        MEDIA-V-PICTURE OF MEDIA-PICTURE@ ENDOF
        MEDIA-V-TEXT    OF MEDIA-TEXT@ ENDOF
        >R DROP 0 R>
    ENDCASE ;

DEFER _MEDIA-DRAW-D
DEFER _MEDIA-HANDLE-D
: _MEDIA-DRAW  ( widget -- )  _MEDIA-DRAW-D ;
: _MEDIA-HANDLE  ( event widget -- consumed? )  _MEDIA-HANDLE-D ;

\ MEDIA-NEW ( rgn msrc -- widget )   A media widget showing nothing yet.
: MEDIA-NEW  ( rgn msrc -- widget )
    _MEDIA-DESC-SIZE ALLOCATE 0<> ABORT" MEDIA-NEW: alloc"
    DUP _MEDIA-DESC-SIZE 0 FILL
    >R
    R@ _MEDIA-O-MSRC + !
    R@ WDG-T-MEDIA ROT ['] _MEDIA-DRAW ['] _MEDIA-HANDLE WDG-INIT
    -1 R@ _MEDIA-O-KIND + !
    R> ;

\ MEDIA-CLEAR ( widget -- )   Show nothing and close the file.
: MEDIA-CLEAR  ( widget -- )
    DUP _MEDIA-RELEASE WDG-DIRTY ;

\ MEDIA-OPEN-VFS ( path-a path-u vfs widget -- ior )
\   Show the file at PATH in VFS the way its kind is shown.  A nonzero ior
\   says the file could not be opened or read, and the widget says so.
: MEDIA-OPEN-VFS  ( path-a path-u vfs widget -- ior )
    DUP _MO-W !  DUP _MEDIA-RELEASE  WDG-DIRTY
    >R 2DUP _MEDIA-BASENAME _MO-W @ _MEDIA-NAME! R>
    _MO-W @ _MEDIA-SOURCE MEDSRC-VFS-OPEN                    ( ior )
    ?DUP IF MEDIA-N-READ _MO-W @ _MEDIA-FACTS EXIT THEN
    _MO-W @ _MEDIA-SOURCE MEDSRC-SIZE@ _MO-W @ _MEDIA-O-SIZE + !
    _MO-W @ _MEDIA-O-SIZE _MEDIA@ MEDIA-SNIFF-BYTES MIN _MO-N !
    _MO-N @ IF
        _MEDIA-SNIFF _MO-N @ 0 _MO-W @ _MEDIA-SOURCE MEDSRC-READ?
        ?DUP IF
            _MO-W @ _MEDIA-SOURCE MEDSRC-RELEASE
            MEDIA-N-READ _MO-W @ _MEDIA-FACTS EXIT
        THEN
    THEN
    _MEDIA-SNIFF _MO-N @ _MO-W @ MEDIA-NAME@
    MEDIA-KIND DUP _MO-W @ _MEDIA-O-KIND + !
    CASE
        MEDIA-K-QOI  OF _MO-W @ _MEDIA-PICTURE 0 ENDOF
        MEDIA-K-TEXT OF _MO-W @ _MEDIA-TEXT ENDOF
        MEDIA-K-HTML OF _MO-W @ _MEDIA-TEXT ENDOF
        _MO-W @ _MEDIA-SOURCE MEDSRC-RELEASE
        MEDIA-N-NO-VIEW _MO-W @ _MEDIA-FACTS 0 SWAP
    ENDCASE ;

\ MEDIA-ALT! ( alt-a alt-u widget -- )
\   A text alternative for pictures in place of the file's name, or 0 0
\   for the name again.  The caller keeps the text alive while it is set.
: MEDIA-ALT!  ( alt-a alt-u widget -- )
    >R R@ _MEDIA-O-ALT-U + !  R@ _MEDIA-O-ALT-A + !
    R@ _MEDIA-O-VIEW _MEDIA@ MEDIA-V-PICTURE = IF
        R@ _MEDIA-ALT R@ _MEDIA-O-PICTURE _MEDIA@ PICT-ALT!
    THEN
    R> WDG-DIRTY ;

\ MEDIA-FREE ( widget -- )   Close the file and give back everything.
: MEDIA-FREE  ( widget -- )
    DUP _MEDIA-RELEASE
    DUP _MEDIA-O-PICTURE _MEDIA@ ?DUP IF PICT-FREE THEN
    FREE ;

\ MEDIA-PENDING? ( widget -- flag )   A picture shown is still decoding.
: MEDIA-PENDING?  ( widget -- flag )
    DUP _MEDIA-O-VIEW _MEDIA@ MEDIA-V-PICTURE <> IF DROP 0 EXIT THEN
    _MEDIA-O-PICTURE _MEDIA@ PICT-PENDING? ;

\ MEDIA-SERVICE ( widget -- changed? )
\   Decode some more of a picture being shown.  True when what the widget
\   shows changed.
: MEDIA-SERVICE  ( widget -- changed? )
    DUP MEDIA-PENDING? 0= IF DROP 0 EXIT THEN
    PICT-STEP-PIXELS OVER _MEDIA-O-PICTURE _MEDIA@ PICT-SERVICE
    DUP IF SWAP WDG-DIRTY ELSE NIP THEN ;

\ =====================================================================
\  4. Drawing and input
\ =====================================================================

VARIABLE _MD-W
VARIABLE _MD-COLS
VARIABLE _MD-ROWS
64 CONSTANT _MD-LINE-CAP
CREATE _MD-LINE _MD-LINE-CAP ALLOT
VARIABLE _MD-LINE-U

: _MD-NOTE-TEXT  ( note -- a u )
    CASE
        MEDIA-N-NO-VIEW OF S" No preview for this kind of file yet" ENDOF
        MEDIA-N-MEMORY  OF S" Not enough memory to show this file" ENDOF
        MEDIA-N-READ    OF S" The file could not be read" ENDOF
        >R 0 0 R>
    ENDCASE ;

\ Append to the facts line; it holds a kind name and a size, which always
\ fit, so nothing is ever cut in practice.
: _MD-ADD  ( a u -- )
    _MD-LINE-CAP _MD-LINE-U @ - MIN
    DUP >R _MD-LINE _MD-LINE-U @ + SWAP CMOVE R> _MD-LINE-U +! ;

\ "kind, size": the size as SIZE-FMT gives it, with " bytes" after a bare
\ count.
: _MD-KIND-SIZE  ( -- a u )
    0 _MD-LINE-U !
    _MD-W @ MEDIA-KIND@ MEDIA-KIND-NAME _MD-ADD
    S" , " _MD-ADD
    _MD-W @ MEDIA-SIZE@ DUP SIZE-FMT _MD-ADD
    1024 < IF S"  bytes" _MD-ADD THEN
    _MD-LINE _MD-LINE-U @ ;

: _MD-CENTER  ( a u row -- row+1 )
    DUP >R 0 _MD-COLS @ DRW-TEXT-CENTER R> 1+ ;

\ The facts: the file's name, what it is and how big, and why it shows only
\ this.  A file that could not be opened has no kind and size to tell.
: _MD-FACTS  ( -- )
    _MD-ROWS @ 2/ 1- DUP 0< IF DROP 0 THEN               ( row )
    _MD-W @ MEDIA-NAME@ ROT _MD-CENTER
    _MD-W @ MEDIA-KIND@ 0< 0= IF _MD-KIND-SIZE ROT _MD-CENTER THEN
    _MD-W @ MEDIA-NOTE@ _MD-NOTE-TEXT ROT _MD-CENTER DROP ;

: _MEDIA-DO-DRAW  ( widget -- )
    DUP _MD-W !
    WDG-REGION DUP RGN-W _MD-COLS ! RGN-H _MD-ROWS !
    _MD-W @ MEDIA-VIEW-WIDGET@ ?DUP IF
        DUP _MD-W @ _MEDIA-FOCUS-TO
        _MD-W @ WDG-REGION WDG-DRAW-IN EXIT
    THEN
    32 0 0 _MD-ROWS @ _MD-COLS @ DRW-FILL-RECT
    _MD-W @ MEDIA-VIEW@ MEDIA-V-FACTS = IF _MD-FACTS THEN ;

: _MEDIA-DO-HANDLE  ( event widget -- consumed? )
    DUP MEDIA-VIEW-WIDGET@ ?DUP 0= IF 2DROP 0 EXIT THEN
    TUCK SWAP _MEDIA-FOCUS-TO WDG-HANDLE ;

' _MEDIA-DO-DRAW IS _MEDIA-DRAW-D
' _MEDIA-DO-HANDLE IS _MEDIA-HANDLE-D

\ =====================================================================
\  5. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _media-guard

' MEDIA-NEW      CONSTANT _media-new-xt
' MEDIA-CLEAR    CONSTANT _media-clear-xt
' MEDIA-OPEN-VFS CONSTANT _media-open-vfs-xt
' MEDIA-ALT!     CONSTANT _media-alt-xt
' MEDIA-FREE     CONSTANT _media-free-xt
' MEDIA-SERVICE  CONSTANT _media-service-xt

: MEDIA-NEW      _media-new-xt      _media-guard WITH-GUARD ;
: MEDIA-CLEAR    _media-clear-xt    _media-guard WITH-GUARD ;
: MEDIA-OPEN-VFS _media-open-vfs-xt _media-guard WITH-GUARD ;
: MEDIA-ALT!     _media-alt-xt      _media-guard WITH-GUARD ;
: MEDIA-FREE     _media-free-xt     _media-guard WITH-GUARD ;
: MEDIA-SERVICE  _media-service-xt  _media-guard WITH-GUARD ;
[THEN] [THEN]
