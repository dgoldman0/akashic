\ vfs-mp64fs.f — MP64FS binding for the VFS layer
\
\ Bridges the abstract VFS to the Megapad-64 native filesystem
\ (MP64FS).  All byte transfer goes through the BIOS disk
\ primitives (DISK-SEC!, DISK-DMA!, DISK-N!, DISK-READ,
\ DISK-WRITE) which are already defined by KDOS.
\
\ Prefix: VMP-   (public API)
\         _VMP-  (internal helpers)
\
\ Load with:   REQUIRE utils/fs/drivers/vfs-mp64fs.f

PROVIDED akashic-vfs-mp64fs
REQUIRE ../vfs.f

\ =====================================================================
\  On-disk constants (must match diskutil.py & kdos.f §7.6)
\ =====================================================================

512  CONSTANT _VMP-SECTOR
14   CONSTANT _VMP-DATA-START
128  CONSTANT _VMP-MAX-FILES
48   CONSTANT _VMP-ENTRY-SIZE
12   CONSTANT _VMP-DIR-SECTORS
255  CONSTANT _VMP-ROOT-PARENT     \ parent=0xFF means root dir

\ File types
0 CONSTANT _VMP-T-FREE
1 CONSTANT _VMP-T-RAW
8 CONSTANT _VMP-T-DIR

\ =====================================================================
\  Binding Context Layout
\ =====================================================================
\
\  Allocated from the VFS arena by VMP-INIT, stored in V.BCTX.
\
\    +0      superblock cache   (512 bytes)
\    +512    bitmap cache        (512 bytes)
\    +1024   directory cache     (128 × 48 = 6144 bytes)
\    +7168   scratch buffer      (512 bytes)
\    +7680   total-sectors cell  (8 bytes)
\    +7688   data-start cell     (8 bytes)
\    +7696   dirty-bmap flag     (8 bytes)
\    +7704   dirty-dir flag      (8 bytes)
\  = 7712 bytes

7712 CONSTANT _VMP-CTX-SIZE

\ Context field offsets
   0 CONSTANT _VMP-C.SUPER
 512 CONSTANT _VMP-C.BMAP
1024 CONSTANT _VMP-C.DIR
7168 CONSTANT _VMP-C.SCRATCH
7680 CONSTANT _VMP-C.TOTAL
7688 CONSTANT _VMP-C.DSTART
7696 CONSTANT _VMP-C.DBMAP
7704 CONSTANT _VMP-C.DDIR

\ Accessor: ( vfs -- ctx )
: _VMP-CTX  ( vfs -- ctx )  V.BCTX @ ;

\ =====================================================================
\  Directory Entry Field Readers (operate on dir-cache address)
\ =====================================================================

: _VMP-DE.SEC    ( de -- u16 )    24 + W@ ;
: _VMP-DE.COUNT  ( de -- u16 )    26 + W@ ;
: _VMP-DE.USED   ( de -- u32 )    28 + L@ ;
: _VMP-DE.TYPE   ( de -- u8 )     32 + C@ ;
: _VMP-DE.FLAGS  ( de -- u8 )     33 + C@ ;
: _VMP-DE.PARENT ( de -- u8 )     34 + C@ ;
: _VMP-DE.EXT1S  ( de -- u16 )    44 + W@ ;
: _VMP-DE.EXT1C  ( de -- u16 )    46 + W@ ;

\ Dirent address from slot index + ctx
: _VMP-DIRENT  ( slot ctx -- de )
    _VMP-C.DIR +  SWAP _VMP-ENTRY-SIZE * + ;

\ Name length of a directory entry (find NUL within 24 bytes)
VARIABLE _VMP-NL
: _VMP-NAMELEN  ( de -- len )
    24 _VMP-NL !
    24 0 DO
        DUP I + C@ 0= IF I _VMP-NL ! LEAVE THEN
    LOOP
    DROP _VMP-NL @ ;

\ =====================================================================
\  Bitmap Helpers (operate on ctx bitmap cache)
\ =====================================================================

