\ =====================================================================
\ dialog-model.f -- Caller-owned canonical DIALOG values
\ =====================================================================
\ ABI 1 is pointer-free: header160, the title/pad8, the message/pad8,
\ then one record a button: header72, its label/pad8 and its shortcut's
\ text/pad8, which may be empty.  The message is
\ the lines the dialog shows, joined by line feeds.  The title, the
\ message and each button have a slot, a rectangle of cells inside the
\ dialog's root, and no two slots meet.  A notice has no buttons.  This is
\ ordinary application data, independent of terminal wire formats.
\
\ A writer measures the model with UDLG-TEXT-BYTES and UDLG-BUTTON-BYTES,
\ owns that many aligned bytes, and writes with UDLG-START, then
\ UDLG-TITLE!, UDLG-MESSAGE-SLOT! and UDLG-LINE+ for each line, then
\ UDLG-BUTTON+ for each button.  UDLG-VALIDATE proves the result.
PROVIDED akashic-tui-dialog-model
REQUIRE status-field-model.f

0 CONSTANT UDLG-S-OK
1 CONSTANT UDLG-S-UNSUPPORTED
2 CONSTANT UDLG-S-CAPACITY
3 CONSTANT UDLG-S-INVALID
1 CONSTANT UDLG-ABI
1 CONSTANT UDLG-F-NOTICE
\ Severities are a status field's: neutral, info, success, warning, error.
4 CONSTANT UDLG-SEVERITY-MAX
1 CONSTANT UDLG-B-DEFAULT
2 CONSTANT UDLG-B-CANCEL
4 CONSTANT UDLG-B-DESTRUCTIVE
1 CONSTANT UDLG-STATE-VISIBLE
2 CONSTANT UDLG-STATE-ENABLED
4 CONSTANT UDLG-STATE-SELECTED
160 CONSTANT UDLG-HEADER-SIZE
72 CONSTANT UDLG-BUTTON-HEADER-SIZE
0 CONSTANT UDLG-BYTES-OFFSET
8 CONSTANT UDLG-ABI-OFFSET
16 CONSTANT UDLG-KEY-OFFSET
24 CONSTANT UDLG-REVISION-OFFSET
32 CONSTANT UDLG-WIDTH-OFFSET
40 CONSTANT UDLG-HEIGHT-OFFSET
48 CONSTANT UDLG-FLAGS-OFFSET
56 CONSTANT UDLG-SEVERITY-OFFSET
\ Each slot is four cells: row, column, height and width, all zero when
\ the slot is absent.
64 CONSTANT UDLG-TITLE-SLOT-OFFSET
96 CONSTANT UDLG-MESSAGE-SLOT-OFFSET
128 CONSTANT UDLG-TITLE-BYTES-OFFSET
136 CONSTANT UDLG-MESSAGE-BYTES-OFFSET
144 CONSTANT UDLG-BUTTON-COUNT-OFFSET
\ 152 is reserved and zero.
0 CONSTANT UDLG-BUTTON-BYTES-OFFSET
8 CONSTANT UDLG-BUTTON-ROLES-OFFSET
16 CONSTANT UDLG-BUTTON-STATE-OFFSET
24 CONSTANT UDLG-BUTTON-SLOT-OFFSET
56 CONSTANT UDLG-BUTTON-LABEL-BYTES-OFFSET
64 CONSTANT UDLG-BUTTON-SHORTCUT-BYTES-OFFSET

CREATE _UDLG-OWNED-START
VARIABLE _UDLG-OWNED-LIMIT
0 _UDLG-OWNED-LIMIT !

