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
\  source.
\
\  While the picture decodes, when it cannot be shown, and when the widget
\  is too small for it, the widget says so in a short label.  Decoding runs
\  in bounded steps from PICT-SERVICE, which the UIDL host calls each pass,
\  so drawing never waits for it.  The widget asks media/picture.f for a
\  copy two pixels a cell high, the size it shows, and keeps the palette
\  colour of every cell, so a redraw only places cells.
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
\   +112  pending      this widget's copy is decoding
\
\  Prefix: PICT- (public), _PICT- (internal)
\  Provider: akashic-tui-picture
\  Dependencies: widget.f, draw.f, color.f, media/picture.f

PROVIDED akashic-tui-picture

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../color.f
REQUIRE ../../media/picture.f
REQUIRE ../../utils/memory-source.f

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
120 CONSTANT _PICT-DESC-SIZE

\ Upper half block: foreground is the upper pixel, background the lower.
0x2580 CONSTANT _PICT-HALF

\ How many source pixels one service pass decodes for one widget.
16384 CONSTANT PICT-STEP-PIXELS

\ Widgets whose copy is decoding, in any document.
VARIABLE _PICT-PENDING-COUNT   0 _PICT-PENDING-COUNT !

\ PICT-WORK? ( -- flag )   Some picture is still decoding.
: PICT-WORK?  ( -- flag )  _PICT-PENDING-COUNT @ 0<> ;

: _PICT@  ( w offset -- x )  + @ ;

: _PICT-PENDING!  ( flag w -- )
    2DUP _PICT-O-PENDING + @ 0<> = IF 2DROP EXIT THEN
    OVER IF 1 ELSE -1 THEN _PICT-PENDING-COUNT +!
    SWAP 0<> SWAP _PICT-O-PENDING + ! ;

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

\ Give back the CELL copy and everything made from it.
: _PICT-DROP-COPY  ( w -- )
    DUP _PICT-DROP-COLOURS
    DUP _PICT-O-CELL _PICT@ ?DUP IF
        DUP PIC-FREE
        PIC-SIZE 2 PICK _PICT-O-MSRC _PICT@ MSRC-FREE
    THEN
    0 OVER _PICT-O-CELL + !
    0 OVER _PICT-O-CELL-W + !  0 OVER _PICT-O-CELL-H + !
    0 SWAP _PICT-PENDING! ;

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
    PIC-START PIC-ST-PENDING = _PSC-W @ _PICT-PENDING!
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
\   source shows nothing.  Both are borrowed.
: PICT-SOURCE!  ( source alt-a alt-u widget -- )
    >R
    R@ _PICT-DROP-COPY
    R@ _PICT-O-ALT-U + !  R@ _PICT-O-ALT-A + !
    R@ _PICT-O-SOURCE + !
    R> WDG-DIRTY ;

\ PICT-FREE ( widget -- )   Give back everything, the widget included.
: PICT-FREE  ( widget -- )
    DUP _PICT-DROP-COPY FREE ;

\ PICT-SERVICE ( budget widget -- changed? )
\   Decode about BUDGET source pixels of the CELL copy.  True when the copy
\   just finished or failed, so what the widget shows changed.
: PICT-SERVICE  ( budget widget -- changed? )
    DUP _PICT-O-PENDING _PICT@ 0= IF 2DROP 0 EXIT THEN
    >R R@ _PICT-O-CELL _PICT@ PIC-STEP PIC-ST-PENDING = IF R> DROP 0 EXIT THEN
    0 R@ _PICT-PENDING!
    R> WDG-DIRTY -1 ;

\ PICT-ALT! ( alt-a alt-u widget -- )   Change the text alternative alone.
: PICT-ALT!  ( alt-a alt-u widget -- )
    >R R@ _PICT-O-ALT-U + !  R@ _PICT-O-ALT-A + !  R> WDG-DIRTY ;

\ PICT-PENDING? ( widget -- flag )   This widget's copy is still decoding.
: PICT-PENDING?  ( widget -- flag )  _PICT-O-PENDING _PICT@ 0<> ;

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
    _PD-COLS @ 1 < _PD-ROWS @ 1 < OR IF EXIT THEN
    _PD-W @ _PICT-O-SOURCE _PICT@ 0= IF EXIT THEN
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
        PIC-ST-FAILED  OF _PD-PIC @ PIC-REASON@ _PD-REASON ENDOF
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

: PICT-NEW      _pict-new-xt     _pict-guard WITH-GUARD ;
: PICT-SOURCE!  _pict-source-xt  _pict-guard WITH-GUARD ;
: PICT-FREE     _pict-free-xt    _pict-guard WITH-GUARD ;
: PICT-SERVICE  _pict-service-xt _pict-guard WITH-GUARD ;
: PICT-ALT!     _pict-alt-xt     _pict-guard WITH-GUARD ;
[THEN] [THEN]
