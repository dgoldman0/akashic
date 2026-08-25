\ =====================================================================
\  uidl-projector.f -- caller-bounded neutral UIDL candidate capture
\ =====================================================================
\
\  This rich-driver-private layer copies supported UIDL semantic snapshots
\  into storage selected by its caller.  It knows no retained engine, wire
\  protocol, screen, region, host, Desk, or applet API.  A successful build
\  is only a local desired-scene candidate; the caller owns publication.
\
\  Prefix:   RUPJ- (private provider contract), _RUPJ- (implementation)
\  Provider: akashic-tui-rterm-uidl-projector1

PROVIDED akashic-tui-rterm-uidl-projector1

REQUIRE ../../liraq/uidl-semantic.f
REQUIRE ../../utils/memory-span.f

\ =====================================================================
\  Stable local status and item record
\ =====================================================================

0 CONSTANT RUPJ-S-OK
1 CONSTANT RUPJ-S-CAPACITY
2 CONSTANT RUPJ-S-INVALID

: RUPJ-STATUS-VALID?  ( status -- flag )  3 U< ;

\ One item is a stable semantic key plus an offset into the accompanying
\ snapshot arena.  Offsets are physical and aligned; BYTES is the exact
\ semantic record size and excludes arena padding.
: _RUPJ-I.ELEMENT-INDEX  ( item -- a )       ;
: _RUPJ-I.SUBKEY         ( item -- a )   8 + ;
: _RUPJ-I.KIND           ( item -- a )  16 + ;
: _RUPJ-I.SNAPSHOT-OFF   ( item -- a )  24 + ;
: _RUPJ-I.SNAPSHOT-BYTES ( item -- a )  32 + ;
: _RUPJ-I.RESERVED       ( item -- a )  40 + ;

48 CONSTANT RUPJ-ITEM-SIZE

: RUPJ-ITEM-BYTES  ( -- bytes )  RUPJ-ITEM-SIZE ;
: RUPJ-ITEM-ELEMENT-INDEX@  ( item -- index )
    _RUPJ-I.ELEMENT-INDEX @ ;
: RUPJ-ITEM-SUBKEY@  ( item -- subkey )  _RUPJ-I.SUBKEY @ ;
: RUPJ-ITEM-KIND@  ( item -- kind )  _RUPJ-I.KIND @ ;
: RUPJ-ITEM-SNAPSHOT-OFFSET@  ( item -- offset )
    _RUPJ-I.SNAPSHOT-OFF @ ;
: RUPJ-ITEM-SNAPSHOT-BYTES@  ( item -- bytes )
    _RUPJ-I.SNAPSHOT-BYTES @ ;

-1 1 RSHIFT CONSTANT _RUPJ-LENGTH-MAX

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
VARIABLE _RUPJ-V-TEXT-CAP
VARIABLE _RUPJ-V-KEY
VARIABLE _RUPJ-V-UPTO

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

: _RUPJ-V-RANGES?  ( -- flag )
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
    _RUPJ-V-UTF8 @ 0< 0= ;

