\ =================================================================
\  gap-buf.f — Gap Buffer with Integrated Line Index
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: GB- / _GB-
\  Depends on: text/utf8.f
\
\  A gap buffer for efficient text editing.  Insert and delete at
\  the cursor are O(1) amortised.  Moving the cursor is
\  O(distance).  A line-start index is maintained incrementally after
\  edits for fast line-number <-> byte-offset mapping.  GB-SET performs
\  a full rebuild because it replaces the complete document.
\
\  The descriptor and byte buffer are arena-allocated.  The caller
\  supplies that arena and buffer growth is reclaimed with it.  The
\  line index has a different lifetime: it is a packed u32 array
\  allocated independently so growth can release the superseded block.
\  GB-FREE releases that index; the arena still owns the descriptor and
\  byte buffer.
\
\  Descriptor layout (8 cells = 64 bytes):
\    +0   buf    Byte buffer  (arena-allocated)
\    +8   cap    Total capacity in bytes
\    +16  gs     Gap start = logical cursor position
\    +24  ge     Gap end (exclusive)
\    +32  lidx   Line-start offset array (packed u32, ALLOCATE-owned)
\    +40  lcap   Line-index capacity (entries)
\    +48  lcnt   Line count (always >= 1)
\    +56  arena  Arena handle (for growth allocation)
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
\    GB-NEW        ( cap arena -- gb )
\    GB-FREE       ( gb -- )        release the independently-owned index
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
\    GB-COPY       ( off dest u gb -- copied ) copy a logical range
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
56 CONSTANT _GB-O-ARENA
64 CONSTANT _GB-DESC-SZ

\ =====================================================================
\  S2 -- Module Temporaries
\ =====================================================================

VARIABLE _GB-T           \ current gb handle
VARIABLE _GB-D           \ delta for move / grow
VARIABLE _GB-LNEW        \ replacement line-index allocation
VARIABLE _GB-LNEW-CAP    \ replacement line-index entry capacity

4 CONSTANT _GB-LIDX-SZ   \ packed u32 byte offsets

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
    _GB-O-LIDX + @  SWAP _GB-LIDX-SZ * +  L@ ;

: _GB-LIDX-ADDR  ( index -- addr )
    _GB-LIDX-SZ * _GB-T @ _GB-O-LIDX + @ + ;

: _GB-LIDX@  ( index -- off )
    _GB-LIDX-ADDR L@ ;

: _GB-LIDX!  ( off index -- )
    _GB-LIDX-ADDR L! ;

: _GB-LIDX+!  ( delta index -- )
    >R R@ _GB-LIDX@ + R> _GB-LIDX! ;

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

: GB-NEW  ( cap arena -- gb )
    _GB-D !                            \ _GB-D = arena
    _GB-D @ _GB-DESC-SZ ARENA-ALLOT   ( cap gb )
    _GB-T !                            \ _GB-T = gb
    _GB-D @ _GB-T @ _GB-O-ARENA + !   \ store arena in descriptor
    _GB-D @ OVER ARENA-ALLOT           ( cap buf )
    _GB-T @ _GB-O-BUF + !             ( cap )
    DUP _GB-T @ _GB-O-CAP + !         \ cap
    0 _GB-T @ _GB-O-GS + !            \ gs = 0
    _GB-T @ _GB-O-GE + !              \ ge = cap (all gap)
    _GB-LIDX-INIT _GB-LIDX-SZ * ALLOCATE
    DUP IF 2DROP ABORT" GB-NEW: line index alloc failed" THEN DROP
    _GB-T @ _GB-O-LIDX + !
    _GB-LIDX-INIT _GB-T @ _GB-O-LCAP + !
    1 _GB-T @ _GB-O-LCNT + !
    0 0 _GB-LIDX!                       \ line 0 at offset 0
    _GB-T @ ;

: GB-FREE  ( gb -- )
    DUP _GB-O-LIDX + @ ?DUP IF FREE THEN
    0 OVER _GB-O-LIDX + !
    0 OVER _GB-O-LCAP + !
    0 SWAP _GB-O-LCNT + ! ;

\ =====================================================================
\  S7 -- Growth
\ =====================================================================

