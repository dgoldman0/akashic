\ sha512-scoped-test.f - Checked hardware SHA-512 contracts

PROVIDED akashic-s512-contract

VARIABLE _s512t-fails
VARIABLE _s512t-checks
VARIABLE _s512t-depth

: _s512t-assert  ( flag -- )
    1 _s512t-checks +!
    0= IF
        1 _s512t-fails +!
        ." SHA512 SCOPED ASSERT " _s512t-checks @ . CR
    THEN ;

: _s512t-stack  ( -- )
    DEPTH _s512t-depth @ = _s512t-assert ;

: _s512t-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

CREATE _s512t-abc
    0x61 C, 0x62 C, 0x63 C,

CREATE _s512t-expected-abc
    0xDD C, 0xAF C, 0x35 C, 0xA1 C, 0x93 C, 0x61 C, 0x7A C, 0xBA C,
    0xCC C, 0x41 C, 0x73 C, 0x49 C, 0xAE C, 0x20 C, 0x41 C, 0x31 C,
    0x12 C, 0xE6 C, 0xFA C, 0x4E C, 0x89 C, 0xA9 C, 0x7E C, 0xA2 C,
    0x0A C, 0x9E C, 0xEE C, 0xE6 C, 0x4B C, 0x55 C, 0xD3 C, 0x9A C,
    0x21 C, 0x92 C, 0x99 C, 0x2A C, 0x27 C, 0x4F C, 0xC1 C, 0xA8 C,
    0x36 C, 0xBA C, 0x3C C, 0x23 C, 0xA3 C, 0xFE C, 0xEB C, 0xBD C,
    0x45 C, 0x4D C, 0x44 C, 0x23 C, 0x64 C, 0x3C C, 0xE8 C, 0x0E C,
    0x2A C, 0x9A C, 0xC9 C, 0x4F C, 0xA5 C, 0x4C C, 0xA4 C, 0x9F C,

CREATE _s512t-expected-empty
    0xCF C, 0x83 C, 0xE1 C, 0x35 C, 0x7E C, 0xEF C, 0xB8 C, 0xBD C,
    0xF1 C, 0x54 C, 0x28 C, 0x50 C, 0xD6 C, 0x6D C, 0x80 C, 0x07 C,
    0xD6 C, 0x20 C, 0xE4 C, 0x05 C, 0x0B C, 0x57 C, 0x15 C, 0xDC C,
    0x83 C, 0xF4 C, 0xA9 C, 0x21 C, 0xD3 C, 0x6C C, 0xE9 C, 0xCE C,
    0x47 C, 0xD0 C, 0xD1 C, 0x3C C, 0x5D C, 0x85 C, 0xF2 C, 0xB0 C,
    0xFF C, 0x83 C, 0x18 C, 0xD2 C, 0x87 C, 0x7E C, 0xEC C, 0x2F C,
    0x63 C, 0xB9 C, 0x31 C, 0xBD C, 0x47 C, 0x41 C, 0x7A C, 0x81 C,
    0xA5 C, 0x38 C, 0x32 C, 0x7A C, 0xF9 C, 0x27 C, 0xDA C, 0x3E C,

CREATE _s512t-digest SHA512-LEN ALLOT
CREATE _s512t-copy   SHA512-LEN ALLOT

: _s512t-snapshot  ( -- )
    _s512t-digest _s512t-copy SHA512-LEN MOVE ;

: _s512t-unchanged?  ( -- flag )
    _s512t-digest _s512t-copy SHA512-LEN _s512t-bytes= ;

: _s512t-abc?  ( -- flag )
    _s512t-digest _s512t-expected-abc SHA512-LEN _s512t-bytes= ;

: _s512t-toggle-byte  ( address -- )
    DUP C@ 1 XOR SWAP C! ;

: _s512t-unowned?  ( -- flag )
    _sha512-guard GUARD-HELD? 0=
    CRYPTO-ACC-TRANSACTION-MINE? 0= AND ;

: _s512t-test-statuses  ( -- )
    SHA512-LEN 64 = _s512t-assert
    SHA512-HEX-LEN 128 = _s512t-assert
    SHA512-S-OK SHA512-STATUS-VALID? _s512t-assert
    SHA512-S-CRYPTO SHA512-STATUS-VALID? _s512t-assert
    SHA512-S-OK 1- SHA512-STATUS-VALID? 0= _s512t-assert
    SHA512-S-CRYPTO 1+ SHA512-STATUS-VALID? 0= _s512t-assert
    _sha512-guard GUARD-BLOCKING? _s512t-assert
    _s512t-stack ;

: _s512t-test-caller-span-status  ( -- )
    _s512t-abc 3 SHA512-CALLER-SPAN-STATUS
        SHA512-S-OK = _s512t-assert
    0 0 SHA512-CALLER-SPAN-STATUS
        SHA512-S-OK = _s512t-assert
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        SHA512-CALLER-SPAN-STATUS
        SHA512-S-RANGE = _s512t-assert
    _sha512-guard 1 SHA512-CALLER-SPAN-STATUS
        SHA512-S-ALIAS = _s512t-assert
    0 1 SHA512-CALLER-SPAN-STATUS
        SHA512-S-INVALID = _s512t-assert

    \ The injected address is this calling core's private BIOS context.
    \ Qualification remains pure even while that context is active.
    _SHA-CONTRACT-CONTEXT 1 SHA512-CALLER-SPAN-STATUS
        SHA512-S-ALIAS = _s512t-assert
    _s512t-digest SHA512-LEN 0xA5 FILL
    _s512t-snapshot
    SHA512-INIT SHA512-S-OK = _s512t-assert
    _SHA-CONTRACT-CONTEXT 1 _s512t-digest SHA512-HASH
        SHA512-S-ALIAS = _s512t-assert
    _s512t-unchanged? _s512t-assert
    _s512t-abc 0 SHA512-UPDATE
        SHA512-S-OK = _s512t-assert
    SHA512-CLEAR SHA512-S-OK = _s512t-assert
    _s512t-unowned? _s512t-assert
    _s512t-stack ;

