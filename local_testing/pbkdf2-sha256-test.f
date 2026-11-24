\ pbkdf2-sha256-test.f - PBKDF2-HMAC-SHA-256 contracts and cycle counts

PROVIDED akashic-pbkdf2-test

VARIABLE _pbkt-fails
VARIABLE _pbkt-checks
VARIABLE _pbkt-depth
VARIABLE _pbkt-remaining
VARIABLE _pbkt-cycles

: _pbkt-assert  ( flag -- )
    1 _pbkt-checks +!
    0= IF
        1 _pbkt-fails +!
        ." PBKDF2 SHA256 ASSERT " _pbkt-checks @ . CR
    THEN ;

: _pbkt-stack  ( -- )
    DEPTH DUP _pbkt-depth @ <> IF
        ." PBKDF2 SHA256 STACK "
        _pbkt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _pbkt-depth @ = _pbkt-assert ;

: _pbkt-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

: _pbkt-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ RFC 7914 section 11 gives the two PBKDF2-HMAC-SHA-256 vectors.  The
\ other expected keys come from Python's hashlib.pbkdf2_hmac, which the
\ unit's Python side recomputes from these same inputs.

\ 6 bytes: "passwd"
CREATE _pbkt-passwd
    0x70 C, 0x61 C, 0x73 C, 0x73 C, 0x77 C, 0x64 C,

\ 4 bytes: "salt"
CREATE _pbkt-salt
    0x73 C, 0x61 C, 0x6C C, 0x74 C,

\ 8 bytes: "Password"
CREATE _pbkt-password
    0x50 C, 0x61 C, 0x73 C, 0x73 C, 0x77 C, 0x6F C, 0x72 C, 0x64 C,

\ 4 bytes: "NaCl"
CREATE _pbkt-nacl
    0x4E C, 0x61 C, 0x43 C, 0x6C C,

\ 85 bytes: "pbkdf2 long password " four times, then "!"
CREATE _pbkt-long
    0x70 C, 0x62 C, 0x6B C, 0x64 C, 0x66 C, 0x32 C, 0x20 C, 0x6C C,
    0x6F C, 0x6E C, 0x67 C, 0x20 C, 0x70 C, 0x61 C, 0x73 C, 0x73 C,
    0x77 C, 0x6F C, 0x72 C, 0x64 C, 0x20 C, 0x70 C, 0x62 C, 0x6B C,
    0x64 C, 0x66 C, 0x32 C, 0x20 C, 0x6C C, 0x6F C, 0x6E C, 0x67 C,
    0x20 C, 0x70 C, 0x61 C, 0x73 C, 0x73 C, 0x77 C, 0x6F C, 0x72 C,
    0x64 C, 0x20 C, 0x70 C, 0x62 C, 0x6B C, 0x64 C, 0x66 C, 0x32 C,
    0x20 C, 0x6C C, 0x6F C, 0x6E C, 0x67 C, 0x20 C, 0x70 C, 0x61 C,
    0x73 C, 0x73 C, 0x77 C, 0x6F C, 0x72 C, 0x64 C, 0x20 C, 0x70 C,
    0x62 C, 0x6B C, 0x64 C, 0x66 C, 0x32 C, 0x20 C, 0x6C C, 0x6F C,
    0x6E C, 0x67 C, 0x20 C, 0x70 C, 0x61 C, 0x73 C, 0x73 C, 0x77 C,
    0x6F C, 0x72 C, 0x64 C, 0x20 C, 0x21 C,

\ 4 bytes: "step"
CREATE _pbkt-step
    0x73 C, 0x74 C, 0x65 C, 0x70 C,

\ 12 bytes: "pbkdf2 steps"
CREATE _pbkt-step-salt
    0x70 C, 0x62 C, 0x6B C, 0x64 C, 0x66 C, 0x32 C, 0x20 C, 0x73 C,
    0x74 C, 0x65 C, 0x70 C, 0x73 C,

