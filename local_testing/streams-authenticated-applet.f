\ Focused contracts for the transport-neutral authenticated Streams applet.
\
\ The fake account provider is sealed through the production SAUTH interface
\ and owns one heap context per app instance.  It performs no transport work:
\ a feed tick crosses Streams' checked authenticated-load boundary, while post
\ ticks select deterministic delivered, no-effect, and uncertain outcomes.
\ The real Streams app descriptor, lifecycle callbacks, durable source owner,
\ draft owner, status projection, close negotiation, and relaunch path remain
\ in the test.

PROVIDED streams-auth-app-test

\ ---------------------------------------------------------------------
\ Test bookkeeping and boot document
\ ---------------------------------------------------------------------

VARIABLE _satc-fails
VARIABLE _satc-checks
VARIABLE _satc-depth
VARIABLE _satc-old-vfs
VARIABLE _satc-vfs
VARIABLE _satc-instance
VARIABLE _satc-account-element
VARIABLE _satc-document-a
VARIABLE _satc-document-u
VARIABLE _satc-document-fd
VARIABLE _satc-instance-heap

VARIABLE _satc-factory-count
VARIABLE _satc-live-contexts
VARIABLE _satc-release-count

CREATE _satc-app APP-DESC ALLOT
CREATE _satc-rid-a RID-SIZE ALLOT
CREATE _satc-rid-b RID-SIZE ALLOT
CREATE _satc-stale STREAMS-SOURCE-SIZE ALLOT
CREATE _satc-replacement STREAMS-SOURCE-SIZE ALLOT
CREATE _satc-expected-text-hash RID-SIZE ALLOT

: _satc-assert  ( flag -- )
    1 _satc-checks +!
    0= IF
        1 _satc-fails +!
        ." STREAMS AUTH APPLET ASSERT " _satc-checks @ . CR
    THEN ;

: _satc-stack  ( -- )
    DEPTH DUP _satc-depth @ <> IF
        ." STREAMS AUTH APPLET STACK " _satc-depth @ . ."  -> " DUP . CR
        .S CR
    THEN
    _satc-depth @ = _satc-assert ;

: _satc-account-visible?  ( expected-a expected-u -- flag )
    _satc-account-element @ S" text" UIDL-ATTR 0= IF
        2DROP 2DROP 0 EXIT
    THEN
    2SWAP STR-STR= ;

: _SATC-LOAD  ( -- )
    0 _satc-fails ! 0 _satc-checks ! DEPTH _satc-depth !
    0 _satc-factory-count ! 0 _satc-live-contexts !
    0 _satc-release-count !
    NAMEBUF 24 0 FILL
    S" saa-feed.json" NAMEBUF SWAP CMOVE
    FIND-BY-NAME DUP -1 =
        ABORT" STREAMS AUTH APPLET feed fixture missing"
    OPEN-BY-SLOT DUP 0=
        ABORT" STREAMS AUTH APPLET feed fixture open failed"
    DUP _satc-document-fd !
    FSIZE DUP 0=
        ABORT" STREAMS AUTH APPLET feed fixture empty"
    DUP _satc-document-u !
    ALLOCATE ABORT" STREAMS AUTH APPLET feed allocation failed"
    DUP _satc-document-a !
    _satc-document-u @ _satc-document-fd @ FREAD
    _satc-document-u @ <>
        ABORT" STREAMS AUTH APPLET feed fixture read failed"
    _satc-document-fd @ FCLOSE 0 _satc-document-fd !
    _satc-stack ;

\ ---------------------------------------------------------------------
\ Sealed per-instance fake provider
\ ---------------------------------------------------------------------

0x5341544343545831 CONSTANT _SATC-CONTEXT-MAGIC

   0 CONSTANT _SATC-C-MAGIC
   8 CONSTANT _SATC-C-SERIAL
  16 CONSTANT _SATC-C-STATE
  24 CONSTANT _SATC-C-STATUS
  32 CONSTANT _SATC-C-ERROR
  40 CONSTANT _SATC-C-OUTCOME
  48 CONSTANT _SATC-C-SEQUENCE
  56 CONSTANT _SATC-C-BUILD-COUNT
  64 CONSTANT _SATC-C-REFRESH-COUNT
  72 CONSTANT _SATC-C-PUBLISH-COUNT
  80 CONSTANT _SATC-C-CANCEL-COUNT
  88 CONSTANT _SATC-C-OP-INSTANCE
  96 CONSTANT _SATC-C-HAS-SOURCE
 104 CONSTANT _SATC-C-SOURCE
_SATC-C-SOURCE STREAMS-SOURCE-SIZE + CONSTANT _SATC-C-URI-U
_SATC-C-URI-U 8 + CONSTANT _SATC-C-URI
192 CONSTANT _SATC-RECEIPT-CAP
_SATC-C-URI _SATC-RECEIPT-CAP + CONSTANT _SATC-C-CID-U
_SATC-C-CID-U 8 + CONSTANT _SATC-C-CID
_SATC-C-CID _SATC-RECEIPT-CAP + CONSTANT _SATC-C-TEXT-HASH
_SATC-C-TEXT-HASH RID-SIZE + CONSTANT _SATC-CONTEXT-SIZE

0 CONSTANT _SATC-OUTCOME-DELIVERED
1 CONSTANT _SATC-OUTCOME-NO-EFFECT
2 CONSTANT _SATC-OUTCOME-UNCERTAIN

