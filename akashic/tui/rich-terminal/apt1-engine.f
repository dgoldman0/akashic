\ =====================================================================
\  apt1-engine.f -- neutral Akashic APT-1 rich-terminal engine
\ =====================================================================
\
\  This module is an explicitly composed owner of one caller-supplied PT
\  session.  It is not discoverable and contains no consumer or environment
\  policy.  The PT module remains the sole authority for wire framing,
\  session epochs, transaction IDs, revisions, credit, and result ordering.
\
\  Prefix:   RTAPT- (public), _RTAPT- (private)
\  Provider: akashic-tui-rtapt

PROVIDED akashic-tui-rtapt

REQUIRE ../../utils/memory-span.f

\ =====================================================================
\  Public status and lifecycle values
\ =====================================================================

0 CONSTANT RTAPT-S-OK
1 CONSTANT RTAPT-S-WOULD-BLOCK
2 CONSTANT RTAPT-S-SESSION-LOST
3 CONSTANT RTAPT-S-INVALID
4 CONSTANT RTAPT-S-UNSUPPORTED
5 CONSTANT RTAPT-S-CAPACITY
6 CONSTANT RTAPT-S-BUSY
7 CONSTANT RTAPT-S-REJECTED

\ Public retained-operation vocabulary accepted by RTAPT-RICH-BEGIN and
\ RTAPT-RICH-SEAL.  The aliases keep concrete PT values below provider
\ bridges rather than leaking them into backend-neutral consumers.
PT-RET-DELTA            CONSTANT RTAPT-RICH-DELTA
PT-RET-REPLACE-START    CONSTANT RTAPT-RICH-REPLACE-START
PT-RET-REPLACE-CONTINUE CONSTANT RTAPT-RICH-REPLACE-CONTINUE
PT-RET-LAYOUT-START     CONSTANT RTAPT-RICH-LAYOUT-START
PT-RET-LAYOUT-CONTINUE  CONSTANT RTAPT-RICH-LAYOUT-CONTINUE

PT-COMMIT            CONSTANT RTAPT-COMMIT
PT-COMMIT-AND-REVEAL CONSTANT RTAPT-COMMIT-AND-REVEAL

0 CONSTANT RTAPT-OWNER-ST-FREE
1 CONSTANT RTAPT-OWNER-ST-OPEN-QUEUED
2 CONSTANT RTAPT-OWNER-ST-OPENING
3 CONSTANT RTAPT-OWNER-ST-OPEN
4 CONSTANT RTAPT-OWNER-ST-DROP-QUEUED
5 CONSTANT RTAPT-OWNER-ST-DROPPING
6 CONSTANT RTAPT-OWNER-ST-TOMBSTONE
7 CONSTANT RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED
8 CONSTANT RTAPT-OWNER-ST-TOMBSTONE-DROPPING
9 CONSTANT RTAPT-OWNER-ST-QUARANTINED
10 CONSTANT RTAPT-OWNER-ST-DROP-RETRY-QUEUED
11 CONSTANT RTAPT-OWNER-ST-DROP-RETRY-DROPPING
12 CONSTANT RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED
13 CONSTANT RTAPT-OWNER-ST-TOMBSTONE-OPENING

0 CONSTANT RTAPT-UPDATE-IDLE
1 CONSTANT RTAPT-UPDATE-CAPTURING
2 CONSTANT RTAPT-UPDATE-SEALED
3 CONSTANT RTAPT-UPDATE-CELL-OPEN
4 CONSTANT RTAPT-UPDATE-AWAITING

0 CONSTANT RTAPT-COUPLING-NONE
1 CONSTANT RTAPT-COUPLING-CELL
2 CONSTANT RTAPT-COUPLING-RETAINED

\ Provider-local feature families and the typed capability snapshot returned
\ to the sole RTE bridge.  The 168-byte record is a fixed shape, not a
\ compiled product quota.  Its address is borrowed only for the synchronous
\ bridge call and never exposes PT's retained reply records.
1  CONSTANT RTAPT-F-CORE
2  CONSTANT RTAPT-F-VECTOR
4  CONSTANT RTAPT-F-IMAGE
8  CONSTANT RTAPT-F-INSTRUMENT
16 CONSTANT RTAPT-F-SERIES
32 CONSTANT RTAPT-F-CADENCE
64 CONSTANT RTAPT-F-CONTROLS
0x7F CONSTANT _RTAPT-FEATURE-MASK

\ PT advertises RET_CONTROLS in raw retained bit 0x100.  That protocol value
\ deliberately does not leak through the neutral/provider-local capability
\ vocabulary above.
0x100 CONSTANT _RTAPT-PT-F-CONTROLS

: _RTAPT-L.FEATURES        ( l -- a )       ;
: _RTAPT-L.OWNER-RECORDS   ( l -- a )   8 + ;
: _RTAPT-L.LIVE-OWNERS     ( l -- a )  16 + ;
: _RTAPT-L.REGIONS         ( l -- a )  24 + ;
: _RTAPT-L.RESOURCES       ( l -- a )  32 + ;
: _RTAPT-L.OBJECTS         ( l -- a )  40 + ;
: _RTAPT-L.SERIES          ( l -- a )  48 + ;
: _RTAPT-L.OPS             ( l -- a )  56 + ;
: _RTAPT-L.UPDATE-BYTES    ( l -- a )  64 + ;
: _RTAPT-L.CHUNK-BYTES     ( l -- a )  72 + ;
: _RTAPT-L.RESOURCE-BYTES  ( l -- a )  80 + ;
: _RTAPT-L.IMAGE-WIDTH     ( l -- a )  88 + ;
: _RTAPT-L.IMAGE-HEIGHT    ( l -- a )  96 + ;
: _RTAPT-L.PATH-POINTS     ( l -- a ) 104 + ;
: _RTAPT-L.GLYPH-RUN-BYTES ( l -- a ) 112 + ;
: _RTAPT-L.UTF8-BYTES      ( l -- a ) 120 + ;
: _RTAPT-L.SAMPLES-APPEND  ( l -- a ) 128 + ;
: _RTAPT-L.SERIES-HISTORY  ( l -- a ) 136 + ;
: _RTAPT-L.SAMPLE-SLOTS    ( l -- a ) 144 + ;
: _RTAPT-L.MIN-INTERVAL-US ( l -- a ) 152 + ;
: _RTAPT-L.OUTBOUND-PAYLOAD ( l -- a ) 160 + ;

168 CONSTANT RTAPT-LIMITS-SIZE

: RTAPT-LIMITS-BYTES  ( -- bytes )  RTAPT-LIMITS-SIZE ;

\ Renderer-neutral menu vocabulary.  These provider-local values are mapped
\ explicitly by the sole RTE bridge even though APT-1 currently assigns the
\ same compact scalar values.
1 CONSTANT RTAPT-CONTROL-MENUBAR
2 CONSTANT RTAPT-CONTROL-MENU
3 CONSTANT RTAPT-CONTROL-ITEM
4 CONSTANT RTAPT-CONTROL-SEPARATOR

1  CONSTANT RTAPT-CONTROL-F-VISIBLE
2  CONSTANT RTAPT-CONTROL-F-ENABLED
4  CONSTANT RTAPT-CONTROL-F-OPEN
8  CONSTANT RTAPT-CONTROL-F-SELECTED
16 CONSTANT RTAPT-CONTROL-F-CHECKED
0x1F CONSTANT _RTAPT-CONTROL-F-MASK

1 CONSTANT _RTAPT-OP-REGION-DEFINE
2 CONSTANT _RTAPT-OP-GLYPH-RUN-DEFINE
3 CONSTANT _RTAPT-OP-GLYPH-RUN-REPLACE
4 CONSTANT _RTAPT-OP-CONTROL-DEFINE
5 CONSTANT _RTAPT-OP-CONTROL-REPLACE
6 CONSTANT _RTAPT-OP-CONTROL-DROP
0 CONSTANT _RTAPT-PF-CONTROL-PHASE-NONE
1 CONSTANT _RTAPT-PF-CONTROL-PHASE-BAR
2 CONSTANT _RTAPT-PF-CONTROL-PHASE-MENU
3 CONSTANT _RTAPT-PF-CONTROL-PHASE-ITEM
72 CONSTANT _RTAPT-REGION-DEFINE-COPY-SIZE
88 CONSTANT _RTAPT-REGION-DEFINE-FRAME-BYTES
120 CONSTANT _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED
120 CONSTANT _RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED
120 CONSTANT _RTAPT-CONTROL-COPY-FIXED
120 CONSTANT _RTAPT-CONTROL-FRAME-FIXED
24 CONSTANT _RTAPT-CONTROL-DROP-COPY-SIZE
64 CONSTANT _RTAPT-CONTROL-DROP-FRAME-BYTES
160 CONSTANT _RTAPT-UPDATE-ENVELOPE-FRAME-BYTES

: _RTAPT-GLYPH-RUN-OP?  ( kind -- flag )
    DUP _RTAPT-OP-GLYPH-RUN-DEFINE =
    SWAP _RTAPT-OP-GLYPH-RUN-REPLACE = OR ;

: _RTAPT-CONTROL-WRITE-OP?  ( kind -- flag )
    DUP _RTAPT-OP-CONTROL-DEFINE =
    SWAP _RTAPT-OP-CONTROL-REPLACE = OR ;

\ One call-borrowed GLYPH-RUN plan describes one complete initial retained root.
\ These are record shapes, never product capacities.
112 CONSTANT RTAPT-GLYPH-RUN-PLAN-SIZE
120 CONSTANT RTAPT-GLYPH-RUN-PLAN-ITEM-SIZE
176 CONSTANT RTAPT-HYBRID-ADMISSION-SIZE

\ The operation record stores a typed operation kind, an offset/length into
\ the separately bounded copy span, the exact owner slot proved at capture,
\ and (for GLYPH_RUN_DEFINE only) the exact earlier REGION_DEFINE index plus
\ one.  No operation or copy capacity is compiled into the engine.
40 CONSTANT RTAPT-OP-SIZE
\ Owner records append engine-private, transient publication-audit scratch.
\ The scratch scales exactly with the caller-provided owner bank and is always
\ scrubbed before the final audit returns.
392 CONSTANT RTAPT-OWNER-SIZE
64 CONSTANT RTAPT-CONFIG-SIZE
504 CONSTANT RTAPT-ENGINE-SIZE

: RTAPT-CONFIG-BYTES  ( -- bytes )  RTAPT-CONFIG-SIZE ;
: RTAPT-ENGINE-BYTES  ( -- bytes )  RTAPT-ENGINE-SIZE ;
: RTAPT-OWNER-BYTES   ( -- bytes )  RTAPT-OWNER-SIZE ;
: RTAPT-OP-BYTES      ( -- bytes )  RTAPT-OP-SIZE ;
: RTAPT-GLYPH-RUN-PLAN-BYTES  ( -- bytes )  RTAPT-GLYPH-RUN-PLAN-SIZE ;
: RTAPT-GLYPH-RUN-PLAN-ITEM-BYTES  ( -- bytes )
    RTAPT-GLYPH-RUN-PLAN-ITEM-SIZE ;
: RTAPT-HYBRID-ADMISSION-BYTES  ( -- bytes )
    RTAPT-HYBRID-ADMISSION-SIZE ;

0x5254415054434647 CONSTANT _RTAPT-CONFIG-MAGIC  \ "RTAPTCFG"
0x5254415054454E47 CONSTANT _RTAPT-ENGINE-MAGIC  \ "RTAPTENG"

\ =====================================================================
\  Caller-owned record layouts
\ =====================================================================

\ Configuration is a checked construction record.  This engine profile needs
\ at least one owner slot, one typed-operation slot, and one byte in its copy
\ bank; their upper bounds come only from the caller's nonempty spans.
\ RTAPT-INIT copies all fields, so configuration is not retained or discovered.
: _RTAPT-C.MAGIC      ( c -- a )       ;
: _RTAPT-C.SESSION    ( c -- a )   8 + ;
: _RTAPT-C.OWNERS-A   ( c -- a )  16 + ;
: _RTAPT-C.OWNERS-U   ( c -- a )  24 + ;
: _RTAPT-C.OPS-A      ( c -- a )  32 + ;
: _RTAPT-C.OPS-U      ( c -- a )  40 + ;
: _RTAPT-C.COPY-A     ( c -- a )  48 + ;
: _RTAPT-C.COPY-U     ( c -- a )  56 + ;

\ Mutation-free initial-GLYPH-RUN admission plan.  ITEMS-A/ITEMS-U are borrowed
\ only for RTAPT-GLYPH-RUN-PREFLIGHT's dynamic extent.
: _RTAPT-LP.OWNER        ( p -- a )       ;
: _RTAPT-LP.GENERATION   ( p -- a )   8 + ;
: _RTAPT-LP.SURFACE-COLS ( p -- a )  16 + ;
: _RTAPT-LP.SURFACE-ROWS ( p -- a )  24 + ;
: _RTAPT-LP.REGION-ID    ( p -- a )  32 + ;
: _RTAPT-LP.REGION-X     ( p -- a )  40 + ;
: _RTAPT-LP.REGION-Y     ( p -- a )  48 + ;
: _RTAPT-LP.REGION-COLS  ( p -- a )  56 + ;
: _RTAPT-LP.REGION-ROWS  ( p -- a )  64 + ;
: _RTAPT-LP.REGION-Z     ( p -- a )  72 + ;
: _RTAPT-LP.REGION-FLAGS ( p -- a )  80 + ;
: _RTAPT-LP.ITEMS-A      ( p -- a )  88 + ;
: _RTAPT-LP.ITEMS-U      ( p -- a )  96 + ;
: _RTAPT-LP.RESERVED     ( p -- a ) 104 + ;

: _RTAPT-LPI.OBJECT        ( i -- a )       ;
: _RTAPT-LPI.PARENT        ( i -- a )   8 + ;
: _RTAPT-LPI.ROW           ( i -- a )  16 + ;
: _RTAPT-LPI.COL           ( i -- a )  24 + ;
: _RTAPT-LPI.HEIGHT        ( i -- a )  32 + ;
: _RTAPT-LPI.WIDTH         ( i -- a )  40 + ;
: _RTAPT-LPI.ROOT-HEIGHT   ( i -- a )  48 + ;
: _RTAPT-LPI.ROOT-WIDTH    ( i -- a )  56 + ;
: _RTAPT-LPI.Z             ( i -- a )  64 + ;
: _RTAPT-LPI.VISIBLE       ( i -- a )  72 + ;
: _RTAPT-LPI.FG-RGBA       ( i -- a )  80 + ;
: _RTAPT-LPI.BG-RGBA       ( i -- a )  88 + ;
: _RTAPT-LPI.ATTRS         ( i -- a )  96 + ;
: _RTAPT-LPI.TEXT-CAPACITY ( i -- a ) 104 + ;
: _RTAPT-LPI.RESERVED      ( i -- a ) 112 + ;

\ Fixed neutral-checked hybrid admission summary.  This provider-local shape
\ is correlated explicitly by engine-apt1.f; it contains no caller bank or
\ text pointers and therefore cannot authorize a second candidate traversal.
: _RTAPT-HA.OWNER           ( s -- a )       ;
: _RTAPT-HA.GENERATION      ( s -- a )   8 + ;
: _RTAPT-HA.SURFACE-COLS    ( s -- a )  16 + ;
: _RTAPT-HA.SURFACE-ROWS    ( s -- a )  24 + ;
: _RTAPT-HA.REGION-ID       ( s -- a )  32 + ;
: _RTAPT-HA.REGION-X        ( s -- a )  40 + ;
: _RTAPT-HA.REGION-Y        ( s -- a )  48 + ;
: _RTAPT-HA.REGION-COLS     ( s -- a )  56 + ;
: _RTAPT-HA.REGION-ROWS     ( s -- a )  64 + ;
: _RTAPT-HA.REGION-Z        ( s -- a )  72 + ;
: _RTAPT-HA.REGION-FLAGS    ( s -- a )  80 + ;
: _RTAPT-HA.CONTROL-COUNT   ( s -- a )  88 + ;
: _RTAPT-HA.CONTROL-TEXT    ( s -- a )  96 + ;
: _RTAPT-HA.CONTROL-ALIGNED ( s -- a ) 104 + ;
: _RTAPT-HA.CONTROL-MAX     ( s -- a ) 112 + ;
: _RTAPT-HA.CONTROL-LAST    ( s -- a ) 120 + ;
: _RTAPT-HA.GLYPH-COUNT     ( s -- a ) 128 + ;
: _RTAPT-HA.GLYPH-TEXT      ( s -- a ) 136 + ;
: _RTAPT-HA.GLYPH-ALIGNED   ( s -- a ) 144 + ;
: _RTAPT-HA.GLYPH-MAX       ( s -- a ) 152 + ;
: _RTAPT-HA.GLYPH-LAST      ( s -- a ) 160 + ;
: _RTAPT-HA.RESERVED        ( s -- a ) 168 + ;

\ Owner entries are engine-private after initialization.  NEXT links a
\ caller-capacity-derived FIFO of exact lifecycle requests.  OWNER-USED counts
\ live bindings, in-flight candidates, tombstones, and quarantined evidence;
\ a successful drop releases quota fields but retains its exact tuple.
: _RTAPT-O.STATE      ( o -- a )       ;
: _RTAPT-O.OWNER      ( o -- a )   8 + ;
: _RTAPT-O.GENERATION ( o -- a )  16 + ;
: _RTAPT-O.REGIONS    ( o -- a )  24 + ;
: _RTAPT-O.RESOURCES  ( o -- a )  32 + ;
: _RTAPT-O.OBJECTS    ( o -- a )  40 + ;
: _RTAPT-O.SERIES     ( o -- a )  48 + ;
: _RTAPT-O.RES-BYTES  ( o -- a )  56 + ;
: _RTAPT-O.UTF8-BYTES ( o -- a )  64 + ;
: _RTAPT-O.SAMPLES    ( o -- a )  72 + ;
: _RTAPT-O.WIRE-STATUS ( o -- a ) 80 + ;
: _RTAPT-O.NEXT       ( o -- a )  88 + ;
: _RTAPT-O.PRIOR-GENERATION ( o -- a ) 96 + ;
: _RTAPT-O.ACTIVE-REGIONS ( o -- a ) 104 + ;
: _RTAPT-O.HIDDEN-REGIONS ( o -- a ) 112 + ;
: _RTAPT-O.REGION-HIGH ( o -- a ) 120 + ;
: _RTAPT-O.PENDING-REGIONS ( o -- a ) 128 + ;
: _RTAPT-O.PENDING-REGION-HIGH ( o -- a ) 136 + ;
: _RTAPT-O.ACTIVE-OBJECTS ( o -- a ) 144 + ;
: _RTAPT-O.HIDDEN-OBJECTS ( o -- a ) 152 + ;
: _RTAPT-O.OBJECT-HIGH ( o -- a ) 160 + ;
: _RTAPT-O.ACTIVE-UTF8 ( o -- a ) 168 + ;
: _RTAPT-O.HIDDEN-UTF8 ( o -- a ) 176 + ;
: _RTAPT-O.PENDING-OBJECTS ( o -- a ) 184 + ;
: _RTAPT-O.PENDING-OBJECT-HIGH ( o -- a ) 192 + ;
: _RTAPT-O.PENDING-UTF8 ( o -- a ) 200 + ;
: _RTAPT-O.ACTIVE-CONTROLS ( o -- a ) 208 + ;
: _RTAPT-O.HIDDEN-CONTROLS ( o -- a ) 216 + ;
: _RTAPT-O.CONTROL-HIGH ( o -- a ) 224 + ;
: _RTAPT-O.PENDING-CONTROLS ( o -- a ) 232 + ;
: _RTAPT-O.PENDING-CONTROL-HIGH ( o -- a ) 240 + ;

248 CONSTANT _RTAPT-OWNER-AUDIT-OFF
144 CONSTANT _RTAPT-OWNER-AUDIT-SIZE
: _RTAPT-O.A-RCOUNT    ( o -- a ) 248 + ;
: _RTAPT-O.A-RHIGH     ( o -- a ) 256 + ;
: _RTAPT-O.A-OCOUNT    ( o -- a ) 264 + ;
: _RTAPT-O.A-OHIGH     ( o -- a ) 272 + ;
: _RTAPT-O.A-UTF8      ( o -- a ) 280 + ;
: _RTAPT-O.A-CCOUNT    ( o -- a ) 288 + ;
: _RTAPT-O.A-CHIGH     ( o -- a ) 296 + ;
: _RTAPT-O.A-CPHASE    ( o -- a ) 304 + ;
: _RTAPT-O.A-CBAR-COUNT ( o -- a ) 312 + ;
: _RTAPT-O.A-CBAR-ID   ( o -- a ) 320 + ;
: _RTAPT-O.A-CMENU-FIRST ( o -- a ) 328 + ;
: _RTAPT-O.A-CMENU-LAST ( o -- a ) 336 + ;
: _RTAPT-O.A-CPARENT   ( o -- a ) 344 + ;
: _RTAPT-O.A-CORDER    ( o -- a ) 352 + ;
: _RTAPT-O.A-COPEN-MENU ( o -- a ) 360 + ;
: _RTAPT-O.A-CSELECTED-MENU ( o -- a ) 368 + ;
: _RTAPT-O.A-CSELECTED-ITEM-PARENT ( o -- a ) 376 + ;
: _RTAPT-O.A-OPS       ( o -- a ) 384 + ;

\ Captured operation records contain no borrowed caller pointer.  COPY-OFF is
\ relative to the engine's caller-owned copy bank and COPY-U is exact for the
\ typed operation kind.
: _RTAPT-P.KIND       ( p -- a )       ;
: _RTAPT-P.COPY-OFF   ( p -- a )   8 + ;
: _RTAPT-P.COPY-U     ( p -- a )  16 + ;
: _RTAPT-P.OWNER-SLOT ( p -- a )  24 + ;
: _RTAPT-P.REGION-OP  ( p -- a )  32 + ;

\ REGION_DEFINE is copied as nine native cells.  The PT typed writer performs
\ the normative wire packing; this record is private retry authority only.
: _RTAPT-RD.OWNER      ( r -- a )       ;
: _RTAPT-RD.GENERATION ( r -- a )   8 + ;
: _RTAPT-RD.REGION     ( r -- a )  16 + ;
: _RTAPT-RD.X          ( r -- a )  24 + ;
: _RTAPT-RD.Y          ( r -- a )  32 + ;
: _RTAPT-RD.COLS       ( r -- a )  40 + ;
: _RTAPT-RD.ROWS       ( r -- a )  48 + ;
: _RTAPT-RD.Z          ( r -- a )  56 + ;
: _RTAPT-RD.FLAGS      ( r -- a )  64 + ;

\ GLYPH_RUN retry authority stores PT-ready normalized geometry, foreground
\ and background RGBA, and the admitted style mask.  The exact copied text
\ follows the fixed header;
\ no captured operation retains the caller's source pointer.
: _RTAPT-LD.OWNER      ( l -- a )       ;
: _RTAPT-LD.GENERATION ( l -- a )   8 + ;
: _RTAPT-LD.OBJECT     ( l -- a )  16 + ;
: _RTAPT-LD.REGION     ( l -- a )  24 + ;
: _RTAPT-LD.PARENT     ( l -- a )  32 + ;
: _RTAPT-LD.LEFT       ( l -- a )  40 + ;
: _RTAPT-LD.TOP        ( l -- a )  48 + ;
: _RTAPT-LD.RIGHT      ( l -- a )  56 + ;
: _RTAPT-LD.BOTTOM     ( l -- a )  64 + ;
: _RTAPT-LD.Z          ( l -- a )  72 + ;
: _RTAPT-LD.VISIBLE    ( l -- a )  80 + ;
: _RTAPT-LD.FG-RGBA    ( l -- a )  88 + ;
: _RTAPT-LD.BG-RGBA    ( l -- a )  96 + ;
: _RTAPT-LD.ATTRS      ( l -- a ) 104 + ;
: _RTAPT-LD.TEXT-U     ( l -- a ) 112 + ;
: _RTAPT-LD.TEXT       ( l -- a ) 120 + ;

\ CONTROL retry authority stores the neutral/provider-validated scalar tuple
\ and exact copied strings.  Geometry has already been normalized to PT-ready
\ UNORM32 bounds.  DEFINE and REPLACE therefore share one 120-byte fixed copy
\ shape and retain no source pointer.
: _RTAPT-CD.OWNER      ( c -- a )       ;
: _RTAPT-CD.GENERATION ( c -- a )   8 + ;
: _RTAPT-CD.CONTROL    ( c -- a )  16 + ;
: _RTAPT-CD.KIND       ( c -- a )  24 + ;
: _RTAPT-CD.STATE      ( c -- a )  32 + ;
: _RTAPT-CD.Z          ( c -- a )  40 + ;
: _RTAPT-CD.REGION     ( c -- a )  48 + ;
: _RTAPT-CD.PARENT     ( c -- a )  56 + ;
: _RTAPT-CD.ORDER      ( c -- a )  64 + ;
: _RTAPT-CD.LEFT       ( c -- a )  72 + ;
: _RTAPT-CD.TOP        ( c -- a )  80 + ;
: _RTAPT-CD.RIGHT      ( c -- a )  88 + ;
: _RTAPT-CD.BOTTOM     ( c -- a )  96 + ;
: _RTAPT-CD.LABEL-U    ( c -- a ) 104 + ;
: _RTAPT-CD.SHORTCUT-U ( c -- a ) 112 + ;
: _RTAPT-CD.TEXT       ( c -- a ) 120 + ;

\ DROP retry authority is the exact three-cell PT payload.
: _RTAPT-CX.OWNER      ( d -- a )       ;
: _RTAPT-CX.GENERATION ( d -- a )   8 + ;
: _RTAPT-CX.CONTROL    ( d -- a )  16 + ;

\ Fixed engine metadata is followed by one PT completion descriptor and one
\ typed limits snapshot.  Both are part of the engine span; neither exposes PT
\ authority or a raw discovery-record address.
: _RTAPT-E.MAGIC      ( e -- a )       ;
: _RTAPT-E.SESSION    ( e -- a )   8 + ;
: _RTAPT-E.OWNERS-A   ( e -- a )  16 + ;
: _RTAPT-E.OWNERS-U   ( e -- a )  24 + ;
: _RTAPT-E.OWNER-CAP  ( e -- a )  32 + ;
: _RTAPT-E.OWNER-USED ( e -- a )  40 + ;
: _RTAPT-E.OPS-A      ( e -- a )  48 + ;
: _RTAPT-E.OPS-U      ( e -- a )  56 + ;
: _RTAPT-E.OP-CAP     ( e -- a )  64 + ;
: _RTAPT-E.COPY-A     ( e -- a )  72 + ;
: _RTAPT-E.COPY-U     ( e -- a )  80 + ;
: _RTAPT-E.QUEUE-HEAD ( e -- a )  88 + ;
: _RTAPT-E.QUEUE-TAIL ( e -- a )  96 + ;
: _RTAPT-E.ACTIVE-O   ( e -- a ) 104 + ;
: _RTAPT-E.ACTIVE-KIND ( e -- a ) 112 + ;
: _RTAPT-E.UPDATE-STATE ( e -- a ) 120 + ;
: _RTAPT-E.COUPLING   ( e -- a ) 128 + ;
: _RTAPT-E.COLS       ( e -- a ) 136 + ;
: _RTAPT-E.ROWS       ( e -- a ) 144 + ;
: _RTAPT-E.CELL-SPANS ( e -- a ) 152 + ;
: _RTAPT-E.CELLS      ( e -- a ) 160 + ;
: _RTAPT-E.CELL-MODE  ( e -- a ) 168 + ;
: _RTAPT-E.RET-MODE   ( e -- a ) 176 + ;
: _RTAPT-E.DISPOSITION ( e -- a ) 184 + ;
: _RTAPT-E.OP-COUNT   ( e -- a ) 192 + ;
: _RTAPT-E.COPY-USED  ( e -- a ) 200 + ;
: _RTAPT-E.RET-BYTES  ( e -- a ) 208 + ;
: _RTAPT-E.SEND-INDEX ( e -- a ) 216 + ;
: _RTAPT-E.LAST-STATUS ( e -- a ) 224 + ;
: _RTAPT-E.LAST-WIRE  ( e -- a ) 232 + ;
: _RTAPT-E.LAST-DETAIL ( e -- a ) 240 + ;
: _RTAPT-E.LAST-REVISION ( e -- a ) 248 + ;
: _RTAPT-E.COMPLETION ( e -- a ) 256 + ;
: _RTAPT-E.LIMITS     ( e -- a ) 336 + ;

0 CONSTANT _RTAPT-ACTIVE-NONE
1 CONSTANT _RTAPT-ACTIVE-OWNER-OPEN
2 CONSTANT _RTAPT-ACTIVE-OWNER-DROP
3 CONSTANT _RTAPT-ACTIVE-OUTPUT
4 CONSTANT _RTAPT-ACTIVE-QUARANTINED

\ =====================================================================
\  Checked storage geometry
\ =====================================================================

: _RTAPT-ALIGNED?  ( a -- flag )  7 AND 0= ;

\ Every provider validator below borrows module-private scratch.  Hybrid
\ admission rejects its fixed summary and engine storage against this whole
\ mutable range before invoking any validator that can write it.
CREATE _RTAPT-HAF-OWNED-START

VARIABLE _RTAPT-CI-C
VARIABLE _RTAPT-CI-S
VARIABLE _RTAPT-CI-OA
VARIABLE _RTAPT-CI-OU
VARIABLE _RTAPT-CI-PA
VARIABLE _RTAPT-CI-PU
VARIABLE _RTAPT-CI-CA
VARIABLE _RTAPT-CI-CU

: _RTAPT-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER _RTAPT-ALIGNED? 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RTAPT-CONFIG-RANGES?  ( -- flag )
    _RTAPT-CI-C @ RTAPT-CONFIG-SIZE _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-CI-S @ PT-SESSION-SIZE _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-CI-OA @ _RTAPT-CI-OU @ _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-CI-PA @ _RTAPT-CI-PU @ _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-CI-CA @ _RTAPT-CI-CU @ _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-CI-OU @ RTAPT-OWNER-SIZE MOD IF 0 EXIT THEN
    _RTAPT-CI-PU @ RTAPT-OP-SIZE MOD IF 0 EXIT THEN

    _RTAPT-CI-C @ RTAPT-CONFIG-SIZE _RTAPT-CI-S @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-CI-OA @ _RTAPT-CI-OU @ _RTAPT-CI-S @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-CI-PA @ _RTAPT-CI-PU @ _RTAPT-CI-S @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-CI-CA @ _RTAPT-CI-CU @ _RTAPT-CI-S @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN

    _RTAPT-CI-C @ RTAPT-CONFIG-SIZE _RTAPT-CI-S @ PT-SESSION-SIZE
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-C @ RTAPT-CONFIG-SIZE _RTAPT-CI-OA @ _RTAPT-CI-OU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-C @ RTAPT-CONFIG-SIZE _RTAPT-CI-PA @ _RTAPT-CI-PU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-C @ RTAPT-CONFIG-SIZE _RTAPT-CI-CA @ _RTAPT-CI-CU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-S @ PT-SESSION-SIZE _RTAPT-CI-OA @ _RTAPT-CI-OU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-S @ PT-SESSION-SIZE _RTAPT-CI-PA @ _RTAPT-CI-PU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-S @ PT-SESSION-SIZE _RTAPT-CI-CA @ _RTAPT-CI-CU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-OA @ _RTAPT-CI-OU @ _RTAPT-CI-PA @ _RTAPT-CI-PU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-OA @ _RTAPT-CI-OU @ _RTAPT-CI-CA @ _RTAPT-CI-CU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-CI-PA @ _RTAPT-CI-PU @ _RTAPT-CI-CA @ _RTAPT-CI-CU @
        MSPAN-OVERLAP? 0= ;

: RTAPT-CONFIG-INIT  ( session owners-a owners-u ops-a ops-u copy-a copy-u config -- status )
    _RTAPT-CI-C ! _RTAPT-CI-CU ! _RTAPT-CI-CA !
    _RTAPT-CI-PU ! _RTAPT-CI-PA ! _RTAPT-CI-OU ! _RTAPT-CI-OA ! _RTAPT-CI-S !
    _RTAPT-CONFIG-RANGES? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CI-C @ RTAPT-CONFIG-SIZE 0 FILL
    _RTAPT-CONFIG-MAGIC _RTAPT-CI-C @ _RTAPT-C.MAGIC !
    _RTAPT-CI-S @ _RTAPT-CI-C @ _RTAPT-C.SESSION !
    _RTAPT-CI-OA @ _RTAPT-CI-C @ _RTAPT-C.OWNERS-A !
    _RTAPT-CI-OU @ _RTAPT-CI-C @ _RTAPT-C.OWNERS-U !
    _RTAPT-CI-PA @ _RTAPT-CI-C @ _RTAPT-C.OPS-A !
    _RTAPT-CI-PU @ _RTAPT-CI-C @ _RTAPT-C.OPS-U !
    _RTAPT-CI-CA @ _RTAPT-CI-C @ _RTAPT-C.COPY-A !
    _RTAPT-CI-CU @ _RTAPT-CI-C @ _RTAPT-C.COPY-U !
    RTAPT-S-OK ;

: _RTAPT-CONFIG-VALID?  ( c -- flag )
    DUP RTAPT-CONFIG-SIZE _RTAPT-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-C.MAGIC @ _RTAPT-CONFIG-MAGIC <> IF DROP 0 EXIT THEN
    DUP _RTAPT-C.SESSION @ _RTAPT-CI-S !
    DUP _RTAPT-C.OWNERS-A @ _RTAPT-CI-OA !
    DUP _RTAPT-C.OWNERS-U @ _RTAPT-CI-OU !
    DUP _RTAPT-C.OPS-A @ _RTAPT-CI-PA !
    DUP _RTAPT-C.OPS-U @ _RTAPT-CI-PU !
    DUP _RTAPT-C.COPY-A @ _RTAPT-CI-CA !
    DUP _RTAPT-C.COPY-U @ _RTAPT-CI-CU !
    _RTAPT-CI-C ! _RTAPT-CONFIG-RANGES? ;

VARIABLE _RTAPT-I-C
VARIABLE _RTAPT-I-E

: _RTAPT-ENGINE-DISJOINT?  ( -- flag )
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE _RTAPT-CI-S @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE _RTAPT-I-C @ RTAPT-CONFIG-SIZE
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE _RTAPT-CI-S @ PT-SESSION-SIZE
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE _RTAPT-CI-OA @ _RTAPT-CI-OU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE _RTAPT-CI-PA @ _RTAPT-CI-PU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE _RTAPT-CI-CA @ _RTAPT-CI-CU @
        MSPAN-OVERLAP? 0= ;

: _RTAPT-PT>STATUS  ( pt-status -- status )
    DUP PT-S-OK = IF DROP RTAPT-S-OK EXIT THEN
    DUP PT-S-WOULD-BLOCK = IF DROP RTAPT-S-WOULD-BLOCK EXIT THEN
    DUP PT-S-SESSION-LOST = IF DROP RTAPT-S-SESSION-LOST EXIT THEN
    DUP PT-S-INVALID = IF DROP RTAPT-S-INVALID EXIT THEN
    DUP PT-S-UNSUPPORTED = IF DROP RTAPT-S-UNSUPPORTED EXIT THEN
    DROP RTAPT-S-SESSION-LOST ;

VARIABLE _RTAPT-EV-E
VARIABLE _RTAPT-EV-P

: _RTAPT-ENGINE-RANGES?  ( engine -- flag )
    _RTAPT-EV-E !
    _RTAPT-EV-E @ RTAPT-ENGINE-SIZE _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.SESSION @ PT-SESSION-SIZE
        _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.OWNERS-A @
        _RTAPT-EV-E @ _RTAPT-E.OWNERS-U @ _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.OPS-A @
        _RTAPT-EV-E @ _RTAPT-E.OPS-U @ _RTAPT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.COPY-A @
        _RTAPT-EV-E @ _RTAPT-E.COPY-U @ _RTAPT-SPAN? 0= IF 0 EXIT THEN

    _RTAPT-EV-E @ RTAPT-ENGINE-SIZE
        _RTAPT-EV-E @ _RTAPT-E.SESSION @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.OWNERS-A @
        _RTAPT-EV-E @ _RTAPT-E.OWNERS-U @
        _RTAPT-EV-E @ _RTAPT-E.SESSION @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.OPS-A @
        _RTAPT-EV-E @ _RTAPT-E.OPS-U @
        _RTAPT-EV-E @ _RTAPT-E.SESSION @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.COPY-A @
        _RTAPT-EV-E @ _RTAPT-E.COPY-U @
        _RTAPT-EV-E @ _RTAPT-E.SESSION @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN

    _RTAPT-EV-E @ RTAPT-ENGINE-SIZE
        _RTAPT-EV-E @ _RTAPT-E.OWNERS-A @
        _RTAPT-EV-E @ _RTAPT-E.OWNERS-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-EV-E @ RTAPT-ENGINE-SIZE
        _RTAPT-EV-E @ _RTAPT-E.OPS-A @
        _RTAPT-EV-E @ _RTAPT-E.OPS-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-EV-E @ RTAPT-ENGINE-SIZE
        _RTAPT-EV-E @ _RTAPT-E.COPY-A @
        _RTAPT-EV-E @ _RTAPT-E.COPY-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.OWNERS-A @
        _RTAPT-EV-E @ _RTAPT-E.OWNERS-U @
        _RTAPT-EV-E @ _RTAPT-E.OPS-A @
        _RTAPT-EV-E @ _RTAPT-E.OPS-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.OWNERS-A @
        _RTAPT-EV-E @ _RTAPT-E.OWNERS-U @
        _RTAPT-EV-E @ _RTAPT-E.COPY-A @
        _RTAPT-EV-E @ _RTAPT-E.COPY-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-EV-E @ _RTAPT-E.OPS-A @
        _RTAPT-EV-E @ _RTAPT-E.OPS-U @
        _RTAPT-EV-E @ _RTAPT-E.COPY-A @
        _RTAPT-EV-E @ _RTAPT-E.COPY-U @ MSPAN-OVERLAP? 0= ;

: _RTAPT-OWNER-POINTER?  ( owner-record engine -- flag )
    >R
    DUP R@ _RTAPT-E.OWNERS-A @ U< IF DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.OWNERS-A @ - DUP R@ _RTAPT-E.OWNERS-U @ U< 0= IF
        DROP R> DROP 0 EXIT
    THEN
    RTAPT-OWNER-SIZE MOD 0= R> DROP ;

: _RTAPT-OWNER-POINTER-OR-ZERO?  ( owner-record|0 engine -- flag )
    OVER 0= IF 2DROP -1 EXIT THEN _RTAPT-OWNER-POINTER? ;

: _RTAPT-U32?  ( u -- flag )  0xFFFFFFFF U> 0= ;
: _RTAPT-U16?  ( u -- flag )  0xFFFF U> 0= ;

: _RTAPT-I32?  ( n -- flag )
    DUP -2147483648 < IF DROP 0 EXIT THEN 2147483647 > 0= ;

: _RTAPT-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

: _RTAPT-ALIGN8?  ( u -- aligned-u flag )
    7 _RTAPT-UADD? 0= IF DROP 0 0 EXIT THEN
    -8 AND -1 ;

: _RTAPT-ZERO-SPAN?  ( a u -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _RTAPT-UMUL?  ( a b -- product flag )
    UM* DUP IF 2DROP 0 0 EXIT THEN DROP -1 ;

: _RTAPT-OP-NTH  ( index engine -- op-record )
    _RTAPT-E.OPS-A @ SWAP RTAPT-OP-SIZE * + ;

VARIABLE _RTAPT-BV-E
VARIABLE _RTAPT-BV-STATE
VARIABLE _RTAPT-BV-OFF
VARIABLE _RTAPT-BV-NEXT
VARIABLE _RTAPT-BV-RET
VARIABLE _RTAPT-BV-P
VARIABLE _RTAPT-BV-COPY
VARIABLE _RTAPT-BV-COPY-U
VARIABLE _RTAPT-BV-FRAME
VARIABLE _RTAPT-BV-RAW-U
VARIABLE _RTAPT-BV-TEXT-U

: _RTAPT-CAPTURED-BANKS?  ( engine -- flag )
    DUP _RTAPT-BV-E !
    DUP _RTAPT-E.OP-COUNT @ _RTAPT-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OP-COUNT @ OVER _RTAPT-E.OP-CAP @ U> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.COPY-USED @ OVER _RTAPT-E.COPY-U @ U> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.SEND-INDEX @ OVER _RTAPT-E.OP-COUNT @ U> IF DROP 0 EXIT THEN
    DROP
    0 _RTAPT-BV-OFF ! 0 _RTAPT-BV-RET !
    _RTAPT-BV-E @ _RTAPT-E.OP-COUNT @ 0 ?DO
        \ Store the loop-local record outright.  Every read below reloads it,
        \ because retaining it leaks one pointer per captured operation.
        I _RTAPT-BV-E @ _RTAPT-OP-NTH _RTAPT-BV-P !
        _RTAPT-BV-P @ _RTAPT-P.OWNER-SLOT @
            _RTAPT-BV-E @ _RTAPT-E.OWNER-CAP @ U< 0= IF
            0 UNLOOP EXIT
        THEN
        _RTAPT-BV-P @ _RTAPT-P.KIND @
            _RTAPT-OP-GLYPH-RUN-DEFINE = IF
            _RTAPT-BV-P @ _RTAPT-P.REGION-OP @ DUP 0= IF
                DROP 0 UNLOOP EXIT
            THEN
            1- I U< 0= IF 0 UNLOOP EXIT THEN
        ELSE
            _RTAPT-BV-P @ _RTAPT-P.REGION-OP @ IF 0 UNLOOP EXIT THEN
        THEN
        _RTAPT-BV-P @ _RTAPT-P.COPY-OFF @ _RTAPT-BV-OFF @ <>
            IF 0 UNLOOP EXIT THEN
        _RTAPT-BV-P @ _RTAPT-P.COPY-U @ DUP 0= IF
            DROP 0 UNLOOP EXIT
        THEN _RTAPT-BV-COPY-U !
        _RTAPT-BV-OFF @ _RTAPT-BV-COPY-U @ _RTAPT-UADD?
            0= IF DROP 0 UNLOOP EXIT THEN DUP _RTAPT-BV-NEXT !
        _RTAPT-BV-E @ _RTAPT-E.COPY-USED @ U> IF 0 UNLOOP EXIT THEN
        _RTAPT-BV-NEXT @ _RTAPT-BV-E @ _RTAPT-E.COPY-U @ U>
            IF 0 UNLOOP EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.COPY-A @ _RTAPT-BV-OFF @ +
            _RTAPT-BV-COPY !
        _RTAPT-BV-P @ _RTAPT-P.KIND @ _RTAPT-OP-REGION-DEFINE = IF
            _RTAPT-BV-COPY-U @ _RTAPT-REGION-DEFINE-COPY-SIZE <>
                IF 0 UNLOOP EXIT THEN
            _RTAPT-REGION-DEFINE-FRAME-BYTES _RTAPT-BV-FRAME !
        ELSE
            _RTAPT-BV-P @ _RTAPT-P.KIND @ _RTAPT-GLYPH-RUN-OP? IF
                _RTAPT-BV-COPY-U @ _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED U<
                    IF 0 UNLOOP EXIT THEN
                _RTAPT-BV-COPY @ _RTAPT-LD.TEXT-U @ _RTAPT-U32? 0=
                    IF 0 UNLOOP EXIT THEN
                _RTAPT-BV-COPY @ _RTAPT-LD.TEXT-U @
                    _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED _RTAPT-UADD? 0= IF
                    DROP 0 UNLOOP EXIT
                THEN DUP _RTAPT-BV-RAW-U ! _RTAPT-ALIGN8? 0= IF
                    DROP 0 UNLOOP EXIT
                THEN _RTAPT-BV-COPY-U @ <> IF 0 UNLOOP EXIT THEN
                _RTAPT-BV-COPY @ _RTAPT-BV-RAW-U @ +
                _RTAPT-BV-COPY-U @ _RTAPT-BV-RAW-U @ -
                    _RTAPT-ZERO-SPAN? 0= IF 0 UNLOOP EXIT THEN
                _RTAPT-BV-COPY @ _RTAPT-LD.TEXT-U @
                    _RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED _RTAPT-UADD? 0= IF
                    DROP 0 UNLOOP EXIT
                THEN _RTAPT-BV-FRAME !
            ELSE
                _RTAPT-BV-P @ _RTAPT-P.KIND @
                    _RTAPT-CONTROL-WRITE-OP? IF
                    _RTAPT-BV-COPY-U @ _RTAPT-CONTROL-COPY-FIXED U<
                        IF 0 UNLOOP EXIT THEN
                    _RTAPT-BV-COPY @ _RTAPT-CD.LABEL-U @ _RTAPT-U32? 0=
                    _RTAPT-BV-COPY @ _RTAPT-CD.SHORTCUT-U @
                        _RTAPT-U32? 0= OR IF 0 UNLOOP EXIT THEN
                    _RTAPT-BV-COPY @ _RTAPT-CD.LABEL-U @
                    _RTAPT-BV-COPY @ _RTAPT-CD.SHORTCUT-U @
                        _RTAPT-UADD? 0= IF DROP 0 UNLOOP EXIT THEN
                    DUP _RTAPT-BV-TEXT-U !
                    _RTAPT-CONTROL-COPY-FIXED _RTAPT-UADD? 0= IF
                        DROP 0 UNLOOP EXIT
                    THEN DUP _RTAPT-BV-RAW-U ! _RTAPT-ALIGN8? 0= IF
                        DROP 0 UNLOOP EXIT
                    THEN _RTAPT-BV-COPY-U @ <> IF 0 UNLOOP EXIT THEN
                    _RTAPT-BV-COPY @ _RTAPT-BV-RAW-U @ +
                    _RTAPT-BV-COPY-U @ _RTAPT-BV-RAW-U @ -
                        _RTAPT-ZERO-SPAN? 0= IF 0 UNLOOP EXIT THEN
                    _RTAPT-BV-TEXT-U @ _RTAPT-CONTROL-FRAME-FIXED
                        _RTAPT-UADD? 0= IF DROP 0 UNLOOP EXIT THEN
                    _RTAPT-BV-FRAME !
                ELSE
                    _RTAPT-BV-P @ _RTAPT-P.KIND @
                        _RTAPT-OP-CONTROL-DROP <> IF 0 UNLOOP EXIT THEN
                    _RTAPT-BV-COPY-U @ _RTAPT-CONTROL-DROP-COPY-SIZE <>
                        IF 0 UNLOOP EXIT THEN
                    _RTAPT-CONTROL-DROP-FRAME-BYTES _RTAPT-BV-FRAME !
                THEN
            THEN
        THEN
        _RTAPT-BV-NEXT @ _RTAPT-BV-OFF !
        _RTAPT-BV-RET @ _RTAPT-BV-FRAME @ _RTAPT-UADD?
            0= IF DROP 0 UNLOOP EXIT THEN _RTAPT-BV-RET !
    LOOP
    _RTAPT-BV-OFF @ _RTAPT-BV-E @ _RTAPT-E.COPY-USED @ =
    _RTAPT-BV-RET @ _RTAPT-BV-E @ _RTAPT-E.RET-BYTES @ = AND ;

: _RTAPT-MODE?  ( mode -- flag )
    DUP PT-RET-DELTA U< IF DROP 0 EXIT THEN
    PT-RET-LAYOUT-CONTINUE U> 0= ;

: _RTAPT-DISPOSITION?  ( disposition -- flag )
    DUP PT-COMMIT = SWAP PT-COMMIT-AND-REVEAL = OR ;

: _RTAPT-MODE-DISPOSITION?  ( mode disposition -- flag )
    DUP PT-COMMIT = IF 2DROP -1 EXIT THEN
    PT-COMMIT-AND-REVEAL <> IF DROP 0 EXIT THEN
    DUP PT-RET-REPLACE-CONTINUE =
    SWAP PT-RET-LAYOUT-CONTINUE = OR ;

: _RTAPT-CELL-MODE?  ( mode -- flag )
    DUP PT-CELL-DELTA = SWAP PT-CELL-REPLACE = OR ;

VARIABLE _RTAPT-CV-COLS
VARIABLE _RTAPT-CV-ROWS
VARIABLE _RTAPT-CV-SPANS
VARIABLE _RTAPT-CV-CELLS
VARIABLE _RTAPT-CV-MODE
VARIABLE _RTAPT-CV-MAX

: _RTAPT-CELL-COUNTS?  ( cols rows spans cells cell-mode -- flag )
    _RTAPT-CV-MODE ! _RTAPT-CV-CELLS ! _RTAPT-CV-SPANS !
    _RTAPT-CV-ROWS ! _RTAPT-CV-COLS !
    _RTAPT-CV-COLS @ DUP 0= SWAP _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-CV-ROWS @ DUP 0= SWAP _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-CV-SPANS @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-CV-CELLS @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-CV-MODE @ PT-CELL-NONE = IF
        _RTAPT-CV-SPANS @ 0= _RTAPT-CV-CELLS @ 0= AND EXIT
    THEN
    _RTAPT-CV-MODE @ _RTAPT-CELL-MODE? 0= IF 0 EXIT THEN
    _RTAPT-CV-COLS @ _RTAPT-CV-ROWS @ _RTAPT-UMUL? 0= IF
        DROP 0 EXIT
    THEN DUP _RTAPT-CV-MAX !
    _RTAPT-CV-CELLS @ U< IF 0 EXIT THEN
    _RTAPT-CV-MODE @ PT-CELL-REPLACE = IF
        _RTAPT-CV-SPANS @ _RTAPT-CV-ROWS @ =
        _RTAPT-CV-CELLS @ _RTAPT-CV-MAX @ = AND EXIT
    THEN
    _RTAPT-CV-SPANS @ 0= IF _RTAPT-CV-CELLS @ 0= EXIT THEN
    _RTAPT-CV-CELLS @ _RTAPT-CV-SPANS @ U< IF 0 EXIT THEN
    _RTAPT-CV-SPANS @ _RTAPT-CV-COLS @ _RTAPT-UMUL? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-CV-CELLS @ U< 0= ;

: _RTAPT-ZERO-CELL-GEOMETRY?  ( engine -- flag )
    DUP _RTAPT-E.COLS @ 0=
    OVER _RTAPT-E.ROWS @ 0= AND
    OVER _RTAPT-E.CELL-SPANS @ 0= AND
    OVER _RTAPT-E.CELLS @ 0= AND
    SWAP _RTAPT-E.CELL-MODE @ PT-CELL-NONE = AND ;

: _RTAPT-UPDATE-COHERENT?  ( engine -- flag )
    DUP _RTAPT-BV-E ! _RTAPT-E.UPDATE-STATE @ DUP _RTAPT-BV-STATE !
    RTAPT-UPDATE-AWAITING U> IF 0 EXIT THEN
    _RTAPT-BV-E @ _RTAPT-CAPTURED-BANKS? 0= IF 0 EXIT THEN
    _RTAPT-BV-STATE @ RTAPT-UPDATE-IDLE = IF
        _RTAPT-BV-E @ _RTAPT-E.COUPLING @ RTAPT-COUPLING-NONE =
        _RTAPT-BV-E @ _RTAPT-E.OP-COUNT @ 0= AND
        _RTAPT-BV-E @ _RTAPT-E.COPY-USED @ 0= AND
        _RTAPT-BV-E @ _RTAPT-E.RET-BYTES @ 0= AND
        _RTAPT-BV-E @ _RTAPT-E.SEND-INDEX @ 0= AND
        _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ PT-RET-NONE = AND
        _RTAPT-BV-E @ _RTAPT-E.DISPOSITION @ PT-COMMIT = AND
        _RTAPT-BV-E @ _RTAPT-ZERO-CELL-GEOMETRY? AND EXIT
    THEN
    _RTAPT-BV-STATE @ DUP RTAPT-UPDATE-CAPTURING =
    SWAP RTAPT-UPDATE-SEALED = OR IF
        _RTAPT-BV-E @ _RTAPT-E.COUPLING @ RTAPT-COUPLING-NONE <>
            IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ _RTAPT-MODE? 0= IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.RET-MODE @
        _RTAPT-BV-E @ _RTAPT-E.DISPOSITION @
            _RTAPT-MODE-DISPOSITION? 0=
            IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.SEND-INDEX @ IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-ZERO-CELL-GEOMETRY? 0= IF 0 EXIT THEN
        _RTAPT-BV-STATE @ RTAPT-UPDATE-SEALED = IF
            _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA =
            _RTAPT-BV-E @ _RTAPT-E.OP-COUNT @ 0= AND IF 0 EXIT THEN
        THEN
        -1 EXIT
    THEN
    _RTAPT-BV-E @ _RTAPT-E.COLS @
    _RTAPT-BV-E @ _RTAPT-E.ROWS @
    _RTAPT-BV-E @ _RTAPT-E.CELL-SPANS @
    _RTAPT-BV-E @ _RTAPT-E.CELLS @
    _RTAPT-BV-E @ _RTAPT-E.CELL-MODE @ _RTAPT-CELL-COUNTS? 0=
        IF 0 EXIT THEN
    _RTAPT-BV-E @ _RTAPT-E.COUPLING @ RTAPT-COUPLING-CELL = IF
        _RTAPT-BV-E @ _RTAPT-E.CELL-MODE @ _RTAPT-CELL-MODE? 0=
            IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ PT-RET-NONE = IF
            _RTAPT-BV-E @ _RTAPT-E.OP-COUNT @ 0<> IF 0 EXIT THEN
            _RTAPT-BV-E @ _RTAPT-E.COPY-USED @
            _RTAPT-BV-E @ _RTAPT-E.RET-BYTES @ OR IF 0 EXIT THEN
            _RTAPT-BV-E @ _RTAPT-E.DISPOSITION @ PT-COMMIT <>
                IF 0 EXIT THEN
        ELSE
            _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ _RTAPT-MODE? 0=
                IF 0 EXIT THEN
            _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA =
            _RTAPT-BV-E @ _RTAPT-E.OP-COUNT @ 0= AND IF 0 EXIT THEN
            _RTAPT-BV-E @ _RTAPT-E.RET-MODE @
            _RTAPT-BV-E @ _RTAPT-E.DISPOSITION @
                _RTAPT-MODE-DISPOSITION? 0=
                IF 0 EXIT THEN
        THEN
    ELSE
        _RTAPT-BV-E @ _RTAPT-E.COUPLING @ RTAPT-COUPLING-RETAINED <>
            IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.CELL-MODE @ PT-CELL-NONE <>
        _RTAPT-BV-E @ _RTAPT-E.CELL-SPANS @ OR
        _RTAPT-BV-E @ _RTAPT-E.CELLS @ OR IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ _RTAPT-MODE? 0= IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA =
        _RTAPT-BV-E @ _RTAPT-E.OP-COUNT @ 0= AND IF 0 EXIT THEN
        _RTAPT-BV-E @ _RTAPT-E.RET-MODE @
        _RTAPT-BV-E @ _RTAPT-E.DISPOSITION @
            _RTAPT-MODE-DISPOSITION? 0=
            IF 0 EXIT THEN
    THEN
    _RTAPT-BV-STATE @ RTAPT-UPDATE-AWAITING = IF
        _RTAPT-BV-E @ _RTAPT-E.SEND-INDEX @
        _RTAPT-BV-E @ _RTAPT-E.OP-COUNT @ <> IF 0 EXIT THEN
    THEN
    -1 ;

VARIABLE _RTAPT-LV-E
VARIABLE _RTAPT-LV-PENDING
VARIABLE _RTAPT-LV-O
VARIABLE _RTAPT-LV-ACTIVE-SHARED
VARIABLE _RTAPT-LV-HIDDEN-SHARED
VARIABLE _RTAPT-LV-PENDING-SHARED
VARIABLE _RTAPT-LV-AUDIT
VARIABLE _RTAPT-LV-AUDIT-OPS
VARIABLE _RTAPT-AUDIT-SCRATCH-DIRTY

VARIABLE _RTAPT-TB-ACTIVE
VARIABLE _RTAPT-TB-HIDDEN
VARIABLE _RTAPT-TB-PENDING
VARIABLE _RTAPT-TB-QUOTA
VARIABLE _RTAPT-TB-E

: _RTAPT-TARGET-BASE  ( active hidden engine -- count )
    _RTAPT-TB-E ! _RTAPT-TB-HIDDEN ! _RTAPT-TB-ACTIVE !
    _RTAPT-TB-E @ _RTAPT-E.RET-MODE @ DUP PT-RET-DELTA =
    OVER PT-RET-LAYOUT-START = OR IF
        DROP _RTAPT-TB-ACTIVE @ EXIT
    THEN
    PT-RET-REPLACE-START = IF 0 EXIT THEN
    _RTAPT-TB-HIDDEN @ ;

: _RTAPT-TARGET-COUNT?  ( active hidden pending quota engine -- flag )
    _RTAPT-TB-E ! _RTAPT-TB-QUOTA ! _RTAPT-TB-PENDING !
    _RTAPT-TB-HIDDEN ! _RTAPT-TB-ACTIVE !
    _RTAPT-TB-ACTIVE @ _RTAPT-TB-QUOTA @ U>
    _RTAPT-TB-HIDDEN @ _RTAPT-TB-QUOTA @ U> OR
    _RTAPT-TB-PENDING @ _RTAPT-TB-QUOTA @ U> OR IF 0 EXIT THEN
    _RTAPT-TB-ACTIVE @ _RTAPT-TB-HIDDEN @ _RTAPT-TB-E @
        _RTAPT-TARGET-BASE
    _RTAPT-TB-PENDING @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-TB-QUOTA @ U> 0= ;

VARIABLE _RTAPT-LH-HIGH
VARIABLE _RTAPT-LH-PENDING
VARIABLE _RTAPT-LH-PENDING-HIGH

: _RTAPT-PENDING-HIGH?  ( high pending pending-high -- flag )
    _RTAPT-LH-PENDING-HIGH ! _RTAPT-LH-PENDING ! _RTAPT-LH-HIGH !
    _RTAPT-LH-PENDING @ 0= IF _RTAPT-LH-PENDING-HIGH @ 0= EXIT THEN
    _RTAPT-LH-PENDING-HIGH @ _RTAPT-LH-HIGH @ U> ;

: _RTAPT-OWNER-AUDIT-ZERO?  ( owner-record -- flag )
    _RTAPT-OWNER-AUDIT-OFF + _RTAPT-OWNER-AUDIT-SIZE _RTAPT-ZERO-SPAN? ;

: _RTAPT-OWNER-AUDIT-MATCH?  ( -- flag )
    _RTAPT-LV-O @ _RTAPT-O.A-RCOUNT @
        _RTAPT-LV-O @ _RTAPT-O.PENDING-REGIONS @ <> IF 0 EXIT THEN
    _RTAPT-LV-O @ _RTAPT-O.A-RCOUNT @ IF
        _RTAPT-LV-O @ _RTAPT-O.A-RHIGH @
        _RTAPT-LV-O @ _RTAPT-O.PENDING-REGION-HIGH @ <> IF 0 EXIT THEN
    ELSE
        _RTAPT-LV-O @ _RTAPT-O.A-RHIGH @
        _RTAPT-LV-O @ _RTAPT-O.REGION-HIGH @ <> IF 0 EXIT THEN
    THEN
    _RTAPT-LV-O @ _RTAPT-O.A-OCOUNT @
        _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECTS @ <> IF 0 EXIT THEN
    _RTAPT-LV-O @ _RTAPT-O.A-OCOUNT @ IF
        _RTAPT-LV-O @ _RTAPT-O.A-OHIGH @
        _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECT-HIGH @ <> IF 0 EXIT THEN
    ELSE
        _RTAPT-LV-O @ _RTAPT-O.A-OHIGH @
        _RTAPT-LV-O @ _RTAPT-O.OBJECT-HIGH @ <> IF 0 EXIT THEN
    THEN
    _RTAPT-LV-O @ _RTAPT-O.A-UTF8 @
        _RTAPT-LV-O @ _RTAPT-O.PENDING-UTF8 @ <> IF 0 EXIT THEN
    _RTAPT-LV-O @ _RTAPT-O.A-CCOUNT @
        _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROLS @ <> IF 0 EXIT THEN
    _RTAPT-LV-O @ _RTAPT-O.A-CCOUNT @ IF
        _RTAPT-LV-O @ _RTAPT-O.A-CHIGH @
        _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROL-HIGH @ <> IF 0 EXIT THEN
        _RTAPT-LV-O @ _RTAPT-O.A-CBAR-COUNT @ 0= IF 0 EXIT THEN
        _RTAPT-LV-O @ _RTAPT-O.A-CPHASE @
            _RTAPT-PF-CONTROL-PHASE-NONE = IF 0 EXIT THEN
    ELSE
        _RTAPT-LV-O @ _RTAPT-O.A-CHIGH @
        _RTAPT-LV-O @ _RTAPT-O.CONTROL-HIGH @ <> IF 0 EXIT THEN
        _RTAPT-LV-O @ _RTAPT-O.A-CPHASE
        80 _RTAPT-ZERO-SPAN? 0= IF 0 EXIT THEN
    THEN
    _RTAPT-LV-AUDIT-OPS @ _RTAPT-LV-O @ _RTAPT-O.A-OPS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LV-AUDIT-OPS !
    _RTAPT-LV-O @ _RTAPT-O.STATE @ RTAPT-OWNER-ST-QUARANTINED =
    _RTAPT-LV-E @ _RTAPT-E.ACTIVE-KIND @
        _RTAPT-ACTIVE-QUARANTINED = <> IF 0 EXIT THEN
    -1 ;

: _RTAPT-OWNER-LEDGERS-FROM?  ( nondefinition-ops audit? engine -- flag )
    _RTAPT-LV-E ! _RTAPT-LV-AUDIT ! _RTAPT-LV-PENDING !
    0 _RTAPT-LV-AUDIT-OPS !
    _RTAPT-LV-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-LV-E @ _RTAPT-E.OWNERS-A @ I RTAPT-OWNER-SIZE * +
        DUP _RTAPT-LV-O ! _RTAPT-O.STATE @ RTAPT-OWNER-ST-FREE = IF
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-REGIONS @
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-REGIONS @ OR
            _RTAPT-LV-O @ _RTAPT-O.REGION-HIGH @ OR
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGIONS @ OR
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGION-HIGH @ OR
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-OBJECTS @ OR
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-OBJECTS @ OR
            _RTAPT-LV-O @ _RTAPT-O.OBJECT-HIGH @ OR
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-UTF8 @ OR
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-UTF8 @ OR
            _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECTS @ OR
            _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECT-HIGH @ OR
            _RTAPT-LV-O @ _RTAPT-O.PENDING-UTF8 @ OR IF
                0 UNLOOP EXIT
            THEN
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-CONTROLS @
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-CONTROLS @ OR
            _RTAPT-LV-O @ _RTAPT-O.CONTROL-HIGH @ OR
            _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROLS @ OR
            _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROL-HIGH @ OR IF
                0 UNLOOP EXIT
            THEN
            _RTAPT-LV-O @ _RTAPT-OWNER-AUDIT-ZERO? 0= IF
                0 UNLOOP EXIT
            THEN
        ELSE
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-REGIONS @
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-REGIONS @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGIONS @
            _RTAPT-LV-O @ _RTAPT-O.REGIONS @ _RTAPT-LV-E @
                _RTAPT-TARGET-COUNT? 0= IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.REGION-HIGH @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGIONS @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGION-HIGH @
                _RTAPT-PENDING-HIGH? 0= IF 0 UNLOOP EXIT THEN

            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-OBJECTS @
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-CONTROLS @ _RTAPT-UADD? 0= IF
                DROP 0 UNLOOP EXIT
            THEN _RTAPT-LV-ACTIVE-SHARED !
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-OBJECTS @
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-CONTROLS @ _RTAPT-UADD? 0= IF
                DROP 0 UNLOOP EXIT
            THEN _RTAPT-LV-HIDDEN-SHARED !
            _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECTS @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROLS @ _RTAPT-UADD? 0= IF
                DROP 0 UNLOOP EXIT
            THEN _RTAPT-LV-PENDING-SHARED !
            _RTAPT-LV-ACTIVE-SHARED @
            _RTAPT-LV-HIDDEN-SHARED @
            _RTAPT-LV-PENDING-SHARED @
            _RTAPT-LV-O @ _RTAPT-O.OBJECTS @ _RTAPT-LV-E @
                _RTAPT-TARGET-COUNT? 0= IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.OBJECT-HIGH @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECTS @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECT-HIGH @
                _RTAPT-PENDING-HIGH? 0= IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.CONTROL-HIGH @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROLS @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROL-HIGH @
                _RTAPT-PENDING-HIGH? 0= IF 0 UNLOOP EXIT THEN

            \ Every retained glyph object or control belongs to a region.  Each
            \ staged definition has already proved a staged REGION, so the same
            \ implication holds independently for active, hidden, and pending
            \ targets.
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-REGIONS @ 0=
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-OBJECTS @ 0<> AND
                IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-REGIONS @ 0=
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-OBJECTS @ 0<> AND
                IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGIONS @ 0=
            _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECTS @ 0<> AND
                IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-REGIONS @ 0=
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-CONTROLS @ 0<> AND
                IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-REGIONS @ 0=
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-CONTROLS @ 0<> AND
                IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGIONS @ 0=
            _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROLS @ 0<> AND
                IF 0 UNLOOP EXIT THEN

            \ A zero-text glyph/control contributes an identity but no UTF-8
            \ bytes.  The reverse state is impossible.
            _RTAPT-LV-ACTIVE-SHARED @ 0=
            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-UTF8 @ 0<> AND
                IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-HIDDEN-SHARED @ 0=
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-UTF8 @ 0<> AND
                IF 0 UNLOOP EXIT THEN
            _RTAPT-LV-PENDING-SHARED @ 0=
            _RTAPT-LV-O @ _RTAPT-O.PENDING-UTF8 @ 0<> AND IF
                0 UNLOOP EXIT
            THEN

            _RTAPT-LV-O @ _RTAPT-O.ACTIVE-UTF8 @
            _RTAPT-LV-O @ _RTAPT-O.HIDDEN-UTF8 @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-UTF8 @
            _RTAPT-LV-O @ _RTAPT-O.UTF8-BYTES @ _RTAPT-LV-E @
                _RTAPT-TARGET-COUNT? 0= IF 0 UNLOOP EXIT THEN

            _RTAPT-LV-AUDIT @ IF
                _RTAPT-OWNER-AUDIT-MATCH? 0= IF 0 UNLOOP EXIT THEN
            ELSE
                _RTAPT-LV-O @ _RTAPT-OWNER-AUDIT-ZERO? 0= IF
                    0 UNLOOP EXIT
                THEN
            THEN

            _RTAPT-LV-PENDING @
            _RTAPT-LV-O @ _RTAPT-O.PENDING-REGIONS @ _RTAPT-UADD? 0= IF
                DROP 0 UNLOOP EXIT
            THEN
            _RTAPT-LV-O @ _RTAPT-O.PENDING-OBJECTS @ _RTAPT-UADD? 0= IF
                DROP 0 UNLOOP EXIT
            THEN
            _RTAPT-LV-O @ _RTAPT-O.PENDING-CONTROLS @ _RTAPT-UADD? 0= IF
                DROP 0 UNLOOP EXIT
            THEN _RTAPT-LV-PENDING !
        THEN
        _RTAPT-LV-AUDIT @ IF
            _RTAPT-LV-O @ _RTAPT-OWNER-AUDIT-OFF +
                _RTAPT-OWNER-AUDIT-SIZE 0 FILL
        THEN
    LOOP
    _RTAPT-LV-AUDIT @ IF 0 _RTAPT-AUDIT-SCRATCH-DIRTY ! THEN
    _RTAPT-LV-PENDING @ _RTAPT-LV-E @ _RTAPT-E.OP-COUNT @ =
    _RTAPT-LV-AUDIT @ IF
        _RTAPT-LV-AUDIT-OPS @ _RTAPT-LV-E @ _RTAPT-E.OP-COUNT @ = AND
    THEN ;

: _RTAPT-OWNER-LEDGERS?  ( engine -- flag )
    DUP _RTAPT-LV-E ! 0 _RTAPT-LV-PENDING !
    \ Replacement/drop operations consume transaction capacity but add no
    \ retained identities.  Count those typed records directly; definition
    \ additions remain cross-checked against their per-owner pending ledgers.
    _RTAPT-LV-E @ _RTAPT-E.OP-COUNT @ 0 ?DO
        I _RTAPT-LV-E @ _RTAPT-OP-NTH _RTAPT-P.KIND @
        DUP _RTAPT-OP-GLYPH-RUN-REPLACE =
        OVER _RTAPT-OP-CONTROL-REPLACE = OR
        SWAP _RTAPT-OP-CONTROL-DROP = OR IF
            1 _RTAPT-LV-PENDING +!
        THEN
    LOOP
    DROP _RTAPT-LV-PENDING @ 0 _RTAPT-LV-E @
        _RTAPT-OWNER-LEDGERS-FROM? ;

VARIABLE _RTAPT-QV-E
VARIABLE _RTAPT-QV-EXPECT
VARIABLE _RTAPT-QV-OK

: _RTAPT-QUARANTINE-COHERENT?  ( engine -- flag )
    DUP _RTAPT-QV-E ! _RTAPT-E.ACTIVE-KIND @
        _RTAPT-ACTIVE-QUARANTINED = _RTAPT-QV-EXPECT !
    -1 _RTAPT-QV-OK !
    _RTAPT-QV-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-QV-E @ _RTAPT-E.OWNERS-A @ I RTAPT-OWNER-SIZE * +
        _RTAPT-O.STATE @ DUP RTAPT-OWNER-ST-FREE = IF
            DROP
        ELSE
            RTAPT-OWNER-ST-QUARANTINED = _RTAPT-QV-EXPECT @ <> IF
                0 _RTAPT-QV-OK !
            THEN
        THEN
    LOOP
    _RTAPT-QV-OK @ ;

\ Validate only the fixed engine geometry and the bounded mutable tails.  This
\ predicate is deliberately loop-free: capture/feed calls use it to prove that
\ their next write is safe, while the full validator below audits every
\ already-captured operation and owner ledger at lifecycle boundaries.
: _RTAPT-ENGINE-STORAGE?  ( e -- flag )
    DUP RTAPT-ENGINE-SIZE _RTAPT-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.MAGIC @ _RTAPT-ENGINE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _RTAPT-ENGINE-RANGES? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OWNERS-U @ RTAPT-OWNER-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OPS-U @ RTAPT-OP-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OWNER-CAP @ OVER _RTAPT-E.OWNERS-U @ RTAPT-OWNER-SIZE / <>
        IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OP-CAP @ OVER _RTAPT-E.OPS-U @ RTAPT-OP-SIZE / <>
        IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OWNER-USED @ OVER _RTAPT-E.OWNER-CAP @ U> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OP-COUNT @ _RTAPT-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.OP-COUNT @ OVER _RTAPT-E.OP-CAP @ U> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.COPY-USED @ OVER _RTAPT-E.COPY-U @ U> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.SEND-INDEX @ OVER _RTAPT-E.OP-COUNT @ U> IF DROP 0 EXIT THEN
    DROP -1 ;

\ RICH-BEGIN establishes this exact quiescent construction phase.  Appenders
\ recheck its fixed state and bounded tails without rescanning the growing
\ prefix; the sole exhaustive audit runs at final publication COMMIT.
: _RTAPT-CAPTURE-READY?  ( e -- flag )
    DUP _RTAPT-ENGINE-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CAPTURING <>
        IF DROP 0 EXIT THEN
    DUP _RTAPT-E.COUPLING @ RTAPT-COUPLING-NONE <> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.SEND-INDEX @ IF DROP 0 EXIT THEN
    DUP _RTAPT-ZERO-CELL-GEOMETRY? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.RET-MODE @ _RTAPT-MODE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.RET-MODE @ OVER _RTAPT-E.DISPOSITION @
        _RTAPT-MODE-DISPOSITION? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-O @
    OVER _RTAPT-E.QUEUE-HEAD @ OR
    OVER _RTAPT-E.QUEUE-TAIL @ OR IF DROP 0 EXIT THEN
    DROP -1 ;

\ Appenders have admitted every captured record.  Queries and PRESENT-BEGIN
\ need only prove that the fixed descriptor still names the sealed, quiescent
\ candidate.  The retry banks remain caller-owned, so their sole exhaustive
\ mutation-safety audit is deliberately deferred to final COMMIT.
: _RTAPT-SEALED-READY?  ( e -- flag )
    DUP _RTAPT-ENGINE-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-SEALED <>
        IF DROP 0 EXIT THEN
    DUP _RTAPT-E.COUPLING @ RTAPT-COUPLING-NONE <> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.SEND-INDEX @ IF DROP 0 EXIT THEN
    DUP _RTAPT-ZERO-CELL-GEOMETRY? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.RET-MODE @ _RTAPT-MODE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.RET-MODE @ OVER _RTAPT-E.DISPOSITION @
        _RTAPT-MODE-DISPOSITION? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.RET-MODE @ PT-RET-DELTA =
    OVER _RTAPT-E.OP-COUNT @ 0= AND IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-O @
    OVER _RTAPT-E.QUEUE-HEAD @ OR
    OVER _RTAPT-E.QUEUE-TAIL @ OR IF DROP 0 EXIT THEN
    DROP -1 ;

: _RTAPT-ENGINE-VALID?  ( e -- flag )
    DUP _RTAPT-ENGINE-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-UPDATE-COHERENT? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-OWNER-LEDGERS? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-QUARANTINE-COHERENT? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.QUEUE-HEAD @ OVER _RTAPT-OWNER-POINTER-OR-ZERO? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RTAPT-E.QUEUE-TAIL @ OVER _RTAPT-OWNER-POINTER-OR-ZERO? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RTAPT-E.ACTIVE-O @ OVER _RTAPT-OWNER-POINTER-OR-ZERO? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RTAPT-E.QUEUE-HEAD @ 0= OVER _RTAPT-E.QUEUE-TAIL @ 0= <> IF
        DROP 0 EXIT
    THEN
    DUP _RTAPT-E.QUEUE-HEAD @ ?DUP IF
        _RTAPT-O.STATE @ DUP RTAPT-OWNER-ST-OPEN-QUEUED =
        OVER RTAPT-OWNER-ST-DROP-QUEUED = OR
        OVER RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED = OR
        OVER RTAPT-OWNER-ST-DROP-RETRY-QUEUED = OR
        SWAP RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED = OR 0= IF
            DROP 0 EXIT
        THEN
    THEN
    DUP _RTAPT-E.QUEUE-TAIL @ ?DUP IF
        _RTAPT-O.STATE @ DUP RTAPT-OWNER-ST-OPEN-QUEUED =
        OVER RTAPT-OWNER-ST-DROP-QUEUED = OR
        OVER RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED = OR
        OVER RTAPT-OWNER-ST-DROP-RETRY-QUEUED = OR
        SWAP RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED = OR 0= IF
            DROP 0 EXIT
        THEN
    THEN
    DUP _RTAPT-E.QUEUE-TAIL @ ?DUP IF _RTAPT-O.NEXT @ IF DROP 0 EXIT THEN THEN
    DUP _RTAPT-E.ACTIVE-KIND @ DUP _RTAPT-ACTIVE-QUARANTINED U> IF
        2DROP 0 EXIT
    THEN
    DUP _RTAPT-ACTIVE-NONE = IF
        DROP
        DUP _RTAPT-E.ACTIVE-O @ IF DROP 0 EXIT THEN
    ELSE DUP _RTAPT-ACTIVE-QUARANTINED = IF
        DROP
        DUP _RTAPT-E.ACTIVE-O @ IF DROP 0 EXIT THEN
        DUP _RTAPT-E.QUEUE-HEAD @ OVER _RTAPT-E.QUEUE-TAIL @ OR IF
            DROP 0 EXIT
        THEN
        DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <> IF DROP 0 EXIT THEN
    ELSE DUP _RTAPT-ACTIVE-OUTPUT = IF
        DROP
        DUP _RTAPT-E.ACTIVE-O @ IF DROP 0 EXIT THEN
        DUP _RTAPT-E.QUEUE-HEAD @ OVER _RTAPT-E.QUEUE-TAIL @ OR IF
            DROP 0 EXIT
        THEN
    ELSE
        DROP
        DUP _RTAPT-E.ACTIVE-O @ 0= IF DROP 0 EXIT THEN
    THEN THEN THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-OWNER-OPEN = IF
        DUP _RTAPT-E.ACTIVE-O @ _RTAPT-O.STATE @ DUP
            RTAPT-OWNER-ST-OPENING =
        SWAP RTAPT-OWNER-ST-TOMBSTONE-OPENING = OR 0= IF DROP 0 EXIT THEN
    THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-OWNER-DROP = IF
        DUP _RTAPT-E.ACTIVE-O @ _RTAPT-O.STATE @ DUP
            RTAPT-OWNER-ST-DROPPING =
        OVER RTAPT-OWNER-ST-TOMBSTONE-DROPPING = OR
        SWAP RTAPT-OWNER-ST-DROP-RETRY-DROPPING = OR 0= IF DROP 0 EXIT THEN
    THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <> IF
        DUP _RTAPT-E.QUEUE-HEAD @ OVER _RTAPT-E.QUEUE-TAIL @ OR IF
            DROP 0 EXIT
        THEN
        DUP _RTAPT-E.ACTIVE-KIND @ DUP _RTAPT-ACTIVE-NONE =
        SWAP _RTAPT-ACTIVE-OUTPUT = OR
        OVER _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = OR 0= IF
            DROP 0 EXIT
        THEN
    THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-AWAITING =
    OVER _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-OUTPUT = <> IF
        DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED <> IF
            DROP 0 EXIT
        THEN
    THEN
    DROP -1 ;

: RTAPT-INIT  ( config engine -- status )
    _RTAPT-I-E ! _RTAPT-I-C !
    _RTAPT-I-C @ _RTAPT-CONFIG-VALID? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-ENGINE-DISJOINT? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-I-E @ _RTAPT-E.MAGIC @ _RTAPT-ENGINE-MAGIC = IF
        RTAPT-S-BUSY EXIT
    THEN
    _RTAPT-CI-S @ PT-RETAINED-DISCOVER _RTAPT-PT>STATUS
    DUP RTAPT-S-OK <> IF EXIT THEN DROP

    _RTAPT-CI-OA @ _RTAPT-CI-OU @ 0 FILL
    _RTAPT-CI-PA @ _RTAPT-CI-PU @ 0 FILL
    _RTAPT-CI-CA @ _RTAPT-CI-CU @ 0 FILL
    _RTAPT-I-E @ RTAPT-ENGINE-SIZE 0 FILL
    _RTAPT-CI-S @ _RTAPT-I-E @ _RTAPT-E.SESSION !
    _RTAPT-CI-OA @ _RTAPT-I-E @ _RTAPT-E.OWNERS-A !
    _RTAPT-CI-OU @ _RTAPT-I-E @ _RTAPT-E.OWNERS-U !
    _RTAPT-CI-OU @ RTAPT-OWNER-SIZE /
        _RTAPT-I-E @ _RTAPT-E.OWNER-CAP !
    _RTAPT-CI-PA @ _RTAPT-I-E @ _RTAPT-E.OPS-A !
    _RTAPT-CI-PU @ _RTAPT-I-E @ _RTAPT-E.OPS-U !
    _RTAPT-CI-PU @ RTAPT-OP-SIZE / _RTAPT-I-E @ _RTAPT-E.OP-CAP !
    _RTAPT-CI-CA @ _RTAPT-I-E @ _RTAPT-E.COPY-A !
    _RTAPT-CI-CU @ _RTAPT-I-E @ _RTAPT-E.COPY-U !
    RTAPT-UPDATE-IDLE _RTAPT-I-E @ _RTAPT-E.UPDATE-STATE !
    RTAPT-S-OK _RTAPT-I-E @ _RTAPT-E.LAST-STATUS !
    _RTAPT-ENGINE-MAGIC _RTAPT-I-E @ _RTAPT-E.MAGIC !
    RTAPT-S-OK ;

: RTAPT-STATUS  ( engine -- status )
    \ Observing the sticky status must not audit an unrelated captured bank.
    DUP _RTAPT-ENGINE-STORAGE? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    _RTAPT-E.LAST-STATUS @ ;

: RTAPT-VALID?  ( engine -- flag )
    _RTAPT-ENGINE-VALID? ;

VARIABLE _RTAPT-QA-E
VARIABLE _RTAPT-QA-STATUS
VARIABLE _RTAPT-QA-O

\ Preserve every committed tuple, quota, high-water, and target ledger while
\ making all bindings unusable.  Uncommitted update/pending authority is
\ discarded, and queue/active reachability is detached before publication of
\ the sticky engine state, so no quarantined request can later reach PT.
: _RTAPT-QUARANTINE-ALL  ( status engine -- status )
    _RTAPT-QA-E ! _RTAPT-QA-STATUS !
    _RTAPT-QA-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-QA-E @ _RTAPT-E.OWNERS-A @ I RTAPT-OWNER-SIZE * +
        DUP _RTAPT-QA-O ! _RTAPT-O.STATE @ RTAPT-OWNER-ST-FREE <> IF
            RTAPT-OWNER-ST-QUARANTINED _RTAPT-QA-O @ _RTAPT-O.STATE !
            0 _RTAPT-QA-O @ _RTAPT-O.NEXT !
            0 _RTAPT-QA-O @ _RTAPT-O.PENDING-REGIONS !
            0 _RTAPT-QA-O @ _RTAPT-O.PENDING-REGION-HIGH !
            0 _RTAPT-QA-O @ _RTAPT-O.PENDING-OBJECTS !
            0 _RTAPT-QA-O @ _RTAPT-O.PENDING-OBJECT-HIGH !
            0 _RTAPT-QA-O @ _RTAPT-O.PENDING-UTF8 !
            0 _RTAPT-QA-O @ _RTAPT-O.PENDING-CONTROLS !
            0 _RTAPT-QA-O @ _RTAPT-O.PENDING-CONTROL-HIGH !
        THEN
    LOOP
    0 _RTAPT-QA-E @ _RTAPT-E.QUEUE-HEAD !
    0 _RTAPT-QA-E @ _RTAPT-E.QUEUE-TAIL !
    0 _RTAPT-QA-E @ _RTAPT-E.ACTIVE-O !
    RTAPT-UPDATE-IDLE _RTAPT-QA-E @ _RTAPT-E.UPDATE-STATE !
    RTAPT-COUPLING-NONE _RTAPT-QA-E @ _RTAPT-E.COUPLING !
    0 _RTAPT-QA-E @ _RTAPT-E.COLS !
    0 _RTAPT-QA-E @ _RTAPT-E.ROWS !
    0 _RTAPT-QA-E @ _RTAPT-E.CELL-SPANS !
    0 _RTAPT-QA-E @ _RTAPT-E.CELLS !
    PT-CELL-NONE _RTAPT-QA-E @ _RTAPT-E.CELL-MODE !
    PT-RET-NONE _RTAPT-QA-E @ _RTAPT-E.RET-MODE !
    PT-COMMIT _RTAPT-QA-E @ _RTAPT-E.DISPOSITION !
    0 _RTAPT-QA-E @ _RTAPT-E.OP-COUNT !
    0 _RTAPT-QA-E @ _RTAPT-E.COPY-USED !
    0 _RTAPT-QA-E @ _RTAPT-E.RET-BYTES !
    0 _RTAPT-QA-E @ _RTAPT-E.SEND-INDEX !
    _RTAPT-ACTIVE-QUARANTINED _RTAPT-QA-E @ _RTAPT-E.ACTIVE-KIND !
    _RTAPT-QA-STATUS @ DUP _RTAPT-QA-E @ _RTAPT-E.LAST-STATUS ! ;

: _RTAPT-SESSION-ENDED?  ( engine -- flag )
    _RTAPT-E.SESSION @ DUP PT-STATE@ PT-ST-ANSI =
    SWAP PT-OWNS? 0= AND ;

: _RTAPT-READY-STATUS  ( engine -- status )
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    DUP _RTAPT-E.SESSION @ PT-STATE@ PT-ST-LOST = IF
        RTAPT-S-SESSION-LOST SWAP _RTAPT-QUARANTINE-ALL EXIT
    THEN
    DUP _RTAPT-E.OWNER-USED @
    OVER _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <> OR
    OVER _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-OUTPUT = OR IF
        DUP _RTAPT-SESSION-ENDED? IF
            RTAPT-S-SESSION-LOST SWAP _RTAPT-QUARANTINE-ALL EXIT
        THEN
    THEN
    _RTAPT-E.SESSION @ PT-RETAINED-STATE@
    DUP PT-RET-ST-AVAILABLE = IF DROP RTAPT-S-OK EXIT THEN
    PT-RET-ST-CELL-ONLY = IF RTAPT-S-UNSUPPORTED ELSE
        RTAPT-S-WOULD-BLOCK
    THEN ;

\ =====================================================================
\  Immutable negotiated-limit snapshot
\ =====================================================================

: _RTAPT-POSITIVE-EXACT?  ( value feature-present? -- flag )
    IF 0<> ELSE 0= THEN ;

VARIABLE _RTAPT-LV-L
VARIABLE _RTAPT-LV-FEATURES

: _RTAPT-LIMIT-FLOOR?  ( required limits -- flag )
    _RTAPT-L.UPDATE-BYTES @ U> 0= ;

: _RTAPT-LIMITS-VALID-BODY  ( limits -- flag )
    DUP RTAPT-LIMITS-SIZE _RTAPT-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-LV-L !
    _RTAPT-L.FEATURES @ DUP _RTAPT-LV-FEATURES !
    DUP _RTAPT-FEATURE-MASK INVERT AND IF DROP 0 EXIT THEN
    DUP RTAPT-F-CORE AND 0= IF DROP 0 EXIT THEN
    DUP RTAPT-F-SERIES AND SWAP RTAPT-F-INSTRUMENT AND 0= AND IF
        0 EXIT
    THEN

    _RTAPT-LV-L @ _RTAPT-L.OWNER-RECORDS @ 0=
    _RTAPT-LV-L @ _RTAPT-L.LIVE-OWNERS @ 0= OR
    _RTAPT-LV-L @ _RTAPT-L.REGIONS @ 0= OR
    _RTAPT-LV-L @ _RTAPT-L.OPS @ 0= OR
    _RTAPT-LV-L @ _RTAPT-L.UPDATE-BYTES @ 248 U< OR IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.LIVE-OWNERS @
    _RTAPT-LV-L @ _RTAPT-L.OWNER-RECORDS @ U> IF 0 EXIT THEN

    _RTAPT-LV-L @ _RTAPT-L.RESOURCES @
    _RTAPT-LV-FEATURES @ RTAPT-F-IMAGE AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.CHUNK-BYTES @
    _RTAPT-LV-FEATURES @ RTAPT-F-IMAGE AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.RESOURCE-BYTES @
    _RTAPT-LV-FEATURES @ RTAPT-F-IMAGE AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.IMAGE-WIDTH @
    _RTAPT-LV-FEATURES @ RTAPT-F-IMAGE AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.IMAGE-HEIGHT @
    _RTAPT-LV-FEATURES @ RTAPT-F-IMAGE AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN

    _RTAPT-LV-FEATURES @
        RTAPT-F-VECTOR RTAPT-F-IMAGE OR RTAPT-F-INSTRUMENT OR
        RTAPT-F-SERIES OR RTAPT-F-CONTROLS OR AND IF
        _RTAPT-LV-L @ _RTAPT-L.OBJECTS @ 0= IF 0 EXIT THEN
    THEN
    _RTAPT-LV-L @ _RTAPT-L.PATH-POINTS @
    _RTAPT-LV-FEATURES @ RTAPT-F-VECTOR AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.GLYPH-RUN-BYTES @ ?DUP IF
        _RTAPT-LV-L @ _RTAPT-L.OBJECTS @ 0= IF DROP 0 EXIT THEN
        DUP _RTAPT-LV-L @ _RTAPT-L.UTF8-BYTES @ U> IF DROP 0 EXIT THEN
        280 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        _RTAPT-LV-L @ _RTAPT-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    ELSE
        _RTAPT-LV-FEATURES @ RTAPT-F-INSTRUMENT AND IF 0 EXIT THEN
        _RTAPT-LV-FEATURES @ RTAPT-F-CONTROLS AND IF
            _RTAPT-LV-L @ _RTAPT-L.UTF8-BYTES @ 0= IF 0 EXIT THEN
        ELSE
            _RTAPT-LV-L @ _RTAPT-L.UTF8-BYTES @ IF 0 EXIT THEN
        THEN
    THEN

    _RTAPT-LV-L @ _RTAPT-L.SERIES @
    _RTAPT-LV-FEATURES @ RTAPT-F-SERIES AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.SAMPLES-APPEND @
    _RTAPT-LV-FEATURES @ RTAPT-F-SERIES AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.SERIES-HISTORY @
    _RTAPT-LV-FEATURES @ RTAPT-F-SERIES AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.SAMPLE-SLOTS @
    _RTAPT-LV-FEATURES @ RTAPT-F-SERIES AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-FEATURES @ RTAPT-F-SERIES AND IF
        _RTAPT-LV-L @ _RTAPT-L.SAMPLES-APPEND @
        _RTAPT-LV-L @ _RTAPT-L.SERIES-HISTORY @ U> IF 0 EXIT THEN
        _RTAPT-LV-L @ _RTAPT-L.SERIES-HISTORY @
        _RTAPT-LV-L @ _RTAPT-L.SAMPLE-SLOTS @ U> IF 0 EXIT THEN
    THEN
    _RTAPT-LV-L @ _RTAPT-L.MIN-INTERVAL-US @
    _RTAPT-LV-FEATURES @ RTAPT-F-CADENCE AND 0<>
        _RTAPT-POSITIVE-EXACT? 0= IF 0 EXIT THEN
    _RTAPT-LV-L @ _RTAPT-L.OUTBOUND-PAYLOAD @ 0= IF 0 EXIT THEN
    _RTAPT-LV-FEATURES @ RTAPT-F-CONTROLS AND IF
        _RTAPT-LV-L @ _RTAPT-L.OUTBOUND-PAYLOAD @ 80 U< IF 0 EXIT THEN
        280 _RTAPT-LV-L @ _RTAPT-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN

    _RTAPT-LV-FEATURES @ RTAPT-F-IMAGE AND IF
        _RTAPT-LV-L @ _RTAPT-L.IMAGE-WIDTH @
        _RTAPT-LV-L @ _RTAPT-L.IMAGE-HEIGHT @ _RTAPT-UMUL? 0= IF
            DROP 0 EXIT
        THEN
        4 _RTAPT-UMUL? 0= IF DROP 0 EXIT THEN
        _RTAPT-LV-L @ _RTAPT-L.RESOURCE-BYTES @ U> IF 0 EXIT THEN
        280 _RTAPT-LV-L @ _RTAPT-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    _RTAPT-LV-FEATURES @ RTAPT-F-VECTOR AND IF
        _RTAPT-LV-L @ _RTAPT-L.PATH-POINTS @ 8 _RTAPT-UMUL? 0= IF
            DROP 0 EXIT
        THEN
        280 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        _RTAPT-LV-L @ _RTAPT-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    _RTAPT-LV-FEATURES @ RTAPT-F-INSTRUMENT AND IF
        _RTAPT-LV-L @ _RTAPT-L.GLYPH-RUN-BYTES @ 304 _RTAPT-UADD? 0= IF
            DROP 0 EXIT
        THEN
        312 MAX _RTAPT-LV-L @ _RTAPT-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    _RTAPT-LV-FEATURES @ RTAPT-F-SERIES AND IF
        _RTAPT-LV-L @ _RTAPT-L.SAMPLES-APPEND @ 16 _RTAPT-UMUL? 0= IF
            DROP 0 EXIT
        THEN
        240 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        312 MAX _RTAPT-LV-L @ _RTAPT-LIMIT-FLOOR? 0= IF 0 EXIT THEN
    THEN
    -1 ;

: RTAPT-LIMITS-VALID?  ( limits -- flag )
    DUP _RTAPT-LV-L !
    _RTAPT-LIMITS-VALID-BODY
    0 _RTAPT-LV-L !
    0 _RTAPT-LV-FEATURES ! ;

: _RTAPT-LE64@  ( a -- u )
    DUP L@ SWAP 4 + L@ 32 LSHIFT OR ;

VARIABLE _RTAPT-LS-E
VARIABLE _RTAPT-LS-CAPS-A
VARIABLE _RTAPT-LS-CAPS-U
VARIABLE _RTAPT-LS-FORMATS-A
VARIABLE _RTAPT-LS-FORMATS-U

: _RTAPT-LIMITS-SCRUB  ( -- )
    0 _RTAPT-LS-E !
    0 _RTAPT-LS-CAPS-A !
    0 _RTAPT-LS-CAPS-U !
    0 _RTAPT-LS-FORMATS-A !
    0 _RTAPT-LS-FORMATS-U ! ;

: _RTAPT-LIMITS-COPY  ( -- limits )
    _RTAPT-LS-E @ _RTAPT-E.LIMITS DUP RTAPT-LIMITS-SIZE 0 FILL
    _RTAPT-LS-CAPS-A @ 8 + _RTAPT-LE64@ DUP 0x3F AND
    SWAP _RTAPT-PT-F-CONTROLS AND IF RTAPT-F-CONTROLS OR THEN
        OVER _RTAPT-L.FEATURES !
    _RTAPT-LS-CAPS-A @ 16 + L@ OVER _RTAPT-L.OWNER-RECORDS !
    _RTAPT-LS-CAPS-A @ 20 + L@ OVER _RTAPT-L.LIVE-OWNERS !
    _RTAPT-LS-CAPS-A @ 24 + L@ OVER _RTAPT-L.REGIONS !
    _RTAPT-LS-CAPS-A @ 28 + L@ OVER _RTAPT-L.RESOURCES !
    _RTAPT-LS-CAPS-A @ 32 + L@ OVER _RTAPT-L.OBJECTS !
    _RTAPT-LS-CAPS-A @ 36 + L@ OVER _RTAPT-L.SERIES !
    _RTAPT-LS-CAPS-A @ 40 + L@ OVER _RTAPT-L.OPS !
    _RTAPT-LS-CAPS-A @ 48 + _RTAPT-LE64@
        OVER _RTAPT-L.UPDATE-BYTES !
    _RTAPT-LS-CAPS-A @ 44 + L@ OVER _RTAPT-L.CHUNK-BYTES !
    _RTAPT-LS-CAPS-A @ 56 + _RTAPT-LE64@
        OVER _RTAPT-L.RESOURCE-BYTES !
    _RTAPT-LS-FORMATS-A @ 12 + L@ OVER _RTAPT-L.IMAGE-WIDTH !
    _RTAPT-LS-FORMATS-A @ 16 + L@ OVER _RTAPT-L.IMAGE-HEIGHT !
    _RTAPT-LS-FORMATS-A @ 20 + L@ OVER _RTAPT-L.PATH-POINTS !
    _RTAPT-LS-FORMATS-A @ 24 + L@ OVER _RTAPT-L.GLYPH-RUN-BYTES !
    _RTAPT-LS-FORMATS-A @ 48 + _RTAPT-LE64@
        OVER _RTAPT-L.UTF8-BYTES !
    _RTAPT-LS-FORMATS-A @ 28 + L@ OVER _RTAPT-L.SAMPLES-APPEND !
    _RTAPT-LS-FORMATS-A @ 32 + L@ OVER _RTAPT-L.SERIES-HISTORY !
    _RTAPT-LS-FORMATS-A @ 40 + _RTAPT-LE64@
        OVER _RTAPT-L.SAMPLE-SLOTS !
    _RTAPT-LS-FORMATS-A @ 36 + L@ OVER _RTAPT-L.MIN-INTERVAL-US !
    _RTAPT-LS-E @ _RTAPT-E.SESSION @ PT-OUTBOUND-MAX-PAYLOAD@
        OVER _RTAPT-L.OUTBOUND-PAYLOAD ! ;

\ Return one call-borrowed provider snapshot.  PT's raw reply addresses are
\ consumed synchronously, copied into the engine, and scrubbed before return.
\ Pending discovery is WOULD_BLOCK; the deterministic CELL-only result is
\ UNSUPPORTED; structural loss is SESSION_LOST.
: _RTAPT-LIMITS-AFTER-VALID@  ( engine -- limits status )
    _RTAPT-LS-E !
    _RTAPT-LS-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF
        0 SWAP _RTAPT-LIMITS-SCRUB EXIT
    THEN DROP
    _RTAPT-LS-E @ _RTAPT-E.SESSION @ PT-RETAINED-CAPS@
    _RTAPT-LS-CAPS-U ! _RTAPT-LS-CAPS-A !
    _RTAPT-LS-E @ _RTAPT-E.SESSION @ PT-RETAINED-FORMATS@
    _RTAPT-LS-FORMATS-U ! _RTAPT-LS-FORMATS-A !
    _RTAPT-LS-CAPS-A @ 0=
    _RTAPT-LS-FORMATS-A @ 0= OR
    _RTAPT-LS-CAPS-U @ 64 <> OR
    _RTAPT-LS-FORMATS-U @ 64 <> OR IF
        0 RTAPT-S-INVALID _RTAPT-LIMITS-SCRUB EXIT
    THEN
    _RTAPT-LIMITS-COPY
    DUP RTAPT-LIMITS-VALID? 0= IF
        RTAPT-LIMITS-SIZE 0 FILL
        0 RTAPT-S-INVALID _RTAPT-LIMITS-SCRUB EXIT
    THEN
    RTAPT-S-OK _RTAPT-LIMITS-SCRUB ;

: RTAPT-LIMITS@  ( engine -- limits status )
    DUP _RTAPT-ENGINE-VALID? 0= IF
        DROP 0 RTAPT-S-INVALID _RTAPT-LIMITS-SCRUB EXIT
    THEN
    _RTAPT-LIMITS-AFTER-VALID@ ;

: RTAPT-FINI  ( engine -- status )
    DUP _RTAPT-ENGINE-VALID? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    \ Live PT ownership keeps exact tombstone/quarantine evidence resident.
    \ Only a synchronized ANSI boundary with this session unowned proves that
    \ all remote generations are gone and permits local record erasure.
    DUP _RTAPT-E.OWNER-USED @
    OVER _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> OR
    OVER _RTAPT-E.QUEUE-HEAD @ OR OVER _RTAPT-E.QUEUE-TAIL @ OR
    OVER _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <> OR IF
        DUP _RTAPT-SESSION-ENDED? 0= IF DROP RTAPT-S-BUSY EXIT THEN
    THEN
    DUP _RTAPT-E.OWNERS-A @ OVER _RTAPT-E.OWNERS-U @ 0 FILL
    DUP _RTAPT-E.OPS-A @ OVER _RTAPT-E.OPS-U @ 0 FILL
    DUP _RTAPT-E.COPY-A @ OVER _RTAPT-E.COPY-U @ 0 FILL
    RTAPT-ENGINE-SIZE 0 FILL RTAPT-S-OK ;

\ =====================================================================
\  Exact owner lifecycle queue
\ =====================================================================

: _RTAPT-OWNER-NTH  ( index engine -- owner-record )
    _RTAPT-E.OWNERS-A @ SWAP RTAPT-OWNER-SIZE * + ;

VARIABLE _RTAPT-OS-E

: _RTAPT-OWNER-SLOT  ( owner-record engine -- index )
    _RTAPT-OS-E !
    _RTAPT-OS-E @ _RTAPT-E.OWNERS-A @ - RTAPT-OWNER-SIZE / ;

VARIABLE _RTAPT-OF-E
VARIABLE _RTAPT-OF-OWNER
VARIABLE _RTAPT-OF-GEN
VARIABLE _RTAPT-OF-RESULT

: _RTAPT-OWNER-FIND  ( owner generation engine -- owner-record|0 )
    _RTAPT-OF-E ! _RTAPT-OF-GEN ! _RTAPT-OF-OWNER !
    0 _RTAPT-OF-RESULT !
    _RTAPT-OF-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        I _RTAPT-OF-E @ _RTAPT-OWNER-NTH DUP _RTAPT-O.STATE @
        RTAPT-OWNER-ST-FREE <> IF
            DUP _RTAPT-O.OWNER @ _RTAPT-OF-OWNER @ =
            OVER _RTAPT-O.GENERATION @ _RTAPT-OF-GEN @ = AND IF
                _RTAPT-OF-RESULT !
            ELSE DROP THEN
        ELSE DROP THEN
    LOOP
    _RTAPT-OF-RESULT @ ;

: _RTAPT-OWNER-ID-FIND  ( owner engine -- owner-record|0 )
    _RTAPT-OF-E ! _RTAPT-OF-OWNER ! 0 _RTAPT-OF-RESULT !
    _RTAPT-OF-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-OF-RESULT @ 0= IF
            I _RTAPT-OF-E @ _RTAPT-OWNER-NTH DUP _RTAPT-O.STATE @
            RTAPT-OWNER-ST-FREE <> IF
                DUP _RTAPT-O.OWNER @ _RTAPT-OF-OWNER @ = IF
                    _RTAPT-OF-RESULT !
                ELSE DROP THEN
            ELSE DROP THEN
        THEN
    LOOP
    _RTAPT-OF-RESULT @ ;

: _RTAPT-OWNER-FREE-SLOT  ( engine -- owner-record|0 )
    DUP _RTAPT-OF-E ! 0 _RTAPT-OF-RESULT !
    _RTAPT-OF-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-OF-RESULT @ 0= IF
            I _RTAPT-OF-E @ _RTAPT-OWNER-NTH DUP _RTAPT-O.STATE @
            RTAPT-OWNER-ST-FREE = IF _RTAPT-OF-RESULT ! ELSE DROP THEN
        THEN
    LOOP
    DROP _RTAPT-OF-RESULT @ ;

VARIABLE _RTAPT-Q-O
VARIABLE _RTAPT-Q-E

: _RTAPT-QUEUE-PUSH  ( owner-record engine -- )
    _RTAPT-Q-E ! _RTAPT-Q-O !
    0 _RTAPT-Q-O @ _RTAPT-O.NEXT !
    _RTAPT-Q-E @ _RTAPT-E.QUEUE-TAIL @ ?DUP IF
        _RTAPT-Q-O @ SWAP _RTAPT-O.NEXT !
    ELSE
        _RTAPT-Q-O @ _RTAPT-Q-E @ _RTAPT-E.QUEUE-HEAD !
    THEN
    _RTAPT-Q-O @ _RTAPT-Q-E @ _RTAPT-E.QUEUE-TAIL ! ;

: _RTAPT-QUEUE-POP  ( engine -- owner-record|0 )
    DUP _RTAPT-Q-E ! _RTAPT-E.QUEUE-HEAD @ DUP 0= IF EXIT THEN
    DUP _RTAPT-O.NEXT @ _RTAPT-Q-E @ _RTAPT-E.QUEUE-HEAD !
    _RTAPT-Q-E @ _RTAPT-E.QUEUE-HEAD @ 0= IF
        0 _RTAPT-Q-E @ _RTAPT-E.QUEUE-TAIL !
    THEN
    0 OVER _RTAPT-O.NEXT ! ;

VARIABLE _RTAPT-OO-E
VARIABLE _RTAPT-OO-O
VARIABLE _RTAPT-OO-OWNER
VARIABLE _RTAPT-OO-GEN
VARIABLE _RTAPT-OO-RQ
VARIABLE _RTAPT-OO-XQ
VARIABLE _RTAPT-OO-OQ
VARIABLE _RTAPT-OO-SQ
VARIABLE _RTAPT-OO-RBQ
VARIABLE _RTAPT-OO-UQ
VARIABLE _RTAPT-OO-SLQ
VARIABLE _RTAPT-OO-REUSED
VARIABLE _RTAPT-OO-PRIOR-GEN

: RTAPT-OWNER-OPEN  ( owner generation region-q resource-q object-q series-q resource-byte-q utf8-byte-q sample-slot-q engine -- status )
    _RTAPT-OO-E ! _RTAPT-OO-SLQ ! _RTAPT-OO-UQ ! _RTAPT-OO-RBQ !
    _RTAPT-OO-SQ ! _RTAPT-OO-OQ ! _RTAPT-OO-XQ ! _RTAPT-OO-RQ !
    _RTAPT-OO-GEN ! _RTAPT-OO-OWNER !
    _RTAPT-OO-E @ _RTAPT-ENGINE-VALID? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-OO-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-OO-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <> IF
        RTAPT-S-BUSY EXIT
    THEN
    _RTAPT-OO-OWNER @ 0= _RTAPT-OO-GEN @ 0= OR IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-OO-RQ @ 0xFFFFFFFF U>
    _RTAPT-OO-XQ @ 0xFFFFFFFF U> OR
    _RTAPT-OO-OQ @ 0xFFFFFFFF U> OR
    _RTAPT-OO-SQ @ 0xFFFFFFFF U> OR IF RTAPT-S-INVALID EXIT THEN
    0 _RTAPT-OO-REUSED !
    0 _RTAPT-OO-PRIOR-GEN !
    _RTAPT-OO-OWNER @ _RTAPT-OO-E @ _RTAPT-OWNER-ID-FIND ?DUP IF
        DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-TOMBSTONE <> IF
            DROP RTAPT-S-BUSY EXIT
        THEN
        DUP _RTAPT-O.GENERATION @ _RTAPT-OO-GEN @ U< 0= IF
            DROP RTAPT-S-BUSY EXIT
        THEN
        DUP _RTAPT-O.GENERATION @ _RTAPT-OO-PRIOR-GEN !
        _RTAPT-OO-O ! -1 _RTAPT-OO-REUSED !
    ELSE
        _RTAPT-OO-E @ _RTAPT-OWNER-FREE-SLOT DUP 0= IF
            DROP RTAPT-S-CAPACITY EXIT
        THEN _RTAPT-OO-O !
    THEN
    _RTAPT-OO-O @ RTAPT-OWNER-SIZE 0 FILL
    _RTAPT-OO-OWNER @ _RTAPT-OO-O @ _RTAPT-O.OWNER !
    _RTAPT-OO-GEN @ _RTAPT-OO-O @ _RTAPT-O.GENERATION !
    _RTAPT-OO-RQ @ _RTAPT-OO-O @ _RTAPT-O.REGIONS !
    _RTAPT-OO-XQ @ _RTAPT-OO-O @ _RTAPT-O.RESOURCES !
    _RTAPT-OO-OQ @ _RTAPT-OO-O @ _RTAPT-O.OBJECTS !
    _RTAPT-OO-SQ @ _RTAPT-OO-O @ _RTAPT-O.SERIES !
    _RTAPT-OO-RBQ @ _RTAPT-OO-O @ _RTAPT-O.RES-BYTES !
    _RTAPT-OO-UQ @ _RTAPT-OO-O @ _RTAPT-O.UTF8-BYTES !
    _RTAPT-OO-SLQ @ _RTAPT-OO-O @ _RTAPT-O.SAMPLES !
    _RTAPT-OO-PRIOR-GEN @ _RTAPT-OO-O @ _RTAPT-O.PRIOR-GENERATION !
    _RTAPT-OO-REUSED @ IF RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED
        ELSE RTAPT-OWNER-ST-OPEN-QUEUED THEN
    _RTAPT-OO-O @ _RTAPT-O.STATE !
    _RTAPT-OO-REUSED @ 0= IF 1 _RTAPT-OO-E @ _RTAPT-E.OWNER-USED +! THEN
    _RTAPT-OO-O @ _RTAPT-OO-E @ _RTAPT-QUEUE-PUSH
    RTAPT-S-OK _RTAPT-OO-E @ _RTAPT-E.LAST-STATUS !
    RTAPT-S-OK ;

: RTAPT-OWNER-STATE@  ( owner generation engine -- owner-state status )
    DUP _RTAPT-ENGINE-VALID? 0= IF 2DROP DROP RTAPT-OWNER-ST-FREE
        RTAPT-S-INVALID EXIT
    THEN
    DUP _RTAPT-READY-STATUS DROP
    _RTAPT-OWNER-FIND DUP 0= IF
        DROP RTAPT-OWNER-ST-FREE
        _RTAPT-OF-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
            _RTAPT-OF-E @ _RTAPT-E.LAST-STATUS @
        ELSE RTAPT-S-OK THEN EXIT
    THEN
    _RTAPT-O.STATE @ DUP RTAPT-OWNER-ST-QUARANTINED = IF
        _RTAPT-OF-E @ _RTAPT-E.LAST-STATUS @
    ELSE RTAPT-S-OK THEN ;

VARIABLE _RTAPT-OD-E
VARIABLE _RTAPT-OD-O
VARIABLE _RTAPT-OD-STATE

: RTAPT-OWNER-DROP  ( owner generation engine -- status )
    DUP _RTAPT-OD-E !
    DUP _RTAPT-ENGINE-VALID? 0= IF 2DROP DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF
        >R 2DROP DROP R> EXIT
    THEN DROP
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <> IF
        2DROP DROP RTAPT-S-BUSY EXIT
    THEN
    _RTAPT-OWNER-FIND DUP 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-OD-O ! _RTAPT-O.STATE @ DUP _RTAPT-OD-STATE !
    DUP RTAPT-OWNER-ST-OPEN = IF
        DROP RTAPT-OWNER-ST-DROP-QUEUED
    ELSE DUP RTAPT-OWNER-ST-TOMBSTONE = IF
        DROP RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED
    ELSE RTAPT-OWNER-ST-DROPPING = IF
        _RTAPT-OD-O @ _RTAPT-O.WIRE-STATUS @ DUP PT-TX-RESULT-INVALID =
        SWAP PT-TX-RESULT-STALE = OR 0= IF RTAPT-S-BUSY EXIT THEN
        RTAPT-OWNER-ST-DROP-RETRY-QUEUED
    ELSE RTAPT-S-BUSY EXIT THEN THEN THEN
    _RTAPT-OD-O @ _RTAPT-O.STATE !
    _RTAPT-OD-O @ _RTAPT-OD-E @ _RTAPT-QUEUE-PUSH
    RTAPT-S-OK _RTAPT-OD-E @ _RTAPT-E.LAST-STATUS !
    RTAPT-S-OK ;

\ =====================================================================
\  Caller-bounded retained candidate capture
\ =====================================================================

VARIABLE _RTAPT-BC-E

: _RTAPT-PENDING-CLEAR  ( engine -- )
    DUP _RTAPT-BC-E !
    _RTAPT-BC-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-BC-E @ _RTAPT-E.OWNERS-A @ I RTAPT-OWNER-SIZE * +
        DUP _RTAPT-O.PENDING-REGIONS OFF
        DUP _RTAPT-O.PENDING-REGION-HIGH OFF
        DUP _RTAPT-O.PENDING-OBJECTS OFF
        DUP _RTAPT-O.PENDING-OBJECT-HIGH OFF
        DUP _RTAPT-O.PENDING-CONTROLS OFF
        DUP _RTAPT-O.PENDING-CONTROL-HIGH OFF
        _RTAPT-O.PENDING-UTF8 OFF
    LOOP DROP ;

: _RTAPT-UPDATE-METADATA-CLEAR  ( engine -- )
    DUP _RTAPT-E.UPDATE-STATE OFF
    DUP _RTAPT-E.COUPLING OFF
    DUP _RTAPT-E.COLS OFF
    DUP _RTAPT-E.ROWS OFF
    DUP _RTAPT-E.CELL-SPANS OFF
    DUP _RTAPT-E.CELLS OFF
    DUP _RTAPT-E.CELL-MODE OFF
    DUP _RTAPT-E.RET-MODE OFF
    DUP _RTAPT-E.DISPOSITION OFF
    DUP _RTAPT-E.OP-COUNT OFF
    DUP _RTAPT-E.COPY-USED OFF
    DUP _RTAPT-E.RET-BYTES OFF
    _RTAPT-E.SEND-INDEX OFF ;

: _RTAPT-CANDIDATE-DISCARD  ( engine -- )
    DUP _RTAPT-BC-E !
    DUP _RTAPT-E.OPS-A @ OVER _RTAPT-E.OP-COUNT @ RTAPT-OP-SIZE * 0 FILL
    DUP _RTAPT-E.COPY-A @ OVER _RTAPT-E.COPY-USED @ 0 FILL
    DUP _RTAPT-PENDING-CLEAR
    _RTAPT-UPDATE-METADATA-CLEAR ;

: _RTAPT-WIRE-REWIND  ( engine -- )
    DUP _RTAPT-E.COUPLING OFF
    DUP _RTAPT-E.COLS OFF
    DUP _RTAPT-E.ROWS OFF
    DUP _RTAPT-E.CELL-SPANS OFF
    DUP _RTAPT-E.CELLS OFF
    DUP _RTAPT-E.CELL-MODE OFF
    DUP _RTAPT-E.SEND-INDEX OFF
    DUP _RTAPT-E.RET-MODE @ PT-RET-NONE = IF
        _RTAPT-CANDIDATE-DISCARD
    ELSE
        RTAPT-UPDATE-SEALED SWAP _RTAPT-E.UPDATE-STATE !
    THEN ;

: RTAPT-USES-SESSION?  ( session engine -- flag )
    \ Session identity depends only on checked fixed storage.  It must not
    \ rescan a sealed caller-owned candidate when an adapter checks binding.
    DUP _RTAPT-ENGINE-STORAGE? 0= IF 2DROP 0 EXIT THEN
    _RTAPT-E.SESSION @ = ;

: RTAPT-STORAGE-DISJOINT?  ( a u engine -- flag )
    >R
    \ This authority query is deliberately stack-only.  Hybrid admission can
    \ use it to reject aliases before any provider validator scratch is safe
    \ to write; the exhaustive semantic audit remains at lifecycle boundaries.
    R@ RTAPT-ENGINE-SIZE _RTAPT-SPAN? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.MAGIC @ _RTAPT-ENGINE-MAGIC <> IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.SESSION @ PT-SESSION-SIZE _RTAPT-SPAN? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.OWNERS-A @ R@ _RTAPT-E.OWNERS-U @
        _RTAPT-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.OPS-A @ R@ _RTAPT-E.OPS-U @
        _RTAPT-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.COPY-A @ R@ _RTAPT-E.COPY-U @
        _RTAPT-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.OWNERS-U @ RTAPT-OWNER-SIZE MOD IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.OPS-U @ RTAPT-OP-SIZE MOD IF
        2DROP R> DROP 0 EXIT
    THEN

    R@ RTAPT-ENGINE-SIZE R@ _RTAPT-E.SESSION @
        PT-STORAGE-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.OWNERS-A @ R@ _RTAPT-E.OWNERS-U @
        R@ _RTAPT-E.SESSION @ PT-STORAGE-DISJOINT? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.OPS-A @ R@ _RTAPT-E.OPS-U @
        R@ _RTAPT-E.SESSION @ PT-STORAGE-DISJOINT? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.COPY-A @ R@ _RTAPT-E.COPY-U @
        R@ _RTAPT-E.SESSION @ PT-STORAGE-DISJOINT? 0= IF
        2DROP R> DROP 0 EXIT
    THEN

    R@ RTAPT-ENGINE-SIZE R@ _RTAPT-E.SESSION @ PT-SESSION-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.SESSION @ PT-SESSION-SIZE
        R@ _RTAPT-E.OWNERS-A @ R@ _RTAPT-E.OWNERS-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.SESSION @ PT-SESSION-SIZE
        R@ _RTAPT-E.OPS-A @ R@ _RTAPT-E.OPS-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.SESSION @ PT-SESSION-SIZE
        R@ _RTAPT-E.COPY-A @ R@ _RTAPT-E.COPY-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ RTAPT-ENGINE-SIZE
        R@ _RTAPT-E.OWNERS-A @ R@ _RTAPT-E.OWNERS-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ RTAPT-ENGINE-SIZE
        R@ _RTAPT-E.OPS-A @ R@ _RTAPT-E.OPS-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ RTAPT-ENGINE-SIZE
        R@ _RTAPT-E.COPY-A @ R@ _RTAPT-E.COPY-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.OWNERS-A @ R@ _RTAPT-E.OWNERS-U @
        R@ _RTAPT-E.OPS-A @ R@ _RTAPT-E.OPS-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.OWNERS-A @ R@ _RTAPT-E.OWNERS-U @
        R@ _RTAPT-E.COPY-A @ R@ _RTAPT-E.COPY-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _RTAPT-E.OPS-A @ R@ _RTAPT-E.OPS-U @
        R@ _RTAPT-E.COPY-A @ R@ _RTAPT-E.COPY-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN

    R@ _RTAPT-E.OWNER-CAP @
        R@ _RTAPT-E.OWNERS-U @ RTAPT-OWNER-SIZE / <> IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.OP-CAP @
        R@ _RTAPT-E.OPS-U @ RTAPT-OP-SIZE / <> IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.OWNER-USED @ R@ _RTAPT-E.OWNER-CAP @ U> IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.OP-COUNT @ _RTAPT-U32? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.OP-COUNT @ R@ _RTAPT-E.OP-CAP @ U> IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.COPY-USED @ R@ _RTAPT-E.COPY-U @ U> IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _RTAPT-E.SEND-INDEX @ R@ _RTAPT-E.OP-COUNT @ U> IF
        2DROP R> DROP 0 EXIT
    THEN

    OVER 0= OVER 0= OR IF 2DROP R> DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _RTAPT-E.SESSION @ PT-STORAGE-DISJOINT? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    2DUP R@ RTAPT-ENGINE-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DUP R@ _RTAPT-E.OWNERS-A @ R@ _RTAPT-E.OWNERS-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _RTAPT-E.OPS-A @ R@ _RTAPT-E.OPS-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _RTAPT-E.COPY-A @ R@ _RTAPT-E.COPY-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DROP R> DROP -1 ;

VARIABLE _RTAPT-BSD-A
VARIABLE _RTAPT-BSD-U
VARIABLE _RTAPT-BSD-E

\ Borrowed text is a byte span, not a construction record.  The caller has
\ already proved ENGINE storage geometry before this private nonalias check.
: _RTAPT-BYTE-SPAN-DISJOINT?  ( a u engine -- flag )
    _RTAPT-BSD-E ! _RTAPT-BSD-U ! _RTAPT-BSD-A !
    _RTAPT-BSD-A @ 0= _RTAPT-BSD-U @ 0= OR IF 0 EXIT THEN
    _RTAPT-BSD-A @ _RTAPT-BSD-U @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTAPT-BSD-A @ _RTAPT-BSD-U @ _RTAPT-BSD-E @ _RTAPT-E.SESSION @
        PT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-BSD-A @ _RTAPT-BSD-U @ _RTAPT-BSD-E @ RTAPT-ENGINE-SIZE
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-BSD-A @ _RTAPT-BSD-U @
        _RTAPT-BSD-E @ _RTAPT-E.OWNERS-A @
        _RTAPT-BSD-E @ _RTAPT-E.OWNERS-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-BSD-A @ _RTAPT-BSD-U @
        _RTAPT-BSD-E @ _RTAPT-E.OPS-A @
        _RTAPT-BSD-E @ _RTAPT-E.OPS-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-BSD-A @ _RTAPT-BSD-U @
        _RTAPT-BSD-E @ _RTAPT-E.COPY-A @
        _RTAPT-BSD-E @ _RTAPT-E.COPY-U @ MSPAN-OVERLAP? 0= ;

\ =====================================================================
\  Mutation-free initial GLYPH-RUN-plan admission
\ =====================================================================
\
\ This check proves the complete declared representation before OWNER_OPEN.
\ It borrows the plan and item span, but neither reserves an owner nor touches
\ the operation/copy banks.  RTAPT-LIMITS@ may refresh only the engine's
\ designated negotiated-limits scratch; ordinary structural loss retains the
\ engine's existing quarantine semantics.  The strictly monotone item walk
\ leaves LAST-OBJECT as identity/order high-water only.  COUNT is the exact
\ logical object reservation; the operation reservation remains COUNT + 1.

VARIABLE _RTAPT-LPF-PLAN
VARIABLE _RTAPT-LPF-E
VARIABLE _RTAPT-LPF-LIMITS
VARIABLE _RTAPT-LPF-ITEMS-A
VARIABLE _RTAPT-LPF-ITEMS-U
VARIABLE _RTAPT-LPF-COUNT
VARIABLE _RTAPT-LPF-ITEM
VARIABLE _RTAPT-LPF-OWNER
VARIABLE _RTAPT-LPF-GEN
VARIABLE _RTAPT-LPF-SURFACE-COLS
VARIABLE _RTAPT-LPF-SURFACE-ROWS
VARIABLE _RTAPT-LPF-REGION-ID
VARIABLE _RTAPT-LPF-REGION-X
VARIABLE _RTAPT-LPF-REGION-Y
VARIABLE _RTAPT-LPF-REGION-COLS
VARIABLE _RTAPT-LPF-REGION-ROWS
VARIABLE _RTAPT-LPF-REGION-Z
VARIABLE _RTAPT-LPF-REGION-FLAGS
VARIABLE _RTAPT-LPF-LAST-OBJECT
VARIABLE _RTAPT-LPF-OBJECT
VARIABLE _RTAPT-LPF-VISIBLE
VARIABLE _RTAPT-LPF-TEXT-CAP
VARIABLE _RTAPT-LPF-MAX-TEXT-CAP
VARIABLE _RTAPT-LPF-UTF8
VARIABLE _RTAPT-LPF-COPY-BYTES
VARIABLE _RTAPT-LPF-OPS
VARIABLE _RTAPT-LPF-TX-BYTES
VARIABLE _RTAPT-LPF-STATUS
VARIABLE _RTAPT-LPF-NEXT
VARIABLE _RTAPT-LPF-ROW-END
VARIABLE _RTAPT-LPF-COL-END
VARIABLE _RTAPT-LPF-SA
VARIABLE _RTAPT-LPF-SB
VARIABLE _RTAPT-LPF-SS

VARIABLE _RTAPT-LPF-OWNER-RECORD
VARIABLE _RTAPT-LPF-MATCH
VARIABLE _RTAPT-LPF-FREE
VARIABLE _RTAPT-LPF-REUSE
VARIABLE _RTAPT-LPF-OCCUPIED
VARIABLE _RTAPT-LPF-STATE
VARIABLE _RTAPT-LPF-LIVE
VARIABLE _RTAPT-LPF-AGG-REGIONS
VARIABLE _RTAPT-LPF-AGG-RESOURCES
VARIABLE _RTAPT-LPF-AGG-OBJECTS
VARIABLE _RTAPT-LPF-AGG-SERIES
VARIABLE _RTAPT-LPF-AGG-RES-BYTES
VARIABLE _RTAPT-LPF-AGG-UTF8
VARIABLE _RTAPT-LPF-AGG-SAMPLES

: _RTAPT-LPF-SCRUB  ( -- )
    0 _RTAPT-LPF-PLAN ! 0 _RTAPT-LPF-E ! 0 _RTAPT-LPF-LIMITS !
    0 _RTAPT-LPF-ITEMS-A ! 0 _RTAPT-LPF-ITEMS-U !
    0 _RTAPT-LPF-COUNT ! 0 _RTAPT-LPF-ITEM !
    0 _RTAPT-LPF-OWNER ! 0 _RTAPT-LPF-GEN !
    0 _RTAPT-LPF-SURFACE-COLS ! 0 _RTAPT-LPF-SURFACE-ROWS !
    0 _RTAPT-LPF-REGION-ID ! 0 _RTAPT-LPF-REGION-X !
    0 _RTAPT-LPF-REGION-Y ! 0 _RTAPT-LPF-REGION-COLS !
    0 _RTAPT-LPF-REGION-ROWS ! 0 _RTAPT-LPF-REGION-Z !
    0 _RTAPT-LPF-REGION-FLAGS ! 0 _RTAPT-LPF-LAST-OBJECT !
    0 _RTAPT-LPF-OBJECT ! 0 _RTAPT-LPF-VISIBLE !
    0 _RTAPT-LPF-TEXT-CAP ! 0 _RTAPT-LPF-MAX-TEXT-CAP !
    0 _RTAPT-LPF-UTF8 ! 0 _RTAPT-LPF-COPY-BYTES !
    0 _RTAPT-LPF-OPS ! 0 _RTAPT-LPF-TX-BYTES ! 0 _RTAPT-LPF-STATUS !
    0 _RTAPT-LPF-NEXT ! 0 _RTAPT-LPF-ROW-END !
    0 _RTAPT-LPF-COL-END ! 0 _RTAPT-LPF-SA !
    0 _RTAPT-LPF-SB ! 0 _RTAPT-LPF-SS !
    0 _RTAPT-LPF-OWNER-RECORD ! 0 _RTAPT-LPF-MATCH !
    0 _RTAPT-LPF-FREE ! 0 _RTAPT-LPF-REUSE !
    0 _RTAPT-LPF-OCCUPIED ! 0 _RTAPT-LPF-STATE !
    0 _RTAPT-LPF-LIVE !
    0 _RTAPT-LPF-AGG-REGIONS ! 0 _RTAPT-LPF-AGG-RESOURCES !
    0 _RTAPT-LPF-AGG-OBJECTS ! 0 _RTAPT-LPF-AGG-SERIES !
    0 _RTAPT-LPF-AGG-RES-BYTES ! 0 _RTAPT-LPF-AGG-UTF8 !
    0 _RTAPT-LPF-AGG-SAMPLES !
    ;

: _RTAPT-LPF-BOOL?  ( value -- flag )
    DUP 0= SWAP -1 = OR ;

0x006F CONSTANT _RTAPT-GLYPH-RUN-ATTR-MASK

: _RTAPT-GLYPH-RUN-ATTRS?  ( attrs -- flag )
    DUP _RTAPT-U16? 0= IF DROP 0 EXIT THEN
    _RTAPT-GLYPH-RUN-ATTR-MASK INVERT AND 0= ;

: _RTAPT-LPF-CAPACITY-FAIL  ( -- flag )
    RTAPT-S-CAPACITY _RTAPT-LPF-STATUS ! 0 ;

\ Checked native signed addition without borrowing the return stack.  This is
\ used from a DO loop, where R is the loop counter.
: _RTAPT-LPF-SADD?  ( a b -- sum flag )
    _RTAPT-LPF-SB ! _RTAPT-LPF-SA !
    _RTAPT-LPF-SA @ _RTAPT-LPF-SB @ + DUP _RTAPT-LPF-SS ! DROP
    _RTAPT-LPF-SA @ _RTAPT-LPF-SS @ XOR
    _RTAPT-LPF-SB @ _RTAPT-LPF-SS @ XOR AND 0< IF
        0 0 EXIT
    THEN
    _RTAPT-LPF-SS @ -1 ;

: _RTAPT-LPF-HEADER?  ( -- flag )
    _RTAPT-LPF-PLAN @ RTAPT-GLYPH-RUN-PLAN-SIZE _RTAPT-SPAN? 0= IF
        0 EXIT
    THEN
    _RTAPT-LPF-PLAN @ _RTAPT-LP.OWNER @ _RTAPT-LPF-OWNER !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.GENERATION @ _RTAPT-LPF-GEN !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.SURFACE-COLS @
        _RTAPT-LPF-SURFACE-COLS !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.SURFACE-ROWS @
        _RTAPT-LPF-SURFACE-ROWS !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.REGION-ID @ _RTAPT-LPF-REGION-ID !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.REGION-X @ _RTAPT-LPF-REGION-X !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.REGION-Y @ _RTAPT-LPF-REGION-Y !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.REGION-COLS @ _RTAPT-LPF-REGION-COLS !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.REGION-ROWS @ _RTAPT-LPF-REGION-ROWS !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.REGION-Z @ _RTAPT-LPF-REGION-Z !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.REGION-FLAGS @
        _RTAPT-LPF-REGION-FLAGS !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.ITEMS-A @ _RTAPT-LPF-ITEMS-A !
    _RTAPT-LPF-PLAN @ _RTAPT-LP.ITEMS-U @ _RTAPT-LPF-ITEMS-U !

    _RTAPT-LPF-OWNER @ 0= _RTAPT-LPF-GEN @ 0= OR
    _RTAPT-LPF-REGION-ID @ 0= OR IF 0 EXIT THEN
    _RTAPT-LPF-SURFACE-COLS @ DUP 0= SWAP _RTAPT-U32? 0= OR
    _RTAPT-LPF-SURFACE-ROWS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF
        0 EXIT
    THEN
    _RTAPT-LPF-REGION-X @ _RTAPT-U32? 0=
    _RTAPT-LPF-REGION-Y @ _RTAPT-U32? 0= OR
    _RTAPT-LPF-REGION-COLS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR
    _RTAPT-LPF-REGION-ROWS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF
        0 EXIT
    THEN
    _RTAPT-LPF-REGION-Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-REGION-FLAGS @ 3 INVERT AND IF 0 EXIT THEN
    _RTAPT-LPF-PLAN @ _RTAPT-LP.RESERVED @ IF 0 EXIT THEN
    _RTAPT-LPF-REGION-X @ _RTAPT-LPF-REGION-COLS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-LPF-SURFACE-COLS @ U> IF 0 EXIT THEN
    _RTAPT-LPF-REGION-Y @ _RTAPT-LPF-REGION-ROWS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-LPF-SURFACE-ROWS @ U> IF 0 EXIT THEN

    _RTAPT-LPF-ITEMS-A @ _RTAPT-LPF-ITEMS-U @ _RTAPT-SPAN? 0= IF
        0 EXIT
    THEN
    _RTAPT-LPF-ITEMS-U @ RTAPT-GLYPH-RUN-PLAN-ITEM-SIZE MOD IF 0 EXIT THEN
    _RTAPT-LPF-ITEMS-U @ RTAPT-GLYPH-RUN-PLAN-ITEM-SIZE /
        DUP _RTAPT-LPF-COUNT !
    DUP 0= SWAP _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-LPF-PLAN @ RTAPT-GLYPH-RUN-PLAN-SIZE
        _RTAPT-LPF-ITEMS-A @ _RTAPT-LPF-ITEMS-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTAPT-LPF-PLAN @ RTAPT-GLYPH-RUN-PLAN-SIZE _RTAPT-LPF-E @
        RTAPT-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEMS-A @ _RTAPT-LPF-ITEMS-U @ _RTAPT-LPF-E @
        RTAPT-STORAGE-DISJOINT? ;

: _RTAPT-LPF-ITEM?  ( item -- flag )
    _RTAPT-LPF-ITEM !
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.OBJECT @ DUP _RTAPT-LPF-OBJECT !
    DUP 0= SWAP _RTAPT-LPF-LAST-OBJECT @ U> 0= OR IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.PARENT @ IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.ROW @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.COL @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.HEIGHT @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.WIDTH @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.ROOT-HEIGHT @
        _RTAPT-LPF-REGION-ROWS @ <> IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.ROOT-WIDTH @
        _RTAPT-LPF-REGION-COLS @ <> IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.VISIBLE @ DUP
        _RTAPT-LPF-VISIBLE ! _RTAPT-LPF-BOOL? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.FG-RGBA @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.BG-RGBA @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.ATTRS @
        _RTAPT-GLYPH-RUN-ATTRS? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.TEXT-CAPACITY @ DUP
        _RTAPT-LPF-TEXT-CAP ! _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.RESERVED @ IF 0 EXIT THEN

    _RTAPT-LPF-ITEM @ _RTAPT-LPI.ROW @
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.HEIGHT @
        _RTAPT-LPF-SADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-LPF-ROW-END !
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.COL @
    _RTAPT-LPF-ITEM @ _RTAPT-LPI.WIDTH @
        _RTAPT-LPF-SADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-LPF-COL-END !
    _RTAPT-LPF-VISIBLE @ IF
        _RTAPT-LPF-ITEM @ _RTAPT-LPI.HEIGHT @ 0=
        _RTAPT-LPF-ITEM @ _RTAPT-LPI.WIDTH @ 0= OR
        _RTAPT-LPF-ITEM @ _RTAPT-LPI.ROW @
            _RTAPT-LPF-REGION-ROWS @ < 0= OR
        _RTAPT-LPF-ROW-END @ 0> 0= OR
        _RTAPT-LPF-ITEM @ _RTAPT-LPI.COL @
            _RTAPT-LPF-REGION-COLS @ < 0= OR
        _RTAPT-LPF-COL-END @ 0> 0= OR IF 0 EXIT THEN
    THEN

    _RTAPT-LPF-UTF8 @ _RTAPT-LPF-TEXT-CAP @
        _RTAPT-UADD? 0= IF
        DROP _RTAPT-LPF-CAPACITY-FAIL EXIT
    THEN _RTAPT-LPF-NEXT !
    _RTAPT-LPF-TEXT-CAP @ _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED
        _RTAPT-UADD? 0= IF
        DROP _RTAPT-LPF-CAPACITY-FAIL EXIT
    THEN
    _RTAPT-ALIGN8? 0= IF DROP _RTAPT-LPF-CAPACITY-FAIL EXIT THEN
    _RTAPT-LPF-COPY-BYTES @ SWAP _RTAPT-UADD? 0= IF
        DROP _RTAPT-LPF-CAPACITY-FAIL EXIT
    THEN
    _RTAPT-LPF-COPY-BYTES !
    _RTAPT-LPF-NEXT @ _RTAPT-LPF-UTF8 !
    _RTAPT-LPF-TEXT-CAP @ _RTAPT-LPF-MAX-TEXT-CAP @ U> IF
        _RTAPT-LPF-TEXT-CAP @ _RTAPT-LPF-MAX-TEXT-CAP !
    THEN
    _RTAPT-LPF-OBJECT @ _RTAPT-LPF-LAST-OBJECT !
    -1 ;

: _RTAPT-LPF-ARITHMETIC?  ( -- flag )
    RTAPT-S-INVALID _RTAPT-LPF-STATUS !
    0 _RTAPT-LPF-LAST-OBJECT ! 0 _RTAPT-LPF-MAX-TEXT-CAP !
    0 _RTAPT-LPF-UTF8 !
    _RTAPT-REGION-DEFINE-COPY-SIZE _RTAPT-LPF-COPY-BYTES !
    _RTAPT-LPF-COUNT @ 0 ?DO
        _RTAPT-LPF-ITEMS-A @ I RTAPT-GLYPH-RUN-PLAN-ITEM-SIZE * +
            _RTAPT-LPF-ITEM? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RTAPT-LPF-COUNT @ 1 _RTAPT-UADD? 0= IF
        DROP _RTAPT-LPF-CAPACITY-FAIL EXIT
    THEN
    DUP _RTAPT-U32? 0= IF DROP _RTAPT-LPF-CAPACITY-FAIL EXIT THEN
    _RTAPT-LPF-OPS !
    _RTAPT-LPF-COUNT @ _RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED
        _RTAPT-UMUL? 0= IF DROP _RTAPT-LPF-CAPACITY-FAIL EXIT THEN
    _RTAPT-LPF-UTF8 @ _RTAPT-UADD? 0= IF
        DROP _RTAPT-LPF-CAPACITY-FAIL EXIT
    THEN
    _RTAPT-UPDATE-ENVELOPE-FRAME-BYTES
        _RTAPT-REGION-DEFINE-FRAME-BYTES +
        _RTAPT-UADD? 0= IF DROP _RTAPT-LPF-CAPACITY-FAIL EXIT THEN
    _RTAPT-LPF-TX-BYTES !
    -1 ;

\ These states still carry or may have reserved live-owner quotas.  Stable
\ TOMBSTONE records do not; in-flight tombstone drop also carries no quotas.
: _RTAPT-LPF-RESERVATION?  ( owner-state -- flag )
    DUP RTAPT-OWNER-ST-OPEN-QUEUED =
    OVER RTAPT-OWNER-ST-OPENING = OR
    OVER RTAPT-OWNER-ST-OPEN = OR
    OVER RTAPT-OWNER-ST-DROP-QUEUED = OR
    OVER RTAPT-OWNER-ST-DROPPING = OR
    OVER RTAPT-OWNER-ST-DROP-RETRY-QUEUED = OR
    OVER RTAPT-OWNER-ST-DROP-RETRY-DROPPING = OR
    OVER RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED = OR
    OVER RTAPT-OWNER-ST-TOMBSTONE-OPENING = OR
    SWAP RTAPT-OWNER-ST-QUARANTINED = OR ;

: _RTAPT-LPF-OWNER-STATE?  ( owner-state -- flag )
    RTAPT-OWNER-ST-TOMBSTONE-OPENING U> 0= ;

\ The caller reaches owner admission only after proving the lifecycle queue
\ empty and ACTIVE-KIND none.  At that stable boundary, a non-FREE record can
\ only be OPEN or a settled TOMBSTONE; any queued/opening/dropping state would
\ be orphaned from the lifecycle authority which must drive it.
: _RTAPT-LPF-ADMISSION-STATE?  ( owner-state -- flag )
    DUP RTAPT-OWNER-ST-FREE =
    OVER RTAPT-OWNER-ST-OPEN = OR
    SWAP RTAPT-OWNER-ST-TOMBSTONE = OR ;

: _RTAPT-LPF-OWNER-QUOTAS?  ( -- flag )
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.REGIONS @ _RTAPT-U32?
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.RESOURCES @ _RTAPT-U32? AND
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.OBJECTS @ _RTAPT-U32? AND
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.SERIES @ _RTAPT-U32? AND ;

: _RTAPT-LPF-OWNER-QUOTAS-ZERO?  ( -- flag )
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.REGIONS @
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.RESOURCES @ OR
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.OBJECTS @ OR
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.SERIES @ OR
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.RES-BYTES @ OR
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.UTF8-BYTES @ OR
    _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.SAMPLES @ OR 0= ;

: _RTAPT-LPF-ADD-OWNER-QUOTAS  ( -- flag )
    _RTAPT-LPF-LIVE @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        _RTAPT-LPF-LIVE !
    _RTAPT-LPF-AGG-REGIONS @
        _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.REGIONS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LPF-AGG-REGIONS !
    _RTAPT-LPF-AGG-RESOURCES @
        _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.RESOURCES @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LPF-AGG-RESOURCES !
    _RTAPT-LPF-AGG-OBJECTS @
        _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.OBJECTS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LPF-AGG-OBJECTS !
    _RTAPT-LPF-AGG-SERIES @
        _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.SERIES @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LPF-AGG-SERIES !
    _RTAPT-LPF-AGG-RES-BYTES @
        _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.RES-BYTES @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LPF-AGG-RES-BYTES !
    _RTAPT-LPF-AGG-UTF8 @
        _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.UTF8-BYTES @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LPF-AGG-UTF8 !
    _RTAPT-LPF-AGG-SAMPLES @
        _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.SAMPLES @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-LPF-AGG-SAMPLES !
    -1 ;

: _RTAPT-LPF-OWNER-ADMISSION  ( -- status )
    0 _RTAPT-LPF-MATCH ! 0 _RTAPT-LPF-FREE ! 0 _RTAPT-LPF-REUSE !
    0 _RTAPT-LPF-OCCUPIED !
    0 _RTAPT-LPF-LIVE ! 0 _RTAPT-LPF-AGG-REGIONS !
    0 _RTAPT-LPF-AGG-RESOURCES ! 0 _RTAPT-LPF-AGG-OBJECTS !
    0 _RTAPT-LPF-AGG-SERIES ! 0 _RTAPT-LPF-AGG-RES-BYTES !
    0 _RTAPT-LPF-AGG-UTF8 ! 0 _RTAPT-LPF-AGG-SAMPLES !
    _RTAPT-LPF-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        I _RTAPT-LPF-E @ _RTAPT-OWNER-NTH DUP
            _RTAPT-LPF-OWNER-RECORD !
        _RTAPT-O.STATE @ DUP _RTAPT-LPF-STATE !
        _RTAPT-LPF-STATE @ _RTAPT-LPF-OWNER-STATE? 0= IF
            DROP RTAPT-S-INVALID UNLOOP EXIT
        THEN
        _RTAPT-LPF-STATE @ _RTAPT-LPF-ADMISSION-STATE? 0= IF
            DROP RTAPT-S-INVALID UNLOOP EXIT
        THEN
        RTAPT-OWNER-ST-FREE = IF
            -1 _RTAPT-LPF-FREE !
        ELSE
            _RTAPT-LPF-OCCUPIED @ 1 _RTAPT-UADD? 0= IF
                DROP RTAPT-S-INVALID UNLOOP EXIT
            THEN
            _RTAPT-LPF-OCCUPIED !
            _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.OWNER @ 0=
            _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.GENERATION @ 0= OR
            _RTAPT-LPF-OWNER-QUOTAS? 0= OR IF
                RTAPT-S-INVALID UNLOOP EXIT
            THEN
            _RTAPT-LPF-OWNER-RECORD @ _RTAPT-O.OWNER @
                _RTAPT-LPF-OWNER @ = IF
                _RTAPT-LPF-MATCH @ IF RTAPT-S-INVALID UNLOOP EXIT THEN
                _RTAPT-LPF-OWNER-RECORD @ _RTAPT-LPF-MATCH !
            THEN
            _RTAPT-LPF-STATE @ _RTAPT-LPF-RESERVATION? IF
                _RTAPT-LPF-ADD-OWNER-QUOTAS 0= IF
                    RTAPT-S-CAPACITY UNLOOP EXIT
                THEN
            ELSE
                \ Every valid non-reserving state is a tombstone phase; a
                \ settled drop has already released all quota authority.
                _RTAPT-LPF-OWNER-QUOTAS-ZERO? 0= IF
                    RTAPT-S-INVALID UNLOOP EXIT
                THEN
            THEN
        THEN
    LOOP

    \ OWNER-USED is authoritative bookkeeping, but admission must also prove
    \ it still exactly describes the concrete record bank before relying on
    \ either the recorded capacity or a free-slot observation.
    _RTAPT-LPF-OCCUPIED @
        _RTAPT-LPF-E @ _RTAPT-E.OWNER-USED @ <> IF
        RTAPT-S-INVALID EXIT
    THEN

    _RTAPT-LPF-MATCH @ ?DUP IF
        DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-TOMBSTONE <> IF
            DROP RTAPT-S-BUSY EXIT
        THEN
        _RTAPT-O.GENERATION @ _RTAPT-LPF-GEN @ U< 0= IF
            RTAPT-S-BUSY EXIT
        THEN
        -1 _RTAPT-LPF-REUSE !
    ELSE
        _RTAPT-LPF-FREE @ 0= IF RTAPT-S-CAPACITY EXIT THEN
    THEN

    _RTAPT-LPF-OCCUPIED @
    _RTAPT-LPF-REUSE @ IF 0 ELSE 1 THEN
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    DUP _RTAPT-LPF-E @ _RTAPT-E.OWNER-CAP @ U> IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-LIMITS @ _RTAPT-L.OWNER-RECORDS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-LIVE @ 1 _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-LIMITS @ _RTAPT-L.LIVE-OWNERS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-AGG-REGIONS @ 1 _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-LIMITS @ _RTAPT-L.REGIONS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    \ OWNER_OPEN reserves the exact shared glyph-object/control count.  Sparse
    \ IDs remain namespace identity and do not inflate the reservation.
    _RTAPT-LPF-AGG-OBJECTS @ _RTAPT-LPF-COUNT @
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LPF-LIMITS @ _RTAPT-L.OBJECTS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-AGG-UTF8 @ _RTAPT-LPF-UTF8 @
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LPF-LIMITS @ _RTAPT-L.UTF8-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-AGG-RESOURCES @
        _RTAPT-LPF-LIMITS @ _RTAPT-L.RESOURCES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-AGG-SERIES @
        _RTAPT-LPF-LIMITS @ _RTAPT-L.SERIES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-AGG-RES-BYTES @
        _RTAPT-LPF-LIMITS @ _RTAPT-L.RESOURCE-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-AGG-SAMPLES @
        _RTAPT-LPF-LIMITS @ _RTAPT-L.SAMPLE-SLOTS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    RTAPT-S-OK ;

: _RTAPT-GLYPH-RUN-PREFLIGHT-BODY  ( -- status )
    _RTAPT-LPF-E @ _RTAPT-ENGINE-VALID? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-LPF-HEADER? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-LPF-ARITHMETIC? 0= IF _RTAPT-LPF-STATUS @ EXIT THEN

    _RTAPT-LPF-E @ RTAPT-LIMITS@ DUP RTAPT-S-OK <> IF NIP EXIT THEN
    DROP _RTAPT-LPF-LIMITS !
    _RTAPT-LPF-LIMITS @ _RTAPT-L.GLYPH-RUN-BYTES @ 0= IF
        RTAPT-S-UNSUPPORTED EXIT
    THEN
    _RTAPT-LPF-MAX-TEXT-CAP @
        _RTAPT-LPF-LIMITS @ _RTAPT-L.GLYPH-RUN-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-OPS @ _RTAPT-LPF-LIMITS @ _RTAPT-L.OPS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-OPS @ _RTAPT-LPF-E @ _RTAPT-E.OP-CAP @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-COPY-BYTES @ _RTAPT-LPF-E @ _RTAPT-E.COPY-U @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-TX-BYTES @
        _RTAPT-LPF-LIMITS @ _RTAPT-L.UPDATE-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LPF-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <>
    _RTAPT-LPF-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> OR
    _RTAPT-LPF-E @ _RTAPT-E.QUEUE-HEAD @ OR
    _RTAPT-LPF-E @ _RTAPT-E.QUEUE-TAIL @ OR IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-LPF-OWNER-ADMISSION ;

: RTAPT-GLYPH-RUN-PREFLIGHT  ( plan engine -- status )
    _RTAPT-LPF-E ! _RTAPT-LPF-PLAN !
    ['] _RTAPT-GLYPH-RUN-PREFLIGHT-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-LPF-SCRUB ;

\ =====================================================================
\  Aggregate-only initial CONTROL admission
\ =====================================================================
\
\ The neutral layer performs the one authoritative parent-first plan walk.
\ This provider consumes only its checked aggregates, so capability and owner
\ admission remain O(1) and never borrow or rescan the caller's control bank.

VARIABLE _RTAPT-CPF-OWNER
VARIABLE _RTAPT-CPF-GEN
VARIABLE _RTAPT-CPF-SURFACE-COLS
VARIABLE _RTAPT-CPF-SURFACE-ROWS
VARIABLE _RTAPT-CPF-REGION-ID
VARIABLE _RTAPT-CPF-REGION-X
VARIABLE _RTAPT-CPF-REGION-Y
VARIABLE _RTAPT-CPF-REGION-COLS
VARIABLE _RTAPT-CPF-REGION-ROWS
VARIABLE _RTAPT-CPF-REGION-Z
VARIABLE _RTAPT-CPF-REGION-FLAGS
VARIABLE _RTAPT-CPF-COUNT
VARIABLE _RTAPT-CPF-TEXT
VARIABLE _RTAPT-CPF-ALIGNED-TEXT
VARIABLE _RTAPT-CPF-MAX-ITEM-TEXT
VARIABLE _RTAPT-CPF-LAST-ID
VARIABLE _RTAPT-CPF-E
VARIABLE _RTAPT-CPF-COPY
VARIABLE _RTAPT-CPF-OPS
VARIABLE _RTAPT-CPF-TX

: _RTAPT-CONTROL-PREFLIGHT-SCRUB  ( -- )
    0 _RTAPT-CPF-OWNER ! 0 _RTAPT-CPF-GEN !
    0 _RTAPT-CPF-SURFACE-COLS ! 0 _RTAPT-CPF-SURFACE-ROWS !
    0 _RTAPT-CPF-REGION-ID ! 0 _RTAPT-CPF-REGION-X !
    0 _RTAPT-CPF-REGION-Y ! 0 _RTAPT-CPF-REGION-COLS !
    0 _RTAPT-CPF-REGION-ROWS ! 0 _RTAPT-CPF-REGION-Z !
    0 _RTAPT-CPF-REGION-FLAGS ! 0 _RTAPT-CPF-COUNT !
    0 _RTAPT-CPF-TEXT ! 0 _RTAPT-CPF-ALIGNED-TEXT !
    0 _RTAPT-CPF-MAX-ITEM-TEXT ! 0 _RTAPT-CPF-LAST-ID !
    0 _RTAPT-CPF-E ! 0 _RTAPT-CPF-COPY !
    0 _RTAPT-CPF-OPS ! 0 _RTAPT-CPF-TX !
    _RTAPT-LPF-SCRUB ;

: _RTAPT-CONTROL-PREFLIGHT-FIELDS?  ( -- flag )
    _RTAPT-CPF-OWNER @ 0= _RTAPT-CPF-GEN @ 0= OR
    _RTAPT-CPF-REGION-ID @ 0= OR IF 0 EXIT THEN
    _RTAPT-CPF-SURFACE-COLS @ DUP 0= SWAP _RTAPT-U32? 0= OR
    _RTAPT-CPF-SURFACE-ROWS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF
        0 EXIT
    THEN
    _RTAPT-CPF-REGION-X @ _RTAPT-U32? 0=
    _RTAPT-CPF-REGION-Y @ _RTAPT-U32? 0= OR
    _RTAPT-CPF-REGION-COLS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR
    _RTAPT-CPF-REGION-ROWS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF
        0 EXIT
    THEN
    _RTAPT-CPF-REGION-X @ _RTAPT-CPF-REGION-COLS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-CPF-SURFACE-COLS @ U> IF 0 EXIT THEN
    _RTAPT-CPF-REGION-Y @ _RTAPT-CPF-REGION-ROWS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-CPF-SURFACE-ROWS @ U> IF 0 EXIT THEN
    _RTAPT-CPF-REGION-Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-CPF-REGION-FLAGS @ 3 INVERT AND IF 0 EXIT THEN
    _RTAPT-CPF-COUNT @ DUP 0= SWAP _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-CPF-TEXT @ 0< _RTAPT-CPF-ALIGNED-TEXT @ 0< OR
    _RTAPT-CPF-MAX-ITEM-TEXT @ 0< OR IF 0 EXIT THEN
    _RTAPT-CPF-ALIGNED-TEXT @ 7 AND IF 0 EXIT THEN
    _RTAPT-CPF-TEXT @ _RTAPT-CPF-ALIGNED-TEXT @ U> IF 0 EXIT THEN
    _RTAPT-CPF-MAX-ITEM-TEXT @ _RTAPT-CPF-TEXT @ U> IF 0 EXIT THEN
    _RTAPT-CPF-COUNT @ 7 _RTAPT-UMUL? 0= IF DROP 0 EXIT THEN
    _RTAPT-CPF-TEXT @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-CPF-ALIGNED-TEXT @ U< IF 0 EXIT THEN
    _RTAPT-CPF-LAST-ID @ DUP 0= SWAP _RTAPT-CPF-COUNT @ U< OR 0= ;

: _RTAPT-CONTROL-PREFLIGHT-ARITHMETIC?  ( -- flag )
    _RTAPT-CPF-COUNT @ _RTAPT-CONTROL-COPY-FIXED _RTAPT-UMUL?
        0= IF DROP 0 EXIT THEN
    _RTAPT-CPF-ALIGNED-TEXT @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-REGION-DEFINE-COPY-SIZE _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        _RTAPT-CPF-COPY !
    _RTAPT-CPF-COUNT @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-U32? 0= IF DROP 0 EXIT THEN _RTAPT-CPF-OPS !
    _RTAPT-CPF-COUNT @ _RTAPT-CONTROL-FRAME-FIXED _RTAPT-UMUL?
        0= IF DROP 0 EXIT THEN
    _RTAPT-CPF-TEXT @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-UPDATE-ENVELOPE-FRAME-BYTES
        _RTAPT-REGION-DEFINE-FRAME-BYTES + _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-CPF-TX !
    -1 ;

: _RTAPT-CONTROL-PREFLIGHT-BODY  ( -- status )
    _RTAPT-CPF-E @ _RTAPT-ENGINE-VALID? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CONTROL-PREFLIGHT-FIELDS? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CONTROL-PREFLIGHT-ARITHMETIC? 0= IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-CPF-E @ RTAPT-LIMITS@ DUP RTAPT-S-OK <> IF NIP EXIT THEN
    DROP _RTAPT-LPF-LIMITS !
    _RTAPT-LPF-LIMITS @ _RTAPT-L.FEATURES @ RTAPT-F-CONTROLS AND 0= IF
        RTAPT-S-UNSUPPORTED EXIT
    THEN
    _RTAPT-CPF-MAX-ITEM-TEXT @ 80 _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-LPF-LIMITS @ _RTAPT-L.OUTBOUND-PAYLOAD @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CPF-OPS @ _RTAPT-LPF-LIMITS @ _RTAPT-L.OPS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CPF-OPS @ _RTAPT-CPF-E @ _RTAPT-E.OP-CAP @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CPF-COPY @ _RTAPT-CPF-E @ _RTAPT-E.COPY-U @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CPF-TX @ _RTAPT-LPF-LIMITS @ _RTAPT-L.UPDATE-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CPF-TEXT @ _RTAPT-LPF-LIMITS @ _RTAPT-L.UTF8-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CPF-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <>
    _RTAPT-CPF-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> OR
    _RTAPT-CPF-E @ _RTAPT-E.QUEUE-HEAD @ OR
    _RTAPT-CPF-E @ _RTAPT-E.QUEUE-TAIL @ OR IF RTAPT-S-BUSY EXIT THEN

    \ Reuse the established owner-admission authority with the control plan's
    \ exact shared object and UTF-8 reservations.  LAST-ID is identity only.
    _RTAPT-CPF-OWNER @ _RTAPT-LPF-OWNER !
    _RTAPT-CPF-GEN @ _RTAPT-LPF-GEN !
    _RTAPT-CPF-COUNT @ _RTAPT-LPF-COUNT !
    _RTAPT-CPF-TEXT @ _RTAPT-LPF-UTF8 !
    _RTAPT-CPF-E @ _RTAPT-LPF-E !
    _RTAPT-LPF-OWNER-ADMISSION ;

\ Stack: owner generation surface-cols surface-rows region-id region-x region-y
\        region-cols region-rows region-z region-flags control-count text-bytes
\        aligned-text-bytes max-item-text last-id engine -- status
: RTAPT-CONTROL-PREFLIGHT  ( aggregate scalars engine -- status )
    _RTAPT-CPF-E ! _RTAPT-CPF-LAST-ID ! _RTAPT-CPF-MAX-ITEM-TEXT !
    _RTAPT-CPF-ALIGNED-TEXT ! _RTAPT-CPF-TEXT ! _RTAPT-CPF-COUNT !
    _RTAPT-CPF-REGION-FLAGS ! _RTAPT-CPF-REGION-Z !
    _RTAPT-CPF-REGION-ROWS ! _RTAPT-CPF-REGION-COLS !
    _RTAPT-CPF-REGION-Y ! _RTAPT-CPF-REGION-X !
    _RTAPT-CPF-REGION-ID ! _RTAPT-CPF-SURFACE-ROWS !
    _RTAPT-CPF-SURFACE-COLS ! _RTAPT-CPF-GEN ! _RTAPT-CPF-OWNER !
    ['] _RTAPT-CONTROL-PREFLIGHT-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-CONTROL-PREFLIGHT-SCRUB ;

\ =====================================================================
\  Aggregate-only hybrid CONTROL / residual GLYPH-RUN admission
\ =====================================================================
\
\ The neutral layer has already made the sole pass over each present caller
\ bank.  This provider sees only a fixed, pointer-free summary and combines
\ both representation families before either initial owner admission or an
\ exact-open-owner replacement check against the existing reservation.

VARIABLE _RTAPT-HAF-SUMMARY
VARIABLE _RTAPT-HAF-E
VARIABLE _RTAPT-HAF-LIMITS
VARIABLE _RTAPT-HAF-OWNER
VARIABLE _RTAPT-HAF-GEN
VARIABLE _RTAPT-HAF-SURFACE-COLS
VARIABLE _RTAPT-HAF-SURFACE-ROWS
VARIABLE _RTAPT-HAF-REGION-ID
VARIABLE _RTAPT-HAF-REGION-X
VARIABLE _RTAPT-HAF-REGION-Y
VARIABLE _RTAPT-HAF-REGION-COLS
VARIABLE _RTAPT-HAF-REGION-ROWS
VARIABLE _RTAPT-HAF-REGION-Z
VARIABLE _RTAPT-HAF-REGION-FLAGS
VARIABLE _RTAPT-HAF-CONTROL-COUNT
VARIABLE _RTAPT-HAF-CONTROL-TEXT
VARIABLE _RTAPT-HAF-CONTROL-ALIGNED
VARIABLE _RTAPT-HAF-CONTROL-MAX
VARIABLE _RTAPT-HAF-CONTROL-LAST
VARIABLE _RTAPT-HAF-GLYPH-COUNT
VARIABLE _RTAPT-HAF-GLYPH-TEXT
VARIABLE _RTAPT-HAF-GLYPH-ALIGNED
VARIABLE _RTAPT-HAF-GLYPH-MAX
VARIABLE _RTAPT-HAF-GLYPH-LAST
VARIABLE _RTAPT-HAF-FAMILY-COUNT
VARIABLE _RTAPT-HAF-FAMILY-TEXT
VARIABLE _RTAPT-HAF-FAMILY-ALIGNED
VARIABLE _RTAPT-HAF-FAMILY-MAX
VARIABLE _RTAPT-HAF-FAMILY-LAST
VARIABLE _RTAPT-HAF-COUNT
VARIABLE _RTAPT-HAF-UTF8
VARIABLE _RTAPT-HAF-COPY
VARIABLE _RTAPT-HAF-OPS
VARIABLE _RTAPT-HAF-TX
CREATE _RTAPT-HAF-OWNED-END

: _RTAPT-HAF-OWNED-DISJOINT?  ( a u -- flag )
    2DUP _RTAPT-HAF-OWNED-START
        _RTAPT-HAF-OWNED-END _RTAPT-HAF-OWNED-START -
        MSPAN-OVERLAP? 0= NIP NIP ;

: _RTAPT-HAF-AUTHORITY?  ( summary engine -- flag )
    OVER RTAPT-HYBRID-ADMISSION-SIZE _RTAPT-SPAN? 0= IF
        2DROP 0 EXIT
    THEN
    OVER RTAPT-HYBRID-ADMISSION-SIZE
        _RTAPT-HAF-OWNED-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    _RTAPT-HAF-OWNED-START
        _RTAPT-HAF-OWNED-END _RTAPT-HAF-OWNED-START -
        2 PICK RTAPT-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    OVER RTAPT-HYBRID-ADMISSION-SIZE 2 PICK
        RTAPT-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DROP -1 ;

: _RTAPT-HAF-COPY-SUMMARY  ( -- )
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.OWNER @ _RTAPT-HAF-OWNER !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.GENERATION @ _RTAPT-HAF-GEN !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.SURFACE-COLS @
        _RTAPT-HAF-SURFACE-COLS !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.SURFACE-ROWS @
        _RTAPT-HAF-SURFACE-ROWS !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.REGION-ID @ _RTAPT-HAF-REGION-ID !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.REGION-X @ _RTAPT-HAF-REGION-X !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.REGION-Y @ _RTAPT-HAF-REGION-Y !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.REGION-COLS @ _RTAPT-HAF-REGION-COLS !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.REGION-ROWS @ _RTAPT-HAF-REGION-ROWS !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.REGION-Z @ _RTAPT-HAF-REGION-Z !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.REGION-FLAGS @
        _RTAPT-HAF-REGION-FLAGS !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.CONTROL-COUNT @
        _RTAPT-HAF-CONTROL-COUNT !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.CONTROL-TEXT @
        _RTAPT-HAF-CONTROL-TEXT !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.CONTROL-ALIGNED @
        _RTAPT-HAF-CONTROL-ALIGNED !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.CONTROL-MAX @
        _RTAPT-HAF-CONTROL-MAX !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.CONTROL-LAST @
        _RTAPT-HAF-CONTROL-LAST !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.GLYPH-COUNT @
        _RTAPT-HAF-GLYPH-COUNT !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.GLYPH-TEXT @
        _RTAPT-HAF-GLYPH-TEXT !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.GLYPH-ALIGNED @
        _RTAPT-HAF-GLYPH-ALIGNED !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.GLYPH-MAX @
        _RTAPT-HAF-GLYPH-MAX !
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.GLYPH-LAST @
        _RTAPT-HAF-GLYPH-LAST ! ;

: _RTAPT-HAF-HEADER?  ( -- flag )
    _RTAPT-HAF-SUMMARY @ _RTAPT-HA.RESERVED @ IF 0 EXIT THEN
    _RTAPT-HAF-OWNER @ 0= _RTAPT-HAF-GEN @ 0= OR
    _RTAPT-HAF-REGION-ID @ 0= OR IF 0 EXIT THEN
    _RTAPT-HAF-SURFACE-COLS @ DUP 0= SWAP _RTAPT-U32? 0= OR
    _RTAPT-HAF-SURFACE-ROWS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF
        0 EXIT
    THEN
    _RTAPT-HAF-REGION-X @ _RTAPT-U32? 0=
    _RTAPT-HAF-REGION-Y @ _RTAPT-U32? 0= OR
    _RTAPT-HAF-REGION-COLS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR
    _RTAPT-HAF-REGION-ROWS @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF
        0 EXIT
    THEN
    _RTAPT-HAF-REGION-X @ _RTAPT-HAF-REGION-COLS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-SURFACE-COLS @ U> IF 0 EXIT THEN
    _RTAPT-HAF-REGION-Y @ _RTAPT-HAF-REGION-ROWS @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-SURFACE-ROWS @ U> IF 0 EXIT THEN
    _RTAPT-HAF-REGION-Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-HAF-REGION-FLAGS @ 3 INVERT AND 0= ;

: _RTAPT-HAF-FAMILY?  ( count text aligned max last -- flag )
    _RTAPT-HAF-FAMILY-LAST ! _RTAPT-HAF-FAMILY-MAX !
    _RTAPT-HAF-FAMILY-ALIGNED ! _RTAPT-HAF-FAMILY-TEXT !
    _RTAPT-HAF-FAMILY-COUNT !
    _RTAPT-HAF-FAMILY-COUNT @ 0= IF
        _RTAPT-HAF-FAMILY-TEXT @ _RTAPT-HAF-FAMILY-ALIGNED @ OR
        _RTAPT-HAF-FAMILY-MAX @ OR _RTAPT-HAF-FAMILY-LAST @ OR 0= EXIT
    THEN
    _RTAPT-HAF-FAMILY-COUNT @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-HAF-FAMILY-TEXT @ 0<
    _RTAPT-HAF-FAMILY-ALIGNED @ 0< OR
    _RTAPT-HAF-FAMILY-MAX @ 0< OR IF 0 EXIT THEN
    _RTAPT-HAF-FAMILY-ALIGNED @ 7 AND IF 0 EXIT THEN
    _RTAPT-HAF-FAMILY-TEXT @ _RTAPT-HAF-FAMILY-ALIGNED @ U> IF
        0 EXIT
    THEN
    _RTAPT-HAF-FAMILY-MAX @ _RTAPT-HAF-FAMILY-TEXT @ U> IF 0 EXIT THEN
    _RTAPT-HAF-FAMILY-COUNT @ 7 _RTAPT-UMUL? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-FAMILY-ALIGNED @ _RTAPT-HAF-FAMILY-TEXT @ -
        SWAP U> IF 0 EXIT THEN
    _RTAPT-HAF-FAMILY-LAST @ DUP 0=
    SWAP _RTAPT-HAF-FAMILY-COUNT @ U< OR 0= ;

: _RTAPT-HAF-FIELDS?  ( -- flag )
    _RTAPT-HAF-COPY-SUMMARY
    _RTAPT-HAF-HEADER? 0= IF 0 EXIT THEN
    _RTAPT-HAF-CONTROL-COUNT @ _RTAPT-HAF-CONTROL-TEXT @
    _RTAPT-HAF-CONTROL-ALIGNED @ _RTAPT-HAF-CONTROL-MAX @
    _RTAPT-HAF-CONTROL-LAST @ _RTAPT-HAF-FAMILY? 0= IF 0 EXIT THEN
    _RTAPT-HAF-GLYPH-COUNT @ _RTAPT-HAF-GLYPH-TEXT @
    _RTAPT-HAF-GLYPH-ALIGNED @ _RTAPT-HAF-GLYPH-MAX @
    _RTAPT-HAF-GLYPH-LAST @ _RTAPT-HAF-FAMILY? 0= IF 0 EXIT THEN
    _RTAPT-HAF-CONTROL-COUNT @ _RTAPT-HAF-GLYPH-COUNT @ OR 0<> ;

: _RTAPT-HAF-ARITHMETIC?  ( -- flag )
    _RTAPT-HAF-CONTROL-COUNT @ _RTAPT-HAF-GLYPH-COUNT @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-HAF-COUNT !
    1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-U32? 0= IF DROP 0 EXIT THEN _RTAPT-HAF-OPS !

    _RTAPT-HAF-CONTROL-TEXT @ _RTAPT-HAF-GLYPH-TEXT @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-HAF-UTF8 !

    _RTAPT-HAF-CONTROL-COUNT @ _RTAPT-CONTROL-COPY-FIXED
        _RTAPT-UMUL? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-CONTROL-ALIGNED @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-GLYPH-COUNT @ _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED
        _RTAPT-UMUL? 0= IF DROP 0 EXIT THEN
    _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-GLYPH-ALIGNED @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-REGION-DEFINE-COPY-SIZE _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-COPY !

    _RTAPT-HAF-CONTROL-COUNT @ _RTAPT-CONTROL-FRAME-FIXED
        _RTAPT-UMUL? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-CONTROL-TEXT @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-GLYPH-COUNT @ _RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED
        _RTAPT-UMUL? 0= IF DROP 0 EXIT THEN
    _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-HAF-GLYPH-TEXT @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-UPDATE-ENVELOPE-FRAME-BYTES
        _RTAPT-REGION-DEFINE-FRAME-BYTES + _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-HAF-TX !
    -1 ;

: _RTAPT-HAF-EXISTING-ADMISSION  ( owner-record -- status )
    DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN <> IF
        DROP RTAPT-S-BUSY EXIT
    THEN
    DUP _RTAPT-O.REGIONS @ 1 U< IF DROP RTAPT-S-CAPACITY EXIT THEN
    DUP _RTAPT-O.OBJECTS @ _RTAPT-HAF-COUNT @ U< IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    DUP _RTAPT-O.UTF8-BYTES @ _RTAPT-HAF-UTF8 @ U< IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    DROP RTAPT-S-OK ;

\ A complete REPLACE_START consumes one target within quotas already held by
\ its exact open owner.  It must not reserve the same owner or global quota a
\ second time.  An absent exact generation retains the initial admission path,
\ which also preserves owner-ID collision and tombstone-reuse policy.
: _RTAPT-HAF-OWNER-ADMISSION  ( -- status )
    _RTAPT-HAF-OWNER @ _RTAPT-HAF-GEN @ _RTAPT-HAF-E @
        _RTAPT-OWNER-FIND ?DUP IF
        _RTAPT-HAF-EXISTING-ADMISSION EXIT
    THEN
    _RTAPT-LPF-OWNER-ADMISSION ;

: _RTAPT-HYBRID-PREFLIGHT-BODY  ( -- status )
    _RTAPT-HAF-E @ _RTAPT-ENGINE-VALID? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-HAF-FIELDS? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-HAF-E @ _RTAPT-LIMITS-AFTER-VALID@
        DUP RTAPT-S-OK <> IF NIP EXIT THEN
    DROP DUP _RTAPT-HAF-LIMITS ! _RTAPT-LPF-LIMITS !

    _RTAPT-HAF-CONTROL-COUNT @ IF
        _RTAPT-HAF-LIMITS @ _RTAPT-L.FEATURES @
            RTAPT-F-CONTROLS AND 0= IF RTAPT-S-UNSUPPORTED EXIT THEN
    THEN
    _RTAPT-HAF-GLYPH-COUNT @ IF
        _RTAPT-HAF-LIMITS @ _RTAPT-L.GLYPH-RUN-BYTES @ 0= IF
            RTAPT-S-UNSUPPORTED EXIT
        THEN
    THEN

    _RTAPT-HAF-ARITHMETIC? 0= IF RTAPT-S-CAPACITY EXIT THEN

    _RTAPT-HAF-CONTROL-COUNT @ IF
        _RTAPT-HAF-CONTROL-MAX @ 80 _RTAPT-UADD? 0= IF
            DROP RTAPT-S-CAPACITY EXIT
        THEN
        _RTAPT-HAF-LIMITS @ _RTAPT-L.OUTBOUND-PAYLOAD @ U> IF
            RTAPT-S-CAPACITY EXIT
        THEN
    THEN
    _RTAPT-HAF-GLYPH-COUNT @ IF
        _RTAPT-HAF-GLYPH-MAX @
            _RTAPT-HAF-LIMITS @ _RTAPT-L.GLYPH-RUN-BYTES @ U> IF
            RTAPT-S-CAPACITY EXIT
        THEN
    THEN
    _RTAPT-HAF-OPS @ _RTAPT-HAF-LIMITS @ _RTAPT-L.OPS @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-HAF-OPS @ _RTAPT-HAF-E @ _RTAPT-E.OP-CAP @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-HAF-COPY @ _RTAPT-HAF-E @ _RTAPT-E.COPY-U @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-HAF-TX @ _RTAPT-HAF-LIMITS @ _RTAPT-L.UPDATE-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-HAF-UTF8 @ _RTAPT-HAF-LIMITS @ _RTAPT-L.UTF8-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-HAF-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <>
    _RTAPT-HAF-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> OR
    _RTAPT-HAF-E @ _RTAPT-E.QUEUE-HEAD @ OR
    _RTAPT-HAF-E @ _RTAPT-E.QUEUE-TAIL @ OR IF RTAPT-S-BUSY EXIT THEN

    _RTAPT-HAF-OWNER @ _RTAPT-LPF-OWNER !
    _RTAPT-HAF-GEN @ _RTAPT-LPF-GEN !
    _RTAPT-HAF-COUNT @ _RTAPT-LPF-COUNT !
    _RTAPT-HAF-UTF8 @ _RTAPT-LPF-UTF8 !
    _RTAPT-HAF-E @ _RTAPT-LPF-E !
    _RTAPT-HAF-OWNER-ADMISSION ;

: _RTAPT-HAF-SCRUB  ( status -- status )
    0 _RTAPT-HAF-SUMMARY ! 0 _RTAPT-HAF-E ! 0 _RTAPT-HAF-LIMITS !
    0 _RTAPT-HAF-OWNER ! 0 _RTAPT-HAF-GEN !
    0 _RTAPT-HAF-SURFACE-COLS ! 0 _RTAPT-HAF-SURFACE-ROWS !
    0 _RTAPT-HAF-REGION-ID ! 0 _RTAPT-HAF-REGION-X !
    0 _RTAPT-HAF-REGION-Y ! 0 _RTAPT-HAF-REGION-COLS !
    0 _RTAPT-HAF-REGION-ROWS ! 0 _RTAPT-HAF-REGION-Z !
    0 _RTAPT-HAF-REGION-FLAGS !
    0 _RTAPT-HAF-CONTROL-COUNT ! 0 _RTAPT-HAF-CONTROL-TEXT !
    0 _RTAPT-HAF-CONTROL-ALIGNED ! 0 _RTAPT-HAF-CONTROL-MAX !
    0 _RTAPT-HAF-CONTROL-LAST ! 0 _RTAPT-HAF-GLYPH-COUNT !
    0 _RTAPT-HAF-GLYPH-TEXT ! 0 _RTAPT-HAF-GLYPH-ALIGNED !
    0 _RTAPT-HAF-GLYPH-MAX ! 0 _RTAPT-HAF-GLYPH-LAST !
    0 _RTAPT-HAF-FAMILY-COUNT ! 0 _RTAPT-HAF-FAMILY-TEXT !
    0 _RTAPT-HAF-FAMILY-ALIGNED ! 0 _RTAPT-HAF-FAMILY-MAX !
    0 _RTAPT-HAF-FAMILY-LAST ! 0 _RTAPT-HAF-COUNT !
    0 _RTAPT-HAF-UTF8 ! 0 _RTAPT-HAF-COPY !
    0 _RTAPT-HAF-OPS ! 0 _RTAPT-HAF-TX !
    _RTAPT-LPF-SCRUB ;

: RTAPT-HYBRID-PREFLIGHT  ( checked-summary engine -- status )
    2DUP _RTAPT-HAF-AUTHORITY? 0= IF
        2DROP RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-HAF-E ! _RTAPT-HAF-SUMMARY !
    ['] _RTAPT-HYBRID-PREFLIGHT-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-HAF-SCRUB ;

: RTAPT-UPDATE-STATE@  ( engine -- update-state status )
    \ This is a phase observation, not a publication boundary.  Polling a
    \ sealed candidate must remain constant-time; its sole exhaustive audit
    \ runs immediately before serialization.
    DUP _RTAPT-ENGINE-STORAGE? 0= IF
        DROP RTAPT-UPDATE-IDLE RTAPT-S-INVALID EXIT
    THEN
    DUP _RTAPT-E.UPDATE-STATE @ DUP RTAPT-UPDATE-AWAITING U> IF
        2DROP RTAPT-UPDATE-IDLE RTAPT-S-INVALID EXIT
    THEN
    SWAP _RTAPT-E.LAST-STATUS @ ;

\ Return the immutable presentation tuple only while the caller-owned
\ retained candidate is sealed.  This query exposes no capture storage and
\ cannot advance, cancel, or publish the candidate.
: RTAPT-SEALED-PRESENTATION@
  ( engine -- retained-mode disposition status )
    DUP _RTAPT-ENGINE-STORAGE? 0= IF
        DROP 0 0 RTAPT-S-INVALID EXIT
    THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-SEALED <> IF
        DROP 0 0 RTAPT-S-BUSY EXIT
    THEN
    DUP _RTAPT-SEALED-READY? 0= IF
        DROP 0 0 RTAPT-S-INVALID EXIT
    THEN
    DUP _RTAPT-E.RET-MODE @ SWAP _RTAPT-E.DISPOSITION @
    RTAPT-S-OK ;

VARIABLE _RTAPT-RB-E
VARIABLE _RTAPT-RB-MODE

: RTAPT-RICH-BEGIN  ( retained-mode engine -- status )
    _RTAPT-RB-E ! _RTAPT-RB-MODE !
    _RTAPT-RB-E @ _RTAPT-ENGINE-VALID? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RB-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-RB-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-RB-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <>
    _RTAPT-RB-E @ _RTAPT-E.QUEUE-HEAD @ OR
    _RTAPT-RB-E @ _RTAPT-E.QUEUE-TAIL @ OR IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-RB-MODE @ _RTAPT-MODE? 0= IF RTAPT-S-INVALID EXIT THEN
    \ Discovery is immutable for this session.  Refresh its engine-owned
    \ snapshot once per candidate instead of rediscovering and fully auditing
    \ the growing captured prefix for every retained definition.
    _RTAPT-RB-E @ RTAPT-LIMITS@ DUP RTAPT-S-OK <> IF NIP EXIT THEN 2DROP
    _RTAPT-RB-MODE @ _RTAPT-RB-E @ _RTAPT-E.RET-MODE !
    PT-COMMIT _RTAPT-RB-E @ _RTAPT-E.DISPOSITION !
    RTAPT-UPDATE-CAPTURING _RTAPT-RB-E @ _RTAPT-E.UPDATE-STATE !
    RTAPT-S-OK DUP _RTAPT-RB-E @ _RTAPT-E.LAST-STATUS ! ;

VARIABLE _RTAPT-RD-E
VARIABLE _RTAPT-RD-O
VARIABLE _RTAPT-RD-P
VARIABLE _RTAPT-RD-COPY
VARIABLE _RTAPT-RD-OWNER
VARIABLE _RTAPT-RD-GEN
VARIABLE _RTAPT-RD-ID
VARIABLE _RTAPT-RD-X
VARIABLE _RTAPT-RD-Y
VARIABLE _RTAPT-RD-COLS
VARIABLE _RTAPT-RD-ROWS
VARIABLE _RTAPT-RD-Z
VARIABLE _RTAPT-RD-FLAGS
VARIABLE _RTAPT-RD-NEXT-COPY
VARIABLE _RTAPT-RD-NEXT-RET
VARIABLE _RTAPT-RD-NEXT-PENDING
VARIABLE _RTAPT-RD-BASE

: _RTAPT-REGION-BASE  ( owner-record engine -- count )
    _RTAPT-RD-E ! _RTAPT-RD-O !
    _RTAPT-RD-E @ _RTAPT-E.RET-MODE @ DUP PT-RET-DELTA =
    OVER PT-RET-LAYOUT-START = OR IF
        DROP _RTAPT-RD-O @ _RTAPT-O.ACTIVE-REGIONS @ EXIT
    THEN
    PT-RET-REPLACE-START = IF 0 EXIT THEN
    _RTAPT-RD-O @ _RTAPT-O.HIDDEN-REGIONS @ ;

: RTAPT-REGION-DEFINE  ( owner generation region x y cols rows z flags engine -- status )
    _RTAPT-RD-E ! _RTAPT-RD-FLAGS ! _RTAPT-RD-Z ! _RTAPT-RD-ROWS !
    _RTAPT-RD-COLS ! _RTAPT-RD-Y ! _RTAPT-RD-X ! _RTAPT-RD-ID !
    _RTAPT-RD-GEN ! _RTAPT-RD-OWNER !
    _RTAPT-RD-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-RD-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CAPTURING <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-RD-E @ _RTAPT-CAPTURE-READY? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-OWNER @ 0= _RTAPT-RD-GEN @ 0= OR
    _RTAPT-RD-ID @ 0= OR IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-X @ _RTAPT-U32? 0= _RTAPT-RD-Y @ _RTAPT-U32? 0= OR
    _RTAPT-RD-COLS @ _RTAPT-U32? 0= OR
    _RTAPT-RD-ROWS @ _RTAPT-U32? 0= OR IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-COLS @ 0= _RTAPT-RD-ROWS @ 0= OR IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-X @ _RTAPT-RD-COLS @ _RTAPT-UADD? 0= IF
        DROP RTAPT-S-INVALID EXIT
    THEN 0xFFFFFFFF U> IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-Y @ _RTAPT-RD-ROWS @ _RTAPT-UADD? 0= IF
        DROP RTAPT-S-INVALID EXIT
    THEN 0xFFFFFFFF U> IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-Z @ _RTAPT-I32? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-FLAGS @ 3 INVERT AND IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-OWNER @ _RTAPT-RD-GEN @ _RTAPT-RD-E @
        _RTAPT-OWNER-FIND DUP 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-RD-O ! _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-RD-ID @ _RTAPT-RD-O @ _RTAPT-O.REGION-HIGH @ U> 0=
        IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-ID @ _RTAPT-RD-O @ _RTAPT-O.PENDING-REGION-HIGH @ U> 0=
        IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RD-O @ _RTAPT-RD-E @ _RTAPT-REGION-BASE _RTAPT-RD-BASE !
    _RTAPT-RD-BASE @ _RTAPT-RD-O @ _RTAPT-O.PENDING-REGIONS @
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    1 _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    DUP _RTAPT-RD-NEXT-PENDING !
    _RTAPT-RD-O @ _RTAPT-O.REGIONS @ U> IF RTAPT-S-CAPACITY EXIT THEN
    \ PRESENT_BEGIN carries retained-op-count as an exact u32 wire field.
    _RTAPT-RD-E @ _RTAPT-E.OP-COUNT @ 0xFFFFFFFF U< 0=
        IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-RD-E @ _RTAPT-E.OP-COUNT @
        _RTAPT-RD-E @ _RTAPT-E.OP-CAP @ U< 0= IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-RD-E @ _RTAPT-E.COPY-U @
        _RTAPT-RD-E @ _RTAPT-E.COPY-USED @ -
        _RTAPT-REGION-DEFINE-COPY-SIZE U< IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-RD-E @ _RTAPT-E.COPY-USED @
        _RTAPT-REGION-DEFINE-COPY-SIZE _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-RD-NEXT-COPY !
    _RTAPT-RD-E @ _RTAPT-E.RET-BYTES @
        _RTAPT-REGION-DEFINE-FRAME-BYTES _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-RD-NEXT-RET !
    _RTAPT-RD-E @ _RTAPT-E.OP-COUNT @ _RTAPT-RD-E @ _RTAPT-OP-NTH
        _RTAPT-RD-P !
    _RTAPT-RD-E @ _RTAPT-E.COPY-A @
        _RTAPT-RD-E @ _RTAPT-E.COPY-USED @ + _RTAPT-RD-COPY !
    _RTAPT-RD-P @ RTAPT-OP-SIZE 0 FILL
    _RTAPT-OP-REGION-DEFINE _RTAPT-RD-P @ _RTAPT-P.KIND !
    _RTAPT-RD-E @ _RTAPT-E.COPY-USED @
        _RTAPT-RD-P @ _RTAPT-P.COPY-OFF !
    _RTAPT-REGION-DEFINE-COPY-SIZE _RTAPT-RD-P @ _RTAPT-P.COPY-U !
    _RTAPT-RD-O @ _RTAPT-RD-E @ _RTAPT-OWNER-SLOT
        _RTAPT-RD-P @ _RTAPT-P.OWNER-SLOT !
    _RTAPT-RD-OWNER @ _RTAPT-RD-COPY @ _RTAPT-RD.OWNER !
    _RTAPT-RD-GEN @ _RTAPT-RD-COPY @ _RTAPT-RD.GENERATION !
    _RTAPT-RD-ID @ _RTAPT-RD-COPY @ _RTAPT-RD.REGION !
    _RTAPT-RD-X @ _RTAPT-RD-COPY @ _RTAPT-RD.X !
    _RTAPT-RD-Y @ _RTAPT-RD-COPY @ _RTAPT-RD.Y !
    _RTAPT-RD-COLS @ _RTAPT-RD-COPY @ _RTAPT-RD.COLS !
    _RTAPT-RD-ROWS @ _RTAPT-RD-COPY @ _RTAPT-RD.ROWS !
    _RTAPT-RD-Z @ _RTAPT-RD-COPY @ _RTAPT-RD.Z !
    _RTAPT-RD-FLAGS @ _RTAPT-RD-COPY @ _RTAPT-RD.FLAGS !
    _RTAPT-RD-O @ _RTAPT-O.PENDING-REGIONS @ 1+
        _RTAPT-RD-O @ _RTAPT-O.PENDING-REGIONS !
    _RTAPT-RD-ID @ _RTAPT-RD-O @ _RTAPT-O.PENDING-REGION-HIGH !
    _RTAPT-RD-NEXT-COPY @ _RTAPT-RD-E @ _RTAPT-E.COPY-USED !
    _RTAPT-RD-NEXT-RET @ _RTAPT-RD-E @ _RTAPT-E.RET-BYTES !
    1 _RTAPT-RD-E @ _RTAPT-E.OP-COUNT +!
    RTAPT-S-OK DUP _RTAPT-RD-E @ _RTAPT-E.LAST-STATUS ! ;

\ =====================================================================
\  Neutral GLYPH-RUN capture
\ =====================================================================

VARIABLE _RTAPT-LD-E
VARIABLE _RTAPT-LD-O
VARIABLE _RTAPT-LD-P
VARIABLE _RTAPT-LD-COPY
VARIABLE _RTAPT-LD-OWNER
VARIABLE _RTAPT-LD-GEN
VARIABLE _RTAPT-LD-OBJECT
VARIABLE _RTAPT-LD-REGION
VARIABLE _RTAPT-LD-PARENT
VARIABLE _RTAPT-LD-ROW
VARIABLE _RTAPT-LD-COL
VARIABLE _RTAPT-LD-HEIGHT
VARIABLE _RTAPT-LD-WIDTH
VARIABLE _RTAPT-LD-ROOT-H
VARIABLE _RTAPT-LD-ROOT-W
VARIABLE _RTAPT-LD-Z
VARIABLE _RTAPT-LD-VISIBLE
VARIABLE _RTAPT-LD-FG-RGBA
VARIABLE _RTAPT-LD-BG-RGBA
VARIABLE _RTAPT-LD-ATTRS
VARIABLE _RTAPT-LD-TEXT-A
VARIABLE _RTAPT-LD-TEXT-U
VARIABLE _RTAPT-LD-LEFT
VARIABLE _RTAPT-LD-TOP
VARIABLE _RTAPT-LD-RIGHT
VARIABLE _RTAPT-LD-BOTTOM
VARIABLE _RTAPT-LD-ROW-END
VARIABLE _RTAPT-LD-COL-END
VARIABLE _RTAPT-LD-NEXT-COPY
VARIABLE _RTAPT-LD-NEXT-RET
VARIABLE _RTAPT-LD-NEXT-OBJECTS
VARIABLE _RTAPT-LD-NEXT-UTF8
VARIABLE _RTAPT-LD-COPY-U
VARIABLE _RTAPT-LD-REGION-OP

VARIABLE _RTAPT-UN-B
VARIABLE _RTAPT-UN-R
VARIABLE _RTAPT-UN-Q
VARIABLE _RTAPT-UN-REM

: _RTAPT-UNORM32-HIGH  ( boundary root -- u32 )
    _RTAPT-UN-R ! _RTAPT-UN-B !
    _RTAPT-UN-B @ 0= IF 0 EXIT THEN
    _RTAPT-UN-B @ _RTAPT-UN-R @ = IF 0xFFFFFFFF EXIT THEN
    0xFFFFFFFF _RTAPT-UN-R @ /MOD _RTAPT-UN-Q ! _RTAPT-UN-REM !
    _RTAPT-UN-B @ _RTAPT-UN-Q @ *
    _RTAPT-UN-B @ _RTAPT-UN-REM @ * _RTAPT-UN-R @ / + ;

\ Low APT edges are rasterized with floor, so encode them with ceiling.
\ Complementing the high-edge floor avoids a boundary*0xFFFFFFFF product.
: _RTAPT-UNORM32-LOW  ( boundary root -- u32 )
    TUCK SWAP - SWAP _RTAPT-UNORM32-HIGH
    0xFFFFFFFF SWAP - ;

: _RTAPT-CANONICAL-FLAG?  ( flag -- valid? )
    DUP 0= SWAP -1 = OR ;

: _RTAPT-GLYPH-RUN-GEOMETRY?  ( -- flag )
    _RTAPT-LD-ROW @ _RTAPT-I32? 0=
    _RTAPT-LD-COL @ _RTAPT-I32? 0= OR IF 0 EXIT THEN
    _RTAPT-LD-HEIGHT @ _RTAPT-U32? 0=
    _RTAPT-LD-WIDTH @ _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-LD-ROOT-H @ DUP 0= SWAP _RTAPT-U32? 0= OR
    _RTAPT-LD-ROOT-W @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF 0 EXIT THEN
    _RTAPT-LD-ROW @ _RTAPT-LD-HEIGHT @ + _RTAPT-LD-ROW-END !
    _RTAPT-LD-COL @ _RTAPT-LD-WIDTH @ + _RTAPT-LD-COL-END !
    _RTAPT-LD-VISIBLE @ IF
        _RTAPT-LD-HEIGHT @ 0= _RTAPT-LD-WIDTH @ 0= OR
        _RTAPT-LD-ROW @ _RTAPT-LD-ROOT-H @ < 0= OR
        _RTAPT-LD-ROW-END @ 0> 0= OR
        _RTAPT-LD-COL @ _RTAPT-LD-ROOT-W @ < 0= OR
        _RTAPT-LD-COL-END @ 0> 0= OR IF 0 EXIT THEN
    THEN
    _RTAPT-LD-COL @ 0 MAX _RTAPT-LD-ROOT-W @ 1- MIN _RTAPT-LD-LEFT !
    _RTAPT-LD-COL-END @ 0 MAX _RTAPT-LD-ROOT-W @ MIN
    _RTAPT-LD-LEFT @ 1+ MAX _RTAPT-LD-ROOT-W @ MIN _RTAPT-LD-RIGHT !
    _RTAPT-LD-ROW @ 0 MAX _RTAPT-LD-ROOT-H @ 1- MIN _RTAPT-LD-TOP !
    _RTAPT-LD-ROW-END @ 0 MAX _RTAPT-LD-ROOT-H @ MIN
    _RTAPT-LD-TOP @ 1+ MAX _RTAPT-LD-ROOT-H @ MIN _RTAPT-LD-BOTTOM !
    _RTAPT-LD-LEFT @ _RTAPT-LD-ROOT-W @
        _RTAPT-UNORM32-LOW _RTAPT-LD-LEFT !
    _RTAPT-LD-TOP @ _RTAPT-LD-ROOT-H @
        _RTAPT-UNORM32-LOW _RTAPT-LD-TOP !
    _RTAPT-LD-RIGHT @ _RTAPT-LD-ROOT-W @
        _RTAPT-UNORM32-HIGH _RTAPT-LD-RIGHT !
    _RTAPT-LD-BOTTOM @ _RTAPT-LD-ROOT-H @
        _RTAPT-UNORM32-HIGH _RTAPT-LD-BOTTOM !
    _RTAPT-LD-LEFT @ _RTAPT-LD-RIGHT @ U<
    _RTAPT-LD-TOP @ _RTAPT-LD-BOTTOM @ U< AND ;

: _RTAPT-GLYPH-RUN-FORBIDDEN-BYTE?  ( byte -- flag )
    DUP 0= OVER 10 = OR SWAP 13 = OR ;

VARIABLE _RTAPT-LU-I
VARIABLE _RTAPT-LU-B0
VARIABLE _RTAPT-LU-B1
VARIABLE _RTAPT-LU-A
VARIABLE _RTAPT-LU-U

: _RTAPT-LUTF8-FINISH  ( flag -- flag )
    0 _RTAPT-LU-I ! 0 _RTAPT-LU-B0 ! 0 _RTAPT-LU-B1 !
    0 _RTAPT-LU-A ! 0 _RTAPT-LU-U ! ;

: _RTAPT-LUTF8-CONT?  ( relative-index -- flag )
    _RTAPT-LU-I @ + DUP _RTAPT-LU-U @ U< 0= IF DROP 0 EXIT THEN
    _RTAPT-LU-A @ + C@ 0xC0 AND 0x80 = ;

\ Validate scalar UTF-8 and the APT GLYPH-RUN control exclusions without leaving
\ the borrowed source in another module's validator scratch.
: _RTAPT-GLYPH-RUN-UTF8?  ( a u -- flag )
    _RTAPT-LU-U ! _RTAPT-LU-A !
    0 _RTAPT-LU-I !
    BEGIN _RTAPT-LU-I @ _RTAPT-LU-U @ U< WHILE
        _RTAPT-LU-A @ _RTAPT-LU-I @ + C@ DUP _RTAPT-LU-B0 !
        DUP _RTAPT-GLYPH-RUN-FORBIDDEN-BYTE? IF
            DROP 0 _RTAPT-LUTF8-FINISH EXIT
        THEN
        0x80 U< IF
            1 _RTAPT-LU-I +!
        ELSE
            _RTAPT-LU-B0 @ 0xC2 >= _RTAPT-LU-B0 @ 0xDF <= AND IF
                1 _RTAPT-LUTF8-CONT? 0= IF
                    0 _RTAPT-LUTF8-FINISH EXIT
                THEN
                2 _RTAPT-LU-I +!
            ELSE
                _RTAPT-LU-B0 @ 0xE0 >= _RTAPT-LU-B0 @ 0xEF <= AND IF
                    _RTAPT-LU-U @ _RTAPT-LU-I @ - 3 U< IF
                        0 _RTAPT-LUTF8-FINISH EXIT
                    THEN
                    _RTAPT-LU-A @ _RTAPT-LU-I @ + 1+ C@
                        _RTAPT-LU-B1 !
                    _RTAPT-LU-B0 @ 0xE0 = IF
                        _RTAPT-LU-B1 @ 0xA0 >=
                        _RTAPT-LU-B1 @ 0xBF <= AND
                    ELSE
                        _RTAPT-LU-B0 @ 0xED = IF
                            _RTAPT-LU-B1 @ 0x80 >=
                            _RTAPT-LU-B1 @ 0x9F <= AND
                        ELSE
                            _RTAPT-LU-B1 @ 0xC0 AND 0x80 =
                        THEN
                    THEN
                    2 _RTAPT-LUTF8-CONT? AND 0= IF
                        0 _RTAPT-LUTF8-FINISH EXIT
                    THEN
                    3 _RTAPT-LU-I +!
                ELSE
                    _RTAPT-LU-B0 @ 0xF0 >=
                    _RTAPT-LU-B0 @ 0xF4 <= AND IF
                        _RTAPT-LU-U @ _RTAPT-LU-I @ - 4 U< IF
                            0 _RTAPT-LUTF8-FINISH EXIT
                        THEN
                        _RTAPT-LU-A @ _RTAPT-LU-I @ + 1+ C@
                            _RTAPT-LU-B1 !
                        _RTAPT-LU-B0 @ 0xF0 = IF
                            _RTAPT-LU-B1 @ 0x90 >=
                            _RTAPT-LU-B1 @ 0xBF <= AND
                        ELSE
                            _RTAPT-LU-B0 @ 0xF4 = IF
                                _RTAPT-LU-B1 @ 0x80 >=
                                _RTAPT-LU-B1 @ 0x8F <= AND
                            ELSE
                                _RTAPT-LU-B1 @ 0xC0 AND 0x80 =
                            THEN
                        THEN
                        2 _RTAPT-LUTF8-CONT? AND
                        3 _RTAPT-LUTF8-CONT? AND 0= IF
                            0 _RTAPT-LUTF8-FINISH EXIT
                        THEN
                        4 _RTAPT-LU-I +!
                    ELSE
                        0 _RTAPT-LUTF8-FINISH EXIT
                    THEN
                THEN
            THEN
        THEN
    REPEAT
    -1 _RTAPT-LUTF8-FINISH ;

: _RTAPT-GLYPH-RUN-TEXT-SPAN?  ( -- flag )
    _RTAPT-LD-TEXT-U @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LD-TEXT-U @ 0= IF _RTAPT-LD-TEXT-A @ 0= EXIT THEN
    _RTAPT-LD-TEXT-A @ _RTAPT-LD-TEXT-U @ _RTAPT-LD-E @
        _RTAPT-BYTE-SPAN-DISJOINT? ;

: _RTAPT-SHARED-OBJECT-BASE?  ( owner-record engine -- count flag )
    >R
    DUP _RTAPT-O.ACTIVE-OBJECTS @
    OVER _RTAPT-O.ACTIVE-CONTROLS @ _RTAPT-UADD? 0= IF
        2DROP R> DROP 0 0 EXIT
    THEN
    OVER _RTAPT-O.HIDDEN-OBJECTS @
    2 PICK _RTAPT-O.HIDDEN-CONTROLS @ _RTAPT-UADD? 0= IF
        2DROP DROP R> DROP 0 0 EXIT
    THEN
    ROT DROP R> _RTAPT-TARGET-BASE -1 ;

: _RTAPT-UTF8-BASE  ( owner-record engine -- bytes )
    >R DUP _RTAPT-O.ACTIVE-UTF8 @ SWAP _RTAPT-O.HIDDEN-UTF8 @
    R> _RTAPT-TARGET-BASE ;

VARIABLE _RTAPT-GT-OBJECT
VARIABLE _RTAPT-GT-REGION
VARIABLE _RTAPT-GT-O
VARIABLE _RTAPT-GT-E
VARIABLE _RTAPT-GRP-P
VARIABLE _RTAPT-GRP-OFF
VARIABLE _RTAPT-GRP-NEXT

\ Replacement is not an addition: it must name the already-selected active
\ or hidden target.  The compact engine deliberately keeps aggregate ledgers,
\ not a product-sized identity table.  Counts and global high-water marks can
\ reject an impossible target here; the physical retained model remains the
\ exact authority for sparse-ID existence and object kind.
: _RTAPT-GLYPH-RUN-TARGET?  ( object region owner-record engine -- flag )
    _RTAPT-GT-E ! _RTAPT-GT-O !
    _RTAPT-GT-REGION ! _RTAPT-GT-OBJECT !
    _RTAPT-GT-O @ _RTAPT-O.ACTIVE-OBJECTS @
    _RTAPT-GT-O @ _RTAPT-O.HIDDEN-OBJECTS @
    _RTAPT-GT-E @ _RTAPT-TARGET-BASE 0= IF 0 EXIT THEN
    _RTAPT-GT-OBJECT @ _RTAPT-GT-O @ _RTAPT-O.OBJECT-HIGH @ U> IF
        0 EXIT
    THEN
    _RTAPT-GT-O @ _RTAPT-O.ACTIVE-REGIONS @
    _RTAPT-GT-O @ _RTAPT-O.HIDDEN-REGIONS @
    _RTAPT-GT-E @ _RTAPT-TARGET-BASE 0= IF 0 EXIT THEN
    _RTAPT-GT-REGION @ _RTAPT-GT-O @ _RTAPT-O.REGION-HIGH @ U> 0= ;


\ Definitions name only an exact REGION_DEFINE captured earlier in this
\ candidate.  A region high-water cannot prove sparse-ID existence.  Root
\ parenting is the only truthful parent form until GROUP and exact object-type
\ identity are added together.
: _RTAPT-GLYPH-RUN-REGION-COPY  ( op-record -- copy-record|0 )
    _RTAPT-GRP-P !
    _RTAPT-GRP-P @ _RTAPT-P.COPY-U @
        _RTAPT-REGION-DEFINE-COPY-SIZE <> IF 0 EXIT THEN
    _RTAPT-GRP-P @ _RTAPT-P.COPY-OFF @ DUP _RTAPT-GRP-OFF !
    DUP 7 AND IF DROP 0 EXIT THEN
    _RTAPT-REGION-DEFINE-COPY-SIZE _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-GRP-NEXT !
    _RTAPT-LD-E @ _RTAPT-E.COPY-USED @ U> IF 0 EXIT THEN
    _RTAPT-GRP-NEXT @ _RTAPT-LD-E @ _RTAPT-E.COPY-U @ U> IF 0 EXIT THEN
    _RTAPT-LD-E @ _RTAPT-E.COPY-A @ _RTAPT-GRP-OFF @ + ;

: _RTAPT-GLYPH-RUN-REGION-OP  ( -- region-op+1|0 )
    _RTAPT-LD-E @ _RTAPT-E.OP-COUNT @ 0 ?DO
        I _RTAPT-LD-E @ _RTAPT-OP-NTH
        DUP _RTAPT-P.KIND @ _RTAPT-OP-REGION-DEFINE = IF
            _RTAPT-GLYPH-RUN-REGION-COPY ?DUP 0= IF
                0 UNLOOP EXIT
            THEN
            DUP _RTAPT-RD.OWNER @ _RTAPT-LD-OWNER @ =
            OVER _RTAPT-RD.GENERATION @ _RTAPT-LD-GEN @ = AND
            OVER _RTAPT-RD.REGION @ _RTAPT-LD-REGION @ = AND
            SWAP DROP IF I 1+ UNLOOP EXIT THEN
        ELSE
            DROP
        THEN
    LOOP
    0 ;

: _RTAPT-GLYPH-RUN-FIELDS?  ( -- flag )
    _RTAPT-LD-OWNER @ 0= _RTAPT-LD-GEN @ 0= OR
    _RTAPT-LD-OBJECT @ 0= OR _RTAPT-LD-REGION @ 0= OR IF 0 EXIT THEN
    _RTAPT-LD-PARENT @ IF 0 EXIT THEN
    _RTAPT-LD-Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-LD-VISIBLE @ _RTAPT-CANONICAL-FLAG? 0= IF 0 EXIT THEN
    _RTAPT-LD-FG-RGBA @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LD-BG-RGBA @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-LD-ATTRS @ _RTAPT-GLYPH-RUN-ATTRS? 0= IF 0 EXIT THEN
    _RTAPT-GLYPH-RUN-GEOMETRY? ;

: _RTAPT-GLYPH-RUN-LIMITS  ( -- status )
    _RTAPT-LD-E @ _RTAPT-E.LIMITS
    DUP RTAPT-LIMITS-VALID? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-L.GLYPH-RUN-BYTES @ 0= IF
        DROP RTAPT-S-UNSUPPORTED EXIT
    THEN
    _RTAPT-LD-TEXT-U @ SWAP _RTAPT-L.GLYPH-RUN-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    RTAPT-S-OK ;

: _RTAPT-GLYPH-RUN-DEFINE-BODY  ( -- status )
    _RTAPT-LD-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    \ Prove the borrowed span before READY may mutate engine state.  The
    \ candidate's immutable negotiated-limit snapshot was established once by
    \ RICH-BEGIN.
    _RTAPT-GLYPH-RUN-FIELDS? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-GLYPH-RUN-TEXT-SPAN? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-LD-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-LD-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CAPTURING <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-LD-E @ _RTAPT-CAPTURE-READY? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-GLYPH-RUN-LIMITS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-LD-TEXT-A @ _RTAPT-LD-TEXT-U @ _RTAPT-GLYPH-RUN-UTF8? 0= IF
        RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-LD-OWNER @ _RTAPT-LD-GEN @ _RTAPT-LD-E @
        _RTAPT-OWNER-FIND DUP 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-LD-O ! _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-GLYPH-RUN-REGION-OP DUP 0= IF
        DROP RTAPT-S-INVALID EXIT
    THEN _RTAPT-LD-REGION-OP !
    _RTAPT-LD-OBJECT @ _RTAPT-LD-O @ _RTAPT-O.OBJECT-HIGH @ U> 0=
        IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-LD-OBJECT @ _RTAPT-LD-O @ _RTAPT-O.PENDING-OBJECT-HIGH @ U> 0=
        IF RTAPT-S-INVALID EXIT THEN

    \ PENDING-OBJECTS remains the glyph-only definition ledger.  Admission,
    \ however, is symmetric across append order: the selected committed target
    \ and both pending definition families consume the shared OBJECT quota.
    _RTAPT-LD-O @ _RTAPT-O.PENDING-OBJECTS @ 1 _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-LD-NEXT-OBJECTS !
    _RTAPT-LD-O @ _RTAPT-LD-E @ _RTAPT-SHARED-OBJECT-BASE? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LD-O @ _RTAPT-O.PENDING-OBJECTS @ _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LD-O @ _RTAPT-O.PENDING-CONTROLS @ _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    1 _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-O @ _RTAPT-O.OBJECTS @ U> IF RTAPT-S-CAPACITY EXIT THEN

    _RTAPT-LD-O @ _RTAPT-LD-E @ _RTAPT-UTF8-BASE
    _RTAPT-LD-O @ _RTAPT-O.PENDING-UTF8 @ _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LD-TEXT-U @ _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    DUP _RTAPT-LD-NEXT-UTF8 !
    _RTAPT-LD-O @ _RTAPT-O.UTF8-BYTES @ U> IF RTAPT-S-CAPACITY EXIT THEN

    _RTAPT-LD-E @ _RTAPT-E.OP-COUNT @ 0xFFFFFFFF U< 0=
        IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-E @ _RTAPT-E.OP-COUNT @
        _RTAPT-LD-E @ _RTAPT-E.OP-CAP @ U< 0= IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-TEXT-U @ _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-ALIGN8? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    DUP _RTAPT-LD-COPY-U !
    _RTAPT-LD-E @ _RTAPT-E.COPY-U @
        _RTAPT-LD-E @ _RTAPT-E.COPY-USED @ - U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LD-E @ _RTAPT-E.COPY-USED @ _RTAPT-LD-COPY-U @
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-NEXT-COPY !
    _RTAPT-LD-E @ _RTAPT-E.RET-BYTES @ _RTAPT-LD-TEXT-U @
        _RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-NEXT-RET !

    _RTAPT-LD-E @ _RTAPT-E.OP-COUNT @ _RTAPT-LD-E @ _RTAPT-OP-NTH
        _RTAPT-LD-P !
    _RTAPT-LD-E @ _RTAPT-E.COPY-A @
        _RTAPT-LD-E @ _RTAPT-E.COPY-USED @ + _RTAPT-LD-COPY !
    _RTAPT-LD-P @ RTAPT-OP-SIZE 0 FILL
    _RTAPT-LD-COPY @ _RTAPT-LD-COPY-U @ 0 FILL
    _RTAPT-OP-GLYPH-RUN-DEFINE _RTAPT-LD-P @ _RTAPT-P.KIND !
    _RTAPT-LD-E @ _RTAPT-E.COPY-USED @
        _RTAPT-LD-P @ _RTAPT-P.COPY-OFF !
    _RTAPT-LD-COPY-U @ _RTAPT-LD-P @ _RTAPT-P.COPY-U !
    _RTAPT-LD-O @ _RTAPT-LD-E @ _RTAPT-OWNER-SLOT
        _RTAPT-LD-P @ _RTAPT-P.OWNER-SLOT !
    _RTAPT-LD-REGION-OP @ _RTAPT-LD-P @ _RTAPT-P.REGION-OP !
    _RTAPT-LD-OWNER @ _RTAPT-LD-COPY @ _RTAPT-LD.OWNER !
    _RTAPT-LD-GEN @ _RTAPT-LD-COPY @ _RTAPT-LD.GENERATION !
    _RTAPT-LD-OBJECT @ _RTAPT-LD-COPY @ _RTAPT-LD.OBJECT !
    _RTAPT-LD-REGION @ _RTAPT-LD-COPY @ _RTAPT-LD.REGION !
    _RTAPT-LD-PARENT @ _RTAPT-LD-COPY @ _RTAPT-LD.PARENT !
    _RTAPT-LD-LEFT @ _RTAPT-LD-COPY @ _RTAPT-LD.LEFT !
    _RTAPT-LD-TOP @ _RTAPT-LD-COPY @ _RTAPT-LD.TOP !
    _RTAPT-LD-RIGHT @ _RTAPT-LD-COPY @ _RTAPT-LD.RIGHT !
    _RTAPT-LD-BOTTOM @ _RTAPT-LD-COPY @ _RTAPT-LD.BOTTOM !
    _RTAPT-LD-Z @ _RTAPT-LD-COPY @ _RTAPT-LD.Z !
    _RTAPT-LD-VISIBLE @ IF 1 ELSE 0 THEN
        _RTAPT-LD-COPY @ _RTAPT-LD.VISIBLE !
    _RTAPT-LD-FG-RGBA @ _RTAPT-LD-COPY @ _RTAPT-LD.FG-RGBA !
    _RTAPT-LD-BG-RGBA @ _RTAPT-LD-COPY @ _RTAPT-LD.BG-RGBA !
    _RTAPT-LD-ATTRS @ _RTAPT-LD-COPY @ _RTAPT-LD.ATTRS !
    _RTAPT-LD-TEXT-U @ _RTAPT-LD-COPY @ _RTAPT-LD.TEXT-U !
    _RTAPT-LD-TEXT-U @ IF
        _RTAPT-LD-TEXT-A @ _RTAPT-LD-COPY @ _RTAPT-LD.TEXT
        _RTAPT-LD-TEXT-U @ MOVE
    THEN
    _RTAPT-LD-NEXT-OBJECTS @ _RTAPT-LD-O @ _RTAPT-O.PENDING-OBJECTS !
    _RTAPT-LD-OBJECT @ _RTAPT-LD-O @ _RTAPT-O.PENDING-OBJECT-HIGH !
    _RTAPT-LD-TEXT-U @ _RTAPT-LD-O @ _RTAPT-O.PENDING-UTF8 +!
    _RTAPT-LD-NEXT-COPY @ _RTAPT-LD-E @ _RTAPT-E.COPY-USED !
    _RTAPT-LD-NEXT-RET @ _RTAPT-LD-E @ _RTAPT-E.RET-BYTES !
    1 _RTAPT-LD-E @ _RTAPT-E.OP-COUNT +!
    RTAPT-S-OK DUP _RTAPT-LD-E @ _RTAPT-E.LAST-STATUS ! ;

: _RTAPT-GLYPH-RUN-REPLACE-BODY  ( -- status )
    _RTAPT-LD-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    \ The borrowed record is proved before discovery/state reads may mutate
    \ engine-local snapshots.  Replacement uses the same neutral geometry,
    \ style, text, retry-copy, and exact wire-byte rules as definition.
    _RTAPT-GLYPH-RUN-FIELDS? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-GLYPH-RUN-TEXT-SPAN? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-LD-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-LD-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CAPTURING <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-LD-E @ _RTAPT-CAPTURE-READY? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-GLYPH-RUN-LIMITS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-LD-TEXT-A @ _RTAPT-LD-TEXT-U @ _RTAPT-GLYPH-RUN-UTF8? 0= IF
        RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-LD-OWNER @ _RTAPT-LD-GEN @ _RTAPT-LD-E @
        _RTAPT-OWNER-FIND DUP 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-LD-O ! _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-LD-OBJECT @ _RTAPT-LD-REGION @
    _RTAPT-LD-O @ _RTAPT-LD-E @ _RTAPT-GLYPH-RUN-TARGET? 0= IF
        RTAPT-S-INVALID EXIT
    THEN

    _RTAPT-LD-E @ _RTAPT-E.OP-COUNT @ 0xFFFFFFFF U< 0=
        IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-E @ _RTAPT-E.OP-COUNT @
        _RTAPT-LD-E @ _RTAPT-E.OP-CAP @ U< 0= IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-TEXT-U @ _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-ALIGN8? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    DUP _RTAPT-LD-COPY-U !
    _RTAPT-LD-E @ _RTAPT-E.COPY-U @
        _RTAPT-LD-E @ _RTAPT-E.COPY-USED @ - U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-LD-E @ _RTAPT-E.COPY-USED @ _RTAPT-LD-COPY-U @
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-NEXT-COPY !
    _RTAPT-LD-E @ _RTAPT-E.RET-BYTES @ _RTAPT-LD-TEXT-U @
        _RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-LD-NEXT-RET !

    _RTAPT-LD-E @ _RTAPT-E.OP-COUNT @ _RTAPT-LD-E @ _RTAPT-OP-NTH
        _RTAPT-LD-P !
    _RTAPT-LD-E @ _RTAPT-E.COPY-A @
        _RTAPT-LD-E @ _RTAPT-E.COPY-USED @ + _RTAPT-LD-COPY !
    _RTAPT-LD-P @ RTAPT-OP-SIZE 0 FILL
    _RTAPT-LD-COPY @ _RTAPT-LD-COPY-U @ 0 FILL
    _RTAPT-OP-GLYPH-RUN-REPLACE _RTAPT-LD-P @ _RTAPT-P.KIND !
    _RTAPT-LD-E @ _RTAPT-E.COPY-USED @
        _RTAPT-LD-P @ _RTAPT-P.COPY-OFF !
    _RTAPT-LD-COPY-U @ _RTAPT-LD-P @ _RTAPT-P.COPY-U !
    _RTAPT-LD-O @ _RTAPT-LD-E @ _RTAPT-OWNER-SLOT
        _RTAPT-LD-P @ _RTAPT-P.OWNER-SLOT !
    0 _RTAPT-LD-P @ _RTAPT-P.REGION-OP !
    _RTAPT-LD-OWNER @ _RTAPT-LD-COPY @ _RTAPT-LD.OWNER !
    _RTAPT-LD-GEN @ _RTAPT-LD-COPY @ _RTAPT-LD.GENERATION !
    _RTAPT-LD-OBJECT @ _RTAPT-LD-COPY @ _RTAPT-LD.OBJECT !
    _RTAPT-LD-REGION @ _RTAPT-LD-COPY @ _RTAPT-LD.REGION !
    _RTAPT-LD-PARENT @ _RTAPT-LD-COPY @ _RTAPT-LD.PARENT !
    _RTAPT-LD-LEFT @ _RTAPT-LD-COPY @ _RTAPT-LD.LEFT !
    _RTAPT-LD-TOP @ _RTAPT-LD-COPY @ _RTAPT-LD.TOP !
    _RTAPT-LD-RIGHT @ _RTAPT-LD-COPY @ _RTAPT-LD.RIGHT !
    _RTAPT-LD-BOTTOM @ _RTAPT-LD-COPY @ _RTAPT-LD.BOTTOM !
    _RTAPT-LD-Z @ _RTAPT-LD-COPY @ _RTAPT-LD.Z !
    _RTAPT-LD-VISIBLE @ IF 1 ELSE 0 THEN
        _RTAPT-LD-COPY @ _RTAPT-LD.VISIBLE !
    _RTAPT-LD-FG-RGBA @ _RTAPT-LD-COPY @ _RTAPT-LD.FG-RGBA !
    _RTAPT-LD-BG-RGBA @ _RTAPT-LD-COPY @ _RTAPT-LD.BG-RGBA !
    _RTAPT-LD-ATTRS @ _RTAPT-LD-COPY @ _RTAPT-LD.ATTRS !
    _RTAPT-LD-TEXT-U @ _RTAPT-LD-COPY @ _RTAPT-LD.TEXT-U !
    _RTAPT-LD-TEXT-U @ IF
        _RTAPT-LD-TEXT-A @ _RTAPT-LD-COPY @ _RTAPT-LD.TEXT
        _RTAPT-LD-TEXT-U @ MOVE
    THEN
    \ Replacement consumes operation/copy/wire capacity but does not add an
    \ object or UTF-8 reservation.  The physical model validates exact sparse
    \ identity and recomputes the candidate's actual UTF-8 usage atomically.
    _RTAPT-LD-NEXT-COPY @ _RTAPT-LD-E @ _RTAPT-E.COPY-USED !
    _RTAPT-LD-NEXT-RET @ _RTAPT-LD-E @ _RTAPT-E.RET-BYTES !
    1 _RTAPT-LD-E @ _RTAPT-E.OP-COUNT +!
    RTAPT-S-OK DUP _RTAPT-LD-E @ _RTAPT-E.LAST-STATUS ! ;

: _RTAPT-GLYPH-RUN-SCRUB  ( -- )
    0 _RTAPT-LD-E ! 0 _RTAPT-LD-O ! 0 _RTAPT-LD-P ! 0 _RTAPT-LD-COPY !
    0 _RTAPT-LD-OWNER ! 0 _RTAPT-LD-GEN ! 0 _RTAPT-LD-OBJECT !
    0 _RTAPT-LD-REGION ! 0 _RTAPT-LD-PARENT !
    0 _RTAPT-LD-ROW ! 0 _RTAPT-LD-COL !
    0 _RTAPT-LD-HEIGHT ! 0 _RTAPT-LD-WIDTH !
    0 _RTAPT-LD-ROOT-H ! 0 _RTAPT-LD-ROOT-W ! 0 _RTAPT-LD-Z !
    0 _RTAPT-LD-VISIBLE !
    0 _RTAPT-LD-FG-RGBA ! 0 _RTAPT-LD-BG-RGBA ! 0 _RTAPT-LD-ATTRS !
    0 _RTAPT-LD-TEXT-A ! 0 _RTAPT-LD-TEXT-U !
    0 _RTAPT-LD-LEFT ! 0 _RTAPT-LD-TOP !
    0 _RTAPT-LD-RIGHT ! 0 _RTAPT-LD-BOTTOM !
    0 _RTAPT-LD-ROW-END ! 0 _RTAPT-LD-COL-END !
    0 _RTAPT-LD-NEXT-COPY ! 0 _RTAPT-LD-NEXT-RET !
    0 _RTAPT-LD-NEXT-OBJECTS ! 0 _RTAPT-LD-NEXT-UTF8 !
    0 _RTAPT-LD-COPY-U ! 0 _RTAPT-LD-REGION-OP !
    0 _RTAPT-UN-B ! 0 _RTAPT-UN-R !
    0 _RTAPT-UN-Q ! 0 _RTAPT-UN-REM !
    0 _RTAPT-LU-I ! 0 _RTAPT-LU-B0 ! 0 _RTAPT-LU-B1 !
    0 _RTAPT-LU-A ! 0 _RTAPT-LU-U !
    0 _RTAPT-GRP-P ! 0 _RTAPT-GRP-OFF ! 0 _RTAPT-GRP-NEXT !
    0 _RTAPT-BSD-A ! 0 _RTAPT-BSD-U ! 0 _RTAPT-BSD-E ! ;

: RTAPT-GLYPH-RUN-DEFINE  ( owner generation object region parent row col height width root-height root-width z visible fg-rgba bg-rgba attrs text-a text-u engine -- status )
    _RTAPT-LD-E ! _RTAPT-LD-TEXT-U ! _RTAPT-LD-TEXT-A !
    _RTAPT-LD-ATTRS ! _RTAPT-LD-BG-RGBA ! _RTAPT-LD-FG-RGBA !
    _RTAPT-LD-VISIBLE ! _RTAPT-LD-Z !
    _RTAPT-LD-ROOT-W ! _RTAPT-LD-ROOT-H !
    _RTAPT-LD-WIDTH ! _RTAPT-LD-HEIGHT !
    _RTAPT-LD-COL ! _RTAPT-LD-ROW ! _RTAPT-LD-PARENT !
    _RTAPT-LD-REGION ! _RTAPT-LD-OBJECT ! _RTAPT-LD-GEN !
    _RTAPT-LD-OWNER !
    ['] _RTAPT-GLYPH-RUN-DEFINE-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-GLYPH-RUN-SCRUB ;

: RTAPT-GLYPH-RUN-REPLACE  ( owner generation object region parent row col height width root-height root-width z visible fg-rgba bg-rgba attrs text-a text-u engine -- status )
    _RTAPT-LD-E ! _RTAPT-LD-TEXT-U ! _RTAPT-LD-TEXT-A !
    _RTAPT-LD-ATTRS ! _RTAPT-LD-BG-RGBA ! _RTAPT-LD-FG-RGBA !
    _RTAPT-LD-VISIBLE ! _RTAPT-LD-Z !
    _RTAPT-LD-ROOT-W ! _RTAPT-LD-ROOT-H !
    _RTAPT-LD-WIDTH ! _RTAPT-LD-HEIGHT !
    _RTAPT-LD-COL ! _RTAPT-LD-ROW ! _RTAPT-LD-PARENT !
    _RTAPT-LD-REGION ! _RTAPT-LD-OBJECT ! _RTAPT-LD-GEN !
    _RTAPT-LD-OWNER !
    ['] _RTAPT-GLYPH-RUN-REPLACE-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-GLYPH-RUN-SCRUB ;

\ =====================================================================
\  Neutral semantic CONTROL capture
\ =====================================================================

VARIABLE _RTAPT-CD-E
VARIABLE _RTAPT-CD-O
VARIABLE _RTAPT-CD-P
VARIABLE _RTAPT-CD-COPY
VARIABLE _RTAPT-CD-OWNER
VARIABLE _RTAPT-CD-GEN
VARIABLE _RTAPT-CD-ID
VARIABLE _RTAPT-CD-KIND
VARIABLE _RTAPT-CD-STATE
VARIABLE _RTAPT-CD-Z
VARIABLE _RTAPT-CD-REGION
VARIABLE _RTAPT-CD-PARENT
VARIABLE _RTAPT-CD-ORDER
VARIABLE _RTAPT-CD-ROW
VARIABLE _RTAPT-CD-COL
VARIABLE _RTAPT-CD-HEIGHT
VARIABLE _RTAPT-CD-WIDTH
VARIABLE _RTAPT-CD-ROOT-H
VARIABLE _RTAPT-CD-ROOT-W
VARIABLE _RTAPT-CD-LABEL-A
VARIABLE _RTAPT-CD-LABEL-U
VARIABLE _RTAPT-CD-SHORTCUT-A
VARIABLE _RTAPT-CD-SHORTCUT-U
VARIABLE _RTAPT-CD-TEXT-U
VARIABLE _RTAPT-CD-LEFT
VARIABLE _RTAPT-CD-TOP
VARIABLE _RTAPT-CD-RIGHT
VARIABLE _RTAPT-CD-BOTTOM
VARIABLE _RTAPT-CD-ROW-END
VARIABLE _RTAPT-CD-COL-END
VARIABLE _RTAPT-CD-COPY-U
VARIABLE _RTAPT-CD-NEXT-COPY
VARIABLE _RTAPT-CD-NEXT-RET
VARIABLE _RTAPT-CD-NEXT-CONTROLS
VARIABLE _RTAPT-CD-NEXT-UTF8
VARIABLE _RTAPT-CD-DIRTY-P
VARIABLE _RTAPT-CD-DIRTY-COPY
VARIABLE _RTAPT-CD-DIRTY-COPY-U

: _RTAPT-CONTROL-TEXT?  ( a u -- flag )
    2DUP _RTAPT-GLYPH-RUN-UTF8? 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ DUP 32 U< SWAP 127 = OR IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _RTAPT-CONTROL-ONE-TEXT-SPAN?  ( a u -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    _RTAPT-CD-E @ _RTAPT-BYTE-SPAN-DISJOINT? ;

: _RTAPT-CONTROL-TEXT-SPANS?  ( -- flag )
    _RTAPT-CD-LABEL-A @ _RTAPT-CD-LABEL-U @
        _RTAPT-CONTROL-ONE-TEXT-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-CD-SHORTCUT-A @ _RTAPT-CD-SHORTCUT-U @
        _RTAPT-CONTROL-ONE-TEXT-SPAN? ;

: _RTAPT-CONTROL-KIND?  ( kind -- flag )
    DUP RTAPT-CONTROL-MENUBAR = IF DROP -1 EXIT THEN
    DUP RTAPT-CONTROL-MENU = IF DROP -1 EXIT THEN
    DUP RTAPT-CONTROL-ITEM = IF DROP -1 EXIT THEN
    RTAPT-CONTROL-SEPARATOR = ;

: _RTAPT-CONTROL-ROOT-GEOMETRY?  ( -- flag )
    _RTAPT-CD-ROW @ _RTAPT-U32? 0=
    _RTAPT-CD-COL @ _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-CD-HEIGHT @ DUP 0= SWAP _RTAPT-U32? 0= OR
    _RTAPT-CD-WIDTH @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF 0 EXIT THEN
    _RTAPT-CD-ROOT-H @ DUP 0= SWAP _RTAPT-U32? 0= OR
    _RTAPT-CD-ROOT-W @ DUP 0= SWAP _RTAPT-U32? 0= OR OR IF 0 EXIT THEN
    _RTAPT-CD-ROW @ _RTAPT-CD-HEIGHT @ _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-CD-ROW-END !
    _RTAPT-CD-COL @ _RTAPT-CD-WIDTH @ _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-CD-COL-END !
    _RTAPT-CD-ROW-END @ _RTAPT-CD-ROOT-H @ U> IF 0 EXIT THEN
    _RTAPT-CD-COL-END @ _RTAPT-CD-ROOT-W @ U> IF 0 EXIT THEN
    _RTAPT-CD-COL @ _RTAPT-CD-ROOT-W @ _RTAPT-UNORM32-LOW
        _RTAPT-CD-LEFT !
    _RTAPT-CD-ROW @ _RTAPT-CD-ROOT-H @ _RTAPT-UNORM32-LOW
        _RTAPT-CD-TOP !
    _RTAPT-CD-COL-END @ _RTAPT-CD-ROOT-W @ _RTAPT-UNORM32-HIGH
        _RTAPT-CD-RIGHT !
    _RTAPT-CD-ROW-END @ _RTAPT-CD-ROOT-H @ _RTAPT-UNORM32-HIGH
        _RTAPT-CD-BOTTOM !
    _RTAPT-CD-LEFT @ _RTAPT-CD-RIGHT @ U<
    _RTAPT-CD-TOP @ _RTAPT-CD-BOTTOM @ U< AND ;

: _RTAPT-CONTROL-DESCENDANT-GEOMETRY?  ( -- flag )
    _RTAPT-CD-ROW @ _RTAPT-CD-COL @ OR
    _RTAPT-CD-HEIGHT @ OR _RTAPT-CD-WIDTH @ OR
    _RTAPT-CD-Z @ OR IF 0 EXIT THEN
    _RTAPT-CD-ROOT-H @ DUP 0= SWAP _RTAPT-U32? 0= OR
    _RTAPT-CD-ROOT-W @ DUP 0= SWAP _RTAPT-U32? 0= OR OR 0= ;

: _RTAPT-CONTROL-STATE-DEPENDENCIES?  ( -- flag )
    _RTAPT-CD-STATE @
        RTAPT-CONTROL-F-OPEN RTAPT-CONTROL-F-SELECTED OR AND IF
        _RTAPT-CD-STATE @
            RTAPT-CONTROL-F-VISIBLE RTAPT-CONTROL-F-ENABLED OR AND
        RTAPT-CONTROL-F-VISIBLE RTAPT-CONTROL-F-ENABLED OR = EXIT
    THEN
    -1 ;

: _RTAPT-CONTROL-SHAPE?  ( -- flag )
    _RTAPT-CD-OWNER @ 0= _RTAPT-CD-GEN @ 0= OR
    _RTAPT-CD-ID @ 0= OR _RTAPT-CD-REGION @ 0= OR IF 0 EXIT THEN
    _RTAPT-CD-KIND @ _RTAPT-CONTROL-KIND? 0= IF 0 EXIT THEN
    _RTAPT-CD-STATE @ _RTAPT-U16? 0=
    _RTAPT-CD-STATE @ _RTAPT-CONTROL-F-MASK INVERT AND 0<> OR IF
        0 EXIT
    THEN
    _RTAPT-CD-Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-CD-ORDER @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-CD-LABEL-U @ _RTAPT-U32? 0=
    _RTAPT-CD-SHORTCUT-U @ _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-CONTROL-STATE-DEPENDENCIES? 0= IF 0 EXIT THEN
    _RTAPT-CD-KIND @ RTAPT-CONTROL-MENUBAR = IF
        _RTAPT-CD-PARENT @ _RTAPT-CD-ORDER @ OR
        _RTAPT-CD-LABEL-U @ OR _RTAPT-CD-SHORTCUT-U @ OR IF 0 EXIT THEN
        _RTAPT-CD-STATE @
            RTAPT-CONTROL-F-VISIBLE RTAPT-CONTROL-F-ENABLED OR
            INVERT AND IF 0 EXIT THEN
        _RTAPT-CONTROL-ROOT-GEOMETRY? EXIT
    THEN
    _RTAPT-CD-PARENT @ 0= IF 0 EXIT THEN
    _RTAPT-CONTROL-DESCENDANT-GEOMETRY? 0= IF 0 EXIT THEN
    _RTAPT-CD-KIND @ RTAPT-CONTROL-MENU = IF
        _RTAPT-CD-LABEL-U @ 0= _RTAPT-CD-SHORTCUT-U @ 0<> OR IF
            0 EXIT
        THEN
        _RTAPT-CD-STATE @ 0x0F INVERT AND 0= EXIT
    THEN
    _RTAPT-CD-KIND @ RTAPT-CONTROL-ITEM = IF
        _RTAPT-CD-LABEL-U @ 0= IF 0 EXIT THEN
        _RTAPT-CD-STATE @ 0x1B INVERT AND 0= EXIT
    THEN
    _RTAPT-CD-LABEL-U @ _RTAPT-CD-SHORTCUT-U @ OR IF 0 EXIT THEN
    _RTAPT-CD-STATE @ RTAPT-CONTROL-F-VISIBLE INVERT AND 0= ;

: _RTAPT-CONTROL-LIMITS  ( -- status )
    _RTAPT-CD-E @ _RTAPT-E.LIMITS DUP
        RTAPT-LIMITS-VALID? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-L.FEATURES @ RTAPT-F-CONTROLS AND 0= IF
        DROP RTAPT-S-UNSUPPORTED EXIT
    THEN
    _RTAPT-CD-E @ _RTAPT-E.OP-COUNT @ 1+
        OVER _RTAPT-L.OPS @ U> IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-CD-TEXT-U @ 80 _RTAPT-UADD? 0= IF
        DROP DROP RTAPT-S-CAPACITY EXIT
    THEN OVER _RTAPT-L.OUTBOUND-PAYLOAD @ U> IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CD-NEXT-RET @ _RTAPT-UPDATE-ENVELOPE-FRAME-BYTES
        _RTAPT-UADD? 0= IF DROP DROP RTAPT-S-CAPACITY EXIT THEN
    SWAP _RTAPT-L.UPDATE-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    RTAPT-S-OK ;

: _RTAPT-CONTROL-PARENT-PRIOR?  ( -- flag )
    _RTAPT-CD-PARENT @ 0= IF
        _RTAPT-CD-KIND @ RTAPT-CONTROL-MENUBAR = EXIT
    THEN
    _RTAPT-CD-KIND @ RTAPT-CONTROL-MENUBAR = IF 0 EXIT THEN
    _RTAPT-CD-PARENT @ _RTAPT-CD-ID @ U< 0= IF 0 EXIT THEN
    _RTAPT-CD-PARENT @ _RTAPT-CD-O @ _RTAPT-O.CONTROL-HIGH @ U> IF
        _RTAPT-CD-PARENT @
        _RTAPT-CD-O @ _RTAPT-O.PENDING-CONTROL-HIGH @ U> 0= EXIT
    THEN
    -1 ;

: _RTAPT-CONTROL-REGION?  ( definition? -- flag )
    IF
        _RTAPT-CD-O @ _RTAPT-O.PENDING-REGIONS @ 0= IF 0 EXIT THEN
        _RTAPT-CD-REGION @
            _RTAPT-CD-O @ _RTAPT-O.PENDING-REGION-HIGH @ U> 0= EXIT
    THEN
    _RTAPT-CD-O @ _RTAPT-O.ACTIVE-REGIONS @ 0= IF 0 EXIT THEN
    _RTAPT-CD-REGION @ _RTAPT-CD-O @ _RTAPT-O.REGION-HIGH @ U> 0= ;

: _RTAPT-CONTROL-SHARED-QUOTA?  ( addition -- flag )
    >R
    _RTAPT-CD-O @ _RTAPT-O.ACTIVE-OBJECTS @
    _RTAPT-CD-O @ _RTAPT-O.ACTIVE-CONTROLS @ _RTAPT-UADD? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    _RTAPT-CD-O @ _RTAPT-O.HIDDEN-OBJECTS @
    _RTAPT-CD-O @ _RTAPT-O.HIDDEN-CONTROLS @ _RTAPT-UADD? 0= IF
        DROP DROP R> DROP 0 EXIT
    THEN
    _RTAPT-CD-E @ _RTAPT-TARGET-BASE
    _RTAPT-CD-O @ _RTAPT-O.PENDING-OBJECTS @ _RTAPT-UADD? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    _RTAPT-CD-O @ _RTAPT-O.PENDING-CONTROLS @ _RTAPT-UADD? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    R> _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-CD-O @ _RTAPT-O.OBJECTS @ U> 0= ;

: _RTAPT-CONTROL-UTF8-QUOTA?  ( include-new-text? -- flag )
    >R
    _RTAPT-CD-O @ _RTAPT-O.ACTIVE-UTF8 @
    _RTAPT-CD-O @ _RTAPT-O.HIDDEN-UTF8 @
    _RTAPT-CD-E @ _RTAPT-TARGET-BASE
    _RTAPT-CD-O @ _RTAPT-O.PENDING-UTF8 @ _RTAPT-UADD? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    R> IF _RTAPT-CD-TEXT-U @ _RTAPT-UADD? 0= IF DROP 0 EXIT THEN THEN
    _RTAPT-CD-O @ _RTAPT-O.UTF8-BYTES @ U> 0= ;

: _RTAPT-CONTROL-CAPACITY?  ( -- flag )
    _RTAPT-CD-E @ _RTAPT-E.OP-COUNT @ 0xFFFFFFFF U< 0= IF 0 EXIT THEN
    _RTAPT-CD-E @ _RTAPT-E.OP-COUNT @
        _RTAPT-CD-E @ _RTAPT-E.OP-CAP @ U< 0= IF 0 EXIT THEN
    _RTAPT-CD-E @ _RTAPT-E.COPY-U @
        _RTAPT-CD-E @ _RTAPT-E.COPY-USED @ -
        _RTAPT-CD-COPY-U @ U< IF 0 EXIT THEN
    _RTAPT-CD-E @ _RTAPT-E.COPY-USED @ _RTAPT-CD-COPY-U @
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-CD-NEXT-COPY !
    _RTAPT-CD-E @ _RTAPT-E.RET-BYTES @ _RTAPT-CD-TEXT-U @
        _RTAPT-CONTROL-FRAME-FIXED _RTAPT-UADD? 0= IF 2DROP 0 EXIT THEN
        _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-CD-NEXT-RET !
    -1 ;

: _RTAPT-CONTROL-COPY-TEXT?  ( -- flag )
    _RTAPT-CD-COPY @ _RTAPT-CD.TEXT
    _RTAPT-CD-LABEL-U @ _RTAPT-CONTROL-TEXT? 0= IF 0 EXIT THEN
    _RTAPT-CD-COPY @ _RTAPT-CD.TEXT _RTAPT-CD-LABEL-U @ +
    _RTAPT-CD-SHORTCUT-U @ _RTAPT-CONTROL-TEXT? ;

: _RTAPT-CONTROL-CAPTURE  ( op-kind -- status )
    _RTAPT-CD-E @ _RTAPT-E.OP-COUNT @ _RTAPT-CD-E @ _RTAPT-OP-NTH
        DUP _RTAPT-CD-P ! _RTAPT-CD-DIRTY-P !
    _RTAPT-CD-E @ _RTAPT-E.COPY-A @
        _RTAPT-CD-E @ _RTAPT-E.COPY-USED @ +
        DUP _RTAPT-CD-COPY ! _RTAPT-CD-DIRTY-COPY !
    _RTAPT-CD-COPY-U @ _RTAPT-CD-DIRTY-COPY-U !
    _RTAPT-CD-P @ RTAPT-OP-SIZE 0 FILL
    _RTAPT-CD-COPY @ _RTAPT-CD-COPY-U @ 0 FILL
    DUP _RTAPT-CD-P @ _RTAPT-P.KIND !
    _RTAPT-CD-E @ _RTAPT-E.COPY-USED @
        _RTAPT-CD-P @ _RTAPT-P.COPY-OFF !
    _RTAPT-CD-COPY-U @ _RTAPT-CD-P @ _RTAPT-P.COPY-U !
    _RTAPT-CD-O @ _RTAPT-CD-E @ _RTAPT-OWNER-SLOT
        _RTAPT-CD-P @ _RTAPT-P.OWNER-SLOT !
    _RTAPT-CD-OWNER @ _RTAPT-CD-COPY @ _RTAPT-CD.OWNER !
    _RTAPT-CD-GEN @ _RTAPT-CD-COPY @ _RTAPT-CD.GENERATION !
    _RTAPT-CD-ID @ _RTAPT-CD-COPY @ _RTAPT-CD.CONTROL !
    _RTAPT-CD-KIND @ _RTAPT-CD-COPY @ _RTAPT-CD.KIND !
    _RTAPT-CD-STATE @ _RTAPT-CD-COPY @ _RTAPT-CD.STATE !
    _RTAPT-CD-Z @ _RTAPT-CD-COPY @ _RTAPT-CD.Z !
    _RTAPT-CD-REGION @ _RTAPT-CD-COPY @ _RTAPT-CD.REGION !
    _RTAPT-CD-PARENT @ _RTAPT-CD-COPY @ _RTAPT-CD.PARENT !
    _RTAPT-CD-ORDER @ _RTAPT-CD-COPY @ _RTAPT-CD.ORDER !
    _RTAPT-CD-LEFT @ _RTAPT-CD-COPY @ _RTAPT-CD.LEFT !
    _RTAPT-CD-TOP @ _RTAPT-CD-COPY @ _RTAPT-CD.TOP !
    _RTAPT-CD-RIGHT @ _RTAPT-CD-COPY @ _RTAPT-CD.RIGHT !
    _RTAPT-CD-BOTTOM @ _RTAPT-CD-COPY @ _RTAPT-CD.BOTTOM !
    _RTAPT-CD-LABEL-U @ _RTAPT-CD-COPY @ _RTAPT-CD.LABEL-U !
    _RTAPT-CD-SHORTCUT-U @ _RTAPT-CD-COPY @ _RTAPT-CD.SHORTCUT-U !
    _RTAPT-CD-LABEL-U @ IF
        _RTAPT-CD-LABEL-A @ _RTAPT-CD-COPY @ _RTAPT-CD.TEXT
        _RTAPT-CD-LABEL-U @ MOVE
    THEN
    _RTAPT-CD-SHORTCUT-U @ IF
        _RTAPT-CD-SHORTCUT-A @
        _RTAPT-CD-COPY @ _RTAPT-CD.TEXT _RTAPT-CD-LABEL-U @ +
        _RTAPT-CD-SHORTCUT-U @ MOVE
    THEN
    _RTAPT-CONTROL-COPY-TEXT? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DROP
    _RTAPT-CD-NEXT-COPY @ _RTAPT-CD-E @ _RTAPT-E.COPY-USED !
    _RTAPT-CD-NEXT-RET @ _RTAPT-CD-E @ _RTAPT-E.RET-BYTES !
    1 _RTAPT-CD-E @ _RTAPT-E.OP-COUNT +!
    0 _RTAPT-CD-DIRTY-P ! 0 _RTAPT-CD-DIRTY-COPY !
    0 _RTAPT-CD-DIRTY-COPY-U !
    RTAPT-S-OK DUP _RTAPT-CD-E @ _RTAPT-E.LAST-STATUS ! ;

: _RTAPT-CONTROL-COMMON?  ( -- status|0 )
    _RTAPT-CD-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CONTROL-SHAPE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CONTROL-TEXT-SPANS? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CD-LABEL-A @ _RTAPT-CD-LABEL-U @
        _RTAPT-CONTROL-TEXT? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CD-SHORTCUT-A @ _RTAPT-CD-SHORTCUT-U @
        _RTAPT-CONTROL-TEXT? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CD-LABEL-U @ _RTAPT-CD-SHORTCUT-U @
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
        _RTAPT-CD-TEXT-U !
    _RTAPT-CD-TEXT-U @ _RTAPT-CONTROL-COPY-FIXED _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-ALIGN8? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
        _RTAPT-CD-COPY-U !
    _RTAPT-CD-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-CD-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CAPTURING <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CD-E @ _RTAPT-CAPTURE-READY? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CONTROL-CAPACITY? 0= IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-CONTROL-LIMITS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-CD-OWNER @ _RTAPT-CD-GEN @ _RTAPT-CD-E @
        _RTAPT-OWNER-FIND DUP 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-CD-O ! _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CONTROL-PARENT-PRIOR? 0= IF RTAPT-S-INVALID EXIT THEN
    0 ;

: _RTAPT-CONTROL-DEFINE-BODY  ( -- status )
    _RTAPT-CONTROL-COMMON? ?DUP IF EXIT THEN
    -1 _RTAPT-CONTROL-REGION? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CD-ID @ _RTAPT-CD-O @ _RTAPT-O.CONTROL-HIGH @ U> 0=
        IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CD-ID @ _RTAPT-CD-O @ _RTAPT-O.PENDING-CONTROL-HIGH @ U> 0=
        IF RTAPT-S-INVALID EXIT THEN
    1 _RTAPT-CONTROL-SHARED-QUOTA? 0= IF RTAPT-S-CAPACITY EXIT THEN
    -1 _RTAPT-CONTROL-UTF8-QUOTA? 0= IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-CD-O @ _RTAPT-O.PENDING-CONTROLS @ 1 _RTAPT-UADD? 0= IF
        DROP RTAPT-S-CAPACITY EXIT
    THEN _RTAPT-CD-NEXT-CONTROLS !
    _RTAPT-CD-O @ _RTAPT-O.PENDING-UTF8 @ _RTAPT-CD-TEXT-U @
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
        _RTAPT-CD-NEXT-UTF8 !
    _RTAPT-OP-CONTROL-DEFINE _RTAPT-CONTROL-CAPTURE
    DUP RTAPT-S-OK = IF
        _RTAPT-CD-NEXT-CONTROLS @
            _RTAPT-CD-O @ _RTAPT-O.PENDING-CONTROLS !
        _RTAPT-CD-ID @ _RTAPT-CD-O @ _RTAPT-O.PENDING-CONTROL-HIGH !
        _RTAPT-CD-NEXT-UTF8 @ _RTAPT-CD-O @ _RTAPT-O.PENDING-UTF8 !
    THEN ;

: _RTAPT-CONTROL-REPLACE-BODY  ( -- status )
    _RTAPT-CONTROL-COMMON? ?DUP IF EXIT THEN
    _RTAPT-CD-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA <> IF
        RTAPT-S-UNSUPPORTED EXIT
    THEN
    0 _RTAPT-CONTROL-REGION? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CD-O @ _RTAPT-O.ACTIVE-CONTROLS @ 0= IF
        RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-CD-ID @ _RTAPT-CD-O @ _RTAPT-O.CONTROL-HIGH @ U> IF
        RTAPT-S-INVALID EXIT
    THEN
    0 _RTAPT-CONTROL-SHARED-QUOTA? 0= IF RTAPT-S-CAPACITY EXIT THEN
    0 _RTAPT-CONTROL-UTF8-QUOTA? 0= IF RTAPT-S-CAPACITY EXIT THEN
    \ This first DELTA replacement contract is state-only: the planner resends
    \ the exact current non-state tuple, including label and shortcut.  The
    \ aggregate-only engine cannot compare retained text, so its zero UTF-8
    \ delta depends on the terminal accepting only a matching state change;
    \ RET_OK is that certification.  Complete replacement definitions remain
    \ the path that recovers exact ledgers.
    _RTAPT-OP-CONTROL-REPLACE _RTAPT-CONTROL-CAPTURE ;

: _RTAPT-CONTROL-SCRUB  ( -- )
    _RTAPT-CD-DIRTY-P @ ?DUP IF RTAPT-OP-SIZE 0 FILL THEN
    _RTAPT-CD-DIRTY-COPY @ ?DUP IF
        _RTAPT-CD-DIRTY-COPY-U @ 0 FILL
    THEN
    0 _RTAPT-CD-E ! 0 _RTAPT-CD-O ! 0 _RTAPT-CD-P !
    0 _RTAPT-CD-COPY ! 0 _RTAPT-CD-OWNER ! 0 _RTAPT-CD-GEN !
    0 _RTAPT-CD-ID ! 0 _RTAPT-CD-KIND ! 0 _RTAPT-CD-STATE !
    0 _RTAPT-CD-Z ! 0 _RTAPT-CD-REGION ! 0 _RTAPT-CD-PARENT !
    0 _RTAPT-CD-ORDER ! 0 _RTAPT-CD-ROW ! 0 _RTAPT-CD-COL !
    0 _RTAPT-CD-HEIGHT ! 0 _RTAPT-CD-WIDTH !
    0 _RTAPT-CD-ROOT-H ! 0 _RTAPT-CD-ROOT-W !
    0 _RTAPT-CD-LABEL-A ! 0 _RTAPT-CD-LABEL-U !
    0 _RTAPT-CD-SHORTCUT-A ! 0 _RTAPT-CD-SHORTCUT-U !
    0 _RTAPT-CD-TEXT-U ! 0 _RTAPT-CD-LEFT ! 0 _RTAPT-CD-TOP !
    0 _RTAPT-CD-RIGHT ! 0 _RTAPT-CD-BOTTOM !
    0 _RTAPT-CD-ROW-END ! 0 _RTAPT-CD-COL-END !
    0 _RTAPT-CD-COPY-U ! 0 _RTAPT-CD-NEXT-COPY !
    0 _RTAPT-CD-NEXT-RET ! 0 _RTAPT-CD-NEXT-CONTROLS !
    0 _RTAPT-CD-NEXT-UTF8 ! 0 _RTAPT-CD-DIRTY-P !
    0 _RTAPT-CD-DIRTY-COPY ! 0 _RTAPT-CD-DIRTY-COPY-U !
    0 _RTAPT-LPF-SA ! 0 _RTAPT-LPF-SB ! 0 _RTAPT-LPF-SS !
    0 _RTAPT-BSD-A ! 0 _RTAPT-BSD-U ! 0 _RTAPT-BSD-E ! ;

: _RTAPT-CONTROL-ARGS!  ( owner generation control kind state z region parent order row col height width root-height root-width label-a label-u shortcut-a shortcut-u engine -- )
    _RTAPT-CD-E ! _RTAPT-CD-SHORTCUT-U ! _RTAPT-CD-SHORTCUT-A !
    _RTAPT-CD-LABEL-U ! _RTAPT-CD-LABEL-A !
    _RTAPT-CD-ROOT-W ! _RTAPT-CD-ROOT-H !
    _RTAPT-CD-WIDTH ! _RTAPT-CD-HEIGHT !
    _RTAPT-CD-COL ! _RTAPT-CD-ROW ! _RTAPT-CD-ORDER !
    _RTAPT-CD-PARENT ! _RTAPT-CD-REGION ! _RTAPT-CD-Z !
    _RTAPT-CD-STATE ! _RTAPT-CD-KIND ! _RTAPT-CD-ID !
    _RTAPT-CD-GEN ! _RTAPT-CD-OWNER ! ;

\ Stack: owner generation control kind state z region parent order row col
\        height width root-height root-width label-a label-u shortcut-a
\        shortcut-u engine -- status
: RTAPT-CONTROL-DEFINE  ( control scalars engine -- status )
    _RTAPT-CONTROL-ARGS!
    ['] _RTAPT-CONTROL-DEFINE-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-CONTROL-SCRUB ;

\ Stack: owner generation control kind state z region parent order row col
\        height width root-height root-width label-a label-u shortcut-a
\        shortcut-u engine -- status
: RTAPT-CONTROL-REPLACE  ( control scalars engine -- status )
    _RTAPT-CONTROL-ARGS!
    ['] _RTAPT-CONTROL-REPLACE-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-CONTROL-SCRUB ;

\ CONTROL_REPLACE and CONTROL_DROP are deliberately DELTA-only in this rung;
\ replacement/layout construction accepts CONTROL_DEFINE records only.  DROP
\ never releases the conservative local control/text ledgers, and the first
\ visual planner does not use it.  A later complete replacement re-establishes
\ exact target aggregates.

VARIABLE _RTAPT-CX-E
VARIABLE _RTAPT-CX-O
VARIABLE _RTAPT-CX-P
VARIABLE _RTAPT-CX-COPY
VARIABLE _RTAPT-CX-OWNER
VARIABLE _RTAPT-CX-GEN
VARIABLE _RTAPT-CX-ID
VARIABLE _RTAPT-CX-NEXT-COPY
VARIABLE _RTAPT-CX-NEXT-RET
VARIABLE _RTAPT-CX-DIRTY-P
VARIABLE _RTAPT-CX-DIRTY-COPY

: _RTAPT-CONTROL-DROP-BODY  ( -- status )
    _RTAPT-CX-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CX-OWNER @ 0= _RTAPT-CX-GEN @ 0= OR
    _RTAPT-CX-ID @ 0= OR IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CX-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-CX-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CAPTURING <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CX-E @ _RTAPT-CAPTURE-READY? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CX-E @ _RTAPT-E.LIMITS DUP
        RTAPT-LIMITS-VALID? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-L.FEATURES @ RTAPT-F-CONTROLS AND 0= IF
        DROP RTAPT-S-UNSUPPORTED EXIT
    THEN
    _RTAPT-CX-E @ _RTAPT-E.OP-COUNT @ 1+
        OVER _RTAPT-L.OPS @ U> IF DROP RTAPT-S-CAPACITY EXIT THEN
    DROP
    _RTAPT-CX-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA <> IF
        RTAPT-S-UNSUPPORTED EXIT
    THEN
    _RTAPT-CX-OWNER @ _RTAPT-CX-GEN @ _RTAPT-CX-E @
        _RTAPT-OWNER-FIND DUP 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-CX-O ! _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CX-O @ _RTAPT-O.ACTIVE-CONTROLS @ 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CX-ID @ _RTAPT-CX-O @ _RTAPT-O.CONTROL-HIGH @ U> IF
        RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-CX-E @ _RTAPT-E.OP-COUNT @ 0xFFFFFFFF U< 0= IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CX-E @ _RTAPT-E.OP-COUNT @
        _RTAPT-CX-E @ _RTAPT-E.OP-CAP @ U< 0= IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-CX-E @ _RTAPT-E.COPY-U @ _RTAPT-CX-E @ _RTAPT-E.COPY-USED @ -
        _RTAPT-CONTROL-DROP-COPY-SIZE U< IF RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-CX-E @ _RTAPT-E.COPY-USED @ _RTAPT-CONTROL-DROP-COPY-SIZE
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
        _RTAPT-CX-NEXT-COPY !
    _RTAPT-CX-E @ _RTAPT-E.RET-BYTES @ _RTAPT-CONTROL-DROP-FRAME-BYTES
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
        _RTAPT-CX-NEXT-RET !
    _RTAPT-CX-NEXT-RET @ _RTAPT-UPDATE-ENVELOPE-FRAME-BYTES
        _RTAPT-UADD? 0= IF DROP RTAPT-S-CAPACITY EXIT THEN
    _RTAPT-CX-E @ _RTAPT-E.LIMITS _RTAPT-L.UPDATE-BYTES @ U> IF
        RTAPT-S-CAPACITY EXIT
    THEN
    _RTAPT-CX-E @ _RTAPT-E.OP-COUNT @ _RTAPT-CX-E @ _RTAPT-OP-NTH
        DUP _RTAPT-CX-P ! _RTAPT-CX-DIRTY-P !
    _RTAPT-CX-E @ _RTAPT-E.COPY-A @ _RTAPT-CX-E @ _RTAPT-E.COPY-USED @ +
        DUP _RTAPT-CX-COPY ! _RTAPT-CX-DIRTY-COPY !
    _RTAPT-CX-P @ RTAPT-OP-SIZE 0 FILL
    _RTAPT-CX-COPY @ _RTAPT-CONTROL-DROP-COPY-SIZE 0 FILL
    _RTAPT-OP-CONTROL-DROP _RTAPT-CX-P @ _RTAPT-P.KIND !
    _RTAPT-CX-E @ _RTAPT-E.COPY-USED @ _RTAPT-CX-P @ _RTAPT-P.COPY-OFF !
    _RTAPT-CONTROL-DROP-COPY-SIZE _RTAPT-CX-P @ _RTAPT-P.COPY-U !
    _RTAPT-CX-O @ _RTAPT-CX-E @ _RTAPT-OWNER-SLOT
        _RTAPT-CX-P @ _RTAPT-P.OWNER-SLOT !
    _RTAPT-CX-OWNER @ _RTAPT-CX-COPY @ _RTAPT-CX.OWNER !
    _RTAPT-CX-GEN @ _RTAPT-CX-COPY @ _RTAPT-CX.GENERATION !
    _RTAPT-CX-ID @ _RTAPT-CX-COPY @ _RTAPT-CX.CONTROL !
    _RTAPT-CX-NEXT-COPY @ _RTAPT-CX-E @ _RTAPT-E.COPY-USED !
    _RTAPT-CX-NEXT-RET @ _RTAPT-CX-E @ _RTAPT-E.RET-BYTES !
    1 _RTAPT-CX-E @ _RTAPT-E.OP-COUNT +!
    0 _RTAPT-CX-DIRTY-P ! 0 _RTAPT-CX-DIRTY-COPY !
    RTAPT-S-OK DUP _RTAPT-CX-E @ _RTAPT-E.LAST-STATUS ! ;

: _RTAPT-CONTROL-DROP-SCRUB  ( -- )
    _RTAPT-CX-DIRTY-P @ ?DUP IF RTAPT-OP-SIZE 0 FILL THEN
    _RTAPT-CX-DIRTY-COPY @ ?DUP IF
        _RTAPT-CONTROL-DROP-COPY-SIZE 0 FILL
    THEN
    0 _RTAPT-CX-E ! 0 _RTAPT-CX-O ! 0 _RTAPT-CX-P !
    0 _RTAPT-CX-COPY ! 0 _RTAPT-CX-OWNER ! 0 _RTAPT-CX-GEN !
    0 _RTAPT-CX-ID ! 0 _RTAPT-CX-NEXT-COPY ! 0 _RTAPT-CX-NEXT-RET !
    0 _RTAPT-CX-DIRTY-P ! 0 _RTAPT-CX-DIRTY-COPY ! ;

: RTAPT-CONTROL-DROP  ( owner generation control engine -- status )
    _RTAPT-CX-E ! _RTAPT-CX-ID ! _RTAPT-CX-GEN ! _RTAPT-CX-OWNER !
    ['] _RTAPT-CONTROL-DROP-BODY CATCH ?DUP IF
        DROP RTAPT-S-INVALID
    THEN
    _RTAPT-CONTROL-DROP-SCRUB ;

VARIABLE _RTAPT-RS-E
VARIABLE _RTAPT-RS-DISPOSITION

: RTAPT-RICH-SEAL  ( disposition engine -- status )
    _RTAPT-RS-E ! _RTAPT-RS-DISPOSITION !
    \ SEAL freezes only the loop-free descriptor.  Appenders validated every
    \ admitted operation; the sole exhaustive caller-mutation audit runs in
    \ CELL-COMMIT immediately before serialization.
    _RTAPT-RS-E @ _RTAPT-CAPTURE-READY? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RS-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-RS-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CAPTURING <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-RS-E @ _RTAPT-E.RET-MODE @ _RTAPT-RS-DISPOSITION @
        _RTAPT-MODE-DISPOSITION? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RS-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA =
    _RTAPT-RS-E @ _RTAPT-E.OP-COUNT @ 0= AND IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-RS-DISPOSITION @ _RTAPT-RS-E @ _RTAPT-E.DISPOSITION !
    RTAPT-UPDATE-SEALED _RTAPT-RS-E @ _RTAPT-E.UPDATE-STATE !
    RTAPT-S-OK DUP _RTAPT-RS-E @ _RTAPT-E.LAST-STATUS ! ;

: RTAPT-RICH-CANCEL  ( engine -- status )
    DUP _RTAPT-ENGINE-VALID? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    DUP _RTAPT-E.UPDATE-STATE @ DUP RTAPT-UPDATE-IDLE = IF
        DROP RTAPT-S-OK DUP ROT _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    DUP RTAPT-UPDATE-CAPTURING = SWAP RTAPT-UPDATE-SEALED = OR 0= IF
        DROP RTAPT-S-BUSY EXIT
    THEN
    DUP _RTAPT-CANDIDATE-DISCARD
    RTAPT-S-OK DUP ROT _RTAPT-E.LAST-STATUS ! ;

VARIABLE _RTAPT-PF-E
VARIABLE _RTAPT-PF-COLS
VARIABLE _RTAPT-PF-ROWS
VARIABLE _RTAPT-PF-O
VARIABLE _RTAPT-PF-P
VARIABLE _RTAPT-PF-COPY
VARIABLE _RTAPT-PF-COPY-U
VARIABLE _RTAPT-PF-RCOUNT
VARIABLE _RTAPT-PF-OCOUNT
VARIABLE _RTAPT-PF-UTF8
VARIABLE _RTAPT-PF-TOTAL
VARIABLE _RTAPT-PF-RHIGH
VARIABLE _RTAPT-PF-OHIGH
VARIABLE _RTAPT-PF-CCOUNT
VARIABLE _RTAPT-PF-CHIGH
VARIABLE _RTAPT-PF-CPHASE
VARIABLE _RTAPT-PF-CBAR-COUNT
VARIABLE _RTAPT-PF-CBAR-ID
VARIABLE _RTAPT-PF-CMENU-FIRST
VARIABLE _RTAPT-PF-CMENU-LAST
VARIABLE _RTAPT-PF-CPARENT
VARIABLE _RTAPT-PF-CORDER
VARIABLE _RTAPT-PF-COPEN-MENU
VARIABLE _RTAPT-PF-CSELECTED-MENU
VARIABLE _RTAPT-PF-CSELECTED-ITEM-PARENT

VARIABLE _RTAPT-PRR-I
VARIABLE _RTAPT-PRR-E
VARIABLE _RTAPT-PRR-GLYPH-RUN
VARIABLE _RTAPT-PRR-P
VARIABLE _RTAPT-PRR-REGION

: _RTAPT-REGION-BACKLINK-FINISH  ( flag -- flag )
    0 _RTAPT-PRR-I ! 0 _RTAPT-PRR-E ! 0 _RTAPT-PRR-GLYPH-RUN !
    0 _RTAPT-PRR-P ! 0 _RTAPT-PRR-REGION ! ;

\ Prove an exact sparse REGION_DEFINE dependency through the captured
\ index-plus-one backlink.  No prefix search is needed, and arbitrary owner
\ interleaving remains legal.
: _RTAPT-REGION-BACKLINK?  ( index glyph-copy op-record engine -- flag )
    _RTAPT-PRR-E ! _RTAPT-PRR-P !
    _RTAPT-PRR-GLYPH-RUN ! _RTAPT-PRR-I !
    _RTAPT-PRR-P @ _RTAPT-P.REGION-OP @ DUP 0= IF
        DROP 0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    1- DUP _RTAPT-PRR-I @ U< 0= IF
        DROP 0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    _RTAPT-PRR-E @ _RTAPT-OP-NTH DUP _RTAPT-PRR-REGION !
    DUP _RTAPT-P.KIND @ _RTAPT-OP-REGION-DEFINE <> IF
        DROP 0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    DUP _RTAPT-P.OWNER-SLOT @
        _RTAPT-PRR-P @ _RTAPT-P.OWNER-SLOT @ <> IF
        DROP 0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    DUP _RTAPT-P.COPY-U @ _RTAPT-REGION-DEFINE-COPY-SIZE <> IF
        DROP 0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    _RTAPT-P.COPY-OFF @ DUP 7 AND IF
        DROP 0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    _RTAPT-REGION-DEFINE-COPY-SIZE _RTAPT-UADD? 0= IF
        DROP 0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    _RTAPT-PRR-E @ _RTAPT-E.COPY-USED @ U> IF
        0 _RTAPT-REGION-BACKLINK-FINISH EXIT
    THEN
    _RTAPT-PRR-REGION @ _RTAPT-P.COPY-OFF @
        _RTAPT-PRR-E @ _RTAPT-E.COPY-A @ + _RTAPT-PRR-REGION !
    _RTAPT-PRR-REGION @ _RTAPT-RD.OWNER @
        _RTAPT-PRR-GLYPH-RUN @ _RTAPT-LD.OWNER @ =
    _RTAPT-PRR-REGION @ _RTAPT-RD.GENERATION @
        _RTAPT-PRR-GLYPH-RUN @ _RTAPT-LD.GENERATION @ = AND
    _RTAPT-PRR-REGION @ _RTAPT-RD.REGION @
        _RTAPT-PRR-GLYPH-RUN @ _RTAPT-LD.REGION @ = AND
    _RTAPT-REGION-BACKLINK-FINISH ;

: _RTAPT-REGION-COPY-SHAPE?  ( copy cols rows -- flag )
    _RTAPT-PF-ROWS ! _RTAPT-PF-COLS ! _RTAPT-PF-COPY !
    _RTAPT-PF-COPY @ _RTAPT-RD.OWNER @ 0=
    _RTAPT-PF-COPY @ _RTAPT-RD.GENERATION @ 0= OR
    _RTAPT-PF-COPY @ _RTAPT-RD.REGION @ 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.X @ _RTAPT-U32? 0=
    _RTAPT-PF-COPY @ _RTAPT-RD.Y @ _RTAPT-U32? 0= OR
    _RTAPT-PF-COPY @ _RTAPT-RD.COLS @ _RTAPT-U32? 0= OR
    _RTAPT-PF-COPY @ _RTAPT-RD.ROWS @ _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.COLS @ 0=
    _RTAPT-PF-COPY @ _RTAPT-RD.ROWS @ 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.X @
    _RTAPT-PF-COPY @ _RTAPT-RD.COLS @ _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-PF-COLS @ U> IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.Y @
    _RTAPT-PF-COPY @ _RTAPT-RD.ROWS @ _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-PF-ROWS @ U> IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.FLAGS @ 3 INVERT AND 0= ;

: _RTAPT-WIRE-BOOL?  ( value -- flag )
    DUP 0= SWAP 1 = OR ;

: _RTAPT-GLYPH-RUN-COPY-SHAPE?  ( copy copy-u -- flag )
    _RTAPT-PF-COPY-U ! _RTAPT-PF-COPY !
    _RTAPT-PF-COPY-U @ _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED U< IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.TEXT-U @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.TEXT-U @
        _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-BV-RAW-U ! _RTAPT-ALIGN8? 0= IF DROP 0 EXIT THEN
    _RTAPT-PF-COPY-U @ <> IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-BV-RAW-U @ +
    _RTAPT-PF-COPY-U @ _RTAPT-BV-RAW-U @ -
        _RTAPT-ZERO-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.OWNER @ 0=
    _RTAPT-PF-COPY @ _RTAPT-LD.GENERATION @ 0= OR
    _RTAPT-PF-COPY @ _RTAPT-LD.OBJECT @ 0= OR
    _RTAPT-PF-COPY @ _RTAPT-LD.REGION @ 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.PARENT @ IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.LEFT @ _RTAPT-U32? 0=
    _RTAPT-PF-COPY @ _RTAPT-LD.TOP @ _RTAPT-U32? 0= OR
    _RTAPT-PF-COPY @ _RTAPT-LD.RIGHT @ _RTAPT-U32? 0= OR
    _RTAPT-PF-COPY @ _RTAPT-LD.BOTTOM @ _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.LEFT @
    _RTAPT-PF-COPY @ _RTAPT-LD.RIGHT @ U< 0=
    _RTAPT-PF-COPY @ _RTAPT-LD.TOP @
    _RTAPT-PF-COPY @ _RTAPT-LD.BOTTOM @ U< 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.VISIBLE @ _RTAPT-WIRE-BOOL? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.FG-RGBA @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.BG-RGBA @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.ATTRS @
        _RTAPT-GLYPH-RUN-ATTRS? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.TEXT
    _RTAPT-PF-COPY @ _RTAPT-LD.TEXT-U @ _RTAPT-GLYPH-RUN-UTF8? ;

: _RTAPT-CONTROL-COPY-SHAPE?  ( copy copy-u -- flag )
    _RTAPT-PF-COPY-U ! _RTAPT-PF-COPY !
    _RTAPT-PF-COPY-U @ _RTAPT-CONTROL-COPY-FIXED U< IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @ _RTAPT-U32? 0=
    _RTAPT-PF-COPY @ _RTAPT-CD.SHORTCUT-U @ _RTAPT-U32? 0= OR IF
        0 EXIT
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @
    _RTAPT-PF-COPY @ _RTAPT-CD.SHORTCUT-U @ _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTAPT-BV-TEXT-U !
    _RTAPT-CONTROL-COPY-FIXED _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-BV-RAW-U ! _RTAPT-ALIGN8? 0= IF DROP 0 EXIT THEN
    _RTAPT-PF-COPY-U @ <> IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-BV-RAW-U @ +
    _RTAPT-PF-COPY-U @ _RTAPT-BV-RAW-U @ -
        _RTAPT-ZERO-SPAN? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.OWNER @ 0=
    _RTAPT-PF-COPY @ _RTAPT-CD.GENERATION @ 0= OR
    _RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @ 0= OR
    _RTAPT-PF-COPY @ _RTAPT-CD.REGION @ 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.KIND @ _RTAPT-CONTROL-KIND? 0= IF
        0 EXIT
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.STATE @ _RTAPT-U16? 0=
    _RTAPT-PF-COPY @ _RTAPT-CD.STATE @
        _RTAPT-CONTROL-F-MASK INVERT AND 0<> OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.Z @ _RTAPT-I32? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.ORDER @ _RTAPT-U32? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.LEFT @ _RTAPT-U32? 0=
    _RTAPT-PF-COPY @ _RTAPT-CD.TOP @ _RTAPT-U32? 0= OR
    _RTAPT-PF-COPY @ _RTAPT-CD.RIGHT @ _RTAPT-U32? 0= OR
    _RTAPT-PF-COPY @ _RTAPT-CD.BOTTOM @ _RTAPT-U32? 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.STATE @
        RTAPT-CONTROL-F-OPEN RTAPT-CONTROL-F-SELECTED OR AND IF
        _RTAPT-PF-COPY @ _RTAPT-CD.STATE @
            RTAPT-CONTROL-F-VISIBLE RTAPT-CONTROL-F-ENABLED OR AND
        RTAPT-CONTROL-F-VISIBLE RTAPT-CONTROL-F-ENABLED OR <> IF
            0 EXIT
        THEN
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.KIND @ RTAPT-CONTROL-MENUBAR = IF
        _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @
        _RTAPT-PF-COPY @ _RTAPT-CD.ORDER @ OR
        _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @ OR
        _RTAPT-PF-COPY @ _RTAPT-CD.SHORTCUT-U @ OR IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.STATE @
            RTAPT-CONTROL-F-VISIBLE RTAPT-CONTROL-F-ENABLED OR
            INVERT AND IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.LEFT @
        _RTAPT-PF-COPY @ _RTAPT-CD.RIGHT @ U< 0=
        _RTAPT-PF-COPY @ _RTAPT-CD.TOP @
        _RTAPT-PF-COPY @ _RTAPT-CD.BOTTOM @ U< 0= OR IF 0 EXIT THEN
    ELSE
        _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @ 0= IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.Z @
        _RTAPT-PF-COPY @ _RTAPT-CD.LEFT @ OR
        _RTAPT-PF-COPY @ _RTAPT-CD.TOP @ OR
        _RTAPT-PF-COPY @ _RTAPT-CD.RIGHT @ OR
        _RTAPT-PF-COPY @ _RTAPT-CD.BOTTOM @ OR IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.KIND @ RTAPT-CONTROL-MENU = IF
            _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @ 0=
            _RTAPT-PF-COPY @ _RTAPT-CD.SHORTCUT-U @ 0<> OR IF 0 EXIT THEN
            _RTAPT-PF-COPY @ _RTAPT-CD.STATE @ 0x0F INVERT AND IF
                0 EXIT
            THEN
        ELSE
            _RTAPT-PF-COPY @ _RTAPT-CD.KIND @ RTAPT-CONTROL-ITEM = IF
                _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @ 0= IF 0 EXIT THEN
                _RTAPT-PF-COPY @ _RTAPT-CD.STATE @ 0x1B INVERT AND IF
                    0 EXIT
                THEN
            ELSE
                _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @
                _RTAPT-PF-COPY @ _RTAPT-CD.SHORTCUT-U @ OR IF 0 EXIT THEN
                _RTAPT-PF-COPY @ _RTAPT-CD.STATE @
                    RTAPT-CONTROL-F-VISIBLE INVERT AND IF 0 EXIT THEN
            THEN
        THEN
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.TEXT
    _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @
        _RTAPT-CONTROL-TEXT? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.TEXT
    _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @ +
    _RTAPT-PF-COPY @ _RTAPT-CD.SHORTCUT-U @ _RTAPT-CONTROL-TEXT? ;

: _RTAPT-CONTROL-DROP-COPY-SHAPE?  ( copy copy-u -- flag )
    _RTAPT-CONTROL-DROP-COPY-SIZE <> IF DROP 0 EXIT THEN
    DUP _RTAPT-CX.OWNER @ 0=
    OVER _RTAPT-CX.GENERATION @ 0= OR
    SWAP _RTAPT-CX.CONTROL @ 0= OR 0= ;

\ The DEFINE graph is proven in one capture-order pass.  Complete menu forests
\ may repeat, with each new bar resetting the current MENU interval.  Global
\ contiguous IDs still make parent checks independent of a caller-bank rescan.
: _RTAPT-PF-CONTROL-NEXT-ID?  ( -- flag )
    _RTAPT-PF-CCOUNT @ 0= IF
        _RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @ DUP
        _RTAPT-PF-CHIGH @ U> 0= IF DROP 0 EXIT THEN
        _RTAPT-PF-CHIGH ! -1 EXIT
    THEN
    _RTAPT-PF-CHIGH @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @ <> IF DROP 0 EXIT THEN
    _RTAPT-PF-CHIGH ! -1 ;

: _RTAPT-PF-CONTROL-MENU?  ( -- flag )
    _RTAPT-PF-CPHASE @ DUP _RTAPT-PF-CONTROL-PHASE-BAR =
    SWAP _RTAPT-PF-CONTROL-PHASE-MENU = OR 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @ _RTAPT-PF-CBAR-ID @ <>
        IF 0 EXIT THEN
    _RTAPT-PF-CPHASE @ _RTAPT-PF-CONTROL-PHASE-BAR = IF
        _RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @ _RTAPT-PF-CMENU-FIRST !
    ELSE
        _RTAPT-PF-COPY @ _RTAPT-CD.ORDER @ _RTAPT-PF-CORDER @ U> 0=
            IF 0 EXIT THEN
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @ _RTAPT-PF-CMENU-LAST !
    _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @ _RTAPT-PF-CPARENT !
    _RTAPT-PF-COPY @ _RTAPT-CD.ORDER @ _RTAPT-PF-CORDER !
    _RTAPT-PF-COPY @ _RTAPT-CD.STATE @ RTAPT-CONTROL-F-OPEN AND IF
        _RTAPT-PF-COPEN-MENU @ IF 0 EXIT THEN
        -1 _RTAPT-PF-COPEN-MENU !
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.STATE @ RTAPT-CONTROL-F-SELECTED AND IF
        _RTAPT-PF-CSELECTED-MENU @ IF 0 EXIT THEN
        -1 _RTAPT-PF-CSELECTED-MENU !
    THEN
    _RTAPT-PF-CONTROL-PHASE-MENU _RTAPT-PF-CPHASE ! -1 ;

: _RTAPT-PF-CONTROL-ITEM?  ( -- flag )
    _RTAPT-PF-CPHASE @ DUP _RTAPT-PF-CONTROL-PHASE-MENU =
    SWAP _RTAPT-PF-CONTROL-PHASE-ITEM = OR 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @
        _RTAPT-PF-CMENU-FIRST @ U< IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @
        _RTAPT-PF-CMENU-LAST @ U> IF 0 EXIT THEN
    _RTAPT-PF-CPHASE @ _RTAPT-PF-CONTROL-PHASE-ITEM = IF
        _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @ _RTAPT-PF-CPARENT @ U<
            IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @ _RTAPT-PF-CPARENT @ = IF
            _RTAPT-PF-COPY @ _RTAPT-CD.ORDER @ _RTAPT-PF-CORDER @ U> 0=
                IF 0 EXIT THEN
        THEN
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.KIND @ RTAPT-CONTROL-ITEM =
    _RTAPT-PF-COPY @ _RTAPT-CD.STATE @ RTAPT-CONTROL-F-SELECTED AND 0<> AND IF
        _RTAPT-PF-CSELECTED-ITEM-PARENT @
        _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @ = IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @
            _RTAPT-PF-CSELECTED-ITEM-PARENT !
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.PARENT @ _RTAPT-PF-CPARENT !
    _RTAPT-PF-COPY @ _RTAPT-CD.ORDER @ _RTAPT-PF-CORDER !
    _RTAPT-PF-CONTROL-PHASE-ITEM _RTAPT-PF-CPHASE ! -1 ;

: _RTAPT-PF-CONTROL-DEFINE-GRAPH?  ( -- flag )
    _RTAPT-PF-CONTROL-NEXT-ID? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.KIND @ RTAPT-CONTROL-MENUBAR = IF
        _RTAPT-PF-CBAR-COUNT @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
            _RTAPT-PF-CBAR-COUNT !
        _RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @ _RTAPT-PF-CBAR-ID !
        0 _RTAPT-PF-CMENU-FIRST ! 0 _RTAPT-PF-CMENU-LAST !
        0 _RTAPT-PF-CPARENT ! 0 _RTAPT-PF-CORDER !
        0 _RTAPT-PF-COPEN-MENU ! 0 _RTAPT-PF-CSELECTED-MENU !
        0 _RTAPT-PF-CSELECTED-ITEM-PARENT !
        _RTAPT-PF-CONTROL-PHASE-BAR _RTAPT-PF-CPHASE ! -1 EXIT
    THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.KIND @ RTAPT-CONTROL-MENU = IF
        _RTAPT-PF-CONTROL-MENU? EXIT
    THEN
    _RTAPT-PF-CONTROL-ITEM? ;

VARIABLE _RTAPT-PA-E
VARIABLE _RTAPT-PA-COLS
VARIABLE _RTAPT-PA-ROWS
VARIABLE _RTAPT-PA-NONDEFINITIONS
VARIABLE _RTAPT-PA-I

: _RTAPT-PUBLICATION-OWNERS-INIT  ( -- )
    -1 _RTAPT-AUDIT-SCRATCH-DIRTY !
    _RTAPT-PA-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        I _RTAPT-PA-E @ _RTAPT-OWNER-NTH
        _RTAPT-OWNER-AUDIT-OFF + _RTAPT-OWNER-AUDIT-SIZE 0 FILL
        I _RTAPT-PA-E @ _RTAPT-OWNER-NTH DUP _RTAPT-O.STATE @
            RTAPT-OWNER-ST-FREE <> IF
            DUP _RTAPT-O.REGION-HIGH @ OVER _RTAPT-O.A-RHIGH !
            DUP _RTAPT-O.OBJECT-HIGH @ OVER _RTAPT-O.A-OHIGH !
            DUP _RTAPT-O.CONTROL-HIGH @ OVER _RTAPT-O.A-CHIGH !
        THEN
        DROP
    LOOP ;

: _RTAPT-PUBLICATION-OWNER-LOAD  ( owner-record -- )
    DUP _RTAPT-PF-O !
    DUP _RTAPT-O.A-RCOUNT @ _RTAPT-PF-RCOUNT !
    DUP _RTAPT-O.A-RHIGH @ _RTAPT-PF-RHIGH !
    DUP _RTAPT-O.A-OCOUNT @ _RTAPT-PF-OCOUNT !
    DUP _RTAPT-O.A-OHIGH @ _RTAPT-PF-OHIGH !
    DUP _RTAPT-O.A-UTF8 @ _RTAPT-PF-UTF8 !
    DUP _RTAPT-O.A-CCOUNT @ _RTAPT-PF-CCOUNT !
    DUP _RTAPT-O.A-CHIGH @ _RTAPT-PF-CHIGH !
    DUP _RTAPT-O.A-CPHASE @ _RTAPT-PF-CPHASE !
    DUP _RTAPT-O.A-CBAR-COUNT @ _RTAPT-PF-CBAR-COUNT !
    DUP _RTAPT-O.A-CBAR-ID @ _RTAPT-PF-CBAR-ID !
    DUP _RTAPT-O.A-CMENU-FIRST @ _RTAPT-PF-CMENU-FIRST !
    DUP _RTAPT-O.A-CMENU-LAST @ _RTAPT-PF-CMENU-LAST !
    DUP _RTAPT-O.A-CPARENT @ _RTAPT-PF-CPARENT !
    DUP _RTAPT-O.A-CORDER @ _RTAPT-PF-CORDER !
    DUP _RTAPT-O.A-COPEN-MENU @ _RTAPT-PF-COPEN-MENU !
    DUP _RTAPT-O.A-CSELECTED-MENU @ _RTAPT-PF-CSELECTED-MENU !
    _RTAPT-O.A-CSELECTED-ITEM-PARENT @
        _RTAPT-PF-CSELECTED-ITEM-PARENT ! ;

: _RTAPT-PUBLICATION-OWNER-SAVE  ( -- flag )
    _RTAPT-PF-RCOUNT @ _RTAPT-PF-O @ _RTAPT-O.A-RCOUNT !
    _RTAPT-PF-RHIGH @ _RTAPT-PF-O @ _RTAPT-O.A-RHIGH !
    _RTAPT-PF-OCOUNT @ _RTAPT-PF-O @ _RTAPT-O.A-OCOUNT !
    _RTAPT-PF-OHIGH @ _RTAPT-PF-O @ _RTAPT-O.A-OHIGH !
    _RTAPT-PF-UTF8 @ _RTAPT-PF-O @ _RTAPT-O.A-UTF8 !
    _RTAPT-PF-CCOUNT @ _RTAPT-PF-O @ _RTAPT-O.A-CCOUNT !
    _RTAPT-PF-CHIGH @ _RTAPT-PF-O @ _RTAPT-O.A-CHIGH !
    _RTAPT-PF-CPHASE @ _RTAPT-PF-O @ _RTAPT-O.A-CPHASE !
    _RTAPT-PF-CBAR-COUNT @ _RTAPT-PF-O @ _RTAPT-O.A-CBAR-COUNT !
    _RTAPT-PF-CBAR-ID @ _RTAPT-PF-O @ _RTAPT-O.A-CBAR-ID !
    _RTAPT-PF-CMENU-FIRST @ _RTAPT-PF-O @ _RTAPT-O.A-CMENU-FIRST !
    _RTAPT-PF-CMENU-LAST @ _RTAPT-PF-O @ _RTAPT-O.A-CMENU-LAST !
    _RTAPT-PF-CPARENT @ _RTAPT-PF-O @ _RTAPT-O.A-CPARENT !
    _RTAPT-PF-CORDER @ _RTAPT-PF-O @ _RTAPT-O.A-CORDER !
    _RTAPT-PF-COPEN-MENU @ _RTAPT-PF-O @ _RTAPT-O.A-COPEN-MENU !
    _RTAPT-PF-CSELECTED-MENU @
        _RTAPT-PF-O @ _RTAPT-O.A-CSELECTED-MENU !
    _RTAPT-PF-CSELECTED-ITEM-PARENT @
        _RTAPT-PF-O @ _RTAPT-O.A-CSELECTED-ITEM-PARENT !
    _RTAPT-PF-O @ _RTAPT-O.A-OPS @ 1 _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN _RTAPT-PF-O @ _RTAPT-O.A-OPS !
    -1 ;

: _RTAPT-PUBLICATION-AUDIT-FINISH  ( flag -- flag )
    _RTAPT-AUDIT-SCRATCH-DIRTY @ _RTAPT-PA-E @ 0<> AND IF
        _RTAPT-PA-E @
        DUP _RTAPT-E.OWNER-CAP @ 0 ?DO
            I OVER _RTAPT-OWNER-NTH
            _RTAPT-OWNER-AUDIT-OFF + _RTAPT-OWNER-AUDIT-SIZE 0 FILL
        LOOP
        DROP
    THEN
    0 _RTAPT-AUDIT-SCRATCH-DIRTY !
    0 _RTAPT-PA-E ! 0 _RTAPT-PA-COLS ! 0 _RTAPT-PA-ROWS !
    0 _RTAPT-PA-NONDEFINITIONS !
    0 _RTAPT-PF-E ! 0 _RTAPT-PF-O ! 0 _RTAPT-PF-P ! 0 _RTAPT-PF-COPY ! ;

\ One structural/semantic operation pass used only by the final publication
\ audit.  It replaces the separate captured-bank and owner-times-operation
\ candidate scans at COMMIT.
: _RTAPT-PUBLICATION-OP-SHAPE?  ( -- flag )
    _RTAPT-PF-P @ _RTAPT-P.OWNER-SLOT @
        _RTAPT-PA-E @ _RTAPT-E.OWNER-CAP @ U< 0= IF 0 EXIT THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-OP-GLYPH-RUN-DEFINE = IF
        _RTAPT-PF-P @ _RTAPT-P.REGION-OP @ DUP 0= IF DROP 0 EXIT THEN
        1- _RTAPT-PA-I @ U< 0= IF 0 EXIT THEN
    ELSE
        _RTAPT-PF-P @ _RTAPT-P.REGION-OP @ IF 0 EXIT THEN
    THEN
    _RTAPT-PF-P @ _RTAPT-P.COPY-OFF @ _RTAPT-BV-OFF @ <> IF 0 EXIT THEN
    _RTAPT-PF-P @ _RTAPT-P.COPY-U @ DUP 0= IF DROP 0 EXIT THEN
        _RTAPT-BV-COPY-U !
    _RTAPT-BV-OFF @ _RTAPT-BV-COPY-U @ _RTAPT-UADD? 0= IF
        DROP 0 EXIT
    THEN DUP _RTAPT-BV-NEXT !
    _RTAPT-PA-E @ _RTAPT-E.COPY-USED @ U> IF 0 EXIT THEN
    _RTAPT-BV-NEXT @ _RTAPT-PA-E @ _RTAPT-E.COPY-U @ U> IF 0 EXIT THEN
    _RTAPT-PA-E @ _RTAPT-E.COPY-A @ _RTAPT-BV-OFF @ +
        DUP _RTAPT-BV-COPY ! _RTAPT-PF-COPY !
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-OP-REGION-DEFINE = IF
        _RTAPT-BV-COPY-U @ _RTAPT-REGION-DEFINE-COPY-SIZE <> IF 0 EXIT THEN
        _RTAPT-REGION-DEFINE-FRAME-BYTES _RTAPT-BV-FRAME !
        -1 EXIT
    THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-GLYPH-RUN-OP? IF
        _RTAPT-BV-COPY-U @ _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED U< IF
            0 EXIT
        THEN
        _RTAPT-BV-COPY @ _RTAPT-LD.TEXT-U @ _RTAPT-U32? 0= IF 0 EXIT THEN
        _RTAPT-BV-COPY @ _RTAPT-LD.TEXT-U @
            _RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED _RTAPT-UADD? 0= IF
            DROP 0 EXIT
        THEN DUP _RTAPT-BV-RAW-U ! _RTAPT-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTAPT-BV-COPY-U @ <> IF 0 EXIT THEN
        _RTAPT-BV-COPY @ _RTAPT-BV-RAW-U @ +
        _RTAPT-BV-COPY-U @ _RTAPT-BV-RAW-U @ -
            _RTAPT-ZERO-SPAN? 0= IF 0 EXIT THEN
        _RTAPT-BV-COPY @ _RTAPT-LD.TEXT-U @
            _RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED _RTAPT-UADD? 0= IF
            DROP 0 EXIT
        THEN _RTAPT-BV-FRAME ! -1 EXIT
    THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-CONTROL-WRITE-OP? IF
        _RTAPT-BV-COPY-U @ _RTAPT-CONTROL-COPY-FIXED U< IF 0 EXIT THEN
        _RTAPT-BV-COPY @ _RTAPT-CD.LABEL-U @ _RTAPT-U32? 0=
        _RTAPT-BV-COPY @ _RTAPT-CD.SHORTCUT-U @ _RTAPT-U32? 0= OR IF
            0 EXIT
        THEN
        _RTAPT-BV-COPY @ _RTAPT-CD.LABEL-U @
        _RTAPT-BV-COPY @ _RTAPT-CD.SHORTCUT-U @ _RTAPT-UADD? 0= IF
            DROP 0 EXIT
        THEN DUP _RTAPT-BV-TEXT-U !
        _RTAPT-CONTROL-COPY-FIXED _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        DUP _RTAPT-BV-RAW-U ! _RTAPT-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTAPT-BV-COPY-U @ <> IF 0 EXIT THEN
        _RTAPT-BV-COPY @ _RTAPT-BV-RAW-U @ +
        _RTAPT-BV-COPY-U @ _RTAPT-BV-RAW-U @ -
            _RTAPT-ZERO-SPAN? 0= IF 0 EXIT THEN
        _RTAPT-BV-TEXT-U @ _RTAPT-CONTROL-FRAME-FIXED _RTAPT-UADD? 0= IF
            DROP 0 EXIT
        THEN _RTAPT-BV-FRAME ! -1 EXIT
    THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-OP-CONTROL-DROP <> IF 0 EXIT THEN
    _RTAPT-BV-COPY-U @ _RTAPT-CONTROL-DROP-COPY-SIZE <> IF 0 EXIT THEN
    _RTAPT-CONTROL-DROP-FRAME-BYTES _RTAPT-BV-FRAME ! -1 ;

: _RTAPT-PUBLICATION-OWNER?  ( -- flag )
    _RTAPT-PF-P @ _RTAPT-P.OWNER-SLOT @ _RTAPT-PA-E @ _RTAPT-OWNER-NTH
        DUP _RTAPT-PF-O !
    DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN <> IF DROP 0 EXIT THEN
    DUP _RTAPT-O.OWNER @ _RTAPT-PF-COPY @ _RTAPT-LD.OWNER @ =
    SWAP _RTAPT-O.GENERATION @
        _RTAPT-PF-COPY @ _RTAPT-LD.GENERATION @ = AND 0= IF 0 EXIT THEN
    _RTAPT-PF-O @ _RTAPT-PUBLICATION-OWNER-LOAD -1 ;

: _RTAPT-PUBLICATION-NONDEFINITION+?  ( -- flag )
    _RTAPT-PA-NONDEFINITIONS @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-PA-NONDEFINITIONS ! -1 ;

: _RTAPT-PUBLICATION-REGION?  ( -- flag )
    _RTAPT-PF-COPY @ _RTAPT-PA-COLS @ _RTAPT-PA-ROWS @
        _RTAPT-REGION-COPY-SHAPE? 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.REGION @
        _RTAPT-PF-RHIGH @ U> 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-RD.REGION @ _RTAPT-PF-RHIGH !
    _RTAPT-PF-RCOUNT @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
    _RTAPT-PF-RCOUNT ! -1 ;

: _RTAPT-PUBLICATION-GLYPH?  ( -- flag )
    _RTAPT-PF-COPY @ _RTAPT-PF-P @ _RTAPT-P.COPY-U @
        _RTAPT-GLYPH-RUN-COPY-SHAPE? 0= IF 0 EXIT THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-OP-GLYPH-RUN-DEFINE = IF
        _RTAPT-PA-I @ _RTAPT-PF-COPY @ _RTAPT-PF-P @ _RTAPT-PA-E @
            _RTAPT-REGION-BACKLINK? 0= IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-LD.OBJECT @
            _RTAPT-PF-OHIGH @ U> 0= IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-LD.OBJECT @ _RTAPT-PF-OHIGH !
        _RTAPT-PF-UTF8 @ _RTAPT-PF-COPY @ _RTAPT-LD.TEXT-U @
            _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-PF-UTF8 !
        _RTAPT-PF-OCOUNT @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        _RTAPT-PF-OCOUNT ! -1 EXIT
    THEN
    _RTAPT-PF-COPY @ _RTAPT-LD.OBJECT @
    _RTAPT-PF-COPY @ _RTAPT-LD.REGION @
    _RTAPT-PF-O @ _RTAPT-PA-E @ _RTAPT-GLYPH-RUN-TARGET? 0= IF
        0 EXIT
    THEN
    _RTAPT-PUBLICATION-NONDEFINITION+? ;

: _RTAPT-PUBLICATION-CONTROL?  ( -- flag )
    _RTAPT-PF-COPY @ _RTAPT-PF-P @ _RTAPT-P.COPY-U @
        _RTAPT-CONTROL-COPY-SHAPE? 0= IF 0 EXIT THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-OP-CONTROL-DEFINE = IF
        _RTAPT-PA-E @ _RTAPT-E.RET-MODE @ PT-RET-REPLACE-START <>
            IF 0 EXIT THEN
        _RTAPT-PF-RCOUNT @ 0= IF 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.REGION @ _RTAPT-PF-RHIGH @ U>
            IF 0 EXIT THEN
        _RTAPT-PF-CONTROL-DEFINE-GRAPH? 0= IF 0 EXIT THEN
        _RTAPT-PF-CCOUNT @ 1 _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
            _RTAPT-PF-CCOUNT !
        _RTAPT-PF-UTF8 @ _RTAPT-PF-COPY @ _RTAPT-CD.LABEL-U @
            _RTAPT-UADD? 0= IF DROP 0 EXIT THEN
        _RTAPT-PF-COPY @ _RTAPT-CD.SHORTCUT-U @
            _RTAPT-UADD? 0= IF DROP 0 EXIT THEN _RTAPT-PF-UTF8 !
        -1 EXIT
    THEN
    _RTAPT-PA-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA <> IF 0 EXIT THEN
    _RTAPT-PF-O @ _RTAPT-O.ACTIVE-CONTROLS @ 0= IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @
        _RTAPT-PF-O @ _RTAPT-O.CONTROL-HIGH @ U> IF 0 EXIT THEN
    _RTAPT-PUBLICATION-NONDEFINITION+? ;

: _RTAPT-PUBLICATION-DROP?  ( -- flag )
    _RTAPT-PF-COPY @ _RTAPT-PF-P @ _RTAPT-P.COPY-U @
        _RTAPT-CONTROL-DROP-COPY-SHAPE? 0= IF 0 EXIT THEN
    _RTAPT-PA-E @ _RTAPT-E.RET-MODE @ PT-RET-DELTA <>
    _RTAPT-PF-O @ _RTAPT-O.ACTIVE-CONTROLS @ 0= OR IF 0 EXIT THEN
    _RTAPT-PF-COPY @ _RTAPT-CX.CONTROL @
        _RTAPT-PF-O @ _RTAPT-O.CONTROL-HIGH @ U> IF 0 EXIT THEN
    _RTAPT-PUBLICATION-NONDEFINITION+? ;

: _RTAPT-PUBLICATION-SEMANTICS?  ( -- flag )
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-OP-REGION-DEFINE = IF
        _RTAPT-PUBLICATION-REGION? EXIT
    THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-GLYPH-RUN-OP? IF
        _RTAPT-PUBLICATION-GLYPH? EXIT
    THEN
    _RTAPT-PF-P @ _RTAPT-P.KIND @ _RTAPT-CONTROL-WRITE-OP? IF
        _RTAPT-PUBLICATION-CONTROL? EXIT
    THEN
    _RTAPT-PUBLICATION-DROP? ;

: _RTAPT-PUBLICATION-OPS?  ( -- flag )
    0 _RTAPT-BV-OFF ! 0 _RTAPT-BV-RET ! 0 _RTAPT-PF-TOTAL !
    0 _RTAPT-PA-NONDEFINITIONS !
    _RTAPT-PA-E @ _RTAPT-E.OP-COUNT @ 0 ?DO
        I _RTAPT-PA-I !
        I _RTAPT-PA-E @ _RTAPT-OP-NTH DUP _RTAPT-PF-P ! _RTAPT-BV-P !
        _RTAPT-PUBLICATION-OP-SHAPE? 0= IF 0 UNLOOP EXIT THEN
        _RTAPT-PUBLICATION-OWNER? 0= IF 0 UNLOOP EXIT THEN
        _RTAPT-PUBLICATION-SEMANTICS? 0= IF 0 UNLOOP EXIT THEN
        _RTAPT-PUBLICATION-OWNER-SAVE 0= IF 0 UNLOOP EXIT THEN
        _RTAPT-BV-NEXT @ _RTAPT-BV-OFF !
        _RTAPT-BV-RET @ _RTAPT-BV-FRAME @ _RTAPT-UADD? 0= IF
            DROP 0 UNLOOP EXIT
        THEN _RTAPT-BV-RET !
        1 _RTAPT-PF-TOTAL +!
    LOOP
    _RTAPT-BV-OFF @ _RTAPT-PA-E @ _RTAPT-E.COPY-USED @ =
    _RTAPT-BV-RET @ _RTAPT-PA-E @ _RTAPT-E.RET-BYTES @ = AND
    _RTAPT-PF-TOTAL @ _RTAPT-PA-E @ _RTAPT-E.OP-COUNT @ = AND ;

: _RTAPT-PUBLICATION-AUDIT-BODY  ( -- flag )
    _RTAPT-PUBLICATION-OWNERS-INIT
    _RTAPT-PUBLICATION-OPS? 0= IF 0 EXIT THEN
    _RTAPT-PA-NONDEFINITIONS @ -1 _RTAPT-PA-E @
        _RTAPT-OWNER-LEDGERS-FROM? ;

: _RTAPT-PUBLICATION-AUDIT?  ( cols rows engine -- flag )
    _RTAPT-PA-E ! _RTAPT-PA-ROWS ! _RTAPT-PA-COLS !
    _RTAPT-PA-E @ _RTAPT-PF-E !
    _RTAPT-PA-COLS @ _RTAPT-PF-COLS !
    _RTAPT-PA-ROWS @ _RTAPT-PF-ROWS !
    ['] _RTAPT-PUBLICATION-AUDIT-BODY CATCH ?DUP IF DROP 0 THEN
    _RTAPT-PUBLICATION-AUDIT-FINISH ;

VARIABLE _RTAPT-CB-E
VARIABLE _RTAPT-CB-COLS
VARIABLE _RTAPT-CB-ROWS
VARIABLE _RTAPT-CB-SPANS
VARIABLE _RTAPT-CB-CELLS
VARIABLE _RTAPT-CB-MODE
VARIABLE _RTAPT-CB-STATE
VARIABLE _RTAPT-CB-STATUS

: RTAPT-CELL-BEGIN  ( cols rows span-count cell-count cell-mode engine -- status )
    _RTAPT-CB-E ! _RTAPT-CB-MODE ! _RTAPT-CB-CELLS ! _RTAPT-CB-SPANS !
    _RTAPT-CB-ROWS ! _RTAPT-CB-COLS !
    _RTAPT-CB-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CB-E @ _RTAPT-E.UPDATE-STATE @ DUP _RTAPT-CB-STATE !
    DUP RTAPT-UPDATE-IDLE = SWAP RTAPT-UPDATE-SEALED = OR 0= IF
        RTAPT-S-BUSY EXIT
    THEN
    _RTAPT-CB-STATE @ RTAPT-UPDATE-SEALED = IF
        _RTAPT-CB-E @ _RTAPT-SEALED-READY? 0= IF
            RTAPT-S-INVALID EXIT
        THEN
    ELSE
        \ CELL-only BEGIN has no retained candidate handoff, so retain the
        \ complete engine check on that independent path.
        _RTAPT-CB-E @ _RTAPT-ENGINE-VALID? 0= IF
            RTAPT-S-INVALID EXIT
        THEN
    THEN
    _RTAPT-CB-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF EXIT THEN DROP
    _RTAPT-CB-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <>
    _RTAPT-CB-E @ _RTAPT-E.QUEUE-HEAD @ OR
    _RTAPT-CB-E @ _RTAPT-E.QUEUE-TAIL @ OR IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CB-COLS @ _RTAPT-CB-ROWS @ _RTAPT-CB-SPANS @ _RTAPT-CB-CELLS @
        _RTAPT-CB-MODE @ _RTAPT-CELL-COUNTS? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CB-MODE @ PT-CELL-NONE =
    _RTAPT-CB-STATE @ RTAPT-UPDATE-SEALED <> AND IF
        RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-CB-STATE @ RTAPT-UPDATE-SEALED = IF
        _RTAPT-CB-COLS @ _RTAPT-CB-ROWS @
        _RTAPT-CB-SPANS @ _RTAPT-CB-CELLS @
        _RTAPT-CB-E @ _RTAPT-E.OP-COUNT @
        _RTAPT-CB-E @ _RTAPT-E.RET-BYTES @
        _RTAPT-CB-MODE @ _RTAPT-CB-E @ _RTAPT-E.RET-MODE @
        _RTAPT-CB-E @ _RTAPT-E.SESSION @ PT-PRESENT-BEGIN _RTAPT-PT>STATUS
    ELSE
        _RTAPT-CB-COLS @ _RTAPT-CB-ROWS @
        _RTAPT-CB-SPANS @ _RTAPT-CB-CELLS @ 0 0
        _RTAPT-CB-MODE @ PT-RET-NONE
        _RTAPT-CB-E @ _RTAPT-E.SESSION @ PT-PRESENT-BEGIN _RTAPT-PT>STATUS
    THEN
    DUP _RTAPT-CB-STATUS ! RTAPT-S-OK <> IF
        _RTAPT-CB-STATUS @ RTAPT-S-SESSION-LOST = IF
            RTAPT-S-SESSION-LOST _RTAPT-CB-E @ _RTAPT-QUARANTINE-ALL EXIT
        THEN
        _RTAPT-CB-STATUS @ DUP _RTAPT-CB-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    _RTAPT-CB-STATE @ RTAPT-UPDATE-IDLE = IF
        PT-RET-NONE _RTAPT-CB-E @ _RTAPT-E.RET-MODE !
        PT-COMMIT _RTAPT-CB-E @ _RTAPT-E.DISPOSITION !
    THEN
    _RTAPT-CB-MODE @ PT-CELL-NONE = IF RTAPT-COUPLING-RETAINED
        ELSE RTAPT-COUPLING-CELL THEN
        _RTAPT-CB-E @ _RTAPT-E.COUPLING !
    _RTAPT-CB-COLS @ _RTAPT-CB-E @ _RTAPT-E.COLS !
    _RTAPT-CB-ROWS @ _RTAPT-CB-E @ _RTAPT-E.ROWS !
    _RTAPT-CB-SPANS @ _RTAPT-CB-E @ _RTAPT-E.CELL-SPANS !
    _RTAPT-CB-CELLS @ _RTAPT-CB-E @ _RTAPT-E.CELLS !
    _RTAPT-CB-MODE @ _RTAPT-CB-E @ _RTAPT-E.CELL-MODE !
    0 _RTAPT-CB-E @ _RTAPT-E.SEND-INDEX !
    RTAPT-UPDATE-CELL-OPEN _RTAPT-CB-E @ _RTAPT-E.UPDATE-STATE !
    RTAPT-S-OK DUP _RTAPT-CB-E @ _RTAPT-E.LAST-STATUS ! ;

VARIABLE _RTAPT-CW-E
VARIABLE _RTAPT-CW-STATUS
VARIABLE _RTAPT-CW-SPAN-ROW
VARIABLE _RTAPT-CW-SPAN-COL
VARIABLE _RTAPT-CW-SPAN-COUNT
VARIABLE _RTAPT-CW-CODEPOINT
VARIABLE _RTAPT-CW-FG
VARIABLE _RTAPT-CW-BG
VARIABLE _RTAPT-CW-ATTRS
VARIABLE _RTAPT-CW-CURSOR-ROW
VARIABLE _RTAPT-CW-CURSOR-COL
VARIABLE _RTAPT-CW-CURSOR-VISIBLE

: _RTAPT-CELL-FEED-READY?  ( engine -- flag )
    DUP _RTAPT-ENGINE-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CELL-OPEN <>
        IF DROP 0 EXIT THEN
    DUP _RTAPT-E.COUPLING @ RTAPT-COUPLING-CELL <> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-O @
    OVER _RTAPT-E.QUEUE-HEAD @ OR
    OVER _RTAPT-E.QUEUE-TAIL @ OR IF DROP 0 EXIT THEN
    DUP _RTAPT-E.SEND-INDEX @ IF DROP 0 EXIT THEN
    DUP _RTAPT-E.CELL-MODE @ _RTAPT-CELL-MODE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.COLS @
    OVER _RTAPT-E.ROWS @
    2 PICK _RTAPT-E.CELL-SPANS @
    3 PICK _RTAPT-E.CELLS @
    4 PICK _RTAPT-E.CELL-MODE @ _RTAPT-CELL-COUNTS? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.RET-MODE @ PT-RET-NONE = IF
        DUP _RTAPT-E.OP-COUNT @
        OVER _RTAPT-E.COPY-USED @ OR
        OVER _RTAPT-E.RET-BYTES @ OR IF DROP 0 EXIT THEN
        DUP _RTAPT-E.DISPOSITION @ PT-COMMIT <> IF DROP 0 EXIT THEN
    ELSE
        DUP _RTAPT-E.RET-MODE @ _RTAPT-MODE? 0= IF DROP 0 EXIT THEN
        DUP _RTAPT-E.RET-MODE @ OVER _RTAPT-E.DISPOSITION @
            _RTAPT-MODE-DISPOSITION? 0= IF DROP 0 EXIT THEN
        DUP _RTAPT-E.RET-MODE @ PT-RET-DELTA =
        OVER _RTAPT-E.OP-COUNT @ 0= AND IF DROP 0 EXIT THEN
    THEN
    DROP -1 ;

: _RTAPT-FEED-RESULT  ( status engine -- status )
    _RTAPT-CW-E ! DUP _RTAPT-CW-STATUS !
    DUP RTAPT-S-SESSION-LOST = IF
        DROP RTAPT-S-SESSION-LOST _RTAPT-CW-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    DUP _RTAPT-CW-E @ _RTAPT-E.LAST-STATUS ! ;

: RTAPT-CELL-SPAN-BEGIN  ( row col count engine -- status )
    _RTAPT-CW-E ! _RTAPT-CW-SPAN-COUNT !
    _RTAPT-CW-SPAN-COL ! _RTAPT-CW-SPAN-ROW !
    _RTAPT-CW-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CW-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-CW-E @ _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    _RTAPT-CW-E @ _RTAPT-CELL-FEED-READY? 0= IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CW-SPAN-ROW @ _RTAPT-CW-SPAN-COL @ _RTAPT-CW-SPAN-COUNT @
        _RTAPT-CW-E @ _RTAPT-E.SESSION @ PT-SPAN-BEGIN _RTAPT-PT>STATUS
        _RTAPT-CW-E @ _RTAPT-FEED-RESULT ;

: RTAPT-CELL-WRITE  ( codepoint fg bg attrs engine -- status )
    _RTAPT-CW-E ! _RTAPT-CW-ATTRS ! _RTAPT-CW-BG !
    _RTAPT-CW-FG ! _RTAPT-CW-CODEPOINT !
    _RTAPT-CW-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CW-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-CW-E @ _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    _RTAPT-CW-E @ _RTAPT-CELL-FEED-READY? 0= IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CW-CODEPOINT @ _RTAPT-CW-FG @
    _RTAPT-CW-BG @ _RTAPT-CW-ATTRS @
        _RTAPT-CW-E @ _RTAPT-E.SESSION @ PT-CELL _RTAPT-PT>STATUS
        _RTAPT-CW-E @ _RTAPT-FEED-RESULT ;

: RTAPT-CELL-CURSOR  ( row col visible engine -- status )
    _RTAPT-CW-E ! _RTAPT-CW-CURSOR-VISIBLE !
    _RTAPT-CW-CURSOR-COL ! _RTAPT-CW-CURSOR-ROW !
    _RTAPT-CW-E @ _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CW-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-CW-E @ _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    _RTAPT-CW-E @ _RTAPT-CELL-FEED-READY? 0= IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CW-CURSOR-ROW @ _RTAPT-CW-CURSOR-COL @
    _RTAPT-CW-CURSOR-VISIBLE @
        _RTAPT-CW-E @ _RTAPT-E.SESSION @ PT-CURSOR _RTAPT-PT>STATUS
        _RTAPT-CW-E @ _RTAPT-FEED-RESULT ;

VARIABLE _RTAPT-CA-E
VARIABLE _RTAPT-CA-REASON
VARIABLE _RTAPT-CA-STATUS

: _RTAPT-ABORT-OPEN  ( reason engine -- status )
    _RTAPT-CA-E ! _RTAPT-CA-REASON !
    _RTAPT-CA-REASON @ _RTAPT-CA-E @ _RTAPT-E.SESSION @
        PT-TX-ABORT _RTAPT-PT>STATUS DUP _RTAPT-CA-STATUS !
    RTAPT-S-OK = IF
        _RTAPT-CA-E @ _RTAPT-WIRE-REWIND
        RTAPT-S-OK DUP _RTAPT-CA-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    RTAPT-S-SESSION-LOST _RTAPT-CA-E @ _RTAPT-QUARANTINE-ALL ;

: RTAPT-CELL-ABORT  ( reason engine -- status )
    DUP _RTAPT-CA-E !
    DUP _RTAPT-ENGINE-VALID? 0= IF 2DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        NIP _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    OVER 0xFFFF U> IF 2DROP RTAPT-S-INVALID EXIT THEN
    DUP _RTAPT-E.UPDATE-STATE @ DUP RTAPT-UPDATE-IDLE =
    SWAP RTAPT-UPDATE-SEALED = OR IF
        2DROP RTAPT-S-OK DUP _RTAPT-CA-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CELL-OPEN <> IF
        2DROP RTAPT-S-BUSY EXIT
    THEN
    _RTAPT-ABORT-OPEN ;

VARIABLE _RTAPT-CS-E
VARIABLE _RTAPT-CS-P
VARIABLE _RTAPT-CS-COPY
VARIABLE _RTAPT-CS-REPLACE

: _RTAPT-SEND-REGION  ( -- status )
    _RTAPT-CS-COPY @ _RTAPT-RD.OWNER @
    _RTAPT-CS-COPY @ _RTAPT-RD.GENERATION @
    _RTAPT-CS-COPY @ _RTAPT-RD.REGION @
    _RTAPT-CS-COPY @ _RTAPT-RD.X @
    _RTAPT-CS-COPY @ _RTAPT-RD.Y @
    _RTAPT-CS-COPY @ _RTAPT-RD.COLS @
    _RTAPT-CS-COPY @ _RTAPT-RD.ROWS @
    _RTAPT-CS-COPY @ _RTAPT-RD.Z @
    _RTAPT-CS-COPY @ _RTAPT-RD.FLAGS @
    _RTAPT-CS-E @ _RTAPT-E.SESSION @ PT-REGION-DEFINE _RTAPT-PT>STATUS ;

: _RTAPT-SEND-GLYPH-RUN  ( replace? -- status )
    _RTAPT-CS-REPLACE !
    _RTAPT-CS-COPY @ _RTAPT-LD.OWNER @
    _RTAPT-CS-COPY @ _RTAPT-LD.GENERATION @
    _RTAPT-CS-COPY @ _RTAPT-LD.OBJECT @
    _RTAPT-CS-COPY @ _RTAPT-LD.REGION @
    _RTAPT-CS-COPY @ _RTAPT-LD.PARENT @
    _RTAPT-CS-COPY @ _RTAPT-LD.LEFT @
    _RTAPT-CS-COPY @ _RTAPT-LD.TOP @
    _RTAPT-CS-COPY @ _RTAPT-LD.RIGHT @
    _RTAPT-CS-COPY @ _RTAPT-LD.BOTTOM @
    _RTAPT-CS-COPY @ _RTAPT-LD.Z @
    _RTAPT-CS-COPY @ _RTAPT-LD.VISIBLE @
    _RTAPT-CS-COPY @ _RTAPT-LD.FG-RGBA @ 24 RSHIFT 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.FG-RGBA @ 16 RSHIFT 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.FG-RGBA @ 8 RSHIFT 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.FG-RGBA @ 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.BG-RGBA @ 24 RSHIFT 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.BG-RGBA @ 16 RSHIFT 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.BG-RGBA @ 8 RSHIFT 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.BG-RGBA @ 0xFF AND
    _RTAPT-CS-COPY @ _RTAPT-LD.ATTRS @
    _RTAPT-CS-COPY @ _RTAPT-LD.TEXT-U @ IF
        _RTAPT-CS-COPY @ _RTAPT-LD.TEXT
        _RTAPT-CS-COPY @ _RTAPT-LD.TEXT-U @
    ELSE 0 0 THEN
    _RTAPT-CS-E @ _RTAPT-E.SESSION @
    _RTAPT-CS-REPLACE @ IF
        PT-GLYPH-RUN-REPLACE
    ELSE
        PT-GLYPH-RUN-DEFINE
    THEN _RTAPT-PT>STATUS
    0 _RTAPT-CS-REPLACE ! ;

: _RTAPT-CONTROL-KIND>PT  ( provider-kind -- pt-kind flag )
    DUP RTAPT-CONTROL-MENUBAR = IF
        DROP PT-CONTROL-MENU-BAR -1 EXIT
    THEN
    DUP RTAPT-CONTROL-MENU = IF DROP PT-CONTROL-MENU -1 EXIT THEN
    DUP RTAPT-CONTROL-ITEM = IF DROP PT-CONTROL-MENU-ITEM -1 EXIT THEN
    RTAPT-CONTROL-SEPARATOR = IF
        PT-CONTROL-MENU-SEPARATOR -1 EXIT
    THEN
    0 0 ;

: _RTAPT-CONTROL-STATE>PT  ( provider-state -- pt-state )
    0 SWAP
    DUP RTAPT-CONTROL-F-VISIBLE AND IF
        SWAP PT-CONTROL-VISIBLE OR SWAP
    THEN
    DUP RTAPT-CONTROL-F-ENABLED AND IF
        SWAP PT-CONTROL-ENABLED OR SWAP
    THEN
    DUP RTAPT-CONTROL-F-OPEN AND IF
        SWAP PT-CONTROL-OPEN OR SWAP
    THEN
    DUP RTAPT-CONTROL-F-SELECTED AND IF
        SWAP PT-CONTROL-SELECTED OR SWAP
    THEN
    DUP RTAPT-CONTROL-F-CHECKED AND IF
        SWAP PT-CONTROL-CHECKED OR SWAP
    THEN
    DROP ;

: _RTAPT-SEND-CONTROL  ( replace? -- status )
    _RTAPT-CS-REPLACE !
    _RTAPT-CS-COPY @ _RTAPT-CD.OWNER @
    _RTAPT-CS-COPY @ _RTAPT-CD.GENERATION @
    _RTAPT-CS-COPY @ _RTAPT-CD.CONTROL @
    _RTAPT-CS-COPY @ _RTAPT-CD.KIND @ _RTAPT-CONTROL-KIND>PT 0= IF
        2DROP 2DROP 0 _RTAPT-CS-REPLACE ! RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-CS-COPY @ _RTAPT-CD.STATE @ _RTAPT-CONTROL-STATE>PT
    _RTAPT-CS-COPY @ _RTAPT-CD.Z @
    _RTAPT-CS-COPY @ _RTAPT-CD.REGION @
    _RTAPT-CS-COPY @ _RTAPT-CD.PARENT @
    _RTAPT-CS-COPY @ _RTAPT-CD.ORDER @
    _RTAPT-CS-COPY @ _RTAPT-CD.LEFT @
    _RTAPT-CS-COPY @ _RTAPT-CD.TOP @
    _RTAPT-CS-COPY @ _RTAPT-CD.RIGHT @
    _RTAPT-CS-COPY @ _RTAPT-CD.BOTTOM @
    _RTAPT-CS-COPY @ _RTAPT-CD.LABEL-U @ IF
        _RTAPT-CS-COPY @ _RTAPT-CD.TEXT
        _RTAPT-CS-COPY @ _RTAPT-CD.LABEL-U @
    ELSE 0 0 THEN
    _RTAPT-CS-COPY @ _RTAPT-CD.SHORTCUT-U @ IF
        _RTAPT-CS-COPY @ _RTAPT-CD.TEXT
        _RTAPT-CS-COPY @ _RTAPT-CD.LABEL-U @ +
        _RTAPT-CS-COPY @ _RTAPT-CD.SHORTCUT-U @
    ELSE 0 0 THEN
    _RTAPT-CS-E @ _RTAPT-E.SESSION @
    _RTAPT-CS-REPLACE @ IF PT-CONTROL-REPLACE ELSE PT-CONTROL-DEFINE THEN
        _RTAPT-PT>STATUS
    0 _RTAPT-CS-REPLACE ! ;

: _RTAPT-SEND-CONTROL-DROP  ( -- status )
    _RTAPT-CS-COPY @ _RTAPT-CX.OWNER @
    _RTAPT-CS-COPY @ _RTAPT-CX.GENERATION @
    _RTAPT-CS-COPY @ _RTAPT-CX.CONTROL @
    _RTAPT-CS-E @ _RTAPT-E.SESSION @ PT-CONTROL-DROP _RTAPT-PT>STATUS ;

: _RTAPT-SEND-CAPTURED  ( op-record engine -- status )
    _RTAPT-CS-E ! DUP _RTAPT-CS-P !
    _RTAPT-P.COPY-OFF @ _RTAPT-CS-E @ _RTAPT-E.COPY-A @ +
        _RTAPT-CS-COPY !
    _RTAPT-CS-P @ _RTAPT-P.KIND @ _RTAPT-OP-REGION-DEFINE = IF
        _RTAPT-SEND-REGION EXIT
    THEN
    _RTAPT-CS-P @ _RTAPT-P.KIND @ _RTAPT-OP-GLYPH-RUN-DEFINE = IF
        0 _RTAPT-SEND-GLYPH-RUN EXIT
    THEN
    _RTAPT-CS-P @ _RTAPT-P.KIND @ _RTAPT-OP-GLYPH-RUN-REPLACE = IF
        -1 _RTAPT-SEND-GLYPH-RUN EXIT
    THEN
    _RTAPT-CS-P @ _RTAPT-P.KIND @ _RTAPT-OP-CONTROL-DEFINE = IF
        0 _RTAPT-SEND-CONTROL EXIT
    THEN
    _RTAPT-CS-P @ _RTAPT-P.KIND @ _RTAPT-OP-CONTROL-REPLACE = IF
        -1 _RTAPT-SEND-CONTROL EXIT
    THEN
    _RTAPT-CS-P @ _RTAPT-P.KIND @ _RTAPT-OP-CONTROL-DROP = IF
        _RTAPT-SEND-CONTROL-DROP EXIT
    THEN
    RTAPT-S-INVALID ;

1 CONSTANT _RTAPT-ABORT-SERIALIZATION
VARIABLE _RTAPT-CM-E
VARIABLE _RTAPT-CM-STATUS

: _RTAPT-COMMIT-READY?  ( engine -- flag )
    DUP _RTAPT-ENGINE-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CELL-OPEN <>
        IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> IF DROP 0 EXIT THEN
    DUP _RTAPT-E.ACTIVE-O @
    OVER _RTAPT-E.QUEUE-HEAD @ OR
    OVER _RTAPT-E.QUEUE-TAIL @ OR IF DROP 0 EXIT THEN
    DUP _RTAPT-E.SEND-INDEX @ IF DROP 0 EXIT THEN
    DUP _RTAPT-E.COLS @
    OVER _RTAPT-E.ROWS @
    2 PICK _RTAPT-E.CELL-SPANS @
    3 PICK _RTAPT-E.CELLS @
    4 PICK _RTAPT-E.CELL-MODE @ _RTAPT-CELL-COUNTS? 0= IF DROP 0 EXIT THEN
    DUP _RTAPT-E.RET-MODE @ PT-RET-NONE = IF
        DUP _RTAPT-E.COUPLING @ RTAPT-COUPLING-CELL <> IF DROP 0 EXIT THEN
        DUP _RTAPT-E.CELL-MODE @ _RTAPT-CELL-MODE? 0= IF DROP 0 EXIT THEN
        DUP _RTAPT-E.OP-COUNT @
        OVER _RTAPT-E.COPY-USED @ OR
        OVER _RTAPT-E.RET-BYTES @ OR IF DROP 0 EXIT THEN
        DUP _RTAPT-E.DISPOSITION @ PT-COMMIT <> IF DROP 0 EXIT THEN
    ELSE
        DUP _RTAPT-E.RET-MODE @ _RTAPT-MODE? 0= IF DROP 0 EXIT THEN
        DUP _RTAPT-E.RET-MODE @ OVER _RTAPT-E.DISPOSITION @
            _RTAPT-MODE-DISPOSITION? 0= IF DROP 0 EXIT THEN
        DUP _RTAPT-E.RET-MODE @ PT-RET-DELTA =
        OVER _RTAPT-E.OP-COUNT @ 0= AND IF DROP 0 EXIT THEN
        DUP _RTAPT-E.COUPLING @ RTAPT-COUPLING-CELL = IF
            DUP _RTAPT-E.CELL-MODE @ _RTAPT-CELL-MODE? 0=
                IF DROP 0 EXIT THEN
        ELSE
            DUP _RTAPT-E.COUPLING @ RTAPT-COUPLING-RETAINED <>
                IF DROP 0 EXIT THEN
            DUP _RTAPT-E.CELL-MODE @ PT-CELL-NONE <>
            OVER _RTAPT-E.CELL-SPANS @ OR
            OVER _RTAPT-E.CELLS @ OR IF DROP 0 EXIT THEN
        THEN
    THEN
    DROP -1 ;

: _RTAPT-COMMIT-FAILED  ( original-status engine -- status )
    _RTAPT-CM-E ! _RTAPT-CM-STATUS !
    _RTAPT-ABORT-SERIALIZATION _RTAPT-CM-E @ _RTAPT-ABORT-OPEN
    DUP RTAPT-S-OK <> IF DROP
        RTAPT-S-SESSION-LOST _RTAPT-CM-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN DROP
    _RTAPT-CM-STATUS @ DUP _RTAPT-CM-E @ _RTAPT-E.LAST-STATUS ! ;

: RTAPT-CELL-COMMIT  ( engine -- status )
    DUP _RTAPT-CM-E ! _RTAPT-ENGINE-STORAGE? 0= IF RTAPT-S-INVALID EXIT THEN
    _RTAPT-CM-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-CM-E @ _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    _RTAPT-CM-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CELL-OPEN <>
        IF RTAPT-S-BUSY EXIT THEN
    _RTAPT-CM-E @ _RTAPT-COMMIT-READY? 0= IF
        RTAPT-S-INVALID _RTAPT-CM-E @ _RTAPT-COMMIT-FAILED EXIT
    THEN
    _RTAPT-CM-E @ _RTAPT-E.COLS @
    _RTAPT-CM-E @ _RTAPT-E.ROWS @ _RTAPT-CM-E @
        _RTAPT-PUBLICATION-AUDIT? 0= IF
        RTAPT-S-INVALID _RTAPT-CM-E @ _RTAPT-COMMIT-FAILED EXIT
    THEN
    BEGIN
        _RTAPT-CM-E @ _RTAPT-E.SEND-INDEX @
        _RTAPT-CM-E @ _RTAPT-E.OP-COUNT @ U<
    WHILE
        _RTAPT-CM-E @ _RTAPT-E.SEND-INDEX @ _RTAPT-CM-E @ _RTAPT-OP-NTH
        _RTAPT-CM-E @ _RTAPT-SEND-CAPTURED
        DUP RTAPT-S-OK <> IF
            _RTAPT-CM-E @ _RTAPT-COMMIT-FAILED EXIT
        THEN DROP
        1 _RTAPT-CM-E @ _RTAPT-E.SEND-INDEX +!
    REPEAT
    _RTAPT-CM-E @ _RTAPT-E.DISPOSITION @
        _RTAPT-CM-E @ _RTAPT-E.SESSION @ PT-PRESENT-COMMIT _RTAPT-PT>STATUS
    DUP RTAPT-S-OK <> IF _RTAPT-CM-E @ _RTAPT-COMMIT-FAILED EXIT THEN DROP
    RTAPT-UPDATE-AWAITING _RTAPT-CM-E @ _RTAPT-E.UPDATE-STATE !
    _RTAPT-ACTIVE-OUTPUT _RTAPT-CM-E @ _RTAPT-E.ACTIVE-KIND !
    RTAPT-S-OK DUP _RTAPT-CM-E @ _RTAPT-E.LAST-STATUS ! ;

\ =====================================================================
\  PT lifecycle completion reconciliation
\ =====================================================================

VARIABLE _RTAPT-ST-E
VARIABLE _RTAPT-ST-O
VARIABLE _RTAPT-ST-PT
VARIABLE _RTAPT-ST-HAS
VARIABLE _RTAPT-ST-TOMBSTONE
VARIABLE _RTAPT-ST-STATE

: _RTAPT-LAST-RESULT!  ( wire-status detail revision engine -- )
    >R
    R@ _RTAPT-E.LAST-REVISION !
    R@ _RTAPT-E.LAST-DETAIL !
    R> _RTAPT-E.LAST-WIRE ! ;

: _RTAPT-ACTIVE-CLEAR  ( engine -- )
    DUP _RTAPT-E.ACTIVE-O OFF
    _RTAPT-ACTIVE-NONE SWAP _RTAPT-E.ACTIVE-KIND ! ;

: _RTAPT-OWNER-CLEAR  ( owner-record engine -- )
    >R RTAPT-OWNER-SIZE 0 FILL
    R@ _RTAPT-E.OWNER-USED @ 1- R@ _RTAPT-E.OWNER-USED !
    R> DROP ;

VARIABLE _RTAPT-OT-O
VARIABLE _RTAPT-OT-OWNER
VARIABLE _RTAPT-OT-GENERATION

\ A settled tombstone carries only the exact tuple.  Quota authority and
\ transient queue/result fields are released at the successful drop boundary.
: _RTAPT-OWNER>TOMBSTONE  ( owner-record -- )
    DUP _RTAPT-OT-O !
    DUP _RTAPT-O.OWNER @ _RTAPT-OT-OWNER !
    _RTAPT-O.GENERATION @ _RTAPT-OT-GENERATION !
    _RTAPT-OT-O @ RTAPT-OWNER-SIZE 0 FILL
    _RTAPT-OT-OWNER @ _RTAPT-OT-O @ _RTAPT-O.OWNER !
    _RTAPT-OT-GENERATION @ _RTAPT-OT-O @ _RTAPT-O.GENERATION !
    RTAPT-OWNER-ST-TOMBSTONE _RTAPT-OT-O @ _RTAPT-O.STATE ! ;

\ A newer-generation open candidate does not supersede the terminal's exact
\ tombstone until RET_OK.  Any local admission failure or rejected result
\ restores the prior tuple instead of fabricating a new tombstone.
: _RTAPT-OWNER-RESTORE-TOMBSTONE  ( owner-record -- flag )
    DUP _RTAPT-O.PRIOR-GENERATION @ DUP 0= IF 2DROP 0 EXIT THEN
    _RTAPT-OT-GENERATION !
    DUP _RTAPT-O.OWNER @ _RTAPT-OT-OWNER !
    DUP RTAPT-OWNER-SIZE 0 FILL
    _RTAPT-OT-OWNER @ OVER _RTAPT-O.OWNER !
    _RTAPT-OT-GENERATION @ OVER _RTAPT-O.GENERATION !
    RTAPT-OWNER-ST-TOMBSTONE SWAP _RTAPT-O.STATE ! -1 ;

: _RTAPT-COMPLETION-IDENTITY?  ( expected-kind expected-request owner e -- flag )
    >R
    R@ _RTAPT-E.COMPLETION PT-COMPLETION-OWNER@ =
    R@ _RTAPT-E.COMPLETION PT-COMPLETION-REQUEST@ ROT = AND
    R@ _RTAPT-E.COMPLETION PT-COMPLETION-KIND@ ROT = AND
    R> DROP ;

: _RTAPT-COMPLETION-GENERATION?  ( owner-record engine -- flag )
    >R _RTAPT-O.GENERATION @
    R> _RTAPT-E.COMPLETION PT-COMPLETION-GENERATION@ = ;

: _RTAPT-RECONCILE-OPEN  ( engine -- status )
    DUP _RTAPT-ST-E ! _RTAPT-E.ACTIVE-O @ _RTAPT-ST-O !
    _RTAPT-ST-O @ _RTAPT-O.STATE @ RTAPT-OWNER-ST-TOMBSTONE-OPENING =
        _RTAPT-ST-TOMBSTONE !
    PT-COMPLETE-RET PT-REQUEST-OWNER-OPEN
    _RTAPT-ST-O @ _RTAPT-O.OWNER @ _RTAPT-ST-E @
    _RTAPT-COMPLETION-IDENTITY? 0= IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-O @ _RTAPT-ST-E @ _RTAPT-COMPLETION-GENERATION? 0= IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-STATUS@ DUP
        DUP _RTAPT-ST-PT ! _RTAPT-ST-O @ _RTAPT-O.WIRE-STATUS !
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-DETAIL@
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-REVISION@
    _RTAPT-ST-E @ _RTAPT-LAST-RESULT!
    _RTAPT-ST-PT @ PT-RET-ABORTED = IF
        RTAPT-S-SESSION-LOST _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-ACTIVE-CLEAR
    _RTAPT-ST-PT @ PT-RET-OK = IF
        0 _RTAPT-ST-O @ _RTAPT-O.PRIOR-GENERATION !
        RTAPT-OWNER-ST-OPEN _RTAPT-ST-O @ _RTAPT-O.STATE ! RTAPT-S-OK
    ELSE
        _RTAPT-ST-TOMBSTONE @ IF
            _RTAPT-ST-O @ _RTAPT-OWNER-RESTORE-TOMBSTONE 0= IF
                RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
            THEN
        ELSE _RTAPT-ST-O @ _RTAPT-ST-E @ _RTAPT-OWNER-CLEAR THEN
        RTAPT-S-REJECTED
    THEN ;

: _RTAPT-RECONCILE-DROP  ( engine -- status )
    DUP _RTAPT-ST-E ! _RTAPT-E.ACTIVE-O @ _RTAPT-ST-O !
    _RTAPT-ST-O @ _RTAPT-O.STATE @ RTAPT-OWNER-ST-TOMBSTONE-DROPPING =
        _RTAPT-ST-TOMBSTONE !
    PT-COMPLETE-TX PT-REQUEST-OWNER-DROP
    _RTAPT-ST-O @ _RTAPT-O.OWNER @ _RTAPT-ST-E @
    _RTAPT-COMPLETION-IDENTITY? 0= IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-O @ _RTAPT-ST-E @ _RTAPT-COMPLETION-GENERATION? 0= IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-STATUS@ DUP
        DUP _RTAPT-ST-PT ! _RTAPT-ST-O @ _RTAPT-O.WIRE-STATUS !
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-DETAIL@
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-REVISION@
    _RTAPT-ST-E @ _RTAPT-LAST-RESULT!
    _RTAPT-ST-PT @ PT-TX-RESULT-ABORTED = IF
        \ Crossed-reset replay is deliberately not guessed in this slice.
        RTAPT-S-SESSION-LOST _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-PT @ PT-TX-RESULT-STALE U> IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-ACTIVE-CLEAR
    _RTAPT-ST-PT @ PT-TX-RESULT-OK = IF
        _RTAPT-ST-O @ _RTAPT-OWNER>TOMBSTONE
        RTAPT-S-OK EXIT
    THEN
    _RTAPT-ST-TOMBSTONE @ IF
        _RTAPT-ST-O @ _RTAPT-OWNER>TOMBSTONE
    ELSE RTAPT-OWNER-ST-DROPPING _RTAPT-ST-O @ _RTAPT-O.STATE ! THEN
    RTAPT-S-REJECTED ;

VARIABLE _RTAPT-PR-E
VARIABLE _RTAPT-PR-O
VARIABLE _RTAPT-PR-MODE
VARIABLE _RTAPT-PR-DISPOSITION
VARIABLE _RTAPT-PR-PENDING

: _RTAPT-LIVE-OWNER?  ( owner-record -- flag )
    _RTAPT-O.STATE @ DUP RTAPT-OWNER-ST-OPEN =
    SWAP RTAPT-OWNER-ST-DROPPING = OR ;

: _RTAPT-APPLY-OUTPUT  ( engine -- )
    DUP _RTAPT-PR-E !
    DUP _RTAPT-E.RET-MODE @ _RTAPT-PR-MODE !
    _RTAPT-E.DISPOSITION @ _RTAPT-PR-DISPOSITION !
    \ START establishes its global target base for every live owner before
    \ any staged definitions are applied.  High-water is never rewound.
    _RTAPT-PR-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-PR-E @ _RTAPT-E.OWNERS-A @ I RTAPT-OWNER-SIZE * +
        DUP _RTAPT-PR-O ! _RTAPT-LIVE-OWNER? IF
            _RTAPT-PR-MODE @ PT-RET-REPLACE-START = IF
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-REGIONS !
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-OBJECTS !
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-CONTROLS !
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-UTF8 !
            THEN
            _RTAPT-PR-MODE @ PT-RET-LAYOUT-START = IF
                _RTAPT-PR-O @ _RTAPT-O.ACTIVE-REGIONS @
                    _RTAPT-PR-O @ _RTAPT-O.HIDDEN-REGIONS !
                _RTAPT-PR-O @ _RTAPT-O.ACTIVE-OBJECTS @
                    _RTAPT-PR-O @ _RTAPT-O.HIDDEN-OBJECTS !
                _RTAPT-PR-O @ _RTAPT-O.ACTIVE-CONTROLS @
                    _RTAPT-PR-O @ _RTAPT-O.HIDDEN-CONTROLS !
                _RTAPT-PR-O @ _RTAPT-O.ACTIVE-UTF8 @
                    _RTAPT-PR-O @ _RTAPT-O.HIDDEN-UTF8 !
            THEN
        THEN
    LOOP
    \ Apply every owner's staged additions to the selected committed target.
    _RTAPT-PR-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
        _RTAPT-PR-E @ _RTAPT-E.OWNERS-A @ I RTAPT-OWNER-SIZE * +
        DUP _RTAPT-PR-O ! _RTAPT-LIVE-OWNER? IF
            _RTAPT-PR-O @ _RTAPT-O.PENDING-REGIONS @
                DUP _RTAPT-PR-PENDING ! IF
                _RTAPT-PR-MODE @ PT-RET-DELTA = IF
                    _RTAPT-PR-PENDING @
                        _RTAPT-PR-O @ _RTAPT-O.ACTIVE-REGIONS +!
                ELSE
                    _RTAPT-PR-PENDING @
                        _RTAPT-PR-O @ _RTAPT-O.HIDDEN-REGIONS +!
                THEN
                _RTAPT-PR-O @ _RTAPT-O.PENDING-REGION-HIGH @
                    _RTAPT-PR-O @ _RTAPT-O.REGION-HIGH !
            THEN
            _RTAPT-PR-O @ _RTAPT-O.PENDING-OBJECTS @
                DUP _RTAPT-PR-PENDING ! IF
                _RTAPT-PR-MODE @ PT-RET-DELTA = IF
                    _RTAPT-PR-PENDING @
                        _RTAPT-PR-O @ _RTAPT-O.ACTIVE-OBJECTS +!
                ELSE
                    _RTAPT-PR-PENDING @
                        _RTAPT-PR-O @ _RTAPT-O.HIDDEN-OBJECTS +!
                THEN
                _RTAPT-PR-O @ _RTAPT-O.PENDING-OBJECT-HIGH @
                    _RTAPT-PR-O @ _RTAPT-O.OBJECT-HIGH !
            THEN
            _RTAPT-PR-O @ _RTAPT-O.PENDING-CONTROLS @
                DUP _RTAPT-PR-PENDING ! IF
                _RTAPT-PR-MODE @ PT-RET-DELTA = IF
                    _RTAPT-PR-PENDING @
                        _RTAPT-PR-O @ _RTAPT-O.ACTIVE-CONTROLS +!
                ELSE
                    _RTAPT-PR-PENDING @
                        _RTAPT-PR-O @ _RTAPT-O.HIDDEN-CONTROLS +!
                THEN
                _RTAPT-PR-O @ _RTAPT-O.PENDING-CONTROL-HIGH @
                    _RTAPT-PR-O @ _RTAPT-O.CONTROL-HIGH !
            THEN
            _RTAPT-PR-MODE @ PT-RET-DELTA = IF
                _RTAPT-PR-O @ _RTAPT-O.PENDING-UTF8 @
                    _RTAPT-PR-O @ _RTAPT-O.ACTIVE-UTF8 +!
            ELSE
                _RTAPT-PR-O @ _RTAPT-O.PENDING-UTF8 @
                    _RTAPT-PR-O @ _RTAPT-O.HIDDEN-UTF8 +!
            THEN
            0 _RTAPT-PR-O @ _RTAPT-O.PENDING-REGIONS !
            0 _RTAPT-PR-O @ _RTAPT-O.PENDING-REGION-HIGH !
            0 _RTAPT-PR-O @ _RTAPT-O.PENDING-OBJECTS !
            0 _RTAPT-PR-O @ _RTAPT-O.PENDING-OBJECT-HIGH !
            0 _RTAPT-PR-O @ _RTAPT-O.PENDING-CONTROLS !
            0 _RTAPT-PR-O @ _RTAPT-O.PENDING-CONTROL-HIGH !
            0 _RTAPT-PR-O @ _RTAPT-O.PENDING-UTF8 !
        THEN
    LOOP
    \ A successful reveal is likewise global: every live owner's complete
    \ hidden ledger becomes active and the hidden ledger is retired.
    _RTAPT-PR-DISPOSITION @ PT-COMMIT-AND-REVEAL = IF
        _RTAPT-PR-E @ _RTAPT-E.OWNER-CAP @ 0 ?DO
            _RTAPT-PR-E @ _RTAPT-E.OWNERS-A @ I RTAPT-OWNER-SIZE * +
            DUP _RTAPT-PR-O ! _RTAPT-LIVE-OWNER? IF
                _RTAPT-PR-O @ _RTAPT-O.HIDDEN-REGIONS @
                    _RTAPT-PR-O @ _RTAPT-O.ACTIVE-REGIONS !
                _RTAPT-PR-O @ _RTAPT-O.HIDDEN-OBJECTS @
                    _RTAPT-PR-O @ _RTAPT-O.ACTIVE-OBJECTS !
                _RTAPT-PR-O @ _RTAPT-O.HIDDEN-CONTROLS @
                    _RTAPT-PR-O @ _RTAPT-O.ACTIVE-CONTROLS !
                _RTAPT-PR-O @ _RTAPT-O.HIDDEN-UTF8 @
                    _RTAPT-PR-O @ _RTAPT-O.ACTIVE-UTF8 !
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-REGIONS !
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-OBJECTS !
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-CONTROLS !
                0 _RTAPT-PR-O @ _RTAPT-O.HIDDEN-UTF8 !
            THEN
        LOOP
    THEN ;

: _RTAPT-OUTPUT-COMPLETION?  ( engine -- flag )
    DUP _RTAPT-E.COMPLETION PT-COMPLETION-KIND@ PT-COMPLETE-TX =
    OVER _RTAPT-E.COMPLETION PT-COMPLETION-REQUEST@
        PT-REQUEST-PRESENT-COMMIT = AND
    OVER _RTAPT-E.COMPLETION PT-COMPLETION-TXID@ 0<> AND
    OVER _RTAPT-E.COMPLETION PT-COMPLETION-DETAIL@ 0= AND
    OVER _RTAPT-E.COMPLETION PT-COMPLETION-OWNER@ 0= AND
    OVER _RTAPT-E.COMPLETION PT-COMPLETION-GENERATION@ 0= AND
    OVER _RTAPT-E.COMPLETION PT-COMPLETION-ITEM@ 0= AND
    SWAP _RTAPT-E.COMPLETION PT-COMPLETION-ACCEPTED-BYTES@ 0= AND ;

: _RTAPT-RECONCILE-OUTPUT  ( engine -- status )
    DUP _RTAPT-ST-E ! _RTAPT-OUTPUT-COMPLETION? 0= IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-STATUS@ DUP
        _RTAPT-ST-PT !
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-DETAIL@
    _RTAPT-ST-E @ _RTAPT-E.COMPLETION PT-COMPLETION-REVISION@
    _RTAPT-ST-E @ _RTAPT-LAST-RESULT!
    _RTAPT-ST-PT @ PT-TX-RESULT-STALE U> IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-PT @ PT-TX-RESULT-OK = IF
        _RTAPT-ST-E @ _RTAPT-ACTIVE-CLEAR
        _RTAPT-ST-E @ _RTAPT-APPLY-OUTPUT
        _RTAPT-ST-E @ _RTAPT-CANDIDATE-DISCARD
        RTAPT-S-OK EXIT
    THEN
    _RTAPT-ST-PT @ PT-TX-RESULT-ABORTED = IF
        RTAPT-S-SESSION-LOST _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.COUPLING @ RTAPT-COUPLING-RETAINED = IF
        _RTAPT-ST-E @ _RTAPT-ACTIVE-CLEAR
        _RTAPT-ST-E @ _RTAPT-WIRE-REWIND
        RTAPT-S-REJECTED EXIT
    THEN
    RTAPT-S-SESSION-LOST _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL ;

: _RTAPT-POLL-COMPLETION  ( engine -- status had-completion )
    DUP _RTAPT-ST-E !
    DUP _RTAPT-E.COMPLETION SWAP _RTAPT-E.SESSION @ PT-COMPLETION-POLL
    _RTAPT-ST-HAS ! _RTAPT-PT>STATUS _RTAPT-ST-PT !
    _RTAPT-ST-PT @ RTAPT-S-SESSION-LOST = IF
        RTAPT-S-SESSION-LOST _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL 0 EXIT
    THEN
    _RTAPT-ST-PT @ RTAPT-S-INVALID = IF
        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL 0 EXIT
    THEN
    _RTAPT-ST-PT @ RTAPT-S-OK <> IF _RTAPT-ST-PT @ 0 EXIT THEN
    _RTAPT-ST-HAS @ 0= IF RTAPT-S-OK 0 EXIT THEN
    _RTAPT-ST-E @ _RTAPT-E.ACTIVE-KIND @
    DUP _RTAPT-ACTIVE-OWNER-OPEN = IF
        DROP _RTAPT-ST-E @ _RTAPT-RECONCILE-OPEN -1 EXIT
    THEN
    DUP _RTAPT-ACTIVE-OWNER-DROP = IF
        DROP
        _RTAPT-ST-E @ _RTAPT-RECONCILE-DROP -1 EXIT
    THEN
    _RTAPT-ACTIVE-OUTPUT = IF
        _RTAPT-ST-E @ _RTAPT-RECONCILE-OUTPUT -1 EXIT
    THEN
    RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL -1 ;

: _RTAPT-OWNER-SEND  ( owner-record engine -- status )
    _RTAPT-ST-E ! _RTAPT-ST-O !
    _RTAPT-ST-O @ _RTAPT-O.STATE @ DUP _RTAPT-ST-STATE !
    DUP RTAPT-OWNER-ST-OPEN-QUEUED =
    SWAP RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED = OR IF
        _RTAPT-ST-O @ _RTAPT-O.OWNER @
        _RTAPT-ST-O @ _RTAPT-O.GENERATION @
        _RTAPT-ST-O @ _RTAPT-O.REGIONS @
        _RTAPT-ST-O @ _RTAPT-O.RESOURCES @
        _RTAPT-ST-O @ _RTAPT-O.OBJECTS @
        _RTAPT-ST-O @ _RTAPT-O.SERIES @
        _RTAPT-ST-O @ _RTAPT-O.RES-BYTES @
        _RTAPT-ST-O @ _RTAPT-O.UTF8-BYTES @
        _RTAPT-ST-O @ _RTAPT-O.SAMPLES @
        _RTAPT-ST-E @ _RTAPT-E.SESSION @ PT-OWNER-OPEN _RTAPT-PT>STATUS
        DUP RTAPT-S-OK = IF
            DROP
            _RTAPT-ST-STATE @ RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED = IF
                RTAPT-OWNER-ST-TOMBSTONE-OPENING
            ELSE RTAPT-OWNER-ST-OPENING THEN
            _RTAPT-ST-O @ _RTAPT-O.STATE !
            _RTAPT-ST-O @ _RTAPT-ST-E @ _RTAPT-E.ACTIVE-O !
            _RTAPT-ACTIVE-OWNER-OPEN _RTAPT-ST-E @ _RTAPT-E.ACTIVE-KIND !
            RTAPT-S-OK
        THEN EXIT
    THEN
    _RTAPT-ST-O @ _RTAPT-O.STATE @ DUP _RTAPT-ST-STATE !
    DUP RTAPT-OWNER-ST-DROP-QUEUED =
    OVER RTAPT-OWNER-ST-DROP-RETRY-QUEUED = OR
    SWAP RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED = OR 0= IF
        RTAPT-S-INVALID EXIT
    THEN
    _RTAPT-ST-O @ _RTAPT-O.OWNER @
    _RTAPT-ST-O @ _RTAPT-O.GENERATION @
    _RTAPT-ST-E @ _RTAPT-E.SESSION @ PT-OWNER-DROP _RTAPT-PT>STATUS
    DUP RTAPT-S-OK = IF
        DROP
        _RTAPT-ST-STATE @ RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED = IF
            RTAPT-OWNER-ST-TOMBSTONE-DROPPING
        ELSE _RTAPT-ST-STATE @ RTAPT-OWNER-ST-DROP-RETRY-QUEUED = IF
            RTAPT-OWNER-ST-DROP-RETRY-DROPPING
        ELSE RTAPT-OWNER-ST-DROPPING THEN THEN
        _RTAPT-ST-O @ _RTAPT-O.STATE !
        _RTAPT-ST-O @ _RTAPT-ST-E @ _RTAPT-E.ACTIVE-O !
        _RTAPT-ACTIVE-OWNER-DROP _RTAPT-ST-E @ _RTAPT-E.ACTIVE-KIND !
        RTAPT-S-OK
    THEN ;

: _RTAPT-OWNER-ADMISSION-FAILED  ( owner-record engine -- flag )
    >R
    DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-OPEN-QUEUED = IF
        R> _RTAPT-OWNER-CLEAR -1 EXIT
    THEN
    DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED = IF
        _RTAPT-OWNER-RESTORE-TOMBSTONE R> DROP EXIT
    THEN
    DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-DROP-QUEUED = IF
        RTAPT-OWNER-ST-OPEN SWAP _RTAPT-O.STATE ! R> DROP -1 EXIT
    THEN
    DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-DROP-RETRY-QUEUED = IF
        RTAPT-OWNER-ST-DROPPING SWAP _RTAPT-O.STATE ! R> DROP -1 EXIT
    THEN
    DUP _RTAPT-O.STATE @ RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED = IF
        RTAPT-OWNER-ST-TOMBSTONE SWAP _RTAPT-O.STATE ! R> DROP -1 EXIT
    THEN
    DROP R> DROP 0 ;

\ RTAPT-STEP performs at most one completion reconciliation or one lifecycle
\ publication.  It never calls PT-SERVICE and cannot consume input events.
: RTAPT-STEP  ( engine -- status )
    DUP _RTAPT-ENGINE-VALID? 0= IF DROP RTAPT-S-INVALID EXIT THEN
    \ This store consumes ENGINE: retaining it below STATUS would leak one
    \ data-stack cell through every terminal-service turn.
    _RTAPT-ST-E !
    _RTAPT-ST-E @ _RTAPT-E.ACTIVE-KIND @
        _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS @ EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE <> IF
        \ PT-COMPLETION-POLL has no completion to return after a synchronized
        \ close.  Detect that boundary here so an unconsumed output cannot
        \ remain WOULD_BLOCK forever while shutdown waits on this engine.
        _RTAPT-ST-E @ _RTAPT-SESSION-ENDED? IF
            RTAPT-S-SESSION-LOST _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL EXIT
        THEN
        _RTAPT-ST-E @ _RTAPT-POLL-COMPLETION
        IF DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! EXIT THEN
        DUP RTAPT-S-OK <> IF
            DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! EXIT
        THEN DROP
        RTAPT-S-WOULD-BLOCK DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-READY-STATUS DUP RTAPT-S-OK <> IF
        DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN DROP
    _RTAPT-ST-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-CELL-OPEN = IF
        RTAPT-S-BUSY DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.UPDATE-STATE @ RTAPT-UPDATE-IDLE <> IF
        \ CAPTURING and SEALED are caller-owned candidates.  STEP never
        \ promotes either one to a retained-only publication implicitly.
        RTAPT-S-OK DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.QUEUE-HEAD @ 0= IF
        RTAPT-S-OK DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! EXIT
    THEN
    _RTAPT-ST-E @ _RTAPT-E.QUEUE-HEAD @ DUP 0= IF
        DROP RTAPT-S-INVALID
    ELSE
        DUP _RTAPT-ST-O ! _RTAPT-ST-E @ _RTAPT-OWNER-SEND
        DUP RTAPT-S-WOULD-BLOCK <> IF
            DUP _RTAPT-ST-PT !
            _RTAPT-ST-E @ _RTAPT-QUEUE-POP
            _RTAPT-ST-O @ <> IF
                DROP RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL
            ELSE
                DROP
                _RTAPT-ST-PT @ RTAPT-S-OK <> IF
                    _RTAPT-ST-O @ _RTAPT-ST-E @
                    _RTAPT-OWNER-ADMISSION-FAILED 0= IF
                        RTAPT-S-INVALID _RTAPT-ST-E @ _RTAPT-QUARANTINE-ALL
                    ELSE _RTAPT-ST-PT @ RTAPT-S-SESSION-LOST = IF
                        RTAPT-S-SESSION-LOST _RTAPT-ST-E @
                            _RTAPT-QUARANTINE-ALL
                    ELSE _RTAPT-ST-PT @ THEN THEN
                ELSE RTAPT-S-OK THEN
            THEN
        THEN
    THEN
    DUP _RTAPT-ST-E @ _RTAPT-E.LAST-STATUS ! ;

VARIABLE _RTAPT-SE-E

\ RTAPT-SETTLE ( engine -- status pending? )
\   Reconcile only an already-admitted owner/output completion.  Local rich
\ candidates, an open CELL transaction, and queued lifecycle requests carry
\ no emitted-result authority and neither block nor become published here.
\ This operation never services PT and never starts ordinary queue work.
: RTAPT-SETTLE  ( engine -- status pending? )
    DUP _RTAPT-SE-E ! _RTAPT-ENGINE-VALID? 0= IF
        RTAPT-S-INVALID 0 EXIT
    THEN
    _RTAPT-SE-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-QUARANTINED = IF
        _RTAPT-SE-E @ _RTAPT-E.LAST-STATUS @ 0 EXIT
    THEN
    _RTAPT-SE-E @ _RTAPT-SESSION-ENDED? IF
        RTAPT-S-SESSION-LOST _RTAPT-SE-E @ _RTAPT-QUARANTINE-ALL 0 EXIT
    THEN
    _RTAPT-SE-E @ _RTAPT-E.ACTIVE-KIND @ _RTAPT-ACTIVE-NONE = IF
        RTAPT-S-OK 0 EXIT
    THEN
    _RTAPT-SE-E @ _RTAPT-POLL-COMPLETION IF
        DUP _RTAPT-SE-E @ _RTAPT-E.LAST-STATUS ! 0 EXIT
    THEN
    DUP RTAPT-S-OK <> IF
        DUP _RTAPT-SE-E @ _RTAPT-E.LAST-STATUS ! 0 EXIT
    THEN DROP
    RTAPT-S-WOULD-BLOCK DUP _RTAPT-SE-E @ _RTAPT-E.LAST-STATUS ! -1 ;
