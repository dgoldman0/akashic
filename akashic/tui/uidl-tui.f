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

\ =====================================================================
\  §1 — TUI Sidecar (per-element, 56 bytes)
\ =====================================================================
\
\  Parallel array indexed by element pool index:
\    elem-index = (elem – _UDL-ELEMS) / _UDL-ELEMSZ
\    sidecar    = elem-index × 56 + _UTUI-SIDECARS
\
\  Fields:
\    +0  row     Computed row in screen coordinates (cell)
\    +8  col     Computed column (cell)
\   +16  width   Computed width (cells)
\   +24  height  Computed height (cells)
\   +32  style   Packed: fg(8) bg(8) attrs(8) border(8)
\   +40  flags   Bit 0=has-sidecar, 1=visible, 2=focused
\   +48  wptr    Widget struct pointer (0 = none)

56 CONSTANT _UTUI-SC-SZ
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

\ Sidecar flag bits
1 CONSTANT _UTUI-SCF-HAS     \ sidecar allocated
2 CONSTANT _UTUI-SCF-VIS     \ visible
4 CONSTANT _UTUI-SCF-FOC     \ focused

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

\ Visibility predicate
: _UTUI-SC-VIS?  ( sc -- flag )
    _UTUI-SC-FLAGS@ _UTUI-SCF-VIS AND 0<> ;

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

\ Apply sidecar style to draw engine
: _UTUI-APPLY-STYLE  ( sc -- )
    _UTUI-SC-STYLE@ _UTUI-UNPACK-STYLE DRW-STYLE! ;

\ Clear all sidecars
: _UTUI-SC-CLEAR-ALL  ( -- )
    _UTUI-SIDECARS _UTUI-MAX-ELEMS _UTUI-SC-SZ * 0 FILL ;

\ =====================================================================
\  §1b — Proxy Region (shared by all materialized widgets)
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
\  §1c — UIDL ↔ Widget Callbacks
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
\  §2 — Global State
\ =====================================================================

VARIABLE _UTUI-RGN        \ root region for the document
VARIABLE _UTUI-DOC-LOADED \ flag: document loaded?
VARIABLE _UTUI-STATE      \ bound state-tree
VARIABLE _UTUI-FOCUS-P    \ currently focused element (0 = none)

0 _UTUI-RGN !
0 _UTUI-DOC-LOADED !
0 _UTUI-STATE !
0 _UTUI-FOCUS-P !

\ Default style: light gray on dark gray, no attrs
253 236 0 _UTUI-PACK-STYLE CONSTANT _UTUI-DEFAULT-STYLE

\ --- Shared temp vars for render/layout (KDOS pattern) ---
VARIABLE _UR-ROW   VARIABLE _UR-COL
VARIABLE _UR-W     VARIABLE _UR-H
VARIABLE _UR-TMP   VARIABLE _UR-ELEM
VARIABLE _UR-EV    \ saved event pointer

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
        _UKP-A @ C@ _UKP-MOD @ EXIT
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
                DUP 8 + @ 3 PICK = IF \ mod-mask match?
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
    _UTUI-DISPLAY-TEXT                 ( a l )
    _UR-W @ MIN                        \ clip to width
    _UR-ROW @ _UR-COL @ DRW-TEXT ;

\ --- Action button ---
: _UTUI-RENDER-ACTION  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    _UTUI-DISPLAY-TEXT                 ( a l )
    _UR-ROW @ _UR-COL @ _UR-W @ DRW-TEXT-CENTER ;

\ --- Input ---
: _UTUI-RENDER-INPUT  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    _UTUI-FILL-BG
    _UTUI-DISPLAY-TEXT                 ( a l )
    _UR-W @ MIN
    _UR-ROW @ _UR-COL @ DRW-TEXT ;

\ --- Separator ---
: _UTUI-RENDER-SEP  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP
    9472 _UR-ROW @ _UR-COL @ _UR-W @ DRW-HLINE ;

\ --- Region / container: fill background ---
: _UTUI-RENDER-REGION  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP _UTUI-FILL-BG ;

