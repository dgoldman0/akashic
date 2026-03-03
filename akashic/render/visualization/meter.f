\ meter.f — Level meters & audio decorators for Akashic render pipeline
\ Part of Akashic render/visualization library for Megapad-64 / KDOS
\
\ Renders audio level meters and related decorators onto surfaces.
\ Designed for VU-style displays, peak indicators, and per-region
\ energy bar charts.
\
\ Features:
\   - Horizontal and vertical bar meters (RMS + peak)
\   - Dual-bar mode: RMS solid fill + peak marker
\   - Energy region bar chart (uses PCM-ENERGY-REGIONS style data)
\   - Clipping indicator (red flash when peak ≥ 1.0)
\   - Configurable color gradients (green→yellow→red)
\   - dB scale labels (optional)
\   - Stereo paired meters
\
\ Prefix: METER-   (public API)
\         _MT-     (internal helpers)
\
\ Load with:   REQUIRE render/visualization/meter.f
\
\ Dependencies:
\   akashic-surface   — pixel buffer target
\   akashic-draw      — drawing primitives
\   akashic-pcm       — PCM buffer access
\   akashic-fp16      — FP16 math
\   akashic-fp16-ext  — FP16-CLAMP, FP16-SQRT, etc.

REQUIRE ../surface.f
REQUIRE ../draw.f
REQUIRE ../../audio/pcm.f
REQUIRE ../../math/fp16.f
REQUIRE ../../math/fp16-ext.f

PROVIDED akashic-meter

\ =====================================================================
\  Color palette — RGBA8888
\ =====================================================================

0x121212FF CONSTANT METER-BG          \ near-black background
0x2A2A2AFF CONSTANT METER-TRACK      \ dark grey meter track
0x4CAF50FF CONSTANT METER-GREEN      \ green (low levels)
0xFFEB3BFF CONSTANT METER-YELLOW     \ yellow (mid levels)
0xF44336FF CONSTANT METER-RED        \ red (high / clip)
0xFF1744FF CONSTANT METER-CLIP       \ bright red clip indicator
0xFFFFFFFF CONSTANT METER-TEXT       \ white labels
0x666666FF CONSTANT METER-GRID       \ tick mark color
0x00E676FF CONSTANT METER-PEAK-MK   \ green peak marker line
0x1A1A1AFF CONSTANT METER-BORDER    \ border color

\ =====================================================================
\  Level thresholds (FP16) for gradient coloring
\ =====================================================================
\  green < 0.5,  yellow 0.5–0.85,  red > 0.85

0x3800 CONSTANT _MT-THRESH-MID   \ 0.5
0x3ACC CONSTANT _MT-THRESH-HI    \ 0.85

\ =====================================================================
\  Configuration — 112 bytes (14 cells)
\ =====================================================================

  0 CONSTANT MC.ORIENT      \ 0 = horizontal, 1 = vertical
  8 CONSTANT MC.X           \ meter position X on surface
 16 CONSTANT MC.Y           \ meter position Y
 24 CONSTANT MC.W           \ meter width (pixels)
 32 CONSTANT MC.H           \ meter height (pixels)
 40 CONSTANT MC.FLAGS       \ bit flags
 48 CONSTANT MC.BG          \ background color
 56 CONSTANT MC.TRACK       \ track (unfilled) color
 64 CONSTANT MC.BORDER      \ border color
 72 CONSTANT MC.PEAK-MK     \ peak marker color
 80 CONSTANT MC.SURF        \ target surface
 88 CONSTANT MC.PCM         \ PCM buffer (for auto-analysis)
 96 CONSTANT MC.RMS-VAL     \ current RMS level (FP16, 0-1)
104 CONSTANT MC.PEAK-VAL    \ current peak level (FP16, 0-1)

112 CONSTANT _MT-CFG-SIZE

