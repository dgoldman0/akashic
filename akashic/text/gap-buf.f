\ =================================================================
\  gap-buf.f — Gap Buffer with Integrated Line Index
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: GB- / _GB-
\  Depends on: text/utf8.f
\
\  A gap buffer for efficient text editing.  Insert and delete at
\  the cursor are O(1) amortised.  Moving the cursor is
\  O(distance).  A line-start index is rebuilt after every edit
\  for fast line-number <-> byte-offset mapping.
\
\  The buffer owns its storage and grows automatically.
\
\  Descriptor layout (7 cells = 56 bytes):
\    +0   buf    Byte buffer  (ALLOCATE'd)
\    +8   cap    Total capacity in bytes
\    +16  gs     Gap start = logical cursor position
\    +24  ge     Gap end (exclusive)
\    +32  lidx   Line-start offset array (cells, ALLOCATE'd)
\    +40  lcap   Line-index capacity (entries)
\    +48  lcnt   Line count (always >= 1)
\
\  Buffer physical layout:
\    [content A][.....gap.....][content B]
\    ^0         ^gs            ^ge        ^cap
\
\  Content length  = cap - (ge - gs)
\  Logical byte at pos:
\    pos < gs  -> buf[pos]
\    pos >= gs -> buf[pos + (ge - gs)]
\
\  Public API:
\    GB-NEW        ( cap -- gb )
\    GB-FREE       ( gb -- )
\    GB-LEN        ( gb -- u )       content length
\    GB-CURSOR     ( gb -- n )       cursor position = gs
\    GB-BYTE@      ( pos gb -- c )   logical byte access
\    GB-MOVE!      ( pos gb -- )     move cursor / gap
\    GB-INS        ( addr u gb -- )  insert bytes at cursor
\    GB-INS-CP     ( cp gb -- )      insert codepoint at cursor
\    GB-DEL        ( n gb -- a u )   delete n bytes forward
\    GB-BS         ( n gb -- a u )   delete n bytes backward
\    GB-DEL-CP     ( gb -- a u )     delete 1 cp forward
\    GB-BS-CP      ( gb -- a u )     delete 1 cp backward
\    GB-SET        ( addr u gb -- )  replace all content
\    GB-CLEAR      ( gb -- )
\    GB-FLATTEN    ( dest gb -- u )  copy content to flat buffer
\    GB-PRE        ( gb -- addr u )  content segment before gap
\    GB-POST       ( gb -- addr u )  content segment after gap
\    GB-LINES      ( gb -- n )       line count (>= 1)
\    GB-LINE-OFF   ( line# gb -- off )
\    GB-LINE-LEN   ( line# gb -- u )
\    GB-CURSOR-LINE ( gb -- line# )
\    GB-CURSOR-COL  ( gb -- col )
\ =================================================================

PROVIDED akashic-gap-buf

REQUIRE utf8.f

\ =====================================================================
\  S1 -- Struct Offsets
\ =====================================================================

 0 CONSTANT _GB-O-BUF
 8 CONSTANT _GB-O-CAP
16 CONSTANT _GB-O-GS
24 CONSTANT _GB-O-GE
32 CONSTANT _GB-O-LIDX
40 CONSTANT _GB-O-LCAP
48 CONSTANT _GB-O-LCNT
56 CONSTANT _GB-DESC-SZ

\ =====================================================================
\  S2 -- Module Temporaries
\ =====================================================================

VARIABLE _GB-T           \ current gb handle
VARIABLE _GB-D           \ delta for move / grow

\ =====================================================================
\  S3 -- Basic Queries
\ =====================================================================

: GB-LEN  ( gb -- u )
    DUP _GB-O-CAP + @
    OVER _GB-O-GE + @  ROT _GB-O-GS + @  -  - ;

: GB-CURSOR  ( gb -- n )
    _GB-O-GS + @ ;

: GB-LINES  ( gb -- n )
    _GB-O-LCNT + @ ;

: GB-LINE-OFF  ( line# gb -- off )
    _GB-O-LIDX + @  SWAP CELLS +  @ ;

: _GB-GAP  ( gb -- u )
    DUP _GB-O-GE + @  SWAP _GB-O-GS + @  - ;

\ =====================================================================
\  S4 -- Byte Access
\ =====================================================================

\ GB-BYTE@ ( pos gb -- c )
\   Access logical byte at position pos.
: GB-BYTE@  ( pos gb -- c )
    >R
    DUP R@ _GB-O-GS + @ < IF
        R> _GB-O-BUF + @ + C@
    ELSE
        R@ _GB-O-GE + @  R@ _GB-O-GS + @ -  +
        R> _GB-O-BUF + @ + C@
    THEN ;

\ =====================================================================
\  S5 -- Segment Access
\ =====================================================================

\ GB-PRE ( gb -- addr u )  content before gap
: GB-PRE  ( gb -- addr u )
    DUP _GB-O-BUF + @
    SWAP _GB-O-GS + @ ;

\ GB-POST ( gb -- addr u )  content after gap
: GB-POST  ( gb -- addr u )
    DUP _GB-O-BUF + @  OVER _GB-O-GE + @  +
    SWAP DUP _GB-O-CAP + @  SWAP _GB-O-GE + @  - ;

\ =====================================================================
\  S6 -- Constructor / Destructor
\ =====================================================================

256 CONSTANT _GB-LIDX-INIT    \ initial line-index capacity

: GB-NEW  ( cap -- gb )
    _GB-DESC-SZ ALLOCATE 0<> ABORT" GB-NEW: desc"
    >R                                 ( cap  R: gb )
    DUP ALLOCATE 0<> ABORT" GB-NEW: buf"
    R@ _GB-O-BUF + !                  ( cap  R: gb )
    DUP R@ _GB-O-CAP + !              \ cap
    0 R@ _GB-O-GS + !                 \ gs = 0
    R@ _GB-O-GE + !                   \ ge = cap (all gap)
    _GB-LIDX-INIT CELLS ALLOCATE 0<> ABORT" GB-NEW: lidx"
    R@ _GB-O-LIDX + !
    _GB-LIDX-INIT R@ _GB-O-LCAP + !
    1 R@ _GB-O-LCNT + !
    0 R@ _GB-O-LIDX + @ !             \ line 0 at offset 0
    R> ;

: GB-FREE  ( gb -- )
    DUP _GB-O-BUF + @ FREE DROP
    DUP _GB-O-LIDX + @ FREE DROP
    FREE DROP ;

\ =====================================================================
\  S7 -- Growth
\ =====================================================================

\ _GB-LIDX-GROW ( -- )   double the line-index array.  Uses _GB-T.
: _GB-LIDX-GROW  ( -- )
    _GB-T @ _GB-O-LCAP + @ 2 *     ( new-lcap )
    DUP CELLS
    _GB-T @ _GB-O-LIDX + @ SWAP RESIZE 0<> ABORT" lidx grow"
    _GB-T @ _GB-O-LIDX + !
    _GB-T @ _GB-O-LCAP + ! ;

\ _GB-GROW ( needed -- )   ensure gap >= needed bytes.  Uses _GB-T.
: _GB-GROW  ( needed -- )
    _GB-T @ _GB-GAP  OVER >= IF DROP EXIT THEN
    \ new-cap = max( 2*cap, cap + needed )
    _GB-T @ _GB-O-CAP + @ 2 *                    ( needed nc1 )
    _GB-T @ _GB-O-CAP + @ 2 PICK +               ( needed nc1 nc2 )
    MAX NIP                                       ( new-cap )
    \ RESIZE buffer
    _GB-T @ _GB-O-BUF + @ OVER RESIZE
    0<> ABORT" _GB-GROW: resize"
    _GB-T @ _GB-O-BUF + !                        ( new-cap )
    \ delta = new-cap - old-cap
    DUP _GB-T @ _GB-O-CAP + @ -  _GB-D !         ( new-cap )
    \ Move post-gap content to end of new buffer
    \ CMOVE> buf+ge -> buf+ge+delta, count = old-cap - ge
    _GB-T @ _GB-O-BUF + @  _GB-T @ _GB-O-GE + @  +   ( nc src )
    DUP _GB-D @ +                                      ( nc src dst )
    _GB-T @ _GB-O-CAP + @  _GB-T @ _GB-O-GE + @  -   ( nc src dst count )
    DUP 0> IF CMOVE> ELSE DROP 2DROP THEN              ( nc )
    \ Update ge and cap
    _GB-D @ _GB-T @ _GB-O-GE +!
    _GB-T @ _GB-O-CAP + ! ;

\ =====================================================================
\  S8 -- Line Index Rebuild
\ =====================================================================

\ _GB-REBUILD-LINES ( -- )   Full rebuild.  Uses _GB-T.
: _GB-REBUILD-LINES  ( -- )
    1 _GB-T @ _GB-O-LCNT + !
    0 _GB-T @ _GB-O-LIDX + @ !            \ line 0 at offset 0
    \ --- pre-gap: physical [0..gs), logical = physical ---
    _GB-T @ _GB-O-GS + @ 0 ?DO
        _GB-T @ _GB-O-BUF + @ I + C@ 10 = IF
            _GB-T @ _GB-O-LCNT + @
            _GB-T @ _GB-O-LCAP + @ >= IF _GB-LIDX-GROW THEN
            I 1+
            _GB-T @ _GB-O-LIDX + @
            _GB-T @ _GB-O-LCNT + @ CELLS + !
            1 _GB-T @ _GB-O-LCNT +!
        THEN
    LOOP
    \ --- post-gap: physical [ge..cap), logical = phys - ge + gs ---
    _GB-T @ _GB-O-CAP + @  _GB-T @ _GB-O-GE + @  ?DO
        _GB-T @ _GB-O-BUF + @ I + C@ 10 = IF
            _GB-T @ _GB-O-LCNT + @
            _GB-T @ _GB-O-LCAP + @ >= IF _GB-LIDX-GROW THEN
            I  _GB-T @ _GB-O-GE + @ -
            _GB-T @ _GB-O-GS + @ +  1+
            _GB-T @ _GB-O-LIDX + @
            _GB-T @ _GB-O-LCNT + @ CELLS + !
            1 _GB-T @ _GB-O-LCNT +!
        THEN
    LOOP ;

\ =====================================================================
\  S9 -- Gap Movement
\ =====================================================================

\ GB-MOVE! ( pos gb -- )
\   Move cursor (gap) to logical position pos.
: GB-MOVE!  ( pos gb -- )
    _GB-T !
    0 MAX  _GB-T @ GB-LEN MIN          ( pos-clamped )
    DUP _GB-T @ _GB-O-GS + @ = IF DROP EXIT THEN
    DUP _GB-T @ _GB-O-GS + @ < IF
        \ --- move left ---
        \ delta = gs - pos
        _GB-T @ _GB-O-GS + @ OVER - _GB-D !    ( pos )
        \ CMOVE> buf+pos -> buf+(ge-delta), delta bytes
        DUP _GB-T @ _GB-O-BUF + @ +                            \ src
        _GB-T @ _GB-O-GE + @ _GB-D @ -  _GB-T @ _GB-O-BUF + @ + \ dst
        _GB-D @  CMOVE>                                          ( pos )
        _GB-T @ _GB-O-GS + !           \ gs = pos
        _GB-D @ NEGATE _GB-T @ _GB-O-GE +!   \ ge -= delta
    ELSE
        \ --- move right ---
        \ delta = pos - gs
        DUP _GB-T @ _GB-O-GS + @ - _GB-D !    ( pos )
        \ CMOVE buf+ge -> buf+gs, delta bytes
        _GB-T @ _GB-O-BUF + @ _GB-T @ _GB-O-GE + @  +   \ src
        _GB-T @ _GB-O-BUF + @ _GB-T @ _GB-O-GS + @ +    \ dst
        _GB-D @  CMOVE                                     ( pos )
        _GB-T @ _GB-O-GS + !           \ gs = pos
        _GB-D @ _GB-T @ _GB-O-GE +!    \ ge += delta
    THEN ;

\ =====================================================================
\  S10 -- Insert
\ =====================================================================

CREATE _GB-CP-BUF 4 ALLOT      \ scratch for single-codepoint encode

\ GB-INS ( addr u gb -- )
\   Insert u bytes at cursor.  Gap grows if needed.
: GB-INS  ( addr u gb -- )
    _GB-T !
    DUP 0= IF 2DROP EXIT THEN
    DUP _GB-GROW                        \ ensure space
    \ Copy into gap at buf+gs
    _GB-T @ _GB-O-BUF + @
    _GB-T @ _GB-O-GS + @ +             ( addr u dest )
    SWAP >R                             ( addr dest  R: u )
    R@ CMOVE                            ( R: u )
    R> _GB-T @ _GB-O-GS +!             \ gs += u
    _GB-T @ _GB-REBUILD-LINES ;

\ GB-INS-CP ( cp gb -- )
\   Insert a single Unicode codepoint (UTF-8 encoded) at cursor.
: GB-INS-CP  ( cp gb -- )
    >R
    _GB-CP-BUF UTF8-ENCODE
    _GB-CP-BUF -                        ( byte-count )
    _GB-CP-BUF SWAP R> GB-INS ;

\ =====================================================================
\  S11 -- Delete
\ =====================================================================

\ GB-DEL ( n gb -- del-addr del-u )
\   Delete n bytes forward from cursor.  Returns a pointer to
\   the deleted bytes (valid until next mutating call).
: GB-DEL  ( n gb -- del-addr del-u )
    _GB-T !
    \ Clamp n to bytes available after cursor
    _GB-T @ GB-LEN  _GB-T @ _GB-O-GS + @  -  MIN
    DUP 0= IF
        _GB-T @ _GB-O-BUF + @  SWAP EXIT    \ empty result
    THEN
    \ Deleted bytes sit at buf+ge (about to become inner gap)
    _GB-T @ _GB-O-BUF + @  _GB-T @ _GB-O-GE + @  +  ( n del-addr )
    SWAP DUP >R                            ( del-addr n  R: n )
    \ Expand gap forward: ge += n
    _GB-T @ _GB-O-GE +!
    _GB-T @ _GB-REBUILD-LINES
    R> ;                                  ( del-addr del-u )

\ GB-BS ( n gb -- del-addr del-u )
\   Delete n bytes backward from cursor.  Returns pointer to
\   deleted bytes (valid until next mutating call).
: GB-BS  ( n gb -- del-addr del-u )
    _GB-T !
    _GB-T @ _GB-O-GS + @  MIN            \ clamp
    DUP 0= IF
        _GB-T @ _GB-O-BUF + @  SWAP EXIT
    THEN
    DUP >R                                ( n  R: n )
    \ Deleted bytes at buf+(gs-n) -- will be inside gap after
    NEGATE _GB-T @ _GB-O-GS +!           \ gs -= n
    _GB-T @ _GB-O-BUF + @
    _GB-T @ _GB-O-GS + @ +               ( del-addr )
    _GB-T @ _GB-REBUILD-LINES
    R> ;                                  ( del-addr del-u )

\ GB-DEL-CP ( gb -- del-addr del-u )
\   Delete one codepoint forward.
: GB-DEL-CP  ( gb -- del-addr del-u )
    DUP >R
    R@ GB-CURSOR  R@ GB-LEN >= IF
        R> DROP 0 0 EXIT                  \ at end
    THEN
    \ Byte at buf+ge is the lead byte of next codepoint
    R@ _GB-O-BUF + @  R@ _GB-O-GE + @  +  C@
    _UTF8-SEQLEN DUP 0= IF DROP 1 THEN
    R> GB-DEL ;

\ GB-BS-CP ( gb -- del-addr del-u )
\   Delete one codepoint backward.
: GB-BS-CP  ( gb -- del-addr del-u )
    DUP >R
    R@ GB-CURSOR 0= IF
        R> DROP 0 0 EXIT                  \ at start
    THEN
    \ Scan backward over continuation bytes to find CP start
    R@ _GB-O-GS + @ 1-                   ( phys-pos )
    BEGIN
        DUP 0 > IF
            DUP R@ _GB-O-BUF + @ + C@ _UTF8-CONT?
        ELSE 0 THEN
    WHILE 1- REPEAT                       ( start-phys )
    R@ _GB-O-GS + @ SWAP -               ( byte-count )
    R> GB-BS ;

\ =====================================================================
\  S12 -- Bulk Content Operations
\ =====================================================================

\ GB-CLEAR ( gb -- )
: GB-CLEAR  ( gb -- )
    DUP _GB-O-CAP + @ OVER _GB-O-GE + !   \ ge = cap
    0 OVER _GB-O-GS + !                    \ gs = 0
    1 OVER _GB-O-LCNT + !
    _GB-O-LIDX + @ 0 SWAP ! ;             \ line 0 at 0

\ GB-SET ( addr u gb -- )
\   Replace all content.  Grows buffer if needed.
: GB-SET  ( addr u gb -- )
    _GB-T !
    \ Grow buffer if content exceeds capacity
    DUP _GB-T @ _GB-O-CAP + @ > IF
        DUP 256 +                           ( addr u new-cap )
        _GB-T @ _GB-O-BUF + @ OVER RESIZE
        0<> ABORT" GB-SET: resize"
        _GB-T @ _GB-O-BUF + !              ( addr u new-cap )
        _GB-T @ _GB-O-CAP + !              ( addr u )
    THEN
    \ Copy content to buf[0..]
    SWAP  _GB-T @ _GB-O-BUF + @            ( u addr buf )
    ROT DUP >R  CMOVE                      ( R: u )
    \ gs = u, ge = cap
    R> _GB-T @ _GB-O-GS + !
    _GB-T @ _GB-O-CAP + @  _GB-T @ _GB-O-GE + !
    _GB-T @ _GB-REBUILD-LINES ;

\ GB-FLATTEN ( dest gb -- u )
\   Copy content to a flat buffer.  Returns content length.
: GB-FLATTEN  ( dest gb -- u )
    _GB-T !
    \ Pre-gap -> dest
    _GB-T @ _GB-O-BUF + @  OVER
    _GB-T @ _GB-O-GS + @  CMOVE
    _GB-T @ _GB-O-GS + @ +                 ( dest' )
    \ Post-gap -> dest'
    _GB-T @ _GB-O-BUF + @  _GB-T @ _GB-O-GE + @  +
    SWAP
    _GB-T @ _GB-O-CAP + @  _GB-T @ _GB-O-GE + @  -
    CMOVE
    _GB-T @ GB-LEN ;

\ =====================================================================
\  S13 -- Line Queries
\ =====================================================================

\ GB-LINE-LEN ( line# gb -- u )
\   Byte length of a line (excluding the newline).
: GB-LINE-LEN  ( line# gb -- u )
    _GB-T !
    DUP 1+ _GB-T @ GB-LINES < IF
        \ Not last line: next_off - this_off - 1
        DUP 1+  _GB-T @ GB-LINE-OFF
        SWAP    _GB-T @ GB-LINE-OFF  -  1-
    ELSE
        \ Last line: content_len - this_off
        _GB-T @ GB-LINE-OFF
        _GB-T @ GB-LEN SWAP -
    THEN ;

\ --- Binary search helpers for GB-CURSOR-LINE ---
VARIABLE _GB-BS-LO   VARIABLE _GB-BS-HI   VARIABLE _GB-BS-MID

\ GB-CURSOR-LINE ( gb -- line# )
\   Line number containing the cursor (0-based).
: GB-CURSOR-LINE  ( gb -- line# )
    _GB-T !
    _GB-T @ GB-CURSOR                     ( pos )
    0 _GB-BS-LO !
    _GB-T @ GB-LINES 1- _GB-BS-HI !
    BEGIN _GB-BS-LO @ _GB-BS-HI @ <= WHILE
        _GB-BS-LO @ _GB-BS-HI @ + 2 / _GB-BS-MID !
        _GB-BS-MID @  _GB-T @ GB-LINE-OFF   ( pos mid-off )
        OVER > IF
            _GB-BS-MID @ 1- _GB-BS-HI !
        ELSE
            _GB-BS-MID @ 1+ _GB-BS-LO !
        THEN
    REPEAT
    DROP
    _GB-BS-LO @ 1- 0 MAX ;

\ GB-CURSOR-COL ( gb -- col )
\   Column of cursor as codepoint count from start of line.
: GB-CURSOR-COL  ( gb -- col )
    _GB-T !
    _GB-T @ GB-CURSOR-LINE  _GB-T @ GB-LINE-OFF  ( off )
    0                                             ( off col )
    BEGIN OVER _GB-T @ GB-CURSOR < WHILE
        OVER _GB-T @ GB-BYTE@
        _UTF8-SEQLEN DUP 0= IF DROP 1 THEN       ( off col seqlen )
        >R 1+  SWAP R> + SWAP                    ( off+seqlen col+1 )
    REPEAT
    NIP ;

\ =====================================================================
\  S14 -- Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _gb-guard

' GB-NEW         CONSTANT _gb-new-xt
' GB-FREE        CONSTANT _gb-free-xt
' GB-MOVE!       CONSTANT _gb-move-xt
' GB-INS         CONSTANT _gb-ins-xt
' GB-INS-CP      CONSTANT _gb-inscp-xt
' GB-DEL         CONSTANT _gb-del-xt
' GB-BS          CONSTANT _gb-bs-xt
' GB-DEL-CP      CONSTANT _gb-delcp-xt
' GB-BS-CP       CONSTANT _gb-bscp-xt
' GB-SET         CONSTANT _gb-set-xt
' GB-CLEAR       CONSTANT _gb-clear-xt
' GB-FLATTEN     CONSTANT _gb-flat-xt
' GB-CURSOR-LINE CONSTANT _gb-cline-xt
' GB-CURSOR-COL  CONSTANT _gb-ccol-xt

: GB-NEW         _gb-new-xt    _gb-guard WITH-GUARD ;
: GB-FREE        _gb-free-xt   _gb-guard WITH-GUARD ;
: GB-MOVE!       _gb-move-xt   _gb-guard WITH-GUARD ;
: GB-INS         _gb-ins-xt    _gb-guard WITH-GUARD ;
: GB-INS-CP      _gb-inscp-xt  _gb-guard WITH-GUARD ;
: GB-DEL         _gb-del-xt    _gb-guard WITH-GUARD ;
: GB-BS          _gb-bs-xt     _gb-guard WITH-GUARD ;
: GB-DEL-CP      _gb-delcp-xt  _gb-guard WITH-GUARD ;
: GB-BS-CP       _gb-bscp-xt   _gb-guard WITH-GUARD ;
: GB-SET         _gb-set-xt    _gb-guard WITH-GUARD ;
: GB-CLEAR       _gb-clear-xt  _gb-guard WITH-GUARD ;
: GB-FLATTEN     _gb-flat-xt   _gb-guard WITH-GUARD ;
: GB-CURSOR-LINE _gb-cline-xt  _gb-guard WITH-GUARD ;
: GB-CURSOR-COL  _gb-ccol-xt   _gb-guard WITH-GUARD ;
[THEN] [THEN]
