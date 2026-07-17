\ =====================================================================
\  Deterministic contracts for the pure Library storage formats
\ =====================================================================
\  The suites below exercise only caller-buffer formats and ordered-chain
\  rules.  VFS allocation, publication, and crash ordering belong to the
\  separate Library VFS-store contract leaf.
\ =====================================================================

VARIABLE _lsfc-fails
VARIABLE _lsfc-checks
VARIABLE _lsfc-depth
VARIABLE _lsfc-byte

CREATE _lsfc-arena-fact LIB-ARENA-FACT-SIZE ALLOT
CREATE _lsfc-bank-fact LIB-BANK-FACT-SIZE ALLOT
CREATE _lsfc-head-fact LIB-HEAD-FACT-SIZE ALLOT
CREATE _lsfc-arena-header LIB-ARENA-HEADER-SIZE ALLOT
CREATE _lsfc-bank-header LIB-BANK-HEADER-SIZE ALLOT
CREATE _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE ALLOT
CREATE _lsfc-chain-a LIB-DIGEST-SIZE ALLOT
CREATE _lsfc-chain-b LIB-DIGEST-SIZE ALLOT
CREATE _lsfc-frame-digest LIB-DIGEST-SIZE ALLOT
CREATE _lsfc-arena-out LIB-ARENA-FACT-SIZE ALLOT
CREATE _lsfc-bank-out LIB-BANK-FACT-SIZE ALLOT
CREATE _lsfc-head-out LIB-HEAD-FACT-SIZE ALLOT
CREATE _lsfc-frame LIB-STORE-SECTOR-SIZE ALLOT

CREATE _lsfc-genesis-golden
0xd7 C, 0x23 C, 0x1a C, 0x88 C, 0xf0 C, 0x34 C, 0xa5 C, 0x17 C,
0x4d C, 0x15 C, 0x56 C, 0x26 C, 0x91 C, 0x07 C, 0x19 C, 0x47 C,
0xa9 C, 0x72 C, 0xbf C, 0x96 C, 0x97 C, 0x7f C, 0xb9 C, 0xd7 C,
0x38 C, 0x90 C, 0x29 C, 0xad C, 0xaa C, 0xac C, 0x62 C, 0xb5 C,

CREATE _lsfc-frame-digest-golden
0x99 C, 0xf9 C, 0x3f C, 0x61 C, 0xa9 C, 0x90 C, 0x03 C, 0xac C,
0x7b C, 0x30 C, 0x98 C, 0x49 C, 0x52 C, 0x7d C, 0x0d C, 0x3d C,
0x9a C, 0xbe C, 0x46 C, 0xc8 C, 0x95 C, 0x98 C, 0x6f C, 0xab C,
0x7f C, 0xb1 C, 0x6b C, 0x2a C, 0x93 C, 0x0a C, 0x01 C, 0xc9 C,

CREATE _lsfc-step-golden
0x07 C, 0x5a C, 0x70 C, 0x6a C, 0xe8 C, 0x96 C, 0x5b C, 0x31 C,
0x01 C, 0x14 C, 0x6e C, 0x05 C, 0x9d C, 0xf7 C, 0x03 C, 0x38 C,
0xb7 C, 0x20 C, 0x44 C, 0x73 C, 0xde C, 0x8d C, 0x39 C, 0x31 C,
0xfe C, 0x84 C, 0x1b C, 0x39 C, 0x47 C, 0x55 C, 0xda C, 0x30 C,

\ CRC32 fields are canonical unsigned 64-bit little-endian values.  Compare
\ wire bytes directly so the fixture seals representation as well as value.
CREATE _lsfc-arena-crc-golden
0xb0 C, 0xf6 C, 0xb8 C, 0xf9 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,

CREATE _lsfc-bank-crc-golden
0xba C, 0xd1 C, 0xa1 C, 0xb7 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,

CREATE _lsfc-head-crc-golden
0xbc C, 0x1e C, 0x8c C, 0xfd C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,

: _lsfc-assert  ( flag -- )
    1 _lsfc-checks +!
    0= IF
        1 _lsfc-fails +!
        ." LIBRARY STORE FORMAT ASSERT " _lsfc-checks @ . CR
    THEN ;

: _lsfc-stack  ( -- )
    DEPTH DUP _lsfc-depth @ <> IF
        ." LIBRARY STORE FORMAT STACK " _lsfc-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _lsfc-depth @ = _lsfc-assert ;

