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
128  CONSTANT _VMP-MAX-FILES
48   CONSTANT _VMP-ENTRY-SIZE
12   CONSTANT _VMP-DIR-SECTORS
2    CONSTANT _VMP-MAX-BMAP-SECTORS
4096 CONSTANT _VMP-BITS-PER-BMAP-SECTOR
8192 CONSTANT _VMP-MAX-SECTORS
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
\    +512    bitmap cache        (2 × 512 bytes maximum)
\    +1536   directory cache     (128 × 48 = 6144 bytes)
\    +7680   scratch buffer      (512 bytes)
\    +8192   parsed geometry     (6 cells)
\    +8240   dirty-bmap flag     (8 bytes)
\    +8248   dirty-dir flag      (8 bytes)
\    +8256   validated/ready     (8 bytes)
\  = 8264 bytes

8264 CONSTANT _VMP-CTX-SIZE

\ Context field offsets
   0 CONSTANT _VMP-C.SUPER
 512 CONSTANT _VMP-C.BMAP
1536 CONSTANT _VMP-C.DIR
7680 CONSTANT _VMP-C.SCRATCH
8192 CONSTANT _VMP-C.TOTAL
8200 CONSTANT _VMP-C.DSTART
8208 CONSTANT _VMP-C.BSTART
8216 CONSTANT _VMP-C.BN
8224 CONSTANT _VMP-C.DIRSTART
8232 CONSTANT _VMP-C.DIRN
8240 CONSTANT _VMP-C.DBMAP
8248 CONSTANT _VMP-C.DDIR
8256 CONSTANT _VMP-C.READY

\ Accessor: ( vfs -- ctx )
: _VMP-CTX  ( vfs -- ctx )  V.BCTX @ ;

: _VMP-READY?  ( vfs -- flag )
    V.BCTX @ DUP 0= IF DROP FALSE EXIT THEN
    _VMP-C.READY + @ 0<> ;

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

\ Find a contiguous run of free sectors in the cached bitmap.
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
    -1
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

VARIABLE _VMRUN-START
VARIABLE _VMRUN-COUNT
VARIABLE _VMRUN-CTX

: _VMP-RUN-FREE?  ( start count ctx -- flag )
    _VMRUN-CTX ! _VMRUN-COUNT ! _VMRUN-START !
    _VMRUN-START @ _VMRUN-CTX @ _VMP-C.DSTART + @ < IF FALSE EXIT THEN
    _VMRUN-START @ _VMRUN-COUNT @ +
    _VMRUN-CTX @ _VMP-C.TOTAL + @ > IF FALSE EXIT THEN
    TRUE
    _VMRUN-COUNT @ 0 ?DO
        _VMRUN-START @ I + _VMRUN-CTX @ _VMP-BIT-FREE? 0= IF
            DROP FALSE LEAVE
        THEN
    LOOP ;

: _VMP-RUN-SET  ( start count ctx -- )
    _VMRUN-CTX ! _VMRUN-COUNT ! _VMRUN-START !
    _VMRUN-COUNT @ 0 ?DO
        _VMRUN-START @ I + _VMRUN-CTX @ _VMP-BIT-SET
    LOOP ;

: _VMP-RUN-CLR  ( start count ctx -- )
    _VMRUN-CTX ! _VMRUN-COUNT ! _VMRUN-START !
    _VMRUN-COUNT @ 0 ?DO
        _VMRUN-START @ I + _VMRUN-CTX @ _VMP-BIT-CLR
    LOOP ;

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
\  superblock (sector 0), validate its disk-derived geometry, then
\  read the complete bitmap and directory into the context caches.

VARIABLE _VMI-V
VARIABLE _VMI-CTX

: _VMP-SB-MARKER   ( ctx -- n ) _VMP-C.SUPER + 4  + W@ ;
: _VMP-SB-TOTAL    ( ctx -- n ) _VMP-C.SUPER + 6  + L@ ;
: _VMP-SB-BSTART   ( ctx -- n ) _VMP-C.SUPER + 10 + W@ ;
: _VMP-SB-BN       ( ctx -- n ) _VMP-C.SUPER + 12 + W@ ;
: _VMP-SB-DIRSTART ( ctx -- n ) _VMP-C.SUPER + 14 + W@ ;
: _VMP-SB-DIRN     ( ctx -- n ) _VMP-C.SUPER + 16 + W@ ;
: _VMP-SB-DSTART   ( ctx -- n ) _VMP-C.SUPER + 18 + W@ ;

