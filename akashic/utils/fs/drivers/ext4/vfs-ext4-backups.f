\ vfs-ext4-backups.f — ext4 sparse-super and copy authority
\
\ Internal dependency of the vfs-ext4.f public facade.

PROVIDED akashic-ext4-backups
REQUIRE vfs-ext4-admission.f
REQUIRE vfs-ext4-descriptor.f

\ =====================================================================
\  Sparse-super backup validation
\ =====================================================================

VARIABLE _EXT4-BS-GROUP
VARIABLE _EXT4-BS-CTX
VARIABLE _EXT4-BS-BLOCK
VARIABLE _EXT4-BS-BUF
VARIABLE _EXT4-BS-PRIMARY

VARIABLE _EXT4-BG-BASE
VARIABLE _EXT4-BG-CTX
VARIABLE _EXT4-BG-BLOCK-BITMAP
VARIABLE _EXT4-BG-INODE-BITMAP
VARIABLE _EXT4-BG-INODE-TABLE
VARIABLE _EXT4-JBT-A
VARIABLE _EXT4-JBT-B

: _EXT4-JOURNAL-BACKUP-TUPLE=?  ( a b -- flag )
    _EXT4-JBT-B ! _EXT4-JBT-A !
    _EXT4-JBT-A @ _EXT4-SB.JOURNAL-BACKUP-TYPE + C@
    _EXT4-JBT-B @ _EXT4-SB.JOURNAL-BACKUP-TYPE + C@ =
    _EXT4-JBT-A @ _EXT4-SB.JOURNAL-BLOCKS +
    _EXT4-JBT-B @ _EXT4-SB.JOURNAL-BLOCKS +
    68 _EXT4-BYTES=? AND ;

\ A backup GDT can lag mutable counters and bitmap checksums after ordinary
\ filesystem activity.  Its own descriptor CRC must nevertheless validate,
\ and the immutable metadata locations must still agree with the primary
\ descriptor.  Reuse the primary descriptor parser so every copy receives
\ the same group-number CRC and bounds checks.
: _EXT4-VALIDATE-BACKUP-GDT  ( gdt-base ctx -- ior )
    _EXT4-BG-CTX ! _EXT4-BG-BASE !
    _EXT4-BG-CTX @ _EXT4-C.GROUPS + @ 0 ?DO
        I _EXT4-BG-CTX @ _EXT4-LOAD-DESC ?DUP IF
            UNLOOP EXIT
        THEN
        _EXT4-BG-CTX @ _EXT4-C.DESC + DUP
            _EXT4-GD.BLOCK-BITMAP-LO + L@ _EXT4-BG-BLOCK-BITMAP !
        DUP _EXT4-GD.INODE-BITMAP-LO + L@ _EXT4-BG-INODE-BITMAP !
        _EXT4-GD.INODE-TABLE-LO + L@ _EXT4-BG-INODE-TABLE !
        I _EXT4-BG-BASE @ _EXT4-BG-CTX @ _EXT4-LOAD-DESC-AT
        ?DUP IF UNLOOP EXIT THEN
        _EXT4-BG-CTX @ _EXT4-C.DESC + DUP
            _EXT4-GD.BLOCK-BITMAP-LO + L@
            _EXT4-BG-BLOCK-BITMAP @ <> IF
                DROP EXT4-D-DESC-CHECKSUM _EXT4-CORRUPT UNLOOP EXIT
            THEN
        DUP _EXT4-GD.INODE-BITMAP-LO + L@
            _EXT4-BG-INODE-BITMAP @ <> IF
                DROP EXT4-D-DESC-CHECKSUM _EXT4-CORRUPT UNLOOP EXIT
            THEN
        _EXT4-GD.INODE-TABLE-LO + L@
            _EXT4-BG-INODE-TABLE @ <> IF
                EXT4-D-DESC-CHECKSUM _EXT4-CORRUPT UNLOOP EXIT
            THEN
    LOOP
    0 ;

