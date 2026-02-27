\ paint.f — Render tree painter for Akashic render pipeline
\ Part of Akashic render library for Megapad-64 / KDOS
\
\ Walks a laid-out box tree and paints to a surface following CSS 2.1
\ Appendix E painting order:
\   1. Background colour
\   2. Background image (future)
\   3. Borders
\   4. Block children (recurse)
\   5. Inline / text content
\   6. Outline (future)
\
\ CSS properties consumed:
\   background-color   — named, #RGB, #RRGGBB → packed RGBA
\   border-color       — shorthand or per-side → packed RGBA
\   border-style       — "solid" only for now (skip if "none"/missing)
\   color              — text foreground → packed RGBA
\   font-size          — integer px (default 16)
\
\ Prefix: PAINT-  (public API)
\         _PNT-   (internal helpers)
\
\ Load with:   REQUIRE render/paint.f
\
\ Dependencies:
\   akashic-box              — box tree, rect queries, style accessors
\   akashic-surface          — SURF-FILL-RECT
\   akashic-draw             — DRAW-RECT, DRAW-TEXT
\   akashic-layout-engine    — layout pass (must be done before paint)
\   akashic-css              — CSS-PARSE-HEX-COLOR, CSS-COLOR-FIND
\   akashic-dom              — DOM-STYLE@, DOM-TEXT
\
\ === Public API ===
\   PAINT-RENDER     ( box-root surf -- )   Paint entire box tree
\   PAINT-BOX        ( box surf -- )        Paint one box (bg + border)
\   PAINT-BG-COLOR   ( box surf -- )        Fill padding rect with bg
\   PAINT-BORDERS    ( box surf -- )        Draw four border edges
\   PAINT-TEXT       ( box surf -- )        Render text content
\   PAINT-CSS-COLOR  ( val-a val-u -- rgba flag )  Parse CSS color value

REQUIRE box.f
REQUIRE surface.f
REQUIRE draw.f
REQUIRE layout.f

PROVIDED akashic-paint

\ =====================================================================
\  Internal variables
\ =====================================================================

VARIABLE _PNT-BOX       \ current box being painted
VARIABLE _PNT-SURF      \ target surface
VARIABLE _PNT-R         \ temp red
VARIABLE _PNT-G         \ temp green
VARIABLE _PNT-B         \ temp blue

\ Rectangle scratch (from BOX-*-RECT)
VARIABLE _PNT-RX        \ rect x
VARIABLE _PNT-RY        \ rect y
VARIABLE _PNT-RW        \ rect w
VARIABLE _PNT-RH        \ rect h

\ Color scratch
VARIABLE _PNT-RGBA      \ packed colour

\ =====================================================================
\  PAINT-CSS-COLOR  ( val-a val-u -- rgba flag )
\ =====================================================================
\  Parse a CSS colour value string into a packed RGBA word.
\  Handles:
\    - #RGB / #RRGGBB hex colours
\    - CSS named colours (via CSS-COLOR-FIND)
\    - "transparent" → 0x00000000
\  Returns rgba and flag (-1 = success, 0 = parse failed).

: PAINT-CSS-COLOR  ( val-a val-u -- rgba flag )
    \ Empty string → fail
    DUP 0= IF 2DROP 0 0 EXIT THEN

    \ Check for "transparent"
    2DUP S" transparent" STR-STRI= IF
        2DROP 0 -1 EXIT
    THEN

    \ Try hex colour: starts with '#'
    OVER C@ 35 = IF         \ '#'
        CSS-PARSE-HEX-COLOR  ( a' u' r g b flag )
        IF
            \ Pack RGB → RGBA (fully opaque: alpha=255)
            _PNT-B !  _PNT-G !  _PNT-R !
            2DROP       \ drop remaining cursor
            _PNT-R @ 24 LSHIFT
            _PNT-G @ 16 LSHIFT OR
            _PNT-B @  8 LSHIFT OR
            255 OR      \ alpha = 0xFF
            -1 EXIT
        ELSE
            \ hex parse failed — drop r g b
            2DROP DROP
            2DROP       \ drop cursor
            0 0 EXIT
        THEN
    THEN

    \ Try named colour
    CSS-COLOR-FIND  ( r g b flag )
    IF
        _PNT-B !  _PNT-G !  _PNT-R !
        _PNT-R @ 24 LSHIFT
        _PNT-G @ 16 LSHIFT OR
        _PNT-B @  8 LSHIFT OR
        255 OR
        -1
    ELSE
        2DROP DROP   \ drop r(0) g(0) b(0)
        0 0
    THEN