: UDLG-BYTES@ ( model -- value ) UDLG-BYTES-OFFSET + @ ;
: UDLG-ABI@ ( model -- value ) UDLG-ABI-OFFSET + @ ;
: UDLG-KEY@ ( model -- value ) UDLG-KEY-OFFSET + @ ;
: UDLG-REVISION@ ( model -- value ) UDLG-REVISION-OFFSET + @ ;
: UDLG-WIDTH@ ( model -- value ) UDLG-WIDTH-OFFSET + @ ;
: UDLG-HEIGHT@ ( model -- value ) UDLG-HEIGHT-OFFSET + @ ;
: UDLG-FLAGS@ ( model -- value ) UDLG-FLAGS-OFFSET + @ ;
: UDLG-SEVERITY@ ( model -- value ) UDLG-SEVERITY-OFFSET + @ ;
: UDLG-TITLE-BYTES@ ( model -- value ) UDLG-TITLE-BYTES-OFFSET + @ ;
: UDLG-MESSAGE-BYTES@ ( model -- value ) UDLG-MESSAGE-BYTES-OFFSET + @ ;
: UDLG-BUTTON-COUNT@ ( model -- value ) UDLG-BUTTON-COUNT-OFFSET + @ ;
\ SLOT@ reads the four cells of a slot at its address.
: UDLG-SLOT@ ( slot -- row col height width )
    DUP @ OVER 8 + @ 2 PICK 16 + @ 3 PICK 24 + @ >R >R >R NIP R> R> R> ;
: UDLG-TITLE-SLOT@ ( model -- row col height width )
    UDLG-TITLE-SLOT-OFFSET + UDLG-SLOT@ ;
: UDLG-MESSAGE-SLOT@ ( model -- row col height width )
    UDLG-MESSAGE-SLOT-OFFSET + UDLG-SLOT@ ;

: _UDLG-ALIGN8 ( u -- aligned ) 7 + -8 AND ;
: UDLG-TITLE@ ( model -- a u ) DUP UDLG-HEADER-SIZE + SWAP UDLG-TITLE-BYTES@ ;
: UDLG-MESSAGE@ ( model -- a u )
    DUP UDLG-TITLE-BYTES@ _UDLG-ALIGN8 UDLG-HEADER-SIZE + OVER +
    SWAP UDLG-MESSAGE-BYTES@ ;
: UDLG-BUTTON-FIRST ( model -- button ) UDLG-MESSAGE@ _UDLG-ALIGN8 + ;
: UDLG-BUTTON-NEXT ( button -- next ) DUP @ + ;
: UDLG-BUTTON-ROLES@ ( button -- roles ) UDLG-BUTTON-ROLES-OFFSET + @ ;
: UDLG-BUTTON-STATE@ ( button -- state ) UDLG-BUTTON-STATE-OFFSET + @ ;
: UDLG-BUTTON-SLOT@ ( button -- row col height width )
    UDLG-BUTTON-SLOT-OFFSET + UDLG-SLOT@ ;
: UDLG-BUTTON-LABEL@ ( button -- a u )
    DUP UDLG-BUTTON-HEADER-SIZE + SWAP UDLG-BUTTON-LABEL-BYTES-OFFSET + @ ;
\ The text of the key that chooses the button, empty when none does.
: UDLG-BUTTON-SHORTCUT@ ( button -- a u )
    DUP UDLG-BUTTON-LABEL@ _UDLG-ALIGN8 +
    SWAP UDLG-BUTTON-SHORTCUT-BYTES-OFFSET + @ ;
\ The title, the message with its line feeds, and every label and
\ shortcut.
: UDLG-UTF8-BYTES@ ( validated-model -- bytes )
    DUP UDLG-TITLE-BYTES@ OVER UDLG-MESSAGE-BYTES@ + SWAP
    DUP UDLG-BUTTON-COUNT@ SWAP UDLG-BUTTON-FIRST SWAP
    0 ?DO
        DUP UDLG-BUTTON-LABEL@ NIP ROT + OVER UDLG-BUTTON-SHORTCUT@ NIP +
        SWAP UDLG-BUTTON-NEXT
    LOOP DROP ;

