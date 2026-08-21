\ vfs-ext4-inode.f — ext4 inode-record format services
\
\ Internal dependency of the vfs-ext4.f public facade.

PROVIDED akashic-ext4-inode
REQUIRE vfs-ext4-admission.f

\ =====================================================================
\  Scalar i_blocks decoding
\ =====================================================================

VARIABLE _EXT4-IB-IN
VARIABLE _EXT4-IB-CTX

: _EXT4-DECODE-I-BLOCKS  ( inode ctx -- blocks-512 ior )
    _EXT4-IB-CTX ! _EXT4-IB-IN !
    _EXT4-IB-IN @ _EXT4-I.BLOCKS-HI + W@ 32 LSHIFT
    _EXT4-IB-IN @ _EXT4-I.BLOCKS-LO + L@ OR
    _EXT4-IB-IN @ _EXT4-I.FLAGS + L@ _EXT4-HUGE-FILE-FL AND IF
        _EXT4-IB-CTX @ _EXT4-C.SPB + @ *
    THEN
    DUP _EXT4-IB-CTX @ _EXT4-C.BLOCKS + @
        _EXT4-IB-CTX @ _EXT4-C.SPB + @ * U> IF
        DROP 0 EXT4-D-BOUNDS _EXT4-CORRUPT EXIT
    THEN
    0 ;

: _EXT4-S32@  ( addr -- n )
    L@ DUP 0x80000000 AND IF 0xFFFFFFFF00000000 OR THEN ;

\ =====================================================================
\  Special-inode i_block decoding
\ =====================================================================

VARIABLE _EXT4-SD-CTX
VARIABLE _EXT4-SD-IN
VARIABLE _EXT4-SD-MODE
VARIABLE _EXT4-SD-RAW
VARIABLE _EXT4-SD-MAJOR
VARIABLE _EXT4-SD-MINOR
VARIABLE _EXT4-SD-INDEX

: _EXT4-I-BLOCK-ZERO-FROM?  ( first-word ctx -- flag )
    _EXT4-SD-CTX ! _EXT4-SD-INDEX !
    BEGIN _EXT4-SD-INDEX @ _EXT4-N-BLOCK-PTRS < WHILE
        _EXT4-SD-CTX @ _EXT4-C.INODE + _EXT4-I.BLOCK +
        _EXT4-SD-INDEX @ 4 * + L@ IF FALSE EXIT THEN
        1 _EXT4-SD-INDEX +!
    REPEAT TRUE ;

\ Device inodes use ext4's old encoding in i_block[0] or its new encoding
\ in i_block[1].  Publish a binding-neutral 64-bit major/minor pair while
\ retaining stable unsupported behavior for OPEN on the resulting vnode.
: _EXT4-DECODE-SPECIAL  ( ctx -- rdev ior )
    DUP _EXT4-SD-CTX ! _EXT4-C.INODE + DUP _EXT4-SD-IN !
    _EXT4-I.MODE + W@ 0xF000 AND _EXT4-SD-MODE !
    _EXT4-SD-CTX @ _EXT4-C.R.SIZE + @
    _EXT4-SD-CTX @ _EXT4-C.R.BLOCKS + @ OR IF
        0 EXT4-D-DATA-MAP _EXT4-CORRUPT EXIT
    THEN
    _EXT4-SD-MODE @ 0x2000 = _EXT4-SD-MODE @ 0x6000 = OR IF
        _EXT4-SD-IN @ _EXT4-I.BLOCK + L@ DUP _EXT4-SD-RAW ! IF
            _EXT4-SD-RAW @ 0xFFFF U> IF
                0 EXT4-D-DATA-MAP _EXT4-CORRUPT EXIT
            THEN
            1 _EXT4-SD-CTX @ _EXT4-I-BLOCK-ZERO-FROM? 0= IF
                0 EXT4-D-DATA-MAP _EXT4-CORRUPT EXIT
            THEN
            _EXT4-SD-RAW @ 8 RSHIFT 0xFF AND _EXT4-SD-MAJOR !
            _EXT4-SD-RAW @ 0xFF AND _EXT4-SD-MINOR !
        ELSE
            _EXT4-SD-IN @ _EXT4-I.BLOCK + 4 + L@ _EXT4-SD-RAW !
            2 _EXT4-SD-CTX @ _EXT4-I-BLOCK-ZERO-FROM? 0= IF
                0 EXT4-D-DATA-MAP _EXT4-CORRUPT EXIT
            THEN
            _EXT4-SD-RAW @ 0xFFF00 AND 8 RSHIFT _EXT4-SD-MAJOR !
            _EXT4-SD-RAW @ 0xFF AND
            _EXT4-SD-RAW @ 12 RSHIFT 0xFFF00 AND OR _EXT4-SD-MINOR !
            _EXT4-SD-MINOR @ 0xFF AND
            _EXT4-SD-MAJOR @ 8 LSHIFT OR
            _EXT4-SD-MINOR @ 0xFF INVERT AND 12 LSHIFT OR
            _EXT4-SD-RAW @ <> IF
                0 EXT4-D-DATA-MAP _EXT4-CORRUPT EXIT
            THEN
        THEN
        _EXT4-SD-MAJOR @ _EXT4-SD-MINOR @ VFS-RDEV-MAKE 0 EXIT
    THEN
    0 _EXT4-SD-CTX @ _EXT4-I-BLOCK-ZERO-FROM? 0= IF
        0 EXT4-D-DATA-MAP _EXT4-CORRUPT EXIT
    THEN
    0 0 ;

