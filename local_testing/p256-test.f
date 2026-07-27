\ p256-test.f - Focused generic NIST P-256 point/key contracts

PROVIDED akashic-p256-test

VARIABLE _p256t-fails
VARIABLE _p256t-checks
VARIABLE _p256t-depth

: _p256t-assert  ( flag -- )
    1 _p256t-checks +!
    0= IF
        1 _p256t-fails +!
        ." P256 ASSERT " _p256t-checks @ . CR
    THEN ;

: _p256t-stack  ( -- )
    DEPTH _p256t-depth @ = _p256t-assert ;

: _p256t-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

: _p256t-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _p256t-be-lt?  ( first second -- flag )
    32 0 DO
        OVER I + C@
        OVER I + C@
        2DUP < IF
            2DROP 2DROP -1 UNLOOP EXIT
        THEN
        > IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;

CREATE _p256t-private-one 32 ALLOT
CREATE _p256t-private-zero 32 ALLOT
CREATE _p256t-private-generated 32 ALLOT
CREATE _p256t-scalar-one-q 32 ALLOT
CREATE _p256t-scalar-zero-q 32 ALLOT

CREATE _p256t-private-rfc6979
    0xC9 C, 0xAF C, 0xA9 C, 0xD8 C, 0x45 C, 0xBA C, 0x75 C, 0x16 C,
    0x6B C, 0x5C C, 0x21 C, 0x57 C, 0x67 C, 0xB1 C, 0xD6 C, 0x93 C,
    0x4E C, 0x50 C, 0xC3 C, 0xDB C, 0x36 C, 0xE8 C, 0x9B C, 0x12 C,
    0x7B C, 0x8A C, 0x62 C, 0x2B C, 0x12 C, 0x0F C, 0x67 C, 0x21 C,

CREATE _p256t-private-n
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,
    0xBC C, 0xE6 C, 0xFA C, 0xAD C, 0xA7 C, 0x17 C, 0x9E C, 0x84 C,
    0xF3 C, 0xB9 C, 0xCA C, 0xC2 C, 0xFC C, 0x63 C, 0x25 C, 0x51 C,

CREATE _p256t-public-g
    0x04 C,
    0x6B C, 0x17 C, 0xD1 C, 0xF2 C, 0xE1 C, 0x2C C, 0x42 C, 0x47 C,
    0xF8 C, 0xBC C, 0xE6 C, 0xE5 C, 0x63 C, 0xA4 C, 0x40 C, 0xF2 C,
    0x77 C, 0x03 C, 0x7D C, 0x81 C, 0x2D C, 0xEB C, 0x33 C, 0xA0 C,
    0xF4 C, 0xA1 C, 0x39 C, 0x45 C, 0xD8 C, 0x98 C, 0xC2 C, 0x96 C,
    0x4F C, 0xE3 C, 0x42 C, 0xE2 C, 0xFE C, 0x1A C, 0x7F C, 0x9B C,
    0x8E C, 0xE7 C, 0xEB C, 0x4A C, 0x7C C, 0x0F C, 0x9E C, 0x16 C,
    0x2B C, 0xCE C, 0x33 C, 0x57 C, 0x6B C, 0x31 C, 0x5E C, 0xCE C,
    0xCB C, 0xB6 C, 0x40 C, 0x68 C, 0x37 C, 0xBF C, 0x51 C, 0xF5 C,

CREATE _p256t-public-2g
    0x04 C,
    0x7C C, 0xF2 C, 0x7B C, 0x18 C, 0x8D C, 0x03 C, 0x4F C, 0x7E C,
    0x8A C, 0x52 C, 0x38 C, 0x03 C, 0x04 C, 0xB5 C, 0x1A C, 0xC3 C,
    0xC0 C, 0x89 C, 0x69 C, 0xE2 C, 0x77 C, 0xF2 C, 0x1B C, 0x35 C,
    0xA6 C, 0x0B C, 0x48 C, 0xFC C, 0x47 C, 0x66 C, 0x99 C, 0x78 C,
    0x07 C, 0x77 C, 0x55 C, 0x10 C, 0xDB C, 0x8E C, 0xD0 C, 0x40 C,
    0x29 C, 0x3D C, 0x9A C, 0xC6 C, 0x9F C, 0x74 C, 0x30 C, 0xDB C,
    0xBA C, 0x7D C, 0xAD C, 0xE6 C, 0x3C C, 0xE9 C, 0x82 C, 0x29 C,
    0x9E C, 0x04 C, 0xB7 C, 0x9D C, 0x22 C, 0x78 C, 0x73 C, 0xD1 C,

