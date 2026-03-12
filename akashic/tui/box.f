\ =====================================================================
\  akashic/tui/box.f — Box Drawing & Borders
\ =====================================================================
\
\  Draw rectangular borders and frames using Unicode box-drawing
\  characters.  Multiple border styles (single, double, rounded,
\  heavy, ASCII).  Composable with draw.f — boxes are drawn into
\  the same back buffer via the current screen.
\
\  Each style is a descriptor containing 8 codepoints stored in
\  a flat cell array.
\
\  Prefix: BOX- (public), _BOX- (internal)
\  Provider: akashic-tui-box
\  Dependencies: draw.f

PROVIDED akashic-tui-box

REQUIRE draw.f

\ =====================================================================
\ 1. Style descriptor offsets (8 codepoints × 8 bytes each = 64 bytes)
\ =====================================================================
\
\   +0   top-left      ┌ / ╔ / ╭ / ┏ / +
\   +8   top-right     ┐ / ╗ / ╮ / ┓ / +
\  +16   bot-left      └ / ╚ / ╰ / ┗ / +
\  +24   bot-right     ┘ / ╝ / ╯ / ┛ / +
\  +32   horizontal    ─ / ═ / ─ / ━ / -
\  +40   vertical      │ / ║ / │ / ┃ / |
\  +48   t-left        ├ / ╠ / ├ / ┣ / +
\  +56   t-right       ┤ / ╣ / ┤ / ┫ / +

 0 CONSTANT _BOX-O-TL
 8 CONSTANT _BOX-O-TR
16 CONSTANT _BOX-O-BL
24 CONSTANT _BOX-O-BR
32 CONSTANT _BOX-O-HORIZ
40 CONSTANT _BOX-O-VERT
48 CONSTANT _BOX-O-TLEFT
56 CONSTANT _BOX-O-TRIGHT

\ =====================================================================
\ 2. Pre-defined styles
\ =====================================================================

\ Helper to create a style descriptor in dictionary
: _BOX-STYLE  ( tl tr bl br h v tleft tright -- )
    CREATE
        >R >R >R >R >R >R >R
        \ Stack: tl   R: tright tleft v h br bl tr
        ,                              \ +0  tl
        R> ,                           \ +8  tr
        R> ,                           \ +16 bl
        R> ,                           \ +24 br
        R> ,                           \ +32 h
        R> ,                           \ +40 v
        R> ,                           \ +48 tleft
        R> ,                           \ +56 tright
    DOES> ;

\ Single line: ┌─┐│└─┘  (├┤ for T-pieces)
HEX
250C 2510 2514 2518 2500 2502 251C 2524 _BOX-STYLE BOX-SINGLE

\ Double line: ╔═╗║╚═╝  (╠╣ for T-pieces)
2554 2557 255A 255D 2550 2551 2560 2563 _BOX-STYLE BOX-DOUBLE

\ Rounded: ╭─╮│╰─╯  (├┤ for T-pieces)
256D 256E 2570 256F 2500 2502 251C 2524 _BOX-STYLE BOX-ROUND

\ Heavy: ┏━┓┃┗━┛  (┣┫ for T-pieces)
250F 2513 2517 251B 2501 2503 2523 252B _BOX-STYLE BOX-HEAVY
DECIMAL

\ ASCII fallback: +-+|+-+
43 43 43 43 45 124 43 43 _BOX-STYLE BOX-ASCII

\ =====================================================================
\ 3. Style accessor helpers
\ =====================================================================

\ _BOX-@ ( style offset -- cp )  Fetch codepoint from style descriptor.
: _BOX-@  ( style offset -- cp )
    + @ ;

\ =====================================================================
\ 4. Drawing words
\ =====================================================================

VARIABLE _BOX-STYLE-ADDR
VARIABLE _BOX-ROW
VARIABLE _BOX-COL
VARIABLE _BOX-H
VARIABLE _BOX-W

\ BOX-DRAW ( style row col h w -- )
\   Draw a border rectangle.
\   Minimum useful size: h=2 w=2 (just corners, no interior).
: BOX-DRAW  ( style row col h w -- )
    _BOX-W !
    _BOX-H !
    _BOX-COL !
    _BOX-ROW !
    _BOX-STYLE-ADDR !

    \ Top-left corner
    _BOX-STYLE-ADDR @ _BOX-O-TL _BOX-@
    _BOX-ROW @ _BOX-COL @
    DRW-CHAR

    \ Top-right corner
    _BOX-STYLE-ADDR @ _BOX-O-TR _BOX-@
    _BOX-ROW @ _BOX-COL @ _BOX-W @ + 1-
    DRW-CHAR

    \ Bottom-left corner
    _BOX-STYLE-ADDR @ _BOX-O-BL _BOX-@
    _BOX-ROW @ _BOX-H @ + 1-
    _BOX-COL @
    DRW-CHAR

    \ Bottom-right corner
    _BOX-STYLE-ADDR @ _BOX-O-BR _BOX-@
    _BOX-ROW @ _BOX-H @ + 1-
    _BOX-COL @ _BOX-W @ + 1-
    DRW-CHAR

    \ Top horizontal edge (between corners)
    _BOX-W @ 2 > IF
        _BOX-STYLE-ADDR @ _BOX-O-HORIZ _BOX-@
        _BOX-ROW @
        _BOX-COL @ 1+
        _BOX-W @ 2 -
        DRW-HLINE
    THEN

    \ Bottom horizontal edge (between corners)
    _BOX-W @ 2 > IF
        _BOX-STYLE-ADDR @ _BOX-O-HORIZ _BOX-@
        _BOX-ROW @ _BOX-H @ + 1-
        _BOX-COL @ 1+
        _BOX-W @ 2 -
        DRW-HLINE
    THEN

    \ Left vertical edge (between corners)
    _BOX-H @ 2 > IF
        _BOX-STYLE-ADDR @ _BOX-O-VERT _BOX-@
        _BOX-ROW @ 1+
        _BOX-COL @
        _BOX-H @ 2 -
        DRW-VLINE
    THEN

    \ Right vertical edge (between corners)
    _BOX-H @ 2 > IF
        _BOX-STYLE-ADDR @ _BOX-O-VERT _BOX-@
        _BOX-ROW @ 1+
        _BOX-COL @ _BOX-W @ + 1-
        _BOX-H @ 2 -
        DRW-VLINE
    THEN ;