\ --- Menubar ---
: _UTUI-RENDER-MBAR  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    \ Fill bar background (1 row)
    32 _UR-ROW @ _UR-COL @ 1 _UR-W @ DRW-FILL-RECT
    \ Draw each menu child's label
    _UR-COL @ 1+ _UR-TMP !            \ column cursor
    UIDL-FIRST-CHILD                   ( child | 0 )
    BEGIN DUP 0<> WHILE
        DUP S" label" UIDL-ATTR IF    ( child la ll )
            2DUP _UR-ROW @ _UR-TMP @ DRW-TEXT
            NIP 2 + _UR-TMP +!        ( child )
        ELSE 2DROP THEN
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

\ --- Status bar: first child left, last child right ---
VARIABLE _UST-FIRST

: _UTUI-RENDER-STATUS  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    32 _UR-ROW @ _UR-COL @ 1 _UR-W @ DRW-FILL-RECT
    _UR-ELEM !
    \ Left text: first child's display text
    _UR-ELEM @ UIDL-FIRST-CHILD ?DUP IF
        DUP _UST-FIRST !
        _UTUI-DISPLAY-TEXT
        DUP 0<> IF
            _UR-W @ 2 - MIN
            _UR-ROW @ _UR-COL @ 1+ DRW-TEXT
        ELSE 2DROP THEN
    ELSE 0 _UST-FIRST ! THEN
    \ Right text: last child (if different from first)
    _UR-ELEM @ UIDL-LAST-CHILD ?DUP IF
        DUP _UST-FIRST @ <> IF
            _UTUI-DISPLAY-TEXT
            DUP 0<> IF
                DUP _UR-W @ SWAP - 1- 0 MAX
                _UR-COL @ + >R
                _UR-ROW @ R> DRW-TEXT
            ELSE 2DROP THEN
        ELSE DROP THEN
    THEN ;

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
    _UR-W @ * 100 / 0 MAX _UR-W @ MIN  ( fill-w )
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

\ --- Textarea ---
: _UTUI-RENDER-TEXTAREA  ( elem -- )
    _UTUI-STASH-SC 0= IF DROP EXIT THEN
    DROP _UTUI-FILL-BG ;

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

\ Input: printable chars, backspace
: _UTUI-H-INPUT  ( elem key-ev -- handled? )
    DUP KEY-IS-CHAR? IF
        KEY-CODE@                      ( elem char )
        2DROP                          \ TODO: insert into bound value
        -1 EXIT
    THEN
    DUP KEY-CODE@ KEY-BACKSPACE = IF
        2DROP                          \ drop ev, elem
        -1 EXIT
    THEN
    2DROP 0 ;

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
: _UTUI-H-TEXTAREA ( elem key-ev -- handled? ) 2DROP 0 ;
: _UTUI-H-LIST     ( elem key-ev -- handled? ) 2DROP 0 ;
: _UTUI-H-DIALOG   ( elem key-ev -- handled? ) 2DROP 0 ;
: _UTUI-H-CANVAS   ( elem key-ev -- handled? ) 2DROP 0 ;

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

