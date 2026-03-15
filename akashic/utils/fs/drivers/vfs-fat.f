\ vfs-fat.f — FAT16/FAT32 binding for the VFS layer
\
\ Bridges the abstract VFS to FAT16 and FAT32 formatted volumes.
\ All byte transfer goes through the BIOS disk primitives
\ (DISK-SEC!, DISK-DMA!, DISK-N!, DISK-READ, DISK-WRITE).
\
\ FAT type is auto-detected from the BPB at mount time using the
\ Microsoft specification's data-cluster-count algorithm:
\   < 4085 clusters  →  FAT12  (NOT supported — returns error)
\   < 65525 clusters →  FAT16
\   ≥ 65525 clusters →  FAT32
\
\ Prefix: VFAT-  (public API)
\         _VFAT- (internal helpers)
\
\ Load with:   REQUIRE utils/fs/drivers/vfs-fat.f

PROVIDED akashic-vfs-fat
REQUIRE ../vfs.f

\ =====================================================================
\  On-disk constants (Microsoft FAT specification)
\ =====================================================================

512  CONSTANT _VFAT-SECTOR         \ bytes per sector (assumed fixed)
32   CONSTANT _VFAT-DIRENT-SIZE    \ directory entry size

\ BPB field offsets within sector 0
\ (all little-endian; use W@ for u16, L@ for u32, C@ for u8)
11   CONSTANT _VFAT-BPB.BPS        \ u16 BytsPerSec
13   CONSTANT _VFAT-BPB.SPC        \ u8  SecPerClus
14   CONSTANT _VFAT-BPB.RSVD       \ u16 RsvdSecCnt
16   CONSTANT _VFAT-BPB.NFATS      \ u8  NumFATs
17   CONSTANT _VFAT-BPB.ROOTENT    \ u16 RootEntCnt (FAT16; 0 for FAT32)
19   CONSTANT _VFAT-BPB.TOT16      \ u16 TotSec16
22   CONSTANT _VFAT-BPB.FATSZ16    \ u16 FATSz16
32   CONSTANT _VFAT-BPB.TOT32      \ u32 TotSec32
36   CONSTANT _VFAT-BPB.FATSZ32    \ u32 FATSz32 (FAT32 only)
44   CONSTANT _VFAT-BPB.ROOTCLUS   \ u32 RootClus (FAT32 only)

\ Boot signature
510  CONSTANT _VFAT-SIG-OFF         \ offset of 0x55, 0xAA

\ FAT directory entry field offsets
0    CONSTANT _VFAT-DE.NAME         \ 8 bytes short name
8    CONSTANT _VFAT-DE.EXT          \ 3 bytes extension
11   CONSTANT _VFAT-DE.ATTR         \ 1 byte  attributes
20   CONSTANT _VFAT-DE.CLUSHI       \ u16 first cluster high (FAT32)
26   CONSTANT _VFAT-DE.CLUSLO       \ u16 first cluster low
28   CONSTANT _VFAT-DE.FILESZ       \ u32 file size

\ Directory entry attribute bits
1    CONSTANT _VFAT-ATTR-RO
2    CONSTANT _VFAT-ATTR-HIDDEN
4    CONSTANT _VFAT-ATTR-SYSTEM
8    CONSTANT _VFAT-ATTR-VOLLABEL
16   CONSTANT _VFAT-ATTR-DIR
32   CONSTANT _VFAT-ATTR-ARCHIVE
15   CONSTANT _VFAT-ATTR-LFN        \ RO|HID|SYS|VOL = LFN marker

\ FAT type tags (internal)
16   CONSTANT _VFAT-TYPE-FAT16
32   CONSTANT _VFAT-TYPE-FAT32

\ End-of-chain sentinels
HEX FFF8 DECIMAL  CONSTANT _VFAT-EOC16
HEX 0FFFFFF8 DECIMAL  CONSTANT _VFAT-EOC32

\ FAT32 cluster mask (clear upper 4 bits)
HEX 0FFFFFFF DECIMAL  CONSTANT _VFAT-FAT32-MASK

\ EOC markers for allocation
HEX FFFF DECIMAL     CONSTANT _VFAT-MARK16
HEX 0FFFFFFF DECIMAL CONSTANT _VFAT-MARK32

\ =====================================================================
\  Binding Context Layout
\ =====================================================================
\
\  Allocated from the VFS arena by _VFAT-INIT, stored in V.BCTX.
\
\  Cached data:
\    +0      BPB cache           (512 bytes — sector 0)
\    +512    FAT sector cache    (512 bytes — one cached FAT sector)
\    +1024   dir sector cache    (512 bytes — one cached dir sector)
\    +1536   scratch buffer      (512 bytes — partial I/O)
\
\  Geometry (computed from BPB):
\    +2048   fat-type            (8 bytes — _VFAT-TYPE-FAT16 or 32)
\    +2056   sec-per-clus        (8 bytes)
\    +2064   rsvd-sec            (8 bytes — reserved sector count)
\    +2072   num-fats            (8 bytes)
\    +2080   fat-size            (8 bytes — sectors per FAT)
\    +2088   root-dir-sectors    (8 bytes — FAT16: sectors for root dir; FAT32: 0)
\    +2096   first-data-sector   (8 bytes)
\    +2104   total-sectors       (8 bytes)
\    +2112   data-clusters       (8 bytes — determines FAT type)
\    +2120   root-cluster        (8 bytes — FAT32: from BPB; FAT16: 0)
\    +2128   root-entry-count    (8 bytes — FAT16: from BPB; FAT32: 0)
\    +2136   root-dir-start      (8 bytes — FAT16: first sector of root dir area)
\
\  FAT sector cache tag:
\    +2144   cached-fat-sec      (8 bytes — sector number, -1 = none)
\
\  Dir sector cache tag:
\    +2152   cached-dir-sec      (8 bytes — sector number, -1 = none)
\
\  Dirty flags:
\    +2160   dirty-fat           (8 bytes — nonzero = FAT cache modified)
\    +2168   dirty-dir           (8 bytes — nonzero = dir cache modified)
\
\  = 2176 bytes

2176 CONSTANT _VFAT-CTX-SIZE

\ Context field offsets
   0 CONSTANT _VFAT-C.BPB
 512 CONSTANT _VFAT-C.FATSEC
