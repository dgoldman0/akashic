\ sha256-scoped-test.f - Checked hardware SHA-256 contracts

PROVIDED akashic-s256-contract

VARIABLE _s256t-fails
VARIABLE _s256t-checks
VARIABLE _s256t-depth

: _s256t-assert  ( flag -- )
    1 _s256t-checks +!
    0= IF
        1 _s256t-fails +!
        ." SHA256 SCOPED ASSERT " _s256t-checks @ . CR
    THEN ;

: _s256t-stack  ( -- )
    DEPTH _s256t-depth @ = _s256t-assert ;

: _s256t-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

CREATE _s256t-abc
    0x61 C, 0x62 C, 0x63 C,

CREATE _s256t-expected-abc
    0xBA C, 0x78 C, 0x16 C, 0xBF C, 0x8F C, 0x01 C, 0xCF C, 0xEA C,
    0x41 C, 0x41 C, 0x40 C, 0xDE C, 0x5D C, 0xAE C, 0x22 C, 0x23 C,
    0xB0 C, 0x03 C, 0x61 C, 0xA3 C, 0x96 C, 0x17 C, 0x7A C, 0x9C C,
    0xB4 C, 0x10 C, 0xFF C, 0x61 C, 0xF2 C, 0x00 C, 0x15 C, 0xAD C,

CREATE _s256t-expected-empty
    0xE3 C, 0xB0 C, 0xC4 C, 0x42 C, 0x98 C, 0xFC C, 0x1C C, 0x14 C,
    0x9A C, 0xFB C, 0xF4 C, 0xC8 C, 0x99 C, 0x6F C, 0xB9 C, 0x24 C,
    0x27 C, 0xAE C, 0x41 C, 0xE4 C, 0x64 C, 0x9B C, 0x93 C, 0x4C C,
    0xA4 C, 0x95 C, 0x99 C, 0x1B C, 0x78 C, 0x52 C, 0xB8 C, 0x55 C,

CREATE _s256t-digest SHA256-LEN ALLOT
CREATE _s256t-copy   SHA256-LEN ALLOT

: _s256t-snapshot  ( -- )
    _s256t-digest _s256t-copy SHA256-LEN MOVE ;

: _s256t-unchanged?  ( -- flag )
    _s256t-digest _s256t-copy SHA256-LEN _s256t-bytes= ;

: _s256t-abc?  ( -- flag )
    _s256t-digest _s256t-expected-abc SHA256-LEN _s256t-bytes= ;

: _s256t-toggle-byte  ( address -- )
    DUP C@ 1 XOR SWAP C! ;

: _s256t-unowned?  ( -- flag )
    _sha256-guard GUARD-HELD? 0=
    CRYPTO-ACC-TRANSACTION-MINE? 0= AND ;

: _s256t-test-statuses  ( -- )
    SHA256-LEN 32 = _s256t-assert
    SHA256-HEX-LEN 64 = _s256t-assert
    SHA256-S-OK SHA256-STATUS-VALID? _s256t-assert
    SHA256-S-CRYPTO SHA256-STATUS-VALID? _s256t-assert
    SHA256-S-OK 1- SHA256-STATUS-VALID? 0= _s256t-assert
    SHA256-S-CRYPTO 1+ SHA256-STATUS-VALID? 0= _s256t-assert
    _sha256-guard GUARD-BLOCKING? _s256t-assert
    _s256t-stack ;

