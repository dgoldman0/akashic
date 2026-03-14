\ =====================================================================
\  akashic/utils/clipboard.f — Clipboard Ring Buffer for KDOS
\ =====================================================================
\
\  A general-purpose clipboard with a configurable ring of entries.
\  All content buffers live in XMEM (extended memory), keeping
\  precious Bank 0 heap / dictionary space free.  Only the 192-byte
\  ring descriptor array is statically ALLOTted in the dictionary.
\
\  The ring is indexed most-recent-first: slot 0 is the latest copy,
\  slot 1 is the copy before that, and so on.  When the ring is full,
\  the oldest entry is evicted and its XMEM block freed via
\  XMEM-FREE-BLOCK.
\
\  Clipboard content is untyped bytes — the caller decides semantics.
\  Zero-copy paste: CLIP-PASTE returns a direct XMEM pointer valid
\  until the next CLIP-COPY that evicts or overwrites that slot.
\
\  Ring entry layout (3 cells = 24 bytes per slot):
\    +0   addr     XMEM pointer to content (or 0 if empty)
\    +8   len      Current content length in bytes
\    +16  cap      Allocated capacity in bytes (XMEM block size)
\
\  Allocation strategy:
\    - New content that fits in the existing slot capacity is copied
\      in-place (no alloc/free).
\    - Growing a slot: XMEM-ALLOT new block, CMOVE, XMEM-FREE-BLOCK
\      old block.  No RESIZE in XMEM — this is the standard pattern
\      (cf. vault.f, surface.f).
\    - Capacities are rounded up to 64-byte boundaries (XMEM tile
\      alignment) with a 64-byte minimum, reducing churn.
\
\  Prefix: CLIP-  (public API)
\          _CLIP- (internal helpers)
\
\  Load with:   REQUIRE clipboard.f
\  Dependencies: XMEM-ALLOT, XMEM-FREE-BLOCK (KDOS §1.14)

PROVIDED akashic-clipboard

\ =====================================================================
\  1. Ring geometry
\ =====================================================================

8 CONSTANT CLIP-RING-SIZE              \ max entries in the ring

24 CONSTANT _CLIP-SLOT-SZ             \ bytes per ring slot (3 cells)

\ Ring storage: CLIP-RING-SIZE × 24 = 192 bytes (for default 8 slots)
CREATE _CLIP-RING  CLIP-RING-SIZE _CLIP-SLOT-SZ * ALLOT

VARIABLE _CLIP-HEAD                    \ physical index of most-recent entry
VARIABLE _CLIP-COUNT                   \ number of occupied entries

0 _CLIP-HEAD !
0 _CLIP-COUNT !

\ Zero the ring at load time
_CLIP-RING  CLIP-RING-SIZE _CLIP-SLOT-SZ *  0 FILL

\ =====================================================================
\  2. Internal helpers
\ =====================================================================

\ _CLIP-SLOT ( physical-idx -- slot-addr )
\   Address of ring slot at physical index.
: _CLIP-SLOT  ( idx -- addr )
    _CLIP-SLOT-SZ *  _CLIP-RING + ;

\ _CLIP-PHYS ( logical -- physical )
\   Convert a logical index (0 = most recent) to a physical ring
\   index, wrapping via modular arithmetic.
\   physical = (head - logical + RING-SIZE) mod RING-SIZE
: _CLIP-PHYS  ( logical -- physical )
    _CLIP-HEAD @ SWAP -  CLIP-RING-SIZE +
    CLIP-RING-SIZE MOD ;

\ _CLIP-ADVANCE-HEAD ( -- )
\   Move head forward by one, wrapping.
: _CLIP-ADVANCE-HEAD  ( -- )
    _CLIP-HEAD @ 1+  CLIP-RING-SIZE MOD  _CLIP-HEAD ! ;

\ _CLIP-REWIND-HEAD ( -- )
\   Move head backward by one, wrapping.  Used to undo an advance
\   when an operation fails after _CLIP-ADVANCE-HEAD.
: _CLIP-REWIND-HEAD  ( -- )
    _CLIP-HEAD @ 0= IF
        CLIP-RING-SIZE 1-
    ELSE
        _CLIP-HEAD @ 1-
    THEN
    _CLIP-HEAD ! ;

\ Slot field accessors — each returns the address of the field
\ within a slot, suitable for @ or !.

\ _CLIP-S-ADDR ( slot -- addr-field )   XMEM content pointer
: _CLIP-S-ADDR  ( slot -- a )  ;
\ _CLIP-S-LEN  ( slot -- len-field )    content length
: _CLIP-S-LEN   ( slot -- a )  8 + ;
\ _CLIP-S-CAP  ( slot -- cap-field )    allocated capacity
: _CLIP-S-CAP   ( slot -- a )  16 + ;

