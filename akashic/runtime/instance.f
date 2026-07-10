\ =====================================================================
\  instance.f - Reusable component descriptors and live instances
\ =====================================================================
\  This layer has no TUI, Desk, UIDL, provider, or transport dependency.
\ =====================================================================

PROVIDED akashic-runtime-instance

1095451472 CONSTANT COMP-MAGIC       \ "AKCP"
1          CONSTANT COMP-ABI-VERSION

1 CONSTANT COMP-E-BAD-DESC
2 CONSTANT COMP-E-NOMEM
3 CONSTANT COMP-E-INIT

\ Component descriptor, 16 cells / 128 bytes.
  0 CONSTANT _CD-MAGIC
  8 CONSTANT _CD-ABI
 16 CONSTANT _CD-SIZE
 24 CONSTANT _CD-ID-A
 32 CONSTANT _CD-ID-U
 40 CONSTANT _CD-VER-A
 48 CONSTANT _CD-VER-U
 56 CONSTANT _CD-STATE-SIZE
 64 CONSTANT _CD-STATE-INIT-XT       \ ( state -- ior )
 72 CONSTANT _CD-STATE-FINI-XT       \ ( state -- )
 80 CONSTANT _CD-CAPS-A
 88 CONSTANT _CD-CAPS-N
 96 CONSTANT _CD-INTENTS-A
104 CONSTANT _CD-INTENTS-N
112 CONSTANT _CD-FLAGS
120 CONSTANT _CD-RESERVED
128 CONSTANT COMP-DESC

: COMP.MAGIC          ( desc -- a ) _CD-MAGIC + ;
: COMP.ABI            ( desc -- a ) _CD-ABI + ;
: COMP.SIZE           ( desc -- a ) _CD-SIZE + ;
: COMP.ID-A           ( desc -- a ) _CD-ID-A + ;
: COMP.ID-U           ( desc -- a ) _CD-ID-U + ;
: COMP.VERSION-A      ( desc -- a ) _CD-VER-A + ;
: COMP.VERSION-U      ( desc -- a ) _CD-VER-U + ;
: COMP.STATE-SIZE     ( desc -- a ) _CD-STATE-SIZE + ;
: COMP.STATE-INIT-XT  ( desc -- a ) _CD-STATE-INIT-XT + ;
: COMP.STATE-FINI-XT  ( desc -- a ) _CD-STATE-FINI-XT + ;
: COMP.CAPS-A         ( desc -- a ) _CD-CAPS-A + ;
: COMP.CAPS-N         ( desc -- a ) _CD-CAPS-N + ;
: COMP.INTENTS-A      ( desc -- a ) _CD-INTENTS-A + ;
: COMP.INTENTS-N      ( desc -- a ) _CD-INTENTS-N + ;
: COMP.FLAGS          ( desc -- a ) _CD-FLAGS + ;

: COMP-DESC-INIT  ( desc -- )
    DUP COMP-DESC 0 FILL
    COMP-MAGIC OVER COMP.MAGIC !
    COMP-ABI-VERSION OVER COMP.ABI !
    COMP-DESC SWAP COMP.SIZE ! ;

: COMP-DESC-VALID?  ( desc -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP COMP.MAGIC @ COMP-MAGIC =
    OVER COMP.ABI @ COMP-ABI-VERSION = AND
    SWAP COMP.SIZE @ COMP-DESC >= AND ;

\ Live component instance, 10 cells / 80 bytes.
 0 CONSTANT _CI-DESC
 8 CONSTANT _CI-STATE
16 CONSTANT _CI-ID
24 CONSTANT _CI-GENERATION
32 CONSTANT _CI-REVISION
40 CONSTANT _CI-FLAGS
48 CONSTANT _CI-ENDPOINT
56 CONSTANT _CI-LAST-ERROR
64 CONSTANT _CI-RESERVED-0
72 CONSTANT _CI-RESERVED-1
80 CONSTANT COMP-INST

: CINST.DESC        ( inst -- a ) _CI-DESC + ;
: CINST.STATE       ( inst -- a ) _CI-STATE + ;
: CINST.ID          ( inst -- a ) _CI-ID + ;
: CINST.GENERATION  ( inst -- a ) _CI-GENERATION + ;
: CINST.REVISION    ( inst -- a ) _CI-REVISION + ;
: CINST.FLAGS       ( inst -- a ) _CI-FLAGS + ;
: CINST.ENDPOINT    ( inst -- a ) _CI-ENDPOINT + ;
: CINST.LAST-ERROR  ( inst -- a ) _CI-LAST-ERROR + ;

: CINST-STATE  ( inst -- state ) CINST.STATE @ ;
: CINST-DESC   ( inst -- desc )  CINST.DESC @ ;
: CINST-TOUCH  ( inst -- )       1 SWAP CINST.REVISION +! ;

VARIABLE _CINST-NEXT-ID
1 _CINST-NEXT-ID !

VARIABLE _CIN-DESC
VARIABLE _CIN-INST
VARIABLE _CIN-STATE
VARIABLE _CIN-IOR
VARIABLE _CIN-SIZE

: _CINST-ALLOC-STATE  ( desc -- state ior )
    COMP.STATE-SIZE @ DUP _CIN-SIZE !
    DUP 0= IF DROP 0 0 EXIT THEN
    ALLOCATE
    DUP IF EXIT THEN
    DROP DUP _CIN-SIZE @ 0 FILL 0 ;

: _CINST-RELEASE-PARTIAL  ( -- )
    _CIN-STATE @ ?DUP IF FREE THEN
    _CIN-INST @ ?DUP IF FREE THEN
    0 _CIN-STATE ! 0 _CIN-INST ! ;

: CINST-NEW  ( desc -- inst ior )
    DUP COMP-DESC-VALID? 0= IF DROP 0 COMP-E-BAD-DESC EXIT THEN
    _CIN-DESC !
    0 _CIN-INST ! 0 _CIN-STATE !
    COMP-INST ALLOCATE
    DUP IF SWAP DROP 0 SWAP EXIT THEN
    DROP DUP _CIN-INST ! COMP-INST 0 FILL
    _CIN-DESC @ _CINST-ALLOC-STATE
    _CIN-IOR ! _CIN-STATE !
    _CIN-IOR @ IF
        _CINST-RELEASE-PARTIAL 0 COMP-E-NOMEM EXIT
    THEN
    _CIN-DESC @ _CIN-INST @ CINST.DESC !
    _CIN-STATE @ _CIN-INST @ CINST.STATE !
    _CINST-NEXT-ID @ DUP _CIN-INST @ CINST.ID !
    _CIN-INST @ CINST.GENERATION !
    1 _CINST-NEXT-ID +!
    1 _CIN-INST @ CINST.REVISION !
    _CIN-DESC @ COMP.STATE-INIT-XT @ ?DUP IF
        _CIN-STATE @ SWAP EXECUTE DUP _CIN-IOR !
        IF _CINST-RELEASE-PARTIAL 0 COMP-E-INIT EXIT THEN
    THEN
    _CIN-INST @ 0 ;

: CINST-FREE  ( inst -- )
    DUP 0= IF DROP EXIT THEN
    DUP CINST-DESC COMP.STATE-FINI-XT @ ?DUP IF
        OVER CINST-STATE SWAP EXECUTE
    THEN
    DUP CINST-STATE ?DUP IF FREE THEN
    FREE ;
