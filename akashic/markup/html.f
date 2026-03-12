\ html.f — HTML5 reader & builder vocabulary
\
\ Builds on akashic-markup-core for HTML5-specific parsing.
\ Case-insensitive tag matching.  Void-element aware.
\ Raw-text elements (script, style) are handled specially.
\
\ Prefix: HTML-   (public API)
\         _HTML-  (internal helpers)
\
\ Load with:   REQUIRE html.f

PROVIDED akashic-html
REQUIRE core.f

\ =====================================================================
\  Void Elements
\ =====================================================================
\
\ HTML5 void elements never have a closing tag.
\ Both <br> and <br/> are valid.  <br></br> is NOT valid HTML5.
\ Table: 14 entries, 9 bytes each (1-byte len + 8-byte name).

CREATE _HV-TBL
 4 C, 97 C, 114 C, 101 C, 97 C,   0 C, 0 C, 0 C, 0 C,  \ area
 4 C, 98 C, 97 C, 115 C, 101 C,   0 C, 0 C, 0 C, 0 C,  \ base
 2 C, 98 C, 114 C,  0 C,  0 C,    0 C, 0 C, 0 C, 0 C,  \ br
 3 C, 99 C, 111 C, 108 C,  0 C,   0 C, 0 C, 0 C, 0 C,  \ col
 5 C, 101 C, 109 C, 98 C, 101 C, 100 C, 0 C, 0 C, 0 C, \ embed
 2 C, 104 C, 114 C,  0 C,  0 C,   0 C, 0 C, 0 C, 0 C,  \ hr
 3 C, 105 C, 109 C, 103 C,  0 C,  0 C, 0 C, 0 C, 0 C,  \ img
 5 C, 105 C, 110 C, 112 C, 117 C, 116 C, 0 C, 0 C, 0 C, \ input
 4 C, 108 C, 105 C, 110 C, 107 C, 0 C, 0 C, 0 C, 0 C,  \ link
 4 C, 109 C, 101 C, 116 C, 97 C,  0 C, 0 C, 0 C, 0 C,  \ meta
 5 C, 112 C, 97 C, 114 C, 97 C, 109 C, 0 C, 0 C, 0 C,  \ param
 6 C, 115 C, 111 C, 117 C, 114 C, 99 C, 101 C, 0 C, 0 C, \ source
 5 C, 116 C, 114 C, 97 C, 99 C, 107 C, 0 C, 0 C, 0 C,  \ track
 3 C, 119 C, 98 C, 114 C,  0 C,   0 C, 0 C, 0 C, 0 C,  \ wbr
14 CONSTANT _HV-COUNT
 9 CONSTANT _HV-ENTRY-SIZE

VARIABLE _HV-NA   VARIABLE _HV-NL

\ HTML-VOID? ( name-a name-u -- flag )
\   Is this tag name a void element?  Case-insensitive.
: HTML-VOID?  ( name-a name-u -- flag )
    _HV-NL !  _HV-NA !
    _HV-COUNT 0 DO
        _HV-TBL I _HV-ENTRY-SIZE * +
        DUP C@                       \ ( entry-addr entry-len )
        SWAP 1+                      \ ( entry-len entry-name-addr )
        OVER                         \ ( el ena el )
        _HV-NA @ _HV-NL @           \ ( el ena el search-a search-u )
        STR-STRI= IF
            DROP -1 UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 ;

\ =====================================================================
\  Raw Text Elements (script, style)
\ =====================================================================

CREATE _HR-SCRIPT  115 C, 99 C, 114 C, 105 C, 112 C, 116 C,  \ script
CREATE _HR-STYLE   115 C, 116 C, 121 C, 108 C, 101 C,         \ style

\ _HTML-RAW-TEXT? ( name-a name-u -- flag )
\   Is this a raw text element?
: _HTML-RAW-TEXT?  ( name-a name-u -- flag )
    2DUP _HR-SCRIPT 6 STR-STRI= IF 2DROP -1 EXIT THEN
    _HR-STYLE 5 STR-STRI= ;

\ _HTML-FIND-RAW-CLOSE ( addr len name-a name-u -- addr' len' )
\   Scan raw text content for </name> (case-insensitive).
\   Stops AT the </name> tag (does not skip it).
VARIABLE _HFRC-NA  VARIABLE _HFRC-NL

