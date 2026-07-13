\ =====================================================================
\  registry.f - Runtime type and live-instance registry
\ =====================================================================

PROVIDED akashic-runtime-registry

REQUIRE instance.f
REQUIRE ../interop/capability.f
REQUIRE ../utils/string.f

32 CONSTANT CREG-MAX-TYPES
64 CONSTANT CREG-MAX-INSTANCES

1 CONSTANT CREG-E-NOMEM
2 CONSTANT CREG-E-FULL
3 CONSTANT CREG-E-DUPLICATE
4 CONSTANT CREG-E-NOT-FOUND

  0 CONSTANT _CR-TYPE-N
  8 CONSTANT _CR-INST-N
 16 CONSTANT _CR-TYPES
_CR-TYPES CREG-MAX-TYPES 8 * + CONSTANT _CR-INSTANCES
_CR-INSTANCES CREG-MAX-INSTANCES 8 * + CONSTANT CREG-SIZE

: CREG.TYPE-N     ( reg -- a ) _CR-TYPE-N + ;
: CREG.INST-N     ( reg -- a ) _CR-INST-N + ;
: CREG.TYPES      ( reg -- a ) _CR-TYPES + ;
: CREG.INSTANCES  ( reg -- a ) _CR-INSTANCES + ;

: CREG-NEW  ( -- reg ior )
    CREG-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP CREG-SIZE 0 FILL 0 ;

: CREG-FREE  ( reg -- )
    ?DUP IF FREE THEN ;

: CREG-TYPE-NTH  ( index reg -- desc | 0 )
    >R DUP 0< OVER R@ CREG.TYPE-N @ >= OR IF DROP R> DROP 0 EXIT THEN
    8 * R> CREG.TYPES + @ ;

: CREG-INST-NTH  ( index reg -- inst | 0 )
    >R DUP 0< OVER R@ CREG.INST-N @ >= OR IF DROP R> DROP 0 EXIT THEN
    8 * R> CREG.INSTANCES + @ ;

VARIABLE _CRT-A
VARIABLE _CRT-U
VARIABLE _CRT-R

: CREG-TYPE-FIND  ( id-a id-u reg -- desc | 0 )
    _CRT-R ! _CRT-U ! _CRT-A !
    _CRT-R @ CREG.TYPE-N @ 0 ?DO
        I _CRT-R @ CREG-TYPE-NTH DUP
        DUP COMP.ID-A @ SWAP COMP.ID-U @
        _CRT-A @ _CRT-U @ STR-STR= IF UNLOOP EXIT THEN
        DROP
    LOOP
    0 ;

: CREG-TYPE+  ( desc reg -- ior )
    >R
    DUP COMP-CAPS-VALID? 0= IF DROP R> DROP CREG-E-NOT-FOUND EXIT THEN
    DUP COMP.ID-A @ OVER COMP.ID-U @ R@ CREG-TYPE-FIND IF
        DROP R> DROP CREG-E-DUPLICATE EXIT
    THEN
    R@ CREG.TYPE-N @ CREG-MAX-TYPES >= IF
        DROP R> DROP CREG-E-FULL EXIT
    THEN
    R@ CREG.TYPE-N @ 8 * R@ CREG.TYPES + !
    1 R> CREG.TYPE-N +!
    0 ;

VARIABLE _CRIA-INST
VARIABLE _CRIA-R

: CREG-INST+  ( inst reg -- ior )
    _CRIA-R ! _CRIA-INST !
    _CRIA-INST @ 0= IF CREG-E-NOT-FOUND EXIT THEN
    _CRIA-R @ CREG.INST-N @ 0 ?DO
        I _CRIA-R @ CREG-INST-NTH _CRIA-INST @ = IF
            CREG-E-DUPLICATE UNLOOP EXIT
        THEN
    LOOP
    _CRIA-R @ CREG.INST-N @ CREG-MAX-INSTANCES >= IF
        CREG-E-FULL EXIT
    THEN
    _CRIA-INST @
    _CRIA-R @ CREG.INST-N @ 8 * _CRIA-R @ CREG.INSTANCES + !
    1 _CRIA-R @ CREG.INST-N +!
    0 ;

VARIABLE _CRI-ID
VARIABLE _CRI-GEN
VARIABLE _CRI-R

: CREG-INST-FIND  ( id generation reg -- inst | 0 )
    _CRI-R ! _CRI-GEN ! _CRI-ID !
    _CRI-R @ CREG.INST-N @ 0 ?DO
        I _CRI-R @ CREG-INST-NTH
        DUP CINST.ID @ _CRI-ID @ =
        OVER CINST.GENERATION @ _CRI-GEN @ = AND IF
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 ;

VARIABLE _CRR-INST
VARIABLE _CRR-R
VARIABLE _CRR-I

: CREG-INST-  ( inst reg -- ior )
    _CRR-R ! _CRR-INST !
    _CRR-R @ CREG.INST-N @ 0 ?DO
        I _CRR-R @ CREG-INST-NTH _CRR-INST @ = IF
            I _CRR-I !
            BEGIN _CRR-I @ _CRR-R @ CREG.INST-N @ 1- < WHILE
                _CRR-I @ 1+ _CRR-R @ CREG-INST-NTH
                _CRR-I @ 8 * _CRR-R @ CREG.INSTANCES + !
                1 _CRR-I +!
            REPEAT
            -1 _CRR-R @ CREG.INST-N +!
            0 _CRR-R @ CREG.INST-N @ 8 * _CRR-R @ CREG.INSTANCES + !
            0 UNLOOP EXIT
        THEN
    LOOP
    CREG-E-NOT-FOUND ;

VARIABLE _CRD-DESC
VARIABLE _CRD-R

: CREG-INST-BY-DESC  ( desc reg -- inst | 0 )
    _CRD-R ! _CRD-DESC !
    _CRD-R @ CREG.INST-N @ 0 ?DO
        I _CRD-R @ CREG-INST-NTH DUP CINST-DESC _CRD-DESC @ = IF
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 ;

: CREG-TYPE-ENSURE  ( desc reg -- ior )
    2DUP CREG-TYPE+ DUP CREG-E-DUPLICATE = IF
        DROP 2DROP 0
    ELSE
        >R 2DROP R>
    THEN ;
