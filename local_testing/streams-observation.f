\ Deterministic harness contracts for the pointer-free Streams observation state.

PROVIDED streams-ochk-tests

\ Load observation-state.f before this deterministic contract leaf.

." [octx] compiling contracts" CR

VARIABLE _octx-fails
VARIABLE _octx-checks
VARIABLE _octx-depth

VARIABLE _octx-state-a
VARIABLE _octx-snapshot-a
VARIABLE _octx-candidates-a
: _octx-state      ( -- a ) _octx-state-a @ ;
: _octx-snapshot   ( -- a ) _octx-snapshot-a @ ;
: _octx-candidates ( -- a ) _octx-candidates-a @ ;
CREATE _octx-source RID-SIZE ALLOT
CREATE _octx-namespace RID-SIZE ALLOT
CREATE _octx-first-id RID-SIZE ALLOT

: _octx-assert  ( flag -- )
    1 _octx-checks +! 0= IF
        1 _octx-fails +! ." OCTX ASSERT " _octx-checks @ . CR
    THEN ;

: _octx-stack  ( -- )
    DEPTH DUP _octx-depth @ <> IF
        ." OCTX STACK " _octx-depth @ . ." -> " DUP . CR .S CR
    THEN
    _octx-depth @ = _octx-assert ;

: _octx-id!  ( value rid -- ) DUP RID-CLEAR ! ;
: _octx-candidate  ( index -- candidate )
    OCHK-CANDIDATE-SIZE * _octx-candidates + ;

: _octx-candidate-1!  ( -- )
    0 _octx-candidate DUP OCHK-CANDIDATE-INIT
    1 OVER OCC.FORMAT ! OCHK-NATIVE-PROVIDER-ID OVER OCC.NATIVE-KIND !
    S" item-1" 2 PICK OCC.NATIVE-U ! OVER OCC.NATIVE-A !
    S" First title" 2 PICK OCC.TITLE-U ! OVER OCC.TITLE-A !
    S" https://feed.example/items/1" 2 PICK OCC.URL-U ! OVER OCC.URL-A !
    S" First summary" 2 PICK OCC.SUMMARY-U ! OVER OCC.SUMMARY-A !
    S" First body" 2 PICK OCC.CONTENT-U ! OVER OCC.CONTENT-A !
    S" 2026-07-16T12:00:00Z" 2 PICK OCC.PUBLISHED-U ! OVER OCC.PUBLISHED-A !
    S" 2026-07-16T12:00:00Z" 2 PICK OCC.MODIFIED-U ! OVER OCC.MODIFIED-A !
    DROP ;

: _octx-candidate-2!  ( -- )
    1 _octx-candidate DUP OCHK-CANDIDATE-INIT
    2 OVER OCC.FORMAT ! OCHK-NATIVE-PROVIDER-ID OVER OCC.NATIVE-KIND !
    S" item-2" 2 PICK OCC.NATIVE-U ! OVER OCC.NATIVE-A !
    S" Second title" 2 PICK OCC.TITLE-U ! OVER OCC.TITLE-A !
    S" https://feed.example/items/2" 2 PICK OCC.URL-U ! OVER OCC.URL-A !
    S" Second summary" 2 PICK OCC.SUMMARY-U ! OVER OCC.SUMMARY-A !
    S" Second body" 2 PICK OCC.CONTENT-U ! OVER OCC.CONTENT-A !
    S" 2026-07-16T12:01:00Z" 2 PICK OCC.PUBLISHED-U ! OVER OCC.PUBLISHED-A !
    S" 2026-07-16T12:01:00Z" 2 PICK OCC.MODIFIED-U ! OVER OCC.MODIFIED-A !
    DROP ;

: _octx-candidate-1-changed!  ( -- )
    S" First body revised"
    0 _octx-candidate OCC.CONTENT-U !
    0 _octx-candidate OCC.CONTENT-A ! ;

