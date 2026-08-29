\ =====================================================================
\  akashic/tui/cell.f — Character Cell Type
\ =====================================================================
\
\  Defines the character cell as a packed 64-bit value — one codepoint,
\  one foreground color index, one background color index, and attribute
\  flags.  This is the "pixel" of the terminal UI.
\
\  Cell Encoding (1 cell = 8 bytes = 64 bits):
\
\    Bits 63       48 47      40 39      32 31          0
\         ┌─────────┬──────────┬──────────┬──────────────┐
\         │  attrs  │   bg     │   fg     │  codepoint   │
\         │ 16 bits │  8 bits  │  8 bits  │   32 bits    │
\         └─────────┴──────────┴──────────┴──────────────┘
\
\  - codepoint (bits 0–31):  Unicode codepoint.  0 = empty cell.
\  - fg        (bits 32–39): Foreground color index (0–255, 256-palette).
\  - bg        (bits 40–47): Background color index (0–255, 256-palette).
\  - attrs     (bits 48–63): Attribute flags.
\
\  Prefix: CELL- (public), _CELL- (internal)
\  Provider: akashic-tui-cell
\  Dependencies: none

PROVIDED akashic-tui-cell

\ =====================================================================
\ 1. Attribute flag constants
\ =====================================================================
\
\  Each is a single-bit mask at the appropriate position.

1            CONSTANT CELL-A-BOLD       \ attrs bit 0 — Bold / bright
2            CONSTANT CELL-A-DIM        \ attrs bit 1 — Dim / faint
4            CONSTANT CELL-A-ITALIC     \ attrs bit 2 — Italic
8            CONSTANT CELL-A-UNDERLINE  \ attrs bit 3 — Underline
16           CONSTANT CELL-A-BLINK      \ attrs bit 4 — Blink
32           CONSTANT CELL-A-REVERSE    \ attrs bit 5 — Reverse video
64           CONSTANT CELL-A-STRIKE     \ attrs bit 6 — Strikethrough
128          CONSTANT CELL-A-WIDE       \ attrs bit 7 — Wide char (left half)
256          CONSTANT CELL-A-CONT       \ attrs bit 8 — Continuation (right half)

\ =====================================================================
\ 2. Field masks
\ =====================================================================

HEX
FFFFFFFF       CONSTANT _CELL-CP-MASK    \ bits 0–31
FF00000000     CONSTANT _CELL-FG-MASK    \ bits 32–39
FF0000000000   CONSTANT _CELL-BG-MASK    \ bits 40–47
DECIMAL

32 CONSTANT _CELL-FG-SHIFT
40 CONSTANT _CELL-BG-SHIFT
48 CONSTANT _CELL-ATTRS-SHIFT

\ Masks for clearing a single field
_CELL-CP-MASK   INVERT CONSTANT _CELL-CP-CLR
_CELL-FG-MASK   INVERT CONSTANT _CELL-FG-CLR
_CELL-BG-MASK   INVERT CONSTANT _CELL-BG-CLR
HEX FFFF000000000000 INVERT CONSTANT _CELL-ATTRS-CLR DECIMAL

\ =====================================================================
\ 3. Constructor
\ =====================================================================

\ CELL-MAKE ( cp fg bg attrs -- cell )
\   Pack fields into a single 64-bit cell value.
: CELL-MAKE  ( cp fg bg attrs -- cell )
    _CELL-ATTRS-SHIFT LSHIFT >R       \ attrs → R
    _CELL-BG-SHIFT    LSHIFT >R       \ bg    → R
    _CELL-FG-SHIFT    LSHIFT          \ fg shifted
    OR                                 \ cp | fg
    R> OR                              \ | bg
    R> OR ;                            \ | attrs

\ =====================================================================
\ 4. Field extractors
\ =====================================================================

\ CELL-CP@ ( cell -- cp )      Extract codepoint (bits 0–31).
: CELL-CP@  ( cell -- cp )
    _CELL-CP-MASK AND ;

\ CELL-FG@ ( cell -- fg )      Extract foreground (bits 32–39).
: CELL-FG@  ( cell -- fg )
    _CELL-FG-SHIFT RSHIFT 255 AND ;

\ CELL-BG@ ( cell -- bg )      Extract background (bits 40–47).
: CELL-BG@  ( cell -- bg )
    _CELL-BG-SHIFT RSHIFT 255 AND ;

\ CELL-ATTRS@ ( cell -- attrs )  Extract attribute flags (bits 48–63).
: CELL-ATTRS@  ( cell -- attrs )
    _CELL-ATTRS-SHIFT RSHIFT ;

\ =====================================================================
\ 5. Field setters (non-destructive — return new cell)
\ =====================================================================

\ CELL-FG! ( fg cell -- cell' )    Replace foreground color.
: CELL-FG!  ( fg cell -- cell' )
    _CELL-FG-CLR AND                  \ clear old fg
    SWAP _CELL-FG-SHIFT LSHIFT OR ;   \ insert new fg

\ CELL-BG! ( bg cell -- cell' )    Replace background color.
: CELL-BG!  ( bg cell -- cell' )
    _CELL-BG-CLR AND                  \ clear old bg
    SWAP _CELL-BG-SHIFT LSHIFT OR ;   \ insert new bg

\ CELL-ATTRS! ( attrs cell -- cell' )  Replace attributes.
: CELL-ATTRS!  ( attrs cell -- cell' )
    _CELL-ATTRS-CLR AND               \ clear old attrs
    SWAP _CELL-ATTRS-SHIFT LSHIFT OR ; \ insert new attrs

\ CELL-CP! ( cp cell -- cell' )    Replace codepoint.
: CELL-CP!  ( cp cell -- cell' )
    _CELL-CP-CLR AND                  \ clear old cp
    SWAP _CELL-CP-MASK AND OR ;       \ insert new cp (masked to 32 bits)

\ =====================================================================
\ 6. Predicates and constants
\ =====================================================================

\ CELL-BLANK ( -- cell )
\   A blank cell: space (32), default fg (7=white), default bg (0=black),
\   no attributes.
32 7 0 0 CELL-MAKE CONSTANT CELL-BLANK

\ CELL-EQUAL? ( a b -- flag )
\   Compare two cells for exact equality.
: CELL-EQUAL?  ( a b -- flag )
    = ;

\ CELL-EMPTY? ( cell -- flag )
\   True if cell has codepoint 0 or space, default colors, no attrs.
: CELL-EMPTY?  ( cell -- flag )
    DUP CELL-CP@ DUP 0= SWAP 32 = OR  \ cp is 0 or space?
    SWAP DUP CELL-ATTRS@ 0=            \ no attrs?
    SWAP DUP CELL-FG@ 7 =             \ default fg?
    SWAP CELL-BG@ 0=                   \ default bg?
    AND AND AND ;

\ CELL-HAS-ATTR? ( attr-mask cell -- flag )
\   Test whether a specific attribute bit is set.
: CELL-HAS-ATTR?  ( attr-mask cell -- flag )
    CELL-ATTRS@ AND 0<> ;

\ =====================================================================
\ 7. Concurrency classification
\ =====================================================================
\
\ CELL values and every word in this module are pure stack computation over
\ immutable constants.  They neither own nor dereference shared storage, so a
\ module guard would add synchronization without protecting any state.  The
\ owner of the buffer containing a CELL remains responsible for synchronizing
\ that buffer; screen.f provides that boundary for screen planes.
