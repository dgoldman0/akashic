\ =====================================================================
\  provider-source.f - Owned construction environment for providers
\ =====================================================================
\  A source owns whatever must outlive the providers it constructs, such
\  as a transport, credential container, or local model runtime. Providers
\  expose live behavior; sources expose only construction and lifetime.
\ =====================================================================

PROVIDED akashic-agent-provider-source

REQUIRE provider.f

0 CONSTANT APSOURCE-S-OK
1 CONSTANT APSOURCE-S-INVALID
2 CONSTANT APSOURCE-S-NOMEM
3 CONSTANT APSOURCE-S-UNAVAILABLE

 0 CONSTANT _APS-ID-A
 8 CONSTANT _APS-ID-U
16 CONSTANT _APS-CONTEXT
24 CONSTANT _APS-NEW-XT       \ ( context -- provider status )
32 CONSTANT _APS-FREE-XT      \ ( source -- )
40 CONSTANT _APS-FLAGS
48 CONSTANT AGENT-PROVIDER-SOURCE-SIZE

: APSOURCE.ID-A     ( source -- a ) _APS-ID-A + ;
: APSOURCE.ID-U     ( source -- a ) _APS-ID-U + ;
: APSOURCE.CONTEXT  ( source -- a ) _APS-CONTEXT + ;
: APSOURCE.NEW-XT   ( source -- a ) _APS-NEW-XT + ;
: APSOURCE.FREE-XT  ( source -- a ) _APS-FREE-XT + ;
: APSOURCE.FLAGS    ( source -- a ) _APS-FLAGS + ;

: APSOURCE-INIT  ( source -- )
    AGENT-PROVIDER-SOURCE-SIZE 0 FILL ;

: APSOURCE-PROVIDER-NEW  ( source -- provider status )
    DUP 0= IF DROP 0 APSOURCE-S-INVALID EXIT THEN
    DUP APSOURCE.NEW-XT @ ?DUP 0= IF
        DROP 0 APSOURCE-S-UNAVAILABLE EXIT
    THEN
    >R APSOURCE.CONTEXT @ R> EXECUTE ;

: APSOURCE-FREE  ( source -- )
    DUP 0= IF DROP EXIT THEN
    DUP APSOURCE.FREE-XT @ ?DUP IF EXECUTE ELSE FREE THEN ;
