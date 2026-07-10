\ =====================================================================
\  schema.f - Bounded schemas for interoperable values
\ =====================================================================

PROVIDED akashic-interop-schema

REQUIRE value.f

1 CONSTANT CS-F-MIN
2 CONSTANT CS-F-MAX
4 CONSTANT CS-F-MAX-LEN

1 CONSTANT CS-E-TYPE
2 CONSTANT CS-E-MIN
3 CONSTANT CS-E-MAX
4 CONSTANT CS-E-LENGTH
5 CONSTANT CS-E-MISSING

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

: _CS-TYPE-OK?  ( value schema -- flag )
    SWAP CV-TYPE@ CS-TYPE-BIT SWAP CS.TYPE-MASK @ AND 0<> ;

VARIABLE _CSV-V
VARIABLE _CSV-S
VARIABLE _CSV-T

: CS-VALIDATE  ( value schema -- ior )
    _CSV-S ! _CSV-V !
    _CSV-V @ _CSV-S @ _CS-TYPE-OK? 0= IF CS-E-TYPE EXIT THEN
    _CSV-V @ CV-TYPE@ DUP _CSV-T !
    CV-T-INT = IF
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
        _CSV-S @ CS.FLAGS @ CS-F-MAX-LEN AND IF
            _CSV-V @ CV-LEN@ _CSV-S @ CS.MAX-LEN @ > IF
                CS-E-LENGTH EXIT
            THEN
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

: CS-VALIDATE-FIELDS  ( map schema -- ior )
    _CSV-S ! _CSV-V !
    _CSV-V @ CV-TYPE@ CV-T-MAP <> IF CS-E-TYPE EXIT THEN
    _CSV-S @ CS.FIELD-N @ 0 ?DO
        _CSV-S @ CS.FIELDS @ I CS-FIELD-SIZE * +
        DUP >R
        R@ CSF.KEY-A @ R@ CSF.KEY-U @ _CSV-V @ CV-MAP-FIND
        DUP 0= IF
            DROP R@ CSF.FLAGS @ CSF-F-REQUIRED AND IF
                R> DROP CS-E-MISSING UNLOOP EXIT
            THEN
        ELSE
            R@ CSF.SCHEMA @ CS-VALIDATE ?DUP IF
                R> DROP UNLOOP EXIT
            THEN
        THEN
        R> DROP
    LOOP
    0 ;
