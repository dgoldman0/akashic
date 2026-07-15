\ =====================================================================
\  schema.f - Bounded schemas for interoperable values
\ =====================================================================

PROVIDED akashic-interop-schema

REQUIRE value.f
REQUIRE ../text/utf8.f
REQUIRE ../concurrency/guard.f

1 CONSTANT CS-F-MIN
2 CONSTANT CS-F-MAX
4 CONSTANT CS-F-MAX-LEN

1 CONSTANT CS-E-TYPE
2 CONSTANT CS-E-MIN
3 CONSTANT CS-E-MAX
4 CONSTANT CS-E-LENGTH
5 CONSTANT CS-E-MISSING
6 CONSTANT CS-E-UNKNOWN
7 CONSTANT CS-E-DUPLICATE
8 CONSTANT CS-E-DEPTH
9 CONSTANT CS-E-SCHEMA
10 CONSTANT CS-E-CAPACITY

16 CONSTANT CS-MAX-DEPTH
CV-MAX-CONTAINER-LEN CONSTANT CS-MAX-CONTAINER-LEN
256 CONSTANT CS-MAX-FIELDS
256 CONSTANT CS-MAX-MAP-ENTRIES
65536 CONSTANT CS-MAX-NODES
0x1FF CONSTANT CS-VALID-TYPE-MASK

 0 CONSTANT _CS-TYPE-MASK
 8 CONSTANT _CS-FLAGS
16 CONSTANT _CS-MIN
24 CONSTANT _CS-MAX
32 CONSTANT _CS-MAX-LEN
40 CONSTANT _CS-ITEM
48 CONSTANT _CS-FIELDS
56 CONSTANT _CS-FIELD-N
64 CONSTANT CS-SIZE

: CS.TYPE-MASK  ( schema -- a ) _CS-TYPE-MASK + ;
: CS.FLAGS      ( schema -- a ) _CS-FLAGS + ;
: CS.MIN        ( schema -- a ) _CS-MIN + ;
: CS.MAX        ( schema -- a ) _CS-MAX + ;
: CS.MAX-LEN    ( schema -- a ) _CS-MAX-LEN + ;
: CS.ITEM       ( schema -- a ) _CS-ITEM + ;
: CS.FIELDS     ( schema -- a ) _CS-FIELDS + ;
: CS.FIELD-N    ( schema -- a ) _CS-FIELD-N + ;

: CS-INIT  ( schema -- ) CS-SIZE 0 FILL ;

: CS-TYPE-BIT  ( type -- mask ) 1 SWAP LSHIFT ;

: CS-ALLOW!  ( type schema -- )
    SWAP CS-TYPE-BIT SWAP CS.TYPE-MASK ! ;

: CS-ALLOW-MASK!  ( mask schema -- )
    CS.TYPE-MASK ! ;

: CS-MIN!  ( n schema -- )
    DUP CS.FLAGS DUP @ CS-F-MIN OR SWAP !
    CS.MIN ! ;

: CS-MAX!  ( n schema -- )
    DUP CS.FLAGS DUP @ CS-F-MAX OR SWAP !
    CS.MAX ! ;

: CS-MAX-LEN!  ( n schema -- )
    DUP CS.FLAGS DUP @ CS-F-MAX-LEN OR SWAP !
    CS.MAX-LEN ! ;

VARIABLE _CSV-V
VARIABLE _CSV-S
VARIABLE _CSV-T

