\ =====================================================================
\  akashic/tui/screen.f — Virtual Screen Buffer (double-buffered)
\ =====================================================================
\
\  Double-buffered character-cell screen.  Widgets write to the back
\  buffer.  SCR-FLUSH diffs front vs. back and emits only changed
\  cells via ANSI escape sequences.
\
\  Screen Descriptor (8 cells = 64 bytes):
\    +0   width         Columns
\    +8   height        Rows
\    +16  front         Address of front buffer (w×h cells)
\    +24  back          Address of back buffer  (w×h cells)
\    +32  cursor-row    Current cursor row (0-based)
\    +40  cursor-col    Current cursor column (0-based)
\    +48  cursor-vis    Cursor visible flag (0 = hidden)
\    +56  dirty         Global dirty flag (0 = clean)
\
\  Each cell is 8 bytes (one CELL-MAKE value), so a buffer for
\  80×24 is 15,360 bytes × 2 = 30,720 bytes (~30 KiB).
\
\  Prefix: SCR- (public), _SCR- (internal)
\  Provider: akashic-tui-screen
\  Dependencies: cell.f, ansi.f, ../text/utf8.f

PROVIDED akashic-tui-screen

REQUIRE cell.f
REQUIRE ansi.f
REQUIRE ../text/utf8.f

\ =====================================================================
\ 1. Descriptor field offsets
\ =====================================================================

 0 CONSTANT _SCR-O-W
 8 CONSTANT _SCR-O-H
16 CONSTANT _SCR-O-FRONT
24 CONSTANT _SCR-O-BACK
32 CONSTANT _SCR-O-CROW
40 CONSTANT _SCR-O-CCOL
48 CONSTANT _SCR-O-CVIS
56 CONSTANT _SCR-O-DIRTY

64 CONSTANT _SCR-DESC-SIZE

\ =====================================================================
\ 2. Current screen pointer
\ =====================================================================

VARIABLE _SCR-CUR   0 _SCR-CUR !

\ Scratch variables (avoid deep stack gymnastics)
VARIABLE _SCR-TMP
VARIABLE _SCR-TMP2
VARIABLE _SCR-TMP3
VARIABLE _SCR-LAST-ROW    \ last physical cursor row during flush
VARIABLE _SCR-LAST-COL    \ last physical cursor col during flush
VARIABLE _SCR-LAST-FG     \ last emitted fg color
VARIABLE _SCR-LAST-BG     \ last emitted bg color
VARIABLE _SCR-LAST-ATTRS  \ last emitted attribute set

\ =====================================================================
\ 3. Internal helpers
\ =====================================================================

\ _SCR-CELLS ( scr -- n )   Total number of cells in one buffer.
: _SCR-CELLS  ( scr -- n )
    DUP _SCR-O-W + @ SWAP _SCR-O-H + @ * ;

\ _SCR-BUF-SIZE ( scr -- bytes )  Buffer size in bytes.
: _SCR-BUF-SIZE  ( scr -- bytes )
    _SCR-CELLS 8 * ;

\ _SCR-IDX ( row col -- offset )  Convert (row,col) to byte offset.
\   offset = (row * width + col) * 8
: _SCR-IDX  ( row col -- offset )
    SWAP _SCR-CUR @ _SCR-O-W + @ * + 8 * ;

VARIABLE _SCR-FILL-VAL

\ _SCR-CELL-FILL ( addr n cell -- )
\   Fill n consecutive cell slots (each 8 bytes) at addr with cell.
\   Note: cannot use >R / R@ across DO..LOOP — loop uses return stack.
: _SCR-CELL-FILL  ( addr n cell -- )
    _SCR-FILL-VAL !
    0 ?DO
        _SCR-FILL-VAL @ OVER !
        8 +
    LOOP
    DROP ;

\ =====================================================================
\ 4. Constructor / destructor
\ =====================================================================

