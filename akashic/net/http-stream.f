\ =====================================================================
\  http-stream.f - Bounded incremental HTTP/1.x response decoder
\ =====================================================================
\  This module owns response framing only. It has no socket, TLS, request,
\  credential, provider, Agent, or TUI dependency. Callbacks receive borrowed
\  slices through the parser descriptor and must copy data they retain.
\ =====================================================================

PROVIDED akashic-http-stream

REQUIRE ../utils/string.f

0  CONSTANT HSTR-STATE-HEADERS
1  CONSTANT HSTR-STATE-LENGTH
2  CONSTANT HSTR-STATE-CLOSE
3  CONSTANT HSTR-STATE-CHUNK-SIZE
4  CONSTANT HSTR-STATE-CHUNK-SIZE-LF
5  CONSTANT HSTR-STATE-CHUNK-DATA
6  CONSTANT HSTR-STATE-CHUNK-DATA-CR
7  CONSTANT HSTR-STATE-CHUNK-DATA-LF
8  CONSTANT HSTR-STATE-TRAILER
9  CONSTANT HSTR-STATE-TRAILER-LF
10 CONSTANT HSTR-STATE-DONE
11 CONSTANT HSTR-STATE-STOPPED

0  CONSTANT HSTR-S-OK
1  CONSTANT HSTR-S-HEADER-OVERFLOW
2  CONSTANT HSTR-S-MALFORMED
3  CONSTANT HSTR-S-FRAMING
4  CONSTANT HSTR-S-BODY-OVERFLOW
5  CONSTANT HSTR-S-CALLBACK
6  CONSTANT HSTR-S-TRUNCATED
7  CONSTANT HSTR-S-CANCELLED
8  CONSTANT HSTR-S-CLOSED
9  CONSTANT HSTR-S-INTERIM-LIMIT
10 CONSTANT HSTR-S-UNSUPPORTED

1 CONSTANT HSTR-F-HEAD

0 CONSTANT HSTR-BODY-NONE
1 CONSTANT HSTR-BODY-LENGTH
2 CONSTANT HSTR-BODY-CHUNKED
3 CONSTANT HSTR-BODY-CLOSE

1 CONSTANT _HSTR-FR-CL
2 CONSTANT _HSTR-FR-TE

16384 CONSTANT HSTR-HEADER-CAPACITY
2048  CONSTANT HSTR-LINE-CAPACITY
8192  CONSTANT HSTR-TRAILER-CAPACITY
67108864 CONSTANT HSTR-DEFAULT-BODY-LIMIT

  0 CONSTANT _HSTR-STATE
  8 CONSTANT _HSTR-STATUS
 16 CONSTANT _HSTR-FLAGS
 24 CONSTANT _HSTR-CODE
 32 CONSTANT _HSTR-VERSION
 40 CONSTANT _HSTR-BODY-MODE
 48 CONSTANT _HSTR-REMAINING
 56 CONSTANT _HSTR-CHUNK-REMAINING
 64 CONSTANT _HSTR-BODY-TOTAL
 72 CONSTANT _HSTR-BODY-LIMIT
 80 CONSTANT _HSTR-HEADER-U
 88 CONSTANT _HSTR-LINE-U
 96 CONSTANT _HSTR-TRAILER-U
104 CONSTANT _HSTR-CONTENT-LENGTH
112 CONSTANT _HSTR-FRAMING
120 CONSTANT _HSTR-HEADERS-XT      \ ( parser context -- status )
128 CONSTANT _HSTR-BODY-XT         \ ( parser context -- status )
136 CONSTANT _HSTR-CONTEXT
144 CONSTANT _HSTR-BODY-A
152 CONSTANT _HSTR-BODY-U
160 CONSTANT _HSTR-INTERIMS
168 CONSTANT _HSTR-HEADER-BUF
_HSTR-HEADER-BUF HSTR-HEADER-CAPACITY + CONSTANT _HSTR-LINE-BUF
_HSTR-LINE-BUF HSTR-LINE-CAPACITY + CONSTANT HSTR-PARSER-SIZE

: HSTR.STATE          ( parser -- a ) _HSTR-STATE + ;
: HSTR.STATUS         ( parser -- a ) _HSTR-STATUS + ;
: HSTR.FLAGS          ( parser -- a ) _HSTR-FLAGS + ;
: HSTR.CODE           ( parser -- a ) _HSTR-CODE + ;
: HSTR.VERSION        ( parser -- a ) _HSTR-VERSION + ;
: HSTR.BODY-MODE      ( parser -- a ) _HSTR-BODY-MODE + ;
: HSTR.REMAINING      ( parser -- a ) _HSTR-REMAINING + ;
: HSTR.CHUNK-REMAINING ( parser -- a ) _HSTR-CHUNK-REMAINING + ;
: HSTR.BODY-TOTAL     ( parser -- a ) _HSTR-BODY-TOTAL + ;
: HSTR.BODY-LIMIT     ( parser -- a ) _HSTR-BODY-LIMIT + ;
: HSTR.HEADER-U       ( parser -- a ) _HSTR-HEADER-U + ;
: HSTR.LINE-U         ( parser -- a ) _HSTR-LINE-U + ;
: HSTR.TRAILER-U      ( parser -- a ) _HSTR-TRAILER-U + ;
: HSTR.CONTENT-LENGTH ( parser -- a ) _HSTR-CONTENT-LENGTH + ;
: HSTR.FRAMING        ( parser -- a ) _HSTR-FRAMING + ;
: HSTR.HEADERS-XT     ( parser -- a ) _HSTR-HEADERS-XT + ;
: HSTR.BODY-XT        ( parser -- a ) _HSTR-BODY-XT + ;
: HSTR.CONTEXT        ( parser -- a ) _HSTR-CONTEXT + ;
: HSTR.BODY-A         ( parser -- a ) _HSTR-BODY-A + ;
: HSTR.BODY-U         ( parser -- a ) _HSTR-BODY-U + ;
: HSTR.INTERIMS       ( parser -- a ) _HSTR-INTERIMS + ;
: HSTR.HEADER-BUF     ( parser -- a ) _HSTR-HEADER-BUF + ;
: HSTR.LINE-BUF       ( parser -- a ) _HSTR-LINE-BUF + ;

