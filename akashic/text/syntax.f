\ =================================================================
\  syntax.f — Syntax highlighting by meaning
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SYN- / _SYN-
\  Depends on: text-style.f, utils/string.f, utils/file-types.f
\
\  Line-by-line scanners that fill a style map (text-style.f): one
\  meaning per byte of the line, 0 for plain text.  The map says what
\  the text means, not how it looks; each display chooses the look.
\  Every scanner has the style-source shape the text area takes,
\  ( line-a line-u map -- ).  A line is scanned on its own, so a
\  construct never carries over to the next line.
\
\  Public API:
\    SYN-SCAN-FORTH  ( line-a line-u map -- )
\        Keywords, comments, strings, and numbers.
\    SYN-SCAN-MD     ( line-a line-u map -- )
\        Headings, `code`, **strong**, *emphasis*, and [links](target).
\    SYN-SCAN-PLAIN  ( line-a line-u map -- )   all plain
\    SYN-LANG-FORTH / SYN-LANG-MD / SYN-LANG-PLAIN  ( -- xt )
\    SYN-SCAN        ( line-a line-u map xt -- )   run a scanner
\    SYN-FOR-FILE    ( name-a name-u -- xt | 0 )
\        The scanner for a file by its name, or 0 for plain text.
\    SYN-MD-LINK-AT  ( line-a line-u pos -- target-a target-u found? )
\        The target of the Markdown link that covers byte POS.
\ =================================================================

PROVIDED akashic-syntax

REQUIRE text-style.f
REQUIRE ../utils/string.f
REQUIRE ../utils/file-types.f

\ _SYN-FILL ( map from to meaning -- )   map[from..to) := meaning
: _SYN-FILL  ( map from to meaning -- )
    >R
    2DUP < 0= IF 2DROP DROP R> DROP EXIT THEN
    OVER - >R + R> R> FILL ;

\ =====================================================================
\  S1 -- Forth keywords
\ =====================================================================
\  Counted strings, ended by a zero length.

: _SYN-KW,  ( addr u -- )
    DUP C,  0 ?DO DUP I + C@ C, LOOP DROP ;

CREATE _SF-KWDS
S" :"          _SYN-KW,   S" ;"          _SYN-KW,
S" IF"         _SYN-KW,   S" ELSE"       _SYN-KW,
S" THEN"       _SYN-KW,   S" BEGIN"      _SYN-KW,
S" WHILE"      _SYN-KW,   S" REPEAT"     _SYN-KW,
S" UNTIL"      _SYN-KW,   S" AGAIN"      _SYN-KW,
S" DO"         _SYN-KW,   S" ?DO"        _SYN-KW,
S" LOOP"       _SYN-KW,   S" +LOOP"      _SYN-KW,
S" LEAVE"      _SYN-KW,   S" UNLOOP"     _SYN-KW,
S" CASE"       _SYN-KW,   S" OF"         _SYN-KW,
S" ENDOF"      _SYN-KW,   S" ENDCASE"    _SYN-KW,
S" CREATE"     _SYN-KW,   S" DOES>"      _SYN-KW,
S" CONSTANT"   _SYN-KW,   S" VARIABLE"   _SYN-KW,
S" VALUE"      _SYN-KW,   S" TO"         _SYN-KW,
S" DEFER"      _SYN-KW,   S" IS"         _SYN-KW,
S" EXIT"       _SYN-KW,   S" RECURSE"    _SYN-KW,
S" IMMEDIATE"  _SYN-KW,   S" POSTPONE"   _SYN-KW,
S" [IF]"       _SYN-KW,   S" [ELSE]"     _SYN-KW,
S" [THEN]"     _SYN-KW,   S" ABORT"      _SYN-KW,
S" CATCH"      _SYN-KW,   S" THROW"      _SYN-KW,
S" REQUIRE"    _SYN-KW,   S" PROVIDED"   _SYN-KW,
S" ALLOT"      _SYN-KW,
0 C,

VARIABLE _KW-WA   VARIABLE _KW-WU

\ _SF-IS-KW? ( addr u -- flag )   A Forth keyword, in any case?
: _SF-IS-KW?  ( addr u -- flag )
    _KW-WU !  _KW-WA !
    _SF-KWDS
    BEGIN
        DUP C@ DUP WHILE                    ( ptr klen )
        \ Only a keyword of the word's length and first letter can match.
        DUP _KW-WU @ = IF
            OVER 1+ C@ _STR-LC _KW-WA @ C@ _STR-LC = IF
                OVER 1+ OVER _KW-WA @ _KW-WU @ STR-STRI= IF
                    2DROP -1 EXIT
                THEN
            THEN
        THEN
        + 1+
    REPEAT
    2DROP 0 ;

\ =====================================================================
\  S2 -- Forth scanner
\ =====================================================================

