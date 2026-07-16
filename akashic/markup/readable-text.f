\ =====================================================================
\  readable-text.f - bounded inert UTF-8 text projection
\ =====================================================================
\  PLAIN and HTML project caller-owned UTF-8 input into caller-owned
\  output without allocating a DOM or executing active content.  ASCII
\  whitespace is folded to one U+0020 and trimmed; other UTF-8 bytes are
\  preserved.  HTML uses a strict fixed-depth scanner and removes script,
\  style, nav, header, footer, and aside subtrees.
\
\  Public API:
\    RTEXT-PLAIN
\      ( source-a source-u destination-a destination-cap -- text-u status )
\    RTEXT-HTML
\      ( source-a source-u destination-a destination-cap -- text-u status )
\
\  SOURCE is limited to RTEXT-SOURCE-MAX and must be valid UTF-8.
\  DESTINATION-CAP is the exact output bound supplied by the caller.
\  Non-empty source and destination spans must not overlap.
\  Successful calls return the committed byte count and RTEXT-S-OK.
\  Failures return zero usable bytes; the destination may contain a partial
\  projection and must be treated as scratch.  A caller needing transactional
\  state should project into its own candidate and commit only on success.
\
\  The HTML subset accepts ordinary start/end tags, quoted attributes, void
\  tags, comments, and a doctype.  It decodes the five XML entities, nbsp,
\  and valid numeric Unicode scalar references.  Unknown named entities and
\  unsupported declarations return RTEXT-S-UNSUPPORTED; malformed UTF-8,
\  entities, or markup return RTEXT-S-INVALID.
\ =====================================================================

PROVIDED akashic-readable-text

REQUIRE ../text/utf8.f
REQUIRE ../concurrency/guard.f

131072 CONSTANT RTEXT-SOURCE-MAX

0 CONSTANT RTEXT-S-OK
1 CONSTANT RTEXT-S-INVALID
2 CONSTANT RTEXT-S-CAPACITY
3 CONSTANT RTEXT-S-UNSUPPORTED

GUARD _readable-text-guard

VARIABLE _RTX-DEST
VARIABLE _RTX-DEST-CAP

\ =====================================================================
\  Small ASCII helpers
\ =====================================================================

: _RTX-ASCII-SPACE?  ( c -- flag )
    DUP 32 = IF DROP -1 EXIT THEN
    9 14 WITHIN ;

