\ jose-json-object-test.f - Strict caller-owned JSON object contracts

PROVIDED akashic-jjo-contracts

VARIABLE _jjot-fails
VARIABLE _jjot-checks
VARIABLE _jjot-depth

: _jjot-assert  ( flag -- )
    1 _jjot-checks +!
    0= IF
        1 _jjot-fails +!
        ." JOSE JSON OBJECT ASSERT " _jjot-checks @ . CR
    THEN ;

: _jjot-stack  ( -- )
    DEPTH DUP _jjot-depth @ <> IF
        ." JOSE JSON OBJECT STACK "
        _jjot-depth @ . ." -> " DUP . CR .S CR
    THEN
    _jjot-depth @ = _jjot-assert ;

: _jjot-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _jjot-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

JOSE-JSON-MAX-MEMBERS JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." JOSE JSON test descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _JJOT-DESCRIPTOR-SIZE

16 JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." JOSE JSON test active descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _JJOT-ACTIVE-DESCRIPTOR-SIZE

CREATE _jjot-input
    JOSE-JSON-MAX-STRING-BYTES 32 + ALLOT
CREATE _jjot-descriptor  _JJOT-DESCRIPTOR-SIZE ALLOT
CREATE _jjot-names       JOSE-JSON-MAX-STRING-BYTES ALLOT
CREATE _jjot-work        JOSE-JSON-OBJECT-WORKSPACE-SIZE ALLOT
CREATE _jjot-string-work JOSE-JSON-STRING-WORKSPACE-SIZE ALLOT
CREATE _jjot-output      128 ALLOT

VARIABLE _jjot-input-u
VARIABLE _jjot-copy-u
VARIABLE _jjot-member-cap
VARIABLE _jjot-names-cap
VARIABLE _jjot-name-o
VARIABLE _jjot-name-u
VARIABLE _jjot-value-o
VARIABLE _jjot-value-u
VARIABLE _jjot-type
VARIABLE _jjot-decoded-u

: _jjot-reset  ( -- )
    0 _jjot-input-u ! ;

: _jjot-char  ( byte -- )
    _jjot-input _jjot-input-u @ + C!
    1 _jjot-input-u +! ;

: _jjot-text  ( address length -- )
    DUP _jjot-copy-u !
    _jjot-input _jjot-input-u @ + SWAP MOVE
    _jjot-copy-u @ _jjot-input-u +! ;

: _jjot-quote  ( -- ) 34 _jjot-char ;
: _jjot-colon  ( -- ) 58 _jjot-char ;
: _jjot-comma  ( -- ) 44 _jjot-char ;
: _jjot-lbrace ( -- ) 123 _jjot-char ;
: _jjot-rbrace ( -- ) 125 _jjot-char ;
: _jjot-lbrack ( -- ) 91 _jjot-char ;
: _jjot-rbrack ( -- ) 93 _jjot-char ;
: _jjot-slash  ( -- ) 92 _jjot-char ;

: _jjot-key  ( address length -- )
    _jjot-quote _jjot-text _jjot-quote _jjot-colon ;

: _jjot-build-main  ( -- )
    _jjot-reset
    _jjot-lbrace
    S" alg" _jjot-key
        _jjot-quote S" ES256" _jjot-text _jjot-quote
    _jjot-comma
    S" ok" _jjot-key S" true" _jjot-text
    _jjot-comma
    S" n" _jjot-key S" -1.25e+2" _jjot-text
    _jjot-comma
    S" obj" _jjot-key
        _jjot-lbrace
        S" x" _jjot-key
            _jjot-lbrack S" null" _jjot-text
            _jjot-comma S" false" _jjot-text _jjot-rbrack
        _jjot-rbrace
    _jjot-comma
    S" emoji" _jjot-key
        _jjot-quote
        _jjot-slash S" uD83D" _jjot-text
        _jjot-slash S" uDE00" _jjot-text
        _jjot-quote
    _jjot-rbrace ;

