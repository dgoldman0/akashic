\ =====================================================================
\ authenticated-provider.f - transport-neutral authenticated Streams seam
\ =====================================================================
\ Streams owns this closed interface.  A concrete account composition owns
\ CONTEXT and implements authenticated feed refresh, state presentation, and
\ text-post delivery without moving OAuth, PDS, XRPC, transport, clock, or
\ receipt policy into the ordinary applet dependency graph.
\
\ A factory has stack effect ( vfs xio-service -- provider status ).  It may
\ bind an already-authenticated account but must not start external work.
\ Success returns a heap-allocated, sealed provider and SAUTH-S-OK.  Ordinary
\ failure returns zero after cleaning every partial allocation.  If cleanup
\ cannot detach a post-bind resource, failure instead returns a valid sealed
\ provider with SAUTH-S-CLEANUP; the caller owns it and must retry CANCEL and
\ RELEASE.  After sealing, the provider owns CONTEXT.  SAUTH-RELEASE frees the
\ descriptor only after the context release callback returns SAUTH-S-OK.
\
\ SOURCE-BUILD writes one complete pointer-free candidate into caller storage;
\ it does not retain that candidate or make it current.  Persisted endpoint
\ and config text may identify the actor and an opaque account binding, but
\ must never contain tokens, live pointers, or a discovered PDS URL.  SOURCE@
\ returns only the exact source revision retained by REFRESH or PUBLISH.
\
\ ACCOUNT$, SOURCE@, URI$, and CID$ return borrowed context storage.  Returned
\ strings and records remain valid until the next SOURCE-BUILD, REFRESH,
\ PUBLISH, TICK, CANCEL, or RELEASE operation on that provider.
\
\ REFRESH and PUBLISH must copy the complete source record synchronously and
\ must not retain caller registry storage.  PUBLISH must likewise synchronously
\ admit or copy exactly text-a/text-u before returning SAUTH-S-OK; it must not
\ retain the caller's mutable draft buffer.  SAUTH-S-OK therefore means those
\ exact source, instance, and text inputs own the newly accepted operation.
\ TICK and CANCEL return changed? true whenever STATE, LAST-STATUS, ERROR,
\ SOURCE@, URI$, CID$, or releasability changed, including terminal error and
\ cleanup transitions.  False promises that every observable remains equal.
\
\ Callback stack effects:
\   ACCOUNT-XT           ( context -- account-a account-u )
\   SOURCE-BUILD-XT      ( actor-a actor-u source context -- status )
\   SOURCE-SUPPORTED-XT  ( source context -- flag )
\   SOURCE-XT            ( context -- source|0 )
\   REFRESH-XT           ( source instance context -- status )
\   PUBLISH-XT
\     ( text-a text-u source instance context -- status )
\   TICK-XT              ( instance context -- changed? status )
\   CANCEL-XT            ( instance context -- changed? status )
\   STATE-XT             ( context -- state )
\   LAST-STATUS-XT       ( context -- status )
\   ERROR-XT             ( context -- error )
\   URI-XT               ( context -- uri-a uri-u )
\   CID-XT               ( context -- cid-a cid-u )
\   RELEASABLE-XT        ( context -- flag )
\   RELEASE-XT           ( context -- status )
\ =====================================================================

\ Keep the module identity within KDOS's 23-byte bound.
PROVIDED akashic-streams-sauth

\ Closed provider statuses.  Concrete compositions translate their private
\ domains into this set before returning through a callback.
0  CONSTANT SAUTH-S-OK
1  CONSTANT SAUTH-S-INVALID
2  CONSTANT SAUTH-S-UNAVAILABLE
3  CONSTANT SAUTH-S-BUSY
4  CONSTANT SAUTH-S-CAPACITY
5  CONSTANT SAUTH-S-STATE
6  CONSTANT SAUTH-S-FEED
7  CONSTANT SAUTH-S-POST
8  CONSTANT SAUTH-S-CLEANUP
9  CONSTANT SAUTH-S-INDETERMINATE
10 CONSTANT SAUTH-S-CANCELLED

\ Closed account-operation states.  FEED-READY retains a presented feed;
\ terminal post states retain their result until the next provider operation.
0  CONSTANT SAUTH-STATE-OFFLINE
1  CONSTANT SAUTH-STATE-IDLE
2  CONSTANT SAUTH-STATE-FEED-ACTIVE
3  CONSTANT SAUTH-STATE-FEED-READY
4  CONSTANT SAUTH-STATE-POST-ACTIVE
5  CONSTANT SAUTH-STATE-POST-DELIVERED
6  CONSTANT SAUTH-STATE-POST-NO-EFFECT
7  CONSTANT SAUTH-STATE-POST-UNCERTAIN
8  CONSTANT SAUTH-STATE-FAILED
9  CONSTANT SAUTH-STATE-CANCELLED
10 CONSTANT SAUTH-STATE-CLEANUP