: _RUPJ-V-ONE?  ( item-index -- flag )
    DUP _RUPJ-V-UPTO ! _RUPJ-V-ITEM-AT _RUPJ-V-ITEM !
    _RUPJ-V-ITEM @ _RUPJ-I.ELEMENT-INDEX @
        DUP 0< IF DROP 0 EXIT THEN
    DUP _RUPJ-V-KEY ! _RUPJ-V-UPTO @
        _RUPJ-V-KEY-FIRST? 0= IF 0 EXIT THEN
    _RUPJ-V-ITEM @ _RUPJ-I.SUBKEY @ IF 0 EXIT THEN
    _RUPJ-V-ITEM @ _RUPJ-I.KIND @
        UIDL-SNAPSHOT-K-LABEL <> IF 0 EXIT THEN
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
    _RUPJ-V-SNAPSHOT @ UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@
        DUP _RUPJ-V-TEXT-CAP !
    UIDL-LABEL-SNAPSHOT-BYTES _RUPJ-V-EXACT @ <> IF 0 EXIT THEN
    _RUPJ-V-UTF8-SUM @ _RUPJ-V-TEXT-CAP @ _RUPJ-UADD? 0= IF
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
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @ _RUPJ-SPAN? 0= IF 0 EXIT THEN
    _RUPJ-SNAPSHOTS-A @ _RUPJ-SNAPSHOTS-U @
        _RUPJ-SPAN? 0= IF 0 EXIT THEN
    _RUPJ-ITEMS-U @ RUPJ-ITEM-SIZE MOD IF 0 EXIT THEN
    _RUPJ-ITEMS-U @ RUPJ-ITEM-SIZE / DUP 0= IF DROP 0 EXIT THEN
    _RUPJ-ITEM-CAP !
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @
        UIDL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RUPJ-ITEMS-A @ _RUPJ-ITEMS-U @
        ST-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
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
VARIABLE _RUPJ-C-TEXT-CAP
VARIABLE _RUPJ-C-NEXT-SNAPSHOT
VARIABLE _RUPJ-C-NEXT-UTF8
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
    _RUPJ-C-SNAPSHOT @ UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@
        DUP _RUPJ-C-TEXT-CAP !
    UIDL-LABEL-SNAPSHOT-BYTES _RUPJ-C-EXACT @ <> IF
        _RUPJ-SET-INVALID EXIT
    THEN
    _RUPJ-UTF8-QUOTA @ _RUPJ-C-TEXT-CAP @ _RUPJ-UADD? 0= IF
        DROP _RUPJ-SET-CAPACITY EXIT
    THEN
    DUP _RUPJ-LENGTH-MAX U> IF
        DROP _RUPJ-SET-CAPACITY EXIT
    THEN
    _RUPJ-C-NEXT-UTF8 !

    _RUPJ-ITEM-COUNT @ _RUPJ-ITEM-AT DUP _RUPJ-C-ITEM !
    RUPJ-ITEM-SIZE 0 FILL
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

: _RUPJ-FAIL-RESULT  ( status -- 0 0 0 0 0 status )
    _RUPJ-STATUS !
    _RUPJ-CLEAR-BANKS
    0 0 0 0 0 _RUPJ-STATUS @ ;

: _RUPJ-BUILD-BODY  ( -- item-count snapshot-used regions objects utf8 status )
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
    _RUPJ-WALK
    _RUPJ-STATUS @ RUPJ-S-OK <> IF
        _RUPJ-STATUS @ _RUPJ-FAIL-RESULT EXIT
    THEN

    _RUPJ-ITEM-COUNT @
    _RUPJ-SNAPSHOT-USED @
    _RUPJ-ITEM-COUNT @ 0<> IF 1 ELSE 0 THEN
    _RUPJ-ITEM-COUNT @
    _RUPJ-UTF8-QUOTA @
    RUPJ-S-OK ;