: _s256t-test-caller-span-status  ( -- )
    _s256t-abc 3 SHA256-CALLER-SPAN-STATUS
        SHA256-S-OK = _s256t-assert
    0 0 SHA256-CALLER-SPAN-STATUS
        SHA256-S-OK = _s256t-assert
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        SHA256-CALLER-SPAN-STATUS
        SHA256-S-RANGE = _s256t-assert
    _sha256-guard 1 SHA256-CALLER-SPAN-STATUS
        SHA256-S-ALIAS = _s256t-assert
    0 1 SHA256-CALLER-SPAN-STATUS
        SHA256-S-INVALID = _s256t-assert

    \ The injected address is this calling core's private BIOS context.
    \ Qualification remains pure even while that context is active.
    _SHA-CONTRACT-CONTEXT 1 SHA256-CALLER-SPAN-STATUS
        SHA256-S-ALIAS = _s256t-assert
    _s256t-digest SHA256-LEN 0xA5 FILL
    _s256t-snapshot
    SHA256-INIT SHA256-S-OK = _s256t-assert
    _SHA-CONTRACT-CONTEXT 1 _s256t-digest SHA256-HASH
        SHA256-S-ALIAS = _s256t-assert
    _s256t-unchanged? _s256t-assert
    _s256t-abc 0 SHA256-UPDATE
        SHA256-S-OK = _s256t-assert
    SHA256-CLEAR SHA256-S-OK = _s256t-assert
    _s256t-unowned? _s256t-assert
    _s256t-stack ;

: _s256t-test-success  ( -- )
    _s256t-abc 3 _s256t-digest SHA256-HASH
        SHA256-S-OK = _s256t-assert
    _s256t-abc? _s256t-assert
    _s256t-unowned? _s256t-assert

    _s256t-abc 1 _s256t-abc 1+ 2
        _s256t-digest SHA256-HASH-2
        SHA256-S-OK = _s256t-assert
    _s256t-abc? _s256t-assert

    _s256t-abc 1 _s256t-abc 1+ 1 _s256t-abc 2 + 1
        _s256t-digest SHA256-HASH-3
        SHA256-S-OK = _s256t-assert
    _s256t-abc? _s256t-assert

    0 0 _s256t-digest SHA256-HASH
        SHA256-S-OK = _s256t-assert
    _s256t-digest _s256t-expected-empty SHA256-LEN
        _s256t-bytes= _s256t-assert
    _s256t-unowned? _s256t-assert
    _s256t-stack ;

: _s256t-test-compare  ( -- )
    _s256t-expected-abc _s256t-digest SHA256-LEN MOVE
    _s256t-expected-abc _s256t-copy SHA256-LEN MOVE
    _s256t-digest _s256t-copy SHA256-COMPARE _s256t-assert

    \ Byte zero remains equal while a later byte differs.
    _s256t-copy 17 + _s256t-toggle-byte
    _s256t-digest _s256t-copy SHA256-COMPARE 0= _s256t-assert
    _s256t-copy 17 + _s256t-toggle-byte

    \ A first-byte mismatch is rejected independently.
    _s256t-copy _s256t-toggle-byte
    _s256t-digest _s256t-copy SHA256-COMPARE 0= _s256t-assert
    _s256t-stack ;

: _s256t-test-rejections  ( -- )
    _s256t-digest SHA256-LEN 0xA5 FILL
    _s256t-snapshot
    0 1 _s256t-digest SHA256-HASH
        SHA256-S-INVALID = _s256t-assert
    _s256t-unchanged? _s256t-assert

    _s256t-abc -1 _s256t-digest SHA256-HASH
        SHA256-S-INVALID = _s256t-assert
    _s256t-unchanged? _s256t-assert

    _s256t-abc 3 0 SHA256-HASH
        SHA256-S-INVALID = _s256t-assert

    _s256t-abc 3 _s256t-abc SHA256-HASH
        SHA256-S-ALIAS = _s256t-assert

    \ This nonwrapping span crosses the end of an advertised physical
    \ window, so pure caller-span qualification rejects it before INIT.
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        _s256t-digest SHA256-HASH
        SHA256-S-RANGE = _s256t-assert
    _s256t-unchanged? _s256t-assert
    _s256t-unowned? _s256t-assert

    \ Immediate reuse proves that the rejected preflight claimed neither
    \ the BIOS context nor either library guard.
    _s256t-abc 3 _s256t-digest SHA256-HASH
        SHA256-S-OK = _s256t-assert
    _s256t-abc? _s256t-assert
    _s256t-unowned? _s256t-assert
    _s256t-stack ;

