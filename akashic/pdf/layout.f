\ =================================================================
\  layout.f  —  a page's runs of text as a document's blocks
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-LAYOUT-, PDF-BLOCK- (public),
\                               _PDLY- (private)
\  Depends on: pdf/filter.f, pdf/page.f, pdf/content.f, pdf/font.f,
\              text/text-style.f, media/document.f
\
\  Public API:
\   PDF-LAYOUT-SIZE     ( -- bytes )                     a layout's record
\   PDF-LAYOUT-READ     ( page content layout -- status )
\   PDF-LAYOUT-FREE     ( layout -- )
\   PDF-LAYOUT-BLOCKS   ( layout -- n )
\   PDF-LAYOUT-BLOCK    ( i layout -- block )
\   PDF-BLOCK-KIND      ( block -- kind level )
\   PDF-BLOCK-ITEM      ( block -- kind number width )
\   PDF-BLOCK-TOP       ( block -- y )
\   PDF-BLOCK-TEXT      ( block layout -- a u )
\   PDF-BLOCK-MEANINGS  ( block layout -- a )
\
\  PDF-LAYOUT-READ lays out the runs PDF-CONTENT-READ read from PAGE as
\  blocks of a document, in the order the content shows them, which is
\  the order producers write text in.  Runs that follow on one baseline,
\  moving right, make a line, with a space where the gap between them is
\  a word's; artifacts are left out.  Lines make a paragraph while they
\  keep its size and its kind of font, follow at its line spacing, and
\  neither indent its first line nor follow a short last line.  A word
\  split by a hyphen at a line's end is joined.
\
\  A paragraph of up to three lines whose text is larger than the page's
\  body text, or a single bold line of it, is a heading: level 1 at 1.6
\  times the body's size, 2 at 1.3, 3 at 1.15, 4 for a bold line.  Lines
\  in a fixed-pitch font make code, a line each.  A paragraph that starts
\  with a bullet, or a number or letter followed by "." or ")", is a list
\  item, its marker kept as the item's kind, number and width.  A line of
\  digits alone that is the page's topmost or lowest is its number, left
\  out.
\
\  Kinds and item kinds are the document's (media/document.f), and a
\  block's text has a meaning a byte (text/text-style.f): strong for bold
\  text, emphasis for italic, code for fixed-pitch text within prose.
\  Points are in the page's default space, 16.16.
\
\  Memory comes from the content's memory source.  One call runs at a
\  time.
\ =================================================================

PROVIDED akashic-pdf-layout

REQUIRE filter.f
REQUIRE page.f
REQUIRE content.f
REQUIRE font.f
REQUIRE ../text/text-style.f
REQUIRE ../media/document.f

\ The record: its memory source, the blocks, their text and meanings.
: _PDLY.MSRC    ( l -- a )        ;
: _PDLY.BLOCKS  ( l -- buf )  8 + ;
: _PDLY.TEXT    ( l -- buf ) 32 + ;
: _PDLY.MEAN    ( l -- buf ) 56 + ;
80 CONSTANT PDF-LAYOUT-SIZE

\ A block: kind, level, item kind, number and width, top, text offset
\ and length.
64 CONSTANT _PDLY-BLOCK

: PDF-LAYOUT-BLOCKS  ( layout -- n )  _PDLY.BLOCKS PDF-BUF.U @ _PDLY-BLOCK / ;
: PDF-LAYOUT-BLOCK   ( i layout -- block )  _PDLY.BLOCKS PDF-BUF.A @ SWAP _PDLY-BLOCK * + ;
: PDF-BLOCK-KIND     ( block -- kind level )  DUP @ SWAP 8 + @ ;
: PDF-BLOCK-ITEM     ( block -- kind number width )  DUP 16 + @ OVER 24 + @ ROT 32 + @ ;
: PDF-BLOCK-TOP      ( block -- y )  40 + @ ;
: PDF-BLOCK-TEXT     ( block layout -- a u )  _PDLY.TEXT PDF-BUF.A @ OVER 48 + @ + SWAP 56 + @ ;
: PDF-BLOCK-MEANINGS ( block layout -- a )  _PDLY.MEAN PDF-BUF.A @ SWAP 48 + @ + ;

