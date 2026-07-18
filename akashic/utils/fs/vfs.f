\ vfs.f — Abstract VFS data structure for KDOS Forth
\
\ Arena-backed virtual filesystem.  Each VFS instance lives in a
\ single KDOS arena, enabling multiple simultaneous filesystems
\ and O(1) bulk teardown via ARENA-DESTROY.
\
\ The VFS is a pure in-memory dentry tree with shared vnodes, a file-
\ descriptor pool, string pool, and path resolver.  It knows
\ nothing about sectors, DMA, MMIO, or any on-disk format.
\ Actual byte transfer is delegated to a binding — a separate
\ module that connects a VFS instance to a backing store.
\
\ VFS-RAM-BINDING supplies the in-memory implementation.
\
\ Prefix: VFS-   (public API)
\         _VFS-  (internal helpers)
\
\ Load with:   REQUIRE utils/fs/vfs.f

PROVIDED akashic-vfs
REQUIRE ../../text/utf8.f
REQUIRE ../memory-span.f

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

\ Attribute update mask.  Size changes deliberately remain VFS-TRUNCATE.
1  CONSTANT VFS-SA-MODE
2  CONSTANT VFS-SA-UID
4  CONSTANT VFS-SA-GID
8  CONSTANT VFS-SA-ATIME
16 CONSTANT VFS-SA-MTIME
32 CONSTANT VFS-SA-CTIME
64 CONSTANT VFS-SA-RDEV
VFS-SA-MODE VFS-SA-UID OR VFS-SA-GID OR VFS-SA-ATIME OR
VFS-SA-MTIME OR VFS-SA-CTIME OR VFS-SA-RDEV OR
CONSTANT VFS-SA-ALL

1 CONSTANT VFS-XATTR-CREATE
2 CONSTANT VFS-XATTR-REPLACE

\ VFS instance flags (bit masks)
1 CONSTANT VFS-F-RO            \ read-only
2 CONSTANT VFS-F-DIRTY         \ has unsync'd state
4 CONSTANT VFS-F-MOUNTED       \ registered in mount table

\ =====================================================================
\  Sizes
\ =====================================================================

64  CONSTANT VFS-INODE-SIZE    \ compatibility name: dentry record
184 CONSTANT VFS-VNODE-SIZE
64  CONSTANT VFS-FD-SIZE
88  CONSTANT VFS-ATTR-SIZE
VFS-ATTR-SIZE CONSTANT VFS-SETATTR-REQ-SIZE
96  CONSTANT VFS-STATFS-SIZE

\ Binding ABI 1 is a validated descriptor plus a fixed operation-table
\ prefix.  There is deliberately no compatibility path for the former raw
\ ten-XT table.
0x564653424E443031 CONSTANT VFS-BINDING-MAGIC  \ "VFSBND01"
1 CONSTANT VFS-BINDING-ABI-MAJOR
0 CONSTANT VFS-BINDING-ABI-MINOR
80 CONSTANT VFS-BINDING-DESC-SIZE
27 CONSTANT VFS-OP-COUNT
VFS-OP-COUNT CELLS CONSTANT VFS-OPS-SIZE

\ Default pool sizes
256 CONSTANT _VFS-FD-DEFAULT   \ default FD pool slots

\ Slab page: 1 cell header + N inode slots
\ Header cell = pointer to next slab page (0 = last page)
\ We size each slab page to hold 64 inodes + header:
\   8 + (64 × 64) = 4104 bytes
64  CONSTANT _VFS-SLAB-SLOTS
8 64 VFS-INODE-SIZE * + CONSTANT _VFS-SLAB-SIZE

\ =====================================================================
\  Binding operation slots and capabilities
\ =====================================================================

 0 CONSTANT VFS-OP-PROBE
 1 CONSTANT VFS-OP-MOUNT
 2 CONSTANT VFS-OP-UNMOUNT
 3 CONSTANT VFS-OP-LOOKUP
 4 CONSTANT VFS-OP-READDIR
 5 CONSTANT VFS-OP-OPEN
 6 CONSTANT VFS-OP-RELEASE
 7 CONSTANT VFS-OP-READ
 8 CONSTANT VFS-OP-WRITE
 9 CONSTANT VFS-OP-CREATE
10 CONSTANT VFS-OP-MKDIR
11 CONSTANT VFS-OP-UNLINK
12 CONSTANT VFS-OP-RMDIR
13 CONSTANT VFS-OP-RENAME
14 CONSTANT VFS-OP-TRUNCATE
15 CONSTANT VFS-OP-GETATTR
16 CONSTANT VFS-OP-SETATTR
17 CONSTANT VFS-OP-LINK
18 CONSTANT VFS-OP-SYMLINK
19 CONSTANT VFS-OP-READLINK
20 CONSTANT VFS-OP-SYNCFS
21 CONSTANT VFS-OP-FSYNC
22 CONSTANT VFS-OP-LISTXATTR
23 CONSTANT VFS-OP-GETXATTR
24 CONSTANT VFS-OP-SETXATTR
25 CONSTANT VFS-OP-REMOVEXATTR
26 CONSTANT VFS-OP-STATFS

: _VFS-OP-BIT  ( slot -- mask )  1 SWAP LSHIFT ;

1  0 LSHIFT CONSTANT VFS-CAP-PROBE
1  1 LSHIFT CONSTANT VFS-CAP-MOUNT
1  2 LSHIFT CONSTANT VFS-CAP-UNMOUNT
1  3 LSHIFT CONSTANT VFS-CAP-LOOKUP
1  4 LSHIFT CONSTANT VFS-CAP-READDIR
1  5 LSHIFT CONSTANT VFS-CAP-OPEN
1  6 LSHIFT CONSTANT VFS-CAP-RELEASE
1  7 LSHIFT CONSTANT VFS-CAP-READ
1  8 LSHIFT CONSTANT VFS-CAP-WRITE
1  9 LSHIFT CONSTANT VFS-CAP-CREATE
1 10 LSHIFT CONSTANT VFS-CAP-MKDIR
1 11 LSHIFT CONSTANT VFS-CAP-UNLINK
1 12 LSHIFT CONSTANT VFS-CAP-RMDIR
1 13 LSHIFT CONSTANT VFS-CAP-RENAME
1 14 LSHIFT CONSTANT VFS-CAP-TRUNCATE
1 15 LSHIFT CONSTANT VFS-CAP-GETATTR
1 16 LSHIFT CONSTANT VFS-CAP-SETATTR
1 17 LSHIFT CONSTANT VFS-CAP-LINK
1 18 LSHIFT CONSTANT VFS-CAP-SYMLINK
1 19 LSHIFT CONSTANT VFS-CAP-READLINK
1 20 LSHIFT CONSTANT VFS-CAP-SYNCFS
1 21 LSHIFT CONSTANT VFS-CAP-FSYNC
1 22 LSHIFT CONSTANT VFS-CAP-LISTXATTR
1 23 LSHIFT CONSTANT VFS-CAP-GETXATTR
1 24 LSHIFT CONSTANT VFS-CAP-SETXATTR
1 25 LSHIFT CONSTANT VFS-CAP-REMOVEXATTR
1 26 LSHIFT CONSTANT VFS-CAP-STATFS
1 32 LSHIFT CONSTANT VFS-CAP-ATOMIC-RENAME
1 33 LSHIFT CONSTANT VFS-CAP-CROSSDIR-RENAME
1 34 LSHIFT CONSTANT VFS-CAP-RENAME-REPLACE
1 35 LSHIFT CONSTANT VFS-CAP-SPARSE
1 36 LSHIFT CONSTANT VFS-CAP-DATA-ONLY-FSYNC
1 37 LSHIFT CONSTANT VFS-CAP-STABLE-HANDLES

1 CONSTANT VFS-BF-NEEDS-VOLUME
2 CONSTANT VFS-BF-CASE-INSENSITIVE
4 CONSTANT VFS-BF-READ-ONLY
8 CONSTANT VFS-BF-STABLE-IDS

: VB.MAGIC      ;
: VB.MAJOR      8 + ;
: VB.MINOR      16 + ;
: VB.DESC-SIZE  24 + ;
: VB.OPS-SIZE   32 + ;
: VB.CAPS       40 + ;
: VB.FLAGS      48 + ;
: VB.OPS        56 + ;
: VB.NAME       64 + ;
: VB.NAME-LEN   72 + ;

\ Structured result: reason[15:0], domain[23:16], flags[31:24], and
\ backend detail[63:32].
0 CONSTANT VFS-IOR-D-CORE
1 CONSTANT VFS-IOR-D-VOLUME
2 CONSTANT VFS-IOR-D-BINDING
3 CONSTANT VFS-IOR-D-FORMAT

1 CONSTANT VFS-IOR-F-RETRYABLE
2 CONSTANT VFS-IOR-F-PARTIAL
4 CONSTANT VFS-IOR-F-CORRUPT
8 CONSTANT VFS-IOR-F-STALE
16 CONSTANT VFS-IOR-F-READONLY

: VFS-IOR-MAKE  ( detail flags domain reason -- ior )
    0xFFFF AND >R
    0xFF AND 16 LSHIFT
    SWAP 0xFF AND 24 LSHIFT OR
    SWAP 0xFFFFFFFF AND 32 LSHIFT OR
    R> OR ;
: VFS-IOR-REASON  ( ior -- u )  0xFFFF AND ;
: VFS-IOR-DOMAIN  ( ior -- u )  16 RSHIFT 0xFF AND ;
: VFS-IOR-FLAGS   ( ior -- u )  24 RSHIFT 0xFF AND ;
: VFS-IOR-DETAIL  ( ior -- u )  32 RSHIFT ;

1  CONSTANT VFS-R-INVALID
2  CONSTANT VFS-R-NOENT
3  CONSTANT VFS-R-EXISTS
4  CONSTANT VFS-R-NOTDIR
5  CONSTANT VFS-R-ISDIR
6  CONSTANT VFS-R-NOTEMPTY
7  CONSTANT VFS-R-READONLY
8  CONSTANT VFS-R-NOSPC
9  CONSTANT VFS-R-IO
10 CONSTANT VFS-R-CORRUPT
11 CONSTANT VFS-R-UNSUPPORTED
12 CONSTANT VFS-R-CONFLICT
13 CONSTANT VFS-R-STALE
14 CONSTANT VFS-R-BUSY
15 CONSTANT VFS-R-OVERFLOW
16 CONSTANT VFS-R-BADF
17 CONSTANT VFS-R-NAMETOOLONG
18 CONSTANT VFS-R-LOOP
19 CONSTANT VFS-R-XDEV
20 CONSTANT VFS-R-NOMEM
21 CONSTANT VFS-R-NOVOLUME

\ Private spellings remain source-compatible with pre-ABI-1 adapters.
VFS-R-INVALID     CONSTANT _VFS-R-INVALID
VFS-R-NOENT       CONSTANT _VFS-R-NOENT
VFS-R-EXISTS      CONSTANT _VFS-R-EXISTS
VFS-R-NOTDIR      CONSTANT _VFS-R-NOTDIR
VFS-R-ISDIR       CONSTANT _VFS-R-ISDIR
VFS-R-NOTEMPTY    CONSTANT _VFS-R-NOTEMPTY
VFS-R-READONLY    CONSTANT _VFS-R-READONLY
VFS-R-NOSPC       CONSTANT _VFS-R-NOSPC
VFS-R-IO          CONSTANT _VFS-R-IO
VFS-R-CORRUPT     CONSTANT _VFS-R-CORRUPT
VFS-R-UNSUPPORTED CONSTANT _VFS-R-UNSUPPORTED
VFS-R-CONFLICT    CONSTANT _VFS-R-CONFLICT
VFS-R-STALE       CONSTANT _VFS-R-STALE
VFS-R-BUSY        CONSTANT _VFS-R-BUSY
VFS-R-OVERFLOW    CONSTANT _VFS-R-OVERFLOW
VFS-R-BADF        CONSTANT _VFS-R-BADF
VFS-R-NAMETOOLONG CONSTANT _VFS-R-NAMETOOLONG
VFS-R-LOOP        CONSTANT _VFS-R-LOOP
VFS-R-XDEV        CONSTANT _VFS-R-XDEV
VFS-R-NOMEM       CONSTANT _VFS-R-NOMEM
VFS-R-NOVOLUME    CONSTANT _VFS-R-NOVOLUME

0 0 VFS-IOR-D-CORE _VFS-R-INVALID     VFS-IOR-MAKE CONSTANT VFS-E-INVALID
0 0 VFS-IOR-D-CORE _VFS-R-NOENT       VFS-IOR-MAKE CONSTANT VFS-E-NOENT
0 0 VFS-IOR-D-CORE _VFS-R-EXISTS      VFS-IOR-MAKE CONSTANT VFS-E-EXISTS
0 0 VFS-IOR-D-CORE _VFS-R-NOTDIR      VFS-IOR-MAKE CONSTANT VFS-E-NOTDIR
0 0 VFS-IOR-D-CORE _VFS-R-ISDIR       VFS-IOR-MAKE CONSTANT VFS-E-ISDIR
0 0 VFS-IOR-D-CORE _VFS-R-NOTEMPTY    VFS-IOR-MAKE CONSTANT VFS-E-NOTEMPTY
0 VFS-IOR-F-READONLY VFS-IOR-D-CORE _VFS-R-READONLY VFS-IOR-MAKE CONSTANT VFS-E-READONLY
0 0 VFS-IOR-D-CORE _VFS-R-NOSPC       VFS-IOR-MAKE CONSTANT VFS-E-NOSPC
0 0 VFS-IOR-D-CORE _VFS-R-IO          VFS-IOR-MAKE CONSTANT VFS-E-IO
0 VFS-IOR-F-CORRUPT VFS-IOR-D-CORE _VFS-R-CORRUPT VFS-IOR-MAKE CONSTANT VFS-E-CORRUPT
0 0 VFS-IOR-D-CORE _VFS-R-UNSUPPORTED VFS-IOR-MAKE CONSTANT VFS-E-UNSUPPORTED
0 0 VFS-IOR-D-CORE _VFS-R-CONFLICT    VFS-IOR-MAKE CONSTANT VFS-E-CONFLICT
0 VFS-IOR-F-STALE VFS-IOR-D-CORE _VFS-R-STALE VFS-IOR-MAKE CONSTANT VFS-E-STALE
0 0 VFS-IOR-D-CORE _VFS-R-BUSY        VFS-IOR-MAKE CONSTANT VFS-E-BUSY
0 0 VFS-IOR-D-CORE _VFS-R-OVERFLOW    VFS-IOR-MAKE CONSTANT VFS-E-OVERFLOW
0 0 VFS-IOR-D-CORE _VFS-R-BADF        VFS-IOR-MAKE CONSTANT VFS-E-BADF
0 0 VFS-IOR-D-CORE _VFS-R-NAMETOOLONG VFS-IOR-MAKE CONSTANT VFS-E-NAMETOOLONG
0 0 VFS-IOR-D-CORE _VFS-R-LOOP        VFS-IOR-MAKE CONSTANT VFS-E-LOOP
0 0 VFS-IOR-D-CORE _VFS-R-XDEV        VFS-IOR-MAKE CONSTANT VFS-E-XDEV
0 0 VFS-IOR-D-CORE _VFS-R-NOMEM       VFS-IOR-MAKE CONSTANT VFS-E-NOMEM
0 0 VFS-IOR-D-CORE _VFS-R-NOVOLUME    VFS-IOR-MAKE CONSTANT VFS-E-NOVOLUME

\ =====================================================================
\  VFS Descriptor Layout
\ =====================================================================
\
\    +0   binding       validated ABI-1 binding descriptor
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
\  +128   volume        explicit volume object (0 only for no-volume binding)
\  +136   volume-cookie immutable attachment identity
\  +144   media-gen     generation captured at mount
\  +152   last-ior      diagnostic copy of the last result
\  +160   lifecycle     VFS-L-* state
\  +168   open-count    live file descriptors
\  +176   vnode-free    reusable vnode records
\  +184   vnode-count   live vnode records
\  +192   reserved
\  +200   reserved

208 CONSTANT VFS-DESC-SIZE

: V.BINDING    ;              \ +0
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
: V.VOLUME     128 + ;        \ +128
: V.VOL-COOKIE 136 + ;        \ +136
: V.MEDIA-GEN  144 + ;        \ +144
: V.LAST-IOR   152 + ;        \ +152
: V.LIFECYCLE  160 + ;        \ +160
: V.OPEN-COUNT 168 + ;        \ +168
: V.VFREE      176 + ;        \ +176
: V.VCOUNT     184 + ;        \ +184
: V.NEXT-BID   192 + ;        \ +192 (RAM and synthetic bindings)

0 CONSTANT VFS-L-NEW
1 CONSTANT VFS-L-MOUNTED
2 CONSTANT VFS-L-UNMOUNTING
3 CONSTANT VFS-L-UNMOUNTED
4 CONSTANT VFS-L-STALE

\ A dentry has one name and parent and points at a shared vnode.  This split
\ makes hard links and unlink-while-open representable.
: D.CHILD      ;
: D.SIBLING    8 + ;
: D.PARENT     16 + ;
: D.VNODE      24 + ;
: D.NAME       32 + ;
: D.FLAGS      40 + ;
: D.COOKIE     48 + ;
: D.OWNER      56 + ;
: D.ALIAS      D.OWNER ;       \ retired spelling; ABI 1 stores owner VFS

1 CONSTANT VFS-DF-UNLINKED