: _HTML-FIND-RAW-CLOSE  ( addr len name-a name-u -- addr' len' )
    _HFRC-NL !  _HFRC-NA !
    BEGIN
        DUP 0> WHILE
        OVER C@ 60 = IF                          \ '<'
            DUP 2 > IF
                OVER 1+ C@ 47 = IF               \ '</'
                    2DUP 2 /STRING MU-GET-NAME    \ ( a u a' u' n-a n-u )
                    _HFRC-NA @ _HFRC-NL @ STR-STRI= IF
                        2DROP EXIT                \ stop AT </name>
                    THEN
                    2DROP                         \ drop a'/u'
                THEN
            THEN
        THEN
        1 /STRING
    REPEAT ;

\ _HTML-SKIP-RAW ( addr len name-a name-u -- addr' len' )
\   Skip raw text content past the </name> closing tag.
: _HTML-SKIP-RAW  ( addr len name-a name-u -- addr' len' )
    _HTML-FIND-RAW-CLOSE
    DUP 0> IF MU-SKIP-TAG THEN ;

\ =====================================================================
\  HTML5-specific Navigation (case-insensitive, void-aware)
\ =====================================================================

\ _HTML-SKIP-ELEMENT ( addr len -- addr' len' )
\   Skip an entire element including content and closing tag.
\   Handles: void elements, raw text elements, case-insensitive
\   close-tag matching, depth tracking.
VARIABLE _HSE-D   VARIABLE _HSE-NA  VARIABLE _HSE-NL

: _HTML-SKIP-ELEMENT  ( addr len -- addr' len' )
    2DUP MU-TAG-TYPE
    DUP MU-T-SELF-CLOSE = IF DROP MU-SKIP-TAG EXIT THEN
    DUP MU-T-COMMENT    = IF DROP MU-SKIP-COMMENT EXIT THEN
    MU-T-OPEN <> IF EXIT THEN

    \ get tag name
    2DUP MU-GET-TAG-NAME _HSE-NL ! _HSE-NA ! 2DROP

    \ void element? just skip the tag
    _HSE-NA @ _HSE-NL @ HTML-VOID? IF
        MU-SKIP-TAG EXIT
    THEN

    \ raw text element? skip tag then scan for </name>
    _HSE-NA @ _HSE-NL @ _HTML-RAW-TEXT? IF
        MU-SKIP-TAG
        _HSE-NA @ _HSE-NL @ _HTML-SKIP-RAW EXIT
    THEN

    \ regular element: depth-track with case-insensitive matching
    1 _HSE-D !
    MU-SKIP-TAG
    BEGIN
        _HSE-D @ 0> WHILE
        DUP 0> 0= IF EXIT THEN
        2DUP MU-TAG-TYPE
        DUP MU-T-OPEN = IF
            DROP
            2DUP MU-GET-TAG-NAME     \ ( a u a' u' n-a n-u )
            2DUP HTML-VOID? IF
                2DROP 2DROP MU-SKIP-TAG
            ELSE 2DUP _HTML-RAW-TEXT? IF
                \ raw text inside our element: skip tag + content
                2>R 2DROP            \ save name, drop a'/u'
                MU-SKIP-TAG
                2R> _HTML-SKIP-RAW
            ELSE
                _HSE-NA @ _HSE-NL @ STR-STRI= IF
                    2DROP 1 _HSE-D +!
                ELSE
                    2DROP
                THEN
                MU-SKIP-TAG
            THEN THEN
        ELSE DUP MU-T-CLOSE = IF
            DROP
            2DUP MU-GET-TAG-NAME     \ ( a u a' u' n-a n-u )
            _HSE-NA @ _HSE-NL @ STR-STRI= IF
                2DROP -1 _HSE-D +!
            ELSE
                2DROP
            THEN
            _HSE-D @ 0> IF MU-SKIP-TAG THEN
        ELSE DUP MU-T-SELF-CLOSE = IF
            DROP MU-SKIP-TAG
        ELSE DUP MU-T-COMMENT = IF
            DROP MU-SKIP-COMMENT
        ELSE
            DROP MU-SKIP-TO-TAG
        THEN THEN THEN THEN
    REPEAT ;

\ _HTML-FIND-TAG ( addr len name-a name-u -- addr' len' flag )
\   Find next opening tag with given name (case-insensitive).
\   Skips non-matching elements (void-aware).
VARIABLE _HFT-NA  VARIABLE _HFT-NL
VARIABLE _HFT-TA  VARIABLE _HFT-TL

