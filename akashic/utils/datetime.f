\ datetime.f — Date/Time Utilities for KDOS / Megapad-64
\
\ Epoch seconds ↔ broken-down time.  ISO 8601 formatting & parsing.
\ No floating point.  Integer-only leap-year calculation.
\
\ BIOS words used:
\   EPOCH@ ( -- epoch-ms-u64 )   reads RTC epoch in milliseconds
\
\ Prefix: DT-   (public API)
\         _DT-  (internal helpers)
\
\ Load with:   REQUIRE datetime.f

PROVIDED akashic-datetime

\ =====================================================================
\  Constants
\ =====================================================================

86400 CONSTANT _DT-SPD          \ seconds per day
3600  CONSTANT _DT-SPH          \ seconds per hour
60    CONSTANT _DT-SPM          \ seconds per minute

\ Days-before-month table (non-leap).  Index 1..12.
\ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334
CREATE _DT-DBM
    0 ,  0 ,  31 ,  59 ,  90 ,  120 ,  151 ,
    181 ,  212 ,  243 ,  273 ,  304 ,  334 ,

\ Days in each month (non-leap).  Index 1..12.
CREATE _DT-DIM
    0 ,  31 ,  28 ,  31 ,  30 ,  31 ,  30 ,
    31 ,  31 ,  30 ,  31 ,  30 ,  31 ,

\ =====================================================================
\  Leap Year
\ =====================================================================

\ DT-LEAP? ( year -- flag )
\   Gregorian leap year test.  -1 = leap, 0 = not leap.
: DT-LEAP?  ( year -- flag )
    DUP 400 MOD 0= IF DROP -1 EXIT THEN
    DUP 100 MOD 0= IF DROP  0 EXIT THEN
    4 MOD 0= IF -1 ELSE 0 THEN ;

\ _DT-DPY ( year -- days )
\   Days in year.
: _DT-DPY  ( year -- days )
    DT-LEAP? IF 366 ELSE 365 THEN ;

\ _DT-DIM@ ( month year -- days )
\   Days in month (1-based), accounting for leap February.
: _DT-DIM@  ( month year -- days )
    SWAP DUP 2 = IF
        DROP DT-LEAP? IF 29 ELSE 28 THEN
    ELSE
        8 * _DT-DIM + @ SWAP DROP
    THEN ;

\ =====================================================================
\  Epoch → Broken-Down
\ =====================================================================

VARIABLE _DT-REM      \ remaining seconds
VARIABLE _DT-DAYS     \ total days from epoch
VARIABLE _DT-Y        \ working year
VARIABLE _DT-M        \ working month

\ _DT-EPOCH>DAYS ( epoch-sec -- days rem )
\   Split epoch seconds into days and remaining seconds.
: _DT-EPOCH>DAYS  ( epoch-sec -- days rem )
    DUP _DT-SPD / SWAP _DT-SPD MOD ;

\ DT-EPOCH>HMS ( epoch -- hour min sec )
\   Unix epoch seconds to hour/minute/second.
: DT-EPOCH>HMS  ( epoch -- hour min sec )
    _DT-SPD MOD
    DUP _DT-SPH /  SWAP _DT-SPH MOD
    DUP _DT-SPM /  SWAP _DT-SPM MOD ;

\ DT-EPOCH>YMD ( epoch -- year month day )
\   Unix epoch seconds to year/month/day.
\   Algorithm: count days from 1970-01-01.
: DT-EPOCH>YMD  ( epoch -- year month day )
    _DT-EPOCH>DAYS DROP       \ days since epoch
    _DT-DAYS !
    1970 _DT-Y !
    \ Advance years
    BEGIN
        _DT-Y @ _DT-DPY  _DT-DAYS @ OVER >= IF
            _DT-DAYS @ SWAP - _DT-DAYS !
            1 _DT-Y +!
            0              \ continue
        ELSE
            DROP -1        \ done
        THEN
    UNTIL
    \ Advance months
    1 _DT-M !
    BEGIN
        _DT-M @ _DT-Y @ _DT-DIM@  _DT-DAYS @ OVER >= IF
            _DT-DAYS @ SWAP - _DT-DAYS !
            1 _DT-M +!
            0
        ELSE
            DROP -1
        THEN
    UNTIL
    _DT-Y @  _DT-M @  _DT-DAYS @ 1+ ;

\ =====================================================================
\  Broken-Down → Epoch
\ =====================================================================

\ DT-YMD>EPOCH ( year month day -- epoch )
\   Year/month/day to Unix epoch at midnight UTC.
VARIABLE _DT-EACC     \ accumulator

