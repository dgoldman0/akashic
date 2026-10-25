\ =====================================================================
\  akashic/tui/widgets/picture.f — a picture, drawn with block characters
\ =====================================================================
\
\  Shows one picture from a media source, fitted inside the widget and
\  centred, keeping its shape.  In CELL each cell is an upper-half block
\  whose foreground is the upper pixel and whose background is the lower
\  one, each the nearest palette colour after blending onto the widget's
\  background, so a cell holds a square-ish pair of pixels.  A rich
\  terminal shows the same picture at its own resolution from the same
\  source: the rich side asks the widget for a copy of the size it shows
\  (PICT-RICH-ASK) and reads it from PICT-RICH@ once ready.
\
\  The widget reads the file's format and the picture's size when it is
\  given a source (PIC-FILE), so a rich terminal that decodes that format
\  can take the file as it is (PICT-FILE@, PICT-FILE-READ), with no copy
\  made.  CELL decodes the files a picture copy decodes, QOI and PNG; any
\  other picture file, or one of those the copy cannot read, such as an
\  interlaced PNG, shows its format and size in a label.
\
\  The rich side says whether it shows the picture, or is taking it to
\  show it (PICT-CLAIM!).  While it does, CELL shows the picture's name and
\  size beneath it and decodes nothing: a CELL copy still decoding stops,
\  and one already made is kept.  PICT-RELEASE-ALL lets every claim go at
\  once, when the rich side shows no picture; a widget showing that label
\  then asks for service, and its redraw makes its CELL copy.
\
\  When the rich side cannot send the picture because of the picture
\  itself, the terminal refusing its bytes as damaged or its file failing
\  to read, it says why (PICT-RICH-FAILED!).  It then takes the picture no
\  more until the widget is given another source, and CELL shows it: from
\  its CELL copy for a file CELL decodes, and otherwise with the reason.
\
\  The rich side also says which file formats it takes (PICT-RICH-FORMATS!).
\  A picture of one of them shows what it is from its first draw, before
\  any claim, so it starts no CELL copy only to stop it.  A picture the rich
\  side then does not take is drawn from its CELL copy at the next pass.
\
\  While the picture decodes, when it cannot be shown, and when the widget
\  is too small for it, the widget says so in a short label.  Decoding runs
\  in bounded steps from PICT-SERVICE, which the UIDL host calls each pass,
\  so drawing never waits for it: the CELL copy first, then a rich copy.
\  The widget asks media/picture.f for a CELL copy two pixels a cell high,
\  the size it shows, and keeps the palette colour of every cell, so a
\  redraw only places cells.
\
\  The source and the text alternative are borrowed: the caller keeps them
\  alive until it sets others or frees the widget.  Copies and colours come
\  from the caller's memory source.
\
\  Picture Descriptor:
\    +0..+32 widget header (type=WDG-T-PICTURE)
\    +40  source       media source, or 0
\    +48  msrc         memory for copies
\    +56  alt-a        text alternative
\    +64  alt-u
\    +72  cell         the CELL copy (PIC-SIZE bytes from msrc), or 0
\    +80  cell-w       the area that copy was made for, in cells
\    +88  cell-h
\    +96  colours      two palette indices a cell (upper, lower), or 0
\   +104  colours-bg   the background those colours were blended onto
\   +112  pending      one of this widget's copies is decoding
\   +120  rich         the rich copy (PIC-SIZE bytes from msrc), or 0
\   +128  rich-w       the most pixels across it was asked for
\   +136  rich-h       and down
\   +144  revision     which picture it shows: new with every source
\   +152  file-format  the file's PIC-F- format, or 0 when PIC-FILE knew none
\   +160  file-w       the picture's width and height, as its file says
\   +168  file-h
\   +176  claim        the claim epoch the rich side took the picture in; 0
\                      before the rich side has looked at the picture, -1
\                      once it has not taken it
\   +184  shown        CELL last drew the label for a claimed picture
\   +192  failed       why the rich side could not send the picture, a
\                      PIC-R- reason, or 0 while it may
\
\  Prefix: PICT- (public), _PICT- (internal)
\  Provider: akashic-tui-picture
\  Dependencies: widget.f, draw.f, color.f, media/picture.f, utils/string.f