\ _GB-LIDX-RESIZE ( new-lcap -- )
\   Replace the packed line index transactionally: allocation must succeed
\   before the live pointer changes or the old block is released.
: _GB-LIDX-RESIZE  ( new-lcap -- )
    DUP _GB-T @ _GB-O-LCAP + @ <= IF DROP EXIT THEN
    _GB-LNEW-CAP !
    _GB-LNEW-CAP @ _GB-LIDX-SZ * ALLOCATE
    DUP IF 2DROP ABORT" gap buffer: line index alloc failed" THEN DROP
    _GB-LNEW !
    _GB-T @ _GB-O-LIDX + @ _GB-LNEW @
    _GB-T @ _GB-O-LCAP + @ _GB-LIDX-SZ * CMOVE
    _GB-T @ _GB-O-LIDX + @ FREE
    _GB-LNEW @ _GB-T @ _GB-O-LIDX + !
    _GB-LNEW-CAP @ _GB-T @ _GB-O-LCAP + ! ;

\ _GB-LIDX-GROW ( -- )   double the line-index array.  Uses _GB-T.
: _GB-LIDX-GROW  ( -- )
    _GB-T @ _GB-O-LCAP + @ 2 * _GB-LIDX-RESIZE ;

\ _GB-GROW ( needed -- )   ensure gap >= needed bytes.  Uses _GB-T.
\   Allocates new buffer from arena, copies both segments, abandons old.
: _GB-GROW  ( needed -- )
    _GB-T @ _GB-GAP  OVER >= IF DROP EXIT THEN
    \ new-cap = max( 2*cap, cap + needed )
    _GB-T @ _GB-O-CAP + @ 2 *                    ( needed nc1 )
    _GB-T @ _GB-O-CAP + @ 2 PICK +               ( needed nc1 nc2 )
    MAX NIP                                       ( new-cap )
    \ Allocate new buffer from arena (old buf abandoned)
    _GB-T @ _GB-O-ARENA + @ OVER ARENA-ALLOT     ( new-cap new-buf )
    _GB-D !                                       ( new-cap )  \ _GB-D = new-buf
    \ Copy pre-gap: old[0..gs) -> new[0..gs)
    _GB-T @ _GB-O-BUF + @  _GB-D @
    _GB-T @ _GB-O-GS + @  CMOVE                   ( new-cap )
    \ delta = new-cap - old-cap
    DUP _GB-T @ _GB-O-CAP + @ -  >R              ( new-cap  R: delta )
    \ Copy post-gap: old[ge..cap) -> new[ge+delta..new-cap)
    _GB-T @ _GB-O-BUF + @  _GB-T @ _GB-O-GE + @  +
    _GB-D @  _GB-T @ _GB-O-GE + @  +  R@ +
    _GB-T @ _GB-O-CAP + @  _GB-T @ _GB-O-GE + @  -
    DUP 0> IF CMOVE ELSE DROP 2DROP THEN          ( new-cap  R: delta )
    \ Update descriptor
    _GB-D @ _GB-T @ _GB-O-BUF + !                ( new-cap  R: delta )
    R> _GB-T @ _GB-O-GE + +!                     ( new-cap )
    _GB-T @ _GB-O-CAP + ! ;

\ =====================================================================
\  S8 -- Line Index Maintenance
\ =====================================================================

\ _GB-LIDX-ENSURE ( count -- )
\   Ensure the packed array can hold count entries.  A bulk operation may
\   jump directly to its exact requirement; ordinary edits retain geometric
\   growth so sequential typing does not resize for every new line.
: _GB-LIDX-ENSURE  ( count -- )
    DUP _GB-T @ _GB-O-LCAP + @ <= IF DROP EXIT THEN
    _GB-T @ _GB-O-LCAP + @ 2 * MAX _GB-LIDX-RESIZE ;

VARIABLE _GB-LCOUNT

\ _GB-CONTENT-LINES ( -- count )
\   Count first so a bulk replacement can grow its index once to the exact
\   required capacity instead of retaining geometric slack.
: _GB-CONTENT-LINES  ( -- count )
    1 _GB-LCOUNT !
    _GB-T @ _GB-O-GS + @ 0 ?DO
        _GB-T @ _GB-O-BUF + @ I + C@ 10 = IF 1 _GB-LCOUNT +! THEN
    LOOP
    _GB-T @ _GB-O-CAP + @ _GB-T @ _GB-O-GE + @ ?DO
        _GB-T @ _GB-O-BUF + @ I + C@ 10 = IF 1 _GB-LCOUNT +! THEN
    LOOP
    _GB-LCOUNT @ ;

