\ waveform.f — PCM waveform visualization for Akashic render pipeline
\ Part of Akashic render/visualization library for Megapad-64 / KDOS
\
\ Renders PCM audio buffers as time-domain waveform plots onto a
\ surface.  Supports:
\   - Configurable view window (start frame, frame count, zoom)
\   - Signed-sample to pixel-Y mapping (center = zero line)
\   - Grid lines (time divisions, amplitude divisions)
\   - Peak envelope overlay (optional)
\   - Zero-crossing line
\   - Stereo: stacked (top/bottom) or overlaid channels
\   - Antialiased min/max column mode for wide zoom-outs
\
\ All rendering targets a SURF-CREATE surface (RGBA8888).
\ PCM samples are assumed FP16 (16-bit, as produced by syn/ engines).
\
\ Prefix: WAVE-   (public API)
\         _WV-    (internal helpers)
\
\ Load with:   REQUIRE render/visualization/waveform.f
\
\ Dependencies:
\   akashic-surface   — pixel buffer target
\   akashic-draw      — line / rect primitives
\   akashic-pcm       — PCM buffer access
\   akashic-fp16      — FP16 math (FP16>INT, INT>FP16, FP16-MUL ...)

REQUIRE ../surface.f
REQUIRE ../draw.f
REQUIRE ../../audio/pcm.f
REQUIRE ../../math/fp16.f

PROVIDED akashic-waveform

\ =====================================================================
\  Color palette — RGBA8888 constants
\ =====================================================================

0x1A1A2EFF CONSTANT WAVE-BG           \ dark navy background
0x2D4A7AFF CONSTANT WAVE-GRID         \ muted blue grid lines
0x4A90D9FF CONSTANT WAVE-ZERO-LINE    \ brighter blue zero line
0x00E676FF CONSTANT WAVE-COLOR        \ green waveform trace
0x00E67680 CONSTANT WAVE-COLOR-DIM    \ translucent green (stereo overlay)
0xFF5252FF CONSTANT WAVE-PEAK         \ red peak markers
0xFFD740FF CONSTANT WAVE-ENVELOPE     \ yellow peak envelope
0xFFFFFFFF CONSTANT WAVE-TEXT-COLOR   \ white text/labels
0x3A3A5CFF CONSTANT WAVE-GRID-MINOR  \ faint minor grid

\ =====================================================================
\  Configuration descriptor — 120 bytes (15 cells)
\ =====================================================================
\  Allocated once, reused across draws.

 0 CONSTANT WC.START       \ start frame (first visible sample)
 8 CONSTANT WC.COUNT       \ number of frames to display
16 CONSTANT WC.AMPSCALE    \ amplitude scale (FP16, default 1.0)
24 CONSTANT WC.GRIDX       \ time grid interval (frames); 0=auto
32 CONSTANT WC.GRIDY       \ amplitude grid divisions; 0=none
40 CONSTANT WC.FLAGS       \ bit flags (see below)
48 CONSTANT WC.BG          \ background color (RGBA)
56 CONSTANT WC.FG          \ primary waveform color (RGBA)
64 CONSTANT WC.FG2         \ secondary channel color (RGBA)
72 CONSTANT WC.GRIDCOLOR   \ grid line color (RGBA)
80 CONSTANT WC.ZEROCOLOR   \ zero-line color (RGBA)
88 CONSTANT WC.PEAKCOLOR   \ peak-envelope color (RGBA)
96 CONSTANT WC.MARGIN      \ margin in pixels (all sides)
104 CONSTANT WC.PCM        \ PCM buffer pointer
112 CONSTANT WC.SURF       \ target surface pointer

120 CONSTANT _WV-CFG-SIZE

\ --- Flag bits ---
1 CONSTANT WAVE-F-GRID       \ draw grid
2 CONSTANT WAVE-F-ZERO       \ draw zero-crossing line
4 CONSTANT WAVE-F-ENVELOPE   \ draw peak envelope
8 CONSTANT WAVE-F-STEREO-STACK  \ stereo: stacked (else overlay)
16 CONSTANT WAVE-F-FILLED    \ filled waveform (vs line)