;

\ =====================================================================
\  _PNT-GET-COLOR  ( box prop-a prop-u default -- rgba )
\ =====================================================================
\  Look up a CSS colour property on a box's DOM node.
\  If property not found or unparseable, return default.

VARIABLE _PGC-DEF

: _PNT-GET-COLOR  ( box prop-a prop-u default -- rgba )
    _PGC-DEF !
    ROT B.DOM @ -ROT DOM-STYLE@    ( val-a val-u flag )
    IF
        PAINT-CSS-COLOR            ( rgba flag )
        IF EXIT THEN
        DROP                       \ drop 0 from failed parse
    ELSE
        2DROP                      \ drop val-a val-u (both 0)
    THEN
    _PGC-DEF @ ;

\ =====================================================================
\  _PNT-GET-FONT-SIZE  ( box -- size )
\ =====================================================================
\  Read font-size from box's DOM node. Default 16.

: _PNT-GET-FONT-SIZE  ( box -- size )
    B.DOM @ S" font-size" DOM-STYLE@
    IF
        \ Parse integer value — look for digits
        0 >R
        BEGIN
            DUP 0> WHILE
            OVER C@                       ( addr u c )
            DUP 48 >= OVER 57 <= AND IF   ( addr u c  -- digit char )
                48 -  R> 10 * + >R
            ELSE
                DROP
            THEN
            1 /STRING
        REPEAT
        2DROP R>
        DUP 0= IF DROP 16 THEN     \ fallback
    ELSE
        2DROP 16
    THEN
;

\ =====================================================================
\  PAINT-BG-COLOR  ( box surf -- )
\ =====================================================================
\  Fill the padding rectangle of a box with its background-color.
\  If no background-color or "transparent", does nothing.

: PAINT-BG-COLOR  ( box surf -- )
    _PNT-SURF !  _PNT-BOX !

    \ Look up background-color
    _PNT-BOX @  S" background-color"  0  _PNT-GET-COLOR
    DUP 0= IF DROP EXIT THEN       \ transparent or not found
    _PNT-RGBA !

    \ Get padding rectangle
    _PNT-BOX @ BOX-PADDING-RECT    ( x y w h )
    _PNT-RH !  _PNT-RW !  _PNT-RY !  _PNT-RX !

    \ Skip zero-area boxes
    _PNT-RW @ 1 < IF EXIT THEN
    _PNT-RH @ 1 < IF EXIT THEN

    \ Fill
    _PNT-SURF @
    _PNT-RX @  _PNT-RY @  _PNT-RW @  _PNT-RH @
    _PNT-RGBA @
    SURF-FILL-RECT ;

\ =====================================================================
\  _PNT-BORDER-COLOR  ( box side-prop-a side-prop-u -- rgba )
\ =====================================================================
\  Get border color for a specific side.  Falls back to
\  "border-color" shorthand, then to foreground "color", then black.

VARIABLE _PBC-BOX

: _PNT-BORDER-COLOR  ( box side-prop-a side-prop-u -- rgba )
    ROT DUP _PBC-BOX !
    -ROT
    \ Try side-specific: border-top-color etc.
    0xFF000000 _PNT-GET-COLOR     ( rgba — from side prop or default )
    DUP 0xFF000000 <> IF EXIT THEN
    DROP

    \ Try shorthand "border-color"
    _PBC-BOX @  S" border-color"  0xFF000000  _PNT-GET-COLOR
    DUP 0xFF000000 <> IF EXIT THEN
    DROP

    \ Fall back to "color" (foreground)
    _PBC-BOX @  S" color"  0x000000FF  _PNT-GET-COLOR ;

\ =====================================================================
\  _PNT-HAS-BORDER-STYLE?  ( box -- flag )
\ =====================================================================
\  Check if the box has border-style set to something other than "none".
\  For now we support "solid" only.