: UDLG-STORAGE-DISJOINT? ( address bytes -- flag )
    2DUP USF-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    _UDLG-OWNED-LIMIT @ DUP _UDLG-OWNED-START U< IF DROP 2DROP 0 EXIT THEN
    _UDLG-OWNED-START - _UDLG-OWNED-START SWAP MSPAN-OVERLAP? 0= ;
: _UDLG-U32? ( n -- flag ) 0x100000000 U< ;
: _UDLG-POS32? ( n -- flag ) DUP 0<> SWAP _UDLG-U32? AND ;
: _UDLG-COORD? ( n -- flag ) 0x80000000 U< ;
: _UDLG-ZERO? ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;
: _UDLG-ALIGNED-SPAN? ( a u -- flag )
    OVER DUP 0= SWAP 7 AND OR IF 2DROP 0 EXIT THEN UDLG-STORAGE-DISJOINT? ;

VARIABLE _UDLG-V-M
VARIABLE _UDLG-V-U
VARIABLE _UDLG-V-O
VARIABLE _UDLG-V-N
VARIABLE _UDLG-V-R
VARIABLE _UDLG-V-Q
VARIABLE _UDLG-V-P
VARIABLE _UDLG-V-END
VARIABLE _UDLG-V-LINE
VARIABLE _UDLG-V-LINES
VARIABLE _UDLG-V-DEFAULTS
VARIABLE _UDLG-V-CANCELS
VARIABLE _UDLG-V-SELECTED
VARIABLE _UDLG-S-R VARIABLE _UDLG-S-C VARIABLE _UDLG-S-H VARIABLE _UDLG-S-W

: _UDLG-HEADER? ( -- flag )
    _UDLG-V-M @ UDLG-BYTES@ _UDLG-V-U @ <> IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-KEY@ 0= _UDLG-V-M @ UDLG-REVISION@ 0= OR IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-WIDTH@ _UDLG-POS32? 0=
    _UDLG-V-M @ UDLG-HEIGHT@ _UDLG-POS32? 0= OR IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-FLAGS@ UDLG-F-NOTICE INVERT AND IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-SEVERITY@ UDLG-SEVERITY-MAX U> IF 0 EXIT THEN
    _UDLG-V-M @ 152 + @ IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-TITLE-BYTES@ _UDLG-U32? 0=
    _UDLG-V-M @ UDLG-MESSAGE-BYTES@ _UDLG-U32? 0= OR
    _UDLG-V-M @ UDLG-BUTTON-COUNT@ _UDLG-U32? 0= OR IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-FLAGS@ UDLG-F-NOTICE AND
    _UDLG-V-M @ UDLG-BUTTON-COUNT@ 0<> AND 0= ;

\ The slot at an address becomes the current one, S.
: _UDLG-SLOT! ( slot -- )
    UDLG-SLOT@ _UDLG-S-W ! _UDLG-S-H ! _UDLG-S-C ! _UDLG-S-R ! ;
: _UDLG-ABSENT? ( -- flag )
    _UDLG-S-R @ _UDLG-S-C @ OR _UDLG-S-H @ OR _UDLG-S-W @ OR 0= ;
\ A present slot has a nonnegative origin and positive extents inside the
\ root.
: _UDLG-PRESENT? ( -- flag )
    _UDLG-S-R @ _UDLG-COORD? 0= _UDLG-S-C @ _UDLG-COORD? 0= OR IF 0 EXIT THEN
    _UDLG-S-H @ _UDLG-POS32? 0= _UDLG-S-W @ _UDLG-POS32? 0= OR IF 0 EXIT THEN
    _UDLG-S-R @ _UDLG-S-H @ + _UDLG-V-M @ UDLG-HEIGHT@ U> IF 0 EXIT THEN
    _UDLG-S-C @ _UDLG-S-W @ + _UDLG-V-M @ UDLG-WIDTH@ U> 0= ;