\ _GB-REBUILD-LINES ( -- )   Full rebuild.  Uses _GB-T.
: _GB-REBUILD-LINES  ( -- )
    _GB-CONTENT-LINES _GB-LIDX-ENSURE
    1 _GB-T @ _GB-O-LCNT + !
    0 0 _GB-LIDX!                          \ line 0 at offset 0
    \ --- pre-gap: physical [0..gs), logical = physical ---
    _GB-T @ _GB-O-GS + @ 0 ?DO
        _GB-T @ _GB-O-BUF + @ I + C@ 10 = IF
            _GB-T @ _GB-O-LCNT + @
            _GB-T @ _GB-O-LCAP + @ >= IF _GB-LIDX-GROW THEN
            I 1+ _GB-T @ _GB-O-LCNT + @ _GB-LIDX!
            1 _GB-T @ _GB-O-LCNT + +!
        THEN
    LOOP
    \ --- post-gap: physical [ge..cap), logical = phys - ge + gs ---
    _GB-T @ _GB-O-CAP + @  _GB-T @ _GB-O-GE + @  ?DO
        _GB-T @ _GB-O-BUF + @ I + C@ 10 = IF
            _GB-T @ _GB-O-LCNT + @
            _GB-T @ _GB-O-LCAP + @ >= IF _GB-LIDX-GROW THEN
            I _GB-T @ _GB-O-GE + @ -
            _GB-T @ _GB-O-GS + @ + 1+
            _GB-T @ _GB-O-LCNT + @ _GB-LIDX!
            1 _GB-T @ _GB-O-LCNT + +!
        THEN
    LOOP ;

\ _GB-LIDX-FIRST-AFTER ( pos -- index )
\   Return the first line-index entry whose logical byte offset is
\   strictly greater than pos.  Returning lcnt means there is no such
\   entry.  Strict comparison matters at a line start: text inserted at
\   that offset belongs to the existing line, so its start remains fixed.
VARIABLE _GB-LF-POS
VARIABLE _GB-LF-LO
VARIABLE _GB-LF-HI
VARIABLE _GB-LF-MID

: _GB-LIDX-FIRST-AFTER  ( pos -- index )
    _GB-LF-POS !
    0 _GB-LF-LO !
    _GB-T @ _GB-O-LCNT + @ _GB-LF-HI !
    BEGIN
        _GB-LF-LO @ _GB-LF-HI @ <
    WHILE
        _GB-LF-LO @ _GB-LF-HI @ + 2 / DUP _GB-LF-MID !
        _GB-LIDX@
        _GB-LF-POS @ <= IF
            _GB-LF-MID @ 1+ _GB-LF-LO !
        ELSE
            _GB-LF-MID @ _GB-LF-HI !
        THEN
    REPEAT
    _GB-LF-LO @ ;

VARIABLE _GB-LI-POS
VARIABLE _GB-LI-LEN
VARIABLE _GB-LI-FIRST
VARIABLE _GB-LI-AFTER
VARIABLE _GB-LI-NL
VARIABLE _GB-LI-OLD-CNT
VARIABLE _GB-LI-NEW-CNT
VARIABLE _GB-LI-WR
VARIABLE _GB-LI-SRC
VARIABLE _GB-LI-DEL-A

\ _GB-LIDX-INSERT ( -- )
\   Update the line index after _GB-LI-LEN bytes have been copied into
\   the pre-gap segment at logical/physical offset _GB-LI-POS.  Existing
\   line starts after the insertion point move right; each inserted LF
\   contributes a new start immediately after itself.
: _GB-LIDX-INSERT  ( -- )
    0 _GB-LI-NL !
    _GB-LI-LEN @ 0 ?DO
        _GB-T @ _GB-O-BUF + @ _GB-LI-POS @ + I + C@ 10 = IF
            1 _GB-LI-NL +!
        THEN
    LOOP

    _GB-LI-POS @ _GB-LIDX-FIRST-AFTER _GB-LI-FIRST !
    _GB-T @ _GB-O-LCNT + @ _GB-LI-OLD-CNT !
    _GB-LI-OLD-CNT @ _GB-LI-NL @ + DUP _GB-LI-NEW-CNT !
    _GB-LIDX-ENSURE

    \ Open room for the new line starts.  CMOVE> is overlap-safe when
    \ moving the tail toward higher addresses.
    _GB-LI-NL @ IF
        _GB-LI-FIRST @ _GB-LIDX-ADDR
        _GB-LI-FIRST @ _GB-LI-NL @ + _GB-LIDX-ADDR
        _GB-LI-OLD-CNT @ _GB-LI-FIRST @ - _GB-LIDX-SZ *
        DUP 0> IF CMOVE> ELSE DROP 2DROP THEN
    THEN

    \ All old starts strictly after the insertion point shift by len.
    _GB-LI-NEW-CNT @ _GB-LI-FIRST @ _GB-LI-NL @ + ?DO
        _GB-LI-LEN @ I _GB-LIDX+!
    LOOP

    \ Fill the opened slots with starts contributed by inserted LFs.
    0 _GB-LI-WR !
    _GB-LI-LEN @ 0 ?DO
        _GB-T @ _GB-O-BUF + @ _GB-LI-POS @ + I + C@ 10 = IF
            _GB-LI-POS @ I + 1+
            _GB-LI-FIRST @ _GB-LI-WR @ + _GB-LIDX!
            1 _GB-LI-WR +!
        THEN
    LOOP
    _GB-LI-NEW-CNT @ _GB-T @ _GB-O-LCNT + ! ;