1024 CONSTANT _VFAT-C.DIRSEC
1536 CONSTANT _VFAT-C.SCRATCH
2048 CONSTANT _VFAT-C.TYPE
2056 CONSTANT _VFAT-C.SPC
2064 CONSTANT _VFAT-C.RSVD
2072 CONSTANT _VFAT-C.NFATS
2080 CONSTANT _VFAT-C.FATSZ
2088 CONSTANT _VFAT-C.RDSEC
2096 CONSTANT _VFAT-C.FDS
2104 CONSTANT _VFAT-C.TOTSEC
2112 CONSTANT _VFAT-C.DCLUS
2120 CONSTANT _VFAT-C.RCLUS
2128 CONSTANT _VFAT-C.RENT
2136 CONSTANT _VFAT-C.RDSTART
2144 CONSTANT _VFAT-C.CFATSEC
2152 CONSTANT _VFAT-C.CDIRSEC
2160 CONSTANT _VFAT-C.DFAT
2168 CONSTANT _VFAT-C.DDIR

\ Accessor
: _VFAT-CTX  ( vfs -- ctx )  V.BCTX @ ;

\ =====================================================================
\  Geometry Helpers
\ =====================================================================

\ cluster-to-sector: first-data-sector + (cluster - 2) * sec-per-clus
: _VFAT-CLUS>SEC  ( cluster ctx -- sector )
    DUP _VFAT-C.FDS + @         ( cluster ctx first-data-sec )
    ROT 2 -                     ( ctx first-data-sec clus-2 )
    ROT _VFAT-C.SPC + @         ( first-data-sec clus-2 spc )
    * + ;

\ Is this cluster value an end-of-chain marker?
: _VFAT-EOC?  ( value ctx -- flag )
    _VFAT-C.TYPE + @  _VFAT-TYPE-FAT32 = IF
        _VFAT-EOC32 >=
    ELSE
        _VFAT-EOC16 >=
    THEN ;

\ =====================================================================
\  Probe  ( sector-0-buf vfs -- flag )
\ =====================================================================
\
\  Check bytes 0x1FE–0x1FF for 0x55, 0xAA boot signature, then
\  validate basic BPB sanity (BytsPerSec=512, SecPerClus power of 2,
\  NumFATs >= 1).

: _VFAT-PROBE  ( buf vfs -- flag )
    DROP                                 ( buf )
    \ Check boot signature 0x55 0xAA
    DUP _VFAT-SIG-OFF + C@  85 <> IF  DROP FALSE EXIT  THEN
    DUP _VFAT-SIG-OFF 1+ + C@  170 <> IF  DROP FALSE EXIT  THEN
    \ BytsPerSec must be 512
    DUP _VFAT-BPB.BPS + W@  512 <> IF  DROP FALSE EXIT  THEN
    \ SecPerClus must be nonzero power of 2
    DUP _VFAT-BPB.SPC + C@             ( buf spc )
    DUP 0= IF  2DROP FALSE EXIT  THEN
    DUP DUP 1- AND 0<> IF  2DROP FALSE EXIT  THEN
    DROP
    \ NumFATs >= 1
    DUP _VFAT-BPB.NFATS + C@  0= IF  DROP FALSE EXIT  THEN
    DROP TRUE ;

\ =====================================================================
\  BPB Parsing  ( ctx -- ior )
\ =====================================================================
\
\  Extract geometry fields from the BPB cache into the context
\  cells.  Determine FAT type from data cluster count.

VARIABLE _VFP-CTX

: _VFAT-PARSE-BPB  ( ctx -- ior )
    _VFP-CTX !
    \ SecPerClus
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.SPC + C@
    _VFP-CTX @ _VFAT-C.SPC + !
    \ RsvdSecCnt
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.RSVD + W@
    _VFP-CTX @ _VFAT-C.RSVD + !
    \ NumFATs
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.NFATS + C@
    _VFP-CTX @ _VFAT-C.NFATS + !
    \ FATSz: prefer FATSz16; if 0, use FATSz32
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.FATSZ16 + W@
    DUP 0= IF
        DROP  _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.FATSZ32 + L@
    THEN
    _VFP-CTX @ _VFAT-C.FATSZ + !
    \ TotSec: prefer TotSec16; if 0, use TotSec32
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.TOT16 + W@
    DUP 0= IF
        DROP  _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.TOT32 + L@
    THEN
    _VFP-CTX @ _VFAT-C.TOTSEC + !
    \ RootEntCnt
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.ROOTENT + W@
    _VFP-CTX @ _VFAT-C.RENT + !
    \ RootDirSectors = ((RootEntCnt * 32) + 511) / 512
    _VFP-CTX @ _VFAT-C.RENT + @  32 *  511 +  512 /
    _VFP-CTX @ _VFAT-C.RDSEC + !
    \ FirstDataSector = RsvdSecCnt + (NumFATs * FATSz) + RootDirSectors
    _VFP-CTX @ _VFAT-C.RSVD + @
    _VFP-CTX @ _VFAT-C.NFATS + @  _VFP-CTX @ _VFAT-C.FATSZ + @  *  +
    _VFP-CTX @ _VFAT-C.RDSEC + @  +
    _VFP-CTX @ _VFAT-C.FDS + !
    \ DataClusters = (TotSec - FirstDataSector) / SecPerClus
    _VFP-CTX @ _VFAT-C.TOTSEC + @
    _VFP-CTX @ _VFAT-C.FDS + @  -
    _VFP-CTX @ _VFAT-C.SPC + @  /
    _VFP-CTX @ _VFAT-C.DCLUS + !
    \ Determine FAT type
    _VFP-CTX @ _VFAT-C.DCLUS + @
    DUP 4085 < IF
        DROP -3 EXIT   \ FAT12 not supported
    THEN
    65525 < IF
        _VFAT-TYPE-FAT16  _VFP-CTX @ _VFAT-C.TYPE + !
        \ FAT16 root dir start = RsvdSecCnt + NumFATs*FATSz
        _VFP-CTX @ _VFAT-C.RSVD + @
        _VFP-CTX @ _VFAT-C.NFATS + @  _VFP-CTX @ _VFAT-C.FATSZ + @  *  +
        _VFP-CTX @ _VFAT-C.RDSTART + !
        0 _VFP-CTX @ _VFAT-C.RCLUS + !
    ELSE
        _VFAT-TYPE-FAT32  _VFP-CTX @ _VFAT-C.TYPE + !
        0 _VFP-CTX @ _VFAT-C.RDSEC + !
        0 _VFP-CTX @ _VFAT-C.RDSTART + !
        \ Root cluster from BPB
        _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.ROOTCLUS + L@
        _VFP-CTX @ _VFAT-C.RCLUS + !
    THEN
    0 ;  \ success