: _HTML-FIND-TAG  ( addr len name-a name-u -- addr' len' flag )
    _HFT-NL !  _HFT-NA !
    BEGIN
        DUP 0> WHILE
        MU-SKIP-WS
        MU-SKIP-TO-TAG
        DUP 0= IF 0 EXIT THEN
        2DUP MU-TAG-TYPE
        DUP MU-T-OPEN = OVER MU-T-SELF-CLOSE = OR IF
            DROP
            2DUP MU-GET-TAG-NAME _HFT-TL ! _HFT-TA ! 2DROP
            _HFT-TA @ _HFT-TL @  _HFT-NA @ _HFT-NL @  STR-STRI= IF
                -1 EXIT
            THEN
            _HTML-SKIP-ELEMENT
        ELSE DUP MU-T-CLOSE = IF
            DROP 0 EXIT
        ELSE DUP MU-T-COMMENT = IF
            DROP MU-SKIP-COMMENT
        ELSE
            DROP MU-SKIP-TAG
        THEN THEN THEN
    REPEAT
    0 ;

\ _HTML-FIND-CLOSE ( addr len name-a name-u -- addr' len' )
\   Find matching </name> (case-insensitive, void-aware).
\   Cursor should be INSIDE the element (past opening tag).
\   Handles raw text elements to avoid false matches inside
\   script/style content.
VARIABLE _HFC-NA  VARIABLE _HFC-NL
VARIABLE _HFC-D
VARIABLE _HFC-TA  VARIABLE _HFC-TL

: _HTML-FIND-CLOSE  ( addr len name-a name-u -- addr' len' )
    _HFC-NL !  _HFC-NA !
    1 _HFC-D !
    BEGIN
        _HFC-D @ 0> WHILE
        DUP 0> 0= IF EXIT THEN
        2DUP MU-TAG-TYPE
        DUP MU-T-OPEN = IF
            DROP
            2DUP MU-GET-TAG-NAME _HFC-TL ! _HFC-TA ! 2DROP
            _HFC-TA @ _HFC-TL @  HTML-VOID? IF
                MU-SKIP-TAG
            ELSE _HFC-TA @ _HFC-TL @  _HTML-RAW-TEXT? IF
                \ raw text element: skip tag + content to avoid
                \ false close-tag matches inside script/style
                MU-SKIP-TAG
                _HFC-TA @ _HFC-TL @ _HTML-SKIP-RAW
            ELSE
                _HFC-TA @ _HFC-TL @  _HFC-NA @ _HFC-NL @  STR-STRI= IF
                    1 _HFC-D +!
                THEN
                MU-SKIP-TAG
            THEN THEN
        ELSE DUP MU-T-CLOSE = IF
            DROP
            2DUP MU-GET-TAG-NAME _HFC-TL ! _HFC-TA ! 2DROP
            _HFC-TA @ _HFC-TL @ _HFC-NA @ _HFC-NL @ STR-STRI= IF
                -1 _HFC-D +!
            THEN
            _HFC-D @ 0> IF MU-SKIP-TAG THEN
        ELSE DUP MU-T-SELF-CLOSE = IF
            DROP MU-SKIP-TAG
        ELSE DUP MU-T-COMMENT = IF
            DROP MU-SKIP-COMMENT
        ELSE
            DROP MU-SKIP-TO-TAG
        THEN THEN THEN THEN
    REPEAT ;

\ _HTML-INNER ( addr len -- inner-a inner-u )
\   Extract content between open and close tags.
\   Uses case-insensitive close matching.
\   For raw text elements, scans for </name> in raw content.
VARIABLE _HI-A
VARIABLE _HI-NA  VARIABLE _HI-NL

: _HTML-INNER  ( addr len -- inner-a inner-u )
    2DUP MU-GET-TAG-NAME _HI-NL ! _HI-NA ! 2DROP
    MU-SKIP-TAG
    OVER _HI-A !
    _HI-NA @ _HI-NL @ _HTML-RAW-TEXT? IF
        _HI-NA @ _HI-NL @ _HTML-FIND-RAW-CLOSE
    ELSE
        _HI-NA @ _HI-NL @ _HTML-FIND-CLOSE
    THEN
    OVER _HI-A @ -
    _HI-A @ SWAP ;

\ =====================================================================
\  HTML5 Reader
\ =====================================================================

\ HTML-ENTER ( addr len -- addr' len' )
\   Enter an element: skip past the opening tag.
: HTML-ENTER  ( addr len -- addr' len' )
    MU-ENTER ;

