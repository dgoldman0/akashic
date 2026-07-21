\ generation-pair-contracts.f - policy-neutral generation-pair contracts

\ Module keys are limited to 23 characters.  Keep this key distinct from the
\ 23-character `akashic-generation-pair` key of the module under test.
PROVIDED akashic-gpair-contracts

VARIABLE _gpt-fails
VARIABLE _gpt-checks
VARIABLE _gpt-depth
VARIABLE _gpt-equal-calls
VARIABLE _gpt-save-calls
VARIABLE _gpt-save-mode
VARIABLE _gpt-save-payload
VARIABLE _gpt-save-slot
VARIABLE _gpt-save-generation
VARIABLE _gpt-save-pair
VARIABLE _gpt-save-context

CREATE _gpt-candidate-a GPAIR-CANDIDATE-SIZE ALLOT
CREATE _gpt-candidate-b GPAIR-CANDIDATE-SIZE ALLOT
CREATE _gpt-candidate-c GPAIR-CANDIDATE-SIZE ALLOT
CREATE _gpt-candidate-d GPAIR-CANDIDATE-SIZE ALLOT
CREATE _gpt-pair-a GPAIR-SIZE ALLOT
CREATE _gpt-pair-b GPAIR-SIZE ALLOT
CREATE _gpt-invalid GPAIR-SIZE ALLOT
CREATE _gpt-overlap GPAIR-SIZE GPAIR-CANDIDATE-SIZE + ALLOT

-1 1 RSHIFT CONSTANT _GPT-MAX-GENERATION

: _gpt-assert  ( flag -- )
    1 _gpt-checks +!
    0= IF 1 _gpt-fails +! ." GPT ASSERT " _gpt-checks @ . CR THEN ;

: _gpt-stack  ( -- )
    DEPTH DUP _gpt-depth @ <> IF
        ." GPT STACK " _gpt-depth @ . ."  -> " DUP . CR .S CR
    THEN
    _gpt-depth @ = _gpt-assert ;

: _gpt-equal  ( value-a value-b context -- equal? detail )
    77 = _gpt-assert
    1 _gpt-equal-calls +!
    = 701 ;

: _gpt-equal-throw  ( value-a value-b context -- equal? detail )
    DROP 2DROP -8401 THROW ;

: _gpt-equal-reenter  ( value-a value-b pair -- equal? detail )
    >R
    _gpt-candidate-c _gpt-candidate-d R@ GPAIR-SELECT
    GPAIR-S-BUSY = _gpt-assert
    GPAIR-R-NONE = _gpt-assert
    R@ GPAIR-RESET GPAIR-S-BUSY = _gpt-assert
    909 R@ GPAIR-SAVE
    GPAIR-S-BUSY = _gpt-assert
    GPAIR-W-NO-EFFECT = _gpt-assert
    R> DROP
    = 702 ;

: _gpt-equal-independent  ( value-a value-b other-pair -- equal? detail )
    >R
    _gpt-candidate-c _gpt-candidate-d R@ GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert
    GPAIR-R-FALLBACK = _gpt-assert
    R> DROP
    = 703 ;

: _gpt-save-durable  ( payload slot generation pair context -- detail )
    88 = _gpt-assert
    >R 2DROP DROP
    R@ GPAIR-SAVE-MAYBE! GPAIR-S-OK = _gpt-assert
    R@ GPAIR-SAVE-DURABLE! GPAIR-S-OK = _gpt-assert
    R> DROP 808 ;