PROVIDED akashic-tui-picture

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../color.f
REQUIRE ../../media/picture.f
REQUIRE ../../utils/memory-source.f
REQUIRE ../../utils/string.f

 40 CONSTANT _PICT-O-SOURCE
 48 CONSTANT _PICT-O-MSRC
 56 CONSTANT _PICT-O-ALT-A
 64 CONSTANT _PICT-O-ALT-U
 72 CONSTANT _PICT-O-CELL
 80 CONSTANT _PICT-O-CELL-W
 88 CONSTANT _PICT-O-CELL-H
 96 CONSTANT _PICT-O-COLOURS
104 CONSTANT _PICT-O-COLOURS-BG
112 CONSTANT _PICT-O-PENDING
120 CONSTANT _PICT-O-RICH
128 CONSTANT _PICT-O-RICH-W
136 CONSTANT _PICT-O-RICH-H
144 CONSTANT _PICT-O-REVISION
152 CONSTANT _PICT-O-FILE-FORMAT
160 CONSTANT _PICT-O-FILE-W
168 CONSTANT _PICT-O-FILE-H
176 CONSTANT _PICT-O-CLAIM
184 CONSTANT _PICT-O-SHOWN
192 CONSTANT _PICT-O-FAILED
200 CONSTANT _PICT-DESC-SIZE

\ Upper half block: foreground is the upper pixel, background the lower.
0x2580 CONSTANT _PICT-HALF

\ How many source pixels one service pass decodes for one widget.
16384 CONSTANT PICT-STEP-PIXELS

\ Widgets with a copy decoding, in any document.
VARIABLE _PICT-PENDING-COUNT   0 _PICT-PENDING-COUNT !

\ A claim holds while it is of the current epoch; a new epoch lets every
\ claim go at once.
VARIABLE _PICT-CLAIM-EPOCH   1 _PICT-CLAIM-EPOCH !

\ Widgets whose CELL view last drew the label for a claimed picture, in any
\ document: each must look again once the claim may have gone.
VARIABLE _PICT-PLACEHOLDERS   0 _PICT-PLACEHOLDERS !

\ The file formats the rich side takes now, PIC-F- format N at bit N-1; 0
\ while it takes none.
VARIABLE _PICT-RICH-FORMATS   0 _PICT-RICH-FORMATS !

\ PICT-RICH-FORMATS! ( formats -- )
\   The rich side says which picture files it takes, so a picture of one of
\   them shows what it is from its first draw.
: PICT-RICH-FORMATS!  ( formats -- )  _PICT-RICH-FORMATS ! ;

\ PICT-WORK? ( -- flag )
\   Some picture is still decoding, or shows the label for a claim that
\   may have gone.
: PICT-WORK?  ( -- flag )  _PICT-PENDING-COUNT @ _PICT-PLACEHOLDERS @ OR 0<> ;

\ The revisions given out so far, to any picture widget: each source a
\ widget is given takes the next.
VARIABLE _PICT-REVISIONS   0 _PICT-REVISIONS !

: _PICT@  ( w offset -- x )  + @ ;

: _PICT-PENDING!  ( flag w -- )
    2DUP _PICT-O-PENDING + @ 0<> = IF 2DROP EXIT THEN
    OVER IF 1 ELSE -1 THEN _PICT-PENDING-COUNT +!
    SWAP 0<> SWAP _PICT-O-PENDING + ! ;

: _PICT-COPY-PENDING?  ( pic|0 -- flag )
    DUP IF PIC-STATE@ PIC-ST-PENDING = THEN ;

\ Whether CELL drew the label for a claimed picture.
: _PICT-SHOWN!  ( placeholder? w -- )
    SWAP 0<> SWAP 2DUP _PICT-O-SHOWN + @ = IF 2DROP EXIT THEN
    OVER IF 1 ELSE -1 THEN _PICT-PLACEHOLDERS +!
    _PICT-O-SHOWN + ! ;

\ The widget is pending while either copy decodes.
: _PICT-SYNC  ( w -- )
    DUP _PICT-O-CELL _PICT@ _PICT-COPY-PENDING?
    OVER _PICT-O-RICH _PICT@ _PICT-COPY-PENDING? OR SWAP _PICT-PENDING! ;

