\ =====================================================================
\  engine.f -- backend-neutral retained semantic-engine facade
\ =====================================================================
\
\  This internal composition interface keeps renderer-neutral producers above
\  concrete terminal engines.  It exposes the bound provider's
\  owner and transaction operations, one immutable negotiated-limits snapshot,
\  call-borrowed neutral GLYPH-RUN, semantic-control, and instrument
\  definitions, plus mutation-free admission plans.  The descriptor is
\  caller-owned, immutable
\  after provider construction, carries one explicit provider context, and
\  reports only the neutral state of the session-global update slot.  It owns
\  no storage, transport, host, UCTX, Desk, or application authority.
\
\  Prefix: RTE- (public), _RTE- (private)
\  Provider: akashic-tui-rte

PROVIDED akashic-tui-rte

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/string.f

\ Stable neutral statuses used by the composed rich-terminal modules.
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
64 CONSTANT RTE-F-CONTROLS
128 CONSTANT RTE-F-CONTROL-COLLECTIONS
0xFF CONSTANT _RTE-FEATURE-MASK

\ One fixed record captures negotiated admission bounds.  Its size is a
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
: _RTE-L.GLYPH-RUN-BYTES ( l -- a ) 112 + ;
: _RTE-L.UTF8-BYTES      ( l -- a ) 120 + ;
: _RTE-L.SAMPLES-APPEND  ( l -- a ) 128 + ;
: _RTE-L.SERIES-HISTORY  ( l -- a ) 136 + ;
: _RTE-L.SAMPLE-SLOTS    ( l -- a ) 144 + ;
: _RTE-L.MIN-INTERVAL-US ( l -- a ) 152 + ;
: _RTE-L.OUTBOUND-PAYLOAD ( l -- a ) 160 + ;

168 CONSTANT RTE-LIMITS-SIZE

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
: RTE-LIMITS-GLYPH-RUN-BYTES@  ( l -- u )  _RTE-L.GLYPH-RUN-BYTES @ ;
: RTE-LIMITS-UTF8-BYTES@      ( l -- u )  _RTE-L.UTF8-BYTES @ ;
: RTE-LIMITS-SAMPLES-APPEND@  ( l -- u )  _RTE-L.SAMPLES-APPEND @ ;
: RTE-LIMITS-SERIES-HISTORY@  ( l -- u )  _RTE-L.SERIES-HISTORY @ ;
: RTE-LIMITS-SAMPLE-SLOTS@    ( l -- u )  _RTE-L.SAMPLE-SLOTS @ ;
: RTE-LIMITS-MIN-INTERVAL-US@ ( l -- u )  _RTE-L.MIN-INTERVAL-US @ ;
: RTE-LIMITS-OUTBOUND-PAYLOAD@ ( l -- u )
    _RTE-L.OUTBOUND-PAYLOAD @ ;

\ Neutral retained update vocabulary.  Values need not equal any provider's.
1 CONSTANT RTE-RETAINED-DELTA
2 CONSTANT RTE-RETAINED-REPLACE-START
3 CONSTANT RTE-RETAINED-REPLACE-CONTINUE
4 CONSTANT RTE-RETAINED-LAYOUT-START
5 CONSTANT RTE-RETAINED-LAYOUT-CONTINUE

0 CONSTANT RTE-COMMIT
1 CONSTANT RTE-COMMIT-AND-REVEAL

\ Neutral state of the one session-global retained/unified update slot.  A
\ provider may use any private representation; these values let the lifecycle
\ materializer correlate its sole active attempt without observing a renderer,
\ wire opcode, or CELL-specific state name.
0 CONSTANT RTE-UPDATE-IDLE
1 CONSTANT RTE-UPDATE-CAPTURING
2 CONSTANT RTE-UPDATE-SEALED
3 CONSTANT RTE-UPDATE-PUBLISHING
4 CONSTANT RTE-UPDATE-AWAITING

: RTE-UPDATE-STATE-VALID?  ( update-state -- flag )
    5 U< ;

0x5254454641434144 CONSTANT _RTE-MAGIC  \ "RTEFACAD"

: _RTE-F.MAGIC          ( f -- a )       ;
: _RTE-F.RESERVED       ( f -- a )   8 + ;
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
: _RTE-F.GLYPH-RUN-DEF-XT   ( f -- a ) 120 + ;
: _RTE-F.GLYPH-RUN-PREFLIGHT-XT ( f -- a ) 128 + ;
: _RTE-F.UPDATE-STATE-XT ( f -- a ) 136 + ;
: _RTE-F.GLYPH-RUN-REPLACE-XT ( f -- a ) 144 + ;
: _RTE-F.CONTROL-PREFLIGHT-XT ( f -- a ) 152 + ;
: _RTE-F.CONTROL-DEF-XT  ( f -- a ) 160 + ;
: _RTE-F.CONTROL-REPLACE-XT ( f -- a ) 168 + ;
: _RTE-F.CONTROL-DROP-XT ( f -- a ) 176 + ;
: _RTE-F.HYBRID-PREFLIGHT-XT ( f -- a ) 184 + ;
: _RTE-F.INSTRUMENT-DEF-XT ( f -- a ) 192 + ;

200 CONSTANT RTE-FACADE-SIZE

: RTE-FACADE-BYTES  ( -- bytes )  RTE-FACADE-SIZE ;

\ A GLYPH-RUN plan describes one root REGION_DEFINE followed by a positive,
\ caller-bounded sequence of GLYPH-RUN_DEFINE operations.  Each item carries the
\ exact retained reservation derived from current semantic text for this
\ desired generation.  Object IDs are strictly increasing but may be sparse,
\ so the final item's ID remains
\ identity-validation high-water only.  The exact owner object quota is item
\ count; the operation quota adds the root REGION_DEFINE.  The plan carries
\ no renderer or provider representation and is borrowed only for
\ RTE-GLYPH-RUN-PREFLIGHT's dynamic extent.
: _RTE-LP.OWNER         ( plan -- a )        ;
: _RTE-LP.GENERATION    ( plan -- a )    8 + ;
: _RTE-LP.SURFACE-COLS  ( plan -- a )   16 + ;
: _RTE-LP.SURFACE-ROWS  ( plan -- a )   24 + ;
: _RTE-LP.REGION-ID     ( plan -- a )   32 + ;
: _RTE-LP.REGION-X      ( plan -- a )   40 + ;
: _RTE-LP.REGION-Y      ( plan -- a )   48 + ;
: _RTE-LP.REGION-COLS   ( plan -- a )   56 + ;
: _RTE-LP.REGION-ROWS   ( plan -- a )   64 + ;
: _RTE-LP.CLIP-X        ( plan -- a )   72 + ;
: _RTE-LP.CLIP-Y        ( plan -- a )   80 + ;
: _RTE-LP.CLIP-COLS     ( plan -- a )   88 + ;
: _RTE-LP.CLIP-ROWS     ( plan -- a )   96 + ;
: _RTE-LP.REGION-Z      ( plan -- a )  104 + ;
: _RTE-LP.REGION-FLAGS  ( plan -- a )  112 + ;
: _RTE-LP.ITEMS-A       ( plan -- a )  120 + ;
: _RTE-LP.ITEMS-U       ( plan -- a )  128 + ;
: _RTE-LP.RESERVED      ( plan -- a )  136 + ;

144 CONSTANT RTE-GLYPH-RUN-PLAN-SIZE

: RTE-GLYPH-RUN-PLAN-BYTES  ( -- bytes )  RTE-GLYPH-RUN-PLAN-SIZE ;

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
: _RTE-LPI.FG-RGBA       ( item -- a )   80 + ;
: _RTE-LPI.BG-RGBA       ( item -- a )   88 + ;
: _RTE-LPI.ATTRS         ( item -- a )   96 + ;
: _RTE-LPI.TEXT-CAPACITY ( item -- a )  104 + ;
: _RTE-LPI.RESERVED      ( item -- a )  112 + ;

120 CONSTANT RTE-GLYPH-RUN-PLAN-ITEM-SIZE

: RTE-GLYPH-RUN-PLAN-ITEM-BYTES  ( -- bytes )
    RTE-GLYPH-RUN-PLAN-ITEM-SIZE ;

\ A GLYPH-RUN definition is a call-borrowed renderer-neutral value record.  Its
\ geometry is expressed in integer cells relative to the projection root;
\ providers perform any representation-specific conversion below this
\ interface.
\ The text bytes are borrowed only for RTE-GLYPH-RUN-DEFINE's dynamic extent.
: _RTE-GLYPH-RUN.OWNER       ( run -- a )        ;
: _RTE-GLYPH-RUN.GENERATION  ( run -- a )    8 + ;
: _RTE-GLYPH-RUN.OBJECT      ( run -- a )   16 + ;
: _RTE-GLYPH-RUN.REGION      ( run -- a )   24 + ;
: _RTE-GLYPH-RUN.PARENT      ( run -- a )   32 + ;
: _RTE-GLYPH-RUN.ROW         ( run -- a )   40 + ;
: _RTE-GLYPH-RUN.COL         ( run -- a )   48 + ;
: _RTE-GLYPH-RUN.HEIGHT      ( run -- a )   56 + ;
: _RTE-GLYPH-RUN.WIDTH       ( run -- a )   64 + ;
: _RTE-GLYPH-RUN.ROOT-HEIGHT ( run -- a )   72 + ;
: _RTE-GLYPH-RUN.ROOT-WIDTH  ( run -- a )   80 + ;
: _RTE-GLYPH-RUN.Z           ( run -- a )   88 + ;
: _RTE-GLYPH-RUN.VISIBLE     ( run -- a )   96 + ;
: _RTE-GLYPH-RUN.FG-RGBA     ( run -- a )  104 + ;
: _RTE-GLYPH-RUN.BG-RGBA     ( run -- a )  112 + ;
: _RTE-GLYPH-RUN.ATTRS       ( run -- a )  120 + ;
: _RTE-GLYPH-RUN.TEXT-A      ( run -- a )  128 + ;
: _RTE-GLYPH-RUN.TEXT-U      ( run -- a )  136 + ;
: _RTE-GLYPH-RUN.RESERVED    ( run -- a )  144 + ;

152 CONSTANT RTE-GLYPH-RUN-SIZE

: RTE-GLYPH-RUN-BYTES  ( -- bytes )  RTE-GLYPH-RUN-SIZE ;

\ Renderer-neutral INSTRUMENT vocabulary.  One strict descriptor covers the
\ complete READOUT/METER/STATUS family without exposing a renderer or wire
\ object type.  COLOR-A/COLOR-B mean foreground/background for READOUT and
\ METER, and inactive/active for STATUS; both are packed 0xRRGGBBAA straight-
\ alpha sRGB.  MODE and OPTIONS are kind-specific; every inapplicable union
\ field must be canonical zero.
1 CONSTANT RTE-INSTRUMENT-READOUT
2 CONSTANT RTE-INSTRUMENT-METER
3 CONSTANT RTE-INSTRUMENT-STATUS

0 CONSTANT RTE-READOUT-INTEGER
1 CONSTANT RTE-READOUT-FIXED
2 CONSTANT RTE-READOUT-PERCENT

0 CONSTANT RTE-METER-HORIZONTAL
1 CONSTANT RTE-METER-VERTICAL
1 CONSTANT RTE-METER-SHOW-VALUE

0 CONSTANT RTE-STATUS-CIRCLE
1 CONSTANT RTE-STATUS-SQUARE
2 CONSTANT RTE-STATUS-DIAMOND

\ Geometry is in signed root-local cells.  UNIT is borrowed only for the
\ dynamic extent of validation or INSTRUMENT-DEFINE.  FORMATTED-BYTES is the
\ exact complete READOUT length (number, punctuation, percent marker, and unit
\ once), not a retained string or a terminal allocation request.
: _RTE-INSTRUMENT.OWNER       ( instrument -- a )        ;
: _RTE-INSTRUMENT.GENERATION  ( instrument -- a )    8 + ;
: _RTE-INSTRUMENT.ID          ( instrument -- a )   16 + ;
: _RTE-INSTRUMENT.KIND        ( instrument -- a )   24 + ;
: _RTE-INSTRUMENT.VISIBLE     ( instrument -- a )   32 + ;
: _RTE-INSTRUMENT.Z           ( instrument -- a )   40 + ;
: _RTE-INSTRUMENT.REGION      ( instrument -- a )   48 + ;
: _RTE-INSTRUMENT.PARENT      ( instrument -- a )   56 + ;
: _RTE-INSTRUMENT.ROW         ( instrument -- a )   64 + ;
: _RTE-INSTRUMENT.COL         ( instrument -- a )   72 + ;
: _RTE-INSTRUMENT.HEIGHT      ( instrument -- a )   80 + ;
: _RTE-INSTRUMENT.WIDTH       ( instrument -- a )   88 + ;
: _RTE-INSTRUMENT.ROOT-HEIGHT ( instrument -- a )   96 + ;
: _RTE-INSTRUMENT.ROOT-WIDTH  ( instrument -- a )  104 + ;
: _RTE-INSTRUMENT.COLOR-A     ( instrument -- a )  112 + ;
: _RTE-INSTRUMENT.COLOR-B     ( instrument -- a )  120 + ;
: _RTE-INSTRUMENT.MODE        ( instrument -- a )  128 + ;
: _RTE-INSTRUMENT.OPTIONS     ( instrument -- a )  136 + ;
: _RTE-INSTRUMENT.MINIMUM     ( instrument -- a )  144 + ;
: _RTE-INSTRUMENT.MAXIMUM     ( instrument -- a )  152 + ;
: _RTE-INSTRUMENT.VALUE       ( instrument -- a )  160 + ;
: _RTE-INSTRUMENT.SCALE       ( instrument -- a )  168 + ;
: _RTE-INSTRUMENT.UNIT-A      ( instrument -- a )  176 + ;
: _RTE-INSTRUMENT.UNIT-U      ( instrument -- a )  184 + ;
: _RTE-INSTRUMENT.FORMATTED-U ( instrument -- a )  192 + ;
: _RTE-INSTRUMENT.RESERVED    ( instrument -- a )  200 + ;

208 CONSTANT RTE-INSTRUMENT-SIZE

: RTE-INSTRUMENT-BYTES  ( -- bytes )  RTE-INSTRUMENT-SIZE ;

\ One optional hybrid family plan carries positive, caller-bounded banks of
\ renderer-neutral regions and the same strict descriptors.  Regions are
\ sorted by native retained identity; items are sorted by object identity and
\ canonically grouped by region so both banks need only one validation pass.
: _RTE-IP.OWNER         ( plan -- a )        ;
: _RTE-IP.GENERATION    ( plan -- a )    8 + ;
: _RTE-IP.SURFACE-COLS  ( plan -- a )   16 + ;
: _RTE-IP.SURFACE-ROWS  ( plan -- a )   24 + ;
: _RTE-IP.REGIONS-A     ( plan -- a )   32 + ;
: _RTE-IP.REGIONS-U     ( plan -- a )   40 + ;
: _RTE-IP.ITEMS-A       ( plan -- a )   48 + ;
: _RTE-IP.ITEMS-U       ( plan -- a )   56 + ;
: _RTE-IP.RESERVED      ( plan -- a )   64 + ;

72 CONSTANT RTE-INSTRUMENT-PLAN-SIZE

1 CONSTANT RTE-REGION-VISIBLE
2 CONSTANT RTE-REGION-CLIPPED
RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR
    CONSTANT _RTE-REGION-FLAG-MASK

: _RTE-IR.ID          ( region -- a )       ;
: _RTE-IR.X           ( region -- a )   8 + ;
: _RTE-IR.Y           ( region -- a )  16 + ;
: _RTE-IR.COLS        ( region -- a )  24 + ;
: _RTE-IR.ROWS        ( region -- a )  32 + ;
: _RTE-IR.CLIP-X      ( region -- a )  40 + ;
: _RTE-IR.CLIP-Y      ( region -- a )  48 + ;
: _RTE-IR.CLIP-COLS   ( region -- a )  56 + ;
: _RTE-IR.CLIP-ROWS   ( region -- a )  64 + ;
: _RTE-IR.Z           ( region -- a )  72 + ;
: _RTE-IR.FLAGS       ( region -- a )  80 + ;
: _RTE-IR.RESERVED    ( region -- a )  88 + ;

96 CONSTANT RTE-INSTRUMENT-REGION-SIZE

: RTE-INSTRUMENT-PLAN-BYTES  ( -- bytes )
    RTE-INSTRUMENT-PLAN-SIZE ;
: RTE-INSTRUMENT-REGION-BYTES  ( -- bytes )
    RTE-INSTRUMENT-REGION-SIZE ;
: RTE-INSTRUMENT-PLAN-ITEM-BYTES  ( -- bytes )
    RTE-INSTRUMENT-SIZE ;

\ Renderer-neutral semantic CONTROL vocabulary.  These values describe
\ meaning above any terminal protocol; a concrete bridge maps each admitted
\ kind and state bit explicitly.  TEXT_AREA, TEXT_GRID, TABSET, and TAB extend
\ the existing CONTROL family and are gated by RTE-F-CONTROL-COLLECTIONS; they
\ are not a second operation family.
1 CONSTANT RTE-CONTROL-MENU-BAR
2 CONSTANT RTE-CONTROL-MENU
3 CONSTANT RTE-CONTROL-MENU-ITEM
4 CONSTANT RTE-CONTROL-MENU-SEPARATOR
5 CONSTANT RTE-CONTROL-TEXT-AREA
6 CONSTANT RTE-CONTROL-TEXT-GRID
7 CONSTANT RTE-CONTROL-TABSET
8 CONSTANT RTE-CONTROL-TAB

1  CONSTANT RTE-CONTROL-VISIBLE
2  CONSTANT RTE-CONTROL-ENABLED
4  CONSTANT RTE-CONTROL-OPEN
8  CONSTANT RTE-CONTROL-SELECTED
16 CONSTANT RTE-CONTROL-CHECKED
0x1F CONSTANT _RTE-CONTROL-STATE-MASK
RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR
    RTE-CONTROL-OPEN OR RTE-CONTROL-SELECTED OR
    CONSTANT _RTE-CONTROL-MENU-STATE-MASK
RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR
    RTE-CONTROL-SELECTED OR RTE-CONTROL-CHECKED OR
    CONSTANT _RTE-CONTROL-ITEM-STATE-MASK
RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR
    RTE-CONTROL-SELECTED OR
    CONSTANT _RTE-CONTROL-COLLECTION-STATE-MASK
RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR
    CONSTANT _RTE-CONTROL-TABSET-STATE-MASK

\ A semantic control is one call-borrowed renderer-neutral value record.
\ Geometry is expressed in integer cells relative to the projection root.
\ LABEL, SHORTCUT, and CONTENT are borrowed only for the dynamic extent of a
\ CONTROL or hybrid preflight, definition, or replacement call; the facade
\ retains no pointer.  CONTENT is one canonical renderer-neutral binary value.
\ CONTENT-ITEMS and CONTENT-UTF8 are its already-derived quota aggregates,
\ not capacities or a parallel item representation.
: _RTE-CONTROL.OWNER       ( control -- a )        ;
: _RTE-CONTROL.GENERATION  ( control -- a )    8 + ;
: _RTE-CONTROL.ID          ( control -- a )   16 + ;
: _RTE-CONTROL.KIND        ( control -- a )   24 + ;
: _RTE-CONTROL.STATE       ( control -- a )   32 + ;
: _RTE-CONTROL.Z           ( control -- a )   40 + ;
: _RTE-CONTROL.REGION      ( control -- a )   48 + ;
: _RTE-CONTROL.PARENT      ( control -- a )   56 + ;
: _RTE-CONTROL.ORDER       ( control -- a )   64 + ;
: _RTE-CONTROL.ROW         ( control -- a )   72 + ;
: _RTE-CONTROL.COL         ( control -- a )   80 + ;
: _RTE-CONTROL.HEIGHT      ( control -- a )   88 + ;
: _RTE-CONTROL.WIDTH       ( control -- a )   96 + ;
: _RTE-CONTROL.ROOT-HEIGHT ( control -- a )  104 + ;
: _RTE-CONTROL.ROOT-WIDTH  ( control -- a )  112 + ;
: _RTE-CONTROL.LABEL-A     ( control -- a )  120 + ;
: _RTE-CONTROL.LABEL-U     ( control -- a )  128 + ;
: _RTE-CONTROL.SHORTCUT-A  ( control -- a )  136 + ;
: _RTE-CONTROL.SHORTCUT-U  ( control -- a )  144 + ;
: _RTE-CONTROL.CONTENT-A   ( control -- a )  152 + ;
: _RTE-CONTROL.CONTENT-U   ( control -- a )  160 + ;
: _RTE-CONTROL.CONTENT-ITEMS ( control -- a ) 168 + ;
: _RTE-CONTROL.CONTENT-UTF8  ( control -- a ) 176 + ;
: _RTE-CONTROL.RESERVED    ( control -- a )  184 + ;

192 CONSTANT RTE-CONTROL-SIZE

: RTE-CONTROL-BYTES  ( -- bytes )  RTE-CONTROL-SIZE ;

