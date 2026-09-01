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
\  Tab Entry (4 cells = 32 bytes each):
\    +0   label-a       Tab label string address
\    +8   label-u       Tab label string length
\   +16   content-rgn   Region for this tab's content
\   +24   key           Stable nonzero identity for this tab lifetime
\
\  Tabs Descriptor (header + 8 cells = 104 bytes):
\    +0..+32  widget header   type=WDG-T-TABS
\    +40      tabs            Address of tab entry array
\    +48      count           Number of tabs (0..max)
\    +56      active          Currently active tab index
\    +64      max-tabs        Maximum number of tabs (allocated capacity)
\    +72      switch-xt       Tab-switched callback ( index widget -- ) or 0
\    +80      instance        Nonzero allocation-lifetime identity
\    +88      next-key        Last per-widget tab key issued
\    +96      entry-bytes     Exact allocated tab-entry span
\
\  Prefix: TAB- (public), _TAB- (internal)
\  Provider: akashic-tui-tabs
\  Dependencies: widget.f, draw.f, box.f, region.f, keys.f,
\                semantic-collections.f, memory-span.f

PROVIDED akashic-tui-tabs

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../box.f
REQUIRE ../region.f
REQUIRE ../keys.f
REQUIRE ../semantic-collections.f
REQUIRE ../../utils/memory-span.f

CREATE _TAB-OWNED-START
VARIABLE _TAB-OWNED-LIMIT
0 _TAB-OWNED-LIMIT !

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _TAB-O-TABS         \ pointer to tab entry array
48 CONSTANT _TAB-O-COUNT        \ current number of tabs
56 CONSTANT _TAB-O-ACTIVE       \ active tab index
64 CONSTANT _TAB-O-MAX          \ max tabs (capacity)
72 CONSTANT _TAB-O-SWITCH-XT    \ callback xt
80 CONSTANT _TAB-O-INSTANCE     \ nonpointer allocation identity
88 CONSTANT _TAB-O-NEXT-KEY     \ last stable tab key issued
96 CONSTANT _TAB-O-ENTRY-BYTES  \ exact allocated entry-array bytes

104 CONSTANT _TAB-DESC-SIZE

\ Tab entry layout (4 cells = 32 bytes)
 0 CONSTANT _TAB-E-LABEL-A
 8 CONSTANT _TAB-E-LABEL-U
16 CONSTANT _TAB-E-CONTENT-RGN
24 CONSTANT _TAB-E-KEY

32 CONSTANT _TAB-ENTRY-SIZE

\ Compatibility capacity for TAB-NEW.  Production callers can select any
\ checked allocation capacity with TAB-NEW-CAP; capture has no separate cap.
8 CONSTANT _TAB-MAX-DEFAULT

-1 1 RSHIFT CONSTANT _TAB-SIGNED-MAX

\ =====================================================================
\ 2. Internal helpers
\ =====================================================================

\ _TAB-ENTRY ( widget index -- entry-addr )
\   Get address of tab entry at index.
: _TAB-ENTRY  ( widget index -- entry-addr )
    _TAB-ENTRY-SIZE * SWAP _TAB-O-TABS + @ + ;

: _TAB-CAPACITY-BYTES?  ( max-tabs -- bytes flag )
    DUP 0< IF DROP 0 0 EXIT THEN
    DUP _TAB-SIGNED-MAX _TAB-ENTRY-SIZE / U> IF DROP 0 0 EXIT THEN
    _TAB-ENTRY-SIZE * -1 ;

VARIABLE _TAB-NEXT-INSTANCE
0 _TAB-NEXT-INSTANCE !

: _TAB-CLAIM-INSTANCE  ( -- token )
    _TAB-NEXT-INSTANCE @ DUP -1 =
        IF DROP 1 ELSE 1+ DUP 0= IF DROP 1 THEN THEN
    DUP _TAB-NEXT-INSTANCE ! ;