VARIABLE _PDLY-L     \ the layout
VARIABLE _PDLY-C     \ the content
VARIABLE _PDLY-MS    \ the memory source

: _PDLY-APPEND  ( a u buf -- ok? )  _PDLY-MS @ PDF-BUF-APPEND ;

\ Add U bytes of M to a buffer.
: _PDLY-FILL+  ( u m buf -- ok? )
    >R OVER R@ PDF-BUF.U @ + R@ _PDLY-MS @ PDF-BUF-GROW 0= IF 2DROP R> DROP 0 EXIT THEN
    OVER R@ PDF-BUF.A @ R@ PDF-BUF.U @ + SWAP ROT FILL
    R> PDF-BUF.U +!  -1 ;

\ Buffers kept while laying out: the lines, their text and meanings, and
\ a count of sizes.
CREATE _PDLY-BUFS-S 4 24 * 7 + ALLOT
: _PDLY-LINES  ( -- buf )  _PDLY-BUFS-S 7 + -8 AND ;
: _PDLY-LTEXT  ( -- buf )  _PDLY-LINES 24 + ;
: _PDLY-LMEAN  ( -- buf )  _PDLY-LINES 48 + ;
: _PDLY-HIST   ( -- buf )  _PDLY-LINES 72 + ;

\ =====================================================================
\  Lines
\ =====================================================================

\ A line: start, end, baseline, size, what all its runs share, its text.
: _PDLY.X0  ( ln -- a )      ;
: _PDLY.X1  ( ln -- a )   8 + ;
: _PDLY.Y   ( ln -- a )  16 + ;
: _PDLY.SZ  ( ln -- a )  24 + ;
: _PDLY.FL  ( ln -- a )  32 + ;
: _PDLY.TO  ( ln -- a )  40 + ;
: _PDLY.TU  ( ln -- a )  48 + ;
56 CONSTANT _PDLY-LINE

1 CONSTANT _PDLY-F-BOLD   2 CONSTANT _PDLY-F-FIXED   4 CONSTANT _PDLY-F-ROTATED

: _PDLY-NLINES  ( -- n )  _PDLY-LINES PDF-BUF.U @ _PDLY-LINE / ;
: _PDLY-LINE@   ( i -- ln )  _PDLY-LINE * _PDLY-LINES PDF-BUF.A @ + ;
: _PDLY-LTEXT@  ( ln -- a u )  _PDLY-LTEXT PDF-BUF.A @ OVER _PDLY.TO @ + SWAP _PDLY.TU @ ;
: _PDLY-LMEAN@  ( ln -- a )  _PDLY-LMEAN PDF-BUF.A @ SWAP _PDLY.TO @ + ;

CREATE _PDLY-NEW _PDLY-LINE ALLOT     \ the line being built
VARIABLE _PDLY-OPEN?

\ A run's facts.
VARIABLE _PDLY-RX0  VARIABLE _PDLY-RY0  VARIABLE _PDLY-RX1  VARIABLE _PDLY-RY1
VARIABLE _PDLY-RSZ  VARIABLE _PDLY-RST

: _PDLY-RUN@  ( run -- )
    DUP PDF-RUN-START _PDLY-RY0 ! _PDLY-RX0 !
    DUP PDF-RUN-END _PDLY-RY1 ! _PDLY-RX1 !
    DUP PDF-RUN-SIZE _PDLY-RSZ !  PDF-RUN-STYLE _PDLY-RST ! ;

: _PDLY-MEANING  ( style -- meaning )
    DUP PDF-FONT-FIXED AND IF DROP TSTY-CODE EXIT THEN
    DUP PDF-FONT-BOLD AND IF DROP TSTY-STRONG EXIT THEN
    PDF-FONT-ITALIC AND IF TSTY-EMPHASIS ELSE TSTY-PLAIN THEN ;

\ The flags a run gives a line.
: _PDLY-RFLAGS  ( -- flags )
    0  _PDLY-RST @ PDF-FONT-BOLD AND IF _PDLY-F-BOLD OR THEN
    _PDLY-RST @ PDF-FONT-FIXED AND IF _PDLY-F-FIXED OR THEN
    _PDLY-RY1 @ _PDLY-RY0 @ - ABS _PDLY-RSZ @ 4 / > IF _PDLY-F-ROTATED OR THEN ;