\ HTML-TEXT ( addr len -- txt-a txt-u )
\   Extract text content of the current element.
\   Cursor must be at the opening tag.
: HTML-TEXT  ( addr len -- txt-a txt-u )
    MU-ENTER
    MU-GET-TEXT 2SWAP 2DROP ;

\ HTML-INNER ( addr len -- inner-a inner-u )
\   Extract everything between open and close tags.
: HTML-INNER  ( addr len -- inner-a inner-u )
    _HTML-INNER ;

\ HTML-CHILD ( addr len name-a name-u -- addr' len' )
\   Find a child element by tag name (case-insensitive).
\   Cursor must be at the PARENT's opening tag.
\   Aborts if not found.
VARIABLE _HC-NA   VARIABLE _HC-NL

: HTML-CHILD  ( addr len name-a name-u -- addr' len' )
    _HC-NL !  _HC-NA !
    MU-ENTER
    _HC-NA @ _HC-NL @ _HTML-FIND-TAG
    0= IF MU-E-NOT-FOUND MU-FAIL THEN ;

\ HTML-CHILD? ( addr len name-a name-u -- addr' len' flag )
\   Like HTML-CHILD but returns flag instead of aborting.
: HTML-CHILD?  ( addr len name-a name-u -- addr' len' flag )
    _HC-NL !  _HC-NA !
    MU-ENTER
    _HC-NA @ _HC-NL @ _HTML-FIND-TAG ;

\ HTML-ATTR ( tag-a tag-u attr-a attr-u -- val-a val-u )
\   Get attribute value from a tag.  Cursor at opening '<'.
\   Aborts if attribute not found.
: HTML-ATTR  ( tag-a tag-u attr-a attr-u -- val-a val-u )
    2>R
    MU-GET-TAG-BODY MU-SKIP-NAME
    2R> MU-ATTR-FIND
    0= IF 2DROP MU-E-NOT-FOUND MU-FAIL 0 0 THEN ;

\ HTML-ATTR? ( tag-a tag-u attr-a attr-u -- val-a val-u flag )
\   Like HTML-ATTR but returns flag.
: HTML-ATTR?  ( tag-a tag-u attr-a attr-u -- val-a val-u flag )
    2>R
    MU-GET-TAG-BODY MU-SKIP-NAME
    2R> MU-ATTR-FIND ;

\ HTML-ID ( addr len -- val-a val-u )
\   Shortcut: get the id attribute value.
VARIABLE _HID-BUF
\ Store "id" as two bytes in little-endian cell: byte0='i', byte1='d'
25705 _HID-BUF !

: HTML-ID  ( addr len -- val-a val-u )
    _HID-BUF 2 HTML-ATTR ;

\ HTML-CLASS-HAS? ( tag-a tag-u class-a class-u -- flag )
\   Does the element have this CSS class?
\   Checks the class="" attribute for a space-delimited word.
CREATE _HC-LIT-CLASS  99 C, 108 C, 97 C, 115 C, 115 C,   \ "class"

VARIABLE _HCH-CA  VARIABLE _HCH-CL
VARIABLE _HCH-VA  VARIABLE _HCH-VL
VARIABLE _HCH-WA  VARIABLE _HCH-WL

: HTML-CLASS-HAS?  ( tag-a tag-u class-a class-u -- flag )
    _HCH-CL !  _HCH-CA !
    MU-GET-TAG-BODY MU-SKIP-NAME
    _HC-LIT-CLASS 5 MU-ATTR-FIND
    0= IF 2DROP 0 EXIT THEN
    \ have class attribute value: scan for matching word
    _HCH-VL !  _HCH-VA !
    _HCH-VA @ _HCH-WA !
    0 _HCH-WL !
    BEGIN
        _HCH-VA @ _HCH-VL @ +  _HCH-WA @ _HCH-WL @ +  > WHILE
        _HCH-WA @ _HCH-WL @ + C@
        DUP 32 = OVER 9 = OR OVER 10 = OR OVER 13 = OR IF
            DROP
            _HCH-WL @ 0> IF
                _HCH-WA @ _HCH-WL @  _HCH-CA @ _HCH-CL @ STR-STR= IF
                    -1 EXIT
                THEN
            THEN
            _HCH-WA @ _HCH-WL @ + 1+ _HCH-WA !
            0 _HCH-WL !
        ELSE
            DROP
            1 _HCH-WL +!
        THEN
    REPEAT
    \ check last word
    _HCH-WL @ 0> IF
        _HCH-WA @ _HCH-WL @  _HCH-CA @ _HCH-CL @ STR-STR=
        EXIT
    THEN
    0 ;

