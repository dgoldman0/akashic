\ ======================================================================
\  LEL — LIRAQ Expression Language evaluator (Layer 2)
\ ======================================================================
\
\  Pure, total, deterministic formula evaluator for UIDL data bindings.
\  Evaluates expressions against the current state tree (ST-USE).
\
\  Public API:
\    LEL-EVAL           ( expr-a expr-l -- type v1 v2 )
\    LEL-SET-CONTEXT    ( item-node index -- )
\    LEL-CLEAR-CONTEXT  ( -- )
\
\  Types returned match ST-T-* constants from state-tree.f:
\    ST-T-STRING(1) ST-T-INTEGER(2) ST-T-BOOLEAN(3) ST-T-NULL(4)
\    ST-T-FLOAT(5) ST-T-ARRAY(6) ST-T-OBJECT(7)
\
\  Totality: every expression produces a value, never errors.
\    Division by zero -> 0, missing path -> null, type mismatch -> 0/''/false.
\
\  Limits: 2048 chars max expr, 32 nesting levels, 16 args per call.
\

REQUIRE ../utils/string.f
REQUIRE ../math/fp32.f
REQUIRE ../math/fixed.f
REQUIRE state-tree.f

PROVIDED akashic-lel

\ =====================================================================
\  Token type constants
\ =====================================================================

0  CONSTANT TK-EOF
1  CONSTANT TK-INT
2  CONSTANT TK-STR
3  CONSTANT TK-TRUE
4  CONSTANT TK-FALSE
5  CONSTANT TK-NULL
6  CONSTANT TK-IDENT
7  CONSTANT TK-LPAREN
8  CONSTANT TK-RPAREN
9  CONSTANT TK-COMMA
10 CONSTANT TK-DOT
11 CONSTANT TK-FLOAT
12 CONSTANT TK-ERR
13 CONSTANT TK-PLUS
14 CONSTANT TK-MINUS
15 CONSTANT TK-STAR
16 CONSTANT TK-SLASH
17 CONSTANT TK-PERCENT
18 CONSTANT TK-EQEQ
19 CONSTANT TK-BANGEQ
20 CONSTANT TK-GT
21 CONSTANT TK-GE
22 CONSTANT TK-LT
23 CONSTANT TK-LE
24 CONSTANT TK-QUESTION
25 CONSTANT TK-COLON

\ =====================================================================
\  Lexer state
\ =====================================================================

VARIABLE _LEL-SRC      \ expression string address
VARIABLE _LEL-SLEN     \ expression string length
VARIABLE _LEL-POS      \ current scan position
VARIABLE _LEL-TOK      \ current token type
VARIABLE _LEL-TVAL1    \ token value cell 1
VARIABLE _LEL-TVAL2    \ token value cell 2

\ =====================================================================
\  Error flag
\ =====================================================================

VARIABLE _LEL-ERR      \ 0 = OK, nonzero = error

\ =====================================================================
\  Value stack — 48 entries, 3 cells each (type, val1, val2)
\ =====================================================================

CREATE _LEL-VS  144 CELLS ALLOT
VARIABLE _LEL-VSP

: _LEL-VPUSH ( type v1 v2 -- )
    _LEL-VSP @ 48 >= IF DROP 2DROP EXIT THEN
    _LEL-VSP @ 3 * CELLS _LEL-VS +
    >R                    \ R: base-addr
    R@ 16 + !             \ store v2 at offset 16
    R@ 8 + !              \ store v1 at offset 8
    R> !                  \ store type at offset 0
    1 _LEL-VSP +! ;

: _LEL-VPOP ( -- type v1 v2 )
    _LEL-VSP @ 0= IF ST-T-NULL 0 0 EXIT THEN
    _LEL-VSP @ 1- DUP _LEL-VSP !
    3 * CELLS _LEL-VS +
    DUP @ OVER 8 + @ ROT 16 + @ ;

: _LEL-VPOP-N ( n -- )
    NEGATE _LEL-VSP +!
    _LEL-VSP @ 0< IF 0 _LEL-VSP ! THEN ;

: _LEL-VIDX ( i -- type v1 v2 )
    3 * CELLS _LEL-VS +
    DUP @ OVER 8 + @ ROT 16 + @ ;

\ =====================================================================
\  Path buffer — 256 bytes for assembling dot-separated paths
\ =====================================================================

CREATE _LEL-PBUF  256 ALLOT
VARIABLE _LEL-PPOS

: _LEL-PRST  0 _LEL-PPOS ! ;

: _LEL-PAPP ( addr len -- )
    _LEL-PPOS @ OVER + 256 > IF 2DROP EXIT THEN
    _LEL-PBUF _LEL-PPOS @ +   \ ( addr len dest )
    SWAP                       \ ( addr dest len )
    DUP >R CMOVE
    R> _LEL-PPOS +! ;

: _LEL-PAPP-CH ( ch -- )
    _LEL-PPOS @ 255 >= IF DROP EXIT THEN
    _LEL-PBUF _LEL-PPOS @ + C!
    1 _LEL-PPOS +! ;

: _LEL-PGET ( -- addr len )
    _LEL-PBUF _LEL-PPOS @ ;

\ =====================================================================
\  Scratch string buffer — 4096 bytes, bump allocator
\ =====================================================================

CREATE _LEL-SBUF  4096 ALLOT
VARIABLE _LEL-SPOS

: _LEL-SRST  0 _LEL-SPOS ! ;

: _LEL-SAPP ( addr len -- )
    _LEL-SPOS @ OVER + 4096 > IF 2DROP EXIT THEN
    _LEL-SBUF _LEL-SPOS @ +   \ ( addr len dest )
    SWAP                       \ ( addr dest len )
    DUP >R CMOVE
    R> _LEL-SPOS +! ;

: _LEL-SAPP-CH ( ch -- )
    _LEL-SPOS @ 4095 >= IF DROP EXIT THEN
    _LEL-SBUF _LEL-SPOS @ + C!
    1 _LEL-SPOS +! ;

\ =====================================================================
\  Context variables for collection templates
\ =====================================================================

VARIABLE _LEL-ITEM     \ state-tree node for _item (0 = null)
VARIABLE _LEL-INDEX    \ integer for _index

0 _LEL-ITEM !
0 _LEL-INDEX !

\ =====================================================================
\  Temp variables for number scanning
\ =====================================================================

VARIABLE _LEL-NINT     \ integer part accumulator
VARIABLE _LEL-NFRAC    \ fractional part accumulator
VARIABLE _LEL-NDIV     \ fractional divisor
VARIABLE _LEL-NNEG     \ negative flag

\ =====================================================================
\  Temp variables for misc use
\ =====================================================================

VARIABLE _LEL-TSTART   \ scratch pos at start of string result
VARIABLE _LEL-TMP      \ general temp
VARIABLE _LEL-FN-A     \ function name address
VARIABLE _LEL-FN-L     \ function name length
VARIABLE _LEL-CNODE    \ current node during _item navigation
VARIABLE _LEL-CNA      \ child-nav search name address
VARIABLE _LEL-CNL      \ child-nav search name length

\ =====================================================================
\  Forward declarations — mutual recursion via VARIABLE + EXECUTE
\ =====================================================================

VARIABLE _XT-EXPR      \ XT of main expression parser
VARIABLE _XT-SKIP      \ XT of skip-expression parser

: _LEL-EXPR   _XT-EXPR @ EXECUTE ;
: _LEL-SKIP-EXPR  _XT-SKIP @ EXECUTE ;

\ =====================================================================
\  Lexer — character helpers
\ =====================================================================

: _LEL-PEEK ( -- ch | -1 )
    _LEL-POS @ _LEL-SLEN @ >= IF -1 EXIT THEN
    _LEL-SRC @ _LEL-POS @ + C@ ;

: _LEL-ADV ( -- )
    _LEL-POS @ 1+ _LEL-POS ! ;

: _LEL-SKIP-WS ( -- )
    BEGIN
        _LEL-PEEK
        DUP 32 = OVER 9 = OR OVER 10 = OR OVER 13 = OR
    WHILE
        DROP _LEL-ADV
    REPEAT
    DROP ;

: _LEL-DIGIT? ( ch -- flag )
    DUP 48 >= SWAP 57 <= AND ;

: _LEL-ALPHA? ( ch -- flag )
    DUP 97 >= SWAP 122 <= AND ;

: _LEL-IDENT-START? ( ch -- flag )
    DUP _LEL-ALPHA? IF DROP TRUE EXIT THEN
    95 = ;

: _LEL-IDENT-CH? ( ch -- flag )
    DUP _LEL-ALPHA? IF DROP TRUE EXIT THEN
    DUP _LEL-DIGIT? IF DROP TRUE EXIT THEN
    DUP 45 = IF DROP TRUE EXIT THEN
    95 = ;

\ =====================================================================
\  Lexer — scan string literal
\ =====================================================================