\ =====================================================================
\  FAT Table Access
\ =====================================================================
\
\  Read the next-cluster value from the FAT for a given cluster.
\  Maintains a 1-sector cache to avoid re-reading the same FAT
\  sector on sequential chain walks.

VARIABLE _VFN-CTX
VARIABLE _VFN-SEC
VARIABLE _VFN-OFF

: _VFAT-FAT-ENSURE  ( fat-sector ctx -- )
    \ If already cached, nothing to do
    2DUP _VFAT-C.CFATSEC + @  = IF  2DROP EXIT  THEN
    \ Flush dirty FAT cache first
    DUP _VFAT-C.DFAT + @ IF
        DUP _VFAT-C.CFATSEC + @  DISK-SEC!
        DUP _VFAT-C.FATSEC +     DISK-DMA!
        1 DISK-N!  DISK-WRITE
        0 OVER _VFAT-C.DFAT + !
    THEN
    \ Read new FAT sector
    OVER DISK-SEC!
    DUP _VFAT-C.FATSEC +  DISK-DMA!
    1 DISK-N!  DISK-READ
    _VFAT-C.CFATSEC + ! ;

: _VFAT-NEXT-CLUSTER  ( cluster ctx -- next-cluster )
    _VFN-CTX !
    _VFN-CTX @ _VFAT-C.TYPE + @  _VFAT-TYPE-FAT32 = IF
        \ FAT32: 4 bytes per entry
        DUP 4 *                        ( cluster byte-off )
        DUP _VFAT-SECTOR /             ( cluster byte-off sec-within-fat )
        _VFN-CTX @ _VFAT-C.RSVD + @ + ( cluster byte-off abs-sector )
        _VFN-CTX @  _VFAT-FAT-ENSURE
        _VFAT-SECTOR MOD               ( cluster off-in-sector )
        NIP                            ( off-in-sector )
        _VFN-CTX @ _VFAT-C.FATSEC + + L@
        _VFAT-FAT32-MASK AND            \ mask upper 4 bits
    ELSE
        \ FAT16: 2 bytes per entry
        DUP 2 *                        ( cluster byte-off )
        DUP _VFAT-SECTOR /             ( cluster byte-off sec-within-fat )
        _VFN-CTX @ _VFAT-C.RSVD + @ + ( cluster byte-off abs-sector )
        _VFN-CTX @  _VFAT-FAT-ENSURE
        _VFAT-SECTOR MOD               ( cluster off-in-sector )
        NIP                            ( off-in-sector )
        _VFN-CTX @ _VFAT-C.FATSEC + + W@
    THEN ;

\ =====================================================================
\  FAT Table Write
\ =====================================================================

VARIABLE _VSF-CTX

: _VFAT-SET-FAT  ( value cluster ctx -- )
    _VSF-CTX !
    _VSF-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT32 = IF
        4 *
        DUP _VFAT-SECTOR /
        _VSF-CTX @ _VFAT-C.RSVD + @ +
        _VSF-CTX @ _VFAT-FAT-ENSURE
        _VFAT-SECTOR MOD
        _VSF-CTX @ _VFAT-C.FATSEC + +
        L!
    ELSE
        2 *
        DUP _VFAT-SECTOR /
        _VSF-CTX @ _VFAT-C.RSVD + @ +
        _VSF-CTX @ _VFAT-FAT-ENSURE
        _VFAT-SECTOR MOD
        _VSF-CTX @ _VFAT-C.FATSEC + +
        W!
    THEN
    -1 _VSF-CTX @ _VFAT-C.DFAT + ! ;

\ =====================================================================
\  Cluster Allocation / Free
\ =====================================================================

VARIABLE _VAC-CTX

: _VFAT-ALLOC-CLUSTER  ( ctx -- cluster | 0 )
    _VAC-CTX !
    _VAC-CTX @ _VFAT-C.DCLUS + @ 2 +   2 DO
        I _VAC-CTX @ _VFAT-NEXT-CLUSTER  0= IF
            _VAC-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT32 = IF
                _VFAT-MARK32
            ELSE
                _VFAT-MARK16
            THEN
            I _VAC-CTX @ _VFAT-SET-FAT
            I UNLOOP EXIT
        THEN
    LOOP
    0 ;

VARIABLE _VFFC-CTX
VARIABLE _VFFC-CUR
VARIABLE _VFFC-NXT

: _VFAT-FREE-CHAIN  ( first-cluster ctx -- )
    _VFFC-CTX !  _VFFC-CUR !
    _VFFC-CUR @ 2 < IF EXIT THEN
    BEGIN
        _VFFC-CUR @ _VFFC-CTX @ _VFAT-NEXT-CLUSTER  _VFFC-NXT !
        0 _VFFC-CUR @ _VFFC-CTX @ _VFAT-SET-FAT
        _VFFC-NXT @ 2 < IF EXIT THEN
        _VFFC-NXT @ _VFFC-CTX @ _VFAT-EOC? IF EXIT THEN
        _VFFC-NXT @ _VFFC-CUR !
    AGAIN ;

\ =====================================================================
\  Directory Entry Helpers
\ =====================================================================

: _VFAT-DE-CLUSTER  ( de -- cluster )
    DUP _VFAT-DE.CLUSLO + W@
    SWAP _VFAT-DE.CLUSHI + W@  16 LSHIFT  OR ;

\ =====================================================================
\  8.3 Short Filename Helpers
\ =====================================================================

CREATE _VFAT-SFN-BUF 11 ALLOT

: _VFAT-UPCHAR  ( c -- C )
    DUP [CHAR] a >=  OVER [CHAR] z <=  AND IF  32 -  THEN ;

: _VFAT-FIND-DOT  ( c-addr u -- index | -1 )
    0 DO
        DUP I + C@ [CHAR] . = IF  DROP I UNLOOP EXIT  THEN
    LOOP
    DROP -1 ;

VARIABLE _VSFN-SRC
VARIABLE _VSFN-LEN
VARIABLE _VSFN-DOT