: _jjot-build-root-duplicate  ( -- )
    _jjot-reset _jjot-lbrace
    S" a" _jjot-key 49 _jjot-char
    _jjot-comma
    _jjot-quote _jjot-slash S" u0061" _jjot-text
    _jjot-quote _jjot-colon 50 _jjot-char
    _jjot-rbrace ;

: _jjot-build-utf8-duplicate  ( -- )
    _jjot-reset _jjot-lbrace
    _jjot-quote 0xC3 _jjot-char 0xA9 _jjot-char
    _jjot-quote _jjot-colon 49 _jjot-char
    _jjot-comma
    _jjot-quote _jjot-slash S" u00e9" _jjot-text
    _jjot-quote _jjot-colon 50 _jjot-char
    _jjot-rbrace ;

: _jjot-build-nested-duplicate  ( -- )
    _jjot-reset _jjot-lbrace
    S" outer" _jjot-key _jjot-lbrace
    S" x" _jjot-key 49 _jjot-char
    _jjot-comma
    _jjot-quote _jjot-slash S" u0078" _jjot-text
    _jjot-quote _jjot-colon 50 _jjot-char
    _jjot-rbrace _jjot-rbrace ;

: _jjot-build-lone-high  ( -- )
    _jjot-reset _jjot-lbrace
    S" x" _jjot-key _jjot-quote
    _jjot-slash S" uD800" _jjot-text
    _jjot-quote _jjot-rbrace ;

: _jjot-build-invalid-utf8  ( -- )
    _jjot-reset _jjot-lbrace
    S" x" _jjot-key _jjot-quote
    0xC0 _jjot-char 0xAF _jjot-char
    _jjot-quote _jjot-rbrace ;

: _jjot-build-leading-zero  ( -- )
    _jjot-reset _jjot-lbrace
    S" x" _jjot-key S" 01" _jjot-text
    _jjot-rbrace ;

: _jjot-build-trailing  ( -- )
    _jjot-reset _jjot-lbrace
    S" x" _jjot-key 49 _jjot-char
    _jjot-rbrace 120 _jjot-char ;

: _jjot-build-array-root  ( -- )
    _jjot-reset _jjot-lbrack _jjot-rbrack ;

: _jjot-build-too-deep  ( -- )
    _jjot-reset _jjot-lbrace
    S" x" _jjot-key
    32 0 DO _jjot-lbrack LOOP
    S" null" _jjot-text
    32 0 DO _jjot-rbrack LOOP
    _jjot-rbrace ;

: _jjot-build-empty  ( -- )
    _jjot-reset _jjot-lbrace _jjot-rbrace ;

: _jjot-build-string-token  ( -- )
    _jjot-reset _jjot-quote
    _jjot-slash S" u0061" _jjot-text
    _jjot-slash S" uD83D" _jjot-text
    _jjot-slash S" uDE00" _jjot-text
    _jjot-slash 110 _jjot-char
    _jjot-quote ;

: _jjot-build-value-string  ( decoded-u -- )
    _jjot-reset _jjot-lbrace
    S" x" _jjot-key _jjot-quote
    0 ?DO 97 _jjot-char LOOP
    _jjot-quote _jjot-rbrace ;

: _jjot-parse  ( member-capacity names-capacity -- status )
    _jjot-names-cap ! _jjot-member-cap !
    _jjot-input _jjot-input-u @
    _jjot-descriptor _jjot-member-cap @
    _jjot-names _jjot-names-cap @
    _jjot-work JOSE-JSON-OBJECT-PARSE ;

: _jjot-member  ( index -- )
    _jjot-descriptor JOSE-JSON-OBJECT-MEMBER@
    JOSE-JSON-S-OK = _jjot-assert
    _jjot-type !
    _jjot-value-u !
    _jjot-value-o !
    _jjot-name-u !
    _jjot-name-o ! ;

: _jjot-name=  ( expected-a expected-u -- flag )
    _jjot-names _jjot-name-o @ +
    _jjot-name-u @
    2SWAP COMPARE 0= ;