\ Vnode fields retain the old metadata offsets where practical so legacy
\ IN.* source accessors can dereference through D.VNODE.
: VN.NEXT      ;
: VN.TYPE      8 + ;
: VN.SIZE-LO   16 + ;
: VN.SIZE-HI   24 + ;
: VN.MODE      32 + ;
: VN.MTIME     40 + ;
: VN.CTIME     48 + ;
: VN.UID       56 + ;
: VN.GID       64 + ;
: VN.NLINK     72 + ;
: VN.BID       80 + ;
: VN.BDATA     88 + ;
: VN.FLAGS     104 + ;
: VN.ATIME     112 + ;
: VN.ATIME-NS  120 + ;
: VN.MTIME-NS  128 + ;
: VN.CTIME-NS  136 + ;
: VN.BLOCKS    144 + ;
: VN.OPEN-REFS 152 + ;
: VN.DREFS     160 + ;
: VN.GEN       168 + ;
: VN.RDEV      176 + ;

\ Binding-neutral SETATTR request.  A binding commits these values first;
\ the VFS publishes selected fields into the shared vnode only on success.
: VA.MASK       ;
: VA.MODE       8 + ;
: VA.UID        16 + ;
: VA.GID        24 + ;
: VA.ATIME      32 + ;
: VA.ATIME-NS   40 + ;
: VA.MTIME      48 + ;
: VA.MTIME-NS   56 + ;
: VA.CTIME      64 + ;
: VA.CTIME-NS   72 + ;
: VA.RDEV       80 + ;

\ Binding-neutral STATFS result.  Counts are unsigned 64-bit cells.
: VSF.BSIZE     ;
: VSF.FRSIZE    8 + ;
: VSF.BLOCKS    16 + ;
: VSF.BFREE     24 + ;
: VSF.BAVAIL    32 + ;
: VSF.FILES     40 + ;
: VSF.FFREE     48 + ;
: VSF.NAMEMAX   56 + ;
: VSF.FLAGS     64 + ;
: VSF.FSID-LO   72 + ;
: VSF.FSID-HI   80 + ;
: VSF.RESERVED  88 + ;

\ =====================================================================
\  Compatibility inode accessors
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

: IN.CHILD      D.CHILD ;
: IN.TYPE       D.VNODE @ VN.TYPE ;
: IN.SIZE-LO    D.VNODE @ VN.SIZE-LO ;
: IN.SIZE-HI    D.VNODE @ VN.SIZE-HI ;
: IN.MODE       D.VNODE @ VN.MODE ;
: IN.MTIME      D.VNODE @ VN.MTIME ;
: IN.CTIME      D.VNODE @ VN.CTIME ;
: IN.PARENT     D.PARENT ;
: IN.SIBLING    D.SIBLING ;
: IN.NAME       D.NAME ;
: IN.BID        D.VNODE @ VN.BID ;
: IN.BDATA      D.VNODE @ VN.BDATA ;
: IN.FLAGS      D.VNODE @ VN.FLAGS ;

\ =====================================================================
\  File Descriptor Layout (8 cells = 64 bytes)
\ =====================================================================
\
\    +0   inode         pointer to referenced inode
\    +8   cursor-lo     byte offset low cell
\   +16   cursor-hi     byte offset high cell
\   +24   flags         VFS-FF-READ, VFS-FF-WRITE, …
\   +32   vfs           back-pointer to owning VFS instance
\   +40   binding-cookie
\   +48   attachment-generation snapshot
\   +56   next-free     free-list chain (when not in use)

: FD.INODE     ;              \ +0
: FD.CUR-LO    8 + ;          \ +8
: FD.CUR-HI    16 + ;         \ +16
: FD.FLAGS     24 + ;         \ +24
: FD.VFS       32 + ;         \ +32
: FD.COOKIE    40 + ;         \ +40
: FD.GEN       48 + ;         \ +48
: FD.FREE      56 + ;         \ +56

\ =====================================================================
\  Current VFS Context
\ =====================================================================

VARIABLE _VFS-CUR    \ current VFS instance handle

: VFS-USE   ( vfs -- )  _VFS-CUR ! ;
: VFS-CUR   ( -- vfs )  _VFS-CUR @ ;

\ =====================================================================
\  Binding validation and dispatch helpers
\ =====================================================================

: _VFS-XT  ( slot vfs -- xt )
    V.BINDING @ VB.OPS @
    SWAP CELLS +     \ offset to slot
    @ ;              \ fetch xt

: VFS-CAPS@  ( vfs -- mask )  V.BINDING @ VB.CAPS @ ;

: VFS-HAS?  ( capability vfs -- flag )
    VFS-CAPS@ AND 0<> ;

: _VFS-HAS-OP?  ( slot vfs -- flag )
    >R _VFS-OP-BIT R> VFS-HAS? ;

: _VFS-RESULT  ( ior vfs -- ior )
    OVER SWAP V.LAST-IOR ! ;

: _VFS-MOUNTED?  ( vfs -- flag )
    V.LIFECYCLE @ VFS-L-MOUNTED = ;

VARIABLE _VRY-V
VARIABLE _VRY-VOL

: _VFS-ATTACHMENT-CURRENT?  ( vfs -- flag )
    _VRY-V !
    _VRY-V @ V.BINDING @ VB.FLAGS @ VFS-BF-NEEDS-VOLUME AND 0= IF
        TRUE EXIT
    THEN
    _VRY-V @ V.VOLUME @ DUP 0= IF DROP FALSE EXIT THEN _VRY-VOL !
    _VRY-VOL @ VOL-VALID? 0= IF FALSE EXIT THEN
    _VRY-VOL @ VOL-STALE? IF FALSE EXIT THEN
    _VRY-VOL @ VOL.COOKIE _VRY-V @ V.VOL-COOKIE @ =
    _VRY-VOL @ VOL.MEDIA-GEN _VRY-V @ V.MEDIA-GEN @ = AND ;

: _VFS-READY  ( vfs -- ior )
    DUP V.LIFECYCLE @ DUP VFS-L-STALE = IF
        2DROP VFS-E-STALE EXIT
    THEN
    VFS-L-MOUNTED <> IF DROP VFS-E-BUSY EXIT THEN
    DUP _VFS-ATTACHMENT-CURRENT? 0= IF
        VFS-L-STALE OVER V.LIFECYCLE !
        VFS-E-STALE SWAP _VFS-RESULT EXIT
    THEN
    DROP 0 ;

VARIABLE _VBV-B
VARIABLE _VBV-CAPS
VARIABLE _VBV-OPS

: VFS-BINDING-VALID?  ( binding -- flag )
    DUP 0= IF DROP FALSE EXIT THEN _VBV-B !
    _VBV-B @ VB.MAGIC @ VFS-BINDING-MAGIC <> IF FALSE EXIT THEN
    \ Major is exact.  ABI-1 minors are additive: sizes and caps select the
    \ prefix this core understands, so VB.MINOR is intentionally not gated.
    _VBV-B @ VB.MAJOR @ VFS-BINDING-ABI-MAJOR <> IF FALSE EXIT THEN
    _VBV-B @ VB.DESC-SIZE @ VFS-BINDING-DESC-SIZE < IF FALSE EXIT THEN
    _VBV-B @ VB.OPS-SIZE @ VFS-OPS-SIZE < IF FALSE EXIT THEN
    _VBV-B @ VB.OPS @ DUP 0= IF DROP FALSE EXIT THEN _VBV-OPS !
    _VBV-B @ VB.CAPS @ _VBV-CAPS !
    \ ABI 1 namespace matching is byte-sensitive.  Reject the folding claim
    \ until the core has one pinned canonicalization rule for both its cache
    \ and binding LOOKUP results.
    _VBV-B @ VB.FLAGS @ VFS-BF-CASE-INSENSITIVE AND IF FALSE EXIT THEN
    VFS-OP-COUNT 0 DO
        _VBV-CAPS @ I _VFS-OP-BIT AND IF
            _VBV-OPS @ I CELLS + @ 0= IF FALSE UNLOOP EXIT THEN
        THEN
    LOOP
    \ Known ABI-1 semantic claims must have their operation prerequisites.
    _VBV-CAPS @ VFS-CAP-ATOMIC-RENAME VFS-CAP-CROSSDIR-RENAME OR
        VFS-CAP-RENAME-REPLACE OR AND IF
        _VBV-CAPS @ VFS-CAP-RENAME AND 0= IF FALSE EXIT THEN
    THEN
    _VBV-CAPS @ VFS-CAP-DATA-ONLY-FSYNC AND IF
        _VBV-CAPS @ VFS-CAP-FSYNC AND 0= IF FALSE EXIT THEN
    THEN
    _VBV-B @ VB.FLAGS @ VFS-BF-STABLE-IDS AND IF
        _VBV-CAPS @ VFS-CAP-GETATTR AND 0= IF FALSE EXIT THEN
    THEN
    _VBV-CAPS @ VFS-CAP-STABLE-HANDLES AND IF
        _VBV-B @ VB.FLAGS @ VFS-BF-STABLE-IDS AND 0= IF FALSE EXIT THEN
        _VBV-CAPS @ VFS-CAP-GETATTR AND 0= IF FALSE EXIT THEN
    THEN
    TRUE ;

100 CONSTANT VFS-PROBE-MAX
VARIABLE _VPR-BINDING
VARIABLE _VPR-VOLUME
VARIABLE _VPR-SCORE
VARIABLE _VPR-IOR

: VFS-PROBE  ( binding volume -- score ior )
    _VPR-VOLUME ! _VPR-BINDING !
    _VPR-BINDING @ VFS-BINDING-VALID? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VPR-BINDING @ VB.CAPS @ VFS-CAP-PROBE AND 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VPR-BINDING @ VB.FLAGS @ VFS-BF-NEEDS-VOLUME AND
    _VPR-VOLUME @ 0= AND IF 0 VFS-E-NOVOLUME EXIT THEN
    _VPR-VOLUME @ ?DUP IF
        DUP VOL-VALID? 0= IF DROP 0 VFS-E-INVALID EXIT THEN
        VOL-STALE? IF 0 VFS-E-STALE EXIT THEN
    THEN
    _VPR-VOLUME @
    _VPR-BINDING @ VB.OPS @ VFS-OP-PROBE CELLS + @ EXECUTE
    _VPR-IOR ! _VPR-SCORE !
    _VPR-IOR @ IF 0 _VPR-IOR @ EXIT THEN
    _VPR-SCORE @ 0< _VPR-SCORE @ VFS-PROBE-MAX > OR IF
        0 VFS-E-CORRUPT EXIT
    THEN
    _VPR-SCORE @ 0 ;

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
\   Initialise a slab page whose next-page header was set by the caller:
\   build the free-list through all slots and prepend it to VFS.IFREE.
VARIABLE _VSI-A
VARIABLE _VSI-V

: _VFS-SLAB-INIT  ( slab-addr vfs -- )
    _VSI-V !  _VSI-A !
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
\  Dentry and vnode allocation
\ =====================================================================

\ _VFS-SLAB-GROW ( vfs -- )
\   Allocate a new slab page from the arena and link it.
VARIABLE _VSG-V
VARIABLE _VSG-S

: _VFS-SLAB-GROW  ( vfs -- flag )
    _VSG-V !
    \ Allocate slab page from arena
    _VSG-V @ V.ARENA @ _VFS-SLAB-SIZE ARENA-ALLOT?
    IF DROP FALSE EXIT THEN _VSG-S !
    \ Link: new-page.next = old slab head
    _VSG-V @ V.ISLAB @   _VSG-S @ !
    \ New page becomes slab head
    _VSG-S @  _VSG-V @ V.ISLAB !
    \ Init free-list within the new page
    _VSG-S @ _VSG-V @ _VFS-SLAB-INIT
    TRUE ;

VARIABLE _VDA-V

: _VFS-DENTRY-ALLOC  ( vfs -- dentry | 0 )
    DUP _VDA-V !
    DUP V.IFREE @
    DUP 0= IF
        DROP DUP _VFS-SLAB-GROW 0= IF DROP 0 EXIT THEN
        DUP V.IFREE @
        DUP 0= IF NIP EXIT THEN
    THEN                         ( vfs dentry )
    DUP @ ROT V.IFREE !
    DUP _VFS-ZERO-INODE
    _VDA-V @ OVER D.OWNER !
    ;

VARIABLE _VVA-TY
VARIABLE _VVA-V
VARIABLE _VVA-VN

: _VFS-VNODE-ALLOC  ( type vfs -- vnode | 0 )
    _VVA-V ! _VVA-TY !
    _VVA-V @ V.VFREE @ ?DUP IF
        DUP VN.NEXT @ _VVA-V @ V.VFREE !
    ELSE
        _VVA-V @ V.ARENA @ VFS-VNODE-SIZE ARENA-ALLOT?
        IF DROP 0 EXIT THEN
    THEN
    DUP _VVA-VN ! VFS-VNODE-SIZE 0 FILL
    _VVA-TY @ _VVA-VN @ VN.TYPE !
    1 _VVA-VN @ VN.NLINK !
    1 _VVA-VN @ VN.DREFS !
    _VVA-V @ V.VCOUNT DUP @ 1+ SWAP !
    _VVA-VN @ ;

VARIABLE _VIA-TY
VARIABLE _VIA-V
VARIABLE _VIA-D

: _VFS-INODE-ALLOC  ( type vfs -- inode | 0 )
    _VIA-V ! _VIA-TY !
    _VIA-V @ _VFS-DENTRY-ALLOC DUP 0= IF EXIT THEN _VIA-D !
    _VIA-TY @ _VIA-V @ _VFS-VNODE-ALLOC DUP 0= IF
        _VIA-D @ _VFS-ZERO-INODE
        _VIA-V @ V.IFREE @ _VIA-D @ !
        _VIA-D @ _VIA-V @ V.IFREE !
        0 EXIT
    THEN
    _VIA-D @ D.VNODE !
    _VIA-D @ ;

VARIABLE _VFR-VN
VARIABLE _VFR-V

: _VFS-VNODE-MAYBE-FREE  ( vnode vfs -- )
    _VFR-V ! _VFR-VN !
    \ NLINK is persistent filesystem metadata, not a cache reference.  An
    \ evicted vnode with no dentries or opens must be reclaimable even while
    \ its on-disk link count remains nonzero.
    _VFR-VN @ VN.OPEN-REFS @ 0<>
    _VFR-VN @ VN.DREFS @ 0<> OR IF EXIT THEN
    VFS-VNODE-SIZE _VFR-VN @ SWAP 0 FILL
    _VFR-V @ V.VFREE @ _VFR-VN @ VN.NEXT !
    _VFR-VN @ _VFR-V @ V.VFREE !
    _VFR-V @ V.VCOUNT DUP @ 1- SWAP ! ;

VARIABLE _VDF-D
VARIABLE _VDF-V
VARIABLE _VDF-DROP-LINK
VARIABLE _VDF-VN

: _VFS-DENTRY-RELEASE  ( dentry drop-link? vfs -- )
    _VDF-V ! _VDF-DROP-LINK ! _VDF-D !
    _VDF-D @ D.VNODE @ _VDF-VN !
    _VDF-D @ D.NAME @ _VFS-STR-RELEASE
    _VDF-DROP-LINK @ IF -1 _VDF-VN @ VN.NLINK +! THEN
    -1 _VDF-VN @ VN.DREFS +!
    _VDF-D @ _VFS-ZERO-INODE
    _VDF-V @ V.IFREE @ _VDF-D @ !
    _VDF-D @ _VDF-V @ V.IFREE !
    _VDF-VN @ _VDF-V @ _VFS-VNODE-MAYBE-FREE ;

: _VFS-INODE-FREE  ( inode vfs -- )
    >R TRUE R> _VFS-DENTRY-RELEASE ;

: _VFS-INODE-EVICT  ( inode vfs -- )
    >R FALSE R> _VFS-DENTRY-RELEASE ;

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
\  Ramdisk binding — ABI 1
\ =====================================================================
\
\  The ramdisk binding stores file content in binding-data cell 0
\  as a pointer to an arena-allocated buffer, and cell 1 as the
\  allocated capacity.  Reads/writes copy bytes from/to that buffer.
\
\  This binding is selected explicitly with VFS-RAM-BINDING.

: _VFS-RAM-MOUNT     ( vfs -- ior )         DROP 0 ;
: _VFS-RAM-UNMOUNT   ( flags vfs -- ior )   2DROP 0 ;
: _VFS-RAM-OPEN      ( inode vfs -- cookie ior )  2DROP 0 0 ;
: _VFS-RAM-RELEASE   ( cookie inode vfs -- ior )  2DROP DROP 0 ;

\ VFS-TRUNCATE publishes the requested logical size before dispatching to
\ a binding.  The RAM binding uses the saved old size to preserve/zero the
\ right byte ranges transactionally.  The public operation below owns these
\ variables; the VFS guard makes the one active truncate visible here.
VARIABLE _VTR-FD
VARIABLE _VTR-SIZE
VARIABLE _VTR-OLD-SIZE
VARIABLE _VTR-OLD-SIZE-HI

\ RAM binding-data is an allocation pair, never a logical-length pair.
\   IN.BDATA @       backing buffer (0 only when capacity is 0)
\   IN.BDATA 8 + @   allocated capacity in bytes
\ Arena allocations are eight-byte aligned, so rejecting a larger request
\ before the allocator's internal `7 +` also closes integer wraparound.
0x7FFFFFFFFFFFFFF8 CONSTANT _VFS-RAM-CAP-MAX
4096 CONSTANT _VFS-RAM-CAP-MIN

