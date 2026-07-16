\ xml-common.f - bounded strict XML support for syndication codecs

PROVIDED akashic-syndication-xml-common

REQUIRE model.f
REQUIRE ../markup/core.f
REQUIRE ../text/utf8.f

131072 CONSTANT SYN-XML-DOCUMENT-CAP
32 CONSTANT SX-MAX-DEPTH
63 CONSTANT SX-MAX-NAME

CREATE _SX-STACK-NAME SX-MAX-DEPTH 64 * ALLOT
CREATE _SX-STACK-LEN SX-MAX-DEPTH 8 * ALLOT
16 CONSTANT SX-MAX-ATTRS
CREATE _SX-ATTR-NAMES SX-MAX-ATTRS 64 * ALLOT
CREATE _SX-ATTR-LENS SX-MAX-ATTRS 8 * ALLOT

VARIABLE _SX-A
VARIABLE _SX-U
VARIABLE _SX-DEPTH
VARIABLE _SX-ROOTS
VARIABLE _SX-TYPE
VARIABLE _SX-NA
VARIABLE _SX-NU
VARIABLE _SX-NEXT-A
VARIABLE _SX-NEXT-U
VARIABLE _SX-ORIG-A
VARIABLE _SX-ORIG-U
VARIABLE _SX-SKIP-A
VARIABLE _SX-SKIP-U

: _SX-WS?  ( c -- flag )
    DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR ;

: _SX-ALL-WS?  ( a u -- flag )
    0 ?DO DUP I + C@ _SX-WS? 0= IF DROP 0 UNLOOP EXIT THEN LOOP
    DROP -1 ;

: _SX-NAME-START?  ( c -- flag )
    DUP 65 >= OVER 90 <= AND IF DROP -1 EXIT THEN
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 95 = SWAP 58 = OR ;

: _SX-NAME-SLOT  ( depth -- a ) 64 * _SX-STACK-NAME + ;
: _SX-LEN-SLOT  ( depth -- a ) 8 * _SX-STACK-LEN + ;

: _SX-PUSH  ( name-a name-u -- status )
    DUP 0= IF 2DROP SYN-S-INVALID EXIT THEN
    DUP SX-MAX-NAME > IF 2DROP SYN-S-CAPACITY EXIT THEN
    _SX-DEPTH @ SX-MAX-DEPTH >= IF 2DROP SYN-S-CAPACITY EXIT THEN
    DUP _SX-DEPTH @ _SX-LEN-SLOT !
    _SX-DEPTH @ _SX-NAME-SLOT SWAP CMOVE
    1 _SX-DEPTH +! SYN-S-OK ;

: _SX-POP-MATCH?  ( name-a name-u -- flag )
    _SX-DEPTH @ 0= IF 2DROP 0 EXIT THEN
    _SX-DEPTH @ 1- DUP _SX-LEN-SLOT @ >R _SX-NAME-SLOT R> STR-STR=
    DUP IF -1 _SX-DEPTH +! THEN ;

VARIABLE _SX-F3-C1
VARIABLE _SX-F3-C2
VARIABLE _SX-F3-C3
VARIABLE _SX-F3-A
VARIABLE _SX-F3-U

: _SX-FIND3?  ( a u c1 c2 c3 -- flag )
    _SX-F3-C3 ! _SX-F3-C2 ! _SX-F3-C1 !
    _SX-F3-U ! _SX-F3-A !
    _SX-F3-U @ 3 < IF 0 EXIT THEN
    _SX-F3-U @ 2 - 0 ?DO
        _SX-F3-A @ I + C@ _SX-F3-C1 @ =
        _SX-F3-A @ I + 1+ C@ _SX-F3-C2 @ = AND
        _SX-F3-A @ I + 2 + C@ _SX-F3-C3 @ = AND IF
            -1 UNLOOP EXIT
        THEN
    LOOP 0 ;

VARIABLE _SXV-A
VARIABLE _SXV-U
VARIABLE _SXV-P
VARIABLE _SXV-REM
VARIABLE _SXV-START
VARIABLE _SXV-RADIX
VARIABLE _SXV-DIGITS
VARIABLE _SXV-CP
VARIABLE _SXV-DIGIT

: _SXV-ADVANCE  ( n -- )
    DUP _SXV-A +! NEGATE _SXV-U +! ;

: _SXV-HEX?  ( c -- n flag )
    DUP 48 >= OVER 57 <= AND IF 48 - -1 EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - -1 EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - -1 EXIT THEN DROP 0 0 ;

: _SXV-DECIMAL?  ( c -- n flag )
    DUP 48 >= OVER 57 <= AND IF 48 - -1 ELSE DROP 0 0 THEN ;

: _SXV-NAMED?  ( a u -- flag )
    2DUP S" amp" STR-STR= IF 2DROP -1 EXIT THEN
    2DUP S" lt" STR-STR= IF 2DROP -1 EXIT THEN
    2DUP S" gt" STR-STR= IF 2DROP -1 EXIT THEN
    2DUP S" quot" STR-STR= IF 2DROP -1 EXIT THEN
    S" apos" STR-STR= ;

: _SXV-XML-CP?  ( cp -- flag )
    DUP 9 = OVER 10 = OR OVER 13 = OR IF DROP -1 EXIT THEN
    DUP 0x20 0xD800 WITHIN IF DROP -1 EXIT THEN
    DUP 0xE000 0xFFFE WITHIN IF DROP -1 EXIT THEN
    0x10000 0x110000 WITHIN ;

VARIABLE _SXCV-A
VARIABLE _SXCV-U