: _octx-begin  ( -- status )
    _octx-source 1 _octx-namespace 1
    S" https://feed.example/feed.json" _octx-state OCHK-BEGIN ;

: _octx-apply  ( -- status )
    _octx-source 1 S" https://feed.example/feed.json"
    42 200 _octx-candidates 2 _octx-state OCHK-APPLY ;

: _octx-head  ( -- head ) _octx-source _octx-state OCHK-SOURCE-FIND ;

: _octx-snapshot!  ( -- )
    _octx-state _octx-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE ;

: _octx-snapshot=?  ( -- flag )
    _octx-state STREAMS-OBSERVATION-CHECKPOINT-SIZE
    _octx-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE COMPARE 0= ;

: _octx-test-init  ( -- )
    _octx-state OCHK-INIT
    _octx-state OCHK-VALID? _octx-assert
    _octx-state OCHK.GENERATION @ 0= _octx-assert
    _octx-state OCHK.SEQUENCE @ 0= _octx-assert
    _octx-state OCHK.SOURCE-COUNT @ 0= _octx-assert
    _octx-state OCHK.OBSERVATION-COUNT @ 0= _octx-assert
    _octx-state OCHK.KEY-COUNT @ 0= _octx-assert
    _octx-stack ;

: _octx-test-begin-alias-rejection  ( -- )
    _octx-snapshot!
    _octx-state OCHK.MAGIC 1 _octx-namespace 1
        S" https://feed.example/feed.json" _octx-state OCHK-BEGIN
        OCHK-S-INVALID = _octx-assert
    _octx-snapshot=? _octx-assert
    _octx-source 1 _octx-state OCHK.MAGIC 1
        S" https://feed.example/feed.json" _octx-state OCHK-BEGIN
        OCHK-S-INVALID = _octx-assert
    _octx-snapshot=? _octx-assert
    _octx-source 1 _octx-namespace 1
        _octx-state OCHK.MAGIC 8 _octx-state OCHK-BEGIN
        OCHK-S-INVALID = _octx-assert
    _octx-snapshot=? _octx-assert
    _octx-stack ;

: _octx-test-first-apply  ( -- )
    _octx-begin OCHK-S-OK = _octx-assert
    _octx-state OCHK-VALID? _octx-assert
    _octx-head DUP 0<> _octx-assert
    DUP OCS.STATE @ OCHK-ATTEMPT-ACCEPTED = _octx-assert
    DUP OCS.ATTEMPT-ID RID-PRESENT? _octx-assert
    OCS.REQUESTED$ S" https://feed.example/feed.json" STR-STR= _octx-assert
    _octx-snapshot!
    _octx-source 1 _octx-state OCHK.MAGIC 8
        42 200 _octx-candidates 2 _octx-state OCHK-APPLY
        OCHK-S-INVALID = _octx-assert
    _octx-snapshot=? _octx-assert
    _octx-apply OCHK-S-OK = _octx-assert
    _octx-state OCHK-VALID? _octx-assert
    _octx-state OCHK.SOURCE-COUNT @ 1 = _octx-assert
    _octx-state OCHK.OBSERVATION-COUNT @ 2 = _octx-assert
    _octx-state OCHK.KEY-COUNT @ 2 = _octx-assert
    _octx-head DUP OCS.STATE @ OCHK-ATTEMPT-SUCCEEDED = _octx-assert
    DUP OCS.NEW-COUNT @ 2 = _octx-assert
    DUP OCS.REVISED-COUNT @ 0= _octx-assert
    DUP OCS.UNCHANGED-COUNT @ 0= _octx-assert
    DUP OCS.DETAIL @ 42 = _octx-assert
    DUP OCS.HTTP-STATUS @ 200 = _octx-assert
    OCS.EFFECTIVE$ S" https://feed.example/feed.json" STR-STR= _octx-assert
    0 _octx-state OCHK-OBSERVATION-NTH DUP 0<> _octx-assert
    DUP OCO.REVISION @ 1 = _octx-assert
    DUP OCO.ID _octx-first-id RID-COPY
    DUP _octx-state OCHK-OBSERVATION-TITLE$ S" First title" STR-STR=
        _octx-assert
    _octx-state OCHK-OBSERVATION-CONTENT$ S" First body" STR-STR=
        _octx-assert
    _octx-stack ;

