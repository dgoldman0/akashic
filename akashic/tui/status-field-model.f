\ =====================================================================
\ status-field-model.f -- Owned, renderer-neutral one-row status value
\ =====================================================================
\ ABI 1: nine u64 cells followed by label bytes, value bytes, zero pad8.
\ The caller owns the entire pointer-free value.  No terminal protocol,
\ focus, enabled state, styling palette, or action is part of this model.

PROVIDED akashic-tui-status-model

REQUIRE ../text/utf8.f
REQUIRE ../utils/memory-span.f

0 CONSTANT USF-S-OK
1 CONSTANT USF-S-UNSUPPORTED
2 CONSTANT USF-S-CAPACITY
3 CONSTANT USF-S-INVALID

1 CONSTANT USF-ABI
1 CONSTANT USF-F-VISIBLE
2 CONSTANT USF-F-EMPHASIZED

 0 CONSTANT USF-BYTES-OFFSET
 8 CONSTANT USF-ABI-OFFSET
16 CONSTANT USF-KEY-OFFSET
24 CONSTANT USF-WIDTH-OFFSET
32 CONSTANT USF-LABEL-COLS-OFFSET
40 CONSTANT USF-SEVERITY-OFFSET
48 CONSTANT USF-FLAGS-OFFSET
56 CONSTANT USF-LABEL-BYTES-OFFSET
64 CONSTANT USF-VALUE-BYTES-OFFSET
72 CONSTANT USF-HEADER-SIZE

CREATE _USF-OWNED-START
VARIABLE _USF-OWNED-LIMIT
0 _USF-OWNED-LIMIT !

: USF-BYTES@       ( model -- u ) USF-BYTES-OFFSET + @ ;
: USF-ABI@         ( model -- u ) USF-ABI-OFFSET + @ ;
: USF-KEY@         ( model -- u ) USF-KEY-OFFSET + @ ;
: USF-WIDTH@       ( model -- u ) USF-WIDTH-OFFSET + @ ;
: USF-LABEL-COLS@  ( model -- u ) USF-LABEL-COLS-OFFSET + @ ;
: USF-SEVERITY@    ( model -- u ) USF-SEVERITY-OFFSET + @ ;
: USF-FLAGS@       ( model -- u ) USF-FLAGS-OFFSET + @ ;
: USF-LABEL-BYTES@ ( model -- u ) USF-LABEL-BYTES-OFFSET + @ ;
: USF-VALUE-BYTES@ ( model -- u ) USF-VALUE-BYTES-OFFSET + @ ;
: USF-LABEL@ ( model -- address bytes )
    DUP USF-HEADER-SIZE + SWAP USF-LABEL-BYTES@ ;
: USF-VALUE@ ( model -- address bytes )
    DUP USF-HEADER-SIZE + OVER USF-LABEL-BYTES@ +
    SWAP USF-VALUE-BYTES@ ;

\ Empty text accepts any address and reads no bytes.  Nonempty spans must
\ be nonzero, nonwrapping, and have a nonnegative signed length.
: _USF-SPAN? ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: USF-STORAGE-DISJOINT? ( address bytes -- flag )
    2DUP _USF-SPAN? 0= IF 2DROP 0 EXIT THEN
    _USF-OWNED-LIMIT @ DUP _USF-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _USF-OWNED-START - _USF-OWNED-START SWAP MSPAN-OVERLAP? 0= ;

-1 1 RSHIFT USF-HEADER-SIZE - 7 - CONSTANT _USF-MAX-TEXT-BYTES

: USF-BYTES ( label-bytes value-bytes -- bytes|0 )
    OVER 0< OVER 0< OR IF 2DROP 0 EXIT THEN
    2DUP + DUP 2 PICK U< IF DROP 2DROP 0 EXIT THEN
    NIP NIP DUP _USF-MAX-TEXT-BYTES U> IF DROP 0 EXIT THEN
    USF-HEADER-SIZE + 7 + -8 AND ;

