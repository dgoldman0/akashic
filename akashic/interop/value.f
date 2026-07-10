\ =====================================================================
\  value.f - Owned, bounded values for interoperability protocols
\ =====================================================================

PROVIDED akashic-interop-value

REQUIRE ../utils/string.f

0 CONSTANT CV-T-NULL
1 CONSTANT CV-T-BOOL
2 CONSTANT CV-T-INT
3 CONSTANT CV-T-F32
4 CONSTANT CV-T-STRING
5 CONSTANT CV-T-BYTES
6 CONSTANT CV-T-LIST
7 CONSTANT CV-T-MAP
8 CONSTANT CV-T-RESOURCE

1 CONSTANT CV-F-OWNED

1 CONSTANT CV-E-NOMEM
2 CONSTANT CV-E-TYPE
3 CONSTANT CV-E-RANGE

 0 CONSTANT _CV-TYPE
 8 CONSTANT _CV-FLAGS
16 CONSTANT _CV-DATA
24 CONSTANT _CV-LEN
32 CONSTANT _CV-AUX
40 CONSTANT CV-SIZE

: CV.TYPE   ( value -- a ) _CV-TYPE + ;
: CV.FLAGS  ( value -- a ) _CV-FLAGS + ;
: CV.DATA   ( value -- a ) _CV-DATA + ;
: CV.LEN    ( value -- a ) _CV-LEN + ;
: CV.AUX    ( value -- a ) _CV-AUX + ;

: CV-TYPE@  ( value -- type ) CV.TYPE @ ;
: CV-LEN@   ( value -- n )    CV.LEN @ ;
: CV-DATA@  ( value -- x )    CV.DATA @ ;

: CV-INIT  ( value -- )
    CV-SIZE 0 FILL ;

80 CONSTANT CV-MAP-ENTRY-SIZE
: CV-MAP-KEY  ( entry -- key-value ) ;
: CV-MAP-VALUE  ( entry -- value )  CV-SIZE + ;

: CV-FREE  ( value -- )
    DUP 0= IF DROP EXIT THEN
    DUP CV-TYPE@
    CASE
        CV-T-LIST OF
            DUP CV.DATA @
            OVER CV.LEN @ 0 ?DO
                DUP I CV-SIZE * + RECURSE
            LOOP
            FREE
        ENDOF
        CV-T-MAP OF
            DUP CV.DATA @
            OVER CV.LEN @ 0 ?DO
                DUP I CV-MAP-ENTRY-SIZE * +
                DUP CV-MAP-KEY RECURSE
                CV-MAP-VALUE RECURSE
            LOOP
            FREE
        ENDOF
        CV-T-STRING OF
            DUP CV.FLAGS @ CV-F-OWNED AND IF
                DUP CV.DATA @ ?DUP IF FREE THEN
            THEN
        ENDOF
        CV-T-BYTES OF
            DUP CV.FLAGS @ CV-F-OWNED AND IF
                DUP CV.DATA @ ?DUP IF FREE THEN
            THEN
        ENDOF
        CV-T-RESOURCE OF
            DUP CV.FLAGS @ CV-F-OWNED AND IF
                DUP CV.DATA @ ?DUP IF FREE THEN
            THEN
        ENDOF
    ENDCASE
    CV-INIT ;

: CV-NULL!  ( value -- )
    DUP CV-FREE CV-T-NULL SWAP CV.TYPE ! ;

: CV-BOOL!  ( flag value -- )
    DUP CV-FREE >R
    CV-T-BOOL R@ CV.TYPE !
    0<> R> CV.DATA ! ;

: CV-INT!  ( n value -- )
    DUP CV-FREE >R
    CV-T-INT R@ CV.TYPE !
    R> CV.DATA ! ;

: CV-F32!  ( bits value -- )
    DUP CV-FREE >R
    CV-T-F32 R@ CV.TYPE !
    R> CV.DATA ! ;

VARIABLE _CVS-A
VARIABLE _CVS-U
VARIABLE _CVS-V
VARIABLE _CVS-T
VARIABLE _CVS-P

: _CV-BLOB!  ( addr len type value -- ior )
    _CVS-V ! _CVS-T ! _CVS-U ! _CVS-A !
    _CVS-V @ CV-FREE
    _CVS-U @ 0= IF
        _CVS-T @ _CVS-V @ CV.TYPE !
        0
        EXIT
    THEN
    _CVS-U @ ALLOCATE
    DUP IF SWAP DROP EXIT THEN
    DROP DUP _CVS-P !
    _CVS-A @ SWAP _CVS-U @ CMOVE
    _CVS-T @ _CVS-V @ CV.TYPE !
    CV-F-OWNED _CVS-V @ CV.FLAGS !
    _CVS-P @ _CVS-V @ CV.DATA !
    _CVS-U @ _CVS-V @ CV.LEN !
    0 ;

: CV-STRING!  ( addr len value -- ior )
    CV-T-STRING SWAP _CV-BLOB! ;

: CV-BYTES!  ( addr len value -- ior )
    CV-T-BYTES SWAP _CV-BLOB! ;

: CV-RESOURCE!  ( addr len value -- ior )
    CV-T-RESOURCE SWAP _CV-BLOB! ;

VARIABLE _CVC-N
VARIABLE _CVC-V
VARIABLE _CVC-P

