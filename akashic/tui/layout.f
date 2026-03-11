\ =====================================================================
\  akashic/tui/layout.f — Container Layout Engine
\ =====================================================================
\
\  Automatic positioning of child regions within a parent.
\  Three layout modes: vertical stack, horizontal stack, and fixed
\  positioning.  Terminal-UI equivalent of CSS flexbox — simpler,
\  but sufficient for dashboard-style layouts.
\
\  Layout Descriptor (6 cells = 48 bytes):
\    +0   region     Region this layout manages
\    +8   mode       LAY-VERTICAL / LAY-HORIZONTAL / LAY-FIXED
\   +16   gap        Gap between children (rows or cols)
\   +24   count      Number of children
\   +32   children   Address of child descriptor array
\   +40   flags      LAY-F-EXPAND, etc.
\
\  Child Descriptor (3 cells = 24 bytes):
\    +0   region     Child region (created by layout engine)
\    +8   size-hint  Requested size (0 = auto-expand)
\   +16   min-size   Minimum size (never shrink below this)
\
\  Prefix: LAY- (public), _LAY- (internal)
\  Provider: akashic-tui-layout
\  Dependencies: region.f

PROVIDED akashic-tui-layout

REQUIRE region.f

\ =====================================================================
\ 1. Constants
\ =====================================================================

0 CONSTANT LAY-VERTICAL     \ Stack children top-to-bottom
1 CONSTANT LAY-HORIZONTAL   \ Stack children left-to-right
2 CONSTANT LAY-FIXED        \ Children at explicit positions

1 CONSTANT LAY-F-EXPAND     \ Distribute remaining space equally

\ =====================================================================
\ 2. Descriptor offsets
\ =====================================================================

\ Layout descriptor
 0 CONSTANT _LAY-O-RGN
 8 CONSTANT _LAY-O-MODE
16 CONSTANT _LAY-O-GAP
24 CONSTANT _LAY-O-COUNT
32 CONSTANT _LAY-O-CHILDREN
40 CONSTANT _LAY-O-FLAGS

48 CONSTANT _LAY-DESC-SIZE

\ Child descriptor
 0 CONSTANT _LAY-C-RGN
 8 CONSTANT _LAY-C-HINT
16 CONSTANT _LAY-C-MIN

24 CONSTANT _LAY-CHILD-SIZE

\ =====================================================================
\ 3. Constructor / destructor
\ =====================================================================

\ LAY-NEW ( rgn mode gap -- lay )
\   Create a layout over the given region.
: LAY-NEW  ( rgn mode gap -- lay )
    _LAY-DESC-SIZE ALLOCATE
    0<> ABORT" LAY-NEW: alloc failed"
    >R
    R@ _LAY-O-GAP   + !             \ gap
    R@ _LAY-O-MODE  + !             \ mode
    R@ _LAY-O-RGN   + !             \ region
    0  R@ _LAY-O-COUNT    + !       \ count = 0
    0  R@ _LAY-O-CHILDREN + !       \ no children yet
    0  R@ _LAY-O-FLAGS    + !       \ no flags
    R> ;

\ LAY-FREE ( lay -- )
\   Free layout + child regions + child array.
VARIABLE _LAY-FREE-LAY
VARIABLE _LAY-FREE-I
VARIABLE _LAY-FREE-N
VARIABLE _LAY-FREE-CARR

: LAY-FREE  ( lay -- )
    _LAY-FREE-LAY !
    _LAY-FREE-LAY @ _LAY-O-COUNT + @ _LAY-FREE-N !
    _LAY-FREE-LAY @ _LAY-O-CHILDREN + @ _LAY-FREE-CARR !
    \ Free each child's region
    0 _LAY-FREE-I !
    BEGIN
        _LAY-FREE-I @ _LAY-FREE-N @ <
    WHILE
        _LAY-FREE-CARR @
        _LAY-FREE-I @ _LAY-CHILD-SIZE * +
        _LAY-C-RGN + @
        DUP 0<> IF RGN-FREE ELSE DROP THEN
        _LAY-FREE-I @ 1+ _LAY-FREE-I !
    REPEAT
    \ Free the children array
    _LAY-FREE-CARR @ DUP 0<> IF FREE ELSE DROP THEN
    \ Free the layout descriptor
    _LAY-FREE-LAY @ FREE ;

\ =====================================================================
\ 4. Accessors
\ =====================================================================

\ LAY-COUNT ( lay -- n )
: LAY-COUNT  ( lay -- n )
    _LAY-O-COUNT + @ ;

\ LAY-CHILD ( lay n -- child-rgn )
\   Get the nth child's region.
: LAY-CHILD  ( lay n -- child-rgn )
    _LAY-CHILD-SIZE *                   \ byte offset into children array
    SWAP _LAY-O-CHILDREN + @ +          \ addr of child descriptor
    _LAY-C-RGN + @ ;                    \ region from child

\ =====================================================================
\ 5. LAY-ADD — add a child
\ =====================================================================