VARIABLE _SF-A       \ line
VARIABLE _SF-U
VARIABLE _SF-MAP
VARIABLE _SF-POS

: _SF-AT     ( -- byte )  _SF-A @ _SF-POS @ + C@ ;
: _SF-MORE?  ( -- flag )  _SF-POS @ _SF-U @ < ;
: _SF-WS?    ( byte -- flag )  DUP 32 = SWAP 9 = OR ;

\ _SF-NEXT-WS? ( -- flag )   Is the byte after the current one blank,
\   or is the current one the line's last?
: _SF-NEXT-WS?  ( -- flag )
    _SF-POS @ 1+ DUP _SF-U @ < 0= IF DROP -1 EXIT THEN
    _SF-A @ + C@ _SF-WS? ;

\ _SF-WORD-END ( -- end )   Where the word at _SF-POS ends.
: _SF-WORD-END  ( -- end )
    _SF-POS @
    BEGIN
        DUP _SF-U @ < IF DUP _SF-A @ + C@ _SF-WS? 0= ELSE 0 THEN
    WHILE 1+ REPEAT ;

: _SF-PAINT  ( from to meaning -- )  >R _SF-MAP @ -ROT R> _SYN-FILL ;

\ _SF-UNTIL ( byte meaning -- )
\   Paint from _SF-POS through the next BYTE, or to the line's end when
\   there is none, and move past it.
: _SF-UNTIL  ( byte meaning -- )
    >R _SF-POS @ SWAP                      ( start byte )
    BEGIN _SF-MORE? WHILE
        _SF-AT OVER = IF
            DROP 1 _SF-POS +!
            _SF-POS @ R> _SF-PAINT EXIT
        THEN
        1 _SF-POS +!
    REPEAT
    DROP _SF-U @ R> _SF-PAINT ;

\ _SF-DIGITS? ( addr u base -- flag )   Every byte a digit in BASE?
VARIABLE _SF-BASE
: _SF-DIGITS?  ( addr u base -- flag )
    _SF-BASE !
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER + SWAP ?DO
        I C@ _STR-LC
        DUP [CHAR] 0 [CHAR] 9 1+ WITHIN IF [CHAR] 0 -
        ELSE DUP [CHAR] a [CHAR] z 1+ WITHIN IF [CHAR] a - 10 +
        ELSE DROP 99 THEN THEN
        _SF-BASE @ < 0= IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

