\ vfs-fat.f — FAT16/FAT32 binding for the VFS layer
\
\ Bridges the abstract VFS to FAT16 and FAT32 formatted volumes.  This
\ binding is intentionally read-only: every mount owns one explicit,
\ generation-bound KDOS volume and every byte transfer uses VOL-READ.
\ Mutation capabilities are not advertised and no write fallback exists.
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

: _VFAT-READY?  ( vfs -- flag )
    V.BCTX @ DUP 0= IF DROP FALSE EXIT THEN
    _VFAT-C.TYPE + @ 0<> ;

\ Translate KDOS block/volume iors into the public VFS layout.  The
\ backend's meaningful low 32 bits remain available as VFS detail.
VARIABLE _VFAT-IO-V
VARIABLE _VFAT-IO-EXPECTED
VARIABLE _VFAT-IO-COMPLETED
VARIABLE _VFAT-IO-BACKEND
VARIABLE _VFAT-IO-FLAGS
VARIABLE _VFAT-IO-REASON

: _VFAT-LATCH-STALE  ( -- )
    _VFAT-IO-V @ ?DUP IF VFS-L-STALE SWAP V.LIFECYCLE ! THEN ;

: _VFAT-MAP-IOR  ( backend-ior -- vfs-ior )
    DUP _VFAT-IO-BACKEND !
    0 _VFAT-IO-FLAGS !
    _VFS-R-IO _VFAT-IO-REASON !
    DUP IF
        DUP IOR>FLAGS
        DUP IOR-F-RETRYABLE AND IF
            VFS-IOR-F-RETRYABLE _VFAT-IO-FLAGS +!
        THEN
        DUP IOR-F-PARTIAL AND IF
            VFS-IOR-F-PARTIAL _VFAT-IO-FLAGS +!
        THEN
        DUP IOR-F-CORRUPT AND IF
            VFS-IOR-F-CORRUPT _VFAT-IO-FLAGS +!
            _VFS-R-CORRUPT _VFAT-IO-REASON !
        THEN
        DUP IOR-F-UNSUPPORTED AND IF
            _VFS-R-UNSUPPORTED _VFAT-IO-REASON !
        THEN
        DUP IOR-F-READONLY AND IF
            VFS-IOR-F-READONLY _VFAT-IO-FLAGS +!
            _VFS-R-READONLY _VFAT-IO-REASON !
        THEN
        IOR-F-STALE AND IF
            VFS-IOR-F-STALE _VFAT-IO-FLAGS +!
            _VFS-R-STALE _VFAT-IO-REASON !
            _VFAT-LATCH-STALE
        THEN
    THEN
    _VFAT-IO-COMPLETED @ _VFAT-IO-EXPECTED @ <> IF
        _VFAT-IO-FLAGS @ VFS-IOR-F-PARTIAL OR _VFAT-IO-FLAGS !
    THEN
    _VFAT-IO-BACKEND @ 0=
    _VFAT-IO-COMPLETED @ _VFAT-IO-EXPECTED @ = AND IF
        DROP 0 EXIT
    THEN
    DROP
    _VFAT-IO-BACKEND @ 0xFFFFFFFF AND
    _VFAT-IO-FLAGS @ VFS-IOR-D-VOLUME _VFAT-IO-REASON @ VFS-IOR-MAKE ;

: _VFAT-VOL-READ  ( dma lba count -- ior )
    DUP _VFAT-IO-EXPECTED !
    _VFAT-IO-V @ V.VOLUME @ VOL-READ
    SWAP _VFAT-IO-COMPLETED ! _VFAT-MAP-IOR ;

: _VFAT-FORMAT-CORRUPT  ( detail -- ior )
    VFS-IOR-F-CORRUPT VFS-IOR-D-FORMAT _VFS-R-CORRUPT VFS-IOR-MAKE ;

: _VFAT-PARTIAL-IOR  ( actual ior -- actual ior )
    DUP IF
        OVER 0> IF VFS-IOR-F-PARTIAL 24 LSHIFT OR THEN
    THEN ;

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

60 CONSTANT VFAT-PROBE-SCORE
CREATE _VFATP-BUF _VFAT-SECTOR ALLOT
VARIABLE _VFATP-VOL