: _lsfc-filled?  ( address length byte -- flag )
    _lsfc-byte !
    0 ?DO
        DUP I + C@ _lsfc-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _lsfc-zero?  ( address length -- flag )
    0 _lsfc-filled? ;

: _lsfc-byte-inc  ( address -- ) DUP C@ 1+ SWAP C! ;

: _lsfc-fill-sequence  ( address length first-byte -- )
    _lsfc-byte !
    0 ?DO _lsfc-byte @ I + 255 AND OVER I + C! LOOP
    DROP ;

: _lsfc-bytes=  ( a u b u -- flag ) COMPARE 0= ;

: _lsfc-build-facts  ( -- )
    _lsfc-arena-fact LIB-ARENA-FACT-INIT
    _lsfc-bank-fact LIB-BANK-FACT-INIT
    _lsfc-head-fact LIB-HEAD-FACT-INIT
    _lsfc-arena-fact LIBAF.ARENA-ID LIB-DIGEST-SIZE 1
        _lsfc-fill-sequence
    _lsfc-chain-a LIB-CONTENT-CHAIN-GENESIS LIB-S-OK = _lsfc-assert

    7 _lsfc-bank-fact LIBBF.GENERATION !
    _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-bank-fact LIBBF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    LIB-ARENA-HEADER-SIZE _lsfc-bank-fact LIBBF.CONTENT-TAIL !
    _lsfc-chain-a _lsfc-bank-fact LIBBF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE
    0x12345678 _lsfc-bank-fact LIBBF.BODY-CRC !
    _lsfc-bank-fact LIBBF.BODY-SHA LIB-DIGEST-SIZE 65
        _lsfc-fill-sequence

    7 _lsfc-head-fact LIBHF.GENERATION !
    1 _lsfc-head-fact LIBHF.BANK-SELECTOR !
    7 _lsfc-head-fact LIBHF.BANK-GENERATION !
    _lsfc-head-fact LIBHF.BANK-SHA LIB-DIGEST-SIZE 97
        _lsfc-fill-sequence
    _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-head-fact LIBHF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    LIB-ARENA-HEADER-SIZE _lsfc-head-fact LIBHF.CONTENT-TAIL !
    _lsfc-chain-a _lsfc-head-fact LIBHF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE ;

: _lsfc-encode-arena  ( -- )
    _lsfc-arena-fact _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        LIB-ARENA-HEADER-ENCODE
    LIB-S-OK = _lsfc-assert
    LIB-ARENA-HEADER-SIZE = _lsfc-assert ;

: _lsfc-encode-bank  ( -- )
    _lsfc-bank-fact _lsfc-bank-header LIB-BANK-HEADER-SIZE
        LIB-BANK-HEADER-ENCODE
    LIB-S-OK = _lsfc-assert
    LIB-BANK-HEADER-SIZE = _lsfc-assert ;

: _lsfc-encode-head  ( -- )
    _lsfc-head-fact _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7
        LIB-HEAD-PAYLOAD-ENCODE
    LIB-S-OK = _lsfc-assert
    LIB-HEAD-PAYLOAD-SIZE = _lsfc-assert ;

: _lsfc-geometry-contracts  ( -- )
    LIB-STORE-SECTOR-SIZE 512 = _lsfc-assert
    LIB-BANK-HEADER-SIZE 512 = _lsfc-assert
    LIB-BANK-BODY-SIZE 403456 = _lsfc-assert
    LIB-BANK-SIZE 403968 = _lsfc-assert
    LIB-BANK-SIZE LIB-STORE-SECTOR-SIZE / 789 = _lsfc-assert
    LIB-BANK-CATALOG-OFFSET 512 = _lsfc-assert
    LIB-BANK-CATALOG-BYTES 393216 = _lsfc-assert
    LIB-BANK-COLLECTION-OFFSET 393728 = _lsfc-assert
    LIB-BANK-COLLECTION-BYTES 10240 = _lsfc-assert
    LIB-ARENA-HEADER-SIZE 512 = _lsfc-assert
    LIB-ARENA-SIZE 655360 = _lsfc-assert
    LIB-ARENA-SIZE LIB-STORE-SECTOR-SIZE / 1280 = _lsfc-assert
    LIB-ARENA-DATA-SIZE 654848 = _lsfc-assert
    LIB-CONTENT-RECORD-MAX 65696 = _lsfc-assert
    LIB-CONTENT-FRAME-MAX 66048 = _lsfc-assert
    LIB-HEAD-PAYLOAD-SIZE 448 = _lsfc-assert
    LIB-CONTENT-HEADER-SIZE LIB-CONTENT-FRAME-SIZE 512 = _lsfc-assert
    LIB-CONTENT-RECORD-MAX LIB-CONTENT-FRAME-SIZE
        LIB-CONTENT-FRAME-MAX = _lsfc-assert
    LIB-CONTENT-HEADER-SIZE 1- LIB-CONTENT-FRAME-SIZE -1 = _lsfc-assert
    LIB-CONTENT-RECORD-MAX 1+ LIB-CONTENT-FRAME-SIZE -1 = _lsfc-assert
    161 LIB-CONTENT-FRAME-SIZE -1 = _lsfc-assert
    _lsfc-stack ;

