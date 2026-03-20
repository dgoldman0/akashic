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
\    UTUI-DETACH      ( -- )
\
\  Prefix: UTUI- (public), _UTUI- (internal)
\  Provider: akashic-tui-uidl-tui
\
\  Dependencies:
\    REQUIRE liraq/uidl.f
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
REQUIRE ../liraq/uidl-chrome.f
REQUIRE ../liraq/state-tree.f
REQUIRE ../liraq/lel.f
REQUIRE screen.f
REQUIRE draw.f
REQUIRE box.f
REQUIRE region.f
REQUIRE layout.f
REQUIRE keys.f
REQUIRE widgets/tree.f
REQUIRE widgets/input.f
REQUIRE widgets/textarea.f
REQUIRE ../css/css.f
REQUIRE color.f

\ =====================================================================
\  §1 — TUI Sidecar (per-element, 80 bytes)
\ =====================================================================
\
\  Parallel array indexed by element pool index:
\    elem-index = (elem – _UDL-ELEMS) / _UDL-ELEMSZ
\    sidecar    = elem-index × 80 + _UTUI-SIDECARS
\
\  Fields:
\    +0  row     Computed row in screen coordinates (cell)
\    +8  col     Computed column (cell)
\   +16  width   Computed width (cells)
\   +24  height  Computed height (cells)
\   +32  style   Packed: fg(8) bg(8) attrs(8) text-align(2) position(2)
\                        z-index(8) reserved(22)
\   +40  flags   Bit 0=has, 1=visible, 2=focused, 3=display-none,
\                    4=overflow-clip
\   +48  wptr    Widget struct pointer (0 = none)
\   +56  padding Packed: PT(8) PR(8) PB(8) PL(8) in bits 0–31
\   +64  offsets Packed: top(16s) right(16s) bottom(16s) left(16s)
\   +72  margin  Packed: MT(8) MR(8) MB(8) ML(8) in bits 0–31

80 CONSTANT _UTUI-SC-SZ
256 CONSTANT _UTUI-MAX-ELEMS
CREATE _UTUI-SIDECARS  _UTUI-MAX-ELEMS _UTUI-SC-SZ * ALLOT

\ Sidecar field offsets
 0 CONSTANT _UTUI-SC-O-ROW
 8 CONSTANT _UTUI-SC-O-COL
16 CONSTANT _UTUI-SC-O-W
24 CONSTANT _UTUI-SC-O-H
32 CONSTANT _UTUI-SC-O-STYLE
40 CONSTANT _UTUI-SC-O-FLAGS
48 CONSTANT _UTUI-SC-O-WPTR
56 CONSTANT _UTUI-SC-O-PAD
64 CONSTANT _UTUI-SC-O-OFFS
72 CONSTANT _UTUI-SC-O-MARGIN

\ Sidecar flag bits
1 CONSTANT _UTUI-SCF-HAS     \ sidecar allocated
2 CONSTANT _UTUI-SCF-VIS     \ visible
4 CONSTANT _UTUI-SCF-FOC     \ focused
8 CONSTANT _UTUI-SCF-HIDE    \ display:none

\ =====================================================================
\  §1a — Element → Sidecar mapping
\ =====================================================================

VARIABLE _UTUI-ELEM-BASE   \ set at load time to _UDL-ELEMS

: _UTUI-SC-IDX  ( elem -- idx )
    _UTUI-ELEM-BASE @ -  _UDL-ELEMSZ / ;

: _UTUI-SIDECAR  ( elem -- sc )
    _UTUI-SC-IDX _UTUI-SC-SZ * _UTUI-SIDECARS + ;

\ Field accessors
: _UTUI-SC-ROW@   ( sc -- n ) _UTUI-SC-O-ROW   + @ ;
: _UTUI-SC-COL@   ( sc -- n ) _UTUI-SC-O-COL   + @ ;
: _UTUI-SC-W@     ( sc -- n ) _UTUI-SC-O-W     + @ ;
: _UTUI-SC-H@     ( sc -- n ) _UTUI-SC-O-H     + @ ;
: _UTUI-SC-STYLE@ ( sc -- s ) _UTUI-SC-O-STYLE + @ ;
: _UTUI-SC-FLAGS@ ( sc -- f ) _UTUI-SC-O-FLAGS + @ ;

: _UTUI-SC-ROW!   ( n sc -- ) _UTUI-SC-O-ROW   + ! ;
: _UTUI-SC-COL!   ( n sc -- ) _UTUI-SC-O-COL   + ! ;
: _UTUI-SC-W!     ( n sc -- ) _UTUI-SC-O-W     + ! ;
: _UTUI-SC-H!     ( n sc -- ) _UTUI-SC-O-H     + ! ;
: _UTUI-SC-STYLE! ( s sc -- ) _UTUI-SC-O-STYLE + ! ;
: _UTUI-SC-FLAGS! ( f sc -- ) _UTUI-SC-O-FLAGS + ! ;
: _UTUI-SC-WPTR@  ( sc -- p ) _UTUI-SC-O-WPTR  + @ ;
: _UTUI-SC-WPTR!  ( p sc -- ) _UTUI-SC-O-WPTR  + ! ;