: _VFAT-PROBE-VOLUME  ( volume -- score ior )
    _VFATP-VOL !
    _VFATP-VOL @ VOL.SECTOR-SIZE _VFAT-SECTOR <> IF
        0 0 0 VFS-IOR-D-VOLUME VFS-R-UNSUPPORTED VFS-IOR-MAKE EXIT
    THEN
    0 _VFAT-IO-V !
    1 _VFAT-IO-EXPECTED !
    _VFATP-BUF 0 1 _VFATP-VOL @ VOL-READ
    SWAP _VFAT-IO-COMPLETED ! _VFAT-MAP-IOR
    DUP IF 0 SWAP EXIT THEN DROP
    _VFATP-BUF 0 _VFAT-PROBE IF VFAT-PROBE-SCORE ELSE 0 THEN 0 ;

\ =====================================================================
\  BPB Parsing  ( ctx -- ior )
\ =====================================================================
\
\  Extract geometry fields from the BPB cache into the context
\  cells.  Determine FAT type from data cluster count.

VARIABLE _VFP-CTX
VARIABLE _VFP-V
VARIABLE _VFP-FIRST
VARIABLE _VFP-FAT-CAP

: _VFAT-PARSE-BPB  ( ctx vfs -- ior )
    _VFP-V ! _VFP-CTX !
    \ SecPerClus
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.SPC + C@
    _VFP-CTX @ _VFAT-C.SPC + !
    _VFP-CTX @ _VFAT-C.SPC + @ DUP 0= IF
        DROP 10 _VFAT-FORMAT-CORRUPT EXIT
    THEN
    DUP DUP 1- AND IF DROP 11 _VFAT-FORMAT-CORRUPT EXIT THEN
    128 > IF 12 _VFAT-FORMAT-CORRUPT EXIT THEN
    \ RsvdSecCnt
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.RSVD + W@
    _VFP-CTX @ _VFAT-C.RSVD + !
    _VFP-CTX @ _VFAT-C.RSVD + @ 0= IF
        13 _VFAT-FORMAT-CORRUPT EXIT
    THEN
    \ NumFATs
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.NFATS + C@
    _VFP-CTX @ _VFAT-C.NFATS + !
    _VFP-CTX @ _VFAT-C.NFATS + @ 0= IF
        14 _VFAT-FORMAT-CORRUPT EXIT
    THEN
    \ FATSz: prefer FATSz16; if 0, use FATSz32
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.FATSZ16 + W@
    DUP 0= IF
        DROP  _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.FATSZ32 + L@
    THEN
    _VFP-CTX @ _VFAT-C.FATSZ + !
    _VFP-CTX @ _VFAT-C.FATSZ + @ 0= IF
        15 _VFAT-FORMAT-CORRUPT EXIT
    THEN
    \ TotSec: prefer TotSec16; if 0, use TotSec32
    _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.TOT16 + W@
    DUP 0= IF
        DROP  _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.TOT32 + L@
    THEN
    _VFP-CTX @ _VFAT-C.TOTSEC + !
    _VFP-CTX @ _VFAT-C.TOTSEC + @
    _VFP-V @ V.VOLUME @ VOL.SECTORS <> IF
        16 _VFAT-FORMAT-CORRUPT EXIT
    THEN
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
    DUP _VFP-FIRST !
    _VFP-CTX @ _VFAT-C.FDS + !
    _VFP-FIRST @ _VFP-CTX @ _VFAT-C.RSVD + @ U< IF
        17 _VFAT-FORMAT-CORRUPT EXIT
    THEN
    _VFP-FIRST @ _VFP-CTX @ _VFAT-C.TOTSEC + @ >= IF
        18 _VFAT-FORMAT-CORRUPT EXIT
    THEN
    \ DataClusters = (TotSec - FirstDataSector) / SecPerClus
    _VFP-CTX @ _VFAT-C.TOTSEC + @
    _VFP-CTX @ _VFAT-C.FDS + @  -
    _VFP-CTX @ _VFAT-C.SPC + @  /
    _VFP-CTX @ _VFAT-C.DCLUS + !
    \ Determine FAT type
    _VFP-CTX @ _VFAT-C.DCLUS + @
    DUP 4085 < IF
        DROP 1 0 VFS-IOR-D-FORMAT _VFS-R-UNSUPPORTED VFS-IOR-MAKE EXIT
    THEN
    65525 < IF
        _VFAT-TYPE-FAT16  _VFP-CTX @ _VFAT-C.TYPE + !
        \ FAT16 root dir start = RsvdSecCnt + NumFATs*FATSz
        _VFP-CTX @ _VFAT-C.RSVD + @
        _VFP-CTX @ _VFAT-C.NFATS + @  _VFP-CTX @ _VFAT-C.FATSZ + @  *  +
        _VFP-CTX @ _VFAT-C.RDSTART + !
        0 _VFP-CTX @ _VFAT-C.RCLUS + !
        _VFP-CTX @ _VFAT-C.RENT + @ 0= IF
            19 _VFAT-FORMAT-CORRUPT EXIT
        THEN
        _VFP-CTX @ _VFAT-C.FATSZ + @ _VFAT-SECTOR * 2 /
        _VFP-FAT-CAP !
    ELSE
        _VFAT-TYPE-FAT32  _VFP-CTX @ _VFAT-C.TYPE + !
        0 _VFP-CTX @ _VFAT-C.RDSEC + !
        0 _VFP-CTX @ _VFAT-C.RDSTART + !
        \ Root cluster from BPB
        _VFP-CTX @ _VFAT-C.BPB + _VFAT-BPB.ROOTCLUS + L@
        _VFP-CTX @ _VFAT-C.RCLUS + !
        _VFP-CTX @ _VFAT-C.RENT + @ IF
            20 _VFAT-FORMAT-CORRUPT EXIT
        THEN
        _VFP-CTX @ _VFAT-C.RCLUS + @ DUP 2 < IF
            DROP 21 _VFAT-FORMAT-CORRUPT EXIT
        THEN
        _VFP-CTX @ _VFAT-C.DCLUS + @ 2 + >= IF
            22 _VFAT-FORMAT-CORRUPT EXIT
        THEN
        _VFP-CTX @ _VFAT-C.FATSZ + @ _VFAT-SECTOR * 4 /
        _VFP-FAT-CAP !
    THEN
    _VFP-FAT-CAP @ _VFP-CTX @ _VFAT-C.DCLUS + @ 2 + < IF
        23 _VFAT-FORMAT-CORRUPT EXIT
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
VARIABLE _VFE-CTX
VARIABLE _VFE-SEC

