\ =====================================================================
\  grid.f - Persistent worksheet with formulas and CSV interchange
\ =====================================================================
\  Grid presents a virtual 64 x 16 sheet. Cell source text is persisted
\  in /grid.csv. Formulas begin with '=' and support integer literals,
\  A1 references, parentheses, + - * /, and SUM(A1:B4).
\
\  Entry: GRID-ENTRY ( desc -- )  for Desk
\         GRID-RUN   ( -- )       standalone
\ =====================================================================

PROVIDED akashic-tui-grid

REQUIRE ../../widgets/prompt.f
REQUIRE ../../widgets/dialog.f
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widget.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/fs/vfs-access.f
REQUIRE ../../../utils/fs/vfs-replace.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../utils/buffer-writer.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/capability.f
REQUIRE ../../../interop/endpoint.f
REQUIRE ../../../interop/resource.f

64 CONSTANT _GRID-ROWS
16 CONSTANT _GRID-COLS
40 CONSTANT _GRID-SOURCE-CAP
72 CONSTANT _GRID-CELL-SZ
98304 CONSTANT _GRID-IO-CAP
256 CONSTANT _GRID-PROMPT-CAP
20 CONSTANT _GRID-EVAL-DEPTH
_GRID-EVAL-DEPTH CONSTANT _GRID-PARSE-DEPTH

 0 CONSTANT _GC-LEN
 8 CONSTANT _GC-VALUE
16 CONSTANT _GC-STATUS
24 CONSTANT _GC-MARK
32 CONSTANT _GC-SOURCE

0  CONSTANT _GRID-ST-TEXT
1  CONSTANT _GRID-ST-NUMBER
2  CONSTANT _GRID-ST-FORMULA
-1 CONSTANT _GRID-ST-ERROR
-2 CONSTANT _GRID-ST-CYCLE
-3 CONSTANT _GRID-ST-DEPTH

: _GRID-ST-ERROR?  ( status -- flag ) 0< ;

0 CONSTANT _GRID-PRM-NONE
1 CONSTANT _GRID-PRM-EDIT
2 CONSTANT _GRID-PRM-GOTO

0 CONSTANT _GRID-L-S-OK
1 CONSTANT _GRID-L-S-MISSING
2 CONSTANT _GRID-L-S-IO
3 CONSTANT _GRID-L-S-TOO-LARGE
4 CONSTANT _GRID-L-S-INVALID
5 CONSTANT _GRID-L-S-CAPACITY
6 CONSTANT _GRID-L-S-FIELD
7 CONSTANT _GRID-L-S-RECOVERY

VARIABLE _GRID-CURRENT-STATE
0 _GRID-CURRENT-STATE !
VARIABLE _GRID-CURRENT-INSTANCE
0 _GRID-CURRENT-INSTANCE !
CMP-LAYOUT-BEGIN

_GRID-CURRENT-STATE CMP-CELL: _GRID-CELLS
_GRID-CURRENT-STATE CMP-CELL: _GRID-IO-BUF
_GRID-CURRENT-STATE CMP-CELL: _GRID-IO-U
_GRID-CURRENT-STATE CMP-CELL: _GRID-MAX-ROW
_GRID-CURRENT-STATE CMP-CELL: _GRID-MAX-COL
_GRID-CURRENT-STATE CMP-CELL: _GRID-SEL-ROW
_GRID-CURRENT-STATE CMP-CELL: _GRID-SEL-COL
_GRID-CURRENT-STATE CMP-CELL: _GRID-SCROLL-ROW
_GRID-CURRENT-STATE CMP-CELL: _GRID-SCROLL-COL
_GRID-CURRENT-STATE CMP-CELL: _GRID-DIRTY
_GRID-CURRENT-STATE CMP-CELL: _GRID-VFS
_GRID-CURRENT-STATE VFA-SCOPE-SIZE CMP-FIELD: _GRID-LOAD-SCOPE
_GRID-CURRENT-STATE VREPL-SIZE CMP-FIELD: _GRID-REPLACE
_GRID-CURRENT-STATE CMP-CELL: _GRID-SOURCE-BLOCKED
_GRID-CURRENT-STATE CBW-SIZE CMP-FIELD: _GRID-IO-WRITER

: _GRID-CELL  ( row col -- cell )
    SWAP _GRID-COLS * + _GRID-CELL-SZ * _GRID-CELLS @ + ;

: _GRID-CLEAR-MODEL  ( -- )
    _GRID-CELLS @ _GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * 0 FILL
    0 _GRID-MAX-ROW ! 0 _GRID-MAX-COL ! ;

VARIABLE _GS-ROW
VARIABLE _GS-COL
VARIABLE _GS-A
VARIABLE _GS-U
VARIABLE _GS-N
VARIABLE _GS-CELL

: _GRID-SET-CELL  ( addr len row col -- )
    _GS-COL ! _GS-ROW ! _GS-U ! _GS-A !
    _GS-ROW @ 0< _GS-ROW @ _GRID-ROWS >= OR IF EXIT THEN
    _GS-COL @ 0< _GS-COL @ _GRID-COLS >= OR IF EXIT THEN
    _GS-U @ _GRID-SOURCE-CAP > IF EXIT THEN
    _GS-ROW @ _GS-COL @ _GRID-CELL _GS-CELL !
    _GS-CELL @ _GC-SOURCE + _GRID-SOURCE-CAP 0 FILL
    _GS-U @ _GS-N !
    _GS-N @ _GS-CELL @ _GC-LEN + !
    _GS-A @ _GS-CELL @ _GC-SOURCE + _GS-N @ CMOVE
    0 _GS-CELL @ _GC-VALUE + !
    _GRID-ST-TEXT _GS-CELL @ _GC-STATUS + !
    0 _GS-CELL @ _GC-MARK + !
    _GS-N @ 0> IF
        _GS-ROW @ _GRID-MAX-ROW @ MAX _GRID-MAX-ROW !
        _GS-COL @ _GRID-MAX-COL @ MAX _GRID-MAX-COL !
    THEN ;

: _GRID-CLEAR-CELL  ( row col -- )
    0 0 2SWAP _GRID-SET-CELL ;

\ ---------------------------------------------------------------------
\ CSV reader
\ ---------------------------------------------------------------------

CREATE _GRID-CSV-FIELD _GRID-SOURCE-CAP ALLOT
VARIABLE _GCSV-POS
VARIABLE _GCSV-ROW
VARIABLE _GCSV-COL
VARIABLE _GCSV-FIELD-U
VARIABLE _GCSV-CH
VARIABLE _GCSV-STATE
VARIABLE _GCSV-COMMIT
VARIABLE _GCSV-ROW-STARTED
VARIABLE _GCSV-STATUS

0 CONSTANT _GCSV-ST-START
1 CONSTANT _GCSV-ST-UNQUOTED
2 CONSTANT _GCSV-ST-QUOTED
3 CONSTANT _GCSV-ST-AFTER-QUOTE

: _GCSV-FIELD-RESET  ( -- )
    0 _GCSV-FIELD-U !
    _GRID-CSV-FIELD _GRID-SOURCE-CAP 0 FILL ;

\ The parser is deliberately strict.  It never clips a decoded field and
\ never mutates the worksheet during its validation pass.
: _GCSV-FAIL  ( status -- flag )
    _GCSV-STATUS ! 0 ;

: _GCSV-FIELD-CHAR  ( c -- flag )
    _GCSV-FIELD-U @ _GRID-SOURCE-CAP >= IF
        DROP _GRID-L-S-FIELD _GCSV-FAIL EXIT
    THEN
    _GRID-CSV-FIELD _GCSV-FIELD-U @ + C!
    1 _GCSV-FIELD-U +! -1 ;

: _GCSV-FIELD-FINISH  ( -- flag )
    _GCSV-ROW @ _GRID-ROWS >=
    _GCSV-COL @ _GRID-COLS >= OR IF
        _GRID-L-S-CAPACITY _GCSV-FAIL EXIT
    THEN
    _GCSV-COMMIT @ IF
        _GRID-CSV-FIELD _GCSV-FIELD-U @ _GCSV-ROW @ _GCSV-COL @
        _GRID-SET-CELL
    THEN
    1 _GCSV-COL +! _GCSV-FIELD-RESET -1 ;

: _GCSV-ROW-FINISH  ( -- flag )
    _GCSV-FIELD-FINISH 0= IF 0 EXIT THEN
    1 _GCSV-ROW +! 0 _GCSV-COL ! 0 _GCSV-ROW-STARTED !
    _GCSV-ST-START _GCSV-STATE ! -1 ;

: _GCSV-RECORD-CR  ( -- )
    _GCSV-POS @ 1+ _GRID-IO-U @ >= IF
        _GRID-L-S-INVALID _GCSV-FAIL DROP EXIT
    THEN
    _GRID-IO-BUF @ _GCSV-POS @ + 1+ C@ 10 <> IF
        _GRID-L-S-INVALID _GCSV-FAIL DROP EXIT
    THEN
    _GCSV-ROW-FINISH IF 2 _GCSV-POS +! THEN ;

: _GCSV-QUOTED-CR  ( -- )
    _GCSV-POS @ 1+ _GRID-IO-U @ >= IF
        _GRID-L-S-INVALID _GCSV-FAIL DROP EXIT
    THEN
    _GRID-IO-BUF @ _GCSV-POS @ + 1+ C@ 10 <> IF
        _GRID-L-S-INVALID _GCSV-FAIL DROP EXIT
    THEN
    13 _GCSV-FIELD-CHAR 0= IF EXIT THEN
    10 _GCSV-FIELD-CHAR 0= IF EXIT THEN
    2 _GCSV-POS +! ;

