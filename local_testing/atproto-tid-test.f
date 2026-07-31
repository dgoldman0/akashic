\ Focused executable contract for caller-owned AT Protocol TID clocks.

PROVIDED atproto-tid-test

VARIABLE _tidt-failed
VARIABLE _tidt-check

CREATE _tidt-clock-a-raw TID-CLOCK-SIZE 7 + ALLOT
CREATE _tidt-clock-b-raw TID-CLOCK-SIZE 7 + ALLOT
CREATE _tidt-out-a 14 ALLOT
CREATE _tidt-out-b 14 ALLOT
CREATE _tidt-adjacent-raw TID-CLOCK-SIZE TID-LENGTH + 7 + ALLOT

: _tidt-clock-a  ( -- clock )
    _tidt-clock-a-raw 7 + -8 AND ;

: _tidt-clock-b  ( -- clock )
    _tidt-clock-b-raw 7 + -8 AND ;

: _tidt-adjacent  ( -- clock )
    _tidt-adjacent-raw 7 + -8 AND ;

: _tidt-assert  ( flag -- )
    1 _tidt-check +!
    0= IF
        -1 _tidt-failed !
        ." AT TID ASSERT " _tidt-check @ . CR
    THEN ;

: _tidt-status  ( actual expected -- )
    = _tidt-assert ;

: _tidt-test-vocabulary  ( -- )
    TID-LENGTH 13 = _tidt-assert
    TID-CLOCK-SIZE 24 = _tidt-assert
    TID-S-OK TID-STATUS-VALID? _tidt-assert
    TID-S-EXHAUSTED TID-STATUS-VALID? _tidt-assert
    -1 TID-STATUS-VALID? 0= _tidt-assert
    TID-S-EXHAUSTED 1+ TID-STATUS-VALID? 0= _tidt-assert ;

: _tidt-test-validation  ( -- )
    S" 2222222222222" TID-VALIDATE TID-S-OK _tidt-status
    S" j222222222222" TID-VALIDATE TID-S-OK _tidt-status
    S" k222222222222" TID-VALIDATE TID-S-SYNTAX _tidt-status
    S" 2222222222220" TID-VALIDATE TID-S-SYNTAX _tidt-status
    S" 222222222222A" TID-VALIDATE TID-S-SYNTAX _tidt-status
    S" 222222222222" TID-VALIDATE TID-S-SYNTAX _tidt-status
    S" 22222222222222" TID-VALIDATE TID-S-CAPACITY _tidt-status
    0 13 TID-VALIDATE TID-S-INVALID _tidt-status
    _tidt-out-a -1 TID-VALIDATE TID-S-INVALID _tidt-status
    S" 2222222222222" TID-VALID? _tidt-assert ;

: _tidt-test-clock-init  ( -- )
    _tidt-clock-a TID-CLOCK-SIZE 90 FILL
    -1 _tidt-clock-a TID-CLOCK-INIT TID-S-RANGE _tidt-status
    _tidt-clock-a C@ 90 = _tidt-assert
    1024 _tidt-clock-a TID-CLOCK-INIT TID-S-RANGE _tidt-status
    _tidt-clock-a C@ 90 = _tidt-assert
    0 0 TID-CLOCK-INIT TID-S-INVALID _tidt-status
    0 _tidt-clock-a 1+ TID-CLOCK-INIT TID-S-INVALID _tidt-status

    0 _tidt-clock-a TID-CLOCK-INIT TID-S-OK _tidt-status
    _tidt-clock-a TID-CLOCK-VALID? _tidt-assert
    _tidt-clock-a _TID-CLOCK-ID-OFF + @ 0= _tidt-assert
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ -1 = _tidt-assert
    1023 _tidt-clock-b TID-CLOCK-INIT TID-S-OK _tidt-status
    _tidt-clock-b TID-CLOCK-VALID? _tidt-assert ;

