\ table.f — Slot-Array / Table Abstraction for KDOS / Megapad-64
\
\ Fixed-width slot array with alloc/free/iterate.
\ Useful for DNS caches, session pools, record lists.
\
\ Table layout in memory (byte offsets from tbl):
\   [0..7]   slot-size  (cell)
\   [8..15]  max-slots  (cell)
\   [16..23] used-count (cell)
\   [24..]   slot 0:  [flag-byte | data ... ]
\             ...
\   Flag byte: 0 = free, 1 = used.
\   Stride = 1 + slot-size.
\
\ Prefix: TBL-   (public API)
\         _TBL-  (internal helpers)
\
\ Load with:   REQUIRE table.f

PROVIDED akashic-table

\ =====================================================================
\  Header Field Offsets
\ =====================================================================

\ Cell-based offsets from table base.
: _TBL-SIZE   ( tbl -- addr )   ;                    \ offset 0
: _TBL-MAX    ( tbl -- addr )   8 + ;                \ offset 8
: _TBL-CNT    ( tbl -- addr )   16 + ;               \ offset 16

24 CONSTANT _TBL-HDR  \ header size in bytes

\ =====================================================================
\  Stride & Slot Addressing
\ =====================================================================

\ _TBL-STRIDE ( tbl -- stride )   1 + slot-size
: _TBL-STRIDE  ( tbl -- stride )
    @ 1+ ;

\ _TBL-FLAG ( tbl idx -- flag-addr )
\   Address of the flag byte for slot idx.
: _TBL-FLAG  ( tbl idx -- flag-addr )
    OVER _TBL-STRIDE *       \ idx * stride
    SWAP _TBL-HDR +          \ tbl + header
    + ;                      \ flag-addr

\ _TBL-DATA ( tbl idx -- data-addr )
\   Address of the data region for slot idx (flag + 1).
: _TBL-DATA  ( tbl idx -- data-addr )
    _TBL-FLAG 1+ ;

\ =====================================================================
\  Public API
\ =====================================================================

\ TBL-CREATE ( slot-size max-slots addr -- )
\   Initialise a table at addr.  Zeros all slot flags.

VARIABLE _TBL-A   \ table address (used by several words)
VARIABLE _TBL-S   \ slot size  (used during CREATE)
VARIABLE _TBL-N   \ max slots  (used during CREATE)

: TBL-CREATE  ( slot-size max-slots addr -- )
    _TBL-A !  _TBL-N !  _TBL-S !
    _TBL-S @  _TBL-A @ !            \ store slot-size
    _TBL-N @  _TBL-A @ 8 + !        \ store max-slots
    0         _TBL-A @ 16 + !       \ count = 0
    \ Zero all flag bytes
    _TBL-N @ 0 ?DO
        0  _TBL-A @  I _TBL-FLAG  C!
    LOOP ;

\ TBL-ALLOC ( tbl -- slot-addr | 0 )
\   Find first free slot, mark used, return data pointer.  0 if full.
: TBL-ALLOC  ( tbl -- slot-addr | 0 )
    DUP _TBL-A !
    8 + @                         \ max-slots (consumes tbl)
    0 ?DO
        _TBL-A @  I  _TBL-FLAG
        DUP C@ 0= IF
            1 SWAP C!             \ mark used
            1 _TBL-A @ 16 + +!   \ count++
            _TBL-A @  I  _TBL-DATA
            UNLOOP EXIT
        THEN DROP
    LOOP
    0 ;

\ TBL-FREE ( tbl slot-addr -- )
\   Mark slot as free.  The slot-addr must point to the data area
\   (i.e. the value returned by TBL-ALLOC / TBL-SLOT).
: TBL-FREE  ( tbl slot-addr -- )
    1-                           \ back up to flag byte
    DUP C@ 1 = IF                \ only decrement count if was used
        0 SWAP C!                \ clear flag
        16 + -1 SWAP +!          \ count--
    ELSE
        DROP DROP                \ already free; nothing to do
    THEN ;

\ TBL-COUNT ( tbl -- n )
\   Number of used slots.
: TBL-COUNT  ( tbl -- n )
    16 + @ ;

\ TBL-SLOT ( tbl idx -- slot-addr | 0 )
\   Address of slot data by 0-based index.
\   Returns 0 if idx out of range or slot is free.
: TBL-SLOT  ( tbl idx -- slot-addr | 0 )
    2DUP SWAP 8 + @ >= IF       \ idx >= max?
        2DROP 0 EXIT
    THEN
    2DUP _TBL-FLAG C@ 0= IF     \ free?
        2DROP 0 EXIT
    THEN
    _TBL-DATA ;

\ TBL-EACH ( tbl xt -- )
\   Execute xt for each used slot.  xt signature: ( slot-addr -- ).
VARIABLE _TBL-XT

: TBL-EACH  ( tbl xt -- )
    _TBL-XT !
    DUP _TBL-A !
    8 + @                        \ max-slots
    0 ?DO
        _TBL-A @  I  _TBL-FLAG
        C@ 1 = IF
            _TBL-A @  I  _TBL-DATA
            _TBL-XT @ EXECUTE
        THEN
    LOOP ;

\ TBL-FIND ( tbl xt -- slot-addr | 0 )
\   Find first used slot where xt returns true.
\   xt signature: ( slot-addr -- flag ).
: TBL-FIND  ( tbl xt -- slot-addr | 0 )
    _TBL-XT !
    DUP _TBL-A !
    8 + @                        \ max-slots
    0 ?DO
        _TBL-A @  I  _TBL-FLAG
        C@ 1 = IF
            _TBL-A @  I  _TBL-DATA DUP
            _TBL-XT @ EXECUTE IF
                UNLOOP EXIT      \ return slot-addr
            THEN DROP
        THEN
    LOOP
    0 ;

\ TBL-FLUSH ( tbl -- )
\   Mark all slots free, reset count to 0.
: TBL-FLUSH  ( tbl -- )
    DUP _TBL-A !
    DUP 8 + @                    \ max-slots
    0 ?DO
        _TBL-A @  I  _TBL-FLAG
        0 SWAP C!
    LOOP
    0 SWAP 16 + ! ;