: _VMP-BIT-FREE?  ( sector ctx -- flag )
    _VMP-C.BMAP +                     ( sector bmap )
    SWAP DUP 8 / ROT +  C@           ( sector byte-val )
    SWAP 8 MOD 1 SWAP LSHIFT         ( byte-val mask )
    AND 0= ;

: _VMP-BIT-SET  ( sector ctx -- )
    _VMP-C.BMAP +                     ( sector bmap )
    SWAP DUP 8 /  ROT +              ( sector bmap-byte-addr )
    DUP C@                            ( sector addr val )
    ROT 8 MOD 1 SWAP LSHIFT          ( addr val mask )
    OR SWAP C! ;

: _VMP-BIT-CLR  ( sector ctx -- )
    _VMP-C.BMAP +
    SWAP DUP 8 /  ROT +
    DUP C@
    ROT 8 MOD 1 SWAP LSHIFT
    INVERT AND SWAP C! ;

\ =====================================================================
\  Probe  ( sector-0-buf vfs -- flag )
\ =====================================================================
\
\  Check that the first 4 bytes are "MP64" (M=77, P=80, 6=54, 4=52).

: _VMP-PROBE  ( buf vfs -- flag )
    DROP
    DUP     C@  77 = IF
    DUP 1+  C@  80 = IF
    DUP 2 + C@  54 = IF
        3 + C@  52 =
        EXIT
    THEN THEN THEN
    DROP FALSE ;

\ =====================================================================
\  Init  ( vfs -- ior )
\ =====================================================================
\
\  Allocate binding-ctx from the VFS's arena.  DMA-read the
\  superblock (sector 0), bitmap (sector 1), and directory
\  (sectors 2–13) into the context caches.  Parse geometry
\  fields from the superblock.

VARIABLE _VMI-V
VARIABLE _VMI-CTX

: _VMP-INIT  ( vfs -- ior )
    _VMI-V !
    \ Check disk present
    DISK? 0= IF  -1 EXIT  THEN
    \ Allocate context
    _VMI-V @ V.ARENA @  _VMP-CTX-SIZE ARENA-ALLOT  _VMI-CTX !
    \ Zero it
    _VMI-CTX @  _VMP-CTX-SIZE  0 FILL
    \ Store in VFS descriptor
    _VMI-CTX @  _VMI-V @ V.BCTX !
    \ Read superblock (sector 0)
    0 DISK-SEC!
    _VMI-CTX @ _VMP-C.SUPER +  DISK-DMA!
    1 DISK-N!  DISK-READ
    \ Verify magic
    _VMI-CTX @ _VMP-C.SUPER +  _VMI-V @  _VMP-PROBE 0= IF
        -2 EXIT   \ not MP64FS
    THEN
    \ Parse geometry from superblock
    _VMI-CTX @ _VMP-C.SUPER + 6 + L@      \ total_sectors (u32 at +6)
    _VMI-CTX @ _VMP-C.TOTAL + !
    _VMI-CTX @ _VMP-C.SUPER + 18 + W@     \ data_start (u16 at +18)
    _VMI-CTX @ _VMP-C.DSTART + !
    \ Read bitmap (sector 1)
    1 DISK-SEC!
    _VMI-CTX @ _VMP-C.BMAP +  DISK-DMA!
    1 DISK-N!  DISK-READ
    \ Read directory (sectors 2–13)
    2 DISK-SEC!
    _VMI-CTX @ _VMP-C.DIR +  DISK-DMA!
    _VMP-DIR-SECTORS DISK-N!  DISK-READ
    \ Clear dirty flags
    0 _VMI-CTX @ _VMP-C.DBMAP + !
    0 _VMI-CTX @ _VMP-C.DDIR + !
    0 ;   \ success

\ =====================================================================
\  VMP-INIT — public wrapper (calls _VMP-INIT + populates root)
\ =====================================================================
\
\  After init, scan the directory for root-level entries and create
\  child inodes under the VFS root.

VARIABLE _VMPI-V
VARIABLE _VMPI-CTX