: _jjot-value=  ( expected-a expected-u -- flag )
    _jjot-input _jjot-value-o @ +
    _jjot-value-u @
    2SWAP COMPARE 0= ;

: _jjot-decode-member-string  ( -- status )
    _jjot-input _jjot-value-o @ +
    _jjot-value-u @
    _jjot-output 128 _jjot-string-work
    JOSE-JSON-STRING-DECODE
    SWAP _jjot-decoded-u ! ;

: _jjot-fill-publication  ( -- )
    _jjot-descriptor _JJOT-DESCRIPTOR-SIZE 0xA5 FILL
    _jjot-names JOSE-JSON-MAX-STRING-BYTES 0x5A FILL ;

: _jjot-publication-unchanged?  ( -- flag )
    _jjot-descriptor _JJOT-DESCRIPTOR-SIZE 0xA5 _jjot-filled?
    _jjot-names JOSE-JSON-MAX-STRING-BYTES 0x5A _jjot-filled?
    AND ;

: _jjot-fill-preflight  ( -- )
    _jjot-fill-publication
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE 0xC3 FILL
    _jjot-string-work JOSE-JSON-STRING-WORKSPACE-SIZE 0x3C FILL
    _jjot-output 128 0xA5 FILL ;

: _jjot-bad-span  ( -- address length )
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2 ;

: _jjot-test-main  ( -- )
    _jjot-build-main
    16 256 _jjot-parse
        JOSE-JSON-S-OK = _jjot-assert
    _jjot-descriptor JOSE-JSON-OBJECT-VALID? _jjot-assert
    _jjot-descriptor JOSE-JSON-OBJECT-COUNT@
        JOSE-JSON-S-OK = _jjot-assert
        5 = _jjot-assert
    _jjot-descriptor JOSE-JSON-OBJECT-NAMES-USED@
        JOSE-JSON-S-OK = _jjot-assert
        14 = _jjot-assert

    0 _jjot-member
    S" alg" _jjot-name= _jjot-assert
    _jjot-type @ JOSE-JSON-T-STRING = _jjot-assert
    _jjot-decode-member-string
        JOSE-JSON-S-OK = _jjot-assert
    _jjot-decoded-u @ 5 = _jjot-assert
    _jjot-output 5 S" ES256" COMPARE 0= _jjot-assert

    1 _jjot-member
    S" ok" _jjot-name= _jjot-assert
    _jjot-type @ JOSE-JSON-T-BOOL = _jjot-assert
    S" true" _jjot-value= _jjot-assert

    2 _jjot-member
    S" n" _jjot-name= _jjot-assert
    _jjot-type @ JOSE-JSON-T-NUMBER = _jjot-assert
    S" -1.25e+2" _jjot-value= _jjot-assert

    3 _jjot-member
    S" obj" _jjot-name= _jjot-assert
    _jjot-type @ JOSE-JSON-T-OBJECT = _jjot-assert
    _jjot-input _jjot-value-o @ + C@ 123 = _jjot-assert

    4 _jjot-member
    S" emoji" _jjot-name= _jjot-assert
    _jjot-type @ JOSE-JSON-T-STRING = _jjot-assert
    _jjot-decode-member-string
        JOSE-JSON-S-OK = _jjot-assert
    _jjot-decoded-u @ 4 = _jjot-assert
    _jjot-output C@ 0xF0 = _jjot-assert
    _jjot-output 1+ C@ 0x9F = _jjot-assert
    _jjot-output 2 + C@ 0x98 = _jjot-assert
    _jjot-output 3 + C@ 0x80 = _jjot-assert

    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert
    _jjot-string-work JOSE-JSON-STRING-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert
    _jjot-stack ;

: _jjot-reject-transactionally  ( expected-status -- )
    >R
    _jjot-fill-publication
    16 256 _jjot-parse
    R> = _jjot-assert
    _jjot-publication-unchanged? _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert ;

