\ =====================================================================
\  akashic/tui/progress.f — Progress Bar & Spinner
\ =====================================================================
\
\  Visual progress indicators.  A progress bar shows a filled/empty
\  ratio.  A spinner shows animated indeterminate progress (requires
\  periodic PRG-TICK calls from the event loop).
\
\  Bar rendering uses full-block and fractional characters for
\  sub-character precision (8 steps per column):
\    █ (full)  ▉▊▋▌▍▎▏ (fractional)  ░ (empty)
\
\  Spinner cycles through Braille dot patterns:
\    ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
\
\  Progress Descriptor (header + 4 cells = 72 bytes):
\    +0..+32  widget header  (type=WDG-T-PROGRESS)
\    +40      value          Current value (0..max)
\    +48      max            Maximum value
\    +56      style          PRG-BAR(0), PRG-SPINNER(1)
\    +64      frame          Spinner animation frame counter
\
\  Prefix: PRG- (public), _PRG- (internal)
\  Provider: akashic-tui-progress
\  Dependencies: widget.f, draw.f, region.f

PROVIDED akashic-tui-progress

REQUIRE ../widget.f
REQUIRE ../draw.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _PRG-O-VALUE
48 CONSTANT _PRG-O-MAX
56 CONSTANT _PRG-O-STYLE
64 CONSTANT _PRG-O-FRAME

72 CONSTANT _PRG-DESC-SIZE

\ =====================================================================
\ 2. Style constants
\ =====================================================================

0 CONSTANT PRG-BAR
1 CONSTANT PRG-SPINNER

\ =====================================================================
\ 3. Bar characters (codepoints)
\ =====================================================================

\ Full block: █ = U+2588
\ Fractional blocks (left-to-right: 7/8 to 1/8):
\   ▉ U+2589  ▊ U+258A  ▋ U+258B  ▌ U+258C
\   ▍ U+258D  ▎ U+258E  ▏ U+258F
\ Empty: ░ = U+2591

0x2588 CONSTANT _PRG-FULL
0x2591 CONSTANT _PRG-EMPTY

\ Fractional table: index 1..7 → codepoint
\ We store 8 entries: 0=empty, 1..7=fractional, but access 1..7 only
CREATE _PRG-FRAC
    0x2591 ,    \ 0/8 = empty (unused index 0)
    0x258F ,    \ 1/8 ▏
    0x258E ,    \ 2/8 ▎
    0x258D ,    \ 3/8 ▍
    0x258C ,    \ 4/8 ▌
    0x258B ,    \ 5/8 ▋
    0x258A ,    \ 6/8 ▊
    0x2589 ,    \ 7/8 ▉

\ _PRG-FRAC@ ( index -- cp )  Index 0..7.
: _PRG-FRAC@  ( index -- cp )
    8 * _PRG-FRAC + @ ;

\ =====================================================================
\ 4. Spinner frames (codepoints)
\ =====================================================================

10 CONSTANT _PRG-SPIN-COUNT

CREATE _PRG-SPIN
    0x280B ,    \ ⠋
    0x2819 ,    \ ⠙
    0x2839 ,    \ ⠹
    0x2838 ,    \ ⠸
    0x283C ,    \ ⠼
    0x2834 ,    \ ⠴
    0x2826 ,    \ ⠦
    0x2827 ,    \ ⠧
    0x2807 ,    \ ⠇
    0x280F ,    \ ⠏

: _PRG-SPIN@ ( frame -- cp )
    _PRG-SPIN-COUNT MOD
    8 * _PRG-SPIN + @ ;

\ =====================================================================
\ 5. Internal — NOP handle (progress bars ignore input)
\ =====================================================================

: _PRG-HANDLE  ( event widget -- 0 )
    2DROP 0 ;

\ =====================================================================
\ 6. Internal — draw bar
\ =====================================================================
\
\  Bar fill algorithm:
\    filled-eighths = (value * width * 8) / max
\    full-cols = filled-eighths / 8
\    frac      = filled-eighths MOD 8
\  Then draw: full-cols of █, 1 fractional char (if frac>0), rest ░.

VARIABLE _PRG-DB-W       \ region width
VARIABLE _PRG-DB-FULL    \ number of full columns
VARIABLE _PRG-DB-FRAC    \ fractional part (0..7)
VARIABLE _PRG-DB-COL     \ current column