\ Text onto the line, every byte with MEANING.
: _PDLY-TEXT+  ( a u meaning -- ok? )
    >R DUP R> _PDLY-LMEAN _PDLY-FILL+ >R  _PDLY-LTEXT _PDLY-APPEND R> AND ;

: _PDLY-SPACE+  ( -- ok? )  S"  " TSTY-PLAIN _PDLY-TEXT+ ;

: _PDLY-ENDS-SPACE?  ( -- flag )
    _PDLY-LTEXT PDF-BUF.U @ _PDLY-NEW _PDLY.TO @ - 0= IF -1 EXIT THEN
    _PDLY-LTEXT DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + 1- C@ 32 = ;

\ Close the line being built, keeping it when it has text.
: _PDLY-CLOSE  ( -- ok? )
    _PDLY-OPEN? @ 0= IF -1 EXIT THEN  0 _PDLY-OPEN? !
    _PDLY-LTEXT PDF-BUF.U @ _PDLY-NEW _PDLY.TO @ - DUP _PDLY-NEW _PDLY.TU !
    0= IF -1 EXIT THEN
    _PDLY-NEW _PDLY-LINE _PDLY-LINES _PDLY-APPEND ;

\ Whether the run continues the line: on its baseline, moving right.
: _PDLY-JOINS?  ( -- flag )
    _PDLY-OPEN? @ 0= IF 0 EXIT THEN
    _PDLY-NEW _PDLY.FL @ _PDLY-F-ROTATED AND IF 0 EXIT THEN
    _PDLY-RFLAGS _PDLY-F-ROTATED AND IF 0 EXIT THEN
    _PDLY-NEW _PDLY.SZ @ _PDLY-RSZ @ MAX                      ( size )
    _PDLY-RY0 @ _PDLY-NEW _PDLY.Y @ - ABS OVER 2 * 5 / > IF DROP 0 EXIT THEN
    _PDLY-RX0 @ _PDLY-NEW _PDLY.X1 @ ROT 2/ - < 0= ;

\ A run, onto the line it continues or a new one.
: _PDLY-RUN+  ( run -- ok? )
    DUP _PDLY-RUN@
    _PDLY-JOINS? IF
        _PDLY-RX0 @ _PDLY-NEW _PDLY.X1 @ -
        _PDLY-NEW _PDLY.SZ @ _PDLY-RSZ @ MAX 3 * 20 / > IF
            _PDLY-ENDS-SPACE? 0= IF
                DUP _PDLY-C @ PDF-RUN-TEXT DROP C@ 32 <> IF
                    _PDLY-SPACE+ 0= IF DROP 0 EXIT THEN
                THEN
            THEN
        THEN
        _PDLY-RX1 @ _PDLY-NEW _PDLY.X1 @ MAX _PDLY-NEW _PDLY.X1 !
        _PDLY-NEW _PDLY.SZ @ _PDLY-RSZ @ MAX _PDLY-NEW _PDLY.SZ !
        _PDLY-NEW _PDLY.FL @ _PDLY-RFLAGS AND _PDLY-NEW _PDLY.FL !
    ELSE
        _PDLY-CLOSE 0= IF DROP 0 EXIT THEN
        -1 _PDLY-OPEN? !
        _PDLY-RX0 @ _PDLY-NEW _PDLY.X0 !  _PDLY-RX1 @ _PDLY-NEW _PDLY.X1 !
        _PDLY-RY0 @ _PDLY-NEW _PDLY.Y !  _PDLY-RSZ @ _PDLY-NEW _PDLY.SZ !
        _PDLY-RFLAGS _PDLY-NEW _PDLY.FL !
        _PDLY-LTEXT PDF-BUF.U @ _PDLY-NEW _PDLY.TO !
    THEN
    _PDLY-C @ PDF-RUN-TEXT _PDLY-RST @ _PDLY-MEANING _PDLY-TEXT+ ;

: _PDLY-MAKE-LINES  ( -- ok? )
    0 _PDLY-OPEN? !
    _PDLY-C @ PDF-CONTENT-RUNS 0 ?DO
        I _PDLY-C @ PDF-CONTENT-RUN
        DUP PDF-RUN-STYLE PDF-RUN-ARTIFACT AND IF DROP ELSE
            _PDLY-RUN+ 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _PDLY-CLOSE ;

