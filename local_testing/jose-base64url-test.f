\ jose-base64url-test.f - Strict caller-owned Base64url contracts

PROVIDED akashic-jose-base64url-test

VARIABLE _jbut-fails
VARIABLE _jbut-checks
VARIABLE _jbut-depth

: _jbut-assert  ( flag -- )
    1 _jbut-checks +!
    0= IF
        1 _jbut-fails +!
        ." JOSE BASE64URL ASSERT " _jbut-checks @ . CR
    THEN ;

: _jbut-stack  ( -- )
    DEPTH DUP _jbut-depth @ <> IF
        ." JOSE BASE64URL STACK "
        _jbut-depth @ . ." -> " DUP . CR .S CR
    THEN
    _jbut-depth @ = _jbut-assert ;

: _jbut-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

CREATE _jbut-f       102 C,
CREATE _jbut-fo      102 C, 111 C,
CREATE _jbut-foo     102 C, 111 C, 111 C,
CREATE _jbut-foob    102 C, 111 C, 111 C,  98 C,
CREATE _jbut-fooba   102 C, 111 C, 111 C,  98 C,  97 C,
CREATE _jbut-foobar  102 C, 111 C, 111 C,  98 C,  97 C, 114 C,
CREATE _jbut-url     0xFB C, 0xEF C, 0xFF C,

CREATE _jbut-lf      90 C, 103 C,  10 C,
CREATE _jbut-cr      90 C, 103 C,  13 C,
CREATE _jbut-tab     90 C, 103 C,   9 C,
CREATE _jbut-nul     65 C,   0 C,
CREATE _jbut-high    65 C, 0x80 C,

CREATE _jbut-input   256 ALLOT
CREATE _jbut-output  512 ALLOT
CREATE _jbut-decoded 256 ALLOT
CREATE _jbut-work    128 ALLOT

VARIABLE _jbut-input-a
VARIABLE _jbut-input-u
VARIABLE _jbut-expected-a
VARIABLE _jbut-expected-u

: _jbut-vector  ( input-a input-u expected-a expected-u -- )
    _jbut-expected-u !
    _jbut-expected-a !
    _jbut-input-u !
    _jbut-input-a !

    _jbut-output 512 0xA5 FILL
    _jbut-input-a @ _jbut-input-u @ _jbut-output 512
        JOSE-B64URL-ENCODE
        JOSE-B64URL-S-OK = _jbut-assert
        _jbut-expected-u @ = _jbut-assert
    _jbut-output _jbut-expected-u @
        _jbut-expected-a @ _jbut-expected-u @
        COMPARE 0= _jbut-assert

    _jbut-decoded 256 0x5A FILL
    _jbut-output _jbut-expected-u @ _jbut-decoded 256
        JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert
        _jbut-input-u @ = _jbut-assert
    _jbut-decoded _jbut-input-u @
        _jbut-input-a @ _jbut-input-u @
        COMPARE 0= _jbut-assert ;

: _jbut-decode-reject  ( source source-u -- )
    _jbut-output 64 0xA5 FILL
    _jbut-output 64 JOSE-B64URL-DECODE
        JOSE-B64URL-S-INVALID = _jbut-assert
        0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert ;

: _jbut-init-input  ( -- )
    256 0 DO
        I _jbut-input I + C!
    LOOP ;

: _jbut-test-lengths  ( -- )
    JOSE-B64URL-S-OK JOSE-B64URL-STATUS-VALID? _jbut-assert
    JOSE-B64URL-S-INVALID JOSE-B64URL-STATUS-VALID? _jbut-assert
    JOSE-B64URL-S-CAPACITY JOSE-B64URL-STATUS-VALID? _jbut-assert
    JOSE-B64URL-S-ALIAS JOSE-B64URL-STATUS-VALID? _jbut-assert
    JOSE-B64URL-S-RANGE JOSE-B64URL-STATUS-VALID? _jbut-assert
    JOSE-B64URL-S-PROTECTED JOSE-B64URL-STATUS-VALID? _jbut-assert
    JOSE-B64URL-S-PLATFORM JOSE-B64URL-STATUS-VALID? _jbut-assert
    JOSE-B64URL-S-PLATFORM 1+
        JOSE-B64URL-STATUS-VALID? 0= _jbut-assert

    CALLER-SPAN-S-OK _JBU-CALLER>STATUS
        JOSE-B64URL-S-OK = _jbut-assert
    CALLER-SPAN-S-RANGE _JBU-CALLER>STATUS
        JOSE-B64URL-S-RANGE = _jbut-assert
    CALLER-SPAN-S-PROTECTED _JBU-CALLER>STATUS
        JOSE-B64URL-S-PROTECTED = _jbut-assert
    CALLER-SPAN-S-PLATFORM _JBU-CALLER>STATUS
        JOSE-B64URL-S-PLATFORM = _jbut-assert
    99 _JBU-CALLER>STATUS
        JOSE-B64URL-S-PLATFORM = _jbut-assert

    0 JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 0 = _jbut-assert
    1 JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 2 = _jbut-assert
    2 JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 3 = _jbut-assert
    3 JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 4 = _jbut-assert
    4 JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 6 = _jbut-assert
    -1 JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-INVALID = _jbut-assert 0= _jbut-assert

    _JBU-ENCODE-INPUT-MAX JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert
        _JBU-LENGTH-MAX = _jbut-assert
    _JBU-ENCODE-INPUT-MAX 1+ JOSE-B64URL-ENCODED-LENGTH
        JOSE-B64URL-S-CAPACITY = _jbut-assert 0= _jbut-assert

    0 0 JOSE-B64URL-DECODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 0= _jbut-assert
    S" Zg" JOSE-B64URL-DECODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 1 = _jbut-assert
    S" Zm8" JOSE-B64URL-DECODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 2 = _jbut-assert
    S" Zm9v" JOSE-B64URL-DECODED-LENGTH
        JOSE-B64URL-S-OK = _jbut-assert 3 = _jbut-assert
    S" A" JOSE-B64URL-DECODED-LENGTH
        JOSE-B64URL-S-INVALID = _jbut-assert 0= _jbut-assert
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        JOSE-B64URL-DECODED-LENGTH
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    1 1 JOSE-B64URL-DECODED-LENGTH
        JOSE-B64URL-S-PROTECTED = _jbut-assert 0= _jbut-assert
    _jbut-stack ;

