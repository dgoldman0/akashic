\ =================================================================
\  font.f  —  a PDF font: the characters and widths of its codes
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-FONT- (public), _PDFT- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f, pdf/cmap.f,
\              pdf/text-tables.f, pdf/textstr.f
\
\  Public API:
\   PDF-FONT-SIZE   ( -- bytes )                          a font's record
\   PDF-FONT-LOAD   ( va vu type file font -- status )    read a font
\   PDF-FONT-FREE   ( font -- )
\   PDF-FONT-NEXT   ( a u font -- a' u' code n )          a string's next code
\   PDF-FONT-TEXT+  ( code font buf -- ok? )              its characters
\   PDF-FONT-WIDTH  ( code font -- w )                    its width
\   PDF-FONT-GLYPH  ( code font -- a u w )                both, kept
\   PDF-FONT-STYLE  ( font -- flags )
\   PDF-FONTS-SIZE  ( -- bytes )                          a set of fonts
\   PDF-FONTS-GET   ( va vu type file fonts -- font status )
\   PDF-FONTS-FREE  ( fonts -- )
\
\  PDF-FONT-LOAD reads the font dictionary a value gives, through a
\  reference.  A code's characters come from the font's ToUnicode map
\  (PDF 32000-1 section 9.10.2) when it holds the code.  Else a simple
\  font's come from its encoding: the base encoding its /Encoding names
\  (Standard, WinAnsi, MacRoman or PDFDoc); else, with no ToUnicode map,
\  an embedded Type 1 program's own; else Symbol's or ZapfDingbats' for
\  those fonts, Latin-1 for another symbolic font, WinAnsi for a TrueType
\  font and Standard for the rest; under /Differences, read through glyph
\  names (the Adobe Glyph List, ligatures, uniXXXX and uXXXX).  A
\  composite font's code is its character when its encoding is a UCS-2 or
\  UTF-16 one.  A code with no character is U+FFFD.
\
\  PDF-FONT-TEXT+ adds a code's characters to BUF, which draws on the
\  font's memory source, as UTF-8: a ligature U+FB00 to U+FB06 as its
\  letters, a tab or line end as a space, other controls as nothing.
\
\  PDF-FONT-NEXT reads a code from U bytes, U at least one: one byte for
\  a simple font; for a composite font two for Identity and UCS-2, two or
\  four for UTF-16, and else as the codespace ranges of its embedded CMap
\  or, for another named CMap, of its ToUnicode map say.  N is the code's
\  bytes; word spacing applies to a code 32 of one byte.
\
\  PDF-FONT-WIDTH is in thousandths of the text size: /Widths, else the
\  descriptor's /MissingWidth, or for a standard font without /Widths its
\  metrics; a Type 3 font's scaled by its /FontMatrix; a composite font's
\  from its CIDFont's /W, else /DW, by the code's CID: the code for an
\  Identity or other named encoding, an embedded CMap's CID.
\
\  PDF-FONT-GLYPH gives a code's characters, as PDF-FONT-TEXT+ writes
\  them, and its width, from a table of the codes shown last, 256 of
\  them by a hash of the code: both depend on the code alone, so a code
\  shown again costs a lookup.  The characters are valid until the next
\  call; they are at most 769 bytes, as a destination is at most 512
\  bytes of UTF-16.
\
\  PDF-FONT-STYLE gives PDF-FONT-BOLD, -ITALIC, -FIXED, -SERIF and
\  -VERTICAL from the descriptor's flags, weight and angle, the font's
\  name and its encoding.
\
\  A set of fonts, which starts zeroed, reads each font object once and
\  keeps it until the set is given back, so the pages of a document
\  share their fonts.  PDF-FONTS-GET gives 0 for a font that cannot be
\  read, and keeps that too.
\
\  Memory comes from the file's memory source; PDF-FONT-FREE gives it
\  back, and on failure PDF-FONT-LOAD gives back what it took.  One call
\  runs at a time.
\ =================================================================

PROVIDED akashic-pdf-font

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f
REQUIRE cmap.f
REQUIRE text-tables.f
REQUIRE textstr.f

1  CONSTANT PDF-FONT-BOLD
2  CONSTANT PDF-FONT-ITALIC
4  CONSTANT PDF-FONT-FIXED
8  CONSTANT PDF-FONT-SERIF
16 CONSTANT PDF-FONT-VERTICAL

\ The record: its kind, memory source, the simple font's tables (each
\ code's character, then each code's width, 32 bits each), the width of
\ a code with none, style, whether it has a ToUnicode map, and that map;
\ for a composite font, how its codes are read, its embedded CMap, and
\ its CIDs' widths as a map built by hand.
: _PDFT.KIND     ( f -- a )        ;
: _PDFT.MSRC     ( f -- a )    8 + ;
: _PDFT.TABLES   ( f -- a )   16 + ;
: _PDFT.MISSING  ( f -- a )   24 + ;
: _PDFT.STYLE    ( f -- a )   32 + ;
: _PDFT.HASTU    ( f -- a )   40 + ;
: _PDFT.TU       ( f -- m )   48 + ;
: _PDFT.ENC      ( f -- a )  136 + ;
: _PDFT.CMAP     ( f -- m )  144 + ;
: _PDFT.W        ( f -- m )  232 + ;
: _PDFT.CACHE    ( f -- a )  320 + ;    \ the codes shown last
328 CONSTANT PDF-FONT-SIZE

\ A kept code: the code plus one (0 for none), its width, its characters'
\ length and up to 15 of their bytes.
24 CONSTANT _PDFT-KEPT
256 _PDFT-KEPT * CONSTANT _PDFT-CACHE-BYTES

1 CONSTANT _PDFT-SIMPLE   2 CONSTANT _PDFT-TYPE3   3 CONSTANT _PDFT-TYPE0
\ How a composite font's codes are read.
0 CONSTANT _PDFT-E-IDENTITY   1 CONSTANT _PDFT-E-UCS2   2 CONSTANT _PDFT-E-UTF16
3 CONSTANT _PDFT-E-EMBEDDED   4 CONSTANT _PDFT-E-NAMED

VARIABLE _PDFT-F        \ the font
VARIABLE _PDFT-FILE
VARIABLE _PDFT-DO   VARIABLE _PDFT-DA   VARIABLE _PDFT-DU     \ its dictionary
VARIABLE _PDFT-XO   VARIABLE _PDFT-XA   VARIABLE _PDFT-XU     \ its descriptor
VARIABLE _PDFT-CO   VARIABLE _PDFT-CA   VARIABLE _PDFT-CU     \ its CIDFont
VARIABLE _PDFT-AO       \ the object holding its /DescendantFonts, when apart
VARIABLE _PDFT-SCALE    \ the font matrix's first value, in millionths
VARIABLE _PDFT-SYMBOLIC
VARIABLE _PDFT-I   VARIABLE _PDFT-J   VARIABLE _PDFT-CP   VARIABLE _PDFT-C