\ Whether slot S and the slot at an address share a cell.  An absent slot
\ shares none.
: _UDLG-MEETS? ( slot -- flag )
    >R
    _UDLG-S-R @ R@ @ R@ 16 + @ + U<
    R@ @ _UDLG-S-R @ _UDLG-S-H @ + U< AND
    _UDLG-S-C @ R@ 8 + @ R@ 24 + @ + U< AND
    R> 8 + @ _UDLG-S-C @ _UDLG-S-W @ + U< AND ;

\ Validate one padded string of clean single-line text at the offset,
\ advancing it.
: _UDLG-V-STRING? ( bytes -- flag )
    _UDLG-V-N !
    _UDLG-V-N @ _UDLG-ALIGN8 _UDLG-V-U @ _UDLG-V-O @ - U> IF 0 EXIT THEN
    _UDLG-V-N @ IF
        _UDLG-V-M @ _UDLG-V-O @ + _UDLG-V-N @ USF-TEXT? 0= IF 0 EXIT THEN
    THEN
    _UDLG-V-M @ _UDLG-V-O @ + _UDLG-V-N @ +
    _UDLG-V-N @ _UDLG-ALIGN8 _UDLG-V-N @ - _UDLG-ZERO? 0= IF 0 EXIT THEN
    _UDLG-V-N @ _UDLG-ALIGN8 _UDLG-V-O +! -1 ;

\ The message's lines are empty or clean single-line text, split at line
\ feeds, which are ASCII and never inside a UTF-8 sequence.
: _UDLG-LINE? ( a u -- flag ) DUP 0= IF 2DROP -1 EXIT THEN USF-TEXT? ;
: _UDLG-V-MESSAGE? ( -- flag )
    _UDLG-V-M @ UDLG-MESSAGE-BYTES@ _UDLG-V-N !
    _UDLG-V-N @ _UDLG-ALIGN8 _UDLG-V-U @ _UDLG-V-O @ - U> IF 0 EXIT THEN
    _UDLG-V-M @ _UDLG-V-O @ + DUP _UDLG-V-P ! _UDLG-V-LINE !
    _UDLG-V-P @ _UDLG-V-N @ + _UDLG-V-END !
    _UDLG-V-N @ 0<> 1 AND _UDLG-V-LINES !
    BEGIN _UDLG-V-P @ _UDLG-V-END @ U< WHILE
        _UDLG-V-P @ C@ 10 = IF
            _UDLG-V-LINE @ _UDLG-V-P @ OVER - _UDLG-LINE? 0= IF 0 EXIT THEN
            _UDLG-V-P @ 1+ _UDLG-V-LINE !
            1 _UDLG-V-LINES +!
        THEN
        1 _UDLG-V-P +!
    REPEAT
    _UDLG-V-LINE @ _UDLG-V-END @ OVER - _UDLG-LINE? 0= IF 0 EXIT THEN
    _UDLG-V-LINES @ _UDLG-V-M @ UDLG-MESSAGE-SLOT-OFFSET + 16 + @ U> IF
        0 EXIT
    THEN
    _UDLG-V-END @ _UDLG-V-N @ _UDLG-ALIGN8 _UDLG-V-N @ - _UDLG-ZERO? 0= IF
        0 EXIT
    THEN
    _UDLG-V-N @ _UDLG-ALIGN8 _UDLG-V-O +! -1 ;

\ At most one default and one cancel button, and no destructive default.
: _UDLG-V-ROLES? ( roles -- flag )
    DUP 7 INVERT AND IF DROP 0 EXIT THEN
    DUP UDLG-B-DEFAULT UDLG-B-DESTRUCTIVE OR AND
        UDLG-B-DEFAULT UDLG-B-DESTRUCTIVE OR = IF DROP 0 EXIT THEN
    DUP UDLG-B-DEFAULT AND IF 1 _UDLG-V-DEFAULTS +! THEN
    UDLG-B-CANCEL AND IF 1 _UDLG-V-CANCELS +! THEN
    _UDLG-V-DEFAULTS @ 2 < _UDLG-V-CANCELS @ 2 < AND ;

