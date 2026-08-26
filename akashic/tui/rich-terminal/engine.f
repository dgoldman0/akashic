\ =====================================================================
\  engine.f -- backend-neutral retained semantic-engine facade
\ =====================================================================
\
\  This internal composition ABI keeps UIDL lifecycle/projector code above
\  concrete terminal engines.  This revision exposes the bound provider's
\  owner and transaction operations, one immutable negotiated-limits snapshot,
\  one call-borrowed neutral LABEL definition, and one mutation-free LABEL
\  admission plan.  The descriptor is caller-owned, immutable after provider
\  construction, and carries one explicit provider context.  It owns no
\  storage, transport, host, UCTX, Desk, or application authority.
\
\  Prefix: RTE- (public), _RTE- (private)
\  Provider: akashic-tui-rte1

PROVIDED akashic-tui-rte1

REQUIRE ../../utils/memory-span.f

\ Stable neutral statuses.  UIDL's RTERM contract aliases these values.
0 CONSTANT RTE-S-OK
1 CONSTANT RTE-S-WOULD-BLOCK
2 CONSTANT RTE-S-UNAVAILABLE
3 CONSTANT RTE-S-CAPACITY
4 CONSTANT RTE-S-STALE
5 CONSTANT RTE-S-INVALID
6 CONSTANT RTE-S-SESSION-LOST
7 CONSTANT RTE-S-SOURCE

: RTE-STATUS-VALID?  ( status -- flag )  8 U< ;

\ Coarse owner states deliberately hide provider queue/tombstone details.
0 CONSTANT RTE-OWNER-ST-FREE
1 CONSTANT RTE-OWNER-ST-OPENING
2 CONSTANT RTE-OWNER-ST-OPEN
3 CONSTANT RTE-OWNER-ST-DROPPING
4 CONSTANT RTE-OWNER-ST-TOMBSTONE
5 CONSTANT RTE-OWNER-ST-QUARANTINED

: RTE-OWNER-STATE-VALID?  ( owner-state -- flag )
    6 U< ;

\ Neutral retained feature families.  These are Akashic capability bits, not
\ provider-specific values.  CORE is required; SERIES depends on INSTRUMENT.
1  CONSTANT RTE-F-CORE
2  CONSTANT RTE-F-VECTOR
4  CONSTANT RTE-F-IMAGE
8  CONSTANT RTE-F-INSTRUMENT
16 CONSTANT RTE-F-SERIES
32 CONSTANT RTE-F-CADENCE
0x3F CONSTANT _RTE-FEATURE-MASK

\ One fixed ABI record captures negotiated admission bounds.  Its size is a
\ record shape, never a product capacity.  Every count and byte maximum comes
\ from the provider's coherent current-epoch capability snapshot.
: _RTE-L.FEATURES        ( l -- a )       ;
: _RTE-L.OWNER-RECORDS   ( l -- a )   8 + ;
: _RTE-L.LIVE-OWNERS     ( l -- a )  16 + ;
: _RTE-L.REGIONS         ( l -- a )  24 + ;
: _RTE-L.RESOURCES       ( l -- a )  32 + ;
: _RTE-L.OBJECTS         ( l -- a )  40 + ;
: _RTE-L.SERIES          ( l -- a )  48 + ;
: _RTE-L.OPS             ( l -- a )  56 + ;
: _RTE-L.UPDATE-BYTES    ( l -- a )  64 + ;
: _RTE-L.CHUNK-BYTES     ( l -- a )  72 + ;
: _RTE-L.RESOURCE-BYTES  ( l -- a )  80 + ;
: _RTE-L.IMAGE-WIDTH     ( l -- a )  88 + ;
: _RTE-L.IMAGE-HEIGHT    ( l -- a )  96 + ;
: _RTE-L.PATH-POINTS     ( l -- a ) 104 + ;
: _RTE-L.LABEL-BYTES     ( l -- a ) 112 + ;
: _RTE-L.UTF8-BYTES      ( l -- a ) 120 + ;
: _RTE-L.SAMPLES-APPEND  ( l -- a ) 128 + ;
: _RTE-L.SERIES-HISTORY  ( l -- a ) 136 + ;
: _RTE-L.SAMPLE-SLOTS    ( l -- a ) 144 + ;
: _RTE-L.MIN-INTERVAL-US ( l -- a ) 152 + ;

160 CONSTANT RTE-LIMITS-SIZE

: RTE-LIMITS-BYTES  ( -- bytes )  RTE-LIMITS-SIZE ;

