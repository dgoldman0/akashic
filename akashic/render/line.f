\ line.f — Line Box Layout for inline formatting context
\ Part of Akashic render library for Megapad-64 / KDOS
\
\ Breaks a linked list of pre-measured inline runs into line boxes
\ that fit within a given available width.  Each line box tracks its
\ runs, height, baseline, and total width.
\
\ Runs are created externally (by layout.f or test code) with explicit
\ width / height / ascender values — no font dependency here.
\
\ Prefix: LINE-  (public API)
\         _LN-   (internal helpers)
\
\ Load with:   REQUIRE render/line.f
\
\ Dependencies:
\   akashic-box  — box descriptor accessors (for box-type runs)
\
\ === Public API ===
\   LINE-RUN-TEXT   ( width height ascender -- run )
\                   Create a text-type inline run
\   LINE-RUN-BOX    ( width height ascender -- run )
\                   Create a box-type inline run
\   LINE-RUN-FREE   ( run -- )        Free a single run
\   LINE-BREAK      ( runs avail-w -- lines )
\                   Break run list into line boxes
\   LINE-ALIGN      ( line avail-w text-align -- )
\                   Horizontally align runs within a line
\   LINE-BASELINE   ( line -- y )     Baseline offset from line top
\   LINE-HEIGHT     ( line -- h )     Line box height
\   LINE-FREE       ( lines -- )      Free all lines and their runs
\
\   Run accessors:
\   LINE-RUN-W      ( run -- w )      Run width
\   LINE-RUN-H      ( run -- h )      Run height
\   LINE-RUN-ASC    ( run -- asc )    Run ascender
\   LINE-RUN-X      ( run -- x )      Run X position
\   LINE-RUN-NEXT   ( run -- run|0 )  Next run in line
\   LINE-RUN-TYPE   ( run -- type )   0=text, 1=box
\
\   Line accessors:
\   LINE-Y          ( line -- y )     Line Y position
\   LINE-W          ( line -- w )     Line total width
\   LINE-NEXT       ( line -- line|0) Next line box
\   LINE-FIRST-RUN  ( line -- run|0 ) First run on this line
\
\   Line setters:
\   LINE-Y!         ( y line -- )     Set line Y position
\
\   Constants:
\   LINE-T-TEXT     Text run type (0)
\   LINE-T-BOX     Box run type (1)
\   LINE-A-LEFT    Left align (0)
\   LINE-A-CENTER  Center align (1)
\   LINE-A-RIGHT   Right align (2)

REQUIRE box.f

PROVIDED akashic-line

\ =====================================================================
\  Constants
\ =====================================================================

0 CONSTANT LINE-T-TEXT
1 CONSTANT LINE-T-BOX

0 CONSTANT LINE-A-LEFT
1 CONSTANT LINE-A-CENTER
2 CONSTANT LINE-A-RIGHT

\ =====================================================================
\  Inline run descriptor  (8 cells = 64 bytes)
\ =====================================================================
\
\  +0   type       0=text, 1=box
\  +8   width      run width in px
\  +16  height     run height in px
\  +24  ascender   distance from top to baseline
\  +32  x          horizontal position (set by LINE-BREAK / LINE-ALIGN)
\  +40  next       next run (in input list, then within a line)
\  +48  data       text: string addr / box: box pointer
\  +56  data-len   text: string length / box: unused

72 CONSTANT _LN-RUN-SIZE

\ Run field accessors ( run -- addr )
: _LR.TYPE  ( run -- addr )         ;       \ +0
: _LR.W     ( run -- addr )  8 + ;          \ +8
: _LR.H     ( run -- addr )  16 + ;         \ +16
: _LR.ASC   ( run -- addr )  24 + ;         \ +24
: _LR.X     ( run -- addr )  32 + ;         \ +32
: _LR.NEXT  ( run -- addr )  40 + ;         \ +40
: _LR.DATA  ( run -- addr )  48 + ;         \ +48
: _LR.DLEN  ( run -- addr )  56 + ;         \ +56
: _LR.SRCBOX ( run -- addr )  64 + ;        \ +64  source box

\ Public run accessors ( run -- value )
: LINE-RUN-TYPE  ( run -- type )   _LR.TYPE @ ;
: LINE-RUN-W     ( run -- w )      _LR.W @ ;
: LINE-RUN-H     ( run -- h )      _LR.H @ ;
: LINE-RUN-ASC   ( run -- asc )    _LR.ASC @ ;
: LINE-RUN-X     ( run -- x )      _LR.X @ ;
: LINE-RUN-NEXT  ( run -- run|0 )  _LR.NEXT @ ;
: LINE-RUN-DATA  ( run -- addr )   _LR.DATA @ ;
: LINE-RUN-DLEN  ( run -- len )    _LR.DLEN @ ;
: LINE-RUN-SRCBOX ( run -- box )   _LR.SRCBOX @ ;