: _GCSV-STEP-START  ( -- )
    _GCSV-CH @ CASE
        [CHAR] " OF
            -1 _GCSV-ROW-STARTED !
            _GCSV-ST-QUOTED _GCSV-STATE ! 1 _GCSV-POS +!
        ENDOF
        [CHAR] , OF
            -1 _GCSV-ROW-STARTED !
            _GCSV-FIELD-FINISH IF 1 _GCSV-POS +! THEN
        ENDOF
        10 OF _GCSV-ROW-FINISH IF 1 _GCSV-POS +! THEN ENDOF
        13 OF _GCSV-RECORD-CR ENDOF
        _GCSV-CH @ _GCSV-FIELD-CHAR IF
            -1 _GCSV-ROW-STARTED !
            _GCSV-ST-UNQUOTED _GCSV-STATE ! 1 _GCSV-POS +!
        THEN
    ENDCASE ;

: _GCSV-STEP-UNQUOTED  ( -- )
    _GCSV-CH @ CASE
        [CHAR] " OF _GRID-L-S-INVALID _GCSV-FAIL DROP ENDOF
        [CHAR] , OF
            _GCSV-FIELD-FINISH IF
                _GCSV-ST-START _GCSV-STATE ! 1 _GCSV-POS +!
            THEN
        ENDOF
        10 OF _GCSV-ROW-FINISH IF 1 _GCSV-POS +! THEN ENDOF
        13 OF _GCSV-RECORD-CR ENDOF
        _GCSV-CH @ _GCSV-FIELD-CHAR IF 1 _GCSV-POS +! THEN
    ENDCASE ;

: _GCSV-STEP-QUOTED  ( -- )
    _GCSV-CH @ [CHAR] " = IF
        _GCSV-POS @ 1+ _GRID-IO-U @ < IF
            _GRID-IO-BUF @ _GCSV-POS @ + 1+ C@ [CHAR] " = IF
                [CHAR] " _GCSV-FIELD-CHAR IF 2 _GCSV-POS +! THEN
                EXIT
            THEN
        THEN
        _GCSV-ST-AFTER-QUOTE _GCSV-STATE ! 1 _GCSV-POS +! EXIT
    THEN
    _GCSV-CH @ 13 = IF _GCSV-QUOTED-CR EXIT THEN
    _GCSV-CH @ _GCSV-FIELD-CHAR IF 1 _GCSV-POS +! THEN ;

: _GCSV-STEP-AFTER-QUOTE  ( -- )
    _GCSV-CH @ CASE
        [CHAR] , OF
            _GCSV-FIELD-FINISH IF
                _GCSV-ST-START _GCSV-STATE ! 1 _GCSV-POS +!
            THEN
        ENDOF
        10 OF _GCSV-ROW-FINISH IF 1 _GCSV-POS +! THEN ENDOF
        13 OF _GCSV-RECORD-CR ENDOF
        _GRID-L-S-INVALID _GCSV-FAIL DROP
    ENDCASE ;

: _GRID-SCAN-CSV  ( commit? -- status )
    _GCSV-COMMIT !
    0 _GCSV-POS ! 0 _GCSV-ROW ! 0 _GCSV-COL !
    0 _GCSV-ROW-STARTED ! 0 _GCSV-STATUS !
    _GCSV-ST-START _GCSV-STATE ! _GCSV-FIELD-RESET
    _GRID-IO-BUF @ _GRID-IO-U @ UTF8-VALID? 0= IF
        _GRID-L-S-INVALID EXIT
    THEN
    BEGIN
        _GCSV-POS @ _GRID-IO-U @ < _GCSV-STATUS @ 0= AND
    WHILE
        _GRID-IO-BUF @ _GCSV-POS @ + C@ _GCSV-CH !
        _GCSV-STATE @ CASE
            _GCSV-ST-START OF _GCSV-STEP-START ENDOF
            _GCSV-ST-UNQUOTED OF _GCSV-STEP-UNQUOTED ENDOF
            _GCSV-ST-QUOTED OF _GCSV-STEP-QUOTED ENDOF
            _GCSV-ST-AFTER-QUOTE OF _GCSV-STEP-AFTER-QUOTE ENDOF
            DROP _GRID-L-S-INVALID _GCSV-FAIL DROP
        ENDCASE
    REPEAT
    _GCSV-STATUS @ ?DUP IF EXIT THEN
    _GCSV-STATE @ _GCSV-ST-QUOTED = IF _GRID-L-S-INVALID EXIT THEN
    _GCSV-ROW-STARTED @ IF
        _GCSV-FIELD-FINISH 0= IF _GCSV-STATUS @ EXIT THEN
    THEN
    _GRID-L-S-OK ;

: _GRID-PARSE-CSV  ( -- status )
    0 _GRID-SCAN-CSV DUP IF EXIT THEN DROP
    _GRID-CLEAR-MODEL
    -1 _GRID-SCAN-CSV ;

VARIABLE _GRID-LOAD-STATUS

: _GRID-READ-FILE-BODY  ( -- )
    S" /grid.csv" VFS-FF-READ _GRID-LOAD-SCOPE VFA-SCOPE-OPEN?
    DUP IF
        VFS-IOR-REASON VFS-R-NOENT = IF
            _GRID-L-S-MISSING
        ELSE
            _GRID-L-S-IO
        THEN
        _GRID-LOAD-STATUS ! DROP EXIT
    THEN
    DROP
    _GRID-IO-BUF @ _GRID-IO-CAP ROT VFA-READ-FILE?
    DUP IF
        VFS-IOR-REASON VFS-R-OVERFLOW = IF
            _GRID-L-S-TOO-LARGE
        ELSE
            _GRID-L-S-IO
        THEN
        _GRID-LOAD-STATUS ! DROP EXIT
    THEN
    DROP _GRID-IO-U !
    _GRID-L-S-OK _GRID-LOAD-STATUS ! ;