: HSTR-INIT  ( parser -- )
    DUP HSTR-PARSER-SIZE 0 FILL
    HSTR-DEFAULT-BODY-LIMIT SWAP HSTR.BODY-LIMIT ! ;

: HSTR-NEW  ( -- parser ior )
    HSTR-PARSER-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP HSTR-INIT 0 ;

: HSTR-FREE  ( parser -- )
    ?DUP IF DUP HSTR-PARSER-SIZE 0 FILL FREE THEN ;

VARIABLE _HSRS-P
VARIABLE _HSRS-HXT
VARIABLE _HSRS-BXT
VARIABLE _HSRS-CONTEXT
VARIABLE _HSRS-FLAGS
VARIABLE _HSRS-LIMIT

: HSTR-RESET  ( parser -- )
    DUP HSTR.HEADERS-XT @ _HSRS-HXT !
    DUP HSTR.BODY-XT @ _HSRS-BXT !
    DUP HSTR.CONTEXT @ _HSRS-CONTEXT !
    DUP HSTR.FLAGS @ _HSRS-FLAGS !
    DUP HSTR.BODY-LIMIT @ _HSRS-LIMIT !
    DUP _HSRS-P ! HSTR-INIT
    _HSRS-HXT @ _HSRS-P @ HSTR.HEADERS-XT !
    _HSRS-BXT @ _HSRS-P @ HSTR.BODY-XT !
    _HSRS-CONTEXT @ _HSRS-P @ HSTR.CONTEXT !
    _HSRS-FLAGS @ _HSRS-P @ HSTR.FLAGS !
    _HSRS-LIMIT @ DUP 0> IF
        _HSRS-P @ HSTR.BODY-LIMIT !
    ELSE
        DROP
    THEN ;

: HSTR-ON-HEADERS!  ( xt parser -- ) HSTR.HEADERS-XT ! ;
: HSTR-ON-BODY!     ( xt parser -- ) HSTR.BODY-XT ! ;
: HSTR-CONTEXT!     ( context parser -- ) HSTR.CONTEXT ! ;

: HSTR-BODY-LIMIT!  ( limit parser -- )
    OVER 0> IF HSTR.BODY-LIMIT ! ELSE 2DROP THEN ;

: HSTR-HEADERS  ( parser -- addr len )
    DUP HSTR.HEADER-BUF SWAP HSTR.HEADER-U @ ;

: HSTR-BODY-SLICE  ( parser -- addr len )
    DUP HSTR.BODY-A @ SWAP HSTR.BODY-U @ ;

VARIABLE _HSFAIL-P

: _HSTR-FAIL  ( status parser -- )
    _HSFAIL-P !
    _HSFAIL-P @ HSTR.STATUS @ 0= IF
        _HSFAIL-P @ HSTR.STATUS !
    ELSE
        DROP
    THEN
    HSTR-STATE-STOPPED _HSFAIL-P @ HSTR.STATE ! ;

: _HSTR-DIGIT?  ( c -- flag )
    DUP 48 >= SWAP 57 <= AND ;

: _HSTR-OWS?  ( c -- flag )
    DUP 32 = SWAP 9 = OR ;

: _HSTR-HEX  ( c -- n flag )
    DUP 48 >= OVER 57 <= AND IF 48 - -1 EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - -1 EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - -1 EXIT THEN
    DROP 0 0 ;

: _HSTR-TCHAR?  ( c -- flag )
    DUP 33 < IF DROP 0 EXIT THEN
    DUP 126 > IF DROP 0 EXIT THEN
    DUP 34 = OVER 40 = OR OVER 41 = OR OVER 44 = OR
    OVER 47 = OR OVER 58 = OR OVER 59 = OR OVER 60 = OR
    OVER 61 = OR OVER 62 = OR OVER 63 = OR OVER 64 = OR
    OVER 91 = OR OVER 92 = OR OVER 93 = OR OVER 123 = OR
    OVER 125 = OR IF DROP 0 ELSE DROP -1 THEN ;

VARIABLE _HSCI-AA
VARIABLE _HSCI-AU
VARIABLE _HSCI-BA
VARIABLE _HSCI-BU

: _HSTR-CIEQ?  ( aa au ba bu -- flag )
    _HSCI-BU ! _HSCI-BA ! _HSCI-AU ! _HSCI-AA !
    _HSCI-AU @ _HSCI-BU @ <> IF 0 EXIT THEN
    _HSCI-AA @ _HSCI-AU @ _HSCI-BA @ _HSCI-BU @ STR-STARTSI? ;

VARIABLE _HSD-A
VARIABLE _HSD-U
VARIABLE _HSD-N

: _HSTR-DECIMAL  ( addr len -- n flag )
    _HSD-U ! _HSD-A ! 0 _HSD-N !
    _HSD-U @ 0= IF 0 0 EXIT THEN
    _HSD-U @ 0 ?DO
        _HSD-A @ I + C@ DUP _HSTR-DIGIT? 0= IF
            DROP 0 0 UNLOOP EXIT
        THEN
        48 -
        _HSD-N @ 214748364 > IF DROP 0 0 UNLOOP EXIT THEN
        _HSD-N @ 10 * + DUP 2147483647 > IF
            DROP 0 0 UNLOOP EXIT
        THEN
        _HSD-N !
    LOOP
    _HSD-N @ -1 ;

VARIABLE _HSL-A
VARIABLE _HSL-U
VARIABLE _HSL-P
VARIABLE _HSL-COLON
VARIABLE _HSL-NA
VARIABLE _HSL-NU
VARIABLE _HSL-VA
VARIABLE _HSL-VU
VARIABLE _HSL-N