: DT-YMD>EPOCH  ( year month day -- epoch )
    1- _DT-REM !             \ day-of-month → 0-based in _DT-REM
    _DT-M !                  \ month
    _DT-Y !                  \ year
    0 _DT-EACC !
    \ Add days for complete years 1970..year-1
    1970
    BEGIN
        DUP _DT-Y @ <
    WHILE
        DUP _DT-DPY _DT-EACC @ + _DT-EACC !
        1+
    REPEAT DROP
    \ Add days for complete months 1..month-1
    _DT-M @ 8 * _DT-DBM + @  _DT-EACC @ + _DT-EACC !
    \ Leap day adjustment: if month > 2 and leap year
    _DT-M @ 2 > IF
        _DT-Y @ DT-LEAP? IF 1 _DT-EACC +! THEN
    THEN
    \ Add remaining days
    _DT-REM @ _DT-EACC +!
    _DT-EACC @ _DT-SPD * ;

\ =====================================================================
\  Formatting — Internal Helpers
\ =====================================================================

VARIABLE _DT-DST      \ destination buffer pointer
VARIABLE _DT-MAX      \ max buffer size
VARIABLE _DT-POS      \ current write position

\ _DT-EMIT ( c -- )  Write one char to output buffer.
: _DT-EMIT  ( c -- )
    _DT-POS @ _DT-MAX @ < IF
        _DT-DST @ _DT-POS @ + C!
        1 _DT-POS +!
    ELSE DROP THEN ;

\ _DT-2D ( n -- )  Write 2-digit zero-padded number.
: _DT-2D  ( n -- )
    DUP 10 < IF
        48 _DT-EMIT              \ '0'
        48 + _DT-EMIT
    ELSE
        DUP 10 / 48 + _DT-EMIT
        10 MOD  48 + _DT-EMIT
    THEN ;

\ _DT-4D ( n -- )  Write 4-digit zero-padded year.
: _DT-4D  ( n -- )
    DUP 1000 / 48 + _DT-EMIT
    DUP 1000 MOD 100 / 48 + _DT-EMIT
    DUP 100 MOD 10 / 48 + _DT-EMIT
    10 MOD 48 + _DT-EMIT ;

\ =====================================================================
\  Formatting — Public API
\ =====================================================================

\ DT-DATE ( epoch dst max -- written )
\   Format epoch as "2024-06-15".  Returns bytes written.
: DT-DATE  ( epoch dst max -- written )
    _DT-MAX ! _DT-DST ! 0 _DT-POS !
    DT-EPOCH>YMD          \ ( year month day )
    ROT _DT-4D            \ year
    45 _DT-EMIT           \ '-'
    SWAP _DT-2D           \ month
    45 _DT-EMIT           \ '-'
    _DT-2D                \ day
    _DT-POS @ ;

\ DT-TIME ( epoch dst max -- written )
\   Format epoch as "14:30:00".  Returns bytes written.
: DT-TIME  ( epoch dst max -- written )
    _DT-MAX ! _DT-DST ! 0 _DT-POS !
    DT-EPOCH>HMS          \ ( hour min sec )
    ROT _DT-2D            \ hour
    58 _DT-EMIT           \ ':'
    SWAP _DT-2D           \ min
    58 _DT-EMIT           \ ':'
    _DT-2D                \ sec
    _DT-POS @ ;

\ DT-ISO8601 ( epoch dst max -- written )
\   Format epoch as "2024-06-15T14:30:00Z".  Returns bytes written.
VARIABLE _DT-ISOE      \ stash epoch for second pass

: DT-ISO8601  ( epoch dst max -- written )
    _DT-MAX ! _DT-DST ! 0 _DT-POS !
    DUP _DT-ISOE !
    DT-EPOCH>YMD          \ ( year month day )
    ROT _DT-4D
    45 _DT-EMIT
    SWAP _DT-2D
    45 _DT-EMIT
    _DT-2D
    84 _DT-EMIT           \ 'T'
    _DT-ISOE @
    DT-EPOCH>HMS          \ ( hour min sec )
    ROT _DT-2D
    58 _DT-EMIT
    SWAP _DT-2D
    58 _DT-EMIT
    _DT-2D
    90 _DT-EMIT           \ 'Z'
    _DT-POS @ ;

\ =====================================================================
\  Parsing
\ =====================================================================

VARIABLE _DTP-PTR      \ parse pointer
VARIABLE _DTP-END      \ end of input
VARIABLE _DTP-OK       \ parse success flag

\ _DTP-CH ( -- c | -1 )  Read next char, advance pointer.
: _DTP-CH  ( -- c | -1 )
    _DTP-PTR @ _DTP-END @ >= IF -1 EXIT THEN
    _DTP-PTR @ C@  1 _DTP-PTR +! ;

\ _DTP-DIGIT ( -- n )  Read one ASCII digit (0-9).  Sets _DTP-OK to 0 on error.
: _DTP-DIGIT  ( -- n )
    _DTP-OK @ 0= IF 0 EXIT THEN
    _DTP-CH DUP 48 < OVER 57 > OR IF
        DROP 0 _DTP-OK ! 0
    ELSE 48 - THEN ;