\ =====================================================================
\  WAVE-CONFIG-CREATE — allocate and initialize default config
\ =====================================================================
\  ( pcm surf -- cfg )

: WAVE-CONFIG-CREATE  ( pcm surf -- cfg )
    SWAP >R >R
    _WV-CFG-SIZE ALLOCATE DROP         \ allocate descriptor
    DUP _WV-CFG-SIZE 0 FILL           \ zero out

    \ Defaults
    DUP WC.START + 0 SWAP !           \ start = 0
    R> OVER WC.SURF + !               \ store surface
    R> DUP ROT TUCK WC.PCM + !        \ store PCM ( pcm cfg )
    SWAP PCM-LEN                       \ ( cfg len )
    OVER WC.COUNT + !                  \ count = full buffer

    DUP WC.AMPSCALE + FP16-POS-ONE SWAP !   \ amp scale = 1.0
    DUP WC.GRIDX + 0 SWAP !           \ auto grid
    DUP WC.GRIDY + 4 SWAP !           \ 4 amplitude divisions
    DUP WC.FLAGS +
        WAVE-F-GRID WAVE-F-ZERO OR SWAP !   \ grid + zero line

    DUP WC.BG +       WAVE-BG        SWAP !
    DUP WC.FG +       WAVE-COLOR     SWAP !
    DUP WC.FG2 +      WAVE-COLOR-DIM SWAP !
    DUP WC.GRIDCOLOR + WAVE-GRID     SWAP !
    DUP WC.ZEROCOLOR + WAVE-ZERO-LINE SWAP !
    DUP WC.PEAKCOLOR + WAVE-ENVELOPE SWAP !
    DUP WC.MARGIN +   4 SWAP !        \ 4-pixel margin
    ;

\ =====================================================================
\  WAVE-CONFIG-FREE — release config descriptor
\ =====================================================================

: WAVE-CONFIG-FREE  ( cfg -- )  FREE DROP ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _WV-CFG        \ current config pointer
VARIABLE _WV-SURF       \ current surface
VARIABLE _WV-PCM        \ current PCM buffer
VARIABLE _WV-PX         \ plot area X origin
VARIABLE _WV-PY         \ plot area Y origin
VARIABLE _WV-PW         \ plot area width (pixels)
VARIABLE _WV-PH         \ plot area height (pixels)
VARIABLE _WV-MID        \ Y pixel of zero line (center)
VARIABLE _WV-HALF       \ half-height (pixels from center to edge)
VARIABLE _WV-START      \ view start frame
VARIABLE _WV-COUNT      \ view frame count
VARIABLE _WV-SPP        \ samples per pixel (FP16)  >1 means zoom out
VARIABLE _WV-AMP        \ amplitude scale (FP16)

\ Temp for rendering loop
VARIABLE _WV-X
VARIABLE _WV-YMIN
VARIABLE _WV-YMAX
VARIABLE _WV-PREV-Y
VARIABLE _WV-CUR-Y
VARIABLE _WV-SAMP

\ Grid-loop scratch (cannot use >R/R@ inside DO — R@ returns loop index)
VARIABLE _WV-NDIV       \ amplitude grid divisions
VARIABLE _WV-GSTEP      \ time grid pixel step
VARIABLE _WV-GINT       \ time grid frame interval

\ Wave-draw scratch (same issue: R@ in DO returns I, not pushed value)
VARIABLE _WV-COLOR      \ foreground color for current draw
VARIABLE _WV-SPAN       \ frame span for current pixel column
VARIABLE _WV-F0         \ frame start for current pixel column

\ =====================================================================
\  Internal: compute plot area from surface + margin
\ =====================================================================

