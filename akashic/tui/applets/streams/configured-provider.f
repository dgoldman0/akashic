\ =====================================================================
\ configured-provider.f - transport-neutral configured provider seam
\ =====================================================================
\ Streams owns this small interface; protocol and transport adapters own
\ the opaque CONTEXT and implement every callback.  CONFIGURE receives a
\ borrowed, already-validated Streams source record.  Returned strings are
\ borrowed from CONTEXT and remain valid until the next provider operation.
\
\ A factory has stack effect ( -- provider status ).  On success it returns
\ a heap-allocated, sealed provider and SCONF-S-OK.  On failure it returns
\ zero and owns cleanup of every partial allocation.  After sealing, the
\ provider owns CONTEXT.  SCONF-RELEASE first asks the context to release
\ itself and frees the provider only after that callback succeeds.
\
\ Callback stack effects:
\   CONFIGURE-XT       ( source context -- status )
\   REQUESTED-XT       ( context -- a u )
\   EFFECTIVE-XT       ( context -- a u )
\   BODY-XT            ( context -- a u )
\   MEDIA-KIND-XT      ( context -- kind )
\   OUTCOME-XT         ( context -- outcome )
\   DETAIL-XT          ( context -- detail )
\   HTTP-STATUS-XT     ( context -- status-code )
\   RESULT-VALID-XT    ( context -- flag )
\   CLEANUP-ERROR-XT   ( context -- error )
\   RELEASABLE-XT      ( context -- flag )
\   POISON-XT          ( error context -- )
\   RELEASE-XT         ( context -- status )
\   START/POLL-XT      ( operation context -- step-status )
\   CANCEL/WIPE-XT     ( operation context -- )
\ =====================================================================

PROVIDED akashic-streams-configured-provider

REQUIRE ../../../net/external-io.f

0 CONSTANT SCONF-S-OK
1 CONSTANT SCONF-S-INVALID
2 CONSTANT SCONF-S-BUSY
3 CONSTANT SCONF-S-CAPACITY
4 CONSTANT SCONF-S-TRANSPORT

\ Transport-neutral retained acquisition outcomes.  Concrete HTTP providers
\ map their internal result domain to this closed set before exposing it.
0  CONSTANT SCONF-O-NONE
1  CONSTANT SCONF-O-OK
2  CONSTANT SCONF-O-HTTP
3  CONSTANT SCONF-O-REDIRECT-LIMIT
4  CONSTANT SCONF-O-REDIRECT-LOOP
5  CONSTANT SCONF-O-AUTHORITY-REQUIRED
6  CONSTANT SCONF-O-REDIRECT-INVALID
7  CONSTANT SCONF-O-HEADER
8  CONSTANT SCONF-O-MEDIA
9  CONSTANT SCONF-O-CONTENT-ENCODING
10 CONSTANT SCONF-O-BODY-OVERFLOW
11 CONSTANT SCONF-O-PROTOCOL
12 CONSTANT SCONF-O-TRANSPORT
13 CONSTANT SCONF-O-CANCELLED
14 CONSTANT SCONF-O-CLEANUP
15 CONSTANT SCONF-O-FAULT
16 CONSTANT SCONF-O-TIMED-OUT

-4803 CONSTANT SCONF-E-INVALID

0x5343464750525631 CONSTANT SCONF-MAGIC  \ "SCFGPRV1"

  0 CONSTANT _SCONF-MAGIC
  8 CONSTANT _SCONF-CONTEXT
 16 CONSTANT _SCONF-CONFIGURE-XT
 24 CONSTANT _SCONF-REQUESTED-XT
 32 CONSTANT _SCONF-EFFECTIVE-XT
 40 CONSTANT _SCONF-BODY-XT
 48 CONSTANT _SCONF-MEDIA-KIND-XT
 56 CONSTANT _SCONF-OUTCOME-XT
 64 CONSTANT _SCONF-DETAIL-XT
 72 CONSTANT _SCONF-HTTP-STATUS-XT
 80 CONSTANT _SCONF-RESULT-VALID-XT
 88 CONSTANT _SCONF-CLEANUP-ERROR-XT
 96 CONSTANT _SCONF-RELEASABLE-XT
104 CONSTANT _SCONF-POISON-XT
112 CONSTANT _SCONF-RELEASE-XT
120 CONSTANT _SCONF-START-XT
128 CONSTANT _SCONF-POLL-XT
136 CONSTANT _SCONF-CANCEL-XT
144 CONSTANT _SCONF-WIPE-XT
152 CONSTANT STREAMS-CONFIGURED-PROVIDER-SIZE