\ SCR-NEW ( w h -- scr )
\   Allocate screen descriptor + two cell buffers.
\   Front buffer is filled with CELL-BLANK, back buffer matches.
: SCR-NEW  ( w h -- scr )
    OVER _SCR-TMP !                    \ save w
    DUP  _SCR-TMP2 !                   \ save h
    2DROP                              \ consume w h from caller

    \ Allocate descriptor (64 bytes)
    _SCR-DESC-SIZE ALLOCATE
    0<> ABORT" SCR-NEW: descriptor alloc failed"
    _SCR-TMP3 !                        \ scr → TMP3

    \ Compute buffer size: w × h × 8
    _SCR-TMP @ _SCR-TMP2 @ * 8 *      ( buf-bytes )

    \ Allocate front buffer
    DUP XMEM? IF XMEM-ALLOT ELSE
        ALLOCATE 0<> ABORT" SCR-NEW: front buf alloc failed"
    THEN
    _SCR-TMP3 @ _SCR-O-FRONT + !

    \ Allocate back buffer
    XMEM? IF XMEM-ALLOT ELSE
        ALLOCATE 0<> ABORT" SCR-NEW: back buf alloc failed"
    THEN
    _SCR-TMP3 @ _SCR-O-BACK + !

    \ Fill both buffers with CELL-BLANK
    _SCR-TMP3 @ _SCR-O-FRONT + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-TMP3 @ _SCR-O-BACK + @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    \ Fill descriptor fields
    _SCR-TMP @  _SCR-TMP3 @ _SCR-O-W     + !
    _SCR-TMP2 @ _SCR-TMP3 @ _SCR-O-H     + !
    0           _SCR-TMP3 @ _SCR-O-CROW   + !
    0           _SCR-TMP3 @ _SCR-O-CCOL   + !
    0           _SCR-TMP3 @ _SCR-O-CVIS   + !
    0           _SCR-TMP3 @ _SCR-O-DIRTY  + !

    _SCR-TMP3 @ ;

\ SCR-FREE ( scr -- )
\   Deallocate screen descriptor.
\   Note: if buffers were XMEM-ALLOT'd, they can't be individually
\   freed (bump allocator).  We FREE the descriptor.
: SCR-FREE  ( scr -- )
    FREE ;

\ =====================================================================
\ 5. Current screen selection
\ =====================================================================

\ SCR-USE ( scr -- )   Set as current screen for drawing words.
: SCR-USE  ( scr -- )
    _SCR-CUR ! ;

\ =====================================================================
\ 6. Accessors (operate on current screen)
\ =====================================================================

: SCR-W   ( -- w )    _SCR-CUR @ _SCR-O-W + @ ;
: SCR-H   ( -- h )    _SCR-CUR @ _SCR-O-H + @ ;

\ =====================================================================
\ 7. Cell read/write
\ =====================================================================

\ SCR-SET ( cell row col -- )   Write cell to back buffer.
: SCR-SET  ( cell row col -- )
    _SCR-IDX _SCR-CUR @ _SCR-O-BACK + @ + ! ;

\ SCR-GET ( row col -- cell )   Read cell from back buffer.
: SCR-GET  ( row col -- cell )
    _SCR-IDX _SCR-CUR @ _SCR-O-BACK + @ + @ ;

\ SCR-FRONT@ ( row col -- cell )  Read cell from front buffer.
: SCR-FRONT@  ( row col -- cell )
    _SCR-IDX _SCR-CUR @ _SCR-O-FRONT + @ + @ ;

\ SCR-FILL ( cell -- )   Fill entire back buffer with given cell.
: SCR-FILL  ( cell -- )
    _SCR-CUR @ _SCR-O-BACK + @
    _SCR-CUR @ _SCR-CELLS
    ROT _SCR-CELL-FILL ;

\ SCR-CLEAR ( -- )   Fill back buffer with CELL-BLANK.
: SCR-CLEAR  ( -- )
    CELL-BLANK SCR-FILL ;

\ =====================================================================
\ 8. Cursor management
\ =====================================================================

