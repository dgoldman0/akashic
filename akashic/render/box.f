\ box.f — CSS Box Model for Akashic render pipeline
\ Part of Akashic render library for Megapad-64 / KDOS
\
\ Each DOM element that generates visual output gets a box.  Boxes form
\ a tree that mirrors the DOM tree but excludes display:none elements.
\
\ Box dimensions are integer pixels.  CSS values are parsed from
\ DOM-STYLE@ strings and converted: "10px" → 10, "auto" → -1.
\
\ Currently supported units: px (default), no unit (treated as px).
\ Percentage, em, rem are left for future layout.f to resolve.
\
\ Prefix: BOX-   (public API)
\         _BOX-  (internal helpers)
\
\ Load with:   REQUIRE render/box.f
\
\ Dependencies:
\   akashic-dom       — DOM tree traversal, style lookup
\   akashic-css       — CSS value parsing (CSS-PARSE-NUMBER, CSS-PARSE-UNIT, etc.)
\
\ === Public API ===
\   BOX-CREATE        ( dom-node -- box )      Allocate box for a DOM node
\   BOX-DESTROY       ( box -- )               Return box to free list
\   BOX-BUILD-TREE    ( dom-root -- box-root ) Generate box tree from DOM
\   BOX-CONTENT-RECT  ( box -- x y w h )       Content area rectangle
\   BOX-PADDING-RECT  ( box -- x y w h )       Content + padding
\   BOX-BORDER-RECT   ( box -- x y w h )       Content + padding + border
\   BOX-MARGIN-RECT   ( box -- x y w h )       Full margin box
\   BOX-RESOLVE-STYLE ( box -- )               Read styles → box fields
\   BOX-DISPLAY       ( box -- display )       Display type
\   BOX-DOM           ( box -- node )          DOM node back-pointer
\   BOX-FREE-TREE     ( box -- )               Free entire box tree
\
\   Accessors:
\   BOX-X / BOX-Y / BOX-W / BOX-H
\   BOX-PARENT / BOX-FIRST-CHILD / BOX-NEXT
\   BOX-MARGIN-T / BOX-MARGIN-R / BOX-MARGIN-B / BOX-MARGIN-L
\   BOX-PADDING-T / BOX-PADDING-R / BOX-PADDING-B / BOX-PADDING-L
\   BOX-BORDER-T / BOX-BORDER-R / BOX-BORDER-B / BOX-BORDER-L

REQUIRE ../dom/dom.f

PROVIDED akashic-box

\ =====================================================================
\  Display type constants
\ =====================================================================

0 CONSTANT BOX-D-BLOCK
1 CONSTANT BOX-D-INLINE
2 CONSTANT BOX-D-INLINE-BLOCK
3 CONSTANT BOX-D-NONE

\ Special value for "auto" dimensions
-1 CONSTANT BOX-AUTO

\ =====================================================================
\  Box descriptor layout  (22 cells = 176 bytes)
\ =====================================================================
\
\  +0    dom-node     Back-pointer to DOM node
\  +8    parent       Parent box (or 0)
\  +16   first-child  First child box (or 0)
\  +24   next         Next sibling box (or 0)
\  +32   display      Display type (0=block, 1=inline, 2=inline-block, 3=none)
\  +40   x            Content origin X (integer px)
\  +48   y            Content origin Y (integer px)
\  +56   width        Content width  (integer px, or BOX-AUTO = -1)
\  +64   height       Content height (integer px, or BOX-AUTO = -1)
\  +72   margin-t     Margin top
\  +80   margin-r     Margin right
\  +88   margin-b     Margin bottom
\  +96   margin-l     Margin left
\  +104  padding-t    Padding top
\  +112  padding-r    Padding right
\  +120  padding-b    Padding bottom
\  +128  padding-l    Padding left
\  +136  border-t     Border width top
\  +144  border-r     Border width right
\  +152  border-b     Border width bottom
\  +160  border-l     Border width left
\  +168  flags        Bit 0: 1 = text box (no children, content is text)
\  +176  frags        Pointer to word-fragment array (for word-wrapped text)
\  +184  min-w        min-width   (integer px, 0 = no minimum)
\  +192  max-w        max-width   (integer px, BOX-AUTO = no maximum)
\  +200  min-h        min-height  (integer px, 0 = no minimum)
\  +208  max-h        max-height  (integer px, BOX-AUTO = no maximum)

216 CONSTANT BOX-DESC-SIZE

\ =====================================================================
\  Field accessor words  ( box -- addr )
\ =====================================================================