\ _SF-NUMBER? ( addr u -- flag )
\   Decimal digits, or hex after $ or 0x, or binary after %, with an
\   optional leading minus sign.
: _SF-NUMBER?  ( addr u -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ [CHAR] - = IF 1 /STRING THEN
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ [CHAR] $ = IF 1 /STRING 16 _SF-DIGITS? EXIT THEN
    OVER C@ [CHAR] % = IF 1 /STRING 2 _SF-DIGITS? EXIT THEN
    DUP 2 > IF
        OVER C@ [CHAR] 0 = IF
            OVER 1+ C@ _STR-LC [CHAR] x = IF 2 /STRING 16 _SF-DIGITS? EXIT THEN
        THEN
    THEN
    10 _SF-DIGITS? ;

\ _SF-WORD ( -- )   Classify the word at _SF-POS and move past it.
\   A word ending in a quote, such as S" or ." or ABORT", starts a string
\   that runs to the next quote.
: _SF-WORD  ( -- )
    _SF-POS @ _SF-WORD-END                 ( start end )
    DUP 1- _SF-A @ + C@ [CHAR] " = IF
        DUP _SF-POS !
        _SF-MORE? IF 1 _SF-POS +! THEN     \ the one blank after the word
        [CHAR] " TSTY-STRING _SF-UNTIL
        TSTY-STRING _SF-PAINT EXIT
    THEN
    DUP _SF-POS !
    2DUP OVER - SWAP _SF-A @ + SWAP        ( start end addr u )
    2DUP _SF-IS-KW? IF 2DROP TSTY-KEYWORD _SF-PAINT EXIT THEN
    _SF-NUMBER? IF TSTY-NUMBER _SF-PAINT EXIT THEN
    2DROP ;

\ SYN-SCAN-FORTH ( line-a line-u map -- )
: SYN-SCAN-FORTH  ( line-a line-u map -- )
    DUP _SF-MAP ! OVER 0 FILL
    _SF-U ! _SF-A ! 0 _SF-POS !
    BEGIN _SF-MORE? WHILE
        _SF-AT _SF-WS? IF
            1 _SF-POS +!
        ELSE _SF-AT [CHAR] \ = _SF-NEXT-WS? AND IF
            _SF-POS @ _SF-U @ TSTY-COMMENT _SF-PAINT
            _SF-U @ _SF-POS !
        ELSE _SF-AT [CHAR] ( = _SF-NEXT-WS? AND IF
            [CHAR] ) TSTY-COMMENT _SF-UNTIL
        ELSE
            _SF-WORD
        THEN THEN THEN
    REPEAT ;

\ =====================================================================
\  S3 -- Markdown scanner
\ =====================================================================

VARIABLE _SM-A   VARIABLE _SM-U   VARIABLE _SM-MAP   VARIABLE _SM-POS

: _SM-AT     ( i -- byte )  _SM-A @ + C@ ;
: _SM-IN?    ( i -- flag )  DUP 0< 0= SWAP _SM-U @ < AND ;
: _SM-BYTE   ( i -- byte | 0 )  DUP _SM-IN? IF _SM-AT ELSE DROP 0 THEN ;
: _SM-BLANK? ( i -- flag )  _SM-BYTE DUP 0= OVER 32 = OR SWAP 9 = OR ;
: _SM-ALNUM? ( i -- flag )
    _SM-BYTE _STR-LC
    DUP [CHAR] a [CHAR] z 1+ WITHIN SWAP [CHAR] 0 [CHAR] 9 1+ WITHIN OR ;

: _SM-PAINT  ( from to meaning -- )  >R _SM-MAP @ -ROT R> _SYN-FILL ;

\ _SM-FIND ( from byte -- i | -1 )   The next BYTE at or after FROM.
: _SM-FIND  ( from byte -- i | -1 )
    SWAP
    BEGIN DUP _SM-U @ < WHILE
        DUP _SM-AT 2 PICK = IF NIP EXIT THEN
        1+
    REPEAT
    2DROP -1 ;

\ _SM-HEADING? ( -- flag )   One to six # and then a blank or the end.
: _SM-HEADING?  ( -- flag )
    0
    BEGIN DUP _SM-BYTE [CHAR] # = WHILE 1+ REPEAT
    DUP 1 7 WITHIN 0= IF DROP 0 EXIT THEN
    _SM-BLANK? ;

\ _SM-CODE ( -- )   `code`: a backtick through the next one.
: _SM-CODE  ( -- )
    _SM-POS @ 1+ [CHAR] ` _SM-FIND DUP 0< IF
        DROP 1 _SM-POS +! EXIT
    THEN
    1+ _SM-POS @ OVER TSTY-CODE _SM-PAINT _SM-POS ! ;

\ _SM-CLOSE ( from marker n -- end | -1 )
\   Where a run of N MARKER bytes closes emphasis opened before FROM: the
\   next such run that follows a non-blank byte.  END is past the run.
VARIABLE _SMC-MARK   VARIABLE _SMC-N
: _SM-CLOSE  ( from marker n -- end | -1 )
    _SMC-N ! _SMC-MARK !
    BEGIN DUP _SM-U @ < WHILE
        DUP _SM-AT _SMC-MARK @ = IF
            _SMC-N @ 2 = IF DUP 1+ _SM-BYTE _SMC-MARK @ = ELSE -1 THEN
            OVER 1- _SM-BLANK? 0= AND IF
                _SMC-N @ + EXIT
            THEN
        THEN
        1+
    REPEAT
    DROP -1 ;

\ _SM-EMPHASIS ( -- )
\   **strong** or __strong__, *emphasis* or _emphasis_.  The text must
\   not start with a blank, and an underscore inside a word is a letter.
\   Markers that open nothing are plain and are passed over.
VARIABLE _SME-MARK   VARIABLE _SME-N   VARIABLE _SME-END
: _SM-EMPHASIS  ( -- )
    _SM-POS @ _SM-AT _SME-MARK !
    _SME-MARK @ [CHAR] _ = _SM-POS @ 1- _SM-ALNUM? AND IF
        1 _SM-POS +! EXIT
    THEN
    _SM-POS @ 1+ _SM-BYTE _SME-MARK @ = IF 2 ELSE 1 THEN _SME-N !
    _SM-POS @ _SME-N @ + _SM-BLANK? IF _SME-N @ _SM-POS +! EXIT THEN
    _SM-POS @ _SME-N @ + 1+ _SME-MARK @ _SME-N @ _SM-CLOSE
    DUP _SME-END ! 0< IF _SME-N @ _SM-POS +! EXIT THEN
    _SME-MARK @ [CHAR] _ = _SME-END @ _SM-ALNUM? AND IF
        _SME-N @ _SM-POS +! EXIT
    THEN
    _SM-POS @ _SME-END @
    _SME-N @ 2 = IF TSTY-STRONG ELSE TSTY-EMPHASIS THEN _SM-PAINT
    _SME-END @ _SM-POS ! ;

\ _SM-LINK-END ( from -- end | -1 )
\   With FROM on a [, the end of [text](target), past its ).
: _SM-LINK-END  ( from -- end | -1 )
    1+ [CHAR] ] _SM-FIND DUP 0< IF EXIT THEN
    1+ DUP _SM-BYTE [CHAR] ( <> IF DROP -1 EXIT THEN
    [CHAR] ) _SM-FIND DUP 0< IF EXIT THEN
    1+ ;

\ _SM-LINK ( -- )   [text](target), the whole of it.
: _SM-LINK  ( -- )
    _SM-POS @ _SM-LINK-END DUP 0< IF DROP 1 _SM-POS +! EXIT THEN
    _SM-POS @ OVER TSTY-LINK _SM-PAINT _SM-POS ! ;

: _SM-SETUP  ( line-a line-u map -- )
    DUP _SM-MAP ! OVER 0 FILL
    _SM-U ! _SM-A ! 0 _SM-POS ! ;

\ SYN-SCAN-MD ( line-a line-u map -- )
: SYN-SCAN-MD  ( line-a line-u map -- )
    _SM-SETUP
    _SM-U @ 0= IF EXIT THEN
    _SM-HEADING? IF 0 _SM-U @ TSTY-HEADING _SM-PAINT EXIT THEN
    BEGIN _SM-POS @ _SM-U @ < WHILE
        _SM-POS @ _SM-AT CASE
            [CHAR] ` OF _SM-CODE ENDOF
            [CHAR] * OF _SM-EMPHASIS ENDOF
            [CHAR] _ OF _SM-EMPHASIS ENDOF
            [CHAR] [ OF _SM-LINK ENDOF
            1 _SM-POS +!
        ENDCASE
    REPEAT ;

\ SYN-MD-LINK-AT ( line-a line-u pos -- target-a target-u found? )
\   The Markdown link whose [text](target) covers byte POS, found by the
\   same walk SYN-SCAN-MD makes, and its target: the bytes inside the
\   parentheses up to the first blank, so an optional title is left out.
VARIABLE _SML-POS
: SYN-MD-LINK-AT  ( line-a line-u pos -- target-a target-u found? )
    _SML-POS ! _SM-U ! _SM-A ! 0 _SM-POS !
    BEGIN _SM-POS @ _SM-U @ < WHILE
        _SM-POS @ _SM-AT [CHAR] [ = IF
            _SM-POS @ _SM-LINK-END DUP 0< 0= IF
                _SML-POS @ _SM-POS @ 2 PICK WITHIN IF   ( end )
                    1- _SM-POS @ [CHAR] ] _SM-FIND 2 +   ( close open )
                    TUCK -                               ( open u )
                    SWAP _SM-A @ + SWAP                  ( a u )
                    2DUP BL STR-INDEX DUP 0< 0= IF NIP ELSE DROP THEN
                    DUP 0<> EXIT
                THEN
                _SM-POS !
            ELSE
                DROP 1 _SM-POS +!
            THEN
        ELSE
            _SM-POS @ _SM-AT [CHAR] ` = IF
                _SM-POS @ 1+ [CHAR] ` _SM-FIND
                DUP 0< IF DROP 1 _SM-POS +! ELSE 1+ _SM-POS ! THEN
            ELSE
                1 _SM-POS +!
            THEN
        THEN
    REPEAT
    0 0 0 ;

\ =====================================================================
\  S4 -- Plain scanner and dispatch
\ =====================================================================

: SYN-SCAN-PLAIN  ( line-a line-u map -- )
    SWAP 0 FILL DROP ;

: SYN-SCAN  ( line-a line-u map xt -- )  EXECUTE ;

' SYN-SCAN-FORTH CONSTANT SYN-LANG-FORTH
' SYN-SCAN-MD    CONSTANT SYN-LANG-MD
' SYN-SCAN-PLAIN CONSTANT SYN-LANG-PLAIN

\ SYN-FOR-FILE ( name-a name-u -- xt | 0 )
\   A file's scanner by its name's type, or 0 when its text is plain, so
\   an editor can skip styling altogether.
: SYN-FOR-FILE  ( name-a name-u -- xt | 0 )
    FT-LOOKUP-LANG CASE
        FT-LANG-FORTH    OF SYN-LANG-FORTH ENDOF
        FT-LANG-MARKDOWN OF SYN-LANG-MD ENDOF
        0 SWAP
    ENDCASE ;

\ =====================================================================
\  S5 -- Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _syn-guard

' SYN-SCAN-FORTH CONSTANT _syn-sforth-xt
' SYN-SCAN-MD    CONSTANT _syn-smd-xt
' SYN-MD-LINK-AT CONSTANT _syn-mdlink-xt

: SYN-SCAN-FORTH  _syn-sforth-xt _syn-guard WITH-GUARD ;
: SYN-SCAN-MD     _syn-smd-xt   _syn-guard WITH-GUARD ;
: SYN-MD-LINK-AT  _syn-mdlink-xt _syn-guard WITH-GUARD ;
[THEN] [THEN]
