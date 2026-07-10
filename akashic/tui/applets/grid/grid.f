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
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widget.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/string.f

64 CONSTANT _GRID-ROWS
16 CONSTANT _GRID-COLS
40 CONSTANT _GRID-SOURCE-CAP
72 CONSTANT _GRID-CELL-SZ
98304 CONSTANT _GRID-IO-CAP
256 CONSTANT _GRID-PROMPT-CAP
16 CONSTANT _GRID-PARSE-DEPTH

 0 CONSTANT _GC-LEN
 8 CONSTANT _GC-VALUE
16 CONSTANT _GC-STATUS
24 CONSTANT _GC-MARK
32 CONSTANT _GC-SOURCE

0  CONSTANT _GRID-ST-TEXT
1  CONSTANT _GRID-ST-NUMBER
2  CONSTANT _GRID-ST-FORMULA
-1 CONSTANT _GRID-ST-ERROR

0 CONSTANT _GRID-PRM-NONE
1 CONSTANT _GRID-PRM-EDIT
2 CONSTANT _GRID-PRM-GOTO

VARIABLE _GRID-CELLS
VARIABLE _GRID-IO-BUF
VARIABLE _GRID-IO-U
VARIABLE _GRID-MAX-ROW
VARIABLE _GRID-MAX-COL
VARIABLE _GRID-SEL-ROW
VARIABLE _GRID-SEL-COL
VARIABLE _GRID-SCROLL-ROW
VARIABLE _GRID-SCROLL-COL
VARIABLE _GRID-DIRTY
VARIABLE _GRID-VFS

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
    _GS-ROW @ _GS-COL @ _GRID-CELL _GS-CELL !
    _GS-CELL @ _GC-SOURCE + _GRID-SOURCE-CAP 0 FILL
    _GS-U @ _GRID-SOURCE-CAP MIN DUP _GS-N !
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
VARIABLE _GCSV-QUOTED
VARIABLE _GCSV-CH

: _GCSV-FIELD-RESET  ( -- )
    0 _GCSV-FIELD-U ! 0 _GCSV-QUOTED !
    _GRID-CSV-FIELD _GRID-SOURCE-CAP 0 FILL ;

: _GCSV-FIELD-CHAR  ( c -- )
    _GCSV-FIELD-U @ _GRID-SOURCE-CAP < IF
        _GRID-CSV-FIELD _GCSV-FIELD-U @ + C!
        1 _GCSV-FIELD-U +!
    ELSE DROP THEN ;

: _GCSV-FIELD-FINISH  ( -- )
    _GRID-CSV-FIELD _GCSV-FIELD-U @ _GCSV-ROW @ _GCSV-COL @
    _GRID-SET-CELL
    1 _GCSV-COL +!
    _GCSV-FIELD-RESET ;

: _GRID-PARSE-CSV  ( -- )
    _GRID-CLEAR-MODEL
    0 _GCSV-POS ! 0 _GCSV-ROW ! 0 _GCSV-COL ! _GCSV-FIELD-RESET
    BEGIN _GCSV-POS @ _GRID-IO-U @ < WHILE
        _GRID-IO-BUF @ _GCSV-POS @ + C@ DUP _GCSV-CH !
        _GCSV-QUOTED @ IF
            _GCSV-CH @ [CHAR] " = IF
                _GCSV-POS @ 1+ _GRID-IO-U @ < IF
                    _GRID-IO-BUF @ _GCSV-POS @ + 1+ C@ [CHAR] " = IF
                        [CHAR] " _GCSV-FIELD-CHAR
                        2 _GCSV-POS +!
                    ELSE
                        0 _GCSV-QUOTED ! 1 _GCSV-POS +!
                    THEN
                ELSE
                    0 _GCSV-QUOTED ! 1 _GCSV-POS +!
                THEN
            ELSE
                _GCSV-CH @ _GCSV-FIELD-CHAR 1 _GCSV-POS +!
            THEN
        ELSE
            _GCSV-CH @ CASE
                [CHAR] " OF -1 _GCSV-QUOTED ! 1 _GCSV-POS +! ENDOF
                [CHAR] , OF _GCSV-FIELD-FINISH 1 _GCSV-POS +! ENDOF
                10 OF
                    _GCSV-FIELD-FINISH
                    1 _GCSV-ROW +! 0 _GCSV-COL !
                    1 _GCSV-POS +!
                ENDOF
                13 OF 1 _GCSV-POS +! ENDOF
                _GCSV-CH @ _GCSV-FIELD-CHAR 1 _GCSV-POS +!
            ENDCASE
        THEN
    REPEAT
    _GCSV-FIELD-U @ 0> _GCSV-COL @ 0> OR IF _GCSV-FIELD-FINISH THEN ;

