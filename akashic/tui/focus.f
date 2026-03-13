\ focus.f — Focus Manager
\
\ Manages which widget receives keyboard input.  Maintains a
\ focus chain (ordered list of focusable widgets).  Tab/Shift-Tab
\ cycles focus.
\
\ The focus chain is a fixed-size parallel array (max 32 entries).
\ Each slot stores a widget address and a next-index, forming a
\ circular singly-linked list.  This avoids adding fields to every
\ widget descriptor.
\
\ Prefix: FOC- (public), _FOC- (internal)
\ Provider: akashic-tui-focus
\ Dependencies: keys.f, widget.f
\
\ Public API:
\   FOC-ADD       ( widget -- )       Add widget to focus chain
\   FOC-REMOVE    ( widget -- )       Remove widget from focus chain
\   FOC-NEXT      ( -- )              Move focus to next widget
\   FOC-PREV      ( -- )              Move focus to previous widget
\   FOC-SET       ( widget -- )       Explicitly set focus
\   FOC-GET       ( -- widget | 0 )   Get currently focused widget
\   FOC-DISPATCH  ( event-addr -- )   Send key event to focused widget
\   FOC-CLEAR     ( -- )              Clear focus chain (teardown)
\   FOC-COUNT     ( -- n )            Number of focusable widgets

PROVIDED akashic-tui-focus

REQUIRE keys.f
REQUIRE widget.f

\ =====================================================================
\  §1 — Constants & Storage
\ =====================================================================

32 CONSTANT _FOC-MAX            \ Maximum entries in focus chain

\ Parallel arrays — each slot holds a widget pointer and next-index.
\ Index 0 is "null" (unused sentinel).  Valid slots: 1.._FOC-MAX.
CREATE _FOC-WIDGETS  _FOC-MAX 1+ CELLS ALLOT   \ [0.._FOC-MAX] widget ptrs
CREATE _FOC-NEXT-IDX _FOC-MAX 1+ CELLS ALLOT   \ [0.._FOC-MAX] next-index

VARIABLE _FOC-CUR               \ Index of currently focused slot (0=none)
VARIABLE _FOC-CNT               \ Number of entries in chain

\ Temporary variable for multi-step operations
VARIABLE _FOC-TMP

\ =====================================================================
\  §2 — Internal Helpers
\ =====================================================================

\ Access slot widget: ( idx -- addr )
: _FOC-SLOT-W  ( idx -- addr )
    CELLS _FOC-WIDGETS + ;

\ Access slot next-index: ( idx -- addr )
: _FOC-SLOT-N  ( idx -- addr )
    CELLS _FOC-NEXT-IDX + ;

\ Read widget at slot: ( idx -- widget )
: _FOC-W@  ( idx -- widget )
    _FOC-SLOT-W @ ;

\ Read next-index at slot: ( idx -- next-idx )
: _FOC-N@  ( idx -- next-idx )
    _FOC-SLOT-N @ ;

\ Write widget at slot: ( widget idx -- )
: _FOC-W!  ( widget idx -- )
    _FOC-SLOT-W ! ;

\ Write next-index at slot: ( next-idx idx -- )
: _FOC-N!  ( next-idx idx -- )
    _FOC-SLOT-N ! ;

\ Find a free slot.  Returns index (1.._FOC-MAX) or 0 if full.
: _FOC-ALLOC  ( -- idx | 0 )
    _FOC-MAX 1+ 1 DO
        I _FOC-W@ 0= IF I UNLOOP EXIT THEN
    LOOP
    0 ;

\ Find the slot index holding a given widget.  Returns idx or 0.
: _FOC-FIND  ( widget -- idx | 0 )
    _FOC-MAX 1+ 1 DO
        DUP I _FOC-W@ = IF DROP I UNLOOP EXIT THEN
    LOOP
    DROP 0 ;

\ Find the slot whose next-index equals the given index.
\ (Walk the circular chain to find the predecessor.)
\ Requires chain to be non-empty and idx to be in the chain.
: _FOC-PRED  ( idx -- pred-idx )
    _FOC-CUR @ _FOC-TMP !
    BEGIN
        _FOC-TMP @ _FOC-N@ OVER = IF
            DROP _FOC-TMP @ EXIT
        THEN
        _FOC-TMP @ _FOC-N@ _FOC-TMP !
    AGAIN ;

\ =====================================================================
\  §3 — Initialization / Clear
\ =====================================================================

: FOC-CLEAR  ( -- )
    _FOC-WIDGETS _FOC-MAX 1+ CELLS 0 FILL
    _FOC-NEXT-IDX _FOC-MAX 1+ CELLS 0 FILL
    0 _FOC-CUR !
    0 _FOC-CNT ! ;

FOC-CLEAR   \ Initialize on load

\ =====================================================================
\  §4 — FOC-ADD
\ =====================================================================

: FOC-ADD  ( widget -- )
    \ Check if already in chain
    DUP _FOC-FIND 0<> IF DROP EXIT THEN

    \ Allocate a slot
    _FOC-ALLOC DUP 0= IF DROP DROP EXIT THEN  \ full — silently ignore
    _FOC-TMP !                                  \ new-idx in _FOC-TMP

    \ Store widget in new slot
    _FOC-TMP @ _FOC-W!                         \ ( )

    _FOC-CNT @ 0= IF
        \ First entry: self-linked circular list
        _FOC-TMP @ _FOC-TMP @ _FOC-N!
        _FOC-TMP @ _FOC-CUR !
    ELSE
        \ Insert after current: new→cur.next, cur→new
        _FOC-CUR @ _FOC-N@                    \ old-next
        _FOC-TMP @ _FOC-N!                    \ new.next = old-next
        _FOC-TMP @ _FOC-CUR @ _FOC-N!         \ cur.next = new
    THEN

    1 _FOC-CNT +! ;