\ =====================================================================
\  1. Copies and colours
\ =====================================================================

: _PICT-COLOURS-BYTES  ( w -- u )
    DUP _PICT-O-CELL-W _PICT@ SWAP _PICT-O-CELL-H _PICT@ * 2* ;

: _PICT-DROP-COLOURS  ( w -- )
    DUP _PICT-O-COLOURS _PICT@ ?DUP IF
        OVER _PICT-COLOURS-BYTES 2 PICK _PICT-O-MSRC _PICT@ MSRC-FREE
    THEN
    0 SWAP _PICT-O-COLOURS + ! ;

\ Give back a copy and its record.
: _PICT-FREE-COPY  ( pic|0 w -- )
    OVER 0= IF 2DROP EXIT THEN
    OVER PIC-FREE  PIC-SIZE SWAP _PICT-O-MSRC _PICT@ MSRC-FREE ;

\ Give back the CELL copy and everything made from it.
: _PICT-DROP-COPY  ( w -- )
    DUP _PICT-DROP-COLOURS
    DUP _PICT-O-CELL _PICT@ OVER _PICT-FREE-COPY
    0 OVER _PICT-O-CELL + !
    0 OVER _PICT-O-CELL-W + !  0 OVER _PICT-O-CELL-H + !
    _PICT-SYNC ;

\ Give back the rich copy.
: _PICT-DROP-RICH  ( w -- )
    DUP _PICT-O-RICH _PICT@ OVER _PICT-FREE-COPY
    0 OVER _PICT-O-RICH + !
    0 OVER _PICT-O-RICH-W + !  0 OVER _PICT-O-RICH-H + !
    _PICT-SYNC ;

VARIABLE _PSC-W

\ Start a copy for a W-by-H cell area: two pixels a cell high.  False when
\ the memory source refused the copy's record.
: _PICT-START-COPY  ( cols rows w -- ok? )
    _PSC-W !
    _PSC-W @ _PICT-DROP-COPY
    2DUP _PSC-W @ _PICT-O-CELL-H + !  _PSC-W @ _PICT-O-CELL-W + !
    PIC-SIZE _PSC-W @ _PICT-O-MSRC _PICT@ MSRC-ALLOC
    DUP 0= IF NIP NIP EXIT THEN
    DUP _PSC-W @ _PICT-O-CELL + !                     ( cols rows rec )
    >R 2* _PSC-W @ _PICT-O-SOURCE _PICT@ _PSC-W @ _PICT-O-MSRC _PICT@ R>
    PIC-START DROP _PSC-W @ _PICT-SYNC
    -1 ;

\ =====================================================================
\  2. Public API
\ =====================================================================

: _PICT-HANDLE  ( event widget -- 0 )  2DROP 0 ;

DEFER _PICT-DRAW-D

: _PICT-DRAW  ( widget -- )  _PICT-DRAW-D ;

\ PICT-NEW ( rgn msrc -- widget )
\   A picture widget showing nothing yet.  Its copies take memory from MSRC.
: PICT-NEW  ( rgn msrc -- widget )
    _PICT-DESC-SIZE ALLOCATE 0<> ABORT" PICT-NEW: alloc"
    DUP _PICT-DESC-SIZE 0 FILL
    >R
    R@ _PICT-O-MSRC + !
    R@ WDG-T-PICTURE ROT ['] _PICT-DRAW ['] _PICT-HANDLE WDG-INIT
    R> ;

\ PICT-SOURCE! ( source alt-a alt-u widget -- )
\   Show the picture in SOURCE, with ALT as its text alternative.  A zero
\   source shows nothing.  Both are borrowed.  The widget takes the next
\   revision and reads the file's format and size.
: PICT-SOURCE!  ( source alt-a alt-u widget -- )
    >R
    R@ _PICT-DROP-COPY  R@ _PICT-DROP-RICH
    0 R@ _PICT-O-CLAIM + !  0 R@ _PICT-SHOWN!  0 R@ _PICT-O-FAILED + !
    R@ _PICT-O-ALT-U + !  R@ _PICT-O-ALT-A + !
    DUP R@ _PICT-O-SOURCE + !
    ?DUP IF PIC-FILE DROP ELSE 0 0 0 THEN
    R@ _PICT-O-FILE-H + !  R@ _PICT-O-FILE-W + !  R@ _PICT-O-FILE-FORMAT + !
    1 _PICT-REVISIONS +!  _PICT-REVISIONS @ R@ _PICT-O-REVISION + !
    R> WDG-DIRTY ;