\ One CONTROL plan describes an initial/full-replacement root REGION_DEFINE
\ followed by a positive, caller-bounded bank of CONTROL_DEFINE operations.
\ Item payload is borrowed through each 192-byte item record.  The preflight
\ callback receives only the checked scalar aggregates derived by the neutral
\ plan's sole item-bank pass.  Callback stack: plan count variable-bytes,
\ aligned-variable-bytes, max-item-variable-bytes, last-id,
\ collection-controls, semantic-items, utf8-bytes, context -- status.
\ It may inspect already-validated header scalars but must not traverse the
\ plan's ITEMS-A/ITEMS-U bank.
: _RTE-CP.OWNER        ( plan -- a )        ;
: _RTE-CP.GENERATION   ( plan -- a )    8 + ;
: _RTE-CP.SURFACE-COLS ( plan -- a )   16 + ;
: _RTE-CP.SURFACE-ROWS ( plan -- a )   24 + ;
: _RTE-CP.REGION-ID    ( plan -- a )   32 + ;
: _RTE-CP.REGION-X     ( plan -- a )   40 + ;
: _RTE-CP.REGION-Y     ( plan -- a )   48 + ;
: _RTE-CP.REGION-COLS  ( plan -- a )   56 + ;
: _RTE-CP.REGION-ROWS  ( plan -- a )   64 + ;
: _RTE-CP.CLIP-X       ( plan -- a )   72 + ;
: _RTE-CP.CLIP-Y       ( plan -- a )   80 + ;
: _RTE-CP.CLIP-COLS    ( plan -- a )   88 + ;
: _RTE-CP.CLIP-ROWS    ( plan -- a )   96 + ;
: _RTE-CP.REGION-Z     ( plan -- a )  104 + ;
: _RTE-CP.REGION-FLAGS ( plan -- a )  112 + ;
: _RTE-CP.ITEMS-A      ( plan -- a )  120 + ;
: _RTE-CP.ITEMS-U      ( plan -- a )  128 + ;
: _RTE-CP.RESERVED     ( plan -- a )  136 + ;

144 CONSTANT RTE-CONTROL-PLAN-SIZE

: RTE-CONTROL-PLAN-BYTES  ( -- bytes )  RTE-CONTROL-PLAN-SIZE ;

: RTE-CONTROL-PLAN-ITEM-BYTES  ( -- bytes )  RTE-CONTROL-SIZE ;

\ One complete hybrid plan joins the optional semantic CONTROL, INSTRUMENT,
\ and residual GLYPH-RUN families under one owner, generation, surface, and
\ root region.  Its positive attempt token, authoritative source generation,
\ and ordinary painted-surface generation bind this derived projection to the
\ exact lifecycle selection it represents.  A missing family is represented
\ only by its canonical zero fields; at least one family must be present.
\ Residual text references are parallel pointer-free (offset,length) records
\ over one dense copied-text span.  Every source address is borrowed only
\ through RTE-HYBRID-PREFLIGHT.  On exact success that call copies the
\ provider-admitted fixed summary into caller-owned admission storage.  The
\ provider may prove either a future OWNER_OPEN or a full replacement within
\ that exact open owner's existing reservation; the caller must ignore the
\ admission storage after every other status.
: _RTE-HP.ATTEMPT          ( hybrid -- a )      ;
: _RTE-HP.SOURCE-GENERATION ( hybrid -- a )  8 + ;
: _RTE-HP.SURFACE-GENERATION ( hybrid -- a ) 16 + ;
: _RTE-HP.CONTROL-PLAN     ( hybrid -- a ) 24 + ;
: _RTE-HP.GLYPH-PLAN       ( hybrid -- a ) 32 + ;
: _RTE-HP.GLYPH-REFS-A     ( hybrid -- a ) 40 + ;
: _RTE-HP.GLYPH-REFS-U     ( hybrid -- a ) 48 + ;
: _RTE-HP.GLYPH-TEXT-A     ( hybrid -- a ) 56 + ;
: _RTE-HP.GLYPH-TEXT-U     ( hybrid -- a ) 64 + ;
: _RTE-HP.CONTROL-BYTES-A  ( hybrid -- a ) 72 + ;
: _RTE-HP.CONTROL-BYTES-U  ( hybrid -- a ) 80 + ;
: _RTE-HP.INSTRUMENT-PLAN  ( hybrid -- a ) 88 + ;
: _RTE-HP.INSTRUMENT-BYTES-A ( hybrid -- a ) 96 + ;
: _RTE-HP.INSTRUMENT-BYTES-U ( hybrid -- a ) 104 + ;
: _RTE-HP.RESERVED         ( hybrid -- a ) 112 + ;

120 CONSTANT RTE-HYBRID-PLAN-SIZE
16 CONSTANT RTE-HYBRID-TEXT-REF-SIZE

: RTE-HYBRID-PLAN-BYTES  ( -- bytes )  RTE-HYBRID-PLAN-SIZE ;
: RTE-HYBRID-TEXT-REF-BYTES  ( -- bytes )
    RTE-HYBRID-TEXT-REF-SIZE ;

: _RTE-HTR.OFFSET  ( ref -- a )      ;
: _RTE-HTR.BYTES   ( ref -- a )  8 + ;

\ The neutral layer creates this call-borrowed checked summary only after its
\ sole traversal of every present caller bank.  A provider may validate these
\ fixed scalars and negotiated arithmetic, but must not revisit a plan, item,
\ reference, or text bank.  Instrument UNIT-BYTES, UNIT-ALIGNED, and UNIT-MAX
\ are respectively the exact raw total, sum of per-operation 8-byte-aligned
\ totals, and largest one-operation unit.  FORMATTED-BYTES and FORMATTED-MAX
\ are the exact retained formatted-text total and largest one-readout need.
\ LAST fields are identity high-water, never quota.
: _RTE-HA.OWNER          ( summary -- a )       ;
: _RTE-HA.GENERATION     ( summary -- a )   8 + ;
: _RTE-HA.SURFACE-COLS   ( summary -- a )  16 + ;
: _RTE-HA.SURFACE-ROWS   ( summary -- a )  24 + ;
: _RTE-HA.REGION-ID      ( summary -- a )  32 + ;
: _RTE-HA.REGION-X       ( summary -- a )  40 + ;
: _RTE-HA.REGION-Y       ( summary -- a )  48 + ;
: _RTE-HA.REGION-COLS    ( summary -- a )  56 + ;
: _RTE-HA.REGION-ROWS    ( summary -- a )  64 + ;
: _RTE-HA.CLIP-X          ( summary -- a )  72 + ;
: _RTE-HA.CLIP-Y          ( summary -- a )  80 + ;
: _RTE-HA.CLIP-COLS       ( summary -- a )  88 + ;
: _RTE-HA.CLIP-ROWS       ( summary -- a )  96 + ;
: _RTE-HA.REGION-Z        ( summary -- a ) 104 + ;
: _RTE-HA.REGION-FLAGS    ( summary -- a ) 112 + ;
: _RTE-HA.CONTROL-COUNT   ( summary -- a ) 120 + ;
: _RTE-HA.CONTROL-BYTES   ( summary -- a ) 128 + ;
: _RTE-HA.CONTROL-ALIGNED ( summary -- a ) 136 + ;
: _RTE-HA.CONTROL-MAX     ( summary -- a ) 144 + ;
: _RTE-HA.CONTROL-LAST    ( summary -- a ) 152 + ;
: _RTE-HA.CONTROL-COLLECTIONS ( summary -- a ) 160 + ;
: _RTE-HA.CONTROL-ITEMS   ( summary -- a ) 168 + ;
: _RTE-HA.CONTROL-UTF8    ( summary -- a ) 176 + ;
: _RTE-HA.GLYPH-COUNT     ( summary -- a ) 184 + ;
: _RTE-HA.GLYPH-TEXT      ( summary -- a ) 192 + ;
: _RTE-HA.GLYPH-ALIGNED   ( summary -- a ) 200 + ;
: _RTE-HA.GLYPH-MAX       ( summary -- a ) 208 + ;
: _RTE-HA.GLYPH-LAST      ( summary -- a ) 216 + ;
: _RTE-HA.INSTRUMENT-REGION-COUNT ( summary -- a ) 224 + ;
: _RTE-HA.INSTRUMENT-COUNT ( summary -- a ) 232 + ;
: _RTE-HA.READOUT-COUNT   ( summary -- a ) 240 + ;
: _RTE-HA.METER-COUNT     ( summary -- a ) 248 + ;
: _RTE-HA.STATUS-COUNT    ( summary -- a ) 256 + ;
: _RTE-HA.INSTRUMENT-UNIT-BYTES ( summary -- a ) 264 + ;
: _RTE-HA.INSTRUMENT-UNIT-ALIGNED ( summary -- a ) 272 + ;
: _RTE-HA.INSTRUMENT-UNIT-MAX ( summary -- a ) 280 + ;
: _RTE-HA.INSTRUMENT-FORMATTED-BYTES ( summary -- a ) 288 + ;
: _RTE-HA.INSTRUMENT-FORMATTED-MAX ( summary -- a ) 296 + ;
: _RTE-HA.INSTRUMENT-LAST ( summary -- a ) 304 + ;
: _RTE-HA.RESERVED        ( summary -- a ) 312 + ;

320 CONSTANT RTE-HYBRID-ADMISSION-SIZE

: RTE-HYBRID-ADMISSION-BYTES  ( -- bytes )
    RTE-HYBRID-ADMISSION-SIZE ;

: _RTE-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RTE-BYTE-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RTE-BOOL?  ( x -- flag )
    DUP 0= SWAP -1 = OR ;

