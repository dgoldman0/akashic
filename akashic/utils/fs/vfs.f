\ vfs.f — Abstract VFS data structure for KDOS Forth
\
\ Arena-backed virtual filesystem.  Each VFS instance lives in a
\ single KDOS arena, enabling multiple simultaneous filesystems
\ and O(1) bulk teardown via ARENA-DESTROY.
\
\ The VFS is a pure in-memory tree of typed inodes with a file-
\ descriptor pool, string pool, and path resolver.  It knows
\ nothing about sectors, DMA, MMIO, or any on-disk format.
\ Actual byte transfer is delegated to a binding — a separate
\ module that connects a VFS instance to a backing store.
\
\ Without a binding the VFS is a ramdisk: create files, write
\ bytes, read them back, list directories — all in memory.
\
\ Prefix: VFS-   (public API)
\         _VFS-  (internal helpers)
\
\ Load with:   REQUIRE utils/fs/vfs.f

PROVIDED akashic-vfs
REQUIRE ../../text/utf8.f

\ =====================================================================
\  Constants — Type Tags
\ =====================================================================

1 CONSTANT VFS-T-FILE
2 CONSTANT VFS-T-DIR
3 CONSTANT VFS-T-SYMLINK
4 CONSTANT VFS-T-SPECIAL

\ Inode flags (bit masks)
1 CONSTANT VFS-IF-DIRTY        \ inode has unsync'd mutations
2 CONSTANT VFS-IF-CHILDREN     \ children have been loaded
4 CONSTANT VFS-IF-PINNED       \ not eligible for eviction
8 CONSTANT VFS-IF-EVICTABLE    \ explicitly marked evictable

\ FD flags (bit masks)
1 CONSTANT VFS-FF-READ
2 CONSTANT VFS-FF-WRITE
4 CONSTANT VFS-FF-APPEND

\ VFS instance flags (bit masks)
1 CONSTANT VFS-F-RO            \ read-only
2 CONSTANT VFS-F-DIRTY         \ has unsync'd state
4 CONSTANT VFS-F-MOUNTED       \ registered in mount table

\ =====================================================================
\  Sizes
\ =====================================================================

112 CONSTANT VFS-INODE-SIZE    \ 14 cells per inode
 48 CONSTANT VFS-FD-SIZE       \  6 cells per file descriptor

\ Vtable: 10 execution tokens = 10 cells = 80 bytes
80  CONSTANT VFS-VT-SIZE

\ Default pool sizes
256 CONSTANT _VFS-FD-DEFAULT   \ default FD pool slots

\ Slab page: 1 cell header + N inode slots
\ Header cell = pointer to next slab page (0 = last page)
\ We size each slab page to hold 64 inodes + header:
\   8 + (64 × 112) = 7176 bytes
64  CONSTANT _VFS-SLAB-SLOTS
8 64 VFS-INODE-SIZE * + CONSTANT _VFS-SLAB-SIZE

\ =====================================================================
\  Vtable Slot Indices
\ =====================================================================

 0 CONSTANT VFS-VT-PROBE      \ ( sector-0-buf vfs -- flag )
 1 CONSTANT VFS-VT-INIT       \ ( vfs -- ior )
 2 CONSTANT VFS-VT-TEARDOWN   \ ( vfs -- )
 3 CONSTANT VFS-VT-READ       \ ( buf len offset inode vfs -- actual )
 4 CONSTANT VFS-VT-WRITE      \ ( buf len offset inode vfs -- actual )
 5 CONSTANT VFS-VT-READDIR    \ ( inode vfs -- )
 6 CONSTANT VFS-VT-SYNC       \ ( inode vfs -- ior )
 7 CONSTANT VFS-VT-CREATE     \ ( inode vfs -- ior )
 8 CONSTANT VFS-VT-DELETE     \ ( inode vfs -- ior )
 9 CONSTANT VFS-VT-TRUNCATE   \ ( inode vfs -- ior )

\ =====================================================================
\  VFS Descriptor Layout (16 cells = 128 bytes)
\ =====================================================================
\
\    +0   vtable        address of 10-xt binding dispatch table
\    +8   flags         VFS-F-RO, VFS-F-DIRTY, …
\   +16   inode-slab    first slab page address
\   +24   inode-free    free-list head across slab pages
\   +32   inode-count   live (allocated) inodes
\   +40   inode-hwm     high-water mark for eviction
\   +48   fd-pool       FD slot array base
\   +56   fd-free       FD free-list head
\   +64   fd-max        number of FD slots
\   +72   root-inode    root directory inode
\   +80   cwd-inode     current working directory inode
\   +88   str-base      string pool base
\   +96   str-ptr       next free byte in string pool
\  +104   str-end       string pool limit
\  +112   binding-ctx   opaque pointer for binding's private state
\  +120   arena         back-pointer to owning arena
\  = 128 bytes (16 cells)

128 CONSTANT VFS-DESC-SIZE     \ 16 cells

: V.VTABLE     ;              \ +0
: V.FLAGS      8 + ;          \ +8
: V.ISLAB      16 + ;         \ +16
: V.IFREE      24 + ;         \ +24
: V.ICOUNT     32 + ;         \ +32
: V.IHWM       40 + ;         \ +40
: V.FDPOOL     48 + ;         \ +48
: V.FDFREE     56 + ;         \ +56
: V.FDMAX      64 + ;         \ +64
: V.ROOT       72 + ;         \ +72
: V.CWD        80 + ;         \ +80
: V.STR-BASE   88 + ;         \ +88
: V.STR-PTR    96 + ;         \ +96
: V.STR-END    104 + ;        \ +104
: V.BCTX       112 + ;        \ +112
: V.ARENA      120 + ;        \ +120

\ =====================================================================
\  Inode Record Layout (14 cells = 112 bytes)
\ =====================================================================
\
\    +0   first-child / next-free   (union)
\    +8   type          VFS-T-FILE, VFS-T-DIR, …
\   +16   size-lo       file size low cell
\   +24   size-hi       file size high cell
\   +32   mode          permission / attribute bits
\   +40   mtime         modification timestamp
\   +48   ctime         creation / change timestamp
\   +56   parent        inode pointer
\   +64   next-sibling  inode pointer (child list is singly-linked)
\   +72   name-handle   string pool handle
\   +80   binding-id    stable on-disk identity (opaque to VFS)
\   +88   bdata-0       binding-private cell 0
\   +96   bdata-1       binding-private cell 1
\  +104   flags         VFS-IF-DIRTY, VFS-IF-CHILDREN, …