\ HTML-EACH-CHILD ( addr len -- addr' len' name-a name-u flag )
\   Iterate child elements.  Call with cursor INSIDE element
\   (past opening tag).  Returns cursor at child, tag name, flag.
\   To advance: call _HTML-SKIP-ELEMENT on current child, then
\   call HTML-EACH-CHILD again.
VARIABLE _HEC-NA  VARIABLE _HEC-NL

: HTML-EACH-CHILD  ( addr len -- addr' len' name-a name-u flag )
    MU-SKIP-WS
    MU-SKIP-TO-TAG
    DUP 0= IF 0 0 0 EXIT THEN
    2DUP MU-TAG-TYPE
    DUP MU-T-CLOSE = OVER MU-T-TEXT = OR IF
        DROP 0 0 0 EXIT
    THEN
    DUP MU-T-COMMENT = IF
        DROP MU-SKIP-COMMENT RECURSE EXIT
    THEN
    DROP
    2DUP MU-GET-TAG-NAME _HEC-NL ! _HEC-NA ! 2DROP
    _HEC-NA @ _HEC-NL @ -1 ;

\ =====================================================================
\  HTML5 Extended Entity Decoding
\ =====================================================================
\
\ Core handles: &amp; &lt; &gt; &quot; &apos; &#DD; &#xHH;
\ HTML5 adds ~30 common named entities.
\ We store entity names as CREATE'd byte arrays.

CREATE _HE-NBSP   110 C, 98 C, 115 C, 112 C,                 \ nbsp
CREATE _HE-COPY   99 C, 111 C, 112 C, 121 C,                 \ copy
CREATE _HE-REG    114 C, 101 C, 103 C,                        \ reg
CREATE _HE-TRADE  116 C, 114 C, 97 C, 100 C, 101 C,          \ trade
CREATE _HE-MDASH  109 C, 100 C, 97 C, 115 C, 104 C,          \ mdash
CREATE _HE-NDASH  110 C, 100 C, 97 C, 115 C, 104 C,          \ ndash
CREATE _HE-LSQUO  108 C, 115 C, 113 C, 117 C, 111 C,         \ lsquo
CREATE _HE-RSQUO  114 C, 115 C, 113 C, 117 C, 111 C,         \ rsquo
CREATE _HE-LDQUO  108 C, 100 C, 113 C, 117 C, 111 C,         \ ldquo
CREATE _HE-RDQUO  114 C, 100 C, 113 C, 117 C, 111 C,         \ rdquo
CREATE _HE-BULL   98 C, 117 C, 108 C, 108 C,                 \ bull
CREATE _HE-HELLIP 104 C, 101 C, 108 C, 108 C, 105 C, 112 C, \ hellip
CREATE _HE-EURO   101 C, 117 C, 114 C, 111 C,                \ euro
CREATE _HE-RARR   114 C, 97 C, 114 C, 114 C,                 \ rarr
CREATE _HE-LARR   108 C, 97 C, 114 C, 114 C,                 \ larr
CREATE _HE-TIMES  116 C, 105 C, 109 C, 101 C, 115 C,         \ times
CREATE _HE-DIVIDE 100 C, 105 C, 118 C, 105 C, 100 C, 101 C, \ divide
CREATE _HE-PARA   112 C, 97 C, 114 C, 97 C,                  \ para
CREATE _HE-SECT   115 C, 101 C, 99 C, 116 C,                 \ sect
CREATE _HE-DEG    100 C, 101 C, 103 C,                        \ deg
CREATE _HE-PLUSMN 112 C, 108 C, 117 C, 115 C, 109 C, 110 C, \ plusmn
CREATE _HE-MICRO  109 C, 105 C, 99 C, 114 C, 111 C,          \ micro
CREATE _HE-MIDDOT 109 C, 105 C, 100 C, 100 C, 111 C, 116 C, \ middot
CREATE _HE-IQUEST 105 C, 113 C, 117 C, 101 C, 115 C, 116 C, \ iquest
CREATE _HE-IEXCL  105 C, 101 C, 120 C, 99 C, 108 C,          \ iexcl
CREATE _HE-CENT   99 C, 101 C, 110 C, 116 C,                 \ cent
CREATE _HE-POUND  112 C, 111 C, 117 C, 110 C, 100 C,         \ pound
CREATE _HE-YEN    121 C, 101 C, 110 C,                        \ yen
CREATE _HE-CURREN 99 C, 117 C, 114 C, 114 C, 101 C, 110 C,  \ curren
CREATE _HE-LAQUO  108 C, 97 C, 113 C, 117 C, 111 C,          \ laquo
CREATE _HE-RAQUO  114 C, 97 C, 113 C, 117 C, 111 C,          \ raquo

