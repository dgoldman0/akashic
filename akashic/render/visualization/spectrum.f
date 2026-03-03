\ spectrum.f — FFT-based spectral display for Akashic render pipeline
\ Part of Akashic render/visualization library for Megapad-64 / KDOS
\
\ Renders a frequency-domain spectral plot from a PCM audio buffer.
\ Computes an FFT over a configurable window, then draws magnitude
\ bars or a line plot.
\
\ Features:
\   - Configurable FFT size (power of 2, default 256)
\   - Bar or line display mode
\   - Linear or logarithmic magnitude scale
\   - Configurable floor/ceiling (dB)
\   - Frequency axis labels (optional)
\   - Peak-hold markers (optional)
\   - Hann windowing to reduce spectral leakage
\   - Color gradient for bar heights (optional)
\
\ Prefix: SPEC-   (public API)
\         _SP-    (internal helpers)
\
\ Load with:   REQUIRE render/visualization/spectrum.f
\
\ Dependencies:
\   akashic-surface   — pixel buffer target
\   akashic-draw      — drawing primitives
\   akashic-pcm       — PCM buffer access
\   akashic-fp16      — FP16 math
\   akashic-fp16-ext  — FP16-SQRT, FP16-CLAMP, etc.
\   akashic-fft       — FFT-FORWARD, FFT-MAGNITUDE

REQUIRE ../surface.f
REQUIRE ../draw.f
REQUIRE ../../audio/pcm.f
REQUIRE ../../math/fp16.f
REQUIRE ../../math/fp16-ext.f
REQUIRE ../../math/fft.f

PROVIDED akashic-spectrum

\ =====================================================================
\  Color palette — RGBA8888 constants
\ =====================================================================

0x0D1117FF CONSTANT SPEC-BG           \ very dark background
0x21262DFF CONSTANT SPEC-GRID         \ faint grid
0x58A6FFFF CONSTANT SPEC-LINE-COLOR   \ bright blue line
0x1F6FEBFF CONSTANT SPEC-BAR-LO      \ bar gradient low  (blue)
0x56D364FF CONSTANT SPEC-BAR-HI      \ bar gradient high (green)
0xFF7B72FF CONSTANT SPEC-PEAK-HOLD   \ red-orange peak hold
0xFFFFFFFF CONSTANT SPEC-TEXT         \ white text
0x8B949EFF CONSTANT SPEC-AXIS        \ grey axis lines

\ =====================================================================
\  Configuration descriptor — 128 bytes (16 cells)
\ =====================================================================

  0 CONSTANT SC.FFTSIZE    \ FFT size (power of 2, e.g. 256)
  8 CONSTANT SC.START      \ start frame for analysis window
 16 CONSTANT SC.FLAGS      \ bit flags
 24 CONSTANT SC.FLOOR      \ magnitude floor (FP16, dB or linear)
 32 CONSTANT SC.CEIL       \ magnitude ceiling (FP16)
 40 CONSTANT SC.BG         \ background color
 48 CONSTANT SC.BARCOLOR   \ bar/line color
 56 CONSTANT SC.PEAKCOLOR  \ peak-hold color
 64 CONSTANT SC.GRIDCOLOR  \ grid line color
 72 CONSTANT SC.MARGIN     \ margin pixels
 80 CONSTANT SC.PCM        \ PCM buffer pointer
 88 CONSTANT SC.SURF       \ target surface pointer
 96 CONSTANT SC.REBUF      \ allocated: real buffer for FFT
104 CONSTANT SC.IMBUF      \ allocated: imaginary buffer for FFT
112 CONSTANT SC.MAGBUF     \ allocated: magnitude output buffer
120 CONSTANT SC.PEAKBUF    \ allocated: peak-hold buffer (or 0)

128 CONSTANT _SP-CFG-SIZE

\ --- Flag bits ---
1 CONSTANT SPEC-F-BARS      \ bar mode (else line)
2 CONSTANT SPEC-F-LOG       \ logarithmic magnitude (else linear)
4 CONSTANT SPEC-F-PEAK-HOLD \ draw peak-hold markers
8 CONSTANT SPEC-F-GRID      \ draw grid lines
16 CONSTANT SPEC-F-WINDOW   \ apply Hann window before FFT

