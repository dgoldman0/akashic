\ =====================================================================
\ public-provider.f - applet-local public feed provider seam
\ =====================================================================
\ Streams owns this narrow interface.  Concrete protocol, transport, and
\ trust modules live in explicit composition modules rather than in the
\ ordinary offline applet dependency graph.
\ A state factory has stack effect ( -- provider status ).  Success returns a
\ sealed provider and SPUB-S-OK; failure owns all partial cleanup and returns
\ zero plus a non-OK status.
\ =====================================================================

PROVIDED akashic-streams-pubif

REQUIRE ../../../net/external-io.f

0 CONSTANT SPUB-S-OK
1 CONSTANT SPUB-S-INVALID
2 CONSTANT SPUB-S-BUSY
3 CONSTANT SPUB-S-CAPACITY
4 CONSTANT SPUB-S-TRANSPORT

-4802 CONSTANT SPUB-E-INVALID

2048 CONSTANT STREAMS-PUBLIC-ACTOR-CAPACITY

0x42555053 CONSTANT SPUB-MAGIC  \ "SPUB" in memory

  0 CONSTANT _SPUB-MAGIC
  8 CONSTANT _SPUB-CONTEXT
 16 CONSTANT _SPUB-CONFIGURE-XT
 24 CONSTANT _SPUB-DECONFIGURE-XT
 32 CONSTANT _SPUB-BODY-XT
 40 CONSTANT _SPUB-RESULT-VALID-XT
 48 CONSTANT _SPUB-CLEANUP-ERROR-XT
 56 CONSTANT _SPUB-RELEASABLE-XT
 64 CONSTANT _SPUB-POISON-XT
 72 CONSTANT _SPUB-RELEASE-XT
 80 CONSTANT _SPUB-START-XT
 88 CONSTANT _SPUB-POLL-XT
 96 CONSTANT _SPUB-CANCEL-XT
104 CONSTANT _SPUB-WIPE-XT
112 CONSTANT STREAMS-PUBLIC-PROVIDER-SIZE

: SPUB.MAGIC             ( provider -- a ) _SPUB-MAGIC + ;
: SPUB.CONTEXT           ( provider -- a ) _SPUB-CONTEXT + ;
: SPUB.CONFIGURE-XT      ( provider -- a ) _SPUB-CONFIGURE-XT + ;
: SPUB.DECONFIGURE-XT    ( provider -- a ) _SPUB-DECONFIGURE-XT + ;
: SPUB.BODY-XT           ( provider -- a ) _SPUB-BODY-XT + ;
: SPUB.RESULT-VALID-XT   ( provider -- a ) _SPUB-RESULT-VALID-XT + ;
: SPUB.CLEANUP-ERROR-XT  ( provider -- a ) _SPUB-CLEANUP-ERROR-XT + ;
: SPUB.RELEASABLE-XT     ( provider -- a ) _SPUB-RELEASABLE-XT + ;
: SPUB.POISON-XT         ( provider -- a ) _SPUB-POISON-XT + ;
: SPUB.RELEASE-XT        ( provider -- a ) _SPUB-RELEASE-XT + ;
: SPUB.START-XT          ( provider -- a ) _SPUB-START-XT + ;
: SPUB.POLL-XT           ( provider -- a ) _SPUB-POLL-XT + ;
: SPUB.CANCEL-XT         ( provider -- a ) _SPUB-CANCEL-XT + ;
: SPUB.WIPE-XT           ( provider -- a ) _SPUB-WIPE-XT + ;

: SPUB-INIT  ( provider -- )
    STREAMS-PUBLIC-PROVIDER-SIZE 0 FILL ;

