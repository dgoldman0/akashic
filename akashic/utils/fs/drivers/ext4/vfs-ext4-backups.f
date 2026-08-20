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

VARIABLE _EXT4-VB-CTX
: _EXT4-VALIDATE-BACKUPS  ( ctx -- ior )
    _EXT4-VB-CTX !
    _EXT4-VB-CTX @ _EXT4-C.GROUPS + @ 1 ?DO
        I _EXT4-SPARSE-GROUP? IF
            I _EXT4-VB-CTX @ _EXT4-VALIDATE-BACKUP-SUPER ?DUP IF
                UNLOOP EXIT
            THEN
        THEN
    LOOP 0 ;