\ PICT-FREE ( widget -- )   Give back everything, the widget included.
: PICT-FREE  ( widget -- )
    0 OVER _PICT-SHOWN!
    DUP _PICT-DROP-COPY DUP _PICT-DROP-RICH FREE ;

\ PICT-CLAIMED? ( widget -- flag )
\   The rich side shows the picture, or is taking it to show it.
: PICT-CLAIMED?  ( widget -- flag )
    _PICT-O-CLAIM _PICT@ DUP 0<> SWAP _PICT-CLAIM-EPOCH @ = AND ;

\ PICT-CLAIM! ( flag widget -- )
\   The rich side says whether it shows the picture, or is taking it to
\   show it.  The CELL view follows at the next service pass or draw.
: PICT-CLAIM!  ( flag widget -- )
    SWAP IF _PICT-CLAIM-EPOCH @ ELSE -1 THEN
    2DUP SWAP _PICT-O-CLAIM + @ = IF 2DROP EXIT THEN
    OVER _PICT-O-CLAIM + ! WDG-DIRTY ;

\ PICT-RICH-FAILED! ( reason widget -- )
\   The rich side could not send the picture, for REASON, a PIC-R- reason:
\   the terminal refused its bytes as damaged, or they could not be read.
\   It takes the picture no more until the widget is given another source,
\   and CELL shows it, with the reason where CELL decodes no such file.  The
\   CELL view follows at the next service pass or draw.
: PICT-RICH-FAILED!  ( reason widget -- )
    2DUP _PICT-O-FAILED + @ <> IF
        TUCK _PICT-O-FAILED + ! DUP WDG-DIRTY
    ELSE
        NIP
    THEN
    0 SWAP PICT-CLAIM! ;

\ PICT-RICH-FAILED@ ( widget -- reason )
\   Why the rich side could not send the picture, or 0 while it may.
: PICT-RICH-FAILED@  ( widget -- reason )  _PICT-O-FAILED _PICT@ ;

\ PICT-RELEASE-ALL ( -- )
\   Let every claim go at once: the rich side shows no picture now, and
\   takes none until it says which formats it takes again.
: PICT-RELEASE-ALL  ( -- )
    1 _PICT-CLAIM-EPOCH +!  0 _PICT-RICH-FORMATS ! ;

\ PICT-PENDING? ( widget -- flag )
\   One of this widget's copies is decoding, or its CELL view shows the
\   label for a claim that has gone.
: PICT-PENDING?  ( widget -- flag )
    DUP _PICT-O-PENDING _PICT@ IF DROP -1 EXIT THEN
    DUP _PICT-O-SHOWN _PICT@ IF PICT-CLAIMED? 0= EXIT THEN
    DROP 0 ;

\ PICT-SERVICE ( budget widget -- changed? )
\   Decode about BUDGET source pixels, of the CELL copy while it decodes,
\   then of the rich copy.  A claimed picture's CELL copy still decoding
\   stops instead, and a label whose claim has gone gives way to the
\   picture.  True when what the widget shows, on either side, changed.
: PICT-SERVICE  ( budget widget -- changed? )
    DUP PICT-PENDING? 0= IF 2DROP 0 EXIT THEN
    >R
    R@ PICT-CLAIMED? IF
        R@ _PICT-O-CELL _PICT@ _PICT-COPY-PENDING? IF
            DROP R@ _PICT-DROP-COPY R> WDG-DIRTY -1 EXIT
        THEN
    ELSE
        \ The label goes: the rich side does not take the picture now, so
        \ its redraw is from the CELL copy.
        R@ _PICT-O-SHOWN _PICT@ IF
            DROP 0 R@ _PICT-SHOWN!  -1 R@ _PICT-O-CLAIM + !
            R> WDG-DIRTY -1 EXIT
        THEN
    THEN
    R@ _PICT-O-CELL _PICT@ _PICT-COPY-PENDING? IF
        R@ _PICT-O-CELL _PICT@
    ELSE R@ _PICT-O-RICH _PICT@ THEN
    PIC-STEP PIC-ST-PENDING = IF R> DROP 0 EXIT THEN
    R@ _PICT-SYNC
    R> WDG-DIRTY -1 ;