VARIABLE _LAY-ADD-LAY
VARIABLE _LAY-ADD-HINT
VARIABLE _LAY-ADD-MIN
VARIABLE _LAY-ADD-N
VARIABLE _LAY-ADD-OLD
VARIABLE _LAY-ADD-NEW

\ LAY-ADD ( lay size-hint min-size -- child-rgn )
\   Add a child with given size-hint and min-size.
\   Returns the child's region (initially 0×0, set by LAY-COMPUTE).
: LAY-ADD  ( lay size-hint min-size -- child-rgn )
    _LAY-ADD-MIN !
    _LAY-ADD-HINT !
    _LAY-ADD-LAY !

    _LAY-ADD-LAY @ _LAY-O-COUNT + @ _LAY-ADD-N !
    _LAY-ADD-LAY @ _LAY-O-CHILDREN + @ _LAY-ADD-OLD !

    \ Allocate new children array (n+1 entries)
    _LAY-ADD-N @ 1+ _LAY-CHILD-SIZE * ALLOCATE
    0<> ABORT" LAY-ADD: alloc failed"
    _LAY-ADD-NEW !

    \ Copy old entries if any
    _LAY-ADD-N @ 0> IF
        _LAY-ADD-OLD @                  \ src
        _LAY-ADD-NEW @                  \ dst
        _LAY-ADD-N @ _LAY-CHILD-SIZE * \ byte count
        CMOVE
    THEN

    \ NOTE: Do not FREE old children array — the KDOS allocator
    \ may corrupt adjacent heap objects when merging freed blocks.
    \ The leaked memory is negligible (layouts rarely grow).

    \ Create a child region (0,0,0,0 for now — LAY-COMPUTE fills in)
    _LAY-ADD-LAY @ _LAY-O-RGN + @     \ parent region
    0 0 0 0 RGN-SUB                    \ ( child-rgn )

    \ Fill in the new child descriptor
    _LAY-ADD-NEW @
    _LAY-ADD-N @ _LAY-CHILD-SIZE * +   \ addr of new child slot
    >R
    DUP R@ _LAY-C-RGN + !             \ child-rgn
    _LAY-ADD-HINT @ R@ _LAY-C-HINT + !
    _LAY-ADD-MIN  @ R@ _LAY-C-MIN  + !
    R>
    DROP                                \ drop child-slot addr

    \ Update layout
    _LAY-ADD-NEW @ _LAY-ADD-LAY @ _LAY-O-CHILDREN + !
    _LAY-ADD-N @ 1+ _LAY-ADD-LAY @ _LAY-O-COUNT + !
    ;  \ child-rgn is already on stack from RGN-SUB

\ =====================================================================
\ 6. LAY-COMPUTE — recompute child positions
\ =====================================================================

\ --- Temporaries ---
VARIABLE _LC-LAY
VARIABLE _LC-RGN
VARIABLE _LC-MODE
VARIABLE _LC-GAP
VARIABLE _LC-COUNT
VARIABLE _LC-CARR
VARIABLE _LC-FLAGS
VARIABLE _LC-PROW
VARIABLE _LC-PCOL
VARIABLE _LC-PH
VARIABLE _LC-PW
VARIABLE _LC-PSIZE       \ parent size in layout direction
VARIABLE _LC-CROSS       \ cross-axis size
VARIABLE _LC-TOTAL-FIXED
VARIABLE _LC-AUTO-COUNT
VARIABLE _LC-TOTAL-GAPS
VARIABLE _LC-REMAINING
VARIABLE _LC-AUTO-SIZE
VARIABLE _LC-POS
VARIABLE _LC-I
VARIABLE _LC-CHILD-SZ
VARIABLE _LC-CADDR       \ current child descriptor addr