: IN.CHILD      ;             \ +0   first-child (or next-free in free-list)
: IN.TYPE       8 + ;         \ +8
: IN.SIZE-LO    16 + ;        \ +16
: IN.SIZE-HI    24 + ;        \ +24
: IN.MODE       32 + ;        \ +32
: IN.MTIME      40 + ;        \ +40
: IN.CTIME      48 + ;        \ +48
: IN.PARENT     56 + ;        \ +56
: IN.SIBLING    64 + ;        \ +64
: IN.NAME       72 + ;        \ +72
: IN.BID        80 + ;        \ +80
: IN.BDATA      88 + ;        \ +88   (2 cells: +88, +96)
: IN.FLAGS      104 + ;       \ +104

\ =====================================================================
\  File Descriptor Layout (6 cells = 48 bytes)
\ =====================================================================
\
\    +0   inode         pointer to referenced inode
\    +8   cursor-lo     byte offset low cell
\   +16   cursor-hi     byte offset high cell
\   +24   flags         VFS-FF-READ, VFS-FF-WRITE, …
\   +32   vfs           back-pointer to owning VFS instance
\   +40   next-free     free-list chain (when not in use)

: FD.INODE     ;              \ +0
: FD.CUR-LO    8 + ;          \ +8
: FD.CUR-HI    16 + ;         \ +16
: FD.FLAGS     24 + ;         \ +24
: FD.VFS       32 + ;         \ +32
: FD.FREE      40 + ;         \ +40

\ =====================================================================
\  Current VFS Context
\ =====================================================================

VARIABLE _VFS-CUR    \ current VFS instance handle

: VFS-USE   ( vfs -- )  _VFS-CUR ! ;
: VFS-CUR   ( -- vfs )  _VFS-CUR @ ;

\ =====================================================================
\  Vtable Dispatch Helper
\ =====================================================================