: _PNT-HAS-BORDER-STYLE?  ( box -- flag )
    B.DOM @ S" border-style" DOM-STYLE@
    IF
        \ Check for "solid"
        S" solid" STR-STRI=
    ELSE
        2DROP 0
    THEN ;

\ =====================================================================
\  PAINT-BORDERS  ( box surf -- )
\ =====================================================================
\  Draw the four border edges of a box as filled rectangles.
\  Only draws if border-style is present (solid) and border-width > 0.

VARIABLE _PBD-BT   VARIABLE _PBD-BR
VARIABLE _PBD-BB   VARIABLE _PBD-BL

: PAINT-BORDERS  ( box surf -- )
    _PNT-SURF !  _PNT-BOX !

    \ Check border-style
    _PNT-BOX @ _PNT-HAS-BORDER-STYLE? 0= IF EXIT THEN

    \ Read border widths
    _PNT-BOX @ BOX-BORDER-T  _PBD-BT !
    _PNT-BOX @ BOX-BORDER-R  _PBD-BR !
    _PNT-BOX @ BOX-BORDER-B  _PBD-BB !
    _PNT-BOX @ BOX-BORDER-L  _PBD-BL !

    \ All zero → nothing to draw
    _PBD-BT @ _PBD-BR @ OR _PBD-BB @ OR _PBD-BL @ OR
    0= IF EXIT THEN

    \ Get border-rect coordinates
    _PNT-BOX @ BOX-BORDER-RECT
    _PNT-RH !  _PNT-RW !  _PNT-RY !  _PNT-RX !

    \ --- Top border ---
    _PBD-BT @ 0> IF
        _PNT-BOX @ S" border-top-color" _PNT-BORDER-COLOR
        _PNT-RGBA !
        _PNT-SURF @
        _PNT-RX @  _PNT-RY @
        _PNT-RW @  _PBD-BT @
        _PNT-RGBA @
        SURF-FILL-RECT
    THEN

    \ --- Bottom border ---
    _PBD-BB @ 0> IF
        _PNT-BOX @ S" border-bottom-color" _PNT-BORDER-COLOR
        _PNT-RGBA !
        _PNT-SURF @
        _PNT-RX @
        _PNT-RY @ _PNT-RH @ + _PBD-BB @ -
        _PNT-RW @  _PBD-BB @
        _PNT-RGBA @
        SURF-FILL-RECT
    THEN

    \ --- Left border ---
    _PBD-BL @ 0> IF
        _PNT-BOX @ S" border-left-color" _PNT-BORDER-COLOR
        _PNT-RGBA !
        _PNT-SURF @
        _PNT-RX @
        _PNT-RY @ _PBD-BT @ +
        _PBD-BL @
        _PNT-RH @ _PBD-BT @ - _PBD-BB @ -
        _PNT-RGBA @
        SURF-FILL-RECT
    THEN

    \ --- Right border ---
    _PBD-BR @ 0> IF
        _PNT-BOX @ S" border-right-color" _PNT-BORDER-COLOR
        _PNT-RGBA !
        _PNT-SURF @
        _PNT-RX @ _PNT-RW @ + _PBD-BR @ -
        _PNT-RY @ _PBD-BT @ +
        _PBD-BR @
        _PNT-RH @ _PBD-BT @ - _PBD-BB @ -
        _PNT-RGBA @
        SURF-FILL-RECT
    THEN ;

\ =====================================================================
\  PAINT-TEXT  ( box surf -- )
\ =====================================================================
\  Render the text content of a text-flagged box.
\  Uses DRAW-TEXT ( surf addr len x y size rgba -- ).
\
\  If the text box has word-split fragments (B.FRAGS != 0), each
\  word is drawn at its individually computed position.
\  Otherwise, the full text is drawn at the box content origin.
\
\  Foreground colour from CSS "color" property, default black.
\  Font size from CSS "font-size" property, default 16.

VARIABLE _PTX-RGBA
VARIABLE _PTX-SIZE
VARIABLE _PTX-FP     \ fragment array pointer
VARIABLE _PTX-FN     \ fragment count
VARIABLE _PTX-FE     \ fragment entry pointer
VARIABLE _PTX-FI     \ fragment index

