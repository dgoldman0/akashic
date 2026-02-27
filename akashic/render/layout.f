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
REQUIRE ../text/layout.f

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
\  Text measurement pre-pass
\ =====================================================================
\  Walk the box tree before layout and set BOX-W / BOX-H on text boxes
\  by measuring glyph advance widths via text/layout.f's LAY-TEXT-WIDTH.
\  Font size comes from the parent element's "font-size" CSS property
\  (text nodes have no CSS of their own).

VARIABLE _LMT-BOX

: _LAYO-GET-TEXT-FONT-SIZE  ( text-box -- font-size )
    BOX-PARENT DUP 0<> IF
        BOX-DOM S" font-size" DOM-STYLE@
        IF
            _BOX-PARSE-PX
            DUP 1 < IF DROP 16 THEN
        ELSE
            2DROP 16
        THEN
    ELSE
        DROP 16
    THEN ;

: _LAYO-MEASURE-TEXT-REC  ( box -- )
    DUP 0= IF DROP EXIT THEN
    DUP B.FLAGS @ _BOX-F-TEXT AND IF
        \ Text box — measure width and height
        _LMT-BOX !
        _LMT-BOX @ _LAYO-GET-TEXT-FONT-SIZE
        LAY-SCALE!
        _LMT-BOX @ BOX-DOM DOM-TEXT
        LAY-TEXT-WIDTH
        _LMT-BOX @ BOX-W!
        _LMT-BOX @ BOX-H BOX-AUTO = IF
            LAY-LINE-HEIGHT _LMT-BOX @ BOX-H!
        THEN
    ELSE
        \ Non-text — recurse into children
        BOX-FIRST-CHILD
        BEGIN DUP 0<> WHILE
            DUP BOX-NEXT >R
            _LAYO-MEASURE-TEXT-REC
            R>
        REPEAT
        DROP
    THEN ;

\ =====================================================================
\  _LAYO-PARSE-TEXT-ALIGN  ( box -- align-const )
\ =====================================================================
\  Read CSS "text-align" from the box's DOM node and return a
\  LINE-A-LEFT / LINE-A-CENTER / LINE-A-RIGHT constant.

: _LAYO-PARSE-TEXT-ALIGN  ( box -- align-const )
    BOX-DOM S" text-align" DOM-STYLE@
    IF
        DUP 6 = IF
            OVER C@ 99 = IF        \ "center" starts with 'c'
                2DROP LINE-A-CENTER EXIT
            THEN
        THEN
        DUP 5 = IF
            OVER C@ 114 = IF       \ "right" starts with 'r'
                2DROP LINE-A-RIGHT EXIT
            THEN
        THEN
        2DROP LINE-A-LEFT
    ELSE
        2DROP LINE-A-LEFT
    THEN ;

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

    \ Check for percentage width marker: w <= -2
    \ Encoding: -(percentage + 2), so pct = NEGATE(w) - 2
    _LAYO-BOX @ BOX-W -2 <= IF
        _LAYO-BOX @ BOX-W NEGATE 2 -         ( percentage )
        _LAYO-BOX @ LAYO-CONTAINING-W        ( pct cw )
        * 100 /                               ( resolved-w )
        DUP 0 < IF DROP 0 THEN
        _LAYO-BOX @ BOX-W!
    ELSE
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
    THEN

    \ Clamp to min-width / max-width
    _LAYO-BOX @ BOX-MIN-W DUP 0> IF
        _LAYO-BOX @ BOX-W OVER < IF
            _LAYO-BOX @ BOX-W!
        ELSE
            DROP
        THEN
    ELSE
        DROP
    THEN
    _LAYO-BOX @ BOX-MAX-W DUP BOX-AUTO <> OVER 0> AND IF
        _LAYO-BOX @ BOX-W OVER > IF
            _LAYO-BOX @ BOX-W!
        ELSE
            DROP
        THEN
    ELSE
        DROP
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

    \ Clamp to min-height / max-height
    _LAYO-BOX @ BOX-MIN-H DUP 0> IF
        _LAYO-BOX @ BOX-H OVER < IF
            _LAYO-BOX @ BOX-H!
        ELSE
            DROP
        THEN
    ELSE
        DROP
    THEN
    _LAYO-BOX @ BOX-MAX-H DUP BOX-AUTO <> OVER 0> AND IF
        _LAYO-BOX @ BOX-H OVER > IF
            _LAYO-BOX @ BOX-H!
        ELSE
            DROP
        THEN
    ELSE
        DROP
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