\ =====================================================================
\  What the page's text is like
\ =====================================================================

VARIABLE _PDLY-BODY      \ the body text's size
VARIABLE _PDLY-SPACING   \ its baselines' distance
VARIABLE _PDLY-RIGHT     \ where its lines end, the furthest
VARIABLE _PDLY-YMIN      \ the lowest baseline
VARIABLE _PDLY-YMAX      \ the highest

CREATE _PDLY-PAIR 16 ALLOT

\ Count WEIGHT for KEY.
: _PDLY-COUNT+  ( weight key -- ok? )
    _PDLY-HIST PDF-BUF.A @ _PDLY-HIST PDF-BUF.U @ 16 / 0 ?DO
        DUP I 16 * + @ 2 PICK = IF
            I 16 * + 8 + NIP +!  -1 UNLOOP EXIT
        THEN
    LOOP DROP
    _PDLY-PAIR !  _PDLY-PAIR 8 + !  _PDLY-PAIR 16 _PDLY-HIST _PDLY-APPEND ;

VARIABLE _PDLY-BK   VARIABLE _PDLY-BC

\ The key counted most, or -1; the count is emptied.
: _PDLY-MOST  ( -- key )
    -1 _PDLY-BK !  0 _PDLY-BC !
    _PDLY-HIST PDF-BUF.A @ _PDLY-HIST PDF-BUF.U @ 16 / 0 ?DO
        DUP I 16 * + DUP 8 + @ _PDLY-BC @ > IF
            DUP @ _PDLY-BK !  8 + @ _PDLY-BC !
        ELSE DROP THEN
    LOOP DROP
    0 _PDLY-HIST PDF-BUF.U !  _PDLY-BK @ ;

\ Half points: a key for a size or a distance.
: _PDLY-KEY    ( f -- key )  0x4000 + 15 RSHIFT ;
: _PDLY-UNKEY  ( key -- f )  15 LSHIFT ;

: _PDLY-BODY?  ( ln -- flag )
    DUP _PDLY.FL @ _PDLY-F-ROTATED AND IF DROP 0 EXIT THEN
    _PDLY.SZ @ _PDLY-BODY @ - ABS _PDLY-BODY @ 10 / > 0= ;

\ The body text's size, by the text in each size; its lines' furthest
\ end; and its baselines' commonest distance.
: _PDLY-MEASURE  ( -- ok? )
    _PDLY-NLINES 0 ?DO
        I _PDLY-LINE@ DUP _PDLY.FL @ _PDLY-F-ROTATED AND IF DROP ELSE
            DUP _PDLY.TU @ SWAP _PDLY.SZ @ _PDLY-KEY _PDLY-COUNT+
            0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _PDLY-MOST DUP 0< IF DROP 10 16 LSHIFT ELSE _PDLY-UNKEY THEN _PDLY-BODY !
    0 _PDLY-RIGHT !
    1 62 LSHIFT DUP _PDLY-YMIN !  NEGATE _PDLY-YMAX !
    _PDLY-NLINES 0 ?DO
        I _PDLY-LINE@ _PDLY.Y @
        DUP _PDLY-YMIN @ MIN _PDLY-YMIN !  _PDLY-YMAX @ MAX _PDLY-YMAX !
    LOOP
    _PDLY-NLINES 0 ?DO
        I _PDLY-LINE@ DUP _PDLY-BODY? IF _PDLY.X1 @ _PDLY-RIGHT @ MAX _PDLY-RIGHT ! ELSE DROP THEN
    LOOP
    _PDLY-NLINES 1 > IF
        _PDLY-NLINES 1 DO
            I 1- _PDLY-LINE@ I _PDLY-LINE@
            OVER _PDLY-BODY? OVER _PDLY-BODY? AND IF
                _PDLY.Y @ SWAP _PDLY.Y @ SWAP -
                DUP 0> OVER _PDLY-BODY @ 3 * < AND IF
                    1 SWAP _PDLY-KEY _PDLY-COUNT+ 0= IF 0 UNLOOP EXIT THEN
                ELSE DROP THEN
            ELSE 2DROP THEN
        LOOP
    THEN
    _PDLY-MOST DUP 0< IF DROP _PDLY-BODY @ 6 * 5 / ELSE _PDLY-UNKEY THEN _PDLY-SPACING !
    -1 ;

