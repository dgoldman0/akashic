\ xml.f — XML reader & builder vocabulary
\
\ Builds on akashic-markup-core for XML-specific parsing.
\ Case-sensitive tag matching.  Strict well-formedness.
\
\ Prefix: XML-   (public API)
\         _XML-  (internal helpers)
\
\ Load with:   REQUIRE xml.f

PROVIDED akashic-xml
REQUIRE core.f

\ =====================================================================
\  XML Reader
\ =====================================================================

\ XML-ENTER ( addr len -- addr' len' )
\   Enter an element: skip past the opening tag.
: XML-ENTER  ( addr len -- addr' len' )
    MU-ENTER ;

\ XML-TEXT ( addr len -- txt-a txt-u )
\   Extract text content of the current element.
\   Cursor must be at the opening tag.
\   Returns the text before any child element or close tag.
: XML-TEXT  ( addr len -- txt-a txt-u )
    MU-ENTER
    MU-GET-TEXT 2SWAP 2DROP ;

\ XML-INNER ( addr len -- inner-a inner-u )
\   Extract everything between open and close tags.
: XML-INNER  ( addr len -- inner-a inner-u )
    MU-INNER ;

\ XML-CHILD ( addr len name-a name-u -- addr' len' )
\   Find a child element by tag name.
\   Cursor must be at the PARENT's opening tag.
\   After: cursor at the child's opening tag.
\   Aborts if not found.
VARIABLE _XC-NA  VARIABLE _XC-NL

: XML-CHILD  ( addr len name-a name-u -- addr' len' )
    _XC-NL !  _XC-NA !
    MU-ENTER
    _XC-NA @ _XC-NL @ MU-FIND-TAG
    0= IF MU-E-NOT-FOUND MU-FAIL THEN ;

\ XML-CHILD? ( addr len name-a name-u -- addr' len' flag )
\   Like XML-CHILD but returns flag instead of aborting.
: XML-CHILD?  ( addr len name-a name-u -- addr' len' flag )
    _XC-NL !  _XC-NA !
    MU-ENTER
    _XC-NA @ _XC-NL @ MU-FIND-TAG ;

\ XML-ATTR ( tag-a tag-u attr-a attr-u -- val-a val-u )
\   Get attribute value from a tag.  Cursor at opening '<'.
\   Aborts if attribute not found.
: XML-ATTR  ( tag-a tag-u attr-a attr-u -- val-a val-u )
    2>R
    MU-GET-TAG-BODY MU-SKIP-NAME
    2R> MU-ATTR-FIND
    0= IF 2DROP MU-E-NOT-FOUND MU-FAIL 0 0 THEN ;

\ XML-ATTR? ( tag-a tag-u attr-a attr-u -- val-a val-u flag )
\   Like XML-ATTR but returns flag.
: XML-ATTR?  ( tag-a tag-u attr-a attr-u -- val-a val-u flag )
    2>R
    MU-GET-TAG-BODY MU-SKIP-NAME
    2R> MU-ATTR-FIND ;

\ XML-SKIP-PI ( addr len -- addr' len' )
\   Skip a processing instruction <?...?>.
: XML-SKIP-PI  ( addr len -- addr' len' )
    MU-SKIP-PI ;

\ XML-SKIP-CDATA ( addr len -- addr' len' )
\   Skip a CDATA section <![CDATA[...]]>.
: XML-SKIP-CDATA  ( addr len -- addr' len' )
    MU-SKIP-CDATA ;