\ BOX-DRAW-TITLED ( style addr len row col h w -- )
\   Draw border + title centered on the top edge.
\   Title is placed starting 2 cols in from the left, truncated if
\   too long for the width.
VARIABLE _BOX-TITLE-A
VARIABLE _BOX-TITLE-L

: BOX-DRAW-TITLED  ( style addr len row col h w -- )
    \ Save title string
    >R >R >R >R                        \ R: w h col row
    _BOX-TITLE-L !
    _BOX-TITLE-A !
    R> R> R> R>                        \ ( style row col h w )

    \ Draw the regular box first
    4 PICK >R                          \ save style again for title
    BOX-DRAW
    R>                                 \ ( style )

    \ Place title text on top edge
    \ Position: row=_BOX-ROW, col=_BOX-COL+2
    \ Max chars: w-4 (leave room for corners + 1 space each side)
    DROP                               \ drop style (we saved row/col/w)

    _BOX-W @ 4 - DUP 0> IF
        _BOX-TITLE-L @ MIN            \ clamp title length
        _BOX-TITLE-A @ SWAP
        _BOX-ROW @
        _BOX-COL @ 2 +
        DRW-TEXT
    ELSE
        DROP                           \ no room for title
    THEN ;

\ BOX-HLINE ( style row col w -- )
\   Draw a horizontal rule using the style's horizontal character.
: BOX-HLINE  ( style row col w -- )
    >R >R >R                           \ R: w col row
    _BOX-O-HORIZ _BOX-@               \ ( horiz-cp )
    R> R> R>                           \ ( cp row col w )
    DRW-HLINE ;

\ BOX-VLINE ( style row col h -- )
\   Draw a vertical rule using the style's vertical character.
: BOX-VLINE  ( style row col h -- )
    >R >R >R                           \ R: h col row
    _BOX-O-VERT _BOX-@                \ ( vert-cp )
    R> R> R>                           \ ( cp row col h )
    DRW-VLINE ;

\ BOX-SHADOW ( row col h w -- )
\   Draw a drop shadow along right edge and bottom edge.
\   Uses dim block character (0x2591 = ░).
\   Shadow is 1 cell wide on the right, 1 cell tall on bottom.
\   Offset by +1 row, +1 col from box bounds.
VARIABLE _BOX-SH-ROW
VARIABLE _BOX-SH-COL
VARIABLE _BOX-SH-H
VARIABLE _BOX-SH-W

: BOX-SHADOW  ( row col h w -- )
    _BOX-SH-W !
    _BOX-SH-H !
    _BOX-SH-COL !
    _BOX-SH-ROW !

    \ Save/set dim style for shadow
    _DRW-FG @ _DRW-BG @ _DRW-ATTRS @
    >R >R >R
    0 DRW-FG!
    0 DRW-BG!
    CELL-A-DIM DRW-ATTR!

    \ Right shadow: vertical line at col+w, from row+1 to row+h
    0x2591                             \ ░
    _BOX-SH-ROW @ 1+
    _BOX-SH-COL @ _BOX-SH-W @ +
    _BOX-SH-H @
    DRW-VLINE

    \ Bottom shadow: horizontal line at row+h, from col+1 to col+w+1
    0x2591                             \ ░
    _BOX-SH-ROW @ _BOX-SH-H @ +
    _BOX-SH-COL @ 1+
    _BOX-SH-W @
    DRW-HLINE

    \ Restore style
    R> _DRW-ATTRS !
    R> _DRW-BG !
    R> _DRW-FG ! ;

\ =====================================================================
\ 5. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _box-guard

' BOX-DRAW            CONSTANT _box-draw-xt
' BOX-DRAW-TITLED     CONSTANT _box-titled-xt
' BOX-HLINE           CONSTANT _box-hline-xt
' BOX-VLINE           CONSTANT _box-vline-xt
' BOX-SHADOW          CONSTANT _box-shadow-xt

: BOX-DRAW            _box-draw-xt    _box-guard WITH-GUARD ;
: BOX-DRAW-TITLED     _box-titled-xt  _box-guard WITH-GUARD ;
: BOX-HLINE           _box-hline-xt   _box-guard WITH-GUARD ;
: BOX-VLINE           _box-vline-xt   _box-guard WITH-GUARD ;
: BOX-SHADOW          _box-shadow-xt  _box-guard WITH-GUARD ;
[THEN] [THEN]