\ RFC 7914: P="passwd", S="salt", c=1, dkLen=64
CREATE _pbkt-exp-rfc1
    0x55 C, 0xAC C, 0x04 C, 0x6E C, 0x56 C, 0xE3 C, 0x08 C, 0x9F C,
    0xEC C, 0x16 C, 0x91 C, 0xC2 C, 0x25 C, 0x44 C, 0xB6 C, 0x05 C,
    0xF9 C, 0x41 C, 0x85 C, 0x21 C, 0x6D C, 0xDE C, 0x04 C, 0x65 C,
    0xE6 C, 0x8B C, 0x9D C, 0x57 C, 0xC2 C, 0x0D C, 0xAC C, 0xBC C,
    0x49 C, 0xCA C, 0x9C C, 0xCC C, 0xF1 C, 0x79 C, 0xB6 C, 0x45 C,
    0x99 C, 0x16 C, 0x64 C, 0xB3 C, 0x9D C, 0x77 C, 0xEF C, 0x31 C,
    0x7C C, 0x71 C, 0xB8 C, 0x45 C, 0xB1 C, 0xE3 C, 0x0B C, 0xD5 C,
    0x09 C, 0x11 C, 0x20 C, 0x41 C, 0xD3 C, 0xA1 C, 0x97 C, 0x83 C,

\ RFC 7914: P="Password", S="NaCl", c=80000, dkLen=64
CREATE _pbkt-exp-rfc2
    0x4D C, 0xDC C, 0xD8 C, 0xF6 C, 0x0B C, 0x98 C, 0xBE C, 0x21 C,
    0x83 C, 0x0C C, 0xEE C, 0x5E C, 0xF2 C, 0x27 C, 0x01 C, 0xF9 C,
    0x64 C, 0x1A C, 0x44 C, 0x18 C, 0xD0 C, 0x4C C, 0x04 C, 0x14 C,
    0xAE C, 0xFF C, 0x08 C, 0x87 C, 0x6B C, 0x34 C, 0xAB C, 0x56 C,
    0xA1 C, 0xD4 C, 0x25 C, 0xA1 C, 0x22 C, 0x58 C, 0x33 C, 0x54 C,
    0x9A C, 0xDB C, 0x84 C, 0x1B C, 0x51 C, 0xC9 C, 0xB3 C, 0x17 C,
    0x6A C, 0x27 C, 0x2B C, 0xDE C, 0xBB C, 0xA1 C, 0xD0 C, 0x78 C,
    0x47 C, 0x8F C, 0x62 C, 0xB3 C, 0x97 C, 0xF3 C, 0x3C C, 0x8D C,

\ hashlib: the 85-byte password, S="salt", c=2, dkLen=40
CREATE _pbkt-exp-long
    0xF6 C, 0x01 C, 0xF2 C, 0x03 C, 0x18 C, 0x0C C, 0xF9 C, 0x4F C,
    0x5C C, 0x8D C, 0xD7 C, 0xA7 C, 0x30 C, 0xDE C, 0x56 C, 0x70 C,
    0x5E C, 0x4F C, 0x14 C, 0xAC C, 0xF0 C, 0x99 C, 0xD4 C, 0x42 C,
    0xF3 C, 0x3B C, 0x36 C, 0x57 C, 0xE5 C, 0xDB C, 0x1C C, 0xD4 C,
    0xAC C, 0x1F C, 0x4D C, 0x3A C, 0x85 C, 0x2C C, 0x31 C, 0x00 C,

\ hashlib: empty password, empty salt, c=3, dkLen=32
CREATE _pbkt-exp-empty
    0xB3 C, 0x72 C, 0x79 C, 0x64 C, 0x54 C, 0xD3 C, 0x7A C, 0xC0 C,
    0x42 C, 0xA1 C, 0x95 C, 0xB6 C, 0x2E C, 0xEB C, 0x7C C, 0xFE C,
    0xD3 C, 0x8D C, 0xDD C, 0x92 C, 0xF7 C, 0x57 C, 0xE2 C, 0xFE C,
    0xE0 C, 0x42 C, 0x10 C, 0xDF C, 0x03 C, 0xAC C, 0x1D C, 0x2E C,