: _jbut-test-vectors  ( -- )
    0 0 0 0 _jbut-vector
    _jbut-f      1 S" Zg"       _jbut-vector
    _jbut-fo     2 S" Zm8"      _jbut-vector
    _jbut-foo    3 S" Zm9v"     _jbut-vector
    _jbut-foob   4 S" Zm9vYg"   _jbut-vector
    _jbut-fooba  5 S" Zm9vYmE"  _jbut-vector
    _jbut-foobar 6 S" Zm9vYmFy" _jbut-vector
    _jbut-url    3 S" --__"     _jbut-vector

    \ Exercise every byte value and all three tail positions without relying
    \ on persistent codec state.  The RFC vectors above independently pin the
    \ alphabet and bit ordering.
    _jbut-input 256 _jbut-output 512 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-OK = _jbut-assert
        DUP 342 = _jbut-assert
    _jbut-output SWAP _jbut-decoded 256 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert
        256 = _jbut-assert
    _jbut-decoded 256 _jbut-input 256 COMPARE 0= _jbut-assert
    _jbut-stack ;

: _jbut-test-strict-rejections  ( -- )
    \ Standard Base64 punctuation, padding, and all ASCII whitespace forms
    \ are outside the JOSE alphabet.
    S" AA+" _jbut-decode-reject
    S" AA/" _jbut-decode-reject
    S" Zg=" _jbut-decode-reject
    S" Zg==" _jbut-decode-reject
    S" =" _jbut-decode-reject
    S" AA=A" _jbut-decode-reject
    S" AAAA=" _jbut-decode-reject
    S" Zg " _jbut-decode-reject
    _jbut-lf  3 _jbut-decode-reject
    _jbut-cr  3 _jbut-decode-reject
    _jbut-tab 3 _jbut-decode-reject
    _jbut-nul 2 _jbut-decode-reject
    _jbut-high 2 _jbut-decode-reject

    \ Impossible length and nonzero unused tail bits are rejected rather
    \ than decoded to the bytes represented by their canonical prefixes.
    S" A"   _jbut-decode-reject
    S" AAAAA" _jbut-decode-reject
    S" Zh"  _jbut-decode-reject
    S" Zm9" _jbut-decode-reject
    S" AB"  _jbut-decode-reject

    \ Exhaust the forbidden low pad-bit values for the shortest two- and
    \ three-character tails, rather than sampling one alternate spelling.
    65 _jbut-work C!
    16 1 DO
        I _JBU-ENCODE-CHAR _jbut-work 1+ C!
        _jbut-work 2 _jbut-decode-reject
    LOOP
    65 _jbut-work C!
    65 _jbut-work 1+ C!
    4 1 DO
        I _JBU-ENCODE-CHAR _jbut-work 2 + C!
        _jbut-work 3 _jbut-decode-reject
    LOOP

    \ The corresponding zero-tail spellings remain valid.
    S" AA" _jbut-output 2 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert 1 = _jbut-assert
    S" AAA" _jbut-output 2 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert 2 = _jbut-assert
    S" ____" _jbut-output 3 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert 3 = _jbut-assert
    _jbut-stack ;