-4804 CONSTANT SAUTH-E-INVALID

0x5341555448505231 CONSTANT SAUTH-MAGIC  \ "SAUTHPR1"

  0 CONSTANT _SAUTH-MAGIC
  8 CONSTANT _SAUTH-CONTEXT
 16 CONSTANT _SAUTH-ACCOUNT-XT
 24 CONSTANT _SAUTH-SOURCE-BUILD-XT
 32 CONSTANT _SAUTH-SOURCE-SUPPORTED-XT
 40 CONSTANT _SAUTH-SOURCE-XT
 48 CONSTANT _SAUTH-REFRESH-XT
 56 CONSTANT _SAUTH-PUBLISH-XT
 64 CONSTANT _SAUTH-TICK-XT
 72 CONSTANT _SAUTH-CANCEL-XT
 80 CONSTANT _SAUTH-STATE-XT
 88 CONSTANT _SAUTH-LAST-STATUS-XT
 96 CONSTANT _SAUTH-ERROR-XT
104 CONSTANT _SAUTH-URI-XT
112 CONSTANT _SAUTH-CID-XT
120 CONSTANT _SAUTH-RELEASABLE-XT
128 CONSTANT _SAUTH-RELEASE-XT
136 CONSTANT SAUTH-PROVIDER-SIZE

: SAUTH.MAGIC                ( provider -- a ) _SAUTH-MAGIC + ;
: SAUTH.CONTEXT              ( provider -- a ) _SAUTH-CONTEXT + ;
: SAUTH.ACCOUNT-XT           ( provider -- a ) _SAUTH-ACCOUNT-XT + ;
: SAUTH.SOURCE-BUILD-XT      ( provider -- a ) _SAUTH-SOURCE-BUILD-XT + ;
: SAUTH.SOURCE-SUPPORTED-XT  ( provider -- a ) _SAUTH-SOURCE-SUPPORTED-XT + ;
: SAUTH.SOURCE-XT            ( provider -- a ) _SAUTH-SOURCE-XT + ;
: SAUTH.REFRESH-XT           ( provider -- a ) _SAUTH-REFRESH-XT + ;
: SAUTH.PUBLISH-XT           ( provider -- a ) _SAUTH-PUBLISH-XT + ;
: SAUTH.TICK-XT              ( provider -- a ) _SAUTH-TICK-XT + ;
: SAUTH.CANCEL-XT            ( provider -- a ) _SAUTH-CANCEL-XT + ;
: SAUTH.STATE-XT             ( provider -- a ) _SAUTH-STATE-XT + ;
: SAUTH.LAST-STATUS-XT       ( provider -- a ) _SAUTH-LAST-STATUS-XT + ;
: SAUTH.ERROR-XT             ( provider -- a ) _SAUTH-ERROR-XT + ;
: SAUTH.URI-XT               ( provider -- a ) _SAUTH-URI-XT + ;
: SAUTH.CID-XT               ( provider -- a ) _SAUTH-CID-XT + ;
: SAUTH.RELEASABLE-XT        ( provider -- a ) _SAUTH-RELEASABLE-XT + ;
: SAUTH.RELEASE-XT           ( provider -- a ) _SAUTH-RELEASE-XT + ;

: SAUTH-INIT  ( provider -- )
    DUP 0<> IF SAUTH-PROVIDER-SIZE 0 FILL ELSE DROP THEN ;