: SX-XML-CHARS-VALID?  ( a u -- flag )
    2DUP UTF8-VALID? 0= IF 2DROP 0 EXIT THEN
    _SXCV-U ! _SXCV-A !
    BEGIN _SXCV-U @ 0> WHILE
        _SXCV-A @ _SXCV-U @ UTF8-DECODE _SXCV-U ! _SXCV-A !
        _SXV-XML-CP? 0= IF 0 EXIT THEN
    REPEAT
    -1 ;

: _SX-REFS-VALID?  ( a u -- flag )
    _SXV-U ! _SXV-A !
    BEGIN _SXV-U @ 0> WHILE
        _SXV-A @ C@ 38 <> IF
            1 _SXV-ADVANCE
        ELSE
            _SXV-U @ 3 < IF 0 EXIT THEN
            _SXV-A @ 1+ _SXV-P ! _SXV-U @ 1- _SXV-REM !
            _SXV-P @ C@ 35 = IF
                1 _SXV-P +! -1 _SXV-REM +! 10 _SXV-RADIX !
                _SXV-REM @ 0> IF
                    _SXV-P @ C@ DUP 120 = SWAP 88 = OR IF
                        1 _SXV-P +! -1 _SXV-REM +! 16 _SXV-RADIX !
                    THEN
                THEN
                0 _SXV-DIGITS ! 0 _SXV-CP !
                BEGIN _SXV-REM @ 0> WHILE
                    _SXV-P @ C@ 59 = IF
                        _SXV-DIGITS @ 0= IF 0 EXIT THEN
                        _SXV-CP @ _SXV-XML-CP? 0= IF 0 EXIT THEN
                        _SXV-P @ _SXV-A @ - 1+ _SXV-ADVANCE
                        -1 _SXV-REM !
                    ELSE
                        _SXV-P @ C@ _SXV-RADIX @ 16 = IF
                            _SXV-HEX?
                        ELSE
                            _SXV-DECIMAL?
                        THEN
                        0= IF DROP 0 EXIT THEN _SXV-DIGIT !
                        _SXV-CP @ 0x10FFFF _SXV-DIGIT @ -
                            _SXV-RADIX @ / > IF 0 EXIT THEN
                        _SXV-CP @ _SXV-RADIX @ * _SXV-DIGIT @ + _SXV-CP !
                        1 _SXV-DIGITS +! 1 _SXV-P +! -1 _SXV-REM +!
                    THEN
                REPEAT
                _SXV-REM @ 0= IF 0 EXIT THEN
            ELSE
                _SXV-P @ _SXV-START !
                BEGIN _SXV-REM @ 0> WHILE
                    _SXV-P @ C@ 59 = IF
                        _SXV-START @ _SXV-P @ _SXV-START @ -
                            _SXV-NAMED? 0= IF 0 EXIT THEN
                        _SXV-P @ _SXV-A @ - 1+ _SXV-ADVANCE
                        -1 _SXV-REM !
                    ELSE
                        1 _SXV-P +! -1 _SXV-REM +!
                    THEN
                REPEAT
                _SXV-REM @ 0= IF 0 EXIT THEN
            THEN
        THEN
    REPEAT -1 ;

: _SX-TEXT-SYNTAX?  ( a u -- flag )
    2DUP 93 93 62 _SX-FIND3? IF 2DROP 0 EXIT THEN
    _SX-REFS-VALID? ;

VARIABLE _SXM-A
VARIABLE _SXM-U

: _SX-COMMENT-VALID?  ( a u -- flag )
    4 /STRING _SXM-U ! _SXM-A !
    BEGIN _SXM-U @ 0> WHILE
        _SXM-U @ 2 >= IF
            _SXM-A @ C@ 45 = _SXM-A @ 1+ C@ 45 = AND IF
                _SXM-U @ 3 >= IF _SXM-A @ 2 + C@ 62 = ELSE 0 THEN
                IF -1 EXIT ELSE 0 EXIT THEN
            THEN
        THEN
        1 _SXM-A +! -1 _SXM-U +!
    REPEAT 0 ;

: _SX-SKIP-COMMENT-CHECKED  ( a u -- a' u' status )
    2DUP _SX-COMMENT-VALID? 0= IF
        2DROP 0 0 SYN-S-INVALID EXIT
    THEN
    MU-SKIP-COMMENT SYN-S-OK ;

: _SX-SKIP-PI-CHECKED  ( a u -- a' u' status )
    _SX-SKIP-U ! _SX-SKIP-A !
    _SX-SKIP-A @ _SX-SKIP-U @ 2 /STRING _SX-U ! _SX-A !
    BEGIN _SX-U @ 2 >= WHILE
        _SX-A @ C@ 63 = _SX-A @ 1+ C@ 62 = AND IF
            _SX-SKIP-A @ _SX-SKIP-U @ MU-SKIP-PI SYN-S-OK EXIT
        THEN
        1 _SX-A +! -1 _SX-U +!
    REPEAT
    0 0 SYN-S-INVALID ;

: _SX-SKIP-CDATA-CHECKED  ( a u -- a' u' status )
    2DUP 9 /STRING 93 93 62 _SX-FIND3? 0= IF
        2DROP 0 0 SYN-S-INVALID EXIT
    THEN
    MU-SKIP-CDATA SYN-S-OK ;

VARIABLE _SXT-A
VARIABLE _SXT-U
VARIABLE _SXT-TYPE
VARIABLE _SXT-NA
VARIABLE _SXT-NU
VARIABLE _SXT-COUNT
VARIABLE _SXT-Q
VARIABLE _SXT-CLOSED
VARIABLE _SXT-VALUE-A

: _SXT-ATTR-NAME-SLOT  ( index -- a ) 64 * _SX-ATTR-NAMES + ;
: _SXT-ATTR-LEN-SLOT  ( index -- a ) 8 * _SX-ATTR-LENS + ;