: _lsfc-fact-contracts  ( -- )
    _lsfc-build-facts
    _lsfc-arena-fact LIB-ARENA-FACT-VALID? _lsfc-assert
    _lsfc-bank-fact LIB-BANK-FACT-VALID? _lsfc-assert
    _lsfc-head-fact LIB-HEAD-FACT-VALID? _lsfc-assert
    _LIBSF-DIGEST LIB-ARENA-FACT-VALID? 0= _lsfc-assert
    _LIBSF-DIGEST LIB-CONTENT-CHAIN-GENESIS
        LIB-S-INVALID = _lsfc-assert
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? _lsfc-assert
    _lsfc-head-fact _lsfc-arena-fact LIB-HEAD-ARENA-MATCH? _lsfc-assert

    513 _lsfc-bank-fact LIBBF.CONTENT-TAIL !
    _lsfc-bank-fact LIB-BANK-FACT-VALID? 0= _lsfc-assert
    _lsfc-build-facts
    1 _lsfc-bank-fact LIBBF.CONTENT-RECORD-COUNT !
    _lsfc-bank-fact LIB-BANK-FACT-VALID? 0= _lsfc-assert
    _lsfc-build-facts
    0 _lsfc-bank-fact LIBBF.CONTENT-CHAIN C!
    _lsfc-bank-fact LIB-BANK-FACT-VALID? 0= _lsfc-assert
    _lsfc-build-facts
    0x100000000 _lsfc-bank-fact LIBBF.BODY-CRC !
    _lsfc-bank-fact LIB-BANK-FACT-VALID? 0= _lsfc-assert

    _lsfc-build-facts
    8 _lsfc-head-fact LIBHF.BANK-GENERATION !
    _lsfc-head-fact LIB-HEAD-FACT-VALID? 0= _lsfc-assert
    _lsfc-build-facts
    2 _lsfc-head-fact LIBHF.BANK-SELECTOR !
    _lsfc-head-fact LIB-HEAD-FACT-VALID? 0= _lsfc-assert
    _lsfc-build-facts
    1 _lsfc-bank-fact LIBBF.GENERATION !
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    1 _lsfc-bank-fact LIBBF.CATALOG-COUNT !
    1 _lsfc-bank-fact LIBBF.MUTATION-SEQUENCE !
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    1 _lsfc-bank-fact LIBBF.COLLECTION-COUNT !
    1 _lsfc-bank-fact LIBBF.MUTATION-SEQUENCE !
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    1 _lsfc-head-fact LIBHF.CATALOG-COUNT !
    1 _lsfc-head-fact LIBHF.MUTATION-SEQUENCE !
    1 _lsfc-bank-fact LIBBF.CATALOG-COUNT !
    2 _lsfc-bank-fact LIBBF.MUTATION-SEQUENCE !
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    1024 _lsfc-head-fact LIBHF.CONTENT-TAIL !
    1 _lsfc-head-fact LIBHF.CONTENT-RECORD-COUNT !
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    1536 _lsfc-head-fact LIBHF.CONTENT-TAIL !
    1 _lsfc-head-fact LIBHF.CONTENT-RECORD-COUNT !
    1536 _lsfc-bank-fact LIBBF.CONTENT-TAIL !
    2 _lsfc-bank-fact LIBBF.CONTENT-RECORD-COUNT !
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    1024 _lsfc-head-fact LIBHF.CONTENT-TAIL !
    1 _lsfc-head-fact LIBHF.CONTENT-RECORD-COUNT !
    1024 _lsfc-bank-fact LIBBF.CONTENT-TAIL !
    1 _lsfc-bank-fact LIBBF.CONTENT-RECORD-COUNT !
    _lsfc-bank-fact LIBBF.CONTENT-CHAIN _lsfc-byte-inc
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    _lsfc-bank-fact LIBBF.ARENA-ID _lsfc-byte-inc
    _lsfc-head-fact _lsfc-bank-fact LIB-HEAD-BANK-MATCH? 0= _lsfc-assert
    _lsfc-build-facts
    _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-byte-inc
    _lsfc-head-fact _lsfc-arena-fact LIB-HEAD-ARENA-MATCH? 0= _lsfc-assert
    _lsfc-stack ;

