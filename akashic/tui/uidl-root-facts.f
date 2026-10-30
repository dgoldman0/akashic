\ =====================================================================
\  uidl-root-facts.f -- what each root of a document's capture read
\ =====================================================================
\
\  The roots a document's snapshot captures are its menus, each
\  collection, data-graphics, status-field and field root, and the dialog
\  it shows.  A root's facts record what its capture read, so that two
\  captures of one root with equal facts are equal: the newest revision
\  among the UIDL elements the capture reads, the revisions of the widget
\  and the model it shows, the context it lays out against, and the
\  geometry it was captured at, which no counter covers.  UIDL's element
\  revisions come from one count every document shares, so an element
\  changed after a capture carries a revision newer than any that capture
\  read, and the newest of them moves.
\
\  Each URF-* word fills one root's record from the descriptor its
\  snapshot module wrote, in the document's own context and before that
\  context changes again.  It reads UIDL's and UIDL-TUI's records
\  directly, as UIDL-TUI does, since each guarded public word costs a
\  guard.  A root whose element or widget cannot be found again records
\  the stamp URF-UNKNOWN, which no capture can match, so that it counts as
\  changed.  The caller fills each record's document token afterwards.
\
\  Record (URF-SIZE bytes, cells only):
\    +0   document token        +8   family
\    +16  source                +24  index
\    +32  generation            +40  key
\    +48  stamp: newest element revision the capture reads
\    +56  the widget's revision
\    +64  the model's or the shown view's revision
\    +72  the context: the screen's size for an overlay, or the count of
\         dialog-element changes for an element dialog
\    +80  row, +88 column, +96 height, +104 width
\    +112 clip row, +120 clip column, +128 clip height, +136 clip width
\    +144 z
\
\  The first URF-IDENTITY-SIZE bytes name the root; the rest are its
\  facts.
\
\  Prefix: URF- (public), _URF- (private)

PROVIDED akashic-tui-uidl-root-facts

REQUIRE uidl-tui.f
REQUIRE uidl-menu-snapshot.f
REQUIRE uidl-collection-snapshot.f
REQUIRE uidl-data-graphics-snapshot.f
REQUIRE uidl-status-field-snapshot.f
REQUIRE uidl-field-snapshot.f
REQUIRE uidl-dialog-snapshot.f
REQUIRE field-model.f
REQUIRE widgets/field.f
REQUIRE widgets/media.f

1 CONSTANT URF-F-MENUS
2 CONSTANT URF-F-COLLECTION
3 CONSTANT URF-F-DATA-GRAPHICS
4 CONSTANT URF-F-STATUS-FIELD
5 CONSTANT URF-F-FIELD
6 CONSTANT URF-F-DIALOG

-1 CONSTANT URF-UNKNOWN

: URF.TOKEN       ( record -- a )      ;
: URF.FAMILY      ( record -- a )   8 + ;
: URF.SOURCE      ( record -- a )  16 + ;
: URF.INDEX       ( record -- a )  24 + ;
: URF.GENERATION  ( record -- a )  32 + ;
: URF.KEY         ( record -- a )  40 + ;
: URF.STAMP       ( record -- a )  48 + ;
: URF.WIDGET-REV  ( record -- a )  56 + ;
: URF.MODEL-REV   ( record -- a )  64 + ;
: URF.CONTEXT     ( record -- a )  72 + ;
: URF.ROW         ( record -- a )  80 + ;
: URF.COLUMN      ( record -- a )  88 + ;
: URF.HEIGHT      ( record -- a )  96 + ;
: URF.WIDTH       ( record -- a ) 104 + ;
: URF.CLIP-ROW    ( record -- a ) 112 + ;
: URF.CLIP-COLUMN ( record -- a ) 120 + ;
: URF.CLIP-HEIGHT ( record -- a ) 128 + ;
: URF.CLIP-WIDTH  ( record -- a ) 136 + ;
: URF.Z           ( record -- a ) 144 + ;

152 CONSTANT URF-SIZE
48 CONSTANT URF-IDENTITY-SIZE

\ ---------------------------------------------------------------------
\  Element revisions
\ ---------------------------------------------------------------------

\ The live element at pool INDEX of the current document, or 0.
: _URF-ELEM  ( index -- elem|0 )
    DUP 0< IF DROP 0 EXIT THEN
    DUP _UDL-ECNT @ < 0= IF DROP 0 EXIT THEN
    _UDL-ELEMSZ * _UDL-ELEMS +
    DUP UE.TYPE @ 0= IF DROP 0 THEN ;