CREATE _p256t-public-rfc6979
    0x04 C,
    0x60 C, 0xFE C, 0xD4 C, 0xBA C, 0x25 C, 0x5A C, 0x9D C, 0x31 C,
    0xC9 C, 0x61 C, 0xEB C, 0x74 C, 0xC6 C, 0x35 C, 0x6D C, 0x68 C,
    0xC0 C, 0x49 C, 0xB8 C, 0x92 C, 0x3B C, 0x61 C, 0xFA C, 0x6C C,
    0xE6 C, 0x69 C, 0x62 C, 0x2E C, 0x60 C, 0xF2 C, 0x9F C, 0xB6 C,
    0x79 C, 0x03 C, 0xFE C, 0x10 C, 0x08 C, 0xB8 C, 0xBC C, 0x99 C,
    0xA4 C, 0x1A C, 0xE9 C, 0xE9 C, 0x56 C, 0x28 C, 0xBC C, 0x64 C,
    0xF2 C, 0xF1 C, 0xB2 C, 0x0C C, 0x2D C, 0x7E C, 0x9F C, 0x51 C,
    0x77 C, 0xA3 C, 0xC2 C, 0x94 C, 0xD4 C, 0x46 C, 0x22 C, 0x99 C,

CREATE _p256t-field-p-be
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0x00 C, 0x00 C, 0x00 C, 0x01 C,
    0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,
    0x00 C, 0x00 C, 0x00 C, 0x00 C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,

CREATE _p256t-public P256-PUBLIC-SIZE ALLOT
CREATE _p256t-public-bad P256-PUBLIC-SIZE ALLOT
CREATE _p256t-snapshot P256-PUBLIC-SIZE ALLOT
CREATE _p256t-workspace P256-WORKSPACE-SIZE ALLOT
CREATE _p256t-workspace-snapshot P256-WORKSPACE-SIZE ALLOT

: _p256t-init  ( -- )
    _p256t-private-one P256-PRIVATE-SIZE 0 FILL
    _p256t-private-zero P256-PRIVATE-SIZE 0 FILL
    _p256t-scalar-one-q P256-SCALAR-SIZE 0 FILL
    _p256t-scalar-zero-q P256-SCALAR-SIZE 0 FILL
    1 _p256t-private-one 31 + C!
    1 _p256t-scalar-one-q 31 + C! ;

: _p256t-workspace-zero?  ( -- flag )
    _p256t-workspace P256-WORKSPACE-SIZE _p256t-zero? ;

: _p256t-output-snapshot  ( -- )
    _p256t-public _p256t-snapshot P256-PUBLIC-SIZE MOVE ;

: _p256t-output-unchanged?  ( -- flag )
    _p256t-public _p256t-snapshot P256-PUBLIC-SIZE _p256t-bytes= ;

: _p256t-private-generated-in-range?  ( -- flag )
    _p256t-private-generated P256-PRIVATE-SIZE _p256t-zero? 0=
    _p256t-private-generated _p256t-private-n _p256t-be-lt?
    AND ;

: _p256t-workspace-snapshot!  ( -- )
    _p256t-workspace _p256t-workspace-snapshot
        P256-WORKSPACE-SIZE MOVE ;

: _p256t-workspace-unchanged?  ( -- flag )
    _p256t-workspace _p256t-workspace-snapshot
        P256-WORKSPACE-SIZE _p256t-bytes= ;