: CS-VALIDATE  ( value schema -- ior )
    _CSV-S ! _CSV-V !
    _CSV-V @ 0= _CSV-S @ 0= OR IF CS-E-SCHEMA EXIT THEN
    _CSV-S @ CS.TYPE-MASK @ DUP 0= IF DROP CS-E-SCHEMA EXIT THEN
    CS-VALID-TYPE-MASK INVERT AND IF CS-E-SCHEMA EXIT THEN
    _CSV-S @ CS.FLAGS @
        CS-F-MIN CS-F-MAX OR CS-F-MAX-LEN OR INVERT AND IF
        CS-E-SCHEMA EXIT
    THEN
    _CSV-S @ CS.FLAGS @ CS-F-MIN CS-F-MAX OR AND
        CS-F-MIN CS-F-MAX OR = IF
        _CSV-S @ CS.MIN @ _CSV-S @ CS.MAX @ > IF CS-E-SCHEMA EXIT THEN
    THEN
    _CSV-S @ CS.FLAGS @ CS-F-MAX-LEN AND IF
        _CSV-S @ CS.MAX-LEN @ 0< IF CS-E-SCHEMA EXIT THEN
    THEN
    _CSV-V @ CV-TYPE@ DUP _CSV-T !
    DUP 0< SWAP CV-T-RESOURCE > OR IF CS-E-TYPE EXIT THEN
    _CSV-T @ CS-TYPE-BIT _CSV-S @ CS.TYPE-MASK @ AND 0= IF
        CS-E-TYPE EXIT
    THEN
    _CSV-T @ CV-T-INT = IF
        _CSV-S @ CS.FLAGS @ CS-F-MIN AND IF
            _CSV-V @ CV-DATA@ _CSV-S @ CS.MIN @ < IF CS-E-MIN EXIT THEN
        THEN
        _CSV-S @ CS.FLAGS @ CS-F-MAX AND IF
            _CSV-V @ CV-DATA@ _CSV-S @ CS.MAX @ > IF CS-E-MAX EXIT THEN
        THEN
    THEN
    _CSV-T @ DUP CV-T-STRING = SWAP DUP CV-T-BYTES =
    SWAP CV-T-RESOURCE = OR OR
    _CSV-T @ CV-T-LIST = OR _CSV-T @ CV-T-MAP = OR IF
        _CSV-V @ CV-LEN@ DUP 0< IF DROP CS-E-LENGTH EXIT THEN
        DUP 0> IF _CSV-V @ CV-DATA@ 0= IF DROP CS-E-LENGTH EXIT THEN THEN
        DROP
        _CSV-S @ CS.FLAGS @ CS-F-MAX-LEN AND IF
            _CSV-V @ CV-LEN@ _CSV-S @ CS.MAX-LEN @ > IF
                CS-E-LENGTH EXIT
            THEN
        THEN
    THEN
    _CSV-T @ DUP CV-T-STRING = SWAP DUP CV-T-BYTES =
    SWAP CV-T-RESOURCE = OR OR IF
        _CSV-V @ CV-LEN@ CV-MAX-STRING-LEN > IF
            CS-E-LENGTH EXIT
        THEN
    THEN
    _CSV-T @ CV-T-LIST = _CSV-T @ CV-T-MAP = OR IF
        _CSV-V @ CV-LEN@ CS-MAX-CONTAINER-LEN > IF
            CS-E-LENGTH EXIT
        THEN
    THEN
    _CSV-T @ CV-T-LIST = IF
        _CSV-V @ CV.AUX @ CV-SIZE <> IF CS-E-TYPE EXIT THEN
    THEN
    _CSV-T @ CV-T-MAP = IF
        _CSV-V @ CV.AUX @ CV-MAP-ENTRY-SIZE <> IF CS-E-TYPE EXIT THEN
    THEN
    _CSV-T @ DUP CV-T-STRING = SWAP CV-T-RESOURCE = OR IF
        _CSV-V @ CV-DATA@ _CSV-V @ CV-LEN@ UTF8-VALID? 0= IF
            CS-E-TYPE EXIT
        THEN
    THEN
    0 ;

\ Map-field schema descriptor, 4 cells / 32 bytes.
 0 CONSTANT _CSF-KEY-A
 8 CONSTANT _CSF-KEY-U
16 CONSTANT _CSF-SCHEMA
24 CONSTANT _CSF-FLAGS
32 CONSTANT CS-FIELD-SIZE

1 CONSTANT CSF-F-REQUIRED

: CSF.KEY-A   ( field -- a ) _CSF-KEY-A + ;
: CSF.KEY-U   ( field -- a ) _CSF-KEY-U + ;
: CSF.SCHEMA  ( field -- a ) _CSF-SCHEMA + ;
: CSF.FLAGS   ( field -- a ) _CSF-FLAGS + ;

