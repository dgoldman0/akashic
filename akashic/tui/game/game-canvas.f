\ =====================================================================
\  akashic/tui/game/game-canvas.f — Canvas Game View Widget
\ =====================================================================
\
\  Combines the Braille canvas (sub-cell pixel resolution) with the
\  Game-View lifecycle (fixed-timestep update, pause-on-blur).
\
\  The widget owns a canvas (CVS-*) and a game-view (GV-*).  The
\  draw callback renders the canvas into the widget's region.  The
\  user's on-draw callback receives the canvas address for direct
\  Braille drawing via CVS-SET, CVS-LINE, etc.
\
\  Descriptor layout (header + 5 cells = 80 bytes):
\    +0..+32   widget header (type=WDG-T-GAME-CANVAS)
\    +40       gv          Game-View widget (owns update/input lifecycle)
\    +48       cvs         Canvas widget (owns dot/colour buffers)
\    +56       user-draw   ( cvs -- ) user draw callback
\    +64       auto-clear  Flag: clear canvas before each draw (default TRUE)
\    +72       user-input  ( ev -- ) user input callback
\
\  Public API:
\    GCVS-NEW        ( rgn fps -- widget )
\    GCVS-FREE       ( widget -- )
\    GCVS-ON-UPDATE  ( widget xt -- )     xt: ( dt -- )
\    GCVS-ON-DRAW    ( widget xt -- )     xt: ( cvs -- )
\    GCVS-ON-INPUT   ( widget xt -- )     xt: ( ev -- )
\    GCVS-TICK       ( widget -- )        Call from TICK-XT
\    GCVS-CANVAS     ( widget -- cvs )    Get canvas for CVS-* calls
\    GCVS-DOT-W      ( widget -- w )      Dot-space width
\    GCVS-DOT-H      ( widget -- h )      Dot-space height
\    GCVS-AUTO-CLEAR! ( widget flag -- )  Toggle auto-clear
\    GCVS-PAUSE      ( widget -- )
\    GCVS-RESUME     ( widget -- )
\
\  Prefix: GCVS- (public), _GCVS- (internal)
\  Provider: akashic-tui-game-canvas
\  Dependencies: game-view.f, canvas.f

PROVIDED akashic-tui-game-canvas

REQUIRE game-view.f
REQUIRE ../widgets/canvas.f

\ =====================================================================
\  §1 — Descriptor Offsets
\ =====================================================================

40 CONSTANT _GCVS-O-GV
48 CONSTANT _GCVS-O-CVS
56 CONSTANT _GCVS-O-USER-DRAW
64 CONSTANT _GCVS-O-AUTO-CLR
72 CONSTANT _GCVS-O-USER-INPUT
80 CONSTANT _GCVS-DESC-SZ

18 CONSTANT WDG-T-GAME-CANVAS

\ =====================================================================
\  §2 — Internal: Draw Callback
\ =====================================================================
\
\  Called by WDG-DRAW.  Optionally clears the canvas, calls the
\  user's draw-xt with the canvas, then delegates to the canvas
\  widget's own draw (which renders Braille glyphs to screen).

VARIABLE _GCVS-CUR   \ current widget being drawn

: _GCVS-DRAW  ( widget -- )
    DUP _GCVS-CUR !
    DUP _GCVS-O-CVS + @                 ( w cvs )
    \ Auto-clear if enabled
    OVER _GCVS-O-AUTO-CLR + @ IF
        DUP CVS-CLEAR
    THEN
    \ Call user draw with canvas
    OVER _GCVS-O-USER-DRAW + @ ?DUP IF
        OVER SWAP EXECUTE                ( w cvs )
    THEN
    \ Render canvas to screen via its draw-xt
    DUP _WDG-O-REGION + @ RGN-USE
    _WDG-O-DRAW-XT + @ ?DUP IF
        _GCVS-CUR @ _GCVS-O-CVS + @ SWAP EXECUTE
    THEN
    DROP ;

\ =====================================================================
\  §3 — Internal: Event Handler
\ =====================================================================

: _GCVS-HANDLE  ( ev widget -- consumed? )
    DUP _GCVS-O-USER-INPUT + @ ?DUP IF
        >R SWAP R> EXECUTE
        DROP -1
    ELSE
        2DROP 0
    THEN ;