\ At most one button is selected, and only a visible enabled one.
: _UDLG-V-STATE? ( state -- flag )
    DUP 7 INVERT AND IF DROP 0 EXIT THEN
    DUP UDLG-STATE-SELECTED AND IF
        3 AND 3 <> IF 0 EXIT THEN
        1 _UDLG-V-SELECTED +! _UDLG-V-SELECTED @ 2 < EXIT
    THEN DROP -1 ;

\ The current button's slot S meets no earlier button's.
: _UDLG-V-PRIOR-APART? ( -- flag )
    _UDLG-V-M @ UDLG-BUTTON-FIRST _UDLG-V-Q !
    BEGIN _UDLG-V-Q @ _UDLG-V-R @ U< WHILE
        _UDLG-V-Q @ UDLG-BUTTON-SLOT-OFFSET + _UDLG-MEETS? IF 0 EXIT THEN
        _UDLG-V-Q @ UDLG-BUTTON-NEXT _UDLG-V-Q !
    REPEAT -1 ;

: _UDLG-V-BUTTON? ( -- flag )
    _UDLG-V-U @ _UDLG-V-O @ - UDLG-BUTTON-HEADER-SIZE U< IF 0 EXIT THEN
    _UDLG-V-M @ _UDLG-V-O @ + _UDLG-V-R !
    _UDLG-V-R @ UDLG-BUTTON-LABEL@ NIP DUP 0= IF DROP 0 EXIT THEN
    DUP _UDLG-U32? 0= IF DROP 0 EXIT THEN
    _UDLG-V-R @ UDLG-BUTTON-SHORTCUT-BYTES-OFFSET + @
        DUP _UDLG-U32? 0= IF 2DROP 0 EXIT THEN
    _UDLG-ALIGN8 SWAP _UDLG-ALIGN8 + UDLG-BUTTON-HEADER-SIZE +
        _UDLG-V-R @ UDLG-BUTTON-BYTES-OFFSET + @ <> IF 0 EXIT THEN
    _UDLG-V-R @ UDLG-BUTTON-ROLES@ _UDLG-V-ROLES? 0= IF 0 EXIT THEN
    _UDLG-V-R @ UDLG-BUTTON-STATE@ _UDLG-V-STATE? 0= IF 0 EXIT THEN
    _UDLG-V-R @ UDLG-BUTTON-SLOT-OFFSET + _UDLG-SLOT!
    _UDLG-PRESENT? 0= IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-TITLE-SLOT-OFFSET + _UDLG-MEETS? IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-MESSAGE-SLOT-OFFSET + _UDLG-MEETS? IF 0 EXIT THEN
    _UDLG-V-PRIOR-APART? 0= IF 0 EXIT THEN
    UDLG-BUTTON-HEADER-SIZE _UDLG-V-O +!
    _UDLG-V-R @ UDLG-BUTTON-LABEL@ NIP _UDLG-V-STRING? 0= IF 0 EXIT THEN
    _UDLG-V-R @ UDLG-BUTTON-SHORTCUT-BYTES-OFFSET + @ _UDLG-V-STRING? ;

: _UDLG-V-BUTTONS? ( -- flag )
    0 _UDLG-V-DEFAULTS ! 0 _UDLG-V-CANCELS ! 0 _UDLG-V-SELECTED !
    _UDLG-V-M @ UDLG-BUTTON-COUNT@
        _UDLG-V-U @ _UDLG-V-O @ - UDLG-BUTTON-HEADER-SIZE / U> IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-BUTTON-COUNT@ 0 ?DO
        _UDLG-V-BUTTON? 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