: _RTX-LOWER  ( c -- c' )
    DUP 65 91 WITHIN IF 32 + THEN ;

VARIABLE _RTCI-A1
VARIABLE _RTCI-U1
VARIABLE _RTCI-A2
VARIABLE _RTCI-U2

: _RTX-ASCII-CI=  ( a1 u1 a2 u2 -- flag )
    _RTCI-U2 ! _RTCI-A2 ! _RTCI-U1 ! _RTCI-A1 !
    _RTCI-U1 @ _RTCI-U2 @ <> IF 0 EXIT THEN
    _RTCI-U1 @ 0 ?DO
        _RTCI-A1 @ I + C@ _RTX-LOWER
        _RTCI-A2 @ I + C@ _RTX-LOWER <> IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

: _RTX-NAME-CHAR?  ( c -- flag )
    DUP 65 91 WITHIN IF DROP -1 EXIT THEN
    DUP 97 123 WITHIN IF DROP -1 EXIT THEN
    DUP 48 58 WITHIN IF DROP -1 EXIT THEN
    DUP 45 = SWAP 58 = OR ;

: _RTX-NAME-START?  ( c -- flag )
    DUP 65 91 WITHIN SWAP 97 123 WITHIN OR ;

: _RTX-SKIP-NAME?  ( a u -- flag )
    2DUP S" script" _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" style"  _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" nav"    _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" header" _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" footer" _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" aside" _RTX-ASCII-CI= ;

: _RTX-RAW-NAME?  ( a u -- flag )
    2DUP S" script" _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" style" _RTX-ASCII-CI= ;

: _RTX-VOID-NAME?  ( a u -- flag )
    2DUP S" area"   _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" base"   _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" br"     _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" col"    _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" embed"  _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" hr"     _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" img"    _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" input"  _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" link"   _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" meta"   _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" param"  _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" source" _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" track"  _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" wbr" _RTX-ASCII-CI= ;

: _RTX-BLOCK-NAME?  ( a u -- flag )
    2DUP S" address"    _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" article"    _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" aside"      _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" blockquote" _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" body"       _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" br"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" dd"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" div"        _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" dl"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" dt"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" fieldset"   _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" figcaption" _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" figure"     _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" footer"     _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h1"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h2"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h3"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h4"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h5"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h6"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" header"     _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" hr"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" html"       _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" li"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" main"       _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" nav"        _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" ol"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" p"          _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" pre"        _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" section"    _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" table"      _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" tbody"      _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" td"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" tfoot"      _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" th"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" thead"      _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" tr"         _RTX-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" ul" _RTX-ASCII-CI= ;

\ =====================================================================
\  Normalized output writer
\ =====================================================================

VARIABLE _RTX-OUT-U
VARIABLE _RTX-PENDING-SPACE
VARIABLE _RTX-STATUS

: _RTX-FAIL  ( status -- )
    _RTX-STATUS @ RTEXT-S-OK = IF _RTX-STATUS ! ELSE DROP THEN ;

: _RTX-BOUNDARY  ( -- )
    _RTX-OUT-U @ IF -1 _RTX-PENDING-SPACE ! THEN ;

: _RTX-EMIT-NONSPACE  ( c -- )
    _RTX-STATUS @ IF DROP EXIT THEN
    _RTX-PENDING-SPACE @ _RTX-OUT-U @ 0> AND IF
        _RTX-OUT-U @ _RTX-DEST-CAP @ >= IF
            DROP RTEXT-S-CAPACITY _RTX-FAIL EXIT
        THEN
        32 _RTX-DEST @ _RTX-OUT-U @ + C!
        1 _RTX-OUT-U +!
    THEN
    0 _RTX-PENDING-SPACE !
    _RTX-OUT-U @ _RTX-DEST-CAP @ >= IF
        DROP RTEXT-S-CAPACITY _RTX-FAIL EXIT
    THEN
    _RTX-DEST @ _RTX-OUT-U @ + C!
    1 _RTX-OUT-U +! ;

: _RTX-EMIT-BYTE  ( c -- )
    DUP _RTX-ASCII-SPACE? IF DROP _RTX-BOUNDARY EXIT THEN
    _RTX-EMIT-NONSPACE ;

VARIABLE _RTX-CP

: _RTX-EMIT-CP  ( cp -- )
    DUP _RTX-CP !
    DUP 0x80 < IF _RTX-EMIT-BYTE EXIT THEN
    DUP 0x800 < IF
        DUP 6 RSHIFT 0xC0 OR _RTX-EMIT-NONSPACE
        0x3F AND 0x80 OR _RTX-EMIT-NONSPACE EXIT
    THEN
    DUP 0x10000 < IF
        DUP 12 RSHIFT 0xE0 OR _RTX-EMIT-NONSPACE
        DUP 6 RSHIFT 0x3F AND 0x80 OR _RTX-EMIT-NONSPACE
        0x3F AND 0x80 OR _RTX-EMIT-NONSPACE EXIT
    THEN
    DUP 18 RSHIFT 0xF0 OR _RTX-EMIT-NONSPACE
    DUP 12 RSHIFT 0x3F AND 0x80 OR _RTX-EMIT-NONSPACE
    DUP 6 RSHIFT 0x3F AND 0x80 OR _RTX-EMIT-NONSPACE
    0x3F AND 0x80 OR _RTX-EMIT-NONSPACE ;

\ =====================================================================
\  Fixed-depth streaming HTML scanner
\ =====================================================================

64 CONSTANT _RTX-TAG-DEPTH-MAX
CREATE _RTX-TAG-A    _RTX-TAG-DEPTH-MAX CELLS ALLOT
CREATE _RTX-TAG-U    _RTX-TAG-DEPTH-MAX CELLS ALLOT
CREATE _RTX-TAG-SKIP _RTX-TAG-DEPTH-MAX CELLS ALLOT

VARIABLE _RTX-A
VARIABLE _RTX-U
VARIABLE _RTX-POS
VARIABLE _RTX-DEPTH
VARIABLE _RTX-SKIP-DEPTH

: _RTX-TAG-A[]     ( index -- a ) CELLS _RTX-TAG-A + ;
: _RTX-TAG-U[]     ( index -- a ) CELLS _RTX-TAG-U + ;
: _RTX-TAG-SKIP[]  ( index -- a ) CELLS _RTX-TAG-SKIP + ;

: _RTX-AT  ( position -- c ) _RTX-A @ + C@ ;

VARIABLE _RTM-POS
VARIABLE _RTM-A
VARIABLE _RTM-U

: _RTX-MATCH-CI?  ( position a u -- flag )
    _RTM-U ! _RTM-A ! _RTM-POS !
    _RTM-POS @ _RTM-U @ + _RTX-U @ > IF 0 EXIT THEN
    _RTX-A @ _RTM-POS @ + _RTM-U @
    _RTM-A @ _RTM-U @ _RTX-ASCII-CI= ;

VARIABLE _RTP-A
VARIABLE _RTP-U
VARIABLE _RTP-SKIP

: _RTX-PUSH  ( name-a name-u own-skip -- )
    _RTP-SKIP ! _RTP-U ! _RTP-A !
    _RTX-DEPTH @ _RTX-TAG-DEPTH-MAX >= IF
        RTEXT-S-CAPACITY _RTX-FAIL EXIT
    THEN
    _RTP-A @ _RTX-DEPTH @ _RTX-TAG-A[] !
    _RTP-U @ _RTX-DEPTH @ _RTX-TAG-U[] !
    _RTP-SKIP @ _RTX-DEPTH @ _RTX-TAG-SKIP[] !
    1 _RTX-DEPTH +!
    _RTP-SKIP @ IF 1 _RTX-SKIP-DEPTH +! THEN ;

: _RTX-TOP-RAW?  ( -- flag )
    _RTX-DEPTH @ 0= IF 0 EXIT THEN
    _RTX-DEPTH @ 1- DUP _RTX-TAG-A[] @
    SWAP _RTX-TAG-U[] @ _RTX-RAW-NAME? ;

VARIABLE _RTC-A
VARIABLE _RTC-U

: _RTX-CLOSE-NAME  ( name-a name-u -- )
    _RTC-U ! _RTC-A !
    _RTX-DEPTH @ 0= IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    _RTX-DEPTH @ 1- DUP _RTX-TAG-A[] @ SWAP _RTX-TAG-U[] @
    _RTC-A @ _RTC-U @ _RTX-ASCII-CI= 0= IF
        RTEXT-S-INVALID _RTX-FAIL EXIT
    THEN
    -1 _RTX-DEPTH +!
    _RTX-DEPTH @ _RTX-TAG-SKIP[] @ IF -1 _RTX-SKIP-DEPTH +! THEN
    _RTX-SKIP-DEPTH @ 0= IF
        _RTC-A @ _RTC-U @ _RTX-BLOCK-NAME? IF _RTX-BOUNDARY THEN
    THEN ;

: _RTX-SKIP-SPACES  ( -- )
    BEGIN _RTX-POS @ _RTX-U @ < WHILE
        _RTX-POS @ _RTX-AT _RTX-ASCII-SPACE? 0= IF EXIT THEN
        1 _RTX-POS +!
    REPEAT ;

\ Find and consume the raw-text element's first syntactically matching close
\ tag.  Script and style bytes are never interpreted as markup or entity
\ references.  Consuming the close here is important: leaving POS at its '<'
\ would cause the outer loop to rediscover the same close indefinitely while
\ the raw-text element remained on top of the stack.
VARIABLE _RTR-I
VARIABLE _RTR-AFTER

: _RTX-SKIP-RAW-TEXT  ( -- )
    _RTX-DEPTH @ 0= IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    _RTX-DEPTH @ 1- DUP _RTX-TAG-A[] @ _RTP-A !
    _RTX-TAG-U[] @ _RTP-U !
    _RTX-POS @ _RTR-I !
    BEGIN _RTR-I @ _RTX-U @ < WHILE
        _RTR-I @ _RTX-AT 60 =
        _RTR-I @ 1+ _RTX-U @ < AND IF
            _RTR-I @ 1+ _RTX-AT 47 = IF
                _RTR-I @ 2 + _RTP-A @ _RTP-U @ _RTX-MATCH-CI? IF
                    _RTR-I @ 2 + _RTP-U @ + DUP _RTR-AFTER !
                    _RTX-U @ < IF
                        _RTR-AFTER @ _RTX-AT DUP 62 =
                        SWAP _RTX-ASCII-SPACE? OR IF
                            _RTR-AFTER @ _RTX-POS !
                            _RTX-SKIP-SPACES
                            _RTX-POS @ _RTX-U @ >= IF
                                RTEXT-S-INVALID _RTX-FAIL EXIT
                            THEN
                            _RTX-POS @ _RTX-AT 62 <> IF
                                RTEXT-S-INVALID _RTX-FAIL EXIT
                            THEN
                            1 _RTX-POS +!
                            _RTP-A @ _RTP-U @ _RTX-CLOSE-NAME EXIT
                        THEN
                    THEN
                THEN
            THEN
        THEN
        1 _RTR-I +!
    REPEAT
    RTEXT-S-INVALID _RTX-FAIL ;

VARIABLE _RTT-NAME-A
VARIABLE _RTT-NAME-U
VARIABLE _RTT-QUOTE
VARIABLE _RTT-LAST-NONSPACE
VARIABLE _RTT-SELF-CLOSE

: _RTX-PARSE-NAME  ( -- )
    _RTX-POS @ _RTX-U @ >= IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    _RTX-POS @ _RTX-AT _RTX-NAME-START? 0= IF
        RTEXT-S-INVALID _RTX-FAIL EXIT
    THEN
    _RTX-A @ _RTX-POS @ + _RTT-NAME-A !
    0 _RTT-NAME-U !
    BEGIN _RTX-POS @ _RTX-U @ < WHILE
        _RTX-POS @ _RTX-AT _RTX-NAME-CHAR? 0= IF EXIT THEN
        1 _RTX-POS +! 1 _RTT-NAME-U +!
    REPEAT ;

\ Consume attributes through a quote-aware '>'.  Unquoted '<' and an
\ unterminated quote are malformed.  SELF-CLOSE records a final slash.
: _RTX-SCAN-TAG-END  ( -- )
    0 _RTT-QUOTE ! 0 _RTT-LAST-NONSPACE ! 0 _RTT-SELF-CLOSE !
    BEGIN _RTX-POS @ _RTX-U @ < WHILE
        _RTX-POS @ _RTX-AT
        _RTT-QUOTE @ IF
            DUP _RTT-QUOTE @ = IF 0 _RTT-QUOTE ! THEN
            DROP 1 _RTX-POS +!
        ELSE
            DUP 34 = OVER 39 = OR IF
                _RTT-QUOTE ! 1 _RTX-POS +!
            ELSE
                DUP 60 = IF
                    DROP RTEXT-S-INVALID _RTX-FAIL EXIT
                THEN
                DUP 62 = IF
                    DROP _RTT-LAST-NONSPACE @ 47 =
                        _RTT-SELF-CLOSE !
                    1 _RTX-POS +! EXIT
                THEN
                DUP _RTX-ASCII-SPACE? 0= IF
                    _RTT-LAST-NONSPACE !
                ELSE DROP THEN
                1 _RTX-POS +!
            THEN
        THEN
    REPEAT
    RTEXT-S-INVALID _RTX-FAIL ;

: _RTX-PARSE-COMMENT  ( -- )
    4 _RTX-POS +!
    BEGIN _RTX-POS @ 2 + _RTX-U @ < WHILE
        _RTX-POS @ _RTX-AT 45 =
        _RTX-POS @ 1+ _RTX-AT 45 = AND
        _RTX-POS @ 2 + _RTX-AT 62 = AND IF
            3 _RTX-POS +! EXIT
        THEN
        1 _RTX-POS +!
    REPEAT
    RTEXT-S-INVALID _RTX-FAIL ;

: _RTX-PARSE-DECLARATION  ( -- )
    _RTX-POS @ S" <!--" _RTX-MATCH-CI? IF
        _RTX-PARSE-COMMENT EXIT
    THEN
    _RTX-POS @ 2 + S" doctype" _RTX-MATCH-CI? 0= IF
        RTEXT-S-UNSUPPORTED _RTX-FAIL EXIT
    THEN
    _RTX-POS @ 9 + DUP _RTX-U @ >= IF
        DROP RTEXT-S-INVALID _RTX-FAIL EXIT
    THEN
    _RTX-AT DUP 62 = SWAP _RTX-ASCII-SPACE? OR 0= IF
        RTEXT-S-INVALID _RTX-FAIL EXIT
    THEN
    _RTX-POS @ 2 + _RTX-POS !
    _RTX-PARSE-NAME
    _RTX-STATUS @ IF EXIT THEN
    _RTX-SCAN-TAG-END ;

: _RTX-PARSE-CLOSE-TAG  ( -- )
    2 _RTX-POS +!
    _RTX-PARSE-NAME _RTX-STATUS @ IF EXIT THEN
    _RTX-SKIP-SPACES
    _RTX-POS @ _RTX-U @ >= IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    _RTX-POS @ _RTX-AT 62 <> IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    1 _RTX-POS +!
    _RTT-NAME-A @ _RTT-NAME-U @ _RTX-CLOSE-NAME ;

: _RTX-PARSE-OPEN-TAG  ( -- )
    1 _RTX-POS +!
    _RTX-PARSE-NAME _RTX-STATUS @ IF EXIT THEN
    _RTX-POS @ _RTX-U @ < IF
        _RTX-POS @ _RTX-AT DUP 62 = OVER 47 = OR
        SWAP _RTX-ASCII-SPACE? OR 0= IF
            RTEXT-S-INVALID _RTX-FAIL EXIT
        THEN
    THEN
    _RTT-NAME-A @ _RTT-NAME-U @ _RTX-SKIP-NAME? _RTP-SKIP !
    _RTX-SKIP-DEPTH @ 0= IF
        _RTT-NAME-A @ _RTT-NAME-U @ _RTX-BLOCK-NAME? IF
            _RTX-BOUNDARY
        THEN
    THEN
    _RTX-SCAN-TAG-END _RTX-STATUS @ IF EXIT THEN
    _RTT-SELF-CLOSE @ IF EXIT THEN
    _RTT-NAME-A @ _RTT-NAME-U @ _RTX-VOID-NAME? IF EXIT THEN
    _RTT-NAME-A @ _RTT-NAME-U @ _RTP-SKIP @ _RTX-PUSH ;

: _RTX-PARSE-TAG  ( -- )
    _RTX-POS @ 1+ _RTX-U @ >= IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    _RTX-POS @ 1+ _RTX-AT
    DUP 33 = IF DROP _RTX-PARSE-DECLARATION EXIT THEN
    DUP 47 = IF DROP _RTX-PARSE-CLOSE-TAG EXIT THEN
    DUP 63 = IF DROP RTEXT-S-UNSUPPORTED _RTX-FAIL EXIT THEN
    DROP _RTX-PARSE-OPEN-TAG ;

\ =====================================================================
\  HTML entity decoding
\ =====================================================================

VARIABLE _RTE-A
VARIABLE _RTE-U
VARIABLE _RTE-I
VARIABLE _RTE-BASE
VARIABLE _RTE-VALUE
VARIABLE _RTE-DIGIT
VARIABLE _RTE-END

: _RTX-ENTITY=  ( a u literal-a literal-u -- flag )
    COMPARE 0= ;

: _RTX-HEX-DIGIT  ( c -- digit valid? )
    DUP 48 58 WITHIN IF 48 - -1 EXIT THEN
    DUP 65 71 WITHIN IF 55 - -1 EXIT THEN
    DUP 97 103 WITHIN IF 87 - -1 EXIT THEN
    DROP 0 0 ;

: _RTX-DEC-DIGIT  ( c -- digit valid? )
    DUP 48 58 WITHIN IF 48 - -1 ELSE DROP 0 0 THEN ;

: _RTX-DECODE-NUMERIC-ENTITY  ( body-a body-u -- )
    _RTE-U ! _RTE-A !
    _RTE-U @ 2 < IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    1 _RTE-I ! 10 _RTE-BASE !
    _RTE-A @ 1+ C@ DUP 120 = SWAP 88 = OR IF
        16 _RTE-BASE ! 2 _RTE-I !
    THEN
    _RTE-I @ _RTE-U @ >= IF RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    0 _RTE-VALUE !
    BEGIN _RTE-I @ _RTE-U @ < WHILE
        _RTE-A @ _RTE-I @ + C@
        _RTE-BASE @ 16 = IF _RTX-HEX-DIGIT ELSE _RTX-DEC-DIGIT THEN
        0= IF DROP RTEXT-S-INVALID _RTX-FAIL EXIT THEN
        _RTE-DIGIT !
        _RTE-VALUE @
        0x10FFFF _RTE-DIGIT @ - _RTE-BASE @ / > IF
            RTEXT-S-INVALID _RTX-FAIL EXIT
        THEN
        _RTE-VALUE @ _RTE-BASE @ * _RTE-DIGIT @ +
        DUP 0x10FFFF > IF DROP RTEXT-S-INVALID _RTX-FAIL EXIT THEN
        _RTE-VALUE ! 1 _RTE-I +!
    REPEAT
    _RTE-VALUE @ DUP 0= IF DROP RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    DUP 0xD800 0xE000 WITHIN IF DROP RTEXT-S-INVALID _RTX-FAIL EXIT THEN
    _RTX-EMIT-CP ;

: _RTX-DECODE-NAMED-ENTITY  ( body-a body-u -- )
    2DUP S" amp"  _RTX-ENTITY= IF 2DROP 38 _RTX-EMIT-BYTE EXIT THEN
    2DUP S" lt"   _RTX-ENTITY= IF 2DROP 60 _RTX-EMIT-BYTE EXIT THEN
    2DUP S" gt"   _RTX-ENTITY= IF 2DROP 62 _RTX-EMIT-BYTE EXIT THEN
    2DUP S" quot" _RTX-ENTITY= IF 2DROP 34 _RTX-EMIT-BYTE EXIT THEN
    2DUP S" apos" _RTX-ENTITY= IF 2DROP 39 _RTX-EMIT-BYTE EXIT THEN
    2DUP S" nbsp" _RTX-ENTITY= IF 2DROP 32 _RTX-EMIT-BYTE EXIT THEN
    2DROP RTEXT-S-UNSUPPORTED _RTX-FAIL ;

\ A semicolon within 32 non-whitespace bytes denotes an entity attempt.
\ Without one, '&' is ordinary literal text (for example, "A & B").
: _RTX-PARSE-ENTITY  ( -- )
    _RTX-POS @ 1+ _RTE-I !
    BEGIN _RTE-I @ _RTX-U @ <
          _RTE-I @ _RTX-POS @ - 33 < AND WHILE
        _RTE-I @ _RTX-AT DUP 59 = IF
            DROP
            _RTE-I @ _RTE-END !
            _RTX-A @ _RTX-POS @ 1+ +
            _RTE-I @ _RTX-POS @ 1+ - DUP 0= IF
                2DROP RTEXT-S-INVALID _RTX-FAIL EXIT
            THEN
            OVER C@ 35 = IF
                _RTX-DECODE-NUMERIC-ENTITY
            ELSE
                _RTX-DECODE-NAMED-ENTITY
            THEN
            _RTE-END @ 1+ _RTX-POS ! EXIT
        THEN
        DUP 60 = OVER 38 = OR SWAP _RTX-ASCII-SPACE? OR IF
            38 _RTX-EMIT-BYTE 1 _RTX-POS +! EXIT
        THEN
        1 _RTE-I +!
    REPEAT
    38 _RTX-EMIT-BYTE 1 _RTX-POS +! ;

\ =====================================================================
\  Media-specific normalizers
\ =====================================================================

: _RTX-NORMALIZE-PLAIN  ( -- )
    0 _RTX-POS !
    BEGIN _RTX-POS @ _RTX-U @ < _RTX-STATUS @ 0= AND WHILE
        _RTX-POS @ _RTX-AT _RTX-EMIT-BYTE
        1 _RTX-POS +!
    REPEAT ;

: _RTX-NORMALIZE-HTML  ( -- )
    0 _RTX-POS ! 0 _RTX-DEPTH ! 0 _RTX-SKIP-DEPTH !
    BEGIN _RTX-POS @ _RTX-U @ < _RTX-STATUS @ 0= AND WHILE
        _RTX-TOP-RAW? IF
            _RTX-SKIP-RAW-TEXT
        ELSE
            _RTX-POS @ _RTX-AT 60 = IF
                _RTX-PARSE-TAG
            ELSE
                _RTX-SKIP-DEPTH @ IF
                    1 _RTX-POS +!
                ELSE
                    _RTX-POS @ _RTX-AT 38 = IF
                        _RTX-PARSE-ENTITY
                    ELSE
                        _RTX-POS @ _RTX-AT _RTX-EMIT-BYTE
                        1 _RTX-POS +!
                    THEN
                THEN
            THEN
        THEN
    REPEAT
    _RTX-STATUS @ 0= _RTX-DEPTH @ 0<> AND IF
        RTEXT-S-INVALID _RTX-FAIL
    THEN ;


\ =====================================================================
\  Guarded public operations
\ =====================================================================

VARIABLE _RTX-SOURCE-A
VARIABLE _RTX-SOURCE-U
VARIABLE _RTX-OVERLAP-SA
VARIABLE _RTX-OVERLAP-SU
VARIABLE _RTX-OVERLAP-DA
VARIABLE _RTX-OVERLAP-DU

: _RTX-SPANS-OVERLAP?
    ( source-a source-u destination-a destination-u -- flag )
    _RTX-OVERLAP-DU ! _RTX-OVERLAP-DA !
    _RTX-OVERLAP-SU ! _RTX-OVERLAP-SA !
    _RTX-OVERLAP-SU @ 0= _RTX-OVERLAP-DU @ 0= OR IF 0 EXIT THEN
    _RTX-OVERLAP-SA @ _RTX-OVERLAP-DA @ <= IF
        _RTX-OVERLAP-DA @ _RTX-OVERLAP-SA @ - _RTX-OVERLAP-SU @ <
    ELSE
        _RTX-OVERLAP-SA @ _RTX-OVERLAP-DA @ - _RTX-OVERLAP-DU @ <
    THEN ;

: _RTX-PREPARE
    ( source-a source-u destination-a destination-cap -- status )
    _RTX-DEST-CAP ! _RTX-DEST ! _RTX-SOURCE-U ! _RTX-SOURCE-A !
    _RTX-SOURCE-U @ 0< _RTX-DEST-CAP @ 0< OR IF
        RTEXT-S-INVALID EXIT
    THEN
    _RTX-SOURCE-A @ 0< _RTX-DEST @ 0< OR IF RTEXT-S-INVALID EXIT THEN
    _RTX-SOURCE-U @ RTEXT-SOURCE-MAX > IF RTEXT-S-CAPACITY EXIT THEN
    _RTX-SOURCE-U @ 0> _RTX-SOURCE-A @ 0= AND IF
        RTEXT-S-INVALID EXIT
    THEN
    _RTX-DEST-CAP @ 0> _RTX-DEST @ 0= AND IF
        RTEXT-S-INVALID EXIT
    THEN
    _RTX-SOURCE-A @ _RTX-SOURCE-U @
    _RTX-DEST @ _RTX-DEST-CAP @ _RTX-SPANS-OVERLAP? IF
        RTEXT-S-INVALID EXIT
    THEN
    _RTX-SOURCE-U @ IF
        _RTX-SOURCE-A @ _RTX-SOURCE-U @ UTF8-VALID? 0= IF
            RTEXT-S-INVALID EXIT
        THEN
    THEN
    _RTX-SOURCE-A @ _RTX-A ! _RTX-SOURCE-U @ _RTX-U !
    0 _RTX-OUT-U ! 0 _RTX-PENDING-SPACE ! RTEXT-S-OK _RTX-STATUS !
    RTEXT-S-OK ;

: _RTX-RESULT  ( -- text-u status )
    _RTX-STATUS @ DUP IF 0 SWAP ELSE DROP _RTX-OUT-U @ RTEXT-S-OK THEN ;

: _RTEXT-PLAIN
    ( source-a source-u destination-a destination-cap -- text-u status )
    _RTX-PREPARE DUP IF 0 SWAP EXIT THEN DROP
    _RTX-NORMALIZE-PLAIN
    _RTX-RESULT ;

: _RTEXT-HTML
    ( source-a source-u destination-a destination-cap -- text-u status )
    _RTX-PREPARE DUP IF 0 SWAP EXIT THEN DROP
    _RTX-NORMALIZE-HTML
    _RTX-RESULT ;

' _RTEXT-PLAIN CONSTANT _rtext-plain-xt
' _RTEXT-HTML  CONSTANT _rtext-html-xt

: RTEXT-PLAIN
    ( source-a source-u destination-a destination-cap -- text-u status )
    _rtext-plain-xt _readable-text-guard WITH-GUARD ;

: RTEXT-HTML
    ( source-a source-u destination-a destination-cap -- text-u status )
    _rtext-html-xt _readable-text-guard WITH-GUARD ;
