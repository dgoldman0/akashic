\ =====================================================================
\  uidl-menu-snapshot.f -- neutral UIDL-TUI menu-tree snapshots
\ =====================================================================
\
\  Copies the ordinary menubar/menu/item/separator model into bounded
\  caller storage.  The output is renderer-neutral and pointer-free; it
\  carries stable UIDL pool keys, authored sibling order, current state,
\  copied label/shortcut bytes, and resolved UIDL-TUI geometry/style.
\
\  Construction is linear.  One coherent resolved-tree visitor copies
\  authoritative facts into index-addressed caller work storage, then one
\  ascending pool-index pass emits canonical records.  Work entries and
\  their scratch text are pointer-free and never publication candidates.
\
\  Public capture API:
\    UMSN-CAPTURE
\      ( generation work-a work-u work-text-a work-text-u
\        records-a records-u text-a text-u
\        -- record-count text-used status )
\
\  Capture is a synchronous UI-owner operation.  It neither yields nor
\  invokes lifecycle or action callbacks.
\
\  Prefix: UMSN- (neutral contract), _UMSN- (implementation)

PROVIDED akashic-tui-uidl-menu-snapshot

REQUIRE uidl-tui.f
REQUIRE ../text/utf8.f
REQUIRE ../utils/memory-span.f

0 CONSTANT UMSN-S-OK
1 CONSTANT UMSN-S-CAPACITY
2 CONSTANT UMSN-S-UNAVAILABLE
3 CONSTANT UMSN-S-INVALID

: UMSN-STATUS-VALID?  ( status -- flag )  4 U< ;

1 CONSTANT UMSN-SOURCE-UIDL

1 CONSTANT UMSN-K-MENUBAR
2 CONSTANT UMSN-K-MENU
3 CONSTANT UMSN-K-ITEM
4 CONSTANT UMSN-K-SEPARATOR

1  CONSTANT UMSN-F-VISIBLE
2  CONSTANT UMSN-F-ENABLED
4  CONSTANT UMSN-F-FOCUSED
8  CONSTANT UMSN-F-OPEN
16 CONSTANT UMSN-F-SELECTED
32 CONSTANT UMSN-F-PAINTABLE
63 CONSTANT _UMSN-F-MASK

\ Record bytes are native cells.  Text offsets are relative to the caller's
\ copied-text arena.  PARENT is zero for a semantic root and the parent's
\ stable pool index plus one otherwise, so index zero is unambiguous.
\
\   +0   magic               "UMENUSN1"
\   +8   ABI                 1
\   +16  exact record bytes  192
\   +24  snapshot generation (caller-issued, nonzero)
\   +32  source kind         UMSN-SOURCE-UIDL
\   +40  source pool index
\   +48  semantic subkey     0
\   +56  parent index + 1    (0 for menubar)
\   +64  neutral kind
\   +72  state flags
\   +80  authored sibling ordinal
\   +88  label text offset
\   +96  label text bytes
\   +104 shortcut text offset
\   +112 shortcut text bytes
\   +120 copied UTUI resolved record (72 bytes)

0x314E53554E454D55 CONSTANT _UMSN-RECORD-MAGIC
1 CONSTANT _UMSN-RECORD-ABI
192 CONSTANT UMSN-RECORD-SIZE

\ Work entries are indexed by source pool index.  Text offsets address the
\ caller's scratch-text span and are repacked during canonical output.
\
\   +0   kind/presence
\   +8   parent index + 1
\   +16  authored sibling ordinal
\   +24  complete neutral state
\   +32  scratch label offset
\   +40  label bytes
\   +48  scratch shortcut offset
\   +56  shortcut bytes
\   +64  copied UTUI resolved record (72 bytes)

136 CONSTANT UMSN-WORK-ENTRY-SIZE

: _UMSN-R.MAGIC       ( r -- a )       ;
: _UMSN-R.ABI         ( r -- a )   8 + ;
: _UMSN-R.BYTES       ( r -- a )  16 + ;
: _UMSN-R.GENERATION  ( r -- a )  24 + ;
: _UMSN-R.SOURCE      ( r -- a )  32 + ;
: _UMSN-R.INDEX       ( r -- a )  40 + ;
: _UMSN-R.SUBKEY      ( r -- a )  48 + ;
: _UMSN-R.PARENT      ( r -- a )  56 + ;
: _UMSN-R.KIND        ( r -- a )  64 + ;
: _UMSN-R.STATE       ( r -- a )  72 + ;
: _UMSN-R.ORDINAL     ( r -- a )  80 + ;
: _UMSN-R.LABEL-O     ( r -- a )  88 + ;
: _UMSN-R.LABEL-U     ( r -- a )  96 + ;
: _UMSN-R.SHORTCUT-O  ( r -- a ) 104 + ;
: _UMSN-R.SHORTCUT-U  ( r -- a ) 112 + ;
: _UMSN-R.RESOLVED    ( r -- a ) 120 + ;

: _UMSN-W.KIND        ( w -- a )       ;
: _UMSN-W.PARENT      ( w -- a )   8 + ;
: _UMSN-W.ORDINAL     ( w -- a )  16 + ;
: _UMSN-W.STATE       ( w -- a )  24 + ;
: _UMSN-W.LABEL-O     ( w -- a )  32 + ;
: _UMSN-W.LABEL-U     ( w -- a )  40 + ;
: _UMSN-W.SHORTCUT-O  ( w -- a )  48 + ;
: _UMSN-W.SHORTCUT-U  ( w -- a )  56 + ;
: _UMSN-W.RESOLVED    ( w -- a )  64 + ;

: UMSN-RECORD-BYTES  ( -- bytes )  UMSN-RECORD-SIZE ;
: UMSN-WORK-ENTRY-BYTES  ( -- bytes )  UMSN-WORK-ENTRY-SIZE ;

: UMSN-RECORD-GENERATION@  ( r -- generation )
    _UMSN-R.GENERATION @ ;
: UMSN-RECORD-SOURCE-INDEX@  ( r -- index )  _UMSN-R.INDEX @ ;
: UMSN-RECORD-SUBKEY@  ( r -- subkey )  _UMSN-R.SUBKEY @ ;
: UMSN-RECORD-PARENT@  ( r -- parent-index-plus-one )
    _UMSN-R.PARENT @ ;
