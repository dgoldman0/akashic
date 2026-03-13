\ =====================================================================
\  akashic/tui/label.f — Static Text Labels
\ =====================================================================
\
\  Displays a fixed text string within a region.  Supports single-line
\  and multi-line text, with left / center / right alignment.
\  Labels are non-interactive (handle-xt is a no-op that returns 0).
\
\  Label Descriptor (header + 3 cells = 64 bytes):
\    +0..+32  widget header  (type=WDG-T-LABEL)
\    +40      text-addr      Address of text string
\    +48      text-len       Length of text string (bytes)
\    +56      align          LBL-LEFT(0) | LBL-CENTER(1) | LBL-RIGHT(2)
\
\  Prefix: LBL- (public), _LBL- (internal)
\  Provider: akashic-tui-label
\  Dependencies: widget.f, draw.f, region.f

PROVIDED akashic-tui-label

REQUIRE ../widget.f
REQUIRE ../draw.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _LBL-O-TEXT-A    \ text address
48 CONSTANT _LBL-O-TEXT-U    \ text length (bytes)
56 CONSTANT _LBL-O-ALIGN     \ alignment mode

64 CONSTANT _LBL-DESC-SIZE   \ total descriptor size

\ =====================================================================
\ 2. Alignment constants
\ =====================================================================

0 CONSTANT LBL-LEFT
1 CONSTANT LBL-CENTER
2 CONSTANT LBL-RIGHT

\ =====================================================================
\ 3. Internal — NOP handle (labels ignore all events)
\ =====================================================================

: _LBL-HANDLE  ( event widget -- 0 )
    2DROP 0 ;

\ =====================================================================
\ 4. Internal — draw
\ =====================================================================
\
\  Draws text into the widget's region (already active via WDG-DRAW).
\  Multi-line: splits at region width, advancing rows.
\  Text beyond the region height is silently clipped.

VARIABLE _LBL-DRW-W       \ region width
VARIABLE _LBL-DRW-H       \ region height
VARIABLE _LBL-DRW-ADDR    \ remaining text addr
VARIABLE _LBL-DRW-LEN     \ remaining text len (bytes)
VARIABLE _LBL-DRW-ROW     \ current row
VARIABLE _LBL-DRW-ALIGN   \ alignment mode

\ --- Draw one row of text with correct alignment ---

VARIABLE _LBL-DR-ADDR
VARIABLE _LBL-DR-BLEN
VARIABLE _LBL-DR-ROW

: _LBL-DRAW-ROW  ( addr blen row -- )
    _LBL-DR-ROW !
    _LBL-DR-BLEN !
    _LBL-DR-ADDR !
    \ Clear the row first
    32 _LBL-DR-ROW @ 0 _LBL-DRW-W @ DRW-HLINE
    \ Draw text with alignment
    _LBL-DRW-ALIGN @ CASE
        LBL-LEFT OF
            _LBL-DR-ADDR @ _LBL-DR-BLEN @
            _LBL-DR-ROW @ 0
            DRW-TEXT
        ENDOF
        LBL-CENTER OF
            _LBL-DR-ADDR @ _LBL-DR-BLEN @
            _LBL-DR-ROW @ 0 _LBL-DRW-W @
            DRW-TEXT-CENTER
        ENDOF
        LBL-RIGHT OF
            _LBL-DR-ADDR @ _LBL-DR-BLEN @
            _LBL-DR-ROW @ 0 _LBL-DRW-W @
            DRW-TEXT-RIGHT
        ENDOF
    ENDCASE ;

\ --- Consume up to maxcp codepoints from _LBL-DRW-ADDR/_LBL-DRW-LEN ---
\   Advances both variables.  Returns bytes consumed.

VARIABLE _LBL-CON-BLEN

: _LBL-CONSUME  ( maxcp -- blen )
    0 _LBL-CON-BLEN !
    BEGIN
        DUP 0>                              \ codepoints left to consume?
        _LBL-DRW-LEN @ 0>                  \ bytes remaining?
        AND
    WHILE
        _LBL-DRW-ADDR @ C@                 \ peek lead byte
        DUP 0x80 < IF DROP 1
        ELSE DUP 0xE0 < IF DROP 2
        ELSE DUP 0xF0 < IF DROP 3
        ELSE DROP 4
        THEN THEN THEN                     \ ( maxcp nbytes )
        DUP _LBL-CON-BLEN +!              \ accumulate byte count
        DUP _LBL-DRW-ADDR +!              \ advance addr
        NEGATE _LBL-DRW-LEN +!            \ reduce remaining len
        1-                                  \ decrement maxcp
    REPEAT
    DROP                                    \ drop remaining maxcp
    _LBL-CON-BLEN @ ;