\ --- Flag bits ---
1 CONSTANT METER-F-PEAK       \ show peak marker
2 CONSTANT METER-F-GRADIENT   \ color gradient (else solid green)
4 CONSTANT METER-F-BORDER     \ draw 1px border
8 CONSTANT METER-F-TICKS      \ draw scale tick marks
16 CONSTANT METER-F-CLIP      \ show clip indicator flash

\ =====================================================================
\  METER-CONFIG-CREATE — allocate and init default meter config
\ =====================================================================
\  ( surf x y w h -- cfg )

: METER-CONFIG-CREATE  ( surf x y w h -- cfg )
    >R >R >R >R >R
    _MT-CFG-SIZE ALLOCATE DROP
    DUP _MT-CFG-SIZE 0 FILL

    R> OVER MC.SURF + !
    R> OVER MC.X + !
    R> OVER MC.Y + !
    R> OVER MC.W + !
    R> OVER MC.H + !

    \ Defaults
    DUP MC.ORIENT + 0 SWAP !          \ horizontal
    DUP MC.FLAGS +
        METER-F-PEAK METER-F-GRADIENT OR METER-F-BORDER OR
        SWAP !
    DUP MC.BG      + METER-BG     SWAP !
    DUP MC.TRACK   + METER-TRACK  SWAP !
    DUP MC.BORDER  + METER-BORDER SWAP !
    DUP MC.PEAK-MK + METER-PEAK-MK SWAP !
    DUP MC.RMS-VAL + FP16-POS-ZERO SWAP !
    DUP MC.PEAK-VAL + FP16-POS-ZERO SWAP !
    DUP MC.PCM + 0 SWAP !
    ;

\ =====================================================================
\  METER-CONFIG-FREE — release config
\ =====================================================================

: METER-CONFIG-FREE  ( cfg -- )  FREE DROP ;

\ =====================================================================
\  Internal scratch
\ =====================================================================

VARIABLE _MT-CFG
VARIABLE _MT-SURF
VARIABLE _MT-X
VARIABLE _MT-Y
VARIABLE _MT-W
VARIABLE _MT-H
VARIABLE _MT-RMS
VARIABLE _MT-PEAK
VARIABLE _MT-INNER-X   \ inner area (inside border)
VARIABLE _MT-INNER-Y
VARIABLE _MT-INNER-W
VARIABLE _MT-INNER-H

\ =====================================================================
\  Internal: setup from config
\ =====================================================================

: _MT-SETUP  ( cfg -- )
    DUP _MT-CFG !
    DUP MC.SURF + @ _MT-SURF !
    DUP MC.X + @ _MT-X !
    DUP MC.Y + @ _MT-Y !
    DUP MC.W + @ _MT-W !
    DUP MC.H + @ _MT-H !
    DUP MC.RMS-VAL + @ _MT-RMS !
    DUP MC.PEAK-VAL + @ _MT-PEAK !

    \ Compute inner area (1px border if enabled)
    _MT-CFG @ MC.FLAGS + @ METER-F-BORDER AND IF
        _MT-X @ 1+ _MT-INNER-X !
        _MT-Y @ 1+ _MT-INNER-Y !
        _MT-W @ 2 - _MT-INNER-W !
        _MT-H @ 2 - _MT-INNER-H !
    ELSE
        _MT-X @ _MT-INNER-X !
        _MT-Y @ _MT-INNER-Y !
        _MT-W @ _MT-INNER-W !
        _MT-H @ _MT-INNER-H !
    THEN

    DROP ;

\ =====================================================================
\  Internal: level → color (gradient: green → yellow → red)
\ =====================================================================
\  level is FP16 in [0, 1]

: _MT-LEVEL-COLOR  ( fp16-level -- rgba )
    _MT-CFG @ MC.FLAGS + @ METER-F-GRADIENT AND 0= IF
        DROP METER-GREEN EXIT
    THEN

    DUP _MT-THRESH-HI FP16-GT IF
        DROP METER-RED EXIT
    THEN

    _MT-THRESH-MID FP16-GT IF
        METER-YELLOW EXIT
    THEN

    METER-GREEN ;