\ =====================================================================
\  Inode checksum and timestamp encoding
\ =====================================================================

VARIABLE _EXT4-RI-INODE
VARIABLE _EXT4-RI-INO
VARIABLE _EXT4-RI-CTX
VARIABLE _EXT4-RI-EXTRA
VARIABLE _EXT4-RI-HAS-HI
VARIABLE _EXT4-RI-CALC

: _EXT4-RESTAMP-INODE  ( inode inode-number ctx -- ior )
    _EXT4-RI-CTX ! _EXT4-RI-INO ! _EXT4-RI-INODE !
    _EXT4-RI-INODE @ 0= _EXT4-RI-CTX @ 0= OR IF
        VFS-E-INVALID EXIT
    THEN
    _EXT4-RI-INO @ 0=
    _EXT4-RI-INO @ _EXT4-RI-CTX @ _EXT4-C.INODES + @ U> OR IF
        EXT4-D-BOUNDS _EXT4-CORRUPT EXIT
    THEN
    _EXT4-RI-CTX @ _EXT4-C.ISIZE + @ 128 U< IF
        EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT
    THEN
    0 _EXT4-RI-HAS-HI !
    _EXT4-RI-CTX @ _EXT4-C.ISIZE + @ 128 > IF
        _EXT4-RI-INODE @ _EXT4-I.EXTRA-SIZE + W@
        DUP _EXT4-RI-EXTRA ! 4 U< IF
            EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT
        THEN
        _EXT4-RI-EXTRA @ 4 MOD IF
            EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT
        THEN
        _EXT4-RI-EXTRA @ 128 +
        _EXT4-RI-CTX @ _EXT4-C.ISIZE + @ U> IF
            EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT
        THEN
        -1 _EXT4-RI-HAS-HI !
    THEN
    0 _EXT4-RI-INODE @ _EXT4-I.CSUM-LO + W!
    _EXT4-RI-HAS-HI @ IF
        0 _EXT4-RI-INODE @ _EXT4-I.CSUM-HI + W!
    THEN
    _EXT4-RI-INO @ _EXT4-RI-CTX @ _EXT4-C.TMP + L!
    _EXT4-RI-CTX @ _EXT4-C.SEED + @ _EXT4-CRC-START
    _EXT4-RI-CTX @ _EXT4-C.TMP + 4 _EXT4-CRC-ADD ?DUP IF EXIT THEN
    _EXT4-RI-INODE @ _EXT4-I.GENERATION + 4 _EXT4-CRC-ADD
    ?DUP IF EXIT THEN
    _EXT4-RI-INODE @ _EXT4-RI-CTX @ _EXT4-C.ISIZE + @ _EXT4-CRC-ADD
    ?DUP IF EXIT THEN
    _EXT4-CRC@ DUP _EXT4-RI-CALC !
    _EXT4-RI-INODE @ _EXT4-I.CSUM-LO + W!
    _EXT4-RI-HAS-HI @ IF
        _EXT4-RI-CALC @ 16 RSHIFT
        _EXT4-RI-INODE @ _EXT4-I.CSUM-HI + W!
    THEN
    0 ;