\ The title's slot is present exactly when it has text, as is the
\ message's, and the two do not meet.
: _UDLG-V-SLOTS? ( -- flag )
    _UDLG-V-M @ UDLG-TITLE-SLOT-OFFSET + _UDLG-SLOT!
    _UDLG-V-M @ UDLG-TITLE-BYTES@ IF _UDLG-PRESENT? ELSE _UDLG-ABSENT? THEN
        0= IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-MESSAGE-SLOT-OFFSET + _UDLG-SLOT!
    _UDLG-V-M @ UDLG-MESSAGE-BYTES@ IF _UDLG-PRESENT? ELSE _UDLG-ABSENT? THEN
        0= IF 0 EXIT THEN
    _UDLG-V-M @ UDLG-TITLE-SLOT-OFFSET + _UDLG-MEETS? 0= ;

: UDLG-VALIDATE ( model bytes -- status )
    2DUP _UDLG-ALIGNED-SPAN? 0= IF 2DROP UDLG-S-INVALID EXIT THEN
    DUP UDLG-HEADER-SIZE U< IF 2DROP UDLG-S-INVALID EXIT THEN
    _UDLG-V-U ! _UDLG-V-M !
    _UDLG-V-M @ UDLG-ABI@ UDLG-ABI <> IF UDLG-S-UNSUPPORTED EXIT THEN
    _UDLG-HEADER? 0= IF UDLG-S-INVALID EXIT THEN
    _UDLG-V-SLOTS? 0= IF UDLG-S-INVALID EXIT THEN
    UDLG-HEADER-SIZE _UDLG-V-O !
    _UDLG-V-M @ UDLG-TITLE-BYTES@ _UDLG-V-STRING? 0= IF UDLG-S-INVALID EXIT THEN
    _UDLG-V-MESSAGE? 0= IF UDLG-S-INVALID EXIT THEN
    _UDLG-V-BUTTONS? 0= IF UDLG-S-INVALID EXIT THEN
    _UDLG-V-O @ _UDLG-V-U @ = IF UDLG-S-OK ELSE UDLG-S-INVALID THEN ;

\ =====================================================================
\  Writing
\ =====================================================================

\ The bytes of the header, the title and the message, and of one button.
: UDLG-TEXT-BYTES ( title-u message-u -- bytes )
    _UDLG-ALIGN8 SWAP _UDLG-ALIGN8 + UDLG-HEADER-SIZE + ;
: UDLG-BUTTON-BYTES ( label-u shortcut-u -- bytes )
    _UDLG-ALIGN8 SWAP _UDLG-ALIGN8 + UDLG-BUTTON-HEADER-SIZE + ;

VARIABLE _UDLG-W-M
VARIABLE _UDLG-W-P
VARIABLE _UDLG-W-S
VARIABLE _UDLG-W-LINES
VARIABLE _UDLG-W-SA
VARIABLE _UDLG-W-SU

\ BYTES always holds the end of what is written.
: _UDLG-W-TEXT-END! ( -- )
    _UDLG-W-M @ UDLG-TITLE-BYTES@ _UDLG-W-M @ UDLG-MESSAGE-BYTES@
    UDLG-TEXT-BYTES _UDLG-W-M @ UDLG-BYTES-OFFSET + ! ;

\ Copy A U to DST and zero its padding.
: _UDLG-W-TEXT ( a u dst -- )
    2DUP SWAP _UDLG-ALIGN8 0 FILL SWAP MOVE ;

: UDLG-START ( key revision width height flags severity model -- )
    DUP _UDLG-W-M ! UDLG-HEADER-SIZE 0 FILL
    _UDLG-W-M @ UDLG-SEVERITY-OFFSET + ! _UDLG-W-M @ UDLG-FLAGS-OFFSET + !
    _UDLG-W-M @ UDLG-HEIGHT-OFFSET + ! _UDLG-W-M @ UDLG-WIDTH-OFFSET + !
    _UDLG-W-M @ UDLG-REVISION-OFFSET + ! _UDLG-W-M @ UDLG-KEY-OFFSET + !
    UDLG-ABI _UDLG-W-M @ UDLG-ABI-OFFSET + !
    UDLG-HEADER-SIZE _UDLG-W-M @ UDLG-BYTES-OFFSET + !
    0 _UDLG-W-LINES ! ;

