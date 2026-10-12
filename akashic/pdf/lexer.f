\ =================================================================
\  lexer.f  —  PDF tokens and values, read as spans of bytes
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF- (public), _PDL- (private)
\  Depends on: nothing
\
\  Public API:
\   PDF-TOKEN    ( a u -- a' u' ta tu type )  the next token
\   PDF-VALUE    ( a u -- a' u' va vu type )  the next whole value
\   PDF-OPERAND  ( a u -- a' u' va vu type )  the same, with no references
\   PDF-INT      ( va vu -- n )               an integer's value
\   PDF-FIXED    ( va vu -- f )               a number, times 65536
\   PDF-REF@     ( va vu -- num gen )         a reference's numbers
\   PDF-NAME=    ( va vu name-a name-u -- flag )  a name is NAME
\   PDF-DICT@    ( key-a key-u da du -- va vu type )  a dictionary's value
\   PDF-ARRAY-N  ( aa au -- n )               an array's values
\   PDF-ARRAY@   ( i aa au -- va vu type )    an array's Ith value
\   PDF-STRING   ( va vu type dst cap -- u )  a string's bytes
\
\  The lexer never copies or keeps the bytes it reads: a token or value
\  is a span of the caller's input, and the caller keeps that input
\  alive while it uses the span.  Words keep their state on the stack,
\  so a value may be read while another is being read.
\
\  A value's span runs from its first byte to its last: a dictionary's
\  from "<<" to ">>", an array's from "[" to "]", a string's with its
\  delimiters, a name's with its slash, and a reference's from its
\  number to its "R".  A name passed to PDF-NAME= or PDF-DICT@ has no
\  slash.
\ =================================================================

PROVIDED akashic-pdf-lexer

\ Token and value types.
0  CONSTANT PDF-T-END          \ no more input
1  CONSTANT PDF-T-INT
2  CONSTANT PDF-T-REAL
3  CONSTANT PDF-T-NAME
4  CONSTANT PDF-T-STRING       \ a literal string
5  CONSTANT PDF-T-HEX          \ a hex string
6  CONSTANT PDF-T-ARRAY        \ a whole array (values only)
7  CONSTANT PDF-T-DICT         \ a whole dictionary (values only)
8  CONSTANT PDF-T-KEYWORD      \ true, false, null, obj, R, an operator ...
9  CONSTANT PDF-T-REF          \ num gen R (values only)
10 CONSTANT PDF-T-OPEN-ARRAY   \ (tokens only)
11 CONSTANT PDF-T-CLOSE-ARRAY
12 CONSTANT PDF-T-OPEN-DICT
13 CONSTANT PDF-T-CLOSE-DICT
14 CONSTANT PDF-T-BAD          \ bytes that are no token, or an open value

\ Character classes: 0 regular, 1 white space, 2 delimiter.
CREATE _PDL-CLASS 256 ALLOT
_PDL-CLASS 256 0 FILL
: _PDL-CLASS!  ( class c -- )  _PDL-CLASS + C! ;
1 0 _PDL-CLASS!  1 9 _PDL-CLASS!  1 10 _PDL-CLASS!  1 12 _PDL-CLASS!
1 13 _PDL-CLASS!  1 32 _PDL-CLASS!
2 40 _PDL-CLASS!  2 41 _PDL-CLASS!  2 60 _PDL-CLASS!  2 62 _PDL-CLASS!
2 91 _PDL-CLASS!  2 93 _PDL-CLASS!  2 123 _PDL-CLASS!  2 125 _PDL-CLASS!
2 47 _PDL-CLASS!  2 37 _PDL-CLASS!

: _PDL-CLASS@  ( c -- class )  _PDL-CLASS + C@ ;
: _PDL-ADV  ( a u n -- a+n u-n )  TUCK - >R + R> ;
: _PDL-DIGIT?  ( c -- flag )  48 58 WITHIN ;

\ Each byte's value as a hex digit, or 255.
CREATE _PDL-HEXV 256 ALLOT
: _PDL-HEXV-FILL  ( -- )
    _PDL-HEXV 256 255 FILL
    10 0 DO I  I 48 + _PDL-HEXV + C! LOOP
    6 0 DO I 10 +  I 65 + _PDL-HEXV + C!  I 10 +  I 97 + _PDL-HEXV + C! LOOP ;
