\ Focused guest contracts for the caller-owned DNS TXT wire utility.
PROVIDED akashic-dns-txt-contracts

VARIABLE _dntt-fails
VARIABLE _dntt-checks
VARIABLE _dntt-depth
VARIABLE _dntt-response-u

CREATE _dntt-query-allocation DNS-TXT-QUERY-SIZE 7 + ALLOT
_dntt-query-allocation 7 + -8 AND CONSTANT _dntt-query
CREATE _dntt-result-allocation DNS-TXT-RESULT-SIZE 7 + ALLOT
_dntt-result-allocation 7 + -8 AND CONSTANT _dntt-result
CREATE _dntt-small-result-allocation DNS-TXT-RESULT-SIZE 7 + ALLOT
_dntt-small-result-allocation 7 + -8 AND CONSTANT _dntt-small-result
CREATE _dntt-value 128 ALLOT
CREATE _dntt-small-value 4 ALLOT
CREATE _dntt-response 1024 ALLOT
CREATE _dntt-name 320 ALLOT

: _dntt-assert  ( flag -- )
    1 _dntt-checks +!
    0= IF
        1 _dntt-fails +!
        ." DNS TXT ASSERT " _dntt-checks @ . CR
    THEN ;

: _dntt-stack  ( -- )
    DEPTH DUP _dntt-depth @ <> IF
        ." DNS TXT STACK " _dntt-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _dntt-depth @ = _dntt-assert ;

: _dntt-byte?  ( address length byte -- flag )
    >R
    BEGIN
        DUP
    WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _dntt-u16@  ( address -- value )
    DUP C@ 8 LSHIFT SWAP 1+ C@ OR ;

: _dntt-u16!  ( value address -- )
    >R
    DUP 8 RSHIFT R@ C!
    0xFF AND R> 1+ C! ;

: _dntt-append-byte  ( byte -- )
    _dntt-response _dntt-response-u @ + C!
    1 _dntt-response-u +! ;

: _dntt-append-u16  ( value -- )
    DUP 8 RSHIFT _dntt-append-byte
    0xFF AND _dntt-append-byte ;

: _dntt-append-u32  ( value -- )
    DUP 24 RSHIFT _dntt-append-byte
    DUP 16 RSHIFT 0xFF AND _dntt-append-byte
    DUP 8 RSHIFT 0xFF AND _dntt-append-byte
    0xFF AND _dntt-append-byte ;

: _dntt-append-pointer  ( offset -- )
    DUP 8 RSHIFT 0x3F AND 0xC0 OR _dntt-append-byte
    0xFF AND _dntt-append-byte ;

: _dntt-append-bytes  ( address length -- )
    BEGIN
        DUP
    WHILE
        OVER C@ _dntt-append-byte
        1- SWAP 1+ SWAP
    REPEAT
    2DROP ;

: _dntt-set-answer-count  ( count -- )
    _dntt-response 6 + _dntt-u16! ;

: _dntt-set-flags  ( flags -- )
    _dntt-response 2 + _dntt-u16! ;

: _dntt-response-base  ( -- )
    _dntt-query DNS-TXT-QUERY$
    DUP DNS-TXT-S-OK = _dntt-assert
    DROP
    DUP _dntt-response-u !
    _dntt-response SWAP CMOVE
    0x8180 _dntt-set-flags
    0 _dntt-set-answer-count ;

: _dntt-result-reset  ( -- )
    _dntt-value 128 _dntt-result DNS-TXT-RESULT-INIT
    DNS-TXT-S-OK = _dntt-assert ;

: _dntt-small-result-reset  ( -- )
    _dntt-small-value 4 _dntt-small-result DNS-TXT-RESULT-INIT
    DNS-TXT-S-OK = _dntt-assert ;

: _dntt-append-owner-and-fixed  ( ttl rdlength -- )
    >R
    12 _dntt-append-pointer
    16 _dntt-append-u16
    1 _dntt-append-u16
    _dntt-append-u32
    R> _dntt-append-u16 ;

: _dntt-append-good-txt  ( ttl -- )
    13 _dntt-append-owner-and-fixed
    4 _dntt-append-byte
    S" did=" _dntt-append-bytes
    7 _dntt-append-byte
    S" example" _dntt-append-bytes ;