: _jjot-test-strict-rejections  ( -- )
    _jjot-build-root-duplicate
    JOSE-JSON-S-DUPLICATE _jjot-reject-transactionally

    _jjot-build-utf8-duplicate
    JOSE-JSON-S-DUPLICATE _jjot-reject-transactionally

    _jjot-build-nested-duplicate
    JOSE-JSON-S-DUPLICATE _jjot-reject-transactionally

    _jjot-build-lone-high
    JOSE-JSON-S-UTF8 _jjot-reject-transactionally

    _jjot-build-invalid-utf8
    JOSE-JSON-S-UTF8 _jjot-reject-transactionally

    _jjot-build-leading-zero
    JOSE-JSON-S-SYNTAX _jjot-reject-transactionally

    _jjot-build-trailing
    JOSE-JSON-S-SYNTAX _jjot-reject-transactionally

    _jjot-build-array-root
    JOSE-JSON-S-SYNTAX _jjot-reject-transactionally

    _jjot-build-too-deep
    JOSE-JSON-S-DEPTH _jjot-reject-transactionally
    _jjot-stack ;

: _jjot-test-capacity-and-alias  ( -- )
    _jjot-build-main
    _jjot-fill-publication
    4 256 _jjot-parse
        JOSE-JSON-S-CAPACITY = _jjot-assert
    _jjot-publication-unchanged? _jjot-assert

    _jjot-fill-publication
    16 13 _jjot-parse
        JOSE-JSON-S-CAPACITY = _jjot-assert
    _jjot-publication-unchanged? _jjot-assert

    \ The source may not double as the descriptor publication.
    _jjot-input _jjot-input-u @
    _jjot-input 2
    _jjot-names 256
    _jjot-work JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-ALIAS = _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert

    \ A zero-member object admits a null, zero-capacity name buffer.
    _jjot-build-empty
    _jjot-input _jjot-input-u @
    _jjot-descriptor 0
    0 0
    _jjot-work JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-OK = _jjot-assert
    _jjot-descriptor JOSE-JSON-OBJECT-COUNT@
        JOSE-JSON-S-OK = _jjot-assert
        0= _jjot-assert
    _jjot-stack ;

: _jjot-test-string-api  ( -- )
    _jjot-build-string-token
    _jjot-input _jjot-input-u @ _jjot-string-work
        JOSE-JSON-STRING-MEASURE
        JOSE-JSON-S-OK = _jjot-assert
        6 = _jjot-assert

    _jjot-output 128 0xA5 FILL
    _jjot-input _jjot-input-u @
    _jjot-output 128 _jjot-string-work
        JOSE-JSON-STRING-DECODE
        JOSE-JSON-S-OK = _jjot-assert
        6 = _jjot-assert
    _jjot-output C@ 97 = _jjot-assert
    _jjot-output 1+ C@ 0xF0 = _jjot-assert
    _jjot-output 2 + C@ 0x9F = _jjot-assert
    _jjot-output 3 + C@ 0x98 = _jjot-assert
    _jjot-output 4 + C@ 0x80 = _jjot-assert
    _jjot-output 5 + C@ 10 = _jjot-assert

    _jjot-output 128 0xA5 FILL
    _jjot-input _jjot-input-u @
    _jjot-output 5 _jjot-string-work
        JOSE-JSON-STRING-DECODE
        JOSE-JSON-S-CAPACITY = _jjot-assert
        0= _jjot-assert
    _jjot-output 128 0xA5 _jjot-filled? _jjot-assert

    _jjot-input _jjot-input-u @
    _jjot-input 64 _jjot-string-work
        JOSE-JSON-STRING-DECODE
        JOSE-JSON-S-ALIAS = _jjot-assert
        0= _jjot-assert

    _jjot-string-work JOSE-JSON-STRING-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert
    _jjot-stack ;

: _jjot-test-object-string-bound  ( -- )
    JOSE-JSON-MAX-STRING-BYTES _jjot-build-value-string
    16 256 _jjot-parse
        JOSE-JSON-S-OK = _jjot-assert
    _jjot-descriptor JOSE-JSON-OBJECT-VALID? _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert

    JOSE-JSON-MAX-STRING-BYTES 1+ _jjot-build-value-string
    JOSE-JSON-S-STRING _jjot-reject-transactionally
    _jjot-stack ;