: B.DOM       ( box -- addr )          ;          \ +0
: B.PARENT    ( box -- addr )  8 + ;              \ +8
: B.CHILD     ( box -- addr )  16 + ;             \ +16
: B.NEXT      ( box -- addr )  24 + ;             \ +24
: B.DISPLAY   ( box -- addr )  32 + ;             \ +32
: B.X         ( box -- addr )  40 + ;             \ +40
: B.Y         ( box -- addr )  48 + ;             \ +48
: B.W         ( box -- addr )  56 + ;             \ +56
: B.H         ( box -- addr )  64 + ;             \ +64
: B.MT        ( box -- addr )  72 + ;             \ +72
: B.MR        ( box -- addr )  80 + ;             \ +80
: B.MB        ( box -- addr )  88 + ;             \ +88
: B.ML        ( box -- addr )  96 + ;             \ +96
: B.PT        ( box -- addr )  104 + ;            \ +104
: B.PR        ( box -- addr )  112 + ;            \ +112
: B.PB        ( box -- addr )  120 + ;            \ +120
: B.PL        ( box -- addr )  128 + ;            \ +128
: B.BT        ( box -- addr )  136 + ;            \ +136
: B.BR        ( box -- addr )  144 + ;            \ +144
: B.BB        ( box -- addr )  152 + ;            \ +152
: B.BL        ( box -- addr )  160 + ;            \ +160
: B.FLAGS     ( box -- addr )  168 + ;            \ +168
: B.FRAGS     ( box -- addr )  176 + ;            \ +176  word fragments
: B.MINW      ( box -- addr )  184 + ;            \ +184  min-width
: B.MAXW      ( box -- addr )  192 + ;            \ +192  max-width
: B.MINH      ( box -- addr )  200 + ;            \ +200  min-height
: B.MAXH      ( box -- addr )  208 + ;            \ +208  max-height

\ Flag bits
1 CONSTANT _BOX-F-TEXT

\ =====================================================================
\  Public accessors  ( box -- value )
\ =====================================================================

: BOX-DOM        ( box -- node )    B.DOM @ ;
: BOX-PARENT     ( box -- box|0 )  B.PARENT @ ;
: BOX-FIRST-CHILD ( box -- box|0 ) B.CHILD @ ;
: BOX-NEXT       ( box -- box|0 )  B.NEXT @ ;
: BOX-DISPLAY    ( box -- disp )   B.DISPLAY @ ;
: BOX-X          ( box -- x )      B.X @ ;
: BOX-Y          ( box -- y )      B.Y @ ;
: BOX-W          ( box -- w )      B.W @ ;
: BOX-H          ( box -- h )      B.H @ ;
: BOX-MARGIN-T   ( box -- n )     B.MT @ ;
: BOX-MARGIN-R   ( box -- n )     B.MR @ ;
: BOX-MARGIN-B   ( box -- n )     B.MB @ ;
: BOX-MARGIN-L   ( box -- n )     B.ML @ ;
: BOX-PADDING-T  ( box -- n )     B.PT @ ;
: BOX-PADDING-R  ( box -- n )     B.PR @ ;
: BOX-PADDING-B  ( box -- n )     B.PB @ ;
: BOX-PADDING-L  ( box -- n )     B.PL @ ;
: BOX-BORDER-T   ( box -- n )     B.BT @ ;
: BOX-BORDER-R   ( box -- n )     B.BR @ ;
: BOX-BORDER-B   ( box -- n )     B.BB @ ;
: BOX-BORDER-L   ( box -- n )     B.BL @ ;
: BOX-FRAGS      ( box -- ptr )   B.FRAGS @ ;
: BOX-MIN-W      ( box -- n )     B.MINW @ ;
: BOX-MAX-W      ( box -- n )     B.MAXW @ ;
: BOX-MIN-H      ( box -- n )     B.MINH @ ;
: BOX-MAX-H      ( box -- n )     B.MAXH @ ;

\ Setters for layout engine
: BOX-X!     ( x box -- )     B.X ! ;
: BOX-Y!     ( y box -- )     B.Y ! ;
: BOX-W!     ( w box -- )     B.W ! ;
: BOX-H!     ( h box -- )     B.H ! ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _BOX-TMP
VARIABLE _BOX-NODE
VARIABLE _BOX-PARENT
VARIABLE _BOX-PREV
VARIABLE _BOX-CUR
VARIABLE _BOX-DISP

\ =====================================================================
\  BOX-CREATE — Allocate a box for a DOM node
\ =====================================================================
\  ( dom-node -- box )
\  Allocates via ALLOCATE.  Zeros all fields.  Sets dom-node back-pointer.

