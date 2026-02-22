\ css.f — CSS parser for KDOS Forth
\
\ Standalone CSS parser: tokenization, declaration parsing,
\ rule iteration, selector parsing, matching, specificity.
\ Same (addr len) cursor model as json.f and markup/core.f.
\
\ Prefix: CSS-   (public API)
\         _CSS-  (internal helpers)
\
\ Load with:   REQUIRE css.f

PROVIDED akashic-css

\ =====================================================================
\  Utility — may already exist; safe to redefine
\ =====================================================================

: /STRING  ( addr len n -- addr+n len-n )
    ROT OVER + -ROT - ;

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE CSS-ERR
VARIABLE CSS-ABORT-ON-ERROR
0 CSS-ERR !
0 CSS-ABORT-ON-ERROR !

1 CONSTANT CSS-E-NOT-FOUND
2 CONSTANT CSS-E-MALFORMED
3 CONSTANT CSS-E-UNTERMINATED
4 CONSTANT CSS-E-UNEXPECTED
5 CONSTANT CSS-E-OVERFLOW

: CSS-FAIL  ( err-code -- )
    CSS-ERR !
    CSS-ABORT-ON-ERROR @ IF ABORT" CSS error" THEN ;

: CSS-OK?  ( -- flag )
    CSS-ERR @ 0= ;

: CSS-CLEAR-ERR  ( -- )
    0 CSS-ERR ! ;

\ =====================================================================
\  String comparison helpers
\ =====================================================================