: _p256t-test-vocabulary  ( -- )
    P256-SCALAR-SIZE 32 = _p256t-assert
    P256-PRIVATE-SIZE 32 = _p256t-assert
    P256-PUBLIC-SIZE 65 = _p256t-assert
    P256-WORKSPACE-SIZE 1152 = _p256t-assert
    P256-S-INTERNAL P256-STATUS-VALID? _p256t-assert
    P256-S-RANGE P256-STATUS-VALID? _p256t-assert
    P256-S-PROTECTED P256-STATUS-VALID? _p256t-assert
    P256-S-PLATFORM P256-STATUS-VALID? _p256t-assert
    P256-S-INTERNAL 1+ P256-STATUS-VALID? 0= _p256t-assert

    CALLER-SPAN-S-OK _P256-CALLER>STATUS
        P256-S-OK = _p256t-assert
    CALLER-SPAN-S-RANGE _P256-CALLER>STATUS
        P256-S-RANGE = _p256t-assert
    CALLER-SPAN-S-PROTECTED _P256-CALLER>STATUS
        P256-S-PROTECTED = _p256t-assert
    CALLER-SPAN-S-PLATFORM _P256-CALLER>STATUS
        P256-S-PLATFORM = _p256t-assert
    99 _P256-CALLER>STATUS
        P256-S-PLATFORM = _p256t-assert

    _p256t-private-one P256-PRIVATE-SIZE
        _P256-FIXED-SPAN-STATUS P256-S-OK = _p256t-assert
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - P256-PRIVATE-SIZE
        _P256-FIXED-SPAN-STATUS P256-S-RANGE = _p256t-assert
    1 P256-PRIVATE-SIZE
        _P256-FIXED-SPAN-STATUS P256-S-PROTECTED = _p256t-assert
    _FLD-TMP 1 P256-RESERVED-OVERLAP? _p256t-assert
    _P256-GX 1 P256-RESERVED-OVERLAP? _p256t-assert
    _p256t-private-one P256-PRIVATE-SIZE
        P256-RESERVED-OVERLAP? 0= _p256t-assert
    _p256t-stack ;

: _p256t-test-private-vectors  ( -- )
    \ One checked hardware key generation replaces the d=1 derivation KAT.
    _p256t-private-generated P256-PRIVATE-SIZE 0xA5 FILL
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-private-generated _p256t-public _p256t-workspace
        P256-KEYGEN
        P256-S-OK = _p256t-assert
    _p256t-private-generated-in-range? _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    \ The generated SEC 1 point must independently pass canonical validation.
    _p256t-public _p256t-workspace P256-PUBLIC-VALID?
        P256-S-OK = _p256t-assert
        _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    \ RFC 6979 A.2.5 supplies a nontrivial scalar and published public key.
    _p256t-private-rfc6979 _p256t-public _p256t-workspace
        P256-PUBLIC-FROM-PRIVATE
        P256-S-OK = _p256t-assert
    _p256t-public _p256t-public-rfc6979 P256-PUBLIC-SIZE
        _p256t-bytes= _p256t-assert
    _p256t-workspace-zero? _p256t-assert
    _p256t-stack ;

: _p256t-test-private-rejections  ( -- )
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-output-snapshot
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-private-zero _p256t-public _p256t-workspace
        P256-PUBLIC-FROM-PRIVATE
        P256-S-PRIVATE = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-private-n _p256t-public _p256t-workspace
        P256-PUBLIC-FROM-PRIVATE
        P256-S-PRIVATE = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-zero? _p256t-assert
    _p256t-stack ;

: _p256t-test-public-validation  ( -- )
    _p256t-public-g _p256t-workspace P256-PUBLIC-VALID?
        P256-S-OK = _p256t-assert
        _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    _p256t-public-2g _p256t-workspace P256-PUBLIC-VALID?
        P256-S-OK = _p256t-assert
        _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    _p256t-public-g _p256t-public P256-PUBLIC-SIZE MOVE
    0x05 _p256t-public C!
    _p256t-public _p256t-workspace P256-PUBLIC-VALID?
        P256-S-OK = _p256t-assert
        0= _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    _p256t-public-g _p256t-public P256-PUBLIC-SIZE MOVE
    _p256t-public 64 + DUP C@ 1 XOR SWAP C!
    _p256t-public _p256t-workspace P256-PUBLIC-VALID?
        P256-S-OK = _p256t-assert
        0= _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    \ SEC 1 coordinates are integers in [0,p); p itself is noncanonical.
    _p256t-public-g _p256t-public P256-PUBLIC-SIZE MOVE
    _p256t-field-p-be _p256t-public 1+ 32 MOVE
    _p256t-public _p256t-workspace P256-PUBLIC-VALID?
        P256-S-OK = _p256t-assert
        0= _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    _p256t-public-g _p256t-public P256-PUBLIC-SIZE MOVE
    _p256t-field-p-be _p256t-public 33 + 32 MOVE
    _p256t-public _p256t-workspace P256-PUBLIC-VALID?
        P256-S-OK = _p256t-assert
        0= _p256t-assert
    _p256t-workspace-zero? _p256t-assert
    _p256t-stack ;

: _p256t-expect-lincomb
  ( scalar-g scalar-q public-q expected -- )
    >R
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-public _p256t-workspace
    P256-PUBLIC-SCALAR-LINCOMB
        P256-S-OK = _p256t-assert
    _p256t-public R@ P256-PUBLIC-SIZE
        _p256t-bytes= _p256t-assert
    _p256t-workspace-zero? _p256t-assert
    R> DROP ;

