\ =====================================================================
\  fdc1.f -- exact bounded renderer-neutral typed FIELD content
\ =====================================================================
\  FDC1 is a call-borrowed canonical value, independent of native widgets,
\  UFLD storage and any terminal provider. Validation derives choice/text
\  quota totals, retains no pointers, and never changes source bytes.
\  Choices use bounded prior-record scans to enforce unique signed values.

PROVIDED akashic-tui-fdc1
REQUIRE ../../utils/memory-span.f

: _FDC1-LE16@ ( a -- u ) DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;
: _FDC1-LE32@ ( a -- u ) DUP _FDC1-LE16@ SWAP 2 + _FDC1-LE16@ 16 LSHIFT OR ;
: _FDC1-LE64@ ( a -- u ) DUP _FDC1-LE32@ SWAP 4 + _FDC1-LE32@ 32 LSHIFT OR ;
: _FDC1-I32@ ( a -- n )
    _FDC1-LE32@ DUP 0x80000000 AND IF 0xFFFFFFFF INVERT OR THEN ;

CREATE _FDC1-OWNED-START
VARIABLE _FDC1-A
VARIABLE _FDC1-U
VARIABLE _FDC1-OUTER-A
VARIABLE _FDC1-OUTER-U
VARIABLE _FDC1-COLS
VARIABLE _FDC1-ROWS
VARIABLE _FDC1-END
VARIABLE _FDC1-P
VARIABLE _FDC1-PREV
VARIABLE _FDC1-LEFT
VARIABLE _FDC1-LABEL-U
VARIABLE _FDC1-FOUND
VARIABLE _FDC1-RECT
VARIABLE _FDC1-UTF8
CREATE _FDC1-OWNED-END

: FDC1-STORAGE-DISJOINT? ( a u -- flag )
    _FDC1-OWNED-START _FDC1-OWNED-END _FDC1-OWNED-START -
    MSPAN-OVERLAP? 0= ;

: _FDC1-UTF8-CONT?  ( byte -- flag )
    0xC0 AND 0x80 = ;

: _FDC1-UTF8-ONE  ( a u -- bytes|0 )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 0x80 < IF
        DUP 0= OVER 10 = OR SWAP 13 = OR IF
            2DROP 0 EXIT
        THEN
        2DROP 1 EXIT
    THEN
    DUP 0xC2 0xE0 WITHIN IF
        DROP
        DUP 2 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ _FDC1-UTF8-CONT? IF 2DROP 2 ELSE 2DROP 0 THEN
        EXIT
    THEN
    DUP 0xE0 0xF0 WITHIN IF
        >R
        DUP 3 < IF 2DROP R> DROP 0 EXIT THEN
        OVER 1+ C@
        R@ 0xE0 = IF
            0xA0 0xC0 WITHIN
        ELSE
            R@ 0xED = IF
                0x80 0xA0 WITHIN
            ELSE
                _FDC1-UTF8-CONT?
            THEN
        THEN
        2 PICK 2 + C@ _FDC1-UTF8-CONT? AND 0= IF
            2DROP R> DROP 0 EXIT
        THEN
        2DROP R> DROP 3 EXIT
    THEN
    DUP 0xF0 0xF5 WITHIN IF
        >R
        DUP 4 < IF 2DROP R> DROP 0 EXIT THEN
        OVER 1+ C@
        R@ 0xF0 = IF
            0x90 0xC0 WITHIN
        ELSE
            R@ 0xF4 = IF
                0x80 0x90 WITHIN
            ELSE
                _FDC1-UTF8-CONT?
            THEN
        THEN
        2 PICK 2 + C@ _FDC1-UTF8-CONT? AND
        2 PICK 3 + C@ _FDC1-UTF8-CONT? AND 0= IF
            2DROP R> DROP 0 EXIT
        THEN
        2DROP R> DROP 4 EXIT
    THEN
    2DROP DROP 0 ;