: _jjot-test-mapped-spans  ( -- )
    _jjot-build-main

    \ A cross-window source is rejected before any caller output or
    \ workspace byte is mutated.
    _jjot-fill-preflight
    _jjot-bad-span
    _jjot-descriptor 16
    _jjot-names 256
    _jjot-work JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-INVALID = _jjot-assert
    _jjot-publication-unchanged? _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        0xC3 _jjot-filled? _jjot-assert

    \ Protected platform memory maps to ALIAS, also without mutation.
    _jjot-fill-preflight
    _jjot-input _jjot-input-u @
    _jjot-descriptor 16
    _jjot-names 256
    1 JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-ALIAS = _jjot-assert
    _jjot-publication-unchanged? _jjot-assert

    \ Every descriptor byte and every advertised names byte is qualified.
    _jjot-fill-preflight
    _jjot-input _jjot-input-u @
    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 0
    _jjot-names 256
    _jjot-work JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-INVALID = _jjot-assert
    _jjot-names JOSE-JSON-MAX-STRING-BYTES
        0x5A _jjot-filled? _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        0xC3 _jjot-filled? _jjot-assert

    _jjot-fill-preflight
    _jjot-input _jjot-input-u @
    _jjot-descriptor 16
    _jjot-bad-span
    _jjot-work JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-INVALID = _jjot-assert
    _jjot-descriptor _JJOT-DESCRIPTOR-SIZE
        0xA5 _jjot-filled? _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        0xC3 _jjot-filled? _jjot-assert

    \ Full table aliases are rejected before binding the workspace.
    _jjot-fill-preflight
    _jjot-input _jjot-input-u @
    _jjot-descriptor 16
    _jjot-descriptor 256
    _jjot-work JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-ALIAS = _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        0xC3 _jjot-filled? _jjot-assert

    _jjot-fill-preflight
    _jjot-input _jjot-input-u @
    _jjot-descriptor 16
    _jjot-input 256
    _jjot-work JOSE-JSON-OBJECT-PARSE
        JOSE-JSON-S-ALIAS = _jjot-assert
    _jjot-descriptor _JJOT-DESCRIPTOR-SIZE
        0xA5 _jjot-filled? _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        0xC3 _jjot-filled? _jjot-assert

    1 JOSE-JSON-OBJECT-VALID? 0= _jjot-assert
    1 JOSE-JSON-OBJECT-WORKSPACE-CLEAR
        JOSE-JSON-S-ALIAS = _jjot-assert

    _jjot-build-string-token
    _jjot-fill-preflight
    _jjot-bad-span _jjot-string-work
        JOSE-JSON-STRING-MEASURE
        JOSE-JSON-S-INVALID = _jjot-assert
        0= _jjot-assert
    _jjot-string-work JOSE-JSON-STRING-WORKSPACE-SIZE
        0x3C _jjot-filled? _jjot-assert

    _jjot-fill-preflight
    _jjot-input _jjot-input-u @
    _jjot-bad-span _jjot-string-work
        JOSE-JSON-STRING-DECODE
        JOSE-JSON-S-INVALID = _jjot-assert
        0= _jjot-assert
    _jjot-output 128 0xA5 _jjot-filled? _jjot-assert
    _jjot-string-work JOSE-JSON-STRING-WORKSPACE-SIZE
        0x3C _jjot-filled? _jjot-assert
    _jjot-stack ;

: _jjot-throw-after-partial-publication
  ( source source-u descriptor member-capacity
    names names-capacity workspace -- status )
    _JJO-BIND
    DUP _JJW.DESCRIPTOR @
        _JJOT-ACTIVE-DESCRIPTOR-SIZE 0x33 FILL
    DUP _JJW.NAMES @ 256 0x44 FILL
    -777 THROW ;

