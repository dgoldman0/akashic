\ =====================================================================
\  run-settings.f - Provider-neutral model and run option contract
\ =====================================================================
\  Providers own all strings and descriptors returned through this port.
\  Callers may borrow them until REVISION changes. Desk policy, approvals,
\  credentials, TUI state, and vendor protocol fields do not belong here.
\
\  A provider runs on the model and options selected through the port,
\  unless a turn names others in a designation: a model, effort, tier and
\  verbosity by id, which a run kept from when it was approved.
\  ARSET-DESIGNATION checks a designation against the catalog.
\ =====================================================================

PROVIDED akashic-agent-run-settings

0 CONSTANT ARSET-S-OK
1 CONSTANT ARSET-S-PENDING
2 CONSTANT ARSET-S-UNSUPPORTED
3 CONSTANT ARSET-S-INVALID
4 CONSTANT ARSET-S-BUSY
5 CONSTANT ARSET-S-CAPACITY
6 CONSTANT ARSET-S-TRANSPORT
7 CONSTANT ARSET-S-PROTOCOL
8 CONSTANT ARSET-S-AUTH
9 CONSTANT ARSET-S-CANCELLED

0 CONSTANT ARSET-STATE-EMPTY
1 CONSTANT ARSET-STATE-LOADING
2 CONSTANT ARSET-STATE-READY
3 CONSTANT ARSET-STATE-ERROR

1 CONSTANT ARCH-F-DEFAULT
2 CONSTANT ARCH-F-SELECTED

1   CONSTANT ARMODEL-F-DEFAULT
2   CONSTANT ARMODEL-F-SELECTED
4   CONSTANT ARMODEL-F-RESPONSES-LITE
8   CONSTANT ARMODEL-F-VERBOSITY
16  CONSTANT ARMODEL-F-TEXT
32  CONSTANT ARMODEL-F-IMAGE

0 CONSTANT ARVERB-AUTO
1 CONSTANT ARVERB-LOW
2 CONSTANT ARVERB-MEDIUM
3 CONSTANT ARVERB-HIGH

 0 CONSTANT _ARCH-ID-A
 8 CONSTANT _ARCH-ID-U
16 CONSTANT _ARCH-LABEL-A
24 CONSTANT _ARCH-LABEL-U
32 CONSTANT _ARCH-DESC-A
40 CONSTANT _ARCH-DESC-U
48 CONSTANT _ARCH-FLAGS
56 CONSTANT AGENT-RUN-CHOICE-SIZE

: ARCH.ID-A     ( choice -- a ) _ARCH-ID-A + ;
: ARCH.ID-U     ( choice -- a ) _ARCH-ID-U + ;
: ARCH.LABEL-A  ( choice -- a ) _ARCH-LABEL-A + ;
: ARCH.LABEL-U  ( choice -- a ) _ARCH-LABEL-U + ;
: ARCH.DESC-A   ( choice -- a ) _ARCH-DESC-A + ;
: ARCH.DESC-U   ( choice -- a ) _ARCH-DESC-U + ;
: ARCH.FLAGS    ( choice -- a ) _ARCH-FLAGS + ;

: ARCH-ID  ( choice -- addr len )
    DUP ARCH.ID-A @ SWAP ARCH.ID-U @ ;

: ARCH-LABEL  ( choice -- addr len )
    DUP ARCH.LABEL-A @ SWAP ARCH.LABEL-U @ ;

: ARCH-DESC  ( choice -- addr len )
    DUP ARCH.DESC-A @ SWAP ARCH.DESC-U @ ;

  0 CONSTANT _ARM-ID-A
  8 CONSTANT _ARM-ID-U
 16 CONSTANT _ARM-LABEL-A
 24 CONSTANT _ARM-LABEL-U
 32 CONSTANT _ARM-DESC-A
 40 CONSTANT _ARM-DESC-U
 48 CONSTANT _ARM-FLAGS
 56 CONSTANT _ARM-PRIORITY
 64 CONSTANT _ARM-CONTEXT-WINDOW
 72 CONSTANT _ARM-EFFORTS-A
 80 CONSTANT _ARM-EFFORTS-N
 88 CONSTANT _ARM-TIERS-A
 96 CONSTANT _ARM-TIERS-N