\ New sidecar field accessors (padding, offsets, margin)
: _UTUI-SC-PAD@    ( sc -- n ) _UTUI-SC-O-PAD    + @ ;
: _UTUI-SC-PAD!    ( n sc -- ) _UTUI-SC-O-PAD    + ! ;
: _UTUI-SC-OFFS@   ( sc -- n ) _UTUI-SC-O-OFFS   + @ ;
: _UTUI-SC-OFFS!   ( n sc -- ) _UTUI-SC-O-OFFS   + ! ;
: _UTUI-SC-MARGIN@ ( sc -- n ) _UTUI-SC-O-MARGIN + @ ;
: _UTUI-SC-MARGIN! ( n sc -- ) _UTUI-SC-O-MARGIN + ! ;

\ Visibility predicate — also checks display:none (HIDE flag)
: _UTUI-SC-VIS?  ( sc -- flag )
    _UTUI-SC-FLAGS@
    DUP _UTUI-SCF-VIS AND 0<>
    SWAP _UTUI-SCF-HIDE AND 0= AND ;

\ Style-field extended accessors (bits 24+ in the style cell)
\ text-align: bits 24-25  (0=left, 1=center, 2=right)
: _UTUI-SC-TALIGN@ ( sc -- align )
    _UTUI-SC-STYLE@ 24 RSHIFT 3 AND ;
\ position:   bits 26-27  (0=static, 1=absolute, 2=fixed)
: _UTUI-SC-POS@    ( sc -- pos )
    _UTUI-SC-STYLE@ 26 RSHIFT 3 AND ;
\ z-index:    bits 28-35  (unsigned 0-255)
: _UTUI-SC-ZIDX@   ( sc -- z )
    _UTUI-SC-STYLE@ 28 RSHIFT 255 AND ;

\ Pack/unpack 4 unsigned bytes (T R B L) for padding / margin
\   Packing: top in bits 0-7, right in bits 8-15,
\            bottom in bits 16-23, left in bits 24-31
: _UTUI-PACK-TRBL  ( t r b l -- packed )
    24 LSHIFT SWAP 16 LSHIFT OR SWAP 8 LSHIFT OR SWAP OR ;

: _UTUI-UNPACK-TRBL  ( packed -- t r b l )
    DUP 255 AND                     \ top
    OVER 8 RSHIFT 255 AND          \ right
    2 PICK 16 RSHIFT 255 AND       \ bottom
    3 PICK 24 RSHIFT 255 AND       \ left
    >R >R >R NIP R> R> R> ;        \ clean the original, leave t r b l

\ Pack/unpack 4 signed 16-bit offsets for position offsets
\   Packing: top bits 0-15, right bits 16-31,
\            bottom bits 32-47, left bits 48-63
: _UTUI-PACK-OFFS  ( top right bottom left -- packed )
    0xFFFF AND 48 LSHIFT
    SWAP 0xFFFF AND 32 LSHIFT OR
    SWAP 0xFFFF AND 16 LSHIFT OR
    SWAP 0xFFFF AND OR ;

\ Sign-extend a 16-bit value to cell
: _UTUI-SEXT16  ( u16 -- signed )
    DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN ;

: _UTUI-UNPACK-OFFS  ( packed -- top right bottom left )
    DUP 0xFFFF AND _UTUI-SEXT16                  \ top
    OVER 16 RSHIFT 0xFFFF AND _UTUI-SEXT16       \ right
    2 PICK 32 RSHIFT 0xFFFF AND _UTUI-SEXT16     \ bottom
    3 PICK 48 RSHIFT 0xFFFF AND _UTUI-SEXT16     \ left
    >R >R >R NIP R> R> R> ;

\ Unpack style → fg bg attrs
: _UTUI-UNPACK-STYLE  ( style -- fg bg attrs )
    DUP 255 AND                 \ fg  (bits 0–7)
    OVER 8 RSHIFT 255 AND      \ bg  (bits 8–15)
    ROT 16 RSHIFT 255 AND ;    \ attrs (bits 16–23)

\ Pack fg bg attrs → style
: _UTUI-PACK-STYLE  ( fg bg attrs -- style )
    16 LSHIFT                   \ attrs << 16
    SWAP 8 LSHIFT OR            \ bg << 8
    SWAP OR ;                   \ fg

\ Apply sidecar style to draw engine; add reverse-video when focused
: _UTUI-APPLY-STYLE  ( sc -- )
    DUP _UTUI-SC-FLAGS@ _UTUI-SCF-FOC AND >R
    _UTUI-SC-STYLE@ _UTUI-UNPACK-STYLE   ( fg bg attrs )
    R> IF CELL-A-REVERSE OR THEN
    DRW-STYLE! ;

\ Clear all sidecars
: _UTUI-SC-CLEAR-ALL  ( -- )
    _UTUI-SIDECARS _UTUI-MAX-ELEMS _UTUI-SC-SZ * 0 FILL ;

