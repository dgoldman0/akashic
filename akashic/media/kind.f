\ =====================================================================
\  media/kind.f — what kind of thing a file is
\ =====================================================================
\
\  Looks at a file's first bytes, then its name.  A signature decides every
\  kind that has one, so a misnamed picture is still a picture; the name
\  only tells an HTML page or a Markdown document from other text.  A page
\  is text that begins like one or is named .html or .htm, and a Markdown
\  document text named .md or .markdown.  Text is valid UTF-8 with no
\  NUL; anything else without a known signature is binary.  A viewer uses
\  the kind to choose how to show a file, and to say what a file is even
\  when it cannot show it yet.
\
\  A caller passes at most MEDIA-SNIFF-BYTES first bytes, or the whole file
\  when it is shorter.  A character cut off by the end of those bytes does
\  not make the text invalid.
\
\  Prefix: MEDIA-K- (kinds), MEDIA- (public), _MK- (private)
\
\  Public API:
\    MEDIA-SNIFF-BYTES  ( -- bytes )
\    MEDIA-KIND         ( prefix-a prefix-u name-a name-u -- kind )
\    MEDIA-KIND-NAME    ( kind -- a u )
\ =====================================================================

REQUIRE ../text/utf8.f

PROVIDED akashic-media-kind

0 CONSTANT MEDIA-K-BINARY
1 CONSTANT MEDIA-K-TEXT
2 CONSTANT MEDIA-K-HTML
3 CONSTANT MEDIA-K-QOI
4 CONSTANT MEDIA-K-PNG
5 CONSTANT MEDIA-K-JPEG
6 CONSTANT MEDIA-K-GIF
7 CONSTANT MEDIA-K-BMP
8 CONSTANT MEDIA-K-WAV
9 CONSTANT MEDIA-K-MARKDOWN

\ Enough for every signature and a fair look at text.
512 CONSTANT MEDIA-SNIFF-BYTES

VARIABLE _MK-A
VARIABLE _MK-U

\ Whether the prefix holds LIT-U bytes equal to LIT at OFFSET.
: _MK-AT?  ( lit-a lit-u offset -- flag )
    2DUP + _MK-U @ U> IF DROP 2DROP 0 EXIT THEN
    _MK-A @ + SWAP 0 ?DO
        OVER I + C@ OVER I + C@ <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP -1 ;

CREATE _MK-QOI   113 C, 111 C, 105 C, 102 C,                    \ qoif
CREATE _MK-PNG   0x89 C, 80 C, 78 C, 71 C, 13 C, 10 C, 26 C, 10 C,
CREATE _MK-JPEG  0xFF C, 0xD8 C, 0xFF C,
CREATE _MK-GIF87 71 C, 73 C, 70 C, 56 C, 55 C, 97 C,            \ GIF87a
CREATE _MK-GIF89 71 C, 73 C, 70 C, 56 C, 57 C, 97 C,            \ GIF89a
CREATE _MK-BM    66 C, 77 C,                                     \ BM
CREATE _MK-RIFF  82 C, 73 C, 70 C, 70 C,                         \ RIFF
CREATE _MK-WAVE  87 C, 65 C, 86 C, 69 C,                         \ WAVE

\ A little-endian u32 at any address.
: _MK-LE32@  ( a -- u )
    DUP C@ OVER 1+ C@ 8 LSHIFT OR OVER 2 + C@ 16 LSHIFT OR
    SWAP 3 + C@ 24 LSHIFT OR ;

\ A bitmap's header size, at offset 14, is one of the known versions.
: _MK-BMP?  ( -- flag )
    _MK-BM 2 0 _MK-AT? 0= IF 0 EXIT THEN
    _MK-U @ 18 < IF 0 EXIT THEN
    _MK-A @ 14 + _MK-LE32@
    DUP 12 = OVER 40 = OR OVER 52 = OR OVER 56 = OR
    OVER 108 = OR SWAP 124 = OR ;

: _MK-SIGNATURE  ( -- kind | -1 )
    _MK-QOI 4 0 _MK-AT? IF MEDIA-K-QOI EXIT THEN
    _MK-PNG 8 0 _MK-AT? IF MEDIA-K-PNG EXIT THEN
    _MK-JPEG 3 0 _MK-AT? IF MEDIA-K-JPEG EXIT THEN
    _MK-GIF87 6 0 _MK-AT? _MK-GIF89 6 0 _MK-AT? OR IF MEDIA-K-GIF EXIT THEN
    _MK-RIFF 4 0 _MK-AT? _MK-WAVE 4 8 _MK-AT? AND IF MEDIA-K-WAV EXIT THEN
    _MK-BMP? IF MEDIA-K-BMP EXIT THEN
    -1 ;

\ The prefix without a character the end of the prefix cut off.  A byte
\ that never starts a character is left for the validity check to refuse.
: _MK-WHOLE-U  ( -- u )
    _MK-U @ DUP 3 MIN 1+ 1 ?DO
        _MK-A @ OVER + I - C@                    ( u byte )
        DUP 0x80 < IF DROP UNLOOP EXIT THEN      \ ASCII: nothing cut
        DUP 0xF5 >= IF DROP UNLOOP EXIT THEN
        DUP 0xC0 AND 0xC0 = IF                   \ a lead byte I from the end
            DUP 0xF0 >= IF DROP 4 ELSE 0xE0 >= IF 3 ELSE 2 THEN THEN
            I > IF I - THEN UNLOOP EXIT
        THEN DROP
    LOOP ;