: RTE-LIMITS-FEATURES@        ( l -- u )  _RTE-L.FEATURES @ ;
: RTE-LIMITS-OWNER-RECORDS@   ( l -- u )  _RTE-L.OWNER-RECORDS @ ;
: RTE-LIMITS-LIVE-OWNERS@     ( l -- u )  _RTE-L.LIVE-OWNERS @ ;
: RTE-LIMITS-REGIONS@         ( l -- u )  _RTE-L.REGIONS @ ;
: RTE-LIMITS-RESOURCES@       ( l -- u )  _RTE-L.RESOURCES @ ;
: RTE-LIMITS-OBJECTS@         ( l -- u )  _RTE-L.OBJECTS @ ;
: RTE-LIMITS-SERIES@          ( l -- u )  _RTE-L.SERIES @ ;
: RTE-LIMITS-OPS@             ( l -- u )  _RTE-L.OPS @ ;
: RTE-LIMITS-UPDATE-BYTES@    ( l -- u )  _RTE-L.UPDATE-BYTES @ ;
: RTE-LIMITS-CHUNK-BYTES@     ( l -- u )  _RTE-L.CHUNK-BYTES @ ;
: RTE-LIMITS-RESOURCE-BYTES@  ( l -- u )  _RTE-L.RESOURCE-BYTES @ ;
: RTE-LIMITS-IMAGE-WIDTH@     ( l -- u )  _RTE-L.IMAGE-WIDTH @ ;
: RTE-LIMITS-IMAGE-HEIGHT@    ( l -- u )  _RTE-L.IMAGE-HEIGHT @ ;
: RTE-LIMITS-PATH-POINTS@     ( l -- u )  _RTE-L.PATH-POINTS @ ;
: RTE-LIMITS-LABEL-BYTES@     ( l -- u )  _RTE-L.LABEL-BYTES @ ;
: RTE-LIMITS-UTF8-BYTES@      ( l -- u )  _RTE-L.UTF8-BYTES @ ;
: RTE-LIMITS-SAMPLES-APPEND@  ( l -- u )  _RTE-L.SAMPLES-APPEND @ ;
: RTE-LIMITS-SERIES-HISTORY@  ( l -- u )  _RTE-L.SERIES-HISTORY @ ;
: RTE-LIMITS-SAMPLE-SLOTS@    ( l -- u )  _RTE-L.SAMPLE-SLOTS @ ;
: RTE-LIMITS-MIN-INTERVAL-US@ ( l -- u )  _RTE-L.MIN-INTERVAL-US @ ;

\ Neutral retained update vocabulary.  Values need not equal any provider's.
1 CONSTANT RTE-RETAINED-DELTA
2 CONSTANT RTE-RETAINED-REPLACE-START
3 CONSTANT RTE-RETAINED-REPLACE-CONTINUE
4 CONSTANT RTE-RETAINED-LAYOUT-START
5 CONSTANT RTE-RETAINED-LAYOUT-CONTINUE

0 CONSTANT RTE-COMMIT
1 CONSTANT RTE-COMMIT-AND-REVEAL

4 CONSTANT _RTE-ABI
0x5254454641434134 CONSTANT _RTE-MAGIC  \ "RTEFACA4"

: _RTE-F.MAGIC          ( f -- a )       ;
: _RTE-F.ABI            ( f -- a )   8 + ;
: _RTE-F.SIZE           ( f -- a )  16 + ;
: _RTE-F.SELF           ( f -- a )  24 + ;
: _RTE-F.CONTEXT        ( f -- a )  32 + ;
: _RTE-F.DISJOINT-XT    ( f -- a )  40 + ;
: _RTE-F.STATUS-XT      ( f -- a )  48 + ;
: _RTE-F.OWNER-OPEN-XT  ( f -- a )  56 + ;
: _RTE-F.OWNER-STATE-XT ( f -- a )  64 + ;
: _RTE-F.RETAINED-BEGIN-XT  ( f -- a )  72 + ;
: _RTE-F.REGION-DEF-XT  ( f -- a )  80 + ;
: _RTE-F.RETAINED-SEAL-XT   ( f -- a )  88 + ;
: _RTE-F.RETAINED-CANCEL-XT ( f -- a )  96 + ;
: _RTE-F.OWNER-DROP-XT  ( f -- a ) 104 + ;
: _RTE-F.LIMITS-XT      ( f -- a ) 112 + ;
: _RTE-F.LABEL-DEF-XT   ( f -- a ) 120 + ;
: _RTE-F.LABEL-PREFLIGHT-XT ( f -- a ) 128 + ;

136 CONSTANT RTE-FACADE-SIZE

: RTE-FACADE-BYTES  ( -- bytes )  RTE-FACADE-SIZE ;

