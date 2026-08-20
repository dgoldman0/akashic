\ vfs-ext4-xattr.f — external ext4 xattr-block format services
\
\ Internal dependency of the vfs-ext4.f public facade.

PROVIDED akashic-ext4-xattr
REQUIRE vfs-ext4-admission.f

0xEA020000 CONSTANT _EXT4-XATTR-MAGIC
1024 CONSTANT _EXT4-XATTR-REFCOUNT-MAX

VARIABLE _EXT4-XC-CTX
VARIABLE _EXT4-XC-BLOCK
VARIABLE _EXT4-XC-BUF

: _EXT4-XATTR-BLOCK-CRC  ( buffer physical-block ctx -- crc ior )
    _EXT4-XC-CTX ! _EXT4-XC-BLOCK ! _EXT4-XC-BUF !
    _EXT4-XC-BLOCK @ _EXT4-XC-CTX @ _EXT4-C.TMP + L!
    0 _EXT4-XC-CTX @ _EXT4-C.TMP 4 + + L!
    _EXT4-XC-CTX @ _EXT4-C.SEED + @ _EXT4-CRC-START
    _EXT4-XC-CTX @ _EXT4-C.TMP + 8 _EXT4-CRC-ADD
    ?DUP IF 0 SWAP EXIT THEN
    _EXT4-XC-BUF @ _EXT4-XC-CTX @ _EXT4-C.BSIZE + @ _EXT4-CRC-ADD
    ?DUP IF 0 SWAP EXIT THEN
    _EXT4-CRC@ 0 ;

\ Restamp one already authenticated external-xattr block after changing only
\ checksum-covered header state.  ext4's metadata checksum covers the 64-bit
\ physical block number followed by the complete block with h_checksum zero.
: _EXT4-STAMP-XATTR-BLOCK  ( buffer physical-block ctx -- ior )
    _EXT4-XC-CTX ! _EXT4-XC-BLOCK ! _EXT4-XC-BUF !
    0 _EXT4-XC-BUF @ 0x10 + L!
    _EXT4-XC-BUF @ _EXT4-XC-BLOCK @ _EXT4-XC-CTX @
    _EXT4-XATTR-BLOCK-CRC ?DUP IF NIP EXIT THEN
    _EXT4-XC-BUF @ 0x10 + L! 0 ;

VARIABLE _EXT4-XB-CTX
VARIABLE _EXT4-XB-BLOCK
VARIABLE _EXT4-XB-STORED

: _EXT4-LOAD-XATTR-BLOCK  ( physical-block ctx -- ior )
    _EXT4-XB-CTX ! DUP _EXT4-XB-BLOCK !
    _EXT4-XB-CTX @ _EXT4-READ-BLOCK ?DUP IF EXIT THEN
    _EXT4-XB-CTX @ _EXT4-C.BLOCK + DUP L@ _EXT4-XATTR-MAGIC <>
    OVER 4 + L@ 0= OR
    OVER 8 + L@ 1 <> OR
    OVER 0x14 + L@ 0<> OR
    OVER 0x18 + L@ 0<> OR
    OVER 0x1C + L@ 0<> OR IF
        DROP EXT4-D-XATTR _EXT4-CORRUPT EXIT
    THEN
    DUP 0x10 + L@ _EXT4-XB-STORED !
    0 SWAP 0x10 + L!
    _EXT4-XB-CTX @ _EXT4-C.BLOCK +
    _EXT4-XB-BLOCK @ _EXT4-XB-CTX @ _EXT4-XATTR-BLOCK-CRC
    ?DUP IF
        NIP _EXT4-XB-STORED @
        _EXT4-XB-CTX @ _EXT4-C.BLOCK + 0x10 + L! EXIT
    THEN
    _EXT4-XB-STORED @
    _EXT4-XB-CTX @ _EXT4-C.BLOCK + 0x10 + L!
    _EXT4-XB-STORED @ <> IF
        EXT4-D-XATTR _EXT4-CORRUPT EXIT
    THEN
    0 ;
