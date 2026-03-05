\ conc-map.f — Concurrent Hash Map for KDOS / Megapad-64
\
\ Thread-safe hash map built on top of KDOS §19 hash tables and
\ rwlock.f.  Wraps an underlying HASHTABLE with a reader-writer
\ lock, providing concurrent read access and exclusive write access.
\
\ Design choices:
\   - One RW lock per map (coarse-grained).  This is simple and
\     correct.  Per-bucket locking would reduce contention on
\     multicore but adds complexity; the current approach is a
\     sound starting point.
\   - Reads (CMAP-GET, CMAP-COUNT) acquire READ-LOCK for
\     consistent snapshots while allowing concurrent readers.
\   - Writes (CMAP-PUT, CMAP-DEL) acquire WRITE-LOCK for
\     exclusive access.
\   - Iteration (CMAP-EACH) holds READ-LOCK for the entire scan,
\     providing snapshot semantics.
\
\ Key/value sizes are fixed at creation time (matching HASHTABLE).
\ Keys are byte arrays compared via SAMESTR?.  Values are byte
\ arrays copied via CMOVE.
\
\ Data structure — Concurrent Map:
\   +0   ht          Pointer to underlying HASHTABLE descriptor
\   +8   rwlock      Inline rwlock (88 bytes = 11 cells)
\
\ Total header: 1 + 11 = 12 cells = 96 bytes (plus the HASHTABLE
\ itself which is allocated separately via HASHTABLE defining word).
\
\ Dependencies:
\   - event.f  (via rwlock.f)
\   - rwlock.f (READ-LOCK, WRITE-LOCK, etc.)
\   - KDOS §19 (HASHTABLE, HT-PUT, HT-GET, HT-DEL, HT-EACH, HT-COUNT)
\
\ Prefix: CMAP-  (public API)
\         _CM-   (internal helpers)
\
\ Load with:   REQUIRE conc-map.f

REQUIRE ../concurrency/rwlock.f

PROVIDED akashic-conc-map

\ =====================================================================
\  Constants
\ =====================================================================

96 CONSTANT _CM-SIZE               \ bytes per cmap header (12 cells)

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _CM-HT    ( cm -- ht )    @ ;           \ +0  → hashtable
: _CM-RWL   ( cm -- rwl )   8 + ;         \ +8  inline rwlock

\ =====================================================================
\  CMAP — Define a Concurrent Map
\ =====================================================================

\ CMAP ( keysize valsize slots "name" -- )
\   Create a named concurrent hash map.  Allocates the underlying
\   HASHTABLE and wraps it with an inline rwlock.
\
\   keysize/valsize: bytes per key/value (same as HASHTABLE).
\   slots: number of hash table slots (prime recommended).
\
\   Example:   8 8 31 CMAP my-cache
\              \ 8-byte keys, 8-byte values, 31 slots

VARIABLE _CM-TMP-HT               \ temp: hashtable address

