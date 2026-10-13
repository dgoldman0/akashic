\ =====================================================================
\  posix-tz.f - POSIX TZ rule strings: parse, format, and convert
\ =====================================================================
\  A zone is a caller-owned record compiled from a POSIX TZ string
\  (IEEE Std 1003.1 section 8.3, with the RFC 8536 section 3.3.1
\  extensions: <...> quoted names and rule hours from -167 to 167), such
\  as EST5EDT,M3.2.0,M11.1.0 or <+0530>-5:30.  It holds the standard and
\  daylight offsets, their names, and the yearly rule between them.
\
\  A zone with a daylight name must carry its rule: POSIX leaves the
\  rule-less form implementation-defined, and this module never guesses
\  one.  A TZ string describes only the current rule, with no history, so
\  every year converts by that rule.
\
\  Instants are Unix seconds.  A local time is "local seconds": its date
\  and time of day encoded as if they were UTC, as DT-YMD>EPOCH-S plus the
\  seconds into the day.  Offsets are seconds east of UTC, so
\  local = utc + offset.  Both stay within datetime.f's 1970..9999 range.
\
\  Local-to-UTC conversion follows RFC 5545: a time the clocks repeat
\  resolves to its first occurrence, the earlier instant, and a time they
\  skip uses the offset in force before the change.
\
\  The module owns no mutable state.  TZ-PARSE keeps its cursor in two
\  cells of the caller's record.
\
\  Public API:
\    TZ-SIZE         ( -- bytes )            zone record size
\    TZ-STRING-MAX   ( -- bytes )            longest accepted TZ string
\    TZ-NAME-MAX     ( -- bytes )            longest zone name
\    TZ-PARSE        ( addr u zone -- status )
\    TZ-FORMAT       ( zone destination capacity -- written status )
\    TZ-DST?         ( zone -- flag )        a daylight rule is present
\    TZ-OFFSET       ( utc-s zone -- offset-s dst? status )
\    TZ-NAME         ( utc-s zone -- addr u status )
\    TZ-UTC>LOCAL    ( utc-s zone -- local-s status )
\    TZ-LOCAL>UTC    ( local-s zone -- utc-s kind status )
\  Kinds: TZ-K-UNIQUE, TZ-K-OVERLAP (first occurrence chosen), TZ-K-GAP
\  (offset before the change).  Statuses are datetime.f's DT-S-*.
\ =====================================================================

REQUIRE datetime.f

PROVIDED akashic-posix-tz

\ =====================================================================
\  Layer 0 - Constants and the zone record
\ =====================================================================

\ Interface limits.  Real TZ strings are under 50 bytes and their names
\ under eight; these leave generous room while keeping records fixed.
128 CONSTANT TZ-STRING-MAX
 16 CONSTANT TZ-NAME-MAX

0 CONSTANT TZ-K-UNIQUE
1 CONSTANT TZ-K-OVERLAP
2 CONSTANT TZ-K-GAP

1 CONSTANT _TZ-R-JULIAN      \ Jn: day n of 365, February 29 never counted
2 CONSTANT _TZ-R-DAY         \ n: zero-based day of the year
3 CONSTANT _TZ-R-MONTH       \ Mm.w.d: weekday d, week w (5 last), month m

1 CONSTANT _TZ-F-DST         \ flags: a daylight rule is present
2 CONSTANT _TZ-F-VALID       \ flags: TZ-PARSE compiled this record

7200 CONSTANT _TZ-DEFAULT-TIME    \ rule transitions default to 02:00:00
1 63 LSHIFT CONSTANT _TZ-NONE     \ below every instant

