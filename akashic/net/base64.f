\ base64.f — Base64 encode/decode for KDOS / Megapad-64 (RFC 4648)
\
\ Provides standard Base64 and URL-safe Base64 encoding/decoding.
\ Variable-based state — same approach as url.f.
\
\ Prefix: B64-   (public API)
\         _B64-  (internal helpers)
\
\ Load with:   REQUIRE base64.f

PROVIDED akashic-base64

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE B64-ERR
1 CONSTANT B64-E-INVALID
2 CONSTANT B64-E-OVERFLOW

: B64-FAIL       ( code -- )  B64-ERR ! ;
: B64-OK?        ( -- flag )  B64-ERR @ 0= ;
: B64-CLEAR-ERR  ( -- )       0 B64-ERR ! ;

\ =====================================================================
\  Lookup Tables
\ =====================================================================

\ Standard alphabet: A-Z a-z 0-9 + /
CREATE _B64-TABLE
  65 C,  66 C,  67 C,  68 C,  69 C,  70 C,  71 C,  72 C,
  73 C,  74 C,  75 C,  76 C,  77 C,  78 C,  79 C,  80 C,
  81 C,  82 C,  83 C,  84 C,  85 C,  86 C,  87 C,  88 C,
  89 C,  90 C,
  97 C,  98 C,  99 C, 100 C, 101 C, 102 C, 103 C, 104 C,
 105 C, 106 C, 107 C, 108 C, 109 C, 110 C, 111 C, 112 C,
 113 C, 114 C, 115 C, 116 C, 117 C, 118 C, 119 C, 120 C,
 121 C, 122 C,
  48 C,  49 C,  50 C,  51 C,  52 C,  53 C,  54 C,  55 C,
  56 C,  57 C,
  43 C,  47 C,

\ URL-safe alphabet: A-Z a-z 0-9 - _
CREATE _B64-TABLE-URL
  65 C,  66 C,  67 C,  68 C,  69 C,  70 C,  71 C,  72 C,
  73 C,  74 C,  75 C,  76 C,  77 C,  78 C,  79 C,  80 C,
  81 C,  82 C,  83 C,  84 C,  85 C,  86 C,  87 C,  88 C,
  89 C,  90 C,
  97 C,  98 C,  99 C, 100 C, 101 C, 102 C, 103 C, 104 C,
 105 C, 106 C, 107 C, 108 C, 109 C, 110 C, 111 C, 112 C,
 113 C, 114 C, 115 C, 116 C, 117 C, 118 C, 119 C, 120 C,
 121 C, 122 C,
  48 C,  49 C,  50 C,  51 C,  52 C,  53 C,  54 C,  55 C,
  56 C,  57 C,
  45 C,  95 C,

\ _B64-VAL ( char -- 6bit | -1 )
\   Reverse-map any Base64 char (standard or URL-safe) to 0-63.
: _B64-VAL  ( char -- n )
    DUP  65 >= OVER  90 <= AND IF  65 - EXIT THEN
    DUP  97 >= OVER 122 <= AND IF  71 - EXIT THEN
    DUP  48 >= OVER  57 <= AND IF   4 + EXIT THEN
    DUP  43 = IF DROP 62 EXIT THEN
    DUP  47 = IF DROP 63 EXIT THEN
    DUP  45 = IF DROP 62 EXIT THEN
    DUP  95 = IF DROP 63 EXIT THEN
    DROP -1 ;

\ =====================================================================
\  Length Calculations
\ =====================================================================

: B64-ENCODED-LEN  ( n -- m )  2 + 3 / 4 * ;
: B64-DECODED-LEN  ( n -- m )  4 / 3 * ;

\ =====================================================================
\  Encoding — shared state
\ =====================================================================

VARIABLE _BE-SRC
VARIABLE _BE-LEN
VARIABLE _BE-OUT
VARIABLE _BE-MAX
VARIABLE _BE-W
VARIABLE _BE-TBL    \ pointer to alphabet table
VARIABLE _BE-PAD    \ flag: add '=' padding?
VARIABLE _BE-B0
VARIABLE _BE-B1
VARIABLE _BE-B2

: _BE-EMIT  ( char -- )
    _BE-W @ _BE-MAX @ >= IF
        DROP B64-E-OVERFLOW B64-FAIL EXIT
    THEN
    _BE-OUT @ _BE-W @ + C!
    1 _BE-W +! ;

: _BE-LOOKUP  ( 6bit -- char )
    _BE-TBL @ + C@ ;

\ Encode one 3-byte group → 4 chars
: _BE-ENCODE3  ( -- )
    _BE-SRC @ C@     _BE-B0 !
    _BE-SRC @ 1 + C@ _BE-B1 !
    _BE-SRC @ 2 + C@ _BE-B2 !
    _BE-B0 @ 2 RSHIFT              _BE-LOOKUP _BE-EMIT
    _BE-B0 @ 3 AND 4 LSHIFT
    _BE-B1 @ 4 RSHIFT OR           _BE-LOOKUP _BE-EMIT
    _BE-B1 @ 15 AND 2 LSHIFT
    _BE-B2 @ 6 RSHIFT OR           _BE-LOOKUP _BE-EMIT
    _BE-B2 @ 63 AND                _BE-LOOKUP _BE-EMIT ;