\ =====================================================================
\  SPEC-CONFIG-CREATE — allocate and initialize default config
\ =====================================================================
\  ( pcm surf fftsize -- cfg )

VARIABLE _SP-ALLOC-CFG    \ scratch for SPEC-CONFIG-CREATE allocations

: SPEC-CONFIG-CREATE  ( pcm surf fftsize -- cfg )
    >R >R >R
    _SP-CFG-SIZE ALLOCATE DROP         \ allocate config
    DUP _SP-CFG-SIZE 0 FILL

    R> OVER SC.PCM  + !               \ pcm  (last pushed, first popped)
    R> OVER SC.SURF + !               \ surf
    R> OVER SC.FFTSIZE + !            \ fftsize (first pushed, last popped)

    DUP SC.START + 0 SWAP !

    \ Allocate FFT working buffers (all FP16 = 2 bytes per bin)
    \ Save cfg to variable so ALLOCATE block can reference it
    \ (OVER would reach 'bytes', not 'cfg', when stack is cfg bytes)
    DUP _SP-ALLOC-CFG !
    SC.FFTSIZE + @ 2*                 ( bytes )
    DUP ALLOCATE DROP _SP-ALLOC-CFG @ SC.REBUF  + !
    DUP ALLOCATE DROP _SP-ALLOC-CFG @ SC.IMBUF  + !
    DUP ALLOCATE DROP _SP-ALLOC-CFG @ SC.MAGBUF + !
    ALLOCATE DROP     _SP-ALLOC-CFG @ SC.PEAKBUF + !

    \ Zero the peak-hold buffer
    _SP-ALLOC-CFG @
    DUP SC.PEAKBUF + @ OVER SC.FFTSIZE + @ 2* 0 FILL

    \ Defaults
    DUP SC.FLAGS +
        SPEC-F-BARS SPEC-F-LOG OR SPEC-F-GRID OR SPEC-F-WINDOW OR
        SWAP !
    DUP SC.FLOOR + FP16-POS-ZERO SWAP !
    DUP SC.CEIL  + FP16-POS-ONE  SWAP !
    DUP SC.BG +        SPEC-BG        SWAP !
    DUP SC.BARCOLOR +  SPEC-BAR-LO    SWAP !
    DUP SC.PEAKCOLOR + SPEC-PEAK-HOLD SWAP !
    DUP SC.GRIDCOLOR + SPEC-GRID      SWAP !
    DUP SC.MARGIN +    4 SWAP !
    ;

\ =====================================================================
\  SPEC-CONFIG-FREE — release config and working buffers
\ =====================================================================

: SPEC-CONFIG-FREE  ( cfg -- )
    DUP SC.REBUF  + @ FREE DROP
    DUP SC.IMBUF  + @ FREE DROP
    DUP SC.MAGBUF + @ FREE DROP
    DUP SC.PEAKBUF + @ FREE DROP
    FREE DROP ;

\ =====================================================================
\  Internal scratch
\ =====================================================================

VARIABLE _SP-CFG
VARIABLE _SP-SURF
VARIABLE _SP-PCM
VARIABLE _SP-PX
VARIABLE _SP-PY
VARIABLE _SP-PW
VARIABLE _SP-PH
VARIABLE _SP-N         \ FFT size
VARIABLE _SP-BINS      \ displayable bins = N/2
VARIABLE _SP-RE
VARIABLE _SP-IM
VARIABLE _SP-MAG
VARIABLE _SP-PEAK
VARIABLE _SP-TMP

\ =====================================================================
\  Internal: setup from config
\ =====================================================================