: _HSTR-HEADER-LINE  ( addr len parser -- status )
    _HSL-P ! _HSL-U ! _HSL-A !
    _HSL-U @ 0= IF HSTR-S-MALFORMED EXIT THEN
    _HSL-A @ C@ DUP 32 = SWAP 9 = OR IF HSTR-S-MALFORMED EXIT THEN
    -1 _HSL-COLON !
    _HSL-U @ 0 ?DO
        _HSL-COLON @ 0< IF
            _HSL-A @ I + C@ DUP 58 = IF
                DROP I _HSL-COLON !
            ELSE
                _HSTR-TCHAR? 0= IF HSTR-S-MALFORMED UNLOOP EXIT THEN
            THEN
        THEN
    LOOP
    _HSL-COLON @ 1 < IF HSTR-S-MALFORMED EXIT THEN
    _HSL-A @ _HSL-NA ! _HSL-COLON @ _HSL-NU !
    _HSL-A @ _HSL-COLON @ 1+ + _HSL-VA !
    _HSL-U @ _HSL-COLON @ 1+ - _HSL-VU !
    BEGIN _HSL-VU @ 0> IF _HSL-VA @ C@ _HSTR-OWS? ELSE 0 THEN WHILE
        1 _HSL-VA +! -1 _HSL-VU +!
    REPEAT
    BEGIN _HSL-VU @ 0> IF
        _HSL-VA @ _HSL-VU @ 1- + C@ _HSTR-OWS?
    ELSE 0 THEN WHILE
        -1 _HSL-VU +!
    REPEAT
    _HSL-VU @ 0 ?DO
        _HSL-VA @ I + C@ DUP 9 = IF DROP ELSE
            DUP 32 < OVER 127 = OR IF DROP HSTR-S-MALFORMED UNLOOP EXIT THEN
            DROP
        THEN
    LOOP

    _HSL-NA @ _HSL-NU @ S" content-length" _HSTR-CIEQ? IF
        _HSL-VA @ _HSL-VU @ _HSTR-DECIMAL 0= IF
            DROP HSTR-S-FRAMING EXIT
        THEN
        _HSL-N !
        _HSL-P @ HSTR.FRAMING @ _HSTR-FR-CL AND IF
            _HSL-P @ HSTR.CONTENT-LENGTH @ _HSL-N @ <> IF
                HSTR-S-FRAMING EXIT
            THEN
        ELSE
            _HSL-N @ _HSL-P @ HSTR.CONTENT-LENGTH !
            _HSL-P @ HSTR.FRAMING DUP @ _HSTR-FR-CL OR SWAP !
        THEN
    THEN

    _HSL-NA @ _HSL-NU @ S" transfer-encoding" _HSTR-CIEQ? IF
        _HSL-P @ HSTR.FRAMING @ _HSTR-FR-TE AND IF HSTR-S-FRAMING EXIT THEN
        _HSL-VA @ _HSL-VU @ S" chunked" _HSTR-CIEQ? 0= IF
            HSTR-S-UNSUPPORTED EXIT
        THEN
        _HSL-P @ HSTR.FRAMING DUP @ _HSTR-FR-TE OR SWAP !
    THEN
    HSTR-S-OK ;

VARIABLE _HSP-P
VARIABLE _HSP-BASE
VARIABLE _HSP-END
VARIABLE _HSP-PTR
VARIABLE _HSP-LEND
VARIABLE _HSP-LEN
VARIABLE _HSP-CODE

VARIABLE _HFCR-PTR
VARIABLE _HFCR-END

: _HSTR-FIND-CRLF  ( addr end -- line-end | 0 )
    _HFCR-END ! _HFCR-PTR !
    BEGIN _HFCR-PTR @ 1+ _HFCR-END @ < WHILE
        _HFCR-PTR @ C@ 13 = _HFCR-PTR @ 1+ C@ 10 = AND IF
            _HFCR-PTR @ EXIT
        THEN
        1 _HFCR-PTR +!
    REPEAT
    0 ;

: _HSTR-STATUS-LINE  ( addr len parser -- status )
    _HSL-P ! _HSL-U ! _HSL-A !
    _HSL-U @ 13 < IF HSTR-S-MALFORMED EXIT THEN
    _HSL-A @ 7 S" HTTP/1." COMPARE 0<> IF HSTR-S-MALFORMED EXIT THEN
    _HSL-A @ 7 + C@ DUP 48 = IF
        DROP 10
    ELSE 49 = IF
        11
    ELSE
        HSTR-S-UNSUPPORTED EXIT
    THEN THEN
    _HSL-P @ HSTR.VERSION !
    _HSL-A @ 8 + C@ 32 <> IF HSTR-S-MALFORMED EXIT THEN
    _HSL-A @ 9 + C@ _HSTR-DIGIT?
    _HSL-A @ 10 + C@ _HSTR-DIGIT? AND
    _HSL-A @ 11 + C@ _HSTR-DIGIT? AND 0= IF HSTR-S-MALFORMED EXIT THEN
    _HSL-A @ 12 + C@ 32 <> IF HSTR-S-MALFORMED EXIT THEN
    _HSL-A @ 9 + C@ 48 - 100 *
    _HSL-A @ 10 + C@ 48 - 10 * +
    _HSL-A @ 11 + C@ 48 - + DUP _HSP-CODE !
    _HSL-P @ HSTR.CODE !
    _HSL-U @ 13 ?DO
        _HSL-A @ I + C@ DUP 9 = IF DROP ELSE
            DUP 32 < OVER 127 = OR IF DROP HSTR-S-MALFORMED UNLOOP EXIT THEN
            DROP
        THEN
    LOOP
    HSTR-S-OK ;