: CMAP  ( keysize valsize slots "name" -- )
    \ First create the hashtable (anonymous — we'll grab its address)
    \ HASHTABLE wants ( keysize valsize slots "name" -- )
    \ But we need an anonymous one.  We'll use HERE before HASHTABLE
    \ to capture the address, then build the CMAP wrapper manually.
    \
    \ Strategy: allocate the HT data inline first, then the CMAP
    \ header that points to it.
    \
    \ Actually, HASHTABLE parses a name and creates a CONSTANT.
    \ For CMAP we need it anonymous.  So we replicate the layout:

    \ Save params
    >R >R >R                           \ R: ( slots valsize keysize )
    HERE _CM-TMP-HT !                  \ HT starts here
    R> ,                               \ +0  keysize
    R> ,                               \ +8  valsize
    R@ ,                               \ +16 slots
    0 ,                                \ +24 count = 0
    HT-LOCK ,                          \ +32 lock#
    \ Allocate and zero-fill data area
    _CM-TMP-HT @ @ _CM-TMP-HT @ 8 + @ + 1+   \ stride = keysize+valsize+1
    R> *                               \ total bytes = stride × slots
    DUP ALLOT
    _CM-TMP-HT @ 40 + SWAP 0 FILL     \ zero the data area

    \ Now allocate the CMAP header
    HERE >R
    _CM-TMP-HT @ ,                     \ +0  ht pointer
    \ Inline rwlock (11 cells = 88 bytes)
    EVT-LOCK ,                         \ +8   lock# = spinlock 6
    0 ,                                \ +16  readers = 0
    0 ,                                \ +24  writer = 0
    \ read-event (4 cells)
    0 ,                                \ +32  flag
    0 ,                                \ +40  wait-count
    0 ,                                \ +48  waiter-0
    0 ,                                \ +56  waiter-1
    \ write-event (4 cells)
    0 ,                                \ +64  flag
    0 ,                                \ +72  wait-count
    0 ,                                \ +80  waiter-0
    0 ,                                \ +88  waiter-1
    R> CONSTANT ;

\ =====================================================================
\  CMAP-PUT — Thread-Safe Insert/Update
\ =====================================================================

\ CMAP-PUT ( key-addr val-addr cm -- )
\   Insert or update a key-value pair under WRITE-LOCK.
\
\   key-addr: pointer to key bytes (keysize bytes)
\   val-addr: pointer to value bytes (valsize bytes)
\
\   Example:
\     CREATE _K 8 ALLOT 42 _K !
\     CREATE _V 8 ALLOT 99 _V !
\     _K _V my-cache CMAP-PUT

: CMAP-PUT  ( key-addr val-addr cm -- )
    DUP _CM-RWL WRITE-LOCK
    DUP >R _CM-HT HT-PUT
    R> _CM-RWL WRITE-UNLOCK ;

\ =====================================================================
\  CMAP-GET — Read with Shared Lock
\ =====================================================================

\ CMAP-GET ( key-addr cm -- val-addr | 0 )
\   Look up a key under READ-LOCK.  Returns pointer to the value
\   within the hash table, or 0 if not found.
\
\   The returned pointer is valid as long as no CMAP-DEL removes
\   the entry.  For safety, copy the value immediately after
\   CMAP-GET returns and before releasing any locks.

: CMAP-GET  ( key-addr cm -- val-addr | 0 )
    DUP _CM-RWL READ-LOCK
    DUP >R _CM-HT HT-GET
    R> _CM-RWL READ-UNLOCK ;

\ =====================================================================
\  CMAP-DEL — Thread-Safe Delete
\ =====================================================================

\ CMAP-DEL ( key-addr cm -- flag )
\   Delete a key under WRITE-LOCK.  Returns -1 if found and
\   deleted, 0 if absent.

: CMAP-DEL  ( key-addr cm -- flag )
    DUP _CM-RWL WRITE-LOCK
    DUP >R _CM-HT HT-DEL
    R> _CM-RWL WRITE-UNLOCK ;

\ =====================================================================
\  CMAP-COUNT — Entry Count
\ =====================================================================

\ CMAP-COUNT ( cm -- n )
\   Number of occupied entries in the map.  Read-locked.

: CMAP-COUNT  ( cm -- n )
    DUP _CM-RWL READ-LOCK
    DUP >R _CM-HT HT-COUNT
    R> _CM-RWL READ-UNLOCK ;

\ =====================================================================
\  CMAP-EACH — Iterate Entries
\ =====================================================================

\ CMAP-EACH ( xt cm -- )
\   Iterate all occupied entries under READ-LOCK (snapshot semantics).
\   The xt is called with ( key-addr val-addr -- ) for each entry.
\
\   Example:
\     : show-entry  ( key val -- )  SWAP @ . @ . CR ;
\     ['] show-entry my-cache CMAP-EACH

: CMAP-EACH  ( xt cm -- )
    DUP _CM-RWL READ-LOCK
    DUP >R _CM-HT HT-EACH
    R> _CM-RWL READ-UNLOCK ;

\ =====================================================================
\  CMAP-CLEAR — Remove All Entries
\ =====================================================================

\ CMAP-CLEAR ( cm -- )
\   Zero-fill all hash table data under WRITE-LOCK.
\   Resets count to 0.  All entries become empty.

VARIABLE _CM-CLR-HT
VARIABLE _CM-CLR-CM

: CMAP-CLEAR  ( cm -- )
    DUP _CM-CLR-CM !  DUP _CM-RWL WRITE-LOCK
    _CM-HT _CM-CLR-HT !
    \ Zero data area
    _CM-CLR-HT @ 40 +                     \ data start
    _CM-CLR-HT @ HT.STRIDE
    _CM-CLR-HT @ HT.SLOTS *               \ total bytes
    0 FILL
    \ Reset count
    0 _CM-CLR-HT @ 24 + !
    _CM-CLR-CM @ _CM-RWL WRITE-UNLOCK ;

\ =====================================================================
\  CMAP-INFO — Debug Display
\ =====================================================================

\ CMAP-INFO ( cm -- )
\   Print concurrent map status for debugging.

: CMAP-INFO  ( cm -- )
    ." [cmap"
    ."  count=" DUP CMAP-COUNT .
    ."  slots=" DUP _CM-HT HT.SLOTS .
    ."  ksize=" DUP _CM-HT HT.KSIZE .
    ."  vsize=" DUP _CM-HT HT.VSIZE .
    ."  rw:" DUP _CM-RWL RW-INFO
    ." ]" CR
    DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  CMAP          ( ksize vsize slots "name" -- )  Create concurrent map
\  CMAP-PUT      ( key-addr val-addr cm -- )      Thread-safe insert/update
\  CMAP-GET      ( key-addr cm -- val-addr | 0 )  Read-locked lookup
\  CMAP-DEL      ( key-addr cm -- flag )          Thread-safe delete
\  CMAP-COUNT    ( cm -- n )                      Entry count
\  CMAP-EACH     ( xt cm -- )                     Iterate (snapshot)
\  CMAP-CLEAR    ( cm -- )                        Remove all entries
\  CMAP-INFO     ( cm -- )                        Debug display