: BOX-CREATE  ( dom-node -- box )
    _BOX-NODE !

    BOX-DESC-SIZE ALLOCATE
    0<> ABORT" BOX-CREATE: alloc failed"
    _BOX-TMP !

    \ Zero entire descriptor
    _BOX-TMP @  BOX-DESC-SIZE  0 FILL

    \ Set DOM node back-pointer
    _BOX-NODE @  _BOX-TMP @ B.DOM  !

    \ Default: block, auto dimensions
    BOX-D-BLOCK  _BOX-TMP @ B.DISPLAY  !
    BOX-AUTO     _BOX-TMP @ B.W        !
    BOX-AUTO     _BOX-TMP @ B.H        !
    BOX-AUTO     _BOX-TMP @ B.MAXW     !
    BOX-AUTO     _BOX-TMP @ B.MAXH     !

    _BOX-TMP @ ;

\ =====================================================================
\  BOX-DESTROY — Free a single box
\ =====================================================================
\  ( box -- )

: BOX-DESTROY  ( box -- )
    DUP B.FRAGS @ 0<> IF DUP B.FRAGS @ FREE THEN
    FREE ;

\ =====================================================================
\  BOX-FREE-TREE — Recursively free all boxes in a tree
\ =====================================================================
\  ( box -- )
\  Post-order traversal: free children first, then self.
\  Iterative to avoid deep recursion on the return stack.

VARIABLE _BFT-CUR
VARIABLE _BFT-NXT
VARIABLE _BFT-PAR

: BOX-FREE-TREE  ( box -- )
    DUP 0= IF DROP EXIT THEN
    _BFT-CUR !

    BEGIN
        _BFT-CUR @ 0<> WHILE

        \ If current has children, descend to first child
        _BFT-CUR @ B.CHILD @ 0<> IF
            _BFT-CUR @ B.CHILD @  _BFT-CUR !
        ELSE
            \ Leaf node: free it, advance to next or back to parent
            BEGIN
                _BFT-CUR @ B.NEXT @  _BFT-NXT !
                _BFT-CUR @ B.PARENT @ _BFT-PAR !

                \ Unlink from parent's child list
                _BFT-PAR @ 0<> IF
                    _BFT-NXT @ _BFT-PAR @ B.CHILD !
                THEN

                _BFT-CUR @ BOX-DESTROY

                _BFT-NXT @ 0<> IF
                    _BFT-NXT @ _BFT-CUR !
                    0   \ exit inner loop, continue outer
                ELSE
                    \ No next sibling — back to parent
                    _BFT-PAR @ 0<> IF
                        _BFT-PAR @ _BFT-CUR !
                        \ Parent's children now empty — loop again
                        -1   \ stay in inner loop
                    ELSE
                        0 _BFT-CUR !  \ root freed
                        0             \ exit inner loop
                    THEN
                THEN
            0= UNTIL
        THEN
    REPEAT ;

\ =====================================================================
\  CSS value parsing helpers
\ =====================================================================
\  _BOX-PARSE-PX ( a u -- n )
\  Parse a CSS length value string into integer pixels.
\  Supports: "10px", "10", "0", "auto".
\  Returns BOX-AUTO (-1) for "auto" or unparseable values.

VARIABLE _BPP-INT
VARIABLE _BPP-FRAC
VARIABLE _BPP-FD

\ Current font-size context for em resolution (set by BOX-RESOLVE-STYLE)
VARIABLE _BOX-EM-SIZE     \ 0 = not yet set (default 16)

: _BOX-IS-AUTO  ( a u -- flag )
    4 <> IF DROP 0 EXIT THEN
    DUP     C@ 97  <> IF DROP 0 EXIT THEN    \ 'a'
    DUP 1 + C@ 117 <> IF DROP 0 EXIT THEN    \ 'u'
    DUP 2 + C@ 116 <> IF DROP 0 EXIT THEN    \ 't'
        3 + C@ 111 =  ;                       \ 'o'

