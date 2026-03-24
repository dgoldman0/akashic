\ =====================================================================
\  akashic/tui/game/game-view.f — Game View Widget
\ =====================================================================
\
\  A widget that hosts a fixed-timestep game loop inside the TUI
\  widget tree.  It bridges the app-shell tick/paint lifecycle with
\  game-oriented callbacks: on-update, on-draw, on-resize.
\
\  The widget renders game content within its region and participates
\  in focus, layout, and dirty tracking like any other TUI widget.
\  When focused, it captures key events and routes them through the
\  game input callback.  When unfocused, updates pause automatically.
\
\  Descriptor layout (header + 10 cells = 120 bytes):
\    +0..+32  widget header (type=WDG-T-GAME-VIEW)
\    +40      update-xt     ( dt -- )  fixed-step update callback
\    +48      draw-xt       ( rgn -- ) draw callback
\    +56      input-xt      ( ev -- )  key/mouse event callback
\    +64      resize-xt     ( w h -- ) resize callback
\    +72      fps           Target FPS (default 30)
\    +80      frame-ms      Milliseconds per frame (1000/fps)
\    +88      accum         Frame time accumulator (ms)
\    +96      last-ms       MS@ of last tick
\    +104     frame-num     Frame counter
\    +112     gv-flags      GV-F-* flags
\
\  Public API:
\    GV-NEW          ( rgn -- widget )
\    GV-FREE         ( widget -- )
\    GV-FPS!         ( widget fps -- )
\    GV-ON-UPDATE    ( widget xt -- )      xt: ( dt -- )
\    GV-ON-DRAW      ( widget xt -- )      xt: ( rgn -- )
\    GV-ON-INPUT     ( widget xt -- )      xt: ( ev -- )
\    GV-ON-RESIZE    ( widget xt -- )      xt: ( w h -- )
\    GV-TICK         ( widget -- )         Call from TICK-XT
\    GV-FRAME#       ( widget -- n )
\    GV-PAUSE        ( widget -- )
\    GV-RESUME       ( widget -- )
\    GV-PAUSED?      ( widget -- flag )
\
\  Prefix: GV- (public), _GV- (internal)
\  Provider: akashic-tui-game-view
\  Dependencies: widget.f, region.f, keys.f

PROVIDED akashic-tui-game-view

REQUIRE ../widget.f
REQUIRE ../region.f
REQUIRE ../keys.f

\ =====================================================================
\  §1 — Descriptor Offsets
\ =====================================================================

40  CONSTANT _GV-O-UPDATE-XT
48  CONSTANT _GV-O-DRAW-XT
56  CONSTANT _GV-O-INPUT-XT
64  CONSTANT _GV-O-RESIZE-XT
72  CONSTANT _GV-O-FPS
80  CONSTANT _GV-O-FRAME-MS
88  CONSTANT _GV-O-ACCUM
96  CONSTANT _GV-O-LAST-MS
104 CONSTANT _GV-O-FRAME-NUM
112 CONSTANT _GV-O-GV-FLAGS
120 CONSTANT _GV-DESC-SZ

\ Widget type — next after WDG-T-EXPLORER(16)
17 CONSTANT WDG-T-GAME-VIEW

\ Internal flags
1 CONSTANT GV-F-PAUSED       \ update paused
2 CONSTANT GV-F-INITED       \ timing initialised

\ =====================================================================
\  §2 — Internal: Draw Callback
\ =====================================================================

: _GV-DRAW  ( widget -- )
    DUP _GV-O-DRAW-XT + @ ?DUP IF
        OVER _WDG-O-REGION + @ RGN-USE
        OVER _WDG-O-REGION + @
        SWAP EXECUTE
    ELSE DROP THEN ;

\ =====================================================================
\  §3 — Internal: Event Handler
\ =====================================================================

: _GV-HANDLE  ( ev widget -- consumed? )
    DUP _GV-O-INPUT-XT + @ ?DUP IF
        >R SWAP R> EXECUTE   \ call input-xt with event
        DROP -1              \ consumed
    ELSE
        2DROP 0              \ not consumed
    THEN ;

\ =====================================================================
\  §4 — Constructor / Destructor
\ =====================================================================

