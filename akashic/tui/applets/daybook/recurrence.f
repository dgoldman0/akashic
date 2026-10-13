\ =====================================================================
\  recurrence.f - Daybook schedule recurrence (an RFC 5545 subset)
\ =====================================================================
\  A rule is a caller-owned record describing when a schedule repeats:
\
\    once      the start only
\    daily     every interval days
\    weekly    on a set of weekdays, every interval weeks (weeks start
\              Monday, the RFC 5545 default)
\    monthly   on a day of the month (1..31, or -1 for the last day) or on
\              the nth weekday (1..5, or -1 for the last), every interval
\              months
\    yearly    on the start's month and day, every interval years
\
\  ending never, after a count of occurrences, or at an UNTIL instant
\  (inclusive, in UTC, as RFC 5545 requires for a zoned start).
\
\  The start is local seconds (see posix-tz.f) and fixes the time of day of
\  every occurrence.  Occurrences are the dates that match the rule on or
\  after the start's date, as RFC 5545 generates them: a weekly rule
\  starting on a Tuesday for Mondays first fires the next Monday.  A date
\  the calendar lacks, such as the 31st of a short month or February 29 in
\  other years, is skipped and does not count.  Ordinals number the
\  occurrences from 1.
\
\  Daily and weekly rules find an ordinal arithmetically, so catching up
\  over a long gap never steps day by day.  Monthly and yearly rules step
\  one period at a time; the Gregorian calendar repeats every 400 years,
\  so a rule that finds no date in 4800 months or 400 years never fires.
\
\  DBREC-NEXT turns occurrences into instants through a posix-tz zone.
\  DBREC-DESCRIBE says in one line, for people, when a rule fires.  The
\  module owns no mutable state.
\
\  Public API:
\    DBREC-SIZE        ( -- bytes )
\    DBREC-CHECK       ( rule zone -- status )
\    DBREC-OCCURRENCE  ( k rule -- local-s status )
\    DBREC-FIRST-FROM  ( local-s rule -- k status )
\    DBREC-NEXT        ( after-utc rule zone -- k utc status )
\    DBREC-DESCRIBE    ( rule writer -- )
\ =====================================================================

REQUIRE ../../../utils/posix-tz.f
REQUIRE ../../../utils/buffer-writer.f

PROVIDED akashic-daybook-recurrence

\ =====================================================================
\  Layer 0 - Constants and the rule record
\ =====================================================================

0 CONSTANT DBREC-ONCE
1 CONSTANT DBREC-DAILY
2 CONSTANT DBREC-WEEKLY
3 CONSTANT DBREC-MONTHLY
4 CONSTANT DBREC-YEARLY

0 CONSTANT DBREC-BY-DAY          \ monthly on a day of the month
1 CONSTANT DBREC-BY-WEEKDAY      \ monthly on the nth weekday

0 CONSTANT DBREC-END-NEVER
1 CONSTANT DBREC-END-UNTIL
2 CONSTANT DBREC-END-COUNT

0 CONSTANT DBREC-S-OK
1 CONSTANT DBREC-S-INVALID       \ a field is outside its range
2 CONSTANT DBREC-S-ENDED         \ the series has no such occurrence
3 CONSTANT DBREC-S-NEVER         \ the rule can never produce an occurrence
4 CONSTANT DBREC-S-RANGE         \ the occurrence is after 9999-12-31
5 CONSTANT DBREC-S-ZONE          \ the zone could not convert the time

\ Interface limits: an interval beyond the calendar's range means nothing,
\ and a count is bounded only to keep arithmetic exact.
9999 CONSTANT DBREC-INTERVAL-MAX
1000000000 CONSTANT DBREC-COUNT-MAX

86400 CONSTANT _DBREC-DAY