: _USF-CONTROL? ( cp -- flag )
    DUP 32 U< IF DROP -1 EXIT THEN
    DUP 127 160 WITHIN IF DROP -1 EXIT THEN
    DUP 0x2028 = SWAP 0x2029 = OR ;

: USF-TEXT? ( address bytes -- flag )
    2DUP _USF-SPAN? 0= IF 2DROP 0 EXIT THEN
    2DUP UTF8-VALID? 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP WHILE
        UTF8-DECODE ROT _USF-CONTROL? IF 2DROP 0 EXIT THEN
    REPEAT 2DROP -1 ;

: _USF-CP-BYTES ( cp -- bytes )
    DUP 0x80 U< IF DROP 1 EXIT THEN
    DUP 0x800 U< IF DROP 2 EXIT THEN
    0x10000 U< IF 3 ELSE 4 THEN ;

\ This is GR-DISPLAY-CP's Cc/Zl/Zp policy used by ordinary DRW-TEXT.
\ The model deliberately has no grapheme-table dependency: these are the
\ complete scalar ranges of those categories.  Other scalars, including
\ directional formatting, retain their ordinary text semantics.
: _USF-DISPLAY-CP ( cp -- display-cp )
    DUP _USF-CONTROL? IF DROP UTF8-REPLACEMENT THEN ;

\ Display construction also preserves maximal-subpart invalid decoding.
\ UTF8-SAFE-COPY has a narrower legacy policy and is not used here.
: USF-DISPLAY-BYTES ( address bytes -- bytes status )
    2DUP USF-STORAGE-DISJOINT? 0= IF 2DROP 0 USF-S-INVALID EXIT THEN
    0 -ROT
    BEGIN DUP WHILE
        UTF8-DECODE 2SWAP _USF-DISPLAY-CP _USF-CP-BYTES +
        DUP _USF-MAX-TEXT-BYTES U> IF 2DROP DROP 0 USF-S-INVALID EXIT THEN
        -ROT
    REPEAT 2DROP USF-S-OK ;

: _USF-DISPLAY-COPY ( address bytes destination -- )
    >R BEGIN DUP WHILE
        UTF8-DECODE ROT _USF-DISPLAY-CP R> UTF8-ENCODE >R
    REPEAT 2DROP R> DROP ;

: _USF-WIDTH? ( width -- flag )
    DUP 0> SWAP 0x100000000 U< AND ;

VARIABLE _USF-V-A
VARIABLE _USF-V-U
VARIABLE _USF-V-END

: USF-VALIDATE ( model bytes -- status )
    2DUP USF-STORAGE-DISJOINT? 0= IF 2DROP USF-S-INVALID EXIT THEN
    OVER 0= OVER USF-HEADER-SIZE U< OR IF 2DROP USF-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP USF-S-INVALID EXIT THEN
    _USF-V-U ! _USF-V-A !
    _USF-V-A @ USF-BYTES@ _USF-V-U @ <> IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-ABI@ USF-ABI <> IF USF-S-UNSUPPORTED EXIT THEN
    _USF-V-A @ USF-KEY@ 0= IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-WIDTH@ _USF-WIDTH? 0= IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-LABEL-COLS@ _USF-V-A @ USF-WIDTH@ U> IF
        USF-S-INVALID EXIT
    THEN
    _USF-V-A @ USF-SEVERITY@ 4 U> IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-FLAGS@ 3 INVERT AND IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-LABEL-BYTES@ _USF-V-A @ USF-VALUE-BYTES@
        USF-BYTES DUP 0= SWAP _USF-V-U @ <> OR IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-LABEL-BYTES@ IF
        _USF-V-A @ USF-LABEL-COLS@ 0= IF USF-S-INVALID EXIT THEN
    THEN
    _USF-V-A @ USF-VALUE-BYTES@ IF
        _USF-V-A @ USF-LABEL-COLS@ _USF-V-A @ USF-WIDTH@ = IF
            USF-S-INVALID EXIT
        THEN
    THEN
    _USF-V-A @ USF-LABEL@ USF-TEXT? 0= IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-VALUE@ USF-TEXT? 0= IF USF-S-INVALID EXIT THEN
    _USF-V-A @ USF-VALUE@ + _USF-V-END !
    _USF-V-A @ _USF-V-U @ + _USF-V-END @ ?DO
        I C@ IF USF-S-INVALID UNLOOP EXIT THEN
    LOOP
    USF-S-OK ;