: SAUTH-VALID?  ( provider -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP SAUTH.MAGIC @ SAUTH-MAGIC =
    OVER SAUTH.CONTEXT @ 0<> AND
    OVER SAUTH.ACCOUNT-XT @ 0<> AND
    OVER SAUTH.SOURCE-BUILD-XT @ 0<> AND
    OVER SAUTH.SOURCE-SUPPORTED-XT @ 0<> AND
    OVER SAUTH.SOURCE-XT @ 0<> AND
    OVER SAUTH.REFRESH-XT @ 0<> AND
    OVER SAUTH.PUBLISH-XT @ 0<> AND
    OVER SAUTH.TICK-XT @ 0<> AND
    OVER SAUTH.CANCEL-XT @ 0<> AND
    OVER SAUTH.STATE-XT @ 0<> AND
    OVER SAUTH.LAST-STATUS-XT @ 0<> AND
    OVER SAUTH.ERROR-XT @ 0<> AND
    OVER SAUTH.URI-XT @ 0<> AND
    OVER SAUTH.CID-XT @ 0<> AND
    OVER SAUTH.RELEASABLE-XT @ 0<> AND
    SWAP SAUTH.RELEASE-XT @ 0<> AND ;

: SAUTH-SEAL  ( provider -- status )
    DUP 0= IF DROP SAUTH-S-INVALID EXIT THEN
    SAUTH-MAGIC OVER SAUTH.MAGIC !
    DUP SAUTH-VALID? IF DROP SAUTH-S-OK EXIT THEN
    SAUTH-INIT SAUTH-S-INVALID ;

: SAUTH-ACCOUNT$  ( provider -- account-a account-u )
    DUP SAUTH-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.ACCOUNT-XT @ EXECUTE ;

: SAUTH-SOURCE-BUILD  ( actor-a actor-u source provider -- status )
    DUP SAUTH-VALID? 0= IF 2DROP 2DROP SAUTH-S-INVALID EXIT THEN
    OVER 0= IF 2DROP 2DROP SAUTH-S-INVALID EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.SOURCE-BUILD-XT @ EXECUTE ;

: SAUTH-SOURCE-SUPPORTED?  ( source provider -- flag )
    DUP SAUTH-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.SOURCE-SUPPORTED-XT @ EXECUTE ;

: SAUTH-SOURCE@  ( provider -- source|0 )
    DUP SAUTH-VALID? 0= IF DROP 0 EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.SOURCE-XT @ EXECUTE ;

: SAUTH-REFRESH  ( source instance provider -- status )
    DUP SAUTH-VALID? 0= IF 2DROP DROP SAUTH-S-INVALID EXIT THEN
    OVER 0= 2 PICK 0= OR IF 2DROP DROP SAUTH-S-INVALID EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.REFRESH-XT @ EXECUTE ;

: SAUTH-PUBLISH  ( text-a text-u source instance provider -- status )
    DUP SAUTH-VALID? 0= IF 2DROP 2DROP DROP SAUTH-S-INVALID EXIT THEN
    OVER 0= 2 PICK 0= OR IF
        2DROP 2DROP DROP SAUTH-S-INVALID EXIT
    THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.PUBLISH-XT @ EXECUTE ;

: SAUTH-TICK  ( instance provider -- changed? status )
    DUP SAUTH-VALID? 0= IF 2DROP 0 SAUTH-S-INVALID EXIT THEN
    OVER 0= IF 2DROP 0 SAUTH-S-INVALID EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.TICK-XT @ EXECUTE ;

: SAUTH-CANCEL  ( instance provider -- changed? status )
    DUP SAUTH-VALID? 0= IF 2DROP 0 SAUTH-S-INVALID EXIT THEN
    OVER 0= IF 2DROP 0 SAUTH-S-INVALID EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.CANCEL-XT @ EXECUTE ;

: SAUTH-STATE@  ( provider -- state )
    DUP SAUTH-VALID? 0= IF DROP SAUTH-STATE-OFFLINE EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.STATE-XT @ EXECUTE ;

: SAUTH-LAST-STATUS@  ( provider -- status )
    DUP SAUTH-VALID? 0= IF DROP SAUTH-S-INVALID EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.LAST-STATUS-XT @ EXECUTE ;

: SAUTH-ERROR@  ( provider -- error )
    DUP SAUTH-VALID? 0= IF DROP SAUTH-E-INVALID EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.ERROR-XT @ EXECUTE ;

: SAUTH-URI$  ( provider -- uri-a uri-u )
    DUP SAUTH-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.URI-XT @ EXECUTE ;

: SAUTH-CID$  ( provider -- cid-a cid-u )
    DUP SAUTH-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.CID-XT @ EXECUTE ;

: SAUTH-RELEASABLE?  ( provider -- flag )
    DUP SAUTH-VALID? 0= IF DROP 0 EXIT THEN
    DUP SAUTH.CONTEXT @ SWAP SAUTH.RELEASABLE-XT @ EXECUTE ;

: SAUTH-RELEASE  ( provider -- status )
    DUP SAUTH-VALID? 0= IF DROP SAUTH-S-INVALID EXIT THEN
    DUP >R
    DUP SAUTH.CONTEXT @ SWAP SAUTH.RELEASE-XT @ EXECUTE
    DUP SAUTH-S-OK <> IF
        R> DROP EXIT
    THEN
    DROP R> DUP SAUTH-PROVIDER-SIZE 0 FILL FREE
    SAUTH-S-OK ;