VARIABLE _VRB-PTR
VARIABLE _VRB-CAP
VARIABLE _VRB-VS
VARIABLE _VRB-BASE
VARIABLE _VRB-END
VARIABLE _VRB-BUF-END

: _VFS-RAM-SPAN?  ( address length -- flag )
    DUP 0<> IF OVER 0= IF 2DROP FALSE EXIT THEN THEN
    MSPAN-NONWRAPPING? ;

: _VFS-RAM-BUFFER?  ( pointer capacity vfs -- flag )
    _VRB-VS ! _VRB-CAP ! _VRB-PTR !
    _VRB-CAP @ 0< IF FALSE EXIT THEN
    _VRB-PTR @ 0= IF _VRB-CAP @ 0= EXIT THEN
    _VRB-CAP @ 0= IF FALSE EXIT THEN
    _VRB-PTR @ _VRB-CAP @ _VFS-RAM-SPAN? 0= IF FALSE EXIT THEN
    _VRB-VS @ V.ARENA @ A.BASE @ DUP 0= IF DROP FALSE EXIT THEN
    _VRB-BASE !
    _VRB-VS @ V.ARENA @ A.SIZE @ DUP 0< IF DROP FALSE EXIT THEN
    _VRB-BASE @ + DUP _VRB-BASE @ U< IF DROP FALSE EXIT THEN
    _VRB-END !
    _VRB-PTR @ _VRB-BASE @ U< IF FALSE EXIT THEN
    _VRB-PTR @ _VRB-CAP @ + _VRB-BUF-END !
    _VRB-BUF-END @ _VRB-END @ U> 0= ;

VARIABLE _VRG-REQUIRED
VARIABLE _VRG-PRESERVE
VARIABLE _VRG-IN
VARIABLE _VRG-VS
VARIABLE _VRG-PTR
VARIABLE _VRG-CAP
VARIABLE _VRG-NEW

: _VFS-RAM-NEXT-CAP  ( required current -- capacity|0 )
    _VRG-CAP ! _VRG-REQUIRED !
    _VRG-REQUIRED @ DUP 0< SWAP _VFS-RAM-CAP-MAX > OR IF 0 EXIT THEN
    _VRG-CAP @ DUP 0< SWAP _VFS-RAM-CAP-MAX > OR IF 0 EXIT THEN
    _VRG-CAP @ 0= IF
        _VFS-RAM-CAP-MIN
    ELSE
        _VRG-CAP @ _VFS-RAM-CAP-MAX 2/ > IF
            _VRG-REQUIRED @
        ELSE
            _VRG-CAP @ 2*
        THEN
    THEN
    _VRG-REQUIRED @ MAX
    DUP _VFS-RAM-CAP-MAX > IF DROP 0 EXIT THEN
    7 + -8 AND ;

\ Ensure a RAM inode has `required` bytes of backing capacity.  Growth is
\ copy-on-grow within the bump arena: the old allocation remains authoritative
\ until a fully zeroed replacement has preserved all live bytes.  Failed
\ allocation therefore changes neither pointer nor capacity nor content.
: _VFS-RAM-ENSURE  ( required preserve-u inode vfs -- ior )
    _VRG-VS ! _VRG-IN ! _VRG-PRESERVE ! _VRG-REQUIRED !
    _VRG-REQUIRED @ 0< _VRG-PRESERVE @ 0< OR IF -1 EXIT THEN
    _VRG-IN @ IN.BDATA @ _VRG-PTR !
    _VRG-IN @ IN.BDATA 8 + @ _VRG-CAP !
    _VRG-PTR @ _VRG-CAP @ _VRG-VS @ _VFS-RAM-BUFFER? 0= IF -1 EXIT THEN
    _VRG-PRESERVE @ _VRG-CAP @ > IF -1 EXIT THEN
    _VRG-REQUIRED @ _VRG-CAP @ <= IF 0 EXIT THEN
    _VRG-REQUIRED @ _VRG-CAP @ _VFS-RAM-NEXT-CAP
    DUP 0= IF DROP -1 EXIT THEN _VRG-NEW !
    _VRG-VS @ V.ARENA @ _VRG-NEW @ ARENA-ALLOT?
    IF DROP -1 EXIT THEN
    DUP _VRG-NEW @ 0 FILL
    _VRG-PTR @ ?DUP IF
        OVER _VRG-PRESERVE @ MOVE
    THEN
    DUP _VRG-IN @ IN.BDATA !
    _VRG-NEW @ _VRG-IN @ IN.BDATA 8 + !
    DROP 0 ;

\ Ramdisk READ — copy from arena buffer to user buffer.
VARIABLE _VRR-BUF
VARIABLE _VRR-LEN
VARIABLE _VRR-OFF
VARIABLE _VRR-IN

: _VFS-RAM-READ  ( buf len off inode vfs -- actual )
    _VRB-VS ! _VRR-IN ! _VRR-OFF ! _VRR-LEN ! _VRR-BUF !
    _VRR-LEN @ 0< _VRR-OFF @ 0< OR IF 0 EXIT THEN
    _VRR-LEN @ 0= IF 0 EXIT THEN
    _VRR-BUF @ _VRR-LEN @ _VFS-RAM-SPAN? 0= IF 0 EXIT THEN
    _VRR-IN @ IN.SIZE-LO @ DUP 0< IF DROP 0 EXIT THEN
    _VRR-IN @ IN.BDATA 8 + @ > IF 0 EXIT THEN
    _VRR-IN @ IN.BDATA @ _VRR-IN @ IN.BDATA 8 + @
        _VRB-VS @ _VFS-RAM-BUFFER? 0= IF 0 EXIT THEN
    _VRR-OFF @ _VRR-IN @ IN.SIZE-LO @ >= IF 0 EXIT THEN
    _VRR-IN @ IN.SIZE-LO @ _VRR-OFF @ - _VRR-LEN @ MIN _VRR-LEN !
    _VRR-IN @ IN.BDATA @ DUP 0= IF DROP 0 EXIT THEN
    _VRR-OFF @ + _VRR-BUF @ _VRR-LEN @ MOVE
    _VRR-LEN @ ;

\ Ramdisk WRITE — copy from user buffer to arena buffer.
VARIABLE _VRW-BUF
VARIABLE _VRW-LEN
VARIABLE _VRW-OFF
VARIABLE _VRW-IN
VARIABLE _VRW-VS
VARIABLE _VRW-END
VARIABLE _VRW-OLD-SIZE

: _VFS-RAM-WRITE  ( buf len off inode vfs -- actual )
    _VRW-VS ! _VRW-IN ! _VRW-OFF ! _VRW-LEN ! _VRW-BUF !
    _VRW-LEN @ 0< _VRW-OFF @ 0< OR IF 0 EXIT THEN
    _VRW-LEN @ 0= IF 0 EXIT THEN
    _VRW-BUF @ _VRW-LEN @ _VFS-RAM-SPAN? 0= IF 0 EXIT THEN
    _VRW-OFF @ _VRW-LEN @ + DUP _VRW-END !
    _VRW-OFF @ U< IF 0 EXIT THEN
    _VRW-IN @ IN.SIZE-LO @ DUP _VRW-OLD-SIZE !
    DUP 0< IF DROP 0 EXIT THEN
    _VRW-IN @ IN.BDATA 8 + @ > IF 0 EXIT THEN
    _VRW-IN @ IN.BDATA @ _VRW-IN @ IN.BDATA 8 + @
        _VRW-VS @ _VFS-RAM-BUFFER? 0= IF 0 EXIT THEN
    _VRW-END @ _VRW-OLD-SIZE @ _VRW-IN @ _VRW-VS @ _VFS-RAM-ENSURE
    IF 0 EXIT THEN
    \ The zero-tail invariant makes ordinary contiguous extension safe;
    \ explicitly clear a sparse gap because shrink/regrow may reuse capacity.
    _VRW-OFF @ _VRW-OLD-SIZE @ > IF
        _VRW-IN @ IN.BDATA @ _VRW-OLD-SIZE @ +
        _VRW-OFF @ _VRW-OLD-SIZE @ - 0 FILL
    THEN
    _VRW-BUF @ _VRW-IN @ IN.BDATA @ _VRW-OFF @ + _VRW-LEN @ MOVE
    _VRW-LEN @ ;

' _VFS-RAM-READ CONSTANT _VFS-RAM-READ-RAW
' _VFS-RAM-WRITE CONSTANT _VFS-RAM-WRITE-RAW

: _VFS-RAM-READ  ( buf len off inode vfs -- actual ior )
    _VFS-RAM-READ-RAW EXECUTE 0 ;

VARIABLE _VRWC-LEN
: _VFS-RAM-WRITE  ( buf len off inode vfs -- actual ior )
    3 PICK _VRWC-LEN !
    _VFS-RAM-WRITE-RAW EXECUTE
    DUP 0= _VRWC-LEN @ 0> AND IF VFS-E-NOMEM ELSE 0 THEN ;

: _VFS-RAM-READDIR   ( inode vfs -- ior )  2DROP 0 ;
: _VFS-RAM-SYNCFS    ( vfs -- ior )        DROP 0 ;
: _VFS-RAM-FSYNC     ( inode vfs -- ior )  2DROP 0 ;
: _VFS-RAM-GETATTR   ( inode vfs -- ior )  2DROP 0 ;

VARIABLE _VRCI-IN
VARIABLE _VRCI-V
: _VFS-RAM-CREATE    ( inode vfs -- ior )
    _VRCI-V ! _VRCI-IN !
    _VRCI-IN @ IN.BID @ 0= IF
        _VRCI-V @ V.NEXT-BID @ DUP _VRCI-IN @ IN.BID !
        1+ _VRCI-V @ V.NEXT-BID !
    THEN
    VFS-IF-PINNED _VRCI-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    0 ;

: _VFS-RAM-UNLINK    ( inode vfs -- ior )  2DROP 0 ;
: _VFS-RAM-RENAME    ( new-a new-u inode new-parent victim flags vfs -- ior )
    2DROP 2DROP 2DROP DROP 0 ;
: _VFS-RAM-LINK      ( new-dentry target vfs -- ior )
    2DROP DROP 0 ;

VARIABLE _VRT-IN
VARIABLE _VRT-VS
VARIABLE _VRT-NEW-SIZE
VARIABLE _VRT-KEEP

: _VFS-RAM-TRUNCATE  ( inode vfs -- ior )
    _VRT-VS ! _VRT-IN !
    _VRT-IN @ IN.SIZE-LO @ _VRT-NEW-SIZE !
    _VRT-NEW-SIZE @ 0< _VTR-OLD-SIZE @ 0< OR IF -1 EXIT THEN
    _VRT-IN @ IN.BDATA @ _VRT-IN @ IN.BDATA 8 + @
        _VRT-VS @ _VFS-RAM-BUFFER? 0= IF -1 EXIT THEN
    _VTR-OLD-SIZE @ _VRT-IN @ IN.BDATA 8 + @ > IF -1 EXIT THEN
    _VRT-NEW-SIZE @ _VTR-OLD-SIZE @ MIN _VRT-KEEP !
    _VRT-NEW-SIZE @ _VRT-KEEP @ _VRT-IN @ _VRT-VS @ _VFS-RAM-ENSURE
    IF -1 EXIT THEN
    _VRT-IN @ IN.BDATA @ ?DUP IF
        _VRT-NEW-SIZE @ +
        _VRT-IN @ IN.BDATA 8 + @ _VRT-NEW-SIZE @ - 0 FILL
    THEN
    0 ;

' _VFS-RAM-TRUNCATE CONSTANT _VFS-RAM-TRUNCATE-RAW
: _VFS-RAM-TRUNCATE  ( inode vfs -- ior )
    _VFS-RAM-TRUNCATE-RAW EXECUTE IF VFS-E-NOMEM ELSE 0 THEN ;

VFS-CAP-MOUNT VFS-CAP-UNMOUNT OR
VFS-CAP-READDIR OR VFS-CAP-OPEN OR VFS-CAP-RELEASE OR
VFS-CAP-READ OR VFS-CAP-WRITE OR VFS-CAP-CREATE OR VFS-CAP-MKDIR OR
VFS-CAP-UNLINK OR VFS-CAP-RMDIR OR VFS-CAP-RENAME OR
VFS-CAP-TRUNCATE OR VFS-CAP-GETATTR OR VFS-CAP-LINK OR
VFS-CAP-SYNCFS OR VFS-CAP-FSYNC OR VFS-CAP-ATOMIC-RENAME OR
VFS-CAP-CROSSDIR-RENAME OR VFS-CAP-RENAME-REPLACE OR
VFS-CAP-STABLE-HANDLES OR CONSTANT VFS-RAM-CAPS

CREATE VFS-RAM-OPS  VFS-OPS-SIZE ALLOT
VFS-RAM-OPS VFS-OPS-SIZE 0 FILL
' _VFS-RAM-MOUNT     VFS-RAM-OPS VFS-OP-MOUNT    CELLS + !
' _VFS-RAM-UNMOUNT   VFS-RAM-OPS VFS-OP-UNMOUNT  CELLS + !
' _VFS-RAM-READDIR   VFS-RAM-OPS VFS-OP-READDIR  CELLS + !
' _VFS-RAM-OPEN      VFS-RAM-OPS VFS-OP-OPEN     CELLS + !
' _VFS-RAM-RELEASE   VFS-RAM-OPS VFS-OP-RELEASE  CELLS + !
' _VFS-RAM-READ      VFS-RAM-OPS VFS-OP-READ     CELLS + !
' _VFS-RAM-WRITE     VFS-RAM-OPS VFS-OP-WRITE    CELLS + !
' _VFS-RAM-CREATE    VFS-RAM-OPS VFS-OP-CREATE   CELLS + !
' _VFS-RAM-CREATE    VFS-RAM-OPS VFS-OP-MKDIR    CELLS + !
' _VFS-RAM-UNLINK    VFS-RAM-OPS VFS-OP-UNLINK   CELLS + !
' _VFS-RAM-UNLINK    VFS-RAM-OPS VFS-OP-RMDIR    CELLS + !
' _VFS-RAM-RENAME    VFS-RAM-OPS VFS-OP-RENAME   CELLS + !
' _VFS-RAM-TRUNCATE  VFS-RAM-OPS VFS-OP-TRUNCATE CELLS + !
' _VFS-RAM-GETATTR   VFS-RAM-OPS VFS-OP-GETATTR  CELLS + !
' _VFS-RAM-LINK      VFS-RAM-OPS VFS-OP-LINK     CELLS + !
' _VFS-RAM-SYNCFS    VFS-RAM-OPS VFS-OP-SYNCFS   CELLS + !
' _VFS-RAM-FSYNC     VFS-RAM-OPS VFS-OP-FSYNC    CELLS + !

CREATE VFS-RAM-BINDING
VFS-BINDING-MAGIC ,
VFS-BINDING-ABI-MAJOR ,
VFS-BINDING-ABI-MINOR ,
VFS-BINDING-DESC-SIZE ,
VFS-OPS-SIZE ,
VFS-RAM-CAPS ,
VFS-BF-STABLE-IDS ,
VFS-RAM-OPS ,
0 , 0 ,

\ =====================================================================
\  VFS-NEW — Create a new VFS instance
\ =====================================================================
\
\  ( arena binding volume -- vfs ior )
\
\  Allocates from the arena:
\    1. VFS descriptor (208 bytes)
\    2. Initial inode slab page (_VFS-SLAB-SIZE bytes)
\    3. FD pool (256 × 64 = 16384 bytes)
\    4. Fixed string pool plus vnode/file capacity
\  Creates root directory inode (type VFS-T-DIR, name "/").

VARIABLE _VN-AR
VARIABLE _VN-BINDING
VARIABLE _VN-VOLUME
VARIABLE _VN-VFS
VARIABLE _VN-IOR
VARIABLE _VN-ENTRY-PTR
VARIABLE _VN-POOL-SIZE

: _VFS-NEW-ROLLBACK  ( -- vfs ior )
    _VN-ENTRY-PTR @ _VN-AR @ A.PTR !
    0 VFS-E-NOMEM ;

