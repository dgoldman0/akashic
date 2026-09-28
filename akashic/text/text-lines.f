\ =================================================================
\  text-lines.f — text broken into lines at a width
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TLINES- / _TLN-
\  Depends on: text-row.f
\
\  Breaks text into lines at most a given number of cells wide, as the
\  shared text contract (docs/rich-terminal/APT-1-TEXT.md Section 12)
\  describes, so that every implementation finds the same lines.  Line
\  feeds separate the text's paragraphs, and each paragraph breaks on
\  its own; an empty paragraph is one empty line.
\
\  A paragraph of printable ASCII, not forced RTL, breaks on its bytes,
\  and each of its lines shows its bytes as they are (the section's last
\  paragraph).  Any other paragraph is laid out once by TROW-LAYOUT, so
\  its levels and joining come from the whole paragraph, and each of its
\  lines is shown by TROW-LINE.
\
\  Cursor (TLINES-SIZE bytes of caller storage, holding one text row):
\    TLINES-INIT    ( cursor -- )
\    TLINES-FREE    ( cursor -- )    release its row's buffer
\    TLINES-START   ( addr u flags direction limit cursor -- line? )
\        Read the text's first line.  FLAGS and DIRECTION are as for
\        TROW-LAYOUT; a LIMIT below 1 counts as 1.  The text must stay
\        unchanged while the cursor reads it.
\    TLINES-NEXT    ( cursor -- line? )   Read the next line.
\        Both are false past the last line, and when a paragraph cannot
\        be laid out, which TLINES-FAILED? then tells.
\    TLINES-FAILED? ( cursor -- flag )
\    TLINES-COUNT   ( addr u flags direction limit cursor -- lines ok? )
\        How many lines the text takes; OK is false when a paragraph
\        cannot be laid out.
\  The line read:
\    TLINES-ROW       ( cursor -- row|0 )  the row showing it, as
\        TROW-LINE shows a line, or 0 when it is printable ASCII shown as
\        its bytes
\    TLINES-BYTES     ( cursor -- addr u )  its bytes, less the spaces at
\        its end
\    TLINES-PARAGRAPH ( cursor -- addr )   its paragraph's first byte,
\        from which the row's byte offsets count
\    TLINES-WIDTH     ( cursor -- cells )
\    TLINES-RTL?      ( cursor -- flag )   it starts at the right edge
\
\  Reading keeps its scratch state in module variables and takes the
\  module guard in GUARDED builds.
\ =================================================================

PROVIDED akashic-text-lines

REQUIRE text-row.f

\ =====================================================================
\  §1 — Cursor
\ =====================================================================

\ The cursor is its row, then the text and the place reached in it.
TROW-SIZE       CONSTANT _TLN-O-TEXT-A
TROW-SIZE  8 +  CONSTANT _TLN-O-TEXT-U
TROW-SIZE 16 +  CONSTANT _TLN-O-FLAGS
TROW-SIZE 24 +  CONSTANT _TLN-O-DIR
TROW-SIZE 32 +  CONSTANT _TLN-O-LIMIT
TROW-SIZE 40 +  CONSTANT _TLN-O-PARA     \ the paragraph's first byte, in the text
TROW-SIZE 48 +  CONSTANT _TLN-O-PARA-U   \ its bytes, without the line feed
TROW-SIZE 56 +  CONSTANT _TLN-O-ASCII    \ it breaks on its bytes
TROW-SIZE 64 +  CONSTANT _TLN-O-FIRST    \ the line's first character
TROW-SIZE 72 +  CONSTANT _TLN-O-END      \ the character after its last
TROW-SIZE 80 +  CONSTANT _TLN-O-FAILED
TROW-SIZE 88 +  CONSTANT TLINES-SIZE

: TLINES-INIT  ( cursor -- )  TLINES-SIZE 0 FILL ;

: TLINES-FREE  ( cursor -- )  DUP TROW-FREE TLINES-INIT ;

VARIABLE _TLN-C       \ the cursor being read

: _TLN@  ( offset -- x )  _TLN-C @ + @ ;
: _TLN!  ( x offset -- )  _TLN-C @ + ! ;

: _TLN-PARA-A  ( -- addr )  _TLN-O-TEXT-A _TLN@ _TLN-O-PARA _TLN@ + ;

\ The paragraph's characters: its bytes, or its row's characters.
: _TLN-CHARS  ( -- n )
    _TLN-O-ASCII _TLN@ IF _TLN-O-PARA-U _TLN@ EXIT THEN
    _TLN-C @ TROW-CHARS ;

\ The width of the paragraph's character J, and whether it is a space:
\ exactly U+0020.  No mirrored or joined form is a space, so a laid-out
\ character's displayed scalar tells.
: _TLN-CHAR  ( j -- width space? )
    _TLN-O-ASCII _TLN@ IF _TLN-PARA-A + C@ 32 = 1 SWAP EXIT THEN
    _TLN-C @ TROW-CHAR DUP TROW.WIDTH
    SWAP DUP TROW.SCALARS 1 = SWAP TROW.CP0 32 = AND ;