\ A LABEL plan describes one root REGION_DEFINE followed by a positive,
\ caller-bounded sequence of LABEL_DEFINE operations.  Each item declares
\ the maximum text bytes which its later definition may consume.  The plan
\ carries no renderer or provider representation and is borrowed only for
\ RTE-LABEL-PREFLIGHT's dynamic extent.
: _RTE-LP.OWNER         ( plan -- a )        ;
: _RTE-LP.GENERATION    ( plan -- a )    8 + ;
: _RTE-LP.SURFACE-COLS  ( plan -- a )   16 + ;
: _RTE-LP.SURFACE-ROWS  ( plan -- a )   24 + ;
: _RTE-LP.REGION-ID     ( plan -- a )   32 + ;
: _RTE-LP.REGION-X      ( plan -- a )   40 + ;
: _RTE-LP.REGION-Y      ( plan -- a )   48 + ;
: _RTE-LP.REGION-COLS   ( plan -- a )   56 + ;
: _RTE-LP.REGION-ROWS   ( plan -- a )   64 + ;
: _RTE-LP.REGION-Z      ( plan -- a )   72 + ;
: _RTE-LP.REGION-FLAGS  ( plan -- a )   80 + ;
: _RTE-LP.ITEMS-A       ( plan -- a )   88 + ;
: _RTE-LP.ITEMS-U       ( plan -- a )   96 + ;
: _RTE-LP.RESERVED      ( plan -- a )  104 + ;

112 CONSTANT RTE-LABEL-PLAN-SIZE

: RTE-LABEL-PLAN-BYTES  ( -- bytes )  RTE-LABEL-PLAN-SIZE ;

: _RTE-LPI.OBJECT        ( item -- a )        ;
: _RTE-LPI.PARENT        ( item -- a )    8 + ;
: _RTE-LPI.ROW           ( item -- a )   16 + ;
: _RTE-LPI.COL           ( item -- a )   24 + ;
: _RTE-LPI.HEIGHT        ( item -- a )   32 + ;
: _RTE-LPI.WIDTH         ( item -- a )   40 + ;
: _RTE-LPI.ROOT-HEIGHT   ( item -- a )   48 + ;
: _RTE-LPI.ROOT-WIDTH    ( item -- a )   56 + ;
: _RTE-LPI.Z             ( item -- a )   64 + ;
: _RTE-LPI.VISIBLE       ( item -- a )   72 + ;
: _RTE-LPI.RGBA          ( item -- a )   80 + ;
: _RTE-LPI.H-ALIGN       ( item -- a )   88 + ;
: _RTE-LPI.V-ALIGN       ( item -- a )   96 + ;
: _RTE-LPI.ELLIPSIZE     ( item -- a )  104 + ;
: _RTE-LPI.TEXT-CAPACITY ( item -- a )  112 + ;
: _RTE-LPI.RESERVED      ( item -- a )  120 + ;

128 CONSTANT RTE-LABEL-PLAN-ITEM-SIZE

: RTE-LABEL-PLAN-ITEM-BYTES  ( -- bytes )
    RTE-LABEL-PLAN-ITEM-SIZE ;

\ A LABEL definition is a call-borrowed renderer-neutral value record.  Its
\ geometry is expressed in integer cells relative to the projection root;
\ providers perform any representation-specific conversion below this ABI.
\ The text bytes are borrowed only for RTE-LABEL-DEFINE's dynamic extent.
: _RTE-LABEL.OWNER       ( label -- a )        ;
: _RTE-LABEL.GENERATION  ( label -- a )    8 + ;
: _RTE-LABEL.OBJECT      ( label -- a )   16 + ;
: _RTE-LABEL.REGION      ( label -- a )   24 + ;
: _RTE-LABEL.PARENT      ( label -- a )   32 + ;
: _RTE-LABEL.ROW         ( label -- a )   40 + ;
: _RTE-LABEL.COL         ( label -- a )   48 + ;
: _RTE-LABEL.HEIGHT      ( label -- a )   56 + ;
: _RTE-LABEL.WIDTH       ( label -- a )   64 + ;
: _RTE-LABEL.ROOT-HEIGHT ( label -- a )   72 + ;
: _RTE-LABEL.ROOT-WIDTH  ( label -- a )   80 + ;
: _RTE-LABEL.Z           ( label -- a )   88 + ;
: _RTE-LABEL.VISIBLE     ( label -- a )   96 + ;
: _RTE-LABEL.RGBA        ( label -- a )  104 + ;
: _RTE-LABEL.H-ALIGN     ( label -- a )  112 + ;
: _RTE-LABEL.V-ALIGN     ( label -- a )  120 + ;
: _RTE-LABEL.ELLIPSIZE   ( label -- a )  128 + ;
: _RTE-LABEL.TEXT-A      ( label -- a )  136 + ;
: _RTE-LABEL.TEXT-U      ( label -- a )  144 + ;
: _RTE-LABEL.RESERVED    ( label -- a )  152 + ;

160 CONSTANT RTE-LABEL-SIZE

: RTE-LABEL-BYTES  ( -- bytes )  RTE-LABEL-SIZE ;

: _RTE-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RTE-BYTE-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RTE-BOOL?  ( x -- flag )
    DUP 0= SWAP -1 = OR ;

: _RTE-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

: _RTE-UMUL?  ( a b -- product flag )
    UM* DUP IF 2DROP 0 0 EXIT THEN DROP -1 ;

: _RTE-POSITIVE-EXACT?  ( value feature-present? -- flag )
    IF 0<> ELSE 0= THEN ;