: _PDFT-FREE     ( obj -- )  _PDFT-FILE @ PDF-OBJ-FREE ;
: _PDFT-MSRC     ( -- msrc )  _PDFT-F @ _PDFT.MSRC @ ;
: _PDFT-RESOLVE  ( va vu type -- obj va' vu' type' status )  _PDFT-FILE @ PDF-RESOLVE ;
: _PDFT-KEY      ( key-a key-u -- va vu type )  _PDFT-DA @ _PDFT-DU @ PDF-DICT@ ;
: _PDFT-XKEY     ( key-a key-u -- va vu type )
    _PDFT-XA @ IF _PDFT-XA @ _PDFT-XU @ PDF-DICT@ ELSE 2DROP 0 0 PDF-T-END THEN ;
: _PDFT-STYLE+   ( flags -- )  _PDFT-F @ _PDFT.STYLE DUP @ ROT OR SWAP ! ;
: _PDFT-CHAR!    ( cp code -- )  4 * _PDFT-F @ _PDFT.TABLES @ + L! ;
: _PDFT-WIDTH!   ( w code -- )  4 * _PDFT-F @ _PDFT.TABLES @ 1024 + + L! ;
: _PDFT-SIGNED   ( u32 -- n )  DUP 0x80000000 AND IF 0x100000000 - THEN ;

\ =====================================================================
\  Numbers
\ =====================================================================

VARIABLE _PDFT-MI   VARIABLE _PDFT-MF   VARIABLE _PDFT-MS

\ A number's value in millionths.
: _PDFT-MICRO  ( va vu -- n )
    0 _PDFT-MI !  0 _PDFT-MF !  0 _PDFT-MS !
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 45 = DUP >R IF SWAP 1+ SWAP 1- THEN
    OVER + SWAP ?DO
        I C@ DUP 46 = IF DROP 1000000 _PDFT-MS ! ELSE
            DUP 48 58 WITHIN 0= IF DROP LEAVE THEN 48 -
            _PDFT-MS @ IF
                _PDFT-MS @ 10 / DUP _PDFT-MS ! * _PDFT-MF +!
            ELSE _PDFT-MI @ 10 * + _PDFT-MI ! THEN
        THEN
    LOOP
    _PDFT-MI @ 1000000 * _PDFT-MF @ +  R> IF NEGATE THEN ;

\ A width in glyph units, in thousandths of the text size.
: _PDFT-WIDTH-OF  ( va vu -- w )  _PDFT-MICRO _PDFT-SCALE @ * 1000000000 / ;

\ A number, through a reference, as an integer: false when it is none.
: _PDFT-NUM  ( va vu type -- n ok? )
    _PDFT-RESOLVE ?DUP IF DROP 2DROP DROP _PDFT-FREE 0 0 EXIT THEN
    DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF PDF-INT -1 ELSE 2DROP 0 0 THEN
    ROT _PDFT-FREE ;

\ =====================================================================
\  Glyph names
\ =====================================================================

VARIABLE _PDFT-GA   VARIABLE _PDFT-GU

\ The known glyph name I, and its character.
: _PDFT-NAME@  ( i -- a u cp )
    CELLS PDF-GLYPH-INDEX + @ DUP 32 RSHIFT PDF-GLYPH-NAMES + COUNT ROT 0xFFFFFFFF AND ;

\ The character of a name the tables know, or 0.
: _PDFT-KNOWN  ( a u -- cp | 0 )
    _PDFT-GU ! _PDFT-GA !
    0 PDF-GLYPH-COUNT 1-
    BEGIN 2DUP > 0= WHILE
        2DUP + 2/ DUP >R _PDFT-NAME@ DROP _PDFT-GA @ _PDFT-GU @ 2SWAP COMPARE
        DUP 0= IF DROP 2DROP R> _PDFT-NAME@ NIP NIP EXIT THEN
        0< IF DROP R> 1- ELSE NIP R> 1+ SWAP THEN
    REPEAT 2DROP 0 ;

\ A ligature named by its letters joined with underscores, or 0.
: _PDFT-JOINED  ( a u -- cp | 0 )
    2DUP S" f_f" COMPARE 0= IF 2DROP 0xFB00 EXIT THEN
    2DUP S" f_i" COMPARE 0= IF 2DROP 0xFB01 EXIT THEN
    2DUP S" f_l" COMPARE 0= IF 2DROP 0xFB02 EXIT THEN
    2DUP S" f_f_i" COMPARE 0= IF 2DROP 0xFB03 EXIT THEN
    2DUP S" f_f_l" COMPARE 0= IF 2DROP 0xFB04 EXIT THEN
    2DUP S" s_t" COMPARE 0= IF 2DROP 0xFB06 EXIT THEN
    2DROP 0 ;

: _PDFT-HEXDIGIT  ( c -- n | -1 )
    DUP 48 58 WITHIN IF 48 - EXIT THEN
    DUP 65 71 WITHIN IF 55 - EXIT THEN
    DUP 97 103 WITHIN IF 87 - EXIT THEN
    DROP -1 ;

\ The U hex digits at A as a number, or -1.
: _PDFT-HEX  ( a u -- n | -1 )
    0 -ROT OVER + SWAP ?DO
        I C@ _PDFT-HEXDIGIT DUP 0< IF NIP UNLOOP EXIT THEN
        SWAP 4 LSHIFT OR
    LOOP ;

\ A character that may be shown: not a surrogate, nor past Unicode.
: _PDFT-VALID  ( cp -- cp | 0 )
    DUP 0xD800 0xE000 WITHIN OVER 0x10FFFF > OR IF DROP 0 THEN ;

\ uniXXXX, its first character; uXXXX to uXXXXXX.  Else 0.
: _PDFT-UNI  ( a u -- cp | 0 )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 117 <> IF 2DROP 0 EXIT THEN
    DUP 7 < 0= IF
        OVER 3 S" uni" COMPARE 0= IF
            DROP 3 + 4 _PDFT-HEX DUP 0< IF DROP 0 THEN _PDFT-VALID EXIT
        THEN
    THEN
    DUP 5 8 WITHIN IF
        1- SWAP 1+ SWAP _PDFT-HEX DUP 0< IF DROP 0 THEN _PDFT-VALID EXIT
    THEN
    2DROP 0 ;

\ The part of A U before the first C.
: _PDFT-UPTO  ( a u c -- a u' )
    _PDFT-C !  DUP 0 ?DO OVER I + C@ _PDFT-C @ = IF DROP I LEAVE THEN LOOP ;

\ A glyph name's character, or 0: its part before a period; a ligature's
\ letters joined, or else its first; a name the tables know; uni or u.
: _PDFT-GLYPH  ( a u -- cp | 0 )
    46 _PDFT-UPTO DUP 0= IF 2DROP 0 EXIT THEN
    2DUP _PDFT-JOINED ?DUP IF NIP NIP EXIT THEN
    95 _PDFT-UPTO
    2DUP _PDFT-KNOWN ?DUP IF NIP NIP EXIT THEN
    _PDFT-UNI ;

\ =====================================================================
\  Streams
\ =====================================================================

CREATE _PDFT-SB-S PDF-BUF-SIZE 7 + ALLOT
: _PDFT-SB  ( -- buf )  _PDFT-SB-S 7 + -8 AND ;

\ The stream a value names, decoded into _PDFT-SB, which is left holding
\ what was decoded for the caller to give back.
: _PDFT-STREAM  ( va vu type -- status )
    _PDFT-SB PDF-BUF-SIZE 0 FILL
    _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    2DROP DROP
    DUP 0= IF DROP PDF-S-DAMAGED EXIT THEN
    DUP _PDFT-SB _PDFT-FILE @ PDF-STREAM SWAP _PDFT-FREE ;

: _PDFT-SB-FREE  ( -- )  _PDFT-SB _PDFT-MSRC PDF-BUF-FREE ;

\ A CMap stream read into the map M: false when there is none to read.
: _PDFT-CMAP  ( va vu type m -- found? status )
    >R _PDFT-STREAM DUP PDF-S-MEMORY = IF R> DROP 0 SWAP EXIT THEN DROP
    _PDFT-SB PDF-BUF.A @ 0= IF R> DROP 0 PDF-S-OK EXIT THEN
    _PDFT-SB PDF-BUF.A @ _PDFT-SB PDF-BUF.U @ _PDFT-MSRC R> PDF-CMAP-PARSE
    _PDFT-SB-FREE  -1 SWAP ;

: _PDFT-TOUNICODE  ( -- status )
    S" ToUnicode" _PDFT-KEY DUP PDF-T-END = IF DROP 2DROP PDF-S-OK EXIT THEN
    _PDFT-F @ _PDFT.TU _PDFT-CMAP SWAP _PDFT-F @ _PDFT.HASTU ! ;

\ =====================================================================
\  Style
\ =====================================================================

VARIABLE _PDFT-SA   VARIABLE _PDFT-SU

\ Whether A U holds SA SU.
: _PDFT-HAS?  ( a u sa su -- flag )
    _PDFT-SU ! _PDFT-SA !
    BEGIN DUP _PDFT-SU @ < 0= WHILE
        OVER _PDFT-SU @ _PDFT-SA @ _PDFT-SU @ COMPARE 0= IF 2DROP -1 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT 2DROP 0 ;

\ Whether A U starts with SA SU.
: _PDFT-STARTS?  ( a u sa su -- flag )
    ROT OVER < IF DROP 2DROP 0 EXIT THEN
    TUCK COMPARE 0= ;

\ The font's name, without its slash and a subset's "ABCDEF+".
: _PDFT-NAME  ( da du -- a u )
    S" BaseFont" 2SWAP PDF-DICT@ PDF-T-NAME <> IF 2DROP 0 0 EXIT THEN
    1- SWAP 1+ SWAP
    DUP 7 > IF OVER 6 + C@ 43 = IF 7 - SWAP 7 + SWAP THEN THEN ;

\ The style a font's name says.
: _PDFT-NAME-STYLE  ( a u -- flags )
    0 >R
    2DUP S" Bold" _PDFT-HAS? >R 2DUP S" bold" _PDFT-HAS? R> OR
    >R 2DUP S" Black" _PDFT-HAS? R> OR
    >R 2DUP S" Heavy" _PDFT-HAS? R> OR >R 2DUP S" Demi" _PDFT-HAS? R> OR
    >R 2DUP S" CMBX" _PDFT-STARTS? R> OR
    IF R> PDF-FONT-BOLD OR >R THEN
    2DUP S" Italic" _PDFT-HAS? >R 2DUP S" Oblique" _PDFT-HAS? R> OR
    >R 2DUP S" CMTI" _PDFT-STARTS? R> OR >R 2DUP S" CMSL" _PDFT-STARTS? R> OR
    IF R> PDF-FONT-ITALIC OR >R THEN
    2DUP S" Courier" _PDFT-HAS? >R 2DUP S" Mono" _PDFT-HAS? R> OR
    >R 2DUP S" CMTT" _PDFT-STARTS? R> OR
    IF R> PDF-FONT-FIXED OR >R THEN
    2DROP R> ;

\ The style the descriptor's flags, weight and angle say; whether it says
\ the font is symbolic is kept.
: _PDFT-DESC-STYLE  ( -- flags )
    0 _PDFT-SYMBOLIC !
    0 S" Flags" _PDFT-XKEY _PDFT-NUM IF
        DUP 1 AND IF SWAP PDF-FONT-FIXED OR SWAP THEN
        DUP 2 AND IF SWAP PDF-FONT-SERIF OR SWAP THEN
        DUP 4 AND OVER 32 AND 0= AND IF -1 _PDFT-SYMBOLIC ! THEN
        DUP 64 AND IF SWAP PDF-FONT-ITALIC OR SWAP THEN
        0x40000 AND IF PDF-FONT-BOLD OR THEN
    ELSE DROP THEN
    S" FontWeight" _PDFT-XKEY _PDFT-NUM IF 600 < 0= IF PDF-FONT-BOLD OR THEN ELSE DROP THEN
    S" ItalicAngle" _PDFT-XKEY _PDFT-NUM IF IF PDF-FONT-ITALIC OR THEN ELSE DROP THEN ;

\ The descriptor of the dictionary DA DU, read into _PDFT-XO.
: _PDFT-DESCRIPTOR  ( da du -- status )
    0 _PDFT-XO !  0 _PDFT-XA !  0 _PDFT-XU !
    S" FontDescriptor" 2SWAP PDF-DICT@ _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    PDF-T-DICT = IF _PDFT-XU ! _PDFT-XA ! ELSE 2DROP THEN
    _PDFT-XO !  PDF-S-OK ;

\ =====================================================================
\  Simple fonts
\ =====================================================================

\ The base encoding a name gives, or 0.
: _PDFT-BASE  ( va vu -- table | 0 )
    2DUP S" WinAnsiEncoding" PDF-NAME= IF 2DROP PDF-ENC-WINANSI EXIT THEN
    2DUP S" MacRomanEncoding" PDF-NAME= IF 2DROP PDF-ENC-MACROMAN EXIT THEN
    2DUP S" StandardEncoding" PDF-NAME= IF 2DROP PDF-ENC-STANDARD EXIT THEN
    2DUP S" PDFDocEncoding" PDF-NAME= IF 2DROP PDF-ENC-PDFDOC EXIT THEN
    2DROP 0 ;

\ Each code's character from a table of 256 two-byte ones.
: _PDFT-BASE!  ( table -- )
    256 0 DO DUP I 2* + W@ I _PDFT-CHAR! LOOP DROP ;

\ Each code its own character, as Latin-1 has it.
: _PDFT-LATIN1!  ( -- )  256 0 DO I I _PDFT-CHAR! LOOP ;

\ After "dup", CODE /NAME of a Type 1 program's encoding.
: _PDFT-T1PUT  ( a u -- a' u' )
    PDF-TOKEN PDF-T-INT <> IF 2DROP EXIT THEN PDF-INT >R
    PDF-TOKEN PDF-T-NAME <> IF 2DROP R> DROP EXIT THEN
    1- SWAP 1+ SWAP _PDFT-GLYPH R>
    DUP 0 256 WITHIN IF _PDFT-CHAR! ELSE 2DROP THEN ;

\ After "/Encoding": StandardEncoding, or "dup CODE /NAME put" to "def".
: _PDFT-T1ENTRIES  ( a u -- found? )
    256 0 DO 0 I _PDFT-CHAR! LOOP
    BEGIN
        PDF-TOKEN DUP PDF-T-END = IF DROP 2DROP 2DROP -1 EXIT THEN
        PDF-T-KEYWORD = IF
            2DUP S" StandardEncoding" COMPARE 0= IF
                2DROP 2DROP PDF-ENC-STANDARD _PDFT-BASE! -1 EXIT
            THEN
            2DUP S" def" COMPARE 0= >R 2DUP S" eexec" COMPARE 0= R> OR IF
                2DROP 2DROP -1 EXIT
            THEN
            S" dup" COMPARE 0= IF _PDFT-T1PUT THEN
        ELSE 2DROP THEN
    AGAIN ;

\ A Type 1 program's clear text, to its "/Encoding".
: _PDFT-T1ENCODING  ( a u -- found? )
    BEGIN
        PDF-TOKEN DUP PDF-T-END = IF DROP 2DROP 2DROP 0 EXIT THEN
        DUP PDF-T-NAME = IF
            DROP S" Encoding" PDF-NAME= IF _PDFT-T1ENTRIES EXIT THEN
        ELSE
            PDF-T-KEYWORD = IF S" eexec" COMPARE 0= IF 2DROP 0 EXIT THEN ELSE 2DROP THEN
        THEN
    AGAIN ;

\ The encoding an embedded Type 1 program sets: false when there is none.
: _PDFT-PROGRAM  ( -- found? status )
    S" FontFile" _PDFT-XKEY DUP PDF-T-END = IF DROP 2DROP 0 PDF-S-OK EXIT THEN
    _PDFT-STREAM DUP PDF-S-MEMORY = IF 0 SWAP EXIT THEN DROP
    _PDFT-SB PDF-BUF.A @ 0= IF 0 PDF-S-OK EXIT THEN
    _PDFT-SB PDF-BUF.A @ _PDFT-SB PDF-BUF.U @ _PDFT-T1ENCODING
    _PDFT-SB-FREE  PDF-S-OK ;

\ The encoding a simple font has of its own.
: _PDFT-OWN-ENCODING  ( -- status )
    _PDFT-DA @ _PDFT-DU @ _PDFT-NAME
    2DUP S" Symbol" _PDFT-STARTS? IF 2DROP PDF-ENC-SYMBOL _PDFT-BASE! PDF-S-OK EXIT THEN
    2DUP S" ZapfDingbats" _PDFT-STARTS? IF 2DROP PDF-ENC-ZAPF _PDFT-BASE! PDF-S-OK EXIT THEN
    2DROP
    _PDFT-F @ _PDFT.HASTU @ 0= IF
        _PDFT-PROGRAM ?DUP IF NIP EXIT THEN
        IF PDF-S-OK EXIT THEN
    THEN
    _PDFT-SYMBOLIC @ IF _PDFT-LATIN1! PDF-S-OK EXIT THEN
    S" Subtype" _PDFT-KEY PDF-T-NAME = IF S" TrueType" PDF-NAME= ELSE 2DROP 0 THEN
    IF PDF-ENC-WINANSI ELSE PDF-ENC-STANDARD THEN _PDFT-BASE!  PDF-S-OK ;

\ /Differences: a code, then the names of that code and those after it.
: _PDFT-DIFFERENCES  ( va vu type -- status )
    _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    PDF-T-ARRAY <> IF 2DROP _PDFT-FREE PDF-S-OK EXIT THEN
    0 _PDFT-I !
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-INT = IF DROP PDF-INT _PDFT-I ! ELSE
        DUP PDF-T-NAME = IF
            DROP 1- SWAP 1+ SWAP _PDFT-GLYPH
            _PDFT-I @ DUP 0 256 WITHIN IF _PDFT-CHAR! ELSE 2DROP THEN
            1 _PDFT-I +!
        ELSE
            DROP 2DROP 2DROP _PDFT-FREE PDF-S-OK EXIT
        THEN THEN
    AGAIN ;

\ The codes' characters: the base encoding, then the differences.
: _PDFT-ENCODING  ( -- status )
    S" Encoding" _PDFT-KEY _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    DUP PDF-T-NAME = IF
        DROP _PDFT-BASE ?DUP IF _PDFT-BASE! ELSE
            _PDFT-OWN-ENCODING ?DUP IF SWAP _PDFT-FREE EXIT THEN
        THEN
        _PDFT-FREE PDF-S-OK EXIT
    THEN
    PDF-T-DICT = IF
        2DUP S" BaseEncoding" 2SWAP PDF-DICT@ PDF-T-NAME = IF _PDFT-BASE ELSE 2DROP 0 THEN
        ?DUP IF _PDFT-BASE! ELSE
            _PDFT-OWN-ENCODING ?DUP IF >R 2DROP _PDFT-FREE R> EXIT THEN
        THEN
        S" Differences" 2SWAP PDF-DICT@ _PDFT-DIFFERENCES
        SWAP _PDFT-FREE EXIT
    THEN
    2DROP _PDFT-FREE _PDFT-OWN-ENCODING ;

VARIABLE _PDFT-WT   VARIABLE _PDFT-WN     \ a standard font's width pairs

\ The standard font a name gives: its width pairs and their count, 0 -1
\ for Courier, whose widths are all 600, or 0 0.
: _PDFT-STANDARD  ( a u -- pairs n )
    2DUP S" Courier" _PDFT-STARTS? IF 2DROP 0 -1 EXIT THEN
    2DUP _PDFT-NAME-STYLE >R
    2DUP S" Helvetica" _PDFT-STARTS? >R 2DUP S" Arial" _PDFT-STARTS? R> OR IF
        2DROP R> PDF-FONT-BOLD AND IF
            PDF-WIDTHS-HELVETICA-BOLD PDF-WIDTHS-HELVETICA-BOLD-N
        ELSE PDF-WIDTHS-HELVETICA PDF-WIDTHS-HELVETICA-N THEN EXIT
    THEN
    S" Times" _PDFT-STARTS? 0= IF R> DROP 0 0 EXIT THEN
    R> DUP PDF-FONT-BOLD AND SWAP PDF-FONT-ITALIC AND
    IF IF PDF-WIDTHS-TIMES-BOLDITALIC PDF-WIDTHS-TIMES-BOLDITALIC-N
       ELSE PDF-WIDTHS-TIMES-ITALIC PDF-WIDTHS-TIMES-ITALIC-N THEN
    ELSE IF PDF-WIDTHS-TIMES-BOLD PDF-WIDTHS-TIMES-BOLD-N
       ELSE PDF-WIDTHS-TIMES-ROMAN PDF-WIDTHS-TIMES-ROMAN-N THEN
    THEN ;

\ A character's width in the standard font's pairs, or -1.
: _PDFT-STDW  ( cp -- w | -1 )
    _PDFT-CP !  0 _PDFT-WN @ 1-
    BEGIN 2DUP > 0= WHILE
        2DUP + 2/ DUP 4 * _PDFT-WT @ + W@ _PDFT-CP @
        2DUP = IF 2DROP 4 * _PDFT-WT @ + 2 + W@ NIP NIP EXIT THEN
        < IF ROT DROP 1+ SWAP ELSE NIP 1- THEN
    REPEAT 2DROP -1 ;

\ The widths of a standard font without /Widths, by each code's character.
: _PDFT-STANDARD-WIDTHS  ( -- )
    _PDFT-DA @ _PDFT-DU @ _PDFT-NAME _PDFT-STANDARD
    DUP -1 = IF 2DROP 256 0 DO 600 I _PDFT-WIDTH! LOOP EXIT THEN
    _PDFT-WN ! _PDFT-WT !
    _PDFT-WN @ 0= IF
        _PDFT-F @ _PDFT.MISSING @ 0= IF 256 0 DO 500 I _PDFT-WIDTH! LOOP THEN EXIT
    THEN
    256 0 DO
        I 4 * _PDFT-F @ _PDFT.TABLES @ + L@ ?DUP IF
            _PDFT-STDW DUP 0< IF DROP 500 THEN I _PDFT-WIDTH!
        THEN
    LOOP ;

\ /FirstChar's code on, the widths of /Widths: false when there are none.
: _PDFT-WIDTHS  ( -- found? status )
    S" FirstChar" _PDFT-KEY _PDFT-NUM 0= IF DROP 0 THEN _PDFT-I !
    S" Widths" _PDFT-KEY _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE 0 R> EXIT THEN
    PDF-T-ARRAY <> IF 2DROP _PDFT-FREE 0 PDF-S-OK EXIT THEN
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-INT = OVER PDF-T-REAL = OR WHILE
        DROP _PDFT-WIDTH-OF
        _PDFT-I @ DUP 0 256 WITHIN IF _PDFT-WIDTH! ELSE 2DROP THEN
        1 _PDFT-I +!
    REPEAT DROP 2DROP 2DROP
    _PDFT-FREE -1 PDF-S-OK ;

\ A Type 3 font's /FontMatrix scale; 0.001, a thousandth, for the rest.
: _PDFT-MATRIX  ( -- )
    1000 _PDFT-SCALE !
    _PDFT-F @ _PDFT.KIND @ _PDFT-TYPE3 <> IF EXIT THEN
    S" FontMatrix" _PDFT-KEY _PDFT-RESOLVE ?DUP IF DROP 2DROP DROP _PDFT-FREE EXIT THEN
    PDF-T-ARRAY = IF
        0 -ROT PDF-ARRAY@ DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF
            _PDFT-MICRO ?DUP IF _PDFT-SCALE ! THEN
        ELSE 2DROP THEN
    ELSE 2DROP THEN
    _PDFT-FREE ;

: _PDFT-SIMPLE-LOAD  ( -- status )
    2048 _PDFT-MSRC MSRC-ALLOC DUP _PDFT-F @ _PDFT.TABLES ! 0= IF PDF-S-MEMORY EXIT THEN
    _PDFT-F @ _PDFT.TABLES @ 2048 0 FILL
    _PDFT-DA @ _PDFT-DU @ _PDFT-DESCRIPTOR ?DUP IF EXIT THEN
    _PDFT-DESC-STYLE _PDFT-STYLE+
    _PDFT-DA @ _PDFT-DU @ _PDFT-NAME _PDFT-NAME-STYLE _PDFT-STYLE+
    _PDFT-ENCODING ?DUP IF EXIT THEN
    _PDFT-MATRIX
    S" MissingWidth" _PDFT-XKEY DUP PDF-T-INT = OVER PDF-T-REAL = OR IF
        DROP _PDFT-WIDTH-OF
    ELSE DROP 2DROP 0 THEN
    DUP _PDFT-F @ _PDFT.MISSING !
    256 0 DO DUP I _PDFT-WIDTH! LOOP DROP
    _PDFT-WIDTHS ?DUP IF NIP EXIT THEN
    0= IF _PDFT-STANDARD-WIDTHS THEN
    PDF-S-OK ;

\ =====================================================================
\  Composite fonts
\ =====================================================================

\ How the font's /Encoding reads codes.
: _PDFT-CODES  ( -- status )
    S" Encoding" _PDFT-KEY DUP PDF-T-NAME = IF
        DROP 1- SWAP 1+ SWAP
        DUP 2 > IF 2DUP + 2 - 2 S" -V" COMPARE 0= IF PDF-FONT-VERTICAL _PDFT-STYLE+ THEN THEN
        2DUP S" Identity-" _PDFT-STARTS? IF 2DROP _PDFT-E-IDENTITY ELSE
        2DUP S" UCS2" _PDFT-HAS? IF 2DROP _PDFT-E-UCS2 ELSE
        2DUP S" UTF16" _PDFT-HAS? IF 2DROP _PDFT-E-UTF16 ELSE
            2DROP _PDFT-E-NAMED
        THEN THEN THEN
        _PDFT-F @ _PDFT.ENC !  PDF-S-OK EXIT
    THEN
    _PDFT-F @ _PDFT.CMAP _PDFT-CMAP ?DUP IF NIP EXIT THEN
    IF _PDFT-E-EMBEDDED ELSE _PDFT-E-IDENTITY THEN _PDFT-F @ _PDFT.ENC !
    PDF-S-OK ;

\ The CIDFont: the first of /DescendantFonts, read into _PDFT-CO.
: _PDFT-CIDFONT  ( -- status )
    0 _PDFT-CO !  0 _PDFT-CA !  0 _PDFT-CU !
    S" DescendantFonts" _PDFT-KEY _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    >R ROT _PDFT-AO ! R>
    PDF-T-ARRAY <> IF 2DROP PDF-S-DAMAGED EXIT THEN
    0 -ROT PDF-ARRAY@ _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDFT-FREE PDF-S-DAMAGED EXIT THEN
    _PDFT-CU ! _PDFT-CA ! _PDFT-CO !  PDF-S-OK ;

\ Widths of CIDs from FIRST to LAST, joined to the pending range when they
\ follow it with the same width.
VARIABLE _PDFT-PF   VARIABLE _PDFT-PL   VARIABLE _PDFT-PW   VARIABLE _PDFT-PENDING

: _PDFT-FLUSH  ( -- ok? )
    _PDFT-PENDING @ 0= IF -1 EXIT THEN  0 _PDFT-PENDING !
    _PDFT-PF @ _PDFT-PL @ _PDFT-PW @ _PDFT-F @ _PDFT.W PDF-CMAP-ADD ;

: _PDFT-W+  ( first last w -- ok? )
    _PDFT-PENDING @ IF
        DUP _PDFT-PW @ = 3 PICK _PDFT-PL @ 1+ = AND IF DROP _PDFT-PL ! DROP -1 EXIT THEN
    THEN
    _PDFT-FLUSH 0= IF DROP 2DROP 0 EXIT THEN
    _PDFT-PW ! _PDFT-PL ! _PDFT-PF !  -1 _PDFT-PENDING !  -1 ;

\ After a CID, an array of widths for it and those after it.
: _PDFT-W-LIST  ( aa au -- status )
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE DUP PDF-T-INT = OVER PDF-T-REAL = OR WHILE
        DROP _PDFT-WIDTH-OF _PDFT-I @ DUP ROT _PDFT-W+ 0= IF 2DROP PDF-S-MEMORY EXIT THEN
        1 _PDFT-I +!
    REPEAT DROP 2DROP 2DROP PDF-S-OK ;

\ /W: "c [w ...]" and "first last w".
: _PDFT-W  ( va vu type -- status )
    _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    PDF-T-ARRAY <> IF 2DROP _PDFT-FREE PDF-S-OK EXIT THEN
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-VALUE PDF-T-INT <> IF 2DROP 2DROP _PDFT-FREE PDF-S-OK EXIT THEN
        PDF-INT _PDFT-I !
        PDF-VALUE DUP PDF-T-ARRAY = IF
            DROP _PDFT-W-LIST ?DUP IF >R 2DROP _PDFT-FREE R> EXIT THEN
        ELSE DUP PDF-T-INT = IF
            DROP PDF-INT _PDFT-J !
            PDF-VALUE DUP PDF-T-INT = OVER PDF-T-REAL = OR 0= IF
                DROP 2DROP 2DROP _PDFT-FREE PDF-S-OK EXIT
            THEN
            DROP _PDFT-WIDTH-OF _PDFT-I @ _PDFT-J @ ROT _PDFT-W+ 0= IF
                2DROP _PDFT-FREE PDF-S-MEMORY EXIT
            THEN
        ELSE DROP 2DROP 2DROP _PDFT-FREE PDF-S-OK EXIT THEN THEN
    AGAIN ;

: _PDFT-TYPE0-LOAD  ( -- status )
    _PDFT-MSRC _PDFT-F @ _PDFT.W PDF-CMAP-INIT
    _PDFT-CODES ?DUP IF EXIT THEN
    _PDFT-CIDFONT ?DUP IF EXIT THEN
    _PDFT-CA @ _PDFT-CU @ _PDFT-DESCRIPTOR ?DUP IF EXIT THEN
    _PDFT-DESC-STYLE _PDFT-STYLE+
    _PDFT-DA @ _PDFT-DU @ _PDFT-NAME _PDFT-NAME-STYLE _PDFT-STYLE+
    1000 _PDFT-SCALE !
    S" DW" _PDFT-CA @ _PDFT-CU @ PDF-DICT@ _PDFT-NUM 0= IF DROP 1000 THEN
    _PDFT-F @ _PDFT.MISSING !
    0 _PDFT-PENDING !
    S" W" _PDFT-CA @ _PDFT-CU @ PDF-DICT@ _PDFT-W ?DUP IF EXIT THEN
    _PDFT-FLUSH 0= IF PDF-S-MEMORY EXIT THEN
    _PDFT-F @ _PDFT.W PDF-CMAP-SEAL  PDF-S-OK ;

\ =====================================================================
\  Loading
\ =====================================================================

\ PDF-FONT-FREE ( font -- )   Give back everything the font holds.
: PDF-FONT-FREE  ( font -- )
    DUP _PDFT.TABLES @ ?DUP IF 2048 2 PICK _PDFT.MSRC @ MSRC-FREE THEN
    DUP _PDFT.CACHE @ ?DUP IF _PDFT-CACHE-BYTES 2 PICK _PDFT.MSRC @ MSRC-FREE THEN
    DUP _PDFT.TU PDF-CMAP-FREE  DUP _PDFT.CMAP PDF-CMAP-FREE  DUP _PDFT.W PDF-CMAP-FREE
    PDF-FONT-SIZE 0 FILL ;

\ Give back the dictionaries read while loading.
: _PDFT-DONE  ( -- )
    _PDFT-CO @ _PDFT-FREE  _PDFT-AO @ _PDFT-FREE  _PDFT-XO @ _PDFT-FREE
    _PDFT-DO @ _PDFT-FREE
    0 _PDFT-CO !  0 _PDFT-AO !  0 _PDFT-XO !  0 _PDFT-DO ! ;

\ PDF-FONT-LOAD ( va vu type file font -- status )
\   Read the font dictionary a value gives, through a reference.
: PDF-FONT-LOAD  ( va vu type file font -- status )
    DUP _PDFT-F !  PDF-FONT-SIZE 0 FILL  DUP _PDFT-FILE !
    PDF-FILE-MSRC _PDFT-F @ _PDFT.MSRC !
    0 _PDFT-CO !  0 _PDFT-AO !  0 _PDFT-XO !  0 _PDFT-DO !
    _PDFT-RESOLVE ?DUP IF >R 2DROP DROP _PDFT-FREE R> EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDFT-FREE PDF-S-DAMAGED EXIT THEN
    _PDFT-DU ! _PDFT-DA ! _PDFT-DO !
    S" Subtype" _PDFT-KEY PDF-T-NAME = IF
        2DUP S" Type0" PDF-NAME= IF 2DROP _PDFT-TYPE0 ELSE
        S" Type3" PDF-NAME= IF _PDFT-TYPE3 ELSE _PDFT-SIMPLE THEN THEN
    ELSE 2DROP _PDFT-SIMPLE THEN
    _PDFT-F @ _PDFT.KIND !
    _PDFT-TOUNICODE ?DUP 0= IF
        _PDFT-F @ _PDFT.KIND @ _PDFT-TYPE0 = IF _PDFT-TYPE0-LOAD ELSE _PDFT-SIMPLE-LOAD THEN
    THEN
    ?DUP 0= IF
        _PDFT-CACHE-BYTES _PDFT-MSRC MSRC-ALLOC DUP _PDFT-F @ _PDFT.CACHE !
        ?DUP IF _PDFT-CACHE-BYTES 0 FILL PDF-S-OK ELSE PDF-S-MEMORY THEN
    THEN
    _PDFT-DONE
    DUP IF _PDFT-F @ PDF-FONT-FREE THEN ;

: PDF-FONT-STYLE  ( font -- flags )  _PDFT.STYLE @ ;

\ =====================================================================
\  Codes
\ =====================================================================

\ PDF-FONT-NEXT ( a u font -- a' u' code n )   A string's next code.
: PDF-FONT-NEXT  ( a u font -- a' u' code n )
    DUP _PDFT.KIND @ _PDFT-TYPE0 <> IF
        DROP OVER C@ >R  SWAP 1+ SWAP 1-  R> 1 EXIT
    THEN
    DUP _PDFT.ENC @ _PDFT-E-IDENTITY = IF OVER 1 > IF
        DROP OVER DUP C@ 8 LSHIFT SWAP 1+ C@ OR >R  SWAP 2 + SWAP 2 -  R> 2 EXIT
    THEN THEN
    DUP _PDFT.ENC @ CASE
        _PDFT-E-EMBEDDED OF >R 2DUP R> _PDFT.CMAP PDF-CMAP-BYTES ENDOF
        _PDFT-E-NAMED OF
            DUP _PDFT.HASTU @ IF >R 2DUP R> _PDFT.TU PDF-CMAP-BYTES ELSE DROP 2 THEN
        ENDOF
        _PDFT-E-UTF16 OF
            DROP OVER C@ 0xD8 0xDC WITHIN OVER 4 < 0= AND IF 4 ELSE 2 THEN
        ENDOF
        >R DROP 2 R>
    ENDCASE
    OVER MIN 1 MAX                                     ( a u n )
    0 OVER 0 DO 8 LSHIFT 3 PICK I + C@ OR LOOP         ( a u n code )
    >R >R  R@ - SWAP R@ + SWAP  R> R> SWAP ;

VARIABLE _PDFT-OUT

: _PDFT-PUT  ( a u -- ok? )  _PDFT-OUT @ _PDFT-MSRC PDF-BUF-APPEND ;

\ A ligature's letters: ff, fi, fl, ffi, ffl, and st for both s-t forms.
: _PDFT-LIGATURE+  ( cp -- ok? )
    0xFB00 -
    DUP 0= IF DROP S" ff" _PDFT-PUT EXIT THEN
    DUP 1 = IF DROP S" fi" _PDFT-PUT EXIT THEN
    DUP 2 = IF DROP S" fl" _PDFT-PUT EXIT THEN
    DUP 3 = IF DROP S" ffi" _PDFT-PUT EXIT THEN
    4 = IF S" ffl" _PDFT-PUT EXIT THEN
    S" st" _PDFT-PUT ;

\ One character onto the output.
: _PDFT-CHAR+  ( cp -- ok? )
    DUP 0xFB00 0xFB07 WITHIN IF _PDFT-LIGATURE+ EXIT THEN
    DUP 32 < IF
        DUP 9 = OVER 10 = OR SWAP 13 = OR IF 32 ELSE -1 EXIT THEN
    THEN
    _PDFT-VALID ?DUP 0= IF 0xFFFD THEN
    _PDFT-OUT @ _PDFT-MSRC PDF-CHAR+ ;

VARIABLE _PDFT-DELTA

\ The characters a ToUnicode lookup gave, the last counted up by DELTA.
: _PDFT-CHARS+  ( a n delta -- ok? )
    _PDFT-DELTA !
    DUP 0= IF 2DROP -1 EXIT THEN
    1- 4 * OVER + SWAP
    BEGIN 2DUP > WHILE
        DUP L@ _PDFT-CHAR+ 0= IF 2DROP 0 EXIT THEN 4 +
    REPEAT DROP
    L@ _PDFT-DELTA @ + _PDFT-CHAR+ ;

\ PDF-FONT-TEXT+ ( code font buf -- ok? )   The code's characters, UTF-8.
: PDF-FONT-TEXT+  ( code font buf -- ok? )
    _PDFT-OUT !  _PDFT-F !
    _PDFT-F @ _PDFT.HASTU @ IF
        DUP _PDFT-F @ _PDFT.TU PDF-CMAP-LOOKUP IF >R ROT DROP R> _PDFT-CHARS+ EXIT THEN
    THEN
    _PDFT-F @ _PDFT.KIND @ _PDFT-TYPE0 <> IF
        255 AND 4 * _PDFT-F @ _PDFT.TABLES @ + L@ ?DUP 0= IF 0xFFFD THEN
        _PDFT-CHAR+ EXIT
    THEN
    _PDFT-F @ _PDFT.ENC @ DUP _PDFT-E-UCS2 = SWAP _PDFT-E-UTF16 = OR IF
        DUP 0xFFFF > IF
            DUP 16 RSHIFT 0xD800 - 10 LSHIFT SWAP 0xFFFF AND 0xDC00 - + 0x10000 +
        THEN
        _PDFT-CHAR+ EXIT
    THEN
    DROP 0xFFFD _PDFT-CHAR+ ;

\ PDF-FONT-WIDTH ( code font -- w )   In thousandths of the text size.
: PDF-FONT-WIDTH  ( code font -- w )
    DUP _PDFT.KIND @ _PDFT-TYPE0 <> IF
        _PDFT.TABLES @ 1024 + SWAP 255 AND 4 * + L@ _PDFT-SIGNED EXIT
    THEN
    >R
    R@ _PDFT.ENC @ DUP _PDFT-E-UCS2 = SWAP _PDFT-E-UTF16 = OR IF
        DROP R> _PDFT.MISSING @ EXIT
    THEN
    R@ _PDFT.ENC @ _PDFT-E-EMBEDDED = IF
        R@ _PDFT.CMAP PDF-CMAP-LOOKUP IF ROT L@ + NIP ELSE 0 THEN
    THEN
    R@ _PDFT.W PDF-CMAP-LOOKUP IF 2DROP L@ _PDFT-SIGNED ELSE R@ _PDFT.MISSING @ THEN
    R> DROP ;

\ =====================================================================
\  Codes kept
\ =====================================================================

\ A code's characters, written into memory that never needs to grow: at
\ most 255 characters of three bytes and one of four.
CREATE _PDFT-GA-S 1024 ALLOT
CREATE _PDFT-GB-S PDF-BUF-SIZE 7 + ALLOT
: _PDFT-GB  ( -- buf )  _PDFT-GB-S 7 + -8 AND ;
_PDFT-GA-S _PDFT-GB PDF-BUF.A !  1024 _PDFT-GB PDF-BUF.CAP !

: _PDFT-SLOT  ( code font -- e )
    _PDFT.CACHE @ SWAP DUP 8 RSHIFT XOR 255 AND _PDFT-KEPT * + ;

\ PDF-FONT-GLYPH ( code font -- a u w )   The code's characters and width.
: PDF-FONT-GLYPH  ( code font -- a u w )
    2DUP _PDFT-SLOT DUP L@ 3 PICK 1+ = IF
        NIP NIP DUP 9 + OVER 8 + C@ ROT 4 + L@ _PDFT-SIGNED EXIT
    THEN
    >R
    0 _PDFT-GB PDF-BUF.U !
    2DUP _PDFT-GB PDF-FONT-TEXT+ DROP
    OVER SWAP PDF-FONT-WIDTH
    _PDFT-GB PDF-BUF.U @ 15 > IF
        R> DROP NIP _PDFT-GA-S _PDFT-GB PDF-BUF.U @ ROT EXIT
    THEN
    SWAP 1+ R@ L!  DUP R@ 4 + L!
    _PDFT-GB PDF-BUF.U @ R@ 8 + C!
    _PDFT-GA-S R@ 9 + _PDFT-GB PDF-BUF.U @ MOVE
    R> 9 + _PDFT-GB PDF-BUF.U @ ROT ;

\ =====================================================================
\  Sets of fonts
\ =====================================================================

\ A set: its fonts (object number, font or 0), and its memory source.
: _PDFS.BUF   ( s -- buf )      ;
: _PDFS.MSRC  ( s -- a )   24 + ;
32 CONSTANT PDF-FONTS-SIZE

VARIABLE _PDFS-S   VARIABLE _PDFS-FILE   VARIABLE _PDFS-NUM   VARIABLE _PDFS-MS
CREATE _PDFS-E 16 ALLOT

: _PDFS-MSRC  ( -- msrc )  _PDFS-S @ _PDFS.MSRC @ ;

\ PDF-FONTS-GET ( va vu type file fonts -- font status )
\   The font a value gives, read once by its object; 0 for one that
\   cannot be read.
: PDF-FONTS-GET  ( va vu type file fonts -- font status )
    _PDFS-S !  _PDFS-FILE !  0 _PDFS-NUM !
    _PDFS-FILE @ PDF-FILE-MSRC _PDFS-S @ _PDFS.MSRC !
    DUP PDF-T-REF = IF
        >R 2DUP PDF-REF@ DROP _PDFS-NUM ! R>
        _PDFS-S @ _PDFS.BUF DUP PDF-BUF.A @ SWAP PDF-BUF.U @ 16 / 0 ?DO
            DUP I 16 * + @ _PDFS-NUM @ = IF
                I 16 * + 8 + @ NIP NIP NIP PDF-S-OK UNLOOP EXIT
            THEN
        LOOP DROP
    THEN
    PDF-FONT-SIZE _PDFS-MSRC MSRC-ALLOC ?DUP 0= IF DROP 2DROP 0 PDF-S-MEMORY EXIT THEN
    DUP >R _PDFS-FILE @ SWAP PDF-FONT-LOAD
    ?DUP IF
        R> PDF-FONT-SIZE _PDFS-MSRC MSRC-FREE
        DUP PDF-S-MEMORY = IF 0 SWAP EXIT THEN DROP 0
    ELSE R> THEN
    _PDFS-NUM @ _PDFS-E !  DUP _PDFS-E 8 + !
    _PDFS-E 16 _PDFS-S @ _PDFS.BUF _PDFS-MSRC PDF-BUF-APPEND 0= IF
        ?DUP IF DUP PDF-FONT-FREE PDF-FONT-SIZE _PDFS-MSRC MSRC-FREE THEN
        0 PDF-S-MEMORY EXIT
    THEN
    PDF-S-OK ;

\ PDF-FONTS-FREE ( fonts -- )   Give back every font the set holds.
: PDF-FONTS-FREE  ( fonts -- )
    DUP _PDFS.MSRC @ ?DUP IF
        _PDFS-MS !
        DUP _PDFS.BUF DUP PDF-BUF.A @ SWAP PDF-BUF.U @ 16 / 0 ?DO
            DUP I 16 * + 8 + @ ?DUP IF DUP PDF-FONT-FREE PDF-FONT-SIZE _PDFS-MS @ MSRC-FREE THEN
        LOOP DROP
        DUP _PDFS.BUF _PDFS-MS @ PDF-BUF-FREE
    THEN
    PDF-FONTS-SIZE 0 FILL ;