\ =====================================================================
\  Internal: draw border
\ =====================================================================

: _MT-DRAW-BORDER  ( -- )
    _MT-CFG @ MC.FLAGS + @ METER-F-BORDER AND 0= IF EXIT THEN
    _MT-SURF @
    _MT-X @ _MT-Y @ _MT-W @ _MT-H @
    _MT-CFG @ MC.BORDER + @
    1 DRAW-RECT-OUTLINE ;

\ =====================================================================
\  Internal: draw track (unfilled background of meter)
\ =====================================================================

: _MT-DRAW-TRACK  ( -- )
    _MT-SURF @
    _MT-INNER-X @ _MT-INNER-Y @
    _MT-INNER-W @ _MT-INNER-H @
    _MT-CFG @ MC.TRACK + @
    DRAW-RECT ;

\ =====================================================================
\  Internal: draw horizontal meter bar
\ =====================================================================

: _MT-DRAW-HBAR  ( fp16-level color -- )
    >R                                 ( level ) ( R: color )
    \ bar_width = level * inner_w
    FP16-POS-ZERO FP16-POS-ONE FP16-CLAMP
    _MT-INNER-W @ INT>FP16 FP16-MUL FP16>INT
    ( bar-w )
    DUP 0 > IF
        _MT-SURF @
        _MT-INNER-X @ _MT-INNER-Y @
        ROT _MT-INNER-H @
        R> DRAW-RECT
    ELSE
        DROP R> DROP
    THEN ;

\ =====================================================================
\  Internal: draw vertical meter bar (fills from bottom up)
\ =====================================================================

: _MT-DRAW-VBAR  ( fp16-level color -- )
    >R
    FP16-POS-ZERO FP16-POS-ONE FP16-CLAMP
    _MT-INNER-H @ INT>FP16 FP16-MUL FP16>INT
    ( bar-h )
    DUP 0 > IF
        _MT-SURF @
        _MT-INNER-X @
        _MT-INNER-Y @ _MT-INNER-H @ + OVER -   ( surf x y )
        _MT-INNER-W @                            ( surf x y w )
        4 ROLL                                   ( surf x y w h )
        R> DRAW-RECT
    ELSE
        DROP R> DROP
    THEN ;

\ =====================================================================
\  Internal: draw peak marker (thin line at peak position)
\ =====================================================================

: _MT-DRAW-PEAK-H  ( fp16-peak -- )
    _MT-CFG @ MC.FLAGS + @ METER-F-PEAK AND 0= IF DROP EXIT THEN
    FP16-POS-ZERO FP16-POS-ONE FP16-CLAMP
    _MT-INNER-W @ INT>FP16 FP16-MUL FP16>INT
    ( x-offset )
    DUP 0 > IF
        _MT-INNER-X @ + >R
        _MT-SURF @ R> _MT-INNER-Y @
        _MT-INNER-H @
        _MT-CFG @ MC.PEAK-MK + @
        DRAW-VLINE
    ELSE
        DROP
    THEN ;

: _MT-DRAW-PEAK-V  ( fp16-peak -- )
    _MT-CFG @ MC.FLAGS + @ METER-F-PEAK AND 0= IF DROP EXIT THEN
    FP16-POS-ZERO FP16-POS-ONE FP16-CLAMP
    _MT-INNER-H @ INT>FP16 FP16-MUL FP16>INT
    ( y-offset )
    DUP 0 > IF
        _MT-INNER-Y @ _MT-INNER-H @ + SWAP - >R
        _MT-SURF @ _MT-INNER-X @ R>
        _MT-INNER-W @
        _MT-CFG @ MC.PEAK-MK + @
        DRAW-HLINE
    ELSE
        DROP
    THEN ;

\ =====================================================================
\  Internal: draw tick marks (scale divisions)
\ =====================================================================