: _BOX-PARSE-PX  ( a u -- n )
    \ Skip leading whitespace
    BEGIN
        DUP 0> IF OVER C@ 32 = ELSE 0 THEN
    WHILE
        1 /STRING
    REPEAT

    DUP 0= IF 2DROP BOX-AUTO EXIT THEN

    \ Check for "auto"
    2DUP _BOX-IS-AUTO IF 2DROP BOX-AUTO EXIT THEN

    \ Parse number
    CSS-PARSE-NUMBER    ( a' u' int frac frac-digits flag )
    0= IF
        2DROP 2DROP BOX-AUTO EXIT        \ not a number
    THEN

    _BPP-FD !  _BPP-FRAC !  _BPP-INT !

    \ Check remaining string for '%' unit (ASCII 37)
    DUP 0> IF
        OVER C@ 37 = IF
            2DROP
            _BPP-INT @ 2 + NEGATE EXIT   \ -(pct+2): percentage marker
        THEN
    THEN

    \ Check for 'em' unit (ASCII 101, 109)
    DUP 2 >= IF
        OVER C@ 101 = IF               \ 'e'
            OVER 1+ C@ 109 = IF        \ 'm'
                2DROP
                \ Resolve em: multiply by current font-size context
                _BOX-EM-SIZE @ DUP 0= IF DROP 16 THEN
                _BPP-INT @ *
                \ Add fractional part: frac * em-size / 10^frac-digits
                _BPP-FRAC @ 0<> IF
                    _BOX-EM-SIZE @ DUP 0= IF DROP 16 THEN
                    _BPP-FRAC @ *
                    1  _BPP-FD @ 0 ?DO 10 * LOOP  /
                    +
                THEN
                EXIT
            THEN
        THEN
    THEN

    \ Check for 'rem' unit (ASCII 114, 101, 109) — resolve at 16px
    DUP 3 >= IF
        OVER C@ 114 = IF               \ 'r'
            OVER 1+ C@ 101 = IF        \ 'e'
                OVER 2 + C@ 109 = IF   \ 'm'
                    2DROP
                    _BPP-INT @ 16 *
                    _BPP-FRAC @ 0<> IF
                        16 _BPP-FRAC @ *
                        1  _BPP-FD @ 0 ?DO 10 * LOOP  /
                        +
                    THEN
                    EXIT
                THEN
            THEN
        THEN
    THEN

    \ Check for 'pt' unit (1pt = 1.333px, approx 4/3)
    DUP 2 >= IF
        OVER C@ 112 = IF               \ 'p'
            OVER 1+ C@ 116 = IF        \ 't'
                2DROP
                _BPP-INT @ 4 * 3 / EXIT
            THEN
        THEN
    THEN

    2DROP                                \ drop remaining string

    \ Just use integer part (truncate fractional — pixel rounding)
    _BPP-INT @ ;

\ Parse a single side value from a TRBL-expanded string
\ (same as _BOX-PARSE-PX but takes a u from TRBL expansion)
: _BOX-PARSE-SIDE  ( a u -- n )
    DUP 0= IF 2DROP 0 EXIT THEN
    _BOX-PARSE-PX ;

\ =====================================================================
\  BOX-RESOLVE-STYLE — Read computed CSS into box fields
\ =====================================================================
\  ( box -- )
\  Reads display, margin, padding, border-width, width, height from
\  the DOM node's computed style via DOM-STYLE@.

VARIABLE _BRS-BOX
VARIABLE _BRS-VA   VARIABLE _BRS-VL     \ value addr/len from DOM-STYLE@
VARIABLE _BPD-A                              \ parse-display scratch

\ Parse display value
\ Stack (a u): address and length of the display value string.
\ We store address in _BPD-A to avoid stack juggling.
: _BOX-PARSE-DISPLAY  ( a u -- display-type )
    DUP 0= IF 2DROP BOX-D-BLOCK EXIT THEN
    OVER _BPD-A !              \ save address
    \ Check for "none" (length = 4)
    DUP 4 = IF
        _BPD-A @     C@ 110 =     \ 'n'
        _BPD-A @ 1 + C@ 111 = AND \ 'o'
        _BPD-A @ 2 + C@ 110 = AND \ 'n'
        _BPD-A @ 3 + C@ 101 = AND \ 'e'
        IF 2DROP BOX-D-NONE EXIT THEN
    THEN
    \ Check for "inline-block" (length = 12)
    DUP 12 = IF
        _BPD-A @     C@ 105 =     \ 'i'
        _BPD-A @ 1 + C@ 110 = AND \ 'n'
        _BPD-A @ 6 + C@ 45  = AND \ '-'
        _BPD-A @ 7 + C@ 98  = AND \ 'b'
        IF 2DROP BOX-D-INLINE-BLOCK EXIT THEN
    THEN
    \ Check for "inline" (length = 6)
    DUP 6 = IF
        _BPD-A @     C@ 105 =     \ 'i'
        _BPD-A @ 1 + C@ 110 = AND \ 'n'
        _BPD-A @ 2 + C@ 108 = AND \ 'l'
        IF 2DROP BOX-D-INLINE EXIT THEN
    THEN
    \ Default = block
    2DROP BOX-D-BLOCK ;

\ Resolve a TRBL shorthand property + individual side overrides
\ ( box prop-a prop-u side-t-a side-t-u side-r-a side-r-u
\   side-b-a side-b-u side-l-a side-l-u
\   field-t field-r field-b field-l -- )
\ Too many parameters for stack — use variables.