\ Deep validation closes declared maps, validates list items recursively, and
\ rejects duplicate keys.  Per-depth frames keep parent traversal state intact
\ across recursion; the public guard serializes the shared frame arrays.
CREATE _CSDF-V CS-MAX-DEPTH 8 * ALLOT
CREATE _CSDF-S CS-MAX-DEPTH 8 * ALLOT
CREATE _CSDF-I CS-MAX-DEPTH 8 * ALLOT
CREATE _CSDF-ENTRY CS-MAX-DEPTH 8 * ALLOT
CREATE _CSDF-KA CS-MAX-DEPTH 8 * ALLOT
CREATE _CSDF-KU CS-MAX-DEPTH 8 * ALLOT
CREATE _CSDF-FIELD CS-MAX-DEPTH 8 * ALLOT
CREATE _CSDF-MATCHES CS-MAX-DEPTH 8 * ALLOT
VARIABLE _CSD-DEPTH
VARIABLE _CSD-NODES

: _CSD-SLOT  ( base -- address ) _CSD-DEPTH @ 8 * + ;
: _CSD-V@  ( -- value ) _CSDF-V _CSD-SLOT @ ;
: _CSD-S@  ( -- schema ) _CSDF-S _CSD-SLOT @ ;
: _CSD-I@  ( -- n ) _CSDF-I _CSD-SLOT @ ;
: _CSD-ENTRY@  ( -- entry ) _CSDF-ENTRY _CSD-SLOT @ ;
: _CSD-KA@  ( -- addr ) _CSDF-KA _CSD-SLOT @ ;
: _CSD-KU@  ( -- len ) _CSDF-KU _CSD-SLOT @ ;
: _CSD-FIELD@  ( -- field ) _CSDF-FIELD _CSD-SLOT @ ;
: _CSD-MATCHES@  ( -- n ) _CSDF-MATCHES _CSD-SLOT @ ;
: _CSD-V!  ( value -- ) _CSDF-V _CSD-SLOT ! ;
: _CSD-S!  ( schema -- ) _CSDF-S _CSD-SLOT ! ;
: _CSD-I!  ( n -- ) _CSDF-I _CSD-SLOT ! ;
: _CSD-ENTRY!  ( entry -- ) _CSDF-ENTRY _CSD-SLOT ! ;
: _CSD-KA!  ( addr -- ) _CSDF-KA _CSD-SLOT ! ;
: _CSD-KU!  ( len -- ) _CSDF-KU _CSD-SLOT ! ;
: _CSD-FIELD!  ( field -- ) _CSDF-FIELD _CSD-SLOT ! ;
: _CSD-MATCHES!  ( n -- ) _CSDF-MATCHES _CSD-SLOT ! ;

DEFER _CSD-VALUE

CREATE _CSD-ANY-SCHEMA CS-SIZE ALLOT
_CSD-ANY-SCHEMA CS-INIT
CS-VALID-TYPE-MASK _CSD-ANY-SCHEMA CS-ALLOW-MASK!

: _CSD-DUPLICATE-KEY?  ( prior-count -- flag )
    0 ?DO
        I _CSD-V@ CV-MAP-NTH CV-MAP-KEY
        DUP CV-DATA@ SWAP CV-LEN@
        _CSD-KA@ _CSD-KU@ STR-STR= IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

: _CSD-FIND-FIELD  ( -- )
    0 _CSD-FIELD! 0 _CSD-MATCHES!
    _CSD-S@ CS.FIELD-N @ 0 ?DO
        _CSD-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP
        DUP CSF.KEY-A @ SWAP CSF.KEY-U @
        _CSD-KA@ _CSD-KU@ STR-STR= IF
            _CSD-FIELD! _CSD-MATCHES@ 1+ _CSD-MATCHES!
        ELSE
            DROP
        THEN
    LOOP ;

: _CSD-DUPLICATE-FIELD?  ( prior-count -- flag )
    0 ?DO
        _CSD-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP
        CSF.KEY-A @ SWAP CSF.KEY-U @
        _CSD-KA@ _CSD-KU@ STR-STR= IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