: _p256t-expect-lincomb-rejection
  ( scalar-g scalar-q public-q expected-status -- )
    >R
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-output-snapshot
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-public _p256t-workspace
    P256-PUBLIC-SCALAR-LINCOMB
        R> = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-zero? _p256t-assert ;

: _p256t-test-lincomb  ( -- )
    \ 1*G + 1*G = 2*G.  The equal scalars occupy distinct input spans.
    _p256t-private-one _p256t-scalar-one-q
        _p256t-public-g _p256t-public-2g
        _p256t-expect-lincomb

    \ 0*G + 1*Q = Q for a non-generator Q.
    _p256t-private-zero _p256t-scalar-one-q
        _p256t-public-2g _p256t-public-2g
        _p256t-expect-lincomb

    \ Zero plus zero is the projective identity and has no SEC 1 encoding.
    _p256t-private-zero _p256t-scalar-zero-q
        _p256t-public-g P256-S-IDENTITY
        _p256t-expect-lincomb-rejection

    \ n is outside the admitted public-scalar range.
    _p256t-private-n _p256t-scalar-one-q
        _p256t-public-g P256-S-SCALAR
        _p256t-expect-lincomb-rejection

    \ A malformed Q is distinguished from an ordinary identity result.
    _p256t-public-g _p256t-public-bad P256-PUBLIC-SIZE MOVE
    0x05 _p256t-public-bad C!
    _p256t-private-zero _p256t-scalar-one-q
        _p256t-public-bad P256-S-PUBLIC
        _p256t-expect-lincomb-rejection
    _p256t-stack ;

: _p256t-test-lincomb-aliases  ( -- )
    \ The two scalar operands may not share storage.
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-output-snapshot
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-workspace-snapshot!
    _p256t-private-one _p256t-private-one _p256t-public-g
        _p256t-public _p256t-workspace
        P256-PUBLIC-SCALAR-LINCOMB
        P256-S-ALIAS = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    \ Q and the result may not be the same caller span.
    _p256t-public-g _p256t-public P256-PUBLIC-SIZE MOVE
    _p256t-output-snapshot
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-workspace-snapshot!
    _p256t-private-zero _p256t-scalar-one-q _p256t-public
        _p256t-public _p256t-workspace
        P256-PUBLIC-SCALAR-LINCOMB
        P256-S-ALIAS = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    \ A result inside the workspace is rejected before either span changes.
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-workspace-snapshot!
    _p256t-private-zero _p256t-scalar-one-q _p256t-public-g
        _p256t-workspace _p256t-workspace
        P256-PUBLIC-SCALAR-LINCOMB
        P256-S-ALIAS = _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert
    _p256t-stack ;

: _p256t-test-geometry  ( -- )
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-output-snapshot
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-workspace-snapshot!
    0 _p256t-public _p256t-workspace P256-PUBLIC-FROM-PRIVATE
        P256-S-RANGE = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    EXT-MEM-BASE EXT-MEM-SIZE + 1 -
        _p256t-public _p256t-workspace P256-PUBLIC-FROM-PRIVATE
        P256-S-RANGE = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    1 _p256t-public _p256t-workspace P256-PUBLIC-FROM-PRIVATE
        P256-S-PROTECTED = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    \ P-256's private tables and every lower Field/crypto-ACC region are
    \ rejected before the caller workspace is initialized.
    _P256-GX _p256t-public _p256t-workspace P256-PUBLIC-FROM-PRIVATE
        P256-S-ALIAS = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    _FLD-TMP _p256t-public _p256t-workspace
        P256-PUBLIC-FROM-PRIVATE
        P256-S-ALIAS = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    _p256t-workspace-snapshot!
    _p256t-private-one _p256t-workspace _p256t-workspace
        P256-PUBLIC-FROM-PRIVATE
        P256-S-ALIAS = _p256t-assert
    _p256t-workspace-unchanged? _p256t-assert

    _p256t-public-g _p256t-public-g P256-PUBLIC-VALID?
        P256-S-ALIAS = _p256t-assert
        0= _p256t-assert

    0 P256-WORKSPACE-CLEAR P256-S-RANGE = _p256t-assert
    1 P256-WORKSPACE-CLEAR P256-S-PROTECTED = _p256t-assert
    _FLD-TMP P256-WORKSPACE-CLEAR P256-S-ALIAS = _p256t-assert
    _P256-N P256-WORKSPACE-CLEAR P256-S-ALIAS = _p256t-assert

    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    _p256t-workspace P256-WORKSPACE-CLEAR
        P256-S-OK = _p256t-assert
    _p256t-workspace-zero? _p256t-assert
    _p256t-stack ;

