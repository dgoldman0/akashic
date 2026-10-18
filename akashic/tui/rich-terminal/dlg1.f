\ =====================================================================
\  dlg1.f -- exact bounded renderer-neutral DIALOG and BUTTON content
\ =====================================================================
\  DLG1 and BTN1 (APT-1-RETAINED-1 sections 9.3 and 9.4) are call-borrowed
\  canonical values, independent of native widgets and any terminal
\  provider.  Validation derives the message's quota bytes, retains no
\  pointers, and never changes source bytes.
\
\  DLG1 is a 56-byte header and the message: tag, version 1, the NOTICE
\  flag, a positive revision, a severity from 0 to 4, the message length,
\  a title slot present exactly when the CONTROL label is, and a message
\  slot present exactly when the message is, both inside the root and
\  apart.  The message's lines are separated by line feeds; each line is
\  clean single-line text, and there are no more lines than message rows.
\  BTN1 is exactly the tag, version 1, and the DEFAULT, CANCEL, and
\  DESTRUCTIVE flags, never destructive and default.

PROVIDED akashic-tui-dlg1
REQUIRE ../../utils/memory-span.f
REQUIRE fdc1.f

: _DLG1-LE16@ ( a -- u ) DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;
: _DLG1-LE32@ ( a -- u ) DUP _DLG1-LE16@ SWAP 2 + _DLG1-LE16@ 16 LSHIFT OR ;
: _DLG1-LE64@ ( a -- u ) DUP _DLG1-LE32@ SWAP 4 + _DLG1-LE32@ 32 LSHIFT OR ;
: _DLG1-I32@ ( a -- n )
    _DLG1-LE32@ DUP 0x80000000 AND IF 0xFFFFFFFF INVERT OR THEN ;

0x31474C44 CONSTANT DLG1-TAG
0x314E5442 CONSTANT BTN1-TAG
56 CONSTANT DLG1-HEADER-SIZE
8 CONSTANT BTN1-SIZE
1 CONSTANT DLG1-F-NOTICE
1 CONSTANT BTN1-F-DEFAULT
2 CONSTANT BTN1-F-CANCEL
4 CONSTANT BTN1-F-DESTRUCTIVE

CREATE _DLG1-OWNED-START
VARIABLE _DLG1-A
VARIABLE _DLG1-U
VARIABLE _DLG1-TITLE-A
VARIABLE _DLG1-TITLE-U
VARIABLE _DLG1-COLS
VARIABLE _DLG1-ROWS
VARIABLE _DLG1-P
VARIABLE _DLG1-END
VARIABLE _DLG1-LINE
VARIABLE _DLG1-LINES
CREATE _DLG1-OWNED-END

: DLG1-STORAGE-DISJOINT? ( a u -- flag )
    _DLG1-OWNED-START _DLG1-OWNED-END _DLG1-OWNED-START -
    MSPAN-OVERLAP? 0= ;

