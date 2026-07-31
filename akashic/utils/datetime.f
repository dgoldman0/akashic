\ =====================================================================
\  datetime.f - Checked, state-free UTC calendar and timestamp support
\ =====================================================================
\  All public scalar units are explicit.  Calendar conversion owns no
\  mutable module state, and bounded formatters qualify the caller's full
\  destination span before publishing an exact, non-truncated result.
\
\  Supported civil range: 1970-01-01 through 9999-12-31 UTC.
\ =====================================================================

REQUIRE caller-span.f

PROVIDED akashic-datetime

0 CONSTANT DT-S-OK
1 CONSTANT DT-S-INVALID
2 CONSTANT DT-S-CAPACITY
3 CONSTANT DT-S-SYNTAX
4 CONSTANT DT-S-RANGE
5 CONSTANT DT-S-PROTECTED
6 CONSTANT DT-S-PLATFORM
7 CONSTANT DT-S-INTERNAL

10 CONSTANT DT-DATE-S-LENGTH
20 CONSTANT DT-RFC3339-UTC-S-LENGTH

253402300799 CONSTANT DT-EPOCH-S-MAX

86400 CONSTANT _DT-SECONDS-PER-DAY
3600 CONSTANT _DT-SECONDS-PER-HOUR
60 CONSTANT _DT-SECONDS-PER-MINUTE

: DT-STATUS-VALID?  ( status -- flag )
    DUP DT-S-OK >= SWAP DT-S-INTERNAL <= AND ;

: _DT-3DUP  ( x1 x2 x3 -- x1 x2 x3 x1 x2 x3 )
    2 PICK 2 PICK 2 PICK ;

: _DT-3DROP  ( x1 x2 x3 -- )
    DROP 2DROP ;

: _DT-YEAR-VALID?  ( year -- flag )
    DUP 1970 >= SWAP 9999 <= AND ;

: _DT-MONTH-VALID?  ( month -- flag )
    DUP 1 >= SWAP 12 <= AND ;