104 CONSTANT _ARM-CONTEXT
112 CONSTANT AGENT-RUN-MODEL-SIZE

: ARMODEL.ID-A           ( model -- a ) _ARM-ID-A + ;
: ARMODEL.ID-U           ( model -- a ) _ARM-ID-U + ;
: ARMODEL.LABEL-A        ( model -- a ) _ARM-LABEL-A + ;
: ARMODEL.LABEL-U        ( model -- a ) _ARM-LABEL-U + ;
: ARMODEL.DESC-A         ( model -- a ) _ARM-DESC-A + ;
: ARMODEL.DESC-U         ( model -- a ) _ARM-DESC-U + ;
: ARMODEL.FLAGS          ( model -- a ) _ARM-FLAGS + ;
: ARMODEL.PRIORITY       ( model -- a ) _ARM-PRIORITY + ;
: ARMODEL.CONTEXT-WINDOW ( model -- a ) _ARM-CONTEXT-WINDOW + ;
: ARMODEL.EFFORTS-A      ( model -- a ) _ARM-EFFORTS-A + ;
: ARMODEL.EFFORTS-N      ( model -- a ) _ARM-EFFORTS-N + ;
: ARMODEL.TIERS-A        ( model -- a ) _ARM-TIERS-A + ;
: ARMODEL.TIERS-N        ( model -- a ) _ARM-TIERS-N + ;
: ARMODEL.CONTEXT        ( model -- a ) _ARM-CONTEXT + ;

: ARMODEL-ID  ( model -- addr len )
    DUP ARMODEL.ID-A @ SWAP ARMODEL.ID-U @ ;

: ARMODEL-LABEL  ( model -- addr len )
    DUP ARMODEL.LABEL-A @ SWAP ARMODEL.LABEL-U @ ;

: ARMODEL-DESC  ( model -- addr len )
    DUP ARMODEL.DESC-A @ SWAP ARMODEL.DESC-U @ ;

VARIABLE _ARPN-I
VARIABLE _ARPN-A
VARIABLE _ARPN-N

: _ARSET-PTR-NTH  ( index pointer-array count -- ptr | 0 )
    _ARPN-N ! _ARPN-A ! _ARPN-I !
    _ARPN-I @ 0< _ARPN-I @ _ARPN-N @ >= OR IF 0 EXIT THEN
    _ARPN-A @ _ARPN-I @ 8 * + @ ;

: ARMODEL-EFFORT-NTH  ( index model -- choice | 0 )
    DUP ARMODEL.EFFORTS-A @ SWAP ARMODEL.EFFORTS-N @ _ARSET-PTR-NTH ;

: ARMODEL-TIER-NTH  ( index model -- choice | 0 )
    DUP ARMODEL.TIERS-A @ SWAP ARMODEL.TIERS-N @ _ARSET-PTR-NTH ;

  0 CONSTANT _ARSET-STATE
  8 CONSTANT _ARSET-REVISION
 16 CONSTANT _ARSET-CONTEXT
 24 CONSTANT _ARSET-MODELS-A
 32 CONSTANT _ARSET-MODELS-N
 40 CONSTANT _ARSET-SELECTED
 48 CONSTANT _ARSET-VERBOSITY
 56 CONSTANT _ARSET-ERROR-A
 64 CONSTANT _ARSET-ERROR-U
 72 CONSTANT _ARSET-REFRESH-XT
 80 CONSTANT _ARSET-POLL-XT
 88 CONSTANT _ARSET-CANCEL-XT
 96 CONSTANT _ARSET-MODEL-XT
104 CONSTANT _ARSET-EFFORT-XT
112 CONSTANT _ARSET-TIER-XT
120 CONSTANT _ARSET-VERBOSITY-XT
128 CONSTANT _ARSET-DISPOSE-XT
136 CONSTANT AGENT-RUN-SETTINGS-SIZE

