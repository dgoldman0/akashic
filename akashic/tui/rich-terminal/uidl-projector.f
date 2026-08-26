\ =====================================================================
\  uidl-projector.f -- caller-bounded neutral UIDL candidate capture
\ =====================================================================
\
\  This rich-driver-private layer copies supported UIDL semantic snapshots
\  and neutral resolved layout/style state into storage selected by its
\  caller.  It knows no retained engine, wire protocol, screen, host, Desk,
\  or applet API.  A successful build is only a local desired-projection
\  candidate; the caller owns publication.
\
\  Prefix:   RUPJ- (private provider contract), _RUPJ- (implementation)
\  Provider: akashic-tui-rterm-uidl-projector

PROVIDED akashic-tui-rterm-uidl-projector

REQUIRE ../uidl-tui.f
REQUIRE ../../liraq/uidl-semantic.f
REQUIRE ../../utils/memory-span.f

\ =====================================================================
\  Stable local status and item record
\ =====================================================================

0 CONSTANT RUPJ-S-OK
1 CONSTANT RUPJ-S-CAPACITY
2 CONSTANT RUPJ-S-INVALID

: RUPJ-STATUS-VALID?  ( status -- flag )  3 U< ;

\ One item is a stable semantic key, an offset into the accompanying semantic
\ snapshot arena, and a copied renderer-neutral resolved record.  Offsets are
\ physical and aligned; BYTES is the exact semantic record size and excludes
\ arena padding.  Resolved row/column are normalized to the captured root.
: _RUPJ-I.ELEMENT-INDEX  ( item -- a )       ;
: _RUPJ-I.SUBKEY         ( item -- a )   8 + ;
: _RUPJ-I.KIND           ( item -- a )  16 + ;
: _RUPJ-I.SNAPSHOT-OFF   ( item -- a )  24 + ;
: _RUPJ-I.SNAPSHOT-BYTES ( item -- a )  32 + ;
: _RUPJ-I.FLAGS          ( item -- a )  40 + ;
: _RUPJ-I.RESOLVED       ( item -- a )  48 + ;
: _RUPJ-I.RESERVED       ( item -- a ) 120 + ;

128 CONSTANT RUPJ-ITEM-SIZE

1 CONSTANT RUPJ-ITEM-F-HAS-RESOLVED
2 CONSTANT RUPJ-ITEM-F-EFFECTIVE-VISIBLE
3 CONSTANT _RUPJ-ITEM-F-MASK

\ Local field accessors consume only the stable copied-record layout.  No
\ UIDL-TUI sidecar or packed style representation crosses this boundary.
: _RUPJ-R.ROW    ( record -- a )       ;
: _RUPJ-R.COL    ( record -- a )   8 + ;
: _RUPJ-R.H      ( record -- a )  16 + ;
: _RUPJ-R.W      ( record -- a )  24 + ;
: _RUPJ-R.FG     ( record -- a )  32 + ;
: _RUPJ-R.BG     ( record -- a )  40 + ;
: _RUPJ-R.ATTRS  ( record -- a )  48 + ;
: _RUPJ-R.ALIGN  ( record -- a )  56 + ;
: _RUPJ-R.Z      ( record -- a )  64 + ;

: RUPJ-ITEM-BYTES  ( -- bytes )  RUPJ-ITEM-SIZE ;
: RUPJ-ITEM-ELEMENT-INDEX@  ( item -- index )
    _RUPJ-I.ELEMENT-INDEX @ ;
: RUPJ-ITEM-SUBKEY@  ( item -- subkey )  _RUPJ-I.SUBKEY @ ;
: RUPJ-ITEM-KIND@  ( item -- kind )  _RUPJ-I.KIND @ ;
: RUPJ-ITEM-SNAPSHOT-OFFSET@  ( item -- offset )
    _RUPJ-I.SNAPSHOT-OFF @ ;
: RUPJ-ITEM-SNAPSHOT-BYTES@  ( item -- bytes )
    _RUPJ-I.SNAPSHOT-BYTES @ ;
: RUPJ-ITEM-FLAGS@  ( item -- flags )  _RUPJ-I.FLAGS @ ;
: RUPJ-ITEM-HAS-RESOLVED?  ( item -- flag )
    RUPJ-ITEM-FLAGS@ RUPJ-ITEM-F-HAS-RESOLVED AND 0<> ;
: RUPJ-ITEM-EFFECTIVE-VISIBLE?  ( item -- flag )
    RUPJ-ITEM-FLAGS@ RUPJ-ITEM-F-EFFECTIVE-VISIBLE AND 0<> ;
: RUPJ-ITEM-RESOLVED  ( item -- record available )
    _RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES ;
: RUPJ-ITEM-RESOLVED-ROW@  ( item -- row )
    _RUPJ-I.RESOLVED _RUPJ-R.ROW @ ;
: RUPJ-ITEM-RESOLVED-COL@  ( item -- col )
    _RUPJ-I.RESOLVED _RUPJ-R.COL @ ;
: RUPJ-ITEM-RESOLVED-HEIGHT@  ( item -- height )
    _RUPJ-I.RESOLVED _RUPJ-R.H @ ;