\ Public style readers — extract fg/bg/attrs from an element's resolved
\ sidecar style.  These are available after UTUI-LOAD returns.
: UTUI-SC-FG@    ( elem -- fg )    _UTUI-SIDECAR _UTUI-SC-STYLE@ 255 AND ;
: UTUI-SC-BG@    ( elem -- bg )    _UTUI-SIDECAR _UTUI-SC-STYLE@ 8 RSHIFT 255 AND ;
: UTUI-SC-ATTRS@ ( elem -- attrs ) _UTUI-SIDECAR _UTUI-SC-STYLE@ 16 RSHIFT 255 AND ;

\ Public geometry reader — returns element's layout rectangle.
: UTUI-ELEM-RGN  ( elem -- row col h w )
    _UTUI-SIDECAR >R
    R@ _UTUI-SC-ROW@
    R@ _UTUI-SC-COL@
    R@ _UTUI-SC-H@
    R> _UTUI-SC-W@ ;

\ =====================================================================
\  §1b — Dynamic Sidecar Helpers
\ =====================================================================

\ _UTUI-SC-ALLOC ( elem -- )
\   Zero-fill the sidecar for elem and set the HAS flag.
\   The sidecar pool is pre-allocated to _UTUI-MAX-ELEMS, matching
\   the element pool size, so no growth is needed.
: _UTUI-SC-ALLOC  ( elem -- )
    _UTUI-SIDECAR
    DUP _UTUI-SC-SZ 0 FILL
    _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS@ OR SWAP _UTUI-SC-FLAGS! ;

\ _UTUI-SC-FREE ( elem -- )
\   Zero-fill the sidecar, clearing the HAS flag.
: _UTUI-SC-FREE  ( elem -- )
    _UTUI-SIDECAR _UTUI-SC-SZ 0 FILL ;

\ Default style: light gray on dark gray, no attrs
253 236 0 _UTUI-PACK-STYLE CONSTANT _UTUI-DEFAULT-STYLE

\ Mask for CSS-inheritable properties:
\   fg(0-7), bg(8-15), attrs(16-23), text-align(24-25)
\ Non-inheritable (position 26-27, z-index 28-35) are excluded.
0x03FFFFFF CONSTANT _UTUI-INHERIT-MASK

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

CREATE _UTUI-PROXY-RGN  _RGN-DESC-SIZE ALLOT

: _UTUI-SYNC-PROXY  ( sc -- )
    DUP _UTUI-SC-ROW@ _UTUI-PROXY-RGN _RGN-O-ROW + !
    DUP _UTUI-SC-COL@ _UTUI-PROXY-RGN _RGN-O-COL + !
    DUP _UTUI-SC-H@   _UTUI-PROXY-RGN _RGN-O-H   + !
        _UTUI-SC-W@   _UTUI-PROXY-RGN _RGN-O-W   + ! ;

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
VARIABLE _UR-TMP   VARIABLE _UR-ELEM
VARIABLE _UR-EV    \ saved event pointer

\ Write _UR-* temp vars into the shared proxy region.
: _UTUI-PROXY-FROM-UR  ( -- )
    _UR-ROW @ _UTUI-PROXY-RGN _RGN-O-ROW + !
    _UR-COL @ _UTUI-PROXY-RGN _RGN-O-COL + !
    _UR-H @   _UTUI-PROXY-RGN _RGN-O-H   + !
    _UR-W @   _UTUI-PROXY-RGN _RGN-O-W   + ! ;

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

VARIABLE _UTUI-RGN        \ root region for the document
VARIABLE _UTUI-DOC-LOADED \ flag: document loaded?
VARIABLE _UTUI-STATE      \ bound state-tree
VARIABLE _UTUI-FOCUS-P    \ currently focused element (0 = none)
VARIABLE _UTUI-NEEDS-PAINT \ global: any UIDL/widget change needs repaint

0 _UTUI-RGN !
0 _UTUI-DOC-LOADED !
0 _UTUI-STATE !
0 _UTUI-FOCUS-P !
0 _UTUI-NEEDS-PAINT !

\ Public setter for the root region (used by desk to re-assign tiles)
: UTUI-RGN!  ( rgn -- )  _UTUI-RGN ! ;

\ Wire UIDL-DIRTY! hook so any element dirtying auto-signals repaint
: _UTUI-DIRTY-HOOK  ( -- ) _UTUI-NEEDS-PAINT ON ;
' _UTUI-DIRTY-HOOK  _UDL-DIRTY-HOOK !

\ =====================================================================
\  §3 — Action Dispatch Table
\ =====================================================================
\
\  64 entries, each 24 bytes: +0 hash, +8 xt, +16 used

64 CONSTANT _UTUI-MAX-ACTS
CREATE _UTUI-ACTS  _UTUI-MAX-ACTS 24 * ALLOT
VARIABLE _UTUI-ACT-CNT

: _UTUI-ACT-HASH  ( a l -- h )
    2166136261
    SWAP 0 ?DO
        OVER I + C@ XOR
        16777619 *
    LOOP
    NIP ;

