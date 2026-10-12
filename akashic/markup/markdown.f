\ =====================================================================
\  markup/markdown.f — Markdown read as a document
\ =====================================================================
\
\  A reader for media/document.f.  It follows CommonMark 0.30: block
\  quotes, bullet and numbered lists, ATX and setext headings, thematic
\  breaks, fenced and indented code, HTML blocks, link reference
\  definitions and paragraphs, and within them emphasis, strong emphasis,
\  code spans, links, pictures, autolinks, raw HTML, hard and soft line
\  breaks, backslash escapes and entities.  The algorithm is the one the
\  CommonMark reference parser, commonmark.js, uses.  Where commonmark.js
\  reads less than the specification's text allows and markdown-it follows
\  the text, as for tabs around a link destination or after a closing
\  fence, the reader follows the text.  GitHub tables are found as
\  markdown-it finds them.
\
\  A document shows text, not HTML.  Raw HTML shows as its text; an HTML
\  block and a GitHub table show as their lines, unbroken, as code does.
\  Whitespace between words shows as one space, as a browser shows it.
\  A character takes one meaning: a link's, else code's, else strong's,
\  else emphasis's.  A picture within text shows its description as a
\  link to the picture; a paragraph that is only a picture is a figure,
\  whose caption is the description.
\
\  The structure pass reads the source once, a line at a time, and keeps
\  each block's kind, its quotes and list items, and the source spans of
\  its lines; the link reference definitions are kept for the whole
\  document.  A block's text is read again from its spans when a view
\  asks for it.  Memory comes from the document's memory source; when it
\  refuses, the pass ends with DOC-S-MEMORY.
\
\  Reference labels match regardless of ASCII case; other letters must
\  match exactly.
\
\  Prefix: MD- (public), _MD- (private)
\
\  Public API:
\    MD-READER  ( -- reader )   the reader record DOC-OPEN takes
\ =====================================================================

REQUIRE ../media/document.f
REQUIRE ../text/unicode-props.f
REQUIRE ../text/text-style.f
REQUIRE html-entities.f

PROVIDED akashic-markdown

\ Failures thrown inside a pass and caught at its top.
-4101 CONSTANT _MD-E-MEMORY
-4102 CONSTANT _MD-E-READ

\ =====================================================================
\  Memory
\ =====================================================================

VARIABLE _MD-D          \ the document
VARIABLE _MD-S          \ its reader state

: _MD-ALLOC  ( bytes -- a )
    _MD-D @ DOC-MSRC@ MSRC-ALLOC DUP 0= IF _MD-E-MEMORY THROW THEN ;
: _MD-FREE   ( a bytes -- )
    OVER 0= IF 2DROP EXIT THEN _MD-D @ DOC-MSRC@ MSRC-FREE ;

\ A buffer: where it is, the bytes it can hold, and the bytes in use.
: _MB.A    ( b -- a )        ;
: _MB.CAP  ( b -- a )    8 + ;
: _MB.N    ( b -- a )   16 + ;
24 CONSTANT _MB-SIZE

VARIABLE _MGW-B
VARIABLE _MGW-NEW

\ _MD-GROW ( need b -- )
\   Make buffer B hold at least NEED bytes, keeping those in use.  It at
\   least doubles, so filling a buffer costs constant time a byte.
: _MD-GROW  ( need b -- )
    _MGW-B !
    DUP _MGW-B @ _MB.CAP @ U> 0= IF DROP EXIT THEN
    _MGW-B @ _MB.CAP @ 2* MAX 256 MAX
    DUP _MD-ALLOC _MGW-NEW !
    _MGW-B @ _MB.A @ ?DUP IF
        DUP _MGW-NEW @ _MGW-B @ _MB.N @ MOVE
        _MGW-B @ _MB.CAP @ _MD-FREE
    THEN
    _MGW-NEW @ _MGW-B @ _MB.A !
    _MGW-B @ _MB.CAP ! ;

\ _MD-ROOM ( bytes b -- a )  Take BYTES more of buffer B; where they are.
: _MD-ROOM  ( bytes b -- a )
    >R DUP R@ _MB.N @ + R@ _MD-GROW
    R@ _MB.A @ R@ _MB.N @ + SWAP R> _MB.N +! ;

: _MD-PUT   ( a u b -- )  OVER SWAP _MD-ROOM SWAP MOVE ;
: _MD-PUTC  ( c b -- )    1 SWAP _MD-ROOM C! ;

: _MD-RELEASE  ( b -- )
    DUP _MB.A @ OVER _MB.CAP @ _MD-FREE _MB-SIZE 0 FILL ;

\ The reader's state, kept with the document while it is open.  LINES,
\ STRS and REFS last as long as the document; the content pass keeps its
\ buffers for the next block; the structure pass's go when it ends.
: _MD-LINES     ( -- b )  _MD-S @ ;
: _MD-STRS      ( -- b )  _MD-S @  24 + ;
: _MD-REFS      ( -- b )  _MD-S @  48 + ;
: _MD-REGION    ( -- b )  _MD-S @  72 + ;
: _MD-SUBJ      ( -- b )  _MD-S @  96 + ;
: _MD-ITEMS     ( -- b )  _MD-S @ 120 + ;
: _MD-POOL      ( -- b )  _MD-S @ 144 + ;
: _MD-DELIMS    ( -- b )  _MD-S @ 168 + ;
: _MD-BRACKETS  ( -- b )  _MD-S @ 192 + ;
: _MD-LINKS     ( -- b )  _MD-S @ 216 + ;
: _MD-OTEXT     ( -- b )  _MD-S @ 240 + ;
: _MD-OMAP      ( -- b )  _MD-S @ 264 + ;
: _MD-ORANGES   ( -- b )  _MD-S @ 288 + ;
: _MD-NODES     ( -- b )  _MD-S @ 312 + ;
: _MD-LBUF      ( -- b )  _MD-S @ 336 + ;
: _MD-CHUNK     ( -- b )  _MD-S @ 360 + ;
: _MD-PARA      ( -- b )  _MD-S @ 384 + ;
: _MD-CHAIN     ( -- b )  _MD-S @ 408 + ;
432 CONSTANT _MDS-SIZE

: _MD-FREE-STRUCTURE  ( -- )
    _MD-NODES _MD-RELEASE _MD-LBUF _MD-RELEASE _MD-CHUNK _MD-RELEASE
    _MD-PARA _MD-RELEASE _MD-CHAIN _MD-RELEASE ;

: _MD-FREE-ALL  ( -- )
    _MD-S @ 0= IF EXIT THEN
    _MDS-SIZE 0 DO _MD-S @ I + _MD-RELEASE _MB-SIZE +LOOP
    _MD-S @ _MDS-SIZE _MD-FREE 0 _MD-S ! ;

\ =====================================================================
\  Characters
\ =====================================================================

: _MD-SPACE-OR-TAB?  ( c -- flag )  DUP 32 = SWAP 9 = OR ;
\ Space, tab, line feed, line tabulation, form feed, carriage return.
: _MD-WS?      ( c -- flag )  DUP 32 = SWAP 9 14 WITHIN OR ;
: _MD-DIGIT?   ( c -- flag )  48 58 WITHIN ;
: _MD-ALPHA?   ( c -- flag )  DUP 65 91 WITHIN SWAP 97 123 WITHIN OR ;
: _MD-ALNUM?   ( c -- flag )  DUP _MD-ALPHA? SWAP _MD-DIGIT? OR ;
: _MD-HEX?     ( c -- flag )
    DUP _MD-DIGIT? OVER 65 71 WITHIN OR SWAP 97 103 WITHIN OR ;
