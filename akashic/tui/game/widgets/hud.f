\ =====================================================================
\  akashic/tui/game/widgets/hud.f — HUD Overlay Widget
\ =====================================================================
\
\  A transparent overlay widget placed atop the Game-View.
\  Renders status indicators: bars, text labels, and icons.
\  Non-focusable — does not consume keyboard events.
\
\  Slot types:
\    HUD-SLOT-BAR   — progress bar (health, mana, etc.)
\    HUD-SLOT-TEXT  — dynamic text label
\    HUD-SLOT-ICON  — single Unicode glyph with colour
\
\  Slot descriptor (56 bytes, 7 cells):
\    +0   type       0=unused, 1=bar, 2=text, 3=icon
\    +8   label-a    Label string address
\    +16  label-u    Label string length
\    +24  val        Bar: current value / Icon: codepoint
\    +32  max        Bar: maximum value / Icon: foreground colour
\    +40  fg         Bar fill colour
\    +48  bg         Bar empty colour
\
\  Public API:
\    HUD-NEW         ( rgn max-slots -- widget )
\    HUD-FREE        ( widget -- )
\    HUD-ADD-BAR     ( hud label-a label-u max fg bg -- slot-id )
\    HUD-SET-BAR     ( hud slot-id current -- )
\    HUD-ADD-TEXT    ( hud label-a label-u -- slot-id )
\    HUD-SET-TEXT    ( hud slot-id addr len -- )
\    HUD-ADD-ICON    ( hud cp fg -- slot-id )
\    HUD-SET-ICON    ( hud slot-id cp -- )
\    HUD-CLEAR       ( hud -- )
\
\  Prefix: HUD- (public), _HUD- (internal)
\  Provider: akashic-tui-game-widgets-hud
\  Dependencies: widget.f, draw.f

PROVIDED ak-tui-gw-hud

REQUIRE ../../widget.f
REQUIRE ../../draw.f

\ =====================================================================
\  §1 — Constants
\ =====================================================================

19 CONSTANT WDG-T-HUD

\ Slot types
0 CONSTANT HUD-SLOT-EMPTY
1 CONSTANT HUD-SLOT-BAR
2 CONSTANT HUD-SLOT-TEXT
3 CONSTANT HUD-SLOT-ICON

\ Slot layout (56 bytes, 7 cells)
 0 CONSTANT _HUD-SL-TYPE
 8 CONSTANT _HUD-SL-LABELA
16 CONSTANT _HUD-SL-LABELU
24 CONSTANT _HUD-SL-VAL
32 CONSTANT _HUD-SL-MAX
40 CONSTANT _HUD-SL-FG
48 CONSTANT _HUD-SL-BG
56 CONSTANT _HUD-SL-SZ

\ Widget descriptor: header (40) + max(+40) + count(+48) + slots(+56)
40 CONSTANT _HUD-O-MAX
48 CONSTANT _HUD-O-COUNT
56 CONSTANT _HUD-O-SLOTS
64 CONSTANT _HUD-HDR-SZ

\ =====================================================================
\  §2 — Slot Access Helpers
\ =====================================================================

\ Get slot base address
: _HUD-SLOT  ( widget slot-id -- addr )
    _HUD-SL-SZ * SWAP _HUD-O-SLOTS + + ;

\ =====================================================================
\  §3 — Slot Management
\ =====================================================================

VARIABLE _HUD-A-W   \ widget being modified

\ Find first empty slot, return slot-id or -1
: _HUD-FIND-EMPTY  ( widget -- slot-id )
    _HUD-A-W !
    _HUD-A-W @ _HUD-O-MAX + @ 0 ?DO
        _HUD-A-W @ I _HUD-SLOT _HUD-SL-TYPE + @ HUD-SLOT-EMPTY = IF
            I UNLOOP EXIT
        THEN
    LOOP
    -1 ;

VARIABLE _HUD-AB-LA   VARIABLE _HUD-AB-LU
VARIABLE _HUD-AB-MAX  VARIABLE _HUD-AB-FG  VARIABLE _HUD-AB-BG