: _lsfc-arena-codec-contracts  ( -- )
    _lsfc-build-facts
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE 0xa5 FILL
    _lsfc-arena-fact _lsfc-arena-header LIB-ARENA-HEADER-SIZE 1-
        LIB-ARENA-HEADER-ENCODE
    LIB-S-CAPACITY = _lsfc-assert
    0= _lsfc-assert
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE 0xa5
        _lsfc-filled? _lsfc-assert
    _lsfc-encode-arena
    _lsfc-arena-header _LIBSA-HEADER-CRC + 8
        _lsfc-arena-crc-golden 8 _lsfc-bytes= _lsfc-assert
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID LIB-ARENA-HEADER-VALIDATE
        LIB-S-OK = _lsfc-assert
    _lsfc-arena-out LIB-ARENA-FACT-SIZE 0xa5 FILL
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-arena-out
        LIB-ARENA-HEADER-DECODE LIB-S-OK = _lsfc-assert
    _lsfc-arena-fact LIB-ARENA-FACT-SIZE
        _lsfc-arena-out LIB-ARENA-FACT-SIZE _lsfc-bytes= _lsfc-assert

    _lsfc-frame-digest LIB-DIGEST-SIZE 200 _lsfc-fill-sequence
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE _lsfc-frame-digest
        LIB-ARENA-HEADER-VALIDATE LIB-S-INTEGRITY = _lsfc-assert
    _lsfc-arena-header _LIBSA-ARENA-U + _lsfc-byte-inc
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID LIB-ARENA-HEADER-VALIDATE
        LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-arena-out LIB-ARENA-FACT-SIZE 0xa5 FILL
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-arena-out
        LIB-ARENA-HEADER-DECODE LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-arena-out LIB-ARENA-FACT-SIZE 0xa5 _lsfc-filled? _lsfc-assert

    _lsfc-encode-arena
    2 _lsfc-arena-header _LIBSA-FORMAT + !
    _lsfc-arena-header _LIBSF-ARENA-CRC
        _lsfc-arena-header _LIBSA-HEADER-CRC + !
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID LIB-ARENA-HEADER-VALIDATE
        LIB-S-UNSUPPORTED = _lsfc-assert
    _lsfc-arena-out LIB-ARENA-FACT-SIZE 0xa5 FILL
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-arena-out
        LIB-ARENA-HEADER-DECODE LIB-S-UNSUPPORTED = _lsfc-assert
    _lsfc-arena-out LIB-ARENA-FACT-SIZE 0xa5 _lsfc-filled? _lsfc-assert
    _lsfc-arena-header _LIBSA-HEADER-U + _lsfc-byte-inc
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID LIB-ARENA-HEADER-VALIDATE
        LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-encode-arena
    1 _lsfc-arena-header _LIBSA-ARENA-U + !
    _lsfc-arena-header _LIBSF-ARENA-CRC
        _lsfc-arena-header _LIBSA-HEADER-CRC + !
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID LIB-ARENA-HEADER-VALIDATE
        LIB-S-INVALID = _lsfc-assert
    _lsfc-encode-arena
    1 _lsfc-arena-header LIB-ARENA-HEADER-SIZE 1- + C!
    _lsfc-arena-header _LIBSF-ARENA-CRC
        _lsfc-arena-header _LIBSA-HEADER-CRC + !
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID LIB-ARENA-HEADER-VALIDATE
        LIB-S-INVALID = _lsfc-assert
    _lsfc-encode-arena
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-arena-header
        LIB-ARENA-HEADER-DECODE LIB-S-INVALID = _lsfc-assert
    _lsfc-encode-arena
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID _lsfc-arena-header 1+
        LIB-ARENA-HEADER-DECODE LIB-S-INVALID = _lsfc-assert
    _lsfc-arena-header LIB-ARENA-HEADER-SIZE
        _lsfc-arena-fact LIBAF.ARENA-ID LIB-ARENA-HEADER-VALIDATE
        LIB-S-OK = _lsfc-assert
    _lsfc-stack ;