\ =====================================================================
\  §2 — Section 12
\ =====================================================================

VARIABLE _TLN-TOTAL     \ the line's width so far, spaces included
VARIABLE _TLN-CONTENT   \ its width without the spaces at its end
VARIABLE _TLN-SEEN      \ it has a character that is not a space
VARIABLE _TLN-AFTER     \ the character before was a space
VARIABLE _TLN-OPP       \ its last break opportunity that fits, or -1
VARIABLE _TLN-FORCED    \ the first character taking the total past the limit

\ _TLN-LINE-END ( first -- end )
\   Where the line that starts at laid-out character FIRST ends: the rest
\   of the paragraph when that fits (rule 1), else its last break
\   opportunity that fits (rule 2), else before the first character
\   taking the total past the limit, or after its first character when
\   that alone is too wide (rule 3).  The scan stops at the first
\   character the line cannot reach.
: _TLN-LINE-END  ( first -- end )
    0 _TLN-TOTAL ! 0 _TLN-CONTENT ! 0 _TLN-SEEN ! 0 _TLN-AFTER !
    -1 _TLN-OPP ! -1 _TLN-FORCED !
    _TLN-CHARS OVER ?DO
        I _TLN-CHAR IF
            _TLN-TOTAL +!  -1 _TLN-AFTER !
        ELSE
            _TLN-SEEN @ _TLN-AFTER @ AND
            _TLN-CONTENT @ _TLN-O-LIMIT _TLN@ > 0= AND IF I _TLN-OPP ! THEN
            _TLN-TOTAL +!  _TLN-TOTAL @ _TLN-CONTENT !
            -1 _TLN-SEEN !  0 _TLN-AFTER !
        THEN
        _TLN-FORCED @ 0< _TLN-TOTAL @ _TLN-O-LIMIT _TLN@ > AND IF
            I _TLN-FORCED !
        THEN
        _TLN-CONTENT @ _TLN-O-LIMIT _TLN@ > IF
            _TLN-OPP @ 0< 0= IF DROP _TLN-OPP @ UNLOOP EXIT THEN
            _TLN-FORCED @ OVER > IF DROP _TLN-FORCED @ UNLOOP EXIT THEN
            1+ UNLOOP EXIT
        THEN
    LOOP
    DROP _TLN-CHARS ;

\ _TLN-ASCII-END ( first -- end )
\   The same rules on printable ASCII, where each byte is one character
\   one cell wide, so they need not walk the line.  The line reaches
\   byte FIRST + LIMIT; S is the first byte from there that is not a
\   space.  Without one the rest fits (rule 1).  Otherwise the last break
\   opportunity at or before S is the start of the word S is in, P, when
\   a byte that is not a space comes before the spaces before P (rule 2),
\   and the line ends at the byte it reaches (rule 3).
VARIABLE _TLN-PA
VARIABLE _TLN-PU

: _TLN-SPACE-AT?  ( i -- flag )  _TLN-PA @ + C@ 32 = ;

: _TLN-ASCII-END  ( first -- end )
    _TLN-PARA-A _TLN-PA !  _TLN-O-PARA-U _TLN@ _TLN-PU !
    DUP _TLN-O-LIMIT _TLN@ + DUP                   ( first reach s )
    BEGIN DUP _TLN-PU @ < IF DUP _TLN-SPACE-AT? ELSE 0 THEN WHILE 1+ REPEAT
    DUP _TLN-PU @ < 0= IF 2DROP DROP _TLN-PU @ EXIT THEN
    BEGIN DUP 3 PICK > IF DUP 1- _TLN-SPACE-AT? 0= ELSE 0 THEN
    WHILE 1- REPEAT                                ( first reach p )
    DUP BEGIN DUP 4 PICK > IF DUP 1- _TLN-SPACE-AT? ELSE 0 THEN
    WHILE 1- REPEAT                                ( first reach p q )
    3 PICK > IF NIP NIP EXIT THEN
    DROP NIP ;

\ Read the line that starts at character FIRST.
: _TLN-SHOW  ( first -- )
    DUP _TLN-O-FIRST _TLN!
    _TLN-O-ASCII _TLN@ IF _TLN-ASCII-END ELSE _TLN-LINE-END THEN
    _TLN-O-END _TLN!
    _TLN-O-ASCII _TLN@ 0= IF
        _TLN-O-FIRST _TLN@ _TLN-O-END _TLN@ _TLN-C @ TROW-LINE
    THEN ;

\ =====================================================================
\  §3 — Paragraphs
\ =====================================================================

\ _TLN-SCAN ( -- )
\   Find the paragraph's end, at the next line feed or the text's end, and
\   whether it breaks on its bytes: printable ASCII, not forced RTL.
: _TLN-SCAN  ( -- )
    _TLN-O-DIR _TLN@ BIDI-RTL <> _TLN-O-ASCII _TLN!
    _TLN-O-TEXT-U _TLN@ _TLN-O-PARA _TLN@ - _TLN-O-PARA-U _TLN!
    _TLN-PARA-A
    _TLN-O-PARA-U _TLN@ 0 ?DO
        DUP I + C@
        DUP 10 = IF 2DROP I _TLN-O-PARA-U _TLN! UNLOOP EXIT THEN
        32 127 WITHIN 0= IF 0 _TLN-O-ASCII _TLN! THEN
    LOOP
    DROP ;