: ARSET.STATE        ( settings -- a ) _ARSET-STATE + ;
: ARSET.REVISION     ( settings -- a ) _ARSET-REVISION + ;
: ARSET.CONTEXT      ( settings -- a ) _ARSET-CONTEXT + ;
: ARSET.MODELS-A     ( settings -- a ) _ARSET-MODELS-A + ;
: ARSET.MODELS-N     ( settings -- a ) _ARSET-MODELS-N + ;
: ARSET.SELECTED     ( settings -- a ) _ARSET-SELECTED + ;
: ARSET.VERBOSITY    ( settings -- a ) _ARSET-VERBOSITY + ;
: ARSET.ERROR-A      ( settings -- a ) _ARSET-ERROR-A + ;
: ARSET.ERROR-U      ( settings -- a ) _ARSET-ERROR-U + ;
: ARSET.REFRESH-XT   ( settings -- a ) _ARSET-REFRESH-XT + ;
: ARSET.POLL-XT      ( settings -- a ) _ARSET-POLL-XT + ;
: ARSET.CANCEL-XT    ( settings -- a ) _ARSET-CANCEL-XT + ;
: ARSET.MODEL-XT     ( settings -- a ) _ARSET-MODEL-XT + ;
: ARSET.EFFORT-XT    ( settings -- a ) _ARSET-EFFORT-XT + ;
: ARSET.TIER-XT      ( settings -- a ) _ARSET-TIER-XT + ;
: ARSET.VERBOSITY-XT ( settings -- a ) _ARSET-VERBOSITY-XT + ;
: ARSET.DISPOSE-XT   ( settings -- a ) _ARSET-DISPOSE-XT + ;

: ARSET-INIT  ( settings -- )
    DUP AGENT-RUN-SETTINGS-SIZE 0 FILL
    1 OVER ARSET.REVISION !
    -1 OVER ARSET.SELECTED !
    ARSET-STATE-EMPTY SWAP ARSET.STATE ! ;

: ARSET-PENDING?  ( settings -- flag )
    DUP 0= IF DROP 0 EXIT THEN ARSET.STATE @ ARSET-STATE-LOADING = ;

: ARSET-ERROR  ( settings -- addr len )
    DUP ARSET.ERROR-A @ SWAP ARSET.ERROR-U @ ;

: ARSET-MODEL-N  ( settings -- count )
    DUP 0= IF EXIT THEN ARSET.MODELS-N @ ;

: ARSET-MODEL-NTH  ( index settings -- model | 0 )
    DUP ARSET.MODELS-A @ SWAP ARSET.MODELS-N @ _ARSET-PTR-NTH ;

: ARSET-SELECTED-MODEL  ( settings -- model | 0 )
    DUP ARSET.SELECTED @ SWAP ARSET-MODEL-NTH ;

: _ARSET-NOARG  ( settings field-offset -- status )
    >R DUP 0= IF DROP R> DROP ARSET-S-UNSUPPORTED EXIT THEN
    DUP R> + @ ?DUP 0= IF DROP ARSET-S-UNSUPPORTED EXIT THEN
    >R ARSET.CONTEXT @ R> EXECUTE ;

: ARSET-REFRESH  ( settings -- status ) _ARSET-REFRESH-XT _ARSET-NOARG ;
: ARSET-POLL     ( settings -- status ) _ARSET-POLL-XT _ARSET-NOARG ;
: ARSET-CANCEL   ( settings -- status ) _ARSET-CANCEL-XT _ARSET-NOARG ;

: ARSET-MODEL!  ( index settings -- status )
    DUP 0= IF 2DROP ARSET-S-UNSUPPORTED EXIT THEN
    DUP ARSET.MODEL-XT @ ?DUP 0= IF 2DROP ARSET-S-UNSUPPORTED EXIT THEN
    >R ARSET.CONTEXT @ R> EXECUTE ;