: _dntt-append-a-record  ( -- )
    12 _dntt-append-pointer
    1 _dntt-append-u16
    1 _dntt-append-u16
    60 _dntt-append-u32
    4 _dntt-append-u16
    192 _dntt-append-byte
    0 _dntt-append-byte
    2 _dntt-append-byte
    1 _dntt-append-byte ;

: _dntt-build-primary-query  ( -- )
    S" _AtProto.Example" 0xBEEF _dntt-query
    DNS-TXT-QUERY-BUILD DNS-TXT-S-OK = _dntt-assert ;

: _dntt-test-name-and-query  ( -- )
    S" _atproto.example" DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-OK = _dntt-assert
    S" one.two" DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-OK = _dntt-assert
    S" one..two" DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-INVALID = _dntt-assert
    S" one.two." DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-INVALID = _dntt-assert
    0 0 DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-INVALID = _dntt-assert

    _dntt-name 320 [CHAR] a FILL
    [CHAR] . _dntt-name 63 + C!
    S" x" _dntt-name 64 + SWAP CMOVE
    _dntt-name 65 DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-OK = _dntt-assert

    _dntt-name 320 [CHAR] a FILL
    S" .x" _dntt-name 64 + SWAP CMOVE
    _dntt-name 66 DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-INVALID = _dntt-assert
    _dntt-name 254 DNS-TXT-NAME-VALIDATE
    DNS-TXT-S-CAPACITY = _dntt-assert

    _dntt-query DNS-TXT-QUERY-SIZE 0xA5 FILL
    S" one..two" 7 _dntt-query DNS-TXT-QUERY-BUILD
    DNS-TXT-S-INVALID = _dntt-assert
    _dntt-query DNS-TXT-QUERY-SIZE 0xA5
    _dntt-byte? _dntt-assert

    _dntt-query DNS-TXT-QUERY-SIZE 0 FILL
    S" one.example" _dntt-query 64 + SWAP CMOVE
    _dntt-query 64 + 11 7 _dntt-query DNS-TXT-QUERY-BUILD
    DNS-TXT-S-ALIAS = _dntt-assert

    _dntt-name 320 [CHAR] a FILL
    [CHAR] . _dntt-name 63 + C!
    [CHAR] . _dntt-name 127 + C!
    [CHAR] . _dntt-name 191 + C!
    _dntt-name 253 65535 _dntt-query DNS-TXT-QUERY-BUILD
    DNS-TXT-S-OK = _dntt-assert
    _dntt-query DNS-TXT-QUERY-VALID? _dntt-assert
    _dntt-query DNS-TXT-QUERY$
    DUP DNS-TXT-S-OK = _dntt-assert
    DROP
    DUP DNS-TXT-QUERY-MAX = _dntt-assert
    DROP DROP
    _dntt-query DNS-TXT-QUERY-ID@
    DUP DNS-TXT-S-OK = _dntt-assert
    DROP 65535 = _dntt-assert

    _dntt-build-primary-query
    _dntt-query DNS-TXT-QUERY$
    DUP DNS-TXT-S-OK = _dntt-assert
    DROP
    DUP 34 = _dntt-assert
    OVER _dntt-u16@ 0xBEEF = _dntt-assert
    OVER 2 + _dntt-u16@ 0x0100 = _dntt-assert
    OVER 4 + _dntt-u16@ 1 = _dntt-assert
    OVER 30 + _dntt-u16@ 16 = _dntt-assert
    OVER 32 + _dntt-u16@ 1 = _dntt-assert
    2DROP
    _dntt-stack ;