VARIABLE _HDE-CHAR
VARIABLE _HDE-NA  VARIABLE _HDE-NL
VARIABLE _HDE-A
VARIABLE _HDE-OU   \ save original length

\ HTML-DECODE-ENTITY ( addr len -- char addr' len' )
\   Decode one &...; entity with HTML5 named entity support.
\   Falls back to MU-DECODE-ENTITY for core 5 + numeric.
\   Return format matches MU-DECODE-ENTITY: char at bottom.
: HTML-DECODE-ENTITY  ( addr len -- char addr' len' )
    DUP 2 < IF OVER C@ -ROT 1 /STRING EXIT THEN
    OVER C@ 38 <> IF OVER C@ -ROT 1 /STRING EXIT THEN
    \ try core decoder first
    DUP _HDE-OU !                    \ save original length
    2DUP MU-DECODE-ENTITY            \ ( orig-a orig-u char a' u' )
    ROT _HDE-CHAR !                  \ ( orig-a orig-u a' u' )
    \ Core returns char=38 for BOTH &amp; AND unknown entities.
    \ Distinguish by checking cursor advancement:
    \ If u' < orig-u - 1, core consumed more than just '&'.
    _HDE-OU @ OVER - 1 > IF
        \ core decoded it
        2SWAP 2DROP
        _HDE-CHAR @ -ROT EXIT       \ ( char a' u' )
    THEN
    \ core didn't recognize it — try extended entities
    2DROP                            \ drop core's a'/u'
    1 /STRING                        \ skip '&' → ( a-after-&, u-1 )
    OVER _HDE-A !
    2DUP 59 MU-SKIP-UNTIL-CH        \ find ';' → ( a, u, a-at-;, u-at-; )
    DUP 0= IF
        \ no ';' found — return '&' past '&'
        2DROP 38 -ROT EXIT
    THEN
    OVER _HDE-A @ -  _HDE-NL !
    _HDE-A @ _HDE-NA !
    1 /STRING                        \ skip ';' → ( a, u, a-past-;, u-past-; )
    2SWAP 2DROP                      \ drop the pre-; cursor
    \ stack: ( a-past-;, u-past-;) — result cursor
    \ try extended named entities
    _HDE-NA @ _HDE-NL @  _HE-NBSP   4 STR-STR= IF  160 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-COPY   4 STR-STR= IF  169 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-REG    3 STR-STR= IF  174 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-TRADE  5 STR-STR= IF 8482 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-MDASH  5 STR-STR= IF 8212 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-NDASH  5 STR-STR= IF 8211 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-LSQUO  5 STR-STR= IF 8216 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-RSQUO  5 STR-STR= IF 8217 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-LDQUO  5 STR-STR= IF 8220 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-RDQUO  5 STR-STR= IF 8221 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-BULL   4 STR-STR= IF 8226 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-HELLIP 6 STR-STR= IF 8230 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-EURO   4 STR-STR= IF 8364 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-RARR   4 STR-STR= IF 8594 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-LARR   4 STR-STR= IF 8592 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-TIMES  5 STR-STR= IF  215 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-DIVIDE 6 STR-STR= IF  247 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-PARA   4 STR-STR= IF  182 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-SECT   4 STR-STR= IF  167 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-DEG    3 STR-STR= IF  176 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-PLUSMN 6 STR-STR= IF  177 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-MICRO  5 STR-STR= IF  181 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-MIDDOT 6 STR-STR= IF  183 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-IQUEST 6 STR-STR= IF  191 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-IEXCL  5 STR-STR= IF  161 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-CENT   4 STR-STR= IF  162 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-POUND  5 STR-STR= IF  163 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-YEN    3 STR-STR= IF  165 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-CURREN 6 STR-STR= IF  164 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-LAQUO  5 STR-STR= IF  171 -ROT EXIT THEN
    _HDE-NA @ _HDE-NL @  _HE-RAQUO  5 STR-STR= IF  187 -ROT EXIT THEN
    38 -ROT ;                        \ unknown → return '&'