: ARSET-EFFORT!  ( index settings -- status )
    DUP 0= IF 2DROP ARSET-S-UNSUPPORTED EXIT THEN
    DUP ARSET.EFFORT-XT @ ?DUP 0= IF 2DROP ARSET-S-UNSUPPORTED EXIT THEN
    >R ARSET.CONTEXT @ R> EXECUTE ;

: ARSET-TIER!  ( index settings -- status )
    DUP 0= IF 2DROP ARSET-S-UNSUPPORTED EXIT THEN
    DUP ARSET.TIER-XT @ ?DUP 0= IF 2DROP ARSET-S-UNSUPPORTED EXIT THEN
    >R ARSET.CONTEXT @ R> EXECUTE ;

: ARSET-VERBOSITY!  ( verbosity settings -- status )
    DUP 0= IF 2DROP ARSET-S-UNSUPPORTED EXIT THEN
    DUP ARSET.VERBOSITY-XT @ ?DUP 0= IF
        2DROP ARSET-S-UNSUPPORTED EXIT
    THEN
    >R ARSET.CONTEXT @ R> EXECUTE ;

: ARSET-DESTROY  ( settings -- )
    DUP 0= IF DROP EXIT THEN
    DUP ARSET.DISPOSE-XT @ ?DUP IF
        >R DUP ARSET.CONTEXT @ R> EXECUTE
    THEN
    AGENT-RUN-SETTINGS-SIZE 0 FILL ;

\ ---------------------------------------------------------------------
\  Selections and designations
\ ---------------------------------------------------------------------

\ MODEL's selected effort or tier, or 0.
: _ARMODEL-SELECTED  ( model nth-xt n -- choice|0 )
    0 ?DO
        I 2 PICK 2 PICK EXECUTE ?DUP IF
            DUP ARCH.FLAGS @ ARCH-F-SELECTED AND IF NIP NIP UNLOOP EXIT THEN
            DROP
        THEN
    LOOP
    2DROP 0 ;

