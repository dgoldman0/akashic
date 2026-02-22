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

\ =====================================================================
\  Layer 2 — Rule Iteration
\ =====================================================================
\
\ Iterate top-level rules in a stylesheet.
\ CSS-RULE-NEXT returns selector + body for each rule.
\ @-rules are skipped by default; dedicated words handle them.

\ CSS-AT-RULE? ( a u -- flag )
\   Is cursor at an @-rule (starts with '@')?
: CSS-AT-RULE?  ( a u -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DROP C@ 64 = ;                   \ '@'

\ CSS-AT-RULE-NAME ( a u -- a' u' name-a name-u )
\   Extract the @-rule name.  Cursor must be at '@'.
\   Returns cursor past the name and the name string.
: CSS-AT-RULE-NAME  ( a u -- a' u' name-a name-u )
    DUP 0= IF 0 0 EXIT THEN
    OVER C@ 64 <> IF 0 0 EXIT THEN  \ not '@'
    1 /STRING                         \ skip '@'
    CSS-GET-IDENT ;

\ CSS-SKIP-AT-RULE ( a u -- a' u' )
\   Skip one @-rule entirely.
\   Block @-rules (@media, @keyframes): skip to closing '}'.
\   Statement @-rules (@import, @charset): skip to ';'.
VARIABLE _CSAR-A

: CSS-SKIP-AT-RULE  ( a u -- a' u' )
    DUP 0= IF EXIT THEN
    OVER C@ 64 <> IF EXIT THEN      \ not '@'
    1 /STRING                         \ skip '@'
    CSS-SKIP-IDENT                    \ skip rule name
    \ scan for '{' or ';', whichever comes first
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 123 = IF        \ '{' — block @-rule
            DROP CSS-SKIP-BLOCK EXIT
        THEN
        DUP 59 = IF                  \ ';' — statement @-rule
            DROP 1 /STRING EXIT
        THEN
        DUP 34 = OVER 39 = OR IF    \ string
            DROP CSS-SKIP-STRING
        ELSE DUP 40 = IF            \ parens
            DROP CSS-SKIP-PARENS
        ELSE DUP 47 = IF            \ possible comment
            DROP
            DUP 2 >= IF
                OVER _CSAR-A !
                _CSAR-A @    C@ 47 =
                _CSAR-A @ 1+ C@ 42 = AND
                IF CSS-SKIP-COMMENT
                ELSE 1 /STRING THEN
            ELSE 1 /STRING THEN
        ELSE
            DROP 1 /STRING
        THEN THEN THEN
    REPEAT ;

\ CSS-RULE-NEXT ( a u -- a' u' sel-a sel-u body-a body-u flag )
\   Get next rule from a stylesheet.
\   Returns: advanced cursor, selector string (trimmed),
\   body (inner content of { } block, no braces), flag.
\   Flag = -1 found, 0 end of stylesheet.
\   Skips @-rules automatically.
VARIABLE _CRN-SA                     \ selector start
VARIABLE _CRN-SL                     \ selector length
VARIABLE _CRN-BA                     \ body start
VARIABLE _CRN-BL                     \ body length
VARIABLE _CRN-D                      \ depth counter

: CSS-RULE-NEXT  ( a u -- a' u' sel-a sel-u body-a body-u flag )
    CSS-SKIP-WS
    DUP 0= IF 0 0 0 0 0 EXIT THEN
    \ skip @-rules
    OVER C@ 64 = IF                  \ '@'
        CSS-SKIP-AT-RULE RECURSE EXIT
    THEN
    \ save selector start
    OVER _CRN-SA !
    \ find '{' — skip strings, comments, parens in selector
    BEGIN
        DUP 0> WHILE
        OVER C@ 123 = IF            \ '{' found
            \ compute selector length
            OVER _CRN-SA @ -  _CRN-SL !
            \ body starts after '{'
            1 /STRING
            OVER _CRN-BA !
            \ find matching '}' using depth counter
            1 _CRN-D !
            BEGIN
                _CRN-D @ 0> WHILE
                DUP 0> 0= IF        \ unterminated block
                    OVER _CRN-BA @ -  _CRN-BL !
                    _CRN-SA @ _CRN-SL @ _CSS-TRIM-END
                    _CRN-BA @ _CRN-BL @
                    -1 EXIT
                THEN
                OVER C@
                DUP 123 = IF        \ nested '{'
                    DROP 1 _CRN-D +!
                    1 /STRING
                ELSE DUP 125 = IF   \ '}'
                    DROP -1 _CRN-D +!
                    _CRN-D @ 0= IF  \ matching close
                        OVER _CRN-BA @ -  _CRN-BL !
                        1 /STRING    \ skip '}'
                        _CRN-SA @ _CRN-SL @ _CSS-TRIM-END
                        _CRN-BA @ _CRN-BL @
                        -1 EXIT
                    THEN
                    1 /STRING
                ELSE DUP 34 = OVER 39 = OR IF
                    DROP CSS-SKIP-STRING
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
                THEN THEN THEN THEN THEN
            REPEAT
            \ shouldn't reach here, but safety return
            _CRN-SA @ _CRN-SL @ _CSS-TRIM-END
            _CRN-BA @ _CRN-BL @
            -1 EXIT
        THEN
        \ skip non-brace content in selector
        OVER C@
        DUP 34 = OVER 39 = OR IF
            DROP CSS-SKIP-STRING
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
        THEN THEN THEN
    REPEAT
    \ no '{' found
    0 0 0 0 0 ;

\ =====================================================================
\  Layer 3 — Selector Parsing
\ =====================================================================
\
\ Parse and tokenize CSS selectors.
\ CSS-SEL-NEXT-SIMPLE parses one simple selector component.
\ CSS-SEL-COMBINATOR parses a combinator between compound selectors.
\ CSS-SEL-GROUP-NEXT iterates comma-separated selector groups.

\ Component type constants
1 CONSTANT CSS-S-TYPE
2 CONSTANT CSS-S-UNIVERSAL
3 CONSTANT CSS-S-CLASS
4 CONSTANT CSS-S-ID
5 CONSTANT CSS-S-ATTR
6 CONSTANT CSS-S-PSEUDO-C
7 CONSTANT CSS-S-PSEUDO-E

\ Combinator type constants
0 CONSTANT CSS-C-DESCENDANT
1 CONSTANT CSS-C-CHILD
2 CONSTANT CSS-C-ADJACENT
3 CONSTANT CSS-C-GENERAL

\ CSS-SEL-NEXT-SIMPLE ( a u -- a' u' type name-a name-u flag )
\   Parse one simple selector component from cursor.
\   Does NOT skip leading whitespace.
\   Returns type constant, name string, and flag.
\   Flag = -1 found, 0 nothing at cursor.
VARIABLE _CSNS-A

: CSS-SEL-NEXT-SIMPLE  ( a u -- a' u' type name-a name-u flag )
    DUP 0= IF 0 0 0 0 EXIT THEN
    OVER C@
    DUP 46 = IF                      \ '.' class
        DROP 1 /STRING
        CSS-GET-IDENT
        CSS-S-CLASS -ROT -1 EXIT
    THEN
    DUP 35 = IF                      \ '#' ID
        DROP 1 /STRING
        CSS-GET-IDENT
        CSS-S-ID -ROT -1 EXIT
    THEN
    DUP 91 = IF                      \ '[' attribute
        DROP 1 /STRING               \ skip '['
        OVER _CSNS-A !
        BEGIN
            DUP 0> WHILE
            OVER C@ 93 = IF          \ ']'
                OVER _CSNS-A @ -
                >R 1 /STRING
                CSS-S-ATTR _CSNS-A @ R>
                -1 EXIT
            THEN
            OVER C@ DUP 34 = OVER 39 = OR IF
                DROP CSS-SKIP-STRING
            ELSE
                DROP 1 /STRING
            THEN
        REPEAT
        \ unterminated
        OVER _CSNS-A @ -
        >R CSS-S-ATTR _CSNS-A @ R>
        -1 EXIT
    THEN
    DUP 58 = IF                      \ ':' pseudo
        DROP 1 /STRING               \ skip first ':'
        DUP 0> IF
            OVER C@ 58 = IF          \ '::' pseudo-element
                1 /STRING
                CSS-GET-IDENT
                CSS-S-PSEUDO-E -ROT -1 EXIT
            THEN
        THEN
        \ ':' pseudo-class (possibly with parens)
        OVER _CSNS-A !
        CSS-SKIP-IDENT
        DUP 0> IF
            OVER C@ 40 = IF          \ '(' function pseudo
                CSS-SKIP-PARENS
            THEN
        THEN
        OVER _CSNS-A @ -
        >R CSS-S-PSEUDO-C _CSNS-A @ R>
        -1 EXIT
    THEN
    DUP 42 = IF                      \ '*' universal
        DROP 1 /STRING
        CSS-S-UNIVERSAL 0 0 -1 EXIT
    THEN
    \ type selector?
    _CSS-IDENT-START? IF
        CSS-GET-IDENT
        CSS-S-TYPE -ROT -1 EXIT
    THEN
    \ nothing recognized
    0 0 0 0 ;

\ CSS-SEL-COMBINATOR ( a u -- a' u' comb-type flag )
\   Parse a combinator between compound selectors.
\   Call AFTER CSS-SEL-NEXT-SIMPLE returns flag=0.
\   Returns combinator type and flag.
\   Flag = 0 means end of selector (comma, brace, or empty).
: CSS-SEL-COMBINATOR  ( a u -- a' u' comb-type flag )
    CSS-SKIP-WS
    DUP 0= IF 0 0 EXIT THEN
    OVER C@
    DUP 44 = IF DROP 0 0 EXIT THEN   \ ',' end of group
    DUP 123 = IF DROP 0 0 EXIT THEN  \ '{' end of selector
    DUP 125 = IF DROP 0 0 EXIT THEN  \ '}' safety
    DUP 62 = IF                      \ '>' child
        DROP 1 /STRING CSS-SKIP-WS
        CSS-C-CHILD -1 EXIT
    THEN
    DUP 43 = IF                      \ '+' adjacent
        DROP 1 /STRING CSS-SKIP-WS
        CSS-C-ADJACENT -1 EXIT
    THEN
    126 = IF                         \ '~' general
        1 /STRING CSS-SKIP-WS
        CSS-C-GENERAL -1 EXIT
    THEN
    \ whitespace was the combinator (descendant)
    CSS-C-DESCENDANT -1 ;

\ CSS-SEL-GROUP-NEXT ( a u -- a' u' sel-a sel-u flag )
\   Iterate comma-separated selector groups.
\   Returns one selector string (trimmed) at a time.
\   Flag = -1 found, 0 no more groups.
VARIABLE _CSGN-A

: CSS-SEL-GROUP-NEXT  ( a u -- a' u' sel-a sel-u flag )
    CSS-SKIP-WS
    DUP 0= IF 0 0 0 EXIT THEN
    OVER _CSGN-A !
    BEGIN
        DUP 0> WHILE
        OVER C@
        DUP 44 = IF                  \ ',' separator
            DROP
            OVER _CSGN-A @ -
            >R 1 /STRING             \ skip ','
            _CSGN-A @ R>
            _CSS-TRIM-END -1 EXIT
        THEN
        DUP 34 = OVER 39 = OR IF
            DROP CSS-SKIP-STRING
        ELSE DUP 40 = IF
            DROP CSS-SKIP-PARENS
        ELSE
            DROP 1 /STRING
        THEN THEN
    REPEAT
    \ end of input — last group
    OVER _CSGN-A @ -
    DUP 0= IF DROP 0 0 0 EXIT THEN
    >R _CSGN-A @ R> _CSS-TRIM-END -1 ;

\ =====================================================================
\  Layer 4 — Selector Matching
\ =====================================================================
\
\ Standalone matching: takes element properties as parameters.
\ Does NOT depend on akashic-html.

\ CSS-MATCH-TYPE ( sel-a sel-u tag-a tag-u -- flag )
\   Type selector match (case-insensitive).
: CSS-MATCH-TYPE  ( sel-a sel-u tag-a tag-u -- flag )
    _CSS-STRI= ;

\ CSS-MATCH-ID ( sel-a sel-u id-a id-u -- flag )
\   ID selector match (exact).
: CSS-MATCH-ID  ( sel-a sel-u id-a id-u -- flag )
    _CSS-STR= ;

\ CSS-MATCH-CLASS ( class-a class-u classes-a classes-u -- flag )
\   Does the space-separated class list contain this class?
VARIABLE _CMC-CA   VARIABLE _CMC-CL
VARIABLE _CMC-TA

: CSS-MATCH-CLASS  ( class-a class-u classes-a classes-u -- flag )
    2SWAP _CMC-CL !  _CMC-CA !       \ save class to find
    BEGIN
        DUP 0> WHILE
        OVER C@ 32 = IF
            1 /STRING                 \ skip space
        ELSE
            OVER _CMC-TA !            \ save token start
            BEGIN
                1 /STRING
                DUP 0> IF
                    OVER C@ 32 =
                ELSE -1 THEN
            UNTIL
            \ compare token
            OVER _CMC-TA @ -
            >R _CMC-CA @ _CMC-CL @ _CMC-TA @ R>
            _CSS-STR=
            IF 2DROP -1 EXIT THEN
        THEN
    REPEAT
    2DROP 0 ;

\ Element state for CSS-MATCH-SIMPLE
VARIABLE _CMS-TA   VARIABLE _CMS-TL   \ tag name
VARIABLE _CMS-IA   VARIABLE _CMS-IL   \ element id
VARIABLE _CMS-CA   VARIABLE _CMS-CL   \ space-sep class list

\ CSS-MATCH-SET ( tag-a tag-u id-a id-u cls-a cls-u -- )
\   Set element properties for matching.
\   Must be called before CSS-MATCH-SIMPLE.
: CSS-MATCH-SET  ( tag-a tag-u id-a id-u cls-a cls-u -- )
    _CMS-CL !  _CMS-CA !
    _CMS-IL !  _CMS-IA !
    _CMS-TL !  _CMS-TA ! ;

\ CSS-MATCH-SIMPLE ( type sel-a sel-u -- flag )
\   Match one simple selector against the element set
\   by CSS-MATCH-SET.
: CSS-MATCH-SIMPLE  ( type sel-a sel-u -- flag )
    ROT
    DUP CSS-S-UNIVERSAL = IF
        DROP 2DROP -1 EXIT
    THEN
    DUP CSS-S-TYPE = IF
        DROP _CMS-TA @ _CMS-TL @ _CSS-STRI= EXIT
    THEN
    DUP CSS-S-ID = IF
        DROP _CMS-IA @ _CMS-IL @ _CSS-STR= EXIT
    THEN
    DUP CSS-S-CLASS = IF
        DROP _CMS-CA @ _CMS-CL @ CSS-MATCH-CLASS EXIT
    THEN
    \ unsupported: attr, pseudo-class, pseudo-element
    DROP 2DROP 0 ;

\ =====================================================================
\  Layer 5 — Specificity & Cascade
\ =====================================================================
\
\ CSS specificity is a triple (a, b, c):
\   a = number of ID selectors
\   b = number of class, attribute, pseudo-class selectors
\   c = number of type, pseudo-element selectors
\ Universal (*) and combinators don't count.

VARIABLE _CSP-A   VARIABLE _CSP-B   VARIABLE _CSP-C

\ CSS-SPECIFICITY ( sel-a sel-u -- a b c )
\   Calculate specificity for a selector string.
: CSS-SPECIFICITY  ( sel-a sel-u -- a b c )
    0 _CSP-A !  0 _CSP-B !  0 _CSP-C !
    BEGIN
        CSS-SEL-NEXT-SIMPLE
        IF
            2DROP                    \ drop name
            DUP CSS-S-ID = IF
                DROP 1 _CSP-A +!
            ELSE
                DUP CSS-S-CLASS =
                OVER CSS-S-ATTR = OR
                OVER CSS-S-PSEUDO-C = OR IF
                    DROP 1 _CSP-B +!
                ELSE
                    DUP CSS-S-TYPE =
                    OVER CSS-S-PSEUDO-E = OR IF
                        DROP 1 _CSP-C +!
                    ELSE
                        DROP         \ universal
                    THEN
                THEN
            THEN
        ELSE
            2DROP DROP               \ drop type/name zeros
            CSS-SEL-COMBINATOR
            IF DROP                  \ drop comb-type, continue
            ELSE
                DROP 2DROP           \ drop comb-type + cursor
                _CSP-A @ _CSP-B @ _CSP-C @
                EXIT
            THEN
        THEN
    AGAIN ;

\ CSS-SPEC-COMPARE ( a1 b1 c1 a2 b2 c2 -- n )
\   Compare two specificities.
\   n > 0: first wins.  n < 0: second wins.  n = 0: equal.
VARIABLE _SPC-A2   VARIABLE _SPC-B2   VARIABLE _SPC-C2

: CSS-SPEC-COMPARE  ( a1 b1 c1 a2 b2 c2 -- n )
    _SPC-C2 !  _SPC-B2 !  _SPC-A2 !
    ROT _SPC-A2 @ -
    DUP 0<> IF NIP NIP EXIT THEN
    DROP
    SWAP _SPC-B2 @ -
    DUP 0<> IF NIP EXIT THEN
    DROP
    _SPC-C2 @ - ;

\ CSS-SPEC-PACK ( a b c -- spec )
\   Pack specificity into single integer: a*65536 + b*256 + c.
: CSS-SPEC-PACK  ( a b c -- spec )
    SWAP 256 * + SWAP 65536 * + ;

\ =====================================================================
\  Layer 6 — Value Parsing
\ =====================================================================
\
\ Parse CSS property values: numbers, units, colors.
\ No floating point — uses integer + fractional parts.

\ _CSS-DIGIT? ( c -- flag )
\   Is this character a decimal digit?
: _CSS-DIGIT?  ( c -- flag )
    DUP 48 >= SWAP 57 <= AND ;

\ CSS-PARSE-INT ( a u -- a' u' n flag )
\   Parse integer with optional sign.
VARIABLE _CPI-N   VARIABLE _CPI-NEG

: CSS-PARSE-INT  ( a u -- a' u' n flag )
    DUP 0= IF 0 0 EXIT THEN
    0 _CPI-NEG !
    \ optional sign
    OVER C@ DUP 45 = IF
        DROP -1 _CPI-NEG !  1 /STRING
    ELSE 43 = IF
        1 /STRING
    THEN THEN
    \ must have at least one digit
    DUP 0= IF 0 0 EXIT THEN
    OVER C@ _CSS-DIGIT? 0= IF 0 0 EXIT THEN
    0 _CPI-N !
    BEGIN
        DUP 0> WHILE
        OVER C@ _CSS-DIGIT? 0= IF
            _CPI-NEG @ IF _CPI-N @ NEGATE ELSE _CPI-N @ THEN
            -1 EXIT
        THEN
        OVER C@ 48 -  _CPI-N @ 10 * +  _CPI-N !
        1 /STRING
    REPEAT
    _CPI-NEG @ IF _CPI-N @ NEGATE ELSE _CPI-N @ THEN -1 ;

\ CSS-PARSE-NUMBER ( a u -- a' u' int frac frac-digits flag )
\   Parse number: integer part + optional fractional part.
\   Example: "3.14" → int=3, frac=14, frac-digits=2.
\   No floating point — caller combines as needed.
VARIABLE _CPN-INT  VARIABLE _CPN-FRAC
VARIABLE _CPN-FD   VARIABLE _CPN-NEG
VARIABLE _CPN-OK

: CSS-PARSE-NUMBER  ( a u -- a' u' int frac frac-digits flag )
    DUP 0= IF 0 0 0 0 EXIT THEN
    0 _CPN-NEG !  0 _CPN-INT !
    0 _CPN-FRAC !  0 _CPN-FD !  0 _CPN-OK !
    \ optional sign
    OVER C@ DUP 45 = IF
        DROP -1 _CPN-NEG !  1 /STRING
    ELSE 43 = IF
        1 /STRING
    THEN THEN
    \ integer digits
    BEGIN
        DUP 0> IF OVER C@ _CSS-DIGIT? ELSE 0 THEN
    WHILE
        -1 _CPN-OK !
        OVER C@ 48 -  _CPN-INT @ 10 * +  _CPN-INT !
        1 /STRING
    REPEAT
    \ decimal point
    DUP 0> IF
        OVER C@ 46 = IF
            1 /STRING
            BEGIN
                DUP 0> IF OVER C@ _CSS-DIGIT? ELSE 0 THEN
            WHILE
                -1 _CPN-OK !
                OVER C@ 48 -  _CPN-FRAC @ 10 * +  _CPN-FRAC !
                1 _CPN-FD +!
                1 /STRING
            REPEAT
        THEN
    THEN
    _CPN-OK @ 0= IF 0 0 0 0 EXIT THEN
    _CPN-NEG @ IF _CPN-INT @ NEGATE ELSE _CPN-INT @ THEN
    _CPN-FRAC @  _CPN-FD @  -1 ;

\ CSS-SKIP-NUMBER ( a u -- a' u' )
\   Skip a numeric value (sign + digits + optional dot + digits).
: CSS-SKIP-NUMBER  ( a u -- a' u' )
    DUP 0= IF EXIT THEN
    OVER C@ DUP 43 = SWAP 45 = OR IF 1 /STRING THEN
    BEGIN
        DUP 0> IF OVER C@ _CSS-DIGIT? ELSE 0 THEN
    WHILE
        1 /STRING
    REPEAT
    DUP 0> IF
        OVER C@ 46 = IF
            1 /STRING
            BEGIN
                DUP 0> IF OVER C@ _CSS-DIGIT? ELSE 0 THEN
            WHILE
                1 /STRING
            REPEAT
        THEN
    THEN ;

\ CSS-PARSE-UNIT ( a u -- a' u' unit-a unit-u )
\   Extract unit suffix: px, em, rem, %, pt, cm, etc.
\   Returns empty (0 0) if no unit follows.
VARIABLE _CPU-A

: CSS-PARSE-UNIT  ( a u -- a' u' unit-a unit-u )
    DUP 0= IF 0 0 EXIT THEN
    OVER C@ 37 = IF              \ '%'
        OVER _CPU-A !
        1 /STRING
        _CPU-A @ 1 EXIT
    THEN
    OVER C@ _CSS-IDENT-START? IF  \ px, em, rem, etc.
        CSS-GET-IDENT EXIT
    THEN
    0 0 ;

\ _CSS-HEX-DIGIT ( c -- n flag )
\   Convert a hex digit character to its value.
: _CSS-HEX-DIGIT  ( c -- n flag )
    DUP 48 >= OVER 57  <= AND IF 48 - -1 EXIT THEN
    DUP 65 >= OVER 70  <= AND IF 55 - -1 EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - -1 EXIT THEN
    DROP 0 0 ;

\ _CSS-HEX-PAIR ( addr -- n flag )
\   Parse two hex digits at addr into a byte value.
: _CSS-HEX-PAIR  ( addr -- n flag )
    DUP C@ _CSS-HEX-DIGIT
    0= IF 2DROP 0 0 EXIT THEN
    SWAP 1+ C@ _CSS-HEX-DIGIT
    0= IF 2DROP 0 0 EXIT THEN
    SWAP 16 * + -1 ;

\ CSS-PARSE-HEX-COLOR ( a u -- a' u' r g b flag )
\   Parse #RGB or #RRGGBB hex color.
\   Returns r, g, b as 0-255 values.
VARIABLE _CHC-A   VARIABLE _CHC-R
VARIABLE _CHC-G   VARIABLE _CHC-B

: CSS-PARSE-HEX-COLOR  ( a u -- a' u' r g b flag )
    DUP 0= IF 0 0 0 0 EXIT THEN
    OVER C@ 35 <> IF 0 0 0 0 EXIT THEN   \ not '#'
    1 /STRING
    OVER _CHC-A !
    \ try 6-digit #RRGGBB
    DUP 6 >= IF
        _CHC-A @     _CSS-HEX-PAIR
        0= IF DROP 0 0 0 0 EXIT THEN  _CHC-R !
        _CHC-A @ 2 + _CSS-HEX-PAIR
        0= IF DROP 0 0 0 0 EXIT THEN  _CHC-G !
        _CHC-A @ 4 + _CSS-HEX-PAIR
        0= IF DROP 0 0 0 0 EXIT THEN  _CHC-B !
        6 /STRING
        _CHC-R @ _CHC-G @ _CHC-B @ -1 EXIT
    THEN
    \ try 3-digit #RGB
    DUP 3 >= IF
        _CHC-A @     C@ _CSS-HEX-DIGIT
        0= IF DROP 0 0 0 0 EXIT THEN  17 * _CHC-R !
        _CHC-A @ 1+  C@ _CSS-HEX-DIGIT
        0= IF DROP 0 0 0 0 EXIT THEN  17 * _CHC-G !
        _CHC-A @ 2 + C@ _CSS-HEX-DIGIT
        0= IF DROP 0 0 0 0 EXIT THEN  17 * _CHC-B !
        3 /STRING
        _CHC-R @ _CHC-G @ _CHC-B @ -1 EXIT
    THEN
    0 0 0 0 ;

\ =====================================================================
\  Layer 7 — Shorthand Expansion
\ =====================================================================
\
\ Parse value lists and expand TRBL shorthands.
\ CSS-SKIP-VALUE skips one value token.
\ CSS-NEXT-VALUE extracts the next space-separated value.
\ CSS-EXPAND-TRBL expands 1-4 values to Top/Right/Bottom/Left.

\ CSS-SKIP-VALUE ( a u -- a' u' )
\   Skip one CSS value token.
\   Handles identifiers, numbers, strings, functions, #colors, etc.
: CSS-SKIP-VALUE  ( a u -- a' u' )
    DUP 0= IF EXIT THEN
    OVER C@
    DUP 34 = OVER 39 = OR IF        \ string
        DROP CSS-SKIP-STRING EXIT
    THEN
    DUP 35 = IF                      \ '#' color
        DROP 1 /STRING
        BEGIN
            DUP 0> WHILE
            OVER C@ _CSS-HEX-DIGIT IF
                DROP 1 /STRING
            ELSE
                DROP EXIT
            THEN
        REPEAT EXIT
    THEN
    DUP 43 = OVER 45 = OR           \ + or - sign
    OVER _CSS-DIGIT? OR
    OVER 46 = OR IF                  \ or '.' for .5
        DROP CSS-SKIP-NUMBER
        \ skip optional unit
        DUP 0> IF
            OVER C@ DUP 37 = IF     \ '%'
                DROP 1 /STRING
            ELSE
                _CSS-IDENT-START? IF
                    CSS-SKIP-IDENT
                THEN
            THEN
        THEN EXIT
    THEN
    _CSS-IDENT-START? IF             \ ident or function
        CSS-SKIP-IDENT
        \ check for '(' — function call
        DUP 0> IF
            OVER C@ 40 = IF
                CSS-SKIP-PARENS
            THEN
        THEN EXIT
    THEN
    \ unknown — skip one char
    DROP 1 /STRING ;

\ CSS-NEXT-VALUE ( a u -- a' u' val-a val-u flag )
\   Get next space-separated value from a value list.
\   Skips leading whitespace. Returns the value string.
\   Flag = -1 found, 0 end of input.
VARIABLE _CNV-A

: CSS-NEXT-VALUE  ( a u -- a' u' val-a val-u flag )
    CSS-SKIP-WS
    DUP 0= IF 0 0 0 EXIT THEN
    OVER _CNV-A !
    CSS-SKIP-VALUE
    OVER _CNV-A @ - DUP 0= IF
        DROP 0 0 0 EXIT
    THEN
    >R _CNV-A @ R> -1 ;

\ CSS-EXPAND-TRBL ( val-a val-u -- t-a t-u r-a r-u b-a b-u l-a l-u n )
\   Parse 1-4 space-separated values and expand to
\   Top, Right, Bottom, Left using CSS shorthand rules.
\   n = number of values found (1-4).
\   Returns all four as string pairs plus count.
\   1 value:  T=R=B=L
\   2 values: T=B, R=L
\   3 values: T, R=L, B
\   4 values: T, R, B, L
VARIABLE _CET-TA  VARIABLE _CET-TL
VARIABLE _CET-RA  VARIABLE _CET-RL
VARIABLE _CET-BA  VARIABLE _CET-BL
VARIABLE _CET-LA  VARIABLE _CET-LL
VARIABLE _CET-N

: CSS-EXPAND-TRBL  ( val-a val-u -- t-a t-u r-a r-u b-a b-u l-a l-u n )
    0 _CET-N !
    0 _CET-TA !  0 _CET-TL !
    0 _CET-RA !  0 _CET-RL !
    0 _CET-BA !  0 _CET-BL !
    0 _CET-LA !  0 _CET-LL !
    \ parse first value
    CSS-NEXT-VALUE 0= IF
        2DROP
        0 0 0 0 0 0 0 0 0 EXIT
    THEN
    _CET-TL !  _CET-TA !  1 _CET-N !
    \ parse 2nd
    CSS-NEXT-VALUE IF
        _CET-RL !  _CET-RA !  2 _CET-N !
        \ parse 3rd
        CSS-NEXT-VALUE IF
            _CET-BL !  _CET-BA !  3 _CET-N !
            \ parse 4th
            CSS-NEXT-VALUE IF
                _CET-LL !  _CET-LA !  4 _CET-N !
            THEN
        THEN
    THEN
    2DROP                            \ drop remaining cursor
    \ apply expansion rules based on count
    _CET-N @ 1 = IF
        _CET-TA @ _CET-TL @         \ T
        _CET-TA @ _CET-TL @         \ R = T
        _CET-TA @ _CET-TL @         \ B = T
        _CET-TA @ _CET-TL @         \ L = T
        1 EXIT
    THEN
    _CET-N @ 2 = IF
        _CET-TA @ _CET-TL @         \ T
        _CET-RA @ _CET-RL @         \ R
        _CET-TA @ _CET-TL @         \ B = T
        _CET-RA @ _CET-RL @         \ L = R
        2 EXIT
    THEN
    _CET-N @ 3 = IF
        _CET-TA @ _CET-TL @         \ T
        _CET-RA @ _CET-RL @         \ R
        _CET-BA @ _CET-BL @         \ B
        _CET-RA @ _CET-RL @         \ L = R
        3 EXIT
    THEN
    \ 4 values
    _CET-TA @ _CET-TL @
    _CET-RA @ _CET-RL @
    _CET-BA @ _CET-BL @
    _CET-LA @ _CET-LL @
    4 ;

\ =====================================================================
\  Layer 8 — @-Rule Parsing
\ =====================================================================
\
\ Parse @-rules: @media, @import, @keyframes.
\ @font-face body is regular CSS declarations — use CSS-DECL-NEXT.

\ _CSS-EXTRACT-BODY ( a u -- a' u' body-a body-u )
\   Cursor at '{'. Returns cursor past block, and trimmed body.
VARIABLE _CEB-A
VARIABLE _CEB-BA   VARIABLE _CEB-BL

: _CSS-EXTRACT-BODY  ( a u -- a' u' body-a body-u )
    DUP 0= IF 0 0 EXIT THEN
    OVER C@ 123 <> IF 0 0 EXIT THEN   \ not '{'
    OVER _CEB-A !                      \ save '{' address
    CSS-SKIP-BLOCK                     \ cursor past '}'
    \ body = chars between { and }
    _CEB-A @ 1+  _CEB-BA !            \ body starts after '{'
    OVER _CEB-A @ - 2 -               \ body len
    DUP 0< IF DROP 0 THEN
    _CEB-BL !
    _CEB-BA @ _CEB-BL @ CSS-SKIP-WS _CSS-TRIM-END
    _CEB-BL ! _CEB-BA !
    _CEB-BA @ _CEB-BL @ ;

\ CSS-MEDIA-QUERY ( a u -- cond-a cond-u body-a body-u flag )
\   Parse @media rule. Cursor at '@media condition { body }'.
\   Returns media condition string and body content.
\   Flag=-1 success, 0 failure.
VARIABLE _CMQ-CA   VARIABLE _CMQ-CL
VARIABLE _CMQ-BA   VARIABLE _CMQ-BL

: CSS-MEDIA-QUERY  ( a u -- cond-a cond-u body-a body-u flag )
    DUP 0= IF 2DROP 0 0 0 0 0 EXIT THEN
    OVER C@ 64 <> IF 2DROP 0 0 0 0 0 EXIT THEN
    CSS-AT-RULE-NAME                   \ a' u' name-a name-u
    2DUP S" media" _CSS-STRI= 0= IF
        2DROP 2DROP 0 0 0 0 0 EXIT
    THEN
    2DROP                              \ drop name
    CSS-SKIP-WS
    OVER _CMQ-CA !                     \ save condition start
    123 CSS-SKIP-UNTIL                 \ at '{'
    DUP 0= IF 2DROP 0 0 0 0 0 EXIT THEN
    \ condition = from saved start to here
    OVER _CMQ-CA @ -
    _CMQ-CA @ SWAP _CSS-TRIM-END
    _CMQ-CL ! _CMQ-CA !
    \ body = content between { and }
    _CSS-EXTRACT-BODY
    _CMQ-BL ! _CMQ-BA !
    2DROP                              \ drop cursor
    _CMQ-CA @ _CMQ-CL @
    _CMQ-BA @ _CMQ-BL @
    -1 ;

\ _CSS-IS-URL-FUNC? ( a u -- a u flag )
\   Check if cursor is at "url(" (case-insensitive). Non-consuming.
VARIABLE _CUF-T

: _CSS-IS-URL-FUNC?  ( a u -- a u flag )
    DUP 4 < IF 0 EXIT THEN
    OVER _CUF-T !
    _CUF-T @ C@ _CSS-TOLOWER 117 <>     IF 0 EXIT THEN
    _CUF-T @ 1+ C@ _CSS-TOLOWER 114 <>  IF 0 EXIT THEN
    _CUF-T @ 2 + C@ _CSS-TOLOWER 108 <> IF 0 EXIT THEN
    _CUF-T @ 3 + C@ 40 <>               IF 0 EXIT THEN
    -1 ;

\ _CSS-STRING-CONTENT ( a u -- content-a content-u )
\   Extract content between quotes. Cursor at opening quote.
VARIABLE _CSC-A

: _CSS-STRING-CONTENT  ( a u -- content-a content-u )
    OVER _CSC-A !                      \ save start address
    CSS-SKIP-STRING                    \ past closing quote
    DROP _CSC-A @ - 2 -               \ content len = consumed - 2
    DUP 0< IF DROP 0 THEN
    _CSC-A @ 1+ SWAP ;                \ content starts after quote

\ CSS-IMPORT-URL ( a u -- url-a url-u flag )
\   Parse @import rule. Cursor at '@import'.
\   Handles: @import "url"; @import url("url"); @import url(bare);
VARIABLE _CIU-A

: CSS-IMPORT-URL  ( a u -- url-a url-u flag )
    DUP 0= IF 2DROP 0 0 0 EXIT THEN
    OVER C@ 64 <> IF 2DROP 0 0 0 EXIT THEN
    CSS-AT-RULE-NAME                   \ a' u' name-a name-u
    2DUP S" import" _CSS-STRI= 0= IF
        2DROP 2DROP 0 0 0 EXIT
    THEN
    2DROP
    CSS-SKIP-WS
    DUP 0= IF 2DROP 0 0 0 EXIT THEN
    \ Try url(...)
    _CSS-IS-URL-FUNC? IF
        4 /STRING CSS-SKIP-WS          \ skip "url(" + ws
        DUP 0= IF 2DROP 0 0 0 EXIT THEN
        OVER C@ DUP 34 = SWAP 39 = OR IF
            _CSS-STRING-CONTENT -1 EXIT
        THEN
        \ bare URL: up to ')'
        OVER _CIU-A !
        41 CSS-SKIP-UNTIL              \ at ')'
        DROP _CIU-A @ -               \ url len
        _CIU-A @ SWAP _CSS-TRIM-END
        -1 EXIT
    THEN
    \ Try quoted string
    OVER C@ DUP 34 = SWAP 39 = OR IF
        _CSS-STRING-CONTENT -1 EXIT
    THEN
    2DROP 0 0 0 ;

\ CSS-KEYFRAMES ( a u -- name-a name-u body-a body-u flag )
\   Parse @keyframes rule. Cursor at '@keyframes name { body }'.
VARIABLE _CKF-NA   VARIABLE _CKF-NL
VARIABLE _CKF-BA   VARIABLE _CKF-BL

: CSS-KEYFRAMES  ( a u -- name-a name-u body-a body-u flag )
    DUP 0= IF 2DROP 0 0 0 0 0 EXIT THEN
    OVER C@ 64 <> IF 2DROP 0 0 0 0 0 EXIT THEN
    CSS-AT-RULE-NAME                   \ a' u' name-a name-u
    2DUP S" keyframes" _CSS-STRI= 0= IF
        2DROP 2DROP 0 0 0 0 0 EXIT
    THEN
    2DROP
    CSS-SKIP-WS
    CSS-GET-IDENT                      \ a' u' name-a name-u
    DUP 0= IF 2DROP 2DROP 0 0 0 0 0 EXIT THEN
    _CKF-NL ! _CKF-NA !               \ save name
    CSS-SKIP-WS
    DUP 0= IF 2DROP 0 0 0 0 0 EXIT THEN
    OVER C@ 123 <> IF 2DROP 0 0 0 0 0 EXIT THEN
    _CSS-EXTRACT-BODY
    _CKF-BL ! _CKF-BA !
    2DROP                              \ drop cursor
    _CKF-NA @ _CKF-NL @
    _CKF-BA @ _CKF-BL @
    -1 ;

\ =====================================================================
\  Layer 9 — Builder
\ =====================================================================
\
\ Build CSS text programmatically into a user-provided buffer.

VARIABLE _CB-BUF   VARIABLE _CB-MAX   VARIABLE _CB-POS

: CSS-SET-OUTPUT  ( addr max -- )
    _CB-MAX !  _CB-BUF !  0 _CB-POS ! ;

: CSS-OUTPUT-RESET  ( -- )
    0 _CB-POS ! ;

: CSS-OUTPUT-RESULT  ( -- addr len )
    _CB-BUF @ _CB-POS @ ;

: _CSS-EMIT  ( char -- )
    _CB-POS @ _CB-MAX @ < IF
        _CB-BUF @ _CB-POS @ + C!
        1 _CB-POS +!
    ELSE
        DROP CSS-E-OVERFLOW CSS-FAIL
    THEN ;

: _CSS-TYPE  ( addr len -- )
    0 ?DO
        DUP I + C@ _CSS-EMIT
    LOOP DROP ;

\ CSS-RULE-START ( sel-a sel-u -- )
\   Emit "selector { "
: CSS-RULE-START  ( sel-a sel-u -- )
    _CSS-TYPE
    32 _CSS-EMIT  123 _CSS-EMIT  32 _CSS-EMIT ;  \ ' { '

\ CSS-RULE-END ( -- )
\   Emit "} "
: CSS-RULE-END  ( -- )
    125 _CSS-EMIT  32 _CSS-EMIT ;    \ '} '

\ CSS-PROP! ( prop-a prop-u val-a val-u -- )
\   Emit "property: value; "
: CSS-PROP!  ( prop-a prop-u val-a val-u -- )
    2>R                              \ save value
    _CSS-TYPE                        \ emit property
    58 _CSS-EMIT  32 _CSS-EMIT      \ ': '
    2R>
    _CSS-TYPE                        \ emit value
    59 _CSS-EMIT  32 _CSS-EMIT ;    \ '; '

\ CSS-COMMENT! ( txt-a txt-u -- )
\   Emit "/* text */ "
: CSS-COMMENT!  ( txt-a txt-u -- )
    47 _CSS-EMIT  42 _CSS-EMIT      \ '/*'
    32 _CSS-EMIT                     \ ' '
    _CSS-TYPE                        \ text
    32 _CSS-EMIT                     \ ' '
    42 _CSS-EMIT  47 _CSS-EMIT      \ '*/'
    32 _CSS-EMIT ;                   \ trailing space

\ CSS-MEDIA-START ( query-a query-u -- )
\   Emit "@media query { "
: CSS-MEDIA-START  ( query-a query-u -- )
    64 _CSS-EMIT                     \ '@'
    109 _CSS-EMIT 101 _CSS-EMIT 100 _CSS-EMIT
    105 _CSS-EMIT  97 _CSS-EMIT      \ 'media'
    32 _CSS-EMIT                     \ ' '
    _CSS-TYPE                        \ query
    32 _CSS-EMIT  123 _CSS-EMIT  32 _CSS-EMIT ;  \ ' { '

\ CSS-MEDIA-END ( -- )
\   Emit "} "
: CSS-MEDIA-END  ( -- )
    125 _CSS-EMIT  32 _CSS-EMIT ;    \ '} '

\ CSS-IMPORT! ( url-a url-u -- )
\   Emit "@import url(\"...\"); "
: CSS-IMPORT!  ( url-a url-u -- )
    64 _CSS-EMIT                     \ '@'
    105 _CSS-EMIT 109 _CSS-EMIT 112 _CSS-EMIT
    111 _CSS-EMIT 114 _CSS-EMIT 116 _CSS-EMIT  \ 'import'
    32 _CSS-EMIT                     \ ' '
    117 _CSS-EMIT 114 _CSS-EMIT 108 _CSS-EMIT  \ 'url'
    40 _CSS-EMIT  34 _CSS-EMIT       \ '("'
    _CSS-TYPE                        \ url
    34 _CSS-EMIT  41 _CSS-EMIT       \ '")'
    59 _CSS-EMIT  32 _CSS-EMIT ;     \ '; '

\ =====================================================================
\  Layer 10 — Named Colors
\ =====================================================================
\
\ 148 CSS named colors stored as a packed table.
\ Each entry: name-len (1 byte), name chars (lowercase), R, G, B.
\ Terminated by a 0-byte sentinel.

CREATE _CSS-COLOR-TABLE
  9 C, 97 C, 108 C, 105 C, 99 C, 101 C, 98 C, 108 C, 117 C, 101 C, 240 C, 248 C, 255 C,
  12 C, 97 C, 110 C, 116 C, 105 C, 113 C, 117 C, 101 C, 119 C, 104 C, 105 C, 116 C, 101 C, 250 C, 235 C, 215 C,
  4 C, 97 C, 113 C, 117 C, 97 C, 0 C, 255 C, 255 C,
  10 C, 97 C, 113 C, 117 C, 97 C, 109 C, 97 C, 114 C, 105 C, 110 C, 101 C, 127 C, 255 C, 212 C,
  5 C, 97 C, 122 C, 117 C, 114 C, 101 C, 240 C, 255 C, 255 C,
  5 C, 98 C, 101 C, 105 C, 103 C, 101 C, 245 C, 245 C, 220 C,
  6 C, 98 C, 105 C, 115 C, 113 C, 117 C, 101 C, 255 C, 228 C, 196 C,
  5 C, 98 C, 108 C, 97 C, 99 C, 107 C, 0 C, 0 C, 0 C,
  14 C, 98 C, 108 C, 97 C, 110 C, 99 C, 104 C, 101 C, 100 C, 97 C, 108 C, 109 C, 111 C, 110 C, 100 C, 255 C, 235 C, 205 C,
  4 C, 98 C, 108 C, 117 C, 101 C, 0 C, 0 C, 255 C,
  10 C, 98 C, 108 C, 117 C, 101 C, 118 C, 105 C, 111 C, 108 C, 101 C, 116 C, 138 C, 43 C, 226 C,
  5 C, 98 C, 114 C, 111 C, 119 C, 110 C, 165 C, 42 C, 42 C,
  9 C, 98 C, 117 C, 114 C, 108 C, 121 C, 119 C, 111 C, 111 C, 100 C, 222 C, 184 C, 135 C,
  9 C, 99 C, 97 C, 100 C, 101 C, 116 C, 98 C, 108 C, 117 C, 101 C, 95 C, 158 C, 160 C,
  10 C, 99 C, 104 C, 97 C, 114 C, 116 C, 114 C, 101 C, 117 C, 115 C, 101 C, 127 C, 255 C, 0 C,
  9 C, 99 C, 104 C, 111 C, 99 C, 111 C, 108 C, 97 C, 116 C, 101 C, 210 C, 105 C, 30 C,
  5 C, 99 C, 111 C, 114 C, 97 C, 108 C, 255 C, 127 C, 80 C,
  14 C, 99 C, 111 C, 114 C, 110 C, 102 C, 108 C, 111 C, 119 C, 101 C, 114 C, 98 C, 108 C, 117 C, 101 C, 100 C, 149 C, 237 C,
  8 C, 99 C, 111 C, 114 C, 110 C, 115 C, 105 C, 108 C, 107 C, 255 C, 248 C, 220 C,
  7 C, 99 C, 114 C, 105 C, 109 C, 115 C, 111 C, 110 C, 220 C, 20 C, 60 C,
  4 C, 99 C, 121 C, 97 C, 110 C, 0 C, 255 C, 255 C,
  8 C, 100 C, 97 C, 114 C, 107 C, 98 C, 108 C, 117 C, 101 C, 0 C, 0 C, 139 C,
  8 C, 100 C, 97 C, 114 C, 107 C, 99 C, 121 C, 97 C, 110 C, 0 C, 139 C, 139 C,
  13 C, 100 C, 97 C, 114 C, 107 C, 103 C, 111 C, 108 C, 100 C, 101 C, 110 C, 114 C, 111 C, 100 C, 184 C, 134 C, 11 C,
  8 C, 100 C, 97 C, 114 C, 107 C, 103 C, 114 C, 97 C, 121 C, 169 C, 169 C, 169 C,
  9 C, 100 C, 97 C, 114 C, 107 C, 103 C, 114 C, 101 C, 101 C, 110 C, 0 C, 100 C, 0 C,
  8 C, 100 C, 97 C, 114 C, 107 C, 103 C, 114 C, 101 C, 121 C, 169 C, 169 C, 169 C,
  9 C, 100 C, 97 C, 114 C, 107 C, 107 C, 104 C, 97 C, 107 C, 105 C, 189 C, 183 C, 107 C,
  11 C, 100 C, 97 C, 114 C, 107 C, 109 C, 97 C, 103 C, 101 C, 110 C, 116 C, 97 C, 139 C, 0 C, 139 C,
  14 C, 100 C, 97 C, 114 C, 107 C, 111 C, 108 C, 105 C, 118 C, 101 C, 103 C, 114 C, 101 C, 101 C, 110 C, 85 C, 107 C, 47 C,
  10 C, 100 C, 97 C, 114 C, 107 C, 111 C, 114 C, 97 C, 110 C, 103 C, 101 C, 255 C, 140 C, 0 C,
  10 C, 100 C, 97 C, 114 C, 107 C, 111 C, 114 C, 99 C, 104 C, 105 C, 100 C, 153 C, 50 C, 204 C,
  7 C, 100 C, 97 C, 114 C, 107 C, 114 C, 101 C, 100 C, 139 C, 0 C, 0 C,
  10 C, 100 C, 97 C, 114 C, 107 C, 115 C, 97 C, 108 C, 109 C, 111 C, 110 C, 233 C, 150 C, 122 C,
  12 C, 100 C, 97 C, 114 C, 107 C, 115 C, 101 C, 97 C, 103 C, 114 C, 101 C, 101 C, 110 C, 143 C, 188 C, 143 C,
  13 C, 100 C, 97 C, 114 C, 107 C, 115 C, 108 C, 97 C, 116 C, 101 C, 98 C, 108 C, 117 C, 101 C, 72 C, 61 C, 139 C,
  13 C, 100 C, 97 C, 114 C, 107 C, 115 C, 108 C, 97 C, 116 C, 101 C, 103 C, 114 C, 97 C, 121 C, 47 C, 79 C, 79 C,
  13 C, 100 C, 97 C, 114 C, 107 C, 115 C, 108 C, 97 C, 116 C, 101 C, 103 C, 114 C, 101 C, 121 C, 47 C, 79 C, 79 C,
  13 C, 100 C, 97 C, 114 C, 107 C, 116 C, 117 C, 114 C, 113 C, 117 C, 111 C, 105 C, 115 C, 101 C, 0 C, 206 C, 209 C,
  10 C, 100 C, 97 C, 114 C, 107 C, 118 C, 105 C, 111 C, 108 C, 101 C, 116 C, 148 C, 0 C, 211 C,
  8 C, 100 C, 101 C, 101 C, 112 C, 112 C, 105 C, 110 C, 107 C, 255 C, 20 C, 147 C,
  11 C, 100 C, 101 C, 101 C, 112 C, 115 C, 107 C, 121 C, 98 C, 108 C, 117 C, 101 C, 0 C, 191 C, 255 C,
  7 C, 100 C, 105 C, 109 C, 103 C, 114 C, 97 C, 121 C, 105 C, 105 C, 105 C,
  7 C, 100 C, 105 C, 109 C, 103 C, 114 C, 101 C, 121 C, 105 C, 105 C, 105 C,
  10 C, 100 C, 111 C, 100 C, 103 C, 101 C, 114 C, 98 C, 108 C, 117 C, 101 C, 30 C, 144 C, 255 C,
  9 C, 102 C, 105 C, 114 C, 101 C, 98 C, 114 C, 105 C, 99 C, 107 C, 178 C, 34 C, 34 C,
  11 C, 102 C, 108 C, 111 C, 114 C, 97 C, 108 C, 119 C, 104 C, 105 C, 116 C, 101 C, 255 C, 250 C, 240 C,
  11 C, 102 C, 111 C, 114 C, 101 C, 115 C, 116 C, 103 C, 114 C, 101 C, 101 C, 110 C, 34 C, 139 C, 34 C,
  7 C, 102 C, 117 C, 99 C, 104 C, 115 C, 105 C, 97 C, 255 C, 0 C, 255 C,
  9 C, 103 C, 97 C, 105 C, 110 C, 115 C, 98 C, 111 C, 114 C, 111 C, 220 C, 220 C, 220 C,
  10 C, 103 C, 104 C, 111 C, 115 C, 116 C, 119 C, 104 C, 105 C, 116 C, 101 C, 248 C, 248 C, 255 C,
  4 C, 103 C, 111 C, 108 C, 100 C, 255 C, 215 C, 0 C,
  9 C, 103 C, 111 C, 108 C, 100 C, 101 C, 110 C, 114 C, 111 C, 100 C, 218 C, 165 C, 32 C,
  4 C, 103 C, 114 C, 97 C, 121 C, 128 C, 128 C, 128 C,
  5 C, 103 C, 114 C, 101 C, 101 C, 110 C, 0 C, 128 C, 0 C,
  11 C, 103 C, 114 C, 101 C, 101 C, 110 C, 121 C, 101 C, 108 C, 108 C, 111 C, 119 C, 173 C, 255 C, 47 C,
  4 C, 103 C, 114 C, 101 C, 121 C, 128 C, 128 C, 128 C,
  8 C, 104 C, 111 C, 110 C, 101 C, 121 C, 100 C, 101 C, 119 C, 240 C, 255 C, 240 C,
  7 C, 104 C, 111 C, 116 C, 112 C, 105 C, 110 C, 107 C, 255 C, 105 C, 180 C,
  9 C, 105 C, 110 C, 100 C, 105 C, 97 C, 110 C, 114 C, 101 C, 100 C, 205 C, 92 C, 92 C,
  6 C, 105 C, 110 C, 100 C, 105 C, 103 C, 111 C, 75 C, 0 C, 130 C,
  5 C, 105 C, 118 C, 111 C, 114 C, 121 C, 255 C, 255 C, 240 C,
  5 C, 107 C, 104 C, 97 C, 107 C, 105 C, 240 C, 230 C, 140 C,
  8 C, 108 C, 97 C, 118 C, 101 C, 110 C, 100 C, 101 C, 114 C, 230 C, 230 C, 250 C,
  13 C, 108 C, 97 C, 118 C, 101 C, 110 C, 100 C, 101 C, 114 C, 98 C, 108 C, 117 C, 115 C, 104 C, 255 C, 240 C, 245 C,
  9 C, 108 C, 97 C, 119 C, 110 C, 103 C, 114 C, 101 C, 101 C, 110 C, 124 C, 252 C, 0 C,
  12 C, 108 C, 101 C, 109 C, 111 C, 110 C, 99 C, 104 C, 105 C, 102 C, 102 C, 111 C, 110 C, 255 C, 250 C, 205 C,
  9 C, 108 C, 105 C, 103 C, 104 C, 116 C, 98 C, 108 C, 117 C, 101 C, 173 C, 216 C, 230 C,
  10 C, 108 C, 105 C, 103 C, 104 C, 116 C, 99 C, 111 C, 114 C, 97 C, 108 C, 240 C, 128 C, 128 C,
  9 C, 108 C, 105 C, 103 C, 104 C, 116 C, 99 C, 121 C, 97 C, 110 C, 224 C, 255 C, 255 C,
  20 C, 108 C, 105 C, 103 C, 104 C, 116 C, 103 C, 111 C, 108 C, 100 C, 101 C, 110 C, 114 C, 111 C, 100 C, 121 C, 101 C, 108 C, 108 C, 111 C, 119 C, 250 C, 250 C, 210 C,
  9 C, 108 C, 105 C, 103 C, 104 C, 116 C, 103 C, 114 C, 97 C, 121 C, 211 C, 211 C, 211 C,
  10 C, 108 C, 105 C, 103 C, 104 C, 116 C, 103 C, 114 C, 101 C, 101 C, 110 C, 144 C, 238 C, 144 C,
  9 C, 108 C, 105 C, 103 C, 104 C, 116 C, 103 C, 114 C, 101 C, 121 C, 211 C, 211 C, 211 C,
  9 C, 108 C, 105 C, 103 C, 104 C, 116 C, 112 C, 105 C, 110 C, 107 C, 255 C, 182 C, 193 C,
  11 C, 108 C, 105 C, 103 C, 104 C, 116 C, 115 C, 97 C, 108 C, 109 C, 111 C, 110 C, 255 C, 160 C, 122 C,
  13 C, 108 C, 105 C, 103 C, 104 C, 116 C, 115 C, 101 C, 97 C, 103 C, 114 C, 101 C, 101 C, 110 C, 32 C, 178 C, 170 C,
  12 C, 108 C, 105 C, 103 C, 104 C, 116 C, 115 C, 107 C, 121 C, 98 C, 108 C, 117 C, 101 C, 135 C, 206 C, 250 C,
  14 C, 108 C, 105 C, 103 C, 104 C, 116 C, 115 C, 108 C, 97 C, 116 C, 101 C, 103 C, 114 C, 97 C, 121 C, 119 C, 136 C, 153 C,
  14 C, 108 C, 105 C, 103 C, 104 C, 116 C, 115 C, 108 C, 97 C, 116 C, 101 C, 103 C, 114 C, 101 C, 121 C, 119 C, 136 C, 153 C,
  14 C, 108 C, 105 C, 103 C, 104 C, 116 C, 115 C, 116 C, 101 C, 101 C, 108 C, 98 C, 108 C, 117 C, 101 C, 176 C, 196 C, 222 C,
  11 C, 108 C, 105 C, 103 C, 104 C, 116 C, 121 C, 101 C, 108 C, 108 C, 111 C, 119 C, 255 C, 255 C, 224 C,
  4 C, 108 C, 105 C, 109 C, 101 C, 0 C, 255 C, 0 C,
  9 C, 108 C, 105 C, 109 C, 101 C, 103 C, 114 C, 101 C, 101 C, 110 C, 50 C, 205 C, 50 C,
  5 C, 108 C, 105 C, 110 C, 101 C, 110 C, 250 C, 240 C, 230 C,
  7 C, 109 C, 97 C, 103 C, 101 C, 110 C, 116 C, 97 C, 255 C, 0 C, 255 C,
  6 C, 109 C, 97 C, 114 C, 111 C, 111 C, 110 C, 128 C, 0 C, 0 C,
  16 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 97 C, 113 C, 117 C, 97 C, 109 C, 97 C, 114 C, 105 C, 110 C, 101 C, 102 C, 205 C, 170 C,
  10 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 98 C, 108 C, 117 C, 101 C, 0 C, 0 C, 205 C,
  12 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 111 C, 114 C, 99 C, 104 C, 105 C, 100 C, 186 C, 85 C, 211 C,
  12 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 112 C, 117 C, 114 C, 112 C, 108 C, 101 C, 147 C, 112 C, 219 C,
  14 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 115 C, 101 C, 97 C, 103 C, 114 C, 101 C, 101 C, 110 C, 60 C, 179 C, 113 C,
  15 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 115 C, 108 C, 97 C, 116 C, 101 C, 98 C, 108 C, 117 C, 101 C, 123 C, 104 C, 238 C,
  17 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 115 C, 112 C, 114 C, 105 C, 110 C, 103 C, 103 C, 114 C, 101 C, 101 C, 110 C, 0 C, 250 C, 154 C,
  15 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 116 C, 117 C, 114 C, 113 C, 117 C, 111 C, 105 C, 115 C, 101 C, 72 C, 209 C, 204 C,
  15 C, 109 C, 101 C, 100 C, 105 C, 117 C, 109 C, 118 C, 105 C, 111 C, 108 C, 101 C, 116 C, 114 C, 101 C, 100 C, 199 C, 21 C, 133 C,
  12 C, 109 C, 105 C, 100 C, 110 C, 105 C, 103 C, 104 C, 116 C, 98 C, 108 C, 117 C, 101 C, 25 C, 25 C, 112 C,
  9 C, 109 C, 105 C, 110 C, 116 C, 99 C, 114 C, 101 C, 97 C, 109 C, 245 C, 255 C, 250 C,
  9 C, 109 C, 105 C, 115 C, 116 C, 121 C, 114 C, 111 C, 115 C, 101 C, 255 C, 228 C, 225 C,
  8 C, 109 C, 111 C, 99 C, 99 C, 97 C, 115 C, 105 C, 110 C, 255 C, 228 C, 181 C,
  11 C, 110 C, 97 C, 118 C, 97 C, 106 C, 111 C, 119 C, 104 C, 105 C, 116 C, 101 C, 255 C, 222 C, 173 C,
  4 C, 110 C, 97 C, 118 C, 121 C, 0 C, 0 C, 128 C,
  7 C, 111 C, 108 C, 100 C, 108 C, 97 C, 99 C, 101 C, 253 C, 245 C, 230 C,
  5 C, 111 C, 108 C, 105 C, 118 C, 101 C, 128 C, 128 C, 0 C,
  9 C, 111 C, 108 C, 105 C, 118 C, 101 C, 100 C, 114 C, 97 C, 98 C, 107 C, 142 C, 35 C,
  6 C, 111 C, 114 C, 97 C, 110 C, 103 C, 101 C, 255 C, 165 C, 0 C,
  9 C, 111 C, 114 C, 97 C, 110 C, 103 C, 101 C, 114 C, 101 C, 100 C, 255 C, 69 C, 0 C,
  6 C, 111 C, 114 C, 99 C, 104 C, 105 C, 100 C, 218 C, 112 C, 214 C,
  13 C, 112 C, 97 C, 108 C, 101 C, 103 C, 111 C, 108 C, 100 C, 101 C, 110 C, 114 C, 111 C, 100 C, 238 C, 232 C, 170 C,
  9 C, 112 C, 97 C, 108 C, 101 C, 103 C, 114 C, 101 C, 101 C, 110 C, 152 C, 251 C, 152 C,
  13 C, 112 C, 97 C, 108 C, 101 C, 116 C, 117 C, 114 C, 113 C, 117 C, 111 C, 105 C, 115 C, 101 C, 175 C, 238 C, 238 C,
  13 C, 112 C, 97 C, 108 C, 101 C, 118 C, 105 C, 111 C, 108 C, 101 C, 116 C, 114 C, 101 C, 100 C, 219 C, 112 C, 147 C,
  10 C, 112 C, 97 C, 112 C, 97 C, 121 C, 97 C, 119 C, 104 C, 105 C, 112 C, 255 C, 239 C, 213 C,
  9 C, 112 C, 101 C, 97 C, 99 C, 104 C, 112 C, 117 C, 102 C, 102 C, 255 C, 218 C, 185 C,
  4 C, 112 C, 101 C, 114 C, 117 C, 205 C, 133 C, 63 C,
  4 C, 112 C, 105 C, 110 C, 107 C, 255 C, 192 C, 203 C,
  4 C, 112 C, 108 C, 117 C, 109 C, 221 C, 160 C, 221 C,
  10 C, 112 C, 111 C, 119 C, 100 C, 101 C, 114 C, 98 C, 108 C, 117 C, 101 C, 176 C, 224 C, 230 C,
  6 C, 112 C, 117 C, 114 C, 112 C, 108 C, 101 C, 128 C, 0 C, 128 C,
  13 C, 114 C, 101 C, 98 C, 101 C, 99 C, 99 C, 97 C, 112 C, 117 C, 114 C, 112 C, 108 C, 101 C, 102 C, 51 C, 153 C,
  3 C, 114 C, 101 C, 100 C, 255 C, 0 C, 0 C,
  9 C, 114 C, 111 C, 115 C, 121 C, 98 C, 114 C, 111 C, 119 C, 110 C, 188 C, 143 C, 143 C,
  9 C, 114 C, 111 C, 121 C, 97 C, 108 C, 98 C, 108 C, 117 C, 101 C, 65 C, 105 C, 225 C,
  11 C, 115 C, 97 C, 100 C, 100 C, 108 C, 101 C, 98 C, 114 C, 111 C, 119 C, 110 C, 139 C, 69 C, 19 C,
  6 C, 115 C, 97 C, 108 C, 109 C, 111 C, 110 C, 250 C, 128 C, 114 C,
  10 C, 115 C, 97 C, 110 C, 100 C, 121 C, 98 C, 114 C, 111 C, 119 C, 110 C, 244 C, 164 C, 96 C,
  8 C, 115 C, 101 C, 97 C, 103 C, 114 C, 101 C, 101 C, 110 C, 46 C, 139 C, 87 C,
  8 C, 115 C, 101 C, 97 C, 115 C, 104 C, 101 C, 108 C, 108 C, 255 C, 245 C, 238 C,
  6 C, 115 C, 105 C, 101 C, 110 C, 110 C, 97 C, 160 C, 82 C, 45 C,
  6 C, 115 C, 105 C, 108 C, 118 C, 101 C, 114 C, 192 C, 192 C, 192 C,
  7 C, 115 C, 107 C, 121 C, 98 C, 108 C, 117 C, 101 C, 135 C, 206 C, 235 C,
  9 C, 115 C, 108 C, 97 C, 116 C, 101 C, 98 C, 108 C, 117 C, 101 C, 106 C, 90 C, 205 C,
  9 C, 115 C, 108 C, 97 C, 116 C, 101 C, 103 C, 114 C, 97 C, 121 C, 112 C, 128 C, 144 C,
  9 C, 115 C, 108 C, 97 C, 116 C, 101 C, 103 C, 114 C, 101 C, 121 C, 112 C, 128 C, 144 C,
  4 C, 115 C, 110 C, 111 C, 119 C, 255 C, 250 C, 250 C,
  11 C, 115 C, 112 C, 114 C, 105 C, 110 C, 103 C, 103 C, 114 C, 101 C, 101 C, 110 C, 0 C, 255 C, 127 C,
  9 C, 115 C, 116 C, 101 C, 101 C, 108 C, 98 C, 108 C, 117 C, 101 C, 70 C, 130 C, 180 C,
  3 C, 116 C, 97 C, 110 C, 210 C, 180 C, 140 C,
  4 C, 116 C, 101 C, 97 C, 108 C, 0 C, 128 C, 128 C,
  7 C, 116 C, 104 C, 105 C, 115 C, 116 C, 108 C, 101 C, 216 C, 191 C, 216 C,
  6 C, 116 C, 111 C, 109 C, 97 C, 116 C, 111 C, 255 C, 99 C, 71 C,
  9 C, 116 C, 117 C, 114 C, 113 C, 117 C, 111 C, 105 C, 115 C, 101 C, 64 C, 224 C, 208 C,
  6 C, 118 C, 105 C, 111 C, 108 C, 101 C, 116 C, 238 C, 130 C, 238 C,
  5 C, 119 C, 104 C, 101 C, 97 C, 116 C, 245 C, 222 C, 179 C,
  5 C, 119 C, 104 C, 105 C, 116 C, 101 C, 255 C, 255 C, 255 C,
  10 C, 119 C, 104 C, 105 C, 116 C, 101 C, 115 C, 109 C, 111 C, 107 C, 101 C, 245 C, 245 C, 245 C,
  6 C, 121 C, 101 C, 108 C, 108 C, 111 C, 119 C, 255 C, 255 C, 0 C,
  11 C, 121 C, 101 C, 108 C, 108 C, 111 C, 119 C, 103 C, 114 C, 101 C, 101 C, 110 C, 154 C, 205 C, 50 C,
  0 C,

\ CSS-COLOR-FIND ( name-a name-u -- r g b flag )
\   Look up a CSS named color. Case-insensitive.
\   Returns RGB values (0-255) and flag (-1 found, 0 not found).
VARIABLE _CCF-P

: CSS-COLOR-FIND  ( name-a name-u -- r g b flag )
    _CSS-COLOR-TABLE _CCF-P !
    BEGIN
        _CCF-P @ C@ DUP 0> WHILE    \ entry-len on stack
        >R                           \ save entry-len
        2DUP                          \ copy input name
        _CCF-P @ 1+ R@               \ tbl-name-addr entry-len
        _CSS-STRI= IF
            2DROP                    \ drop input name
            R>                       \ entry-len
            1+ _CCF-P @ +           \ addr of R byte
            DUP C@ SWAP 1+ DUP C@
            SWAP 1+ C@               \ R G B
            -1 EXIT
        THEN
        R> 4 + _CCF-P +!            \ advance past entry
    REPEAT
    DROP 2DROP 0 0 0 0 ;