VARIABLE _RTE-SADD-A
VARIABLE _RTE-SADD-B
VARIABLE _RTE-SADD-SUM

\ Return the signed sum only when native-cell addition is exact.  Keep the
\ scratch off the return stack because plan validation calls this from a DO
\ loop, whose return-stack state belongs to the loop counter.
: _RTE-SADD?  ( a b -- sum flag )
    _RTE-SADD-B ! _RTE-SADD-A !
    _RTE-SADD-A @ _RTE-SADD-B @ + _RTE-SADD-SUM !
    _RTE-SADD-A @ _RTE-SADD-SUM @ XOR
    _RTE-SADD-B @ _RTE-SADD-SUM @ XOR AND 0< IF
        0 0 EXIT
    THEN
    _RTE-SADD-SUM @ -1 ;

VARIABLE _RTE-LPV-PLAN
VARIABLE _RTE-LPV-ITEM
VARIABLE _RTE-LPV-ITEMS-A
VARIABLE _RTE-LPV-ITEMS-U
VARIABLE _RTE-LPV-PRIOR-OBJECT
VARIABLE _RTE-LPV-ROW-END
VARIABLE _RTE-LPV-COL-END

: _RTE-LABEL-PLAN-VALID-FINISH  ( flag -- flag )
    0 _RTE-LPV-PLAN !
    0 _RTE-LPV-ITEM !
    0 _RTE-LPV-ITEMS-A !
    0 _RTE-LPV-ITEMS-U !
    0 _RTE-LPV-PRIOR-OBJECT !
    0 _RTE-LPV-ROW-END !
    0 _RTE-LPV-COL-END ! ;

: _RTE-LABEL-PLAN-ITEM-GEOMETRY?  ( -- flag )
    _RTE-LPV-ITEM @ _RTE-LPI.HEIGHT @ 0<
    _RTE-LPV-ITEM @ _RTE-LPI.WIDTH @ 0< OR IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.ROOT-HEIGHT @ 0> 0=
    _RTE-LPV-ITEM @ _RTE-LPI.ROOT-WIDTH @ 0> 0= OR IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.ROOT-HEIGHT @
        _RTE-LPV-PLAN @ _RTE-LP.REGION-ROWS @ <> IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.ROOT-WIDTH @
        _RTE-LPV-PLAN @ _RTE-LP.REGION-COLS @ <> IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.ROW @
    _RTE-LPV-ITEM @ _RTE-LPI.HEIGHT @ _RTE-SADD? 0= IF
        DROP 0 EXIT
    THEN _RTE-LPV-ROW-END !
    _RTE-LPV-ITEM @ _RTE-LPI.COL @
    _RTE-LPV-ITEM @ _RTE-LPI.WIDTH @ _RTE-SADD? 0= IF
        DROP 0 EXIT
    THEN _RTE-LPV-COL-END !
    _RTE-LPV-ITEM @ _RTE-LPI.VISIBLE @ IF
        _RTE-LPV-ITEM @ _RTE-LPI.HEIGHT @ 0=
        _RTE-LPV-ITEM @ _RTE-LPI.WIDTH @ 0= OR
        _RTE-LPV-ITEM @ _RTE-LPI.ROW @
            _RTE-LPV-ITEM @ _RTE-LPI.ROOT-HEIGHT @ < 0= OR
        _RTE-LPV-ROW-END @ 0> 0= OR
        _RTE-LPV-ITEM @ _RTE-LPI.COL @
            _RTE-LPV-ITEM @ _RTE-LPI.ROOT-WIDTH @ < 0= OR
        _RTE-LPV-COL-END @ 0> 0= OR IF 0 EXIT THEN
    THEN
    -1 ;

: _RTE-LABEL-PLAN-ITEM?  ( -- flag )
    _RTE-LPV-ITEM @ _RTE-LPI.OBJECT @ DUP 0= IF DROP 0 EXIT THEN
    DUP _RTE-LPV-PRIOR-OBJECT @ U> 0= IF DROP 0 EXIT THEN
    _RTE-LPV-PRIOR-OBJECT !
    _RTE-LPV-ITEM @ _RTE-LPI.PARENT @ IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.VISIBLE @ _RTE-BOOL? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.RGBA @ 0xFFFFFFFF U> IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.H-ALIGN @ 3 U< 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.V-ALIGN @ 3 U< 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.ELLIPSIZE @ _RTE-BOOL? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.TEXT-CAPACITY @ 0< IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.RESERVED @ IF 0 EXIT THEN
    _RTE-LABEL-PLAN-ITEM-GEOMETRY? ;