\ =====================================================================
\  HTML5 Builder
\ =====================================================================

VARIABLE _HB-BUF   VARIABLE _HB-MAX   VARIABLE _HB-POS

: HTML-SET-OUTPUT  ( addr max -- )
    _HB-MAX !  _HB-BUF !  0 _HB-POS ! ;

: HTML-OUTPUT-RESET  ( -- )
    0 _HB-POS ! ;

: HTML-OUTPUT-RESULT  ( -- addr len )
    _HB-BUF @ _HB-POS @ ;

: _HTML-EMIT  ( char -- )
    _HB-POS @ _HB-MAX @ < IF
        _HB-BUF @ _HB-POS @ + C!
        1 _HB-POS +!
    ELSE
        DROP MU-E-OVERFLOW MU-FAIL
    THEN ;

: _HTML-TYPE  ( addr len -- )
    0 ?DO
        DUP I + C@ _HTML-EMIT
    LOOP DROP ;

\ HTML-DOCTYPE ( -- )
\   Emit <!DOCTYPE html>
: HTML-DOCTYPE  ( -- )
    60 _HTML-EMIT  33 _HTML-EMIT     \ '<!'
    68 _HTML-EMIT  79 _HTML-EMIT     \ 'DO'
    67 _HTML-EMIT  84 _HTML-EMIT     \ 'CT'
    89 _HTML-EMIT  80 _HTML-EMIT     \ 'YP'
    69 _HTML-EMIT                    \ 'E'
    32 _HTML-EMIT                    \ ' '
    104 _HTML-EMIT 116 _HTML-EMIT    \ 'ht'
    109 _HTML-EMIT 108 _HTML-EMIT    \ 'ml'
    62 _HTML-EMIT ;                  \ '>'

\ HTML-< ( name-a name-u -- )
: HTML-<  ( name-a name-u -- )
    60 _HTML-EMIT
    _HTML-TYPE ;

\ HTML-> ( -- )
: HTML->  ( -- )
    62 _HTML-EMIT ;

\ HTML-/> ( -- )
\   Close void element.  HTML5 style: just '>' (not '/>').
: HTML-/>  ( -- )
    62 _HTML-EMIT ;

\ HTML-</ ( name-a name-u -- )
: HTML-</  ( name-a name-u -- )
    60 _HTML-EMIT  47 _HTML-EMIT
    _HTML-TYPE
    62 _HTML-EMIT ;

\ HTML-ATTR! ( name-a name-u val-a val-u -- )
\   Add attribute: outputs ' name="value"'
: HTML-ATTR!  ( name-a name-u val-a val-u -- )
    2>R
    32 _HTML-EMIT
    _HTML-TYPE
    61 _HTML-EMIT
    34 _HTML-EMIT
    2R> _HTML-TYPE
    34 _HTML-EMIT ;

\ HTML-BARE-ATTR! ( name-a name-u -- )
\   Add bare (valueless) attribute: outputs ' name'
: HTML-BARE-ATTR!  ( name-a name-u -- )
    32 _HTML-EMIT
    _HTML-TYPE ;

\ _HTML-ESCAPE-CHAR ( char -- )
: _HTML-ESCAPE-CHAR  ( char -- )
    DUP 38 = IF DROP                 \ '&' → &amp;
        38 _HTML-EMIT 97 _HTML-EMIT 109 _HTML-EMIT
        112 _HTML-EMIT 59 _HTML-EMIT EXIT
    THEN
    DUP 60 = IF DROP                 \ '<' → &lt;
        38 _HTML-EMIT 108 _HTML-EMIT 116 _HTML-EMIT
        59 _HTML-EMIT EXIT
    THEN
    DUP 62 = IF DROP                 \ '>' → &gt;
        38 _HTML-EMIT 103 _HTML-EMIT 116 _HTML-EMIT
        59 _HTML-EMIT EXIT
    THEN
    _HTML-EMIT ;

\ HTML-TEXT! ( txt-a txt-u -- )
: HTML-TEXT!  ( txt-a txt-u -- )
    0 ?DO
        DUP I + C@ _HTML-ESCAPE-CHAR
    LOOP DROP ;

\ HTML-RAW! ( txt-a txt-u -- )
\   Emit raw text (for script/style content).
: HTML-RAW!  ( txt-a txt-u -- )
    _HTML-TYPE ;