: SCONF.MAGIC             ( provider -- a ) _SCONF-MAGIC + ;
: SCONF.CONTEXT           ( provider -- a ) _SCONF-CONTEXT + ;
: SCONF.CONFIGURE-XT      ( provider -- a ) _SCONF-CONFIGURE-XT + ;
: SCONF.REQUESTED-XT      ( provider -- a ) _SCONF-REQUESTED-XT + ;
: SCONF.EFFECTIVE-XT      ( provider -- a ) _SCONF-EFFECTIVE-XT + ;
: SCONF.BODY-XT           ( provider -- a ) _SCONF-BODY-XT + ;
: SCONF.MEDIA-KIND-XT     ( provider -- a ) _SCONF-MEDIA-KIND-XT + ;
: SCONF.OUTCOME-XT        ( provider -- a ) _SCONF-OUTCOME-XT + ;
: SCONF.DETAIL-XT         ( provider -- a ) _SCONF-DETAIL-XT + ;
: SCONF.HTTP-STATUS-XT    ( provider -- a ) _SCONF-HTTP-STATUS-XT + ;
: SCONF.RESULT-VALID-XT   ( provider -- a ) _SCONF-RESULT-VALID-XT + ;
: SCONF.CLEANUP-ERROR-XT  ( provider -- a ) _SCONF-CLEANUP-ERROR-XT + ;
: SCONF.RELEASABLE-XT     ( provider -- a ) _SCONF-RELEASABLE-XT + ;
: SCONF.POISON-XT         ( provider -- a ) _SCONF-POISON-XT + ;
: SCONF.RELEASE-XT        ( provider -- a ) _SCONF-RELEASE-XT + ;
: SCONF.START-XT          ( provider -- a ) _SCONF-START-XT + ;
: SCONF.POLL-XT           ( provider -- a ) _SCONF-POLL-XT + ;
: SCONF.CANCEL-XT         ( provider -- a ) _SCONF-CANCEL-XT + ;
: SCONF.WIPE-XT           ( provider -- a ) _SCONF-WIPE-XT + ;

: SCONF-INIT  ( provider -- )
    DUP 0<> IF STREAMS-CONFIGURED-PROVIDER-SIZE 0 FILL ELSE DROP THEN ;