: _CSD-VALIDATE-FIELDS  ( -- ior )
    _CSD-S@ CS.FIELD-N @ 0 ?DO
        _CSD-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP _CSD-FIELD!
        DUP CSF.FLAGS @ CSF-F-REQUIRED INVERT AND IF
            DROP CS-E-SCHEMA UNLOOP EXIT
        THEN
        DUP CSF.SCHEMA @ 0= IF DROP CS-E-SCHEMA UNLOOP EXIT THEN
        DUP CSF.KEY-A @ SWAP CSF.KEY-U @ DUP 0< IF
            2DROP CS-E-SCHEMA UNLOOP EXIT
        THEN
        DUP CV-MAX-STRING-LEN > IF
            2DROP CS-E-SCHEMA UNLOOP EXIT
        THEN
        DUP 0> IF OVER 0= IF
            2DROP CS-E-SCHEMA UNLOOP EXIT
        THEN THEN
        2DUP UTF8-VALID? 0= IF 2DROP CS-E-SCHEMA UNLOOP EXIT THEN
        _CSD-KU! _CSD-KA!
        I _CSD-DUPLICATE-FIELD? IF CS-E-SCHEMA UNLOOP EXIT THEN
    LOOP
    0 ;

: _CSD-LIST  ( -- ior )
    _CSD-V@ CV-LEN@ CS-MAX-CONTAINER-LEN > IF CS-E-LENGTH EXIT THEN
    _CSD-V@ CV-LEN@ 0 ?DO
        I _CSD-V@ CV-LIST-NTH DUP 0= IF
            DROP CS-E-TYPE UNLOOP EXIT
        THEN
        _CSD-S@ CS.ITEM @ _CSD-VALUE ?DUP IF UNLOOP EXIT THEN
    LOOP
    0 ;

: _CSD-MAP  ( -- ior )
    _CSD-V@ CV-LEN@ CS-MAX-MAP-ENTRIES > IF CS-E-LENGTH EXIT THEN
    _CSD-S@ CS.FIELD-N @ DUP 0< OVER CS-MAX-FIELDS > OR IF
        DROP CS-E-SCHEMA EXIT
    THEN
    DUP 0> IF _CSD-S@ CS.FIELDS @ 0= IF DROP CS-E-SCHEMA EXIT THEN THEN
    DROP
    _CSD-VALIDATE-FIELDS ?DUP IF EXIT THEN
    0 _CSD-I!
    BEGIN _CSD-I@ _CSD-V@ CV-LEN@ < WHILE
        _CSD-I@ _CSD-V@ CV-MAP-NTH DUP 0= IF
            DROP CS-E-TYPE EXIT
        THEN
        DUP _CSD-ENTRY! CV-MAP-KEY DUP CV-TYPE@ CV-T-STRING <> IF
            DROP CS-E-TYPE EXIT
        THEN
        DUP CV-DATA@ SWAP CV-LEN@ DUP 0< IF 2DROP CS-E-LENGTH EXIT THEN
        DUP CV-MAX-STRING-LEN > IF 2DROP CS-E-LENGTH EXIT THEN
        DUP 0> IF OVER 0= IF 2DROP CS-E-LENGTH EXIT THEN THEN
        2DUP UTF8-VALID? 0= IF 2DROP CS-E-TYPE EXIT THEN
        _CSD-KU! _CSD-KA!
        _CSD-I@ _CSD-DUPLICATE-KEY? IF CS-E-DUPLICATE EXIT THEN
        _CSD-S@ CS.FIELD-N @ IF
            _CSD-FIND-FIELD
            _CSD-MATCHES@ 0= IF CS-E-UNKNOWN EXIT THEN
            _CSD-MATCHES@ 1 > IF CS-E-DUPLICATE EXIT THEN
            _CSD-FIELD@ CSF.FLAGS @ CSF-F-REQUIRED INVERT AND IF
                CS-E-SCHEMA EXIT
            THEN
            _CSD-FIELD@ CSF.SCHEMA @ ?DUP IF
                _CSD-ENTRY@ CV-MAP-VALUE SWAP _CSD-VALUE ?DUP IF EXIT THEN
            THEN
        ELSE
            _CSD-ENTRY@ CV-MAP-VALUE 0 _CSD-VALUE ?DUP IF EXIT THEN
        THEN
        _CSD-I@ 1+ _CSD-I!
    REPEAT
    _CSD-S@ CS.FIELD-N @ 0 ?DO
        _CSD-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP CSF.FLAGS @
        CSF-F-REQUIRED AND IF
            DUP CSF.KEY-A @ SWAP CSF.KEY-U @ _CSD-V@ CV-MAP-FIND
            0= IF CS-E-MISSING UNLOOP EXIT THEN
        ELSE
            DROP
        THEN
    LOOP
    0 ;