\ =====================================================================
\  §4 — Internal: GV draw bridge
\ =====================================================================
\
\  The game-view's on-draw receives a region, but for a game-canvas
\  we need to route through _GCVS-DRAW instead.  We use a variable
\  to pass the outer widget reference.

VARIABLE _GCVS-OUTER

: _GCVS-GV-DRAW  ( rgn -- )
    DROP _GCVS-OUTER @ _GCVS-DRAW ;

\ =====================================================================
\  §5 — Constructor / Destructor
\ =====================================================================

: GCVS-NEW  ( rgn fps -- widget )
    >R                                   \ ( rgn  R: fps )
    _GCVS-DESC-SZ ALLOCATE
    0<> ABORT" GCVS-NEW: alloc"          ( rgn desc )
    \ Fill widget header
    WDG-T-GAME-CANVAS OVER _WDG-O-TYPE      + !
    SWAP OVER _WDG-O-REGION  + !         ( desc )  rgn stored
    ['] _GCVS-DRAW  OVER _WDG-O-DRAW-XT   + !
    ['] _GCVS-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                    OVER _WDG-O-FLAGS     + !
    \ Create internal game-view
    DUP _WDG-O-REGION + @               ( desc rgn )
    GV-NEW                               ( desc gv )
    OVER _GCVS-O-GV + !                 ( desc )
    \ Set FPS on game-view
    DUP _GCVS-O-GV + @ R> GV-FPS!       ( desc )
    \ Create internal canvas
    DUP _WDG-O-REGION + @               ( desc rgn )
    CVS-NEW                              ( desc cvs )
    OVER _GCVS-O-CVS + !                ( desc )
    \ Init fields
    0 OVER _GCVS-O-USER-DRAW  + !
    -1 OVER _GCVS-O-AUTO-CLR  + !       \ auto-clear ON by default
    0 OVER _GCVS-O-USER-INPUT + ! ;

: GCVS-FREE  ( widget -- )
    DUP _GCVS-O-CVS + @ CVS-FREE
    DUP _GCVS-O-GV  + @ GV-FREE
    FREE ;

\ =====================================================================
\  §6 — Configuration
\ =====================================================================

: GCVS-ON-UPDATE  ( widget xt -- )
    SWAP _GCVS-O-GV + @ SWAP GV-ON-UPDATE ;

: GCVS-ON-DRAW  ( widget xt -- )
    SWAP _GCVS-O-USER-DRAW + ! ;

: GCVS-ON-INPUT  ( widget xt -- )
    SWAP _GCVS-O-USER-INPUT + ! ;

: GCVS-AUTO-CLEAR!  ( widget flag -- )
    SWAP _GCVS-O-AUTO-CLR + ! ;

\ =====================================================================
\  §7 — Tick / Pause / Resume
\ =====================================================================

: GCVS-TICK  ( widget -- )
    DUP _GCVS-CUR !
    DUP _GCVS-O-GV + @ GV-TICK
    WDG-DIRTY ;

: GCVS-PAUSE   ( widget -- )  _GCVS-O-GV + @ GV-PAUSE ;
: GCVS-RESUME  ( widget -- )  _GCVS-O-GV + @ GV-RESUME ;

\ =====================================================================
\  §8 — Queries
\ =====================================================================

: GCVS-CANVAS  ( widget -- cvs )
    _GCVS-O-CVS + @ ;

: GCVS-DOT-W  ( widget -- w )
    _GCVS-O-CVS + @
    48 + @ ;  \ _CVS-O-DW = 48

: GCVS-DOT-H  ( widget -- h )
    _GCVS-O-CVS + @
    56 + @ ;  \ _CVS-O-DH = 56

\ =====================================================================
\  §9 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _gcvs-guard

' GCVS-NEW   CONSTANT _gcvs-new-xt
' GCVS-FREE  CONSTANT _gcvs-free-xt
' GCVS-TICK  CONSTANT _gcvs-tick-xt

: GCVS-NEW   _gcvs-new-xt   _gcvs-guard WITH-GUARD ;
: GCVS-FREE  _gcvs-free-xt  _gcvs-guard WITH-GUARD ;
: GCVS-TICK  _gcvs-tick-xt  _gcvs-guard WITH-GUARD ;
[THEN] [THEN]