VARIABLE _VMGV-CTX
: _VMP-GEOMETRY?  ( ctx -- flag )
    _VMGV-CTX !
    _VMGV-CTX @ _VMP-SB-MARKER 1 <> IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-TOTAL DUP 15 < SWAP _VMP-MAX-SECTORS > OR
        IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-TOTAL DISK-SECTORS <> IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-BSTART 1 <> IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-BN DUP 1 < SWAP _VMP-MAX-BMAP-SECTORS > OR
        IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-TOTAL _VMP-BITS-PER-BMAP-SECTOR 1- +
        _VMP-BITS-PER-BMAP-SECTOR /
        _VMGV-CTX @ _VMP-SB-BN <> IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-DIRSTART
        _VMGV-CTX @ _VMP-SB-BSTART _VMGV-CTX @ _VMP-SB-BN + <>
        IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-DIRN _VMP-DIR-SECTORS <> IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-DSTART
        _VMGV-CTX @ _VMP-SB-DIRSTART _VMGV-CTX @ _VMP-SB-DIRN + <>
        IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-SB-DSTART _VMGV-CTX @ _VMP-SB-TOTAL >=
        IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-C.SUPER + 20 + C@ _VMP-MAX-FILES <>
        IF FALSE EXIT THEN
    _VMGV-CTX @ _VMP-C.SUPER + 21 + C@ _VMP-ENTRY-SIZE <>
        IF FALSE EXIT THEN
    TRUE ;

\ Validate every occupied directory entry before VMP-INIT exposes an inode.
\ Later read/write/delete callbacks can then rely on bounded, bitmap-backed
\ extents instead of reinterpreting untrusted disk fields at mutation time.
VARIABLE _VMEV-CTX
VARIABLE _VMEV-DE
VARIABLE _VMEV-START
VARIABLE _VMEV-COUNT
VARIABLE _VMPV-CTX
VARIABLE _VMDV-CTX

: _VMP-RUN-ALLOCATED?  ( start count ctx -- flag )
    _VMEV-CTX ! _VMEV-COUNT ! _VMEV-START !
    _VMEV-COUNT @ 0= IF FALSE EXIT THEN
    _VMEV-START @ _VMEV-CTX @ _VMP-C.DSTART + @ < IF FALSE EXIT THEN
    _VMEV-START @ _VMEV-CTX @ _VMP-C.TOTAL + @ >= IF FALSE EXIT THEN
    _VMEV-COUNT @
        _VMEV-CTX @ _VMP-C.TOTAL + @ _VMEV-START @ - >
        IF FALSE EXIT THEN
    TRUE
    _VMEV-COUNT @ 0 DO
        _VMEV-START @ I + _VMEV-CTX @ _VMP-BIT-FREE? IF
            DROP FALSE LEAVE
        THEN
    LOOP ;

: _VMP-PARENT-VALID?  ( parent ctx -- flag )
    _VMPV-CTX !
    DUP _VMP-ROOT-PARENT = IF DROP TRUE EXIT THEN
    DUP _VMP-MAX-FILES >= IF DROP FALSE EXIT THEN
    _VMPV-CTX @ _VMP-DIRENT
    DUP C@ 0<> SWAP _VMP-DE.TYPE _VMP-T-DIR = AND ;

