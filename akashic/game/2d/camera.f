\ =====================================================================
\  akashic/game/2d/camera.f — Camera / Viewport Controller
\ =====================================================================
\
\  Tracks a target position with optional smoothing, screen-shake,
\  and bounds clamping.  The camera position is used by the world
\  renderer and tilemap to determine the visible portion of the world.
\
\  All coordinates are integers (tile units).  Smooth follow uses
\  fixed-point interpolation with 8-bit fraction (256 = 1.0).
\
\  Shake uses a simple decaying random offset.
\
\  Camera Descriptor (96 bytes, 12 cells):
\    +0   world-w     World width (tiles)
\    +8   world-h     World height (tiles)
\    +16  view-w      Viewport width (columns visible)
\    +24  view-h      Viewport height (rows visible)
\    +32  x           Current camera X (top-left, fixed-point ×256)
\    +40  y           Current camera Y (top-left, fixed-point ×256)
\    +48  target-x    Target X (fixed-point ×256)
\    +56  target-y    Target Y (fixed-point ×256)
\    +64  smooth      Smoothing factor (0=instant, 1–255=lerp speed)
\    +72  shake-amp   Current shake amplitude
\    +80  shake-dur   Remaining shake ticks
\    +88  shake-seed  PRNG state for shake offset
\
\  Public API:
\    CAM-NEW      ( world-w world-h view-w view-h -- cam )
\    CAM-FREE     ( cam -- )
\    CAM-FOLLOW   ( cam target-x target-y -- )
\    CAM-SNAP     ( cam x y -- )
\    CAM-SHAKE    ( cam amplitude duration -- )
\    CAM-BOUNDS!  ( cam world-w world-h -- )
\    CAM-VIEW!    ( cam view-w view-h -- )
\    CAM-SMOOTH!  ( cam factor -- )
\    CAM-TICK     ( cam -- )
\    CAM-X        ( cam -- x )     Effective X (with shake)
\    CAM-Y        ( cam -- y )     Effective Y (with shake)
\
\  Prefix: CAM- (public), _CAM- (internal)
\  Provider: akashic-game-2d-camera
\  No dependencies.

PROVIDED akashic-game-2d-camera

\ =====================================================================
\  §1 — Descriptor Offsets
\ =====================================================================

0  CONSTANT _CAM-O-WW
8  CONSTANT _CAM-O-WH
16 CONSTANT _CAM-O-VW
24 CONSTANT _CAM-O-VH
32 CONSTANT _CAM-O-X
40 CONSTANT _CAM-O-Y
48 CONSTANT _CAM-O-TX
56 CONSTANT _CAM-O-TY
64 CONSTANT _CAM-O-SMOOTH
72 CONSTANT _CAM-O-SHAKE-AMP
80 CONSTANT _CAM-O-SHAKE-DUR
88 CONSTANT _CAM-O-SHAKE-SEED
96 CONSTANT _CAM-DESC-SZ

\ =====================================================================
\  §2 — Constructor / Destructor
\ =====================================================================

: CAM-NEW  ( world-w world-h view-w view-h -- cam )
    _CAM-DESC-SZ ALLOCATE
    0<> ABORT" CAM-NEW: alloc"
    DUP _CAM-DESC-SZ 0 FILL             ( ww wh vw vh cam )
    >R
    R@ _CAM-O-VH + !                    \ view-h
    R@ _CAM-O-VW + !                    \ view-w
    R@ _CAM-O-WH + !                    \ world-h
    R@ _CAM-O-WW + !                    \ world-w
    42 R@ _CAM-O-SHAKE-SEED + !         \ arbitrary PRNG seed
    R> ;

: CAM-FREE  ( cam -- )  FREE ;

\ =====================================================================
\  §3 — Configuration
\ =====================================================================

: CAM-SMOOTH!  ( cam factor -- )
    SWAP _CAM-O-SMOOTH + ! ;