: HUD-ADD-BAR  ( hud label-a label-u max fg bg -- slot-id )
    _HUD-AB-BG !  _HUD-AB-FG !  _HUD-AB-MAX !
    _HUD-AB-LU !  _HUD-AB-LA !
    DUP _HUD-FIND-EMPTY DUP -1 = IF NIP EXIT THEN
    >R
    DUP R@ _HUD-SLOT >R
    HUD-SLOT-BAR R@ _HUD-SL-TYPE  + !
    _HUD-AB-LA @  R@ _HUD-SL-LABELA + !
    _HUD-AB-LU @  R@ _HUD-SL-LABELU + !
    0             R@ _HUD-SL-VAL    + !
    _HUD-AB-MAX @ R@ _HUD-SL-MAX    + !
    _HUD-AB-FG @  R@ _HUD-SL-FG     + !
    _HUD-AB-BG @  R@ _HUD-SL-BG     + !
    R> DROP
    DUP _HUD-O-COUNT + DUP @ 1+ SWAP !
    WDG-DIRTY
    R> ;

VARIABLE _HUD-SB-CUR

: HUD-SET-BAR  ( hud slot-id current -- )
    _HUD-SB-CUR !
    OVER SWAP _HUD-SLOT _HUD-SL-VAL + _HUD-SB-CUR @ SWAP !
    WDG-DIRTY ;

VARIABLE _HUD-AT-LA  VARIABLE _HUD-AT-LU

: HUD-ADD-TEXT  ( hud label-a label-u -- slot-id )
    _HUD-AT-LU !  _HUD-AT-LA !
    DUP _HUD-FIND-EMPTY DUP -1 = IF NIP EXIT THEN
    >R
    DUP R@ _HUD-SLOT >R
    HUD-SLOT-TEXT R@ _HUD-SL-TYPE  + !
    _HUD-AT-LA @ R@ _HUD-SL-LABELA + !
    _HUD-AT-LU @ R@ _HUD-SL-LABELU + !
    0            R@ _HUD-SL-VAL    + !
    0            R@ _HUD-SL-MAX    + !
    R> DROP
    DUP _HUD-O-COUNT + DUP @ 1+ SWAP !
    WDG-DIRTY
    R> ;

VARIABLE _HUD-ST-A  VARIABLE _HUD-ST-U

: HUD-SET-TEXT  ( hud slot-id addr len -- )
    _HUD-ST-U !  _HUD-ST-A !
    OVER SWAP _HUD-SLOT >R
    _HUD-ST-A @ R@ _HUD-SL-VAL + !
    _HUD-ST-U @ R@ _HUD-SL-MAX + !
    R> DROP
    WDG-DIRTY ;

VARIABLE _HUD-AI-CP  VARIABLE _HUD-AI-FG

: HUD-ADD-ICON  ( hud cp fg -- slot-id )
    _HUD-AI-FG !  _HUD-AI-CP !
    DUP _HUD-FIND-EMPTY DUP -1 = IF NIP EXIT THEN
    >R
    DUP R@ _HUD-SLOT >R
    HUD-SLOT-ICON R@ _HUD-SL-TYPE  + !
    0             R@ _HUD-SL-LABELA + !
    0             R@ _HUD-SL-LABELU + !
    _HUD-AI-CP @  R@ _HUD-SL-VAL    + !
    _HUD-AI-FG @  R@ _HUD-SL-FG     + !
    R> DROP
    DUP _HUD-O-COUNT + DUP @ 1+ SWAP !
    WDG-DIRTY
    R> ;

VARIABLE _HUD-SI-CP

: HUD-SET-ICON  ( hud slot-id cp -- )
    _HUD-SI-CP !
    OVER SWAP _HUD-SLOT _HUD-SL-VAL + _HUD-SI-CP @ SWAP !
    WDG-DIRTY ;

: HUD-CLEAR  ( hud -- )
    DUP _HUD-O-SLOTS +
    OVER _HUD-O-MAX + @ _HUD-SL-SZ * 0 FILL
    DUP _HUD-O-COUNT + 0 SWAP !
    WDG-DIRTY ;

