\ =================================================================
\  grapheme.f — characters (extended grapheme clusters) and widths
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: GR- / _GR-
\  Depends on: utf8.f, unicode-props.f
\
\  A character is one extended grapheme cluster (UAX #29, Unicode
\  15.1.0, rules GB1 to GB999 including GB9c), as the shared text
\  contract (docs/rich-terminal/APT-1-TEXT.md Section 3) requires.
\  Its width follows Section 4 of that contract, and ill-formed UTF-8,
\  Cc, Zl, and Zp scalars are read as U+FFFD (Section 5).
\
\  Segmenter (one scalar at a time, caller-owned state):
\    GR-STATE-SIZE   ( -- n )
\    GR-RESET        ( state -- )           start of text
\    GR-BREAK?       ( props state -- flag ) boundary before this scalar?
\
\  Cursor (walks a UTF-8 buffer one character at a time):
\    GR-CURSOR-SIZE  ( -- n )
\    GR-CURSOR-INIT  ( addr u flags cursor -- )
\    GR-NEXT         ( cursor -- flag )      read the next character
\    GR-C-ADDR GR-C-BYTES GR-C-SCALARS GR-C-WIDTH GR-C-CP0 GR-C-PROPS0
\                    ( cursor -- x )        fields of the last character
\    GR-F-TAB        keep U+0009 as itself instead of U+FFFD
\
\  Whole strings (ASCII fast path, then the cursor):
\    GR-SWIDTH       ( addr u -- width )     display width in cells
\    GR-COUNT        ( addr u -- n )         number of characters
\    GR-NEXT-BOUNDARY ( addr u off -- off' ) next boundary after off
\    GR-PREV-BOUNDARY ( addr u off -- off' ) last boundary before off
\
\  The ordinary string words use one module cursor and are guarded in
\  GUARDED builds; *-WITH variants take a caller cursor and are
\  reentrant.
\ =================================================================

PROVIDED akashic-grapheme

REQUIRE utf8.f
REQUIRE unicode-props.f

\ =====================================================================
\  §1 — Segmenter state
\ =====================================================================

 0 CONSTANT _GR-S-PACKED      \ see below
 8 CONSTANT _GR-S-CUR         \ scratch: GCB of the scalar being judged
16 CONSTANT GR-STATE-SIZE

\ The packed cell holds everything GB1 to GB13 need from earlier
\ scalars:
\   bits 0-3  previous GCB; 15 at start of text
\   bits 4-5  GB11 state: 0, 1 ExtPict Extend*, 2 ExtPict Extend* ZWJ
\   bits 6-7  GB9c state: 0, 1 Consonant [Extend|Linker]*, 2 ... Linker
\   bits 8-   regional indicators in a row
\ It is zero exactly when the previous scalar was an ordinary character
\ (GCB Other, not Extended_Pictographic, no InCB value) with nothing
\ pending, which lets the common case skip the rules.
15 CONSTANT _GR-START
0x7F CONSTANT _GR-PLAIN-MASK   \ GCB, ExtPict, and InCB bits of props

: GR-RESET  ( state -- )
    _GR-START SWAP _GR-S-PACKED + ! ;

: _GR-S-PREV@   ( state -- gcb )   _GR-S-PACKED + @ 15 AND ;
: _GR-S-EMOJI@  ( state -- n )     _GR-S-PACKED + @ 4 RSHIFT 3 AND ;
: _GR-S-INCB@   ( state -- n )     _GR-S-PACKED + @ 6 RSHIFT 3 AND ;
: _GR-S-RI@     ( state -- n )     _GR-S-PACKED + @ 8 RSHIFT ;

\ _GR-PAIR-ACTION ( prev cur -- action )
\   The stateless part of GB3 to GB13 for one pair of GCB values:
\   0 break, 1 no break, 2 break unless GB9c or GB11 holds, 3 break
\   unless GB12/GB13 holds.  GB9c and GB11 can only join an Other after
\   an Extend or ZWJ, and GB12/GB13 only two regional indicators; the
\   table generator checks that every InCB consonant and every
\   Extended_Pictographic scalar has GCB Other.
: _GR-PAIR-ACTION  ( prev cur -- action )
    OVER UP-GCB-CR = OVER UP-GCB-LF = AND IF 2DROP 1 EXIT THEN   \ GB3
    OVER UP-GCB-CR UP-GCB-CONTROL 1+ WITHIN IF 2DROP 0 EXIT THEN \ GB4
    DUP UP-GCB-CR UP-GCB-CONTROL 1+ WITHIN IF 2DROP 0 EXIT THEN  \ GB5
    OVER UP-GCB-L = IF                                           \ GB6
        DUP UP-GCB-L = OVER UP-GCB-V = OR
        OVER UP-GCB-LV = OR OVER UP-GCB-LVT = OR IF 2DROP 1 EXIT THEN
    THEN
    OVER DUP UP-GCB-LV = SWAP UP-GCB-V = OR IF                   \ GB7
        DUP DUP UP-GCB-V = SWAP UP-GCB-T = OR IF 2DROP 1 EXIT THEN
    THEN
    OVER DUP UP-GCB-LVT = SWAP UP-GCB-T = OR IF                  \ GB8
        DUP UP-GCB-T = IF 2DROP 1 EXIT THEN
    THEN
    DUP UP-GCB-EXTEND = OVER UP-GCB-ZWJ = OR                     \ GB9
    OVER UP-GCB-SPACINGMARK = OR IF 2DROP 1 EXIT THEN            \ GB9a
    OVER UP-GCB-PREPEND = IF 2DROP 1 EXIT THEN                   \ GB9b
    OVER DUP UP-GCB-EXTEND = SWAP UP-GCB-ZWJ = OR
    OVER UP-GCB-OTHER = AND IF 2DROP 2 EXIT THEN                 \ GB9c, GB11
    UP-GCB-RI = SWAP UP-GCB-RI = AND IF 3 ELSE 0 THEN ;          \ GB12, GB13

CREATE _GR-PAIRS 256 ALLOT

: _GR-BUILD-PAIRS  ( -- )
    _GR-PAIRS 256 0 FILL
    14 0 DO
        14 0 DO
            J I _GR-PAIR-ACTION  J 16 * I + _GR-PAIRS + C!
        LOOP
    LOOP ;
_GR-BUILD-PAIRS

\ _GR-RULE-BREAK? ( props state -- flag )
\   GB1 to GB999 for the boundary between the previous scalar and this
\   one.  Reads the state; changes only the scratch field.
: _GR-RULE-BREAK?  ( props state -- flag )
    >R
    DUP UP-GCB DUP R@ _GR-S-CUR + !          ( props cur )
    R@ _GR-S-PREV@                           ( props cur prev )
    DUP _GR-START = IF 2DROP DROP R> DROP -1 EXIT THEN   \ GB1
    16 * + _GR-PAIRS + C@                    ( props action )
    CASE
        0 OF DROP -1 ENDOF
        1 OF DROP 0 ENDOF
        2 OF                                             \ GB9c, GB11
            DUP UP-INCB UP-INCB-CONSONANT =
            R@ _GR-S-INCB@ 2 = AND
            SWAP UP-EXTPICT? R@ _GR-S-EMOJI@ 2 = AND OR 0=
        ENDOF
        3 OF DROP R@ _GR-S-RI@ 1 AND 0= ENDOF            \ GB12, GB13
        >R DROP -1 R>
    ENDCASE
    R> DROP ;

\ _GR-ADVANCE ( props state -- )
\   Move the state past the scalar whose GCB is in the scratch field.
: _GR-ADVANCE  ( props state -- )
    >R
    R@ _GR-S-CUR + @ UP-GCB-RI = IF R@ _GR-S-RI@ 1+ ELSE 0 THEN
    8 LSHIFT                                 ( props packed )
    OVER UP-EXTPICT? IF
        1
    ELSE R@ _GR-S-EMOJI@ 1 = IF
        R@ _GR-S-CUR + @ DUP UP-GCB-EXTEND = IF DROP 1 ELSE
            UP-GCB-ZWJ = IF 2 ELSE 0 THEN
        THEN
    ELSE 0 THEN THEN
    4 LSHIFT OR                              ( props packed )
    SWAP UP-INCB DUP UP-INCB-CONSONANT = IF
        DROP 1
    ELSE R@ _GR-S-INCB@ IF
        DUP UP-INCB-LINKER = IF DROP 2 ELSE
            UP-INCB-EXTEND = IF R@ _GR-S-INCB@ ELSE 0 THEN
        THEN
    ELSE DROP 0 THEN THEN
    6 LSHIFT OR
    R@ _GR-S-CUR + @ OR R> _GR-S-PACKED + ! ;

\ GR-BREAK? ( props state -- flag )
\   True when a character boundary comes before the scalar with PROPS.
\   The state then moves past that scalar.  An ordinary character after
\   an ordinary character always breaks and leaves the state as it was.
: GR-BREAK?  ( props state -- flag )
    DUP _GR-S-PACKED + @ 0= IF
        OVER _GR-PLAIN-MASK AND 0= IF 2DROP -1 EXIT THEN
    THEN
    2DUP _GR-RULE-BREAK? >R _GR-ADVANCE R> ;

\ =====================================================================
\  §2 — Cursor
\ =====================================================================

 0 CONSTANT _GR-C-A          \ address of the lookahead scalar
 8 CONSTANT _GR-C-U          \ bytes left, counting the lookahead
16 CONSTANT _GR-C-LA-CP      \ lookahead scalar after replacement, -1 none
24 CONSTANT _GR-C-LA-PROPS
32 CONSTANT _GR-C-LA-BYTES
40 CONSTANT _GR-C-FLAGS
48 CONSTANT _GR-C-ADDR       \ fields of the last character read
56 CONSTANT _GR-C-BYTES
64 CONSTANT _GR-C-SCALARS
72 CONSTANT _GR-C-WIDTH
80 CONSTANT _GR-C-CP0
88 CONSTANT _GR-C-PROPS0
96 CONSTANT _GR-C-CP1
104 CONSTANT _GR-C-PROPS1
112 CONSTANT _GR-C-IGNORABLE \ every scalar so far is default-ignorable
120 CONSTANT _GR-C-TARGET    \ scratch: byte offset for boundary searches
128 CONSTANT _GR-C-SEG        \ segmenter state
_GR-C-SEG GR-STATE-SIZE + CONSTANT _GR-C-DEC       \ UTF-8 decoder state
_GR-C-DEC UTF8-DECODE-STATE-SIZE + CONSTANT GR-CURSOR-SIZE

1 CONSTANT GR-F-TAB

: GR-C-ADDR     ( cursor -- a )     _GR-C-ADDR + @ ;
: GR-C-BYTES    ( cursor -- u )     _GR-C-BYTES + @ ;
: GR-C-SCALARS  ( cursor -- n )     _GR-C-SCALARS + @ ;
: GR-C-WIDTH    ( cursor -- w )     _GR-C-WIDTH + @ ;
: GR-C-CP0      ( cursor -- cp )    _GR-C-CP0 + @ ;
: GR-C-PROPS0   ( cursor -- props ) _GR-C-PROPS0 + @ ;
: GR-C-CP1      ( cursor -- cp|-1 ) _GR-C-CP1 + @ ;

\ GR-DISPLAY-CP ( cp props flags -- cp' props' )
\   Section 5 replacement: Cc, Zl, and Zp read as U+FFFD, except a tab
\   when GR-F-TAB is set.  Ill-formed UTF-8 already decoded as U+FFFD.
: GR-DISPLAY-CP  ( cp props flags -- cp' props' )
    OVER UP-INVALID? 0= IF DROP EXIT THEN
    GR-F-TAB AND IF OVER 9 = IF EXIT THEN THEN
    2DROP 0xFFFD DUP UP-PROPS ;

\ _GR-FAST-DECODE ( addr u -- cp bytes true | false )
\   Decode a well-formed two-byte sequence, or a three-byte sequence
\   outside the surrogate block, in place.  Anything else, including
\   every ill-formed input, is left to UTF8-DECODE-WITH.
: _GR-FAST-DECODE  ( addr u -- cp bytes true | false )
    OVER C@                                   ( addr u b0 )
    DUP 0xC2 0xE0 WITHIN IF
        OVER 2 < IF 2DROP DROP 0 EXIT THEN
        2 PICK 1+ C@ DUP 0xC0 AND 0x80 <> IF 2DROP 2DROP 0 EXIT THEN
        0x3F AND SWAP 0x1F AND 6 LSHIFT OR NIP NIP 2 -1 EXIT
    THEN
    DUP 0xE1 0xF0 WITHIN OVER 0xED <> AND IF
        OVER 3 < IF 2DROP DROP 0 EXIT THEN
        2 PICK 1+ C@ DUP 0xC0 AND 0x80 <> IF 2DROP 2DROP 0 EXIT THEN
        3 PICK 2 + C@ DUP 0xC0 AND 0x80 <> IF 2DROP 2DROP DROP 0 EXIT THEN
        0x3F AND SWAP 0x3F AND 6 LSHIFT OR SWAP 0x0F AND 12 LSHIFT OR
        NIP NIP 3 -1 EXIT
    THEN
    2DROP DROP 0 ;

\ GR-DECODE ( addr u flags state -- cp props bytes )
\   Decode the scalar at ADDR (U > 0 bytes remain) as displayed text:
\   ill-formed input reads as U+FFFD one maximal subpart at a time, and
\   Section 5 replaces Cc, Zl, and Zp unless FLAGS keeps a tab.  STATE is
\   UTF8-DECODE-STATE-SIZE bytes of caller storage.
: GR-DECODE  ( addr u flags state -- cp props bytes )
    SWAP >R >R                                ( addr u  R: flags state )
    OVER C@ 0x80 < IF
        DROP C@ 1
    ELSE 2DUP _GR-FAST-DECODE IF
        2SWAP 2DROP
    ELSE
        TUCK R@ UTF8-DECODE-WITH NIP ROT SWAP -
    THEN THEN                                 ( cp bytes )
    R> DROP
    SWAP DUP UP-PROPS R> GR-DISPLAY-CP ROT ;

\ _GR-DECODE-LA ( cursor -- )
\   Decode the next scalar into the lookahead fields.  The lookahead
\   scalar is -1 at the end of the buffer.
: _GR-DECODE-LA  ( cursor -- )
    >R
    R@ _GR-C-U + @ 0= IF -1 R> _GR-C-LA-CP + ! EXIT THEN
    R@ _GR-C-A + @ R@ _GR-C-U + @ R@ _GR-C-FLAGS + @ R@ _GR-C-DEC +
    GR-DECODE
    R@ _GR-C-LA-BYTES + !
    R@ _GR-C-LA-PROPS + !
    R> _GR-C-LA-CP + ! ;

\ Consume the lookahead into the current character.
: _GR-TAKE-LA  ( cursor -- )
    >R
    R@ _GR-C-LA-BYTES + @ DUP R@ _GR-C-BYTES + +!
    DUP R@ _GR-C-A + +!
    NEGATE R@ _GR-C-U + +!
    R@ _GR-C-SCALARS + @ 1 = IF
        R@ _GR-C-LA-CP + @ R@ _GR-C-CP1 + !
        R@ _GR-C-LA-PROPS + @ R@ _GR-C-PROPS1 + !
    THEN
    1 R@ _GR-C-SCALARS + +!
    R@ _GR-C-LA-PROPS + @ UP-IGNORABLE? 0= IF
        0 R@ _GR-C-IGNORABLE + !
    THEN
    R> DROP ;

\ GR-CURSOR-INIT ( addr u flags cursor -- )
: GR-CURSOR-INIT  ( addr u flags cursor -- )
    >R
    R@ _GR-C-FLAGS + !
    R@ _GR-C-U + !
    R@ _GR-C-A + !
    R@ _GR-C-SEG + GR-RESET
    0 R@ _GR-C-BYTES + !
    0 R@ _GR-C-SCALARS + !
    R@ _GR-C-A + @ R@ _GR-C-ADDR + !
    R@ _GR-DECODE-LA
    R@ _GR-C-LA-CP + @ 0< 0= IF
        R@ _GR-C-LA-PROPS + @ R@ _GR-C-SEG + GR-BREAK? DROP
    THEN
    R> DROP ;

\ GR-CHAR-WIDTH ( props0 cp1 props1 count ignorable? -- w )
\   APT-1-TEXT Section 4, W(c), from the properties of a character's first
\   scalar, its second scalar and that scalar's properties (any values
\   when COUNT is 1), its scalar count, and whether every scalar is
\   default-ignorable.
: GR-CHAR-WIDTH  ( props0 cp1 props1 count ignorable? -- w )
    IF DROP 2DROP DROP 0 EXIT THEN            ( props0 cp1 props1 count )
    1 > IF                                    ( props0 cp1 props1 )
        2 PICK UP-GCB UP-GCB-RI =
        OVER UP-GCB UP-GCB-RI = AND IF 2DROP DROP 2 EXIT THEN
        2 PICK UP-EMOJI? IF
            UP-EMOJI-MODIFIER? SWAP 0xFE0F = OR IF DROP 2 EXIT THEN
            UP-WIDTH ?DUP 0= IF 1 THEN EXIT
        THEN
    THEN
    2DROP UP-WIDTH ?DUP 0= IF 1 THEN ;

: _GR-CHAR-WIDTH  ( cursor -- w )
    >R R@ _GR-C-PROPS0 + @ R@ _GR-C-CP1 + @ R@ _GR-C-PROPS1 + @
    R@ _GR-C-SCALARS + @ R> _GR-C-IGNORABLE + @ GR-CHAR-WIDTH ;

\ GR-NEXT ( cursor -- flag )
\   Read one character; false at the end of the buffer.
: GR-NEXT  ( cursor -- flag )
    >R
    R@ _GR-C-LA-CP + @ 0< IF R> DROP 0 EXIT THEN
    R@ _GR-C-A + @ R@ _GR-C-ADDR + !
    0 R@ _GR-C-BYTES + !
    0 R@ _GR-C-SCALARS + !
    -1 R@ _GR-C-CP1 + !
    0 R@ _GR-C-PROPS1 + !
    -1 R@ _GR-C-IGNORABLE + !
    R@ _GR-C-LA-CP + @ R@ _GR-C-CP0 + !
    R@ _GR-C-LA-PROPS + @ R@ _GR-C-PROPS0 + !
    R@ _GR-TAKE-LA
    BEGIN
        R@ _GR-DECODE-LA
        R@ _GR-C-LA-CP + @ 0< IF
            0
        ELSE
            R@ _GR-C-LA-PROPS + @ R@ _GR-C-SEG + GR-BREAK? 0=
        THEN
    WHILE
        R@ _GR-TAKE-LA
    REPEAT
    R@ _GR-CHAR-WIDTH R@ _GR-C-WIDTH + !
    R> DROP -1 ;

\ =====================================================================
\  §3 — Whole strings
\ =====================================================================

\ _GR-PRINTABLE-ASCII? ( addr u -- flag )
\   Every byte U+0020..U+007E: each byte is one character of width 1.
: _GR-PRINTABLE-ASCII?  ( addr u -- flag )
    BEGIN DUP 0> WHILE
        OVER C@ 32 127 WITHIN 0= IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT 2DROP -1 ;

: GR-SWIDTH-WITH  ( addr u cursor -- width )
    >R
    2DUP _GR-PRINTABLE-ASCII? IF NIP R> DROP EXIT THEN
    0 R@ GR-CURSOR-INIT
    0 BEGIN R@ GR-NEXT WHILE R@ GR-C-WIDTH + REPEAT
    R> DROP ;

: GR-COUNT-WITH  ( addr u cursor -- n )
    >R
    2DUP _GR-PRINTABLE-ASCII? IF NIP R> DROP EXIT THEN
    0 R@ GR-CURSOR-INIT
    0 BEGIN R@ GR-NEXT WHILE 1+ REPEAT
    R> DROP ;

\ GR-NEXT-BOUNDARY-WITH ( addr u off cursor -- off' )
\   The first character boundary after byte offset OFF, or U when OFF is
\   at or past the end.  An offset inside a character moves to its end.
\   Tabs count as themselves, as they do in an edited line.
: GR-NEXT-BOUNDARY-WITH  ( addr u off cursor -- off' )
    >R
    DUP 2 PICK >= IF DROP NIP R> DROP EXIT THEN   ( addr u off )
    0 MAX R@ _GR-C-TARGET + !
    OVER -ROT GR-F-TAB R@ GR-CURSOR-INIT          ( addr )
    BEGIN R@ GR-NEXT WHILE
        R@ GR-C-ADDR R@ GR-C-BYTES + OVER -       ( addr end-off )
        DUP R@ _GR-C-TARGET + @ > IF NIP R> DROP EXIT THEN
        DROP
    REPEAT
    DROP R> _GR-C-TARGET + @ ;

\ GR-PREV-BOUNDARY-WITH ( addr u off cursor -- off' )
\   The last character boundary before byte offset OFF, or 0.
: GR-PREV-BOUNDARY-WITH  ( addr u off cursor -- off' )
    >R
    DUP 0> 0= IF DROP 2DROP R> DROP 0 EXIT THEN   ( addr u off )
    OVER MIN R@ _GR-C-TARGET + !
    OVER -ROT GR-F-TAB R@ GR-CURSOR-INIT          ( addr )
    0 SWAP                                        ( last addr )
    BEGIN R@ GR-NEXT WHILE
        R@ GR-C-ADDR OVER -                       ( last addr start-off )
        DUP R@ _GR-C-TARGET + @ < IF
            ROT DROP SWAP
        ELSE
            2DROP R> DROP EXIT
        THEN
    REPEAT
    DROP R> DROP ;

CREATE _GR-CURSOR GR-CURSOR-SIZE ALLOT

: GR-SWIDTH  ( addr u -- width )  _GR-CURSOR GR-SWIDTH-WITH ;
: GR-COUNT   ( addr u -- n )      _GR-CURSOR GR-COUNT-WITH ;
: GR-NEXT-BOUNDARY  ( addr u off -- off' )
    _GR-CURSOR GR-NEXT-BOUNDARY-WITH ;
: GR-PREV-BOUNDARY  ( addr u off -- off' )
    _GR-CURSOR GR-PREV-BOUNDARY-WITH ;

\ =====================================================================
\  §4 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _gr-guard

' GR-SWIDTH        CONSTANT _gr-swidth-xt
' GR-COUNT         CONSTANT _gr-count-xt
' GR-NEXT-BOUNDARY CONSTANT _gr-next-boundary-xt
' GR-PREV-BOUNDARY CONSTANT _gr-prev-boundary-xt

: GR-SWIDTH        _gr-swidth-xt _gr-guard WITH-GUARD ;
: GR-COUNT         _gr-count-xt _gr-guard WITH-GUARD ;
: GR-NEXT-BOUNDARY _gr-next-boundary-xt _gr-guard WITH-GUARD ;
: GR-PREV-BOUNDARY _gr-prev-boundary-xt _gr-guard WITH-GUARD ;
[THEN] [THEN]
