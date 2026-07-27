\ oauth2-pkce-test.f - Focused generic RFC 7636 S256 contracts

PROVIDED akashic-oauth2-pkce-test

VARIABLE _opkt-fails
VARIABLE _opkt-checks
VARIABLE _opkt-depth

: _opkt-assert  ( flag -- )
    1 _opkt-checks +!
    0= IF
        1 _opkt-fails +!
        ." OAUTH2 PKCE ASSERT " _opkt-checks @ . CR
    THEN ;

: _opkt-stack  ( -- )
    DEPTH DUP _opkt-depth @ <> IF
        ." OAUTH2 PKCE STACK "
        _opkt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _opkt-depth @ = _opkt-assert ;

: _opkt-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

: _opkt-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _opkt-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _opkt-vector  ( -- verifier verifier-u )
    S" dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk" ;

: _opkt-vector-challenge  ( -- challenge challenge-u )
    S" E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" ;

: _opkt-copy-vector  ( destination -- )
    >R _opkt-vector R> SWAP MOVE ;

CREATE _opkt-valid            160 ALLOT
CREATE _opkt-output           128 ALLOT
CREATE _opkt-output-b         128 ALLOT
CREATE _opkt-verifier-output  128 ALLOT
CREATE _opkt-raw               32 ALLOT
CREATE _opkt-canonical         43 ALLOT
CREATE _opkt-alias            256 ALLOT
CREATE _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE ALLOT
CREATE _opkt-work-b OAUTH2-PKCE-WORKSPACE-SIZE ALLOT
CREATE _opkt-work-copy OAUTH2-PKCE-WORKSPACE-SIZE ALLOT

: _opkt-work-a-zero?  ( -- flag )
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE _opkt-zero? ;

: _opkt-work-b-zero?  ( -- flag )
    _opkt-work-b OAUTH2-PKCE-WORKSPACE-SIZE _opkt-zero? ;

: _opkt-snapshot-work  ( -- )
    _opkt-work-a _opkt-work-copy
    OAUTH2-PKCE-WORKSPACE-SIZE MOVE ;

: _opkt-work-unchanged?  ( -- flag )
    _opkt-work-a _opkt-work-copy
    OAUTH2-PKCE-WORKSPACE-SIZE _opkt-bytes= ;

: _opkt-expect-verifier-reject  ( verifier verifier-u -- )
    _opkt-output 128 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-snapshot-work
    _opkt-output 128 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-VERIFIER = _opkt-assert
        0= _opkt-assert
    _opkt-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert ;

: _opkt-expect-char-reject  ( char -- )
    _opkt-valid 43 65 FILL
    _opkt-valid 17 + C!
    _opkt-valid 43 _opkt-expect-verifier-reject ;

: _opkt-expect-s256-alias
  ( verifier verifier-u challenge capacity workspace -- )
    OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-ALIAS = _opkt-assert
        0= _opkt-assert ;

: _opkt-expect-generate-alias
  ( verifier capacity challenge capacity workspace -- )
    OAUTH2-PKCE-GENERATE
        OAUTH2-PKCE-S-ALIAS = _opkt-assert
        0= _opkt-assert
        0= _opkt-assert ;

: _opkt-test-vocabulary  ( -- )
    OAUTH2-PKCE-VERIFIER-MIN 43 = _opkt-assert
    OAUTH2-PKCE-VERIFIER-MAX 128 = _opkt-assert
    OAUTH2-PKCE-GENERATED-VERIFIER-SIZE 43 = _opkt-assert
    OAUTH2-PKCE-CHALLENGE-SIZE 43 = _opkt-assert
    OAUTH2-PKCE-WORKSPACE-SIZE 219 = _opkt-assert
    OAUTH2-PKCE-S-CRYPTO
        OAUTH2-PKCE-STATUS-VALID? _opkt-assert
    OAUTH2-PKCE-S-INTERNAL
        OAUTH2-PKCE-STATUS-VALID? _opkt-assert
    OAUTH2-PKCE-S-INTERNAL 1+
        OAUTH2-PKCE-STATUS-VALID? 0= _opkt-assert

    _opkt-valid 160 65 FILL
    45  _opkt-valid      C!
    46  _opkt-valid 1+   C!
    95  _opkt-valid 2 +  C!
    126 _opkt-valid 3 +  C!
    48  _opkt-valid 4 +  C!
    90  _opkt-valid 5 +  C!
    122 _opkt-valid 6 +  C!
    _opkt-valid 43 OAUTH2-PKCE-VERIFIER-VALID? _opkt-assert
    _opkt-valid 128 OAUTH2-PKCE-VERIFIER-VALID? _opkt-assert
    _opkt-valid 42 OAUTH2-PKCE-VERIFIER-VALID? 0= _opkt-assert
    _opkt-valid 129 OAUTH2-PKCE-VERIFIER-VALID? 0= _opkt-assert
    0 43 OAUTH2-PKCE-VERIFIER-VALID? 0= _opkt-assert
    _opkt-stack ;

