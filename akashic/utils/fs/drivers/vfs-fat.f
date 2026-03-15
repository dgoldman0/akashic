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
\  8.3 Short Filename Helpers
\ =====================================================================
\
\  FAT SFN is 8+3 bytes, space-padded, stored uppercase.
\  We convert the VFS name (e.g. "readme.txt") to the padded 11-byte
\  form, case-insensitively.

CREATE _VFAT-SFN-BUF 11 ALLOT   \ compiled 8.3 scratch

\ Convert lowercase a-z to uppercase A-Z
: _VFAT-UPCHAR  ( c -- C )
    DUP [CHAR] a >=  OVER [CHAR] z <=  AND IF
        32 -
    THEN ;

\ Build 11-byte SFN from ( c-addr u ).
\ Returns TRUE if conversion succeeded, FALSE if name is too long
\ or contains illegal characters.
VARIABLE _VFAT-SFN-OK

: _VFAT-MAKE-SFN  ( c-addr u -- flag )
    \ Clear buffer to spaces
    _VFAT-SFN-BUF 11 32 FILL
    1 _VFAT-SFN-OK !
    \ Parse base name (up to 8 chars before '.')
    0 >R                           \ R: dst-index (into SFN buf)
    0 DO                            ( c-addr )
        DUP I + C@                  ( c-addr ch )
        DUP [CHAR] . = IF
            DROP
            \ Fill rest of base with spaces (already filled)
            \ Skip to extension
            I 1+  >R DROP          \ new src index on R
            R> R> DROP >R          \ ... actually, rethink:
            \ We need to parse extension now
            LEAVE
        THEN
        _VFAT-UPCHAR
        R@ 8 < IF
            _VFAT-SFN-BUF R@ +  C!
            R> 1+ >R
        ELSE
            DROP  0 _VFAT-SFN-OK !
        THEN
    LOOP
    DROP                            ( )
    R> DROP
    \ TODO: parse extension portion
    \ For scaffold, just return the flag
    _VFAT-SFN-OK @ ;

\ Compare 11-byte SFN with a directory entry's name field
: _VFAT-SFN=  ( de -- flag )
    _VFAT-SFN-BUF 11  ROT  11 0 DO
        OVER I + C@  2 PICK I + C@  <> IF
            2DROP DROP FALSE UNLOOP EXIT
        THEN
    LOOP
    2DROP DROP TRUE ;

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
\  Init  ( vfs -- ior )
\ =====================================================================
\
\  Allocate binding context, DMA-read sector 0 (BPB), parse
\  geometry, validate FAT type.

VARIABLE _VFI-V
VARIABLE _VFI-CTX

: _VFAT-INIT  ( vfs -- ior )
    _VFI-V !
    \ Check disk present
    DISK? 0= IF  -1 EXIT  THEN
    \ Allocate context from arena
    _VFI-V @ V.ARENA @  _VFAT-CTX-SIZE ARENA-ALLOT  _VFI-CTX !
    _VFI-CTX @  _VFAT-CTX-SIZE  0 FILL
    _VFI-CTX @  _VFI-V @ V.BCTX !
    \ Read sector 0 (BPB)
    0 DISK-SEC!
    _VFI-CTX @ _VFAT-C.BPB +  DISK-DMA!
    1 DISK-N!  DISK-READ
    \ Verify probe
    _VFI-CTX @ _VFAT-C.BPB +  _VFI-V @  _VFAT-PROBE 0= IF
        -2 EXIT
    THEN
    \ Parse BPB → geometry cells
    _VFI-CTX @  _VFAT-PARSE-BPB
    DUP 0<> IF  EXIT  THEN
    DROP
    \ Invalidate caches
    -1  _VFI-CTX @ _VFAT-C.CFATSEC + !
    -1  _VFI-CTX @ _VFAT-C.CDIRSEC + !
    0   _VFI-CTX @ _VFAT-C.DFAT + !
    0   _VFI-CTX @ _VFAT-C.DDIR + !
    0 ;

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
    \ TODO §1.3 — scan root directory, create child inodes
    \ For FAT16: walk root-dir-start sectors (fixed-size area)
    \ For FAT32: walk root-cluster chain
    0 ;

\ =====================================================================
\  Readdir  ( inode vfs -- )
\ =====================================================================
\
\  Scan the directory starting at the inode's first cluster
\  (or the fixed root-dir area for FAT16 root).  For each
\  non-deleted, non-LFN 32-byte entry, allocate a child inode.

: _VFAT-READDIR  ( inode vfs -- )
    \ TODO §1.3 — directory traversal
    2DROP ;

\ =====================================================================
\  Read  ( buf len offset inode vfs -- actual )
\ =====================================================================

: _VFAT-READ  ( buf len offset inode vfs -- actual )
    \ TODO §1.4 — cluster-chain read with partial sector handling
    2DROP 2DROP DROP 0 ;

\ =====================================================================
\  Write  ( buf len offset inode vfs -- actual )
\ =====================================================================

: _VFAT-WRITE  ( buf len offset inode vfs -- actual )
    \ TODO §1.5 — cluster-chain write + allocation
    2DROP 2DROP DROP 0 ;

\ =====================================================================
\  Sync  ( inode vfs -- ior )
\ =====================================================================
\
\  Flush dirty FAT and directory sector caches to disk.
\  Writes both FAT copies for consistency.

: _VFAT-SYNC  ( inode vfs -- ior )
    NIP V.BCTX @                     ( ctx )
    DUP _VFAT-C.DFAT + @ IF
        DUP _VFAT-C.CFATSEC + @  DISK-SEC!
        DUP _VFAT-C.FATSEC +     DISK-DMA!
        1 DISK-N!  DISK-WRITE
        \ TODO: write second FAT copy
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

: _VFAT-CREATE  ( inode vfs -- ior )
    \ TODO §1.5 — allocate dir entry + cluster, populate SFN
    2DROP 0 ;

\ =====================================================================
\  Delete  ( inode vfs -- ior )
\ =====================================================================

: _VFAT-DELETE  ( inode vfs -- ior )
    \ TODO §1.5 — mark dir entry 0xE5, free cluster chain
    2DROP 0 ;

\ =====================================================================
\  Truncate  ( inode vfs -- ior )
\ =====================================================================

: _VFAT-TRUNCATE  ( inode vfs -- ior )
    \ TODO §1.5 — update dir entry size, free excess clusters
    2DROP 0 ;

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
' _VFAT-INIT      VFAT-VTABLE  VFS-VT-INIT     CELLS + !
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