\ XML-GET-CDATA ( addr len -- txt-a txt-u )
\   Extract the content of a CDATA section (without delimiters).
\   Cursor must be at '<![CDATA['.
VARIABLE _XGC-A
: XML-GET-CDATA  ( addr len -- txt-a txt-u )
    DUP 9 < IF 2DROP 0 0 EXIT THEN
    9 /STRING                        \ skip '<![CDATA['
    OVER _XGC-A !
    BEGIN
        DUP 0> WHILE
        DUP 3 >= IF
            OVER _XGC-A @ = 0= IF   \ not at start  (skip)
            THEN
            OVER C@ 93 =            \ ]
            IF OVER 1+ C@ 93 =      \ ]
            IF OVER 2 + C@ 62 = IF  \ >
                OVER _XGC-A @ -      \ content length
                _XGC-A @ SWAP EXIT
            THEN THEN THEN
        THEN
        1 /STRING
    REPEAT
    \ no closing ]]> found
    OVER _XGC-A @ -
    _XGC-A @ SWAP ;

\ XML-PATH ( addr len path-a path-u -- addr' len' )
\   Navigate a slash-separated path: "a/b/c"
\   Cursor should be at or before the root element.
\   Intermediate segments: MU-FIND-TAG + MU-ENTER.
\   Last segment: MU-FIND-TAG only (cursor left AT element).
VARIABLE _XP-PA  VARIABLE _XP-PL   \ remaining path
VARIABLE _XP-SA  VARIABLE _XP-SL   \ current segment

: XML-PATH  ( addr len path-a path-u -- addr' len' )
    _XP-PL !  _XP-PA !
    _XP-PA @ _XP-SA !
    0 _XP-SL !
    BEGIN
        _XP-PL @ 0> WHILE
        _XP-PA @ C@ 47 = IF     \ '/'
            1 _XP-PA +!  -1 _XP-PL +!
            _XP-SL @ 0> IF
                _XP-SA @ _XP-SL @ MU-FIND-TAG
                IF MU-ENTER THEN
            THEN
            _XP-PA @ _XP-SA !
            0 _XP-SL !
        ELSE
            1 _XP-SL +!
            1 _XP-PA +!  -1 _XP-PL +!
        THEN
    REPEAT
    \ last segment (no trailing slash)
    _XP-SL @ 0> IF
        _XP-SA @ _XP-SL @ MU-FIND-TAG DROP
    THEN ;

\ XML-EACH-CHILD ( addr len -- addr' len' name-a name-u flag )
\   Iterate child elements.  Call with cursor INSIDE an element
\   (past the opening tag).
\   Returns: cursor at next sibling, current child's tag name, flag.
\   flag = -1 if a child found, 0 if no more.
\   To iterate, use the returned cursor for the next call after
\   skipping the current child with MU-SKIP-ELEMENT.
VARIABLE _XEC-NA  VARIABLE _XEC-NL

: XML-EACH-CHILD  ( addr len -- addr' len' name-a name-u flag )
    MU-SKIP-WS
    MU-SKIP-TO-TAG
    DUP 0= IF 0 0 0 EXIT THEN
    2DUP MU-TAG-TYPE
    DUP MU-T-CLOSE = OVER MU-T-TEXT = OR IF
        DROP 0 0 0 EXIT              \ end of children
    THEN
    DUP MU-T-COMMENT = IF
        DROP MU-SKIP-COMMENT RECURSE EXIT
    THEN
    DUP MU-T-PI = IF
        DROP MU-SKIP-PI RECURSE EXIT
    THEN
    DROP
    2DUP MU-GET-TAG-NAME _XEC-NL ! _XEC-NA ! 2DROP
    _XEC-NA @ _XEC-NL @ -1 ;

\ =====================================================================
\  XML Builder
\ =====================================================================

\ Output buffer & vectored emit
VARIABLE _XB-BUF   VARIABLE _XB-MAX   VARIABLE _XB-POS

: XML-SET-OUTPUT  ( addr max -- )
    _XB-MAX !  _XB-BUF !  0 _XB-POS ! ;

: XML-OUTPUT-RESET  ( -- )
    0 _XB-POS ! ;

: XML-OUTPUT-RESULT  ( -- addr len )
    _XB-BUF @ _XB-POS @ ;