: _gpt-save  ( payload slot generation pair context -- detail )
    _gpt-save-context !
    _gpt-save-pair !
    _gpt-save-generation !
    _gpt-save-slot !
    _gpt-save-payload !
    1 _gpt-save-calls +!
    _gpt-save-context @ 77 = _gpt-assert
    _gpt-save-mode @ CASE
        0 OF 600 ENDOF
        1 OF
            _gpt-save-pair @ GPAIR-SAVE-MAYBE!
                GPAIR-S-OK = _gpt-assert
            601
        ENDOF
        2 OF
            _gpt-save-pair @ GPAIR-SAVE-MAYBE!
                GPAIR-S-OK = _gpt-assert
            _gpt-save-pair @ GPAIR-SAVE-DURABLE!
                GPAIR-S-OK = _gpt-assert
            602
        ENDOF
        3 OF -8501 THROW ENDOF
        4 OF
            _gpt-save-pair @ GPAIR-SAVE-MAYBE!
                GPAIR-S-OK = _gpt-assert
            -8502 THROW
        ENDOF
        5 OF
            _gpt-save-pair @ GPAIR-SAVE-MAYBE!
                GPAIR-S-OK = _gpt-assert
            _gpt-save-pair @ GPAIR-SAVE-DURABLE!
                GPAIR-S-OK = _gpt-assert
            -8503 THROW
        ENDOF
        6 OF
            999 _gpt-save-pair @ GPAIR-SAVE
            GPAIR-S-BUSY = _gpt-assert
            GPAIR-W-NO-EFFECT = _gpt-assert
            _gpt-candidate-c _gpt-candidate-d _gpt-save-pair @
                GPAIR-SELECT
            GPAIR-S-BUSY = _gpt-assert
            GPAIR-R-NONE = _gpt-assert
            _gpt-save-pair @ GPAIR-RESET
                GPAIR-S-BUSY = _gpt-assert
            606
        ENDOF
        7 OF
            _gpt-save-pair @ GPAIR-SAVE-DURABLE!
                GPAIR-S-PROTOCOL = _gpt-assert
            607
        ENDOF
        8 OF
            888 _gpt-pair-b GPAIR-SAVE
            GPAIR-S-OK = _gpt-assert
            GPAIR-W-DURABLE = _gpt-assert
            608
        ENDOF
        699 SWAP
    ENDCASE ;

: _gpt-init-candidates  ( -- )
    _gpt-candidate-a GPAIR-CANDIDATE-INIT GPAIR-S-OK = _gpt-assert
    _gpt-candidate-b GPAIR-CANDIDATE-INIT GPAIR-S-OK = _gpt-assert
    _gpt-candidate-c GPAIR-CANDIDATE-INIT GPAIR-S-OK = _gpt-assert
    _gpt-candidate-d GPAIR-CANDIDATE-INIT GPAIR-S-OK = _gpt-assert ;

: _gpt-init-pair-a  ( -- )
    ['] _gpt-equal ['] _gpt-save 77 _gpt-pair-a GPAIR-INIT
        GPAIR-S-OK = _gpt-assert ;

: _gpt-candidate-contracts  ( -- )
    _gpt-init-candidates
    _gpt-candidate-a GPAIR-CANDIDATE-VALID? _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-CLASS@
        GPAIR-C-ABSENT = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-GENERATION@ 0= _gpt-assert

    41 _gpt-candidate-a GPAIR-CANDIDATE-CORRUPT!
        GPAIR-S-OK = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-CLASS@
        GPAIR-C-CORRUPT = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-DETAIL@ 41 = _gpt-assert

    101 7 42 _gpt-candidate-a GPAIR-CANDIDATE-VALUE!
        GPAIR-S-OK = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-VALID? _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-CLASS@
        GPAIR-C-VALID = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-VALUE@ 101 = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-GENERATION@ 7 = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-DETAIL@ 42 = _gpt-assert

    202 0 99 _gpt-candidate-a GPAIR-CANDIDATE-VALUE!
        GPAIR-S-INVALID = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-VALUE@ 101 = _gpt-assert
    0 GPAIR-CANDIDATE-INIT GPAIR-S-INVALID = _gpt-assert
    -8 GPAIR-CANDIDATE-INIT GPAIR-S-INVALID = _gpt-assert
    -8 GPAIR-CANDIDATE-VALID? 0= _gpt-assert
    0 0 GPAIR-CANDIDATE-ABSENT! GPAIR-S-INVALID = _gpt-assert
    0 -8 GPAIR-CANDIDATE-ABSENT! GPAIR-S-INVALID = _gpt-assert
    _gpt-stack ;