\ --- Stack layout (vertical) ---
: _UTUI-LAYOUT-STACK  ( elem -- )
    _UL-ELEM !
    _UL-ELEM @ _UTUI-SIDECAR _UL-SC !
    _UL-SC @ _UTUI-SC-ROW@ _UL-ROW !
    _UL-SC @ _UTUI-SC-COL@ _UL-COL !
    _UL-SC @ _UTUI-SC-W@   _UL-W !
    _UL-SC @ _UTUI-SC-H@   _UL-H !
    _UL-ROW @ _UL-POS !

    _UL-ELEM @ UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP _UTUI-SIDECAR             ( child csc )
        OVER UIDL-EVAL-WHEN IF        \ UIDL-EVAL-WHEN takes elem (OVER), not sidecar
            _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
            _UL-POS @ OVER _UTUI-SC-ROW!
            _UL-COL @ OVER _UTUI-SC-COL!
            _UL-W @   OVER _UTUI-SC-W!
            \ Height: 1 for leaf, remaining space for containers
            OVER UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
                ED.FLAGS @ EL-CONTENT-MODEL
                DUP EL-CONTAINER = OVER EL-FIXED-2 = OR
                OVER EL-COLLECTION = OR IF
                    DROP
                    _UL-H @ _UL-POS @ _UL-ROW @ - -
                    DUP 0< IF DROP 1 THEN
                ELSE
                    DROP 1
                THEN
            ELSE 1 THEN
            OVER _UTUI-SC-H!
            _UL-SC @ _UTUI-SC-STYLE@ OVER _UTUI-SC-STYLE!
            DROP                       ( child )
            DUP _UTUI-SIDECAR _UTUI-SC-H@ _UL-POS +!
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
            _UTUI-SCF-HAS _UTUI-SCF-VIS OR OVER _UTUI-SC-FLAGS!
            _UL-ROW @ OVER _UTUI-SC-ROW!
            _UL-POS @ OVER _UTUI-SC-COL!
            _UL-CW @  OVER _UTUI-SC-W!
            _UL-H @   OVER _UTUI-SC-H!
            _UL-SC @ _UTUI-SC-STYLE@ OVER _UTUI-SC-STYLE!
            DROP                       ( child )
            _UL-CW @ _UL-POS +!
        ELSE
            _UTUI-SCF-HAS OVER _UTUI-SC-FLAGS!
            DROP                       ( child )
        THEN
        UIDL-NEXT-SIB
    REPEAT
    DROP ;

\ --- Menubar layout ---
: _UTUI-LAYOUT-MBAR  ( elem -- ) DROP ;

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
                _UL-H @ 2 - 0 MAX OVER _UTUI-SC-H!
            ELSE
                \ Inactive: zero dimensions (effectively hidden)
                0 OVER _UTUI-SC-ROW!
                0 OVER _UTUI-SC-COL!
                0 OVER _UTUI-SC-W!
                0 OVER _UTUI-SC-H!
            THEN
            _UL-SC @ _UTUI-SC-STYLE@ OVER _UTUI-SC-STYLE!
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

: _UTUI-LAYOUT-SPLIT  ( elem -- )
    _USP-ELEM !
    _USP-ELEM @ _UTUI-SIDECAR _USP-SC !
    _USP-SC @ _UTUI-SC-VIS? 0= IF EXIT THEN

    \ Read ratio= (default 50)
    _USP-ELEM @ S" ratio" UIDL-ATTR IF
        STR>NUM 0= IF DROP 50 THEN
    ELSE 2DROP 50 THEN
    _USP-RATIO !

    \ Compute left/right widths
    _USP-SC @ _UTUI-SC-W@
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
        _USP-SC @ _UTUI-SC-ROW@ OVER _UTUI-SC-ROW!
        _USP-SC @ _UTUI-SC-COL@ OVER _UTUI-SC-COL!
        _USP-LW @              OVER _UTUI-SC-W!
        _USP-SC @ _UTUI-SC-H@  OVER _UTUI-SC-H!
        _USP-SC @ _UTUI-SC-STYLE@ OVER _UTUI-SC-STYLE!
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
        _USP-SC @ _UTUI-SC-ROW@                      OVER _UTUI-SC-ROW!
        _USP-SC @ _UTUI-SC-COL@ _USP-LW @ + 1 +     OVER _UTUI-SC-COL!
        _USP-RW @                                     OVER _UTUI-SC-W!
        _USP-SC @ _UTUI-SC-H@                        OVER _UTUI-SC-H!
        _USP-SC @ _UTUI-SC-STYLE@                    OVER _UTUI-SC-STYLE!
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
    _UTUI-RGN @ RGN-H _UDL-DLG-SC @ _UTUI-SC-H@ - 2/ 0 MAX
    _UTUI-RGN @ RGN-ROW +
    _UDL-DLG-SC @ _UTUI-SC-ROW!
    _UTUI-RGN @ RGN-W _UDL-DLG-SC @ _UTUI-SC-W@ - 2/ 0 MAX
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
\  §8 — XT Installation
\ =====================================================================