: VMP-INIT  ( vfs -- ior )
    DUP _VMP-INIT               ( vfs ior )
    DUP 0<> IF  NIP EXIT  THEN  \ init failed
    DROP                         ( vfs )
    \ Now populate root directory children
    DUP V.BCTX @  _VMPI-CTX !
    _VMPI-V !
    _VMP-MAX-FILES 0 DO
        I _VMPI-CTX @  _VMP-DIRENT   ( de )
        DUP C@ 0<> IF                \ slot occupied?
            DUP _VMP-DE.PARENT _VMP-ROOT-PARENT = IF   \ root child?
                \ Determine VFS inode type
                DUP _VMP-DE.TYPE _VMP-T-DIR = IF
                    VFS-T-DIR
                ELSE
                    VFS-T-FILE
                THEN                          ( de vfs-type )
                _VMPI-V @  _VFS-INODE-ALLOC   ( de inode )
                \ Set name from dir entry (NUL-terminated, max 24 bytes)
                OVER _VMP-NAMELEN             ( de inode namelen )
                >R OVER R>                    ( de inode de namelen )
                _VMPI-V @  _VFS-STR-ALLOC     ( de inode handle )
                OVER IN.NAME !
                \ Set binding-id = slot index
                I OVER IN.BID !
                \ Set bdata-0 = start_sector, bdata-1 = sec_count
                OVER _VMP-DE.SEC   OVER IN.BDATA !
                OVER _VMP-DE.COUNT OVER IN.BDATA 8 + !
                \ Set file size
                OVER _VMP-DE.USED  OVER IN.SIZE-LO !
                0                  OVER IN.SIZE-HI !
                \ If directory, mark children NOT loaded yet
                DUP IN.TYPE @ VFS-T-DIR = IF
                    0 OVER IN.FLAGS !
                ELSE
                    0 OVER IN.FLAGS !
                THEN
                \ Add to root's child list
                DUP _VMPI-V @ V.ROOT @  _VFS-ADD-CHILD
                \ Bump inode count
                _VMPI-V @ V.ICOUNT DUP @ 1+ SWAP !
                DROP                          ( de )
            THEN
        THEN
        DROP                                  ( )
    LOOP
    \ Mark root as children-loaded
    VFS-IF-CHILDREN
    _VMPI-V @ V.ROOT @ IN.FLAGS DUP @ ROT OR SWAP !
    0 ;   \ success

\ =====================================================================
\  Readdir  ( inode vfs -- )
\ =====================================================================
\
\  For a directory inode, scan the MP64FS directory table for entries
\  whose parent slot matches the inode's binding-id.  Create child
\  inodes for each match.

VARIABLE _VMRD-IN
VARIABLE _VMRD-V
VARIABLE _VMRD-CTX
VARIABLE _VMRD-PID    \ parent dir slot to match

: _VMP-READDIR  ( inode vfs -- )
    _VMRD-V !  _VMRD-IN !
    _VMRD-V @ V.BCTX @  _VMRD-CTX !
    \ The parent slot to match = this inode's binding-id
    _VMRD-IN @ IN.BID @  _VMRD-PID !
    _VMP-MAX-FILES 0 DO
        I _VMRD-CTX @  _VMP-DIRENT   ( de )
        DUP C@ 0<> IF                \ slot occupied?
            DUP _VMP-DE.PARENT        ( de parent )
            _VMRD-PID @ = IF          \ matches our dir?
                DUP _VMP-DE.TYPE _VMP-T-DIR = IF
                    VFS-T-DIR
                ELSE
                    VFS-T-FILE
                THEN                          ( de vfs-type )
                _VMRD-V @  _VFS-INODE-ALLOC   ( de inode )
                OVER _VMP-NAMELEN             ( de inode namelen )
                >R OVER R>                    ( de inode de namelen )
                _VMRD-V @  _VFS-STR-ALLOC
                OVER IN.NAME !
                I OVER IN.BID !
                OVER _VMP-DE.SEC   OVER IN.BDATA !
                OVER _VMP-DE.COUNT OVER IN.BDATA 8 + !
                OVER _VMP-DE.USED  OVER IN.SIZE-LO !
                0                  OVER IN.SIZE-HI !
                DUP IN.TYPE @ VFS-T-DIR = IF
                    0 OVER IN.FLAGS !
                ELSE
                    0 OVER IN.FLAGS !
                THEN
                DUP _VMRD-IN @  _VFS-ADD-CHILD
                _VMRD-V @ V.ICOUNT DUP @ 1+ SWAP !
                DROP
            THEN
        THEN
        DROP
    LOOP ;

