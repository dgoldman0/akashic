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

\ _MU-STR= ( s1 l1 s2 l2 -- flag )
\   Case-sensitive string comparison.
: _MU-STR=  ( s1 l1 s2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 DO
        OVER I + C@  OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ _MU-TOLOWER ( c -- c' )
\   Convert A-Z to a-z; other chars unchanged.
: _MU-TOLOWER  ( c -- c' )
    DUP 65 >= OVER 90 <= AND IF 32 + THEN ;

\ _MU-STRI= ( s1 l1 s2 l2 -- flag )
\   Case-insensitive string comparison.
: _MU-STRI=  ( s1 l1 s2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 DO
        OVER I + C@ _MU-TOLOWER
        OVER I + C@ _MU-TOLOWER
        <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

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
            _MTT-A @ 2 + C@ _MU-TOLOWER 100 =   \ d
            _MTT-A @ 3 + C@ _MU-TOLOWER 111 = AND \ o
            _MTT-A @ 4 + C@ _MU-TOLOWER  99 = AND \ c
            _MTT-A @ 5 + C@ _MU-TOLOWER 116 = AND \ t
            _MTT-A @ 6 + C@ _MU-TOLOWER 121 = AND \ y
            _MTT-A @ 7 + C@ _MU-TOLOWER 112 = AND \ p
            _MTT-A @ 8 + C@ _MU-TOLOWER 101 = AND \ e
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