: _CSD-VALUE-R  ( value schema -- ior )
    1 _CSD-NODES +!
    _CSD-NODES @ CS-MAX-NODES > IF 2DROP CS-E-CAPACITY EXIT THEN
    1 _CSD-DEPTH +!
    _CSD-DEPTH @ CS-MAX-DEPTH >= IF
        2DROP -1 _CSD-DEPTH +! CS-E-DEPTH EXIT
    THEN
    _CSD-S! _CSD-V!
    _CSD-S@ 0= IF _CSD-ANY-SCHEMA _CSD-S! THEN
    _CSD-V@ _CSD-S@ CS-VALIDATE ?DUP IF
        -1 _CSD-DEPTH +! EXIT
    THEN
    _CSD-V@ CV-TYPE@ CASE
        CV-T-LIST OF _CSD-LIST ENDOF
        CV-T-MAP OF _CSD-MAP ENDOF
        0 SWAP
    ENDCASE
    -1 _CSD-DEPTH +! ;

' _CSD-VALUE-R IS _CSD-VALUE

\ Validate the schema graph independently of a particular value.  Without
\ this pass, an invalid item or optional-field schema could hide behind an
\ empty container and never be checked.
CREATE _CSSV-DUMMY CV-SIZE ALLOT
CREATE _CSSVF-S CS-MAX-DEPTH 8 * ALLOT
CREATE _CSSVF-KA CS-MAX-DEPTH 8 * ALLOT
CREATE _CSSVF-KU CS-MAX-DEPTH 8 * ALLOT
VARIABLE _CSSV-DEPTH
VARIABLE _CSSV-NODES

: _CSSV-SLOT  ( base -- address ) _CSSV-DEPTH @ 8 * + ;
: _CSSV-S@  ( -- schema ) _CSSVF-S _CSSV-SLOT @ ;
: _CSSV-S!  ( schema -- ) _CSSVF-S _CSSV-SLOT ! ;
: _CSSV-KA@  ( -- addr ) _CSSVF-KA _CSSV-SLOT @ ;
: _CSSV-KA!  ( addr -- ) _CSSVF-KA _CSSV-SLOT ! ;
: _CSSV-KU@  ( -- len ) _CSSVF-KU _CSSV-SLOT @ ;
: _CSSV-KU!  ( len -- ) _CSSVF-KU _CSSV-SLOT ! ;

DEFER _CSSV-SCHEMA

: _CSSV-DUPLICATE-FIELD?  ( prior-count -- flag )
    0 ?DO
        _CSSV-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP
        CSF.KEY-A @ SWAP CSF.KEY-U @
        _CSSV-KA@ _CSSV-KU@ STR-STR= IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

: _CSSV-FIELDS  ( -- ior )
    _CSSV-S@ CS.FIELD-N @ DUP 0< OVER CS-MAX-FIELDS > OR IF
        DROP CS-E-SCHEMA EXIT
    THEN
    DUP 0> IF _CSSV-S@ CS.FIELDS @ 0= IF
        DROP CS-E-SCHEMA EXIT
    THEN THEN
    0 ?DO
        _CSSV-S@ CS.FIELDS @ I CS-FIELD-SIZE * +
        DUP CSF.FLAGS @ CSF-F-REQUIRED INVERT AND IF
            DROP CS-E-SCHEMA UNLOOP EXIT
        THEN
        DUP CSF.SCHEMA @ 0= IF DROP CS-E-SCHEMA UNLOOP EXIT THEN
        DUP CSF.KEY-A @ SWAP CSF.KEY-U @ DUP 0< IF
            2DROP CS-E-SCHEMA UNLOOP EXIT
        THEN
        DUP CV-MAX-STRING-LEN > IF
            2DROP CS-E-SCHEMA UNLOOP EXIT
        THEN
        DUP 0> IF OVER 0= IF
            2DROP CS-E-SCHEMA UNLOOP EXIT
        THEN THEN
        2DUP UTF8-VALID? 0= IF 2DROP CS-E-SCHEMA UNLOOP EXIT THEN
        _CSSV-KU! _CSSV-KA!
        I _CSSV-DUPLICATE-FIELD? IF CS-E-SCHEMA UNLOOP EXIT THEN
        _CSSV-S@ CS.FIELDS @ I CS-FIELD-SIZE * + CSF.SCHEMA @
        _CSSV-SCHEMA ?DUP IF UNLOOP EXIT THEN
    LOOP
    0 ;

