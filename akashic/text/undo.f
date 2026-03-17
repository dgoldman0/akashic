\ =================================================================
\  undo.f — Undo / Redo System for Gap Buffer
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: UNDO- / _UD- / _UE-
\  Depends on: text/gap-buf.f
\
\  Two stacks (undo + redo) of edit records.  Each record stores
\  the edit type (insert/delete), byte position, and a copy of
\  the affected text.
\
\  Consecutive same-type, adjacent edits are coalesced into a
\  single record (sequential typing / backspacing).  Coalescing
\  breaks on: newline, cursor jump, explicit UNDO-BREAK, or
\  after undo/redo.  Any new edit clears the redo stack.
\
\  Entries are moved (not copied) between stacks on undo/redo.
\
\  Public API:
\    UNDO-NEW       ( -- ud )
\    UNDO-FREE      ( ud -- )
\    UNDO-PUSH      ( type pos addr u ud -- )
\    UNDO-UNDO      ( gb ud -- flag )
\    UNDO-REDO      ( gb ud -- flag )
\    UNDO-CLEAR     ( ud -- )
\    UNDO-BREAK     ( ud -- )       break coalescing
\    UNDO-CAN-UNDO? ( ud -- flag )
\    UNDO-CAN-REDO? ( ud -- flag )
\    UNDO-T-INS     ( -- 0 )        edit type: insert
\    UNDO-T-DEL     ( -- 1 )        edit type: delete
\ =================================================================

PROVIDED akashic-undo

REQUIRE gap-buf.f

\ =====================================================================
\  S1 -- Constants & Struct Offsets
\ =====================================================================

\ Edit types
0 CONSTANT UNDO-T-INS
1 CONSTANT UNDO-T-DEL

\ --- Undo entry (5 cells = 40 bytes) ---
 0 CONSTANT _UE-O-TYPE     \ 0=insert, 1=delete
 8 CONSTANT _UE-O-POS      \ byte offset in buffer
16 CONSTANT _UE-O-LEN      \ byte count
24 CONSTANT _UE-O-DATA     \ ALLOCATE'd copy of affected bytes
32 CONSTANT _UE-O-DCAP     \ allocated capacity of data buffer
40 CONSTANT _UE-SZ

\ --- Undo state descriptor (7 cells = 56 bytes) ---
 0 CONSTANT _UD-O-USTK     \ undo stack array (cell-pointers)
 8 CONSTANT _UD-O-UCAP     \ undo max entries
16 CONSTANT _UD-O-UCNT     \ current undo count
24 CONSTANT _UD-O-RSTK     \ redo stack array
32 CONSTANT _UD-O-RCAP     \ redo max entries
40 CONSTANT _UD-O-RCNT     \ current redo count
48 CONSTANT _UD-O-COAL     \ coalescing flag (-1 = on, 0 = off)
56 CONSTANT _UD-DESC-SZ

512 CONSTANT _UD-STK-MAX   \ max entries per stack

\ =====================================================================
\  S2 -- Module Temporaries
\ =====================================================================

VARIABLE _UD-T             \ current undo-state handle

\ =====================================================================
\  S3 -- Entry Management
\ =====================================================================

VARIABLE _UE-A   VARIABLE _UE-B   VARIABLE _UE-C   VARIABLE _UE-D

\ _UE-NEW ( type pos addr u -- entry )
\   Allocate a new undo entry with a copy of the data bytes.
: _UE-NEW  ( type pos addr u -- entry )
    _UE-D !  _UE-C !  _UE-B !  _UE-A !
    _UE-SZ ALLOCATE 0<> ABORT" _UE-NEW"
    >R
    _UE-A @ R@ _UE-O-TYPE + !
    _UE-B @ R@ _UE-O-POS  + !
    _UE-D @ R@ _UE-O-LEN  + !
    _UE-D @ 64 MAX
    DUP R@ _UE-O-DCAP + !
    ALLOCATE 0<> ABORT" _UE-NEW:d"
    R@ _UE-O-DATA + !
    _UE-C @  R@ _UE-O-DATA + @  _UE-D @  CMOVE
    R> ;

\ _UE-FREE ( entry -- )
: _UE-FREE  ( entry -- )
    DUP _UE-O-DATA + @ ?DUP IF FREE DROP THEN
    FREE DROP ;

