\ core.f — Shared markup-parsing core for XML & HTML5
\
\ Low-level tag scanning, attribute parsing, entity decoding,
\ and depth-aware element navigation.
\ Both the XML and HTML5 vocabularies build on these primitives.
\
\ Operates on (addr len) cursor pairs — same model as json.f.
\
\ Prefix: MU-   (public API)
\         _MU-  (internal helpers)
\
\ Load with:   REQUIRE core.f

REQUIRE ../utils/string.f

PROVIDED akashic-markup-core

\ =====================================================================
\  Utility — may already exist; safe to redefine
\ =====================================================================

\ /STRING ( addr len n -- addr+n len-n )
\   Standard Forth word; defined here in case BIOS lacks it.
: /STRING  ( addr len n -- addr+n len-n )
    ROT OVER + -ROT - ;

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE MU-ERR
VARIABLE MU-ABORT-ON-ERROR
0 MU-ERR !
0 MU-ABORT-ON-ERROR !                \ default: soft-fail

1 CONSTANT MU-E-NOT-FOUND
2 CONSTANT MU-E-MALFORMED
3 CONSTANT MU-E-UNTERMINATED
4 CONSTANT MU-E-UNEXPECTED
5 CONSTANT MU-E-OVERFLOW

: MU-FAIL  ( err-code -- )
    MU-ERR !
    MU-ABORT-ON-ERROR @ IF ABORT" Markup error" THEN ;

: MU-OK?  ( -- flag )
    MU-ERR @ 0= ;

: MU-CLEAR-ERR  ( -- )
    0 MU-ERR ! ;

\ =====================================================================
\  Layer 0 — Low-level Scanning Primitives
\ =====================================================================

\ MU-SKIP-WS ( addr len -- addr' len' )
\   Skip XML/HTML whitespace: space, tab, LF, CR.
: MU-SKIP-WS  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 32 =
        OVER  9 = OR
        OVER 10 = OR
        SWAP 13 = OR
        0= IF EXIT THEN
        1 /STRING
    REPEAT ;

\ MU-SKIP-UNTIL-CH ( addr len char -- addr' len' )
\   Advance cursor until char is found (or end of input).
\   Cursor stops AT the character (not past it).
: MU-SKIP-UNTIL-CH  ( addr len char -- addr' len' )
    >R
    BEGIN
        DUP 0> WHILE
        OVER C@ R@ = IF R> DROP EXIT THEN
        1 /STRING
    REPEAT
    R> DROP ;

\ MU-SKIP-PAST-CH ( addr len char -- addr' len' )
\   Advance cursor past the first occurrence of char.
\   If char is not found, cursor goes to end.
: MU-SKIP-PAST-CH  ( addr len char -- addr' len' )
    MU-SKIP-UNTIL-CH
    DUP 0> IF 1 /STRING THEN ;

\ _MU-NAME-CHAR? ( c -- flag )
\   Is this character valid in a tag/attribute name?
\   Letters, digits, hyphen, underscore, period, colon.
: _MU-NAME-CHAR?  ( c -- flag )
    DUP 65 >= OVER 90  <= AND IF DROP -1 EXIT THEN   \ A-Z
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN   \ a-z
    DUP 48 >= OVER 57  <= AND IF DROP -1 EXIT THEN   \ 0-9
    DUP 45 = IF DROP -1 EXIT THEN                    \ -
    DUP 95 = IF DROP -1 EXIT THEN                    \ _
    DUP 46 = IF DROP -1 EXIT THEN                    \ .
    58 = IF -1 EXIT THEN                             \ : (namespace)
    0 ;

\ MU-SKIP-NAME ( addr len -- addr' len' )
\   Skip past a tag or attribute name (sequence of name chars).
: MU-SKIP-NAME  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ _MU-NAME-CHAR?
        0= IF EXIT THEN
        1 /STRING
    REPEAT ;

\ MU-GET-NAME ( addr len -- addr' len' name-a name-u )
\   Extract a name: scan name chars, return both the advanced
\   cursor and the name string.
: MU-GET-NAME  ( addr len -- addr' len' name-a name-u )
    OVER >R                          \ save start
    MU-SKIP-NAME
    OVER R> TUCK -                   ( addr' len' name-a name-u )
    ;

\ MU-SKIP-QUOTED ( addr len -- addr' len' )
\   Skip a quoted string: "..." or '...'.
\   addr must point at the opening quote character.
\   Cursor ends up just past the closing quote.
: MU-SKIP-QUOTED  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ DUP 34 = SWAP 39 = OR 0= IF EXIT THEN  \ not " or '
    OVER C@                          \ save quote char
    >R 1 /STRING                     \ skip opening quote
    R> MU-SKIP-PAST-CH ;             \ skip to and past closing quote

\ MU-GET-QUOTED ( addr len -- addr' len' val-a val-u )
\   Extract the inner bytes of a quoted string (without quotes).
\   addr must point at the opening quote.
\   Returns: cursor past closing quote, value string (zero-copy).
VARIABLE _MQ-VA
VARIABLE _MQ-VL