: CAM-BOUNDS!  ( cam world-w world-h -- )
    ROT DUP >R _CAM-O-WH + !
    R> _CAM-O-WW + ! ;

: CAM-VIEW!  ( cam view-w view-h -- )
    ROT DUP >R _CAM-O-VH + !
    R> _CAM-O-VW + ! ;

\ =====================================================================
\  §4 — Follow / Snap
\ =====================================================================

\ Internal: center target so that (tx,ty) is at the viewport center.
\ Stores as fixed-point ×256.
: _CAM-CENTER  ( cam tx ty -- )
    SWAP                                 ( cam ty tx )
    2 PICK _CAM-O-VW + @ 2 / -          ( cam ty tx' )
    256 *                                ( cam ty tx-fp )
    2 PICK _CAM-O-TX + !                ( cam ty )
    SWAP _CAM-O-VH + @ 2 / -            ( ty' )
    256 * SWAP _CAM-O-TY + ! ;

\ Wrong — need cam for TY store.  Redo:
: CAM-FOLLOW  ( cam target-x target-y -- )
    >R >R DUP R> R>                      ( cam cam tx ty )
    SWAP                                 ( cam cam ty tx )
    3 PICK _CAM-O-VW + @ 2 / -          ( cam cam ty tx' )
    256 *                                ( cam cam ty tx-fp )
    2 PICK _CAM-O-TX + !                ( cam cam ty )
    SWAP _CAM-O-VH + @ 2 / -            ( cam ty' )
    256 * SWAP _CAM-O-TY + ! ;

: CAM-SNAP  ( cam x y -- )
    >R >R DUP R> R>                      ( cam cam x y )
    SWAP                                 ( cam cam y x )
    3 PICK _CAM-O-VW + @ 2 / -
    256 *
    DUP 3 PICK _CAM-O-TX + !
    2 PICK _CAM-O-X + !                 ( cam cam y )
    SWAP _CAM-O-VH + @ 2 / -
    256 *
    2DUP SWAP _CAM-O-TY + !
    SWAP _CAM-O-Y + ! ;

\ =====================================================================
\  §5 — Shake
\ =====================================================================

: CAM-SHAKE  ( cam amplitude duration -- )
    2 PICK _CAM-O-SHAKE-DUR + !
    SWAP _CAM-O-SHAKE-AMP + ! ;

\ Simple xorshift PRNG for shake offsets.
: _CAM-RAND  ( cam -- n )
    DUP _CAM-O-SHAKE-SEED + @
    DUP 13 LSHIFT XOR
    DUP 17 RSHIFT XOR
    DUP 5 LSHIFT XOR
    DUP ROT _CAM-O-SHAKE-SEED + ! ;

\ =====================================================================
\  §6 — Tick
\ =====================================================================
\
\  Lerp position toward target.  Decay shake.  Clamp to world bounds.

: _CAM-CLAMP  ( cam -- )
    \ Clamp X: 0 <= x/256 <= world-w - view-w
    DUP _CAM-O-X + @                    ( cam x-fp )
    DUP 0< IF DROP 0 THEN               ( cam x-fp' )
    OVER _CAM-O-WW + @
    2 PICK _CAM-O-VW + @ -              ( cam x-fp max )
    256 *                                ( cam x-fp max-fp )
    2DUP > IF NIP ELSE DROP THEN         ( cam clamped )
    OVER _CAM-O-X + !
    \ Clamp Y: 0 <= y/256 <= world-h - view-h
    DUP _CAM-O-Y + @
    DUP 0< IF DROP 0 THEN
    OVER _CAM-O-WH + @
    2 PICK _CAM-O-VH + @ -
    256 *
    2DUP > IF NIP ELSE DROP THEN
    SWAP _CAM-O-Y + ! ;

: CAM-TICK  ( cam -- )
    DUP _CAM-O-SMOOTH + @ 0= IF
        \ Instant follow: snap to target
        DUP _CAM-O-TX + @ OVER _CAM-O-X + !
        DUP _CAM-O-TY + @ OVER _CAM-O-Y + !
    ELSE
        \ Lerp: x += (target - x) * smooth / 256
        DUP _CAM-O-TX + @ OVER _CAM-O-X + @ -
        OVER _CAM-O-SMOOTH + @ * 256 /
        DUP 0= IF                       \ ensure at least ±1 pixel movement
            DROP
            OVER _CAM-O-TX + @ OVER _CAM-O-X + @ -
            DUP 0> IF DROP 1 ELSE
            DUP 0< IF DROP -1 ELSE DROP 0 THEN THEN
        THEN
        OVER _CAM-O-X + @ + OVER _CAM-O-X + !
        \ Same for Y
        DUP _CAM-O-TY + @ OVER _CAM-O-Y + @ -
        OVER _CAM-O-SMOOTH + @ * 256 /
        DUP 0= IF
            DROP
            OVER _CAM-O-TY + @ OVER _CAM-O-Y + @ -
            DUP 0> IF DROP 1 ELSE
            DUP 0< IF DROP -1 ELSE DROP 0 THEN THEN
        THEN
        OVER _CAM-O-Y + @ + OVER _CAM-O-Y + !
    THEN
    \ Decay shake
    DUP _CAM-O-SHAKE-DUR + @ 0> IF
        DUP _CAM-O-SHAKE-DUR + @
        1- OVER _CAM-O-SHAKE-DUR + !
    THEN
    \ Clamp to world bounds
    _CAM-CLAMP ;

\ =====================================================================
\  §7 — Queries
\ =====================================================================

\ Return effective camera position (integer tiles) including shake offset.
: CAM-X  ( cam -- x )
    DUP _CAM-O-X + @ 256 /              ( cam x )
    OVER _CAM-O-SHAKE-DUR + @ 0> IF
        OVER _CAM-RAND
        OVER _CAM-O-SHAKE-AMP + @ MOD
        OVER _CAM-O-SHAKE-AMP + @ 2 / -
        +                                ( cam x' )
    THEN
    NIP ;

: CAM-Y  ( cam -- y )
    DUP _CAM-O-Y + @ 256 /
    OVER _CAM-O-SHAKE-DUR + @ 0> IF
        OVER _CAM-RAND
        OVER _CAM-O-SHAKE-AMP + @ MOD
        OVER _CAM-O-SHAKE-AMP + @ 2 / -
        +
    THEN
    NIP ;

\ =====================================================================
\  §8 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _cam-guard

' CAM-NEW     CONSTANT _cam-new-xt
' CAM-FREE    CONSTANT _cam-free-xt
' CAM-SMOOTH! CONSTANT _cam-smooth-xt
' CAM-BOUNDS! CONSTANT _cam-bounds-xt
' CAM-VIEW!   CONSTANT _cam-view-xt
' CAM-FOLLOW  CONSTANT _cam-follow-xt
' CAM-SNAP    CONSTANT _cam-snap-xt
' CAM-SHAKE   CONSTANT _cam-shake-xt
' CAM-TICK    CONSTANT _cam-tick-xt

: CAM-NEW     _cam-new-xt     _cam-guard WITH-GUARD ;
: CAM-FREE    _cam-free-xt    _cam-guard WITH-GUARD ;
: CAM-SMOOTH! _cam-smooth-xt  _cam-guard WITH-GUARD ;
: CAM-BOUNDS! _cam-bounds-xt  _cam-guard WITH-GUARD ;
: CAM-VIEW!   _cam-view-xt    _cam-guard WITH-GUARD ;
: CAM-FOLLOW  _cam-follow-xt  _cam-guard WITH-GUARD ;
: CAM-SNAP    _cam-snap-xt    _cam-guard WITH-GUARD ;
: CAM-SHAKE   _cam-shake-xt   _cam-guard WITH-GUARD ;
: CAM-TICK    _cam-tick-xt    _cam-guard WITH-GUARD ;
[THEN] [THEN]
