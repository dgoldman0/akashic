\ toml.f — TOML v1.0 reader for KDOS / Megapad-64
\
\ Zero-copy cursor-based parser following the same (addr len)
\ model as json.f.
\
\ Prefix: TOML-   (public API)
\         _TOML-  (internal helpers)

REQUIRE string.f
REQUIRE ../text/utf8.f

PROVIDED akashic-toml

\ =====================================================================
\  Error Handling  (mirrors json.f)
\ =====================================================================

VARIABLE TOML-ERR
VARIABLE TOML-ABORT-ON-ERROR
0 TOML-ERR !
0 TOML-ABORT-ON-ERROR !

1 CONSTANT TOML-E-NOT-FOUND
2 CONSTANT TOML-E-WRONG-TYPE
3 CONSTANT TOML-E-UNTERMINATED
4 CONSTANT TOML-E-UNEXPECTED
5 CONSTANT TOML-E-OVERFLOW
6 CONSTANT TOML-E-BAD-KEY
7 CONSTANT TOML-E-BAD-INT

: TOML-FAIL  ( err-code -- )
    TOML-ERR !
    TOML-ABORT-ON-ERROR @ IF ABORT" TOML error" THEN ;

: TOML-OK?  ( -- flag )  TOML-ERR @ 0= ;
: TOML-CLEAR-ERR  ( -- )  0 TOML-ERR ! ;

\ _TOML-FAIL-00 ( err -- 0 0 )  fail and leave 0 0
: _TOML-FAIL-00  ( err -- 0 0 )
    TOML-FAIL 0 0 ;

\ =====================================================================
\  Layer 0 — Primitives
\ =====================================================================

: TOML-SKIP-WS  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 32 = SWAP 9 = OR 0= IF EXIT THEN
        1 /STRING
    REPEAT ;

: TOML-SKIP-COMMENT  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 35 <> IF EXIT THEN
    BEGIN
        DUP 0> WHILE
        OVER C@ 10 = IF EXIT THEN
        OVER C@ 13 = IF EXIT THEN
        1 /STRING
    REPEAT ;

: TOML-SKIP-EOL  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 13 = IF
        1 /STRING
        DUP 0> IF OVER C@ 10 = IF 1 /STRING THEN THEN EXIT
    THEN
    OVER C@ 10 = IF 1 /STRING THEN ;

: TOML-SKIP-LINE  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 10 = SWAP 13 = OR IF
            TOML-SKIP-EOL EXIT
        THEN
        1 /STRING
    REPEAT ;

: TOML-SKIP-NL  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@
        DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR IF
            1 /STRING
        ELSE
            OVER C@ 35 = IF TOML-SKIP-COMMENT
            ELSE EXIT
            THEN
        THEN
    REPEAT ;

\ ── Multi-char lookahead ─────────────────────────────────────────────

: _TOML-3DQ?  ( addr len -- flag )
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER C@ 34 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 34 <>  IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 34 =  NIP NIP ;

: _TOML-3SQ?  ( addr len -- flag )
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER C@ 39 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 39 <>  IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 39 =  NIP NIP ;

: _TOML-2BRACK?  ( addr len -- flag )
    DUP 2 < IF 2DROP 0 EXIT THEN
    OVER C@ 91 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 91 =   NIP NIP ;

\ ── Multiline leading-newline trim ───────────────────────────────────

: _TOML-TRIM-ML-OPEN  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 10 = IF 1 /STRING EXIT THEN
    OVER C@ 13 = IF
        1 /STRING
        DUP 0> IF OVER C@ 10 = IF 1 /STRING THEN THEN
    THEN ;

\ ── String skipping ──────────────────────────────────────────────────

: TOML-SKIP-BASIC-STRING  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 34 <> IF EXIT THEN
    1 /STRING
    BEGIN
        DUP 0> WHILE
        OVER C@ 92 = IF
            DUP 2 >= IF 2 /STRING ELSE 1 /STRING THEN
        ELSE
            OVER C@ 34 = IF 1 /STRING EXIT THEN
            1 /STRING
        THEN
    REPEAT
    TOML-E-UNTERMINATED TOML-FAIL ;

: TOML-SKIP-LITERAL-STRING  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 39 <> IF EXIT THEN
    1 /STRING
    BEGIN
        DUP 0> WHILE
        OVER C@ 39 = IF 1 /STRING EXIT THEN
        1 /STRING
    REPEAT
    TOML-E-UNTERMINATED TOML-FAIL ;

: TOML-SKIP-ML-BASIC  ( addr len -- addr' len' )
    3 /STRING  _TOML-TRIM-ML-OPEN
    BEGIN
        DUP 0> WHILE
        OVER C@ 92 = IF
            DUP 2 >= IF 2 /STRING ELSE 1 /STRING THEN
        ELSE
            2DUP _TOML-3DQ? IF 3 /STRING EXIT THEN
            1 /STRING
        THEN
    REPEAT
    TOML-E-UNTERMINATED TOML-FAIL ;

: TOML-SKIP-ML-LITERAL  ( addr len -- addr' len' )
    3 /STRING  _TOML-TRIM-ML-OPEN
    BEGIN
        DUP 0> WHILE
        2DUP _TOML-3SQ? IF 3 /STRING EXIT THEN
        1 /STRING
    REPEAT
    TOML-E-UNTERMINATED TOML-FAIL ;

: TOML-SKIP-STRING  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 34 = IF
        2DUP _TOML-3DQ? IF TOML-SKIP-ML-BASIC EXIT THEN
        TOML-SKIP-BASIC-STRING EXIT
    THEN
    OVER C@ 39 = IF
        2DUP _TOML-3SQ? IF TOML-SKIP-ML-LITERAL EXIT THEN
        TOML-SKIP-LITERAL-STRING EXIT
    THEN ;

\ ── Value skipping ───────────────────────────────────────────────────