_PDL-HEXV-FILL

\ A hex digit's value, or -1.
: _PDL-HEXVAL  ( c -- n | -1 )  _PDL-HEXV + C@ DUP 255 = IF DROP -1 THEN ;

\ Skip white space and comments.
: _PDL-SPACE  ( a u -- a' u' )
    BEGIN DUP WHILE
        OVER C@ DUP 37 = IF
            DROP
            BEGIN DUP IF OVER C@ DUP 10 <> SWAP 13 <> AND ELSE 0 THEN WHILE
                1 _PDL-ADV
            REPEAT
        ELSE
            _PDL-CLASS@ 1 <> IF EXIT THEN
            1 _PDL-ADV
        THEN
    REPEAT ;

\ Skip regular characters.
: _PDL-REGULAR  ( a u -- a' u' )
    BEGIN DUP IF OVER C@ _PDL-CLASS@ 0= ELSE 0 THEN WHILE
        1 _PDL-ADV
    REPEAT ;

\ The type of the regular token of U bytes at A: a number or a keyword.
: _PDL-WORD-TYPE  ( a u -- type )
    OVER C@ DUP 43 = SWAP 45 = OR IF 1 _PDL-ADV THEN
    DUP 0= IF 2DROP PDF-T-KEYWORD EXIT THEN
    0 0 2SWAP OVER + SWAP ?DO                         ( digits dots )
        I C@ DUP _PDL-DIGIT? IF DROP SWAP 1+ SWAP ELSE
            46 = IF 1+ ELSE 2DROP PDF-T-KEYWORD UNLOOP EXIT THEN
        THEN
    LOOP
    DUP 1 > IF 2DROP PDF-T-KEYWORD EXIT THEN
    SWAP 0= IF DROP PDF-T-KEYWORD EXIT THEN
    IF PDF-T-REAL ELSE PDF-T-INT THEN ;

\ A literal string's rest, after its "(": to just after its matching ")".
: _PDL-LITERAL  ( a u -- a' u' ok? )
    1 >R
    BEGIN DUP WHILE
        OVER C@ DUP 92 = IF
            DROP 1 _PDL-ADV DUP IF 1 _PDL-ADV THEN
        ELSE DUP 40 = IF
            DROP R> 1+ >R 1 _PDL-ADV
        ELSE 41 = IF
            1 _PDL-ADV R> 1- DUP 0= IF DROP -1 EXIT THEN >R
        ELSE
            1 _PDL-ADV
        THEN THEN THEN
    REPEAT R> DROP 0 ;

\ A hex string's rest, after its "<": to just after its ">".
: _PDL-HEX  ( a u -- a' u' ok? )
    BEGIN DUP WHILE
        OVER C@ 62 = IF 1 _PDL-ADV -1 EXIT THEN
        1 _PDL-ADV
    REPEAT 0 ;

\ One token at A, U at least one byte, past white space.
: _PDL-ONE  ( a u -- a' u' type )
    OVER C@
    DUP 47 = IF DROP 1 _PDL-ADV _PDL-REGULAR PDF-T-NAME EXIT THEN
    DUP 40 = IF
        DROP 1 _PDL-ADV _PDL-LITERAL IF PDF-T-STRING ELSE PDF-T-BAD THEN EXIT
    THEN
    DUP 60 = IF
        DROP DUP 1 > IF OVER 1+ C@ 60 = ELSE 0 THEN IF
            2 _PDL-ADV PDF-T-OPEN-DICT EXIT
        THEN
        1 _PDL-ADV _PDL-HEX IF PDF-T-HEX ELSE PDF-T-BAD THEN EXIT
    THEN
    DUP 62 = IF
        DROP DUP 1 > IF OVER 1+ C@ 62 = ELSE 0 THEN IF
            2 _PDL-ADV PDF-T-CLOSE-DICT EXIT
        THEN
        1 _PDL-ADV PDF-T-BAD EXIT
    THEN
    DUP 91 = IF DROP 1 _PDL-ADV PDF-T-OPEN-ARRAY EXIT THEN
    DUP 93 = IF DROP 1 _PDL-ADV PDF-T-CLOSE-ARRAY EXIT THEN
    DUP 123 = OVER 125 = OR IF DROP 1 _PDL-ADV PDF-T-KEYWORD EXIT THEN
    _PDL-CLASS@ 2 = IF 1 _PDL-ADV PDF-T-BAD EXIT THEN
    OVER >R _PDL-REGULAR
    OVER R@ - R> SWAP _PDL-WORD-TYPE ;