: _MD-LOWER    ( c -- c' )  DUP 65 91 WITHIN IF 32 + THEN ;
: _MD-UPPER    ( c -- c' )  DUP 97 123 WITHIN IF 32 - THEN ;

: _MD-ASCII-PUNCT?  ( c -- flag )
    DUP 33 48 WITHIN OVER 58 65 WITHIN OR OVER 91 97 WITHIN OR
    SWAP 123 127 WITHIN OR ;

\ Unicode whitespace: the space separators, and tab, line feed, line
\ tabulation, form feed and carriage return.
: _MD-UWS?  ( cp -- flag )
    DUP 9 14 WITHIN IF DROP -1 EXIT THEN
    DUP 32 = OVER 160 = OR OVER 5760 = OR IF DROP -1 EXIT THEN
    DUP 8192 8203 WITHIN IF DROP -1 EXIT THEN
    DUP 8239 = OVER 8287 = OR SWAP 12288 = OR ;

\ Punctuation: ASCII punctuation, or General_Category P.
: _MD-PUNCT?  ( cp -- flag )
    DUP 128 < IF _MD-ASCII-PUNCT? EXIT THEN UP-PROPS UP-PUNCT? ;

: _MD-CHAR-IN?  ( a u c -- flag )
    -ROT 0 ?DO 2DUP I + C@ = IF 2DROP UNLOOP -1 EXIT THEN LOOP 2DROP 0 ;

VARIABLE _MDC-A
VARIABLE _MDC-U

\ _MD-DECODE ( a u -- cp n )
\   The scalar at A and its bytes, U at least 1.  An ill-formed sequence
\   reads as U+FFFD over its longest well-formed prefix, or one byte.
: _MD-DECODE  ( a u -- cp n )
    _MDC-U ! DUP _MDC-A ! C@
    DUP 128 < IF 1 EXIT THEN
    DUP 194 < IF DROP 65533 1 EXIT THEN
    DUP 224 < IF
        _MDC-U @ 2 < IF DROP 65533 1 EXIT THEN
        _MDC-A @ 1+ C@ DUP 128 192 WITHIN 0= IF 2DROP 65533 1 EXIT THEN
        63 AND SWAP 31 AND 6 LSHIFT OR 2 EXIT
    THEN
    DUP 240 < IF
        DUP 224 = IF 160 ELSE 128 THEN OVER 237 = IF 160 ELSE 192 THEN
        _MDC-U @ 2 < IF 2DROP DROP 65533 1 EXIT THEN
        _MDC-A @ 1+ C@ -ROT WITHIN 0= IF DROP 65533 1 EXIT THEN
        _MDC-U @ 3 < IF DROP 65533 2 EXIT THEN
        _MDC-A @ 2 + C@ 128 192 WITHIN 0= IF DROP 65533 2 EXIT THEN
        15 AND 12 LSHIFT
        _MDC-A @ 1+ C@ 63 AND 6 LSHIFT OR
        _MDC-A @ 2 + C@ 63 AND OR 3 EXIT
    THEN
    DUP 245 < IF
        DUP 240 = IF 144 ELSE 128 THEN OVER 244 = IF 144 ELSE 192 THEN
        _MDC-U @ 2 < IF 2DROP DROP 65533 1 EXIT THEN
        _MDC-A @ 1+ C@ -ROT WITHIN 0= IF DROP 65533 1 EXIT THEN
        _MDC-U @ 3 < IF DROP 65533 2 EXIT THEN
        _MDC-A @ 2 + C@ 128 192 WITHIN 0= IF DROP 65533 2 EXIT THEN
        _MDC-U @ 4 < IF DROP 65533 3 EXIT THEN
        _MDC-A @ 3 + C@ 128 192 WITHIN 0= IF DROP 65533 3 EXIT THEN
        7 AND 18 LSHIFT
        _MDC-A @ 1+ C@ 63 AND 12 LSHIFT OR
        _MDC-A @ 2 + C@ 63 AND 6 LSHIFT OR
        _MDC-A @ 3 + C@ 63 AND OR 4 EXIT
    THEN
    DROP 65533 1 ;

\ _MD-ENCODE ( cp a -- n )  Write CP's UTF-8 at A.
: _MD-ENCODE  ( cp a -- n )
    OVER 128 < IF C! 1 EXIT THEN
    OVER 2048 < IF
        OVER 6 RSHIFT 192 OR OVER C!
        SWAP 63 AND 128 OR SWAP 1+ C! 2 EXIT
    THEN
    OVER 65536 < IF
        OVER 12 RSHIFT 224 OR OVER C!
        OVER 6 RSHIFT 63 AND 128 OR OVER 1+ C!
        SWAP 63 AND 128 OR SWAP 2 + C! 3 EXIT
    THEN
    OVER 18 RSHIFT 240 OR OVER C!
    OVER 12 RSHIFT 63 AND 128 OR OVER 1+ C!
    OVER 6 RSHIFT 63 AND 128 OR OVER 2 + C!
    SWAP 63 AND 128 OR SWAP 3 + C! 4 ;

CREATE _MD-ENC 8 ALLOT

\ _MD-PUT-CP ( cp b -- )  Append CP's UTF-8 to buffer B.
: _MD-PUT-CP  ( cp b -- )  >R _MD-ENC _MD-ENCODE _MD-ENC SWAP R> _MD-PUT ;

VARIABLE _MLC-E

\ _MD-LAST-CP ( a u -- n cp )  The last scalar of the text, U at least 1.
: _MD-LAST-CP  ( a u -- n cp )
    OVER + _MLC-E !
    _MLC-E @ 1-
    BEGIN
        2DUP < IF DUP C@ 192 AND 128 = _MLC-E @ 2 PICK - 4 < AND ELSE 0 THEN
    WHILE 1- REPEAT
    NIP _MLC-E @ OVER - 2DUP _MD-DECODE
    ROT OVER = IF ROT DROP SWAP EXIT THEN
    2DROP DROP 1 65533 ;

\ _MD-TRIM ( a u -- a' u' )  Without its leading and trailing whitespace.
: _MD-TRIM  ( a u -- a' u' )
    BEGIN DUP 0> IF 2DUP _MD-DECODE SWAP _MD-UWS? ELSE 0 0 THEN WHILE /STRING REPEAT
    DROP
    BEGIN DUP 0> IF 2DUP _MD-LAST-CP _MD-UWS? ELSE 0 0 THEN WHILE - REPEAT
    DROP ;

\ _MD-STRIP ( a u -- a' u' )  Without leading and trailing ASCII whitespace.
: _MD-STRIP  ( a u -- a' u' )
    BEGIN DUP 0> IF OVER C@ _MD-WS? ELSE 0 THEN WHILE 1 /STRING REPEAT
    BEGIN DUP 0> IF 2DUP + 1- C@ _MD-WS? ELSE 0 THEN WHILE 1- REPEAT ;

: _MD-ALL-WS?  ( a u -- flag )
    0 ?DO DUP I + C@ _MD-WS? 0= IF DROP UNLOOP 0 EXIT THEN LOOP DROP -1 ;

: _MD-ALL-SPACES?  ( a u -- flag )
    0 ?DO DUP I + C@ 32 <> IF DROP UNLOOP 0 EXIT THEN LOOP DROP -1 ;

VARIABLE _MCB-C

\ _MD-COUNT-BYTE ( a u c -- n )  How many of the bytes are C.
: _MD-COUNT-BYTE  ( a u c -- n )
    _MCB-C ! 0 SWAP 0 ?DO OVER I + C@ _MCB-C @ = IF 1+ THEN LOOP NIP ;

VARIABLE _MSP-C

\ _MD-SPLIT ( a u c -- pa pu ra ru )
\   The text before the first C, and the text after it (empty when none).
: _MD-SPLIT  ( a u c -- pa pu ra ru )
    _MSP-C ! 2DUP
    BEGIN DUP 0> IF OVER C@ _MSP-C @ <> ELSE 0 THEN WHILE 1 /STRING REPEAT
    >R >R DROP R@ OVER - R> R>
    DUP IF 1 /STRING THEN ;

: _MD-PREFIX?  ( a u p v -- flag )
    ROT OVER < IF 2DROP DROP 0 EXIT THEN TUCK COMPARE 0= ;

VARIABLE _MFD-P
VARIABLE _MFD-V

\ _MD-FIND ( a u p v -- index | -1 )  Where P first occurs in the text.
: _MD-FIND  ( a u p v -- index | -1 )
    _MFD-V ! _MFD-P !
    DUP _MFD-V @ - 1+ 0 MAX 0 ?DO
        OVER I + _MFD-V @ _MFD-P @ _MFD-V @ COMPARE 0= IF 2DROP I UNLOOP EXIT THEN
    LOOP 2DROP -1 ;

\ Do the V bytes at A equal the lowercase text P, ignoring case?
: _MD-SAME-CI?  ( a p v -- flag )
    0 ?DO OVER I + C@ _MD-LOWER OVER I + C@ <> IF 2DROP UNLOOP 0 EXIT THEN LOOP
    2DROP -1 ;

: _MD-CONTAINS-CI?  ( a u p v -- flag )
    _MFD-V ! _MFD-P !
    DUP _MFD-V @ - 1+ 0 MAX 0 ?DO
        OVER I + _MFD-P @ _MFD-V @ _MD-SAME-CI? IF 2DROP UNLOOP -1 EXIT THEN
    LOOP 2DROP 0 ;

: _MD-DIGITS  ( n -- digits )  1 SWAP BEGIN 10 / DUP WHILE SWAP 1+ SWAP REPEAT DROP ;

\ =====================================================================
\  Entities and escapes
\ =====================================================================

\ A numeric reference to a scalar that may not appear reads as U+FFFD:
\ a surrogate, a noncharacter, a control but tab, line feed, form feed and
\ carriage return, and anything past U+10FFFF.
: _MD-ENTITY-SCALAR  ( n -- cp )
    DUP 55296 57344 WITHIN IF DROP 65533 EXIT THEN
    DUP 64976 65008 WITHIN IF DROP 65533 EXIT THEN
    DUP 65535 AND DUP 65535 = SWAP 65534 = OR IF DROP 65533 EXIT THEN
    DUP 0 9 WITHIN OVER 11 = OR IF DROP 65533 EXIT THEN
    DUP 14 32 WITHIN IF DROP 65533 EXIT THEN
    DUP 127 160 WITHIN IF DROP 65533 EXIT THEN
    DUP 1114111 > IF DROP 65533 EXIT THEN ;

VARIABLE _MME-A
VARIABLE _MME-U
VARIABLE _MME-I
VARIABLE _MME-V

: _MME-AT  ( i -- c | -1 )  DUP _MME-U @ < IF _MME-A @ + C@ ELSE DROP -1 THEN ;

\ _MD-MATCH-ENTITY ( a u -- len cp1 cp2 n )
\   The reference at A, which starts with &: its bytes and the one or two
\   scalars it stands for, or 0 0 0 0 when no reference starts there.
: _MD-MATCH-ENTITY  ( a u -- len cp1 cp2 n )
    _MME-U ! _MME-A ! 0 _MME-V !
    1 _MME-AT 35 = IF
        2 _MME-AT 32 OR 120 = IF
            \ &#x and one to six hexadecimal digits
            3 _MME-I !
            BEGIN _MME-I @ _MME-AT DUP _MD-HEX? _MME-I @ 9 < AND WHILE
                DUP 58 < IF 48 - ELSE 32 OR 87 - THEN
                _MME-V @ 4 LSHIFT + _MME-V ! 1 _MME-I +!
            REPEAT DROP
            _MME-I @ 3 - 1 7 WITHIN 0= IF 0 0 0 0 EXIT THEN
        ELSE
            \ &# and one to seven decimal digits
            2 _MME-I !
            BEGIN _MME-I @ _MME-AT DUP _MD-DIGIT? _MME-I @ 9 < AND WHILE
                48 - _MME-V @ 10 * + _MME-V ! 1 _MME-I +!
            REPEAT DROP
            _MME-I @ 2 - 1 8 WITHIN 0= IF 0 0 0 0 EXIT THEN
        THEN
        _MME-I @ _MME-AT 59 <> IF 0 0 0 0 EXIT THEN
        _MME-I @ 1+ _MME-V @ _MD-ENTITY-SCALAR 0 1 EXIT
    THEN
    \ & a letter and one to thirty-one letters or digits ;
    1 _MME-AT _MD-ALPHA? 0= IF 0 0 0 0 EXIT THEN
    2 _MME-I !
    BEGIN _MME-I @ _MME-AT _MD-ALNUM? _MME-I @ 34 < AND WHILE 1 _MME-I +! REPEAT
    _MME-I @ 3 34 WITHIN 0= IF 0 0 0 0 EXIT THEN
    _MME-I @ _MME-AT 59 <> IF 0 0 0 0 EXIT THEN
    _MME-A @ 1+ _MME-I @ 1- HENT-LOOKUP
    DUP 0= IF DROP 2DROP 0 0 0 0 EXIT THEN
    >R >R >R _MME-I @ 1+ R> R> R> ;

VARIABLE _MUN-A
VARIABLE _MUN-U
VARIABLE _MUN-B

\ _MD-UNESCAPE ( a u b -- )
\   Append the text to buffer B with its backslash escapes and entities
\   replaced by what they stand for.
: _MD-UNESCAPE  ( a u b -- )
    _MUN-B ! _MUN-U ! _MUN-A !
    BEGIN _MUN-U @ 0> WHILE
        _MUN-A @ C@
        DUP 92 = _MUN-U @ 1 > AND IF
            DROP _MUN-A @ 1+ C@ DUP _MD-ASCII-PUNCT? IF
                _MUN-B @ _MD-PUTC 2
            ELSE
                DROP 92 _MUN-B @ _MD-PUTC 1
            THEN
        ELSE DUP 38 = IF
            DROP _MUN-A @ _MUN-U @ _MD-MATCH-ENTITY
            DUP 0= IF
                2DROP 2DROP 38 _MUN-B @ _MD-PUTC 1
            ELSE
                2 = IF SWAP _MUN-B @ _MD-PUT-CP _MUN-B @ _MD-PUT-CP
                ELSE DROP _MUN-B @ _MD-PUT-CP THEN
            THEN
        ELSE
            _MUN-B @ _MD-PUTC 1
        THEN THEN
        DUP _MUN-A +! NEGATE _MUN-U +!
    REPEAT ;

\ =====================================================================
\  The subject a parse reads: the open paragraph, or a block's text
\ =====================================================================

VARIABLE _MD-SA
VARIABLE _MD-SU
VARIABLE _MD-POS

: _MD-AT     ( i -- c | -1 )  DUP _MD-SU @ < IF _MD-SA @ + C@ ELSE DROP -1 THEN ;
: _MD-SPEEK  ( -- c | -1 )    _MD-POS @ _MD-AT ;

: _MD-SKIP-SP  ( -- )
    BEGIN _MD-SPEEK _MD-SPACE-OR-TAB? WHILE 1 _MD-POS +! REPEAT ;
: _MD-SKIP-WS-NL  ( -- )
    BEGIN _MD-SPEEK DUP _MD-SPACE-OR-TAB? SWAP 10 = OR WHILE 1 _MD-POS +! REPEAT ;
\ Spaces and tabs, at most one line feed, then spaces and tabs.
: _MD-SPNL  ( -- )
    _MD-SKIP-SP _MD-SPEEK 10 = IF 1 _MD-POS +! _MD-SKIP-SP THEN ;
: _MD-AT-LINE-END?  ( -- flag )  _MD-SPEEK DUP -1 = SWAP 10 = OR ;

\ The scalar at byte I, or a line feed past the end.
: _MD-CP-AT  ( i -- cp )
    DUP _MD-SU @ < 0= IF DROP 10 EXIT THEN
    _MD-SA @ OVER + SWAP _MD-SU @ SWAP - _MD-DECODE DROP ;

\ The scalar that ends before byte I, or a line feed at the start.
: _MD-CP-BEFORE  ( i -- cp )
    DUP 0= IF DROP 10 EXIT THEN
    _MD-SA @ SWAP _MD-LAST-CP NIP ;

VARIABLE _MLL-I
VARIABLE _MLL-N

\ _MD-LINK-LABEL ( -- n )
\   A link label at the position: [, at most 999 characters with no
\   unescaped bracket, and ].  Moves past it and returns its bytes, or
\   returns 0 and stays.
: _MD-LINK-LABEL  ( -- n )
    _MD-SPEEK 91 <> IF 0 EXIT THEN
    _MD-POS @ 1+ _MLL-I ! 0 _MLL-N !
    BEGIN
        _MLL-I @ _MD-AT
        DUP -1 = OVER 91 = OR IF DROP 0 EXIT THEN
        DUP 93 = IF
            DROP _MLL-N @ 999 > IF 0 EXIT THEN
            _MLL-I @ 1+ _MD-POS @ - DUP _MD-POS +! EXIT
        THEN
        92 = IF
            _MLL-I @ 1+ _MD-AT -1 <> IF 1 _MLL-I +! 1 _MLL-N +! THEN
        THEN
        _MLL-I @ _MD-AT 192 AND 128 <> IF 1 _MLL-N +! THEN
        1 _MLL-I +!
    AGAIN ;

VARIABLE _MD-DEST-A
VARIABLE _MD-DEST-U
VARIABLE _MLD-START
VARIABLE _MLD-LEVEL

\ One step through a bare destination: false where it ends.
: _MD-DEST-STEP  ( -- more? )
    _MD-SPEEK
    DUP 33 < OVER 127 = OR IF DROP 0 EXIT THEN
    DUP 92 = IF
        DROP _MD-POS @ 1+ _MD-SU @ < IF
            _MD-POS @ 1+ _MD-AT 32 = IF 0 EXIT THEN
            2 _MD-POS +! -1 EXIT
        THEN
        1 _MD-POS +! -1 EXIT
    THEN
    DUP 40 = IF DROP 1 _MLD-LEVEL +! 1 _MD-POS +! -1 EXIT THEN
    41 = IF
        _MLD-LEVEL @ 0= IF 0 EXIT THEN
        -1 _MLD-LEVEL +!
    THEN
    1 _MD-POS +! -1 ;

\ _MD-LINK-DEST ( -- ok? )
\   A link destination at the position: <...> without a line feed or <,
\   or text without spaces or controls whose parentheses balance.  Moves
\   past it and leaves its raw text in _MD-DEST-A and _MD-DEST-U, or
\   returns false and stays.
: _MD-LINK-DEST  ( -- ok? )
    _MD-POS @ _MLD-START !
    _MD-SPEEK 60 = IF
        1 _MD-POS +!
        BEGIN
            _MD-SPEEK
            DUP -1 = OVER 10 = OR OVER 60 = OR IF
                DROP _MLD-START @ _MD-POS ! 0 EXIT
            THEN
            DUP 62 = IF
                DROP _MD-SA @ _MLD-START @ + 1+ _MD-DEST-A !
                _MD-POS @ _MLD-START @ - 1- _MD-DEST-U !
                1 _MD-POS +! -1 EXIT
            THEN
            92 = _MD-POS @ 1+ _MD-SU @ < AND IF 2 ELSE 1 THEN _MD-POS +!
        AGAIN
    THEN
    0 _MLD-LEVEL !
    BEGIN _MD-DEST-STEP 0= UNTIL
    _MD-POS @ _MLD-START @ = _MLD-LEVEL @ 0<> OR IF
        _MLD-START @ _MD-POS ! 0 EXIT
    THEN
    _MD-SA @ _MLD-START @ + _MD-DEST-A !
    _MD-POS @ _MLD-START @ - _MD-DEST-U ! -1 ;

VARIABLE _MD-TITLE-U

\ _MD-LINK-TITLE ( -- ok? )
\   A link title at the position, in "", '' or ().  Moves past it and
\   leaves its raw length in _MD-TITLE-U, or returns false and stays.
: _MD-LINK-TITLE  ( -- ok? )
    _MD-POS @ >R
    _MD-SPEEK DUP 34 = OVER 39 = OR OVER 40 = OR 0= IF DROP R> DROP 0 EXIT THEN
    DUP 40 = IF DROP 41 THEN
    1 _MD-POS +!
    BEGIN _MD-SPEEK DUP -1 <> WHILE
        2DUP = IF
            2DROP _MD-POS @ R> - 1- _MD-TITLE-U ! 1 _MD-POS +! -1 EXIT
        THEN
        DUP 40 = 2 PICK 41 = AND IF 2DROP R> _MD-POS ! 0 EXIT THEN
        92 = _MD-POS @ 1+ _MD-SU @ < AND IF 1 _MD-POS +! THEN
        1 _MD-POS +!
    REPEAT
    2DROP R> _MD-POS ! 0 ;

\ =====================================================================
\  Link reference definitions
\ =====================================================================

: _MD-STRING   ( a u -- off )  _MD-STRS _MB.N @ -ROT _MD-STRS _MD-PUT ;
: _MD-STRING@  ( off u -- a u )  SWAP _MD-STRS _MB.A @ + SWAP ;

VARIABLE _MNZ-B
VARIABLE _MNZ-PEND
VARIABLE _MNZ-ANY

\ _MD-NORMALIZE ( a u b -- )
\   Append a label to buffer B as references match it: trimmed, with each
\   run of whitespace one space, in ASCII capitals.
: _MD-NORMALIZE  ( a u b -- )
    _MNZ-B ! 0 _MNZ-PEND ! 0 _MNZ-ANY !
    BEGIN DUP 0> WHILE
        2DUP _MD-DECODE
        OVER _MD-UWS? IF
            NIP _MNZ-ANY @ IF -1 _MNZ-PEND ! THEN
        ELSE
            _MNZ-PEND @ IF 32 _MNZ-B @ _MD-PUTC 0 _MNZ-PEND ! THEN
            -1 _MNZ-ANY !
            SWAP DUP 128 < IF _MD-UPPER THEN _MNZ-B @ _MD-PUT-CP
        THEN
        /STRING
    REPEAT 2DROP ;

\ The table of definitions: slots of 32 bytes, each the offsets and
\ lengths of a label and its destination among the strings, a power of
\ two of them; _MB.N counts the definitions.
: _MD-REF-SLOT   ( k -- a )  5 LSHIFT _MD-REFS _MB.A @ + ;
: _MD-REF-SLOTS  ( -- n )    _MD-REFS _MB.CAP @ 5 RSHIFT ;

: _MD-HASH  ( a u -- h )
    -3750763034362895579 SWAP 0 ?DO OVER I + C@ XOR 1099511628211 * LOOP NIP ;

VARIABLE _MRF-A
VARIABLE _MRF-U

\ _MD-REF-FIND ( a u -- slot found? )
\   The slot holding the label, or the empty slot where it would go.
: _MD-REF-FIND  ( a u -- slot found? )
    _MRF-U ! _MRF-A !
    _MRF-A @ _MRF-U @ _MD-HASH _MD-REF-SLOTS 1- AND
    BEGIN
        DUP _MD-REF-SLOT
        DUP 8 + @ 0= IF NIP 0 EXIT THEN
        DUP @ OVER 8 + @ _MD-STRING@ _MRF-A @ _MRF-U @ COMPARE 0= IF NIP -1 EXIT THEN
        DROP 1+ _MD-REF-SLOTS 1- AND
    AGAIN ;

: _MD-REF-PUT  ( loff lu doff du slot -- )
    TUCK 24 + ! TUCK 16 + ! TUCK 8 + ! ! 1 _MD-REFS _MB.N +! ;

VARIABLE _MRG-OLD
VARIABLE _MRG-CAP
VARIABLE _MRG-S
VARIABLE _MRG-T

\ Twice the slots, never less than 16, holding the same definitions.
: _MD-REF-GROW  ( -- )
    _MD-REFS _MB.A @ _MRG-OLD ! _MD-REFS _MB.CAP @ _MRG-CAP !
    _MRG-CAP @ 2* 512 MAX DUP _MD-ALLOC
    2DUP SWAP 0 FILL
    _MD-REFS _MB.A ! _MD-REFS _MB.CAP ! 0 _MD-REFS _MB.N !
    _MRG-CAP @ 0 ?DO
        _MRG-OLD @ I + _MRG-S !
        _MRG-S @ 8 + @ IF
            _MRG-S @ @ _MRG-S @ 8 + @ 2DUP _MD-STRING@ _MD-REF-FIND DROP _MRG-T !
            _MRG-S @ 16 + @ _MRG-S @ 24 + @ _MRG-T @ _MD-REF-PUT
        THEN
    32 +LOOP
    _MRG-OLD @ _MRG-CAP @ _MD-FREE ;

\ _MD-FIND-LABEL ( a u -- dest-a dest-u found? )
\   The destination a link label with its brackets names.
: _MD-FIND-LABEL  ( a u -- dest-a dest-u found? )
    _MD-REFS _MB.N @ 0= IF 2DROP 0 0 0 EXIT THEN
    _MD-POOL _MB.N @ >R
    1 /STRING 1- _MD-POOL _MD-NORMALIZE
    _MD-POOL _MB.A @ R@ + _MD-POOL _MB.N @ R@ -
    _MD-REF-FIND IF
        DUP 16 + @ SWAP 24 + @ _MD-STRING@ -1
    ELSE DROP 0 0 0 THEN
    R> _MD-POOL _MB.N ! ;

VARIABLE _MRD-LABEL-U
VARIABLE _MRD-DEST-A
VARIABLE _MRD-DEST-U
VARIABLE _MRD-AFTER
VARIABLE _MRD-TITLE
VARIABLE _MRD-MARK

\ _MD-REFERENCE ( -- consumed )
\   A link reference definition at the start of the subject: its label,
\   :, its destination, an optional title, and the end of its line.  Keeps
\   the first definition of each label and returns the bytes it took, all
\   whole lines, or 0.
: _MD-REFERENCE  ( -- consumed )
    0 _MD-POS !
    _MD-LINK-LABEL DUP 0= IF EXIT THEN _MRD-LABEL-U !
    _MD-SPEEK 58 <> IF 0 EXIT THEN 1 _MD-POS +!
    _MD-SKIP-WS-NL
    _MD-LINK-DEST 0= IF 0 EXIT THEN
    _MD-DEST-A @ _MRD-DEST-A ! _MD-DEST-U @ _MRD-DEST-U !
    _MD-POS @ _MRD-AFTER !
    _MD-SKIP-WS-NL
    0 _MRD-TITLE !
    _MD-POS @ _MRD-AFTER @ <> _MD-POS @ _MD-SU @ < AND IF
        _MD-LINK-TITLE IF -1 _MRD-TITLE ! ELSE _MRD-AFTER @ _MD-POS ! THEN
    ELSE _MRD-AFTER @ _MD-POS ! THEN
    _MD-SKIP-SP
    _MD-AT-LINE-END? 0= IF
        \ Something follows on the line.  Without a title that is not
        \ empty, the definition fails; else it may end at its destination.
        _MRD-TITLE @ IF _MD-TITLE-U @ 0> ELSE 0 THEN 0= IF 0 EXIT THEN
        _MRD-AFTER @ _MD-POS ! _MD-SKIP-SP
        _MD-AT-LINE-END? 0= IF 0 EXIT THEN
    THEN
    _MD-SPEEK 10 = IF 1 _MD-POS +! THEN
    _MD-STRS _MB.N @ _MRD-MARK !
    _MD-SA @ 1+ _MRD-LABEL-U @ 2 - _MD-STRS _MD-NORMALIZE
    _MD-STRS _MB.N @ _MRD-MARK @ - DUP 0= IF DROP 0 EXIT THEN
    _MRD-MARK @ SWAP                                 ( loff lu )
    _MD-REFS _MB.N @ IF
        2DUP _MD-STRING@ _MD-REF-FIND NIP IF
            \ An earlier definition of the label stands.
            2DROP _MRD-MARK @ _MD-STRS _MB.N ! _MD-POS @ EXIT
        THEN
    THEN
    _MD-STRS _MB.N @
    _MRD-DEST-A @ _MRD-DEST-U @ _MD-STRS _MD-UNESCAPE
    _MD-STRS _MB.N @ OVER -                          ( loff lu doff du )
    _MD-REFS _MB.N @ 1+ 2* _MD-REF-SLOTS > IF _MD-REF-GROW THEN
    3 PICK 3 PICK _MD-STRING@ _MD-REF-FIND DROP _MD-REF-PUT
    _MD-POS @ ;

\ =====================================================================
\  Source lines
\ =====================================================================

VARIABLE _MD-FPOS       \ the next file offset to read into the chunk
VARIABLE _MD-FSIZE
VARIABLE _MD-CPOS       \ the next unread byte of the chunk
VARIABLE _MD-CLEN       \ the bytes the chunk holds
VARIABLE _MD-CR         \ the last line ended with a carriage return
VARIABLE _MD-L-A        \ the line, without its end
VARIABLE _MD-L-U
VARIABLE _MD-L-OFF      \ the file offset of its first byte
VARIABLE _MD-LINE-NO
VARIABLE _MD-CEND       \ where the chunk's bytes end

4096 CONSTANT _MD-CHUNK-BYTES

\ Refill the chunk; false at the end of the source.
: _MD-FILL  ( -- more? )
    _MD-FPOS @ _MD-FSIZE @ U< 0= IF 0 EXIT THEN
    _MD-FSIZE @ _MD-FPOS @ - _MD-CHUNK-BYTES MIN DUP _MD-CLEN !
    _MD-CHUNK _MB.A @ SWAP _MD-FPOS @ _MD-D @ DOC-SOURCE@ MEDSRC-READ?
    IF _MD-E-READ THROW THEN
    _MD-CLEN @ _MD-FPOS +! 0 _MD-CPOS ! -1 ;

: _MD-CHUNK-HAS?  ( -- flag )
    _MD-CPOS @ _MD-CLEN @ < IF -1 EXIT THEN _MD-FILL ;

: _MD-LINE-DONE  ( -- )
    _MD-LBUF _MB.A @ _MD-L-A ! _MD-LBUF _MB.N @ _MD-L-U ! ;

\ _MD-NEXT-LINE ( -- more? )
\   Read the next line into the line buffer.  A line ends at a line feed, a
\   carriage return, both, or the end of the source; an empty last line
\   after a final line end is no line.
: _MD-NEXT-LINE  ( -- more? )
    0 _MD-LBUF _MB.N !
    _MD-CHUNK-HAS? 0= IF 0 EXIT THEN
    _MD-CR @ IF
        0 _MD-CR !
        _MD-CHUNK _MB.A @ _MD-CPOS @ + C@ 10 = IF
            1 _MD-CPOS +!
            _MD-CHUNK-HAS? 0= IF 0 EXIT THEN
        THEN
    THEN
    _MD-FPOS @ _MD-CLEN @ - _MD-CPOS @ + _MD-L-OFF !
    BEGIN
        \ Scan the chunk from the next byte to a line's end or its own.
        _MD-CHUNK _MB.A @ DUP _MD-CLEN @ + _MD-CEND !
        DUP _MD-CPOS @ +
        BEGIN
            DUP _MD-CEND @ < IF DUP C@ DUP 10 <> SWAP 13 <> AND ELSE 0 THEN
        WHILE 1+ REPEAT
        SWAP -
        _MD-CHUNK _MB.A @ _MD-CPOS @ + OVER _MD-CPOS @ - _MD-LBUF _MD-PUT
        DUP _MD-CPOS !
        _MD-CLEN @ < IF
            _MD-CHUNK _MB.A @ _MD-CPOS @ + C@ 13 = _MD-CR !
            1 _MD-CPOS +! _MD-LINE-DONE -1 EXIT
        THEN
        _MD-FILL 0= IF _MD-LINE-DONE -1 EXIT THEN
    AGAIN ;

\ =====================================================================
\  Where the line is read from
\ =====================================================================

VARIABLE _MD-OFFSET
VARIABLE _MD-COLUMN
VARIABLE _MD-PARTIAL       \ a tab is partly taken by the offset
VARIABLE _MD-NN            \ the next byte that is not a space or tab
VARIABLE _MD-NN-COL
VARIABLE _MD-INDENT
VARIABLE _MD-INDENTED
VARIABLE _MD-BLANK

: _MD-PEEK  ( i -- c | -1 )
    DUP _MD-L-U @ < IF _MD-L-A @ + C@ ELSE DROP -1 THEN ;

: _MD-REST  ( i -- a u )  _MD-L-A @ OVER + _MD-L-U @ ROT - 0 MAX ;

: _MD-FIND-NEXT-NONSPACE  ( -- )
    _MD-OFFSET @ _MD-COLUMN @
    BEGIN
        OVER _MD-PEEK
        DUP 32 = IF DROP 1+ SWAP 1+ SWAP 0 ELSE
        9 = IF DUP 4 MOD 4 SWAP - + SWAP 1+ SWAP 0 ELSE -1 THEN THEN
    UNTIL
    _MD-NN-COL ! DUP _MD-NN !
    _MD-PEEK -1 = _MD-BLANK !
    _MD-NN-COL @ _MD-COLUMN @ - DUP _MD-INDENT !
    3 > _MD-INDENTED ! ;

: _MD-ADVANCE-NEXT-NONSPACE  ( -- )
    _MD-NN @ _MD-OFFSET ! _MD-NN-COL @ _MD-COLUMN ! 0 _MD-PARTIAL ! ;

VARIABLE _MAO-N
VARIABLE _MAO-COLS

\ _MD-ADVANCE-OFFSET ( count columns? -- )
\   Move past COUNT characters, or COUNT columns when COLUMNS?, where a tab
\   may be taken in part.
: _MD-ADVANCE-OFFSET  ( count columns? -- )
    _MAO-COLS ! _MAO-N !
    BEGIN _MAO-N @ 0> _MD-OFFSET @ _MD-PEEK -1 <> AND WHILE
        _MD-OFFSET @ _MD-PEEK 9 = IF
            4 _MD-COLUMN @ 4 MOD -
            _MAO-COLS @ IF
                DUP _MAO-N @ > _MD-PARTIAL !
                _MAO-N @ MIN
                DUP _MD-COLUMN +!
                _MD-PARTIAL @ 0= IF 1 _MD-OFFSET +! THEN
                NEGATE _MAO-N +!
            ELSE
                _MD-COLUMN +! 0 _MD-PARTIAL ! 1 _MD-OFFSET +! -1 _MAO-N +!
            THEN
        ELSE
            0 _MD-PARTIAL ! 1 _MD-OFFSET +! 1 _MD-COLUMN +! -1 _MAO-N +!
        THEN
    REPEAT ;

\ =====================================================================
\  Nodes
\ =====================================================================

0 CONSTANT _MD-T-DOC
1 CONSTANT _MD-T-QUOTE
2 CONSTANT _MD-T-LIST
3 CONSTANT _MD-T-ITEM
4 CONSTANT _MD-T-PARA
5 CONSTANT _MD-T-HEADING
6 CONSTANT _MD-T-CODE
7 CONSTANT _MD-T-HTML
8 CONSTANT _MD-T-RULE

\ A node is 64 bytes of 32-bit fields.  Node 0 is the document, which is
\ no node's child, so a child, last child or next sibling of 0 means none.
\ NB holds where the nodes are, which changes only when they grow.
VARIABLE _MD-NB
 0 CONSTANT _N.TYPE
 4 CONSTANT _N.FLAGS
 8 CONSTANT _N.PARENT
12 CONSTANT _N.FIRST
16 CONSTANT _N.LAST
20 CONSTANT _N.NEXT
24 CONSTANT _N.START       \ the line it began on
28 CONSTANT _N.LFIRST      \ its line spans
32 CONSTANT _N.LCOUNT
36 CONSTANT _N.LEVEL       \ a heading's level
36 CONSTANT _N.HTYPE       \ an HTML block's type, 1 to 7
36 CONSTANT _N.FCHAR       \ a fence's character
36 CONSTANT _N.MCHAR       \ a list's bullet, or its number's delimiter
40 CONSTANT _N.FLEN        \ a fence's length
40 CONSTANT _N.LSTART      \ a list's first number
44 CONSTANT _N.FOFF        \ a fence's indentation
44 CONSTANT _N.MOFF        \ an item's marker indentation
48 CONSTANT _N.PAD         \ an item's marker width with its spaces
56 CONSTANT _N.KEEP        \ code or HTML: lines to the last with text
56 CONSTANT _N.COUNT       \ a list's items; an item's place in its list
60 CONSTANT _N.MARK        \ the block whose ancestor it last was
64 CONSTANT _N-SIZE

 1 CONSTANT _MD-F-OPEN
 2 CONSTANT _MD-F-LASTBLANK
 4 CONSTANT _MD-F-CHECKED
 8 CONSTANT _MD-F-FENCED
16 CONSTANT _MD-F-TIGHT
32 CONSTANT _MD-F-ORDERED
 64 CONSTANT _MD-F-STARTED
128 CONSTANT _MD-F-TABLE       \ a paragraph whose last lines are a table

: _MD-N   ( i -- n )  6 LSHIFT _MD-NB @ + ;
: _N@     ( i field -- v )  SWAP 6 LSHIFT + _MD-NB @ + L@ ;
: _N!     ( v i field -- )  SWAP 6 LSHIFT + _MD-NB @ + L! ;
: _NF?    ( i bit -- flag )  SWAP _N.FLAGS _N@ AND 0<> ;
: _NF+    ( i bit -- )  OVER _N.FLAGS _N@ OR SWAP _N.FLAGS _N! ;
: _NF-    ( i bit -- )  INVERT OVER _N.FLAGS _N@ AND SWAP _N.FLAGS _N! ;
: _MD-TYPE  ( i -- type )  _N.TYPE _N@ ;

\ A paragraph that holds no table.  Once a table starts, a line that
\ begins any other block ends it, as GitHub tables end.
: _MD-PLAIN-PARA?  ( i -- flag )
    DUP _MD-TYPE _MD-T-PARA = SWAP _MD-F-TABLE _NF? 0= AND ;

VARIABLE _MD-TIP          \ the innermost open block, -1 when none
VARIABLE _MD-OLDTIP
VARIABLE _MD-CONT         \ the container a line has matched so far
VARIABLE _MD-LAST-MATCHED
VARIABLE _MD-ALL-CLOSED

VARIABLE _MNN-I

\ _MD-NEW-NODE ( type parent -- i )  A new open node, PARENT's last child.
: _MD-NEW-NODE  ( type parent -- i )
    _MD-NODES _MB.N @ 6 RSHIFT _MNN-I !
    _N-SIZE _MD-NODES _MD-ROOM _N-SIZE 0 FILL
    _MD-NODES _MB.A @ _MD-NB !
    _MNN-I @ _N.PARENT _N!
    _MNN-I @ _N.TYPE _N!
    _MD-F-OPEN _MNN-I @ _N.FLAGS _N!
    _MD-LINE-NO @ _MNN-I @ _N.START _N!
    _MNN-I @ IF
        _MNN-I @ _N.PARENT _N@
        DUP _N.LAST _N@ ?DUP IF
            _MNN-I @ SWAP _N.NEXT _N!
        ELSE
            _MNN-I @ OVER _N.FIRST _N!
        THEN
        _MNN-I @ SWAP _N.LAST _N!
    THEN
    _MNN-I @ ;

VARIABLE _MUL-I
VARIABLE _MUL-P

\ _MD-UNLINK ( i -- )  Take a node out of its parent's children.
: _MD-UNLINK  ( i -- )
    DUP _MUL-I ! _N.PARENT _N@ _MUL-P !
    _MUL-P @ _N.FIRST _N@ _MUL-I @ = IF
        _MUL-I @ _N.NEXT _N@ _MUL-P @ _N.FIRST _N!
        _MUL-P @ _N.LAST _N@ _MUL-I @ = IF 0 _MUL-P @ _N.LAST _N! THEN
        EXIT
    THEN
    _MUL-P @ _N.FIRST _N@
    BEGIN DUP _N.NEXT _N@ _MUL-I @ <> WHILE _N.NEXT _N@ REPEAT
    _MUL-I @ _N.NEXT _N@ OVER _N.NEXT _N!
    _MUL-P @ _N.LAST _N@ _MUL-I @ = IF _MUL-P @ _N.LAST _N! ELSE DROP THEN ;

: _MD-ACCEPTS-LINES?  ( type -- flag )
    DUP _MD-T-PARA = OVER _MD-T-CODE = OR SWAP _MD-T-HTML = OR ;

: _MD-CAN-CONTAIN?  ( parent-type child-type -- flag )
    SWAP
    DUP _MD-T-LIST = IF DROP _MD-T-ITEM = EXIT THEN
    DUP _MD-T-DOC = OVER _MD-T-QUOTE = OR SWAP _MD-T-ITEM = OR IF
        _MD-T-ITEM <> EXIT
    THEN
    DROP 0 ;

\ =====================================================================
\  Line spans and the open paragraph
\ =====================================================================

\ A span is 8 bytes: the file offset of a line's content, then its
\ length shifted left 2 with the columns of a tab taken in part before
\ it, which show as spaces.
: _MD-SPAN   ( k -- a )  3 LSHIFT _MD-LINES _MB.A @ + ;
: _MD-SPANS  ( -- n )  _MD-LINES _MB.N @ 3 RSHIFT ;
: _MD-SPAN@  ( k -- off u lead )
    _MD-SPAN DUP L@ SWAP 4 + L@ DUP 2 RSHIFT SWAP 3 AND ;
: _MD-ADD-SPAN  ( off u lead -- )
    SWAP 2 LSHIFT OR >R
    8 _MD-LINES _MD-ROOM TUCK L! R> SWAP 4 + L! ;

\ The open paragraph's text: each line, after a tab taken in part, and a
\ line feed.  Definitions taken from its start move PARA-START.
VARIABLE _MD-PARA-START

: _MD-PARA-TEXT  ( -- a u )
    _MD-PARA _MB.A @ _MD-PARA-START @ + _MD-PARA _MB.N @ _MD-PARA-START @ - ;

\ The paragraph's last line, without its line feed.
: _MD-PARA-LAST  ( -- a u )
    _MD-PARA-TEXT DUP 0= IF EXIT THEN
    1- 2DUP
    BEGIN DUP 0> IF 2DUP + 1- C@ 10 <> ELSE 0 THEN WHILE 1- REPEAT
    NIP /STRING ;

: _MD-ADD-LINE  ( -- )
    0
    _MD-PARTIAL @ IF 1 _MD-OFFSET +! DROP 4 _MD-COLUMN @ 4 MOD - THEN
    _MD-OFFSET @ _MD-L-U @ MIN
    _MD-TIP @ _N.LCOUNT _N@ 0= IF _MD-SPANS _MD-TIP @ _N.LFIRST _N! THEN
    _MD-TIP @ _N.LCOUNT _N@ 1+ _MD-TIP @ _N.LCOUNT _N!
    DUP _MD-L-OFF @ + OVER _MD-L-U @ SWAP - 3 PICK _MD-ADD-SPAN
    _MD-TIP @ _MD-TYPE _MD-T-PARA = IF
        OVER 0 ?DO 32 _MD-PARA _MD-PUTC LOOP
        _MD-L-A @ OVER + _MD-L-U @ ROT - _MD-PARA _MD-PUT
        DROP 10 _MD-PARA _MD-PUTC EXIT
    THEN
    \ Code and HTML: count the lines up to the last that is not only spaces.
    NIP _MD-L-U @ SWAP ?DO
        _MD-L-A @ I + C@ 32 <> IF
            _MD-TIP @ _N.LCOUNT _N@ _MD-TIP @ _N.KEEP _N! LEAVE
        THEN
    LOOP ;

\ =====================================================================
\  GitHub tables
\ =====================================================================

\ A delimiter row's cell: an optional colon, hyphens, an optional colon.
: _MD-ALIGN-CELL?  ( a u -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 58 = IF 1 /STRING THEN
    DUP 0> IF 2DUP + 1- C@ 58 = IF 1- THEN THEN
    DUP 0= IF 2DROP 0 EXIT THEN
    0 ?DO DUP I + C@ 45 <> IF DROP UNLOOP 0 EXIT THEN LOOP DROP -1 ;

: _MD-ROW-START?  ( c -- flag )  DUP 124 = OVER 45 = OR SWAP 58 = OR ;

: _MD-ROW-CHAR?  ( c -- flag )
    DUP 124 = OVER 45 = OR OVER 58 = OR SWAP _MD-SPACE-OR-TAB? OR ;

VARIABLE _MDR-A
VARIABLE _MDR-U
VARIABLE _MDR-N
VARIABLE _MDR-CELLS

\ _MD-DELIM-ROW ( a u -- columns )
\   The columns of a table's delimiter row, or 0 when the text is none.
: _MD-DELIM-ROW  ( a u -- columns )
    _MDR-U ! _MDR-A !
    _MDR-U @ 2 < IF 0 EXIT THEN
    _MDR-A @ C@ DUP 124 = OVER 45 = OR SWAP 58 = OR 0= IF 0 EXIT THEN
    _MDR-A @ 1+ C@ _MD-ROW-CHAR? 0= IF 0 EXIT THEN
    _MDR-A @ C@ 45 = _MDR-A @ 1+ C@ _MD-SPACE-OR-TAB? AND IF 0 EXIT THEN
    _MDR-U @ 0 ?DO
        _MDR-A @ I + C@ _MD-ROW-CHAR? 0= IF UNLOOP 0 EXIT THEN
    LOOP
    _MDR-A @ _MDR-U @ 124 _MD-COUNT-BYTE 1+ _MDR-CELLS !
    0 _MDR-N !
    _MDR-A @ _MDR-U @
    _MDR-CELLS @ 0 ?DO
        124 _MD-SPLIT 2SWAP _MD-STRIP
        DUP 0= IF
            2DROP I 0= I _MDR-CELLS @ 1- = OR 0= IF 2DROP UNLOOP 0 EXIT THEN
        ELSE
            _MD-ALIGN-CELL? 0= IF 2DROP UNLOOP 0 EXIT THEN
            1 _MDR-N +!
        THEN
    LOOP
    2DROP _MDR-N @ ;

VARIABLE _MHC-P

\ _MD-HEADER-CELLS ( a u -- n )
\   The cells of a table's header row: its text split at each | that no
\   backslash comes right before, less an empty first or last cell.
: _MD-HEADER-CELLS  ( a u -- n )
    _MD-STRIP
    2DUP 124 _MD-COUNT-BYTE 0= IF 2DROP 0 EXIT THEN
    0 _MHC-P !
    DUP 0 ?DO
        OVER I + C@ 124 = IF
            I 0= IF 1 _MHC-P +! ELSE OVER I + 1- C@ 92 <> IF 1 _MHC-P +! THEN THEN
        THEN
    LOOP
    _MHC-P @ 1+
    2 PICK C@ 124 = IF 1- THEN
    2 PICK 2 PICK + 1- C@ 124 = IF
        OVER 1 = IF 1- ELSE 2 PICK 2 PICK + 2 - C@ 92 <> IF 1- THEN THEN
    THEN
    NIP NIP ;

\ _MD-TABLE-PAIR? ( ha hu da du -- flag )
\   Do a header row and the line after it start a table?
: _MD-TABLE-PAIR?  ( ha hu da du -- flag )
    _MD-DELIM-ROW DUP 0= IF NIP NIP EXIT THEN
    >R _MD-HEADER-CELLS R> = ;

VARIABLE _MPT-PA
VARIABLE _MPT-PU
VARIABLE _MPT-K

\ _MD-PARA-TABLE ( -- k | -1 )  The paragraph's line where a table starts.
: _MD-PARA-TABLE  ( -- k | -1 )
    _MD-PARA-TEXT
    -1 _MPT-PA ! 0 _MPT-PU ! 0 _MPT-K !
    BEGIN DUP 0> WHILE
        10 _MD-SPLIT 2SWAP
        _MPT-PA @ -1 <> IF
            _MPT-PA @ _MPT-PU @ 2OVER _MD-TABLE-PAIR? IF
                2DROP 2DROP _MPT-K @ 1- EXIT
            THEN
        THEN
        _MPT-PU ! _MPT-PA ! 1 _MPT-K +!
    REPEAT
    2DROP -1 ;

\ =====================================================================
\  Closing blocks
\ =====================================================================

DEFER _MD-FINALIZE   ( i -- )

\ _MD-ADD-CHILD ( type -- i )
\   Close the innermost open block until one can hold TYPE, and add a new
\   block of that type to it.
: _MD-ADD-CHILD  ( type -- i )
    BEGIN _MD-TIP @ _MD-TYPE OVER _MD-CAN-CONTAIN? 0= WHILE
        _MD-TIP @ _MD-FINALIZE
    REPEAT
    _MD-TIP @ _MD-NEW-NODE DUP _MD-TIP ! ;

: _MD-CLOSE-UNMATCHED  ( -- )
    _MD-ALL-CLOSED @ IF EXIT THEN
    BEGIN _MD-OLDTIP @ _MD-LAST-MATCHED @ <> WHILE
        _MD-OLDTIP @ DUP _N.PARENT _N@ _MD-OLDTIP ! _MD-FINALIZE
    REPEAT
    -1 _MD-ALL-CLOSED ! ;

\ Does the block end with a blank line, looking into a list's last item
\ and an item's last block?
: _MD-ENDS-BLANK?  ( i -- flag )
    BEGIN
        DUP 0= IF DROP 0 EXIT THEN
        DUP _MD-F-LASTBLANK _NF? IF DROP -1 EXIT THEN
        DUP _MD-F-CHECKED _NF? 0=
        OVER _MD-TYPE DUP _MD-T-LIST = SWAP _MD-T-ITEM = OR AND
        OVER _MD-F-CHECKED _NF+
        0= IF DROP 0 EXIT THEN
        _N.LAST _N@
    AGAIN ;

VARIABLE _MFL-L

\ A list is loose when an item but its last ends with a blank line, or a
\ block in an item ends with one and something follows it in the list.
: _MD-FINALIZE-LIST  ( i -- )
    DUP _MFL-L ! _N.FIRST _N@
    BEGIN DUP WHILE
        DUP _MD-ENDS-BLANK? OVER _N.NEXT _N@ 0<> AND IF
            DROP _MFL-L @ _MD-F-TIGHT _NF- EXIT
        THEN
        DUP _N.FIRST _N@
        BEGIN DUP WHILE
            DUP _MD-ENDS-BLANK?
            2 PICK _N.NEXT _N@ 0<> 2 PICK _N.NEXT _N@ 0<> OR AND IF
                DROP 0 _MFL-L @ _MD-F-TIGHT _NF-
            ELSE
                _N.NEXT _N@
            THEN
        REPEAT DROP
        _N.NEXT _N@
    REPEAT DROP ;

: _MD-FINALIZE-CODE  ( i -- )
    DUP _MD-F-FENCED _NF? IF
        \ The opening line, with the info string, is not code.
        DUP _N.LCOUNT _N@ IF
            DUP _N.LFIRST _N@ 1+ OVER _N.LFIRST _N!
            DUP _N.LCOUNT _N@ 1- SWAP _N.LCOUNT _N!
        ELSE DROP THEN
        EXIT
    THEN
    DUP _N.KEEP _N@ SWAP _N.LCOUNT _N! ;

\ _MD-TAKE-REFS ( i -- )
\   Take the link reference definitions at the start of open paragraph I,
\   with the lines they fill.
: _MD-TAKE-REFS  ( i -- )
    BEGIN
        _MD-PARA-TEXT _MD-SU ! _MD-SA !
        _MD-SU @ IF _MD-SA @ C@ 91 = ELSE 0 THEN
    WHILE
        _MD-REFERENCE ?DUP 0= IF DROP EXIT THEN
        _MD-SA @ OVER 10 _MD-COUNT-BYTE
        2 PICK _N.LFIRST _N@ OVER + 3 PICK _N.LFIRST _N!
        2 PICK _N.LCOUNT _N@ SWAP - 2 PICK _N.LCOUNT _N!
        _MD-PARA-START +!
    REPEAT DROP ;

\ _MD-SPLIT-TABLE ( i k -- )  Paragraph I's lines from K on are a table.
: _MD-SPLIT-TABLE  ( i k -- )
    DUP 0= IF
        DROP _MD-T-CODE OVER _N.TYPE _N!
        DUP _N.LCOUNT _N@ SWAP _N.KEEP _N! EXIT
    THEN
    _MD-T-CODE 2 PICK _N.PARENT _N@ _MD-NEW-NODE      ( i k t )
    DUP _MD-F-OPEN _NF-
    2 PICK _N.LFIRST _N@ 2 PICK + OVER _N.LFIRST _N!
    2 PICK _N.LCOUNT _N@ 2 PICK - DUP 2 PICK _N.LCOUNT _N!
    SWAP _N.KEEP _N!
    SWAP _N.LCOUNT _N! ;

: _MD-FINALIZE-PARA  ( i -- )
    DUP _MD-TAKE-REFS
    _MD-PARA-TEXT _MD-ALL-WS? IF _MD-UNLINK EXIT THEN
    \ Only a paragraph that took a delimiter row holds a table.
    DUP _MD-F-TABLE _NF? 0= IF DROP EXIT THEN
    _MD-PARA-TABLE DUP 0< IF 2DROP EXIT THEN
    _MD-SPLIT-TABLE ;

: _MD-FINALIZE-NODE  ( i -- )
    DUP _MD-F-OPEN _NF-
    DUP _MD-TYPE
    DUP _MD-T-LIST = IF DROP DUP _MD-FINALIZE-LIST ELSE
    DUP _MD-T-CODE = OVER _MD-T-HTML = OR IF DROP DUP _MD-FINALIZE-CODE ELSE
    _MD-T-PARA = IF DUP _MD-FINALIZE-PARA THEN THEN THEN
    DUP IF _N.PARENT _N@ ELSE DROP -1 THEN _MD-TIP ! ;
' _MD-FINALIZE-NODE IS _MD-FINALIZE

\ =====================================================================
\  Continuing open blocks
\ =====================================================================

: _MD-CONT-QUOTE  ( -- r )
    _MD-INDENTED @ 0= _MD-NN @ _MD-PEEK 62 = AND IF
        _MD-ADVANCE-NEXT-NONSPACE 1 0 _MD-ADVANCE-OFFSET
        _MD-OFFSET @ _MD-PEEK _MD-SPACE-OR-TAB? IF 1 -1 _MD-ADVANCE-OFFSET THEN
        0 EXIT
    THEN
    1 ;

: _MD-CONT-ITEM  ( i -- r )
    _MD-BLANK @ IF
        _N.FIRST _N@ 0= IF 1 EXIT THEN
        _MD-ADVANCE-NEXT-NONSPACE 0 EXIT
    THEN
    DUP _N.MOFF _N@ SWAP _N.PAD _N@ +
    DUP _MD-INDENT @ > IF DROP 1 EXIT THEN
    -1 _MD-ADVANCE-OFFSET 0 ;

\ A closing fence: the fence's character at least as often as the fence,
\ and only spaces or tabs after it.
: _MD-CLOSING-FENCE?  ( i -- flag )
    _MD-NN @ BEGIN DUP _MD-PEEK 2 PICK _N.FCHAR _N@ = WHILE 1+ REPEAT  ( i e )
    DUP _MD-NN @ - DUP 3 < SWAP 3 PICK _N.FLEN _N@ < OR IF 2DROP 0 EXIT THEN
    NIP _MD-REST _MD-ALL-WS? ;

: _MD-CONT-CODE  ( i -- r )
    DUP _MD-F-FENCED _NF? IF
        _MD-INDENT @ 4 < IF
            _MD-NN @ _MD-PEEK OVER _N.FCHAR _N@ = IF
                DUP _MD-CLOSING-FENCE? IF _MD-FINALIZE 2 EXIT THEN
            THEN
        THEN
        \ Skip the spaces the opening fence was indented by.
        _N.FOFF _N@
        BEGIN DUP 0> _MD-OFFSET @ _MD-PEEK _MD-SPACE-OR-TAB? AND WHILE
            1 -1 _MD-ADVANCE-OFFSET 1-
        REPEAT DROP 0 EXIT
    THEN
    DROP
    _MD-INDENT @ 3 > IF 4 -1 _MD-ADVANCE-OFFSET 0 EXIT THEN
    _MD-BLANK @ IF _MD-ADVANCE-NEXT-NONSPACE 0 EXIT THEN
    1 ;

: _MD-CONT-HTML  ( i -- r )
    _MD-BLANK @ IF _N.HTYPE _N@ DUP 6 = SWAP 7 = OR IF 1 ELSE 0 THEN EXIT THEN
    DROP 0 ;

\ _MD-CONTINUE ( i -- r )
\   Does open block I go on in this line?  0 yes, 1 no, 2 the line is done.
: _MD-CONTINUE  ( i -- r )
    DUP _MD-TYPE
    DUP _MD-T-QUOTE = IF 2DROP _MD-CONT-QUOTE EXIT THEN
    DUP _MD-T-ITEM = IF DROP _MD-CONT-ITEM EXIT THEN
    DUP _MD-T-CODE = IF DROP _MD-CONT-CODE EXIT THEN
    DUP _MD-T-HTML = IF DROP _MD-CONT-HTML EXIT THEN
    DUP _MD-T-PARA = IF 2DROP _MD-BLANK @ IF 1 ELSE 0 THEN EXIT THEN
    DUP _MD-T-HEADING = SWAP _MD-T-RULE = OR NIP IF 1 ELSE 0 THEN ;

\ =====================================================================
\  HTML
\ =====================================================================

VARIABLE _MHT-A
VARIABLE _MHT-U
VARIABLE _MHT-I

: _MHT@   ( -- c | -1 )  _MHT-I @ DUP _MHT-U @ < IF _MHT-A @ + C@ ELSE DROP -1 THEN ;
: _MHT+   ( -- )  1 _MHT-I +! ;
: _MHT-SET  ( a u -- )  _MHT-U ! _MHT-A ! 0 _MHT-I ! ;
: _MHT-WS  ( -- n )  0 BEGIN _MHT@ _MD-WS? WHILE 1+ _MHT+ REPEAT ;

: _MHT-TAGNAME  ( -- ok? )
    _MHT@ _MD-ALPHA? 0= IF 0 EXIT THEN _MHT+
    BEGIN _MHT@ DUP _MD-ALNUM? SWAP 45 = OR WHILE _MHT+ REPEAT -1 ;

: _MHT-ATTRNAME  ( -- ok? )
    _MHT@ DUP _MD-ALPHA? OVER 95 = OR SWAP 58 = OR 0= IF 0 EXIT THEN _MHT+
    BEGIN
        _MHT@ DUP _MD-ALNUM? OVER 58 = OR OVER 46 = OR OVER 95 = OR SWAP 45 = OR
    WHILE _MHT+ REPEAT -1 ;

: _MD-UNQUOTED?  ( c -- flag )
    DUP 32 > OVER 34 <> AND OVER 39 <> AND OVER 61 <> AND OVER 60 <> AND
    OVER 62 <> AND SWAP 96 <> AND ;

: _MHT-VALUE  ( -- ok? )
    _MHT@ DUP 39 = OVER 34 = OR IF
        _MHT+
        BEGIN _MHT@ DUP -1 = IF 2DROP 0 EXIT THEN OVER <> WHILE _MHT+ REPEAT
        DROP _MHT+ -1 EXIT
    THEN
    DROP 0 BEGIN _MHT@ _MD-UNQUOTED? WHILE 1+ _MHT+ REPEAT 0<> ;

\ _MD-MATCH-OPEN-TAG ( a u -- len )  An open tag at A, or 0.
: _MD-MATCH-OPEN-TAG  ( a u -- len )
    _MHT-SET
    _MHT@ 60 <> IF 0 EXIT THEN _MHT+
    _MHT-TAGNAME 0= IF 0 EXIT THEN
    BEGIN
        _MHT-I @
        _MHT-WS 0> IF _MHT-ATTRNAME ELSE 0 THEN
        IF
            DROP
            _MHT-I @ >R
            _MHT-WS DROP
            _MHT@ 61 = IF
                _MHT+ _MHT-WS DROP _MHT-VALUE 0= IF R@ _MHT-I ! THEN
            ELSE R@ _MHT-I ! THEN
            R> DROP 0
        ELSE _MHT-I ! -1 THEN
    UNTIL
    _MHT-WS DROP
    _MHT@ 47 = IF _MHT+ THEN
    _MHT@ 62 <> IF 0 EXIT THEN _MHT+ _MHT-I @ ;

\ _MD-MATCH-CLOSE-TAG ( a u -- len )  A closing tag at A, or 0.
: _MD-MATCH-CLOSE-TAG  ( a u -- len )
    _MHT-SET
    _MHT@ 60 <> IF 0 EXIT THEN _MHT+
    _MHT@ 47 <> IF 0 EXIT THEN _MHT+
    _MHT-TAGNAME 0= IF 0 EXIT THEN
    _MHT-WS DROP _MHT@ 62 <> IF 0 EXIT THEN _MHT+ _MHT-I @ ;

\ A comment: <!---->, or <!-- then text that starts with neither > nor
\ ->, holds no --, and ends where --> follows.
: _MD-MATCH-COMMENT  ( a u -- len )
    4 /STRING
    2DUP S" -->" _MD-PREFIX? IF 2DROP 7 EXIT THEN
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 62 = IF 2DROP 0 EXIT THEN
    2DUP S" ->" _MD-PREFIX? IF 2DROP 0 EXIT THEN
    2DUP S" --" _MD-FIND
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    DUP 2 + 2 PICK < IF
        2 PICK OVER + 2 + C@ 62 = IF NIP NIP 7 + EXIT THEN
    THEN
    DROP 2DROP 0 ;

\ A declaration: <!, capital letters, whitespace, and text to >.
: _MD-MATCH-DECLARATION  ( a u -- len )
    _MHT-SET 2 _MHT-I !
    0 BEGIN _MHT@ 65 91 WITHIN WHILE 1+ _MHT+ REPEAT
    0= IF 0 EXIT THEN
    _MHT-WS 0= IF 0 EXIT THEN
    BEGIN _MHT@ DUP -1 <> SWAP 62 <> AND WHILE _MHT+ REPEAT
    _MHT@ 62 <> IF 0 EXIT THEN _MHT+ _MHT-I @ ;

\ _MD-MATCH-HTML-TAG ( a u -- len )
\   Raw HTML at A, which starts with <: an open or closing tag, a comment,
\   a processing instruction, a declaration or a CDATA section, or 0.
: _MD-MATCH-HTML-TAG  ( a u -- len )
    2DUP _MD-MATCH-OPEN-TAG ?DUP IF NIP NIP EXIT THEN
    2DUP _MD-MATCH-CLOSE-TAG ?DUP IF NIP NIP EXIT THEN
    2DUP S" <!--" _MD-PREFIX? IF _MD-MATCH-COMMENT EXIT THEN
    2DUP S" <?" _MD-PREFIX? IF
        2 /STRING S" ?>" _MD-FIND DUP 0< IF DROP 0 ELSE 4 + THEN EXIT
    THEN
    2DUP S" <![CDATA[" _MD-PREFIX? IF
        9 /STRING S" ]]>" _MD-FIND DUP 0< IF DROP 0 ELSE 12 + THEN EXIT
    THEN
    2DUP S" <!" _MD-PREFIX? IF _MD-MATCH-DECLARATION EXIT THEN
    2DROP 0 ;

\ The block names an HTML block of type 6 opens with.
: _MD-BLOCK-NAMES-1  ( -- a u )
    S" address article aside base basefont blockquote body caption center col colgroup dd details dialog dir div dl dt fieldset figcaption figure footer form frame frameset" ;
: _MD-BLOCK-NAMES-2  ( -- a u )
    S" h1 h2 h3 h4 h5 h6 head header hr html iframe legend li link main menu menuitem nav noframes ol optgroup option p param section source summary table tbody td tfoot th thead title tr track ul" ;

\ Is the name, in any case, one of the lowercase names in the list?
: _MD-NAME=  ( a u b v -- flag )
    ROT OVER <> IF DROP 2DROP 0 EXIT THEN
    0 ?DO OVER I + C@ _MD-LOWER OVER I + C@ <> IF 2DROP UNLOOP 0 EXIT THEN LOOP
    2DROP -1 ;

: _MD-IN-NAMES?  ( a u list-a list-u -- flag )
    BEGIN DUP 0> WHILE
        32 _MD-SPLIT 2>R
        2OVER 2SWAP _MD-NAME= IF 2DROP 2R> 2DROP -1 EXIT THEN
        2R>
    REPEAT
    2DROP 2DROP 0 ;

: _MD-BLOCK-NAME?  ( a u -- flag )
    2DUP _MD-BLOCK-NAMES-1 _MD-IN-NAMES? IF 2DROP -1 EXIT THEN
    _MD-BLOCK-NAMES-2 _MD-IN-NAMES? ;

: _MD-NAME-RUN  ( a u -- n )
    TUCK 0 ?DO DUP I + C@ _MD-ALNUM? 0= IF 2DROP I UNLOOP EXIT THEN LOOP DROP ;

\ _MD-HTML-START ( a u -- type | 0 )
\   The kind of HTML block, 1 to 6, the line's text at A starts.
: _MD-HTML-START  ( a u -- type | 0 )
    _MHT-SET
    _MHT-A @ _MHT-U @ S" <!--" _MD-PREFIX? IF 2 EXIT THEN
    _MHT-A @ _MHT-U @ S" <?" _MD-PREFIX? IF 3 EXIT THEN
    _MHT-A @ _MHT-U @ S" <![CDATA[" _MD-PREFIX? IF 5 EXIT THEN
    _MHT-A @ _MHT-U @ S" <!" _MD-PREFIX? IF
        _MHT-U @ 2 > IF _MHT-A @ 2 + C@ 65 91 WITHIN IF 4 EXIT THEN THEN
    THEN
    \ 1: <script, <pre, <textarea or <style, then whitespace, > or the end
    _MHT-A @ 1+ _MHT-U @ 1- _MD-NAME-RUN
    ?DUP IF
        _MHT-A @ 1+ OVER S" script pre textarea style" _MD-IN-NAMES? IF
            1+ _MHT-I ! _MHT@ DUP -1 = OVER 62 = OR SWAP _MD-WS? OR IF 1 EXIT THEN
        ELSE DROP THEN
    THEN
    \ 6: < or </, a block name, then whitespace, >, /> or the end
    _MHT-U @ 1 > IF _MHT-A @ 1+ C@ 47 = IF 2 ELSE 1 THEN ELSE 1 THEN
    _MHT-A @ OVER + _MHT-U @ 2 PICK - 0 MAX _MD-NAME-RUN
    DUP 0= IF 2DROP 0 EXIT THEN
    _MHT-A @ 2 PICK + OVER _MD-BLOCK-NAME? 0= IF 2DROP 0 EXIT THEN
    + _MHT-I !
    _MHT@ DUP -1 = OVER 62 = OR SWAP _MD-WS? OR IF 6 EXIT THEN
    _MHT@ 47 = IF _MHT+ _MHT@ 62 = IF 6 EXIT THEN THEN
    0 ;

\ Does the line hold the end of an HTML block of type 1 to 5?
: _MD-HTML-CLOSES?  ( a u type -- flag )
    DUP 1 = IF
        DROP
        2DUP S" </script>" _MD-CONTAINS-CI? IF 2DROP -1 EXIT THEN
        2DUP S" </pre>" _MD-CONTAINS-CI? IF 2DROP -1 EXIT THEN
        2DUP S" </textarea>" _MD-CONTAINS-CI? IF 2DROP -1 EXIT THEN
        S" </style>" _MD-CONTAINS-CI? EXIT
    THEN
    DUP 2 = IF DROP S" -->" _MD-FIND 0< 0= EXIT THEN
    DUP 3 = IF DROP S" ?>" _MD-FIND 0< 0= EXIT THEN
    DUP 4 = IF DROP S" >" _MD-FIND 0< 0= EXIT THEN
    5 = IF S" ]]>" _MD-FIND 0< 0= EXIT THEN
    2DROP 0 ;

\ =====================================================================
\  Starting blocks
\ =====================================================================

: _MD-START-QUOTE  ( -- r )
    _MD-INDENTED @ IF 0 EXIT THEN
    _MD-NN @ _MD-PEEK 62 <> IF 0 EXIT THEN
    _MD-ADVANCE-NEXT-NONSPACE 1 0 _MD-ADVANCE-OFFSET
    _MD-OFFSET @ _MD-PEEK _MD-SPACE-OR-TAB? IF 1 -1 _MD-ADVANCE-OFFSET THEN
    _MD-CLOSE-UNMATCHED _MD-T-QUOTE _MD-ADD-CHILD DROP 1 ;

VARIABLE _MAT-K
VARIABLE _MAT-S
VARIABLE _MAT-E

\ Where an ATX heading's text ends: before a closing run of # that a space
\ or tab precedes, or at nothing when the text is only #.
: _MD-ATX-END  ( start end -- end' )
    _MAT-E ! _MAT-S !
    _MAT-E @ BEGIN DUP _MAT-S @ > IF DUP 1- _MD-PEEK _MD-SPACE-OR-TAB? ELSE 0 THEN WHILE 1- REPEAT
    DUP BEGIN DUP _MAT-S @ > IF DUP 1- _MD-PEEK 35 = ELSE 0 THEN WHILE 1- REPEAT   ( e h )
    2DUP = IF 2DROP _MAT-E @ EXIT THEN
    DUP _MAT-S @ = IF 2DROP _MAT-S @ EXIT THEN
    DUP 1- _MD-PEEK _MD-SPACE-OR-TAB? 0= IF 2DROP _MAT-E @ EXIT THEN
    NIP BEGIN DUP _MAT-S @ > IF DUP 1- _MD-PEEK _MD-SPACE-OR-TAB? ELSE 0 THEN WHILE 1- REPEAT ;

: _MD-START-ATX  ( -- r )
    _MD-INDENTED @ IF 0 EXIT THEN
    0 BEGIN DUP _MD-NN @ + _MD-PEEK 35 = WHILE 1+ REPEAT
    DUP 1 7 WITHIN 0= IF DROP 0 EXIT THEN
    DUP _MD-NN @ + _MD-PEEK DUP -1 = SWAP _MD-SPACE-OR-TAB? OR 0= IF DROP 0 EXIT THEN
    _MAT-K !
    _MD-NN @ _MAT-K @ + BEGIN DUP _MD-PEEK _MD-SPACE-OR-TAB? WHILE 1+ REPEAT _MD-NN @ -
    _MD-ADVANCE-NEXT-NONSPACE 0 _MD-ADVANCE-OFFSET
    _MD-CLOSE-UNMATCHED
    _MD-T-HEADING _MD-ADD-CHILD
    _MAT-K @ OVER _N.LEVEL _N!
    _MD-SPANS OVER _N.LFIRST _N! 1 SWAP _N.LCOUNT _N!
    _MD-OFFSET @ DUP _MD-L-U @ _MD-ATX-END OVER -     ( start len )
    SWAP _MD-L-OFF @ + SWAP 0 _MD-ADD-SPAN
    _MD-L-U @ _MD-OFFSET ! 0 _MD-PARTIAL ! 2 ;

: _MD-START-FENCE  ( -- r )
    _MD-INDENTED @ IF 0 EXIT THEN
    _MD-NN @ _MD-PEEK DUP 96 = OVER 126 = OR 0= IF DROP 0 EXIT THEN
    0 BEGIN 2DUP _MD-NN @ + _MD-PEEK = WHILE 1+ REPEAT
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER 96 = IF
        \ A backtick fence's info string holds no backtick.
        _MD-L-U @ OVER _MD-NN @ + ?DO
            _MD-L-A @ I + C@ 96 = IF 2DROP UNLOOP 0 EXIT THEN
        LOOP
    THEN
    _MD-CLOSE-UNMATCHED
    _MD-T-CODE _MD-ADD-CHILD
    DUP _MD-F-FENCED _NF+
    _MD-INDENT @ OVER _N.FOFF _N!
    TUCK _N.FLEN _N! TUCK _N.FCHAR _N!
    _MD-ADVANCE-NEXT-NONSPACE _N.FLEN _N@ 0 _MD-ADVANCE-OFFSET 2 ;

: _MD-START-HTML  ( -- r )
    _MD-INDENTED @ IF 0 EXIT THEN
    _MD-NN @ _MD-PEEK 60 <> IF 0 EXIT THEN
    _MD-NN @ _MD-REST _MD-HTML-START
    ?DUP 0= IF
        \ 7: one whole open or closing tag on the line, which may not
        \ interrupt a paragraph, nor continue one lazily.
        _MD-CONT @ _MD-TYPE _MD-T-PARA = IF 0 EXIT THEN
        _MD-ALL-CLOSED @ 0= _MD-BLANK @ 0= AND _MD-TIP @ _MD-TYPE _MD-T-PARA = AND IF
            0 EXIT
        THEN
        _MD-NN @ _MD-REST 2DUP _MD-MATCH-OPEN-TAG ?DUP 0= IF 2DUP _MD-MATCH-CLOSE-TAG THEN
        ?DUP 0= IF 2DROP 0 EXIT THEN
        /STRING _MD-ALL-WS? 0= IF 0 EXIT THEN
        7
    THEN
    _MD-CLOSE-UNMATCHED
    _MD-T-HTML _MD-ADD-CHILD _N.HTYPE _N! 2 ;

: _MD-START-SETEXT  ( -- r )
    _MD-INDENTED @ IF 0 EXIT THEN
    _MD-CONT @ _MD-TYPE _MD-T-PARA <> IF 0 EXIT THEN
    _MD-NN @ _MD-PEEK DUP 61 = OVER 45 = OR 0= IF DROP 0 EXIT THEN
    _MD-NN @ BEGIN 2DUP _MD-PEEK = WHILE 1+ REPEAT
    BEGIN DUP _MD-PEEK _MD-SPACE-OR-TAB? WHILE 1+ REPEAT
    _MD-L-U @ < IF DROP 0 EXIT THEN
    _MD-CLOSE-UNMATCHED
    _MD-CONT @ _MD-TAKE-REFS
    _MD-PARA-TEXT NIP 0= IF DROP 0 EXIT THEN
    \ A table's delimiter row is no underline.
    _MD-CONT @ _MD-F-TABLE _NF? IF DROP 0 EXIT THEN
    61 = IF 1 ELSE 2 THEN _MD-CONT @ _N.LEVEL _N!
    _MD-T-HEADING _MD-CONT @ _N.TYPE _N!
    _MD-CONT @ _MD-TIP !
    _MD-L-U @ _MD-OFFSET ! 0 _MD-PARTIAL ! 2 ;

: _MD-START-RULE  ( -- r )
    _MD-INDENTED @ IF 0 EXIT THEN
    _MD-NN @ _MD-PEEK DUP 42 = OVER 95 = OR OVER 45 = OR 0= IF DROP 0 EXIT THEN
    0 _MD-L-U @ _MD-NN @ ?DO
        _MD-L-A @ I + C@
        DUP 3 PICK = IF DROP 1+ ELSE
            _MD-SPACE-OR-TAB? 0= IF 2DROP UNLOOP 0 EXIT THEN
        THEN
    LOOP
    NIP 3 < IF 0 EXIT THEN
    _MD-CLOSE-UNMATCHED _MD-T-RULE _MD-ADD-CHILD DROP
    _MD-L-U @ _MD-OFFSET ! 0 _MD-PARTIAL ! 2 ;

VARIABLE _MLM-ORD       \ a numbered item
VARIABLE _MLM-CHAR      \ its bullet, or its number's delimiter
VARIABLE _MLM-START
VARIABLE _MLM-LEN       \ the marker's bytes
VARIABLE _MLM-MOFF      \ the marker's indentation
VARIABLE _MLM-PAD

\ _MD-LIST-MARKER ( -- ok? )
\   A list item's marker at the line's next text, and the spaces after it.
\   Moves past them when it finds one.
: _MD-LIST-MARKER  ( -- ok? )
    _MD-INDENT @ 3 > IF 0 EXIT THEN
    _MD-INDENT @ _MLM-MOFF !
    _MD-NN @ _MD-PEEK
    DUP 42 = OVER 43 = OR OVER 45 = OR IF
        _MLM-CHAR ! 0 _MLM-ORD ! 1 _MLM-LEN ! 0 _MLM-START !
    ELSE
        DROP
        0 0 BEGIN
            DUP _MD-NN @ + _MD-PEEK DUP _MD-DIGIT?
        WHILE
            48 - ROT 10 * + SWAP 1+
        REPEAT
        OVER 1 10 WITHIN 0= IF DROP 2DROP 0 EXIT THEN
        DUP 46 = OVER 41 = OR 0= IF DROP 2DROP 0 EXIT THEN
        _MLM-CHAR ! 1+ _MLM-LEN ! _MLM-START ! -1 _MLM-ORD !
        \ Only a list numbered from 1 interrupts a paragraph.
        _MD-CONT @ _MD-PLAIN-PARA? _MLM-START @ 1 <> AND IF 0 EXIT THEN
    THEN
    \ A space, a tab or the line's end follows the marker.
    _MD-NN @ _MLM-LEN @ + _MD-PEEK DUP -1 <> SWAP _MD-SPACE-OR-TAB? 0= AND IF 0 EXIT THEN
    \ An item that interrupts a paragraph has text on its first line.
    _MD-CONT @ _MD-PLAIN-PARA? IF
        _MD-NN @ _MLM-LEN @ + _MD-REST _MD-ALL-WS? IF 0 EXIT THEN
    THEN
    _MD-ADVANCE-NEXT-NONSPACE _MLM-LEN @ -1 _MD-ADVANCE-OFFSET
    _MD-COLUMN @ _MD-OFFSET @
    BEGIN
        1 -1 _MD-ADVANCE-OFFSET
        _MD-COLUMN @ 2 PICK - 5 < _MD-OFFSET @ _MD-PEEK _MD-SPACE-OR-TAB? AND
    0= UNTIL
    _MD-OFFSET @ _MD-PEEK -1 =
    _MD-COLUMN @ 3 PICK -
    DUP 5 < OVER 0> AND ROT 0= AND IF
        _MLM-LEN @ + _MLM-PAD ! 2DROP
    ELSE
        DROP _MLM-LEN @ 1+ _MLM-PAD !
        _MD-OFFSET ! _MD-COLUMN !
        _MD-OFFSET @ _MD-PEEK _MD-SPACE-OR-TAB? IF 1 -1 _MD-ADVANCE-OFFSET THEN
    THEN
    -1 ;

: _MD-SET-LIST-DATA  ( i -- )
    _MLM-ORD @ IF DUP _MD-F-ORDERED _NF+ THEN
    _MLM-CHAR @ OVER _N.MCHAR _N!
    _MLM-START @ OVER _N.LSTART _N!
    _MLM-MOFF @ OVER _N.MOFF _N!
    _MLM-PAD @ SWAP _N.PAD _N! ;

: _MD-LISTS-MATCH?  ( list -- flag )
    DUP _MD-F-ORDERED _NF? _MLM-ORD @ 0<> =
    SWAP _N.MCHAR _N@ _MLM-CHAR @ = AND ;

: _MD-START-ITEM  ( -- r )
    _MD-INDENTED @ IF _MD-CONT @ _MD-TYPE _MD-T-LIST <> IF 0 EXIT THEN THEN
    _MD-LIST-MARKER 0= IF 0 EXIT THEN
    _MD-CLOSE-UNMATCHED
    _MD-TIP @ _MD-TYPE _MD-T-LIST <> IF -1 ELSE _MD-TIP @ _MD-LISTS-MATCH? 0= THEN IF
        _MD-T-LIST _MD-ADD-CHILD
        DUP _MD-F-TIGHT _NF+ _MD-SET-LIST-DATA
    THEN
    _MD-T-ITEM _MD-ADD-CHILD
    DUP _MD-SET-LIST-DATA
    DUP _N.PARENT _N@ _N.COUNT _N@ OVER _N.COUNT _N!
    _N.PARENT _N@ DUP _N.COUNT _N@ 1+ SWAP _N.COUNT _N!
    1 ;

: _MD-START-INDENTED  ( -- r )
    _MD-INDENTED @ 0= IF 0 EXIT THEN
    _MD-TIP @ _MD-PLAIN-PARA? IF 0 EXIT THEN
    _MD-BLANK @ IF 0 EXIT THEN
    4 -1 _MD-ADVANCE-OFFSET _MD-CLOSE-UNMATCHED _MD-T-CODE _MD-ADD-CHILD DROP 2 ;

\ _MD-TRY-STARTS ( -- r )
\   0: nothing starts, 1: a container starts, 2: a leaf starts.  The starts
\   are tried in CommonMark's order; each one's first character is
\   checked first, so only those that could start are tried.
: _MD-TRY-STARTS  ( -- r )
    _MD-INDENTED @ IF
        _MD-START-ITEM ?DUP IF EXIT THEN
        _MD-START-INDENTED EXIT
    THEN
    _MD-NN @ _MD-PEEK
    DUP 62 = IF DROP _MD-START-QUOTE EXIT THEN
    DUP 35 = IF DROP _MD-START-ATX EXIT THEN
    DUP 96 = OVER 126 = OR IF DROP _MD-START-FENCE EXIT THEN
    DUP 60 = IF DROP _MD-START-HTML EXIT THEN
    DUP 61 = IF DROP _MD-START-SETEXT EXIT THEN
    DUP 45 = IF DROP
        _MD-START-SETEXT ?DUP IF EXIT THEN
        _MD-START-RULE ?DUP IF EXIT THEN
        _MD-START-ITEM EXIT
    THEN
    DUP 42 = IF DROP
        _MD-START-RULE ?DUP IF EXIT THEN
        _MD-START-ITEM EXIT
    THEN
    DUP 95 = IF DROP _MD-START-RULE EXIT THEN
    DROP _MD-START-ITEM ;

\ The characters a block may start with: # ` ~ * + _ = < > - and digits.
CREATE _MD-STARTERS 256 ALLOT  _MD-STARTERS 256 0 FILL
: _MD-STARTER!  ( c -- )  _MD-STARTERS + 1 SWAP C! ;
35 _MD-STARTER!  96 _MD-STARTER!  126 _MD-STARTER!  42 _MD-STARTER!
43 _MD-STARTER!  95 _MD-STARTER!  61 _MD-STARTER!  60 _MD-STARTER!
62 _MD-STARTER!  45 _MD-STARTER!
: _MD-STARTER-DIGITS  ( -- )  58 48 DO I _MD-STARTER! LOOP ;
_MD-STARTER-DIGITS

: _MD-MAYBE-SPECIAL?  ( c -- flag )
    DUP 0< IF DROP 0 EXIT THEN _MD-STARTERS + C@ 0<> ;

\ =====================================================================
\  A line
\ =====================================================================

\ Match the open blocks against the line; true when the line is done.
: _MD-MATCH-OPEN  ( -- done? )
    BEGIN
        _MD-CONT @ _N.LAST _N@
        DUP IF DUP _MD-F-OPEN _NF? ELSE 0 THEN
    WHILE
        _MD-CONT !
        _MD-FIND-NEXT-NONSPACE
        _MD-CONT @ _MD-CONTINUE
        DUP 2 = IF DROP -1 EXIT THEN
        IF _MD-CONT @ _N.PARENT _N@ _MD-CONT ! 0 EXIT THEN
    REPEAT
    DROP 0 ;

\ Start new blocks in the last matched container.
: _MD-OPEN-NEW  ( -- )
    \ A table's delimiter row continues the paragraph its header ends.
    _MD-CONT @ _MD-TYPE _MD-T-PARA = IF
        _MD-FIND-NEXT-NONSPACE
        _MD-INDENTED @ 0= _MD-NN @ _MD-PEEK _MD-ROW-START? AND IF
            _MD-PARA-LAST _MD-NN @ _MD-REST _MD-TABLE-PAIR? IF
                _MD-CONT @ _MD-F-TABLE _NF+
                _MD-ADVANCE-NEXT-NONSPACE EXIT
            THEN
        THEN
    THEN
    BEGIN
        _MD-FIND-NEXT-NONSPACE
        _MD-INDENTED @ 0= _MD-NN @ _MD-PEEK _MD-MAYBE-SPECIAL? 0= AND IF
            _MD-ADVANCE-NEXT-NONSPACE EXIT
        THEN
        _MD-TRY-STARTS
        DUP 0= IF DROP _MD-ADVANCE-NEXT-NONSPACE EXIT THEN
        _MD-TIP @ _MD-CONT !
        2 = IF EXIT THEN
    AGAIN ;

\ Set or clear LASTBLANK on I and every block around it.
: _MD-PROPAGATE-BLANK  ( flag i -- )
    BEGIN
        2DUP SWAP IF _MD-F-LASTBLANK _NF+ ELSE _MD-F-LASTBLANK _NF- THEN
        DUP 0= IF 2DROP EXIT THEN
        _N.PARENT _N@
    AGAIN ;

: _MD-NEW-PARA  ( -- )
    _MD-T-PARA _MD-ADD-CHILD DROP
    0 _MD-PARA _MB.N ! 0 _MD-PARA-START ! ;

\ _MD-INCORPORATE ( -- )  Add the line to the document.
: _MD-INCORPORATE  ( -- )
    _MD-TIP @ _MD-OLDTIP !
    0 _MD-OFFSET ! 0 _MD-COLUMN ! 0 _MD-BLANK ! 0 _MD-PARTIAL !
    1 _MD-LINE-NO +!
    0 _MD-CONT !
    _MD-MATCH-OPEN IF EXIT THEN
    _MD-CONT @ _MD-OLDTIP @ = _MD-ALL-CLOSED !
    _MD-CONT @ _MD-LAST-MATCHED !
    _MD-CONT @ _MD-TYPE DUP _MD-T-PARA <> SWAP _MD-ACCEPTS-LINES? AND 0= IF
        _MD-OPEN-NEW
    THEN
    \ A paragraph goes on lazily.
    _MD-ALL-CLOSED @ 0= _MD-BLANK @ 0= AND _MD-TIP @ _MD-TYPE _MD-T-PARA = AND IF
        _MD-ADD-LINE EXIT
    THEN
    _MD-CLOSE-UNMATCHED
    _MD-BLANK @ IF
        _MD-CONT @ _N.LAST _N@ ?DUP IF _MD-F-LASTBLANK _NF+ THEN
    THEN
    \ A blank line counts for the blocks around it, but not in a quote,
    \ in fenced code, or right after an empty item's marker.
    _MD-CONT @ _MD-TYPE
    _MD-BLANK @
    OVER _MD-T-QUOTE <> AND
    OVER _MD-T-CODE = _MD-CONT @ _MD-F-FENCED _NF? AND 0= AND
    OVER _MD-T-ITEM = _MD-CONT @ _N.FIRST _N@ 0= AND
        _MD-CONT @ _N.START _N@ _MD-LINE-NO @ = AND 0= AND
    _MD-CONT @ _MD-PROPAGATE-BLANK
    DUP _MD-ACCEPTS-LINES? IF
        _MD-ADD-LINE
        _MD-T-HTML = IF
            _MD-CONT @ _N.HTYPE _N@ DUP 1 6 WITHIN IF
                _MD-OFFSET @ _MD-REST ROT _MD-HTML-CLOSES? IF
                    _MD-CONT @ _MD-FINALIZE
                THEN
            ELSE DROP THEN
        THEN
        EXIT
    THEN
    DROP
    _MD-OFFSET @ _MD-L-U @ < _MD-BLANK @ 0= AND IF
        _MD-NEW-PARA _MD-ADVANCE-NEXT-NONSPACE _MD-ADD-LINE
    THEN ;

\ =====================================================================
\  The document's blocks
\ =====================================================================

VARIABLE _ME-SERIAL      \ the blocks added so far

\ I and the blocks around it are the latest block's ancestors.
: _MD-MARK  ( i -- )
    BEGIN _ME-SERIAL @ OVER _N.MARK _N! DUP WHILE _N.PARENT _N@ REPEAT DROP ;

\ The nearest block around I, or I, that holds the block before.
: _MD-COMMON  ( i -- a )
    BEGIN DUP _N.MARK _N@ _ME-SERIAL @ <> WHILE _N.PARENT _N@ REPEAT ;

\ The quotes and items among A and the blocks around it.
: _MD-SHARED  ( a -- n )
    0 SWAP
    BEGIN
        DUP _MD-TYPE DUP _MD-T-QUOTE = SWAP _MD-T-ITEM = OR IF SWAP 1+ SWAP THEN
        DUP
    WHILE _N.PARENT _N@ REPEAT
    DROP ;

\ No blank row between blocks in a tight list, one elsewhere.
: _MD-GAP  ( a -- rows )
    DUP _MD-TYPE _MD-T-ITEM = IF _N.PARENT _N@ THEN
    DUP _MD-TYPE _MD-T-LIST = IF _MD-F-TIGHT _NF? IF 0 ELSE 1 THEN EXIT THEN
    DROP 1 ;

\ The quotes and items around I, and I when it is an item, innermost
\ first.
: _MD-COLLECT  ( i -- )
    0 _MD-CHAIN _MB.N !
    BEGIN DUP WHILE
        DUP _MD-TYPE DUP _MD-T-QUOTE = SWAP _MD-T-ITEM = OR IF
            DUP 8 _MD-CHAIN _MD-ROOM !
        THEN
        _N.PARENT _N@
    REPEAT DROP ;

VARIABLE _MAC-I
VARIABLE _MAC-L

: _MD-ADD-CONTAINER-NODE  ( i -- )
    DUP _MAC-I !
    _MD-TYPE _MD-T-QUOTE = IF
        DOC-C-QUOTE 2 0 0
    ELSE
        _MAC-I @ _N.PARENT _N@ _MAC-L !
        _MAC-L @ _MD-F-ORDERED _NF? IF
            DOC-C-NUMBERED
            _MAC-L @ _N.LSTART _N@ _MAC-L @ _N.COUNT _N@ + 1- _MD-DIGITS 2 +
            _MAC-L @ _N.LSTART _N@ _MAC-I @ _N.COUNT _N@ +
        ELSE
            DOC-C-BULLET 2 0
        THEN
        _MAC-I @ _MD-F-STARTED _NF? 0=
        _MAC-I @ _MD-F-STARTED _NF+
    THEN
    _MD-D @ DOC-ADD-CONTAINER 0= IF _MD-E-MEMORY THROW THEN ;

: _MD-ADD-CONTAINERS  ( -- )
    _MD-CHAIN _MB.N @
    BEGIN DUP 0> WHILE
        8 - DUP _MD-CHAIN _MB.A @ + @ _MD-ADD-CONTAINER-NODE
    REPEAT DROP ;

: _MD-EMIT-LEAF  ( i kind level loc-a loc-b -- )
    _MD-D @ DOC-ADD-BLOCK DUP 0= IF _MD-E-MEMORY THROW THEN
    _ME-SERIAL @ IF
        OVER _MD-COMMON DUP _MD-GAP DUP 3 PICK BLK-ROWS-BEFORE!
        IF _MD-SHARED OVER BLK-INSIDE! ELSE DROP THEN
    THEN
    DROP
    1 _ME-SERIAL +!
    DUP _MD-COLLECT _MD-ADD-CONTAINERS
    _MD-MARK ;

: _MD-LOC  ( i -- first count )  DUP _N.LFIRST _N@ SWAP _N.LCOUNT _N@ ;

: _MD-VISIT  ( i -- )
    DUP _MD-TYPE
    DUP _MD-T-PARA = IF DROP DUP DOC-B-PARAGRAPH 0 ROT _MD-LOC _MD-EMIT-LEAF EXIT THEN
    DUP _MD-T-HEADING = IF
        DROP DUP DOC-B-HEADING OVER _N.LEVEL _N@ ROT _MD-LOC _MD-EMIT-LEAF EXIT
    THEN
    DUP _MD-T-CODE = OVER _MD-T-HTML = OR IF
        DROP DUP DOC-B-CODE 0 ROT _MD-LOC _MD-EMIT-LEAF EXIT
    THEN
    DUP _MD-T-RULE = IF DROP DOC-B-RULE 0 0 0 _MD-EMIT-LEAF EXIT THEN
    _MD-T-ITEM = IF
        \ An empty item shows its mark beside an empty paragraph.
        DUP _N.FIRST _N@ 0= IF DOC-B-PARAGRAPH 0 0 0 _MD-EMIT-LEAF EXIT THEN
    THEN
    DROP ;

: _MD-CONTAINER?  ( i -- flag )
    _MD-TYPE DUP _MD-T-QUOTE = OVER _MD-T-LIST = OR SWAP _MD-T-ITEM = OR ;

\ Add every block, in the order the document shows them.
: _MD-EMIT-ALL  ( -- )
    0 _ME-SERIAL !
    0 _N.FIRST _N@
    BEGIN DUP WHILE
        DUP _MD-VISIT
        DUP _MD-CONTAINER? OVER _N.FIRST _N@ 0<> AND IF
            _N.FIRST _N@
        ELSE
            BEGIN DUP IF DUP _N.NEXT _N@ 0= ELSE 0 THEN WHILE _N.PARENT _N@ REPEAT
            DUP IF _N.NEXT _N@ THEN
        THEN
    REPEAT DROP ;

\ =====================================================================
\  The structure pass
\ =====================================================================

: _MD-PARSE  ( -- )
    _MD-CHUNK-BYTES _MD-CHUNK _MD-GROW
    _MD-D @ DOC-SOURCE@ MEDSRC-SIZE@ _MD-FSIZE !
    0 _MD-FPOS ! 0 _MD-CPOS ! 0 _MD-CLEN ! 0 _MD-CR ! 0 _MD-LINE-NO !
    _MD-T-DOC 0 _MD-NEW-NODE _MD-TIP !
    BEGIN _MD-NEXT-LINE WHILE _MD-INCORPORATE REPEAT
    BEGIN _MD-TIP @ 0< 0= WHILE _MD-TIP @ _MD-FINALIZE REPEAT
    _MD-EMIT-ALL ;

: _MD-STATUS  ( throw-code -- status )
    DUP 0= IF EXIT THEN
    DUP _MD-E-MEMORY = IF DROP DOC-S-MEMORY EXIT THEN
    DUP _MD-E-READ = IF DROP DOC-S-READ EXIT THEN
    THROW ;

: _MD-STRUCTURE-XT  ( doc -- status )
    _MD-D ! 0 _MD-S !
    _MDS-SIZE _MD-D @ DOC-MSRC@ MSRC-ALLOC DUP 0= IF DROP DOC-S-MEMORY EXIT THEN
    DUP _MDS-SIZE 0 FILL DUP _MD-S ! _MD-D @ DOC-STATE!
    ['] _MD-PARSE CATCH
    _MD-FREE-STRUCTURE
    _MD-STATUS ;

\ =====================================================================
\  Inline items
\ =====================================================================

\ An item is 32 bytes of 32-bit fields: what it is, its meanings, its
\ text among the pool's bytes, and the link it lies in (one more than the
\ link's index, 0 for none).
 0 CONSTANT _I.TYPE
 4 CONSTANT _I.FLAGS
 8 CONSTANT _I.OFF
12 CONSTANT _I.LEN
16 CONSTANT _I.LINK

0 CONSTANT _MD-I-NONE      \ taken away
1 CONSTANT _MD-I-TEXT
2 CONSTANT _MD-I-SOFT      \ a soft line break
3 CONSTANT _MD-I-HARD      \ a hard line break
4 CONSTANT _MD-I-CODE
5 CONSTANT _MD-I-HTML

1 CONSTANT _MD-IF-EMPH
2 CONSTANT _MD-IF-STRONG
4 CONSTANT _MD-IF-JOIN     \ plain text the next plain text may join

: _MD-ITEM    ( k -- a )  5 LSHIFT _MD-ITEMS _MB.A @ + ;
: _I@         ( k field -- v )  SWAP _MD-ITEM + L@ ;
: _I!         ( v k field -- )  SWAP _MD-ITEM + L! ;
: _MD-NITEMS  ( -- n )  _MD-ITEMS _MB.N @ 5 RSHIFT ;
: _MD-ITEM-TEXT  ( k -- a u )
    DUP _I.OFF _I@ _MD-POOL _MB.A @ + SWAP _I.LEN _I@ ;

: _MD-NEW-ITEM  ( type off len flags -- k )
    _MD-NITEMS >R
    32 _MD-ITEMS _MD-ROOM DROP
    R@ _I.FLAGS _I! R@ _I.LEN _I! R@ _I.OFF _I! R@ _I.TYPE _I!
    0 R@ _I.LINK _I!
    R> ;

\ _MD-TEXT ( a u -- )
\   Plain text, joined to plain text just before it outside a link.
: _MD-TEXT  ( a u -- )
    DUP 0= IF 2DROP EXIT THEN
    _MD-NITEMS ?DUP IF
        1-
        DUP _I.TYPE _I@ _MD-I-TEXT = OVER _I.FLAGS _I@ _MD-IF-JOIN AND 0<> AND
        OVER _I.LINK _I@ 0= AND
        OVER _I.OFF _I@ 2 PICK _I.LEN _I@ + _MD-POOL _MB.N @ = AND IF
            DUP _I.LEN _I@ 2 PICK + SWAP _I.LEN _I!
            _MD-POOL _MD-PUT EXIT
        THEN
        DROP
    THEN
    _MD-POOL _MB.N @ -ROT DUP >R _MD-POOL _MD-PUT R>
    _MD-I-TEXT -ROT _MD-IF-JOIN _MD-NEW-ITEM DROP ;

\ _MD-TEXT-ITEM ( a u -- k )  Text that stays an item of its own.
: _MD-TEXT-ITEM  ( a u -- k )
    _MD-POOL _MB.N @ -ROT DUP >R _MD-POOL _MD-PUT R>
    _MD-I-TEXT -ROT 0 _MD-NEW-ITEM ;

: _MD-TEXT-BYTE  ( c -- )  _MD-ENC C! _MD-ENC 1 _MD-TEXT ;
: _MD-TEXT-CP    ( cp -- )  _MD-ENC _MD-ENCODE _MD-ENC SWAP _MD-TEXT ;

\ Delimiter runs of * and _, 64 bytes each, in a list from the stack's
\ top through PREV; -1 means none.
 0 CONSTANT _D.CC
 8 CONSTANT _D.NUM
16 CONSTANT _D.ORIG
24 CONSTANT _D.ITEM
32 CONSTANT _D.PREV
40 CONSTANT _D.NEXT
48 CONSTANT _D.OPEN
56 CONSTANT _D.CLOSE

VARIABLE _MD-DTOP

: _MD-DELIM  ( k -- a )  6 LSHIFT _MD-DELIMS _MB.A @ + ;
: _D@  ( k field -- v )  SWAP _MD-DELIM + @ ;
: _D!  ( v k field -- )  SWAP _MD-DELIM + ! ;

: _MD-PUSH-DELIM  ( cc num item open close -- )
    _MD-DELIMS _MB.N @ 6 RSHIFT >R
    64 _MD-DELIMS _MD-ROOM DROP
    R@ _D.CLOSE _D! R@ _D.OPEN _D! R@ _D.ITEM _D!
    DUP R@ _D.NUM _D! R@ _D.ORIG _D! R@ _D.CC _D!
    _MD-DTOP @ R@ _D.PREV _D! -1 R@ _D.NEXT _D!
    _MD-DTOP @ 0< 0= IF R@ _MD-DTOP @ _D.NEXT _D! THEN
    R> _MD-DTOP ! ;

: _MD-REMOVE-DELIM  ( d -- )
    DUP _D.PREV _D@ DUP 0< 0= IF OVER _D.NEXT _D@ SWAP _D.NEXT _D! ELSE DROP THEN
    DUP _D.NEXT _D@ DUP 0< IF
        DROP _D.PREV _D@ _MD-DTOP !
    ELSE
        SWAP _D.PREV _D@ SWAP _D.PREV _D!
    THEN ;

\ Brackets [ and ![ that may open a link or a picture, 64 bytes each.
 0 CONSTANT _B.ITEM
 8 CONSTANT _B.PREV
16 CONSTANT _B.PDELIM      \ the delimiter stack's top when it opened
24 CONSTANT _B.INDEX       \ where its [ is
32 CONSTANT _B.IMAGE
40 CONSTANT _B.ACTIVE
48 CONSTANT _B.AFTER       \ another bracket opened after it

VARIABLE _MD-BTOP

: _MD-BRACKET  ( k -- a )  6 LSHIFT _MD-BRACKETS _MB.A @ + ;
: _B@  ( k field -- v )  SWAP _MD-BRACKET + @ ;
: _B!  ( v k field -- )  SWAP _MD-BRACKET + ! ;

: _MD-ADD-BRACKET  ( item index image -- )
    _MD-BTOP @ 0< 0= IF -1 _MD-BTOP @ _B.AFTER _B! THEN
    _MD-BRACKETS _MB.N @ 6 RSHIFT >R
    64 _MD-BRACKETS _MD-ROOM DROP
    R@ _B.IMAGE _B! R@ _B.INDEX _B! R@ _B.ITEM _B!
    _MD-BTOP @ R@ _B.PREV _B! _MD-DTOP @ R@ _B.PDELIM _B!
    -1 R@ _B.ACTIVE _B! 0 R@ _B.AFTER _B!
    R> _MD-BTOP ! ;

: _MD-REMOVE-BRACKET  ( -- )  _MD-BTOP @ _B.PREV _B@ _MD-BTOP ! ;

\ Links and pictures, 64 bytes each: the destination among the pool's
\ bytes, whether it is a picture, and the items from its opening bracket
\ to its end.  An item names one by its index plus one.
 0 CONSTANT _L.OFF
 8 CONSTANT _L.U
16 CONSTANT _L.IMAGE
24 CONSTANT _L.FIRST
32 CONSTANT _L.END

: _MD-LINK    ( k -- a )  6 LSHIFT _MD-LINKS _MB.A @ + ;
: _MD-NLINKS  ( -- n )  _MD-LINKS _MB.N @ 6 RSHIFT ;

\ _MD-NEW-LINK ( off u image first -- id )
\   A link or picture whose opening item is FIRST and whose items run to the
\   last so far.
: _MD-NEW-LINK  ( off u image first -- id )
    _MD-NLINKS >R 64 _MD-LINKS _MD-ROOM >R
    R@ _L.FIRST + ! R@ _L.IMAGE + ! R@ _L.U + ! R@ _L.OFF + !
    _MD-NITEMS R> _L.END + ! R> 1+ ;

: _MD-SET-LINK  ( id from to -- )  SWAP ?DO DUP I _I.LINK _I! LOOP DROP ;
: _MD-SET-FLAG  ( flag from to -- )
    SWAP ?DO DUP I _I.FLAGS _I@ OR I _I.FLAGS _I! LOOP DROP ;

\ =====================================================================
\  Inline syntax
\ =====================================================================

VARIABLE _MNL-TYPE
VARIABLE _MNL-K

\ The last item's last byte, when it is plain text outside a link.
: _MD-NL-LAST  ( -- c | -1 )
    _MNL-K @ _MD-ITEM-TEXT DUP IF + 1- C@ ELSE 2DROP -1 THEN ;

\ A line feed: a hard break after two spaces, else a soft one.  Spaces
\ before it and after it go.
: _MD-NEWLINE  ( -- )
    1 _MD-POS +!
    _MD-I-SOFT _MNL-TYPE !
    _MD-NITEMS IF
        _MD-NITEMS 1- _MNL-K !
        _MNL-K @ _I.TYPE _I@ _MD-I-TEXT = _MNL-K @ _I.LINK _I@ 0= AND
        _MD-NL-LAST 32 = AND IF
            _MNL-K @ _MD-ITEM-TEXT DUP 1 > IF + 2 - C@ 32 = ELSE 2DROP 0 THEN
            IF _MD-I-HARD _MNL-TYPE ! THEN
            BEGIN _MD-NL-LAST 32 = WHILE
                _MNL-K @ _I.LEN _I@ 1- _MNL-K @ _I.LEN _I!
            REPEAT
        THEN
    THEN
    _MNL-TYPE @ 0 0 0 _MD-NEW-ITEM DROP
    BEGIN _MD-SPEEK 32 = WHILE 1 _MD-POS +! REPEAT ;

: _MD-BACKSLASH  ( -- )
    1 _MD-POS +!
    _MD-SPEEK 10 = IF 1 _MD-POS +! _MD-I-HARD 0 0 0 _MD-NEW-ITEM DROP EXIT THEN
    _MD-SPEEK DUP _MD-ASCII-PUNCT? IF 1 _MD-POS +! _MD-TEXT-BYTE EXIT THEN
    DROP 92 _MD-TEXT-BYTE ;

VARIABLE _MBT-N
VARIABLE _MBT-AFTER
VARIABLE _MCS-OFF
VARIABLE _MCS-U

\ A code span from the opening run to END, where the closing run starts.
\ Its line feeds read as spaces, and one space goes from each end when
\ both ends have one and it is not only spaces.
: _MD-CODE-SPAN  ( end -- )
    _MBT-AFTER @ - _MCS-U !
    _MD-POOL _MB.N @ _MCS-OFF !
    _MD-SA @ _MBT-AFTER @ + _MCS-U @ _MD-POOL _MD-PUT
    _MD-POOL _MB.A @ _MCS-OFF @ +
    _MCS-U @ 0 ?DO DUP I + C@ 10 = IF 32 OVER I + C! THEN LOOP
    _MCS-U @ 2 > IF
        DUP C@ 32 = OVER _MCS-U @ + 1- C@ 32 = AND IF
            DUP _MCS-U @ _MD-ALL-SPACES? 0= IF 1 _MCS-OFF +! -2 _MCS-U +! THEN
        THEN
    THEN DROP
    _MD-I-CODE _MCS-OFF @ _MCS-U @ 0 _MD-NEW-ITEM DROP ;

: _MD-BACKTICKS  ( -- )
    0 BEGIN _MD-SPEEK 96 = WHILE 1+ 1 _MD-POS +! REPEAT _MBT-N !
    _MD-POS @ _MBT-AFTER !
    BEGIN
        BEGIN _MD-SPEEK DUP -1 <> SWAP 96 <> AND WHILE 1 _MD-POS +! REPEAT
        _MD-SPEEK -1 = IF
            \ No closing run: the backticks are text.
            _MBT-AFTER @ _MD-POS !
            _MD-SA @ _MBT-AFTER @ + _MBT-N @ - _MBT-N @ _MD-TEXT EXIT
        THEN
        _MD-POS @ 0 BEGIN _MD-SPEEK 96 = WHILE 1+ 1 _MD-POS +! REPEAT
        _MBT-N @ = IF _MD-CODE-SPAN EXIT THEN
        DROP
    AGAIN ;

VARIABLE _MHD-CC
VARIABLE _MHD-N
VARIABLE _MHD-START
VARIABLE _MHD-AWS
VARIABLE _MHD-AP
VARIABLE _MHD-BWS
VARIABLE _MHD-BP

\ A run of * or _: text, and a delimiter when its flanking lets it open
\ or close emphasis.
: _MD-HANDLE-DELIM  ( cc -- )
    _MHD-CC ! _MD-POS @ _MHD-START !
    0 BEGIN _MD-SPEEK _MHD-CC @ = WHILE 1+ 1 _MD-POS +! REPEAT _MHD-N !
    _MD-POS @ _MD-CP-AT DUP _MD-UWS? _MHD-AWS ! _MD-PUNCT? _MHD-AP !
    _MHD-START @ _MD-CP-BEFORE DUP _MD-UWS? _MHD-BWS ! _MD-PUNCT? _MHD-BP !
    _MHD-AWS @ 0= _MHD-AP @ 0= _MHD-BWS @ OR _MHD-BP @ OR AND
    _MHD-BWS @ 0= _MHD-BP @ 0= _MHD-AWS @ OR _MHD-AP @ OR AND
    _MHD-CC @ 95 = IF
        OVER OVER 0= _MHD-BP @ OR AND
        -ROT SWAP 0= _MHD-AP @ OR AND
    THEN
    _MD-SA @ _MHD-START @ + _MHD-N @ _MD-TEXT-ITEM
    -ROT 2DUP OR IF
        >R >R _MHD-CC @ _MHD-N @ ROT R> R> _MD-PUSH-DELIM
    ELSE 2DROP DROP THEN ;

CREATE _MPE-BOTTOM 9 CELLS ALLOT
VARIABLE _MPE-SB
VARIABLE _MPE-CLOSER
VARIABLE _MPE-OPENER
VARIABLE _MPE-IDX
VARIABLE _MPE-FOUND
VARIABLE _MPE-OLD

: _MD-ODD-MATCH?  ( opener -- flag )
    DUP _D.CLOSE _D@ _MPE-CLOSER @ _D.OPEN _D@ OR 0<>
    _MPE-CLOSER @ _D.ORIG _D@ 3 MOD 0<> AND
    SWAP _D.ORIG _D@ _MPE-CLOSER @ _D.ORIG _D@ + 3 MOD 0= AND ;

: _MD-FIND-OPENER  ( -- )
    _MPE-CLOSER @ _D.CC _D@ 95 = IF 2 ELSE
        3 _MPE-CLOSER @ _D.OPEN _D@ IF 3 + THEN _MPE-CLOSER @ _D.ORIG _D@ 3 MOD +
    THEN _MPE-IDX !
    0 _MPE-FOUND !
    _MPE-CLOSER @ _D.PREV _D@
    BEGIN
        DUP 0< 0= OVER _MPE-SB @ <> AND
        OVER _MPE-BOTTOM _MPE-IDX @ CELLS + @ <> AND
    WHILE
        DUP _MD-ODD-MATCH? 0=
        OVER _D.CC _D@ _MPE-CLOSER @ _D.CC _D@ = AND
        OVER _D.OPEN _D@ 0<> AND IF -1 _MPE-FOUND ! _MPE-OPENER ! EXIT THEN
        _D.PREV _D@
    REPEAT DROP ;

: _MD-MATCH-PAIR  ( -- )
    _MPE-CLOSER @ _D.NUM _D@ 1 > _MPE-OPENER @ _D.NUM _D@ 1 > AND IF 2 ELSE 1 THEN
    DUP NEGATE _MPE-OPENER @ _D.NUM _D@ + _MPE-OPENER @ _D.NUM _D!
    DUP NEGATE _MPE-CLOSER @ _D.NUM _D@ + _MPE-CLOSER @ _D.NUM _D!
    \ The runs lose the characters they used.
    _MPE-OPENER @ _D.ITEM _D@ DUP _I.LEN _I@ 2 PICK - SWAP _I.LEN _I!
    _MPE-CLOSER @ _D.ITEM _D@ DUP _I.LEN _I@ 2 PICK - SWAP _I.LEN _I!
    \ What lies between them is emphasized, or strongly.
    1 = IF _MD-IF-EMPH ELSE _MD-IF-STRONG THEN
    _MPE-OPENER @ _D.ITEM _D@ 1+ _MPE-CLOSER @ _D.ITEM _D@ _MD-SET-FLAG
    _MPE-OPENER @ _D.NEXT _D@ _MPE-CLOSER @ <> IF
        _MPE-CLOSER @ _MPE-OPENER @ _D.NEXT _D!
        _MPE-OPENER @ _MPE-CLOSER @ _D.PREV _D!
    THEN
    _MPE-OPENER @ _D.NUM _D@ 0= IF
        _MD-I-NONE _MPE-OPENER @ _D.ITEM _D@ _I.TYPE _I!
        _MPE-OPENER @ _MD-REMOVE-DELIM
    THEN
    _MPE-CLOSER @ _D.NUM _D@ 0= IF
        _MD-I-NONE _MPE-CLOSER @ _D.ITEM _D@ _I.TYPE _I!
        _MPE-CLOSER @ _D.NEXT _D@
        _MPE-CLOSER @ _MD-REMOVE-DELIM
        _MPE-CLOSER !
    THEN ;

\ _MD-PROCESS-EMPHASIS ( bottom -- )
\   Match the delimiters above BOTTOM into emphasis, and take them away.
: _MD-PROCESS-EMPHASIS  ( bottom -- )
    _MPE-SB !
    9 0 DO _MPE-SB @ _MPE-BOTTOM I CELLS + ! LOOP
    _MD-DTOP @
    BEGIN DUP 0< 0= IF DUP _D.PREV _D@ _MPE-SB @ <> ELSE 0 THEN WHILE _D.PREV _D@ REPEAT
    _MPE-CLOSER !
    BEGIN _MPE-CLOSER @ 0< 0= WHILE
        _MPE-CLOSER @ _D.CLOSE _D@ 0= IF
            _MPE-CLOSER @ _D.NEXT _D@ _MPE-CLOSER !
        ELSE
            _MD-FIND-OPENER
            _MPE-CLOSER @ _MPE-OLD !
            _MPE-FOUND @ IF
                _MD-MATCH-PAIR
            ELSE
                _MPE-CLOSER @ _D.NEXT _D@ _MPE-CLOSER !
                _MPE-OLD @ _D.PREV _D@ _MPE-BOTTOM _MPE-IDX @ CELLS + !
                _MPE-OLD @ _D.OPEN _D@ 0= IF _MPE-OLD @ _MD-REMOVE-DELIM THEN
            THEN
        THEN
    REPEAT
    BEGIN _MD-DTOP @ DUP 0< 0= SWAP _MPE-SB @ <> AND WHILE
        _MD-DTOP @ _MD-REMOVE-DELIM
    REPEAT ;

: _MD-OPEN-BRACKET  ( -- )
    _MD-SA @ _MD-POS @ + 1 _MD-TEXT-ITEM _MD-POS @ 0 _MD-ADD-BRACKET
    1 _MD-POS +! ;

: _MD-BANG  ( -- )
    _MD-POS @ 1+ _MD-AT 91 = IF
        _MD-SA @ _MD-POS @ + 2 _MD-TEXT-ITEM _MD-POS @ 1+ -1 _MD-ADD-BRACKET
        2 _MD-POS +! EXIT
    THEN
    33 _MD-TEXT-BYTE 1 _MD-POS +! ;

VARIABLE _MCB-START       \ just after the ]
VARIABLE _MCB-SAVE
VARIABLE _MCB-OPENER
VARIABLE _MCB-MATCHED
VARIABLE _MCB-DEST-OFF    \ the destination, unescaped among the pool's bytes
VARIABLE _MCB-DEST-U

: _MD-STORE-DEST  ( a u -- )
    _MD-POOL _MB.N @ _MCB-DEST-OFF !
    _MD-POOL _MD-UNESCAPE
    _MD-POOL _MB.N @ _MCB-DEST-OFF @ - _MCB-DEST-U ! ;

\ ( destination title ) right after the ].
: _MD-INLINE-DEST  ( -- )
    1 _MD-POS +! _MD-SPNL
    _MD-LINK-DEST 0= IF
        _MD-SPEEK 41 <> IF _MCB-SAVE @ _MD-POS ! EXIT THEN
        _MD-SA @ _MD-POS @ + _MD-DEST-A ! 0 _MD-DEST-U !
    THEN
    _MD-SPNL
    \ A title follows whitespace.
    _MD-POS @ 1- _MD-AT _MD-WS? IF _MD-LINK-TITLE DROP THEN
    _MD-SPNL
    _MD-SPEEK 41 <> IF _MCB-SAVE @ _MD-POS ! EXIT THEN
    1 _MD-POS +!
    _MD-DEST-A @ _MD-DEST-U @ _MD-STORE-DEST
    -1 _MCB-MATCHED ! ;

VARIABLE _MRL-BEFORE

\ A label after the ], or the link's own text, that names a definition.
: _MD-REFERENCE-LINK  ( -- )
    _MD-POS @ _MRL-BEFORE !
    _MD-LINK-LABEL
    DUP 2 > IF
        _MD-SA @ _MRL-BEFORE @ + OVER
    ELSE
        _MCB-OPENER @ _B.AFTER _B@ 0= IF
            _MD-SA @ _MCB-OPENER @ _B.INDEX _B@ +
            _MCB-START @ _MCB-OPENER @ _B.INDEX _B@ -
        ELSE 0 0 THEN
    THEN
    ROT 0= IF _MCB-SAVE @ _MD-POS ! THEN
    DUP 0= IF 2DROP EXIT THEN
    _MD-FIND-LABEL 0= IF 2DROP EXIT THEN
    _MD-POOL _MB.N @ _MCB-DEST-OFF ! DUP _MCB-DEST-U !
    _MD-POOL _MD-PUT
    -1 _MCB-MATCHED ! ;

: _MD-MAKE-LINK  ( -- )
    _MCB-DEST-OFF @ _MCB-DEST-U @ _MCB-OPENER @ _B.IMAGE _B@
    _MCB-OPENER @ _B.ITEM _B@ _MD-NEW-LINK
    _MCB-OPENER @ _B.ITEM _B@ 1+ _MD-NITEMS _MD-SET-LINK
    _MCB-OPENER @ _B.PDELIM _B@ _MD-PROCESS-EMPHASIS
    _MD-REMOVE-BRACKET
    _MD-I-NONE _MCB-OPENER @ _B.ITEM _B@ _I.TYPE _I!
    \ No link in a link: earlier [ no longer open links.
    _MCB-OPENER @ _B.IMAGE _B@ 0= IF
        _MD-BTOP @
        BEGIN DUP 0< 0= WHILE
            DUP _B.IMAGE _B@ 0= IF 0 OVER _B.ACTIVE _B! THEN
            _B.PREV _B@
        REPEAT DROP
    THEN ;

: _MD-CLOSE-BRACKET  ( -- )
    1 _MD-POS +! _MD-POS @ _MCB-START !
    _MD-BTOP @ DUP _MCB-OPENER !
    0< IF 93 _MD-TEXT-BYTE EXIT THEN
    _MCB-OPENER @ _B.ACTIVE _B@ 0= IF 93 _MD-TEXT-BYTE _MD-REMOVE-BRACKET EXIT THEN
    0 _MCB-MATCHED !
    _MD-POS @ _MCB-SAVE !
    _MD-SPEEK 40 = IF _MD-INLINE-DEST THEN
    _MCB-MATCHED @ 0= IF _MD-REFERENCE-LINK THEN
    _MCB-MATCHED @ IF _MD-MAKE-LINK EXIT THEN
    _MD-REMOVE-BRACKET _MCB-START @ _MD-POS ! 93 _MD-TEXT-BYTE ;

: _MD-EMAIL-LOCAL?  ( c -- flag )
    DUP _MD-ALNUM? IF DROP -1 EXIT THEN
    S" .!#$%&'*+/=?^_`{|}~-" ROT _MD-CHAR-IN? ;

\ _MD-MATCH-AUTOLINK ( a u -- len email? )
\   An autolink at A, which starts with <: a URI with a scheme, or an
\   email address, and >.  0 0 when there is none.
: _MD-MATCH-AUTOLINK  ( a u -- len email? )
    _MHT-SET
    _MHT@ 60 <> IF 0 0 EXIT THEN _MHT+
    _MHT@ _MD-ALPHA? IF
        _MHT-I @
        BEGIN _MHT@ DUP _MD-ALNUM? OVER 43 = OR OVER 46 = OR SWAP 45 = OR WHILE _MHT+ REPEAT
        _MHT-I @ SWAP -
        2 33 WITHIN _MHT@ 58 = AND IF
            _MHT+
            BEGIN _MHT@ DUP 32 > OVER 60 <> AND SWAP 62 <> AND WHILE _MHT+ REPEAT
            _MHT@ 62 = IF _MHT+ _MHT-I @ 0 EXIT THEN
            0 0 EXIT
        THEN
        1 _MHT-I !
    THEN
    0 BEGIN _MHT@ _MD-EMAIL-LOCAL? WHILE 1+ _MHT+ REPEAT
    0= IF 0 0 EXIT THEN
    _MHT@ 64 <> IF 0 0 EXIT THEN _MHT+
    BEGIN
        \ A label: 1 to 63 letters, digits and hyphens, with no hyphen at
        \ either end.
        _MHT-I @
        BEGIN _MHT@ DUP _MD-ALNUM? SWAP 45 = OR WHILE _MHT+ REPEAT
        _MHT-I @ OVER -
        DUP 1 64 WITHIN 0= IF 2DROP 0 0 EXIT THEN
        OVER _MHT-A @ + C@ _MD-ALNUM? 0= IF 2DROP 0 0 EXIT THEN
        + 1- _MHT-A @ + C@ _MD-ALNUM? 0= IF 0 0 EXIT THEN
        _MHT@ 46 =
    WHILE _MHT+ REPEAT
    _MHT@ 62 <> IF 0 0 EXIT THEN _MHT+ _MHT-I @ -1 ;

: _MD-AUTOLINK  ( -- ok? )
    _MD-SA @ _MD-POS @ + _MD-SU @ _MD-POS @ - _MD-MATCH-AUTOLINK
    OVER 0= IF 2DROP 0 EXIT THEN
    _MD-POOL _MB.N @ _MCB-DEST-OFF !
    IF S" mailto:" _MD-POOL _MD-PUT THEN
    _MD-SA @ _MD-POS @ + 1+ OVER 2 - _MD-POOL _MD-PUT
    _MCB-DEST-OFF @ _MD-POOL _MB.N @ _MCB-DEST-OFF @ - 0 _MD-NITEMS _MD-NEW-LINK
    _MD-SA @ _MD-POS @ + 1+ 2 PICK 2 - _MD-TEXT-ITEM _I.LINK _I!
    _MD-POS +! -1 ;

: _MD-HTML-INLINE  ( -- ok? )
    _MD-SA @ _MD-POS @ + _MD-SU @ _MD-POS @ - _MD-MATCH-HTML-TAG
    DUP 0= IF EXIT THEN
    _MD-POOL _MB.N @ SWAP
    _MD-SA @ _MD-POS @ + OVER _MD-POOL _MD-PUT
    DUP _MD-POS +!
    _MD-I-HTML -ROT 0 _MD-NEW-ITEM DROP -1 ;

: _MD-ENTITY  ( -- ok? )
    _MD-SA @ _MD-POS @ + _MD-SU @ _MD-POS @ - _MD-MATCH-ENTITY
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    2 = IF SWAP _MD-TEXT-CP _MD-TEXT-CP ELSE DROP _MD-TEXT-CP THEN
    _MD-POS +! -1 ;

\ The characters that may start inline syntax, one byte each: line feed
\ ` [ ] \ ! < & * _ ' and ".
CREATE _MD-SPECIALS 256 ALLOT  _MD-SPECIALS 256 0 FILL
: _MD-SPECIAL!  ( c -- )  _MD-SPECIALS + 1 SWAP C! ;
10 _MD-SPECIAL!  96 _MD-SPECIAL!  91 _MD-SPECIAL!  93 _MD-SPECIAL!
92 _MD-SPECIAL!  33 _MD-SPECIAL!  60 _MD-SPECIAL!  38 _MD-SPECIAL!
42 _MD-SPECIAL!  95 _MD-SPECIAL!  39 _MD-SPECIAL!  34 _MD-SPECIAL!

VARIABLE _MSR-END

\ Plain text to the next character that may start syntax, at least one.
: _MD-STRING-RUN  ( -- )
    _MD-SA @ DUP _MD-SU @ + _MSR-END !
    _MD-POS @ +
    BEGIN
        DUP _MSR-END @ < IF DUP C@ _MD-SPECIALS + C@ 0= ELSE 0 THEN
    WHILE 1+ REPEAT
    _MD-SA @ -
    DUP _MD-POS @ = IF 1+ THEN
    _MD-SA @ _MD-POS @ + OVER _MD-POS @ - _MD-TEXT
    _MD-POS ! ;

: _MD-PARSE-INLINE  ( -- )
    _MD-SPEEK
    DUP 10 = IF DROP _MD-NEWLINE EXIT THEN
    DUP 92 = IF DROP _MD-BACKSLASH EXIT THEN
    DUP 96 = IF DROP _MD-BACKTICKS EXIT THEN
    DUP 42 = OVER 95 = OR IF _MD-HANDLE-DELIM EXIT THEN
    DUP 91 = IF DROP _MD-OPEN-BRACKET EXIT THEN
    DUP 33 = IF DROP _MD-BANG EXIT THEN
    DUP 93 = IF DROP _MD-CLOSE-BRACKET EXIT THEN
    DUP 60 = IF
        DROP _MD-AUTOLINK IF EXIT THEN _MD-HTML-INLINE IF EXIT THEN
        60 _MD-TEXT-BYTE 1 _MD-POS +! EXIT
    THEN
    DUP 38 = IF
        DROP _MD-ENTITY IF EXIT THEN
        38 _MD-TEXT-BYTE 1 _MD-POS +! EXIT
    THEN
    DROP _MD-STRING-RUN ;

\ _MD-INLINE ( -- )  The subject's inline items.
: _MD-INLINE  ( -- )
    0 _MD-ITEMS _MB.N ! 0 _MD-POOL _MB.N ! 0 _MD-DELIMS _MB.N !
    0 _MD-BRACKETS _MB.N ! 0 _MD-LINKS _MB.N !
    0 _MD-POS ! -1 _MD-DTOP ! -1 _MD-BTOP !
    BEGIN _MD-POS @ _MD-SU @ < WHILE _MD-PARSE-INLINE REPEAT
    -1 _MD-PROCESS-EMPHASIS ;

\ =====================================================================
\  A block's text
\ =====================================================================

VARIABLE _MD-REGION-OFF

\ _MD-READ-REGION ( first count -- )
\   Read the source from the first span's start to the last one's end.
: _MD-READ-REGION  ( first count -- )
    0 _MD-REGION _MB.N !
    DUP 0= IF 2DROP EXIT THEN
    OVER + 1- _MD-SPAN@ DROP + SWAP _MD-SPAN@ 2DROP
    DUP _MD-REGION-OFF !
    - DUP _MD-REGION _MD-ROOM
    SWAP _MD-REGION-OFF @ _MD-D @ DOC-SOURCE@ MEDSRC-READ? IF _MD-E-READ THROW THEN ;

: _MD-SPAN-TEXT  ( k -- a u lead )
    _MD-SPAN@ >R SWAP _MD-REGION-OFF @ - _MD-REGION _MB.A @ + SWAP R> ;

\ The spans' text, each line after the spaces a split tab gives it, with
\ line feeds between, trimmed.
: _MD-BUILD-SUBJECT  ( first count -- )
    0 _MD-SUBJ _MB.N !
    OVER + SWAP ?DO
        I _MD-SPAN-TEXT 0 ?DO 32 _MD-SUBJ _MD-PUTC LOOP
        _MD-SUBJ _MD-PUT 10 _MD-SUBJ _MD-PUTC
    LOOP
    _MD-SUBJ _MB.A @ _MD-SUBJ _MB.N @ _MD-TRIM _MD-SU ! _MD-SA ! ;

VARIABLE _ML-PEND        \ a space is pending, shown before the next text
VARIABLE _ML-PEND-M
VARIABLE _ML-PEND-L
VARIABLE _ML-CUR-L       \ the link whose range is open, 0 for none
VARIABLE _ML-CUR-START
VARIABLE _ML-FIGURE      \ a figure's caption, which links nothing

: _ML-CLOSE-RANGE  ( -- )
    _ML-CUR-L @ IF
        24 _MD-ORANGES _MD-ROOM
        _ML-CUR-START @ OVER ! _MD-OTEXT _MB.N @ OVER 8 + ! _ML-CUR-L @ SWAP 16 + !
        0 _ML-CUR-L !
    THEN ;

: _ML-LINK-TO  ( link -- )
    DUP _ML-CUR-L @ = IF DROP EXIT THEN
    _ML-CLOSE-RANGE
    DUP _ML-CUR-L ! IF _MD-OTEXT _MB.N @ _ML-CUR-START ! THEN ;

: _ML-BYTES  ( a u meaning link -- )
    _ML-LINK-TO
    OVER _MD-OMAP _MD-ROOM SWAP 2 PICK SWAP FILL
    _MD-OTEXT _MD-PUT ;

CREATE _ML-SPACE-BYTE 32 C,
CREATE _ML-LF-BYTE 10 C,

: _ML-FLUSH  ( -- )
    _ML-PEND @ 0= IF EXIT THEN 0 _ML-PEND !
    _ML-SPACE-BYTE 1 _ML-PEND-M @ _ML-PEND-L @ _ML-BYTES ;

: _ML-CHARS  ( a u meaning link -- )  _ML-FLUSH _ML-BYTES ;

\ Whitespace: one space at most, and none at the start of a line.
: _ML-SPACE  ( meaning link -- )
    _ML-PEND @ IF 2DROP EXIT THEN
    _MD-OTEXT _MB.N @ 0= IF 2DROP EXIT THEN
    _MD-OTEXT _MB.A @ _MD-OTEXT _MB.N @ + 1- C@ 10 = IF 2DROP EXIT THEN
    _ML-PEND-L ! _ML-PEND-M ! -1 _ML-PEND ! ;

: _ML-BREAK  ( -- )
    0 _ML-PEND ! _ML-LF-BYTE 1 0 0 _ML-BYTES ;

VARIABLE _MLT-M
VARIABLE _MLT-L
VARIABLE _MLT-KEEP       \ spaces are kept, as in a code span

: _ML-CP  ( cp -- )  _MD-ENC _MD-ENCODE _MD-ENC SWAP _MLT-M @ _MLT-L @ _ML-CHARS ;

\ The printable ASCII bytes at the text's start.
: _MD-ASCII-RUN  ( a u -- n )
    TUCK 0 ?DO DUP I + C@ 33 127 WITHIN 0= IF 2DROP I UNLOOP EXIT THEN LOOP DROP ;

\ _ML-TEXT ( a u meaning link keep? -- )
\   Show text: whitespace as spaces, controls and ill-formed UTF-8 as
\   U+FFFD.
: _ML-TEXT  ( a u meaning link keep? -- )
    _MLT-KEEP ! _MLT-L ! _MLT-M !
    BEGIN DUP 0> WHILE
        2DUP _MD-ASCII-RUN ?DUP IF
            >R OVER R@ _MLT-M @ _MLT-L @ _ML-CHARS R> /STRING
        ELSE
            OVER C@ DUP 128 < IF
                DUP _MD-WS? IF
                    DROP _MLT-KEEP @ IF
                        _ML-SPACE-BYTE 1 _MLT-M @ _MLT-L @ _ML-CHARS
                    ELSE _MLT-M @ _MLT-L @ _ML-SPACE THEN
                ELSE DROP 65533 _ML-CP THEN
                1 /STRING
            ELSE
                DROP 2DUP _MD-DECODE
                SWAP 65533 = IF 65533 _ML-CP ELSE 2 PICK OVER _MLT-M @ _MLT-L @ _ML-CHARS THEN
                /STRING
            THEN
        THEN
    REPEAT 2DROP ;

: _ML-MEANING  ( k -- meaning )
    DUP _I.LINK _I@ 0<> _ML-FIGURE @ 0= AND IF DROP TSTY-LINK EXIT THEN
    DUP _I.TYPE _I@ _MD-I-CODE = IF DROP TSTY-CODE EXIT THEN
    _I.FLAGS _I@ DUP _MD-IF-STRONG AND IF DROP TSTY-STRONG EXIT THEN
    _MD-IF-EMPH AND IF TSTY-EMPHASIS ELSE TSTY-PLAIN THEN ;

: _ML-LINK  ( k -- link )  _ML-FIGURE @ IF DROP 0 ELSE _I.LINK _I@ THEN ;

\ The items as text, meanings and link ranges.
: _MD-LINEARIZE  ( -- )
    0 _MD-OTEXT _MB.N ! 0 _MD-OMAP _MB.N ! 0 _MD-ORANGES _MB.N !
    0 _ML-PEND ! 0 _ML-CUR-L !
    _MD-NITEMS 0 ?DO
        I _I.TYPE _I@
        DUP _MD-I-TEXT = OVER _MD-I-HTML = OR IF
            I _MD-ITEM-TEXT I _ML-MEANING I _ML-LINK 0 _ML-TEXT
        THEN
        DUP _MD-I-CODE = IF
            I _MD-ITEM-TEXT I _ML-MEANING I _ML-LINK -1 _ML-TEXT
        THEN
        DUP _MD-I-SOFT = IF I _ML-MEANING I _ML-LINK _ML-SPACE THEN
        _MD-I-HARD = IF _ML-BREAK THEN
    LOOP
    _ML-CLOSE-RANGE ;

VARIABLE _MFT-I
VARIABLE _MFT-MAP
VARIABLE _MFT-N
VARIABLE _MFT-M

\ Hand the text to the document's builder, a run of one meaning at a time,
\ then the links.
: _MD-FLUSH-TEXT  ( -- )
    0 _MFT-I !
    _MD-OMAP _MB.A @ _MFT-MAP !  _MD-OTEXT _MB.N @ _MFT-N !
    BEGIN _MFT-I @ _MFT-N @ < WHILE
        _MFT-MAP @ _MFT-I @ + C@ _MFT-M !
        _MFT-I @
        BEGIN
            1+ DUP _MFT-N @ < IF DUP _MFT-MAP @ + C@ _MFT-M @ = ELSE 0 THEN
        WHILE REPEAT
        _MD-OTEXT _MB.A @ _MFT-I @ + OVER _MFT-I @ -
        _MFT-I @ _MD-OMAP _MB.A @ + C@ _MD-D @ DOC-CB-TEXT 0= IF _MD-E-MEMORY THROW THEN
        _MFT-I !
    REPEAT
    _MD-ORANGES _MB.N @ 0 ?DO
        _MD-ORANGES _MB.A @ I + DUP @ OVER 8 + @ ROT 16 + @ 1- _MD-LINK
        DUP _L.OFF + @ _MD-POOL _MB.A @ + SWAP _L.U + @
        _MD-D @ DOC-CB-LINK 0= IF _MD-E-MEMORY THROW THEN
    24 +LOOP ;

\ Is the paragraph only one picture: is the last link a picture whose
\ opening bracket is the first item and whose end is the last?
: _MD-FIGURE?  ( -- flag )
    _MD-NLINKS DUP 0= IF EXIT THEN
    1- _MD-LINK
    DUP _L.IMAGE + @ 0= IF DROP 0 EXIT THEN
    DUP _L.FIRST + @ 0= SWAP _L.END + @ _MD-NITEMS = AND ;

: _MD-PROSE  ( block -- )
    DUP BLK-KIND@ DOC-B-PARAGRAPH = >R
    BLK-LOC@ 2DUP _MD-READ-REGION _MD-BUILD-SUBJECT
    _MD-INLINE
    \ A paragraph that is only a picture is a figure; a heading stays one.
    R> IF _MD-FIGURE? ELSE 0 THEN DUP _ML-FIGURE ! IF
        DOC-B-FIGURE 0 _MD-D @ DOC-CB-KIND
        _MD-NLINKS 1- _MD-LINK DUP _L.OFF + @ _MD-POOL _MB.A @ + SWAP _L.U + @
        _MD-D @ DOC-CB-FIGURE 0= IF _MD-E-MEMORY THROW THEN
    THEN
    _MD-LINEARIZE _MD-FLUSH-TEXT ;

VARIABLE _MCT-COL

\ A line of code: tabs to the next multiple of four columns, controls
\ and ill-formed UTF-8 as U+FFFD.
: _MD-CODE-LINE  ( a u lead -- )
    DUP _MCT-COL !
    0 ?DO 32 _MD-OTEXT _MD-PUTC LOOP
    BEGIN DUP 0> WHILE
        2DUP _MD-ASCII-RUN ?DUP IF
            DUP _MCT-COL +! >R OVER R@ _MD-OTEXT _MD-PUT R> /STRING
        ELSE
            OVER C@
            DUP 32 = IF
                DROP 32 _MD-OTEXT _MD-PUTC 1 _MCT-COL +! 1 /STRING
            ELSE DUP 9 = IF
                DROP 4 _MCT-COL @ 4 MOD - DUP _MCT-COL +!
                0 ?DO 32 _MD-OTEXT _MD-PUTC LOOP 1 /STRING
            ELSE 128 < IF
                65533 _MD-OTEXT _MD-PUT-CP 1 _MCT-COL +! 1 /STRING
            ELSE
                2DUP _MD-DECODE SWAP 65533 = IF
                    65533 _MD-OTEXT _MD-PUT-CP
                ELSE 2 PICK OVER _MD-OTEXT _MD-PUT THEN
                1 _MCT-COL +! /STRING
            THEN THEN THEN
        THEN
    REPEAT 2DROP ;

VARIABLE _MCD-FIRST

: _MD-CODE  ( block -- )
    BLK-LOC@ 2DUP _MD-READ-REGION
    0 _MD-OTEXT _MB.N !
    OVER _MCD-FIRST !
    OVER + SWAP ?DO
        I _MCD-FIRST @ <> IF 10 _MD-OTEXT _MD-PUTC THEN
        I _MD-SPAN-TEXT _MD-CODE-LINE
    LOOP
    _MD-OTEXT _MB.A @ _MD-OTEXT _MB.N @ TSTY-PLAIN _MD-D @ DOC-CB-TEXT
    0= IF _MD-E-MEMORY THROW THEN ;

: _MD-CONTENT-BODY  ( block -- )
    DUP BLK-KIND@
    DUP DOC-B-PARAGRAPH = OVER DOC-B-HEADING = OR IF DROP _MD-PROSE EXIT THEN
    DOC-B-CODE = IF _MD-CODE EXIT THEN
    DROP ;

: _MD-CONTENT-XT  ( index doc -- status )
    DUP _MD-D ! DUP DOC-STATE@ _MD-S !
    DOC-BLOCK
    ['] _MD-CONTENT-BODY CATCH
    DUP IF NIP THEN _MD-STATUS ;

: _MD-CLOSE-XT  ( doc -- )
    DUP _MD-D ! DOC-STATE@ _MD-S ! _MD-FREE-ALL 0 _MD-D @ DOC-STATE! ;

\ =====================================================================
\  The reader
\ =====================================================================

CREATE _MD-READER RDR-SIZE ALLOT
' _MD-STRUCTURE-XT _MD-READER RDR.STRUCTURE-XT !
' _MD-CONTENT-XT   _MD-READER RDR.CONTENT-XT !
' _MD-CLOSE-XT     _MD-READER RDR.CLOSE-XT !
0                 _MD-READER RDR.PART-XT !

: MD-READER  ( -- reader )  _MD-READER ;