\ =====================================================================
\  Line box descriptor  (6 cells = 48 bytes)
\ =====================================================================
\
\  +0   y          Y position of line box
\  +8   height     Line height (max-asc + max-desc)
\  +16  baseline   Baseline offset from top (= max ascender)
\  +24  first-run  First run on this line
\  +32  width      Total width of all runs
\  +40  next       Next line box

48 CONSTANT _LN-LINE-SIZE

\ Line field accessors ( line -- addr )
: _LL.Y     ( line -- addr )         ;      \ +0
: _LL.H     ( line -- addr )  8 + ;         \ +8
: _LL.BL    ( line -- addr )  16 + ;        \ +16
: _LL.FIRST ( line -- addr )  24 + ;        \ +24
: _LL.W     ( line -- addr )  32 + ;        \ +32
: _LL.NEXT  ( line -- addr )  40 + ;        \ +40

\ Public line accessors ( line -- value )
: LINE-Y          ( line -- y )       _LL.Y @ ;
: LINE-HEIGHT     ( line -- h )       _LL.H @ ;
: LINE-BASELINE   ( line -- y )       _LL.BL @ ;
: LINE-FIRST-RUN  ( line -- run|0 )   _LL.FIRST @ ;
: LINE-W          ( line -- w )       _LL.W @ ;
: LINE-NEXT       ( line -- line|0 )  _LL.NEXT @ ;

\ Line setter
: LINE-Y!  ( y line -- )  _LL.Y ! ;

\ =====================================================================
\  Run creation
\ =====================================================================

VARIABLE _LRC-RUN

\ Internal: allocate and zero a run
: _LN-ALLOC-RUN  ( -- run )
    _LN-RUN-SIZE ALLOCATE
    0<> ABORT" line.f: run alloc failed"
    DUP _LRC-RUN !
    _LN-RUN-SIZE 0 FILL
    _LRC-RUN @ ;

: LINE-RUN-TEXT  ( width height ascender -- run )
    _LN-ALLOC-RUN _LRC-RUN !
    _LRC-RUN @ _LR.ASC !
    _LRC-RUN @ _LR.H !
    _LRC-RUN @ _LR.W !
    LINE-T-TEXT _LRC-RUN @ _LR.TYPE !
    _LRC-RUN @ ;

: LINE-RUN-BOX  ( width height ascender -- run )
    _LN-ALLOC-RUN _LRC-RUN !
    _LRC-RUN @ _LR.ASC !
    _LRC-RUN @ _LR.H !
    _LRC-RUN @ _LR.W !
    LINE-T-BOX _LRC-RUN @ _LR.TYPE !
    _LRC-RUN @ ;

: LINE-RUN-FREE  ( run -- )
    FREE ;

\ =====================================================================
\  Run list helpers
\ =====================================================================

\ Append a run to the end of a run list.
\ ( run list-head -- new-head )
\ If list-head is 0, run becomes the head.
VARIABLE _LNA-CUR

: LINE-RUN-APPEND  ( run list-head -- new-head )
    DUP 0= IF DROP EXIT THEN    \ list empty → run is head
    DUP _LNA-CUR !              \ save head
    \ Walk to tail
    BEGIN
        _LNA-CUR @ _LR.NEXT @ 0<> WHILE
        _LNA-CUR @ _LR.NEXT @  _LNA-CUR !
    REPEAT
    \ Link run at tail
    SWAP _LNA-CUR @ _LR.NEXT !
    \ Return original head (still on stack)
    ;

\ =====================================================================
\  LINE-BREAK — Break runs into line boxes
\ =====================================================================
\  ( runs avail-w -- lines )
\  Walks the input run list.  Packs runs onto line boxes greedily.
\  A run that would overflow starts a new line — unless the current
\  line is empty (single oversized run gets its own line).
\
\  All variables prefixed _LB- to avoid clashes.

VARIABLE _LB-AW        \ available width
VARIABLE _LB-RUN       \ current run being processed
VARIABLE _LB-FIRST     \ first line box (result)
VARIABLE _LB-LINE      \ current line being built
VARIABLE _LB-PREV      \ previous line (for linking)
VARIABLE _LB-LW        \ current line accumulated width
VARIABLE _LB-LFIRST    \ first run on current line
VARIABLE _LB-LLAST     \ last run on current line
VARIABLE _LB-MAXA      \ max ascender on current line
VARIABLE _LB-MAXD      \ max descender on current line
VARIABLE _LB-TMP       \ scratch

\ Internal: start a new (empty) current line
: _LB-NEW-LINE  ( -- )
    0 _LB-LW !
    0 _LB-LFIRST !
    0 _LB-LLAST !
    0 _LB-MAXA !
    0 _LB-MAXD ! ;