\ =====================================================================
\  Blocks
\ =====================================================================

\ The block being built.
CREATE _PDLY-BNEW _PDLY-BLOCK ALLOT
VARIABLE _PDLY-BOPEN?
VARIABLE _PDLY-BSZ       \ its size
VARIABLE _PDLY-BFL       \ what all its lines share
VARIABLE _PDLY-BLEFT     \ its lines' leftmost start
VARIABLE _PDLY-BLINES    \ how many lines it has
VARIABLE _PDLY-PREV      \ its last line
VARIABLE _PDLY-ITEM-X    \ where a list item's text starts

: _PDLY-BTEXT-U  ( -- u )  _PDLY-L @ _PDLY.TEXT PDF-BUF.U @ ;

\ Text onto the block, every byte with MEANING.
: _PDLY-BTEXT+  ( a u meaning -- ok? )
    >R DUP R> _PDLY-L @ _PDLY.MEAN _PDLY-FILL+ >R
    _PDLY-L @ _PDLY.TEXT _PDLY-APPEND R> AND ;

\ U bytes of text at A, with the U meanings at M, onto the block.
: _PDLY-COPY  ( a u m -- ok? )
    OVER _PDLY-L @ _PDLY.MEAN _PDLY-APPEND >R
    _PDLY-L @ _PDLY.TEXT _PDLY-APPEND R> AND ;

\ The block's text byte BACK from its end, or 0.
: _PDLY-LAST  ( back -- c )
    _PDLY-BTEXT-U _PDLY-BNEW 48 + @ - OVER < IF DROP 0 EXIT THEN
    _PDLY-L @ _PDLY.TEXT DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + SWAP - C@ ;

: _PDLY-LOWER?  ( c -- flag )  97 123 WITHIN ;

\ The characters of U bytes of UTF-8: the bytes that start one.
: _PDLY-CHARS  ( a u -- n )
    0 -ROT OVER + SWAP ?DO I C@ 0xC0 AND 0x80 <> IF 1+ THEN LOOP ;

\ A bullet and a space at the start of a line's text: the marker's
\ length, or 0.
: _PDLY-BULLET  ( a u -- n )
    DUP 2 < IF 2DROP 0 EXIT THEN
    OVER C@ DUP 45 = SWAP 42 = OR IF OVER 1+ C@ 32 = IF 2DROP 2 EXIT THEN THEN
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER C@ 0xC2 = IF OVER 1+ C@ 0xB7 = IF OVER 2 + C@ 32 = IF 2DROP 3 EXIT THEN THEN THEN
    DUP 4 < IF 2DROP 0 EXIT THEN
    OVER 3 + C@ 32 <> IF 2DROP 0 EXIT THEN
    DROP DUP C@ 8 LSHIFT OVER 1+ C@ OR 8 LSHIFT SWAP 2 + C@ OR
    CASE
        0xE280A2 OF 4 ENDOF   0xE280A3 OF 4 ENDOF   0xE28093 OF 4 ENDOF
        0xE28183 OF 4 ENDOF   0xE297A6 OF 4 ENDOF   0xE296AA OF 4 ENDOF
        0xE296AB OF 4 ENDOF   0xE296A0 OF 4 ENDOF   0xE296A1 OF 4 ENDOF
        0xE297BE OF 4 ENDOF   0xEF82B7 OF 4 ENDOF   0xEF82A7 OF 4 ENDOF
        0 SWAP
    ENDCASE ;

VARIABLE _PDLY-NUM   VARIABLE _PDLY-MA   VARIABLE _PDLY-MU   VARIABLE _PDLY-MI

: _PDLY-AT  ( i -- c )  DUP _PDLY-MU @ < IF _PDLY-MA @ + C@ ELSE DROP 0 THEN ;