: _VFAT-FAT-ENSURE  ( fat-sector ctx -- )
    _VFE-CTX ! _VFE-SEC !
    _VFE-SEC @ _VFE-CTX @ _VFAT-C.CFATSEC + @ = IF EXIT THEN
    _VFE-CTX @ _VFAT-C.FATSEC + _VFE-SEC @ 1 _VFAT-VOL-READ
    ?DUP IF THROW THEN
    _VFE-SEC @ _VFE-CTX @ _VFAT-C.CFATSEC + ! ;

: _VFAT-NEXT-CLUSTER  ( cluster ctx -- next-cluster )
    _VFN-CTX !
    DUP 2 < IF DROP 30 _VFAT-FORMAT-CORRUPT THROW THEN
    DUP _VFN-CTX @ _VFAT-C.DCLUS + @ 2 + >= IF
        DROP 31 _VFAT-FORMAT-CORRUPT THROW
    THEN
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
\  Directory Entry Helpers
\ =====================================================================

: _VFAT-DE-CLUSTER  ( de -- cluster )
    DUP _VFAT-DE.CLUSLO + W@
    SWAP _VFAT-DE.CLUSHI + W@  16 LSHIFT  OR ;

\ =====================================================================
\  8.3 Short Filename Decoder
\ =====================================================================

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

VARIABLE _VFDE-CTX
VARIABLE _VFDE-SEC

: _VFAT-DIR-ENSURE  ( sector ctx -- )
    _VFDE-CTX ! _VFDE-SEC !
    _VFDE-SEC @ _VFDE-CTX @ _VFAT-C.CDIRSEC + @ = IF EXIT THEN
    _VFDE-CTX @ _VFAT-C.DIRSEC + _VFDE-SEC @ 1 _VFAT-VOL-READ
    ?DUP IF THROW THEN
    _VFDE-SEC @ _VFDE-CTX @ _VFAT-C.CDIRSEC + ! ;

\ =====================================================================
\  Init  ( vfs -- ior )
\ =====================================================================

VARIABLE _VFI-V
VARIABLE _VFI-CTX

