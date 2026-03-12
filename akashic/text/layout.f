\ layout.f — Text layout engine for KDOS / Megapad-64
\
\ Iterates UTF-8 strings, maps codepoints to glyphs via TTF cmap,
\ accumulates advance widths, and provides simple word-wrap line
\ breaking at a configurable pixel width.
\
\ Coordinates are in scaled pixel units (font units × pixel_size / UPEM).
\
\ Prefix: LAY-   (public API)
\         _LAY-  (internal helpers)
\
\ Load with:   REQUIRE layout.f
\
\ === Public API ===
\   LAY-SCALE!       ( pixel-size -- )         set rendering scale
\   LAY-TEXT-WIDTH    ( addr len -- pixels )    measure string width
\   LAY-CHAR-WIDTH   ( codepoint -- pixels )   single character width
\   LAY-LINE-HEIGHT  ( -- pixels )             line height
\   LAY-ASCENDER     ( -- pixels )             scaled ascender
\   LAY-DESCENDER    ( -- pixels )             scaled descender
\
\   LAY-WRAP-WIDTH!  ( pixels -- )             set max line width
\   LAY-WRAP-INIT    ( addr len -- )           begin word-wrap iteration
\   LAY-WRAP-LINE    ( -- addr len flag )      get next line; flag=0 done
\
\   LAY-CURSOR-INIT  ( x y -- )               set cursor position
\   LAY-CURSOR@      ( -- x y )               get current cursor
\   LAY-CURSOR-ADV   ( codepoint -- )          advance cursor by char width
\   LAY-CURSOR-NL    ( -- )                    newline: reset x, advance y

PROVIDED akashic-layout
REQUIRE ../text/utf8.f
REQUIRE ../font/ttf.f

\ =====================================================================
\  Scale state
\ =====================================================================

VARIABLE _LAY-PXSZ    \ pixel size (e.g. 16)
VARIABLE _LAY-UPEM    \ cached UPEM from TTF

: LAY-SCALE!  ( pixel-size -- )
    _LAY-PXSZ !
    TTF-UPEM _LAY-UPEM ! ;

: _LAY-SCALE  ( font-units -- pixels )
    _LAY-PXSZ @ * _LAY-UPEM @ / ;

\ =====================================================================
\  Single character width
\ =====================================================================

: LAY-CHAR-WIDTH  ( codepoint -- pixels )
    TTF-CMAP-LOOKUP TTF-ADVANCE _LAY-SCALE ;

\ =====================================================================
\  String width measurement
\ =====================================================================

VARIABLE _LAY-TW-ACC

: LAY-TEXT-WIDTH  ( addr len -- pixels )
    0 _LAY-TW-ACC !
    BEGIN DUP 0 > WHILE
        UTF8-DECODE              ( cp addr' len' )
        ROT LAY-CHAR-WIDTH       ( addr' len' w )
        _LAY-TW-ACC +!
    REPEAT
    2DROP _LAY-TW-ACC @ ;

\ =====================================================================
\  Vertical metrics
\ =====================================================================

: LAY-ASCENDER    ( -- pixels )  TTF-ASCENDER  _LAY-SCALE ;
: LAY-DESCENDER   ( -- pixels )  TTF-DESCENDER _LAY-SCALE ;
: LAY-LINE-HEIGHT ( -- pixels )
    TTF-ASCENDER TTF-DESCENDER - TTF-LINEGAP + _LAY-SCALE ;

\ =====================================================================
\  Cursor positioning
\ =====================================================================

VARIABLE _LAY-CX   VARIABLE _LAY-CY
VARIABLE _LAY-STARTX

: LAY-CURSOR-INIT  ( x y -- )
    _LAY-CY !  DUP _LAY-CX !  _LAY-STARTX ! ;

: LAY-CURSOR@  ( -- x y )  _LAY-CX @  _LAY-CY @ ;

: LAY-CURSOR-ADV  ( codepoint -- )
    LAY-CHAR-WIDTH _LAY-CX +! ;

: LAY-CURSOR-NL  ( -- )
    _LAY-STARTX @ _LAY-CX !
    LAY-LINE-HEIGHT _LAY-CY +! ;

\ =====================================================================
\  Word-wrap line iterator
\ =====================================================================
\  Returns successive lines from a UTF-8 string, each fitting within
\  the wrap width.  Breaks at spaces or forces a mid-word break.
\
\  Usage:
\    max-width LAY-WRAP-WIDTH!
\    addr len LAY-WRAP-INIT
\    BEGIN LAY-WRAP-LINE WHILE  ... process (addr len) ...  REPEAT

VARIABLE _LAY-WRAP-W                  \ max line width in pixels
VARIABLE _LAY-WR-A                    \ remaining string addr
VARIABLE _LAY-WR-L                    \ remaining string len

: LAY-WRAP-WIDTH!  ( pixels -- )  _LAY-WRAP-W ! ;
: LAY-WRAP-INIT   ( addr len -- )  _LAY-WR-L !  _LAY-WR-A ! ;

\ Scan state for one line
VARIABLE _LAY-LS     \ line start addr
VARIABLE _LAY-ACC    \ accumulated pixel width
VARIABLE _LAY-SA     \ scan addr (current position before decode)
VARIABLE _LAY-SL     \ scan remaining len (before decode)
VARIABLE _LAY-NA     \ next addr (after decode)
VARIABLE _LAY-NL     \ next remaining len (after decode)
VARIABLE _LAY-BA     \ break addr (addr after last space)
VARIABLE _LAY-BL     \ break remaining len at that point
VARIABLE _LAY-BSEEN  \ saw a break opportunity?
VARIABLE _LAY-CP     \ current codepoint