: _VFAT-MAKE-SFN  ( c-addr u -- flag )
    _VFAT-SFN-BUF 11 32 FILL
    _VSFN-LEN !  _VSFN-SRC !
    _VSFN-SRC @  _VSFN-LEN @  _VFAT-FIND-DOT  _VSFN-DOT !
    \ Base name (before dot, up to 8 chars)
    _VSFN-DOT @ -1 = IF  _VSFN-LEN @  ELSE  _VSFN-DOT @  THEN
    8 MIN
    0 DO
        _VSFN-SRC @ I + C@  _VFAT-UPCHAR
        _VFAT-SFN-BUF I + C!
    LOOP
    \ Extension (after dot, up to 3 chars)
    _VSFN-DOT @ -1 <> IF
        _VSFN-LEN @  _VSFN-DOT @ -  1-   3 MIN
        0 DO
            _VSFN-SRC @  _VSFN-DOT @ 1+ I + +  C@
            _VFAT-UPCHAR
            _VFAT-SFN-BUF 8 + I + C!
        LOOP
    THEN
    _VSFN-DOT @ -1 = IF  _VSFN-LEN @  ELSE  _VSFN-DOT @  THEN
    0> ;

\ SFN → readable name ("HELLO   TXT" → "HELLO.TXT")
CREATE _VFAT-NAMEBUF 13 ALLOT
VARIABLE _VFAT-NLEN

: _VFAT-SFN>NAME  ( de -- addr len )
    _VFAT-NAMEBUF 13 0 FILL
    0 _VFAT-NLEN !
    8 0 DO
        DUP I + C@ 32 <> IF
            DUP I + C@  _VFAT-NAMEBUF _VFAT-NLEN @ + C!
            _VFAT-NLEN @ 1+ _VFAT-NLEN !
        ELSE LEAVE THEN
    LOOP
    DUP 8 + C@ 32 <> IF
        [CHAR] .  _VFAT-NAMEBUF _VFAT-NLEN @ + C!
        _VFAT-NLEN @ 1+ _VFAT-NLEN !
        3 0 DO
            DUP 8 I + + C@ 32 <> IF
                DUP 8 I + + C@  _VFAT-NAMEBUF _VFAT-NLEN @ + C!
                _VFAT-NLEN @ 1+ _VFAT-NLEN !
            ELSE LEAVE THEN
        LOOP
    THEN
    DROP
    _VFAT-NAMEBUF _VFAT-NLEN @ ;

\ =====================================================================
\  Directory Sector Cache
\ =====================================================================
\
\  One-sector sliding window for directory traversal.
\  _VFAT-DIR-ENSURE loads a sector into the dir cache if not
\  already present.

: _VFAT-DIR-ENSURE  ( sector ctx -- )
    2DUP _VFAT-C.CDIRSEC + @  = IF  2DROP EXIT  THEN
    \ Flush dirty dir cache
    DUP _VFAT-C.DDIR + @ IF
        DUP _VFAT-C.CDIRSEC + @  DISK-SEC!
        DUP _VFAT-C.DIRSEC +     DISK-DMA!
        1 DISK-N!  DISK-WRITE
        0 OVER _VFAT-C.DDIR + !
    THEN
    OVER DISK-SEC!
    DUP _VFAT-C.DIRSEC +  DISK-DMA!
    1 DISK-N!  DISK-READ
    _VFAT-C.CDIRSEC + ! ;

\ =====================================================================
\  Inode → Dir Entry Accessor
\ =====================================================================
\
\  Each inode stores a packed dir-entry location in IN.BDATA 8 +:
\    packed = abs_sector * 16 + entry_index_in_sector
\  (16 entries per 512-byte sector, each 32 bytes)

VARIABLE _VFID-CTX

: _VFAT-INODE-DE  ( inode ctx -- de-addr )
    _VFID-CTX !
    IN.BDATA 8 + @
    DUP 16 /
    _VFID-CTX @ _VFAT-DIR-ENSURE
    16 MOD  _VFAT-DIRENT-SIZE *
    _VFID-CTX @ _VFAT-C.DIRSEC + + ;

\ =====================================================================
\  Init  ( vfs -- ior )
\ =====================================================================

VARIABLE _VFI-V
VARIABLE _VFI-CTX

: _VFAT-INIT  ( vfs -- ior )
    _VFI-V !
    DISK? 0= IF  -1 EXIT  THEN
    _VFI-V @ V.ARENA @  _VFAT-CTX-SIZE ARENA-ALLOT  _VFI-CTX !
    _VFI-CTX @  _VFAT-CTX-SIZE  0 FILL
    _VFI-CTX @  _VFI-V @ V.BCTX !
    0 DISK-SEC!
    _VFI-CTX @ _VFAT-C.BPB +  DISK-DMA!
    1 DISK-N!  DISK-READ
    _VFI-CTX @ _VFAT-C.BPB +  _VFI-V @  _VFAT-PROBE 0= IF
        -2 EXIT
    THEN
    _VFI-CTX @  _VFAT-PARSE-BPB
    DUP 0<> IF  EXIT  THEN
    DROP
    -1  _VFI-CTX @ _VFAT-C.CFATSEC + !
    -1  _VFI-CTX @ _VFAT-C.CDIRSEC + !
    0   _VFI-CTX @ _VFAT-C.DFAT + !
    0   _VFI-CTX @ _VFAT-C.DDIR + !
    0 ;

\ =====================================================================
\  Directory Scanning  — Common Entry Handler
\ =====================================================================
\
\  _VFAT-SCAN-ONE-DE processes a single 32-byte directory entry.
\  Skips free (0x00), deleted (0xE5), LFN, volume-labels, . and ..
\  Otherwise allocates a VFS child inode, sets name/size/BID/BDATA.

VARIABLE _VFSD-IN
VARIABLE _VFSD-V
VARIABLE _VFSD-CTX