: MU-GET-QUOTED  ( addr len -- addr' len' val-a val-u )
    DUP 0> 0= IF 0 0 EXIT THEN
    OVER C@                          \ quote char
    >R 1 /STRING                     \ skip opening quote
    OVER _MQ-VA !                    \ save value start
    R> MU-SKIP-UNTIL-CH              \ find closing quote
    \ compute value length
    OVER _MQ-VA @ -  _MQ-VL !       \ val-len = current - start
    \ skip past closing quote
    DUP 0> IF 1 /STRING THEN
    _MQ-VA @ _MQ-VL @ ;

\ ── String comparison helpers ────────────────────────────────────────
\ Now provided by REQUIRE string.f → STR-STR=, STR-STRI=

\ =====================================================================
\  Layer 1 — Tag Detection & Classification
\ =====================================================================

\ Type constants
0 CONSTANT MU-T-TEXT         \ plain text (not a tag)
1 CONSTANT MU-T-OPEN        \ <tag ...>
2 CONSTANT MU-T-CLOSE       \ </tag>
3 CONSTANT MU-T-SELF-CLOSE  \ <tag .../>
4 CONSTANT MU-T-COMMENT     \ <!-- ... -->
5 CONSTANT MU-T-PI          \ <?target ... ?>
6 CONSTANT MU-T-CDATA       \ <![CDATA[ ... ]]>
7 CONSTANT MU-T-DOCTYPE     \ <!DOCTYPE ...>

\ MU-AT-TAG? ( addr len -- flag )
\   True if cursor is at a '<' character.
: MU-AT-TAG?  ( addr len -- flag )
    DUP 0> IF DROP C@ 60 = EXIT THEN   \ 60 = '<'
    2DROP 0 ;

\ _MU-PEEK2 ( addr len -- c1 c2 | 0 0 )
\   Peek at first two characters.  Returns 0 0 if less than 2 chars.
: _MU-PEEK2  ( addr len -- c1 c2 )
    DUP 2 < IF 2DROP 0 0 EXIT THEN
    OVER C@  SWAP DROP  SWAP 1+ C@ ;