\ _UE-ENSURE ( additional entry -- )
\   Grow the entry's data buffer so it can hold `additional` more bytes.
: _UE-ENSURE  ( additional entry -- )
    >R
    R@ _UE-O-LEN + @ +                  ( total-needed )
    DUP R@ _UE-O-DCAP + @ <= IF
        R> 2DROP EXIT
    THEN
    2 *                                  ( new-dcap )
    R@ _UE-O-DATA + @ OVER RESIZE
    0<> ABORT" _UE-ENSURE"
    R@ _UE-O-DATA + !
    R> _UE-O-DCAP + ! ;

\ =====================================================================
\  S4 -- Stack Operations (Undo Stack)
\ =====================================================================

\ _UD-UPUSH ( entry -- )
: _UD-UPUSH  ( entry -- )
    _UD-T @ _UD-O-UCNT + @
    _UD-T @ _UD-O-UCAP + @ >= IF
        \ Full — evict oldest entry
        _UD-T @ _UD-O-USTK + @ @ _UE-FREE
        _UD-T @ _UD-O-USTK + @  DUP CELL+  SWAP
        _UD-T @ _UD-O-UCNT + @ 1- CELLS  CMOVE
        -1 _UD-T @ _UD-O-UCNT + +!
    THEN
    _UD-T @ _UD-O-USTK + @
    _UD-T @ _UD-O-UCNT + @ CELLS +  !
    1 _UD-T @ _UD-O-UCNT + +! ;

\ _UD-UPOP ( -- entry | 0 )
: _UD-UPOP  ( -- entry | 0 )
    _UD-T @ _UD-O-UCNT + @ 0= IF 0 EXIT THEN
    -1 _UD-T @ _UD-O-UCNT + +!
    _UD-T @ _UD-O-USTK + @
    _UD-T @ _UD-O-UCNT + @ CELLS + @ ;

\ _UD-UPEEK ( -- entry | 0 )
: _UD-UPEEK  ( -- entry | 0 )
    _UD-T @ _UD-O-UCNT + @ 0= IF 0 EXIT THEN
    _UD-T @ _UD-O-USTK + @
    _UD-T @ _UD-O-UCNT + @ 1- CELLS + @ ;

\ _UD-UCLEAR ( -- )
: _UD-UCLEAR  ( -- )
    _UD-T @ _UD-O-UCNT + @ 0 ?DO
        _UD-T @ _UD-O-USTK + @  I CELLS + @  _UE-FREE
    LOOP
    0 _UD-T @ _UD-O-UCNT + ! ;

\ =====================================================================
\  S5 -- Stack Operations (Redo Stack)
\ =====================================================================

\ _UD-RPUSH ( entry -- )
: _UD-RPUSH  ( entry -- )
    _UD-T @ _UD-O-RCNT + @
    _UD-T @ _UD-O-RCAP + @ >= IF
        _UD-T @ _UD-O-RSTK + @ @ _UE-FREE
        _UD-T @ _UD-O-RSTK + @  DUP CELL+  SWAP
        _UD-T @ _UD-O-RCNT + @ 1- CELLS  CMOVE
        -1 _UD-T @ _UD-O-RCNT + +!
    THEN
    _UD-T @ _UD-O-RSTK + @
    _UD-T @ _UD-O-RCNT + @ CELLS +  !
    1 _UD-T @ _UD-O-RCNT + +! ;

\ _UD-RPOP ( -- entry | 0 )
: _UD-RPOP  ( -- entry | 0 )
    _UD-T @ _UD-O-RCNT + @ 0= IF 0 EXIT THEN
    -1 _UD-T @ _UD-O-RCNT + +!
    _UD-T @ _UD-O-RSTK + @
    _UD-T @ _UD-O-RCNT + @ CELLS + @ ;

\ _UD-RCLEAR ( -- )
: _UD-RCLEAR  ( -- )
    _UD-T @ _UD-O-RCNT + @ 0 ?DO
        _UD-T @ _UD-O-RSTK + @  I CELLS + @  _UE-FREE
    LOOP
    0 _UD-T @ _UD-O-RCNT + ! ;

\ =====================================================================
\  S6 -- Coalescing
\ =====================================================================

\ _UD-HAS-NL? ( addr u -- flag )
\   True if the byte range contains a newline.
: _UD-HAS-NL?  ( addr u -- flag )
    0 ?DO
        DUP I + C@ 10 = IF DROP -1 UNLOOP EXIT THEN
    LOOP
    DROP 0 ;