: _RTE-LABEL-PLAN-VALID-BODY  ( -- flag )
    _RTE-LPV-PLAN @ DUP RTE-LABEL-PLAN-SIZE _RTE-SPAN? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RTE-LP.OWNER @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.GENERATION @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.SURFACE-COLS @ 0> 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.SURFACE-ROWS @ 0> 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-ID @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-X @ 0< IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-Y @ 0< IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-COLS @ 0> 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-ROWS @ 0> 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-FLAGS @ 3 INVERT AND IF DROP 0 EXIT THEN
    DUP _RTE-LP.RESERVED @ IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-X @ OVER _RTE-LP.REGION-COLS @
        _RTE-UADD? 0= IF DROP DROP 0 EXIT THEN
    OVER _RTE-LP.SURFACE-COLS @ U> IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-Y @ OVER _RTE-LP.REGION-ROWS @
        _RTE-UADD? 0= IF DROP DROP 0 EXIT THEN
    OVER _RTE-LP.SURFACE-ROWS @ U> IF DROP 0 EXIT THEN
    DUP _RTE-LP.ITEMS-A @ _RTE-LPV-ITEMS-A !
    DUP _RTE-LP.ITEMS-U @ _RTE-LPV-ITEMS-U !
    DROP
    _RTE-LPV-ITEMS-A @ _RTE-LPV-ITEMS-U @ _RTE-SPAN? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEMS-U @ 0= IF 0 EXIT THEN
    _RTE-LPV-ITEMS-U @ RTE-LABEL-PLAN-ITEM-SIZE MOD IF 0 EXIT THEN
    _RTE-LPV-PLAN @ RTE-LABEL-PLAN-SIZE
        _RTE-LPV-ITEMS-A @ _RTE-LPV-ITEMS-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    0 _RTE-LPV-PRIOR-OBJECT !
    _RTE-LPV-ITEMS-A @ _RTE-LPV-ITEM !
    _RTE-LPV-ITEMS-U @ RTE-LABEL-PLAN-ITEM-SIZE / 0 ?DO
        _RTE-LABEL-PLAN-ITEM? 0= IF 0 UNLOOP EXIT THEN
        RTE-LABEL-PLAN-ITEM-SIZE _RTE-LPV-ITEM +!
    LOOP
    -1 ;

: RTE-LABEL-PLAN-VALID?  ( plan -- flag )
    _RTE-LPV-PLAN !
    _RTE-LABEL-PLAN-VALID-BODY
    _RTE-LABEL-PLAN-VALID-FINISH ;

: _RTE-UTF8-CONT?  ( byte -- flag )
    0xC0 AND 0x80 = ;

\ Return the exact byte length of one admitted scalar, or zero.  LABEL text
\ additionally excludes the three structural control bytes NUL, LF, and CR.
: _RTE-LABEL-UTF8-ONE  ( a u -- bytes|0 )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 0x80 < IF
        DUP 0= OVER 10 = OR SWAP 13 = OR IF
            2DROP 0 EXIT
        THEN
        2DROP 1 EXIT
    THEN
    DUP 0xC2 0xE0 WITHIN IF
        DROP
        DUP 2 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ _RTE-UTF8-CONT? IF 2DROP 2 ELSE 2DROP 0 THEN
        EXIT
    THEN
    DUP 0xE0 0xF0 WITHIN IF
        >R
        DUP 3 < IF 2DROP R> DROP 0 EXIT THEN
        OVER 1+ C@
        R@ 0xE0 = IF
            0xA0 0xC0 WITHIN
        ELSE
            R@ 0xED = IF
                0x80 0xA0 WITHIN
            ELSE
                _RTE-UTF8-CONT?
            THEN
        THEN
        2 PICK 2 + C@ _RTE-UTF8-CONT? AND 0= IF
            2DROP R> DROP 0 EXIT
        THEN
        2DROP R> DROP 3 EXIT
    THEN
    DUP 0xF0 0xF5 WITHIN IF
        >R
        DUP 4 < IF 2DROP R> DROP 0 EXIT THEN
        OVER 1+ C@
        R@ 0xF0 = IF
            0x90 0xC0 WITHIN
        ELSE
            R@ 0xF4 = IF
                0x80 0x90 WITHIN
            ELSE
                _RTE-UTF8-CONT?
            THEN
        THEN
        2 PICK 2 + C@ _RTE-UTF8-CONT? AND
        2 PICK 3 + C@ _RTE-UTF8-CONT? AND 0= IF
            2DROP R> DROP 0 EXIT
        THEN
        2DROP R> DROP 4 EXIT
    THEN
    2DROP DROP 0 ;