: _lsfc-bank-codec-contracts  ( -- )
    _lsfc-build-facts
    _lsfc-bank-header LIB-BANK-HEADER-SIZE 0xa5 FILL
    _lsfc-bank-fact _lsfc-bank-header LIB-BANK-HEADER-SIZE 1-
        LIB-BANK-HEADER-ENCODE
    LIB-S-CAPACITY = _lsfc-assert
    0= _lsfc-assert
    _lsfc-bank-header LIB-BANK-HEADER-SIZE 0xa5 _lsfc-filled? _lsfc-assert
    _lsfc-encode-bank
    _lsfc-bank-header _LIBSB-HEADER-CRC + 8
        _lsfc-bank-crc-golden 8 _lsfc-bytes= _lsfc-assert
    _lsfc-bank-header LIB-BANK-HEADER-SIZE LIB-BANK-HEADER-VALIDATE
        LIB-S-OK = _lsfc-assert
    _lsfc-bank-out LIB-BANK-FACT-SIZE 0xa5 FILL
    _lsfc-bank-header LIB-BANK-HEADER-SIZE _lsfc-bank-out
        LIB-BANK-HEADER-DECODE LIB-S-OK = _lsfc-assert
    _lsfc-bank-fact LIB-BANK-FACT-SIZE
        _lsfc-bank-out LIB-BANK-FACT-SIZE _lsfc-bytes= _lsfc-assert
    _lsfc-bank-header _LIBSB-GENERATION + _lsfc-byte-inc
    _lsfc-bank-header LIB-BANK-HEADER-SIZE LIB-BANK-HEADER-VALIDATE
        LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-bank-out LIB-BANK-FACT-SIZE 0xa5 FILL
    _lsfc-bank-header LIB-BANK-HEADER-SIZE _lsfc-bank-out
        LIB-BANK-HEADER-DECODE LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-bank-out LIB-BANK-FACT-SIZE 0xa5 _lsfc-filled? _lsfc-assert
    _lsfc-encode-bank
    2 _lsfc-bank-header _LIBSB-FORMAT + !
    _lsfc-bank-header _LIBSF-BANK-CRC
        _lsfc-bank-header _LIBSB-HEADER-CRC + !
    _lsfc-bank-header LIB-BANK-HEADER-SIZE LIB-BANK-HEADER-VALIDATE
        LIB-S-UNSUPPORTED = _lsfc-assert
    _lsfc-bank-out LIB-BANK-FACT-SIZE 0xa5 FILL
    _lsfc-bank-header LIB-BANK-HEADER-SIZE _lsfc-bank-out
        LIB-BANK-HEADER-DECODE LIB-S-UNSUPPORTED = _lsfc-assert
    _lsfc-bank-out LIB-BANK-FACT-SIZE 0xa5 _lsfc-filled? _lsfc-assert
    _lsfc-bank-header _LIBSB-GENERATION + _lsfc-byte-inc
    _lsfc-bank-header LIB-BANK-HEADER-SIZE LIB-BANK-HEADER-VALIDATE
        LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-encode-bank
    1 _lsfc-bank-header _LIBSB-CATALOG-OFFSET + !
    _lsfc-bank-header _LIBSF-BANK-CRC
        _lsfc-bank-header _LIBSB-HEADER-CRC + !
    _lsfc-bank-header LIB-BANK-HEADER-SIZE LIB-BANK-HEADER-VALIDATE
        LIB-S-INVALID = _lsfc-assert
    _lsfc-encode-bank
    1 _lsfc-bank-header LIB-BANK-HEADER-SIZE 1- + C!
    _lsfc-bank-header _LIBSF-BANK-CRC
        _lsfc-bank-header _LIBSB-HEADER-CRC + !
    _lsfc-bank-header LIB-BANK-HEADER-SIZE LIB-BANK-HEADER-VALIDATE
        LIB-S-INVALID = _lsfc-assert
    _lsfc-encode-bank
    _lsfc-bank-header LIB-BANK-HEADER-SIZE _lsfc-bank-header
        LIB-BANK-HEADER-DECODE LIB-S-INVALID = _lsfc-assert
    _lsfc-stack ;