: _MK-TEXT?  ( -- flag )
    _MK-U @ 0 ?DO
        _MK-A @ I + C@ 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _MK-A @ _MK-WHOLE-U UTF8-VALID? ;

\ ASCII lower case, for matching tags and names.
: _MK-LOWER  ( c -- c' )  DUP 65 91 WITHIN IF 32 + THEN ;

\ Whether the A U text starts with LIT, ignoring ASCII case.
: _MK-STARTS?  ( a u lit-a lit-u -- flag )
    ROT OVER < IF 2DROP DROP 0 EXIT THEN         ( a lit-a lit-u )
    0 ?DO
        OVER I + C@ _MK-LOWER OVER I + C@ <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP -1 ;

CREATE _MK-DOCTYPE 60 C, 33 C, 100 C, 111 C, 99 C, 116 C, 121 C, 112 C,
    101 C, 32 C, 104 C, 116 C, 109 C, 108 C,                     \ <!doctype html
CREATE _MK-HTML-TAG 60 C, 104 C, 116 C, 109 C, 108 C,            \ <html
CREATE _MK-HTML-EXT 46 C, 104 C, 116 C, 109 C, 108 C,            \ .html
CREATE _MK-HTM-EXT 46 C, 104 C, 116 C, 109 C,                    \ .htm
CREATE _MK-MD-EXT 46 C, 109 C, 100 C,                             \ .md
CREATE _MK-MARKDOWN-EXT 46 C, 109 C, 97 C, 114 C, 107 C, 100 C,
    111 C, 119 C, 110 C,                                         \ .markdown

\ The text after a byte order mark and leading white space starts like a page.
: _MK-HTML-START?  ( -- flag )
    _MK-A @ _MK-U @
    DUP 3 >= IF
        OVER C@ 0xEF = 2 PICK 1+ C@ 0xBB = AND 2 PICK 2 + C@ 0xBF = AND IF
            3 - SWAP 3 + SWAP
        THEN
    THEN
    BEGIN DUP IF OVER C@ DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR ELSE 0 THEN
    WHILE 1- SWAP 1+ SWAP REPEAT
    2DUP _MK-DOCTYPE 14 _MK-STARTS? IF 2DROP -1 EXIT THEN
    _MK-HTML-TAG 5 _MK-STARTS? ;

\ Whether the name ends with LIT, ignoring ASCII case.
: _MK-ENDS?  ( name-a name-u lit-a lit-u -- flag )
    2 PICK OVER < IF 2DROP 2DROP 0 EXIT THEN
    2SWAP + OVER - ROT ROT                        ( tail lit-a lit-u )
    0 ?DO
        OVER I + C@ _MK-LOWER OVER I + C@ <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP -1 ;

\ MEDIA-KIND ( prefix-a prefix-u name-a name-u -- kind )
\   The kind of a file from its first bytes and its name.
: MEDIA-KIND  ( prefix-a prefix-u name-a name-u -- kind )
    2SWAP _MK-U ! _MK-A !                        ( name-a name-u )
    _MK-SIGNATURE DUP -1 <> IF NIP NIP EXIT THEN DROP
    _MK-TEXT? 0= IF 2DROP MEDIA-K-BINARY EXIT THEN
    _MK-HTML-START? IF 2DROP MEDIA-K-HTML EXIT THEN
    2DUP _MK-HTML-EXT 5 _MK-ENDS? IF 2DROP MEDIA-K-HTML EXIT THEN
    2DUP _MK-HTM-EXT 4 _MK-ENDS? IF 2DROP MEDIA-K-HTML EXIT THEN
    2DUP _MK-MD-EXT 3 _MK-ENDS? IF 2DROP MEDIA-K-MARKDOWN EXIT THEN
    _MK-MARKDOWN-EXT 9 _MK-ENDS? IF MEDIA-K-MARKDOWN EXIT THEN
    MEDIA-K-TEXT ;

\ MEDIA-KIND-NAME ( kind -- a u )   What to call a kind in a viewer.
: MEDIA-KIND-NAME  ( kind -- a u )
    CASE
        MEDIA-K-TEXT OF S" text" ENDOF
        MEDIA-K-HTML OF S" HTML page" ENDOF
        MEDIA-K-MARKDOWN OF S" Markdown document" ENDOF
        MEDIA-K-QOI  OF S" QOI picture" ENDOF
        MEDIA-K-PNG  OF S" PNG picture" ENDOF
        MEDIA-K-JPEG OF S" JPEG picture" ENDOF
        MEDIA-K-GIF  OF S" GIF picture" ENDOF
        MEDIA-K-BMP  OF S" BMP picture" ENDOF
        MEDIA-K-WAV  OF S" WAV sound" ENDOF
        >R S" binary data" R>
    ENDCASE ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _media-kind-guard

' MEDIA-KIND CONSTANT _media-kind-xt

: MEDIA-KIND  _media-kind-xt _media-kind-guard WITH-GUARD ;
[THEN] [THEN]