VARIABLE _USF-I-KEY
VARIABLE _USF-I-WIDTH
VARIABLE _USF-I-SPLIT
VARIABLE _USF-I-SEVERITY
VARIABLE _USF-I-FLAGS
VARIABLE _USF-I-LA
VARIABLE _USF-I-LU
VARIABLE _USF-I-VA
VARIABLE _USF-I-VU
VARIABLE _USF-I-DST
VARIABLE _USF-I-CAP
VARIABLE _USF-I-NEED
VARIABLE _USF-I-DISPLAY
VARIABLE _USF-I-OUT-LU
VARIABLE _USF-I-OUT-VU

: _USF-INIT-PREFLIGHT?
    ( key width split severity flags la lu va vu dst cap -- ... flag )
    1 PICK 1 PICK USF-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    5 PICK 5 PICK USF-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    3 PICK 3 PICK USF-STORAGE-DISJOINT? ;

: _USF-INIT-IMPL
    ( key width split severity flags label-a label-u value-a value-u dst cap -- used status )
    _USF-INIT-PREFLIGHT? 0= IF
        2DROP 2DROP 2DROP 2DROP 2DROP DROP 0 USF-S-INVALID EXIT
    THEN
    _USF-I-CAP ! _USF-I-DST ! _USF-I-VU ! _USF-I-VA !
    _USF-I-LU ! _USF-I-LA ! _USF-I-FLAGS ! _USF-I-SEVERITY !
    _USF-I-SPLIT ! _USF-I-WIDTH ! _USF-I-KEY !
    _USF-I-DST @ DUP 0= SWAP 7 AND OR IF 0 USF-S-INVALID EXIT THEN
    _USF-I-KEY @ 0= IF 0 USF-S-INVALID EXIT THEN
    _USF-I-WIDTH @ _USF-WIDTH? 0= IF 0 USF-S-INVALID EXIT THEN
    _USF-I-SPLIT @ _USF-I-WIDTH @ U> IF 0 USF-S-INVALID EXIT THEN
    _USF-I-SEVERITY @ 4 U> IF 0 USF-S-INVALID EXIT THEN
    _USF-I-FLAGS @ 3 INVERT AND IF 0 USF-S-INVALID EXIT THEN
    _USF-I-LU @ IF
        _USF-I-SPLIT @ 0= IF 0 USF-S-INVALID EXIT THEN
    THEN
    _USF-I-VU @ IF
        _USF-I-SPLIT @ _USF-I-WIDTH @ = IF 0 USF-S-INVALID EXIT THEN
    THEN
    _USF-I-DISPLAY @ IF
        _USF-I-LA @ _USF-I-LU @ USF-DISPLAY-BYTES
            DUP IF EXIT THEN DROP _USF-I-OUT-LU !
        _USF-I-VA @ _USF-I-VU @ USF-DISPLAY-BYTES
            DUP IF EXIT THEN DROP _USF-I-OUT-VU !
    ELSE
        _USF-I-LA @ _USF-I-LU @ USF-TEXT? 0= IF 0 USF-S-INVALID EXIT THEN
        _USF-I-VA @ _USF-I-VU @ USF-TEXT? 0= IF 0 USF-S-INVALID EXIT THEN
        _USF-I-LU @ _USF-I-OUT-LU ! _USF-I-VU @ _USF-I-OUT-VU !
    THEN
    _USF-I-OUT-LU @ _USF-I-OUT-VU @ USF-BYTES DUP 0= IF
        DROP 0 USF-S-INVALID EXIT
    THEN _USF-I-NEED !
    _USF-I-DST @ _USF-I-CAP @ _USF-I-LA @ _USF-I-LU @
        MSPAN-OVERLAP? IF 0 USF-S-INVALID EXIT THEN
    _USF-I-DST @ _USF-I-CAP @ _USF-I-VA @ _USF-I-VU @
        MSPAN-OVERLAP? IF 0 USF-S-INVALID EXIT THEN
    _USF-I-CAP @ _USF-I-NEED @ U< IF 0 USF-S-CAPACITY EXIT THEN
    \ Every refusal precedes the first destination write.
    _USF-I-DST @ _USF-I-NEED @ 0 FILL
    _USF-I-NEED @ _USF-I-DST @ USF-BYTES-OFFSET + !
    USF-ABI _USF-I-DST @ USF-ABI-OFFSET + !
    _USF-I-KEY @ _USF-I-DST @ USF-KEY-OFFSET + !
    _USF-I-WIDTH @ _USF-I-DST @ USF-WIDTH-OFFSET + !
    _USF-I-SPLIT @ _USF-I-DST @ USF-LABEL-COLS-OFFSET + !
    _USF-I-SEVERITY @ _USF-I-DST @ USF-SEVERITY-OFFSET + !
    _USF-I-FLAGS @ _USF-I-DST @ USF-FLAGS-OFFSET + !
    _USF-I-OUT-LU @ _USF-I-DST @ USF-LABEL-BYTES-OFFSET + !
    _USF-I-OUT-VU @ _USF-I-DST @ USF-VALUE-BYTES-OFFSET + !
    _USF-I-DISPLAY @ IF
        _USF-I-LA @ _USF-I-LU @ _USF-I-DST @ USF-HEADER-SIZE +
            _USF-DISPLAY-COPY
        _USF-I-VA @ _USF-I-VU @
            _USF-I-DST @ USF-HEADER-SIZE + _USF-I-OUT-LU @ +
            _USF-DISPLAY-COPY
    ELSE
        _USF-I-LA @ _USF-I-DST @ USF-HEADER-SIZE + _USF-I-LU @ MOVE
        _USF-I-VA @ _USF-I-DST @ USF-HEADER-SIZE + _USF-I-LU @ +
            _USF-I-VU @ MOVE
    THEN
    _USF-I-NEED @ USF-S-OK ;

: _USF-INIT-MODE
    ( key width split severity flags la lu va vu dst cap display? -- used status )
    >R _USF-INIT-PREFLIGHT? 0= IF
        R> DROP 2DROP 2DROP 2DROP 2DROP 2DROP DROP 0 USF-S-INVALID EXIT
    THEN R> _USF-I-DISPLAY ! _USF-INIT-IMPL ;

: USF-INIT
    ( key width split severity flags la lu va vu dst cap -- used status )
    0 _USF-INIT-MODE ;

: USF-INIT-DISPLAY
    ( key width split severity flags la lu va vu dst cap -- used status )
    -1 _USF-INIT-MODE ;

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _usf-guard
' USF-INIT CONSTANT _usf-init-xt
' USF-INIT-DISPLAY CONSTANT _usf-init-display-xt
' USF-VALIDATE CONSTANT _usf-validate-xt
: USF-INIT _usf-init-xt _usf-guard WITH-GUARD ;
: USF-INIT-DISPLAY _usf-init-display-xt _usf-guard WITH-GUARD ;
: USF-VALIDATE _usf-validate-xt _usf-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _USF-OWNED-END
_USF-OWNED-END _USF-OWNED-LIMIT !