: _p256t-throw3  ( first second workspace -- status )
    -781 THROW ;

: _p256t-throw2  ( first workspace -- valid? status )
    -782 THROW ;

: _p256t-throw5
  ( first second third fourth workspace -- status )
    -783 THROW ;

: _p256t-throw-wipe  ( workspace -- )
    0 OVER C!
    -784 THROW ;

: _p256t-publish-throw3  ( first second workspace -- status )
    >R NIP
    0xC3 SWAP C!
    R> DROP
    -785 THROW ;

: _p256t-run-throw3  ( -- )
    _p256t-private-one _p256t-public _p256t-workspace
        ['] _p256t-throw3 _P256-CALL3-STATUS DROP ;

: _p256t-run-throw2  ( -- )
    _p256t-public-g _p256t-workspace
        ['] _p256t-throw2 _P256-CALL2-RESULT 2DROP ;

: _p256t-run-throw5  ( -- )
    _p256t-private-one _p256t-private-one _p256t-public-g
        _p256t-public _p256t-workspace
        ['] _p256t-throw5 _P256-CALL5-STATUS DROP ;

: _p256t-run-publish-throw3  ( -- )
    _p256t-private-one _p256t-public _p256t-workspace
        ['] _p256t-publish-throw3 _P256-CALL3-STATUS DROP ;

: _p256t-run-cleanup-status-throw  ( -- )
    P256-S-PRIVATE _p256t-workspace ['] _p256t-throw-wipe
        _P256-CLEANUP-STATUS DROP ;

: _p256t-run-cleanup-result-throw  ( -- )
    -1 P256-S-OK _p256t-workspace ['] _p256t-throw-wipe
        _P256-CLEANUP-RESULT 2DROP ;

: _p256t-test-exception-transparency  ( -- )
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-output-snapshot
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    ['] _p256t-run-throw3 CATCH -781 = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    ['] _p256t-run-throw2 CATCH -782 = _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-output-snapshot
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    ['] _p256t-run-throw5 CATCH -783 = _p256t-assert
    _p256t-output-unchanged? _p256t-assert
    _p256t-workspace-zero? _p256t-assert

    \ A fault after publication starts is rethrown after cleanup.  The
    \ caller sees the exact exception and can observe that publication was
    \ partial; no ordinary status promises that the output stayed unchanged.
    _p256t-public P256-PUBLIC-SIZE 0xA5 FILL
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    ['] _p256t-run-publish-throw3 CATCH -785 = _p256t-assert
    _p256t-public C@ 0xC3 = _p256t-assert
    _p256t-public 1+ C@ 0xA5 = _p256t-assert
    _p256t-workspace-zero? _p256t-assert
    _p256t-stack ;

: _p256t-test-cleanup-propagation  ( -- )
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    ['] _p256t-run-cleanup-status-throw CATCH
        -784 = _p256t-assert
    _p256t-workspace C@ 0= _p256t-assert
    _p256t-workspace 1+ C@ 0x5A = _p256t-assert

    \ Result-shape cleanup follows the same exception-transparent contract.
    _p256t-workspace P256-WORKSPACE-SIZE 0x5A FILL
    ['] _p256t-run-cleanup-result-throw CATCH
        -784 = _p256t-assert
    _p256t-workspace C@ 0= _p256t-assert
    _p256t-workspace 1+ C@ 0x5A = _p256t-assert
    _p256t-stack ;

: _P256T-RUN  ( -- )
    DEPTH _p256t-depth !
    0 _p256t-fails !
    0 _p256t-checks !
    _p256t-init
    _p256t-test-vocabulary
    _p256t-test-private-vectors
    _p256t-test-private-rejections
    _p256t-test-public-validation
    _p256t-test-lincomb
    _p256t-test-lincomb-aliases
    _p256t-test-geometry
    _p256t-test-exception-transparency
    _p256t-test-cleanup-propagation
    _p256t-fails @ 0= IF
        ." P256 PASS " _p256t-checks @ . CR
    ELSE
        ." P256 FAIL " _p256t-fails @ .
        ." / " _p256t-checks @ . CR
    THEN ;