: _URF-REV  ( elem -- revision )
    _UDL-ELEMS - _UDL-ELEMSZ / _UDL-REV-AT @ ;

\ STAMP raised to the revisions of ELEM and every ancestor it has.
: _URF-UP  ( stamp elem -- stamp' )
    BEGIN ?DUP WHILE
        DUP _URF-REV ROT MAX SWAP UE.PARENT @
    REPEAT ;

\ STAMP raised to the revisions of every element below ELEM.
VARIABLE _URF-DOWN-ROOT
: _URF-DOWN-NEXT  ( elem -- next|0 )
    DUP UE.FCHILD @ ?DUP IF NIP EXIT THEN
    BEGIN
        DUP _URF-DOWN-ROOT @ = IF DROP 0 EXIT THEN
        DUP UE.NEXT @ ?DUP IF NIP EXIT THEN
        UE.PARENT @ DUP 0=
    UNTIL ;
: _URF-DOWN  ( stamp elem -- stamp' )
    DUP _URF-DOWN-ROOT !
    UE.FCHILD @ ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _URF-REV ROT MAX SWAP
        _URF-DOWN-NEXT ?DUP 0=
    UNTIL ;

\ ---------------------------------------------------------------------
\  Records
\ ---------------------------------------------------------------------

VARIABLE _URF-R

\ Begin RECORD for a root of FAMILY.
: _URF-BEGIN  ( family record -- )
    DUP _URF-R ! DUP URF-SIZE 0 FILL URF.FAMILY ! ;

: _URF-IDENTITY!  ( source index generation key -- )
    _URF-R @ URF.KEY !
    _URF-R @ URF.GENERATION !
    _URF-R @ URF.INDEX !
    _URF-R @ URF.SOURCE ! ;

: _URF-PLACE!  ( row column height width -- )
    _URF-R @ URF.WIDTH !
    _URF-R @ URF.HEIGHT !
    _URF-R @ URF.COLUMN !
    _URF-R @ URF.ROW ! ;

: _URF-CLIP!  ( row column height width z -- )
    _URF-R @ URF.Z !
    _URF-R @ URF.CLIP-WIDTH !
    _URF-R @ URF.CLIP-HEIGHT !
    _URF-R @ URF.CLIP-COLUMN !
    _URF-R @ URF.CLIP-ROW ! ;

: _URF-UNKNOWN  ( -- )  URF-UNKNOWN _URF-R @ URF.STAMP ! ;

\ The stamp of the element at INDEX and its ancestors; unknown without one.
: _URF-ELEMENT-STAMP!  ( index -- )
    _URF-ELEM ?DUP 0= IF _URF-UNKNOWN EXIT THEN
    0 SWAP _URF-UP _URF-R @ URF.STAMP ! ;

\ The screen's size, as one cell.
: _URF-SCREEN  ( -- cell )  SCR-H 32 LSHIFT SCR-W OR ;

\ The relation that mounts the root named by SOURCE GENERATION KEY.
: _URF-RELATION  ( source generation key -- relation|0 )
    _UTUI-MC-HEAD @
    BEGIN DUP WHILE
        DUP _UTUI-MCR-SOURCE@ 4 PICK =
        OVER _UTUI-MCR-GENERATION@ 4 PICK = AND
        OVER _UTUI-MCR-ROOT-KEY@ 3 PICK = AND IF
            NIP NIP NIP EXIT
        THEN
        _UTUI-MCR-NEXT@
    REPEAT
    NIP NIP NIP ;

\ The widget a mounted root shows, with its revision and the stamp of the
\ element it is mounted under recorded; 0, and the root unknown, when its
\ relation or widget is gone.
: _URF-MOUNTED  ( -- widget|0 )
    _URF-R @ URF.INDEX @ _URF-R @ URF.GENERATION @ _URF-R @ URF.KEY @
        _URF-RELATION
    ?DUP 0= IF _URF-UNKNOWN 0 EXIT THEN
    _UTUI-MCR-WIDGET@ ?DUP 0= IF _URF-UNKNOWN 0 EXIT THEN
    DUP WDG-REVISION _URF-R @ URF.WIDGET-REV !
    _URF-R @ URF.INDEX @ _URF-ELEMENT-STAMP! ;

\ ---------------------------------------------------------------------
\  Families
\ ---------------------------------------------------------------------

\ URF-MENUS ( records-a count record -- )
\   The document's menus as one root: the newest revision among the
\   elements of its COUNT UMSN records at RECORDS-A and their ancestors.
\   Opening a menu, moving focus into or out of one, and laying one out
\   each count a change to the elements they touch.
: URF-MENUS  ( records-a count record -- )
    URF-F-MENUS SWAP _URF-BEGIN
    0 SWAP 0 ?DO                          ( records-a stamp )
        OVER I UMSN-RECORD-SIZE * + UMSN-RECORD-SOURCE-INDEX@
        _URF-ELEM ?DUP 0= IF 2DROP _URF-UNKNOWN UNLOOP EXIT THEN
        _URF-UP
    LOOP
    NIP _URF-R @ URF.STAMP ! ;

\ URF-NOW ( -- stamp )
\   The count of element changes now.  Every element changed later carries
\   a newer revision, since every document and context takes its revisions
\   from one count that nothing resets.
: URF-NOW  ( -- stamp )  _UDL-STAMP @ ;

\ URF-MENUS-SINCE? ( records-a count stamp -- flag )
\   Whether a capture of the document's menus now would give its COUNT UMSN
\   records at RECORDS-A, captured when the count stood at STAMP: each
\   record's element is still there, and none of them, nor any ancestor,
\   nor any child of one of its menus, carries a newer revision; and every
\   menubar the document holds has a record.  A menu's row comes or goes
\   only among its children, and a menubar can appear anywhere; every other
\   change the menus read counts a change to the elements URF-MENUS reads.
VARIABLE _URF-S-STAMP
VARIABLE _URF-S-RECORD
VARIABLE _URF-S-BARS

\ No child of ELEM is newer than the stamp.
: _URF-CHILDREN-SINCE?  ( elem -- flag )
    UE.FCHILD @
    BEGIN ?DUP WHILE
        DUP _URF-REV _URF-S-STAMP @ U> IF DROP 0 EXIT THEN
        UE.NEXT @
    REPEAT -1 ;

\ The count of menubars the document holds.
: _URF-MENUBARS  ( -- n )
    0 _UDL-ECNT @ 0 ?DO
        I _UDL-ELEMSZ * _UDL-ELEMS + UE.TYPE @ UIDL-T-MENUBAR = IF 1+ THEN
    LOOP ;

: URF-MENUS-SINCE?  ( records-a count stamp -- flag )
    _URF-S-STAMP ! 0 _URF-S-BARS !
    0 ?DO
        DUP I UMSN-RECORD-SIZE * + _URF-S-RECORD !
        _URF-S-RECORD @ UMSN-RECORD-SOURCE-INDEX@ _URF-ELEM
        ?DUP 0= IF DROP 0 UNLOOP EXIT THEN
        0 OVER _URF-UP _URF-S-STAMP @ U> IF 2DROP 0 UNLOOP EXIT THEN
        _URF-S-RECORD @ UMSN-RECORD-KIND@ DUP UMSN-K-MENU = IF
            DROP _URF-CHILDREN-SINCE? 0= IF DROP 0 UNLOOP EXIT THEN
        ELSE
            UMSN-K-MENUBAR = IF 1 _URF-S-BARS +! THEN DROP
        THEN
    LOOP DROP
    _URF-MENUBARS _URF-S-BARS @ = ;

\ URF-COLLECTION ( descriptor record -- )
\   A collection root: a direct one reads its element, its ancestors, a
\   tab set's tabs, and the widget the element hosts, or a media element's
\   shown view; a mounted one reads the widget its relation mounts and the
\   element it is mounted under.
: URF-COLLECTION  ( descriptor record -- )
    URF-F-COLLECTION SWAP _URF-BEGIN >R
    R@ UCSN-DESCRIPTOR-SOURCE@ R@ UCSN-DESCRIPTOR-SOURCE-INDEX@
    R@ UCSN-DESCRIPTOR-SOURCE-GENERATION@ R@ UCSN-DESCRIPTOR-ROOT-KEY@
        _URF-IDENTITY!
    R@ UCSN-DESCRIPTOR-ROW@ R@ UCSN-DESCRIPTOR-COLUMN@
    R@ UCSN-DESCRIPTOR-HEIGHT@ R@ UCSN-DESCRIPTOR-WIDTH@ _URF-PLACE!
    R@ UCSN-DESCRIPTOR-CLIP-ROW@ R@ UCSN-DESCRIPTOR-CLIP-COLUMN@
    R@ UCSN-DESCRIPTOR-CLIP-HEIGHT@ R@ UCSN-DESCRIPTOR-CLIP-WIDTH@
    R> UCSN-DESCRIPTOR-Z@ _URF-CLIP!
    _URF-R @ URF.GENERATION @ IF _URF-MOUNTED DROP EXIT THEN
    _URF-R @ URF.INDEX @ _URF-ELEM ?DUP 0= IF _URF-UNKNOWN EXIT THEN
    0 OVER _URF-UP OVER _URF-DOWN _URF-R @ URF.STAMP !
    DUP _UTUI-HOSTED-WIDGET ?DUP IF                    ( elem widget )
        DUP WDG-REVISION _URF-R @ URF.WIDGET-REV !
        OVER UE.TYPE @ UIDL-T-MEDIA = IF
            MEDIA-VIEW-WIDGET@ ?DUP IF
                WDG-REVISION _URF-R @ URF.MODEL-REV !
            THEN
        ELSE DROP THEN
    THEN DROP ;

\ URF-DATA-GRAPHICS ( descriptor record -- )
\   A data-graphics root reads the widget its relation mounts, whose model
\   an application rebinds to change it, and the element it is mounted
\   under.
: URF-DATA-GRAPHICS  ( descriptor record -- )
    URF-F-DATA-GRAPHICS SWAP _URF-BEGIN >R
    R@ UDGSN-DESCRIPTOR-SOURCE@ R@ UDGSN-DESCRIPTOR-SOURCE-INDEX@
    R@ UDGSN-DESCRIPTOR-SOURCE-GENERATION@ R@ UDGSN-DESCRIPTOR-ROOT-KEY@
        _URF-IDENTITY!
    R@ UDGSN-DESCRIPTOR-ROW@ R@ UDGSN-DESCRIPTOR-COLUMN@
    R@ UDGSN-DESCRIPTOR-HEIGHT@ R@ UDGSN-DESCRIPTOR-WIDTH@ _URF-PLACE!
    R@ UDGSN-DESCRIPTOR-CLIP-ROW@ R@ UDGSN-DESCRIPTOR-CLIP-COLUMN@
    R@ UDGSN-DESCRIPTOR-CLIP-HEIGHT@ R@ UDGSN-DESCRIPTOR-CLIP-WIDTH@
    R> UDGSN-DESCRIPTOR-Z@ _URF-CLIP!
    _URF-MOUNTED DROP ;

\ URF-STATUS-FIELD ( descriptor record -- )
\   A status field reads its label, the status element it sits in, and
\   their ancestors.
: URF-STATUS-FIELD  ( descriptor record -- )
    URF-F-STATUS-FIELD SWAP _URF-BEGIN >R
    R@ USFSN-DESCRIPTOR-SOURCE@ R@ USFSN-DESCRIPTOR-SOURCE-INDEX@
    R@ USFSN-DESCRIPTOR-SOURCE-GENERATION@ R@ USFSN-DESCRIPTOR-ROOT-KEY@
        _URF-IDENTITY!
    R@ USFSN-DESCRIPTOR-ROW@ R@ USFSN-DESCRIPTOR-COLUMN@
    R@ USFSN-DESCRIPTOR-HEIGHT@ R@ USFSN-DESCRIPTOR-WIDTH@ _URF-PLACE!
    R@ USFSN-DESCRIPTOR-CLIP-ROW@ R@ USFSN-DESCRIPTOR-CLIP-COLUMN@
    R@ USFSN-DESCRIPTOR-CLIP-HEIGHT@ R@ USFSN-DESCRIPTOR-CLIP-WIDTH@
    R> USFSN-DESCRIPTOR-Z@ _URF-CLIP!
    _URF-R @ URF.INDEX @ _URF-ELEMENT-STAMP! ;

\ The prompt a document shows as its overlay, which the record's key
\ names by instance: its revision, which counts its input's changes, and
\ the screen it lays out against.
: _URF-OVERLAY-PROMPT  ( -- )
    _UTUI-OVERLAY @ ?DUP 0= IF _URF-UNKNOWN EXIT THEN
    _UTUI-OVERLAY-INSTANCE @ _URF-R @ URF.KEY @ <> IF
        DROP _URF-UNKNOWN EXIT
    THEN
    WDG-REVISION _URF-R @ URF.WIDGET-REV !
    _URF-SCREEN _URF-R @ URF.CONTEXT ! ;

\ URF-FIELD ( descriptor record -- )
\   A mounted field reads its widget, the model the widget is bound to,
\   whose revision the application issues, and the element it is mounted
\   under.  The overlay field reads the document's prompt.
: URF-FIELD  ( descriptor record -- )
    URF-F-FIELD SWAP _URF-BEGIN >R
    R@ UFLSN-DESCRIPTOR-SOURCE@ R@ UFLSN-DESCRIPTOR-SOURCE-INDEX@
    R@ UFLSN-DESCRIPTOR-SOURCE-GENERATION@ R@ UFLSN-DESCRIPTOR-ROOT-KEY@
        _URF-IDENTITY!
    R@ UFLSN-DESCRIPTOR-ROW@ R@ UFLSN-DESCRIPTOR-COLUMN@
    R@ UFLSN-DESCRIPTOR-HEIGHT@ R@ UFLSN-DESCRIPTOR-WIDTH@ _URF-PLACE!
    R@ UFLSN-DESCRIPTOR-CLIP-ROW@ R@ UFLSN-DESCRIPTOR-CLIP-COLUMN@
    R@ UFLSN-DESCRIPTOR-CLIP-HEIGHT@ R@ UFLSN-DESCRIPTOR-CLIP-WIDTH@
    R> UFLSN-DESCRIPTOR-Z@ _URF-CLIP!
    _URF-R @ URF.SOURCE @ UFLSN-SOURCE-OVERLAY = IF
        _URF-OVERLAY-PROMPT EXIT
    THEN
    _URF-MOUNTED ?DUP 0= IF EXIT THEN
    FLD-MODEL@ IF UFLD-REVISION@ _URF-R @ URF.MODEL-REV ! ELSE DROP THEN ;

\ URF-DIALOG ( descriptor record -- )
\   A dialog widget reads the widget the document shows, which the
\   record's key names by instance, and the screen.  A dialog element
\   reads itself, its contents and ancestors, the count of dialog-element
\   changes, which every document shares, and the screen.
: URF-DIALOG  ( descriptor record -- )
    URF-F-DIALOG SWAP _URF-BEGIN >R
    R@ UDLSN-DESCRIPTOR-SOURCE@ 0 0 R@ UDLSN-DESCRIPTOR-KEY@ _URF-IDENTITY!
    R@ UDLSN-DESCRIPTOR-ROW@ R@ UDLSN-DESCRIPTOR-COLUMN@
    R@ UDLSN-DESCRIPTOR-HEIGHT@ R@ UDLSN-DESCRIPTOR-WIDTH@ _URF-PLACE!
    0 0 0 0 R> UDLSN-DESCRIPTOR-Z@ _URF-CLIP!
    _URF-SCREEN _URF-R @ URF.CONTEXT !
    _URF-R @ URF.SOURCE @ UDLSN-SOURCE-OVERLAY = IF
        DLG-SHOWN ?DUP 0= IF _URF-UNKNOWN EXIT THEN
        DUP DLG-INSTANCE@ _URF-R @ URF.KEY @ <> IF
            DROP _URF-UNKNOWN EXIT
        THEN
        WDG-REVISION _URF-R @ URF.WIDGET-REV ! EXIT
    THEN
    _URF-R @ URF.KEY @ 1- _URF-ELEM ?DUP 0= IF _URF-UNKNOWN EXIT THEN
    0 OVER _URF-UP SWAP _URF-DOWN _URF-R @ URF.STAMP !
    UTUI-DIALOG-REVISION _URF-R @ URF.MODEL-REV ! ;

\ URF-SAME? ( record-a record-b -- flag )
\   Whether two records describe one root captured from the same state:
\   equal byte for byte, and neither unknown.
: URF-SAME?  ( record-a record-b -- flag )
    OVER URF.STAMP @ URF-UNKNOWN = IF 2DROP 0 EXIT THEN
    DUP URF.STAMP @ URF-UNKNOWN = IF 2DROP 0 EXIT THEN
    URF-SIZE TUCK COMPARE 0= ;

\ URF-ROOT? ( record family source index generation key -- flag )
\   Whether RECORD names the root FAMILY SOURCE INDEX GENERATION KEY,
\   whatever its document.
: URF-ROOT?  ( record family source index generation key -- flag )
    5 PICK URF.KEY @ = >R
    4 PICK URF.GENERATION @ = R> AND >R
    3 PICK URF.INDEX @ = R> AND >R
    2 PICK URF.SOURCE @ = R> AND >R
    OVER URF.FAMILY @ = R> AND NIP ;