: _SXT-ATTR-UNIQUE?  ( name-a name-u -- flag )
    _SXT-NU ! _SXT-NA !
    _SXT-COUNT @ 0 ?DO
        _SXT-NA @ _SXT-NU @ I _SXT-ATTR-NAME-SLOT
            I _SXT-ATTR-LEN-SLOT @ STR-STR= IF 0 UNLOOP EXIT THEN
    LOOP
    _SXT-COUNT @ SX-MAX-ATTRS >= IF 0 EXIT THEN
    _SXT-NU @ _SXT-COUNT @ _SXT-ATTR-LEN-SLOT !
    _SXT-NA @ _SXT-COUNT @ _SXT-ATTR-NAME-SLOT _SXT-NU @ CMOVE
    1 _SXT-COUNT +! -1 ;

: _SX-TAG-SYNTAX  ( tag-a tag-u type -- status )
    _SXT-TYPE ! _SXT-U ! _SXT-A ! 0 _SXT-COUNT !
    _SXT-A @ _SXT-U @ MU-GET-TAG-BODY
    DUP 0= IF 2DROP SYN-S-INVALID EXIT THEN
    _SXT-U ! _SXT-A !
    _SXT-TYPE @ MU-T-CLOSE = IF
        _SXT-A @ C@ 47 <> IF SYN-S-INVALID EXIT THEN
        1 _SXT-A +! -1 _SXT-U +!
    THEN
    _SXT-A @ _SXT-U @ MU-GET-NAME
    _SXT-NU ! _SXT-NA ! _SXT-U ! _SXT-A !
    _SXT-NU @ 0= IF SYN-S-INVALID EXIT THEN
    _SXT-NA @ C@ _SX-NAME-START? 0= IF SYN-S-INVALID EXIT THEN
    _SXT-NU @ SX-MAX-NAME > IF SYN-S-CAPACITY EXIT THEN
    _SXT-TYPE @ MU-T-CLOSE = IF
        _SXT-A @ _SXT-U @ MU-SKIP-WS _SXT-U ! _SXT-A !
        _SXT-U @ 0= IF SYN-S-OK ELSE SYN-S-INVALID THEN EXIT
    THEN
    BEGIN
        _SXT-COUNT @ _SXT-U @ 0> AND IF
            _SXT-A @ C@ DUP 47 <> SWAP _SX-WS? 0= AND IF
                SYN-S-INVALID EXIT
            THEN
        THEN
        _SXT-A @ _SXT-U @ MU-SKIP-WS _SXT-U ! _SXT-A !
        _SXT-U @ 0= IF
            _SXT-TYPE @ MU-T-OPEN = IF SYN-S-OK ELSE SYN-S-INVALID THEN EXIT
        THEN
        _SXT-A @ C@ 47 = IF
            _SXT-U @ 1 = _SXT-TYPE @ MU-T-SELF-CLOSE = AND
            IF SYN-S-OK ELSE SYN-S-INVALID THEN
            EXIT
        THEN
        _SXT-A @ _SXT-U @ MU-GET-NAME
        _SXT-NU ! _SXT-NA ! _SXT-U ! _SXT-A !
        _SXT-NU @ 0= _SXT-NU @ SX-MAX-NAME > OR IF SYN-S-INVALID EXIT THEN
        _SXT-NA @ C@ _SX-NAME-START? 0= IF SYN-S-INVALID EXIT THEN
        _SXT-NA @ _SXT-NU @ _SXT-ATTR-UNIQUE? 0= IF SYN-S-INVALID EXIT THEN
        _SXT-A @ _SXT-U @ MU-SKIP-WS _SXT-U ! _SXT-A !
        _SXT-U @ 0= IF SYN-S-INVALID EXIT THEN
        _SXT-A @ C@ 61 <> IF SYN-S-INVALID EXIT THEN
        1 _SXT-A +! -1 _SXT-U +!
        _SXT-A @ _SXT-U @ MU-SKIP-WS _SXT-U ! _SXT-A !
        _SXT-U @ 0= IF SYN-S-INVALID EXIT THEN
        _SXT-A @ C@ DUP 34 = OVER 39 = OR 0= IF DROP SYN-S-INVALID EXIT THEN
        _SXT-Q ! 0 _SXT-CLOSED ! 1 _SXT-A +! -1 _SXT-U +!
        _SXT-A @ _SXT-VALUE-A !
        BEGIN _SXT-U @ 0> _SXT-CLOSED @ 0= AND WHILE
            _SXT-A @ C@ DUP 60 = IF DROP SYN-S-INVALID EXIT THEN
            _SXT-Q @ = IF
                _SXT-VALUE-A @ _SXT-A @ _SXT-VALUE-A @ -
                    _SX-REFS-VALID? 0= IF SYN-S-INVALID EXIT THEN
                1 _SXT-A +! -1 _SXT-U +! -1 _SXT-CLOSED !
            ELSE
                1 _SXT-A +! -1 _SXT-U +!
            THEN
        REPEAT
        _SXT-CLOSED @ 0= IF SYN-S-INVALID EXIT THEN
    AGAIN ;

64 CONSTANT SX-MAX-NS
CREATE _SXNS-PREFIX-A SX-MAX-NS 8 * ALLOT
CREATE _SXNS-PREFIX-U SX-MAX-NS 8 * ALLOT
CREATE _SXNS-URI-A SX-MAX-NS 8 * ALLOT
CREATE _SXNS-URI-U SX-MAX-NS 8 * ALLOT
CREATE _SXNS-LEVEL SX-MAX-NS 8 * ALLOT
VARIABLE _SXNS-COUNT
VARIABLE _SXNS-I
VARIABLE _SXNS-PA
VARIABLE _SXNS-PU
VARIABLE _SXNS-UA
VARIABLE _SXNS-UU
VARIABLE _SXNS-TARGET-DEPTH

: _SXNS-CELL  ( index base -- a ) SWAP 8 * + ;