: _VMP-DIRENT-VALID?  ( de ctx -- flag )
    _VMEV-CTX ! _VMEV-DE !
    _VMEV-DE @ _VMP-DE.PARENT _VMEV-CTX @ _VMP-PARENT-VALID? 0=
        IF FALSE EXIT THEN
    _VMEV-DE @ _VMP-DE.TYPE DUP 0= SWAP 10 > OR IF FALSE EXIT THEN
    _VMEV-DE @ _VMP-DE.TYPE _VMP-T-DIR = IF
        _VMEV-DE @ _VMP-DE.SEC
        _VMEV-DE @ _VMP-DE.COUNT OR
        _VMEV-DE @ _VMP-DE.USED OR
        _VMEV-DE @ _VMP-DE.EXT1S OR
        _VMEV-DE @ _VMP-DE.EXT1C OR 0= EXIT
    THEN
    _VMEV-DE @ _VMP-DE.SEC _VMEV-DE @ _VMP-DE.COUNT _VMEV-CTX @
        _VMP-RUN-ALLOCATED? 0= IF FALSE EXIT THEN
    _VMEV-DE @ _VMP-DE.EXT1S 0= _VMEV-DE @ _VMP-DE.EXT1C 0= <> IF
        FALSE EXIT
    THEN
    _VMEV-DE @ _VMP-DE.EXT1C IF
        _VMEV-DE @ _VMP-DE.EXT1S _VMEV-DE @ _VMP-DE.EXT1C _VMEV-CTX @
        _VMP-RUN-ALLOCATED? 0= IF FALSE EXIT THEN
    THEN
    _VMEV-DE @ _VMP-DE.USED
    _VMEV-DE @ _VMP-DE.COUNT _VMEV-DE @ _VMP-DE.EXT1C +
        _VMP-SECTOR * <= ;

: _VMP-DIRECTORY-VALID?  ( ctx -- flag )
    _VMDV-CTX ! TRUE
    _VMP-MAX-FILES 0 DO
        I _VMDV-CTX @ _VMP-DIRENT DUP C@ IF
            _VMDV-CTX @ _VMP-DIRENT-VALID? 0= IF
                DROP FALSE LEAVE
            THEN
        ELSE
            DROP
        THEN
    LOOP ;

: _VMP-ADOPT-GEOMETRY  ( ctx -- )
    DUP _VMP-SB-TOTAL    OVER _VMP-C.TOTAL + !
    DUP _VMP-SB-DSTART   OVER _VMP-C.DSTART + !
    DUP _VMP-SB-BSTART   OVER _VMP-C.BSTART + !
    DUP _VMP-SB-BN       OVER _VMP-C.BN + !
    DUP _VMP-SB-DIRSTART OVER _VMP-C.DIRSTART + !
    DUP _VMP-SB-DIRN      SWAP _VMP-C.DIRN + ! ;

: _VMP-INIT  ( vfs -- ior )
    _VMI-V !
    \ Check disk present
    DISK? 0= IF  -1 EXIT  THEN
    \ Allocate context
    _VMI-V @ V.ARENA @  _VMP-CTX-SIZE ARENA-ALLOT?
    IF DROP -1 EXIT THEN
    _VMI-CTX !
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
    \ Validate and adopt disk geometry before any variable-size DMA.
    _VMI-CTX @ _VMP-GEOMETRY? 0= IF -3 EXIT THEN
    _VMI-CTX @ _VMP-ADOPT-GEOMETRY
    \ Read the complete bitmap.
    _VMI-CTX @ _VMP-C.BSTART + @ DISK-SEC!
    _VMI-CTX @ _VMP-C.BMAP +  DISK-DMA!
    _VMI-CTX @ _VMP-C.BN + @ DISK-N!  DISK-READ
    \ Read the geometry-selected directory.
    _VMI-CTX @ _VMP-C.DIRSTART + @ DISK-SEC!
    _VMI-CTX @ _VMP-C.DIR +  DISK-DMA!
    _VMI-CTX @ _VMP-C.DIRN + @ DISK-N!  DISK-READ
    \ Metadata sectors must all be reserved in the allocation bitmap.
    _VMI-CTX @ _VMP-C.DSTART + @ 0 DO
        I _VMI-CTX @ _VMP-BIT-FREE? IF -4 UNLOOP EXIT THEN
    LOOP
    _VMI-CTX @ _VMP-DIRECTORY-VALID? 0= IF -5 EXIT THEN
    \ Clear dirty flags
    0 _VMI-CTX @ _VMP-C.DBMAP + !
    0 _VMI-CTX @ _VMP-C.DDIR + !
    -1 _VMI-CTX @ _VMP-C.READY + !
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
    DUP _VMP-READY? 0= IF 2DROP EXIT THEN
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
VARIABLE _VMRR-ESEC    \ secondary extent start sector
VARIABLE _VMRR-ENSEC   \ secondary extent sector count
VARIABLE _VMRR-ACT     \ actual bytes read so far
VARIABLE _VMRR-SCR     \ scratch buffer address