\ _TLN-PARAGRAPH ( offset -- line? )
\   Begin the paragraph at byte OFFSET of the text and read its first line.
: _TLN-PARAGRAPH  ( offset -- line? )
    _TLN-O-PARA _TLN!
    _TLN-SCAN
    _TLN-O-ASCII _TLN@ 0= IF
        _TLN-PARA-A _TLN-O-PARA-U _TLN@ _TLN-O-FLAGS _TLN@ _TLN-O-DIR _TLN@
        _TLN-C @ TROW-LAYOUT 0= IF -1 _TLN-O-FAILED _TLN! 0 EXIT THEN
    THEN
    0 _TLN-SHOW -1 ;

: TLINES-START  ( addr u flags direction limit cursor -- line? )
    _TLN-C !
    1 MAX _TLN-O-LIMIT _TLN!  _TLN-O-DIR _TLN!  _TLN-O-FLAGS _TLN!
    _TLN-O-TEXT-U _TLN!  _TLN-O-TEXT-A _TLN!
    0 _TLN-O-FAILED _TLN!
    0 _TLN-PARAGRAPH ;

: TLINES-NEXT  ( cursor -- line? )
    _TLN-C !
    _TLN-O-FAILED _TLN@ IF 0 EXIT THEN
    _TLN-O-END _TLN@ _TLN-CHARS < IF _TLN-O-END _TLN@ _TLN-SHOW -1 EXIT THEN
    \ The paragraph is done; the next one starts after its line feed.
    _TLN-O-PARA _TLN@ _TLN-O-PARA-U _TLN@ +
    DUP _TLN-O-TEXT-U _TLN@ < 0= IF DROP 0 EXIT THEN
    1+ _TLN-PARAGRAPH ;

: TLINES-FAILED?  ( cursor -- flag )  _TLN-O-FAILED + @ 0<> ;

: TLINES-COUNT  ( addr u flags direction limit cursor -- lines ok? )
    DUP >R TLINES-START
    0 SWAP BEGIN WHILE 1+ R@ TLINES-NEXT REPEAT
    R> TLINES-FAILED? 0= ;

\ =====================================================================
\  §4 — The line read
\ =====================================================================

: TLINES-ROW  ( cursor -- row|0 )  DUP _TLN-O-ASCII + @ IF DROP 0 THEN ;

: TLINES-PARAGRAPH  ( cursor -- addr )
    DUP _TLN-O-TEXT-A + @ SWAP _TLN-O-PARA + @ + ;

: TLINES-RTL?  ( cursor -- flag )
    DUP _TLN-O-ASCII + @ IF DROP 0 EXIT THEN
    TROW-PARA 1 AND 0<> ;

\ The line's end, less the spaces at its end.
: _TLN-LAST  ( -- last )
    _TLN-O-END _TLN@ BEGIN
        DUP _TLN-O-FIRST _TLN@ > IF DUP 1- _TLN-CHAR NIP ELSE 0 THEN
    WHILE 1- REPEAT ;

\ Where the paragraph's character J starts, in bytes from its first.
: _TLN-BYTE  ( j -- byte )
    _TLN-O-ASCII _TLN@ IF EXIT THEN
    DUP _TLN-C @ TROW-CHARS < IF _TLN-C @ TROW-CHAR TROW.BYTE EXIT THEN
    DROP _TLN-O-PARA-U _TLN@ ;

: TLINES-BYTES  ( cursor -- addr u )
    _TLN-C !
    _TLN-PARA-A _TLN-O-FIRST _TLN@ _TLN-BYTE +
    _TLN-LAST _TLN-BYTE _TLN-O-FIRST _TLN@ _TLN-BYTE - ;

: TLINES-WIDTH  ( cursor -- cells )
    DUP _TLN-O-ASCII + @ IF TLINES-BYTES NIP EXIT THEN
    TROW-WIDTH ;

\ =====================================================================
\  §5 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _tlines-guard

' TLINES-START  CONSTANT _tlines-start-xt
' TLINES-NEXT   CONSTANT _tlines-next-xt
' TLINES-COUNT  CONSTANT _tlines-count-xt
' TLINES-BYTES  CONSTANT _tlines-bytes-xt
' TLINES-WIDTH  CONSTANT _tlines-width-xt

: TLINES-START  _tlines-start-xt _tlines-guard WITH-GUARD ;
: TLINES-NEXT   _tlines-next-xt _tlines-guard WITH-GUARD ;
: TLINES-COUNT  _tlines-count-xt _tlines-guard WITH-GUARD ;
: TLINES-BYTES  _tlines-bytes-xt _tlines-guard WITH-GUARD ;
: TLINES-WIDTH  _tlines-width-xt _tlines-guard WITH-GUARD ;
[THEN] [THEN]