: _MT-DRAW-TICKS-H  ( -- )
    _MT-CFG @ MC.FLAGS + @ METER-F-TICKS AND 0= IF EXIT THEN
    \ Draw 10 tick marks along the bottom edge
    11 0 DO
        _MT-INNER-X @  I _MT-INNER-W @ * 10 /  +
        >R
        _MT-SURF @ R>
        _MT-INNER-Y @ _MT-INNER-H @ + 1 -
        2
        METER-GRID
        DRAW-VLINE
    LOOP ;

: _MT-DRAW-TICKS-V  ( -- )
    _MT-CFG @ MC.FLAGS + @ METER-F-TICKS AND 0= IF EXIT THEN
    11 0 DO
        _MT-INNER-Y @ _MT-INNER-H @ +
        I _MT-INNER-H @ * 10 / -
        >R
        _MT-SURF @ _MT-INNER-X @ R>
        2
        METER-GRID
        DRAW-HLINE
    LOOP ;

\ =====================================================================
\  Internal: clip indicator (red bar at the end if peak ≥ 1.0)
\ =====================================================================

: _MT-DRAW-CLIP-H  ( -- )
    _MT-CFG @ MC.FLAGS + @ METER-F-CLIP AND 0= IF EXIT THEN
    _MT-PEAK @ FP16-POS-ONE FP16-GT 0= IF EXIT THEN
    \ Draw 3px red bar at the right edge
    _MT-SURF @
    _MT-INNER-X @ _MT-INNER-W @ + 3 -
    _MT-INNER-Y @
    3 _MT-INNER-H @
    METER-CLIP DRAW-RECT ;

: _MT-DRAW-CLIP-V  ( -- )
    _MT-CFG @ MC.FLAGS + @ METER-F-CLIP AND 0= IF EXIT THEN
    _MT-PEAK @ FP16-POS-ONE FP16-GT 0= IF EXIT THEN
    _MT-SURF @
    _MT-INNER-X @ _MT-INNER-Y @
    _MT-INNER-W @ 3
    METER-CLIP DRAW-RECT ;

\ =====================================================================
\  METER-DRAW — main entry: render a single meter
\ =====================================================================
\  ( cfg -- )

: METER-DRAW  ( cfg -- )
    _MT-SETUP

    _MT-DRAW-BORDER
    _MT-DRAW-TRACK

    \ Determine color from RMS level
    _MT-RMS @ _MT-LEVEL-COLOR

    \ Draw filled bar
    _MT-CFG @ MC.ORIENT + @ 0= IF
        \ Horizontal
        _MT-RMS @ SWAP _MT-DRAW-HBAR
        _MT-PEAK @ _MT-DRAW-PEAK-H
        _MT-DRAW-TICKS-H
        _MT-DRAW-CLIP-H
    ELSE
        \ Vertical
        _MT-RMS @ SWAP _MT-DRAW-VBAR
        _MT-PEAK @ _MT-DRAW-PEAK-V
        _MT-DRAW-TICKS-V
        _MT-DRAW-CLIP-V
    THEN ;

\ =====================================================================
\  METER-SET-LEVELS  ( rms-fp16 peak-fp16 cfg -- )
\  Manually set meter levels (e.g., from external analysis).

: METER-SET-LEVELS  ( rms peak cfg -- )
    TUCK MC.PEAK-VAL + !
    MC.RMS-VAL + ! ;

\ =====================================================================
\  METER-ANALYZE  ( pcm cfg -- )
\  Analyze a PCM buffer and update meter levels automatically.
\  Uses PCM-SCAN-PEAK for peak detection and a simple RMS scan.

VARIABLE _MT-SUM
VARIABLE _MT-NSAMP
VARIABLE _MT-SAMP