VARIABLE _PRA-W

\ PICT-RICH-ASK ( max-w max-h widget -- ok? )
\   Ask for a rich copy no larger than MAX-W by MAX-H pixels, for a terminal
\   that shows the picture at its own resolution.  A new bound gives back
\   the copy there was and starts another, which PICT-SERVICE decodes after
\   the CELL copy; the bound asked before keeps the copy there is.  False
\   when the memory source refused the copy's record, or nothing is shown.
: PICT-RICH-ASK  ( max-w max-h widget -- ok? )
    _PRA-W !
    _PRA-W @ _PICT-O-SOURCE _PICT@ 0= IF 2DROP 0 EXIT THEN
    _PRA-W @ _PICT-O-RICH _PICT@ IF
        OVER _PRA-W @ _PICT-O-RICH-W _PICT@ =
        OVER _PRA-W @ _PICT-O-RICH-H _PICT@ = AND IF 2DROP -1 EXIT THEN
    THEN
    _PRA-W @ _PICT-DROP-RICH
    PIC-SIZE _PRA-W @ _PICT-O-MSRC _PICT@ MSRC-ALLOC
    DUP 0= IF NIP NIP EXIT THEN                       ( w h rec )
    DUP _PRA-W @ _PICT-O-RICH + !
    >R 2DUP _PRA-W @ _PICT-O-RICH-H + !  _PRA-W @ _PICT-O-RICH-W + !
    _PRA-W @ _PICT-O-SOURCE _PICT@ _PRA-W @ _PICT-O-MSRC _PICT@ R>
    PIC-START DROP
    _PRA-W @ _PICT-SYNC -1 ;

\ PICT-RICH@ ( widget -- pic | 0 )
\   The rich copy asked for, pending, ready or failed, or 0.  Its pixels
\   stay the widget's: they go when it asks again, shows another picture or
\   is freed.
: PICT-RICH@  ( widget -- pic | 0 )  _PICT-O-RICH _PICT@ ;

\ PICT-REVISION@ ( widget -- revision )
\   Which picture the widget shows: a number no earlier source of any
\   picture widget had.  Every copy of one picture, at any size, shares
\   it, and another picture never does.  0 before the first source.
: PICT-REVISION@  ( widget -- revision )  _PICT-O-REVISION _PICT@ ;

\ PICT-FILE@ ( widget -- format width height )
\   The file's PIC-F- format and the picture's size, as its file says;
\   0 0 0 for no source or a file that is no picture PIC-FILE knows.
: PICT-FILE@  ( widget -- format width height )
    DUP _PICT-O-FILE-FORMAT _PICT@ OVER _PICT-O-FILE-W _PICT@
    ROT _PICT-O-FILE-H _PICT@ ;

\ PICT-FILE-BYTES@ ( widget -- bytes )   The file's length, 0 with none.
: PICT-FILE-BYTES@  ( widget -- bytes )
    _PICT-O-SOURCE _PICT@ ?DUP IF MEDSRC-SIZE@ ELSE 0 THEN ;

\ PICT-FILE-READ ( a u offset widget -- ior )
\   Read U bytes of the file at OFFSET into A, as its source reads them.
: PICT-FILE-READ  ( a u offset widget -- ior )
    _PICT-O-SOURCE _PICT@ ?DUP 0= IF 2DROP DROP -1 EXIT THEN
    MEDSRC-READ? ;

\ PICT-ALT! ( alt-a alt-u widget -- )   Change the text alternative alone.
: PICT-ALT!  ( alt-a alt-u widget -- )
    >R R@ _PICT-O-ALT-U + !  R@ _PICT-O-ALT-A + !  R> WDG-DIRTY ;