: _s256t-test-reserved-aliases  ( -- )
    _s256t-digest SHA256-LEN 0xA5 FILL
    _s256t-snapshot

    \ Acquiring the outer transaction would mutate this input.
    _crypto-acc-guard 1 _s256t-digest SHA256-HASH
        SHA256-S-ALIAS = _s256t-assert
    _s256t-unchanged? _s256t-assert

    \ Exercise later input positions as well as the one-span form.
    _s256t-abc 1 _CACC-PUBLIC-ZERO 1
        _s256t-digest SHA256-HASH-2
        SHA256-S-ALIAS = _s256t-assert
    _s256t-unchanged? _s256t-assert

    _s256t-abc 1 _s256t-abc 1+ 1 _sha256-guard 1
        _s256t-digest SHA256-HASH-3
        SHA256-S-ALIAS = _s256t-assert
    _s256t-unchanged? _s256t-assert

    \ Outer cleanup must not be allowed to erase an OK digest.
    _CACC-SCRUB-LO _s256t-copy SHA256-LEN MOVE
    _s256t-abc 3 _CACC-SCRUB-LO SHA256-HASH
        SHA256-S-ALIAS = _s256t-assert
    _CACC-SCRUB-LO _s256t-copy SHA256-LEN
        _s256t-bytes= _s256t-assert

    \ FINAL must not target either guard while it is owned.
    _sha256-guard _s256t-copy SHA256-LEN MOVE
    _s256t-abc 3 _sha256-guard SHA256-HASH
        SHA256-S-ALIAS = _s256t-assert
    _sha256-guard _s256t-copy SHA256-LEN
        _s256t-bytes= _s256t-assert

    _crypto-acc-guard _s256t-copy SHA256-LEN MOVE
    _s256t-abc 3 _crypto-acc-guard SHA256-HASH
        SHA256-S-ALIAS = _s256t-assert
    _crypto-acc-guard _s256t-copy SHA256-LEN
        _s256t-bytes= _s256t-assert

    _s256t-unowned? _s256t-assert
    _s256t-stack ;

\ Held hashes run only inside SHA256-WITH-TRANSACTION, which owns both
\ boundaries for the whole run and releases them afterwards.
VARIABLE _s256t-held-status
VARIABLE _s256t-held-mine

: _s256t-held-body  ( -- )
    SHA256-TRANSACTION-MINE? _s256t-held-mine !
    _s256t-abc 3 _s256t-digest SHA256-HELD-HASH
    _s256t-held-status !
    \ A second complete hash in the same transaction reuses it.
    _s256t-held-status @ SHA256-S-OK = IF
        _s256t-abc 3 _s256t-copy SHA256-HELD-HASH
        _s256t-held-status !
    THEN ;

\ An exception inside the run propagates after the run has cleared the
\ BIOS context and released both boundaries.
: _s256t-held-throw-body  ( -- )
    SHA256-INIT DROP
    _s256t-abc 3 SHA256-UPDATE DROP
    -4242 THROW ;