: _DT-EPOCH-S-VALID?  ( epoch-s -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    DT-EPOCH-S-MAX <= ;

: _DT-LEAP?  ( year -- flag )
    DUP 400 MOD 0= IF DROP -1 EXIT THEN
    DUP 100 MOD 0= IF DROP 0 EXIT THEN
    4 MOD 0= ;

: _DT-MONTH-DAYS  ( year month -- days )
    DUP 2 = IF
        DROP _DT-LEAP? IF 29 ELSE 28 THEN EXIT
    THEN
    DUP 4 = OVER 6 = OR OVER 9 = OR OVER 11 = OR IF
        2DROP 30
    ELSE
        2DROP 31
    THEN ;

: DT-MONTH-DAYS  ( year month -- days status )
    OVER _DT-YEAR-VALID? 0= IF 2DROP 0 DT-S-RANGE EXIT THEN
    DUP _DT-MONTH-VALID? 0= IF 2DROP 0 DT-S-SYNTAX EXIT THEN
    _DT-MONTH-DAYS DT-S-OK ;

: _DT-YMD-VALID?  ( year month day -- flag )
    2 PICK _DT-YEAR-VALID? 0= IF _DT-3DROP 0 EXIT THEN
    OVER _DT-MONTH-VALID? 0= IF _DT-3DROP 0 EXIT THEN
    DUP 1 < IF _DT-3DROP 0 EXIT THEN
    2 PICK 2 PICK _DT-MONTH-DAYS >
    >R 2DROP R> 0= ;

\ Howard Hinnant's civil-date transform, specialized to nonnegative Unix
\ days.  Recomputing the small pure intermediates keeps the implementation
\ state-free and constant-time without caller workspace.
: _DT-ERA  ( days -- era )
    719468 + 146097 / ;

: _DT-DAY-OF-ERA  ( days -- day-of-era )
    DUP 719468 + SWAP _DT-ERA 146097 * - ;

: _DT-YEAR-OF-ERA  ( days -- year-of-era )
    _DT-DAY-OF-ERA
    DUP >R
    DUP 1460 / -
    R@ 36524 / +
    R> 146096 / -
    365 / ;

: _DT-CIVIL-YEAR  ( days -- year )
    DUP _DT-YEAR-OF-ERA SWAP _DT-ERA 400 * + ;

: _DT-DAY-OF-YEAR  ( days -- day-of-year )
    DUP _DT-YEAR-OF-ERA
    DUP 365 * OVER 4 / +
    SWAP 100 / -
    SWAP _DT-DAY-OF-ERA SWAP - ;

: _DT-MARCH-MONTH  ( days -- march-month )
    _DT-DAY-OF-YEAR 5 * 2 + 153 / ;

: _DT-DAYS>YMD  ( days -- year month day )
    DUP _DT-CIVIL-YEAR
    OVER _DT-MARCH-MONTH
    DUP 10 < IF 3 + ELSE 9 - THEN
    DUP 2 <= IF SWAP 1+ SWAP THEN
    2 PICK _DT-DAY-OF-YEAR
    3 PICK _DT-MARCH-MONTH 153 * 2 + 5 / - 1+
    >R ROT DROP R> ;

: _DT-YEAR-DAY>ERA-DAY  ( year-of-era day-of-year -- day-of-era )
    >R
    DUP 365 * OVER 4 / +
    SWAP 100 / -
    R> + ;

: _DT-YMD>DAYS  ( year month day -- days )
    1- >R
    DUP 2 <= IF SWAP 1- SWAP THEN
    OVER 400 /
    2 PICK OVER 400 * -
    2 PICK DUP 2 > IF 3 - ELSE 9 + THEN
    153 * 2 + 5 / R> +
    _DT-YEAR-DAY>ERA-DAY
    SWAP 146097 * + 719468 -
    >R 2DROP R> ;

: DT-EPOCH-S>YMD  ( epoch-s -- year month day status )
    DUP _DT-EPOCH-S-VALID? 0= IF
        DROP 0 0 0 DT-S-RANGE EXIT
    THEN
    _DT-SECONDS-PER-DAY / _DT-DAYS>YMD DT-S-OK ;

: DT-YMD>EPOCH-S  ( year month day -- epoch-s status )
    2 PICK _DT-YEAR-VALID? 0= IF
        _DT-3DROP 0 DT-S-RANGE EXIT
    THEN
    _DT-3DUP _DT-YMD-VALID? 0= IF
        _DT-3DROP 0 DT-S-SYNTAX EXIT
    THEN
    _DT-YMD>DAYS _DT-SECONDS-PER-DAY * DT-S-OK ;

: _DT-PUT-2  ( value destination -- )
    >R
    DUP 10 / [CHAR] 0 + R@ C!
    10 MOD [CHAR] 0 + R> 1+ C! ;

: _DT-PUT-4  ( value destination -- )
    >R
    DUP 1000 / [CHAR] 0 + R@ C!
    DUP 1000 MOD 100 / [CHAR] 0 + R@ 1+ C!
    DUP 100 MOD 10 / [CHAR] 0 + R@ 2 + C!
    10 MOD [CHAR] 0 + R> 3 + C! ;

: _DT-WRITE-DATE  ( epoch-s destination -- )
    >R
    _DT-SECONDS-PER-DAY / _DT-DAYS>YMD
    ROT R@ _DT-PUT-4
    SWAP R@ 5 + _DT-PUT-2
    R@ 8 + _DT-PUT-2
    [CHAR] - R@ 4 + C!
    [CHAR] - R@ 7 + C!
    R> DROP ;

: _DT-EPOCH-S>HMS  ( epoch-s -- hour minute second )
    _DT-SECONDS-PER-DAY MOD
    DUP _DT-SECONDS-PER-HOUR / SWAP _DT-SECONDS-PER-HOUR MOD
    DUP _DT-SECONDS-PER-MINUTE / SWAP _DT-SECONDS-PER-MINUTE MOD ;

: _DT-WRITE-TIME  ( epoch-s destination -- )
    >R
    _DT-EPOCH-S>HMS
    ROT R@ _DT-PUT-2
    SWAP R@ 3 + _DT-PUT-2
    R@ 6 + _DT-PUT-2
    [CHAR] : R@ 2 + C!
    [CHAR] : R@ 5 + C!
    R> DROP ;

: _DT-WRITE-RFC3339  ( epoch-s destination -- )
    >R
    DUP R@ _DT-WRITE-DATE
    R@ 11 + _DT-WRITE-TIME
    [CHAR] T R@ 10 + C!
    [CHAR] Z R@ 19 + C!
    R> DROP ;

: _DT-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP DT-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP DT-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF DROP DT-S-PROTECTED EXIT THEN
    DROP DT-S-PLATFORM ;

: _DT-FORMAT-STATUS  ( epoch-s destination capacity required -- status )
    >R
    2 PICK _DT-EPOCH-S-VALID? 0= IF
        _DT-3DROP R> DROP DT-S-RANGE EXIT
    THEN
    DUP 0< IF
        _DT-3DROP R> DROP DT-S-INVALID EXIT
    THEN
    DUP R@ < IF
        _DT-3DROP R> DROP DT-S-CAPACITY EXIT
    THEN
    2DUP CALLER-SPAN-STATUS _DT-CALLER>STATUS >R
    _DT-3DROP R> R> DROP ;

: DT-DATE-S  ( epoch-s destination capacity -- written status )
    _DT-3DUP DT-DATE-S-LENGTH _DT-FORMAT-STATUS
    DUP IF >R _DT-3DROP 0 R> EXIT THEN DROP
    DROP _DT-WRITE-DATE DT-DATE-S-LENGTH DT-S-OK ;

: DT-RFC3339-UTC-S  ( epoch-s destination capacity -- written status )
    _DT-3DUP DT-RFC3339-UTC-S-LENGTH _DT-FORMAT-STATUS
    DUP IF >R _DT-3DROP 0 R> EXIT THEN DROP
    DROP _DT-WRITE-RFC3339 DT-RFC3339-UTC-S-LENGTH DT-S-OK ;

: DT-NOW-MS  ( -- epoch-ms )
    EPOCH@ ;

: DT-NOW-S  ( -- epoch-s )
    DT-NOW-MS 1000 / ;