: _s512t-test-success  ( -- )
    _s512t-abc 3 _s512t-digest SHA512-HASH
        SHA512-S-OK = _s512t-assert
    _s512t-abc? _s512t-assert
    _s512t-unowned? _s512t-assert

    _s512t-abc 1 _s512t-abc 1+ 2
        _s512t-digest SHA512-HASH-2
        SHA512-S-OK = _s512t-assert
    _s512t-abc? _s512t-assert

    _s512t-abc 1 _s512t-abc 1+ 1 _s512t-abc 2 + 1
        _s512t-digest SHA512-HASH-3
        SHA512-S-OK = _s512t-assert
    _s512t-abc? _s512t-assert

    0 0 _s512t-digest SHA512-HASH
        SHA512-S-OK = _s512t-assert
    _s512t-digest _s512t-expected-empty SHA512-LEN
        _s512t-bytes= _s512t-assert
    _s512t-unowned? _s512t-assert
    _s512t-stack ;

: _s512t-test-compare  ( -- )
    _s512t-expected-abc _s512t-digest SHA512-LEN MOVE
    _s512t-expected-abc _s512t-copy SHA512-LEN MOVE
    _s512t-digest _s512t-copy SHA512-COMPARE _s512t-assert

    \ Byte zero remains equal while a later byte differs.
    _s512t-copy 41 + _s512t-toggle-byte
    _s512t-digest _s512t-copy SHA512-COMPARE 0= _s512t-assert
    _s512t-copy 41 + _s512t-toggle-byte

    _s512t-copy _s512t-toggle-byte
    _s512t-digest _s512t-copy SHA512-COMPARE 0= _s512t-assert
    _s512t-stack ;

: _s512t-test-rejections  ( -- )
    _s512t-digest SHA512-LEN 0xA5 FILL
    _s512t-snapshot
    0 1 _s512t-digest SHA512-HASH
        SHA512-S-INVALID = _s512t-assert
    _s512t-unchanged? _s512t-assert

    _s512t-abc -1 _s512t-digest SHA512-HASH
        SHA512-S-INVALID = _s512t-assert
    _s512t-unchanged? _s512t-assert

    _s512t-abc 3 0 SHA512-HASH
        SHA512-S-INVALID = _s512t-assert

    _s512t-abc 3 _s512t-abc SHA512-HASH
        SHA512-S-ALIAS = _s512t-assert

    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        _s512t-digest SHA512-HASH
        SHA512-S-RANGE = _s512t-assert
    _s512t-unchanged? _s512t-assert
    _s512t-unowned? _s512t-assert

    _s512t-abc 3 _s512t-digest SHA512-HASH
        SHA512-S-OK = _s512t-assert
    _s512t-abc? _s512t-assert
    _s512t-unowned? _s512t-assert
    _s512t-stack ;

: _s512t-test-reserved-aliases  ( -- )
    _s512t-digest SHA512-LEN 0xA5 FILL
    _s512t-snapshot

    _crypto-acc-guard 1 _s512t-digest SHA512-HASH
        SHA512-S-ALIAS = _s512t-assert
    _s512t-unchanged? _s512t-assert

    _s512t-abc 1 _CACC-PUBLIC-ZERO 1
        _s512t-digest SHA512-HASH-2
        SHA512-S-ALIAS = _s512t-assert
    _s512t-unchanged? _s512t-assert

    _s512t-abc 1 _s512t-abc 1+ 1 _sha512-guard 1
        _s512t-digest SHA512-HASH-3
        SHA512-S-ALIAS = _s512t-assert
    _s512t-unchanged? _s512t-assert

    \ An output beginning in crypto-ACC scrub storage is forbidden.
    _CACC-SCRUB-LO _s512t-copy SHA512-LEN MOVE
    _s512t-abc 3 _CACC-SCRUB-LO SHA512-HASH
        SHA512-S-ALIAS = _s512t-assert
    _CACC-SCRUB-LO _s512t-copy SHA512-LEN
        _s512t-bytes= _s512t-assert

    _sha512-guard _s512t-copy SHA512-LEN MOVE
    _s512t-abc 3 _sha512-guard SHA512-HASH
        SHA512-S-ALIAS = _s512t-assert
    _sha512-guard _s512t-copy SHA512-LEN
        _s512t-bytes= _s512t-assert

    _crypto-acc-guard _s512t-copy SHA512-LEN MOVE
    _s512t-abc 3 _crypto-acc-guard SHA512-HASH
        SHA512-S-ALIAS = _s512t-assert
    _crypto-acc-guard _s512t-copy SHA512-LEN
        _s512t-bytes= _s512t-assert

    _s512t-unowned? _s512t-assert
    _s512t-stack ;

: _S512T-RUN  ( -- )
    0 _s512t-fails !
    0 _s512t-checks !
    DEPTH _s512t-depth !
    ." SHA512 RUN START" CR
    _s512t-test-statuses
    _s512t-test-caller-span-status
    _s512t-test-success
    _s512t-test-compare
    _s512t-test-rejections
    _s512t-test-reserved-aliases
    _s512t-stack
    _s512t-fails @ 0= IF
        ." SHA512 SCOPED PASS " _s512t-checks @ . CR
    ELSE
        ." SHA512 SCOPED FAIL " _s512t-fails @ . CR
    THEN ;