: _FDC1-TEXT-SPAN?  ( a u -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: FDC1-TEXT?  ( a u -- flag )
    2DUP _FDC1-TEXT-SPAN? 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP WHILE
        2DUP _FDC1-UTF8-ONE DUP 0= IF
            DROP 2DROP 0 EXIT
        THEN >R
        OVER C@ DUP 32 U< SWAP 127 = OR IF
            2DROP R> DROP 0 EXIT
        THEN
        OVER C@ 0xC2 = IF
            OVER 1+ C@ 0xA0 U< IF 2DROP R> DROP 0 EXIT THEN
        THEN
        OVER C@ 0xE2 = R@ 3 = AND IF
            OVER 1+ C@ 0x80 = IF
                OVER 2 + C@ DUP 0xA8 = SWAP 0xA9 = OR IF
                    2DROP R> DROP 0 EXIT
                THEN
            THEN
        THEN
        R> TUCK - >R + R>
    REPEAT 2DROP -1 ;

: _FDC1-RECT?  ( a -- flag )
    _FDC1-RECT !
    _FDC1-RECT @ _FDC1-I32@ 0<
    _FDC1-RECT @ 4 + _FDC1-I32@ 0< OR IF FALSE EXIT THEN
    _FDC1-RECT @ 8 + _FDC1-LE32@ 0= _FDC1-RECT @ 12 + _FDC1-LE32@ 0= OR IF
        FALSE EXIT
    THEN
    _FDC1-RECT @ _FDC1-I32@ _FDC1-RECT @ 8 + _FDC1-LE32@ + _FDC1-COLS @ U>
    _FDC1-RECT @ 4 + _FDC1-I32@ _FDC1-RECT @ 12 + _FDC1-LE32@ +
        _FDC1-ROWS @ U> OR 0= ;

: _FDC1-GEOMETRY?  ( -- flag )
    _FDC1-A @ 40 + _FDC1-RECT? 0= IF FALSE EXIT THEN
    _FDC1-OUTER-U @ 0= IF
        _FDC1-A @ 24 + _FDC1-LE64@ _FDC1-A @ 32 + _FDC1-LE64@ OR 0= EXIT
    THEN
    _FDC1-A @ 24 + _FDC1-RECT? 0= IF FALSE EXIT THEN
    \ At least one separating edge is required; touching edges are allowed.
    _FDC1-A @ 24 + _FDC1-I32@ _FDC1-A @ 32 + _FDC1-LE32@ +
        _FDC1-A @ 40 + _FDC1-I32@ U> 0=
    _FDC1-A @ 40 + _FDC1-I32@ _FDC1-A @ 48 + _FDC1-LE32@ +
        _FDC1-A @ 24 + _FDC1-I32@ U> 0= OR
    _FDC1-A @ 28 + _FDC1-I32@ _FDC1-A @ 36 + _FDC1-LE32@ +
        _FDC1-A @ 44 + _FDC1-I32@ U> 0= OR
    _FDC1-A @ 44 + _FDC1-I32@ _FDC1-A @ 52 + _FDC1-LE32@ +
        _FDC1-A @ 28 + _FDC1-I32@ U> 0= OR ;

: _FDC1-CHOICES?  ( -- flag )
    _FDC1-A @ 88 + _FDC1-LE32@ DUP _FDC1-LEFT ! 0= IF FALSE EXIT THEN
    _FDC1-LEFT @ _FDC1-U @ 96 - 17 / U> IF FALSE EXIT THEN
    _FDC1-A @ 96 + _FDC1-P ! FALSE _FDC1-FOUND !
    BEGIN _FDC1-LEFT @ WHILE
        _FDC1-END @ _FDC1-P @ - 16 U< IF FALSE EXIT THEN
        _FDC1-P @ 12 + _FDC1-LE32@ IF FALSE EXIT THEN
        _FDC1-P @ 8 + _FDC1-LE32@ DUP _FDC1-LABEL-U ! 0= IF FALSE EXIT THEN
        _FDC1-LABEL-U @ _FDC1-END @ _FDC1-P @ - 16 - U> IF
            FALSE EXIT
        THEN
        _FDC1-P @ 16 + _FDC1-LABEL-U @ FDC1-TEXT? 0= IF
            FALSE EXIT
        THEN
        _FDC1-A @ 96 + _FDC1-PREV !
        BEGIN _FDC1-PREV @ _FDC1-P @ U< WHILE
            _FDC1-PREV @ _FDC1-LE64@ _FDC1-P @ _FDC1-LE64@ = IF FALSE EXIT THEN
            _FDC1-PREV @ 8 + _FDC1-LE32@ 16 + _FDC1-PREV +!
        REPEAT
        _FDC1-P @ _FDC1-LE64@ _FDC1-A @ 56 + _FDC1-LE64@ = IF
            TRUE _FDC1-FOUND !
        THEN
        _FDC1-LABEL-U @ _FDC1-UTF8 +!
        _FDC1-LABEL-U @ 16 + _FDC1-P +! -1 _FDC1-LEFT +!
    REPEAT
    _FDC1-P @ _FDC1-END @ = _FDC1-FOUND @ AND ;

: _FDC1-CONTENT?  ( -- flag )
    _FDC1-A @ _FDC1-U @ + _FDC1-END !
    _FDC1-A @ _FDC1-LE32@ 0x31434446 <> IF FALSE EXIT THEN
    _FDC1-A @ 4 + _FDC1-LE16@ 1 <> IF FALSE EXIT THEN
    _FDC1-A @ 6 + _FDC1-LE16@ DUP 1 U< SWAP 3 U> OR IF FALSE EXIT THEN
    _FDC1-A @ 8 + _FDC1-LE64@ 0= IF FALSE EXIT THEN
    _FDC1-A @ 16 + _FDC1-LE32@ 1 INVERT AND
    _FDC1-A @ 20 + _FDC1-LE32@ OR IF FALSE EXIT THEN
    _FDC1-GEOMETRY? 0= IF FALSE EXIT THEN
    _FDC1-A @ 6 + _FDC1-LE16@ 1 = IF
        _FDC1-U @ 96 <> IF FALSE EXIT THEN
        _FDC1-A @ 88 + _FDC1-LE32@ _FDC1-A @ 92 + _FDC1-LE32@ OR IF FALSE EXIT THEN
        _FDC1-A @ 56 + _FDC1-LE64@ _FDC1-A @ 64 + _FDC1-LE64@ < IF
            FALSE EXIT
        THEN
        _FDC1-A @ 56 + _FDC1-LE64@ _FDC1-A @ 72 + _FDC1-LE64@ > IF
            FALSE EXIT
        THEN
        _FDC1-A @ 80 + _FDC1-LE64@ 0> EXIT
    THEN
    _FDC1-A @ 64 + _FDC1-LE64@ _FDC1-A @ 72 + _FDC1-LE64@ OR
    _FDC1-A @ 80 + _FDC1-LE64@ OR IF FALSE EXIT THEN
    _FDC1-A @ 6 + _FDC1-LE16@ 2 = IF
        _FDC1-A @ 92 + _FDC1-LE32@ IF FALSE EXIT THEN
        _FDC1-CHOICES? EXIT
    THEN
    _FDC1-A @ 56 + _FDC1-LE64@ _FDC1-A @ 88 + _FDC1-LE32@ OR IF FALSE EXIT THEN
    _FDC1-A @ 92 + _FDC1-LE32@ _FDC1-U @ 96 - <> IF FALSE EXIT THEN
    _FDC1-A @ 92 + _FDC1-LE32@ DUP _FDC1-UTF8 ! DUP IF
        _FDC1-A @ 96 + SWAP FDC1-TEXT?
    ELSE DROP TRUE THEN ;


: _FDC1-SCRUB ( -- )
    0 _FDC1-A ! 0 _FDC1-U ! 0 _FDC1-OUTER-A ! 0 _FDC1-OUTER-U !
    0 _FDC1-COLS ! 0 _FDC1-ROWS ! 0 _FDC1-END ! 0 _FDC1-P !
    0 _FDC1-PREV ! 0 _FDC1-LEFT ! 0 _FDC1-LABEL-U !
    0 _FDC1-FOUND ! 0 _FDC1-RECT ! 0 _FDC1-UTF8 ! ;

\ All source authority checks are stack-only and precede scratch writes.
: _FDC1-AUTHORITY? ( a u label-a label-u -- flag )
    2DUP _FDC1-TEXT-SPAN? 0= IF 2DROP 2DROP 0 EXIT THEN
    2DUP FDC1-STORAGE-DISJOINT? 0= IF 2DROP 2DROP 0 EXIT THEN
    2OVER DUP 96 U< 2 PICK 0= OR IF 2DROP 2DROP 2DROP 0 EXIT THEN
    DUP 0xFFFFFFFF U> IF 2DROP 2DROP 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 2DROP 0 EXIT THEN
    FDC1-STORAGE-DISJOINT? 0= IF 2DROP 2DROP 0 EXIT THEN
    MSPAN-OVERLAP? 0= ;

: _FDC1-VALIDATE-BODY ( -- flag )
    _FDC1-COLS @ DUP 0= SWAP 0xFFFFFFFF U> OR IF 0 EXIT THEN
    _FDC1-ROWS @ DUP 0= SWAP 0xFFFFFFFF U> OR IF 0 EXIT THEN
    _FDC1-OUTER-U @ 0xFFFFFFFF U> IF 0 EXIT THEN
    _FDC1-OUTER-A @ _FDC1-OUTER-U @ FDC1-TEXT? 0= IF 0 EXIT THEN
    _FDC1-CONTENT? ;

\ Content UTF8 excludes the separately charged outer CONTROL label.
\ Failure returns three zeros, including after any bounded parser throw.
: FDC1-VALIDATE ( a u label-a label-u cols rows -- choices utf8 flag )
    >R >R
    2OVER 2OVER _FDC1-AUTHORITY? 0= IF
        2DROP 2DROP R> DROP R> DROP 0 0 0 EXIT
    THEN
    R> _FDC1-COLS ! R> _FDC1-ROWS !
    _FDC1-OUTER-U ! _FDC1-OUTER-A ! _FDC1-U ! _FDC1-A !
    0 _FDC1-UTF8 !
    ['] _FDC1-VALIDATE-BODY CATCH ?DUP IF DROP 0 THEN
    IF _FDC1-A @ 88 + _FDC1-LE32@ _FDC1-UTF8 @ -1 ELSE 0 0 0 THEN
    _FDC1-SCRUB ;
