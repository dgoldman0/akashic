\ =====================================================================
\ atproto-author-feed-present.f - authenticated AT feed presentation
\ =====================================================================
\ This explicit applet composition edge presents one already-published
\ authenticated author-feed page through the existing Streams Bluesky view.
\ It does not wrap the owner in SPUB, start transport, retain response bytes,
\ or move OAuth/PDS policy into the applet.  The caller must first publish the
\ connector's exact response into a real Streams flow and must present before
\ XIO wipe releases that response.
\
\ The applet performs a second transactional BFM decode from the exact body.
\ That deliberately reuses its established replacement/navigation boundary
\ until a separately checked BFM model-copy admission API exists.
\ =====================================================================

\ Keep the module identity within KDOS's 23-byte bound.
PROVIDED akashic-streams-atview

REQUIRE streams.f
REQUIRE atproto-author-feed-connector.f

0 CONSTANT STREAMS-AT-VIEW-S-OK
1 CONSTANT STREAMS-AT-VIEW-S-INVALID
2 CONSTANT STREAMS-AT-VIEW-S-STATE
3 CONSTANT STREAMS-AT-VIEW-S-PRESENTATION

VARIABLE _SATV-OWNER
VARIABLE _SATV-INSTANCE
VARIABLE _SATV-CONNECTOR
VARIABLE _SATV-EVENT
VARIABLE _SATV-FEED
VARIABLE _SATV-BODY-A
VARIABLE _SATV-BODY-U
VARIABLE _SATV-STATUS

: _SATV-CLEAR  ( -- )
    0 _SATV-OWNER ! 0 _SATV-INSTANCE ! 0 _SATV-CONNECTOR !
    0 _SATV-EVENT ! 0 _SATV-FEED !
    0 _SATV-BODY-A ! 0 _SATV-BODY-U ! 0 _SATV-STATUS ! ;

: _SATV-RETURN  ( status -- status )
    >R _SATV-CLEAR R> ;

: _SATV-STREAMS-INSTANCE?  ( instance -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CINST.ID @ 0> 0= IF DROP 0 EXIT THEN
    DUP CINST.GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    DUP CINST.REVISION @ 0> 0= IF DROP 0 EXIT THEN
    DUP CINST-STATE 0= IF DROP 0 EXIT THEN
    CINST-DESC DUP COMP-DESC-VALID? 0= IF DROP 0 EXIT THEN
    DUP COMP.STATE-SIZE @ _STM-STATE-SIZE <> IF DROP 0 EXIT THEN
    DUP COMP.STATE-FINI-XT @ ['] _STM-STATE-FINI <> IF DROP 0 EXIT THEN
    DUP COMP.ID-A @ SWAP COMP.ID-U @
        S" org.akashic.streams" STR-STR= ;

: _SATV-EVENT-CURRENT?  ( event connector -- flag )
    >R
    DUP STREAMS-EVENT-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    DUP SEVT.MEDIA @ STREAMS-MEDIA-BSKY-FEED-JSON =
    OVER SEVT.DIRECTION @ STREAMS-EVENT-DIRECTION-INGRESS = AND
    OVER SEVT.CONNECTOR-ID R@ SCON.ID RID= AND
    OVER SEVT.CONNECTOR-REVISION @ R@ SCON.REVISION @ = AND
    OVER SEVT.PROTOCOL @ R@ SCON.PROTOCOL @ = AND
    SWAP SEVT.SEQUENCE @ 0> AND
    R> DROP ;

: STREAMS-AT-AUTHOR-FEED-PRESENT
  ( connector-owner instance -- status )
    _SATV-CLEAR
    _SATV-INSTANCE ! _SATV-OWNER !
    _SATV-INSTANCE @ _SATV-STREAMS-INSTANCE? 0= IF
        STREAMS-AT-VIEW-S-INVALID _SATV-RETURN EXIT
    THEN
    _SATV-OWNER @ AT-AUTHOR-FEED-CONNECTOR-VALID? 0= IF
        STREAMS-AT-VIEW-S-INVALID _SATV-RETURN EXIT
    THEN

    _SATV-OWNER @ AT-AUTHOR-FEED-CONNECTOR-CONNECTOR@
    _SATV-STATUS ! _SATV-CONNECTOR !
    _SATV-STATUS @ AT-AUTHOR-FEED-CONNECTOR-S-OK <> IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN
    _SATV-CONNECTOR @ STREAMS-CONNECTOR-VALID? 0= IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN

    _SATV-OWNER @ AT-AUTHOR-FEED-CONNECTOR-EVENT@
    _SATV-STATUS ! _SATV-EVENT !
    _SATV-STATUS @ AT-AUTHOR-FEED-CONNECTOR-S-OK <> IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN
    _SATV-EVENT @ _SATV-CONNECTOR @
        _SATV-EVENT-CURRENT? 0= IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN

    \ FEED@ proves that the same connector owner admitted the response into
    \ its bounded BFM before this applet-facing decode is attempted.
    _SATV-OWNER @ AT-AUTHOR-FEED-CONNECTOR-FEED@
    _SATV-STATUS ! _SATV-FEED !
    _SATV-STATUS @ AT-AUTHOR-FEED-CONNECTOR-S-OK <> IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN
    _SATV-FEED @ 0= IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN

    _SATV-OWNER @ AT-AUTHOR-FEED-CONNECTOR-BODY@
    _SATV-STATUS ! _SATV-BODY-U ! _SATV-BODY-A !
    _SATV-STATUS @ AT-AUTHOR-FEED-CONNECTOR-S-OK <> IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN
    _SATV-BODY-A @ _SATV-BODY-U @
    _SATV-EVENT @ SEVT.PAYLOAD-DIGEST
        SHA3-256-HASH-COMPARE 0= IF
        STREAMS-AT-VIEW-S-STATE _SATV-RETURN EXIT
    THEN

    _SATV-BODY-A @ _SATV-BODY-U @
    _SATV-EVENT @ SEVT.CONNECTOR-ID
    _SATV-EVENT @ SEVT.CONNECTOR-REVISION @
    _SATV-EVENT @ SEVT.SEQUENCE @
    _SATV-INSTANCE @ _STM-LOAD-AUTHOR-FEED-JSON
    BFM-S-OK =
    IF STREAMS-AT-VIEW-S-OK
    ELSE STREAMS-AT-VIEW-S-PRESENTATION THEN
    _SATV-RETURN ;