\ PDF-TOKEN ( a u -- a' u' ta tu type )
\   The next token of the U bytes at A, and the input after it.
: PDF-TOKEN  ( a u -- a' u' ta tu type )
    _PDL-SPACE
    DUP 0= IF 0 0 PDF-T-END EXIT THEN
    OVER >R _PDL-ONE
    R> 3 PICK OVER - ROT ;

VARIABLE _PDL-DEPTH

: _PDL-CLOSE?  ( -- done? )  -1 _PDL-DEPTH +!  _PDL-DEPTH @ 0= ;

\ The rest of an array or dictionary after its opening token: to just
\ after the token that closes it, or false at the end of the input or at
\ bytes that are no token.  Its bytes are passed over without making
\ tokens of them: only strings, comments and the nesting are followed.
: _PDL-NESTED  ( a u -- a' u' ok? )
    1 _PDL-DEPTH !
    BEGIN DUP WHILE
        OVER C@ DUP _PDL-CLASS@ 2 <> IF DROP 1 _PDL-ADV ELSE
        DUP 40 = IF DROP 1 _PDL-ADV _PDL-LITERAL 0= IF 0 EXIT THEN ELSE
        DUP 37 = IF
            DROP
            BEGIN DUP IF OVER C@ DUP 10 <> SWAP 13 <> AND ELSE 0 THEN WHILE
                1 _PDL-ADV
            REPEAT
        ELSE
        DUP 91 = IF DROP 1 _PDL-DEPTH +!  1 _PDL-ADV ELSE
        DUP 93 = IF DROP 1 _PDL-ADV _PDL-CLOSE? IF -1 EXIT THEN ELSE
        DUP 60 = IF
            DROP DUP 1 > IF OVER 1+ C@ 60 = ELSE 0 THEN IF
                1 _PDL-DEPTH +!  2 _PDL-ADV
            ELSE 1 _PDL-ADV _PDL-HEX 0= IF 0 EXIT THEN THEN
        ELSE
        DUP 62 = IF
            DROP DUP 1 > IF OVER 1+ C@ 62 = ELSE 0 THEN 0= IF 0 EXIT THEN
            2 _PDL-ADV _PDL-CLOSE? IF -1 EXIT THEN
        ELSE
            41 = IF 0 EXIT THEN
            1 _PDL-ADV
        THEN THEN THEN THEN THEN THEN THEN
    REPEAT 0 ;

VARIABLE _PDL-TA  VARIABLE _PDL-TU

