\ vfs-ext4-dirent.f — checked linear ext4 directory-entry blocks
\
\ Internal dependency of the vfs-ext4.f public facade.

PROVIDED akashic-ext4-dirent
REQUIRE vfs-ext4-admission.f
REQUIRE vfs-ext4-dirhash.f

VARIABLE _EXT4-DV-INO
VARIABLE _EXT4-DV-GEN
VARIABLE _EXT4-DV-CTX
VARIABLE _EXT4-DV-STORED
VARIABLE _EXT4-DV-OFF
VARIABLE _EXT4-DV-LIMIT
VARIABLE _EXT4-DV-DE
VARIABLE _EXT4-DV-REC
VARIABLE _EXT4-DV-NLEN

: _EXT4-DIRENT>TYPE  ( dtype -- type supported? )
    CASE
        0 OF 0 TRUE          ENDOF
        1 OF VFS-T-FILE TRUE ENDOF
        2 OF VFS-T-DIR TRUE  ENDOF
        3 OF VFS-T-SPECIAL TRUE ENDOF
        4 OF VFS-T-SPECIAL TRUE ENDOF
        5 OF VFS-T-SPECIAL TRUE ENDOF
        6 OF VFS-T-SPECIAL TRUE ENDOF
        7 OF VFS-T-SYMLINK TRUE ENDOF
        0 FALSE ROT
    ENDCASE ;

\ Authenticate both the checksum tail and the complete dirent chain.  Callers
\ may then bind a mutation payload to record boundaries instead of treating a
\ checksum-valid byte offset inside name or slack storage as a directory entry.
: _EXT4-VALIDATE-DIR-BLOCK  ( dir-inum generation ctx -- ior )
    _EXT4-DV-CTX ! _EXT4-DV-GEN ! _EXT4-DV-INO !
    _EXT4-DV-CTX @ _EXT4-C.BSIZE + @ 12 - DUP _EXT4-DV-LIMIT !
    DROP _EXT4-DV-CTX @ _EXT4-C.DIR-BLOCK +
    _EXT4-DV-LIMIT @ +
    DUP L@ 0<> OVER 4 + W@ 12 <> OR OVER 6 + C@ 0<> OR
    OVER 7 + C@ 0xDE <> OR IF
        DROP EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
    THEN
    8 + L@ _EXT4-DV-STORED !
    _EXT4-DV-INO @ _EXT4-DV-CTX @ _EXT4-C.TMP + L!
    _EXT4-DV-GEN @ _EXT4-DV-CTX @ _EXT4-C.TMP 4 + + L!
    _EXT4-DV-CTX @ _EXT4-C.SEED + @ _EXT4-CRC-START
    _EXT4-DV-CTX @ _EXT4-C.TMP + 8 _EXT4-CRC-ADD ?DUP IF EXIT THEN
    _EXT4-DV-CTX @ _EXT4-C.DIR-BLOCK + _EXT4-DV-LIMIT @
    _EXT4-CRC-ADD ?DUP IF EXIT THEN
    _EXT4-CRC@ _EXT4-DV-STORED @ <> IF
        EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
    THEN
    0 _EXT4-DV-OFF !
    BEGIN _EXT4-DV-OFF @ _EXT4-DV-LIMIT @ < WHILE
        _EXT4-DV-CTX @ _EXT4-C.DIR-BLOCK + _EXT4-DV-OFF @ +
        DUP _EXT4-DV-DE ! 4 + W@ DUP _EXT4-DV-REC !
        DUP 12 U< SWAP 3 AND 0<> OR IF
            EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
        THEN
        _EXT4-DV-OFF @ _EXT4-DV-REC @ + _EXT4-DV-LIMIT @ U> IF
            EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
        THEN
        _EXT4-DV-DE @ 6 + C@ DUP _EXT4-DV-NLEN !
        _EXT4-DV-REC @ 8 - U> IF
            EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
        THEN
        _EXT4-DV-DE @ L@ IF
            _EXT4-DV-DE @ L@ _EXT4-DV-CTX @ _EXT4-C.INODES + @ U>
            _EXT4-DV-NLEN @ 0= OR IF
                EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
            THEN
            _EXT4-DV-DE @ 8 + _EXT4-DV-NLEN @
            _EXT4-DIRENT-NAME-VALID? 0= IF
                EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
            THEN
            _EXT4-DV-DE @ 7 + C@ _EXT4-DIRENT>TYPE 0= IF
                DROP EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
            THEN DROP
        THEN
        _EXT4-DV-REC @ _EXT4-DV-OFF +!
    REPEAT
    _EXT4-DV-OFF @ _EXT4-DV-LIMIT @ <> IF
        EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
    THEN
    0 ;

VARIABLE _EXT4-RDB-BLOCK
VARIABLE _EXT4-RDB-INO
VARIABLE _EXT4-RDB-GEN
VARIABLE _EXT4-RDB-CTX
VARIABLE _EXT4-RDB-TAIL

: _EXT4-RESTAMP-DIR-BLOCK  ( block dir-inum generation ctx -- ior )
    _EXT4-RDB-CTX ! _EXT4-RDB-GEN ! _EXT4-RDB-INO !
    _EXT4-RDB-BLOCK !
    _EXT4-RDB-BLOCK @ 0= _EXT4-RDB-CTX @ 0= OR IF
        VFS-E-INVALID EXIT
    THEN
    _EXT4-RDB-INO @ 0=
    _EXT4-RDB-INO @ _EXT4-RDB-CTX @ _EXT4-C.INODES + @ U> OR IF
        EXT4-D-BOUNDS _EXT4-CORRUPT EXIT
    THEN
    _EXT4-RDB-BLOCK @ _EXT4-RDB-CTX @ _EXT4-C.BSIZE + @ 12 - +
    DUP _EXT4-RDB-TAIL !
    DUP L@ 0<>
    OVER 4 + W@ 12 <> OR
    OVER 6 + C@ 0<> OR
    OVER 7 + C@ 0xDE <> OR IF
        DROP EXT4-D-DIRECTORY _EXT4-CORRUPT EXIT
    THEN
    DROP
    0 _EXT4-RDB-TAIL @ 8 + L!
    _EXT4-RDB-INO @ _EXT4-RDB-CTX @ _EXT4-C.TMP + L!
    _EXT4-RDB-GEN @ _EXT4-RDB-CTX @ _EXT4-C.TMP 4 + + L!
    _EXT4-RDB-CTX @ _EXT4-C.SEED + @ _EXT4-CRC-START
    _EXT4-RDB-CTX @ _EXT4-C.TMP + 8 _EXT4-CRC-ADD ?DUP IF EXIT THEN
    _EXT4-RDB-BLOCK @ _EXT4-RDB-CTX @ _EXT4-C.BSIZE + @ 12 -
    _EXT4-CRC-ADD ?DUP IF EXIT THEN
    _EXT4-CRC@ _EXT4-RDB-TAIL @ 8 + L!
    0 ;