\ Store a slot's four cells at an address.
: _UDLG-SLOT-STORE ( row col height width slot -- )
    _UDLG-W-S ! _UDLG-W-S @ 24 + ! _UDLG-W-S @ 16 + !
    _UDLG-W-S @ 8 + ! _UDLG-W-S @ ! ;

: UDLG-TITLE! ( row col height width a u model -- )
    _UDLG-W-M !
    DUP _UDLG-W-M @ UDLG-TITLE-BYTES-OFFSET + !
    _UDLG-W-M @ UDLG-HEADER-SIZE + _UDLG-W-TEXT
    _UDLG-W-M @ UDLG-TITLE-SLOT-OFFSET + _UDLG-SLOT-STORE
    _UDLG-W-TEXT-END! ;

: UDLG-MESSAGE-SLOT! ( row col height width model -- )
    UDLG-MESSAGE-SLOT-OFFSET + _UDLG-SLOT-STORE ;

\ Append one line to the message, after a line feed unless it is the
\ first; a line may be empty.
: UDLG-LINE+ ( a u model -- )
    _UDLG-W-M !
    _UDLG-W-M @ UDLG-MESSAGE@ + _UDLG-W-P !
    _UDLG-W-LINES @ IF
        10 _UDLG-W-P @ C! 1 _UDLG-W-P +!
        1 _UDLG-W-M @ UDLG-MESSAGE-BYTES-OFFSET + +!
    THEN
    1 _UDLG-W-LINES +!
    DUP _UDLG-W-M @ UDLG-MESSAGE-BYTES-OFFSET + +!
    _UDLG-W-P @ SWAP MOVE
    _UDLG-W-M @ UDLG-MESSAGE@ +
    _UDLG-W-M @ UDLG-MESSAGE-BYTES@ DUP _UDLG-ALIGN8 SWAP - 0 FILL
    _UDLG-W-TEXT-END! ;

: UDLG-BUTTON+ ( row col height width roles state a u shortcut-a shortcut-u model -- )
    _UDLG-W-M ! _UDLG-W-SU ! _UDLG-W-SA !
    _UDLG-W-M @ DUP UDLG-BYTES@ + _UDLG-W-P !
    _UDLG-W-P @ UDLG-BUTTON-HEADER-SIZE 0 FILL
    DUP _UDLG-W-SU @ UDLG-BUTTON-BYTES _UDLG-W-P @ UDLG-BUTTON-BYTES-OFFSET + !
    DUP _UDLG-W-P @ UDLG-BUTTON-LABEL-BYTES-OFFSET + !
    _UDLG-W-SU @ _UDLG-W-P @ UDLG-BUTTON-SHORTCUT-BYTES-OFFSET + !
    DUP >R _UDLG-W-P @ UDLG-BUTTON-HEADER-SIZE + _UDLG-W-TEXT
    _UDLG-W-SA @ _UDLG-W-SU @
        _UDLG-W-P @ UDLG-BUTTON-HEADER-SIZE + R> _UDLG-ALIGN8 + _UDLG-W-TEXT
    _UDLG-W-P @ UDLG-BUTTON-STATE-OFFSET + !
    _UDLG-W-P @ UDLG-BUTTON-ROLES-OFFSET + !
    _UDLG-W-P @ UDLG-BUTTON-SLOT-OFFSET + _UDLG-SLOT-STORE
    _UDLG-W-P @ UDLG-BUTTON-NEXT _UDLG-W-M @ -
        _UDLG-W-M @ UDLG-BYTES-OFFSET + !
    1 _UDLG-W-M @ UDLG-BUTTON-COUNT-OFFSET + +! ;

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _udlg-guard
' UDLG-VALIDATE CONSTANT _udlg-validate-xt
: UDLG-VALIDATE _udlg-validate-xt _udlg-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _UDLG-OWNED-END
_UDLG-OWNED-END _UDLG-OWNED-LIMIT !
