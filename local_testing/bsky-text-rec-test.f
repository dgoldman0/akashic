\ Focused executable contract for the exact Bluesky text-record encoder.

PROVIDED bluesky-text-record-test

VARIABLE _btrt-failed
VARIABLE _btrt-check
VARIABLE _btrt-expected-u
VARIABLE _btrt-scan-a
VARIABLE _btrt-scan-u
VARIABLE _btrt-scan-byte

CREATE _btrt-work-a-raw BSKY-TEXT-RECORD-WORKSPACE-SIZE 7 + ALLOT
CREATE _btrt-work-b-raw BSKY-TEXT-RECORD-WORKSPACE-SIZE 7 + ALLOT
CREATE _btrt-output-a BSKY-TEXT-RECORD-BODY-MAX 1+ ALLOT
CREATE _btrt-output-b 256 ALLOT
CREATE _btrt-expected 256 ALLOT
CREATE _btrt-special 5 ALLOT
CREATE _btrt-malformed 2 ALLOT
CREATE _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX 1+ ALLOT
CREATE _btrt-adjacent 85 ALLOT

: _btrt-work-a  ( -- workspace )
    _btrt-work-a-raw 7 + -8 AND ;

: _btrt-work-b  ( -- workspace )
    _btrt-work-b-raw 7 + -8 AND ;

: _btrt-assert  ( flag -- )
    1 _btrt-check +!
    0= IF
        -1 _btrt-failed !
        ." BSKY TEXT RECORD ASSERT " _btrt-check @ . CR
    THEN ;

: _btrt-status  ( actual expected -- )
    = _btrt-assert ;

: _btrt-all-byte?  ( address length byte -- flag )
    _btrt-scan-byte !
    _btrt-scan-u !
    _btrt-scan-a !
    _btrt-scan-u @ 0 ?DO
        _btrt-scan-a @ I + C@ _btrt-scan-byte @ <> IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _btrt-exp-reset  ( -- )
    0 _btrt-expected-u ! ;

: _btrt-exp-char  ( character -- )
    _btrt-expected _btrt-expected-u @ + C!
    1 _btrt-expected-u +! ;

: _btrt-exp-append  ( address length -- )
    DUP >R
    _btrt-expected _btrt-expected-u @ + SWAP MOVE
    R> _btrt-expected-u +! ;

