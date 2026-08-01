\ =====================================================================
\ streams-online.f - explicit online Streams provider composition
\ =====================================================================
\ The ordinary streams.f entry remains transport-free.  This opt-in edge
\ installs the public Bluesky factory, the configured HTTPS syndication
\ factory, and an optional authenticated provider factory into their distinct
\ instance-state seams, then delegates to the ordinary Streams descriptor
\ construction.
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
VARIABLE _STREAMS-ONLINE-AUTH-FACTORY
VARIABLE _STREAMS-ONLINE-SETUP-SEALED
VARIABLE _STREAMS-ONLINE-NEXT-CONFIGURED
VARIABLE _STREAMS-ONLINE-NEXT-AUTH

-4805 CONSTANT STREAMS-ONLINE-E-FACTORY-CONFLICT

: _STREAMS-ONLINE-STATE-INIT  ( state -- ior )
    DUP ['] STREAMS-BLUESKY-PUBLIC-NEW SWAP
        STREAMS-PUBLIC-FACTORY-STATE!
    ?DUP IF NIP EXIT THEN
    DUP
    _STREAMS-ONLINE-CONFIGURED-FACTORY @ ?DUP 0= IF
        ['] STREAMS-CONFIGURED-SYNDICATION-NEW
    THEN SWAP
        STREAMS-CONFIGURED-FACTORY-STATE!
    ?DUP IF NIP EXIT THEN
    _STREAMS-ONLINE-AUTH-FACTORY @ ?DUP IF
        SWAP STREAMS-AUTH-FACTORY-STATE!
    ELSE
        DROP 0
    THEN ;

CREATE STREAMS-ONLINE-COMP-DESC COMP-DESC ALLOT

: _STREAMS-ONLINE-COMP-TRY-SETUP-WITH-PROVIDERS
  ( configured-factory-xt auth-factory-xt -- ior )
    _STREAMS-ONLINE-NEXT-AUTH !
    DUP 0= IF DROP ['] STREAMS-CONFIGURED-SYNDICATION-NEW THEN
    _STREAMS-ONLINE-NEXT-CONFIGURED !
    _STREAMS-ONLINE-SETUP-SEALED @ IF
        _STREAMS-ONLINE-NEXT-CONFIGURED @
            _STREAMS-ONLINE-CONFIGURED-FACTORY @ =
        _STREAMS-ONLINE-NEXT-AUTH @
            _STREAMS-ONLINE-AUTH-FACTORY @ = AND IF
            0
        ELSE
            STREAMS-ONLINE-E-FACTORY-CONFLICT
        THEN EXIT
    THEN
    _STREAMS-ONLINE-NEXT-CONFIGURED @
        _STREAMS-ONLINE-CONFIGURED-FACTORY !
    _STREAMS-ONLINE-NEXT-AUTH @ _STREAMS-ONLINE-AUTH-FACTORY !
    STREAMS-ONLINE-COMP-DESC STREAMS-COMP-SETUP
    ['] _STREAMS-ONLINE-STATE-INIT
        STREAMS-ONLINE-COMP-DESC COMP.STATE-INIT-XT !
    -1 _STREAMS-ONLINE-SETUP-SEALED ! 0 ;

\ STREAMS-ONLINE-COMP-DESC is a singleton composition descriptor.  Repeating
\ its original setup is harmless; changing either factory after the first
\ setup is rejected before globals or descriptor fields can be mutated.
: STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS
  ( configured-factory-xt auth-factory-xt -- )
    _STREAMS-ONLINE-COMP-TRY-SETUP-WITH-PROVIDERS ?DUP IF THROW THEN ;

: STREAMS-ONLINE-COMP-SETUP-WITH-CONFIGURED  ( configured-factory-xt -- )
    0 STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS ;

: STREAMS-ONLINE-COMP-SETUP  ( -- )
    ['] STREAMS-CONFIGURED-SYNDICATION-NEW 0
        STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS ;

: STREAMS-ONLINE-ENTRY  ( app-desc -- )
    STREAMS-ONLINE-COMP-SETUP
    STREAMS-ONLINE-COMP-DESC SWAP STREAMS-ENTRY-WITH-COMP ;

: STREAMS-ONLINE-ENTRY-WITH-CONFIGURED
  ( configured-factory-xt app-desc -- )
    >R 0 STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS
    STREAMS-ONLINE-COMP-DESC R> STREAMS-ENTRY-WITH-COMP ;

: STREAMS-ONLINE-ENTRY-WITH-PROVIDERS
  ( configured-factory-xt auth-factory-xt app-desc -- )
    >R STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS
    STREAMS-ONLINE-COMP-DESC R> STREAMS-ENTRY-WITH-COMP ;