: _dntt-test-result-lifecycle  ( -- )
    _dntt-value 128 0xA5 FILL
    _dntt-result DNS-TXT-RESULT-SIZE 0xA5 FILL
    _dntt-result 64 _dntt-result DNS-TXT-RESULT-INIT
    DNS-TXT-S-ALIAS = _dntt-assert

    _dntt-result-reset
    _dntt-result DNS-TXT-RESULT-VALID? _dntt-assert

    DNS-TXT-S-INVALID _dntt-result _DNTR.STATUS !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    DNS-TXT-S-EMPTY _dntt-result _DNTR.STATUS !

    1 _dntt-result _DNTR.LENGTH !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    0 _dntt-result _DNTR.LENGTH !

    DNS-TXT-E-ID _dntt-result _DNTR.EVIDENCE !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    0 _dntt-result _DNTR.EVIDENCE !

    _dntt-result DNS-TXT-STATUS@
    DNS-TXT-S-EMPTY = _dntt-assert
    _dntt-result DNS-TXT-VALUE$ NIP 0= _dntt-assert
    _dntt-value 128 0 _dntt-byte? _dntt-assert
    _dntt-stack ;

: _dntt-test-success  ( -- )
    _dntt-result-reset
    _dntt-response-base
    [CHAR] a _dntt-response 14 + C!
    1 _dntt-set-answer-count
    300 _dntt-append-good-txt
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-OK = _dntt-assert
    _dntt-result DNS-TXT-STATUS@
    DNS-TXT-S-OK = _dntt-assert
    _dntt-result DNS-TXT-VALUE$
    S" did=example" COMPARE 0= _dntt-assert
    _dntt-result DNS-TXT-RCODE@ 0= _dntt-assert
    _dntt-result DNS-TXT-FLAGS@ 0x8180 = _dntt-assert
    _dntt-result DNS-TXT-EVIDENCE@
    DNS-TXT-E-RESPONSE DNS-TXT-E-ID OR
    DNS-TXT-E-QUESTION OR DNS-TXT-E-VALUE OR
    = _dntt-assert
    _dntt-result DNS-TXT-ANSWER-COUNT@ 1 = _dntt-assert
    _dntt-result DNS-TXT-MATCHED-COUNT@ 1 = _dntt-assert
    _dntt-result DNS-TXT-STRING-COUNT@ 2 = _dntt-assert
    _dntt-result DNS-TXT-TTL@ 300 = _dntt-assert
    _dntt-stack ;

: _dntt-success-evidence  ( -- evidence )
    DNS-TXT-E-RESPONSE DNS-TXT-E-ID OR
    DNS-TXT-E-QUESTION OR DNS-TXT-E-VALUE OR ;

: _dntt-test-result-corruption  ( -- )
    _dntt-result DNS-TXT-RESULT-VALID? _dntt-assert

    \ Non-success states cannot publish a value length.
    DNS-TXT-S-CAPACITY _dntt-result _DNTR.STATUS !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    DNS-TXT-S-OK _dntt-result _DNTR.STATUS !

    \ Successful publication requires VALUE and its full evidence chain.
    DNS-TXT-E-RESPONSE DNS-TXT-E-ID OR
    DNS-TXT-E-QUESTION OR _dntt-result _DNTR.EVIDENCE !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    _dntt-success-evidence _dntt-result _DNTR.EVIDENCE !

    DNS-TXT-E-VALUE _dntt-result _DNTR.EVIDENCE !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    _dntt-success-evidence _dntt-result _DNTR.EVIDENCE !

    \ RCODE and evidence are bidirectional, not independent observations.
    3 _dntt-result _DNTR.RCODE !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    0 _dntt-result _DNTR.RCODE !

    DNS-TXT-E-RCODE _dntt-success-evidence OR
    _dntt-result _DNTR.EVIDENCE !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    _dntt-success-evidence _dntt-result _DNTR.EVIDENCE !

    DNS-TXT-E-TRUNCATED _dntt-success-evidence OR
    _dntt-result _DNTR.EVIDENCE !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    _dntt-success-evidence _dntt-result _DNTR.EVIDENCE !

    \ NODATA and DUPLICATE cannot contradict the retained match count.
    0 _dntt-result _DNTR.LENGTH !
    DNS-TXT-E-RESPONSE DNS-TXT-E-ID OR
    DNS-TXT-E-QUESTION OR _dntt-result _DNTR.EVIDENCE !
    DNS-TXT-S-NODATA _dntt-result _DNTR.STATUS !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    DNS-TXT-S-DUPLICATE _dntt-result _DNTR.STATUS !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert

    \ A bound RCODE must agree with the response flag nibble.
    DNS-TXT-S-RCODE _dntt-result _DNTR.STATUS !
    3 _dntt-result _DNTR.RCODE !
    DNS-TXT-E-RCODE _dntt-result _DNTR.EVIDENCE +!
    0 _dntt-result _DNTR.MATCHED-COUNT !
    0 _dntt-result _DNTR.STRING-COUNT !
    0 _dntt-result _DNTR.TTL !
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert

    \ Restore the parser-produced success state for subsequent contracts.
    11 _dntt-result _DNTR.LENGTH !
    DNS-TXT-S-OK _dntt-result _DNTR.STATUS !
    0 _dntt-result _DNTR.RCODE !
    0x8180 _dntt-result _DNTR.FLAGS !
    _dntt-success-evidence _dntt-result _DNTR.EVIDENCE !
    1 _dntt-result _DNTR.MATCHED-COUNT !
    2 _dntt-result _DNTR.STRING-COUNT !
    300 _dntt-result _DNTR.TTL !
    _dntt-result DNS-TXT-RESULT-VALID? _dntt-assert
    _dntt-stack ;

