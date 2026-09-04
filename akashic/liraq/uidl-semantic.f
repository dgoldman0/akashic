\ =====================================================================
\  uidl-semantic.f -- renderer-neutral UIDL semantic snapshots
\ =====================================================================
\
\  Semantic snapshots are derived, caller-owned copies of the values in a
\  UIDL element.  They contain no terminal, screen, region, or provider
\  identity.  Element definitions publish one neutral capture hook through
\  ED.SEMANTICS; ( destination=0 capacity=0 ) is the exact measure call.
\
\  The first snapshot family is LABEL.  Every label with valid resolved text
\  is eligible.  The destination record owns an exact copy of the current
\  text; renderer allocation remains outside UIDL semantics.
\
\  Prefix: UIDL- (public), _UIDLS- (private)
\  Provider: akashic-uidl-semantic
\
\  Public compound seam:
\    UIDL-SEMANTIC-OBSERVE  ( i*x xt -- j*x )
\    UIDL-SEMANTIC-STORAGE-DISJOINT?  ( address length -- flag )

PROVIDED akashic-uidl-semantic

REQUIRE uidl.f
REQUIRE ../text/utf8.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Stable snapshot status and kind values
\ =====================================================================

0 CONSTANT UIDL-SNAP-S-OK
1 CONSTANT UIDL-SNAP-S-UNSUPPORTED
2 CONSTANT UIDL-SNAP-S-CAPACITY
3 CONSTANT UIDL-SNAP-S-INVALID

: UIDL-SNAP-STATUS-VALID?  ( status -- flag )  4 U< ;

1 CONSTANT UIDL-SNAPSHOT-K-LABEL

\ In an unguarded build this is simply a scoped execution seam.  Guarded
\ builds redefine it below so one caller can hold the complete canonical
\ UIDL -> semantic scratch -> LEL -> state observation while deriving more
\ than one snapshot.
: UIDL-SEMANTIC-OBSERVE  ( i*x xt -- j*x )  EXECUTE ;

\ =====================================================================
\  Shared text-value semantics
\ =====================================================================

\ A native signed cell has at most 20 decimal bytes.  This fixed conversion
\ scratch is an ABI-derived scalar bound, not an application text capacity.
\ _uidls-guard protects it across complete snapshot capture; UIDL-TEXT@
\ exposes it only with the call-borrowed lifetime documented below.
CREATE _UIDLS-OWNED-START
CREATE _UIDLS-NUM-TEXT 24 ALLOT
VARIABLE _UIDLS-NUM-POS
VARIABLE _UIDLS-NUM-NEG
VARIABLE _UIDLS-OWNED-LIMIT

0 _UIDLS-OWNED-LIMIT !

: _UIDLS-NUM>TEXT  ( n -- a u )
    DUP 0= IF
        DROP 23 _UIDLS-NUM-POS !
        48 _UIDLS-NUM-TEXT 23 + C!
        _UIDLS-NUM-TEXT 23 + 1 EXIT
    THEN
    DUP 0< _UIDLS-NUM-NEG !
    DUP 0> IF NEGATE THEN
    23 _UIDLS-NUM-POS !
    BEGIN DUP 0< WHILE
        DUP 10 MOD NEGATE 48 +
        _UIDLS-NUM-TEXT _UIDLS-NUM-POS @ + C!
        -1 _UIDLS-NUM-POS +!
        10 /
    REPEAT
    DROP
    _UIDLS-NUM-NEG @ IF
        45 _UIDLS-NUM-TEXT _UIDLS-NUM-POS @ + C!
        _UIDLS-NUM-TEXT _UIDLS-NUM-POS @ +
        23 _UIDLS-NUM-POS @ - 1+
    ELSE
        _UIDLS-NUM-TEXT _UIDLS-NUM-POS @ 1+ +
        23 _UIDLS-NUM-POS @ -
    THEN
    0 _UIDLS-NUM-POS ! 0 _UIDLS-NUM-NEG ! ;

\ The returned span is borrowed only until the next operation which can
\ mutate its source.  Integer conversion uses the module's protected scalar
\ scratch.  Snapshot capture copies the bytes synchronously while its guard
\ remains held.
: _UIDLS-VALUE>TEXT  ( type v1 v2 -- a u )
    ROT
    DUP ST-T-STRING = IF DROP EXIT THEN
    DUP ST-T-INTEGER = IF
        DROP DROP _UIDLS-NUM>TEXT EXIT
    THEN
    DUP ST-T-BOOLEAN = IF
        DROP DROP
        IF S" true" ELSE S" false" THEN EXIT
    THEN
    2DROP DROP S" " ;