: _CSSV-SCHEMA-R  ( schema -- ior )
    DUP 0= IF DROP CS-E-SCHEMA EXIT THEN
    1 _CSSV-NODES +!
    _CSSV-NODES @ CS-MAX-NODES > IF DROP CS-E-CAPACITY EXIT THEN
    1 _CSSV-DEPTH +!
    _CSSV-DEPTH @ CS-MAX-DEPTH >= IF
        DROP -1 _CSSV-DEPTH +! CS-E-DEPTH EXIT
    THEN
    DUP _CSSV-S!
    _CSSV-DUMMY SWAP CS-VALIDATE DUP CS-E-TYPE = IF DROP 0 THEN
    ?DUP IF -1 _CSSV-DEPTH +! EXIT THEN
    _CSSV-S@ CS.TYPE-MASK @ CV-T-LIST CS-TYPE-BIT AND IF
        _CSSV-S@ CS.ITEM @ ?DUP IF
            _CSSV-SCHEMA ?DUP IF -1 _CSSV-DEPTH +! EXIT THEN
        THEN
    THEN
    _CSSV-S@ CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
        _CSSV-FIELDS ?DUP IF -1 _CSSV-DEPTH +! EXIT THEN
    THEN
    -1 _CSSV-DEPTH +! 0 ;

' _CSSV-SCHEMA-R IS _CSSV-SCHEMA

: _CSSV-VALIDATE  ( schema -- ior )
    _CSSV-DUMMY CV-INIT
    0 _CSSV-NODES ! -1 _CSSV-DEPTH ! _CSSV-SCHEMA ;

\ Public graph-only validation.  A null pointer is not a schema here;
\ callers whose contract treats a null schema as "unspecified" must handle
\ that case before calling.  This checks every reachable list item and map
\ field even when no corresponding runtime value is present.
: CS-SCHEMA-VALIDATE  ( schema -- ior )
    DUP 0= IF DROP CS-E-SCHEMA EXIT THEN
    _CSSV-VALIDATE ;

: CS-VALIDATE-DEEP  ( value schema -- ior )
    DUP 0= IF 2DROP CS-E-SCHEMA EXIT THEN
    DUP _CSSV-VALIDATE ?DUP IF >R 2DROP R> EXIT THEN
    0 _CSD-NODES ! -1 _CSD-DEPTH ! _CSD-VALUE ;

: CS-VALIDATE-FIELDS  ( map schema -- ior )
    CS-VALIDATE-DEEP ;

GUARD _cs-guard
' CS-VALIDATE CONSTANT _cs-validate-xt
' CS-SCHEMA-VALIDATE CONSTANT _cs-schema-validate-xt
' CS-VALIDATE-DEEP CONSTANT _cs-validate-deep-xt
' CS-VALIDATE-FIELDS CONSTANT _cs-validate-fields-xt
: CS-VALIDATE  _cs-validate-xt _cs-guard WITH-GUARD ;
: CS-SCHEMA-VALIDATE
    _cs-schema-validate-xt _cs-guard WITH-GUARD ;
: CS-VALIDATE-DEEP  _cs-validate-deep-xt _cs-guard WITH-GUARD ;
: CS-VALIDATE-FIELDS  _cs-validate-fields-xt _cs-guard WITH-GUARD ;