: RUPJ-ITEM-RESOLVED-WIDTH@  ( item -- width )
    _RUPJ-I.RESOLVED _RUPJ-R.W @ ;
: RUPJ-ITEM-RESOLVED-FG@  ( item -- fg )
    _RUPJ-I.RESOLVED _RUPJ-R.FG @ ;
: RUPJ-ITEM-RESOLVED-BG@  ( item -- bg )
    _RUPJ-I.RESOLVED _RUPJ-R.BG @ ;
: RUPJ-ITEM-RESOLVED-ATTRS@  ( item -- attrs )
    _RUPJ-I.RESOLVED _RUPJ-R.ATTRS @ ;
: RUPJ-ITEM-RESOLVED-ALIGN@  ( item -- align )
    _RUPJ-I.RESOLVED _RUPJ-R.ALIGN @ ;
: RUPJ-ITEM-RESOLVED-Z@  ( item -- z )
    _RUPJ-I.RESOLVED _RUPJ-R.Z @ ;

-1 1 RSHIFT CONSTANT _RUPJ-LENGTH-MAX
_RUPJ-LENGTH-MAX CONSTANT _RUPJ-SIGNED-MAX
_RUPJ-SIGNED-MAX INVERT CONSTANT _RUPJ-SIGNED-MIN

: _RUPJ-ALIGNED?  ( a -- flag )  7 AND 0= ;

: _RUPJ-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER _RUPJ-ALIGNED? 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RUPJ-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

: _RUPJ-ALIGN8?  ( exact -- stride flag )
    DUP 0> 0= IF DROP 0 0 EXIT THEN
    7 _RUPJ-UADD? 0= IF DROP 0 0 EXIT THEN
    -8 AND
    DUP _RUPJ-LENGTH-MAX U> IF DROP 0 0 EXIT THEN
    -1 ;

\ =====================================================================
\  Published-candidate validation
\ =====================================================================

VARIABLE _RUPJ-V-ITEMS-A
VARIABLE _RUPJ-V-ITEMS-U
VARIABLE _RUPJ-V-ITEM-COUNT
VARIABLE _RUPJ-V-SNAPSHOTS-A
VARIABLE _RUPJ-V-SNAPSHOTS-U
VARIABLE _RUPJ-V-SNAPSHOT-USED
VARIABLE _RUPJ-V-REGIONS
VARIABLE _RUPJ-V-OBJECTS
VARIABLE _RUPJ-V-UTF8
VARIABLE _RUPJ-V-EXPECTED-OFF
VARIABLE _RUPJ-V-UTF8-SUM
VARIABLE _RUPJ-V-ITEM
VARIABLE _RUPJ-V-SNAPSHOT
VARIABLE _RUPJ-V-EXACT
VARIABLE _RUPJ-V-STRIDE
VARIABLE _RUPJ-V-TEXT-U
VARIABLE _RUPJ-V-KEY
VARIABLE _RUPJ-V-UPTO
VARIABLE _RUPJ-V-FLAGS
VARIABLE _RUPJ-V-ROOT-H
VARIABLE _RUPJ-V-ROOT-W
VARIABLE _RUPJ-V-R-ROW
VARIABLE _RUPJ-V-R-COL
VARIABLE _RUPJ-V-R-H
VARIABLE _RUPJ-V-R-W