\ --- Main draw routine ---

: _LBL-DRAW  ( widget -- )
    DUP WDG-REGION RGN-W _LBL-DRW-W !
    DUP WDG-REGION RGN-H _LBL-DRW-H !
    DUP _LBL-O-ALIGN + @ _LBL-DRW-ALIGN !
    DUP _LBL-O-TEXT-A + @ _LBL-DRW-ADDR !
        _LBL-O-TEXT-U + @ _LBL-DRW-LEN !
    0 _LBL-DRW-ROW !
    \ Draw text rows
    BEGIN
        _LBL-DRW-LEN @ 0>
        _LBL-DRW-ROW @ _LBL-DRW-H @ <
        AND
    WHILE
        _LBL-DRW-ADDR @                    \ save line start addr
        _LBL-DRW-W @ _LBL-CONSUME         \ ( start-addr blen )
        _LBL-DRW-ROW @
        _LBL-DRAW-ROW
        1 _LBL-DRW-ROW +!
    REPEAT
    \ Clear remaining rows
    BEGIN
        _LBL-DRW-ROW @ _LBL-DRW-H @ <
    WHILE
        32 _LBL-DRW-ROW @ 0 _LBL-DRW-W @ DRW-HLINE
        1 _LBL-DRW-ROW +!
    REPEAT ;

\ =====================================================================
\ 5. Constructor
\ =====================================================================

\ LBL-NEW ( rgn text-a text-u align -- widget )
\   Create a new label widget.
: LBL-NEW  ( rgn text-a text-u align -- widget )
    >R >R >R                               \ R: align text-u text-a ; ( rgn )
    _LBL-DESC-SIZE ALLOCATE
    0<> ABORT" LBL-NEW: alloc failed"      \ ( rgn addr )
    \ Fill header fields directly
    WDG-T-LABEL    OVER _WDG-O-TYPE      + !
    SWAP           OVER _WDG-O-REGION    + !   \ rgn stored; ( addr )
    ['] _LBL-DRAW  OVER _WDG-O-DRAW-XT   + !
    ['] _LBL-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                   OVER _WDG-O-FLAGS     + !
    \ Fill label fields from R stack
    R> OVER _LBL-O-TEXT-A + !              \ text-a
    R> OVER _LBL-O-TEXT-U + !              \ text-u
    R> OVER _LBL-O-ALIGN  + ! ;           \ align → ( widget )

\ =====================================================================
\ 6. Mutators
\ =====================================================================

\ LBL-SET-TEXT ( widget text-a text-u -- )
: LBL-SET-TEXT  ( widget text-a text-u -- )
    ROT                                     \ ( text-a text-u widget )
    DUP >R
    _LBL-O-TEXT-U + !                       \ store text-u
    R@ _LBL-O-TEXT-A + !                    \ store text-a
    R> WDG-DIRTY ;

\ LBL-SET-ALIGN ( widget align -- )
: LBL-SET-ALIGN  ( widget align -- )
    OVER _LBL-O-ALIGN + !
    WDG-DIRTY ;

\ LBL-FREE ( widget -- )
: LBL-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\ 7. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _lbl-guard

' LBL-NEW         CONSTANT _lbl-new-xt
' LBL-SET-TEXT     CONSTANT _lbl-settext-xt
' LBL-SET-ALIGN    CONSTANT _lbl-setalign-xt
' LBL-FREE        CONSTANT _lbl-free-xt

: LBL-NEW         _lbl-new-xt       _lbl-guard WITH-GUARD ;
: LBL-SET-TEXT     _lbl-settext-xt   _lbl-guard WITH-GUARD ;
: LBL-SET-ALIGN    _lbl-setalign-xt  _lbl-guard WITH-GUARD ;
: LBL-FREE        _lbl-free-xt      _lbl-guard WITH-GUARD ;
[THEN] [THEN]