\ Internal: add current run to the current line
: _LB-ADD-RUN  ( -- )
    _LB-RUN @ _LR.NEXT @  _LB-TMP !  \ save original next
    0 _LB-RUN @ _LR.NEXT !            \ detach from input list

    \ Set run X position
    _LB-LW @ _LB-RUN @ _LR.X !

    \ Link into current line's run list
    _LB-LLAST @ 0<> IF
        _LB-RUN @ _LB-LLAST @ _LR.NEXT !
    ELSE
        _LB-RUN @ _LB-LFIRST !
    THEN
    _LB-RUN @ _LB-LLAST !

    \ Accumulate width
    _LB-RUN @ _LR.W @  _LB-LW +!

    \ Track max ascender
    _LB-RUN @ _LR.ASC @  _LB-MAXA @ > IF
        _LB-RUN @ _LR.ASC @  _LB-MAXA !
    THEN

    \ Track max descender (height - ascender)
    _LB-RUN @ _LR.H @  _LB-RUN @ _LR.ASC @ -
    DUP _LB-MAXD @ > IF _LB-MAXD ! ELSE DROP THEN

    \ Advance to next run from saved pointer
    _LB-TMP @ _LB-RUN ! ;

\ Internal: finalize the current line — allocate line box, link it
: _LB-FINISH-LINE  ( -- )
    _LB-LFIRST @ 0= IF EXIT THEN  \ nothing on this line

    _LN-LINE-SIZE ALLOCATE
    0<> ABORT" line.f: line alloc failed"
    _LB-LINE !

    \ Fill line descriptor
    0                  _LB-LINE @ _LL.Y !        \ Y set later
    _LB-MAXA @ _LB-MAXD @ +  _LB-LINE @ _LL.H !
    _LB-MAXA @        _LB-LINE @ _LL.BL !
    _LB-LFIRST @      _LB-LINE @ _LL.FIRST !
    _LB-LW @          _LB-LINE @ _LL.W !
    0                  _LB-LINE @ _LL.NEXT !

    \ Link to previous line
    _LB-PREV @ 0<> IF
        _LB-LINE @ _LB-PREV @ _LL.NEXT !
    ELSE
        _LB-LINE @ _LB-FIRST !
    THEN
    _LB-LINE @ _LB-PREV ! ;

: LINE-BREAK  ( runs avail-w -- lines )
    _LB-AW !
    _LB-RUN !
    0 _LB-FIRST !
    0 _LB-PREV !
    _LB-NEW-LINE

    BEGIN
        _LB-RUN @ 0<> WHILE

        \ Would this run overflow current line?
        _LB-LW @ _LB-RUN @ _LR.W @ +  _LB-AW @ > IF
            \ Only break if line already has content
            _LB-LFIRST @ 0<> IF
                _LB-FINISH-LINE
                _LB-NEW-LINE
                \ Don't advance _LB-RUN — re-test on new line
            ELSE
                \ Empty line + oversized run → put it alone
                _LB-ADD-RUN
                _LB-FINISH-LINE
                _LB-NEW-LINE
            THEN
        ELSE
            _LB-ADD-RUN
        THEN
    REPEAT

    \ Finish last line if any runs remain
    _LB-FINISH-LINE

    _LB-FIRST @ ;

\ =====================================================================
\  LINE-ALIGN — Horizontally align runs within a line
\ =====================================================================
\  ( line avail-w text-align -- )
\  0=left (no-op), 1=center, 2=right.

VARIABLE _LA-LINE
VARIABLE _LA-OFF
VARIABLE _LA-RUN

: LINE-ALIGN  ( line avail-w text-align -- )
    DUP LINE-A-LEFT = IF
        DROP 2DROP EXIT          \ left alignment: nothing to do
    THEN

    _LA-OFF !                    \ temporarily store align type
    OVER LINE-W -                \ ( line gap )
    DUP 1 < IF
        2DROP EXIT               \ no room to shift
    THEN

    _LA-OFF @ LINE-A-CENTER = IF
        2 /                      \ center: half gap
    THEN
    _LA-OFF !                    \ now _LA-OFF = pixel offset

    \ Walk runs, shift X by offset
    _LA-LINE !
    _LA-LINE @ LINE-FIRST-RUN  _LA-RUN !
    BEGIN
        _LA-RUN @ 0<> WHILE
        _LA-OFF @  _LA-RUN @ _LR.X +!
        _LA-RUN @ _LR.NEXT @  _LA-RUN !
    REPEAT ;

\ =====================================================================
\  LINE-FREE — Free all line boxes and their runs
\ =====================================================================
\  ( lines -- )

VARIABLE _LF-LINE
VARIABLE _LF-NEXT
VARIABLE _LF-RUN
VARIABLE _LF-RNXT

: LINE-FREE  ( lines -- )
    _LF-LINE !
    BEGIN
        _LF-LINE @ 0<> WHILE
        _LF-LINE @ _LL.NEXT @  _LF-NEXT !

        \ Free all runs on this line
        _LF-LINE @ _LL.FIRST @  _LF-RUN !
        BEGIN
            _LF-RUN @ 0<> WHILE
            _LF-RUN @ _LR.NEXT @  _LF-RNXT !
            _LF-RUN @ LINE-RUN-FREE
            _LF-RNXT @ _LF-RUN !
        REPEAT

        _LF-LINE @ FREE
        _LF-NEXT @ _LF-LINE !
    REPEAT ;