\ _GB-LIDX-DELETE ( start len -- )
\   Remove line starts introduced by LFs in [start,start+len), then shift
\   every surviving later start left by len.  A deleted LF at byte q owns
\   the line-start entry q+1, hence the interval (start,start+len].
: _GB-LIDX-DELETE  ( start len -- )
    DUP 0= IF 2DROP EXIT THEN
    _GB-LI-LEN ! _GB-LI-POS !
    _GB-LI-POS @ _GB-LIDX-FIRST-AFTER _GB-LI-FIRST !
    _GB-LI-POS @ _GB-LI-LEN @ +
    _GB-LIDX-FIRST-AFTER _GB-LI-AFTER !
    _GB-T @ _GB-O-LCNT + @ _GB-LI-OLD-CNT !

    \ Close over entries belonging to deleted LFs.  CMOVE is overlap-safe
    \ in this lower-address direction.
    _GB-LI-AFTER @ _GB-LIDX-ADDR
    _GB-LI-FIRST @ _GB-LIDX-ADDR
    _GB-LI-OLD-CNT @ _GB-LI-AFTER @ - _GB-LIDX-SZ *
    DUP 0> IF CMOVE ELSE DROP 2DROP THEN

    _GB-LI-OLD-CNT @
    _GB-LI-AFTER @ _GB-LI-FIRST @ - -
    DUP _GB-LI-NEW-CNT !
    _GB-T @ _GB-O-LCNT + !

    _GB-LI-NEW-CNT @ _GB-LI-FIRST @ ?DO
        _GB-LI-LEN @ NEGATE I _GB-LIDX+!
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
        _GB-D @ NEGATE _GB-T @ _GB-O-GE + +!   \ ge -= delta
    ELSE
        \ --- move right ---
        \ delta = pos - gs
        DUP _GB-T @ _GB-O-GS + @ - _GB-D !    ( pos )
        \ CMOVE buf+ge -> buf+gs, delta bytes
        _GB-T @ _GB-O-BUF + @ _GB-T @ _GB-O-GE + @  +   \ src
        _GB-T @ _GB-O-BUF + @ _GB-T @ _GB-O-GS + @ +    \ dst
        _GB-D @  CMOVE                                     ( pos )
        _GB-T @ _GB-O-GS + !           \ gs = pos
        _GB-D @ _GB-T @ _GB-O-GE + +!    \ ge += delta
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
    _GB-LI-LEN ! _GB-LI-SRC !
    _GB-T @ _GB-O-GS + @ _GB-LI-POS !
    _GB-LI-LEN @ _GB-GROW               \ ensure space
    \ Copy into gap at buf+gs
    _GB-LI-SRC @
    _GB-T @ _GB-O-BUF + @
    _GB-T @ _GB-O-GS + @ +             ( addr dest )
    _GB-LI-LEN @ CMOVE
    _GB-LI-LEN @ _GB-T @ _GB-O-GS + +!  \ gs += u
    _GB-LIDX-INSERT ;

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
    DUP _GB-LI-LEN ! DROP
    _GB-T @ _GB-O-GS + @ _GB-LI-POS !
    \ Deleted bytes sit at buf+ge (about to become inner gap).
    _GB-T @ _GB-O-BUF + @  _GB-T @ _GB-O-GE + @ +
    _GB-LI-DEL-A !
    _GB-LI-POS @ _GB-LI-LEN @ _GB-LIDX-DELETE
    \ Expand gap forward: ge += n
    _GB-LI-LEN @ _GB-T @ _GB-O-GE + +!
    _GB-LI-DEL-A @ _GB-LI-LEN @ ;         ( del-addr del-u )