\ MU-TAG-TYPE ( addr len -- type )
\   Classify what kind of tag starts at cursor.
\   Cursor must be AT the '<'.  Returns MU-T-TEXT if not at a tag.
\
\   Detection logic:
\     not '<'             → MU-T-TEXT
\     <!--                → MU-T-COMMENT
\     <![CDATA[           → MU-T-CDATA
\     <!DOCTYPE / <!doctype → MU-T-DOCTYPE
\     <?                  → MU-T-PI
\     </                  → MU-T-CLOSE
\     <name .../>         → MU-T-SELF-CLOSE  (scan needed)
\     <name ...>          → MU-T-OPEN
VARIABLE _MTT-A   VARIABLE _MTT-L

: MU-TAG-TYPE  ( addr len -- type )
    DUP 0> 0= IF 2DROP MU-T-TEXT EXIT THEN
    OVER C@ 60 <> IF 2DROP MU-T-TEXT EXIT THEN  \ not '<'

    \ save addr for multi-byte peeks
    OVER _MTT-A !

    \ check <!-- (comment)
    DUP 4 >= IF
        _MTT-A @     C@ 60  =           \ <
        _MTT-A @ 1+  C@ 33  = AND       \ !
        _MTT-A @ 2 + C@ 45  = AND       \ -
        _MTT-A @ 3 + C@ 45  = AND       \ -
        IF 2DROP MU-T-COMMENT EXIT THEN
    THEN

    \ check <![CDATA[
    DUP 9 >= IF
        _MTT-A @     C@ 60  =           \ <
        _MTT-A @ 1+  C@ 33  = AND       \ !
        _MTT-A @ 2 + C@ 91  = AND       \ [
        _MTT-A @ 3 + C@ 67  = AND       \ C
        _MTT-A @ 4 + C@ 68  = AND       \ D
        _MTT-A @ 5 + C@ 65  = AND       \ A
        _MTT-A @ 6 + C@ 84  = AND       \ T
        _MTT-A @ 7 + C@ 65  = AND       \ A
        _MTT-A @ 8 + C@ 91  = AND       \ [
        IF 2DROP MU-T-CDATA EXIT THEN
    THEN

    \ check <!DOCTYPE (case-insensitive on DOCTYPE)
    DUP 10 >= IF
        _MTT-A @     C@ 60  =                   \ <
        _MTT-A @ 1+  C@ 33  = AND               \ !
        IF
            _MTT-A @ 2 + C@ _STR-LC 100 =   \ d
            _MTT-A @ 3 + C@ _STR-LC 111 = AND \ o
            _MTT-A @ 4 + C@ _STR-LC  99 = AND \ c
            _MTT-A @ 5 + C@ _STR-LC 116 = AND \ t
            _MTT-A @ 6 + C@ _STR-LC 121 = AND \ y
            _MTT-A @ 7 + C@ _STR-LC 112 = AND \ p
            _MTT-A @ 8 + C@ _STR-LC 101 = AND \ e
            IF 2DROP MU-T-DOCTYPE EXIT THEN
        THEN
    THEN

    \ check <? (processing instruction)
    DUP 2 >= IF
        _MTT-A @     C@ 60 =            \ <
        _MTT-A @ 1+  C@ 63 = AND        \ ?
        IF 2DROP MU-T-PI EXIT THEN
    THEN

    \ check </ (closing tag)
    DUP 2 >= IF
        _MTT-A @     C@ 60 =            \ <
        _MTT-A @ 1+  C@ 47 = AND        \ /
        IF 2DROP MU-T-CLOSE EXIT THEN
    THEN

    \ Must be <name...> or <name.../>
    \ Scan forward to find > and check if preceded by /
    1 /STRING                        \ skip '<'
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 62 = IF         \ '>'
            DROP
            \ check if previous char was '/'
            OVER 1- C@ 47 = IF
                2DROP MU-T-SELF-CLOSE EXIT
            THEN
            2DROP MU-T-OPEN EXIT
        THEN
        DUP 34 = IF                  \ '"' — skip double-quoted
            DROP MU-SKIP-QUOTED
        ELSE
            39 = IF                  \ '\'' — skip single-quoted
                MU-SKIP-QUOTED
            ELSE
                1 /STRING
            THEN
        THEN
    REPEAT
    2DROP MU-T-TEXT ;                \ malformed — no closing >

\ =====================================================================
\  Layer 2 — Tag Scanning
\ =====================================================================

\ MU-SKIP-TAG ( addr len -- addr' len' )
\   Skip one complete tag: <...>.
\   Handles quoted attributes so '>' inside quotes doesn't stop early.
\   If not at '<', does nothing.
: MU-SKIP-TAG  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 60 <> IF EXIT THEN      \ not '<'
    1 /STRING                        \ skip '<'
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 62 = IF         \ '>'
            DROP 1 /STRING EXIT
        THEN
        DUP 34 = IF                  \ '"'
            DROP MU-SKIP-QUOTED
        ELSE
            39 = IF                  \ '\''
                MU-SKIP-QUOTED
            ELSE
                1 /STRING
            THEN
        THEN
    REPEAT ;

\ MU-SKIP-COMMENT ( addr len -- addr' len' )
\   Skip <!-- ... -->.  Cursor must be at '<'.
\   Scans for '-->' end marker.
VARIABLE _MSC-A
: MU-SKIP-COMMENT  ( addr len -- addr' len' )
    DUP 4 < IF EXIT THEN
    4 /STRING                        \ skip '<!--'
    BEGIN
        DUP 0> WHILE
        \ look for '-->'
        DUP 3 >= IF
            OVER _MSC-A !
            _MSC-A @     C@ 45 =     \ -
            _MSC-A @ 1+  C@ 45 = AND \ -
            _MSC-A @ 2 + C@ 62 = AND \ >
            IF 3 /STRING EXIT THEN
        THEN
        1 /STRING
    REPEAT ;

\ MU-SKIP-PI ( addr len -- addr' len' )
\   Skip <?...?>.  Cursor must be at '<'.
VARIABLE _MSP-A
: MU-SKIP-PI  ( addr len -- addr' len' )
    DUP 2 < IF EXIT THEN
    2 /STRING                        \ skip '<?'
    BEGIN
        DUP 0> WHILE
        DUP 2 >= IF
            OVER _MSP-A !
            _MSP-A @     C@ 63 =     \ ?
            _MSP-A @ 1+  C@ 62 = AND \ >
            IF 2 /STRING EXIT THEN
        THEN
        1 /STRING
    REPEAT ;

\ MU-SKIP-CDATA ( addr len -- addr' len' )
\   Skip <![CDATA[...]]>.  Cursor must be at '<'.
VARIABLE _MSD-A
: MU-SKIP-CDATA  ( addr len -- addr' len' )
    DUP 9 < IF EXIT THEN
    9 /STRING                        \ skip '<![CDATA['
    BEGIN
        DUP 0> WHILE
        DUP 3 >= IF
            OVER _MSD-A !
            _MSD-A @     C@ 93 =     \ ]
            _MSD-A @ 1+  C@ 93 = AND \ ]
            _MSD-A @ 2 + C@ 62 = AND \ >
            IF 3 /STRING EXIT THEN
        THEN
        1 /STRING
    REPEAT ;

\ MU-SKIP-TO-TAG ( addr len -- addr' len' )
\   Skip text content, stopping at the next '<' (or end of input).
: MU-SKIP-TO-TAG  ( addr len -- addr' len' )
    60 MU-SKIP-UNTIL-CH ;           \ '<'

\ MU-GET-TEXT ( addr len -- addr' len' txt-a txt-u )
\   Extract text content before the next '<'.
\   Returns cursor advanced past text, and the text string.
VARIABLE _MGT-A
: MU-GET-TEXT  ( addr len -- addr' len' txt-a txt-u )
    OVER _MGT-A !
    MU-SKIP-TO-TAG
    OVER _MGT-A @ -                  \ txt-len = new-addr - old-addr
    _MGT-A @ SWAP ;                  \ ( addr' len' txt-a txt-u )

\ MU-GET-TAG-NAME ( addr len -- addr' len' name-a name-u )
\   Extract the tag name from a tag.
\   Works for open, close, self-close tags.
\   Cursor must be at '<'.
\   After: cursor past tag name, name string returned.
: MU-GET-TAG-NAME  ( addr len -- addr' len' name-a name-u )
    DUP 0> 0= IF 0 0 EXIT THEN
    1 /STRING                        \ skip '<'
    \ skip '/' for close tags
    DUP 0> IF
        OVER C@ 47 = IF 1 /STRING THEN
    THEN
    MU-SKIP-WS
    MU-GET-NAME ;

\ MU-GET-TAG-BODY ( addr len -- body-a body-u )
\   Extract everything between '<' and '>'.
\   Returns the inner content (e.g. "div class=\"x\"").
\   Does NOT advance the cursor — returns a slice.
VARIABLE _MGB-A
: MU-GET-TAG-BODY  ( addr len -- body-a body-u )
    DUP 0> 0= IF 0 0 EXIT THEN
    1 /STRING                        \ skip '<'
    OVER _MGB-A !                    \ save inner start
    \ scan forward for '>'
    BEGIN
        DUP 0> WHILE
        OVER C@ 62 = IF             \ '>'
            OVER _MGB-A @ -          \ body-len
            >R 2DROP _MGB-A @ R> EXIT
        THEN
        OVER C@ DUP 34 = SWAP 39 = OR IF
            MU-SKIP-QUOTED
        ELSE
            1 /STRING
        THEN
    REPEAT
    \ no closing '>' found
    2DROP 0 0 ;

\ =====================================================================
\  Layer 3 — Attribute Parsing
\ =====================================================================

\ Attribute iteration works on the "body" of a tag — the content
\ between '<' and '>'.  Typically obtained via MU-GET-TAG-BODY, then
\ MU-SKIP-NAME to skip past the tag name, leaving the attribute area.
\
\ MU-ATTR-NEXT iterates attributes one at a time:
\   name="value"     → name + inner value (without quotes)
\   name='value'     → same
\   name=value       → bare value (scan to space or > or /)
\   name             → bare attribute (value is 0 0)

\ Variables for returning multi-value results
VARIABLE _MAN-NA  VARIABLE _MAN-NL   \ attribute name
VARIABLE _MAN-VA  VARIABLE _MAN-VL   \ attribute value

\ MU-ATTR-NEXT ( a u -- a' u' na nl va vl flag )
\   Parse one attribute from the body cursor.
\   Returns: advanced cursor, name (na nl), value (va vl), flag.
\   flag = -1 if an attribute was found, 0 if none left.
\   If bare attribute (no =value), va vl = 0 0.
: MU-ATTR-NEXT  ( a u -- a' u' na nl va vl flag )
    MU-SKIP-WS
    \ end of body?  Check for end-of-input, '>', '/'
    DUP 0= IF 0 0 0 0 0 EXIT THEN
    OVER C@ DUP 62 = SWAP 47 = OR IF   \ '>' or '/'
        0 0 0 0 0 EXIT
    THEN
    \ extract attribute name
    MU-GET-NAME
    _MAN-NL !  _MAN-NA !
    \ check for '='
    MU-SKIP-WS
    DUP 0> IF
        OVER C@ 61 = IF             \ '='
            1 /STRING                \ skip '='
            MU-SKIP-WS
            \ check if quoted
            DUP 0> IF
                OVER C@ DUP 34 = SWAP 39 = OR IF
                    MU-GET-QUOTED
                    _MAN-VL !  _MAN-VA !
                ELSE
                    \ bare value — scan to space, >, /
                    OVER _MAN-VA !
                    BEGIN
                        DUP 0> WHILE
                        OVER C@ DUP 32 <=       \ ws
                        OVER 62 = OR            \ >
                        SWAP 47 = OR            \ /
                        IF
                            OVER _MAN-VA @ -  _MAN-VL !
                            _MAN-NA @ _MAN-NL @
                            _MAN-VA @ _MAN-VL @
                            -1 EXIT
                        THEN
                        1 /STRING
                    REPEAT
                    \ ran off end — value is rest of string
                    OVER _MAN-VA @ -  _MAN-VL !
                THEN
            ELSE
                0 _MAN-VA !  0 _MAN-VL !
            THEN
        ELSE
            \ bare attribute (no =)
            0 _MAN-VA !  0 _MAN-VL !
        THEN
    ELSE
        0 _MAN-VA !  0 _MAN-VL !
    THEN
    _MAN-NA @ _MAN-NL @  _MAN-VA @ _MAN-VL @  -1 ;

\ MU-ATTR-FIND ( body-a body-u attr-a attr-u -- val-a val-u flag )
\   Find an attribute by name in a tag body.
\   Returns value string and flag (-1 found, 0 not found).
\   body cursor should point PAST the tag name.
VARIABLE _MAF-SA  VARIABLE _MAF-SL   \ search name

: MU-ATTR-FIND  ( body-a body-u attr-a attr-u -- val-a val-u flag )
    _MAF-SL !  _MAF-SA !
    BEGIN
        MU-ATTR-NEXT                 \ ( a' u' na nl va vl flag )
        DUP 0= IF                   \ no more attrs
            \ stack: a' u' na nl va vl 0
            >R 2DROP 2DROP 2DROP R>  \ ( 0 )
            0 0 ROT EXIT             \ ( 0 0 0 )
        THEN
        DROP                         \ drop flag
        \ ( a' u' na nl va vl )
        2>R                          \ save value  R: va vl
        _MAF-SA @ _MAF-SL @ STR-STR=
        IF                           \ name matches
            2DROP                    \ drop cursor
            2R> -1 EXIT              \ ( va vl -1 )
        THEN
        2R> 2DROP                    \ discard value, continue
    AGAIN ;

\ MU-ATTR-HAS? ( body-a body-u attr-a attr-u -- flag )
\   Does this tag body have the named attribute?
: MU-ATTR-HAS?  ( body-a body-u attr-a attr-u -- flag )
    MU-ATTR-FIND                     \ ( val-a val-u flag )
    >R 2DROP R> ;

\ =====================================================================
\  Layer 4 — Entity Decoding
\ =====================================================================

\ MU-DECODE-ENTITY ( addr len -- char addr' len' )
\   Decode one &...; entity starting at '&'.
\   Handles:
\     &amp; &lt; &gt; &quot; &apos;    (XML built-ins)
\     &#60;                            (decimal numeric)
\     &#x3C;                           (hex numeric)
\   If unrecognised, returns '&' and advances 1 char.

VARIABLE _MDE-A
VARIABLE _MDE-B    \ current position for named entity checks
VARIABLE _MDE-ACC  \ accumulator for numeric entities

: _MU-DIGIT?  ( c -- n flag )
    DUP 48 >= OVER 57 <= AND IF 48 - -1 EXIT THEN
    0 ;

: _MU-HEXDIG?  ( c -- n flag )
    DUP 48 >= OVER 57 <= AND IF 48 - -1 EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - -1 EXIT THEN   \ A-F
    DUP 97 >= OVER 102 <= AND IF 87 - -1 EXIT THEN  \ a-f
    0 ;

: MU-DECODE-ENTITY  ( addr len -- char addr' len' )
    DUP 0> 0= IF 0 EXIT THEN
    OVER C@ 38 <> IF                 \ not '&'
        OVER C@ -ROT 1 /STRING EXIT \ return char as-is
    THEN
    OVER _MDE-A !                    \ save '&' position
    1 /STRING                        \ skip '&'

    \ &#  (numeric)
    DUP 0> IF OVER C@ 35 = IF       \ '#'
        1 /STRING                    \ skip '#'
        \ &#x (hex)
        DUP 0> IF OVER C@ DUP 120 = SWAP 88 = OR IF
            1 /STRING                \ skip 'x'
            0 _MDE-ACC !
            BEGIN
                DUP 0> WHILE
                OVER C@ DUP 59 = IF \ ';'
                    DROP 1 /STRING
                    _MDE-ACC @ -ROT EXIT
                THEN
                _MU-HEXDIG? IF
                    _MDE-ACC @ 16 * + _MDE-ACC !
                    1 /STRING
                ELSE
                    DROP
                    _MDE-ACC @ -ROT EXIT
                THEN
            REPEAT
            _MDE-ACC @ -ROT EXIT
        THEN THEN
        \ &#DD (decimal)
        0 _MDE-ACC !
        BEGIN
            DUP 0> WHILE
            OVER C@ DUP 59 = IF     \ ';'
                DROP 1 /STRING
                _MDE-ACC @ -ROT EXIT
            THEN
            _MU-DIGIT? IF
                _MDE-ACC @ 10 * + _MDE-ACC !
                1 /STRING
            ELSE
                DROP
                _MDE-ACC @ -ROT EXIT
            THEN
        REPEAT
        _MDE-ACC @ -ROT EXIT
    THEN THEN

    \ Named entities — save position for multi-byte checks
    DUP 2 < IF 38 EXIT THEN         \ too short, return '&'
    OVER _MDE-B !                    \ save current addr
    OVER C@
    DUP 97 = IF                      \ 'a' — amp or apos
        DROP
        \ check amp;  (a=97 m=109 p=112 ;=59)
        DUP 4 >= IF
            _MDE-B @     C@ 97  =
            _MDE-B @ 1+  C@ 109 = AND
            _MDE-B @ 2 + C@ 112 = AND
            _MDE-B @ 3 + C@ 59  = AND
            IF 38 -ROT 4 /STRING EXIT THEN   \ '&'
        THEN
        \ check apos;  (a=97 p=112 o=111 s=115 ;=59)
        DUP 5 >= IF
            _MDE-B @     C@ 97  =
            _MDE-B @ 1+  C@ 112 = AND
            _MDE-B @ 2 + C@ 111 = AND
            _MDE-B @ 3 + C@ 115 = AND
            _MDE-B @ 4 + C@ 59  = AND
            IF 39 -ROT 5 /STRING EXIT THEN   \ '\''
        THEN
        38 -ROT EXIT                 \ unrecognised, return '&'
    THEN

    DUP 108 = IF                     \ 'l' — lt  (l=108 t=116 ;=59)
        DROP
        DUP 3 >= IF
            _MDE-B @     C@ 108 =
            _MDE-B @ 1+  C@ 116 = AND
            _MDE-B @ 2 + C@ 59  = AND
            IF 60 -ROT 3 /STRING EXIT THEN   \ '<'
        THEN
        38 -ROT EXIT
    THEN

    DUP 103 = IF                     \ 'g' — gt  (g=103 t=116 ;=59)
        DROP
        DUP 3 >= IF
            _MDE-B @     C@ 103 =
            _MDE-B @ 1+  C@ 116 = AND
            _MDE-B @ 2 + C@ 59  = AND
            IF 62 -ROT 3 /STRING EXIT THEN   \ '>'
        THEN
        38 -ROT EXIT
    THEN

    113 = IF                         \ 'q' — quot (q=113 u=117 o=111 t=116 ;=59)
        DUP 5 >= IF
            _MDE-B @     C@ 113 =
            _MDE-B @ 1+  C@ 117 = AND
            _MDE-B @ 2 + C@ 111 = AND
            _MDE-B @ 3 + C@ 116 = AND
            _MDE-B @ 4 + C@ 59  = AND
            IF 34 -ROT 5 /STRING EXIT THEN   \ '"'
        THEN
        38 -ROT EXIT
    THEN

    \ unrecognised entity — return '&', cursor stays after '&'
    38 -ROT ;

\ MU-UNESCAPE ( src slen dest dmax -- len )
\   Decode all entities from src into dest buffer.
\   Returns number of bytes written.
\   Stops at end of src or when dest is full.
VARIABLE _MUE-D   VARIABLE _MUE-N   VARIABLE _MUE-MAX

: MU-UNESCAPE  ( src slen dest dmax -- len )
    _MUE-MAX !  _MUE-D !  0 _MUE-N !
    BEGIN
        DUP 0> WHILE
        _MUE-N @ _MUE-MAX @ >= IF 2DROP _MUE-N @ EXIT THEN
        OVER C@ 38 = IF             \ '&'
            MU-DECODE-ENTITY         \ ( char addr' len' )
            ROT                      \ ( addr' len' char )
            _MUE-D @ _MUE-N @ + C!
            1 _MUE-N +!
        ELSE
            OVER C@
            _MUE-D @ _MUE-N @ + C!
            1 _MUE-N +!
            1 /STRING
        THEN
    REPEAT
    2DROP _MUE-N @ ;

\ =====================================================================
\  Layer 5 — Element Navigation (depth-aware)
\ =====================================================================

\ MU-ENTER ( addr len -- addr' len' )
\   Skip past the opening tag.  Cursor must be at '<'.
\   After: cursor is at the content inside the element.
: MU-ENTER  ( addr len -- addr' len' )
    MU-SKIP-TAG ;

\ MU-SKIP-ELEMENT ( addr len -- addr' len' )
\   Skip an entire element including its content and closing tag.
\   Cursor must be at an opening '<'.
\   Handles nested elements via depth tracking.
\   For self-closing tags, just skips the tag.
VARIABLE _MSE-D    \ depth counter
VARIABLE _MSE-NA   VARIABLE _MSE-NL   \ tag name saved

: MU-SKIP-ELEMENT  ( addr len -- addr' len' )
    \ classify what we're at
    2DUP MU-TAG-TYPE
    DUP MU-T-SELF-CLOSE = IF DROP MU-SKIP-TAG EXIT THEN
    DUP MU-T-COMMENT    = IF DROP MU-SKIP-COMMENT EXIT THEN
    DUP MU-T-PI         = IF DROP MU-SKIP-PI EXIT THEN
    DUP MU-T-CDATA      = IF DROP MU-SKIP-CDATA EXIT THEN
    MU-T-OPEN <> IF EXIT THEN       \ not an open tag, do nothing

    1 _MSE-D !                       \ depth = 1
    MU-SKIP-TAG                      \ skip the opening tag
    BEGIN
        _MSE-D @ 0> WHILE
        DUP 0> 0= IF EXIT THEN      \ ran out of input
        2DUP MU-TAG-TYPE
        DUP MU-T-OPEN = IF
            DROP 1 _MSE-D +!
            MU-SKIP-TAG
        ELSE DUP MU-T-CLOSE = IF
            DROP -1 _MSE-D +!
            MU-SKIP-TAG
        ELSE DUP MU-T-SELF-CLOSE = IF
            DROP MU-SKIP-TAG
        ELSE DUP MU-T-COMMENT = IF
            DROP MU-SKIP-COMMENT
        ELSE DUP MU-T-PI = IF
            DROP MU-SKIP-PI
        ELSE DUP MU-T-CDATA = IF
            DROP MU-SKIP-CDATA
        ELSE
            DROP MU-SKIP-TO-TAG      \ skip text
        THEN THEN THEN THEN THEN THEN
    REPEAT ;

\ MU-FIND-CLOSE ( addr len name-a name-u -- addr' len' )
\   Find the matching closing tag </name> for the given name.
\   Depth-aware: tracks nested elements with the same name.
\   Cursor should be INSIDE the element (past the opening tag).
VARIABLE _MFC-NA   VARIABLE _MFC-NL
VARIABLE _MFC-D
VARIABLE _MFC-TA   VARIABLE _MFC-TL   \ temp tag name

: MU-FIND-CLOSE  ( addr len name-a name-u -- addr' len' )
    _MFC-NL !  _MFC-NA !
    1 _MFC-D !                       \ depth = 1
    BEGIN
        _MFC-D @ 0> WHILE
        DUP 0> 0= IF EXIT THEN      \ end of input
        2DUP MU-TAG-TYPE
        DUP MU-T-OPEN = IF
            DROP
            2DUP MU-GET-TAG-NAME  _MFC-TL !  _MFC-TA !  2DROP
            _MFC-TA @ _MFC-TL @ _MFC-NA @ _MFC-NL @ STR-STR= IF
                1 _MFC-D +!
            THEN
            MU-SKIP-TAG
        ELSE DUP MU-T-CLOSE = IF
            DROP
            2DUP MU-GET-TAG-NAME  _MFC-TL !  _MFC-TA !  2DROP
            _MFC-TA @ _MFC-TL @ _MFC-NA @ _MFC-NL @ STR-STR= IF
                -1 _MFC-D +!
            THEN
            _MFC-D @ 0> IF MU-SKIP-TAG THEN
        ELSE DUP MU-T-SELF-CLOSE = IF
            DROP MU-SKIP-TAG
        ELSE DUP MU-T-COMMENT = IF
            DROP MU-SKIP-COMMENT
        ELSE DUP MU-T-PI = IF
            DROP MU-SKIP-PI
        ELSE DUP MU-T-CDATA = IF
            DROP MU-SKIP-CDATA
        ELSE
            DROP MU-SKIP-TO-TAG
        THEN THEN THEN THEN THEN THEN
    REPEAT ;

\ MU-INNER ( addr len -- inner-a inner-u )
\   Extract the content between the opening and closing tags.
\   Cursor must be at the opening '<tag...>'.
\   Returns the inner content (everything between > and </tag>).
VARIABLE _MI-A
VARIABLE _MI-NA  VARIABLE _MI-NL

: MU-INNER  ( addr len -- inner-a inner-u )
    \ get tag name
    2DUP MU-GET-TAG-NAME  _MI-NL !  _MI-NA !  2DROP
    \ skip past opening tag
    MU-SKIP-TAG
    OVER _MI-A !                     \ save inner start
    \ find matching close
    _MI-NA @ _MI-NL @  MU-FIND-CLOSE
    \ cursor is now at </tag>, inner ends here
    OVER _MI-A @ -                   \ inner-len = current - start
    _MI-A @ SWAP ;

\ MU-NEXT-SIBLING ( addr len -- addr' len' flag )
\   Skip to the next sibling element.
\   Cursor must be at an element's opening tag.
\   Skips the current element, then any text/ws, stops at next tag.
\   flag = -1 if a sibling found, 0 if end reached.
: MU-NEXT-SIBLING  ( addr len -- addr' len' flag )
    MU-SKIP-ELEMENT                  \ skip current element
    MU-SKIP-WS                      \ skip whitespace
    MU-SKIP-TO-TAG                  \ skip any remaining text
    DUP 0> IF
        2DUP MU-AT-TAG? IF
            -1
        ELSE
            0
        THEN
    ELSE
        0
    THEN ;

\ MU-FIND-TAG ( addr len name-a name-u -- addr' len' flag )
\   Find next opening tag with the given name at the SAME depth.
\   Skips over non-matching elements entirely.
\   flag = -1 if found, 0 if not.
VARIABLE _MFT-NA  VARIABLE _MFT-NL
VARIABLE _MFT-TA  VARIABLE _MFT-TL

: MU-FIND-TAG  ( addr len name-a name-u -- addr' len' flag )
    _MFT-NL !  _MFT-NA !
    BEGIN
        DUP 0> WHILE
        MU-SKIP-WS
        MU-SKIP-TO-TAG
        DUP 0= IF 0 EXIT THEN
        2DUP MU-TAG-TYPE
        DUP MU-T-OPEN = OVER MU-T-SELF-CLOSE = OR IF
            DROP
            2DUP MU-GET-TAG-NAME _MFT-TL ! _MFT-TA ! 2DROP
            _MFT-TA @ _MFT-TL @  _MFT-NA @ _MFT-NL @  STR-STR= IF
                -1 EXIT              \ found it
            THEN
            MU-SKIP-ELEMENT          \ skip non-matching element
        ELSE DUP MU-T-CLOSE = IF
            \ hit a closing tag at our level — no more siblings
            DROP 0 EXIT
        ELSE DUP MU-T-COMMENT = IF
            DROP MU-SKIP-COMMENT
        ELSE DUP MU-T-PI = IF
            DROP MU-SKIP-PI
        ELSE
            DROP MU-SKIP-TAG         \ skip whatever it is
        THEN THEN THEN THEN
    REPEAT
    0 ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _mkcore-guard

' MU-FAIL         CONSTANT _mu-fail-xt
' MU-OK?          CONSTANT _mu-ok-q-xt
' MU-CLEAR-ERR    CONSTANT _mu-clear-err-xt
' MU-SKIP-WS      CONSTANT _mu-skip-ws-xt
' MU-SKIP-UNTIL-CH CONSTANT _mu-skip-until-ch-xt
' MU-SKIP-PAST-CH CONSTANT _mu-skip-past-ch-xt
' MU-SKIP-NAME    CONSTANT _mu-skip-name-xt
' MU-GET-NAME     CONSTANT _mu-get-name-xt
' MU-SKIP-QUOTED  CONSTANT _mu-skip-quoted-xt
' MU-GET-QUOTED   CONSTANT _mu-get-quoted-xt
' MU-AT-TAG?      CONSTANT _mu-at-tag-q-xt
' MU-TAG-TYPE     CONSTANT _mu-tag-type-xt
' MU-SKIP-TAG     CONSTANT _mu-skip-tag-xt
' MU-SKIP-COMMENT CONSTANT _mu-skip-comment-xt
' MU-SKIP-PI      CONSTANT _mu-skip-pi-xt
' MU-SKIP-CDATA   CONSTANT _mu-skip-cdata-xt
' MU-SKIP-TO-TAG  CONSTANT _mu-skip-to-tag-xt
' MU-GET-TEXT     CONSTANT _mu-get-text-xt
' MU-GET-TAG-NAME CONSTANT _mu-get-tag-name-xt
' MU-GET-TAG-BODY CONSTANT _mu-get-tag-body-xt
' MU-ATTR-NEXT    CONSTANT _mu-attr-next-xt
' MU-ATTR-FIND    CONSTANT _mu-attr-find-xt
' MU-ATTR-HAS?    CONSTANT _mu-attr-has-q-xt
' MU-DECODE-ENTITY CONSTANT _mu-decode-entity-xt
' MU-UNESCAPE     CONSTANT _mu-unescape-xt
' MU-ENTER        CONSTANT _mu-enter-xt
' MU-SKIP-ELEMENT CONSTANT _mu-skip-element-xt
' MU-FIND-CLOSE   CONSTANT _mu-find-close-xt
' MU-INNER        CONSTANT _mu-inner-xt
' MU-NEXT-SIBLING CONSTANT _mu-next-sibling-xt
' MU-FIND-TAG     CONSTANT _mu-find-tag-xt

: MU-FAIL         _mu-fail-xt _mkcore-guard WITH-GUARD ;
: MU-OK?          _mu-ok-q-xt _mkcore-guard WITH-GUARD ;
: MU-CLEAR-ERR    _mu-clear-err-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-WS      _mu-skip-ws-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-UNTIL-CH _mu-skip-until-ch-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-PAST-CH _mu-skip-past-ch-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-NAME    _mu-skip-name-xt _mkcore-guard WITH-GUARD ;
: MU-GET-NAME     _mu-get-name-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-QUOTED  _mu-skip-quoted-xt _mkcore-guard WITH-GUARD ;
: MU-GET-QUOTED   _mu-get-quoted-xt _mkcore-guard WITH-GUARD ;
: MU-AT-TAG?      _mu-at-tag-q-xt _mkcore-guard WITH-GUARD ;
: MU-TAG-TYPE     _mu-tag-type-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-TAG     _mu-skip-tag-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-COMMENT _mu-skip-comment-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-PI      _mu-skip-pi-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-CDATA   _mu-skip-cdata-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-TO-TAG  _mu-skip-to-tag-xt _mkcore-guard WITH-GUARD ;
: MU-GET-TEXT     _mu-get-text-xt _mkcore-guard WITH-GUARD ;
: MU-GET-TAG-NAME _mu-get-tag-name-xt _mkcore-guard WITH-GUARD ;
: MU-GET-TAG-BODY _mu-get-tag-body-xt _mkcore-guard WITH-GUARD ;
: MU-ATTR-NEXT    _mu-attr-next-xt _mkcore-guard WITH-GUARD ;
: MU-ATTR-FIND    _mu-attr-find-xt _mkcore-guard WITH-GUARD ;
: MU-ATTR-HAS?    _mu-attr-has-q-xt _mkcore-guard WITH-GUARD ;
: MU-DECODE-ENTITY _mu-decode-entity-xt _mkcore-guard WITH-GUARD ;
: MU-UNESCAPE     _mu-unescape-xt _mkcore-guard WITH-GUARD ;
: MU-ENTER        _mu-enter-xt _mkcore-guard WITH-GUARD ;
: MU-SKIP-ELEMENT _mu-skip-element-xt _mkcore-guard WITH-GUARD ;
: MU-FIND-CLOSE   _mu-find-close-xt _mkcore-guard WITH-GUARD ;
: MU-INNER        _mu-inner-xt _mkcore-guard WITH-GUARD ;
: MU-NEXT-SIBLING _mu-next-sibling-xt _mkcore-guard WITH-GUARD ;
: MU-FIND-TAG     _mu-find-tag-xt _mkcore-guard WITH-GUARD ;
[THEN] [THEN]
