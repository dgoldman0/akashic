\ =================================================================
\  syntax.f — Syntax Highlighting for Text Editors
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SYN- / _SYN-
\  Depends on: utils/string.f
\
\  Line-by-line scanner that fills a byte-indexed token-type map.
\  The editor's renderer reads the map to apply colors.
\
\  The colormap stores one byte per source-byte position, holding
\  a SYN-T-* token type.  The editor maps token types to colors
\  via the palette (SYN-PAL-FG, SYN-PAL-BG, SYN-PAL-ATTRS).
\
\  Built-in scanners for Forth, Markdown, and plain text.
\
\  Public API:
\    SYN-T-*        Token-type constants (0–8)
\    SYN-SCAN       ( addr u map lang-xt -- )
\    SYN-LANG-FORTH ( -- xt )
\    SYN-LANG-MD    ( -- xt )
\    SYN-LANG-PLAIN ( -- xt )
\    SYN-PAL-SET    ( type fg bg attrs -- )
\    SYN-PAL-FG     ( type -- fg )
\    SYN-PAL-BG     ( type -- bg )
\    SYN-PAL-ATTRS  ( type -- attrs )
\ =================================================================

PROVIDED akashic-syntax

REQUIRE ../utils/string.f

\ =====================================================================
\  S1 -- Token Types
\ =====================================================================

0 CONSTANT SYN-T-DEFAULT
1 CONSTANT SYN-T-KEYWORD
2 CONSTANT SYN-T-COMMENT
3 CONSTANT SYN-T-STRING
4 CONSTANT SYN-T-NUMBER
5 CONSTANT SYN-T-HEADING
6 CONSTANT SYN-T-BOLD
7 CONSTANT SYN-T-LINK
8 CONSTANT SYN-T-CODE
9 CONSTANT _SYN-T-MAX

\ =====================================================================
\  S2 -- Default Palette
\ =====================================================================
\  Each entry packs fg(8) | bg(8)<<8 | attrs(8)<<16 in one cell.

CREATE SYN-PALETTE  _SYN-T-MAX CELLS ALLOT

: SYN-PAL-SET  ( type fg bg attrs -- )
    16 LSHIFT  SWAP 8 LSHIFT OR  OR
    SYN-PALETTE ROT CELLS +  ! ;

: SYN-PAL-FG    ( type -- fg )    CELLS SYN-PALETTE + @ 0xFF AND ;
: SYN-PAL-BG    ( type -- bg )    CELLS SYN-PALETTE + @ 8 RSHIFT 0xFF AND ;
: SYN-PAL-ATTRS ( type -- attrs ) CELLS SYN-PALETTE + @ 16 RSHIFT 0xFF AND ;

\ --- Load defaults (ANSI 16-color) ---
\  type             fg  bg  attrs
SYN-T-DEFAULT  7   0   0   SYN-PAL-SET   \ white on black
SYN-T-KEYWORD  14  0   1   SYN-PAL-SET   \ bright cyan, bold
SYN-T-COMMENT  8   0   0   SYN-PAL-SET   \ dark gray
SYN-T-STRING   3   0   0   SYN-PAL-SET   \ yellow
SYN-T-NUMBER   6   0   0   SYN-PAL-SET   \ cyan
SYN-T-HEADING  13  0   1   SYN-PAL-SET   \ bright magenta, bold
SYN-T-BOLD     15  0   1   SYN-PAL-SET   \ bright white, bold
SYN-T-LINK     12  0   0   SYN-PAL-SET   \ bright blue
SYN-T-CODE     2   0   0   SYN-PAL-SET   \ green

\ =====================================================================
\  S3 -- Internal Utilities  (uses _STR-LC / STR-STRI= from string.f)
\ =====================================================================

\ _SYN-FILL ( map from to type -- )
\   Fill map[from..to-1] with token type.
: _SYN-FILL  ( map from to type -- )
    >R                               ( map from to  R: type )
    SWAP ?DO
        R@ OVER I + C!
    LOOP
    DROP R> DROP ;

