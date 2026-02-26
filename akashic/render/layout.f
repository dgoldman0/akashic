\ layout.f — Block & Inline Flow Layout Engine
\
\ Implements CSS 2.1 normal flow: block formatting context and inline
\ formatting context.  Takes a box tree (from box.f) and computes
\ positions (x, y) and resolved dimensions (width, height) for each box.
\
\ Load with:   REQUIRE render/layout.f
\ Depends on:  box.f, line.f
\
\ Public API:
\   LAYO-LAYOUT          ( box-root vp-w vp-h -- )  Full layout pass
\   LAYO-BLOCK           ( box -- )                  Lay out a block box
\   LAYO-INLINE-CONTEXT  ( box -- )                  Inline formatting ctx
\   LAYO-RESOLVE-WIDTH   ( box -- )                  Resolve width
\   LAYO-RESOLVE-HEIGHT  ( box -- )                  Resolve height
\   LAYO-COLLAPSE-MARGINS( a b -- collapsed )        Margin collapsing
\   LAYO-CONTAINING-W    ( box -- w )                Containing block width
\ =====================================================================

REQUIRE box.f
REQUIRE line.f

PROVIDED akashic-layout-engine

\ =====================================================================
\  Variables
\ =====================================================================

VARIABLE _LAYO-VP-W         \ viewport width
VARIABLE _LAYO-VP-H         \ viewport height
VARIABLE _LAYO-BOX          \ current box being laid out
VARIABLE _LAYO-CHILD        \ current child during iteration
VARIABLE _LAYO-CUR-Y        \ running Y cursor within a block
VARIABLE _LAYO-CW           \ containing width (for resolve-width)
VARIABLE _LAYO-PREV-MB      \ previous sibling's margin-bottom (for collapsing)
VARIABLE _LAYO-COLLAPSED    \ collapsed margin value

\ Inline context scratch
VARIABLE _LAYO-RUNS         \ run list head for inline context
VARIABLE _LAYO-LINES        \ line box list from LINE-BREAK
VARIABLE _LAYO-LINE-CUR     \ current line during iteration
VARIABLE _LAYO-RUN          \ current run during line processing

\ =====================================================================
\  LAYO-CONTAINING-W  ( box -- w )
\ =====================================================================
\  Returns the content width of the containing block.
\  For the root box (no parent), returns the viewport width.

: LAYO-CONTAINING-W  ( box -- w )
    BOX-PARENT
    DUP 0= IF
        DROP _LAYO-VP-W @
    ELSE
        BOX-W
        DUP BOX-AUTO = IF DROP _LAYO-VP-W @ THEN
    THEN
;

\ =====================================================================
\  LAYO-COLLAPSE-MARGINS  ( margin-a margin-b -- collapsed )
\ =====================================================================
\  CSS 2.1 margin collapsing for vertical margins:
\  - Both positive: max
\  - Both negative: min (most negative)
\  - Mixed: sum (positive + negative)

: LAYO-COLLAPSE-MARGINS  ( a b -- collapsed )
    2DUP 0 >= SWAP 0 >= AND IF
        \ Both non-negative: take the larger
        MAX EXIT
    THEN
    2DUP 0 < SWAP 0 < AND IF
        \ Both negative: take the more negative (min)
        MIN EXIT
    THEN
    \ Mixed: sum
    +
;

\ =====================================================================
\  LAYO-RESOLVE-WIDTH  ( box -- )
\ =====================================================================
\  Resolve the box's content width.
\  CSS 2.1 block width:
\    if width = auto:
\      width = containing-width - margin-l - margin-r
\                               - padding-l - padding-r
\                               - border-l  - border-r
\  If the result would be negative, clamp to 0.

: LAYO-RESOLVE-WIDTH  ( box -- )
    _LAYO-BOX !

    _LAYO-BOX @ BOX-W BOX-AUTO = IF
        \ auto width: fill containing block
        _LAYO-BOX @ LAYO-CONTAINING-W

        _LAYO-BOX @ BOX-MARGIN-L -
        _LAYO-BOX @ BOX-MARGIN-R -
        _LAYO-BOX @ BOX-PADDING-L -
        _LAYO-BOX @ BOX-PADDING-R -
        _LAYO-BOX @ BOX-BORDER-L -
        _LAYO-BOX @ BOX-BORDER-R -

        \ Clamp to 0
        DUP 0 < IF DROP 0 THEN

        _LAYO-BOX @ BOX-W!
    THEN
;

\ =====================================================================
\  LAYO-RESOLVE-HEIGHT  ( box -- )
\ =====================================================================
\  Resolve the box's content height after children are laid out.
\  If height = auto, set it to _LAYO-CUR-Y (the Y cursor after all
\  children).