\ SCR-CURSOR-AT ( row col -- )   Set logical cursor position.
: SCR-CURSOR-AT  ( row col -- )
    _SCR-CUR @ _SCR-O-CCOL + !
    _SCR-CUR @ _SCR-O-CROW + ! ;

\ SCR-CURSOR-ON ( -- )   Show cursor on next flush.
: SCR-CURSOR-ON  ( -- )
    -1 _SCR-CUR @ _SCR-O-CVIS + ! ;

\ SCR-CURSOR-OFF ( -- )  Hide cursor on next flush.
: SCR-CURSOR-OFF  ( -- )
    0 _SCR-CUR @ _SCR-O-CVIS + ! ;

\ =====================================================================
\ 9. Dirty / force
\ =====================================================================

\ SCR-FORCE ( -- )
\   Force full redraw by clearing the front buffer to an impossible
\   value so every cell differs.
: SCR-FORCE  ( -- )
    _SCR-CUR @ _SCR-O-FRONT + @
    _SCR-CUR @ _SCR-CELLS
    -1 _SCR-CELL-FILL                 \ fill front with -1 (never matches)
    -1 _SCR-CUR @ _SCR-O-DIRTY + ! ;

\ =====================================================================
\ 10. Internal: emit a single cell via ANSI
\ =====================================================================

\ _SCR-MOVE-TO ( row col -- )
\   Emit ANSI-AT if necessary, update tracking state.
\   ANSI-AT uses 1-based row/col.
: _SCR-MOVE-TO  ( row col -- )
    2DUP _SCR-LAST-COL @ = SWAP _SCR-LAST-ROW @ = AND IF
        2DROP EXIT                     \ already there
    THEN
    OVER _SCR-LAST-ROW !
    DUP  _SCR-LAST-COL !
    SWAP 1+ SWAP 1+ ANSI-AT ;         \ row+1, col+1 (1-based)

\ _SCR-EMIT-ATTRS ( cell -- )
\   Emit ANSI attribute/color changes needed for this cell.
\   Compares against last emitted state, emits only diffs.
\   CELL-ATTRS@ returns low-bit attrs (0–15) matching CELL-A-* constants.
: _SCR-EMIT-ATTRS  ( cell -- )
    DUP CELL-ATTRS@ DUP _SCR-LAST-ATTRS @ <> IF
        \ Attributes changed — reset and re-apply
        ANSI-RESET
        DUP CELL-A-BOLD       AND IF ANSI-BOLD      THEN
        DUP CELL-A-DIM        AND IF ANSI-DIM       THEN
        DUP CELL-A-ITALIC     AND IF ANSI-ITALIC    THEN
        DUP CELL-A-UNDERLINE  AND IF ANSI-UNDERLINE THEN
        DUP CELL-A-BLINK      AND IF ANSI-BLINK     THEN
        DUP CELL-A-REVERSE    AND IF ANSI-REVERSE   THEN
        DUP CELL-A-STRIKE     AND IF ANSI-STRIKE    THEN
        _SCR-LAST-ATTRS !
        \ After RESET, fg/bg are default — force re-emit below
        -1 _SCR-LAST-FG !
        -1 _SCR-LAST-BG !
    ELSE
        DROP
    THEN
    DUP CELL-FG@ DUP _SCR-LAST-FG @ <> IF
        DUP ANSI-FG256
        _SCR-LAST-FG !
    ELSE
        DROP
    THEN
    CELL-BG@ DUP _SCR-LAST-BG @ <> IF
        DUP ANSI-BG256
        _SCR-LAST-BG !
    ELSE
        DROP
    THEN ;

\ Scratch buffer for UTF-8 encoding (4 bytes is enough)
CREATE _SCR-UTF8-BUF 4 ALLOT