\ Compare the immutable profile fields of one checksum-authenticated copy.
\ Mutable counters, timestamps, state, LAST_ORPHAN, RECOVER, and
\ ORPHAN_PRESENT may legitimately differ; the caller supplies the copy's
\ required group number explicitly.
: _EXT4-SUPER-INVARIANTS?  ( candidate group reference -- flag )
    _EXT4-BS-PRIMARY ! _EXT4-BS-GROUP ! _EXT4-BS-BUF !
    _EXT4-BS-BUF @ _EXT4-SB.MAGIC + W@ _EXT4-MAGIC =
    _EXT4-BS-BUF @ _EXT4-SB.GROUP-NR + W@ _EXT4-BS-GROUP @ = AND
    _EXT4-BS-BUF @ _EXT4-SB.INODES + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.INODES + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.BLOCKS-LO + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.BLOCKS-LO + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.BLOCKS-HI + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.BLOCKS-HI + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.FIRST-DATA + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.FIRST-DATA + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.LOG-BLOCK + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.LOG-BLOCK + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.LOG-CLUSTER + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.LOG-CLUSTER + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.BPG + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.BPG + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.CPG + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.CPG + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.IPG + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.IPG + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.REVISION + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.REVISION + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.CREATOR + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.CREATOR + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.INODE-SIZE + W@
        _EXT4-BS-PRIMARY @ _EXT4-SB.INODE-SIZE + W@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.FIRST-INO + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.FIRST-INO + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.ERRORS + W@
        _EXT4-BS-PRIMARY @ _EXT4-SB.ERRORS + W@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.RESERVED-GDT + W@
        _EXT4-BS-PRIMARY @ _EXT4-SB.RESERVED-GDT + W@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.COMPAT + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.COMPAT + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.INCOMPAT + L@
        _EXT4-INCOMPAT-RECOVER INVERT AND
        _EXT4-BS-PRIMARY @ _EXT4-SB.INCOMPAT + L@
        _EXT4-INCOMPAT-RECOVER INVERT AND = AND
    _EXT4-BS-BUF @ _EXT4-SB.RO-COMPAT + L@
        _EXT4-RO-ORPHAN-PRESENT INVERT AND
        _EXT4-BS-PRIMARY @ _EXT4-SB.RO-COMPAT + L@
        _EXT4-RO-ORPHAN-PRESENT INVERT AND = AND
    _EXT4-BS-BUF @ _EXT4-SB.DESC-SIZE + W@
        _EXT4-BS-PRIMARY @ _EXT4-SB.DESC-SIZE + W@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.CSUM-TYPE + C@
        _EXT4-BS-PRIMARY @ _EXT4-SB.CSUM-TYPE + C@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.MIN-EXTRA + W@
        _EXT4-BS-PRIMARY @ _EXT4-SB.MIN-EXTRA + W@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.WANT-EXTRA + W@
        _EXT4-BS-PRIMARY @ _EXT4-SB.WANT-EXTRA + W@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.LOG-FLEX + C@
        _EXT4-BS-PRIMARY @ _EXT4-SB.LOG-FLEX + C@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.CSUM-SEED + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.CSUM-SEED + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.JOURNAL-INO + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.JOURNAL-INO + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.JOURNAL-BACKUP-TYPE + C@
        _EXT4-BS-PRIMARY @ _EXT4-SB.JOURNAL-BACKUP-TYPE + C@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.JOURNAL-BLOCKS +
        _EXT4-BS-PRIMARY @ _EXT4-SB.JOURNAL-BLOCKS +
        68 _EXT4-BYTES=? AND
    _EXT4-BS-BUF @ _EXT4-SB.ORPHAN-INO + L@
        _EXT4-BS-PRIMARY @ _EXT4-SB.ORPHAN-INO + L@ = AND
    _EXT4-BS-BUF @ _EXT4-SB.UUID +
        _EXT4-BS-PRIMARY @ _EXT4-SB.UUID + 16 _EXT4-BYTES=? AND ;

: _EXT4-BACKUP-SUPER-FIELDS?  ( backup ctx -- flag )
    _EXT4-BS-CTX !
    _EXT4-BS-GROUP @
    _EXT4-BS-CTX @ _EXT4-C.SB +
    _EXT4-SUPER-INVARIANTS? ;