\ PICT-CELL-COPY@ ( widget -- pic | 0 )   The CELL copy, for inspection.
: PICT-CELL-COPY@  ( widget -- pic | 0 )  _PICT-O-CELL _PICT@ ;

\ =====================================================================
\  3. CELL drawing
\ =====================================================================

VARIABLE _PD-W        \ the widget
VARIABLE _PD-COLS     \ its area
VARIABLE _PD-ROWS
VARIABLE _PD-BG       \ its background palette index
VARIABLE _PD-BR  VARIABLE _PD-BG-G  VARIABLE _PD-BB   \ that background as RGB
VARIABLE _PD-PIC
VARIABLE _PD-OW  VARIABLE _PD-OH
VARIABLE _PD-LEFT     \ first cell column of the picture
VARIABLE _PD-TOP      \ first pixel row of the picture, in the area
VARIABLE _PD-PX       \ the copy's pixels
VARIABLE _PD-OUT      \ next colour byte

\ The palette index of pixel X Y of the copy, or the background outside it.
VARIABLE _PDC-A
: _PD-PIXEL  ( x y -- index )
    DUP 0< OVER _PD-OH @ < 0= OR IF 2DROP _PD-BG @ EXIT THEN
    OVER 0< 2 PICK _PD-OW @ < 0= OR IF 2DROP _PD-BG @ EXIT THEN
    _PD-OW @ * + 4 * _PD-PX @ +                       ( a )
    DUP 3 + C@ DUP _PDC-A !
    0= IF DROP _PD-BG @ EXIT THEN
    _PDC-A @ 255 = IF
        DUP C@ OVER 1+ C@ ROT 2 + C@ TUI-RESOLVE-COLOR EXIT
    THEN
    \ Partly transparent: blend each channel onto the background.
    DUP C@      _PDC-A @ * _PD-BR @   255 _PDC-A @ - * + 127 + 255 /
    OVER 1+ C@  _PDC-A @ * _PD-BG-G @ 255 _PDC-A @ - * + 127 + 255 /
    ROT 2 + C@  _PDC-A @ * _PD-BB @   255 _PDC-A @ - * + 127 + 255 /
    TUI-RESOLVE-COLOR ;

\ Work out every cell's two colours once, for this copy and background.
: _PD-COLOURS?  ( -- ok? )
    _PD-W @ _PICT-O-COLOURS _PICT@ IF
        _PD-W @ _PICT-O-COLOURS-BG _PICT@ _PD-BG @ = IF -1 EXIT THEN
        _PD-W @ _PICT-DROP-COLOURS
    THEN
    _PD-W @ _PICT-COLOURS-BYTES _PD-W @ _PICT-O-MSRC _PICT@ MSRC-ALLOC
    DUP 0= IF EXIT THEN
    DUP _PD-W @ _PICT-O-COLOURS + !  _PD-OUT !
    _PD-BG @ _PD-W @ _PICT-O-COLOURS-BG + !
    _PD-BG @ TUI-PALETTE>RGBA
    DUP 24 RSHIFT 255 AND _PD-BR !
    DUP 16 RSHIFT 255 AND _PD-BG-G !
    8 RSHIFT 255 AND _PD-BB !
    _PD-ROWS @ 0 ?DO
        _PD-COLS @ 0 ?DO
            I _PD-LEFT @ -  J 2* _PD-TOP @ -  _PD-PIXEL _PD-OUT @ C!
            I _PD-LEFT @ -  J 2* 1+ _PD-TOP @ - _PD-PIXEL _PD-OUT @ 1+ C!
            2 _PD-OUT +!
        LOOP
    LOOP -1 ;

\ Place the cells that are not plain background, in plain block cells, and
\ leave the caller's style as it was.
VARIABLE _PD-FG  VARIABLE _PD-ATTRS
: _PD-CELLS  ( -- )
    DRW-FG@ _PD-FG !  DRW-ATTR@ _PD-ATTRS !  0 DRW-ATTR!
    _PD-W @ _PICT-O-COLOURS _PICT@ _PD-OUT !
    _PD-ROWS @ 0 ?DO
        _PD-COLS @ 0 ?DO
            _PD-OUT @ C@ _PD-OUT @ 1+ C@                 ( upper lower )
            2DUP _PD-BG @ = SWAP _PD-BG @ = AND IF
                2DROP
            ELSE
                DRW-BG! DRW-FG!  _PICT-HALF J I DRW-CHAR
            THEN
            2 _PD-OUT +!
        LOOP
    LOOP
    _PD-FG @ DRW-FG!  _PD-BG @ DRW-BG!  _PD-ATTRS @ DRW-ATTR! ;