: LAY-WRAP-LINE  ( -- addr len flag )
    _LAY-WR-L @ DUP 0< SWAP 0= OR IF 0 0 0 EXIT THEN

    _LAY-WR-A @ _LAY-LS !
    0 _LAY-ACC !
    0 _LAY-BSEEN !
    _LAY-WR-A @ _LAY-SA !
    _LAY-WR-L @ _LAY-SL !

    BEGIN _LAY-SL @ 0 > WHILE
        \ Decode one codepoint
        _LAY-SA @ _LAY-SL @
        UTF8-DECODE                   ( cp na nl )
        _LAY-NL !  _LAY-NA !  _LAY-CP !

        \ ── Hard newline ──
        _LAY-CP @ 0x0A = IF
            _LAY-LS @
            _LAY-SA @ OVER -           ( line-start line-len )
            _LAY-NA @ _LAY-WR-A !
            _LAY-NL @ _LAY-WR-L !
            -1 EXIT
        THEN

        \ ── Space: record break opportunity (position after space) ──
        _LAY-CP @ 0x20 = IF
            _LAY-NA @ _LAY-BA !
            _LAY-NL @ _LAY-BL !
            1 _LAY-BSEEN !
        THEN

        \ ── Accumulate width ──
        _LAY-CP @ LAY-CHAR-WIDTH _LAY-ACC +!

        \ ── Check overflow ──
        _LAY-ACC @ _LAY-WRAP-W @ > IF
            _LAY-BSEEN @ IF
                \ Break at last space (space consumed)
                _LAY-LS @
                _LAY-BA @ OVER -       ( line-start line-len )
                _LAY-BA @ _LAY-WR-A !
                _LAY-BL @ _LAY-WR-L !
                -1 EXIT
            ELSE
                \ Forced break: at current char (before it)
                _LAY-LS @
                _LAY-SA @ OVER -       ( line-start line-len )
                DUP 0= IF
                    \ At least one char per line to avoid infinite loop
                    DROP
                    _LAY-NA @ OVER -   ( line-start line-len )
                    _LAY-NA @ _LAY-WR-A !
                    _LAY-NL @ _LAY-WR-L !
                ELSE
                    _LAY-SA @ _LAY-WR-A !
                    _LAY-SL @ _LAY-WR-L !
                THEN
                -1 EXIT
            THEN
        THEN

        \ ── Advance scan ──
        _LAY-NA @ _LAY-SA !
        _LAY-NL @ _LAY-SL !
    REPEAT

    \ ── End of string: return remainder as last line ──
    _LAY-LS @
    _LAY-SA @ OVER -                   ( line-start line-len )
    _LAY-SA @ _LAY-WR-A !
    _LAY-SL @ _LAY-WR-L !
    DUP 0 > IF -1 ELSE DROP 0 0 THEN ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _txtlay-guard

' LAY-SCALE!      CONSTANT _lay-scale-s-xt
' LAY-CHAR-WIDTH  CONSTANT _lay-char-width-xt
' LAY-TEXT-WIDTH  CONSTANT _lay-text-width-xt
' LAY-ASCENDER    CONSTANT _lay-ascender-xt
' LAY-DESCENDER   CONSTANT _lay-descender-xt
' LAY-LINE-HEIGHT CONSTANT _lay-line-height-xt
' LAY-CURSOR-INIT CONSTANT _lay-cursor-init-xt
' LAY-CURSOR@     CONSTANT _lay-cursor-at-xt
' LAY-CURSOR-ADV  CONSTANT _lay-cursor-adv-xt
' LAY-CURSOR-NL   CONSTANT _lay-cursor-nl-xt
' LAY-WRAP-WIDTH! CONSTANT _lay-wrap-width-s-xt
' LAY-WRAP-INIT   CONSTANT _lay-wrap-init-xt
' LAY-WRAP-LINE   CONSTANT _lay-wrap-line-xt

: LAY-SCALE!      _lay-scale-s-xt _txtlay-guard WITH-GUARD ;
: LAY-CHAR-WIDTH  _lay-char-width-xt _txtlay-guard WITH-GUARD ;
: LAY-TEXT-WIDTH  _lay-text-width-xt _txtlay-guard WITH-GUARD ;
: LAY-ASCENDER    _lay-ascender-xt _txtlay-guard WITH-GUARD ;
: LAY-DESCENDER   _lay-descender-xt _txtlay-guard WITH-GUARD ;
: LAY-LINE-HEIGHT _lay-line-height-xt _txtlay-guard WITH-GUARD ;
: LAY-CURSOR-INIT _lay-cursor-init-xt _txtlay-guard WITH-GUARD ;
: LAY-CURSOR@     _lay-cursor-at-xt _txtlay-guard WITH-GUARD ;
: LAY-CURSOR-ADV  _lay-cursor-adv-xt _txtlay-guard WITH-GUARD ;
: LAY-CURSOR-NL   _lay-cursor-nl-xt _txtlay-guard WITH-GUARD ;
: LAY-WRAP-WIDTH! _lay-wrap-width-s-xt _txtlay-guard WITH-GUARD ;
: LAY-WRAP-INIT   _lay-wrap-init-xt _txtlay-guard WITH-GUARD ;
: LAY-WRAP-LINE   _lay-wrap-line-xt _txtlay-guard WITH-GUARD ;
[THEN] [THEN]