: _LEL-SCAN-STR ( -- )
    _LEL-ADV                              \ consume opening '
    _LEL-SPOS @                           \ ( start-offset )
    BEGIN
        _LEL-PEEK
        DUP -1 = IF                       \ unterminated
            2DROP 12 _LEL-TOK ! EXIT
        THEN
        DUP 39 = IF                       \ quote char
            DROP _LEL-ADV
            _LEL-PEEK 39 = IF             \ escaped ''
                39 _LEL-SAPP-CH
                _LEL-ADV
            ELSE                           \ end of string
                DUP _LEL-SBUF + _LEL-TVAL1 !
                _LEL-SPOS @ SWAP - _LEL-TVAL2 !
                2 _LEL-TOK !
                EXIT
            THEN
        ELSE
            _LEL-SAPP-CH
            _LEL-ADV
        THEN
    AGAIN ;

\ =====================================================================
\  Lexer — scan number (integer or float)
\ =====================================================================

: _LEL-SCAN-NUM ( neg-flag -- )
    _LEL-NNEG !
    0 _LEL-NINT !
    \ Accumulate integer digits
    BEGIN
        _LEL-PEEK DUP _LEL-DIGIT?
    WHILE
        48 - _LEL-NINT @ 10 * + _LEL-NINT !
        _LEL-ADV
    REPEAT
    DROP
    \ Check for '.digit' -> float literal
    _LEL-PEEK 46 = IF
        _LEL-POS @ 1+ _LEL-SLEN @ < IF
            _LEL-SRC @ _LEL-POS @ 1+ + C@ _LEL-DIGIT? IF
                \ Float literal — parse fractional part
                _LEL-ADV
                0 _LEL-NFRAC !  1 _LEL-NDIV !
                BEGIN
                    _LEL-PEEK DUP _LEL-DIGIT?
                WHILE
                    48 - _LEL-NFRAC @ 10 * + _LEL-NFRAC !
                    _LEL-NDIV @ 10 * _LEL-NDIV !
                    _LEL-ADV
                REPEAT
                DROP
                \ Build FP32: int-part + frac/div
                _LEL-NINT @ INT>FP32
                _LEL-NFRAC @ INT>FP32
                _LEL-NDIV @ INT>FP32
                FP32-DIV FP32-ADD
                _LEL-NNEG @ IF FP32-NEGATE THEN
                _LEL-TVAL1 !
                11 _LEL-TOK !
                EXIT
            THEN
        THEN
    THEN
    \ Integer literal
    _LEL-NINT @ _LEL-NNEG @ IF NEGATE THEN
    _LEL-TVAL1 !
    1 _LEL-TOK ! ;

\ =====================================================================
\  Lexer — scan identifier / keyword
\ =====================================================================

: _LEL-SCAN-IDENT ( -- )
    _LEL-SRC @ _LEL-POS @ +              \ start address in source
    BEGIN
        _LEL-PEEK DUP _LEL-IDENT-CH?
    WHILE
        DROP _LEL-ADV
    REPEAT
    DROP
    _LEL-SRC @ _LEL-POS @ + OVER -       \ ( start-addr length )
    \ Check keywords
    2DUP S" true"  STR-STR= IF 2DROP 3  _LEL-TOK ! EXIT THEN
    2DUP S" false" STR-STR= IF 2DROP 4  _LEL-TOK ! EXIT THEN
    2DUP S" null"  STR-STR= IF 2DROP 5  _LEL-TOK ! EXIT THEN
    \ Plain identifier
    6 _LEL-TOK !
    _LEL-TVAL2 ! _LEL-TVAL1 ! ;

\ =====================================================================
\  Lexer — main tokenizer
\ =====================================================================

: _LEL-NEXT ( -- )
    _LEL-SKIP-WS
    _LEL-PEEK
    DUP -1 = IF DROP 0  _LEL-TOK ! EXIT THEN
    DUP 40 = IF DROP _LEL-ADV 7  _LEL-TOK ! EXIT THEN
    DUP 41 = IF DROP _LEL-ADV 8  _LEL-TOK ! EXIT THEN
    DUP 44 = IF DROP _LEL-ADV 9  _LEL-TOK ! EXIT THEN
    DUP 46 = IF DROP _LEL-ADV 10 _LEL-TOK ! EXIT THEN
    DUP 39 = IF DROP _LEL-SCAN-STR EXIT THEN
    DUP _LEL-DIGIT? IF DROP 0 _LEL-SCAN-NUM EXIT THEN
    DUP 43 = IF DROP _LEL-ADV TK-PLUS     _LEL-TOK ! EXIT THEN  \ +
    DUP 45 = IF DROP _LEL-ADV TK-MINUS    _LEL-TOK ! EXIT THEN  \ -
    DUP 42 = IF DROP _LEL-ADV TK-STAR     _LEL-TOK ! EXIT THEN  \ *
    DUP 47 = IF DROP _LEL-ADV TK-SLASH    _LEL-TOK ! EXIT THEN  \ /
    DUP 37 = IF DROP _LEL-ADV TK-PERCENT  _LEL-TOK ! EXIT THEN  \ %
    DUP 63 = IF DROP _LEL-ADV TK-QUESTION _LEL-TOK ! EXIT THEN  \ ?
    DUP 58 = IF DROP _LEL-ADV TK-COLON    _LEL-TOK ! EXIT THEN  \ :
    DUP 62 = IF                                                   \ >
        DROP _LEL-ADV
        _LEL-PEEK 61 = IF _LEL-ADV TK-GE _LEL-TOK !
        ELSE TK-GT _LEL-TOK ! THEN EXIT
    THEN
    DUP 60 = IF                                                   \ <
        DROP _LEL-ADV
        _LEL-PEEK 61 = IF _LEL-ADV TK-LE _LEL-TOK !
        ELSE TK-LT _LEL-TOK ! THEN EXIT
    THEN
    DUP 61 = IF                                                   \ =
        DROP _LEL-ADV
        _LEL-PEEK 61 = IF _LEL-ADV TK-EQEQ _LEL-TOK !
        ELSE TK-ERR _LEL-TOK ! THEN EXIT
    THEN
    DUP 33 = IF                                                   \ !
        DROP _LEL-ADV
        _LEL-PEEK 61 = IF _LEL-ADV TK-BANGEQ _LEL-TOK !
        ELSE TK-ERR _LEL-TOK ! THEN EXIT
    THEN
    DUP _LEL-IDENT-START? IF DROP _LEL-SCAN-IDENT EXIT THEN
    DROP _LEL-ADV 12 _LEL-TOK ! ;

\ =====================================================================
\  Peek ahead — look at next non-WS char without consuming
\ =====================================================================

: _LEL-PEEK-AHEAD ( -- ch | -1 )
    _LEL-POS @ _LEL-TMP !
    BEGIN
        _LEL-TMP @ _LEL-SLEN @ >= IF -1 EXIT THEN
        _LEL-SRC @ _LEL-TMP @ + C@
        DUP 32 = OVER 9 = OR IF
            DROP _LEL-TMP @ 1+ _LEL-TMP !
        ELSE
            EXIT
        THEN
    AGAIN ;

\ =====================================================================
\  Child navigation helpers (for _item path resolution)
\ =====================================================================

: _LEL-NAV-CHILD ( parent name-a name-l -- child | 0 )
    _LEL-CNL ! _LEL-CNA !
    SN.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP SN.NAMEA @ OVER SN.NAMEL @
        _LEL-CNA @ _LEL-CNL @
        STR-STR=
        IF EXIT THEN
        SN.NEXT @
    REPEAT ;

: _LEL-NAV-NTH ( parent idx -- child | 0 )
    SWAP SN.FCHILD @
    SWAP
    0 ?DO
        DUP 0= IF UNLOOP EXIT THEN
        SN.NEXT @
    LOOP ;

\ =====================================================================
\  Node-to-value — read state tree node, push as LEL value
\ =====================================================================

: _LEL-NODE-TO-VAL ( node -- )
    DUP ST-GET-TYPE
    DUP ST-T-STRING = IF
        DROP ST-GET-STR ST-T-STRING -ROT _LEL-VPUSH EXIT
    THEN
    DUP ST-T-INTEGER = IF
        DROP ST-GET-INT ST-T-INTEGER SWAP 0 _LEL-VPUSH EXIT
    THEN
    DUP ST-T-BOOLEAN = IF
        DROP ST-GET-BOOL ST-T-BOOLEAN SWAP 0 _LEL-VPUSH EXIT
    THEN
    DUP ST-T-FLOAT = IF
        DROP ST-GET-FLOAT ST-T-FLOAT SWAP 0 _LEL-VPUSH EXIT
    THEN
    DUP ST-T-NULL = IF
        2DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT
    THEN
    DUP ST-T-ARRAY = IF
        DROP ST-T-ARRAY SWAP 0 _LEL-VPUSH EXIT
    THEN
    DUP ST-T-OBJECT = IF
        DROP ST-T-OBJECT SWAP 0 _LEL-VPUSH EXIT
    THEN
    2DROP ST-T-NULL 0 0 _LEL-VPUSH ;

\ =====================================================================
\  _item path resolution
\ =====================================================================