: UTUI-DO!  ( do-a do-l xt -- )
    >R
    _UTUI-ACT-CNT @ _UTUI-MAX-ACTS >= IF 2DROP R> DROP EXIT THEN
    _UTUI-ACT-HASH                     ( hash  R: xt )
    _UTUI-ACT-CNT @ 24 * _UTUI-ACTS + ( hash entry  R: xt )
    OVER OVER !                         \ entry+0 = hash
    R> OVER 8 + !                       \ entry+8 = xt
    1 OVER 16 + !                       \ entry+16 = used
    DROP DROP
    1 _UTUI-ACT-CNT +! ;

: _UTUI-ACT-FIND  ( do-a do-l -- xt | 0 )
    _UTUI-ACT-HASH                     ( hash )
    _UTUI-ACT-CNT @ 0 ?DO
        I 24 * _UTUI-ACTS +           ( hash entry )
        DUP 16 + @ IF                  \ used?
            DUP @ 2 PICK = IF         \ hash match?
                8 + @ NIP UNLOOP EXIT
            THEN
        THEN
        DROP
    LOOP
    DROP 0 ;

: _UTUI-FIRE-DO  ( elem -- )
    DUP S" do" UIDL-ATTR IF           ( elem da dl )
        _UTUI-ACT-FIND                 ( elem xt|0 )
        ?DUP IF EXECUTE EXIT THEN
        DROP EXIT
    THEN
    2DROP DROP ;

: _UTUI-ACT-CLEAR  ( -- )
    0 _UTUI-ACT-CNT !
    _UTUI-ACTS _UTUI-MAX-ACTS 24 * 0 FILL ;

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
    DUP _UTUI-SC-ROW@ _UR-ROW !
    DUP _UTUI-SC-COL@ _UR-COL !
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
            DROP NIP                   ( n )
            NUM>STR EXIT
        THEN
        DUP ST-T-BOOLEAN = IF
            DROP NIP
            IF S" true" ELSE S" false" THEN EXIT
        THEN
        DROP 2DROP S" "
    ELSE
        2DROP S" "                     \ no bind — UIDL-BIND returned (0 0 0)
    THEN ;

\ --- Get display text: bind= first, then text= attr, then empty ---
: _UTUI-DISPLAY-TEXT  ( elem -- a l )
    DUP UIDL-BIND IF                   ( elem ba bl )
        ROT DROP                        \ drop elem, keep bind str
        LEL-EVAL                        ( type v1 v2 )
        ROT                            ( v1 v2 type )
        DUP ST-T-STRING  = IF DROP EXIT THEN
        DUP ST-T-INTEGER = IF
            DROP NIP
            NUM>STR EXIT
        THEN
        DUP ST-T-BOOLEAN = IF
            DROP NIP
            IF S" true" ELSE S" false" THEN EXIT
        THEN
        DROP 2DROP S" "
    ELSE 2DROP                          \ UIDL-BIND returned (0 0 0), elem still on stack
        S" text" UIDL-ATTR IF EXIT THEN
        2DROP 0 0
    THEN ;

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
    RGN-ROOT ;

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
    _UTUI-SIDECAR _UTUI-SC-WPTR@ ?DUP IF  ( wptr )
        _UTUI-PROXY-FROM-UR
        _UTUI-PROXY-RGN RGN-USE
        DUP _WDG-O-DRAW-XT + @ EXECUTE
        RGN-ROOT
    THEN ;

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
    \ Sync proxy region from cached sidecar geometry
    _UR-ROW @ _UTUI-PROXY-RGN _RGN-O-ROW + !
    _UR-COL @ _UTUI-PROXY-RGN _RGN-O-COL + !
    _UR-H @   _UTUI-PROXY-RGN _RGN-O-H   + !
    _UR-W @   _UTUI-PROXY-RGN _RGN-O-W   + !
    _UTUI-PROXY-RGN RGN-USE
    _TREE-DRAW
    RGN-ROOT ;

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
    RGN-ROOT ;

\ --- Canvas: fill background (actual CVS-* drawing is app-level) ---
: _UTUI-RENDER-CANVAS  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP _UTUI-FILL-BG ;

\ --- Scroll: background fill (scroll indicators TODO) ---
: _UTUI-RENDER-SCROLL  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP _UTUI-FILL-BG ;

\ --- NOP ---
: _UTUI-RENDER-NOP  ( elem -- ) DROP ;

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

\ Stubs for complex handlers — TODO
: _UTUI-H-MENU     ( elem key-ev -- handled? ) 2DROP 0 ;
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

\ Tree: delegate to materialized TREE widget's _TREE-HANDLE
: _UTUI-H-TREE  ( elem key-ev -- handled? )
    OVER _UTUI-SIDECAR                    ( elem ev sc )
    DUP _UTUI-SC-WPTR@                    ( elem ev sc wptr )
    DUP 0= IF DROP DROP 2DROP 0 EXIT THEN
    >R _UTUI-SYNC-PROXY                   ( elem ev   R: wptr )
    NIP R>                                 ( ev wptr )
    _TREE-HANDLE ;