VARIABLE _BRS-FT    VARIABLE _BRS-FR
VARIABLE _BRS-FB    VARIABLE _BRS-FL

\ Parse a TRBL CSS property and store into 4 box fields.
\ ( box shorthand-name-a shorthand-name-u
\   field-t-addr field-r-addr field-b-addr field-l-addr -- )
: _BOX-RESOLVE-TRBL  ( box prop-a prop-u ft fr fb fl -- )
    _BRS-FL !  _BRS-FB !  _BRS-FR !  _BRS-FT !
    _BRS-VL !  _BRS-VA !  _BRS-BOX !

    \ Try the shorthand property
    _BRS-BOX @ B.DOM @  _BRS-VA @ _BRS-VL @  DOM-STYLE@
    IF
        \ Expand TRBL
        CSS-EXPAND-TRBL DROP
        ( t-a t-u r-a r-u b-a b-u l-a l-u )
        _BOX-PARSE-SIDE _BRS-FL @ !
        _BOX-PARSE-SIDE _BRS-FB @ !
        _BOX-PARSE-SIDE _BRS-FR @ !
        _BOX-PARSE-SIDE _BRS-FT @ !
    ELSE
        2DROP
        0 _BRS-FT @ !   0 _BRS-FR @ !
        0 _BRS-FB @ !   0 _BRS-FL @ !
    THEN ;

\ Check one individual side property and override a field if found.
\ ( box prop-a prop-u field-addr -- )
VARIABLE _BRSD-FLD
: _BOX-RESOLVE-SIDE  ( box prop-a prop-u fld -- )
    _BRSD-FLD !
    ROT B.DOM @   \ ( prop-a prop-u dom )
    -ROT          \ ( dom prop-a prop-u )
    DOM-STYLE@
    IF  _BOX-PARSE-PX _BRSD-FLD @ !  ELSE  2DROP  THEN ;