: _EXT4-VALIDATE-BACKUP-SUPER  ( group ctx -- ior )
    _EXT4-BS-CTX ! DUP _EXT4-BS-GROUP !
    _EXT4-BS-CTX @ _EXT4-C.BPG + @ *
    _EXT4-BS-CTX @ _EXT4-C.FIRST + @ + DUP _EXT4-BS-BLOCK !
    _EXT4-BS-CTX @ _EXT4-READ-BLOCK ?DUP IF EXIT THEN
    _EXT4-BS-CTX @ _EXT4-C.BLOCK + DUP _EXT4-BS-BUF !
    _EXT4-SUPER-CHECKSUM? ?DUP IF NIP EXIT THEN 0= IF
        EXT4-D-BACKUP-SUPER _EXT4-CORRUPT EXIT
    THEN
    _EXT4-BS-BUF @ _EXT4-SUPER-SEED? ?DUP IF NIP EXIT THEN 0= IF
        EXT4-D-BACKUP-SUPER _EXT4-CORRUPT EXIT
    THEN
    _EXT4-BS-BUF @ _EXT4-BS-CTX @ _EXT4-BACKUP-SUPER-FIELDS? 0= IF
        EXT4-D-BACKUP-SUPER _EXT4-CORRUPT EXIT
    THEN
    _EXT4-BS-BLOCK @ 1+ _EXT4-BS-CTX @ _EXT4-VALIDATE-BACKUP-GDT ;

\ ---------------------------------------------------------------------
\  Standing backup validation
\ ---------------------------------------------------------------------
\
\ A backup validation reads only the backup superblocks and the backup
\ descriptor blocks after them, and compares them with the primary
\ superblock's fixed fields and the primary descriptors' block-bitmap,
\ inode-bitmap and inode-table locations.  Its result depends on nothing
\ else, so it stands while none of those inputs changes.  The write watch
\ counts every write that meets a backup's superblock, its descriptor blocks
\ or their reserved successors, and every write to another volume
\ (_EXT4-BK-NOTE).  The group validation that precedes each backup
\ validation chains the three primary locations of every group into a
\ CRC32C and records it with its context and map epoch.  A validation that
\ passed keeps its context, its volume, the watch's count, that CRC and a
\ copy of the primary superblock it compared with.  A later validation of
\ the same context stands when the watch's count is unchanged, the group
\ validation of the same epoch found the same locations, and the primary
\ superblock's fixed fields equal the copy's.  Anything else validates
\ every copy again.
VARIABLE _EXT4-BK-WRITES
0 _EXT4-BK-WRITES !
VARIABLE _EXT4-BKM-CTX
0 _EXT4-BKM-CTX !
VARIABLE _EXT4-BKM-VOL
VARIABLE _EXT4-BKM-WRITES
VARIABLE _EXT4-BKM-LOCATIONS
CREATE _EXT4-BKM-SPACE _EXT4-SB-SIZE 7 + ALLOT
_EXT4-BKM-SPACE 7 + -8 AND CONSTANT _EXT4-BKM-SUPER
VARIABLE _EXT4-GL-CTX
0 _EXT4-GL-CTX !
VARIABLE _EXT4-GL-EPOCH
VARIABLE _EXT4-GL-CRC
VARIABLE _EXT4-BKN-FIRST
VARIABLE _EXT4-BKN-LAST

\ Count a write of COUNT sectors at LBA that may meet a backup.
: _EXT4-BK-NOTE  ( lba count -- )
    _EXT4-BKM-CTX @ 0= IF 2DROP EXIT THEN
    _EXT4-IO-VOL @ _EXT4-BKM-VOL @ <>
    _EXT4-BKM-CTX @ _EXT4-C.SPB + @ 0= OR
    _EXT4-BKM-CTX @ _EXT4-C.BPG + @ 0= OR IF
        2DROP 1 _EXT4-BK-WRITES +! EXIT
    THEN
    DUP 0= IF 2DROP EXIT THEN
    OVER + 1- _EXT4-BKM-CTX @ _EXT4-C.SPB + @ / _EXT4-BKN-LAST !
    _EXT4-BKM-CTX @ _EXT4-C.SPB + @ / _EXT4-BKN-FIRST !
    _EXT4-BKN-LAST @ _EXT4-BKM-CTX @ _EXT4-C.FIRST + @ U< IF EXIT THEN
    _EXT4-BKN-FIRST @ _EXT4-BKM-CTX @ _EXT4-C.FIRST + @ U< IF
        _EXT4-BKM-CTX @ _EXT4-C.FIRST + @ _EXT4-BKN-FIRST !
    THEN
    _EXT4-BKN-LAST @ _EXT4-BKM-CTX @ _EXT4-C.FIRST + @ -
    _EXT4-BKM-CTX @ _EXT4-C.BPG + @ / 1+
    _EXT4-BKM-CTX @ _EXT4-C.GROUPS + @ MIN
    _EXT4-BKN-FIRST @ _EXT4-BKM-CTX @ _EXT4-C.FIRST + @ -
    _EXT4-BKM-CTX @ _EXT4-C.BPG + @ /
    ?DO
        I IF I _EXT4-SPARSE-GROUP? IF
            I _EXT4-BKM-CTX @ _EXT4-C.BPG + @ *
            _EXT4-BKM-CTX @ _EXT4-C.FIRST + @ +
            _EXT4-BKN-LAST @ U> 0= IF
                I _EXT4-BKM-CTX @ _EXT4-BACKUP-END
                _EXT4-BKN-FIRST @ U> IF
                    1 _EXT4-BK-WRITES +! UNLOOP EXIT
                THEN
            THEN
        THEN THEN
    LOOP ;