: UMSN-RECORD-KIND@  ( r -- kind )  _UMSN-R.KIND @ ;
: UMSN-RECORD-STATE@  ( r -- state )  _UMSN-R.STATE @ ;
: UMSN-RECORD-ORDINAL@  ( r -- ordinal )  _UMSN-R.ORDINAL @ ;
: UMSN-RECORD-LABEL-OFFSET@  ( r -- offset )  _UMSN-R.LABEL-O @ ;
: UMSN-RECORD-LABEL-BYTES@  ( r -- bytes )  _UMSN-R.LABEL-U @ ;
: UMSN-RECORD-SHORTCUT-OFFSET@  ( r -- offset )
    _UMSN-R.SHORTCUT-O @ ;
: UMSN-RECORD-SHORTCUT-BYTES@  ( r -- bytes )
    _UMSN-R.SHORTCUT-U @ ;
: UMSN-RECORD-RESOLVED  ( r -- resolved available )
    _UMSN-R.RESOLVED UTUI-RESOLVED-BYTES ;

-1 1 RSHIFT CONSTANT _UMSN-LENGTH-MAX

: _UMSN-SIZED-BYTES  ( count stride -- bytes|0 )
    OVER 0< IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    _UMSN-LENGTH-MAX OVER / 2 PICK U< IF 2DROP 0 EXIT THEN
    * ;

: UMSN-WORK-BYTES  ( element-high-water -- bytes|0 )
    UMSN-WORK-ENTRY-SIZE _UMSN-SIZED-BYTES ;

: UMSN-RECORD-BANK-BYTES  ( record-capacity -- bytes|0 )
    UMSN-RECORD-SIZE _UMSN-SIZED-BYTES ;

CREATE _UMSN-OWNED-START

VARIABLE _UMSN-GENERATION
VARIABLE _UMSN-WORK-A
VARIABLE _UMSN-WORK-U
VARIABLE _UMSN-WORK-CAP
VARIABLE _UMSN-WORK-TEXT-A
VARIABLE _UMSN-WORK-TEXT-U
VARIABLE _UMSN-WORK-TEXT-USED
VARIABLE _UMSN-RECORDS-A
VARIABLE _UMSN-RECORDS-U
VARIABLE _UMSN-RECORD-CAP
VARIABLE _UMSN-TEXT-A
VARIABLE _UMSN-TEXT-U
VARIABLE _UMSN-RANGES-VALID

VARIABLE _UMSN-STATUS
VARIABLE _UMSN-HIGH-WATER
VARIABLE _UMSN-RECORD-COUNT
VARIABLE _UMSN-TEXT-USED
VARIABLE _UMSN-DIRTY-WORK-U
VARIABLE _UMSN-DIRTY-WORK-TEXT-U
VARIABLE _UMSN-DIRTY-RECORD-U
VARIABLE _UMSN-DIRTY-TEXT-U
VARIABLE _UMSN-SCAN-I

VARIABLE _UMSN-V-ELEM
VARIABLE _UMSN-V-INDEX
VARIABLE _UMSN-V-ORDINAL
VARIABLE _UMSN-V-LOCAL
VARIABLE _UMSN-V-EFFECTIVE
VARIABLE _UMSN-V-RESOLVED-A
VARIABLE _UMSN-V-RESOLVED-U
VARIABLE _UMSN-V-PARENT
VARIABLE _UMSN-V-PARENT-KIND
VARIABLE _UMSN-V-KIND
VARIABLE _UMSN-V-STATE
VARIABLE _UMSN-V-WORK
VARIABLE _UMSN-V-LABEL-A
VARIABLE _UMSN-V-LABEL-U
VARIABLE _UMSN-V-SHORTCUT-A
VARIABLE _UMSN-V-SHORTCUT-U
VARIABLE _UMSN-V-LABEL-O
VARIABLE _UMSN-V-SHORTCUT-O
VARIABLE _UMSN-V-NEXT-WORK-TEXT

VARIABLE _UMSN-E-INDEX
VARIABLE _UMSN-E-WORK
VARIABLE _UMSN-E-RECORD
VARIABLE _UMSN-E-KIND
VARIABLE _UMSN-E-PARENT
VARIABLE _UMSN-E-ORDINAL
VARIABLE _UMSN-E-STATE
VARIABLE _UMSN-E-WORK-LABEL-O
VARIABLE _UMSN-E-LABEL-U
VARIABLE _UMSN-E-WORK-SHORTCUT-O
VARIABLE _UMSN-E-SHORTCUT-U
VARIABLE _UMSN-E-LABEL-O
VARIABLE _UMSN-E-SHORTCUT-O
VARIABLE _UMSN-E-NEXT-TEXT

VARIABLE _UMSN-TV-A
VARIABLE _UMSN-TV-U
VARIABLE _UMSN-TV-I

VARIABLE _UMSN-OWNED-LIMIT

: _UMSN-ALIGNED?  ( address -- flag )  7 AND 0= ;

: _UMSN-OPTIONAL-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _UMSN-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