\ Record layout (bytes):
\    +0  flags
\    +8  standard offset, seconds east of UTC
\   +16  daylight offset
\   +24  start rule (kind, a, b, c, time: five cells)
\   +64  end rule
\  +104  standard name: length cell, then TZ-NAME-MAX bytes
\  +128  daylight name
\  +152  TZ-PARSE cursor: address, remaining bytes
: _TZ.FLAGS     ( zone -- addr ) ;
: _TZ.STD-OFF   ( zone -- addr ) 8 + ;
: _TZ.DST-OFF   ( zone -- addr ) 16 + ;
: _TZ.START     ( zone -- rule ) 24 + ;
: _TZ.END       ( zone -- rule ) 64 + ;
: _TZ.STD-NAME  ( zone -- field ) 104 + ;
: _TZ.DST-NAME  ( zone -- field ) 128 + ;
: _TZ.CUR-A     ( zone -- addr ) 152 + ;
: _TZ.CUR-U     ( zone -- addr ) 160 + ;
168 CONSTANT TZ-SIZE

: _TZ-RULE.KIND ( rule -- addr ) ;
: _TZ-RULE.A    ( rule -- addr ) 8 + ;
: _TZ-RULE.B    ( rule -- addr ) 16 + ;
: _TZ-RULE.C    ( rule -- addr ) 24 + ;
: _TZ-RULE.TIME ( rule -- addr ) 32 + ;

: _TZ-VALID?  ( zone -- flag )
    _TZ.FLAGS @ _TZ-F-VALID AND 0<> ;

: TZ-DST?  ( zone -- flag )
    DUP _TZ-VALID? 0= IF DROP 0 EXIT THEN
    _TZ.FLAGS @ _TZ-F-DST AND 0<> ;

: _TZ-INSTANT?  ( seconds -- flag )
    0 DT-EPOCH-S-MAX 1+ WITHIN ;

: _TZ-SPAN-STATUS  ( addr u -- status )
    CALLER-SPAN-STATUS
    DUP CALLER-SPAN-S-OK = IF DROP DT-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP DT-S-RANGE EXIT THEN
    CALLER-SPAN-S-PROTECTED = IF DT-S-PROTECTED ELSE DT-S-PLATFORM THEN ;

\ =====================================================================
\  Layer 1 - Parsing
\ =====================================================================

\ The next byte, or -1 at the end of the string.
: _TZ-PEEK  ( zone -- char )
    DUP _TZ.CUR-U @ 0= IF DROP -1 EXIT THEN
    _TZ.CUR-A @ C@ ;

: _TZ-SKIP  ( zone -- )
    1 OVER _TZ.CUR-A +!
    -1 SWAP _TZ.CUR-U +! ;

\ Consume char when it is next.
: _TZ-ACCEPT?  ( zone char -- flag )
    OVER _TZ-PEEK = IF _TZ-SKIP -1 ELSE DROP 0 THEN ;

: _TZ-DIGIT?  ( char -- flag )
    [CHAR] 0 [CHAR] 9 1+ WITHIN ;

: _TZ-ALPHA?  ( char -- flag )
    DUP [CHAR] A [CHAR] Z 1+ WITHIN
    SWAP [CHAR] a [CHAR] z 1+ WITHIN OR ;

\ Up to max-digits decimal digits; count is 0 when none were present.
: _TZ-DIGITS  ( zone max-digits -- n count )
    0 0                                     ( zone max n count )
    BEGIN
        3 PICK _TZ-PEEK DUP _TZ-DIGIT?      ( zone max n count ch digit? )
        2 PICK 5 PICK < AND
    WHILE
        [CHAR] 0 - ROT 10 * + SWAP 1+
        3 PICK _TZ-SKIP
    REPEAT
    DROP >R NIP NIP R> ;

\ A number of 1..max-digits digits within lo..hi.
: _TZ-FIELD  ( zone max-digits lo hi -- n flag )
    2>R _TZ-DIGITS
    0<> OVER 2R@ 1+ WITHIN AND
    2R> 2DROP ;

\ Exactly two digits below 60.
: _TZ-SIXTY  ( zone -- n flag )
    2 _TZ-DIGITS 2 = OVER 60 < AND ;