: _opkt-test-rfc7636-vector  ( -- )
    _opkt-output 128 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-vector
    _opkt-output 128 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-OK = _opkt-assert
        OAUTH2-PKCE-CHALLENGE-SIZE = _opkt-assert
    _opkt-output OAUTH2-PKCE-CHALLENGE-SIZE
    _opkt-vector-challenge COMPARE 0= _opkt-assert
    _opkt-output OAUTH2-PKCE-CHALLENGE-SIZE +
    128 OAUTH2-PKCE-CHALLENGE-SIZE - 0xA5
        _opkt-filled? _opkt-assert
    _opkt-work-a-zero? _opkt-assert
    _opkt-stack ;

: _opkt-test-strict-verifiers  ( -- )
    _opkt-valid 160 65 FILL
    _opkt-valid 42 _opkt-expect-verifier-reject
    _opkt-valid 129 _opkt-expect-verifier-reject

    \ RFC 7636 admits only ASCII ALPHA / DIGIT / "-" / "." / "_" / "~".
    43  _opkt-expect-char-reject       \ '+'
    47  _opkt-expect-char-reject       \ '/'
    61  _opkt-expect-char-reject       \ '='
    32  _opkt-expect-char-reject       \ space
    10  _opkt-expect-char-reject       \ line feed
    128 _opkt-expect-char-reject       \ non-ASCII

    \ Negative lengths are malformed geometry rather than verifier syntax.
    _opkt-output 128 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-snapshot-work
    _opkt-valid -1 _opkt-output 128 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-INVALID = _opkt-assert
        0= _opkt-assert
    _opkt-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert
    _opkt-stack ;

: _opkt-test-capacity  ( -- )
    _opkt-output 128 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-snapshot-work
    _opkt-vector
    _opkt-output 42 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-CAPACITY = _opkt-assert
        0= _opkt-assert
    _opkt-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    _opkt-vector
    _opkt-output 0 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-CAPACITY = _opkt-assert
        0= _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    _opkt-vector
    _opkt-output -1 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-INVALID = _opkt-assert
        0= _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    _opkt-vector
    0 43 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-INVALID = _opkt-assert
        0= _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    \ The exact 43-byte capacity is sufficient.
    _opkt-output 128 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x3C FILL
    _opkt-vector
    _opkt-output 43 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-OK = _opkt-assert
        43 = _opkt-assert
    _opkt-output 43 _opkt-vector-challenge
        COMPARE 0= _opkt-assert
    _opkt-work-a-zero? _opkt-assert

    \ Generation rejects either insufficient destination before entropy use.
    _opkt-verifier-output 128 0xA5 FILL
    _opkt-output 128 0x5A FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x3C FILL
    _opkt-snapshot-work
    _opkt-verifier-output 42
    _opkt-output 128 _opkt-work-a OAUTH2-PKCE-GENERATE
        OAUTH2-PKCE-S-CAPACITY = _opkt-assert
        0= _opkt-assert
        0= _opkt-assert
    _opkt-verifier-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-output 128 0x5A _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    _opkt-verifier-output 128
    _opkt-output 42 _opkt-work-a OAUTH2-PKCE-GENERATE
        OAUTH2-PKCE-S-CAPACITY = _opkt-assert
        0= _opkt-assert
        0= _opkt-assert
    _opkt-verifier-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-output 128 0x5A _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert
    _opkt-stack ;

