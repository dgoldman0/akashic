\ =====================================================================
\  akashic/tui/uidl-tui.f — UIDL TUI Backend
\ =====================================================================
\
\  The TUI rendering backend for UIDL.  Installs real render-xt,
\  event-xt, and layout-xt implementations into the Element Registry,
\  then provides focus management, hit-testing, dirty-rect repaint,
\  action dispatch, shortcut registration, and the subscription-
\  driven reactive loop.  Operates directly on the UIDL element
\  tree with no DOM intermediary.
\
\  Public API (all UTUI- prefixed):
\    UTUI-LOAD        ( xml-a xml-u rgn -- flag )
\    UTUI-BIND-STATE  ( st -- )
\    UTUI-PAINT       ( -- )
\    UTUI-RELAYOUT    ( -- )
\    UTUI-DISPATCH-KEY   ( ev -- handled? )
\    UTUI-DISPATCH-MOUSE ( row col btn -- handled? )
\    UTUI-FOCUS       ( -- elem | 0 )
\    UTUI-FOCUS!      ( elem -- )
\    UTUI-FOCUS-NEXT  ( -- )
\    UTUI-FOCUS-PREV  ( -- )
\    UTUI-BY-ID       ( id-a id-l -- elem | 0 )
\    UTUI-DO!         ( do-a do-l xt -- )
\    UTUI-SHOW-DIALOG ( id-a id-l -- )
\    UTUI-HIDE-DIALOG ( id-a id-l -- )
\    UTUI-HIT-TEST    ( row col -- elem | 0 )
\    UTUI-VISIBLE!    ( visible -- )
\    UTUI-QUIESCE     ( -- status )
\    UTUI-DETACH      ( -- )
\    UTUI-RESOLVED-BYTES  ( -- bytes )
\    UTUI-ELEM-RESOLVED-STATE@  ( elem -- effective-visible status )
\    UTUI-ELEM-RESOLVED-CAPTURE ( elem destination available
\                                      -- effective-visible status )
\    UTUI-RESOLVED-VALID?  ( record available -- flag )
\    UTUI-RESOLVED-OBSERVE ( i*x xt -- j*x )
\    UTUI-RESOLVED-TREE-EACH ( visitor-xt -- status )
\      visitor-xt ( elem source-index sibling-ordinal local-visible
\                   effective-visible resolved available -- )
\    UTUI-STORAGE-DISJOINT?    ( address length -- flag )
\
\  Prefix: UTUI- (public), _UTUI- (internal)
\  Provider: akashic-tui-uidl-tui
\
\  Dependencies:
\    REQUIRE liraq/uidl.f
\    REQUIRE liraq/uidl-semantic.f
\    REQUIRE liraq/uidl-chrome.f
\    REQUIRE liraq/state-tree.f
\    REQUIRE liraq/lel.f
\    REQUIRE tui/screen.f
\    REQUIRE tui/draw.f
\    REQUIRE tui/box.f
\    REQUIRE tui/region.f
\    REQUIRE tui/layout.f
\    REQUIRE tui/keys.f

PROVIDED akashic-tui-uidl-tui

REQUIRE ../liraq/uidl.f
REQUIRE ../liraq/uidl-semantic.f
REQUIRE ../liraq/uidl-chrome.f
REQUIRE ../liraq/state-tree.f
REQUIRE ../liraq/lel.f
REQUIRE screen.f
REQUIRE tui-sidecar.f
REQUIRE box.f
REQUIRE region.f
REQUIRE layout.f
REQUIRE keys.f
REQUIRE widgets/tree.f
REQUIRE widgets/input.f
REQUIRE widgets/list.f
REQUIRE widgets/textarea.f
REQUIRE widgets/dialog.f
REQUIRE ../css/css.f
REQUIRE color.f

\ =====================================================================
\  §1 — TUI Sidecar (shared layout from tui-sidecar.f)
\ =====================================================================
\
\  Parallel array indexed by element pool index:
\    elem-index = (elem – _UDL-ELEMS) / _UDL-ELEMSZ
\    sidecar    = elem-index × TSC-SIZE + _UTUI-SIDECARS
\
\  Uses the unified TSC record (96 bytes = 12 cells).
\  See tui-sidecar.f for full field map.
\
\  UIDL-specific field mapping:
\    AUX1 (+48)  = wptr       Widget struct pointer
\    AUX2 (+56)  = padding    Packed TRBL
\    AUX3 (+64)  = offsets    4×16-bit signed
\    AUX4 (+72)  = margin     Packed TRBL
\    AUX5 (+80)  = wowner     0 = UIDL-owned, 1 = caller-owned
\    AUX6 (+88)  = runtime    UIDL-TUI runtime visibility state

TSC-SIZE CONSTANT _UTUI-SC-SZ
256 CONSTANT _UTUI-MAX-ELEMS
CREATE _UTUI-SIDECARS  _UTUI-MAX-ELEMS _UTUI-SC-SZ * ALLOT

\ Sidecar field offset aliases (all delegate to TSC-O-*)
TSC-O-ROW   CONSTANT _UTUI-SC-O-ROW
TSC-O-COL   CONSTANT _UTUI-SC-O-COL
TSC-O-W     CONSTANT _UTUI-SC-O-W
TSC-O-H     CONSTANT _UTUI-SC-O-H
TSC-O-STYLE CONSTANT _UTUI-SC-O-STYLE
TSC-O-FLAGS CONSTANT _UTUI-SC-O-FLAGS
TSC-O-AUX1  CONSTANT _UTUI-SC-O-WPTR
TSC-O-AUX2  CONSTANT _UTUI-SC-O-PAD
TSC-O-AUX3  CONSTANT _UTUI-SC-O-OFFS
TSC-O-AUX4  CONSTANT _UTUI-SC-O-MARGIN
TSC-O-AUX5  CONSTANT _UTUI-SC-O-WOWNER
TSC-O-AUX6  CONSTANT _UTUI-SC-O-RUNTIME

0 CONSTANT _UTUI-WOWNER-UIDL
1 CONSTANT _UTUI-WOWNER-CALLER

\ Sidecar flag aliases (all delegate to TSC-F-*)
TSC-F-HAS       CONSTANT _UTUI-SCF-HAS
TSC-F-VISIBLE   CONSTANT _UTUI-SCF-VIS
TSC-F-FOCUSABLE CONSTANT _UTUI-SCF-FOC
TSC-F-HIDE      CONSTANT _UTUI-SCF-HIDE

1 CONSTANT _UTUI-RUNTIME-F-HIDDEN

\ Layout owns HAS/VIS but must not erase durable style/focus state while it
\ assigns a child's rectangle.  Runtime show/hide lives in AUX6 and therefore
\ remains independent of both CSS display:none and the packed flag word.
_UTUI-SCF-FOC TSC-F-HIDDEN OR _UTUI-SCF-HIDE OR
    CONSTANT _UTUI-SCF-DURABLE

\ =====================================================================
\  §1a — Element → Sidecar mapping
\ =====================================================================

VARIABLE _UTUI-ELEM-BASE   \ set at load time to _UDL-ELEMS

: _UTUI-SC-IDX  ( elem -- idx )
    _UTUI-ELEM-BASE @ -  _UDL-ELEMSZ / ;

: _UTUI-SIDECAR  ( elem -- sc )
    _UTUI-SC-IDX _UTUI-SC-SZ * _UTUI-SIDECARS + ;

\ Field accessors (thin wrappers on TSC-*)
: _UTUI-SC-ROW@   ( sc -- n ) TSC-ROW@ ;
: _UTUI-SC-COL@   ( sc -- n ) TSC-COL@ ;
: _UTUI-SC-W@     ( sc -- n ) TSC-W@ ;
: _UTUI-SC-H@     ( sc -- n ) TSC-H@ ;
: _UTUI-SC-STYLE@ ( sc -- s ) TSC-STYLE@ ;
: _UTUI-SC-FLAGS@ ( sc -- f ) TSC-FLAGS@ ;

: _UTUI-SC-ROW!   ( n sc -- ) TSC-ROW! ;
: _UTUI-SC-COL!   ( n sc -- ) TSC-COL! ;
: _UTUI-SC-W!     ( n sc -- ) TSC-W! ;
: _UTUI-SC-H!     ( n sc -- ) TSC-H! ;
: _UTUI-SC-STYLE! ( s sc -- ) TSC-STYLE! ;
: _UTUI-SC-FLAGS! ( f sc -- ) TSC-FLAGS! ;
: _UTUI-SC-WPTR@  ( sc -- p ) TSC-AUX1@ ;
: _UTUI-SC-WPTR!  ( p sc -- ) TSC-AUX1! ;
: _UTUI-SC-WOWNER@ ( sc -- n ) _UTUI-SC-O-WOWNER + @ ;
: _UTUI-SC-WOWNER! ( n sc -- ) _UTUI-SC-O-WOWNER + ! ;
: _UTUI-SC-RUNTIME@ ( sc -- n ) _UTUI-SC-O-RUNTIME + @ ;
: _UTUI-SC-RUNTIME! ( n sc -- ) _UTUI-SC-O-RUNTIME + ! ;

: _UTUI-SC-LAYOUT-FLAGS!  ( layout-flags sc -- )
    DUP _UTUI-SC-FLAGS@ _UTUI-SCF-DURABLE AND
    ROT OR SWAP _UTUI-SC-FLAGS! ;

\ Padding, offsets, margin accessors (via TSC AUX slots)
: _UTUI-SC-PAD@    ( sc -- n ) TSC-AUX2@ ;
: _UTUI-SC-PAD!    ( n sc -- ) TSC-AUX2! ;
: _UTUI-SC-OFFS@   ( sc -- n ) TSC-AUX3@ ;
: _UTUI-SC-OFFS!   ( n sc -- ) TSC-AUX3! ;
: _UTUI-SC-MARGIN@ ( sc -- n ) TSC-AUX4@ ;
: _UTUI-SC-MARGIN! ( n sc -- ) TSC-AUX4! ;

\ Visibility predicate — delegates to TSC-VIS?
: _UTUI-SC-VIS?  ( sc -- flag )
    DUP TSC-VIS?
    SWAP _UTUI-SC-RUNTIME@ _UTUI-RUNTIME-F-HIDDEN AND 0= AND ;

\ Style-field extended accessors (delegates to TSC-UNPACK-*)
: _UTUI-SC-TALIGN@ ( sc -- align )
    TSC-STYLE@ TSC-UNPACK-TALIGN ;
: _UTUI-SC-POS@    ( sc -- pos )
    TSC-STYLE@ TSC-UNPACK-POS ;
: _UTUI-SC-ZIDX@   ( sc -- z )
    TSC-STYLE@ TSC-UNPACK-ZIDX ;

\ TRBL pack/unpack (delegated to tui-sidecar.f)
: _UTUI-PACK-TRBL   ( t r b l -- packed )  TSC-PACK-TRBL ;
: _UTUI-UNPACK-TRBL ( packed -- t r b l )  TSC-UNPACK-TRBL ;

\ Offset pack/unpack (delegated to tui-sidecar.f)
: _UTUI-PACK-OFFS   ( top right bottom left -- packed )  TSC-PACK-OFFS ;
: _UTUI-SEXT16      ( u16 -- signed )  TSC-SEXT16 ;
: _UTUI-UNPACK-OFFS ( packed -- top right bottom left )  TSC-UNPACK-OFFS ;

\ Unpack style → fg bg attrs (delegated to TSC)
: _UTUI-UNPACK-STYLE  ( style -- fg bg attrs )
    DUP TSC-UNPACK-FG
    OVER TSC-UNPACK-BG
    ROT TSC-UNPACK-ATTRS ;

\ Pack fg bg attrs → style (delegated to TSC)
: _UTUI-PACK-STYLE  ( fg bg attrs -- style )
    TSC-PACK-STYLE ;

\ Apply sidecar style to draw engine; add reverse-video when focused.
\ Suppress focus highlight when element has a mounted widget — the
\ widget renders its own selection/focus indicator internally.
: _UTUI-APPLY-STYLE  ( sc -- )
    DUP TSC-FLAGS@ _UTUI-SCF-FOC AND 0<>
    OVER _UTUI-SC-WPTR@ IF DROP 0 THEN     \ widget → no UIDL focus chrome
    TSC-APPLY-STYLE-FOC ;

\ Clear all sidecars
: _UTUI-SC-CLEAR-ALL  ( -- )
    _UTUI-SIDECARS _UTUI-MAX-ELEMS _UTUI-SC-SZ * 0 FILL ;

\ Public style readers — extract fg/bg/attrs from an element's resolved
\ sidecar style.  These are available after UTUI-LOAD returns.
: UTUI-SC-FG@    ( elem -- fg )    _UTUI-SIDECAR TSC-STYLE@ TSC-UNPACK-FG ;
: UTUI-SC-BG@    ( elem -- bg )    _UTUI-SIDECAR TSC-STYLE@ TSC-UNPACK-BG ;
: UTUI-SC-ATTRS@ ( elem -- attrs ) _UTUI-SIDECAR TSC-STYLE@ TSC-UNPACK-ATTRS ;

\ Public geometry reader — returns element's layout rectangle.
: UTUI-ELEM-RGN  ( elem -- row col h w )
    _UTUI-SIDECAR >R
    R@ _UTUI-SC-ROW@
    R@ _UTUI-SC-COL@
    R@ _UTUI-SC-H@
    R> _UTUI-SC-W@ ;

\ =====================================================================
\  §1b — Renderer-neutral resolved projection record
\ =====================================================================
\
\ Optional projections receive an explicit copy of resolved geometry and
\ style.  No sidecar address and no packed TSC word crosses this seam.

0 CONSTANT UTUI-RESOLVED-S-OK
1 CONSTANT UTUI-RESOLVED-S-UNAVAILABLE
2 CONSTANT UTUI-RESOLVED-S-INVALID

: UTUI-RESOLVED-STATUS-VALID?  ( status -- flag )  3 U< ;

: _UTUI-RS.ROW    ( record -- address )       ;
: _UTUI-RS.COL    ( record -- address )   8 + ;
: _UTUI-RS.H      ( record -- address )  16 + ;
: _UTUI-RS.W      ( record -- address )  24 + ;
: _UTUI-RS.FG     ( record -- address )  32 + ;
: _UTUI-RS.BG     ( record -- address )  40 + ;
: _UTUI-RS.ATTRS  ( record -- address )  48 + ;
: _UTUI-RS.ALIGN  ( record -- address )  56 + ;
: _UTUI-RS.Z      ( record -- address )  64 + ;

72 CONSTANT UTUI-RESOLVED-SIZE

: UTUI-RESOLVED-BYTES  ( -- bytes )  UTUI-RESOLVED-SIZE ;

\ =====================================================================
\  §1c — Dynamic Sidecar Helpers
\ =====================================================================

\ _UTUI-SC-ALLOC ( elem -- )
\   Zero-fill the sidecar for elem and set the HAS flag.
\   The sidecar pool is pre-allocated to _UTUI-MAX-ELEMS, matching
\   the element pool size, so no growth is needed.
: _UTUI-SC-ALLOC  ( elem -- )
    _UTUI-SIDECAR
    DUP TSC-CLEAR
    _UTUI-SCF-HAS OVER TSC-FLAGS@ OR SWAP TSC-FLAGS! ;

\ _UTUI-SC-FREE ( elem -- )
\   Zero-fill the sidecar, clearing the HAS flag.
: _UTUI-SC-FREE  ( elem -- )
    _UTUI-SIDECAR TSC-CLEAR ;

\ Default style: light gray on dark gray, no attrs
253 236 0 _UTUI-PACK-STYLE CONSTANT _UTUI-DEFAULT-STYLE

\ Mask for CSS-inheritable properties:
\   fg(0-7), bg(8-15), attrs(16-31), text-align(32-33)
\ Non-inheritable (position 34-35, z-index 36-43, border 44-51) excluded.
0x3FFFFFFFF CONSTANT _UTUI-INHERIT-MASK

\ _UTUI-INHERIT-PARENT-STYLE ( elem -- )
\   Seed this element's sidecar with parent's inheritable style bits.
: _UTUI-INHERIT-PARENT-STYLE  ( elem -- )
    DUP UIDL-PARENT ?DUP IF
        _UTUI-SIDECAR _UTUI-SC-STYLE@
        _UTUI-INHERIT-MASK AND         ( elem inherit )
        SWAP _UTUI-SIDECAR             ( inherit sc )
        DUP _UTUI-SC-STYLE@            ( inherit sc cstyle )
        _UTUI-INHERIT-MASK INVERT AND  ( inherit sc non-inh )
        ROT OR SWAP _UTUI-SC-STYLE!
    ELSE
        \ No parent — seed with default style
        _UTUI-DEFAULT-STYLE SWAP _UTUI-SIDECAR _UTUI-SC-STYLE!
    THEN ;

\ _UTUI-MATERIALIZE-ONE ( elem -- )
\   Materialize a single element if it's a widget type.
\   (forward reference — defined after _UTUI-MAT-* helpers exist)
DEFER _UTUI-MATERIALIZE-ONE

\ _UTUI-DEMATERIALIZE-ONE ( elem -- )
\   Free the widget (if any) attached to a single element.
\   (forward reference — defined after type constants are available)
DEFER _UTUI-DEMATERIALIZE-ONE

\ =====================================================================
\  §1c — Proxy Region (shared by all materialized widgets)
\ =====================================================================
\
\  A single static region (40 bytes) synced from the current sidecar
\  before each widget _*-DRAW or _*-HANDLE call.  Safe because the
\  TUI is single-threaded.

VARIABLE _UTUI-RGN        \ root region; proxy helpers compile this address
CREATE _UTUI-PROXY-RGN  _RGN-DESC-SIZE ALLOT

: _UTUI-SYNC-PROXY  ( sc -- )
    DUP _UTUI-SC-ROW@ _UTUI-PROXY-RGN _RGN-O-ROW + !
    DUP _UTUI-SC-COL@ _UTUI-PROXY-RGN _RGN-O-COL + !
    DUP _UTUI-SC-H@   _UTUI-PROXY-RGN _RGN-O-H   + !
        _UTUI-SC-W@   _UTUI-PROXY-RGN _RGN-O-W   + !
    _UTUI-RGN @ _UTUI-PROXY-RGN _RGN-O-PARENT + ! ;

\ =====================================================================
\  §1d — UIDL ↔ Widget Callbacks
\ =====================================================================
\
\  Tree walk callbacks — UIDL element tokens serve as tree node tokens.

: _UTUI-TREE-CHILD  ( node -- child | 0 )  UIDL-FIRST-CHILD ;
: _UTUI-TREE-NEXT   ( node -- sib  | 0 )  UIDL-NEXT-SIB ;
: _UTUI-TREE-LABEL  ( node -- a l )
    DUP S" label" UIDL-ATTR IF ROT DROP EXIT THEN
    2DROP S" text" UIDL-ATTR IF EXIT THEN
    2DROP S" ?" ;
: _UTUI-TREE-LEAF?  ( node -- flag )  UIDL-FIRST-CHILD 0= ;

\ =====================================================================
\  §1d — Render / Event Helpers
\ =====================================================================

\ --- Shared temp vars for render/layout (KDOS pattern) ---
\ (Must be declared before _UTUI-PROXY-FROM-UR which references them.)
VARIABLE _UR-ROW   VARIABLE _UR-COL
VARIABLE _UR-W     VARIABLE _UR-H
VARIABLE _UR-ABS-ROW VARIABLE _UR-ABS-COL
VARIABLE _UR-TMP   VARIABLE _UR-ELEM
VARIABLE _UR-EV    \ saved event pointer

\ Write _UR-* temp vars into the shared proxy region.
: _UTUI-PROXY-FROM-UR  ( -- )
    _UR-ABS-ROW @ _UTUI-PROXY-RGN _RGN-O-ROW + !
    _UR-ABS-COL @ _UTUI-PROXY-RGN _RGN-O-COL + !
    _UR-H @   _UTUI-PROXY-RGN _RGN-O-H   + !
    _UR-W @   _UTUI-PROXY-RGN _RGN-O-W   + !
    _UTUI-RGN @ _UTUI-PROXY-RGN _RGN-O-PARENT + ! ;

\ Sync sidecar focus state into a widget's WDG-F-FOCUSED flag.
: _UTUI-SYNC-WFOCUS  ( sc wptr -- )
    >R
    _UTUI-SC-FLAGS@ _UTUI-SCF-FOC AND
    R@ _WDG-O-FLAGS + @
    WDG-F-FOCUSED INVERT AND
    SWAP IF WDG-F-FOCUSED OR THEN
    R> _WDG-O-FLAGS + ! ;

\ Temp var for materialization.
VARIABLE _UTUI-MAT-W

\ =====================================================================
\  §2 — Global State
\ =====================================================================

VARIABLE _UTUI-DOC-LOADED \ flag: document loaded?
VARIABLE _UTUI-STATE      \ bound state-tree
VARIABLE _UTUI-FOCUS-P    \ currently focused element (0 = none)
VARIABLE _UTUI-NEEDS-PAINT \ global: any UIDL/widget change needs repaint

\ Optional derived-projection state.  UIDL owns this lifecycle; applications
\ see neither a renderer nor a provider-specific scene service.  Composition
\ installs one immutable adapter table and attaches it only after UTUI-LOAD has
\ produced a coherent document.  The call-borrowed document binding is
\ consumed synchronously; only the adapter-issued token is stored in the
\ active UCTX.
0 CONSTANT _UTUI-PROJ-S-OK
2 CONSTANT _UTUI-PROJ-S-UNAVAILABLE
4 CONSTANT _UTUI-PROJ-S-STALE
5 CONSTANT _UTUI-PROJ-S-INVALID

VARIABLE _UTUI-PROJ-TOKEN
VARIABLE _UTUI-PROJ-STATUS
VARIABLE _UTUI-VISIBLE
VARIABLE _UTUI-PROJ-ATTACHED
VARIABLE _UTUI-QUIESCING
VARIABLE _UTUI-QUIESCED

\ Projection-adapter callback table (installed atomically and immutable
\ thereafter):
\   attach-xt   ( document-binding context -- token status )
\   project-xt  ( token context -- status )
\   relayout-xt ( visible region token context -- status )
\   quiesce-xt  ( token context -- status )
\   detach-xt   ( token context -- status )
\ All callbacks run synchronously on the UI owner with the exact UCTX active.
\ CONTEXT is immutable composition authority and deliberately does not enter a
\ UCTX; only the opaque token and lifecycle scalars are context-local.
VARIABLE _UTUI-PROJ-ADAPTER-CONTEXT
VARIABLE _UTUI-PROJ-ATTACH-XT
VARIABLE _UTUI-PROJ-PROJECT-XT
VARIABLE _UTUI-PROJ-RELAYOUT-XT
VARIABLE _UTUI-PROJ-QUIESCE-XT
VARIABLE _UTUI-PROJ-DETACH-XT
VARIABLE _UTUI-PROJ-ADAPTER-INSTALLED
VARIABLE _UTUI-PROJ-CALLING

0 _UTUI-RGN !
0 _UTUI-DOC-LOADED !
0 _UTUI-STATE !
0 _UTUI-FOCUS-P !
0 _UTUI-NEEDS-PAINT !
0 _UTUI-PROJ-TOKEN !
0 _UTUI-PROJ-STATUS !
0 _UTUI-VISIBLE !
0 _UTUI-PROJ-ATTACHED !
0 _UTUI-QUIESCING !
0 _UTUI-QUIESCED !
0 _UTUI-PROJ-ADAPTER-CONTEXT !
0 _UTUI-PROJ-ATTACH-XT !
0 _UTUI-PROJ-PROJECT-XT !
0 _UTUI-PROJ-RELAYOUT-XT !
0 _UTUI-PROJ-QUIESCE-XT !
0 _UTUI-PROJ-DETACH-XT !
0 _UTUI-PROJ-ADAPTER-INSTALLED !
0 _UTUI-PROJ-CALLING !

VARIABLE _UTUI-PAI-ATTACH
VARIABLE _UTUI-PAI-PROJECT
VARIABLE _UTUI-PAI-RELAYOUT
VARIABLE _UTUI-PAI-QUIESCE
VARIABLE _UTUI-PAI-DETACH
VARIABLE _UTUI-PAI-CONTEXT

\ _UTUI-PROJECTION-ADAPTER!
\   ( context attach project relayout quiesce detach -- flag )
\ Composition-only, one-way installation.  An exact repeated installation is
\ idempotent; a partial or different adapter is refused without mutation.
: _UTUI-PROJECTION-ADAPTER!
    ( context attach project relayout quiesce detach -- flag )
    _UTUI-PAI-DETACH !
    _UTUI-PAI-QUIESCE !
    _UTUI-PAI-RELAYOUT !
    _UTUI-PAI-PROJECT !
    _UTUI-PAI-ATTACH !
    _UTUI-PAI-CONTEXT !
    _UTUI-PROJ-ADAPTER-INSTALLED @ IF
        _UTUI-PROJ-ADAPTER-CONTEXT @ _UTUI-PAI-CONTEXT @ =
        _UTUI-PROJ-ATTACH-XT  @ _UTUI-PAI-ATTACH  @ = AND
        _UTUI-PROJ-PROJECT-XT @ _UTUI-PAI-PROJECT @ = AND
        _UTUI-PROJ-RELAYOUT-XT @ _UTUI-PAI-RELAYOUT @ = AND
        _UTUI-PROJ-QUIESCE-XT @ _UTUI-PAI-QUIESCE @ = AND
        _UTUI-PROJ-DETACH-XT  @ _UTUI-PAI-DETACH  @ = AND
        EXIT
    THEN
    _UTUI-PAI-CONTEXT @ 0<>
    _UTUI-PAI-ATTACH @ 0<> AND
    _UTUI-PAI-PROJECT @ 0<> AND
    _UTUI-PAI-RELAYOUT @ 0<> AND
    _UTUI-PAI-QUIESCE @ 0<> AND
    _UTUI-PAI-DETACH @ 0<> AND 0= IF 0 EXIT THEN
    _UTUI-PAI-CONTEXT @ _UTUI-PROJ-ADAPTER-CONTEXT !
    _UTUI-PAI-ATTACH  @ _UTUI-PROJ-ATTACH-XT !
    _UTUI-PAI-PROJECT @ _UTUI-PROJ-PROJECT-XT !
    _UTUI-PAI-RELAYOUT @ _UTUI-PROJ-RELAYOUT-XT !
    _UTUI-PAI-QUIESCE @ _UTUI-PROJ-QUIESCE-XT !
    _UTUI-PAI-DETACH  @ _UTUI-PROJ-DETACH-XT !
    -1 _UTUI-PROJ-ADAPTER-INSTALLED !
    -1 ;

: _UTUI-PROJ-STATUS?  ( status -- flag )
    8 U< ;

VARIABLE _UTUI-PROJ-ARG0
VARIABLE _UTUI-PROJ-ARG1
VARIABLE _UTUI-PROJ-ARG2

: _UTUI-PROJ-DO-ATTACH  ( -- token status )
    _UTUI-PROJ-ARG0 @ _UTUI-PROJ-ADAPTER-CONTEXT @
    _UTUI-PROJ-ATTACH-XT @ EXECUTE ;