\ hh[:mm[:ss]] as seconds, no more than max-hour hours in total, with at
\ most hour-digits digits of hours.
: _TZ-CLOCK  ( zone hour-digits max-hour -- seconds flag )
    >R OVER SWAP _TZ-DIGITS             ( zone h count ; R: max-hour )
    0= IF R> 2DROP DROP 0 0 EXIT THEN
    3600 *                              ( zone seconds )
    OVER [CHAR] : _TZ-ACCEPT? IF
        OVER _TZ-SIXTY 0= IF R> DROP 2DROP DROP 0 0 EXIT THEN
        60 * +
        OVER [CHAR] : _TZ-ACCEPT? IF
            OVER _TZ-SIXTY 0= IF R> DROP 2DROP DROP 0 0 EXIT THEN
            +
        THEN
    THEN
    NIP DUP R> 3600 * > IF DROP 0 0 EXIT THEN
    -1 ;

\ [+|-]hh[:mm[:ss]] as signed seconds.
: _TZ-SIGNED-CLOCK  ( zone hour-digits max-hour -- seconds flag )
    2 PICK [CHAR] - _TZ-ACCEPT? IF
        _TZ-CLOCK SWAP NEGATE SWAP EXIT
    THEN
    2 PICK [CHAR] + _TZ-ACCEPT? DROP
    _TZ-CLOCK ;

: _TZ-NAME-CHAR?  ( char -- flag )
    DUP _TZ-ALPHA? OVER _TZ-DIGIT? OR
    OVER [CHAR] + = OR SWAP [CHAR] - = OR ;

\ Append char to a name field; false when the name is full.
: _TZ-NAME+  ( char field -- flag )
    DUP @ TZ-NAME-MAX < 0= IF 2DROP 0 EXIT THEN
    TUCK DUP @ + 8 + C!
    1 SWAP +! -1 ;

\ Three or more letters, or <...> holding three or more letters, digits,
\ + and -.
: _TZ-READ-NAME  ( zone field -- flag )
    0 OVER !
    OVER [CHAR] < _TZ-ACCEPT? IF
        BEGIN
            OVER _TZ-PEEK DUP _TZ-NAME-CHAR?
        WHILE
            OVER _TZ-NAME+ 0= IF 2DROP 0 EXIT THEN
            OVER _TZ-SKIP
        REPEAT
        DROP
        OVER [CHAR] > _TZ-ACCEPT? 0= IF 2DROP 0 EXIT THEN
    ELSE
        BEGIN
            OVER _TZ-PEEK DUP _TZ-ALPHA?
        WHILE
            OVER _TZ-NAME+ 0= IF 2DROP 0 EXIT THEN
            OVER _TZ-SKIP
        REPEAT
        DROP
    THEN
    @ 3 >= NIP ;

\ Jn, n or Mm.w.d, then an optional /time.
: _TZ-DATE  ( zone rule -- flag )
    OVER [CHAR] J _TZ-ACCEPT? IF
        _TZ-R-JULIAN OVER _TZ-RULE.KIND !
        OVER 3 1 365 _TZ-FIELD 0= IF 2DROP DROP 0 EXIT THEN
        OVER _TZ-RULE.A !
    ELSE OVER [CHAR] M _TZ-ACCEPT? IF
        _TZ-R-MONTH OVER _TZ-RULE.KIND !
        OVER 2 1 12 _TZ-FIELD 0= IF 2DROP DROP 0 EXIT THEN
        OVER _TZ-RULE.A !
        OVER [CHAR] . _TZ-ACCEPT? 0= IF 2DROP 0 EXIT THEN
        OVER 1 1 5 _TZ-FIELD 0= IF 2DROP DROP 0 EXIT THEN
        OVER _TZ-RULE.B !
        OVER [CHAR] . _TZ-ACCEPT? 0= IF 2DROP 0 EXIT THEN
        OVER 1 0 6 _TZ-FIELD 0= IF 2DROP DROP 0 EXIT THEN
        OVER _TZ-RULE.C !
    ELSE
        _TZ-R-DAY OVER _TZ-RULE.KIND !
        OVER 3 0 365 _TZ-FIELD 0= IF 2DROP DROP 0 EXIT THEN
        OVER _TZ-RULE.A !
    THEN THEN
    _TZ-DEFAULT-TIME OVER _TZ-RULE.TIME !
    OVER [CHAR] / _TZ-ACCEPT? IF
        OVER 3 167 _TZ-SIGNED-CLOCK 0= IF 2DROP DROP 0 EXIT THEN
        OVER _TZ-RULE.TIME !
    THEN
    2DROP -1 ;