: _lsfc-head-codec-contracts  ( -- )
    _lsfc-build-facts
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 0xa5 FILL
    _lsfc-head-fact _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 1- 7
        LIB-HEAD-PAYLOAD-ENCODE
    LIB-S-CAPACITY = _lsfc-assert
    0= _lsfc-assert
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 0xa5
        _lsfc-filled? _lsfc-assert
    _lsfc-encode-head
    _lsfc-head-payload _LIBSH-PAYLOAD-CRC + 8
        _lsfc-head-crc-golden 8 _lsfc-bytes= _lsfc-assert
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7
        LIB-HEAD-PAYLOAD-VALIDATE LIB-S-OK = _lsfc-assert
    _lsfc-head-out LIB-HEAD-FACT-SIZE 0xa5 FILL
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7 _lsfc-head-out
        LIB-HEAD-PAYLOAD-DECODE LIB-S-OK = _lsfc-assert
    _lsfc-head-fact LIB-HEAD-FACT-SIZE
        _lsfc-head-out LIB-HEAD-FACT-SIZE _lsfc-bytes= _lsfc-assert
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 8
        LIB-HEAD-PAYLOAD-VALIDATE LIB-S-INTEGRITY = _lsfc-assert
    _lsfc-head-payload _LIBSH-GENERATION + _lsfc-byte-inc
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7
        LIB-HEAD-PAYLOAD-VALIDATE LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-head-out LIB-HEAD-FACT-SIZE 0xa5 FILL
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7 _lsfc-head-out
        LIB-HEAD-PAYLOAD-DECODE LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-head-out LIB-HEAD-FACT-SIZE 0xa5 _lsfc-filled? _lsfc-assert
    _lsfc-encode-head
    2 _lsfc-head-payload _LIBSH-FORMAT + !
    _lsfc-head-payload _LIBSF-HEAD-CRC
        _lsfc-head-payload _LIBSH-PAYLOAD-CRC + !
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7
        LIB-HEAD-PAYLOAD-VALIDATE LIB-S-UNSUPPORTED = _lsfc-assert
    _lsfc-head-out LIB-HEAD-FACT-SIZE 0xa5 FILL
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7 _lsfc-head-out
        LIB-HEAD-PAYLOAD-DECODE LIB-S-UNSUPPORTED = _lsfc-assert
    _lsfc-head-out LIB-HEAD-FACT-SIZE 0xa5 _lsfc-filled? _lsfc-assert
    _lsfc-head-payload _LIBSH-GENERATION + _lsfc-byte-inc
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7
        LIB-HEAD-PAYLOAD-VALIDATE LIB-S-CHECKSUM = _lsfc-assert
    _lsfc-encode-head
    1 _lsfc-head-payload _LIBSH-BANK-U + !
    _lsfc-head-payload _LIBSF-HEAD-CRC
        _lsfc-head-payload _LIBSH-PAYLOAD-CRC + !
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7
        LIB-HEAD-PAYLOAD-VALIDATE LIB-S-INVALID = _lsfc-assert
    _lsfc-encode-head
    1 _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 1- + C!
    _lsfc-head-payload _LIBSF-HEAD-CRC
        _lsfc-head-payload _LIBSH-PAYLOAD-CRC + !
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7
        LIB-HEAD-PAYLOAD-VALIDATE LIB-S-INVALID = _lsfc-assert
    _lsfc-encode-head
    _lsfc-head-payload LIB-HEAD-PAYLOAD-SIZE 7 _lsfc-head-payload
        LIB-HEAD-PAYLOAD-DECODE LIB-S-INVALID = _lsfc-assert
    _lsfc-stack ;

