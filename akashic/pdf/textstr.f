\ =================================================================
\  textstr.f  —  PDF text strings and characters, as UTF-8
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF- (public), _PDTS- (private)
\  Depends on: pdf/filter.f, pdf/text-tables.f
\
\  Public API:
\   PDF-CHAR+     ( cp buf msrc -- ok? )   a character onto BUF as UTF-8
\   PDF-TEXTSTR+  ( a u buf msrc -- ok? )  a text string, onto BUF as UTF-8
\
\  A text string (PDF 32000-1 section 7.9.2.2), such as an outline item's
\  title, is UTF-16BE after the byte order mark FE FF, its surrogate
\  pairs joined and a language's escape (from one U+001B to the next)
\  left out; UTF-8 after EF BB BF, as PDF 2.0 allows; and PDFDocEncoding
\  otherwise.  UTF-16LE after FF FE, which some writers give, is read as
\  well.  A code with no character, or half a surrogate pair, is U+FFFD;
\  a tab or a line end is a space, and another control nothing.
\
\  BUF is a pdf/filter.f buffer growing from MSRC; false when the source
\  refuses.  PDF-CHAR+ writes into BUF itself, without the text/utf8.f
\  encoder's guard, which costs more than the encoding: it is called for
\  each glyph of a page's text.  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-textstr

REQUIRE filter.f
REQUIRE text-tables.f

\ A character's UTF-8 bytes at A: how many.
: _PDTS-UTF8  ( cp a -- n )
    OVER 0x80 < IF C! 1 EXIT THEN
    OVER 0x800 < IF
        OVER 6 RSHIFT 0xC0 OR OVER C!
        SWAP 0x3F AND 0x80 OR SWAP 1+ C!  2 EXIT
    THEN
    OVER 0x10000 < IF
        OVER 12 RSHIFT 0xE0 OR OVER C!
        OVER 6 RSHIFT 0x3F AND 0x80 OR OVER 1+ C!
        SWAP 0x3F AND 0x80 OR SWAP 2 + C!  3 EXIT
    THEN
    OVER 18 RSHIFT 0xF0 OR OVER C!
    OVER 12 RSHIFT 0x3F AND 0x80 OR OVER 1+ C!
    OVER 6 RSHIFT 0x3F AND 0x80 OR OVER 2 + C!
    SWAP 0x3F AND 0x80 OR SWAP 3 + C!  4 ;

\ PDF-CHAR+ ( cp buf msrc -- ok? )   A character onto BUF as UTF-8.
: PDF-CHAR+  ( cp buf msrc -- ok? )
    >R DUP PDF-BUF.U @ 4 + OVER R> PDF-BUF-GROW 0= IF 2DROP 0 EXIT THEN
    DUP >R PDF-BUF.A @ R@ PDF-BUF.U @ + _PDTS-UTF8 R> PDF-BUF.U +! -1 ;

VARIABLE _PDTS-B   VARIABLE _PDTS-M   VARIABLE _PDTS-HIGH   VARIABLE _PDTS-ESC
VARIABLE _PDTS-LE   \ whether the UTF-16 is little-endian

\ A text string's character onto the output.
: _PDTS-CP+  ( cp -- ok? )
    DUP 32 < IF DUP 9 = OVER 10 = OR SWAP 13 = OR IF 32 ELSE -1 EXIT THEN THEN
    _PDTS-B @ _PDTS-M @ PDF-CHAR+ ;

\ A high surrogate left without its low half: U+FFFD.
: _PDTS-UNPAIRED  ( -- ok? )
    _PDTS-HIGH @ IF 0 _PDTS-HIGH !  0xFFFD _PDTS-CP+ ELSE -1 THEN ;

\ One UTF-16 code unit.
: _PDTS-UNIT  ( unit -- ok? )
    DUP 0x1B = IF DROP _PDTS-ESC @ 0= _PDTS-ESC ! -1 EXIT THEN
    _PDTS-ESC @ IF DROP -1 EXIT THEN
    DUP 0xDC00 0xE000 WITHIN IF
        _PDTS-HIGH @ ?DUP IF
            0 _PDTS-HIGH !  0xD800 - 10 LSHIFT SWAP 0xDC00 - + 0x10000 +
        ELSE DROP 0xFFFD THEN
        _PDTS-CP+ EXIT
    THEN
    _PDTS-UNPAIRED 0= IF DROP 0 EXIT THEN
    DUP 0xD800 0xDC00 WITHIN IF _PDTS-HIGH ! -1 EXIT THEN
    _PDTS-CP+ ;

\ UTF-16 after its byte order mark.
: _PDTS-UTF16  ( a u -- ok? )
    2 - SWAP 2 + SWAP  0 _PDTS-HIGH !  0 _PDTS-ESC !
    BEGIN DUP 1 > WHILE
        OVER DUP C@ SWAP 1+ C@  _PDTS-LE @ IF SWAP THEN  SWAP 8 LSHIFT OR
        >R 2 - SWAP 2 + SWAP R>
        _PDTS-UNIT 0= IF 2DROP 0 EXIT THEN
    REPEAT 2DROP _PDTS-UNPAIRED ;

\ Whether the U bytes at A start with the two bytes B0 B1.
: _PDTS-MARK?  ( a u b0 b1 -- flag )
    2 PICK 2 < IF 2DROP 2DROP 0 EXIT THEN
    >R >R DROP DUP C@ R> = SWAP 1+ C@ R> = AND ;

\ PDF-TEXTSTR+ ( a u buf msrc -- ok? )   A text string's U bytes at A,
\ onto BUF as UTF-8.
: PDF-TEXTSTR+  ( a u buf msrc -- ok? )
    _PDTS-M ! _PDTS-B !
    2DUP 0xFE 0xFF _PDTS-MARK? IF 0 _PDTS-LE ! _PDTS-UTF16 EXIT THEN
    2DUP 0xFF 0xFE _PDTS-MARK? IF -1 _PDTS-LE ! _PDTS-UTF16 EXIT THEN
    2DUP 0xEF 0xBB _PDTS-MARK? IF
        DUP 2 > IF OVER 2 + C@ 0xBF = IF
            3 - SWAP 3 + SWAP _PDTS-B @ _PDTS-M @ PDF-BUF-APPEND EXIT
        THEN THEN
    THEN
    OVER + SWAP ?DO
        I C@ 2* PDF-ENC-PDFDOC + W@ ?DUP 0= IF 0xFFFD THEN
        _PDTS-CP+ 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;