: _TAB-CLAIM-KEY  ( widget -- key|0 )
    DUP _TAB-O-NEXT-KEY + @ DUP -1 = IF 2DROP 0 EXIT THEN
    1+ DUP ROT _TAB-O-NEXT-KEY + ! ;

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
        _TAB-E-LABEL-U + @ + 2 +           \ same header spacing as UIDL tabs
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
VARIABLE _TAB-HIT-ROW
VARIABLE _TAB-HIT-COL
VARIABLE _TAB-HIT-WIDGET
VARIABLE _TAB-HIT-REL
VARIABLE _TAB-HIT-POS
VARIABLE _TAB-HIT-SPAN

\ TAB-HIT-INDEX ( absolute-row absolute-column widget -- index flag )
\   Resolve one ordinary header hit using the same root-local convention as
\   core UIDL tabs: labels begin at column one and each next label begins
\   label-length+2 columns later.  Only row zero of the widget is interactive;
\   the underline and content panel are not tab targets.
: TAB-HIT-INDEX  ( absolute-row absolute-column widget -- index flag )
    _TAB-HIT-WIDGET ! _TAB-HIT-COL ! _TAB-HIT-ROW !
    _TAB-HIT-ROW @ _TAB-HIT-WIDGET @ WDG-REGION RGN-ROW <> IF
        0 0 EXIT
    THEN
    _TAB-HIT-COL @ _TAB-HIT-WIDGET @ WDG-REGION RGN-COL -
    DUP 0< IF DROP 0 0 EXIT THEN
    DUP _TAB-HIT-WIDGET @ WDG-REGION RGN-W U< 0= IF
        DROP 0 0 EXIT
    THEN
    _TAB-HIT-REL !
    1 _TAB-HIT-POS !
    _TAB-HIT-WIDGET @ _TAB-O-COUNT + @ 0 ?DO
        _TAB-HIT-WIDGET @ I _TAB-ENTRY _TAB-E-LABEL-U + @
        DUP 0< IF DROP 0 0 UNLOOP EXIT THEN
        DUP _TAB-SIGNED-MAX 2 - U> IF DROP 0 0 UNLOOP EXIT THEN
        2 + _TAB-HIT-SPAN !
        _TAB-HIT-REL @ _TAB-HIT-POS @ U< 0= IF
            _TAB-HIT-REL @ _TAB-HIT-POS @ - _TAB-HIT-SPAN @ U< IF
                I -1 UNLOOP EXIT
            THEN
        THEN
        _TAB-HIT-POS @ _TAB-HIT-SPAN @ +
        DUP _TAB-HIT-POS @ U< IF DROP 0 0 UNLOOP EXIT THEN
        _TAB-HIT-POS !
    LOOP
    0 0 ;

\ _TAB-SELECT! ( index widget -- )
\   One ordinary state transition for API, keyboard, and later intent routes.
: _TAB-SELECT!  ( index widget -- )
    2DUP _TAB-O-ACTIVE + !
    DUP WDG-DIRTY
    DUP _TAB-O-SWITCH-XT + @ DUP 0<> IF
        >R 2DUP R> EXECUTE
    ELSE
        DROP
    THEN
    2DROP ;

\ _TAB-HANDLE ( event widget -- consumed? )
: _TAB-HANDLE  ( event widget -- consumed? )
    _TAB-HND-W !
    DUP @ KEY-T-SPECIAL = IF
        8 + @
        CASE
            KEY-LEFT OF
                _TAB-HND-W @ _TAB-O-ACTIVE + @
                DUP 0 > IF
                    1- _TAB-HND-W @ _TAB-SELECT!
                ELSE
                    DROP
                THEN
                -1
            ENDOF
            KEY-RIGHT OF
                _TAB-HND-W @ _TAB-O-ACTIVE + @
                _TAB-HND-W @ _TAB-O-COUNT + @ 1- < IF
                    _TAB-HND-W @ _TAB-O-ACTIVE + @ 1+
                    _TAB-HND-W @ _TAB-SELECT!
                THEN
                -1
            ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DUP @ KEY-T-MOUSE = IF
        DUP 8 + @ KEY-MOUSE-LEFT <> IF DROP 0 EXIT THEN
        16 + @ DUP 16 RSHIFT SWAP 0xFFFF AND
        _TAB-HND-W @ TAB-HIT-INDEX IF
            _TAB-HND-W @ _TAB-SELECT!
            -1
        ELSE
            DROP 0
        THEN
        EXIT
    THEN
    DROP 0 ;