\ =====================================================================
\  Word-level text splitting for inline context
\ =====================================================================
\  Splits text box content at space boundaries into word-runs.
\  Each word-run carries its substring (addr, len) and a back-reference
\  to the source text box for CSS style lookup during painting.
\  A fragment array is allocated on the text box (B.FRAGS) to store
\  the final (x, y, addr, len) for each word after line breaking.

VARIABLE _WSP-BOX     \ text box being split
VARIABLE _WSP-SZ      \ font size

\ Check if a string contains a space character
: _LAYO-HAS-SPACE?  ( addr len -- flag )
    BEGIN DUP 0> WHILE
        OVER C@ 0x20 = IF 2DROP -1 EXIT THEN
        1 /STRING
    REPEAT
    2DROP 0 ;

\ Count space-separated chunks in text
VARIABLE _WC-A   VARIABLE _WC-L   VARIABLE _WC-N

: _LAYO-COUNT-WORDS  ( addr len -- n )
    _WC-L !  _WC-A !
    0 _WC-N !
    BEGIN _WC-L @ 0> WHILE
        \ Start of a chunk — count it
        _WC-N @ 1+ _WC-N !
        \ Skip non-spaces
        BEGIN
            _WC-L @ 0> IF _WC-A @ C@ 0x20 <> ELSE 0 THEN
        WHILE
            _WC-A @ 1+ _WC-A !  _WC-L @ 1- _WC-L !
        REPEAT
        \ Include trailing space if present
        _WC-L @ 0> IF
            _WC-A @ C@ 0x20 = IF
                _WC-A @ 1+ _WC-A !  _WC-L @ 1- _WC-L !
            THEN
        THEN
    REPEAT
    _WC-N @ ;

\ Word-run creation variables
VARIABLE _WSP-RA    \ word start addr
VARIABLE _WSP-WA    \ scanning addr
VARIABLE _WSP-WL    \ scanning remaining len
VARIABLE _WSP-WLEN  \ saved word length (survives ALLOCATE)

\ Split a text box into word-runs, append to _LIC-RUN-HEAD.
\ Allocates a fragment array on the text box's B.FRAGS.
: _LAYO-SPLIT-TEXT  ( text-box -- )
    _WSP-BOX !

    \ Get font size and set scale
    _WSP-BOX @ _LAYO-GET-TEXT-FONT-SIZE _WSP-SZ !
    _WSP-SZ @ LAY-SCALE!

    \ Get text content
    _WSP-BOX @ B.DOM @ DOM-TEXT   ( addr len )
    DUP 0= IF 2DROP EXIT THEN

    \ Count words for fragment array allocation
    2DUP _LAYO-COUNT-WORDS        ( addr len nwords )
    DUP 0= IF DROP 2DROP EXIT THEN

    \ Allocate fragment array: (1 + 4*n) cells
    DUP 4 * 1+ CELLS ALLOCATE
    0<> ABORT" layout.f: frag alloc failed"
    DUP 0 SWAP !                   \ count = 0
    _WSP-BOX @ B.FRAGS !          ( addr len nwords )
    DROP                           ( addr len )

    \ Scan text and create one run per word
    _WSP-WL !  _WSP-WA !

    BEGIN _WSP-WL @ 0> WHILE
        _WSP-WA @ _WSP-RA !       \ word start

        \ Skip non-spaces (word characters)
        BEGIN
            _WSP-WL @ 0> IF _WSP-WA @ C@ 0x20 <> ELSE 0 THEN
        WHILE
            _WSP-WA @ 1+ _WSP-WA !  _WSP-WL @ 1- _WSP-WL !
        REPEAT

        \ Include trailing space if present
        _WSP-WL @ 0> IF
            _WSP-WA @ C@ 0x20 = IF
                _WSP-WA @ 1+ _WSP-WA !  _WSP-WL @ 1- _WSP-WL !
            THEN
        THEN

        \ Create run for this word chunk
        _WSP-WA @ _WSP-RA @ -     ( word-len )
        DUP 0> IF
            _WSP-WLEN !                    ( -- )  \ save word-len in variable
            \ Compute text width — note: word-len is in _WSP-WLEN, not on stack
            _WSP-RA @  _WSP-WLEN @  LAY-TEXT-WIDTH  ( width )
            LAY-LINE-HEIGHT                ( width height )
            LAY-ASCENDER                   ( width height asc )
            LINE-RUN-TEXT                  ( run )
            \ Set substring data, length, and source box from variables
            \ (word-len was saved BEFORE ALLOCATE which may corrupt the data stack)
            DUP _LR.DATA   _WSP-RA @   SWAP !
            DUP _LR.DLEN   _WSP-WLEN @ SWAP !
            DUP _LR.SRCBOX _WSP-BOX @  SWAP !
            \ Append to run list
            _LIC-RUN-HEAD @ LINE-RUN-APPEND _LIC-RUN-HEAD !
        ELSE
            DROP
        THEN
    REPEAT ;