: _VFAT-INIT  ( vfs -- ior )
    _VFI-V !
    _VFI-V @ _VFAT-IO-V !
    _VFI-V @ V.VOLUME @ DUP 0= IF DROP VFS-E-NOVOLUME EXIT THEN
    DUP VOL-STALE? IF
        DROP _VFAT-LATCH-STALE
        0 VFS-IOR-F-STALE VFS-IOR-D-VOLUME _VFS-R-STALE VFS-IOR-MAKE
        EXIT
    THEN
    DUP VOL-VALID? 0= IF DROP VFS-E-NOVOLUME EXIT THEN
    DUP VOL.SECTOR-SIZE _VFAT-SECTOR <> IF
        DROP 0 0 VFS-IOR-D-VOLUME _VFS-R-UNSUPPORTED VFS-IOR-MAKE EXIT
    THEN
    DUP VOL.COOKIE _VFI-V @ V.VOL-COOKIE !
    VOL.MEDIA-GEN _VFI-V @ V.MEDIA-GEN !
    \ Retain at most one context allocation even when mount fails.
    _VFI-V @ V.BCTX @ ?DUP IF
        _VFI-CTX !
    ELSE
        _VFI-V @ V.ARENA @ _VFAT-CTX-SIZE ARENA-ALLOT?
        IF DROP VFS-E-NOMEM EXIT THEN
        DUP _VFI-CTX ! _VFI-V @ V.BCTX !
    THEN
    _VFI-CTX @  _VFAT-CTX-SIZE  0 FILL
    _VFI-CTX @ _VFAT-C.BPB + 0 1 _VFAT-VOL-READ ?DUP IF EXIT THEN
    _VFI-CTX @ _VFAT-C.BPB +  _VFI-V @  _VFAT-PROBE 0= IF
        1 0 VFS-IOR-D-FORMAT _VFS-R-UNSUPPORTED VFS-IOR-MAKE EXIT
    THEN
    _VFI-CTX @ _VFI-V @ _VFAT-PARSE-BPB
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
VARIABLE _VFSD-NEW

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
    DUP 0= IF 2DROP DROP VFS-E-NOMEM THROW THEN
    DUP _VFSD-NEW !
    OVER _VFAT-SFN>NAME
    _VFSD-V @ _VFS-STR-ALLOC
    DUP 0= IF
        DROP 2DROP DROP
        _VFSD-NEW @ TRUE _VFSD-V @ _VFS-DENTRY-RELEASE
        VFS-E-NOMEM THROW
    THEN
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
        OVER C@ 0= IF 2DROP LEAVE THEN  \ 0x00 terminates the directory
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
VARIABLE _VFCS-LEFT
VARIABLE _VFCS-DONE

: _VFAT-SCAN-CLUS-DIR  ( first-clus parent-inode vfs ctx -- )
    _VFCS-CTX !  _VFCS-V !  _VFCS-PAR !  _VFCS-CUR !
    _VFCS-CTX @ _VFAT-C.DCLUS + @ 1+ _VFCS-LEFT !
    0 _VFCS-DONE !
    BEGIN
        _VFCS-LEFT @ 0= IF 40 _VFAT-FORMAT-CORRUPT THROW THEN
        -1 _VFCS-LEFT +!
        _VFCS-CUR @ 2 < IF 41 _VFAT-FORMAT-CORRUPT THROW THEN
        _VFCS-CUR @ _VFCS-CTX @ _VFAT-EOC? IF EXIT THEN
        _VFCS-CUR @ _VFCS-CTX @ _VFAT-C.DCLUS + @ 2 + >= IF
            42 _VFAT-FORMAT-CORRUPT THROW
        THEN
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
            OVER C@ 0= IF
                2DROP -1 _VFCS-DONE ! LEAVE
            THEN
            _VFCS-PAR @  _VFCS-V @  _VFCS-CTX @
            _VFAT-SCAN-ONE-DE
        LOOP
        _VFCS-DONE @ IF EXIT THEN
        _VFCS-CUR @ _VFCS-CTX @ _VFAT-NEXT-CLUSTER _VFCS-CUR !
    AGAIN ;

\ =====================================================================
\  VFAT-INIT — public wrapper (calls _VFAT-INIT + populates root)
\ =====================================================================