: _SXNS-LOOKUP  ( prefix-a prefix-u -- uri-a uri-u found )
    _SXNS-PU ! _SXNS-PA !
    _SXNS-PA @ _SXNS-PU @ S" xml" STR-STR= IF
        S" http://www.w3.org/XML/1998/namespace" -1 EXIT
    THEN
    _SXNS-COUNT @ 1- _SXNS-I !
    BEGIN _SXNS-I @ 0< 0= WHILE
        _SXNS-I @ _SXNS-PREFIX-A _SXNS-CELL @
        _SXNS-I @ _SXNS-PREFIX-U _SXNS-CELL @
        _SXNS-PA @ _SXNS-PU @ STR-STR= IF
            _SXNS-I @ _SXNS-URI-A _SXNS-CELL @
            _SXNS-I @ _SXNS-URI-U _SXNS-CELL @ -1 EXIT
        THEN
        -1 _SXNS-I +!
    REPEAT
    0 0 0 ;

: _SXNS-ADD  ( prefix-a prefix-u uri-a uri-u level -- status )
    _SXNS-TARGET-DEPTH ! _SXNS-UU ! _SXNS-UA ! _SXNS-PU ! _SXNS-PA !
    _SXNS-COUNT @ SX-MAX-NS >= IF SYN-S-CAPACITY EXIT THEN
    _SXNS-PA @ _SXNS-COUNT @ _SXNS-PREFIX-A _SXNS-CELL !
    _SXNS-PU @ _SXNS-COUNT @ _SXNS-PREFIX-U _SXNS-CELL !
    _SXNS-UA @ _SXNS-COUNT @ _SXNS-URI-A _SXNS-CELL !
    _SXNS-UU @ _SXNS-COUNT @ _SXNS-URI-U _SXNS-CELL !
    _SXNS-TARGET-DEPTH @ _SXNS-COUNT @ _SXNS-LEVEL _SXNS-CELL !
    1 _SXNS-COUNT +! SYN-S-OK ;

: _SXNS-POP-TO  ( depth -- )
    _SXNS-TARGET-DEPTH !
    BEGIN
        _SXNS-COUNT @ 0> IF
            _SXNS-COUNT @ 1- _SXNS-LEVEL _SXNS-CELL @
            _SXNS-TARGET-DEPTH @ >
        ELSE 0 THEN
    WHILE
        -1 _SXNS-COUNT +!
    REPEAT ;

VARIABLE _SXQ-A
VARIABLE _SXQ-U
VARIABLE _SXQ-I
VARIABLE _SXQ-COLONS
VARIABLE _SXQ-POS

: _SX-QNAME-SPLIT
    ( name-a name-u -- prefix-a prefix-u local-a local-u status )
    _SXQ-U ! _SXQ-A ! 0 _SXQ-COLONS ! 0 _SXQ-POS !
    _SXQ-U @ 0= IF 0 0 0 0 SYN-S-INVALID EXIT THEN
    _SXQ-U @ 0 ?DO
        _SXQ-A @ I + C@ 58 = IF
            1 _SXQ-COLONS +! I _SXQ-POS !
        THEN
    LOOP
    _SXQ-COLONS @ 1 > IF 0 0 0 0 SYN-S-INVALID EXIT THEN
    _SXQ-COLONS @ 0= IF
        0 0 _SXQ-A @ _SXQ-U @ SYN-S-OK EXIT
    THEN
    _SXQ-POS @ 0= _SXQ-POS @ _SXQ-U @ 1- = OR IF
        0 0 0 0 SYN-S-INVALID EXIT
    THEN
    _SXQ-A @ _SXQ-POS @
    _SXQ-A @ _SXQ-POS @ + 1+ _SXQ-U @ _SXQ-POS @ - 1-
    SYN-S-OK ;

VARIABLE _SXNG-A
VARIABLE _SXNG-U
VARIABLE _SXNG-LEVEL
VARIABLE _SXNG-NA
VARIABLE _SXNG-NU
VARIABLE _SXNG-VA
VARIABLE _SXNG-VU
VARIABLE _SXNG-PA
VARIABLE _SXNG-PU
VARIABLE _SXNG-LA
VARIABLE _SXNG-LU

: _SXNS-GATHER  ( tag-a tag-u level -- status )
    _SXNG-LEVEL ! _SXNG-U ! _SXNG-A !
    _SXNG-A @ _SXNG-U @ MU-GET-TAG-BODY
    DUP 0= IF 2DROP SYN-S-INVALID EXIT THEN
    MU-SKIP-NAME
    BEGIN
        MU-ATTR-NEXT
        DUP 0= IF
            >R 2DROP 2DROP 2DROP R> DROP SYN-S-OK EXIT
        THEN
        DROP _SXNG-VU ! _SXNG-VA ! _SXNG-NU ! _SXNG-NA !
        _SXNG-NA @ _SXNG-NU @ _SX-QNAME-SPLIT
        DUP IF >R 2DROP 2DROP 2DROP R> EXIT THEN DROP
        _SXNG-LU ! _SXNG-LA ! _SXNG-PU ! _SXNG-PA !
        _SXNG-PA @ _SXNG-PU @ S" xmlns" STR-STR= IF
            _SXNG-LA @ _SXNG-LU @ S" xmlns" STR-STR= IF
                2DROP SYN-S-INVALID EXIT
            THEN
            _SXNG-LA @ _SXNG-LU @ S" xml" STR-STR= IF
                _SXNG-VA @ _SXNG-VU @
                    S" http://www.w3.org/XML/1998/namespace" STR-STR= 0= IF
                    2DROP SYN-S-INVALID EXIT
                THEN
            ELSE
                _SXNG-VU @ 0= IF 2DROP SYN-S-INVALID EXIT THEN
                _SXNG-VA @ _SXNG-VU @
                    S" http://www.w3.org/XML/1998/namespace" STR-STR= IF
                    2DROP SYN-S-INVALID EXIT
                THEN
            THEN
            _SXNG-VA @ _SXNG-VU @
                S" http://www.w3.org/2000/xmlns/" STR-STR= IF
                2DROP SYN-S-INVALID EXIT
            THEN
            _SXNG-LA @ _SXNG-LU @ _SXNG-VA @ _SXNG-VU @
                _SXNG-LEVEL @ _SXNS-ADD
                ?DUP IF >R 2DROP R> EXIT THEN
        ELSE
            _SXNG-PU @ 0= _SXNG-LA @ _SXNG-LU @ S" xmlns" STR-STR= AND IF
                _SXNG-VA @ _SXNG-VU @
                    S" http://www.w3.org/2000/xmlns/" STR-STR= IF
                    2DROP SYN-S-INVALID EXIT
                THEN
                0 0 _SXNG-VA @ _SXNG-VU @ _SXNG-LEVEL @
                    _SXNS-ADD ?DUP IF >R 2DROP R> EXIT THEN
            THEN
        THEN
    AGAIN ;