\ std offset [dst [offset] ,start[/time],end[/time]]
: _TZ-PARSE-BODY  ( zone -- flag )
    DUP DUP _TZ.STD-NAME _TZ-READ-NAME 0= IF DROP 0 EXIT THEN
    DUP 2 24 _TZ-SIGNED-CLOCK 0= IF 2DROP 0 EXIT THEN
    NEGATE OVER _TZ.STD-OFF !               \ POSIX counts west of UTC
    DUP _TZ-PEEK -1 = IF DROP -1 EXIT THEN
    DUP DUP _TZ.DST-NAME _TZ-READ-NAME 0= IF DROP 0 EXIT THEN
    DUP _TZ.STD-OFF @ 3600 + OVER _TZ.DST-OFF !   \ default: an hour ahead
    DUP _TZ-PEEK [CHAR] , <> IF
        DUP 2 24 _TZ-SIGNED-CLOCK 0= IF 2DROP 0 EXIT THEN
        NEGATE OVER _TZ.DST-OFF !
    THEN
    DUP [CHAR] , _TZ-ACCEPT? 0= IF DROP 0 EXIT THEN
    DUP DUP _TZ.START _TZ-DATE 0= IF DROP 0 EXIT THEN
    DUP [CHAR] , _TZ-ACCEPT? 0= IF DROP 0 EXIT THEN
    DUP DUP _TZ.END _TZ-DATE 0= IF DROP 0 EXIT THEN
    _TZ-F-DST OVER _TZ.FLAGS !
    _TZ-PEEK -1 = ;

\ Compile a TZ string into the caller's record.  On failure the record is
\ zeroed and every other word refuses it.
: TZ-PARSE  ( addr u zone -- status )
    OVER 0< IF DROP 2DROP DT-S-INVALID EXIT THEN
    OVER TZ-STRING-MAX > IF DROP 2DROP DT-S-RANGE EXIT THEN
    DUP TZ-SIZE _TZ-SPAN-STATUS ?DUP IF >R DROP 2DROP R> EXIT THEN
    DUP TZ-SIZE 0 FILL
    >R R@ _TZ.CUR-U ! R@ _TZ.CUR-A ! R>
    DUP _TZ-PARSE-BODY IF
        DUP _TZ.FLAGS @ _TZ-F-VALID OR OVER _TZ.FLAGS !
        0 OVER _TZ.CUR-A ! 0 SWAP _TZ.CUR-U !
        DT-S-OK EXIT
    THEN
    TZ-SIZE 0 FILL DT-S-SYNTAX ;

\ =====================================================================
\  Layer 2 - Formatting
\ =====================================================================
\  The formatter runs twice: first with no destination to measure the
\  result, then to write it.  _TZ-PUT stores a byte only into a real
\  destination.