VARIABLE _VFATI-V
VARIABLE _VFATI-CTX

VARIABLE _VFAT-TX-PARENT
VARIABLE _VFAT-TX-V
VARIABLE _VFAT-TX-OLD-CHILD
VARIABLE _VFAT-TX-OLD-COUNT
VARIABLE _VFAT-TX-OLD-STR

: _VFAT-TX-BEGIN  ( parent vfs -- )
    _VFAT-TX-V ! _VFAT-TX-PARENT !
    _VFAT-TX-PARENT @ IN.CHILD @ _VFAT-TX-OLD-CHILD !
    _VFAT-TX-V @ V.ICOUNT @ _VFAT-TX-OLD-COUNT !
    _VFAT-TX-V @ V.STR-PTR @ _VFAT-TX-OLD-STR ! ;

: _VFAT-TX-ROLLBACK  ( -- )
    BEGIN
        _VFAT-TX-PARENT @ IN.CHILD @
        DUP _VFAT-TX-OLD-CHILD @ <>
    WHILE
        DUP _VFAT-TX-PARENT @ _VFS-REMOVE-CHILD
        TRUE _VFAT-TX-V @ _VFS-DENTRY-RELEASE
    REPEAT DROP
    _VFAT-TX-OLD-COUNT @ _VFAT-TX-V @ V.ICOUNT !
    _VFAT-TX-OLD-STR @ _VFAT-TX-V @ V.STR-PTR ! ;

: _VFATI-SCAN-ROOT  ( -- )
    _VFATI-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT16 = IF
        _VFATI-V @ V.ROOT @
        _VFATI-V @  _VFATI-CTX @  _VFAT-SCAN-ROOT-16
    ELSE
        _VFATI-CTX @ _VFAT-C.RCLUS + @
        _VFATI-V @ V.ROOT @
        _VFATI-V @  _VFATI-CTX @  _VFAT-SCAN-CLUS-DIR
    THEN ;

