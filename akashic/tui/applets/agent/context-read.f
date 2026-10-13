\ =====================================================================
\  context-read.f - A scheduled run reads its one document
\ =====================================================================
\  A scheduled run may name one exact version of a document as its
\  context (interop/qualified-locator.f).  Desk's broker attaches that
\  document through its owner and lends the run a resource client
\  (interop/resource-client.f) for it while the run starts; the run's
\  facet lets it describe and snapshot that document and nothing else.
\
\  ACREAD-READ reads it as the run, each request under a one-use grant
\  from the run (run-grant.f).  It describes the document and stops when
\  its current revision is not the one the locator names, or when it is
\  larger than ROOM, the bytes the run may still disclose.  It then takes
\  a snapshot of that exact version, whose digest the resource client
\  checks, and which must be UTF-8 text.  The reader holds the text
\  until ACREAD-FREE, which wipes it.
\
\  Public API:
\    ACREAD-SIZE      ( -- bytes )
\    ACREAD-INIT      ( reader -- )
\    ACREAD-READ      ( locator source run room reader -- status )
\    ACREAD-TEXT      ( reader -- a u )
\    ACREAD-TITLE     ( reader -- a u )
\    ACREAD-REVISION  ( reader -- revision )
\    ACREAD-FREE      ( reader -- )
\ =====================================================================

PROVIDED akashic-agent-context-read

REQUIRE run-grant.f
REQUIRE ../../../interop/resource-client.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../math/sha3.f

0 CONSTANT ACREAD-S-OK
1 CONSTANT ACREAD-S-UNAVAILABLE   \ no document to read, or its owner is gone
2 CONSTANT ACREAD-S-STALE         \ it is no longer the version named
3 CONSTANT ACREAD-S-DISCLOSURE    \ larger than the run may disclose
4 CONSTANT ACREAD-S-FAILED        \ the read failed, or was not text
5 CONSTANT ACREAD-S-NOMEM

 0 CONSTANT _ACR-REQUEST    \ the read's request; its result holds the text
 8 CONSTANT _ACR-TITLE-A
16 CONSTANT _ACR-TITLE-U
24 CONSTANT _ACR-REVISION
32 CONSTANT _ACR-TEXT-A
40 CONSTANT _ACR-TEXT-U
48 CONSTANT ACREAD-SIZE

: ACREAD-INIT  ( reader -- ) ACREAD-SIZE 0 FILL ;

: ACREAD-TEXT  ( reader -- a u ) DUP _ACR-TEXT-A + @ SWAP _ACR-TEXT-U + @ ;
: ACREAD-TITLE  ( reader -- a u ) DUP _ACR-TITLE-A + @ SWAP _ACR-TITLE-U + @ ;
: ACREAD-REVISION  ( reader -- revision ) _ACR-REVISION + @ ;

\ Wipes and frees what the reader holds.
: ACREAD-FREE  ( reader -- )
    DUP ACREAD-TEXT ?DUP IF 0 FILL ELSE DROP THEN
    DUP _ACR-REQUEST + @ CBR-FREE
    DUP _ACR-TITLE-A + @ ?DUP IF FREE THEN
    ACREAD-INIT ;

VARIABLE _ACRR-L  VARIABLE _ACRR-S  VARIABLE _ACRR-RUN  VARIABLE _ACRR-ROOM
VARIABLE _ACRR-R  VARIABLE _ACRR-Q

\ What a request the bus answered with STATUS means for the read.
: _ACREAD-BUS-STATUS  ( status -- read-status )
    CASE
        CBUS-S-OK OF ACREAD-S-OK ENDOF
        CBUS-S-STALE-REVISION OF ACREAD-S-STALE ENDOF
        CBUS-S-STALE-INSTANCE OF ACREAD-S-UNAVAILABLE ENDOF
        CBUS-S-NOT-FOUND OF ACREAD-S-UNAVAILABLE ENDOF
        RCLI-S-STALE OF ACREAD-S-UNAVAILABLE ENDOF
        ACREAD-S-FAILED SWAP
    ENDCASE ;

\ Readies the prepared request to go as the run: its Mandate, an
\ invocation id of its own for operation OP, and a grant.  Its arguments
\ are not sealed: a snapshot's carry a digest as bytes, which the typed
\ seal cannot encode.  Nothing can change them before the bus takes the
\ grant, as the read prepares, grants and sends each request at once,
\ and no one else holds it.
: _ACREAD-AS-RUN  ( op-a op-u -- status )
    _ACRR-RUN @ AMRUN.MANDATE MAND.ID _ACRR-Q @ CBR.MANDATE-ID RID-COPY
    SHA3-256-BEGIN
    S" akashic.agent.context-read.v1" SHA3-256-ADD
    _ACRR-RUN @ AMRUN.MANDATE MAND.ID RID-SIZE SHA3-256-ADD
    SHA3-256-ADD
    _ACRR-Q @ CBR.INVOCATION-ID SHA3-256-END
    AGR-F-MANDATE-AUTO CFENTRY-F-INVOKE CFENTRY-F-AUTO-OBSERVE OR
    _ACRR-Q @ _ACRR-RUN @ _ACRR-S @ RCLI.BUS @ AGRANT-ISSUE ;