: _VFAT-SCAN-ONE-DE  ( de packed-loc parent-inode vfs ctx -- )
    _VFSD-CTX !  _VFSD-V !  _VFSD-IN !    ( de packed-loc )
    SWAP                                     ( packed-loc de )
    DUP C@ 0= IF 2DROP EXIT THEN
    DUP C@ 229 = IF 2DROP EXIT THEN
    DUP _VFAT-DE.ATTR + C@ 15 AND 15 = IF 2DROP EXIT THEN
    DUP _VFAT-DE.ATTR + C@ _VFAT-ATTR-VOLLABEL AND IF 2DROP EXIT THEN
    DUP C@ [CHAR] . = IF
        DUP 1+ C@ 32 = IF 2DROP EXIT THEN
        DUP 1+ C@ [CHAR] . = IF
            DUP 2 + C@ 32 = IF 2DROP EXIT THEN
        THEN
    THEN
    DUP _VFAT-DE.ATTR + C@ _VFAT-ATTR-DIR AND IF
        VFS-T-DIR
    ELSE
        VFS-T-FILE
    THEN
    _VFSD-V @ _VFS-INODE-ALLOC           ( packed-loc de inode )
    OVER _VFAT-SFN>NAME
    _VFSD-V @ _VFS-STR-ALLOC
    OVER IN.NAME !                         ( packed-loc de inode )
    OVER _VFAT-DE-CLUSTER
    DUP 2 PICK IN.BID !
    OVER IN.BDATA !                        ( packed-loc de inode )
    ROT OVER IN.BDATA 8 + !              ( de inode )
    OVER _VFAT-DE.FILESZ + L@
    OVER IN.SIZE-LO !
    0 OVER IN.SIZE-HI !
    0 OVER IN.FLAGS !
    DUP _VFSD-IN @  _VFS-ADD-CHILD
    _VFSD-V @ V.ICOUNT DUP @ 1+ SWAP !
    DROP DROP ;

\ =====================================================================
\  FAT16 Root Directory Scanner
\ =====================================================================

VARIABLE _VFRS-PAR
VARIABLE _VFRS-V
VARIABLE _VFRS-CTX

: _VFAT-SCAN-ROOT-16  ( parent-inode vfs ctx -- )
    _VFRS-CTX !  _VFRS-V !  _VFRS-PAR !
    _VFRS-CTX @ _VFAT-C.RENT + @     ( max-entries )
    0 DO
        I _VFAT-DIRENT-SIZE *         ( byte-off )
        DUP _VFAT-SECTOR /            ( byte-off sec-in-root )
        _VFRS-CTX @ _VFAT-C.RDSTART + @ +  ( byte-off abs-sector )
        DUP >R
        _VFRS-CTX @ _VFAT-DIR-ENSURE  ( byte-off  R: abs-sec )
        _VFAT-SECTOR MOD               ( off-in-sec  R: abs-sec )
        DUP _VFAT-DIRENT-SIZE /        ( off-in-sec entry-idx  R: abs-sec )
        R> 16 * +                      ( off-in-sec packed-loc )
        SWAP _VFRS-CTX @ _VFAT-C.DIRSEC + +  ( packed-loc de-addr )
        SWAP                            ( de-addr packed-loc )
        _VFRS-PAR @  _VFRS-V @  _VFRS-CTX @
        _VFAT-SCAN-ONE-DE
    LOOP ;

\ =====================================================================
\  Cluster-Chain Directory Scanner
\ =====================================================================

VARIABLE _VFCS-CUR
VARIABLE _VFCS-PAR
VARIABLE _VFCS-V
VARIABLE _VFCS-CTX

: _VFAT-SCAN-CLUS-DIR  ( first-clus parent-inode vfs ctx -- )
    _VFCS-CTX !  _VFCS-V !  _VFCS-PAR !  _VFCS-CUR !
    BEGIN
        _VFCS-CUR @ 2 < IF EXIT THEN
        _VFCS-CUR @ _VFCS-CTX @ _VFAT-EOC? IF EXIT THEN
        _VFCS-CTX @ _VFAT-C.SPC + @ _VFAT-SECTOR *
        _VFAT-DIRENT-SIZE /             ( entries-per-cluster )
        0 DO
            I _VFAT-DIRENT-SIZE *       ( byte-off-in-cluster )
            DUP _VFAT-SECTOR /
            _VFCS-CUR @ _VFCS-CTX @ _VFAT-CLUS>SEC +  ( byte-off abs-sec )
            DUP >R
            _VFCS-CTX @ _VFAT-DIR-ENSURE  ( byte-off  R: abs-sec )
            _VFAT-SECTOR MOD               ( off-in-sec  R: abs-sec )
            DUP _VFAT-DIRENT-SIZE /        ( off-in-sec entry-idx  R: abs-sec )
            R> 16 * +                      ( off-in-sec packed-loc )
            SWAP _VFCS-CTX @ _VFAT-C.DIRSEC + +  ( packed-loc de-addr )
            SWAP
            _VFCS-PAR @  _VFCS-V @  _VFCS-CTX @
            _VFAT-SCAN-ONE-DE
        LOOP
        _VFCS-CUR @ _VFCS-CTX @ _VFAT-NEXT-CLUSTER _VFCS-CUR !
    AGAIN ;

\ =====================================================================
\  Find Free Dir Entry (for CREATE)
\ =====================================================================

VARIABLE _VFFR-CTX

: _VFAT-FIND-FREE-ROOT-16  ( ctx -- de-addr packed-loc | 0 0 )
    _VFFR-CTX !
    _VFFR-CTX @ _VFAT-C.RENT + @     ( max-entries )
    0 DO
        I _VFAT-DIRENT-SIZE *
        DUP _VFAT-SECTOR /
        _VFFR-CTX @ _VFAT-C.RDSTART + @ +
        DUP >R
        _VFFR-CTX @ _VFAT-DIR-ENSURE
        _VFAT-SECTOR MOD
        DUP _VFAT-DIRENT-SIZE /
        R> 16 * +                      ( off-in-sec packed-loc )
        SWAP _VFFR-CTX @ _VFAT-C.DIRSEC + +  ( packed-loc de-addr )
        DUP C@ 0= IF
            SWAP UNLOOP EXIT           ( de-addr packed-loc )
        THEN
        2DROP
    LOOP
    0 0 ;

VARIABLE _VFFF-CTX
VARIABLE _VFFF-CUR