: PAINT-TEXT  ( box surf -- )
    _PNT-SURF !  _PNT-BOX !

    \ Must be a text box
    _PNT-BOX @ B.FLAGS @ _BOX-F-TEXT AND 0= IF EXIT THEN

    \ Get foreground colour and font size (common for all fragments)
    _PNT-BOX @  S" color"  0x000000FF  _PNT-GET-COLOR
    _PTX-RGBA !
    _PNT-BOX @ _PNT-GET-FONT-SIZE  _PTX-SIZE !

    \ Check for word-split fragments
    _PNT-BOX @ B.FRAGS @ DUP 0<> IF
        \ Has fragments — draw each word at its computed position
        _PTX-FP !
        _PTX-FP @ @ _PTX-FN !
        0 _PTX-FI !
        BEGIN _PTX-FI @ _PTX-FN @ < WHILE
            _PTX-FI @ 4 * 1+ CELLS _PTX-FP @ + _PTX-FE !
            _PNT-SURF @
            _PTX-FE @ 16 + @              \ addr
            _PTX-FE @ 24 + @              \ len
            _PTX-FE @ @                   \ x
            _PTX-FE @ 8 + @              \ y
            _PTX-SIZE @
            _PTX-RGBA @
            DRAW-TEXT
            _PTX-FI @ 1+ _PTX-FI !
        REPEAT
    ELSE
        DROP
        \ No fragments — draw full text at box position (classic path)
        _PNT-BOX @ B.DOM @ DOM-TEXT   ( txt-a txt-u )
        DUP 0= IF 2DROP EXIT THEN
        _PNT-SURF @
        -ROT                          ( surf txt-a txt-u )
        _PNT-BOX @ BOX-X             ( surf txt-a txt-u x )
        _PNT-BOX @ BOX-Y             ( surf txt-a txt-u x y )
        _PTX-SIZE @                   ( surf txt-a txt-u x y size )
        _PTX-RGBA @                   ( surf txt-a txt-u x y size rgba )
        DRAW-TEXT
    THEN ;

\ =====================================================================
\  PAINT-BOX  ( box surf -- )
\ =====================================================================
\  Paint a single (non-text) box: background then borders.

: PAINT-BOX  ( box surf -- )
    2DUP PAINT-BG-COLOR
    PAINT-BORDERS ;

\ =====================================================================
\  PAINT-RENDER  ( box-root surf -- )
\ =====================================================================
\  Walk the box tree in CSS painting order and render to surface.
\
\  For each box (depth-first):
\    1. Paint background + borders (PAINT-BOX)
\    2. Recurse into block children
\    3. Paint text content (PAINT-TEXT)
\
\  Uses return stack for recursive save/restore of _PNT-BOX / _PNT-SURF.

VARIABLE _PR-BOX
VARIABLE _PR-SURF
VARIABLE _PR-CHILD

: PAINT-RENDER  ( box-root surf -- )
    _PR-SURF !  _PR-BOX !

    \ Skip display:none
    _PR-BOX @ BOX-DISPLAY BOX-D-NONE = IF EXIT THEN

    \ 1. Paint this box's background and borders (not for text boxes)
    _PR-BOX @ B.FLAGS @ _BOX-F-TEXT AND 0= IF
        _PR-BOX @ _PR-SURF @ PAINT-BOX
    THEN

    \ 2. Paint text content (only for text boxes)
    _PR-BOX @ B.FLAGS @ _BOX-F-TEXT AND IF
        _PR-BOX @ _PR-SURF @ PAINT-TEXT
        EXIT       \ text boxes have no children
    THEN

    \ 3. Recurse into children
    _PR-BOX @ BOX-FIRST-CHILD _PR-CHILD !
    BEGIN
        _PR-CHILD @ 0<> WHILE
        \ Save state on return stack
        _PR-BOX @   >R
        _PR-SURF @  >R
        _PR-CHILD @ >R

        _PR-CHILD @ _PR-SURF @ PAINT-RENDER

        \ Restore state
        R> _PR-CHILD !
        R> _PR-SURF !
        R> _PR-BOX !

        _PR-CHILD @ BOX-NEXT _PR-CHILD !
    REPEAT ;