: _RUPJ-ZERO?  ( a u -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _RUPJ-V-ITEM-AT  ( index -- item )
    RUPJ-ITEM-SIZE * _RUPJ-V-ITEMS-A @ + ;

: _RUPJ-V-KEY-FIRST?  ( key prior-count -- flag )
    _RUPJ-V-UPTO ! _RUPJ-V-KEY !
    _RUPJ-V-UPTO @ 0 ?DO
        I _RUPJ-V-ITEM-AT _RUPJ-I.ELEMENT-INDEX @
        _RUPJ-V-KEY @ = IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _RUPJ-V-INTERSECTS-ROOT?  ( record -- flag )
    DUP _RUPJ-R.ROW @ _RUPJ-V-R-ROW !
    DUP _RUPJ-R.COL @ _RUPJ-V-R-COL !
    DUP _RUPJ-R.H @ _RUPJ-V-R-H !
    _RUPJ-R.W @ _RUPJ-V-R-W !
    _RUPJ-V-R-H @ 0> _RUPJ-V-R-W @ 0> AND 0= IF 0 EXIT THEN
    _RUPJ-V-R-ROW @ _RUPJ-V-ROOT-H @ <
    _RUPJ-V-R-ROW @ _RUPJ-V-R-H @ + 0> AND
    _RUPJ-V-R-COL @ _RUPJ-V-ROOT-W @ < AND
    _RUPJ-V-R-COL @ _RUPJ-V-R-W @ + 0> AND ;

: _RUPJ-V-RANGES?  ( -- flag )
    UTUI-RESOLVED-BYTES 72 <> IF 0 EXIT THEN
    _RUPJ-V-ITEMS-A @ _RUPJ-V-ITEMS-U @ _RUPJ-SPAN? 0= IF 0 EXIT THEN
    _RUPJ-V-SNAPSHOTS-A @ _RUPJ-V-SNAPSHOTS-U @
        _RUPJ-SPAN? 0= IF 0 EXIT THEN
    _RUPJ-V-ITEMS-U @ RUPJ-ITEM-SIZE MOD IF 0 EXIT THEN
    _RUPJ-V-ITEMS-A @ _RUPJ-V-ITEMS-U @
        _RUPJ-V-SNAPSHOTS-A @ _RUPJ-V-SNAPSHOTS-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RUPJ-V-ITEM-COUNT @ DUP 0< IF DROP 0 EXIT THEN
    _RUPJ-V-ITEMS-U @ RUPJ-ITEM-SIZE / U> IF 0 EXIT THEN
    _RUPJ-V-SNAPSHOT-USED @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    _RUPJ-V-SNAPSHOTS-U @ U> IF 0 EXIT THEN
    _RUPJ-V-REGIONS @
        _RUPJ-V-ITEM-COUNT @ 0<> IF 1 ELSE 0 THEN <> IF 0 EXIT THEN
    _RUPJ-V-OBJECTS @ _RUPJ-V-ITEM-COUNT @ <> IF 0 EXIT THEN
    _RUPJ-V-UTF8 @ 0< IF 0 EXIT THEN
    _RUPJ-V-ROOT-H @ DUP 0> 0= IF DROP 0 EXIT THEN
    _RUPJ-SIGNED-MAX U> IF 0 EXIT THEN
    _RUPJ-V-ROOT-W @ DUP 0> 0= IF DROP 0 EXIT THEN
    _RUPJ-SIGNED-MAX U> 0= ;

: _RUPJ-V-ONE?  ( item-index -- flag )
    DUP _RUPJ-V-UPTO ! _RUPJ-V-ITEM-AT _RUPJ-V-ITEM !
    _RUPJ-V-ITEM @ _RUPJ-I.ELEMENT-INDEX @
        DUP 0< IF DROP 0 EXIT THEN
    DUP _RUPJ-V-KEY ! _RUPJ-V-UPTO @
        _RUPJ-V-KEY-FIRST? 0= IF 0 EXIT THEN
    _RUPJ-V-ITEM @ _RUPJ-I.SUBKEY @ IF 0 EXIT THEN
    _RUPJ-V-ITEM @ _RUPJ-I.KIND @
        UIDL-SNAPSHOT-K-LABEL <> IF 0 EXIT THEN
    _RUPJ-V-ITEM @ _RUPJ-I.FLAGS @ DUP _RUPJ-V-FLAGS !
    _RUPJ-ITEM-F-MASK INVERT AND IF 0 EXIT THEN
    _RUPJ-V-FLAGS @ RUPJ-ITEM-F-EFFECTIVE-VISIBLE AND IF
        _RUPJ-V-FLAGS @ RUPJ-ITEM-F-HAS-RESOLVED AND 0= IF
            0 EXIT
        THEN
    THEN
    _RUPJ-V-FLAGS @ RUPJ-ITEM-F-HAS-RESOLVED AND IF
        _RUPJ-V-ITEM @ _RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES
            UTUI-RESOLVED-VALID? 0= IF 0 EXIT THEN
        _RUPJ-V-FLAGS @ RUPJ-ITEM-F-EFFECTIVE-VISIBLE AND IF
            _RUPJ-V-ITEM @ _RUPJ-I.RESOLVED
                _RUPJ-V-INTERSECTS-ROOT? 0= IF 0 EXIT THEN
        THEN
    ELSE
        _RUPJ-V-ITEM @ _RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES
            _RUPJ-ZERO? 0= IF 0 EXIT THEN
    THEN
    _RUPJ-V-ITEM @ _RUPJ-I.RESERVED @ IF 0 EXIT THEN
    _RUPJ-V-ITEM @ _RUPJ-I.SNAPSHOT-OFF @
        DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _RUPJ-V-EXPECTED-OFF @ <> IF DROP 0 EXIT THEN
    _RUPJ-V-SNAPSHOTS-A @ + _RUPJ-V-SNAPSHOT !
    _RUPJ-V-ITEM @ _RUPJ-I.SNAPSHOT-BYTES @
        DUP 0> 0= IF DROP 0 EXIT THEN
    DUP _RUPJ-V-EXACT ! _RUPJ-ALIGN8? 0= IF DROP 0 EXIT THEN
    DUP _RUPJ-V-STRIDE !
    _RUPJ-V-EXPECTED-OFF @ SWAP _RUPJ-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RUPJ-V-SNAPSHOT-USED @ U> IF DROP 0 EXIT THEN
    _RUPJ-V-EXPECTED-OFF !
    _RUPJ-V-SNAPSHOT @ _RUPJ-V-EXACT @
        UIDL-LABEL-SNAPSHOT-VALID? 0= IF 0 EXIT THEN
    _RUPJ-V-SNAPSHOT @ UIDL-LABEL-SNAPSHOT-BYTES@
        _RUPJ-V-EXACT @ <> IF 0 EXIT THEN
    _RUPJ-V-SNAPSHOT @ UIDL-LABEL-SNAPSHOT-TEXT@ NIP
        DUP _RUPJ-V-TEXT-U !
    UIDL-LABEL-SNAPSHOT-BYTES _RUPJ-V-EXACT @ <> IF 0 EXIT THEN
    _RUPJ-V-UTF8-SUM @ _RUPJ-V-TEXT-U @ _RUPJ-UADD? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RUPJ-LENGTH-MAX U> IF DROP 0 EXIT THEN
    _RUPJ-V-UTF8-SUM !
    _RUPJ-V-SNAPSHOT @ _RUPJ-V-EXACT @ +
    _RUPJ-V-STRIDE @ _RUPJ-V-EXACT @ - _RUPJ-ZERO? ;

: _RUPJ-V-BODY?  ( -- flag )
    _RUPJ-V-RANGES? 0= IF 0 EXIT THEN
    0 _RUPJ-V-EXPECTED-OFF ! 0 _RUPJ-V-UTF8-SUM !
    _RUPJ-V-ITEM-COUNT @ 0 ?DO
        I _RUPJ-V-ONE? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RUPJ-V-EXPECTED-OFF @ _RUPJ-V-SNAPSHOT-USED @ <> IF 0 EXIT THEN
    _RUPJ-V-UTF8-SUM @ _RUPJ-V-UTF8 @ <> IF 0 EXIT THEN
    _RUPJ-V-ITEM-COUNT @ RUPJ-ITEM-SIZE *
    DUP _RUPJ-V-ITEMS-A @ +
    _RUPJ-V-ITEMS-U @ ROT - _RUPJ-ZERO? 0= IF 0 EXIT THEN
    _RUPJ-V-SNAPSHOT-USED @
    DUP _RUPJ-V-SNAPSHOTS-A @ +
    _RUPJ-V-SNAPSHOTS-U @ ROT - _RUPJ-ZERO? ;

: _RUPJ-V-CALL  ( -- flag )
    _RUPJ-V-BODY? ;

\ =====================================================================
\  Checked caller storage
\ =====================================================================

VARIABLE _RUPJ-ITEMS-A
VARIABLE _RUPJ-ITEMS-U
VARIABLE _RUPJ-ITEM-CAP
VARIABLE _RUPJ-SNAPSHOTS-A
VARIABLE _RUPJ-SNAPSHOTS-U
VARIABLE _RUPJ-RANGES-VALID

: _RUPJ-RANGES?  ( -- flag )
    UTUI-RESOLVED-BYTES 72 <> IF 0 EXIT THEN
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @ _RUPJ-SPAN? 0= IF 0 EXIT THEN
    _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOTS-U @
        _RUPJ-SPAN? 0= IF 0 EXIT THEN
    _RUPJ-ITEMS-U @ RUPJ-ITEM-SIZE MOD IF 0 EXIT THEN
    _RUPJ-ITEMS-U @ RUPJ-ITEM-SIZE / DUP 0= IF DROP 0 EXIT THEN
    _RUPJ-ITEM-CAP !
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @
        UTUI-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @
        UIDL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @
        ST-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOTS-U @
        UTUI-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOTS-U @
        UIDL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOTS-U @
        ST-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @
        _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOTS-U @
        MSPAN-OVERLAP? 0= ;

: _RUPJ-CLEAR-BANKS  ( -- )
    _RUPJ-RANGES-VALID @ 0= IF EXIT THEN
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @ 0 FILL
    _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOTS-U @ 0 FILL ;

\ =====================================================================
\  Candidate construction
\ =====================================================================

VARIABLE _RUPJ-STATUS
VARIABLE _RUPJ-ELEMENT-TOTAL
VARIABLE _RUPJ-VISITED
VARIABLE _RUPJ-ITEM-COUNT
VARIABLE _RUPJ-SNAPSHOT-USED
VARIABLE _RUPJ-UTF8-QUOTA

VARIABLE _RUPJ-C-ELEM
VARIABLE _RUPJ-C-INDEX
VARIABLE _RUPJ-C-EXACT
VARIABLE _RUPJ-C-STRIDE
VARIABLE _RUPJ-C-SNAPSHOT
VARIABLE _RUPJ-C-ITEM
VARIABLE _RUPJ-C-TEXT-U
VARIABLE _RUPJ-C-NEXT-SNAPSHOT
VARIABLE _RUPJ-C-NEXT-UTF8
VARIABLE _RUPJ-C-RESOLVED-STATUS
VARIABLE _RUPJ-C-RESOLVED-VISIBLE
VARIABLE _RUPJ-C-RESOLVED-FLAGS
VARIABLE _RUPJ-C-NORM-ROW
VARIABLE _RUPJ-C-NORM-COL
VARIABLE _RUPJ-ROOT-ROW
VARIABLE _RUPJ-ROOT-COL
VARIABLE _RUPJ-ROOT-H
VARIABLE _RUPJ-ROOT-W
VARIABLE _RUPJ-SUB-A
VARIABLE _RUPJ-SUB-B
VARIABLE _RUPJ-KEY

: _RUPJ-ITEM-AT  ( index -- item )
    RUPJ-ITEM-SIZE * _RUPJ-ITEMS-A @ + ;

: _RUPJ-KEY-UNIQUE?  ( element-index -- flag )
    _RUPJ-KEY !
    _RUPJ-ITEM-COUNT @ 0 ?DO
        I _RUPJ-ITEM-AT _RUPJ-I.ELEMENT-INDEX @
        _RUPJ-KEY @ = IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _RUPJ-SET-INVALID  ( -- )
    RUPJ-S-INVALID _RUPJ-STATUS ! ;

: _RUPJ-SET-CAPACITY  ( -- )
    RUPJ-S-CAPACITY _RUPJ-STATUS ! ;

: _RUPJ-SSUB?  ( a b -- difference flag )
    _RUPJ-SUB-B ! _RUPJ-SUB-A !
    _RUPJ-SUB-B @ 0> IF
        _RUPJ-SUB-A @ _RUPJ-SIGNED-MIN _RUPJ-SUB-B @ + < IF
            0 0 EXIT
        THEN
    ELSE
        _RUPJ-SUB-B @ 0< IF
            _RUPJ-SUB-A @ _RUPJ-SIGNED-MAX _RUPJ-SUB-B @ + > IF
                0 0 EXIT
            THEN
        THEN
    THEN
    _RUPJ-SUB-A @ _RUPJ-SUB-B @ - -1 ;

: _RUPJ-C-NORMALIZE-RESOLVED?  ( -- flag )
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES
        UTUI-RESOLVED-VALID? 0= IF 0 EXIT THEN
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.ROW @
        _RUPJ-ROOT-ROW @ _RUPJ-SSUB? 0= IF DROP 0 EXIT THEN
    _RUPJ-C-NORM-ROW !
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.COL @
        _RUPJ-ROOT-COL @ _RUPJ-SSUB? 0= IF DROP 0 EXIT THEN
    _RUPJ-C-NORM-COL !
    _RUPJ-C-NORM-ROW @
        _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.ROW !
    _RUPJ-C-NORM-COL @
        _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.COL !
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES
        UTUI-RESOLVED-VALID? ;

: _RUPJ-CAPTURE-RESOLVED?  ( -- flag )
    0 _RUPJ-C-RESOLVED-FLAGS !
    _RUPJ-C-ELEM @ _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED
        UTUI-RESOLVED-BYTES UTUI-ELEM-RESOLVED-CAPTURE
    _RUPJ-C-RESOLVED-STATUS ! _RUPJ-C-RESOLVED-VISIBLE !
    _RUPJ-C-RESOLVED-STATUS @ UTUI-RESOLVED-S-OK = IF
        _RUPJ-C-NORMALIZE-RESOLVED? 0= IF
            _RUPJ-SET-INVALID 0 EXIT
        THEN
        RUPJ-ITEM-F-HAS-RESOLVED _RUPJ-C-RESOLVED-FLAGS !
        _RUPJ-C-RESOLVED-VISIBLE @ IF
            RUPJ-ITEM-F-EFFECTIVE-VISIBLE
                _RUPJ-C-RESOLVED-FLAGS +!
        THEN
        _RUPJ-C-RESOLVED-FLAGS @ _RUPJ-C-ITEM @ _RUPJ-I.FLAGS !
        -1 EXIT
    THEN
    _RUPJ-C-RESOLVED-STATUS @ UTUI-RESOLVED-S-UNAVAILABLE = IF
        _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES
            _RUPJ-ZERO? 0= IF _RUPJ-SET-INVALID 0 EXIT THEN
        -1 EXIT
    THEN
    _RUPJ-SET-INVALID 0 ;

: _RUPJ-CAPTURE-ROOT?  ( root -- flag )
    _RUPJ-C-ELEM !
    _RUPJ-ITEMS-A @ DUP _RUPJ-C-ITEM ! RUPJ-ITEM-SIZE 0 FILL
    _RUPJ-C-ELEM @ _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED
        UTUI-RESOLVED-BYTES UTUI-ELEM-RESOLVED-CAPTURE
    _RUPJ-C-RESOLVED-STATUS ! _RUPJ-C-RESOLVED-VISIBLE !
    _RUPJ-C-RESOLVED-STATUS @ UTUI-RESOLVED-S-OK <> IF
        0 EXIT
    THEN
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES
        UTUI-RESOLVED-VALID? 0= IF 0 EXIT THEN
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.ROW @
        DUP 0< IF DROP 0 EXIT THEN _RUPJ-ROOT-ROW !
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.COL @
        DUP 0< IF DROP 0 EXIT THEN _RUPJ-ROOT-COL !
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.H @
        DUP 0> 0= IF DROP 0 EXIT THEN
        DUP _RUPJ-SIGNED-MAX U> IF DROP 0 EXIT THEN _RUPJ-ROOT-H !
    _RUPJ-C-ITEM @ _RUPJ-I.RESOLVED _RUPJ-R.W @
        DUP 0> 0= IF DROP 0 EXIT THEN
        DUP _RUPJ-SIGNED-MAX U> IF DROP 0 EXIT THEN _RUPJ-ROOT-W !
    _RUPJ-C-ITEM @ RUPJ-ITEM-SIZE 0 FILL
    -1 ;

: _RUPJ-LABEL-PREFLIGHT  ( -- flag )
    _RUPJ-C-INDEX @ _RUPJ-KEY-UNIQUE? 0= IF
        _RUPJ-SET-INVALID 0 EXIT
    THEN
    _RUPJ-ITEM-COUNT @ _RUPJ-ITEM-CAP @ U< 0= IF
        _RUPJ-SET-CAPACITY 0 EXIT
    THEN
    _RUPJ-C-EXACT @ _RUPJ-ALIGN8? 0= IF
        DROP _RUPJ-SET-CAPACITY 0 EXIT
    THEN
    _RUPJ-C-STRIDE !
    _RUPJ-SNAPSHOT-USED @ _RUPJ-SNAPSHOTS-U @ U> IF
        _RUPJ-SET-INVALID 0 EXIT
    THEN
    _RUPJ-C-STRIDE @
        _RUPJ-SNAPSHOTS-U @ _RUPJ-SNAPSHOT-USED @ - U> IF
        _RUPJ-SET-CAPACITY 0 EXIT
    THEN
    _RUPJ-SNAPSHOT-USED @ _RUPJ-C-STRIDE @ _RUPJ-UADD? 0= IF
        DROP _RUPJ-SET-CAPACITY 0 EXIT
    THEN
    _RUPJ-C-NEXT-SNAPSHOT !
    _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOT-USED @ +
        _RUPJ-C-SNAPSHOT !
    -1 ;

: _RUPJ-LABEL-CAPTURE  ( elem element-index -- )
    _RUPJ-C-INDEX ! _RUPJ-C-ELEM !
    _RUPJ-C-ELEM @ UIDL-SNAPSHOT-SIZE
    DUP UIDL-SNAP-S-UNSUPPORTED = IF 2DROP EXIT THEN
    DUP UIDL-SNAP-S-CAPACITY = IF
        2DROP _RUPJ-SET-CAPACITY EXIT
    THEN
    DUP UIDL-SNAP-S-OK <> IF
        2DROP _RUPJ-SET-INVALID EXIT
    THEN
    DROP DUP 0> 0= IF DROP _RUPJ-SET-INVALID EXIT THEN
    _RUPJ-C-EXACT !
    _RUPJ-LABEL-PREFLIGHT 0= IF EXIT THEN

    _RUPJ-C-ELEM @ _RUPJ-C-SNAPSHOT @ _RUPJ-C-EXACT @
        UIDL-SNAPSHOT-CAPTURE
    DUP UIDL-SNAP-S-CAPACITY = IF
        2DROP _RUPJ-SET-CAPACITY EXIT
    THEN
    DUP UIDL-SNAP-S-OK <> IF
        2DROP _RUPJ-SET-INVALID EXIT
    THEN
    DROP _RUPJ-C-EXACT @ <> IF _RUPJ-SET-INVALID EXIT THEN
    _RUPJ-C-SNAPSHOT @ _RUPJ-C-EXACT @
        UIDL-LABEL-SNAPSHOT-VALID? 0= IF
        _RUPJ-SET-INVALID EXIT
    THEN
    _RUPJ-C-SNAPSHOT @ UIDL-LABEL-SNAPSHOT-TEXT@ NIP
        DUP _RUPJ-C-TEXT-U !
    UIDL-LABEL-SNAPSHOT-BYTES _RUPJ-C-EXACT @ <> IF
        _RUPJ-SET-INVALID EXIT
    THEN
    _RUPJ-UTF8-QUOTA @ _RUPJ-C-TEXT-U @ _RUPJ-UADD? 0= IF
        DROP _RUPJ-SET-CAPACITY EXIT
    THEN
    DUP _RUPJ-LENGTH-MAX U> IF
        DROP _RUPJ-SET-CAPACITY EXIT
    THEN
    _RUPJ-C-NEXT-UTF8 !

    _RUPJ-ITEM-COUNT @ _RUPJ-ITEM-AT DUP _RUPJ-C-ITEM !
    RUPJ-ITEM-SIZE 0 FILL
    _RUPJ-CAPTURE-RESOLVED? 0= IF EXIT THEN
    _RUPJ-C-INDEX @ _RUPJ-C-ITEM @ _RUPJ-I.ELEMENT-INDEX !
    UIDL-SNAPSHOT-K-LABEL _RUPJ-C-ITEM @ _RUPJ-I.KIND !
    _RUPJ-SNAPSHOT-USED @ _RUPJ-C-ITEM @ _RUPJ-I.SNAPSHOT-OFF !
    _RUPJ-C-EXACT @ _RUPJ-C-ITEM @ _RUPJ-I.SNAPSHOT-BYTES !

    _RUPJ-C-NEXT-SNAPSHOT @ _RUPJ-SNAPSHOT-USED !
    _RUPJ-C-NEXT-UTF8 @ _RUPJ-UTF8-QUOTA !
    1 _RUPJ-ITEM-COUNT +! ;

: _RUPJ-PROCESS-ELEMENT  ( elem -- )
    DUP UIDL-ELEM-INDEX? 0= IF
        2DROP _RUPJ-SET-INVALID EXIT
    THEN
    _RUPJ-C-INDEX !
    _RUPJ-VISITED @ 1 _RUPJ-UADD? 0= IF
        DROP DROP _RUPJ-SET-INVALID EXIT
    THEN
    DUP _RUPJ-ELEMENT-TOTAL @ U> IF
        DROP DROP _RUPJ-SET-INVALID EXIT
    THEN
    _RUPJ-VISITED !
    DUP UIDL-TYPE UIDL-T-LABEL = IF
        _RUPJ-C-INDEX @ _RUPJ-LABEL-CAPTURE
    ELSE
        DROP
    THEN ;

\ A bounded recursive preorder walk follows only the live root tree.  Every
\ child must name the current parent, and the global allocated high-water is
\ an upper bound on visits, so malformed cycles terminate as INVALID.
: _RUPJ-WALK  ( elem -- )
    _RUPJ-STATUS @ RUPJ-S-OK <> IF DROP EXIT THEN
    DUP _RUPJ-PROCESS-ELEMENT
    _RUPJ-STATUS @ RUPJ-S-OK <> IF DROP EXIT THEN
    DUP UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UIDL-ELEM-INDEX? 0= IF
            3DROP _RUPJ-SET-INVALID EXIT
        THEN
        DROP
        DUP UIDL-PARENT 2 PICK <> IF
            2DROP _RUPJ-SET-INVALID EXIT
        THEN
        DUP UIDL-NEXT-SIB SWAP RECURSE
        _RUPJ-STATUS @ RUPJ-S-OK <> IF 2DROP EXIT THEN
    REPEAT
    2DROP ;

: _RUPJ-FAIL-RESULT  ( status -- 0 0 0 0 0 0 0 status )
    _RUPJ-STATUS !
    _RUPJ-CLEAR-BANKS
    0 0 0 0 0 0 0 _RUPJ-STATUS @ ;

: _RUPJ-BUILD-BODY
  ( -- item-count snapshot-used regions objects utf8 root-h root-w status )
    _RUPJ-RANGES? 0= IF
        RUPJ-S-INVALID _RUPJ-FAIL-RESULT EXIT
    THEN
    -1 _RUPJ-RANGES-VALID !
    _RUPJ-CLEAR-BANKS
    RUPJ-S-OK _RUPJ-STATUS !
    0 _RUPJ-VISITED ! 0 _RUPJ-ITEM-COUNT !
    0 _RUPJ-SNAPSHOT-USED ! 0 _RUPJ-UTF8-QUOTA !

    UIDL-ELEM-COUNT DUP 0> 0= IF
        DROP RUPJ-S-INVALID _RUPJ-FAIL-RESULT EXIT
    THEN
    _RUPJ-ELEMENT-TOTAL !
    UIDL-ROOT DUP 0= IF
        DROP RUPJ-S-INVALID _RUPJ-FAIL-RESULT EXIT
    THEN
    DUP UIDL-ELEM-INDEX? 0= IF
        2DROP RUPJ-S-INVALID _RUPJ-FAIL-RESULT EXIT
    THEN
    DROP
    DUP UIDL-PARENT 0<> IF
        DROP RUPJ-S-INVALID _RUPJ-FAIL-RESULT EXIT
    THEN
    DUP _RUPJ-CAPTURE-ROOT? 0= IF
        DROP RUPJ-S-INVALID _RUPJ-FAIL-RESULT EXIT
    THEN
    _RUPJ-WALK
    _RUPJ-STATUS @ RUPJ-S-OK <> IF
        _RUPJ-STATUS @ _RUPJ-FAIL-RESULT EXIT
    THEN

    _RUPJ-ITEM-COUNT @
    _RUPJ-SNAPSHOT-USED @
    _RUPJ-ITEM-COUNT @ 0<> IF 1 ELSE 0 THEN
    _RUPJ-ITEM-COUNT @
    _RUPJ-UTF8-QUOTA @
    _RUPJ-ROOT-H @
    _RUPJ-ROOT-W @
    RUPJ-S-OK ;

: _RUPJ-BUILD-CALL
  ( -- item-count snapshot-used regions objects utf8 root-h root-w status )
    ['] _RUPJ-BUILD-BODY UIDL-SEMANTIC-OBSERVE ;

: _RUPJ-SCRUB  ( -- )
    0 _RUPJ-V-ITEMS-A ! 0 _RUPJ-V-ITEMS-U !
    0 _RUPJ-V-ITEM-COUNT ! 0 _RUPJ-V-SNAPSHOTS-A !
    0 _RUPJ-V-SNAPSHOTS-U ! 0 _RUPJ-V-SNAPSHOT-USED !
    0 _RUPJ-V-REGIONS ! 0 _RUPJ-V-OBJECTS ! 0 _RUPJ-V-UTF8 !
    0 _RUPJ-V-EXPECTED-OFF ! 0 _RUPJ-V-UTF8-SUM !
    0 _RUPJ-V-ITEM ! 0 _RUPJ-V-SNAPSHOT ! 0 _RUPJ-V-EXACT !
    0 _RUPJ-V-STRIDE ! 0 _RUPJ-V-TEXT-U !
    0 _RUPJ-V-KEY ! 0 _RUPJ-V-UPTO ! 0 _RUPJ-V-FLAGS !
    0 _RUPJ-V-ROOT-H ! 0 _RUPJ-V-ROOT-W !
    0 _RUPJ-V-R-ROW ! 0 _RUPJ-V-R-COL !
    0 _RUPJ-V-R-H ! 0 _RUPJ-V-R-W !
    0 _RUPJ-ITEMS-A ! 0 _RUPJ-ITEMS-U ! 0 _RUPJ-ITEM-CAP !
    0 _RUPJ-SNAPSHOTS-A ! 0 _RUPJ-SNAPSHOTS-U !
    0 _RUPJ-RANGES-VALID ! 0 _RUPJ-STATUS !
    0 _RUPJ-ELEMENT-TOTAL ! 0 _RUPJ-VISITED !
    0 _RUPJ-ITEM-COUNT ! 0 _RUPJ-SNAPSHOT-USED !
    0 _RUPJ-UTF8-QUOTA !
    0 _RUPJ-C-ELEM ! 0 _RUPJ-C-INDEX ! 0 _RUPJ-C-EXACT !
    0 _RUPJ-C-STRIDE ! 0 _RUPJ-C-SNAPSHOT ! 0 _RUPJ-C-ITEM !
    0 _RUPJ-C-TEXT-U ! 0 _RUPJ-C-NEXT-SNAPSHOT !
    0 _RUPJ-C-NEXT-UTF8 !
    0 _RUPJ-C-RESOLVED-STATUS ! 0 _RUPJ-C-RESOLVED-VISIBLE !
    0 _RUPJ-C-RESOLVED-FLAGS !
    0 _RUPJ-C-NORM-ROW ! 0 _RUPJ-C-NORM-COL !
    0 _RUPJ-ROOT-ROW ! 0 _RUPJ-ROOT-COL !
    0 _RUPJ-ROOT-H ! 0 _RUPJ-ROOT-W !
    0 _RUPJ-SUB-A ! 0 _RUPJ-SUB-B ! 0 _RUPJ-KEY ! ;

\ RUPJ-BUILD
\   Capture all currently supported LABEL semantics in root preorder.
\   Unsupported element semantics are skipped and continue through ordinary
\   CELL fallback.  On success, item-count/object-quota are equal,
\   region-quota is one iff any item exists, UTF8 quota is the checked sum of
\   current copied text bytes, snapshot-used is the checked sum of aligned
\   record strides, and root-H/W bind every normalized resolved rectangle to
\   its captured layout extent.
\
\   The complete destination is cleared before construction.  Any failure or
\   caught exception clears it again and returns seven zero results plus a
\   stable status, so no partial candidate can be mistaken for publication.
: RUPJ-BUILD
  ( items-a items-u snapshots-a snapshots-u
    -- item-count snapshot-used region-quota object-quota utf8-quota
       root-height root-width status )
    _RUPJ-SNAPSHOTS-U ! _RUPJ-SNAPSHOTS-A !
    _RUPJ-ITEMS-U ! _RUPJ-ITEMS-A !
    0 _RUPJ-RANGES-VALID !
    ['] _RUPJ-BUILD-CALL CATCH ?DUP IF
        DROP RUPJ-S-INVALID _RUPJ-FAIL-RESULT
    THEN
    _RUPJ-SCRUB ;

: RUPJ-CANDIDATE-VALID?
  ( items-a items-u item-count snapshots-a snapshots-u snapshot-used
    region-quota object-quota utf8-quota root-height root-width -- flag )
    _RUPJ-V-ROOT-W ! _RUPJ-V-ROOT-H !
    _RUPJ-V-UTF8 ! _RUPJ-V-OBJECTS ! _RUPJ-V-REGIONS !
    _RUPJ-V-SNAPSHOT-USED ! _RUPJ-V-SNAPSHOTS-U !
    _RUPJ-V-SNAPSHOTS-A ! _RUPJ-V-ITEM-COUNT !
    _RUPJ-V-ITEMS-U ! _RUPJ-V-ITEMS-A !
    ['] _RUPJ-V-CALL CATCH ?DUP IF DROP 0 THEN
    _RUPJ-SCRUB ;

\ Guarded builds serialize the complete borrowed-bank lifetime.  UIDL-TUI and
\ UIDL stay outermost: callers enter the compound resolved observation before
\ acquiring projector scratch, and the raw builder then enters the recursive
\ complete semantic observation.
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _rupj-guard

' RUPJ-BUILD             CONSTANT _rupj-build-xt
' RUPJ-CANDIDATE-VALID?  CONSTANT _rupj-candidate-valid-q-xt

: _RUPJ-BUILD-GUARDED
  ( items-a items-u snapshots-a snapshots-u
    -- item-count snapshot-used region-quota object-quota utf8-quota
       root-height root-width status )
    _rupj-build-xt _rupj-guard WITH-GUARD ;

: RUPJ-BUILD
  ( items-a items-u snapshots-a snapshots-u
    -- item-count snapshot-used region-quota object-quota utf8-quota
       root-height root-width status )
    ['] _RUPJ-BUILD-GUARDED UTUI-RESOLVED-OBSERVE ;

: RUPJ-CANDIDATE-VALID?
  ( items-a items-u item-count snapshots-a snapshots-u snapshot-used
    region-quota object-quota utf8-quota root-height root-width -- flag )
    _rupj-candidate-valid-q-xt _rupj-guard WITH-GUARD ;
[THEN] [THEN]