\ HTML-COMMENT! ( txt-a txt-u -- )
\   Emit <!-- text -->
: HTML-COMMENT!  ( txt-a txt-u -- )
    60 _HTML-EMIT 33 _HTML-EMIT
    45 _HTML-EMIT 45 _HTML-EMIT
    32 _HTML-EMIT
    _HTML-TYPE
    32 _HTML-EMIT
    45 _HTML-EMIT 45 _HTML-EMIT
    62 _HTML-EMIT ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _html-guard

' HTML-VOID?      CONSTANT _html-void-q-xt
' HTML-ENTER      CONSTANT _html-enter-xt
' HTML-TEXT       CONSTANT _html-text-xt
' HTML-INNER      CONSTANT _html-inner-xt
' HTML-CHILD      CONSTANT _html-child-xt
' HTML-CHILD?     CONSTANT _html-child-q-xt
' HTML-ATTR       CONSTANT _html-attr-xt
' HTML-ATTR?      CONSTANT _html-attr-q-xt
' HTML-ID         CONSTANT _html-id-xt
' HTML-CLASS-HAS? CONSTANT _html-class-has-q-xt
' HTML-EACH-CHILD CONSTANT _html-each-child-xt
' HTML-DECODE-ENTITY CONSTANT _html-decode-entity-xt
' HTML-SET-OUTPUT CONSTANT _html-set-output-xt
' HTML-OUTPUT-RESET CONSTANT _html-output-reset-xt
' HTML-OUTPUT-RESULT CONSTANT _html-output-result-xt
' HTML-DOCTYPE    CONSTANT _html-doctype-xt
' HTML-<          CONSTANT _html-from-xt
' HTML->          CONSTANT _html-to-xt
' HTML-/>         CONSTANT _html-div-to-xt
' HTML-</         CONSTANT _html-from-div-xt
' HTML-ATTR!      CONSTANT _html-attr-s-xt
' HTML-BARE-ATTR! CONSTANT _html-bare-attr-s-xt
' HTML-TEXT!      CONSTANT _html-text-s-xt
' HTML-RAW!       CONSTANT _html-raw-s-xt
' HTML-COMMENT!   CONSTANT _html-comment-s-xt

: HTML-VOID?      _html-void-q-xt _html-guard WITH-GUARD ;
: HTML-ENTER      _html-enter-xt _html-guard WITH-GUARD ;
: HTML-TEXT       _html-text-xt _html-guard WITH-GUARD ;
: HTML-INNER      _html-inner-xt _html-guard WITH-GUARD ;
: HTML-CHILD      _html-child-xt _html-guard WITH-GUARD ;
: HTML-CHILD?     _html-child-q-xt _html-guard WITH-GUARD ;
: HTML-ATTR       _html-attr-xt _html-guard WITH-GUARD ;
: HTML-ATTR?      _html-attr-q-xt _html-guard WITH-GUARD ;
: HTML-ID         _html-id-xt _html-guard WITH-GUARD ;
: HTML-CLASS-HAS? _html-class-has-q-xt _html-guard WITH-GUARD ;
: HTML-EACH-CHILD _html-each-child-xt _html-guard WITH-GUARD ;
: HTML-DECODE-ENTITY _html-decode-entity-xt _html-guard WITH-GUARD ;
: HTML-SET-OUTPUT _html-set-output-xt _html-guard WITH-GUARD ;
: HTML-OUTPUT-RESET _html-output-reset-xt _html-guard WITH-GUARD ;
: HTML-OUTPUT-RESULT _html-output-result-xt _html-guard WITH-GUARD ;
: HTML-DOCTYPE    _html-doctype-xt _html-guard WITH-GUARD ;
: HTML-<          _html-from-xt _html-guard WITH-GUARD ;
: HTML->          _html-to-xt _html-guard WITH-GUARD ;
: HTML-/>         _html-div-to-xt _html-guard WITH-GUARD ;
: HTML-</         _html-from-div-xt _html-guard WITH-GUARD ;
: HTML-ATTR!      _html-attr-s-xt _html-guard WITH-GUARD ;
: HTML-BARE-ATTR! _html-bare-attr-s-xt _html-guard WITH-GUARD ;
: HTML-TEXT!      _html-text-s-xt _html-guard WITH-GUARD ;
: HTML-RAW!       _html-raw-s-xt _html-guard WITH-GUARD ;
: HTML-COMMENT!   _html-comment-s-xt _html-guard WITH-GUARD ;
[THEN] [THEN]