\ =====================================================================
\  §5 — FOC-REMOVE
\ =====================================================================

: FOC-REMOVE  ( widget -- )
    _FOC-FIND DUP 0= IF DROP EXIT THEN     \ not found

    \ idx on stack
    _FOC-CNT @ 1 = IF
        \ Last entry: clear everything
        0 SWAP _FOC-W!
        0 _FOC-CUR !
        0 _FOC-CNT !
        EXIT
    THEN

    \ Find predecessor
    DUP _FOC-PRED                            \ ( idx pred-idx )

    \ Unlink: pred.next = idx.next
    OVER _FOC-N@                             \ ( idx pred-idx idx-next )
    OVER _FOC-N!                             \ pred.next = idx-next ( idx pred-idx )
    DROP                                     \ ( idx )

    \ If removing the current, move current to next
    DUP _FOC-CUR @ = IF
        DUP _FOC-N@ _FOC-CUR !
    THEN

    \ Clear old focus flag on the widget being removed
    DUP _FOC-W@ _WDG-FOCUS-CLR

    \ Free slot
    0 SWAP _FOC-W!

    -1 _FOC-CNT +! ;

\ =====================================================================
\  §6 — FOC-GET / FOC-SET
\ =====================================================================

: FOC-GET  ( -- widget | 0 )
    _FOC-CUR @ DUP 0= IF EXIT THEN
    _FOC-W@ ;

: FOC-SET  ( widget -- )
    _FOC-FIND DUP 0= IF DROP EXIT THEN     \ not in chain

    \ Clear old focus
    _FOC-CUR @ DUP 0<> IF
        _FOC-W@ _WDG-FOCUS-CLR
    ELSE DROP THEN

    \ Set new focus
    DUP _FOC-CUR !
    _FOC-W@ _WDG-FOCUS-SET ;

\ =====================================================================
\  §7 — FOC-NEXT / FOC-PREV
\ =====================================================================

: FOC-NEXT  ( -- )
    _FOC-CUR @ DUP 0= IF DROP EXIT THEN

    \ Clear old
    DUP _FOC-W@ _WDG-FOCUS-CLR

    \ Advance
    _FOC-N@ DUP _FOC-CUR !

    \ Set new
    _FOC-W@ _WDG-FOCUS-SET ;

: FOC-PREV  ( -- )
    _FOC-CUR @ DUP 0= IF DROP EXIT THEN

    \ Clear old
    DUP _FOC-W@ _WDG-FOCUS-CLR

    \ Walk backwards: find pred of current
    _FOC-PRED DUP _FOC-CUR !

    \ Set new
    _FOC-W@ _WDG-FOCUS-SET ;

\ =====================================================================
\  §8 — FOC-DISPATCH
\ =====================================================================

: FOC-DISPATCH  ( event-addr -- )
    FOC-GET DUP 0= IF 2DROP EXIT THEN
    WDG-HANDLE DROP ;

\ =====================================================================
\  §9 — FOC-COUNT / FOC-EACH
\ =====================================================================

: FOC-COUNT  ( -- n )
    _FOC-CNT @ ;

: FOC-EACH  ( xt -- )
    \ Call xt once per chain entry: xt ( widget -- )
    _FOC-MAX 1+ 1 DO
        I _FOC-W@ DUP 0<> IF OVER EXECUTE ELSE DROP THEN
    LOOP DROP ;

\ =====================================================================
\  §10 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _foc-guard

' FOC-ADD         CONSTANT _foc-add-xt
' FOC-REMOVE      CONSTANT _foc-remove-xt
' FOC-NEXT        CONSTANT _foc-next-xt
' FOC-PREV        CONSTANT _foc-prev-xt
' FOC-SET         CONSTANT _foc-set-xt
' FOC-GET         CONSTANT _foc-get-xt
' FOC-DISPATCH    CONSTANT _foc-dispatch-xt
' FOC-CLEAR       CONSTANT _foc-clear-xt
' FOC-COUNT       CONSTANT _foc-count-xt
' FOC-EACH        CONSTANT _foc-each-xt

: FOC-ADD         _foc-add-xt       _foc-guard WITH-GUARD ;
: FOC-REMOVE      _foc-remove-xt    _foc-guard WITH-GUARD ;
: FOC-NEXT        _foc-next-xt      _foc-guard WITH-GUARD ;
: FOC-PREV        _foc-prev-xt      _foc-guard WITH-GUARD ;
: FOC-SET         _foc-set-xt       _foc-guard WITH-GUARD ;
: FOC-GET         _foc-get-xt       _foc-guard WITH-GUARD ;
: FOC-DISPATCH    _foc-dispatch-xt  _foc-guard WITH-GUARD ;
: FOC-CLEAR       _foc-clear-xt     _foc-guard WITH-GUARD ;
: FOC-COUNT       _foc-count-xt     _foc-guard WITH-GUARD ;
: FOC-EACH        _foc-each-xt      _foc-guard WITH-GUARD ;
[THEN] [THEN]