\ =====================================================================
\ 5. Constructor
\ =====================================================================

VARIABLE _TAB-NC-RGN
VARIABLE _TAB-NC-CAP
VARIABLE _TAB-NC-BYTES
VARIABLE _TAB-NC-ARRAY
VARIABLE _TAB-NC-INSTANCE
VARIABLE _TAB-NC-WIDGET

\ TAB-NEW-CAP ( rgn max-tabs -- widget )
\   Create an empty tab container with an exact caller-selected entry
\   capacity.  This is an ordinary widget allocation bound, not a semantic
\   collection or terminal limit.  Zero capacity is a valid empty widget.
: TAB-NEW-CAP  ( rgn max-tabs -- widget )
    _TAB-NC-CAP ! _TAB-NC-RGN !
    _TAB-NC-RGN @ DUP 0= ABORT" TAB-NEW-CAP: region"
    DUP 7 AND ABORT" TAB-NEW-CAP: region alignment"
    RGN-SIZE MSPAN-NONWRAPPING? 0= ABORT" TAB-NEW-CAP: region span"
    _TAB-NC-CAP @ _TAB-CAPACITY-BYTES?
        0= ABORT" TAB-NEW-CAP: capacity"
    _TAB-NC-BYTES !
    _TAB-CLAIM-INSTANCE _TAB-NC-INSTANCE !
    _TAB-DESC-SIZE ALLOCATE
    0<> ABORT" TAB-NEW-CAP: descriptor alloc"
    _TAB-NC-WIDGET !
    _TAB-NC-BYTES @ IF
        _TAB-NC-BYTES @ ALLOCATE DUP IF
            2DROP
            _TAB-NC-WIDGET @ FREE
            -1 ABORT" TAB-NEW-CAP: entry alloc"
        THEN
        DROP
    ELSE
        0
    THEN
    _TAB-NC-ARRAY !
    WDG-T-TABS _TAB-NC-WIDGET @ _WDG-O-TYPE + !
    _TAB-NC-RGN @ _TAB-NC-WIDGET @ _WDG-O-REGION + !
    ['] _TAB-DRAW _TAB-NC-WIDGET @ _WDG-O-DRAW-XT + !
    ['] _TAB-HANDLE _TAB-NC-WIDGET @ _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
        _TAB-NC-WIDGET @ _WDG-O-FLAGS + !
    _TAB-NC-ARRAY @ _TAB-NC-WIDGET @ _TAB-O-TABS + !
    0 _TAB-NC-WIDGET @ _TAB-O-COUNT + !
    0 _TAB-NC-WIDGET @ _TAB-O-ACTIVE + !
    _TAB-NC-CAP @ _TAB-NC-WIDGET @ _TAB-O-MAX + !
    0 _TAB-NC-WIDGET @ _TAB-O-SWITCH-XT + !
    _TAB-NC-INSTANCE @ _TAB-NC-WIDGET @ _TAB-O-INSTANCE + !
    0 _TAB-NC-WIDGET @ _TAB-O-NEXT-KEY + !
    _TAB-NC-BYTES @ _TAB-NC-WIDGET @ _TAB-O-ENTRY-BYTES + !
    _TAB-NC-WIDGET @ ;

\ TAB-NEW ( rgn -- widget )
\   Compatibility constructor using the historical ordinary default.
: TAB-NEW  ( rgn -- widget )
    _TAB-MAX-DEFAULT TAB-NEW-CAP ;

\ =====================================================================
\ 6. Public API
\ =====================================================================

\ TAB-ADD ( label-a label-u widget -- content-rgn )
\   Add a tab.  Returns the content region for that tab.
\   Content region is rows 2..h-1 of the widget's region (below header+line).
VARIABLE _TAB-ADD-KEY
: TAB-ADD  ( label-a label-u widget -- content-rgn )
    DUP _TAB-O-COUNT + @
    OVER _TAB-O-MAX + @ >= IF
        DROP 2DROP 0 EXIT                   \ tab array full
    THEN
    DUP _TAB-CLAIM-KEY DUP 0= IF
        DROP DROP 2DROP 0 EXIT              \ per-widget key space exhausted
    THEN
    _TAB-ADD-KEY !
    >R                                      \ R: widget
    \ Get current count = new index; compute entry address
    R@ _TAB-O-COUNT + @                    \ ( la lu idx )
    R@ SWAP _TAB-ENTRY                     \ ( la lu entry )
    \ Fill label
    ROT OVER _TAB-E-LABEL-A + !           \ ( lu entry )
    SWAP OVER _TAB-E-LABEL-U + !          \ ( entry )
    _TAB-ADD-KEY @ OVER _TAB-E-KEY + !
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
    _TAB-SELECT! ;

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

\ TAB-CAPACITY ( widget -- n )
: TAB-CAPACITY  ( widget -- n )
    _TAB-O-MAX + @ ;

\ TAB-KEY@ ( index widget -- key )
\   Stable for the tab's lifetime across label changes and entry shifts.
: TAB-KEY@  ( index widget -- key )
    SWAP _TAB-ENTRY _TAB-E-KEY + @ ;

\ TAB-INSTANCE@ ( widget -- token )
\   Stable, nonpointer identity for this widget allocation's lifetime.
: TAB-INSTANCE@  ( widget -- token )
    _TAB-O-INSTANCE + @ ;

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
        \ Shift complete entries, preserving each tab's stable key.
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
    DUP _TAB-O-TABS + @ ?DUP IF FREE THEN \ free entry array
    FREE ;                                  \ free descriptor

\ =====================================================================
\ 7. Renderer-neutral TABSET observation
\ =====================================================================
\
\ This read-only source observes the same labels, selection, geometry, and
\ stable entry identities used by ordinary TAB drawing and input.  It knows
\ nothing about UIDL attachments, publication revisions, retained controls,
\ renderers, or applets.  The caller supplies the root key, builder scratch,
\ and exact output bank.  Destination 0/capacity 0 is exact measure mode.

\ Pure first-line authority.  Keep it outside the guarded surface so upper
\ collectors can reject aliases of module scratch (including the guard)
\ before either this module or its guard writes state.
: TAB-STORAGE-DISJOINT?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _TAB-OWNED-LIMIT @ DUP _TAB-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _TAB-OWNED-START - >R
    _TAB-OWNED-START R> MSPAN-OVERLAP? 0= ;

: _TAB-BORROWED-SPAN?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _TAB-POSITIVE-U32?  ( value -- flag )
    DUP 0> SWAP 0x100000000 U< AND ;

VARIABLE _TAB-G-WIDGET
VARIABLE _TAB-G-CAP
VARIABLE _TAB-G-BYTES
VARIABLE _TAB-G-COUNT
VARIABLE _TAB-G-ACTIVE

: _TAB-GENUINE?  ( widget -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _TAB-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _TAB-G-WIDGET !
    DUP _WDG-O-TYPE + @ WDG-T-TABS <> IF DROP 0 EXIT THEN
    DUP _WDG-O-DRAW-XT + @ ['] _TAB-DRAW <> IF DROP 0 EXIT THEN
    DUP _WDG-O-HANDLE-XT + @ ['] _TAB-HANDLE <> IF DROP 0 EXIT THEN
    DUP _TAB-O-INSTANCE + @ 0= IF DROP 0 EXIT THEN
    DUP WDG-REGION DUP 0= IF 2DROP 0 EXIT THEN
    DUP 7 AND IF 2DROP 0 EXIT THEN
    RGN-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DROP
    _TAB-G-WIDGET @ _TAB-O-MAX + @ DUP _TAB-G-CAP !
        _TAB-CAPACITY-BYTES? 0= IF DROP 0 EXIT THEN
        _TAB-G-BYTES !
    _TAB-G-WIDGET @ _TAB-O-ENTRY-BYTES + @ _TAB-G-BYTES @ <> IF
        0 EXIT
    THEN
    _TAB-G-BYTES @ IF
        _TAB-G-WIDGET @ _TAB-O-TABS + @ DUP 0= IF DROP 0 EXIT THEN
        DUP 7 AND IF DROP 0 EXIT THEN
        _TAB-G-BYTES @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    ELSE
        _TAB-G-WIDGET @ _TAB-O-TABS + @ IF 0 EXIT THEN
    THEN
    _TAB-G-WIDGET @ _TAB-O-COUNT + @ DUP _TAB-G-COUNT !
    DUP 0< IF DROP 0 EXIT THEN
    DUP 0x100000000 U< 0= IF DROP 0 EXIT THEN
    _TAB-G-CAP @ U> IF 0 EXIT THEN
    _TAB-G-WIDGET @ _TAB-O-ACTIVE + @ DUP _TAB-G-ACTIVE !
    _TAB-G-COUNT @ 0= IF 0= EXIT THEN
    DUP 0< IF DROP 0 EXIT THEN
    _TAB-G-COUNT @ U< ;

VARIABLE _TAB-SD-A
VARIABLE _TAB-SD-U
VARIABLE _TAB-SD-WIDGET
VARIABLE _TAB-SD-ENTRY
VARIABLE _TAB-SD-LABEL-A
VARIABLE _TAB-SD-LABEL-U
VARIABLE _TAB-SD-CONTENT

: _TAB-SD-OVERLAP?  ( address bytes -- flag )
    _TAB-SD-A @ _TAB-SD-U @ 2SWAP MSPAN-OVERLAP? ;

\ TAB-TABSET-STORAGE-DISJOINT? ( address bytes widget -- flag )
\   Reject aliases of all live state read by TABSET capture.  The complete
\   allocated entry array is protected, not merely its currently used prefix;
\   each live borrowed label and child-region descriptor is protected too.
: TAB-TABSET-STORAGE-DISJOINT?  ( address bytes widget -- flag )
    >R
    2DUP TAB-STORAGE-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    _TAB-SD-U ! _TAB-SD-A ! R> _TAB-SD-WIDGET !
    _TAB-SD-WIDGET @ _TAB-GENUINE? 0= IF 0 EXIT THEN
    _TAB-SD-WIDGET @ _TAB-DESC-SIZE _TAB-SD-OVERLAP? IF 0 EXIT THEN
    _TAB-SD-WIDGET @ WDG-REGION RGN-SIZE _TAB-SD-OVERLAP? IF 0 EXIT THEN
    _TAB-SD-WIDGET @ _TAB-O-ENTRY-BYTES + @ IF
        _TAB-SD-WIDGET @ _TAB-O-TABS + @
        _TAB-SD-WIDGET @ _TAB-O-ENTRY-BYTES + @
        _TAB-SD-OVERLAP? IF 0 EXIT THEN
    THEN
    _TAB-SD-WIDGET @ _TAB-O-COUNT + @ 0 ?DO
        _TAB-SD-WIDGET @ I _TAB-ENTRY DUP _TAB-SD-ENTRY !
        DUP _TAB-E-KEY + @ 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _TAB-E-LABEL-A + @ _TAB-SD-LABEL-A !
        DUP _TAB-E-LABEL-U + @ _TAB-SD-LABEL-U !
        _TAB-E-CONTENT-RGN + @ _TAB-SD-CONTENT !
        _TAB-SD-LABEL-U @ 0> 0= IF 0 UNLOOP EXIT THEN
        _TAB-SD-LABEL-A @ _TAB-SD-LABEL-U @
            _TAB-BORROWED-SPAN? 0= IF 0 UNLOOP EXIT THEN
        _TAB-SD-LABEL-A @ _TAB-SD-LABEL-U @
            _TAB-SD-OVERLAP? IF 0 UNLOOP EXIT THEN
        _TAB-SD-CONTENT @ DUP 0= IF DROP 0 UNLOOP EXIT THEN
        DUP 7 AND IF DROP 0 UNLOOP EXIT THEN
        DUP RGN-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 UNLOOP EXIT THEN
        RGN-SIZE _TAB-SD-OVERLAP? IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

VARIABLE _TAB-C-ROOT
VARIABLE _TAB-C-DST
VARIABLE _TAB-C-CAP
VARIABLE _TAB-C-BUILDER
VARIABLE _TAB-C-WIDGET
VARIABLE _TAB-C-ROOT-H
VARIABLE _TAB-C-ROOT-W
VARIABLE _TAB-C-ROOT-STATE
VARIABLE _TAB-C-TAB-STATE
VARIABLE _TAB-C-ENTRY

: _TAB-CAPTURE-PREFLIGHT?  ( root destination capacity builder widget -- flag )
    DUP _TAB-GENUINE? 0= IF 0 EXIT THEN
    4 PICK 0= IF 0 EXIT THEN
    3 PICK 3 PICK 2 PICK TAB-TABSET-STORAGE-DISJOINT? 0= IF
        0 EXIT
    THEN
    1 PICK USCOL-BUILDER-SIZE 2 PICK
        TAB-TABSET-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    1 PICK USCOL-BUILDER-SIZE USCOL-STORAGE-DISJOINT? 0= IF
        0 EXIT
    THEN
    -1 ;

\ TAB-TABSET-CAPTURE
\   ( root-key destination capacity builder widget -- bytes status )
\   Root geometry covers only the ordinary two-row header paint (or the one
\   available row of a one-row widget), never the content panel below it.
: TAB-TABSET-CAPTURE
    ( root-key destination capacity builder widget -- bytes status )
    1 PICK USCOL-BUILDER-SIZE TAB-STORAGE-DISJOINT? 0= IF
        2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT
    THEN
    3 PICK 3 PICK TAB-STORAGE-DISJOINT? 0= IF
        2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT
    THEN
    _TAB-CAPTURE-PREFLIGHT? 0= IF
        2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT
    THEN
    _TAB-C-WIDGET ! _TAB-C-BUILDER ! _TAB-C-CAP !
    _TAB-C-DST ! _TAB-C-ROOT !
    _TAB-C-DST @ _TAB-C-CAP @ _TAB-C-BUILDER @ USCOL-BUILDER-INIT
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TAB-C-WIDGET @ WDG-REGION RGN-H DUP 0> 0= IF
        DROP 0 USCOL-S-UNAVAILABLE EXIT
    THEN
    2 MIN _TAB-C-ROOT-H !
    _TAB-C-WIDGET @ WDG-REGION RGN-W DUP _TAB-POSITIVE-U32? 0= IF
        DROP 0 USCOL-S-UNAVAILABLE EXIT
    THEN
    _TAB-C-ROOT-W !
    0 _TAB-C-ROOT-STATE !
    _TAB-C-WIDGET @ WDG-VISIBLE? IF
        USCOL-STATE-VISIBLE _TAB-C-ROOT-STATE +!
    THEN
    _TAB-C-WIDGET @ WDG-DISABLED? 0= IF
        USCOL-STATE-ENABLED _TAB-C-ROOT-STATE +!
    THEN
    _TAB-C-ROOT @ 0 0 _TAB-C-ROOT-H @ _TAB-C-ROOT-W @
    _TAB-C-ROOT-STATE @ _TAB-C-BUILDER @ USCOL-TABSET-BEGIN
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TAB-C-WIDGET @ _TAB-O-COUNT + @ 0 ?DO
        _TAB-C-WIDGET @ I _TAB-ENTRY _TAB-C-ENTRY !
        0 _TAB-C-TAB-STATE !
        _TAB-C-WIDGET @ WDG-VISIBLE? IF
            USCOL-STATE-VISIBLE _TAB-C-TAB-STATE +!
        THEN
        _TAB-C-WIDGET @ WDG-DISABLED? 0= IF
            USCOL-STATE-ENABLED _TAB-C-TAB-STATE +!
        THEN
        I _TAB-C-WIDGET @ _TAB-O-ACTIVE + @ =
        _TAB-C-WIDGET @ WDG-VISIBLE? AND
        _TAB-C-WIDGET @ WDG-DISABLED? 0= AND IF
            USCOL-STATE-SELECTED _TAB-C-TAB-STATE +!
        THEN
        _TAB-C-ENTRY @ _TAB-E-KEY + @ I _TAB-C-TAB-STATE @
        _TAB-C-ENTRY @ _TAB-E-LABEL-A + @
        _TAB-C-ENTRY @ _TAB-E-LABEL-U + @
        0 0 _TAB-C-BUILDER @ USCOL-TAB
        DUP USCOL-S-OK <> IF 0 SWAP UNLOOP EXIT THEN DROP
    LOOP
    _TAB-C-BUILDER @ USCOL-TABSET-END
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TAB-C-BUILDER @ USCOL-BUILDER-FINISH ;

\ TAB-TABSET-MEASURE ( root-key builder widget -- bytes status )
: TAB-TABSET-MEASURE  ( root-key builder widget -- bytes status )
    >R >R 0 0 R> R> TAB-TABSET-CAPTURE ;

\ =====================================================================
\ 8. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _tab-guard

' TAB-NEW-CAP     CONSTANT _tab-new-cap-xt
' TAB-NEW         CONSTANT _tab-new-xt
' TAB-ADD         CONSTANT _tab-add-xt
' TAB-REMOVE      CONSTANT _tab-remove-xt
' TAB-SELECT      CONSTANT _tab-select-xt
' TAB-ACTIVE      CONSTANT _tab-active-xt
' TAB-ON-SWITCH   CONSTANT _tab-onswitch-xt
' TAB-CONTENT     CONSTANT _tab-content-xt
' TAB-COUNT       CONSTANT _tab-count-xt
' TAB-CAPACITY    CONSTANT _tab-capacity-xt
' TAB-KEY@        CONSTANT _tab-key-at-xt
' TAB-INSTANCE@   CONSTANT _tab-instance-at-xt
' TAB-HIT-INDEX   CONSTANT _tab-hit-index-xt
' TAB-LABEL!      CONSTANT _tab-label-s-xt
' TAB-LABEL@      CONSTANT _tab-label-g-xt
' TAB-FREE        CONSTANT _tab-free-xt
' TAB-TABSET-CAPTURE CONSTANT _tab-tabset-capture-xt
' TAB-TABSET-MEASURE CONSTANT _tab-tabset-measure-xt
' TAB-TABSET-STORAGE-DISJOINT?
    CONSTANT _tab-tabset-storage-disjoint-q-xt

: TAB-NEW-CAP     _tab-new-cap-xt   _tab-guard WITH-GUARD ;
: TAB-NEW         _tab-new-xt       _tab-guard WITH-GUARD ;
: TAB-ADD         _tab-add-xt       _tab-guard WITH-GUARD ;
: TAB-REMOVE      _tab-remove-xt    _tab-guard WITH-GUARD ;
: TAB-SELECT      _tab-select-xt    _tab-guard WITH-GUARD ;
: TAB-ACTIVE      _tab-active-xt    _tab-guard WITH-GUARD ;
: TAB-ON-SWITCH   _tab-onswitch-xt  _tab-guard WITH-GUARD ;
: TAB-CONTENT     _tab-content-xt   _tab-guard WITH-GUARD ;
: TAB-COUNT       _tab-count-xt     _tab-guard WITH-GUARD ;
: TAB-CAPACITY    _tab-capacity-xt  _tab-guard WITH-GUARD ;
: TAB-KEY@        _tab-key-at-xt    _tab-guard WITH-GUARD ;
: TAB-INSTANCE@   _tab-instance-at-xt _tab-guard WITH-GUARD ;
: TAB-HIT-INDEX   _tab-hit-index-xt _tab-guard WITH-GUARD ;
: TAB-LABEL!      _tab-label-s-xt   _tab-guard WITH-GUARD ;
: TAB-LABEL@      _tab-label-g-xt   _tab-guard WITH-GUARD ;
: TAB-FREE        _tab-free-xt      _tab-guard WITH-GUARD ;
: TAB-TABSET-CAPTURE
    _tab-tabset-capture-xt _tab-guard WITH-GUARD ;
: TAB-TABSET-MEASURE
    _tab-tabset-measure-xt _tab-guard WITH-GUARD ;
: TAB-TABSET-STORAGE-DISJOINT?
    _tab-tabset-storage-disjoint-q-xt _tab-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _TAB-OWNED-END
_TAB-OWNED-END _TAB-OWNED-LIMIT !