: _jjot-test-throw-cleanup  ( -- )
    _jjot-build-main
    _jjot-fill-publication
    _jjot-input _jjot-input-u @
    _jjot-descriptor 16
    _jjot-names 256
    _jjot-work
    ['] _jjot-throw-after-partial-publication
    _JJO-PARSE-CALL
        JOSE-JSON-S-INTERNAL = _jjot-assert
    _jjot-descriptor _JJOT-ACTIVE-DESCRIPTOR-SIZE
        _jjot-zero? _jjot-assert
    _jjot-descriptor _JJOT-ACTIVE-DESCRIPTOR-SIZE +
    _JJOT-DESCRIPTOR-SIZE _JJOT-ACTIVE-DESCRIPTOR-SIZE -
    0xA5 _jjot-filled? _jjot-assert
    _jjot-names 256 _jjot-zero? _jjot-assert
    _jjot-names 256 +
    JOSE-JSON-MAX-STRING-BYTES 256 -
    0x5A _jjot-filled? _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert
    _jjot-stack ;

: _jjot-publication-throw  ( workspace -- )
    0 OVER _JJW.DESCRIPTOR @ _JJD.MAGIC !
    0x33 OVER _JJW.DESCRIPTOR @ _JJD.COUNT !
    DROP -778 THROW ;

: _jjot-invoke-publication-throw  ( -- )
    _jjot-work
    ['] _jjot-publication-throw
    ['] _JJO-OBJECT-WORKSPACE-ZERO
    _JJO-CALL-FINALLY ;

: _jjot-operation-throw  ( workspace -- )
    DROP -778 THROW ;

: _jjot-cleanup-throw  ( workspace -- )
    DROP -779 THROW ;

: _jjot-invoke-double-throw  ( -- )
    _jjot-work
    ['] _jjot-operation-throw
    ['] _jjot-cleanup-throw
    _JJO-CALL-FINALLY ;

: _jjot-test-publication-and-cleanup-throws  ( -- )
    _jjot-build-main
    16 256 _jjot-parse
        JOSE-JSON-S-OK = _jjot-assert

    _jjot-input _jjot-input-u @
    _jjot-descriptor 16
    _jjot-names 256
    _jjot-work _JJO-BIND DROP
    ['] _jjot-invoke-publication-throw CATCH
        -778 = _jjot-assert
    _jjot-descriptor JOSE-JSON-OBJECT-VALID? 0= _jjot-assert
    _jjot-work JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _jjot-zero? _jjot-assert

    ['] _jjot-invoke-double-throw CATCH
        -779 = _jjot-assert
    _jjot-stack ;

: _jjot-test-descriptor-guards  ( -- )
    _jjot-build-main
    16 256 _jjot-parse
        JOSE-JSON-S-OK = _jjot-assert
    1 _jjot-descriptor _JJD.RESERVED !
    _jjot-descriptor JOSE-JSON-OBJECT-VALID? 0= _jjot-assert
    0 _jjot-descriptor _JJD.RESERVED !
    _jjot-descriptor JOSE-JSON-OBJECT-VALID? _jjot-assert
    5 _jjot-descriptor JOSE-JSON-OBJECT-MEMBER@
        JOSE-JSON-S-INVALID = _jjot-assert
        2DROP 2DROP DROP
    _jjot-stack ;

: _JJOT-RUN  ( -- )
    0 _jjot-fails !
    0 _jjot-checks !
    DEPTH _jjot-depth !
    _jjot-test-main
    _jjot-test-strict-rejections
    _jjot-test-capacity-and-alias
    _jjot-test-string-api
    _jjot-test-object-string-bound
    _jjot-test-mapped-spans
    _jjot-test-throw-cleanup
    _jjot-test-publication-and-cleanup-throws
    _jjot-test-descriptor-guards
    _jjot-stack
    _jjot-fails @ 0= IF
        ." JOSE JSON OBJECT PASS " _jjot-checks @ . CR
    ELSE
        ." JOSE JSON OBJECT FAIL " _jjot-fails @ . CR
    THEN ;