\ _CLIP-FREE-SLOT ( slot-addr -- )
\   Free the XMEM buffer in a slot (if any) and zero all fields.
: _CLIP-FREE-SLOT  ( slot -- )
    DUP @ ?DUP IF                      \ has a buffer?
        OVER 16 + @                    \ get capacity
        XMEM-FREE-BLOCK               \ free XMEM block (addr size --)
    THEN
    0 OVER !  0 OVER 8 + !  0 SWAP 16 + ! ;

\ _CLIP-MIN-CAP ( len -- cap )
\   Compute minimum allocation capacity.  Round up to the next
\   64-byte boundary (XMEM tile alignment).  Minimum 64.
: _CLIP-MIN-CAP  ( len -- cap )
    63 + -64 AND
    DUP 64 < IF DROP 64 THEN ;

\ =====================================================================
\  3. Public API — Core Operations
\ =====================================================================

\ CLIP-INIT ( -- )
\   Reset the clipboard to empty, freeing all XMEM slot buffers.
: CLIP-INIT  ( -- )
    CLIP-RING-SIZE 0 DO
        I _CLIP-SLOT _CLIP-FREE-SLOT
    LOOP
    0 _CLIP-HEAD !
    0 _CLIP-COUNT ! ;

\ CLIP-COUNT ( -- n )
\   Number of occupied ring entries.
: CLIP-COUNT  ( -- n )
    _CLIP-COUNT @ ;

\ CLIP-EMPTY? ( -- flag )
\   True if the ring has no entries.
: CLIP-EMPTY?  ( -- flag )
    CLIP-COUNT 0= ;

\ -----------------------------------------------------------------
\  CLIP-COPY — push a new entry onto the ring
\ -----------------------------------------------------------------

\ Scratch variables for CLIP-COPY (Core-0 single-threaded pattern)
VARIABLE _CLIP-SRC                     \ source address
VARIABLE _CLIP-LEN                     \ source length
VARIABLE _CLIP-TGT                     \ target slot address
VARIABLE _CLIP-NEWCAP                  \ desired XMEM capacity

\ _CLIP-ENSURE-BUF ( -- ior )
\   Ensure _CLIP-TGT slot has an XMEM buffer of at least
\   _CLIP-NEWCAP bytes.  Reuses existing buffer if large enough;
\   otherwise allocates a new XMEM block, frees the old one.
\   Returns 0 on success, -1 on XMEM allocation failure.
: _CLIP-ENSURE-BUF  ( -- ior )
    _CLIP-TGT @ @ 0<> IF
        \ Existing buffer — check capacity
        _CLIP-TGT @ _CLIP-S-CAP @  _CLIP-NEWCAP @  >= IF
            0 EXIT                         \ sufficient — reuse
        THEN
        \ Need to grow — alloc new XMEM block
        _CLIP-NEWCAP @ XMEM-ALLOT? IF
            DROP -1 EXIT                   \ XMEM full (drop dummy addr)
        THEN                               ( new-addr )
        \ Copy old content to new block (preserve during transition)
        _CLIP-TGT @ @ OVER                ( new old new )
        _CLIP-TGT @ _CLIP-S-LEN @         ( new old new old-len )
        CMOVE                              ( new )
        \ Free old XMEM block
        _CLIP-TGT @ @                     ( new old-addr )
        _CLIP-TGT @ _CLIP-S-CAP @         ( new old-addr old-cap )
        XMEM-FREE-BLOCK                   ( new )
        \ Update slot with new block
        _CLIP-TGT @ !
        _CLIP-NEWCAP @ _CLIP-TGT @ _CLIP-S-CAP !
        0 EXIT
    THEN
    \ No buffer — fresh XMEM-ALLOT
    _CLIP-NEWCAP @ XMEM-ALLOT? IF
        DROP -1 EXIT                       \ drop dummy addr
    THEN
    _CLIP-TGT @ !
    _CLIP-NEWCAP @ _CLIP-TGT @ _CLIP-S-CAP !
    0 ;