\ Begin, extend and record the chain of primary locations the group
\ validation of CTX builds, one group at a time, from each group's
\ descriptor in C.DESC.
VARIABLE _EXT4-GL-RUNNING

: _EXT4-GL-BEGIN  ( -- )
    0 _EXT4-GL-CTX ! 0xFFFFFFFF _EXT4-GL-RUNNING ! ;

: _EXT4-GL-ADD  ( ctx -- ior )
    _EXT4-GL-RUNNING @ _EXT4-CRC-START
    _EXT4-C.DESC + _EXT4-GD.BLOCK-BITMAP-LO + 12 _EXT4-CRC-ADD
    ?DUP IF EXIT THEN
    _EXT4-CRC@ _EXT4-GL-RUNNING ! 0 ;

: _EXT4-GL-RECORD  ( ctx -- )
    _EXT4-GL-CTX ! _EXT4-MAP-EPOCH @ _EXT4-GL-EPOCH !
    _EXT4-GL-RUNNING @ _EXT4-GL-CRC ! ;

: _EXT4-BKM-STANDS?  ( ctx -- flag )
    DUP _EXT4-BKM-CTX @ <> IF DROP FALSE EXIT THEN
    DUP _EXT4-GL-CTX @ <> IF DROP FALSE EXIT THEN
    _EXT4-GL-EPOCH @ _EXT4-MAP-EPOCH @ <>
    _EXT4-GL-CRC @ _EXT4-BKM-LOCATIONS @ <> OR
    _EXT4-BK-WRITES @ _EXT4-BKM-WRITES @ <> OR
    _EXT4-IO-VOL @ _EXT4-BKM-VOL @ <> OR IF DROP FALSE EXIT THEN
    _EXT4-C.SB + 0 _EXT4-BKM-SUPER _EXT4-SUPER-INVARIANTS? ;

\ Drop the kept validation; a mount reads its medium afresh.
: _EXT4-BKM-DROP  ( -- )  0 _EXT4-BKM-CTX ! ;

: _EXT4-BKM-KEEP  ( ctx -- )
    0 _EXT4-BKM-CTX !
    DUP _EXT4-GL-CTX @ <>
    _EXT4-GL-EPOCH @ _EXT4-MAP-EPOCH @ <> OR IF DROP EXIT THEN
    DUP _EXT4-C.SB + _EXT4-BKM-SUPER _EXT4-SB-SIZE MOVE
    _EXT4-GL-CRC @ _EXT4-BKM-LOCATIONS !
    _EXT4-BK-WRITES @ _EXT4-BKM-WRITES !
    _EXT4-IO-VOL @ _EXT4-BKM-VOL !
    _EXT4-BKM-CTX ! ;

VARIABLE _EXT4-VB-CTX
: _EXT4-VALIDATE-BACKUPS  ( ctx -- ior )
    _EXT4-VB-CTX !
    _EXT4-VB-CTX @ _EXT4-BKM-STANDS? IF 0 EXIT THEN
    0 _EXT4-BKM-CTX !
    _EXT4-VB-CTX @ _EXT4-C.GROUPS + @ 1 ?DO
        I _EXT4-SPARSE-GROUP? IF
            I _EXT4-VB-CTX @ _EXT4-VALIDATE-BACKUP-SUPER ?DUP IF
                UNLOOP EXIT
            THEN
        THEN
    LOOP
    _EXT4-VB-CTX @ _EXT4-BKM-KEEP 0 ;