\ =====================================================================
\  Read  ( buf len offset inode vfs -- actual )
\ =====================================================================
\
\  Translate inode bdata (start_sector + sec_count) into disk DMA
\  reads.  Handle partial head/tail sectors via the ctx scratch
\  buffer.  Multi-extent support via ext1.

VARIABLE _VMRR-BUF
VARIABLE _VMRR-LEN
VARIABLE _VMRR-OFF
VARIABLE _VMRR-IN
VARIABLE _VMRR-V
VARIABLE _VMRR-CTX
VARIABLE _VMRR-REM     \ remaining bytes
VARIABLE _VMRR-POS     \ current byte position within file data
VARIABLE _VMRR-SSEC    \ start sector of current extent
VARIABLE _VMRR-NSEC    \ sector count of current extent
VARIABLE _VMRR-ACT     \ actual bytes read so far
VARIABLE _VMRR-SCR     \ scratch buffer address

\ Helper: disk sector for a byte position within a single extent
: _VMRR-DSEC  ( -- sec )
    _VMRR-POS @ _VMP-SECTOR /  _VMRR-SSEC @ + ;

\ Helper: read head partial sector
VARIABLE _VMRR-CHUNK
: _VMRR-HEAD  ( -- )
    _VMRR-POS @ _VMP-SECTOR MOD  DUP 0= IF DROP EXIT THEN  ( off )
    _VMRR-DSEC DISK-SEC!
    _VMRR-SCR @ DISK-DMA!  1 DISK-N!  DISK-READ
    _VMP-SECTOR OVER -  _VMRR-REM @ MIN  _VMRR-CHUNK !  ( off )
    _VMRR-SCR @ +  _VMRR-BUF @  _VMRR-CHUNK @  CMOVE
    _VMRR-CHUNK @ DUP _VMRR-BUF +!  DUP _VMRR-POS +!
    DUP _VMRR-ACT +!  NEGATE _VMRR-REM +! ;

\ Helper: DMA full sectors
: _VMRR-FULL  ( -- )
    _VMRR-REM @ _VMP-SECTOR /  ( n-full )
    BEGIN DUP 0> WHILE
        _VMRR-DSEC DISK-SEC!
        _VMRR-BUF @ DISK-DMA!
        DUP 255 MIN             ( n-full batch )
        DUP DISK-N!  DISK-READ
        DUP _VMP-SECTOR *
        DUP _VMRR-BUF +!
        DUP _VMRR-POS +!
        DUP _VMRR-ACT +!
        NEGATE _VMRR-REM +!
        -
    REPEAT DROP ;

\ Helper: read tail partial sector
: _VMRR-TAIL  ( -- )
    _VMRR-REM @ 0= IF EXIT THEN
    _VMRR-DSEC DISK-SEC!
    _VMRR-SCR @ DISK-DMA!  1 DISK-N!  DISK-READ
    _VMRR-SCR @  _VMRR-BUF @  _VMRR-REM @  CMOVE
    _VMRR-REM @ DUP _VMRR-ACT +!
    DUP _VMRR-BUF +!  _VMRR-POS +! ;