: _CSS-TOLOWER  ( c -- c' )
    DUP 65 >= OVER 90 <= AND IF 32 + THEN ;

: _CSS-STRI=  ( s1 l1 s2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 DO
        OVER I + C@ _CSS-TOLOWER
        OVER I + C@ _CSS-TOLOWER
        <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _CSS-STR=  ( s1 l1 s2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 DO
        OVER I + C@  OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ =====================================================================
\  Layer 0 — Scanning Primitives
\ =====================================================================

\ _CSS-WS? ( c -- flag )
\   Is this character CSS whitespace?
: _CSS-WS?  ( c -- flag )
    DUP 32 =
    OVER  9 = OR
    OVER 10 = OR
    SWAP 13 = OR ;

\ CSS-SKIP-COMMENT ( addr len -- addr' len' )
\   Skip one /* ... */ block comment.
\   Cursor must be at '/'.  If next char is not '*', does nothing.
VARIABLE _CSC-A

: CSS-SKIP-COMMENT  ( addr len -- addr' len' )
    DUP 2 < IF EXIT THEN
    OVER _CSC-A !
    _CSC-A @ C@ 47 <>  IF EXIT THEN        \ not '/'
    _CSC-A @ 1+ C@ 42 <> IF EXIT THEN      \ not '*'
    2 /STRING                                \ skip '/*'
    BEGIN
        DUP 0> WHILE
        DUP 2 >= IF
            OVER _CSC-A !
            _CSC-A @    C@ 42 =              \ '*'
            _CSC-A @ 1+ C@ 47 = AND          \ '/'
            IF 2 /STRING EXIT THEN
        THEN
        1 /STRING
    REPEAT ;

\ CSS-SKIP-WS ( addr len -- addr' len' )
\   Skip CSS whitespace AND /* ... */ comments.
VARIABLE _CSW-A

: CSS-SKIP-WS  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ _CSS-WS? IF
            1 /STRING
        ELSE
            \ check for /* comment
            DUP 2 >= IF
                OVER _CSW-A !
                _CSW-A @    C@ 47 =          \ '/'
                _CSW-A @ 1+ C@ 42 = AND      \ '*'
                IF
                    CSS-SKIP-COMMENT
                ELSE
                    EXIT
                THEN
            ELSE
                EXIT
            THEN
        THEN
    REPEAT ;

\ CSS-SKIP-STRING ( addr len -- addr' len' )
\   Skip a quoted string: "..." or '...'.
\   Handles backslash escapes.
\   Cursor must be at the opening quote character.
: CSS-SKIP-STRING  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ DUP 34 = SWAP 39 = OR 0= IF EXIT THEN  \ not " or '
    OVER C@ >R                       \ save quote char
    1 /STRING                        \ skip opening quote
    BEGIN
        DUP 0> WHILE
        OVER C@ R@ = IF             \ closing quote
            R> DROP
            1 /STRING EXIT
        THEN
        OVER C@ 92 = IF             \ backslash escape
            DUP 2 >= IF
                2 /STRING            \ skip \ + next char
            ELSE
                1 /STRING
            THEN
        ELSE
            1 /STRING
        THEN
    REPEAT
    R> DROP ;                        \ unterminated string

\ _CSS-IDENT-CHAR? ( c -- flag )
\   Is this a CSS identifier character?
\   Letters, digits, hyphen, underscore, non-ASCII (>127).
: _CSS-IDENT-CHAR?  ( c -- flag )
    DUP 65 >= OVER 90  <= AND IF DROP -1 EXIT THEN   \ A-Z
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN   \ a-z
    DUP 48 >= OVER 57  <= AND IF DROP -1 EXIT THEN   \ 0-9
    DUP 45 = IF DROP -1 EXIT THEN                    \ -
    DUP 95 = IF DROP -1 EXIT THEN                    \ _
    127 > IF -1 EXIT THEN                            \ non-ASCII
    0 ;

\ _CSS-IDENT-START? ( c -- flag )
\   Can this character start an identifier?
\   Same as ident-char but no digit and no leading hyphen-digit.
: _CSS-IDENT-START?  ( c -- flag )
    DUP 65 >= OVER 90  <= AND IF DROP -1 EXIT THEN
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 95 = IF DROP -1 EXIT THEN                    \ _
    DUP 45 = IF DROP -1 EXIT THEN                    \ - (CSS allows leading -)
    127 > IF -1 EXIT THEN
    0 ;

\ CSS-SKIP-IDENT ( addr len -- addr' len' )
\   Skip a CSS identifier.
: CSS-SKIP-IDENT  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ _CSS-IDENT-START? 0= IF EXIT THEN
    \ skip leading - if present, then check next
    OVER C@ 45 = IF
        1 /STRING
        DUP 0> 0= IF EXIT THEN
    THEN
    BEGIN
        DUP 0> WHILE
        OVER C@ _CSS-IDENT-CHAR?
        0= IF EXIT THEN
        \ handle backslash escapes in identifiers
        OVER C@ 92 = IF
            DUP 2 >= IF
                2 /STRING
            ELSE
                EXIT
            THEN
        ELSE
            1 /STRING
        THEN
    REPEAT ;

\ CSS-GET-IDENT ( addr len -- addr' len' name-a name-u )
\   Extract identifier string.
: CSS-GET-IDENT  ( addr len -- addr' len' name-a name-u )
    OVER >R
    CSS-SKIP-IDENT
    OVER R> TUCK - ;

\ CSS-SKIP-BLOCK ( addr len -- addr' len' )
\   Skip a balanced { ... } block.
\   Cursor must be at '{'.
\   Respects nested blocks, strings, and comments.
VARIABLE _CSB-D

: CSS-SKIP-BLOCK  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 123 <> IF EXIT THEN     \ not '{'
    1 _CSB-D !
    1 /STRING                        \ skip '{'
    BEGIN
        _CSB-D @ 0> WHILE
        DUP 0> 0= IF EXIT THEN
        OVER C@
        DUP 123 = IF                 \ '{'
            DROP 1 _CSB-D +!
            1 /STRING
        ELSE DUP 125 = IF           \ '}'
            DROP -1 _CSB-D +!
            _CSB-D @ 0> IF 1 /STRING THEN
        ELSE DUP 34 = OVER 39 = OR IF  \ string
            DROP CSS-SKIP-STRING
        ELSE DUP 47 = IF            \ possible comment
            DROP
            DUP 2 >= IF
                OVER 1+ C@ 42 = IF  \ '/*'
                    CSS-SKIP-COMMENT
                ELSE
                    1 /STRING
                THEN
            ELSE
                1 /STRING
            THEN
        ELSE
            DROP 1 /STRING
        THEN THEN THEN THEN
    REPEAT
    \ skip closing '}'
    DUP 0> IF 1 /STRING THEN ;

\ CSS-SKIP-PARENS ( addr len -- addr' len' )
\   Skip a balanced ( ... ) group.
\   Cursor must be at '('.
VARIABLE _CSP-D

: CSS-SKIP-PARENS  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 40 <> IF EXIT THEN      \ not '('
    1 _CSP-D !
    1 /STRING                        \ skip '('
    BEGIN
        _CSP-D @ 0> WHILE
        DUP 0> 0= IF EXIT THEN
        OVER C@
        DUP 40 = IF                  \ '('
            DROP 1 _CSP-D +!
            1 /STRING
        ELSE DUP 41 = IF            \ ')'
            DROP -1 _CSP-D +!
            _CSP-D @ 0> IF 1 /STRING THEN
        ELSE DUP 34 = OVER 39 = OR IF
            DROP CSS-SKIP-STRING
        ELSE DUP 47 = IF
            DROP
            DUP 2 >= IF
                OVER 1+ C@ 42 = IF
                    CSS-SKIP-COMMENT
                ELSE
                    1 /STRING
                THEN
            ELSE
                1 /STRING
            THEN
        ELSE
            DROP 1 /STRING
        THEN THEN THEN THEN
    REPEAT
    DUP 0> IF 1 /STRING THEN ;

\ CSS-SKIP-UNTIL ( addr len char -- addr' len' )
\   Skip forward until char is found, respecting strings,
\   comments, and balanced blocks/parens.
: CSS-SKIP-UNTIL  ( addr len char -- addr' len' )
    >R
    BEGIN
        DUP 0> WHILE
        OVER C@ R@ = IF R> DROP EXIT THEN
        OVER C@
        DUP 34 = OVER 39 = OR IF
            DROP CSS-SKIP-STRING
        ELSE DUP 123 = IF
            DROP CSS-SKIP-BLOCK
        ELSE DUP 40 = IF
            DROP CSS-SKIP-PARENS
        ELSE DUP 47 = IF
            DROP
            DUP 2 >= IF
                OVER 1+ C@ 42 = IF
                    CSS-SKIP-COMMENT
                ELSE
                    1 /STRING
                THEN
            ELSE
                1 /STRING
            THEN
        ELSE
            DROP 1 /STRING
        THEN THEN THEN THEN
    REPEAT
    R> DROP ;

\ =====================================================================
\  Layer 1 — Declaration Parsing
\ =====================================================================
\
\ Parse property: value; pairs inside a { } block.
\ Cursor should be INSIDE the block (past '{').

\ _CSS-TRIM-END ( addr len -- addr len' )
\   Remove trailing whitespace from a string.
: _CSS-TRIM-END  ( addr len -- addr len' )
    BEGIN
        DUP 0> WHILE
        OVER OVER + 1- C@ _CSS-WS?
        0= IF EXIT THEN
        1-
    REPEAT ;

\ CSS-DECL-NEXT ( a u -- a' u' prop-a prop-u val-a val-u flag )
\   Iterate declarations in a { } block.
\   Cursor inside the block (past '{').
\   Returns: advanced cursor, property name, value string, flag.
\   Flag = -1 if a declaration was found, 0 if end of block.
\   Value is everything between ':' and ';' (whitespace-trimmed).
\   Skips empty declarations (bare semicolons).
VARIABLE _CDN-PA   VARIABLE _CDN-PL   \ property
VARIABLE _CDN-VA   VARIABLE _CDN-VL   \ value

: CSS-DECL-NEXT  ( a u -- a' u' prop-a prop-u val-a val-u flag )
    CSS-SKIP-WS
    \ end of block?
    DUP 0= IF 0 0 0 0 0 EXIT THEN
    OVER C@ 125 = IF                 \ '}'
        0 0 0 0 0 EXIT
    THEN
    \ skip bare semicolons
    OVER C@ 59 = IF                  \ ';'
        1 /STRING RECURSE EXIT
    THEN
    \ extract property name
    CSS-GET-IDENT
    _CDN-PL !  _CDN-PA !
    \ skip to ':'
    CSS-SKIP-WS
    DUP 0> IF
        OVER C@ 58 = IF             \ ':'
            1 /STRING                \ skip ':'
        ELSE
            \ malformed — skip to ; or }
            BEGIN
                DUP 0> WHILE
                OVER C@ DUP 59 = SWAP 125 = OR IF
                    OVER C@ 59 = IF 1 /STRING THEN
                    _CDN-PA @ _CDN-PL @
                    0 0 -1 EXIT      \ return prop with empty value
                THEN
                1 /STRING
            REPEAT
            _CDN-PA @ _CDN-PL @ 0 0 -1 EXIT
        THEN
    THEN
    \ extract value: everything until ';' or '}'
    CSS-SKIP-WS
    OVER _CDN-VA !
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 59 = SWAP 125 = OR IF
            \ compute value length
            OVER _CDN-VA @ -  _CDN-VL !
            \ skip ';' if present
            OVER C@ 59 = IF 1 /STRING THEN
            _CDN-PA @ _CDN-PL @
            _CDN-VA @ _CDN-VL @ _CSS-TRIM-END
            -1 EXIT
        THEN
        OVER C@
        DUP 34 = OVER 39 = OR IF
            DROP CSS-SKIP-STRING
        ELSE DUP 40 = IF
            DROP CSS-SKIP-PARENS
        ELSE
            DROP 1 /STRING
        THEN THEN
    REPEAT
    \ end of input — return what we have
    OVER _CDN-VA @ -  _CDN-VL !
    _CDN-PA @ _CDN-PL @
    _CDN-VA @ _CDN-VL @ _CSS-TRIM-END
    -1 ;

\ CSS-DECL-FIND ( a u prop-a prop-u -- val-a val-u flag )
\   Find a specific property in a declaration block.
\   Cursor inside the block (past '{').
\   Case-insensitive property match.
VARIABLE _CDF-SA   VARIABLE _CDF-SL

: CSS-DECL-FIND  ( a u prop-a prop-u -- val-a val-u flag )
    _CDF-SL !  _CDF-SA !
    BEGIN
        CSS-DECL-NEXT                \ ( a' u' pa pu va vu flag )
        DUP 0= IF                   \ no more decls
            >R 2DROP 2DROP 2DROP R>
            0 0 ROT EXIT             \ ( 0 0 0 )
        THEN
        DROP                         \ drop flag
        2>R                          \ save val  R: va vu
        _CDF-SA @ _CDF-SL @ _CSS-STRI=
        IF
            2DROP                    \ drop cursor
            2R> -1 EXIT              \ ( va vu -1 )
        THEN
        2R> 2DROP                    \ discard val, continue
    AGAIN ;

\ CSS-DECL-HAS? ( a u prop-a prop-u -- flag )
\   Does this block declare the given property?
: CSS-DECL-HAS?  ( a u prop-a prop-u -- flag )
    CSS-DECL-FIND
    >R 2DROP R> ;

\ CSS-IMPORTANT? ( val-a val-u -- flag )
\   Does this value end with !important?
\   Checks for "!important" at end (after trimming whitespace).
VARIABLE _CIP-A

: CSS-IMPORTANT?  ( val-a val-u -- flag )
    _CSS-TRIM-END
    DUP 10 < IF 2DROP 0 EXIT THEN   \ too short
    \ look at last 10 chars for "!important"
    OVER OVER + 10 - _CIP-A !
    _CIP-A @    C@ 33  =            \ !
    _CIP-A @ 1+ C@ _CSS-TOLOWER 105 = AND   \ i
    _CIP-A @ 2 + C@ _CSS-TOLOWER 109 = AND  \ m
    _CIP-A @ 3 + C@ _CSS-TOLOWER 112 = AND  \ p
    _CIP-A @ 4 + C@ _CSS-TOLOWER 111 = AND  \ o
    _CIP-A @ 5 + C@ _CSS-TOLOWER 114 = AND  \ r
    _CIP-A @ 6 + C@ _CSS-TOLOWER 116 = AND  \ t
    _CIP-A @ 7 + C@ _CSS-TOLOWER  97 = AND  \ a
    _CIP-A @ 8 + C@ _CSS-TOLOWER 110 = AND  \ n
    _CIP-A @ 9 + C@ _CSS-TOLOWER 116 = AND  \ t
    IF 2DROP -1 EXIT THEN
    2DROP 0 ;

\ CSS-STRIP-IMPORTANT ( val-a val-u -- val-a' val-u' )
\   Remove trailing !important from a value string.
\   If !important is not present, returns unchanged.
: CSS-STRIP-IMPORTANT  ( val-a val-u -- val-a' val-u' )
    2DUP CSS-IMPORTANT? 0= IF EXIT THEN
    \ remove last 10 chars and trim trailing whitespace
    10 -
    _CSS-TRIM-END ;