: _LEL-RESOLVE-ITEM ( -- )
    _LEL-NEXT
    _LEL-ITEM @ DUP 0= IF
        DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT
    THEN
    _LEL-CNODE !
    BEGIN
        _LEL-TOK @ TK-DOT =
    WHILE
        _LEL-NEXT
        _LEL-TOK @ TK-IDENT = IF
            _LEL-CNODE @
            _LEL-TVAL1 @ _LEL-TVAL2 @
            _LEL-NAV-CHILD
            DUP 0= IF
                DROP ST-T-NULL 0 0 _LEL-VPUSH
                _LEL-NEXT EXIT
            THEN
            _LEL-CNODE !
        ELSE _LEL-TOK @ TK-INT = IF
            _LEL-CNODE @ _LEL-TVAL1 @ _LEL-NAV-NTH
            DUP 0= IF
                DROP ST-T-NULL 0 0 _LEL-VPUSH
                _LEL-NEXT EXIT
            THEN
            _LEL-CNODE !
        ELSE
            ST-T-NULL 0 0 _LEL-VPUSH
            _LEL-NEXT EXIT
        THEN THEN
        _LEL-NEXT
    REPEAT
    _LEL-CNODE @ _LEL-NODE-TO-VAL ;

\ =====================================================================
\  State reference — build dot path, navigate state tree
\ =====================================================================

: _LEL-BUILD-PATH ( ident-a ident-l -- path-a path-l )
    _LEL-PRST
    _LEL-PAPP
    _LEL-NEXT
    BEGIN
        _LEL-TOK @ TK-DOT =
    WHILE
        46 _LEL-PAPP-CH
        _LEL-NEXT
        _LEL-TOK @ TK-IDENT = IF
            _LEL-TVAL1 @ _LEL-TVAL2 @ _LEL-PAPP
        ELSE _LEL-TOK @ TK-INT = IF
            _LEL-TVAL1 @ NUM>STR _LEL-PAPP
        THEN THEN
        _LEL-NEXT
    REPEAT
    _LEL-PGET ;

: _LEL-STATE-OR-CTX ( ident-a ident-l -- )
    2DUP S" _index" STR-STR= IF
        2DROP
        ST-T-INTEGER _LEL-INDEX @ 0 _LEL-VPUSH
        _LEL-NEXT EXIT
    THEN
    2DUP S" _item" STR-STR= IF
        2DROP _LEL-RESOLVE-ITEM EXIT
    THEN
    _LEL-BUILD-PATH
    ST-GET-PATH
    DUP 0= IF
        DROP ST-T-NULL 0 0 _LEL-VPUSH
    ELSE
        _LEL-NODE-TO-VAL
    THEN ;

\ =====================================================================
\  Coercion helpers
\ =====================================================================

: _LEL-COERCE-INT ( type v1 v2 -- n )
    ROT
    DUP ST-T-INTEGER = IF DROP DROP EXIT THEN
    DUP ST-T-BOOLEAN = IF DROP DROP EXIT THEN
    DUP ST-T-FLOAT   = IF DROP DROP FP32>INT EXIT THEN
    DUP ST-T-STRING  = IF DROP STR>NUM IF EXIT THEN 0 EXIT THEN
    DROP 2DROP 0 ;

: _LEL-COERCE-FP32 ( type v1 v2 -- fp32 )
    ROT
    DUP ST-T-FLOAT   = IF DROP DROP EXIT THEN
    DUP ST-T-INTEGER = IF DROP DROP INT>FP32 EXIT THEN
    DUP ST-T-BOOLEAN = IF DROP DROP INT>FP32 EXIT THEN
    DUP ST-T-STRING  = IF
        DROP STR>NUM IF INT>FP32 ELSE DROP FP32-ZERO THEN EXIT
    THEN
    DROP 2DROP FP32-ZERO ;

: _LEL-EITHER-FLOAT? ( -- flag )
    _LEL-VSP @ 1- 3 * CELLS _LEL-VS + @  ST-T-FLOAT =
    _LEL-VSP @ 2 - 3 * CELLS _LEL-VS + @  ST-T-FLOAT = OR ;

\ =====================================================================
\  Arithmetic builtins (Phase 2)
\ =====================================================================

: _LEL-FN-ADD ( -- )
    _LEL-EITHER-FLOAT? IF
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        FP32-ADD ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT
        _LEL-VPOP _LEL-COERCE-INT
        + ST-T-INTEGER SWAP 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-SUB ( -- )
    _LEL-EITHER-FLOAT? IF
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        SWAP FP32-SUB ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT
        _LEL-VPOP _LEL-COERCE-INT
        SWAP - ST-T-INTEGER SWAP 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-MUL ( -- )
    _LEL-EITHER-FLOAT? IF
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        FP32-MUL ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT
        _LEL-VPOP _LEL-COERCE-INT
        * ST-T-INTEGER SWAP 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-DIV ( -- )
    _LEL-EITHER-FLOAT? IF
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        SWAP FP32-DIV ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT DUP 0= IF
            DROP _LEL-VPOP _LEL-COERCE-INT DROP
            ST-T-INTEGER 0 0 _LEL-VPUSH
        ELSE
            _LEL-VPOP _LEL-COERCE-INT SWAP /
            ST-T-INTEGER SWAP 0 _LEL-VPUSH
        THEN
    THEN ;

: _LEL-FN-MOD ( -- )
    _LEL-EITHER-FLOAT? IF
        \ float mod: a - floor(a/b)*b
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        SWAP OVER                       \ ( b a b )
        FP32-DIV FP32>FX FX-FLOOR FX>FP32 \ ( b a floor(a/b) )
        ROT FP32-MUL FP32-SUB            \ ( a-floor(a/b)*b )
        ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT DUP 0= IF
            DROP _LEL-VPOP _LEL-COERCE-INT DROP
            ST-T-INTEGER 0 0 _LEL-VPUSH
        ELSE
            _LEL-VPOP _LEL-COERCE-INT SWAP MOD
            ST-T-INTEGER SWAP 0 _LEL-VPUSH
        THEN
    THEN ;

: _LEL-FN-NEG ( -- )
    _LEL-VSP @ 1- 3 * CELLS _LEL-VS + @ ST-T-FLOAT = IF
        _LEL-VPOP _LEL-COERCE-FP32 FP32-NEGATE
        ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT NEGATE
        ST-T-INTEGER SWAP 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-ABS ( -- )
    _LEL-VSP @ 1- 3 * CELLS _LEL-VS + @ ST-T-FLOAT = IF
        _LEL-VPOP _LEL-COERCE-FP32 FP32-ABS
        ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT ABS
        ST-T-INTEGER SWAP 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-ROUND ( -- )
    _LEL-VPOP _LEL-COERCE-FP32
    FP32>FX FX-ROUND FX>FP32
    ST-T-FLOAT SWAP 0 _LEL-VPUSH ;

: _LEL-FN-FLOOR ( -- )
    _LEL-VPOP _LEL-COERCE-FP32
    FP32>FX FX-FLOOR FX>FP32
    ST-T-FLOAT SWAP 0 _LEL-VPUSH ;

: _LEL-FN-CEIL ( -- )
    _LEL-VPOP _LEL-COERCE-FP32
    FP32>FX FX-CEIL FX>FP32
    ST-T-FLOAT SWAP 0 _LEL-VPUSH ;

: _LEL-FN-MIN ( -- )
    _LEL-EITHER-FLOAT? IF
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        FP32-MIN ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT
        _LEL-VPOP _LEL-COERCE-INT
        MIN ST-T-INTEGER SWAP 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-MAX ( -- )
    _LEL-EITHER-FLOAT? IF
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        FP32-MAX ST-T-FLOAT SWAP 0 _LEL-VPUSH
    ELSE
        _LEL-VPOP _LEL-COERCE-INT
        _LEL-VPOP _LEL-COERCE-INT
        MAX ST-T-INTEGER SWAP 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-CLAMP ( -- )
    \ clamp(val, lo, hi) — all 3 from vstack (hi on top)
    _LEL-VPOP _LEL-COERCE-INT               \ hi
    _LEL-VPOP _LEL-COERCE-INT               \ lo hi
    _LEL-VPOP _LEL-COERCE-INT               \ val lo hi
    ROT                                       \ ( lo hi val )
    OVER MIN                                  \ ( lo clamp-hi )
    ROT MAX                                   \ ( clamped )
    ST-T-INTEGER SWAP 0 _LEL-VPUSH ;

\ =====================================================================
\  Truthy helper + comparison/logic builtins (Phase 3)
\ =====================================================================

: _LEL-TRUTHY? ( type v1 v2 -- flag )
    ROT
    DUP ST-T-NULL    = IF DROP 2DROP FALSE EXIT THEN
    DUP ST-T-BOOLEAN = IF DROP DROP 0<> EXIT THEN
    DUP ST-T-INTEGER = IF DROP DROP 0<> EXIT THEN
    DUP ST-T-FLOAT   = IF DROP DROP FP32-0= 0= EXIT THEN
    DUP ST-T-STRING  = IF DROP NIP 0<> EXIT THEN
    DROP 2DROP TRUE ;