: _lsfc-chain-contracts  ( -- )
    _lsfc-chain-a LIB-CONTENT-CHAIN-GENESIS LIB-S-OK = _lsfc-assert
    _lsfc-chain-a LIB-DIGEST-SIZE
        _lsfc-genesis-golden LIB-DIGEST-SIZE _lsfc-bytes= _lsfc-assert
    _lsfc-frame LIB-STORE-SECTOR-SIZE 17 _lsfc-fill-sequence
    _lsfc-frame LIB-STORE-SECTOR-SIZE _lsfc-frame-digest
        LIB-CONTENT-FRAME-DIGEST LIB-S-OK = _lsfc-assert
    _lsfc-frame-digest LIB-DIGEST-SIZE
        _lsfc-frame-digest-golden LIB-DIGEST-SIZE _lsfc-bytes= _lsfc-assert
    _lsfc-chain-a LIB-ARENA-HEADER-SIZE LIB-STORE-SECTOR-SIZE
        _lsfc-frame-digest _lsfc-chain-b LIB-CONTENT-CHAIN-STEP
        LIB-S-OK = _lsfc-assert
    _lsfc-chain-b LIB-DIGEST-SIZE
        _lsfc-step-golden LIB-DIGEST-SIZE _lsfc-bytes= _lsfc-assert
    _lsfc-chain-a 1024 LIB-STORE-SECTOR-SIZE
        _lsfc-frame-digest _lsfc-chain-b LIB-CONTENT-CHAIN-STEP
        LIB-S-OK = _lsfc-assert
    _lsfc-chain-b LIB-DIGEST-SIZE
        _lsfc-step-golden LIB-DIGEST-SIZE _lsfc-bytes= 0= _lsfc-assert
    _lsfc-chain-a LIB-ARENA-SIZE LIB-CONTENT-FRAME-MAX -
        LIB-CONTENT-FRAME-MAX _lsfc-frame-digest _lsfc-chain-b
        LIB-CONTENT-CHAIN-STEP LIB-S-OK = _lsfc-assert
    _lsfc-chain-a LIB-ARENA-SIZE LIB-CONTENT-FRAME-MAX -
        LIB-STORE-SECTOR-SIZE + LIB-CONTENT-FRAME-MAX
        _lsfc-frame-digest _lsfc-chain-b LIB-CONTENT-CHAIN-STEP
        LIB-S-INVALID = _lsfc-assert
    _lsfc-chain-a 511 LIB-STORE-SECTOR-SIZE
        _lsfc-frame-digest _lsfc-chain-b LIB-CONTENT-CHAIN-STEP
        LIB-S-INVALID = _lsfc-assert
    _lsfc-chain-a 513 LIB-STORE-SECTOR-SIZE
        _lsfc-frame-digest _lsfc-chain-b LIB-CONTENT-CHAIN-STEP
        LIB-S-INVALID = _lsfc-assert
    _lsfc-chain-a LIB-ARENA-HEADER-SIZE 511
        _lsfc-frame-digest _lsfc-chain-b LIB-CONTENT-CHAIN-STEP
        LIB-S-INVALID = _lsfc-assert
    _lsfc-chain-a LIB-ARENA-HEADER-SIZE 513
        _lsfc-frame-digest _lsfc-chain-b LIB-CONTENT-CHAIN-STEP
        LIB-S-INVALID = _lsfc-assert
    _lsfc-chain-a LIB-ARENA-HEADER-SIZE LIB-STORE-SECTOR-SIZE
        _lsfc-frame-digest _lsfc-chain-a LIB-CONTENT-CHAIN-STEP
        LIB-S-INVALID = _lsfc-assert
    _lsfc-chain-a LIB-ARENA-HEADER-SIZE LIB-STORE-SECTOR-SIZE
        _lsfc-frame-digest _lsfc-chain-a 1+ LIB-CONTENT-CHAIN-STEP
        LIB-S-INVALID = _lsfc-assert
    _lsfc-chain-a LIB-DIGEST-SIZE
        _lsfc-genesis-golden LIB-DIGEST-SIZE _lsfc-bytes= _lsfc-assert
    _lsfc-frame LIB-STORE-SECTOR-SIZE _lsfc-frame
        LIB-CONTENT-FRAME-DIGEST LIB-S-INVALID = _lsfc-assert
    _lsfc-frame 511 _lsfc-frame-digest LIB-CONTENT-FRAME-DIGEST
        LIB-S-INVALID = _lsfc-assert
    _lsfc-stack ;

0 _lsfc-fails !
0 _lsfc-checks !
DEPTH _lsfc-depth !
_lsfc-geometry-contracts
_lsfc-fact-contracts
_lsfc-arena-codec-contracts
_lsfc-bank-codec-contracts
_lsfc-head-codec-contracts
_lsfc-chain-contracts

_lsfc-fails @ ?DUP IF
    ." LIBRARY STORE FORMAT FAIL " . ." / " _lsfc-checks @ . CR
ELSE
    ." LIBRARY STORE FORMAT PASS " _lsfc-checks @ . CR
THEN