: VFS-NEW  ( arena binding volume -- vfs ior )
    _VN-VOLUME ! _VN-BINDING ! _VN-AR !
    _VN-BINDING @ VFS-BINDING-VALID? 0= IF
        0 VFS-E-INVALID EXIT
    THEN
    _VN-BINDING @ VB.FLAGS @ VFS-BF-NEEDS-VOLUME AND
    _VN-VOLUME @ 0= AND IF 0 VFS-E-NOVOLUME EXIT THEN
    _VN-VOLUME @ ?DUP IF
        DUP VOL-VALID? 0= IF DROP 0 VFS-E-INVALID EXIT THEN
        VOL-STALE? IF 0 VFS-E-STALE EXIT THEN
    THEN
    VFS-CAP-MOUNT _VN-BINDING @ VB.CAPS @ AND 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    VFS-CAP-UNMOUNT _VN-BINDING @ VB.CAPS @ AND 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VN-AR @ A.PTR @ _VN-ENTRY-PTR !

    \ 1. Allocate descriptor
    _VN-AR @ VFS-DESC-SIZE ARENA-ALLOT?
    IF DROP _VFS-NEW-ROLLBACK EXIT THEN _VN-VFS !

    \ Store binding, explicit attachment, and arena.
    _VN-BINDING @ _VN-VFS @ V.BINDING !
    _VN-AR @   _VN-VFS @ V.ARENA !
    0          _VN-VFS @ V.FLAGS !
    0          _VN-VFS @ V.BCTX !
    _VN-VOLUME @ _VN-VFS @ V.VOLUME !
    _VN-VOLUME @ ?DUP IF
        DUP VOL.COOKIE _VN-VFS @ V.VOL-COOKIE !
        VOL.MEDIA-GEN _VN-VFS @ V.MEDIA-GEN !
    ELSE
        0 _VN-VFS @ V.VOL-COOKIE !
        0 _VN-VFS @ V.MEDIA-GEN !
    THEN
    0 _VN-VFS @ V.LAST-IOR !
    VFS-L-NEW _VN-VFS @ V.LIFECYCLE !
    0 _VN-VFS @ V.OPEN-COUNT !
    0 _VN-VFS @ V.VFREE !
    0 _VN-VFS @ V.VCOUNT !
    2 _VN-VFS @ V.NEXT-BID !
    _VN-BINDING @ VB.FLAGS @ VFS-BF-READ-ONLY AND IF
        VFS-F-RO _VN-VFS @ V.FLAGS !
    THEN
    _VN-VOLUME @ ?DUP IF
        VOL.FLAGS VOL-F-READONLY AND IF
            VFS-F-RO _VN-VFS @ V.FLAGS DUP @ ROT OR SWAP !
        THEN
    THEN

    \ 2. Allocate initial inode slab page
    _VN-AR @ _VFS-SLAB-SIZE ARENA-ALLOT?
    IF DROP _VFS-NEW-ROLLBACK EXIT THEN
    _VN-VFS @ V.ISLAB !
    0 _VN-VFS @ V.ISLAB @ !
    0  _VN-VFS @ V.IFREE !
    0  _VN-VFS @ V.ICOUNT !
    256  _VN-VFS @ V.IHWM !       \ default eviction threshold

    \ Init slab free-list
    _VN-VFS @ V.ISLAB @  _VN-VFS @  _VFS-SLAB-INIT

    \ 3. Allocate FD pool
    _VN-AR @ _VFS-FD-DEFAULT VFS-FD-SIZE * ARENA-ALLOT?
    IF DROP _VFS-NEW-ROLLBACK EXIT THEN
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
    DUP _VN-POOL-SIZE !
    _VN-AR @ SWAP ARENA-ALLOT?
    IF DROP _VFS-NEW-ROLLBACK EXIT THEN    ( str-base )
    DUP  _VN-VFS @ V.STR-BASE !
    DUP  _VN-VFS @ V.STR-PTR !
    _VN-POOL-SIZE @ + _VN-VFS @ V.STR-END !

    \ 5. Create root directory inode
    VFS-T-DIR  _VN-VFS @  _VFS-INODE-ALLOC  ( root-inode )
    DUP 0= IF DROP _VFS-NEW-ROLLBACK EXIT THEN
    DUP  _VN-VFS @ V.ROOT !
    DUP  _VN-VFS @ V.CWD !
    \ Name = "/"
    S" /"  _VN-VFS @  _VFS-STR-ALLOC
    DUP 0= IF
        DROP DROP _VFS-NEW-ROLLBACK EXIT
    THEN
    OVER IN.NAME !
    \ Root has no parent
    0  OVER IN.PARENT !
    1  OVER IN.BID !
    \ Mark children not loaded (binding will populate later)
    VFS-IF-PINNED OVER IN.FLAGS !
    DROP

    \ Increment inode count
    _VN-VFS @ V.ICOUNT @  1+  _VN-VFS @ V.ICOUNT !

    \ Mount only after a complete core descriptor exists.  Failed mount
    \ leaves the returned VFS inspectable but not usable.
    _VN-VFS @ VFS-OP-MOUNT _VN-VFS @ _VFS-XT EXECUTE _VN-IOR !
    _VN-IOR @ IF
        _VN-IOR @ _VN-VFS @ V.LAST-IOR !
        _VN-VFS @ _VN-IOR @ EXIT
    THEN
    VFS-L-MOUNTED _VN-VFS @ V.LIFECYCLE !
    _VN-VFS @ VFS-USE
    _VN-VFS @ 0 ;

\ =====================================================================
\  VFS-DESTROY — Tear down a VFS instance
\ =====================================================================
\
\  ( vfs -- )
\
\  Force-unmounts through the binding, then destroys the arena.
\  All dentries, vnodes, FDs, strings, and buffers are reclaimed in bulk.

1 CONSTANT VFS-UNMOUNT-F-FORCE

VARIABLE _VUM-FLAGS
VARIABLE _VUM-V

: VFS-UNMOUNT  ( flags vfs -- ior )
    _VUM-V ! _VUM-FLAGS !
    _VUM-V @ V.LIFECYCLE @ VFS-L-UNMOUNTED = IF 0 EXIT THEN
    _VUM-V @ V.LIFECYCLE @ VFS-L-STALE = IF VFS-E-STALE EXIT THEN
    _VUM-V @ V.LIFECYCLE @ VFS-L-MOUNTED <> IF VFS-E-BUSY EXIT THEN
    _VUM-V @ V.OPEN-COUNT @ 0<>
    _VUM-FLAGS @ VFS-UNMOUNT-F-FORCE AND 0= AND IF VFS-E-BUSY EXIT THEN
    \ Never dispatch through a closed, rebound, or generation-drifted volume.
    \ Checked operations latch the same terminal state through _VFS-READY.
    _VUM-V @ _VFS-ATTACHMENT-CURRENT? 0= IF
        VFS-L-STALE _VUM-V @ V.LIFECYCLE !
        VFS-E-STALE _VUM-V @ _VFS-RESULT EXIT
    THEN
    VFS-L-UNMOUNTING _VUM-V @ V.LIFECYCLE !
    _VUM-FLAGS @ _VUM-V @
    VFS-OP-UNMOUNT _VUM-V @ _VFS-XT EXECUTE
    DUP IF
        DUP VFS-IOR-REASON VFS-R-STALE =
        _VUM-V @ V.LIFECYCLE @ VFS-L-STALE = OR IF
            VFS-L-STALE _VUM-V @ V.LIFECYCLE !
        ELSE
            VFS-L-MOUNTED _VUM-V @ V.LIFECYCLE !
        THEN
        _VUM-V @ _VFS-RESULT EXIT
    THEN
    VFS-L-UNMOUNTED _VUM-V @ V.LIFECYCLE !
    _VUM-V @ _VFS-RESULT ;

: VFS-DESTROY  ( vfs -- )
    DUP _VFS-CUR @ = IF 0 _VFS-CUR ! THEN
    DUP >R VFS-UNMOUNT-F-FORCE SWAP VFS-UNMOUNT DROP
    R> V.ARENA @ ARENA-DESTROY ;

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
VARIABLE _VFS-LOOKUP-XT  \ filled once VFS-LOOKUP exists
: _VFS-MAYBE-EVICT  ( vfs -- )
    DUP V.ICOUNT @
    OVER V.IHWM @  > IF
        _VFS-EVICT-XT @ EXECUTE
    ELSE  DROP  THEN ;

\ -- Helper: ensure children are loaded --
: _VFS-ENSURE-CHILDREN?  ( dir-inode vfs -- ior )
    OVER IN.FLAGS @ VFS-IF-CHILDREN AND IF 2DROP 0 EXIT THEN
    DUP _VFS-READY ?DUP IF >R 2DROP R> EXIT THEN
    VFS-OP-READDIR OVER _VFS-HAS-OP? 0= IF
        2DROP VFS-E-UNSUPPORTED EXIT
    THEN
    2DUP VFS-OP-READDIR OVER _VFS-XT EXECUTE
    ?DUP IF >R 2DROP R> EXIT THEN
    DROP IN.FLAGS DUP @ VFS-IF-CHILDREN OR SWAP ! 0 ;

: _VFS-ENSURE-CHILDREN  ( dir-inode vfs -- )
    _VFS-ENSURE-CHILDREN? ?DUP IF THROW THEN ;

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

: _VFS-DENTRY-OWNED?  ( dentry vfs -- flag )
    OVER 0= IF 2DROP FALSE EXIT THEN
    SWAP D.OWNER @ = ;

VARIABLE _VRCF-A
VARIABLE _VRCF-U
VARIABLE _VRCF-DIR
VARIABLE _VRCF-V

: _VFS-RESOLVE-CHILD  ( c-addr u dir vfs -- child | 0 )
    _VRCF-V ! _VRCF-DIR ! _VRCF-U ! _VRCF-A !
    _VRCF-A @ _VRCF-U @ _VRCF-DIR @ _VFS-FIND-CHILD
    DUP IF EXIT THEN DROP
    VFS-OP-LOOKUP _VRCF-V @ _VFS-HAS-OP? IF
        _VRCF-A @ _VRCF-U @ _VRCF-DIR @ _VRCF-V @
        _VFS-LOOKUP-XT @ EXECUTE
        DUP IF
            DUP VFS-IOR-REASON VFS-R-NOENT = IF 2DROP 0 EXIT THEN
            NIP THROW
        THEN
        DROP EXIT
    THEN
    _VRCF-DIR @ _VRCF-V @ _VFS-ENSURE-CHILDREN
    _VRCF-A @ _VRCF-U @ _VRCF-DIR @ _VFS-FIND-CHILD ;

\ -- Path resolution temporaries --
VARIABLE _VR-S       \ scan pointer into path string
VARIABLE _VR-E       \ end of path string
VARIABLE _VR-V       \ vfs
VARIABLE _VR-IN      \ current inode
VARIABLE _VR-CS      \ component start
VARIABLE _VR-CL      \ component length
VARIABLE _VR-IOR     \ checked resolver's structural failure

: VFS-RESOLVE  ( c-addr u vfs -- inode | 0 )
    _VR-V !
    0 _VR-IOR !
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
                    VFS-E-NOTDIR _VR-IOR ! 0 EXIT
                THEN
                _VR-CS @ _VR-CL @ _VR-IN @ _VR-V @ _VFS-RESOLVE-CHILD
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
                _VR-IN @ IN.TYPE @ VFS-T-DIR <> IF
                    VFS-E-NOTDIR _VR-IOR ! 0 EXIT
                THEN
                _VR-CS @ _VR-CL @ _VR-IN @ _VR-V @ _VFS-RESOLVE-CHILD
                DUP 0= IF  EXIT  THEN  _VR-IN !
            THEN ELSE
                \ two chars, first not dot — normal lookup
                _VR-IN @ IN.TYPE @ VFS-T-DIR <> IF
                    VFS-E-NOTDIR _VR-IOR ! 0 EXIT
                THEN
                _VR-CS @ _VR-CL @ _VR-IN @ _VR-V @ _VFS-RESOLVE-CHILD
                DUP 0= IF  EXIT  THEN  _VR-IN !
            THEN
        ELSE
            \ Normal component (3+ chars or 1-2 non-special)
            _VR-IN @ IN.TYPE @ VFS-T-DIR <> IF
                VFS-E-NOTDIR _VR-IOR ! 0 EXIT
            THEN
            _VR-CS @ _VR-CL @ _VR-IN @ _VR-V @ _VFS-RESOLVE-CHILD
            DUP 0= IF  EXIT  THEN  _VR-IN !
        THEN THEN THEN
    REPEAT
    _VR-IN @ ;

VARIABLE _VRQ-A
VARIABLE _VRQ-U
VARIABLE _VRQ-V
VARIABLE _VRQ-IN

: _VFS-RESOLVE?-BODY  ( -- )
    _VRQ-A @ _VRQ-U @ _VRQ-V @ VFS-RESOLVE _VRQ-IN ! ;