VARIABLE _SXNR-A
VARIABLE _SXNR-U
VARIABLE _SXNR-ATTR
VARIABLE _SXNR-PA
VARIABLE _SXNR-PU
VARIABLE _SXNR-LA
VARIABLE _SXNR-LU

: _SXNS-RESOLVE  ( name-a name-u attribute? -- uri-a uri-u local-a local-u status )
    _SXNR-ATTR ! _SXNR-U ! _SXNR-A !
    _SXNR-A @ _SXNR-U @ _SX-QNAME-SPLIT
    DUP IF EXIT THEN DROP
    _SXNR-LU ! _SXNR-LA ! _SXNR-PU ! _SXNR-PA !
    _SXNR-ATTR @ IF
        _SXNR-PU @ 0= _SXNR-LA @ _SXNR-LU @ S" xmlns" STR-STR= AND IF
            S" http://www.w3.org/2000/xmlns/"
                _SXNR-LA @ _SXNR-LU @ SYN-S-OK EXIT
        THEN
        _SXNR-PA @ _SXNR-PU @ S" xmlns" STR-STR= IF
            S" http://www.w3.org/2000/xmlns/"
                _SXNR-LA @ _SXNR-LU @ SYN-S-OK EXIT
        THEN
        _SXNR-PU @ 0= IF
            0 0 _SXNR-LA @ _SXNR-LU @ SYN-S-OK EXIT
        THEN
    THEN
    _SXNR-PA @ _SXNR-PU @ _SXNS-LOOKUP
    0= IF
        2DROP
        _SXNR-PU @ 0= IF
            0 0 _SXNR-LA @ _SXNR-LU @ SYN-S-OK
        ELSE
            0 0 0 0 SYN-S-INVALID
        THEN
        EXIT
    THEN
    _SXNR-LA @ _SXNR-LU @ SYN-S-OK ;

CREATE _SXNA-URI-A SX-MAX-ATTRS 8 * ALLOT
CREATE _SXNA-URI-U SX-MAX-ATTRS 8 * ALLOT
CREATE _SXNA-LOCAL-A SX-MAX-ATTRS 8 * ALLOT
CREATE _SXNA-LOCAL-U SX-MAX-ATTRS 8 * ALLOT
VARIABLE _SXNA-COUNT
VARIABLE _SXNA-NA
VARIABLE _SXNA-NU
VARIABLE _SXNA-UA
VARIABLE _SXNA-UU
VARIABLE _SXNA-LA
VARIABLE _SXNA-LU
VARIABLE _SXNA-I

: _SXNS-ATTR-DUPS  ( tag-a tag-u -- status )
    MU-GET-TAG-BODY DUP 0= IF 2DROP SYN-S-INVALID EXIT THEN
    MU-SKIP-NAME 0 _SXNA-COUNT !
    BEGIN
        MU-ATTR-NEXT
        DUP 0= IF
            >R 2DROP 2DROP 2DROP R> DROP SYN-S-OK EXIT
        THEN
        DROP 2DROP _SXNA-NU ! _SXNA-NA !
        _SXNA-NA @ _SXNA-NU @ -1 _SXNS-RESOLVE
        DUP IF >R 2DROP 2DROP 2DROP R> EXIT THEN DROP
        _SXNA-LU ! _SXNA-LA ! _SXNA-UU ! _SXNA-UA !
        _SXNA-COUNT @ 0 ?DO
            _SXNA-UA @ _SXNA-UU @ I _SXNA-URI-A _SXNS-CELL @
                I _SXNA-URI-U _SXNS-CELL @ STR-STR=
            _SXNA-LA @ _SXNA-LU @ I _SXNA-LOCAL-A _SXNS-CELL @
                I _SXNA-LOCAL-U _SXNS-CELL @ STR-STR= AND IF
                2DROP SYN-S-INVALID UNLOOP EXIT
            THEN
        LOOP
        _SXNA-UA @ _SXNA-COUNT @ _SXNA-URI-A _SXNS-CELL !
        _SXNA-UU @ _SXNA-COUNT @ _SXNA-URI-U _SXNS-CELL !
        _SXNA-LA @ _SXNA-COUNT @ _SXNA-LOCAL-A _SXNS-CELL !
        _SXNA-LU @ _SXNA-COUNT @ _SXNA-LOCAL-U _SXNS-CELL !
        1 _SXNA-COUNT +!
    AGAIN ;

VARIABLE _SXNT-A
VARIABLE _SXNT-U
VARIABLE _SXNT-TYPE
VARIABLE _SXNT-SAVED