\ Record layout (bytes):
\    +0  frequency
\    +8  interval
\   +16  weekly weekdays: ISO weekday bits 1..7, 0 for the start's weekday
\   +24  monthly mode: DBREC-BY-DAY or DBREC-BY-WEEKDAY
\   +32  monthly day (1..31, -1 last, 0 the start's) or nth (1..5, -1)
\   +40  monthly weekday for DBREC-BY-WEEKDAY (ISO 1..7)
\   +48  end kind
\   +56  until (UTC seconds) or count
\   +64  start (local seconds)
: DBREC.FREQ          ( rule -- addr ) ;
: DBREC.INTERVAL      ( rule -- addr ) 8 + ;
: DBREC.WEEKDAYS      ( rule -- addr ) 16 + ;
: DBREC.MONTH-MODE    ( rule -- addr ) 24 + ;
: DBREC.MONTH-DAY     ( rule -- addr ) 32 + ;
: DBREC.MONTH-WEEKDAY ( rule -- addr ) 40 + ;
: DBREC.END           ( rule -- addr ) 48 + ;
: DBREC.LIMIT         ( rule -- addr ) 56 + ;
: DBREC.START         ( rule -- addr ) 64 + ;
72 CONSTANT DBREC-SIZE

\ =====================================================================
\  Layer 1 - Calendar helpers (days since 1970-01-01)
\ =====================================================================

: _DBREC-LAST-DAY  ( -- days )
    DT-EPOCH-S-MAX _DBREC-DAY / ;

: _DBREC-START-DAY  ( rule -- days )
    DBREC.START @ _DBREC-DAY / ;

: _DBREC-TOD  ( rule -- seconds )
    DBREC.START @ _DBREC-DAY MOD ;

: _DBREC-ISO  ( days -- iso-weekday )
    _DBREC-DAY * DT-WEEKDAY DROP ;

: _DBREC-DATE  ( days -- year month day )
    _DBREC-DAY * DT-EPOCH-S>YMD DROP ;

\ The day of a civil date; flag false when the calendar lacks it.
: _DBREC-DAY-OF  ( year month day -- days flag )
    DT-YMD>EPOCH-S IF DROP 0 0 ELSE _DBREC-DAY / -1 THEN ;

: _DBREC-BITS  ( mask -- n )
    0 SWAP BEGIN DUP WHILE DUP 1- AND SWAP 1+ SWAP REPEAT DROP ;

\ =====================================================================
\  Layer 2 - Daily and weekly rules, arithmetically
\ =====================================================================

: _DBREC-DAILY-DAY  ( k rule -- days )
    DUP >R DBREC.INTERVAL @ SWAP 1- * R> _DBREC-START-DAY + ;

\ The first ordinal on day T or later.
: _DBREC-DAILY-FROM  ( T rule -- k )
    2DUP _DBREC-START-DAY <= IF 2DROP 1 EXIT THEN
    DUP >R _DBREC-START-DAY -
    R@ DBREC.INTERVAL @ + 1- R> DBREC.INTERVAL @ / 1+ ;

: _DBREC-WEEK-MASK  ( rule -- mask )
    DUP DBREC.WEEKDAYS @ ?DUP IF NIP EXIT THEN
    _DBREC-START-DAY _DBREC-ISO 1 SWAP LSHIFT ;

\ The Monday of the week holding the start: week 0.
: _DBREC-MONDAY0  ( rule -- days )
    _DBREC-START-DAY DUP _DBREC-ISO 1- - ;

\ The weekday of a mask's set bit r (0 the first, in ISO order).
: _DBREC-NTH-BIT  ( mask r -- iso )
    SWAP 1                                  ( r mask iso )
    BEGIN DUP 7 <= WHILE
        2DUP 1 SWAP LSHIFT AND IF
            ROT DUP 0= IF DROP NIP EXIT THEN
            1- ROT ROT
        THEN
        1+
    REPEAT
    NIP NIP ;

\ Mask days falling before day X, counting from week 0's Monday: the
\ active weeks wholly before X's week, then X's week before X's weekday.
: _DBREC-WEEK-COUNT  ( X rule -- n )
    >R
    DUP R@ _DBREC-MONDAY0 - 7 /                         ( X W )
    DUP R@ DBREC.INTERVAL @ + 1- R@ DBREC.INTERVAL @ /  ( X W full )
    R@ _DBREC-WEEK-MASK _DBREC-BITS *                   ( X W base )
    SWAP R@ DBREC.INTERVAL @ MOD 0= IF
        SWAP _DBREC-ISO 1 SWAP LSHIFT 1-
        R@ _DBREC-WEEK-MASK AND _DBREC-BITS +
    ELSE
        NIP
    THEN
    R> DROP ;

: _DBREC-WEEKLY-DAY  ( k rule -- days )
    >R
    R@ _DBREC-WEEK-MASK                                 ( k mask )
    R@ _DBREC-START-DAY R@ _DBREC-WEEK-COUNT            ( k mask skipped )
    ROT + 1-                                            ( mask j )
    OVER _DBREC-BITS /MOD                               ( mask r q )
    R@ DBREC.INTERVAL @ * 7 *                           ( mask r week-days )
    >R _DBREC-NTH-BIT 1- R> +
    R> _DBREC-MONDAY0 + ;

: _DBREC-WEEKLY-FROM  ( T rule -- k )
    2DUP _DBREC-START-DAY <= IF 2DROP 1 EXIT THEN
    DUP >R _DBREC-WEEK-COUNT
    R@ _DBREC-START-DAY R> _DBREC-WEEK-COUNT - 1+ ;

\ =====================================================================
\  Layer 3 - Monthly and yearly rules, one period at a time
\ =====================================================================

\ Period i is the start's month (or year) plus i intervals.
: _DBREC-MONTH-AT  ( i rule -- year month )
    >R R@ DBREC.INTERVAL @ *
    R> _DBREC-START-DAY _DBREC-DATE DROP     ( i*n year0 month0 )
    1- ROT + 12 /MOD                         ( year0 m-rem year-add )
    ROT + SWAP 1+ ;

: _DBREC-YEAR-AT  ( i rule -- year )
    DUP DBREC.INTERVAL @ ROT * SWAP _DBREC-START-DAY _DBREC-DATE 2DROP + ;

: _DBREC-PERIOD-YEAR  ( i rule -- year )
    DUP DBREC.FREQ @ DBREC-MONTHLY = IF _DBREC-MONTH-AT DROP EXIT THEN
    _DBREC-YEAR-AT ;

\ Periods that may pass without a date before the rule is known to never
\ fire: one Gregorian cycle.
: _DBREC-CYCLE  ( rule -- periods )
    DBREC.FREQ @ DBREC-MONTHLY = IF 4800 ELSE 400 THEN ;

\ The nth (1..5, -1 last) ISO weekday of a month.
: _DBREC-NTH-WEEKDAY  ( year month nth iso -- days flag )
    >R >R
    2DUP 1 _DBREC-DAY-OF DROP                ( year month first )
    ROT ROT DT-MONTH-DAYS DROP               ( first days-in-month )
    R> R>                                    ( first dim nth iso )
    OVER -1 = IF
        NIP >R + 1-                          ( last ; R: iso )
        DUP _DBREC-ISO R> - 7 + 7 MOD - -1 EXIT
    THEN
    >R >R OVER _DBREC-ISO                    ( first dim first-iso ; R: iso nth )
    R> R> ROT                                ( first dim nth iso first-iso )
    - 7 + 7 MOD                              ( first dim nth delta )
    SWAP 1- 7 * +                            ( first dim offset )
    TUCK > IF + -1 ELSE 2DROP 0 0 THEN ;

\ The rule's date in a month; flag false when the month lacks it.
: _DBREC-MONTH-DAY  ( year month rule -- days flag )
    DUP DBREC.MONTH-MODE @ DBREC-BY-WEEKDAY = IF
        DUP DBREC.MONTH-DAY @ SWAP DBREC.MONTH-WEEKDAY @
        _DBREC-NTH-WEEKDAY EXIT
    THEN
    DUP DBREC.MONTH-DAY @ ?DUP 0= IF
        _DBREC-START-DAY _DBREC-DATE NIP NIP
    ELSE
        NIP
    THEN                                     ( year month day )
    DUP -1 = IF DROP 2DUP DT-MONTH-DAYS DROP THEN
    _DBREC-DAY-OF ;

: _DBREC-PERIOD-DAY  ( i rule -- days flag )
    DUP DBREC.FREQ @ DBREC-MONTHLY = IF
        TUCK _DBREC-MONTH-AT ROT _DBREC-MONTH-DAY EXIT
    THEN
    TUCK _DBREC-YEAR-AT                      ( rule year )
    SWAP _DBREC-START-DAY _DBREC-DATE        ( year year0 month0 day0 )
    ROT DROP _DBREC-DAY-OF ;

\ Walk the occurrences in order to the first that is the k-th or falls on
\ day T or later.
: _DBREC-SEEK  ( k T rule -- k' days status )
    >R 1 0 0                                 ( k T ordinal i misses ; R: rule )
    BEGIN
        OVER R@ _DBREC-PERIOD-YEAR 9999 > IF
            2DROP 2DROP DROP R> DROP 0 0 DBREC-S-RANGE EXIT
        THEN
        DUP R@ _DBREC-CYCLE > IF
            2DROP 2DROP DROP R> DROP 0 0 DBREC-S-NEVER EXIT
        THEN
        OVER R@ _DBREC-PERIOD-DAY            ( k T ordinal i misses days flag )
        0= IF
            DROP 1+
        ELSE DUP R@ _DBREC-START-DAY < IF
            DROP 1+
        ELSE
            DUP 5 PICK >= 4 PICK 7 PICK >= OR IF
                >R DROP DROP NIP NIP R> DBREC-S-OK R> DROP EXIT
            THEN
            DROP DROP 0 ROT 1+ ROT ROT
        THEN THEN
        SWAP 1+ SWAP
    AGAIN ;

\ =====================================================================
\  Layer 4 - Public words
\ =====================================================================

: _DBREC-COUNT-ENDED?  ( k rule -- flag )
    DUP DBREC.END @ DBREC-END-COUNT = IF DBREC.LIMIT @ > EXIT THEN
    2DROP 0 ;

\ A day as local seconds at the rule's time of day, or a range failure.
: _DBREC-LOCAL  ( days rule -- local status )
    OVER _DBREC-LAST-DAY > IF 2DROP 0 DBREC-S-RANGE EXIT THEN
    _DBREC-TOD SWAP _DBREC-DAY * +
    DUP DT-EPOCH-S-MAX > IF DROP 0 DBREC-S-RANGE EXIT THEN
    DBREC-S-OK ;

\ The local time of the k-th occurrence (k from 1).
: DBREC-OCCURRENCE  ( k rule -- local-s status )
    OVER 1 < IF 2DROP 0 DBREC-S-INVALID EXIT THEN
    2DUP _DBREC-COUNT-ENDED? IF 2DROP 0 DBREC-S-ENDED EXIT THEN
    DUP DBREC.FREQ @ CASE
        DBREC-ONCE OF
            SWAP 1 > IF DROP 0 DBREC-S-ENDED EXIT THEN
            DUP _DBREC-START-DAY SWAP _DBREC-LOCAL EXIT
        ENDOF
        DBREC-DAILY OF
            TUCK _DBREC-DAILY-DAY SWAP _DBREC-LOCAL EXIT
        ENDOF
        DBREC-WEEKLY OF
            TUCK _DBREC-WEEKLY-DAY SWAP _DBREC-LOCAL EXIT
        ENDOF
    ENDCASE
    \ Monthly and yearly.
    >R _DBREC-LAST-DAY 1+ R@ _DBREC-SEEK     ( k' days status ; R: rule )
    ?DUP IF >R 2DROP 0 R> R> DROP EXIT THEN
    NIP R> _DBREC-LOCAL ;

\ The first ordinal whose local time is local-s or later.
: DBREC-FIRST-FROM  ( local-s rule -- k status )
    OVER _DBREC-DAY / OVER _DBREC-START-DAY MAX     ( local rule T )
    \ A day whose occurrence time has passed starts from the next day.
    ROT DUP _DBREC-DAY / 2 PICK =                    ( rule T local same-day? )
    SWAP _DBREC-DAY MOD 3 PICK _DBREC-TOD > AND IF 1+ THEN
    SWAP                                            ( T rule )
    DUP DBREC.FREQ @ CASE
        DBREC-ONCE OF
            DUP _DBREC-START-DAY ROT < IF DROP 0 DBREC-S-ENDED EXIT THEN
            DROP 1 DBREC-S-OK EXIT
        ENDOF
        DBREC-DAILY OF
            _DBREC-DAILY-FROM DBREC-S-OK EXIT
        ENDOF
        DBREC-WEEKLY OF
            _DBREC-WEEKLY-FROM DBREC-S-OK EXIT
        ENDOF
    ENDCASE
    >R DBREC-COUNT-MAX SWAP R> _DBREC-SEEK
    ?DUP IF NIP NIP 0 SWAP EXIT THEN
    DROP DBREC-S-OK ;

\ The first occurrence strictly after an instant, in UTC.  Searching starts
\ two days earlier in local time, which covers any offset change, and steps
\ forward to the first instant past after-utc.
: DBREC-NEXT  ( after-utc rule zone -- k utc status )
    >R >R
    DUP R> R> ROT                            ( after rule zone after )
    OVER TZ-UTC>LOCAL IF DROP 0 THEN         ( after rule zone local )
    2 _DBREC-DAY * - 0 MAX                   ( after rule zone from )
    2 PICK DBREC-FIRST-FROM ?DUP IF          ( after rule zone k status )
        >R 2DROP 2DROP 0 0 R> EXIT
    THEN
    BEGIN                                    ( after rule zone k )
        DUP 3 PICK DBREC-OCCURRENCE ?DUP IF
            >R 2DROP 2DROP DROP 0 0 R> EXIT
        THEN                                 ( after rule zone k local )
        2 PICK TZ-LOCAL>UTC NIP IF
            2DROP 2DROP DROP 0 0 DBREC-S-ZONE EXIT
        THEN                                 ( after rule zone k utc )
        3 PICK DBREC.END @ DBREC-END-UNTIL = IF
            DUP 4 PICK DBREC.LIMIT @ > IF
                2DROP 2DROP DROP 0 0 DBREC-S-ENDED EXIT
            THEN
        THEN
        DUP 5 PICK > IF
            >R >R 2DROP DROP R> R> DBREC-S-OK EXIT
        THEN
        DROP 1+
    AGAIN ;

\ Field ranges, then that the rule produces a first occurrence before any
\ UNTIL.
: DBREC-CHECK  ( rule zone -- status )
    OVER DBREC.FREQ @ 0 DBREC-YEARLY 1+ WITHIN 0= IF 2DROP DBREC-S-INVALID EXIT THEN
    OVER DBREC.INTERVAL @ 1 DBREC-INTERVAL-MAX 1+ WITHIN 0= IF
        2DROP DBREC-S-INVALID EXIT
    THEN
    OVER DBREC.START @ 0 DT-EPOCH-S-MAX 1+ WITHIN 0= IF
        2DROP DBREC-S-INVALID EXIT
    THEN
    OVER DBREC.WEEKDAYS @ 254 INVERT AND IF 2DROP DBREC-S-INVALID EXIT THEN
    OVER DBREC.FREQ @ DBREC-MONTHLY = IF
        OVER DBREC.MONTH-MODE @ DBREC-BY-WEEKDAY = IF
            OVER DBREC.MONTH-DAY @ DUP -1 = SWAP 1 6 WITHIN OR 0= IF
                2DROP DBREC-S-INVALID EXIT
            THEN
            OVER DBREC.MONTH-WEEKDAY @ 1 8 WITHIN 0= IF
                2DROP DBREC-S-INVALID EXIT
            THEN
        ELSE
            OVER DBREC.MONTH-MODE @ DBREC-BY-DAY <> IF
                2DROP DBREC-S-INVALID EXIT
            THEN
            OVER DBREC.MONTH-DAY @ DUP -1 = SWAP 0 32 WITHIN OR 0= IF
                2DROP DBREC-S-INVALID EXIT
            THEN
        THEN
    THEN
    OVER DBREC.END @ CASE
        DBREC-END-NEVER OF ENDOF
        DBREC-END-UNTIL OF
            OVER DBREC.LIMIT @ 0 DT-EPOCH-S-MAX 1+ WITHIN 0= IF
                2DROP DBREC-S-INVALID EXIT
            THEN
        ENDOF
        DBREC-END-COUNT OF
            OVER DBREC.LIMIT @ 1 DBREC-COUNT-MAX 1+ WITHIN 0= IF
                2DROP DBREC-S-INVALID EXIT
            THEN
        ENDOF
        >R 2DROP DBREC-S-INVALID R> DROP EXIT
    ENDCASE
    OVER DBREC.FREQ @ DBREC-ONCE = IF
        OVER DBREC.END @ DBREC-END-NEVER <> IF 2DROP DBREC-S-INVALID EXIT THEN
    THEN
    \ The first occurrence must exist and, with an UNTIL, come before it.
    \ Searching from instant -1 reaches an occurrence at instant 0.
    -1 ROT ROT DBREC-NEXT NIP NIP
    DUP DBREC-S-ENDED = IF DROP DBREC-S-NEVER THEN ;

\ =====================================================================
\  Layer 6 - Describing a rule
\ =====================================================================
\  DBREC-DESCRIBE appends to a caller's buffer writer (utils/buffer-
\  writer.f) one line saying when a checked rule fires:
\
\    once on 2026-10-11 at 09:00
\    daily at 09:00 from 2026-10-11
\    every 2 weeks on Mon, Thu at 09:00 from 2026-10-11, 10 times
\    monthly on the last Fri at 09:00 from 2026-10-11, until
\      2027-06-30 23:00 UTC
\
\  Times of day and dates are the rule's local ones; an UNTIL is the UTC
\  instant the rule keeps.  A writer with DBREC-DESCRIBE-MAX bytes of room
\  always holds the line; one with less latches its capacity status.

\ The longest line: every 9999 weeks on all seven days at 23:59 from
\ 9999-12-31, until 9999-12-31 23:59 UTC.
106 CONSTANT DBREC-DESCRIBE-MAX

: _DBREC-W$  ( address length writer -- ) CBW-APPEND DROP ;
: _DBREC-WC  ( char writer -- ) CBW-CHAR DROP ;

\ Two digits.
: _DBREC-W2  ( n writer -- )
    OVER 10 < IF [CHAR] 0 OVER _DBREC-WC THEN CBW-NUMBER DROP ;

\ "YYYY-MM-DD" of SECONDS.
: _DBREC-WDATE  ( seconds writer -- )
    >R DT-EPOCH-S>YMD DROP                   ( year month day )
    ROT R@ CBW-NUMBER DROP [CHAR] - R@ _DBREC-WC
    SWAP R@ _DBREC-W2 [CHAR] - R@ _DBREC-WC R> _DBREC-W2 ;

\ "HH:MM" of SECONDS since midnight.
: _DBREC-WCLOCK  ( seconds writer -- )
    >R 60 / 60 /MOD R@ _DBREC-W2 [CHAR] : R@ _DBREC-WC R> _DBREC-W2 ;

\ An ISO weekday's short name.
: _DBREC-DAY$  ( iso -- address length )
    1- 3 * S" MonTueWedThuFriSatSun" DROP + 3 ;

\ The nth of a month's weekdays: 1st to 5th, or last.
: _DBREC-NTH$  ( n -- address length )
    DUP -1 = IF DROP S" last" EXIT THEN
    1- 3 * S" 1st2nd3rd4th5th" DROP + 3 ;

: _DBREC-ADVERB$  ( frequency -- address length )
    CASE
        DBREC-DAILY   OF S" daily" ENDOF
        DBREC-WEEKLY  OF S" weekly" ENDOF
        DBREC-MONTHLY OF S" monthly" ENDOF
        >R S" yearly" R>
    ENDCASE ;

: _DBREC-UNITS$  ( frequency -- address length )
    CASE
        DBREC-DAILY   OF S" days" ENDOF
        DBREC-WEEKLY  OF S" weeks" ENDOF
        DBREC-MONTHLY OF S" months" ENDOF
        >R S" years" R>
    ENDCASE ;

\ "daily", or "every 3 days".
: _DBREC-WPERIOD  ( rule writer -- )
    OVER DBREC.INTERVAL @ 1 = IF
        SWAP DBREC.FREQ @ _DBREC-ADVERB$ ROT _DBREC-W$ EXIT
    THEN
    S" every " 2 PICK _DBREC-W$
    OVER DBREC.INTERVAL @ OVER CBW-NUMBER DROP
    BL OVER _DBREC-WC
    SWAP DBREC.FREQ @ _DBREC-UNITS$ ROT _DBREC-W$ ;

\ " on Mon, Thu": a weekly rule's days, in ISO order.
: _DBREC-WDAYS  ( rule writer -- )
    S"  on " 2 PICK _DBREC-W$
    SWAP _DBREC-WEEK-MASK -1                 ( writer mask first? )
    8 1 DO
        OVER 1 I LSHIFT AND IF
            DUP 0= IF S" , " 4 PICK _DBREC-W$ THEN
            DROP 0
            I _DBREC-DAY$ 4 PICK _DBREC-W$
        THEN
    LOOP
    2DROP DROP ;

\ " on day 15", " on the last day", " on the 2nd Tue" or " on the last
\ Fri": a monthly rule's date.
: _DBREC-WMONTH  ( rule writer -- )
    OVER DBREC.MONTH-MODE @ DBREC-BY-WEEKDAY = IF
        S"  on the " 2 PICK _DBREC-W$
        OVER DBREC.MONTH-DAY @ _DBREC-NTH$ 2 PICK _DBREC-W$
        BL OVER _DBREC-WC
        SWAP DBREC.MONTH-WEEKDAY @ _DBREC-DAY$ ROT _DBREC-W$ EXIT
    THEN
    OVER DBREC.MONTH-DAY @ -1 = IF NIP S"  on the last day" ROT _DBREC-W$ EXIT THEN
    S"  on day " 2 PICK _DBREC-W$
    SWAP DUP DBREC.MONTH-DAY @ ?DUP 0= IF
        _DBREC-START-DAY _DBREC-DATE NIP NIP
    ELSE
        NIP
    THEN
    SWAP CBW-NUMBER DROP ;

\ ", 10 times" or ", until 2027-06-30 23:00 UTC"; nothing for a series
\ that never ends.
: _DBREC-WEND  ( rule writer -- )
    OVER DBREC.END @ DBREC-END-COUNT = IF
        S" , " 2 PICK _DBREC-W$
        OVER DBREC.LIMIT @ OVER CBW-NUMBER DROP
        SWAP DBREC.LIMIT @ 1 = IF S"  time" ELSE S"  times" THEN ROT _DBREC-W$
        EXIT
    THEN
    OVER DBREC.END @ DBREC-END-UNTIL = IF
        S" , until " 2 PICK _DBREC-W$
        OVER DBREC.LIMIT @ OVER _DBREC-WDATE
        BL OVER _DBREC-WC
        OVER DBREC.LIMIT @ _DBREC-DAY MOD OVER _DBREC-WCLOCK
        NIP S"  UTC" ROT _DBREC-W$ EXIT
    THEN
    2DROP ;

\ Appends one line saying when RULE, which DBREC-CHECK accepts, fires.
: DBREC-DESCRIBE  ( rule writer -- )
    OVER DBREC.FREQ @ DBREC-ONCE = IF
        S" once on " 2 PICK _DBREC-W$
        OVER DBREC.START @ OVER _DBREC-WDATE
        S"  at " 2 PICK _DBREC-W$
        SWAP _DBREC-TOD SWAP _DBREC-WCLOCK EXIT
    THEN
    2DUP _DBREC-WPERIOD
    OVER DBREC.FREQ @ CASE
        DBREC-WEEKLY  OF 2DUP _DBREC-WDAYS ENDOF
        DBREC-MONTHLY OF 2DUP _DBREC-WMONTH ENDOF
    ENDCASE
    S"  at " 2 PICK _DBREC-W$
    OVER _DBREC-TOD OVER _DBREC-WCLOCK
    S"  from " 2 PICK _DBREC-W$
    OVER DBREC.START @ OVER _DBREC-WDATE
    _DBREC-WEND ;