: _RTE-U16?  ( u -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    0xFFFF U> 0= ;

: _RTE-U32?  ( u -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    0xFFFFFFFF U> 0= ;

: _RTE-I32?  ( n -- flag )
    DUP -2147483648 < IF DROP 0 EXIT THEN
    2147483647 > 0= ;

0x006F CONSTANT _RTE-GLYPH-RUN-ATTR-MASK

: _RTE-GLYPH-RUN-ATTRS?  ( attrs -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    DUP 0xFFFF U> IF DROP 0 EXIT THEN
    _RTE-GLYPH-RUN-ATTR-MASK INVERT AND 0= ;

: _RTE-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

: _RTE-UMUL?  ( a b -- product flag )
    UM* DUP IF 2DROP 0 0 EXIT THEN DROP -1 ;

: _RTE-POSITIVE-EXACT?  ( value feature-present? -- flag )
    IF 0<> ELSE 0= THEN ;

\ Hybrid admission writes the existing GLYPH-RUN, CONTROL, and INSTRUMENT validator
\ scratch as well as its own checked summary.  Keep the whole mutable range
\ explicit so every caller-owned span can be rejected before any of that
\ scratch is touched.
CREATE _RTE-HPV-OWNED-START

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

VARIABLE _RTE-RV-X
VARIABLE _RTE-RV-Y
VARIABLE _RTE-RV-COLS
VARIABLE _RTE-RV-ROWS
VARIABLE _RTE-RV-CLIP-X
VARIABLE _RTE-RV-CLIP-Y
VARIABLE _RTE-RV-CLIP-COLS
VARIABLE _RTE-RV-CLIP-ROWS
VARIABLE _RTE-RV-FLAGS
VARIABLE _RTE-RV-SURFACE-COLS
VARIABLE _RTE-RV-SURFACE-ROWS
VARIABLE _RTE-RV-X-END
VARIABLE _RTE-RV-Y-END
VARIABLE _RTE-RV-CLIP-X-END
VARIABLE _RTE-RV-CLIP-Y-END

: _RTE-RV-FINISH  ( flag -- flag )
    0 _RTE-RV-X ! 0 _RTE-RV-Y !
    0 _RTE-RV-COLS ! 0 _RTE-RV-ROWS !
    0 _RTE-RV-CLIP-X ! 0 _RTE-RV-CLIP-Y !
    0 _RTE-RV-CLIP-COLS ! 0 _RTE-RV-CLIP-ROWS !
    0 _RTE-RV-FLAGS !
    0 _RTE-RV-SURFACE-COLS ! 0 _RTE-RV-SURFACE-ROWS !
    0 _RTE-RV-X-END ! 0 _RTE-RV-Y-END !
    0 _RTE-RV-CLIP-X-END ! 0 _RTE-RV-CLIP-Y-END ! ;

: _RTE-REGION-GEOMETRY-BODY?  ( -- flag )
    _RTE-RV-SURFACE-COLS @ DUP 0= IF DROP 0 EXIT THEN
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-RV-SURFACE-ROWS @ DUP 0= IF DROP 0 EXIT THEN
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-RV-X @ _RTE-I32? 0= _RTE-RV-Y @ _RTE-I32? 0= OR IF
        0 EXIT
    THEN
    _RTE-RV-COLS @ DUP 0= IF DROP 0 EXIT THEN
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-RV-ROWS @ DUP 0= IF DROP 0 EXIT THEN
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-RV-CLIP-X @ _RTE-U32? 0=
    _RTE-RV-CLIP-Y @ _RTE-U32? 0= OR
    _RTE-RV-CLIP-COLS @ _RTE-U32? 0= OR
    _RTE-RV-CLIP-ROWS @ _RTE-U32? 0= OR IF 0 EXIT THEN
    _RTE-RV-FLAGS @ _RTE-REGION-FLAG-MASK INVERT AND IF 0 EXIT THEN

    \ Logical endpoints need only fit the native signed cell.  They may exceed
    \ i32 because a signed i32 origin plus a positive u32 extent is the neutral
    \ geometry being represented, not another i32 coordinate.
    _RTE-RV-X @ _RTE-RV-COLS @ _RTE-SADD? 0= IF DROP 0 EXIT THEN
        _RTE-RV-X-END !
    _RTE-RV-Y @ _RTE-RV-ROWS @ _RTE-SADD? 0= IF DROP 0 EXIT THEN
        _RTE-RV-Y-END !

    _RTE-RV-FLAGS @ RTE-REGION-CLIPPED AND 0= IF
        _RTE-RV-CLIP-X @ _RTE-RV-CLIP-Y @ OR
        _RTE-RV-CLIP-COLS @ OR _RTE-RV-CLIP-ROWS @ OR 0= EXIT
    THEN
    _RTE-RV-CLIP-X @ _RTE-RV-CLIP-Y @ OR
    _RTE-RV-CLIP-COLS @ OR _RTE-RV-CLIP-ROWS @ OR 0= IF -1 EXIT THEN
    _RTE-RV-CLIP-COLS @ 0= _RTE-RV-CLIP-ROWS @ 0= OR IF 0 EXIT THEN

    _RTE-RV-CLIP-X @ _RTE-RV-CLIP-COLS @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-RV-CLIP-X-END !
    _RTE-RV-SURFACE-COLS @ U> IF 0 EXIT THEN
    _RTE-RV-CLIP-Y @ _RTE-RV-CLIP-ROWS @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-RV-CLIP-Y-END !
    _RTE-RV-SURFACE-ROWS @ U> IF 0 EXIT THEN

    _RTE-RV-CLIP-X @ _RTE-RV-X @ < IF 0 EXIT THEN
    _RTE-RV-CLIP-X-END @ _RTE-RV-X-END @ > IF 0 EXIT THEN
    _RTE-RV-CLIP-Y @ _RTE-RV-Y @ < IF 0 EXIT THEN
    _RTE-RV-CLIP-Y-END @ _RTE-RV-Y-END @ > IF 0 EXIT THEN
    -1 ;

: _RTE-REGION-GEOMETRY?
    ( x y cols rows clip-x clip-y clip-cols clip-rows flags surface-cols surface-rows -- flag )
    _RTE-RV-SURFACE-ROWS ! _RTE-RV-SURFACE-COLS ! _RTE-RV-FLAGS !
    _RTE-RV-CLIP-ROWS ! _RTE-RV-CLIP-COLS !
    _RTE-RV-CLIP-Y ! _RTE-RV-CLIP-X !
    _RTE-RV-ROWS ! _RTE-RV-COLS ! _RTE-RV-Y ! _RTE-RV-X !
    _RTE-REGION-GEOMETRY-BODY? _RTE-RV-FINISH ;

VARIABLE _RTE-LPV-PLAN
VARIABLE _RTE-LPV-ITEM
VARIABLE _RTE-LPV-ITEMS-A
VARIABLE _RTE-LPV-ITEMS-U
VARIABLE _RTE-LPV-PRIOR-OBJECT
VARIABLE _RTE-LPV-ROW-END
VARIABLE _RTE-LPV-COL-END

: _RTE-GLYPH-RUN-PLAN-VALID-FINISH  ( flag -- flag )
    0 _RTE-LPV-PLAN !
    0 _RTE-LPV-ITEM !
    0 _RTE-LPV-ITEMS-A !
    0 _RTE-LPV-ITEMS-U !
    0 _RTE-LPV-PRIOR-OBJECT !
    0 _RTE-LPV-ROW-END !
    0 _RTE-LPV-COL-END ! ;

: _RTE-GLYPH-RUN-PLAN-ITEM-GEOMETRY?  ( -- flag )
    _RTE-LPV-ITEM @ _RTE-LPI.HEIGHT @ DUP 0=
        SWAP _RTE-U32? 0= OR IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.WIDTH @ DUP 0=
        SWAP _RTE-U32? 0= OR IF 0 EXIT THEN
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
        _RTE-LPV-ITEM @ _RTE-LPI.ROW @
            _RTE-LPV-ITEM @ _RTE-LPI.ROOT-HEIGHT @ < 0=
        _RTE-LPV-ROW-END @ 0> 0= OR
        _RTE-LPV-ITEM @ _RTE-LPI.COL @
            _RTE-LPV-ITEM @ _RTE-LPI.ROOT-WIDTH @ < 0= OR
        _RTE-LPV-COL-END @ 0> 0= OR IF 0 EXIT THEN
    THEN
    -1 ;

: _RTE-GLYPH-RUN-PLAN-ITEM?  ( -- flag )
    _RTE-LPV-ITEM @ _RTE-LPI.OBJECT @ DUP 0= IF DROP 0 EXIT THEN
    DUP _RTE-LPV-PRIOR-OBJECT @ U> 0= IF DROP 0 EXIT THEN
    _RTE-LPV-PRIOR-OBJECT !
    _RTE-LPV-ITEM @ _RTE-LPI.PARENT @ IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.VISIBLE @ _RTE-BOOL? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.FG-RGBA @ 0xFFFFFFFF U> IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.BG-RGBA @ 0xFFFFFFFF U> IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.ATTRS @
        _RTE-GLYPH-RUN-ATTRS? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.TEXT-CAPACITY @ 0< IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.RESERVED @ IF 0 EXIT THEN
    _RTE-GLYPH-RUN-PLAN-ITEM-GEOMETRY? ;

: _RTE-GLYPH-RUN-PLAN-HEADER?  ( -- flag )
    _RTE-LPV-PLAN @ RTE-GLYPH-RUN-PLAN-SIZE _RTE-SPAN? 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.OWNER @ 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.GENERATION @ 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.SURFACE-COLS @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.SURFACE-ROWS @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.REGION-ID @ 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.REGION-Z @ _RTE-I32? 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.RESERVED @ IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.REGION-X @
    _RTE-LPV-PLAN @ _RTE-LP.REGION-Y @
    _RTE-LPV-PLAN @ _RTE-LP.REGION-COLS @
    _RTE-LPV-PLAN @ _RTE-LP.REGION-ROWS @
    _RTE-LPV-PLAN @ _RTE-LP.CLIP-X @
    _RTE-LPV-PLAN @ _RTE-LP.CLIP-Y @
    _RTE-LPV-PLAN @ _RTE-LP.CLIP-COLS @
    _RTE-LPV-PLAN @ _RTE-LP.CLIP-ROWS @
    _RTE-LPV-PLAN @ _RTE-LP.REGION-FLAGS @
    _RTE-LPV-PLAN @ _RTE-LP.SURFACE-COLS @
    _RTE-LPV-PLAN @ _RTE-LP.SURFACE-ROWS @
        _RTE-REGION-GEOMETRY? 0= IF 0 EXIT THEN
    _RTE-LPV-PLAN @ _RTE-LP.ITEMS-A @ _RTE-LPV-ITEMS-A !
    _RTE-LPV-PLAN @ _RTE-LP.ITEMS-U @ _RTE-LPV-ITEMS-U !
    _RTE-LPV-ITEMS-A @ _RTE-LPV-ITEMS-U @ _RTE-SPAN? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEMS-U @ 0= IF 0 EXIT THEN
    _RTE-LPV-ITEMS-U @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE MOD IF 0 EXIT THEN
    _RTE-LPV-PLAN @ RTE-GLYPH-RUN-PLAN-SIZE
        _RTE-LPV-ITEMS-A @ _RTE-LPV-ITEMS-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    -1 ;

: _RTE-GLYPH-RUN-PLAN-VALID-BODY  ( -- flag )
    _RTE-GLYPH-RUN-PLAN-HEADER? 0= IF 0 EXIT THEN
    0 _RTE-LPV-PRIOR-OBJECT !
    _RTE-LPV-ITEMS-A @ _RTE-LPV-ITEM !
    _RTE-LPV-ITEMS-U @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE / 0 ?DO
        _RTE-GLYPH-RUN-PLAN-ITEM? 0= IF 0 UNLOOP EXIT THEN
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTE-LPV-ITEM +!
    LOOP
    -1 ;

: RTE-GLYPH-RUN-PLAN-VALID?  ( plan -- flag )
    _RTE-LPV-PLAN !
    _RTE-GLYPH-RUN-PLAN-VALID-BODY
    _RTE-GLYPH-RUN-PLAN-VALID-FINISH ;

: _RTE-UTF8-CONT?  ( byte -- flag )
    0xC0 AND 0x80 = ;

\ Return the exact byte length of one admitted scalar, or zero.  GLYPH-RUN text
\ additionally excludes the three structural control bytes NUL, LF, and CR.
: _RTE-GLYPH-RUN-UTF8-ONE  ( a u -- bytes|0 )
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

: _RTE-GLYPH-RUN-TEXT-SPAN?  ( a u -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RTE-GLYPH-RUN-TEXT?  ( a u -- flag )
    2DUP _RTE-GLYPH-RUN-TEXT-SPAN? 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP 0> WHILE
        2DUP _RTE-GLYPH-RUN-UTF8-ONE DUP 0= IF
            DROP 2DROP 0 EXIT
        THEN
        /STRING
    REPEAT
    2DROP -1 ;

VARIABLE _RTE-LG-GLYPH-RUN
VARIABLE _RTE-LG-ROW-END
VARIABLE _RTE-LG-COL-END

: _RTE-LG-FINISH  ( flag -- flag )
    0 _RTE-LG-GLYPH-RUN ! 0 _RTE-LG-ROW-END ! 0 _RTE-LG-COL-END ! ;

: _RTE-GLYPH-RUN-GEOMETRY?  ( glyph run -- flag )
    _RTE-LG-GLYPH-RUN !
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.HEIGHT @ 0<
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.WIDTH @ 0< OR IF
        0 _RTE-LG-FINISH EXIT
    THEN
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.ROOT-HEIGHT @ 0> 0=
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.ROOT-WIDTH @ 0> 0= OR IF
        0 _RTE-LG-FINISH EXIT
    THEN
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.ROW @
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.HEIGHT @ _RTE-SADD? 0= IF
        DROP 0 _RTE-LG-FINISH EXIT
    THEN _RTE-LG-ROW-END !
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.COL @
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.WIDTH @ _RTE-SADD? 0= IF
        DROP 0 _RTE-LG-FINISH EXIT
    THEN _RTE-LG-COL-END !
    _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.VISIBLE @ IF
        _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.HEIGHT @ 0=
        _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.WIDTH @ 0= OR
        _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.ROW @
            _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.ROOT-HEIGHT @ < 0= OR
        _RTE-LG-ROW-END @ 0> 0= OR
        _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.COL @
            _RTE-LG-GLYPH-RUN @ _RTE-GLYPH-RUN.ROOT-WIDTH @ < 0= OR
        _RTE-LG-COL-END @ 0> 0= OR IF
            0 _RTE-LG-FINISH EXIT
        THEN
    THEN
    -1 _RTE-LG-FINISH ;

: _RTE-GLYPH-RUN-FIELDS?  ( glyph run -- flag )
    DUP _RTE-GLYPH-RUN.OWNER @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.GENERATION @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.OBJECT @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.REGION @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.PARENT @ OVER _RTE-GLYPH-RUN.OBJECT @ = IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.VISIBLE @ _RTE-BOOL? 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.FG-RGBA @ 0xFFFFFFFF U> IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.BG-RGBA @ 0xFFFFFFFF U> IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.ATTRS @
        _RTE-GLYPH-RUN-ATTRS? 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.RESERVED @ IF DROP 0 EXIT THEN
    _RTE-GLYPH-RUN-GEOMETRY? ;

: RTE-GLYPH-RUN-VALID?  ( run -- flag )
    DUP RTE-GLYPH-RUN-SIZE _RTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN-FIELDS? 0= IF DROP 0 EXIT THEN
    DUP _RTE-GLYPH-RUN.TEXT-A @ SWAP _RTE-GLYPH-RUN.TEXT-U @
        _RTE-GLYPH-RUN-TEXT? ;

\ CONTROL strings are scalar UTF-8 presentation text.  In addition to the
\ structural bytes excluded from GLYPH-RUNs, every C0 control and DEL is
\ rejected so a semantic label cannot smuggle terminal behavior.
: _RTE-CONTROL-TEXT-SPAN?  ( a u -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

\ CONTENT is renderer-neutral binary data, not presentation text.  Its
\ canonical empty/nonempty pointer rules are nevertheless identical to the
\ scalar string spans above.
: _RTE-CONTROL-CONTENT-SPAN?  ( a u -- flag )
    _RTE-CONTROL-TEXT-SPAN? ;

: _RTE-CONTROL-TEXT?  ( a u -- flag )
    2DUP _RTE-CONTROL-TEXT-SPAN? 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP 0> WHILE
        2DUP _RTE-GLYPH-RUN-UTF8-ONE DUP 0= IF
            DROP 2DROP 0 EXIT
        THEN
        >R
        OVER C@ DUP 32 U< SWAP 127 = OR IF
            2DROP R> DROP 0 EXIT
        THEN
        R> /STRING
    REPEAT
    2DROP -1 ;

VARIABLE _RTE-LC-CONTROL
VARIABLE _RTE-LC-ROW-END
VARIABLE _RTE-LC-COL-END
VARIABLE _RTE-CSD-CONTROL

: _RTE-LC-FINISH  ( flag -- flag )
    0 _RTE-LC-CONTROL !
    0 _RTE-LC-ROW-END !
    0 _RTE-LC-COL-END ! ;

\ Canonical READOUT measurement.  This computes only the exact byte count and
\ never allocates or retains formatted text.  The percent path decomposes the
\ wide 100*value calculation so the complete signed-cell domain remains valid.
-1 1 RSHIFT CONSTANT _RTE-SIGNED-MAX
0x8000000000000000 CONSTANT _RTE-SIGNED-MIN

VARIABLE _RTE-DV-SCALE
VARIABLE _RTE-DV-REM
VARIABLE _RTE-DV-QUOT

: _RTE-MAGNITUDE/MOD  ( value positive-scale -- remainder quotient )
    _RTE-DV-SCALE !
    DUP 0< IF
        DUP _RTE-SIGNED-MIN = IF
            DROP _RTE-SIGNED-MAX _RTE-DV-SCALE @ /MOD
            _RTE-DV-QUOT ! 1+ DUP _RTE-DV-SCALE @ = IF
                DROP 0 _RTE-DV-REM !
                _RTE-DV-QUOT @ 1+ _RTE-DV-QUOT !
            ELSE
                _RTE-DV-REM !
            THEN
            _RTE-DV-REM @ _RTE-DV-QUOT @ EXIT
        THEN
        NEGATE
    THEN
    _RTE-DV-SCALE @ /MOD ;

VARIABLE _RTE-RFL-FORMAT
VARIABLE _RTE-RFL-DECIMALS
VARIABLE _RTE-RFL-VALUE
VARIABLE _RTE-RFL-SCALE
VARIABLE _RTE-RFL-UNIT-U
VARIABLE _RTE-RFL-REM
VARIABLE _RTE-RFL-QUOT
VARIABLE _RTE-RFL-PROD-LO
VARIABLE _RTE-RFL-PROD-HI
VARIABLE _RTE-RFL-EXTRA
VARIABLE _RTE-RFL-Q-LO
VARIABLE _RTE-RFL-Q-HI
VARIABLE _RTE-RFL-POW10
VARIABLE _RTE-RFL-T-LO
VARIABLE _RTE-RFL-T-HI
VARIABLE _RTE-RFL-DIGITS
VARIABLE _RTE-RFL-LENGTH

: _RTE-RFL-PRODUCT>=SCALE?  ( -- flag )
    _RTE-RFL-PROD-HI @ IF -1 EXIT THEN
    _RTE-RFL-PROD-LO @ _RTE-RFL-SCALE @ U< 0= ;

: _RTE-RFL-PRODUCT-SCALE-  ( -- )
    _RTE-RFL-PROD-LO @ _RTE-RFL-SCALE @ U< IF
        -1 _RTE-RFL-PROD-HI +!
    THEN
    _RTE-RFL-PROD-LO @ _RTE-RFL-SCALE @ - _RTE-RFL-PROD-LO ! ;

: _RTE-RFL-PERCENT-REMAINDER  ( -- remainder quotient-extra )
    _RTE-RFL-REM @ 100 UM*
    _RTE-RFL-PROD-HI ! _RTE-RFL-PROD-LO !
    0 _RTE-RFL-EXTRA !
    BEGIN _RTE-RFL-PRODUCT>=SCALE? WHILE
        _RTE-RFL-PRODUCT-SCALE-
        1 _RTE-RFL-EXTRA +!
    REPEAT
    _RTE-RFL-PROD-LO @ _RTE-RFL-EXTRA @ ;

: _RTE-RFL-Q+  ( u -- )
    _RTE-RFL-Q-LO @ OVER + DUP
    _RTE-RFL-Q-LO @ U< IF 1 _RTE-RFL-Q-HI +! THEN
    _RTE-RFL-Q-LO ! DROP ;

: _RTE-RFL-INTEGER-CARRY?  ( -- flag )
    _RTE-RFL-REM @ 0= IF 0 EXIT THEN
    _RTE-RFL-DECIMALS @ 19 U> IF 0 EXIT THEN
    1 _RTE-RFL-POW10 !
    _RTE-RFL-DECIMALS @ 0 ?DO
        _RTE-RFL-POW10 @ 10 * _RTE-RFL-POW10 !
    LOOP
    _RTE-RFL-SCALE @ _RTE-RFL-REM @ -
        _RTE-RFL-POW10 @ UM*
    DUP IF 2DROP 0 EXIT THEN DROP
    _RTE-RFL-SCALE @ 2/ U> 0= ;

: _RTE-RFL-DOUBLE>=THRESHOLD?  ( -- flag )
    _RTE-RFL-Q-HI @ _RTE-RFL-T-HI @ U< IF 0 EXIT THEN
    _RTE-RFL-Q-HI @ _RTE-RFL-T-HI @ U> IF -1 EXIT THEN
    _RTE-RFL-Q-LO @ _RTE-RFL-T-LO @ U< 0= ;

: _RTE-RFL-THRESHOLD*10  ( -- )
    _RTE-RFL-T-LO @ 10 UM*
    _RTE-RFL-PROD-HI ! _RTE-RFL-T-LO !
    _RTE-RFL-T-HI @ 10 * _RTE-RFL-PROD-HI @ + _RTE-RFL-T-HI ! ;

: _RTE-RFL-INTEGER-DIGITS  ( -- digits )
    1 _RTE-RFL-DIGITS !
    10 _RTE-RFL-T-LO ! 0 _RTE-RFL-T-HI !
    BEGIN _RTE-RFL-DOUBLE>=THRESHOLD? WHILE
        1 _RTE-RFL-DIGITS +!
        _RTE-RFL-THRESHOLD*10
    REPEAT
    _RTE-RFL-DIGITS @ ;

: _RTE-RFL-BASE-RATIONAL  ( -- )
    _RTE-RFL-VALUE @ _RTE-RFL-SCALE @ _RTE-MAGNITUDE/MOD
    _RTE-RFL-QUOT ! _RTE-RFL-REM !
    _RTE-RFL-FORMAT @ RTE-READOUT-PERCENT = IF
        _RTE-RFL-QUOT @ 100 UM*
        _RTE-RFL-Q-HI ! _RTE-RFL-Q-LO !
        _RTE-RFL-PERCENT-REMAINDER
        _RTE-RFL-EXTRA ! _RTE-RFL-REM !
        _RTE-RFL-EXTRA @ _RTE-RFL-Q+
    ELSE
        _RTE-RFL-QUOT @ _RTE-RFL-Q-LO !
        0 _RTE-RFL-Q-HI !
    THEN
    _RTE-RFL-INTEGER-CARRY? IF 1 _RTE-RFL-Q+ THEN ;

: _RTE-RFL-ADD?  ( u -- flag )
    _RTE-RFL-LENGTH @ SWAP _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-U32? 0= IF DROP 0 EXIT THEN
    _RTE-RFL-LENGTH ! -1 ;

: RTE-READOUT-FORMATTED-BYTES?
    ( format decimals value scale unit-bytes -- bytes flag )
    _RTE-RFL-UNIT-U ! _RTE-RFL-SCALE ! _RTE-RFL-VALUE !
    _RTE-RFL-DECIMALS ! _RTE-RFL-FORMAT !
    _RTE-RFL-FORMAT @ DUP RTE-READOUT-INTEGER U<
        SWAP RTE-READOUT-PERCENT U> OR IF 0 0 EXIT THEN
    _RTE-RFL-DECIMALS @ _RTE-U32? 0= IF 0 0 EXIT THEN
    _RTE-RFL-UNIT-U @ _RTE-U32? 0= IF 0 0 EXIT THEN
    _RTE-RFL-FORMAT @ RTE-READOUT-INTEGER = IF
        _RTE-RFL-DECIMALS @ IF 0 0 EXIT THEN
        _RTE-RFL-SCALE @ 1 <> IF 0 0 EXIT THEN
    ELSE
        _RTE-RFL-SCALE @ 0> 0= IF 0 0 EXIT THEN
    THEN
    _RTE-RFL-BASE-RATIONAL
    _RTE-RFL-INTEGER-DIGITS _RTE-RFL-LENGTH !
    _RTE-RFL-VALUE @ 0< IF 1 _RTE-RFL-ADD? 0= IF 0 0 EXIT THEN THEN
    _RTE-RFL-DECIMALS @ IF
        1 _RTE-RFL-ADD? 0= IF 0 0 EXIT THEN
        _RTE-RFL-DECIMALS @ _RTE-RFL-ADD? 0= IF 0 0 EXIT THEN
    THEN
    _RTE-RFL-FORMAT @ RTE-READOUT-PERCENT = IF
        1 _RTE-RFL-ADD? 0= IF 0 0 EXIT THEN
    THEN
    _RTE-RFL-UNIT-U @ _RTE-RFL-ADD? 0= IF 0 0 EXIT THEN
    _RTE-RFL-LENGTH @ -1 ;

VARIABLE _RTE-LI-INSTRUMENT

: _RTE-INSTRUMENT-GEOMETRY?  ( -- flag )
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.ROW @ _RTE-I32? 0= IF
        0 EXIT
    THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.COL @ _RTE-I32? 0= IF
        0 EXIT
    THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.HEIGHT @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.WIDTH @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.ROOT-HEIGHT @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.ROOT-WIDTH @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.ROW @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.HEIGHT @ _RTE-SADD? 0= IF
        DROP 0 EXIT
    THEN DROP
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.COL @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.WIDTH @ _RTE-SADD? 0= IF
        DROP 0 EXIT
    THEN DROP
    -1 ;

: _RTE-INSTRUMENT-READOUT?  ( -- flag )
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MINIMUM @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MAXIMUM @ OR IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MODE @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.OPTIONS @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.VALUE @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.SCALE @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-U @
        RTE-READOUT-FORMATTED-BYTES? 0= IF DROP 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.FORMATTED-U @ = ;

: _RTE-INSTRUMENT-METER?  ( -- flag )
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MODE @ DUP
        RTE-METER-HORIZONTAL =
    SWAP RTE-METER-VERTICAL = OR 0= IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.OPTIONS @
        RTE-METER-SHOW-VALUE INVERT AND IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MINIMUM @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MAXIMUM @ >= IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.VALUE @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MINIMUM @ < IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.VALUE @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MAXIMUM @ > IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.SCALE @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-A @ OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-U @ OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.FORMATTED-U @ OR 0= ;

: _RTE-INSTRUMENT-STATUS?  ( -- flag )
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MODE @ DUP
        RTE-STATUS-CIRCLE U<
    SWAP RTE-STATUS-DIAMOND U> OR IF 0 EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.OPTIONS @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MINIMUM @ OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.MAXIMUM @ OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.SCALE @ OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-A @ OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-U @ OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.FORMATTED-U @ OR 0= ;

: _RTE-INSTRUMENT-KIND?  ( -- flag )
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.KIND @
        RTE-INSTRUMENT-READOUT = IF _RTE-INSTRUMENT-READOUT? EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.KIND @
        RTE-INSTRUMENT-METER = IF _RTE-INSTRUMENT-METER? EXIT THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.KIND @
        RTE-INSTRUMENT-STATUS = IF _RTE-INSTRUMENT-STATUS? EXIT THEN
    0 ;

: _RTE-INSTRUMENT-FIELDS?  ( instrument -- flag )
    _RTE-LI-INSTRUMENT !
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.OWNER @ 0=
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.GENERATION @ 0= OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.ID @ 0= OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.REGION @ 0= OR IF
        0 0 _RTE-LI-INSTRUMENT ! EXIT
    THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.PARENT @
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.ID @ = IF
        0 0 _RTE-LI-INSTRUMENT ! EXIT
    THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.VISIBLE @ _RTE-BOOL? 0= IF
        0 0 _RTE-LI-INSTRUMENT ! EXIT
    THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.Z @ _RTE-I32? 0= IF
        0 0 _RTE-LI-INSTRUMENT ! EXIT
    THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.COLOR-A @ _RTE-U32? 0=
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.COLOR-B @ _RTE-U32? 0= OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-U @ _RTE-U32? 0= OR
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.FORMATTED-U @ _RTE-U32? 0= OR IF
        0 0 _RTE-LI-INSTRUMENT ! EXIT
    THEN
    _RTE-LI-INSTRUMENT @ _RTE-INSTRUMENT.RESERVED @ IF
        0 0 _RTE-LI-INSTRUMENT ! EXIT
    THEN
    _RTE-INSTRUMENT-GEOMETRY? 0= IF
        0 0 _RTE-LI-INSTRUMENT ! EXIT
    THEN
    _RTE-INSTRUMENT-KIND?
    0 _RTE-LI-INSTRUMENT ! ;

: _RTE-INSTRUMENT-STRUCTURAL?  ( instrument -- flag )
    DUP RTE-INSTRUMENT-SIZE _RTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTE-INSTRUMENT-FIELDS? 0= IF DROP 0 EXIT THEN
    DUP _RTE-INSTRUMENT.UNIT-A @ SWAP _RTE-INSTRUMENT.UNIT-U @
        _RTE-CONTROL-TEXT-SPAN? ;

: RTE-INSTRUMENT-VALID?  ( instrument -- flag )
    DUP _RTE-INSTRUMENT-STRUCTURAL? 0= IF DROP 0 EXIT THEN
    DUP _RTE-INSTRUMENT.UNIT-A @ SWAP _RTE-INSTRUMENT.UNIT-U @
        _RTE-CONTROL-TEXT? ;

: _RTE-CONTROL-DESCENDANT?  ( -- flag )
    _RTE-LC-CONTROL @ _RTE-CONTROL.PARENT @ 0<>
    _RTE-LC-CONTROL @ _RTE-CONTROL.Z @ 0= AND
    _RTE-LC-CONTROL @ _RTE-CONTROL.ROW @
    _RTE-LC-CONTROL @ _RTE-CONTROL.COL @ OR
    _RTE-LC-CONTROL @ _RTE-CONTROL.HEIGHT @ OR
    _RTE-LC-CONTROL @ _RTE-CONTROL.WIDTH @ OR 0= AND ;

: _RTE-CONTROL-TEXT-COLLECTION-KIND?  ( kind -- flag )
    DUP RTE-CONTROL-TEXT-AREA =
    SWAP RTE-CONTROL-TEXT-GRID = OR ;

: _RTE-CONTROL-COLLECTION-KIND?  ( kind -- flag )
    DUP _RTE-CONTROL-TEXT-COLLECTION-KIND? IF DROP -1 EXIT THEN
    DUP RTE-CONTROL-TABSET =
    SWAP RTE-CONTROL-TAB = OR ;

: _RTE-CONTROL-ROOT-KIND?  ( kind -- flag )
    DUP RTE-CONTROL-MENU-BAR = IF DROP -1 EXIT THEN
    DUP _RTE-CONTROL-TEXT-COLLECTION-KIND? IF DROP -1 EXIT THEN
    RTE-CONTROL-TABSET = ;

: _RTE-CONTROL-CONTENT-ZERO?  ( -- flag )
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-A @
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-U @ OR
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-ITEMS @ OR
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 @ OR 0= ;

: _RTE-CONTROL-SPANS-DISJOINT-FINISH  ( flag -- flag )
    0 _RTE-CSD-CONTROL ! ;

: _RTE-CONTROL-SPANS-DISJOINT?  ( control -- flag )
    _RTE-CSD-CONTROL !
    _RTE-CSD-CONTROL @ _RTE-CONTROL.LABEL-A @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.LABEL-U @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.SHORTCUT-A @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.SHORTCUT-U @
        MSPAN-OVERLAP? IF 0 _RTE-CONTROL-SPANS-DISJOINT-FINISH EXIT THEN
    _RTE-CSD-CONTROL @ _RTE-CONTROL.LABEL-A @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.LABEL-U @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.CONTENT-A @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.CONTENT-U @
        MSPAN-OVERLAP? IF 0 _RTE-CONTROL-SPANS-DISJOINT-FINISH EXIT THEN
    _RTE-CSD-CONTROL @ _RTE-CONTROL.SHORTCUT-A @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.SHORTCUT-U @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.CONTENT-A @
    _RTE-CSD-CONTROL @ _RTE-CONTROL.CONTENT-U @
        MSPAN-OVERLAP? IF 0 _RTE-CONTROL-SPANS-DISJOINT-FINISH EXIT THEN
    -1 _RTE-CONTROL-SPANS-DISJOINT-FINISH ;

: _RTE-CONTROL-COLLECTION-CONTENT?  ( -- flag )
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-U @ 72 U< IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-ITEMS @
        32 _RTE-UMUL? 0= IF DROP 0 EXIT THEN
    72 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 @
        _RTE-UADD? 0= IF DROP 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-U @ = ;

: _RTE-CONTROL-GEOMETRY?  ( -- flag )
    _RTE-LC-CONTROL @ _RTE-CONTROL.ROW @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.COL @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.HEIGHT @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.WIDTH @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.ROOT-HEIGHT @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.ROOT-WIDTH @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @
        _RTE-CONTROL-ROOT-KIND? 0= IF
        _RTE-CONTROL-DESCENDANT? EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.HEIGHT @ 0=
    _RTE-LC-CONTROL @ _RTE-CONTROL.WIDTH @ 0= OR IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.ROW @
    _RTE-LC-CONTROL @ _RTE-CONTROL.HEIGHT @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-LC-ROW-END !
    _RTE-LC-CONTROL @ _RTE-CONTROL.ROOT-HEIGHT @ U> IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.COL @
    _RTE-LC-CONTROL @ _RTE-CONTROL.WIDTH @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-LC-COL-END !
    _RTE-LC-CONTROL @ _RTE-CONTROL.ROOT-WIDTH @ U> IF 0 EXIT THEN
    -1 ;

: _RTE-CONTROL-KIND?  ( -- flag )
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @
        RTE-CONTROL-MENU-BAR = IF
        _RTE-LC-CONTROL @ _RTE-CONTROL.PARENT @ IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.ORDER @ IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @
        _RTE-LC-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ OR IF 0 EXIT THEN
        _RTE-CONTROL-CONTENT-ZERO? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR INVERT AND 0= EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @ RTE-CONTROL-MENU = IF
        _RTE-CONTROL-DESCENDANT? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @ 0> 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ IF 0 EXIT THEN
        _RTE-CONTROL-CONTENT-ZERO? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            _RTE-CONTROL-MENU-STATE-MASK INVERT AND 0= EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @ RTE-CONTROL-MENU-ITEM = IF
        _RTE-CONTROL-DESCENDANT? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @ 0> 0= IF 0 EXIT THEN
        _RTE-CONTROL-CONTENT-ZERO? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            _RTE-CONTROL-ITEM-STATE-MASK INVERT AND 0= EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @
        RTE-CONTROL-MENU-SEPARATOR = IF
        _RTE-CONTROL-DESCENDANT? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @
        _RTE-LC-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ OR IF 0 EXIT THEN
        _RTE-CONTROL-CONTENT-ZERO? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            RTE-CONTROL-VISIBLE INVERT AND 0= EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @
        _RTE-CONTROL-TEXT-COLLECTION-KIND? IF
        _RTE-LC-CONTROL @ _RTE-CONTROL.PARENT @
        _RTE-LC-CONTROL @ _RTE-CONTROL.ORDER @ OR IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @
        _RTE-LC-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ OR IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            _RTE-CONTROL-COLLECTION-STATE-MASK INVERT AND IF
            0 EXIT
        THEN
        _RTE-CONTROL-COLLECTION-CONTENT? EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @ RTE-CONTROL-TABSET = IF
        _RTE-LC-CONTROL @ _RTE-CONTROL.PARENT @
        _RTE-LC-CONTROL @ _RTE-CONTROL.ORDER @ OR IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @
        _RTE-LC-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ OR IF 0 EXIT THEN
        _RTE-CONTROL-CONTENT-ZERO? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            _RTE-CONTROL-TABSET-STATE-MASK INVERT AND 0= EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @ RTE-CONTROL-TAB = IF
        _RTE-CONTROL-DESCENDANT? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @ 0> 0= IF 0 EXIT THEN
        _RTE-CONTROL-CONTENT-ZERO? 0= IF 0 EXIT THEN
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            _RTE-CONTROL-COLLECTION-STATE-MASK INVERT AND 0= EXIT
    THEN
    0 ;

: _RTE-CONTROL-FIELDS-BODY?  ( -- flag )
    _RTE-LC-CONTROL @ _RTE-CONTROL.OWNER @ 0=
    _RTE-LC-CONTROL @ _RTE-CONTROL.GENERATION @ 0= OR
    _RTE-LC-CONTROL @ _RTE-CONTROL.ID @ 0= OR
    _RTE-LC-CONTROL @ _RTE-CONTROL.REGION @ 0= OR IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.PARENT @
    _RTE-LC-CONTROL @ _RTE-CONTROL.ID @ = IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.KIND @ _RTE-U16? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @ _RTE-U16? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.Z @ _RTE-I32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.ORDER @ _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @ _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.SHORTCUT-U @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-U @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-ITEMS @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.LABEL-U @
    _RTE-LC-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.CONTENT-U @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN DROP
    _RTE-LC-CONTROL @ _RTE-CONTROL.RESERVED @ IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
        _RTE-CONTROL-STATE-MASK INVERT AND IF 0 EXIT THEN
    _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
        RTE-CONTROL-OPEN RTE-CONTROL-SELECTED OR AND IF
        _RTE-LC-CONTROL @ _RTE-CONTROL.STATE @
            RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR AND
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR <> IF 0 EXIT THEN
    THEN
    _RTE-CONTROL-GEOMETRY? 0= IF 0 EXIT THEN
    _RTE-CONTROL-KIND? ;

: _RTE-CONTROL-FIELDS?  ( control -- flag )
    _RTE-LC-CONTROL !
    _RTE-CONTROL-FIELDS-BODY?
    _RTE-LC-FINISH ;

: RTE-CONTROL-VALID?  ( control -- flag )
    DUP RTE-CONTROL-SIZE _RTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTE-CONTROL-FIELDS? 0= IF DROP 0 EXIT THEN
    DUP _RTE-CONTROL.LABEL-A @ OVER _RTE-CONTROL.LABEL-U @
        _RTE-CONTROL-TEXT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-CONTROL.SHORTCUT-A @ OVER _RTE-CONTROL.SHORTCUT-U @
        _RTE-CONTROL-TEXT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-CONTROL.CONTENT-A @ OVER _RTE-CONTROL.CONTENT-U @
        _RTE-CONTROL-CONTENT-SPAN? 0= IF DROP 0 EXIT THEN
    _RTE-CONTROL-SPANS-DISJOINT? ;

\ INSTRUMENT plan validation performs one caller-bounded pass over the exact
\ region bank and one pass over the exact descriptor bank.  It derives all
\ hybrid admission aggregates itself; a provider never receives authority to
\ revisit either bank or any unit source.
VARIABLE _RTE-IPV-PLAN
VARIABLE _RTE-IPV-REGION
VARIABLE _RTE-IPV-ITEM
VARIABLE _RTE-IPV-REGIONS-A
VARIABLE _RTE-IPV-REGIONS-U
VARIABLE _RTE-IPV-REGIONS-END
VARIABLE _RTE-IPV-ITEMS-A
VARIABLE _RTE-IPV-ITEMS-U
VARIABLE _RTE-IPV-BYTES-A
VARIABLE _RTE-IPV-BYTES-U
VARIABLE _RTE-IPV-FIXED-AUTHORITY
VARIABLE _RTE-IPV-REGION-COUNT
VARIABLE _RTE-IPV-PRIOR-REGION-ID
VARIABLE _RTE-IPV-FIRST-REGION-ID
VARIABLE _RTE-IPV-REGION-USED
VARIABLE _RTE-IPV-COUNT
VARIABLE _RTE-IPV-READOUTS
VARIABLE _RTE-IPV-METERS
VARIABLE _RTE-IPV-STATUSES
VARIABLE _RTE-IPV-UNIT-BYTES
VARIABLE _RTE-IPV-UNIT-ALIGNED
VARIABLE _RTE-IPV-UNIT-MAX
VARIABLE _RTE-IPV-FORMATTED-BYTES
VARIABLE _RTE-IPV-FORMATTED-MAX
VARIABLE _RTE-IPV-PRIOR-ID
VARIABLE _RTE-IPV-LAST-ID
VARIABLE _RTE-IPV-SPAN-A
VARIABLE _RTE-IPV-SPAN-U
VARIABLE _RTE-IPV-END

: _RTE-IPV-FINISH  ( x -- x )
    0 _RTE-IPV-PLAN ! 0 _RTE-IPV-REGION ! 0 _RTE-IPV-ITEM !
    0 _RTE-IPV-REGIONS-A ! 0 _RTE-IPV-REGIONS-U !
    0 _RTE-IPV-REGIONS-END !
    0 _RTE-IPV-ITEMS-A ! 0 _RTE-IPV-ITEMS-U !
    0 _RTE-IPV-BYTES-A ! 0 _RTE-IPV-BYTES-U !
    0 _RTE-IPV-FIXED-AUTHORITY !
    0 _RTE-IPV-REGION-COUNT ! 0 _RTE-IPV-PRIOR-REGION-ID !
    0 _RTE-IPV-FIRST-REGION-ID !
    0 _RTE-IPV-REGION-USED !
    0 _RTE-IPV-COUNT ! 0 _RTE-IPV-READOUTS !
    0 _RTE-IPV-METERS ! 0 _RTE-IPV-STATUSES !
    0 _RTE-IPV-UNIT-BYTES ! 0 _RTE-IPV-UNIT-ALIGNED !
    0 _RTE-IPV-UNIT-MAX ! 0 _RTE-IPV-FORMATTED-BYTES !
    0 _RTE-IPV-FORMATTED-MAX !
    0 _RTE-IPV-PRIOR-ID ! 0 _RTE-IPV-LAST-ID !
    0 _RTE-IPV-SPAN-A ! 0 _RTE-IPV-SPAN-U ! 0 _RTE-IPV-END ! ;

: _RTE-IPV-HEADER?  ( -- flag )
    _RTE-IPV-FIXED-AUTHORITY @ 0= IF
        _RTE-IPV-PLAN @ RTE-INSTRUMENT-PLAN-SIZE _RTE-SPAN? 0= IF
            0 EXIT
        THEN
    THEN
    _RTE-IPV-PLAN @ _RTE-IP.OWNER @ 0= IF 0 EXIT THEN
    _RTE-IPV-PLAN @ _RTE-IP.GENERATION @ 0= IF 0 EXIT THEN
    _RTE-IPV-PLAN @ _RTE-IP.SURFACE-COLS @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-IPV-PLAN @ _RTE-IP.SURFACE-ROWS @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-IPV-PLAN @ _RTE-IP.RESERVED @ IF 0 EXIT THEN

    _RTE-IPV-PLAN @ _RTE-IP.REGIONS-A @ _RTE-IPV-REGIONS-A !
    _RTE-IPV-PLAN @ _RTE-IP.REGIONS-U @ _RTE-IPV-REGIONS-U !
    _RTE-IPV-PLAN @ _RTE-IP.ITEMS-A @ _RTE-IPV-ITEMS-A !
    _RTE-IPV-PLAN @ _RTE-IP.ITEMS-U @ _RTE-IPV-ITEMS-U !
    _RTE-IPV-REGIONS-A @ _RTE-IPV-REGIONS-U @ _RTE-SPAN? 0= IF 0 EXIT THEN
    _RTE-IPV-REGIONS-U @ 0= IF 0 EXIT THEN
    _RTE-IPV-REGIONS-U @ RTE-INSTRUMENT-REGION-SIZE MOD IF 0 EXIT THEN
    _RTE-IPV-ITEMS-A @ _RTE-IPV-ITEMS-U @ _RTE-SPAN? 0= IF 0 EXIT THEN
    _RTE-IPV-ITEMS-U @ 0= IF 0 EXIT THEN
    _RTE-IPV-ITEMS-U @ RTE-INSTRUMENT-SIZE MOD IF 0 EXIT THEN
    _RTE-IPV-FIXED-AUTHORITY @ 0= IF
        _RTE-IPV-PLAN @ RTE-INSTRUMENT-PLAN-SIZE
        _RTE-IPV-REGIONS-A @ _RTE-IPV-REGIONS-U @ MSPAN-OVERLAP? IF
            0 EXIT
        THEN
        _RTE-IPV-PLAN @ RTE-INSTRUMENT-PLAN-SIZE
        _RTE-IPV-ITEMS-A @ _RTE-IPV-ITEMS-U @ MSPAN-OVERLAP? IF
            0 EXIT
        THEN
        _RTE-IPV-REGIONS-A @ _RTE-IPV-REGIONS-U @
        _RTE-IPV-ITEMS-A @ _RTE-IPV-ITEMS-U @ MSPAN-OVERLAP? IF
            0 EXIT
        THEN
    THEN
    -1 ;

: _RTE-IPV-REGION-ID?  ( -- flag )
    _RTE-IPV-REGION @ _RTE-IR.ID @ DUP 0= IF DROP 0 EXIT THEN
    DUP _RTE-IPV-PRIOR-REGION-ID @ U> 0= IF DROP 0 EXIT THEN
    _RTE-IPV-REGION-COUNT @ 0= IF
        DUP _RTE-IPV-FIRST-REGION-ID !
    THEN
    _RTE-IPV-PRIOR-REGION-ID !
    _RTE-IPV-REGION-COUNT @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-U32? 0= IF DROP 0 EXIT THEN _RTE-IPV-REGION-COUNT !
    -1 ;

: _RTE-IPV-REGION?  ( -- flag )
    _RTE-IPV-REGION-ID? 0= IF 0 EXIT THEN
    _RTE-IPV-REGION @ _RTE-IR.Z @ _RTE-I32? 0= IF 0 EXIT THEN
    _RTE-IPV-REGION @ _RTE-IR.RESERVED @ IF 0 EXIT THEN
    _RTE-IPV-REGION @ _RTE-IR.X @
    _RTE-IPV-REGION @ _RTE-IR.Y @
    _RTE-IPV-REGION @ _RTE-IR.COLS @
    _RTE-IPV-REGION @ _RTE-IR.ROWS @
    _RTE-IPV-REGION @ _RTE-IR.CLIP-X @
    _RTE-IPV-REGION @ _RTE-IR.CLIP-Y @
    _RTE-IPV-REGION @ _RTE-IR.CLIP-COLS @
    _RTE-IPV-REGION @ _RTE-IR.CLIP-ROWS @
    _RTE-IPV-REGION @ _RTE-IR.FLAGS @
    _RTE-IPV-PLAN @ _RTE-IP.SURFACE-COLS @
    _RTE-IPV-PLAN @ _RTE-IP.SURFACE-ROWS @
        _RTE-REGION-GEOMETRY? ;

: _RTE-IPV-UNIT-AUTHORITY?  ( -- flag )
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.UNIT-A @ _RTE-IPV-SPAN-A !
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.UNIT-U @ _RTE-IPV-SPAN-U !
    _RTE-IPV-SPAN-U @ 0= IF _RTE-IPV-SPAN-A @ 0= EXIT THEN
    _RTE-IPV-FIXED-AUTHORITY @ IF
        _RTE-IPV-BYTES-U @ 0= IF 0 EXIT THEN
        _RTE-IPV-SPAN-A @ _RTE-IPV-BYTES-A @ U< IF 0 EXIT THEN
        _RTE-IPV-SPAN-A @ _RTE-IPV-SPAN-U @ _RTE-UADD? 0= IF
            DROP 0 EXIT
        THEN _RTE-IPV-END !
        _RTE-IPV-BYTES-A @ _RTE-IPV-BYTES-U @ _RTE-UADD? 0= IF
            DROP 0 EXIT
        THEN
        _RTE-IPV-END @ SWAP U> 0= EXIT
    THEN
    _RTE-IPV-SPAN-A @ _RTE-IPV-SPAN-U @
    _RTE-IPV-PLAN @ RTE-INSTRUMENT-PLAN-SIZE MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    _RTE-IPV-SPAN-A @ _RTE-IPV-SPAN-U @
    _RTE-IPV-REGIONS-A @ _RTE-IPV-REGIONS-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    _RTE-IPV-SPAN-A @ _RTE-IPV-SPAN-U @
    _RTE-IPV-ITEMS-A @ _RTE-IPV-ITEMS-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    -1 ;

: _RTE-IPV-CORRELATES?  ( -- flag )
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.OWNER @
        _RTE-IPV-PLAN @ _RTE-IP.OWNER @ <> IF 0 EXIT THEN
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.GENERATION @
        _RTE-IPV-PLAN @ _RTE-IP.GENERATION @ <> IF 0 EXIT THEN
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.REGION @
        _RTE-IPV-REGION @ _RTE-IR.ID @ <> IF
        _RTE-IPV-REGION-USED @ 0= IF 0 EXIT THEN
        _RTE-IPV-REGION @ RTE-INSTRUMENT-REGION-SIZE + DUP
            _RTE-IPV-REGIONS-END @ U< 0= IF DROP 0 EXIT THEN
        _RTE-IPV-REGION !
        _RTE-IPV-ITEM @ _RTE-INSTRUMENT.REGION @
            _RTE-IPV-REGION @ _RTE-IR.ID @ <> IF 0 EXIT THEN
        0 _RTE-IPV-REGION-USED !
    THEN
    -1 _RTE-IPV-REGION-USED !
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.ROOT-HEIGHT @
        _RTE-IPV-REGION @ _RTE-IR.ROWS @ <> IF 0 EXIT THEN
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.ROOT-WIDTH @
        _RTE-IPV-REGION @ _RTE-IR.COLS @ <> IF 0 EXIT THEN
    -1 ;

: _RTE-IPV-ID?  ( -- flag )
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.ID @ DUP
    _RTE-IPV-PRIOR-ID @ U> 0= IF DROP 0 EXIT THEN
    DUP _RTE-IPV-PRIOR-ID ! _RTE-IPV-LAST-ID ! -1 ;

: _RTE-IPV-KIND-COUNT?  ( -- flag )
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.KIND @
        RTE-INSTRUMENT-READOUT = IF
        _RTE-IPV-READOUTS @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
        DUP _RTE-U32? 0= IF DROP 0 EXIT THEN _RTE-IPV-READOUTS ! -1 EXIT
    THEN
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.KIND @
        RTE-INSTRUMENT-METER = IF
        _RTE-IPV-METERS @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
        DUP _RTE-U32? 0= IF DROP 0 EXIT THEN _RTE-IPV-METERS ! -1 EXIT
    THEN
    _RTE-IPV-STATUSES @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-U32? 0= IF DROP 0 EXIT THEN _RTE-IPV-STATUSES ! -1 ;

: _RTE-IPV-AGGREGATE?  ( -- flag )
    _RTE-IPV-COUNT @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-U32? 0= IF DROP 0 EXIT THEN _RTE-IPV-COUNT !
    _RTE-IPV-UNIT-BYTES @
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.UNIT-U @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-U32? 0= IF DROP 0 EXIT THEN _RTE-IPV-UNIT-BYTES !
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.UNIT-U @ 7 _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN 7 INVERT AND
    _RTE-IPV-UNIT-ALIGNED @ SWAP _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-U32? 0= IF DROP 0 EXIT THEN _RTE-IPV-UNIT-ALIGNED !
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.UNIT-U @
        _RTE-IPV-UNIT-MAX @ MAX _RTE-IPV-UNIT-MAX !
    _RTE-IPV-FORMATTED-BYTES @
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.FORMATTED-U @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-U32? 0= IF DROP 0 EXIT THEN
    _RTE-IPV-FORMATTED-BYTES !
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.FORMATTED-U @
        _RTE-IPV-FORMATTED-MAX @ MAX _RTE-IPV-FORMATTED-MAX !
    _RTE-IPV-KIND-COUNT? ;

: _RTE-IPV-ITEM-STRUCTURAL?  ( -- flag )
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT-STRUCTURAL? ;

: _RTE-IPV-ITEM-TEXT?  ( -- flag )
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.UNIT-A @
    _RTE-IPV-ITEM @ _RTE-INSTRUMENT.UNIT-U @
        _RTE-CONTROL-TEXT? ;

: _RTE-IPV-ITEM?  ( -- flag )
    _RTE-IPV-ITEM-STRUCTURAL? 0= IF 0 EXIT THEN
    _RTE-IPV-UNIT-AUTHORITY? 0= IF 0 EXIT THEN
    _RTE-IPV-ITEM-TEXT? 0= IF 0 EXIT THEN
    _RTE-IPV-CORRELATES? 0= IF 0 EXIT THEN
    _RTE-IPV-ID? 0= IF 0 EXIT THEN
    _RTE-IPV-AGGREGATE? ;

: _RTE-INSTRUMENT-PLAN-VALID-BODY  ( -- flag )
    _RTE-IPV-HEADER? 0= IF 0 EXIT THEN
    0 _RTE-IPV-REGION-COUNT ! 0 _RTE-IPV-PRIOR-REGION-ID !
    0 _RTE-IPV-FIRST-REGION-ID !
    _RTE-IPV-REGIONS-A @ _RTE-IPV-REGION !
    _RTE-IPV-REGIONS-A @ _RTE-IPV-REGIONS-U @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTE-IPV-REGIONS-END !
    _RTE-IPV-REGIONS-U @ RTE-INSTRUMENT-REGION-SIZE / 0 ?DO
        _RTE-IPV-REGION? 0= IF 0 UNLOOP EXIT THEN
        RTE-INSTRUMENT-REGION-SIZE _RTE-IPV-REGION +!
    LOOP

    0 _RTE-IPV-COUNT ! 0 _RTE-IPV-READOUTS !
    0 _RTE-IPV-METERS ! 0 _RTE-IPV-STATUSES !
    0 _RTE-IPV-UNIT-BYTES ! 0 _RTE-IPV-UNIT-ALIGNED !
    0 _RTE-IPV-UNIT-MAX ! 0 _RTE-IPV-FORMATTED-BYTES !
    0 _RTE-IPV-FORMATTED-MAX !
    0 _RTE-IPV-PRIOR-ID ! 0 _RTE-IPV-LAST-ID !
    _RTE-IPV-REGIONS-A @ _RTE-IPV-REGION !
    0 _RTE-IPV-REGION-USED !
    _RTE-IPV-ITEMS-A @ _RTE-IPV-ITEM !
    _RTE-IPV-ITEMS-U @ RTE-INSTRUMENT-SIZE / 0 ?DO
        _RTE-IPV-ITEM? 0= IF 0 UNLOOP EXIT THEN
        RTE-INSTRUMENT-SIZE _RTE-IPV-ITEM +!
    LOOP
    _RTE-IPV-REGION-USED @ 0= IF 0 EXIT THEN
    _RTE-IPV-REGION @ RTE-INSTRUMENT-REGION-SIZE +
        _RTE-IPV-REGIONS-END @ = ;

: RTE-INSTRUMENT-PLAN-VALID?  ( plan -- flag )
    _RTE-IPV-PLAN !
    0 _RTE-IPV-FIXED-AUTHORITY !
    _RTE-INSTRUMENT-PLAN-VALID-BODY
    _RTE-IPV-FINISH ;

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
    _RTE-LV-FEATURES @ RTE-F-CONTROL-COLLECTIONS AND
    _RTE-LV-FEATURES @ RTE-F-CONTROLS AND 0= AND IF 0 EXIT THEN

    _RTE-LV-L @ _RTE-L.OWNER-RECORDS @ 0=
    _RTE-LV-L @ _RTE-L.LIVE-OWNERS @ 0= OR
    _RTE-LV-L @ _RTE-L.REGIONS @ 0= OR
    _RTE-LV-L @ _RTE-L.OPS @ 0= OR IF 0 EXIT THEN
    _RTE-LV-L @ _RTE-L.LIVE-OWNERS @
    _RTE-LV-L @ _RTE-L.OWNER-RECORDS @ U> IF 0 EXIT THEN
    264 _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    _RTE-LV-L @ _RTE-L.OUTBOUND-PAYLOAD @ 64 U< IF 0 EXIT THEN

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

    _RTE-LV-FEATURES @
        RTE-F-VECTOR RTE-F-IMAGE OR RTE-F-INSTRUMENT OR RTE-F-SERIES OR
        RTE-F-CONTROLS OR AND IF
        _RTE-LV-L @ _RTE-L.OBJECTS @ 0= IF 0 EXIT THEN
    THEN
    _RTE-LV-L @ _RTE-L.PATH-POINTS @
    _RTE-LV-FEATURES @ RTE-F-VECTOR AND 0<> _RTE-POSITIVE-EXACT? 0= IF
        0 EXIT
    THEN
    _RTE-LV-L @ _RTE-L.GLYPH-RUN-BYTES @ ?DUP IF
        _RTE-LV-L @ _RTE-L.OBJECTS @ 0= IF DROP 0 EXIT THEN
        DUP _RTE-LV-L @ _RTE-L.UTF8-BYTES @ U> IF DROP 0 EXIT THEN
        280 _RTE-UADD? 0= IF DROP 0 EXIT THEN
        _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    ELSE
        _RTE-LV-FEATURES @ RTE-F-CONTROLS AND 0= IF
            _RTE-LV-L @ _RTE-L.UTF8-BYTES @ IF 0 EXIT THEN
        THEN
        _RTE-LV-FEATURES @ RTE-F-INSTRUMENT AND IF 0 EXIT THEN
    THEN
    _RTE-LV-FEATURES @ RTE-F-CONTROLS AND IF
        _RTE-LV-L @ _RTE-L.OBJECTS @ 0= IF 0 EXIT THEN
        _RTE-LV-FEATURES @ RTE-F-CONTROL-COLLECTIONS AND 0= IF
            _RTE-LV-L @ _RTE-L.UTF8-BYTES @ 0= IF 0 EXIT THEN
        THEN
        _RTE-LV-L @ _RTE-L.OUTBOUND-PAYLOAD @ 80 U< IF 0 EXIT THEN
        280 _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    _RTE-LV-FEATURES @ RTE-F-CONTROL-COLLECTIONS AND IF
        _RTE-LV-L @ _RTE-L.OUTBOUND-PAYLOAD @ 152 U< IF 0 EXIT THEN
        352 _RTE-LV-L @ _RTE-LIMIT-FLOOR? 0= IF 0 EXIT THEN
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
        _RTE-LV-L @ _RTE-L.GLYPH-RUN-BYTES @ 304 _RTE-UADD? 0= IF
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
    DUP _RTE-F.RESERVED @ IF DROP 0 EXIT THEN
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
    OVER _RTE-F.GLYPH-RUN-DEF-XT @ 0= OR IF DROP 0 EXIT THEN
    DUP _RTE-F.GLYPH-RUN-PREFLIGHT-XT @ 0=
    OVER _RTE-F.UPDATE-STATE-XT @ 0= OR
    OVER _RTE-F.GLYPH-RUN-REPLACE-XT @ 0= OR IF DROP 0 EXIT THEN
    DUP _RTE-F.CONTROL-PREFLIGHT-XT @ 0=
    OVER _RTE-F.CONTROL-DEF-XT @ 0= OR
    OVER _RTE-F.CONTROL-REPLACE-XT @ 0= OR
    OVER _RTE-F.CONTROL-DROP-XT @ 0= OR IF DROP 0 EXIT THEN
    DUP _RTE-F.HYBRID-PREFLIGHT-XT @ 0=
    OVER _RTE-F.INSTRUMENT-DEF-XT @ 0= OR IF DROP 0 EXIT THEN
    DROP -1 ;

: RTE-STORAGE-DISJOINT?  ( a u facade -- flag )
    DUP RTE-VALID? 0= IF _RTE-DROP3 0 EXIT THEN
    >R
    2DUP _RTE-BYTE-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ RTE-FACADE-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTE-F.CONTEXT @ R> _RTE-F.DISJOINT-XT @ EXECUTE
    DUP _RTE-BOOL? 0= IF DROP 0 THEN ;

\ CONTROL plan validation performs exactly one pass over the caller's item
\ bank.  Besides full intrinsic validation it proves header correlation,
\ contiguous parent-first identity, fixed-depth menu graph/order/state,
\ standalone semantic collection roots, and the exact scalar aggregates
\ consumed by provider admission.  A nonzero FACADE adds storage-authority
\ checks to that same pass; it never triggers a second item traversal.
VARIABLE _RTE-CPV-PLAN
VARIABLE _RTE-CPV-FACADE
VARIABLE _RTE-CPV-ITEM
VARIABLE _RTE-CPV-ITEMS-A
VARIABLE _RTE-CPV-ITEMS-U
VARIABLE _RTE-CPV-FIRST-ID
VARIABLE _RTE-CPV-PRIOR-ID
VARIABLE _RTE-CPV-COUNT
VARIABLE _RTE-CPV-BYTES
VARIABLE _RTE-CPV-ALIGNED-BYTES
VARIABLE _RTE-CPV-MAX-ITEM-BYTES
VARIABLE _RTE-CPV-LAST-ID
VARIABLE _RTE-CPV-ROOTS
VARIABLE _RTE-CPV-COLLECTIONS
VARIABLE _RTE-CPV-CONTENT-ITEMS
VARIABLE _RTE-CPV-UTF8-BYTES
VARIABLE _RTE-CPV-ROOT-ID
VARIABLE _RTE-CPV-ITEM-BYTES
VARIABLE _RTE-CPV-ITEM-UTF8
VARIABLE _RTE-CPV-ITEM-ALIGNED
VARIABLE _RTE-CPV-SPAN-A
VARIABLE _RTE-CPV-SPAN-U
VARIABLE _RTE-CPV-PHASE
VARIABLE _RTE-CPV-GROUP-ACTIVE
VARIABLE _RTE-CPV-GROUP-PARENT
VARIABLE _RTE-CPV-PRIOR-ORDER
VARIABLE _RTE-CPV-OPEN-SEEN
VARIABLE _RTE-CPV-SELECTED-SEEN
VARIABLE _RTE-CPV-PARENT-ID
VARIABLE _RTE-CPV-PARENT-INDEX
VARIABLE _RTE-CPV-PARENT-OFFSET
VARIABLE _RTE-CPV-PARENT-RECORD
VARIABLE _RTE-CPV-CONTROL-BYTES-A
VARIABLE _RTE-CPV-CONTROL-BYTES-U
VARIABLE _RTE-CPV-FIXED-AUTHORITY

0 CONSTANT _RTE-CPV-PHASE-MENUBAR
1 CONSTANT _RTE-CPV-PHASE-MENU
2 CONSTANT _RTE-CPV-PHASE-ROW
3 CONSTANT _RTE-CPV-PHASE-STANDALONE
4 CONSTANT _RTE-CPV-PHASE-TABSET
5 CONSTANT _RTE-CPV-PHASE-TAB

: _RTE-CPV-FINISH  ( x -- x )
    0 _RTE-CPV-PLAN !
    0 _RTE-CPV-FACADE !
    0 _RTE-CPV-ITEM !
    0 _RTE-CPV-ITEMS-A !
    0 _RTE-CPV-ITEMS-U !
    0 _RTE-CPV-FIRST-ID !
    0 _RTE-CPV-PRIOR-ID !
    0 _RTE-CPV-COUNT !
    0 _RTE-CPV-BYTES !
    0 _RTE-CPV-ALIGNED-BYTES !
    0 _RTE-CPV-MAX-ITEM-BYTES !
    0 _RTE-CPV-LAST-ID !
    0 _RTE-CPV-ROOTS !
    0 _RTE-CPV-COLLECTIONS !
    0 _RTE-CPV-CONTENT-ITEMS !
    0 _RTE-CPV-UTF8-BYTES !
    0 _RTE-CPV-ROOT-ID !
    0 _RTE-CPV-ITEM-BYTES !
    0 _RTE-CPV-ITEM-UTF8 !
    0 _RTE-CPV-ITEM-ALIGNED !
    0 _RTE-CPV-SPAN-A !
    0 _RTE-CPV-SPAN-U !
    0 _RTE-CPV-PHASE !
    0 _RTE-CPV-GROUP-ACTIVE !
    0 _RTE-CPV-GROUP-PARENT !
    0 _RTE-CPV-PRIOR-ORDER !
    0 _RTE-CPV-OPEN-SEEN !
    0 _RTE-CPV-SELECTED-SEEN !
    0 _RTE-CPV-PARENT-ID !
    0 _RTE-CPV-PARENT-INDEX !
    0 _RTE-CPV-PARENT-OFFSET !
    0 _RTE-CPV-PARENT-RECORD !
    0 _RTE-CPV-CONTROL-BYTES-A !
    0 _RTE-CPV-CONTROL-BYTES-U !
    0 _RTE-CPV-FIXED-AUTHORITY ! ;

: _RTE-CPV-HEADER?  ( -- flag )
    _RTE-CPV-FIXED-AUTHORITY @ 0= IF
        _RTE-CPV-PLAN @ RTE-CONTROL-PLAN-SIZE _RTE-SPAN? 0= IF
            0 EXIT
        THEN
        _RTE-CPV-FACADE @ IF
            _RTE-CPV-PLAN @ RTE-CONTROL-PLAN-SIZE _RTE-CPV-FACADE @
                RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
        THEN
    THEN
    _RTE-CPV-PLAN @ _RTE-CP.OWNER @ 0= IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.GENERATION @ 0= IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.SURFACE-COLS @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.SURFACE-ROWS @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.REGION-ID @ 0= IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.REGION-Z @ _RTE-I32? 0= IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.RESERVED @ IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.REGION-X @
    _RTE-CPV-PLAN @ _RTE-CP.REGION-Y @
    _RTE-CPV-PLAN @ _RTE-CP.REGION-COLS @
    _RTE-CPV-PLAN @ _RTE-CP.REGION-ROWS @
    _RTE-CPV-PLAN @ _RTE-CP.CLIP-X @
    _RTE-CPV-PLAN @ _RTE-CP.CLIP-Y @
    _RTE-CPV-PLAN @ _RTE-CP.CLIP-COLS @
    _RTE-CPV-PLAN @ _RTE-CP.CLIP-ROWS @
    _RTE-CPV-PLAN @ _RTE-CP.REGION-FLAGS @
    _RTE-CPV-PLAN @ _RTE-CP.SURFACE-COLS @
    _RTE-CPV-PLAN @ _RTE-CP.SURFACE-ROWS @
        _RTE-REGION-GEOMETRY? 0= IF 0 EXIT THEN
    _RTE-CPV-PLAN @ _RTE-CP.ITEMS-A @ _RTE-CPV-ITEMS-A !
    _RTE-CPV-PLAN @ _RTE-CP.ITEMS-U @ _RTE-CPV-ITEMS-U !
    _RTE-CPV-FIXED-AUTHORITY @ 0= IF
        _RTE-CPV-ITEMS-A @ _RTE-CPV-ITEMS-U @
            _RTE-SPAN? 0= IF 0 EXIT THEN
        _RTE-CPV-ITEMS-U @ RTE-CONTROL-SIZE MOD IF 0 EXIT THEN
        _RTE-CPV-PLAN @ RTE-CONTROL-PLAN-SIZE
            _RTE-CPV-ITEMS-A @ _RTE-CPV-ITEMS-U @ MSPAN-OVERLAP? IF
            0 EXIT
        THEN
        _RTE-CPV-FACADE @ IF
            _RTE-CPV-ITEMS-A @ _RTE-CPV-ITEMS-U @ _RTE-CPV-FACADE @
                RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
        THEN
    THEN
    -1 ;

: _RTE-CPV-BYTES-AUTHORITY?  ( a u -- flag )
    _RTE-CPV-SPAN-U ! _RTE-CPV-SPAN-A !
    _RTE-CPV-SPAN-U @ 0= IF _RTE-CPV-SPAN-A @ 0= EXIT THEN
    _RTE-CPV-FIXED-AUTHORITY @ IF
        _RTE-CPV-CONTROL-BYTES-U @ 0= IF 0 EXIT THEN
        _RTE-CPV-SPAN-A @ _RTE-CPV-CONTROL-BYTES-A @ U< IF 0 EXIT THEN
        _RTE-CPV-SPAN-A @ _RTE-CPV-SPAN-U @ +
        _RTE-CPV-CONTROL-BYTES-A @ _RTE-CPV-CONTROL-BYTES-U @ +
            U> IF 0 EXIT THEN
        -1 EXIT
    THEN
    _RTE-CPV-SPAN-A @ _RTE-CPV-SPAN-U @
        _RTE-CPV-PLAN @ RTE-CONTROL-PLAN-SIZE MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    _RTE-CPV-SPAN-A @ _RTE-CPV-SPAN-U @
        _RTE-CPV-ITEMS-A @ _RTE-CPV-ITEMS-U @ MSPAN-OVERLAP? IF
        0 EXIT
    THEN
    _RTE-CPV-FACADE @ IF
        _RTE-CPV-SPAN-A @ _RTE-CPV-SPAN-U @ _RTE-CPV-FACADE @
            RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    THEN
    -1 ;

: _RTE-CPV-ITEM-CORRELATES?  ( -- flag )
    _RTE-CPV-ITEM @ _RTE-CONTROL.OWNER @
        _RTE-CPV-PLAN @ _RTE-CP.OWNER @ <> IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.GENERATION @
        _RTE-CPV-PLAN @ _RTE-CP.GENERATION @ <> IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.REGION @
        _RTE-CPV-PLAN @ _RTE-CP.REGION-ID @ <> IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.ROOT-HEIGHT @
        _RTE-CPV-PLAN @ _RTE-CP.REGION-ROWS @ <> IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.ROOT-WIDTH @
        _RTE-CPV-PLAN @ _RTE-CP.REGION-COLS @ <> IF 0 EXIT THEN
    -1 ;

: _RTE-CPV-ITEM-STRUCTURAL?  ( -- flag )
    _RTE-CPV-ITEM @ RTE-CONTROL-SIZE _RTE-SPAN? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL-FIELDS? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-U @
        _RTE-CONTROL-TEXT-SPAN? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-U @
        _RTE-CONTROL-TEXT-SPAN? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.CONTENT-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.CONTENT-U @
        _RTE-CONTROL-CONTENT-SPAN? ;

: _RTE-CPV-ITEM-BYTES-AUTHORITY?  ( -- flag )
    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-U @
        _RTE-CPV-BYTES-AUTHORITY? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-U @
        _RTE-CPV-BYTES-AUTHORITY? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.CONTENT-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.CONTENT-U @
        _RTE-CPV-BYTES-AUTHORITY? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL-SPANS-DISJOINT? ;

: _RTE-CPV-ITEM-TEXT?  ( -- flag )
    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-U @
        _RTE-CONTROL-TEXT? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-A @
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-U @
        _RTE-CONTROL-TEXT? ;

: _RTE-CPV-ID?  ( -- flag )
    _RTE-CPV-COUNT @ 0= IF
        _RTE-CPV-ITEM @ _RTE-CONTROL.ID @ DUP _RTE-CPV-FIRST-ID !
        DUP _RTE-CPV-PRIOR-ID !
        _RTE-CPV-LAST-ID !
        -1 EXIT
    THEN
    _RTE-CPV-PRIOR-ID @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.ID @ <> IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.ID @ DUP _RTE-CPV-PRIOR-ID !
    _RTE-CPV-LAST-ID !
    -1 ;

: _RTE-CPV-PARENT-RECORD?  ( -- flag )
    \ Contiguous identities make the already-validated parent an O(1)
    \ lookup at ITEMS-A + (parent - FIRST-ID) * CONTROL-SIZE.
    _RTE-CPV-ITEM @ _RTE-CONTROL.PARENT @ DUP 0= IF DROP 0 EXIT THEN
    DUP _RTE-CPV-PARENT-ID !
    DUP _RTE-CPV-ROOT-ID @ U< IF DROP 0 EXIT THEN
    _RTE-CPV-FIRST-ID @ U< IF 0 EXIT THEN
    _RTE-CPV-PARENT-ID @ _RTE-CPV-FIRST-ID @ -
        DUP _RTE-CPV-PARENT-INDEX !
    _RTE-CPV-COUNT @ U< 0= IF 0 EXIT THEN
    _RTE-CPV-PARENT-INDEX @ RTE-CONTROL-SIZE _RTE-UMUL? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-CPV-PARENT-OFFSET !
    _RTE-CPV-ITEMS-A @ SWAP _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-CPV-PARENT-RECORD !
    _RTE-CONTROL.ID @ _RTE-CPV-PARENT-ID @ = ;

: _RTE-CPV-GROUP-RESET  ( -- )
    -1 _RTE-CPV-GROUP-ACTIVE !
    _RTE-CPV-PARENT-ID @ _RTE-CPV-GROUP-PARENT !
    _RTE-CPV-ITEM @ _RTE-CONTROL.ORDER @ _RTE-CPV-PRIOR-ORDER !
    0 _RTE-CPV-OPEN-SEEN !
    0 _RTE-CPV-SELECTED-SEEN ! ;

: _RTE-CPV-GROUP-ORDER?  ( -- flag )
    _RTE-CPV-GROUP-ACTIVE @ 0= IF _RTE-CPV-GROUP-RESET -1 EXIT THEN
    _RTE-CPV-PARENT-ID @ _RTE-CPV-GROUP-PARENT @ U< IF 0 EXIT THEN
    _RTE-CPV-PARENT-ID @ _RTE-CPV-GROUP-PARENT @ <> IF
        _RTE-CPV-GROUP-RESET -1 EXIT
    THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.ORDER @
        _RTE-CPV-PRIOR-ORDER @ U> 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.ORDER @ _RTE-CPV-PRIOR-ORDER !
    -1 ;

: _RTE-CPV-GROUP-STATE?  ( -- flag )
    _RTE-CPV-PHASE @ _RTE-CPV-PHASE-MENU = IF
        _RTE-CPV-ITEM @ _RTE-CONTROL.STATE @ RTE-CONTROL-OPEN AND IF
            _RTE-CPV-OPEN-SEEN @ IF 0 EXIT THEN
            -1 _RTE-CPV-OPEN-SEEN !
        THEN
        _RTE-CPV-ITEM @ _RTE-CONTROL.STATE @
            RTE-CONTROL-SELECTED AND IF
            _RTE-CPV-SELECTED-SEEN @ IF 0 EXIT THEN
            -1 _RTE-CPV-SELECTED-SEEN !
        THEN
        -1 EXIT
    THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.STATE @ RTE-CONTROL-SELECTED AND IF
        _RTE-CPV-SELECTED-SEEN @ IF 0 EXIT THEN
        -1 _RTE-CPV-SELECTED-SEEN !
    THEN
    -1 ;

: _RTE-CPV-GROUP?  ( -- flag )
    _RTE-CPV-GROUP-ORDER? 0= IF 0 EXIT THEN
    _RTE-CPV-GROUP-STATE? ;

: _RTE-CPV-PHASE-MENU?  ( -- flag )
    _RTE-CPV-PHASE @ _RTE-CPV-PHASE-ROW = IF 0 EXIT THEN
    _RTE-CPV-PHASE @ _RTE-CPV-PHASE-MENUBAR = IF
        _RTE-CPV-PHASE-MENU _RTE-CPV-PHASE !
        0 _RTE-CPV-GROUP-ACTIVE !
    THEN
    _RTE-CPV-PARENT-RECORD? 0= IF 0 EXIT THEN
    _RTE-CPV-PARENT-RECORD @ _RTE-CONTROL.KIND @
        RTE-CONTROL-MENU-BAR <> IF 0 EXIT THEN
    _RTE-CPV-GROUP? ;

: _RTE-CPV-PHASE-ROW?  ( -- flag )
    _RTE-CPV-PHASE @ _RTE-CPV-PHASE-MENUBAR = IF 0 EXIT THEN
    _RTE-CPV-PHASE @ _RTE-CPV-PHASE-MENU = IF
        _RTE-CPV-PHASE-ROW _RTE-CPV-PHASE !
        0 _RTE-CPV-GROUP-ACTIVE !
    THEN
    _RTE-CPV-PARENT-RECORD? 0= IF 0 EXIT THEN
    _RTE-CPV-PARENT-RECORD @ _RTE-CONTROL.KIND @
        RTE-CONTROL-MENU <> IF 0 EXIT THEN
    _RTE-CPV-GROUP? ;

: _RTE-CPV-PHASE-TAB?  ( -- flag )
    _RTE-CPV-PHASE @ DUP _RTE-CPV-PHASE-TABSET =
    SWAP _RTE-CPV-PHASE-TAB = OR 0= IF 0 EXIT THEN
    _RTE-CPV-PHASE @ _RTE-CPV-PHASE-TABSET = IF
        _RTE-CPV-PHASE-TAB _RTE-CPV-PHASE !
        0 _RTE-CPV-GROUP-ACTIVE !
    THEN
    _RTE-CPV-PARENT-RECORD? 0= IF 0 EXIT THEN
    _RTE-CPV-PARENT-RECORD @ _RTE-CONTROL.KIND @
        RTE-CONTROL-TABSET <> IF 0 EXIT THEN
    _RTE-CPV-GROUP? ;

: _RTE-CPV-ROOT-START  ( phase -- )
    _RTE-CPV-PHASE !
    _RTE-CPV-ITEM @ _RTE-CONTROL.ID @ _RTE-CPV-ROOT-ID !
    0 _RTE-CPV-GROUP-ACTIVE !
    0 _RTE-CPV-GROUP-PARENT !
    0 _RTE-CPV-PRIOR-ORDER !
    0 _RTE-CPV-OPEN-SEEN !
    0 _RTE-CPV-SELECTED-SEEN ! ;

\ One plan may concatenate complete per-document menu forests and standalone
\ semantic collection roots.  A TABSET may be followed by its ordered TAB
\ children before the next root.  Object IDs remain globally contiguous,
\ while each new root resets only root-local order and selection state and
\ becomes the lower bound for later parents.  Thus no descendant can attach
\ back across an intervening root.
: _RTE-CPV-GRAPH?  ( -- flag )
    _RTE-CPV-ID? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.KIND @
        _RTE-CONTROL-ROOT-KIND? IF
        _RTE-CPV-ITEM @ _RTE-CONTROL.PARENT @ IF 0 EXIT THEN
        _RTE-CPV-ROOTS @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
            _RTE-CPV-ROOTS !
        _RTE-CPV-ITEM @ _RTE-CONTROL.KIND @
            RTE-CONTROL-MENU-BAR = IF
            _RTE-CPV-PHASE-MENUBAR
        ELSE
            _RTE-CPV-ITEM @ _RTE-CONTROL.KIND @
                RTE-CONTROL-TABSET = IF
                _RTE-CPV-PHASE-TABSET
            ELSE
                _RTE-CPV-PHASE-STANDALONE
            THEN
        THEN
        _RTE-CPV-ROOT-START
        -1 EXIT
    THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.KIND @ RTE-CONTROL-MENU = IF
        _RTE-CPV-PHASE-MENU? EXIT
    THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.KIND @ RTE-CONTROL-TAB = IF
        _RTE-CPV-PHASE-TAB? EXIT
    THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.KIND @ DUP
        RTE-CONTROL-MENU-ITEM =
    SWAP RTE-CONTROL-MENU-SEPARATOR = OR IF
        _RTE-CPV-PHASE-ROW? EXIT
    THEN
    0 ;

: _RTE-CPV-ITEM-AGGREGATE?  ( -- flag )
    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-U @
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-U @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.CONTENT-UTF8 @
        _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-CPV-ITEM-UTF8 !
    _RTE-CPV-UTF8-BYTES @ SWAP _RTE-UADD? 0= IF DROP 0 EXIT THEN
    _RTE-CPV-UTF8-BYTES !

    _RTE-CPV-ITEM @ _RTE-CONTROL.LABEL-U @
    _RTE-CPV-ITEM @ _RTE-CONTROL.SHORTCUT-U @ _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN
    _RTE-CPV-ITEM @ _RTE-CONTROL.CONTENT-U @
        _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-CPV-ITEM-BYTES !
    _RTE-CPV-BYTES @ SWAP _RTE-UADD? 0= IF DROP 0 EXIT THEN
    _RTE-CPV-BYTES !
    _RTE-CPV-ITEM-BYTES @ 7 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    7 INVERT AND DUP _RTE-CPV-ITEM-ALIGNED !
    _RTE-CPV-ALIGNED-BYTES @ SWAP _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTE-CPV-ALIGNED-BYTES !
    _RTE-CPV-ITEM-BYTES @ _RTE-CPV-MAX-ITEM-BYTES @ MAX
        _RTE-CPV-MAX-ITEM-BYTES !

    _RTE-CPV-ITEM @ _RTE-CONTROL.KIND @
        _RTE-CONTROL-COLLECTION-KIND? IF
        _RTE-CPV-COLLECTIONS @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
        _RTE-CPV-COLLECTIONS !
    THEN
    _RTE-CPV-CONTENT-ITEMS @
    _RTE-CPV-ITEM @ _RTE-CONTROL.CONTENT-ITEMS @
        _RTE-UADD? 0= IF DROP 0 EXIT THEN
    _RTE-CPV-CONTENT-ITEMS !
    _RTE-CPV-COUNT @ 1 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    _RTE-CPV-COUNT !
    -1 ;

: _RTE-CPV-ITEM?  ( -- flag )
    _RTE-CPV-ITEM-STRUCTURAL? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM-BYTES-AUTHORITY? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM-TEXT? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM-CORRELATES? 0= IF 0 EXIT THEN
    _RTE-CPV-GRAPH? 0= IF 0 EXIT THEN
    _RTE-CPV-ITEM-AGGREGATE? ;

: _RTE-CONTROL-PLAN-VALID-BODY  ( -- flag )
    _RTE-CPV-HEADER? 0= IF 0 EXIT THEN
    0 _RTE-CPV-FIRST-ID !
    0 _RTE-CPV-PRIOR-ID !
    0 _RTE-CPV-COUNT !
    0 _RTE-CPV-BYTES !
    0 _RTE-CPV-ALIGNED-BYTES !
    0 _RTE-CPV-MAX-ITEM-BYTES !
    0 _RTE-CPV-LAST-ID !
    0 _RTE-CPV-ROOTS !
    0 _RTE-CPV-COLLECTIONS !
    0 _RTE-CPV-CONTENT-ITEMS !
    0 _RTE-CPV-UTF8-BYTES !
    0 _RTE-CPV-ROOT-ID !
    _RTE-CPV-PHASE-MENUBAR _RTE-CPV-PHASE !
    0 _RTE-CPV-GROUP-ACTIVE !
    0 _RTE-CPV-GROUP-PARENT !
    0 _RTE-CPV-PRIOR-ORDER !
    0 _RTE-CPV-OPEN-SEEN !
    0 _RTE-CPV-SELECTED-SEEN !
    0 _RTE-CPV-PARENT-ID !
    0 _RTE-CPV-PARENT-INDEX !
    0 _RTE-CPV-PARENT-OFFSET !
    0 _RTE-CPV-PARENT-RECORD !
    _RTE-CPV-ITEMS-A @ _RTE-CPV-ITEM !
    _RTE-CPV-ITEMS-U @ RTE-CONTROL-SIZE / 0 ?DO
        _RTE-CPV-ITEM? 0= IF 0 UNLOOP EXIT THEN
        RTE-CONTROL-SIZE _RTE-CPV-ITEM +!
    LOOP
    _RTE-CPV-ROOTS @ 0<> ;

: RTE-CONTROL-PLAN-VALID?  ( plan -- flag )
    _RTE-CPV-PLAN !
    0 _RTE-CPV-FACADE !
    _RTE-CONTROL-PLAN-VALID-BODY
    _RTE-CPV-FINISH ;

: RTE-STATUS@  ( facade -- status )
    DUP RTE-VALID? 0= IF DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.STATUS-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-UPDATE-STATE@  ( facade -- update-state status )
    DUP RTE-VALID? 0= IF
        DROP RTE-UPDATE-IDLE RTE-S-INVALID EXIT
    THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.UPDATE-STATE-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF
        2DROP RTE-UPDATE-IDLE RTE-S-INVALID EXIT
    THEN
    OVER RTE-UPDATE-STATE-VALID? 0= IF
        2DROP RTE-UPDATE-IDLE RTE-S-INVALID
    THEN ;

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

: RTE-OWNER-OPEN  ( owner generation region-q resource-q object-q series-q resource-bytes utf8-bytes sample-slots facade -- status )
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
    ( owner generation region x y cols rows clip-x clip-y clip-cols clip-rows z flags facade -- status )
    DUP RTE-VALID? 0= IF
        2DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP
        RTE-S-INVALID EXIT
    THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.REGION-DEF-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

\ =====================================================================
\  One-pass hybrid CONTROL / INSTRUMENT / residual GLYPH-RUN admission
\ =====================================================================
\
\ The wrapper contains only borrowed spans.  Authority is proved for the
\ complete graph before either item bank, the reference bank, or text bytes
\ are dereferenced.  Each present family is then traversed exactly once and
\ reduced to the fixed summary passed to the provider.

VARIABLE _RTE-HPV-HYBRID
VARIABLE _RTE-HPV-ADMISSION
VARIABLE _RTE-HPV-FACADE
VARIABLE _RTE-HPV-CONTROL
VARIABLE _RTE-HPV-GLYPH
VARIABLE _RTE-HPV-INSTRUMENT
VARIABLE _RTE-HPV-CONTROL-ITEMS-A
VARIABLE _RTE-HPV-CONTROL-ITEMS-U
VARIABLE _RTE-HPV-GLYPH-ITEMS-A
VARIABLE _RTE-HPV-GLYPH-ITEMS-U
VARIABLE _RTE-HPV-REFS-A
VARIABLE _RTE-HPV-REFS-U
VARIABLE _RTE-HPV-TEXT-A
VARIABLE _RTE-HPV-TEXT-U
VARIABLE _RTE-HPV-CONTROL-BYTES-A
VARIABLE _RTE-HPV-CONTROL-BYTES-U
VARIABLE _RTE-HPV-INSTRUMENT-BYTES-A
VARIABLE _RTE-HPV-INSTRUMENT-BYTES-U
VARIABLE _RTE-HPV-REF
VARIABLE _RTE-HPV-TEXT-OFF
VARIABLE _RTE-HPV-TEXT-END
VARIABLE _RTE-HPV-ITEM-TEXT
VARIABLE _RTE-HPV-ITEM-ALIGNED
VARIABLE _RTE-HPV-GLYPH-COUNT
VARIABLE _RTE-HPV-GLYPH-TEXT
VARIABLE _RTE-HPV-GLYPH-ALIGNED
VARIABLE _RTE-HPV-GLYPH-MAX
VARIABLE _RTE-HPV-GLYPH-FIRST
VARIABLE _RTE-HPV-GLYPH-LAST
VARIABLE _RTE-HPV-INSTRUMENT-LAST
VARIABLE _RTE-HPV-INSTRUMENT-FIRST-REGION
\ The checked summary crosses the neutral/provider callback boundary, whose
\ fixed-record ABI requires cell alignment.
CREATE _RTE-HPV-SUMMARY-MEM RTE-HYBRID-ADMISSION-SIZE 7 + ALLOT
_RTE-HPV-SUMMARY-MEM 7 + -8 AND CONSTANT _RTE-HPV-SUMMARY
CREATE _RTE-HPV-OWNED-END

: _RTE-HPV-OWNED-DISJOINT?  ( a u -- flag )
    2DUP _RTE-HPV-OWNED-START
        _RTE-HPV-OWNED-END _RTE-HPV-OWNED-START -
        MSPAN-OVERLAP? 0= NIP NIP ;

: _RTE-HPV-FIXED-RECORD?  ( a u facade -- flag )
    >R
    2DUP _RTE-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    2DUP _RTE-HPV-OWNED-DISJOINT? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R> RTE-STORAGE-DISJOINT? ;

: _RTE-HPV-FIXED-BYTE?  ( a u facade -- flag )
    >R
    2DUP _RTE-CONTROL-TEXT-SPAN? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP 0= IF 2DROP R> DROP -1 EXIT THEN
    2DUP _RTE-HPV-OWNED-DISJOINT? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R> RTE-STORAGE-DISJOINT? ;

: _RTE-HPV-FIXED-DISJOINT?  ( a1 u1 a2 u2 -- flag )
    MSPAN-OVERLAP? 0= ;

: _RTE-HPV-CONTROL-PLAN-SPAN  ( hybrid -- a u )
    _RTE-HP.CONTROL-PLAN @ RTE-CONTROL-PLAN-SIZE ;

: _RTE-HPV-CONTROL-ITEMS-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.CONTROL-PLAN @ _RTE-CP.ITEMS-A @
    SWAP _RTE-HP.CONTROL-PLAN @ _RTE-CP.ITEMS-U @ ;

: _RTE-HPV-CONTROL-BYTES-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.CONTROL-BYTES-A @
    SWAP _RTE-HP.CONTROL-BYTES-U @ ;

: _RTE-HPV-INSTRUMENT-PLAN-SPAN  ( hybrid -- a u )
    _RTE-HP.INSTRUMENT-PLAN @ RTE-INSTRUMENT-PLAN-SIZE ;

: _RTE-HPV-INSTRUMENT-REGIONS-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.INSTRUMENT-PLAN @ _RTE-IP.REGIONS-A @
    SWAP _RTE-HP.INSTRUMENT-PLAN @ _RTE-IP.REGIONS-U @ ;

: _RTE-HPV-INSTRUMENT-ITEMS-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.INSTRUMENT-PLAN @ _RTE-IP.ITEMS-A @
    SWAP _RTE-HP.INSTRUMENT-PLAN @ _RTE-IP.ITEMS-U @ ;

: _RTE-HPV-INSTRUMENT-BYTES-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.INSTRUMENT-BYTES-A @
    SWAP _RTE-HP.INSTRUMENT-BYTES-U @ ;

: _RTE-HPV-GLYPH-PLAN-SPAN  ( hybrid -- a u )
    _RTE-HP.GLYPH-PLAN @ RTE-GLYPH-RUN-PLAN-SIZE ;

: _RTE-HPV-GLYPH-ITEMS-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.GLYPH-PLAN @ _RTE-LP.ITEMS-A @
    SWAP _RTE-HP.GLYPH-PLAN @ _RTE-LP.ITEMS-U @ ;

: _RTE-HPV-GLYPH-REFS-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.GLYPH-REFS-A @
    SWAP _RTE-HP.GLYPH-REFS-U @ ;

: _RTE-HPV-GLYPH-TEXT-SPAN  ( hybrid -- a u )
    DUP _RTE-HP.GLYPH-TEXT-A @
    SWAP _RTE-HP.GLYPH-TEXT-U @ ;

: _RTE-HPV-FIXED-PLAN?  ( plan -- flag )
    DUP _RTE-LP.OWNER @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.GENERATION @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.SURFACE-COLS @ DUP 0= IF
        2DROP 0 EXIT
    THEN _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.SURFACE-ROWS @ DUP 0= IF
        2DROP 0 EXIT
    THEN _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-ID @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-X @ _RTE-I32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-Y @ _RTE-I32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-COLS @ DUP 0= IF
        2DROP 0 EXIT
    THEN _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-ROWS @ DUP 0= IF
        2DROP 0 EXIT
    THEN _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.CLIP-X @ _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.CLIP-Y @ _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.CLIP-COLS @ _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.CLIP-ROWS @ _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-Z @ _RTE-I32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-LP.REGION-FLAGS @
        _RTE-REGION-FLAG-MASK INVERT AND IF DROP 0 EXIT THEN
    DUP _RTE-LP.RESERVED @ IF DROP 0 EXIT THEN
    DROP -1 ;

: _RTE-HPV-FIXED-INSTRUMENT-PLAN?  ( plan -- flag )
    DUP _RTE-IP.OWNER @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-IP.GENERATION @ 0= IF DROP 0 EXIT THEN
    DUP _RTE-IP.SURFACE-COLS @ DUP 0= IF 2DROP 0 EXIT THEN
        _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-IP.SURFACE-ROWS @ DUP 0= IF 2DROP 0 EXIT THEN
        _RTE-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTE-IP.REGIONS-U @ DUP 0= IF 2DROP 0 EXIT THEN
        RTE-INSTRUMENT-REGION-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RTE-IP.ITEMS-U @ DUP 0= IF 2DROP 0 EXIT THEN
        RTE-INSTRUMENT-SIZE MOD IF DROP 0 EXIT THEN
    _RTE-IP.RESERVED @ 0= ;

: _RTE-HPV-FIXED-WRAPPER?  ( hybrid facade -- flag )
    OVER RTE-HYBRID-PLAN-SIZE 2 PICK
        _RTE-HPV-FIXED-RECORD? 0= IF 2DROP 0 EXIT THEN
    OVER _RTE-HP.ATTEMPT @ 0= IF 2DROP 0 EXIT THEN
    OVER _RTE-HP.SOURCE-GENERATION @ 0= IF 2DROP 0 EXIT THEN
    OVER _RTE-HP.SURFACE-GENERATION @ 0= IF 2DROP 0 EXIT THEN
    OVER _RTE-HP.RESERVED @ IF 2DROP 0 EXIT THEN
    OVER _RTE-HP.CONTROL-PLAN @
    2 PICK _RTE-HP.GLYPH-PLAN @ OR
    2 PICK _RTE-HP.INSTRUMENT-PLAN @ OR 0= IF 2DROP 0 EXIT THEN
    OVER _RTE-HP.CONTROL-PLAN @ 0= IF
        OVER _RTE-HP.CONTROL-BYTES-A @
        2 PICK _RTE-HP.CONTROL-BYTES-U @ OR IF 2DROP 0 EXIT THEN
    THEN
    OVER _RTE-HP.GLYPH-PLAN @ 0= IF
        OVER _RTE-HP.GLYPH-REFS-A @
        2 PICK _RTE-HP.GLYPH-REFS-U @ OR
        2 PICK _RTE-HP.GLYPH-TEXT-A @ OR
        2 PICK _RTE-HP.GLYPH-TEXT-U @ OR IF 2DROP 0 EXIT THEN
    THEN
    OVER _RTE-HP.INSTRUMENT-PLAN @ 0= IF
        OVER _RTE-HP.INSTRUMENT-BYTES-A @
        2 PICK _RTE-HP.INSTRUMENT-BYTES-U @ OR IF 2DROP 0 EXIT THEN
    THEN
    2DROP -1 ;

: _RTE-HPV-FIXED-CONTROL?  ( hybrid facade -- flag )
    >R
    DUP _RTE-HP.CONTROL-PLAN @ 0= IF DROP R> DROP -1 EXIT THEN
    DUP _RTE-HPV-CONTROL-PLAN-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.CONTROL-PLAN @
        _RTE-HPV-FIXED-PLAN? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-ITEMS-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.CONTROL-PLAN @ _RTE-CP.ITEMS-U @
        RTE-CONTROL-SIZE MOD IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-BYTES-SPAN R@
        _RTE-HPV-FIXED-BYTE? 0= IF DROP R> DROP 0 EXIT THEN

    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-CONTROL-PLAN-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-CONTROL-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-PLAN-SPAN
    2 PICK _RTE-HPV-CONTROL-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.CONTROL-BYTES-U @ IF
        DUP RTE-HYBRID-PLAN-SIZE
        2 PICK _RTE-HPV-CONTROL-BYTES-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-CONTROL-PLAN-SPAN
        2 PICK _RTE-HPV-CONTROL-BYTES-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-CONTROL-ITEMS-SPAN
        2 PICK _RTE-HPV-CONTROL-BYTES-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    THEN
    DROP R> DROP -1 ;

: _RTE-HPV-FIXED-INSTRUMENT?  ( hybrid facade -- flag )
    >R
    DUP _RTE-HP.INSTRUMENT-PLAN @ 0= IF DROP R> DROP -1 EXIT THEN
    DUP _RTE-HPV-INSTRUMENT-PLAN-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.INSTRUMENT-PLAN @
        _RTE-HPV-FIXED-INSTRUMENT-PLAN? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-INSTRUMENT-REGIONS-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-INSTRUMENT-ITEMS-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-INSTRUMENT-BYTES-SPAN R@
        _RTE-HPV-FIXED-BYTE? 0= IF DROP R> DROP 0 EXIT THEN

    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-INSTRUMENT-PLAN-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-INSTRUMENT-REGIONS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-INSTRUMENT-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-INSTRUMENT-PLAN-SPAN
    2 PICK _RTE-HPV-INSTRUMENT-REGIONS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-INSTRUMENT-PLAN-SPAN
    2 PICK _RTE-HPV-INSTRUMENT-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-INSTRUMENT-REGIONS-SPAN
    2 PICK _RTE-HPV-INSTRUMENT-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.INSTRUMENT-BYTES-U @ IF
        DUP RTE-HYBRID-PLAN-SIZE
        2 PICK _RTE-HPV-INSTRUMENT-BYTES-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-INSTRUMENT-PLAN-SPAN
        2 PICK _RTE-HPV-INSTRUMENT-BYTES-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-INSTRUMENT-REGIONS-SPAN
        2 PICK _RTE-HPV-INSTRUMENT-BYTES-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-INSTRUMENT-ITEMS-SPAN
        2 PICK _RTE-HPV-INSTRUMENT-BYTES-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    THEN
    DROP R> DROP -1 ;

: _RTE-HPV-FIXED-GLYPH?  ( hybrid facade -- flag )
    >R
    DUP _RTE-HP.GLYPH-PLAN @ 0= IF DROP R> DROP -1 EXIT THEN
    DUP _RTE-HPV-GLYPH-PLAN-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.GLYPH-PLAN @
        _RTE-HPV-FIXED-PLAN? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-GLYPH-ITEMS-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.GLYPH-PLAN @ _RTE-LP.ITEMS-U @
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE MOD IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-GLYPH-REFS-SPAN R@
        _RTE-HPV-FIXED-RECORD? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.GLYPH-PLAN @ _RTE-LP.ITEMS-U @
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE /
        DUP _RTE-U32? 0= IF 2DROP R> DROP 0 EXIT THEN
    RTE-HYBRID-TEXT-REF-SIZE _RTE-UMUL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _RTE-HP.GLYPH-REFS-U @ <> IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-GLYPH-TEXT-SPAN R@
        _RTE-HPV-FIXED-BYTE? 0= IF DROP R> DROP 0 EXIT THEN

    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-GLYPH-PLAN-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-GLYPH-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP RTE-HYBRID-PLAN-SIZE
    2 PICK _RTE-HPV-GLYPH-REFS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-GLYPH-PLAN-SPAN
    2 PICK _RTE-HPV-GLYPH-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-GLYPH-PLAN-SPAN
    2 PICK _RTE-HPV-GLYPH-REFS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HPV-GLYPH-ITEMS-SPAN
    2 PICK _RTE-HPV-GLYPH-REFS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.GLYPH-TEXT-U @ IF
        DUP RTE-HYBRID-PLAN-SIZE
        2 PICK _RTE-HPV-GLYPH-TEXT-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-GLYPH-PLAN-SPAN
        2 PICK _RTE-HPV-GLYPH-TEXT-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-GLYPH-ITEMS-SPAN
        2 PICK _RTE-HPV-GLYPH-TEXT-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-GLYPH-REFS-SPAN
        2 PICK _RTE-HPV-GLYPH-TEXT-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    THEN
    DROP R> DROP -1 ;

: _RTE-HPV-FIXED-HEADERS-SAME?  ( control-plan glyph-plan -- flag )
    >R
    DUP _RTE-CP.OWNER @ R@ _RTE-LP.OWNER @ =
    OVER _RTE-CP.GENERATION @ R@ _RTE-LP.GENERATION @ = AND
    OVER _RTE-CP.SURFACE-COLS @ R@ _RTE-LP.SURFACE-COLS @ = AND
    OVER _RTE-CP.SURFACE-ROWS @ R@ _RTE-LP.SURFACE-ROWS @ = AND
    OVER _RTE-CP.REGION-ID @ R@ _RTE-LP.REGION-ID @ = AND
    OVER _RTE-CP.REGION-X @ R@ _RTE-LP.REGION-X @ = AND
    OVER _RTE-CP.REGION-Y @ R@ _RTE-LP.REGION-Y @ = AND
    OVER _RTE-CP.REGION-COLS @ R@ _RTE-LP.REGION-COLS @ = AND
    OVER _RTE-CP.REGION-ROWS @ R@ _RTE-LP.REGION-ROWS @ = AND
    OVER _RTE-CP.CLIP-X @ R@ _RTE-LP.CLIP-X @ = AND
    OVER _RTE-CP.CLIP-Y @ R@ _RTE-LP.CLIP-Y @ = AND
    OVER _RTE-CP.CLIP-COLS @ R@ _RTE-LP.CLIP-COLS @ = AND
    OVER _RTE-CP.CLIP-ROWS @ R@ _RTE-LP.CLIP-ROWS @ = AND
    OVER _RTE-CP.REGION-Z @ R@ _RTE-LP.REGION-Z @ = AND
    OVER _RTE-CP.REGION-FLAGS @ R@ _RTE-LP.REGION-FLAGS @ = AND
    NIP R> DROP ;

: _RTE-HPV-FIXED-INSTRUMENT-HEADER-SAME?  ( base-plan instrument-plan -- flag )
    >R
    DUP _RTE-LP.OWNER @ R@ _RTE-IP.OWNER @ =
    OVER _RTE-LP.GENERATION @ R@ _RTE-IP.GENERATION @ = AND
    OVER _RTE-LP.SURFACE-COLS @ R@ _RTE-IP.SURFACE-COLS @ = AND
    OVER _RTE-LP.SURFACE-ROWS @ R@ _RTE-IP.SURFACE-ROWS @ = AND
    NIP R> DROP ;

: _RTE-HPV-FIXED-CROSS?  ( hybrid -- flag )
    DUP _RTE-HP.CONTROL-PLAN @ 0=
    OVER _RTE-HP.GLYPH-PLAN @ 0= OR IF DROP -1 EXIT THEN
    DUP _RTE-HPV-CONTROL-PLAN-SPAN
    2 PICK _RTE-HPV-GLYPH-PLAN-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-PLAN-SPAN
    2 PICK _RTE-HPV-GLYPH-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-PLAN-SPAN
    2 PICK _RTE-HPV-GLYPH-REFS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-ITEMS-SPAN
    2 PICK _RTE-HPV-GLYPH-PLAN-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-ITEMS-SPAN
    2 PICK _RTE-HPV-GLYPH-ITEMS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-HPV-CONTROL-ITEMS-SPAN
    2 PICK _RTE-HPV-GLYPH-REFS-SPAN
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _RTE-HP.GLYPH-TEXT-U @ IF
        DUP _RTE-HPV-CONTROL-PLAN-SPAN
        2 PICK _RTE-HPV-GLYPH-TEXT-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
        DUP _RTE-HPV-CONTROL-ITEMS-SPAN
        2 PICK _RTE-HPV-GLYPH-TEXT-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
    THEN
    DUP _RTE-HP.CONTROL-BYTES-U @ IF
        DUP _RTE-HPV-CONTROL-BYTES-SPAN
        2 PICK _RTE-HPV-GLYPH-PLAN-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
        DUP _RTE-HPV-CONTROL-BYTES-SPAN
        2 PICK _RTE-HPV-GLYPH-ITEMS-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
        DUP _RTE-HPV-CONTROL-BYTES-SPAN
        2 PICK _RTE-HPV-GLYPH-REFS-SPAN
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
        DUP _RTE-HP.GLYPH-TEXT-U @ IF
            DUP _RTE-HPV-CONTROL-BYTES-SPAN
            2 PICK _RTE-HPV-GLYPH-TEXT-SPAN
                _RTE-HPV-FIXED-DISJOINT? 0= IF DROP 0 EXIT THEN
        THEN
    THEN
    DUP _RTE-HP.CONTROL-PLAN @
    OVER _RTE-HP.GLYPH-PLAN @ _RTE-HPV-FIXED-HEADERS-SAME? 0= IF
        DROP 0 EXIT
    THEN
    DROP -1 ;

: _RTE-HPV-INSTRUMENT-WITH-SPAN?  ( hybrid a u -- flag )
    2 PICK _RTE-HPV-INSTRUMENT-PLAN-SPAN
    3 PICK 3 PICK
        _RTE-HPV-FIXED-DISJOINT? 0= IF
        2DROP DROP 0 EXIT
    THEN
    2 PICK _RTE-HPV-INSTRUMENT-REGIONS-SPAN
    3 PICK 3 PICK
        _RTE-HPV-FIXED-DISJOINT? 0= IF
        2DROP DROP 0 EXIT
    THEN
    2 PICK _RTE-HPV-INSTRUMENT-ITEMS-SPAN
    3 PICK 3 PICK
        _RTE-HPV-FIXED-DISJOINT? 0= IF
        2DROP DROP 0 EXIT
    THEN
    2 PICK _RTE-HP.INSTRUMENT-BYTES-U @ IF
        2 PICK _RTE-HPV-INSTRUMENT-BYTES-SPAN
        3 PICK 3 PICK
            _RTE-HPV-FIXED-DISJOINT? 0= IF
            2DROP DROP 0 EXIT
        THEN
    THEN
    2DROP DROP -1 ;

: _RTE-HPV-FIXED-INSTRUMENT-CROSS?  ( hybrid -- flag )
    DUP _RTE-HP.INSTRUMENT-PLAN @ 0= IF DROP -1 EXIT THEN
    DUP _RTE-HP.CONTROL-PLAN @ IF
        DUP DUP _RTE-HPV-CONTROL-PLAN-SPAN
            _RTE-HPV-INSTRUMENT-WITH-SPAN? 0= IF DROP 0 EXIT THEN
        DUP DUP _RTE-HPV-CONTROL-ITEMS-SPAN
            _RTE-HPV-INSTRUMENT-WITH-SPAN? 0= IF DROP 0 EXIT THEN
        DUP _RTE-HP.CONTROL-BYTES-U @ IF
            DUP DUP _RTE-HPV-CONTROL-BYTES-SPAN
                _RTE-HPV-INSTRUMENT-WITH-SPAN? 0= IF DROP 0 EXIT THEN
        THEN
        DUP _RTE-HP.CONTROL-PLAN @
        OVER _RTE-HP.INSTRUMENT-PLAN @
            _RTE-HPV-FIXED-INSTRUMENT-HEADER-SAME? 0= IF DROP 0 EXIT THEN
    THEN
    DUP _RTE-HP.GLYPH-PLAN @ IF
        DUP DUP _RTE-HPV-GLYPH-PLAN-SPAN
            _RTE-HPV-INSTRUMENT-WITH-SPAN? 0= IF DROP 0 EXIT THEN
        DUP DUP _RTE-HPV-GLYPH-ITEMS-SPAN
            _RTE-HPV-INSTRUMENT-WITH-SPAN? 0= IF DROP 0 EXIT THEN
        DUP DUP _RTE-HPV-GLYPH-REFS-SPAN
            _RTE-HPV-INSTRUMENT-WITH-SPAN? 0= IF DROP 0 EXIT THEN
        DUP _RTE-HP.GLYPH-TEXT-U @ IF
            DUP DUP _RTE-HPV-GLYPH-TEXT-SPAN
                _RTE-HPV-INSTRUMENT-WITH-SPAN? 0= IF DROP 0 EXIT THEN
        THEN
        DUP _RTE-HP.GLYPH-PLAN @
        OVER _RTE-HP.INSTRUMENT-PLAN @
            _RTE-HPV-FIXED-INSTRUMENT-HEADER-SAME? 0= IF DROP 0 EXIT THEN
    THEN
    DROP -1 ;

: _RTE-HPV-FIXED-AUTHORITY?  ( hybrid facade -- flag )
    2DUP _RTE-HPV-FIXED-WRAPPER? 0= IF 2DROP 0 EXIT THEN
    _RTE-HPV-OWNED-START _RTE-HPV-OWNED-END _RTE-HPV-OWNED-START -
    2 PICK RTE-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP _RTE-HPV-FIXED-CONTROL? 0= IF 2DROP 0 EXIT THEN
    2DUP _RTE-HPV-FIXED-GLYPH? 0= IF 2DROP 0 EXIT THEN
    2DUP _RTE-HPV-FIXED-INSTRUMENT? 0= IF 2DROP 0 EXIT THEN
    OVER _RTE-HPV-FIXED-CROSS? 0= IF 2DROP 0 EXIT THEN
    OVER _RTE-HPV-FIXED-INSTRUMENT-CROSS? 0= IF 2DROP 0 EXIT THEN
    2DROP -1 ;

\ The admitted summary is caller output, so prove its authority before any
\ engine scratch or caller byte is written.  The complete source graph has
\ already been fixed-authority checked, making these span reads safe.  This
\ remains a fixed stack-only proof: it never revisits an item or reference.
: _RTE-HPV-ADMISSION-GRAPH-DISJOINT?  ( hybrid admission -- flag )
    >R
    DUP RTE-HYBRID-PLAN-SIZE
    R@ RTE-HYBRID-ADMISSION-SIZE
        _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RTE-HP.CONTROL-PLAN @ IF
        DUP _RTE-HPV-CONTROL-PLAN-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-CONTROL-ITEMS-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HP.CONTROL-BYTES-U @ IF
            DUP _RTE-HPV-CONTROL-BYTES-SPAN
            R@ RTE-HYBRID-ADMISSION-SIZE
                _RTE-HPV-FIXED-DISJOINT? 0= IF
                    DROP R> DROP 0 EXIT
                THEN
        THEN
    THEN
    DUP _RTE-HP.GLYPH-PLAN @ IF
        DUP _RTE-HPV-GLYPH-PLAN-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-GLYPH-ITEMS-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-GLYPH-REFS-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HP.GLYPH-TEXT-U @ IF
            DUP _RTE-HPV-GLYPH-TEXT-SPAN
            R@ RTE-HYBRID-ADMISSION-SIZE
                _RTE-HPV-FIXED-DISJOINT? 0= IF
                    DROP R> DROP 0 EXIT
                THEN
        THEN
    THEN
    DUP _RTE-HP.INSTRUMENT-PLAN @ IF
        DUP _RTE-HPV-INSTRUMENT-PLAN-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-INSTRUMENT-REGIONS-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HPV-INSTRUMENT-ITEMS-SPAN
        R@ RTE-HYBRID-ADMISSION-SIZE
            _RTE-HPV-FIXED-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
        DUP _RTE-HP.INSTRUMENT-BYTES-U @ IF
            DUP _RTE-HPV-INSTRUMENT-BYTES-SPAN
            R@ RTE-HYBRID-ADMISSION-SIZE
                _RTE-HPV-FIXED-DISJOINT? 0= IF
                    DROP R> DROP 0 EXIT
                THEN
        THEN
    THEN
    DROP R> DROP -1 ;

: _RTE-HPV-ADMISSION-AUTHORITY?  ( hybrid admission facade -- flag )
    >R
    DUP RTE-HYBRID-ADMISSION-SIZE _RTE-SPAN? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP RTE-HYBRID-ADMISSION-SIZE
        _RTE-HPV-OWNED-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    DUP RTE-HYBRID-ADMISSION-SIZE R@
        RTE-STORAGE-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    _RTE-HPV-ADMISSION-GRAPH-DISJOINT?
    R> DROP ;

: _RTE-HPV-INIT  ( -- )
    _RTE-HPV-HYBRID @ _RTE-HP.CONTROL-PLAN @ _RTE-HPV-CONTROL !
    _RTE-HPV-HYBRID @ _RTE-HP.GLYPH-PLAN @ _RTE-HPV-GLYPH !
    _RTE-HPV-HYBRID @ _RTE-HP.INSTRUMENT-PLAN @ _RTE-HPV-INSTRUMENT !
    _RTE-HPV-HYBRID @ _RTE-HP.GLYPH-REFS-A @ _RTE-HPV-REFS-A !
    _RTE-HPV-HYBRID @ _RTE-HP.GLYPH-REFS-U @ _RTE-HPV-REFS-U !
    _RTE-HPV-HYBRID @ _RTE-HP.GLYPH-TEXT-A @ _RTE-HPV-TEXT-A !
    _RTE-HPV-HYBRID @ _RTE-HP.GLYPH-TEXT-U @ _RTE-HPV-TEXT-U !
    _RTE-HPV-HYBRID @ _RTE-HP.CONTROL-BYTES-A @
        _RTE-HPV-CONTROL-BYTES-A !
    _RTE-HPV-HYBRID @ _RTE-HP.CONTROL-BYTES-U @
        _RTE-HPV-CONTROL-BYTES-U !
    _RTE-HPV-HYBRID @ _RTE-HP.INSTRUMENT-BYTES-A @
        _RTE-HPV-INSTRUMENT-BYTES-A !
    _RTE-HPV-HYBRID @ _RTE-HP.INSTRUMENT-BYTES-U @
        _RTE-HPV-INSTRUMENT-BYTES-U !
    _RTE-HPV-CONTROL @ IF
        _RTE-HPV-CONTROL @ _RTE-CP.ITEMS-A @
            _RTE-HPV-CONTROL-ITEMS-A !
        _RTE-HPV-CONTROL @ _RTE-CP.ITEMS-U @
            _RTE-HPV-CONTROL-ITEMS-U !
    THEN
    _RTE-HPV-GLYPH @ IF
        _RTE-HPV-GLYPH @ _RTE-LP.ITEMS-A @ _RTE-HPV-GLYPH-ITEMS-A !
        _RTE-HPV-GLYPH @ _RTE-LP.ITEMS-U @ _RTE-HPV-GLYPH-ITEMS-U !
        _RTE-HPV-GLYPH-ITEMS-U @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE /
            _RTE-HPV-GLYPH-COUNT !
    THEN ;

: _RTE-HPV-COPY-BASE-HEADER  ( plan -- )
    _RTE-HPV-SUMMARY 120 MOVE ;

: _RTE-HPV-COPY-COMMON-HEADER  ( plan -- )
    _RTE-HPV-SUMMARY 32 MOVE ;

: _RTE-HPV-CONTROL?  ( -- flag )
    _RTE-HPV-CONTROL @ 0= IF -1 EXIT THEN
    _RTE-HPV-CONTROL @ _RTE-CPV-PLAN !
    _RTE-HPV-FACADE @ _RTE-CPV-FACADE !
    -1 _RTE-CPV-FIXED-AUTHORITY !
    _RTE-HPV-CONTROL-BYTES-A @ _RTE-CPV-CONTROL-BYTES-A !
    _RTE-HPV-CONTROL-BYTES-U @ _RTE-CPV-CONTROL-BYTES-U !
    _RTE-CONTROL-PLAN-VALID-BODY 0= IF 0 EXIT THEN
    _RTE-HPV-CONTROL-BYTES-U @ _RTE-CPV-BYTES @ <> IF 0 EXIT THEN
    _RTE-HPV-CONTROL @ _RTE-HPV-COPY-BASE-HEADER
    _RTE-CPV-COUNT @ _RTE-HPV-SUMMARY _RTE-HA.CONTROL-COUNT !
    _RTE-CPV-BYTES @ _RTE-HPV-SUMMARY _RTE-HA.CONTROL-BYTES !
    _RTE-CPV-ALIGNED-BYTES @
        _RTE-HPV-SUMMARY _RTE-HA.CONTROL-ALIGNED !
    _RTE-CPV-MAX-ITEM-BYTES @ _RTE-HPV-SUMMARY _RTE-HA.CONTROL-MAX !
    _RTE-CPV-LAST-ID @ _RTE-HPV-SUMMARY _RTE-HA.CONTROL-LAST !
    _RTE-CPV-COLLECTIONS @
        _RTE-HPV-SUMMARY _RTE-HA.CONTROL-COLLECTIONS !
    _RTE-CPV-CONTENT-ITEMS @
        _RTE-HPV-SUMMARY _RTE-HA.CONTROL-ITEMS !
    _RTE-CPV-UTF8-BYTES @ _RTE-HPV-SUMMARY _RTE-HA.CONTROL-UTF8 !
    0 _RTE-CPV-FINISH DROP
    -1 ;

: _RTE-HPV-INSTRUMENT?  ( -- flag )
    _RTE-HPV-INSTRUMENT @ 0= IF -1 EXIT THEN
    _RTE-HPV-INSTRUMENT @ _RTE-IPV-PLAN !
    -1 _RTE-IPV-FIXED-AUTHORITY !
    _RTE-HPV-INSTRUMENT-BYTES-A @ _RTE-IPV-BYTES-A !
    _RTE-HPV-INSTRUMENT-BYTES-U @ _RTE-IPV-BYTES-U !
    _RTE-INSTRUMENT-PLAN-VALID-BODY 0= IF 0 EXIT THEN
    _RTE-HPV-INSTRUMENT-BYTES-U @ _RTE-IPV-UNIT-BYTES @ <> IF
        0 EXIT
    THEN
    _RTE-HPV-CONTROL @ 0= IF
        _RTE-HPV-INSTRUMENT @ _RTE-HPV-COPY-COMMON-HEADER
    THEN
    _RTE-IPV-REGION-COUNT @
        _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-REGION-COUNT !
    _RTE-IPV-COUNT @ _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-COUNT !
    _RTE-IPV-READOUTS @ _RTE-HPV-SUMMARY _RTE-HA.READOUT-COUNT !
    _RTE-IPV-METERS @ _RTE-HPV-SUMMARY _RTE-HA.METER-COUNT !
    _RTE-IPV-STATUSES @ _RTE-HPV-SUMMARY _RTE-HA.STATUS-COUNT !
    _RTE-IPV-UNIT-BYTES @
        _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-UNIT-BYTES !
    _RTE-IPV-UNIT-ALIGNED @
        _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-UNIT-ALIGNED !
    _RTE-IPV-UNIT-MAX @
        _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-UNIT-MAX !
    _RTE-IPV-FORMATTED-BYTES @
        _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-FORMATTED-BYTES !
    _RTE-IPV-FORMATTED-MAX @
        _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-FORMATTED-MAX !
    _RTE-IPV-LAST-ID @ _RTE-HPV-SUMMARY _RTE-HA.INSTRUMENT-LAST !
    _RTE-IPV-LAST-ID @ _RTE-HPV-INSTRUMENT-LAST !
    _RTE-IPV-FIRST-REGION-ID @ _RTE-HPV-INSTRUMENT-FIRST-REGION !
    0 _RTE-IPV-FINISH DROP
    -1 ;

: _RTE-HPV-GLYPH-ITEM?  ( -- flag )
    _RTE-GLYPH-RUN-PLAN-ITEM? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.ROW @ _RTE-I32? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.COL @ _RTE-I32? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.HEIGHT @ _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.WIDTH @ _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.Z @ _RTE-I32? 0= IF 0 EXIT THEN
    _RTE-LPV-ITEM @ _RTE-LPI.TEXT-CAPACITY @
        _RTE-U32? 0= IF 0 EXIT THEN
    _RTE-HPV-REF @ _RTE-HTR.OFFSET @ DUP _RTE-U32? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-HPV-TEXT-OFF !
    _RTE-HPV-GLYPH-TEXT @ <> IF 0 EXIT THEN
    _RTE-HPV-REF @ _RTE-HTR.BYTES @ DUP _RTE-U32? 0= IF
        DROP 0 EXIT
    THEN DUP _RTE-HPV-ITEM-TEXT !
    _RTE-LPV-ITEM @ _RTE-LPI.TEXT-CAPACITY @ <> IF 0 EXIT THEN
    _RTE-HPV-TEXT-OFF @ _RTE-HPV-ITEM-TEXT @
        _RTE-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTE-HPV-TEXT-END !
    _RTE-HPV-TEXT-U @ U> IF 0 EXIT THEN
    _RTE-HPV-ITEM-TEXT @ IF
        _RTE-HPV-TEXT-A @ _RTE-HPV-TEXT-OFF @
            _RTE-UADD? 0= IF DROP 0 EXIT THEN
        _RTE-HPV-ITEM-TEXT @ _RTE-GLYPH-RUN-TEXT? 0= IF 0 EXIT THEN
    THEN
    _RTE-HPV-TEXT-END @ _RTE-HPV-GLYPH-TEXT !
    _RTE-HPV-ITEM-TEXT @ 7 _RTE-UADD? 0= IF DROP 0 EXIT THEN
    7 INVERT AND DUP _RTE-HPV-ITEM-ALIGNED !
    _RTE-HPV-GLYPH-ALIGNED @ SWAP _RTE-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTE-HPV-GLYPH-ALIGNED !
    _RTE-HPV-ITEM-TEXT @ _RTE-HPV-GLYPH-MAX @ MAX
        _RTE-HPV-GLYPH-MAX !
    _RTE-HPV-GLYPH-LAST @ 0= IF
        _RTE-LPV-ITEM @ _RTE-LPI.OBJECT @ _RTE-HPV-GLYPH-FIRST !
    THEN
    _RTE-LPV-ITEM @ _RTE-LPI.OBJECT @ _RTE-HPV-GLYPH-LAST !
    -1 ;

: _RTE-HPV-GLYPH?  ( -- flag )
    _RTE-HPV-GLYPH @ 0= IF -1 EXIT THEN
    _RTE-HPV-CONTROL @ 0= IF
        _RTE-HPV-GLYPH @ _RTE-HPV-COPY-BASE-HEADER
    THEN
    _RTE-HPV-GLYPH @ _RTE-LPV-PLAN !
    _RTE-GLYPH-RUN-PLAN-HEADER? 0= IF 0 EXIT THEN
    _RTE-HPV-GLYPH-ITEMS-A @ _RTE-LPV-ITEMS-A !
    _RTE-HPV-GLYPH-ITEMS-U @ _RTE-LPV-ITEMS-U !
    0 _RTE-LPV-PRIOR-OBJECT !
    _RTE-HPV-GLYPH-ITEMS-A @ _RTE-LPV-ITEM !
    _RTE-HPV-REFS-A @ _RTE-HPV-REF !
    0 _RTE-HPV-GLYPH-TEXT !
    0 _RTE-HPV-GLYPH-ALIGNED !
    0 _RTE-HPV-GLYPH-MAX !
    0 _RTE-HPV-GLYPH-FIRST !
    0 _RTE-HPV-GLYPH-LAST !
    _RTE-HPV-GLYPH-COUNT @ 0 ?DO
        _RTE-HPV-GLYPH-ITEM? 0= IF 0 UNLOOP EXIT THEN
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTE-LPV-ITEM +!
        RTE-HYBRID-TEXT-REF-SIZE _RTE-HPV-REF +!
    LOOP
    _RTE-HPV-GLYPH-TEXT @ _RTE-HPV-TEXT-U @ <> IF 0 EXIT THEN
    _RTE-HPV-GLYPH-COUNT @ _RTE-HPV-SUMMARY _RTE-HA.GLYPH-COUNT !
    _RTE-HPV-GLYPH-TEXT @ _RTE-HPV-SUMMARY _RTE-HA.GLYPH-TEXT !
    _RTE-HPV-GLYPH-ALIGNED @
        _RTE-HPV-SUMMARY _RTE-HA.GLYPH-ALIGNED !
    _RTE-HPV-GLYPH-MAX @ _RTE-HPV-SUMMARY _RTE-HA.GLYPH-MAX !
    _RTE-HPV-GLYPH-LAST @ _RTE-HPV-SUMMARY _RTE-HA.GLYPH-LAST !
    0 _RTE-GLYPH-RUN-PLAN-VALID-FINISH DROP
    -1 ;

: _RTE-HPV-IDENTITY-RANGES?  ( -- flag )
    _RTE-HPV-INSTRUMENT @ IF
        _RTE-HPV-GLYPH @ IF
            _RTE-HPV-INSTRUMENT-LAST @ _RTE-HPV-GLYPH-FIRST @ U< 0= IF
                0 EXIT
            THEN
        THEN
        _RTE-HPV-SUMMARY _RTE-HA.REGION-ID @ IF
            _RTE-HPV-SUMMARY _RTE-HA.REGION-ID @
            _RTE-HPV-INSTRUMENT-FIRST-REGION @ U< 0= IF 0 EXIT THEN
        THEN
    THEN
    -1 ;

: _RTE-HPV-FINISH  ( status -- status )
    _RTE-HPV-SUMMARY RTE-HYBRID-ADMISSION-SIZE 0 FILL
    0 _RTE-HPV-HYBRID ! 0 _RTE-HPV-ADMISSION !
    0 _RTE-HPV-FACADE !
    0 _RTE-HPV-CONTROL ! 0 _RTE-HPV-GLYPH !
    0 _RTE-HPV-INSTRUMENT !
    0 _RTE-HPV-CONTROL-ITEMS-A ! 0 _RTE-HPV-CONTROL-ITEMS-U !
    0 _RTE-HPV-GLYPH-ITEMS-A ! 0 _RTE-HPV-GLYPH-ITEMS-U !
    0 _RTE-HPV-REFS-A ! 0 _RTE-HPV-REFS-U !
    0 _RTE-HPV-TEXT-A ! 0 _RTE-HPV-TEXT-U !
    0 _RTE-HPV-CONTROL-BYTES-A ! 0 _RTE-HPV-CONTROL-BYTES-U !
    0 _RTE-HPV-INSTRUMENT-BYTES-A !
    0 _RTE-HPV-INSTRUMENT-BYTES-U !
    0 _RTE-HPV-REF ! 0 _RTE-HPV-TEXT-OFF !
    0 _RTE-HPV-TEXT-END ! 0 _RTE-HPV-ITEM-TEXT !
    0 _RTE-HPV-ITEM-ALIGNED ! 0 _RTE-HPV-GLYPH-COUNT !
    0 _RTE-HPV-GLYPH-TEXT ! 0 _RTE-HPV-GLYPH-ALIGNED !
    0 _RTE-HPV-GLYPH-MAX ! 0 _RTE-HPV-GLYPH-FIRST !
    0 _RTE-HPV-GLYPH-LAST !
    0 _RTE-HPV-INSTRUMENT-LAST !
    0 _RTE-HPV-INSTRUMENT-FIRST-REGION !
    0 _RTE-SADD-A ! 0 _RTE-SADD-B ! 0 _RTE-SADD-SUM !
    0 _RTE-CPV-FINISH DROP
    0 _RTE-IPV-FINISH DROP
    0 _RTE-GLYPH-RUN-PLAN-VALID-FINISH DROP ;

: _RTE-HYBRID-PREFLIGHT-BODY  ( -- status )
    _RTE-HPV-INIT
    _RTE-HPV-SUMMARY RTE-HYBRID-ADMISSION-SIZE 0 FILL
    _RTE-HPV-CONTROL? 0= IF RTE-S-INVALID EXIT THEN
    _RTE-HPV-INSTRUMENT? 0= IF RTE-S-INVALID EXIT THEN
    _RTE-HPV-GLYPH? 0= IF RTE-S-INVALID EXIT THEN
    _RTE-HPV-IDENTITY-RANGES? 0= IF RTE-S-INVALID EXIT THEN
    _RTE-HPV-SUMMARY _RTE-HPV-FACADE @ _RTE-F.CONTEXT @
    _RTE-HPV-FACADE @ _RTE-F.HYBRID-PREFLIGHT-XT @ EXECUTE
    DUP RTE-S-OK = IF
        _RTE-HPV-SUMMARY _RTE-HPV-ADMISSION @
            RTE-HYBRID-ADMISSION-SIZE MOVE
    THEN ;

: RTE-HYBRID-PREFLIGHT  ( hybrid admission facade -- status )
    >R
    OVER R@ _RTE-HPV-FIXED-AUTHORITY? 0= IF
        2DROP R> DROP RTE-S-INVALID EXIT
    THEN
    2DUP R@ _RTE-HPV-ADMISSION-AUTHORITY? 0= IF
        2DROP R> DROP RTE-S-INVALID EXIT
    THEN
    R@ _RTE-F.HYBRID-PREFLIGHT-XT @ 0= IF
        2DROP R> DROP RTE-S-INVALID EXIT
    THEN
    R> _RTE-HPV-FACADE !
    _RTE-HPV-ADMISSION ! _RTE-HPV-HYBRID !
    ['] _RTE-HYBRID-PREFLIGHT-BODY CATCH ?DUP IF
        DROP RTE-S-INVALID
    THEN
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN
    _RTE-HPV-FINISH ;

: RTE-CONTROL-PREFLIGHT  ( plan facade -- status )
    DUP RTE-VALID? 0= IF
        2DROP RTE-S-INVALID _RTE-CPV-FINISH EXIT
    THEN
    DUP _RTE-CPV-FACADE !
    OVER _RTE-CPV-PLAN !
    2DROP
    _RTE-CONTROL-PLAN-VALID-BODY 0= IF
        RTE-S-INVALID _RTE-CPV-FINISH EXIT
    THEN
    _RTE-CPV-PLAN @
    _RTE-CPV-COUNT @
    _RTE-CPV-BYTES @
    _RTE-CPV-ALIGNED-BYTES @
    _RTE-CPV-MAX-ITEM-BYTES @
    _RTE-CPV-LAST-ID @
    _RTE-CPV-COLLECTIONS @
    _RTE-CPV-CONTENT-ITEMS @
    _RTE-CPV-UTF8-BYTES @
    _RTE-CPV-FACADE @ _RTE-F.CONTEXT @
    _RTE-CPV-FACADE @ _RTE-F.CONTROL-PREFLIGHT-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN
    _RTE-CPV-FINISH ;

: RTE-GLYPH-RUN-PREFLIGHT  ( plan facade -- status )
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-GLYPH-RUN-PLAN-SIZE _RTE-SPAN? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER RTE-GLYPH-RUN-PLAN-SIZE 2 PICK RTE-STORAGE-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-LP.ITEMS-A @ 2 PICK _RTE-LP.ITEMS-U @ _RTE-SPAN? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-LP.ITEMS-A @ 2 PICK _RTE-LP.ITEMS-U @
        2 PICK RTE-STORAGE-DISJOINT? 0= IF
            2DROP RTE-S-INVALID EXIT
        THEN
    OVER RTE-GLYPH-RUN-PLAN-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.GLYPH-RUN-PREFLIGHT-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-GLYPH-RUN-DEFINE  ( run facade -- status )
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-GLYPH-RUN-SIZE _RTE-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-GLYPH-RUN-SIZE 2 PICK RTE-STORAGE-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-GLYPH-RUN.TEXT-A @ 2 PICK _RTE-GLYPH-RUN.TEXT-U @
        _RTE-GLYPH-RUN-TEXT-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER _RTE-GLYPH-RUN.TEXT-U @ IF
        OVER _RTE-GLYPH-RUN.TEXT-A @ 2 PICK _RTE-GLYPH-RUN.TEXT-U @
            2 PICK RTE-STORAGE-DISJOINT? 0= IF
                2DROP RTE-S-INVALID EXIT
            THEN
    THEN
    \ Dispatch proves bounded-span and scalar structure only.  The installed
    \ provider owns negotiated length admission before its linear UTF-8 scan.
    \ Imposing a facade-local text ceiling would violate caller-bounded design.
    OVER _RTE-GLYPH-RUN-FIELDS? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.GLYPH-RUN-DEF-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-GLYPH-RUN-REPLACE  ( run facade -- status )
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-GLYPH-RUN-SIZE _RTE-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-GLYPH-RUN-SIZE 2 PICK RTE-STORAGE-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-GLYPH-RUN.TEXT-A @ 2 PICK _RTE-GLYPH-RUN.TEXT-U @
        _RTE-GLYPH-RUN-TEXT-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER _RTE-GLYPH-RUN.TEXT-U @ IF
        OVER _RTE-GLYPH-RUN.TEXT-A @ 2 PICK _RTE-GLYPH-RUN.TEXT-U @
            2 PICK RTE-STORAGE-DISJOINT? 0= IF
                2DROP RTE-S-INVALID EXIT
            THEN
    THEN
    OVER _RTE-GLYPH-RUN-FIELDS? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.GLYPH-RUN-REPLACE-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

: RTE-INSTRUMENT-DEFINE  ( instrument facade -- status )
    DUP RTE-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER RTE-INSTRUMENT-SIZE _RTE-SPAN? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER RTE-INSTRUMENT-SIZE _RTE-HPV-OWNED-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER RTE-INSTRUMENT-SIZE 2 PICK RTE-STORAGE-DISJOINT? 0= IF
        2DROP RTE-S-INVALID EXIT
    THEN
    OVER _RTE-INSTRUMENT.UNIT-A @
    2 PICK _RTE-INSTRUMENT.UNIT-U @
        _RTE-CONTROL-TEXT-SPAN? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER _RTE-INSTRUMENT.UNIT-U @ IF
        OVER _RTE-INSTRUMENT.UNIT-A @
        2 PICK _RTE-INSTRUMENT.UNIT-U @
        2 PICK RTE-STORAGE-DISJOINT? 0= IF
            2DROP RTE-S-INVALID EXIT
        THEN
        OVER _RTE-INSTRUMENT.UNIT-A @
        2 PICK _RTE-INSTRUMENT.UNIT-U @
        _RTE-HPV-OWNED-DISJOINT? 0= IF
            2DROP RTE-S-INVALID EXIT
        THEN
        OVER _RTE-INSTRUMENT.UNIT-A @
        2 PICK _RTE-INSTRUMENT.UNIT-U @
        3 PICK RTE-INSTRUMENT-SIZE MSPAN-OVERLAP? IF
            2DROP RTE-S-INVALID EXIT
        THEN
    THEN
    OVER RTE-INSTRUMENT-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.INSTRUMENT-DEF-XT @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN ;

VARIABLE _RTE-CD-CONTROL
VARIABLE _RTE-CD-FACADE
VARIABLE _RTE-CD-CALLBACK-XT

: _RTE-CD-FINISH  ( x -- x )
    0 _RTE-CD-CONTROL !
    0 _RTE-CD-FACADE !
    0 _RTE-CD-CALLBACK-XT ! ;

: _RTE-CONTROL-DISPATCH-READY?  ( -- flag )
    _RTE-CD-FACADE @ RTE-VALID? 0= IF 0 EXIT THEN
    _RTE-CD-CONTROL @ RTE-CONTROL-SIZE _RTE-SPAN? 0= IF 0 EXIT THEN
    _RTE-CD-CONTROL @ RTE-CONTROL-SIZE _RTE-CD-FACADE @
        RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTE-CD-CONTROL @ _RTE-CONTROL.LABEL-A @
    _RTE-CD-CONTROL @ _RTE-CONTROL.LABEL-U @
        _RTE-CONTROL-TEXT-SPAN? 0= IF 0 EXIT THEN
    _RTE-CD-CONTROL @ _RTE-CONTROL.LABEL-U @ IF
        _RTE-CD-CONTROL @ _RTE-CONTROL.LABEL-A @
        _RTE-CD-CONTROL @ _RTE-CONTROL.LABEL-U @ _RTE-CD-FACADE @
            RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    THEN
    _RTE-CD-CONTROL @ _RTE-CONTROL.SHORTCUT-A @
    _RTE-CD-CONTROL @ _RTE-CONTROL.SHORTCUT-U @
        _RTE-CONTROL-TEXT-SPAN? 0= IF 0 EXIT THEN
    _RTE-CD-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ IF
        _RTE-CD-CONTROL @ _RTE-CONTROL.SHORTCUT-A @
        _RTE-CD-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ _RTE-CD-FACADE @
            RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    THEN
    _RTE-CD-CONTROL @ _RTE-CONTROL.CONTENT-A @
    _RTE-CD-CONTROL @ _RTE-CONTROL.CONTENT-U @
        _RTE-CONTROL-CONTENT-SPAN? 0= IF 0 EXIT THEN
    _RTE-CD-CONTROL @ _RTE-CONTROL.CONTENT-U @ IF
        _RTE-CD-CONTROL @ _RTE-CONTROL.CONTENT-A @
        _RTE-CD-CONTROL @ _RTE-CONTROL.CONTENT-U @ _RTE-CD-FACADE @
            RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    THEN
    _RTE-CD-CONTROL @ RTE-CONTROL-VALID? ;

: _RTE-CONTROL-DISPATCH  ( control facade callback-field-xt -- status )
    _RTE-CD-CALLBACK-XT !
    _RTE-CD-FACADE !
    _RTE-CD-CONTROL !
    _RTE-CONTROL-DISPATCH-READY? 0= IF
        RTE-S-INVALID _RTE-CD-FINISH EXIT
    THEN
    _RTE-CD-CONTROL @
    _RTE-CD-FACADE @ _RTE-F.CONTEXT @
    _RTE-CD-FACADE @ _RTE-CD-CALLBACK-XT @ EXECUTE @ EXECUTE
    DUP RTE-STATUS-VALID? 0= IF DROP RTE-S-INVALID THEN
    _RTE-CD-FINISH ;

: RTE-CONTROL-DEFINE  ( control facade -- status )
    ['] _RTE-F.CONTROL-DEF-XT _RTE-CONTROL-DISPATCH ;

: RTE-CONTROL-REPLACE  ( control facade -- status )
    ['] _RTE-F.CONTROL-REPLACE-XT _RTE-CONTROL-DISPATCH ;

: RTE-CONTROL-DROP  ( owner generation control facade -- status )
    DUP RTE-VALID? 0= IF 2DROP 2DROP RTE-S-INVALID EXIT THEN
    3 PICK 0= 3 PICK 0= OR 2 PICK 0= OR IF
        2DROP 2DROP RTE-S-INVALID EXIT
    THEN
    DUP _RTE-F.CONTEXT @ SWAP _RTE-F.CONTROL-DROP-XT @ EXECUTE
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