\ hashlib: P="step", S="pbkdf2 steps", c=37, dkLen=33
CREATE _pbkt-exp-steps
    0xF4 C, 0xBA C, 0x28 C, 0xE4 C, 0x24 C, 0x22 C, 0x1A C, 0x19 C,
    0x32 C, 0x06 C, 0xA4 C, 0xF3 C, 0x92 C, 0xE5 C, 0xA9 C, 0x38 C,
    0xDC C, 0x6B C, 0xFD C, 0xD1 C, 0xB8 C, 0x0A C, 0x6B C, 0x78 C,
    0x11 C, 0xB8 C, 0xE6 C, 0x0C C, 0x8A C, 0x55 C, 0x9B C, 0x0B C,
    0x6D C,

64 PBKDF2-SHA256-WORKSPACE-SIZE CONSTANT _pbkt-ws-u
CREATE _pbkt-ws _pbkt-ws-u ALLOT
CREATE _pbkt-dk 64 ALLOT
CREATE _pbkt-block 96 ALLOT

\ One-shot derivation into _pbkt-dk through _pbkt-ws.
: _pbkt-derive  ( password password-u salt salt-u iterations dk-u -- status )
    _pbkt-dk SWAP _pbkt-ws PBKDF2-SHA256 ;

: _pbkt-test-sizes  ( -- )
    0 PBKDF2-SHA256-WORKSPACE-SIZE 0= _pbkt-assert
    -1 PBKDF2-SHA256-WORKSPACE-SIZE 0= _pbkt-assert
    1 PBKDF2-SHA256-WORKSPACE-SIZE 288 = _pbkt-assert
    32 PBKDF2-SHA256-WORKSPACE-SIZE 288 = _pbkt-assert
    33 PBKDF2-SHA256-WORKSPACE-SIZE 320 = _pbkt-assert
    _pbkt-ws-u 320 = _pbkt-assert
    PBKDF2-SHA256-S-OK PBKDF2-SHA256-STATUS-VALID? _pbkt-assert
    PBKDF2-SHA256-S-CRYPTO PBKDF2-SHA256-STATUS-VALID? _pbkt-assert
    PBKDF2-SHA256-S-CRYPTO 1+ PBKDF2-SHA256-STATUS-VALID? 0= _pbkt-assert
    -1 PBKDF2-SHA256-STATUS-VALID? 0= _pbkt-assert
    _pbkt-stack ;

: _pbkt-test-rfc1  ( -- )
    _pbkt-dk 64 0 FILL
    _pbkt-passwd 6 _pbkt-salt 4 1 64 _pbkt-derive
        PBKDF2-SHA256-S-OK = _pbkt-assert
    _pbkt-dk _pbkt-exp-rfc1 64 _pbkt-bytes= _pbkt-assert
    _pbkt-ws _pbkt-ws-u _pbkt-zero? _pbkt-assert
    _pbkt-stack ;

\ A password longer than the 64-byte block is hashed first; a 40-byte key
\ takes a partial second block.
: _pbkt-test-long  ( -- )
    _pbkt-dk 64 0xA5 FILL
    _pbkt-long 85 _pbkt-salt 4 2 40 _pbkt-derive
        PBKDF2-SHA256-S-OK = _pbkt-assert
    _pbkt-dk _pbkt-exp-long 40 _pbkt-bytes= _pbkt-assert
    _pbkt-dk 40 + C@ 0xA5 = _pbkt-assert
    _pbkt-ws _pbkt-ws-u _pbkt-zero? _pbkt-assert
    _pbkt-stack ;

\ RFC 8018 admits an empty password and an empty salt.
: _pbkt-test-empty  ( -- )
    _pbkt-dk 64 0 FILL
    0 0 0 0 3 32 _pbkt-derive
        PBKDF2-SHA256-S-OK = _pbkt-assert
    _pbkt-dk _pbkt-exp-empty 32 _pbkt-bytes= _pbkt-assert
    _pbkt-stack ;