\ =====================================================================
\  S4 -- Forth Keyword Table
\ =====================================================================
\  Stored as counted strings: length-byte, characters, repeated.
\  Terminated by a 0 length byte.

CREATE _SF-KWDS
  1 C, CHAR : C,
  1 C, CHAR ; C,
  2 C, CHAR I C, CHAR F C,
  4 C, CHAR E C, CHAR L C, CHAR S C, CHAR E C,
  4 C, CHAR T C, CHAR H C, CHAR E C, CHAR N C,
  5 C, CHAR B C, CHAR E C, CHAR G C, CHAR I C, CHAR N C,
  5 C, CHAR W C, CHAR H C, CHAR I C, CHAR L C, CHAR E C,
  6 C, CHAR R C, CHAR E C, CHAR P C, CHAR E C, CHAR A C, CHAR T C,
  5 C, CHAR U C, CHAR N C, CHAR T C, CHAR I C, CHAR L C,
  5 C, CHAR A C, CHAR G C, CHAR A C, CHAR I C, CHAR N C,
  2 C, CHAR D C, CHAR O C,
  3 C, CHAR ? C, CHAR D C, CHAR O C,
  4 C, CHAR L C, CHAR O C, CHAR O C, CHAR P C,
  5 C, CHAR + C, CHAR L C, CHAR O C, CHAR O C, CHAR P C,
  5 C, CHAR L C, CHAR E C, CHAR A C, CHAR V C, CHAR E C,
  6 C, CHAR U C, CHAR N C, CHAR L C, CHAR O C, CHAR O C, CHAR P C,
  4 C, CHAR C C, CHAR A C, CHAR S C, CHAR E C,
  2 C, CHAR O C, CHAR F C,
  5 C, CHAR E C, CHAR N C, CHAR D C, CHAR O C, CHAR F C,
  7 C, CHAR E C, CHAR N C, CHAR D C, CHAR C C, CHAR A C, CHAR S C, CHAR E C,
  6 C, CHAR C C, CHAR R C, CHAR E C, CHAR A C, CHAR T C, CHAR E C,
  5 C, CHAR D C, CHAR O C, CHAR E C, CHAR S C, CHAR > C,
  8 C, CHAR C C, CHAR O C, CHAR N C, CHAR S C, CHAR T C, CHAR A C, CHAR N C, CHAR T C,
  8 C, CHAR V C, CHAR A C, CHAR R C, CHAR I C, CHAR A C, CHAR B C, CHAR L C, CHAR E C,
  5 C, CHAR V C, CHAR A C, CHAR L C, CHAR U C, CHAR E C,
  2 C, CHAR T C, CHAR O C,
  4 C, CHAR E C, CHAR X C, CHAR I C, CHAR T C,
  5 C, CHAR A C, CHAR B C, CHAR O C, CHAR R C, CHAR T C,
  7 C, CHAR R C, CHAR E C, CHAR Q C, CHAR U C, CHAR I C, CHAR R C, CHAR E C,
  8 C, CHAR P C, CHAR R C, CHAR O C, CHAR V C, CHAR I C, CHAR D C, CHAR E C, CHAR D C,
  5 C, CHAR A C, CHAR L C, CHAR L C, CHAR O C, CHAR T C,
  0 C,    \ terminator

VARIABLE _KW-WA   VARIABLE _KW-WU