: GV-NEW  ( rgn -- widget )
    _GV-DESC-SZ ALLOCATE
    0<> ABORT" GV-NEW: alloc"
    \ Fill widget header
    WDG-T-GAME-VIEW OVER _WDG-O-TYPE      + !
    SWAP              OVER _WDG-O-REGION    + !
    ['] _GV-DRAW      OVER _WDG-O-DRAW-XT  + !
    ['] _GV-HANDLE    OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                      OVER _WDG-O-FLAGS     + !
    \ Init game-view fields
    0 OVER _GV-O-UPDATE-XT + !
    0 OVER _GV-O-DRAW-XT   + !
    0 OVER _GV-O-INPUT-XT  + !
    0 OVER _GV-O-RESIZE-XT + !
    30 OVER _GV-O-FPS      + !
    33 OVER _GV-O-FRAME-MS + !  \ 1000/30 ≈ 33
    0 OVER _GV-O-ACCUM     + !
    0 OVER _GV-O-LAST-MS   + !
    0 OVER _GV-O-FRAME-NUM + !
    0 OVER _GV-O-GV-FLAGS  + ! ;

: GV-FREE  ( widget -- )
    FREE DROP ;

\ =====================================================================
\  §5 — Configuration
\ =====================================================================

: GV-FPS!  ( widget fps -- )
    1 MAX                              \ clamp to >= 1
    2DUP SWAP _GV-O-FPS + !           \ store fps
    1000 SWAP / 1 MAX
    SWAP _GV-O-FRAME-MS + ! ;

: GV-ON-UPDATE  ( widget xt -- )  SWAP _GV-O-UPDATE-XT + ! ;
: GV-ON-DRAW    ( widget xt -- )  SWAP _GV-O-DRAW-XT   + ! ;
: GV-ON-INPUT   ( widget xt -- )  SWAP _GV-O-INPUT-XT  + ! ;
: GV-ON-RESIZE  ( widget xt -- )  SWAP _GV-O-RESIZE-XT + ! ;

\ =====================================================================
\  §6 — Pause / Resume
\ =====================================================================

: GV-PAUSE  ( widget -- )
    DUP _GV-O-GV-FLAGS + @
    GV-F-PAUSED OR
    SWAP _GV-O-GV-FLAGS + ! ;

: GV-RESUME  ( widget -- )
    DUP _GV-O-GV-FLAGS + @
    GV-F-PAUSED INVERT AND
    SWAP _GV-O-GV-FLAGS + !  ;

: GV-PAUSED?  ( widget -- flag )
    _GV-O-GV-FLAGS + @ GV-F-PAUSED AND 0<> ;

\ =====================================================================
\  §7 — Tick (called from APP.TICK-XT)
\ =====================================================================
\
\  Computes elapsed time, runs fixed-timestep updates via the
\  accumulator pattern, increments frame counter, and marks dirty.

: GV-TICK  ( widget -- )
    \ Skip if paused or no update callback
    DUP GV-PAUSED? IF DROP EXIT THEN
    DUP _GV-O-UPDATE-XT + @ 0= IF DROP EXIT THEN
    \ Initialise timing on first tick
    DUP _GV-O-GV-FLAGS + @ GV-F-INITED AND 0= IF
        MS@ OVER _GV-O-LAST-MS + !
        DUP _GV-O-GV-FLAGS + @
        GV-F-INITED OR
        OVER _GV-O-GV-FLAGS + !
    THEN
    \ Compute elapsed ms
    MS@ DUP                              ( w now now )
    2 PICK _GV-O-LAST-MS + @ -          ( w now elapsed )
    ROT DUP >R                           \ ( now elapsed w  R: w )
    _GV-O-LAST-MS + ROT SWAP !          ( elapsed )  \ store now
    \ Cap to 200ms to prevent spiral of death
    DUP 200 > IF DROP 200 THEN
    \ Add to accumulator
    R@ _GV-O-ACCUM + @ +
    R@ _GV-O-ACCUM + !
    \ Run fixed-step updates
    BEGIN
        R@ _GV-O-ACCUM + @
        R@ _GV-O-FRAME-MS + @ >=
    WHILE
        R@ _GV-O-FRAME-MS + @
        R@ _GV-O-UPDATE-XT + @ EXECUTE
        R@ _GV-O-ACCUM + @
        R@ _GV-O-FRAME-MS + @ -
        R@ _GV-O-ACCUM + !
        R@ _GV-O-FRAME-NUM + @ 1+
        R@ _GV-O-FRAME-NUM + !
    REPEAT
    \ Mark widget dirty for repaint
    R> WDG-DIRTY ;

\ =====================================================================
\  §8 — Queries
\ =====================================================================

: GV-FRAME#  ( widget -- n )
    _GV-O-FRAME-NUM + @ ;

\ =====================================================================
\  §9 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _gv-guard

' GV-NEW     CONSTANT _gv-new-xt
' GV-FREE    CONSTANT _gv-free-xt
' GV-TICK    CONSTANT _gv-tick-xt

: GV-NEW     _gv-new-xt   _gv-guard WITH-GUARD ;
: GV-FREE    _gv-free-xt  _gv-guard WITH-GUARD ;
: GV-TICK    _gv-tick-xt  _gv-guard WITH-GUARD ;
[THEN] [THEN]