: _LEL-IS-NUMERIC? ( type -- flag )
    DUP ST-T-INTEGER = OVER ST-T-FLOAT = OR SWAP ST-T-BOOLEAN = OR ;

: _LEL-FN-EQ ( -- )
    _LEL-VSP @ 1- 3 * CELLS _LEL-VS + @    \ type-b
    _LEL-VSP @ 2 - 3 * CELLS _LEL-VS + @   \ type-a type-b
    \ Both null?
    OVER ST-T-NULL = OVER ST-T-NULL = AND IF
        2DROP 2 _LEL-VPOP-N
        ST-T-BOOLEAN 1 0 _LEL-VPUSH EXIT
    THEN
    \ Both string?
    OVER ST-T-STRING = OVER ST-T-STRING = AND IF
        2DROP
        _LEL-VPOP ROT DROP
        _LEL-VPOP ROT DROP
        STR-STR= IF 1 ELSE 0 THEN
        ST-T-BOOLEAN SWAP 0 _LEL-VPUSH EXIT
    THEN
    \ Both numeric-compatible?
    OVER _LEL-IS-NUMERIC? OVER _LEL-IS-NUMERIC? AND IF
        2DROP
        _LEL-VPOP _LEL-COERCE-FP32
        _LEL-VPOP _LEL-COERCE-FP32
        FP32= IF 1 ELSE 0 THEN
        ST-T-BOOLEAN SWAP 0 _LEL-VPUSH EXIT
    THEN
    \ Different types → false
    2DROP 2 _LEL-VPOP-N
    ST-T-BOOLEAN 0 0 _LEL-VPUSH ;

: _LEL-FN-NEQ ( -- )
    _LEL-FN-EQ
    _LEL-VPOP _LEL-COERCE-INT IF 0 ELSE 1 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-GT ( -- )
    _LEL-VPOP _LEL-COERCE-FP32
    _LEL-VPOP _LEL-COERCE-FP32
    SWAP FP32> IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-GTE ( -- )
    _LEL-VPOP _LEL-COERCE-FP32
    _LEL-VPOP _LEL-COERCE-FP32
    SWAP FP32>= IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-LT ( -- )
    _LEL-VPOP _LEL-COERCE-FP32
    _LEL-VPOP _LEL-COERCE-FP32
    SWAP FP32< IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-LTE ( -- )
    _LEL-VPOP _LEL-COERCE-FP32
    _LEL-VPOP _LEL-COERCE-FP32
    SWAP FP32<= IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-NOT ( -- )
    _LEL-VPOP _LEL-TRUTHY? IF 0 ELSE 1 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

\ Short-circuit functions — manage their own lexer

: _LEL-FN-IF ( -- )
    _LEL-NEXT _LEL-NEXT       \ consume 'if' '(' → first arg token
    _LEL-EXPR                  \ evaluate condition
    _LEL-VPOP _LEL-TRUTHY? IF
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-EXPR              \ evaluate then-branch
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-SKIP-EXPR         \ skip else-branch
    ELSE
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-SKIP-EXPR         \ skip then-branch
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-EXPR              \ evaluate else-branch
    THEN
    _LEL-NEXT ;               \ consume ')'

: _LEL-FN-AND ( -- )
    _LEL-NEXT _LEL-NEXT
    _LEL-EXPR
    _LEL-VSP @ 1- _LEL-VIDX _LEL-TRUTHY? IF
        _LEL-VPOP 2DROP DROP   \ discard truthy a
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-EXPR              \ return b
    ELSE
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-SKIP-EXPR         \ skip b, keep falsy a
    THEN
    _LEL-NEXT ;

: _LEL-FN-OR ( -- )
    _LEL-NEXT _LEL-NEXT
    _LEL-EXPR
    _LEL-VSP @ 1- _LEL-VIDX _LEL-TRUTHY? IF
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-SKIP-EXPR         \ skip b, keep truthy a
    ELSE
        _LEL-VPOP 2DROP DROP   \ discard falsy a
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-EXPR              \ return b
    THEN
    _LEL-NEXT ;

: _LEL-FN-COALESCE ( -- )
    _LEL-NEXT _LEL-NEXT
    _LEL-EXPR
    _LEL-VSP @ 1- 3 * CELLS _LEL-VS + @ ST-T-NULL <> IF
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-SKIP-EXPR         \ skip b, keep non-null a
    ELSE
        _LEL-VPOP 2DROP DROP   \ discard null a
        _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
        _LEL-EXPR              \ return b
    THEN
    _LEL-NEXT ;

\ =====================================================================
\  String coercion helper
\ =====================================================================

: _LEL-COERCE-STR ( type v1 v2 -- addr len )
    ROT
    DUP ST-T-STRING  = IF DROP EXIT THEN
    DUP ST-T-INTEGER = IF DROP DROP NUM>STR EXIT THEN
    DUP ST-T-FLOAT   = IF DROP DROP FP32>INT NUM>STR EXIT THEN
    DUP ST-T-BOOLEAN = IF
        DROP DROP IF S" true" ELSE S" false" THEN EXIT
    THEN
    DUP ST-T-NULL = IF 2DROP DROP S" " EXIT THEN
    2DROP DROP S" " ;

\ =====================================================================
\  String builtins (Phase 4)
\ =====================================================================

: _LEL-FN-CONCAT ( argc -- )
    DUP 0= IF DROP ST-T-STRING _LEL-SBUF 0 _LEL-VPUSH EXIT THEN
    _LEL-SPOS @  >R           \ save scratch start; R: start
    _LEL-VSP @ OVER -         \ ( argc base-idx )
    OVER 0 ?DO
        DUP I + _LEL-VIDX
        _LEL-COERCE-STR
        _LEL-SAPP
    LOOP
    DROP                       \ drop base-idx
    _LEL-VPOP-N               \ pop all args
    _LEL-SBUF R@ + _LEL-SPOS @ R> -
    ST-T-STRING -ROT _LEL-VPUSH ;

: _LEL-FN-LENGTH ( -- )
    _LEL-VPOP
    ROT DUP ST-T-STRING = IF
        DROP NIP ST-T-INTEGER SWAP 0 _LEL-VPUSH EXIT
    THEN
    DUP ST-T-ARRAY = OVER ST-T-OBJECT = OR IF
        DROP DROP SN.NCHILD @
        ST-T-INTEGER SWAP 0 _LEL-VPUSH EXIT
    THEN
    DROP 2DROP ST-T-INTEGER 0 0 _LEL-VPUSH ;

: _LEL-FN-UPPER ( -- )
    _LEL-VPOP _LEL-COERCE-STR
    DUP 0= IF ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    _LEL-SPOS @ >R  _LEL-SAPP
    _LEL-SBUF R@ + _LEL-SPOS @ R> -
    2DUP STR-TOUPPER
    ST-T-STRING -ROT _LEL-VPUSH ;

: _LEL-FN-LOWER ( -- )
    _LEL-VPOP _LEL-COERCE-STR
    DUP 0= IF ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    _LEL-SPOS @ >R  _LEL-SAPP
    _LEL-SBUF R@ + _LEL-SPOS @ R> -
    2DUP STR-TOLOWER
    ST-T-STRING -ROT _LEL-VPUSH ;

: _LEL-FN-TRIM ( -- )
    _LEL-VPOP _LEL-COERCE-STR
    STR-TRIM
    ST-T-STRING -ROT _LEL-VPUSH ;

: _LEL-FN-SUBSTRING ( -- )
    _LEL-VPOP _LEL-COERCE-INT _LEL-TMP !  \ save req-len
    _LEL-VPOP _LEL-COERCE-INT              \ ( req-start )
    _LEL-VPOP _LEL-COERCE-STR              \ ( req-start s-addr s-len )
    ROT 0 MAX OVER MIN                     \ ( s-addr s-len clamped-start )
    DUP >R - SWAP R> +                     \ ( remaining result-addr )
    SWAP _LEL-TMP @ 0 MAX OVER MIN         \ ( result-addr clamped-len )
    ST-T-STRING -ROT _LEL-VPUSH ;

: _LEL-FN-CONTAINS ( -- )
    _LEL-VPOP _LEL-COERCE-STR >R >R       \ save needle; R: ndl-l ndl-a
    _LEL-VPOP _LEL-COERCE-STR R> R>       \ ( hay-a hay-l ndl-a ndl-l )
    STR-STR-CONTAINS IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-STARTS-WITH ( -- )
    _LEL-VPOP _LEL-COERCE-STR >R >R       \ save prefix
    _LEL-VPOP _LEL-COERCE-STR R> R>       \ ( str-a str-l pfx-a pfx-l )
    STR-STARTS? IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-ENDS-WITH ( -- )
    _LEL-VPOP _LEL-COERCE-STR >R >R       \ save suffix
    _LEL-VPOP _LEL-COERCE-STR R> R>       \ ( str-a str-l sfx-a sfx-l )
    STR-ENDS? IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

\ =====================================================================
\  Type builtins (Phase 5)
\ =====================================================================

