\ =====================================================================
\  akashic/tui/tabs.f — Tabbed Panel Widget
\ =====================================================================
\
\  A row of tab headers with a content area below.  Each tab has a
\  label and a child region.  Switching tabs shows the corresponding
\  content region and hides others.
\
\  The widget uses the top row of its region for the tab header bar.
\  Content regions occupy the remaining rows below.
\
\  Tab Entry (3 cells = 24 bytes each):
\    +0   label-a       Tab label string address
\    +8   label-u       Tab label string length
\   +16   content-rgn   Region for this tab's content
\
\  Tabs Descriptor (header + 5 cells = 80 bytes):
\    +0..+32  widget header   type=WDG-T-TABS
\    +40      tabs            Address of tab entry array
\    +48      count           Number of tabs (0..max)
\    +56      active          Currently active tab index
\    +64      max-tabs        Maximum number of tabs (allocated capacity)
\    +72      switch-xt       Tab-switched callback ( index widget -- ) or 0
\
\  Prefix: TAB- (public), _TAB- (internal)
\  Provider: akashic-tui-tabs
\  Dependencies: widget.f, draw.f, box.f, region.f, keys.f

PROVIDED akashic-tui-tabs

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../box.f
REQUIRE ../region.f
REQUIRE ../keys.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _TAB-O-TABS         \ pointer to tab entry array
48 CONSTANT _TAB-O-COUNT        \ current number of tabs
56 CONSTANT _TAB-O-ACTIVE       \ active tab index
64 CONSTANT _TAB-O-MAX          \ max tabs (capacity)
72 CONSTANT _TAB-O-SWITCH-XT    \ callback xt

80 CONSTANT _TAB-DESC-SIZE

\ Tab entry layout (3 cells = 24 bytes)
 0 CONSTANT _TAB-E-LABEL-A
 8 CONSTANT _TAB-E-LABEL-U
16 CONSTANT _TAB-E-CONTENT-RGN

24 CONSTANT _TAB-ENTRY-SIZE

\ Maximum tabs (pre-allocated)
8 CONSTANT _TAB-MAX-DEFAULT

\ =====================================================================
\ 2. Internal helpers
\ =====================================================================

\ _TAB-ENTRY ( widget index -- entry-addr )
\   Get address of tab entry at index.
: _TAB-ENTRY  ( widget index -- entry-addr )
    _TAB-ENTRY-SIZE * SWAP _TAB-O-TABS + @ + ;

\ =====================================================================
\ 3. Internal draw
\ =====================================================================

VARIABLE _TAB-DRW-W    \ widget during draw
VARIABLE _TAB-DRW-RW   \ region width
VARIABLE _TAB-DRW-E    \ current entry
VARIABLE _TAB-DRW-C    \ current column
VARIABLE _TAB-DRW-I    \ outer loop index (avoid J)

\ _TAB-COL-ACC ( outer-index -- col )
\   Compute the column of tab at outer-index by summing previous tab widths.
: _TAB-COL-ACC  ( outer-index -- col )
    0 SWAP                                  \ ( col outer-index )
    0 ?DO
        _TAB-DRW-W @ I _TAB-ENTRY
        _TAB-E-LABEL-U + @ + 3 +           \ " label " = len+2+1 separator
    LOOP ;