\ Map a logical file position to its physical sector across both extents.
: _VMRR-DSEC  ( -- sec )
    _VMRR-POS @ _VMP-SECTOR / DUP
    _VMRR-NSEC @ < IF
        _VMRR-SSEC @ +
    ELSE
        _VMRR-NSEC @ - _VMRR-ESEC @ +
    THEN ;

\ Contiguous sectors remaining in the current extent.
: _VMRR-RUN-SECS  ( -- count )
    _VMRR-POS @ _VMP-SECTOR / DUP
    _VMRR-NSEC @ < IF
        _VMRR-NSEC @ SWAP -
    ELSE
        _VMRR-NSEC @ _VMRR-ENSEC @ + SWAP -
    THEN ;

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
        DUP 255 MIN _VMRR-RUN-SECS MIN  ( n-full batch )
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
    DUP _VMP-READY? 0= IF 2DROP 2DROP DROP 0 EXIT THEN
    _VMRR-V !  _VMRR-IN !  _VMRR-OFF !  _VMRR-LEN !  _VMRR-BUF !
    _VMRR-V @ V.BCTX @  _VMRR-CTX !
    _VMRR-CTX @ _VMP-C.SCRATCH +  _VMRR-SCR !
    0 _VMRR-ACT !
    \ Load both extents before clamping the request.
    _VMRR-IN @ IN.BDATA @      _VMRR-SSEC !
    _VMRR-IN @ IN.BDATA 8 + @  _VMRR-NSEC !
    _VMRR-IN @ IN.BID @ _VMRR-CTX @ _VMP-DIRENT
    DUP _VMP-DE.EXT1S _VMRR-ESEC !
        _VMP-DE.EXT1C _VMRR-ENSEC !
    \ Clamp len to file size - offset
    _VMRR-IN @ IN.SIZE-LO @  _VMRR-OFF @ -
    DUP 0< IF  DROP 0 EXIT  THEN   \ offset past EOF
    _VMRR-LEN @ MIN  _VMRR-LEN !
    \ Corrupt metadata must not read beyond allocated extents.
    _VMRR-NSEC @ _VMRR-ENSEC @ + _VMP-SECTOR * _VMRR-OFF @ -
    0 MAX _VMRR-LEN @ MIN _VMRR-LEN !
    _VMRR-LEN @ 0= IF  0 EXIT  THEN
    _VMRR-OFF @  _VMRR-POS !
    _VMRR-LEN @  _VMRR-REM !
    _VMRR-HEAD  _VMRR-FULL  _VMRR-TAIL
    _VMRR-ACT @ ;

\ =====================================================================
\  Write  ( buf len offset inode vfs -- actual )
\ =====================================================================

\ Grow a file's allocation to cover a desired byte length.  Prefer an
\ in-place primary extension; otherwise use MP64FS's secondary extent.
VARIABLE _VMG-BYTES
VARIABLE _VMG-IN
VARIABLE _VMG-V
VARIABLE _VMG-CTX
VARIABLE _VMG-DE
VARIABLE _VMG-WANT
VARIABLE _VMG-PCOUNT
VARIABLE _VMG-ESTART
VARIABLE _VMG-ECOUNT
VARIABLE _VMG-ADD
VARIABLE _VMG-START