: VFAT-INIT  ( vfs -- ior )
    DUP V.LIFECYCLE @ VFS-L-MOUNTED = IF DROP 0 EXIT THEN
    DUP V.LAST-IOR @ ?DUP IF NIP EXIT THEN
    DUP _VFAT-INIT
    DUP 0<> IF NIP EXIT THEN DROP
    DUP V.BCTX @ _VFATI-CTX !
    DUP _VFAT-IO-V ! _VFATI-V !
    \ Root identity is format-specific.  Core constructs BID=1, but FAT16
    \ uses the fixed root area (sentinel 0) and FAT32 uses BPB RootClus.
    _VFATI-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT16 = IF
        0
    ELSE
        _VFATI-CTX @ _VFAT-C.RCLUS + @
    THEN DUP _VFATI-V @ V.ROOT @ IN.BID !
    _VFATI-V @ V.ROOT @ IN.BDATA !
    _VFATI-V @ V.ROOT @ _VFATI-V @ _VFAT-TX-BEGIN
    ['] _VFATI-SCAN-ROOT CATCH ?DUP IF
        _VFAT-TX-ROLLBACK
        0 _VFATI-CTX @ _VFAT-C.TYPE + !
        EXIT
    THEN
    VFS-IF-CHILDREN  _VFATI-V @ V.ROOT @ IN.FLAGS DUP @ ROT OR SWAP !
    0 ;

\ =====================================================================
\  Readdir  ( inode vfs -- )
\ =====================================================================

VARIABLE _VFRD-IN
VARIABLE _VFRD-V
VARIABLE _VFRD-CTX

: _VFRD-SCAN  ( -- )
    _VFRD-V @ V.BCTX @  _VFRD-CTX !
    _VFRD-IN @ IN.BID @ 0=
    _VFRD-CTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT16 =  AND IF
        _VFRD-IN @  _VFRD-V @  _VFRD-CTX @  _VFAT-SCAN-ROOT-16
        EXIT
    THEN
    _VFRD-IN @ IN.BID @
    _VFRD-IN @  _VFRD-V @  _VFRD-CTX @  _VFAT-SCAN-CLUS-DIR ;

: _VFAT-READDIR  ( inode vfs -- ior )
    DUP _VFAT-READY? 0= IF 2DROP VFS-E-BUSY EXIT THEN
    _VFRD-V ! _VFRD-IN !
    _VFRD-V @ _VFAT-IO-V !
    _VFRD-IN @ _VFRD-V @ _VFAT-TX-BEGIN
    ['] _VFRD-SCAN CATCH
    DUP IF _VFAT-TX-ROLLBACK THEN ;

\ =====================================================================
\  Read  ( buf len offset inode vfs -- actual ior )
\ =====================================================================

VARIABLE _VFR-BUF
VARIABLE _VFR-LEN
VARIABLE _VFR-OFF
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
VARIABLE _VFR-IOR
VARIABLE _VFR-LEFT

: _VFR-VALID-CUR  ( -- )
    _VFR-CUR @ 2 < IF 50 _VFAT-FORMAT-CORRUPT THROW THEN
    _VFR-CUR @ _VFR-CTX @ _VFAT-EOC? IF
        51 _VFAT-FORMAT-CORRUPT THROW
    THEN
    _VFR-CUR @ _VFR-CTX @ _VFAT-C.DCLUS + @ 2 + >= IF
        52 _VFAT-FORMAT-CORRUPT THROW
    THEN ;

: _VFR-ADVANCE  ( -- )
    _VFR-LEFT @ 0= IF 53 _VFAT-FORMAT-CORRUPT THROW THEN
    -1 _VFR-LEFT +!
    _VFR-CUR @ _VFR-CTX @ _VFAT-NEXT-CLUSTER _VFR-CUR ! ;

: _VFR-TRANSFER  ( -- )
    BEGIN _VFR-COFF @ _VFR-BPC @ >= WHILE
        _VFR-VALID-CUR _VFR-ADVANCE
        _VFR-BPC @ NEGATE _VFR-COFF +!
    REPEAT
    BEGIN _VFR-REM @ 0> WHILE
        _VFR-VALID-CUR
        _VFR-COFF @ _VFAT-SECTOR /
        _VFR-CUR @ _VFR-CTX @ _VFAT-CLUS>SEC + _VFR-SEC !
        _VFR-SEC @ _VFR-CTX @ _VFAT-C.TOTSEC + @ >= IF
            54 _VFAT-FORMAT-CORRUPT THROW
        THEN
        _VFR-COFF @ _VFAT-SECTOR MOD _VFR-SOFF !
        _VFAT-SECTOR _VFR-SOFF @ - _VFR-REM @ MIN _VFR-CHUNK !
        _VFR-CHUNK @ 0= IF 55 _VFAT-FORMAT-CORRUPT THROW THEN
        _VFR-SCR @ _VFR-SEC @ 1 _VFAT-VOL-READ _VFR-IOR !
        _VFAT-IO-COMPLETED @ IF
            _VFR-SCR @ _VFR-SOFF @ + _VFR-BUF @ _VFR-CHUNK @ CMOVE
            _VFR-CHUNK @ DUP _VFR-ACT +!
            DUP _VFR-BUF +!
            DUP _VFR-COFF +!
            NEGATE _VFR-REM +!
        THEN
        _VFR-IOR @ ?DUP IF THROW THEN
        _VFR-COFF @ _VFR-BPC @ >= _VFR-REM @ 0> AND IF
            _VFR-ADVANCE
            _VFR-BPC @ NEGATE _VFR-COFF +!
        THEN
    REPEAT ;

: _VFAT-READ  ( buf len offset inode vfs -- actual ior )
    DUP _VFAT-READY? 0= IF 2DROP 2DROP DROP 0 VFS-E-BUSY EXIT THEN
    _VFR-V ! _VFR-IN ! _VFR-OFF ! _VFR-LEN ! _VFR-BUF !
    _VFR-V @ _VFAT-IO-V !
    _VFR-OFF @ 0< _VFR-LEN @ 0< OR IF 0 VFS-E-INVALID EXIT THEN
    _VFR-V @ V.BCTX @ _VFR-CTX !
    _VFR-CTX @ _VFAT-C.SCRATCH + _VFR-SCR !
    _VFR-CTX @ _VFAT-C.SPC + @ _VFAT-SECTOR * _VFR-BPC !
    0 _VFR-ACT !
    _VFR-IN @ IN.SIZE-LO @ _VFR-OFF @ -
    DUP 0< IF DROP 0 0 EXIT THEN
    _VFR-LEN @ MIN _VFR-REM !
    _VFR-REM @ 0= IF 0 0 EXIT THEN
    _VFR-IN @ IN.BDATA @ _VFR-CUR !
    _VFR-OFF @ _VFR-COFF !
    _VFR-CTX @ _VFAT-C.DCLUS + @ 1+ _VFR-LEFT !
    ['] _VFR-TRANSFER CATCH _VFR-IOR !
    _VFR-ACT @ _VFR-IOR @ _VFAT-PARTIAL-IOR ;

\ =====================================================================
\  Disabled mutation entrypoints
\ =====================================================================

\ Mutation entrypoints exist only as explicit fail-closed documentation.
\ They are deliberately absent from VFAT-CAPS and VFAT-OPS.
: _VFAT-WRITE  ( buf len offset inode vfs -- actual ior )
    2DROP 2DROP DROP 0 VFS-E-READONLY ;
: _VFAT-CREATE    ( inode vfs -- ior )  2DROP VFS-E-READONLY ;
: _VFAT-DELETE    ( inode vfs -- ior )  2DROP VFS-E-READONLY ;
: _VFAT-TRUNCATE  ( inode vfs -- ior )  2DROP VFS-E-READONLY ;

\ =====================================================================
\  Read-only ABI adapters and unmount
\ =====================================================================

: _VFAT-OPEN     ( inode vfs -- cookie ior )  2DROP 0 0 ;
: _VFAT-RELEASE  ( cookie inode vfs -- ior )  DROP 2DROP 0 ;
: _VFAT-GETATTR  ( inode vfs -- ior )         2DROP 0 ;
: _VFAT-SYNCFS   ( vfs -- ior )               DROP 0 ;
: _VFAT-FSYNC    ( inode vfs -- ior )         2DROP 0 ;

VARIABLE _VFAT-UM-V
: _VFAT-UNMOUNT  ( flags vfs -- ior )
    _VFAT-UM-V ! DROP
    0 _VFAT-UM-V @ V.BCTX !
    0 ;

\ =====================================================================
\  Validated read-only binding descriptor
\ =====================================================================

VFS-CAP-PROBE VFS-CAP-MOUNT OR VFS-CAP-UNMOUNT OR
VFS-CAP-READDIR OR VFS-CAP-OPEN OR VFS-CAP-RELEASE OR
VFS-CAP-READ OR VFS-CAP-GETATTR OR
VFS-CAP-SYNCFS OR VFS-CAP-FSYNC OR
CONSTANT VFAT-CAPS

CREATE VFAT-OPS  VFS-OPS-SIZE ALLOT
VFAT-OPS VFS-OPS-SIZE 0 FILL
' _VFAT-PROBE-VOLUME VFAT-OPS VFS-OP-PROBE    CELLS + !
' VFAT-INIT       VFAT-OPS VFS-OP-MOUNT    CELLS + !
' _VFAT-UNMOUNT   VFAT-OPS VFS-OP-UNMOUNT  CELLS + !
' _VFAT-READDIR   VFAT-OPS VFS-OP-READDIR  CELLS + !
' _VFAT-OPEN      VFAT-OPS VFS-OP-OPEN     CELLS + !
' _VFAT-RELEASE   VFAT-OPS VFS-OP-RELEASE  CELLS + !
' _VFAT-READ      VFAT-OPS VFS-OP-READ     CELLS + !
' _VFAT-GETATTR   VFAT-OPS VFS-OP-GETATTR  CELLS + !
' _VFAT-SYNCFS    VFAT-OPS VFS-OP-SYNCFS   CELLS + !
' _VFAT-FSYNC     VFAT-OPS VFS-OP-FSYNC    CELLS + !

CREATE VFAT-BINDING
VFS-BINDING-MAGIC ,
VFS-BINDING-ABI-MAJOR ,
VFS-BINDING-ABI-MINOR ,
VFS-BINDING-DESC-SIZE ,
VFS-OPS-SIZE ,
VFAT-CAPS ,
VFS-BF-NEEDS-VOLUME VFS-BF-READ-ONLY OR ,
VFAT-OPS ,
0 , 0 ,

\ =====================================================================
\  Convenience: VFAT-NEW  ( arena volume -- vfs ior )
\ =====================================================================

: VFAT-NEW  ( arena volume -- vfs ior )
    VFAT-BINDING SWAP VFS-NEW ;