: _octx-test-unchanged  ( -- )
    _octx-begin OCHK-S-OK = _octx-assert
    _octx-apply OCHK-S-OK = _octx-assert
    _octx-state OCHK-VALID? _octx-assert
    _octx-state OCHK.OBSERVATION-COUNT @ 2 = _octx-assert
    _octx-state OCHK.KEY-COUNT @ 2 = _octx-assert
    _octx-head DUP OCS.NEW-COUNT @ 0= _octx-assert
    DUP OCS.REVISED-COUNT @ 0= _octx-assert
    OCS.UNCHANGED-COUNT @ 2 = _octx-assert
    0 _octx-state OCHK-OBSERVATION-NTH OCO.ID
        _octx-first-id RID= _octx-assert
    0 _octx-state OCHK-KEY-NTH OCK.LAST-SEEN-SEQUENCE @
        _octx-state OCHK.SEQUENCE @ = _octx-assert
    _octx-stack ;

: _octx-test-revision  ( -- )
    _octx-candidate-1-changed!
    _octx-begin OCHK-S-OK = _octx-assert
    _octx-apply OCHK-S-OK = _octx-assert
    _octx-state OCHK-VALID? _octx-assert
    _octx-state OCHK.OBSERVATION-COUNT @ 3 = _octx-assert
    _octx-head DUP OCS.NEW-COUNT @ 0= _octx-assert
    DUP OCS.REVISED-COUNT @ 1 = _octx-assert
    OCS.UNCHANGED-COUNT @ 1 = _octx-assert
    2 _octx-state OCHK-OBSERVATION-NTH DUP OCO.REVISION @ 2 = _octx-assert
    DUP OCO.ID _octx-first-id RID= _octx-assert
    _octx-state OCHK-OBSERVATION-CONTENT$
        S" First body revised" STR-STR= _octx-assert
    _octx-stack ;

: _octx-test-failure-preserves-observations  ( -- )
    _octx-state OCHK-OBSERVATION-OFFSET +
    _octx-snapshot OCHK-OBSERVATION-OFFSET +
    OCHK-OBSERVATION-MAX OCHK-OBSERVATION-SIZE * CMOVE
    _octx-begin OCHK-S-OK = _octx-assert
    _octx-source 1 OCHK-ATTEMPT-FAILED OCHK-O-HTTP 17 503 0 91 0
        _octx-state OCHK-TERMINAL OCHK-S-OK = _octx-assert
    _octx-state OCHK-VALID? _octx-assert
    _octx-head DUP OCS.STATE @ OCHK-ATTEMPT-FAILED = _octx-assert
    DUP OCS.OUTCOME @ OCHK-O-HTTP = _octx-assert
    DUP OCS.DETAIL @ 17 = _octx-assert
    DUP OCS.HTTP-STATUS @ 503 = _octx-assert
    OCS.XIO-ERROR @ 91 = _octx-assert
    _octx-state OCHK-OBSERVATION-OFFSET +
    OCHK-OBSERVATION-MAX OCHK-OBSERVATION-SIZE *
    _octx-snapshot OCHK-OBSERVATION-OFFSET +
    OCHK-OBSERVATION-MAX OCHK-OBSERVATION-SIZE * COMPARE 0= _octx-assert
    _octx-stack ;