: _s256t-held-throw  ( -- )
    ['] _s256t-held-throw-body SHA256-WITH-TRANSACTION ;

: _s256t-test-held  ( -- )
    \ Outside a held transaction the word refuses without hashing.
    _s256t-digest SHA256-LEN 0xA5 FILL
    _s256t-snapshot
    _s256t-abc 3 _s256t-digest SHA256-HELD-HASH
        SHA256-S-STATE = _s256t-assert
    _s256t-unchanged? _s256t-assert
    SHA256-TRANSACTION-MINE? 0= _s256t-assert
    _s256-held @ 0= _s256t-assert

    0 _s256t-held-status ! 0 _s256t-held-mine !
    _s256t-copy SHA256-LEN 0 FILL
    ['] _s256t-held-body SHA256-WITH-TRANSACTION
    _s256t-held-mine @ _s256t-assert
    _s256t-held-status @ SHA256-S-OK = _s256t-assert
    _s256t-abc? _s256t-assert
    _s256t-copy _s256t-expected-abc SHA256-LEN
        _s256t-bytes= _s256t-assert
    _s256t-unowned? _s256t-assert
    _s256-held @ 0= _s256t-assert

    ['] _s256t-held-throw CATCH -4242 = _s256t-assert
    _s256t-unowned? _s256t-assert
    _s256-held @ 0= _s256t-assert
    \ The cleared context takes a fresh hash.
    _s256t-abc 3 _s256t-digest SHA256-HASH
        SHA256-S-OK = _s256t-assert
    _s256t-abc? _s256t-assert
    _s256t-stack ;

\ A keyed state stands for a 64-byte first block: a resume equals the one
\ hash of block || message, for a message right after the state, apart
\ from it, or in two parts.
CREATE _s256t-keyed 96 ALLOT        \ a keyed state, then a message
CREATE _s256t-block 64 ALLOT
CREATE _s256t-one 32 ALLOT
CREATE _s256t-two 32 ALLOT
CREATE _s256t-three 32 ALLOT
VARIABLE _s256t-keyed-status

: _s256t-keyed-body  ( -- )
    _s256t-block _s256t-keyed SHA256-HELD-KEY _s256t-keyed-status !
    _s256t-keyed _s256t-keyed 64 + 32 _s256t-one SHA256-HELD-RESUME
        _s256t-keyed-status +!
    _s256t-keyed _s256t-abc 3 _s256t-two SHA256-HELD-RESUME
        _s256t-keyed-status +!
    _s256t-keyed _s256t-abc 2 _s256t-abc 2 + 1 _s256t-three
        SHA256-HELD-RESUME-2 _s256t-keyed-status +! ;

: _s256t-test-keyed  ( -- )
    _s256t-block 64 0x36 FILL
    _s256t-keyed 96 0 FILL
    _s256t-keyed 64 + 32 0x5C FILL
    \ Outside a held transaction every keyed word refuses.
    _s256t-block _s256t-keyed SHA256-HELD-KEY
        SHA256-S-STATE = _s256t-assert
    _s256t-keyed _s256t-abc 3 _s256t-two SHA256-HELD-RESUME
        SHA256-S-STATE = _s256t-assert
    _s256t-keyed _s256t-abc 2 _s256t-abc 2 + 1 _s256t-three
        SHA256-HELD-RESUME-2 SHA256-S-STATE = _s256t-assert
    SHA256-KEYED-SIZE 64 >= _s256t-assert
    -1 _s256t-keyed-status !
    ['] _s256t-keyed-body SHA256-WITH-TRANSACTION
    _s256t-keyed-status @ 0= _s256t-assert
    _s256t-block 64 _s256t-keyed 64 + 32 _s256t-digest SHA256-HASH-2
        SHA256-S-OK = _s256t-assert
    _s256t-one _s256t-digest SHA256-LEN _s256t-bytes= _s256t-assert
    _s256t-block 64 _s256t-abc 3 _s256t-digest SHA256-HASH-2
        SHA256-S-OK = _s256t-assert
    _s256t-two _s256t-digest SHA256-LEN _s256t-bytes= _s256t-assert
    _s256t-three _s256t-digest SHA256-LEN _s256t-bytes= _s256t-assert
    _s256t-unowned? _s256t-assert
    _s256t-stack ;

: _S256T-RUN  ( -- )
    0 _s256t-fails !
    0 _s256t-checks !
    DEPTH _s256t-depth !
    ." SHA256 RUN START" CR
    _s256t-test-statuses
    _s256t-test-caller-span-status
    _s256t-test-success
    _s256t-test-compare
    _s256t-test-rejections
    _s256t-test-reserved-aliases
    _s256t-test-held
    _s256t-test-keyed
    _s256t-stack
    _s256t-fails @ 0= IF
        ." SHA256 SCOPED PASS " _s256t-checks @ . CR
    ELSE
        ." SHA256 SCOPED FAIL " _s256t-fails @ . CR
    THEN ;