\ Up to three digits or a letter, then "." or ")" and a space; or in
\ parentheses, then a space: the number and the marker's length, or 0 0.
: _PDLY-NUMBERED  ( a u -- number n )
    _PDLY-MU ! _PDLY-MA !  0 _PDLY-NUM !
    0 _PDLY-AT 40 = IF 1 ELSE 0 THEN DUP _PDLY-MI !
    _PDLY-MI @ _PDLY-AT DUP 48 58 WITHIN IF
        DROP
        BEGIN _PDLY-MI @ _PDLY-AT DUP 48 58 WITHIN WHILE
            48 - _PDLY-NUM @ 10 * + _PDLY-NUM !  1 _PDLY-MI +!
        REPEAT DROP
        _PDLY-MI @ OVER - 3 > IF DROP 0 0 EXIT THEN
    ELSE
        DUP _PDLY-LOWER? 0= IF 2DROP 0 0 EXIT THEN
        96 - _PDLY-NUM !  1 _PDLY-MI +!
    THEN
    IF
        _PDLY-MI @ _PDLY-AT 41 <> IF 0 0 EXIT THEN
    ELSE
        _PDLY-MI @ _PDLY-AT DUP 46 = SWAP 41 = OR 0= IF 0 0 EXIT THEN
    THEN
    1 _PDLY-MI +!
    _PDLY-MI @ _PDLY-AT 32 <> IF 0 0 EXIT THEN
    _PDLY-NUM @ _PDLY-MI @ 1+ ;

\ The list item a line's text starts: its kind, number and marker's
\ length in bytes, or 0 0 0.
: _PDLY-MARKER  ( a u -- kind number n )
    2DUP _PDLY-BULLET ?DUP IF NIP NIP DOC-C-BULLET 0 ROT EXIT THEN
    _PDLY-NUMBERED ?DUP IF DOC-C-NUMBERED -ROT EXIT THEN
    DROP 0 0 0 ;

\ The cells an item's marker takes: a bullet and a space, or the number
\ and a dot and a space.
: _PDLY-WIDTH  ( kind number -- cells )
    SWAP DOC-C-BULLET = IF DROP 2 EXIT THEN
    2 SWAP BEGIN 10 / DUP WHILE SWAP 1+ SWAP REPEAT DROP 1+ ;

\ Whether a line is the page's number: digits alone, the page's topmost
\ or lowest line, on a page of more lines.
: _PDLY-FOLIO?  ( ln -- flag )
    _PDLY-NLINES 2 < IF DROP 0 EXIT THEN
    DUP _PDLY-LTEXT@ DUP 0= IF 2DROP DROP 0 EXIT THEN
    OVER + SWAP ?DO
        I C@ DUP 48 58 WITHIN SWAP 32 = OR 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    _PDLY.Y @ DUP _PDLY-YMIN @ = SWAP _PDLY-YMAX @ = OR ;

\ Finish the block being built, its kind from its lines.
: _PDLY-FINISH  ( -- ok? )
    _PDLY-BOPEN? @ 0= IF -1 EXIT THEN  0 _PDLY-BOPEN? !
    _PDLY-BTEXT-U _PDLY-BNEW 48 + @ - DUP _PDLY-BNEW 56 + !
    0= IF -1 EXIT THEN
    DOC-B-PARAGRAPH _PDLY-BNEW !  0 _PDLY-BNEW 8 + !
    _PDLY-BFL @ _PDLY-F-FIXED AND IF
        DOC-B-CODE _PDLY-BNEW !
    ELSE _PDLY-BNEW 16 + @ 0= IF
        _PDLY-BSZ @ 100 * _PDLY-BODY @ 1 MAX /
        DUP 115 < 0= _PDLY-BLINES @ 4 < AND IF
            DOC-B-HEADING _PDLY-BNEW !
            DUP 160 < 0= IF 1 ELSE DUP 130 < 0= IF 2 ELSE 3 THEN THEN _PDLY-BNEW 8 + !
        ELSE
            DUP 95 < 0= _PDLY-BFL @ _PDLY-F-BOLD AND 0<> AND
            _PDLY-BLINES @ 1 = AND _PDLY-BNEW 56 + @ 100 < AND IF
                DOC-B-HEADING _PDLY-BNEW !  4 _PDLY-BNEW 8 + !
            THEN
        THEN DROP
    THEN THEN
    \ A heading's or code's text has no meanings of its own.
    _PDLY-BNEW @ DOC-B-PARAGRAPH <> IF
        _PDLY-L @ _PDLY.MEAN PDF-BUF.A @ _PDLY-BNEW 48 + @ +
        _PDLY-BNEW 56 + @ TSTY-PLAIN FILL
    THEN
    _PDLY-BNEW _PDLY-BLOCK _PDLY-L @ _PDLY.BLOCKS _PDLY-APPEND ;