VARIABLE _EXT4-ITM-SECONDS
VARIABLE _EXT4-ITM-NSEC
VARIABLE _EXT4-ITM-INODE
VARIABLE _EXT4-ITM-CTX
VARIABLE _EXT4-ITM-LOW
VARIABLE _EXT4-ITM-SIGNED
VARIABLE _EXT4-ITM-EPOCH
VARIABLE _EXT4-ITM-EXTRA

\ Encode one explicit timestamp into both mtime and ctime without consulting
\ an ambiguous ambient clock.  Ext4 decodes the low word as signed and then
\ adds the extra field's two epoch bits, so derive those bits from the
\ sign-extended low word rather than from a logical seconds shift.
: _EXT4-SET-INODE-MTIME-CTIME  ( seconds nsec inode ctx -- ior )
    _EXT4-ITM-CTX ! _EXT4-ITM-INODE !
    _EXT4-ITM-NSEC ! _EXT4-ITM-SECONDS !
    _EXT4-ITM-CTX @ 0= _EXT4-ITM-INODE @ 0= OR IF
        VFS-E-INVALID EXIT
    THEN
    _EXT4-ITM-NSEC @ 0<
    _EXT4-ITM-NSEC @ 1000000000 U< 0= OR IF
        VFS-E-INVALID EXIT
    THEN
    _EXT4-ITM-CTX @ _EXT4-C.ISIZE + @ DUP 128 =
    SWAP 256 = OR 0= IF
        EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT
    THEN
    _EXT4-ITM-SECONDS @ -2147483648 <
    _EXT4-ITM-SECONDS @ 15032385535 > OR IF
        VFS-E-OVERFLOW EXIT
    THEN
    _EXT4-ITM-SECONDS @ 0xFFFFFFFF AND DUP _EXT4-ITM-LOW !
    DUP 0x80000000 AND IF 0xFFFFFFFF00000000 OR THEN
    _EXT4-ITM-SIGNED !
    _EXT4-ITM-SECONDS @ _EXT4-ITM-SIGNED @ - 32 RSHIFT
    DUP _EXT4-ITM-EPOCH ! 3 U> IF VFS-E-OVERFLOW EXIT THEN
    _EXT4-ITM-CTX @ _EXT4-C.ISIZE + @ 128 = IF
        _EXT4-ITM-NSEC @ _EXT4-ITM-EPOCH @ OR IF
            VFS-E-OVERFLOW EXIT
        THEN
        0 _EXT4-ITM-EXTRA !
    ELSE
        \ This first writable slice follows live-inode staging's modern
        \ profile: all three extra timestamps and the high checksum exist.
        \ Old-format 256-byte records with extra_isize zero remain readable
        \ but are not silently upgraded by a writable mutation.
        _EXT4-ITM-INODE @ _EXT4-I.EXTRA-SIZE + W@
        DUP 16 U< IF DROP EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT THEN
        DUP 4 MOD IF DROP EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT THEN
        128 + _EXT4-ITM-CTX @ _EXT4-C.ISIZE + @ U> IF
            EXT4-D-INODE-CHECKSUM _EXT4-CORRUPT EXIT
        THEN
        _EXT4-ITM-NSEC @ 2 LSHIFT _EXT4-ITM-EPOCH @ OR
        _EXT4-ITM-EXTRA !
    THEN
    _EXT4-ITM-LOW @ _EXT4-ITM-INODE @ _EXT4-I.CTIME + L!
    _EXT4-ITM-LOW @ _EXT4-ITM-INODE @ _EXT4-I.MTIME + L!
    _EXT4-ITM-CTX @ _EXT4-C.ISIZE + @ 128 > IF
        _EXT4-ITM-EXTRA @
        _EXT4-ITM-INODE @ _EXT4-I.CTIME-EXTRA + L!
        _EXT4-ITM-EXTRA @
        _EXT4-ITM-INODE @ _EXT4-I.MTIME-EXTRA + L!
    THEN
    0 ;