VARIABLE _GRID-LOAD-FD

: _GRID-LOAD  ( -- ior )
    _GRID-CLEAR-MODEL
    VFS-CUR >R _GRID-VFS @ VFS-USE
    S" /grid.csv" VFS-OPEN
    R> VFS-USE
    DUP 0= IF DROP 0 EXIT THEN
    _GRID-LOAD-FD !
    _GRID-IO-BUF @ _GRID-IO-CAP _GRID-LOAD-FD @ VFS-READ _GRID-IO-U !
    _GRID-LOAD-FD @ VFS-CLOSE
    _GRID-PARSE-CSV
    0 ;

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

VARIABLE _GP-RESULT
VARIABLE _GP-RESULT-OK

: _GRID-EVAL-FORMULA  ( addr len -- value ok )
    _GP-PUSH 0= IF 2DROP 0 0 EXIT THEN
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

CREATE _GE-CELL-STACK 20 CELLS ALLOT
VARIABLE _GE-DEPTH
VARIABLE _GE-VALUE
VARIABLE _GE-STATUS
VARIABLE _GE-OK

: _GE-PUSH  ( cell -- )
    _GE-CELL-STACK _GE-DEPTH @ CELLS + ! 1 _GE-DEPTH +! ;

: _GE-CELL@  ( -- cell )
    _GE-CELL-STACK _GE-DEPTH @ 1- CELLS + @ ;

: _GE-POP  ( -- ) -1 _GE-DEPTH +! ;

: _GE-FINISH  ( value status ok -- value ok )
    _GE-OK ! _GE-STATUS ! _GE-VALUE !
    _GE-VALUE @ _GE-CELL@ _GC-VALUE + !
    _GE-STATUS @ _GE-CELL@ _GC-STATUS + !
    2 _GE-CELL@ _GC-MARK + !
    _GE-POP
    _GE-VALUE @ _GE-OK @ ;

: _GRID-EVAL-CELL  ( row col -- value ok )
    OVER 0< OVER 0< OR IF 2DROP 0 0 EXIT THEN
    OVER _GRID-ROWS >= OVER _GRID-COLS >= OR IF 2DROP 0 0 EXIT THEN
    _GRID-CELL
    DUP _GC-MARK + @ 2 = IF
        DUP _GC-VALUE + @ SWAP _GC-STATUS + @ _GRID-ST-ERROR <> EXIT
    THEN
    DUP _GC-MARK + @ 1 = IF
        _GRID-ST-ERROR OVER _GC-STATUS + !
        2 SWAP _GC-MARK + ! 0 0 EXIT
    THEN
    _GE-PUSH
    1 _GE-CELL@ _GC-MARK + !
    _GE-CELL@ _GC-LEN + @ 0= IF 0 _GRID-ST-TEXT -1 _GE-FINISH EXIT THEN
    _GE-CELL@ _GC-SOURCE + C@ [CHAR] = = IF
        _GE-CELL@ _GC-SOURCE + 1+
        _GE-CELL@ _GC-LEN + @ 1- _GRID-EVAL-FORMULA
        0= IF DROP 0 _GRID-ST-ERROR 0 _GE-FINISH
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

VARIABLE _GIO-A
VARIABLE _GIO-U
VARIABLE _GIO-N

: _GIO-RESET  ( -- ) 0 _GRID-IO-U ! ;

: _GIO-APPEND  ( addr len -- )
    _GIO-U ! _GIO-A !
    _GRID-IO-CAP _GRID-IO-U @ - 0 MAX _GIO-U @ MIN DUP _GIO-N !
    _GIO-A @ _GRID-IO-BUF @ _GRID-IO-U @ + _GIO-N @ CMOVE
    _GIO-N @ _GRID-IO-U +! ;

: _GIO-CHAR  ( c -- )
    _GRID-IO-U @ _GRID-IO-CAP < IF
        _GRID-IO-BUF @ _GRID-IO-U @ + C! 1 _GRID-IO-U +!
    ELSE DROP THEN ;

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