\ GB-BS ( n gb -- del-addr del-u )
\   Delete n bytes backward from cursor.  Returns pointer to
\   deleted bytes (valid until next mutating call).
: GB-BS  ( n gb -- del-addr del-u )
    _GB-T !
    _GB-T @ _GB-O-GS + @  MIN            \ clamp
    DUP 0= IF
        _GB-T @ _GB-O-BUF + @  SWAP EXIT
    THEN
    DUP _GB-LI-LEN !
    _GB-T @ _GB-O-GS + @ OVER - _GB-LI-POS !
    DROP
    _GB-T @ _GB-O-BUF + @ _GB-LI-POS @ + _GB-LI-DEL-A !
    _GB-LI-POS @ _GB-LI-LEN @ _GB-LIDX-DELETE
    \ Deleted bytes at buf+(gs-n) -- will be inside gap after.
    _GB-LI-LEN @ NEGATE _GB-T @ _GB-O-GS + +!  \ gs -= n
    _GB-LI-DEL-A @ _GB-LI-LEN @ ;         ( del-addr del-u )

\ GB-DEL-CP ( gb -- del-addr del-u )
\   Delete one codepoint forward.
: GB-DEL-CP  ( gb -- del-addr del-u )
    >R
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
    >R
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
    _GB-O-LIDX + @ 0 SWAP L! ;            \ line 0 at 0

\ GB-SET ( addr u gb -- )
\   Replace all content.  Grows buffer if needed.
: GB-SET  ( addr u gb -- )
    _GB-T !
    \ Grow buffer if content exceeds capacity
    DUP _GB-T @ _GB-O-CAP + @ > IF
        DUP 256 +                           ( addr u new-cap )
        _GB-T @ _GB-O-ARENA + @ OVER ARENA-ALLOT
        _GB-T @ _GB-O-BUF + !              ( addr u new-cap )
        _GB-T @ _GB-O-CAP + !              ( addr u )
    THEN
    \ Copy content to buf[0..]
    SWAP  _GB-T @ _GB-O-BUF + @            ( u addr buf )
    ROT DUP >R  CMOVE                      ( R: u )
    \ gs = u, ge = cap
    R> _GB-T @ _GB-O-GS + !
    _GB-T @ _GB-O-CAP + @  _GB-T @ _GB-O-GE + !
    _GB-REBUILD-LINES ;

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

VARIABLE _GB-RNG-OFF
VARIABLE _GB-RNG-DEST
VARIABLE _GB-RNG-LEN
VARIABLE _GB-RNG-PRE

\ GB-COPY ( off dest u gb -- copied )
\   Copy a clamped logical range without flattening the whole buffer.
\   At most two CMOVEs are needed: one from each side of the gap.
: GB-COPY  ( off dest u gb -- copied )
    _GB-T !
    _GB-RNG-LEN ! _GB-RNG-DEST ! _GB-RNG-OFF !
    _GB-RNG-OFF @ DUP 0< IF DROP 0 THEN
    _GB-T @ GB-LEN MIN _GB-RNG-OFF !
    _GB-RNG-LEN @ DUP 0< IF DROP 0 THEN
    _GB-T @ GB-LEN _GB-RNG-OFF @ - MIN _GB-RNG-LEN !
    0 _GB-RNG-PRE !

    \ Portion before the gap, if the requested range starts there.
    _GB-RNG-OFF @ _GB-T @ _GB-O-GS + @ < IF
        _GB-T @ _GB-O-GS + @ _GB-RNG-OFF @ -
        _GB-RNG-LEN @ MIN DUP _GB-RNG-PRE !
        _GB-T @ _GB-O-BUF + @ _GB-RNG-OFF @ +
        _GB-RNG-DEST @ ROT CMOVE
    THEN

    \ Remaining portion starts at or after the logical gap boundary.
    _GB-RNG-LEN @ _GB-RNG-PRE @ - DUP 0> IF
        _GB-RNG-OFF @ _GB-RNG-PRE @ +
        _GB-T @ _GB-O-GS + @ -
        _GB-T @ _GB-O-GE + @ +
        _GB-T @ _GB-O-BUF + @ +
        _GB-RNG-DEST @ _GB-RNG-PRE @ +
        ROT CMOVE
    ELSE
        DROP
    THEN
    _GB-RNG-LEN @ ;

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
' GB-COPY        CONSTANT _gb-copy-xt
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
: GB-COPY        _gb-copy-xt   _gb-guard WITH-GUARD ;
: GB-CURSOR-LINE _gb-cline-xt  _gb-guard WITH-GUARD ;
: GB-CURSOR-COL  _gb-ccol-xt   _gb-guard WITH-GUARD ;
[THEN] [THEN]