\ The same derivation one iteration per step reaches the same key; block
\ changes cost no budget, and finishing early is refused.
: _pbkt-test-steps  ( -- )
    _pbkt-step 4 _pbkt-step-salt 12 37 33 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-OK = _pbkt-assert
    _pbkt-dk _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-STATE = _pbkt-assert
    1 _pbkt-ws PBKDF2-SHA256-STEP
        PBKDF2-SHA256-S-OK = _pbkt-assert
    71 = _pbkt-assert
    0 _pbkt-cycles !
    BEGIN
        1 _pbkt-cycles +!
        1 _pbkt-ws PBKDF2-SHA256-STEP
        PBKDF2-SHA256-S-OK = _pbkt-assert
        DUP _pbkt-remaining !
    0= UNTIL
    _pbkt-cycles @ 71 = _pbkt-assert
    _pbkt-dk 64 0xA5 FILL
    _pbkt-dk _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-OK = _pbkt-assert
    _pbkt-dk _pbkt-exp-steps 33 _pbkt-bytes= _pbkt-assert
    _pbkt-dk 33 + C@ 0xA5 = _pbkt-assert
    _pbkt-ws _pbkt-ws-u _pbkt-zero? _pbkt-assert
    \ A finished workspace is no longer live.
    1 _pbkt-ws PBKDF2-SHA256-STEP
        PBKDF2-SHA256-S-STATE = _pbkt-assert
    0= _pbkt-assert
    _pbkt-stack ;

: _pbkt-test-rejections  ( -- )
    _pbkt-ws _pbkt-ws-u 0 FILL
    1 _pbkt-ws PBKDF2-SHA256-STEP
        PBKDF2-SHA256-S-STATE = _pbkt-assert
    0= _pbkt-assert
    _pbkt-dk _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-STATE = _pbkt-assert
    _pbkt-ws PBKDF2-SHA256-ABANDON
        PBKDF2-SHA256-S-STATE = _pbkt-assert
    0 PBKDF2-SHA256-ABANDON
        PBKDF2-SHA256-S-STATE = _pbkt-assert

    _pbkt-passwd 6 _pbkt-salt 4 1 0 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-INVALID = _pbkt-assert
    _pbkt-passwd 6 _pbkt-salt 4 0 32 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-INVALID = _pbkt-assert
    _pbkt-passwd 6 _pbkt-salt 4 1 32 0 PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-INVALID = _pbkt-assert
    0 6 _pbkt-salt 4 1 32 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-INVALID = _pbkt-assert
    \ An iteration count whose remaining total cannot be a cell.
    _pbkt-passwd 6 _pbkt-salt 4 -1 1 RSHIFT 64 _pbkt-ws
        PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-INVALID = _pbkt-assert
    \ Inputs inside the workspace.
    _pbkt-ws 8 + 6 _pbkt-salt 4 1 32 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-ALIAS = _pbkt-assert
    _pbkt-passwd 6 _pbkt-ws 200 + 4 1 32 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-ALIAS = _pbkt-assert
    _pbkt-ws _pbkt-ws-u _pbkt-zero? _pbkt-assert

    \ A zero budget is refused; a destination inside the workspace is
    \ refused and leaves the finished derivation for a later finish.
    _pbkt-passwd 6 _pbkt-salt 4 2 32 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-OK = _pbkt-assert
    0 _pbkt-ws PBKDF2-SHA256-STEP
        PBKDF2-SHA256-S-INVALID = _pbkt-assert
    DROP
    1 _pbkt-ws PBKDF2-SHA256-STEP
        PBKDF2-SHA256-S-OK = _pbkt-assert
    0= _pbkt-assert
    _pbkt-ws 16 + _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-ALIAS = _pbkt-assert
    0 _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-INVALID = _pbkt-assert
    _pbkt-ws PBKDF2-SHA256-ABANDON
        PBKDF2-SHA256-S-OK = _pbkt-assert
    _pbkt-ws _pbkt-ws-u _pbkt-zero? _pbkt-assert
    _pbkt-stack ;

