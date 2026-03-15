\ color.f — RGB → xterm-256 Palette Color Resolution
\
\ Shared TUI color utilities: maps 24-bit RGB to the nearest xterm-256
\ palette index.  Used by both dom-tui.f and uidl-tui.f.
\
\ Strategy:
\   1. Try the 6×6×6 color cube (indices 16–231).
\   2. Try the 24-step grayscale ramp (indices 232–255).
\   3. Return whichever has the smallest Euclidean distance².
\
\ Public words:
\   TUI-RESOLVE-COLOR   ( r g b -- index )
\   TUI-PARSE-COLOR     ( val-a val-u -- index found? )
\
\ Prefix: TUI-  (public)
\         _TC-  (internal)
\
\ Load with:   REQUIRE color.f

PROVIDED akashic-tui-color

REQUIRE ../css/css.f
REQUIRE ../utils/string.f

\ =====================================================================
\  §1 — RGB → 256-Palette Resolution
\ =====================================================================

\ -- 6×6×6 cube quantiser --
\ Cube levels: 0, 95, 135, 175, 215, 255.

CREATE _TC-CUBE-LEVELS  0 C, 95 C, 135 C, 175 C, 215 C, 255 C,

VARIABLE _TC-R   VARIABLE _TC-G   VARIABLE _TC-B
VARIABLE _TC-BEST-IDX   VARIABLE _TC-BEST-DIST

\ _TC-CUBE-SNAP ( component -- level index )
\   Snap one 0-255 component to nearest cube level.
VARIABLE _TCS-V   VARIABLE _TCS-BEST   VARIABLE _TCS-BD

: _TC-CUBE-SNAP  ( component -- level index )
    _TCS-V !  0 _TCS-BEST !  999 _TCS-BD !
    6 0 DO
        _TC-CUBE-LEVELS I + C@
        _TCS-V @ -  DUP *          \ distance²
        DUP _TCS-BD @ < IF
            _TCS-BD !
            I _TCS-BEST !
        ELSE DROP THEN
    LOOP
    _TC-CUBE-LEVELS _TCS-BEST @ + C@  _TCS-BEST @ ;

VARIABLE _TCC-RI   VARIABLE _TCC-GI   VARIABLE _TCC-BI
VARIABLE _TCC-RL   VARIABLE _TCC-GL   VARIABLE _TCC-BL

\ _TC-CUBE-DIST ( r g b -- dist index )
\   Compute distance² and palette index for best cube match.
: _TC-CUBE-DIST  ( r g b -- dist index )
    _TC-CUBE-SNAP _TCC-BI !  _TCC-BL !
    _TC-CUBE-SNAP _TCC-GI !  _TCC-GL !
    _TC-CUBE-SNAP _TCC-RI !  _TCC-RL !
    \ distance²
    _TC-R @ _TCC-RL @ -  DUP *
    _TC-G @ _TCC-GL @ -  DUP *  +
    _TC-B @ _TCC-BL @ -  DUP *  +
    \ index = 16 + 36*ri + 6*gi + bi
    16  _TCC-RI @ 36 * +  _TCC-GI @ 6 * +  _TCC-BI @ + ;

\ _TC-GRAY-DIST ( r g b -- dist index )
\   Find nearest grayscale ramp entry (232–255).
\   Ramp: index i → gray = 8 + 10*i, i=0..23.
VARIABLE _TGD-AVG   VARIABLE _TGD-BEST   VARIABLE _TGD-BD

: _TC-GRAY-DIST  ( r g b -- dist index )
    + + 3 /  _TGD-AVG !           \ average → target gray
    0 _TGD-BEST !  999999 _TGD-BD !
    24 0 DO
        I 10 * 8 +                \ gray level for index 232+i
        _TGD-AVG @ -  DUP *       \ distance² from avg
        DUP _TGD-BD @ < IF
            _TGD-BD !  I _TGD-BEST !
        ELSE DROP THEN
    LOOP
    \ Actual distance² from R,G,B to uniform gray
    _TGD-BEST @ 10 * 8 +          \ chosen gray level
    DUP _TC-R @ -  DUP *
    OVER _TC-G @ -  DUP *  +
    SWAP _TC-B @ -  DUP *  +
    _TGD-BEST @ 232 + ;

\ TUI-RESOLVE-COLOR ( r g b -- index )
\   Map 24-bit RGB → nearest xterm-256 palette index.
: TUI-RESOLVE-COLOR  ( r g b -- index )
    _TC-B !  _TC-G !  _TC-R !
    \ Try cube
    _TC-R @ _TC-G @ _TC-B @  _TC-CUBE-DIST
    _TC-BEST-IDX !  _TC-BEST-DIST !
    \ Try grayscale
    _TC-R @ _TC-G @ _TC-B @  _TC-GRAY-DIST
    \ ( gray-dist gray-idx ) — compare
    SWAP  _TC-BEST-DIST @ <= IF    \ gray closer
        \ return gray-idx
    ELSE
        DROP  _TC-BEST-IDX @       \ cube closer
    THEN ;

\ =====================================================================
\  §2 — CSS Color String → Palette Index
\ =====================================================================

VARIABLE _TPC-R   VARIABLE _TPC-G   VARIABLE _TPC-B
VARIABLE _TPC-VA  VARIABLE _TPC-VU  \ saved input for integer fallback

\ TUI-PARSE-COLOR ( val-a val-u -- index found? )
\   Parse CSS color value → palette index.
\   Supported formats:
\     #RGB / #RRGGBB        (hex)
\     Named CSS colors      (red, blue, ...)
\     Raw integer 0-255     (palette index)
: TUI-PARSE-COLOR  ( val-a val-u -- index found? )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    2DUP _TPC-VU ! _TPC-VA !           \ save for integer fallback
    OVER C@ [CHAR] # = IF
        \ Starts with # — try hex parse
        2DUP CSS-PARSE-HEX-COLOR IF     \ ( o-a o-u a' u' r g b )
            _TPC-B !  _TPC-G !  _TPC-R !
            2DROP 2DROP                  \ drop a' u' AND 2DUP copies
            _TPC-R @ _TPC-G @ _TPC-B @  TUI-RESOLVE-COLOR
            -1 EXIT
        THEN
        \ Hex parse failed: ( o-a o-u a' u' 0 0 0 )
        DROP DROP DROP 2DROP            \ clean all 5 residuals
    THEN
    \ Try named color (148 CSS named colors)
    CSS-COLOR-FIND IF                    \ ( r g b )
        _TPC-B !  _TPC-G !  _TPC-R !
        _TPC-R @ _TPC-G @ _TPC-B @  TUI-RESOLVE-COLOR
        -1 EXIT
    THEN
    DROP DROP DROP                       \ clean COLOR-FIND residual (0 0 0)
    \ Try raw integer palette index (0-255)
    _TPC-VA @ _TPC-VU @
    CSS-PARSE-INT IF                     \ ( a' u' n )
        -ROT                             \ ( n a' u' )
        DUP 0= IF                       \ entire string consumed?
            2DROP                        \ ( n )
            DUP 0 >= OVER 255 <= AND IF
                -1 EXIT                  \ ( n -1 ) — success
            THEN
            DROP                         \ n out of range
        ELSE
            2DROP DROP                   \ trailing chars — not an integer
        THEN
    ELSE
        DROP 2DROP                       \ CSS-PARSE-INT failure cleanup
    THEN
    0 0 ;