: _VMP-ENSURE  ( bytes inode vfs -- ior )
    _VMG-V ! _VMG-IN ! _VMG-BYTES !
    _VMG-IN @ IN.TYPE @ VFS-T-FILE <> IF -1 EXIT THEN
    _VMG-BYTES @ 0= IF 0 EXIT THEN
    _VMG-V @ V.BCTX @ _VMG-CTX !
    _VMG-IN @ IN.BID @ _VMG-CTX @ _VMP-DIRENT DUP _VMG-DE !
    DUP _VMP-DE.COUNT _VMG-PCOUNT !
    DUP _VMP-DE.EXT1S _VMG-ESTART !
        _VMP-DE.EXT1C _VMG-ECOUNT !
    _VMG-BYTES @ _VMP-SECTOR 1- + _VMP-SECTOR / _VMG-WANT !
    _VMG-WANT @ _VMG-PCOUNT @ _VMG-ECOUNT @ + <= IF 0 EXIT THEN
    _VMG-WANT @ _VMG-PCOUNT @ _VMG-ECOUNT @ + - _VMG-ADD !

    _VMG-ECOUNT @ 0> IF
        \ A two-extent file can only grow at the end of extent 1.
        _VMG-ESTART @ _VMG-ECOUNT @ +
        _VMG-ADD @ _VMG-CTX @ _VMP-RUN-FREE? 0= IF -2 EXIT THEN
        _VMG-ESTART @ _VMG-ECOUNT @ +
        _VMG-ADD @ _VMG-CTX @ _VMP-RUN-SET
        _VMG-ECOUNT @ _VMG-ADD @ +
        DUP _VMG-ECOUNT ! _VMG-DE @ 46 + W!
    ELSE
        \ First try to keep the file in one contiguous extent.
        _VMG-IN @ IN.BDATA @ _VMG-PCOUNT @ +
        _VMG-ADD @ _VMG-CTX @ _VMP-RUN-FREE? IF
            _VMG-IN @ IN.BDATA @ _VMG-PCOUNT @ +
            _VMG-ADD @ _VMG-CTX @ _VMP-RUN-SET
            _VMG-PCOUNT @ _VMG-ADD @ + DUP _VMG-PCOUNT !
            DUP _VMG-IN @ IN.BDATA 8 + !
                _VMG-DE @ 26 + W!
        ELSE
            \ Fragmented growth becomes the secondary extent.
            _VMG-ADD @ _VMG-CTX @ _VMP-FIND-FREE DUP -1 = IF
                DROP -2 EXIT
            THEN
            DUP _VMG-START !
            _VMG-ADD @ _VMG-CTX @ _VMP-RUN-SET
            _VMG-START @ _VMG-DE @ 44 + W!
            _VMG-ADD @   _VMG-DE @ 46 + W!
        THEN
    THEN
    -1 _VMG-CTX @ _VMP-C.DBMAP + !
    -1 _VMG-CTX @ _VMP-C.DDIR + !
    VFS-IF-DIRTY _VMG-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    0 ;

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
VARIABLE _VMRW-ESEC
VARIABLE _VMRW-ENSEC
VARIABLE _VMRW-ACT
VARIABLE _VMRW-SCR

: _VMRW-DSEC  ( -- sec )
    _VMRW-POS @ _VMP-SECTOR / DUP
    _VMRW-NSEC @ < IF
        _VMRW-SSEC @ +
    ELSE
        _VMRW-NSEC @ - _VMRW-ESEC @ +
    THEN ;

: _VMRW-RUN-SECS  ( -- count )
    _VMRW-POS @ _VMP-SECTOR / DUP
    _VMRW-NSEC @ < IF
        _VMRW-NSEC @ SWAP -
    ELSE
        _VMRW-NSEC @ _VMRW-ENSEC @ + SWAP -
    THEN ;

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
        DUP 255 MIN _VMRW-RUN-SECS MIN
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
    DUP _VMP-READY? 0= IF 2DROP 2DROP DROP 0 EXIT THEN
    _VMRW-V !  _VMRW-IN !  _VMRW-OFF !  _VMRW-LEN !  _VMRW-BUF !
    _VMRW-V @ V.BCTX @  _VMRW-CTX !
    _VMRW-CTX @ _VMP-C.SCRATCH +  _VMRW-SCR !
    0 _VMRW-ACT !
    \ Grow before clamping so ordinary writes are not limited by the
    \ file's creation-time allocation.
    _VMRW-OFF @ _VMRW-LEN @ +
    _VMRW-IN @ _VMRW-V @ _VMP-ENSURE DROP
    _VMRW-IN @ IN.BDATA @      _VMRW-SSEC !
    _VMRW-IN @ IN.BDATA 8 + @  _VMRW-NSEC !
    _VMRW-IN @ IN.BID @ _VMRW-CTX @ _VMP-DIRENT
    DUP _VMP-DE.EXT1S _VMRW-ESEC !
        _VMP-DE.EXT1C _VMRW-ENSEC !
    \ If growth failed, retain VFS partial-write semantics.
    _VMRW-NSEC @ _VMRW-ENSEC @ + _VMP-SECTOR *  ( capacity )
    _VMRW-OFF @ _VMRW-LEN @ +  OVER > IF
        \ Clamp to capacity
        _VMRW-OFF @ -  0 MAX  _VMRW-LEN !
    ELSE DROP THEN
    _VMRW-LEN @ 0= IF  0 EXIT  THEN
    _VMRW-OFF @  _VMRW-POS !
    _VMRW-LEN @  _VMRW-REM !
    _VMRW-HEAD  _VMRW-FULL  _VMRW-TAIL
    \ Update dir cache: used_bytes = max(old, offset+len)
    _VMRW-OFF @ _VMRW-ACT @ +   ( new-end )
    _VMRW-IN @ IN.BID @  _VMRW-CTX @  _VMP-DIRENT  ( new-end de )
    DUP _VMP-DE.USED  ROT MAX                       ( de new-used )
    OVER 28 + L!                                     \ update dir cache
    DROP                                              \ discard dir entry
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
VARIABLE _VMSY-IN

