\ test-utf8.f — Smoke tests for akashic utf8.f
\
\ Run with:  REQUIRE test-utf8.f
\ All tests print PASS/FAIL and a final summary.

REQUIRE utf8.f

VARIABLE _TU-PASS   0 _TU-PASS !
VARIABLE _TU-FAIL   0 _TU-FAIL !

: _TU-OK  ( flag name-addr name-len -- )
    ROT IF
        _TU-PASS @ 1+ _TU-PASS !
        ." PASS: " TYPE CR
    ELSE
        _TU-FAIL @ 1+ _TU-FAIL !
        ." FAIL: " TYPE CR
    THEN ;

\ Helper: create a byte buffer on the stack area
CREATE _TU-BUF 16 ALLOT

\ =====================================================================
\  Test 1: Decode ASCII
\ =====================================================================
: _TU-ASCII
    S" A"                              ( addr 1 )
    UTF8-DECODE                        ( cp addr' len' )
    ROT 65 = -ROT                     ( flag addr' len' )
    0 = SWAP DROP                     ( flag flag2 )
    AND
    S" decode ASCII 'A'" _TU-OK ;

\ =====================================================================
\  Test 2: Decode 2-byte (U+00A7 § = C2 A7)
\ =====================================================================
CREATE _TU-SECT 0xC2 C, 0xA7 C,

: _TU-2BYTE
    _TU-SECT 2
    UTF8-DECODE                        ( cp addr' len' )
    ROT 0xA7 = -ROT                   ( flag addr' len' )
    0 = SWAP DROP AND
    S" decode 2-byte U+00A7 section" _TU-OK ;

\ =====================================================================
\  Test 3: Decode 3-byte (U+2014 — = E2 80 94)
\ =====================================================================
CREATE _TU-MDASH 0xE2 C, 0x80 C, 0x94 C,

: _TU-3BYTE
    _TU-MDASH 3
    UTF8-DECODE                        ( cp addr' len' )
    ROT 0x2014 = -ROT
    0 = SWAP DROP AND
    S" decode 3-byte U+2014 em-dash" _TU-OK ;

\ =====================================================================
\  Test 4: Decode 4-byte (U+1F600 😀 = F0 9F 98 80)
\ =====================================================================
CREATE _TU-GRIN 0xF0 C, 0x9F C, 0x98 C, 0x80 C,

: _TU-4BYTE
    _TU-GRIN 4
    UTF8-DECODE
    ROT 0x1F600 = -ROT
    0 = SWAP DROP AND
    S" decode 4-byte U+1F600 grinning" _TU-OK ;

\ =====================================================================
\  Test 5: Invalid leading byte (0xFF) → U+FFFD, advances 1
\ =====================================================================
CREATE _TU-BAD 0xFF C, 0x41 C,

: _TU-INVALID
    _TU-BAD 2
    UTF8-DECODE                        ( cp addr' len' )
    ROT 0xFFFD = -ROT                 ( flag addr' len' )
    1 = SWAP DROP AND                  \ 1 byte remaining
    S" invalid byte -> U+FFFD" _TU-OK ;

\ =====================================================================
\  Test 6: Truncated 2-byte sequence → U+FFFD
\ =====================================================================
CREATE _TU-TRUNC 0xC2 C,

: _TU-TRUNCATED
    _TU-TRUNC 1
    UTF8-DECODE
    ROT 0xFFFD = -ROT
    0 = SWAP DROP AND
    S" truncated 2-byte -> U+FFFD" _TU-OK ;

\ =====================================================================
\  Test 7: Overlong 2-byte (U+0041 encoded as C1 81) → U+FFFD
\ =====================================================================
CREATE _TU-OVER 0xC1 C, 0x81 C,

: _TU-OVERLONG
    _TU-OVER 2
    UTF8-DECODE
    ROT 0xFFFD = -ROT
    0 = SWAP DROP AND
    S" overlong 2-byte -> U+FFFD" _TU-OK ;