: _dntt-test-no-data-and-unrelated  ( -- )
    _dntt-result-reset
    _dntt-response-base
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-NODATA = _dntt-assert
    _dntt-result DNS-TXT-EVIDENCE@
    DNS-TXT-E-RESPONSE DNS-TXT-E-ID OR
    DNS-TXT-E-QUESTION OR = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    _dntt-append-a-record
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-NODATA = _dntt-assert
    _dntt-result DNS-TXT-ANSWER-COUNT@ 1 = _dntt-assert
    _dntt-result DNS-TXT-MATCHED-COUNT@ 0= _dntt-assert
    _dntt-stack ;

: _dntt-test-duplicate-and-capacity  ( -- )
    _dntt-result-reset
    _dntt-response-base
    2 _dntt-set-answer-count
    300 _dntt-append-good-txt
    200 _dntt-append-good-txt
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-DUPLICATE = _dntt-assert
    _dntt-result DNS-TXT-MATCHED-COUNT@ 2 = _dntt-assert
    _dntt-result DNS-TXT-STRING-COUNT@ 4 = _dntt-assert
    _dntt-result DNS-TXT-VALUE$ NIP 0= _dntt-assert
    _dntt-value 128 0 _dntt-byte? _dntt-assert

    _dntt-small-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    300 _dntt-append-good-txt
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-small-result DNS-TXT-PARSE
    DNS-TXT-S-CAPACITY = _dntt-assert
    _dntt-small-result DNS-TXT-RESULT-VALID? _dntt-assert
    _dntt-small-result DNS-TXT-MATCHED-COUNT@ 1 = _dntt-assert
    _dntt-small-result DNS-TXT-STRING-COUNT@ 2 = _dntt-assert
    _dntt-small-value 4 0 _dntt-byte? _dntt-assert
    _dntt-stack ;

: _dntt-test-header-outcomes  ( -- )
    _dntt-result-reset
    _dntt-response-base
    0x1111 _dntt-response _dntt-u16!
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MISMATCH = _dntt-assert
    _dntt-result DNS-TXT-EVIDENCE@ 0= _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    0x8380 _dntt-set-flags
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-TRUNCATED = _dntt-assert
    _dntt-result DNS-TXT-EVIDENCE@
    DNS-TXT-E-ID DNS-TXT-E-RESPONSE OR
    DNS-TXT-E-QUESTION OR DNS-TXT-E-TRUNCATED OR
    = _dntt-assert

    \ Question binding precedes TC handling.
    _dntt-result-reset
    _dntt-response-base
    0x8380 _dntt-set-flags
    1 _dntt-response _dntt-response-u @ 4 - + _dntt-u16!
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MISMATCH = _dntt-assert
    _dntt-result DNS-TXT-EVIDENCE@
    DNS-TXT-E-ID DNS-TXT-E-RESPONSE OR = _dntt-assert

    \ A nonzero RCODE remains evidence when TC determines the outcome.
    _dntt-result-reset
    _dntt-response-base
    0x8383 _dntt-set-flags
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-TRUNCATED = _dntt-assert
    _dntt-result DNS-TXT-RCODE@ 3 = _dntt-assert
    _dntt-result DNS-TXT-EVIDENCE@
    DNS-TXT-E-ID DNS-TXT-E-RESPONSE OR
    DNS-TXT-E-QUESTION OR DNS-TXT-E-TRUNCATED OR
    DNS-TXT-E-RCODE OR = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    0x8183 _dntt-set-flags
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-RCODE = _dntt-assert
    _dntt-result DNS-TXT-RCODE@ 3 = _dntt-assert
    _dntt-result DNS-TXT-EVIDENCE@
    DNS-TXT-E-ID DNS-TXT-E-RESPONSE OR
    DNS-TXT-E-QUESTION OR DNS-TXT-E-RCODE OR
    = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    1 _dntt-response _dntt-response-u @ 4 - + _dntt-u16!
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MISMATCH = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    0x81C0 _dntt-set-flags
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert
    _dntt-stack ;

