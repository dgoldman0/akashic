\ Focused executable contract for the checked, state-free datetime module.

PROVIDED datetime-test

VARIABLE _dtt-failed

CREATE _dtt-a 32 ALLOT
CREATE _dtt-b 32 ALLOT

: _dtt-assert  ( flag -- )
    0= IF
        -1 _dtt-failed !
        ." DATETIME ASSERT" CR
    THEN ;

: _dtt-status  ( actual expected -- )
    = _dtt-assert ;

: _dtt-test-statuses  ( -- )
    DT-S-OK DT-STATUS-VALID? _dtt-assert
    DT-S-INTERNAL DT-STATUS-VALID? _dtt-assert
    -1 DT-STATUS-VALID? 0= _dtt-assert
    DT-S-INTERNAL 1+ DT-STATUS-VALID? 0= _dtt-assert
    DT-DATE-S-LENGTH 10 = _dtt-assert
    DT-RFC3339-UTC-S-LENGTH 20 = _dtt-assert ;

: _dtt-test-calendar  ( -- )
    2000 2 DT-MONTH-DAYS
    DT-S-OK _dtt-status 29 = _dtt-assert
    2100 2 DT-MONTH-DAYS
    DT-S-OK _dtt-status 28 = _dtt-assert
    2024 4 DT-MONTH-DAYS
    DT-S-OK _dtt-status 30 = _dtt-assert
    2024 13 DT-MONTH-DAYS
    DT-S-SYNTAX _dtt-status 0= _dtt-assert
    10000 1 DT-MONTH-DAYS
    DT-S-RANGE _dtt-status 0= _dtt-assert

    1970 1 1 DT-YMD>EPOCH-S
    DT-S-OK _dtt-status 0= _dtt-assert
    2000 2 29 DT-YMD>EPOCH-S
    DT-S-OK _dtt-status 951782400 = _dtt-assert
    2023 2 29 DT-YMD>EPOCH-S
    DT-S-SYNTAX _dtt-status 0= _dtt-assert
    1969 12 31 DT-YMD>EPOCH-S
    DT-S-RANGE _dtt-status 0= _dtt-assert

    0 DT-EPOCH-S>YMD
    DT-S-OK _dtt-status
    1 = _dtt-assert 1 = _dtt-assert 1970 = _dtt-assert
    951782400 DT-EPOCH-S>YMD
    DT-S-OK _dtt-status
    29 = _dtt-assert 2 = _dtt-assert 2000 = _dtt-assert
    DT-EPOCH-S-MAX DT-EPOCH-S>YMD
    DT-S-OK _dtt-status
    31 = _dtt-assert 12 = _dtt-assert 9999 = _dtt-assert
    -1 DT-EPOCH-S>YMD
    DT-S-RANGE _dtt-status
    0= _dtt-assert 0= _dtt-assert 0= _dtt-assert ;

: _dtt-test-format  ( -- )
    _dtt-a 32 165 FILL
    1718465400 _dtt-a 32 DT-RFC3339-UTC-S
    DT-S-OK _dtt-status 20 = _dtt-assert
    _dtt-a 20 S" 2024-06-15T15:30:00Z" COMPARE 0= _dtt-assert
    _dtt-a 20 + C@ 165 = _dtt-assert

    _dtt-b 32 90 FILL
    951782400 _dtt-b 32 DT-DATE-S
    DT-S-OK _dtt-status 10 = _dtt-assert
    _dtt-b 10 S" 2000-02-29" COMPARE 0= _dtt-assert
    _dtt-b 10 + C@ 90 = _dtt-assert
    _dtt-a 20 S" 2024-06-15T15:30:00Z" COMPARE 0= _dtt-assert

    _dtt-a 32 165 FILL
    0 _dtt-a 19 DT-RFC3339-UTC-S
    DT-S-CAPACITY _dtt-status 0= _dtt-assert
    _dtt-a C@ 165 = _dtt-assert _dtt-a 18 + C@ 165 = _dtt-assert

    0 _dtt-a -1 DT-RFC3339-UTC-S
    DT-S-INVALID _dtt-status 0= _dtt-assert
    -1 _dtt-a 32 DT-RFC3339-UTC-S
    DT-S-RANGE _dtt-status 0= _dtt-assert
    DT-EPOCH-S-MAX 1+ _dtt-a 32 DT-RFC3339-UTC-S
    DT-S-RANGE _dtt-status 0= _dtt-assert
    _dtt-a C@ 165 = _dtt-assert

    DT-EPOCH-S-MAX _dtt-a 32 DT-RFC3339-UTC-S
    DT-S-OK _dtt-status 20 = _dtt-assert
    _dtt-a 20 S" 9999-12-31T23:59:59Z" COMPARE 0= _dtt-assert ;

: _DTT-RUN  ( -- )
    0 _dtt-failed !
    _dtt-test-statuses
    _dtt-test-calendar
    _dtt-test-format
    DEPTH 0= _dtt-assert
    _dtt-failed @ IF
        ." DATETIME FAIL" CR
    ELSE
        ." DATETIME PASS" CR
    THEN ;