\ The integer or the text FIELD of the request's result.
: _ACREAD-FIELD  ( key-a key-u -- value|0 ) _ACRR-Q @ CBR.RESULT CV-MAP-FIND ;

\ Describes the document: its revision must be the locator's, and its
\ size within the room.  Keeps a copy of its title.
: _ACREAD-DESCRIBE  ( -- status )
    CPRINC-AGENT _ACRR-Q @ _ACRR-S @ RCLI-DESCRIBE-PREPARE
    ?DUP IF _ACREAD-BUS-STATUS EXIT THEN
    S" resource.describe" _ACREAD-AS-RUN IF ACREAD-S-FAILED EXIT THEN
    _ACRR-Q @ _ACRR-S @ RCLI-DESCRIBE-DISPATCH
    ?DUP IF _ACREAD-BUS-STATUS EXIT THEN
    S" domain_revision" _ACREAD-FIELD CV-DATA@
    DUP _ACRR-R @ _ACR-REVISION + !
    _ACRR-L @ QLOC.DOMAIN-REVISION @ <> IF ACREAD-S-STALE EXIT THEN
    S" size" _ACREAD-FIELD CV-DATA@ _ACRR-ROOM @ > IF
        ACREAD-S-DISCLOSURE EXIT
    THEN
    S" title" _ACREAD-FIELD DUP CV-DATA@ SWAP CV-LEN@
    DUP 1 MAX ALLOCATE IF DROP 2DROP ACREAD-S-NOMEM EXIT THEN
    DUP _ACRR-R @ _ACR-TITLE-A + ! OVER _ACRR-R @ _ACR-TITLE-U + !
    SWAP MOVE
    ACREAD-S-OK ;

\ Takes a snapshot of the exact version: text within the room.
: _ACREAD-SNAPSHOT  ( -- status )
    _ACRR-L @ CPRINC-AGENT _ACRR-Q @ _ACRR-S @ RCLI-SNAPSHOT-PREPARE
    ?DUP IF _ACREAD-BUS-STATUS EXIT THEN
    S" resource.snapshot" _ACREAD-AS-RUN IF ACREAD-S-FAILED EXIT THEN
    _ACRR-L @ _ACRR-Q @ _ACRR-S @ RCLI-SNAPSHOT-DISPATCH
    ?DUP IF _ACREAD-BUS-STATUS EXIT THEN
    S" content" _ACREAD-FIELD DUP CV-DATA@ SWAP CV-LEN@
    DUP _ACRR-ROOM @ > IF 2DROP ACREAD-S-DISCLOSURE EXIT THEN
    2DUP UTF8-VALID? 0= IF 2DROP ACREAD-S-FAILED EXIT THEN
    _ACRR-R @ _ACR-TEXT-U + ! _ACRR-R @ _ACR-TEXT-A + !
    ACREAD-S-OK ;

\ Reads the document LOCATOR names, exactly that version, through SOURCE
\ as RUN, if it takes no more than ROOM bytes.  The reader is filled only
\ as far as the read got: ACREAD-FREE it either way.
: ACREAD-READ  ( locator source run room reader -- status )
    DUP ACREAD-INIT
    _ACRR-R ! _ACRR-ROOM ! _ACRR-RUN ! _ACRR-S ! _ACRR-L !
    _ACRR-L @ QLOC-VALID? 0= IF ACREAD-S-FAILED EXIT THEN
    _ACRR-L @ QLOC.MODE @ QLOC-M-EXACT-DOMAIN <> IF ACREAD-S-FAILED EXIT THEN
    _ACRR-S @ RCLI-VALID? 0= IF ACREAD-S-UNAVAILABLE EXIT THEN
    _ACRR-RUN @ AMRUN-ACTIVE? 0= IF ACREAD-S-FAILED EXIT THEN
    CBR-NEW IF DROP ACREAD-S-NOMEM EXIT THEN
    DUP _ACRR-Q ! _ACRR-R @ _ACR-REQUEST + !
    _ACREAD-DESCRIBE ?DUP IF EXIT THEN
    _ACREAD-SNAPSHOT ;