: _UIDLS-TEXT@  ( elem -- a u )
    DUP UIDL-BIND IF
        ROT DROP
        LEL-EVAL _UIDLS-VALUE>TEXT
    ELSE
        2DROP
        S" text" UIDL-ATTR IF EXIT THEN
        2DROP 0 0
    THEN ;

: _UIDLS-TEXT-IN-STATE  ( elem -- a u )
    _UIDLS-TEXT@ ;

: _UIDLS-TEXT-IN-LEL  ( elem -- a u )
    ['] _UIDLS-TEXT-IN-STATE ST-OBSERVE ;

: _UIDLS-TEXT-IN-UIDL  ( elem -- a u )
    ['] _UIDLS-TEXT-IN-LEL LEL-OBSERVE ;

: UIDL-TEXT@  ( elem -- a u )
    ['] _UIDLS-TEXT-IN-UIDL UIDL-OBSERVE ;

\ =====================================================================
\  LABEL snapshot record
\ =====================================================================
\
\  +0   magic             "UIDLSNAP"
\  +8   reserved          0
\  +16  semantic kind     UIDL-SNAPSHOT-K-LABEL
\  +24  exact record bytes (64 + current text bytes)
\  +32  flags             0
\  +40  current text bytes
\  +48  reserved          0
\  +56  reserved          0
\  +64  copied current text

\ MegaPad records are native little-endian.  This numeric cell is chosen so
\ its in-memory bytes are the literal publication tag "UIDLSNAP".
0x50414E534C444955 CONSTANT _UIDLS-SNAPSHOT-MAGIC
64 CONSTANT UIDL-LABEL-SNAPSHOT-HEADER-SIZE
-1 1 RSHIFT CONSTANT _UIDLS-LENGTH-MAX

: _UIDLS-S.MAGIC     ( s -- a )       ;
: _UIDLS-S.RESERVED  ( s -- a )   8 + ;
: _UIDLS-S.KIND      ( s -- a )  16 + ;
: _UIDLS-S.BYTES     ( s -- a )  24 + ;
: _UIDLS-S.FLAGS     ( s -- a )  32 + ;
: _UIDLS-SL.TEXT-U   ( s -- a )  40 + ;
: _UIDLS-SL.RESERVED0 ( s -- a ) 48 + ;
: _UIDLS-SL.RESERVED1 ( s -- a ) 56 + ;
: _UIDLS-SL.TEXT     ( s -- a )  64 + ;

: _UIDLS-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

: UIDL-LABEL-SNAPSHOT-BYTES  ( text-bytes -- bytes | 0 )
    DUP 0< IF DROP 0 EXIT THEN
    UIDL-LABEL-SNAPSHOT-HEADER-SIZE SWAP _UIDLS-UADD? 0= IF
        DROP 0 EXIT
    THEN
    DUP _UIDLS-LENGTH-MAX U> IF DROP 0 THEN ;

: UIDL-LABEL-SNAPSHOT-BYTES@  ( snapshot -- bytes )
    _UIDLS-S.BYTES @ ;

: UIDL-LABEL-SNAPSHOT-TEXT@  ( snapshot -- a u )
    DUP _UIDLS-SL.TEXT SWAP _UIDLS-SL.TEXT-U @ ;

\ =====================================================================
\  LABEL text and capture preflight
\ =====================================================================

: _UIDLS-LABEL-FORBIDDEN-BYTE?  ( byte -- flag )
    DUP 0= OVER 10 = OR SWAP 13 = OR ;

: _UIDLS-LABEL-TEXT?  ( a u -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    2DUP UTF8-VALID? 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ _UIDLS-LABEL-FORBIDDEN-BYTE? IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

VARIABLE _UIDLS-LABEL-ELEM
VARIABLE _UIDLS-LABEL-DST
VARIABLE _UIDLS-LABEL-DST-CAP
VARIABLE _UIDLS-LABEL-TEXT-A
VARIABLE _UIDLS-LABEL-TEXT-U
VARIABLE _UIDLS-LABEL-TOTAL
VARIABLE _UIDLS-LABEL-P-ELEM
VARIABLE _UIDLS-LABEL-P-DST
VARIABLE _UIDLS-LABEL-P-CAP

: _UIDLS-LABEL-FINISH  ( bytes status -- bytes status )
    0 _UIDLS-LABEL-ELEM !
    0 _UIDLS-LABEL-DST ! 0 _UIDLS-LABEL-DST-CAP !
    0 _UIDLS-LABEL-TEXT-A ! 0 _UIDLS-LABEL-TEXT-U !
    0 _UIDLS-LABEL-TOTAL !
    0 _UIDLS-LABEL-P-ELEM ! 0 _UIDLS-LABEL-P-DST !
    0 _UIDLS-LABEL-P-CAP ! ;

: _UIDLS-LABEL-PREPARE  ( -- status )
    _UIDLS-LABEL-ELEM @ _UIDLS-TEXT@
    _UIDLS-LABEL-TEXT-U ! _UIDLS-LABEL-TEXT-A !
    _UIDLS-LABEL-TEXT-A @ _UIDLS-LABEL-TEXT-U @
        _UIDLS-LABEL-TEXT? 0= IF UIDL-SNAP-S-INVALID EXIT THEN
    _UIDLS-LABEL-TEXT-U @ UIDL-LABEL-SNAPSHOT-BYTES
    DUP 0= IF DROP UIDL-SNAP-S-CAPACITY EXIT THEN
    _UIDLS-LABEL-TOTAL !
    UIDL-SNAP-S-OK ;

\ One hook serves both measurement and capture.  Exact (0,0) measures.
\ Every ordinary failure is decided before the destination is modified.
: _UIDLS-LABEL-CAPTURE-BODY  ( elem destination capacity -- bytes status )
    _UIDLS-LABEL-DST-CAP ! _UIDLS-LABEL-DST ! _UIDLS-LABEL-ELEM !
    _UIDLS-LABEL-PREPARE
    DUP UIDL-SNAP-S-OK <> IF
        0 SWAP EXIT
    THEN
    DROP

    _UIDLS-LABEL-DST @ 0= IF
        _UIDLS-LABEL-DST-CAP @ 0= IF
            _UIDLS-LABEL-TOTAL @ UIDL-SNAP-S-OK
        ELSE
            0 UIDL-SNAP-S-INVALID
        THEN
        EXIT
    THEN

    _UIDLS-LABEL-DST-CAP @ 0< IF
        0 UIDL-SNAP-S-INVALID EXIT
    THEN
    _UIDLS-LABEL-DST @ 7 AND IF
        0 UIDL-SNAP-S-INVALID EXIT
    THEN
    _UIDLS-LABEL-DST @ _UIDLS-LABEL-DST-CAP @
        MSPAN-NONWRAPPING? 0= IF
        0 UIDL-SNAP-S-INVALID EXIT
    THEN
    _UIDLS-LABEL-TOTAL @ _UIDLS-LABEL-DST-CAP @ U> IF
        0 UIDL-SNAP-S-CAPACITY EXIT
    THEN
    _UIDLS-LABEL-DST @ _UIDLS-LABEL-TOTAL @
        UIDL-STORAGE-DISJOINT? 0= IF
        0 UIDL-SNAP-S-INVALID EXIT
    THEN
    _UIDLS-LABEL-DST @ _UIDLS-LABEL-TOTAL @
        ST-STORAGE-DISJOINT? 0= IF
        0 UIDL-SNAP-S-INVALID EXIT
    THEN
    _UIDLS-LABEL-TEXT-A @ _UIDLS-LABEL-TEXT-U @
    _UIDLS-LABEL-DST @ _UIDLS-LABEL-TOTAL @ MSPAN-OVERLAP? IF
        0 UIDL-SNAP-S-INVALID EXIT
    THEN

    _UIDLS-LABEL-DST @ _UIDLS-LABEL-TOTAL @ 0 FILL
    UIDL-SNAPSHOT-K-LABEL _UIDLS-LABEL-DST @ _UIDLS-S.KIND !
    _UIDLS-LABEL-TOTAL @ _UIDLS-LABEL-DST @ _UIDLS-S.BYTES !
    _UIDLS-LABEL-TEXT-U @ _UIDLS-LABEL-DST @ _UIDLS-SL.TEXT-U !
    _UIDLS-LABEL-TEXT-A @ _UIDLS-LABEL-DST @ _UIDLS-SL.TEXT
        _UIDLS-LABEL-TEXT-U @ CMOVE
    _UIDLS-SNAPSHOT-MAGIC _UIDLS-LABEL-DST @ _UIDLS-S.MAGIC !
    _UIDLS-LABEL-TOTAL @ UIDL-SNAP-S-OK ;

: _UIDLS-LABEL-CAPTURE-CALL  ( -- bytes status )
    _UIDLS-LABEL-P-ELEM @ _UIDLS-LABEL-P-DST @ _UIDLS-LABEL-P-CAP @
    _UIDLS-LABEL-CAPTURE-BODY ;

\ Convert source/helper exceptions to the stable snapshot status and scrub
\ every borrowed pointer on both normal and exceptional exits.
: _UIDLS-LABEL-CAPTURE  ( elem destination capacity -- bytes status )
    _UIDLS-LABEL-P-CAP ! _UIDLS-LABEL-P-DST ! _UIDLS-LABEL-P-ELEM !
    ['] _UIDLS-LABEL-CAPTURE-CALL CATCH ?DUP IF
        DROP 0 UIDL-SNAP-S-INVALID
    THEN
    _UIDLS-LABEL-FINISH ;

\ =====================================================================
\  Generic element snapshot dispatch
\ =====================================================================

: _UIDLS-DROP3  ( x1 x2 x3 -- )  2DROP DROP ;

: _UIDLS-CANONICAL-RESULT  ( bytes status -- bytes status )
    DUP UIDL-SNAP-STATUS-VALID? 0= IF
        2DROP 0 UIDL-SNAP-S-INVALID EXIT
    THEN
    DUP UIDL-SNAP-S-OK = IF
        OVER 0> IF EXIT THEN
        2DROP 0 UIDL-SNAP-S-INVALID EXIT
    THEN
    NIP 0 SWAP ;

: _UIDLS-SNAPSHOT-DISPATCH  ( elem destination capacity -- bytes status )
    ROT DUP UIDL-TYPE EL-DEF-BY-TYPE
    DUP 0= IF
        DROP _UIDLS-DROP3 0 UIDL-SNAP-S-UNSUPPORTED EXIT
    THEN
    ED.SEMANTICS @ DUP 0= IF
        DROP _UIDLS-DROP3 0 UIDL-SNAP-S-UNSUPPORTED EXIT
    THEN
    >R -ROT R> EXECUTE
    _UIDLS-CANONICAL-RESULT ;

VARIABLE _UIDLS-SNAP-P-ELEM
VARIABLE _UIDLS-SNAP-P-DST
VARIABLE _UIDLS-SNAP-P-CAP

: _UIDLS-SNAP-P-CLEAR  ( -- )
    0 _UIDLS-SNAP-P-ELEM ! 0 _UIDLS-SNAP-P-DST !
    0 _UIDLS-SNAP-P-CAP ! ;

: _UIDLS-SNAPSHOT-IN-STATE  ( -- bytes status )
    _UIDLS-SNAP-P-ELEM @ _UIDLS-SNAP-P-DST @ _UIDLS-SNAP-P-CAP @
    _UIDLS-SNAPSHOT-DISPATCH ;

: _UIDLS-SNAPSHOT-IN-LEL  ( -- bytes status )
    ['] _UIDLS-SNAPSHOT-IN-STATE ST-OBSERVE ;

: _UIDLS-SNAPSHOT-IN-UIDL  ( -- bytes status )
    ['] _UIDLS-SNAPSHOT-IN-LEL LEL-OBSERVE ;

: _UIDLS-SNAPSHOT-CALL  ( -- bytes status )
    ['] _UIDLS-SNAPSHOT-IN-UIDL UIDL-OBSERVE ;

: UIDL-SNAPSHOT-CAPTURE  ( elem destination capacity -- bytes status )
    _UIDLS-SNAP-P-CAP ! _UIDLS-SNAP-P-DST ! _UIDLS-SNAP-P-ELEM !
    ['] _UIDLS-SNAPSHOT-CALL CATCH ?DUP IF
        DROP 0 UIDL-SNAP-S-INVALID
    THEN
    _UIDLS-SNAP-P-CLEAR
    _UIDLS-CANONICAL-RESULT ;

: UIDL-SNAPSHOT-SIZE  ( elem -- bytes status )
    0 0 UIDL-SNAPSHOT-CAPTURE ;

\ Install the one current neutral semantic family.  Renderers consume the
\ public UIDL words and do not install, replace, or name this hook.
' _UIDLS-LABEL-CAPTURE UIDL-T-LABEL EL-SET-SEMANTICS

\ =====================================================================
\  Published LABEL snapshot validation
\ =====================================================================

VARIABLE _UIDLS-LV-SNAPSHOT
VARIABLE _UIDLS-LV-AVAILABLE
VARIABLE _UIDLS-LV-TEXT-U
VARIABLE _UIDLS-LV-TOTAL
VARIABLE _UIDLS-LV-P-SNAPSHOT
VARIABLE _UIDLS-LV-P-AVAILABLE

: _UIDLS-LV-FINISH  ( flag -- flag )
    0 _UIDLS-LV-SNAPSHOT ! 0 _UIDLS-LV-AVAILABLE !
    0 _UIDLS-LV-TEXT-U !
    0 _UIDLS-LV-TOTAL ! ;

: _UIDLS-LV-P-CLEAR  ( -- )
    0 _UIDLS-LV-P-SNAPSHOT ! 0 _UIDLS-LV-P-AVAILABLE ! ;

: _UIDLS-LABEL-SNAPSHOT-VALID-BODY?  ( snapshot available -- flag )
    _UIDLS-LV-AVAILABLE ! _UIDLS-LV-SNAPSHOT !
    _UIDLS-LV-AVAILABLE @ 0< IF 0 _UIDLS-LV-FINISH EXIT THEN
    _UIDLS-LV-SNAPSHOT @ 0= IF 0 _UIDLS-LV-FINISH EXIT THEN
    _UIDLS-LV-SNAPSHOT @ 7 AND IF 0 _UIDLS-LV-FINISH EXIT THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-LV-AVAILABLE @
        MSPAN-NONWRAPPING? 0= IF 0 _UIDLS-LV-FINISH EXIT THEN
    _UIDLS-LV-AVAILABLE @ UIDL-LABEL-SNAPSHOT-HEADER-SIZE U< IF
        0 _UIDLS-LV-FINISH EXIT
    THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-S.MAGIC @
        _UIDLS-SNAPSHOT-MAGIC <> IF 0 _UIDLS-LV-FINISH EXIT THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-S.RESERVED @ IF
        0 _UIDLS-LV-FINISH EXIT
    THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-S.KIND @
        UIDL-SNAPSHOT-K-LABEL <> IF 0 _UIDLS-LV-FINISH EXIT THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-S.FLAGS @ IF
        0 _UIDLS-LV-FINISH EXIT
    THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-SL.RESERVED0 @ IF
        0 _UIDLS-LV-FINISH EXIT
    THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-SL.RESERVED1 @ IF
        0 _UIDLS-LV-FINISH EXIT
    THEN

    _UIDLS-LV-SNAPSHOT @ _UIDLS-SL.TEXT-U @
    DUP 0< IF DROP 0 _UIDLS-LV-FINISH EXIT THEN
    DUP _UIDLS-LV-TEXT-U ! UIDL-LABEL-SNAPSHOT-BYTES
    DUP 0= IF DROP 0 _UIDLS-LV-FINISH EXIT THEN
    DUP _UIDLS-LV-TOTAL !
    _UIDLS-LV-SNAPSHOT @ _UIDLS-S.BYTES @ <> IF
        0 _UIDLS-LV-FINISH EXIT
    THEN
    _UIDLS-LV-TOTAL @ _UIDLS-LV-AVAILABLE @ U> IF
        0 _UIDLS-LV-FINISH EXIT
    THEN
    _UIDLS-LV-SNAPSHOT @ _UIDLS-SL.TEXT _UIDLS-LV-TEXT-U @
        _UIDLS-LABEL-TEXT? 0= IF 0 _UIDLS-LV-FINISH EXIT THEN
    -1 _UIDLS-LV-FINISH ;

: _UIDLS-LABEL-SNAPSHOT-VALID-CALL  ( -- flag )
    _UIDLS-LV-P-SNAPSHOT @ _UIDLS-LV-P-AVAILABLE @
    _UIDLS-LABEL-SNAPSHOT-VALID-BODY? ;

: UIDL-LABEL-SNAPSHOT-VALID?  ( snapshot available -- flag )
    _UIDLS-LV-P-AVAILABLE ! _UIDLS-LV-P-SNAPSHOT !
    ['] _UIDLS-LABEL-SNAPSHOT-VALID-CALL CATCH ?DUP IF
        DROP 0 _UIDLS-LV-FINISH
    THEN
    _UIDLS-LV-P-CLEAR ;

\ Reject overlap with semantic conversion, capture, validation, and guard
\ storage.  The conservative provider span also covers the implementation
\ threaded between those cells; callers never need to place derived output
\ inside this module's dictionary extent.
: _UIDLS-STORAGE-DISJOINT-BODY?  ( address length -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _UIDLS-OWNED-LIMIT @ DUP _UIDLS-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _UIDLS-OWNED-START - >R
    2DUP _UIDLS-OWNED-START R> MSPAN-OVERLAP? 0= NIP NIP ;

: UIDL-SEMANTIC-STORAGE-DISJOINT?  ( address length -- flag )
    ['] _UIDLS-STORAGE-DISJOINT-BODY? CATCH ?DUP IF
        DROP 2DROP 0
    THEN ;

\ =====================================================================
\  Guard public calls which use semantic scratch
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _uidls-guard

' UIDL-TEXT@                  CONSTANT _uidls-text-at-xt
' UIDL-SNAPSHOT-CAPTURE       CONSTANT _uidls-snapshot-capture-xt
' UIDL-SNAPSHOT-SIZE          CONSTANT _uidls-snapshot-size-xt
' UIDL-LABEL-SNAPSHOT-VALID?  CONSTANT _uidls-label-valid-q-xt

\ The caller's xt stays on the data stack until the innermost observation.
\ Each helper adds exactly one guard around the next helper, preserving body
\ results and exceptions through the generic observation/guard seams.
: _UIDLS-OBSERVE-IN-STATE  ( i*x xt -- j*x )
    ST-OBSERVE ;

: _UIDLS-OBSERVE-IN-LEL  ( i*x xt -- j*x )
    ['] _UIDLS-OBSERVE-IN-STATE LEL-OBSERVE ;

: _UIDLS-OBSERVE-WITH-SEMANTIC  ( i*x xt -- j*x )
    ['] _UIDLS-OBSERVE-IN-LEL _uidls-guard WITH-GUARD ;

\ UIDL is always acquired before semantic scratch.  A caller may already own
\ the document guard while invoking a neutral semantic operation; preserving
\ that global order prevents an AB/BA cycle with a concurrent snapshot caller.
\ The raw words' nested UIDL observations are recursive for the same owner.
: _UIDLS-TEXT-AT-GUARDED  ( elem -- a u )
    _uidls-text-at-xt _uidls-guard WITH-GUARD ;

: _UIDLS-SNAPSHOT-CAPTURE-GUARDED
  ( elem destination capacity -- bytes status )
    _uidls-snapshot-capture-xt _uidls-guard WITH-GUARD ;

: _UIDLS-SNAPSHOT-SIZE-GUARDED  ( elem -- bytes status )
    _uidls-snapshot-size-xt _uidls-guard WITH-GUARD ;

: UIDL-TEXT@  ( elem -- a u )
    ['] _UIDLS-TEXT-AT-GUARDED UIDL-OBSERVE ;

: UIDL-SNAPSHOT-CAPTURE
  ( elem destination capacity -- bytes status )
    ['] _UIDLS-SNAPSHOT-CAPTURE-GUARDED UIDL-OBSERVE ;

: UIDL-SNAPSHOT-SIZE  ( elem -- bytes status )
    ['] _UIDLS-SNAPSHOT-SIZE-GUARDED UIDL-OBSERVE ;

: UIDL-LABEL-SNAPSHOT-VALID?  _uidls-label-valid-q-xt _uidls-guard WITH-GUARD ;

: UIDL-SEMANTIC-OBSERVE  ( i*x xt -- j*x )
    ['] _UIDLS-OBSERVE-WITH-SEMANTIC UIDL-OBSERVE ;
[THEN] [THEN]

CREATE _UIDLS-OWNED-END
_UIDLS-OWNED-END _UIDLS-OWNED-LIMIT !