\ _SCR-EMIT-CHAR ( cell -- )
\   Emit the cell's codepoint as UTF-8.
: _SCR-EMIT-CHAR  ( cell -- )
    CELL-CP@
    DUP 0= IF DROP 32 THEN            \ empty → space
    DUP 128 < IF
        EMIT                           \ ASCII fast path
    ELSE
        _SCR-UTF8-BUF UTF8-ENCODE _SCR-UTF8-BUF -
        _SCR-UTF8-BUF SWAP TYPE        \ emit multi-byte sequence
    THEN ;

\ =====================================================================
\ 11. SCR-FLUSH — differential screen update
\ =====================================================================
\
\  Iterates every cell.  Where front[i] ≠ back[i]:
\    1. Position cursor (skip if consecutive)
\    2. Emit attribute/color changes
\    3. Emit character (UTF-8)
\  After flushing, copy back → front cell by cell.

: SCR-FLUSH  ( -- )
    ANSI-CURSOR-OFF                    \ hide cursor during update

    \ Reset tracking state
    -1 _SCR-LAST-ROW !
    -1 _SCR-LAST-COL !
    -1 _SCR-LAST-FG !
    -1 _SCR-LAST-BG !
     0 _SCR-LAST-ATTRS !

    _SCR-CUR @ _SCR-O-FRONT + @ _SCR-TMP  !   \ front
    _SCR-CUR @ _SCR-O-BACK  + @ _SCR-TMP2 !   \ back

    _SCR-CUR @ _SCR-O-H + @ 0 DO              \ for each row
        _SCR-CUR @ _SCR-O-W + @ 0 DO          \ for each col
            _SCR-TMP2 @ @                      ( back-cell )
            _SCR-TMP  @ @ OVER = 0= IF         \ front ≠ back?
                J I _SCR-MOVE-TO               \ position cursor  (J=row I=col)
                DUP _SCR-EMIT-ATTRS            \ attrs/colors
                DUP _SCR-EMIT-CHAR             \ character
                _SCR-LAST-COL @ 1+
                _SCR-LAST-COL !                \ advance col tracking
            THEN
            \ Copy back → front
            _SCR-TMP2 @ @ _SCR-TMP @ !
            8 _SCR-TMP  +!
            8 _SCR-TMP2 +!
            DROP                               \ drop back-cell
        LOOP
    LOOP

    \ Restore cursor
    _SCR-CUR @ _SCR-O-CVIS + @ IF
        _SCR-CUR @ _SCR-O-CROW + @ 1+
        _SCR-CUR @ _SCR-O-CCOL + @ 1+
        ANSI-AT
        ANSI-CURSOR-ON
    THEN

    ANSI-RESET                         \ clean up attribute state
    0 _SCR-CUR @ _SCR-O-DIRTY + ! ;   \ clear dirty flag

\ =====================================================================
\ 12. SCR-RESIZE
\ =====================================================================
\
\   Resize the screen.  This creates new buffers, copies the
\   overlapping region from old back buffer, then replaces the
\   descriptor fields.  Old buffers are abandoned (XMEM bump).

VARIABLE _SCR-OLD-W
VARIABLE _SCR-OLD-H
VARIABLE _SCR-OLD-BACK
VARIABLE _SCR-NEW-FRONT
VARIABLE _SCR-NEW-BACK
VARIABLE _SCR-COPY-W
VARIABLE _SCR-COPY-H