: _VMP-READ  ( buf len offset inode vfs -- actual )
    _VMRR-V !  _VMRR-IN !  _VMRR-OFF !  _VMRR-LEN !  _VMRR-BUF !
    _VMRR-V @ V.BCTX @  _VMRR-CTX !
    _VMRR-CTX @ _VMP-C.SCRATCH +  _VMRR-SCR !
    0 _VMRR-ACT !
    \ Clamp len to file size - offset
    _VMRR-IN @ IN.SIZE-LO @  _VMRR-OFF @ -
    DUP 0< IF  DROP 0 EXIT  THEN   \ offset past EOF
    _VMRR-LEN @ MIN  _VMRR-LEN !
    _VMRR-LEN @ 0= IF  0 EXIT  THEN
    \ Set up extent: primary extent first
    _VMRR-IN @ IN.BDATA @      _VMRR-SSEC !   \ start_sector
    _VMRR-IN @ IN.BDATA 8 + @  _VMRR-NSEC !   \ sec_count
    _VMRR-OFF @  _VMRR-POS !
    _VMRR-LEN @  _VMRR-REM !
    \ For simplicity, this binding handles the primary extent only.
    \ Multi-extent files (ext1) can be added later.
    _VMRR-HEAD  _VMRR-FULL  _VMRR-TAIL
    _VMRR-ACT @ ;

\ =====================================================================
\  Write  ( buf len offset inode vfs -- actual )
\ =====================================================================

VARIABLE _VMRW-BUF
VARIABLE _VMRW-LEN
VARIABLE _VMRW-OFF
VARIABLE _VMRW-IN
VARIABLE _VMRW-V
VARIABLE _VMRW-CTX
VARIABLE _VMRW-REM
VARIABLE _VMRW-POS
VARIABLE _VMRW-SSEC
VARIABLE _VMRW-NSEC
VARIABLE _VMRW-ACT
VARIABLE _VMRW-SCR

: _VMRW-DSEC  ( -- sec )
    _VMRW-POS @ _VMP-SECTOR /  _VMRW-SSEC @ + ;

VARIABLE _VMRW-CHUNK
: _VMRW-HEAD  ( -- )
    _VMRW-POS @ _VMP-SECTOR MOD  DUP 0= IF DROP EXIT THEN
    _VMRW-DSEC DISK-SEC!
    _VMRW-SCR @ DISK-DMA!  1 DISK-N!  DISK-READ
    _VMP-SECTOR OVER -  _VMRW-REM @ MIN  _VMRW-CHUNK !
    _VMRW-BUF @  OVER _VMRW-SCR @ +  _VMRW-CHUNK @  CMOVE
    DROP
    _VMRW-DSEC DISK-SEC!
    _VMRW-SCR @ DISK-DMA!  1 DISK-N!  DISK-WRITE
    _VMRW-CHUNK @ DUP _VMRW-BUF +!  DUP _VMRW-POS +!
    DUP _VMRW-ACT +!  NEGATE _VMRW-REM +! ;

: _VMRW-FULL  ( -- )
    _VMRW-REM @ _VMP-SECTOR /
    BEGIN DUP 0> WHILE
        _VMRW-DSEC DISK-SEC!
        _VMRW-BUF @ DISK-DMA!
        DUP 255 MIN
        DUP DISK-N!  DISK-WRITE
        DUP _VMP-SECTOR *
        DUP _VMRW-BUF +!
        DUP _VMRW-POS +!
        DUP _VMRW-ACT +!
        NEGATE _VMRW-REM +!
        -
    REPEAT DROP ;

: _VMRW-TAIL  ( -- )
    _VMRW-REM @ 0= IF EXIT THEN
    _VMRW-DSEC DISK-SEC!
    _VMRW-SCR @ DISK-DMA!  1 DISK-N!  DISK-READ
    _VMRW-BUF @  _VMRW-SCR @  _VMRW-REM @  CMOVE
    _VMRW-DSEC DISK-SEC!
    _VMRW-SCR @ DISK-DMA!  1 DISK-N!  DISK-WRITE
    _VMRW-REM @ DUP _VMRW-ACT +!
    DUP _VMRW-BUF +!  _VMRW-POS +! ;