: _VMP-SYNC  ( inode vfs -- ior )
    DUP _VMP-READY? 0= IF 2DROP -1 EXIT THEN
    _VMSY-V !  _VMSY-IN !
    _VMSY-V @ V.BCTX @  _VMSY-CTX !
    _VMSY-CTX @ 0= IF  -1 EXIT  THEN
    \ Reflect mutable inode metadata, notably rename, into its stable
    \ directory slot before flushing the global cache.
    _VMSY-IN @ DUP 0<> IF
        DUP _VMSY-V @ V.ROOT @ <> IF
            DUP IN.BID @ _VMSY-CTX @ _VMP-DIRENT
            DUP 24 0 FILL
            OVER IN.NAME @ _VFS-STR-GET 23 MIN
            >R OVER R> CMOVE
            0 OVER 40 + L!              \ content changed: CRC unknown
            DROP DROP
            -1 _VMSY-CTX @ _VMP-C.DDIR + !
        ELSE
            DROP
        THEN
    ELSE
        DROP
    THEN
    \ Write bitmap if dirty
    _VMSY-CTX @ _VMP-C.DBMAP + @ IF
        _VMSY-CTX @ _VMP-C.BSTART + @ DISK-SEC!
        _VMSY-CTX @ _VMP-C.BMAP + DISK-DMA!
        _VMSY-CTX @ _VMP-C.BN + @ DISK-N!  DISK-WRITE
        0 _VMSY-CTX @ _VMP-C.DBMAP + !
    THEN
    \ Write directory if dirty
    _VMSY-CTX @ _VMP-C.DDIR + @ IF
        _VMSY-CTX @ _VMP-C.DIRSTART + @ DISK-SEC!
        _VMSY-CTX @ _VMP-C.DIR + DISK-DMA!
        _VMSY-CTX @ _VMP-C.DIRN + @ DISK-N!  DISK-WRITE
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
VARIABLE _VMFS-CTX

: _VMP-FIND-FREE-SLOT  ( ctx -- slot | -1 )
    _VMFS-CTX ! -1
    _VMP-MAX-FILES 0 DO
        I _VMFS-CTX @ _VMP-DIRENT C@ 0= IF
            DROP I LEAVE
        THEN
    LOOP ;

: _VMP-CREATE  ( inode vfs -- ior )
    DUP _VMP-READY? 0= IF 2DROP -1 EXIT THEN
    _VMCR-V !  _VMCR-IN !
    _VMCR-V @ V.BCTX @  _VMCR-CTX !
    _VMCR-IN @ IN.NAME @ _VFS-STR-GET NIP 23 > IF -3 EXIT THEN
    \ Find free dir slot
    _VMCR-CTX @ _VMP-FIND-FREE-SLOT  _VMCR-SLOT !
    _VMCR-SLOT @ -1 = IF  -1 EXIT  THEN  \ directory full
    \ Determine sector allocation
    _VMCR-IN @ IN.TYPE @ VFS-T-DIR = IF
        0 _VMCR-NSEC !   \ directories don't get data sectors
    ELSE
        \ Start small; _VMP-WRITE grows into one or two extents.
        1 _VMCR-NSEC !
        _VMCR-NSEC @ _VMCR-CTX @  _VMP-FIND-FREE  ( sector | -1 )
        DUP -1 = IF
            DROP -2 EXIT   \ no space
        THEN
        _VMCR-IN @ IN.BDATA !           \ bdata-0 = start_sector
        _VMCR-NSEC @  _VMCR-IN @ IN.BDATA 8 + !  \ bdata-1 = sec_count
        _VMCR-IN @ IN.BDATA @ _VMCR-NSEC @ _VMCR-CTX @ _VMP-RUN-SET
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
    DUP _VMP-READY? 0= IF 2DROP -1 EXIT THEN
    _VMDL-V !  _VMDL-IN !
    _VMDL-V @ V.BCTX @  _VMDL-CTX !
    \ Free bitmap sectors in both extents.
    _VMDL-IN @ IN.BDATA @
    _VMDL-IN @ IN.BDATA 8 + @
    _VMDL-CTX @ _VMP-RUN-CLR
    _VMDL-IN @ IN.BID @ _VMDL-CTX @ _VMP-DIRENT
    DUP _VMP-DE.EXT1S
    SWAP _VMP-DE.EXT1C
    _VMDL-CTX @ _VMP-RUN-CLR
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
\  Resize the allocation and update used_bytes.  Files retain at least
\  one primary sector so a zero-length file remains writable.