: LAYO-RESOLVE-HEIGHT  ( box -- )
    _LAYO-BOX !

    _LAYO-BOX @ BOX-H BOX-AUTO = IF
        _LAYO-CUR-Y @  _LAYO-BOX @ BOX-H!
    THEN
;

\ =====================================================================
\  LAYO-INLINE-CONTEXT  ( box -- )
\ =====================================================================
\  Generate line boxes for inline children of a block box.
\  Walks children, creates runs for each inline/text box, breaks
\  into lines, assigns Y positions, and sets _LAYO-CUR-Y.
\
\  For each inline child:
\    - text boxes    → text run (width from BOX-W, any height)
\    - inline boxes  → box run
\    - inline-block  → box run (resolved width/height)
\
\  Text measurement must happen upstream (BOX-W set before layout).
\  For text boxes with auto width, we default to 0 (placeholder).

VARIABLE _LIC-BOX       \ the parent block box
VARIABLE _LIC-CHILD     \ iteration child
VARIABLE _LIC-RUN-HEAD  \ run list head (0 initially)
VARIABLE _LIC-RUN       \ current run being created
VARIABLE _LIC-W         \ width for current run
VARIABLE _LIC-H         \ height for current run
VARIABLE _LIC-ASC       \ ascender for current run

: _LAYO-MAKE-INLINE-RUN  ( child -- run | 0 )
    DUP B.FLAGS @ _BOX-F-TEXT AND IF
        \ Text box — create text run
        DUP BOX-W
        DUP BOX-AUTO = IF DROP 0 THEN   _LIC-W !
        DUP BOX-H
        DUP BOX-AUTO = IF DROP 16 THEN  _LIC-H !  \ default text height 16
        \ Ascender = ~80% of height (rough default)
        _LIC-H @ 4 * 5 / _LIC-ASC !
        DROP
        _LIC-W @  _LIC-H @  _LIC-ASC @  LINE-RUN-TEXT
    ELSE
        \ Inline or inline-block box — create box run
        DUP BOX-W
        DUP BOX-AUTO = IF DROP 0 THEN   _LIC-W !
        DUP BOX-H
        DUP BOX-AUTO = IF DROP 0 THEN   _LIC-H !
        _LIC-H @ _LIC-ASC !    \ ascender = full height for box runs
        DROP
        _LIC-W @  _LIC-H @  _LIC-ASC @  LINE-RUN-BOX
    THEN
;

: LAYO-INLINE-CONTEXT  ( box -- )
    _LIC-BOX !
    0 _LIC-RUN-HEAD !

    \ Walk inline children, build run list
    _LIC-BOX @ BOX-FIRST-CHILD _LIC-CHILD !
    BEGIN
        _LIC-CHILD @ 0<> WHILE

        _LIC-CHILD @ BOX-DISPLAY BOX-D-NONE <> IF
            _LIC-CHILD @ _LAYO-MAKE-INLINE-RUN
            DUP 0<> IF
                _LIC-RUN-HEAD @ LINE-RUN-APPEND  _LIC-RUN-HEAD !
            ELSE
                DROP
            THEN
        THEN

        _LIC-CHILD @ BOX-NEXT _LIC-CHILD !
    REPEAT

    _LIC-RUN-HEAD @ 0= IF
        \ No inline content — height stays as-is
        EXIT
    THEN

    \ Break runs into lines
    _LIC-RUN-HEAD @  _LIC-BOX @ BOX-W  LINE-BREAK
    _LAYO-LINES !

    \ Position lines vertically
    0 _LAYO-CUR-Y !
    _LAYO-LINES @ _LAYO-LINE-CUR !
    BEGIN
        _LAYO-LINE-CUR @ 0<> WHILE
        _LAYO-CUR-Y @  _LAYO-LINE-CUR @  LINE-Y!
        _LAYO-CUR-Y @  _LAYO-LINE-CUR @  LINE-HEIGHT  +  _LAYO-CUR-Y !
        _LAYO-LINE-CUR @ LINE-NEXT _LAYO-LINE-CUR !
    REPEAT

    \ Align lines (left alignment by default)
    _LAYO-LINES @ _LAYO-LINE-CUR !
    BEGIN
        _LAYO-LINE-CUR @ 0<> WHILE
        _LAYO-LINE-CUR @  _LIC-BOX @ BOX-W  LINE-A-LEFT  LINE-ALIGN
        _LAYO-LINE-CUR @ LINE-NEXT _LAYO-LINE-CUR !
    REPEAT

    \ Update inline children positions from line runs
    \ Walk lines → runs, match back to child boxes
    \ For now, position children based on run x/y
    _LAYO-LINES @ _LAYO-LINE-CUR !
    _LIC-BOX @ BOX-FIRST-CHILD _LIC-CHILD !
    BEGIN
        _LAYO-LINE-CUR @ 0<> WHILE
        _LAYO-LINE-CUR @ LINE-FIRST-RUN _LAYO-RUN !
        BEGIN
            _LAYO-RUN @ 0<> _LIC-CHILD @ 0<> AND WHILE

            \ Skip display:none children
            BEGIN
                _LIC-CHILD @ 0<> IF
                    _LIC-CHILD @ BOX-DISPLAY BOX-D-NONE =
                ELSE 0 THEN
            WHILE
                _LIC-CHILD @ BOX-NEXT _LIC-CHILD !
            REPEAT

            _LIC-CHILD @ 0<> IF
                \ Set child position from run
                _LAYO-RUN @ LINE-RUN-X  _LIC-CHILD @ BOX-X!
                _LAYO-LINE-CUR @ LINE-Y  _LIC-CHILD @ BOX-Y!

                \ Set child dimensions from run if auto
                _LIC-CHILD @ BOX-W BOX-AUTO = IF
                    _LAYO-RUN @ LINE-RUN-W  _LIC-CHILD @ BOX-W!
                THEN
                _LIC-CHILD @ BOX-H BOX-AUTO = IF
                    _LAYO-RUN @ LINE-RUN-H  _LIC-CHILD @ BOX-H!
                THEN

                _LIC-CHILD @ BOX-NEXT _LIC-CHILD !
            THEN
            _LAYO-RUN @ LINE-RUN-NEXT _LAYO-RUN !
        REPEAT

        _LAYO-LINE-CUR @ LINE-NEXT _LAYO-LINE-CUR !
    REPEAT

    \ Free line boxes (runs were part of them)
    _LAYO-LINES @ LINE-FREE