\ =====================================================================
\  _LAYO-MAKE-INLINE-RUNS  ( child -- )
\ =====================================================================
\  Creates one or more runs for an inline child and appends to
\  _LIC-RUN-HEAD.  Text boxes with spaces are word-split; others
\  get a single run.  All runs have srcbox set for positioning.

: _LAYO-MAKE-INLINE-RUNS  ( child -- )
    DUP B.FLAGS @ _BOX-F-TEXT AND IF
        \ Text box — check if needs word splitting
        DUP B.DOM @ DOM-TEXT _LAYO-HAS-SPACE? IF
            \ Has spaces — word-split with fragment array
            _LAYO-SPLIT-TEXT
        ELSE
            \ No spaces — single run (classic path)
            DUP >R
            DUP BOX-W
            DUP BOX-AUTO = IF DROP 0 THEN   _LIC-W !
            DUP BOX-H
            DUP BOX-AUTO = IF DROP 16 THEN  _LIC-H !
            _LIC-H @ 4 * 5 / _LIC-ASC !
            DROP
            _LIC-W @  _LIC-H @  _LIC-ASC @  LINE-RUN-TEXT
            R> OVER _LR.SRCBOX !
            _LIC-RUN-HEAD @ LINE-RUN-APPEND  _LIC-RUN-HEAD !
        THEN
    ELSE
        \ Inline or inline-block box — single box run
        DUP >R
        DUP BOX-W
        DUP BOX-AUTO = IF DROP 0 THEN   _LIC-W !
        DUP BOX-H
        DUP BOX-AUTO = IF DROP 0 THEN   _LIC-H !
        _LIC-H @ _LIC-ASC !
        DROP
        _LIC-W @  _LIC-H @  _LIC-ASC @  LINE-RUN-BOX
        R> OVER _LR.SRCBOX !
        _LIC-RUN-HEAD @ LINE-RUN-APPEND  _LIC-RUN-HEAD !
    THEN ;

\ Fragment positioning scratch variables
VARIABLE _LPF-FBOX   \ fragment source box
VARIABLE _LPF-FP     \ fragment array pointer
VARIABLE _LPF-FN     \ fragment count
VARIABLE _LPF-FE     \ fragment entry pointer