: _octx-test-recovery  ( -- )
    _octx-begin OCHK-S-OK = _octx-assert
    _octx-state OCHK-RECOVER-INDETERMINATE
    OCHK-S-OK = SWAP 1 = AND _octx-assert
    _octx-state OCHK-VALID? _octx-assert
    _octx-head DUP OCS.STATE @ OCHK-ATTEMPT-INDETERMINATE = _octx-assert
    OCS.OUTCOME @ OCHK-O-INDETERMINATE = _octx-assert
    _octx-stack ;

: _octx-test-rejected-transaction  ( -- )
    _octx-begin OCHK-S-OK = _octx-assert
    _octx-state _octx-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    0 _octx-candidate OCC.NATIVE-A @ 0 _octx-candidate OCC.NATIVE-U @
    1 _octx-candidate OCC.NATIVE-U ! 1 _octx-candidate OCC.NATIVE-A !
    0 _octx-candidate OCC.FORMAT @ 1 _octx-candidate OCC.FORMAT !
    _octx-apply OCHK-S-INVALID = _octx-assert
    _octx-state STREAMS-OBSERVATION-CHECKPOINT-SIZE
    _octx-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE COMPARE 0= _octx-assert
    _octx-source 1 OCHK-ATTEMPT-CANCELLED OCHK-O-CANCELLED 0 0 0 0 0
        _octx-state OCHK-TERMINAL OCHK-S-OK = _octx-assert
    _octx-candidate-2!
    _octx-stack ;

: _octx-test-corruption  ( -- )
    _octx-state _octx-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _octx-state OCHK.BLOB DUP C@ 1 XOR SWAP C!
    _octx-state OCHK-VALID? 0= _octx-assert
    _octx-snapshot _octx-state STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _octx-state OCHK-VALID? _octx-assert
    _octx-stack ;

: _octx-run  ( -- )
    ." [octx] begin" CR
    0 _octx-fails ! 0 _octx-checks ! DEPTH _octx-depth !
    STREAMS-OBSERVATION-CHECKPOINT-SIZE ALLOCATE DUP IF
        2DROP ." STREAMS OBSERVATION CONTRACTS FAIL allocation" CR EXIT
    THEN DROP _octx-state-a !
    STREAMS-OBSERVATION-CHECKPOINT-SIZE ALLOCATE DUP IF
        2DROP _octx-state FREE
        ." STREAMS OBSERVATION CONTRACTS FAIL allocation" CR EXIT
    THEN DROP _octx-snapshot-a !
    OCHK-BATCH-MAX OCHK-CANDIDATE-SIZE * ALLOCATE DUP IF
        2DROP _octx-snapshot FREE _octx-state FREE
        ." STREAMS OBSERVATION CONTRACTS FAIL allocation" CR EXIT
    THEN DROP _octx-candidates-a !
    101 _octx-source _octx-id!
    202 _octx-namespace _octx-id!
    _octx-candidate-1! _octx-candidate-2!
    ." [octx] init" CR
    _octx-test-init
    ." [octx] aliases" CR
    _octx-test-begin-alias-rejection
    ." [octx] first" CR
    _octx-test-first-apply
    ." [octx] unchanged" CR
    _octx-test-unchanged
    ." [octx] revision" CR
    _octx-test-revision
    ." [octx] failure" CR
    _octx-test-failure-preserves-observations
    ." [octx] recovery" CR
    _octx-test-recovery
    ." [octx] rejection" CR
    _octx-test-rejected-transaction
    ." [octx] corruption" CR
    _octx-test-corruption
    _octx-fails @ 0= IF
        ." STREAMS OBSERVATION CONTRACTS PASS " _octx-checks @ .
    ELSE
        ." STREAMS OBSERVATION CONTRACTS FAIL " _octx-fails @ .
        ." / " _octx-checks @ .
    THEN CR
    _octx-candidates FREE _octx-snapshot FREE _octx-state FREE
    0 _octx-candidates-a ! 0 _octx-snapshot-a ! 0 _octx-state-a ! ;