: _CV-CONTAINER!  ( count type elem-size value -- ior )
    _CVC-V ! >R SWAP _CVC-N !       ( type ; R: elem-size )
    _CVC-V @ CV-FREE
    _CVC-N @ 0< IF R> DROP DROP CV-E-RANGE EXIT THEN
    DUP _CVC-V @ CV.TYPE !
    R> _CVC-V @ CV.AUX !
    _CVC-N @ _CVC-V @ CV.LEN !
    _CVC-N @ 0= IF DROP 0 EXIT THEN
    _CVC-N @ _CVC-V @ CV.AUX @ * ALLOCATE
    DUP IF SWAP DROP DROP EXIT THEN
    DROP DUP _CVC-P !
    _CVC-N @ _CVC-V @ CV.AUX @ * 0 FILL
    _CVC-P @ _CVC-V @ CV.DATA !
    CV-F-OWNED _CVC-V @ CV.FLAGS !
    DROP 0 ;

: CV-LIST!  ( count value -- ior )
    CV-T-LIST CV-SIZE ROT _CV-CONTAINER! ;

: CV-MAP!  ( count value -- ior )
    CV-T-MAP CV-MAP-ENTRY-SIZE ROT _CV-CONTAINER! ;

VARIABLE _CVN-I
VARIABLE _CVN-V

: CV-LIST-NTH  ( index value -- child | 0 )
    _CVN-V ! _CVN-I !
    _CVN-V @ CV-TYPE@ CV-T-LIST <> IF 0 EXIT THEN
    _CVN-I @ 0< _CVN-I @ _CVN-V @ CV-LEN@ >= OR IF 0 EXIT THEN
    _CVN-V @ CV-DATA@ _CVN-I @ CV-SIZE * + ;

: CV-MAP-NTH  ( index value -- entry | 0 )
    _CVN-V ! _CVN-I !
    _CVN-V @ CV-TYPE@ CV-T-MAP <> IF 0 EXIT THEN
    _CVN-I @ 0< _CVN-I @ _CVN-V @ CV-LEN@ >= OR IF 0 EXIT THEN
    _CVN-V @ CV-DATA@ _CVN-I @ CV-MAP-ENTRY-SIZE * + ;

VARIABLE _CVM-KA
VARIABLE _CVM-KU
VARIABLE _CVM-V

: CV-MAP-FIND  ( key-a key-u map -- value | 0 )
    _CVM-V ! _CVM-KU ! _CVM-KA !
    _CVM-V @ CV-TYPE@ CV-T-MAP <> IF 0 EXIT THEN
    _CVM-V @ CV-LEN@ 0 ?DO
        I _CVM-V @ CV-MAP-NTH DUP CV-MAP-KEY
        DUP CV-TYPE@ CV-T-STRING = IF
            DUP CV-DATA@ SWAP CV-LEN@
            _CVM-KA @ _CVM-KU @ STR-STR= IF
                CV-MAP-VALUE UNLOOP EXIT
            THEN
        ELSE DROP THEN
        DROP
    LOOP
    0 ;

\ Deep-copy an owned interoperability value.  Container children are
\ cloned recursively so callers never retain pointers into event buffers.
: CV-COPY  ( source destination -- ior )
    2DUP = IF 2DROP 0 EXIT THEN
    DUP CV-FREE
    OVER CV-TYPE@ CASE
        CV-T-NULL OF
            NIP CV-NULL! 0
        ENDOF
        CV-T-BOOL OF
            >R CV-DATA@ R> CV-BOOL! 0
        ENDOF
        CV-T-INT OF
            >R CV-DATA@ R> CV-INT! 0
        ENDOF
        CV-T-F32 OF
            >R CV-DATA@ R> CV-F32! 0
        ENDOF
        CV-T-STRING OF
            >R DUP CV-DATA@ SWAP CV-LEN@ R> CV-STRING!
        ENDOF
        CV-T-BYTES OF
            >R DUP CV-DATA@ SWAP CV-LEN@ R> CV-BYTES!
        ENDOF
        CV-T-RESOURCE OF
            >R DUP CV-DATA@ SWAP CV-LEN@ R> CV-RESOURCE!
        ENDOF
        CV-T-LIST OF
            >R
            DUP CV-LEN@ R@ CV-LIST! ?DUP IF
                NIP R> DROP EXIT
            THEN
            DUP CV-LEN@ 0 ?DO
                I OVER CV-LIST-NTH
                I R@ CV-LIST-NTH
                RECURSE ?DUP IF
                    >R DROP R> R> DROP UNLOOP EXIT
                THEN
            LOOP
            DROP R> DROP 0
        ENDOF
        CV-T-MAP OF
            >R
            DUP CV-LEN@ R@ CV-MAP! ?DUP IF
                NIP R> DROP EXIT
            THEN
            DUP CV-LEN@ 0 ?DO
                I OVER CV-MAP-NTH
                I R@ CV-MAP-NTH
                2 PICK CV-MAP-KEY
                OVER CV-MAP-KEY
                RECURSE ?DUP IF
                    >R 2DROP DROP R> R> DROP UNLOOP EXIT
                THEN
                OVER CV-MAP-VALUE
                OVER CV-MAP-VALUE
                RECURSE ?DUP IF
                    >R 2DROP DROP R> R> DROP UNLOOP EXIT
                THEN
                2DROP
            LOOP
            DROP R> DROP 0
        ENDOF
        2DROP CV-E-TYPE
    ENDCASE ;