: METER-ANALYZE  ( pcm cfg -- )
    >R >R

    \ Peak: scan and read
    R@ PCM-SCAN-PEAK FP16-ABS
    R> OVER R@ MC.PEAK-VAL + !

    \ RMS: sum of squares via FP16-MUL, divide by N
    \ (Simplified: use FP32 for accumulation would be better,
    \  but for meter display FP16 precision is sufficient)
    FP16-POS-ZERO _MT-SUM !
    R@ MC.PCM + @
    DUP 0<> IF
        DUP PCM-LEN _MT-NSAMP !
        _MT-NSAMP @ 0 DO
            I 0 OVER PCM-SAMPLE@
            DUP FP16-MUL                \ sample²
            _MT-SUM @ FP16-ADD _MT-SUM !
            DROP
        LOOP
        _MT-SUM @
        _MT-NSAMP @ INT>FP16 FP16-DIV  \ mean of squares
        FP16-SQRT                       \ RMS
        R@ MC.RMS-VAL + !
    ELSE
        DROP
    THEN

    R> DROP ;

\ =====================================================================
\  METER-ORIENT!  ( 0|1 cfg -- )
\  Set orientation: 0=horizontal, 1=vertical.

: METER-ORIENT!  ( orient cfg -- )
    MC.ORIENT + ! ;

\ =====================================================================
\  Energy region bar chart
\ =====================================================================
\  METER-ENERGY-CHART  ( rms-array n surf x y w h -- )
\  Draws a bar chart of N energy values (FP16 array, e.g.
\  per-region RMS levels).  Each bar auto-colored by level.
\
\  rms-array: address of N consecutive FP16 values (2 bytes each)
\  n: number of regions
\  surf x y w h: target area

VARIABLE _MT-EC-N
VARIABLE _MT-EC-ARR
VARIABLE _MT-EC-SURF
VARIABLE _MT-EC-X
VARIABLE _MT-EC-Y
VARIABLE _MT-EC-W
VARIABLE _MT-EC-H
VARIABLE _MT-EC-BARW
VARIABLE _MT-EC-GAP

: METER-ENERGY-CHART  ( rms-array n surf x y w h -- )
    _MT-EC-H ! _MT-EC-W ! _MT-EC-Y ! _MT-EC-X !
    _MT-EC-SURF ! _MT-EC-N ! _MT-EC-ARR !

    \ Draw track background
    _MT-EC-SURF @
    _MT-EC-X @ _MT-EC-Y @
    _MT-EC-W @ _MT-EC-H @
    METER-TRACK DRAW-RECT

    \ Bar width = (w - (n-1)*gap) / n , gap=2
    2 _MT-EC-GAP !
    _MT-EC-W @
    _MT-EC-N @ 1 - _MT-EC-GAP @ * -
    _MT-EC-N @ /
    1 MAX _MT-EC-BARW !

    _MT-EC-N @ 0 DO
        \ Read RMS value
        _MT-EC-ARR @ I 2* + W@        ( rms-fp16 )
        DUP FP16-POS-ZERO FP16-POS-ONE FP16-CLAMP

        \ Height
        _MT-EC-H @ INT>FP16 FP16-MUL FP16>INT  ( rms-fp16 bar-h )
        SWAP

        \ Color from level
        _MT-LEVEL-COLOR                ( bar-h color )
        >R

        DUP 0 > IF
            \ X position
            _MT-EC-X @  I _MT-EC-BARW @ _MT-EC-GAP @ + * +
            \ Y = bottom - h
            _MT-EC-Y @ _MT-EC-H @ + 2 PICK -

            ( bar-h x y )
            >R >R
            _MT-EC-SURF @ R> R>
            _MT-EC-BARW @
            4 ROLL
            R> DRAW-RECT
        ELSE
            DROP R> DROP
        THEN
    LOOP ;

\ =====================================================================
\  Stereo paired meters
\ =====================================================================
\  METER-STEREO-DRAW  ( cfg-l cfg-r -- )
\  Draws two meters side-by-side. Caller sets up positions.

: METER-STEREO-DRAW  ( cfg-l cfg-r -- )
    METER-DRAW METER-DRAW ;