VARIABLE _VMTR-IN
VARIABLE _VMTR-V
VARIABLE _VMTR-CTX
VARIABLE _VMTR-DE
VARIABLE _VMTR-WANT
VARIABLE _VMTR-PCOUNT
VARIABLE _VMTR-ESTART
VARIABLE _VMTR-ECOUNT
VARIABLE _VMTR-KEEP-E

: _VMP-SHRINK  ( bytes inode vfs -- )
    _VMTR-V ! _VMTR-IN !
    _VMP-SECTOR 1- + _VMP-SECTOR / 1 MAX _VMTR-WANT !
    _VMTR-V @ V.BCTX @ _VMTR-CTX !
    _VMTR-IN @ IN.BID @ _VMTR-CTX @ _VMP-DIRENT DUP _VMTR-DE !
    DUP _VMP-DE.COUNT _VMTR-PCOUNT !
    DUP _VMP-DE.EXT1S _VMTR-ESTART !
        _VMP-DE.EXT1C _VMTR-ECOUNT !
    _VMTR-WANT @ _VMTR-PCOUNT @ _VMTR-ECOUNT @ + >= IF EXIT THEN
    _VMTR-WANT @ _VMTR-PCOUNT @ >= IF
        _VMTR-WANT @ _VMTR-PCOUNT @ - _VMTR-KEEP-E !
        _VMTR-ESTART @ _VMTR-KEEP-E @ +
        _VMTR-ECOUNT @ _VMTR-KEEP-E @ -
        _VMTR-CTX @ _VMP-RUN-CLR
        _VMTR-KEEP-E @ DUP _VMTR-DE @ 46 + W!
        0= IF 0 _VMTR-DE @ 44 + W! THEN
    ELSE
        _VMTR-IN @ IN.BDATA @ _VMTR-WANT @ +
        _VMTR-PCOUNT @ _VMTR-WANT @ -
        _VMTR-CTX @ _VMP-RUN-CLR
        _VMTR-ESTART @ _VMTR-ECOUNT @ _VMTR-CTX @ _VMP-RUN-CLR
        _VMTR-WANT @ DUP _VMTR-IN @ IN.BDATA 8 + !
            _VMTR-DE @ 26 + W!
        0 _VMTR-DE @ 44 + W!
        0 _VMTR-DE @ 46 + W!
    THEN
    -1 _VMTR-CTX @ _VMP-C.DBMAP + !
    -1 _VMTR-CTX @ _VMP-C.DDIR + ! ;

: _VMP-TRUNCATE  ( inode vfs -- ior )
    DUP _VMP-READY? 0= IF 2DROP -1 EXIT THEN
    _VMTR-V ! _VMTR-IN !
    _VMTR-IN @ IN.SIZE-LO @ _VMTR-IN @ _VMTR-V @ _VMP-ENSURE
    ?DUP IF EXIT THEN
    _VMTR-IN @ IN.SIZE-LO @ _VMTR-IN @ _VMTR-V @ _VMP-SHRINK
    _VMTR-IN @ IN.BID @ _VMTR-V @ V.BCTX @ _VMP-DIRENT
    _VMTR-IN @ IN.SIZE-LO @ OVER 28 + L!
    DROP
    -1 _VMTR-V @ V.BCTX @ _VMP-C.DDIR + !
    0 ;

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