: _satc-c.magic          ( context -- a ) _SATC-C-MAGIC + ;
: _satc-c.serial         ( context -- a ) _SATC-C-SERIAL + ;
: _satc-c.state          ( context -- a ) _SATC-C-STATE + ;
: _satc-c.status         ( context -- a ) _SATC-C-STATUS + ;
: _satc-c.error          ( context -- a ) _SATC-C-ERROR + ;
: _satc-c.outcome        ( context -- a ) _SATC-C-OUTCOME + ;
: _satc-c.sequence       ( context -- a ) _SATC-C-SEQUENCE + ;
: _satc-c.build-count    ( context -- a ) _SATC-C-BUILD-COUNT + ;
: _satc-c.refresh-count  ( context -- a ) _SATC-C-REFRESH-COUNT + ;
: _satc-c.publish-count  ( context -- a ) _SATC-C-PUBLISH-COUNT + ;
: _satc-c.cancel-count   ( context -- a ) _SATC-C-CANCEL-COUNT + ;
: _satc-c.op-instance    ( context -- a ) _SATC-C-OP-INSTANCE + ;
: _satc-c.has-source     ( context -- a ) _SATC-C-HAS-SOURCE + ;
: _satc-c.source         ( context -- source ) _SATC-C-SOURCE + ;
: _satc-c.uri-u          ( context -- a ) _SATC-C-URI-U + ;
: _satc-c.uri            ( context -- a ) _SATC-C-URI + ;
: _satc-c.cid-u          ( context -- a ) _SATC-C-CID-U + ;
: _satc-c.cid            ( context -- a ) _SATC-C-CID + ;
: _satc-c.text-hash      ( context -- a ) _SATC-C-TEXT-HASH + ;