: _VFAT-FIND-FREE-CLUS-DIR  ( first-cluster ctx -- de-addr packed-loc | 0 0 )
    _VFFF-CTX !  _VFFF-CUR !
    BEGIN
        _VFFF-CUR @ 2 < IF 0 0 EXIT THEN
        _VFFF-CUR @ _VFFF-CTX @ _VFAT-EOC? IF 0 0 EXIT THEN
        _VFFF-CTX @ _VFAT-C.SPC + @ _VFAT-SECTOR *
        _VFAT-DIRENT-SIZE /
        0 DO
            I _VFAT-DIRENT-SIZE *
            DUP _VFAT-SECTOR /
            _VFFF-CUR @ _VFFF-CTX @ _VFAT-CLUS>SEC +
            DUP >R
            _VFFF-CTX @ _VFAT-DIR-ENSURE
            _VFAT-SECTOR MOD
            DUP _VFAT-DIRENT-SIZE /
            R> 16 * +
            SWAP _VFFF-CTX @ _VFAT-C.DIRSEC + +
            DUP C@ 0= IF
                SWAP UNLOOP EXIT       ( de-addr packed-loc )
            THEN
            2DROP
        LOOP
        _VFFF-CUR @ _VFFF-CTX @ _VFAT-NEXT-CLUSTER _VFFF-CUR !
    AGAIN ;

\ =====================================================================
\  VFAT-INIT — public wrapper (calls _VFAT-INIT + populates root)
\ =====================================================================

VARIABLE _VFATI-V
VARIABLE _VFATI-CTX

: VFAT-INIT  ( vfs -- ior )
    DUP _VFAT-INIT
    DUP 0<> IF  NIP EXIT  THEN
    DROP
    DUP V.BCTX @  _VFATI-CTX !
    _VFATI-V !
    _VFATI-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT16 = IF
        _VFATI-V @ V.ROOT @
        _VFATI-V @  _VFATI-CTX @  _VFAT-SCAN-ROOT-16
    ELSE
        _VFATI-CTX @ _VFAT-C.RCLUS + @
        _VFATI-V @ V.ROOT @
        _VFATI-V @  _VFATI-CTX @  _VFAT-SCAN-CLUS-DIR
    THEN
    VFS-IF-CHILDREN  _VFATI-V @ V.ROOT @ IN.FLAGS DUP @ ROT OR SWAP !
    0 ;

\ =====================================================================
\  Readdir  ( inode vfs -- )
\ =====================================================================

VARIABLE _VFRD-IN
VARIABLE _VFRD-V
VARIABLE _VFRD-CTX

: _VFAT-READDIR  ( inode vfs -- )
    _VFRD-V !  _VFRD-IN !
    _VFRD-V @ V.BCTX @  _VFRD-CTX !
    _VFRD-IN @ IN.BID @ 0=
    _VFRD-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT16 =  AND IF
        _VFRD-IN @  _VFRD-V @  _VFRD-CTX @  _VFAT-SCAN-ROOT-16
        EXIT
    THEN
    _VFRD-IN @ IN.BID @
    _VFRD-IN @  _VFRD-V @  _VFRD-CTX @  _VFAT-SCAN-CLUS-DIR ;

\ =====================================================================
\  Read  ( buf len offset inode vfs -- actual )
\ =====================================================================

VARIABLE _VFR-BUF
VARIABLE _VFR-REM
VARIABLE _VFR-IN
VARIABLE _VFR-V
VARIABLE _VFR-CTX
VARIABLE _VFR-CUR
VARIABLE _VFR-COFF
VARIABLE _VFR-ACT
VARIABLE _VFR-SCR
VARIABLE _VFR-BPC
VARIABLE _VFR-SEC
VARIABLE _VFR-SOFF
VARIABLE _VFR-CHUNK

: _VFAT-READ  ( buf len offset inode vfs -- actual )
    _VFR-V !  _VFR-IN !
    _VFR-V @ V.BCTX @ _VFR-CTX !
    _VFR-CTX @ _VFAT-C.SCRATCH + _VFR-SCR !
    _VFR-CTX @ _VFAT-C.SPC + @ _VFAT-SECTOR * _VFR-BPC !
    0 _VFR-ACT !
    ( buf len offset )
    _VFR-IN @ IN.SIZE-LO @ OVER -    ( buf len offset avail )
    DUP 0< IF 2DROP 2DROP 0 EXIT THEN
    ROT MIN                            ( buf offset clamped-len )
    _VFR-REM !                         ( buf offset )
    _VFR-REM @ 0= IF 2DROP 0 EXIT THEN
    SWAP _VFR-BUF !                    ( offset )
    _VFR-IN @ IN.BDATA @  _VFR-CUR !
    DUP _VFR-COFF !
    BEGIN _VFR-COFF @ _VFR-BPC @ >= WHILE
        _VFR-CUR @ _VFR-CTX @ _VFAT-NEXT-CLUSTER _VFR-CUR !
        _VFR-BPC @ NEGATE _VFR-COFF +!
    REPEAT
    DROP
    BEGIN _VFR-REM @ 0> WHILE
        _VFR-CUR @ 2 < IF _VFR-ACT @ EXIT THEN
        _VFR-CUR @ _VFR-CTX @ _VFAT-EOC? IF _VFR-ACT @ EXIT THEN
        _VFR-COFF @ _VFAT-SECTOR /
        _VFR-CUR @ _VFR-CTX @ _VFAT-CLUS>SEC +  _VFR-SEC !
        _VFR-COFF @ _VFAT-SECTOR MOD              _VFR-SOFF !
        _VFAT-SECTOR _VFR-SOFF @ - _VFR-REM @ MIN _VFR-CHUNK !
        _VFR-CHUNK @ 0= IF _VFR-ACT @ EXIT THEN
        _VFR-SEC @ DISK-SEC!
        _VFR-SCR @ DISK-DMA! 1 DISK-N! DISK-READ
        _VFR-SCR @ _VFR-SOFF @ +  _VFR-BUF @  _VFR-CHUNK @  CMOVE
        _VFR-CHUNK @ DUP _VFR-ACT +!
        DUP _VFR-BUF +!
        DUP _VFR-COFF +!
        NEGATE _VFR-REM +!
        _VFR-COFF @ _VFR-BPC @ >= IF
            _VFR-CUR @ _VFR-CTX @ _VFAT-NEXT-CLUSTER _VFR-CUR !
            _VFR-BPC @ NEGATE _VFR-COFF +!
        THEN
    REPEAT
    _VFR-ACT @ ;

\ =====================================================================
\  Write  ( buf len offset inode vfs -- actual )
\ =====================================================================