VARIABLE _HSC-P
VARIABLE _HSC-XT
VARIABLE _HSC-RESULT

: _HSTR-CALL-INNER  ( -- )
    _HSC-P @ _HSC-P @ HSTR.CONTEXT @ _HSC-XT @ EXECUTE
    _HSC-RESULT ! ;

: _HSTR-CALL  ( xt parser -- status )
    _HSC-P ! _HSC-XT ! 0 _HSC-RESULT !
    ['] _HSTR-CALL-INNER CATCH DUP IF
        DROP HSTR-S-CALLBACK
    ELSE
        DROP _HSC-RESULT @ IF HSTR-S-CALLBACK ELSE HSTR-S-OK THEN
    THEN ;

: _HSTR-MESSAGE-RESET  ( parser -- )
    DUP 0 SWAP HSTR.CODE !
    DUP 0 SWAP HSTR.VERSION !
    DUP HSTR-BODY-NONE SWAP HSTR.BODY-MODE !
    DUP 0 SWAP HSTR.REMAINING !
    DUP 0 SWAP HSTR.CHUNK-REMAINING !
    DUP 0 SWAP HSTR.HEADER-U !
    DUP 0 SWAP HSTR.LINE-U !
    DUP 0 SWAP HSTR.TRAILER-U !
    DUP 0 SWAP HSTR.CONTENT-LENGTH !
    0 SWAP HSTR.FRAMING ! ;

: _HSTR-FINAL-HEADERS  ( parser -- status )
    _HSP-P !
    _HSP-P @ HSTR.FLAGS @ HSTR-F-HEAD AND
    _HSP-P @ HSTR.CODE @ 204 = OR
    _HSP-P @ HSTR.CODE @ 304 = OR IF
        HSTR-BODY-NONE _HSP-P @ HSTR.BODY-MODE !
        HSTR-STATE-DONE _HSP-P @ HSTR.STATE !
    ELSE
        _HSP-P @ HSTR.FRAMING @ _HSTR-FR-TE AND IF
            HSTR-BODY-CHUNKED _HSP-P @ HSTR.BODY-MODE !
            HSTR-STATE-CHUNK-SIZE _HSP-P @ HSTR.STATE !
        ELSE
            _HSP-P @ HSTR.FRAMING @ _HSTR-FR-CL AND IF
                _HSP-P @ HSTR.CONTENT-LENGTH @
                DUP _HSP-P @ HSTR.BODY-LIMIT @ > IF
                    DROP HSTR-S-BODY-OVERFLOW EXIT
                THEN
                DUP _HSP-P @ HSTR.REMAINING !
                HSTR-BODY-LENGTH _HSP-P @ HSTR.BODY-MODE !
                0= IF HSTR-STATE-DONE ELSE HSTR-STATE-LENGTH THEN
                _HSP-P @ HSTR.STATE !
            ELSE
                HSTR-BODY-CLOSE _HSP-P @ HSTR.BODY-MODE !
                HSTR-STATE-CLOSE _HSP-P @ HSTR.STATE !
            THEN
        THEN
    THEN
    _HSP-P @ HSTR.HEADERS-XT @ ?DUP IF
        _HSP-P @ _HSTR-CALL DUP IF EXIT THEN DROP
    THEN
    HSTR-S-OK ;

: _HSTR-PARSE-HEADERS  ( parser -- status )
    DUP _HSP-P ! HSTR.HEADER-BUF _HSP-BASE !
    _HSP-BASE @ _HSP-P @ HSTR.HEADER-U @ + _HSP-END !
    _HSP-BASE @ _HSP-END @ _HSTR-FIND-CRLF DUP 0= IF
        HSTR-S-MALFORMED EXIT
    THEN
    DUP _HSP-LEND ! _HSP-BASE @ - _HSP-LEN !
    _HSP-BASE @ _HSP-LEN @ _HSP-P @ _HSTR-STATUS-LINE
    DUP IF EXIT THEN DROP
    _HSP-LEND @ 2 + _HSP-PTR !
    BEGIN _HSP-PTR @ _HSP-END @ < WHILE
        _HSP-PTR @ 2 + _HSP-END @ > IF HSTR-S-MALFORMED EXIT THEN
        _HSP-PTR @ C@ 13 = _HSP-PTR @ 1+ C@ 10 = AND IF
            _HSP-PTR @ 2 + _HSP-END @ <> IF HSTR-S-MALFORMED EXIT THEN
            _HSP-END @ _HSP-PTR !
        ELSE
            _HSP-PTR @ _HSP-END @ _HSTR-FIND-CRLF DUP 0= IF
                HSTR-S-MALFORMED EXIT
            THEN
            DUP _HSP-LEND ! _HSP-PTR @ - _HSP-LEN !
            _HSP-PTR @ _HSP-LEN @ _HSP-P @ _HSTR-HEADER-LINE
            DUP IF EXIT THEN DROP
            _HSP-LEND @ 2 + _HSP-PTR !
        THEN
    REPEAT
    _HSP-P @ HSTR.FRAMING @ _HSTR-FR-CL _HSTR-FR-TE OR AND
    _HSTR-FR-CL _HSTR-FR-TE OR = IF
        HSTR-S-FRAMING EXIT
    THEN
    _HSP-P @ HSTR.CODE @ DUP 100 >= SWAP 200 < AND IF
        _HSP-P @ HSTR.CODE @ 101 = IF HSTR-S-UNSUPPORTED EXIT THEN
        1 _HSP-P @ HSTR.INTERIMS +!
        _HSP-P @ HSTR.INTERIMS @ 8 > IF HSTR-S-INTERIM-LIMIT EXIT THEN
        _HSP-P @ _HSTR-MESSAGE-RESET
        HSTR-STATE-HEADERS _HSP-P @ HSTR.STATE ! HSTR-S-OK EXIT
    THEN
    _HSP-P @ _HSTR-FINAL-HEADERS ;

VARIABLE _HSHB-P
VARIABLE _HSHB-C

: _HSTR-HEADER-BYTE  ( c parser -- )
    _HSHB-P ! _HSHB-C !
    _HSHB-P @ HSTR.HEADER-U @ HSTR-HEADER-CAPACITY >= IF
        HSTR-S-HEADER-OVERFLOW _HSHB-P @ _HSTR-FAIL EXIT
    THEN
    _HSHB-P @ HSTR.HEADER-U @ 0> IF
        _HSHB-P @ HSTR.HEADER-BUF _HSHB-P @ HSTR.HEADER-U @ 1- + C@
        13 = _HSHB-C @ 10 <> AND IF
            HSTR-S-MALFORMED _HSHB-P @ _HSTR-FAIL EXIT
        THEN
    THEN
    _HSHB-C @ 10 = IF
        _HSHB-P @ HSTR.HEADER-U @ 0= IF
            HSTR-S-MALFORMED _HSHB-P @ _HSTR-FAIL EXIT
        THEN
        _HSHB-P @ HSTR.HEADER-BUF _HSHB-P @ HSTR.HEADER-U @ 1- + C@
        13 <> IF HSTR-S-MALFORMED _HSHB-P @ _HSTR-FAIL EXIT THEN
    THEN
    _HSHB-C @ _HSHB-P @ HSTR.HEADER-BUF
    _HSHB-P @ HSTR.HEADER-U @ + C!
    1 _HSHB-P @ HSTR.HEADER-U +!
    _HSHB-P @ HSTR.HEADER-U @ 4 >= IF
        _HSHB-P @ HSTR.HEADER-BUF _HSHB-P @ HSTR.HEADER-U @ 4 - +
        DUP C@ 13 = OVER 1+ C@ 10 = AND
        OVER 2 + C@ 13 = AND SWAP 3 + C@ 10 = AND IF
            _HSHB-P @ _HSTR-PARSE-HEADERS DUP IF
                _HSHB-P @ _HSTR-FAIL
            ELSE
                DROP
            THEN
        THEN
    THEN ;

VARIABLE _HSE-P
VARIABLE _HSE-A
VARIABLE _HSE-U

: _HSTR-EMIT  ( addr len parser -- status )
    _HSE-P ! _HSE-U ! _HSE-A !
    _HSE-P @ HSTR.BODY-TOTAL @ _HSE-U @ +
    _HSE-P @ HSTR.BODY-LIMIT @ > IF HSTR-S-BODY-OVERFLOW EXIT THEN
    _HSE-A @ _HSE-P @ HSTR.BODY-A !
    _HSE-U @ _HSE-P @ HSTR.BODY-U !
    _HSE-P @ HSTR.BODY-XT @ ?DUP IF
        _HSE-P @ _HSTR-CALL
    ELSE
        HSTR-S-OK
    THEN
    DUP 0= IF _HSE-U @ _HSE-P @ HSTR.BODY-TOTAL +! THEN
    0 _HSE-P @ HSTR.BODY-A ! 0 _HSE-P @ HSTR.BODY-U ! ;

VARIABLE _HSCZ-P
VARIABLE _HSCZ-U
VARIABLE _HSCZ-N
VARIABLE _HSCZ-DIGITS
VARIABLE _HSCZ-EXT
VARIABLE _HSCZ-EXT-TEXT

: _HSTR-PARSE-CHUNK-SIZE  ( parser -- status )
    DUP _HSCZ-P ! HSTR.LINE-U @ DUP _HSCZ-U !
    0= IF HSTR-S-FRAMING EXIT THEN
    0 _HSCZ-N ! 0 _HSCZ-DIGITS ! -1 _HSCZ-EXT !
    _HSCZ-U @ 0 ?DO
        _HSCZ-EXT @ 0< IF
            _HSCZ-P @ HSTR.LINE-BUF I + C@ DUP 59 = IF
                DROP I 1+ _HSCZ-EXT !
            ELSE
                _HSTR-HEX 0= IF DROP HSTR-S-FRAMING UNLOOP EXIT THEN
                _HSCZ-DIGITS @ 16 >= IF
                    DROP HSTR-S-BODY-OVERFLOW UNLOOP EXIT
                THEN
                _HSCZ-N @ 16 * + DUP _HSCZ-P @ HSTR.BODY-LIMIT @ > IF
                    DROP HSTR-S-BODY-OVERFLOW UNLOOP EXIT
                THEN
                _HSCZ-N ! 1 _HSCZ-DIGITS +!
            THEN
        THEN
    LOOP
    _HSCZ-DIGITS @ 0= IF HSTR-S-FRAMING EXIT THEN
    _HSCZ-EXT @ 0>= IF
        _HSCZ-EXT @ _HSCZ-U @ >= IF HSTR-S-FRAMING EXIT THEN
        0 _HSCZ-EXT-TEXT !
        _HSCZ-U @ _HSCZ-EXT @ ?DO
            _HSCZ-P @ HSTR.LINE-BUF I + C@
            DUP 9 = OVER 32 = OR IF DROP ELSE
                DUP 33 < OVER 126 > OR IF
                    DROP HSTR-S-FRAMING UNLOOP EXIT
                THEN
                DROP 1 _HSCZ-EXT-TEXT !
            THEN
        LOOP
        _HSCZ-EXT-TEXT @ 0= IF HSTR-S-FRAMING EXIT THEN
    THEN
    _HSCZ-N @ _HSCZ-P @ HSTR.BODY-TOTAL @ +
    _HSCZ-P @ HSTR.BODY-LIMIT @ > IF HSTR-S-BODY-OVERFLOW EXIT THEN
    _HSCZ-N @ _HSCZ-P @ HSTR.CHUNK-REMAINING !
    0 _HSCZ-P @ HSTR.LINE-U !
    _HSCZ-N @ 0= IF
        HSTR-STATE-TRAILER
    ELSE
        HSTR-STATE-CHUNK-DATA
    THEN
    _HSCZ-P @ HSTR.STATE ! HSTR-S-OK ;

VARIABLE _HSTL-P
VARIABLE _HSTL-FRAMING
VARIABLE _HSTL-CL
VARIABLE _HSTL-NEW-FRAMING

: _HSTR-TRAILER-LINE  ( parser -- status )
    DUP _HSTL-P ! HSTR.LINE-U @ 0= IF
        HSTR-STATE-DONE _HSTL-P @ HSTR.STATE ! HSTR-S-OK EXIT
    THEN
    _HSTL-P @ HSTR.FRAMING @ _HSTL-FRAMING !
    _HSTL-P @ HSTR.CONTENT-LENGTH @ _HSTL-CL !
    0 _HSTL-P @ HSTR.FRAMING !
    _HSTL-P @ HSTR.LINE-BUF _HSTL-P @ HSTR.LINE-U @ _HSTL-P @
    _HSTR-HEADER-LINE
    _HSTL-P @ HSTR.FRAMING @ _HSTL-NEW-FRAMING !
    _HSTL-FRAMING @ _HSTL-P @ HSTR.FRAMING !
    _HSTL-CL @ _HSTL-P @ HSTR.CONTENT-LENGTH !
    DUP IF EXIT THEN DROP
    _HSTL-NEW-FRAMING @ IF HSTR-S-FRAMING EXIT THEN
    0 _HSTL-P @ HSTR.LINE-U ! HSTR-STATE-TRAILER _HSTL-P @ HSTR.STATE !
    HSTR-S-OK ;

: _HSTR-LINE-BYTE  ( c parser -- status )
    _HSHB-P ! _HSHB-C !
    _HSHB-P @ HSTR.LINE-U @ HSTR-LINE-CAPACITY >= IF
        HSTR-S-FRAMING EXIT
    THEN
    _HSHB-C @ _HSHB-P @ HSTR.LINE-BUF _HSHB-P @ HSTR.LINE-U @ + C!
    1 _HSHB-P @ HSTR.LINE-U +! HSTR-S-OK ;

VARIABLE _HSF-A
VARIABLE _HSF-U
VARIABLE _HSF-P
VARIABLE _HSF-N
VARIABLE _HSF-C

: _HSF-ADVANCE  ( n -- )
    DUP _HSF-A +! NEGATE _HSF-U +! ;

: _HSF-FAIL  ( status -- )
    _HSF-P @ _HSTR-FAIL ;

: HSTR-FEED  ( addr len parser -- status )
    _HSF-P ! _HSF-U ! _HSF-A !
    _HSF-P @ HSTR.STATE @ HSTR-STATE-DONE = IF
        _HSF-U @ IF HSTR-S-FRAMING ELSE HSTR-S-OK THEN EXIT
    THEN
    _HSF-P @ HSTR.STATE @ HSTR-STATE-STOPPED = IF
        _HSF-P @ HSTR.STATUS @ EXIT
    THEN
    BEGIN _HSF-U @ 0> _HSF-P @ HSTR.STATUS @ 0= AND WHILE
        _HSF-P @ HSTR.STATE @ CASE
            HSTR-STATE-HEADERS OF
                _HSF-A @ C@ _HSF-P @ _HSTR-HEADER-BYTE
                1 _HSF-ADVANCE
            ENDOF
            HSTR-STATE-LENGTH OF
                _HSF-U @ _HSF-P @ HSTR.REMAINING @ MIN _HSF-N !
                _HSF-A @ _HSF-N @ _HSF-P @ _HSTR-EMIT DUP IF
                    _HSF-FAIL
                ELSE
                    DROP _HSF-N @ DUP _HSF-ADVANCE
                    NEGATE _HSF-P @ HSTR.REMAINING +!
                    _HSF-P @ HSTR.REMAINING @ 0= IF
                        HSTR-STATE-DONE _HSF-P @ HSTR.STATE !
                    THEN
                THEN
            ENDOF
            HSTR-STATE-CLOSE OF
                _HSF-A @ _HSF-U @ _HSF-P @ _HSTR-EMIT DUP IF
                    _HSF-FAIL
                ELSE
                    DROP _HSF-U @ _HSF-ADVANCE
                THEN
            ENDOF
            HSTR-STATE-CHUNK-SIZE OF
                _HSF-A @ C@ DUP _HSF-C ! 13 = IF
                    HSTR-STATE-CHUNK-SIZE-LF _HSF-P @ HSTR.STATE !
                ELSE
                    _HSF-C @ 10 = IF
                        HSTR-S-FRAMING _HSF-FAIL
                    ELSE
                        _HSF-C @ _HSF-P @ _HSTR-LINE-BYTE DUP IF
                            _HSF-FAIL
                        ELSE
                            DROP
                        THEN
                    THEN
                THEN
                1 _HSF-ADVANCE
            ENDOF
            HSTR-STATE-CHUNK-SIZE-LF OF
                _HSF-A @ C@ 10 <> IF
                    HSTR-S-FRAMING _HSF-FAIL
                ELSE
                    _HSF-P @ _HSTR-PARSE-CHUNK-SIZE DUP IF
                        _HSF-FAIL
                    ELSE
                        DROP
                    THEN
                THEN
                1 _HSF-ADVANCE
            ENDOF
            HSTR-STATE-CHUNK-DATA OF
                _HSF-U @ _HSF-P @ HSTR.CHUNK-REMAINING @ MIN _HSF-N !
                _HSF-A @ _HSF-N @ _HSF-P @ _HSTR-EMIT DUP IF
                    _HSF-FAIL
                ELSE
                    DROP _HSF-N @ DUP _HSF-ADVANCE
                    NEGATE _HSF-P @ HSTR.CHUNK-REMAINING +!
                    _HSF-P @ HSTR.CHUNK-REMAINING @ 0= IF
                        HSTR-STATE-CHUNK-DATA-CR _HSF-P @ HSTR.STATE !
                    THEN
                THEN
            ENDOF
            HSTR-STATE-CHUNK-DATA-CR OF
                _HSF-A @ C@ 13 <> IF HSTR-S-FRAMING _HSF-FAIL ELSE
                    HSTR-STATE-CHUNK-DATA-LF _HSF-P @ HSTR.STATE !
                THEN
                1 _HSF-ADVANCE
            ENDOF
            HSTR-STATE-CHUNK-DATA-LF OF
                _HSF-A @ C@ 10 <> IF HSTR-S-FRAMING _HSF-FAIL ELSE
                    HSTR-STATE-CHUNK-SIZE _HSF-P @ HSTR.STATE !
                THEN
                1 _HSF-ADVANCE
            ENDOF
            HSTR-STATE-TRAILER OF
                1 _HSF-P @ HSTR.TRAILER-U +!
                _HSF-P @ HSTR.TRAILER-U @ HSTR-TRAILER-CAPACITY > IF
                    HSTR-S-FRAMING _HSF-FAIL
                ELSE
                    _HSF-A @ C@ DUP _HSF-C ! 13 = IF
                        HSTR-STATE-TRAILER-LF _HSF-P @ HSTR.STATE !
                    ELSE
                        _HSF-C @ 10 = IF HSTR-S-FRAMING _HSF-FAIL ELSE
                            _HSF-C @ _HSF-P @ _HSTR-LINE-BYTE DUP IF
                                _HSF-FAIL
                            ELSE
                                DROP
                            THEN
                        THEN
                    THEN
                THEN
                1 _HSF-ADVANCE
            ENDOF
            HSTR-STATE-TRAILER-LF OF
                1 _HSF-P @ HSTR.TRAILER-U +!
                _HSF-A @ C@ 10 <> IF HSTR-S-FRAMING _HSF-FAIL ELSE
                    _HSF-P @ _HSTR-TRAILER-LINE DUP IF
                        _HSF-FAIL
                    ELSE
                        DROP
                    THEN
                THEN
                1 _HSF-ADVANCE
            ENDOF
            HSTR-S-FRAMING _HSF-FAIL
        ENDCASE
    REPEAT
    _HSF-P @ HSTR.STATUS @ DUP IF EXIT THEN DROP
    _HSF-U @ 0> IF HSTR-S-FRAMING ELSE HSTR-S-OK THEN ;

: HSTR-EOF  ( parser -- status )
    DUP HSTR.STATE @ HSTR-STATE-DONE = IF DROP HSTR-S-OK EXIT THEN
    DUP HSTR.STATE @ HSTR-STATE-CLOSE = IF
        HSTR-STATE-DONE OVER HSTR.STATE ! DROP HSTR-S-OK EXIT
    THEN
    DUP HSTR.STATE @ HSTR-STATE-STOPPED = IF HSTR.STATUS @ EXIT THEN
    HSTR-S-TRUNCATED OVER _HSTR-FAIL HSTR.STATUS @ ;

: HSTR-CANCEL  ( parser -- )
    DUP HSTR.STATE @ HSTR-STATE-DONE <> IF
        HSTR-S-CANCELLED OVER HSTR.STATUS !
        HSTR-STATE-STOPPED SWAP HSTR.STATE !
    ELSE
        DROP
    THEN ;

VARIABLE _HSH-A
VARIABLE _HSH-U
VARIABLE _HSH-P
VARIABLE _HSH-NA
VARIABLE _HSH-NU
VARIABLE _HSH-END
VARIABLE _HSH-PTR
VARIABLE _HSH-LEND
VARIABLE _HSH-COLON
VARIABLE _HSH-VA
VARIABLE _HSH-VU

: HSTR-HEADER  ( name-a name-u parser -- value-a value-u flag )
    _HSH-P ! _HSH-NU ! _HSH-NA !
    _HSH-P @ HSTR.HEADER-U @ 0= IF 0 0 0 EXIT THEN
    _HSH-P @ HSTR.HEADER-BUF _HSH-A !
    _HSH-A @ _HSH-P @ HSTR.HEADER-U @ + _HSH-END !
    _HSH-A @ _HSH-END @ _HSTR-FIND-CRLF DUP 0= IF 0 0 0 EXIT THEN
    2 + _HSH-PTR !
    BEGIN _HSH-PTR @ 2 + _HSH-END @ <= WHILE
        _HSH-PTR @ C@ 13 = _HSH-PTR @ 1+ C@ 10 = AND IF
            _HSH-END @ _HSH-PTR !
        ELSE
            _HSH-PTR @ _HSH-END @ _HSTR-FIND-CRLF DUP 0= IF 0 0 0 EXIT THEN
            DUP _HSH-LEND ! _HSH-PTR @ - _HSH-U !
            -1 _HSH-COLON !
            _HSH-U @ 0 ?DO
                _HSH-COLON @ 0< IF
                    _HSH-PTR @ I + C@ 58 = IF I _HSH-COLON ! THEN
                THEN
            LOOP
            _HSH-COLON @ 0> IF
                _HSH-PTR @ _HSH-COLON @ _HSH-NA @ _HSH-NU @ _HSTR-CIEQ? IF
                    _HSH-PTR @ _HSH-COLON @ 1+ + _HSH-VA !
                    _HSH-U @ _HSH-COLON @ 1+ - _HSH-VU !
                    BEGIN _HSH-VU @ 0> IF
                        _HSH-VA @ C@ _HSTR-OWS?
                    ELSE 0 THEN WHILE
                        1 _HSH-VA +! -1 _HSH-VU +!
                    REPEAT
                    BEGIN _HSH-VU @ 0> IF
                        _HSH-VA @ _HSH-VU @ 1- + C@ _HSTR-OWS?
                    ELSE 0 THEN WHILE
                        -1 _HSH-VU +!
                    REPEAT
                    _HSH-VA @ _HSH-VU @ -1 EXIT
                THEN
            THEN
            _HSH-LEND @ 2 + _HSH-PTR !
        THEN
    REPEAT
    0 0 0 ;

\ =====================================================================
\  Injected cooperative receive port
\ =====================================================================
\  RECV-XT: ( buffer capacity context -- count io-status )
\  POLL-XT: ( context -- )
\  CLOSE-XT: ( context -- )

0 CONSTANT HIO-S-OK
1 CONSTANT HIO-S-EOF
2 CONSTANT HIO-S-FAILED
3 CONSTANT HIO-S-CANCELLED

0 CONSTANT HSTR-PUMP-IDLE
1 CONSTANT HSTR-PUMP-PROGRESS
2 CONSTANT HSTR-PUMP-DONE
3 CONSTANT HSTR-PUMP-PARSER-ERROR
4 CONSTANT HSTR-PUMP-TRANSPORT-ERROR
5 CONSTANT HSTR-PUMP-CANCELLED

 0 CONSTANT _HIO-CONTEXT
 8 CONSTANT _HIO-RECV-XT
16 CONSTANT _HIO-POLL-XT
24 CONSTANT _HIO-CLOSE-XT
32 CONSTANT HIO-PORT-SIZE

: HIO.CONTEXT  ( port -- a ) _HIO-CONTEXT + ;
: HIO.RECV-XT  ( port -- a ) _HIO-RECV-XT + ;
: HIO.POLL-XT  ( port -- a ) _HIO-POLL-XT + ;
: HIO.CLOSE-XT ( port -- a ) _HIO-CLOSE-XT + ;

: HIO-INIT  ( port -- ) HIO-PORT-SIZE 0 FILL ;

: HIO-POLL  ( port -- )
    DUP HIO.POLL-XT @ ?DUP IF
        >R HIO.CONTEXT @ R> EXECUTE
    ELSE
        DROP
    THEN ;

: HIO-CLOSE  ( port -- )
    DUP HIO.CLOSE-XT @ ?DUP IF
        >R HIO.CONTEXT @ R> EXECUTE
    ELSE
        DROP
    THEN ;

VARIABLE _HIO-R-PORT
VARIABLE _HIO-R-XT
VARIABLE _HIO-R-N
VARIABLE _HIO-R-STATUS

: _HIO-RECV-INNER  ( buffer capacity -- )
    _HIO-R-PORT @ HIO.CONTEXT @ _HIO-R-XT @ EXECUTE
    _HIO-R-STATUS ! _HIO-R-N ! ;

: HIO-RECV  ( buffer capacity port -- count io-status )
    DUP 0= IF DROP 2DROP 0 HIO-S-FAILED EXIT THEN
    DUP _HIO-R-PORT ! HIO.RECV-XT @ DUP 0= IF
        DROP 2DROP 0 HIO-S-FAILED EXIT
    THEN
    _HIO-R-XT ! 0 _HIO-R-N ! HIO-S-FAILED _HIO-R-STATUS !
    ['] _HIO-RECV-INNER CATCH IF 2DROP 0 HIO-S-FAILED EXIT THEN
    _HIO-R-N @ _HIO-R-STATUS @ ;

VARIABLE _HSPM-PARSER
VARIABLE _HSPM-PORT
VARIABLE _HSPM-BUFFER
VARIABLE _HSPM-CAPACITY
VARIABLE _HSPM-N
VARIABLE _HSPM-IO

: HSTR-PUMP  ( parser port buffer capacity -- pump-status )
    _HSPM-CAPACITY ! _HSPM-BUFFER ! _HSPM-PORT ! _HSPM-PARSER !
    _HSPM-PARSER @ HSTR.STATE @ HSTR-STATE-DONE = IF
        HSTR-PUMP-DONE EXIT
    THEN
    _HSPM-PARSER @ HSTR.STATUS @ IF HSTR-PUMP-PARSER-ERROR EXIT THEN
    _HSPM-CAPACITY @ 0> 0= IF HSTR-PUMP-TRANSPORT-ERROR EXIT THEN
    _HSPM-PORT @ HIO-POLL
    _HSPM-BUFFER @ _HSPM-CAPACITY @ _HSPM-PORT @ HIO-RECV
    _HSPM-IO ! _HSPM-N !
    _HSPM-IO @ HIO-S-CANCELLED = IF
        _HSPM-PARSER @ HSTR-CANCEL HSTR-PUMP-CANCELLED EXIT
    THEN
    _HSPM-IO @ HIO-S-EOF = IF
        _HSPM-PARSER @ HSTR-EOF DUP IF
            DROP HSTR-PUMP-PARSER-ERROR
        ELSE
            DROP HSTR-PUMP-DONE
        THEN
        EXIT
    THEN
    _HSPM-IO @ HIO-S-OK <> IF HSTR-PUMP-TRANSPORT-ERROR EXIT THEN
    _HSPM-N @ 0< _HSPM-N @ _HSPM-CAPACITY @ > OR IF
        HSTR-PUMP-TRANSPORT-ERROR EXIT
    THEN
    _HSPM-N @ 0= IF HSTR-PUMP-IDLE EXIT THEN
    _HSPM-BUFFER @ _HSPM-N @ _HSPM-PARSER @ HSTR-FEED DUP IF
        DROP HSTR-PUMP-PARSER-ERROR
    ELSE
        DROP _HSPM-PARSER @ HSTR.STATE @ HSTR-STATE-DONE = IF
            HSTR-PUMP-DONE
        ELSE
            HSTR-PUMP-PROGRESS
        THEN
    THEN ;

\ Persistent response and pump state is descriptor-owned. Internal scan and
\ callback scratch is shared, so calls are safe to interleave cooperatively but
\ must be serialized if a future runtime permits preemption inside a call.