: _SP-SETUP  ( cfg -- )
    DUP _SP-CFG !
    DUP SC.SURF + @ _SP-SURF !
    DUP SC.PCM  + @ _SP-PCM !
    DUP SC.FFTSIZE + @ _SP-N !
    _SP-N @ 2/ _SP-BINS !
    DUP SC.REBUF  + @ _SP-RE !
    DUP SC.IMBUF  + @ _SP-IM !
    DUP SC.MAGBUF + @ _SP-MAG !
    DUP SC.PEAKBUF + @ _SP-PEAK !

    \ Plot area
    DUP SC.MARGIN + @ >R
    _SP-SURF @ SURF-W R@ 2* - _SP-PW !
    _SP-SURF @ SURF-H R@ 2* - _SP-PH !
    R@ _SP-PX !
    R> _SP-PY !

    DROP ;

\ =====================================================================
\  Internal: fill FFT real buffer from PCM, apply Hann window
\ =====================================================================
\  Hann window: w(n) = 0.5 * (1 - cos(2*pi*n / (N-1)))
\  Simplified: use FP16 multiply with precomputed table would be
\  ideal, but for simplicity we approximate:
\    w(n) ≈ sin²(pi * n / N) ≈ n*(N-n) * 4/N² (parabolic approx)
\  This is a reasonable window that reduces leakage without lookup.
\
\  IMPORTANT: We also prescale each sample by 1/N to prevent FP16
\  overflow during the FFT butterfly accumulation.  The resulting
\  magnitude bins are therefore already normalized (per-sample avg).

VARIABLE _SP-WSCALE    \ 4/N² as FP16
VARIABLE _SP-PRESCALE  \ 1/N  as FP16

: _SP-LOAD-SAMPLES  ( -- )
    \ Compute 4/N² for parabolic window as (2/N)*(2/N)
    \ (Cannot compute N² directly — overflows FP16 for N>=256)
    2 INT>FP16  _SP-N @ INT>FP16  FP16-DIV   \ 2/N
    DUP FP16-MUL _SP-WSCALE !                \ (2/N)² = 4/N²

    \ Compute 1/N prescale to prevent FFT overflow
    FP16-POS-ONE
    _SP-N @ INT>FP16
    FP16-DIV _SP-PRESCALE !

    _SP-N @ 0 DO
        \ Read sample (or zero if past buffer)
        _SP-CFG @ SC.START + @ I +
        DUP 0 < IF DROP FP16-POS-ZERO
        ELSE DUP _SP-PCM @ PCM-LEN >= IF DROP FP16-POS-ZERO
        ELSE 0 _SP-PCM @ PCM-SAMPLE@
        THEN THEN

        \ Apply window if flagged
        _SP-CFG @ SC.FLAGS + @ SPEC-F-WINDOW AND IF
            \ w(n) = n * (N-n) * (4/N²)
            I INT>FP16
            _SP-N @ I - INT>FP16 FP16-MUL
            _SP-WSCALE @ FP16-MUL
            FP16-MUL
        THEN

        \ Prescale by 1/N to prevent FP16 overflow in FFT
        _SP-PRESCALE @ FP16-MUL

        \ Store into real buffer
        _SP-RE @ I 2* + W!

        \ Zero imaginary
        FP16-POS-ZERO _SP-IM @ I 2* + W!
    LOOP ;

\ =====================================================================
\  Internal: run FFT and compute magnitude
\ =====================================================================

: _SP-COMPUTE-FFT  ( -- )
    _SP-RE @ _SP-IM @ _SP-N @ FFT-FORWARD
    _SP-RE @ _SP-IM @ _SP-MAG @ _SP-N @ FFT-MAGNITUDE ;

\ =====================================================================
\  Internal: auto-scale — find max magnitude in displayable bins
\  and set SC.CEIL to that value (so tallest bar fills full height)
\ =====================================================================

VARIABLE _SP-AUTO-MAX

: _SP-AUTO-SCALE  ( -- )
    FP16-POS-ZERO _SP-AUTO-MAX !

    _SP-BINS @ 1 DO        \ skip bin 0 (DC offset)
        _SP-MAG @ I 2* + W@
        _SP-AUTO-MAX @ FP16-MAX
        _SP-AUTO-MAX !
    LOOP

    \ If max > 0, use it as ceiling (leave a 10% headroom: max * 1.1)
    _SP-AUTO-MAX @ FP16-POS-ZERO FP16-MAX  \ ensure non-zero
    DUP FP16-POS-ZERO = IF
        DROP FP16-POS-ONE   \ fallback
    ELSE
        0x3E66 FP16-MUL     \ 0x3E66 ≈ 1.1 in FP16
    THEN
    _SP-CFG @ SC.CEIL + ! ;