VARIABLE _UC-TYPE   VARIABLE _UC-POS
VARIABLE _UC-ADDR   VARIABLE _UC-LEN
VARIABLE _UC-E      \ top undo entry being checked

\ _UD-TRY-COALESCE ( type pos addr u -- coalesced? )
\   Attempts to merge the new edit into the top undo entry.
\   Consumes the four arguments regardless of result.
: _UD-TRY-COALESCE  ( type pos addr u -- flag )
    _UC-LEN !  _UC-ADDR !  _UC-POS !  _UC-TYPE !

    _UD-T @ _UD-O-COAL + @ 0= IF 0 EXIT THEN
    _UD-UPEEK DUP 0= IF DROP 0 EXIT THEN   _UC-E !
    _UC-TYPE @  _UC-E @ _UE-O-TYPE + @  <> IF 0 EXIT THEN
    _UC-ADDR @  _UC-LEN @  _UD-HAS-NL?  IF 0 EXIT THEN

    _UC-TYPE @ UNDO-T-INS = IF
        \ INSERT: new pos must equal old pos + old len (sequential typing)
        _UC-POS @
        _UC-E @ _UE-O-POS + @  _UC-E @ _UE-O-LEN + @  +
        <> IF 0 EXIT THEN
        \ Append new bytes to entry data
        _UC-LEN @  _UC-E @  _UE-ENSURE
        _UC-ADDR @
        _UC-E @ _UE-O-DATA + @  _UC-E @ _UE-O-LEN + @  +
        _UC-LEN @  CMOVE
        _UC-LEN @  _UC-E @ _UE-O-LEN + +!
        -1 EXIT
    THEN

    \ DELETE — check backspace pattern: new pos + new len == old pos
    _UC-POS @  _UC-LEN @ +
    _UC-E @ _UE-O-POS + @  = IF
        \ Prepend: shift old data right, copy new at start
        _UC-LEN @  _UC-E @  _UE-ENSURE
        _UC-E @ _UE-O-DATA + @
        DUP  _UC-LEN @ +
        _UC-E @ _UE-O-LEN + @   CMOVE>
        _UC-ADDR @  _UC-E @ _UE-O-DATA + @  _UC-LEN @  CMOVE
        _UC-POS @  _UC-E @ _UE-O-POS + !
        _UC-LEN @  _UC-E @ _UE-O-LEN + +!
        -1 EXIT
    THEN

    \ DELETE — check forward-delete pattern: new pos == old pos
    _UC-POS @  _UC-E @ _UE-O-POS + @  = IF
        \ Append new bytes
        _UC-LEN @  _UC-E @  _UE-ENSURE
        _UC-ADDR @
        _UC-E @ _UE-O-DATA + @  _UC-E @ _UE-O-LEN + @  +
        _UC-LEN @  CMOVE
        _UC-LEN @  _UC-E @ _UE-O-LEN + +!
        -1 EXIT
    THEN

    0 ;

\ =====================================================================
\  S7 -- Constructor / Destructor
\ =====================================================================

: UNDO-NEW  ( -- ud )
    _UD-DESC-SZ ALLOCATE 0<> ABORT" UNDO-NEW"
    DUP >R
    _UD-STK-MAX CELLS ALLOCATE 0<> ABORT" UNDO-NEW:u"
    R@ _UD-O-USTK + !
    _UD-STK-MAX R@ _UD-O-UCAP + !
    0 R@ _UD-O-UCNT + !
    _UD-STK-MAX CELLS ALLOCATE 0<> ABORT" UNDO-NEW:r"
    R@ _UD-O-RSTK + !
    _UD-STK-MAX R@ _UD-O-RCAP + !
    0 R@ _UD-O-RCNT + !
    -1 R@ _UD-O-COAL + !
    R> ;

: UNDO-FREE  ( ud -- )
    DUP _UD-T !
    _UD-UCLEAR  _UD-RCLEAR
    DUP _UD-O-USTK + @ FREE DROP
    DUP _UD-O-RSTK + @ FREE DROP
    FREE DROP ;

\ =====================================================================
\  S8 -- Public API
\ =====================================================================

: UNDO-CAN-UNDO?  ( ud -- flag )   _UD-O-UCNT + @ 0<> ;
: UNDO-CAN-REDO?  ( ud -- flag )   _UD-O-RCNT + @ 0<> ;