\ Tabs: Left/Right to switch active tab
: _UTUI-H-TABS  ( elem key-ev -- handled? )
    KEY-CODE@                              ( elem code )
    OVER _UTUI-SIDECAR _UTUI-SC-WPTR@     ( elem code state )
    DUP 0= IF DROP 2DROP 0 EXIT THEN
    >R                                      ( elem code  R: state )
    DUP KEY-LEFT = IF
        DROP
        R@ @ 0> IF
            R@ @ 1- R@ !
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
    IF DROP -1 EXIT THEN
    DUP UIDL-TYPE UIDL-T-TEXTAREA = IF DROP 0 EXIT THEN
    DUP UIDL-TYPE UIDL-T-CANVAS   = IF DROP 0 EXIT THEN
    UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
        ED.FLAGS @ EL-CONTENT-MODEL
        DUP EL-CONTAINER = OVER EL-FIXED-2 = OR
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
                _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
                _UL-POS @ OVER _UTUI-SC-ROW!
                _UL-COL @ OVER _UTUI-SC-COL!
                0 OVER _UTUI-SC-W!
                0 OVER _UTUI-SC-H!
                DROP
            ELSE
                DUP _UL-READ-CHILD-MARGIN
                _ULM-T @ _UL-POS +!       \ advance pos by margin-top

                _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
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
            _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
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

            _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
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
            _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
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
            _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
            _UL-ROW @ OVER _UTUI-SC-ROW!
            _UL-POS @ OVER _UTUI-SC-COL!
            _UL-CW @ 2 + OVER _UTUI-SC-W!
            1 OVER _UTUI-SC-H!
            _UL-CW @ 2 + _UL-POS +!
            DROP                       ( child )
        ELSE                           ( child csc )
            _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
            DROP                       ( child )
        THEN
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

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
            _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
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
            _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
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
        _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
        _USP-ROW @ OVER _UTUI-SC-ROW!
        _USP-COL @ OVER _UTUI-SC-COL!
        _USP-LW @              OVER _UTUI-SC-W!
        _USP-SH @              OVER _UTUI-SC-H!
    ELSE
        _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
    THEN
    DROP                               ( child1 )

    \ Second child = right pane
    UIDL-NEXT-SIB
    DUP 0= IF DROP EXIT THEN
    DUP _UTUI-SIDECAR                 ( child2 sc2 )
    OVER UIDL-EVAL-WHEN IF
        _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
        _USP-ROW @                                    OVER _UTUI-SC-ROW!
        _USP-COL @ _USP-LW @ + 1 +                   OVER _UTUI-SC-COL!
        _USP-RW @                                     OVER _UTUI-SC-W!
        _USP-SH @                                     OVER _UTUI-SC-H!
    ELSE
        _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
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