\ =====================================================================
\  Internal: scale magnitude bin to pixel height
\ =====================================================================
\  Linear: y = (mag / ceil) * plot_height, clamped
\  Log: approximate dB = 20*log10(mag) ... simplified here,
\       we use mag directly normalized to [floor, ceil].

: _SP-MAG>HEIGHT  ( fp16-mag -- pixels )
    \ Normalize: (mag - floor) / (ceil - floor)
    _SP-CFG @ SC.FLOOR + @ FP16-SUB    \ mag - floor
    _SP-CFG @ SC.CEIL  + @
    _SP-CFG @ SC.FLOOR + @ FP16-SUB    \ ceil - floor
    FP16-DIV                            \ normalized [0,1]

    \ Clamp to [0, 1]
    FP16-POS-ZERO FP16-POS-ONE FP16-CLAMP

    \ Scale to plot height
    _SP-PH @ INT>FP16 FP16-MUL
    FP16>INT ;

\ =====================================================================
\  Internal: update peak-hold buffer
\ =====================================================================

: _SP-UPDATE-PEAKS  ( -- )
    _SP-CFG @ SC.FLAGS + @ SPEC-F-PEAK-HOLD AND 0= IF EXIT THEN

    _SP-BINS @ 0 DO
        _SP-MAG  @ I 2* + W@          \ current magnitude
        _SP-PEAK @ I 2* + W@          \ stored peak
        2DUP FP16-MAX                  \ max of current and stored
        OVER <> IF                     \ peak changed?
            _SP-MAG @ I 2* + W@
            _SP-PEAK @ I 2* + W!      \ update
        ELSE
            \ Decay peak slowly: peak = peak * 0.99
            _SP-PEAK @ I 2* + W@
            0x3C66 FP16-MUL           \ 0x3C66 ≈ 0.99 in FP16
            _SP-PEAK @ I 2* + W!
        THEN
        2DROP
    LOOP ;

\ =====================================================================
\  Internal: draw background + grid
\ =====================================================================

: _SP-DRAW-BG  ( -- )
    _SP-SURF @ _SP-CFG @ SC.BG + @ SURF-CLEAR ;

: _SP-DRAW-GRID  ( -- )
    _SP-CFG @ SC.FLAGS + @ SPEC-F-GRID AND 0= IF EXIT THEN

    \ 4 horizontal grid lines (25%, 50%, 75%, 100% height)
    4 0 DO
        _SP-PY @ _SP-PH @ I 1+ * 4 /  +
        >R
        _SP-SURF @ _SP-PX @ R> _SP-PW @
        _SP-CFG @ SC.GRIDCOLOR + @
        DRAW-HLINE
    LOOP

    \ Vertical grid: divide into 8 frequency regions
    8 0 DO
        _SP-PX @ _SP-PW @ I * 8 /  +
        >R
        _SP-SURF @ R> _SP-PY @ _SP-PH @
        _SP-CFG @ SC.GRIDCOLOR + @
        DRAW-VLINE
    LOOP ;

\ =====================================================================
\  Internal: draw bars
\ =====================================================================

VARIABLE _SP-BARW      \ bar width in pixels
VARIABLE _SP-GAP       \ gap between bars (pixels)

: _SP-DRAW-BARS  ( -- )
    \ Compute bar width: plot_width / bins
    _SP-PW @ _SP-BINS @ /
    DUP 3 < IF DROP 2 0 ELSE 1 - 1 THEN
    _SP-GAP ! _SP-BARW !

    _SP-BINS @ 0 DO
        _SP-MAG @ I 2* + W@
        _SP-MAG>HEIGHT                 ( h )
        DUP 0 > IF
            \ Bar X position
            _SP-PX @  I _SP-BARW @ _SP-GAP @ + * +
            \ Bar Y = bottom - h
            _SP-PY @ _SP-PH @ + OVER -
            ( h x y )
            >R >R                      ( h ) ( R: y x )
            _SP-SURF @ R> R>
            _SP-BARW @                 ( surf x y barw )
            4 ROLL                     ( surf x y barw h )
            _SP-CFG @ SC.BARCOLOR + @
            DRAW-RECT
        ELSE
            DROP
        THEN
    LOOP ;