: _WV-SETUP  ( cfg -- )
    DUP _WV-CFG !
    DUP WC.SURF + @ _WV-SURF !
    DUP WC.PCM  + @ _WV-PCM !
    DUP WC.START + @ _WV-START !
    DUP WC.COUNT + @ _WV-COUNT !
    DUP WC.AMPSCALE + @ _WV-AMP !

    \ Plot area = surface minus margin on all sides
    DUP WC.MARGIN + @ >R              ( cfg ) ( R: margin )
    _WV-SURF @ SURF-W R@ 2* - _WV-PW !
    _WV-SURF @ SURF-H R@ 2* - _WV-PH !
    R@ _WV-PX !
    R> _WV-PY !

    \ Center line and half-height
    _WV-PH @ 2/ _WV-HALF !
    _WV-PY @ _WV-HALF @ + _WV-MID !

    \ Samples per pixel (FP16)
    \ SPP = count / plot_width
    _WV-COUNT @  INT>FP16
    _WV-PW @     INT>FP16  FP16-DIV
    _WV-SPP !

    DROP ;

\ =====================================================================
\  Internal: FP16 sample → pixel Y
\ =====================================================================
\  Y = mid - (sample * amp * half)
\  sample is FP16 in [-1,1], amp is FP16 scale, half is pixels.

: _WV-SAMPLE>Y  ( fp16-sample -- y-pixel )
    _WV-AMP @ FP16-MUL                \ apply amplitude scale
    _WV-HALF @ INT>FP16 FP16-MUL      \ scale to pixels
    FP16>INT                           \ convert to integer
    _WV-MID @ SWAP - ;                \ flip: positive sample = up

\ =====================================================================
\  Internal: read sample, clamped to buffer bounds
\ =====================================================================

: _WV-GET-SAMPLE  ( frame -- fp16 )
    DUP 0 < IF DROP FP16-POS-ZERO EXIT THEN
    DUP _WV-PCM @ PCM-LEN >= IF DROP FP16-POS-ZERO EXIT THEN
    0 _WV-PCM @ PCM-SAMPLE@ ;

\ =====================================================================
\  Internal: draw background
\ =====================================================================

: _WV-DRAW-BG  ( -- )
    _WV-SURF @  _WV-CFG @ WC.BG + @  SURF-CLEAR ;

\ =====================================================================
\  Internal: draw grid lines
\ =====================================================================

: _WV-DRAW-GRID  ( -- )
    _WV-CFG @ WC.FLAGS + @ WAVE-F-GRID AND 0= IF EXIT THEN

    \ --- Amplitude grid (horizontal lines) ---
    _WV-CFG @ WC.GRIDY + @ DUP 0= IF DROP EXIT THEN
    _WV-NDIV !            \ save n-divisions to variable
    \ Draw n+1 lines from top to bottom of plot area
    _WV-NDIV @ 1+ 0 DO
        _WV-PY @  _WV-PH @ I * _WV-NDIV @ /  +   ( y )
        _WV-SURF @ _WV-PX @ ROT _WV-PW @
        _WV-CFG @ WC.GRIDCOLOR + @
        DRAW-HLINE
    LOOP

    \ --- Time grid (vertical lines) ---
    _WV-CFG @ WC.GRIDX + @ DUP 0<> IF
        \ Manual grid interval (in frames)
        _WV-GINT !            \ save interval to variable
        _WV-COUNT @ _WV-GINT @ / 1+ 0 DO
            I _WV-GINT @ * INT>FP16  _WV-SPP @ FP16-DIV  FP16>INT
            _WV-PX @ +  ( x )
            DUP _WV-PX @ _WV-PW @ + >= IF DROP ELSE
                _WV-SURF @ SWAP _WV-PY @ _WV-PH @
                _WV-CFG @ WC.GRIDCOLOR + @
                DRAW-VLINE
            THEN
        LOOP
    ELSE
        DROP
        \ Auto: ~8 vertical divisions
        _WV-PW @ 8 / DUP 0= IF DROP 1 THEN
        _WV-GSTEP !           \ save pixel-step to variable
        _WV-PW @ _WV-GSTEP @ / 1+ 0 DO
            _WV-PX @ I _WV-GSTEP @ * +  ( x )
            DUP _WV-PX @ _WV-PW @ + >= IF DROP ELSE
                _WV-SURF @ SWAP _WV-PY @ _WV-PH @
                _WV-CFG @ WC.GRIDCOLOR + @
                DRAW-VLINE
            THEN
        LOOP
    THEN ;