\ _DTP-2D ( -- n )  Read two-digit number.
: _DTP-2D  ( -- n )
    _DTP-DIGIT 10 *  _DTP-DIGIT + ;

\ _DTP-4D ( -- n )  Read four-digit number.
: _DTP-4D  ( -- n )
    _DTP-DIGIT 1000 *
    _DTP-DIGIT 100 * +
    _DTP-DIGIT 10 * +
    _DTP-DIGIT + ;

\ _DTP-EXPECT ( c -- )  Expect specific character.
: _DTP-EXPECT  ( c -- )
    _DTP-OK @ 0= IF DROP EXIT THEN
    _DTP-CH OVER <> IF 0 _DTP-OK ! THEN DROP ;

\ DT-PARSE-ISO ( addr len -- epoch ior )
\   Parse "2024-06-15T14:30:00Z" to epoch seconds.
\   ior = 0 success, -1 failure.
: DT-PARSE-ISO  ( addr len -- epoch ior )
    OVER + _DTP-END !  _DTP-PTR !
    -1 _DTP-OK !
    _DTP-4D                  \ year
    45 _DTP-EXPECT           \ '-'
    _DTP-2D                  \ month
    45 _DTP-EXPECT           \ '-'
    _DTP-2D                  \ day
    84 _DTP-EXPECT           \ 'T'
    _DTP-OK @ 0= IF 2DROP DROP 0 -1 EXIT THEN
    \ ( year month day )  on stack — already in right order
    DT-YMD>EPOCH             \ epoch at midnight
    _DTP-2D _DT-SPH *  +     \ + hours
    58 _DTP-EXPECT            \ ':'
    _DTP-2D _DT-SPM *  +     \ + minutes
    58 _DTP-EXPECT            \ ':'
    _DTP-2D +                 \ + seconds
    \ Optional trailing 'Z'
    _DTP-PTR @ _DTP-END @ < IF
        _DTP-PTR @ C@ 90 = IF 1 _DTP-PTR +! THEN  \ skip 'Z'
    THEN
    _DTP-OK @ IF 0 ELSE DROP 0 -1 THEN ;

\ =====================================================================
\  RTC / Current Time
\ =====================================================================

\ DT-NOW-MS ( -- epoch-ms )
\   Read RTC hardware, return epoch milliseconds (64-bit).
: DT-NOW-MS  ( -- epoch-ms )
    EPOCH@ ;

\ DT-NOW-S ( -- epoch )
\   Read RTC hardware, return epoch seconds (integer division).
: DT-NOW-S  ( -- epoch )
    DT-NOW-MS 1000 / ;

\ DT-NOW ( -- epoch )
\   Alias for DT-NOW-S.  Default resolution = seconds.
: DT-NOW  ( -- epoch )
    DT-NOW-S ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _datetime-guard

' DT-LEAP?        CONSTANT _dt-leap-q-xt
' DT-EPOCH>HMS    CONSTANT _dt-epoch-to-hms-xt
' DT-EPOCH>YMD    CONSTANT _dt-epoch-to-ymd-xt
' DT-YMD>EPOCH    CONSTANT _dt-ymd-to-epoch-xt
' DT-DATE         CONSTANT _dt-date-xt
' DT-TIME         CONSTANT _dt-time-xt
' DT-ISO8601      CONSTANT _dt-iso8601-xt
' DT-PARSE-ISO    CONSTANT _dt-parse-iso-xt
' DT-NOW-MS       CONSTANT _dt-now-ms-xt
' DT-NOW-S        CONSTANT _dt-now-s-xt
' DT-NOW          CONSTANT _dt-now-xt

: DT-LEAP?        _dt-leap-q-xt _datetime-guard WITH-GUARD ;
: DT-EPOCH>HMS    _dt-epoch-to-hms-xt _datetime-guard WITH-GUARD ;
: DT-EPOCH>YMD    _dt-epoch-to-ymd-xt _datetime-guard WITH-GUARD ;
: DT-YMD>EPOCH    _dt-ymd-to-epoch-xt _datetime-guard WITH-GUARD ;
: DT-DATE         _dt-date-xt _datetime-guard WITH-GUARD ;
: DT-TIME         _dt-time-xt _datetime-guard WITH-GUARD ;
: DT-ISO8601      _dt-iso8601-xt _datetime-guard WITH-GUARD ;
: DT-PARSE-ISO    _dt-parse-iso-xt _datetime-guard WITH-GUARD ;
: DT-NOW-MS       _dt-now-ms-xt _datetime-guard WITH-GUARD ;
: DT-NOW-S        _dt-now-s-xt _datetime-guard WITH-GUARD ;
: DT-NOW          _dt-now-xt _datetime-guard WITH-GUARD ;
[THEN] [THEN]