\ CLIP-COPY ( addr len -- ior )
\   Push a new entry onto the ring.  Copies len bytes from addr
\   into an XMEM-allocated buffer in the next ring slot.
\   If the ring is full, the oldest entry is evicted (XMEM freed).
\   If the target slot already has an XMEM buffer with sufficient
\   capacity, it is reused; otherwise a new block is allocated and
\   the old one freed.
\
\   Returns 0 on success, -1 on XMEM allocation failure.
\   Zero-length copies are allowed (stores an empty entry).
: CLIP-COPY  ( addr len -- ior )
    _CLIP-LEN !  _CLIP-SRC !

    \ Advance head to the next physical slot
    _CLIP-ADVANCE-HEAD
    _CLIP-HEAD @ _CLIP-SLOT  _CLIP-TGT !

    \ Zero-length copy: store empty entry, skip XMEM allocation.
    \ Safe to evict eagerly because zero-length never allocates.
    _CLIP-LEN @ 0= IF
        _CLIP-COUNT @ CLIP-RING-SIZE >= IF
            _CLIP-TGT @ _CLIP-FREE-SLOT
        ELSE
            1 _CLIP-COUNT +!
        THEN
        0 _CLIP-TGT @ !                   \ addr = 0
        0 _CLIP-TGT @ _CLIP-S-LEN !       \ len = 0
        0 _CLIP-TGT @ _CLIP-S-CAP !       \ cap = 0
        0 EXIT
    THEN

    \ Ensure the target slot has adequate XMEM buffer.
    \ When the ring is full the target slot holds the oldest entry's
    \ buffer.  _CLIP-ENSURE-BUF may reuse it (capacity sufficient) or
    \ grow it (allot new, cmove, free old).  If the allocation fails
    \ the old buffer is left intact — we rewind head and bail out,
    \ keeping the ring in its prior state.
    _CLIP-LEN @ _CLIP-MIN-CAP _CLIP-NEWCAP !
    _CLIP-ENSURE-BUF IF
        _CLIP-REWIND-HEAD                  \ undo the advance
        -1 EXIT                            \ XMEM allocation failed
    THEN

    \ Copy source data into the slot's XMEM buffer
    _CLIP-SRC @  _CLIP-TGT @ @  _CLIP-LEN @  CMOVE

    \ Store content length
    _CLIP-LEN @ _CLIP-TGT @ _CLIP-S-LEN !

    \ Adjust count: only increment when ring was not already full
    _CLIP-COUNT @ CLIP-RING-SIZE < IF 1 _CLIP-COUNT +! THEN
    0 ;

\ =====================================================================
\  4. Public API — Paste / Query
\ =====================================================================

\ CLIP-PASTE ( -- addr len )
\   Return the most recent clipboard entry (logical slot 0).
\   Returns 0 0 if the clipboard is empty.
\   The returned XMEM pointer is valid until the next CLIP-COPY
\   that evicts or overwrites that physical slot.
: CLIP-PASTE  ( -- addr len )
    CLIP-EMPTY? IF 0 0 EXIT THEN
    0 _CLIP-PHYS _CLIP-SLOT
    DUP @  SWAP _CLIP-S-LEN @ ;

\ CLIP-PASTE-N ( n -- addr len )
\   Return the Nth most recent entry (0 = most recent).
\   Returns 0 0 if n >= CLIP-COUNT.
: CLIP-PASTE-N  ( n -- addr len )
    DUP CLIP-COUNT >= IF DROP 0 0 EXIT THEN
    _CLIP-PHYS _CLIP-SLOT
    DUP @  SWAP _CLIP-S-LEN @ ;

\ CLIP-LEN ( -- n )
\   Length of the most recent entry in bytes.  0 if empty.
: CLIP-LEN  ( -- n )
    CLIP-EMPTY? IF 0 EXIT THEN
    0 _CLIP-PHYS _CLIP-SLOT _CLIP-S-LEN @ ;

\ CLIP-DROP ( -- )
\   Discard the most recent entry, freeing its XMEM buffer.
\   Rewinds the head pointer.  No-op if empty.
: CLIP-DROP  ( -- )
    CLIP-EMPTY? IF EXIT THEN
    _CLIP-HEAD @ _CLIP-SLOT _CLIP-FREE-SLOT
    _CLIP-REWIND-HEAD
    -1 _CLIP-COUNT +! ;

\ =====================================================================
\  5. Public API — Lifecycle
\ =====================================================================

\ CLIP-CLEAR ( -- )
\   Free all XMEM entries and reset the ring to empty.
: CLIP-CLEAR  ( -- )
    CLIP-INIT ;

\ CLIP-DESTROY ( -- )
\   Teardown — free all XMEM entries.  Call on application exit.
: CLIP-DESTROY  ( -- )
    CLIP-INIT ;

\ =====================================================================
\  6. Diagnostics
\ =====================================================================

\ .CLIP ( -- )
\   Print clipboard ring status to the console.
: .CLIP  ( -- )
    ." Clipboard: count=" CLIP-COUNT .
    ."  ring-size=" CLIP-RING-SIZE .
    ."  head=" _CLIP-HEAD @ . CR
    CLIP-COUNT 0 ?DO
        ."   [" I . ." ] "
        I _CLIP-PHYS _CLIP-SLOT
        ." addr=" DUP @ .
        ." len="  DUP _CLIP-S-LEN @ .
        ." cap="  _CLIP-S-CAP @ . CR
    LOOP ;