VARIABLE _TSV-DEPTH
: TOML-SKIP-VALUE  ( addr len -- addr' len' )
    TOML-SKIP-WS
    DUP 0> 0= IF EXIT THEN
    OVER C@ DUP 34 = OVER 39 = OR IF
        DROP TOML-SKIP-STRING EXIT
    THEN
    DUP 91 = OVER 123 = OR IF
        DROP
        1 _TSV-DEPTH !  1 /STRING
        BEGIN DUP 0> _TSV-DEPTH @ 0> AND WHILE
            OVER C@ DUP 34 = OVER 39 = OR IF
                DROP TOML-SKIP-STRING
            ELSE DUP 91 = OVER 123 = OR IF
                DROP 1 _TSV-DEPTH +!  1 /STRING
            ELSE DUP 93 = OVER 125 = OR IF
                DROP -1 _TSV-DEPTH +!  1 /STRING
            ELSE DUP 35 = IF
                DROP TOML-SKIP-COMMENT
            ELSE DUP 10 = OVER 13 = OR IF
                DROP TOML-SKIP-EOL
            ELSE
                DROP 1 /STRING
            THEN THEN THEN THEN THEN
        REPEAT EXIT
    THEN
    DROP
    BEGIN DUP 0> WHILE
        OVER C@ DUP 44 = OVER 93 = OR OVER 125 = OR
        OVER 32 = OR OVER 9 = OR OVER 10 = OR OVER 13 = OR
        SWAP 35 = OR IF EXIT THEN
        1 /STRING
    REPEAT ;

\ =====================================================================
\  Layer 1 — Type Introspection
\ =====================================================================

0 CONSTANT TOML-T-ERROR
1 CONSTANT TOML-T-STRING
2 CONSTANT TOML-T-INTEGER
3 CONSTANT TOML-T-FLOAT
4 CONSTANT TOML-T-BOOL
5 CONSTANT TOML-T-DATETIME
6 CONSTANT TOML-T-ARRAY
7 CONSTANT TOML-T-INLINE-TABLE

: _TOML-DIGIT?  ( c -- flag )  DUP 48 >= SWAP 57 <= AND ;

: _TOML-STARTS-TRUE?  ( addr len -- flag )
    DUP 4 < IF 2DROP 0 EXIT THEN
    OVER C@ 116 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 114 <>  IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 117 <> IF 2DROP 0 EXIT THEN
    OVER 3 + C@ 101 =  NIP NIP ;

: _TOML-STARTS-FALSE?  ( addr len -- flag )
    DUP 5 < IF 2DROP 0 EXIT THEN
    OVER C@ 102 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 97 <>   IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 108 <> IF 2DROP 0 EXIT THEN
    OVER 3 + C@ 115 <> IF 2DROP 0 EXIT THEN
    OVER 4 + C@ 101 =  NIP NIP ;

: _TOML-NUM-HAS-DOT-OR-E?  ( addr len -- flag )
    BEGIN DUP 0> WHILE
        OVER C@
        DUP 46 = IF DROP 2DROP -1 EXIT THEN
        DUP 101 = OVER 69 = OR IF DROP 2DROP -1 EXIT THEN
        DUP 32 = OVER 9 = OR OVER 10 = OR OVER 13 = OR
        OVER 44 = OR OVER 93 = OR OVER 125 = OR SWAP 35 = OR
        IF 2DROP 0 EXIT THEN
        1 /STRING
    REPEAT
    2DROP 0 ;