: LAYO-INLINE-CONTEXT  ( box -- )
    _LIC-BOX !
    0 _LIC-RUN-HEAD !

    \ Walk inline children, build run list
    _LIC-BOX @ BOX-FIRST-CHILD _LIC-CHILD !
    BEGIN
        _LIC-CHILD @ 0<> WHILE

        _LIC-CHILD @ BOX-DISPLAY BOX-D-NONE <> IF
            _LIC-CHILD @ _LAYO-MAKE-INLINE-RUNS
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

    \ Align lines — read text-align from CSS
    _LIC-BOX @ _LAYO-PARSE-TEXT-ALIGN   ( align-const )
    _LAYO-LINES @ _LAYO-LINE-CUR !
    BEGIN
        _LAYO-LINE-CUR @ 0<> WHILE
        _LAYO-LINE-CUR @  _LIC-BOX @ BOX-W  ROT DUP >R  LINE-ALIGN  R>
        _LAYO-LINE-CUR @ LINE-NEXT _LAYO-LINE-CUR !
    REPEAT
    DROP    \ drop align-const

    \ Update inline children positions from line runs.
    \ Word-split text boxes: store fragments in B.FRAGS array.
    \ Single-run text/box: set BOX-X/BOX-Y directly from srcbox.

    _LAYO-LINES @ _LAYO-LINE-CUR !
    BEGIN
        _LAYO-LINE-CUR @ 0<> WHILE
        _LAYO-LINE-CUR @ LINE-FIRST-RUN _LAYO-RUN !
        BEGIN
            _LAYO-RUN @ 0<> WHILE

            _LAYO-RUN @ _LR.SRCBOX @ DUP 0<> IF
                \ Run has a source box
                DUP B.FRAGS @ 0<> IF
                    \ Word-run with fragment array — store fragment
                    _LPF-FBOX !
                    _LPF-FBOX @ B.FRAGS @ _LPF-FP !
                    _LPF-FP @ @ _LPF-FN !
                    _LPF-FN @ 4 * 1+ CELLS _LPF-FP @ + _LPF-FE !
                    _LIC-BOX @ BOX-X  _LAYO-RUN @ LINE-RUN-X +
                    _LPF-FE @       !
                    _LIC-BOX @ BOX-Y  _LAYO-LINE-CUR @ LINE-Y +
                    _LPF-FE @ 8 +   !
                    _LAYO-RUN @ _LR.DATA @
                    _LPF-FE @ 16 +  !
                    _LAYO-RUN @ _LR.DLEN @
                    _LPF-FE @ 24 +  !
                    _LPF-FN @ 1+ _LPF-FP @ !
                ELSE
                    \ Single run (no fragments) — set box position
                    _LIC-BOX @ BOX-X  _LAYO-RUN @ LINE-RUN-X +
                    OVER BOX-X!
                    _LIC-BOX @ BOX-Y  _LAYO-LINE-CUR @ LINE-Y +
                    OVER BOX-Y!
                    DUP BOX-W BOX-AUTO = IF
                        _LAYO-RUN @ LINE-RUN-W OVER BOX-W!
                    THEN
                    DUP BOX-H BOX-AUTO = IF
                        _LAYO-RUN @ LINE-RUN-H OVER BOX-H!
                    THEN
                    DROP
                THEN
            ELSE
                DROP
            THEN

            _LAYO-RUN @ LINE-RUN-NEXT _LAYO-RUN !
        REPEAT

        _LAYO-LINE-CUR @ LINE-NEXT _LAYO-LINE-CUR !
    REPEAT

    \ Set word-split text boxes' position from their first fragment
    _LIC-BOX @ BOX-FIRST-CHILD _LIC-CHILD !
    BEGIN _LIC-CHILD @ 0<> WHILE
        _LIC-CHILD @ B.FLAGS @ _BOX-F-TEXT AND IF
            _LIC-CHILD @ B.FRAGS @ DUP 0<> IF
                DUP @ 0> IF
                    CELL+                              ( entry-ptr )
                    DUP @  _LIC-CHILD @ BOX-X!        ( entry-ptr )
                    CELL+ @  _LIC-CHILD @ BOX-Y!      ( -- )
                ELSE
                    DROP
                THEN
            ELSE
                DROP
            THEN
        THEN
        _LIC-CHILD @ BOX-NEXT _LIC-CHILD !
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

                    _LB-BOX @ BOX-Y
                    _LAYO-CUR-Y @ +
                    _LAYO-COLLAPSED @ +
                    _LB-CHILD @ BOX-BORDER-T +
                    _LB-CHILD @ BOX-PADDING-T +
                    _LB-CHILD @ BOX-Y!

                    \ child height defaults to 0 if auto
                    _LB-CHILD @ BOX-H BOX-AUTO = IF
                        0 _LB-CHILD @ BOX-H!
                    THEN

                    \ Advance Y past child's full border-box
                    _LAYO-CUR-Y @  _LAYO-COLLAPSED @ +
                    _LB-CHILD @ BOX-BORDER-T +
                    _LB-CHILD @ BOX-PADDING-T +
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

                    \ Set child Y position (absolute content origin)
                    _LB-BOX @ BOX-Y
                    _LAYO-CUR-Y @ +
                    _LAYO-COLLAPSED @ +
                    _LB-CHILD @ BOX-BORDER-T +
                    _LB-CHILD @ BOX-PADDING-T +
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

                    \ Advance Y past child's full border-box
                    _LAYO-CUR-Y @  _LAYO-COLLAPSED @ +
                    _LB-CHILD @ BOX-BORDER-T +
                    _LB-CHILD @ BOX-PADDING-T +
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

    \ Pre-pass: measure text box widths using font metrics
    _LL-BOX @ _LAYO-MEASURE-TEXT-REC

    \ Root content origin = margin + border + padding
    _LL-BOX @ BOX-MARGIN-L  _LL-BOX @ BOX-BORDER-L +  _LL-BOX @ BOX-PADDING-L +
    _LL-BOX @ BOX-X!
    _LL-BOX @ BOX-MARGIN-T  _LL-BOX @ BOX-BORDER-T +  _LL-BOX @ BOX-PADDING-T +
    _LL-BOX @ BOX-Y!

    \ Lay out as block
    _LL-BOX @ LAYO-BLOCK
;