: SPUB-VALID?  ( provider -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP SPUB.MAGIC @ SPUB-MAGIC =
    OVER SPUB.CONTEXT @ 0<> AND
    OVER SPUB.CONFIGURE-XT @ 0<> AND
    OVER SPUB.DECONFIGURE-XT @ 0<> AND
    OVER SPUB.BODY-XT @ 0<> AND
    OVER SPUB.RESULT-VALID-XT @ 0<> AND
    OVER SPUB.CLEANUP-ERROR-XT @ 0<> AND
    OVER SPUB.RELEASABLE-XT @ 0<> AND
    OVER SPUB.POISON-XT @ 0<> AND
    OVER SPUB.RELEASE-XT @ 0<> AND
    OVER SPUB.START-XT @ 0<> AND
    OVER SPUB.POLL-XT @ 0<> AND
    OVER SPUB.CANCEL-XT @ 0<> AND
    SWAP SPUB.WIPE-XT @ 0<> AND ;

: SPUB-SEAL  ( provider -- status )
    DUP 0= IF DROP SPUB-S-INVALID EXIT THEN
    SPUB-MAGIC OVER SPUB.MAGIC !
    DUP SPUB-VALID? IF DROP SPUB-S-OK EXIT THEN
    SPUB-INIT SPUB-S-INVALID ;

VARIABLE _SPUB-P
VARIABLE _SPUB-A
VARIABLE _SPUB-U

: SPUB-CONFIGURE  ( actor-a actor-u provider -- status )
    _SPUB-P ! _SPUB-U ! _SPUB-A !
    _SPUB-P @ SPUB-VALID? 0= IF SPUB-S-INVALID EXIT THEN
    _SPUB-A @ _SPUB-U @ _SPUB-P @ SPUB.CONTEXT @
        _SPUB-P @ SPUB.CONFIGURE-XT @ EXECUTE ;

: SPUB-DECONFIGURE  ( provider -- status )
    DUP SPUB-VALID? 0= IF DROP SPUB-S-INVALID EXIT THEN
    DUP SPUB.CONTEXT @ SWAP SPUB.DECONFIGURE-XT @ EXECUTE ;

: SPUB-BODY@  ( provider -- body-a body-u )
    DUP SPUB-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP SPUB.CONTEXT @ SWAP SPUB.BODY-XT @ EXECUTE ;

: SPUB-RESULT-VALID?  ( provider -- flag )
    DUP SPUB-VALID? 0= IF DROP 0 EXIT THEN
    DUP SPUB.CONTEXT @ SWAP SPUB.RESULT-VALID-XT @ EXECUTE ;

: SPUB-CLEANUP-ERROR@  ( provider -- error )
    DUP SPUB-VALID? 0= IF DROP SPUB-E-INVALID EXIT THEN
    DUP SPUB.CONTEXT @ SWAP SPUB.CLEANUP-ERROR-XT @ EXECUTE ;

: SPUB-RELEASABLE?  ( provider -- flag )
    DUP SPUB-VALID? 0= IF DROP 0 EXIT THEN
    DUP SPUB.CONTEXT @ SWAP SPUB.RELEASABLE-XT @ EXECUTE ;

VARIABLE _SPUB-POISON-ERROR

: SPUB-POISON  ( error provider -- )
    DUP SPUB-VALID? 0= IF 2DROP EXIT THEN
    SWAP _SPUB-POISON-ERROR !
    DUP SPUB.CONTEXT @ SWAP SPUB.POISON-XT @
    _SPUB-POISON-ERROR @ -ROT EXECUTE ;

VARIABLE _SPUB-FREE-P
VARIABLE _SPUB-FREE-STATUS

: SPUB-FREE  ( provider -- status )
    DUP SPUB-VALID? 0= IF DROP SPUB-S-INVALID EXIT THEN
    DUP _SPUB-FREE-P !
    DUP SPUB.CONTEXT @ SWAP SPUB.RELEASE-XT @ EXECUTE
    DUP _SPUB-FREE-STATUS ! SPUB-S-OK <> IF
        _SPUB-FREE-STATUS @ EXIT
    THEN
    _SPUB-FREE-P @ DUP STREAMS-PUBLIC-PROVIDER-SIZE 0 FILL FREE
    SPUB-S-OK ;

VARIABLE _SPUB-XIO-OP
VARIABLE _SPUB-XIO-P

: _SPUB-XIO-RESULT!  ( step-status -- step-status )
    DUP XIO-STEP-SUCCEEDED = IF
        _SPUB-XIO-P @ _SPUB-XIO-OP @ XIOO.RESULT !
    THEN ;

: _SPUB-XIO-INVALID  ( -- step-status )
    SPUB-E-INVALID _SPUB-XIO-OP @ XIOO.ERROR ! XIO-STEP-FAILED ;

: SPUB-XIO-START  ( operation provider -- step-status )
    _SPUB-XIO-P ! _SPUB-XIO-OP !
    _SPUB-XIO-P @ SPUB-VALID? 0= IF _SPUB-XIO-INVALID EXIT THEN
    _SPUB-XIO-OP @ _SPUB-XIO-P @ SPUB.CONTEXT @
        _SPUB-XIO-P @ SPUB.START-XT @ EXECUTE _SPUB-XIO-RESULT! ;

: SPUB-XIO-POLL  ( operation provider -- step-status )
    _SPUB-XIO-P ! _SPUB-XIO-OP !
    _SPUB-XIO-P @ SPUB-VALID? 0= IF _SPUB-XIO-INVALID EXIT THEN
    _SPUB-XIO-OP @ _SPUB-XIO-P @ SPUB.CONTEXT @
        _SPUB-XIO-P @ SPUB.POLL-XT @ EXECUTE _SPUB-XIO-RESULT! ;

: SPUB-XIO-CANCEL  ( operation provider -- )
    _SPUB-XIO-P ! _SPUB-XIO-OP !
    _SPUB-XIO-P @ SPUB-VALID? 0= IF SPUB-E-INVALID THROW THEN
    _SPUB-XIO-OP @ _SPUB-XIO-P @ SPUB.CONTEXT @
        _SPUB-XIO-P @ SPUB.CANCEL-XT @ EXECUTE ;

: SPUB-XIO-WIPE  ( operation provider -- )
    _SPUB-XIO-P ! _SPUB-XIO-OP !
    _SPUB-XIO-P @ SPUB-VALID? 0= IF SPUB-E-INVALID THROW THEN
    _SPUB-XIO-OP @ _SPUB-XIO-P @ SPUB.CONTEXT @
        _SPUB-XIO-P @ SPUB.WIPE-XT @ EXECUTE ;
