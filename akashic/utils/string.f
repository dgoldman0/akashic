\ string.f — Shared string utilities for KDOS / Megapad-64
\
\ Eliminates duplicate case-insensitive comparison code from
\ css.f (_CSS-STRI=), markup/core.f (_MU-STRI=), and
\ headers.f (_CI-PREFIX).  All libraries REQUIRE string.f.
\
\ Same (addr len) model as the rest of Akashic.
\
\ Prefix: STR-   (public API)
\         _STR-  (internal helpers)
\
\ Load with:   REQUIRE string.f

PROVIDED akashic-string

\ =====================================================================
\  /STRING (may already exist — safe to redefine)
\ =====================================================================

: /STRING  ( addr len n -- addr+n len-n )
    ROT OVER + -ROT - ;

\ =====================================================================
\  Character Case (internal)
\ =====================================================================

: _STR-LC  ( c -- c' )
    DUP 65 >= OVER 90 <= AND IF 32 + THEN ;

: _STR-UC  ( c -- c' )
    DUP 97 >= OVER 122 <= AND IF 32 - THEN ;

\ =====================================================================
\  String Case Conversion (in-place)
\ =====================================================================

: STR-TOLOWER  ( addr len -- )
    0 ?DO
        DUP I + DUP C@ _STR-LC SWAP C!
    LOOP DROP ;

: STR-TOUPPER  ( addr len -- )
    0 ?DO
        DUP I + DUP C@ _STR-UC SWAP C!
    LOOP DROP ;

\ =====================================================================
\  String Comparison
\ =====================================================================

\ STR-STR= ( s1 l1 s2 l2 -- flag )
\   Case-sensitive string comparison. -1 = equal, 0 = not equal.
: STR-STR=  ( s1 l1 s2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 DO
        OVER I + C@  OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ STR-STRI= ( s1 l1 s2 l2 -- flag )
\   Case-insensitive string comparison. -1 = equal, 0 = not equal.
: STR-STRI=  ( s1 l1 s2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 DO
        OVER I + C@ _STR-LC
        OVER I + C@ _STR-LC
        <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ =====================================================================
\  Prefix / Suffix Matching
\ =====================================================================

\ STR-STARTS? ( str-a str-u pfx-a pfx-u -- flag )
\   Case-sensitive prefix match.
VARIABLE _SS-SA
VARIABLE _SS-SL
VARIABLE _SS-PA
VARIABLE _SS-PL

: STR-STARTS?  ( str-a str-u pfx-a pfx-u -- flag )
    _SS-PL ! _SS-PA ! _SS-SL ! _SS-SA !
    _SS-PL @ _SS-SL @ > IF 0 EXIT THEN
    _SS-PL @ 0= IF -1 EXIT THEN
    _SS-PL @ 0 DO
        _SS-SA @ I + C@  _SS-PA @ I + C@ <> IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

\ STR-STARTSI? ( str-a str-u pfx-a pfx-u -- flag )
\   Case-insensitive prefix match.
: STR-STARTSI?  ( str-a str-u pfx-a pfx-u -- flag )
    _SS-PL ! _SS-PA ! _SS-SL ! _SS-SA !
    _SS-PL @ _SS-SL @ > IF 0 EXIT THEN
    _SS-PL @ 0= IF -1 EXIT THEN
    _SS-PL @ 0 DO
        _SS-SA @ I + C@  _STR-LC
        _SS-PA @ I + C@  _STR-LC
        <> IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

\ STR-ENDS? ( str-a str-u sfx-a sfx-u -- flag )
\   Case-sensitive suffix match.
VARIABLE _SE-SA
VARIABLE _SE-SL
VARIABLE _SE-XA
VARIABLE _SE-XL

: STR-ENDS?  ( str-a str-u sfx-a sfx-u -- flag )
    _SE-XL ! _SE-XA ! _SE-SL ! _SE-SA !
    _SE-XL @ _SE-SL @ > IF 0 EXIT THEN
    _SE-XL @ 0= IF -1 EXIT THEN
    _SE-SL @ _SE-XL @ - \ offset into str where suffix should start
    _SE-XL @ 0 DO
        _SE-SA @ OVER I + + C@
        _SE-XA @ I + C@ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ =====================================================================
\  Searching
\ =====================================================================

\ STR-INDEX ( str-a str-u c -- idx | -1 )
\   First occurrence of char c in string.  -1 if not found.
VARIABLE _SI-SA
VARIABLE _SI-SL
VARIABLE _SI-CH

: STR-INDEX  ( str-a str-u c -- idx | -1 )
    _SI-CH ! _SI-SL ! _SI-SA !
    _SI-SL @ 0= IF -1 EXIT THEN
    _SI-SL @ 0 DO
        _SI-SA @ I + C@ _SI-CH @ = IF
            I UNLOOP EXIT
        THEN
    LOOP
    -1 ;

\ STR-RINDEX ( str-a str-u c -- idx | -1 )
\   Last occurrence of char c in string.  -1 if not found.
VARIABLE _SR-SA
VARIABLE _SR-SL
VARIABLE _SR-CH

: STR-RINDEX  ( str-a str-u c -- idx | -1 )
    _SR-CH ! _SR-SL ! _SR-SA !
    _SR-SL @ 0= IF -1 EXIT THEN
    _SR-SL @ 0 DO
        _SR-SA @ _SR-SL @ 1- I - + C@ _SR-CH @ = IF
            _SR-SL @ 1- I - UNLOOP EXIT
        THEN
    LOOP
    -1 ;

\ STR-STR-CONTAINS ( hay-a hay-u ndl-a ndl-u -- flag )
\   Does the haystack contain the needle as a substring?
\   Case-sensitive.  flag = -1 if found, 0 if not found.
VARIABLE _SSC-HA   VARIABLE _SSC-HL
VARIABLE _SSC-NA   VARIABLE _SSC-NL

: STR-STR-CONTAINS  ( hay-a hay-u ndl-a ndl-u -- flag )
    _SSC-NL !  _SSC-NA !  _SSC-HL !  _SSC-HA !
    _SSC-NL @ 0= IF -1 EXIT THEN            \ empty needle always matches
    _SSC-NL @ _SSC-HL @ > IF 0 EXIT THEN    \ needle longer than haystack
    _SSC-HL @ _SSC-NL @ - 1+  0 DO
        -1  _SSC-NL @ 0 DO
            _SSC-HA @ J + I + C@
            _SSC-NA @ I + C@
            <> IF DROP 0 LEAVE THEN
        LOOP
        IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

\ STR-STRI-CONTAINS ( hay-a hay-u ndl-a ndl-u -- flag )
\   Case-insensitive substring search.
VARIABLE _SIC-HA   VARIABLE _SIC-HL
VARIABLE _SIC-NA   VARIABLE _SIC-NL

: STR-STRI-CONTAINS  ( hay-a hay-u ndl-a ndl-u -- flag )
    _SIC-NL !  _SIC-NA !  _SIC-HL !  _SIC-HA !
    _SIC-NL @ 0= IF -1 EXIT THEN
    _SIC-NL @ _SIC-HL @ > IF 0 EXIT THEN
    _SIC-HL @ _SIC-NL @ - 1+  0 DO
        -1  _SIC-NL @ 0 DO
            _SIC-HA @ J + I + C@  _STR-LC
            _SIC-NA @ I + C@      _STR-LC
            <> IF DROP 0 LEAVE THEN
        LOOP
        IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

\ STR-SPLIT ( str-a str-u c -- pre-a pre-u post-a post-u flag )
\   Split at first occurrence of delimiter char c.
\   flag = -1 if found, 0 if not found (post = 0 0).
VARIABLE _SP-SA
VARIABLE _SP-SL
VARIABLE _SP-IDX

: STR-SPLIT  ( str-a str-u c -- pre-a pre-u post-a post-u flag )
    >R _SP-SL ! _SP-SA !
    _SP-SA @ _SP-SL @ R> STR-INDEX  _SP-IDX !
    _SP-IDX @ 0< IF
        _SP-SA @ _SP-SL @  0 0  0 EXIT
    THEN
    _SP-SA @  _SP-IDX @
    _SP-SA @ _SP-IDX @ + 1+
    _SP-SL @ _SP-IDX @ - 1-
    -1 ;

\ =====================================================================
\  Trimming
\ =====================================================================

\ _STR-WS? ( c -- flag )  whitespace: space, tab, CR, LF
: _STR-WS?  ( c -- flag )
    DUP 32 = OVER 9 = OR OVER 13 = OR SWAP 10 = OR ;

\ STR-TRIM-L ( addr len -- addr' len' )
: STR-TRIM-L  ( addr len -- addr' len' )
    BEGIN
        DUP 0> IF OVER C@ _STR-WS? ELSE 0 THEN
    WHILE
        1 /STRING
    REPEAT ;

\ STR-TRIM-R ( addr len -- addr' len' )
: STR-TRIM-R  ( addr len -- addr' len' )
    BEGIN
        DUP 0> IF OVER OVER + 1- C@ _STR-WS? ELSE 0 THEN
    WHILE
        1-
    REPEAT ;

\ STR-TRIM ( addr len -- addr' len' )
: STR-TRIM  ( addr len -- addr' len' )
    STR-TRIM-L STR-TRIM-R ;

\ =====================================================================
\  Number Conversion
\ =====================================================================

\ NUM>STR ( n -- addr len )
\   Signed decimal number to string.
\   Uses static buffer — NOT re-entrant.
CREATE _N2S-BUF 24 ALLOT
VARIABLE _N2S-POS

: NUM>STR  ( n -- addr len )
    DUP 0= IF DROP _N2S-BUF 48 OVER C! 1 EXIT THEN
    DUP 0< IF
        NEGATE
        23 _N2S-POS !
        BEGIN
            DUP 0>
        WHILE
            DUP 10 MOD 48 +
            _N2S-BUF _N2S-POS @ + C!
            -1 _N2S-POS +!
            10 /
        REPEAT
        DROP
        _N2S-BUF _N2S-POS @ + 45 OVER C!  \ '-' sign
        23 _N2S-POS @ - 1+
    ELSE
        23 _N2S-POS !
        BEGIN
            DUP 0>
        WHILE
            DUP 10 MOD 48 +
            _N2S-BUF _N2S-POS @ + C!
            -1 _N2S-POS +!
            10 /
        REPEAT
        DROP
        _N2S-BUF _N2S-POS @ + 1+
        23 _N2S-POS @ - 
    THEN ;

\ STR>NUM ( addr len -- n flag )
\   Parse signed decimal string.  flag = -1 success, 0 failure.
VARIABLE _S2N-PTR
VARIABLE _S2N-END
VARIABLE _S2N-ACC
VARIABLE _S2N-NEG

: STR>NUM  ( addr len -- n flag )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    OVER + _S2N-END !  _S2N-PTR !
    0 _S2N-ACC !  0 _S2N-NEG !
    \ Check leading '-'
    _S2N-PTR @ C@ 45 = IF
        -1 _S2N-NEG !
        1 _S2N-PTR +!
        _S2N-PTR @ _S2N-END @ >= IF 0 0 EXIT THEN
    THEN
    \ Check leading '+'
    _S2N-PTR @ C@ 43 = IF
        1 _S2N-PTR +!
        _S2N-PTR @ _S2N-END @ >= IF 0 0 EXIT THEN
    THEN
    \ Must have at least one digit
    _S2N-PTR @ C@ DUP 48 < SWAP 57 > OR IF 0 0 EXIT THEN
    BEGIN
        _S2N-PTR @ _S2N-END @ <
    WHILE
        _S2N-PTR @ C@ DUP 48 >= OVER 57 <= AND IF
            48 -
            _S2N-ACC @ 10 * + _S2N-ACC !
            1 _S2N-PTR +!
        ELSE
            DROP 0 0 EXIT
        THEN
    REPEAT
    _S2N-NEG @ IF _S2N-ACC @ NEGATE ELSE _S2N-ACC @ THEN
    -1 ;

\ =====================================================================
\  Buffer Tokenizer
\ =====================================================================
\
\ Parse whitespace-delimited tokens from an arbitrary (addr len) buffer
\ rather than from the BIOS input stream (TIB).
\
\   STR-SKIP-BL   ( addr len -- addr' len' )
\     Advance past leading spaces/tabs/newlines.
\
\   STR-PARSE-TOKEN ( addr len -- tok tlen rest rlen )
\     Extract next whitespace-delimited token from buffer.
\     tok/tlen = the token.  rest/rlen = remaining buffer after token.
\     If buffer is empty (or all whitespace), tlen = 0.

: _STR-IS-BL  ( addr len -- addr len flag )
    DUP 0> IF
        OVER C@ DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR
    ELSE
        0
    THEN ;

: _STR-NOT-BL  ( addr len -- addr len flag )
    DUP 0> IF
        OVER C@ DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR 0=
    ELSE
        0
    THEN ;

: STR-SKIP-BL  ( addr len -- addr' len' )
    BEGIN _STR-IS-BL WHILE 1 /STRING REPEAT ;

: STR-PARSE-TOKEN  ( addr len -- tok tlen rest rlen )
    STR-SKIP-BL
    DUP 0= IF EXIT THEN        \ empty → tok=addr, tlen=0, rest=addr, rlen=0
    2DUP                        ( addr len addr0 len0 )
    BEGIN _STR-NOT-BL WHILE 1 /STRING REPEAT
    \ Stack: ( addr len addr' len' ) — addr'=past token, len'=remaining
    2SWAP                       ( addr' len' addr len )
    DROP                        ( addr' len' addr )
    2 PICK OVER -               ( addr' len' addr tlen )
    2SWAP ;                     ( tok tlen rest rlen )

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ustr-guard

' STR-TOLOWER     CONSTANT _str-tolower-xt
' STR-TOUPPER     CONSTANT _str-toupper-xt
' STR-STR=        CONSTANT _str-str=-xt
' STR-STRI=       CONSTANT _str-stri=-xt
' STR-STARTS?     CONSTANT _str-starts-q-xt
' STR-STARTSI?    CONSTANT _str-startsi-q-xt
' STR-ENDS?       CONSTANT _str-ends-q-xt
' STR-INDEX       CONSTANT _str-index-xt
' STR-RINDEX      CONSTANT _str-rindex-xt
' STR-STR-CONTAINS CONSTANT _str-str-contains-xt
' STR-STRI-CONTAINS CONSTANT _str-stri-contains-xt
' STR-SPLIT       CONSTANT _str-split-xt
' STR-TRIM-L      CONSTANT _str-trim-l-xt
' STR-TRIM-R      CONSTANT _str-trim-r-xt
' STR-TRIM        CONSTANT _str-trim-xt
' NUM>STR         CONSTANT _num-to-str-xt
' STR>NUM         CONSTANT _str-to-num-xt
' STR-SKIP-BL     CONSTANT _str-skip-bl-xt
' STR-PARSE-TOKEN CONSTANT _str-parse-token-xt

: STR-TOLOWER     _str-tolower-xt _ustr-guard WITH-GUARD ;
: STR-TOUPPER     _str-toupper-xt _ustr-guard WITH-GUARD ;
: STR-STR=        _str-str=-xt _ustr-guard WITH-GUARD ;
: STR-STRI=       _str-stri=-xt _ustr-guard WITH-GUARD ;
: STR-STARTS?     _str-starts-q-xt _ustr-guard WITH-GUARD ;
: STR-STARTSI?    _str-startsi-q-xt _ustr-guard WITH-GUARD ;
: STR-ENDS?       _str-ends-q-xt _ustr-guard WITH-GUARD ;
: STR-INDEX       _str-index-xt _ustr-guard WITH-GUARD ;
: STR-RINDEX      _str-rindex-xt _ustr-guard WITH-GUARD ;
: STR-STR-CONTAINS _str-str-contains-xt _ustr-guard WITH-GUARD ;
: STR-STRI-CONTAINS _str-stri-contains-xt _ustr-guard WITH-GUARD ;
: STR-SPLIT       _str-split-xt _ustr-guard WITH-GUARD ;
: STR-TRIM-L      _str-trim-l-xt _ustr-guard WITH-GUARD ;
: STR-TRIM-R      _str-trim-r-xt _ustr-guard WITH-GUARD ;
: STR-TRIM        _str-trim-xt _ustr-guard WITH-GUARD ;
: NUM>STR         _num-to-str-xt _ustr-guard WITH-GUARD ;
: STR>NUM         _str-to-num-xt _ustr-guard WITH-GUARD ;
: STR-SKIP-BL     _str-skip-bl-xt _ustr-guard WITH-GUARD ;
: STR-PARSE-TOKEN _str-parse-token-xt _ustr-guard WITH-GUARD ;
[THEN] [THEN]