\ =====================================================================
\  Internal: draw zero-crossing line
\ =====================================================================

: _WV-DRAW-ZERO  ( -- )
    _WV-CFG @ WC.FLAGS + @ WAVE-F-ZERO AND 0= IF EXIT THEN
    _WV-SURF @ _WV-PX @ _WV-MID @ _WV-PW @
    _WV-CFG @ WC.ZEROCOLOR + @
    DRAW-HLINE ;

\ =====================================================================
\  Internal: draw waveform — line mode (1:1 or interpolated)
\ =====================================================================
\  When SPP ≤ 1 (zoomed in): draw one pixel per sample, connect
\  with vertical lines for continuity.
\  When SPP > 1 (zoomed out): for each pixel column, scan the
\  sample range and draw a vertical min/max bar.

: _WV-DRAW-WAVE-LINE  ( color -- )
    _WV-COLOR !

    \ For each pixel column in plot area
    _WV-PW @ 0 DO
        I _WV-PX @ +  _WV-X !

        \ Compute frame range for this pixel column
        I     INT>FP16 _WV-SPP @ FP16-MUL FP16>INT _WV-START @ +
        I 1 + INT>FP16 _WV-SPP @ FP16-MUL FP16>INT _WV-START @ +

        ( f0 f1 )
        OVER - 1 MAX _WV-SPAN !
        _WV-F0 !

        \ First sample → initial min/max Y
        _WV-F0 @ _WV-GET-SAMPLE _WV-SAMPLE>Y
        DUP _WV-YMIN ! _WV-YMAX !

        \ If span>1 (zoomed out): scan remaining samples
        _WV-SPAN @ 1 > IF
            _WV-SPAN @ 1 DO
                _WV-F0 @ I + _WV-GET-SAMPLE _WV-SAMPLE>Y
                DUP _WV-YMIN @ < IF DUP _WV-YMIN ! THEN
                DUP _WV-YMAX @ > IF DUP _WV-YMAX ! THEN
                DROP
            LOOP
        THEN

        \ Draw vertical bar from ymin to ymax
        _WV-SURF @ _WV-X @ _WV-YMIN @
        _WV-YMAX @ _WV-YMIN @ - 1+
        _WV-COLOR @ DRAW-VLINE

        \ Connect to previous column with a line if gap
        I 0 > IF
            _WV-PREV-Y @ _WV-YMIN @ <> IF
                _WV-SURF @
                _WV-X @ 1 - _WV-PREV-Y @
                _WV-X @ _WV-YMIN @
                _WV-COLOR @ DRAW-LINE
            THEN
        THEN

        _WV-YMAX @ _WV-PREV-Y !
    LOOP ;

\ =====================================================================
\  Internal: draw waveform — filled mode
\ =====================================================================
\  Draws filled area from zero line to sample value.

: _WV-DRAW-WAVE-FILLED  ( color -- )
    _WV-COLOR !

    _WV-PW @ 0 DO
        I _WV-PX @ + _WV-X !

        \ Frame for this pixel
        I INT>FP16 _WV-SPP @ FP16-MUL FP16>INT _WV-START @ +
        _WV-GET-SAMPLE _WV-SAMPLE>Y  _WV-CUR-Y !

        \ Draw vertical bar from zero line to sample
        _WV-CUR-Y @ _WV-MID @ < IF
            \ Sample above center (positive)
            _WV-SURF @  _WV-X @  _WV-CUR-Y @
            _WV-MID @ _WV-CUR-Y @ - 1+
            _WV-COLOR @ DRAW-VLINE
        ELSE
            \ Sample below center (negative) or at center
            _WV-SURF @  _WV-X @  _WV-MID @
            _WV-CUR-Y @ _WV-MID @ - 1+
            _WV-COLOR @ DRAW-VLINE
        THEN
    LOOP ;