: _GRID-SERIALIZE  ( -- )
    _GIO-RESET _GRID-RECALC-MAX
    _GRID-MAX-ROW @ 1+ 0 ?DO
        _GRID-MAX-COL @ 1+ 0 ?DO
            J I _GRID-CELL DUP _GC-SOURCE + SWAP _GC-LEN + @
            _GRID-CSV-FIELD!
            I _GRID-MAX-COL @ < IF [CHAR] , _GIO-CHAR THEN
        LOOP
        10 _GIO-CHAR
    LOOP ;

VARIABLE _GRID-SAVE-FD
VARIABLE _GRID-SAVE-ACTUAL
VARIABLE _GRID-SAVE-IOR

: _GRID-WRITE  ( -- ior )
    VFS-CUR >R _GRID-VFS @ VFS-USE
    S" /grid.csv" VFS-OPEN
    DUP 0= IF
        DROP S" /grid.csv" _GRID-VFS @ VFS-CREATE
        DUP 0= IF DROP R> VFS-USE -1 EXIT THEN DROP
        S" /grid.csv" VFS-OPEN
        DUP 0= IF DROP R> VFS-USE -1 EXIT THEN
    THEN
    R> VFS-USE _GRID-SAVE-FD !
    _GRID-SAVE-FD @ VFS-REWIND
    0 _GRID-SAVE-FD @ VFS-TRUNCATE IF
        _GRID-SAVE-FD @ VFS-CLOSE -2 EXIT
    THEN
    _GRID-IO-BUF @ _GRID-IO-U @ _GRID-SAVE-FD @ VFS-WRITE
    _GRID-SAVE-ACTUAL !
    _GRID-SAVE-FD @ VFS-CLOSE
    _GRID-VFS @ VFS-SYNC DROP
    _GRID-SAVE-ACTUAL @ _GRID-IO-U @ = IF 0 ELSE -3 THEN ;

\ ---------------------------------------------------------------------
\ UI state and status helpers
\ ---------------------------------------------------------------------

VARIABLE _GRID-E-BODY
VARIABLE _GRID-E-SBAR
VARIABLE _GRID-E-SBAR-CELL
VARIABLE _GRID-E-SBAR-STATE

CREATE _GRID-PANEL 40 ALLOT
VARIABLE _GRID-PANEL-RGN

VARIABLE _GRID-PROMPT
VARIABLE _GRID-PROMPT-RGN
VARIABLE _GRID-PROMPT-MODE
CREATE _GRID-PROMPT-BUF _GRID-PROMPT-CAP ALLOT
CREATE _GRID-CHAR-BUF 4 ALLOT

CREATE _GRID-NAME-BUF 8 ALLOT
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

CREATE _GRID-STATE-BUF 72 ALLOT
VARIABLE _GRID-STATE-U
VARIABLE _GSA-A
VARIABLE _GSA-U
VARIABLE _GSA-N

: _GSTATE-RESET  ( -- ) 0 _GRID-STATE-U ! ;

: _GSTATE-APPEND  ( addr len -- )
    _GSA-U ! _GSA-A !
    72 _GRID-STATE-U @ - 0 MAX _GSA-U @ MIN DUP _GSA-N !
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
        _GRID-ST-ERROR OF S" Error" _GSTATE-APPEND ENDOF
        _GRID-ST-FORMULA OF S" Formula" _GSTATE-APPEND ENDOF
        _GRID-ST-NUMBER OF S" Number" _GSTATE-APPEND ENDOF
        DROP S" Text" _GSTATE-APPEND
    ENDCASE
    S"   |  " _GSTATE-APPEND
    _GRID-DIRTY @ IF S" Unsaved" ELSE S" Saved" THEN _GSTATE-APPEND
    _GRID-E-SBAR-STATE @ ?DUP IF
        S" text" _GRID-STATE-BUF _GRID-STATE-U @ UTUI-SET-ATTR
    THEN ;

: _GRID-INVALIDATE  ( -- )
    _GRID-PANEL WDG-DIRTY
    _GRID-E-BODY @ ?DUP IF UIDL-DIRTY! THEN
    _GRID-UPDATE-STATUS
    ASHELL-DIRTY! ;

: _GRID-SAVE  ( -- ior )
    _GRID-SERIALIZE _GRID-WRITE DUP _GRID-SAVE-IOR !
    0= IF 0 _GRID-DIRTY ! THEN
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