\ Start a block with line LN.
: _PDLY-START  ( ln -- ok? )
    _PDLY-FINISH 0= IF DROP 0 EXIT THEN
    -1 _PDLY-BOPEN? !  1 _PDLY-BLINES !  DUP _PDLY-PREV !
    DUP _PDLY.SZ @ _PDLY-BSZ !  DUP _PDLY.FL @ _PDLY-BFL !  DUP _PDLY.X0 @ _PDLY-BLEFT !
    _PDLY-BNEW _PDLY-BLOCK 0 FILL
    DUP _PDLY.Y @ OVER _PDLY.SZ @ + _PDLY-BNEW 40 + !
    _PDLY-BTEXT-U _PDLY-BNEW 48 + !
    DUP _PDLY-LTEXT@ _PDLY-MARKER
    ?DUP IF
        >R 2DUP _PDLY-WIDTH _PDLY-BNEW 32 + ! R>
        >R _PDLY-BNEW 24 + ! _PDLY-BNEW 16 + !
        \ the item's text starts after its marker, its share of the line
        DUP _PDLY-LTEXT@ DROP R@ _PDLY-CHARS
        OVER _PDLY.X1 @ 2 PICK _PDLY.X0 @ - *
        OVER _PDLY-LTEXT@ _PDLY-CHARS 1 MAX /
        OVER _PDLY.X0 @ + _PDLY-ITEM-X !
        DUP _PDLY-LTEXT@ R@ - SWAP R@ + SWAP
        ROT _PDLY-LMEAN@ R> +
    ELSE
        2DROP DUP _PDLY-LTEXT@ ROT _PDLY-LMEAN@
    THEN
    _PDLY-COPY ;

CREATE _PDLY-NL 10 C,

\ A line of code's indent: the spaces its start lies right of the
\ block's first line, a fixed-pitch character being six tenths of the
\ size.
: _PDLY-INDENT+  ( ln -- ok? )
    DUP _PDLY.X0 @ _PDLY-BLEFT @ - SWAP _PDLY.SZ @ 3 * 5 / 1 MAX
    DUP 2/ ROT + SWAP /
    BEGIN DUP 0> WHILE
        S"  " TSTY-PLAIN _PDLY-BTEXT+ 0= IF DROP 0 EXIT THEN 1-
    REPEAT DROP -1 ;

\ Join line LN to the block: a line of code by a line end and its
\ indent; a word split by a hyphen into one; else with a space between.
: _PDLY-JOIN  ( ln -- ok? )
    1 _PDLY-BLINES +!  DUP _PDLY-PREV !
    _PDLY-BFL @ OVER _PDLY.FL @ AND _PDLY-BFL !
    _PDLY-BFL @ _PDLY-F-FIXED AND IF
        _PDLY-NL 1 TSTY-PLAIN _PDLY-BTEXT+ 0= IF DROP 0 EXIT THEN
        DUP _PDLY-INDENT+ 0= IF DROP 0 EXIT THEN
    ELSE
        DUP _PDLY.X0 @ _PDLY-BLEFT @ MIN _PDLY-BLEFT !
        1 _PDLY-LAST 45 = 2 _PDLY-LAST _PDLY-LOWER? AND
        OVER _PDLY-LTEXT@ IF C@ _PDLY-LOWER? ELSE DROP 0 THEN AND IF
            -1 _PDLY-L @ _PDLY.TEXT PDF-BUF.U +!  -1 _PDLY-L @ _PDLY.MEAN PDF-BUF.U +!
        ELSE 1 _PDLY-LAST 32 <> IF
            S"  " TSTY-PLAIN _PDLY-BTEXT+ 0= IF DROP 0 EXIT THEN
        THEN THEN
    THEN
    DUP _PDLY-LTEXT@ ROT _PDLY-LMEAN@ _PDLY-COPY ;