\ =====================================================================
\  §4 — Drawing
\ =====================================================================

VARIABLE _HUD-D-W      \ widget
VARIABLE _HUD-D-RW     \ region width
VARIABLE _HUD-D-COL    \ current column cursor

\ Draw one bar slot: "Label ████░░░░ "
VARIABLE _HUD-DB-CUR  VARIABLE _HUD-DB-MAX
VARIABLE _HUD-DB-BARW  VARIABLE _HUD-DB-FILLED

: _HUD-DRAW-BAR  ( slot-addr row -- )
    SWAP >R
    \ Label
    DRW-STYLE-SAVE
    7 0 0 DRW-STYLE!
    R@ _HUD-SL-LABELA + @  R@ _HUD-SL-LABELU + @
    2 PICK _HUD-D-COL @ DRW-TEXT
    R@ _HUD-SL-LABELU + @ _HUD-D-COL +!
    [CHAR] : OVER _HUD-D-COL @ DRW-CHAR  1 _HUD-D-COL +!

    \ Compute fill
    R@ _HUD-SL-VAL + @ _HUD-DB-CUR !
    R@ _HUD-SL-MAX + @ _HUD-DB-MAX !
    8 _HUD-DB-BARW !
    _HUD-DB-MAX @ 0> IF
        _HUD-DB-CUR @ 8 * _HUD-DB-MAX @ / _HUD-DB-FILLED !
    ELSE  0 _HUD-DB-FILLED !  THEN
    _HUD-DB-FILLED @ 0 MAX 8 MIN _HUD-DB-FILLED !

    \ Filled portion
    R@ _HUD-SL-FG + @ 0 0 DRW-STYLE!
    0x2588 OVER _HUD-D-COL @ _HUD-DB-FILLED @ DRW-HLINE
    _HUD-DB-FILLED @ _HUD-D-COL +!

    \ Empty portion
    R@ _HUD-SL-BG + @ 0 0 DRW-STYLE!
    0x2591 OVER _HUD-D-COL @  8 _HUD-DB-FILLED @ -  DRW-HLINE
    8 _HUD-DB-FILLED @ - _HUD-D-COL +!

    DRW-STYLE-RESTORE
    BL OVER _HUD-D-COL @ DRW-CHAR  1 _HUD-D-COL +!
    R> DROP DROP ;

\ Draw one text slot: "Label: value "
: _HUD-DRAW-TEXT  ( slot-addr row -- )
    SWAP >R
    DRW-STYLE-SAVE
    7 0 0 DRW-STYLE!
    R@ _HUD-SL-LABELA + @  R@ _HUD-SL-LABELU + @
    2 PICK _HUD-D-COL @ DRW-TEXT
    R@ _HUD-SL-LABELU + @ _HUD-D-COL +!
    [CHAR] : OVER _HUD-D-COL @ DRW-CHAR  1 _HUD-D-COL +!

    \ Dynamic text (stored in val=addr, max=len)
    R@ _HUD-SL-VAL + @ 0<> IF
        R@ _HUD-SL-VAL + @  R@ _HUD-SL-MAX + @
        2 PICK _HUD-D-COL @ DRW-TEXT
        R@ _HUD-SL-MAX + @ _HUD-D-COL +!
    THEN

    DRW-STYLE-RESTORE
    BL OVER _HUD-D-COL @ DRW-CHAR  1 _HUD-D-COL +!
    R> DROP DROP ;

\ Draw one icon slot: coloured glyph + space
: _HUD-DRAW-ICON  ( slot-addr row -- )
    SWAP >R
    DRW-STYLE-SAVE
    R@ _HUD-SL-FG + @ 0 0 DRW-STYLE!
    R@ _HUD-SL-VAL + @  OVER _HUD-D-COL @ DRW-CHAR
    1 _HUD-D-COL +!
    DRW-STYLE-RESTORE
    BL OVER _HUD-D-COL @ DRW-CHAR  1 _HUD-D-COL +!
    R> DROP DROP ;