VARIABLE _VFW-BUF
VARIABLE _VFW-REM
VARIABLE _VFW-IN
VARIABLE _VFW-V
VARIABLE _VFW-CTX
VARIABLE _VFW-CUR
VARIABLE _VFW-COFF
VARIABLE _VFW-ACT
VARIABLE _VFW-SCR
VARIABLE _VFW-BPC
VARIABLE _VFW-PREV
VARIABLE _VFW-ORIGOFF
VARIABLE _VFW-SEC
VARIABLE _VFW-SOFF
VARIABLE _VFW-CHUNK

: _VFAT-WRITE-EXTEND  ( -- cluster | 0 )
    _VFW-CTX @ _VFAT-ALLOC-CLUSTER  DUP 0= IF EXIT THEN
    DUP _VFW-PREV @ _VFW-CTX @ _VFAT-SET-FAT ;

: _VFAT-WRITE  ( buf len offset inode vfs -- actual )
    _VFW-V !  _VFW-IN !
    _VFW-V @ V.BCTX @ _VFW-CTX !
    _VFW-CTX @ _VFAT-C.SCRATCH + _VFW-SCR !
    _VFW-CTX @ _VFAT-C.SPC + @ _VFAT-SECTOR * _VFW-BPC !
    0 _VFW-ACT !  0 _VFW-PREV !
    ( buf len offset )
    DUP >R
    ROT _VFW-BUF !  SWAP _VFW-REM !    ( offset )
    R> _VFW-ORIGOFF !
    _VFW-REM @ 0= IF DROP 0 EXIT THEN
    \ Ensure at least one cluster
    _VFW-IN @ IN.BDATA @  _VFW-CUR !
    _VFW-CUR @ 0= IF
        _VFW-CTX @ _VFAT-ALLOC-CLUSTER  _VFW-CUR !
        _VFW-CUR @ 0= IF DROP 0 EXIT THEN
        _VFW-CUR @ _VFW-IN @ IN.BDATA !
        _VFW-CUR @ _VFW-IN @ IN.BID !
    THEN
    DUP _VFW-COFF !  DROP
    \ Skip full clusters (extending chain as needed)
    BEGIN _VFW-COFF @ _VFW-BPC @ >= WHILE
        _VFW-CUR @ _VFW-PREV !
        _VFW-CUR @ _VFW-CTX @ _VFAT-NEXT-CLUSTER
        DUP _VFW-CTX @ _VFAT-EOC? IF
            DROP _VFAT-WRITE-EXTEND
            DUP 0= IF _VFW-ACT @ EXIT THEN
        THEN
        _VFW-CUR !
        _VFW-BPC @ NEGATE _VFW-COFF +!
    REPEAT
    \ Write loop — one sector at a time
    BEGIN _VFW-REM @ 0> WHILE
        _VFW-CUR @ 2 < IF _VFW-ACT @ EXIT THEN
        _VFW-COFF @ _VFAT-SECTOR /
        _VFW-CUR @ _VFW-CTX @ _VFAT-CLUS>SEC +  _VFW-SEC !
        _VFW-COFF @ _VFAT-SECTOR MOD              _VFW-SOFF !
        _VFAT-SECTOR _VFW-SOFF @ - _VFW-REM @ MIN _VFW-CHUNK !
        _VFW-CHUNK @ 0= IF _VFW-ACT @ EXIT THEN
        _VFW-SOFF @ 0<>  _VFW-CHUNK @ _VFAT-SECTOR <  OR IF
            \ Partial: read-modify-write
            _VFW-SEC @ DISK-SEC!
            _VFW-SCR @ DISK-DMA! 1 DISK-N! DISK-READ
            _VFW-BUF @  _VFW-SCR @ _VFW-SOFF @ +  _VFW-CHUNK @  CMOVE
            _VFW-SEC @ DISK-SEC!
            _VFW-SCR @ DISK-DMA! 1 DISK-N! DISK-WRITE
        ELSE
            \ Full sector DMA
            _VFW-SEC @ DISK-SEC!
            _VFW-BUF @ DISK-DMA! 1 DISK-N! DISK-WRITE
        THEN
        _VFW-CHUNK @ DUP _VFW-ACT +!
        DUP _VFW-BUF +!
        DUP _VFW-COFF +!
        NEGATE _VFW-REM +!
        \ Advance cluster if needed
        _VFW-COFF @ _VFW-BPC @ >= IF
            _VFW-CUR @ _VFW-PREV !
            _VFW-CUR @ _VFW-CTX @ _VFAT-NEXT-CLUSTER
            DUP _VFW-CTX @ _VFAT-EOC? IF
                DROP
                _VFW-REM @ 0> IF
                    _VFAT-WRITE-EXTEND
                    DUP 0= IF _VFW-ACT @ EXIT THEN
                ELSE 0 THEN
            THEN
            _VFW-CUR !
            _VFW-BPC @ NEGATE _VFW-COFF +!
        THEN
    REPEAT
    \ Update file size in inode and dir entry
    _VFW-ACT @ 0> IF
        _VFW-ORIGOFF @ _VFW-ACT @ +
        _VFW-IN @ IN.SIZE-LO @ MAX
        DUP _VFW-IN @ IN.SIZE-LO !
        _VFW-IN @ _VFW-CTX @ _VFAT-INODE-DE
        _VFAT-DE.FILESZ + L!
        -1 _VFW-CTX @ _VFAT-C.DDIR + !
        VFS-IF-DIRTY _VFW-IN @ IN.FLAGS DUP @ ROT OR SWAP !
    THEN
    _VFW-ACT @ ;

\ =====================================================================
\  Sync  ( inode vfs -- ior )
\ =====================================================================

: _VFAT-SYNC  ( inode vfs -- ior )
    NIP V.BCTX @                     ( ctx )
    DUP _VFAT-C.DFAT + @ IF
        DUP _VFAT-C.CFATSEC + @  DISK-SEC!
        DUP _VFAT-C.FATSEC +     DISK-DMA!
        1 DISK-N!  DISK-WRITE
        \ Second FAT copy
        DUP _VFAT-C.CFATSEC + @
        OVER _VFAT-C.FATSZ + @ +   DISK-SEC!
        DUP _VFAT-C.FATSEC +       DISK-DMA!
        1 DISK-N!  DISK-WRITE
        0 OVER _VFAT-C.DFAT + !
    THEN
    DUP _VFAT-C.DDIR + @ IF
        DUP _VFAT-C.CDIRSEC + @  DISK-SEC!
        DUP _VFAT-C.DIRSEC +     DISK-DMA!
        1 DISK-N!  DISK-WRITE
        0 OVER _VFAT-C.DDIR + !
    THEN
    DROP 0 ;