: _LEL-FN-TO-STRING ( -- )
    _LEL-VSP @ 1- 3 * CELLS _LEL-VS + @ ST-T-STRING = IF EXIT THEN
    _LEL-SPOS @ >R
    _LEL-VPOP _LEL-COERCE-STR _LEL-SAPP
    _LEL-SBUF R@ + _LEL-SPOS @ R> -
    ST-T-STRING -ROT _LEL-VPUSH ;

: _LEL-FN-TO-NUMBER ( -- )
    _LEL-VPOP _LEL-COERCE-INT
    ST-T-INTEGER SWAP 0 _LEL-VPUSH ;

: _LEL-FN-TO-BOOLEAN ( -- )
    _LEL-VPOP _LEL-TRUTHY? IF 1 ELSE 0 THEN
    ST-T-BOOLEAN SWAP 0 _LEL-VPUSH ;

: _LEL-FN-IS-NULL ( -- )
    _LEL-VPOP ROT ST-T-NULL = IF
        2DROP ST-T-BOOLEAN 1 0 _LEL-VPUSH
    ELSE
        2DROP ST-T-BOOLEAN 0 0 _LEL-VPUSH
    THEN ;

: _LEL-FN-TYPE-OF ( -- )
    _LEL-VPOP ROT
    DUP ST-T-STRING  = IF 2DROP DROP S" string"  ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    DUP ST-T-INTEGER = IF 2DROP DROP S" integer" ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    DUP ST-T-BOOLEAN = IF 2DROP DROP S" boolean" ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    DUP ST-T-NULL    = IF 2DROP DROP S" null"    ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    DUP ST-T-FLOAT   = IF 2DROP DROP S" float"   ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    DUP ST-T-ARRAY   = IF 2DROP DROP S" array"   ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
        ST-T-OBJECT  = IF 2DROP S" object"  ST-T-STRING -ROT _LEL-VPUSH EXIT THEN
    S" unknown" ST-T-STRING -ROT _LEL-VPUSH ;

\ =====================================================================
\  Function dispatch — string match against known builtins
\ =====================================================================

VARIABLE _XT-DISPATCH-EXT   0 _XT-DISPATCH-EXT !

: _LEL-DISPATCH ( name-a name-l argc -- )
    >R                                    \ save argc
    2DUP S" add"   STR-STR= IF 2DROP R> DROP _LEL-FN-ADD   EXIT THEN
    2DUP S" sub"   STR-STR= IF 2DROP R> DROP _LEL-FN-SUB   EXIT THEN
    2DUP S" mul"   STR-STR= IF 2DROP R> DROP _LEL-FN-MUL   EXIT THEN
    2DUP S" div"   STR-STR= IF 2DROP R> DROP _LEL-FN-DIV   EXIT THEN
    2DUP S" mod"   STR-STR= IF 2DROP R> DROP _LEL-FN-MOD   EXIT THEN
    2DUP S" neg"   STR-STR= IF 2DROP R> DROP _LEL-FN-NEG   EXIT THEN
    2DUP S" abs"   STR-STR= IF 2DROP R> DROP _LEL-FN-ABS   EXIT THEN
    2DUP S" round" STR-STR= IF 2DROP R> DROP _LEL-FN-ROUND EXIT THEN
    2DUP S" floor" STR-STR= IF 2DROP R> DROP _LEL-FN-FLOOR EXIT THEN
    2DUP S" ceil"  STR-STR= IF 2DROP R> DROP _LEL-FN-CEIL  EXIT THEN
    2DUP S" min"   STR-STR= IF 2DROP R> DROP _LEL-FN-MIN   EXIT THEN
    2DUP S" max"   STR-STR= IF 2DROP R> DROP _LEL-FN-MAX   EXIT THEN
    2DUP S" clamp" STR-STR= IF 2DROP R> DROP _LEL-FN-CLAMP EXIT THEN
    \ Comparison (Phase 3)
    2DUP S" eq"    STR-STR= IF 2DROP R> DROP _LEL-FN-EQ    EXIT THEN
    2DUP S" neq"   STR-STR= IF 2DROP R> DROP _LEL-FN-NEQ   EXIT THEN
    2DUP S" gt"    STR-STR= IF 2DROP R> DROP _LEL-FN-GT    EXIT THEN
    2DUP S" gte"   STR-STR= IF 2DROP R> DROP _LEL-FN-GTE   EXIT THEN
    2DUP S" lt"    STR-STR= IF 2DROP R> DROP _LEL-FN-LT    EXIT THEN
    2DUP S" lte"   STR-STR= IF 2DROP R> DROP _LEL-FN-LTE   EXIT THEN
    2DUP S" not"   STR-STR= IF 2DROP R> DROP _LEL-FN-NOT   EXIT THEN
    \ String (Phase 4)
    2DUP S" concat"      STR-STR= IF 2DROP R> _LEL-FN-CONCAT      EXIT THEN
    2DUP S" length"      STR-STR= IF 2DROP R> DROP _LEL-FN-LENGTH      EXIT THEN
    2DUP S" upper"       STR-STR= IF 2DROP R> DROP _LEL-FN-UPPER       EXIT THEN
    2DUP S" lower"       STR-STR= IF 2DROP R> DROP _LEL-FN-LOWER       EXIT THEN
    2DUP S" trim"        STR-STR= IF 2DROP R> DROP _LEL-FN-TRIM        EXIT THEN
    2DUP S" substring"   STR-STR= IF 2DROP R> DROP _LEL-FN-SUBSTRING   EXIT THEN
    2DUP S" contains"    STR-STR= IF 2DROP R> DROP _LEL-FN-CONTAINS    EXIT THEN
    2DUP S" starts-with" STR-STR= IF 2DROP R> DROP _LEL-FN-STARTS-WITH EXIT THEN
    2DUP S" ends-with"   STR-STR= IF 2DROP R> DROP _LEL-FN-ENDS-WITH   EXIT THEN
    \ Type (Phase 5)
    2DUP S" to-string"   STR-STR= IF 2DROP R> DROP _LEL-FN-TO-STRING   EXIT THEN
    2DUP S" to-number"   STR-STR= IF 2DROP R> DROP _LEL-FN-TO-NUMBER   EXIT THEN
    2DUP S" to-boolean"  STR-STR= IF 2DROP R> DROP _LEL-FN-TO-BOOLEAN  EXIT THEN
    2DUP S" is-null"     STR-STR= IF 2DROP R> DROP _LEL-FN-IS-NULL     EXIT THEN
    2DUP S" type-of"     STR-STR= IF 2DROP R> DROP _LEL-FN-TYPE-OF     EXIT THEN
    \ Extension hook — Phase 2+ builtins registered via _XT-DISPATCH-EXT
    _XT-DISPATCH-EXT @ IF
        2DUP R@
        _XT-DISPATCH-EXT @ EXECUTE
        IF 2DROP R> DROP EXIT THEN
    THEN
    \ Unknown function — pop all args, return null
    2DROP R>
    _LEL-VPOP-N
    ST-T-NULL 0 0 _LEL-VPUSH ;

\ =====================================================================
\  Function call — eager evaluation of all arguments
\ =====================================================================

: _LEL-FUNCALL ( ident-a ident-l -- )
    \ Short-circuit functions: handle before eager arg evaluation
    2DUP S" if"       STR-STR= IF 2DROP _LEL-FN-IF       EXIT THEN
    2DUP S" and"      STR-STR= IF 2DROP _LEL-FN-AND      EXIT THEN
    2DUP S" or"       STR-STR= IF 2DROP _LEL-FN-OR       EXIT THEN
    2DUP S" coalesce" STR-STR= IF 2DROP _LEL-FN-COALESCE EXIT THEN
    \ Eager evaluation for all other functions
    _LEL-NEXT                              \ consume ident -> '('
    _LEL-NEXT                              \ consume '(' -> first arg or ')'
    0                                      \ ( ident-a ident-l argc )
    _LEL-TOK @ TK-RPAREN <> IF
        BEGIN
            _LEL-EXPR
            1+
            _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
            _LEL-TOK @ TK-RPAREN =
        UNTIL
    THEN
    _LEL-NEXT                              \ consume ')'
    \ Stack: ( ident-a ident-l argc )
    _LEL-DISPATCH ;

\ =====================================================================
\  Skip expression — walk over expression without evaluating
\  (Used by short-circuit functions in later phases)
\ =====================================================================

: _LEL-SKIP-IMPL ( -- )
    _LEL-ERR @ IF EXIT THEN
    _LEL-TOK @
    DUP TK-INT = OVER TK-FLOAT = OR OVER TK-STR = OR
    OVER TK-TRUE = OR OVER TK-FALSE = OR OVER TK-NULL = OR IF
        DROP _LEL-NEXT EXIT
    THEN
    TK-IDENT = IF
        _LEL-PEEK-AHEAD 40 = IF
            \ Skip function call
            _LEL-NEXT _LEL-NEXT
            _LEL-TOK @ TK-RPAREN <> IF
                BEGIN
                    _LEL-SKIP-EXPR
                    _LEL-TOK @ TK-COMMA = IF _LEL-NEXT THEN
                    _LEL-TOK @ TK-RPAREN =
                UNTIL
            THEN
            _LEL-NEXT
        ELSE
            \ Skip state reference
            _LEL-NEXT
            BEGIN _LEL-TOK @ TK-DOT = WHILE
                _LEL-NEXT _LEL-NEXT
            REPEAT
        THEN
        EXIT
    THEN
    _LEL-NEXT ;