: _UTUI-PROJ-CALL-ATTACH  ( document-binding -- token status )
    _UTUI-PROJ-CALLING @ IF DROP 0 _UTUI-PROJ-S-INVALID EXIT THEN
    _UTUI-PROJ-ARG0 !
    -1 _UTUI-PROJ-CALLING !
    ['] _UTUI-PROJ-DO-ATTACH CATCH
    0 _UTUI-PROJ-CALLING !
    0 _UTUI-PROJ-ARG0 !
    ?DUP IF DROP 0 _UTUI-PROJ-S-INVALID THEN ;

: _UTUI-PROJ-DO-PROJECT  ( -- status )
    _UTUI-PROJ-ARG0 @ _UTUI-PROJ-ADAPTER-CONTEXT @
    _UTUI-PROJ-PROJECT-XT @ EXECUTE ;

: _UTUI-PROJ-CALL-PROJECT  ( token -- status )
    _UTUI-PROJ-CALLING @ IF DROP _UTUI-PROJ-S-INVALID EXIT THEN
    _UTUI-PROJ-ARG0 !
    -1 _UTUI-PROJ-CALLING !
    ['] _UTUI-PROJ-DO-PROJECT CATCH
    0 _UTUI-PROJ-CALLING !
    0 _UTUI-PROJ-ARG0 !
    ?DUP IF DROP _UTUI-PROJ-S-INVALID THEN ;

: _UTUI-PROJ-DO-RELAYOUT  ( -- status )
    _UTUI-PROJ-ARG0 @ _UTUI-PROJ-ARG1 @ _UTUI-PROJ-ARG2 @
    _UTUI-PROJ-ADAPTER-CONTEXT @
    _UTUI-PROJ-RELAYOUT-XT @ EXECUTE ;

: _UTUI-PROJ-CALL-RELAYOUT  ( visible region token -- status )
    _UTUI-PROJ-CALLING @ IF 3DROP _UTUI-PROJ-S-INVALID EXIT THEN
    _UTUI-PROJ-ARG2 ! _UTUI-PROJ-ARG1 ! _UTUI-PROJ-ARG0 !
    -1 _UTUI-PROJ-CALLING !
    ['] _UTUI-PROJ-DO-RELAYOUT CATCH
    0 _UTUI-PROJ-CALLING !
    0 _UTUI-PROJ-ARG0 ! 0 _UTUI-PROJ-ARG1 ! 0 _UTUI-PROJ-ARG2 !
    ?DUP IF DROP _UTUI-PROJ-S-INVALID THEN ;

: _UTUI-PROJ-DO-QUIESCE  ( -- status )
    _UTUI-PROJ-ARG0 @ _UTUI-PROJ-ADAPTER-CONTEXT @
    _UTUI-PROJ-QUIESCE-XT @ EXECUTE ;

: _UTUI-PROJ-CALL-QUIESCE  ( token -- status )
    _UTUI-PROJ-CALLING @ IF DROP _UTUI-PROJ-S-INVALID EXIT THEN
    _UTUI-PROJ-ARG0 !
    -1 _UTUI-PROJ-CALLING !
    ['] _UTUI-PROJ-DO-QUIESCE CATCH
    0 _UTUI-PROJ-CALLING !
    0 _UTUI-PROJ-ARG0 !
    ?DUP IF DROP _UTUI-PROJ-S-INVALID THEN ;

: _UTUI-PROJ-DO-DETACH  ( -- status )
    _UTUI-PROJ-ARG0 @ _UTUI-PROJ-ADAPTER-CONTEXT @
    _UTUI-PROJ-DETACH-XT @ EXECUTE ;

: _UTUI-PROJ-CALL-DETACH  ( token -- status )
    _UTUI-PROJ-CALLING @ IF DROP _UTUI-PROJ-S-INVALID EXIT THEN
    _UTUI-PROJ-ARG0 !
    -1 _UTUI-PROJ-CALLING !
    ['] _UTUI-PROJ-DO-DETACH CATCH
    0 _UTUI-PROJ-CALLING !
    0 _UTUI-PROJ-ARG0 !
    ?DUP IF DROP _UTUI-PROJ-S-INVALID THEN ;

VARIABLE _UTUI-PAA-BINDING
VARIABLE _UTUI-PAA-VISIBLE
VARIABLE _UTUI-PAA-TOKEN
VARIABLE _UTUI-PAA-STATUS

: _UTUI-PAA-CLEAR  ( -- )
    0 _UTUI-PAA-BINDING !
    0 _UTUI-PAA-VISIBLE !
    0 _UTUI-PAA-TOKEN !
    0 _UTUI-PAA-STATUS ! ;

: _UTUI-PROJECTION-RELAYOUT  ( -- status )
    _UTUI-PROJ-ATTACHED @ 0= IF _UTUI-PROJ-S-OK EXIT THEN
    _UTUI-QUIESCING @ IF _UTUI-PROJ-S-STALE EXIT THEN
    _UTUI-VISIBLE @ IF
        _UTUI-RGN @ DUP 0= IF DROP _UTUI-PROJ-S-INVALID EXIT THEN
        TRUE SWAP
    ELSE
        FALSE 0
    THEN
    _UTUI-PROJ-TOKEN @ _UTUI-PROJ-CALL-RELAYOUT
    DUP _UTUI-PROJ-STATUS? 0= IF DROP _UTUI-PROJ-S-INVALID THEN
    DUP _UTUI-PROJ-STATUS ! ;

\ Composition-private attach.  Called after a successful UTUI-LOAD.  The
\ binding is borrowed for this call only and is never stored in UIDL globals
\ or a UCTX.
: _UTUI-PROJECTION-ATTACH  ( document-binding visible -- status )
    _UTUI-PAA-VISIBLE ! _UTUI-PAA-BINDING !
    _UTUI-PROJ-ADAPTER-INSTALLED @ 0= IF
        _UTUI-PROJ-S-UNAVAILABLE DUP _UTUI-PROJ-STATUS !
        _UTUI-PAA-CLEAR EXIT
    THEN
    _UTUI-PAA-BINDING @ 0= _UTUI-DOC-LOADED @ 0= OR
    _UTUI-PROJ-ATTACHED @ OR _UTUI-QUIESCING @ OR
    _UTUI-QUIESCED @ OR IF
        _UTUI-PROJ-S-INVALID DUP _UTUI-PROJ-STATUS !
        _UTUI-PAA-CLEAR EXIT
    THEN
    _UTUI-PAA-BINDING @ _UTUI-PROJ-CALL-ATTACH
    0 _UTUI-PAA-BINDING !
    _UTUI-PAA-STATUS ! _UTUI-PAA-TOKEN !
    _UTUI-PAA-STATUS @ _UTUI-PROJ-STATUS? 0= IF
        _UTUI-PROJ-S-INVALID _UTUI-PAA-STATUS !
    THEN
    _UTUI-PAA-STATUS @ _UTUI-PROJ-S-OK = IF
        _UTUI-PAA-TOKEN @ 0= IF
            _UTUI-PROJ-S-INVALID DUP _UTUI-PROJ-STATUS !
            _UTUI-PAA-CLEAR EXIT
        THEN
    ELSE
        _UTUI-PAA-TOKEN @ IF
            _UTUI-PROJ-S-INVALID _UTUI-PAA-STATUS !
        THEN
        _UTUI-PAA-STATUS @ DUP _UTUI-PROJ-STATUS !
        _UTUI-PAA-CLEAR EXIT
    THEN
    _UTUI-PAA-TOKEN @ _UTUI-PROJ-TOKEN !
    _UTUI-PAA-VISIBLE @ 0<> _UTUI-VISIBLE !
    -1 _UTUI-PROJ-ATTACHED !
    0 _UTUI-QUIESCING !
    0 _UTUI-QUIESCED !
    _UTUI-PAA-CLEAR
    _UTUI-PROJECTION-RELAYOUT ;

\ Visibility changes are synchronized immediately.  Hidden documents pass a
\ zero region so a freed tile region can never be retained or dereferenced.
: UTUI-VISIBLE!  ( visible -- )
    0<> _UTUI-VISIBLE !
    _UTUI-PROJECTION-RELAYOUT DROP ;

: _UTUI-PROJECTION-PUBLISH  ( -- )
    _UTUI-PROJ-ATTACHED @ 0= IF EXIT THEN
    _UTUI-QUIESCING @ IF EXIT THEN
    _UTUI-PROJ-TOKEN @ _UTUI-PROJ-CALL-PROJECT
    DUP _UTUI-PROJ-STATUS? 0= IF DROP _UTUI-PROJ-S-INVALID THEN
    _UTUI-PROJ-STATUS ! ;

\ Quiesce is the retryable pre-shutdown barrier.  A failed callback leaves the
\ token live and projection state intact.  Success stops project/relayout but
\ retains the source-free token for final detach.
: UTUI-QUIESCE  ( -- status )
    _UTUI-QUIESCED @ IF _UTUI-PROJ-S-OK EXIT THEN
    -1 _UTUI-QUIESCING !
    _UTUI-PROJ-ATTACHED @ 0= IF
        -1 _UTUI-QUIESCED !
        _UTUI-PROJ-S-OK DUP _UTUI-PROJ-STATUS ! EXIT
    THEN
    _UTUI-PROJ-TOKEN @ _UTUI-PROJ-CALL-QUIESCE
    DUP _UTUI-PROJ-STATUS? 0= IF DROP _UTUI-PROJ-S-INVALID THEN
    DUP _UTUI-PROJ-STATUS !
    DUP _UTUI-PROJ-S-OK = IF -1 _UTUI-QUIESCED ! THEN ;

\ Final detach is distinct from source quiescence.  Failure preserves the
\ complete source-free token for retry and forbids ordinary UIDL teardown.
: _UTUI-PROJECTION-DETACH  ( -- status )
    _UTUI-PROJ-ATTACHED @ 0= IF _UTUI-PROJ-S-OK EXIT THEN
    _UTUI-QUIESCED @ 0= IF
        UTUI-QUIESCE DUP IF EXIT THEN DROP
    THEN
    _UTUI-PROJ-TOKEN @ _UTUI-PROJ-CALL-DETACH
    DUP _UTUI-PROJ-STATUS? 0= IF DROP _UTUI-PROJ-S-INVALID THEN
    DUP _UTUI-PROJ-STATUS !
    DUP _UTUI-PROJ-S-OK = IF
        0 _UTUI-PROJ-TOKEN !
        0 _UTUI-PROJ-ATTACHED !
    THEN ;

: _UTUI-PROJECTION-CLEAR  ( -- )
    0 _UTUI-PROJ-TOKEN !
    0 _UTUI-PROJ-STATUS !
    0 _UTUI-VISIBLE !
    0 _UTUI-PROJ-ATTACHED !
    0 _UTUI-QUIESCING !
    0 _UTUI-QUIESCED !
    0 _UTUI-PROJ-CALLING !
    0 _UTUI-PROJ-ARG0 ! 0 _UTUI-PROJ-ARG1 ! 0 _UTUI-PROJ-ARG2 !
    _UTUI-PAA-CLEAR ;

\ Public setter for the root region (used by desk to re-assign tiles)
: UTUI-RGN!  ( rgn -- )  _UTUI-RGN ! ;

\ UIDL render words use document-relative coordinates while ordinary widget
\ regions remain screen-absolute.  Restore the document clip after every
\ nested widget draw; callers leave the paint cycle at RGN-ROOT.
: _UTUI-RESTORE-DOC-RGN  ( -- )
    _UTUI-RGN @ ?DUP IF RGN-USE ELSE RGN-ROOT THEN ;

\ Wire UIDL-DIRTY! hook so any element dirtying auto-signals repaint
: _UTUI-DIRTY-HOOK  ( -- ) _UTUI-NEEDS-PAINT ON ;
' _UTUI-DIRTY-HOOK  _UDL-DIRTY-HOOK !

\ =====================================================================
\  §3 — Action Dispatch Table
\ =====================================================================
\
\  Exact, context-local action names and their execution tokens share one
\  bounded arena.  Fixed 24-byte entries grow upward while copied name bytes
\  grow downward, so registration never retains caller-owned string storage.
\  Entry layout: +0 name offset, +8 name length, +16 xt.

24 CONSTANT _UTUI-ACT-ENTRY-SIZE
1536 CONSTANT _UTUI-ACTS-SZ
CREATE _UTUI-ACTS  _UTUI-ACTS-SZ ALLOT
VARIABLE _UTUI-ACT-CNT

VARIABLE _UTUI-ACT-REG-A
VARIABLE _UTUI-ACT-REG-U
VARIABLE _UTUI-ACT-REG-XT
VARIABLE _UTUI-ACT-FRONTIER
VARIABLE _UTUI-ACT-ENTRIES-END
VARIABLE _UTUI-ACT-ENTRY-P
VARIABLE _UTUI-ACT-ENTRY-OFF
VARIABLE _UTUI-ACT-ENTRY-U
VARIABLE _UTUI-ACT-QA
VARIABLE _UTUI-ACT-QU

: _UTUI-ACT-ENTRY  ( index -- entry )
    _UTUI-ACT-ENTRY-SIZE * _UTUI-ACTS + ;

: _UTUI-ACT-COUNT-VALID?  ( count -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    _UTUI-ACTS-SZ _UTUI-ACT-ENTRY-SIZE / U> 0= ;

: _UTUI-ACT-ENTRY-VALID?  ( entries-end entry -- flag )
    _UTUI-ACT-ENTRY-P !
    _UTUI-ACT-ENTRIES-END !
    _UTUI-ACT-ENTRY-P @ @ _UTUI-ACT-ENTRY-OFF !
    _UTUI-ACT-ENTRY-P @ 8 + @ _UTUI-ACT-ENTRY-U !
    _UTUI-ACT-ENTRY-U @ 0> 0= IF 0 EXIT THEN
    _UTUI-ACT-ENTRY-OFF @ _UTUI-ACT-ENTRIES-END @ U< IF 0 EXIT THEN
    _UTUI-ACT-ENTRY-OFF @ _UTUI-ACTS-SZ U> IF 0 EXIT THEN
    _UTUI-ACT-ENTRY-U @
        _UTUI-ACTS-SZ _UTUI-ACT-ENTRY-OFF @ - U> IF 0 EXIT THEN
    -1 ;

: _UTUI-ACT-FRONTIER?  ( count -- frontier flag )
    DUP _UTUI-ACT-COUNT-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP 0= IF DROP _UTUI-ACTS-SZ -1 EXIT THEN
    DUP _UTUI-ACT-ENTRY-SIZE * _UTUI-ACT-ENTRIES-END !
    1- _UTUI-ACT-ENTRY DUP _UTUI-ACT-ENTRY-P !
    _UTUI-ACT-ENTRIES-END @ SWAP _UTUI-ACT-ENTRY-VALID? 0= IF
        0 0 EXIT
    THEN
    _UTUI-ACT-ENTRY-P @ @ -1 ;

: _UTUI-ACT-REG-CLEAR  ( -- )
    0 _UTUI-ACT-REG-A !
    0 _UTUI-ACT-REG-U !
    0 _UTUI-ACT-REG-XT ! ;

: _UTUI-DO-BODY  ( do-a do-l xt -- )
    _UTUI-ACT-REG-XT !
    _UTUI-ACT-REG-U !
    _UTUI-ACT-REG-A !
    _UTUI-ACT-REG-U @ 0> 0= IF EXIT THEN
    _UTUI-ACT-REG-A @ 0= IF EXIT THEN
    _UTUI-ACT-REG-A @ _UTUI-ACT-REG-U @
        MSPAN-NONWRAPPING? 0= IF EXIT THEN
    _UTUI-ACT-REG-A @ _UTUI-ACT-REG-U @
        _UTUI-ACTS _UTUI-ACTS-SZ MSPAN-OVERLAP? IF EXIT THEN
    _UTUI-ACT-CNT @ DUP _UTUI-ACT-COUNT-VALID? 0= IF DROP EXIT THEN
    DUP _UTUI-ACT-FRONTIER? 0= IF 2DROP EXIT THEN
    _UTUI-ACT-FRONTIER !
    _UTUI-ACT-ENTRY-SIZE *
    DUP _UTUI-ACTS-SZ _UTUI-ACT-ENTRY-SIZE - U> IF DROP EXIT THEN
    _UTUI-ACT-ENTRY-SIZE + _UTUI-ACT-ENTRIES-END !
    _UTUI-ACT-ENTRIES-END @ _UTUI-ACT-FRONTIER @ U> IF EXIT THEN
    _UTUI-ACT-REG-U @
        _UTUI-ACT-FRONTIER @ _UTUI-ACT-ENTRIES-END @ - U> IF EXIT THEN
    _UTUI-ACT-FRONTIER @ _UTUI-ACT-REG-U @ -
        _UTUI-ACT-ENTRY-OFF !
    _UTUI-ACT-REG-A @
        _UTUI-ACTS _UTUI-ACT-ENTRY-OFF @ +
        _UTUI-ACT-REG-U @ CMOVE
    _UTUI-ACT-CNT @ _UTUI-ACT-ENTRY DUP _UTUI-ACT-ENTRY-P !
    _UTUI-ACT-ENTRY-OFF @ OVER !
    _UTUI-ACT-REG-U @ OVER 8 + !
    _UTUI-ACT-REG-XT @ SWAP 16 + !
    1 _UTUI-ACT-CNT +! ;

: UTUI-DO!  ( do-a do-l xt -- )
    _UTUI-DO-BODY
    _UTUI-ACT-REG-CLEAR ;

: _UTUI-ACT-QUERY-CLEAR  ( -- )
    0 _UTUI-ACT-QA !
    0 _UTUI-ACT-QU ! ;

: _UTUI-ACT-FIND-BODY  ( do-a do-l -- xt | 0 )
    _UTUI-ACT-QU !
    _UTUI-ACT-QA !
    _UTUI-ACT-QU @ 0> 0= IF 0 EXIT THEN
    _UTUI-ACT-QA @ 0= IF 0 EXIT THEN
    _UTUI-ACT-QA @ _UTUI-ACT-QU @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _UTUI-ACT-CNT @ DUP _UTUI-ACT-COUNT-VALID? 0= IF DROP 0 EXIT THEN
    DUP _UTUI-ACT-ENTRY-SIZE * _UTUI-ACT-ENTRIES-END !
    0 ?DO
        I _UTUI-ACT-ENTRY
        _UTUI-ACT-ENTRIES-END @ SWAP _UTUI-ACT-ENTRY-VALID? 0= IF
            0 UNLOOP EXIT
        THEN
        _UTUI-ACT-ENTRY-U @ _UTUI-ACT-QU @ = IF
            _UTUI-ACTS _UTUI-ACT-ENTRY-OFF @ + _UTUI-ACT-ENTRY-U @
            _UTUI-ACT-QA @ _UTUI-ACT-QU @ STR-STR= IF
                I _UTUI-ACT-ENTRY 16 + @ UNLOOP EXIT
            THEN
        THEN
    LOOP
    0 ;

: _UTUI-ACT-FIND  ( do-a do-l -- xt | 0 )
    _UTUI-ACT-FIND-BODY
    _UTUI-ACT-QUERY-CLEAR ;

: _UTUI-FIRE-DO  ( elem -- )
    DUP S" do" UIDL-ATTR IF           ( elem da dl )
        _UTUI-ACT-FIND                 ( elem xt|0 )
        ?DUP IF EXECUTE EXIT THEN
        DROP EXIT
    THEN
    2DROP DROP ;

: _UTUI-ACT-CLEAR  ( -- )
    0 _UTUI-ACT-CNT !
    _UTUI-ACTS _UTUI-ACTS-SZ 0 FILL
    _UTUI-ACT-REG-CLEAR
    _UTUI-ACT-QUERY-CLEAR ;

\ =====================================================================
\  §4 — Shortcut Table
\ =====================================================================
\
\  64 entries, each 32 bytes: +0 key-code, +8 mod-mask, +16 elem, +24 used

64 CONSTANT _UTUI-MAX-SHORTS
CREATE _UTUI-SHORTS  _UTUI-MAX-SHORTS 32 * ALLOT
VARIABLE _UTUI-SHORT-CNT

\ Key-descriptor parsing temps
VARIABLE _UKP-A  VARIABLE _UKP-L  VARIABLE _UKP-MOD

\ Parse "Ctrl+Shift+S" → key-code mod-mask
\ Uses variables exclusively to avoid stack clutter.
: _UTUI-PARSE-KEY-DESC  ( a l -- key-code mod-mask )
    _UKP-L ! _UKP-A !
    0 _UKP-MOD !

    \ Check for Ctrl+ prefix
    _UKP-A @ _UKP-L @ S" Ctrl+" STR-STARTS? IF
        _UKP-MOD @ KEY-MOD-CTRL OR _UKP-MOD !
        _UKP-A @ 5 + _UKP-A !
        _UKP-L @ 5 - _UKP-L !
    THEN

    \ Check for Shift+ prefix
    _UKP-A @ _UKP-L @ S" Shift+" STR-STARTS? IF
        _UKP-MOD @ KEY-MOD-SHIFT OR _UKP-MOD !
        _UKP-A @ 6 + _UKP-A !
        _UKP-L @ 6 - _UKP-L !
    THEN

    \ Check for Alt+ prefix
    _UKP-A @ _UKP-L @ S" Alt+" STR-STARTS? IF
        _UKP-MOD @ KEY-MOD-ALT OR _UKP-MOD !
        _UKP-A @ 4 + _UKP-A !
        _UKP-L @ 4 - _UKP-L !
    THEN

    \ Remaining = key name
    _UKP-L @ 1 = IF
        _UKP-A @ C@
        \ keys.f decodes Ctrl+letter to lowercase codes; normalise A-Z
        _UKP-MOD @ KEY-MOD-CTRL AND IF
            DUP [CHAR] A >= OVER [CHAR] Z <= AND IF 32 OR THEN
        THEN
        _UKP-MOD @ EXIT
    THEN
    _UKP-A @ _UKP-L @
    2DUP S" F1"  STR-STR= IF 2DROP KEY-F1  _UKP-MOD @ EXIT THEN
    2DUP S" F2"  STR-STR= IF 2DROP KEY-F2  _UKP-MOD @ EXIT THEN
    2DUP S" F3"  STR-STR= IF 2DROP KEY-F3  _UKP-MOD @ EXIT THEN
    2DUP S" F4"  STR-STR= IF 2DROP KEY-F4  _UKP-MOD @ EXIT THEN
    2DUP S" F5"  STR-STR= IF 2DROP KEY-F5  _UKP-MOD @ EXIT THEN
    2DUP S" F6"  STR-STR= IF 2DROP KEY-F6  _UKP-MOD @ EXIT THEN
    2DUP S" F7"  STR-STR= IF 2DROP KEY-F7  _UKP-MOD @ EXIT THEN
    2DUP S" F8"  STR-STR= IF 2DROP KEY-F8  _UKP-MOD @ EXIT THEN
    2DUP S" F9"  STR-STR= IF 2DROP KEY-F9  _UKP-MOD @ EXIT THEN
    2DUP S" F10" STR-STR= IF 2DROP KEY-F10 _UKP-MOD @ EXIT THEN
    2DUP S" F11" STR-STR= IF 2DROP KEY-F11 _UKP-MOD @ EXIT THEN
    2DUP S" F12" STR-STR= IF 2DROP KEY-F12 _UKP-MOD @ EXIT THEN
    2DUP S" Tab"       STR-STR= IF 2DROP KEY-TAB       _UKP-MOD @ EXIT THEN
    2DUP S" Enter"     STR-STR= IF 2DROP KEY-ENTER     _UKP-MOD @ EXIT THEN
    2DUP S" Backspace" STR-STR= IF 2DROP KEY-BACKSPACE  _UKP-MOD @ EXIT THEN
    2DUP S" Escape"    STR-STR= IF 2DROP KEY-ESC        _UKP-MOD @ EXIT THEN
    2DUP S" Delete"    STR-STR= IF 2DROP KEY-DEL        _UKP-MOD @ EXIT THEN
    2DUP S" Insert"    STR-STR= IF 2DROP KEY-INS        _UKP-MOD @ EXIT THEN
    2DUP S" Home"      STR-STR= IF 2DROP KEY-HOME       _UKP-MOD @ EXIT THEN
    2DUP S" End"       STR-STR= IF 2DROP KEY-END        _UKP-MOD @ EXIT THEN
    2DUP S" PageUp"    STR-STR= IF 2DROP KEY-PGUP       _UKP-MOD @ EXIT THEN
    2DUP S" PageDown"  STR-STR= IF 2DROP KEY-PGDN       _UKP-MOD @ EXIT THEN
    2DROP 0 _UKP-MOD @ ;

\ Register a shortcut for an element with key= attr
: _UTUI-REG-SHORTCUT  ( elem -- )
    DUP S" key" UIDL-ATTR IF         ( elem ka kl )
        _UTUI-SHORT-CNT @ _UTUI-MAX-SHORTS >= IF
            2DROP DROP EXIT
        THEN
        _UTUI-PARSE-KEY-DESC          ( elem key-code mod-mask )
        _UTUI-SHORT-CNT @ 32 * _UTUI-SHORTS +  ( elem kc mm entry )
        >R
        R@ 8 + !                      \ entry+8 = mod-mask
        R@ !                          \ entry+0 = key-code
        R@ 16 + !                     \ entry+16 = elem
        1 R> 24 + !                   \ entry+24 = used
        1 _UTUI-SHORT-CNT +!
    ELSE 2DROP DROP THEN ;

\ Match key against shortcuts → elem | 0
: _UTUI-SHORT-MATCH  ( key-code mod-mask -- elem | 0 )
    _UTUI-SHORT-CNT @ 0 ?DO
        I 32 * _UTUI-SHORTS +
        DUP 24 + @ IF                 \ used?
            DUP @ 3 PICK = IF         \ key-code match?
                DUP 8 + @ 2 PICK = IF \ mod-mask match?
                    16 + @
                    >R 2DROP R>
                    UNLOOP EXIT
                THEN
            THEN
        THEN
        DROP
    LOOP
    2DROP 0 ;

: _UTUI-SHORT-CLEAR  ( -- )
    0 _UTUI-SHORT-CNT !
    _UTUI-SHORTS _UTUI-MAX-SHORTS 32 * 0 FILL ;

\ =====================================================================
\  §5 — Rendering Words (render-xt implementations)
\ =====================================================================
\
\  Each render-xt receives ( elem -- ) and draws to screen buffer.
\  All rendering uses _UR-* temp vars to avoid stack gymnastics.

\ --- Stash sidecar fields into temp vars ---
\ Leaves elem on stack, returns false if invisible.
: _UTUI-STASH-SC  ( elem -- elem flag )
    DUP _UTUI-SIDECAR                 ( elem sc )
    DUP _UTUI-SC-VIS? 0= IF DROP 0 EXIT THEN
    DUP _UTUI-APPLY-STYLE
    DRW-STYLE-SAVE                     \ widgets use DRW-STYLE-RESTORE
    DUP _UTUI-SC-ROW@ DUP _UR-ABS-ROW !
    _UTUI-RGN @ ?DUP IF RGN-ROW - THEN _UR-ROW !
    DUP _UTUI-SC-COL@ DUP _UR-ABS-COL !
    _UTUI-RGN @ ?DUP IF RGN-COL - THEN _UR-COL !
    DUP _UTUI-SC-W@   _UR-W !
    _UTUI-SC-H@        _UR-H !
    -1 ;

\ --- Helper: fill sidecar rect with spaces ---
: _UTUI-FILL-BG  ( -- )
    32 _UR-ROW @ _UR-COL @ _UR-H @ _UR-W @ DRW-FILL-RECT ;

\ --- Evaluate bind= → display text ---
\ Uses UIDL-BIND ( elem -- a l flag ).  Returns ( a l ).
\ For int/bool, converts to string via pictured numeric output.
: _UTUI-BIND-TEXT  ( elem -- a l )
    UIDL-BIND IF                       ( ba bl — bind expression )
        LEL-EVAL                       ( type v1 v2 )
        ROT                            ( v1 v2 type )
        DUP ST-T-STRING  = IF DROP EXIT THEN
        DUP ST-T-INTEGER = IF
            DROP DROP                  ( n )
            NUM>STR EXIT
        THEN
        DUP ST-T-BOOLEAN = IF
            DROP DROP
            IF S" true" ELSE S" false" THEN EXIT
        THEN
        DROP 2DROP S" "
    ELSE
        2DROP S" "                     \ no bind — UIDL-BIND returned (0 0 0)
    THEN ;

\ --- Get display text from renderer-neutral UIDL value semantics ---
: _UTUI-DISPLAY-TEXT  ( elem -- a l )
    UIDL-TEXT@ ;

\ --- Label ---
: _UTUI-RENDER-LABEL  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG                              \ fill full rect with bg color
    DUP _UTUI-SIDECAR _UTUI-SC-TALIGN@    ( elem align )
    SWAP _UTUI-DISPLAY-TEXT                ( align a l )
    _UR-W @ MIN                            \ clip to width
    ROT                                    ( a l' align )
    DUP 1 = IF DROP _UR-ROW @ _UR-COL @ _UR-W @ DRW-TEXT-CENTER EXIT THEN
    DUP 2 = IF DROP _UR-ROW @ _UR-COL @ _UR-W @ DRW-TEXT-RIGHT  EXIT THEN
    DROP _UR-ROW @ _UR-COL @ DRW-TEXT ;

\ --- Action button ---
: _UTUI-RENDER-ACTION  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    _UTUI-DISPLAY-TEXT                 ( a l )
    _UR-ROW @ _UR-COL @ _UR-W @ DRW-TEXT-CENTER ;

\ --- Input: delegate to materialized INP widget ---
: _UTUI-RENDER-INPUT  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    DUP _UTUI-SIDECAR                  ( elem sc )
    DUP _UTUI-SC-WPTR@                 ( elem sc wptr )
    DUP 0= IF DROP 2DROP EXIT THEN
    SWAP OVER _UTUI-SYNC-WFOCUS       ( elem wptr )
    NIP                                ( wptr )
    _UTUI-PROXY-FROM-UR
    _UTUI-PROXY-RGN RGN-USE
    _INP-DRAW
    _UTUI-RESTORE-DOC-RGN ;

\ --- Separator ---
: _UTUI-RENDER-SEP  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP
    9472 _UR-ROW @ _UR-COL @ _UR-W @ DRW-HLINE ;

\ --- Region / container: fill bg, draw mounted widget if any ---
: _UTUI-RENDER-REGION  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    \ Stack: ( elem )
    _UTUI-FILL-BG
    \ If a widget was attached via UTUI-WIDGET-SET, draw it
    DUP _UTUI-SIDECAR                    ( elem sc )
    DUP _UTUI-SC-WPTR@ ?DUP IF           ( elem sc wptr )
        >R
        DUP R@ _UTUI-SYNC-WFOCUS
        2DROP R>                          ( wptr )
        _UTUI-PROXY-FROM-UR
        \ Sync the widget's own region from current sidecar (handles resize)
        DUP _WDG-O-REGION + @
        _UR-ABS-ROW @ OVER _RGN-O-ROW + !
        _UR-ABS-COL @ OVER _RGN-O-COL + !
        _UR-H @   OVER _RGN-O-H   + !
        _UR-W @   OVER _RGN-O-W   + !
        _UTUI-RGN @ SWAP _RGN-O-PARENT + !
        _UTUI-PROXY-RGN RGN-USE
        DUP _WDG-O-DRAW-XT + @ EXECUTE
        _UTUI-RESTORE-DOC-RGN
    ELSE
        2DROP
    THEN ;

\ --- Menu dropdown state ---
VARIABLE _UTUI-MENU-OPEN       \ currently-open <menu> elem (0 = none)
VARIABLE _UTUI-MENU-SAVED-FOC  \ focus before menu opened

\ --- Menubar ---
\ Does elem or any descendant of elem hold focus?
: _UTUI-HAS-FOCUS?  ( elem -- flag )
    _UTUI-FOCUS-P @ DUP 0= IF NIP EXIT THEN  ( elem foc )
    BEGIN
        2DUP = IF 2DROP -1 EXIT THEN
        UIDL-PARENT DUP 0=
    UNTIL NIP ;

: _UTUI-RENDER-MBAR  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    \ Fill bar background (1 row)
    32 _UR-ROW @ _UR-COL @ 1 _UR-W @ DRW-FILL-RECT
    \ Draw each menu child's label.
    \ Highlight when the menu (or any item inside it) holds focus.
    _UR-COL @ 1+ _UR-TMP !            \ column cursor
    UIDL-FIRST-CHILD                   ( child | 0 )
    BEGIN DUP 0<> WHILE
        DUP S" label" UIDL-ATTR IF    ( child la ll )
            2 PICK _UTUI-HAS-FOCUS? IF
                _DRW-ATTRS @ CELL-A-REVERSE OR _DRW-ATTRS !
            THEN
            2DUP _UR-ROW @ _UR-TMP @ DRW-TEXT
            DRW-STYLE-RESTORE
            NIP 2 + _UR-TMP +!        ( child )
        ELSE 2DROP THEN
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

\ --- Menu dropdown rendering ---
\
\  Each element renders itself.  <menu> draws the border box when
\  open; each <item> draws its own background + text + highlight.
\  Opening a menu sets z-index > 0 so the paint walker defers it
\  to the Pass 2 overlay buffer, and _UTUI-PAINT-SUBTREE walks its
\  admitted visible descendants without re-deferring nested nodes.

VARIABLE _UMD-COL      \ dropdown left column
VARIABLE _UMD-MAXW     \ widest item text length
VARIABLE _UMD-ICNT     \ item count
VARIABLE _UMD-ROW      \ dropdown top row (menubar row + 1)

\ Menu rows follow the same semantic/layout admission rule as ordinary flow.
\ Only items and separators are valid rows; when=false, display:none, and
\ positioned children do not consume space.  Runtime hiding and
\ visibility:hidden retain a row but still suppress paint and hit-testing.
: _UTUI-MENU-ROW?  ( child -- flag )
    DUP UIDL-EVAL-WHEN 0= IF DROP 0 EXIT THEN
    DUP UIDL-TYPE DUP UIDL-T-ITEM = SWAP UIDL-T-SEPARATOR = OR 0= IF
        DROP 0 EXIT
    THEN
    DUP _UTUI-SIDECAR _UTUI-SC-FLAGS@ _UTUI-SCF-HIDE AND IF
        DROP 0 EXIT
    THEN
    _UTUI-SIDECAR _UTUI-SC-POS@ 0= ;

: _UTUI-MENU-NAVIGABLE?  ( child -- flag )
    DUP UIDL-TYPE UIDL-T-ITEM <> IF DROP 0 EXIT THEN
    DUP _UTUI-MENU-ROW? 0= IF DROP 0 EXIT THEN
    _UTUI-SIDECAR _UTUI-SC-VIS? ;

\ Retained menu semantics need the row's own visibility, independently of
\ whether its MENU ancestor is currently open.  Closing a menu deliberately
\ clears the layout-owned VIS bit, so this predicate observes admission and
\ the durable CSS/runtime hiding authorities without treating that close-owned
\ bit as local application state.
: _UTUI-MENU-ROW-LOCAL-VISIBLE-BODY?  ( elem -- flag )
    DUP UIDL-ELEM-INDEX? 0= IF 2DROP 0 EXIT THEN DROP
    _UTUI-DOC-LOADED @ 0= IF DROP 0 EXIT THEN
    _UTUI-ELEM-BASE @ _UDL-ELEMS <> IF DROP 0 EXIT THEN
    DUP _UTUI-MENU-ROW? 0= IF DROP 0 EXIT THEN
    _UTUI-SIDECAR
    DUP _UTUI-SC-FLAGS@
    DUP _UTUI-SCF-HAS AND 0= IF 2DROP 0 EXIT THEN
    TSC-F-HIDDEN _UTUI-SCF-HIDE OR AND IF DROP 0 EXIT THEN
    _UTUI-SC-RUNTIME@ _UTUI-RUNTIME-F-HIDDEN AND 0= ;

\ Measure admitted items and find the widest text= label.
: _UTUI-MENU-MEASURE  ( menu-elem -- )
    0 _UMD-MAXW !   0 _UMD-ICNT !
    UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-MENU-ROW? IF
            1 _UMD-ICNT +!
            DUP UIDL-TYPE UIDL-T-ITEM = IF
                DUP S" text" UIDL-ATTR IF
                    NIP _UMD-MAXW @ MAX _UMD-MAXW !
                ELSE 2DROP THEN
            THEN
        THEN
        UIDL-NEXT-SIB
    REPEAT DROP ;

\ Render <menu>: draw border box when this menu is the open dropdown.
\ Geometry already covers the dropdown area (set by _UTUI-MENU-OPEN!).
: _UTUI-RENDER-MENU  ( elem -- )
    DUP _UTUI-MENU-OPEN @ <> IF DROP EXIT THEN
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP
    \ Fill interior with bg color
    _UTUI-FILL-BG
    \ Draw single-line border
    BOX-SINGLE _UR-ROW @ _UR-COL @ _UR-H @ _UR-W @ BOX-DRAW ;

\ Render <item>: self-rendering — bg fill + text + reverse highlight
: _UTUI-RENDER-ITEM  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    \ Highlight if this item is focused
    DUP _UTUI-FOCUS-P @ = IF
        _DRW-ATTRS @ CELL-A-REVERSE OR _DRW-ATTRS !
    THEN
    _UTUI-FILL-BG
    DUP S" text" UIDL-ATTR IF
        _UR-ROW @ _UR-COL @ 1+ DRW-TEXT
    ELSE 2DROP THEN
    DROP ;

\ --- Status bar: first child left, last child right ---
VARIABLE _UST-FIRST

: _UTUI-RENDER-STATUS  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP
    \ Just fill the status bar background — child labels render themselves.
    32 _UR-ROW @ _UR-COL @ 1 _UR-W @ DRW-FILL-RECT ;

\ --- Toolbar ---
: _UTUI-RENDER-TOOLBAR  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP
    32 _UR-ROW @ _UR-COL @ 1 _UR-W @ DRW-FILL-RECT ;

\ --- Dialog ---
: _UTUI-RENDER-DLG  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP
    \ Fill area
    _UTUI-FILL-BG
    \ Border
    BOX-ROUND _UR-ROW @ _UR-COL @ _UR-H @ _UR-W @ BOX-DRAW ;

\ --- Split: draw vertical divider at ratio= position ---
: _UTUI-RENDER-SPLIT  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    \ Fill background so overlay-close repaint produces correct bg
    _UTUI-FILL-BG
    \ Read ratio= (default 50)
    S" ratio" UIDL-ATTR IF
        STR>NUM 0= IF DROP 50 THEN
    ELSE 2DROP 50 THEN                 ( ratio )
    \ Divider col offset = w * ratio / 100
    _UR-W @ * 100 /
    _UR-COL @ +                        ( abs-col )
    9474 _UR-ROW @ ROT _UR-H @ DRW-VLINE ;

\ --- Tabs header: draw labels + active highlight + underline ---
VARIABLE _UT-TAB-COL

: _UTUI-RENDER-TABS  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    \ Active tab index from wptr state (default 0)
    DUP _UTUI-SIDECAR _UTUI-SC-WPTR@
    DUP IF @ ELSE DROP 0 THEN
    _UR-ELEM !                         \ active index
    _UR-COL @ 1+ _UT-TAB-COL !
    0 _UR-TMP !                        \ child index counter
    UIDL-FIRST-CHILD                   ( child | 0 )
    BEGIN DUP 0<> WHILE
        DUP S" label" UIDL-ATTR IF    ( child la ll )
            \ Reverse highlight for active tab
            _UR-TMP @ _UR-ELEM @ = IF
                _DRW-BG @ _DRW-FG @ DRW-BG! DRW-FG!
            THEN
            2DUP _UR-ROW @ _UT-TAB-COL @ DRW-TEXT
            _UR-TMP @ _UR-ELEM @ = IF
                _DRW-BG @ _DRW-FG @ DRW-BG! DRW-FG!
            THEN
            NIP 2 + _UT-TAB-COL +!    ( child )
        ELSE 2DROP THEN
        1 _UR-TMP +!
        UIDL-NEXT-SIB
    REPEAT DROP
    \ Underline on row 1 if h >= 2
    _UR-H @ 2 >= IF
        9472 _UR-ROW @ 1+ _UR-COL @ _UR-W @ DRW-HLINE
    THEN ;

\ --- Progress bar ---
: _UTUI-RENDER-PROGRESS  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    \ Track background (light shade)
    9617 _UR-ROW @ _UR-COL @ _UR-W @ DRW-HLINE
    \ Evaluate bind for value 0–100
    _UTUI-BIND-TEXT                    ( a l )
    DUP 0= IF 2DROP EXIT THEN
    STR>NUM 0= IF DROP EXIT THEN      ( n )
    _UR-W @ * 100 / DUP 0< IF DROP 0 THEN _UR-W @ MIN  ( fill-w )
    DUP 0= IF DROP EXIT THEN
    _UR-TMP !
    9608 _UR-ROW @ _UR-COL @ _UR-TMP @ DRW-HLINE ;

\ --- Toggle ---
: _UTUI-RENDER-TOGGLE  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-DISPLAY-TEXT                 ( a l )
    S" true" STR-STR=                  ( flag )
    IF S" [X]" ELSE S" [ ]" THEN
    _UR-ROW @ _UR-COL @ DRW-TEXT ;

\ --- Indicator (like label) ---
: _UTUI-RENDER-INDICATOR  ( elem -- )
    _UTUI-RENDER-LABEL ;

\ --- List / collection: background fill + child rows ---
: _UTUI-RENDER-LIST  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP _UTUI-FILL-BG ;

\ --- Tree: delegate to materialized TREE widget ---
: _UTUI-RENDER-TREE  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    DUP _UTUI-SIDECAR _UTUI-SC-WPTR@  ( elem wptr )
    DUP 0= IF 2DROP EXIT THEN
    NIP                                ( wptr )
    \ Widget proxy regions remain screen-absolute even though direct UIDL
    \ drawing is relative to the document clip.
    _UTUI-PROXY-FROM-UR
    _UTUI-PROXY-RGN RGN-USE
    _TREE-DRAW
    _UTUI-RESTORE-DOC-RGN ;

\ --- Textarea: delegate to materialized TXTA widget ---
: _UTUI-RENDER-TEXTAREA  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    DUP _UTUI-SIDECAR                  ( elem sc )
    DUP _UTUI-SC-WPTR@                 ( elem sc wptr )
    DUP 0= IF DROP 2DROP EXIT THEN
    SWAP OVER _UTUI-SYNC-WFOCUS       ( elem wptr )
    NIP                                ( wptr )
    _UTUI-PROXY-FROM-UR
    _UTUI-PROXY-RGN RGN-USE
    _TXTA-DRAW
    _UTUI-RESTORE-DOC-RGN ;

\ --- Canvas: fill background (actual CVS-* drawing is app-level) ---
: _UTUI-RENDER-CANVAS  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP _UTUI-FILL-BG ;

\ --- Scroll: render scrollbar track and proportional thumb ---
\
\ The <scroll> container wraps a single child (region, textarea, tree,
\ etc.).  Layout reserves 1 column on the right for a scrollbar track.
\ The render word fills the background, then queries the child widget
\ for (content-height, scroll-offset, visible-height) and draws a
\ proportional thumb on the track.

\ Type-dispatched scroll-info query.  Returns 0 0 0 for unsupported types.
: _USCR-SCROLL-INFO  ( widget -- content-h offset visible-h )
    DUP WDG-TYPE
    DUP WDG-T-LIST = IF DROP LST-SCROLL-INFO EXIT THEN
    DUP WDG-T-TREE = IF DROP TREE-SCROLL-INFO EXIT THEN
    DUP WDG-T-TEXTAREA = IF DROP TXTA-SCROLL-INFO EXIT THEN
    DROP DROP 0 0 0 ;

\ Type-dispatched scroll-set.  No-op for unsupported types.
: _USCR-SCROLL-SET  ( offset widget -- )
    DUP WDG-TYPE
    DUP WDG-T-LIST = IF DROP LST-SCROLL-SET EXIT THEN
    DUP WDG-T-TREE = IF DROP TREE-SCROLL-SET EXIT THEN
    DUP WDG-T-TEXTAREA = IF DROP TXTA-SCROLL-SET EXIT THEN
    DROP 2DROP ;

\ Get the widget pointer from <scroll>'s single child element.
: _USCR-CHILD-WDG  ( scroll-elem -- widget | 0 )
    UIDL-FIRST-CHILD DUP 0= IF EXIT THEN
    _UTUI-SIDECAR _UTUI-SC-WPTR@ ;

\ Scroll-track drawing constants (Unicode)
9617 CONSTANT _USCR-TRACK-CP    \ ░ light shade — track background
9608 CONSTANT _USCR-THUMB-CP    \ █ full block  — thumb

\ Temp vars for scroll rendering (single-threaded, safe)
VARIABLE _USCR-CH    \ content height
VARIABLE _USCR-SO    \ scroll offset
VARIABLE _USCR-VH    \ visible height
VARIABLE _USCR-TH    \ thumb height (cells)
VARIABLE _USCR-TP    \ thumb top (0-based within track)
VARIABLE _USCR-SC    \ saved sidecar during scroll mouse dispatch

: _UTUI-RENDER-SCROLL  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    \ Sync child's proxy region so widget sees correct dimensions
    DUP UIDL-FIRST-CHILD ?DUP IF
        _UTUI-SIDECAR _UTUI-SYNC-PROXY
    THEN
    \ Get child widget
    _USCR-CHILD-WDG DUP 0= IF DROP EXIT THEN
    _USCR-SCROLL-INFO
    _USCR-VH ! _USCR-SO ! _USCR-CH !
    \ If content fits, draw dimmed track with no thumb
    _USCR-CH @ _USCR-VH @ <= IF
        CELL-A-DIM DRW-ATTR!
        _USCR-TRACK-CP _UR-ROW @ _UR-COL @ _UR-W @ + 1-
        _UR-H @ DRW-VLINE
        DRW-STYLE-RESTORE EXIT
    THEN
    \ Compute thumb height: max(1, visible * track / content)
    _USCR-VH @ _UR-H @ * _USCR-CH @ /
    1 MAX _USCR-TH !
    \ Compute thumb position: offset * (track - thumb) / (content - visible)
    _USCR-SO @
    _UR-H @ _USCR-TH @ -               ( offset track-avail )
    *                                    ( offset*avail )
    _USCR-CH @ _USCR-VH @ -            ( offset*avail max-scroll )
    DUP 0= IF DROP DROP 0 ELSE / THEN  ( thumb-top )
    _USCR-TP !
    \ Draw track column: DRW-VLINE ( cp row col len -- )
    _UR-COL @ _UR-W @ + 1-             ( track-col )
    CELL-A-DIM DRW-ATTR!
    _USCR-TRACK-CP _UR-ROW @ 2 PICK _UR-H @ DRW-VLINE
    \ Draw thumb over track
    DRW-STYLE-RESTORE
    _USCR-THUMB-CP _UR-ROW @ _USCR-TP @ + 2 PICK _USCR-TH @ DRW-VLINE
    DROP                                \ drop track-col
    DRW-STYLE-RESTORE ;

\ --- NOP ---
: _UTUI-RENDER-NOP  ( elem -- ) DROP ;

\ Root <uidl> render — fill bg so overlay-close repaint clears stale cells.
: _UTUI-RENDER-ROOT  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP
    _UTUI-FILL-BG ;

\ =====================================================================
\  §6 — Event Handler Words (event-xt implementations)
\ =====================================================================
\
\  Signature: ( elem key-ev -- handled? )

: _UTUI-H-NOP  ( elem key-ev -- 0 ) 2DROP 0 ;

\ Action: Enter/Space activates
: _UTUI-H-ACTION  ( elem key-ev -- handled? )
    KEY-CODE@                          ( elem code )
    DUP KEY-ENTER = OVER 32 = OR IF   ( elem code )
        DROP                           ( elem )
        _UTUI-FIRE-DO
        -1 EXIT
    THEN
    2DROP 0 ;

\ Input: delegate to materialized INP widget
: _UTUI-H-INPUT  ( elem key-ev -- handled? )
    OVER _UTUI-SIDECAR                    ( elem ev sc )
    DUP _UTUI-SC-WPTR@                    ( elem ev sc wptr )
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    >R                                     ( elem ev sc  R: wptr )
    DUP R@ _UTUI-SYNC-WFOCUS
    _UTUI-SYNC-PROXY
    NIP R>                                 ( ev wptr )
    _INP-HANDLE ;

\ Toggle: Enter/Space toggles
: _UTUI-H-TOGGLE  ( elem key-ev -- handled? )
    KEY-CODE@                          ( elem code )
    DUP KEY-ENTER = OVER 32 = OR IF
        DROP                           ( elem )
        DUP _UTUI-DISPLAY-TEXT
        S" true" STR-STR=             ( elem flag )
        IF S" false" ELSE S" true" THEN ( elem sa sl )
        UIDL-BIND-WRITE               \ ( ) — UIDL-BIND-WRITE( elem va vl -- )
        -1 EXIT
    THEN
    2DROP 0 ;

\ --- Menu event handler ---
\
\ Forward-declared words from later sections needed by the menu impl.
DEFER _UTUI-FINALIZE-MENU-D  ( elem -- )
' DROP IS _UTUI-FINALIZE-MENU-D

DEFER _UTUI-FOCUS-D  ( -- elem | 0 )
' NOOP IS _UTUI-FOCUS-D

DEFER _UTUI-FOCUS!-D  ( elem -- )
' DROP IS _UTUI-FOCUS!-D

DEFER _UTUI-FOCUS-NEXT-D  ( -- )
' NOOP IS _UTUI-FOCUS-NEXT-D

DEFER _UTUI-FOCUS-PREV-D  ( -- )
' NOOP IS _UTUI-FOCUS-PREV-D

DEFER _UTUI-DIRTY-SUBTREE-D  ( elem -- )
' DROP IS _UTUI-DIRTY-SUBTREE-D

DEFER _UTUI-DIRTY-RECT-D  ( row col h w -- )
: _udr-drop4  2DROP 2DROP ;
' _udr-drop4 IS _UTUI-DIRTY-RECT-D

DEFER _UTUI-DO-LAYOUT-REC-D  ( elem -- )
' DROP IS _UTUI-DO-LAYOUT-REC-D

\ Saved original sidecar geometry (1-row label from menubar layout)
VARIABLE _UTUI-MENU-SAVE-ROW
VARIABLE _UTUI-MENU-SAVE-H
VARIABLE _UTUI-MENU-SAVE-W
VARIABLE _UTUI-MENU-SAVE-Z

: _UTUI-MENU-STATE-CLEAR  ( -- )
    0 _UTUI-MENU-OPEN !
    0 _UTUI-MENU-SAVED-FOC !
    0 _UTUI-MENU-SAVE-ROW !
    0 _UTUI-MENU-SAVE-H !
    0 _UTUI-MENU-SAVE-W !
    0 _UTUI-MENU-SAVE-Z ! ;

\ Close the currently-open menu dropdown.
: _UTUI-MENU-CLOSE  ( -- )
    _UTUI-MENU-OPEN @ DUP 0= IF DROP EXIT THEN
    \ Hide item sidecars (clear VIS before dirty-rect walk)
    DUP UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-VIS INVERT AND SWAP _UTUI-SC-FLAGS!
        UIDL-NEXT-SIB
    REPEAT DROP
    \ Dirty the actual open rectangle.  Item text may have changed since the
    \ menu opened, so remeasurement would not necessarily describe the cells
    \ that must be repainted.
    DUP _UTUI-SIDECAR >R
    R@ _UTUI-SC-ROW@
    R@ _UTUI-SC-COL@
    R@ _UTUI-SC-H@
    R> _UTUI-SC-W@
    _UTUI-DIRTY-RECT-D
    \ Restore original 1-row geometry and its authored/base z-index.
    DUP _UTUI-SIDECAR
    _UTUI-MENU-SAVE-ROW @ OVER _UTUI-SC-ROW!
    _UTUI-MENU-SAVE-H @   OVER _UTUI-SC-H!
    _UTUI-MENU-SAVE-W @   OVER _UTUI-SC-W!
    _UTUI-MENU-SAVE-Z @ SWAP TSC-SET-ZIDX!
    \ Dirty the menubar so the highlight updates
    UIDL-PARENT ?DUP IF UIDL-DIRTY! THEN
    0 _UTUI-MENU-OPEN !
    \ Restore saved focus
    _UTUI-MENU-SAVED-FOC @ ?DUP IF
        DUP _UTUI-SIDECAR _UTUI-SC-VIS? IF _UTUI-FOCUS!-D
        ELSE DROP THEN
    THEN
    0 _UTUI-MENU-SAVED-FOC ! ;

\ Open a menu dropdown.
: _UTUI-MENU-OPEN!  ( menu-elem -- )
    _UTUI-MENU-OPEN @ IF _UTUI-MENU-CLOSE THEN
    _UTUI-FOCUS-D _UTUI-MENU-SAVED-FOC !
    DUP _UTUI-MENU-OPEN !
    \ Finalization is separate from the installed flow-layout XT.  At event
    \ time the menu still has its fully resolved compact label rectangle.
    DUP _UTUI-FINALIZE-MENU-D
    \ Dirty everything so the dropdown paints
    DUP _UTUI-DIRTY-SUBTREE-D
    DUP UIDL-DIRTY!
    UIDL-PARENT ?DUP IF UIDL-DIRTY! THEN ;

\ Toggle: click same menu closes, different opens
: _UTUI-MENU-TOGGLE  ( menu-elem -- )
    DUP _UTUI-MENU-OPEN @ = IF
        DROP _UTUI-MENU-CLOSE
    ELSE
        _UTUI-MENU-OPEN!
    THEN ;

\ Find first <item> child of an open menu
: _UTUI-MENU-FIRST-ITEM  ( -- item | 0 )
    _UTUI-MENU-OPEN @ ?DUP 0= IF 0 EXIT THEN
    UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-MENU-NAVIGABLE? IF EXIT THEN
        UIDL-NEXT-SIB
    REPEAT ;

\ Find last <item> child of an open menu
: _UTUI-MENU-LAST-ITEM  ( -- item | 0 )
    _UTUI-MENU-OPEN @ ?DUP 0= IF 0 EXIT THEN
    UIDL-LAST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-MENU-NAVIGABLE? IF EXIT THEN
        UIDL-PREV-SIB
    REPEAT ;

\ Move to next/prev sibling within the open dropdown
: _UTUI-MENU-ITEM-NEXT  ( -- )
    _UTUI-FOCUS-D DUP 0= IF DROP EXIT THEN
    BEGIN UIDL-NEXT-SIB DUP 0<> WHILE
        DUP _UTUI-MENU-NAVIGABLE? IF _UTUI-FOCUS!-D EXIT THEN
    REPEAT DROP
    \ Wrap to first item
    _UTUI-MENU-FIRST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN ;

: _UTUI-MENU-ITEM-PREV  ( -- )
    _UTUI-FOCUS-D DUP 0= IF DROP EXIT THEN
    BEGIN UIDL-PREV-SIB DUP 0<> WHILE
        DUP _UTUI-MENU-NAVIGABLE? IF _UTUI-FOCUS!-D EXIT THEN
    REPEAT DROP
    \ Wrap to last item
    _UTUI-MENU-LAST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN ;

: _UTUI-MENU-AVAILABLE?  ( menu -- flag )
    DUP UIDL-TYPE UIDL-T-MENU <> IF DROP 0 EXIT THEN
    _UTUI-SIDECAR _UTUI-SC-VIS? ;

\ Switch to the next/prev <menu> in the bar
: _UTUI-MENU-SWITCH-NEXT  ( -- )
    _UTUI-MENU-OPEN @ ?DUP 0= IF EXIT THEN
    BEGIN UIDL-NEXT-SIB DUP 0<> WHILE
        DUP _UTUI-MENU-AVAILABLE? IF
            _UTUI-MENU-OPEN!
            _UTUI-MENU-FIRST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN
            EXIT
        THEN
    REPEAT DROP ;

: _UTUI-MENU-SWITCH-PREV  ( -- )
    _UTUI-MENU-OPEN @ ?DUP 0= IF EXIT THEN
    BEGIN UIDL-PREV-SIB DUP 0<> WHILE
        DUP _UTUI-MENU-AVAILABLE? IF
            _UTUI-MENU-OPEN!
            _UTUI-MENU-FIRST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN
            EXIT
        THEN
    REPEAT DROP ;

\ <menu> key handler: Enter/Space/Down opens; Esc closes; arrows navigate
: _UTUI-H-MENU  ( elem key-ev -- handled? )
    KEY-CODE@                          ( elem code )
    DUP KEY-ENTER = OVER 32 = OR IF
        DROP
        DUP _UTUI-MENU-OPEN @ = IF
            DROP _UTUI-MENU-CLOSE
        ELSE
            _UTUI-MENU-OPEN!
            _UTUI-MENU-FIRST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN
        THEN
        -1 EXIT
    THEN
    DUP KEY-DOWN = IF
        2DROP
        _UTUI-MENU-OPEN @ 0= IF EXIT THEN
        _UTUI-MENU-FIRST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN
        -1 EXIT
    THEN
    DUP KEY-ESC = IF
        2DROP _UTUI-MENU-CLOSE -1 EXIT
    THEN
    DUP KEY-RIGHT = IF
        2DROP
        _UTUI-MENU-OPEN @ IF
            _UTUI-MENU-SWITCH-NEXT
        ELSE
            _UTUI-FOCUS-NEXT-D
        THEN
        -1 EXIT
    THEN
    DUP KEY-LEFT = IF
        2DROP
        _UTUI-MENU-OPEN @ IF
            _UTUI-MENU-SWITCH-PREV
        ELSE
            _UTUI-FOCUS-PREV-D
        THEN
        -1 EXIT
    THEN
    2DROP 0 ;

\ <item> key handler: Enter/Space fires do=; arrows navigate
: _UTUI-H-ITEM  ( elem key-ev -- handled? )
    KEY-CODE@                          ( elem code )
    DUP KEY-ENTER = OVER 32 = OR IF
        DROP _UTUI-FIRE-DO
        _UTUI-MENU-CLOSE -1 EXIT
    THEN
    DUP KEY-DOWN = IF
        2DROP _UTUI-MENU-ITEM-NEXT -1 EXIT
    THEN
    DUP KEY-UP = IF
        2DROP _UTUI-MENU-ITEM-PREV -1 EXIT
    THEN
    DUP KEY-ESC = IF
        2DROP _UTUI-MENU-CLOSE -1 EXIT
    THEN
    DUP KEY-RIGHT = IF
        2DROP _UTUI-MENU-SWITCH-NEXT -1 EXIT
    THEN
    DUP KEY-LEFT = IF
        2DROP _UTUI-MENU-SWITCH-PREV -1 EXIT
    THEN
    2DROP 0 ;

\ Textarea: delegate to materialized TXTA widget
: _UTUI-H-TEXTAREA  ( elem key-ev -- handled? )
    OVER _UTUI-SIDECAR                    ( elem ev sc )
    DUP _UTUI-SC-WPTR@                    ( elem ev sc wptr )
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    >R                                     ( elem ev sc  R: wptr )
    DUP R@ _UTUI-SYNC-WFOCUS
    _UTUI-SYNC-PROXY
    NIP R>                                 ( ev wptr )
    _TXTA-HANDLE ;
: _UTUI-H-LIST     ( elem key-ev -- handled? ) 2DROP 0 ;
: _UTUI-H-DIALOG   ( elem key-ev -- handled? ) 2DROP 0 ;
: _UTUI-H-CANVAS   ( elem key-ev -- handled? ) 2DROP 0 ;

\ Region / group: delegate to mounted widget via generic WDG-HANDLE
: _UTUI-H-REGION  ( elem key-ev -- handled? )
    OVER _UTUI-SIDECAR                    ( elem ev sc )
    DUP _UTUI-SC-WPTR@                    ( elem ev sc wptr )
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    >R                                     ( elem ev sc  R: wptr )
    DUP R@ _UTUI-SYNC-WFOCUS
    _UTUI-SYNC-PROXY
    NIP R>                                 ( ev wptr )
    WDG-HANDLE ;

\ Scroll container: forward keyboard events to child's widget
: _UTUI-H-SCROLL  ( elem key-ev -- handled? )
    OVER UIDL-FIRST-CHILD DUP 0= IF
        DROP 2DROP 0 EXIT
    THEN
    NIP SWAP                               ( child ev )
    OVER _UTUI-SIDECAR                     ( child ev csc )
    DUP _UTUI-SC-WPTR@                     ( child ev csc wptr )
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    >R                                      ( child ev csc  R: wptr )
    DUP R@ _UTUI-SYNC-WFOCUS
    _UTUI-SYNC-PROXY
    NIP R>                                  ( ev wptr )
    WDG-HANDLE ;

\ Tree: delegate to materialized TREE widget's _TREE-HANDLE
: _UTUI-H-TREE  ( elem key-ev -- handled? )
    OVER _UTUI-SIDECAR                    ( elem ev sc )
    DUP _UTUI-SC-WPTR@                    ( elem ev sc wptr )
    DUP 0= IF DROP DROP 2DROP 0 EXIT THEN
    >R _UTUI-SYNC-PROXY                   ( elem ev   R: wptr )
    NIP R>                                 ( ev wptr )
    _TREE-HANDLE ;

\ Tabs: Left/Right to switch active tab
\ After switching, relayout the subtree so child panels resize.
: _UTUI-H-TABS  ( elem key-ev -- handled? )
    KEY-CODE@                              ( elem code )
    OVER _UTUI-SIDECAR _UTUI-SC-WPTR@     ( elem code state )
    DUP 0= IF DROP 2DROP 0 EXIT THEN
    >R                                      ( elem code  R: state )
    DUP KEY-LEFT = IF
        DROP
        R@ @ 0> IF
            R@ @ 1- R@ !
            DUP _UTUI-DO-LAYOUT-REC-D
            UIDL-DIRTY! R> DROP -1 EXIT
        THEN
        DROP R> DROP 0 EXIT
    THEN
    DUP KEY-RIGHT = IF
        DROP
        R@ @ 1+                            ( elem next )
        OVER UIDL-NCHILDREN                ( elem next nch )
        < IF
            R@ @ 1+ R@ !
            DUP _UTUI-DO-LAYOUT-REC-D
            UIDL-DIRTY! R> DROP -1 EXIT
        THEN
        DROP R> DROP 0 EXIT
    THEN
    DROP DROP R> DROP 0 ;

\ =====================================================================
\  §7 — Layout Words (layout-xt implementations)
\ =====================================================================
\
\  All layout words use dedicated temp VARIABLEs (_UL-*) to avoid
\  stack gymnastics — this is the KDOS pattern for complex computations.

VARIABLE _UL-ELEM
VARIABLE _UL-SC
VARIABLE _UL-ROW
VARIABLE _UL-COL
VARIABLE _UL-W
VARIABLE _UL-H
VARIABLE _UL-POS
VARIABLE _UL-LEAF-ROWS   \ pre-counted leaf row total

\ Helper: should this element get height=1 in stack layout?
\ Fixed-height (leaf) → -1;  expandable → 0.
\ status/toolbar:  always 1-row (leaf-like).
\ textarea/canvas: always expandable (need vertical space).
\ action:          invisible → treated as leaf (1-row).
\ Everything else: containers expand, leaves get 1 row.
: _UL-IS-LEAF?  ( elem -- flag )
    DUP UIDL-TYPE DUP UIDL-T-STATUS = SWAP UIDL-T-TOOLBAR = OR
    OVER UIDL-TYPE UIDL-T-MENUBAR = OR
    IF DROP -1 EXIT THEN
    DUP UIDL-TYPE UIDL-T-TEXTAREA = IF DROP 0 EXIT THEN
    DUP UIDL-TYPE UIDL-T-CANVAS   = IF DROP 0 EXIT THEN
    UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
        ED.FLAGS @ EL-CONTENT-MODEL
        DUP EL-CONTAINER = OVER EL-FIXED-2 = OR
        OVER EL-FIXED-1 = OR
        OVER EL-COLLECTION = OR IF DROP 0 ELSE DROP -1 THEN
    ELSE -1 THEN ;

\ Helper: action elements are invisible layout-wise (key bindings).
\   Also skips positioned elements (absolute/fixed) pulled out of flow
\   and display:none elements (HIDE flag set by pre-layout style pass).
: _UL-SKIP-LAYOUT?  ( elem -- flag )
    DUP UIDL-TYPE UIDL-T-ACTION = IF DROP -1 EXIT THEN
    DUP _UTUI-SIDECAR _UTUI-SC-FLAGS@ _UTUI-SCF-HIDE AND IF DROP -1 EXIT THEN
    _UTUI-SIDECAR _UTUI-SC-POS@ 0<> ;

\ Helper: adjust _UL-ROW/COL/W/H content area by parent padding.
\   Call after loading _UL-ROW/COL/W/H from parent sidecar.
\   Does nothing when padding is 0 (fast path).
VARIABLE _ULP-T  VARIABLE _ULP-R  VARIABLE _ULP-B  VARIABLE _ULP-L

: _UL-APPLY-PAD  ( -- )
    _UL-SC @ _UTUI-SC-PAD@            ( packed )
    DUP 0= IF DROP EXIT THEN          \ fast path: no padding
    _UTUI-UNPACK-TRBL                  ( pt pr pb pl )
    _ULP-L !  _ULP-B !  _ULP-R !  _ULP-T !
    _ULP-T @  _UL-ROW +!              \ row += padding-top
    _ULP-L @  _UL-COL +!              \ col += padding-left
    _UL-W @  _ULP-L @ -  _ULP-R @ -  DUP 0< IF DROP 0 THEN  _UL-W !
    _UL-H @  _ULP-T @ -  _ULP-B @ -  DUP 0< IF DROP 0 THEN  _UL-H ! ;

\ Temp vars for child margin during layout
VARIABLE _ULM-T  VARIABLE _ULM-R  VARIABLE _ULM-B  VARIABLE _ULM-L

\ Helper: read child sidecar margin into _ULM-* vars. Zero if none.
: _UL-READ-CHILD-MARGIN  ( csc -- )
    _UTUI-SC-MARGIN@
    DUP 0= IF DROP
        0 _ULM-T !  0 _ULM-R !  0 _ULM-B !  0 _ULM-L !
    ELSE
        _UTUI-UNPACK-TRBL  _ULM-L !  _ULM-B !  _ULM-R !  _ULM-T !
    THEN ;

\ --- Stack layout (vertical) ---
\  Two-pass: first count leaf rows, then give containers the remainder.
: _UTUI-LAYOUT-STACK  ( elem -- )
    _UL-ELEM !
    _UL-ELEM @ _UTUI-SIDECAR _UL-SC !
    _UL-SC @ _UTUI-SC-ROW@ _UL-ROW !
    _UL-SC @ _UTUI-SC-COL@ _UL-COL !
    _UL-SC @ _UTUI-SC-W@   _UL-W !
    _UL-SC @ _UTUI-SC-H@   _UL-H !
    _UL-APPLY-PAD                      \ adjust content area for padding
    _UL-ROW @ _UL-POS !

    \ Pass 1: count rows consumed by leaf children (skip actions)
    0 _UL-ELEM @ UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UIDL-EVAL-WHEN IF
            DUP _UL-SKIP-LAYOUT? 0= IF
                DUP _UL-IS-LEAF? IF SWAP 1+ SWAP THEN
            THEN
        THEN
        UIDL-NEXT-SIB
    REPEAT DROP
    _UL-LEAF-ROWS !

    \ Pass 2: assign positions (actions get 0-height)
    _UL-ELEM @ UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-SIDECAR             ( child csc )
        OVER UIDL-EVAL-WHEN IF
            OVER _UL-SKIP-LAYOUT? IF
                \ Action/positioned: give it sidecar flags but 0 height
                _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
                _UL-POS @ OVER _UTUI-SC-ROW!
                _UL-COL @ OVER _UTUI-SC-COL!
                0 OVER _UTUI-SC-W!
                0 OVER _UTUI-SC-H!
                DROP
            ELSE
                DUP _UL-READ-CHILD-MARGIN
                _ULM-T @ _UL-POS +!       \ advance pos by margin-top

                _UTUI-SCF-HAS _UTUI-SCF-VIS OR
                    OVER _UTUI-SC-LAYOUT-FLAGS!
                _UL-POS @ OVER _UTUI-SC-ROW!
                _UL-COL @ _ULM-L @ + OVER _UTUI-SC-COL!
                _UL-W @ _ULM-L @ - _ULM-R @ -
                DUP 0< IF DROP 0 THEN
                OVER _UTUI-SC-W!
                \ Height: 1 for leaf, remaining (minus leaf rows) for containers
                OVER _UL-IS-LEAF? IF
                    1
                ELSE
                    _UL-H @ _UL-LEAF-ROWS @ -
                    _UL-POS @ _UL-ROW @ - -
                    DUP 1 < IF DROP 1 THEN
                THEN
                OVER _UTUI-SC-H!
                DROP                       ( child )
                DUP _UTUI-SIDECAR _UTUI-SC-H@ _UL-POS +!
                _ULM-B @ _UL-POS +!       \ advance pos by margin-bottom
            THEN
        ELSE
            _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
            DROP                       ( child )
        THEN
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

\ --- Flex layout (horizontal) ---
VARIABLE _UL-CW   \ child width for flex

: _UTUI-LAYOUT-FLEX  ( elem -- )
    _UL-ELEM !
    _UL-ELEM @ _UTUI-SIDECAR _UL-SC !
    _UL-SC @ _UTUI-SC-ROW@ _UL-ROW !
    _UL-SC @ _UTUI-SC-COL@ _UL-COL !
    _UL-SC @ _UTUI-SC-W@   _UL-W !
    _UL-SC @ _UTUI-SC-H@   _UL-H !
    _UL-APPLY-PAD                      \ adjust content area for padding
    _UL-COL @ _UL-POS !

    \ Count visible children
    0 _UL-ELEM @ UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UIDL-EVAL-WHEN IF SWAP 1+ SWAP THEN
        UIDL-NEXT-SIB
    REPEAT DROP                        ( count )
    DUP 0= IF DROP EXIT THEN
    _UL-W @ SWAP / _UL-CW !           ( )

    _UL-ELEM @ UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-SIDECAR             ( child csc )
        OVER UIDL-EVAL-WHEN IF
            DUP _UL-READ-CHILD-MARGIN
            _ULM-L @ _UL-POS +!       \ advance pos by margin-left

            _UTUI-SCF-HAS _UTUI-SCF-VIS OR
                OVER _UTUI-SC-LAYOUT-FLAGS!
            _UL-ROW @ _ULM-T @ + OVER _UTUI-SC-ROW!
            _UL-POS @ OVER _UTUI-SC-COL!
            _UL-CW @ _ULM-L @ - _ULM-R @ -
            DUP 0< IF DROP 0 THEN
            OVER _UTUI-SC-W!
            _UL-H @ _ULM-T @ - _ULM-B @ -
            DUP 0< IF DROP 0 THEN
            OVER _UTUI-SC-H!
            DROP                       ( child )
            _UL-CW @ _ULM-R @ + _UL-POS +!  \ advance by width + margin-right
        ELSE
            _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
            DROP                       ( child )
        THEN
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

\ --- Menubar layout: assign sidecar coords matching the renderer ---
\ Each <menu> child occupies 1 row, its width = label-length + 2
\ (matching the 2-char gap the renderer advances by).
: _UTUI-LAYOUT-MBAR  ( elem -- )
    _UL-ELEM !
    _UL-ELEM @ _UTUI-SIDECAR _UL-SC !
    _UL-SC @ _UTUI-SC-ROW@ _UL-ROW !
    _UL-SC @ _UTUI-SC-COL@ _UL-COL !
    _UL-COL @ 1+ _UL-POS !            \ column cursor (matches renderer)
    _UL-ELEM @ UIDL-FIRST-CHILD       ( child | 0 )
    BEGIN DUP 0<> WHILE
        DUP _UTUI-SIDECAR             ( child csc )
        OVER S" label" UIDL-ATTR IF   ( child csc la ll )
            NIP _UL-CW !              ( child csc )
            _UTUI-SCF-HAS _UTUI-SCF-VIS OR
                OVER _UTUI-SC-LAYOUT-FLAGS!
            _UL-ROW @ OVER _UTUI-SC-ROW!
            _UL-POS @ OVER _UTUI-SC-COL!
            _UL-CW @ 2 + OVER _UTUI-SC-W!
            1 OVER _UTUI-SC-H!
            _UL-CW @ 2 + _UL-POS +!
            DROP                       ( child )
        ELSE                           ( child csc )
            _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
            DROP                       ( child )
        THEN
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

\ --- Menu layout and final resolved dropdown pass ---
\ Flow layout leaves every menu in its compact menubar-label rectangle.  The
\ canonical post-style pass finalizes the one open menu only after authored
\ width/height/z and positioned geometry have all been resolved.
: _UTUI-LAYOUT-MENU  ( elem -- )  DROP ;

: _UTUI-FINALIZE-MENU  ( elem -- )
    DUP _UTUI-MENU-OPEN @ <> IF DROP EXIT THEN
    \ Preserve the fully resolved compact rectangle for close, then derive the
    \ overlay rectangle exactly once.
    DUP _UTUI-SIDECAR _UTUI-SC-ROW@ _UTUI-MENU-SAVE-ROW !
    DUP _UTUI-SIDECAR _UTUI-SC-H@   _UTUI-MENU-SAVE-H !
    DUP _UTUI-SIDECAR _UTUI-SC-W@   _UTUI-MENU-SAVE-W !
    DUP _UTUI-SIDECAR _UTUI-SC-ZIDX@ _UTUI-MENU-SAVE-Z !
    DUP _UTUI-MENU-MEASURE
    DUP _UTUI-SIDECAR _UTUI-SC-ROW@ 1+ OVER _UTUI-SIDECAR _UTUI-SC-ROW!
    _UMD-ICNT @ 2 + OVER _UTUI-SIDECAR _UTUI-SC-H!
    _UMD-MAXW @ 4 + OVER _UTUI-SIDECAR _UTUI-SC-W!
    200 OVER _UTUI-SIDECAR TSC-SET-ZIDX!
    DUP _UTUI-SIDECAR _UTUI-SC-COL@ _UMD-COL !
    DUP _UTUI-SIDECAR _UTUI-SC-ROW@ _UMD-ROW !
    _UMD-MAXW @ 2 +                    ( elem item-w )
    0                                  ( elem item-w idx )
    2 PICK UIDL-FIRST-CHILD            ( elem item-w idx child )
    BEGIN DUP 0<> WHILE
        DUP _UTUI-MENU-ROW? IF
            DUP _UTUI-MENU-NAVIGABLE? 0= IF
                DUP _UTUI-FOCUS-D = IF 0 _UTUI-FOCUS!-D THEN
            THEN
            DUP _UTUI-SIDECAR         ( ... child sc )
            _UTUI-SCF-HAS _UTUI-SCF-VIS OR
                OVER _UTUI-SC-LAYOUT-FLAGS!
            _UMD-ROW @ 3 PICK 1+ +
                OVER _UTUI-SC-ROW!     \ row = dropdown_top+1+idx
            _UMD-COL @ 1+
                OVER _UTUI-SC-COL!     \ col = dropdown_col+1
            3 PICK OVER _UTUI-SC-W!    \ w = item-w
            1 OVER _UTUI-SC-H!         \ h = 1
            DROP                       ( elem item-w idx child )
            UIDL-NEXT-SIB SWAP 1+ SWAP
                                        ( elem item-w idx+1 next )
        ELSE
            \ Fail closed if admission changed since the previous layout.
            DUP _UTUI-FOCUS-D = IF 0 _UTUI-FOCUS!-D THEN
            DUP _UTUI-SIDECAR         ( ... child sc )
            _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
            0 OVER _UTUI-SC-ROW!
            0 OVER _UTUI-SC-COL!
            0 OVER _UTUI-SC-W!
            0 OVER _UTUI-SC-H!
            DROP UIDL-NEXT-SIB        ( elem item-w idx next )
        THEN
    REPEAT
    DROP DROP DROP DROP
    \ If relayout removed the focused row, keep keyboard authority inside the
    \ open menu only by choosing its first still-admitted item.
    _UTUI-FOCUS-D 0= IF
        _UTUI-MENU-FIRST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN
    THEN ;

\ Resolve the event-handler forward declaration.  The same finalizer is called
\ directly by canonical relayout after the positioned pass.
' _UTUI-FINALIZE-MENU IS _UTUI-FINALIZE-MENU-D

\ --- Status / toolbar: lay out children horizontally ---
: _UTUI-LAYOUT-STATUS  ( elem -- ) _UTUI-LAYOUT-FLEX ;
: _UTUI-LAYOUT-TOOLBAR ( elem -- ) _UTUI-LAYOUT-FLEX ;

\ --- Tabs: 2-row header, only active tab child visible ---
: _UTUI-LAYOUT-TABS  ( elem -- )
    _UL-ELEM !
    _UL-ELEM @ _UTUI-SIDECAR _UL-SC !
    _UL-SC @ _UTUI-SC-ROW@ _UL-ROW !
    _UL-SC @ _UTUI-SC-COL@ _UL-COL !
    _UL-SC @ _UTUI-SC-W@   _UL-W !
    _UL-SC @ _UTUI-SC-H@   _UL-H !
    _UL-APPLY-PAD                      \ adjust content area for padding

    \ Get active tab index from wptr state (default 0)
    _UL-SC @ _UTUI-SC-WPTR@
    DUP IF @ ELSE DROP 0 THEN
    _UL-POS !                          \ reuse _UL-POS as active idx

    0 _UL-ELEM @ UIDL-FIRST-CHILD     ( idx child )
    BEGIN DUP 0<> WHILE
        DUP _UTUI-SIDECAR             ( idx child csc )
        OVER UIDL-EVAL-WHEN IF
            _UTUI-SCF-HAS _UTUI-SCF-VIS OR
                OVER _UTUI-SC-LAYOUT-FLAGS!
            2 PICK _UL-POS @ = IF
                \ Active tab: content area below header (row+2, col, w, h-2)
                _UL-ROW @ 2 + OVER _UTUI-SC-ROW!
                _UL-COL @     OVER _UTUI-SC-COL!
                _UL-W @       OVER _UTUI-SC-W!
                _UL-H @ 2 - DUP 0< IF DROP 0 THEN OVER _UTUI-SC-H!
            ELSE
                \ Inactive: zero dimensions (effectively hidden)
                0 OVER _UTUI-SC-ROW!
                0 OVER _UTUI-SC-COL!
                0 OVER _UTUI-SC-W!
                0 OVER _UTUI-SC-H!
            THEN
        ELSE
            _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
        THEN
        DROP                           ( idx child )
        UIDL-NEXT-SIB
        SWAP 1+ SWAP                   ( idx+1 next )
    REPEAT
    DROP DROP ;

\ --- Split layout: divide by ratio= ---
VARIABLE _USP-ELEM  VARIABLE _USP-SC
VARIABLE _USP-RATIO VARIABLE _USP-LW  VARIABLE _USP-RW
VARIABLE _USP-ROW   VARIABLE _USP-COL  VARIABLE _USP-SW  VARIABLE _USP-SH

\ Helper: read split parent sidecar dims + apply padding
: _USP-READ-PAD  ( -- )
    _USP-SC @ _UTUI-SC-ROW@ _USP-ROW !
    _USP-SC @ _UTUI-SC-COL@ _USP-COL !
    _USP-SC @ _UTUI-SC-W@   _USP-SW !
    _USP-SC @ _UTUI-SC-H@   _USP-SH !
    _USP-SC @ _UTUI-SC-PAD@
    DUP 0= IF DROP EXIT THEN
    _UTUI-UNPACK-TRBL  _ULP-L !  _ULP-B !  _ULP-R !  _ULP-T !
    _ULP-T @  _USP-ROW +!
    _ULP-L @  _USP-COL +!
    _USP-SW @  _ULP-L @ -  _ULP-R @ -  DUP 0< IF DROP 0 THEN  _USP-SW !
    _USP-SH @  _ULP-T @ -  _ULP-B @ -  DUP 0< IF DROP 0 THEN  _USP-SH ! ;

: _UTUI-LAYOUT-SPLIT  ( elem -- )
    _USP-ELEM !
    _USP-ELEM @ _UTUI-SIDECAR _USP-SC !
    _USP-SC @ _UTUI-SC-VIS? 0= IF EXIT THEN
    _USP-READ-PAD

    \ Read ratio= (default 50)
    _USP-ELEM @ S" ratio" UIDL-ATTR IF
        STR>NUM 0= IF DROP 50 THEN
    ELSE 2DROP 50 THEN
    _USP-RATIO !

    \ Compute left/right widths
    _USP-SW @
    DUP _USP-RATIO @ * 100 / _USP-LW !
    _USP-LW @ - 1 -
    DUP 0< IF DROP 0 THEN
    _USP-RW !

    \ First child = left pane
    _USP-ELEM @ UIDL-FIRST-CHILD
    DUP 0= IF DROP EXIT THEN
    DUP _UTUI-SIDECAR                 ( child1 sc1 )
    OVER UIDL-EVAL-WHEN IF            \ OVER gets child1 (elem), not sc1
        _UTUI-SCF-HAS _UTUI-SCF-VIS OR
            OVER _UTUI-SC-LAYOUT-FLAGS!
        _USP-ROW @ OVER _UTUI-SC-ROW!
        _USP-COL @ OVER _UTUI-SC-COL!
        _USP-LW @              OVER _UTUI-SC-W!
        _USP-SH @              OVER _UTUI-SC-H!
    ELSE
        _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
    THEN
    DROP                               ( child1 )

    \ Second child = right pane
    UIDL-NEXT-SIB
    DUP 0= IF DROP EXIT THEN
    DUP _UTUI-SIDECAR                 ( child2 sc2 )
    OVER UIDL-EVAL-WHEN IF
        _UTUI-SCF-HAS _UTUI-SCF-VIS OR
            OVER _UTUI-SC-LAYOUT-FLAGS!
        _USP-ROW @                                    OVER _UTUI-SC-ROW!
        _USP-COL @ _USP-LW @ + 1 +                   OVER _UTUI-SC-COL!
        _USP-RW @                                     OVER _UTUI-SC-W!
        _USP-SH @                                     OVER _UTUI-SC-H!
    ELSE
        _UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!
    THEN
    2DROP ;

\ --- Dialog layout: centered overlay ---
VARIABLE _UDL-DLG-SC

: _UTUI-LAYOUT-DLG  ( elem -- )
    DUP _UTUI-SIDECAR _UDL-DLG-SC !
    _UDL-DLG-SC @ _UTUI-SC-VIS? 0= IF DROP EXIT THEN

    \ Dialog dimensions: 60% width (min 10), children+4 height (5–20)
    _UTUI-RGN @ RGN-W 60 * 100 /
    10 MAX _UDL-DLG-SC @ _UTUI-SC-W!
    DUP UIDL-NCHILDREN 4 + 5 MAX 20 MIN
    _UDL-DLG-SC @ _UTUI-SC-H!
    \ Center in root region
    _UTUI-RGN @ RGN-H _UDL-DLG-SC @ _UTUI-SC-H@ - 2/ DUP 0< IF DROP 0 THEN
    _UTUI-RGN @ RGN-ROW +
    _UDL-DLG-SC @ _UTUI-SC-ROW!
    _UTUI-RGN @ RGN-W _UDL-DLG-SC @ _UTUI-SC-W@ - 2/ DUP 0< IF DROP 0 THEN
    _UTUI-RGN @ RGN-COL +
    _UDL-DLG-SC @ _UTUI-SC-COL!
    \ Layout children inside dialog (stack)
    _UTUI-LAYOUT-STACK ;

\ --- Scroll: reserve 1 col for scrollbar track on child ---
: _UTUI-LAYOUT-SCROLL  ( elem -- )
    DUP _UTUI-SIDECAR _UTUI-SC-W@ 2 < IF
        _UTUI-LAYOUT-STACK EXIT         \ too narrow for track
    THEN
    \ Temporarily reduce own width by 1 for child layout
    DUP _UTUI-SIDECAR DUP _UTUI-SC-W@  ( elem sc w )
    1- OVER _UTUI-SC-W!                 ( elem sc )
    SWAP _UTUI-LAYOUT-STACK             ( sc )
    \ Restore full width so render sees the track column
    DUP _UTUI-SC-W@ 1+ SWAP _UTUI-SC-W! ;

\ --- Generic layout dispatcher based on arrange= ---
: _UTUI-LAYOUT-DISPATCH  ( elem -- )
    DUP UIDL-ARRANGE
    DUP UIDL-A-STACK = IF DROP _UTUI-LAYOUT-STACK EXIT THEN
    DUP UIDL-A-FLEX  = IF DROP _UTUI-LAYOUT-FLEX  EXIT THEN
    DUP UIDL-A-DOCK  = IF DROP _UTUI-LAYOUT-STACK EXIT THEN
    DUP UIDL-A-FLOW  = IF DROP _UTUI-LAYOUT-FLEX  EXIT THEN
    DUP UIDL-A-GRID  = IF DROP _UTUI-LAYOUT-FLEX  EXIT THEN
    DROP _UTUI-LAYOUT-STACK ;

\ =====================================================================
\  §7b — Positioned Element Resolution
\ =====================================================================
\
\  After layout + style resolution, resolve absolute/fixed positioned
\  elements.  These were skipped during flow layout (§7).
\  - absolute: row/col relative to parent sidecar + offsets
\  - fixed:    row/col relative to root region + offsets
\  Width/height default to parent's content area if not explicitly set.

VARIABLE _UPO-SC    VARIABLE _UPO-PSC
VARIABLE _UPO-POS   VARIABLE _UPO-W   VARIABLE _UPO-H
VARIABLE _UPO-OT  VARIABLE _UPO-OR  VARIABLE _UPO-OB  VARIABLE _UPO-OL

: _UTUI-RESOLVE-POS-ELEM  ( elem -- )
    DUP _UTUI-SIDECAR DUP _UTUI-SC-POS@      ( elem sc pos )
    DUP 0= IF 2DROP DROP EXIT THEN            \ static → skip
    _UPO-POS !  _UPO-SC !                     ( elem )

    \ Mark as layout-visible (positioned elements were skipped in flow).
    \ Runtime hiding remains an independent AUX6 predicate.
    _UTUI-SCF-HAS _UTUI-SCF-VIS OR
    _UPO-SC @ _UTUI-SC-LAYOUT-FLAGS!

    \ Determine reference frame
    _UPO-POS @ 2 = IF                         \ fixed → root region
        _UTUI-RGN @ RGN-ROW  _UPO-SC @ _UTUI-SC-ROW!
        _UTUI-RGN @ RGN-COL  _UPO-SC @ _UTUI-SC-COL!
        _UTUI-RGN @ RGN-W    _UPO-W !
        _UTUI-RGN @ RGN-H    _UPO-H !
    ELSE                                      \ absolute → parent sidecar
        DUP UIDL-PARENT ?DUP IF
            _UTUI-SIDECAR _UPO-PSC !
            _UPO-PSC @ _UTUI-SC-ROW@ _UPO-SC @ _UTUI-SC-ROW!
            _UPO-PSC @ _UTUI-SC-COL@ _UPO-SC @ _UTUI-SC-COL!
            _UPO-PSC @ _UTUI-SC-W@   _UPO-W !
            _UPO-PSC @ _UTUI-SC-H@   _UPO-H !
        ELSE
            _UTUI-RGN @ RGN-ROW  _UPO-SC @ _UTUI-SC-ROW!
            _UTUI-RGN @ RGN-COL  _UPO-SC @ _UTUI-SC-COL!
            _UTUI-RGN @ RGN-W    _UPO-W !
            _UTUI-RGN @ RGN-H    _UPO-H !
        THEN
    THEN
    DROP                                      \ drop elem

    \ Unpack offsets
    _UPO-SC @ _UTUI-SC-OFFS@ _UTUI-UNPACK-OFFS
    _UPO-OL !  _UPO-OB !  _UPO-OR !  _UPO-OT !

    \ Row = base-row + top offset
    _UPO-OT @ _UPO-SC @ _UTUI-SC-ROW@ + _UPO-SC @ _UTUI-SC-ROW!

    \ Col = base-col + left offset
    _UPO-OL @ _UPO-SC @ _UTUI-SC-COL@ + _UPO-SC @ _UTUI-SC-COL!

    \ Width: use CSS width if set, else compute from left+right or parent
    _UPO-SC @ _UTUI-SC-W@ 0= IF
        _UPO-W @ _UPO-OL @ - _UPO-OR @ -
        DUP 1 < IF DROP 1 THEN
        _UPO-SC @ _UTUI-SC-W!
    THEN

    \ Height: use CSS height if set, else compute from top+bottom or parent
    _UPO-SC @ _UTUI-SC-H@ 0= IF
        _UPO-H @ _UPO-OT @ - _UPO-OB @ -
        DUP 1 < IF DROP 1 THEN
        _UPO-SC @ _UTUI-SC-H!
    THEN ;

\ Walk all elements and resolve positioned ones
: _UTUI-RESOLVE-POSITIONED  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _UTUI-RESOLVE-POS-ELEM
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF
                        FALSE
                    ELSE DROP 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ =====================================================================
\  §8 — XT Installation
\ =====================================================================
\
\  Uses EL-SET-RENDER / EL-SET-EVENT / EL-SET-LAYOUT (uidl.f public
\  API) with UIDL-T-* type-id constants.  External code (applets,
\  plugins) uses the same API to register custom element behaviour
\  without modifying any library file.

: UTUI-INSTALL-XTS  ( -- )
    \ --- Render XTs ---
    ['] _UTUI-RENDER-LABEL     UIDL-T-LABEL      EL-SET-RENDER
    ['] _UTUI-RENDER-ACTION    UIDL-T-ACTION     EL-SET-RENDER
    ['] _UTUI-RENDER-INPUT     UIDL-T-INPUT      EL-SET-RENDER
    ['] _UTUI-RENDER-SEP       UIDL-T-SEPARATOR  EL-SET-RENDER
    ['] _UTUI-RENDER-REGION    UIDL-T-REGION     EL-SET-RENDER
    ['] _UTUI-RENDER-REGION    UIDL-T-GROUP      EL-SET-RENDER
    ['] _UTUI-RENDER-MBAR      UIDL-T-MENUBAR    EL-SET-RENDER
    ['] _UTUI-RENDER-MENU      UIDL-T-MENU       EL-SET-RENDER
    ['] _UTUI-RENDER-ITEM      UIDL-T-ITEM       EL-SET-RENDER
    ['] _UTUI-RENDER-STATUS    UIDL-T-STATUS     EL-SET-RENDER
    ['] _UTUI-RENDER-TOOLBAR   UIDL-T-TOOLBAR    EL-SET-RENDER
    ['] _UTUI-RENDER-DLG       UIDL-T-DIALOG     EL-SET-RENDER
    ['] _UTUI-RENDER-SPLIT     UIDL-T-SPLIT      EL-SET-RENDER
    ['] _UTUI-RENDER-TABS      UIDL-T-TABS       EL-SET-RENDER
    ['] _UTUI-RENDER-TOGGLE    UIDL-T-TOGGLE     EL-SET-RENDER
    ['] _UTUI-RENDER-INDICATOR UIDL-T-INDICATOR  EL-SET-RENDER
    ['] _UTUI-RENDER-LIST      UIDL-T-COLLECTION EL-SET-RENDER
    ['] _UTUI-RENDER-TREE      UIDL-T-TREE       EL-SET-RENDER
    ['] _UTUI-RENDER-TEXTAREA  UIDL-T-TEXTAREA   EL-SET-RENDER
    ['] _UTUI-RENDER-SCROLL    UIDL-T-SCROLL     EL-SET-RENDER
    ['] _UTUI-RENDER-CANVAS    UIDL-T-CANVAS     EL-SET-RENDER
    ['] _UTUI-RENDER-NOP       UIDL-T-TEMPLATE   EL-SET-RENDER
    ['] _UTUI-RENDER-NOP       UIDL-T-EMPTY      EL-SET-RENDER
    ['] _UTUI-RENDER-NOP       UIDL-T-REP        EL-SET-RENDER
    ['] _UTUI-RENDER-NOP       UIDL-T-OPTION     EL-SET-RENDER
    ['] _UTUI-RENDER-NOP       UIDL-T-META       EL-SET-RENDER
    ['] _UTUI-RENDER-ROOT      UIDL-T-UIDL       EL-SET-RENDER

    \ --- Event XTs ---
    ['] _UTUI-H-ACTION         UIDL-T-ACTION     EL-SET-EVENT
    ['] _UTUI-H-INPUT          UIDL-T-INPUT      EL-SET-EVENT
    ['] _UTUI-H-TOGGLE         UIDL-T-TOGGLE     EL-SET-EVENT
    ['] _UTUI-H-MENU           UIDL-T-MENU       EL-SET-EVENT
    ['] _UTUI-H-ITEM           UIDL-T-ITEM       EL-SET-EVENT
    ['] _UTUI-H-TEXTAREA       UIDL-T-TEXTAREA   EL-SET-EVENT
    ['] _UTUI-H-LIST           UIDL-T-COLLECTION EL-SET-EVENT
    ['] _UTUI-H-TREE           UIDL-T-TREE       EL-SET-EVENT
    ['] _UTUI-H-TABS           UIDL-T-TABS       EL-SET-EVENT
    ['] _UTUI-H-DIALOG         UIDL-T-DIALOG     EL-SET-EVENT
    ['] _UTUI-H-CANVAS         UIDL-T-CANVAS     EL-SET-EVENT
    ['] _UTUI-H-REGION         UIDL-T-REGION     EL-SET-EVENT
    ['] _UTUI-H-REGION         UIDL-T-GROUP      EL-SET-EVENT
    ['] _UTUI-H-SCROLL         UIDL-T-SCROLL     EL-SET-EVENT

    \ --- Layout XTs ---
    ['] _UTUI-LAYOUT-DISPATCH  UIDL-T-REGION     EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-DISPATCH  UIDL-T-GROUP      EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-MBAR      UIDL-T-MENUBAR    EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-MENU      UIDL-T-MENU       EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-STATUS    UIDL-T-STATUS     EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-TOOLBAR   UIDL-T-TOOLBAR    EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-DLG       UIDL-T-DIALOG     EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-SPLIT     UIDL-T-SPLIT      EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-TABS      UIDL-T-TABS       EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-SCROLL    UIDL-T-SCROLL     EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-DISPATCH  UIDL-T-TAB        EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-DISPATCH  UIDL-T-UIDL       EL-SET-LAYOUT
;

UTUI-INSTALL-XTS

\ =====================================================================
\  §9 — Focus Management
\ =====================================================================

: UTUI-FOCUS  ( -- elem | 0 )  _UTUI-FOCUS-P @ ;

\ Dirty element, and walk up to the nearest ancestor that owns a
\ real render-xt.  Container renders like _UTUI-RENDER-MBAR paint
\ children on their behalf, so they must re-render when a child's
\ visual state (e.g. focus) changes.
: _UTUI-FOCUS-DIRTY  ( elem -- )
    BEGIN
        DUP UIDL-DIRTY!
        DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
            ED.RENDER-XT @ ['] NOOP <>
        ELSE 0 THEN
        IF DROP EXIT THEN              \ has own render — stop
        UIDL-PARENT DUP 0=
    UNTIL DROP ;

: UTUI-FOCUS!  ( elem -- )
    \ Clear old focus
    _UTUI-FOCUS-P @ ?DUP IF
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-FOC INVERT AND SWAP _UTUI-SC-FLAGS!
        _UTUI-FOCUS-DIRTY
    THEN
    \ Set new
    DUP _UTUI-FOCUS-P !
    ?DUP IF
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-FOC OR SWAP _UTUI-SC-FLAGS!
        _UTUI-FOCUS-DIRTY
    THEN ;

: _UTUI-DFS-NEXT  ( elem -- next | 0 )
    DUP UIDL-FIRST-CHILD ?DUP IF NIP EXIT THEN
    BEGIN
        DUP UIDL-NEXT-SIB ?DUP IF NIP EXIT THEN
        UIDL-PARENT DUP 0=
    UNTIL ;

: _UTUI-DFS-PREV  ( elem -- prev | 0 )
    DUP UIDL-PREV-SIB ?DUP IF
        NIP
        BEGIN DUP UIDL-LAST-CHILD ?DUP IF NIP ELSE EXIT THEN AGAIN
    THEN
    UIDL-PARENT ;

: _UTUI-FOCUSABLE?  ( elem -- flag )
    DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
        ED.FLAGS @ EL-FOCUSABLE? IF
            _UTUI-SIDECAR _UTUI-SC-VIS?
        ELSE
            \ Not inherently focusable — but a mounted widget makes it so
            _UTUI-SIDECAR DUP _UTUI-SC-WPTR@ IF
                _UTUI-SC-VIS?
            ELSE DROP 0 THEN
        THEN
    ELSE DROP 0 THEN ;

VARIABLE _UF-START

: UTUI-FOCUS-NEXT  ( -- )
    UTUI-FOCUS DUP 0= IF
        DROP UIDL-ROOT ?DUP 0= IF EXIT THEN
    THEN
    DUP _UF-START !
    BEGIN
        _UTUI-DFS-NEXT
        DUP 0= IF DROP UIDL-ROOT THEN
        DUP _UTUI-FOCUSABLE? IF
            UTUI-FOCUS! EXIT
        THEN
        DUP _UF-START @ =
    UNTIL
    DROP ;

: UTUI-FOCUS-PREV  ( -- )
    UTUI-FOCUS DUP 0= IF
        DROP UIDL-ROOT ?DUP 0= IF EXIT THEN
        BEGIN DUP UIDL-LAST-CHILD ?DUP WHILE NIP REPEAT
    THEN
    DUP _UF-START !
    BEGIN
        _UTUI-DFS-PREV
        DUP 0= IF
            DROP UIDL-ROOT
            BEGIN DUP UIDL-LAST-CHILD ?DUP WHILE NIP REPEAT
        THEN
        DUP _UTUI-FOCUSABLE? IF
            UTUI-FOCUS! EXIT
        THEN
        DUP _UF-START @ =
    UNTIL
    DROP ;

\ =====================================================================
\  §10 — Hit Testing
\ =====================================================================

VARIABLE _UHT-BEST
VARIABLE _UHT-ROW
VARIABLE _UHT-COL
VARIABLE _UHT-SC

: UTUI-HIT-TEST  ( row col -- elem | 0 )
    _UHT-COL ! _UHT-ROW !
    0 _UHT-BEST !
    UIDL-ROOT ?DUP 0= IF 0 EXIT THEN
    BEGIN
        DUP _UTUI-SIDECAR _UHT-SC !   \ stash sidecar
        _UHT-SC @ _UTUI-SC-VIS? IF
            _UHT-SC @ _UTUI-SC-ROW@ _UHT-ROW @ <=
            _UHT-SC @ _UTUI-SC-ROW@ _UHT-SC @ _UTUI-SC-H@ + _UHT-ROW @ > AND
            _UHT-SC @ _UTUI-SC-COL@ _UHT-COL @ <= AND
            _UHT-SC @ _UTUI-SC-COL@ _UHT-SC @ _UTUI-SC-W@ + _UHT-COL @ > AND
            IF DUP _UHT-BEST ! THEN
        THEN
        \ DFS advance
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF
                        FALSE          \ continue to check parent's next-sib
                    ELSE DROP 0 TRUE THEN   \ no parent → done, push sentinel
                THEN
            UNTIL
            DUP 0= IF DROP _UHT-BEST @ EXIT THEN
        THEN
    AGAIN ;

\ =====================================================================
\  §11 — Tree Walk & Layout
\ =====================================================================

: _UTUI-DO-LAYOUT-REC  ( elem -- )
    DUP 0= IF DROP EXIT THEN

    DUP UIDL-EVAL-WHEN IF
        DUP _UTUI-SIDECAR
        _UTUI-SCF-HAS _UTUI-SCF-VIS OR SWAP
        _UTUI-SC-LAYOUT-FLAGS!
    ELSE
        DUP _UTUI-SIDECAR
        _UTUI-SCF-HAS SWAP _UTUI-SC-LAYOUT-FLAGS!
        DROP EXIT
    THEN

    \ Call layout-xt
    DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
        ED.LAYOUT-XT @ DUP ['] NOOP <> IF
            OVER SWAP EXECUTE
        ELSE DROP THEN
    THEN

    \ Recurse into children
    DUP UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-DO-LAYOUT-REC
        UIDL-NEXT-SIB
    REPEAT
    DROP

    UIDL-DIRTY! ;

\ Reset every derived field that the canonical relayout pipeline recomputes.
\ Widget pointers, ownership, runtime visibility, focus, and explicit-hidden
\ state remain mounted.  display:none, geometry, box data, offsets, and packed
\ style are rebuilt from the current UIDL attributes.
: _UTUI-RESET-RESOLVED-ELEM  ( elem -- )
    _UTUI-SIDECAR >R
    0 R@ _UTUI-SC-ROW!
    0 R@ _UTUI-SC-COL!
    0 R@ _UTUI-SC-H!
    0 R@ _UTUI-SC-W!
    0 R@ _UTUI-SC-STYLE!
    0 R@ _UTUI-SC-PAD!
    0 R@ _UTUI-SC-OFFS!
    0 R@ _UTUI-SC-MARGIN!
    R@ _UTUI-SC-FLAGS@
    _UTUI-SCF-HAS _UTUI-SCF-FOC OR TSC-F-HIDDEN OR AND
    R> _UTUI-SC-FLAGS! ;

: _UTUI-RESET-RESOLVED  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _UTUI-RESET-RESOLVED-ELEM
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF FALSE
                    ELSE DROP 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ The style passes are defined after the layout engine because they depend on
\ its helpers.  Deferred entry points let every relayout run one canonical
\ pipeline without moving those sections or duplicating the initial-load path.
DEFER _UTUI-PRELAYOUT-STYLES-D  ( -- )
' NOOP IS _UTUI-PRELAYOUT-STYLES-D
DEFER _UTUI-RESOLVE-STYLES-D  ( -- )
' NOOP IS _UTUI-RESOLVE-STYLES-D

: UTUI-RELAYOUT  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN

    \ Resolve layout-affecting declarations before reseeding the root and
    \ walking flow layout.  Derived projection state never observes the
    \ stale pre-layout or pre-positioned sidecars of a later relayout.
    _UTUI-RESET-RESOLVED
    _UTUI-PRELAYOUT-STYLES-D

    _UTUI-SIDECAR
    _UTUI-RGN @ RGN-ROW OVER _UTUI-SC-ROW!
    _UTUI-RGN @ RGN-COL OVER _UTUI-SC-COL!
    _UTUI-RGN @ RGN-W   OVER _UTUI-SC-W!
    _UTUI-RGN @ RGN-H   OVER _UTUI-SC-H!
    _UTUI-DEFAULT-STYLE  OVER _UTUI-SC-STYLE!
    _UTUI-SCF-HAS _UTUI-SCF-VIS OR SWAP _UTUI-SC-LAYOUT-FLAGS!

    UIDL-ROOT _UTUI-DO-LAYOUT-REC
    _UTUI-RESOLVE-STYLES-D
    _UTUI-RESOLVE-POSITIONED
    _UTUI-MENU-OPEN @ ?DUP IF _UTUI-FINALIZE-MENU THEN
    \ Optional projections observe only fully resolved UIDL geometry.
    _UTUI-PROJECTION-RELAYOUT DROP ;

\ =====================================================================
\ Resolve forward references that need _UTUI-DO-LAYOUT-REC
' _UTUI-DO-LAYOUT-REC IS _UTUI-DO-LAYOUT-REC-D

\  §12 — Subscription Wiring
\ =====================================================================

: _UTUI-WIRE-SUBS  ( -- )
    UIDL-RESET-SUBS
    _UTUI-SHORT-CLEAR
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP UIDL-BIND IF               ( elem ba bl )
            2 PICK -ROT UIDL-SUBSCRIBE \ UIDL-SUBSCRIBE( elem bind-a bind-l -- )
        ELSE 2DROP THEN                 \ UIDL-BIND returned (0 0 0): drop 0 0
        DUP _UTUI-REG-SHORTCUT
        \ DFS advance
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF
                        FALSE
                    ELSE DROP 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ =====================================================================
\  §13 — Paint (Z-Ordered Repaint)
\ =====================================================================
\
\  Two-pass paint:
\    Pass 1: Paint all normal-flow elements (z-index == 0 and not dialog).
\            Defer elements with z-index > 0 or type=dialog to overlay buf.
\            Skip entire subtree of deferred elements.
\    Pass 2: Sort overlay buffer by z-index ascending, paint each as a
\            full subtree (element + all descendants in tree order).

32 CONSTANT _UTUI-MAX-OVERLAYS
CREATE _UTUI-OVERLAY-BUF  _UTUI-MAX-OVERLAYS 2 * CELLS ALLOT  \ pairs: (elem, z-index)
VARIABLE _UTUI-OVERLAY-CNT

\ Add element to overlay buffer for deferred painting
: _UTUI-DEFER-OVERLAY  ( elem z-index -- )
    _UTUI-OVERLAY-CNT @ _UTUI-MAX-OVERLAYS >= IF 2DROP EXIT THEN
    _UTUI-OVERLAY-CNT @ 2 * CELLS _UTUI-OVERLAY-BUF +
    SWAP OVER 8 + !                    \ store z-index at +8
    !                                  \ store elem at +0
    1 _UTUI-OVERLAY-CNT +! ;

\ Paint a single element (calls its render-xt).  Neutral UIDL, LEL, and state
\ observations stay held until the hook has consumed every borrowed span and
\ the same element has been marked clean.  Semantic scratch writers enter
\ through UIDL first, so the outer UIDL observation also pins that scratch.
: _UTUI-RENDER-ONE-BODY  ( elem -- )
    DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
        ED.RENDER-XT @ DUP ['] NOOP <> IF
            OVER SWAP EXECUTE
        ELSE DROP THEN
    THEN
    UIDL-CLEAN! ;

: _UTUI-RENDER-ONE-IN-STATE  ( elem -- )
    _UTUI-RENDER-ONE-BODY ;

: _UTUI-RENDER-ONE-IN-LEL  ( elem -- )
    ['] _UTUI-RENDER-ONE-IN-STATE ST-OBSERVE ;

: _UTUI-RENDER-ONE-IN-UIDL  ( elem -- )
    ['] _UTUI-RENDER-ONE-IN-LEL LEL-OBSERVE ;

: _UTUI-RENDER-ONE  ( elem -- )
    ['] _UTUI-RENDER-ONE-IN-UIDL UIDL-OBSERVE ;

\ Parent renderers own and clear their full rectangles.  Ensure their
\ direct children repaint later in the same DFS pass so clean child
\ content is not erased by a parent-only update.
: _UTUI-DIRTY-CHILDREN  ( elem -- )
    UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UE.FLAGS DUP @ UIDL-F-DIRTY OR SWAP !
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

\ --- Paint entire subtree (element + all descendants) ---
\ Used in Pass 2 for overlay elements that were deferred from Pass 1.
\ Does NOT re-defer elements — all descendants paint unconditionally.
VARIABLE _UPST-ROOT

: _UTUI-PAINT-SUBTREE-NEXT  ( elem -- next | 0 )
    BEGIN
        DUP _UPST-ROOT @ = IF DROP 0 EXIT THEN
        DUP UIDL-NEXT-SIB ?DUP IF NIP EXIT THEN
        UIDL-PARENT DUP 0= IF EXIT THEN
    AGAIN ;

: _UTUI-PAINT-SUBTREE  ( elem -- )
    DUP _UPST-ROOT !
    BEGIN
        DUP _UTUI-SIDECAR _UTUI-SC-VIS? 0= IF
            DUP UIDL-CLEAN!
            _UTUI-PAINT-SUBTREE-NEXT
        ELSE
            DUP _UTUI-RENDER-ONE
            DUP UIDL-TYPE UIDL-T-MENU =
            OVER _UTUI-MENU-OPEN @ <> AND IF
                _UTUI-PAINT-SUBTREE-NEXT
            ELSE
                DUP UIDL-FIRST-CHILD ?DUP IF NIP
                ELSE _UTUI-PAINT-SUBTREE-NEXT THEN
            THEN
        THEN
        DUP 0= IF DROP EXIT THEN
    AGAIN ;

\ --- Skip-children flag ---
\ Set by _UTUI-PAINT-ELEM when an element is deferred to the overlay
\ buffer; tells the Pass 1 DFS to skip the element's subtree.
VARIABLE _UTUI-SKIP-CHILDREN

: _UTUI-PAINT-ELEM  ( elem -- )
    0 _UTUI-SKIP-CHILDREN !
    \ Always skip children of non-open <menu> elements — their items
    \ have no valid coordinates.  Open menus have z-index>0 and will
    \ be deferred+skipped by the z-index check below anyway.
    DUP UIDL-TYPE UIDL-T-MENU = IF
        DUP _UTUI-MENU-OPEN @ <> IF
            -1 _UTUI-SKIP-CHILDREN !
        THEN
    THEN
    DUP _UTUI-SIDECAR _UTUI-SC-VIS? 0= IF
        -1 _UTUI-SKIP-CHILDREN !
        UIDL-CLEAN! EXIT
    THEN
    DUP UIDL-DIRTY? 0= IF DROP EXIT THEN
    \ Defer dialogs (always painted on top)
    DUP UIDL-TYPE UIDL-T-DIALOG = IF
        DUP _UTUI-SIDECAR _UTUI-SC-ZIDX@
        DUP 0= IF DROP 255 THEN         \ dialogs default to z-index 255
        _UTUI-DEFER-OVERLAY
        -1 _UTUI-SKIP-CHILDREN !
        EXIT
    THEN
    \ Defer elements with z-index > 0
    DUP _UTUI-SIDECAR _UTUI-SC-ZIDX@ DUP 0<> IF
        _UTUI-DEFER-OVERLAY
        -1 _UTUI-SKIP-CHILDREN !
        EXIT
    THEN DROP
    DUP _UTUI-DIRTY-CHILDREN
    _UTUI-RENDER-ONE ;

\ --- DFS advance past subtree ---
\ Advance to the next sibling (or ancestor's sibling), skipping all
\ descendants.  Returns 0 when the tree is exhausted.
: _UTUI-SKIP-SUBTREE  ( elem -- next | 0 )
    BEGIN
        DUP UIDL-NEXT-SIB ?DUP IF NIP EXIT THEN
        UIDL-PARENT DUP 0=
    UNTIL ;

\ Simple insertion-sort overlay buffer by z-index (ascending)
: _UTUI-SORT-OVERLAYS  ( -- )
    _UTUI-OVERLAY-CNT @ 2 < IF EXIT THEN
    _UTUI-OVERLAY-CNT @ 1 DO
        I 2 * CELLS _UTUI-OVERLAY-BUF +
        DUP @ SWAP 8 + @              ( elem-i zi-i )
        I 1 - BEGIN
            DUP 0>= IF
                DUP 2 * CELLS _UTUI-OVERLAY-BUF + 8 + @
                2 PICK > IF            \ prev z > current z → shift right
                    DUP 2 * CELLS _UTUI-OVERLAY-BUF +    ( elem zi j entry-j )
                    DUP @  SWAP 8 + @                      ( elem zi j ej zj )
                    3 PICK 1+  2 * CELLS _UTUI-OVERLAY-BUF +
                    SWAP OVER 8 + ! !                      \ copy j → j+1
                    1-
                    -1                 \ continue
                ELSE
                    0                  \ stop
                THEN
            ELSE 0 THEN
        UNTIL                          ( elem zi j )
        1+ 2 * CELLS _UTUI-OVERLAY-BUF +
        SWAP OVER 8 + ! !             \ store elem, zi in final position
    LOOP ;

\ Helper: paint Pass 2 overlay elements if any were deferred.
: _UTUI-PAINT-PASS2  ( -- )
    _UTUI-OVERLAY-CNT @ 0> IF
        _UTUI-SORT-OVERLAYS
        _UTUI-OVERLAY-CNT @ 0 DO
            I 2 * CELLS _UTUI-OVERLAY-BUF + @
            _UTUI-PAINT-SUBTREE
        LOOP
    THEN ;

: _UTUI-PAINT-FINISH  ( -- )
    _UTUI-PAINT-PASS2
    RGN-ROOT ;

\ Helper: walk up from elem to the next sibling of an ancestor.
\ Returns the next DFS node, or 0 if the tree is exhausted.
: _UTUI-PAINT-WALK-UP  ( elem -- next|0 )
    BEGIN
        DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
        ELSE
            UIDL-PARENT DUP IF
                FALSE
            ELSE DROP 0 TRUE THEN
        THEN
    UNTIL ;

: UTUI-PAINT  ( -- )
    _UTUI-DOC-LOADED @ 0= IF EXIT THEN
    \ Publish the derived view while UIDL dirty flags still describe the same
    \ authoritative update that CELL rendering is about to consume.
    \ Projection failure is diagnostic-only here; CELL remains universal.
    _UTUI-PROJECTION-PUBLISH
    \ Direct UIDL rendering uses document-relative coordinates under the
    \ document clip.  Widget proxies temporarily switch to their own absolute
    \ regions and restore this clip before the DFS continues.
    _UTUI-RESTORE-DOC-RGN
    0 _UTUI-OVERLAY-CNT !
    UIDL-ROOT ?DUP 0= IF RGN-ROOT EXIT THEN
    \ Pass 1: normal flow elements (skip subtrees of deferred overlays)
    BEGIN
        DUP _UTUI-PAINT-ELEM
        _UTUI-SKIP-CHILDREN @ IF
            \ Deferred element — skip its entire subtree
            _UTUI-SKIP-SUBTREE
            DUP 0= IF DROP _UTUI-PAINT-FINISH EXIT THEN
        ELSE
            DUP UIDL-FIRST-CHILD ?DUP IF NIP
            ELSE
                _UTUI-PAINT-WALK-UP
                DUP 0= IF DROP _UTUI-PAINT-FINISH EXIT THEN
            THEN
        THEN
    AGAIN ;

\ =====================================================================
\  §14 — Key Dispatch
\ =====================================================================

: UTUI-DISPATCH-KEY  ( ev -- handled? )
    DUP _UR-EV !                       \ save original event pointer
    DUP KEY-CODE@ SWAP KEY-MODS@       ( code mods )

    \ Tab / Shift-Tab
    OVER KEY-TAB = IF
        DUP KEY-MOD-SHIFT AND IF
            2DROP UTUI-FOCUS-PREV -1 EXIT
        ELSE
            2DROP UTUI-FOCUS-NEXT -1 EXIT
        THEN
    THEN

    \ Down / Right → next focusable; Up / Left → prev focusable
    \ Skip arrow focus-nav when the focused element has a mounted widget
    \ (widgets use arrows for internal navigation).
    UTUI-FOCUS DUP IF
        _UTUI-SIDECAR _UTUI-SC-WPTR@
    ELSE DROP 0 THEN
    0= IF
        OVER KEY-DOWN = OVER 0= AND IF
            2DROP UTUI-FOCUS-NEXT -1 EXIT THEN
        OVER KEY-RIGHT = OVER 0= AND IF
            2DROP UTUI-FOCUS-NEXT -1 EXIT THEN
        OVER KEY-UP = OVER 0= AND IF
            2DROP UTUI-FOCUS-PREV -1 EXIT THEN
        OVER KEY-LEFT = OVER 0= AND IF
            2DROP UTUI-FOCUS-PREV -1 EXIT THEN
    THEN

    \ Shortcut table
    2DUP _UTUI-SHORT-MATCH            ( code mods elem|0 )
    ?DUP IF
        NIP NIP
        _UTUI-FIRE-DO -1 EXIT
    THEN

    \ Focused element's event-xt
    UTUI-FOCUS ?DUP IF                ( code mods elem )
        >R 2DROP R>                    ( elem )
        DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
            ED.EVENT-XT @ DUP ['] NOOP <> IF
                >R                     ( elem   R: xt )
                _UR-EV @               ( elem ev   R: xt )
                R>                     ( elem ev xt )
                EXECUTE                ( handled? )
                DUP IF UTUI-FOCUS ?DUP IF UIDL-DIRTY! THEN THEN
                EXIT
            ELSE DROP THEN
        THEN
        \ Enter / Space on focusable elem → fire do= action
        _UR-EV @ KEY-CODE@
        DUP KEY-ENTER = SWAP 32 = OR IF
            _UTUI-FIRE-DO -1 EXIT
        THEN
        DROP 0 EXIT
    THEN
    2DROP 0 ;

\ =====================================================================
\  §15 — Mouse Dispatch
\ =====================================================================

\ --- Tab click helper: map click column to tab index ---
\ _UHT-COL still holds the clicked column from UTUI-HIT-TEST.
VARIABLE _UTC-POS

: _UTUI-TAB-CLICK  ( elem -- )
    DUP _UTUI-SIDECAR                     ( elem sc )
    DUP _UTUI-SC-COL@ 1+ _UTC-POS !       ( elem sc )
    _UTUI-SC-WPTR@ ?DUP 0= IF DROP EXIT THEN  ( elem state )
    >R                                     ( elem   R: state )
    0 SWAP                                 ( idx elem   R: state )
    UIDL-FIRST-CHILD                       ( idx child|0   R: state )
    BEGIN DUP 0<> WHILE
        DUP S" label" UIDL-ATTR IF         ( idx child la ll )
            NIP                            ( idx child ll )
            _UHT-COL @ _UTC-POS @ >=
            _UHT-COL @ _UTC-POS @ 3 PICK 2 + + < AND IF
                                            ( idx child ll )
                DROP DROP                   ( idx   R: state )
                R> !                        ( )
                EXIT
            THEN
            2 + _UTC-POS +!                ( idx child )
        ELSE 2DROP THEN                    ( idx child )
        UIDL-NEXT-SIB
        SWAP 1+ SWAP                       ( idx+1 next )
    REPEAT
    DROP DROP R> DROP ;

\ Scratch event buffer for synthesising mouse events to widgets
CREATE _UDM-EV 3 CELLS ALLOT

: UTUI-DISPATCH-MOUSE  ( row col btn -- handled? )
    \ Ignore mouse release events — only act on press
    DUP KEY-MOUSE-RELEASE = IF
        DROP 2DROP 0 EXIT
    THEN
    DROP                                \ btn unused for now
    UTUI-HIT-TEST                      ( elem | 0 )
    DUP 0= IF
        \ Clicked empty space — close any open menu
        _UTUI-MENU-OPEN @ IF _UTUI-MENU-CLOSE THEN
        EXIT
    THEN
    \ Check if we clicked a <menu> element
    DUP UIDL-TYPE UIDL-T-MENU = IF
        DUP _UTUI-MENU-OPEN @ = IF
            DROP _UTUI-MENU-CLOSE
        ELSE
            DUP UTUI-FOCUS!
            _UTUI-MENU-OPEN!
            _UTUI-MENU-FIRST-ITEM ?DUP IF UTUI-FOCUS! THEN
        THEN
        -1 EXIT
    THEN
    \ Check if we clicked an <item> inside the open menu
    DUP UIDL-TYPE UIDL-T-ITEM = IF
        DUP UIDL-PARENT _UTUI-MENU-OPEN @ = IF
            DUP UTUI-FOCUS!
            _UTUI-FIRE-DO
            _UTUI-MENU-CLOSE -1 EXIT
        THEN
    THEN
    \ Anything else: close menu first, then normal dispatch
    _UTUI-MENU-OPEN @ IF _UTUI-MENU-CLOSE THEN
    \ Tabs: click to switch active tab, relayout subtree
    DUP UIDL-TYPE UIDL-T-TABS = IF
        DUP UTUI-FOCUS!
        DUP _UTUI-TAB-CLICK
        DUP _UTUI-DO-LAYOUT-REC
        UIDL-DIRTY! -1 EXIT
    THEN
    \ Scroll: click on track column → jump scroll
    DUP UIDL-TYPE UIDL-T-SCROLL = IF
        DUP _UTUI-SIDECAR                 ( elem sc )
        DUP _UTUI-SC-COL@ OVER _UTUI-SC-W@ + 1-  ( elem sc track-col )
        _UHT-COL @ = IF                   ( elem sc )
            \ Click is on the scrollbar track
            _USCR-SC !                     ( elem ) \ save sc
            DUP                            ( elem elem )
            _USCR-CHILD-WDG DUP 0= IF     ( elem widget|0 )
                2DROP -1 EXIT
            THEN
            DUP _USCR-SCROLL-INFO          ( elem widget ch so vh )
            _USCR-VH ! DROP _USCR-CH !    ( elem widget )
            _USCR-CH @ _USCR-VH @ -
            DUP 0< IF DROP 0 THEN          ( elem widget max-scroll )
            _UHT-ROW @ _USCR-SC @ _UTUI-SC-ROW@ -
                                            ( elem widget max-scroll rel-row )
            _USCR-SC @ _UTUI-SC-H@        ( elem widget max-scroll rel-row h )
            DUP 0= IF                      \ 0-height guard
                2DROP DROP 0               ( elem widget 0 )
            ELSE >R * R> / THEN            ( elem widget target-offset )
            SWAP _USCR-SCROLL-SET          ( elem )
            _UTUI-DIRTY-SUBTREE-D
            -1 EXIT
        ELSE
            2DROP                          ( -- drop elem sc )
        THEN
        -1 EXIT
    THEN
    DUP _UTUI-FOCUSABLE? IF
        DUP UTUI-FOCUS!
    THEN
    \ If the element has a mounted widget, forward mouse event to it
    DUP _UTUI-SIDECAR DUP _UTUI-SC-WPTR@  ( elem sc wptr )
    ?DUP IF
        >R                                 ( elem sc  R: wptr )
        DUP R@ _UTUI-SYNC-WFOCUS          ( elem sc  R: wptr )
        _UTUI-SYNC-PROXY                   ( elem  R: wptr )
        DROP                               ( R: wptr )
        KEY-T-MOUSE _UDM-EV !
        KEY-MOUSE-LEFT _UDM-EV 8 + !
        _UHT-ROW @ 16 LSHIFT _UHT-COL @ OR _UDM-EV 16 + !
        _UDM-EV R> WDG-HANDLE DROP
    ELSE
        DROP                               ( elem sc -- drop sc )
        _UTUI-FIRE-DO                      ( -- fires do= action )
    THEN
    -1 ;

\ =====================================================================
\  §16 — Overlay Show / Hide
\ =====================================================================
\
\  Generic show/hide for any element (group, dialog, etc.).
\  UTUI-SHOW sets visible + dirties the subtree.
\  UTUI-HIDE clears visible, clears the rect, and dirties elements
\  underneath so they repaint.
\
\  Focus capture: UTUI-SHOW saves focus and moves it to the first
\  focusable element inside the overlay. UTUI-HIDE restores the
\  saved focus.

\ --- Dirty helpers ---

\ Mark element and all descendants dirty.
VARIABLE _UDST-ROOT

: _UTUI-DIRTY-SUBTREE  ( elem -- )
    DUP _UDST-ROOT !
    BEGIN
        DUP UIDL-DIRTY!
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP _UDST-ROOT @ = IF DROP 0 TRUE
                ELSE
                    DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                    ELSE
                        UIDL-PARENT
                        DUP _UDST-ROOT @ = IF DROP 0 TRUE
                        ELSE DUP 0= IF TRUE ELSE FALSE THEN
                        THEN
                    THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ Mark all visible base-layer elements overlapping a rectangle dirty.
\ Used after hiding an overlay to repaint what was underneath.
VARIABLE _UDR-R1   VARIABLE _UDR-C1
VARIABLE _UDR-R2   VARIABLE _UDR-C2
VARIABLE _UDR-SC

: _UTUI-DIRTY-RECT  ( row col h w -- )
    \ Compute exclusive bottom-right
    >R >R                              ( row col  R: w h )
    OVER R> + _UDR-R2 !                 \ r2 = row + h
    DUP  R> + _UDR-C2 !                 \ c2 = col + w
    _UDR-C1 !  _UDR-R1 !               \ r1 = row, c1 = col
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _UTUI-SIDECAR _UDR-SC !
        _UDR-SC @ _UTUI-SC-FLAGS@ _UTUI-SCF-HAS AND IF
            _UDR-SC @ _UTUI-SC-VIS? IF
                \ Overlap iff: er < r2  AND  er+eh > r1  AND  ec < c2  AND  ec+ew > c1
                _UDR-SC @ _UTUI-SC-ROW@  _UDR-R2 @ <
                _UDR-SC @ _UTUI-SC-ROW@ _UDR-SC @ _UTUI-SC-H@ + _UDR-R1 @ >  AND
                _UDR-SC @ _UTUI-SC-COL@  _UDR-C2 @ <  AND
                _UDR-SC @ _UTUI-SC-COL@ _UDR-SC @ _UTUI-SC-W@ + _UDR-C1 @ >  AND
                IF DUP _UTUI-DIRTY-SUBTREE THEN
            THEN
        THEN
        \ DFS advance
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP 0=
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ Resolve menu forward-declared deferred words now that all deps exist
' UTUI-FOCUS          IS _UTUI-FOCUS-D
' UTUI-FOCUS!         IS _UTUI-FOCUS!-D
' UTUI-FOCUS-NEXT     IS _UTUI-FOCUS-NEXT-D
' UTUI-FOCUS-PREV     IS _UTUI-FOCUS-PREV-D
' _UTUI-DIRTY-SUBTREE IS _UTUI-DIRTY-SUBTREE-D
' _UTUI-DIRTY-RECT    IS _UTUI-DIRTY-RECT-D

: _UTUI-DIALOG-DISMISS  ( row col h w -- )
    _UTUI-DIRTY-RECT ;
' _UTUI-DIALOG-DISMISS IS _DLG-DISMISS-HOOK

: _UTUI-DIALOG-BOUNDS  ( -- row col h w )
    _UTUI-RGN @ IF
        _UTUI-RGN @ RGN-ROW
        _UTUI-RGN @ RGN-COL
        _UTUI-RGN @ RGN-H
        _UTUI-RGN @ RGN-W
    ELSE
        0 0 SCR-H SCR-W
    THEN ;
' _UTUI-DIALOG-BOUNDS IS _DLG-BOUNDS-HOOK

\ --- Focus save / restore ---
VARIABLE _UTUI-SAVED-FOCUS     \ stashed focus elem for overlay hide

\ --- Show / hide by element pointer ---

: _UTUI-VIS-SUBTREE!  ( flag elem -- )
    \ Set or clear immediate VIS and the durable runtime-hidden bit on elem +
    \ descendants.  AUX6 survives canonical relayout without masquerading as
    \ CSS display:none or changing layout participation.
    SWAP >R
    DUP _UDST-ROOT !
    BEGIN
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@
        R@ IF _UTUI-SCF-VIS OR ELSE _UTUI-SCF-VIS INVERT AND THEN
        SWAP _UTUI-SC-FLAGS!
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-RUNTIME@
        R@ IF
            _UTUI-RUNTIME-F-HIDDEN INVERT AND
        ELSE
            _UTUI-RUNTIME-F-HIDDEN OR
        THEN
        SWAP _UTUI-SC-RUNTIME!
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP _UDST-ROOT @ = IF DROP 0 TRUE
                ELSE
                    DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                    ELSE
                        UIDL-PARENT
                        DUP _UDST-ROOT @ = IF DROP 0 TRUE
                        ELSE DUP 0= IF TRUE ELSE FALSE THEN
                        THEN
                    THEN
                THEN
            UNTIL
            DUP 0= IF R> DROP DROP EXIT THEN
        THEN
    AGAIN ;

VARIABLE _USH-SC    \ temp sidecar for show/hide
VARIABLE _USH-ROW  VARIABLE _USH-COL
VARIABLE _USH-H    VARIABLE _USH-W

: _UTUI-SHOW-ELEM  ( elem -- )
    \ Save current focus
    UTUI-FOCUS _UTUI-SAVED-FOCUS !
    \ Set VIS on entire subtree + dirty
    DUP -1 SWAP _UTUI-VIS-SUBTREE!
    DUP _UTUI-DIRTY-SUBTREE
    \ Focus first focusable child (if any)
    DUP >R
    BEGIN
        _UTUI-DFS-NEXT
        DUP 0= IF DROP R> DROP EXIT THEN
        DUP R@ = IF DROP R> DROP EXIT THEN
        DUP _UTUI-FOCUSABLE? IF
            UTUI-FOCUS! R> DROP EXIT
        THEN
    AGAIN ;

: _UTUI-HIDE-ELEM  ( elem -- )
    DUP _UTUI-SIDECAR _USH-SC !
    \ Snapshot bounding rect before hiding
    _USH-SC @ _UTUI-SC-ROW@  _USH-ROW !
    _USH-SC @ _UTUI-SC-COL@  _USH-COL !
    _USH-SC @ _UTUI-SC-H@    _USH-H !
    _USH-SC @ _UTUI-SC-W@    _USH-W !
    \ Clear VIS on entire subtree
    DUP 0 SWAP _UTUI-VIS-SUBTREE!
    \ Dirty underlying elements that overlap
    _USH-ROW @ _USH-COL @ _USH-H @ _USH-W @ _UTUI-DIRTY-RECT
    \ Clear the overlay area
    _USH-ROW @ _USH-COL @ _USH-H @ _USH-W @ DRW-CLEAR-RECT
    \ Restore saved focus
    _UTUI-SAVED-FOCUS @ ?DUP IF
        DUP _UTUI-SIDECAR _UTUI-SC-VIS? IF
            UTUI-FOCUS!
        ELSE DROP THEN
    THEN ;

\ --- Public by-ID wrappers ---

: UTUI-SHOW  ( id-a id-l -- )
    UIDL-BY-ID ?DUP IF _UTUI-SHOW-ELEM THEN ;

: UTUI-HIDE  ( id-a id-l -- )
    UIDL-BY-ID ?DUP IF _UTUI-HIDE-ELEM THEN ;

\ --- Legacy dialog wrappers (delegate to generic show/hide) ---

: UTUI-SHOW-DIALOG  ( id-a id-l -- )  UTUI-SHOW ;
: UTUI-HIDE-DIALOG  ( id-a id-l -- )  UTUI-HIDE ;

\ =====================================================================
\  §16a — Widget Materialization
\ =====================================================================
\
\  Walk the UIDL tree after layout; for elements that need widget
\  state (tree, tabs), allocate a widget struct or mini state block
\  and store the pointer in the sidecar's wptr cell (+48).

\ --- Input materialization helper ---
: _UTUI-MAT-INPUT  ( elem -- )
    >R
    R@ _UTUI-SIDECAR _UTUI-SYNC-PROXY
    256 ALLOCATE 0<> ABORT" inp-buf"
    _UTUI-PROXY-RGN OVER 256 INP-NEW
    DUP _UTUI-MAT-W !
    R@ _UTUI-SIDECAR _UTUI-SC-WPTR!
    DROP
    R@ S" text" UIDL-ATTR IF
        _UTUI-MAT-W @ INP-SET-TEXT
    ELSE 2DROP THEN
    R@ S" placeholder" UIDL-ATTR IF
        _UTUI-MAT-W @ INP-SET-PLACEHOLDER
    ELSE 2DROP THEN
    R> DROP ;

\ --- Textarea materialization helper ---
: _UTUI-MAT-TXTA  ( elem -- )
    >R
    R@ _UTUI-SIDECAR _UTUI-SYNC-PROXY
    4096 ALLOCATE 0<> ABORT" txta-buf"
    _UTUI-PROXY-RGN OVER 4096 TXTA-NEW
    DUP _UTUI-MAT-W !
    R@ _UTUI-SIDECAR _UTUI-SC-WPTR!
    DROP
    R@ S" text" UIDL-ATTR IF
        _UTUI-MAT-W @ TXTA-SET-TEXT
    ELSE 2DROP THEN
    R> DROP ;

: _UTUI-MATERIALIZE  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP UIDL-TYPE                  ( elem type )
        DUP UIDL-T-TREE = IF
            DROP
            DUP _UTUI-SIDECAR _UTUI-SYNC-PROXY
            _UTUI-PROXY-RGN OVER
            ['] _UTUI-TREE-CHILD ['] _UTUI-TREE-NEXT
            ['] _UTUI-TREE-LABEL ['] _UTUI-TREE-LEAF?
            TREE-NEW                   ( elem widget )
            OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
        ELSE DUP UIDL-T-TABS = IF
            DROP
            8 ALLOCATE 0<> ABORT" tabs-state"
            DUP 0 SWAP !               ( elem state )
            OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
        ELSE DUP UIDL-T-INPUT = IF
            DROP DUP _UTUI-MAT-INPUT
        ELSE DUP UIDL-T-TEXTAREA = IF
            DROP DUP _UTUI-MAT-TXTA
        ELSE
            DROP                       \ unmatched type
        THEN THEN THEN THEN
        \ DFS advance
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF FALSE
                    ELSE DROP 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

VARIABLE _UDM-ELEM
VARIABLE _UDM-SC
VARIABLE _UDM-WPTR

\ _UTUI-RELEASE-WIDGET ( elem -- )
\   Release UIDL-materialized state, but only detach widgets installed by
\   UTUI-WIDGET-SET.  Those pointers are borrowed from the applet and may
\   name embedded component state rather than an ALLOCATE block.
: _UTUI-RELEASE-WIDGET  ( elem -- )
    DUP _UDM-ELEM !
    _UTUI-SIDECAR DUP _UDM-SC !
    _UTUI-SC-WPTR@ DUP _UDM-WPTR !
    0= IF EXIT THEN
    _UDM-SC @ _UTUI-SC-WOWNER@ _UTUI-WOWNER-CALLER <> IF
        _UDM-ELEM @ UIDL-TYPE
        DUP UIDL-T-TREE = IF
            DROP _UDM-WPTR @ TREE-FREE
        ELSE DUP UIDL-T-INPUT = IF
            DROP
            _UDM-WPTR @ DUP _INP-O-BUF-A + @ FREE
            FREE
        ELSE DUP UIDL-T-TEXTAREA = IF
            DROP
            _UDM-WPTR @ DUP _TXTA-O-BUF-A + @ FREE
            FREE
        ELSE
            DROP _UDM-WPTR @ FREE       \ tabs state, etc.
        THEN THEN THEN
    THEN
    0 _UDM-SC @ _UTUI-SC-WPTR!
    _UTUI-WOWNER-UIDL _UDM-SC @ _UTUI-SC-WOWNER! ;

: _UTUI-DEMATERIALIZE  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _UTUI-RELEASE-WIDGET
        \ DFS advance
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF FALSE
                    ELSE DROP 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ --- Single-element materialize (resolves DEFER from §1c) ---
: _UTUI-DO-MATERIALIZE  ( elem -- )
    DUP UIDL-TYPE                      ( elem type )
    DUP UIDL-T-TREE = IF
        DROP
        DUP _UTUI-SIDECAR _UTUI-SYNC-PROXY
        _UTUI-PROXY-RGN OVER
        ['] _UTUI-TREE-CHILD ['] _UTUI-TREE-NEXT
        ['] _UTUI-TREE-LABEL ['] _UTUI-TREE-LEAF?
        TREE-NEW                       ( elem widget )
        OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
    ELSE DUP UIDL-T-INPUT = IF
        DROP DUP _UTUI-MAT-INPUT
    ELSE DUP UIDL-T-TEXTAREA = IF
        DROP DUP _UTUI-MAT-TXTA
    ELSE DUP UIDL-T-TABS = IF
        DROP
        8 ALLOCATE 0<> ABORT" tabs-state"
        DUP 0 SWAP !
        OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
    ELSE
        DROP
    THEN THEN THEN THEN
    DROP ;
' _UTUI-DO-MATERIALIZE IS _UTUI-MATERIALIZE-ONE

\ --- Single-element dematerialize (resolves DEFER from §1c) ---
: _UTUI-DO-DEMATERIALIZE  ( elem -- )
    _UTUI-RELEASE-WIDGET ;
' _UTUI-DO-DEMATERIALIZE IS _UTUI-DEMATERIALIZE-ONE

\ _UTUI-CSS-INT ( a u -- n flag )
\   Parse a simple integer from a CSS value string.
\   Returns n and -1 if successful, 0 0 otherwise.
: _UTUI-CSS-INT  ( a u -- n flag )
    CSS-PARSE-NUMBER 0= IF 2DROP 0 0 EXIT THEN
    2DROP                        \ discard frac, frac-digits
    -ROT 2DROP                   \ discard remaining string
    -1 ;

\ =====================================================================
\  §16c — Pre-Layout Style Pass
\ =====================================================================
\
\  Before layout, extract layout-affecting CSS properties from style=:
\    position         → style bits 26-27 (affects flow skip)
\    display: none    → flags bit 3 (HIDE — affects visibility/flow)
\    padding          → sidecar +56 (affects content area)
\    margin           → sidecar +72 (affects spacing)
\
\  These must be resolved before layout because the layout engine
\  needs them to compute positions.  Full visual properties (color,
\  text-align, z-index, width/height) are resolved post-layout in §16b.

VARIABLE _UPRE-VA  VARIABLE _UPRE-VL  VARIABLE _UPRE-SC  VARIABLE _UPRE-STY

: _UTUI-PRELAYOUT-ELEM  ( elem -- )
    DUP S" style" UIDL-ATTR 0= IF 2DROP DROP EXIT THEN
    ROT _UTUI-SIDECAR _UPRE-SC !
    _UPRE-VL !  _UPRE-VA !
    _UPRE-SC @ _UTUI-SC-STYLE@  _UPRE-STY !

    \ -- position --
    _UPRE-VA @ _UPRE-VL @
    S" position" CSS-DECL-FIND IF
        2DUP S" absolute" STR-STRI= IF
            2DROP
            _UPRE-STY @  0xC00000000 INVERT AND  0x400000000 OR  _UPRE-STY !
        ELSE 2DUP S" fixed" STR-STRI= IF
            2DROP
            _UPRE-STY @  0xC00000000 INVERT AND  0x800000000 OR  _UPRE-STY !
        ELSE 2DROP THEN THEN
    ELSE 2DROP THEN

    \ -- display --
    _UPRE-VA @ _UPRE-VL @
    S" display" CSS-DECL-FIND IF
        S" none" STR-STRI= IF
            _UPRE-SC @ _UTUI-SC-FLAGS@
            _UTUI-SCF-HIDE OR
            _UPRE-SC @ _UTUI-SC-FLAGS!
        THEN
    ELSE 2DROP THEN

    \ -- padding (shorthand) --
    _UPRE-VA @ _UPRE-VL @
    S" padding" CSS-DECL-FIND IF
        CSS-EXPAND-TRBL DROP             ( t-a t-u r-a r-u b-a b-u l-a l-u )
        _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ left
        _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ bottom
        _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ right
        _UTUI-CSS-INT IF ELSE DROP 0 THEN         \ top
        R> R> R>                                    \ top right bottom left
        _UTUI-PACK-TRBL  _UPRE-SC @ _UTUI-SC-PAD!
    ELSE 2DROP THEN

    \ -- margin (shorthand) --
    _UPRE-VA @ _UPRE-VL @
    S" margin" CSS-DECL-FIND IF
        CSS-EXPAND-TRBL DROP             ( t-a t-u r-a r-u b-a b-u l-a l-u )
        _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ left
        _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ bottom
        _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ right
        _UTUI-CSS-INT IF ELSE DROP 0 THEN         \ top
        R> R> R>                                    \ top right bottom left
        _UTUI-PACK-TRBL  _UPRE-SC @ _UTUI-SC-MARGIN!
    ELSE 2DROP THEN

    \ Write back style (position bits)
    _UPRE-STY @ _UPRE-SC @ _UTUI-SC-STYLE! ;

\ DFS walk: pre-layout style pass
: _UTUI-PRELAYOUT-STYLES  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _UTUI-PRELAYOUT-ELEM
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF
                        FALSE
                    ELSE DROP 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

' _UTUI-PRELAYOUT-STYLES IS _UTUI-PRELAYOUT-STYLES-D

\ =====================================================================
\  §16b — CSS style= Attribute Resolution (Post-Layout)
\ =====================================================================
\
\ After layout, walk the element tree and resolve inline `style=`
\ attributes.  CSS properties supported:
\   color            → fg byte in packed sidecar style
\   background-color → bg byte
\   font-weight:bold → bold bit (bit 16) in attrs
\   width            → sidecar W (absolute or % of parent)
\   height           → sidecar H (absolute or % of parent)
\   text-align       → bits 24-25 in style
\   z-index          → bits 28-35 in style
\   position offsets → sidecar +64 (top/right/bottom/left)
\ Note: position, display, padding, margin are resolved pre-layout (§16c).

VARIABLE _URES-VA    VARIABLE _URES-VL   \ style= value string
VARIABLE _URES-SC                         \ current sidecar
VARIABLE _URES-STYLE                      \ accumulating packed style

\ _UTUI-CSS-SET-FG ( val-a val-u -- )
\   Parse a CSS color value and set fg bits (0-7) of the current style.
: _UTUI-CSS-SET-FG  ( val-a val-u -- )
    TUI-PARSE-COLOR IF
        _URES-STYLE @  0xFFFFFF00 AND  OR  _URES-STYLE !
    ELSE DROP THEN ;

\ _UTUI-CSS-SET-BG ( val-a val-u -- )
\   Parse a CSS color value and set bg bits (8-15) of the current style.
: _UTUI-CSS-SET-BG  ( val-a val-u -- )
    TUI-PARSE-COLOR IF
        8 LSHIFT
        _URES-STYLE @  0xFFFF00FF AND  OR  _URES-STYLE !
    ELSE DROP THEN ;

\ _UTUI-CSS-SET-BOLD ( val-a val-u -- )
\   If value is "bold", set bold bit (bit 16).
: _UTUI-CSS-SET-BOLD  ( val-a val-u -- )
    S" bold" STR-STRI= IF
        _URES-STYLE @  0x10000 OR  _URES-STYLE !
    THEN ;

\ _UTUI-CSS-SET-DIM ( val-a val-u parent-dim offset -- )
\   Parse a CSS dimension value.  If it has a % unit, resolve against
\   parent-dim.  Otherwise treat as absolute integer cells.
\   Store result at sidecar + offset.
VARIABLE _UCD-OFF   VARIABLE _UCD-PDIM

: _UTUI-CSS-SET-DIM  ( val-a val-u parent-dim offset -- )
    _UCD-OFF !  _UCD-PDIM !
    CSS-PARSE-NUMBER 0= IF 2DROP EXIT THEN
    \ ( a' u' int frac frac-digits )
    2DROP                        \ discard frac, frac-digits
    -ROT                         \ ( int a' u' )
    CSS-PARSE-UNIT               \ ( int a'' u'' unit-a unit-u )
    2SWAP 2DROP                  \ ( int unit-a unit-u )
    DUP 1 = IF
        OVER C@ 37 = IF          \ '%'
            2DROP
            _UCD-PDIM @ * 100 /  \ resolve percentage
            DUP 0 <= IF DROP 1 THEN   \ minimum 1 cell
            _URES-SC @  _UCD-OFF @ +  !
            EXIT
        THEN
    THEN
    2DROP                        \ drop unit
    \ Absolute value (integer cells)
    DUP 0 <= IF DROP 1 THEN
    _URES-SC @  _UCD-OFF @ +  ! ;

\ _UTUI-CSS-SET-ALIGN ( val-a val-u -- )
\   Parse text-align value and set bits 32-33 of style.
: _UTUI-CSS-SET-ALIGN  ( val-a val-u -- )
    2DUP S" center" STR-STRI= IF
        2DROP
        _URES-STYLE @  0x300000000 INVERT AND  0x100000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DUP S" right" STR-STRI= IF
        2DROP
        _URES-STYLE @  0x300000000 INVERT AND  0x200000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DROP ;   \ "left" or unknown → 0 (default)

\ _UTUI-CSS-SET-POSITION ( val-a val-u -- )
\   Parse position value and set bits 34-35 of style.
: _UTUI-CSS-SET-POSITION  ( val-a val-u -- )
    2DUP S" absolute" STR-STRI= IF
        2DROP
        _URES-STYLE @  0xC00000000 INVERT AND  0x400000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DUP S" fixed" STR-STRI= IF
        2DROP
        _URES-STYLE @  0xC00000000 INVERT AND  0x800000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DROP ;   \ "static" or unknown → 0 (default)

\ _UTUI-CSS-SET-ZINDEX ( val-a val-u -- )
\   Parse z-index integer (0-255) and set bits 36-43 of style.
: _UTUI-CSS-SET-ZINDEX  ( val-a val-u -- )
    _UTUI-CSS-INT 0= IF DROP EXIT THEN
    DUP 0 < IF DROP 0 THEN
    255 MIN
    36 LSHIFT
    _URES-STYLE @  0xFF000000000 INVERT AND  OR  _URES-STYLE ! ;

\ _UTUI-CSS-SET-PAD ( val-a val-u -- )
\   Parse padding shorthand (1-4 values) and store in sidecar.
: _UTUI-CSS-SET-PAD  ( val-a val-u -- )
    CSS-EXPAND-TRBL DROP             ( t-a t-u r-a r-u b-a b-u l-a l-u )
    _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ left
    _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ bottom
    _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ right
    _UTUI-CSS-INT IF ELSE DROP 0 THEN         \ top
    R> R> R>                                    \ top right bottom left
    _UTUI-PACK-TRBL  _URES-SC @ _UTUI-SC-PAD! ;

\ _UTUI-CSS-SET-MARGIN ( val-a val-u -- )
\   Parse margin shorthand (1-4 values) and store in sidecar.
: _UTUI-CSS-SET-MARGIN  ( val-a val-u -- )
    CSS-EXPAND-TRBL DROP             ( t-a t-u r-a r-u b-a b-u l-a l-u )
    _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ left
    _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ bottom
    _UTUI-CSS-INT IF ELSE DROP 0 THEN >R      \ right
    _UTUI-CSS-INT IF ELSE DROP 0 THEN         \ top
    R> R> R>                                    \ top right bottom left
    _UTUI-PACK-TRBL  _URES-SC @ _UTUI-SC-MARGIN! ;

\ _UTUI-CSS-SET-OFFSET ( val-a val-u shift -- )
\   Parse a position offset (top/right/bottom/left) and merge into
\   the offsets cell at the given 16-bit shift position.
: _UTUI-CSS-SET-OFFSET  ( val-a val-u shift -- )
    >R
    _UTUI-CSS-INT 0= IF DROP R> DROP EXIT THEN
    0xFFFF AND R@ LSHIFT                       \ value in position
    _URES-SC @ _UTUI-SC-OFFS@
    0xFFFF R> LSHIFT INVERT AND                \ clear that slot
    OR
    _URES-SC @ _UTUI-SC-OFFS! ;

\ _UTUI-CSS-SET-DISPLAY ( val-a val-u -- )
\   Parse display property.  "none" sets HIDE flag.
: _UTUI-CSS-SET-DISPLAY  ( val-a val-u -- )
    S" none" STR-STRI= IF
        _URES-SC @ _UTUI-SC-FLAGS@
        _UTUI-SCF-HIDE OR
        _URES-SC @ _UTUI-SC-FLAGS!
    THEN ;

\ _UTUI-RESOLVE-ELEM-STYLE ( elem -- )
\   Read style= attribute, parse CSS declarations, apply to sidecar.
: _UTUI-RESOLVE-ELEM-STYLE  ( elem -- )
    DUP S" style" UIDL-ATTR 0= IF 2DROP DROP EXIT THEN
    \ ( elem val-a val-u ) — inline CSS declarations
    ROT _UTUI-SIDECAR _URES-SC !
    _URES-SC @ _UTUI-SC-STYLE@ _URES-STYLE !
    _URES-VL !  _URES-VA !

    \ -- color (fg) --
    _URES-VA @ _URES-VL @
    S" color" CSS-DECL-FIND IF
        _UTUI-CSS-SET-FG
    ELSE 2DROP THEN

    \ -- background-color (bg) --
    _URES-VA @ _URES-VL @
    S" background-color" CSS-DECL-FIND IF
        _UTUI-CSS-SET-BG
    ELSE 2DROP THEN

    \ -- font-weight --
    _URES-VA @ _URES-VL @
    S" font-weight" CSS-DECL-FIND IF
        _UTUI-CSS-SET-BOLD
    ELSE 2DROP THEN

    \ -- width --
    _URES-VA @ _URES-VL @
    S" width" CSS-DECL-FIND IF
        _URES-SC @ _UTUI-SC-W@               \ parent-dim fallback = own W
        _UTUI-SC-O-W  _UTUI-CSS-SET-DIM
    ELSE 2DROP THEN

    \ -- height --
    _URES-VA @ _URES-VL @
    S" height" CSS-DECL-FIND IF
        _URES-SC @ _UTUI-SC-H@               \ parent-dim fallback = own H
        _UTUI-SC-O-H  _UTUI-CSS-SET-DIM
    ELSE 2DROP THEN

    \ -- text-align --
    _URES-VA @ _URES-VL @
    S" text-align" CSS-DECL-FIND IF
        _UTUI-CSS-SET-ALIGN
    ELSE 2DROP THEN

    \ -- position --
    _URES-VA @ _URES-VL @
    S" position" CSS-DECL-FIND IF
        _UTUI-CSS-SET-POSITION
    ELSE 2DROP THEN

    \ -- z-index --
    _URES-VA @ _URES-VL @
    S" z-index" CSS-DECL-FIND IF
        _UTUI-CSS-SET-ZINDEX
    ELSE 2DROP THEN

    \ -- display --
    _URES-VA @ _URES-VL @
    S" display" CSS-DECL-FIND IF
        _UTUI-CSS-SET-DISPLAY
    ELSE 2DROP THEN

    \ -- padding (shorthand) --
    _URES-VA @ _URES-VL @
    S" padding" CSS-DECL-FIND IF
        _UTUI-CSS-SET-PAD
    ELSE 2DROP THEN

    \ -- margin (shorthand) --
    _URES-VA @ _URES-VL @
    S" margin" CSS-DECL-FIND IF
        _UTUI-CSS-SET-MARGIN
    ELSE 2DROP THEN

    \ -- position offsets: top, right, bottom, left --
    _URES-VA @ _URES-VL @
    S" top" CSS-DECL-FIND IF
        0 _UTUI-CSS-SET-OFFSET
    ELSE 2DROP THEN

    _URES-VA @ _URES-VL @
    S" right" CSS-DECL-FIND IF
        16 _UTUI-CSS-SET-OFFSET
    ELSE 2DROP THEN

    _URES-VA @ _URES-VL @
    S" bottom" CSS-DECL-FIND IF
        32 _UTUI-CSS-SET-OFFSET
    ELSE 2DROP THEN

    _URES-VA @ _URES-VL @
    S" left" CSS-DECL-FIND IF
        48 _UTUI-CSS-SET-OFFSET
    ELSE 2DROP THEN

    \ Write back accumulated style
    _URES-STYLE @ _URES-SC @ _UTUI-SC-STYLE! ;

\ _UTUI-RESOLVE-STYLES-REC ( elem -- )
\   Recursively walk element tree, resolve style= on each node.
\   After resolving this element's own style, propagate inheritable
\   properties (fg, bg, attrs, text-align) to each child's sidecar
\   BEFORE resolving the child's style=, achieving CSS inheritance.
: _UTUI-RESOLVE-STYLES-REC  ( elem -- )
    DUP _UTUI-RESOLVE-ELEM-STYLE
    \ Extract inheritable bits from this (now-resolved) element
    DUP _UTUI-SIDECAR _UTUI-SC-STYLE@
    _UTUI-INHERIT-MASK AND             ( elem inherit )
    SWAP UIDL-FIRST-CHILD              ( inherit child|0 )
    BEGIN DUP 0<> WHILE
        \ Seed child with parent's inheritable bits (preserve child's
        \ non-inheritable bits like position from prelayout)
        DUP _UTUI-SIDECAR              ( inherit child csc )
        DUP _UTUI-SC-STYLE@            ( inherit child csc cstyle )
        _UTUI-INHERIT-MASK INVERT AND  ( inherit child csc non-inherit )
        3 PICK OR                       ( inherit child csc merged )
        SWAP _UTUI-SC-STYLE!           ( inherit child )
        DUP _UTUI-RESOLVE-STYLES-REC
        UIDL-NEXT-SIB
    REPEAT
    2DROP ;

\ _UTUI-RESOLVE-STYLES ( -- )
\   Walk the entire UIDL tree and resolve all style= attributes.
: _UTUI-RESOLVE-STYLES  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    _UTUI-RESOLVE-STYLES-REC ;

' _UTUI-RESOLVE-STYLES IS _UTUI-RESOLVE-STYLES-D

\ =====================================================================
\  §17 — UTUI-LOAD
\ =====================================================================

: UTUI-BY-ID  ( id-a id-l -- elem | 0 )  UIDL-BY-ID ;

\ UTUI-WIDGET@ ( elem -- wptr | 0 )
\   Return the widget pointer associated with a UIDL element, or 0.
: UTUI-WIDGET@  ( elem -- wptr | 0 )
    _UTUI-SIDECAR _UTUI-SC-WPTR@ ;

VARIABLE _UTS-ELEM
VARIABLE _UTS-INDEX

\ UTUI-TAB-SELECT ( index elem -- )
\   Select a UIDL <tabs> child, relayout its subtree, and repaint it.
: UTUI-TAB-SELECT  ( index elem -- )
    _UTS-ELEM ! _UTS-INDEX !
    _UTS-ELEM @ UIDL-NCHILDREN DUP 0= IF DROP EXIT THEN
    1- _UTS-INDEX @ 0 MAX MIN _UTS-INDEX !
    _UTS-ELEM @ _UTUI-SIDECAR _UTUI-SC-WPTR@ ?DUP IF
        _UTS-INDEX @ SWAP !
    THEN
    _UTS-ELEM @ _UTUI-DO-LAYOUT-REC
    _UTS-ELEM @ UIDL-DIRTY!
    _UTUI-NEEDS-PAINT ON ;

\ =====================================================================
\  §17a — Dynamic DOM Mutation (TUI-aware wrappers)
\ =====================================================================

\ UTUI-ADD-ELEM ( parent type -- elem | 0 )
\   Create a new UIDL element, allocate sidecar, resolve style,
\   materialize if widget type.  Marks parent dirty + signals repaint.
: UTUI-ADD-ELEM  ( parent type -- elem | 0 )
    UIDL-ADD-ELEM                      ( elem | 0 )
    DUP 0= IF EXIT THEN
    DUP _UTUI-SC-ALLOC
    DUP _UTUI-INHERIT-PARENT-STYLE
    DUP _UTUI-RESOLVE-ELEM-STYLE
    DUP _UTUI-MATERIALIZE-ONE
    DUP _UTUI-SIDECAR
    DUP _UTUI-SC-FLAGS@ _UTUI-SCF-VIS OR SWAP _UTUI-SC-FLAGS!
    DUP UIDL-PARENT ?DUP IF UIDL-DIRTY! THEN
    _UTUI-NEEDS-PAINT ON ;

: _UTUI-ANCESTOR-OF?  ( ancestor elem -- flag )
    BEGIN
        2DUP = IF 2DROP -1 EXIT THEN
        UIDL-PARENT DUP 0=
    UNTIL
    2DROP 0 ;

\ UTUI-REMOVE-ELEM ( elem -- )
\   Dematerialize, free sidecar, unlink from tree.  Marks parent
\   dirty + signals repaint.
: UTUI-REMOVE-ELEM  ( elem -- )
    _UTUI-MENU-OPEN @ ?DUP IF
        OVER SWAP _UTUI-ANCESTOR-OF? IF _UTUI-MENU-CLOSE THEN
    THEN
    DUP _UTUI-DEMATERIALIZE-ONE
    DUP UIDL-PARENT ?DUP IF UIDL-DIRTY! THEN
    DUP _UTUI-SC-FREE
    UIDL-REMOVE-ELEM
    _UTUI-NEEDS-PAINT ON ;

\ UTUI-SET-ATTR ( elem na nl va vl -- )
\   Set attribute + auto-dirty the element and signal repaint.
\   Equal-value writes are no-ops: they neither consume string-pool
\   space nor schedule a redundant frame.
VARIABLE _USA-ELEM
VARIABLE _USA-NA
VARIABLE _USA-NL
VARIABLE _USA-VA
VARIABLE _USA-VL

: UTUI-SET-ATTR  ( elem na nl va vl -- )
    _USA-VL ! _USA-VA ! _USA-NL ! _USA-NA ! _USA-ELEM !
    _USA-ELEM @ _USA-NA @ _USA-NL @ UIDL-ATTR IF
        _USA-VA @ _USA-VL @ STR-STR= IF EXIT THEN
    ELSE
        2DROP
    THEN
    _USA-ELEM @ _USA-NA @ _USA-NL @ _USA-VA @ _USA-VL @
    UIDL-SET-ATTR
    _USA-ELEM @ UIDL-DIRTY! ;

\ UTUI-WIDGET-SET ( wptr elem -- )
\   Attach a manually created widget to a UIDL element.
\   The widget is drawn automatically by UTUI-PAINT when it
\   visits this element.  The pointer remains caller-owned: detach and
\   document teardown clear it but never free it.  Pass 0 as wptr to detach.
: UTUI-WIDGET-SET  ( wptr elem -- )
    DUP >R
    _UTUI-SIDECAR
    OVER IF
        _UTUI-WOWNER-CALLER OVER _UTUI-SC-WOWNER!
    ELSE
        _UTUI-WOWNER-UIDL OVER _UTUI-SC-WOWNER!
    THEN
    _UTUI-SC-WPTR!
    R> UIDL-DIRTY!
    _UTUI-NEEDS-PAINT ON ;

: UTUI-BIND-STATE  ( st -- )
    DUP _UTUI-STATE !
    ST-USE ;

: UTUI-LOAD  ( xml-a xml-u rgn -- flag )
    _UTUI-MENU-STATE-CLEAR
    _UTUI-RGN !

    UIDL-PARSE                         ( flag )
    DUP 0= IF EXIT THEN
    DROP                               \ discard parse flag; push -1 at end

    \ Set element pool base for sidecar indexing.
    \ _UDL-ELEMS is a CREATE'd buffer in uidl.f: executing it
    \ pushes the pool base address.
    _UDL-ELEMS _UTUI-ELEM-BASE !

    _UTUI-SC-CLEAR-ALL
    _UTUI-ACT-CLEAR

    UTUI-RELAYOUT
    _UTUI-MATERIALIZE
    _UTUI-WIRE-SUBS

    0 _UTUI-FOCUS-P !
    UTUI-FOCUS-NEXT

    -1 _UTUI-DOC-LOADED !
    \ Composition may now synchronously attach an optional projection adapter.
    \ UTUI-LOAD itself never borrows or retains that adapter's binding.
    -1 ;

\ =====================================================================
\  §18 — UTUI-DETACH
\ =====================================================================

: UTUI-DETACH  ( -- )
    \ Generic hosts call quiesce before APP.SHUTDOWN and final detach after it.
    \ This fail-closed fallback prevents semantic storage from being cleared
    \ when either barrier was omitted or refused.
    _UTUI-PROJECTION-DETACH ?DUP IF THROW THEN
    _UTUI-DEMATERIALIZE
    _UTUI-MENU-STATE-CLEAR
    _UTUI-SC-CLEAR-ALL
    _UTUI-ACT-CLEAR
    _UTUI-SHORT-CLEAR
    UIDL-RESET-SUBS
    0 _UTUI-FOCUS-P !
    0 _UTUI-DOC-LOADED !
    0 _UTUI-RGN !
    _UTUI-PROJECTION-CLEAR ;

\ =====================================================================
\  §18b — UIDL Context Save / Restore  (UCTX)
\ =====================================================================
\
\  Per sub-app UIDL context buffer holding 27 scalar variables and
\  10 pool arrays.  Total 103,640 bytes (~101 KiB).
\
\  This section lives in uidl-tui.f because it must enumerate every
\  private _UDL-* and _UTUI-* variable and pool.  The shell (browser)
\  calls only the public API: UCTX-ALLOC, UCTX-FREE, UCTX-SAVE,
\  UCTX-RESTORE, UCTX-CLEAR, UCTX-TOTAL.

27 CONSTANT _UCTX-NVAR
216 CONSTANT _UCTX-VAR-SZ       \ 27 × 8

\ Pool sizes (must match module declarations)
32768 CONSTANT _UCTX-ELEMS-SZ   \ 256 × 128
20480 CONSTANT _UCTX-ATTRS-SZ   \ 512 × 40
12288 CONSTANT _UCTX-STRS-SZ
 2048 CONSTANT _UCTX-HASH-SZ    \ 256 × 8
 4096 CONSTANT _UCTX-HIDS-SZ    \ 256 × 16
 3072 CONSTANT _UCTX-SUBS-SZ    \ 128 × 24
24576 CONSTANT _UCTX-SC-SZ      \ 256 × 96  ( TSC-SIZE )
_UTUI-ACTS-SZ CONSTANT _UCTX-ACTS-SZ  \ exact action arena
 2048 CONSTANT _UCTX-SHORTS-SZ  \ 64 × 32
  512 CONSTANT _UCTX-OVBUF-SZ   \ 32 × 16

\ Offsets into context buffer
_UCTX-VAR-SZ                                       CONSTANT _UCTX-O-ELEMS
_UCTX-O-ELEMS  _UCTX-ELEMS-SZ  +                   CONSTANT _UCTX-O-ATTRS
_UCTX-O-ATTRS  _UCTX-ATTRS-SZ  +                   CONSTANT _UCTX-O-STRS
_UCTX-O-STRS   _UCTX-STRS-SZ   +                   CONSTANT _UCTX-O-HASH
_UCTX-O-HASH   _UCTX-HASH-SZ   +                   CONSTANT _UCTX-O-HIDS
_UCTX-O-HIDS   _UCTX-HIDS-SZ   +                   CONSTANT _UCTX-O-SUBS
_UCTX-O-SUBS   _UCTX-SUBS-SZ   +                   CONSTANT _UCTX-O-SC
_UCTX-O-SC     _UCTX-SC-SZ     +                   CONSTANT _UCTX-O-ACTS
_UCTX-O-ACTS   _UCTX-ACTS-SZ   +                   CONSTANT _UCTX-O-SHORTS
_UCTX-O-SHORTS _UCTX-SHORTS-SZ +                   CONSTANT _UCTX-O-OVBUF
_UCTX-O-OVBUF  _UCTX-OVBUF-SZ  +                   CONSTANT UCTX-TOTAL

\ --- Variable table: maps index → global VARIABLE address ---
CREATE _UCTX-VARS  _UCTX-NVAR CELLS ALLOT

: _UCTX-INIT-VARS  ( -- )
    _UDL-ECNT           _UCTX-VARS  0 CELLS + !
    _UDL-ACNT           _UCTX-VARS  1 CELLS + !
    _UDL-SPOS           _UCTX-VARS  2 CELLS + !
    _UDL-ROOT           _UCTX-VARS  3 CELLS + !
    _UDL-SUB-CNT        _UCTX-VARS  4 CELLS + !
    _UTUI-ELEM-BASE     _UCTX-VARS  5 CELLS + !
    _UTUI-DOC-LOADED    _UCTX-VARS  6 CELLS + !
    _UTUI-STATE         _UCTX-VARS  7 CELLS + !
    _UTUI-FOCUS-P       _UCTX-VARS  8 CELLS + !
    _UTUI-ACT-CNT       _UCTX-VARS  9 CELLS + !
    _UTUI-SHORT-CNT     _UCTX-VARS 10 CELLS + !
    _UTUI-OVERLAY-CNT   _UCTX-VARS 11 CELLS + !
    _UTUI-SAVED-FOCUS   _UCTX-VARS 12 CELLS + !
    _UTUI-SKIP-CHILDREN _UCTX-VARS 13 CELLS + !
    _UTUI-RGN           _UCTX-VARS 14 CELLS + !
    _UTUI-PROJ-TOKEN     _UCTX-VARS 15 CELLS + !
    _UTUI-PROJ-STATUS    _UCTX-VARS 16 CELLS + !
    _UTUI-VISIBLE        _UCTX-VARS 17 CELLS + !
    _UTUI-PROJ-ATTACHED   _UCTX-VARS 18 CELLS + !
    _UTUI-QUIESCING       _UCTX-VARS 19 CELLS + !
    _UTUI-QUIESCED        _UCTX-VARS 20 CELLS + !
    _UTUI-MENU-OPEN       _UCTX-VARS 21 CELLS + !
    _UTUI-MENU-SAVED-FOC  _UCTX-VARS 22 CELLS + !
    _UTUI-MENU-SAVE-ROW   _UCTX-VARS 23 CELLS + !
    _UTUI-MENU-SAVE-H     _UCTX-VARS 24 CELLS + !
    _UTUI-MENU-SAVE-W     _UCTX-VARS 25 CELLS + !
    _UTUI-MENU-SAVE-Z     _UCTX-VARS 26 CELLS + ! ;
_UCTX-INIT-VARS

\ --- Pool table: maps index → (global-addr, ctx-offset, size) ---
10 CONSTANT _UCTX-NPOOL
CREATE _UCTX-POOLS  _UCTX-NPOOL 3 * CELLS ALLOT

: _UCTX-INIT-POOLS  ( -- )
    _UDL-ELEMS        _UCTX-POOLS   0 + !
    _UCTX-O-ELEMS     _UCTX-POOLS   8 + !
    _UCTX-ELEMS-SZ    _UCTX-POOLS  16 + !
    _UDL-ATTRS        _UCTX-POOLS  24 + !
    _UCTX-O-ATTRS     _UCTX-POOLS  32 + !
    _UCTX-ATTRS-SZ    _UCTX-POOLS  40 + !
    _UDL-STRS         _UCTX-POOLS  48 + !
    _UCTX-O-STRS      _UCTX-POOLS  56 + !
    _UCTX-STRS-SZ     _UCTX-POOLS  64 + !
    _UDL-HASH         _UCTX-POOLS  72 + !
    _UCTX-O-HASH      _UCTX-POOLS  80 + !
    _UCTX-HASH-SZ     _UCTX-POOLS  88 + !
    _UDL-HIDS         _UCTX-POOLS  96 + !
    _UCTX-O-HIDS      _UCTX-POOLS 104 + !
    _UCTX-HIDS-SZ     _UCTX-POOLS 112 + !
    _UDL-SUBS         _UCTX-POOLS 120 + !
    _UCTX-O-SUBS      _UCTX-POOLS 128 + !
    _UCTX-SUBS-SZ     _UCTX-POOLS 136 + !
    _UTUI-SIDECARS    _UCTX-POOLS 144 + !
    _UCTX-O-SC        _UCTX-POOLS 152 + !
    _UCTX-SC-SZ       _UCTX-POOLS 160 + !
    _UTUI-ACTS        _UCTX-POOLS 168 + !
    _UCTX-O-ACTS      _UCTX-POOLS 176 + !
    _UCTX-ACTS-SZ     _UCTX-POOLS 184 + !
    _UTUI-SHORTS      _UCTX-POOLS 192 + !
    _UCTX-O-SHORTS    _UCTX-POOLS 200 + !
    _UCTX-SHORTS-SZ   _UCTX-POOLS 208 + !
    _UTUI-OVERLAY-BUF _UCTX-POOLS 216 + !
    _UCTX-O-OVBUF     _UCTX-POOLS 224 + !
    _UCTX-OVBUF-SZ    _UCTX-POOLS 232 + ! ;
_UCTX-INIT-POOLS

\ --- Public API ---

: UCTX-ALLOC  ( -- ctx | 0 )
    UCTX-TOTAL ALLOCATE IF DROP 0 THEN ;

: UCTX-FREE  ( ctx -- )
    FREE ;

\ Pool copy helper variables
VARIABLE _UCP-SRC   VARIABLE _UCP-DST   VARIABLE _UCP-SZ

: UCTX-SAVE  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    _UCTX-NVAR 0 DO
        I CELLS _UCTX-VARS + @
        @ OVER I CELLS + !
    LOOP
    _UCTX-NPOOL 0 DO
        I 3 * CELLS _UCTX-POOLS +
        DUP @       _UCP-SRC !
        DUP 16 + @  _UCP-SZ  !
        8 + @ OVER + _UCP-DST !
        _UCP-SRC @ _UCP-DST @ _UCP-SZ @ CMOVE
    LOOP
    DROP ;

: UCTX-RESTORE  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    _UCTX-NVAR 0 DO
        DUP I CELLS + @
        I CELLS _UCTX-VARS + @
        !
    LOOP
    _UCTX-NPOOL 0 DO
        I 3 * CELLS _UCTX-POOLS +
        DUP @       _UCP-DST !
        DUP 16 + @  _UCP-SZ  !
        8 + @ OVER + _UCP-SRC !
        _UCP-SRC @ _UCP-DST @ _UCP-SZ @ CMOVE
    LOOP
    DROP ;

: UCTX-CLEAR  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    UCTX-TOTAL 0 FILL ;

\ =====================================================================
\  §18c — Coherent resolved projection observation
\ =====================================================================
\
\ The record is assembled in private scalar scratch and copied only after the
\ complete element, ancestor, geometry, style, and destination checks pass.
\ This makes every ordinary failure destination-preserving and prevents a TSC
\ address or packed style word from escaping UIDL-TUI.

-1 1 RSHIFT CONSTANT _UTUI-RS-SIGNED-MAX
127 CONSTANT _UTUI-RS-ATTR-MASK

VARIABLE _UTUI-RS-P-ELEM
VARIABLE _UTUI-RS-ELEM
VARIABLE _UTUI-RS-NODE
VARIABLE _UTUI-RS-SC
VARIABLE _UTUI-RS-ROOT
VARIABLE _UTUI-RS-DEPTH
VARIABLE _UTUI-RS-TOTAL
VARIABLE _UTUI-RS-VISIBLE
VARIABLE _UTUI-RS-STYLE
VARIABLE _UTUI-RS-ROW
VARIABLE _UTUI-RS-COL
VARIABLE _UTUI-RS-H
VARIABLE _UTUI-RS-W
VARIABLE _UTUI-RS-ROW-END
VARIABLE _UTUI-RS-COL-END
VARIABLE _UTUI-RS-FG
VARIABLE _UTUI-RS-BG
VARIABLE _UTUI-RS-ATTRS
VARIABLE _UTUI-RS-ALIGN
VARIABLE _UTUI-RS-Z
VARIABLE _UTUI-RS-ROOT-ROW
VARIABLE _UTUI-RS-ROOT-COL
VARIABLE _UTUI-RS-ROOT-H
VARIABLE _UTUI-RS-ROOT-W
VARIABLE _UTUI-RS-ROOT-ROW-END
VARIABLE _UTUI-RS-ROOT-COL-END
VARIABLE _UTUI-RS-DST
VARIABLE _UTUI-RST-ACTIVE
VARIABLE _UTUI-OWNED-LIMIT

0 _UTUI-OWNED-LIMIT !

: _UTUI-RS-AXIS-END?  ( start length -- end flag )
    DUP 0< IF 2DROP 0 0 EXIT THEN
    >R
    DUP _UTUI-RS-SIGNED-MAX R@ - > IF
        DROP R> DROP 0 0 EXIT
    THEN
    R> + -1 ;

: _UTUI-RESOLVED-SPAN?  ( address available -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP UTUI-RESOLVED-SIZE U< IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _UTUI-RS-ATTRS-VALID?  ( attrs -- flag )
    DUP 65535 U> IF DROP 0 EXIT THEN
    DUP CELL-A-WIDE CELL-A-CONT OR AND 0=
    SWAP _UTUI-RS-ATTR-MASK INVERT AND 0= AND ;

\ Reject every authoritative storage range read by a combined resolved-state
\ and semantic projection.  The current root-region descriptor is borrowed by
\ UIDL-TUI, so it is protected explicitly in addition to provider-owned,
\ neutral UIDL, semantic scratch, and state-tree storage.
: _UTUI-STORAGE-DISJOINT-BODY?  ( address length -- flag )
    OVER 0= OVER 0> 0= OR IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _UTUI-OWNED-LIMIT @ DUP _UTUI-SIDECARS U< IF
        DROP 2DROP 0 EXIT
    THEN
    _UTUI-SIDECARS - DUP 0> 0= IF DROP 2DROP 0 EXIT THEN
    >R 2DUP _UTUI-SIDECARS R>
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    _UTUI-RGN @ DUP IF
        DUP RGN-SIZE MSPAN-NONWRAPPING? 0= IF 3DROP 0 EXIT THEN
        >R
        2DUP R> RGN-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    ELSE
        DROP
    THEN
    2DUP UIDL-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UIDL-SEMANTIC-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP ST-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DROP -1 ;

: UTUI-STORAGE-DISJOINT?  ( address length -- flag )
    ['] _UTUI-STORAGE-DISJOINT-BODY? CATCH ?DUP IF
        DROP 2DROP 0
    THEN ;

: _UTUI-RESOLVED-VALID-BODY?  ( record available -- flag )
    2DUP _UTUI-RESOLVED-SPAN? 0= IF 2DROP 0 EXIT THEN
    DROP
    DUP _UTUI-RS.ROW @ OVER _UTUI-RS.H @ _UTUI-RS-AXIS-END?
        0= IF 2DROP 0 EXIT THEN DROP
    DUP _UTUI-RS.COL @ OVER _UTUI-RS.W @ _UTUI-RS-AXIS-END?
        0= IF 2DROP 0 EXIT THEN DROP
    DUP _UTUI-RS.FG @ 255 U> IF DROP 0 EXIT THEN
    DUP _UTUI-RS.BG @ 255 U> IF DROP 0 EXIT THEN
    DUP _UTUI-RS.ATTRS @ _UTUI-RS-ATTRS-VALID? 0= IF DROP 0 EXIT THEN
    DUP _UTUI-RS.ALIGN @ 2 U> IF DROP 0 EXIT THEN
    _UTUI-RS.Z @ 255 U> 0= ;

: UTUI-RESOLVED-VALID?  ( record available -- flag )
    ['] _UTUI-RESOLVED-VALID-BODY? CATCH ?DUP IF
        DROP 2DROP 0
    THEN ;

: _UTUI-RS-TARGET-CLEAR  ( -- )
    0 _UTUI-RS-P-ELEM ! 0 _UTUI-RS-ELEM ! 0 _UTUI-RS-NODE !
    0 _UTUI-RS-SC ! 0 _UTUI-RS-DEPTH !
    0 _UTUI-RS-TOTAL ! 0 _UTUI-RS-VISIBLE ! 0 _UTUI-RS-STYLE !
    0 _UTUI-RS-ROW ! 0 _UTUI-RS-COL ! 0 _UTUI-RS-H ! 0 _UTUI-RS-W !
    0 _UTUI-RS-ROW-END ! 0 _UTUI-RS-COL-END !
    0 _UTUI-RS-FG ! 0 _UTUI-RS-BG ! 0 _UTUI-RS-ATTRS !
    0 _UTUI-RS-ALIGN ! 0 _UTUI-RS-Z !
    0 _UTUI-RS-DST ! ;

: _UTUI-RS-CLEAR  ( -- )
    _UTUI-RS-TARGET-CLEAR
    0 _UTUI-RS-ROOT !
    0 _UTUI-RS-ROOT-ROW ! 0 _UTUI-RS-ROOT-COL !
    0 _UTUI-RS-ROOT-H ! 0 _UTUI-RS-ROOT-W !
    0 _UTUI-RS-ROOT-ROW-END ! 0 _UTUI-RS-ROOT-COL-END ! ;

: _UTUI-RS-TARGET-VALID?  ( -- flag )
    _UTUI-RS-ROW @ _UTUI-RS-H @ _UTUI-RS-AXIS-END?
        0= IF DROP 0 EXIT THEN _UTUI-RS-ROW-END !
    _UTUI-RS-COL @ _UTUI-RS-W @ _UTUI-RS-AXIS-END?
        0= IF DROP 0 EXIT THEN _UTUI-RS-COL-END !
    _UTUI-RS-FG @ 255 U> IF 0 EXIT THEN
    _UTUI-RS-BG @ 255 U> IF 0 EXIT THEN
    _UTUI-RS-ATTRS @ _UTUI-RS-ATTRS-VALID? 0= IF 0 EXIT THEN
    _UTUI-RS-ALIGN @ 2 U> IF 0 EXIT THEN
    _UTUI-RS-Z @ 255 U> IF 0 EXIT THEN
    _UTUI-RS-STYLE @ TSC-UNPACK-POS 2 U> IF 0 EXIT THEN
    _UTUI-RS-STYLE @ 52 RSHIFT IF 0 EXIT THEN
    -1 ;

: _UTUI-RS-ROOT-GEOMETRY?  ( -- flag )
    _UTUI-RS-ROOT @ _UTUI-SIDECAR _UTUI-RS-SC !
    _UTUI-RS-SC @ _UTUI-SC-ROW@ _UTUI-RS-ROOT-ROW !
    _UTUI-RS-SC @ _UTUI-SC-COL@ _UTUI-RS-ROOT-COL !
    _UTUI-RS-SC @ _UTUI-SC-H@ _UTUI-RS-ROOT-H !
    _UTUI-RS-SC @ _UTUI-SC-W@ _UTUI-RS-ROOT-W !
    _UTUI-RS-ROOT-ROW @ _UTUI-RS-ROOT-H @ _UTUI-RS-AXIS-END?
        0= IF DROP 0 EXIT THEN _UTUI-RS-ROOT-ROW-END !
    _UTUI-RS-ROOT-COL @ _UTUI-RS-ROOT-W @ _UTUI-RS-AXIS-END?
        0= IF DROP 0 EXIT THEN _UTUI-RS-ROOT-COL-END !
    -1 ;

: _UTUI-RS-INTERSECTS-ROOT?  ( -- flag )
    _UTUI-RS-H @ 0> _UTUI-RS-W @ 0> AND
    _UTUI-RS-ROOT-H @ 0> AND _UTUI-RS-ROOT-W @ 0> AND
        0= IF 0 EXIT THEN
    _UTUI-RS-ROW @ _UTUI-RS-ROOT-ROW-END @ <
    _UTUI-RS-ROOT-ROW @ _UTUI-RS-ROW-END @ < AND
    _UTUI-RS-COL @ _UTUI-RS-ROOT-COL-END @ < AND
    _UTUI-RS-ROOT-COL @ _UTUI-RS-COL-END @ < AND ;

: _UTUI-RS-RESOLVE  ( elem -- status )
    _UTUI-RS-CLEAR
    _UTUI-DOC-LOADED @ 0= IF DROP UTUI-RESOLVED-S-INVALID EXIT THEN
    _UTUI-ELEM-BASE @ _UDL-ELEMS <> IF
        DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    DUP UIDL-ELEM-INDEX? 0= IF
        2DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    DROP DUP _UTUI-RS-ELEM !
    DUP _UTUI-SIDECAR DUP _UTUI-RS-SC !
    _UTUI-SC-FLAGS@ _UTUI-SCF-HAS AND 0= IF
        DROP UTUI-RESOLVED-S-UNAVAILABLE EXIT
    THEN

    _UTUI-RS-SC @ _UTUI-SC-ROW@ _UTUI-RS-ROW !
    _UTUI-RS-SC @ _UTUI-SC-COL@ _UTUI-RS-COL !
    _UTUI-RS-SC @ _UTUI-SC-H@ _UTUI-RS-H !
    _UTUI-RS-SC @ _UTUI-SC-W@ _UTUI-RS-W !
    _UTUI-RS-SC @ _UTUI-SC-STYLE@ DUP _UTUI-RS-STYLE !
    DUP TSC-UNPACK-FG _UTUI-RS-FG !
    DUP TSC-UNPACK-BG _UTUI-RS-BG !
    DUP TSC-UNPACK-ATTRS _UTUI-RS-ATTRS !
    DROP
    _UTUI-RS-SC @ _UTUI-SC-TALIGN@ _UTUI-RS-ALIGN !
    0 _UTUI-RS-Z !
    _UTUI-RS-TARGET-VALID? 0= IF
        DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    DROP

    -1 _UTUI-RS-VISIBLE !
    UIDL-ELEM-COUNT DUP 0> 0= IF
        DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    _UTUI-RS-TOTAL !
    _UTUI-RS-ELEM @ _UTUI-RS-NODE !
    BEGIN
        _UTUI-RS-NODE @ UIDL-ELEM-INDEX? 0= IF
            DROP UTUI-RESOLVED-S-INVALID EXIT
        THEN
        DROP
        _UTUI-RS-NODE @ _UTUI-SIDECAR DUP _UTUI-RS-SC !
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-HAS AND 0= IF
            DROP UTUI-RESOLVED-S-UNAVAILABLE EXIT
        THEN
        _UTUI-SC-VIS? 0= IF 0 _UTUI-RS-VISIBLE ! THEN

        \ Closed menus suppress their descendants.  The menu element itself
        \ remains a coherent node; only a target below it is suppressed.
        _UTUI-RS-NODE @ _UTUI-RS-ELEM @ <> IF
            _UTUI-RS-NODE @ UIDL-TYPE UIDL-T-MENU =
            _UTUI-RS-NODE @ _UTUI-MENU-OPEN @ <> AND IF
                0 _UTUI-RS-VISIBLE !
            THEN
        THEN

        \ Pass 1 defers the outermost dialog or positive-z ancestor and then
        \ paints its complete subtree.  Walking target-to-root and overwriting
        \ on each deferred node therefore yields that group's actual z.
        _UTUI-RS-NODE @ UIDL-TYPE UIDL-T-DIALOG = IF
            _UTUI-RS-SC @ _UTUI-SC-ZIDX@ DUP 0= IF DROP 255 THEN
        ELSE
            _UTUI-RS-SC @ _UTUI-SC-ZIDX@
        THEN
        ?DUP IF _UTUI-RS-Z ! THEN

        _UTUI-RS-NODE @ UIDL-PARENT DUP 0= IF
            DROP _UTUI-RS-NODE @ _UTUI-RS-ROOT ! -1
        ELSE
            _UTUI-RS-NODE !
            1 _UTUI-RS-DEPTH +!
            _UTUI-RS-DEPTH @ _UTUI-RS-TOTAL @ U< 0= IF
                UTUI-RESOLVED-S-INVALID EXIT
            THEN
            0
        THEN
    UNTIL
    _UTUI-RS-ROOT @ UIDL-ROOT <> IF UTUI-RESOLVED-S-INVALID EXIT THEN
    _UTUI-RS-ROOT-GEOMETRY? 0= IF UTUI-RESOLVED-S-INVALID EXIT THEN
    _UTUI-RS-INTERSECTS-ROOT? 0= IF 0 _UTUI-RS-VISIBLE ! THEN
    UTUI-RESOLVED-S-OK ;

: _UTUI-RS-RESOLVE-CALL  ( -- status )
    _UTUI-RS-P-ELEM @ _UTUI-RS-RESOLVE ;

: _UTUI-RS-CALL  ( elem -- status )
    _UTUI-RS-P-ELEM !
    ['] _UTUI-RS-RESOLVE-CALL CATCH ?DUP IF
        DROP UTUI-RESOLVED-S-INVALID
    THEN ;

: _UTUI-RS-RESULT  ( status -- effective-visible status )
    DUP UTUI-RESOLVED-S-OK = IF _UTUI-RS-VISIBLE @ 0<> ELSE 0 THEN
    SWAP _UTUI-RS-CLEAR ;

: UTUI-ELEM-RESOLVED-STATE@
    ( elem -- effective-visible status )
    _UTUI-RST-ACTIVE @ IF
        DROP 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    _UTUI-RS-CALL _UTUI-RS-RESULT ;

: _UTUI-RS-WRITE  ( -- )
    _UTUI-RS-ROW @ _UTUI-RS-DST @ _UTUI-RS.ROW !
    _UTUI-RS-COL @ _UTUI-RS-DST @ _UTUI-RS.COL !
    _UTUI-RS-H @ _UTUI-RS-DST @ _UTUI-RS.H !
    _UTUI-RS-W @ _UTUI-RS-DST @ _UTUI-RS.W !
    _UTUI-RS-FG @ _UTUI-RS-DST @ _UTUI-RS.FG !
    _UTUI-RS-BG @ _UTUI-RS-DST @ _UTUI-RS.BG !
    _UTUI-RS-ATTRS @ _UTUI-RS-DST @ _UTUI-RS.ATTRS !
    _UTUI-RS-ALIGN @ _UTUI-RS-DST @ _UTUI-RS.ALIGN !
    _UTUI-RS-Z @ _UTUI-RS-DST @ _UTUI-RS.Z ! ;

: _UTUI-ELEM-RESOLVED-CAPTURE-BODY
    ( elem destination available -- effective-visible status )
    2DUP _UTUI-RESOLVED-SPAN? 0= IF
        3DROP 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    OVER UTUI-RESOLVED-SIZE UTUI-STORAGE-DISJOINT? 0= IF
        3DROP 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    DROP SWAP _UTUI-RS-CALL
    DUP UTUI-RESOLVED-S-OK <> IF
        NIP 0 SWAP _UTUI-RS-CLEAR 0 _UTUI-RS-DST ! EXIT
    THEN
    DROP _UTUI-RS-DST !
    _UTUI-RS-WRITE
    UTUI-RESOLVED-S-OK _UTUI-RS-RESULT
    0 _UTUI-RS-DST ! ;

: UTUI-ELEM-RESOLVED-CAPTURE
    ( elem destination available -- effective-visible status )
    _UTUI-RST-ACTIVE @ IF
        3DROP 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    ['] _UTUI-ELEM-RESOLVED-CAPTURE-BODY CATCH ?DUP IF
        DROP 3DROP 0 UTUI-RESOLVED-S-INVALID
    THEN
    _UTUI-RS-CLEAR 0 _UTUI-RS-DST ! ;

\ =====================================================================
\  Linear resolved-tree observation
\ =====================================================================
\
\ The visitor receives every live node once in authored preorder.  A complete
\ resolved record is call-borrowed when AVAILABLE is 72; an unavailable
\ lineage is reported with AVAILABLE zero.  The visitor must copy anything it
\ retains and must not yield, mutate UIDL/application state, or invoke
\ lifecycle/action callbacks.
\
\ Local visibility is renderer-neutral application visibility.  For menu rows
\ it deliberately ignores the close-owned VIS bit while retaining WHEN,
\ display:none, visibility:hidden, runtime hiding, and layout admission.
\ Effective visibility additionally carries ordinary VIS, ancestor visibility,
\ closed-menu suppression, and the node's own root intersection.  Parent
\ rectangle intersection is not inherited because positioned children may
\ re-enter the root clip.

1 CONSTANT _UTUI-RST-S-VISIBLE
2 CONSTANT _UTUI-RST-S-AVAILABLE

VARIABLE _UTUI-RST-VISITOR
VARIABLE _UTUI-RST-TOTAL
VARIABLE _UTUI-RST-VISITED
VARIABLE _UTUI-RST-ELEM
VARIABLE _UTUI-RST-INDEX
VARIABLE _UTUI-RST-ORDINAL
VARIABLE _UTUI-RST-ANCESTOR-STATE
VARIABLE _UTUI-RST-ANCESTOR-VISIBLE
VARIABLE _UTUI-RST-ANCESTOR-AVAILABLE
VARIABLE _UTUI-RST-OUTERMOST-Z
VARIABLE _UTUI-RST-RAW-VISIBLE
VARIABLE _UTUI-RST-LOCAL-VISIBLE
VARIABLE _UTUI-RST-LINEAGE-VISIBLE
VARIABLE _UTUI-RST-EFFECTIVE-VISIBLE
VARIABLE _UTUI-RST-NODE-AVAILABLE
VARIABLE _UTUI-RST-NODE-Z
VARIABLE _UTUI-RST-AVAILABLE-BYTES

CREATE _UTUI-RST-RESOLVED UTUI-RESOLVED-SIZE ALLOT
CREATE _UTUI-RST-SEEN _UTUI-MAX-ELEMS ALLOT

: _UTUI-RST-CLEAR  ( -- )
    0 _UTUI-RST-VISITOR ! 0 _UTUI-RST-ACTIVE !
    0 _UTUI-RST-TOTAL ! 0 _UTUI-RST-VISITED !
    0 _UTUI-RST-ELEM ! 0 _UTUI-RST-INDEX ! 0 _UTUI-RST-ORDINAL !
    0 _UTUI-RST-ANCESTOR-STATE ! 0 _UTUI-RST-ANCESTOR-VISIBLE !
    0 _UTUI-RST-ANCESTOR-AVAILABLE ! 0 _UTUI-RST-OUTERMOST-Z !
    0 _UTUI-RST-RAW-VISIBLE !
    0 _UTUI-RST-LOCAL-VISIBLE ! 0 _UTUI-RST-LINEAGE-VISIBLE !
    0 _UTUI-RST-EFFECTIVE-VISIBLE ! 0 _UTUI-RST-NODE-AVAILABLE !
    0 _UTUI-RST-NODE-Z ! 0 _UTUI-RST-AVAILABLE-BYTES !
    _UTUI-RST-RESOLVED UTUI-RESOLVED-SIZE 0 FILL
    _UTUI-RST-SEEN _UTUI-MAX-ELEMS 0 FILL
    _UTUI-RS-CLEAR ;

: _UTUI-RST-LOCAL-VISIBLE?  ( -- flag )
    _UTUI-RST-ELEM @ UIDL-TYPE
    DUP UIDL-T-ITEM = SWAP UIDL-T-SEPARATOR = OR IF
        _UTUI-RST-ELEM @ UIDL-PARENT ?DUP IF
            UIDL-TYPE UIDL-T-MENU = IF
                _UTUI-RST-ELEM @
                    _UTUI-MENU-ROW-LOCAL-VISIBLE-BODY? EXIT
            THEN
        THEN
    THEN
    _UTUI-RS-SC @ _UTUI-SC-VIS? ;

: _UTUI-RST-LOAD-NODE  ( -- status )
    \ Preserve the root geometry prepared once by the tree body.
    _UTUI-RS-TARGET-CLEAR
    _UTUI-RST-RESOLVED UTUI-RESOLVED-SIZE 0 FILL
    0 _UTUI-RST-RAW-VISIBLE ! 0 _UTUI-RST-LOCAL-VISIBLE !
    0 _UTUI-RST-LINEAGE-VISIBLE ! 0 _UTUI-RST-EFFECTIVE-VISIBLE !
    0 _UTUI-RST-NODE-AVAILABLE ! 0 _UTUI-RST-NODE-Z !
    _UTUI-RST-ELEM @ DUP _UTUI-RS-ELEM !
    _UTUI-SIDECAR DUP _UTUI-RS-SC !
    DUP _UTUI-SC-FLAGS@ _UTUI-SCF-HAS AND 0= IF
        DROP UTUI-RESOLVED-S-UNAVAILABLE EXIT
    THEN

    DUP _UTUI-SC-ROW@ _UTUI-RS-ROW !
    DUP _UTUI-SC-COL@ _UTUI-RS-COL !
    DUP _UTUI-SC-H@ _UTUI-RS-H !
    DUP _UTUI-SC-W@ _UTUI-RS-W !
    DUP _UTUI-SC-STYLE@ DUP _UTUI-RS-STYLE !
    DUP TSC-UNPACK-FG _UTUI-RS-FG !
    DUP TSC-UNPACK-BG _UTUI-RS-BG !
    DUP TSC-UNPACK-ATTRS _UTUI-RS-ATTRS !
    DROP
    DUP _UTUI-SC-TALIGN@ _UTUI-RS-ALIGN !

    _UTUI-RST-OUTERMOST-Z @ ?DUP IF
        _UTUI-RST-NODE-Z !
    ELSE
        DUP _UTUI-SC-ZIDX@
        _UTUI-RST-ELEM @ UIDL-TYPE UIDL-T-DIALOG = IF
            DUP 0= IF DROP 255 THEN
        THEN
        _UTUI-RST-NODE-Z !
    THEN
    DROP
    _UTUI-RST-NODE-Z @ _UTUI-RS-Z !
    _UTUI-RS-TARGET-VALID? 0= IF UTUI-RESOLVED-S-INVALID EXIT THEN

    _UTUI-RS-SC @ _UTUI-SC-VIS? 0<> _UTUI-RST-RAW-VISIBLE !
    _UTUI-RST-LOCAL-VISIBLE? 0<> _UTUI-RST-LOCAL-VISIBLE !
    _UTUI-RST-ANCESTOR-AVAILABLE @ 0= IF
        UTUI-RESOLVED-S-UNAVAILABLE EXIT
    THEN
    -1 _UTUI-RST-NODE-AVAILABLE !
    _UTUI-RST-ANCESTOR-VISIBLE @ 0<>
    _UTUI-RST-RAW-VISIBLE @ AND 0<>
        _UTUI-RST-LINEAGE-VISIBLE !
    _UTUI-RST-LINEAGE-VISIBLE @
    _UTUI-RS-INTERSECTS-ROOT? AND 0<>
        _UTUI-RST-EFFECTIVE-VISIBLE !
    _UTUI-RST-EFFECTIVE-VISIBLE @ _UTUI-RS-VISIBLE !

    _UTUI-RST-RESOLVED _UTUI-RS-DST !
    _UTUI-RS-WRITE
    0 _UTUI-RS-DST !
    UTUI-RESOLVED-S-OK ;

: _UTUI-RST-VISIT  ( available -- )
    _UTUI-RST-AVAILABLE-BYTES !
    _UTUI-RST-ELEM @
    _UTUI-RST-INDEX @
    _UTUI-RST-ORDINAL @
    _UTUI-RST-LOCAL-VISIBLE @
    _UTUI-RST-EFFECTIVE-VISIBLE @
    _UTUI-RST-RESOLVED _UTUI-RST-AVAILABLE-BYTES @
    _UTUI-RST-VISITOR @ EXECUTE ;

: _UTUI-RST-CHILD-STATE  ( -- state )
    0
    _UTUI-RST-NODE-AVAILABLE @ IF _UTUI-RST-S-AVAILABLE OR THEN
    _UTUI-RST-LINEAGE-VISIBLE @ IF _UTUI-RST-S-VISIBLE OR THEN
    _UTUI-RST-ELEM @ UIDL-TYPE UIDL-T-MENU = IF
        _UTUI-RST-ELEM @ _UTUI-MENU-OPEN @ <> IF
            _UTUI-RST-S-VISIBLE INVERT AND
        THEN
    THEN ;

: _UTUI-RST-NODE
    ( elem sibling-ordinal ancestor-state outermost-z
      -- elem child-state child-outermost-z status )
    _UTUI-RST-OUTERMOST-Z ! _UTUI-RST-ANCESTOR-STATE !
    _UTUI-RST-ORDINAL ! _UTUI-RST-ELEM !
    _UTUI-RST-ANCESTOR-STATE @ _UTUI-RST-S-VISIBLE AND 0<>
        _UTUI-RST-ANCESTOR-VISIBLE !
    _UTUI-RST-ANCESTOR-STATE @ _UTUI-RST-S-AVAILABLE AND 0<>
        _UTUI-RST-ANCESTOR-AVAILABLE !
    _UTUI-RST-VISITED @ _UTUI-RST-TOTAL @ U< 0= IF
        0 0 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    1 _UTUI-RST-VISITED +!
    _UTUI-RST-ELEM @ UIDL-ELEM-INDEX? 0= IF
        DROP 0 0 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    _UTUI-RST-INDEX !
    _UTUI-RST-INDEX @ _UTUI-RST-SEEN + DUP C@ IF
        DROP 0 0 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    1 SWAP C!

    _UTUI-RST-LOAD-NODE
    DUP UTUI-RESOLVED-S-INVALID = IF
        >R 0 0 0 R> EXIT
    THEN
    DUP UTUI-RESOLVED-S-UNAVAILABLE = IF
        DROP 0 _UTUI-RST-VISIT
        _UTUI-RST-ELEM @ 0 0 UTUI-RESOLVED-S-OK EXIT
    THEN
    DUP UTUI-RESOLVED-S-OK <> IF
        DROP 0 0 0 UTUI-RESOLVED-S-INVALID EXIT
    THEN
    DROP
    UTUI-RESOLVED-SIZE _UTUI-RST-VISIT
    _UTUI-RST-ELEM @
    _UTUI-RST-CHILD-STATE
    _UTUI-RST-NODE-Z @
    UTUI-RESOLVED-S-OK ;

: _UTUI-RST-WALK
    ( elem sibling-ordinal ancestor-state outermost-z -- status )
    _UTUI-RST-NODE DUP IF
        >R 3DROP R> EXIT
    THEN
    DROP                                      ( elem child-vis child-z )
    2 PICK UIDL-FIRST-CHILD 0                 ( elem child-vis child-z child ord )
    BEGIN OVER 0<> WHILE
        OVER UIDL-ELEM-INDEX? 0= IF
            DROP 2DROP 3DROP UTUI-RESOLVED-S-INVALID EXIT
        THEN
        DROP
        OVER UIDL-PARENT 5 PICK <> IF
            2DROP 3DROP UTUI-RESOLVED-S-INVALID EXIT
        THEN
        OVER UIDL-NEXT-SIB >R
        DUP 1+ >R
        2OVER RECURSE                         ( elem child-vis child-z status )
        DUP IF
            R> DROP R> DROP
            >R 3DROP R> EXIT
        THEN
        DROP
        R> R> SWAP                            ( elem child-vis child-z next ord' )
    REPEAT
    2DROP 3DROP UTUI-RESOLVED-S-OK ;

: _UTUI-RST-COMPLETE?  ( -- flag )
    _UTUI-RST-TOTAL @ 0 ?DO
        I _UDL-ELEMSZ * _UDL-ELEMS + UE.TYPE @ 0<>
        I _UTUI-RST-SEEN + C@ 0<> <> IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _UTUI-RST-EACH-BODY  ( -- status )
    _UTUI-DOC-LOADED @ 0= IF UTUI-RESOLVED-S-UNAVAILABLE EXIT THEN
    _UTUI-ELEM-BASE @ _UDL-ELEMS <> IF UTUI-RESOLVED-S-INVALID EXIT THEN
    UIDL-ELEM-COUNT DUP 0> 0= IF
        DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    DUP _UTUI-MAX-ELEMS U> IF
        DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    _UTUI-RST-TOTAL !
    0 _UTUI-RST-VISITED !

    UIDL-ROOT DUP 0= IF DROP UTUI-RESOLVED-S-INVALID EXIT THEN
    DUP UIDL-ELEM-INDEX? 0= IF
        2DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    DROP
    DUP UIDL-PARENT IF DROP UTUI-RESOLVED-S-INVALID EXIT THEN
    DUP _UTUI-SIDECAR _UTUI-SC-FLAGS@ _UTUI-SCF-HAS AND 0= IF
        DROP UTUI-RESOLVED-S-UNAVAILABLE EXIT
    THEN
    DUP _UTUI-RS-ROOT !
    _UTUI-RS-ROOT-GEOMETRY? 0= IF
        DROP UTUI-RESOLVED-S-INVALID EXIT
    THEN
    0 _UTUI-RST-S-VISIBLE _UTUI-RST-S-AVAILABLE OR 0
        _UTUI-RST-WALK ?DUP IF EXIT THEN
    _UTUI-RST-COMPLETE? IF
        UTUI-RESOLVED-S-OK
    ELSE
        UTUI-RESOLVED-S-INVALID
    THEN ;

: _UTUI-RST-EACH-SEMANTIC  ( -- status )
    ['] _UTUI-RST-EACH-BODY UIDL-SEMANTIC-OBSERVE ;

: UTUI-RESOLVED-TREE-EACH  ( visitor-xt -- status )
    _UTUI-RST-ACTIVE @ IF DROP UTUI-RESOLVED-S-INVALID EXIT THEN
    DUP 0= IF DROP UTUI-RESOLVED-S-INVALID EXIT THEN
    _UTUI-RST-CLEAR
    _UTUI-RST-VISITOR !
    -1 _UTUI-RST-ACTIVE !
    ['] _UTUI-RST-EACH-SEMANTIC CATCH ?DUP IF
        >R _UTUI-RST-CLEAR R> THROW
    THEN
    _UTUI-RST-CLEAR ;

\ In unguarded builds this is a direct synchronous callback.  The guarded
\ redefinition below acquires UIDL-TUI before UIDL for one coherent snapshot.
: UTUI-RESOLVED-OBSERVE  ( i*x xt -- j*x )  EXECUTE ;

\ =====================================================================
\  §19 — Guard Section
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _utui-guard

' UTUI-LOAD           CONSTANT _utui-load-xt
' UTUI-BIND-STATE     CONSTANT _utui-bind-state-xt
' UTUI-PAINT          CONSTANT _utui-paint-xt
' UTUI-RELAYOUT       CONSTANT _utui-relayout-xt
' UTUI-DISPATCH-KEY   CONSTANT _utui-dispatch-key-xt
' UTUI-DISPATCH-MOUSE CONSTANT _utui-dispatch-mouse-xt
' UTUI-FOCUS          CONSTANT _utui-focus-xt
' UTUI-FOCUS!         CONSTANT _utui-focus-s-xt
' UTUI-FOCUS-NEXT     CONSTANT _utui-focus-next-xt
' UTUI-FOCUS-PREV     CONSTANT _utui-focus-prev-xt
' UTUI-BY-ID          CONSTANT _utui-by-id-xt
' UTUI-WIDGET@        CONSTANT _utui-widget-at-xt
' UTUI-TAB-SELECT     CONSTANT _utui-tab-select-xt
' UTUI-DO!            CONSTANT _utui-do-s-xt
' UTUI-SHOW-DIALOG    CONSTANT _utui-show-dialog-xt
' UTUI-HIDE-DIALOG    CONSTANT _utui-hide-dialog-xt
' UTUI-HIT-TEST       CONSTANT _utui-hit-test-xt
' UTUI-DETACH         CONSTANT _utui-detach-xt
' UTUI-VISIBLE! CONSTANT _utui-visible-s-xt
' UTUI-QUIESCE  CONSTANT _utui-quiesce-xt
' UTUI-INSTALL-XTS    CONSTANT _utui-install-xts-xt
' UTUI-ADD-ELEM       CONSTANT _utui-add-elem-xt
' UTUI-REMOVE-ELEM    CONSTANT _utui-remove-elem-xt
' UTUI-SET-ATTR       CONSTANT _utui-set-attr-xt
' UTUI-WIDGET-SET     CONSTANT _utui-widget-set-xt
' UTUI-ELEM-RGN       CONSTANT _utui-elem-rgn-xt
' UTUI-ELEM-RESOLVED-STATE@
    CONSTANT _utui-elem-resolved-state-at-xt
' UTUI-ELEM-RESOLVED-CAPTURE
    CONSTANT _utui-elem-resolved-capture-xt
' UTUI-RESOLVED-TREE-EACH
    CONSTANT _utui-resolved-tree-each-xt
' UTUI-STORAGE-DISJOINT? CONSTANT _utui-storage-disjoint-q-xt

: UTUI-BIND-STATE     _utui-bind-state-xt     _utui-guard WITH-GUARD ;
: UTUI-FOCUS          _utui-focus-xt          _utui-guard WITH-GUARD ;
: UTUI-FOCUS!         _utui-focus-s-xt        _utui-guard WITH-GUARD ;
: UTUI-FOCUS-NEXT     _utui-focus-next-xt     _utui-guard WITH-GUARD ;
: UTUI-FOCUS-PREV     _utui-focus-prev-xt     _utui-guard WITH-GUARD ;
: UTUI-BY-ID          _utui-by-id-xt          _utui-guard WITH-GUARD ;
: UTUI-WIDGET@        _utui-widget-at-xt      _utui-guard WITH-GUARD ;
: UTUI-DO!            _utui-do-s-xt           _utui-guard WITH-GUARD ;
: UTUI-SHOW-DIALOG    _utui-show-dialog-xt    _utui-guard WITH-GUARD ;
: UTUI-HIDE-DIALOG    _utui-hide-dialog-xt    _utui-guard WITH-GUARD ;
: UTUI-HIT-TEST       _utui-hit-test-xt       _utui-guard WITH-GUARD ;
: UTUI-DETACH
    _UTUI-PROJ-ADAPTER-INSTALLED @ IF
        _utui-detach-xt EXECUTE
    ELSE
        _utui-detach-xt _utui-guard WITH-GUARD
    THEN ;
: UTUI-INSTALL-XTS    _utui-install-xts-xt    _utui-guard WITH-GUARD ;
: UTUI-ADD-ELEM       _utui-add-elem-xt       _utui-guard WITH-GUARD ;
: UTUI-REMOVE-ELEM    _utui-remove-elem-xt    _utui-guard WITH-GUARD ;
: UTUI-SET-ATTR       _utui-set-attr-xt       _utui-guard WITH-GUARD ;
: UTUI-WIDGET-SET     _utui-widget-set-xt     _utui-guard WITH-GUARD ;
: UTUI-ELEM-RGN       _utui-elem-rgn-xt       _utui-guard WITH-GUARD ;

\ Observation lock order is deliberately UTUI -> UIDL.  A later projection
\ may acquire its own guard and the semantic/LEL/state observation seams only
\ while these two authoritative resolved sources remain coherent.
: _UTUI-RESOLVED-IN-UIDL  ( i*x xt -- j*x )  UIDL-OBSERVE ;

: UTUI-RESOLVED-OBSERVE  ( i*x xt -- j*x )
    ['] _UTUI-RESOLVED-IN-UIDL _utui-guard WITH-GUARD ;

: UTUI-ELEM-RESOLVED-STATE@
    ( elem -- effective-visible status )
    _utui-elem-resolved-state-at-xt UTUI-RESOLVED-OBSERVE ;

: UTUI-ELEM-RESOLVED-CAPTURE
    ( elem destination available -- effective-visible status )
    _utui-elem-resolved-capture-xt UTUI-RESOLVED-OBSERVE ;

\ The saved raw words enter one complete UIDL semantic/LEL/state observation;
\ this wrapper adds UIDL-TUI as the outermost authority.
: UTUI-RESOLVED-TREE-EACH  ( visitor-xt -- status )
    _utui-resolved-tree-each-xt _utui-guard WITH-GUARD ;

: UTUI-STORAGE-DISJOINT?  ( address length -- flag )
    _utui-storage-disjoint-q-xt UTUI-RESOLVED-OBSERVE ;

\ These entries own the current UIDL context and may execute registered
\ layout, render, widget, app action, or projection callbacks.  They run
\ only on the UI owner core and deliberately do not retain _utui-guard across
\ callback code.
\ Cross-core callers must post a lifecycle/render/input request to that owner.
: UTUI-LOAD           _utui-load-xt EXECUTE ;
: UTUI-PAINT          _utui-paint-xt EXECUTE ;
: UTUI-RELAYOUT       _utui-relayout-xt EXECUTE ;
: UTUI-VISIBLE! _utui-visible-s-xt EXECUTE ;
: UTUI-QUIESCE  _utui-quiesce-xt EXECUTE ;
: UTUI-DISPATCH-KEY   _utui-dispatch-key-xt EXECUTE ;
: UTUI-DISPATCH-MOUSE _utui-dispatch-mouse-xt EXECUTE ;
: UTUI-TAB-SELECT     _utui-tab-select-xt EXECUTE ;
[THEN] [THEN]

\ Finalize the conservative provider-owned span only after optional guard
\ storage and captured XTs have been created.  Public calls occur after the
\ module has loaded, so a zero or backwards limit always fails closed.
CREATE _UTUI-OWNED-END
_UTUI-OWNED-END _UTUI-OWNED-LIMIT !