: _TOML-STARTS-INF?  ( addr len -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 43 = SWAP 45 = OR IF 1 /STRING THEN
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER C@ 105 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 110 <>  IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 102 =  NIP NIP ;

: _TOML-STARTS-NAN?  ( addr len -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 43 = SWAP 45 = OR IF 1 /STRING THEN
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER C@ 110 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 97 <>   IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 110 =  NIP NIP ;

: TOML-TYPE?  ( addr len -- type )
    TOML-SKIP-WS
    DUP 0> 0= IF 2DROP TOML-T-ERROR EXIT THEN
    OVER C@
    DUP 34 = OVER 39 = OR IF DROP 2DROP TOML-T-STRING EXIT THEN
    DUP 91 = IF DROP 2DROP TOML-T-ARRAY EXIT THEN
    DUP 123 = IF DROP 2DROP TOML-T-INLINE-TABLE EXIT THEN
    DUP 116 = IF
        DROP 2DUP _TOML-STARTS-TRUE? IF 2DROP TOML-T-BOOL EXIT THEN
        2DROP TOML-T-ERROR EXIT
    THEN
    DUP 102 = IF
        DROP 2DUP _TOML-STARTS-FALSE? IF 2DROP TOML-T-BOOL EXIT THEN
        2DROP TOML-T-ERROR EXIT
    THEN
    DROP
    2DUP _TOML-STARTS-INF? IF 2DROP TOML-T-FLOAT EXIT THEN
    2DUP _TOML-STARTS-NAN? IF 2DROP TOML-T-FLOAT EXIT THEN
    OVER C@ DUP _TOML-DIGIT? OVER 43 = OR SWAP 45 = OR IF
        DUP 10 >= IF
            OVER 4 + C@ 45 = IF 2DROP TOML-T-DATETIME EXIT THEN
        THEN
        2DUP _TOML-NUM-HAS-DOT-OR-E? IF 2DROP TOML-T-FLOAT EXIT THEN
        2DROP TOML-T-INTEGER EXIT
    THEN
    2DROP TOML-T-ERROR ;

: TOML-STRING?       ( addr len -- flag )  TOML-TYPE? TOML-T-STRING = ;
: TOML-INTEGER?      ( addr len -- flag )  TOML-TYPE? TOML-T-INTEGER = ;
: TOML-FLOAT?        ( addr len -- flag )  TOML-TYPE? TOML-T-FLOAT = ;
: TOML-BOOL?         ( addr len -- flag )  TOML-TYPE? TOML-T-BOOL = ;
: TOML-DATETIME?     ( addr len -- flag )  TOML-TYPE? TOML-T-DATETIME = ;
: TOML-ARRAY?        ( addr len -- flag )  TOML-TYPE? TOML-T-ARRAY = ;
: TOML-INLINE-TABLE? ( addr len -- flag )  TOML-TYPE? TOML-T-INLINE-TABLE = ;

\ =====================================================================
\  Layer 2 — Value Extraction
\ =====================================================================

\ ── String extraction helpers ────────────────────────────────────────
\ Each returns ( str-addr str-len ).  Zero-copy into source buffer.
\ Uses variables to avoid deep stack juggling.

VARIABLE _TGS-A    \ cursor addr
VARIABLE _TGS-L    \ cursor len
VARIABLE _TGS-CNT  \ byte count

\ _TOML-GET-BASIC-STR ( addr len -- str-a str-l )
\   addr points at opening ".  Returns inner content (no quotes).
: _TOML-GET-BASIC-STR  ( addr len -- str-a str-l )
    1 /STRING  _TGS-L ! _TGS-A !  0 _TGS-CNT !
    _TGS-A @
    BEGIN _TGS-L @ 0> WHILE
        _TGS-A @ C@ 92 = IF
            _TGS-L @ 2 < IF
                DROP TOML-E-UNTERMINATED _TOML-FAIL-00 EXIT
            THEN
            2 _TGS-CNT +!
            _TGS-A @ 2 + _TGS-A !  _TGS-L @ 2 - _TGS-L !
        ELSE
            _TGS-A @ C@ 34 = IF
                _TGS-CNT @ EXIT
            THEN
            1 _TGS-CNT +!
            _TGS-A @ 1+ _TGS-A !  _TGS-L @ 1- _TGS-L !
        THEN
    REPEAT
    DROP TOML-E-UNTERMINATED _TOML-FAIL-00 ;

\ _TOML-GET-LITERAL-STR ( addr len -- str-a str-l )
\   addr points at opening '.  Returns inner content.
: _TOML-GET-LITERAL-STR  ( addr len -- str-a str-l )
    1 /STRING  _TGS-L ! _TGS-A !  0 _TGS-CNT !
    _TGS-A @
    BEGIN _TGS-L @ 0> WHILE
        _TGS-A @ C@ 39 = IF _TGS-CNT @ EXIT THEN
        1 _TGS-CNT +!
        _TGS-A @ 1+ _TGS-A !  _TGS-L @ 1- _TGS-L !
    REPEAT
    DROP TOML-E-UNTERMINATED _TOML-FAIL-00 ;

\ _TOML-GET-ML-BASIC-STR ( addr len -- str-a str-l )
\   addr points at opening """.  Returns inner content after trim.
: _TOML-GET-ML-BASIC-STR  ( addr len -- str-a str-l )
    3 /STRING  _TOML-TRIM-ML-OPEN
    _TGS-L ! _TGS-A !  0 _TGS-CNT !
    _TGS-A @
    BEGIN _TGS-L @ 0> WHILE
        _TGS-A @ C@ 92 = IF
            _TGS-L @ 2 < IF
                DROP TOML-E-UNTERMINATED _TOML-FAIL-00 EXIT
            THEN
            2 _TGS-CNT +!
            _TGS-A @ 2 + _TGS-A !  _TGS-L @ 2 - _TGS-L !
        ELSE
            _TGS-A @ _TGS-L @ _TOML-3DQ? IF
                _TGS-CNT @ EXIT
            THEN
            1 _TGS-CNT +!
            _TGS-A @ 1+ _TGS-A !  _TGS-L @ 1- _TGS-L !
        THEN
    REPEAT
    DROP TOML-E-UNTERMINATED _TOML-FAIL-00 ;

\ _TOML-GET-ML-LITERAL-STR ( addr len -- str-a str-l )
\   addr points at opening '''.  Returns inner content after trim.
: _TOML-GET-ML-LITERAL-STR  ( addr len -- str-a str-l )
    3 /STRING  _TOML-TRIM-ML-OPEN
    _TGS-L ! _TGS-A !  0 _TGS-CNT !
    _TGS-A @
    BEGIN _TGS-L @ 0> WHILE
        _TGS-A @ _TGS-L @ _TOML-3SQ? IF
            _TGS-CNT @ EXIT
        THEN
        1 _TGS-CNT +!
        _TGS-A @ 1+ _TGS-A !  _TGS-L @ 1- _TGS-L !
    REPEAT
    DROP TOML-E-UNTERMINATED _TOML-FAIL-00 ;

\ TOML-GET-STRING ( addr len -- str-addr str-len )
\   Dispatch to the appropriate string extractor.
: TOML-GET-STRING  ( addr len -- str-addr str-len )
    TOML-SKIP-WS
    DUP 0> 0= IF 2DROP TOML-E-WRONG-TYPE _TOML-FAIL-00 EXIT THEN
    OVER C@ 34 = IF
        2DUP _TOML-3DQ? IF _TOML-GET-ML-BASIC-STR EXIT THEN
        _TOML-GET-BASIC-STR EXIT
    THEN
    OVER C@ 39 = IF
        2DUP _TOML-3SQ? IF _TOML-GET-ML-LITERAL-STR EXIT THEN
        _TOML-GET-LITERAL-STR EXIT
    THEN
    2DROP TOML-E-WRONG-TYPE _TOML-FAIL-00 ;

\ ── String unescaping ────────────────────────────────────────────────

VARIABLE _TU-DST
VARIABLE _TU-MAX
VARIABLE _TU-POS

: _TU-HEX  ( c -- n )
    DUP 48 >= OVER 57 <= AND IF 48 - EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - EXIT THEN
    DROP -1 ;

: _TU-STORE  ( c -- )
    _TU-POS @ _TU-MAX @ >= IF DROP TOML-E-OVERFLOW TOML-FAIL EXIT THEN
    _TU-DST @ _TU-POS @ + C!  1 _TU-POS +! ;

VARIABLE _TU-CP
: _TU-PARSE-HEX  ( addr n -- codepoint )
    0 _TU-CP !
    0 DO
        DUP I + C@ _TU-HEX
        DUP 0< IF DROP DROP 0xFFFD _TU-CP ! LEAVE THEN
        _TU-CP @ 4 LSHIFT OR _TU-CP !
    LOOP
    DROP _TU-CP @ ;

CREATE _TU-UBUF 4 ALLOT
: _TU-ENCODE-UTF8  ( cp -- )
    DUP 0x80 < IF _TU-STORE EXIT THEN
    _TU-UBUF UTF8-ENCODE _TU-UBUF -
    _TU-UBUF SWAP 0 DO DUP I + C@ _TU-STORE LOOP DROP ;

\ _TU-ESC-SIMPLE ( c -- c' )  map simple escape char to output char, -1 if not simple
: _TU-ESC-SIMPLE  ( c -- c' )
    DUP 110 = IF DROP 10 EXIT THEN
    DUP 114 = IF DROP 13 EXIT THEN
    DUP 116 = IF DROP  9 EXIT THEN
    DUP  98 = IF DROP  8 EXIT THEN
    DUP 102 = IF DROP 12 EXIT THEN
    DUP  34 = IF DROP 34 EXIT THEN
    DUP  92 = IF DROP 92 EXIT THEN
    DROP -1 ;

\ _TU-ESC-UNICODE ( addr len ndigits -- addr' len' )
: _TU-ESC-UNICODE  ( addr len ndigits -- addr' len' )
    >R 1 /STRING
    DUP R@ < IF R> DROP 0xFFFD _TU-ENCODE-UTF8 EXIT THEN
    OVER R@ _TU-PARSE-HEX _TU-ENCODE-UTF8
    R> /STRING ;

\ _TU-ESC-NEWLINE ( addr len -- addr' len' )  skip ws+newlines after line-ending backslash
: _TU-ESC-NEWLINE  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR
        0= IF EXIT THEN  1 /STRING
    REPEAT ;

: _TU-ESCAPE  ( addr len -- addr' len' )
    1 /STRING
    DUP 0> 0= IF EXIT THEN
    OVER C@
    DUP 117 = IF DROP 4 _TU-ESC-UNICODE EXIT THEN
    DUP 85  = IF DROP 8 _TU-ESC-UNICODE EXIT THEN
    DUP 10 = OVER 13 = OR IF DROP _TU-ESC-NEWLINE EXIT THEN
    _TU-ESC-SIMPLE
    DUP -1 = IF DROP OVER C@ _TU-STORE 1 /STRING EXIT THEN
    _TU-STORE 1 /STRING ;

: TOML-UNESCAPE  ( src slen dest dmax -- len )
    _TU-MAX ! _TU-DST ! 0 _TU-POS !
    BEGIN DUP 0> WHILE
        OVER C@ 92 = IF
            _TU-ESCAPE
        ELSE
            OVER C@ _TU-STORE  1 /STRING
        THEN
    REPEAT
    2DROP _TU-POS @ ;

\ ── Integer extraction ───────────────────────────────────────────────

VARIABLE _TGI-NEG
VARIABLE _TGI-ACC

\ _TGI-ACCUM-HEX ( addr len -- addr' len' )
: _TGI-ACCUM-HEX  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ _TU-HEX DUP 0< IF DROP EXIT THEN
            _TGI-ACC @ 16 * + _TGI-ACC !  1 /STRING
        THEN
    REPEAT ;

\ _TGI-ACCUM-OCT ( addr len -- addr' len' )
: _TGI-ACCUM-OCT  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ DUP 48 >= SWAP 55 <= AND 0= IF EXIT THEN
            OVER C@ 48 -  _TGI-ACC @ 8 * + _TGI-ACC !  1 /STRING
        THEN
    REPEAT ;

\ _TGI-ACCUM-BIN ( addr len -- addr' len' )
: _TGI-ACCUM-BIN  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ DUP 48 = SWAP 49 = OR 0= IF EXIT THEN
            OVER C@ 48 -  _TGI-ACC @ 2 * + _TGI-ACC !  1 /STRING
        THEN
    REPEAT ;

\ _TGI-ACCUM-DEC ( addr len -- addr' len' )
: _TGI-ACCUM-DEC  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ DUP 48 >= SWAP 57 <= AND 0= IF EXIT THEN
            OVER C@ 48 -  _TGI-ACC @ 10 * + _TGI-ACC !  1 /STRING
        THEN
    REPEAT ;

\ _TGI-RESULT ( -- n )
: _TGI-RESULT  ( -- n )
    _TGI-NEG @ IF _TGI-ACC @ NEGATE ELSE _TGI-ACC @ THEN ;

: TOML-GET-INT  ( addr len -- n )
    TOML-SKIP-WS
    0 _TGI-NEG !  0 _TGI-ACC !
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ 43 = IF 1 /STRING THEN
    DUP 0> IF OVER C@ 45 = IF -1 _TGI-NEG ! 1 /STRING THEN THEN
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    \ Check for 0x, 0o, 0b prefix
    OVER C@ 48 = OVER 2 >= AND IF
        OVER 1+ C@ DUP 120 = OVER 88 = OR IF
            DROP 2 /STRING _TGI-ACCUM-HEX 2DROP _TGI-RESULT EXIT
        THEN
        DUP 111 = OVER 79 = OR IF
            DROP 2 /STRING _TGI-ACCUM-OCT 2DROP _TGI-RESULT EXIT
        THEN
        DUP 98 = OVER 66 = OR IF
            DROP 2 /STRING _TGI-ACCUM-BIN 2DROP _TGI-RESULT EXIT
        THEN
        DROP
    THEN
    _TGI-ACCUM-DEC 2DROP _TGI-RESULT ;

\ ── Boolean extraction ───────────────────────────────────────────────

: TOML-GET-BOOL  ( addr len -- flag )
    TOML-SKIP-WS
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ 116 = IF 2DROP -1 EXIT THEN
    OVER C@ 102 = IF 2DROP  0 EXIT THEN
    2DROP TOML-E-WRONG-TYPE TOML-FAIL 0 ;

\ ── Float / Datetime raw extraction ──────────────────────────────────

: TOML-GET-FLOAT-STR  ( addr len -- str-a str-l )
    TOML-SKIP-WS  OVER
    BEGIN DUP 0> WHILE
        OVER C@ DUP 32 = OVER 9 = OR OVER 10 = OR OVER 13 = OR
        OVER 44 = OR OVER 93 = OR OVER 125 = OR SWAP 35 = OR
        IF NIP SWAP - EXIT THEN
        1 /STRING
    REPEAT
    NIP SWAP - ;

: TOML-GET-DATETIME-STR  ( addr len -- str-a str-l )
    TOML-GET-FLOAT-STR ;

\ =====================================================================
\  Layer 3 — Key Extraction
\ =====================================================================

CREATE _TEK-BUF 256 ALLOT
VARIABLE _TEK-POS
VARIABLE _TEK-A
VARIABLE _TEK-L

\ _TEK-COPY-BARE ( -- )  copy bare-key chars into _TEK-BUF
: _TEK-COPY-BARE  ( -- )
    BEGIN _TEK-L @ 0> WHILE
        _TEK-A @ C@
        DUP 65 >= OVER 90 <= AND
        OVER 97 >= 2 PICK 122 <= AND OR
        OVER 48 >= 2 PICK 57 <= AND OR
        OVER 95 = OR SWAP 45 = OR IF
            _TEK-A @ C@ _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
            _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
        ELSE EXIT THEN
    REPEAT ;

\ _TEK-COPY-BASIC ( -- )  copy content of "..." key into buf
: _TEK-COPY-BASIC  ( -- )
    _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
    BEGIN _TEK-L @ 0> WHILE
        _TEK-A @ C@ 92 = IF
            _TEK-A @ C@ _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
            _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
            _TEK-L @ 0> IF
                _TEK-A @ C@ _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
                _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
            THEN
        ELSE
            _TEK-A @ C@ 34 = IF
                _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !  EXIT
            THEN
            _TEK-A @ C@ _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
            _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
        THEN
    REPEAT ;

\ _TEK-COPY-LITERAL ( -- )  copy content of '...' key into buf
: _TEK-COPY-LITERAL  ( -- )
    _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
    BEGIN _TEK-L @ 0> WHILE
        _TEK-A @ C@ 39 = IF
            _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !  EXIT
        THEN
        _TEK-A @ C@ _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
        _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
    REPEAT ;

\ _TEK-SKIP-WS-CHECK-DOT ( -- )  after a key segment, check for dot
: _TEK-SKIP-WS-CHECK-DOT  ( -- )
    \ Skip whitespace
    BEGIN _TEK-L @ 0> WHILE
        _TEK-A @ C@ DUP 32 = SWAP 9 = OR 0= IF EXIT THEN
        _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
    REPEAT ;

\ _TOML-EXTRACT-KEY ( addr len -- key-a key-l tail-a tail-l )
: _TOML-EXTRACT-KEY  ( addr len -- key-a key-l tail-a tail-l )
    0 _TEK-POS !
    TOML-SKIP-WS  _TEK-L ! _TEK-A !
    BEGIN _TEK-L @ 0> WHILE
        _TEK-A @ C@
        DUP 34 = IF
            DROP _TEK-COPY-BASIC
            _TEK-SKIP-WS-CHECK-DOT
            _TEK-L @ 0> IF _TEK-A @ C@ 46 = IF
                46 _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
                _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
                _TEK-SKIP-WS-CHECK-DOT
            THEN THEN
            _TEK-L @ 0> IF _TEK-A @ C@ 61 = IF
                _TEK-BUF _TEK-POS @  _TEK-A @ _TEK-L @  EXIT
            THEN THEN
        ELSE DUP 39 = IF
            DROP _TEK-COPY-LITERAL
            _TEK-SKIP-WS-CHECK-DOT
            _TEK-L @ 0> IF _TEK-A @ C@ 46 = IF
                46 _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
                _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
                _TEK-SKIP-WS-CHECK-DOT
            THEN THEN
            _TEK-L @ 0> IF _TEK-A @ C@ 61 = IF
                _TEK-BUF _TEK-POS @  _TEK-A @ _TEK-L @  EXIT
            THEN THEN
        ELSE DUP 46 = IF
            DROP
            46 _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
            _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
            _TEK-SKIP-WS-CHECK-DOT
        ELSE
            DUP 65 >= OVER 90 <= AND
            OVER 97 >= 2 PICK 122 <= AND OR
            OVER 48 >= 2 PICK 57 <= AND OR
            OVER 95 = OR SWAP 45 = OR IF
                _TEK-COPY-BARE
                _TEK-SKIP-WS-CHECK-DOT
                _TEK-L @ 0> IF _TEK-A @ C@ 46 = IF
                    46 _TEK-BUF _TEK-POS @ + C!  1 _TEK-POS +!
                    _TEK-A @ 1+ _TEK-A !  _TEK-L @ 1- _TEK-L !
                    _TEK-SKIP-WS-CHECK-DOT
                THEN THEN
                _TEK-L @ 0> IF _TEK-A @ C@ 61 = IF
                    _TEK-BUF _TEK-POS @  _TEK-A @ _TEK-L @  EXIT
                THEN THEN
            ELSE
                DROP
                _TEK-BUF _TEK-POS @  _TEK-A @ _TEK-L @  EXIT
            THEN
        THEN THEN THEN
    REPEAT
    _TEK-BUF _TEK-POS @  _TEK-A @ _TEK-L @ ;

\ =====================================================================
\  Layer 4 — Table / Section Navigation
\ =====================================================================

: _TOML-AT-HEADER?  ( addr len -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ 91 <> IF 2DROP 0 EXIT THEN
    DUP 2 >= IF OVER 1+ C@ 91 = IF 2DROP 0 EXIT THEN THEN
    2DROP -1 ;

: _TOML-AT-AHEADER?  ( addr len -- flag )
    2DUP _TOML-2BRACK? NIP NIP ;

\ _TOML-EXTRACT-HEADER ( addr len -- name-a name-l body-a body-l )
VARIABLE _TEH-S
: _TOML-EXTRACT-HEADER  ( addr len -- name-a name-l body-a body-l )
    1 /STRING TOML-SKIP-WS
    OVER _TEH-S !
    BEGIN DUP 0> WHILE
        OVER C@ 93 = IF
            OVER _TEH-S @ -
            _TEH-S @ SWAP
            2SWAP 1 /STRING TOML-SKIP-LINE EXIT
        THEN
        1 /STRING
    REPEAT
    OVER _TEH-S @ -  _TEH-S @ SWAP  2SWAP ;

\ _TOML-EXTRACT-AHEADER ( addr len -- name-a name-l body-a body-l )
VARIABLE _TEAH-S
: _TOML-EXTRACT-AHEADER  ( addr len -- name-a name-l body-a body-l )
    2 /STRING TOML-SKIP-WS
    OVER _TEAH-S !
    BEGIN DUP 0> WHILE
        OVER C@ 93 = IF
            OVER _TEAH-S @ -
            DUP 0> IF
                OVER OVER + 1- C@ 32 = IF 1- THEN
            THEN
            DUP 0> IF
                OVER OVER + 1- C@ 9 = IF 1- THEN
            THEN
            _TEAH-S @ SWAP
            2SWAP
            DUP 0> IF OVER C@ 93 = IF 1 /STRING THEN THEN
            DUP 0> IF OVER C@ 93 = IF 1 /STRING THEN THEN
            TOML-SKIP-LINE EXIT
        THEN
        1 /STRING
    REPEAT
    OVER _TEAH-S @ -  _TEAH-S @ SWAP  2SWAP ;

\ TOML-FIND-TABLE ( addr len name-a name-l -- body-a body-l )
VARIABLE _TFT-NA
VARIABLE _TFT-NL

: TOML-FIND-TABLE  ( addr len name-a name-l -- body-a body-l )
    _TFT-NL ! _TFT-NA !
    BEGIN
        TOML-SKIP-NL
        DUP 0> WHILE
        2DUP _TOML-AT-HEADER? IF
            2DUP _TOML-EXTRACT-HEADER
            2>R STR-TRIM
            _TFT-NA @ _TFT-NL @ STR-STR=
            IF 2DROP 2R> EXIT THEN
            2R> 2SWAP 2DROP
        ELSE
            TOML-SKIP-LINE
        THEN
    REPEAT
    2DROP TOML-E-NOT-FOUND _TOML-FAIL-00 ;

\ TOML-FIND-TABLE? ( addr len name-a name-l -- body-a body-l flag )
: TOML-FIND-TABLE?  ( addr len name-a name-l -- body-a body-l flag )
    TOML-ABORT-ON-ERROR @ >R
    TOML-CLEAR-ERR  0 TOML-ABORT-ON-ERROR !
    TOML-FIND-TABLE
    R> TOML-ABORT-ON-ERROR !
    TOML-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;

\ TOML-FIND-ATABLE ( addr len name-a name-l n -- body-a body-l )
VARIABLE _TFAT-NA
VARIABLE _TFAT-NL
VARIABLE _TFAT-IDX
VARIABLE _TFAT-CNT

: TOML-FIND-ATABLE  ( addr len name-a name-l n -- body-a body-l )
    _TFAT-CNT !  _TFAT-NL ! _TFAT-NA !
    0 _TFAT-IDX !
    BEGIN
        TOML-SKIP-NL
        DUP 0> WHILE
        2DUP _TOML-AT-AHEADER? IF
            2DUP _TOML-EXTRACT-AHEADER
            2>R STR-TRIM
            _TFAT-NA @ _TFAT-NL @ STR-STR=
            IF
                _TFAT-IDX @ _TFAT-CNT @ = IF
                    2DROP 2R> EXIT
                THEN
                1 _TFAT-IDX +!
            THEN
            2DROP 2R> 2SWAP 2DROP
        ELSE
            TOML-SKIP-LINE
        THEN
    REPEAT
    2DROP TOML-E-NOT-FOUND _TOML-FAIL-00 ;

\ =====================================================================
\  Layer 5 — Key Navigation (within current scope)
\ =====================================================================

VARIABLE _TK-KA
VARIABLE _TK-KL

: TOML-KEY  ( addr len kaddr klen -- vaddr vlen )
    _TK-KL ! _TK-KA !
    BEGIN
        TOML-SKIP-NL  DUP 0>
    WHILE
        OVER C@ 91 = IF
            2DROP TOML-E-NOT-FOUND _TOML-FAIL-00 EXIT
        THEN
        2DUP _TOML-EXTRACT-KEY
        2>R
        _TK-KA @ _TK-KL @ STR-STR=
        IF
            2DROP 2R>
            TOML-SKIP-WS
            DUP 0> IF OVER C@ 61 = IF 1 /STRING THEN THEN
            TOML-SKIP-WS EXIT
        THEN
        2R> 2DROP
        TOML-SKIP-LINE
    REPEAT
    2DROP TOML-E-NOT-FOUND _TOML-FAIL-00 ;

: TOML-KEY?  ( addr len kaddr klen -- vaddr vlen flag )
    TOML-ABORT-ON-ERROR @ >R
    TOML-CLEAR-ERR  0 TOML-ABORT-ON-ERROR !
    TOML-KEY
    R> TOML-ABORT-ON-ERROR !
    TOML-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;

\ =====================================================================
\  Layer 6 — Path Navigation
\ =====================================================================

VARIABLE _RDOT-TMP
: _TOML-FIND-RDOT  ( addr len -- offset | -1 )
    DUP 0= IF 2DROP -1 EXIT THEN
    -1 _RDOT-TMP !
    0 DO DUP I + C@ 46 = IF I _RDOT-TMP ! THEN LOOP
    DROP _RDOT-TMP @ ;

VARIABLE _TP-PA
VARIABLE _TP-PL
VARIABLE _TP-DA
VARIABLE _TP-DL
VARIABLE _TP-RD

: TOML-PATH  ( addr len path-a path-l -- val-a val-l )
    _TP-PL ! _TP-PA !
    _TP-DL ! _TP-DA !
    _TP-PA @ _TP-PL @ _TOML-FIND-RDOT  _TP-RD !
    _TP-RD @ -1 = IF
        _TP-DA @ _TP-DL @
        _TP-PA @ _TP-PL @ TOML-KEY EXIT
    THEN
    \ Try table + key: table = path[0..rdot], key = path[rdot+1..]
    _TP-DA @ _TP-DL @
    _TP-PA @ _TP-RD @
    TOML-FIND-TABLE?
    IF
        _TP-PA @ _TP-RD @ + 1+
        _TP-PL @ _TP-RD @ - 1-
        TOML-KEY?
        IF EXIT THEN
        2DROP
    ELSE
        2DROP
    THEN
    \ Fallback: try full dotted key
    _TP-DA @ _TP-DL @
    _TP-PA @ _TP-PL @ TOML-KEY ;

: TOML-PATH?  ( addr len path-a path-l -- val-a val-l flag )
    TOML-ABORT-ON-ERROR @ >R
    TOML-CLEAR-ERR  0 TOML-ABORT-ON-ERROR !
    TOML-PATH
    R> TOML-ABORT-ON-ERROR !
    TOML-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;

\ =====================================================================
\  Layer 7 — Array / Inline-Table Navigation
\ =====================================================================

: TOML-ENTER  ( addr len -- addr' len' )
    TOML-SKIP-WS
    DUP 0> 0= IF TOML-E-UNEXPECTED TOML-FAIL EXIT THEN
    OVER C@ DUP 91 = SWAP 123 = OR 0= IF
        TOML-E-WRONG-TYPE TOML-FAIL EXIT
    THEN
    1 /STRING TOML-SKIP-NL ;

: TOML-NEXT  ( addr len -- addr' len' flag )
    TOML-SKIP-VALUE  TOML-SKIP-NL
    DUP 0> 0= IF 0 EXIT THEN
    OVER C@ 93 = IF 0 EXIT THEN
    OVER C@ 125 = IF 0 EXIT THEN
    OVER C@ 44 = IF 1 /STRING THEN
    TOML-SKIP-NL
    DUP 0> 0= IF 0 EXIT THEN
    OVER C@ 93 = IF 0 EXIT THEN
    OVER C@ 125 = IF 0 EXIT THEN
    -1 ;

: TOML-NTH  ( addr len n -- addr' len' )
    DUP 0= IF DROP EXIT THEN
    0 DO
        TOML-SKIP-VALUE TOML-SKIP-NL
        DUP 0> 0= IF TOML-E-NOT-FOUND TOML-FAIL UNLOOP EXIT THEN
        OVER C@ 93 = IF TOML-E-NOT-FOUND TOML-FAIL UNLOOP EXIT THEN
        OVER C@ 44 = IF 1 /STRING THEN
        TOML-SKIP-NL
    LOOP ;

: TOML-COUNT  ( addr len -- n )
    0 >R  TOML-SKIP-NL
    DUP 0> 0= IF 2DROP R> EXIT THEN
    OVER C@ 93 = IF 2DROP R> EXIT THEN
    OVER C@ 125 = IF 2DROP R> EXIT THEN
    R> 1+ >R
    BEGIN
        TOML-SKIP-VALUE TOML-SKIP-NL
        DUP 0> IF
            OVER C@ 44 = IF
                1 /STRING TOML-SKIP-NL  R> 1+ >R  -1
            ELSE 0 THEN
        ELSE 0 THEN
    0= UNTIL
    2DROP R> ;

\ =====================================================================
\  Layer 8 — Iteration
\ =====================================================================

: TOML-EACH-KEY  ( addr len -- addr' len' key-a key-l flag )
    TOML-SKIP-NL
    DUP 0> 0= IF 0 0 0 EXIT THEN
    OVER C@ 91 = IF 0 0 0 EXIT THEN
    2DUP _TOML-EXTRACT-KEY
    2>R 2SWAP 2DROP 2R>
    TOML-SKIP-WS
    DUP 0> IF OVER C@ 61 = IF 1 /STRING THEN THEN
    TOML-SKIP-WS
    2SWAP -1 ;

\ =====================================================================
\  Layer 9 — Inline-Table Key Lookup
\ =====================================================================

VARIABLE _TIK-KA
VARIABLE _TIK-KL

: TOML-IKEY  ( addr len kaddr klen -- vaddr vlen )
    _TIK-KL ! _TIK-KA !
    TOML-SKIP-NL
    BEGIN
        DUP 0> IF OVER C@ 125 <> ELSE 0 THEN
    WHILE
        OVER C@ 44 = IF 1 /STRING TOML-SKIP-NL THEN
        2DUP _TOML-EXTRACT-KEY
        2>R
        _TIK-KA @ _TIK-KL @ STR-STR=
        IF
            2DROP 2R>
            TOML-SKIP-WS
            DUP 0> IF OVER C@ 61 = IF 1 /STRING THEN THEN
            TOML-SKIP-WS EXIT
        THEN
        2R> 2SWAP 2DROP
        TOML-SKIP-WS
        DUP 0> IF OVER C@ 61 = IF 1 /STRING THEN THEN
        TOML-SKIP-VALUE TOML-SKIP-NL
    REPEAT
    2DROP TOML-E-NOT-FOUND _TOML-FAIL-00 ;

\ =====================================================================
\  Layer 10 — Convenience / Comparison / Guards
\ =====================================================================

: TOML-STRING=  ( addr len saddr slen -- flag )
    2>R TOML-GET-STRING 2R> STR-STR= ;

: TOML-INT=  ( addr len n -- flag )
    >R TOML-GET-INT R> = ;

: TOML-EXPECT-STRING  ( addr len -- addr len )
    2DUP TOML-STRING? 0= IF TOML-E-WRONG-TYPE TOML-FAIL THEN ;

: TOML-EXPECT-INTEGER  ( addr len -- addr len )
    2DUP TOML-INTEGER? 0= IF TOML-E-WRONG-TYPE TOML-FAIL THEN ;

: TOML-EXPECT-BOOL  ( addr len -- addr len )
    2DUP TOML-BOOL? 0= IF TOML-E-WRONG-TYPE TOML-FAIL THEN ;

: TOML-EXPECT-ARRAY  ( addr len -- addr len )
    2DUP TOML-ARRAY? 0= IF TOML-E-WRONG-TYPE TOML-FAIL THEN ;

: TOML-EXPECT-INLINE-TABLE  ( addr len -- addr len )
    2DUP TOML-INLINE-TABLE? 0= IF TOML-E-WRONG-TYPE TOML-FAIL THEN ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _toml-guard

' TOML-FAIL       CONSTANT _toml-fail-xt
' TOML-OK?        CONSTANT _toml-ok-q-xt
' TOML-CLEAR-ERR  CONSTANT _toml-clear-err-xt
' TOML-SKIP-WS    CONSTANT _toml-skip-ws-xt
' TOML-SKIP-COMMENT CONSTANT _toml-skip-comment-xt
' TOML-SKIP-EOL   CONSTANT _toml-skip-eol-xt
' TOML-SKIP-LINE  CONSTANT _toml-skip-line-xt
' TOML-SKIP-NL    CONSTANT _toml-skip-nl-xt
' TOML-SKIP-BASIC-STRING CONSTANT _toml-skip-basic-string-xt
' TOML-SKIP-LITERAL-STRING CONSTANT _toml-skip-literal-string-xt
' TOML-SKIP-ML-BASIC CONSTANT _toml-skip-ml-basic-xt
' TOML-SKIP-ML-LITERAL CONSTANT _toml-skip-ml-literal-xt
' TOML-SKIP-STRING CONSTANT _toml-skip-string-xt
' TOML-SKIP-VALUE CONSTANT _toml-skip-value-xt
' TOML-TYPE?      CONSTANT _toml-type-q-xt
' TOML-STRING?    CONSTANT _toml-string-q-xt
' TOML-INTEGER?   CONSTANT _toml-integer-q-xt
' TOML-FLOAT?     CONSTANT _toml-float-q-xt
' TOML-BOOL?      CONSTANT _toml-bool-q-xt
' TOML-DATETIME?  CONSTANT _toml-datetime-q-xt
' TOML-ARRAY?     CONSTANT _toml-array-q-xt
' TOML-INLINE-TABLE? CONSTANT _toml-inline-table-q-xt
' TOML-GET-STRING CONSTANT _toml-get-string-xt
' TOML-UNESCAPE   CONSTANT _toml-unescape-xt
' TOML-GET-INT    CONSTANT _toml-get-int-xt
' TOML-GET-BOOL   CONSTANT _toml-get-bool-xt
' TOML-GET-FLOAT-STR CONSTANT _toml-get-float-str-xt
' TOML-GET-DATETIME-STR CONSTANT _toml-get-datetime-str-xt
' TOML-FIND-TABLE CONSTANT _toml-find-table-xt
' TOML-FIND-TABLE? CONSTANT _toml-find-table-q-xt
' TOML-FIND-ATABLE CONSTANT _toml-find-atable-xt
' TOML-KEY        CONSTANT _toml-key-xt
' TOML-KEY?       CONSTANT _toml-key-q-xt
' TOML-PATH       CONSTANT _toml-path-xt
' TOML-PATH?      CONSTANT _toml-path-q-xt
' TOML-ENTER      CONSTANT _toml-enter-xt
' TOML-NEXT       CONSTANT _toml-next-xt
' TOML-NTH        CONSTANT _toml-nth-xt
' TOML-COUNT      CONSTANT _toml-count-xt
' TOML-EACH-KEY   CONSTANT _toml-each-key-xt
' TOML-IKEY       CONSTANT _toml-ikey-xt
' TOML-STRING=    CONSTANT _toml-string=-xt
' TOML-INT=       CONSTANT _toml-int=-xt
' TOML-EXPECT-STRING CONSTANT _toml-expect-string-xt
' TOML-EXPECT-INTEGER CONSTANT _toml-expect-integer-xt
' TOML-EXPECT-BOOL CONSTANT _toml-expect-bool-xt
' TOML-EXPECT-ARRAY CONSTANT _toml-expect-array-xt
' TOML-EXPECT-INLINE-TABLE CONSTANT _toml-expect-inline-table-xt

: TOML-FAIL       _toml-fail-xt _toml-guard WITH-GUARD ;
: TOML-OK?        _toml-ok-q-xt _toml-guard WITH-GUARD ;
: TOML-CLEAR-ERR  _toml-clear-err-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-WS    _toml-skip-ws-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-COMMENT _toml-skip-comment-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-EOL   _toml-skip-eol-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-LINE  _toml-skip-line-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-NL    _toml-skip-nl-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-BASIC-STRING _toml-skip-basic-string-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-LITERAL-STRING _toml-skip-literal-string-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-ML-BASIC _toml-skip-ml-basic-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-ML-LITERAL _toml-skip-ml-literal-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-STRING _toml-skip-string-xt _toml-guard WITH-GUARD ;
: TOML-SKIP-VALUE _toml-skip-value-xt _toml-guard WITH-GUARD ;
: TOML-TYPE?      _toml-type-q-xt _toml-guard WITH-GUARD ;
: TOML-STRING?    _toml-string-q-xt _toml-guard WITH-GUARD ;
: TOML-INTEGER?   _toml-integer-q-xt _toml-guard WITH-GUARD ;
: TOML-FLOAT?     _toml-float-q-xt _toml-guard WITH-GUARD ;
: TOML-BOOL?      _toml-bool-q-xt _toml-guard WITH-GUARD ;
: TOML-DATETIME?  _toml-datetime-q-xt _toml-guard WITH-GUARD ;
: TOML-ARRAY?     _toml-array-q-xt _toml-guard WITH-GUARD ;
: TOML-INLINE-TABLE? _toml-inline-table-q-xt _toml-guard WITH-GUARD ;
: TOML-GET-STRING _toml-get-string-xt _toml-guard WITH-GUARD ;
: TOML-UNESCAPE   _toml-unescape-xt _toml-guard WITH-GUARD ;
: TOML-GET-INT    _toml-get-int-xt _toml-guard WITH-GUARD ;
: TOML-GET-BOOL   _toml-get-bool-xt _toml-guard WITH-GUARD ;
: TOML-GET-FLOAT-STR _toml-get-float-str-xt _toml-guard WITH-GUARD ;
: TOML-GET-DATETIME-STR _toml-get-datetime-str-xt _toml-guard WITH-GUARD ;
: TOML-FIND-TABLE _toml-find-table-xt _toml-guard WITH-GUARD ;
: TOML-FIND-TABLE? _toml-find-table-q-xt _toml-guard WITH-GUARD ;
: TOML-FIND-ATABLE _toml-find-atable-xt _toml-guard WITH-GUARD ;
: TOML-KEY        _toml-key-xt _toml-guard WITH-GUARD ;
: TOML-KEY?       _toml-key-q-xt _toml-guard WITH-GUARD ;
: TOML-PATH       _toml-path-xt _toml-guard WITH-GUARD ;
: TOML-PATH?      _toml-path-q-xt _toml-guard WITH-GUARD ;
: TOML-ENTER      _toml-enter-xt _toml-guard WITH-GUARD ;
: TOML-NEXT       _toml-next-xt _toml-guard WITH-GUARD ;
: TOML-NTH        _toml-nth-xt _toml-guard WITH-GUARD ;
: TOML-COUNT      _toml-count-xt _toml-guard WITH-GUARD ;
: TOML-EACH-KEY   _toml-each-key-xt _toml-guard WITH-GUARD ;
: TOML-IKEY       _toml-ikey-xt _toml-guard WITH-GUARD ;
: TOML-STRING=    _toml-string=-xt _toml-guard WITH-GUARD ;
: TOML-INT=       _toml-int=-xt _toml-guard WITH-GUARD ;
: TOML-EXPECT-STRING _toml-expect-string-xt _toml-guard WITH-GUARD ;
: TOML-EXPECT-INTEGER _toml-expect-integer-xt _toml-guard WITH-GUARD ;
: TOML-EXPECT-BOOL _toml-expect-bool-xt _toml-guard WITH-GUARD ;
: TOML-EXPECT-ARRAY _toml-expect-array-xt _toml-guard WITH-GUARD ;
: TOML-EXPECT-INLINE-TABLE _toml-expect-inline-table-xt _toml-guard WITH-GUARD ;
[THEN] [THEN]