\ A one- or two-line label in the middle: the text alternative, if any,
\ then the message.
: _PD-LABEL  ( msg-a msg-u -- )
    _PD-ROWS @ 2/ _PD-W @ _PICT-O-ALT-U _PICT@ IF
        DUP 0> IF
            _PD-W @ _PICT-O-ALT-A _PICT@ _PD-W @ _PICT-O-ALT-U _PICT@
            2 PICK 1- 0 _PD-COLS @ DRW-TEXT-CENTER
        THEN
    THEN
    0 _PD-COLS @ DRW-TEXT-CENTER ;

48 CONSTANT _PD-FACTS-CAP
CREATE _PD-FACTS-BUF _PD-FACTS-CAP ALLOT
VARIABLE _PD-FACTS-U

: _PD-FACTS-ADD  ( a u -- )
    _PD-FACTS-CAP _PD-FACTS-U @ - MIN
    DUP >R _PD-FACTS-BUF _PD-FACTS-U @ + SWAP CMOVE R> _PD-FACTS-U +! ;

\ What the picture file is: its format and size, as "PNG, 1920 × 1080".
: _PD-FACTS  ( -- )
    0 _PD-FACTS-U !
    _PD-W @ _PICT-O-FILE-FORMAT _PICT@ CASE
        PIC-F-QOI  OF S" QOI" ENDOF
        PIC-F-PNG  OF S" PNG" ENDOF
        PIC-F-JPEG OF S" JPEG" ENDOF
        >R S" Picture" R>
    ENDCASE _PD-FACTS-ADD
    S" , " _PD-FACTS-ADD
    _PD-W @ _PICT-O-FILE-W _PICT@ NUM>STR _PD-FACTS-ADD
    S"  × " _PD-FACTS-ADD
    _PD-W @ _PICT-O-FILE-H _PICT@ NUM>STR _PD-FACTS-ADD
    _PD-FACTS-BUF _PD-FACTS-U @ _PD-LABEL ;

: _PD-REASON  ( reason -- )
    CASE
        PIC-R-UNSUPPORTED OF S" This picture's format can't be shown yet" ENDOF
        PIC-R-DAMAGED     OF S" The picture is damaged" ENDOF
        PIC-R-READ        OF S" The picture could not be read" ENDOF
        PIC-R-MEMORY      OF S" Not enough memory to show the picture" ENDOF
        >R S" The picture could not be shown" R>
    ENDCASE _PD-LABEL ;

: _PD-READY  ( -- )
    _PD-PIC @ PIC-WIDTH@ _PD-OW !  _PD-PIC @ PIC-HEIGHT@ _PD-OH !
    _PD-PIC @ PIC-PIXELS DROP _PD-PX !
    _PD-COLS @ _PD-OW @ - 2/ _PD-LEFT !
    _PD-ROWS @ 2* _PD-OH @ - 2/ _PD-TOP !
    _PD-COLOURS? 0= IF S" Not enough memory to show the picture" _PD-LABEL EXIT THEN
    _PD-CELLS ;