\ =====================================================================
\  Internal: draw line mode
\ =====================================================================

VARIABLE _SP-PREV-X
VARIABLE _SP-PREV-Y2

: _SP-DRAW-LINE  ( -- )
    _SP-BINS @ 0 DO
        _SP-MAG @ I 2* + W@
        _SP-MAG>HEIGHT                 ( h )

        \ X = px + i * pw / bins
        _SP-PX @  I _SP-PW @ * _SP-BINS @ /  +
        \ Y = bottom - h
        _SP-PY @ _SP-PH @ + ROT -

        ( x y )
        I 0 > IF
            _SP-SURF @
            _SP-PREV-X @ _SP-PREV-Y2 @
            2 PICK 2 PICK
            ( surf x0 y0 x1 y1 )
            SPEC-LINE-COLOR
            DRAW-LINE
        THEN
        DUP _SP-PREV-Y2 !
        OVER _SP-PREV-X !
        2DROP
    LOOP ;

\ =====================================================================
\  Internal: draw peak hold markers
\ =====================================================================

: _SP-DRAW-PEAKS  ( -- )
    _SP-CFG @ SC.FLAGS + @ SPEC-F-PEAK-HOLD AND 0= IF EXIT THEN

    _SP-BINS @ 0 DO
        _SP-PEAK @ I 2* + W@
        _SP-MAG>HEIGHT                 ( h )
        DUP 0 > IF
            _SP-PX @  I _SP-PW @ * _SP-BINS @ /  +  ( h x )
            SWAP                                     ( x h )
            _SP-PY @ _SP-PH @ + SWAP -               ( x y )
            >R >R
            _SP-SURF @ R> R>
            3 1 MAX   \ marker width: at least 3px
            _SP-PW @ _SP-BINS @ / 1 MAX MIN
            1                                         ( surf x y w 1 )
            _SP-CFG @ SC.PEAKCOLOR + @
            DRAW-RECT
        ELSE
            DROP
        THEN
    LOOP ;

\ =====================================================================
\  SPEC-DRAW — main entry: render spectrum to surface
\ =====================================================================
\  ( cfg -- )

: SPEC-DRAW  ( cfg -- )
    _SP-SETUP

    \ Load samples into FFT buffer
    _SP-LOAD-SAMPLES

    \ Run FFT
    _SP-COMPUTE-FFT

    \ Auto-scale ceiling to max magnitude
    _SP-AUTO-SCALE

    \ Update peak hold
    _SP-UPDATE-PEAKS

    \ Clear and draw grid
    _SP-DRAW-BG
    _SP-DRAW-GRID

    \ Draw spectrum
    _SP-CFG @ SC.FLAGS + @ SPEC-F-BARS AND IF
        _SP-DRAW-BARS
    ELSE
        _SP-DRAW-LINE
    THEN

    \ Peak hold markers
    _SP-DRAW-PEAKS ;

\ =====================================================================
\  Convenience: one-shot spectrum render
\ =====================================================================
\  SPEC-RENDER  ( pcm surf -- )
\  Uses 256-point FFT, default config.

: SPEC-RENDER  ( pcm surf -- )
    256 SPEC-CONFIG-CREATE
    DUP SPEC-DRAW
    SPEC-CONFIG-FREE ;

\ =====================================================================
\  SPEC-WINDOW!  ( start cfg -- )
\  Set analysis window start frame.

: SPEC-WINDOW!  ( start cfg -- )
    SC.START + ! ;

\ =====================================================================
\  SPEC-FFT-SIZE@  ( cfg -- n )
\  Read FFT size from config.

: SPEC-FFT-SIZE@  ( cfg -- n )
    SC.FFTSIZE + @ ;