: BOX-RESOLVE-STYLE  ( box -- )
    _BRS-BOX !

    \ --- Set em context from parent's font-size ---
    _BRS-BOX @ B.DOM @ DOM-PARENT DUP 0<> IF
        DUP DOM-TYPE@ DOM-T-ELEMENT = IF
            S" font-size" DOM-STYLE@
            IF
                16 _BOX-EM-SIZE !   \ set default first
                _BOX-PARSE-PX
                DUP 1 < IF DROP 16 THEN
                _BOX-EM-SIZE !
            ELSE
                2DROP 16 _BOX-EM-SIZE !
            THEN
        ELSE
            DROP 16 _BOX-EM-SIZE !
        THEN
    ELSE
        DROP 16 _BOX-EM-SIZE !
    THEN

    \ --- Display ---
    _BRS-BOX @ B.DOM @  S" display"  DOM-STYLE@
    IF
        _BOX-PARSE-DISPLAY
    ELSE
        2DROP BOX-D-BLOCK
    THEN
    _BRS-BOX @ B.DISPLAY ! 

    \ --- Width & Height ---
    _BRS-BOX @ B.DOM @  S" width"  DOM-STYLE@
    IF  _BOX-PARSE-PX  ELSE  2DROP BOX-AUTO  THEN
    _BRS-BOX @ B.W !

    _BRS-BOX @ B.DOM @  S" height"  DOM-STYLE@
    IF  _BOX-PARSE-PX  ELSE  2DROP BOX-AUTO  THEN
    _BRS-BOX @ B.H !

    \ --- Min/Max width & height ---
    _BRS-BOX @ B.DOM @  S" min-width"  DOM-STYLE@
    IF  _BOX-PARSE-PX  DUP BOX-AUTO = IF DROP 0 THEN  ELSE  2DROP 0  THEN
    _BRS-BOX @ B.MINW !

    _BRS-BOX @ B.DOM @  S" max-width"  DOM-STYLE@
    IF  _BOX-PARSE-PX  ELSE  2DROP BOX-AUTO  THEN
    _BRS-BOX @ B.MAXW !

    _BRS-BOX @ B.DOM @  S" min-height"  DOM-STYLE@
    IF  _BOX-PARSE-PX  DUP BOX-AUTO = IF DROP 0 THEN  ELSE  2DROP 0  THEN
    _BRS-BOX @ B.MINH !

    _BRS-BOX @ B.DOM @  S" max-height"  DOM-STYLE@
    IF  _BOX-PARSE-PX  ELSE  2DROP BOX-AUTO  THEN
    _BRS-BOX @ B.MAXH !

    \ --- Margin (shorthand then individual overrides) ---
    _BRS-BOX @  S" margin"
    _BRS-BOX @ B.MT  _BRS-BOX @ B.MR
    _BRS-BOX @ B.MB  _BRS-BOX @ B.ML
    _BOX-RESOLVE-TRBL
    _BRS-BOX @  S" margin-top"     _BRS-BOX @ B.MT  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" margin-right"   _BRS-BOX @ B.MR  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" margin-bottom"  _BRS-BOX @ B.MB  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" margin-left"    _BRS-BOX @ B.ML  _BOX-RESOLVE-SIDE

    \ --- Padding (shorthand then individual overrides) ---
    _BRS-BOX @  S" padding"
    _BRS-BOX @ B.PT  _BRS-BOX @ B.PR
    _BRS-BOX @ B.PB  _BRS-BOX @ B.PL
    _BOX-RESOLVE-TRBL
    _BRS-BOX @  S" padding-top"     _BRS-BOX @ B.PT  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" padding-right"   _BRS-BOX @ B.PR  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" padding-bottom"  _BRS-BOX @ B.PB  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" padding-left"    _BRS-BOX @ B.PL  _BOX-RESOLVE-SIDE

    \ --- Border-width (shorthand then individual overrides) ---
    _BRS-BOX @  S" border-width"
    _BRS-BOX @ B.BT  _BRS-BOX @ B.BR
    _BRS-BOX @ B.BB  _BRS-BOX @ B.BL
    _BOX-RESOLVE-TRBL
    _BRS-BOX @  S" border-top-width"     _BRS-BOX @ B.BT  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" border-right-width"   _BRS-BOX @ B.BR  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" border-bottom-width"  _BRS-BOX @ B.BB  _BOX-RESOLVE-SIDE
    _BRS-BOX @  S" border-left-width"    _BRS-BOX @ B.BL  _BOX-RESOLVE-SIDE

    \ --- Check if this is a text node box ---
    _BRS-BOX @ B.DOM @  DOM-TYPE@  DOM-T-TEXT = IF
        _BOX-F-TEXT  _BRS-BOX @ B.FLAGS  !
        BOX-D-INLINE  _BRS-BOX @ B.DISPLAY  !
    THEN

    \ --- User-agent defaults for special elements ---
    \ Only apply defaults when CSS didn't set explicit values.
    _BRS-BOX @ B.DOM @  DOM-TYPE@  DOM-T-ELEMENT = IF
        _BRS-BOX @ B.DOM @ DOM-TAG-NAME

        \ <hr>: margin 8px top/bottom, height 0, 1px border-top
        2DUP S" hr" STR-STRI= IF
            _BRS-BOX @ B.H @ BOX-AUTO = IF  0 _BRS-BOX @ B.H !  THEN
            _BRS-BOX @ B.MT @ 0= IF  8 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  8 _BRS-BOX @ B.MB !  THEN
        THEN

        \ <ul> / <ol>: left padding 40px, margin 16px top/bottom
        2DUP S" ul" STR-STRI= OVER 2 = AND IF
            _BRS-BOX @ B.PL @ 0= IF  40 _BRS-BOX @ B.PL !  THEN
            _BRS-BOX @ B.MT @ 0= IF  16 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  16 _BRS-BOX @ B.MB !  THEN
        THEN
        2DUP S" ol" STR-STRI= OVER 2 = AND IF
            _BRS-BOX @ B.PL @ 0= IF  40 _BRS-BOX @ B.PL !  THEN
            _BRS-BOX @ B.MT @ 0= IF  16 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  16 _BRS-BOX @ B.MB !  THEN
        THEN

        \ <p>: margin 16px top/bottom
        2DUP S" p" STR-STRI= OVER 1 = AND IF
            _BRS-BOX @ B.MT @ 0= IF  16 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  16 _BRS-BOX @ B.MB !  THEN
        THEN

        \ <h1>-<h6>: default margins (simplified)
        2DUP S" h1" STR-STRI= IF
            _BRS-BOX @ B.MT @ 0= IF  21 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  21 _BRS-BOX @ B.MB !  THEN
        THEN
        2DUP S" h2" STR-STRI= IF
            _BRS-BOX @ B.MT @ 0= IF  19 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  19 _BRS-BOX @ B.MB !  THEN
        THEN
        2DUP S" h3" STR-STRI= IF
            _BRS-BOX @ B.MT @ 0= IF  18 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  18 _BRS-BOX @ B.MB !  THEN
        THEN

        \ <blockquote>: left margin 40px, top/bottom 16px
        2DUP S" blockquote" STR-STRI= IF
            _BRS-BOX @ B.ML @ 0= IF  40 _BRS-BOX @ B.ML !  THEN
            _BRS-BOX @ B.MT @ 0= IF  16 _BRS-BOX @ B.MT !  THEN
            _BRS-BOX @ B.MB @ 0= IF  16 _BRS-BOX @ B.MB !  THEN
        THEN

        2DROP
    THEN ;