: _TZ-PUT  ( dst pos char -- dst pos' )
    2 PICK IF >R 2DUP + R> SWAP C! ELSE DROP THEN 1+ ;

: _TZ-POW10  ( i -- 10^i )
    1 SWAP 0 ?DO 10 * LOOP ;

\ Exactly width digits of n.
: _TZ-PUT-DIGITS  ( dst pos n width -- dst pos' )
    BEGIN DUP WHILE
        1-
        2DUP _TZ-POW10 / 10 MOD [CHAR] 0 +
        >R 2SWAP R> _TZ-PUT 2SWAP
    REPEAT 2DROP ;

: _TZ-WIDTH  ( n -- digits )
    1 SWAP BEGIN DUP 9 > WHILE 10 / SWAP 1+ SWAP REPEAT DROP ;

: _TZ-PUT-NUMBER  ( dst pos n -- dst pos' )
    DUP _TZ-WIDTH _TZ-PUT-DIGITS ;

\ Signed seconds as [-]h[:mm[:ss]], omitting zero trailing fields.
: _TZ-PUT-CLOCK  ( dst pos seconds -- dst pos' )
    DUP 0< IF NEGATE >R [CHAR] - _TZ-PUT R> THEN
    >R R@ 3600 / _TZ-PUT-NUMBER
    R@ 3600 MOD IF
        [CHAR] : _TZ-PUT R@ 3600 MOD 60 / 2 _TZ-PUT-DIGITS
        R@ 60 MOD IF
            [CHAR] : _TZ-PUT R@ 60 MOD 2 _TZ-PUT-DIGITS
        THEN
    THEN
    R> DROP ;

: _TZ-ALPHA-ONLY?  ( addr u -- flag )
    BEGIN DUP WHILE
        OVER C@ _TZ-ALPHA? 0= IF 2DROP 0 EXIT THEN
        SWAP 1+ SWAP 1-
    REPEAT 2DROP -1 ;

: _TZ-PUT-BYTES  ( dst pos addr u -- dst pos' )
    BEGIN DUP WHILE
        OVER C@ >R 2SWAP R> _TZ-PUT 2SWAP SWAP 1+ SWAP 1-
    REPEAT 2DROP ;

\ A name bare when it is all letters, else quoted in <>.
: _TZ-PUT-NAME  ( dst pos field -- dst pos' )
    DUP 8 + SWAP @
    2DUP _TZ-ALPHA-ONLY? IF _TZ-PUT-BYTES EXIT THEN
    2SWAP [CHAR] < _TZ-PUT 2SWAP _TZ-PUT-BYTES [CHAR] > _TZ-PUT ;

: _TZ-PUT-RULE  ( dst pos rule -- dst pos' )
    >R
    R@ _TZ-RULE.KIND @ CASE
        _TZ-R-JULIAN OF
            [CHAR] J _TZ-PUT R@ _TZ-RULE.A @ _TZ-PUT-NUMBER
        ENDOF
        _TZ-R-DAY OF
            R@ _TZ-RULE.A @ _TZ-PUT-NUMBER
        ENDOF
        _TZ-R-MONTH OF
            [CHAR] M _TZ-PUT R@ _TZ-RULE.A @ _TZ-PUT-NUMBER
            [CHAR] . _TZ-PUT R@ _TZ-RULE.B @ _TZ-PUT-NUMBER
            [CHAR] . _TZ-PUT R@ _TZ-RULE.C @ _TZ-PUT-NUMBER
        ENDOF
    ENDCASE
    R@ _TZ-RULE.TIME @ _TZ-DEFAULT-TIME <> IF
        [CHAR] / _TZ-PUT R@ _TZ-RULE.TIME @ _TZ-PUT-CLOCK
    THEN
    R> DROP ;

\ The canonical TZ string: default offsets and transition times omitted,
\ names quoted only when they need it.
: _TZ-FORMAT  ( dst zone -- dst written )
    >R 0
    R@ _TZ.STD-NAME _TZ-PUT-NAME
    R@ _TZ.STD-OFF @ NEGATE _TZ-PUT-CLOCK
    R@ TZ-DST? IF
        R@ _TZ.DST-NAME _TZ-PUT-NAME
        R@ _TZ.DST-OFF @ R@ _TZ.STD-OFF @ 3600 + <> IF
            R@ _TZ.DST-OFF @ NEGATE _TZ-PUT-CLOCK
        THEN
        [CHAR] , _TZ-PUT R@ _TZ.START _TZ-PUT-RULE
        [CHAR] , _TZ-PUT R@ _TZ.END _TZ-PUT-RULE
    THEN
    R> DROP ;

: TZ-FORMAT  ( zone destination capacity -- written status )
    DUP 0< IF DROP 2DROP 0 DT-S-INVALID EXIT THEN
    2 PICK _TZ-VALID? 0= IF DROP 2DROP 0 DT-S-INVALID EXIT THEN
    0 3 PICK _TZ-FORMAT NIP              ( zone dst cap need )
    TUCK < IF DROP 2DROP 0 DT-S-CAPACITY EXIT THEN
    2DUP _TZ-SPAN-STATUS ?DUP IF >R DROP 2DROP 0 R> EXIT THEN
    DROP SWAP _TZ-FORMAT NIP DT-S-OK ;

\ =====================================================================
\  Layer 3 - Transitions
\ =====================================================================

\ Local midnight of weekday d (0 Sunday) in week w (5 = last) of month m.
: _TZ-MONTH-DAY  ( year rule -- local-s )
    >R
    DUP R@ _TZ-RULE.A @ 1 DT-YMD>EPOCH-S DROP     ( year first )
    DUP DT-WEEKDAY DROP 7 MOD                     ( year first sunday0 )
    R@ _TZ-RULE.C @ SWAP - 7 + 7 MOD              ( year first day0 )
    R@ _TZ-RULE.B @ 1- 7 * +                      ( year first index )
    ROT R> _TZ-RULE.A @ DT-MONTH-DAYS DROP        ( first index days )
    OVER SWAP < 0= IF 7 - THEN
    86400 * + ;

\ Local seconds of the rule's transition in year, read on the wall clock
\ in force just before it.  Flag false outside 1970..9999.
: _TZ-RULE-LOCAL  ( year rule -- local-s flag )
    OVER 1 1 DT-YMD>EPOCH-S IF 2DROP DROP 0 0 EXIT THEN   ( year rule jan1 )
    OVER _TZ-RULE.KIND @ CASE
        _TZ-R-JULIAN OF
            OVER _TZ-RULE.A @ 1-                         \ day index
            3 PICK 2 DT-MONTH-DAYS DROP 29 = IF
                DUP 59 >= IF 1+ THEN                     \ skip February 29
            THEN
            86400 * +
        ENDOF
        _TZ-R-DAY OF
            OVER _TZ-RULE.A @ 86400 * +
        ENDOF
        _TZ-R-MONTH OF
            DROP 2DUP _TZ-MONTH-DAY
        ENDOF
    ENDCASE
    SWAP _TZ-RULE.TIME @ + NIP -1 ;

\ The instant the daylight rule starts in year.  The wall clock before
\ the start shows standard time.
: _TZ-START-UTC  ( year zone -- utc flag )
    DUP >R _TZ.START _TZ-RULE-LOCAL
    SWAP R> _TZ.STD-OFF @ - SWAP ;

\ The instant it ends.  The wall clock before the end shows daylight time.
: _TZ-END-UTC  ( year zone -- utc flag )
    DUP >R _TZ.END _TZ-RULE-LOCAL
    SWAP R> _TZ.DST-OFF @ - SWAP ;

\ The latest of xt's transitions over year-1..year+1 at or before t, or
\ _TZ-NONE.  xt is ( year zone -- utc flag ).
: _TZ-LATEST  ( t zone year xt -- latest )
    SWAP _TZ-NONE SWAP                    ( t zone xt latest year )
    DUP 2 + SWAP 1- DO
        I 3 PICK 3 PICK EXECUTE           ( t zone xt latest utc flag )
        IF
            DUP 5 PICK <= IF MAX ELSE DROP THEN
        ELSE
            DROP
        THEN
    LOOP
    >R 2DROP DROP R> ;

\ The standard-time year of an instant, kept within 1970..9999.
: _TZ-YEAR  ( t zone -- year )
    _TZ.STD-OFF @ + 0 MAX DT-EPOCH-S-MAX MIN
    DT-EPOCH-S>YMD DROP 2DROP ;

\ Daylight time holds at t when the most recent transition was a start.
\ A start and an end at the same instant leave daylight time in force,
\ which is how a TZ string spells permanent daylight time.
: _TZ-DST-AT?  ( t zone -- flag )
    DUP TZ-DST? 0= IF 2DROP 0 EXIT THEN
    2DUP _TZ-YEAR                                        ( t zone year )
    2 PICK 2 PICK 2 PICK ['] _TZ-START-UTC _TZ-LATEST    ( t zone year s* )
    3 PICK 3 PICK 3 PICK ['] _TZ-END-UTC _TZ-LATEST      ( t zone year s* e* )
    2DUP MAX _TZ-NONE = IF
        \ Before every known transition: the state the year ends in.
        2DROP ROT DROP SWAP                              ( year zone )
        2DUP _TZ-START-UTC DROP ROT ROT _TZ-END-UTC DROP >= EXIT
    THEN
    >= >R DROP 2DROP R> ;

\ =====================================================================
\  Layer 4 - Public conversions
\ =====================================================================

: TZ-OFFSET  ( utc-s zone -- offset-s dst? status )
    DUP _TZ-VALID? 0= IF 2DROP 0 0 DT-S-INVALID EXIT THEN
    OVER _TZ-INSTANT? 0= IF 2DROP 0 0 DT-S-RANGE EXIT THEN
    TUCK _TZ-DST-AT? IF
        _TZ.DST-OFF @ -1
    ELSE
        _TZ.STD-OFF @ 0
    THEN DT-S-OK ;

\ The name in force at an instant.  The bytes stay in the zone record.
: TZ-NAME  ( utc-s zone -- addr u status )
    DUP _TZ-VALID? 0= IF 2DROP 0 0 DT-S-INVALID EXIT THEN
    OVER _TZ-INSTANT? 0= IF 2DROP 0 0 DT-S-RANGE EXIT THEN
    TUCK _TZ-DST-AT? IF _TZ.DST-NAME ELSE _TZ.STD-NAME THEN
    DUP 8 + SWAP @ DT-S-OK ;

: TZ-UTC>LOCAL  ( utc-s zone -- local-s status )
    OVER >R TZ-OFFSET
    ?DUP IF NIP NIP R> DROP 0 SWAP EXIT THEN
    DROP R> +
    DUP _TZ-INSTANT? IF DT-S-OK ELSE DROP 0 DT-S-RANGE THEN ;

\ Publish an instant with its kind, or a range failure outside 1970..9999.
: _TZ-RESULT  ( utc kind -- utc kind status )
    OVER _TZ-INSTANT? IF DT-S-OK EXIT THEN
    2DROP 0 0 DT-S-RANGE ;

\ The instant is consistent when reading it back shows the assumed time.
: _TZ-HOLDS?  ( utc zone dst? -- flag )
    >R OVER _TZ-INSTANT? 0= IF R> DROP 2DROP 0 EXIT THEN
    _TZ-DST-AT? R> = ;

: TZ-LOCAL>UTC  ( local-s zone -- utc-s kind status )
    DUP _TZ-VALID? 0= IF 2DROP 0 0 DT-S-INVALID EXIT THEN
    OVER _TZ-INSTANT? 0= IF 2DROP 0 0 DT-S-RANGE EXIT THEN
    DUP TZ-DST? 0= IF
        _TZ.STD-OFF @ - TZ-K-UNIQUE _TZ-RESULT EXIT
    THEN
    2DUP _TZ.STD-OFF @ -                       ( local zone u-std )
    ROT 2 PICK _TZ.DST-OFF @ -                 ( zone u-std u-dst )
    DUP 3 PICK -1 _TZ-HOLDS?                   ( zone u-std u-dst dst-holds )
    2 PICK 4 PICK 0 _TZ-HOLDS?                 ( ... dst-holds std-holds )
    2DUP AND IF
        \ The clocks repeat this time: its first occurrence.
        2DROP MIN NIP TZ-K-OVERLAP _TZ-RESULT EXIT
    THEN
    IF DROP DROP NIP TZ-K-UNIQUE _TZ-RESULT EXIT THEN
    IF NIP NIP TZ-K-UNIQUE _TZ-RESULT EXIT THEN
    \ The clocks skip this time: read it with the offset before the change.
    MAX NIP TZ-K-GAP _TZ-RESULT ;