: VFS-RESOLVE?  ( c-addr u vfs -- inode ior )
    _VRQ-V ! _VRQ-U ! _VRQ-A !
    _VRQ-U @ 0< IF 0 VFS-E-INVALID EXIT THEN
    _VRQ-U @ 0> IF
        _VRQ-A @ 0= IF 0 VFS-E-INVALID EXIT THEN
        _VRQ-A @ _VRQ-U @ MSPAN-NONWRAPPING? 0= IF
            0 VFS-E-INVALID EXIT
        THEN
    THEN
    _VRQ-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    0 _VRQ-IN !
    ['] _VFS-RESOLVE?-BODY CATCH ?DUP IF 0 SWAP EXIT THEN
    _VRQ-IN @ DUP 0= IF
        DROP 0 _VR-IOR @ DUP 0= IF DROP VFS-E-NOENT THEN
    ELSE 0 THEN ;

\ =====================================================================
\  VFS-OPEN / VFS-CLOSE
\ =====================================================================

VARIABLE _VOQ-A
VARIABLE _VOQ-U
VARIABLE _VOQ-FLAGS
VARIABLE _VOQ-V
VARIABLE _VOQ-IN
VARIABLE _VOQ-FD
VARIABLE _VOQ-COOKIE

: VFS-OPEN?  ( c-addr u flags vfs -- fd ior )
    _VOQ-V ! _VOQ-FLAGS ! _VOQ-U ! _VOQ-A !
    _VOQ-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VOQ-FLAGS @ VFS-FF-READ VFS-FF-WRITE OR VFS-FF-APPEND OR
    INVERT AND IF 0 VFS-E-INVALID EXIT THEN
    _VOQ-FLAGS @ VFS-FF-READ VFS-FF-WRITE OR AND 0= IF
        0 VFS-E-INVALID EXIT
    THEN
    _VOQ-FLAGS @ VFS-FF-WRITE AND IF
        _VOQ-V @ V.FLAGS @ VFS-F-RO AND IF 0 VFS-E-READONLY EXIT THEN
    THEN
    _VOQ-A @ _VOQ-U @ _VOQ-V @ VFS-RESOLVE?
    DUP IF NIP 0 SWAP EXIT THEN DROP _VOQ-IN !
    _VOQ-FLAGS @ VFS-FF-APPEND AND IF
        _VOQ-IN @ IN.SIZE-HI @ 0<> _VOQ-IN @ IN.SIZE-LO @ 0< OR IF
            0 VFS-E-OVERFLOW EXIT
        THEN
    THEN
    VFS-OP-OPEN _VOQ-V @ _VFS-HAS-OP? 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VOQ-V @ _VFS-FD-ALLOC DUP 0= IF 0 VFS-E-NOMEM EXIT THEN _VOQ-FD !
    _VOQ-IN @ _VOQ-V @
    VFS-OP-OPEN _VOQ-V @ _VFS-XT EXECUTE
    DUP IF
        NIP _VOQ-FD @ _VOQ-V @ _VFS-FD-FREE
        0 SWAP EXIT
    THEN
    DROP _VOQ-COOKIE !
    _VOQ-IN @ _VOQ-FD @ FD.INODE !
    _VOQ-FLAGS @ VFS-FF-APPEND AND IF
        _VOQ-IN @ IN.SIZE-LO @
    ELSE
        0
    THEN _VOQ-FD @ FD.CUR-LO !
    0 _VOQ-FD @ FD.CUR-HI !
    _VOQ-FLAGS @ _VOQ-FD @ FD.FLAGS !
    _VOQ-V @ _VOQ-FD @ FD.VFS !
    _VOQ-COOKIE @ _VOQ-FD @ FD.COOKIE !
    _VOQ-V @ V.MEDIA-GEN @ _VOQ-FD @ FD.GEN !
    1 _VOQ-IN @ D.VNODE @ VN.OPEN-REFS +!
    1 _VOQ-V @ V.OPEN-COUNT +!
    _VOQ-FD @ 0 ;

: VFS-OPEN  ( c-addr u -- fd | 0 )
    VFS-CUR DUP V.FLAGS @ VFS-F-RO AND IF
        VFS-FF-READ
    ELSE
        VFS-FF-READ VFS-FF-WRITE OR
    THEN SWAP VFS-OPEN?
    DUP 0= IF DROP EXIT THEN
    DUP VFS-IOR-REASON _VFS-R-NOENT = IF 2DROP 0 EXIT THEN
    NIP THROW ;

VARIABLE _VDFQ-D
VARIABLE _VDFQ-V

: _VFS-DENTRY-HAS-FD?  ( dentry vfs -- flag )
    _VDFQ-V ! _VDFQ-D !
    _VDFQ-V @ V.FDPOOL @
    _VDFQ-V @ V.FDMAX @ 0 DO
        DUP I VFS-FD-SIZE * + FD.INODE @ _VDFQ-D @ = IF
            DROP TRUE UNLOOP EXIT
        THEN
    LOOP
    DROP FALSE ;

VARIABLE _VCQ-FD
VARIABLE _VCQ-V
VARIABLE _VCQ-IN
VARIABLE _VCQ-IOR

: VFS-CLOSE?  ( fd -- ior )
    DUP 0= IF DROP VFS-E-BADF EXIT THEN _VCQ-FD !
    _VCQ-FD @ FD.VFS @ DUP 0= IF DROP VFS-E-BADF EXIT THEN _VCQ-V !
    _VCQ-FD @ FD.INODE @ DUP 0= IF DROP VFS-E-BADF EXIT THEN _VCQ-IN !
    0 _VCQ-IOR !
    VFS-OP-RELEASE _VCQ-V @ _VFS-HAS-OP? IF
        _VCQ-FD @ FD.COOKIE @ _VCQ-IN @ _VCQ-V @
        VFS-OP-RELEASE _VCQ-V @ _VFS-XT EXECUTE _VCQ-IOR !
    THEN
    -1 _VCQ-IN @ D.VNODE @ VN.OPEN-REFS +!
    -1 _VCQ-V @ V.OPEN-COUNT +!
    _VCQ-FD @ _VCQ-V @ _VFS-FD-FREE
    _VCQ-IN @ D.FLAGS @ VFS-DF-UNLINKED AND IF
        _VCQ-IN @ _VCQ-V @ _VFS-DENTRY-HAS-FD? 0= IF
            _VCQ-IN @ FALSE _VCQ-V @ _VFS-DENTRY-RELEASE
        THEN
    THEN
    _VCQ-IOR @ ;

: VFS-CLOSE  ( fd -- )
    VFS-CLOSE? ?DUP IF THROW THEN ;

\ =====================================================================
\  VFS-READ / VFS-WRITE
\ =====================================================================
\
\  Canonical calls return both progress and a structured ior.  Legal partial
\  progress advances the cursor even when the same call reports an error.

VARIABLE _VRD-FD
VARIABLE _VRD-ACT
VARIABLE _VRD-IOR
VARIABLE _VRD-BUF
VARIABLE _VRD-LEN
VARIABLE _VRD-V

: VFS-READ?  ( buf len fd -- actual ior )
    _VRD-FD ! _VRD-LEN ! _VRD-BUF !
    _VRD-FD @ 0= IF 0 VFS-E-BADF EXIT THEN
    _VRD-FD @ FD.VFS @ DUP 0= IF DROP 0 VFS-E-BADF EXIT THEN _VRD-V !
    _VRD-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VRD-FD @ FD.FLAGS @ VFS-FF-READ AND 0= IF 0 VFS-E-BADF EXIT THEN
    _VRD-FD @ FD.INODE @ IN.TYPE @ VFS-T-DIR = IF 0 VFS-E-ISDIR EXIT THEN
    _VRD-FD @ FD.CUR-HI @ 0<> _VRD-FD @ FD.CUR-LO @ 0< OR IF
        0 VFS-E-OVERFLOW EXIT
    THEN
    _VRD-LEN @ 0< IF 0 VFS-E-INVALID EXIT THEN
    _VRD-LEN @ 0> _VRD-BUF @ 0= AND IF 0 VFS-E-INVALID EXIT THEN
    _VRD-FD @ FD.GEN @ _VRD-V @ V.MEDIA-GEN @ <> IF 0 VFS-E-STALE EXIT THEN
    VFS-OP-READ _VRD-V @ _VFS-HAS-OP? 0= IF 0 VFS-E-UNSUPPORTED EXIT THEN
    _VRD-FD @ FD.CUR-LO @ _VRD-LEN @ +
    DUP 0< IF DROP 0 VFS-E-OVERFLOW EXIT THEN
    _VRD-FD @ FD.CUR-LO @ U< IF 0 VFS-E-OVERFLOW EXIT THEN
    _VRD-BUF @ _VRD-LEN @
    _VRD-FD @ FD.CUR-LO @
    _VRD-FD @ FD.INODE @
    _VRD-V @
    VFS-OP-READ _VRD-V @ _VFS-XT EXECUTE
    _VRD-IOR ! _VRD-ACT !
    _VRD-ACT @ 0< _VRD-ACT @ _VRD-LEN @ > OR IF
        0 VFS-E-CORRUPT EXIT
    THEN
    _VRD-FD @ FD.CUR-LO @  _VRD-ACT @ +
    _VRD-FD @ FD.CUR-LO !
    _VRD-IOR @ _VRD-V @ _VFS-RESULT DROP
    _VRD-ACT @ _VRD-IOR @ ;

: VFS-READ  ( buf len fd -- actual )
    VFS-READ? ?DUP IF THROW THEN ;

VARIABLE _VWR-FD
VARIABLE _VWR-ACT
VARIABLE _VWR-IOR
VARIABLE _VWR-BUF
VARIABLE _VWR-LEN
VARIABLE _VWR-V

: VFS-WRITE?  ( buf len fd -- actual ior )
    _VWR-FD ! _VWR-LEN ! _VWR-BUF !
    _VWR-FD @ 0= IF 0 VFS-E-BADF EXIT THEN
    _VWR-FD @ FD.VFS @ DUP 0= IF DROP 0 VFS-E-BADF EXIT THEN _VWR-V !
    _VWR-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VWR-FD @ FD.FLAGS @ VFS-FF-WRITE AND 0= IF 0 VFS-E-BADF EXIT THEN
    _VWR-FD @ FD.INODE @ IN.TYPE @ VFS-T-DIR = IF 0 VFS-E-ISDIR EXIT THEN
    _VWR-FD @ FD.CUR-HI @ 0<> _VWR-FD @ FD.CUR-LO @ 0< OR IF
        0 VFS-E-OVERFLOW EXIT
    THEN
    _VWR-V @ V.FLAGS @ VFS-F-RO AND IF 0 VFS-E-READONLY EXIT THEN
    _VWR-LEN @ 0< IF 0 VFS-E-INVALID EXIT THEN
    _VWR-LEN @ 0> _VWR-BUF @ 0= AND IF 0 VFS-E-INVALID EXIT THEN
    _VWR-FD @ FD.GEN @ _VWR-V @ V.MEDIA-GEN @ <> IF 0 VFS-E-STALE EXIT THEN
    VFS-OP-WRITE _VWR-V @ _VFS-HAS-OP? 0= IF 0 VFS-E-UNSUPPORTED EXIT THEN
    _VWR-FD @ FD.FLAGS @ VFS-FF-APPEND AND IF
        _VWR-FD @ FD.INODE @ IN.SIZE-HI @ 0<>
        _VWR-FD @ FD.INODE @ IN.SIZE-LO @ 0< OR IF
            0 VFS-E-OVERFLOW EXIT
        THEN
        _VWR-FD @ FD.INODE @ IN.SIZE-LO @ _VWR-FD @ FD.CUR-LO !
    THEN
    _VWR-FD @ FD.CUR-LO @ _VWR-LEN @ +
    DUP 0< IF DROP 0 VFS-E-OVERFLOW EXIT THEN
    _VWR-FD @ FD.CUR-LO @ U< IF 0 VFS-E-OVERFLOW EXIT THEN
    _VWR-BUF @ _VWR-LEN @
    _VWR-FD @ FD.CUR-LO @
    _VWR-FD @ FD.INODE @
    _VWR-V @
    VFS-OP-WRITE _VWR-V @ _VFS-XT EXECUTE
    _VWR-IOR ! _VWR-ACT !
    _VWR-ACT @ 0< _VWR-ACT @ _VWR-LEN @ > OR IF
        0 VFS-E-CORRUPT EXIT
    THEN
    _VWR-ACT @ 0> IF
        _VWR-FD @ FD.CUR-LO @ _VWR-ACT @ +
        _VWR-FD @ FD.CUR-LO !
        _VWR-FD @ FD.CUR-LO @
        _VWR-FD @ FD.INODE @ IN.SIZE-LO @
        > IF
            _VWR-FD @ FD.CUR-LO @
            _VWR-FD @ FD.INODE @ IN.SIZE-LO !
            VFS-IF-DIRTY
            _VWR-FD @ FD.INODE @ IN.FLAGS DUP @ ROT OR SWAP !
            VFS-F-DIRTY _VWR-V @ V.FLAGS DUP @ ROT OR SWAP !
        THEN
    THEN
    _VWR-IOR @ _VWR-V @ _VFS-RESULT DROP
    _VWR-ACT @ _VWR-IOR @ ;

: VFS-WRITE  ( buf len fd -- actual )
    VFS-WRITE? ?DUP IF THROW THEN ;

\ VFS-READ-EXACT / VFS-WRITE-EXACT
\   Complete a requested transfer across legal partial progress.  A zero,
\   negative, or overlong result before completion fails structurally.  The
\   descriptor cursor remains advanced by any progress made before failure.

VARIABLE _VRE-A
VARIABLE _VRE-REM
VARIABLE _VRE-FD
VARIABLE _VRE-ACT
VARIABLE _VRE-POS

: VFS-READ-EXACT  ( buf len fd -- ior )
    _VRE-FD ! _VRE-REM ! _VRE-A !
    _VRE-REM @ 0< IF VFS-E-INVALID EXIT THEN
    _VRE-REM @ 0> _VRE-A @ 0= AND IF VFS-E-INVALID EXIT THEN
    BEGIN _VRE-REM @ 0> WHILE
        _VRE-FD @ FD.CUR-LO @ _VRE-POS !
        _VRE-A @ _VRE-REM @ _VRE-FD @ VFS-READ?
        DUP IF NIP EXIT THEN DROP DUP _VRE-ACT !
        DUP 0= OVER 0< OR SWAP _VRE-REM @ > OR IF
            _VRE-POS @ _VRE-FD @ FD.CUR-LO ! VFS-E-IO EXIT THEN
        _VRE-ACT @ _VRE-A +!
        _VRE-ACT @ NEGATE _VRE-REM +!
    REPEAT
    0 ;

VARIABLE _VWE-A
VARIABLE _VWE-REM
VARIABLE _VWE-FD
VARIABLE _VWE-ACT
VARIABLE _VWE-POS

: VFS-WRITE-EXACT  ( buf len fd -- ior )
    _VWE-FD ! _VWE-REM ! _VWE-A !
    _VWE-REM @ 0< IF VFS-E-INVALID EXIT THEN
    _VWE-REM @ 0> _VWE-A @ 0= AND IF VFS-E-INVALID EXIT THEN
    BEGIN _VWE-REM @ 0> WHILE
        _VWE-FD @ FD.CUR-LO @ _VWE-POS !
        _VWE-A @ _VWE-REM @ _VWE-FD @ VFS-WRITE?
        DUP IF NIP EXIT THEN DROP DUP _VWE-ACT !
        DUP 0= OVER 0< OR SWAP _VWE-REM @ > OR IF
            _VWE-POS @ _VWE-FD @ FD.CUR-LO ! VFS-E-IO EXIT THEN
        _VWE-ACT @ _VWE-A +!
        _VWE-ACT @ NEGATE _VWE-REM +!
    REPEAT
    0 ;

\ =====================================================================
\  VFS-SEEK / VFS-REWIND / VFS-TELL / VFS-SIZE
\ =====================================================================

VARIABLE _VSK-POS
VARIABLE _VSK-FD
VARIABLE _VSK-V

: VFS-SEEK?  ( pos fd -- ior )
    _VSK-FD ! _VSK-POS !
    _VSK-FD @ 0= IF VFS-E-BADF EXIT THEN
    _VSK-FD @ FD.VFS @ DUP 0= IF DROP VFS-E-BADF EXIT THEN _VSK-V !
    _VSK-V @ _VFS-READY ?DUP IF EXIT THEN
    _VSK-POS @ 0< IF VFS-E-OVERFLOW EXIT THEN
    _VSK-POS @ _VSK-FD @ FD.CUR-LO !
    0 _VSK-FD @ FD.CUR-HI !
    0 ;

: VFS-SEEK    ( pos fd -- )       VFS-SEEK? ?DUP IF THROW THEN ;
: VFS-REWIND  ( fd -- )          0 SWAP VFS-SEEK ;
: VFS-TELL    ( fd -- pos )      FD.CUR-LO @ ;
: VFS-SIZE    ( fd -- size )     FD.INODE @ IN.SIZE-LO @ ;

\ VFS-TRUNCATE ( size fd -- ior )
\   Set a file's logical size and notify its backing store.  The file
\   cursor is clamped to the new end on success.
VARIABLE _VTR-V
: VFS-TRUNCATE  ( size fd -- ior )
    _VTR-FD ! _VTR-SIZE !
    _VTR-FD @ 0= IF VFS-E-BADF EXIT THEN
    _VTR-SIZE @ 0< IF VFS-E-OVERFLOW EXIT THEN
    _VTR-FD @ FD.VFS @ DUP 0= IF DROP VFS-E-BADF EXIT THEN _VTR-V !
    _VTR-V @ _VFS-READY ?DUP IF EXIT THEN
    _VTR-FD @ FD.FLAGS @ VFS-FF-WRITE AND 0= IF VFS-E-BADF EXIT THEN
    _VTR-FD @ FD.INODE @ IN.TYPE @ VFS-T-DIR = IF VFS-E-ISDIR EXIT THEN
    _VTR-V @ V.FLAGS @ VFS-F-RO AND IF VFS-E-READONLY EXIT THEN
    _VTR-FD @ FD.GEN @ _VTR-V @ V.MEDIA-GEN @ <> IF VFS-E-STALE EXIT THEN
    VFS-OP-TRUNCATE _VTR-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VTR-FD @ FD.INODE @ IN.SIZE-LO @ _VTR-OLD-SIZE !
    _VTR-FD @ FD.INODE @ IN.SIZE-HI @ _VTR-OLD-SIZE-HI !
    _VTR-SIZE @ _VTR-FD @ FD.INODE @ IN.SIZE-LO !
    0 _VTR-FD @ FD.INODE @ IN.SIZE-HI !
    _VTR-FD @ FD.INODE @
    _VTR-V @
    VFS-OP-TRUNCATE _VTR-V @ _VFS-XT EXECUTE
    DUP IF
        _VTR-OLD-SIZE @ _VTR-FD @ FD.INODE @ IN.SIZE-LO !
        _VTR-OLD-SIZE-HI @ _VTR-FD @ FD.INODE @ IN.SIZE-HI !
        EXIT
    THEN DROP
    VFS-IF-DIRTY
    _VTR-FD @ FD.INODE @ IN.FLAGS DUP @ ROT OR SWAP !
    VFS-F-DIRTY _VTR-V @ V.FLAGS DUP @ ROT OR SWAP !
    _VTR-FD @ FD.CUR-LO @ _VTR-SIZE @ > IF
        _VTR-SIZE @ _VTR-FD @ FD.CUR-LO !
    THEN
    0 _VTR-V @ _VFS-RESULT ;

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
        IN.CHILD                 ( child pchild-field )
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
VARIABLE _VMK-IN
VARIABLE _VMK-IOR
VARIABLE _VMK-A
VARIABLE _VMK-U

: _VFS-VALID-NAME?  ( c-addr u -- flag )
    DUP 0= IF 2DROP FALSE EXIT THEN
    DUP 0< IF 2DROP FALSE EXIT THEN
    DUP 255 > IF 2DROP FALSE EXIT THEN
    OVER 0= IF 2DROP FALSE EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP FALSE EXIT THEN
    DUP 1 = IF
        OVER C@ [CHAR] . = IF 2DROP FALSE EXIT THEN
    THEN
    DUP 2 = IF
        OVER C@ [CHAR] . =
        2 PICK 1+ C@ [CHAR] . = AND IF 2DROP FALSE EXIT THEN
    THEN
    DUP 0 ?DO
        OVER I + C@ DUP 0= SWAP [CHAR] / = OR IF
            2DROP FALSE UNLOOP EXIT
        THEN
    LOOP
    2DROP TRUE ;

: VFS-MKFILE?  ( c-addr u vfs -- inode ior )
    _VMK-V ! _VMK-U ! _VMK-A !
    _VMK-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VMK-V @ V.FLAGS @ VFS-F-RO AND IF 0 VFS-E-READONLY EXIT THEN
    VFS-OP-CREATE _VMK-V @ _VFS-HAS-OP? 0= IF 0 VFS-E-UNSUPPORTED EXIT THEN
    _VMK-A @ _VMK-U @ _VFS-VALID-NAME? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VMK-V @ V.CWD @ _VMK-V @ _VFS-ENSURE-CHILDREN?
    ?DUP IF 0 SWAP EXIT THEN
    _VMK-A @ _VMK-U @ _VMK-V @ V.CWD @ _VFS-FIND-CHILD
    ?DUP IF DROP 0 VFS-E-EXISTS EXIT THEN
    \ Allocate new inode
    VFS-T-FILE _VMK-V @ _VFS-INODE-ALLOC   ( inode )
    DUP 0= IF 0 VFS-E-NOMEM EXIT THEN
    \ Set name
    _VMK-A @ _VMK-U @ _VMK-V @ _VFS-STR-ALLOC ( inode handle )
    DUP 0= IF
        DROP DUP _VMK-V @ _VFS-INODE-FREE
        DROP 0 VFS-E-NOMEM EXIT
    THEN
    OVER IN.NAME !                           ( inode )
    \ Zero size
    0 OVER IN.SIZE-LO !
    0 OVER IN.SIZE-HI !
    0 OVER IN.FLAGS !
    DUP _VMK-IN !
    \ Add to cwd
    DUP _VMK-V @ V.CWD @  _VFS-ADD-CHILD
    \ Notify binding
    DUP _VMK-V @ VFS-OP-CREATE _VMK-V @ _VFS-XT EXECUTE _VMK-IOR !
    _VMK-IOR @ IF
        DROP
        _VMK-IN @ _VMK-V @ V.CWD @ _VFS-REMOVE-CHILD
        _VMK-IN @ _VMK-V @ _VFS-INODE-FREE
        0 _VMK-IOR @ EXIT
    THEN
    \ Increment count
    _VMK-V @ V.ICOUNT DUP @ 1+ SWAP !
    VFS-F-DIRTY _VMK-V @ V.FLAGS DUP @ ROT OR SWAP !
    0 ;

: VFS-MKFILE  ( c-addr u vfs -- inode | 0 )
    VFS-MKFILE? DUP 0= IF DROP EXIT THEN
    DUP VFS-IOR-REASON DUP _VFS-R-EXISTS =
    SWAP _VFS-R-READONLY = OR IF 2DROP 0 EXIT THEN
    NIP THROW ;

: VFS-MKDIR  ( c-addr u vfs -- ior )
    _VMK-V ! _VMK-U ! _VMK-A !
    _VMK-V @ _VFS-READY ?DUP IF EXIT THEN
    _VMK-V @ V.FLAGS @ VFS-F-RO AND IF VFS-E-READONLY EXIT THEN
    VFS-OP-MKDIR _VMK-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VMK-A @ _VMK-U @ _VFS-VALID-NAME? 0= IF VFS-E-INVALID EXIT THEN
    _VMK-V @ V.CWD @ _VMK-V @ _VFS-ENSURE-CHILDREN? ?DUP IF EXIT THEN
    _VMK-A @ _VMK-U @ _VMK-V @ V.CWD @ _VFS-FIND-CHILD
    ?DUP IF DROP VFS-E-EXISTS EXIT THEN
    VFS-T-DIR _VMK-V @ _VFS-INODE-ALLOC    ( inode )
    DUP 0= IF VFS-E-NOMEM EXIT THEN
    _VMK-A @ _VMK-U @ _VMK-V @ _VFS-STR-ALLOC ( inode handle )
    DUP 0= IF
        DROP DUP _VMK-V @ _VFS-INODE-FREE
        DROP VFS-E-NOMEM EXIT
    THEN
    OVER IN.NAME !
    0 OVER IN.SIZE-LO !
    0 OVER IN.SIZE-HI !
    VFS-IF-CHILDREN OVER IN.FLAGS !  \ empty dir = children loaded
    DUP _VMK-IN !
    DUP _VMK-V @ V.CWD @  _VFS-ADD-CHILD
    DUP _VMK-V @ VFS-OP-MKDIR _VMK-V @ _VFS-XT EXECUTE _VMK-IOR !
    _VMK-IOR @ IF
        DROP
        _VMK-IN @ _VMK-V @ V.CWD @ _VFS-REMOVE-CHILD
        _VMK-IN @ _VMK-V @ _VFS-INODE-FREE
        _VMK-IOR @ EXIT
    THEN
    _VMK-V @ V.ICOUNT DUP @ 1+ SWAP !
    VFS-F-DIRTY _VMK-V @ V.FLAGS DUP @ ROT OR SWAP !
    DROP 0 ;                     \ ior = 0 (success)

\ Rename is one binding operation followed by one cache publication.  The
\ old tree remains authoritative until the callback succeeds.
1 CONSTANT VFS-RN-NOREPLACE

VARIABLE _VRN-A
VARIABLE _VRN-U
VARIABLE _VRN-IN
VARIABLE _VRN-V
VARIABLE _VRN-PARENT
VARIABLE _VRN-OLD-PARENT
VARIABLE _VRN-HANDLE
VARIABLE _VRN-VICTIM
VARIABLE _VRN-FLAGS
VARIABLE _VRN-WALK

: VFS-RENAME-AT  ( new-a new-u inode new-parent flags vfs -- ior )
    _VRN-V ! _VRN-FLAGS ! _VRN-PARENT ! _VRN-IN ! _VRN-U ! _VRN-A !
    _VRN-V @ _VFS-READY ?DUP IF EXIT THEN
    _VRN-V @ V.FLAGS @ VFS-F-RO AND IF VFS-E-READONLY EXIT THEN
    VFS-OP-RENAME _VRN-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VRN-IN @ _VRN-V @ _VFS-DENTRY-OWNED? 0= IF VFS-E-XDEV EXIT THEN
    _VRN-PARENT @ _VRN-V @ _VFS-DENTRY-OWNED? 0= IF VFS-E-XDEV EXIT THEN
    _VRN-A @ _VRN-U @ _VFS-VALID-NAME? 0= IF VFS-E-INVALID EXIT THEN
    _VRN-IN @ IN.PARENT @ DUP 0= IF DROP VFS-E-INVALID EXIT THEN
    _VRN-OLD-PARENT !
    _VRN-PARENT @ IN.TYPE @ VFS-T-DIR <> IF VFS-E-NOTDIR EXIT THEN
    _VRN-PARENT @ _VRN-V @ _VFS-ENSURE-CHILDREN? ?DUP IF EXIT THEN
    _VRN-A @ _VRN-U @ _VRN-PARENT @ _VFS-FIND-CHILD
    DUP _VRN-IN @ = IF DROP 0 EXIT THEN _VRN-VICTIM !
    _VRN-VICTIM @ IF
        _VRN-VICTIM @ D.VNODE @ _VRN-IN @ D.VNODE @ = IF 0 EXIT THEN
        _VRN-FLAGS @ VFS-RN-NOREPLACE AND IF VFS-E-EXISTS EXIT THEN
        _VRN-VICTIM @ IN.TYPE @ VFS-T-DIR = IF
            _VRN-VICTIM @ _VRN-V @ _VFS-ENSURE-CHILDREN? ?DUP IF EXIT THEN
            _VRN-VICTIM @ IN.CHILD @ IF VFS-E-NOTEMPTY EXIT THEN
        THEN
        _VRN-IN @ IN.TYPE @ VFS-T-DIR =
        _VRN-VICTIM @ IN.TYPE @ VFS-T-DIR = <> IF VFS-E-CONFLICT EXIT THEN
    THEN
    \ A directory cannot be moved beneath itself.
    _VRN-IN @ IN.TYPE @ VFS-T-DIR = IF
        _VRN-PARENT @ _VRN-WALK !
        BEGIN _VRN-WALK @ WHILE
            _VRN-WALK @ _VRN-IN @ = IF VFS-E-INVALID EXIT THEN
            _VRN-WALK @ IN.PARENT @ _VRN-WALK !
        REPEAT
    THEN
    _VRN-A @ _VRN-U @ _VRN-V @ _VFS-STR-ALLOC _VRN-HANDLE !
    _VRN-HANDLE @ 0= IF VFS-E-NOMEM EXIT THEN
    _VRN-A @ _VRN-U @ _VRN-IN @ _VRN-PARENT @ _VRN-VICTIM @
    _VRN-FLAGS @ _VRN-V @
    VFS-OP-RENAME _VRN-V @ _VFS-XT EXECUTE
    DUP IF _VRN-HANDLE @ _VFS-STR-RELEASE EXIT THEN
    DROP
    _VRN-VICTIM @ IF
        _VRN-VICTIM @ _VRN-PARENT @ _VFS-REMOVE-CHILD
        -1 _VRN-VICTIM @ D.VNODE @ VN.NLINK +!
        _VRN-VICTIM @ _VRN-V @ _VFS-DENTRY-HAS-FD? IF
            VFS-DF-UNLINKED _VRN-VICTIM @ D.FLAGS !
        ELSE
            _VRN-VICTIM @ FALSE _VRN-V @ _VFS-DENTRY-RELEASE
        THEN
        _VRN-V @ V.ICOUNT DUP @ 1- SWAP !
    THEN
    _VRN-OLD-PARENT @ _VRN-PARENT @ <> IF
        _VRN-IN @ _VRN-OLD-PARENT @ _VFS-REMOVE-CHILD
        _VRN-IN @ _VRN-PARENT @ _VFS-ADD-CHILD
    THEN
    _VRN-IN @ IN.NAME @ _VFS-STR-RELEASE
    _VRN-HANDLE @ _VRN-IN @ IN.NAME !
    VFS-IF-DIRTY _VRN-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    VFS-F-DIRTY _VRN-V @ V.FLAGS DUP @ ROT OR SWAP !
    0 ;

: VFS-RENAME  ( new-a new-u inode vfs -- ior )
    >R DUP IN.PARENT @ VFS-RN-NOREPLACE R> VFS-RENAME-AT ;

VARIABLE _VLN-A
VARIABLE _VLN-U
VARIABLE _VLN-TARGET
VARIABLE _VLN-PARENT
VARIABLE _VLN-V
VARIABLE _VLN-D
VARIABLE _VLN-H

: VFS-LINK  ( name-a name-u target parent vfs -- dentry ior )
    _VLN-V ! _VLN-PARENT ! _VLN-TARGET ! _VLN-U ! _VLN-A !
    _VLN-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VLN-V @ V.FLAGS @ VFS-F-RO AND IF 0 VFS-E-READONLY EXIT THEN
    VFS-OP-LINK _VLN-V @ _VFS-HAS-OP? 0= IF 0 VFS-E-UNSUPPORTED EXIT THEN
    _VLN-TARGET @ _VLN-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    _VLN-PARENT @ _VLN-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    _VLN-TARGET @ IN.TYPE @ VFS-T-DIR = IF 0 VFS-E-ISDIR EXIT THEN
    _VLN-PARENT @ IN.TYPE @ VFS-T-DIR <> IF 0 VFS-E-NOTDIR EXIT THEN
    _VLN-A @ _VLN-U @ _VFS-VALID-NAME? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VLN-PARENT @ _VLN-V @ _VFS-ENSURE-CHILDREN? ?DUP IF 0 SWAP EXIT THEN
    _VLN-A @ _VLN-U @ _VLN-PARENT @ _VFS-FIND-CHILD
    ?DUP IF DROP 0 VFS-E-EXISTS EXIT THEN
    _VLN-V @ _VFS-DENTRY-ALLOC DUP 0= IF 0 VFS-E-NOMEM EXIT THEN _VLN-D !
    _VLN-A @ _VLN-U @ _VLN-V @ _VFS-STR-ALLOC DUP 0= IF
        DROP _VLN-D @ _VFS-ZERO-INODE
        _VLN-V @ V.IFREE @ _VLN-D @ !
        _VLN-D @ _VLN-V @ V.IFREE !
        0 VFS-E-NOMEM EXIT
    THEN _VLN-H !
    _VLN-H @ _VLN-D @ D.NAME !
    _VLN-TARGET @ D.VNODE @ DUP _VLN-D @ D.VNODE !
    1 OVER VN.NLINK +! 1 SWAP VN.DREFS +!
    _VLN-PARENT @ _VLN-D @ D.PARENT !
    _VLN-D @ _VLN-TARGET @ _VLN-V @
    VFS-OP-LINK _VLN-V @ _VFS-XT EXECUTE
    DUP IF
        _VLN-D @ TRUE _VLN-V @ _VFS-DENTRY-RELEASE
        0 SWAP EXIT
    THEN DROP
    _VLN-D @ _VLN-PARENT @ _VFS-ADD-CHILD
    _VLN-V @ V.ICOUNT DUP @ 1+ SWAP !
    VFS-F-DIRTY _VLN-V @ V.FLAGS DUP @ ROT OR SWAP !
    _VLN-D @ 0 ;

\ Cache-population helpers for READDIR/LOOKUP.  Stable BID+generation is the
\ vnode identity key; loading another on-disk hard link attaches a new dentry
\ without inventing another vnode or changing persistent NLINK metadata.
VARIABLE _VFV-BID
VARIABLE _VFV-GEN
VARIABLE _VFV-V
VARIABLE _VFV-P
VARIABLE _VFV-D

: _VFS-FIND-VNODE  ( bid generation vfs -- vnode | 0 )
    _VFV-V ! _VFV-GEN ! _VFV-BID !
    _VFV-V @ V.ISLAB @ _VFV-P !
    BEGIN _VFV-P @ WHILE
        _VFS-SLAB-SLOTS 0 DO
            _VFV-P @ 8 + I VFS-INODE-SIZE * + _VFV-D !
            _VFV-D @ D.VNODE @ ?DUP IF
                DUP VN.BID @ _VFV-BID @ =
                OVER VN.GEN @ _VFV-GEN @ = AND IF
                    UNLOOP EXIT
                THEN
                DROP
            THEN
        LOOP
        _VFV-P @ @ _VFV-P !
    REPEAT
    0 ;

: _VFS-DENTRY-ABANDON  ( dentry vfs -- )
    >R
    DUP _VFS-ZERO-INODE
    R@ V.IFREE @ OVER !
    R> V.IFREE ! ;

VARIABLE _VCDN-A
VARIABLE _VCDN-U
VARIABLE _VCDN-TYPE
VARIABLE _VCDN-BID
VARIABLE _VCDN-GEN
VARIABLE _VCDN-PARENT
VARIABLE _VCDN-V
VARIABLE _VCDN-D
VARIABLE _VCDN-VN
VARIABLE _VCDN-H

: VFS-CACHE-DENTRY  ( name-a name-u type bid generation parent vfs -- dentry ior )
    _VCDN-V ! _VCDN-PARENT ! _VCDN-GEN ! _VCDN-BID !
    _VCDN-TYPE ! _VCDN-U ! _VCDN-A !
    _VCDN-PARENT @ 0= _VCDN-BID @ 0= OR IF 0 VFS-E-INVALID EXIT THEN
    _VCDN-PARENT @ _VCDN-V @ _VFS-DENTRY-OWNED? 0= IF
        0 VFS-E-XDEV EXIT
    THEN
    _VCDN-PARENT @ IN.TYPE @ VFS-T-DIR <> IF 0 VFS-E-NOTDIR EXIT THEN
    _VCDN-TYPE @ VFS-T-FILE < _VCDN-TYPE @ VFS-T-SPECIAL > OR IF
        0 VFS-E-INVALID EXIT
    THEN
    _VCDN-A @ _VCDN-U @ _VFS-VALID-NAME? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VCDN-A @ _VCDN-U @ _VCDN-PARENT @ _VFS-FIND-CHILD DUP IF
        DUP IN.TYPE @ _VCDN-TYPE @ <> IF DROP 0 VFS-E-CORRUPT EXIT THEN
        DUP D.VNODE @ DUP VN.BID @ _VCDN-BID @ =
        SWAP VN.GEN @ _VCDN-GEN @ = AND IF 0 EXIT THEN
        DROP 0 VFS-E-CONFLICT EXIT
    THEN DROP
    _VCDN-BID @ _VCDN-GEN @ _VCDN-V @ _VFS-FIND-VNODE
    DUP IF
        DUP VN.TYPE @ _VCDN-TYPE @ <> IF DROP 0 VFS-E-CORRUPT EXIT THEN
        _VCDN-VN !
        _VCDN-V @ _VFS-DENTRY-ALLOC DUP 0= IF 0 VFS-E-NOMEM EXIT THEN
        _VCDN-D !
        _VCDN-A @ _VCDN-U @ _VCDN-V @ _VFS-STR-ALLOC DUP 0= IF
            DROP _VCDN-D @ _VCDN-V @ _VFS-DENTRY-ABANDON
            0 VFS-E-NOMEM EXIT
        THEN _VCDN-H !
        _VCDN-H @ _VCDN-D @ D.NAME !
        _VCDN-VN @ _VCDN-D @ D.VNODE !
        1 _VCDN-VN @ VN.DREFS +!
    ELSE
        DROP
        _VCDN-TYPE @ _VCDN-V @ _VFS-INODE-ALLOC DUP 0= IF
            0 VFS-E-NOMEM EXIT
        THEN _VCDN-D !
        _VCDN-BID @ _VCDN-D @ IN.BID !
        _VCDN-GEN @ _VCDN-D @ D.VNODE @ VN.GEN !
        _VCDN-A @ _VCDN-U @ _VCDN-V @ _VFS-STR-ALLOC DUP 0= IF
            DROP _VCDN-D @ _VCDN-V @ _VFS-INODE-FREE
            0 VFS-E-NOMEM EXIT
        THEN _VCDN-D @ IN.NAME !
    THEN
    _VCDN-D @ _VCDN-PARENT @ _VFS-ADD-CHILD
    _VCDN-V @ V.ICOUNT DUP @ 1+ SWAP !
    _VCDN-D @ 0 ;

VARIABLE _VCDD-D
VARIABLE _VCDD-V

: VFS-CACHE-DROP  ( dentry vfs -- ior )
    _VCDD-V ! _VCDD-D !
    _VCDD-D @ 0= IF VFS-E-INVALID EXIT THEN
    _VCDD-D @ _VCDD-V @ _VFS-DENTRY-OWNED? 0= IF VFS-E-XDEV EXIT THEN
    _VCDD-D @ D.VNODE @ 0= IF VFS-E-INVALID EXIT THEN
    _VCDD-D @ _VCDD-V @ V.ROOT @ = IF VFS-E-INVALID EXIT THEN
    _VCDD-D @ IN.PARENT @ DUP 0= IF DROP VFS-E-INVALID EXIT THEN
    _VCDD-D @ _VCDD-V @ _VFS-DENTRY-HAS-FD? IF
        DROP
        VFS-E-BUSY EXIT
    THEN
    _VCDD-D @ SWAP _VFS-REMOVE-CHILD
    _VCDD-D @ _VCDD-V @ _VFS-INODE-EVICT
    _VCDD-V @ V.ICOUNT DUP @ 1- SWAP !
    0 ;

VARIABLE _VLK-A
VARIABLE _VLK-U
VARIABLE _VLK-PARENT
VARIABLE _VLK-V
VARIABLE _VLK-D
VARIABLE _VLK-IOR

: VFS-LOOKUP  ( name-a name-u parent vfs -- dentry ior )
    _VLK-V ! _VLK-PARENT ! _VLK-U ! _VLK-A !
    _VLK-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    VFS-OP-LOOKUP _VLK-V @ _VFS-HAS-OP? 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VLK-PARENT @ 0= IF 0 VFS-E-INVALID EXIT THEN
    _VLK-PARENT @ _VLK-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    _VLK-PARENT @ IN.TYPE @ VFS-T-DIR <> IF 0 VFS-E-NOTDIR EXIT THEN
    _VLK-A @ _VLK-U @ _VFS-VALID-NAME? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VLK-A @ _VLK-U @ _VLK-PARENT @ _VFS-FIND-CHILD DUP IF 0 EXIT THEN DROP
    _VLK-A @ _VLK-U @ _VLK-PARENT @ _VLK-V @
    VFS-OP-LOOKUP _VLK-V @ _VFS-XT EXECUTE
    _VLK-IOR ! _VLK-D !
    _VLK-IOR @ IF
        _VLK-IOR @ _VLK-V @ _VFS-RESULT DROP
        0 _VLK-IOR @ EXIT
    THEN
    _VLK-D @ 0= IF 0 VFS-E-CORRUPT EXIT THEN
    _VLK-D @ D.VNODE @ 0= IF 0 VFS-E-CORRUPT EXIT THEN
    _VLK-D @ _VLK-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    _VLK-D @ IN.PARENT @ _VLK-PARENT @ <> IF 0 VFS-E-CORRUPT EXIT THEN
    _VLK-A @ _VLK-U @ _VLK-D @ IN.NAME @ _VFS-STR-MATCH? 0= IF
        0 VFS-E-CORRUPT EXIT
    THEN
    _VLK-D @ 0 _VLK-V @ _VFS-RESULT ;

' VFS-LOOKUP _VFS-LOOKUP-XT !

\ =====================================================================
\  Ext4-facing metadata, symlink, xattr, and statfs dispatch
\ =====================================================================

: _VFS-BUFFER?  ( a u -- flag )
    DUP 0< IF 2DROP FALSE EXIT THEN
    DUP 0= IF 2DROP TRUE EXIT THEN
    OVER 0= IF 2DROP FALSE EXIT THEN
    MSPAN-NONWRAPPING? ;

: _VFS-XATTR-NAME?  ( a u -- flag )
    DUP 0= IF 2DROP FALSE EXIT THEN
    DUP 255 > IF 2DROP FALSE EXIT THEN
    _VFS-BUFFER? ;

: _VFS-ACTUAL-VALID?  ( actual capacity -- flag )
    OVER 0< IF 2DROP FALSE EXIT THEN
    DUP 0= IF 2DROP TRUE EXIT THEN
    U> 0= ;

VARIABLE _VGA-IN
VARIABLE _VGA-V

: VFS-GETATTR  ( inode vfs -- ior )
    _VGA-V ! _VGA-IN !
    _VGA-IN @ 0= IF VFS-E-INVALID EXIT THEN
    _VGA-V @ _VFS-READY ?DUP IF EXIT THEN
    _VGA-IN @ _VGA-V @ _VFS-DENTRY-OWNED? 0= IF VFS-E-XDEV EXIT THEN
    VFS-OP-GETATTR _VGA-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VGA-IN @ _VGA-V @
    VFS-OP-GETATTR _VGA-V @ _VFS-XT EXECUTE
    _VGA-V @ _VFS-RESULT ;

VARIABLE _VSA-ATTR
VARIABLE _VSA-MASK
VARIABLE _VSA-IN
VARIABLE _VSA-V
VARIABLE _VSA-VN

: VFS-SETATTR  ( attr inode vfs -- ior )
    _VSA-V ! _VSA-IN ! _VSA-ATTR !
    _VSA-ATTR @ 0= _VSA-IN @ 0= OR IF VFS-E-INVALID EXIT THEN
    _VSA-ATTR @ VFS-ATTR-SIZE _VFS-BUFFER? 0= IF VFS-E-INVALID EXIT THEN
    _VSA-ATTR @ VA.MASK @ _VSA-MASK !
    _VSA-MASK @ VFS-SA-ALL INVERT AND IF VFS-E-INVALID EXIT THEN
    _VSA-V @ _VFS-READY ?DUP IF EXIT THEN
    _VSA-IN @ _VSA-V @ _VFS-DENTRY-OWNED? 0= IF VFS-E-XDEV EXIT THEN
    _VSA-V @ V.FLAGS @ VFS-F-RO AND IF VFS-E-READONLY EXIT THEN
    VFS-OP-SETATTR _VSA-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VSA-ATTR @ _VSA-IN @ _VSA-V @
    VFS-OP-SETATTR _VSA-V @ _VFS-XT EXECUTE
    DUP IF _VSA-V @ _VFS-RESULT EXIT THEN DROP
    _VSA-IN @ D.VNODE @ _VSA-VN !
    _VSA-MASK @ VFS-SA-MODE AND IF
        _VSA-ATTR @ VA.MODE @ _VSA-VN @ VN.MODE !
    THEN
    _VSA-MASK @ VFS-SA-UID AND IF
        _VSA-ATTR @ VA.UID @ _VSA-VN @ VN.UID !
    THEN
    _VSA-MASK @ VFS-SA-GID AND IF
        _VSA-ATTR @ VA.GID @ _VSA-VN @ VN.GID !
    THEN
    _VSA-MASK @ VFS-SA-ATIME AND IF
        _VSA-ATTR @ VA.ATIME @ _VSA-VN @ VN.ATIME !
        _VSA-ATTR @ VA.ATIME-NS @ _VSA-VN @ VN.ATIME-NS !
    THEN
    _VSA-MASK @ VFS-SA-MTIME AND IF
        _VSA-ATTR @ VA.MTIME @ _VSA-VN @ VN.MTIME !
        _VSA-ATTR @ VA.MTIME-NS @ _VSA-VN @ VN.MTIME-NS !
    THEN
    _VSA-MASK @ VFS-SA-CTIME AND IF
        _VSA-ATTR @ VA.CTIME @ _VSA-VN @ VN.CTIME !
        _VSA-ATTR @ VA.CTIME-NS @ _VSA-VN @ VN.CTIME-NS !
    THEN
    _VSA-MASK @ VFS-SA-RDEV AND IF
        _VSA-ATTR @ VA.RDEV @ _VSA-VN @ VN.RDEV !
    THEN
    VFS-IF-DIRTY _VSA-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    VFS-F-DIRTY _VSA-V @ V.FLAGS DUP @ ROT OR SWAP !
    0 _VSA-V @ _VFS-RESULT ;

VARIABLE _VSL-TA
VARIABLE _VSL-TU
VARIABLE _VSL-NA
VARIABLE _VSL-NU
VARIABLE _VSL-PARENT
VARIABLE _VSL-V
VARIABLE _VSL-D
VARIABLE _VSL-H

: VFS-SYMLINK  ( target-a target-u name-a name-u parent vfs -- inode ior )
    _VSL-V ! _VSL-PARENT ! _VSL-NU ! _VSL-NA ! _VSL-TU ! _VSL-TA !
    _VSL-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VSL-V @ V.FLAGS @ VFS-F-RO AND IF 0 VFS-E-READONLY EXIT THEN
    VFS-OP-SYMLINK _VSL-V @ _VFS-HAS-OP? 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VSL-PARENT @ 0= IF 0 VFS-E-INVALID EXIT THEN
    _VSL-PARENT @ _VSL-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    _VSL-PARENT @ IN.TYPE @ VFS-T-DIR <> IF 0 VFS-E-NOTDIR EXIT THEN
    _VSL-NA @ _VSL-NU @ _VFS-VALID-NAME? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VSL-TA @ _VSL-TU @ _VFS-BUFFER? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VSL-PARENT @ _VSL-V @ _VFS-ENSURE-CHILDREN? ?DUP IF 0 SWAP EXIT THEN
    _VSL-NA @ _VSL-NU @ _VSL-PARENT @ _VFS-FIND-CHILD
    ?DUP IF DROP 0 VFS-E-EXISTS EXIT THEN
    VFS-T-SYMLINK _VSL-V @ _VFS-INODE-ALLOC
    DUP 0= IF 0 VFS-E-NOMEM EXIT THEN _VSL-D !
    _VSL-NA @ _VSL-NU @ _VSL-V @ _VFS-STR-ALLOC DUP 0= IF
        DROP _VSL-D @ _VSL-V @ _VFS-INODE-FREE
        0 VFS-E-NOMEM EXIT
    THEN _VSL-H !
    _VSL-H @ _VSL-D @ IN.NAME !
    _VSL-TU @ _VSL-D @ IN.SIZE-LO !
    _VSL-PARENT @ _VSL-D @ IN.PARENT !
    _VSL-TA @ _VSL-TU @ _VSL-D @ _VSL-V @
    VFS-OP-SYMLINK _VSL-V @ _VFS-XT EXECUTE
    DUP IF
        _VSL-D @ _VSL-V @ _VFS-INODE-FREE
        0 SWAP EXIT
    THEN DROP
    _VSL-D @ _VSL-PARENT @ _VFS-ADD-CHILD
    _VSL-V @ V.ICOUNT DUP @ 1+ SWAP !
    VFS-F-DIRTY _VSL-V @ V.FLAGS DUP @ ROT OR SWAP !
    _VSL-D @ 0 ;

VARIABLE _VRL-BUF
VARIABLE _VRL-CAP
VARIABLE _VRL-IN
VARIABLE _VRL-V
VARIABLE _VRL-ACT
VARIABLE _VRL-IOR

: VFS-READLINK  ( buf capacity inode vfs -- actual ior )
    _VRL-V ! _VRL-IN ! _VRL-CAP ! _VRL-BUF !
    _VRL-IN @ 0= IF 0 VFS-E-INVALID EXIT THEN
    _VRL-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VRL-IN @ _VRL-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    _VRL-IN @ IN.TYPE @ VFS-T-SYMLINK <> IF 0 VFS-E-INVALID EXIT THEN
    VFS-OP-READLINK _VRL-V @ _VFS-HAS-OP? 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VRL-BUF @ _VRL-CAP @ _VFS-BUFFER? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VRL-BUF @ _VRL-CAP @ _VRL-IN @ _VRL-V @
    VFS-OP-READLINK _VRL-V @ _VFS-XT EXECUTE
    _VRL-IOR ! _VRL-ACT !
    _VRL-ACT @ _VRL-CAP @ _VFS-ACTUAL-VALID? 0= IF
        0 VFS-E-CORRUPT EXIT
    THEN
    _VRL-IOR @ _VRL-V @ _VFS-RESULT DROP
    _VRL-ACT @ _VRL-IOR @ ;

VARIABLE _VLX-BUF
VARIABLE _VLX-CAP
VARIABLE _VLX-IN
VARIABLE _VLX-V
VARIABLE _VLX-ACT
VARIABLE _VLX-IOR

: VFS-LISTXATTR  ( buf capacity inode vfs -- actual ior )
    _VLX-V ! _VLX-IN ! _VLX-CAP ! _VLX-BUF !
    _VLX-IN @ 0= IF 0 VFS-E-INVALID EXIT THEN
    _VLX-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VLX-IN @ _VLX-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    VFS-OP-LISTXATTR _VLX-V @ _VFS-HAS-OP? 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VLX-BUF @ _VLX-CAP @ _VFS-BUFFER? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VLX-BUF @ _VLX-CAP @ _VLX-IN @ _VLX-V @
    VFS-OP-LISTXATTR _VLX-V @ _VFS-XT EXECUTE
    _VLX-IOR ! _VLX-ACT !
    _VLX-ACT @ _VLX-CAP @ _VFS-ACTUAL-VALID? 0= IF
        0 VFS-E-CORRUPT EXIT
    THEN
    _VLX-IOR @ _VLX-V @ _VFS-RESULT DROP
    _VLX-ACT @ _VLX-IOR @ ;

VARIABLE _VGX-NA
VARIABLE _VGX-NU
VARIABLE _VGX-BUF
VARIABLE _VGX-CAP
VARIABLE _VGX-IN
VARIABLE _VGX-V
VARIABLE _VGX-ACT
VARIABLE _VGX-IOR

: VFS-GETXATTR  ( name-a name-u buf capacity inode vfs -- actual ior )
    _VGX-V ! _VGX-IN ! _VGX-CAP ! _VGX-BUF ! _VGX-NU ! _VGX-NA !
    _VGX-IN @ 0= IF 0 VFS-E-INVALID EXIT THEN
    _VGX-V @ _VFS-READY ?DUP IF 0 SWAP EXIT THEN
    _VGX-IN @ _VGX-V @ _VFS-DENTRY-OWNED? 0= IF 0 VFS-E-XDEV EXIT THEN
    VFS-OP-GETXATTR _VGX-V @ _VFS-HAS-OP? 0= IF
        0 VFS-E-UNSUPPORTED EXIT
    THEN
    _VGX-NA @ _VGX-NU @ _VFS-XATTR-NAME? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VGX-BUF @ _VGX-CAP @ _VFS-BUFFER? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VGX-NA @ _VGX-NU @ _VGX-BUF @ _VGX-CAP @ _VGX-IN @ _VGX-V @
    VFS-OP-GETXATTR _VGX-V @ _VFS-XT EXECUTE
    _VGX-IOR ! _VGX-ACT !
    _VGX-ACT @ _VGX-CAP @ _VFS-ACTUAL-VALID? 0= IF
        0 VFS-E-CORRUPT EXIT
    THEN
    _VGX-IOR @ _VGX-V @ _VFS-RESULT DROP
    _VGX-ACT @ _VGX-IOR @ ;

VARIABLE _VSX-NA
VARIABLE _VSX-NU
VARIABLE _VSX-VA
VARIABLE _VSX-VU
VARIABLE _VSX-FLAGS
VARIABLE _VSX-IN
VARIABLE _VSX-V

: VFS-SETXATTR  ( name-a name-u value-a value-u flags inode vfs -- ior )
    _VSX-V ! _VSX-IN ! _VSX-FLAGS ! _VSX-VU ! _VSX-VA ! _VSX-NU ! _VSX-NA !
    _VSX-IN @ 0= IF VFS-E-INVALID EXIT THEN
    _VSX-V @ _VFS-READY ?DUP IF EXIT THEN
    _VSX-IN @ _VSX-V @ _VFS-DENTRY-OWNED? 0= IF VFS-E-XDEV EXIT THEN
    _VSX-V @ V.FLAGS @ VFS-F-RO AND IF VFS-E-READONLY EXIT THEN
    VFS-OP-SETXATTR _VSX-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VSX-NA @ _VSX-NU @ _VFS-XATTR-NAME? 0= IF VFS-E-INVALID EXIT THEN
    _VSX-VA @ _VSX-VU @ _VFS-BUFFER? 0= IF VFS-E-INVALID EXIT THEN
    _VSX-FLAGS @ VFS-XATTR-CREATE VFS-XATTR-REPLACE OR INVERT AND IF
        VFS-E-INVALID EXIT
    THEN
    _VSX-FLAGS @ VFS-XATTR-CREATE VFS-XATTR-REPLACE OR = IF
        VFS-E-INVALID EXIT
    THEN
    _VSX-NA @ _VSX-NU @ _VSX-VA @ _VSX-VU @ _VSX-FLAGS @
    _VSX-IN @ _VSX-V @
    VFS-OP-SETXATTR _VSX-V @ _VFS-XT EXECUTE
    DUP IF _VSX-V @ _VFS-RESULT EXIT THEN DROP
    VFS-IF-DIRTY _VSX-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    VFS-F-DIRTY _VSX-V @ V.FLAGS DUP @ ROT OR SWAP !
    0 _VSX-V @ _VFS-RESULT ;

VARIABLE _VRX-NA
VARIABLE _VRX-NU
VARIABLE _VRX-IN
VARIABLE _VRX-V

: VFS-REMOVEXATTR  ( name-a name-u inode vfs -- ior )
    _VRX-V ! _VRX-IN ! _VRX-NU ! _VRX-NA !
    _VRX-IN @ 0= IF VFS-E-INVALID EXIT THEN
    _VRX-V @ _VFS-READY ?DUP IF EXIT THEN
    _VRX-IN @ _VRX-V @ _VFS-DENTRY-OWNED? 0= IF VFS-E-XDEV EXIT THEN
    _VRX-V @ V.FLAGS @ VFS-F-RO AND IF VFS-E-READONLY EXIT THEN
    VFS-OP-REMOVEXATTR _VRX-V @ _VFS-HAS-OP? 0= IF
        VFS-E-UNSUPPORTED EXIT
    THEN
    _VRX-NA @ _VRX-NU @ _VFS-XATTR-NAME? 0= IF VFS-E-INVALID EXIT THEN
    _VRX-NA @ _VRX-NU @ _VRX-IN @ _VRX-V @
    VFS-OP-REMOVEXATTR _VRX-V @ _VFS-XT EXECUTE
    DUP IF _VRX-V @ _VFS-RESULT EXIT THEN DROP
    VFS-IF-DIRTY _VRX-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    VFS-F-DIRTY _VRX-V @ V.FLAGS DUP @ ROT OR SWAP !
    0 _VRX-V @ _VFS-RESULT ;

VARIABLE _VSF-BUF
VARIABLE _VSF-SIZE
VARIABLE _VSF-V

: VFS-STATFS  ( statfs-buffer bytes vfs -- ior )
    _VSF-V ! _VSF-SIZE ! _VSF-BUF !
    _VSF-V @ _VFS-READY ?DUP IF EXIT THEN
    VFS-OP-STATFS _VSF-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VSF-SIZE @ VFS-STATFS-SIZE < IF VFS-E-OVERFLOW EXIT THEN
    _VSF-BUF @ _VSF-SIZE @ _VFS-BUFFER? 0= IF VFS-E-INVALID EXIT THEN
    _VSF-BUF @ _VSF-SIZE @ _VSF-V @
    VFS-OP-STATFS _VSF-V @ _VFS-XT EXECUTE
    _VSF-V @ _VFS-RESULT ;

\ =====================================================================
\  VFS-CREATE -- path-aware file creation
\ =====================================================================

VARIABLE _VCR-A
VARIABLE _VCR-U
VARIABLE _VCR-V
VARIABLE _VCR-OLD-V
VARIABLE _VCR-OLD-CWD
VARIABLE _VCR-SPLIT
VARIABLE _VCR-PARENT

: _VCR-RESTORE  ( -- )
    _VCR-OLD-CWD @ _VCR-V @ V.CWD !
    _VCR-OLD-V @ VFS-USE ;

\ VFS-CREATE ( path-a path-u vfs -- inode | 0 )
\   Create a file at an absolute or relative path.  Parent directories
\   must already exist.  Existing paths and trailing slashes fail.
: VFS-CREATE  ( path-a path-u vfs -- inode | 0 )
    _VCR-V ! _VCR-U ! _VCR-A !
    _VCR-V @ V.FLAGS @ VFS-F-RO AND IF 0 EXIT THEN
    _VCR-U @ 0= IF 0 EXIT THEN
    _VCR-A @ _VCR-U @ 1- + C@ [CHAR] / = IF 0 EXIT THEN
    VFS-CUR _VCR-OLD-V !
    _VCR-V @ V.CWD @ _VCR-OLD-CWD !
    _VCR-V @ VFS-USE
    _VCR-A @ _VCR-U @ _VCR-V @ VFS-RESOLVE ?DUP IF
        DROP _VCR-RESTORE 0 EXIT
    THEN
    -1 _VCR-SPLIT !
    _VCR-U @ 0 DO
        _VCR-A @ I + C@ [CHAR] / = IF I _VCR-SPLIT ! THEN
    LOOP
    _VCR-SPLIT @ 0< IF
        _VCR-OLD-CWD @ _VCR-PARENT !
    ELSE
        _VCR-SPLIT @ 0= IF
            _VCR-A @ 1
        ELSE
            _VCR-A @ _VCR-SPLIT @
        THEN
        _VCR-V @ VFS-RESOLVE
        DUP 0= IF DROP _VCR-RESTORE 0 EXIT THEN
        DUP IN.TYPE @ VFS-T-DIR <> IF DROP _VCR-RESTORE 0 EXIT THEN
        _VCR-PARENT !
    THEN
    _VCR-PARENT @ _VCR-V @ V.CWD !
    _VCR-SPLIT @ 0< IF
        _VCR-A @ _VCR-U @
    ELSE
        _VCR-A @ _VCR-SPLIT @ 1+ +
        _VCR-U @ _VCR-SPLIT @ 1+ -
    THEN
    _VCR-V @ VFS-MKFILE
    _VCR-RESTORE ;

VARIABLE _VRM-V
VARIABLE _VRM-IN
VARIABLE _VRM-IOR

: VFS-RM  ( c-addr u vfs -- ior )
    _VRM-V !
    _VRM-V @ _VFS-READY ?DUP IF >R 2DROP R> EXIT THEN
    _VRM-V @ V.FLAGS @ VFS-F-RO AND IF 2DROP VFS-E-READONLY EXIT THEN
    _VRM-V @ VFS-RESOLVE?
    DUP IF NIP EXIT THEN DROP _VRM-IN !
    \ Don't delete root
    _VRM-IN @ _VRM-V @ V.ROOT @ = IF VFS-E-INVALID EXIT THEN
    \ Don't delete non-empty directories
    _VRM-IN @ IN.TYPE @ VFS-T-DIR = IF
        VFS-OP-RMDIR _VRM-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
        _VRM-IN @ _VRM-V @ _VFS-ENSURE-CHILDREN? ?DUP IF EXIT THEN
        _VRM-IN @ IN.CHILD @ 0<> IF VFS-E-NOTEMPTY EXIT THEN
        VFS-OP-RMDIR
    ELSE
        VFS-OP-UNLINK _VRM-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
        VFS-OP-UNLINK
    THEN
    _VRM-IN @ _VRM-V @ ROT _VRM-V @ _VFS-XT EXECUTE
    DUP _VRM-IOR ! IF _VRM-IOR @ EXIT THEN
    \ Unlink from parent
    _VRM-IN @  _VRM-IN @ IN.PARENT @  _VFS-REMOVE-CHILD
    -1 _VRM-IN @ D.VNODE @ VN.NLINK +!
    _VRM-IN @ _VRM-V @ _VFS-DENTRY-HAS-FD? IF
        VFS-DF-UNLINKED _VRM-IN @ D.FLAGS !
    ELSE
        _VRM-IN @ FALSE _VRM-V @ _VFS-DENTRY-RELEASE
    THEN
    \ Decrement count
    _VRM-V @ V.ICOUNT DUP @ 1- SWAP !
    VFS-F-DIRTY _VRM-V @ V.FLAGS DUP @ ROT OR SWAP !
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

VARIABLE _VCD-A
VARIABLE _VCD-U
VARIABLE _VCD-V

: VFS-CD?  ( c-addr u vfs -- ior )
    _VCD-V ! _VCD-U ! _VCD-A !
    _VCD-V @ _VFS-READY ?DUP IF EXIT THEN
    _VCD-A @ _VCD-U @ _VCD-V @ VFS-RESOLVE?
    DUP IF NIP EXIT THEN DROP
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP VFS-E-NOTDIR EXIT THEN
    _VCD-V @ V.CWD ! 0 ;

: VFS-CD  ( c-addr u vfs -- ior )
    VFS-CD? IF -1 ELSE 0 THEN ;

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
\  VFS-SYNC — Binding-owned filesystem durability boundary
\ =====================================================================
\
\  ( vfs -- ior )
\
\  Calls SYNCFS once so the binding owns ordering, then clears cached dirty
\  observations only after success.

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
    _VSY-V @ _VFS-READY ?DUP IF EXIT THEN
    VFS-OP-SYNCFS _VSY-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VSY-V @ VFS-OP-SYNCFS _VSY-V @ _VFS-XT EXECUTE
    DUP IF _VSY-V @ _VFS-RESULT EXIT THEN DROP
    \ Binding-owned ordering and durability completed.  Only now may the
    \ generic cache clear dirty observations.
    _VSY-V @ V.ISLAB @  _VSY-P !      \ first slab page
    BEGIN  _VSY-P @ 0<>  WHILE
        _VFS-SLAB-SLOTS 0 DO
            _VSY-P @ 8 + I VFS-INODE-SIZE * +  _VSY-IN !
            _VSY-IN @ _VSY-V @  _VFS-INODE-IN-FREELIST?
            0= IF
                _VSY-IN @ IN.FLAGS @ VFS-IF-DIRTY INVERT AND
                _VSY-IN @ IN.FLAGS !
            THEN
        LOOP
        _VSY-P @ @ _VSY-P !
    REPEAT
    _VSY-V @ V.FLAGS @ VFS-F-DIRTY INVERT AND _VSY-V @ V.FLAGS !
    0 _VSY-V @ _VFS-RESULT ;

VARIABLE _VFY-FD
VARIABLE _VFY-V

: VFS-FSYNC  ( fd -- ior )
    DUP 0= IF DROP VFS-E-BADF EXIT THEN _VFY-FD !
    _VFY-FD @ FD.VFS @ DUP 0= IF DROP VFS-E-BADF EXIT THEN _VFY-V !
    _VFY-V @ _VFS-READY ?DUP IF EXIT THEN
    VFS-OP-FSYNC _VFY-V @ _VFS-HAS-OP? 0= IF VFS-E-UNSUPPORTED EXIT THEN
    _VFY-FD @ FD.INODE @ _VFY-V @
    VFS-OP-FSYNC _VFY-V @ _VFS-XT EXECUTE
    DUP IF _VFY-V @ _VFS-RESULT EXIT THEN DROP
    _VFY-FD @ FD.INODE @ IN.FLAGS @ VFS-IF-DIRTY INVERT AND
    _VFY-FD @ FD.INODE @ IN.FLAGS !
    0 _VFY-V @ _VFS-RESULT ;

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
    \ A single cached name may be removed only when targeted LOOKUP can
    \ reconstruct it.  READDIR-only bindings keep complete enumerations.
    VFS-OP-LOOKUP R@ _VFS-HAS-OP? 0= IF
        R> 2DROP FALSE EXIT
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
    DUP R@ _VFS-INODE-EVICT
    R@ V.ICOUNT DUP @ 1- SWAP !
    R> DROP DROP TRUE ;

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
    -1 _VIP-D @ 1-
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

\ VFS-TRANSACTION ( xt -- ... )
\   Execute an arbitrary multi-call VFS operation as one exclusion region.
\   The guarded build replaces this fallback with a recursive _vfs-guard
\   wrapper below.  Results and THROW behavior are those of xt.
: VFS-TRANSACTION  ( xt -- ... )
    EXECUTE ;

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
' VFS-PROBE        CONSTANT _vfs-probe-xt
' VFS-NEW          CONSTANT _vfs-new-xt
' VFS-DESTROY      CONSTANT _vfs-destroy-xt
' VFS-UNMOUNT      CONSTANT _vfs-unmount-xt
' VFS-RESOLVE      CONSTANT _vfs-resolve-xt
' VFS-RESOLVE?     CONSTANT _vfs-resolveq-xt
' VFS-OPEN         CONSTANT _vfs-open-xt
' VFS-OPEN?        CONSTANT _vfs-openq-xt
' VFS-CLOSE        CONSTANT _vfs-close-xt
' VFS-CLOSE?       CONSTANT _vfs-closeq-xt
' VFS-READ         CONSTANT _vfs-read-xt
' VFS-READ?        CONSTANT _vfs-readq-xt
' VFS-WRITE        CONSTANT _vfs-write-xt
' VFS-WRITE?       CONSTANT _vfs-writeq-xt
' VFS-READ-EXACT   CONSTANT _vfs-read-exact-xt
' VFS-WRITE-EXACT  CONSTANT _vfs-write-exact-xt
' VFS-SEEK?        CONSTANT _vfs-seekq-xt
' VFS-SEEK         CONSTANT _vfs-seek-xt
' VFS-REWIND       CONSTANT _vfs-rewind-xt
' VFS-TELL         CONSTANT _vfs-tell-xt
' VFS-SIZE         CONSTANT _vfs-size-xt
' VFS-TRUNCATE     CONSTANT _vfs-truncate-xt
' VFS-MKFILE       CONSTANT _vfs-mkfile-xt
' VFS-CREATE       CONSTANT _vfs-create-xt
' VFS-MKDIR        CONSTANT _vfs-mkdir-xt
' VFS-RENAME       CONSTANT _vfs-rename-xt
' VFS-RENAME-AT    CONSTANT _vfs-rename-at-xt
' VFS-LINK         CONSTANT _vfs-link-xt
' VFS-CACHE-DENTRY CONSTANT _vfs-cache-dentry-xt
' VFS-CACHE-DROP   CONSTANT _vfs-cache-drop-xt
' VFS-LOOKUP       CONSTANT _vfs-lookup-xt
' VFS-GETATTR      CONSTANT _vfs-getattr-xt
' VFS-SETATTR      CONSTANT _vfs-setattr-xt
' VFS-SYMLINK      CONSTANT _vfs-symlink-xt
' VFS-READLINK     CONSTANT _vfs-readlink-xt
' VFS-LISTXATTR    CONSTANT _vfs-listxattr-xt
' VFS-GETXATTR     CONSTANT _vfs-getxattr-xt
' VFS-SETXATTR     CONSTANT _vfs-setxattr-xt
' VFS-REMOVEXATTR  CONSTANT _vfs-removexattr-xt
' VFS-STATFS       CONSTANT _vfs-statfs-xt
' VFS-RM           CONSTANT _vfs-rm-xt
' VFS-DIR          CONSTANT _vfs-dir-xt
' VFS-CD?          CONSTANT _vfs-cdq-xt
' VFS-CD           CONSTANT _vfs-cd-xt
' VFS-STAT         CONSTANT _vfs-stat-xt
' VFS-SYNC         CONSTANT _vfs-sync-xt
' VFS-FSYNC        CONSTANT _vfs-fsync-xt
' VFS-SET-HWM      CONSTANT _vfs-set-hwm-xt
' VFS-INODE-PATH   CONSTANT _vfs-inode-path-xt
' VFS-TRANSACTION  CONSTANT _vfs-transaction-xt

: VFS-USE          _vfs-use-xt      _vfs-guard WITH-GUARD ;
: VFS-CUR          _vfs-cur-xt      _vfs-guard WITH-GUARD ;
: VFS-PROBE        _vfs-probe-xt    _vfs-guard WITH-GUARD ;
: VFS-NEW          _vfs-new-xt      _vfs-guard WITH-GUARD ;
: VFS-DESTROY      _vfs-destroy-xt  _vfs-guard WITH-GUARD ;
: VFS-UNMOUNT      _vfs-unmount-xt  _vfs-guard WITH-GUARD ;
: VFS-RESOLVE      _vfs-resolve-xt  _vfs-guard WITH-GUARD ;
: VFS-RESOLVE?     _vfs-resolveq-xt _vfs-guard WITH-GUARD ;
: VFS-OPEN         _vfs-open-xt     _vfs-guard WITH-GUARD ;
: VFS-OPEN?        _vfs-openq-xt    _vfs-guard WITH-GUARD ;
: VFS-CLOSE        _vfs-close-xt    _vfs-guard WITH-GUARD ;
: VFS-CLOSE?       _vfs-closeq-xt   _vfs-guard WITH-GUARD ;
: VFS-READ         _vfs-read-xt     _vfs-guard WITH-GUARD ;
: VFS-READ?        _vfs-readq-xt    _vfs-guard WITH-GUARD ;
: VFS-WRITE        _vfs-write-xt    _vfs-guard WITH-GUARD ;
: VFS-WRITE?       _vfs-writeq-xt   _vfs-guard WITH-GUARD ;
: VFS-READ-EXACT   _vfs-read-exact-xt _vfs-guard WITH-GUARD ;
: VFS-WRITE-EXACT  _vfs-write-exact-xt _vfs-guard WITH-GUARD ;
: VFS-SEEK?        _vfs-seekq-xt    _vfs-guard WITH-GUARD ;
: VFS-SEEK         _vfs-seek-xt     _vfs-guard WITH-GUARD ;
: VFS-REWIND       _vfs-rewind-xt   _vfs-guard WITH-GUARD ;
: VFS-TELL         _vfs-tell-xt     _vfs-guard WITH-GUARD ;
: VFS-SIZE         _vfs-size-xt     _vfs-guard WITH-GUARD ;
: VFS-TRUNCATE     _vfs-truncate-xt _vfs-guard WITH-GUARD ;
: VFS-MKFILE       _vfs-mkfile-xt   _vfs-guard WITH-GUARD ;
: VFS-CREATE       _vfs-create-xt   _vfs-guard WITH-GUARD ;
: VFS-MKDIR        _vfs-mkdir-xt    _vfs-guard WITH-GUARD ;
: VFS-RENAME       _vfs-rename-xt   _vfs-guard WITH-GUARD ;
: VFS-RENAME-AT    _vfs-rename-at-xt _vfs-guard WITH-GUARD ;
: VFS-LINK         _vfs-link-xt     _vfs-guard WITH-GUARD ;
: VFS-CACHE-DENTRY _vfs-cache-dentry-xt _vfs-guard WITH-GUARD ;
: VFS-CACHE-DROP   _vfs-cache-drop-xt _vfs-guard WITH-GUARD ;
: VFS-LOOKUP       _vfs-lookup-xt   _vfs-guard WITH-GUARD ;
: VFS-GETATTR      _vfs-getattr-xt  _vfs-guard WITH-GUARD ;
: VFS-SETATTR      _vfs-setattr-xt  _vfs-guard WITH-GUARD ;
: VFS-SYMLINK      _vfs-symlink-xt  _vfs-guard WITH-GUARD ;
: VFS-READLINK     _vfs-readlink-xt _vfs-guard WITH-GUARD ;
: VFS-LISTXATTR    _vfs-listxattr-xt _vfs-guard WITH-GUARD ;
: VFS-GETXATTR     _vfs-getxattr-xt _vfs-guard WITH-GUARD ;
: VFS-SETXATTR     _vfs-setxattr-xt _vfs-guard WITH-GUARD ;
: VFS-REMOVEXATTR  _vfs-removexattr-xt _vfs-guard WITH-GUARD ;
: VFS-STATFS       _vfs-statfs-xt   _vfs-guard WITH-GUARD ;
: VFS-RM           _vfs-rm-xt       _vfs-guard WITH-GUARD ;
: VFS-DIR          _vfs-dir-xt      _vfs-guard WITH-GUARD ;
: VFS-CD?          _vfs-cdq-xt      _vfs-guard WITH-GUARD ;
: VFS-CD           _vfs-cd-xt       _vfs-guard WITH-GUARD ;
: VFS-STAT         _vfs-stat-xt     _vfs-guard WITH-GUARD ;
: VFS-SYNC         _vfs-sync-xt     _vfs-guard WITH-GUARD ;
: VFS-FSYNC        _vfs-fsync-xt    _vfs-guard WITH-GUARD ;
: VFS-SET-HWM      _vfs-set-hwm-xt  _vfs-guard WITH-GUARD ;
: VFS-INODE-PATH   _vfs-inode-path-xt _vfs-guard WITH-GUARD ;
: VFS-TRANSACTION  _vfs-transaction-xt _vfs-guard WITH-GUARD ;

[THEN] [THEN]