: _PRG-DRAW-BAR  ( widget -- )
    DUP WDG-REGION RGN-W _PRG-DB-W !
    DUP _PRG-O-MAX + @                 \ ( widget max )
    DUP 0= IF                          \ max=0 → empty bar
        2DROP
        _PRG-EMPTY 0 0 _PRG-DB-W @ DRW-HLINE
        EXIT
    THEN
    SWAP _PRG-O-VALUE + @              \ ( max value )
    \ filled-eighths = value * width * 8 / max
    _PRG-DB-W @ 8 * *                  \ ( max  value*w*8 )
    SWAP /                              \ ( filled-eighths )
    DUP 8 /  _PRG-DB-FULL !           \ full columns
    8 MOD    _PRG-DB-FRAC !            \ fractional
    0 _PRG-DB-COL !
    \ Draw full columns
    _PRG-DB-FULL @ 0 ?DO
        _PRG-FULL 0 _PRG-DB-COL @ DRW-CHAR
        1 _PRG-DB-COL +!
    LOOP
    \ Draw fractional column (if any and within width)
    _PRG-DB-FRAC @ 0<> _PRG-DB-COL @ _PRG-DB-W @ < AND IF
        _PRG-DB-FRAC @ _PRG-FRAC@
        0 _PRG-DB-COL @ DRW-CHAR
        1 _PRG-DB-COL +!
    THEN
    \ Fill remaining with empty blocks
    BEGIN
        _PRG-DB-COL @ _PRG-DB-W @ <
    WHILE
        _PRG-EMPTY 0 _PRG-DB-COL @ DRW-CHAR
        1 _PRG-DB-COL +!
    REPEAT ;

\ =====================================================================
\ 7. Internal — draw spinner
\ =====================================================================

: _PRG-DRAW-SPIN  ( widget -- )
    DUP WDG-REGION RGN-W              \ ( widget w )
    SWAP _PRG-O-FRAME + @             \ ( w frame )
    _PRG-SPIN@                          \ ( w cp )
    0 0 DRW-CHAR                       \ draw spinner at (0,0)
    \ Fill rest of row with spaces
    1 ?DO
        32 0 I DRW-CHAR
    LOOP ;

\ =====================================================================
\ 8. Internal — draw dispatch
\ =====================================================================

: _PRG-DRAW  ( widget -- )
    DUP _PRG-O-STYLE + @ CASE
        PRG-BAR     OF _PRG-DRAW-BAR  ENDOF
        PRG-SPINNER OF _PRG-DRAW-SPIN ENDOF
        \ default: just drop
        SWAP DROP
    ENDCASE ;

\ =====================================================================
\ 9. Constructor
\ =====================================================================

\ PRG-NEW ( rgn max style -- widget )
\   Create a progress indicator.
: PRG-NEW  ( rgn max style -- widget )
    >R >R                                  \ R: style max ; ( rgn )
    _PRG-DESC-SIZE ALLOCATE
    0<> ABORT" PRG-NEW: alloc failed"      \ ( rgn addr )
    \ Fill header
    WDG-T-PROGRESS OVER _WDG-O-TYPE      + !
    SWAP           OVER _WDG-O-REGION    + !   \ ( addr )
    ['] _PRG-DRAW  OVER _WDG-O-DRAW-XT   + !
    ['] _PRG-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                   OVER _WDG-O-FLAGS     + !
    \ Fill progress fields
    0              OVER _PRG-O-VALUE + !       \ value = 0
    R>             OVER _PRG-O-MAX   + !       \ max
    R>             OVER _PRG-O-STYLE + !       \ style
    0              OVER _PRG-O-FRAME + ! ;     \ frame = 0

\ =====================================================================
\ 10. Public API
\ =====================================================================

\ PRG-SET ( widget value -- )
\   Set current value, mark dirty.
: PRG-SET  ( widget value -- )
    OVER _PRG-O-VALUE + !
    WDG-DIRTY ;

\ PRG-INC ( widget -- )
\   Increment value by 1, mark dirty.
: PRG-INC  ( widget -- )
    DUP _PRG-O-VALUE + @ 1+
    OVER _PRG-O-VALUE + !
    WDG-DIRTY ;

\ PRG-TICK ( widget -- )
\   Advance spinner frame by 1, mark dirty.
: PRG-TICK  ( widget -- )
    DUP _PRG-O-FRAME + @ 1+
    OVER _PRG-O-FRAME + !
    WDG-DIRTY ;

\ PRG-PCT ( widget -- n )
\   Get percentage (0–100).
: PRG-PCT  ( widget -- n )
    DUP _PRG-O-MAX + @ DUP 0= IF
        2DROP 0 EXIT
    THEN
    SWAP _PRG-O-VALUE + @ 100 *
    SWAP / ;

\ PRG-FREE ( widget -- )
: PRG-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\ 11. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _prg-guard

' PRG-NEW         CONSTANT _prg-new-xt
' PRG-SET         CONSTANT _prg-set-xt
' PRG-INC         CONSTANT _prg-inc-xt
' PRG-TICK        CONSTANT _prg-tick-xt
' PRG-PCT         CONSTANT _prg-pct-xt
' PRG-FREE        CONSTANT _prg-free-xt

: PRG-NEW         _prg-new-xt       _prg-guard WITH-GUARD ;
: PRG-SET         _prg-set-xt       _prg-guard WITH-GUARD ;
: PRG-INC         _prg-inc-xt       _prg-guard WITH-GUARD ;
: PRG-TICK        _prg-tick-xt      _prg-guard WITH-GUARD ;
: PRG-PCT         _prg-pct-xt       _prg-guard WITH-GUARD ;
: PRG-FREE        _prg-free-xt      _prg-guard WITH-GUARD ;
[THEN] [THEN]
