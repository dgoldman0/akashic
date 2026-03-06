\ channel.f — Go-Style Bounded Channels for KDOS / Megapad-64
\
\ CSP-style bounded channels for inter-task communication.
\ A channel embeds an inline circular buffer + two events
\ (not-full, not-empty).  Sending blocks if full; receiving
\ blocks if empty.
\
\ Custom inline ring operations (direct ! / @ / CMOVE) avoid the
\ double-locking and global-variable issues of RING-PUSH/RING-POP.
\ Each channel has its own spinlock number (like rwlock.f) to
\ reduce contention across unrelated channels.
\
\ Two API flavors:
\   CHAN-SEND / CHAN-RECV        — 1-cell (64-bit) values
\   CHAN-SEND-BUF / CHAN-RECV-BUF — arbitrary elem-size (addr-based)
\
\ CHAN-SELECT polls N channels and returns the first one with data.
\
\ Data structure — 15 cells = 120 bytes (fixed) + data area:
\   +0    lock#       per-channel spinlock number
\   +8    closed      0 | -1
\   +16   elem-size   bytes per element
\   +24   capacity    max number of elements
\   +32   head        read index  (oldest element)
\   +40   tail        write index (next write position)
\   +48   count       current number of elements
\   +56   evt-nf      not-full event  (4 cells = 32 bytes)
\   +88   evt-ne      not-empty event (4 cells = 32 bytes)
\   +120  data...     capacity × elem-size bytes
\
\ Closed-channel semantics:
\   CHAN-SEND on closed channel:     -1 THROW
\   CHAN-RECV on closed + empty:     returns 0
\   CHAN-TRY-RECV on closed + empty: returns ( 0 0 )
\   CHAN-SELECT when all closed + empty: returns ( -1 0 )
\
\ REQUIRE event.f
\
\ Prefix: CHAN-  (public API)
\         _CHAN- (internal helpers)
\
\ Load with:   REQUIRE channel.f

REQUIRE ../concurrency/event.f

PROVIDED akashic-channel

\ =====================================================================
\  Constants
\ =====================================================================

15 CONSTANT _CHAN-FIXED-CELLS      \ fixed cells per descriptor
120 CONSTANT _CHAN-FIXED-SIZE      \ fixed bytes (15 × 8)

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _CHAN-LOCK#   ( ch -- addr )   ;           \ +0   spinlock number
: _CHAN-CLOSED  ( ch -- addr )   8 + ;       \ +8   closed flag
: _CHAN-ESIZE   ( ch -- addr )   16 + ;      \ +16  elem-size (bytes)
: _CHAN-CAP     ( ch -- addr )   24 + ;      \ +24  capacity
: _CHAN-HEAD    ( ch -- addr )   32 + ;      \ +32  head (read index)
: _CHAN-TAIL    ( ch -- addr )   40 + ;      \ +40  tail (write index)
: _CHAN-CNT     ( ch -- addr )   48 + ;      \ +48  count
: _CHAN-EVT-NF  ( ch -- ev )     56 + ;      \ +56  not-full event
: _CHAN-EVT-NE  ( ch -- ev )     88 + ;      \ +88  not-empty event
: _CHAN-DATA    ( ch -- addr )   120 + ;     \ +120 data area

\ =====================================================================
\  CHANNEL — Defining Word
\ =====================================================================