\ Core encoder — _BE-TBL and _BE-PAD must be set first.
: _B64-ENCODE-CORE  ( src slen dst dmax -- written )
    B64-CLEAR-ERR
    _BE-MAX ! _BE-OUT ! 0 _BE-W !
    _BE-LEN ! _BE-SRC !
    \ Full 3-byte groups
    BEGIN _BE-LEN @ 3 >= WHILE
        _BE-ENCODE3
        3 _BE-SRC +!  -3 _BE-LEN +!
    REPEAT
    \ 2-byte remainder → 3 chars + optional pad
    _BE-LEN @ 2 = IF
        _BE-SRC @ C@     _BE-B0 !
        _BE-SRC @ 1 + C@ _BE-B1 !
        _BE-B0 @ 2 RSHIFT              _BE-LOOKUP _BE-EMIT
        _BE-B0 @ 3 AND 4 LSHIFT
        _BE-B1 @ 4 RSHIFT OR           _BE-LOOKUP _BE-EMIT
        _BE-B1 @ 15 AND 2 LSHIFT       _BE-LOOKUP _BE-EMIT
        _BE-PAD @ IF 61 _BE-EMIT THEN
    ELSE _BE-LEN @ 1 = IF
        \ 1-byte remainder → 2 chars + optional 2 pads
        _BE-SRC @ C@ _BE-B0 !
        _BE-B0 @ 2 RSHIFT              _BE-LOOKUP _BE-EMIT
        _BE-B0 @ 3 AND 4 LSHIFT        _BE-LOOKUP _BE-EMIT
        _BE-PAD @ IF 61 _BE-EMIT  61 _BE-EMIT THEN
    THEN THEN
    _BE-W @ ;

\ B64-ENCODE ( src slen dst dmax -- written )
\   Standard Base64 with '=' padding.
: B64-ENCODE  ( src slen dst dmax -- written )
    _B64-TABLE _BE-TBL !  -1 _BE-PAD !
    _B64-ENCODE-CORE ;

\ B64-ENCODE-URL ( src slen dst dmax -- written )
\   URL-safe Base64 (- _ instead of + /), no padding.
: B64-ENCODE-URL  ( src slen dst dmax -- written )
    _B64-TABLE-URL _BE-TBL !  0 _BE-PAD !
    _B64-ENCODE-CORE ;

\ =====================================================================
\  Decoding
\ =====================================================================

VARIABLE _BD-SRC
VARIABLE _BD-LEN
VARIABLE _BD-OUT
VARIABLE _BD-MAX
VARIABLE _BD-W
VARIABLE _BD-CNT    \ sextets accumulated (0-3)
VARIABLE _BD-ACC    \ 24-bit accumulator

: _BD-EMIT  ( byte -- )
    _BD-W @ _BD-MAX @ >= IF
        DROP B64-E-OVERFLOW B64-FAIL EXIT
    THEN
    _BD-OUT @ _BD-W @ + C!
    1 _BD-W +! ;

\ B64-DECODE ( src slen dst dmax -- written )
\   Decode standard or URL-safe Base64.  Skips whitespace and '='.
: B64-DECODE  ( src slen dst dmax -- written )
    B64-CLEAR-ERR
    _BD-MAX ! _BD-OUT ! 0 _BD-W !
    _BD-LEN ! _BD-SRC !
    0 _BD-CNT !  0 _BD-ACC !
    BEGIN
        _BD-LEN @ 0>
    WHILE
        _BD-SRC @ C@
        \ Skip whitespace
        DUP 32 = OVER 10 = OR OVER 13 = OR OVER 9 = OR IF
            DROP
        ELSE DUP 61 = IF
            \ Skip padding '='
            DROP
        ELSE
            _B64-VAL
            DUP -1 = IF
                DROP B64-E-INVALID B64-FAIL
                _BD-W @ EXIT
            THEN
            _BD-ACC @ 6 LSHIFT OR _BD-ACC !
            1 _BD-CNT +!
            _BD-CNT @ 4 = IF
                _BD-ACC @ 16 RSHIFT 255 AND _BD-EMIT
                _BD-ACC @  8 RSHIFT 255 AND _BD-EMIT
                _BD-ACC @            255 AND _BD-EMIT
                0 _BD-CNT !  0 _BD-ACC !
            THEN
        THEN THEN
        1 _BD-SRC +!  -1 _BD-LEN +!
    REPEAT
    \ Handle trailing sextets
    _BD-CNT @ 2 = IF
        _BD-ACC @ 4 RSHIFT 255 AND _BD-EMIT
    THEN
    _BD-CNT @ 3 = IF
        _BD-ACC @ 10 RSHIFT 255 AND _BD-EMIT
        _BD-ACC @  2 RSHIFT 255 AND _BD-EMIT
    THEN
    _BD-W @ ;

\ B64-DECODE-URL ( src slen dst dmax -- written )
\   URL-safe decode — same logic since _B64-VAL handles both alphabets.
: B64-DECODE-URL  ( src slen dst dmax -- written )
    B64-DECODE ;

\ ── Concurrency ──
\
\ All public words in this module are NOT reentrant.  They use shared
\ VARIABLE scratch space that would be corrupted by concurrent access.
\ Callers must ensure single-task access via WITH-GUARD, WITH-CRITICAL,
\ or by running with preemption disabled.