: _SX-TAG-NS  ( tag-a tag-u type -- status )
    _SXNT-TYPE ! _SXNT-U ! _SXNT-A !
    _SXNT-TYPE @ MU-T-CLOSE = IF
        _SXNT-A @ _SXNT-U @ MU-GET-TAG-NAME 2SWAP 2DROP
        0 _SXNS-RESOLVE >R 2DROP 2DROP R> EXIT
    THEN
    _SXNS-COUNT @ _SXNT-SAVED !
    _SXNT-A @ _SXNT-U @ _SX-DEPTH @ 1+ _SXNS-GATHER
    ?DUP IF _SXNT-SAVED @ _SXNS-COUNT ! EXIT THEN
    _SXNT-A @ _SXNT-U @ MU-GET-TAG-NAME 2SWAP 2DROP
    0 _SXNS-RESOLVE DUP IF
        >R 2DROP 2DROP R> _SXNT-SAVED @ _SXNS-COUNT ! EXIT
    THEN
    DROP 2DROP 2DROP
    _SXNT-A @ _SXNT-U @ _SXNS-ATTR-DUPS
    ?DUP IF _SXNT-SAVED @ _SXNS-COUNT ! EXIT THEN
    _SXNT-TYPE @ MU-T-SELF-CLOSE = IF
        _SXNT-SAVED @ _SXNS-COUNT !
    THEN
    SYN-S-OK ;

: SX-VALIDATE  ( document-a document-u -- status )
    DUP 0< IF 2DROP SYN-S-INVALID EXIT THEN
    DUP SYN-XML-DOCUMENT-CAP > IF 2DROP SYN-S-CAPACITY EXIT THEN
    2DUP _SX-ORIG-U ! _SX-ORIG-A !
    _SX-ORIG-U @ 0> _SX-ORIG-A @ 0= AND IF 2DROP SYN-S-INVALID EXIT THEN
    2DUP SX-XML-CHARS-VALID? 0= IF 2DROP SYN-S-INVALID EXIT THEN
    _SX-U ! _SX-A ! 0 _SX-DEPTH ! 0 _SX-ROOTS ! 0 _SXNS-COUNT !
    BEGIN _SX-U @ 0> WHILE
        _SX-A @ C@ 60 <> IF
            _SX-A @ _SX-U @ MU-SKIP-TO-TAG
            _SX-NEXT-U ! _SX-NEXT-A !
            _SX-A @ _SX-NEXT-A @ OVER -
            2DUP _SX-TEXT-SYNTAX? 0= IF 2DROP SYN-S-INVALID EXIT THEN
            _SX-DEPTH @ 0= IF _SX-ALL-WS? 0= ELSE 2DROP 0 THEN
            IF SYN-S-INVALID EXIT THEN
            _SX-NEXT-A @ _SX-A ! _SX-NEXT-U @ _SX-U !
        ELSE
            _SX-A @ _SX-U @ MU-TAG-TYPE _SX-TYPE !
            _SX-TYPE @ MU-T-TEXT = IF SYN-S-INVALID EXIT THEN
            _SX-TYPE @ MU-T-DOCTYPE = IF SYN-S-UNSUPPORTED EXIT THEN
            _SX-TYPE @ MU-T-COMMENT = IF
                _SX-A @ _SX-U @ _SX-SKIP-COMMENT-CHECKED
                DUP IF >R 2DROP R> EXIT THEN DROP _SX-U ! _SX-A !
            ELSE _SX-TYPE @ MU-T-PI = IF
                _SX-DEPTH @ IF SYN-S-INVALID EXIT THEN
                _SX-A @ _SX-U @ _SX-SKIP-PI-CHECKED
                DUP IF >R 2DROP R> EXIT THEN DROP _SX-U ! _SX-A !
            ELSE _SX-TYPE @ MU-T-CDATA = IF
                _SX-DEPTH @ 0= IF SYN-S-INVALID EXIT THEN
                _SX-A @ _SX-U @ _SX-SKIP-CDATA-CHECKED
                DUP IF >R 2DROP R> EXIT THEN DROP _SX-U ! _SX-A !
            ELSE _SX-TYPE @ MU-T-CLOSE = IF
                _SX-A @ _SX-U @ _SX-TYPE @ _SX-TAG-SYNTAX
                    ?DUP IF EXIT THEN
                _SX-A @ _SX-U @ _SX-TYPE @ _SX-TAG-NS
                    ?DUP IF EXIT THEN
                _SX-A @ _SX-U @ MU-GET-TAG-NAME
                _SX-NU ! _SX-NA ! 2DROP
                _SX-NA @ _SX-NU @ _SX-POP-MATCH? 0= IF
                    SYN-S-INVALID EXIT
                THEN
                _SX-DEPTH @ _SXNS-POP-TO
                _SX-A @ _SX-U @ MU-SKIP-TAG _SX-U ! _SX-A !
            ELSE
                _SX-A @ _SX-U @ _SX-TYPE @ _SX-TAG-SYNTAX
                    ?DUP IF EXIT THEN
                _SX-A @ _SX-U @ _SX-TYPE @ _SX-TAG-NS
                    ?DUP IF EXIT THEN
                _SX-DEPTH @ 0= IF
                    _SX-ROOTS @ IF SYN-S-INVALID EXIT THEN
                    1 _SX-ROOTS +!
                THEN
                _SX-A @ _SX-U @ MU-GET-TAG-NAME
                _SX-NU ! _SX-NA ! 2DROP
                _SX-TYPE @ MU-T-OPEN = IF
                    _SX-NA @ _SX-NU @ _SX-PUSH ?DUP IF EXIT THEN
                THEN
                _SX-A @ _SX-U @ MU-SKIP-TAG _SX-U ! _SX-A !
            THEN THEN THEN THEN
        THEN
    REPEAT
    _SX-DEPTH @ 0<> _SX-ROOTS @ 1 <> OR IF SYN-S-INVALID ELSE SYN-S-OK THEN ;