: _satc-context-valid?  ( context -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    _satc-c.magic @ _SATC-CONTEXT-MAGIC = ;

: _satc-context-active?  ( context -- flag )
    _satc-c.state @ DUP SAUTH-STATE-FEED-ACTIVE =
    SWAP SAUTH-STATE-POST-ACTIVE = OR ;

: _satc-context-releasable?  ( context -- flag )
    DUP _satc-context-valid? 0= IF DROP 0 EXIT THEN
    _satc-context-active? 0= ;

: _satc-receipt-wipe  ( context -- )
    0 OVER _satc-c.uri-u !
    DUP _satc-c.uri _SATC-RECEIPT-CAP 0 FILL
    0 OVER _satc-c.cid-u !
    DUP _satc-c.cid _SATC-RECEIPT-CAP 0 FILL
    DROP ;

VARIABLE _satc-source-check

: _satc-source-binding?  ( source -- flag )
    DUP 0= IF DROP 0 EXIT THEN _satc-source-check !
    _satc-source-check @ SSOURCE.KIND @
        SSOURCE-KIND-ATPROTO-AUTHENTICATED <> IF 0 EXIT THEN
    _satc-source-check @ SSOURCE.FORMAT @
        SSOURCE-FORMAT-ATPROTO-JSON <> IF 0 EXIT THEN
    _satc-source-check @ SSOURCE.FLAGS @ SSOURCE-F-ENABLED AND
        0= IF 0 EXIT THEN
    _satc-source-check @ STREAMS-SOURCE-CONFIG$
        S" account=acct-main" STR-STR= 0= IF 0 EXIT THEN
    _satc-source-check @ STREAMS-SOURCE-ENDPOINT$
        SWAP 0<> SWAP 0> AND ;

VARIABLE _satc-current-source
VARIABLE _satc-current-instance
VARIABLE _satc-current-found

: _satc-source-current?  ( source instance -- flag )
    _satc-current-instance ! _satc-current-source !
    _satc-current-instance @ 0= IF 0 EXIT THEN
    _satc-current-source @ _satc-source-binding? 0= IF 0 EXIT THEN
    _satc-current-instance @ _STM-ACTIVATE
    _satc-current-source @ SSOURCE.ID
        _STM-SOURCE-REGISTRY STREAMS-SOURCE-FIND
    DUP _satc-current-found ! 0= IF 0 EXIT THEN
    _satc-current-found @ SSOURCE.ID
        _satc-current-source @ SSOURCE.ID RID=
    _satc-current-found @ SSOURCE.REVISION @
        _satc-current-source @ SSOURCE.REVISION @ = AND ;

VARIABLE _satc-build-actor-a
VARIABLE _satc-build-actor-u
VARIABLE _satc-build-source
VARIABLE _satc-build-context

: _satc-fake-account$  ( context -- account-a account-u )
    _satc-context-valid? 0= IF 0 0 EXIT THEN
    S" @acct-main.test" ;

: _satc-fake-source-build  ( actor-a actor-u source context -- status )
    _satc-build-context ! _satc-build-source !
    _satc-build-actor-u ! _satc-build-actor-a !
    _satc-build-context @ _satc-context-valid? 0= IF
        SAUTH-S-INVALID EXIT
    THEN
    _satc-build-source @ 0= IF SAUTH-S-INVALID EXIT THEN
    _satc-build-actor-u @ DUP 1 <
        SWAP STREAMS-SOURCE-ENDPOINT-MAX > OR IF
        SAUTH-S-INVALID EXIT
    THEN
    _satc-build-actor-a @ _satc-build-actor-u @ UTF8-VALID? 0= IF
        SAUTH-S-INVALID EXIT
    THEN
    _satc-build-source @ STREAMS-SOURCE-INIT
    SSOURCE-KIND-ATPROTO-AUTHENTICATED
        _satc-build-source @ SSOURCE.KIND !
    SSOURCE-FORMAT-ATPROTO-JSON _satc-build-source @ SSOURCE.FORMAT !
    S" Authenticated AT" _satc-build-source @ STREAMS-SOURCE-LABEL!
        SSREG-S-OK <> IF SAUTH-S-INVALID EXIT THEN
    _satc-build-actor-a @ _satc-build-actor-u @
        _satc-build-source @ STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK <> IF SAUTH-S-INVALID EXIT THEN
    S" account=acct-main" _satc-build-source @ STREAMS-SOURCE-CONFIG!
        SSREG-S-OK <> IF SAUTH-S-INVALID EXIT THEN
    1 _satc-build-context @ _satc-c.build-count +!
    SAUTH-S-OK ;

: _satc-fake-source-supported?  ( source context -- flag )
    DUP _satc-context-valid? 0= IF 2DROP 0 EXIT THEN
    DROP _satc-source-binding? ;

: _satc-fake-source@  ( context -- source|0 )
    DUP _satc-context-valid? 0= IF DROP 0 EXIT THEN
    DUP _satc-c.has-source @ 0= IF DROP 0 EXIT THEN
    _satc-c.source ;

VARIABLE _satc-refresh-source
VARIABLE _satc-refresh-instance
VARIABLE _satc-refresh-context

: _satc-fake-refresh  ( source instance context -- status )
    _satc-refresh-context ! _satc-refresh-instance !
    _satc-refresh-source !
    _satc-refresh-context @ _satc-context-valid? 0= IF
        SAUTH-S-INVALID EXIT
    THEN
    _satc-refresh-source @ _satc-refresh-context @
        _satc-fake-source-supported? 0= IF SAUTH-S-INVALID EXIT THEN
    _satc-refresh-source @ _satc-refresh-instance @
        _satc-source-current? 0= IF SAUTH-S-INVALID EXIT THEN
    _satc-refresh-context @ _satc-context-active? IF
        SAUTH-S-BUSY EXIT
    THEN
    _satc-refresh-source @ _satc-refresh-context @ _satc-c.source
        STREAMS-SOURCE-SIZE CMOVE
    -1 _satc-refresh-context @ _satc-c.has-source !
    _satc-refresh-instance @
        _satc-refresh-context @ _satc-c.op-instance !
    SAUTH-STATE-FEED-ACTIVE
        _satc-refresh-context @ _satc-c.state !
    SAUTH-S-OK _satc-refresh-context @ _satc-c.status !
    0 _satc-refresh-context @ _satc-c.error !
    1 _satc-refresh-context @ _satc-c.refresh-count +!
    SAUTH-S-OK ;

VARIABLE _satc-publish-a
VARIABLE _satc-publish-u
VARIABLE _satc-publish-source
VARIABLE _satc-publish-instance
VARIABLE _satc-publish-context

: _satc-retained-source-exact?  ( source context -- flag )
    _satc-publish-context ! _satc-publish-source !
    _satc-publish-context @ _satc-c.has-source @ 0= IF 0 EXIT THEN
    _satc-publish-source @ SSOURCE.ID
        _satc-publish-context @ _satc-c.source SSOURCE.ID RID=
    _satc-publish-source @ SSOURCE.REVISION @
        _satc-publish-context @ _satc-c.source SSOURCE.REVISION @ = AND ;

: _satc-fake-publish
  ( text-a text-u source instance context -- status )
    _satc-publish-context ! _satc-publish-instance !
    _satc-publish-source ! _satc-publish-u ! _satc-publish-a !
    _satc-publish-context @ _satc-context-valid? 0= IF
        SAUTH-S-INVALID EXIT
    THEN
    _satc-publish-u @ DUP 1 < SWAP _STM-DRAFT-CAP > OR IF
        SAUTH-S-INVALID EXIT
    THEN
    _satc-publish-a @ _satc-publish-u @ UTF8-VALID? 0= IF
        SAUTH-S-INVALID EXIT
    THEN
    _satc-publish-source @ _satc-publish-instance @
        _satc-source-current? 0= IF SAUTH-S-INVALID EXIT THEN
    _satc-publish-source @ _satc-publish-context @
        _satc-retained-source-exact? 0= IF SAUTH-S-INVALID EXIT THEN
    _satc-publish-context @ _satc-context-active? IF
        SAUTH-S-BUSY EXIT
    THEN
    _satc-publish-a @ _satc-publish-u @
        _satc-publish-context @ _satc-c.text-hash SHA3-256-HASH
    _satc-publish-context @ _satc-receipt-wipe
    _satc-publish-instance @
        _satc-publish-context @ _satc-c.op-instance !
    SAUTH-STATE-POST-ACTIVE _satc-publish-context @ _satc-c.state !
    SAUTH-S-OK _satc-publish-context @ _satc-c.status !
    0 _satc-publish-context @ _satc-c.error !
    1 _satc-publish-context @ _satc-c.publish-count +!
    SAUTH-S-OK ;

VARIABLE _satc-tick-instance
VARIABLE _satc-tick-context
VARIABLE _satc-tick-status

: _satc-feed-tick  ( -- changed? status )
    _satc-tick-context @ _satc-c.source _satc-tick-instance @
        STREAMS-AUTH-SOURCE-ADMISSIBLE? 0= IF
        SAUTH-STATE-FAILED _satc-tick-context @ _satc-c.state !
        SAUTH-S-INVALID _satc-tick-context @ _satc-c.status !
        SAUTH-S-INVALID _satc-tick-context @ _satc-c.error !
        0 _satc-tick-context @ _satc-c.op-instance !
        -1 SAUTH-S-INVALID EXIT
    THEN
    1 _satc-tick-context @ _satc-c.sequence +!
    _satc-document-a @ _satc-document-u @
    _satc-tick-context @ _satc-c.source SSOURCE.ID
    _satc-tick-context @ _satc-c.source SSOURCE.REVISION @
    _satc-tick-context @ _satc-c.sequence @
    _satc-tick-instance @ _STM-LOAD-AUTHOR-FEED-JSON
    DUP _satc-tick-status ! BFM-S-OK = IF
        SAUTH-STATE-FEED-READY _satc-tick-context @ _satc-c.state !
        SAUTH-S-OK _satc-tick-context @ _satc-c.status !
        0 _satc-tick-context @ _satc-c.error !
        0 _satc-tick-context @ _satc-c.op-instance !
        -1 SAUTH-S-OK EXIT
    THEN
    SAUTH-STATE-FAILED _satc-tick-context @ _satc-c.state !
    SAUTH-S-FEED _satc-tick-context @ _satc-c.status !
    _satc-tick-status @ _satc-tick-context @ _satc-c.error !
    0 _satc-tick-context @ _satc-c.op-instance !
    -1 SAUTH-S-FEED ;

: _satc-delivered-receipt!  ( context -- )
    DUP _satc-receipt-wipe _satc-tick-context !
    S" at://did:plc:bob/app.bsky.feed.post/3satcdelivered"
        DUP _satc-tick-context @ _satc-c.uri-u !
        _satc-tick-context @ _satc-c.uri SWAP CMOVE
    S" bafyreig-streams-authenticated-applet"
        DUP _satc-tick-context @ _satc-c.cid-u !
        _satc-tick-context @ _satc-c.cid SWAP CMOVE ;

: _satc-post-tick  ( -- changed? status )
    _satc-tick-context @ _satc-c.outcome @ CASE
        _SATC-OUTCOME-DELIVERED OF
            _satc-tick-context @ _satc-delivered-receipt!
            SAUTH-STATE-POST-DELIVERED
                _satc-tick-context @ _satc-c.state !
            SAUTH-S-OK _satc-tick-context @ _satc-c.status !
        ENDOF
        _SATC-OUTCOME-NO-EFFECT OF
            _satc-tick-context @ _satc-receipt-wipe
            SAUTH-STATE-POST-NO-EFFECT
                _satc-tick-context @ _satc-c.state !
            SAUTH-S-OK _satc-tick-context @ _satc-c.status !
        ENDOF
        _SATC-OUTCOME-UNCERTAIN OF
            _satc-tick-context @ _satc-receipt-wipe
            SAUTH-STATE-POST-UNCERTAIN
                _satc-tick-context @ _satc-c.state !
            SAUTH-S-INDETERMINATE _satc-tick-context @ _satc-c.status !
        ENDOF
        _satc-tick-context @ _satc-receipt-wipe
        SAUTH-STATE-FAILED _satc-tick-context @ _satc-c.state !
        SAUTH-S-POST _satc-tick-context @ _satc-c.status !
    ENDCASE
    0 _satc-tick-context @ _satc-c.op-instance !
    -1 _satc-tick-context @ _satc-c.status @ ;

: _satc-fake-tick  ( instance context -- changed? status )
    _satc-tick-context ! _satc-tick-instance !
    _satc-tick-context @ _satc-context-valid? 0= IF
        0 SAUTH-S-INVALID EXIT
    THEN
    _satc-tick-context @ _satc-context-active? IF
        _satc-tick-context @ _satc-c.op-instance @
            _satc-tick-instance @ <> IF 0 SAUTH-S-INVALID EXIT THEN
    THEN
    _satc-tick-context @ _satc-c.state @
        SAUTH-STATE-FEED-ACTIVE = IF _satc-feed-tick EXIT THEN
    _satc-tick-context @ _satc-c.state @
        SAUTH-STATE-POST-ACTIVE = IF _satc-post-tick EXIT THEN
    0 SAUTH-S-OK ;

VARIABLE _satc-cancel-instance
VARIABLE _satc-cancel-context

: _satc-fake-cancel  ( instance context -- changed? status )
    _satc-cancel-context ! _satc-cancel-instance !
    _satc-cancel-context @ _satc-context-valid? 0= IF
        0 SAUTH-S-INVALID EXIT
    THEN
    _satc-cancel-context @ _satc-context-active? 0= IF
        0 SAUTH-S-OK EXIT
    THEN
    _satc-cancel-context @ _satc-c.op-instance @
        _satc-cancel-instance @ <> IF 0 SAUTH-S-INVALID EXIT THEN
    _satc-cancel-context @ _satc-receipt-wipe
    SAUTH-STATE-CANCELLED _satc-cancel-context @ _satc-c.state !
    SAUTH-S-CANCELLED _satc-cancel-context @ _satc-c.status !
    0 _satc-cancel-context @ _satc-c.op-instance !
    1 _satc-cancel-context @ _satc-c.cancel-count +!
    -1 SAUTH-S-CANCELLED ;

: _satc-fake-state@  ( context -- state ) _satc-c.state @ ;
: _satc-fake-status@  ( context -- status ) _satc-c.status @ ;
: _satc-fake-error@  ( context -- error ) _satc-c.error @ ;

: _satc-fake-uri$  ( context -- uri-a uri-u )
    DUP _satc-c.uri SWAP _satc-c.uri-u @ ;

: _satc-fake-cid$  ( context -- cid-a cid-u )
    DUP _satc-c.cid SWAP _satc-c.cid-u @ ;

: _satc-fake-release  ( context -- status )
    DUP _satc-context-valid? 0= IF DROP SAUTH-S-INVALID EXIT THEN
    DUP _satc-context-releasable? 0= IF DROP SAUTH-S-CLEANUP EXIT THEN
    DUP _SATC-CONTEXT-SIZE 0 FILL FREE
    -1 _satc-live-contexts +!
    1 _satc-release-count +!
    SAUTH-S-OK ;

VARIABLE _satc-factory-context
VARIABLE _satc-factory-status

: _SATC-FAKE-NEW  ( vfs xio-service -- provider status )
    DROP
    DUP 0= IF DROP 0 SAUTH-S-UNAVAILABLE EXIT THEN
    _satc-vfs @ <> IF 0 SAUTH-S-INVALID EXIT THEN
    _SATC-CONTEXT-SIZE ALLOCATE DUP IF
        2DROP 0 SAUTH-S-CAPACITY EXIT
    THEN
    DROP DUP _satc-factory-context ! _SATC-CONTEXT-SIZE 0 FILL
    _SATC-CONTEXT-MAGIC _satc-factory-context @ _satc-c.magic !
    _satc-factory-count @ 1+
        _satc-factory-context @ _satc-c.serial !
    SAUTH-STATE-IDLE _satc-factory-context @ _satc-c.state !
    SAUTH-S-OK _satc-factory-context @ _satc-c.status !
    _SATC-OUTCOME-DELIVERED
        _satc-factory-context @ _satc-c.outcome !
    SAUTH-PROVIDER-SIZE ALLOCATE DUP IF
        2DROP _satc-factory-context @ FREE
        0 _satc-factory-context ! 0 SAUTH-S-CAPACITY EXIT
    THEN
    DROP DUP SAUTH-INIT
    _satc-factory-context @ OVER SAUTH.CONTEXT !
    ['] _satc-fake-account$ OVER SAUTH.ACCOUNT-XT !
    ['] _satc-fake-source-build OVER SAUTH.SOURCE-BUILD-XT !
    ['] _satc-fake-source-supported? OVER SAUTH.SOURCE-SUPPORTED-XT !
    ['] _satc-fake-source@ OVER SAUTH.SOURCE-XT !
    ['] _satc-fake-refresh OVER SAUTH.REFRESH-XT !
    ['] _satc-fake-publish OVER SAUTH.PUBLISH-XT !
    ['] _satc-fake-tick OVER SAUTH.TICK-XT !
    ['] _satc-fake-cancel OVER SAUTH.CANCEL-XT !
    ['] _satc-fake-state@ OVER SAUTH.STATE-XT !
    ['] _satc-fake-status@ OVER SAUTH.LAST-STATUS-XT !
    ['] _satc-fake-error@ OVER SAUTH.ERROR-XT !
    ['] _satc-fake-uri$ OVER SAUTH.URI-XT !
    ['] _satc-fake-cid$ OVER SAUTH.CID-XT !
    ['] _satc-context-releasable? OVER SAUTH.RELEASABLE-XT !
    ['] _satc-fake-release OVER SAUTH.RELEASE-XT !
    DUP SAUTH-SEAL DUP _satc-factory-status !
    SAUTH-S-OK <> IF
        DUP FREE DROP
        _satc-factory-context @ DUP _SATC-CONTEXT-SIZE 0 FILL FREE
        0 _satc-factory-context !
        0 _satc-factory-status @ EXIT
    THEN
    1 _satc-factory-count +! 1 _satc-live-contexts +!
    0 _satc-factory-context ! SAUTH-S-OK ;

\ ---------------------------------------------------------------------
\ App lifecycle helpers
\ ---------------------------------------------------------------------

: _satc-provider  ( -- provider ) _STM-AUTH-PROVIDER @ ;

: _satc-context  ( -- context )
    _satc-provider SAUTH.CONTEXT @ ;

: _satc-app-init  ( -- )
    _satc-app APP.COMP-DESC @ CINST-NEW
    DUP IF NIP THROW THEN DROP DUP _satc-instance !
    ['] _SATC-FAKE-NEW OVER CINST-STATE
        STREAMS-AUTH-FACTORY-STATE! SAUTH-S-OK = _satc-assert
    _satc-app APP.INIT-XT @ EXECUTE ;

: _satc-app-tick  ( -- )
    _satc-instance @ _satc-app APP.TICK-XT @ EXECUTE ;

: _satc-app-shutdown-free  ( -- )
    _satc-instance @ _satc-app APP.SHUTDOWN-XT @ EXECUTE
    _satc-instance @ CINST-FREE 0 _satc-instance ! ;

: _satc-current-provider-source  ( -- source|0 )
    _satc-provider SAUTH-SOURCE@ ;

: _satc-current-source-b  ( -- source|0 )
    1 _STM-SOURCE-REGISTRY STREAMS-SOURCE-NTH ;

: _satc-receipt-empty?  ( -- flag )
    _satc-provider SAUTH-URI$ NIP 0=
    _satc-provider SAUTH-CID$ NIP 0= AND ;

\ ---------------------------------------------------------------------
\ Focused staged contracts
\ ---------------------------------------------------------------------

: _SATC-SETUP  ( -- )
    VFS-CUR _satc-old-vfs !
    1048576 A-XMEM ARENA-NEW DUP 0<>
        ABORT" STREAMS AUTH APPLET arena allocation failed"
    DROP
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
    DUP 0= ABORT" STREAMS AUTH APPLET VFS allocation failed"
    DUP _satc-vfs ! VFS-USE
    S" <uidl><label id=sbar-account text=Unset/></uidl>"
        UIDL-PARSE _satc-assert
    S" sbar-account" UIDL-BY-ID
        DUP 0<> _satc-assert _satc-account-element !
    _STREAMS-COMP-SETUP
    STREAMS-COMP-DESC _satc-app STREAMS-ENTRY-WITH-COMP
    HEAP-FREE-BYTES _satc-instance-heap !
    _satc-app-init
    _STM-AUTH-INIT-STATUS @ SAUTH-S-OK = _satc-assert
    _satc-provider DUP SAUTH-VALID? _satc-assert
    SAUTH-ACCOUNT$ S" @acct-main.test" STR-STR= _satc-assert
    S" @acct-main.test" _satc-account-visible? _satc-assert
    _STM-AUTH-STATE$ S" Authenticated account ready"
        STR-STR= _satc-assert
    _satc-factory-count @ 1 = _satc-assert
    _satc-live-contexts @ 1 = _satc-assert
    _satc-context _satc-c.serial @ 1 = _satc-assert
    _satc-context _satc-c.build-count @ 0= _satc-assert
    _satc-current-provider-source 0= _satc-assert
    _satc-stack ;

VARIABLE _satc-source-a
VARIABLE _satc-source-b

: _SATC-SOURCE  ( -- )
    S" did:plc:alice" _STM-APPLY-AUTH-SOURCE-CREATE
    _STM-SOURCE-REGISTRY STREAMS-SOURCE-COUNT 1 = _satc-assert
    0 _STM-SOURCE-REGISTRY STREAMS-SOURCE-NTH
        DUP _satc-source-a ! SSOURCE.ID _satc-rid-a RID-COPY
    S" did:plc:bob" _STM-APPLY-AUTH-SOURCE-CREATE
    _STM-SOURCE-REGISTRY STREAMS-SOURCE-COUNT 2 = _satc-assert
    1 _STM-SOURCE-REGISTRY STREAMS-SOURCE-NTH
        DUP _satc-source-b ! SSOURCE.ID _satc-rid-b RID-COPY
    _satc-rid-a _satc-rid-b RID= 0= _satc-assert
    _satc-source-b @ DUP STREAMS-SOURCE-VALID? _satc-assert
    DUP SSOURCE.REVISION @ 1 = _satc-assert
    DUP SSOURCE.KIND @ SSOURCE-KIND-ATPROTO-AUTHENTICATED =
        _satc-assert
    DUP SSOURCE.FORMAT @ SSOURCE-FORMAT-ATPROTO-JSON = _satc-assert
    DUP STREAMS-SOURCE-LABEL$ S" Authenticated AT"
        STR-STR= _satc-assert
    DUP STREAMS-SOURCE-ENDPOINT$ S" did:plc:bob"
        STR-STR= _satc-assert
    DUP STREAMS-SOURCE-CONFIG$ S" account=acct-main"
        STR-STR= _satc-assert
    DUP STREAMS-SOURCE-ENDPOINT$ DROP
        OVER SSOURCE.ENDPOINT = _satc-assert
    DUP STREAMS-SOURCE-CONFIG$ DROP
        OVER SSOURCE.CONFIG = _satc-assert
    DROP
    _satc-context _satc-c.build-count @ 2 = _satc-assert
    _STM-SOURCE-SELECTED @ 1 = _satc-assert
    _STM-SOURCE-UI-CANDIDATE STREAMS-SOURCE-SIZE _SSOURCE-ZERO?
        _satc-assert
    _STM-SOURCE-UI-RID RID-SIZE _SSOURCE-ZERO? _satc-assert
    _satc-current-provider-source 0= _satc-assert
    _satc-stack ;

: _SATC-REFRESH  ( -- )
    _STM-SOURCE-REFRESH-ACTION
    _satc-context _satc-c.refresh-count @ 1 = _satc-assert
    _satc-current-provider-source DUP 0<> _satc-assert
    DUP SSOURCE.ID _satc-rid-b RID= _satc-assert
    SSOURCE.REVISION @ 1 = _satc-assert
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-FEED-ACTIVE = _satc-assert
    _satc-app-tick
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-FEED-READY = _satc-assert
    _STM-FEED-READY @ _satc-assert
    _STM-FEED-SOURCE @ _STM-SOURCE-AUTHENTICATED = _satc-assert
    _STM-FEED-CONNECTOR-ID _satc-rid-b RID= _satc-assert
    _STM-FEED-CONNECTOR-REVISION @ 1 = _satc-assert
    _STM-FEED-SEQUENCE @ 1 = _satc-assert
    _STM-ITEM-COUNT 2 = _satc-assert
    0 _STM-ITEM BFM.ITEM.TEXT
        S" Injected fixtures make network behavior reviewable."
        STR-STR= _satc-assert
    _STM-OPEN-TIMELINE
    _STM-VIEW @ _STM-V-TIMELINE = _satc-assert
    24 _STM-DH !
    _STM-VISIBLE-ITEMS 0> _satc-assert
    _STM-FEED-PROVENANCE$
        S" PDS-authenticated / AppView proxy requested"
        STR-STR= _satc-assert
    _satc-stack ;

: _satc-set-outcome  ( outcome -- )
    _satc-context _satc-c.outcome ! ;

: _SATC-PUBLISH  ( -- )
    S" A useful authenticated draft" _STM-DRAFT-OWNER! _satc-assert
    S" A useful authenticated draft" _satc-expected-text-hash SHA3-256-HASH
    _SATC-OUTCOME-DELIVERED _satc-set-outcome
    _STM-PUBLISH-ACTION
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-ACTIVE = _satc-assert
    _STM-AUTH-OP-KIND @ _STM-AUTH-OP-POST = _satc-assert
    _STM-AUTH-PUBLISH-DRAFT-REVISION @ _STM-DRAFT-REV @ = _satc-assert
    _satc-context _satc-c.text-hash
        _satc-expected-text-hash RID= _satc-assert
    S" A locally edited draft" _STM-DRAFT-OWNER! _satc-assert
    _STM-AUTH-PUBLISH-DRAFT-REVISION @ _STM-DRAFT-REV @ < _satc-assert
    _satc-context _satc-c.text-hash
        _satc-expected-text-hash RID= _satc-assert
    _satc-receipt-empty? _satc-assert
    _satc-app-tick
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-DELIVERED = _satc-assert
    _satc-provider SAUTH-URI$
        S" at://did:plc:bob/app.bsky.feed.post/3satcdelivered"
        STR-STR= _satc-assert
    _satc-provider SAUTH-CID$
        S" bafyreig-streams-authenticated-applet"
        STR-STR= _satc-assert
    _STM-AUTH-RESULT-PANEL? _satc-assert
    _satc-app-tick
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-DELIVERED = _satc-assert
    _satc-provider SAUTH-URI$ NIP 0> _satc-assert

    _SATC-OUTCOME-NO-EFFECT _satc-set-outcome
    _STM-PUBLISH-ACTION _satc-receipt-empty? _satc-assert
    _satc-app-tick
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-NO-EFFECT = _satc-assert
    _STM-AUTH-STATE$ S" Not published / no repository effect"
        STR-STR= _satc-assert
    _satc-receipt-empty? _satc-assert
    _STM-AUTH-RESULT-PANEL? _satc-assert

    _SATC-OUTCOME-UNCERTAIN _satc-set-outcome
    _STM-PUBLISH-ACTION _satc-app-tick
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-UNCERTAIN = _satc-assert
    _satc-provider SAUTH-LAST-STATUS@
        SAUTH-S-INDETERMINATE = _satc-assert
    _STM-AUTH-STATE$ S" Publication outcome uncertain"
        STR-STR= _satc-assert
    _satc-receipt-empty? _satc-assert
    _satc-context _satc-c.publish-count @ 3 = _satc-assert
    _satc-stack ;

: _SATC-STALE-START  ( -- )
    _satc-current-source-b DUP _satc-source-b !
    DUP _satc-stale STREAMS-SOURCE-SIZE CMOVE
    _satc-replacement STREAMS-SOURCE-SIZE CMOVE
    1 _STM-SOURCE-SELECTED !
    _STM-SOURCE-REFRESH-ACTION
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-FEED-ACTIVE = _satc-assert
    _satc-context _satc-c.refresh-count @ 2 = _satc-assert
    _satc-stack ;

: _SATC-STALE-MUTATE  ( -- )
    S" Authenticated AT revised" _satc-replacement
        STREAMS-SOURCE-LABEL! SSREG-S-OK = _satc-assert
    _satc-replacement 1 _satc-instance @ STREAMS-SOURCE-REPLACE-OWNER
        STREAMS-SOURCE-S-OK = _satc-assert
    _satc-current-source-b DUP SSOURCE.REVISION @ 2 = _satc-assert
    DROP
    _STM-AUTH-CURRENT-SOURCE 0= _satc-assert
    _satc-app-tick
    _satc-provider SAUTH-STATE@ SAUTH-STATE-FAILED = _satc-assert
    _STM-FEED-CONNECTOR-REVISION @ 1 = _satc-assert
    _STM-FEED-SEQUENCE @ 1 = _satc-assert
    _satc-context _satc-c.refresh-count @
    _STM-REFRESH-ACTION
    _satc-context _satc-c.refresh-count @ = _satc-assert
    _satc-stale _satc-instance @ _satc-provider SAUTH-REFRESH
        SAUTH-S-INVALID = _satc-assert
    _satc-stack ;

: _SATC-STALE-RECOVER  ( -- )
    1 _STM-SOURCE-SELECTED !
    _STM-SOURCE-REFRESH-ACTION
    _satc-context _satc-c.refresh-count @ 3 = _satc-assert
    _satc-current-provider-source SSOURCE.REVISION @ 2 = _satc-assert
    _satc-app-tick
    _STM-FEED-CONNECTOR-REVISION @ 2 = _satc-assert
    _STM-FEED-SEQUENCE @ 2 = _satc-assert
    _STM-ITEM-COUNT 2 = _satc-assert
    _satc-stack ;

: _SATC-POST-RACE  ( -- )
    \ Completion may win a source-revision race after a post was accepted.
    \ The provider must retain that external fact rather than erase its receipt.
    _SATC-OUTCOME-DELIVERED _satc-set-outcome
    _STM-PUBLISH-ACTION
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-ACTIVE = _satc-assert
    _satc-current-source-b _satc-replacement STREAMS-SOURCE-SIZE CMOVE
    S" Authenticated AT post race" _satc-replacement
        STREAMS-SOURCE-LABEL! SSREG-S-OK = _satc-assert
    _satc-replacement 2 _satc-instance @ STREAMS-SOURCE-REPLACE-OWNER
        STREAMS-SOURCE-S-OK = _satc-assert
    _satc-app-tick
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-DELIVERED = _satc-assert
    _satc-provider SAUTH-URI$ NIP 0> _satc-assert
    _STM-AUTH-CURRENT-SOURCE 0= _satc-assert

    \ Rebind intentionally to the new source before the close/cancel contract.
    1 _STM-SOURCE-SELECTED !
    _STM-SOURCE-REFRESH-ACTION _satc-app-tick
    _STM-FEED-CONNECTOR-REVISION @ 3 = _satc-assert
    _STM-FEED-SEQUENCE @ 3 = _satc-assert
    _satc-stack ;

: _SATC-CLOSE  ( -- )
    _SATC-OUTCOME-DELIVERED _satc-set-outcome
    _STM-PUBLISH-ACTION
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-POST-ACTIVE = _satc-assert
    _satc-provider SAUTH-RELEASABLE? 0= _satc-assert
    APP-CLOSE-R-WINDOW _satc-instance @
        _satc-app APP.REQUEST-CLOSE-XT @ EXECUTE
        APP-CLOSE-D-ALLOW = _satc-assert
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-CANCELLED = _satc-assert
    _satc-provider SAUTH-RELEASABLE? _satc-assert
    _satc-context _satc-c.cancel-count @ 1 = _satc-assert
    _satc-receipt-empty? _satc-assert
    _satc-app-shutdown-free
    _satc-live-contexts @ 0= _satc-assert
    _satc-release-count @ 1 = _satc-assert
    HEAP-FREE-BYTES _satc-instance-heap @ = _satc-assert
    _satc-stack ;

: _SATC-RELAUNCH  ( -- )
    _satc-app-init
    _satc-factory-count @ 2 = _satc-assert
    _satc-live-contexts @ 1 = _satc-assert
    _satc-context _satc-c.serial @ 2 = _satc-assert
    _satc-provider SAUTH-STATE@ SAUTH-STATE-IDLE = _satc-assert
    _satc-current-provider-source 0= _satc-assert
    _satc-receipt-empty? _satc-assert
    _STM-FEED-READY @ 0= _satc-assert
    _STM-SOURCE-REGISTRY STREAMS-SOURCE-COUNT 2 = _satc-assert
    _satc-current-source-b SSOURCE.REVISION @ 3 = _satc-assert
    _STM-DRAFT-REV @ 2 = _satc-assert
    _STM-DRAFT-BUF _STM-DRAFT-U @
        S" A locally edited draft" STR-STR= _satc-assert
    S" @acct-main.test" _satc-account-visible? _satc-assert
    1 _STM-SOURCE-SELECTED !
    _STM-SOURCE-REFRESH-ACTION _satc-app-tick
    _satc-provider SAUTH-STATE@
        SAUTH-STATE-FEED-READY = _satc-assert
    _STM-FEED-CONNECTOR-ID _satc-rid-b RID= _satc-assert
    _STM-FEED-CONNECTOR-REVISION @ 3 = _satc-assert
    APP-CLOSE-R-WINDOW _satc-instance @
        _satc-app APP.REQUEST-CLOSE-XT @ EXECUTE
        APP-CLOSE-D-ALLOW = _satc-assert
    _satc-context _satc-c.cancel-count @ 0= _satc-assert
    _satc-app-shutdown-free
    _satc-live-contexts @ 0= _satc-assert
    _satc-release-count @ 2 = _satc-assert
    HEAP-FREE-BYTES _satc-instance-heap @ = _satc-assert
    _satc-stack ;

: _SATC-FINISH  ( -- )
    _satc-live-contexts @ 0= _satc-assert
    _satc-factory-count @ _satc-release-count @ = _satc-assert
    UIDL-RESET
    _satc-old-vfs @ VFS-USE
    _satc-vfs @ VFS-DESTROY 0 _satc-vfs !
    _satc-document-a @ ?DUP IF
        DUP _satc-document-u @ 0 FILL FREE
        0 _satc-document-a ! 0 _satc-document-u !
    THEN
    _satc-stack
    _satc-fails @ 0= IF
        ." STREAMS AUTH APPLET PASS " _satc-checks @ .
    ELSE
        ." STREAMS AUTH APPLET FAIL " _satc-fails @ . ."  / "
            _satc-checks @ .
    THEN CR ;