\ _TAB-DRAW ( widget -- )
\   Draw tab header row + active tab content border.
: _TAB-DRAW  ( widget -- )
    DUP _TAB-DRW-W !
    WDG-REGION RGN-W  _TAB-DRW-RW !
    \ Clear header row (row 0)
    32 0 0 _TAB-DRW-RW @ DRW-HLINE
    \ Draw tab labels across row 0
    _TAB-DRW-W @ _TAB-O-COUNT + @ 0 ?DO
        _TAB-DRW-W @ I _TAB-ENTRY  _TAB-DRW-E !
        I _TAB-DRW-I !
        \ Compute column position
        I _TAB-COL-ACC  _TAB-DRW-C !
        \ Is this the active tab?
        I _TAB-DRW-W @ _TAB-O-ACTIVE + @ = IF
            CELL-A-REVERSE DRW-ATTR!
        THEN
        \ Draw " label " with padding
        32 0 _TAB-DRW-C @ DRW-CHAR         \ leading space at col
        _TAB-DRW-E @ _TAB-E-LABEL-A + @
        _TAB-DRW-E @ _TAB-E-LABEL-U + @
        0 _TAB-DRW-C @ 1+ DRW-TEXT         \ label text at col+1
        32 0 _TAB-DRW-C @ 1+
        _TAB-DRW-E @ _TAB-E-LABEL-U + @ +
        DRW-CHAR                            \ trailing space
        I _TAB-DRW-W @ _TAB-O-ACTIVE + @ = IF
            0 DRW-ATTR!
        THEN
        \ Draw separator (│) if not last tab
        I 1+ _TAB-DRW-W @ _TAB-O-COUNT + @ < IF
            0x2502 0
            _TAB-DRW-C @ _TAB-DRW-E @ _TAB-E-LABEL-U + @ + 2 +
            DRW-CHAR
        THEN
    LOOP
    \ Draw underline on row 1 if height > 1
    _TAB-DRW-W @ WDG-REGION RGN-H 1 > IF
        0x2500 1 0 _TAB-DRW-RW @ DRW-HLINE
    THEN
    ;

\ =====================================================================
\ 4. Internal handle
\ =====================================================================

VARIABLE _TAB-HND-W   \ widget saved during handle

\ _TAB-HANDLE ( event widget -- consumed? )
: _TAB-HANDLE  ( event widget -- consumed? )
    _TAB-HND-W !
    DUP @ KEY-T-SPECIAL = IF
        8 + @
        CASE
            KEY-LEFT OF
                _TAB-HND-W @ _TAB-O-ACTIVE + @
                DUP 0 > IF
                    1- _TAB-HND-W @ _TAB-O-ACTIVE + !
                    _TAB-HND-W @ WDG-DIRTY
                ELSE
                    DROP
                THEN
                -1
            ENDOF
            KEY-RIGHT OF
                _TAB-HND-W @ _TAB-O-ACTIVE + @
                _TAB-HND-W @ _TAB-O-COUNT + @ 1- < IF
                    _TAB-HND-W @ _TAB-O-ACTIVE + @ 1+
                    _TAB-HND-W @ _TAB-O-ACTIVE + !
                    _TAB-HND-W @ WDG-DIRTY
                THEN
                -1
            ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DROP 0 ;

\ =====================================================================
\ 5. Constructor
\ =====================================================================