VARIABLE _EXT4-ICT-SECONDS
VARIABLE _EXT4-ICT-NSEC
VARIABLE _EXT4-ICT-INODE
VARIABLE _EXT4-ICT-CTX
VARIABLE _EXT4-ICT-MTIME-LOW
VARIABLE _EXT4-ICT-MTIME-EXTRA

: _EXT4-SET-INODE-CTIME  ( seconds nsec inode ctx -- ior )
    _EXT4-ICT-CTX ! _EXT4-ICT-INODE !
    _EXT4-ICT-NSEC ! _EXT4-ICT-SECONDS !
    _EXT4-ICT-CTX @ 0= _EXT4-ICT-INODE @ 0= OR IF
        VFS-E-INVALID EXIT
    THEN
    _EXT4-ICT-INODE @ _EXT4-I.MTIME + L@ _EXT4-ICT-MTIME-LOW !
    _EXT4-ICT-CTX @ _EXT4-C.ISIZE + @ 128 > IF
        _EXT4-ICT-INODE @ _EXT4-I.MTIME-EXTRA + L@
        _EXT4-ICT-MTIME-EXTRA !
    ELSE
        0 _EXT4-ICT-MTIME-EXTRA !
    THEN
    _EXT4-ICT-SECONDS @ _EXT4-ICT-NSEC @
    _EXT4-ICT-INODE @ _EXT4-ICT-CTX @
    _EXT4-SET-INODE-MTIME-CTIME ?DUP IF EXIT THEN
    _EXT4-ICT-MTIME-LOW @ _EXT4-ICT-INODE @ _EXT4-I.MTIME + L!
    _EXT4-ICT-CTX @ _EXT4-C.ISIZE + @ 128 > IF
        _EXT4-ICT-MTIME-EXTRA @
        _EXT4-ICT-INODE @ _EXT4-I.MTIME-EXTRA + L!
    THEN
    0 ;

VARIABLE _EXT4-EIB-SECTORS
VARIABLE _EXT4-EIB-INODE
VARIABLE _EXT4-EIB-CTX
VARIABLE _EXT4-EIB-RAW
VARIABLE _EXT4-EIB-LIMIT

\ Encode the on-disk 48-bit i_blocks field without silently changing the
\ HUGE_FILE unit convention.  Callers supply the normalized 512-byte-sector
\ count used by the rest of this driver.
: _EXT4-ENCODE-I-BLOCKS  ( blocks-512 inode ctx -- ior )
    _EXT4-EIB-CTX ! _EXT4-EIB-INODE ! _EXT4-EIB-SECTORS !
    _EXT4-EIB-CTX @ 0= _EXT4-EIB-INODE @ 0= OR IF
        VFS-E-INVALID EXIT
    THEN
    _EXT4-EIB-SECTORS @ 0< IF VFS-E-INVALID EXIT THEN
    _EXT4-EIB-CTX @ _EXT4-C.SPB + @ 0= IF VFS-E-INVALID EXIT THEN
    _EXT4-EIB-CTX @ _EXT4-C.BLOCKS + @
    _EXT4-EIB-CTX @ _EXT4-C.SPB + @ _EXT4-UMUL?
    DUP IF NIP EXIT THEN DROP _EXT4-EIB-LIMIT !
    _EXT4-EIB-SECTORS @ _EXT4-EIB-LIMIT @ U> IF
        EXT4-D-BOUNDS _EXT4-CORRUPT EXIT
    THEN
    _EXT4-EIB-SECTORS @
    _EXT4-EIB-INODE @ _EXT4-I.FLAGS + L@
    _EXT4-HUGE-FILE-FL AND IF
        _EXT4-EIB-CTX @ _EXT4-C.SPB + @ /MOD
        SWAP IF DROP EXT4-D-DATA-MAP _EXT4-CORRUPT EXIT THEN
    THEN
    DUP _EXT4-EIB-RAW ! 0xFFFFFFFFFFFF U> IF
        EXT4-D-BOUNDS _EXT4-CORRUPT EXIT
    THEN
    _EXT4-EIB-RAW @ DUP 0xFFFFFFFF AND
    _EXT4-EIB-INODE @ _EXT4-I.BLOCKS-LO + L!
    32 RSHIFT _EXT4-EIB-INODE @ _EXT4-I.BLOCKS-HI + W!
    0 ;