: _tidt-test-generation  ( -- )
    0 _tidt-clock-a TID-CLOCK-INIT TID-S-OK _tidt-status
    _tidt-out-a 14 165 FILL
    0 _tidt-out-a 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-OK _tidt-status
    _tidt-out-a 13 S" 2222222222222" COMPARE 0= _tidt-assert
    _tidt-out-a 13 + C@ 165 = _tidt-assert
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ 0= _tidt-assert

    0 _tidt-clock-a TID-CLOCK-INIT TID-S-OK _tidt-status
    1 _tidt-out-a 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-OK _tidt-status
    _tidt-out-a 13 S" 222222222zc22" COMPARE 0= _tidt-assert
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ 1000 = _tidt-assert

    1 _tidt-out-b 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-OK _tidt-status
    _tidt-out-a _tidt-out-b TID-COMPARE -1 = _tidt-assert
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ 1001 = _tidt-assert
    0 _tidt-out-a 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-OK _tidt-status
    _tidt-out-b _tidt-out-a TID-COMPARE -1 = _tidt-assert
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ 1002 = _tidt-assert
    _tidt-out-a _tidt-out-a TID-COMPARE 0= _tidt-assert ;

: _tidt-test-independent-clocks  ( -- )
    0 _tidt-clock-a TID-CLOCK-INIT TID-S-OK _tidt-status
    1 _tidt-clock-b TID-CLOCK-INIT TID-S-OK _tidt-status
    500 _tidt-out-a 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-OK _tidt-status
    500 _tidt-out-b 13 _tidt-clock-b TID-CLOCK-NEXT-MS
    TID-S-OK _tidt-status
    _tidt-out-a _tidt-out-b TID-COMPARE -1 = _tidt-assert
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ 500000 = _tidt-assert
    _tidt-clock-b _TID-CLOCK-LAST-OFF + @ 500000 = _tidt-assert ;

: _tidt-test-failure-atomicity  ( -- )
    0 _tidt-clock-a TID-CLOCK-INIT TID-S-OK _tidt-status
    _tidt-out-a 14 165 FILL
    0 _tidt-out-a 12 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-CAPACITY _tidt-status
    _tidt-out-a C@ 165 = _tidt-assert
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ -1 = _tidt-assert

    -1 _tidt-out-a 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-RANGE _tidt-status
    _tidt-out-a C@ 165 = _tidt-assert
    _TID-EPOCH-MS-MAX 1+ _tidt-out-a 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-RANGE _tidt-status
    _tidt-clock-a _TID-CLOCK-LAST-OFF + @ -1 = _tidt-assert

    0 _tidt-adjacent TID-CLOCK-INIT TID-S-OK _tidt-status
    0 _tidt-adjacent TID-CLOCK-SIZE _tidt-adjacent TID-CLOCK-NEXT-MS
    TID-S-ALIAS _tidt-status
    _tidt-adjacent TID-CLOCK-VALID? _tidt-assert
    0 _tidt-adjacent TID-CLOCK-SIZE + TID-LENGTH
    _tidt-adjacent TID-CLOCK-NEXT-MS TID-S-OK _tidt-status

    0 _tidt-clock-a TID-CLOCK-INIT TID-S-OK _tidt-status
    0 _tidt-clock-a !
    _tidt-clock-a TID-CLOCK-VALID? 0= _tidt-assert
    0 _tidt-out-a 13 _tidt-clock-a TID-CLOCK-NEXT-MS
    TID-S-INVALID _tidt-status ;

: _tidt-test-exhaustion  ( -- )
    1023 _tidt-clock-b TID-CLOCK-INIT TID-S-OK _tidt-status
    _TID-MICROSECOND-MAX 1- _tidt-clock-b _TID-CLOCK-LAST-OFF + !
    0 _tidt-out-a 13 _tidt-clock-b TID-CLOCK-NEXT-MS
    TID-S-OK _tidt-status
    _tidt-out-a 13 S" bzzzzzzzzzzzz" COMPARE 0= _tidt-assert
    _tidt-clock-b _TID-CLOCK-LAST-OFF + @
    _TID-MICROSECOND-MAX = _tidt-assert
    _tidt-out-b 14 165 FILL
    0 _tidt-out-b 13 _tidt-clock-b TID-CLOCK-NEXT-MS
    TID-S-EXHAUSTED _tidt-status
    _tidt-out-b C@ 165 = _tidt-assert ;

: _TIDT-RUN  ( -- )
    0 _tidt-failed !
    0 _tidt-check !
    _tidt-test-vocabulary
    _tidt-test-validation
    _tidt-test-clock-init
    _tidt-test-generation
    _tidt-test-independent-clocks
    _tidt-test-failure-atomicity
    _tidt-test-exhaustion
    DEPTH 0= _tidt-assert
    _tidt-failed @ IF
        ." AT TID FAIL" CR
    ELSE
        ." AT TID PASS" CR
    THEN ;