VARIABLE _GRID-CELL-W
VARIABLE _GRID-VIS-COLS
VARIABLE _GRID-VIS-ROWS
VARIABLE _GRID-PW
VARIABLE _GRID-PH

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
    _GD-CELL @ _GC-STATUS + @ _GRID-ST-ERROR = IF
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
            _GRID-SUB-A @ _GRID-SUB-U @
            _GRID-SEL-ROW @ _GRID-SEL-COL @ _GRID-SET-CELL
            _GRID-RECALCULATE _GRID-COMMIT
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

: _GRID-DO-RELOAD  ( elem -- )
    DROP _GRID-LOAD DROP _GRID-RECALCULATE 0 _GRID-DIRTY !
    _GRID-INVALIDATE S" Grid reloaded" 1400 ASHELL-TOAST ;

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

\ ---------------------------------------------------------------------
\ App lifecycle
\ ---------------------------------------------------------------------

: GRID-INIT-CB  ( -- )
    _GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * ALLOCATE
    0<> ABORT" grid: cell allocation failed" _GRID-CELLS !
    _GRID-IO-CAP ALLOCATE
    0<> ABORT" grid: I/O allocation failed" _GRID-IO-BUF !
    0 _GRID-PROMPT ! 0 _GRID-PROMPT-RGN ! 0 _GRID-PANEL-RGN !
    _GRID-PRM-NONE _GRID-PROMPT-MODE !
    0 _GRID-SEL-ROW ! 0 _GRID-SEL-COL !
    0 _GRID-SCROLL-ROW ! 0 _GRID-SCROLL-COL ! 0 _GRID-DIRTY !
    1 _GRID-VIS-COLS ! 1 _GRID-VIS-ROWS !
    VFS-CUR DUP 0= ABORT" grid: no VFS available" _GRID-VFS !
    S" grid-body" UTUI-BY-ID _GRID-E-BODY !
    S" sbar" UTUI-BY-ID _GRID-E-SBAR !
    S" sbar-cell" UTUI-BY-ID _GRID-E-SBAR-CELL !
    S" sbar-state" UTUI-BY-ID _GRID-E-SBAR-STATE !
    _GRID-LOAD DROP _GRID-RECALCULATE

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
    _GRID-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _GRID-UPDATE-STATUS ;

: GRID-EVENT-CB  ( event -- consumed? )
    _GRID-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    _UTUI-MENU-OPEN @ IF DROP 0 EXIT THEN
    _GRID-PANEL WDG-HANDLE ;

: GRID-PAINT-CB  ( -- )
    _GRID-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN DROP
    _GRID-E-SBAR @ ?DUP IF UTUI-ELEM-RGN _GRID-PROMPT @ PRM-SET-BOUNDS THEN
    _GRID-PROMPT @ WDG-DRAW ;

: GRID-TICK-CB  ( -- ) ;

: GRID-SHUTDOWN-CB  ( -- )
    _GRID-E-BODY @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _GRID-PROMPT @ ?DUP IF PRM-FREE THEN
    _GRID-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _GRID-PANEL-RGN @ ?DUP IF RGN-FREE THEN
    _GRID-CELLS @ ?DUP IF FREE THEN
    _GRID-IO-BUF @ ?DUP IF FREE THEN
    0 _GRID-CELLS ! 0 _GRID-IO-BUF ! 0 _GRID-PROMPT !
    0 _GRID-PROMPT-RGN ! 0 _GRID-PANEL-RGN ! ;

: GRID-ENTRY  ( desc -- )
    DUP APP-DESC-INIT
    ['] GRID-INIT-CB OVER APP.INIT-XT !
    ['] GRID-EVENT-CB OVER APP.EVENT-XT !
    ['] GRID-TICK-CB OVER APP.TICK-XT !
    ['] GRID-PAINT-CB OVER APP.PAINT-XT !
    ['] GRID-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    S" tui/applets/grid/grid.uidl"
    ROT DUP >R APP.UIDL-FILE-U ! R@ APP.UIDL-FILE-A !
    0 R@ APP.WIDTH ! 0 R@ APP.HEIGHT !
    S" Grid" R@ APP.TITLE-U ! R> APP.TITLE-A ! ;

CREATE GRID-DESC APP-DESC ALLOT

: GRID-RUN  ( -- )
    GRID-DESC GRID-ENTRY
    GRID-DESC ASHELL-RUN ;
