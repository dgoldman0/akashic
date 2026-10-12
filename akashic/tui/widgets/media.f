\ =====================================================================
\  akashic/tui/widgets/media.f — a file, shown the way its kind is shown
\ =====================================================================
\
\  Given a file, the media widget finds what kind of thing it is and shows
\  it through the matching view: a picture widget for QOI, PNG and JPEG
\  pictures, a document view for a kind it has a document reader for, a
\  text area for other text, and the file's facts (name, kind and size)
\  for anything else.  It reads Markdown documents from the start; an
\  owner adds a reader for another kind with MEDIA-READER!, as File
\  Explorer adds pdf/document.f's for PDFs, so an application that shows
\  no such files does not load their reader.  The picture widget decodes
\  QOI and PNG for CELL and shows a JPEG's format and size there; a rich
\  terminal that decodes the file shows the picture itself.  Each view is
\  a canonical widget drawn the ordinary way (WDG-DRAW-IN), so a rich
\  terminal sees the same views it sees anywhere else and CELL shows each
\  one completely.  Focus and keys go to the view shown.
\
\  The widget owns the file it shows.  MEDIA-OPEN-VFS opens it, and the
\  next open, MEDIA-CLEAR or MEDIA-FREE closes it; a text file is read whole
\  and closed at once, and a document stays open while it is shown, since
\  its view reads a block's text only when it reaches the block.  Picture
\  decoding runs from MEDIA-SERVICE, which the UIDL host calls each pass,
\  so drawing never waits for it.  The text view holds the whole file in a
\  buffer sized to it, and the path is kept in a copy sized to it, both
\  from the widget's memory source; when that memory refuses the text or
\  the document, the widget says so instead of cutting it.
\
\  A document that needs a password to be read shows its facts and says it
\  is protected.  A document's figures and links name files from the
\  document's folder (utils/fs/link-path.f).  A figure's picture is opened
\  from the same file system.  A link to one of the document's own
\  headings scrolls the view; any other link goes to the owner's follow
\  word, set with MEDIA-FOLLOW!, as the path it names, or the LPATH-
\  status saying why it names none.
\
\  Media Descriptor:
\    +0..+32 widget header (type=WDG-T-MEDIA)
\    +40  msrc       memory for views, the path and the document
\    +48  kind       MEDIA-K-*, or -1 while no file is known
\    +56  size       the file's bytes
\    +64  view       MEDIA-V-*
\    +72  picture    picture widget, made on first use, or 0
\    +80  text       text area of the current text view, or 0
\    +88  text-buf   its buffer, from msrc
\    +96  text-cap
\   +104  note       why a file shows only its facts: MEDIA-N-*
\   +112  path-a     the path the file was opened by, from msrc
\   +120  path-u
\   +128  alt-a      text alternative for pictures (borrowed), or 0
\   +136  alt-u
\   +144  vfs        the file system the file is in
\   +152  docv       document view, made on first use, or 0
\   +160  doc        the open document (DOC-SIZE bytes from msrc), or 0
\   +168  follow-xt  ( path-a path-u status ctx -- ), or 0
\   +176  follow-ctx
\   +184  readers    a document reader for each kind (MEDIA-KINDS cells), or 0
\         source     MEDSRC-VFS-SIZE bytes: the open file, after the readers
\
\  Prefix: MEDIA- (public), _MEDIA- and _MDW- (internal)
\  Provider: akashic-tui-media
\  Dependencies: widget.f, draw.f, picture.f, textarea.f, document.f,
\                media/*, markup/markdown.f, utils/fs/link-path.f

PROVIDED akashic-tui-media

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE picture.f
REQUIRE textarea.f
REQUIRE document.f
REQUIRE ../../media/source.f
REQUIRE ../../media/vfs-source.f
REQUIRE ../../media/kind.f
REQUIRE ../../media/document.f
REQUIRE ../../markup/markdown.f
REQUIRE ../../utils/fs/link-path.f
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
112 CONSTANT _MEDIA-O-PATH-A
120 CONSTANT _MEDIA-O-PATH-U
128 CONSTANT _MEDIA-O-ALT-A
136 CONSTANT _MEDIA-O-ALT-U
144 CONSTANT _MEDIA-O-VFS
152 CONSTANT _MEDIA-O-DOCV
160 CONSTANT _MEDIA-O-DOC
168 CONSTANT _MEDIA-O-FOLLOW
176 CONSTANT _MEDIA-O-FOLLOW-CTX
184 CONSTANT _MEDIA-O-READERS
_MEDIA-O-READERS MEDIA-KINDS CELLS + CONSTANT _MEDIA-O-SOURCE
_MEDIA-O-SOURCE MEDSRC-VFS-SIZE + CONSTANT _MEDIA-DESC-SIZE

0 CONSTANT MEDIA-V-NONE
1 CONSTANT MEDIA-V-PICTURE
2 CONSTANT MEDIA-V-TEXT
3 CONSTANT MEDIA-V-FACTS
4 CONSTANT MEDIA-V-DOCUMENT

0 CONSTANT MEDIA-N-NONE
1 CONSTANT MEDIA-N-NO-VIEW    \ this kind has no view yet
2 CONSTANT MEDIA-N-MEMORY     \ not enough memory to show it
3 CONSTANT MEDIA-N-READ       \ the file could not be opened or read
4 CONSTANT MEDIA-N-LOCKED     \ the document needs a password to be read

: _MEDIA@  ( w offset -- x )  + @ ;
: _MEDIA-SOURCE  ( w -- source )  _MEDIA-O-SOURCE + ;
: _MEDIA-MSRC  ( w -- msrc )  _MEDIA-O-MSRC _MEDIA@ ;
: _MEDIA-READER  ( kind w -- reader|0 )  _MEDIA-O-READERS + SWAP CELLS + @ ;

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
\  2. The file's path and name
\ =====================================================================

\ The name after the last slash of a path.
: _MEDIA-BASENAME  ( path-a path-u -- name-a name-u )
    DUP BEGIN DUP WHILE
        2 PICK OVER 1- + C@ 47 = IF
            ROT OVER + -ROT - EXIT
        THEN 1-
    REPEAT DROP ;

: MEDIA-PATH@  ( widget -- a u )
    DUP _MEDIA-O-PATH-A _MEDIA@ SWAP _MEDIA-O-PATH-U _MEDIA@ ;
: MEDIA-NAME@  ( widget -- a u )  MEDIA-PATH@ _MEDIA-BASENAME ;

: _MEDIA-DROP-PATH  ( w -- )
    DUP _MEDIA-O-PATH-A _MEDIA@ ?DUP IF
        OVER _MEDIA-O-PATH-U _MEDIA@ 2 PICK _MEDIA-MSRC MSRC-FREE
    THEN
    0 OVER _MEDIA-O-PATH-A + !  0 SWAP _MEDIA-O-PATH-U + ! ;

\ Keep a copy of PATH, or no path when memory refuses it.
: _MEDIA-PATH!  ( path-a path-u w -- )
    >R DUP R@ _MEDIA-MSRC MSRC-ALLOC                ( a u copy|0 )
    DUP 0= IF DROP 2DROP R> DROP EXIT THEN
    DUP R@ _MEDIA-O-PATH-A + !  OVER R@ _MEDIA-O-PATH-U + !
    SWAP CMOVE R> DROP ;

\ =====================================================================
\  3. Views
\ =====================================================================

\ The text alternative pictures show: the caller's, else the name.
: _MEDIA-ALT  ( w -- a u )
    DUP _MEDIA-O-ALT-U _MEDIA@ IF
        DUP _MEDIA-O-ALT-A _MEDIA@ SWAP _MEDIA-O-ALT-U _MEDIA@ EXIT
    THEN
    MEDIA-NAME@ ;

: _MEDIA-DROP-TEXT  ( w -- )
    DUP _MEDIA-O-TEXT _MEDIA@ ?DUP IF TXTA-FREE THEN
    0 OVER _MEDIA-O-TEXT + !
    DUP _MEDIA-O-TEXT-BUF _MEDIA@ ?DUP IF
        OVER _MEDIA-O-TEXT-CAP _MEDIA@ 2 PICK _MEDIA-MSRC MSRC-FREE
    THEN
    0 OVER _MEDIA-O-TEXT-BUF + !  0 SWAP _MEDIA-O-TEXT-CAP + ! ;

\ Give back the document's record; the document is closed or never opened.
: _MEDIA-DROP-DOC  ( w -- )
    DUP _MEDIA-O-DOC _MEDIA@ ?DUP IF
        DOC-SIZE 2 PICK _MEDIA-MSRC MSRC-FREE
    THEN
    0 SWAP _MEDIA-O-DOC + ! ;

\ Stop showing anything and close the file.
: _MEDIA-RELEASE  ( w -- )
    DUP _MEDIA-O-PICTURE _MEDIA@ ?DUP IF >R 0 0 0 R> PICT-SOURCE! THEN
    DUP _MEDIA-O-VIEW _MEDIA@ MEDIA-V-DOCUMENT = IF
        0 OVER _MEDIA-O-DOCV _MEDIA@ DOCV-DOCUMENT!
        DUP _MEDIA-O-DOC _MEDIA@ DOC-CLOSE
        DUP _MEDIA-DROP-DOC
    THEN
    DUP _MEDIA-DROP-TEXT
    DUP _MEDIA-DROP-PATH
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

\ --- Documents -----------------------------------------------------------

VARIABLE _MDF-W

\ _MEDIA-RESOLVE-PATH ( target-a target-u w -- buf cap u status )
\   The path a document's link or figure names, from the document's
\   folder, in a buffer from the widget's memory sized to the longest path
\   it can name.  The caller gives BUF back; it is 0 when memory refused
\   it, and the status is then LPATH-S-ROOM.
: _MEDIA-RESOLVE-PATH  ( target-a target-u w -- buf cap u status )
    _MDF-W !
    DUP _MDF-W @ _MEDIA-O-PATH-U _MEDIA@ LPATH-BOUND
    DUP _MDF-W @ _MEDIA-MSRC MSRC-ALLOC                  ( t-a t-u cap buf )
    ?DUP 0= IF DROP 2DROP 0 0 0 LPATH-S-ROOM EXIT THEN
    SWAP 2>R
    _MDF-W @ MEDIA-PATH@ 2R@ LPATH-RESOLVE
    2R> 2SWAP ;

VARIABLE _MFR-BUF
VARIABLE _MFR-CAP
VARIABLE _MFR-U
VARIABLE _MFR-SRC

\ The document view's resolve word: a figure's picture, opened read-only
\ from the same file system, or 0.
: _MEDIA-FIG-RESOLVE  ( name-a name-u w -- source|0 )
    DUP _MDF-W ! _MEDIA-RESOLVE-PATH                    ( buf cap u status )
    >R _MFR-U ! _MFR-CAP ! _MFR-BUF !
    0 R> LPATH-S-OK = IF
        MEDSRC-VFS-SIZE _MDF-W @ _MEDIA-MSRC MSRC-ALLOC ?DUP IF
            _MFR-SRC !
            _MFR-BUF @ _MFR-U @ _MDF-W @ _MEDIA-O-VFS _MEDIA@ _MFR-SRC @
            MEDSRC-VFS-OPEN IF
                _MFR-SRC @ MEDSRC-VFS-SIZE _MDF-W @ _MEDIA-MSRC MSRC-FREE
            ELSE
                DROP _MFR-SRC @
            THEN
        THEN
    THEN
    _MFR-BUF @ ?DUP IF _MFR-CAP @ _MDF-W @ _MEDIA-MSRC MSRC-FREE THEN ;

\ The document view's release word.
: _MEDIA-FIG-RELEASE  ( source w -- )
    >R DUP MEDSRC-RELEASE MEDSRC-VFS-SIZE R> _MEDIA-MSRC MSRC-FREE ;

\ The document view's follow word: the path a link names goes to the
\ owner's follow word, and stays valid only while it runs.
: _MEDIA-FOLLOW  ( target-a target-u w -- )
    DUP _MEDIA-O-FOLLOW _MEDIA@ 0= IF DROP 2DROP EXIT THEN
    DUP >R _MEDIA-RESOLVE-PATH                          ( buf cap u status )
    >R >R OVER R> R>                                    ( buf cap buf u status )
    R@ _MEDIA-O-FOLLOW-CTX _MEDIA@ R@ _MEDIA-O-FOLLOW _MEDIA@ EXECUTE
    OVER IF R@ _MEDIA-MSRC MSRC-FREE ELSE 2DROP THEN
    R> DROP ;

VARIABLE _MDD-W

\ Show the open file as a document, read by the reader for its kind.  It
\ stays open while shown.  A document that needs a password, or one that
\ memory refuses, shows its facts and says so; that is no read error.
: _MEDIA-DOCUMENT  ( w -- ior )
    _MDD-W !
    DOC-SIZE _MDD-W @ _MEDIA-MSRC MSRC-ALLOC ?DUP 0= IF
        _MDD-W @ _MEDIA-SOURCE MEDSRC-RELEASE
        MEDIA-N-MEMORY _MDD-W @ _MEDIA-FACTS 0 EXIT
    THEN
    _MDD-W @ _MEDIA-O-DOC + !
    _MDD-W @ _MEDIA-SOURCE
    _MDD-W @ _MEDIA-O-KIND _MEDIA@ _MDD-W @ _MEDIA-READER _MDD-W @ _MEDIA-MSRC
    _MDD-W @ _MEDIA-O-DOC _MEDIA@ DOC-OPEN
    ?DUP IF
        _MDD-W @ _MEDIA-DROP-DOC
        _MDD-W @ _MEDIA-SOURCE MEDSRC-RELEASE
        CASE
            DOC-S-MEMORY OF MEDIA-N-MEMORY _MDD-W @ _MEDIA-FACTS 0 ENDOF
            DOC-S-LOCKED OF MEDIA-N-LOCKED _MDD-W @ _MEDIA-FACTS 0 ENDOF
            MEDIA-N-READ _MDD-W @ _MEDIA-FACTS -1 SWAP
        ENDCASE EXIT
    THEN
    _MDD-W @ _MEDIA-O-DOCV _MEDIA@ 0= IF
        _MDD-W @ WDG-REGION _MDD-W @ _MEDIA-MSRC DOCV-NEW
        DUP _MDD-W @ _MEDIA-O-DOCV + !
        >R ['] _MEDIA-FIG-RESOLVE ['] _MEDIA-FIG-RELEASE ['] _MEDIA-FOLLOW
        _MDD-W @ R> DOCV-OWNER!
    THEN
    _MDD-W @ _MEDIA-O-DOC _MEDIA@ _MDD-W @ _MEDIA-O-DOCV _MEDIA@ DOCV-DOCUMENT!
    MEDIA-V-DOCUMENT _MDD-W @ _MEDIA-O-VIEW + ! 0 ;

CREATE _MEDIA-SNIFF MEDIA-SNIFF-BYTES ALLOT
VARIABLE _MO-W
VARIABLE _MO-N

\ Give the focus of the media widget to the view it shows.
: _MEDIA-FOCUS-TO  ( view-widget w -- )
    WDG-FOCUSED? IF WDG-FOCUS-SET ELSE WDG-FOCUS-CLR THEN ;

\ =====================================================================
\  4. Public API
\ =====================================================================

: MEDIA-KIND@     ( widget -- kind )      _MEDIA-O-KIND _MEDIA@ ;
: MEDIA-SIZE@     ( widget -- bytes )     _MEDIA-O-SIZE _MEDIA@ ;
: MEDIA-VIEW@     ( widget -- view )      _MEDIA-O-VIEW _MEDIA@ ;
: MEDIA-NOTE@     ( widget -- note )      _MEDIA-O-NOTE _MEDIA@ ;
: MEDIA-PICTURE@  ( widget -- picture|0 ) _MEDIA-O-PICTURE _MEDIA@ ;
: MEDIA-TEXT@     ( widget -- text|0 )    _MEDIA-O-TEXT _MEDIA@ ;
: MEDIA-DOCUMENT@ ( widget -- docv|0 )    _MEDIA-O-DOCV _MEDIA@ ;

\ MEDIA-VIEW-WIDGET@ ( widget -- view-widget|0 )
\   The canonical widget the current view draws: the picture, the text
\   area or the document view.  Zero for the facts view and for nothing.
: MEDIA-VIEW-WIDGET@  ( widget -- view-widget|0 )
    DUP MEDIA-VIEW@ CASE
        MEDIA-V-PICTURE  OF MEDIA-PICTURE@ ENDOF
        MEDIA-V-TEXT     OF MEDIA-TEXT@ ENDOF
        MEDIA-V-DOCUMENT OF MEDIA-DOCUMENT@ ENDOF
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
    MD-READER MEDIA-K-MARKDOWN CELLS R@ _MEDIA-O-READERS + + !
    R> ;

\ MEDIA-READER! ( reader kind widget -- )
\   Show files of KIND as documents READER reads (media/document.f), or
\   for 0, as the kind is otherwise shown.  It takes effect at the next
\   open.
: MEDIA-READER!  ( reader kind widget -- )
    OVER 0 MEDIA-KINDS WITHIN 0= IF DROP 2DROP EXIT THEN
    _MEDIA-O-READERS + SWAP CELLS + ! ;

\ MEDIA-CLEAR ( widget -- )   Show nothing and close the file.
: MEDIA-CLEAR  ( widget -- )
    DUP _MEDIA-RELEASE WDG-DIRTY ;

\ MEDIA-OPEN-VFS ( path-a path-u vfs widget -- ior )
\   Show the file at PATH in VFS the way its kind is shown.  A nonzero ior
\   says the file could not be opened or read, and the widget says so.
: MEDIA-OPEN-VFS  ( path-a path-u vfs widget -- ior )
    DUP _MO-W !  DUP _MEDIA-RELEASE  WDG-DIRTY
    DUP _MO-W @ _MEDIA-O-VFS + !
    >R 2DUP _MO-W @ _MEDIA-PATH! R>
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
    DUP _MO-W @ _MEDIA-READER IF DROP _MO-W @ _MEDIA-DOCUMENT EXIT THEN
    CASE
        MEDIA-K-QOI      OF _MO-W @ _MEDIA-PICTURE 0 ENDOF
        MEDIA-K-PNG      OF _MO-W @ _MEDIA-PICTURE 0 ENDOF
        MEDIA-K-JPEG     OF _MO-W @ _MEDIA-PICTURE 0 ENDOF
        MEDIA-K-TEXT     OF _MO-W @ _MEDIA-TEXT ENDOF
        MEDIA-K-HTML     OF _MO-W @ _MEDIA-TEXT ENDOF
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

\ MEDIA-FOLLOW! ( follow-xt ctx widget -- )
\   The word a link in a shown document goes to, unless it is a link to
\   one of the document's own headings: ( path-a path-u status ctx -- ),
\   with the path the link names and LPATH-S-OK, or no path and the
\   LPATH- status saying why it names none.  The path stays valid only
\   while the word runs.  Zero follows no such link.
: MEDIA-FOLLOW!  ( follow-xt ctx widget -- )
    TUCK _MEDIA-O-FOLLOW-CTX + ! _MEDIA-O-FOLLOW + ! ;

\ MEDIA-FREE ( widget -- )   Close the file and give back everything.
: MEDIA-FREE  ( widget -- )
    DUP _MEDIA-RELEASE
    DUP _MEDIA-O-PICTURE _MEDIA@ ?DUP IF PICT-FREE THEN
    DUP _MEDIA-O-DOCV _MEDIA@ ?DUP IF DOCV-FREE THEN
    FREE ;

\ MEDIA-PENDING? ( widget -- flag )
\   A picture shown, or a figure's, is still decoding.
: MEDIA-PENDING?  ( widget -- flag )
    DUP MEDIA-VIEW@ CASE
        MEDIA-V-PICTURE  OF MEDIA-PICTURE@ PICT-PENDING? ENDOF
        MEDIA-V-DOCUMENT OF MEDIA-DOCUMENT@ DOCV-PENDING? ENDOF
        >R DROP 0 R>
    ENDCASE ;

\ MEDIA-SERVICE ( widget -- changed? )
\   Decode some more of a picture being shown.  True when what the widget
\   shows changed.
: MEDIA-SERVICE  ( widget -- changed? )
    DUP MEDIA-PENDING? 0= IF DROP 0 EXIT THEN
    DUP MEDIA-VIEW@ MEDIA-V-DOCUMENT = IF
        DUP MEDIA-DOCUMENT@ DOCV-SERVICE
    ELSE
        PICT-STEP-PIXELS OVER MEDIA-PICTURE@ PICT-SERVICE
    THEN
    DUP IF SWAP WDG-DIRTY ELSE NIP THEN ;

\ =====================================================================
\  5. Drawing and input
\ =====================================================================

VARIABLE _MDW-W
VARIABLE _MDW-COLS
VARIABLE _MDW-ROWS
64 CONSTANT _MDW-LINE-CAP
CREATE _MDW-LINE _MDW-LINE-CAP ALLOT
VARIABLE _MDW-LINE-U

: _MDW-NOTE-TEXT  ( note -- a u )
    CASE
        MEDIA-N-NO-VIEW OF S" No preview for this kind of file yet" ENDOF
        MEDIA-N-MEMORY  OF S" Not enough memory to show this file" ENDOF
        MEDIA-N-READ    OF S" The file could not be read" ENDOF
        MEDIA-N-LOCKED  OF S" The file is protected by a password" ENDOF
        >R 0 0 R>
    ENDCASE ;

\ Append to the facts line; it holds a kind name and a size, which always
\ fit, so nothing is ever cut in practice.
: _MDW-ADD  ( a u -- )
    _MDW-LINE-CAP _MDW-LINE-U @ - MIN
    DUP >R _MDW-LINE _MDW-LINE-U @ + SWAP CMOVE R> _MDW-LINE-U +! ;

\ "kind, size": the size as SIZE-FMT gives it, with " bytes" after a bare
\ count.
: _MDW-KIND-SIZE  ( -- a u )
    0 _MDW-LINE-U !
    _MDW-W @ MEDIA-KIND@ MEDIA-KIND-NAME _MDW-ADD
    S" , " _MDW-ADD
    _MDW-W @ MEDIA-SIZE@ DUP SIZE-FMT _MDW-ADD
    1024 < IF S"  bytes" _MDW-ADD THEN
    _MDW-LINE _MDW-LINE-U @ ;

: _MDW-CENTER  ( a u row -- row+1 )
    DUP >R 0 _MDW-COLS @ DRW-TEXT-CENTER R> 1+ ;

\ The facts: the file's name, what it is and how big, and why it shows only
\ this.  A file that could not be opened has no kind and size to tell.
: _MDW-FACTS  ( -- )
    _MDW-ROWS @ 2/ 1- DUP 0< IF DROP 0 THEN               ( row )
    _MDW-W @ MEDIA-NAME@ ROT _MDW-CENTER
    _MDW-W @ MEDIA-KIND@ 0< 0= IF _MDW-KIND-SIZE ROT _MDW-CENTER THEN
    _MDW-W @ MEDIA-NOTE@ _MDW-NOTE-TEXT ROT _MDW-CENTER DROP ;

: _MEDIA-DO-DRAW  ( widget -- )
    DUP _MDW-W !
    WDG-REGION DUP RGN-W _MDW-COLS ! RGN-H _MDW-ROWS !
    _MDW-W @ MEDIA-VIEW-WIDGET@ ?DUP IF
        DUP _MDW-W @ _MEDIA-FOCUS-TO
        _MDW-W @ WDG-REGION WDG-DRAW-IN EXIT
    THEN
    32 0 0 _MDW-ROWS @ _MDW-COLS @ DRW-FILL-RECT
    _MDW-W @ MEDIA-VIEW@ MEDIA-V-FACTS = IF _MDW-FACTS THEN ;

: _MEDIA-DO-HANDLE  ( event widget -- consumed? )
    DUP MEDIA-VIEW-WIDGET@ ?DUP 0= IF 2DROP 0 EXIT THEN
    TUCK SWAP _MEDIA-FOCUS-TO WDG-HANDLE ;

' _MEDIA-DO-DRAW IS _MEDIA-DRAW-D
' _MEDIA-DO-HANDLE IS _MEDIA-HANDLE-D

\ =====================================================================
\  6. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _media-guard

' MEDIA-NEW      CONSTANT _media-new-xt
' MEDIA-CLEAR    CONSTANT _media-clear-xt
' MEDIA-OPEN-VFS CONSTANT _media-open-vfs-xt
' MEDIA-ALT!     CONSTANT _media-alt-xt
' MEDIA-FOLLOW!  CONSTANT _media-follow-xt
' MEDIA-READER!  CONSTANT _media-reader-xt
' MEDIA-FREE     CONSTANT _media-free-xt
' MEDIA-SERVICE  CONSTANT _media-service-xt

: MEDIA-NEW      _media-new-xt      _media-guard WITH-GUARD ;
: MEDIA-CLEAR    _media-clear-xt    _media-guard WITH-GUARD ;
: MEDIA-OPEN-VFS _media-open-vfs-xt _media-guard WITH-GUARD ;
: MEDIA-ALT!     _media-alt-xt      _media-guard WITH-GUARD ;
: MEDIA-FOLLOW!  _media-follow-xt   _media-guard WITH-GUARD ;
: MEDIA-READER!  _media-reader-xt   _media-guard WITH-GUARD ;
: MEDIA-FREE     _media-free-xt     _media-guard WITH-GUARD ;
: MEDIA-SERVICE  _media-service-xt  _media-guard WITH-GUARD ;
[THEN] [THEN]