: _UMSN-OWNED-DISJOINT?  ( address length -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    _UMSN-OWNED-LIMIT @ DUP _UMSN-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _UMSN-OWNED-START - >R
    2DUP _UMSN-OWNED-START R> MSPAN-OVERLAP? 0= NIP NIP ;

: _UMSN-AUTHORITY-DISJOINT?  ( address length -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    2DUP _UMSN-OWNED-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    UTUI-STORAGE-DISJOINT? ;

: _UMSN-RANGES?  ( -- flag )
    _UMSN-GENERATION @ 0= IF 0 EXIT THEN

    _UMSN-WORK-A @ _UMSN-WORK-U @ _UMSN-OPTIONAL-SPAN? 0= IF
        0 EXIT
    THEN
    _UMSN-WORK-U @ UMSN-WORK-ENTRY-SIZE MOD IF 0 EXIT THEN
    _UMSN-WORK-U @ IF
        _UMSN-WORK-A @ _UMSN-ALIGNED? 0= IF 0 EXIT THEN
    THEN

    _UMSN-WORK-TEXT-A @ _UMSN-WORK-TEXT-U @
        _UMSN-OPTIONAL-SPAN? 0= IF 0 EXIT THEN

    _UMSN-RECORDS-A @ _UMSN-RECORDS-U @ _UMSN-OPTIONAL-SPAN? 0= IF
        0 EXIT
    THEN
    _UMSN-RECORDS-U @ UMSN-RECORD-SIZE MOD IF 0 EXIT THEN
    _UMSN-RECORDS-U @ IF
        _UMSN-RECORDS-A @ _UMSN-ALIGNED? 0= IF 0 EXIT THEN
    THEN

    _UMSN-TEXT-A @ _UMSN-TEXT-U @ _UMSN-OPTIONAL-SPAN? 0= IF
        0 EXIT
    THEN

    _UMSN-WORK-A @ _UMSN-WORK-U @ _UMSN-AUTHORITY-DISJOINT? 0= IF
        0 EXIT
    THEN
    _UMSN-WORK-TEXT-A @ _UMSN-WORK-TEXT-U @
        _UMSN-AUTHORITY-DISJOINT? 0= IF 0 EXIT THEN
    _UMSN-RECORDS-A @ _UMSN-RECORDS-U @
        _UMSN-AUTHORITY-DISJOINT? 0= IF 0 EXIT THEN
    _UMSN-TEXT-A @ _UMSN-TEXT-U @ _UMSN-AUTHORITY-DISJOINT? 0= IF
        0 EXIT
    THEN

    _UMSN-WORK-A @ _UMSN-WORK-U @
        _UMSN-WORK-TEXT-A @ _UMSN-WORK-TEXT-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    _UMSN-WORK-A @ _UMSN-WORK-U @
        _UMSN-RECORDS-A @ _UMSN-RECORDS-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    _UMSN-WORK-A @ _UMSN-WORK-U @
        _UMSN-TEXT-A @ _UMSN-TEXT-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _UMSN-WORK-TEXT-A @ _UMSN-WORK-TEXT-U @
        _UMSN-RECORDS-A @ _UMSN-RECORDS-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    _UMSN-WORK-TEXT-A @ _UMSN-WORK-TEXT-U @
        _UMSN-TEXT-A @ _UMSN-TEXT-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _UMSN-RECORDS-A @ _UMSN-RECORDS-U @
        _UMSN-TEXT-A @ _UMSN-TEXT-U @ MSPAN-OVERLAP? 0= ;

: _UMSN-WORK-AT  ( index -- work )
    UMSN-WORK-ENTRY-SIZE * _UMSN-WORK-A @ + ;

: _UMSN-RECORD-AT  ( ordinal -- record )
    UMSN-RECORD-SIZE * _UMSN-RECORDS-A @ + ;

: _UMSN-SET-CAPACITY  ( -- )
    _UMSN-STATUS @ UMSN-S-OK = IF UMSN-S-CAPACITY _UMSN-STATUS ! THEN ;

: _UMSN-SET-UNAVAILABLE  ( -- )
    _UMSN-STATUS @ UMSN-S-OK = IF
        UMSN-S-UNAVAILABLE _UMSN-STATUS !
    THEN ;

: _UMSN-SET-INVALID  ( -- )  UMSN-S-INVALID _UMSN-STATUS ! ;

: _UMSN-PREPARE-WORK?  ( -- flag )
    \ Parent classification reads KIND from any current UIDL predecessor, so
    \ initialize exactly the document prefix that the coherent tree visit may
    \ address.  Record the prefix before FILL so a caught partial write is
    \ scrubbed by the ordinary failure path.
    UIDL-ELEM-COUNT DUP 0< IF DROP _UMSN-SET-INVALID 0 EXIT THEN
    DUP _UMSN-WORK-CAP @ U> IF DROP _UMSN-SET-CAPACITY 0 EXIT THEN
    DUP 0= IF DROP -1 EXIT THEN
    UMSN-WORK-BYTES DUP 0= IF DROP _UMSN-SET-INVALID 0 EXIT THEN
    DUP _UMSN-DIRTY-WORK-U !
    _UMSN-WORK-A @ SWAP 0 FILL
    -1 ;

: _UMSN-CLEAR-PARTIAL  ( -- )
    _UMSN-RANGES-VALID @ 0= IF EXIT THEN
    _UMSN-DIRTY-WORK-U @ ?DUP IF
        _UMSN-WORK-A @ SWAP 0 FILL
    THEN
    _UMSN-DIRTY-WORK-TEXT-U @ ?DUP IF
        _UMSN-WORK-TEXT-A @ SWAP 0 FILL
    THEN
    _UMSN-DIRTY-RECORD-U @ ?DUP IF
        _UMSN-RECORDS-A @ SWAP 0 FILL
    THEN
    _UMSN-DIRTY-TEXT-U @ ?DUP IF
        _UMSN-TEXT-A @ SWAP 0 FILL
    THEN ;

: _UMSN-TEXT?  ( address length -- flag )
    _UMSN-TV-U ! _UMSN-TV-A !
    _UMSN-TV-U @ 0< IF 0 EXIT THEN
    _UMSN-TV-U @ 0= IF -1 EXIT THEN
    _UMSN-TV-A @ 0= IF 0 EXIT THEN
    _UMSN-TV-A @ _UMSN-TV-U @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _UMSN-TV-A @ _UMSN-TV-U @ UTF8-VALID? 0= IF 0 EXIT THEN
    0 _UMSN-TV-I !
    BEGIN _UMSN-TV-I @ _UMSN-TV-U @ < WHILE
        _UMSN-TV-A @ _UMSN-TV-I @ + C@
        DUP 32 < SWAP 127 = OR IF 0 EXIT THEN
        1 _UMSN-TV-I +!
    REPEAT
    -1 ;

: _UMSN-BOOL?  ( flag -- valid )
    DUP 0= SWAP -1 = OR ;

\ =====================================================================
\  Pass 1 -- one coherent resolved-tree visitor
\ =====================================================================

: _UMSN-V-ARGS?  ( -- flag )
    _UMSN-V-INDEX @ 0< _UMSN-V-ORDINAL @ 0< OR IF 0 EXIT THEN
    _UMSN-V-LOCAL @ _UMSN-BOOL? 0= IF 0 EXIT THEN
    _UMSN-V-EFFECTIVE @ _UMSN-BOOL? 0= IF 0 EXIT THEN
    _UMSN-V-EFFECTIVE @ _UMSN-V-LOCAL @ 0= AND IF 0 EXIT THEN
    _UMSN-V-RESOLVED-U @ DUP 0= SWAP UTUI-RESOLVED-SIZE = OR
        0= IF 0 EXIT THEN
    _UMSN-V-RESOLVED-U @ 0= _UMSN-V-EFFECTIVE @ AND IF 0 EXIT THEN
    _UMSN-V-ELEM @ UIDL-ELEM-INDEX? 0= IF DROP 0 EXIT THEN
    _UMSN-V-INDEX @ = ;

: _UMSN-V-INDEX?  ( -- flag )
    _UMSN-V-INDEX @ _UMSN-WORK-CAP @ U< 0= IF
        _UMSN-SET-CAPACITY 0 EXIT
    THEN
    _UMSN-V-INDEX @ 1+ DUP _UMSN-HIGH-WATER @ U> IF
        _UMSN-HIGH-WATER !
    ELSE
        DROP
    THEN
    -1 ;

: _UMSN-V-LOAD-PARENT?  ( -- flag )
    0 _UMSN-V-PARENT ! 0 _UMSN-V-PARENT-KIND !
    _UMSN-V-ELEM @ UIDL-PARENT ?DUP IF
        DUP UIDL-ELEM-INDEX? 0= IF 2DROP 0 EXIT THEN
        DUP _UMSN-WORK-CAP @ U< 0= IF 2DROP 0 EXIT THEN
        DUP 1+ _UMSN-V-PARENT !
        _UMSN-WORK-AT _UMSN-W.KIND @ _UMSN-V-PARENT-KIND !
        DROP
    THEN
    -1 ;

: _UMSN-V-CLASSIFY?  ( -- semantic-entry? )
    0 _UMSN-V-KIND !
    _UMSN-V-ELEM @ UIDL-TYPE
    _UMSN-V-PARENT-KIND @ UMSN-K-MENUBAR = IF
        UIDL-T-MENU <> IF _UMSN-SET-INVALID 0 EXIT THEN
        UMSN-K-MENU _UMSN-V-KIND ! -1 EXIT
    THEN
    _UMSN-V-PARENT-KIND @ UMSN-K-MENU = IF
        DUP UIDL-T-ITEM = IF
            DROP UMSN-K-ITEM
        ELSE
            UIDL-T-SEPARATOR = IF UMSN-K-SEPARATOR
            ELSE _UMSN-SET-INVALID 0 EXIT THEN
        THEN
        _UMSN-V-KIND !
        _UMSN-V-ELEM @ UIDL-FIRST-CHILD IF
            _UMSN-SET-INVALID 0 EXIT
        THEN
        _UMSN-V-ELEM @ _UTUI-MENU-ROW? 0= IF
            0 _UMSN-V-KIND ! 0 EXIT
        THEN
        -1 EXIT
    THEN
    _UMSN-V-PARENT-KIND @ DUP UMSN-K-ITEM =
        SWAP UMSN-K-SEPARATOR = OR IF
        DROP _UMSN-SET-INVALID 0 EXIT
    THEN
    UIDL-T-MENUBAR = IF
        0 _UMSN-V-PARENT !
        UMSN-K-MENUBAR _UMSN-V-KIND ! -1 EXIT
    THEN
    0 ;

: _UMSN-V-BUILD-STATE  ( -- )
    0 _UMSN-V-STATE !
    _UMSN-V-LOCAL @ IF UMSN-F-VISIBLE _UMSN-V-STATE +! THEN
    _UMSN-V-EFFECTIVE @ IF UMSN-F-PAINTABLE _UMSN-V-STATE +! THEN
    _UMSN-V-KIND @ UMSN-K-SEPARATOR <> IF
        UMSN-F-ENABLED _UMSN-V-STATE +!
    THEN
    _UMSN-V-KIND @ DUP UMSN-K-MENU = SWAP UMSN-K-ITEM = OR IF
        _UMSN-V-ELEM @ _UTUI-FOCUS-P @ = IF
            UMSN-F-FOCUSED _UMSN-V-STATE +!
        THEN
    THEN
    _UMSN-V-KIND @ UMSN-K-MENU = IF
        _UMSN-V-ELEM @ _UTUI-MENU-OPEN @ =
        _UMSN-V-EFFECTIVE @ AND IF UMSN-F-OPEN _UMSN-V-STATE +! THEN
        _UMSN-V-ELEM @ _UTUI-FOCUS-P @ =
        _UMSN-V-EFFECTIVE @ AND IF
            UMSN-F-SELECTED _UMSN-V-STATE +!
        THEN
    THEN
    _UMSN-V-KIND @ UMSN-K-ITEM = IF
        _UMSN-V-ELEM @ _UTUI-FOCUS-P @ =
        _UMSN-V-EFFECTIVE @ AND IF
            UMSN-F-SELECTED _UMSN-V-STATE +!
        THEN
    THEN ;

: _UMSN-V-WRITE-BASE?  ( -- flag )
    _UMSN-V-INDEX @ _UMSN-WORK-AT DUP _UMSN-V-WORK !
    DUP _UMSN-W.KIND @ IF DROP 0 EXIT THEN
    _UMSN-V-PARENT @ OVER _UMSN-W.PARENT !
    _UMSN-V-ORDINAL @ OVER _UMSN-W.ORDINAL !
    _UMSN-V-STATE @ OVER _UMSN-W.STATE !
    _UMSN-V-KIND @ SWAP _UMSN-W.KIND !
    -1 ;

: _UMSN-V-MARK-PARENT-SELECTED  ( -- )
    _UMSN-V-KIND @ UMSN-K-ITEM <> IF EXIT THEN
    _UMSN-V-ELEM @ _UTUI-FOCUS-P @ <> IF EXIT THEN
    _UMSN-V-PARENT @ DUP 0= IF DROP EXIT THEN
    1- _UMSN-WORK-AT DUP _UMSN-W.STATE @
    DUP UMSN-F-PAINTABLE AND 0= IF 2DROP EXIT THEN
    UMSN-F-SELECTED OR SWAP _UMSN-W.STATE ! ;

: _UMSN-V-READ-TEXTS?  ( -- flag )
    0 _UMSN-V-LABEL-A ! 0 _UMSN-V-LABEL-U !
    0 _UMSN-V-SHORTCUT-A ! 0 _UMSN-V-SHORTCUT-U !
    _UMSN-V-KIND @ UMSN-K-MENU = IF
        _UMSN-V-ELEM @ S" label" UIDL-ATTR IF
            _UMSN-V-LABEL-U ! _UMSN-V-LABEL-A !
        ELSE
            2DROP 0 EXIT
        THEN
    THEN
    _UMSN-V-KIND @ UMSN-K-ITEM = IF
        _UMSN-V-ELEM @ UIDL-TEXT@
        _UMSN-V-LABEL-U ! _UMSN-V-LABEL-A !
        _UMSN-V-ELEM @ S" key" UIDL-ATTR IF
            _UMSN-V-SHORTCUT-U ! _UMSN-V-SHORTCUT-A !
        ELSE
            2DROP
        THEN
    THEN
    _UMSN-V-KIND @ DUP UMSN-K-MENU = SWAP UMSN-K-ITEM = OR IF
        _UMSN-V-LABEL-U @ 0> 0= IF 0 EXIT THEN
    THEN
    _UMSN-V-LABEL-A @ _UMSN-V-LABEL-U @ _UMSN-TEXT? 0= IF
        0 EXIT
    THEN
    _UMSN-V-SHORTCUT-A @ _UMSN-V-SHORTCUT-U @ _UMSN-TEXT? ;

: _UMSN-V-PREFLIGHT-WORK-TEXT?  ( -- flag )
    _UMSN-WORK-TEXT-USED @ _UMSN-V-LABEL-O !
    _UMSN-WORK-TEXT-USED @ _UMSN-V-LABEL-U @ _UMSN-UADD? 0= IF
        DROP _UMSN-SET-CAPACITY 0 EXIT
    THEN
    DUP _UMSN-V-SHORTCUT-O !
    _UMSN-V-SHORTCUT-U @ _UMSN-UADD? 0= IF
        DROP _UMSN-SET-CAPACITY 0 EXIT
    THEN
    DUP _UMSN-WORK-TEXT-U @ U> IF
        DROP _UMSN-SET-CAPACITY 0 EXIT
    THEN
    _UMSN-V-NEXT-WORK-TEXT !
    -1 ;

\ A bound integer label may be borrowed from UIDL semantic conversion
\ scratch rather than persistent UIDL storage.  Keep both borrowed strings
\ disjoint from the complete append range so the first CMOVE cannot corrupt
\ the source of either copy.
: _UMSN-V-TEXT-SOURCES-DISJOINT?  ( -- flag )
    _UMSN-V-LABEL-A @ _UMSN-V-LABEL-U @
    _UMSN-WORK-TEXT-A @ _UMSN-WORK-TEXT-USED @ +
    _UMSN-V-NEXT-WORK-TEXT @ _UMSN-WORK-TEXT-USED @ -
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _UMSN-V-SHORTCUT-A @ _UMSN-V-SHORTCUT-U @
    _UMSN-WORK-TEXT-A @ _UMSN-WORK-TEXT-USED @ +
    _UMSN-V-NEXT-WORK-TEXT @ _UMSN-WORK-TEXT-USED @ -
        MSPAN-OVERLAP? 0= ;

: _UMSN-V-COPY-TEXT  ( -- )
    _UMSN-V-NEXT-WORK-TEXT @ _UMSN-DIRTY-WORK-TEXT-U !
    _UMSN-V-LABEL-U @ IF
        _UMSN-V-LABEL-A @
        _UMSN-WORK-TEXT-A @ _UMSN-V-LABEL-O @ +
        _UMSN-V-LABEL-U @ CMOVE
    THEN
    _UMSN-V-SHORTCUT-U @ IF
        _UMSN-V-SHORTCUT-A @
        _UMSN-WORK-TEXT-A @ _UMSN-V-SHORTCUT-O @ +
        _UMSN-V-SHORTCUT-U @ CMOVE
    THEN
    _UMSN-V-LABEL-O @ _UMSN-V-WORK @ _UMSN-W.LABEL-O !
    _UMSN-V-LABEL-U @ _UMSN-V-WORK @ _UMSN-W.LABEL-U !
    _UMSN-V-SHORTCUT-O @ _UMSN-V-WORK @ _UMSN-W.SHORTCUT-O !
    _UMSN-V-SHORTCUT-U @ _UMSN-V-WORK @ _UMSN-W.SHORTCUT-U !
    _UMSN-V-NEXT-WORK-TEXT @ _UMSN-WORK-TEXT-USED ! ;

: _UMSN-V-RESOLVED?  ( -- flag )
    _UMSN-V-RESOLVED-U @ 0= IF
        _UMSN-SET-UNAVAILABLE 0 EXIT
    THEN
    _UMSN-V-RESOLVED-U @ UTUI-RESOLVED-SIZE <> IF
        _UMSN-SET-INVALID 0 EXIT
    THEN
    _UMSN-V-RESOLVED-A @ DUP 0= IF DROP _UMSN-SET-INVALID 0 EXIT THEN
    DUP _UMSN-ALIGNED? 0= IF DROP _UMSN-SET-INVALID 0 EXIT THEN
    DUP UTUI-RESOLVED-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP _UMSN-SET-INVALID 0 EXIT
    THEN
    DUP UTUI-RESOLVED-SIZE UTUI-RESOLVED-VALID? 0= IF
        DROP _UMSN-SET-INVALID 0 EXIT
    THEN
    _UMSN-V-WORK @ _UMSN-W.RESOLVED UTUI-RESOLVED-SIZE CMOVE
    -1 ;

: _UMSN-TREE-VISITOR
    ( elem source-index sibling-ordinal local-visible effective-visible resolved available -- )
    _UMSN-V-RESOLVED-U ! _UMSN-V-RESOLVED-A !
    _UMSN-V-EFFECTIVE ! _UMSN-V-LOCAL ! _UMSN-V-ORDINAL !
    _UMSN-V-INDEX ! _UMSN-V-ELEM !
    _UMSN-STATUS @ DUP UMSN-S-CAPACITY =
        SWAP UMSN-S-INVALID = OR IF EXIT THEN
    _UMSN-V-ARGS? 0= IF _UMSN-SET-INVALID EXIT THEN
    _UMSN-V-INDEX? 0= IF EXIT THEN
    _UMSN-V-LOAD-PARENT? 0= IF _UMSN-SET-INVALID EXIT THEN
    _UMSN-V-CLASSIFY? 0= IF EXIT THEN
    _UMSN-V-BUILD-STATE
    _UMSN-V-WRITE-BASE? 0= IF _UMSN-SET-INVALID EXIT THEN
    _UMSN-V-MARK-PARENT-SELECTED
    _UMSN-V-RESOLVED? 0= IF EXIT THEN
    \ Copy resolved state before UIDL-TEXT@ can lend numeric scratch.
    _UMSN-V-READ-TEXTS? 0= IF _UMSN-SET-INVALID EXIT THEN
    _UMSN-V-PREFLIGHT-WORK-TEXT? 0= IF EXIT THEN
    _UMSN-V-TEXT-SOURCES-DISJOINT? 0= IF _UMSN-SET-INVALID EXIT THEN
    _UMSN-V-COPY-TEXT ;

\ =====================================================================
\  Pass 2 -- canonical ascending-key record emission
\ =====================================================================

: _UMSN-WORK-TEXT-SPAN?  ( offset length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    OVER 0< IF 2DROP 0 EXIT THEN
    _UMSN-UADD? 0= IF DROP 0 EXIT THEN
    DUP _UMSN-WORK-TEXT-USED @ U> IF DROP 0 EXIT THEN
    _UMSN-WORK-TEXT-U @ U> 0= ;

: _UMSN-E-STATE?  ( -- flag )
    _UMSN-E-STATE @ _UMSN-F-MASK INVERT AND IF 0 EXIT THEN
    _UMSN-E-STATE @ UMSN-F-PAINTABLE AND
    _UMSN-E-STATE @ UMSN-F-VISIBLE AND 0= AND IF 0 EXIT THEN
    _UMSN-E-STATE @ UMSN-F-OPEN UMSN-F-SELECTED OR AND
    _UMSN-E-STATE @ UMSN-F-PAINTABLE AND 0= AND IF 0 EXIT THEN
    _UMSN-E-KIND @ UMSN-K-MENUBAR = IF
        _UMSN-E-STATE @
        UMSN-F-VISIBLE UMSN-F-ENABLED OR UMSN-F-PAINTABLE OR
        INVERT AND 0=
        _UMSN-E-STATE @ UMSN-F-ENABLED AND 0<> AND EXIT
    THEN
    _UMSN-E-KIND @ UMSN-K-MENU = IF
        _UMSN-E-STATE @ UMSN-F-ENABLED AND 0<> EXIT
    THEN
    _UMSN-E-KIND @ UMSN-K-ITEM = IF
        _UMSN-E-STATE @
        UMSN-F-VISIBLE UMSN-F-ENABLED OR UMSN-F-FOCUSED OR
        UMSN-F-SELECTED OR UMSN-F-PAINTABLE OR INVERT AND 0=
        _UMSN-E-STATE @ UMSN-F-ENABLED AND 0<> AND EXIT
    THEN
    _UMSN-E-KIND @ UMSN-K-SEPARATOR = IF
        _UMSN-E-STATE @
        UMSN-F-VISIBLE UMSN-F-PAINTABLE OR INVERT AND 0= EXIT
    THEN
    0 ;

: _UMSN-E-TEXT-SHAPE?  ( -- flag )
    _UMSN-E-KIND @ UMSN-K-MENU = IF
        _UMSN-E-LABEL-U @ 0>
        _UMSN-E-SHORTCUT-U @ 0= AND 0= IF 0 EXIT THEN
    THEN
    _UMSN-E-KIND @ UMSN-K-ITEM = IF
        _UMSN-E-LABEL-U @ 0> 0= IF 0 EXIT THEN
    THEN
    _UMSN-E-KIND @ DUP UMSN-K-MENUBAR =
        SWAP UMSN-K-SEPARATOR = OR IF
        _UMSN-E-LABEL-U @ _UMSN-E-SHORTCUT-U @ OR IF 0 EXIT THEN
    THEN
    _UMSN-E-WORK-LABEL-O @ _UMSN-E-LABEL-U @
        _UMSN-WORK-TEXT-SPAN? 0= IF 0 EXIT THEN
    _UMSN-E-WORK-SHORTCUT-O @ _UMSN-E-SHORTCUT-U @
        _UMSN-WORK-TEXT-SPAN? 0= IF 0 EXIT THEN
    _UMSN-E-WORK-LABEL-O @ _UMSN-E-LABEL-U @ _UMSN-UADD? 0= IF
        DROP 0 EXIT
    THEN
    _UMSN-E-WORK-SHORTCUT-O @ = ;

: _UMSN-E-LOAD  ( index work -- )
    _UMSN-E-WORK ! _UMSN-E-INDEX !
    _UMSN-E-WORK @ _UMSN-W.KIND @ _UMSN-E-KIND !
    _UMSN-E-WORK @ _UMSN-W.PARENT @ _UMSN-E-PARENT !
    _UMSN-E-WORK @ _UMSN-W.ORDINAL @ _UMSN-E-ORDINAL !
    _UMSN-E-WORK @ _UMSN-W.STATE @ _UMSN-E-STATE !
    _UMSN-E-WORK @ _UMSN-W.LABEL-O @ _UMSN-E-WORK-LABEL-O !
    _UMSN-E-WORK @ _UMSN-W.LABEL-U @ _UMSN-E-LABEL-U !
    _UMSN-E-WORK @ _UMSN-W.SHORTCUT-O @ _UMSN-E-WORK-SHORTCUT-O !
    _UMSN-E-WORK @ _UMSN-W.SHORTCUT-U @ _UMSN-E-SHORTCUT-U ! ;

: _UMSN-E-WORK?  ( -- flag )
    _UMSN-E-KIND @ DUP UMSN-K-MENUBAR <
        SWAP UMSN-K-SEPARATOR > OR IF 0 EXIT THEN
    _UMSN-E-PARENT @ 0< _UMSN-E-ORDINAL @ 0< OR IF 0 EXIT THEN
    _UMSN-E-KIND @ UMSN-K-MENUBAR = IF
        _UMSN-E-PARENT @ IF 0 EXIT THEN
    ELSE
        _UMSN-E-PARENT @ 0= IF 0 EXIT THEN
    THEN
    _UMSN-E-STATE? 0= IF 0 EXIT THEN
    _UMSN-E-TEXT-SHAPE? 0= IF 0 EXIT THEN
    _UMSN-E-WORK @ _UMSN-W.RESOLVED UTUI-RESOLVED-SIZE
        UTUI-RESOLVED-VALID? ;

: _UMSN-E-PREFLIGHT-TEXT?  ( -- flag )
    _UMSN-TEXT-USED @ _UMSN-E-LABEL-O !
    _UMSN-TEXT-USED @ _UMSN-E-LABEL-U @ _UMSN-UADD? 0= IF
        DROP _UMSN-SET-CAPACITY 0 EXIT
    THEN
    DUP _UMSN-E-SHORTCUT-O !
    _UMSN-E-SHORTCUT-U @ _UMSN-UADD? 0= IF
        DROP _UMSN-SET-CAPACITY 0 EXIT
    THEN
    DUP _UMSN-TEXT-U @ U> IF
        DROP _UMSN-SET-CAPACITY 0 EXIT
    THEN
    _UMSN-E-NEXT-TEXT !
    -1 ;

: _UMSN-E-COPY-TEXT  ( -- )
    _UMSN-E-LABEL-U @ IF
        _UMSN-WORK-TEXT-A @ _UMSN-E-WORK-LABEL-O @ +
        _UMSN-TEXT-A @ _UMSN-E-LABEL-O @ +
        _UMSN-E-LABEL-U @ CMOVE
    THEN
    _UMSN-E-SHORTCUT-U @ IF
        _UMSN-WORK-TEXT-A @ _UMSN-E-WORK-SHORTCUT-O @ +
        _UMSN-TEXT-A @ _UMSN-E-SHORTCUT-O @ +
        _UMSN-E-SHORTCUT-U @ CMOVE
    THEN ;

: _UMSN-WRITE-RECORD  ( -- )
    _UMSN-RECORD-COUNT @ _UMSN-RECORD-AT _UMSN-E-RECORD !
    _UMSN-RECORD-COUNT @ 1+ UMSN-RECORD-SIZE *
        _UMSN-DIRTY-RECORD-U !
    _UMSN-E-RECORD @ UMSN-RECORD-SIZE 0 FILL
    _UMSN-E-NEXT-TEXT @ _UMSN-DIRTY-TEXT-U !
    _UMSN-E-COPY-TEXT

    _UMSN-RECORD-ABI _UMSN-E-RECORD @ _UMSN-R.ABI !
    UMSN-RECORD-SIZE _UMSN-E-RECORD @ _UMSN-R.BYTES !
    _UMSN-GENERATION @ _UMSN-E-RECORD @ _UMSN-R.GENERATION !
    UMSN-SOURCE-UIDL _UMSN-E-RECORD @ _UMSN-R.SOURCE !
    _UMSN-E-INDEX @ _UMSN-E-RECORD @ _UMSN-R.INDEX !
    0 _UMSN-E-RECORD @ _UMSN-R.SUBKEY !
    _UMSN-E-PARENT @ _UMSN-E-RECORD @ _UMSN-R.PARENT !
    _UMSN-E-KIND @ _UMSN-E-RECORD @ _UMSN-R.KIND !
    _UMSN-E-STATE @ _UMSN-E-RECORD @ _UMSN-R.STATE !
    _UMSN-E-ORDINAL @ _UMSN-E-RECORD @ _UMSN-R.ORDINAL !
    _UMSN-E-LABEL-O @ _UMSN-E-RECORD @ _UMSN-R.LABEL-O !
    _UMSN-E-LABEL-U @ _UMSN-E-RECORD @ _UMSN-R.LABEL-U !
    _UMSN-E-SHORTCUT-O @ _UMSN-E-RECORD @ _UMSN-R.SHORTCUT-O !
    _UMSN-E-SHORTCUT-U @ _UMSN-E-RECORD @ _UMSN-R.SHORTCUT-U !
    _UMSN-E-WORK @ _UMSN-W.RESOLVED
        _UMSN-E-RECORD @ _UMSN-R.RESOLVED UTUI-RESOLVED-SIZE CMOVE
    _UMSN-RECORD-MAGIC _UMSN-E-RECORD @ _UMSN-R.MAGIC !

    _UMSN-E-NEXT-TEXT @ _UMSN-TEXT-USED !
    1 _UMSN-RECORD-COUNT +! ;

: _UMSN-EMIT-ONE  ( index work -- )
    _UMSN-E-LOAD
    _UMSN-RECORD-COUNT @ _UMSN-RECORD-CAP @ U< 0= IF
        _UMSN-SET-CAPACITY EXIT
    THEN
    _UMSN-E-WORK? 0= IF _UMSN-SET-INVALID EXIT THEN
    _UMSN-E-PREFLIGHT-TEXT? 0= IF EXIT THEN
    _UMSN-WRITE-RECORD ;

: _UMSN-EMIT-CANONICAL  ( -- )
    0 _UMSN-SCAN-I !
    BEGIN _UMSN-SCAN-I @ _UMSN-HIGH-WATER @ < WHILE
        _UMSN-SCAN-I @ _UMSN-WORK-AT DUP _UMSN-W.KIND @ IF
            _UMSN-SCAN-I @ SWAP _UMSN-EMIT-ONE
            _UMSN-STATUS @ UMSN-S-OK <> IF EXIT THEN
        ELSE
            DROP
        THEN
        1 _UMSN-SCAN-I +!
    REPEAT ;

\ =====================================================================
\  Capture orchestration
\ =====================================================================

: _UMSN-FAIL-RESULT  ( -- 0 0 status )
    _UMSN-CLEAR-PARTIAL
    0 0 _UMSN-STATUS @ ;

: _UMSN-MAP-TREE-STATUS  ( tree-status -- )
    DUP UTUI-RESOLVED-S-OK = IF DROP EXIT THEN
    UTUI-RESOLVED-S-UNAVAILABLE = IF
        _UMSN-SET-UNAVAILABLE
    ELSE
        _UMSN-SET-INVALID
    THEN ;

: _UMSN-CAPTURE-BODY  ( -- record-count text-used status )
    UMSN-S-OK _UMSN-STATUS !
    0 _UMSN-HIGH-WATER !
    0 _UMSN-WORK-TEXT-USED ! 0 _UMSN-RECORD-COUNT !
    0 _UMSN-TEXT-USED ! 0 _UMSN-DIRTY-WORK-U !
    0 _UMSN-DIRTY-WORK-TEXT-U !
    0 _UMSN-DIRTY-RECORD-U ! 0 _UMSN-DIRTY-TEXT-U !

    _UMSN-PREPARE-WORK? 0= IF _UMSN-FAIL-RESULT EXIT THEN

    ['] _UMSN-TREE-VISITOR UTUI-RESOLVED-TREE-EACH
        _UMSN-MAP-TREE-STATUS
    _UMSN-STATUS @ UMSN-S-OK <> IF _UMSN-FAIL-RESULT EXIT THEN

    _UMSN-EMIT-CANONICAL
    _UMSN-STATUS @ UMSN-S-OK <> IF _UMSN-FAIL-RESULT EXIT THEN
    _UMSN-RECORD-COUNT @ _UMSN-TEXT-USED @ UMSN-S-OK ;

: _UMSN-SCRUB  ( -- )
    0 _UMSN-GENERATION !
    0 _UMSN-WORK-A ! 0 _UMSN-WORK-U ! 0 _UMSN-WORK-CAP !
    0 _UMSN-WORK-TEXT-A ! 0 _UMSN-WORK-TEXT-U !
    0 _UMSN-WORK-TEXT-USED !
    0 _UMSN-RECORDS-A ! 0 _UMSN-RECORDS-U ! 0 _UMSN-RECORD-CAP !
    0 _UMSN-TEXT-A ! 0 _UMSN-TEXT-U ! 0 _UMSN-RANGES-VALID !
    0 _UMSN-STATUS ! 0 _UMSN-HIGH-WATER ! 0 _UMSN-RECORD-COUNT !
    0 _UMSN-TEXT-USED ! 0 _UMSN-DIRTY-WORK-U !
    0 _UMSN-DIRTY-WORK-TEXT-U !
    0 _UMSN-DIRTY-RECORD-U ! 0 _UMSN-DIRTY-TEXT-U ! 0 _UMSN-SCAN-I !
    0 _UMSN-V-ELEM ! 0 _UMSN-V-INDEX ! 0 _UMSN-V-ORDINAL !
    0 _UMSN-V-LOCAL ! 0 _UMSN-V-EFFECTIVE !
    0 _UMSN-V-RESOLVED-A ! 0 _UMSN-V-RESOLVED-U !
    0 _UMSN-V-PARENT ! 0 _UMSN-V-PARENT-KIND ! 0 _UMSN-V-KIND !
    0 _UMSN-V-STATE ! 0 _UMSN-V-WORK !
    0 _UMSN-V-LABEL-A ! 0 _UMSN-V-LABEL-U !
    0 _UMSN-V-SHORTCUT-A ! 0 _UMSN-V-SHORTCUT-U !
    0 _UMSN-V-LABEL-O ! 0 _UMSN-V-SHORTCUT-O !
    0 _UMSN-V-NEXT-WORK-TEXT !
    0 _UMSN-E-INDEX ! 0 _UMSN-E-WORK ! 0 _UMSN-E-RECORD !
    0 _UMSN-E-KIND ! 0 _UMSN-E-PARENT ! 0 _UMSN-E-ORDINAL !
    0 _UMSN-E-STATE ! 0 _UMSN-E-WORK-LABEL-O ! 0 _UMSN-E-LABEL-U !
    0 _UMSN-E-WORK-SHORTCUT-O ! 0 _UMSN-E-SHORTCUT-U !
    0 _UMSN-E-LABEL-O ! 0 _UMSN-E-SHORTCUT-O !
    0 _UMSN-E-NEXT-TEXT !
    0 _UMSN-TV-A ! 0 _UMSN-TV-U ! 0 _UMSN-TV-I ! ;

: UMSN-CAPTURE
    ( generation work-a work-u work-text-a work-text-u records-a records-u text-a text-u -- record-count text-used status )
    _UMSN-TEXT-U ! _UMSN-TEXT-A !
    _UMSN-RECORDS-U ! _UMSN-RECORDS-A !
    _UMSN-WORK-TEXT-U ! _UMSN-WORK-TEXT-A !
    _UMSN-WORK-U ! _UMSN-WORK-A ! _UMSN-GENERATION !
    0 _UMSN-RANGES-VALID !
    _UMSN-RANGES? 0= IF
        0 0 UMSN-S-INVALID _UMSN-SCRUB EXIT
    THEN
    _UMSN-WORK-U @ UMSN-WORK-ENTRY-SIZE / _UMSN-WORK-CAP !
    _UMSN-RECORDS-U @ UMSN-RECORD-SIZE / _UMSN-RECORD-CAP !
    -1 _UMSN-RANGES-VALID !
    ['] _UMSN-CAPTURE-BODY CATCH ?DUP IF
        DROP _UMSN-SET-INVALID _UMSN-FAIL-RESULT
    THEN
    _UMSN-SCRUB ;

CREATE _UMSN-OWNED-END
_UMSN-OWNED-END _UMSN-OWNED-LIMIT !