\ _VFS-XT ( slot# vfs -- xt )
\   Fetch execution token from the VFS's vtable at the given slot.
: _VFS-XT  ( slot vfs -- xt )
    V.VTABLE @       \ vtable base
    SWAP CELLS +     \ offset to slot
    @ ;              \ fetch xt

\ =====================================================================
\  Read-Only Stub (for read-only bindings)
\ =====================================================================

: _VFS-RO-STUB  ( ... -- -1 )
    ." read-only filesystem" CR  -1 ;

\ =====================================================================
\  String Pool
\ =====================================================================
\
\  String entry layout:
\    +0   len       (1 cell)
\    +8   refcount  (1 cell)
\   +16   bytes     (ALIGN8(len) payload)
\
\  Handle = address of entry.  Handle 0 = null sentinel.

VARIABLE _VSA-SRC
VARIABLE _VSA-LEN
VARIABLE _VSA-ESZ

: _VFS-STR-ALLOC  ( src-a src-u vfs -- handle )
    >R  _VSA-LEN !  _VSA-SRC !
    \ Entry size = 16 + ALIGN8(len)
    _VSA-LEN @ 7 + -8 AND 16 +  _VSA-ESZ !
    \ Check space
    R@ V.STR-PTR @  _VSA-ESZ @ +
    R@ V.STR-END @  > IF
        R> DROP  0 EXIT         \ out of string space
    THEN
    \ Handle = current str-ptr
    R@ V.STR-PTR @
    \ Write header
    _VSA-LEN @ OVER !           \ len at +0
    1 OVER 8 + !                \ refcount = 1 at +8
    \ Copy string bytes
    _VSA-LEN @ 0> IF
        _VSA-SRC @  OVER 16 +  _VSA-LEN @  CMOVE
    THEN
    \ Advance str-ptr
    R@ V.STR-PTR @  _VSA-ESZ @ +
    R> V.STR-PTR ! ;

: _VFS-STR-GET  ( handle -- addr len )
    DUP 0= IF  0 EXIT  THEN
    DUP 16 + SWAP @ ;

: _VFS-STR-REF  ( handle -- )
    DUP 0= IF  DROP EXIT  THEN
    DUP 8 + @ 1+  SWAP 8 + ! ;

: _VFS-STR-RELEASE  ( handle -- )
    DUP 0= IF  DROP EXIT  THEN
    DUP 8 + @ 1-  SWAP 8 + ! ;

: _VFS-STR-MATCH?  ( c-addr u handle -- flag )
    DUP 0= IF  DROP 2DROP FALSE EXIT  THEN
    _VFS-STR-GET             ( c-addr u addr2 len2 )
    ROT OVER <> IF           \ lengths differ
        2DROP DROP FALSE EXIT
    THEN                     ( c-addr addr2 len )
    DUP 0= IF  DROP 2DROP TRUE EXIT  THEN
    >R SWAP R>               ( addr2 c-addr len )
    0 DO
        OVER I + C@
        OVER I + C@
        <> IF  2DROP FALSE UNLOOP EXIT  THEN
    LOOP
    2DROP TRUE ;

\ =====================================================================
\  Inode Zero / Slab Init
\ =====================================================================

: _VFS-ZERO-INODE  ( inode -- )
    VFS-INODE-SIZE 0 FILL ;

: _VFS-ZERO-FD  ( fd -- )
    VFS-FD-SIZE 0 FILL ;

\ _VFS-SLAB-INIT ( slab-addr vfs -- )
\   Initialise a freshly allocated slab page: zero the next-page
\   header, build free-list through all slots, prepend to VFS
\   inode free-list.
VARIABLE _VSI-A
VARIABLE _VSI-V

: _VFS-SLAB-INIT  ( slab-addr vfs -- )
    _VSI-V !  _VSI-A !
    \ Zero next-page header (first cell of slab page)
    0  _VSI-A @ !
    \ First inode slot starts at slab-addr + 8 (after header)
    _VSI-A @ 8 +  _VSI-A !
    \ Chain slots: each slot.+0 = address of next slot
    _VFS-SLAB-SLOTS 1- 0 DO
        _VSI-A @  VFS-INODE-SIZE +    \ next slot addr
        _VSI-A @ !                    \ current.+0 = next
        _VSI-A @  VFS-INODE-SIZE +  _VSI-A !
    LOOP
    \ Last slot.+0 = current VFS free-list head (append to chain)
    _VSI-V @ V.IFREE @  _VSI-A @ !
    \ VFS free-list head = first slot of this slab
    _VSI-V @ V.ISLAB @  8 +  _VSI-V @ V.IFREE ! ;

\ _VFS-FD-INIT ( vfs -- )
\   Build free-list through the FD pool.
VARIABLE _VFI-A

: _VFS-FD-INIT  ( vfs -- )
    DUP V.FDPOOL @  _VFI-A !
    V.FDMAX @ 1- 0 DO
        _VFI-A @  VFS-FD-SIZE +       \ next slot addr
        _VFI-A @ FD.FREE !            \ current.free = next
        _VFI-A @  VFS-FD-SIZE +  _VFI-A !
    LOOP
    0  _VFI-A @ FD.FREE !             \ last slot.free = 0
    ;

\ =====================================================================
\  Inode Alloc / Free
\ =====================================================================

\ _VFS-SLAB-GROW ( vfs -- )
\   Allocate a new slab page from the arena and link it.
VARIABLE _VSG-V
VARIABLE _VSG-S

: _VFS-SLAB-GROW  ( vfs -- )
    _VSG-V !
    \ Allocate slab page from arena
    _VSG-V @ V.ARENA @  _VFS-SLAB-SIZE ARENA-ALLOT  _VSG-S !
    \ Link: new-page.next = old slab head
    _VSG-V @ V.ISLAB @   _VSG-S @ !
    \ New page becomes slab head
    _VSG-S @  _VSG-V @ V.ISLAB !
    \ Init free-list within the new page
    _VSG-S @  _VSG-V @  _VFS-SLAB-INIT ;

VARIABLE _VIA-TY

: _VFS-INODE-ALLOC  ( type vfs -- inode )
    SWAP _VIA-TY !
    DUP V.IFREE @
    DUP 0= IF
        \ Free-list empty — grow slab
        DROP DUP _VFS-SLAB-GROW
        DUP V.IFREE @
        DUP 0= IF -1 THROW THEN  \ VFS inode pool exhausted
    THEN                          ( vfs inode )
    DUP @  ROT V.IFREE !         \ pop free-list head
    DUP _VFS-ZERO-INODE
    _VIA-TY @  OVER IN.TYPE !
    ;

: _VFS-INODE-FREE  ( inode vfs -- )
    >R
    DUP IN.NAME @ _VFS-STR-RELEASE
    DUP _VFS-ZERO-INODE
    R@ V.IFREE @  OVER !         \ inode.+0 = old head
    R> V.IFREE !                  \ head = inode
    ;

\ =====================================================================
\  FD Alloc / Free
\ =====================================================================

: _VFS-FD-ALLOC  ( vfs -- fd | 0 )
    DUP V.FDFREE @
    DUP 0= IF  NIP EXIT  THEN    \ pool exhausted
    DUP FD.FREE @  ROT V.FDFREE !  \ pop free-list
    DUP _VFS-ZERO-FD ;

: _VFS-FD-FREE  ( fd vfs -- )
    >R
    DUP _VFS-ZERO-FD
    R@ V.FDFREE @  OVER FD.FREE !  \ fd.free = old head
    R> V.FDFREE !                   \ head = fd
    ;

\ =====================================================================
\  Ramdisk Binding — Vtable
\ =====================================================================
\
\  The ramdisk binding stores file content in binding-data cell 0
\  as a pointer to an arena-allocated buffer, and cell 1 as the
\  allocated capacity.  Reads/writes copy bytes from/to that buffer.
\
\  This is the default binding when no backing store is attached.

: _VFS-RAM-PROBE     ( buf vfs -- flag )    2DROP FALSE ;
: _VFS-RAM-INIT      ( vfs -- ior )         DROP 0 ;
: _VFS-RAM-TEARDOWN  ( vfs -- )             DROP ;

\ Ramdisk READ — copy from arena buffer to user buffer.
VARIABLE _VRR-BUF
VARIABLE _VRR-LEN
VARIABLE _VRR-OFF
VARIABLE _VRR-IN

: _VFS-RAM-READ  ( buf len off inode vfs -- actual )
    DROP _VRR-IN ! _VRR-OFF ! _VRR-LEN ! _VRR-BUF !
    _VRR-IN @ IN.BDATA @
    DUP 0= IF  DROP 0 EXIT  THEN       \ no content yet
    \ avail = fsize - off
    _VRR-IN @ IN.SIZE-LO @  _VRR-OFF @ -
    DUP 0< IF  DROP DROP 0 EXIT  THEN  \ offset past EOF
    _VRR-LEN @ MIN                      ( cptr actual )
    DUP 0= IF  NIP EXIT  THEN
    >R                                  ( cptr  R: actual )
    _VRR-OFF @ +  _VRR-BUF @ R@ CMOVE  \ src → buf
    R> ;

\ Ramdisk WRITE — copy from user buffer to arena buffer.
VARIABLE _VRW-BUF
VARIABLE _VRW-LEN
VARIABLE _VRW-OFF
VARIABLE _VRW-IN
VARIABLE _VRW-VS

: _VFS-RAM-WRITE  ( buf len off inode vfs -- actual )
    _VRW-VS ! _VRW-IN ! _VRW-OFF ! _VRW-LEN ! _VRW-BUF !
    \ Ensure content buffer exists
    _VRW-IN @ IN.BDATA @
    DUP 0= IF
        DROP
        \ Allocate: cap = max(off+len, 4096)
        _VRW-OFF @ _VRW-LEN @ + 4096 MAX
        _VRW-VS @ V.ARENA @ SWAP ARENA-ALLOT
        DUP _VRW-IN @ IN.BDATA !
    THEN                                    ( cptr )
    \ Copy bytes: src=buf, dst=cptr+off
    _VRW-OFF @ +                            ( dst )
    _VRW-BUF @ SWAP _VRW-LEN @ CMOVE
    _VRW-LEN @ ;                            ( actual )
    ;
: _VFS-RAM-READDIR   ( inode vfs -- )       2DROP ;
: _VFS-RAM-SYNC      ( inode vfs -- ior )   2DROP 0 ;
: _VFS-RAM-CREATE    ( inode vfs -- ior )   2DROP 0 ;
: _VFS-RAM-DELETE    ( inode vfs -- ior )   2DROP 0 ;
: _VFS-RAM-TRUNCATE  ( inode vfs -- ior )   2DROP 0 ;

CREATE VFS-RAM-VTABLE  VFS-VT-SIZE ALLOT
' _VFS-RAM-PROBE     VFS-RAM-VTABLE  VFS-VT-PROBE    CELLS + !
' _VFS-RAM-INIT      VFS-RAM-VTABLE  VFS-VT-INIT     CELLS + !
' _VFS-RAM-TEARDOWN  VFS-RAM-VTABLE  VFS-VT-TEARDOWN CELLS + !
' _VFS-RAM-READ      VFS-RAM-VTABLE  VFS-VT-READ     CELLS + !
' _VFS-RAM-WRITE     VFS-RAM-VTABLE  VFS-VT-WRITE    CELLS + !
' _VFS-RAM-READDIR   VFS-RAM-VTABLE  VFS-VT-READDIR  CELLS + !
' _VFS-RAM-SYNC      VFS-RAM-VTABLE  VFS-VT-SYNC     CELLS + !
' _VFS-RAM-CREATE    VFS-RAM-VTABLE  VFS-VT-CREATE   CELLS + !
' _VFS-RAM-DELETE    VFS-RAM-VTABLE  VFS-VT-DELETE    CELLS + !
' _VFS-RAM-TRUNCATE  VFS-RAM-VTABLE  VFS-VT-TRUNCATE CELLS + !

\ =====================================================================
\  VFS-NEW — Create a new VFS instance
\ =====================================================================
\
\  ( arena vtable -- vfs )
\
\  Allocates from the arena:
\    1. VFS descriptor (128 bytes)
\    2. Initial inode slab page (_VFS-SLAB-SIZE bytes)
\    3. FD pool (64 × 48 = 3072 bytes)
\    4. String pool (remaining arena space)
\  Creates root directory inode (type VFS-T-DIR, name "/").

VARIABLE _VN-AR
VARIABLE _VN-VT
VARIABLE _VN-VFS

: VFS-NEW  ( arena vtable -- vfs )
    _VN-VT !  _VN-AR !

    \ 1. Allocate descriptor
    _VN-AR @  VFS-DESC-SIZE ARENA-ALLOT  _VN-VFS !

    \ Store vtable and arena
    _VN-VT @   _VN-VFS @ V.VTABLE !
    _VN-AR @   _VN-VFS @ V.ARENA !
    0          _VN-VFS @ V.FLAGS !
    0          _VN-VFS @ V.BCTX !

    \ 2. Allocate initial inode slab page
    _VN-AR @  _VFS-SLAB-SIZE ARENA-ALLOT
    _VN-VFS @ V.ISLAB !
    0  _VN-VFS @ V.IFREE !
    0  _VN-VFS @ V.ICOUNT !
    256  _VN-VFS @ V.IHWM !       \ default eviction threshold

    \ Init slab free-list
    _VN-VFS @ V.ISLAB @  _VN-VFS @  _VFS-SLAB-INIT

    \ 3. Allocate FD pool
    _VN-AR @  _VFS-FD-DEFAULT VFS-FD-SIZE * ARENA-ALLOT
    _VN-VFS @ V.FDPOOL !
    _VFS-FD-DEFAULT  _VN-VFS @ V.FDMAX !
    _VN-VFS @ V.FDPOOL @  _VN-VFS @ V.FDFREE !

    \ Init FD free-list
    _VN-VFS @  _VFS-FD-INIT

    \ 4. String pool — fixed allocation (rest stays free for
    \    file content buffers, additional slab pages, etc.)
    \    Pool size = min(65536, remaining / 4)
    _VN-AR @ DUP A.BASE @ SWAP A.SIZE @ +  _VN-AR @ A.PTR @ -
                                            ( remaining )
    4 /  65536 MIN  4096 MAX                ( pool-size )
    _VN-AR @ OVER ARENA-ALLOT              ( pool-size str-base )
    DUP  _VN-VFS @ V.STR-BASE !
    DUP  _VN-VFS @ V.STR-PTR !
    SWAP +  _VN-VFS @ V.STR-END !

    \ Set as current context
    _VN-VFS @  VFS-USE

    \ 5. Create root directory inode
    VFS-T-DIR  _VN-VFS @  _VFS-INODE-ALLOC  ( root-inode )
    DUP  _VN-VFS @ V.ROOT !
    DUP  _VN-VFS @ V.CWD !
    \ Name = "/"
    S" /"  _VN-VFS @  _VFS-STR-ALLOC
    OVER IN.NAME !
    \ Root has no parent
    0  OVER IN.PARENT !
    \ Mark children not loaded (binding will populate later)
    0  OVER IN.FLAGS !
    DROP

    \ Increment inode count
    _VN-VFS @ V.ICOUNT @  1+  _VN-VFS @ V.ICOUNT !

    \ Return VFS handle
    _VN-VFS @ ;

\ =====================================================================
\  VFS-DESTROY — Tear down a VFS instance
\ =====================================================================
\
\  ( vfs -- )
\
\  Calls the binding's teardown xt, then destroys the arena.
\  All inodes, FDs, and strings are reclaimed in bulk.

: VFS-DESTROY  ( vfs -- )
    DUP VFS-VT-TEARDOWN OVER _VFS-XT EXECUTE
    V.ARENA @  ARENA-DESTROY ;

\ =====================================================================
\  Path Resolution
\ =====================================================================
\
\  VFS-RESOLVE ( c-addr u vfs -- inode | 0 )
\
\  Iterative path resolver.  Walks "/"-delimited components from
\  root (if leading "/") or cwd.  Calls xt-readdir lazily on
\  unloaded directories.  Returns the final inode or 0 if any
\  component is not found.

\ -- Forward reference for auto-eviction hook --
\    _VFS-EVICT is defined later; we defer through a variable.
VARIABLE _VFS-EVICT-XT   \ filled once _VFS-EVICT exists
: _VFS-MAYBE-EVICT  ( vfs -- )
    DUP V.ICOUNT @
    OVER V.IHWM @  > IF
        _VFS-EVICT-XT @ EXECUTE
    ELSE  DROP  THEN ;

\ -- Helper: ensure children are loaded --
: _VFS-ENSURE-CHILDREN  ( dir-inode vfs -- )
    OVER IN.FLAGS @  VFS-IF-CHILDREN AND IF  2DROP EXIT  THEN
    2DUP VFS-VT-READDIR OVER _VFS-XT EXECUTE
    DROP IN.FLAGS DUP @ VFS-IF-CHILDREN OR SWAP ! ;

\ -- Helper: find child by name in a directory inode --
\    Walks first-child → sibling chain comparing name handles.
VARIABLE _VFC-A
VARIABLE _VFC-U

: _VFS-FIND-CHILD  ( c-addr u dir-inode -- child-inode | 0 )
    IN.CHILD @                    ( c-addr u child )
    BEGIN
        DUP 0= IF                \ end of chain
            NIP NIP EXIT
        THEN
        2 PICK 2 PICK            ( c-addr u child c-addr u )
        2 PICK IN.NAME @         ( c-addr u child c-addr u hndl )
        _VFS-STR-MATCH? IF       \ found
            NIP NIP EXIT
        THEN
        IN.SIBLING @             \ advance to next sibling
    AGAIN ;

\ -- Path resolution temporaries --
VARIABLE _VR-S       \ scan pointer into path string
VARIABLE _VR-E       \ end of path string
VARIABLE _VR-V       \ vfs
VARIABLE _VR-IN      \ current inode
VARIABLE _VR-CS      \ component start
VARIABLE _VR-CL      \ component length

: VFS-RESOLVE  ( c-addr u vfs -- inode | 0 )
    _VR-V !
    _VR-V @ _VFS-MAYBE-EVICT
    OVER + _VR-E !               \ end = addr + len
    _VR-S !                      \ scan = addr

    \ Choose starting inode
    _VR-S @ _VR-E @ < IF
        _VR-S @ C@ [CHAR] / = IF
            _VR-V @ V.ROOT @  _VR-IN !
            _VR-S @ 1+ _VR-S !  \ skip leading /
        ELSE
            _VR-V @ V.CWD @  _VR-IN !
        THEN
    ELSE
        _VR-V @ V.CWD @  _VR-IN !
        _VR-IN @ EXIT            \ empty path = cwd
    THEN

    \ Consume trailing slashes
    BEGIN
        _VR-E @ _VR-S @ > IF
            _VR-E @ 1- C@ [CHAR] / = IF
                _VR-E @ 1-  _VR-E !
                FALSE            \ continue trimming
            ELSE TRUE THEN
        ELSE TRUE THEN
    UNTIL

    \ Walk components
    BEGIN  _VR-S @ _VR-E @ <  WHILE
        \ Find next "/"
        _VR-S @  _VR-CS !
        0  _VR-CL !
        BEGIN
            _VR-S @ _VR-E @ < IF
                _VR-S @ C@ [CHAR] / <> IF
                    _VR-CL @ 1+  _VR-CL !
                    _VR-S @ 1+  _VR-S !
                    FALSE
                ELSE TRUE THEN
            ELSE TRUE THEN
        UNTIL

        \ Skip the "/" separator
        _VR-S @ _VR-E @ < IF
            _VR-S @ C@ [CHAR] / = IF
                _VR-S @ 1+  _VR-S !
            THEN
        THEN

        \ Empty component (double slash) — skip
        _VR-CL @ 0= IF  ELSE

        \ Handle "." — stay at current
        _VR-CL @ 1 = IF
            _VR-CS @ C@ [CHAR] . = IF  ELSE
                \ single char, not dot — look up
                _VR-IN @ IN.TYPE @ VFS-T-DIR <> IF
                    0 EXIT       \ not a directory
                THEN
                _VR-IN @  _VR-V @  _VFS-ENSURE-CHILDREN
                _VR-CS @ _VR-CL @  _VR-IN @  _VFS-FIND-CHILD
                DUP 0= IF  EXIT  THEN
                _VR-IN !
            THEN
        ELSE

        \ Handle ".." — go to parent
        _VR-CL @ 2 = IF
            _VR-CS @     C@ [CHAR] . = IF
            _VR-CS @ 1+  C@ [CHAR] . = IF
                _VR-IN @ IN.PARENT @
                DUP 0= IF  DROP  _VR-V @ V.ROOT @  THEN
                _VR-IN !
            ELSE
                \ two chars, second not dot — normal lookup
                _VR-IN @ IN.TYPE @ VFS-T-DIR <> IF  0 EXIT  THEN
                _VR-IN @  _VR-V @  _VFS-ENSURE-CHILDREN
                _VR-CS @ _VR-CL @  _VR-IN @  _VFS-FIND-CHILD
                DUP 0= IF  EXIT  THEN  _VR-IN !
            THEN ELSE
                \ two chars, first not dot — normal lookup
                _VR-IN @ IN.TYPE @ VFS-T-DIR <> IF  0 EXIT  THEN
                _VR-IN @  _VR-V @  _VFS-ENSURE-CHILDREN
                _VR-CS @ _VR-CL @  _VR-IN @  _VFS-FIND-CHILD
                DUP 0= IF  EXIT  THEN  _VR-IN !
            THEN
        ELSE
            \ Normal component (3+ chars or 1-2 non-special)
            _VR-IN @ IN.TYPE @ VFS-T-DIR <> IF  0 EXIT  THEN
            _VR-IN @  _VR-V @  _VFS-ENSURE-CHILDREN
            _VR-CS @ _VR-CL @  _VR-IN @  _VFS-FIND-CHILD
            DUP 0= IF  EXIT  THEN  _VR-IN !
        THEN THEN THEN
    REPEAT
    _VR-IN @ ;

\ =====================================================================
\  VFS-OPEN / VFS-CLOSE
\ =====================================================================

: VFS-OPEN  ( c-addr u -- fd | 0 )
    VFS-CUR _VFS-MAYBE-EVICT
    VFS-CUR VFS-RESOLVE         ( inode | 0 )
    DUP 0= IF  EXIT  THEN       \ not found
    \ Allocate FD
    VFS-CUR _VFS-FD-ALLOC       ( inode fd | inode 0 )
    DUP 0= IF  NIP EXIT  THEN   \ FD pool exhausted
    \ Populate FD
    TUCK FD.INODE !              ( fd )   \ fd.inode = inode
    0  OVER FD.CUR-LO !         \ cursor = 0
    0  OVER FD.CUR-HI !
    VFS-FF-READ VFS-FF-WRITE OR
    OVER FD.FLAGS !              \ default read+write
    VFS-CUR OVER FD.VFS !       \ back-pointer to VFS
    ;

: VFS-CLOSE  ( fd -- )
    DUP FD.VFS @                 ( fd vfs )
    _VFS-FD-FREE                \ return FD to pool
    ;

\ =====================================================================
\  VFS-READ / VFS-WRITE
\ =====================================================================
\
\  All reads/writes dispatch through the binding vtable.
\  The abstract layer manages the cursor; the binding moves bytes.

VARIABLE _VRD-FD
VARIABLE _VRD-ACT

: VFS-READ  ( buf len fd -- actual )
    _VRD-FD !
    \ Gather: buf len offset inode vfs
    _VRD-FD @ FD.CUR-LO @       ( buf len offset )
    _VRD-FD @ FD.INODE @        ( buf len offset inode )
    _VRD-FD @ FD.VFS @          ( buf len offset inode vfs )
    DUP >R
    VFS-VT-READ R> _VFS-XT EXECUTE   ( actual )
    _VRD-ACT !
    \ Advance cursor
    _VRD-FD @ FD.CUR-LO @  _VRD-ACT @ +
    _VRD-FD @ FD.CUR-LO !
    _VRD-ACT @ ;

VARIABLE _VWR-FD
VARIABLE _VWR-ACT

: VFS-WRITE  ( buf len fd -- actual )
    _VWR-FD !
    \ Check read-only
    _VWR-FD @ FD.VFS @  V.FLAGS @  VFS-F-RO AND IF
        2DROP -1 EXIT            \ read-only VFS
    THEN
    \ Gather: buf len offset inode vfs
    _VWR-FD @ FD.CUR-LO @       ( buf len offset )
    _VWR-FD @ FD.INODE @        ( buf len offset inode )
    _VWR-FD @ FD.VFS @          ( buf len offset inode vfs )
    DUP >R
    VFS-VT-WRITE R> _VFS-XT EXECUTE   ( actual )
    _VWR-ACT !
    \ Advance cursor
    _VWR-FD @ FD.CUR-LO @  _VWR-ACT @ +
    _VWR-FD @ FD.CUR-LO !
    \ Update inode size if write extended file
    _VWR-FD @ FD.CUR-LO @
    _VWR-FD @ FD.INODE @ IN.SIZE-LO @
    > IF
        _VWR-FD @ FD.CUR-LO @
        _VWR-FD @ FD.INODE @ IN.SIZE-LO !
        VFS-IF-DIRTY
        _VWR-FD @ FD.INODE @ IN.FLAGS DUP @ ROT OR SWAP !
    THEN
    _VWR-ACT @ ;

\ =====================================================================
\  VFS-SEEK / VFS-REWIND / VFS-TELL / VFS-SIZE
\ =====================================================================

: VFS-SEEK    ( pos fd -- )       FD.CUR-LO ! ;
: VFS-REWIND  ( fd -- )          0 SWAP FD.CUR-LO ! ;
: VFS-TELL    ( fd -- pos )      FD.CUR-LO @ ;
: VFS-SIZE    ( fd -- size )     FD.INODE @ IN.SIZE-LO @ ;

\ =====================================================================
\  Inode Tree Mutation Helpers
\ =====================================================================

\ _VFS-ADD-CHILD ( child parent -- )
\   Prepend child to parent's child list.
: _VFS-ADD-CHILD  ( child parent -- )
    2DUP SWAP IN.PARENT !       \ child.parent = parent
    DUP IN.CHILD @              ( child parent old-first )
    2 PICK IN.SIBLING !         \ child.sibling = old-first
    IN.CHILD ! ;                \ parent.child = child

\ _VFS-REMOVE-CHILD ( child parent -- )
\   Unlink child from parent's child list.
VARIABLE _VRC-PREV

: _VFS-REMOVE-CHILD  ( child parent -- )
    DUP IN.CHILD @              ( child parent first )
    2 PICK = IF
        \ child is first in list — parent.child = child.sibling
        SWAP IN.CHILD            ( child pchild-field )
        SWAP IN.SIBLING @       ( pchild-field new-first )
        SWAP ! EXIT
    THEN
    \ Walk sibling chain to find predecessor
    DUP IN.CHILD @  _VRC-PREV !
    DROP                         ( child )
    BEGIN
        _VRC-PREV @ IN.SIBLING @
        DUP 0= IF  2DROP EXIT  THEN   \ not found (shouldn't happen)
        OVER = IF
            \ prev.sibling = child.sibling
            DUP IN.SIBLING @
            _VRC-PREV @ IN.SIBLING !
            DROP EXIT
        THEN
        _VRC-PREV @ IN.SIBLING @  _VRC-PREV !
    AGAIN ;

\ =====================================================================
\  VFS-MKFILE / VFS-MKDIR / VFS-RM
\ =====================================================================

VARIABLE _VMK-V

: VFS-MKFILE  ( c-addr u vfs -- inode | 0 )
    _VMK-V !
    \ Allocate new inode
    VFS-T-FILE _VMK-V @ _VFS-INODE-ALLOC   ( c-addr u inode )
    \ Set name
    ROT ROT _VMK-V @ _VFS-STR-ALLOC        ( inode handle )
    OVER IN.NAME !                           ( inode )
    \ Zero size
    0 OVER IN.SIZE-LO !
    0 OVER IN.SIZE-HI !
    0 OVER IN.FLAGS !
    \ Add to cwd
    DUP _VMK-V @ V.CWD @  _VFS-ADD-CHILD
    \ Notify binding
    DUP _VMK-V @ VFS-VT-CREATE _VMK-V @ _VFS-XT EXECUTE DROP
    \ Increment count
    _VMK-V @ V.ICOUNT DUP @ 1+ SWAP !
    ;

: VFS-MKDIR  ( c-addr u vfs -- ior )
    _VMK-V !
    VFS-T-DIR _VMK-V @ _VFS-INODE-ALLOC    ( c-addr u inode )
    ROT ROT _VMK-V @ _VFS-STR-ALLOC        ( inode handle )
    OVER IN.NAME !
    0 OVER IN.SIZE-LO !
    0 OVER IN.SIZE-HI !
    VFS-IF-CHILDREN OVER IN.FLAGS !  \ empty dir = children loaded
    DUP _VMK-V @ V.CWD @  _VFS-ADD-CHILD
    DUP _VMK-V @  VFS-VT-CREATE _VMK-V @ _VFS-XT EXECUTE DROP
    _VMK-V @ V.ICOUNT DUP @ 1+ SWAP !
    DROP 0 ;                     \ ior = 0 (success)

VARIABLE _VRM-V
VARIABLE _VRM-IN

: VFS-RM  ( c-addr u vfs -- ior )
    _VRM-V !
    _VRM-V @ VFS-RESOLVE         ( inode | 0 )
    DUP 0= IF  DROP -1 EXIT  THEN   \ not found
    _VRM-IN !
    \ Don't delete root
    _VRM-IN @  _VRM-V @ V.ROOT @  = IF  -1 EXIT  THEN
    \ Don't delete non-empty directories
    _VRM-IN @ IN.TYPE @ VFS-T-DIR = IF
        _VRM-IN @ IN.CHILD @ 0<> IF  -1 EXIT  THEN
    THEN
    \ Notify binding (delete on-disk structures)
    _VRM-IN @  _VRM-V @  VFS-VT-DELETE _VRM-V @ _VFS-XT EXECUTE DROP
    \ Unlink from parent
    _VRM-IN @  _VRM-IN @ IN.PARENT @  _VFS-REMOVE-CHILD
    \ Free inode
    _VRM-IN @  _VRM-V @  _VFS-INODE-FREE
    \ Decrement count
    _VRM-V @ V.ICOUNT DUP @ 1- SWAP !
    0 ;                          \ ior = 0 (success)

\ =====================================================================
\  VFS-DIR / VFS-CD / VFS-STAT
\ =====================================================================

: VFS-DIR  ( vfs -- )
    DUP V.CWD @                  ( vfs cwd )
    SWAP                         ( cwd vfs )
    2DUP _VFS-ENSURE-CHILDREN   ( cwd vfs )
    NIP                          ( vfs )
    V.CWD @ IN.CHILD @          ( first-child )
    BEGIN
        DUP 0<> WHILE
        DUP IN.TYPE @ CASE
            VFS-T-DIR  OF  ." [DIR]  " ENDOF
            VFS-T-FILE OF  ."        " ENDOF
            VFS-T-SYMLINK OF ." [LNK]  " ENDOF
            ."  ???   "
        ENDCASE
        DUP IN.NAME @ _VFS-STR-GET TYPE
        DUP IN.TYPE @ VFS-T-FILE = IF
            ."   " DUP IN.SIZE-LO @ .
        THEN
        CR
        IN.SIBLING @
    REPEAT
    DROP ;

: VFS-CD  ( c-addr u vfs -- ior )
    DUP >R VFS-RESOLVE          ( inode | 0  R: vfs )
    DUP 0= IF  R> DROP -1 EXIT  THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF
        DROP R> DROP -1 EXIT     \ not a directory
    THEN
    R> V.CWD !  0 ;             \ success

: VFS-STAT  ( c-addr u vfs -- )
    DUP >R VFS-RESOLVE          ( inode | 0  R: vfs )
    R> DROP
    DUP 0= IF  DROP ." not found" CR EXIT  THEN
    ." Name:  " DUP IN.NAME @ _VFS-STR-GET TYPE CR
    ." Type:  " DUP IN.TYPE @ CASE
        VFS-T-FILE    OF  ." file"    ENDOF
        VFS-T-DIR     OF  ." dir"     ENDOF
        VFS-T-SYMLINK OF  ." symlink" ENDOF
        ." special"
    ENDCASE CR
    ." Size:  " DUP IN.SIZE-LO @ . CR
    ." Mode:  " DUP IN.MODE @ . CR
    ." Flags: " IN.FLAGS @ . CR ;

\ =====================================================================
\  VFS-SYNC — Flush dirty inodes to backing store
\ =====================================================================
\
\  ( vfs -- ior )
\
\  Walks every allocated inode across all slab pages.  For each
\  inode with the VFS-IF-DIRTY flag, calls the binding's sync xt
\  and clears the flag on success.  Returns 0 on full success,
\  or the first non-zero ior encountered.

VARIABLE _VSY-V
VARIABLE _VSY-P      \ current slab page
VARIABLE _VSY-I      \ slot index
VARIABLE _VSY-IN     \ inode address
VARIABLE _VSY-IOR    \ accumulated ior

: _VFS-INODE-IN-FREELIST?  ( inode vfs -- flag )
    V.IFREE @                    ( inode cursor )
    BEGIN
        DUP 0= IF  2DROP FALSE EXIT  THEN
        2DUP = IF  2DROP TRUE EXIT   THEN
        @                        \ follow next-free pointer
    AGAIN ;

: VFS-SYNC  ( vfs -- ior )
    _VSY-V !
    0 _VSY-IOR !
    _VSY-V @ V.ISLAB @  _VSY-P !      \ first slab page
    BEGIN  _VSY-P @ 0<>  WHILE
        _VFS-SLAB-SLOTS 0 DO
            \ Slot address = page + 8 + i*INODE-SIZE
            _VSY-P @ 8 + I VFS-INODE-SIZE * +  _VSY-IN !
            \ Skip slots on the free-list
            _VSY-IN @ _VSY-V @  _VFS-INODE-IN-FREELIST?
            0= IF
                _VSY-IN @ IN.FLAGS @  VFS-IF-DIRTY AND IF
                    _VSY-IN @  _VSY-V @
                    VFS-VT-SYNC _VSY-V @ _VFS-XT EXECUTE
                    DUP 0= IF
                        DROP
                        \ Clear dirty flag
                        _VSY-IN @ IN.FLAGS @
                        VFS-IF-DIRTY INVERT AND
                        _VSY-IN @ IN.FLAGS !
                    ELSE
                        _VSY-IOR @ 0= IF  _VSY-IOR !
                        ELSE  DROP  THEN
                    THEN
                THEN
            THEN
        LOOP
        _VSY-P @ @  _VSY-P !          \ next slab page
    REPEAT
    \ Clear VFS-level dirty flag on success
    _VSY-IOR @ 0= IF
        _VSY-V @ V.FLAGS @
        VFS-F-DIRTY INVERT AND
        _VSY-V @ V.FLAGS !
    THEN
    _VSY-IOR @ ;

\ =====================================================================
\  Eviction — Reclaim inodes when count exceeds high-water mark
\ =====================================================================
\
\  _VFS-EVICT ( vfs -- )
\
\  Called automatically by VFS-OPEN / VFS-RESOLVE when inode-count
\  exceeds inode-hwm.  Walks all slab pages; for each live inode
\  that is:
\     - NOT pinned (VFS-IF-PINNED clear)
\     - NOT dirty  (VFS-IF-DIRTY clear) — already sync'd
\     - A leaf directory whose children were loaded from binding
\       but can be discarded (VFS-IF-CHILDREN set, no child inodes)
\     - OR a non-open file inode with no FD referencing it
\
\  Evicted directory inodes get VFS-IF-CHILDREN cleared so the
\  binding re-populates on next access.
\
\  Strategy: single pass, evict up to (count - hwm/2) inodes to
\  avoid thrashing on the boundary.

VARIABLE _VEV-V
VARIABLE _VEV-P       \ slab page
VARIABLE _VEV-IN      \ inode
VARIABLE _VEV-GOAL    \ how many to evict
VARIABLE _VEV-EVICTED \ evicted so far

\ _VFS-INODE-HAS-FD? ( inode vfs -- flag )
\   True if any FD currently references this inode.
: _VFS-INODE-HAS-FD?  ( inode vfs -- flag )
    DUP V.FDPOOL @  SWAP V.FDMAX @   ( inode base max )
    0 DO
        2DUP                          ( inode base inode base )
        I VFS-FD-SIZE * +             ( inode base inode fd )
        FD.INODE @                    ( inode base inode fd-inode )
        = IF  2DROP TRUE UNLOOP EXIT  THEN
    LOOP
    2DROP FALSE ;

\ _VFS-EVICT-INODE ( inode vfs -- flag )
\   Attempt to evict a single inode.  Returns TRUE if evicted.
: _VFS-EVICT-INODE  ( inode vfs -- flag )
    >R
    DUP IN.FLAGS @  VFS-IF-PINNED AND IF
        R> 2DROP FALSE EXIT       \ pinned — skip
    THEN
    DUP IN.FLAGS @  VFS-IF-DIRTY AND IF
        R> 2DROP FALSE EXIT       \ dirty — must sync first
    THEN
    \ Directory with no children remaining? Clear loaded flag.
    DUP IN.TYPE @  VFS-T-DIR = IF
        DUP IN.CHILD @ 0= IF
            \ Directory is empty (children already removed or never
            \ populated).  Clear VFS-IF-CHILDREN so binding reloads.
            DUP IN.FLAGS @
            VFS-IF-CHILDREN INVERT AND
            OVER IN.FLAGS !
        ELSE
            \ Has child inodes — can't evict
            R> 2DROP FALSE EXIT
        THEN
    THEN
    \ File: must not have any open FD
    DUP IN.TYPE @  VFS-T-FILE = IF
        DUP R@ _VFS-INODE-HAS-FD? IF
            R> 2DROP FALSE EXIT   \ in use
        THEN
    THEN
    \ Safe to evict — unlink from parent & free
    DUP IN.PARENT @ ?DUP IF
        OVER SWAP _VFS-REMOVE-CHILD
    THEN
    DUP R@ _VFS-INODE-FREE
    R@ V.ICOUNT DUP @ 1- SWAP !
    R> DROP TRUE ;

: _VFS-EVICT  ( vfs -- )
    _VEV-V !
    \ Calculate goal: evict down to hwm/2
    _VEV-V @ V.ICOUNT @
    _VEV-V @ V.IHWM @  2 /  -
    DUP 0< IF  DROP 0  THEN
    _VEV-GOAL !
    0 _VEV-EVICTED !

    _VEV-V @ V.ISLAB @  _VEV-P !
    BEGIN
        _VEV-P @ 0<>
        _VEV-EVICTED @ _VEV-GOAL @ <  AND
    WHILE
        _VFS-SLAB-SLOTS 0 DO
            _VEV-EVICTED @ _VEV-GOAL @ >= IF  LEAVE  THEN
            _VEV-P @ 8 + I VFS-INODE-SIZE * +  _VEV-IN !
            _VEV-IN @ _VEV-V @  _VFS-INODE-IN-FREELIST?
            0= IF
                _VEV-IN @ _VEV-V @  _VFS-EVICT-INODE IF
                    _VEV-EVICTED @ 1+  _VEV-EVICTED !
                THEN
            THEN
        LOOP
        _VEV-P @ @  _VEV-P !
    REPEAT ;

\ VFS-SET-HWM ( n vfs -- )
\   Adjust the eviction high-water mark.
: VFS-SET-HWM  ( n vfs -- )  V.IHWM ! ;

\ VFS-INODE-PATH ( inode buf cap -- len )
\   Walk parent chain building "/a/b/c" into buf.
\   Returns actual length written (capped at cap).
16 CONSTANT _VIP-DEPTH
CREATE _VIP-ADDRS _VIP-DEPTH CELLS ALLOT
CREATE _VIP-LENS  _VIP-DEPTH CELLS ALLOT
VARIABLE _VIP-D  VARIABLE _VIP-BUF  VARIABLE _VIP-CAP  VARIABLE _VIP-POS

: VFS-INODE-PATH  ( inode buf cap -- len )
    _VIP-CAP !  _VIP-BUF !  0 _VIP-D !  0 _VIP-POS !
    \ Collect ancestor names
    BEGIN
        DUP IN.PARENT @ 0<>
        _VIP-D @ _VIP-DEPTH < AND
    WHILE
        DUP IN.NAME @ _VFS-STR-GET
        _VIP-D @ CELLS _VIP-LENS + !
        _VIP-D @ CELLS _VIP-ADDRS + !
        1 _VIP-D +!
        IN.PARENT @
    REPEAT
    DROP
    _VIP-D @ 0= IF
        47 _VIP-BUF @ C!                    \ '/'
        1 EXIT
    THEN
    \ Write segments deepest-first → "/a/b/c"
    _VIP-D @ 1- 0 SWAP
    DO
        _VIP-POS @ _VIP-CAP @ >= IF LEAVE THEN
        47 _VIP-BUF @ _VIP-POS @ + C!     \ '/'
        1 _VIP-POS +!
        I CELLS _VIP-ADDRS + @
        I CELLS _VIP-LENS + @
        DUP _VIP-POS @ + _VIP-CAP @ > IF
            _VIP-CAP @ _VIP-POS @ - MIN
        THEN
        DUP >R
        _VIP-BUF @ _VIP-POS @ + SWAP CMOVE
        R> _VIP-POS +!
    -1 +LOOP
    _VIP-POS @ ;

\ -- Patch forward reference now that _VFS-EVICT is defined --
' _VFS-EVICT  _VFS-EVICT-XT !

\ =====================================================================
\  Guard Section (opt-in concurrency)
\ =====================================================================
\
\  If GUARDED is defined and true, wrap public words in a mutex.
\  Field accessors (V.* IN.* FD.*) are pure offset arithmetic
\  and are NOT guarded.

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _vfs-guard

' VFS-USE          CONSTANT _vfs-use-xt
' VFS-CUR          CONSTANT _vfs-cur-xt
' VFS-NEW          CONSTANT _vfs-new-xt
' VFS-DESTROY      CONSTANT _vfs-destroy-xt
' VFS-RESOLVE      CONSTANT _vfs-resolve-xt
' VFS-OPEN         CONSTANT _vfs-open-xt
' VFS-CLOSE        CONSTANT _vfs-close-xt
' VFS-READ         CONSTANT _vfs-read-xt
' VFS-WRITE        CONSTANT _vfs-write-xt
' VFS-SEEK         CONSTANT _vfs-seek-xt
' VFS-REWIND       CONSTANT _vfs-rewind-xt
' VFS-TELL         CONSTANT _vfs-tell-xt
' VFS-SIZE         CONSTANT _vfs-size-xt
' VFS-MKFILE       CONSTANT _vfs-mkfile-xt
' VFS-MKDIR        CONSTANT _vfs-mkdir-xt
' VFS-RM           CONSTANT _vfs-rm-xt
' VFS-DIR          CONSTANT _vfs-dir-xt
' VFS-CD           CONSTANT _vfs-cd-xt
' VFS-STAT         CONSTANT _vfs-stat-xt
' VFS-SYNC         CONSTANT _vfs-sync-xt
' VFS-SET-HWM      CONSTANT _vfs-set-hwm-xt
' VFS-INODE-PATH   CONSTANT _vfs-inode-path-xt

: VFS-USE          _vfs-use-xt      _vfs-guard WITH-GUARD ;
: VFS-CUR          _vfs-cur-xt      _vfs-guard WITH-GUARD ;
: VFS-NEW          _vfs-new-xt      _vfs-guard WITH-GUARD ;
: VFS-DESTROY      _vfs-destroy-xt  _vfs-guard WITH-GUARD ;
: VFS-RESOLVE      _vfs-resolve-xt  _vfs-guard WITH-GUARD ;
: VFS-OPEN         _vfs-open-xt     _vfs-guard WITH-GUARD ;
: VFS-CLOSE        _vfs-close-xt    _vfs-guard WITH-GUARD ;
: VFS-READ         _vfs-read-xt     _vfs-guard WITH-GUARD ;
: VFS-WRITE        _vfs-write-xt    _vfs-guard WITH-GUARD ;
: VFS-SEEK         _vfs-seek-xt     _vfs-guard WITH-GUARD ;
: VFS-REWIND       _vfs-rewind-xt   _vfs-guard WITH-GUARD ;
: VFS-TELL         _vfs-tell-xt     _vfs-guard WITH-GUARD ;
: VFS-SIZE         _vfs-size-xt     _vfs-guard WITH-GUARD ;
: VFS-MKFILE       _vfs-mkfile-xt   _vfs-guard WITH-GUARD ;
: VFS-MKDIR        _vfs-mkdir-xt    _vfs-guard WITH-GUARD ;
: VFS-RM           _vfs-rm-xt       _vfs-guard WITH-GUARD ;
: VFS-DIR          _vfs-dir-xt      _vfs-guard WITH-GUARD ;
: VFS-CD           _vfs-cd-xt       _vfs-guard WITH-GUARD ;
: VFS-STAT         _vfs-stat-xt     _vfs-guard WITH-GUARD ;
: VFS-SYNC         _vfs-sync-xt     _vfs-guard WITH-GUARD ;
: VFS-SET-HWM      _vfs-set-hwm-xt  _vfs-guard WITH-GUARD ;
: VFS-INODE-PATH   _vfs-inode-path-xt _vfs-guard WITH-GUARD ;

[THEN] [THEN]