: _RTE-LABEL-TEXT-SPAN?  ( a u -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RTE-LABEL-TEXT?  ( a u -- flag )
    2DUP _RTE-LABEL-TEXT-SPAN? 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP 0> WHILE
        2DUP _RTE-LABEL-UTF8-ONE DUP 0= IF
            DROP 2DROP 0 EXIT
        THEN
        /STRING
    REPEAT
    2DROP -1 ;

VARIABLE _RTE-LG-LABEL
VARIABLE _RTE-LG-ROW-END
VARIABLE _RTE-LG-COL-END

: _RTE-LG-FINISH  ( flag -- flag )
    0 _RTE-LG-LABEL ! 0 _RTE-LG-ROW-END ! 0 _RTE-LG-COL-END ! ;

: _RTE-LABEL-GEOMETRY?  ( label -- flag )
    _RTE-LG-LABEL !
    _RTE-LG-LABEL @ _RTE-LABEL.HEIGHT @ 0<
    _RTE-LG-LABEL @ _RTE-LABEL.WIDTH @ 0< OR IF
        0 _RTE-LG-FINISH EXIT
    THEN
    _RTE-LG-LABEL @ _RTE-LABEL.ROOT-HEIGHT @ 0> 0=
    _RTE-LG-LABEL @ _RTE-LABEL.ROOT-WIDTH @ 0> 0= OR IF
        0 _RTE-LG-FINISH EXIT
    THEN
    _RTE-LG-LABEL @ _RTE-LABEL.ROW @
    _RTE-LG-LABEL @ _RTE-LABEL.HEIGHT @ _RTE-SADD? 0= IF
        DROP 0 _RTE-LG-FINISH EXIT
    THEN _RTE-LG-ROW-END !
    _RTE-LG-LABEL @ _RTE-LABEL.COL @
    _RTE-LG-LABEL @ _RTE-LABEL.WIDTH @ _RTE-SADD? 0= IF
        DROP 0 _RTE-LG-FINISH EXIT
    THEN _RTE-LG-COL-END !
    _RTE-LG-LABEL @ _RTE-LABEL.VISIBLE @ IF
        _RTE-LG-LABEL @ _RTE-LABEL.HEIGHT @ 0=
        _RTE-LG-LABEL @ _RTE-LABEL.WIDTH @ 0= OR
        _RTE-LG-LABEL @ _RTE-LABEL.ROW @
            _RTE-LG-LABEL @ _RTE-LABEL.ROOT-HEIGHT @ < 0= OR
        _RTE-LG-ROW-END @ 0> 0= OR
        _RTE-LG-LABEL @ _RTE-LABEL.COL @
            _RTE-LG-LABEL @ _RTE-LABEL.ROOT-WIDTH @ < 0= OR
        _RTE-LG-COL-END @ 0> 0= OR IF
            0 _RTE-LG-FINISH EXIT
        THEN
    THEN
    -1 _RTE-LG-FINISH ;

: _RTE-LABEL-FIELDS?  ( label -- flag )
    DUP _RTE-LABEL.OWNER @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.GENERATION @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.OBJECT @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.REGION @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.PARENT @ OVER _RTE-LABEL.OBJECT @ = IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.VISIBLE @ _RTE-BOOL? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.RGBA @ 0xFFFFFFFF U> IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.H-ALIGN @ 3 U< 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.V-ALIGN @ 3 U< 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.ELLIPSIZE @ _RTE-BOOL? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.RESERVED @ IF DROP 0 EXIT THEN
    _RTE-LABEL-GEOMETRY? ;

: RTE-LABEL-VALID?  ( label -- flag )
    DUP RTE-LABEL-SIZE _RTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL-FIELDS? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LABEL.TEXT-A @ SWAP _RTE-LABEL.TEXT-U @
        _RTE-LABEL-TEXT? ;

VARIABLE _RTE-LV-L
VARIABLE _RTE-LV-FEATURES

: _RTE-LIMIT-FLOOR?  ( required limits -- flag )
    _RTE-L.UPDATE-BYTES @ U> 0= ;

: _RTE-LIMITS-VALID-BODY  ( limits -- flag )
    DUP RTE-LIMITS-SIZE _RTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LV-L !
    _RTE-L.FEATURES @ DUP _RTE-LV-FEATURES !
    DUP _RTE-FEATURE-MASK INVERT AND IF DROP 0 EXIT THEN
    DUP RTE-F-CORE AND 0= IF DROP 0 EXIT THEN
    DUP RTE-F-SERIES AND SWAP RTE-F-INSTRUMENT AND 0= AND IF 0 EXIT THEN

    _RTE-LV-L @ _RTE-L.OWNER-RECORDS @ 0=
    _RTE-LV-L @ _RTE-L.LIVE-OWNERS @ 0= OR
    _RTE-LV-L @ _RTE-L.REGIONS @ 0= OR
    _RTE-LV-L @ _RTE-L.OPS @ 0= OR IF 0 EXIT THEN
    _RTE-LV-L @ _RTE-L.LIVE-OWNERS @
    _RTE-LV-L @ _RTE-L.OWNER-RECORDS @ U> IF 0 EXIT THEN
    248 _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN

    _RTE-LV-L @ _RTE-L.RESOURCES @
    _RTE-LV-FEATURES @ RTE-F-IMAGE AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.CHUNK-BYTES @
    _RTE-LV-FEATURES @ RTE-F-IMAGE AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.RESOURCE-BYTES @
    _RTE-LV-FEATURES @ RTE-F-IMAGE AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.IMAGE-WIDTH @
    _RTE-LV-FEATURES @ RTE-F-IMAGE AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.IMAGE-HEIGHT @
    _RTE-LV-FEATURES @ RTE-F-IMAGE AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN

    _RTE-LV-L @ _RTE-L.OBJECTS @
    _RTE-LV-FEATURES @
        RTE-F-VECTOR RTE-F-IMAGE OR RTE-F-INSTRUMENT OR RTE-F-SERIES OR
        AND 0<> _RTE-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTE-LV-L @ _RTE-L.PATH-POINTS @
    _RTE-LV-FEATURES @ RTE-F-VECTOR AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.LABEL-BYTES @
    _RTE-LV-FEATURES @ RTE-F-INSTRUMENT AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.UTF8-BYTES @
    _RTE-LV-FEATURES @ RTE-F-INSTRUMENT AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-FEATURES @ RTE-F-INSTRUMENT AND IF
        _RTE-LV-L @ _RTE-L.UTF8-BYTES @
        _RTE-LV-L @ _RTE-L.LABEL-BYTES @ U< IF 0 EXIT THEN
    THEN

    _RTE-LV-L @ _RTE-L.SERIES @
    _RTE-LV-FEATURES @ RTE-F-SERIES AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.SAMPLES-APPEND @
    _RTE-LV-FEATURES @ RTE-F-SERIES AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.SERIES-HISTORY @
    _RTE-LV-FEATURES @ RTE-F-SERIES AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.SAMPLE-SLOTS @
    _RTE-LV-FEATURES @ RTE-F-SERIES AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-FEATURES @ RTE-F-SERIES AND IF
        _RTE-LV-L @ _RTE-L.SAMPLES-APPEND @
        _RTE-LV-L @ _RTE-L.SERIES-HISTORY @ U> IF 0 EXIT THEN
        _RTE-LV-L @ _RTE-L.SERIES-HISTORY @
        _RTE-LV-L @ _RTE-L.SAMPLE-SLOTS @ U> IF 0 EXIT THEN
    THEN
    _RTE-LV-L @ _RTE-L.MIN-INTERVAL-US @
    _RTE-LV-FEATURES @ RTE-F-CADENCE AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN

    _RTE-LV-FEATURES @ RTE-F-IMAGE AND IF
        _RTE-LV-L @ _RTE-L.IMAGE-WIDTH @
        _RTE-LV-L @ _RTE-L.IMAGE-HEIGHT @ _RTE-UMUL? 0= IF
            DROP 0 EXIT
        THEN
        4 _RTE-UMUL? 0= IF DROP 0 EXIT THEN
        _RTE-LV-L @ _RTE-L.RESOURCE-BYTES @ U> IF 0 EXIT THEN
        280 _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    _RTE-LV-FEATURES @ RTE-F-VECTOR AND IF
        _RTE-LV-L @ _RTE-L.PATH-POINTS @ 8 _RTE-UMUL? 0= IF
            DROP 0 EXIT
        THEN
        280 _RTE-UADD? 0= IF DROP 0 EXIT THEN
        _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    _RTE-LV-FEATURES @ RTE-F-INSTRUMENT AND IF
        _RTE-LV-L @ _RTE-L.LABEL-BYTES @ 304 _RTE-UADD? 0= IF
            DROP 0 EXIT
        THEN
        312 MAX _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    _RTE-LV-FEATURES @ RTE-F-SERIES AND IF
        _RTE-LV-L @ _RTE-L.SAMPLES-APPEND @ 16 _RTE-UMUL? 0= IF
            DROP 0 EXIT
        THEN
        240 _RTE-UADD? 0= IF DROP 0 EXIT THEN
        312 MAX _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    -1 ;

: RTE-LIMITS-VALID?  ( limits -- flag )
    DUP _RTE-LV-L !
    _RTE-LIMITS-VALID-BODY
    0 _RTE-LV-L !
    0 _RTE-LV-FEATURES ! ;

: _RTE-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _RTE-MODE?  ( mode -- flag )
    DUP RTE-RETAINED-DELTA =
    OVER RTE-RETAINED-REPLACE-START = OR
    OVER RTE-RETAINED-REPLACE-CONTINUE = OR
    OVER RTE-RETAINED-LAYOUT-START = OR
    SWAP RTE-RETAINED-LAYOUT-CONTINUE = OR ;

: _RTE-DISPOSITION?  ( disposition -- flag )
    DUP RTE-COMMIT = SWAP RTE-COMMIT-AND-REVEAL = OR ;

: RTE-VALID?  ( facade -- flag )
    DUP RTE-FACADE-SIZE _RTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTE-F.MAGIC @ _RTE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _RTE-F.ABI @ _RTE-ABI <> IF DROP 0 EXIT THEN
    DUP _RTE-F.SIZE @ RTE-FACADE-SIZE <> IF DROP 0 EXIT THEN
    DUP _RTE-F.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _RTE-F.CONTEXT @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-F.DISJOINT-XT @ 0=
    OVER _RTE-F.STATUS-XT @ 0= OR
    OVER _RTE-F.OWNER-OPEN-XT @ 0= OR
    OVER _RTE-F.OWNER-STATE-XT @ 0= OR
    OVER _RTE-F.RETAINED-BEGIN-XT @ 0= OR
    OVER _RTE-F.REGION-DEF-XT @ 0= OR
    OVER _RTE-F.RETAINED-SEAL-XT @ 0= OR
    OVER _RTE-F.RETAINED-CANCEL-XT @ 0= OR
    OVER _RTE-F.OWNER-DROP-XT @ 0= OR IF DROP 0 EXIT THEN
    DUP _RTE-F.LIMITS-XT @ 0=
    OVER _RTE-F.LABEL-DEF-XT @ 0= OR IF DROP 0 EXIT THEN
    _RTE-F.LABEL-PREFLIGHT-XT @ 0<> ;

: RTE-STORAGE-DISJOINT?  ( a u facade -- flag )
    DUP RTE-VALID? 0= IF _RTE-DROP3 0 EXIT THEN
    >R
    2DUP _RTE-BYTE-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ RTE-FACADE-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTE-F.CONTEXT @ R> _RTE-F.DISJOINT-XT @ EXECUTE
    DUP _RTE-BOOL? 0= IF DROP 0 THEN ;

: RTE-STATUS@  ( facade -- status )
    DUP RTE-VALID? 0= IF DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.STATUS-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-LIMITS@  ( limits facade -- status )
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-LIMITS-SIZE _RTE-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-LIMITS-SIZE 2 PICK RTE-STORAGE-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER >R
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.LIMITS-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN
    DUP RTE-S-OK = IF
        R@ RTE-LIMITS-VALID? 0= IF DROP RTE-S-INVALID THEN
    THEN
    R> DROP ;

: RTE-OWNER-OPEN
    ( owner generation region-q resource-q object-q series-q
      resource-bytes utf8-bytes sample-slots facade -- status )
    DUP RTE-VALID? 0= IF 2DROP 2DROP 2DROP 2DROP 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.OWNER-OPEN-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-OWNER-STATE@  ( owner generation facade -- owner-state status )
    DUP RTE-VALID? 0= IF
        _RTE-DROP3 RTE-OWNER-ST-FREE RTE-S-INVALID EXIT
    THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.OWNER-STATE-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF
        2DROP RTE-OWNER-ST-FREE RTE-S-INVALID
        EXIT
    THEN
    OVER RTE-OWNER-STATE-VALID? 0= IF
        2DROP RTE-OWNER-ST-FREE RTE-S-INVALID
    THEN ;

: RTE-RETAINED-BEGIN  ( retained-mode facade -- status )
    OVER _RTE-MODE? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.RETAINED-BEGIN-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-REGION-DEFINE
    ( owner generation region x y cols rows z flags facade -- status )
    DUP RTE-VALID? 0= IF 2DROP 2DROP 2DROP 2DROP 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.REGION-DEF-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-LABEL-PREFLIGHT  ( plan facade -- status )
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-LABEL-PLAN-SIZE _RTE-SPAN? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER RTE-LABEL-PLAN-SIZE 2 PICK RTE-STORAGE-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-LP.ITEMS-A @ 2 PICK _RTE-LP.ITEMS-U @ _RTE-SPAN? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-LP.ITEMS-A @ 2 PICK _RTE-LP.ITEMS-U @
        2 PICK RTE-STORAGE-DISJOINT? 0= IF
            2DROP RTE-S-INVALID EXIT
        THEN
    OVER RTE-LABEL-PLAN-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.LABEL-PREFLIGHT-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-LABEL-DEFINE  ( label facade -- status )
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-LABEL-SIZE _RTE-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-LABEL-SIZE 2 PICK RTE-STORAGE-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-LABEL.TEXT-A @ 2 PICK _RTE-LABEL.TEXT-U @
        _RTE-LABEL-TEXT-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER _RTE-LABEL.TEXT-U @ IF
        OVER _RTE-LABEL.TEXT-A @ 2 PICK _RTE-LABEL.TEXT-U @
            2 PICK RTE-STORAGE-DISJOINT? 0= IF
                2DROP RTE-S-INVALID EXIT
            THEN
    THEN
    \ Dispatch proves bounded-span and scalar structure only.  The installed
    \ provider owns negotiated length admission before its linear UTF-8 scan.
    \ Imposing a facade-local text ceiling would violate caller-bounded design.
    OVER _RTE-LABEL-FIELDS? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.LABEL-DEF-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-RETAINED-SEAL  ( disposition facade -- status )
    OVER _RTE-DISPOSITION? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.RETAINED-SEAL-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-RETAINED-CANCEL  ( facade -- status )
    DUP RTE-VALID? 0= IF DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.RETAINED-CANCEL-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-OWNER-DROP  ( owner generation facade -- status )
    DUP RTE-VALID? 0= IF _RTE-DROP3 RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.OWNER-DROP-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;