;

\ =====================================================================
\  LAYO-BLOCK  ( box -- )
\ =====================================================================
\  Lay out a block box and its children.
\
\  Block layout algorithm (CSS 2.1 normal flow):
\  1. Resolve width (auto → fill containing block).
\  2. Set content origin X = parent content X + margin-l + border-l + padding-l.
\  3. Walk children:
\     a. Block children: lay out recursively. Advance Y by child's
\        margin-box height. Collapse vertical margins.
\     b. Inline children: enter inline formatting context.
\  4. Resolve height (auto → sum of children from Y cursor).

VARIABLE _LB-BOX          \ current box being laid out
VARIABLE _LB-CHILD        \ current child in iteration
VARIABLE _LB-ALL-INLINE   \ flag: 1 if all children are inline

: _LAYO-IS-INLINE  ( display -- flag )
    DUP BOX-D-INLINE = SWAP BOX-D-INLINE-BLOCK = OR ;

\ Check if all children of a box are inline (or text)
: _LAYO-ALL-CHILDREN-INLINE  ( box -- flag )
    BOX-FIRST-CHILD
    BEGIN
        DUP 0<> WHILE
        DUP BOX-DISPLAY
        DUP BOX-D-NONE = IF
            DROP   \ skip display:none
        ELSE
            _LAYO-IS-INLINE 0= IF
                DROP 0 EXIT    \ found a block child
            THEN
        THEN
        BOX-NEXT
    REPEAT
    DROP 1   \ all inline (or no children)
;