: SCR-RESIZE  ( w h -- )
    _SCR-CUR @ _SCR-O-W + @ _SCR-OLD-W !
    _SCR-CUR @ _SCR-O-H + @ _SCR-OLD-H !
    _SCR-CUR @ _SCR-O-BACK + @ _SCR-OLD-BACK !

    OVER _SCR-TMP  !                   \ new w
    DUP  _SCR-TMP2 !                   \ new h
    2DROP                              \ consume w h from caller

    \ Allocate new buffers
    _SCR-TMP @ _SCR-TMP2 @ * 8 *      ( bytes )
    DUP XMEM? IF XMEM-ALLOT ELSE
        ALLOCATE 0<> ABORT" SCR-RESIZE: front alloc failed"
    THEN _SCR-NEW-FRONT !

    XMEM? IF XMEM-ALLOT ELSE
        ALLOCATE 0<> ABORT" SCR-RESIZE: back alloc failed"
    THEN _SCR-NEW-BACK !

    \ Fill new buffers with CELL-BLANK
    _SCR-NEW-FRONT @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    _SCR-NEW-BACK @
    _SCR-TMP @ _SCR-TMP2 @ *
    CELL-BLANK _SCR-CELL-FILL

    \ Copy overlapping region from old back → new back
    _SCR-TMP @  _SCR-OLD-W @ MIN _SCR-COPY-W !
    _SCR-TMP2 @ _SCR-OLD-H @ MIN _SCR-COPY-H !

    _SCR-COPY-H @ 0 ?DO
        \ Source row start: old-back + row * old-w * 8
        _SCR-OLD-BACK @ I _SCR-OLD-W @ * 8 * +
        \ Dest row start:  new-back + row * new-w * 8
        _SCR-NEW-BACK @ I _SCR-TMP  @ * 8 * +
        \ Byte count: copy-w * 8
        _SCR-COPY-W @ 8 *
        CMOVE
    LOOP

    \ Update descriptor
    _SCR-TMP @       _SCR-CUR @ _SCR-O-W     + !
    _SCR-TMP2 @      _SCR-CUR @ _SCR-O-H     + !
    _SCR-NEW-FRONT @ _SCR-CUR @ _SCR-O-FRONT + !
    _SCR-NEW-BACK  @ _SCR-CUR @ _SCR-O-BACK  + !

    \ Force full redraw
    SCR-FORCE ;

\ =====================================================================
\ 13. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _scr-guard

' SCR-NEW             CONSTANT _scr-new-xt
' SCR-FREE            CONSTANT _scr-free-xt
' SCR-USE             CONSTANT _scr-use-xt
' SCR-W               CONSTANT _scr-w-xt
' SCR-H               CONSTANT _scr-h-xt
' SCR-SET             CONSTANT _scr-set-xt
' SCR-GET             CONSTANT _scr-get-xt
' SCR-FILL            CONSTANT _scr-fill-xt
' SCR-CLEAR           CONSTANT _scr-clear-xt
' SCR-FLUSH           CONSTANT _scr-flush-xt
' SCR-FORCE           CONSTANT _scr-force-xt
' SCR-RESIZE          CONSTANT _scr-resize-xt
' SCR-CURSOR-AT       CONSTANT _scr-curat-xt
' SCR-CURSOR-ON       CONSTANT _scr-curon-xt
' SCR-CURSOR-OFF      CONSTANT _scr-curoff-xt

: SCR-NEW             _scr-new-xt    _scr-guard WITH-GUARD ;
: SCR-FREE            _scr-free-xt   _scr-guard WITH-GUARD ;
: SCR-USE             _scr-use-xt    _scr-guard WITH-GUARD ;
: SCR-W               _scr-w-xt      _scr-guard WITH-GUARD ;
: SCR-H               _scr-h-xt      _scr-guard WITH-GUARD ;
: SCR-SET             _scr-set-xt    _scr-guard WITH-GUARD ;
: SCR-GET             _scr-get-xt    _scr-guard WITH-GUARD ;
: SCR-FILL            _scr-fill-xt   _scr-guard WITH-GUARD ;
: SCR-CLEAR           _scr-clear-xt  _scr-guard WITH-GUARD ;
: SCR-FLUSH           _scr-flush-xt  _scr-guard WITH-GUARD ;
: SCR-FORCE           _scr-force-xt  _scr-guard WITH-GUARD ;
: SCR-RESIZE          _scr-resize-xt _scr-guard WITH-GUARD ;
: SCR-CURSOR-AT       _scr-curat-xt  _scr-guard WITH-GUARD ;
: SCR-CURSOR-ON       _scr-curon-xt  _scr-guard WITH-GUARD ;
: SCR-CURSOR-OFF      _scr-curoff-xt _scr-guard WITH-GUARD ;
[THEN] [THEN]