\ =====================================================================
\  Create  ( inode vfs -- ior )
\ =====================================================================

VARIABLE _VFCR-IN
VARIABLE _VFCR-V
VARIABLE _VFCR-CTX
VARIABLE _VFCR-CLUS

: _VFAT-CREATE  ( inode vfs -- ior )
    _VFCR-V !  _VFCR-IN !
    _VFCR-V @ V.BCTX @  _VFCR-CTX !
    \ Allocate initial cluster
    _VFCR-CTX @ _VFAT-ALLOC-CLUSTER  _VFCR-CLUS !
    _VFCR-CLUS @ 0= IF -2 EXIT THEN
    \ Set inode binding fields
    _VFCR-CLUS @ _VFCR-IN @ IN.BID !
    _VFCR-CLUS @ _VFCR-IN @ IN.BDATA !
    \ Find free slot in parent directory
    _VFCR-IN @ IN.PARENT @
    DUP 0= IF DROP _VFCR-V @ V.ROOT @ THEN
    DUP IN.BID @ 0=
    _VFCR-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT16 =  AND IF
        DROP
        _VFCR-CTX @ _VFAT-FIND-FREE-ROOT-16
    ELSE
        IN.BID @  _VFCR-CTX @ _VFAT-FIND-FREE-CLUS-DIR
    THEN
    ( de-addr packed-loc | 0 0 )
    DUP 0= IF
        2DROP
        _VFCR-CLUS @ _VFCR-CTX @ _VFAT-FREE-CHAIN
        -1 EXIT
    THEN
    _VFCR-IN @ IN.BDATA 8 + !         ( de-addr )
    DUP _VFAT-DIRENT-SIZE 0 FILL
    \ Build SFN name
    _VFCR-IN @ IN.NAME @ _VFS-STR-GET
    _VFAT-MAKE-SFN DROP
    _VFAT-SFN-BUF OVER 11 CMOVE       ( de )
    \ Set attributes
    _VFCR-IN @ IN.TYPE @ VFS-T-DIR = IF
        _VFAT-ATTR-DIR
    ELSE
        _VFAT-ATTR-ARCHIVE
    THEN  OVER _VFAT-DE.ATTR + C!     ( de )
    \ Set cluster
    _VFCR-CLUS @ OVER _VFAT-DE.CLUSLO + W!
    _VFCR-CLUS @ 16 RSHIFT OVER _VFAT-DE.CLUSHI + W!
    \ Set file size = 0
    0 OVER _VFAT-DE.FILESZ + L!
    DROP
    -1 _VFCR-CTX @ _VFAT-C.DDIR + !
    0 ;

\ =====================================================================
\  Delete  ( inode vfs -- ior )   — NO TOMBSTONES
\ =====================================================================
\
\  Zeros the 32-byte directory entry entirely (byte 0 = 0x00).
\  Does NOT use the FAT 0xE5 tombstone convention.

VARIABLE _VFD-IN
VARIABLE _VFD-V
VARIABLE _VFD-CTX

: _VFAT-DELETE  ( inode vfs -- ior )
    _VFD-V !  _VFD-IN !
    _VFD-V @ V.BCTX @  _VFD-CTX !
    \ Free cluster chain
    _VFD-IN @ IN.BDATA @  DUP 2 >= IF
        _VFD-CTX @ _VFAT-FREE-CHAIN
    ELSE DROP THEN
    \ Zero the directory entry (no tombstone)
    _VFD-IN @ _VFD-CTX @ _VFAT-INODE-DE
    _VFAT-DIRENT-SIZE 0 FILL
    -1 _VFD-CTX @ _VFAT-C.DDIR + !
    0 ;

\ =====================================================================
\  Truncate  ( inode vfs -- ior )
\ =====================================================================

VARIABLE _VFT-IN
VARIABLE _VFT-V
VARIABLE _VFT-CTX

: _VFAT-TRUNCATE  ( inode vfs -- ior )
    _VFT-V !  _VFT-IN !
    _VFT-V @ V.BCTX @  _VFT-CTX !
    _VFT-IN @ _VFT-CTX @ _VFAT-INODE-DE
    _VFT-IN @ IN.SIZE-LO @
    SWAP _VFAT-DE.FILESZ + L!
    -1 _VFT-CTX @ _VFAT-C.DDIR + !
    0 ;

\ =====================================================================
\  Teardown  ( vfs -- )
\ =====================================================================

: _VFAT-TEARDOWN  ( vfs -- )
    DUP V.BCTX @ 0= IF  DROP EXIT  THEN
    0 OVER _VFAT-SYNC DROP
    0 SWAP V.BCTX ! ;

\ =====================================================================
\  Vtable
\ =====================================================================

CREATE VFAT-VTABLE  VFS-VT-SIZE ALLOT
' _VFAT-PROBE     VFAT-VTABLE  VFS-VT-PROBE    CELLS + !
' VFAT-INIT       VFAT-VTABLE  VFS-VT-INIT     CELLS + !
' _VFAT-TEARDOWN  VFAT-VTABLE  VFS-VT-TEARDOWN CELLS + !
' _VFAT-READ      VFAT-VTABLE  VFS-VT-READ     CELLS + !
' _VFAT-WRITE     VFAT-VTABLE  VFS-VT-WRITE    CELLS + !
' _VFAT-READDIR   VFAT-VTABLE  VFS-VT-READDIR  CELLS + !
' _VFAT-SYNC      VFAT-VTABLE  VFS-VT-SYNC     CELLS + !
' _VFAT-CREATE    VFAT-VTABLE  VFS-VT-CREATE   CELLS + !
' _VFAT-DELETE    VFAT-VTABLE  VFS-VT-DELETE    CELLS + !
' _VFAT-TRUNCATE  VFAT-VTABLE  VFS-VT-TRUNCATE CELLS + !

\ =====================================================================
\  Convenience: VFAT-NEW  ( arena -- vfs )
\ =====================================================================

: VFAT-NEW  ( arena -- vfs )
    VFAT-VTABLE VFS-NEW ;