: _opkt-test-alias-geometry  ( -- )
    _opkt-alias 256 0xA5 FILL
    _opkt-alias _opkt-copy-vector
    _opkt-alias 43 _opkt-alias 64 _opkt-work-a
        _opkt-expect-s256-alias
    _opkt-alias 43 _opkt-vector COMPARE 0= _opkt-assert

    \ Borrowed input and the workspace may not intersect.
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-work-a _opkt-copy-vector
    _opkt-snapshot-work
    _opkt-output 128 0xA5 FILL
    _opkt-work-a 43 _opkt-output 128 _opkt-work-a
        _opkt-expect-s256-alias
    _opkt-work-unchanged? _opkt-assert
    _opkt-output 128 0xA5 _opkt-filled? _opkt-assert

    \ The complete advertised capacity is disjoint from the wiped workspace.
    _opkt-snapshot-work
    _opkt-vector
    _opkt-work-a 64 _opkt-work-a _opkt-expect-s256-alias
    _opkt-work-unchanged? _opkt-assert

    _opkt-verifier-output 128 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-snapshot-work
    _opkt-verifier-output 128
    _opkt-verifier-output 128 _opkt-work-a
        _opkt-expect-generate-alias
    _opkt-verifier-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-snapshot-work
    _opkt-output 128 0xA5 FILL
    _opkt-work-a 128
    _opkt-output 128 _opkt-work-a
        _opkt-expect-generate-alias
    _opkt-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-snapshot-work
    _opkt-verifier-output 128 0xA5 FILL
    _opkt-verifier-output 128
    _opkt-work-a 128 _opkt-work-a
        _opkt-expect-generate-alias
    _opkt-verifier-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-work-unchanged? _opkt-assert

    \ Exact adjacency is disjoint even when the verifier lives inside unused
    \ destination capacity.
    _opkt-alias 256 0xA5 FILL
    _opkt-alias 43 + _opkt-copy-vector
    _opkt-alias 43 + 43
    _opkt-alias 86 _opkt-work-a OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-OK = _opkt-assert
        43 = _opkt-assert
    _opkt-alias 43 _opkt-vector-challenge
        COMPARE 0= _opkt-assert
    _opkt-alias 43 + 43 _opkt-vector
        COMPARE 0= _opkt-assert
    _opkt-work-a-zero? _opkt-assert

    \ Generation likewise admits adjacent exact publications even though
    \ the first output advertises capacity across the second result.
    _opkt-alias 128 0xA5 FILL
    _opkt-alias 86
    _opkt-alias 43 + 43 _opkt-work-a OAUTH2-PKCE-GENERATE
        OAUTH2-PKCE-S-OK = _opkt-assert
        43 = _opkt-assert
        43 = _opkt-assert
    _opkt-alias 43 OAUTH2-PKCE-VERIFIER-VALID? _opkt-assert
    _opkt-work-a-zero? _opkt-assert
    _opkt-stack ;

: _opkt-test-entropy-output  ( -- )
    _opkt-verifier-output 128 0xA5 FILL
    _opkt-output 128 0x5A FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x3C FILL
    _opkt-verifier-output 43
    _opkt-output 43 _opkt-work-a OAUTH2-PKCE-GENERATE
        OAUTH2-PKCE-S-OK = _opkt-assert
        OAUTH2-PKCE-CHALLENGE-SIZE = _opkt-assert
        OAUTH2-PKCE-GENERATED-VERIFIER-SIZE = _opkt-assert
    _opkt-verifier-output 43
        OAUTH2-PKCE-VERIFIER-VALID? _opkt-assert

    \ A generated verifier is the canonical unpadded Base64url encoding of
    \ exactly 32 entropy bytes.
    _opkt-verifier-output 43 _opkt-raw 32 JOSE-B64URL-DECODE
        JOSE-B64URL-S-OK = _opkt-assert
        32 = _opkt-assert
    _opkt-raw 32 _opkt-canonical 43 JOSE-B64URL-ENCODE
        JOSE-B64URL-S-OK = _opkt-assert
        43 = _opkt-assert
    _opkt-canonical _opkt-verifier-output 43
        _opkt-bytes= _opkt-assert

    \ A second independent hardware-entropy acquisition must not reproduce the
    \ first verifier.  The collision probability is 2^-256; this also guards
    \ against accidentally encoding a fixed staging buffer instead of the
    \ bytes returned by ENTROPY-FILL.
    _opkt-valid 160 0xA5 FILL
    _opkt-canonical 43 0x5A FILL
    _opkt-valid 43
    _opkt-canonical 43 _opkt-work-b OAUTH2-PKCE-GENERATE
        OAUTH2-PKCE-S-OK = _opkt-assert
        43 = _opkt-assert
        43 = _opkt-assert
    _opkt-valid 43 OAUTH2-PKCE-VERIFIER-VALID? _opkt-assert
    _opkt-valid _opkt-verifier-output 43
        _opkt-bytes= 0= _opkt-assert
    _opkt-work-b-zero? _opkt-assert

    \ Independently recompute S256 from the published verifier.
    _opkt-output-b 128 0xA5 FILL
    _opkt-verifier-output 43
    _opkt-output-b 128 _opkt-work-b OAUTH2-PKCE-S256
        OAUTH2-PKCE-S-OK = _opkt-assert
        43 = _opkt-assert
    _opkt-output-b _opkt-output 43 _opkt-bytes= _opkt-assert

    _opkt-verifier-output 43 + 85 0xA5
        _opkt-filled? _opkt-assert
    _opkt-output 43 + 85 0x5A
        _opkt-filled? _opkt-assert
    _opkt-work-a-zero? _opkt-assert
    _opkt-work-b-zero? _opkt-assert
    _opkt-stack ;