\ _LAY-COMPUTE-INNER ( lay -- )
\   The actual compute algorithm.
: _LAY-COMPUTE-INNER  ( lay -- )
    _LC-LAY !
    _LC-LAY @ _LAY-O-RGN + @      _LC-RGN !
    _LC-LAY @ _LAY-O-MODE + @     _LC-MODE !
    _LC-LAY @ _LAY-O-GAP + @      _LC-GAP !
    _LC-LAY @ _LAY-O-COUNT + @    _LC-COUNT !
    _LC-LAY @ _LAY-O-CHILDREN + @ _LC-CARR !
    _LC-LAY @ _LAY-O-FLAGS + @    _LC-FLAGS !

    \ Parent info
    _LC-RGN @ RGN-ROW _LC-PROW !
    _LC-RGN @ RGN-COL _LC-PCOL !
    _LC-RGN @ RGN-H   _LC-PH !
    _LC-RGN @ RGN-W   _LC-PW !

    \ Parent size in layout direction
    _LC-MODE @ LAY-VERTICAL = IF
        _LC-PH @ _LC-PSIZE !
        _LC-PW @ _LC-CROSS !
    ELSE
        _LC-PW @ _LC-PSIZE !
        _LC-PH @ _LC-CROSS !
    THEN

    \ --- Pass 1: Measure ---
    0 _LC-TOTAL-FIXED !
    0 _LC-AUTO-COUNT !

    0 _LC-I !
    BEGIN
        _LC-I @ _LC-COUNT @ <
    WHILE
        _LC-CARR @  _LC-I @ _LAY-CHILD-SIZE * + _LC-CADDR !
        _LC-CADDR @ _LAY-C-HINT + @           \ size-hint
        DUP 0> IF
            _LC-TOTAL-FIXED @ + _LC-TOTAL-FIXED !
        ELSE
            DROP
            _LC-AUTO-COUNT @ 1+ _LC-AUTO-COUNT !
        THEN
        _LC-I @ 1+ _LC-I !
    REPEAT

    \ Total gaps
    _LC-COUNT @ 1 > IF
        _LC-COUNT @ 1- _LC-GAP @ * _LC-TOTAL-GAPS !
    ELSE
        0 _LC-TOTAL-GAPS !
    THEN

    \ Remaining space
    _LC-PSIZE @
    _LC-TOTAL-FIXED @ -
    _LC-TOTAL-GAPS @ -
    DUP 0< IF DROP 0 THEN
    _LC-REMAINING !

    \ Auto size per expand child
    _LC-AUTO-COUNT @ 0> IF
        _LC-FLAGS @ LAY-F-EXPAND AND IF
            _LC-REMAINING @ _LC-AUTO-COUNT @ / _LC-AUTO-SIZE !
        ELSE
            0 _LC-AUTO-SIZE !
        THEN
    ELSE
        0 _LC-AUTO-SIZE !
    THEN

    \ --- Pass 2: Distribute ---
    0 _LC-POS !
    0 _LC-I !
    BEGIN
        _LC-I @ _LC-COUNT @ <
    WHILE
        _LC-CARR @ _LC-I @ _LAY-CHILD-SIZE * + _LC-CADDR !

        \ Determine child size
        _LC-CADDR @ _LAY-C-HINT + @
        DUP 0> IF
            _LC-CHILD-SZ !
        ELSE
            DROP
            _LC-AUTO-SIZE @ _LC-CHILD-SZ !
        THEN

        \ Enforce min-size
        _LC-CADDR @ _LAY-C-MIN + @
        _LC-CHILD-SZ @ OVER < IF    \ child-sz < min?
            _LC-CHILD-SZ !
        ELSE
            DROP
        THEN

        \ Update child region directly
        _LC-CADDR @ _LAY-C-RGN + @    \ child-rgn
        >R
        _LC-MODE @ LAY-VERTICAL = IF
            \ Vertical: row varies, col = parent col, w = parent w
            _LC-PROW @ _LC-POS @ +  R@ _RGN-O-ROW + !
            _LC-PCOL @               R@ _RGN-O-COL + !
            _LC-CHILD-SZ @           R@ _RGN-O-H   + !
            _LC-CROSS @              R@ _RGN-O-W   + !
        ELSE
            \ Horizontal: col varies, row = parent row, h = parent h
            _LC-PROW @               R@ _RGN-O-ROW + !
            _LC-PCOL @ _LC-POS @ +   R@ _RGN-O-COL + !
            _LC-CROSS @              R@ _RGN-O-H   + !
            _LC-CHILD-SZ @           R@ _RGN-O-W   + !
        THEN
        R>
        DROP

        \ Advance position
        _LC-POS @ _LC-CHILD-SZ @ + _LC-GAP @ + _LC-POS !

        _LC-I @ 1+ _LC-I !
    REPEAT ;

\ LAY-COMPUTE ( lay -- )
\   Recompute child positions and sizes.
: LAY-COMPUTE  ( lay -- )
    DUP _LAY-O-COUNT + @ 0= IF DROP EXIT THEN  \ nothing to do
    _LAY-COMPUTE-INNER ;

\ =====================================================================
\ 7. Flags helper
\ =====================================================================

\ LAY-FLAGS! ( flags lay -- )
\   Set layout flags.
: LAY-FLAGS!  ( flags lay -- )
    _LAY-O-FLAGS + ! ;

\ =====================================================================
\ 8. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
GUARD _lay-guard

' LAY-NEW       CONSTANT _lay-new-xt
' LAY-FREE      CONSTANT _lay-free-xt
' LAY-ADD       CONSTANT _lay-add-xt
' LAY-COMPUTE   CONSTANT _lay-compute-xt
' LAY-CHILD     CONSTANT _lay-child-xt
' LAY-COUNT     CONSTANT _lay-count-xt
' LAY-FLAGS!    CONSTANT _lay-flags-xt

: LAY-NEW       _lay-new-xt     _lay-guard WITH-GUARD ;
: LAY-FREE      _lay-free-xt    _lay-guard WITH-GUARD ;
: LAY-ADD       _lay-add-xt     _lay-guard WITH-GUARD ;
: LAY-COMPUTE   _lay-compute-xt _lay-guard WITH-GUARD ;
: LAY-CHILD     _lay-child-xt   _lay-guard WITH-GUARD ;
: LAY-COUNT     _lay-count-xt   _lay-guard WITH-GUARD ;
: LAY-FLAGS!    _lay-flags-xt   _lay-guard WITH-GUARD ;
[THEN] [THEN]