: _dntt-test-malformed-names  ( -- )
    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    _dntt-response-u @ _dntt-append-pointer
    16 _dntt-append-u16
    1 _dntt-append-u16
    0 _dntt-append-u32
    1 _dntt-append-u16
    0 _dntt-append-byte
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert

    \ An in-range pointer still cannot target later packet bytes.
    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    _dntt-response-u @ 2 + _dntt-append-pointer
    16 _dntt-append-u16
    1 _dntt-append-u16
    0 _dntt-append-u32
    1 _dntt-append-u16
    0 _dntt-append-byte
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    16383 _dntt-append-pointer
    16 _dntt-append-u16
    1 _dntt-append-u16
    0 _dntt-append-u32
    1 _dntt-append-u16
    0 _dntt-append-byte
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    0x40 _dntt-append-byte
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert
    _dntt-stack ;

: _dntt-test-malformed-rdata  ( -- )
    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    60 2 _dntt-append-owner-and-fixed
    5 _dntt-append-byte
    [CHAR] x _dntt-append-byte
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    60 0 _dntt-append-owner-and-fixed
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert
    _dntt-result DNS-TXT-RESULT-VALID? _dntt-assert
    _dntt-result DNS-TXT-MATCHED-COUNT@ 1 = _dntt-assert
    _dntt-result DNS-TXT-STRING-COUNT@ 0= _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    0x80000000 1 _dntt-append-owner-and-fixed
    0 _dntt-append-byte
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert

    _dntt-result-reset
    _dntt-response-base
    1 _dntt-set-answer-count
    60 _dntt-append-good-txt
    0xAA _dntt-append-byte
    _dntt-response _dntt-response-u @
    _dntt-query _dntt-result DNS-TXT-PARSE
    DNS-TXT-S-MALFORMED = _dntt-assert
    _dntt-stack ;

: _dntt-test-wipe  ( -- )
    _dntt-result-reset
    _dntt-value 128 0xA5 FILL
    _dntt-result DNS-TXT-RESULT-WIPE
    DNS-TXT-S-OK = _dntt-assert
    _dntt-result DNS-TXT-RESULT-VALID? 0= _dntt-assert
    _dntt-value 128 0 _dntt-byte? _dntt-assert

    _dntt-query DNS-TXT-QUERY-WIPE
    DNS-TXT-S-OK = _dntt-assert
    _dntt-query DNS-TXT-QUERY-VALID? 0= _dntt-assert
    _dntt-query DNS-TXT-QUERY-SIZE 0 _dntt-byte? _dntt-assert
    _dntt-stack ;

: _DNTT-RUN  ( -- )
    0 _dntt-fails !
    0 _dntt-checks !
    DEPTH _dntt-depth !
    _dntt-test-name-and-query
    _dntt-test-result-lifecycle
    _dntt-test-success
    _dntt-test-result-corruption
    _dntt-test-no-data-and-unrelated
    _dntt-test-duplicate-and-capacity
    _dntt-test-header-outcomes
    _dntt-test-malformed-names
    _dntt-test-malformed-rdata
    _dntt-test-wipe
    _dntt-fails @ 0= IF
        ." DNS TXT MESSAGE PASS " _dntt-checks @ . CR
    ELSE
        ." DNS TXT MESSAGE FAIL " _dntt-fails @ .
        ." / " _dntt-checks @ . CR
    THEN ;