: SCONF-VALID?  ( provider -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP SCONF.MAGIC @ SCONF-MAGIC =
    OVER SCONF.CONTEXT @ 0<> AND
    OVER SCONF.CONFIGURE-XT @ 0<> AND
    OVER SCONF.REQUESTED-XT @ 0<> AND
    OVER SCONF.EFFECTIVE-XT @ 0<> AND
    OVER SCONF.BODY-XT @ 0<> AND
    OVER SCONF.MEDIA-KIND-XT @ 0<> AND
    OVER SCONF.OUTCOME-XT @ 0<> AND
    OVER SCONF.DETAIL-XT @ 0<> AND
    OVER SCONF.HTTP-STATUS-XT @ 0<> AND
    OVER SCONF.RESULT-VALID-XT @ 0<> AND
    OVER SCONF.CLEANUP-ERROR-XT @ 0<> AND
    OVER SCONF.RELEASABLE-XT @ 0<> AND
    OVER SCONF.POISON-XT @ 0<> AND
    OVER SCONF.RELEASE-XT @ 0<> AND
    OVER SCONF.START-XT @ 0<> AND
    OVER SCONF.POLL-XT @ 0<> AND
    OVER SCONF.CANCEL-XT @ 0<> AND
    SWAP SCONF.WIPE-XT @ 0<> AND ;

: SCONF-SEAL  ( provider -- status )
    DUP 0= IF DROP SCONF-S-INVALID EXIT THEN
    SCONF-MAGIC OVER SCONF.MAGIC !
    DUP SCONF-VALID? IF DROP SCONF-S-OK EXIT THEN
    SCONF-INIT SCONF-S-INVALID ;

VARIABLE _SCONF-P
VARIABLE _SCONF-SOURCE

: SCONF-CONFIGURE  ( source provider -- status )
    _SCONF-P ! _SCONF-SOURCE !
    _SCONF-SOURCE @ 0= IF SCONF-S-INVALID EXIT THEN
    _SCONF-P @ SCONF-VALID? 0= IF SCONF-S-INVALID EXIT THEN
    _SCONF-SOURCE @ _SCONF-P @ SCONF.CONTEXT @
        _SCONF-P @ SCONF.CONFIGURE-XT @ EXECUTE ;

: SCONF-REQUESTED$  ( provider -- a u )
    DUP SCONF-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.REQUESTED-XT @ EXECUTE ;

: SCONF-EFFECTIVE$  ( provider -- a u )
    DUP SCONF-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.EFFECTIVE-XT @ EXECUTE ;

: SCONF-BODY$  ( provider -- a u )
    DUP SCONF-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.BODY-XT @ EXECUTE ;

: SCONF-MEDIA-KIND  ( provider -- kind )
    DUP SCONF-VALID? 0= IF DROP 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.MEDIA-KIND-XT @ EXECUTE ;

: SCONF-OUTCOME  ( provider -- outcome )
    DUP SCONF-VALID? 0= IF DROP 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.OUTCOME-XT @ EXECUTE ;

: SCONF-DETAIL  ( provider -- detail )
    DUP SCONF-VALID? 0= IF DROP 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.DETAIL-XT @ EXECUTE ;

: SCONF-HTTP-STATUS  ( provider -- status-code )
    DUP SCONF-VALID? 0= IF DROP 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.HTTP-STATUS-XT @ EXECUTE ;

: SCONF-RESULT-VALID?  ( provider -- flag )
    DUP SCONF-VALID? 0= IF DROP 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.RESULT-VALID-XT @ EXECUTE ;

: SCONF-CLEANUP-ERROR@  ( provider -- error )
    DUP SCONF-VALID? 0= IF DROP SCONF-E-INVALID EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.CLEANUP-ERROR-XT @ EXECUTE ;

: SCONF-RELEASABLE?  ( provider -- flag )
    DUP SCONF-VALID? 0= IF DROP 0 EXIT THEN
    DUP SCONF.CONTEXT @ SWAP SCONF.RELEASABLE-XT @ EXECUTE ;

VARIABLE _SCONF-POISON-ERROR

: SCONF-POISON  ( error provider -- )
    DUP SCONF-VALID? 0= IF 2DROP EXIT THEN
    SWAP _SCONF-POISON-ERROR !
    DUP SCONF.CONTEXT @ SWAP SCONF.POISON-XT @
    _SCONF-POISON-ERROR @ -ROT EXECUTE ;

VARIABLE _SCONF-RELEASE-P
VARIABLE _SCONF-RELEASE-STATUS

: SCONF-RELEASE  ( provider -- status )
    DUP SCONF-VALID? 0= IF DROP SCONF-S-INVALID EXIT THEN
    DUP _SCONF-RELEASE-P !
    DUP SCONF.CONTEXT @ SWAP SCONF.RELEASE-XT @ EXECUTE
    DUP _SCONF-RELEASE-STATUS ! SCONF-S-OK <> IF
        _SCONF-RELEASE-STATUS @ EXIT
    THEN
    _SCONF-RELEASE-P @ DUP STREAMS-CONFIGURED-PROVIDER-SIZE 0 FILL FREE
    SCONF-S-OK ;

VARIABLE _SCONF-XIO-OP
VARIABLE _SCONF-XIO-P

: _SCONF-XIO-RESULT!  ( step-status -- step-status )
    DUP XIO-STEP-SUCCEEDED = IF
        _SCONF-XIO-P @ _SCONF-XIO-OP @ XIOO.RESULT !
    THEN ;

: _SCONF-XIO-INVALID  ( -- step-status )
    SCONF-E-INVALID _SCONF-XIO-OP @ XIOO.ERROR ! XIO-STEP-FAILED ;

: SCONF-XIO-START  ( operation provider -- step-status )
    _SCONF-XIO-P ! _SCONF-XIO-OP !
    _SCONF-XIO-P @ SCONF-VALID? 0= IF _SCONF-XIO-INVALID EXIT THEN
    _SCONF-XIO-OP @ _SCONF-XIO-P @ SCONF.CONTEXT @
        _SCONF-XIO-P @ SCONF.START-XT @ EXECUTE _SCONF-XIO-RESULT! ;

: SCONF-XIO-POLL  ( operation provider -- step-status )
    _SCONF-XIO-P ! _SCONF-XIO-OP !
    _SCONF-XIO-P @ SCONF-VALID? 0= IF _SCONF-XIO-INVALID EXIT THEN
    _SCONF-XIO-OP @ _SCONF-XIO-P @ SCONF.CONTEXT @
        _SCONF-XIO-P @ SCONF.POLL-XT @ EXECUTE _SCONF-XIO-RESULT! ;

: SCONF-XIO-CANCEL  ( operation provider -- )
    _SCONF-XIO-P ! _SCONF-XIO-OP !
    _SCONF-XIO-P @ SCONF-VALID? 0= IF SCONF-E-INVALID THROW THEN
    _SCONF-XIO-OP @ _SCONF-XIO-P @ SCONF.CONTEXT @
        _SCONF-XIO-P @ SCONF.CANCEL-XT @ EXECUTE ;

: SCONF-XIO-WIPE  ( operation provider -- )
    _SCONF-XIO-P ! _SCONF-XIO-OP !
    _SCONF-XIO-P @ SCONF-VALID? 0= IF SCONF-E-INVALID THROW THEN
    _SCONF-XIO-OP @ _SCONF-XIO-P @ SCONF.CONTEXT @
        _SCONF-XIO-P @ SCONF.WIPE-XT @ EXECUTE ;