: _UTUI-INST-R  ( xt name-a name-l -- )
    EL-LOOKUP ?DUP IF ED.RENDER-XT ! ELSE DROP THEN ;
: _UTUI-INST-E  ( xt name-a name-l -- )
    EL-LOOKUP ?DUP IF ED.EVENT-XT  ! ELSE DROP THEN ;
: _UTUI-INST-L  ( xt name-a name-l -- )
    EL-LOOKUP ?DUP IF ED.LAYOUT-XT ! ELSE DROP THEN ;

: UTUI-INSTALL-XTS  ( -- )
    \ --- Render XTs ---
    ['] _UTUI-RENDER-LABEL     S" label"      _UTUI-INST-R
    ['] _UTUI-RENDER-ACTION    S" action"     _UTUI-INST-R
    ['] _UTUI-RENDER-INPUT     S" input"      _UTUI-INST-R
    ['] _UTUI-RENDER-SEP       S" separator"  _UTUI-INST-R
    ['] _UTUI-RENDER-REGION    S" region"     _UTUI-INST-R
    ['] _UTUI-RENDER-REGION    S" group"      _UTUI-INST-R
    ['] _UTUI-RENDER-MBAR      S" menubar"    _UTUI-INST-R
    ['] _UTUI-RENDER-STATUS    S" status"     _UTUI-INST-R
    ['] _UTUI-RENDER-TOOLBAR   S" toolbar"    _UTUI-INST-R
    ['] _UTUI-RENDER-DLG       S" dialog"     _UTUI-INST-R
    ['] _UTUI-RENDER-SPLIT     S" split"      _UTUI-INST-R
    ['] _UTUI-RENDER-TABS      S" tabs"       _UTUI-INST-R
    ['] _UTUI-RENDER-PROGRESS  S" progress"   _UTUI-INST-R
    ['] _UTUI-RENDER-TOGGLE    S" toggle"     _UTUI-INST-R
    ['] _UTUI-RENDER-INDICATOR S" indicator"  _UTUI-INST-R
    ['] _UTUI-RENDER-LIST      S" collection" _UTUI-INST-R
    ['] _UTUI-RENDER-LIST      S" list"       _UTUI-INST-R
    ['] _UTUI-RENDER-TREE      S" tree"       _UTUI-INST-R
    ['] _UTUI-RENDER-TEXTAREA  S" textarea"   _UTUI-INST-R
    ['] _UTUI-RENDER-SCROLL    S" scroll"     _UTUI-INST-R
    ['] _UTUI-RENDER-CANVAS    S" canvas"     _UTUI-INST-R
    ['] _UTUI-RENDER-NOP       S" template"   _UTUI-INST-R
    ['] _UTUI-RENDER-NOP       S" empty"      _UTUI-INST-R
    ['] _UTUI-RENDER-NOP       S" rep"        _UTUI-INST-R
    ['] _UTUI-RENDER-NOP       S" option"     _UTUI-INST-R
    ['] _UTUI-RENDER-NOP       S" meta"       _UTUI-INST-R
    ['] _UTUI-RENDER-NOP       S" uidl"       _UTUI-INST-R

    \ --- Event XTs ---
    ['] _UTUI-H-ACTION         S" action"     _UTUI-INST-E
    ['] _UTUI-H-INPUT          S" input"      _UTUI-INST-E
    ['] _UTUI-H-TOGGLE         S" toggle"     _UTUI-INST-E
    ['] _UTUI-H-MENU           S" menu"       _UTUI-INST-E
    ['] _UTUI-H-TEXTAREA       S" textarea"   _UTUI-INST-E
    ['] _UTUI-H-LIST           S" collection" _UTUI-INST-E
    ['] _UTUI-H-TREE           S" tree"       _UTUI-INST-E
    ['] _UTUI-H-TABS           S" tabs"       _UTUI-INST-E
    ['] _UTUI-H-DIALOG         S" dialog"     _UTUI-INST-E
    ['] _UTUI-H-CANVAS         S" canvas"     _UTUI-INST-E

    \ --- Layout XTs ---
    ['] _UTUI-LAYOUT-DISPATCH  S" region"     _UTUI-INST-L
    ['] _UTUI-LAYOUT-DISPATCH  S" group"      _UTUI-INST-L
    ['] _UTUI-LAYOUT-MBAR      S" menubar"    _UTUI-INST-L
    ['] _UTUI-LAYOUT-STATUS    S" status"     _UTUI-INST-L
    ['] _UTUI-LAYOUT-TOOLBAR   S" toolbar"    _UTUI-INST-L
    ['] _UTUI-LAYOUT-DLG       S" dialog"     _UTUI-INST-L
    ['] _UTUI-LAYOUT-SPLIT     S" split"      _UTUI-INST-L
    ['] _UTUI-LAYOUT-TABS      S" tabs"       _UTUI-INST-L
    ['] _UTUI-LAYOUT-SCROLL    S" scroll"     _UTUI-INST-L
    ['] _UTUI-LAYOUT-DISPATCH  S" uidl"       _UTUI-INST-L
;

UTUI-INSTALL-XTS

\ =====================================================================
\  §9 — Focus Management
\ =====================================================================

: UTUI-FOCUS  ( -- elem | 0 )  _UTUI-FOCUS-P @ ;

: UTUI-FOCUS!  ( elem -- )
    \ Clear old focus
    _UTUI-FOCUS-P @ ?DUP IF
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-FOC INVERT AND SWAP _UTUI-SC-FLAGS!
        UIDL-DIRTY!
    THEN
    \ Set new
    DUP _UTUI-FOCUS-P !
    ?DUP IF
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-FOC OR SWAP _UTUI-SC-FLAGS!
        UIDL-DIRTY!
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
        ELSE DROP 0 THEN
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
                    ELSE 0 TRUE THEN   \ no parent → done, push sentinel
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
                    ELSE 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ =====================================================================
\  §13 — Paint (Dirty-Rect Repaint)
\ =====================================================================

VARIABLE _UTUI-PAINT-DLG

: _UTUI-PAINT-ELEM  ( elem -- )
    DUP UIDL-DIRTY? 0= IF DROP EXIT THEN
    DUP _UTUI-SIDECAR _UTUI-SC-VIS? 0= IF
        UIDL-CLEAN! EXIT
    THEN
    DUP UIDL-TYPE UIDL-T-DIALOG = IF
        _UTUI-PAINT-DLG !
        EXIT
    THEN
    DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
        ED.RENDER-XT @ DUP ['] NOOP <> IF
            OVER SWAP EXECUTE
        ELSE DROP THEN
    THEN
    UIDL-CLEAN! ;

: UTUI-PAINT  ( -- )
    _UTUI-DOC-LOADED @ 0= IF EXIT THEN
    0 _UTUI-PAINT-DLG !
    UIDL-ROOT ?DUP 0= IF EXIT THEN
    BEGIN
        DUP _UTUI-PAINT-ELEM
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF
                        FALSE
                    ELSE 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP
                \ Deferred dialog render
                _UTUI-PAINT-DLG @ ?DUP IF
                    DUP UIDL-TYPE EL-DEF-BY-TYPE ?DUP IF
                        ED.RENDER-XT @ DUP ['] NOOP <> IF
                            OVER SWAP EXECUTE
                        ELSE DROP THEN
                    THEN
                    UIDL-CLEAN!
                THEN
                EXIT
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
                EXECUTE EXIT           \ xt( elem ev -- handled? )
            ELSE DROP THEN
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
\  §16 — Dialog Show / Hide
\ =====================================================================

: UTUI-SHOW-DIALOG  ( id-a id-l -- )
    UIDL-BY-ID ?DUP IF
        DUP _UTUI-SIDECAR
        DUP _UTUI-SC-FLAGS@ _UTUI-SCF-VIS OR SWAP _UTUI-SC-FLAGS!
        UIDL-DIRTY!
    THEN ;

VARIABLE _UDH-SC   \ temp for dialog hide

: UTUI-HIDE-DIALOG  ( id-a id-l -- )
    UIDL-BY-ID ?DUP IF
        DUP _UTUI-SIDECAR _UDH-SC !
        _UDH-SC @ _UTUI-SC-FLAGS@ _UTUI-SCF-VIS INVERT AND
        _UDH-SC @ _UTUI-SC-FLAGS!
        \ Clear dialog area
        _UDH-SC @ _UTUI-SC-ROW@
        _UDH-SC @ _UTUI-SC-COL@
        _UDH-SC @ _UTUI-SC-H@
        _UDH-SC @ _UTUI-SC-W@
        DRW-CLEAR-RECT
        \ Re-dirty underlying elements
        UIDL-ROOT ?DUP IF UIDL-DIRTY! THEN
    THEN ;

\ =====================================================================
\  §16a — Widget Materialization
\ =====================================================================
\
\  Walk the UIDL tree after layout; for elements that need widget
\  state (tree, tabs), allocate a widget struct or mini state block
\  and store the pointer in the sidecar's wptr cell (+48).

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
        ELSE
            UIDL-T-TABS = IF
                8 ALLOCATE 0<> ABORT" tabs-state"
                DUP 0 SWAP !           ( elem state )
                OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
            THEN
        THEN
        \ DFS advance
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF FALSE
                    ELSE 0 TRUE THEN
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
            OVER UIDL-TYPE UIDL-T-TREE = IF
                TREE-FREE
            ELSE
                FREE DROP              \ tabs state, etc.
            THEN
            0 OVER _UTUI-SIDECAR _UTUI-SC-WPTR!
        THEN
        \ DFS advance
        DUP UIDL-FIRST-CHILD ?DUP IF NIP
        ELSE
            BEGIN
                DUP UIDL-NEXT-SIB ?DUP IF NIP TRUE
                ELSE
                    UIDL-PARENT DUP IF FALSE
                    ELSE 0 TRUE THEN
                THEN
            UNTIL
            DUP 0= IF DROP EXIT THEN
        THEN
    AGAIN ;

\ =====================================================================
\  §17 — UTUI-LOAD
\ =====================================================================

: UTUI-BY-ID  ( id-a id-l -- elem | 0 )  UIDL-BY-ID ;

: UTUI-BIND-STATE  ( st -- )
    DUP _UTUI-STATE !
    ST-USE ;

: UTUI-LOAD  ( xml-a xml-u rgn -- flag )
    _UTUI-RGN !

    UIDL-PARSE                         ( flag )
    DUP 0= IF EXIT THEN

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
' UTUI-DO!            CONSTANT _utui-do-s-xt
' UTUI-SHOW-DIALOG    CONSTANT _utui-show-dialog-xt
' UTUI-HIDE-DIALOG    CONSTANT _utui-hide-dialog-xt
' UTUI-HIT-TEST       CONSTANT _utui-hit-test-xt
' UTUI-DETACH         CONSTANT _utui-detach-xt
' UTUI-INSTALL-XTS    CONSTANT _utui-install-xts-xt

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
: UTUI-DO!            _utui-do-s-xt           _utui-guard WITH-GUARD ;
: UTUI-SHOW-DIALOG    _utui-show-dialog-xt    _utui-guard WITH-GUARD ;
: UTUI-HIDE-DIALOG    _utui-hide-dialog-xt    _utui-guard WITH-GUARD ;
: UTUI-HIT-TEST       _utui-hit-test-xt       _utui-guard WITH-GUARD ;
: UTUI-DETACH         _utui-detach-xt         _utui-guard WITH-GUARD ;
: UTUI-INSTALL-XTS    _utui-install-xts-xt    _utui-guard WITH-GUARD ;
[THEN] [THEN]