\ Main draw callback
: _HUD-DRAW  ( widget -- )
    DUP _HUD-D-W !
    DUP WDG-REGION RGN-USE
    DUP WDG-REGION RGN-W _HUD-D-RW !
    0 _HUD-D-COL !

    \ Clear row 0
    32 0 0 _HUD-D-RW @ DRW-HLINE

    \ Iterate slots, draw each on row 0
    DUP _HUD-O-MAX + @ 0 ?DO
        DUP I _HUD-SLOT DUP _HUD-SL-TYPE + @ CASE
            HUD-SLOT-BAR   OF  0 _HUD-DRAW-BAR   ENDOF
            HUD-SLOT-TEXT  OF  0 _HUD-DRAW-TEXT   ENDOF
            HUD-SLOT-ICON  OF  0 _HUD-DRAW-ICON   ENDOF
            \ HUD-SLOT-EMPTY — skip
            DROP
        ENDCASE
        _HUD-D-COL @ _HUD-D-RW @ >= IF LEAVE THEN
    LOOP
    DROP ;

\ =====================================================================
\  §5 — Handle (no-op, non-focusable)
\ =====================================================================

: _HUD-HANDLE  ( event widget -- consumed? )
    2DROP 0 ;

\ =====================================================================
\  §6 — Constructor / Destructor
\ =====================================================================

VARIABLE _HUD-N-RGN   VARIABLE _HUD-N-MAX

: HUD-NEW  ( rgn max-slots -- widget )
    _HUD-N-MAX !  _HUD-N-RGN !

    \ Allocate descriptor + slot array
    _HUD-HDR-SZ _HUD-N-MAX @ _HUD-SL-SZ * + ALLOCATE
    0<> ABORT" HUD-NEW: alloc"

    \ Header
    WDG-T-HUD             OVER _WDG-O-TYPE      + !
    _HUD-N-RGN @          OVER _WDG-O-REGION    + !
    ['] _HUD-DRAW          OVER _WDG-O-DRAW-XT   + !
    ['] _HUD-HANDLE        OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                          OVER _WDG-O-FLAGS     + !

    \ HUD fields
    _HUD-N-MAX @          OVER _HUD-O-MAX       + !
    0                     OVER _HUD-O-COUNT     + !

    \ Zero all slot types (mark empty)
    DUP _HUD-O-SLOTS +  _HUD-N-MAX @ _HUD-SL-SZ *  0 FILL ;

: HUD-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\  §7 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _hud-guard

' HUD-NEW       CONSTANT _hud-new-xt
' HUD-FREE      CONSTANT _hud-free-xt
' HUD-ADD-BAR   CONSTANT _hud-add-bar-xt
' HUD-SET-BAR   CONSTANT _hud-set-bar-xt
' HUD-ADD-TEXT  CONSTANT _hud-add-text-xt
' HUD-SET-TEXT  CONSTANT _hud-set-text-xt
' HUD-ADD-ICON  CONSTANT _hud-add-icon-xt
' HUD-SET-ICON  CONSTANT _hud-set-icon-xt
' HUD-CLEAR     CONSTANT _hud-clear-xt

: HUD-NEW       _hud-new-xt       _hud-guard WITH-GUARD ;
: HUD-FREE      _hud-free-xt      _hud-guard WITH-GUARD ;
: HUD-ADD-BAR   _hud-add-bar-xt   _hud-guard WITH-GUARD ;
: HUD-SET-BAR   _hud-set-bar-xt   _hud-guard WITH-GUARD ;
: HUD-ADD-TEXT  _hud-add-text-xt  _hud-guard WITH-GUARD ;
: HUD-SET-TEXT  _hud-set-text-xt  _hud-guard WITH-GUARD ;
: HUD-ADD-ICON  _hud-add-icon-xt  _hud-guard WITH-GUARD ;
: HUD-SET-ICON  _hud-set-icon-xt  _hud-guard WITH-GUARD ;
: HUD-CLEAR     _hud-clear-xt     _hud-guard WITH-GUARD ;
[THEN] [THEN]