\ --- Scroll ---
: _UTUI-LAYOUT-SCROLL  ( elem -- ) _UTUI-LAYOUT-STACK ;

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

    \ Mark as visible (positioned elements were skipped in flow layout)
    _UPO-SC @ _UTUI-SC-FLAGS@
    _UTUI-SCF-HAS _UTUI-SCF-VIS OR OR
    _UPO-SC @ _UTUI-SC-FLAGS!

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
    ['] _UTUI-RENDER-NOP       UIDL-T-UIDL       EL-SET-RENDER

    \ --- Event XTs ---
    ['] _UTUI-H-ACTION         UIDL-T-ACTION     EL-SET-EVENT
    ['] _UTUI-H-INPUT          UIDL-T-INPUT      EL-SET-EVENT
    ['] _UTUI-H-TOGGLE         UIDL-T-TOGGLE     EL-SET-EVENT
    ['] _UTUI-H-MENU           UIDL-T-MENU       EL-SET-EVENT
    ['] _UTUI-H-TEXTAREA       UIDL-T-TEXTAREA   EL-SET-EVENT
    ['] _UTUI-H-LIST           UIDL-T-COLLECTION EL-SET-EVENT
    ['] _UTUI-H-TREE           UIDL-T-TREE       EL-SET-EVENT
    ['] _UTUI-H-TABS           UIDL-T-TABS       EL-SET-EVENT
    ['] _UTUI-H-DIALOG         UIDL-T-DIALOG     EL-SET-EVENT
    ['] _UTUI-H-CANVAS         UIDL-T-CANVAS     EL-SET-EVENT
    ['] _UTUI-H-REGION         UIDL-T-REGION     EL-SET-EVENT
    ['] _UTUI-H-REGION         UIDL-T-GROUP      EL-SET-EVENT

    \ --- Layout XTs ---
    ['] _UTUI-LAYOUT-DISPATCH  UIDL-T-REGION     EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-DISPATCH  UIDL-T-GROUP      EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-MBAR      UIDL-T-MENUBAR    EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-STATUS    UIDL-T-STATUS     EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-TOOLBAR   UIDL-T-TOOLBAR    EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-DLG       UIDL-T-DIALOG     EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-SPLIT     UIDL-T-SPLIT      EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-TABS      UIDL-T-TABS       EL-SET-LAYOUT
    ['] _UTUI-LAYOUT-SCROLL    UIDL-T-SCROLL     EL-SET-LAYOUT
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
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-HAS OR _UTUI-SCF-VIS OR
        SWAP _UTUI-SC-FLAGS!
    ELSE
        DUP _UTUI-SIDECAR
        _UTUI-SCF-HAS SWAP _UTUI-SC-FLAGS!
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

: UTUI-RELAYOUT  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN

    DUP _UTUI-SIDECAR
    _UTUI-RGN @ RGN-ROW OVER _UTUI-SC-ROW!
    _UTUI-RGN @ RGN-COL OVER _UTUI-SC-COL!
    _UTUI-RGN @ RGN-W   OVER _UTUI-SC-W!
    _UTUI-RGN @ RGN-H   OVER _UTUI-SC-H!
    _UTUI-DEFAULT-STYLE  OVER _UTUI-SC-STYLE!
    _UTUI-SCF-HAS _UTUI-SCF-VIS OR SWAP _UTUI-SC-FLAGS!

    UIDL-ROOT _UTUI-DO-LAYOUT-REC ;

\ =====================================================================
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

\ Paint a single element (calls its render-xt)
: _UTUI-RENDER-ONE  ( elem -- )
    DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
        ED.RENDER-XT @ DUP ['] NOOP <> IF
            OVER SWAP EXECUTE
        ELSE DROP THEN
    THEN
    UIDL-CLEAN! ;

\ --- Paint entire subtree (element + all descendants) ---
\ Used in Pass 2 for overlay elements that were deferred from Pass 1.
\ Does NOT re-defer elements — all descendants paint unconditionally.
VARIABLE _UPST-ROOT

: _UTUI-PAINT-SUBTREE  ( elem -- )
    DUP _UPST-ROOT !
    BEGIN
        DUP _UTUI-SIDECAR _UTUI-SC-VIS? IF
            DUP _UTUI-RENDER-ONE
        ELSE DUP UIDL-CLEAN! THEN
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP _UPST-ROOT @ = IF DROP 0 TRUE
                ELSE
                    DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                    ELSE
                        UIDL-PARENT
                        DUP _UPST-ROOT @ = IF DROP 0 TRUE
                        ELSE DUP 0= IF TRUE ELSE FALSE THEN
                        THEN
                    THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ --- Skip-children flag ---
\ Set by _UTUI-PAINT-ELEM when an element is deferred to the overlay
\ buffer; tells the Pass 1 DFS to skip the element's subtree.
VARIABLE _UTUI-SKIP-CHILDREN

: _UTUI-PAINT-ELEM  ( elem -- )
    0 _UTUI-SKIP-CHILDREN !
    DUP UIDL-DIRTY? 0= IF DROP EXIT THEN
    DUP _UTUI-SIDECAR _UTUI-SC-VIS? 0= IF
        UIDL-CLEAN! EXIT
    THEN
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
    \ Reset to full-screen clip — render words use absolute sidecar
    \ coordinates, so there must be no region offset active.
    RGN-ROOT
    0 _UTUI-OVERLAY-CNT !
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    \ Pass 1: normal flow elements (skip subtrees of deferred overlays)
    BEGIN
        DUP _UTUI-PAINT-ELEM
        _UTUI-SKIP-CHILDREN @ IF
            \ Deferred element — skip its entire subtree
            _UTUI-SKIP-SUBTREE
            DUP 0= IF DROP _UTUI-PAINT-PASS2 EXIT THEN
        ELSE
            DUP UIDL-FIRST-CHILD ?DUP IF NIP
            ELSE
                _UTUI-PAINT-WALK-UP
                DUP 0= IF DROP _UTUI-PAINT-PASS2 EXIT THEN
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
    OVER KEY-DOWN = OVER 0= AND IF
        2DROP UTUI-FOCUS-NEXT -1 EXIT THEN
    OVER KEY-RIGHT = OVER 0= AND IF
        2DROP UTUI-FOCUS-NEXT -1 EXIT THEN
    OVER KEY-UP = OVER 0= AND IF
        2DROP UTUI-FOCUS-PREV -1 EXIT THEN
    OVER KEY-LEFT = OVER 0= AND IF
        2DROP UTUI-FOCUS-PREV -1 EXIT THEN

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

: UTUI-DISPATCH-MOUSE  ( row col btn -- handled? )
    DROP                                \ btn unused for now
    UTUI-HIT-TEST                      ( elem | 0 )
    DUP 0= IF EXIT THEN
    DUP _UTUI-FOCUSABLE? IF
        DUP UTUI-FOCUS!
    THEN
    _UTUI-FIRE-DO -1 ;

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
                IF DUP UIDL-DIRTY! THEN
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

\ --- Focus save / restore ---
VARIABLE _UTUI-SAVED-FOCUS     \ stashed focus elem for overlay hide

\ --- Show / hide by element pointer ---

: _UTUI-VIS-SUBTREE!  ( flag elem -- )
    \ Set or clear VIS on elem + all descendants.
    SWAP >R
    DUP _UDST-ROOT !
    BEGIN
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@
        R@ IF _UTUI-SCF-VIS OR ELSE _UTUI-SCF-VIS INVERT AND THEN
        SWAP _UTUI-SC-FLAGS!
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

: _UTUI-DEMATERIALIZE  ( -- )
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _UTUI-SIDECAR _UTUI-SC-WPTR@  ( elem wptr )
        ?DUP IF
            OVER UIDL-TYPE             ( elem wptr type )
            DUP UIDL-T-TREE = IF
                DROP TREE-FREE
            ELSE DUP UIDL-T-INPUT = IF
                DROP
                DUP _INP-O-BUF-A + @ FREE
                FREE
            ELSE DUP UIDL-T-TEXTAREA = IF
                DROP
                DUP _TXTA-O-BUF-A + @ FREE
                FREE
            ELSE
                DROP FREE              \ tabs state, etc.
            THEN THEN THEN
            0 OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
        THEN
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
    DUP _UTUI-SIDECAR _UTUI-SC-WPTR@  ( elem wptr )
    ?DUP IF
        OVER UIDL-TYPE                 ( elem wptr type )
        DUP UIDL-T-TREE = IF
            DROP TREE-FREE
        ELSE DUP UIDL-T-INPUT = IF
            DROP
            DUP _INP-O-BUF-A + @ FREE
            FREE
        ELSE DUP UIDL-T-TEXTAREA = IF
            DROP
            DUP _TXTA-O-BUF-A + @ FREE
            FREE
        ELSE
            DROP FREE
        THEN THEN THEN
        0 OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
    THEN
    DROP ;
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
            _UPRE-STY @  0x0C000000 INVERT AND  0x04000000 OR  _UPRE-STY !
        ELSE 2DUP S" fixed" STR-STRI= IF
            2DROP
            _UPRE-STY @  0x0C000000 INVERT AND  0x08000000 OR  _UPRE-STY !
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
\   Parse text-align value and set bits 24-25 of style.
: _UTUI-CSS-SET-ALIGN  ( val-a val-u -- )
    2DUP S" center" STR-STRI= IF
        2DROP
        _URES-STYLE @  0x03000000 INVERT AND  0x01000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DUP S" right" STR-STRI= IF
        2DROP
        _URES-STYLE @  0x03000000 INVERT AND  0x02000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DROP ;   \ "left" or unknown → 0 (default)

\ _UTUI-CSS-SET-POSITION ( val-a val-u -- )
\   Parse position value and set bits 26-27 of style.
: _UTUI-CSS-SET-POSITION  ( val-a val-u -- )
    2DUP S" absolute" STR-STRI= IF
        2DROP
        _URES-STYLE @  0x0C000000 INVERT AND  0x04000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DUP S" fixed" STR-STRI= IF
        2DROP
        _URES-STYLE @  0x0C000000 INVERT AND  0x08000000 OR  _URES-STYLE !
        EXIT
    THEN
    2DROP ;   \ "static" or unknown → 0 (default)

\ _UTUI-CSS-SET-ZINDEX ( val-a val-u -- )
\   Parse z-index integer (0-255) and set bits 28-35 of style.
: _UTUI-CSS-SET-ZINDEX  ( val-a val-u -- )
    _UTUI-CSS-INT 0= IF DROP EXIT THEN
    DUP 0 < IF DROP 0 THEN
    255 MIN
    28 LSHIFT
    _URES-STYLE @  0xFF0000000 INVERT AND  OR  _URES-STYLE ! ;

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

\ =====================================================================
\  §17 — UTUI-LOAD
\ =====================================================================

: UTUI-BY-ID  ( id-a id-l -- elem | 0 )  UIDL-BY-ID ;

\ UTUI-WIDGET@ ( elem -- wptr | 0 )
\   Return the widget pointer associated with a UIDL element, or 0.
: UTUI-WIDGET@  ( elem -- wptr | 0 )
    _UTUI-SIDECAR _UTUI-SC-WPTR@ ;

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

\ UTUI-REMOVE-ELEM ( elem -- )
\   Dematerialize, free sidecar, unlink from tree.  Marks parent
\   dirty + signals repaint.
: UTUI-REMOVE-ELEM  ( elem -- )
    DUP _UTUI-DEMATERIALIZE-ONE
    DUP UIDL-PARENT ?DUP IF UIDL-DIRTY! THEN
    DUP _UTUI-SC-FREE
    UIDL-REMOVE-ELEM
    _UTUI-NEEDS-PAINT ON ;

\ UTUI-SET-ATTR ( elem na nl va vl -- )
\   Set attribute + auto-dirty the element and signal repaint.
\   UIDL-SET-ATTR doesn't call UIDL-DIRTY! itself, so we keep
\   elem on stack and dirty it after the attribute is written.
: UTUI-SET-ATTR  ( elem na nl va vl -- )
    4 PICK >R
    UIDL-SET-ATTR
    R> UIDL-DIRTY! ;

\ UTUI-WIDGET-SET ( wptr elem -- )
\   Attach a manually created widget to a UIDL element.
\   The widget is drawn automatically by UTUI-PAINT when it
\   visits this element.  Pass 0 as wptr to detach.
: UTUI-WIDGET-SET  ( wptr elem -- )
    DUP >R
    _UTUI-SIDECAR _UTUI-SC-WPTR!
    R> UIDL-DIRTY!
    _UTUI-NEEDS-PAINT ON ;

: UTUI-BIND-STATE  ( st -- )
    DUP _UTUI-STATE !
    ST-USE ;

: UTUI-LOAD  ( xml-a xml-u rgn -- flag )
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

    _UTUI-PRELAYOUT-STYLES             \ §16c: position, display, padding, margin
    UTUI-RELAYOUT          DROP        \ (leaks 1 item — drop it)
    _UTUI-RESOLVE-STYLES               \ §16b: colors, text-align, z-index, dims, offsets
    _UTUI-RESOLVE-POSITIONED           \ §7b: place absolute/fixed elements
    _UTUI-MATERIALIZE
    _UTUI-WIRE-SUBS

    0 _UTUI-FOCUS-P !
    UTUI-FOCUS-NEXT

    -1 _UTUI-DOC-LOADED !
    -1 ;

\ =====================================================================
\  §18 — UTUI-DETACH
\ =====================================================================

: UTUI-DETACH  ( -- )
    _UTUI-DEMATERIALIZE
    _UTUI-SC-CLEAR-ALL
    _UTUI-ACT-CLEAR
    _UTUI-SHORT-CLEAR
    UIDL-RESET-SUBS
    0 _UTUI-FOCUS-P !
    0 _UTUI-DOC-LOADED !
    0 _UTUI-RGN ! ;

\ =====================================================================
\  §18b — UIDL Context Save / Restore  (UCTX)
\ =====================================================================
\
\  Per sub-app UIDL context buffer holding 15 scalar variables and
\  10 pool arrays.  Total ~99,448 bytes (~97 KiB).
\
\  This section lives in uidl-tui.f because it must enumerate every
\  private _UDL-* and _UTUI-* variable and pool.  The shell (browser)
\  calls only the public API: UCTX-ALLOC, UCTX-FREE, UCTX-SAVE,
\  UCTX-RESTORE, UCTX-CLEAR, UCTX-TOTAL.

15 CONSTANT _UCTX-NVAR
120 CONSTANT _UCTX-VAR-SZ       \ 15 × 8

\ Pool sizes (must match module declarations)
32768 CONSTANT _UCTX-ELEMS-SZ   \ 256 × 128
20480 CONSTANT _UCTX-ATTRS-SZ   \ 512 × 40
12288 CONSTANT _UCTX-STRS-SZ
 2048 CONSTANT _UCTX-HASH-SZ    \ 256 × 8
 4096 CONSTANT _UCTX-HIDS-SZ    \ 256 × 16
 3072 CONSTANT _UCTX-SUBS-SZ    \ 128 × 24
20480 CONSTANT _UCTX-SC-SZ      \ 256 × 80
 1536 CONSTANT _UCTX-ACTS-SZ    \ 64 × 24
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
    _UTUI-RGN           _UCTX-VARS 14 CELLS + ! ;
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

: UCTX-FREE  ( ctx -- )  FREE ;

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
' UTUI-DO!            CONSTANT _utui-do-s-xt
' UTUI-SHOW-DIALOG    CONSTANT _utui-show-dialog-xt
' UTUI-HIDE-DIALOG    CONSTANT _utui-hide-dialog-xt
' UTUI-HIT-TEST       CONSTANT _utui-hit-test-xt
' UTUI-DETACH         CONSTANT _utui-detach-xt
' UTUI-INSTALL-XTS    CONSTANT _utui-install-xts-xt
' UTUI-ADD-ELEM       CONSTANT _utui-add-elem-xt
' UTUI-REMOVE-ELEM    CONSTANT _utui-remove-elem-xt
' UTUI-SET-ATTR       CONSTANT _utui-set-attr-xt
' UTUI-WIDGET-SET     CONSTANT _utui-widget-set-xt
' UTUI-ELEM-RGN       CONSTANT _utui-elem-rgn-xt

: UTUI-LOAD           _utui-load-xt           _utui-guard WITH-GUARD ;
: UTUI-BIND-STATE     _utui-bind-state-xt     _utui-guard WITH-GUARD ;
: UTUI-PAINT          _utui-paint-xt          _utui-guard WITH-GUARD ;
: UTUI-RELAYOUT       _utui-relayout-xt       _utui-guard WITH-GUARD ;
: UTUI-DISPATCH-KEY   _utui-dispatch-key-xt   _utui-guard WITH-GUARD ;
: UTUI-DISPATCH-MOUSE _utui-dispatch-mouse-xt _utui-guard WITH-GUARD ;
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
: UTUI-DETACH         _utui-detach-xt         _utui-guard WITH-GUARD ;
: UTUI-INSTALL-XTS    _utui-install-xts-xt    _utui-guard WITH-GUARD ;
: UTUI-ADD-ELEM       _utui-add-elem-xt       _utui-guard WITH-GUARD ;
: UTUI-REMOVE-ELEM    _utui-remove-elem-xt    _utui-guard WITH-GUARD ;
: UTUI-SET-ATTR       _utui-set-attr-xt       _utui-guard WITH-GUARD ;
: UTUI-WIDGET-SET     _utui-widget-set-xt     _utui-guard WITH-GUARD ;
: UTUI-ELEM-RGN       _utui-elem-rgn-xt       _utui-guard WITH-GUARD ;
[THEN] [THEN]