\ _SF-IS-KW? ( addr u -- flag )
\   Check whether the word matches any Forth keyword.
: _SF-IS-KW?  ( addr u -- flag )
    _KW-WU !  _KW-WA !
    _SF-KWDS
    BEGIN
        DUP C@ DUP WHILE                    ( ptr klen )
        OVER 1+  OVER                        ( ptr klen kaddr klen )
        _KW-WA @  _KW-WU @                  ( ptr klen kaddr klen wa wu )
        2SWAP  STR-STRI= IF
            2DROP -1 EXIT
        THEN
        1+ +                                   ( ptr' = ptr + klen + 1 )
    REPEAT
    DROP DROP 0 ;

\ =====================================================================
\  S5 -- Forth Scanner
\ =====================================================================

VARIABLE _SF-A       \ line addr
VARIABLE _SF-U       \ line length
VARIABLE _SF-MAP     \ colormap addr
VARIABLE _SF-POS     \ current position

: _SF-AT  ( -- byte )  _SF-A @ _SF-POS @ + C@ ;
: _SF-MORE? ( -- flag ) _SF-POS @ _SF-U @ < ;

: _SF-IS-DIGIT ( b -- flag )
    DUP [CHAR] 0 >=  SWAP [CHAR] 9 <=  AND ;

: _SF-IS-WS ( b -- flag )
    DUP 32 = SWAP 9 = OR ;

\ _SF-WORD-BOUNDS ( -- start end )
\   Find the current word's start (= _SF-POS) and end position.
: _SF-WORD-BOUNDS  ( -- start end )
    _SF-POS @
    BEGIN
        DUP _SF-U @ < WHILE
        _SF-A @ OVER + C@ _SF-IS-WS 0= WHILE
        1+
    REPEAT THEN
    _SF-POS @ SWAP ;

\ _SF-PAINT ( start end type -- )
: _SF-PAINT  ( start end type -- )
    >R SWAP ?DO
        R@ _SF-MAP @ I + C!
    LOOP R> DROP ;

\ _SF-SCAN-LINE-COMMENT ( -- )
\   Paint from _SF-POS to end as comment.
: _SF-SCAN-LINE-COMMENT  ( -- )
    _SF-POS @  _SF-U @  SYN-T-COMMENT  _SF-PAINT
    _SF-U @ _SF-POS ! ;

\ _SF-SCAN-PAREN-COMMENT ( -- )
\   Paint `( ... )` as comment.  Advances _SF-POS past `)`.
: _SF-SCAN-PAREN-COMMENT  ( -- )
    _SF-POS @ >R                             \ save start
    BEGIN _SF-MORE? WHILE
        _SF-AT [CHAR] ) = IF
            1 _SF-POS +!                     \ skip )
            R> _SF-POS @  SYN-T-COMMENT  _SF-PAINT
            EXIT
        THEN
        1 _SF-POS +!
    REPEAT
    \ Unclosed — paint to end
    R> _SF-U @  SYN-T-COMMENT  _SF-PAINT ;

\ _SF-SCAN-STRING ( -- )
\   Paint a Forth string literal up to the closing `"`.
\   Assumes _SF-POS is on the `"` that starts the body.
: _SF-SCAN-STRING  ( -- )
    _SF-POS @ >R                             \ save start
    1 _SF-POS +!                             \ skip opening "
    BEGIN _SF-MORE? WHILE
        _SF-AT [CHAR] " = IF
            1 _SF-POS +!                     \ skip closing "
            R> _SF-POS @  SYN-T-STRING  _SF-PAINT
            EXIT
        THEN
        1 _SF-POS +!
    REPEAT
    R> _SF-U @  SYN-T-STRING  _SF-PAINT ;

