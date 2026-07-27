\ ed25519-linked-test.f - Linked Ed25519 caller-migration qualification

PROVIDED akashic-ed25519-linked-test

VARIABLE _edlt-fails
VARIABLE _edlt-checks
VARIABLE _edlt-depth

: _edlt-assert  ( flag -- )
    1 _edlt-checks +!
    0= IF
        1 _edlt-fails +!
        ." ED25519 LINKED ASSERT " _edlt-checks @ . CR
    THEN ;

: _edlt-stack  ( -- )
    DEPTH _edlt-depth @ = _edlt-assert ;

: _edlt-bytes=  ( first second length -- flag )
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ RFC 8032 section 7.1, TEST 1: empty message.
CREATE _edlt-seed
    0x9D C, 0x61 C, 0xB1 C, 0x9D C, 0xEF C, 0xFD C, 0x5A C, 0x60 C,
    0xBA C, 0x84 C, 0x4A C, 0xF4 C, 0x92 C, 0xEC C, 0x2C C, 0xC4 C,
    0x44 C, 0x49 C, 0xC5 C, 0x69 C, 0x7B C, 0x32 C, 0x69 C, 0x19 C,
    0x70 C, 0x3B C, 0xAC C, 0x03 C, 0x1C C, 0xAE C, 0x7F C, 0x60 C,

CREATE _edlt-want-pub
    0xD7 C, 0x5A C, 0x98 C, 0x01 C, 0x82 C, 0xB1 C, 0x0A C, 0xB7 C,
    0xD5 C, 0x4B C, 0xFE C, 0xD3 C, 0xC9 C, 0x64 C, 0x07 C, 0x3A C,
    0x0E C, 0xE1 C, 0x72 C, 0xF3 C, 0xDA C, 0xA6 C, 0x23 C, 0x25 C,
    0xAF C, 0x02 C, 0x1A C, 0x68 C, 0xF7 C, 0x07 C, 0x51 C, 0x1A C,

CREATE _edlt-want-sig
    0xE5 C, 0x56 C, 0x43 C, 0x00 C, 0xC3 C, 0x60 C, 0xAC C, 0x72 C,
    0x90 C, 0x86 C, 0xE2 C, 0xCC C, 0x80 C, 0x6E C, 0x82 C, 0x8A C,
    0x84 C, 0x87 C, 0x7F C, 0x1E C, 0xB8 C, 0xE5 C, 0xD9 C, 0x74 C,
    0xD8 C, 0x73 C, 0xE0 C, 0x65 C, 0x22 C, 0x49 C, 0x01 C, 0x55 C,
    0x5F C, 0xB8 C, 0x82 C, 0x15 C, 0x90 C, 0xA3 C, 0x3B C, 0xAC C,
    0xC6 C, 0x1E C, 0x39 C, 0x70 C, 0x1C C, 0xF9 C, 0xB4 C, 0x6B C,
    0xD2 C, 0x5B C, 0xF5 C, 0xF0 C, 0x59 C, 0x5B C, 0xBE C, 0x24 C,
    0x65 C, 0x51 C, 0x41 C, 0x43 C, 0x8E C, 0x7A C, 0x10 C, 0x0B C,

CREATE _edlt-empty 0 C,
CREATE _edlt-pub  ED25519-KEY-LEN ALLOT
CREATE _edlt-priv 64 ALLOT
CREATE _edlt-sig  ED25519-SIG-LEN ALLOT

: _edlt-ownership-released?  ( -- flag )
    _ed25519-guard GUARD-HELD? 0=
    _fld-guard GUARD-HELD? 0= AND
    _crypto-acc-guard GUARD-HELD? 0= AND
    CRYPTO-ACC-TRANSACTION-MINE? 0= AND ;

: _edlt-test-ownership-shape  ( -- )
    _ed25519-guard GUARD-BLOCKING? _edlt-assert
    _fld-guard GUARD-BLOCKING? _edlt-assert
    _crypto-acc-guard GUARD-BLOCKING? _edlt-assert
    _edlt-ownership-released? _edlt-assert
    _edlt-stack ;

: _edlt-test-rfc8032-empty  ( -- )
    _edlt-pub ED25519-KEY-LEN 0xA5 FILL
    _edlt-priv 64 0xA5 FILL
    _edlt-sig ED25519-SIG-LEN 0xA5 FILL

    _edlt-seed _edlt-pub _edlt-priv ED25519-KEYGEN
    _edlt-pub _edlt-want-pub ED25519-KEY-LEN
        _edlt-bytes= _edlt-assert
    _edlt-ownership-released? _edlt-assert
    _edlt-stack

    _edlt-empty 0 _edlt-priv _edlt-pub _edlt-sig ED25519-SIGN
    _edlt-sig _edlt-want-sig ED25519-SIG-LEN
        _edlt-bytes= _edlt-assert
    _edlt-ownership-released? _edlt-assert
    _edlt-stack

    _edlt-empty 0 _edlt-pub _edlt-sig ED25519-VERIFY
        _edlt-assert
    _edlt-ownership-released? _edlt-assert
    _edlt-stack ;

: _EDLT-RUN  ( -- )
    0 _edlt-fails !
    0 _edlt-checks !
    DEPTH _edlt-depth !
    ED25519-KEY-LEN 32 = _edlt-assert
    ED25519-SIG-LEN 64 = _edlt-assert
    _edlt-test-ownership-shape
    _edlt-test-rfc8032-empty
    _edlt-stack
    _edlt-fails @ 0= IF
        ." ED25519 LINKED PASS " _edlt-checks @ . CR
    ELSE
        ." ED25519 LINKED FAIL " _edlt-fails @ . CR
    THEN ;