\ =====================================================================
\  Internal: draw peak envelope overlay
\ =====================================================================
\  Scans the visible range in blocks and draws peak markers.

VARIABLE _WV-ENV-BLOCK
VARIABLE _WV-ENV-MAX

: _WV-DRAW-ENVELOPE  ( -- )
    _WV-CFG @ WC.FLAGS + @ WAVE-F-ENVELOPE AND 0= IF EXIT THEN

    \ Block size: ~8 pixels worth of samples
    8 INT>FP16 _WV-SPP @ FP16-MUL FP16>INT
    1 MAX _WV-ENV-BLOCK !

    _WV-PW @ 0 DO
        \ Frame for this pixel
        I INT>FP16 _WV-SPP @ FP16-MUL FP16>INT _WV-START @ +
        ( frame )

        \ Find peak in the block around this frame
        DUP _WV-ENV-BLOCK @ + OVER DO
            I _WV-GET-SAMPLE FP16-ABS
            DUP _WV-ENV-MAX @ FP16-MAX DUP _WV-ENV-MAX @ <> IF
                _WV-ENV-MAX !
            ELSE
                DROP
            THEN
            DROP
        LOOP
        DROP

        \ Draw envelope dot (positive side)
        _WV-ENV-MAX @ _WV-SAMPLE>Y >R
        _WV-SURF @ I _WV-PX @ + R>
        _WV-CFG @ WC.PEAKCOLOR + @
        SURF-PIXEL!

        \ Mirror (negative side)
        _WV-ENV-MAX @ FP16-NEG _WV-SAMPLE>Y >R
        _WV-SURF @ I _WV-PX @ + R>
        _WV-CFG @ WC.PEAKCOLOR + @
        SURF-PIXEL!

        FP16-POS-ZERO _WV-ENV-MAX !
    LOOP ;

\ =====================================================================
\  WAVE-DRAW — main entry: render waveform to surface
\ =====================================================================
\  ( cfg -- )
\  Reads all configuration from the descriptor.
\  Clears the surface, draws grid, zero line, and waveform.

: WAVE-DRAW  ( cfg -- )
    _WV-SETUP

    \ Clear background
    _WV-DRAW-BG

    \ Grid
    _WV-DRAW-GRID

    \ Zero-crossing line
    _WV-DRAW-ZERO

    \ Waveform trace
    _WV-CFG @ WC.FLAGS + @ WAVE-F-FILLED AND IF
        _WV-CFG @ WC.FG + @ _WV-DRAW-WAVE-FILLED
    ELSE
        _WV-CFG @ WC.FG + @ _WV-DRAW-WAVE-LINE
    THEN

    \ Peak envelope
    _WV-DRAW-ENVELOPE ;

\ =====================================================================
\  Convenience: one-shot waveform render
\ =====================================================================
\  WAVE-RENDER  ( pcm surf -- )
\  Creates a default config, draws, frees config.

: WAVE-RENDER  ( pcm surf -- )
    2DUP WAVE-CONFIG-CREATE
    DUP WAVE-DRAW
    WAVE-CONFIG-FREE ;

\ =====================================================================
\  WAVE-ZOOM  ( start count cfg -- )
\  Set view window.

: WAVE-ZOOM  ( start count cfg -- )
    TUCK WC.COUNT + !
    WC.START + ! ;

\ =====================================================================
\  WAVE-AMPLITUDE!  ( fp16-scale cfg -- )
\  Set amplitude scale factor.

: WAVE-AMPLITUDE!  ( fp16-scale cfg -- )
    WC.AMPSCALE + ! ;

\ =====================================================================
\  WAVE-FLAGS!  ( flags cfg -- )
\  Set/replace all flags.

: WAVE-FLAGS!  ( flags cfg -- )
    WC.FLAGS + ! ;