\ Whether line LN starts a block after the one being built: a rotated
\ line, another kind of font or size, a baseline not at the block's
\ spacing below the last, a list item, a line out of a list item's text,
\ a first line's indent, or a line after a short one.
: _PDLY-BREAK?  ( ln -- flag )
    _PDLY-BOPEN? @ 0= IF DROP -1 EXIT THEN
    DUP _PDLY.FL @ _PDLY-F-ROTATED AND IF DROP -1 EXIT THEN
    _PDLY-PREV @ _PDLY.FL @ _PDLY-F-ROTATED AND IF DROP -1 EXIT THEN
    DUP _PDLY.FL @ _PDLY-BFL @ XOR _PDLY-F-FIXED AND IF DROP -1 EXIT THEN
    DUP _PDLY.SZ @ _PDLY-BSZ @ - ABS _PDLY-BSZ @ 10 / > IF DROP -1 EXIT THEN
    _PDLY-PREV @ _PDLY.Y @ OVER _PDLY.Y @ -
    DUP 0> 0= IF 2DROP -1 EXIT THEN
    _PDLY-SPACING @ _PDLY-BSZ @ * _PDLY-BODY @ 1 MAX / 13 * 10 / > IF DROP -1 EXIT THEN
    DUP _PDLY-LTEXT@ _PDLY-MARKER NIP NIP IF DROP -1 EXIT THEN
    _PDLY-BFL @ _PDLY-F-FIXED AND IF DROP 0 EXIT THEN
    _PDLY-BNEW 16 + @ IF
        _PDLY.X0 @ _PDLY-ITEM-X @ - ABS _PDLY-BSZ @ > EXIT
    THEN
    DUP _PDLY.X0 @ _PDLY-BLEFT @ - _PDLY-BSZ @ > IF DROP -1 EXIT THEN
    DROP
    _PDLY-BSZ @ _PDLY-BODY @ - ABS _PDLY-BODY @ 10 / > IF 0 EXIT THEN
    1 _PDLY-LAST 45 = IF 0 EXIT THEN
    _PDLY-PREV @ _PDLY.X1 @ _PDLY-RIGHT @ _PDLY-BSZ @ 4 * - < ;

: _PDLY-MAKE-BLOCKS  ( -- ok? )
    0 _PDLY-BOPEN? !
    _PDLY-NLINES 0 ?DO
        I _PDLY-LINE@ DUP _PDLY-FOLIO? IF DROP ELSE
            DUP _PDLY-BREAK? IF _PDLY-START ELSE _PDLY-JOIN THEN
            0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _PDLY-FINISH ;

\ =====================================================================
\  Laying out a page
\ =====================================================================

\ PDF-LAYOUT-FREE ( layout -- )   Give back its blocks and their text.
: PDF-LAYOUT-FREE  ( layout -- )
    DUP _PDLY.MSRC @ ?DUP IF
        >R DUP _PDLY.BLOCKS R@ PDF-BUF-FREE  DUP _PDLY.TEXT R@ PDF-BUF-FREE
        DUP _PDLY.MEAN R> PDF-BUF-FREE
    THEN
    PDF-LAYOUT-SIZE 0 FILL ;

\ PDF-LAYOUT-READ ( page content layout -- status )
\   The blocks of the runs CONTENT read from PAGE, which may be closed.
: PDF-LAYOUT-READ  ( page content layout -- status )
    DUP _PDLY-L !  PDF-LAYOUT-SIZE 0 FILL  _PDLY-C !
    PDF-PAGE-FILE PDF-FILE-MSRC DUP _PDLY-MS !  _PDLY-L @ _PDLY.MSRC !
    _PDLY-LINES 4 PDF-BUF-SIZE * 0 FILL
    _PDLY-MAKE-LINES IF _PDLY-MEASURE IF _PDLY-MAKE-BLOCKS ELSE 0 THEN ELSE 0 THEN
    _PDLY-LINES _PDLY-MS @ PDF-BUF-FREE  _PDLY-LTEXT _PDLY-MS @ PDF-BUF-FREE
    _PDLY-LMEAN _PDLY-MS @ PDF-BUF-FREE  _PDLY-HIST _PDLY-MS @ PDF-BUF-FREE
    IF PDF-S-OK ELSE PDF-S-MEMORY THEN ;