: _VMP-WRITE  ( buf len offset inode vfs -- actual )
    _VMRW-V !  _VMRW-IN !  _VMRW-OFF !  _VMRW-LEN !  _VMRW-BUF !
    _VMRW-V @ V.BCTX @  _VMRW-CTX !
    _VMRW-CTX @ _VMP-C.SCRATCH +  _VMRW-SCR !
    0 _VMRW-ACT !
    \ Bounds check: offset + len must fit in allocated sectors
    _VMRW-IN @ IN.BDATA 8 + @  _VMP-SECTOR *   ( capacity )
    _VMRW-OFF @ _VMRW-LEN @ +  OVER > IF
        \ Clamp to capacity
        _VMRW-OFF @ -  0 MAX  _VMRW-LEN !
    ELSE DROP THEN
    _VMRW-LEN @ 0= IF  0 EXIT  THEN
    _VMRW-IN @ IN.BDATA @      _VMRW-SSEC !
    _VMRW-IN @ IN.BDATA 8 + @  _VMRW-NSEC !
    _VMRW-OFF @  _VMRW-POS !
    _VMRW-LEN @  _VMRW-REM !
    _VMRW-HEAD  _VMRW-FULL  _VMRW-TAIL
    \ Update dir cache: used_bytes = max(old, offset+len)
    _VMRW-OFF @ _VMRW-ACT @ +   ( new-end )
    _VMRW-IN @ IN.BID @  _VMRW-CTX @  _VMP-DIRENT  ( new-end de )
    DUP _VMP-DE.USED  ROT MAX                       ( de new-used )
    OVER 28 + L!                                     \ update dir cache
    \ Mark dir dirty
    -1 _VMRW-CTX @ _VMP-C.DDIR + !
    \ Update inode size-lo
    _VMRW-IN @ IN.BID @  _VMRW-CTX @  _VMP-DIRENT  _VMP-DE.USED
    _VMRW-IN @ IN.SIZE-LO !
    \ Mark inode dirty
    VFS-IF-DIRTY  _VMRW-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    _VMRW-ACT @ ;

\ =====================================================================
\  Sync  ( inode vfs -- ior )
\ =====================================================================
\
\  Write the bitmap and directory caches back to disk if dirty.

VARIABLE _VMSY-V
VARIABLE _VMSY-CTX

: _VMP-SYNC  ( inode vfs -- ior )
    _VMSY-V !  DROP      \ inode ignored; we sync globally
    _VMSY-V @ V.BCTX @  _VMSY-CTX !
    _VMSY-CTX @ 0= IF  -1 EXIT  THEN
    \ Write bitmap if dirty
    _VMSY-CTX @ _VMP-C.DBMAP + @ IF
        1 DISK-SEC!
        _VMSY-CTX @ _VMP-C.BMAP + DISK-DMA!
        1 DISK-N!  DISK-WRITE
        0 _VMSY-CTX @ _VMP-C.DBMAP + !
    THEN
    \ Write directory if dirty
    _VMSY-CTX @ _VMP-C.DDIR + @ IF
        2 DISK-SEC!
        _VMSY-CTX @ _VMP-C.DIR + DISK-DMA!
        _VMP-DIR-SECTORS DISK-N!  DISK-WRITE
        0 _VMSY-CTX @ _VMP-C.DDIR + !
    THEN
    0 ;

\ =====================================================================
\  Create  ( inode vfs -- ior )
\ =====================================================================
\
\  Allocate a directory slot and disk sectors for a newly created
\  inode.  The VFS layer has already allocated the inode and set
\  its name; we fill in the on-disk structures.

VARIABLE _VMCR-IN
VARIABLE _VMCR-V
VARIABLE _VMCR-CTX
VARIABLE _VMCR-SLOT
VARIABLE _VMCR-NSEC

: _VMP-FIND-FREE-SLOT  ( ctx -- slot | -1 )
    >R -1
    _VMP-MAX-FILES 0 DO
        I R@ _VMP-DIRENT  C@ 0= IF
            DROP I LEAVE
        THEN
    LOOP
    R> DROP ;