: LAYO-BLOCK  ( box -- )
    _LB-BOX !

    \ 1. Resolve width
    _LB-BOX @ LAYO-RESOLVE-WIDTH

    \ 2. Set content origin X
    _LB-BOX @ BOX-PARENT 0<> IF
        _LB-BOX @ BOX-PARENT BOX-X
        _LB-BOX @ BOX-MARGIN-L +
        _LB-BOX @ BOX-BORDER-L +
        _LB-BOX @ BOX-PADDING-L +
        _LB-BOX @ BOX-X!
    THEN

    \ 3. Check children type
    _LB-BOX @ BOX-FIRST-CHILD 0= IF
        \ No children — auto height = 0
        0 _LAYO-CUR-Y !
        _LB-BOX @ LAYO-RESOLVE-HEIGHT
        EXIT
    THEN

    _LB-BOX @ _LAYO-ALL-CHILDREN-INLINE _LB-ALL-INLINE !

    _LB-ALL-INLINE @ IF
        \ All inline — enter inline formatting context
        _LB-BOX @ LAYO-INLINE-CONTEXT
        _LB-BOX @ LAYO-RESOLVE-HEIGHT
    ELSE
        \ Block children
        0 _LAYO-CUR-Y !
        0 _LAYO-PREV-MB !

        _LB-BOX @ BOX-FIRST-CHILD _LB-CHILD !
        BEGIN
            _LB-CHILD @ 0<> WHILE

            _LB-CHILD @ BOX-DISPLAY BOX-D-NONE = IF
                \ Skip hidden children
            ELSE
                _LB-CHILD @ BOX-DISPLAY _LAYO-IS-INLINE IF
                    \ Inline child in block context — treat as block
                    \ (anonymous block box — simplified: just resolve it)
                    _LB-CHILD @ LAYO-RESOLVE-WIDTH

                    _LB-BOX @ BOX-X
                    _LB-CHILD @ BOX-MARGIN-L +
                    _LB-CHILD @ BOX-BORDER-L +
                    _LB-CHILD @ BOX-PADDING-L +
                    _LB-CHILD @ BOX-X!

                    \ Collapse top margin with previous bottom margin
                    _LAYO-PREV-MB @  _LB-CHILD @ BOX-MARGIN-T
                    LAYO-COLLAPSE-MARGINS _LAYO-COLLAPSED !

                    _LAYO-CUR-Y @
                    _LAYO-COLLAPSED @ +        \ apply collapsed margin
                    _LB-CHILD @ BOX-Y!

                    \ child height defaults to 0 if auto
                    _LB-CHILD @ BOX-H BOX-AUTO = IF
                        0 _LB-CHILD @ BOX-H!
                    THEN

                    \ Advance Y past child's border-box bottom
                    _LB-CHILD @ BOX-Y
                    _LB-CHILD @ BOX-H +
                    _LB-CHILD @ BOX-PADDING-B +
                    _LB-CHILD @ BOX-BORDER-B +
                    _LAYO-CUR-Y !

                    _LB-CHILD @ BOX-MARGIN-B _LAYO-PREV-MB !
                ELSE
                    \ Block child — full recursive layout
                    \ Collapse top margin with previous bottom margin
                    _LAYO-PREV-MB @  _LB-CHILD @ BOX-MARGIN-T
                    LAYO-COLLAPSE-MARGINS _LAYO-COLLAPSED !

                    \ Set child Y position
                    _LAYO-CUR-Y @
                    _LAYO-COLLAPSED @ +        \ apply collapsed margin
                    _LB-CHILD @ BOX-Y!

                    \ Recurse
                    _LB-CHILD @
                    \ Save our iteration state on return stack
                    _LB-BOX @         >R
                    _LB-CHILD @       >R
                    _LAYO-CUR-Y @     >R
                    _LAYO-PREV-MB @   >R
                    _LB-ALL-INLINE @  >R

                    LAYO-BLOCK

                    R> _LB-ALL-INLINE !
                    R> _LAYO-PREV-MB !
                    R> _LAYO-CUR-Y !
                    R> _LB-CHILD !
                    R> _LB-BOX !

                    \ Advance Y past child's border-box bottom
                    _LB-CHILD @ BOX-Y
                    _LB-CHILD @ BOX-H +
                    _LB-CHILD @ BOX-PADDING-B +
                    _LB-CHILD @ BOX-BORDER-B +
                    _LAYO-CUR-Y !

                    _LB-CHILD @ BOX-MARGIN-B _LAYO-PREV-MB !
                THEN
            THEN

            _LB-CHILD @ BOX-NEXT _LB-CHILD !
        REPEAT

        \ Add final margin-bottom to cursor
        _LAYO-CUR-Y @  _LAYO-PREV-MB @ +  _LAYO-CUR-Y !

        \ 4. Resolve height
        _LB-BOX @ LAYO-RESOLVE-HEIGHT
    THEN
;

\ =====================================================================
\  LAYO-LAYOUT  ( box-root viewport-w viewport-h -- )
\ =====================================================================
\  Top-level entry: set viewport, position root, run block layout.

VARIABLE _LL-BOX

: LAYO-LAYOUT  ( box-root vp-w vp-h -- )
    _LAYO-VP-H !
    _LAYO-VP-W !
    _LL-BOX !

    \ Root content origin = margin + border + padding
    _LL-BOX @ BOX-MARGIN-L  _LL-BOX @ BOX-BORDER-L +  _LL-BOX @ BOX-PADDING-L +
    _LL-BOX @ BOX-X!
    _LL-BOX @ BOX-MARGIN-T  _LL-BOX @ BOX-BORDER-T +  _LL-BOX @ BOX-PADDING-T +
    _LL-BOX @ BOX-Y!

    \ Lay out as block
    _LL-BOX @ LAYO-BLOCK
;