VARIABLE _SXR-A
VARIABLE _SXR-U

: SX-ROOT  ( document-a document-u -- root-a root-u status )
    _SXR-U ! _SXR-A !
    BEGIN
        _SXR-A @ _SXR-U @ MU-SKIP-WS _SXR-U ! _SXR-A !
        _SXR-U @ 0= IF 0 0 SYN-S-MISSING EXIT THEN
        _SXR-A @ _SXR-U @ MU-TAG-TYPE DUP MU-T-PI = IF
            DROP _SXR-A @ _SXR-U @ MU-SKIP-PI _SXR-U ! _SXR-A !
        ELSE DUP MU-T-COMMENT = IF
            DROP _SXR-A @ _SXR-U @ MU-SKIP-COMMENT _SXR-U ! _SXR-A !
        ELSE
            DUP MU-T-OPEN = SWAP MU-T-SELF-CLOSE = OR IF
                _SXR-A @ _SXR-U @ SYN-S-OK EXIT
            THEN
            0 0 SYN-S-INVALID EXIT
        THEN THEN
    AGAIN ;

VARIABLE _SXA-EA
VARIABLE _SXA-EU
VARIABLE _SXA-KA
VARIABLE _SXA-KU
VARIABLE _SXA-VA
VARIABLE _SXA-VU
VARIABLE _SXA-THIS-VA
VARIABLE _SXA-THIS-VU
VARIABLE _SXA-COUNT

: SX-ATTR-SPAN  ( element-a element-u key-a key-u -- value-a value-u found status )
    _SXA-KU ! _SXA-KA ! _SXA-EU ! _SXA-EA ! 0 _SXA-COUNT !
    _SXA-EA @ _SXA-EU @ MU-GET-TAG-BODY
    DUP 0= IF 2DROP 0 0 0 SYN-S-INVALID EXIT THEN
    MU-SKIP-NAME
    BEGIN
        MU-ATTR-NEXT
        DUP 0= IF
            >R 2DROP 2DROP 2DROP R> DROP
            _SXA-COUNT @ IF _SXA-VA @ _SXA-VU @ -1 ELSE 0 0 0 THEN
            SYN-S-OK EXIT
        THEN
        DROP _SXA-THIS-VU ! _SXA-THIS-VA !
        _SXA-KA @ _SXA-KU @ STR-STR= IF
            1 _SXA-COUNT +!
            _SXA-COUNT @ 1 > IF 2DROP 0 0 0 SYN-S-INVALID EXIT THEN
            _SXA-THIS-VA @ _SXA-VA ! _SXA-THIS-VU @ _SXA-VU !
        THEN
    AGAIN ;

VARIABLE _SXC-SA
VARIABLE _SXC-SU
VARIABLE _SXC-D
VARIABLE _SXC-MAX
VARIABLE _SXC-LEN
VARIABLE _SXC-N
VARIABLE _SXC-V
VARIABLE _SXC-BASE
VARIABLE _SXC-DIGIT

: _SXC-EMIT  ( c -- status )
    _SXC-N @ _SXC-MAX @ >= IF DROP SYN-S-CAPACITY EXIT THEN
    _SXC-D @ _SXC-N @ + C! 1 _SXC-N +! SYN-S-OK ;

: _SXC-HEX?  ( c -- n flag )
    DUP 48 >= OVER 57 <= AND IF 48 - -1 EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - -1 EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - -1 EXIT THEN DROP 0 0 ;

: _SXC-DIGIT?  ( c -- n flag )
    DUP 48 >= OVER 57 <= AND IF 48 - -1 ELSE DROP 0 0 THEN ;

: _SXC-EMIT-CP  ( cp -- status )
    DUP _SXV-XML-CP? 0= IF
        DROP SYN-S-INVALID EXIT
    THEN
    DUP 0x80 < IF _SXC-EMIT EXIT THEN
    DUP 0x800 < IF
        DUP 6 RSHIFT 0xC0 OR _SXC-EMIT ?DUP IF NIP EXIT THEN
        0x3F AND 0x80 OR _SXC-EMIT EXIT
    THEN
    DUP 0x10000 < IF
        DUP 12 RSHIFT 0xE0 OR _SXC-EMIT ?DUP IF NIP EXIT THEN
        DUP 6 RSHIFT 0x3F AND 0x80 OR _SXC-EMIT ?DUP IF NIP EXIT THEN
        0x3F AND 0x80 OR _SXC-EMIT EXIT
    THEN
    DUP 18 RSHIFT 0xF0 OR _SXC-EMIT ?DUP IF NIP EXIT THEN
    DUP 12 RSHIFT 0x3F AND 0x80 OR _SXC-EMIT ?DUP IF NIP EXIT THEN
    DUP 6 RSHIFT 0x3F AND 0x80 OR _SXC-EMIT ?DUP IF NIP EXIT THEN
    0x3F AND 0x80 OR _SXC-EMIT ;

: _SXC-NAMED  ( a u -- cp status )
    2DUP S" amp" STR-STR= IF 2DROP 38 SYN-S-OK EXIT THEN
    2DUP S" lt" STR-STR= IF 2DROP 60 SYN-S-OK EXIT THEN
    2DUP S" gt" STR-STR= IF 2DROP 62 SYN-S-OK EXIT THEN
    2DUP S" quot" STR-STR= IF 2DROP 34 SYN-S-OK EXIT THEN
    S" apos" STR-STR= IF 39 SYN-S-OK ELSE 0 SYN-S-UNSUPPORTED THEN ;

VARIABLE _SXE-START
VARIABLE _SXE-P
VARIABLE _SXE-REM
VARIABLE _SXE-RADIX
VARIABLE _SXE-DIGITS