: _gpt-pair-contracts  ( -- )
    _gpt-invalid GPAIR-SIZE 88 FILL
    0 ['] _gpt-save 77 _gpt-invalid GPAIR-INIT
        GPAIR-S-INVALID = _gpt-assert
    _gpt-invalid C@ 88 = _gpt-assert
    ['] _gpt-equal 0 77 _gpt-invalid GPAIR-INIT
        GPAIR-S-INVALID = _gpt-assert
    _gpt-invalid C@ 88 = _gpt-assert
    ['] _gpt-equal ['] _gpt-save 77 -8 GPAIR-INIT
        GPAIR-S-INVALID = _gpt-assert
    -8 GPAIR-VALID? 0= _gpt-assert

    _gpt-init-pair-a
    _gpt-pair-a GPAIR-VALID? _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ -1 = _gpt-assert
    _gpt-pair-a GPAIR-RESULT@ GPAIR-R-NONE = _gpt-assert
    _gpt-pair-a GPAIR-OUTCOME@ GPAIR-W-NO-EFFECT = _gpt-assert
    _gpt-pair-a GPAIR-CONTEXT@ 77 = _gpt-assert
    _gpt-pair-a GPAIR-INACTIVE-SLOT?
    GPAIR-S-OK = _gpt-assert GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-NEXT-GENERATION?
    GPAIR-S-OK = _gpt-assert 1 = _gpt-assert
    _gpt-pair-a GPAIR-SAVE-MAYBE!
        GPAIR-S-PROTOCOL = _gpt-assert
    _gpt-pair-a GPAIR-SAVE-DURABLE!
        GPAIR-S-PROTOCOL = _gpt-assert
    _gpt-pair-a GPAIR-RESET GPAIR-S-OK = _gpt-assert
    _gpt-stack ;

: _gpt-pair-tail-candidate  ( -- candidate )
    _gpt-pair-a GPAIR-SIZE GPAIR-CANDIDATE-SIZE - + ;

: _gpt-alias-contracts  ( -- )
    _gpt-init-pair-a

    \ Both descriptors remain structurally valid: B begins in A's opaque
    \ detail cell.  Their partial fixed-span overlap is still rejected.
    0 _gpt-overlap GPAIR-CANDIDATE-ABSENT! DROP
    0 _gpt-overlap 32 + GPAIR-CANDIDATE-ABSENT! DROP
    _gpt-overlap GPAIR-CANDIDATE-VALID? _gpt-assert
    _gpt-overlap 32 + GPAIR-CANDIDATE-VALID? _gpt-assert
    _gpt-overlap _gpt-overlap 32 + _gpt-pair-a GPAIR-SELECT
    GPAIR-S-INVALID = _gpt-assert GPAIR-R-NONE = _gpt-assert
    _gpt-pair-a GPAIR-RESULT@ GPAIR-R-NONE = _gpt-assert

    \ Exact candidate alias is rejected, while exact adjacency is accepted.
    _gpt-overlap _gpt-overlap _gpt-pair-a GPAIR-SELECT
    GPAIR-S-INVALID = _gpt-assert GPAIR-R-NONE = _gpt-assert
    0 _gpt-overlap 80 + GPAIR-CANDIDATE-ABSENT! DROP
    0 _gpt-overlap 80 + GPAIR-CANDIDATE-SIZE +
        GPAIR-CANDIDATE-ABSENT! DROP
    _gpt-overlap 80 +
    _gpt-overlap 80 + GPAIR-CANDIDATE-SIZE +
    _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-ABSENT = _gpt-assert

    \ A valid candidate can occupy otherwise-unused pair scratch cells, but
    \ an operation may not accept that partially aliased storage graph.
    _gpt-init-pair-a
    0 _gpt-pair-tail-candidate GPAIR-CANDIDATE-ABSENT! DROP
    0 _gpt-candidate-b GPAIR-CANDIDATE-ABSENT! DROP
    _gpt-pair-a GPAIR-VALID? _gpt-assert
    _gpt-pair-tail-candidate GPAIR-CANDIDATE-VALID? _gpt-assert
    _gpt-pair-tail-candidate _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-INVALID = _gpt-assert GPAIR-R-NONE = _gpt-assert
    _gpt-pair-a GPAIR-RESULT@ GPAIR-R-NONE = _gpt-assert
    _gpt-stack ;

: _gpt-select-absent-corrupt  ( -- )
    _gpt-init-pair-a _gpt-init-candidates
    11 _gpt-candidate-a GPAIR-CANDIDATE-ABSENT! DROP
    12 _gpt-candidate-b GPAIR-CANDIDATE-ABSENT! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-ABSENT = _gpt-assert
    _gpt-pair-a GPAIR-RESULT@ GPAIR-R-ABSENT = _gpt-assert
    _gpt-pair-a GPAIR-SELECTED@ 0= _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ -1 = _gpt-assert
    _gpt-candidate-a GPAIR-CANDIDATE-DETAIL@ 11 = _gpt-assert
    _gpt-candidate-b GPAIR-CANDIDATE-DETAIL@ 12 = _gpt-assert

    21 _gpt-candidate-a GPAIR-CANDIDATE-CORRUPT! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-CORRUPT = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ -1 = _gpt-assert

    _gpt-candidate-a _gpt-candidate-a _gpt-pair-a GPAIR-SELECT
    GPAIR-S-INVALID = _gpt-assert GPAIR-R-NONE = _gpt-assert
    _gpt-pair-a GPAIR-RESULT@ GPAIR-R-CORRUPT = _gpt-assert
    _gpt-stack ;

: _gpt-select-fallback-newest  ( -- )
    _gpt-init-pair-a _gpt-init-candidates
    101 2 31 _gpt-candidate-a GPAIR-CANDIDATE-VALUE! DROP
    32 _gpt-candidate-b GPAIR-CANDIDATE-ABSENT! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-FALLBACK = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 2 = _gpt-assert
    _gpt-pair-a GPAIR-SELECTED@ _gpt-candidate-a = _gpt-assert
    _gpt-pair-a GPAIR-INACTIVE-SLOT?
    GPAIR-S-OK = _gpt-assert GPAIR-SLOT-B = _gpt-assert

    _gpt-pair-a GPAIR-RESET DROP
    33 _gpt-candidate-a GPAIR-CANDIDATE-CORRUPT! DROP
    202 5 34 _gpt-candidate-b GPAIR-CANDIDATE-VALUE! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-FALLBACK = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-B = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 5 = _gpt-assert

    _gpt-pair-a GPAIR-RESET DROP
    301 7 0 _gpt-candidate-a GPAIR-CANDIDATE-VALUE! DROP
    302 9 0 _gpt-candidate-b GPAIR-CANDIDATE-VALUE! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-NEWEST = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-B = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 9 = _gpt-assert

    _gpt-pair-a GPAIR-RESET DROP
    303 10 0 _gpt-candidate-a GPAIR-CANDIDATE-VALUE! DROP
    304 9 0 _gpt-candidate-b GPAIR-CANDIDATE-VALUE! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-NEWEST = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 10 = _gpt-assert

    \ A later classification with no authoritative candidate must revoke the
    \ previously selected generation and slot.  It must not expose stale RAM
    \ authority from the preceding successful selection.
    41 _gpt-candidate-a GPAIR-CANDIDATE-ABSENT! DROP
    42 _gpt-candidate-b GPAIR-CANDIDATE-ABSENT! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-ABSENT = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ -1 = _gpt-assert
    _gpt-pair-a GPAIR-SELECTED@ 0= _gpt-assert
    _gpt-stack ;

: _gpt-select-equal  ( -- )
    _gpt-init-pair-a _gpt-init-candidates 0 _gpt-equal-calls !
    401 11 0 _gpt-candidate-a GPAIR-CANDIDATE-VALUE! DROP
    401 11 0 _gpt-candidate-b GPAIR-CANDIDATE-VALUE! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-EQUAL = _gpt-assert
    _gpt-equal-calls @ 1 = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 11 = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 701 = _gpt-assert

    _gpt-pair-a GPAIR-RESET DROP
    401 12 0 _gpt-candidate-a GPAIR-CANDIDATE-VALUE! DROP
    402 12 0 _gpt-candidate-b GPAIR-CANDIDATE-VALUE! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-AMBIGUOUS = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ -1 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-SELECTED@ 0= _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 701 = _gpt-assert
    _gpt-pair-a GPAIR-CALLBACK-THROW@ 0= _gpt-assert

    ['] _gpt-equal-throw ['] _gpt-save 77 _gpt-pair-a GPAIR-INIT DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-CALLBACK = _gpt-assert GPAIR-R-NONE = _gpt-assert
    _gpt-pair-a GPAIR-CALLBACK-THROW@ -8401 = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 0= _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE? 0= _gpt-assert
    _gpt-stack ;

: _gpt-select-reentry-independent  ( -- )
    _gpt-init-candidates
    501 20 0 _gpt-candidate-a GPAIR-CANDIDATE-VALUE! DROP
    501 20 0 _gpt-candidate-b GPAIR-CANDIDATE-VALUE! DROP
    601 1 0 _gpt-candidate-c GPAIR-CANDIDATE-VALUE! DROP
    0 _gpt-candidate-d GPAIR-CANDIDATE-ABSENT! DROP

    ['] _gpt-equal-reenter ['] _gpt-save _gpt-pair-a
        _gpt-pair-a GPAIR-INIT DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-EQUAL = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 702 = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE? 0= _gpt-assert

    ['] _gpt-equal ['] _gpt-save-durable 88 _gpt-pair-b GPAIR-INIT DROP
    ['] _gpt-equal-independent ['] _gpt-save _gpt-pair-b
        _gpt-pair-a GPAIR-INIT DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-EQUAL = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 703 = _gpt-assert
    _gpt-pair-b GPAIR-RESULT@ GPAIR-R-FALLBACK = _gpt-assert
    _gpt-pair-b GPAIR-GENERATION@ 1 = _gpt-assert
    _gpt-stack ;

: _gpt-save-result  ( expected-outcome expected-status -- )
    >R ROT = _gpt-assert R> = _gpt-assert ;

: _gpt-save-contracts  ( -- )
    _gpt-init-pair-a _gpt-init-candidates
    0 _gpt-save-calls !

    0 _gpt-save-mode !
    100 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-NO-EFFECT GPAIR-S-OK _gpt-save-result
    _gpt-save-calls @ 1 = _gpt-assert
    _gpt-save-payload @ 100 = _gpt-assert
    _gpt-save-slot @ GPAIR-SLOT-A = _gpt-assert
    _gpt-save-generation @ 1 = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 600 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ -1 = _gpt-assert

    1 _gpt-save-mode !
    101 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-MAYBE GPAIR-S-OK _gpt-save-result
    _gpt-pair-a GPAIR-DETAIL@ 601 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ -1 = _gpt-assert

    2 _gpt-save-mode !
    102 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-DURABLE GPAIR-S-OK _gpt-save-result
    _gpt-pair-a GPAIR-DETAIL@ 602 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 1 = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-NEXT-GENERATION?
    GPAIR-S-OK = _gpt-assert 2 = _gpt-assert

    103 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-DURABLE GPAIR-S-OK _gpt-save-result
    _gpt-save-slot @ GPAIR-SLOT-B = _gpt-assert
    _gpt-save-generation @ 2 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 2 = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-B = _gpt-assert

    3 _gpt-save-mode !
    104 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-NO-EFFECT GPAIR-S-CALLBACK _gpt-save-result
    _gpt-pair-a GPAIR-CALLBACK-THROW@ -8501 = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 0= _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 2 = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-B = _gpt-assert

    4 _gpt-save-mode !
    105 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-MAYBE GPAIR-S-CALLBACK _gpt-save-result
    _gpt-pair-a GPAIR-CALLBACK-THROW@ -8502 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 2 = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-B = _gpt-assert

    5 _gpt-save-mode !
    106 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-DURABLE GPAIR-S-CALLBACK _gpt-save-result
    _gpt-pair-a GPAIR-CALLBACK-THROW@ -8503 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 3 = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE? 0= _gpt-assert
    _gpt-stack ;

: _gpt-save-reentry-independent  ( -- )
    _gpt-init-pair-a _gpt-init-candidates
    6 _gpt-save-mode !
    200 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-NO-EFFECT GPAIR-S-OK _gpt-save-result
    _gpt-pair-a GPAIR-DETAIL@ 606 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert

    7 _gpt-save-mode !
    201 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-NO-EFFECT GPAIR-S-OK _gpt-save-result
    _gpt-pair-a GPAIR-DETAIL@ 607 = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert

    ['] _gpt-equal ['] _gpt-save-durable 88 _gpt-pair-b GPAIR-INIT DROP
    8 _gpt-save-mode !
    202 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-NO-EFFECT GPAIR-S-OK _gpt-save-result
    _gpt-pair-b GPAIR-GENERATION@ 1 = _gpt-assert
    _gpt-pair-b GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ 0= _gpt-assert
    _gpt-stack ;

: _gpt-generation-overflow  ( -- )
    _gpt-init-pair-a _gpt-init-candidates
    701 _GPT-MAX-GENERATION 0 _gpt-candidate-a
        GPAIR-CANDIDATE-VALUE! DROP
    701 _GPT-MAX-GENERATION 0 _gpt-candidate-b
        GPAIR-CANDIDATE-VALUE! DROP
    _gpt-candidate-a _gpt-candidate-b _gpt-pair-a GPAIR-SELECT
    GPAIR-S-OK = _gpt-assert GPAIR-R-EQUAL = _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ _GPT-MAX-GENERATION = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 701 = _gpt-assert
    _gpt-save-calls @ >R
    2 _gpt-save-mode !
    300 _gpt-pair-a GPAIR-SAVE
    GPAIR-W-NO-EFFECT GPAIR-S-CAPACITY _gpt-save-result
    _gpt-save-calls @ R> = _gpt-assert
    _gpt-pair-a GPAIR-DETAIL@ 0= _gpt-assert
    _gpt-pair-a GPAIR-CALLBACK-THROW@ 0= _gpt-assert
    _gpt-pair-a GPAIR-NEXT-GENERATION@ 0= _gpt-assert
    _gpt-pair-a GPAIR-GENERATION@ _GPT-MAX-GENERATION = _gpt-assert
    _gpt-pair-a GPAIR-ACTIVE-SLOT@ GPAIR-SLOT-A = _gpt-assert
    _gpt-pair-a GPAIR-NEXT-GENERATION?
    GPAIR-S-CAPACITY = _gpt-assert 0= _gpt-assert
    _gpt-stack ;

: _gpt-run  ( -- )
    0 _gpt-fails ! 0 _gpt-checks ! DEPTH _gpt-depth !
    _gpt-candidate-contracts
    _gpt-pair-contracts
    _gpt-alias-contracts
    _gpt-select-absent-corrupt
    _gpt-select-fallback-newest
    _gpt-select-equal
    _gpt-select-reentry-independent
    _gpt-save-contracts
    _gpt-save-reentry-independent
    _gpt-generation-overflow
    _gpt-stack
    _gpt-fails @ 0= IF
        ." GENERATION PAIR PASS " _gpt-checks @ .
    ELSE
        ." GENERATION PAIR FAIL " _gpt-fails @ . ." / "
        _gpt-checks @ .
    THEN CR ;

_gpt-run