' _LEL-SKIP-IMPL _XT-SKIP !

\ =====================================================================
\  Expression parser — recursive descent, fused with evaluator
\ =====================================================================

: _LEL-EXPR-IMPL ( -- )
    _LEL-ERR @ IF ST-T-NULL 0 0 _LEL-VPUSH EXIT THEN
    _LEL-TOK @
    DUP TK-INT = IF
        DROP
        ST-T-INTEGER _LEL-TVAL1 @ 0 _LEL-VPUSH
        _LEL-NEXT EXIT
    THEN
    DUP TK-FLOAT = IF
        DROP
        ST-T-FLOAT _LEL-TVAL1 @ 0 _LEL-VPUSH
        _LEL-NEXT EXIT
    THEN
    DUP TK-STR = IF
        DROP
        ST-T-STRING _LEL-TVAL1 @ _LEL-TVAL2 @ _LEL-VPUSH
        _LEL-NEXT EXIT
    THEN
    DUP TK-TRUE = IF
        DROP ST-T-BOOLEAN 1 0 _LEL-VPUSH _LEL-NEXT EXIT
    THEN
    DUP TK-FALSE = IF
        DROP ST-T-BOOLEAN 0 0 _LEL-VPUSH _LEL-NEXT EXIT
    THEN
    DUP TK-NULL = IF
        DROP ST-T-NULL 0 0 _LEL-VPUSH _LEL-NEXT EXIT
    THEN
    DUP TK-IDENT = IF
        DROP
        _LEL-TVAL1 @ _LEL-TVAL2 @
        _LEL-PEEK-AHEAD 40 = IF
            _LEL-FUNCALL
        ELSE
            _LEL-STATE-OR-CTX
        THEN
        EXIT
    THEN
    DUP TK-EOF = IF
        DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT
    THEN
    \ Unknown / error token
    DROP
    1 _LEL-ERR !
    ST-T-NULL 0 0 _LEL-VPUSH ;

' _LEL-EXPR-IMPL _XT-EXPR !

\ =====================================================================
\  Public API
\ =====================================================================

: LEL-EVAL ( expr-a expr-l -- type v1 v2 )
    _LEL-SRST  _LEL-PRST
    0 _LEL-ERR !
    0 _LEL-VSP !
    _LEL-SLEN ! _LEL-SRC !
    0 _LEL-POS !
    _LEL-NEXT
    _LEL-TOK @ TK-EOF = IF
        ST-T-NULL 0 0 EXIT
    THEN
    _LEL-EXPR
    _LEL-ERR @ IF
        0 _LEL-VSP !
        ST-T-NULL 0 0 EXIT
    THEN
    _LEL-VPOP ;

: LEL-SET-CONTEXT ( item-node index -- )
    _LEL-INDEX ! _LEL-ITEM ! ;

: LEL-CLEAR-CONTEXT ( -- )
    0 _LEL-ITEM ! 0 _LEL-INDEX ! ;

\ =====================================================================
\  Phase 2.4 — literal() function (identity, argument passes through)
\ =====================================================================

\ _LEL-FN-LITERAL is a no-op: the argument is already on the value
\ stack from eager evaluation.  Dispatch entry just drops argc.

\ =====================================================================
\  Phase 2.3 — Additional string functions
\ =====================================================================

\ ----- replace(str, search, replacement) -----
VARIABLE _LEL-RPL-A   VARIABLE _LEL-RPL-L    \ replacement string
VARIABLE _LEL-SCH-A   VARIABLE _LEL-SCH-L    \ search string
VARIABLE _LEL-SRC-A   VARIABLE _LEL-SRC-L    \ source string
VARIABLE _LEL-RI                               \ scan index

: _LEL-FN-REPLACE ( -- )
    _LEL-VPOP _LEL-COERCE-STR _LEL-RPL-L ! _LEL-RPL-A !
    _LEL-VPOP _LEL-COERCE-STR _LEL-SCH-L ! _LEL-SCH-A !
    _LEL-VPOP _LEL-COERCE-STR _LEL-SRC-L ! _LEL-SRC-A !
    _LEL-SCH-L @ 0= IF
        ST-T-STRING _LEL-SRC-A @ _LEL-SRC-L @ _LEL-VPUSH EXIT
    THEN
    _LEL-SPOS @ >R
    0 _LEL-RI !
    BEGIN
        _LEL-RI @ _LEL-SRC-L @ < WHILE
        \ check if search string matches at position RI
        _LEL-SRC-L @ _LEL-RI @ - _LEL-SCH-L @ >= IF
            _LEL-SRC-A @ _LEL-RI @ + _LEL-SCH-L @
            _LEL-SCH-A @ _LEL-SCH-L @
            STR-STR= IF
                \ match — append replacement
                _LEL-RPL-A @ _LEL-RPL-L @ _LEL-SAPP
                _LEL-SCH-L @ _LEL-RI +!
            ELSE
                _LEL-SRC-A @ _LEL-RI @ + C@ _LEL-SAPP-CH
                1 _LEL-RI +!
            THEN
        ELSE
            _LEL-SRC-A @ _LEL-RI @ + C@ _LEL-SAPP-CH
            1 _LEL-RI +!
        THEN
    REPEAT
    ST-T-STRING _LEL-SBUF R@ + _LEL-SPOS @ R> - _LEL-VPUSH ;

\ ----- split(str, delim) — produces state-tree array under _scratch -----
VARIABLE _LEL-SPD-A   VARIABLE _LEL-SPD-L    \ delimiter string
VARIABLE _LEL-SPS-A   VARIABLE _LEL-SPS-L    \ source string
VARIABLE _LEL-SPI                              \ scan index
VARIABLE _LEL-SPW                              \ word start index

: _LEL-FN-SPLIT ( -- )
    _LEL-VPOP _LEL-COERCE-STR _LEL-SPD-L ! _LEL-SPD-A !
    _LEL-VPOP _LEL-COERCE-STR _LEL-SPS-L ! _LEL-SPS-A !
    \ Create scratch array _scratch.split
    S" _scratch.split" ST-ENSURE-ARRAY DROP
    \ Clear existing children (delete old entries)
    BEGIN
        S" _scratch.split" ST-ARRAY-COUNT 0>
    WHILE
        S" _scratch.split" 0 ST-ARRAY-REMOVE
    REPEAT
    _LEL-SPD-L @ 0= IF
        \ Empty delimiter — put whole string as single element
        _LEL-SPS-A @ _LEL-SPS-L @
        S" _scratch.split" ST-ARRAY-APPEND-STR
        S" _scratch.split" ST-GET-PATH DUP IF
            ST-T-ARRAY SWAP 0 _LEL-VPUSH
        ELSE
            DROP ST-T-NULL 0 0 _LEL-VPUSH
        THEN
        EXIT
    THEN
    0 _LEL-SPI !  0 _LEL-SPW !
    BEGIN
        _LEL-SPI @ _LEL-SPS-L @ < WHILE
        _LEL-SPS-L @ _LEL-SPI @ - _LEL-SPD-L @ >= IF
            _LEL-SPS-A @ _LEL-SPI @ + _LEL-SPD-L @
            _LEL-SPD-A @ _LEL-SPD-L @
            STR-STR= IF
                \ Delimiter found — append word [SPW..SPI)
                _LEL-SPS-A @ _LEL-SPW @ +
                _LEL-SPI @ _LEL-SPW @ -
                S" _scratch.split" ST-ARRAY-APPEND-STR
                _LEL-SPI @ _LEL-SPD-L @ + DUP _LEL-SPI ! _LEL-SPW !
            ELSE
                1 _LEL-SPI +!
            THEN
        ELSE
            1 _LEL-SPI +!
        THEN
    REPEAT
    \ Append final segment
    _LEL-SPS-A @ _LEL-SPW @ +
    _LEL-SPS-L @ _LEL-SPW @ -
    S" _scratch.split" ST-ARRAY-APPEND-STR
    S" _scratch.split" ST-GET-PATH DUP IF
        ST-T-ARRAY SWAP 0 _LEL-VPUSH
    ELSE
        DROP ST-T-NULL 0 0 _LEL-VPUSH
    THEN ;

\ ----- join(arr, delim) — concatenate array elements with delimiter -----
VARIABLE _LEL-JD-A   VARIABLE _LEL-JD-L      \ delimiter
VARIABLE _LEL-JARR                             \ array node
VARIABLE _LEL-JI                               \ iteration index
VARIABLE _LEL-JN                               \ child count