\ =====================================================================
\  Test 8: UTF8-ENCODE roundtrip for U+00A7
\ =====================================================================
: _TU-ENC-2
    0xA7 _TU-BUF UTF8-ENCODE          ( buf' )
    _TU-BUF -                          ( bytes-written )
    2 =                                ( flag: 2 bytes? )
    _TU-BUF C@ 0xC2 = AND
    _TU-BUF 1+ C@ 0xA7 = AND
    S" encode U+00A7 -> C2 A7" _TU-OK ;

\ =====================================================================
\  Test 9: UTF8-ENCODE roundtrip for U+2014
\ =====================================================================
: _TU-ENC-3
    0x2014 _TU-BUF UTF8-ENCODE
    _TU-BUF - 3 =
    _TU-BUF C@ 0xE2 = AND
    _TU-BUF 1+ C@ 0x80 = AND
    _TU-BUF 2 + C@ 0x94 = AND
    S" encode U+2014 -> E2 80 94" _TU-OK ;

\ =====================================================================
\  Test 10: UTF8-LEN
\ =====================================================================
CREATE _TU-MIX 0x41 C, 0xC2 C, 0xA7 C, 0xE2 C, 0x80 C, 0x94 C,

: _TU-LENGTH
    _TU-MIX 6 UTF8-LEN
    3 =
    S" UTF8-LEN 'A' + section + mdash = 3" _TU-OK ;

\ =====================================================================
\  Test 11: UTF8-VALID? on good input
\ =====================================================================
: _TU-VALID-GOOD
    _TU-MIX 6 UTF8-VALID?
    S" UTF8-VALID? on good input" _TU-OK ;

\ =====================================================================
\  Test 12: UTF8-VALID? on bad input
\ =====================================================================
: _TU-VALID-BAD
    _TU-BAD 2 UTF8-VALID?
    0= \ should return 0 (invalid), invert is TRUE
    S" UTF8-VALID? on bad input" _TU-OK ;

\ =====================================================================
\  Test 13: UTF8-NTH
\ =====================================================================
: _TU-NTH
    _TU-MIX 6 0 UTF8-NTH 0x41 =       \ 0th = 'A'
    _TU-MIX 6 1 UTF8-NTH 0xA7 = AND   \ 1st = §
    _TU-MIX 6 2 UTF8-NTH 0x2014 = AND \ 2nd = —
    _TU-MIX 6 3 UTF8-NTH 0xFFFD = AND \ 3rd = out of range
    S" UTF8-NTH 0,1,2,3" _TU-OK ;

\ =====================================================================
\  Test 14: Encode → Decode roundtrip for U+1F600
\ =====================================================================
: _TU-ROUNDTRIP
    0x1F600 _TU-BUF UTF8-ENCODE       ( buf' )
    _TU-BUF -                          ( nbytes = 4 )
    _TU-BUF SWAP                       ( addr len )
    UTF8-DECODE                        ( cp addr' len' )
    ROT 0x1F600 = -ROT
    0 = SWAP DROP AND
    S" roundtrip U+1F600" _TU-OK ;

\ =====================================================================
\  Run all
\ =====================================================================

: TEST-UTF8  ( -- )
    0 _TU-PASS !  0 _TU-FAIL !
    ." === UTF-8 Tests ===" CR
    _TU-ASCII
    _TU-2BYTE
    _TU-3BYTE
    _TU-4BYTE
    _TU-INVALID
    _TU-TRUNCATED
    _TU-OVERLONG
    _TU-ENC-2
    _TU-ENC-3
    _TU-LENGTH
    _TU-VALID-GOOD
    _TU-VALID-BAD
    _TU-NTH
    _TU-ROUNDTRIP
    CR ." --- Results: "
    _TU-PASS @ . ." passed, "
    _TU-FAIL @ . ." failed ---" CR
    _TU-FAIL @ 0 > IF
        ." SOME TESTS FAILED" CR
    ELSE
        ." ALL TESTS PASSED" CR
    THEN ;

TEST-UTF8