: _XML-EMIT  ( char -- )
    _XB-POS @ _XB-MAX @ < IF
        _XB-BUF @ _XB-POS @ + C!
        1 _XB-POS +!
    ELSE
        DROP MU-E-OVERFLOW MU-FAIL
    THEN ;

: _XML-TYPE  ( addr len -- )
    0 ?DO
        DUP I + C@ _XML-EMIT
    LOOP DROP ;

\ XML-< ( name-a name-u -- )
\   Start an opening tag: outputs '<' + name
: XML-<  ( name-a name-u -- )
    60 _XML-EMIT                     \ '<'
    _XML-TYPE ;

\ XML-> ( -- )
\   Close an opening tag: outputs '>'
: XML->  ( -- )
    62 _XML-EMIT ;                   \ '>'

\ XML-/> ( -- )
\   Self-closing tag end: outputs '/>'
: XML-/>  ( -- )
    47 _XML-EMIT  62 _XML-EMIT ;    \ '/>'

\ XML-</ ( name-a name-u -- )
\   Closing tag: outputs '</name>'
: XML-</  ( name-a name-u -- )
    60 _XML-EMIT  47 _XML-EMIT      \ '</'
    _XML-TYPE
    62 _XML-EMIT ;                   \ '>'

\ XML-ATTR! ( name-a name-u val-a val-u -- )
\   Add attribute to current tag: outputs ' name="value"'
: XML-ATTR!  ( name-a name-u val-a val-u -- )
    2>R
    32 _XML-EMIT                     \ space
    _XML-TYPE                        \ name
    61 _XML-EMIT                     \ '='
    34 _XML-EMIT                     \ '"'
    2R> _XML-TYPE                    \ value
    34 _XML-EMIT ;                   \ '"'

\ _XML-ESCAPE-CHAR ( char -- )
\   Emit char with XML escaping for text content.
: _XML-ESCAPE-CHAR  ( char -- )
    DUP 38 = IF DROP                 \ '&' → &amp;
        38 _XML-EMIT 97 _XML-EMIT 109 _XML-EMIT
        112 _XML-EMIT 59 _XML-EMIT EXIT
    THEN
    DUP 60 = IF DROP                 \ '<' → &lt;
        38 _XML-EMIT 108 _XML-EMIT 116 _XML-EMIT
        59 _XML-EMIT EXIT
    THEN
    DUP 62 = IF DROP                 \ '>' → &gt;
        38 _XML-EMIT 103 _XML-EMIT 116 _XML-EMIT
        59 _XML-EMIT EXIT
    THEN
    _XML-EMIT ;

\ XML-TEXT! ( txt-a txt-u -- )
\   Emit text content with XML escaping (& < >).
: XML-TEXT!  ( txt-a txt-u -- )
    0 ?DO
        DUP I + C@ _XML-ESCAPE-CHAR
    LOOP DROP ;

\ XML-RAW! ( txt-a txt-u -- )
\   Emit raw text (no escaping).
: XML-RAW!  ( txt-a txt-u -- )
    _XML-TYPE ;

\ XML-COMMENT! ( txt-a txt-u -- )
\   Emit <!-- text -->
: XML-COMMENT!  ( txt-a txt-u -- )
    60 _XML-EMIT 33 _XML-EMIT       \ '<!'
    45 _XML-EMIT 45 _XML-EMIT       \ '--'
    32 _XML-EMIT                     \ space
    _XML-TYPE                        \ text
    32 _XML-EMIT                     \ space
    45 _XML-EMIT 45 _XML-EMIT       \ '--'
    62 _XML-EMIT ;                   \ '>'

\ XML-PI! ( target-a tu data-a du -- )
\   Emit <?target data?>
: XML-PI!  ( target-a tu data-a du -- )
    2>R
    60 _XML-EMIT 63 _XML-EMIT       \ '<?'
    _XML-TYPE                        \ target
    32 _XML-EMIT                     \ space
    2R> _XML-TYPE                    \ data
    63 _XML-EMIT 62 _XML-EMIT ;     \ '?>'