\ FIND-FREE-RUN: find contiguous free sectors in bitmap
VARIABLE _VMFF-NEED
VARIABLE _VMFF-START
VARIABLE _VMFF-LEN
VARIABLE _VMFF-CTX
VARIABLE _VMFF-TOTAL

: _VMP-FIND-FREE  ( count ctx -- sector | -1 )
    _VMFF-CTX !  _VMFF-NEED !
    _VMFF-CTX @ _VMP-C.DSTART + @  _VMFF-START !
    0 _VMFF-LEN !
    _VMFF-CTX @ _VMP-C.TOTAL + @   _VMFF-TOTAL !
    -1   \ default result
    _VMFF-TOTAL @  _VMFF-CTX @ _VMP-C.DSTART + @  DO
        I _VMFF-CTX @  _VMP-BIT-FREE? IF
            _VMFF-LEN @ 0= IF  I _VMFF-START !  THEN
            1 _VMFF-LEN +!
            _VMFF-LEN @ _VMFF-NEED @ >= IF
                DROP _VMFF-START @
                LEAVE
            THEN
        ELSE
            0 _VMFF-LEN !
        THEN
    LOOP ;

: _VMP-CREATE  ( inode vfs -- ior )
    _VMCR-V !  _VMCR-IN !
    _VMCR-V @ V.BCTX @  _VMCR-CTX !
    \ Find free dir slot
    _VMCR-CTX @ _VMP-FIND-FREE-SLOT  _VMCR-SLOT !
    _VMCR-SLOT @ -1 = IF  -1 EXIT  THEN  \ directory full
    \ Determine sector allocation
    _VMCR-IN @ IN.TYPE @ VFS-T-DIR = IF
        0 _VMCR-NSEC !   \ directories don't get data sectors
    ELSE
        \ Default: allocate 2 sectors for a new file (1 KiB)
        2 _VMCR-NSEC !
        _VMCR-NSEC @ _VMCR-CTX @  _VMP-FIND-FREE  ( sector | -1 )
        DUP -1 = IF
            \ Try 1 sector
            DROP 1 _VMCR-NSEC !
            _VMCR-NSEC @ _VMCR-CTX @  _VMP-FIND-FREE
            DUP -1 = IF
                DROP -2 EXIT   \ no space
            THEN
        THEN
        _VMCR-IN @ IN.BDATA !           \ bdata-0 = start_sector
        _VMCR-NSEC @  _VMCR-IN @ IN.BDATA 8 + !  \ bdata-1 = sec_count
        \ Mark sectors allocated in bitmap
        _VMCR-NSEC @ 0 DO
            _VMCR-IN @ IN.BDATA @ I +  _VMCR-CTX @  _VMP-BIT-SET
        LOOP
        -1 _VMCR-CTX @ _VMP-C.DBMAP + !   \ bitmap dirty
    THEN
    \ Build directory entry
    _VMCR-SLOT @  _VMCR-CTX @  _VMP-DIRENT  ( de )
    DUP _VMP-ENTRY-SIZE 0 FILL
    \ Copy name from inode's string handle
    _VMCR-IN @ IN.NAME @  _VFS-STR-GET     ( de addr len )
    23 MIN                                  ( de addr len' )
    >R OVER R> CMOVE                        ( de )
    \ Set fields
    _VMCR-IN @ IN.BDATA @   OVER 24 + W!   \ start_sector
    _VMCR-NSEC @             OVER 26 + W!   \ sec_count
    0                        OVER 28 + L!   \ used_bytes = 0
    _VMCR-IN @ IN.TYPE @ VFS-T-DIR = IF
        _VMP-T-DIR
    ELSE
        _VMP-T-RAW
    THEN                     OVER 32 + C!   \ type
    0                        OVER 33 + C!   \ flags
    \ Parent: find the parent inode's binding-id
    _VMCR-IN @ IN.PARENT @  DUP 0<> IF
        DUP  _VMCR-V @ V.ROOT @  = IF
            DROP _VMP-ROOT-PARENT
        ELSE
            IN.BID @
        THEN
    ELSE
        DROP _VMP-ROOT-PARENT
    THEN                     OVER 34 + C!   \ parent slot
    DROP
    \ Set inode binding-id = slot
    _VMCR-SLOT @  _VMCR-IN @ IN.BID !
    \ Mark dir dirty
    -1 _VMCR-CTX @ _VMP-C.DDIR + !
    0 ;

\ =====================================================================
\  Delete  ( inode vfs -- ior )
\ =====================================================================

VARIABLE _VMDL-IN
VARIABLE _VMDL-V
VARIABLE _VMDL-CTX

: _VMP-DELETE  ( inode vfs -- ior )
    _VMDL-V !  _VMDL-IN !
    _VMDL-V @ V.BCTX @  _VMDL-CTX !
    \ Free bitmap sectors (primary extent)
    _VMDL-IN @ IN.BDATA 8 + @  0 DO     \ sec_count iterations
        _VMDL-IN @ IN.BDATA @ I +  _VMDL-CTX @  _VMP-BIT-CLR
    LOOP
    -1 _VMDL-CTX @ _VMP-C.DBMAP + !     \ bitmap dirty
    \ Clear directory entry
    _VMDL-IN @ IN.BID @  _VMDL-CTX @  _VMP-DIRENT
    _VMP-ENTRY-SIZE 0 FILL
    -1 _VMDL-CTX @ _VMP-C.DDIR + !      \ dir dirty
    0 ;

\ =====================================================================
\  Truncate  ( inode vfs -- ior )
\ =====================================================================
\
\  Set used_bytes in the dir cache to inode's size-lo.

: _VMP-TRUNCATE  ( inode vfs -- ior )
    V.BCTX @  SWAP                       ( ctx inode )
    DUP IN.BID @  ROT  _VMP-DIRENT      ( inode de )
    OVER IN.SIZE-LO @  SWAP 28 + L!     \ update used_bytes
    DROP  0 ;

\ =====================================================================
\  Teardown  ( vfs -- )
\ =====================================================================
\
\  Flush all dirty caches to disk.  Context memory is reclaimed
\  when the VFS arena is destroyed.

: _VMP-TEARDOWN  ( vfs -- )
    DUP V.BCTX @ 0= IF  DROP EXIT  THEN
    \ Sync everything
    0 OVER _VMP-SYNC DROP
    \ Clear the ctx pointer (arena handles deallocation)
    0 SWAP V.BCTX ! ;

\ =====================================================================
\  Vtable
\ =====================================================================

CREATE VMP-VTABLE  VFS-VT-SIZE ALLOT
' _VMP-PROBE     VMP-VTABLE  VFS-VT-PROBE    CELLS + !
' _VMP-INIT      VMP-VTABLE  VFS-VT-INIT     CELLS + !
' _VMP-TEARDOWN  VMP-VTABLE  VFS-VT-TEARDOWN CELLS + !
' _VMP-READ      VMP-VTABLE  VFS-VT-READ     CELLS + !
' _VMP-WRITE     VMP-VTABLE  VFS-VT-WRITE    CELLS + !
' _VMP-READDIR   VMP-VTABLE  VFS-VT-READDIR  CELLS + !
' _VMP-SYNC      VMP-VTABLE  VFS-VT-SYNC     CELLS + !
' _VMP-CREATE    VMP-VTABLE  VFS-VT-CREATE   CELLS + !
' _VMP-DELETE    VMP-VTABLE  VFS-VT-DELETE    CELLS + !
' _VMP-TRUNCATE  VMP-VTABLE  VFS-VT-TRUNCATE CELLS + !

\ =====================================================================
\  Convenience: VMP-NEW  ( arena -- vfs )
\ =====================================================================
\
\  Create a VFS instance pre-wired to the MP64FS binding.
\  Caller still needs to call VMP-INIT on the returned vfs.

: VMP-NEW  ( arena -- vfs )
    VMP-VTABLE VFS-NEW ;