: _LEL-FN-JOIN ( -- )
    _LEL-VPOP _LEL-COERCE-STR _LEL-JD-L ! _LEL-JD-A !
    _LEL-VPOP ROT
    DUP ST-T-ARRAY <> IF
        2DROP DROP ST-T-STRING S" " _LEL-VPUSH EXIT
    THEN
    DROP DROP _LEL-JARR !
    _LEL-JARR @ SN.NCHILD @ _LEL-JN !
    _LEL-JN @ 0= IF
        ST-T-STRING S" " _LEL-VPUSH EXIT
    THEN
    _LEL-SPOS @ >R
    _LEL-JARR @ SN.FCHILD @
    0 _LEL-JI !
    BEGIN
        DUP 0<> WHILE
        \ Push node value onto vstack, coerce to string
        DUP _LEL-NODE-TO-VAL
        _LEL-VPOP _LEL-COERCE-STR _LEL-SAPP
        _LEL-JI @ _LEL-JN @ 1- < IF
            _LEL-JD-A @ _LEL-JD-L @ _LEL-SAPP
        THEN
        1 _LEL-JI +!
        SN.NEXT @
    REPEAT
    DROP
    ST-T-STRING _LEL-SBUF R@ + _LEL-SPOS @ R> - _LEL-VPUSH ;

\ ----- format(number, pattern) — simplified number->string -----
\ Pattern is ignored for now — just converts number to string.
\ This satisfies the spec requirement for the function to exist.

: _LEL-FN-FORMAT ( -- )
    _LEL-VPOP 2DROP DROP     \ discard pattern arg
    _LEL-VPOP
    ROT DUP ST-T-FLOAT = IF
        DROP DROP FP32>INT NUM>STR
    ELSE DUP ST-T-INTEGER = IF
        DROP DROP NUM>STR
    ELSE
        2DROP DROP S" 0"
    THEN THEN
    _LEL-SPOS @ >R _LEL-SAPP
    ST-T-STRING _LEL-SBUF R@ + _LEL-SPOS @ R> - _LEL-VPUSH ;

\ =====================================================================
\  Phase 2.2 — Array functions
\ =====================================================================

\ ----- at(arr, idx) -----
: _LEL-FN-AT ( -- )
    _LEL-VPOP _LEL-COERCE-INT              \ ( idx )
    _LEL-VPOP ROT                           \ ( v1 v2 type )
    ST-T-ARRAY <> IF DROP DROP DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT THEN
    DROP                                    \ ( arr-node idx )
    SWAP _LEL-NAV-NTH
    DUP 0= IF DROP ST-T-NULL 0 0 _LEL-VPUSH ELSE _LEL-NODE-TO-VAL THEN ;

\ ----- first(arr) -----
: _LEL-FN-FIRST ( -- )
    _LEL-VPOP ROT
    ST-T-ARRAY <> IF DROP DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT THEN
    DROP                                    \ ( arr-node )
    SN.FCHILD @
    DUP 0= IF DROP ST-T-NULL 0 0 _LEL-VPUSH ELSE _LEL-NODE-TO-VAL THEN ;

\ ----- last(arr) -----
: _LEL-FN-LAST ( -- )
    _LEL-VPOP ROT
    ST-T-ARRAY <> IF DROP DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT THEN
    DROP                                    \ ( arr-node )
    SN.LCHILD @
    DUP 0= IF DROP ST-T-NULL 0 0 _LEL-VPUSH ELSE _LEL-NODE-TO-VAL THEN ;

\ ----- includes(arr, val) — linear scan, type-aware compare -----
VARIABLE _LEL-INC-T   VARIABLE _LEL-INC-V1  VARIABLE _LEL-INC-V2

: _LEL-FN-INCLUDES ( -- )
    _LEL-VPOP _LEL-INC-V2 ! _LEL-INC-V1 ! _LEL-INC-T !
    _LEL-VPOP ROT
    ST-T-ARRAY <> IF DROP DROP ST-T-BOOLEAN 0 0 _LEL-VPUSH EXIT THEN
    DROP SN.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP _LEL-NODE-TO-VAL
        \ Push search value, call eq
        _LEL-INC-T @ _LEL-INC-V1 @ _LEL-INC-V2 @ _LEL-VPUSH
        _LEL-FN-EQ
        _LEL-VPOP _LEL-COERCE-INT IF
            DROP ST-T-BOOLEAN 1 0 _LEL-VPUSH EXIT
        THEN
        SN.NEXT @
    REPEAT
    DROP ST-T-BOOLEAN 0 0 _LEL-VPUSH ;

\ ----- reverse(arr) — returns new scratch array -----
VARIABLE _LEL-REV-N

: _LEL-FN-REVERSE ( -- )
    _LEL-VPOP ROT
    ST-T-ARRAY <> IF DROP DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT THEN
    DROP
    DUP SN.NCHILD @ _LEL-REV-N !
    S" _scratch.reverse" ST-ENSURE-ARRAY DROP
    BEGIN S" _scratch.reverse" ST-ARRAY-COUNT 0> WHILE
        S" _scratch.reverse" 0 ST-ARRAY-REMOVE
    REPEAT
    \ Walk from last child backward
    SN.LCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP _LEL-NODE-TO-VAL
        _LEL-VPOP ROT
        DUP ST-T-STRING = IF
            DROP S" _scratch.reverse" ST-ARRAY-APPEND-STR
        ELSE DUP ST-T-INTEGER = IF
            DROP DROP S" _scratch.reverse" ST-ARRAY-APPEND-INT
        ELSE
            2DROP DROP
        THEN THEN
        SN.PREV @
    REPEAT
    DROP
    S" _scratch.reverse" ST-GET-PATH DUP IF
        ST-T-ARRAY SWAP 0 _LEL-VPUSH
    ELSE DROP ST-T-NULL 0 0 _LEL-VPUSH THEN ;

\ ----- length(arr) — already handled by _LEL-FN-LENGTH -----
\ (it checks for ST-T-ARRAY and returns SN.NCHILD)

\ =====================================================================
\  Phase 2.1 — Infix operator parser (Pratt parser)
\ =====================================================================

\ Binding powers for each precedence level (higher = tighter binding)
\ or: 2, and: 4, eq/ne: 6, cmp: 8, add/sub: 10, mul/div/mod: 12, unary: 14

\ _LEL-INFIX-BP — return left binding power for the current token.
\ Returns 0 if not an infix operator (stops PRATT loop).

VARIABLE _LEL-IBP     \ infix binding power result

: _LEL-INFIX-BP ( -- bp )
    _LEL-TOK @
    DUP TK-PLUS    = IF DROP 10 EXIT THEN
    DUP TK-MINUS   = IF DROP 10 EXIT THEN
    DUP TK-STAR    = IF DROP 12 EXIT THEN
    DUP TK-SLASH   = IF DROP 12 EXIT THEN
    DUP TK-PERCENT = IF DROP 12 EXIT THEN
    DUP TK-EQEQ   = IF DROP  6 EXIT THEN
    DUP TK-BANGEQ  = IF DROP  6 EXIT THEN
    DUP TK-GT      = IF DROP  8 EXIT THEN
    DUP TK-GE      = IF DROP  8 EXIT THEN
    DUP TK-LT      = IF DROP  8 EXIT THEN
    DUP TK-LE      = IF DROP  8 EXIT THEN
    DUP TK-QUESTION = IF DROP  1 EXIT THEN  \ ternary ? : (lowest)
    DUP TK-IDENT = IF
        DROP
        _LEL-TVAL1 @ _LEL-TVAL2 @
        2DUP S" and" STR-STR= IF 2DROP 4 EXIT THEN
        2DUP S" or"  STR-STR= IF 2DROP 2 EXIT THEN
        2DROP 0 EXIT
    THEN
    DROP 0 ;

\ Forward-declare the Pratt entry (mutual recursion with NUD/LED)
VARIABLE _XT-PRATT

: _LEL-PRATT-CALL ( min-bp -- )
    _XT-PRATT @ EXECUTE ;

\ ----- NUD (null denotation) — prefix / atoms -----
\ Handles: literals, identifiers/function calls, parenthesized exprs,
\ unary minus, unary not.