\ TAB-NEW ( rgn -- widget )
\   Create empty tab container.
: TAB-NEW  ( rgn -- widget )
    _TAB-DESC-SIZE ALLOCATE
    0<> ABORT" TAB-NEW: alloc failed"      \ ( rgn addr )
    WDG-T-TABS    OVER _WDG-O-TYPE      + !
    SWAP          OVER _WDG-O-REGION    + !
    ['] _TAB-DRAW OVER _WDG-O-DRAW-XT   + !
    ['] _TAB-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                  OVER _WDG-O-FLAGS     + !
    \ Allocate tab entry array
    _TAB-MAX-DEFAULT _TAB-ENTRY-SIZE * ALLOCATE
    0<> ABORT" TAB-NEW: tab array alloc failed"
    OVER _TAB-O-TABS + !
    0             OVER _TAB-O-COUNT     + !   \ count = 0
    0             OVER _TAB-O-ACTIVE    + !   \ active = 0
    _TAB-MAX-DEFAULT
                  OVER _TAB-O-MAX       + !   \ max capacity
    0             OVER _TAB-O-SWITCH-XT + ! ; \ no callback

\ =====================================================================
\ 6. Public API
\ =====================================================================

\ TAB-ADD ( label-a label-u widget -- content-rgn )
\   Add a tab.  Returns the content region for that tab.
\   Content region is rows 2..h-1 of the widget's region (below header+line).
: TAB-ADD  ( label-a label-u widget -- content-rgn )
    DUP _TAB-O-COUNT + @
    OVER _TAB-O-MAX + @ >= IF
        DROP 2DROP 0 EXIT                   \ tab array full
    THEN
    >R                                      \ R: widget
    \ Get current count = new index; compute entry address
    R@ _TAB-O-COUNT + @                    \ ( la lu idx )
    R@ SWAP _TAB-ENTRY                     \ ( la lu entry )
    \ Fill label
    ROT OVER _TAB-E-LABEL-A + !           \ ( lu entry )
    SWAP OVER _TAB-E-LABEL-U + !          \ ( entry )
    \ Create content sub-region: row 2, col 0, h-2, w
    R@ WDG-REGION DUP RGN-H 2 -           \ ( entry rgn h-2 )
    DUP 0< IF DROP 0 THEN                 \ clamp h-2
    SWAP RGN-W                              \ ( entry h-2 w )
    R@ WDG-REGION 2 0 4 PICK 4 PICK       \ ( entry h-2 w rgn 2 0 h-2 w )
    RGN-SUB                                \ ( entry h-2 w content-rgn )
    ROT DROP SWAP DROP                      \ ( entry content-rgn )
    OVER _TAB-E-CONTENT-RGN + !            \ store in entry
    _TAB-E-CONTENT-RGN + @                 \ reload to return
    \ Increment count
    R@ _TAB-O-COUNT + @ 1+
    R> _TAB-O-COUNT + !
    ;

\ TAB-SELECT ( index widget -- )
\   Switch to tab at index.
: TAB-SELECT  ( index widget -- )
    2DUP _TAB-O-ACTIVE + !
    DUP WDG-DIRTY
    DUP _TAB-O-SWITCH-XT + @ DUP 0<> IF
        >R 2DUP R> EXECUTE
    ELSE
        DROP
    THEN
    2DROP ;

\ TAB-ACTIVE ( widget -- index )
: TAB-ACTIVE  ( widget -- index )
    _TAB-O-ACTIVE + @ ;

\ TAB-ON-SWITCH ( xt widget -- )
: TAB-ON-SWITCH  ( xt widget -- )
    _TAB-O-SWITCH-XT + ! ;

\ TAB-CONTENT ( index widget -- rgn )
\   Get content region for tab at index.
: TAB-CONTENT  ( index widget -- rgn )
    SWAP _TAB-ENTRY _TAB-E-CONTENT-RGN + @ ;

\ TAB-COUNT ( widget -- n )
: TAB-COUNT  ( widget -- n )
    _TAB-O-COUNT + @ ;

\ TAB-REMOVE ( index widget -- )
\   Remove tab at index.  Shifts entries above down by one slot.
\   Adjusts active index: if removed < active → active-1,
\   if removed == active or active >= count → clamp.
\   Does NOT free content region or child widgets.
VARIABLE _TAB-RM-W
VARIABLE _TAB-RM-I
: TAB-REMOVE  ( index widget -- )
    _TAB-RM-W !
    \ Bounds check
    DUP _TAB-RM-W @ _TAB-O-COUNT + @ >= IF DROP EXIT THEN
    DUP 0< IF DROP EXIT THEN
    _TAB-RM-I !                                \ save index
    \ How many entries above this one need shifting?
    _TAB-RM-W @ _TAB-O-COUNT + @ 1-  _TAB-RM-I @ -   \ ( entries-above )
    DUP 0> IF
        \ Shift: src = entry[idx+1], dst = entry[idx], cnt = entries * 24
        _TAB-RM-I @ 1+ _TAB-RM-W @ SWAP _TAB-ENTRY   \ ( n src )
        _TAB-RM-I @    _TAB-RM-W @ SWAP _TAB-ENTRY   \ ( n src dst )
        ROT _TAB-ENTRY-SIZE *                  \ ( src dst cnt )
        CMOVE                                  \ KDOS: ( src dst cnt )
    ELSE
        DROP                                   \ no shift needed (was last)
    THEN
    \ Decrement count
    _TAB-RM-W @ _TAB-O-COUNT + @  1-
    _TAB-RM-W @ _TAB-O-COUNT + !
    \ Adjust active index
    _TAB-RM-W @ _TAB-O-COUNT + @ 0= IF
        0 _TAB-RM-W @ _TAB-O-ACTIVE + !       \ no tabs left
    ELSE
        _TAB-RM-I @ _TAB-RM-W @ _TAB-O-ACTIVE + @ < IF
            \ removed tab was before active → shift active down
            _TAB-RM-W @ _TAB-O-ACTIVE + @  1-
            _TAB-RM-W @ _TAB-O-ACTIVE + !
        ELSE
            _TAB-RM-W @ _TAB-O-ACTIVE + @
            _TAB-RM-W @ _TAB-O-COUNT + @ >= IF
                _TAB-RM-W @ _TAB-O-COUNT + @ 1-
                _TAB-RM-W @ _TAB-O-ACTIVE + ! \ clamp to last
            THEN
        THEN
    THEN
    _TAB-RM-W @ WDG-DIRTY ;

\ TAB-LABEL! ( label-a label-u index widget -- )
\   Update the label of an existing tab.  Marks widget dirty.
: TAB-LABEL!  ( label-a label-u index widget -- )
    DUP >R SWAP _TAB-ENTRY                    \ ( la lu entry  R: widget )
    ROT OVER _TAB-E-LABEL-A + !               \ ( lu entry )
    SWAP OVER _TAB-E-LABEL-U + !              \ ( entry )
    DROP R> WDG-DIRTY ;

\ TAB-LABEL@ ( index widget -- label-a label-u )
\   Read the label of tab at index.
: TAB-LABEL@  ( index widget -- label-a label-u )
    SWAP _TAB-ENTRY
    DUP _TAB-E-LABEL-A + @
    SWAP _TAB-E-LABEL-U + @ ;

\ TAB-FREE ( widget -- )
\   Free the tab entry array and descriptor.
: TAB-FREE  ( widget -- )
    DUP _TAB-O-TABS + @ FREE              \ free entry array
    FREE ;                                  \ free descriptor

\ =====================================================================
\ 7. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _tab-guard

' TAB-NEW         CONSTANT _tab-new-xt
' TAB-ADD         CONSTANT _tab-add-xt
' TAB-REMOVE      CONSTANT _tab-remove-xt
' TAB-SELECT      CONSTANT _tab-select-xt
' TAB-ACTIVE      CONSTANT _tab-active-xt
' TAB-ON-SWITCH   CONSTANT _tab-onswitch-xt
' TAB-CONTENT     CONSTANT _tab-content-xt
' TAB-COUNT       CONSTANT _tab-count-xt
' TAB-LABEL!      CONSTANT _tab-label-s-xt
' TAB-LABEL@      CONSTANT _tab-label-g-xt
' TAB-FREE        CONSTANT _tab-free-xt

: TAB-NEW         _tab-new-xt       _tab-guard WITH-GUARD ;
: TAB-ADD         _tab-add-xt       _tab-guard WITH-GUARD ;
: TAB-REMOVE      _tab-remove-xt    _tab-guard WITH-GUARD ;
: TAB-SELECT      _tab-select-xt    _tab-guard WITH-GUARD ;
: TAB-ACTIVE      _tab-active-xt    _tab-guard WITH-GUARD ;
: TAB-ON-SWITCH   _tab-onswitch-xt  _tab-guard WITH-GUARD ;
: TAB-CONTENT     _tab-content-xt   _tab-guard WITH-GUARD ;
: TAB-COUNT       _tab-count-xt     _tab-guard WITH-GUARD ;
: TAB-LABEL!      _tab-label-s-xt   _tab-guard WITH-GUARD ;
: TAB-LABEL@      _tab-label-g-xt   _tab-guard WITH-GUARD ;
: TAB-FREE        _tab-free-xt      _tab-guard WITH-GUARD ;
[THEN] [THEN]