: ARMODEL-SELECTED-EFFORT  ( model -- choice|0 )
    DUP 0= IF EXIT THEN
    ['] ARMODEL-EFFORT-NTH OVER ARMODEL.EFFORTS-N @ _ARMODEL-SELECTED ;

: ARMODEL-SELECTED-TIER  ( model -- choice|0 )
    DUP 0= IF EXIT THEN
    ['] ARMODEL-TIER-NTH OVER ARMODEL.TIERS-N @ _ARMODEL-SELECTED ;

\ A designation names one model and its options for one run, by id.  It
\ borrows its strings.  An empty effort names none, for a model that has
\ none; an empty tier asks for no service tier.
 0 CONSTANT _ARD-MODEL-A
 8 CONSTANT _ARD-MODEL-U
16 CONSTANT _ARD-EFFORT-A
24 CONSTANT _ARD-EFFORT-U
32 CONSTANT _ARD-TIER-A
40 CONSTANT _ARD-TIER-U
48 CONSTANT _ARD-VERBOSITY
56 CONSTANT AGENT-RUN-DESIGNATION-SIZE

: ARDES.MODEL-A    ( designation -- a ) _ARD-MODEL-A + ;
: ARDES.MODEL-U    ( designation -- a ) _ARD-MODEL-U + ;
: ARDES.EFFORT-A   ( designation -- a ) _ARD-EFFORT-A + ;
: ARDES.EFFORT-U   ( designation -- a ) _ARD-EFFORT-U + ;
: ARDES.TIER-A     ( designation -- a ) _ARD-TIER-A + ;
: ARDES.TIER-U     ( designation -- a ) _ARD-TIER-U + ;
: ARDES.VERBOSITY  ( designation -- a ) _ARD-VERBOSITY + ;

: ARDES-INIT  ( designation -- ) AGENT-RUN-DESIGNATION-SIZE 0 FILL ;

: ARDES-MODEL  ( designation -- addr len )
    DUP ARDES.MODEL-A @ SWAP ARDES.MODEL-U @ ;

: ARDES-EFFORT  ( designation -- addr len )
    DUP ARDES.EFFORT-A @ SWAP ARDES.EFFORT-U @ ;

: ARDES-TIER  ( designation -- addr len )
    DUP ARDES.TIER-A @ SWAP ARDES.TIER-U @ ;

\ The model in SETTINGS whose id is ID, or 0.
: ARSET-FIND-MODEL  ( id-a id-u settings -- model|0 )
    DUP ARSET-MODEL-N 0 ?DO
        I OVER ARSET-MODEL-NTH ?DUP IF
            DUP ARMODEL-ID 5 PICK 5 PICK COMPARE 0= IF
                NIP NIP NIP UNLOOP EXIT
            THEN
            DROP
        THEN
    LOOP
    DROP 2DROP 0 ;

\ The index of the choice whose id is ID among MODEL's N choices that
\ NTH-XT gives, or -1.
: _ARMODEL-FIND  ( id-a id-u model nth-xt n -- index )
    0 ?DO
        I 2 PICK 2 PICK EXECUTE ?DUP IF
            ARCH-ID 5 PICK 5 PICK COMPARE 0= IF
                2DROP 2DROP I UNLOOP EXIT
            THEN
        THEN
    LOOP
    2DROP 2DROP -1 ;

: ARMODEL-FIND-EFFORT  ( id-a id-u model -- index )
    ['] ARMODEL-EFFORT-NTH OVER ARMODEL.EFFORTS-N @ _ARMODEL-FIND ;

: ARMODEL-FIND-TIER  ( id-a id-u model -- index )
    ['] ARMODEL-TIER-NTH OVER ARMODEL.TIERS-N @ _ARMODEL-FIND ;

\ Whether MODEL offers the effort ID names: one of its own, or none when
\ it has none.
: _ARMODEL-EFFORT?  ( id-a id-u model -- flag )
    DUP ARMODEL.EFFORTS-N @ 0= IF DROP NIP 0= EXIT THEN
    ARMODEL-FIND-EFFORT 0< 0= ;

\ Whether MODEL offers the tier ID names: none, or one of its own.
: _ARMODEL-TIER?  ( id-a id-u model -- flag )
    OVER 0= IF 2DROP DROP -1 EXIT THEN
    ARMODEL-FIND-TIER 0< 0= ;

\ Whether MODEL takes VERBOSITY: its own default, or any it lets a run
\ choose.
: _ARMODEL-VERBOSITY?  ( verbosity model -- flag )
    SWAP ARVERB-AUTO = IF DROP -1 EXIT THEN
    ARMODEL.FLAGS @ ARMODEL-F-VERBOSITY AND 0<> ;

\ The model in SETTINGS that DESIGNATION names, when the catalog offers
\ exactly what it names: the model, its effort, its tier and its
\ verbosity.  PENDING while the catalog is not ready; UNSUPPORTED when it
\ does not offer that.
: ARSET-DESIGNATION  ( designation settings -- model|0 status )
    OVER 0= OVER 0= OR IF 2DROP 0 ARSET-S-INVALID EXIT THEN
    OVER ARDES.VERBOSITY @ ARVERB-AUTO ARVERB-HIGH 1+ WITHIN 0= IF
        2DROP 0 ARSET-S-INVALID EXIT
    THEN
    DUP ARSET.STATE @ ARSET-STATE-READY <> IF 2DROP 0 ARSET-S-PENDING EXIT THEN
    OVER ARDES-MODEL ROT ARSET-FIND-MODEL               ( designation model|0 )
    DUP 0= IF NIP ARSET-S-UNSUPPORTED EXIT THEN
    OVER ARDES-EFFORT 2 PICK _ARMODEL-EFFORT?
    2 PICK ARDES-TIER 3 PICK _ARMODEL-TIER? AND
    2 PICK ARDES.VERBOSITY @ 2 PICK _ARMODEL-VERBOSITY? AND
    ROT DROP IF ARSET-S-OK ELSE DROP 0 ARSET-S-UNSUPPORTED THEN ;