: _opkt-test-entropy-unavailable  ( -- )
    \ This entry point runs only in the host-disabled TRNG profile.
    ENTROPY-READY? 0= _opkt-assert
    _opkt-verifier-output 128 0xA5 FILL
    _opkt-output 128 0x5A FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x3C FILL
    _opkt-verifier-output 128
    _opkt-output 128 _opkt-work-a OAUTH2-PKCE-GENERATE
        OAUTH2-PKCE-S-ENTROPY = _opkt-assert
        0= _opkt-assert
        0= _opkt-assert
    _opkt-verifier-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-output 128 0x5A _opkt-filled? _opkt-assert
    _opkt-work-a-zero? _opkt-assert
    _opkt-stack ;

: _opkt-throw-result
  ( verifier verifier-u challenge capacity workspace -- written status )
    -863 THROW ;

: _opkt-throw-generate
  \ ( verifier capacity challenge capacity workspace
  \   -- verifier-written challenge-written status )
    -864 THROW ;

: _opkt-test-wipe-and-throw  ( -- )
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-CLEAR
        OAUTH2-PKCE-S-OK = _opkt-assert
    _opkt-work-a-zero? _opkt-assert
    0 OAUTH2-PKCE-WORKSPACE-CLEAR
        OAUTH2-PKCE-S-INVALID = _opkt-assert

    _opkt-output 128 0xA5 FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x5A FILL
    _opkt-vector
    _opkt-output 128 _opkt-work-a
    ['] _opkt-throw-result _OPK-CALL-RESULT
        OAUTH2-PKCE-S-INTERNAL = _opkt-assert
        0= _opkt-assert
    _opkt-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-work-a-zero? _opkt-assert

    _opkt-verifier-output 128 0xA5 FILL
    _opkt-output 128 0x5A FILL
    _opkt-work-a OAUTH2-PKCE-WORKSPACE-SIZE 0x3C FILL
    _opkt-verifier-output 128
    _opkt-output 128 _opkt-work-a
    ['] _opkt-throw-generate _OPK-CALL-GENERATE
        OAUTH2-PKCE-S-INTERNAL = _opkt-assert
        0= _opkt-assert
        0= _opkt-assert
    _opkt-verifier-output 128 0xA5 _opkt-filled? _opkt-assert
    _opkt-output 128 0x5A _opkt-filled? _opkt-assert
    _opkt-work-a-zero? _opkt-assert
    _opkt-stack ;

: _OPKT-RUN  ( -- )
    0 _opkt-fails !
    0 _opkt-checks !
    DEPTH _opkt-depth !

    _opkt-test-vocabulary
    _opkt-test-rfc7636-vector
    _opkt-test-strict-verifiers
    _opkt-test-capacity
    _opkt-test-alias-geometry
    _opkt-test-entropy-output
    _opkt-test-wipe-and-throw

    _opkt-stack
    _opkt-fails @ 0= IF
        ." OAUTH2 PKCE PASS " _opkt-checks @ . CR
    ELSE
        ." OAUTH2 PKCE FAIL " _opkt-fails @ .
        ." / " _opkt-checks @ . CR
    THEN ;

: _OPKT-RUN-ENTROPY-FAIL  ( -- )
    0 _opkt-fails !
    0 _opkt-checks !
    DEPTH _opkt-depth !
    _opkt-test-entropy-unavailable
    _opkt-stack
    _opkt-fails @ 0= IF
        ." OAUTH2 PKCE ENTROPY PASS " _opkt-checks @ . CR
    ELSE
        ." OAUTH2 PKCE ENTROPY FAIL " _opkt-fails @ .
        ." / " _opkt-checks @ . CR
    THEN ;