\ =====================================================================
\  Rectangle queries
\ =====================================================================
\  Return (x y w h) integer rectangles for the various box model areas.
\  We store box in _BR-BOX to avoid stack juggling madness.

VARIABLE _BR-BOX

: BOX-CONTENT-RECT  ( box -- x y w h )
    _BR-BOX !
    _BR-BOX @ B.X @
    _BR-BOX @ B.Y @
    _BR-BOX @ B.W @
    _BR-BOX @ B.H @ ;

: BOX-PADDING-RECT  ( box -- x y w h )
    _BR-BOX !
    _BR-BOX @ B.X @  _BR-BOX @ B.PL @ -
    _BR-BOX @ B.Y @  _BR-BOX @ B.PT @ -
    _BR-BOX @ B.W @  _BR-BOX @ B.PL @ +  _BR-BOX @ B.PR @ +
    _BR-BOX @ B.H @  _BR-BOX @ B.PT @ +  _BR-BOX @ B.PB @ + ;

: BOX-BORDER-RECT  ( box -- x y w h )
    _BR-BOX !
    _BR-BOX @ B.X @  _BR-BOX @ B.PL @ -  _BR-BOX @ B.BL @ -
    _BR-BOX @ B.Y @  _BR-BOX @ B.PT @ -  _BR-BOX @ B.BT @ -
    _BR-BOX @ B.W @  _BR-BOX @ B.PL @ +  _BR-BOX @ B.PR @ +
                     _BR-BOX @ B.BL @ +  _BR-BOX @ B.BR @ +
    _BR-BOX @ B.H @  _BR-BOX @ B.PT @ +  _BR-BOX @ B.PB @ +
                     _BR-BOX @ B.BT @ +  _BR-BOX @ B.BB @ + ;

: BOX-MARGIN-RECT  ( box -- x y w h )
    _BR-BOX !
    _BR-BOX @ B.X @  _BR-BOX @ B.PL @ -  _BR-BOX @ B.BL @ -  _BR-BOX @ B.ML @ -
    _BR-BOX @ B.Y @  _BR-BOX @ B.PT @ -  _BR-BOX @ B.BT @ -  _BR-BOX @ B.MT @ -
    _BR-BOX @ B.W @  _BR-BOX @ B.PL @ +  _BR-BOX @ B.PR @ +
                     _BR-BOX @ B.BL @ +  _BR-BOX @ B.BR @ +
                     _BR-BOX @ B.ML @ +  _BR-BOX @ B.MR @ +
    _BR-BOX @ B.H @  _BR-BOX @ B.PT @ +  _BR-BOX @ B.PB @ +
                     _BR-BOX @ B.BT @ +  _BR-BOX @ B.BB @ +
                     _BR-BOX @ B.MT @ +  _BR-BOX @ B.MB @ + ;

\ =====================================================================
\  BOX-BUILD-TREE — Generate box tree from DOM tree
\ =====================================================================
\  ( dom-root -- box-root )
\  Walks the DOM tree depth-first.  For each node that generates boxes
\  (element with display != none, or text node with non-empty text),
\  creates a box, links it into the box tree, and resolves its style.
\
\  Text nodes become leaf boxes with the _BOX-F-TEXT flag set.
\  display:none elements (and their subtrees) are skipped.

VARIABLE _BBT-ROOT       \ root box
VARIABLE _BBT-CUR-PAR    \ current parent box
VARIABLE _BBT-LAST       \ last child at current level (for sibling linking)
VARIABLE _BBT-BOX        \ current box being created

\ Internal: create a box for a DOM node and link it under the current parent
: _BOX-LINK-CHILD  ( dom-node -- box )
    BOX-CREATE DUP _BBT-BOX !

    \ Link to parent
    _BBT-CUR-PAR @ _BBT-BOX @ B.PARENT !

    \ Link as sibling or first child
    _BBT-LAST @ 0<> IF
        _BBT-BOX @  _BBT-LAST @ B.NEXT  !
    ELSE
        _BBT-CUR-PAR @ 0<> IF
            _BBT-BOX @  _BBT-CUR-PAR @ B.CHILD  !
        THEN
    THEN

    _BBT-BOX @ _BBT-LAST !
    _BBT-BOX @ ;