: _btrt-exp-prefix  ( -- )
    _btrt-exp-reset
    [CHAR] { _btrt-exp-char
    [CHAR] " _btrt-exp-char S" $type" _btrt-exp-append
    [CHAR] " _btrt-exp-char [CHAR] : _btrt-exp-char
    [CHAR] " _btrt-exp-char S" app.bsky.feed.post" _btrt-exp-append
    [CHAR] " _btrt-exp-char [CHAR] , _btrt-exp-char
    [CHAR] " _btrt-exp-char S" text" _btrt-exp-append
    [CHAR] " _btrt-exp-char [CHAR] : _btrt-exp-char
    [CHAR] " _btrt-exp-char ;

: _btrt-exp-suffix  ( timestamp-a timestamp-u -- )
    [CHAR] " _btrt-exp-char [CHAR] , _btrt-exp-char
    [CHAR] " _btrt-exp-char S" createdAt" _btrt-exp-append
    [CHAR] " _btrt-exp-char [CHAR] : _btrt-exp-char
    [CHAR] " _btrt-exp-char
    _btrt-exp-append
    [CHAR] " _btrt-exp-char [CHAR] } _btrt-exp-char ;

: _btrt-exp-record  ( text-a text-u timestamp-a timestamp-u -- )
    2>R _btrt-exp-prefix _btrt-exp-append 2R> _btrt-exp-suffix ;

: _btrt-exact?  ( output written -- flag )
    _btrt-expected _btrt-expected-u @ COMPARE 0= ;

: _btrt-encode-ok
  \ ( epoch-ms text-a text-u destination capacity workspace -- written )
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-OK _btrt-status ;

: _btrt-setup-bytes  ( -- )
    [CHAR] A _btrt-special C!
    [CHAR] " _btrt-special 1+ C!
    [CHAR] \ _btrt-special 2 + C!
    10 _btrt-special 3 + C!
    1 _btrt-special 4 + C!
    0xC0 _btrt-malformed C!
    0xAF _btrt-malformed 1+ C! ;

: _btrt-test-vocabulary  ( -- )
    BSKY-TEXT-RECORD-TEXT-MAX 3000 = _btrt-assert
    BSKY-TEXT-RECORD-BODY-MAX 18075 = _btrt-assert
    BSKY-TEXT-RECORD-WORKSPACE-SIZE 18176 = _btrt-assert
    BSKY-TEXT-RECORD-S-OK BSKY-TEXT-RECORD-STATUS-VALID? _btrt-assert
    BSKY-TEXT-RECORD-S-INTERNAL BSKY-TEXT-RECORD-STATUS-VALID? _btrt-assert
    -1 BSKY-TEXT-RECORD-STATUS-VALID? 0= _btrt-assert
    0 0 BSKY-TEXT-RECORD-MEASURE
    BSKY-TEXT-RECORD-S-OK _btrt-status 75 = _btrt-assert
    S" hello" BSKY-TEXT-RECORD-MEASURE
    BSKY-TEXT-RECORD-S-OK _btrt-status 80 = _btrt-assert ;

: _btrt-test-exact  ( -- )
    0 0 S" 1970-01-01T00:00:00Z" _btrt-exp-record
    _btrt-output-a 256 165 FILL
    _btrt-work-a BSKY-TEXT-RECORD-WORKSPACE-SIZE 90 FILL
    0 0 0 _btrt-output-a 256 _btrt-work-a _btrt-encode-ok
    DUP _btrt-output-a SWAP _btrt-exact? _btrt-assert
    _btrt-output-a + C@ 165 = _btrt-assert
    _btrt-work-a BSKY-TEXT-RECORD-WORKSPACE-SIZE 0
    _btrt-all-byte? _btrt-assert

    S" hello" S" 2024-06-15T15:30:00Z" _btrt-exp-record
    1718465400123 S" hello" _btrt-output-a 256 _btrt-work-a
    _btrt-encode-ok
    DUP 80 = _btrt-assert
    _btrt-output-a SWAP _btrt-exact? _btrt-assert

    0 0 S" 9999-12-31T23:59:59Z" _btrt-exp-record
    _BSKYTR-EPOCH-MS-MAX 0 0 _btrt-output-a 256 _btrt-work-a
    _btrt-encode-ok
    DUP 75 = _btrt-assert
    _btrt-output-a SWAP _btrt-exact? _btrt-assert ;

: _btrt-test-escaping  ( -- )
    _btrt-exp-prefix
    [CHAR] A _btrt-exp-char
    [CHAR] \ _btrt-exp-char [CHAR] " _btrt-exp-char
    [CHAR] \ _btrt-exp-char [CHAR] \ _btrt-exp-char
    [CHAR] \ _btrt-exp-char [CHAR] n _btrt-exp-char
    [CHAR] \ _btrt-exp-char [CHAR] u _btrt-exp-char
    [CHAR] 0 _btrt-exp-char [CHAR] 0 _btrt-exp-char
    [CHAR] 0 _btrt-exp-char [CHAR] 1 _btrt-exp-char
    S" 1970-01-01T00:00:00Z" _btrt-exp-suffix
    0 _btrt-special 5 _btrt-output-a 256 _btrt-work-a
    _btrt-encode-ok
    _btrt-output-a SWAP _btrt-exact? _btrt-assert

    0xE2 _btrt-special C!
    0x98 _btrt-special 1+ C!
    0x83 _btrt-special 2 + C!
    _btrt-special 3 S" 1970-01-01T00:00:00Z" _btrt-exp-record
    0 _btrt-special 3 _btrt-output-a 256 _btrt-work-a
    _btrt-encode-ok
    _btrt-output-a SWAP _btrt-exact? _btrt-assert ;

: _btrt-test-bounds  ( -- )
    _btrt-output-a 256 165 FILL
    0 S" hello" _btrt-output-a 79 _btrt-work-a
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-CAPACITY _btrt-status 0= _btrt-assert
    _btrt-output-a 256 165 _btrt-all-byte? _btrt-assert

    0 _btrt-malformed 2 _btrt-output-a 256 _btrt-work-a
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-UTF8 _btrt-status 0= _btrt-assert
    _btrt-output-a 256 165 _btrt-all-byte? _btrt-assert

    -1 0 0 _btrt-output-a 256 _btrt-work-a
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-RANGE _btrt-status 0= _btrt-assert
    _BSKYTR-EPOCH-MS-MAX 1+ 0 0 _btrt-output-a 256 _btrt-work-a
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-RANGE _btrt-status 0= _btrt-assert

    _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX 1+ [CHAR] a FILL
    0 _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX 1+
    _btrt-output-a BSKY-TEXT-RECORD-BODY-MAX _btrt-work-a
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-TEXT _btrt-status 0= _btrt-assert
    _btrt-output-a 256 165 _btrt-all-byte? _btrt-assert

    0 0 0 _btrt-output-a 256 0 BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-INVALID _btrt-status 0= _btrt-assert
    0 0 0 _btrt-output-a 256 _btrt-work-a 1+
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-INVALID _btrt-status 0= _btrt-assert
    0 0 0 0 75 _btrt-work-a BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-INVALID _btrt-status 0= _btrt-assert
    0 0 0 _btrt-output-a -1 _btrt-work-a BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-INVALID _btrt-status 0= _btrt-assert
    _btrt-output-a 256 165 _btrt-all-byte? _btrt-assert ;

: _btrt-test-alias-and-adjacency  ( -- )
    S" hi" _btrt-output-a SWAP MOVE
    0 _btrt-output-a 2 _btrt-output-a 80 _btrt-work-a
    BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-ALIAS _btrt-status 0= _btrt-assert
    _btrt-output-a C@ [CHAR] h = _btrt-assert

    0 0 0 _btrt-work-a 75 _btrt-work-a BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-ALIAS _btrt-status 0= _btrt-assert

    S" hi" _btrt-work-a _BSKYTRW-STAGING-OFF + SWAP MOVE
    0 _btrt-work-a _BSKYTRW-STAGING-OFF + 2
    _btrt-output-a 80 _btrt-work-a BSKY-TEXT-RECORD-ENCODE
    BSKY-TEXT-RECORD-S-ALIAS _btrt-status 0= _btrt-assert

    S" hello" _btrt-adjacent 80 + SWAP MOVE
    1718465400123 _btrt-adjacent 80 + 5
    _btrt-adjacent 80 _btrt-work-a _btrt-encode-ok
    80 = _btrt-assert
    _btrt-adjacent 80 + 5 S" hello" COMPARE 0= _btrt-assert ;

: _btrt-test-protocol-maximum  ( -- )
    _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX [CHAR] " FILL
    _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX
    BSKY-TEXT-RECORD-MEASURE
    BSKY-TEXT-RECORD-S-OK _btrt-status 6075 = _btrt-assert
    0 _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX
    _btrt-output-a BSKY-TEXT-RECORD-BODY-MAX _btrt-work-a
    _btrt-encode-ok 6075 = _btrt-assert
    _btrt-output-a 38 + C@ [CHAR] \ = _btrt-assert
    _btrt-output-a 39 + C@ [CHAR] " = _btrt-assert

    _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX 0 FILL
    0 _btrt-max-text BSKY-TEXT-RECORD-TEXT-MAX
    _btrt-output-a BSKY-TEXT-RECORD-BODY-MAX _btrt-work-a
    _btrt-encode-ok
    BSKY-TEXT-RECORD-BODY-MAX = _btrt-assert
    _btrt-output-a 38 + C@ [CHAR] \ = _btrt-assert
    _btrt-output-a 39 + C@ [CHAR] u = _btrt-assert
    _btrt-output-a 40 + C@ [CHAR] 0 = _btrt-assert ;

: _btrt-test-independent-workspaces  ( -- )
    0 S" one" _btrt-output-a 256 _btrt-work-a _btrt-encode-ok DROP
    0 S" two" _btrt-output-b 256 _btrt-work-b _btrt-encode-ok DROP
    _btrt-output-a 78 _btrt-output-b 78 COMPARE 0<> _btrt-assert
    _btrt-work-a BSKY-TEXT-RECORD-WORKSPACE-SIZE 0
    _btrt-all-byte? _btrt-assert
    _btrt-work-b BSKY-TEXT-RECORD-WORKSPACE-SIZE 0
    _btrt-all-byte? _btrt-assert
    0 BSKY-TEXT-RECORD-WORKSPACE-CLEAR
    BSKY-TEXT-RECORD-S-INVALID _btrt-status
    _btrt-work-a 1+ BSKY-TEXT-RECORD-WORKSPACE-CLEAR
    BSKY-TEXT-RECORD-S-INVALID _btrt-status ;

: _BTRT-RUN  ( -- )
    0 _btrt-failed !
    0 _btrt-check !
    _btrt-setup-bytes
    _btrt-test-vocabulary
    _btrt-test-exact
    _btrt-test-escaping
    _btrt-test-bounds
    _btrt-test-alias-and-adjacency
    _btrt-test-protocol-maximum
    _btrt-test-independent-workspaces
    DEPTH 0= _btrt-assert
    _btrt-failed @ IF
        ." BSKY TEXT RECORD FAIL" CR
    ELSE
        ." BSKY TEXT RECORD PASS" CR
    THEN ;
