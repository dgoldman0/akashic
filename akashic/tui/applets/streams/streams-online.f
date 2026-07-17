\ =====================================================================
\ streams-online.f - explicit online Streams provider composition
\ =====================================================================
\ The ordinary streams.f entry remains transport-free.  This opt-in edge
\ installs the public Bluesky factory and the configured HTTPS syndication
\ factory into their distinct instance-state seams, then delegates to the
\ ordinary Streams descriptor construction.
\
\ Dependency direction:
\   streams-online -> bluesky-public -> streams
\                  -> syndication-http
\ No concrete provider is added to streams.f's offline dependency closure.
\ =====================================================================

\ Keep the module identity within KDOS's 23-byte bound.
PROVIDED akashic-streams-online

REQUIRE bluesky-public.f
REQUIRE syndication-http.f

VARIABLE _STREAMS-ONLINE-CONFIGURED-FACTORY

: _STREAMS-ONLINE-STATE-INIT  ( state -- ior )
    DUP ['] STREAMS-BLUESKY-PUBLIC-NEW SWAP
        STREAMS-PUBLIC-FACTORY-STATE!
    ?DUP IF NIP EXIT THEN
    _STREAMS-ONLINE-CONFIGURED-FACTORY @ ?DUP 0= IF
        ['] STREAMS-CONFIGURED-SYNDICATION-NEW
    THEN SWAP
        STREAMS-CONFIGURED-FACTORY-STATE! ;

CREATE STREAMS-ONLINE-COMP-DESC COMP-DESC ALLOT

: STREAMS-ONLINE-COMP-SETUP-WITH-CONFIGURED  ( configured-factory-xt -- )
    DUP 0= IF DROP ['] STREAMS-CONFIGURED-SYNDICATION-NEW THEN
    _STREAMS-ONLINE-CONFIGURED-FACTORY !
    STREAMS-ONLINE-COMP-DESC STREAMS-COMP-SETUP
    ['] _STREAMS-ONLINE-STATE-INIT
        STREAMS-ONLINE-COMP-DESC COMP.STATE-INIT-XT ! ;

: STREAMS-ONLINE-COMP-SETUP  ( -- )
    ['] STREAMS-CONFIGURED-SYNDICATION-NEW
        STREAMS-ONLINE-COMP-SETUP-WITH-CONFIGURED ;

: STREAMS-ONLINE-ENTRY  ( app-desc -- )
    STREAMS-ONLINE-COMP-SETUP
    STREAMS-ONLINE-COMP-DESC SWAP STREAMS-ENTRY-WITH-COMP ;

: STREAMS-ONLINE-ENTRY-WITH-CONFIGURED
  ( configured-factory-xt app-desc -- )
    >R STREAMS-ONLINE-COMP-SETUP-WITH-CONFIGURED
    STREAMS-ONLINE-COMP-DESC R> STREAMS-ENTRY-WITH-COMP ;