\ An empty span is canonically address zero; a nonempty one does not wrap.
: _DLG1-SPAN?  ( a u -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

\ A present slot: a nonnegative origin and positive extents inside the root.
: _DLG1-RECT?  ( a -- flag )
    DUP _DLG1-I32@ 0< OVER 4 + _DLG1-I32@ 0< OR IF DROP 0 EXIT THEN
    DUP 8 + _DLG1-LE32@ 0= OVER 12 + _DLG1-LE32@ 0= OR IF DROP 0 EXIT THEN
    DUP _DLG1-I32@ OVER 8 + _DLG1-LE32@ + _DLG1-COLS @ U> IF DROP 0 EXIT THEN
    DUP 4 + _DLG1-I32@ SWAP 12 + _DLG1-LE32@ + _DLG1-ROWS @ U> 0= ;

: _DLG1-ABSENT?  ( a -- flag )
    DUP _DLG1-LE64@ SWAP 8 + _DLG1-LE64@ OR 0= ;

\ The title slot at 24 and the message slot at 40 have at least one
\ separating edge; touching edges are allowed.
: _DLG1-APART?  ( -- flag )
    _DLG1-A @ 24 + _DLG1-I32@ _DLG1-A @ 32 + _DLG1-LE32@ +
        _DLG1-A @ 40 + _DLG1-I32@ U> 0=
    _DLG1-A @ 40 + _DLG1-I32@ _DLG1-A @ 48 + _DLG1-LE32@ +
        _DLG1-A @ 24 + _DLG1-I32@ U> 0= OR
    _DLG1-A @ 28 + _DLG1-I32@ _DLG1-A @ 36 + _DLG1-LE32@ +
        _DLG1-A @ 44 + _DLG1-I32@ U> 0= OR
    _DLG1-A @ 44 + _DLG1-I32@ _DLG1-A @ 52 + _DLG1-LE32@ +
        _DLG1-A @ 28 + _DLG1-I32@ U> 0= OR ;

\ One message line: empty, or clean single-line text.  A line feed is ASCII
\ and never inside a UTF-8 sequence, so lines split at its bytes.
: _DLG1-LINE?  ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    FDC1-TEXT? ;

: _DLG1-MESSAGE?  ( -- flag )
    _DLG1-A @ DLG1-HEADER-SIZE + DUP _DLG1-P ! _DLG1-LINE !
    _DLG1-A @ _DLG1-U @ + _DLG1-END !
    1 _DLG1-LINES !
    BEGIN _DLG1-P @ _DLG1-END @ U< WHILE
        _DLG1-P @ C@ 10 = IF
            _DLG1-LINE @ _DLG1-P @ OVER - _DLG1-LINE? 0= IF 0 EXIT THEN
            _DLG1-P @ 1+ _DLG1-LINE !
            1 _DLG1-LINES +!
        THEN
        1 _DLG1-P +!
    REPEAT
    _DLG1-LINE @ _DLG1-END @ OVER - _DLG1-LINE? ;

: _DLG1-CONTENT?  ( -- flag )
    _DLG1-U @ DLG1-HEADER-SIZE U< IF 0 EXIT THEN
    _DLG1-A @ _DLG1-LE32@ DLG1-TAG <> IF 0 EXIT THEN
    _DLG1-A @ 4 + _DLG1-LE16@ 1 <> IF 0 EXIT THEN
    _DLG1-A @ 6 + _DLG1-LE16@ DLG1-F-NOTICE INVERT AND IF 0 EXIT THEN
    _DLG1-A @ 8 + _DLG1-LE64@ 0= IF 0 EXIT THEN
    _DLG1-A @ 16 + _DLG1-LE32@ 4 U> IF 0 EXIT THEN
    _DLG1-A @ 20 + _DLG1-LE32@ _DLG1-U @ DLG1-HEADER-SIZE - <> IF 0 EXIT THEN
    _DLG1-TITLE-U @ IF
        _DLG1-A @ 24 + _DLG1-RECT? 0= IF 0 EXIT THEN
    ELSE
        _DLG1-A @ 24 + _DLG1-ABSENT? 0= IF 0 EXIT THEN
    THEN
    _DLG1-A @ 20 + _DLG1-LE32@ 0= IF _DLG1-A @ 40 + _DLG1-ABSENT? EXIT THEN
    _DLG1-A @ 40 + _DLG1-RECT? 0= IF 0 EXIT THEN
    _DLG1-TITLE-U @ IF _DLG1-APART? 0= IF 0 EXIT THEN THEN
    _DLG1-MESSAGE? 0= IF 0 EXIT THEN
    _DLG1-LINES @ _DLG1-A @ 52 + _DLG1-LE32@ U> 0= ;

: _DLG1-SCRUB ( -- )
    0 _DLG1-A ! 0 _DLG1-U ! 0 _DLG1-TITLE-A ! 0 _DLG1-TITLE-U !
    0 _DLG1-COLS ! 0 _DLG1-ROWS ! 0 _DLG1-P ! 0 _DLG1-END !
    0 _DLG1-LINE ! 0 _DLG1-LINES ! ;

\ All source authority checks are stack-only and precede scratch writes.
: _DLG1-AUTHORITY? ( a u title-a title-u -- flag )
    2DUP _DLG1-SPAN? 0= IF 2DROP 2DROP 0 EXIT THEN
    2DUP DLG1-STORAGE-DISJOINT? 0= IF 2DROP 2DROP 0 EXIT THEN
    2OVER DUP DLG1-HEADER-SIZE U< 2 PICK 0= OR IF 2DROP 2DROP 2DROP 0 EXIT THEN
    DUP 0xFFFFFFFF U> IF 2DROP 2DROP 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 2DROP 0 EXIT THEN
    DLG1-STORAGE-DISJOINT? 0= IF 2DROP 2DROP 0 EXIT THEN
    MSPAN-OVERLAP? 0= ;

: _DLG1-VALIDATE-BODY ( -- flag )
    _DLG1-COLS @ DUP 0= SWAP 0xFFFFFFFF U> OR IF 0 EXIT THEN
    _DLG1-ROWS @ DUP 0= SWAP 0xFFFFFFFF U> OR IF 0 EXIT THEN
    _DLG1-TITLE-U @ 0xFFFFFFFF U> IF 0 EXIT THEN
    _DLG1-TITLE-A @ _DLG1-TITLE-U @ FDC1-TEXT? 0= IF 0 EXIT THEN
    _DLG1-CONTENT? ;

\ DLG1-VALIDATE ( a u title-a title-u cols rows -- utf8 flag )
\   Validate one exact DLG1 value for a dialog root COLS by ROWS cells with
\   the CONTROL label TITLE.  UTF8 is the message's bytes; the title is
\   charged separately as the label.  Failure returns two zeros, including
\   after any bounded parser throw.
: DLG1-VALIDATE ( a u title-a title-u cols rows -- utf8 flag )
    >R >R
    2OVER 2OVER _DLG1-AUTHORITY? 0= IF
        2DROP 2DROP R> DROP R> DROP 0 0 EXIT
    THEN
    R> _DLG1-COLS ! R> _DLG1-ROWS !
    _DLG1-TITLE-U ! _DLG1-TITLE-A ! _DLG1-U ! _DLG1-A !
    ['] _DLG1-VALIDATE-BODY CATCH ?DUP IF DROP 0 THEN
    IF _DLG1-A @ 20 + _DLG1-LE32@ -1 ELSE 0 0 THEN
    _DLG1-SCRUB ;

\ BTN1-VALIDATE ( a u -- flag )
\   Validate one exact 8-byte BTN1 value.
: BTN1-VALIDATE ( a u -- flag )
    DUP BTN1-SIZE <> IF 2DROP 0 EXIT THEN
    2DUP _DLG1-SPAN? 0= IF 2DROP 0 EXIT THEN
    DROP
    DUP _DLG1-LE32@ BTN1-TAG <> IF DROP 0 EXIT THEN
    DUP 4 + _DLG1-LE16@ 1 <> IF DROP 0 EXIT THEN
    6 + _DLG1-LE16@
    DUP BTN1-F-DEFAULT BTN1-F-CANCEL OR BTN1-F-DESTRUCTIVE OR INVERT AND IF
        DROP 0 EXIT
    THEN
    DUP BTN1-F-DESTRUCTIVE AND 0<> SWAP BTN1-F-DEFAULT AND 0<> AND 0= ;