\ CHANNEL ( lock# elem-size capacity "name" -- )
\   Create a named bounded channel.
\
\   lock# is a hardware spinlock number (0–7).  EVT-LOCK (6) is a
\   reasonable default; multiple channels can share the same spinlock.
\
\   elem-size is the size of each element in bytes.  Typically 8
\   (= 1 CELLS) for single-cell values.
\
\   capacity is the maximum number of buffered items.
\
\   Example:   6 1 CELLS 8 CHANNEL work-queue
\              6 1 CELLS 4 CHANNEL results

: CHANNEL  ( lock# elem-size capacity "name" -- )
    HERE >R
    ROT ,              \ +0   lock#
    0 ,                \ +8   closed = 0 (open)
    SWAP ,             \ +16  elem-size
    DUP ,              \ +24  capacity (keep on stack for ALLOT)
    0 ,                \ +32  head = 0
    0 ,                \ +40  tail = 0
    0 ,                \ +48  count = 0
    \ evt-not-full: initially SET (buffer is not full at creation)
    -1 ,               \ +56  flag = SET
    0 ,                \ +64  wait-count = 0
    0 ,                \ +72  waiter-0 = none
    0 ,                \ +80  waiter-1 = none
    \ evt-not-empty: initially UNSET (buffer is empty at creation)
    0 ,                \ +88  flag = UNSET
    0 ,                \ +96  wait-count = 0
    0 ,                \ +104 waiter-0 = none
    0 ,                \ +112 waiter-1 = none
    \ Data area: capacity × elem-size bytes
    R@ _CHAN-ESIZE @ * \ capacity × elem-size
    ALLOT
    R> CONSTANT ;

\ =====================================================================
\  Query
\ =====================================================================

\ CHAN-CLOSED? ( chan -- flag )
\   TRUE (-1) if the channel has been closed.

: CHAN-CLOSED?  ( ch -- flag )
    _CHAN-CLOSED @ 0<> ;

\ CHAN-COUNT ( chan -- n )
\   Number of items currently buffered.  Lock-free read.

: CHAN-COUNT  ( ch -- n )
    _CHAN-CNT @ ;

\ =====================================================================
\  Internal — Condition Checks
\ =====================================================================

\ _CHAN-FULL? ( ch -- flag )
\   TRUE if count >= capacity.

: _CHAN-FULL?  ( ch -- flag )
    DUP _CHAN-CNT @ SWAP _CHAN-CAP @ >= ;

\ _CHAN-EMPTY? ( ch -- flag )
\   TRUE if count == 0.

: _CHAN-EMPTY?  ( ch -- flag )
    _CHAN-CNT @ 0= ;

\ =====================================================================
\  Internal — Inline Ring Push/Pop (1-cell values)
\ =====================================================================
\
\ These operate UNDER the caller's channel lock.
\ No RING-PUSH/RING-POP, no global variables, no double-locking.

\ _CHAN-PUSH-CELL ( val ch -- )
\   Store a single-cell value at data[tail], advance tail, count++.
\   Caller MUST hold the channel lock.

: _CHAN-PUSH-CELL  ( val ch -- )
    >R
    R@ _CHAN-TAIL @  R@ _CHAN-ESIZE @  *  R@ _CHAN-DATA +  !
    R@ _CHAN-TAIL @  1+  R@ _CHAN-CAP @  MOD  R@ _CHAN-TAIL !
    1 R> _CHAN-CNT +! ;

\ _CHAN-POP-CELL ( ch -- val )
\   Fetch a single-cell value from data[head], advance head, count--.
\   Caller MUST hold the channel lock.

: _CHAN-POP-CELL  ( ch -- val )
    >R
    R@ _CHAN-HEAD @  R@ _CHAN-ESIZE @  *  R@ _CHAN-DATA +  @
    R@ _CHAN-HEAD @  1+  R@ _CHAN-CAP @  MOD  R@ _CHAN-HEAD !
    -1 R> _CHAN-CNT +! ;

\ =====================================================================
\  Internal — Inline Ring Push/Pop (addr-based, arbitrary elem-size)
\ =====================================================================

\ _CHAN-PUSH-BUF ( addr ch -- )
\   CMOVE elem-size bytes from addr into data[tail].
\   Caller MUST hold the channel lock.

: _CHAN-PUSH-BUF  ( addr ch -- )
    >R
    \ src = addr (on stack)
    R@ _CHAN-TAIL @  R@ _CHAN-ESIZE @  *  R@ _CHAN-DATA +  \ dst
    R@ _CHAN-ESIZE @                                        \ count
    CMOVE
    R@ _CHAN-TAIL @  1+  R@ _CHAN-CAP @  MOD  R@ _CHAN-TAIL !
    1 R> _CHAN-CNT +! ;

\ _CHAN-POP-BUF ( addr ch -- )
\   CMOVE elem-size bytes from data[head] into addr.
\   Caller MUST hold the channel lock.

: _CHAN-POP-BUF  ( addr ch -- )
    >R
    R@ _CHAN-HEAD @  R@ _CHAN-ESIZE @  *  R@ _CHAN-DATA +  \ src
    SWAP                                                    \ ( src addr )
    R@ _CHAN-ESIZE @                                        \ count
    CMOVE
    R@ _CHAN-HEAD @  1+  R@ _CHAN-CAP @  MOD  R@ _CHAN-HEAD !
    -1 R> _CHAN-CNT +! ;

\ =====================================================================
\  Internal — Lock Helpers
\ =====================================================================

: _CHAN-LOCK    ( ch -- )   _CHAN-LOCK# @ LOCK ;
: _CHAN-UNLOCK  ( ch -- )   _CHAN-LOCK# @ UNLOCK ;

\ =====================================================================
\  CHAN-SEND — Blocking 1-Cell Send
\ =====================================================================

\ CHAN-SEND ( val ch -- )
\   Send a single-cell value into the channel.
\   Blocks if the buffer is full (spins with YIELD?).
\   THROWs -1 if the channel is closed.

: CHAN-SEND  ( val ch -- )
    DUP CHAN-CLOSED? IF  2DROP -1 THROW  THEN
    BEGIN
        DUP _CHAN-LOCK
        DUP _CHAN-FULL? 0= IF           \ room available (under lock)
            SWAP OVER _CHAN-PUSH-CELL    \ push val
            DUP _CHAN-UNLOCK
            _CHAN-EVT-NE EVT-SET         \ wake receivers
            EXIT
        THEN
        DUP _CHAN-UNLOCK
        \ Re-check closed (may have been closed while waiting)
        DUP CHAN-CLOSED? IF  2DROP -1 THROW  THEN
        DUP _CHAN-EVT-NF EVT-WAIT        \ wait for room
        DUP _CHAN-EVT-NF EVT-RESET       \ clear for next cycle
    AGAIN ;

\ =====================================================================
\  CHAN-RECV — Blocking 1-Cell Receive
\ =====================================================================

\ CHAN-RECV ( ch -- val )
\   Receive a single-cell value from the channel.
\   Blocks if the buffer is empty (spins with YIELD?).
\   Returns 0 if the channel is closed and empty.

: CHAN-RECV  ( ch -- val )
    BEGIN
        DUP _CHAN-LOCK
        DUP _CHAN-EMPTY? 0= IF           \ data available (under lock)
            DUP _CHAN-POP-CELL            \ ( ch val )
            SWAP DUP _CHAN-UNLOCK
            _CHAN-EVT-NF EVT-SET          \ wake senders
            EXIT                          \ ( val )
        THEN
        DUP _CHAN-UNLOCK
        DUP CHAN-CLOSED? IF  DROP 0 EXIT  THEN   \ closed + empty
        DUP _CHAN-EVT-NE EVT-WAIT         \ wait for data
        DUP _CHAN-EVT-NE EVT-RESET        \ clear for next cycle
    AGAIN ;

\ =====================================================================
\  CHAN-TRY-SEND — Non-Blocking 1-Cell Send
\ =====================================================================

\ CHAN-TRY-SEND ( val ch -- flag )
\   Try to send without blocking.
\   Returns TRUE (-1) if sent, FALSE (0) if full or closed.

: CHAN-TRY-SEND  ( val ch -- flag )
    DUP CHAN-CLOSED? IF  2DROP 0 EXIT  THEN
    DUP _CHAN-LOCK
    DUP _CHAN-FULL? IF
        DUP _CHAN-UNLOCK
        2DROP 0                          \ full → false
    ELSE
        SWAP OVER _CHAN-PUSH-CELL
        DUP _CHAN-UNLOCK
        _CHAN-EVT-NE EVT-SET
        -1                               \ success → true
    THEN ;

\ =====================================================================
\  CHAN-TRY-RECV — Non-Blocking 1-Cell Receive
\ =====================================================================

\ CHAN-TRY-RECV ( ch -- val flag )
\   Try to receive without blocking.
\   Returns ( val TRUE ) on success, ( 0 0 ) if empty.

: CHAN-TRY-RECV  ( ch -- val flag )
    DUP _CHAN-LOCK
    DUP _CHAN-EMPTY? 0= IF
        DUP _CHAN-POP-CELL               \ ( ch val )
        SWAP DUP _CHAN-UNLOCK
        _CHAN-EVT-NF EVT-SET
        -1                               \ ( val true )
    ELSE
        DUP _CHAN-UNLOCK
        DROP 0 0                         \ ( 0 0 )
    THEN ;

\ =====================================================================
\  CHAN-SEND-BUF — Blocking Addr-Based Send
\ =====================================================================

\ CHAN-SEND-BUF ( addr ch -- )
\   Send elem-size bytes from addr into the channel.
\   Blocks if the buffer is full.  THROWs -1 if closed.

: CHAN-SEND-BUF  ( addr ch -- )
    DUP CHAN-CLOSED? IF  2DROP -1 THROW  THEN
    BEGIN
        DUP _CHAN-LOCK
        DUP _CHAN-FULL? 0= IF
            SWAP OVER _CHAN-PUSH-BUF
            DUP _CHAN-UNLOCK
            _CHAN-EVT-NE EVT-SET  EXIT
        THEN
        DUP _CHAN-UNLOCK
        DUP CHAN-CLOSED? IF  2DROP -1 THROW  THEN
        DUP _CHAN-EVT-NF EVT-WAIT
        DUP _CHAN-EVT-NF EVT-RESET
    AGAIN ;

\ =====================================================================
\  CHAN-RECV-BUF — Blocking Addr-Based Receive
\ =====================================================================

\ CHAN-RECV-BUF ( addr ch -- flag )
\   Receive elem-size bytes into addr from the channel.
\   Blocks if the buffer is empty.
\   Returns TRUE (-1) if data was received.
\   Returns FALSE (0) if the channel is closed and empty
\   (addr buffer is left untouched in that case).

: CHAN-RECV-BUF  ( addr ch -- flag )
    BEGIN
        DUP _CHAN-LOCK
        DUP _CHAN-EMPTY? 0= IF
            2DUP _CHAN-POP-BUF            \ copy to addr (under lock)
            DUP _CHAN-UNLOCK
            NIP _CHAN-EVT-NF EVT-SET
            -1 EXIT                       \ success
        THEN
        DUP _CHAN-UNLOCK
        DUP CHAN-CLOSED? IF  2DROP 0 EXIT  THEN   \ closed + empty
        DUP _CHAN-EVT-NE EVT-WAIT
        DUP _CHAN-EVT-NE EVT-RESET
    AGAIN ;

\ =====================================================================
\  CHAN-CLOSE — Close the Channel
\ =====================================================================

\ CHAN-CLOSE ( ch -- )
\   Mark the channel as closed.  Wake all blocked senders and
\   receivers so they can see the new state and exit.
\   Items already in the buffer can still be received.

: CHAN-CLOSE  ( ch -- )
    DUP _CHAN-LOCK
    -1 OVER _CHAN-CLOSED !
    DUP _CHAN-UNLOCK
    \ Wake everyone so blocked senders/receivers notice the close
    DUP _CHAN-EVT-NF EVT-SET
    _CHAN-EVT-NE EVT-SET ;

\ =====================================================================
\  CHAN-SELECT — Wait on Multiple Channels
\ =====================================================================

\ CHAN-SELECT ( chan1 chan2 ... chanN n -- idx val )
\   Poll N channels in round-robin order.  Returns the index
\   (0-based, matching push order) and value from the first
\   channel that has data available.
\
\   Returns ( -1 0 ) if ALL channels are closed and empty.
\
\   Uses CHAN-TRY-RECV internally; only works with 1-cell channels.
\   YIELD? is called between polling rounds for cooperative scheduling.
\
\   Example:   ch-a ch-b ch-c 3 CHAN-SELECT  ( -- idx val )

\ _SEL-VAL, _SEL-IDX, _SEL-DEAD removed — all state now lives on
\ the data stack inside CHAN-SELECT to avoid shared-state corruption
\ when multiple tasks call CHAN-SELECT concurrently.  (Tier 0c fix)

: _CHAN-SEL-DROP  ( chan1 ... chanN n -- )
    0 DO DROP LOOP ;

: CHAN-SELECT  ( chan1 chan2 ... chanN n -- idx val )
    BEGIN
        0                             \ dead-count on TOS ( chans n dead )
        OVER 0 DO
            \ Access chan[I]: channels sit deeper in the stack.
            \ Stack below dead: chan1..chanN n
            \ We need chan[I] — that's at position (n - I) + 1
            \ counting from 'n', but 'dead' is above 'n', so +2.
            OVER I - 1+ PICK          \ copy chan[I] to TOS ( chans n dead ch )

            \ Track closed+empty channels
            DUP CHAN-CLOSED? IF
                DUP _CHAN-EMPTY? IF
                    SWAP 1+ SWAP      \ dead++ ( chans n dead' ch )
                THEN
            THEN

            CHAN-TRY-RECV             \ ( chans n dead val flag )
            IF                        \ got data!
                \ Stack: chan1..chanN n dead val
                I >R                  \ save index  R: (..DO.. idx)
                >R                    \ save val    R: (..DO.. idx val)
                DROP                  \ drop dead   ( chans n )
                _CHAN-SEL-DROP        \ drop all N channels ( )
                R> R>                 \ ( val idx )
                SWAP                  \ ( idx val )
                UNLOOP EXIT
            ELSE
                DROP                  \ drop 0 from failed try
            THEN
        LOOP

        \ All channels checked, none ready.
        \ If every channel is closed+empty, return ( -1 0 ).
        \ Stack: chan1..chanN n dead
        OVER = IF                     \ dead = n?
            _CHAN-SEL-DROP
            -1 0 EXIT
        THEN

        YIELD?
    AGAIN ;

\ =====================================================================
\  CHAN-INFO — Debug Display
\ =====================================================================

\ CHAN-INFO ( ch -- )
\   Print channel status for debugging.

: CHAN-INFO  ( ch -- )
    ." [channel"
    ."  lock#=" DUP _CHAN-LOCK# @ .
    DUP CHAN-CLOSED? IF  ."  CLOSED"  ELSE  ."  open"  THEN
    ."  esize=" DUP _CHAN-ESIZE @ .
    ."  cap=" DUP _CHAN-CAP @ .
    ."  count=" DUP _CHAN-CNT @ .
    ."  head=" DUP _CHAN-HEAD @ .
    ."  tail=" DUP _CHAN-TAIL @ .
    CR ."   nf:" DUP _CHAN-EVT-NF EVT-INFO
    ."   ne:" DUP _CHAN-EVT-NE EVT-INFO
    ." ]" CR
    DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  CHANNEL       ( lock# esize cap "name" -- )  Create bounded channel
\  CHAN-SEND      ( val ch -- )                  Send 1-cell; block if full
\  CHAN-RECV      ( ch -- val )                  Recv 1-cell; block if empty
\  CHAN-TRY-SEND  ( val ch -- flag )             Non-blocking 1-cell send
\  CHAN-TRY-RECV  ( ch -- val flag )             Non-blocking 1-cell recv
\  CHAN-SEND-BUF  ( addr ch -- )                 Send elem-size bytes
\  CHAN-RECV-BUF  ( addr ch -- flag )            Recv elem-size bytes
\  CHAN-CLOSE     ( ch -- )                      Close channel
\  CHAN-CLOSED?   ( ch -- flag )                 Is closed?
\  CHAN-COUNT     ( ch -- n )                    Items buffered
\  CHAN-SELECT    ( ch1..chN n -- idx val )      Wait on N channels
\  CHAN-INFO      ( ch -- )                      Debug display