: _RUPJ-BUILD-CALL  ( -- item-count snapshot-used regions objects utf8 status )
    ['] _RUPJ-BUILD-BODY UIDL-SEMANTIC-OBSERVE ;

: _RUPJ-SCRUB  ( -- )
    0 _RUPJ-V-ITEMS-A ! 0 _RUPJ-V-ITEMS-U !
    0 _RUPJ-V-ITEM-COUNT ! 0 _RUPJ-V-SNAPSHOTS-A !
    0 _RUPJ-V-SNAPSHOTS-U ! 0 _RUPJ-V-SNAPSHOT-USED !
    0 _RUPJ-V-REGIONS ! 0 _RUPJ-V-OBJECTS ! 0 _RUPJ-V-UTF8 !
    0 _RUPJ-V-EXPECTED-OFF ! 0 _RUPJ-V-UTF8-SUM !
    0 _RUPJ-V-ITEM ! 0 _RUPJ-V-SNAPSHOT ! 0 _RUPJ-V-EXACT !
    0 _RUPJ-V-STRIDE ! 0 _RUPJ-V-TEXT-CAP !
    0 _RUPJ-V-KEY ! 0 _RUPJ-V-UPTO !
    0 _RUPJ-ITEMS-A ! 0 _RUPJ-ITEMS-U ! 0 _RUPJ-ITEM-CAP !
    0 _RUPJ-SNAPSHOTS-A ! 0 _RUPJ-SNAPSHOTS-U !
    0 _RUPJ-RANGES-VALID ! 0 _RUPJ-STATUS !
    0 _RUPJ-ELEMENT-TOTAL ! 0 _RUPJ-VISITED !
    0 _RUPJ-ITEM-COUNT ! 0 _RUPJ-SNAPSHOT-USED !
    0 _RUPJ-UTF8-QUOTA !
    0 _RUPJ-C-ELEM ! 0 _RUPJ-C-INDEX ! 0 _RUPJ-C-EXACT !
    0 _RUPJ-C-STRIDE ! 0 _RUPJ-C-SNAPSHOT ! 0 _RUPJ-C-ITEM !
    0 _RUPJ-C-TEXT-CAP ! 0 _RUPJ-C-NEXT-SNAPSHOT !
    0 _RUPJ-C-NEXT-UTF8 ! 0 _RUPJ-KEY ! ;

\ RUPJ-BUILD
\   Capture all currently supported LABEL semantics in root preorder.  A
\   LABEL without an explicit neutral capacity is skipped for ordinary CELL
\   fallback.  On success, item-count/object-quota are equal, region-quota is
\   one iff any item exists, UTF8 quota is the checked sum of raw declarations,
\   and snapshot-used is the checked sum of aligned record strides.
\
\   The complete destination is cleared before construction.  Any failure or
\   caught exception clears it again and returns five zero results plus a
\   stable status, so no partial candidate can be mistaken for publication.
: RUPJ-BUILD
  ( items-a items-u snapshots-a snapshots-u
    -- item-count snapshot-used region-quota object-quota utf8-quota status )
    _RUPJ-SNAPSHOTS-U ! _RUPJ-SNAPSHOTS-A !
    _RUPJ-ITEMS-U ! _RUPJ-ITEMS-A !
    0 _RUPJ-RANGES-VALID !
    ['] _RUPJ-BUILD-CALL CATCH ?DUP IF
        DROP RUPJ-S-INVALID _RUPJ-FAIL-RESULT
    THEN
    _RUPJ-SCRUB ;

: RUPJ-CANDIDATE-VALID?
  ( items-a items-u item-count snapshots-a snapshots-u snapshot-used
    region-quota object-quota utf8-quota -- flag )
    _RUPJ-V-UTF8 ! _RUPJ-V-OBJECTS ! _RUPJ-V-REGIONS !
    _RUPJ-V-SNAPSHOT-USED ! _RUPJ-V-SNAPSHOTS-U !
    _RUPJ-V-SNAPSHOTS-A ! _RUPJ-V-ITEM-COUNT !
    _RUPJ-V-ITEMS-U ! _RUPJ-V-ITEMS-A !
    ['] _RUPJ-V-CALL CATCH ?DUP IF DROP 0 THEN
    _RUPJ-SCRUB ;

\ Guarded builds serialize the complete borrowed-bank lifetime.  UIDL stays
\ outermost: callers enter its observation before acquiring projector scratch,
\ and the raw builder then enters the recursive complete semantic observation.
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _rupj-guard

' RUPJ-BUILD             CONSTANT _rupj-build-xt
' RUPJ-CANDIDATE-VALID?  CONSTANT _rupj-candidate-valid-q-xt

: _RUPJ-BUILD-GUARDED
  ( items-a items-u snapshots-a snapshots-u
    -- item-count snapshot-used region-quota object-quota utf8-quota status )
    _rupj-build-xt _rupj-guard WITH-GUARD ;

: RUPJ-BUILD
  ( items-a items-u snapshots-a snapshots-u
    -- item-count snapshot-used region-quota object-quota utf8-quota status )
    ['] _RUPJ-BUILD-GUARDED UIDL-OBSERVE ;

: RUPJ-CANDIDATE-VALID?
  ( items-a items-u item-count snapshots-a snapshots-u snapshot-used
    region-quota object-quota utf8-quota -- flag )
    _rupj-candidate-valid-q-xt _rupj-guard WITH-GUARD ;
[THEN] [THEN]