: _PICT-DO-DRAW  ( widget -- )
    DUP _PD-W !
    WDG-REGION DUP RGN-W _PD-COLS ! RGN-H _PD-ROWS !
    DRW-BG@ _PD-BG !
    32 0 0 _PD-ROWS @ _PD-COLS @ DRW-FILL-RECT
    0 _PD-W @ _PICT-SHOWN!
    _PD-COLS @ 1 < _PD-ROWS @ 1 < OR IF EXIT THEN
    _PD-W @ _PICT-O-SOURCE _PICT@ 0= IF EXIT THEN
    \ While the rich side shows the picture, CELL shows what it is beneath
    \ and decodes nothing; a copy already made stays for later.
    _PD-W @ PICT-CLAIMED? IF
        _PD-W @ _PICT-O-CELL _PICT@ _PICT-COPY-PENDING? IF
            _PD-W @ _PICT-DROP-COPY
        THEN
        -1 _PD-W @ _PICT-SHOWN!  _PD-FACTS EXIT
    THEN
    \ A picture of a format the rich side takes, which it has not yet looked
    \ at, shows what it is from its first draw rather than start a CELL copy.
    _PD-W @ _PICT-O-CLAIM _PICT@ 0=
    _PD-W @ _PICT-O-FILE-FORMAT _PICT@ ?DUP IF
        1- 1 SWAP LSHIFT _PICT-RICH-FORMATS @ AND 0<>
    ELSE 0 THEN AND IF
        -1 _PD-W @ _PICT-SHOWN!  _PD-FACTS EXIT
    THEN
    \ A picture file CELL does not decode shows what it is, or why the
    \ rich side could not show it.
    _PD-W @ _PICT-O-FILE-FORMAT _PICT@ DUP 0<> SWAP PIC-DECODES? 0= AND IF
        _PD-W @ _PICT-O-FAILED _PICT@ ?DUP IF _PD-REASON EXIT THEN
        _PD-FACTS EXIT
    THEN
    _PD-W @ _PICT-O-CELL _PICT@ 0<>
    _PD-W @ _PICT-O-CELL-W _PICT@ _PD-COLS @ = AND
    _PD-W @ _PICT-O-CELL-H _PICT@ _PD-ROWS @ = AND 0= IF
        _PD-COLS @ _PD-ROWS @ _PD-W @ _PICT-START-COPY 0= IF
            S" Not enough memory to show the picture" _PD-LABEL EXIT
        THEN
    THEN
    _PD-W @ _PICT-O-CELL _PICT@ DUP _PD-PIC !
    PIC-STATE@ CASE
        PIC-ST-READY   OF _PD-READY ENDOF
        PIC-ST-FAILED  OF
            \ A file the copy cannot read, such as an interlaced PNG,
            \ shows what it is.
            _PD-PIC @ PIC-REASON@ DUP PIC-R-UNSUPPORTED =
            _PD-W @ _PICT-O-FILE-FORMAT _PICT@ 0<> AND IF DROP _PD-FACTS
            ELSE _PD-REASON THEN
        ENDOF
        >R S" Loading the picture" _PD-LABEL R>
    ENDCASE ;

' _PICT-DO-DRAW IS _PICT-DRAW-D

\ =====================================================================
\  4. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _pict-guard

' PICT-NEW      CONSTANT _pict-new-xt
' PICT-SOURCE!  CONSTANT _pict-source-xt
' PICT-FREE     CONSTANT _pict-free-xt
' PICT-SERVICE  CONSTANT _pict-service-xt
' PICT-ALT!     CONSTANT _pict-alt-xt
' PICT-RICH-ASK CONSTANT _pict-rich-ask-xt
' PICT-CLAIM!   CONSTANT _pict-claim-xt
' PICT-RICH-FAILED! CONSTANT _pict-rich-failed-xt
' PICT-RELEASE-ALL CONSTANT _pict-release-all-xt
' PICT-RICH-FORMATS! CONSTANT _pict-rich-formats-xt

: PICT-NEW      _pict-new-xt     _pict-guard WITH-GUARD ;
: PICT-SOURCE!  _pict-source-xt  _pict-guard WITH-GUARD ;
: PICT-FREE     _pict-free-xt    _pict-guard WITH-GUARD ;
: PICT-SERVICE  _pict-service-xt _pict-guard WITH-GUARD ;
: PICT-ALT!     _pict-alt-xt     _pict-guard WITH-GUARD ;
: PICT-RICH-ASK _pict-rich-ask-xt _pict-guard WITH-GUARD ;
: PICT-CLAIM!   _pict-claim-xt   _pict-guard WITH-GUARD ;
: PICT-RICH-FAILED! _pict-rich-failed-xt _pict-guard WITH-GUARD ;
: PICT-RELEASE-ALL _pict-release-all-xt _pict-guard WITH-GUARD ;
: PICT-RICH-FORMATS! _pict-rich-formats-xt _pict-guard WITH-GUARD ;
[THEN] [THEN]