: _LEL-NUD ( -- )
    _LEL-TOK @
    DUP TK-INT = IF
        DROP ST-T-INTEGER _LEL-TVAL1 @ 0 _LEL-VPUSH
        _LEL-NEXT EXIT
    THEN
    DUP TK-FLOAT = IF
        DROP ST-T-FLOAT _LEL-TVAL1 @ 0 _LEL-VPUSH
        _LEL-NEXT EXIT
    THEN
    DUP TK-STR = IF
        DROP ST-T-STRING _LEL-TVAL1 @ _LEL-TVAL2 @ _LEL-VPUSH
        _LEL-NEXT EXIT
    THEN
    DUP TK-TRUE = IF
        DROP ST-T-BOOLEAN 1 0 _LEL-VPUSH _LEL-NEXT EXIT
    THEN
    DUP TK-FALSE = IF
        DROP ST-T-BOOLEAN 0 0 _LEL-VPUSH _LEL-NEXT EXIT
    THEN
    DUP TK-NULL = IF
        DROP ST-T-NULL 0 0 _LEL-VPUSH _LEL-NEXT EXIT
    THEN
    DUP TK-MINUS = IF
        \ Unary minus — parse operand at high bp, negate
        DROP _LEL-NEXT
        14 _LEL-PRATT-CALL
        _LEL-FN-NEG EXIT
    THEN
    DUP TK-LPAREN = IF
        \ Parenthesized expression
        DROP _LEL-NEXT
        0 _LEL-PRATT-CALL
        \ Expect TK-RPAREN
        _LEL-TOK @ TK-RPAREN = IF _LEL-NEXT THEN
        EXIT
    THEN
    DUP TK-IDENT = IF
        DROP
        _LEL-TVAL1 @ _LEL-TVAL2 @
        \ Check for 'not' keyword (prefix operator)
        2DUP S" not" STR-STR= IF
            _LEL-PEEK-AHEAD 40 <> IF
                \ not as prefix operator (not followed by lparen)
                2DROP _LEL-NEXT
                14 _LEL-PRATT-CALL
                _LEL-FN-NOT EXIT
            THEN
        THEN
        \ Function call or state reference (same as old _LEL-EXPR-IMPL)
        _LEL-PEEK-AHEAD 40 = IF
            _LEL-FUNCALL
        ELSE
            _LEL-STATE-OR-CTX
        THEN
        EXIT
    THEN
    DUP TK-EOF = IF
        DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT
    THEN
    \ Unknown token
    DROP 1 _LEL-ERR !
    ST-T-NULL 0 0 _LEL-VPUSH ;

\ ----- LED (left denotation) — infix operators -----
\ Left operand is already on vstack.  Consume operator, parse right
\ operand at the appropriate binding power, then apply the operator.

VARIABLE _LEL-LED-TOK   \ save operator token

: _LEL-LED ( -- )
    _LEL-TOK @ _LEL-LED-TOK !
    _LEL-LED-TOK @
    \ ---- ternary ? : ----
    DUP TK-QUESTION = IF
        DROP _LEL-NEXT                    \ consume ?
        _LEL-VPOP _LEL-TRUTHY? IF
            0 _LEL-PRATT-CALL             \ evaluate then-expr
            _LEL-TOK @ TK-COLON = IF _LEL-NEXT THEN
            \ skip else-expr: evaluate and discard
            0 _LEL-PRATT-CALL
            _LEL-VPOP 2DROP DROP
        ELSE
            \ skip then-expr: evaluate and discard
            0 _LEL-PRATT-CALL
            _LEL-VPOP 2DROP DROP
            _LEL-TOK @ TK-COLON = IF _LEL-NEXT THEN
            0 _LEL-PRATT-CALL
        THEN
        EXIT
    THEN
    \ ---- short-circuit and/or ----
    DUP TK-IDENT = IF
        DROP
        _LEL-TVAL1 @ _LEL-TVAL2 @
        2DUP S" and" STR-STR= IF
            2DROP _LEL-NEXT
            \ left is on vstack
            _LEL-VSP @ 1- _LEL-VIDX _LEL-TRUTHY? IF
                _LEL-VPOP 2DROP DROP     \ discard truthy left
                4 _LEL-PRATT-CALL       \ evaluate right, keep it
            ELSE
                \ left is falsy — skip right, keep left
                4 _LEL-PRATT-CALL
                _LEL-VPOP 2DROP DROP     \ discard right
            THEN
            EXIT
        THEN
        2DUP S" or" STR-STR= IF
            2DROP _LEL-NEXT
            _LEL-VSP @ 1- _LEL-VIDX _LEL-TRUTHY? IF
                \ left is truthy — skip right, keep left
                2 _LEL-PRATT-CALL
                _LEL-VPOP 2DROP DROP     \ discard right
            ELSE
                _LEL-VPOP 2DROP DROP     \ discard falsy left
                2 _LEL-PRATT-CALL       \ evaluate right, keep it
            THEN
            EXIT
        THEN
        2DROP EXIT   \ shouldn't reach here
    THEN
    \ ---- binary operators ----
    DROP _LEL-NEXT                        \ consume operator token
    \ Parse right operand at this operator's binding power
    \ (left-assoc: same bp; right-assoc would be bp-1)
    _LEL-LED-TOK @
    DUP TK-PLUS    = IF DROP 10 _LEL-PRATT-CALL _LEL-FN-ADD   EXIT THEN
    DUP TK-MINUS   = IF DROP 10 _LEL-PRATT-CALL _LEL-FN-SUB   EXIT THEN
    DUP TK-STAR    = IF DROP 12 _LEL-PRATT-CALL _LEL-FN-MUL   EXIT THEN
    DUP TK-SLASH   = IF DROP 12 _LEL-PRATT-CALL _LEL-FN-DIV   EXIT THEN
    DUP TK-PERCENT = IF DROP 12 _LEL-PRATT-CALL _LEL-FN-MOD   EXIT THEN
    DUP TK-EQEQ   = IF DROP  6 _LEL-PRATT-CALL _LEL-FN-EQ    EXIT THEN
    DUP TK-BANGEQ  = IF DROP  6 _LEL-PRATT-CALL _LEL-FN-NEQ   EXIT THEN
    DUP TK-GT      = IF DROP  8 _LEL-PRATT-CALL _LEL-FN-GT    EXIT THEN
    DUP TK-GE      = IF DROP  8 _LEL-PRATT-CALL _LEL-FN-GTE   EXIT THEN
    DUP TK-LT      = IF DROP  8 _LEL-PRATT-CALL _LEL-FN-LT    EXIT THEN
    DUP TK-LE      = IF DROP  8 _LEL-PRATT-CALL _LEL-FN-LTE   EXIT THEN
    DROP ;

\ ----- Main Pratt loop -----
\ ( min-bp -- )
\ Parses expression with minimum binding power.

: _LEL-PRATT-IMPL ( min-bp -- )
    _LEL-ERR @ IF DROP ST-T-NULL 0 0 _LEL-VPUSH EXIT THEN
    >R
    _LEL-NUD
    BEGIN
        _LEL-ERR @ 0= IF
            _LEL-INFIX-BP DUP R@ > IF
                DROP _LEL-LED
                TRUE
            ELSE
                DROP FALSE
            THEN
        ELSE
            FALSE
        THEN
    WHILE REPEAT
    R> DROP ;

' _LEL-PRATT-IMPL _XT-PRATT !

\ ----- Wire Pratt parser as the expression entry point -----
\ Replace _LEL-EXPR-IMPL with a Pratt entry at binding power 0.

: _LEL-EXPR-PRATT ( -- )
    0 _LEL-PRATT-IMPL ;

' _LEL-EXPR-PRATT _XT-EXPR !

\ ----- Update skip to handle infix operators -----
\ For the Pratt parser world, skip = evaluate and discard.

: _LEL-SKIP-PRATT ( -- )
    _LEL-EXPR
    _LEL-VPOP 2DROP DROP ;

' _LEL-SKIP-PRATT _XT-SKIP !

\ =====================================================================
\  Extension dispatch — hook for Phase 2+ builtins
\ =====================================================================
\ Called by the hook in _LEL-DISPATCH with ( name-a name-l argc -- flag ).
\ Returns TRUE if the function was handled, FALSE otherwise.

: _LEL-DISPATCH-EXT ( name-a name-l argc -- flag )
    DROP                                  \ argc not needed — each fn knows arity
    \ Phase 2.4
    2DUP S" literal"  STR-STR= IF 2DROP TRUE EXIT THEN
    \ Phase 2.3
    2DUP S" replace"  STR-STR= IF 2DROP _LEL-FN-REPLACE TRUE EXIT THEN
    2DUP S" split"    STR-STR= IF 2DROP _LEL-FN-SPLIT   TRUE EXIT THEN
    2DUP S" join"     STR-STR= IF 2DROP _LEL-FN-JOIN     TRUE EXIT THEN
    2DUP S" format"   STR-STR= IF 2DROP _LEL-FN-FORMAT   TRUE EXIT THEN
    \ Phase 2.2
    2DUP S" at"       STR-STR= IF 2DROP _LEL-FN-AT       TRUE EXIT THEN
    2DUP S" first"    STR-STR= IF 2DROP _LEL-FN-FIRST    TRUE EXIT THEN
    2DUP S" last"     STR-STR= IF 2DROP _LEL-FN-LAST     TRUE EXIT THEN
    2DUP S" includes" STR-STR= IF 2DROP _LEL-FN-INCLUDES  TRUE EXIT THEN
    2DUP S" reverse"  STR-STR= IF 2DROP _LEL-FN-REVERSE   TRUE EXIT THEN
    \ Not handled
    2DROP FALSE ;

' _LEL-DISPATCH-EXT _XT-DISPATCH-EXT !

\ =====================================================================
\  Phase 2.5 — Computed value linkage
\ =====================================================================

: _ST-LEL-COMPUTE ( expr-a expr-l -- type v1 v2 )
    LEL-EVAL ;

' _ST-LEL-COMPUTE _ST-COMPUTE-XT !