\ Device cycles, for the record: 1,000 iterations in one step and in ten
\ steps of 100, BEGIN alone, and one 96-byte hash through the public word
\ against the held transaction.
: _pbkt-hash-x100  ( -- )
    100 0 DO _pbkt-block 96 _pbkt-dk SHA256-HASH DROP LOOP ;

: _pbkt-held-x100  ( -- )
    100 0 DO _pbkt-block 96 _pbkt-dk SHA256-HELD-HASH DROP LOOP ;

: _pbkt-measure  ( -- )
    _pbkt-passwd 6 _pbkt-salt 4 1001 32 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-OK = _pbkt-assert
    PERF-CYCLES 1000 _pbkt-ws PBKDF2-SHA256-STEP PERF-CYCLES >R
        PBKDF2-SHA256-S-OK = _pbkt-assert
    0= _pbkt-assert
    R> SWAP - ." PBKDF2 CYCLES 1000 ITERATIONS ONE STEP=" . CR
    _pbkt-dk _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-OK = _pbkt-assert

    _pbkt-passwd 6 _pbkt-salt 4 1001 32 _pbkt-ws PBKDF2-SHA256-BEGIN
        PBKDF2-SHA256-S-OK = _pbkt-assert
    PERF-CYCLES
    10 0 DO 100 _pbkt-ws PBKDF2-SHA256-STEP 2DROP LOOP
    PERF-CYCLES SWAP - ." PBKDF2 CYCLES 1000 ITERATIONS TEN STEPS=" . CR
    _pbkt-dk _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-OK = _pbkt-assert

    PERF-CYCLES
    _pbkt-passwd 6 _pbkt-salt 4 1 32 _pbkt-ws PBKDF2-SHA256-BEGIN
    PERF-CYCLES >R
        PBKDF2-SHA256-S-OK = _pbkt-assert
    R> SWAP - ." PBKDF2 CYCLES BEGIN=" . CR
    _pbkt-dk _pbkt-ws PBKDF2-SHA256-FINISH
        PBKDF2-SHA256-S-OK = _pbkt-assert

    _pbkt-block 96 0x3C FILL
    PERF-CYCLES _pbkt-hash-x100 PERF-CYCLES SWAP -
        ." SHA256-HASH CYCLES X100=" . CR
    PERF-CYCLES ['] _pbkt-held-x100 SHA256-WITH-TRANSACTION
    PERF-CYCLES SWAP -
        ." SHA256-HELD-HASH CYCLES X100=" . CR
    _pbkt-stack ;

\ The second RFC 7914 vector runs 160,000 iterations over two blocks.
: _pbkt-test-rfc2  ( -- )
    _pbkt-dk 64 0 FILL
    PERF-CYCLES >R
    _pbkt-password 8 _pbkt-nacl 4 80000 64 _pbkt-derive
    PERF-CYCLES R> - _pbkt-cycles !
        PBKDF2-SHA256-S-OK = _pbkt-assert
    _pbkt-dk _pbkt-exp-rfc2 64 _pbkt-bytes= _pbkt-assert
    ." PBKDF2 CYCLES RFC7914 160000 ITERATIONS=" _pbkt-cycles @ . CR
    _pbkt-stack ;

: _PBKT-RUN  ( -- )
    0 _pbkt-fails !
    0 _pbkt-checks !
    DEPTH _pbkt-depth !
    ." PBKDF2 SHA256 RUN START" CR
    _pbkt-test-sizes
    _pbkt-test-rfc1
    _pbkt-test-long
    _pbkt-test-empty
    _pbkt-test-steps
    _pbkt-test-rejections
    _pbkt-measure
    _pbkt-test-rfc2
    _pbkt-stack
    _pbkt-fails @ 0= IF
        ." PBKDF2 SHA256 PASS " _pbkt-checks @ . CR
    ELSE
        ." PBKDF2 SHA256 FAIL " _pbkt-fails @ . CR
    THEN ;