\ _BOX-UNLINK-LAST — Remove the most recently linked box.
\   Called when we discover display:none after linking.
\   ( box -- )  Frees the box and restores _BBT-LAST.
VARIABLE _BUL-BOX
VARIABLE _BUL-PREV
: _BOX-UNLINK-LAST  ( box -- )
    _BUL-BOX !
    \ If it was set as first child of parent, clear that
    _BBT-CUR-PAR @ 0<> IF
        _BBT-CUR-PAR @ B.CHILD @  _BUL-BOX @ = IF
            0 _BBT-CUR-PAR @ B.CHILD !
        THEN
    THEN
    \ Find the previous sibling (whose B.NEXT = _BUL-BOX) and unlink.
    0 _BBT-LAST !   \ default: no previous
    _BBT-CUR-PAR @ 0<> IF
        _BBT-CUR-PAR @ B.CHILD @ 0<> IF
            _BBT-CUR-PAR @ B.CHILD @  _BUL-PREV !
            _BUL-PREV @ _BUL-BOX @ = IF
                \ First child IS the box — already handled above
            ELSE
                \ Walk until we find the predecessor
                BEGIN
                    _BUL-PREV @ B.NEXT @  _BUL-BOX @ <> WHILE
                    _BUL-PREV @ B.NEXT @  _BUL-PREV !
                REPEAT
                \ _BUL-PREV's B.NEXT = _BUL-BOX.  Unlink.
                0  _BUL-PREV @ B.NEXT  !
                _BUL-PREV @  _BBT-LAST !
            THEN
        THEN
    THEN
    _BUL-BOX @ BOX-DESTROY ;

\ _BOX-BUILD-REC — Recursive tree builder.
\   ( dom-node -- )
\   Saves/restores _BBT-CUR-PAR, _BBT-LAST on the return stack so
\   recursive calls don't clobber the caller's state.
\   _BBR-CHILD iterates children; we advance it BEFORE recursing and
\   also save/restore it via the return stack.

: _BOX-BUILD-REC  ( dom-node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT = IF
        \ Create box, resolve style
        _BOX-LINK-CHILD      ( box )   \ dom-node consumed by BOX-CREATE
        DUP BOX-RESOLVE-STYLE

        \ Check display:none — unlink and skip subtree
        DUP BOX-DISPLAY BOX-D-NONE = IF
            _BOX-UNLINK-LAST
            EXIT
        THEN

        \ Save caller's state on return stack
        _BBT-CUR-PAR @ >R
        _BBT-LAST @    >R

        \ This box becomes the new parent for children
        DUP _BBT-CUR-PAR !     ( box )
        0   _BBT-LAST !

        \ Iterate children
        BOX-DOM DOM-FIRST-CHILD   ( first-child|0 )
        BEGIN
            DUP 0<> WHILE        ( child-node )
            DUP DOM-NEXT >R      \ save next-sib on return stack
            _BOX-BUILD-REC       \ recurse — may clobber all globals
            R>                   \ restore next-sib
        REPEAT
        DROP                     \ drop the 0

        \ Restore caller's state
        R> _BBT-LAST !
        R> _BBT-CUR-PAR !
    ELSE
        DUP DOM-TYPE@ DOM-T-TEXT = IF
            \ Create text box (leaf) — only if non-empty
            DUP DOM-TEXT NIP 0> IF
                _BOX-LINK-CHILD
                BOX-RESOLVE-STYLE
                EXIT          \ early exit so we don't DROP twice
            THEN
        THEN
        DROP
    THEN ;

\ BOX-BUILD-TREE — Generate box tree from DOM tree.
\   ( dom-root -- box-root )
\   DOM-PARSE-HTML returns a fragment; we iterate its children.

: BOX-BUILD-TREE  ( dom-root -- box-root )
    0 _BBT-ROOT !
    0 _BBT-CUR-PAR !
    0 _BBT-LAST !

    DUP DOM-TYPE@ DUP DOM-T-ELEMENT = SWAP DOM-T-TEXT = OR IF
        \ Single element or text node — make it the root box
        DUP _BOX-LINK-CHILD _BBT-ROOT !
        _BBT-ROOT @  _BBT-CUR-PAR !
        0 _BBT-LAST !

        DOM-FIRST-CHILD            ( first-child|0 )
        BEGIN
            DUP 0<> WHILE          ( child-node )
            DUP DOM-NEXT >R
            _BOX-BUILD-REC
            R>
        REPEAT
        DROP

        _BBT-ROOT @ BOX-RESOLVE-STYLE
    ELSE
        \ Fragment/document: iterate children at top level
        DOM-FIRST-CHILD            ( first-child|0 )
        BEGIN
            DUP 0<> WHILE          ( child-node )
            DUP DOM-NEXT >R
            _BOX-BUILD-REC
            R>
        REPEAT
        DROP
        _BBT-LAST @  _BBT-ROOT !
    THEN

    _BBT-ROOT @ ;