: _GRID-READ-FILE  ( -- status )
    _GRID-L-S-IO _GRID-LOAD-STATUS !
    ['] _GRID-READ-FILE-BODY _GRID-LOAD-SCOPE VFA-SCOPE-CALL
    OR IF _GRID-L-S-IO ELSE _GRID-LOAD-STATUS @ THEN ;

: _GRID-RECOVER  ( -- status )
    _GRID-REPLACE VREPL-RECOVER
    DUP VREPL-S-OK = IF DROP _GRID-L-S-OK EXIT THEN
    DUP VREPL-S-ROLLED-BACK = IF DROP _GRID-L-S-OK EXIT THEN
    VREPL-S-COMMITTED-CLEANUP = IF
        _GRID-L-S-OK ELSE _GRID-L-S-RECOVERY
    THEN ;

: _GRID-LOAD  ( -- status )
    _GRID-RECOVER DUP IF -1 _GRID-SOURCE-BLOCKED ! EXIT THEN DROP
    _GRID-READ-FILE DUP _GRID-L-S-MISSING = IF
        DROP _GRID-CLEAR-MODEL 0 _GRID-SOURCE-BLOCKED !
        _GRID-L-S-OK EXIT
    THEN
    DUP IF -1 _GRID-SOURCE-BLOCKED ! EXIT THEN DROP
    _GRID-PARSE-CSV DUP IF -1 ELSE 0 THEN _GRID-SOURCE-BLOCKED ! ;

\ ---------------------------------------------------------------------
\ Formula parser
\ ---------------------------------------------------------------------

VARIABLE _GP-SRC
VARIABLE _GP-LEN
VARIABLE _GP-POS
VARIABLE _GP-OK
VARIABLE _GP-DEPTH

CREATE _GP-SAVE-SRC _GRID-PARSE-DEPTH CELLS ALLOT
CREATE _GP-SAVE-LEN _GRID-PARSE-DEPTH CELLS ALLOT
CREATE _GP-SAVE-POS _GRID-PARSE-DEPTH CELLS ALLOT
CREATE _GP-SAVE-OK  _GRID-PARSE-DEPTH CELLS ALLOT

: _GP-PUSH  ( -- flag )
    _GP-DEPTH @ _GRID-PARSE-DEPTH >= IF 0 EXIT THEN
    _GP-SRC @ _GP-SAVE-SRC _GP-DEPTH @ CELLS + !
    _GP-LEN @ _GP-SAVE-LEN _GP-DEPTH @ CELLS + !
    _GP-POS @ _GP-SAVE-POS _GP-DEPTH @ CELLS + !
    _GP-OK  @ _GP-SAVE-OK  _GP-DEPTH @ CELLS + !
    1 _GP-DEPTH +! -1 ;

: _GP-POP  ( -- )
    _GP-DEPTH @ 0= IF EXIT THEN
    -1 _GP-DEPTH +!
    _GP-SAVE-SRC _GP-DEPTH @ CELLS + @ _GP-SRC !
    _GP-SAVE-LEN _GP-DEPTH @ CELLS + @ _GP-LEN !
    _GP-SAVE-POS _GP-DEPTH @ CELLS + @ _GP-POS !
    _GP-SAVE-OK  _GP-DEPTH @ CELLS + @ _GP-OK ! ;

: _GP-PEEK  ( -- c | -1 )
    _GP-POS @ _GP-LEN @ >= IF -1 EXIT THEN
    _GP-SRC @ _GP-POS @ + C@ ;

: _GP-ADV  ( -- )
    _GP-POS @ _GP-LEN @ < IF 1 _GP-POS +! THEN ;

: _GP-SKIP-WS  ( -- )
    BEGIN _GP-PEEK DUP BL = OVER 9 = OR WHILE DROP _GP-ADV REPEAT DROP ;

: _GP-DIGIT?  ( c -- flag )
    DUP [CHAR] 0 >= SWAP [CHAR] 9 <= AND ;

: _GP-UPPER  ( c -- c' )
    DUP [CHAR] a >= OVER [CHAR] z <= AND IF 32 - THEN ;

VARIABLE _GP-EXPECT-CH
: _GP-EXPECT  ( c -- flag )
    _GP-EXPECT-CH ! _GP-SKIP-WS
    _GP-PEEK _GP-EXPECT-CH @ = IF _GP-ADV -1 EXIT THEN
    0 _GP-OK ! 0 ;

VARIABLE _GP-NUM-ACC
: _GP-PARSE-NUMBER  ( -- n )
    0 _GP-NUM-ACC !
    BEGIN _GP-PEEK DUP _GP-DIGIT? WHILE
        [CHAR] 0 - _GP-NUM-ACC @ 10 * + _GP-NUM-ACC ! _GP-ADV
    REPEAT DROP _GP-NUM-ACC @ ;

VARIABLE _GP-COORD-COL
VARIABLE _GP-COORD-ROW
VARIABLE _GP-COORD-DIGITS

: _GP-PARSE-COORD  ( -- row col flag )
    _GP-SKIP-WS
    _GP-PEEK _GP-UPPER DUP [CHAR] A < OVER [CHAR] P > OR IF
        DROP 0 0 0 EXIT
    THEN
    [CHAR] A - _GP-COORD-COL ! _GP-ADV
    0 _GP-COORD-ROW ! 0 _GP-COORD-DIGITS !
    BEGIN _GP-PEEK DUP _GP-DIGIT? WHILE
        [CHAR] 0 - _GP-COORD-ROW @ 10 * + _GP-COORD-ROW !
        1 _GP-COORD-DIGITS +! _GP-ADV
    REPEAT DROP
    _GP-COORD-DIGITS @ 0= IF 0 0 0 EXIT THEN
    _GP-COORD-ROW @ 1- DUP 0< OVER _GRID-ROWS >= OR IF
        DROP 0 0 0 EXIT
    THEN
    _GP-COORD-COL @ -1 ;

: _GP-SUM-START?  ( -- flag )
    _GP-LEN @ _GP-POS @ - 4 < IF 0 EXIT THEN
    _GP-SRC @ _GP-POS @ + C@ _GP-UPPER [CHAR] S <> IF 0 EXIT THEN
    _GP-SRC @ _GP-POS @ + 1+ C@ _GP-UPPER [CHAR] U <> IF 0 EXIT THEN
    _GP-SRC @ _GP-POS @ + 2 + C@ _GP-UPPER [CHAR] M <> IF 0 EXIT THEN
    _GP-SRC @ _GP-POS @ + 3 + C@ [CHAR] ( = ;

VARIABLE _GRID-EVAL-XT
: _GRID-REF-EVAL  ( row col -- value ok )
    _GRID-EVAL-XT @ EXECUTE ;

VARIABLE _GPS-R1
VARIABLE _GPS-C1
VARIABLE _GPS-R2
VARIABLE _GPS-C2
VARIABLE _GPS-RLO
VARIABLE _GPS-RHI
VARIABLE _GPS-CLO
VARIABLE _GPS-CHI

: _GP-PARSE-SUM  ( -- value )
    4 _GP-POS +!
    _GP-PARSE-COORD 0= IF 2DROP 0 _GP-OK ! 0 EXIT THEN
    _GPS-C1 ! _GPS-R1 !
    [CHAR] : _GP-EXPECT 0= IF 0 EXIT THEN
    _GP-PARSE-COORD 0= IF 2DROP 0 _GP-OK ! 0 EXIT THEN
    _GPS-C2 ! _GPS-R2 !
    [CHAR] ) _GP-EXPECT DROP
    _GPS-R1 @ _GPS-R2 @ MIN _GPS-RLO !
    _GPS-R1 @ _GPS-R2 @ MAX _GPS-RHI !
    _GPS-C1 @ _GPS-C2 @ MIN _GPS-CLO !
    _GPS-C1 @ _GPS-C2 @ MAX _GPS-CHI !
    0
    _GPS-RHI @ 1+ _GPS-RLO @ ?DO
        _GPS-CHI @ 1+ _GPS-CLO @ ?DO
            J I _GRID-REF-EVAL
            0= IF DROP 0 _GP-OK ! ELSE + THEN
        LOOP
    LOOP ;

VARIABLE _GP-EXPR-XT
: _GP-EXPR  ( -- value ) _GP-EXPR-XT @ EXECUTE ;

: _GP-PARSE-PRIMARY  ( -- value )
    _GP-SKIP-WS
    _GP-PEEK DUP [CHAR] ( = IF
        DROP _GP-ADV _GP-EXPR [CHAR] ) _GP-EXPECT DROP EXIT
    THEN
    DUP _GP-DIGIT? IF DROP _GP-PARSE-NUMBER EXIT THEN
    DROP
    _GP-SUM-START? IF _GP-PARSE-SUM EXIT THEN
    _GP-PARSE-COORD 0= IF
        2DROP 0 _GP-OK ! _GP-ADV 0 EXIT
    THEN
    _GRID-REF-EVAL 0= IF DROP 0 _GP-OK ! 0 THEN ;

: _GP-PARSE-FACTOR  ( -- value )
    _GP-SKIP-WS _GP-PEEK
    DUP [CHAR] - = IF DROP _GP-ADV RECURSE NEGATE EXIT THEN
    DUP [CHAR] + = IF DROP _GP-ADV RECURSE EXIT THEN
    DROP _GP-PARSE-PRIMARY ;

: _GP-PARSE-TERM  ( -- value )
    _GP-PARSE-FACTOR
    BEGIN
        _GP-SKIP-WS _GP-PEEK DUP [CHAR] * = OVER [CHAR] / = OR
    WHILE
        _GP-ADV _GP-PARSE-FACTOR SWAP
        CASE
            [CHAR] * OF * ENDOF
            [CHAR] / OF
                DUP 0= IF 2DROP 0 0 _GP-OK ! ELSE / THEN
            ENDOF
        ENDCASE
    REPEAT DROP ;

: _GP-PARSE-EXPR  ( -- value )
    _GP-PARSE-TERM
    BEGIN
        _GP-SKIP-WS _GP-PEEK DUP [CHAR] + = OVER [CHAR] - = OR
    WHILE
        _GP-ADV _GP-PARSE-TERM SWAP
        CASE
            [CHAR] + OF + ENDOF
            [CHAR] - OF - ENDOF
        ENDCASE
    REPEAT DROP ;

' _GP-PARSE-EXPR _GP-EXPR-XT !

\ The dependency stack and its parallel error stack have one shared,
\ explicit capacity.  _GE-PUSH checks that capacity before either write.
CREATE _GE-CELL-STACK _GRID-EVAL-DEPTH CELLS ALLOT
CREATE _GE-ERROR-STACK _GRID-EVAL-DEPTH CELLS ALLOT
VARIABLE _GE-DEPTH
VARIABLE _GE-VALUE
VARIABLE _GE-STATUS
VARIABLE _GE-OK

: _GE-PUSH  ( cell -- cell flag )
    _GE-DEPTH @ DUP 0< SWAP _GRID-EVAL-DEPTH >= OR IF 0 EXIT THEN
    DUP _GE-CELL-STACK _GE-DEPTH @ CELLS + !
    _GRID-ST-ERROR _GE-ERROR-STACK _GE-DEPTH @ CELLS + !
    1 _GE-DEPTH +! -1 ;

: _GE-CELL@  ( -- cell )
    _GE-CELL-STACK _GE-DEPTH @ 1- CELLS + @ ;

: _GE-ERROR@  ( -- status )
    _GE-DEPTH @ 0= IF _GRID-ST-ERROR EXIT THEN
    _GE-ERROR-STACK _GE-DEPTH @ 1- CELLS + @ ;

: _GE-NOTE-ERROR  ( status -- )
    _GE-DEPTH @ 0= IF DROP EXIT THEN
    _GE-ERROR-STACK _GE-DEPTH @ 1- CELLS +
    DUP @ _GRID-ST-ERROR = IF ! ELSE 2DROP THEN ;

: _GE-POP  ( -- )
    _GE-DEPTH @ 0> IF -1 _GE-DEPTH +! THEN ;

: _GE-FINISH  ( value status ok -- value ok )
    _GE-OK ! _GE-STATUS ! _GE-VALUE !
    _GE-VALUE @ _GE-CELL@ _GC-VALUE + !
    _GE-STATUS @ _GE-CELL@ _GC-STATUS + !
    2 _GE-CELL@ _GC-MARK + !
    _GE-POP
    _GE-OK @ 0= IF _GE-STATUS @ _GE-NOTE-ERROR THEN
    _GE-VALUE @ _GE-OK @ ;

VARIABLE _GP-RESULT
VARIABLE _GP-RESULT-OK

: _GRID-EVAL-FORMULA  ( addr len -- value ok )
    _GP-PUSH 0= IF
        2DROP _GRID-ST-DEPTH _GE-NOTE-ERROR 0 0 EXIT
    THEN
    _GP-LEN ! _GP-SRC ! 0 _GP-POS ! -1 _GP-OK !
    _GP-EXPR _GP-RESULT !
    _GP-SKIP-WS
    _GP-POS @ _GP-LEN @ <> IF 0 _GP-OK ! THEN
    _GP-OK @ _GP-RESULT-OK !
    _GP-POP
    _GP-RESULT @ _GP-RESULT-OK @ ;

\ ---------------------------------------------------------------------
\ Cell evaluator with cycle detection
\ ---------------------------------------------------------------------

: _GRID-EVAL-CELL  ( row col -- value ok )
    OVER 0< OVER 0< OR IF 2DROP 0 0 EXIT THEN
    OVER _GRID-ROWS >= OVER _GRID-COLS >= OR IF 2DROP 0 0 EXIT THEN
    _GRID-CELL
    DUP _GC-MARK + @ 2 = IF
        DUP _GC-STATUS + @ DUP _GRID-ST-ERROR? IF
            _GE-NOTE-ERROR DROP 0 0 EXIT
        THEN
        DROP _GC-VALUE + @ -1 EXIT
    THEN
    DUP _GC-MARK + @ 1 = IF
        _GRID-ST-CYCLE OVER _GC-STATUS + !
        2 SWAP _GC-MARK + !
        _GRID-ST-CYCLE _GE-NOTE-ERROR 0 0 EXIT
    THEN
    _GE-PUSH 0= IF
        _GRID-ST-DEPTH OVER _GC-STATUS + !
        2 SWAP _GC-MARK + !
        _GRID-ST-DEPTH _GE-NOTE-ERROR 0 0 EXIT
    THEN
    DROP
    1 _GE-CELL@ _GC-MARK + !
    _GE-CELL@ _GC-LEN + @ 0= IF 0 _GRID-ST-TEXT -1 _GE-FINISH EXIT THEN
    _GE-CELL@ _GC-SOURCE + C@ [CHAR] = = IF
        _GE-CELL@ _GC-SOURCE + 1+
        _GE-CELL@ _GC-LEN + @ 1- _GRID-EVAL-FORMULA
        0= IF DROP 0 _GE-ERROR@ 0 _GE-FINISH
        ELSE _GRID-ST-FORMULA -1 _GE-FINISH THEN
        EXIT
    THEN
    _GE-CELL@ _GC-SOURCE + _GE-CELL@ _GC-LEN + @ STR>NUM
    IF _GRID-ST-NUMBER -1 _GE-FINISH
    ELSE DROP 0 _GRID-ST-TEXT -1 _GE-FINISH THEN ;

' _GRID-EVAL-CELL _GRID-EVAL-XT !

: _GRID-RECALCULATE  ( -- )
    0 _GE-DEPTH ! 0 _GP-DEPTH !
    _GRID-ROWS _GRID-COLS * 0 ?DO
        0 _GRID-CELLS @ I _GRID-CELL-SZ * + _GC-MARK + !
    LOOP
    _GRID-MAX-ROW @ 1+ 0 ?DO
        _GRID-MAX-COL @ 1+ 0 ?DO J I _GRID-EVAL-CELL 2DROP LOOP
    LOOP ;

\ ---------------------------------------------------------------------
\ CSV writer
\ ---------------------------------------------------------------------

: _GIO-SYNC-LENGTH  ( -- )
    _GRID-IO-WRITER CBW-LENGTH@ _GRID-IO-U ! ;

: _GIO-RESET  ( -- )
    _GRID-IO-WRITER CBW-RESET DROP
    _GIO-SYNC-LENGTH ;

: _GIO-APPEND  ( addr len -- )
    _GRID-IO-WRITER CBW-APPEND DROP
    _GIO-SYNC-LENGTH ;

: _GIO-CHAR  ( c -- )
    _GRID-IO-WRITER CBW-CHAR DROP
    _GIO-SYNC-LENGTH ;

VARIABLE _GQ-A
VARIABLE _GQ-U

: _GRID-CSV-QUOTE?  ( addr len -- flag )
    _GQ-U ! _GQ-A !
    _GQ-U @ 0 ?DO
        _GQ-A @ I + C@ DUP [CHAR] , = OVER [CHAR] " = OR
        OVER 10 = OR SWAP 13 = OR IF -1 UNLOOP EXIT THEN
    LOOP 0 ;

: _GRID-CSV-FIELD!  ( addr len -- )
    2DUP _GRID-CSV-QUOTE? 0= IF _GIO-APPEND EXIT THEN
    [CHAR] " _GIO-CHAR
    _GQ-U ! _GQ-A !
    _GQ-U @ 0 ?DO
        _GQ-A @ I + C@ DUP _GIO-CHAR
        [CHAR] " = IF [CHAR] " _GIO-CHAR THEN
    LOOP
    [CHAR] " _GIO-CHAR ;

: _GRID-RECALC-MAX  ( -- )
    0 _GRID-MAX-ROW ! 0 _GRID-MAX-COL !
    _GRID-ROWS 0 ?DO
        _GRID-COLS 0 ?DO
            J I _GRID-CELL _GC-LEN + @ 0> IF
                J _GRID-MAX-ROW @ MAX _GRID-MAX-ROW !
                I _GRID-MAX-COL @ MAX _GRID-MAX-COL !
            THEN
        LOOP
    LOOP ;

: _GRID-SERIALIZE  ( -- status )
    _GIO-RESET _GRID-RECALC-MAX
    _GRID-MAX-ROW @ 1+ 0 ?DO
        _GRID-MAX-COL @ 1+ 0 ?DO
            J I _GRID-CELL DUP _GC-SOURCE + SWAP _GC-LEN + @
            _GRID-CSV-FIELD!
            I _GRID-MAX-COL @ < IF [CHAR] , _GIO-CHAR THEN
        LOOP
        10 _GIO-CHAR
    LOOP
    _GRID-IO-WRITER CBW-STATUS@ DUP CBW-S-OK = IF
        DROP _GRID-L-S-OK EXIT
    THEN
    CBW-S-CAPACITY = IF
        _GRID-L-S-CAPACITY ELSE _GRID-L-S-INVALID
    THEN ;

VARIABLE _GRID-SAVE-IOR

: _GRID-WRITE  ( -- ior )
    _GRID-SOURCE-BLOCKED @ IF _GRID-L-S-RECOVERY EXIT THEN
    _GRID-IO-BUF @ _GRID-IO-U @ _GRID-REPLACE VREPL-REPLACE
    DUP VREPL-S-OK = IF DROP 0 EXIT THEN
    DUP VREPL-S-COMMITTED-CLEANUP = IF DROP 0 EXIT THEN
    \ A verified rollback or pre-publication I/O failure leaves the old
    \ target authoritative and the in-memory sheet retryable.  Only states
    \ whose winning generation is ambiguous block another save until load
    \ recovery succeeds.
    DUP VREPL-S-RECOVERY =
    OVER VREPL-S-MARKER-CORRUPT = OR
    OVER VREPL-S-UNCERTAIN = OR IF
        -1 _GRID-SOURCE-BLOCKED !
    THEN ;

\ ---------------------------------------------------------------------
\ UI state and status helpers
\ ---------------------------------------------------------------------

_GRID-CURRENT-STATE CMP-CELL: _GRID-E-BODY
_GRID-CURRENT-STATE CMP-CELL: _GRID-E-SBAR
_GRID-CURRENT-STATE CMP-CELL: _GRID-E-SBAR-CELL
_GRID-CURRENT-STATE CMP-CELL: _GRID-E-SBAR-STATE

_GRID-CURRENT-STATE 40 CMP-FIELD: _GRID-PANEL
_GRID-CURRENT-STATE CMP-CELL: _GRID-PANEL-RGN

_GRID-CURRENT-STATE CMP-CELL: _GRID-PROMPT
_GRID-CURRENT-STATE CMP-CELL: _GRID-PROMPT-RGN
_GRID-CURRENT-STATE CMP-CELL: _GRID-PROMPT-MODE
_GRID-CURRENT-STATE _GRID-PROMPT-CAP CMP-FIELD: _GRID-PROMPT-BUF
_GRID-CURRENT-STATE 4 CMP-FIELD: _GRID-CHAR-BUF

_GRID-CURRENT-STATE 8 CMP-FIELD: _GRID-NAME-BUF
VARIABLE _GN-ROW
VARIABLE _GN-COL
VARIABLE _GN-A
VARIABLE _GN-U

: _GRID-CELL-NAME  ( row col -- addr len )
    _GN-COL ! _GN-ROW !
    _GN-COL @ [CHAR] A + _GRID-NAME-BUF C!
    _GN-ROW @ 1+ NUM>STR _GN-U ! _GN-A !
    _GN-A @ _GRID-NAME-BUF 1+ _GN-U @ CMOVE
    _GRID-NAME-BUF _GN-U @ 1+ ;

_GRID-CURRENT-STATE 72 CMP-FIELD: _GRID-STATE-BUF
_GRID-CURRENT-STATE CMP-CELL: _GRID-STATE-U
VARIABLE _GSA-A
VARIABLE _GSA-U
VARIABLE _GSA-N

: _GSTATE-RESET  ( -- ) 0 _GRID-STATE-U ! ;

: _GSTATE-APPEND  ( addr len -- )
    _GSA-U ! _GSA-A !
    72 _GRID-STATE-U @ - 0 MAX _GSA-U @ MIN _GSA-N !
    _GSA-A @ _GRID-STATE-BUF _GRID-STATE-U @ + _GSA-N @ CMOVE
    _GSA-N @ _GRID-STATE-U +! ;

: _GRID-UPDATE-STATUS  ( -- )
    _GRID-E-SBAR-CELL @ ?DUP IF
        S" text" _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CELL-NAME
        UTUI-SET-ATTR
    THEN
    _GSTATE-RESET S" Grid  |  " _GSTATE-APPEND
    _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CELL DUP _GC-STATUS + @
    CASE
        _GRID-ST-DEPTH OF S" Depth" _GSTATE-APPEND ENDOF
        _GRID-ST-CYCLE OF S" Cycle" _GSTATE-APPEND ENDOF
        _GRID-ST-ERROR OF S" Error" _GSTATE-APPEND ENDOF
        _GRID-ST-FORMULA OF S" Formula" _GSTATE-APPEND ENDOF
        _GRID-ST-NUMBER OF S" Number" _GSTATE-APPEND ENDOF
        DROP S" Text" _GSTATE-APPEND
    ENDCASE
    S"   |  " _GSTATE-APPEND
    _GRID-SOURCE-BLOCKED @ IF
        _GRID-DIRTY @ IF S" Source blocked / Unsaved"
        ELSE S" Source blocked" THEN
    ELSE
        _GRID-DIRTY @ IF S" Unsaved" ELSE S" Saved" THEN
    THEN _GSTATE-APPEND
    _GRID-E-SBAR-STATE @ ?DUP IF
        S" text" _GRID-STATE-BUF _GRID-STATE-U @ UTUI-SET-ATTR
    THEN ;

: _GRID-INVALIDATE  ( -- )
    _GRID-PANEL WDG-DIRTY
    _GRID-E-BODY @ ?DUP IF UIDL-DIRTY! THEN
    _GRID-UPDATE-STATUS
    ASHELL-DIRTY! ;

: _GRID-SAVE  ( -- ior )
    _GRID-SERIALIZE DUP IF
        _GRID-SAVE-IOR !
    ELSE
        DROP _GRID-WRITE _GRID-SAVE-IOR !
    THEN
    _GRID-SAVE-IOR @ 0= IF 0 _GRID-DIRTY ! THEN
    _GRID-INVALIDATE
    _GRID-SAVE-IOR @ ;

: _GRID-COMMIT  ( -- )
    -1 _GRID-DIRTY !
    _GRID-INVALIDATE ;

\ ---------------------------------------------------------------------
\ Prompt and navigation
\ ---------------------------------------------------------------------

VARIABLE _GRID-SHOW-MODE
VARIABLE _GRID-SHOW-LA
VARIABLE _GRID-SHOW-LU
VARIABLE _GRID-SHOW-IA
VARIABLE _GRID-SHOW-IU

: _GRID-SHOW-PROMPT  ( mode label-a label-u initial-a initial-u -- )
    _GRID-SHOW-IU ! _GRID-SHOW-IA ! _GRID-SHOW-LU ! _GRID-SHOW-LA !
    _GRID-SHOW-MODE !
    _GRID-PROMPT @ 0= IF EXIT THEN
    _GRID-SHOW-MODE @ _GRID-PROMPT-MODE !
    _GRID-SHOW-LA @ _GRID-SHOW-LU @
    _GRID-SHOW-IA @ _GRID-SHOW-IU @ _GRID-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _GRID-BEGIN-EDIT  ( -- )
    _GRID-PRM-EDIT S" Edit cell:"
    _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CELL
    DUP _GC-SOURCE + SWAP _GC-LEN + @ _GRID-SHOW-PROMPT ;

: _GRID-BEGIN-REPLACE  ( addr len -- )
    _GRID-PRM-EDIT S" Edit cell:" 2SWAP _GRID-SHOW-PROMPT ;

: _GRID-BEGIN-GOTO  ( -- )
    _GRID-PRM-GOTO S" Go to cell:"
    _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CELL-NAME
    _GRID-SHOW-PROMPT ;

VARIABLE _GNC-A
VARIABLE _GNC-U
VARIABLE _GNC-COL

: _GRID-NAME>COORD  ( addr len -- row col flag )
    STR-TRIM _GNC-U ! _GNC-A !
    _GNC-U @ 2 < IF 0 0 0 EXIT THEN
    _GNC-A @ C@ _GP-UPPER DUP [CHAR] A < OVER [CHAR] P > OR IF
        DROP 0 0 0 EXIT
    THEN
    [CHAR] A - _GNC-COL !
    _GNC-A @ 1+ _GNC-U @ 1- STR>NUM 0= IF DROP 0 0 0 EXIT THEN
    1- DUP 0< OVER _GRID-ROWS >= OR IF DROP 0 0 0 EXIT THEN
    _GNC-COL @ -1 ;

_GRID-CURRENT-STATE CMP-CELL: _GRID-CELL-W
_GRID-CURRENT-STATE CMP-CELL: _GRID-VIS-COLS
_GRID-CURRENT-STATE CMP-CELL: _GRID-VIS-ROWS
_GRID-CURRENT-STATE CMP-CELL: _GRID-PW
_GRID-CURRENT-STATE CMP-CELL: _GRID-PH

CMP-LAYOUT-SIZE CONSTANT _GRID-STATE-SIZE

: _GRID-ACTIVATE  ( instance -- )
    DUP _GRID-CURRENT-INSTANCE !
    CINST-STATE _GRID-CURRENT-STATE ! ;

: _GRID-METRICS  ( -- )
    _GRID-PANEL 8 + @ DUP RGN-W _GRID-PW ! RGN-H _GRID-PH !
    _GRID-PW @ 60 < IF 10 ELSE 12 THEN _GRID-CELL-W !
    _GRID-PW @ 4 - _GRID-CELL-W @ / 1 MAX _GRID-COLS MIN
    _GRID-VIS-COLS !
    _GRID-PH @ 2 - 1 MAX _GRID-ROWS MIN _GRID-VIS-ROWS ! ;

: _GRID-ENSURE-VISIBLE  ( -- )
    _GRID-SEL-COL @ _GRID-SCROLL-COL @ < IF
        _GRID-SEL-COL @ _GRID-SCROLL-COL !
    THEN
    _GRID-SEL-COL @ _GRID-SCROLL-COL @ _GRID-VIS-COLS @ + >= IF
        _GRID-SEL-COL @ _GRID-VIS-COLS @ - 1+ 0 MAX _GRID-SCROLL-COL !
    THEN
    _GRID-SEL-ROW @ _GRID-SCROLL-ROW @ < IF
        _GRID-SEL-ROW @ _GRID-SCROLL-ROW !
    THEN
    _GRID-SEL-ROW @ _GRID-SCROLL-ROW @ _GRID-VIS-ROWS @ + >= IF
        _GRID-SEL-ROW @ _GRID-VIS-ROWS @ - 1+ 0 MAX _GRID-SCROLL-ROW !
    THEN ;

VARIABLE _GM-DR
VARIABLE _GM-DC

: _GRID-MOVE  ( delta-row delta-col -- )
    _GM-DC ! _GM-DR !
    _GRID-SEL-ROW @ _GM-DR @ + 0 MAX _GRID-ROWS 1- MIN _GRID-SEL-ROW !
    _GRID-SEL-COL @ _GM-DC @ + 0 MAX _GRID-COLS 1- MIN _GRID-SEL-COL !
    _GRID-METRICS _GRID-ENSURE-VISIBLE _GRID-INVALIDATE ;

\ ---------------------------------------------------------------------
\ Worksheet drawing
\ ---------------------------------------------------------------------

VARIABLE _GD-CELL
VARIABLE _GD-ROW
VARIABLE _GD-COL
VARIABLE _GD-W
VARIABLE _GD-SELECTED
VARIABLE _GD-FG
VARIABLE _GD-BG
VARIABLE _GD-ATTR
VARIABLE _GD-TEXT-W

: _GRID-DRAW-CELL  ( cell screen-row screen-col width selected -- )
    _GD-SELECTED ! _GD-W ! _GD-COL ! _GD-ROW ! _GD-CELL !
    _GD-SELECTED @ IF
        15 _GD-FG ! 24 _GD-BG ! CELL-A-BOLD _GD-ATTR !
    ELSE
        253 _GD-FG ! 233 _GD-BG ! 0 _GD-ATTR !
    THEN
    _GD-FG @ _GD-BG @ _GD-ATTR @ DRW-STYLE!
    32 _GD-ROW @ _GD-COL @ _GD-W @ DRW-HLINE
    _GD-W @ 1- 1 MAX _GD-TEXT-W !
    _GD-CELL @ _GC-LEN + @ 0= IF EXIT THEN
    _GD-CELL @ _GC-STATUS + @ _GRID-ST-ERROR? IF
        _GD-SELECTED @ 0= IF 203 DRW-FG! THEN
        S" #ERR" _GD-ROW @ _GD-COL @ DRW-TEXT EXIT
    THEN
    _GD-CELL @ _GC-STATUS + @ _GRID-ST-FORMULA = IF
        _GD-SELECTED @ 0= IF 42 DRW-FG! THEN
        _GD-CELL @ _GC-VALUE + @ NUM>STR
        _GD-ROW @ _GD-COL @ _GD-TEXT-W @ DRW-TEXT-RIGHT EXIT
    THEN
    _GD-CELL @ _GC-STATUS + @ _GRID-ST-NUMBER = IF
        _GD-SELECTED @ 0= IF 81 DRW-FG! THEN
        _GD-CELL @ _GC-SOURCE + _GD-CELL @ _GC-LEN + @
        _GD-ROW @ _GD-COL @ _GD-TEXT-W @ DRW-TEXT-RIGHT EXIT
    THEN
    _GD-CELL @ _GC-SOURCE +
    _GD-CELL @ _GC-LEN + @ _GD-TEXT-W @ MIN
    _GD-ROW @ _GD-COL @ DRW-TEXT ;

VARIABLE _GD-ACTUAL-ROW
VARIABLE _GD-ACTUAL-COL
VARIABLE _GD-SCREEN-ROW
VARIABLE _GD-SCREEN-COL

: _GRID-PANEL-DRAW  ( widget -- )
    DROP _GRID-METRICS _GRID-ENSURE-VISIBLE
    253 233 0 DRW-STYLE!
    32 0 0 _GRID-PH @ _GRID-PW @ DRW-FILL-RECT

    253 236 0 DRW-STYLE!
    32 0 0 1 _GRID-PW @ DRW-FILL-RECT
    _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CELL-NAME 0 1 DRW-TEXT
    244 DRW-FG! [CHAR] = 0 6 DRW-CHAR
    _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CELL
    DUP _GC-SOURCE + SWAP _GC-LEN + @ _GRID-PW @ 9 - 0 MAX MIN
    0 8 DRW-TEXT

    255 60 1 DRW-STYLE!
    32 1 0 1 _GRID-PW @ DRW-FILL-RECT
    _GRID-VIS-COLS @ 0 ?DO
        _GRID-SCROLL-COL @ I + DUP _GD-ACTUAL-COL !
        [CHAR] A + 1
        4 I _GRID-CELL-W @ * + _GRID-CELL-W @ 2 / +
        DRW-CHAR
    LOOP

    _GRID-VIS-ROWS @ 0 ?DO
        _GRID-SCROLL-ROW @ I + _GD-ACTUAL-ROW !
        I 2 + _GD-SCREEN-ROW !
        250 236 0 DRW-STYLE!
        _GD-ACTUAL-ROW @ 1+ NUM>STR
        _GD-SCREEN-ROW @ 0 3 DRW-TEXT-RIGHT
        _GRID-VIS-COLS @ 0 ?DO
            _GRID-SCROLL-COL @ I + _GD-ACTUAL-COL !
            4 I _GRID-CELL-W @ * + _GD-SCREEN-COL !
            _GD-ACTUAL-ROW @ _GD-ACTUAL-COL @ _GRID-CELL
            _GD-SCREEN-ROW @ _GD-SCREEN-COL @ _GRID-CELL-W @
            _GD-ACTUAL-ROW @ _GRID-SEL-ROW @ =
            _GD-ACTUAL-COL @ _GRID-SEL-COL @ = AND
            _GRID-DRAW-CELL
        LOOP
    LOOP
    DRW-STYLE-RESET ;

\ ---------------------------------------------------------------------
\ Input handling and actions
\ ---------------------------------------------------------------------

VARIABLE _GRID-H-WIDGET

: _GRID-CLEAR-SELECTED  ( -- )
    _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CLEAR-CELL
    _GRID-RECALCULATE _GRID-COMMIT ;

: _GRID-PANEL-HANDLE  ( event widget -- consumed? )
    _GRID-H-WIDGET !
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-LEFT OF 0 -1 _GRID-MOVE -1 EXIT ENDOF
            KEY-RIGHT OF 0 1 _GRID-MOVE -1 EXIT ENDOF
            KEY-UP OF -1 0 _GRID-MOVE -1 EXIT ENDOF
            KEY-DOWN OF 1 0 _GRID-MOVE -1 EXIT ENDOF
            KEY-PGUP OF _GRID-VIS-ROWS @ NEGATE 0 _GRID-MOVE -1 EXIT ENDOF
            KEY-PGDN OF _GRID-VIS-ROWS @ 0 _GRID-MOVE -1 EXIT ENDOF
            KEY-HOME OF 0 _GRID-SEL-COL ! _GRID-METRICS _GRID-ENSURE-VISIBLE _GRID-INVALIDATE -1 EXIT ENDOF
            KEY-END OF _GRID-MAX-COL @ _GRID-SEL-COL ! _GRID-METRICS _GRID-ENSURE-VISIBLE _GRID-INVALIDATE -1 EXIT ENDOF
            KEY-TAB OF 0 1 _GRID-MOVE -1 EXIT ENDOF
            KEY-BACKTAB OF 0 -1 _GRID-MOVE -1 EXIT ENDOF
            KEY-ENTER OF _GRID-BEGIN-EDIT -1 EXIT ENDOF
            KEY-F2 OF _GRID-BEGIN-EDIT -1 EXIT ENDOF
            KEY-DEL OF _GRID-CLEAR-SELECTED -1 EXIT ENDOF
        ENDCASE
        0 EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
        DUP 16 + @ 0= IF
            8 + @ DUP 32 >= OVER 126 <= AND IF
                _GRID-CHAR-BUF C!
                _GRID-CHAR-BUF 1 _GRID-BEGIN-REPLACE
                -1 EXIT
            THEN DROP
        THEN
    THEN
    DROP 0 ;

: _GRID-PANEL-INIT  ( rgn -- )
    DUP _GRID-PANEL-RGN !
    _GRID-PANEL
    31 OVER !
    SWAP OVER 8 + !
    ['] _GRID-PANEL-DRAW OVER 16 + !
    ['] _GRID-PANEL-HANDLE OVER 24 + !
    WDG-F-VISIBLE WDG-F-DIRTY OR SWAP 32 + ! ;

VARIABLE _GRID-SUB-A
VARIABLE _GRID-SUB-U
VARIABLE _GRID-SUB-MODE

: _GRID-PROMPT-SUBMIT  ( prompt -- )
    PRM-GET-TEXT _GRID-SUB-U ! _GRID-SUB-A !
    _GRID-PROMPT-MODE @ _GRID-SUB-MODE !
    _GRID-PRM-NONE _GRID-PROMPT-MODE !
    _GRID-SUB-MODE @ CASE
        _GRID-PRM-EDIT OF
            _GRID-SUB-U @ _GRID-SOURCE-CAP > IF
                S" A Grid cell is limited to 40 bytes" 2200 ASHELL-TOAST
            ELSE
                _GRID-SUB-A @ _GRID-SUB-U @
                _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-SET-CELL
                _GRID-RECALCULATE _GRID-COMMIT
            THEN
        ENDOF
        _GRID-PRM-GOTO OF
            _GRID-SUB-A @ _GRID-SUB-U @ _GRID-NAME>COORD
            IF
                _GRID-SEL-COL ! _GRID-SEL-ROW !
                _GRID-METRICS _GRID-ENSURE-VISIBLE
            ELSE
                2DROP S" Invalid cell name" 1800 ASHELL-TOAST
            THEN
        ENDOF
    ENDCASE
    _GRID-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _GRID-INVALIDATE ;

: _GRID-PROMPT-CANCEL  ( prompt -- )
    DROP _GRID-PRM-NONE _GRID-PROMPT-MODE !
    _GRID-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _GRID-INVALIDATE ;

: _GRID-DO-SAVE  ( elem -- )
    DROP _GRID-SAVE IF S" Grid save failed" ELSE S" Grid saved" THEN
    1500 ASHELL-TOAST ;

: _GRID-LOAD-ERROR-TOAST  ( status -- )
    DUP _GRID-L-S-TOO-LARGE = IF
        DROP S" Grid source exceeds 96 KiB; current sheet kept"
        3000 ASHELL-TOAST EXIT
    THEN
    DUP _GRID-L-S-RECOVERY = IF
        DROP S" Grid recovery failed; current sheet kept"
        3000 ASHELL-TOAST EXIT
    THEN
    DUP _GRID-L-S-CAPACITY = IF
        DROP S" Grid source exceeds 64 rows or 16 columns"
        3000 ASHELL-TOAST EXIT
    THEN
    DUP _GRID-L-S-FIELD = IF
        DROP S" Grid source has a field over 40 bytes"
        3000 ASHELL-TOAST EXIT
    THEN
    DUP _GRID-L-S-INVALID = IF
        DROP S" Grid source is malformed; current sheet kept"
        3000 ASHELL-TOAST EXIT
    THEN
    DROP S" Grid read failed; current sheet kept" 2800 ASHELL-TOAST ;

: _GRID-RELOAD-NOW  ( -- )
    _GRID-LOAD DUP IF
        _GRID-LOAD-ERROR-TOAST
    ELSE
        DROP _GRID-RECALCULATE 0 _GRID-DIRTY !
        _GRID-INVALIDATE S" Grid reloaded" 1400 ASHELL-TOAST
    THEN ;

: _GRID-DO-RELOAD  ( elem -- )
    DROP
    _GRID-DIRTY @ IF
        S" Reload Grid and discard unsaved changes?" DLG-CONFIRM 0= IF
            EXIT
        THEN
    THEN
    _GRID-RELOAD-NOW ;

: _GRID-DO-EDIT  ( elem -- ) DROP _GRID-BEGIN-EDIT ;
: _GRID-DO-CLEAR-CELL  ( elem -- ) DROP _GRID-CLEAR-SELECTED ;

: _GRID-DO-CLEAR-SHEET  ( elem -- )
    DROP _GRID-CLEAR-MODEL _GRID-RECALCULATE
    0 _GRID-SEL-ROW ! 0 _GRID-SEL-COL ! _GRID-COMMIT ;

: _GRID-DO-RECALC  ( elem -- )
    DROP _GRID-RECALCULATE _GRID-INVALIDATE
    S" Recalculated" 1000 ASHELL-TOAST ;

: _GRID-DO-GOTO  ( elem -- ) DROP _GRID-BEGIN-GOTO ;
: _GRID-DO-QUIT  ( elem -- ) DROP ASHELL-QUIT ;
: _GRID-DO-ABOUT  ( elem -- )
    DROP S" Grid - CSV worksheet with live integer formulas" 2600 ASHELL-TOAST ;

VARIABLE _GRID-SOURCE-REQ
VARIABLE _GRID-INIT-LOAD-STATUS

: _GRID-SOURCE-COMPLETE  ( request -- )
    DUP CBR.STATUS @ CBUS-S-OK <> IF
        S" Could not route the Grid source" 2000 ASHELL-TOAST
    THEN
    CBR-FREE ;

: _GRID-POST-SOURCE-INTENT  ( intent-a intent-u -- )
    CBR-NEW DUP IF
        2DROP 2DROP S" Could not allocate source request" 1800 ASHELL-TOAST EXIT
    THEN
    DROP _GRID-SOURCE-REQ !
    CPRINC-COMPONENT _GRID-SOURCE-REQ @ CBR.PRINCIPAL !
    S" /grid.csv" _GRID-SOURCE-REQ @ CBR.ARGS IRES-VFS! IF
        2DROP _GRID-SOURCE-REQ @ CBR-FREE EXIT
    THEN
    ['] _GRID-SOURCE-COMPLETE _GRID-SOURCE-REQ @ CBR.COMPLETE-XT !
    _GRID-SOURCE-REQ @ _GRID-CURRENT-INSTANCE @ CINST-POST-INTENT
    DUP CBUS-S-OK <> IF
        DROP _GRID-SOURCE-REQ @ CBR-FREE
        S" Source routing is unavailable outside Desk" 1800 ASHELL-TOAST
    ELSE DROP THEN ;

: _GRID-DO-EDIT-SOURCE  ( elem -- )
    DROP S" resource.open" _GRID-POST-SOURCE-INTENT ;

: _GRID-DO-REVEAL-SOURCE  ( elem -- )
    DROP S" resource.reveal" _GRID-POST-SOURCE-INTENT ;

\ ---------------------------------------------------------------------
\ App lifecycle
\ ---------------------------------------------------------------------

: GRID-INIT-CB  ( instance -- )
    _GRID-ACTIVATE
    _GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * ALLOCATE
    0<> ABORT" grid: cell allocation failed" _GRID-CELLS !
    _GRID-IO-CAP ALLOCATE
    0<> ABORT" grid: I/O allocation failed" _GRID-IO-BUF !
    _GRID-IO-BUF @ _GRID-IO-CAP _GRID-IO-WRITER CBW-INIT
    0<> ABORT" grid: I/O writer initialization failed"
    0 _GRID-PROMPT ! 0 _GRID-PROMPT-RGN ! 0 _GRID-PANEL-RGN !
    _GRID-PRM-NONE _GRID-PROMPT-MODE !
    0 _GRID-SEL-ROW ! 0 _GRID-SEL-COL !
    0 _GRID-SCROLL-ROW ! 0 _GRID-SCROLL-COL ! 0 _GRID-DIRTY !
    0 _GRID-SOURCE-BLOCKED ! 0 _GRID-IO-U !
    1 _GRID-VIS-COLS ! 1 _GRID-VIS-ROWS !
    VFS-CUR DUP 0= ABORT" grid: no VFS available" _GRID-VFS !
    _GRID-VFS @ _GRID-LOAD-SCOPE VFA-SCOPE-INIT
    0<> ABORT" grid: access scope initialization failed"
    _GRID-VFS @ _GRID-REPLACE VREPL-INIT
    0<> ABORT" grid: replacement initialization failed"
    S" /grid.csv" _GRID-REPLACE VREPL-DERIVE-PATHS!
    0<> ABORT" grid: replacement path setup failed"
    _GRID-CLEAR-MODEL
    S" grid-body" UTUI-BY-ID _GRID-E-BODY !
    S" sbar" UTUI-BY-ID _GRID-E-SBAR !
    S" sbar-cell" UTUI-BY-ID _GRID-E-SBAR-CELL !
    S" sbar-state" UTUI-BY-ID _GRID-E-SBAR-STATE !
    _GRID-LOAD _GRID-INIT-LOAD-STATUS ! _GRID-RECALCULATE

    _GRID-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW DUP _GRID-PROMPT-RGN !
        _GRID-PROMPT-BUF _GRID-PROMPT-CAP PRM-NEW DUP _GRID-PROMPT !
        ['] _GRID-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
        ['] _GRID-PROMPT-CANCEL OVER PRM-ON-CANCEL
        15 23 ROT PRM-COLORS!
    THEN
    _GRID-E-BODY @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW _GRID-PANEL-INIT
        _GRID-PANEL _GRID-E-BODY @ UTUI-WIDGET-SET
    THEN
    S" save" ['] _GRID-DO-SAVE UTUI-DO!
    S" reload" ['] _GRID-DO-RELOAD UTUI-DO!
    S" edit-cell" ['] _GRID-DO-EDIT UTUI-DO!
    S" clear-cell" ['] _GRID-DO-CLEAR-CELL UTUI-DO!
    S" clear-sheet" ['] _GRID-DO-CLEAR-SHEET UTUI-DO!
    S" recalculate" ['] _GRID-DO-RECALC UTUI-DO!
    S" goto" ['] _GRID-DO-GOTO UTUI-DO!
    S" quit" ['] _GRID-DO-QUIT UTUI-DO!
    S" about" ['] _GRID-DO-ABOUT UTUI-DO!
    S" edit-source" ['] _GRID-DO-EDIT-SOURCE UTUI-DO!
    S" reveal-source" ['] _GRID-DO-REVEAL-SOURCE UTUI-DO!
    _GRID-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _GRID-UPDATE-STATUS
    _GRID-INIT-LOAD-STATUS @ ?DUP IF _GRID-LOAD-ERROR-TOAST THEN ;

: GRID-EVENT-CB  ( event instance -- consumed? )
    _GRID-ACTIVATE
    _GRID-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    _UTUI-MENU-OPEN @ IF DROP 0 EXIT THEN
    _GRID-PANEL WDG-HANDLE ;

: GRID-PAINT-CB  ( instance -- )
    _GRID-ACTIVATE
    _GRID-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN DROP
    _GRID-E-SBAR @ ?DUP IF UTUI-ELEM-RGN _GRID-PROMPT @ PRM-SET-BOUNDS THEN
    _GRID-PROMPT @ WDG-DRAW ;

: GRID-TICK-CB  ( instance -- ) _GRID-ACTIVATE ;

: GRID-REQUEST-CLOSE-CB  ( reason instance -- decision )
    _GRID-ACTIVATE DROP
    _GRID-DIRTY @ 0= IF APP-CLOSE-D-ALLOW EXIT THEN
    S" Close Grid and discard unsaved changes?" DLG-CONFIRM IF
        APP-CLOSE-D-ALLOW
    ELSE
        APP-CLOSE-D-CANCEL
    THEN ;

: GRID-SHUTDOWN-CB  ( instance -- )
    _GRID-ACTIVATE
    _GRID-E-BODY @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _GRID-PROMPT @ ?DUP IF PRM-FREE THEN
    _GRID-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _GRID-PANEL-RGN @ ?DUP IF RGN-FREE THEN
    _GRID-CELLS @ ?DUP IF FREE THEN
    _GRID-IO-BUF @ ?DUP IF FREE THEN
    0 _GRID-CELLS ! 0 _GRID-IO-BUF ! 0 _GRID-PROMPT !
    0 _GRID-PROMPT-RGN ! 0 _GRID-PANEL-RGN ! ;

CREATE _GRID-CELL-TEXT-SCHEMA CS-SIZE ALLOT
CREATE _GRID-CSV-SCHEMA CS-SIZE ALLOT
CREATE _GRID-RESOURCE-SCHEMA CS-SIZE ALLOT
CREATE _GRID-NULL-SCHEMA CS-SIZE ALLOT
CREATE _GRID-BOOL-SCHEMA CS-SIZE ALLOT
5 CONSTANT _GRID-CAP-COUNT
CREATE GRID-CAPS _GRID-CAP-COUNT CAP-DESC * ALLOT
: GRID-CAP-SET       ( -- cap ) GRID-CAPS ;
: GRID-CAP-SELECTED  ( -- cap ) GRID-CAPS CAP-DESC + ;
: GRID-CAP-CSV       ( -- cap ) GRID-CAPS CAP-DESC 2 * + ;
: GRID-CAP-SOURCE    ( -- cap ) GRID-CAPS CAP-DESC 3 * + ;
: GRID-CAP-SAVE      ( -- cap ) GRID-CAPS CAP-DESC 4 * + ;

VARIABLE _GCH-A
VARIABLE _GCH-U

: _GRID-CAP-SET-HANDLER  ( request instance -- status )
    _GRID-ACTIVATE
    DUP CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@ _GCH-U ! _GCH-A !
    _GCH-U @ _GRID-SOURCE-CAP > IF DROP CBUS-S-FAILED EXIT THEN
    _GCH-A @ _GCH-U @ _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-SET-CELL
    _GRID-RECALCULATE _GRID-COMMIT
    DUP CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@
    ROT CBR.RESULT CV-STRING! IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _GRID-CAP-SELECTED-HANDLER  ( request instance -- status )
    _GRID-ACTIVATE
    _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-CELL
    DUP _GC-SOURCE + SWAP _GC-LEN + @ ROT CBR.RESULT CV-STRING!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _GRID-CAP-CSV-HANDLER  ( request instance -- status )
    _GRID-ACTIVATE
    _GRID-SERIALIZE IF DROP CBUS-S-FAILED EXIT THEN
    _GRID-IO-BUF @ _GRID-IO-U @ ROT CBR.RESULT CV-STRING!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _GRID-CAP-SOURCE-HANDLER  ( request instance -- status )
    _GRID-ACTIVATE
    S" /grid.csv" ROT CBR.RESULT IRES-VFS!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _GRID-CAP-SAVE-HANDLER  ( request instance -- status )
    _GRID-ACTIVATE
    _GRID-SAVE 0= DUP ROT CBR.RESULT CV-BOOL!
    IF CBUS-S-OK ELSE CBUS-S-FAILED THEN ;

: _GRID-CAP-SETUP  ( -- )
    _GRID-CELL-TEXT-SCHEMA CS-INIT
    CV-T-STRING _GRID-CELL-TEXT-SCHEMA CS-ALLOW!
    _GRID-SOURCE-CAP _GRID-CELL-TEXT-SCHEMA CS-MAX-LEN!
    _GRID-CSV-SCHEMA CS-INIT
    CV-T-STRING _GRID-CSV-SCHEMA CS-ALLOW!
    _GRID-IO-CAP _GRID-CSV-SCHEMA CS-MAX-LEN!
    _GRID-RESOURCE-SCHEMA CS-INIT
    CV-T-RESOURCE _GRID-RESOURCE-SCHEMA CS-ALLOW!
    516 _GRID-RESOURCE-SCHEMA CS-MAX-LEN!
    _GRID-NULL-SCHEMA CS-INIT
    CV-T-NULL _GRID-NULL-SCHEMA CS-ALLOW!
    _GRID-BOOL-SCHEMA CS-INIT
    CV-T-BOOL _GRID-BOOL-SCHEMA CS-ALLOW!

    GRID-CAP-SET CAP-DESC-INIT
    CAP-K-COMMAND GRID-CAP-SET CAP.KIND !
    S" grid.cell.set-selected"
    GRID-CAP-SET CAP.ID-U ! GRID-CAP-SET CAP.ID-A !
    S" Set selected cell"
    GRID-CAP-SET CAP.TITLE-U ! GRID-CAP-SET CAP.TITLE-A !
    S" Replace the selected cell source and recalculate dependents"
    GRID-CAP-SET CAP.DESC-U ! GRID-CAP-SET CAP.DESC-A !
    _GRID-CELL-TEXT-SCHEMA GRID-CAP-SET CAP.IN-SCHEMA !
    _GRID-CELL-TEXT-SCHEMA GRID-CAP-SET CAP.OUT-SCHEMA !
    CAP-E-MUTATE GRID-CAP-SET CAP.EFFECTS !
    CAP-F-NEEDS-TARGET GRID-CAP-SET CAP.FLAGS !
    ['] _GRID-CAP-SET-HANDLER GRID-CAP-SET CAP.HANDLER-XT !

    GRID-CAP-SELECTED CAP-DESC-INIT
    CAP-K-RESOURCE GRID-CAP-SELECTED CAP.KIND !
    S" grid.cell.selected"
    GRID-CAP-SELECTED CAP.ID-U ! GRID-CAP-SELECTED CAP.ID-A !
    S" Selected cell"
    GRID-CAP-SELECTED CAP.TITLE-U ! GRID-CAP-SELECTED CAP.TITLE-A !
    S" Read the selected cell source"
    GRID-CAP-SELECTED CAP.DESC-U ! GRID-CAP-SELECTED CAP.DESC-A !
    _GRID-CELL-TEXT-SCHEMA GRID-CAP-SELECTED CAP.OUT-SCHEMA !
    CAP-E-OBSERVE GRID-CAP-SELECTED CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
    GRID-CAP-SELECTED CAP.FLAGS !
    ['] _GRID-CAP-SELECTED-HANDLER GRID-CAP-SELECTED CAP.HANDLER-XT !

    GRID-CAP-CSV CAP-DESC-INIT
    CAP-K-RESOURCE GRID-CAP-CSV CAP.KIND !
    S" grid.workbook.csv"
    GRID-CAP-CSV CAP.ID-U ! GRID-CAP-CSV CAP.ID-A !
    S" Workbook CSV"
    GRID-CAP-CSV CAP.TITLE-U ! GRID-CAP-CSV CAP.TITLE-A !
    S" Read the used worksheet range as CSV"
    GRID-CAP-CSV CAP.DESC-U ! GRID-CAP-CSV CAP.DESC-A !
    _GRID-CSV-SCHEMA GRID-CAP-CSV CAP.OUT-SCHEMA !
    CAP-E-OBSERVE GRID-CAP-CSV CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR GRID-CAP-CSV CAP.FLAGS !
    ['] _GRID-CAP-CSV-HANDLER GRID-CAP-CSV CAP.HANDLER-XT !

    GRID-CAP-SOURCE CAP-DESC-INIT
    CAP-K-RESOURCE GRID-CAP-SOURCE CAP.KIND !
    S" grid.source"
    GRID-CAP-SOURCE CAP.ID-U ! GRID-CAP-SOURCE CAP.ID-A !
    S" Grid source"
    GRID-CAP-SOURCE CAP.TITLE-U ! GRID-CAP-SOURCE CAP.TITLE-A !
    S" Read the durable workbook resource"
    GRID-CAP-SOURCE CAP.DESC-U ! GRID-CAP-SOURCE CAP.DESC-A !
    _GRID-RESOURCE-SCHEMA GRID-CAP-SOURCE CAP.OUT-SCHEMA !
    CAP-E-OBSERVE GRID-CAP-SOURCE CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR GRID-CAP-SOURCE CAP.FLAGS !
    ['] _GRID-CAP-SOURCE-HANDLER GRID-CAP-SOURCE CAP.HANDLER-XT !

    GRID-CAP-SAVE CAP-DESC-INIT
    CAP-K-COMMAND GRID-CAP-SAVE CAP.KIND !
    S" grid.workbook.save"
    GRID-CAP-SAVE CAP.ID-U ! GRID-CAP-SAVE CAP.ID-A !
    S" Save workbook"
    GRID-CAP-SAVE CAP.TITLE-U ! GRID-CAP-SAVE CAP.TITLE-A !
    S" Persist the current worksheet to its CSV source"
    GRID-CAP-SAVE CAP.DESC-U ! GRID-CAP-SAVE CAP.DESC-A !
    _GRID-NULL-SCHEMA GRID-CAP-SAVE CAP.IN-SCHEMA !
    _GRID-BOOL-SCHEMA GRID-CAP-SAVE CAP.OUT-SCHEMA !
    CAP-E-PERSIST GRID-CAP-SAVE CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR GRID-CAP-SAVE CAP.FLAGS !
    ['] _GRID-CAP-SAVE-HANDLER GRID-CAP-SAVE CAP.HANDLER-XT ! ;

CREATE GRID-COMP-DESC COMP-DESC ALLOT

: _GRID-COMP-SETUP  ( -- )
    _GRID-CAP-SETUP
    GRID-COMP-DESC COMP-DESC-INIT
    S" org.akashic.grid"
    GRID-COMP-DESC COMP.ID-U ! GRID-COMP-DESC COMP.ID-A !
    S" 1.0.0"
    GRID-COMP-DESC COMP.VERSION-U ! GRID-COMP-DESC COMP.VERSION-A !
    _GRID-STATE-SIZE GRID-COMP-DESC COMP.STATE-SIZE !
    GRID-CAPS GRID-COMP-DESC COMP.CAPS-A !
    _GRID-CAP-COUNT GRID-COMP-DESC COMP.CAPS-N ! ;

: GRID-ENTRY  ( desc -- )
    _GRID-COMP-SETUP
    DUP APP-DESC-INIT
    GRID-COMP-DESC      OVER APP.COMP-DESC !
    ['] GRID-INIT-CB OVER APP.INIT-XT !
    ['] GRID-EVENT-CB OVER APP.EVENT-XT !
    ['] GRID-TICK-CB OVER APP.TICK-XT !
    ['] GRID-PAINT-CB OVER APP.PAINT-XT !
    ['] GRID-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _GRID-ACTIVATE OVER APP.ACTIVATE-XT !
    ['] GRID-REQUEST-CLOSE-CB OVER APP.REQUEST-CLOSE-XT !
    S" tui/applets/grid/grid.uidl"
    ROT DUP >R APP.UIDL-FILE-U ! R@ APP.UIDL-FILE-A !
    0 R@ APP.WIDTH ! 0 R@ APP.HEIGHT !
    S" Grid" R@ APP.TITLE-U ! R> APP.TITLE-A ! ;

CREATE GRID-DESC APP-DESC ALLOT

: GRID-RUN  ( -- )
    GRID-DESC GRID-ENTRY
    GRID-DESC ASHELL-RUN ;