\ _SF-IS-NUMBER ( addr u -- flag )
\   Simple check: all digits, or starts with 0x/$ (hex prefix).
: _SF-IS-NUMBER  ( addr u -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ [CHAR] - = IF 1 /STRING THEN    \ skip leading -
    DUP 0= IF 2DROP 0 EXIT THEN
    \ Check hex prefix
    OVER C@ [CHAR] $ = IF 2DROP -1 EXIT THEN
    DUP 2 >= IF
        OVER C@ [CHAR] 0 =
        OVER 1 + C@ _STR-LC [CHAR] x = AND IF
            2DROP -1 EXIT
        THEN
    THEN
    \ All digits?
    0 ?DO
        DUP I + C@ _SF-IS-DIGIT 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ SYN-SCAN-FORTH ( addr u map -- )
\   Forth syntax scanner.
: SYN-SCAN-FORTH  ( addr u map -- )
    _SF-MAP !  _SF-U !  _SF-A !
    0 _SF-POS !
    \ Fill with default
    _SF-MAP @  0  _SF-U @  SYN-T-DEFAULT  _SF-PAINT
    BEGIN _SF-MORE? WHILE
        \ Skip whitespace
        _SF-AT _SF-IS-WS IF 1 _SF-POS +! ELSE
        \ Line comment: `\` followed by space or at EOL
        _SF-AT [CHAR] \ = IF
            _SF-POS @ 1+ _SF-U @ >= IF
                _SF-SCAN-LINE-COMMENT
            ELSE
                _SF-A @ _SF-POS @ + 1+ C@ _SF-IS-WS IF
                    _SF-SCAN-LINE-COMMENT
                ELSE
                    \ Just a backslash word — treat as normal word
                    _SF-WORD-BOUNDS                ( start end )
                    SYN-T-DEFAULT _SF-PAINT
                    _SF-WORD-BOUNDS NIP _SF-POS !
                THEN
            THEN
        ELSE
        \ Paren comment: `(` followed by space
        _SF-AT [CHAR] ( = IF
            _SF-POS @ 1+ _SF-U @ < IF
                _SF-A @ _SF-POS @ + 1+ C@ _SF-IS-WS IF
                    _SF-SCAN-PAREN-COMMENT
                ELSE
                    _SF-WORD-BOUNDS 2DROP
                    _SF-WORD-BOUNDS NIP _SF-POS !
                THEN
            ELSE
                1 _SF-POS +!
            THEN
        ELSE
        \ String literals: ." S" C" ABORT"
        \ Detect: word ending in " followed by space, then string body
        _SF-WORD-BOUNDS                      ( start end )
        2DUP  1- _SF-A @ + C@ [CHAR] " =
        2 PICK 2 PICK < AND IF
            \ Word ends with " → treat next region as string
            2DUP SYN-T-STRING _SF-PAINT
            NIP _SF-POS !                    \ advance past the word
            \ Now scan string body
            _SF-MORE? IF _SF-SCAN-STRING THEN
        ELSE
            \ Regular word — check keyword / number
            OVER  _SF-A @ +                  ( start end word-addr )
            SWAP OVER -                      ( start word-addr word-len )
            2DUP _SF-IS-KW? IF
                2DROP
                SYN-T-KEYWORD _SF-PAINT
                _SF-WORD-BOUNDS NIP _SF-POS !
            ELSE
            2DUP _SF-IS-NUMBER IF
                2DROP
                SYN-T-NUMBER _SF-PAINT
                _SF-WORD-BOUNDS NIP _SF-POS !
            ELSE
                2DROP
                2DROP
                _SF-WORD-BOUNDS NIP _SF-POS !
            THEN THEN
        THEN
        THEN THEN THEN
    REPEAT ;

\ =====================================================================
\  S6 -- Markdown Scanner
\ =====================================================================

VARIABLE _SM-A   VARIABLE _SM-U   VARIABLE _SM-MAP   VARIABLE _SM-POS

: _SM-AT   ( -- byte ) _SM-A @ _SM-POS @ + C@ ;
: _SM-MORE? ( -- flag ) _SM-POS @ _SM-U @ < ;
: _SM-LEFT  ( -- n )    _SM-U @ _SM-POS @ - ;

: SYN-SCAN-MD  ( addr u map -- )
    _SM-MAP !  _SM-U !  _SM-A !
    0 _SM-POS !
    _SM-MAP @  0  _SM-U @  SYN-T-DEFAULT  _SF-PAINT
    _SM-U @ 0= IF EXIT THEN
    \ --- Headings: line starts with `#` ---
    _SM-A @ C@ [CHAR] # = IF
        _SM-MAP @  0  _SM-U @  SYN-T-HEADING  _SF-PAINT
        EXIT
    THEN
    \ --- Inline patterns ---
    BEGIN _SM-MORE? WHILE
        \ Backtick: inline code
        _SM-AT [CHAR] ` = IF
            _SM-POS @ >R  1 _SM-POS +!
            BEGIN _SM-MORE? WHILE
                _SM-AT [CHAR] ` = IF
                    1 _SM-POS +!
                    _SM-MAP @  R> _SM-POS @  SYN-T-CODE  _SF-PAINT
                    0     \ sentinel: matched
                ELSE
                    1 _SM-POS +!  -1
                THEN
            0= UNTIL
            ELSE R> DROP THEN
        ELSE
        \ Bold: **...**
        _SM-AT [CHAR] * =  _SM-LEFT 2 >=  AND IF
            _SM-A @ _SM-POS @ + 1+ C@ [CHAR] * = IF
                _SM-POS @ >R  2 _SM-POS +!
                BEGIN _SM-MORE? WHILE
                    _SM-AT [CHAR] * =  _SM-LEFT 2 >=  AND IF
                        _SM-A @ _SM-POS @ + 1+ C@ [CHAR] * = IF
                            2 _SM-POS +!
                            _SM-MAP @  R> _SM-POS @  SYN-T-BOLD  _SF-PAINT
                            0
                        ELSE
                            1 _SM-POS +!  -1
                        THEN
                    ELSE
                        1 _SM-POS +!  -1
                    THEN
                0= UNTIL
                ELSE R> DROP THEN
            ELSE
                1 _SM-POS +!
            THEN
        ELSE
        \ Link: [text](url)
        _SM-AT [CHAR] [ = IF
            _SM-POS @ >R  1 _SM-POS +!
            BEGIN _SM-MORE? WHILE
                _SM-AT [CHAR] ] = IF
                    _SM-POS @ 1+  _SM-U @ < IF
                        _SM-A @ _SM-POS @ + 1+ C@ [CHAR] ( = IF
                            \ Found ]( — scan to )
                            2 _SM-POS +!
                            BEGIN _SM-MORE? WHILE
                                _SM-AT [CHAR] ) = IF
                                    1 _SM-POS +!
                                    _SM-MAP @  R> _SM-POS @
                                    SYN-T-LINK  _SF-PAINT
                                    0
                                ELSE
                                    1 _SM-POS +! -1
                                THEN
                            0= UNTIL
                            ELSE R> DROP THEN
                            0     \ exit outer loop
                        ELSE
                            R> DROP  0
                        THEN
                    ELSE
                        R> DROP  0
                    THEN
                ELSE
                    1 _SM-POS +!  -1
                THEN
            0= UNTIL
            ELSE R> DROP THEN
        ELSE
            1 _SM-POS +!
        THEN THEN THEN
    REPEAT ;

\ =====================================================================
\  S7 -- Plain Scanner (no highlighting)
\ =====================================================================

: SYN-SCAN-PLAIN  ( addr u map -- )
    ROT DROP                          ( u map )
    0 ROT SYN-T-DEFAULT  _SF-PAINT ;

\ =====================================================================
\  S8 -- Dispatch
\ =====================================================================

\ SYN-SCAN ( addr u map lang-xt -- )
\   Scan a line using the given language scanner.
: SYN-SCAN  ( addr u map lang-xt -- )
    EXECUTE ;

\ Language selectors (return scanner xt)
' SYN-SCAN-FORTH CONSTANT SYN-LANG-FORTH
' SYN-SCAN-MD    CONSTANT SYN-LANG-MD
' SYN-SCAN-PLAIN CONSTANT SYN-LANG-PLAIN

\ =====================================================================
\  S9 -- Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _syn-guard

' SYN-SCAN-FORTH CONSTANT _syn-sforth-xt
' SYN-SCAN-MD    CONSTANT _syn-smd-xt

: SYN-SCAN-FORTH  _syn-sforth-xt _syn-guard WITH-GUARD ;
: SYN-SCAN-MD     _syn-smd-xt   _syn-guard WITH-GUARD ;
[THEN] [THEN]