\ An integer that two more tokens, an integer and R, make a reference.
: _PDL-REF?  ( a u ta tu type -- a' u' va vu type' )
    DROP _PDL-TU ! _PDL-TA !
    2DUP PDF-TOKEN NIP NIP PDF-T-INT = IF
        PDF-TOKEN PDF-T-KEYWORD = IF
            1 = SWAP C@ 82 = AND IF
                2SWAP 2DROP
                _PDL-TA @ 2 PICK OVER - PDF-T-REF EXIT
            THEN
        ELSE 2DROP THEN
    THEN
    2DROP _PDL-TA @ _PDL-TU @ PDF-T-INT ;

\ An array or dictionary whose opening token was read, read whole.
: _PDL-WHOLE  ( a u ta tu type -- a' u' va vu type )
    >R DROP >R
    _PDL-NESTED
    R> SWAP R> SWAP
    IF PDF-T-OPEN-ARRAY = IF PDF-T-ARRAY ELSE PDF-T-DICT THEN
    ELSE DROP PDF-T-BAD THEN
    >R 2 PICK OVER - R> ;

\ PDF-OPERAND ( a u -- a' u' va vu type )
\   The next whole value where no reference can be, as in a content
\   stream or a CMap: an array or dictionary as one span, and integers
\   left integers, which spares the look ahead for an "R".
: PDF-OPERAND  ( a u -- a' u' va vu type )
    PDF-TOKEN
    DUP PDF-T-OPEN-ARRAY = OVER PDF-T-OPEN-DICT = OR IF _PDL-WHOLE THEN ;

\ PDF-VALUE ( a u -- a' u' va vu type )
\   The next whole value: an array, dictionary or reference as one span.
: PDF-VALUE  ( a u -- a' u' va vu type )
    PDF-OPERAND DUP PDF-T-INT = IF _PDL-REF? THEN ;

\ PDF-INT ( va vu -- n )   An integer's value; a real's whole part.
: PDF-INT  ( va vu -- n )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 45 = DUP >R IF 1 _PDL-ADV ELSE OVER C@ 43 = IF 1 _PDL-ADV THEN THEN
    0 -ROT OVER + SWAP ?DO
        I C@ DUP _PDL-DIGIT? 0= IF DROP LEAVE THEN 48 - SWAP 10 * +
    LOOP
    R> IF NEGATE THEN ;

VARIABLE _PDL-NI  VARIABLE _PDL-NF  VARIABLE _PDL-NS

\ PDF-FIXED ( va vu -- f )   A number times 65536, to five fraction digits.
: PDF-FIXED  ( va vu -- f )
    0 _PDL-NI !  0 _PDL-NF !  0 _PDL-NS !
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 45 = DUP >R IF 1 _PDL-ADV ELSE OVER C@ 43 = IF 1 _PDL-ADV THEN THEN
    OVER + SWAP ?DO
        I C@ DUP 46 = IF DROP 1 _PDL-NS ! ELSE
            DUP _PDL-DIGIT? 0= IF DROP LEAVE THEN 48 -
            _PDL-NS @ IF
                _PDL-NS @ 100000 < IF
                    _PDL-NF @ 10 * + _PDL-NF !  _PDL-NS @ 10 * _PDL-NS !
                ELSE DROP THEN
            ELSE _PDL-NI @ 10 * + _PDL-NI ! THEN
        THEN
    LOOP
    _PDL-NI @ 16 LSHIFT
    _PDL-NS @ ?DUP IF _PDL-NF @ 16 LSHIFT SWAP / + THEN
    R> IF NEGATE THEN ;

\ PDF-REF@ ( va vu -- num gen )   A reference's object and generation.
: PDF-REF@  ( va vu -- num gen )
    PDF-TOKEN DROP PDF-INT >R PDF-TOKEN DROP PDF-INT NIP NIP R> SWAP ;

\ PDF-NAME= ( va vu name-a name-u -- flag )
\   Whether the name at VA, with its slash and any #xx codes, is NAME.
: PDF-NAME=  ( va vu name-a name-u -- flag )
    2SWAP DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    1 _PDL-ADV
    BEGIN DUP WHILE
        OVER C@ 35 = OVER 3 < 0= AND IF
            OVER 1+ C@ _PDL-HEXVAL 4 LSHIFT  2 PICK 2 + C@ _PDL-HEXVAL OR
            255 AND >R 3 _PDL-ADV R>
        ELSE OVER C@ >R 1 _PDL-ADV R> THEN
        >R 2SWAP DUP 0= IF R> DROP 2DROP 2DROP 0 EXIT THEN
        OVER C@ R> <> IF 2DROP 2DROP 0 EXIT THEN
        1 _PDL-ADV 2SWAP
    REPEAT 2DROP NIP 0= ;

VARIABLE _PDL-KA  VARIABLE _PDL-KU

\ PDF-DICT@ ( key-a key-u da du -- va vu type )
\   The value of KEY in the dictionary at DA, or 0 0 PDF-T-END.
: PDF-DICT@  ( key-a key-u da du -- va vu type )
    2SWAP _PDL-KU ! _PDL-KA !  2 _PDL-ADV
    BEGIN
        PDF-VALUE PDF-T-NAME <> IF 2DROP 2DROP 0 0 PDF-T-END EXIT THEN
        _PDL-KA @ _PDL-KU @ PDF-NAME= >R
        PDF-VALUE
        R> IF >R 2SWAP 2DROP R> EXIT THEN
        DUP PDF-T-END = OVER PDF-T-BAD = OR IF DROP 2DROP 2DROP 0 0 PDF-T-END EXIT THEN
        DROP 2DROP
    AGAIN ;

\ An array's next value, or false at its end.
: _PDL-NEXT  ( a u -- a' u' va vu type more? )
    PDF-VALUE DUP PDF-T-CLOSE-ARRAY = OVER PDF-T-END = OR OVER PDF-T-BAD = OR 0= ;

\ PDF-ARRAY-N ( aa au -- n )   How many values the array at AA holds.
: PDF-ARRAY-N  ( aa au -- n )
    1 _PDL-ADV 0 >R
    BEGIN _PDL-NEXT WHILE DROP 2DROP R> 1+ >R REPEAT
    DROP 2DROP 2DROP R> ;

\ PDF-ARRAY@ ( i aa au -- va vu type )
\   The array's Ith value, from 0, or 0 0 PDF-T-END.
: PDF-ARRAY@  ( i aa au -- va vu type )
    1 _PDL-ADV ROT >R
    BEGIN _PDL-NEXT WHILE
        R@ 0= IF R> DROP >R 2SWAP 2DROP R> EXIT THEN
        DROP 2DROP R> 1- >R
    REPEAT
    R> DROP DROP 2DROP 2DROP 0 0 PDF-T-END ;

VARIABLE _PDS-D  VARIABLE _PDS-CAP  VARIABLE _PDS-N

: _PDS-PUT  ( c -- )
    _PDS-N @ _PDS-CAP @ < IF _PDS-D @ _PDS-N @ + C! ELSE DROP THEN
    1 _PDS-N +! ;

\ Up to three octal digits after a backslash.
: _PDS-OCTAL  ( a u -- a' u' )
    0 3 0 DO                                          ( a u n )
        OVER 0= IF LEAVE THEN
        2 PICK C@ DUP 48 56 WITHIN 0= IF DROP LEAVE THEN
        48 - SWAP 8 * +  -ROT 1 _PDL-ADV ROT
    LOOP 255 AND _PDS-PUT ;

\ A line end in a string: CR, LF, or CR LF.
: _PDS-EOL  ( a u -- a' u' )
    OVER C@ 13 = IF
        1 _PDL-ADV DUP IF OVER C@ 10 = IF 1 _PDL-ADV THEN THEN
    ELSE 1 _PDL-ADV THEN ;

\ The escape after a backslash.
: _PDS-ESCAPE  ( a u -- a' u' )
    DUP 0= IF EXIT THEN
    OVER C@ 48 56 WITHIN IF _PDS-OCTAL EXIT THEN
    OVER C@ DUP 13 = SWAP 10 = OR IF _PDS-EOL EXIT THEN
    OVER C@ CASE
        110 OF 10 ENDOF  114 OF 13 ENDOF  116 OF 9 ENDOF
        98 OF 8 ENDOF  102 OF 12 ENDOF
        DUP
    ENDCASE _PDS-PUT 1 _PDL-ADV ;

\ A literal string's bytes between its parentheses.
: _PDS-LITERAL  ( a u -- )
    BEGIN DUP WHILE
        OVER C@ DUP 92 = IF DROP 1 _PDL-ADV _PDS-ESCAPE ELSE
            DUP 13 = OVER 10 = OR IF DROP _PDS-EOL 10 _PDS-PUT ELSE
                _PDS-PUT 1 _PDL-ADV
            THEN
        THEN
    REPEAT 2DROP ;

VARIABLE _PDS-HI    \ a digit waiting for the one after it, or -1

\ A hex string's digits between its angle brackets.
: _PDS-HEX  ( a u -- )
    -1 _PDS-HI !
    OVER + SWAP ?DO
        I C@ _PDL-HEXV + C@ DUP 16 < IF
            _PDS-HI @ DUP 0< IF DROP _PDS-HI ! ELSE
                4 LSHIFT OR _PDS-PUT  -1 _PDS-HI !
            THEN
        ELSE DROP THEN
    LOOP
    _PDS-HI @ DUP 0< IF DROP ELSE 4 LSHIFT _PDS-PUT THEN ;

\ PDF-STRING ( va vu type dst cap -- u )
\   A string's bytes, at most CAP of them written at DST.  U is the
\   string's whole length, which may pass CAP.  A value that is no
\   string has no bytes.
: PDF-STRING  ( va vu type dst cap -- u )
    _PDS-CAP ! _PDS-D ! 0 _PDS-N !
    >R DUP 2 < IF 2DROP R> DROP 0 EXIT THEN
    1 _PDL-ADV 1- R>
    DUP PDF-T-HEX = IF DROP _PDS-HEX _PDS-N @ EXIT THEN
    PDF-T-STRING = IF _PDS-LITERAL _PDS-N @ EXIT THEN
    2DROP 0 ;