: _SXC-ENTITY  ( a u -- consumed cp status )
    DUP 3 < IF 2DROP 0 0 SYN-S-INVALID EXIT THEN
    OVER C@ 38 <> IF 2DROP 0 0 SYN-S-INVALID EXIT THEN
    _SXE-REM ! DUP _SXE-START ! 1+ _SXE-P ! -1 _SXE-REM +!
    _SXE-P @ C@ 35 = IF
        1 _SXE-P +! -1 _SXE-REM +! 10 _SXE-RADIX !
        _SXE-REM @ 0> IF
            _SXE-P @ C@ DUP 120 = SWAP 88 = OR IF
                1 _SXE-P +! -1 _SXE-REM +! 16 _SXE-RADIX !
            THEN
        THEN
        0 _SXC-V ! 0 _SXE-DIGITS !
        BEGIN _SXE-REM @ 0> WHILE
            _SXE-P @ C@ 59 = IF
                _SXE-DIGITS @ 0= IF 0 0 SYN-S-INVALID EXIT THEN
                _SXE-P @ _SXE-START @ - 1+ _SXC-V @ SYN-S-OK EXIT
            THEN
            _SXE-P @ C@ _SXE-RADIX @ 16 = IF
                _SXC-HEX?
            ELSE
                _SXC-DIGIT?
            THEN
            0= IF DROP 0 0 SYN-S-INVALID EXIT THEN
            _SXC-DIGIT !
            _SXC-V @ 0x10FFFF _SXC-DIGIT @ - _SXE-RADIX @ / > IF
                0 0 SYN-S-INVALID EXIT
            THEN
            _SXC-V @ _SXE-RADIX @ * _SXC-DIGIT @ + _SXC-V !
            1 _SXE-DIGITS +! 1 _SXE-P +! -1 _SXE-REM +!
        REPEAT
        0 0 SYN-S-INVALID EXIT
    THEN
    BEGIN _SXE-REM @ 0> WHILE
        _SXE-P @ C@ 59 = IF
            _SXE-START @ 1+ _SXE-P @ _SXE-START @ 1+ - _SXC-NAMED
            >R >R _SXE-P @ _SXE-START @ - 1+ R> R> EXIT
        THEN
        1 _SXE-P +! -1 _SXE-REM +!
    REPEAT
    0 0 SYN-S-INVALID ;

: SX-COPY-XML-TEXT  ( source-a source-u dest max length-cell -- status )
    _SXC-LEN ! _SXC-MAX ! _SXC-D ! _SXC-SU ! _SXC-SA !
    0 _SXC-LEN @ !
    _SXC-SA @ _SXC-SU @ MU-SKIP-WS _SXC-SU ! _SXC-SA !
    BEGIN
        _SXC-SU @ 0> IF
            _SXC-SA @ _SXC-SU @ + 1- C@ _SX-WS?
        ELSE 0 THEN
    WHILE
        -1 _SXC-SU +!
    REPEAT
    _SXC-SA @ _SXC-SU @ SX-XML-CHARS-VALID? 0= IF
        SYN-S-INVALID EXIT
    THEN
    \ A single CDATA wrapper is a literal text value.
    _SXC-SU @ 12 >= IF
        _SXC-SA @ _SXC-SU @ MU-TAG-TYPE MU-T-CDATA = IF
            _SXC-SA @ _SXC-SU @ MU-SKIP-CDATA
            NIP 0= IF
                _SXC-SA @ 9 + _SXC-SU @ 12 -
                2DUP SX-XML-CHARS-VALID? 0= IF
                    2DROP SYN-S-INVALID EXIT
                THEN
                DUP _SXC-MAX @ > IF 2DROP SYN-S-CAPACITY EXIT THEN
                DUP _SXC-LEN @ ! _SXC-D @ SWAP CMOVE SYN-S-OK EXIT
            THEN
        THEN
    THEN
    0 _SXC-N !
    BEGIN _SXC-SU @ 0> WHILE
        _SXC-SA @ C@ DUP 60 = IF DROP SYN-S-UNSUPPORTED EXIT THEN
        38 = IF
            _SXC-SA @ _SXC-SU @ _SXC-ENTITY
            DUP IF >R 2DROP R> EXIT THEN DROP
            >R DUP _SXC-SA +! NEGATE _SXC-SU +! R>
            _SXC-EMIT-CP ?DUP IF EXIT THEN
        ELSE
            _SXC-SA @ C@ _SXC-EMIT ?DUP IF EXIT THEN
            1 _SXC-SA +! -1 _SXC-SU +!
        THEN
    REPEAT
    _SXC-D @ _SXC-N @ UTF8-VALID? 0= IF SYN-S-INVALID EXIT THEN
    _SXC-N @ _SXC-LEN @ ! SYN-S-OK ;

VARIABLE _SXTC-D
VARIABLE _SXTC-M
VARIABLE _SXTC-L

: SX-ELEMENT-TEXT  ( element-a element-u dest max length-cell -- status )
    _SXTC-L ! _SXTC-M ! _SXTC-D !
    MU-INNER _SXTC-D @ _SXTC-M @ _SXTC-L @ SX-COPY-XML-TEXT ;

VARIABLE _SXAC-D
VARIABLE _SXAC-M
VARIABLE _SXAC-L

: SX-ATTR-COPY
    ( element-a element-u key-a key-u dest max length-cell -- found status )
    _SXAC-L ! _SXAC-M ! _SXAC-D !
    SX-ATTR-SPAN DUP IF >R 2DROP DROP R> 0 SWAP EXIT THEN DROP
    0= IF 2DROP 0 _SXAC-L @ ! 0 SYN-S-OK EXIT THEN
    _SXAC-D @ _SXAC-M @ _SXAC-L @ SX-COPY-XML-TEXT -1 SWAP ;