: _jbut-test-transactional-failures  ( -- )
    _jbut-output 64 0xA5 FILL
    _jbut-foobar 6 _jbut-output 7 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-CAPACITY = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    S" Zm9vYmFy" _jbut-output 5 JOSE-B64URL-DECODE
        JOSE-B64URL-S-CAPACITY = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    0 1 _jbut-output 64 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    _jbut-foo -1 _jbut-output 64 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    _jbut-foo 3 0 4 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    _jbut-foo 3 _jbut-output -1 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    -8 16 _jbut-output 64 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    0 2 _jbut-output 64 JOSE-B64URL-DECODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    S" Zg" 0 1 JOSE-B64URL-DECODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    \ Empty spans ignore their address at the generic caller boundary.
    0 0 0 0 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-OK = _jbut-assert 0= _jbut-assert
    0 0 0 0 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert 0= _jbut-assert
    -1 0 -1 0 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-OK = _jbut-assert 0= _jbut-assert
    -1 0 -1 0 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert 0= _jbut-assert
    _jbut-stack ;

: _jbut-test-mapped-spans  ( -- )
    \ Cross-window and protected sources return before inspection and leave
    \ a valid destination wholly unchanged.
    _jbut-output 64 0xA5 FILL
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        _jbut-output 64 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        _jbut-output 64 JOSE-B64URL-DECODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    1 1 _jbut-output 64 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-PROTECTED = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    _jbut-output 64 0xA5 FILL
    1 1 _jbut-output 64 JOSE-B64URL-DECODE
        JOSE-B64URL-S-PROTECTED = _jbut-assert 0= _jbut-assert
    _jbut-output 64 0xA5 _jbut-filled? _jbut-assert

    \ The complete advertised capacity is qualified even when the exact
    \ result would fit before the end of its mapped window.
    _jbut-foo 3 EXT-MEM-BASE EXT-MEM-SIZE + 1 - 8
        JOSE-B64URL-ENCODE
        JOSE-B64URL-S-RANGE = _jbut-assert 0= _jbut-assert
    S" Zm9v" 1 8 JOSE-B64URL-DECODE
        JOSE-B64URL-S-PROTECTED = _jbut-assert 0= _jbut-assert
    _jbut-stack ;

: _jbut-test-alias-contract  ( -- )
    _jbut-work 128 0xA5 FILL
    102 _jbut-work C!
    111 _jbut-work 1+ C!
    111 _jbut-work 2 + C!
    _jbut-work 3 _jbut-work 8 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-ALIAS = _jbut-assert 0= _jbut-assert
    _jbut-work C@ 102 = _jbut-assert
    _jbut-work 1+ C@ 111 = _jbut-assert
    _jbut-work 2 + C@ 111 = _jbut-assert
    _jbut-work 3 + 5 0xA5 _jbut-filled? _jbut-assert

    S" Zm9v" _jbut-work SWAP MOVE
    _jbut-work 4 _jbut-work 4 JOSE-B64URL-DECODE
        JOSE-B64URL-S-ALIAS = _jbut-assert 0= _jbut-assert
    _jbut-work 4 S" Zm9v" COMPARE 0= _jbut-assert

    \ Exact adjacency is disjoint.
    102 _jbut-work C!
    111 _jbut-work 1+ C!
    111 _jbut-work 2 + C!
    _jbut-work 3 _jbut-work 3 + 4 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-OK = _jbut-assert 4 = _jbut-assert
    _jbut-work 3 + 4 S" Zm9v" COMPARE 0= _jbut-assert

    S" Zm9v" _jbut-work 3 + SWAP MOVE
    _jbut-work 3 + 4 _jbut-work 3 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _jbut-assert 3 = _jbut-assert
    _jbut-work 3 S" foo" COMPARE 0= _jbut-assert

    \ Only the exact result span participates in aliasing.  Borrowed source
    \ may occupy unused advertised capacity without being overwritten.
    102 _jbut-work 8 + C!
    111 _jbut-work 9 + C!
    111 _jbut-work 10 + C!
    _jbut-work 8 + 3 _jbut-work 16 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-OK = _jbut-assert 4 = _jbut-assert
    _jbut-work 4 S" Zm9v" COMPARE 0= _jbut-assert

    \ Partial intersection with the exact result is still rejected.
    102 _jbut-work 2 + C!
    111 _jbut-work 3 + C!
    111 _jbut-work 4 + C!
    _jbut-work 2 + 3 _jbut-work 8 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-ALIAS = _jbut-assert 0= _jbut-assert
    _jbut-stack ;

: _JBUT-RUN  ( -- )
    0 _jbut-fails !
    0 _jbut-checks !
    DEPTH _jbut-depth !
    _jbut-init-input
    _jbut-test-lengths
    _jbut-test-vectors
    _jbut-test-strict-rejections
    _jbut-test-transactional-failures
    _jbut-test-mapped-spans
    _jbut-test-alias-contract
    _jbut-stack
    _jbut-fails @ 0= IF
        ." JOSE BASE64URL PASS " _jbut-checks @ . CR
    ELSE
        ." JOSE BASE64URL FAIL " _jbut-fails @ . CR
    THEN ;