: UNDO-BREAK  ( ud -- )
    0 SWAP _UD-O-COAL + ! ;

: UNDO-CLEAR  ( ud -- )
    DUP _UD-T !
    _UD-UCLEAR  _UD-RCLEAR ;

\ UNDO-PUSH ( type pos addr u ud -- )
\   Record an edit.  Clears redo.  Attempts coalescing.
: UNDO-PUSH  ( type pos addr u ud -- )
    _UD-T !
    _UD-RCLEAR
    _UD-TRY-COALESCE IF EXIT THEN
    \ No coalesce — create new entry from saved variables
    _UC-TYPE @  _UC-POS @  _UC-ADDR @  _UC-LEN @
    _UE-NEW  _UD-UPUSH
    -1 _UD-T @ _UD-O-COAL + ! ;

\ --- Undo / Redo Execution ---

VARIABLE _UDO-E     \ entry being applied
VARIABLE _UDO-GB    \ gap buffer being modified

\ UNDO-UNDO ( gb ud -- flag )
\   Undo the most recent edit.  Moves the entry to the redo stack.
\   Returns TRUE if an edit was undone, FALSE if nothing to undo.
: UNDO-UNDO  ( gb ud -- flag )
    _UD-T !  _UDO-GB !
    _UD-UPOP DUP 0= IF EXIT THEN
    _UDO-E !
    _UDO-E @ _UE-O-POS + @  _UDO-GB @ GB-MOVE!
    _UDO-E @ _UE-O-TYPE + @ UNDO-T-INS = IF
        \ Undo insert = delete forward
        _UDO-E @ _UE-O-LEN + @  _UDO-GB @ GB-DEL  2DROP
    ELSE
        \ Undo delete = re-insert saved bytes
        _UDO-E @ _UE-O-DATA + @
        _UDO-E @ _UE-O-LEN + @
        _UDO-GB @ GB-INS
    THEN
    _UDO-E @ _UD-RPUSH
    0 _UD-T @ _UD-O-COAL + !          \ break coalescing
    -1 ;

\ UNDO-REDO ( gb ud -- flag )
\   Re-apply the most recently undone edit.  Moves the entry back
\   to the undo stack.  Returns TRUE if applied, FALSE if nothing.
: UNDO-REDO  ( gb ud -- flag )
    _UD-T !  _UDO-GB !
    _UD-RPOP DUP 0= IF EXIT THEN
    _UDO-E !
    _UDO-E @ _UE-O-POS + @  _UDO-GB @ GB-MOVE!
    _UDO-E @ _UE-O-TYPE + @ UNDO-T-INS = IF
        \ Redo insert = re-insert
        _UDO-E @ _UE-O-DATA + @
        _UDO-E @ _UE-O-LEN + @
        _UDO-GB @ GB-INS
    ELSE
        \ Redo delete = re-delete
        _UDO-E @ _UE-O-LEN + @  _UDO-GB @ GB-DEL  2DROP
    THEN
    _UDO-E @ _UD-UPUSH
    0 _UD-T @ _UD-O-COAL + !          \ break coalescing
    -1 ;

\ =====================================================================
\  S9 -- Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ud-guard

' UNDO-NEW    CONSTANT _ud-new-xt
' UNDO-FREE   CONSTANT _ud-free-xt
' UNDO-PUSH   CONSTANT _ud-push-xt
' UNDO-UNDO   CONSTANT _ud-undo-xt
' UNDO-REDO   CONSTANT _ud-redo-xt
' UNDO-CLEAR  CONSTANT _ud-clear-xt
' UNDO-BREAK  CONSTANT _ud-break-xt

: UNDO-NEW    _ud-new-xt   _ud-guard WITH-GUARD ;
: UNDO-FREE   _ud-free-xt  _ud-guard WITH-GUARD ;
: UNDO-PUSH   _ud-push-xt  _ud-guard WITH-GUARD ;
: UNDO-UNDO   _ud-undo-xt  _ud-guard WITH-GUARD ;
: UNDO-REDO   _ud-redo-xt  _ud-guard WITH-GUARD ;
: UNDO-CLEAR  _ud-clear-xt _ud-guard WITH-GUARD ;
: UNDO-BREAK  _ud-break-xt _ud-guard WITH-GUARD ;
[THEN] [THEN]
