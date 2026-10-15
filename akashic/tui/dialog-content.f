\ =====================================================================
\ dialog-content.f -- Checked canonical UDLG to DLG1 and BTN1 content
\ =====================================================================
\ A dialog's title stays separate CONTROL data, its label, and DLG1 is the
\ 56-byte header and the message.  A button's label is its CONTROL label
\ too, and BTN1 is the eight bytes of its roles.  This encoder allocates
\ nothing, copies no native padding, and accepts byte-aligned
\ destinations.
PROVIDED akashic-tui-dialog-content
REQUIRE dialog-model.f

0 CONSTANT UDLGC-S-OK
1 CONSTANT UDLGC-S-CAPACITY
2 CONSTANT UDLGC-S-INVALID
56 CONSTANT UDLGC-DIALOG-HEADER-SIZE
8 CONSTANT UDLGC-BUTTON-SIZE
0x31474C44 CONSTANT UDLGC-DIALOG-TAG
0x314E5442 CONSTANT UDLGC-BUTTON-TAG

CREATE _UDLGC-OWNED-START
VARIABLE _UDLGC-OWNED-LIMIT
0 _UDLGC-OWNED-LIMIT !

: UDLGC-STORAGE-DISJOINT? ( address bytes -- flag )
    2DUP UDLG-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    _UDLGC-OWNED-LIMIT @ DUP _UDLGC-OWNED-START U< IF DROP 2DROP 0 EXIT THEN
    _UDLGC-OWNED-START - _UDLGC-OWNED-START SWAP MSPAN-OVERLAP? 0= ;

VARIABLE _UDLGC-M
VARIABLE _UDLGC-DST
VARIABLE _UDLGC-CAP
VARIABLE _UDLGC-NEED

\ UDLGC-DIALOG-BYTES ( model bytes -- wire-bytes status )
\   The DLG1 bytes of a valid model: the header and its message.
: UDLGC-DIALOG-BYTES ( model bytes -- wire-bytes status )
    2DUP UDLGC-STORAGE-DISJOINT? 0= IF 2DROP 0 UDLGC-S-INVALID EXIT THEN
    2DUP UDLG-VALIDATE UDLG-S-OK <> IF 2DROP 0 UDLGC-S-INVALID EXIT THEN
    DROP UDLG-MESSAGE-BYTES@ UDLGC-DIALOG-HEADER-SIZE + UDLGC-S-OK ;

: _UDLGC-LE! ( value address bytes -- )
    0 ?DO OVER 255 AND OVER I + C! SWAP 8 RSHIFT SWAP LOOP 2DROP ;
: _UDLGC-U16! ( value offset -- ) _UDLGC-DST @ + 2 _UDLGC-LE! ;
: _UDLGC-U32! ( value offset -- ) _UDLGC-DST @ + 4 _UDLGC-LE! ;
: _UDLGC-U64! ( value offset -- ) _UDLGC-DST @ + 8 _UDLGC-LE! ;

\ A slot goes out as x, y, width and height: column, row, width, height.
: _UDLGC-SLOT! ( row col height width offset -- )
    >R R@ 8 + _UDLGC-U32! R@ 12 + _UDLGC-U32!
    R@ _UDLGC-U32! R> 4 + _UDLGC-U32! ;

\ UDLGC-DIALOG-PACK ( model bytes output-address capacity -- used status )
\   Write a valid model's DLG1 content.  The output lies apart from the
\   model and from this module's scratch.
: UDLGC-DIALOG-PACK ( model bytes output-address capacity -- used status )
    2DUP UDLGC-STORAGE-DISJOINT? 0= IF 2DROP 2DROP 0 UDLGC-S-INVALID EXIT THEN
    OVER 0= IF 2DROP 2DROP 0 UDLGC-S-INVALID EXIT THEN
    3 PICK 3 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        2DROP 2DROP 0 UDLGC-S-INVALID EXIT
    THEN
    _UDLGC-CAP ! _UDLGC-DST ! OVER _UDLGC-M !
    UDLGC-DIALOG-BYTES DUP IF EXIT THEN DROP
    DUP _UDLGC-CAP @ U> IF DROP 0 UDLGC-S-CAPACITY EXIT THEN
    _UDLGC-NEED !
    \ All fallible work precedes the first destination write.
    _UDLGC-DST @ UDLGC-DIALOG-HEADER-SIZE 0 FILL
    UDLGC-DIALOG-TAG 0 _UDLGC-U32! 1 4 _UDLGC-U16!
    _UDLGC-M @ UDLG-FLAGS@ 6 _UDLGC-U16!
    _UDLGC-M @ UDLG-REVISION@ 8 _UDLGC-U64!
    _UDLGC-M @ UDLG-SEVERITY@ 16 _UDLGC-U32!
    _UDLGC-M @ UDLG-MESSAGE-BYTES@ 20 _UDLGC-U32!
    _UDLGC-M @ UDLG-TITLE-SLOT@ 24 _UDLGC-SLOT!
    _UDLGC-M @ UDLG-MESSAGE-SLOT@ 40 _UDLGC-SLOT!
    _UDLGC-M @ UDLG-MESSAGE@ _UDLGC-DST @ UDLGC-DIALOG-HEADER-SIZE + SWAP MOVE
    _UDLGC-NEED @ UDLGC-S-OK ;

\ UDLGC-BUTTON-PACK ( button output-address capacity -- used status )
\   Write the BTN1 content of a button record of a valid model.
: UDLGC-BUTTON-PACK ( button output-address capacity -- used status )
    2DUP UDLGC-STORAGE-DISJOINT? 0= IF 2DROP DROP 0 UDLGC-S-INVALID EXIT THEN
    OVER 0= IF 2DROP DROP 0 UDLGC-S-INVALID EXIT THEN
    2 PICK UDLG-BUTTON-HEADER-SIZE 3 PICK 3 PICK MSPAN-OVERLAP? IF
        2DROP DROP 0 UDLGC-S-INVALID EXIT
    THEN
    UDLGC-BUTTON-SIZE U< IF 2DROP 0 UDLGC-S-CAPACITY EXIT THEN
    _UDLGC-DST ! UDLG-BUTTON-ROLES@
    DUP 7 INVERT AND
    OVER UDLG-B-DEFAULT UDLG-B-DESTRUCTIVE OR AND
        UDLG-B-DEFAULT UDLG-B-DESTRUCTIVE OR = OR IF
        DROP 0 UDLGC-S-INVALID EXIT
    THEN
    UDLGC-BUTTON-TAG 0 _UDLGC-U32! 1 4 _UDLGC-U16! 6 _UDLGC-U16!
    UDLGC-BUTTON-SIZE UDLGC-S-OK ;

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _udlgc-guard
' UDLGC-DIALOG-BYTES CONSTANT _udlgc-bytes-xt
' UDLGC-DIALOG-PACK CONSTANT _udlgc-pack-xt
' UDLGC-BUTTON-PACK CONSTANT _udlgc-button-xt
: UDLGC-DIALOG-BYTES _udlgc-bytes-xt _udlgc-guard WITH-GUARD ;
: UDLGC-DIALOG-PACK _udlgc-pack-xt _udlgc-guard WITH-GUARD ;
: UDLGC-BUTTON-PACK _udlgc-button-xt _udlgc-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _UDLGC-OWNED-END
_UDLGC-OWNED-END _UDLGC-OWNED-LIMIT !
